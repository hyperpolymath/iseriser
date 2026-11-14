#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// tlaiser library API.
//
// Provides programmatic access to tlaiser's state machine extraction
// and TLA+/PlusCal code generation pipeline. Used by the CLI binary
// and available for integration with other -iser tools.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, validate};

/// Convenience: load, validate, and generate all TLA+ artifacts.
///
/// This is the main entry point for programmatic use. It reads a
/// `tlaiser.toml` manifest, validates the state machine definitions,
/// and generates `.tla`, `.pcal`, `.cfg`, and run script files.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
