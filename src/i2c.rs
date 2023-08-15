//! Purpose of this module: I2C bus interface defition - AsyncBus and AsyncDevice

#[cfg(test)]
pub mod test_utils;

use async_trait::async_trait;
use std::fmt;
use std::sync::Arc;

use futures::lock::Mutex;
use async_compat::futures;

use crate::error::{self, ErrorKind};

/// Struct representing I2C address
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Address(u8);

impl Address {
    /// Build I2C address from 8-bit hardware address
    pub fn new(address: u8) -> Self {
        assert_eq!(address & 1, 0, "odd 8-bit I2C address");
        Self(address)
    }
    /// Get 8-bit hardware address for write access
    pub fn to_writable_hw_addr(&self) -> u8 {
        self.0 | 1
    }
    /// Get 8-bit hardware address for read access
    pub fn to_readable_hw_addr(&self) -> u8 {
        self.0
    }
}

impl fmt::Display for Address {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:#02x}", self.to_readable_hw_addr())
    }
}

/// `AsyncBus` represents ops on async I2C bus
#[async_trait]
pub trait AsyncBus
where
    Self: Sync + Send,
{
    async fn read(&mut self, addr: Address, reg: u8) -> error::Result<u8>;

    async fn write(&mut self, addr: Address, reg: u8, val: u8) -> error::Result<()>;
}

/// We can make any bus shared by wrapping it in a lock
#[derive(Clone)]
pub struct SharedBus<T> {
    inner: Arc<Mutex<T>>,
}

impl<T> SharedBus<T>
where
    T: AsyncBus,
{
    pub fn new(bus: T) -> Self {
        Self {
            inner: Arc::new(Mutex::new(bus)),
        }
    }
}

#[async_trait]
impl<T> AsyncBus for SharedBus<T>
where
    T: AsyncBus,
{
    async fn read(&mut self, addr: Address, reg: u8) -> error::Result<u8> {
        let mut bus = self.inner.lock().await;
        bus.read(addr, reg).await
    }

    async fn write(&mut self, addr: Address, reg: u8, val: u8) -> error::Result<()> {
        let mut bus = self.inner.lock().await;
        bus.write(addr, reg, val).await
    }
}

/// `AsyncDevice` represents (async) ops on a device on I2C bus
#[async_trait]
pub trait AsyncDevice
where
    Self: Sync + Send,
{
    /// Read register
    async fn read(&mut self, reg: u8) -> error::Result<u8>;

    /// Write register
    async fn write(&mut self, reg: u8, val: u8) -> error::Result<()>;

    /// Write register and immediately read it back to check it was written correctly.
    /// * `reg` - address of register to write
    /// * `reg_read_back` - address of register to read! because it often is that those
    ///   two are different
    /// * `val` - value to write to the register
    async fn write_readback(&mut self, reg: u8, reg_read_back: u8, val: u8) -> error::Result<()>;

    /// Return I2C address of device
    fn get_address(&self) -> Address;
}

/// We can make a `Device` by tying together some kind of bus (T) and I2C address
#[derive(Clone)]
pub struct Device<T> {
    bus: T,
    address: Address,
}

impl<T> Device<T> {
    pub fn new(bus: T, address: Address) -> Self {
        Self { bus, address }
    }
}

/// We can implement async ops on `Device` just by passing down the operation
/// to I2C bus together with I2C address.
#[async_trait]
impl<T> AsyncDevice for Device<T>
where
    T: Clone + AsyncBus,
{
    async fn read(&mut self, reg: u8) -> error::Result<u8> {
        self.bus.read(self.address, reg).await
    }

    async fn write(&mut self, reg: u8, val: u8) -> error::Result<()> {
        self.bus.write(self.address, reg, val).await
    }

    fn get_address(&self) -> Address {
        self.address
    }

    /// TODO: Maybe, just maybe find a better place where to put this function.
    ///
    /// TODO: Maybe make this function a default implementation for `AsyncDevice` trait -
    /// it doesn't currently work because of https://github.com/rust-lang/rust/issues/51443
    /// which is due to `async-trait` conversion.
    async fn write_readback(&mut self, reg: u8, reg_read_back: u8, val: u8) -> error::Result<()> {
        self.write(reg, val).await?;
        let new_val = self.read(reg_read_back).await?;
        if val != new_val {
            Err(ErrorKind::I2cHashchip(format!(
                "failed to read back register {:#x}/{:#x}: written {:#x} but read back {:#x}",
                reg, reg_read_back, val, new_val
            )))?
        }
        Ok(())
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use async_compat::tokio;

    #[test]
    #[should_panic]
    fn test_i2c_address_fail() {
        // odd address is bad
        Address::new(0x31);
    }

    #[test]
    #[should_panic]
    fn test_i2c_address_ok() {
        let addr = Address::new(0x30);
        assert_eq!(addr.to_readable_hw_addr(), 0x30);
        assert_eq!(addr.to_writable_hw_addr(), 0x31);
        let addr = Address::new(0x18);
        assert_eq!(addr.to_readable_hw_addr(), 0x30);
        assert_eq!(addr.to_writable_hw_addr(), 0x31);
    }

    #[tokio::test]
    async fn test_i2c_device_bus() {
        let bus = test_utils::FakeI2cBus::new(Address::new(0x16), &[], Some(0), Some(0x7f));
        let mut dev_bad = Device::new(bus.clone(), Address::new(0x14));
        let mut dev = Device::new(bus, Address::new(0x16));

        dev.write(6, 0x5a).await.unwrap();
        assert_eq!(dev.read(6).await.unwrap(), 0x5a);
        assert_eq!(dev.read(7).await.unwrap(), 0);
        dev.write_readback(8, 8, 0xaa).await.unwrap();
        assert!(dev.write_readback(8, 9, 0xaa).await.is_err());

        assert_eq!(dev_bad.read(6).await.unwrap(), 0x7f);
        assert!(dev_bad.write_readback(8, 8, 0xaa).await.is_err());

        // should return error on reads/writes
        let bus = test_utils::FakeI2cBus::new(Address::new(0x16), &[], Some(0), None);
        let mut dev = Device::new(bus, Address::new(0x14));
        assert!(dev.write_readback(5, 5, 0x10).await.is_err());

        // some registers could be poisoned
        let bus = test_utils::FakeI2cBus::new(
            Address::new(0x16),
            &[test_utils::InitReg(3, 10)],
            None,
            None,
        );
        let mut dev = Device::new(bus, Address::new(0x16));
        assert_eq!(dev.read(3).await.unwrap(), 10);
        assert!(dev.write(3, 11).await.is_ok());
        assert!(dev.read(4).await.is_err());
        assert!(dev.write(4, 5).await.is_err());
    }

    #[tokio::test]
    async fn test_shared_i2c_bus() {
        // FakeI2cBus is not "shared" by default, clone just creates another copy
        // with the same register settings.
        let bus = test_utils::FakeI2cBus::new(Address::new(0x16), &[], Some(0), Some(0x7f));
        // Now we wrap it in a `SharedBus`, getting something we can clone while
        // getting shared backing registers.
        let shared_bus = SharedBus::new(bus);
        let mut dev1 = Device::new(shared_bus.clone(), Address::new(0x16));
        let mut dev2 = Device::new(shared_bus.clone(), Address::new(0x16));

        // writes by one device on the bus ...
        dev1.write(3, 0x11).await.unwrap();
        // ... could be seen by another device on the same bus ...
        assert_eq!(dev2.read(3).await.unwrap(), 0x11);
        // ... and vice versa
        dev2.write(5, 0x22).await.unwrap();
        assert_eq!(dev1.read(5).await.unwrap(), 0x22);
        assert_eq!(dev1.read(4).await.unwrap(), 0x00);
    }
}