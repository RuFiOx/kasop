#![cfg_attr(all(test, feature = "bench"), feature(test))]

use std::env::consts::DLL_EXTENSION;
use std::env::current_exe;
use std::error::Error as StdError;
use std::ffi::OsStr;

use clap::{App, FromArgMatches, IntoApp};
use kasop::PluginManager;
use log::{error, info};
use rand::{thread_rng, RngCore};
use std::fs;
use std::sync::atomic::AtomicU16;
use std::sync::Arc;
use std::thread::sleep;
use std::time::Duration;

use crate::cli::Opt;
use crate::client::grpc::KaspadHandler;
use crate::client::stratum::StratumHandler;
use crate::client::Client;
use crate::miner::MinerManager;
use crate::target::Uint256;

mod cli;
mod client;
mod kaspad_messages;
mod miner;
mod pow;
mod target;
mod watch;

pub mod async_i2c;
pub mod counters;
pub mod bm1387;
pub mod error;
pub mod i2c;
pub mod command;
pub mod io;
pub mod gpio;
pub mod power;
pub mod sensor;
pub mod halt;
pub mod monitor;
pub mod fan;

use bm1387::{ChipAddress, MidstateCount};

use embedded_hal::digital::v2::InputPin;
use embedded_hal::digital::v2::OutputPin;

use error::ErrorKind;
use failure::ResultExt;

use futures::channel::mpsc;
use futures::lock::{Mutex, MutexGuard};
use futures::stream::StreamExt;
use async_compat::futures;

/// Timing constants
const INACTIVATE_FROM_CHAIN_DELAY: Duration = Duration::from_millis(100);
/// Base delay quantum during hashboard initialization
const INIT_DELAY: Duration = Duration::from_secs(1);
/// Time to wait between successive hashboard initialization attempts
const ENUM_RETRY_DELAY: Duration = Duration::from_secs(10);
/// How many times to retry the enumeration
const ENUM_RETRY_COUNT: usize = 10;

/// Maximum number of chips is limitted by the fact that there is only 8-bit address field and
/// addresses to the chips need to be assigned with step of 4 (e.g. 0, 4, 8, etc.)
pub const MAX_CHIPS_ON_CHAIN: usize = 64;
/// Number of chips to consider OK for initialization
pub const EXPECTED_CHIPS_ON_CHAIN: usize = 63;

/// Oscillator speed for all chips on S9 hash boards
pub const CHIP_OSC_CLK_HZ: usize = 25_000_000;

/// Exact value of the initial baud rate after reset of the hashing chips.
const INIT_CHIP_BAUD_RATE: usize = 115740;
/// Exact desired target baud rate when hashing at full speed (matches the divisor, too)
const TARGET_CHIP_BAUD_RATE: usize = 1562500;

/// Address of chip with connected temp sensor
const TEMP_CHIP: ChipAddress = ChipAddress::One(61);

/// Timeout for completion of haschain halt
const HALT_TIMEOUT: Duration = Duration::from_secs(30);

/// Core address space size (it should be 114, but the addresses are non-consecutive)
const CORE_ADR_SPACE_SIZE: usize = 128;

/// Power type alias
/// TODO: Implement it as a proper type (not just alias)
pub type Power = usize;

/// Type representing plug pin
#[derive(Clone)]
pub struct PlugPin {
    pin: gpio::PinIn,
}

impl PlugPin {
    pub fn open(gpio_mgr: &gpio::ControlPinManager, hashboard_idx: usize) -> error::Result<Self> {
        Ok(Self {
            pin: gpio_mgr
                .get_pin_in(gpio::PinInName::Plug(hashboard_idx))
                .context(ErrorKind::Hashboard(
                    hashboard_idx,
                    "failed to initialize plug pin".to_string(),
                ))?,
        })
    }

    pub fn hashboard_present(&self) -> error::Result<bool> {
        Ok(self.pin.is_high()?)
    }
}

/// Type representing reset pin
#[derive(Clone)]
pub struct ResetPin {
    pin: gpio::PinOut,
}

impl ResetPin {
    pub fn open(gpio_mgr: &gpio::ControlPinManager, hashboard_idx: usize) -> error::Result<Self> {
        Ok(Self {
            pin: gpio_mgr
                .get_pin_out(gpio::PinOutName::Rst(hashboard_idx))
                .context(ErrorKind::Hashboard(
                    hashboard_idx,
                    "failed to initialize reset pin".to_string(),
                ))?,
        })
    }

    pub fn enter_reset(&mut self) -> error::Result<()> {
        self.pin.set_low()?;
        Ok(())
    }

    pub fn exit_reset(&mut self) -> error::Result<()> {
        self.pin.set_high()?;
        Ok(())
    }
}

/// Hash Chain Controller provides abstraction of the FPGA interface for operating hashing boards.
/// It is the user-space driver for the IP Core
///
/// Main responsibilities:
/// - memory mapping of the FPGA control interface
/// - mining work submission and solution processing
///
/// TODO: disable voltage controller via async `Drop` trait (which doesn't exist yet)
pub struct HashChain {
    /// Number of chips that have been detected
    chip_count: usize,
    /// Eliminates the need to query the IP core about the current number of configured midstates
    midstate_count: MidstateCount,
    /// ASIC difficulty
    asic_difficulty: usize,
    /// ASIC target (matches difficulty)
    asic_target: crate::target::Uint256,
    /// Voltage controller on this hashboard
    voltage_ctrl: Arc<power::Control>,
    /// Pin for resetting the hashboard
    reset_pin: ResetPin,
    hashboard_idx: usize,
    pub command_context: command::Context,
    pub common_io: io::Common,
    work_rx_io: Mutex<Option<io::WorkRx>>,
    work_tx_io: Mutex<Option<io::WorkTx>>,
    monitor_tx: mpsc::UnboundedSender<monitor::Message>,
    /// Do not send open-core work if this is true (some tests that test chip initialization may
    /// want to do this).
    disable_init_work: bool,
    /// channels through which temperature status is sent
    temperature_sender: Mutex<Option<watch::Sender<Option<sensor::Temperature>>>>,
    temperature_receiver: watch::Receiver<Option<sensor::Temperature>>,
    /// nonce counter
    pub counter: Arc<Mutex<counters::HashChain>>,
    /// halter to stop this hashchain
    halt_sender: Arc<halt::Sender>,
    /// we need to keep the halt receiver around, otherwise the "stop-notify" channel closes when chain ends
    #[allow(dead_code)]
    halt_receiver: halt::Receiver,
    /// Current hashchain settings
    frequency: Mutex<FrequencySettings>,
}

const WHITELIST: [&str; 2] = ["libkaspauart", "kaspauart"];

pub mod proto {
    tonic::include_proto!("protowire");
    // include!("protowire.rs"); // FIXME: https://github.com/intellij-rust/intellij-rust/issues/6579
}

pub type Error = Box<dyn StdError + Send + Sync + 'static>;

type Hash = Uint256;

fn filter_plugins(dirname: &str) -> Vec<String> {
    match fs::read_dir(dirname) {
        Ok(readdir) => readdir
            .map(|entry| entry.unwrap().path())
            .filter(|fname| {
                fname.is_file()
                    && fname.extension().is_some()
                    && fname.extension().and_then(OsStr::to_str).unwrap_or_default().starts_with(DLL_EXTENSION)
            })
            .filter(|fname| WHITELIST.iter().any(|lib| *lib == fname.file_stem().and_then(OsStr::to_str).unwrap()))
            .map(|path| path.to_str().unwrap().to_string())
            .collect::<Vec<String>>(),
        _ => Vec::<String>::new(),
    }
}

async fn get_client(
    kaspad_address: String,
    mining_address: String,
    mine_when_not_synced: bool,
    block_template_ctr: Arc<AtomicU16>,
) -> Result<Box<dyn Client + 'static>, Error> {
    if kaspad_address.starts_with("stratum+tcp://") {
        let (_schema, address) = kaspad_address.split_once("://").unwrap();
        Ok(StratumHandler::connect(
            address.to_string().clone(),
            mining_address.clone(),
            mine_when_not_synced,
            Some(block_template_ctr.clone()),
        )
        .await?)
    } else if kaspad_address.starts_with("grpc://") {
        Ok(KaspadHandler::connect(
            kaspad_address.clone(),
            mining_address.clone(),
            mine_when_not_synced,
            Some(block_template_ctr.clone()),
        )
        .await?)
    } else {
        Err("Did not recognize pool/grpc address schema".into())
    }
}

async fn client_main(
    opt: &Opt,
    block_template_ctr: Arc<AtomicU16>,
    plugin_manager: &PluginManager,
) -> Result<(), Error> {
    let mut client = get_client(
        opt.kaspad_address.clone(),
        opt.mining_address.clone(),
        opt.mine_when_not_synced,
        block_template_ctr.clone(),
    )
    .await?;

    if opt.devfund_percent > 0 {
        client.add_devfund(opt.devfund_address.clone(), opt.devfund_percent);
    }
    client.register().await?;
    let mut miner_manager = MinerManager::new(client.get_block_channel(), opt.num_threads, plugin_manager);
    client.listen(&mut miner_manager).await?;
    drop(miner_manager);
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    let mut path = current_exe().unwrap_or_default();
    path.pop(); // Getting the parent directory
    let plugins = filter_plugins(path.to_str().unwrap_or("."));
    let (app, mut plugin_manager): (App, PluginManager) =
        kasop::load_plugins(Opt::into_app().term_width(120), &plugins)?;

    let matches = app.get_matches();

    plugin_manager.process_options(&matches)?;
    let mut opt: Opt = Opt::from_arg_matches(&matches)?;
    opt.process()?;
    env_logger::builder().filter_level(opt.log_level()).parse_default_env().init();
    info!("Found plugins: {:?}", plugins);

    let block_template_ctr = Arc::new(AtomicU16::new((thread_rng().next_u64() % 10_000u64) as u16));
    if opt.devfund_percent > 0 {
        info!(
            "devfund enabled, mining {}.{}% of the time to devfund address: {} ",
            opt.devfund_percent / 100,
            opt.devfund_percent % 100,
            opt.devfund_address
        );
    }
    loop {
        match client_main(&opt, block_template_ctr.clone(), &plugin_manager).await {
            Ok(_) => info!("Client closed gracefully"),
            Err(e) => error!("Client closed with error {:?}", e),
        }
        info!("Client closed, reconnecting");
        sleep(Duration::from_millis(100));
    }
}

type Frequency = usize;

#[derive(Clone)]
pub struct FrequencySettings {
    pub chip: Vec<Frequency>,
}

impl FrequencySettings {
    /// Build frequency settings with all chips having the same frequency
    pub fn from_frequency(frequency: usize) -> Self {
        Self {
            chip: vec![frequency; EXPECTED_CHIPS_ON_CHAIN],
        }
    }

    pub fn set_chip_count(&mut self, chip_count: usize) {
        assert!(self.chip.len() >= chip_count);
        self.chip.resize(chip_count, 0);
    }

    pub fn total(&self) -> u64 {
        self.chip.iter().fold(0, |total_f, &f| total_f + f as u64)
    }

    #[allow(dead_code)]
    pub fn min(&self) -> usize {
        *self.chip.iter().min().expect("BUG: no chips on chain")
    }

    #[allow(dead_code)]
    pub fn max(&self) -> usize {
        *self.chip.iter().max().expect("BUG: no chips on chain")
    }

    pub fn avg(&self) -> usize {
        assert!(self.chip.len() > 0, "BUG: no chips on chain");
        let sum: u64 = self.chip.iter().map(|frequency| *frequency as u64).sum();
        (sum / self.chip.len() as u64) as usize
    }

    fn pretty_frequency(freq: usize) -> String {
        format!("{:.01} MHz", (freq as f32) / 1_000_000.0)
    }
}