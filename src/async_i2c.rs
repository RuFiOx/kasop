//! Async wrapper for `I2cdev` - runs I2cDevice in a separate thread and forwards
//! requests from async tasks.

use logging::macros::*;

use futures::channel::mpsc;
use futures::channel::oneshot;
use futures::executor::block_on;
use futures::stream::StreamExt;
use async_compat::{futures, tokio};
use tokio::task;

use embedded_hal::blocking::i2c::{Read, Write};
use linux_embedded_hal::I2cdev;

use crate::error::{self, ErrorKind};
use failure::ResultExt;

use std::convert::AsRef;
use std::path::Path;

enum Request {
    Read {
        address: u8,
        num_bytes: usize,
        /// Channel used to send back result
        reply: oneshot::Sender<error::Result<Vec<u8>>>,
    },
    Write {
        address: u8,
        bytes: Vec<u8>,
        /// Channel used to send back result
        reply: oneshot::Sender<error::Result<()>>,
    },
}

/// Server for I2C read/write requests
/// Runs in separate thread.
/// Terminates when all request sender sides are dropped.
fn serve_requests(
    mut i2c_device: I2cdev,
    mut request_rx: mpsc::UnboundedReceiver<Request>,
) -> error::Result<()> {
    while let Some(request) = block_on(request_rx.next()) {
        match request {
            Request::Read {
                address,
                num_bytes,
                reply,
            } => {
                let mut bytes = vec![0; num_bytes];
                let result = i2c_device
                    .read(address, &mut bytes)
                    .with_context(|e| ErrorKind::I2c(e.to_string()))
                    .map(|_| bytes)
                    .map_err(|e| e.into());
                if reply.send(result).is_err() {
                    warn!("AsyncI2c reply send failed - remote side may have ended");
                }
            }
            Request::Write {
                address,
                bytes,
                reply,
            } => {
                let result = i2c_device
                    .write(address, &bytes)
                    .with_context(|e| ErrorKind::I2c(e.to_string()))
                    .map_err(|e| e.into());
                if reply.send(result).is_err() {
                    warn!("AsyncI2c reply send failed - remote side may have ended");
                }
            }
        }
    }
    Ok(())
}

/// Clonable async I2C device. I2cDevice is closed when last sender channel is dropped.
pub struct AsyncI2cDev {
    request_tx: mpsc::UnboundedSender<Request>,
}

/// TODO: Make this into a trait, then implement different backends.
/// TODO: Write tests for this and for power controller (fake async I2C with power controller,
/// check power initialization goes as expected etc., maybe reuse I2C bus from sensors?).
/// TODO: Reuse traits from `i2c/i2c.rs`
impl AsyncI2cDev {
    /// Open I2C device
    /// Although this function is not async, it has to be called from within Tokio context
    /// because it spawns task in a separate thread that serves the (blocking) I2C requests.
    pub fn open<P: AsRef<Path>>(path: P) -> error::Result<Self> {
        let i2c_device = I2cdev::new(path).with_context(|e| ErrorKind::I2c(e.to_string()))?;
        let (request_tx, request_rx) = mpsc::unbounded();

        // Spawn the future in a separate blocking pool (for blocking operations)
        // so that this doesn't block the regular threadpool.
        task::spawn_blocking(move || {
            if let Err(e) = serve_requests(i2c_device, request_rx) {
                error!("{}", e);
            }
        });

        Ok(Self { request_tx })
    }

    pub async fn read(&self, address: u8, num_bytes: usize) -> error::Result<Vec<u8>> {
        let (reply_tx, reply_rx) = oneshot::channel();
        let request = Request::Read {
            address,
            num_bytes,
            reply: reply_tx,
        };
        self.request_tx
            .unbounded_send(request)
            .expect("I2C request failed");
        reply_rx.await.expect("failed to receive I2C reply")
    }

    pub async fn write(&self, address: u8, bytes: Vec<u8>) -> error::Result<()> {
        let (reply_tx, reply_rx) = oneshot::channel();
        let request = Request::Write {
            address,
            bytes,
            reply: reply_tx,
        };
        self.request_tx
            .unbounded_send(request)
            .expect("I2C request failed");
        reply_rx.await.expect("failed to receive I2C reply")
    }
}
