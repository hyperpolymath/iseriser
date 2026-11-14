#![forbid(unsafe_code)]
#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push,
    clippy::upper_case_acronyms,
    clippy::format_in_format_args,
    clippy::enum_variant_names,
    clippy::module_inception,
    clippy::doc_lazy_continuation,
    clippy::manual_clamp,
    clippy::type_complexity
)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// wokelangiser library crate — public API for consent pattern generation,
// WCAG accessibility compliance checking, and internationalisation extraction.
//
// This module re-exports the core types and functions so that other crates
// can use wokelangiser as a library (e.g. for integration into CI/CD pipelines
// or editor plugins).

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, validate};

/// Run the full wokelangiser generation pipeline:
/// load a manifest, validate it, and generate all output files.
///
/// # Arguments
/// * `manifest_path` - Path to the wokelangiser.toml file
/// * `output_dir` - Directory where generated files will be written
///
/// # Errors
/// Returns an error if the manifest cannot be loaded or validated,
/// or if code generation fails.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
