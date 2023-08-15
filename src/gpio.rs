use embedded_hal;
use sysfs_gpio;

/// Helper struct for altering output pins which implements OutputPin trait
#[derive(Clone)]
pub struct PinOut(sysfs_gpio::Pin);

impl embedded_hal::digital::v2::OutputPin for PinOut {
    type Error = sysfs_gpio::Error;

    fn set_low(&mut self) -> Result<(), Self::Error> {
        self.0.set_value(0)
    }

    fn set_high(&mut self) -> Result<(), Self::Error> {
        self.0.set_value(1)
    }
}

/// Helper struct for reading input pins which implements InputPin trait
#[derive(Clone)]
pub struct PinIn(sysfs_gpio::Pin);

impl embedded_hal::digital::v2::InputPin for PinIn {
    type Error = sysfs_gpio::Error;

    fn is_high(&self) -> Result<bool, Self::Error> {
        self.0.get_value().map(|value| value > 0)
    }

    fn is_low(&self) -> Result<bool, Self::Error> {
        self.0.get_value().map(|value| value == 0)
    }
}

/// All known output pin types on S9
#[derive(Debug)]
pub enum PinOutName {
    LEDFrontRed,
    LEDFrontGreen,
    Buzzer,
    Rst(usize),
}

/// All known input pin types on S9
#[derive(Debug, Copy, Clone)]
pub enum PinInName {
    ResetButton,
    IPSelect,
    Plug(usize),
}

/// Provides functionality for configuring specific S9 control pins
/// The pins can be accessed by name (see PinOutName and PinInName)
pub struct ControlPinManager;

impl ControlPinManager {
    pub fn new() -> Self {
        ControlPinManager {}
    }

    /// Returns a specified output pin and initializes it (export in sysfs)
    pub fn get_pin_out(&self, pin_name: PinOutName) -> Result<PinOut, sysfs_gpio::Error> {
        let pin_num = match pin_name {
            PinOutName::LEDFrontRed => 943,
            PinOutName::LEDFrontGreen => 944,
            PinOutName::Buzzer => 945,
            PinOutName::Rst(i) => {
                assert!(i > 0 && i <= 8, "Rst pin {} is out of range", i);
                888 + (i - 1)
            }
        };

        let pin = sysfs_gpio::Pin::new(pin_num as u64);
        pin.export()?;
        pin.set_direction(sysfs_gpio::Direction::Out)?;
        Ok(PinOut(pin))
    }

    /// Returns a specified input pin and initializes it (export in sysfs)
    pub fn get_pin_in(&self, pin_name: PinInName) -> Result<PinIn, sysfs_gpio::Error> {
        let pin_num: usize = match pin_name {
            PinInName::ResetButton => 953,
            PinInName::IPSelect => 957,
            PinInName::Plug(i) => {
                assert!(i > 0 && i <= 8, "Plug pin {} is out of range", i);
                897 + (i - 1)
            }
        };

        let pin = sysfs_gpio::Pin::new(pin_num as u64);
        pin.export()?;
        pin.set_direction(sysfs_gpio::Direction::In)?;
        Ok(PinIn(pin))
    }
}

// NOTE: all unit tests below have to be run sequentially as each of them instantiates its own
// ControlPinManager. However, since all pin accessing methods attempt to perform gpio pin
// export, there is a race condition that causes one of the exports to fail.
#[cfg(test)]
mod test {
    use super::*;
    use embedded_hal::digital::v2::InputPin;

    #[test]
    fn test_get_pin_in_check_plug_pin_that_exists() {
        let ctrl_pin_manager = ControlPinManager::new();
        for i in 1..9 {
            let pin_in = ctrl_pin_manager.get_pin_in(PinInName::Plug(i));
            match pin_in {
                Ok(_) => (),
                Err(err) => assert!(false, "Failed to detect plugin pin {} {}", i, err),
            }
        }
    }

    /// Verify non existing
    #[test]
    #[should_panic]
    fn test_get_pin_in_check_plug_pin_doesnt_exist() {
        let ctrl_pin_manager = ControlPinManager::new();
        for i in [0usize, 10].iter() {
            let _pin_in = ctrl_pin_manager.get_pin_in(PinInName::Plug(*i));
        }
    }

    #[test]
    fn test_get_pin_in_verify_default_values() {
        let ctrl_pin_manager = ControlPinManager::new();
        for p in [PinInName::ResetButton, PinInName::IPSelect].iter() {
            if let Ok(pin_in) = ctrl_pin_manager.get_pin_in(*p) {
                assert!(
                    pin_in.is_high().unwrap(),
                    "Unexpected value for pin: {:?}",
                    p
                );
            }
        }
    }

    #[test]
    #[ignore]
    fn test_get_pin_in_verify_default_rst_values() {
        let ctrl_pin_manager = ControlPinManager::new();
        for i in 1..9 {
            let plug_name = PinInName::Plug(i);
            match ctrl_pin_manager.get_pin_in(plug_name) {
                Ok(plug_pin) => assert!(
                    !plug_pin.is_high().unwrap(),
                    "Unexpected value for pin: {:?}",
                    plug_name
                ),
                Err(e) => assert!(false, "Failed to get plug pin {}", e),
            }
        }
    }
}