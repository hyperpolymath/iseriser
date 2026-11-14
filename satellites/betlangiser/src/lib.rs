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
// betlangiser library — Public API for ternary probabilistic modelling
// via Betlang code generation.
//
// This crate provides:
// - Manifest parsing and validation for betlangiser.toml files
// - ABI types: Distribution, TernaryBool (Kleene algebra), ConfidenceInterval
// - Code generation: Betlang source with distribution declarations,
//   propagation rules, and ternary logic helpers

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{ConfidenceInterval, Distribution, SimulationConfig, SimulationResult, TernaryBool};
pub use manifest::{Manifest, load_manifest, validate};

/// High-level API: load a manifest, validate it, and generate Betlang code.
///
/// This is the primary entry point for programmatic use of betlangiser.
/// For CLI usage, see `betlangiser --help`.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
