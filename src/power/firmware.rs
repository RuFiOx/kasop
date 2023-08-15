//! PIC firmware loader

use crate::error::{self, ErrorKind};
use crate::power::{PicAddress, PicWords};
use failure::ResultExt;

use std::convert::AsRef;
use std::fs::File;
use std::path::Path;

use std::io::prelude::*;
use std::io::BufReader;
use std::u32;

/// Parse line with hex number
fn parse_line(line: std::io::Result<String>) -> error::Result<u32> {
    Ok(u32::from_str_radix(&(line?), 16)?)
}

/// Load address and program size are fixed for now
/// Flash offset
const PROGRAM_LOAD_ADDRESS: PicAddress = PicAddress(0x0300);
/// Program size
const PROGRAM_LOAD_END_ADDRESS: PicAddress = PicAddress(0x0f7f);

/// Program to be loaded to PIC of voltage controller
#[derive(Clone)]
pub struct PicProgram {
    pub load_addr: PicAddress,
    pub prog_size: PicWords,
    pub bytes: Vec<u8>,
}

impl PicProgram {
    /// Construct loadable PIC program from bytes
    pub fn from_bytes(bytes: Vec<u8>) -> error::Result<Self> {
        let prog_size = PROGRAM_LOAD_ADDRESS.distance_to(PROGRAM_LOAD_END_ADDRESS);
        if bytes.len() != prog_size.to_bytes() {
            Err(ErrorKind::Power(format!(
                "wrong size of PIC program (expected {:#x}, got {:#x})",
                prog_size.to_bytes(),
                bytes.len()
            )))?
        }
        Ok(Self {
            load_addr: PROGRAM_LOAD_ADDRESS,
            prog_size,
            bytes,
        })
    }

    /// Parse Bitmain .txt firmware format
    pub fn read<P: AsRef<Path>>(path: P) -> error::Result<Self> {
        let path = path.as_ref();
        let f = File::open(path)?;
        let f = BufReader::new(f);
        let mut bytes = Vec::new();
        for (line_no, line) in f.lines().enumerate() {
            let word = parse_line(line).with_context(|_| {
                ErrorKind::Power(format!(
                    "cannot parse PIC program {} on line {}",
                    path.display(),
                    line_no + 1
                ))
            })?;
            bytes.push((word >> 8) as u8);
            bytes.push(word as u8);
        }
        Self::from_bytes(bytes)
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::power;
    use async_compat::tokio;
    use logging::macros::*;
    use std::sync::Arc;

    /// Read program from PIC and verify it's the same as `pic_program`
    async fn verify_program(
        voltage_ctrl: &power::Control,
        pic_program: &PicProgram,
    ) -> error::Result<()> {
        let in_pic = voltage_ctrl
            .read_flash(pic_program.load_addr, pic_program.prog_size)
            .await?;
        assert_eq!(
            in_pic, pic_program.bytes,
            "expected_in_flash={:#x?}, is_in_flash={:#x?}",
            pic_program.bytes, in_pic
        );
        Ok(())
    }

    /// Perform these steps to test we know how to load firmware correctly:
    ///  * load "random bytes" firmware to PIC
    ///  * read back and verify
    ///  * load correct firmware to PIC
    ///  * read back and verify
    ///  * restart, load application, verify version
    ///
    /// This test is disabled by default, because it takes too long (around 2 minutes) and may
    /// wear out the flash if run too often.
    #[tokio::test]
    #[ignore]
    async fn test_pic_reload_program() {
        let voltage_ctrl_backend = Arc::new(power::I2cBackend::new(0));
        let voltage_ctrl = power::Control::new(voltage_ctrl_backend, 8);
        let good_program = power::firmware::PicProgram::read(power::PIC_PROGRAM_PATH)
            .expect("program read failed");

        // Load garbage program
        info!("Loading bad program");
        let mut bad_program = good_program.clone();
        // PIC has 14-bit flash, so avoid setting highest two bits of each word (which is BE u16)
        bad_program.bytes = vec![0x3f, 0xff, 0x2a, 0xaa, 0x15, 0x55]
            .into_iter()
            .cycle()
            .take(bad_program.bytes.len())
            .collect::<Vec<u8>>();
        voltage_ctrl
            .program_pic(&bad_program)
            .await
            .expect("bad program load failed");
        verify_program(&voltage_ctrl, &bad_program)
            .await
            .expect("PIC dump failed");

        // Load good program
        info!("Loading good program");
        voltage_ctrl
            .program_pic(&good_program)
            .await
            .expect("good program load failed");
        verify_program(&voltage_ctrl, &good_program)
            .await
            .expect("PIC dump failed");

        // Boot to application, check version
        info!("Starting application");
        voltage_ctrl.reset().await.expect("reset failed");
        voltage_ctrl
            .jump_from_loader_to_app()
            .await
            .expect("jump to app failed");
        let version = voltage_ctrl
            .get_version()
            .await
            .expect("failed to get version");
        assert_eq!(version, 3);
    }
}
