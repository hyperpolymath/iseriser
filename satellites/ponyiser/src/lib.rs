#![forbid(unsafe_code)]
#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push
)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ponyiser library API.
//
// Provides programmatic access to the ponyiser analysis and code generation
// engine. Use this crate as a library to embed Pony capability analysis
// into your own tooling.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{
    Actor, Behaviour, BehaviourParam, CapabilityViolation, Field, RefCapability, SubtypingResult,
    check_subtype, is_subtype, validate_sendability,
};
pub use codegen::capability::{AnalysisResult, analyse, infer_capability};
pub use manifest::{Manifest, load_manifest, parse_manifest, validate};

/// Convenience: load, validate, and generate all artifacts.
///
/// Reads a ponyiser.toml manifest, validates it, runs capability analysis,
/// and generates .pony source files in the output directory.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
