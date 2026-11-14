#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// nimiser library API.
// Public modules for manifest parsing, ABI types, and code generation.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, validate};

/// Convenience: load, validate, and generate all artifacts in one call.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
