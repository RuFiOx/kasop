//! Nonce and error counters for estimating hashrate
//!
//! Note: `valid` counter is in shares, `errors` are in error event instances (not in shares)

use crate::bm1387;

use std::time::{Duration, Instant};

/// Per-core counters for valid nonces/errors
#[derive(Clone, Copy)]
pub struct Core {
    pub valid: usize,
    pub errors: usize,
}

impl Core {
    pub fn reset(&mut self) {
        self.valid = 0;
        self.errors = 0;
    }

    pub fn new() -> Self {
        Self {
            valid: 0,
            errors: 0,
        }
    }
}

#[derive(Clone, Copy)]
pub struct Chip {
    pub core: [Core; super::CORE_ADR_SPACE_SIZE],
    pub valid: usize,
    pub errors: usize,
}

impl Chip {
    pub fn new() -> Self {
        Self {
            valid: 0,
            errors: 0,
            core: [Core::new(); super::CORE_ADR_SPACE_SIZE],
        }
    }

    pub fn reset(&mut self) {
        self.valid = 0;
        self.errors = 0;
        for core in self.core.iter_mut() {
            core.reset();
        }
    }
}

#[derive(Clone)]
pub struct HashChain {
    pub chip: Vec<Chip>,
    pub valid: usize,
    pub errors: usize,
    pub started: Instant,
    pub stopped: Option<Instant>,
    pub asic_difficulty: usize,
}

impl HashChain {
    pub fn new(chip_count: usize, asic_difficulty: usize) -> Self {
        Self {
            valid: 0,
            errors: 0,
            started: Instant::now(),
            stopped: None,
            chip: vec![Chip::new(); chip_count],
            asic_difficulty,
        }
    }

    pub fn reset(&mut self) {
        self.valid = 0;
        self.errors = 0;
        for chip in self.chip.iter_mut() {
            chip.reset();
        }
        self.started = Instant::now();
    }

    /// Create a snapshot of the current state of counters.
    /// This will set stopped time to current timestamp so that the hashrate will not decay
    /// from this moment on.
    pub fn snapshot(&self) -> Self {
        let mut snapshot = self.clone();
        snapshot.stopped = Some(Instant::now());
        snapshot
    }

    pub fn duration(&self) -> Duration {
        self.stopped
            .unwrap_or_else(|| Instant::now())
            .duration_since(self.started)
    }

    pub fn add_valid(&mut self, addr: bm1387::CoreAddress) {
        if addr.chip >= self.chip.len() {
            // nonce from non-existent chip
            // TODO: what to do?
            return;
        }
        self.valid += self.asic_difficulty;
        self.chip[addr.chip].valid += self.asic_difficulty;
        self.chip[addr.chip].core[addr.core].valid += self.asic_difficulty;
    }

    pub fn add_error(&mut self, addr: bm1387::CoreAddress) {
        if addr.chip >= self.chip.len() {
            // nonce from non-existent chip
            // TODO: what to do?
            return;
        }
        self.errors += 1;
        self.chip[addr.chip].errors += 1;
        self.chip[addr.chip].core[addr.core].errors += 1;
    }

    pub fn set_chip_count(&mut self, chip_count: usize) {
        self.chip.resize(chip_count, Chip::new());
    }

    pub fn chip_count(&self) -> usize {
        self.chip.len()
    }
}