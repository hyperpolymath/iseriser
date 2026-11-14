#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push
)]
#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// halideiser library API.
//
// Public modules:
//   - abi:      Core types (PipelineStage, HalideOperation, SchedulePrimitive, etc.)
//   - manifest: TOML manifest parsing, validation, and serialization
//   - codegen:  Halide C++ generation, CMake build files, pipeline resolution

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, validate};

/// Convenience: load, validate, and generate all artifacts in one call.
///
/// # Arguments
/// * `manifest_path` — Path to a halideiser.toml file
/// * `output_dir`    — Directory to write generated C++/CMake files into
///
/// # Errors
/// Returns an error if the manifest is invalid or file I/O fails.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
