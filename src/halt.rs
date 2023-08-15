//! This module provides a way to
//!   * spawn tasks in "termination context"
//!   * terminate that context
//!   * wait for "termination" in normal context, do cleanup, and notify the terminator that we
//!     have completed termination
//!
//! Termination context means that task is run `select`-ed on termination condition, and when
//! that condition is signaled, select returns and the task is dropped.
extern crate async_compat;

use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use crate::error;
use error::ErrorKind;

use futures::channel::mpsc;
use futures::future::{select, Either};
use futures::lock::Mutex;

use async_compat::prelude::*;
use crate::halt::tokio::signal::unix::SignalKind;
use crate::halt::tokio::signal::unix::signal;

/// Token sent by halted task to confirm that halting is done
struct Done;

/// Receiver side of "halt done" confirmation
struct DoneReceiver {
    done_rx: mpsc::UnboundedReceiver<Done>,
}

/// Sender side of "halt done" confirmation
pub struct DoneSender {
    done_tx: mpsc::UnboundedSender<Done>,
}

impl DoneSender {
    /// Confirm halt has been done
    pub fn confirm(self) {
        self.done_tx
            .unbounded_send(Done)
            .expect("halt done send failed");
    }
}

fn make_done_pair() -> (DoneSender, DoneReceiver) {
    let (done_tx, done_rx) = mpsc::unbounded();

    (DoneSender { done_tx }, DoneReceiver { done_rx })
}

/// One (non-clonable) instance of receiver
/// In case the sender ends, the `recv` part of channel receives `None` as EOF
pub struct NotifyReceiver {
    notify_rx: mpsc::UnboundedReceiver<DoneSender>,
}

impl NotifyReceiver {
    /// Wait for notification.
    /// Returning `None` means that the halt-sender dropped out
    pub async fn wait_for_halt(mut self) -> Option<DoneSender> {
        self.notify_rx.next().await
    }

    pub fn spawn_halt_handler<F>(self, f: F)
    where
        F: Future<Output = ()> + 'static + Send,
    {
        tokio::spawn(async move {
            if let Some(done_sender) = self.wait_for_halt().await {
                f.await;
                done_sender.confirm();
            }
        });
    }

    /// Spawn a new task that is dropped when `Halt` is received
    pub fn spawn<F>(self, f: F)
    where
        F: Future<Output = ()> + 'static + Send,
    {
        tokio::spawn(async move {
            match select(f.boxed(), self.wait_for_halt().boxed()).await {
                // in case we received halt notification, reply and exit
                Either::Right((halt_result, _)) => {
                    match halt_result {
                        // confirm we are done (there's no cleanup)
                        Some(done_sender) => done_sender.confirm(),
                        // halt sender was dropped
                        None => (),
                    }
                }
                Either::Left(_) => {
                    // task exited normally, do nothing
                }
            }
        });
    }
}

/// One halt receiver as seen by halt sender
struct NotifySender {
    notify_tx: mpsc::UnboundedSender<DoneSender>,
    name: String,
}

impl NotifySender {
    /// Send a halt notification.
    /// Return value of `None` means that the other side dropped the receiver (which is OK if ie.
    /// the "halted" section exited by itself).
    /// Return of `Some(done)` means the other side received the notification and will report
    /// back via `done` channel.
    pub fn send_halt(&self) -> Option<DoneReceiver> {
        let (done_sender, done_receiver) = make_done_pair();

        if self.notify_tx.unbounded_send(done_sender).is_ok() {
            Some(done_receiver)
        } else {
            None
        }
    }
}

fn make_notify_pair(name: String) -> (NotifySender, NotifyReceiver) {
    let (notify_tx, notify_rx) = mpsc::unbounded();

    (
        NotifySender { notify_tx, name },
        NotifyReceiver { notify_rx },
    )
}

/// Clonable receiver that can register clients for halt notification
/// It's kept separate from `Sender` to split responsibilities.
/// TODO: Receiver seems to have no responsibility except for client registration, consider
///  moving it to Sender...
#[derive(Clone)]
pub struct Receiver {
    sender: Arc<Sender>,
}

impl Receiver {
    pub async fn register_client(&self, name: String) -> NotifyReceiver {
        self.sender.clone().register_client(name).await
    }
}

/// One halt context capable of notifying all of registered `clients`
pub struct Sender {
    clients: Mutex<Vec<NotifySender>>,
    exit_hooks: Mutex<Vec<Pin<Box<dyn Future<Output = ()> + 'static + Send>>>>,
    /// How long to wait for client to finish
    halt_timeout: Duration,
}

impl Sender {
    /// Create new Sender
    fn new(halt_timeout: Duration) -> Arc<Self> {
        Arc::new(Self {
            clients: Mutex::new(Vec::new()),
            halt_timeout,
            exit_hooks: Mutex::new(Vec::new()),
        })
    }

    /// Register one client. Available only through `Receiver` API
    async fn register_client(self: Arc<Self>, name: String) -> NotifyReceiver {
        let (notify_sender, notify_receiver) = make_notify_pair(name);
        self.clients.lock().await.push(notify_sender);
        notify_receiver
    }

    /// Register hook that is to be executed after all futures terminated
    pub async fn add_exit_hook<F>(&self, f: F)
    where
        F: Future<Output = ()> + 'static + Send,
    {
        self.exit_hooks.lock().await.push(Box::pin(f));
    }

    /// Issue halt for all registered client tasks.
    /// Note, that we have to halt tasks one by one instead of halting them at once. If set of
    /// tasks was halted (we send them channel to reply back) and one of them would be dropped
    /// before it had a chance to run (ie. as a result of another task that is being terminated
    /// dropping it in termination handler) it wouldn't respond with "termination successful".
    async fn send_halt_internal(self: Arc<Self>) -> error::Result<()> {
        // take the list of clients
        let mut clients: Vec<_> = self.clients.lock().await.drain(..).collect();

        // notify clients one-by-one
        for client in clients.drain(..) {
            // try to halt them
            let mut done_wait = match client.send_halt() {
                // client has already ended
                None => continue,
                // extract handle, wait on it later
                Some(handle) => handle,
            };
            
            match done_wait.done_rx.next().timeout(self.halt_timeout).await {
                Ok(confirm) => match confirm {
                    Some(_) => (),
                    None => Err(ErrorKind::Halt(format!(
                        "failed to halt client {}: dropped handle",
                        client.name
                    )))?,
                },
                Err(_) => Err(ErrorKind::Halt(format!(
                    "failed to halt client {}: timeout",
                    client.name
                )))?,
            }
        }

        // run exit hooks (in order they came in)
        for hook in self.exit_hooks.lock().await.drain(..) {
            hook.await;
        }
        Ok(())
    }

    /// This is a hack around `halt_sender` having to be run from tokio context, because it spawns
    /// additional threads.
    pub fn hook_termination_signals(self: Arc<Self>) {
        // Hook `SIGINT`, `SIGHUP` and `SIGTERM`
        for signal_type in vec![
            SignalKind::interrupt(),
            SignalKind::hangup(),
            SignalKind::terminate(),
        ] {
            let halt_sender = self.clone();
            tokio::spawn(async move {
                if let Some(_) = signal(signal_type)
                    .expect("BUG: failed hooking signal")
                    .next()
                    .await
                {
                    // Exit after receiving signal
                    // halt_sender.send_halt().await;
                }
            });
        }
    }

    // pub async fn send_halt(self: Arc<Self>) {
    //     let (finish_tx, mut finish_rx) = mpsc::unbounded();
    //     let handle: task::JoinHandle<error::Result<()>> = tokio::spawn(async move {
    //         self.send_halt_internal().await?;
    //         let _result = finish_tx.unbounded_send(());
    //         Ok(())
    //     });
    //     finish_rx.next().await;
    //     handle
    //         .await
    //         .expect("halt task has panicked")
    //         .expect("halt failed");
    // }
}

/// Build a halt sender/receiver pair
pub fn make_pair(halt_timeout: Duration) -> (Arc<Sender>, Receiver) {
    let sender = Sender::new(halt_timeout);
    let receiver = Receiver {
        sender: sender.clone(),
    };

    (sender, receiver)
}
