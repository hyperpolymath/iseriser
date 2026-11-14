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
// eclexiaiser library — Add energy, carbon, and resource-cost awareness to
// existing software via Eclexia economics-as-code.
//
// This library provides:
// - ABI types for energy budgets, carbon intensity, and sustainability reports
// - Manifest parsing and validation for `eclexiaiser.toml`
// - Code generation for instrumentation wrappers and Eclexia constraints
// - Sustainability report generation (text, JSON, EU CSRD)

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, parse_manifest, validate};

/// Generate all eclexiaiser artifacts from a manifest file.
///
/// This is the main library entry point. It loads the manifest, validates it,
/// and generates instrumentation code, Eclexia constraints, and a sustainability
/// report in the specified output directory.
///
/// # Arguments
/// - `manifest_path` — Path to `eclexiaiser.toml`
/// - `output_dir` — Directory for generated artifacts
///
/// # Errors
/// Returns an error if the manifest cannot be loaded, fails validation, or
/// if code generation encounters an I/O error.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
