//! This module contains interface for reading from sensor (`Sensor`) and what
//! constitutes a sensor reading (`Temperature`, `Measurement`).
//!
//! HOW TO EXTEND THIS IN THE FUTURE
//!
//! * Struct `Temperature` is not very generic and varies from sensor to sensor, so move it into
//!   sensor drivers. Struct `Measurement` is OK for now, it represents more or less the outcomes
//!   of temperature readout.
//!
//! * Each miner has a topology of sensors. It also has to know how to interpret the readout of
//!   each sensor (ie. make a `IntoS9Temperature` trait and then implement
//!   `IntoS9Temperature<TMP451SensorReadout>` and the like).
//!
//! * Maybe provide a generic temperature readout structure that has just the `local` and `remote`
//!   portions (and make a conversion function when needed).

mod tmp42x;
mod tmp451;

use crate::error;
use crate::i2c;

use async_trait::async_trait;
use logging::macros::*;
use lazy_static::lazy_static;
use std::boxed::Box;

/// Generic sensor
#[async_trait]
pub trait Sensor: Sync + Send {
    /// Initialize the sensor (should be called at least once before first call to `read_temperature`
    async fn init(&mut self) -> error::Result<()>;

    /// Read temperature from sensor
    async fn read_temperature(&mut self) -> error::Result<Temperature>;
}

/// Result of measuring temperature with remote sensor
#[derive(Debug, PartialEq, Clone)]
pub enum Measurement {
    /// Sensor not present
    NotPresent,
    /// Reading is invalid (due to under-power etc.)
    InvalidReading,
    /// Sensor broke off
    OpenCircuit,
    /// Sensor is "shorted"
    ShortCircuit,
    /// OK, temperature in degree celsius
    Ok(f32),
}

/// Allow converting measurement into "valid temperature or nothing"
impl From<Measurement> for Option<f32> {
    fn from(m: Measurement) -> Self {
        match m {
            Measurement::Ok(t) => Some(t),
            _ => None,
        }
    }
}

/// Temperature reading
#[derive(Debug, PartialEq, Clone)]
pub struct Temperature {
    /// Local temperature (internal to the sensor) - usually present
    pub local: Measurement,

    /// Remote aka external sensor - may fail or not be present at all
    pub remote: Measurement,
}

lazy_static! {
    /// List of all known I2C address where sensors are present
    static ref SENSOR_I2C_ADDRESS: [i2c::Address; 3] = [
        i2c::Address::new(0x98),
        i2c::Address::new(0x9a),
        i2c::Address::new(0x9c),
    ];
}

pub const INVALID_TEMPERATURE_READING: Temperature = Temperature {
    local: Measurement::InvalidReading,
    remote: Measurement::InvalidReading,
};

/// Probe one I2C address for known sensor
///
/// The reason for not using unified API for driver probing is that the sensor detection logic
/// is pretty much ad-hoc (see for example `lm90` driver in Linux kernel) and would require
/// changes to the "probe API" with each new sensor.
pub async fn probe_i2c_device(
    mut i2c_device: Box<dyn i2c::AsyncDevice>,
) -> error::Result<Option<Box<dyn Sensor>>> {
    // Interesting SMBus registers
    const REG_MANUFACTURER_ID: u8 = 0xfe;
    const REG_DEVICE_ID: u8 = 0xff;

    // Read manufacturer and device ID
    let manufacturer_id = i2c_device.read(REG_MANUFACTURER_ID).await?;
    let device_id = i2c_device.read(REG_DEVICE_ID).await?;

    info!(
        "{:?} manufacturer_id={:#x} device_id={:#x}",
        i2c_device.get_address(),
        manufacturer_id,
        device_id
    );

    // Decide which sensor to use
    let sensor = match manufacturer_id {
        0x55 => match device_id {
            0x21 | 0x22 | 0x23 => Some(tmp42x::TMP42x::new(i2c_device, device_id as usize - 0x20)),
            _ => Some(tmp451::TMP451::new(i2c_device)),
        },
        0x41 => Some(tmp451::ADT7461::new(i2c_device)),
        0x1a => Some(tmp451::NCT218::new(i2c_device)),
        _ => None,
    };

    Ok(sensor)
}

/// Probe for known addresses for supported sensors
pub async fn probe_i2c_sensors<T: 'static + i2c::AsyncBus + Clone>(
    i2c_bus: T,
) -> error::Result<Option<Box<dyn Sensor>>> {
    // Go through all known addresses
    for address in SENSOR_I2C_ADDRESS.iter() {
        // Construct device at given i2c address
        let i2c_device = Box::new(i2c::Device::new(i2c_bus.clone(), *address));

        // Try to probe this device
        match probe_i2c_device(i2c_device).await? {
            // OK, there's one
            sensor @ Some(_) => return Ok(sensor),
            _ => (),
        }
    }

    // No sensors were found
    Ok(None)
}

#[cfg(test)]
mod test {
    use super::*;
    use i2c::test_utils;
    use async_compat::tokio;

    async fn test_probe_address(addr: u8, man_id: u8, dev_id: u8) -> bool {
        let bus = test_utils::FakeI2cBus::new(
            i2c::Address::new(addr),
            &[
                test_utils::InitReg(0xfe, man_id),
                test_utils::InitReg(0xff, dev_id),
            ],
            Some(0),
            Some(0xff),
        );
        let bus = i2c::SharedBus::new(bus);
        let result = probe_i2c_sensors(bus).await.unwrap();
        result.is_some()
    }

    #[tokio::test]
    async fn inner_test_probe_i2c_sensors() {
        assert_eq!(test_probe_address(0x98, 0x55, 0x13).await, true);
        assert_eq!(test_probe_address(0x98, 0x55, 0x21).await, true);
        assert_eq!(test_probe_address(0x9a, 0x41, 0x12).await, true);
        assert_eq!(test_probe_address(0x9c, 0x1a, 0x37).await, true);
        assert_eq!(test_probe_address(0x9c, 0x37, 0x21).await, false);
        assert_eq!(test_probe_address(0x84, 0x55, 0x21).await, false);
    }
}