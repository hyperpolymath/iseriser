#![forbid(unsafe_code)]
#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push
)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Chapeliser library API.
// This crate can be used as both a CLI tool (`chapeliser` binary) and as a library
// dependency. Other Rust projects can call `chapeliser::generate()` to Chapelise
// their workloads programmatically — keeping all Chapel/Zig/FFI scaffolding in
// Chapeliser's repo, not in the consumer's repo.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, validate};

/// Convenience function: load manifest, validate, and generate all artifacts.
/// This is the library entry point for programmatic use.
///
/// # Example
///
/// ```rust,no_run
/// chapeliser::generate("chapeliser.toml", "generated/chapeliser").unwrap();
/// ```
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
