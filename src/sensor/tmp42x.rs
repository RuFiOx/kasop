//! Driver implementation of sensor driver for TMP42x and similar sensors

use crate::error;
use crate::i2c;
use crate::sensor::{self, Measurement, Temperature};

use packed_struct::prelude::*;
use packed_struct_codegen::PackedStruct;

use async_trait::async_trait;
use std::boxed::Box;

/// both `HIGH` and `LOW` byte are four registers for each of the temperatures:
/// local, remote1, remote2, remote3
const REG_TEMP_HIGH_BASE: u8 = 0x00;
const REG_TEMP_LOW_BASE: u8 = 0x10;
const REG_CONFIG_1: u8 = 0x09;
const REG_CONFIG_2: u8 = 0x0a;

#[derive(PackedStruct, Clone, Debug, PartialEq)]
#[packed_struct(bit_numbering = "lsb0", size_bytes = "1")]
pub struct RegConfig1 {
    #[packed_field(bits = "6")]
    pub shutdown: bool,
    #[packed_field(bits = "2")]
    pub extended_range: bool,
}

#[derive(PackedStruct, Clone, Debug, PartialEq)]
#[packed_struct(bit_numbering = "lsb0", size_bytes = "1")]
pub struct RegConfig2 {
    #[packed_field(bits = "6")]
    pub remote_3_enable: bool,
    #[packed_field(bits = "5")]
    pub remote_2_enable: bool,
    #[packed_field(bits = "4")]
    pub remote_1_enable: bool,
    #[packed_field(bits = "3")]
    pub local_enable: bool,
    #[packed_field(bits = "2")]
    pub resistance_correction: bool,
}

#[derive(PackedStruct, Clone, Debug, PartialEq)]
#[packed_struct(bit_numbering = "lsb0", size_bytes = "1")]
pub struct RegTempLowByte {
    #[packed_field(bits = "7:4")]
    pub fract: u8,
    #[packed_field(bits = "1")]
    pub temp_invalid: bool,
    #[packed_field(bits = "0")]
    pub open_circuit: bool,
}

/// TMP421/422/423 driver
pub struct TMP42x {
    i2c_device: Box<dyn i2c::AsyncDevice>,
    /// We intend to support chips with multiple remote temperature sensors in the future.
    /// This registers defines how many remote sensors we are connected to.
    #[allow(dead_code)]
    num_remote_sensors: usize,
    /// If `Some`: if local temperature high-byte reg is this value, then discard the reading.
    /// This is used to discard the first reading after changing register format to extended mode.
    discard_readings: Option<u8>,
}

impl TMP42x {
    pub fn new(
        i2c_device: Box<dyn i2c::AsyncDevice>,
        num_remote_sensors: usize,
    ) -> Box<dyn sensor::Sensor> {
        // TODO: If you are fixing this, you need to figure out sensor topology on hashboard
        assert_eq!(num_remote_sensors, 1);
        Box::new(Self {
            i2c_device,
            num_remote_sensors,
            discard_readings: None,
        }) as Box<dyn sensor::Sensor>
    }

    /// Read temperature from one sensor, `index` determines which one:
    /// `*` 0 is local temperature
    /// `*` 1..3 are for remote temperature
    ///
    /// Each sensor is represented by a pair of registers containing high-byte/low-byte of the
    /// temperature.
    pub async fn read_one_sensor(&mut self, index: usize) -> error::Result<Measurement> {
        assert!(index <= 3);
        let high = self
            .i2c_device
            .read(REG_TEMP_HIGH_BASE + index as u8)
            .await?;
        let low = self
            .i2c_device
            .read(REG_TEMP_LOW_BASE + index as u8)
            .await?;
        let low_bits = RegTempLowByte::unpack(&[low]).expect("LowByte unpacking failed");

        let result = if low_bits.temp_invalid {
            Measurement::InvalidReading
        } else if low_bits.open_circuit {
            Measurement::OpenCircuit
        } else if high == 0 {
            Measurement::ShortCircuit
        } else {
            let t = (high as f32 - 64.0) + (low_bits.fract as f32 / 16.0);
            Measurement::Ok(t)
        };

        Ok(result)
    }
}

#[async_trait]
impl sensor::Sensor for TMP42x {
    /// Initialize temperature sensor - enable ext. range and all sensors
    async fn init(&mut self) -> error::Result<()> {
        // Eh, when setting the `RANGE` bit to 1, the change in temperature register format
        // isn't reflected until after the next ADC conversion finishes!
        // Let's remember the initial temperature and discard all temperature readings until
        // this value changes (we assume the temperature wouldn't change by 0x40 between two
        // readings).
        self.discard_readings = Some(self.i2c_device.read(REG_TEMP_HIGH_BASE).await?);

        // Set extended range
        let config1 = RegConfig1 {
            shutdown: false,
            extended_range: true,
        };
        self.i2c_device
            .write_readback(REG_CONFIG_1, REG_CONFIG_1, config1.pack()[0])
            .await?;

        // Enable sensors
        // TODO: enable remote sensors 2 and 3 for tmp422 and tmp423
        let config2 = RegConfig2 {
            remote_3_enable: false,
            remote_2_enable: false,
            remote_1_enable: true,
            local_enable: true,
            resistance_correction: true,
        };
        self.i2c_device
            .write_readback(REG_CONFIG_2, REG_CONFIG_2, config2.pack()[0])
            .await?;

        Ok(())
    }

    /// Do a temperature reading from all supported sensors
    async fn read_temperature(&mut self) -> error::Result<Temperature> {
        // Mechanism to invalidate readings until "extended mode" is reflected in temp register
        match self.discard_readings {
            Some(bad_value) => {
                // Check if local temperature changed
                let local_high_byte = self.i2c_device.read(REG_TEMP_HIGH_BASE).await?;
                if local_high_byte == bad_value {
                    // Still bad value, invalidate reading
                    return Ok(Temperature {
                        local: Measurement::InvalidReading,
                        remote: Measurement::InvalidReading,
                    });
                }
                // OK, all readings are valid from now on
                self.discard_readings = None;
            }
            _ => (),
        }

        // Check local & remote sensors
        let local = self.read_one_sensor(0).await?;
        let remote = self.read_one_sensor(1).await?;

        Ok(Temperature { local, remote })
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_tmp42x_regs() {
        let config1 = RegConfig1 {
            shutdown: true,
            extended_range: true,
        };
        assert_eq!(config1.pack(), [0x44]);

        let config2 = RegConfig2 {
            remote_3_enable: true,
            remote_2_enable: false,
            remote_1_enable: true,
            local_enable: true,
            resistance_correction: true,
        };
        assert_eq!(config2.pack(), [0x5c]);

        let low_byte = RegTempLowByte {
            fract: 0xd,
            temp_invalid: false,
            open_circuit: true,
        };
        assert_eq!(low_byte.pack(), [0xd1]);
        assert_eq!(
            RegTempLowByte::unpack(&[0xd1]).expect("unpacking failed"),
            low_byte
        );
    }

    // TODO: write more tests
}
