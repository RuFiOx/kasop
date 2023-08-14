// Copyright (C) 2019  Braiins Systems s.r.o.
//
// This file is part of Braiins Open-Source Initiative (BOSI).
//
// BOSI is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
// Please, keep in mind that we may also license BOSI or any part thereof
// under a proprietary license. For more information on the terms and conditions
// of such proprietary license or if you have any other questions, please
// contact us at opensource@braiins.com.

use std::env;
use std::error::Error;
use std::fs;
use std::path::Path;
use std::process::Command;

// source dir. will be removed and recreated with generated source files
const SRC_DIR: &'static str = "src";

pub fn run(input_path: String) -> std::io::Result<()> {
    let current_dir = env::current_dir()?;

    // clear up existing src/
    if Path::new(SRC_DIR).is_dir() {
        fs::remove_dir_all(SRC_DIR).map_err(|err| {
            std::io::Error::new(
                err.kind(),
                format!("removing {}: {}", SRC_DIR, err.description()),
            )
        })?;
    }

    fs::create_dir(SRC_DIR).map_err(|err| {
        std::io::Error::new(
            err.kind(),
            format!("recreating {}: {}", SRC_DIR, err.description()),
        )
    })?;

    // create code as single line blob
    let input = fs::read_to_string(&input_path).map_err(|err| {
        std::io::Error::new(
            err.kind(),
            format!("reading {}: {}", input_path, err.description()),
        )
    })?;

    // NOTE: svd2rust panics on most failures anyways
    let out = svd2rust::generate(input.as_str(), svd2rust::Target::None, false).map_err(|err| {
        std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("generating code from {}: {:?}", input_path, err),
        )
    })?;

    // split code blob to files
    form::create_directory_structure(Path::new(&current_dir).join(SRC_DIR), out.lib_rs).map_err(
        |err| {
            std::io::Error::new(
                std::io::ErrorKind::Other,
                format!("formating code in {}: {}", SRC_DIR, err),
            )
        },
    )?;

    // reformat
    let out = Command::new("rustfmt")
        .arg(Path::new(&current_dir).join(SRC_DIR).join("lib.rs"))
        .status()
        .map_err(|err| {
            std::io::Error::new(
                std::io::ErrorKind::Other,
                format!("reformating files in {}: {}", SRC_DIR, err),
            )
        })?;

    if !out.success() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "rustfmt failed",
        ));
    }

    // rebuild lib.rs only if fpga-io.xml is changed
    print!("cargo:rerun-if-changed={}", input_path);
    Ok(())
}
