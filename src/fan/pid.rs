//! Implementation of fan control using PID

mod offset_pid;

use super::Speed;
use offset_pid::OffsetPIDController;
use pid_control::Controller;
use std::time::Instant;

pub struct TempControl {
    pid: OffsetPIDController,
    last_update: Instant,
}

impl TempControl {
    pub fn new() -> Self {
        // kp/ki/kd constants are negative because the PID works in reverse direction
        // (the lower the PWM, the higher the temperature)
        let pid = OffsetPIDController::new(-5.0, -0.03, -0.15, 70.0);

        let mut temp_control = Self {
            pid,
            last_update: Instant::now(),
        };
        temp_control.set_warm_up_limits();
        return temp_control;
    }

    /// set fan limits when warming up
    pub fn set_warm_up_limits(&mut self) {
        self.pid.set_limits(60.0, 100.0);
    }

    /// set fan limits when in operation
    pub fn set_normal_limits(&mut self) {
        self.pid.set_limits(1.0, 100.0);
    }

    pub fn set_target(&mut self, target: f64) {
        self.pid.set_target(target);
    }

    pub fn update(&mut self, temperature: f64) -> Speed {
        let pwm = self
            .pid
            .update(temperature, self.last_update.elapsed().as_secs_f64());
        self.last_update = Instant::now();
        Speed::new(pwm as usize)
    }
}
