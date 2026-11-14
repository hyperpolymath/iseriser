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
// ephapaxiser library — Enforce single-use linear type semantics on resources via Ephapax.
//
// This crate provides:
// - Manifest parsing and validation (ephapaxiser.toml)
// - Source code parsing to find resource allocation/deallocation sites
// - Ownership analysis to detect leaks, double-frees, and use-after-free
// - Code generation of Ephapax linear type wrappers
//
// Design note: When Idris2 proofs conflict with Ephapax linear types, Idris2 ALWAYS wins.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{AnalysisResult, LinearResource, OwnershipState, ResourceKind, Violation};
pub use manifest::{Manifest, load_manifest, validate};

/// Convenience function: load manifest, validate, generate wrappers and analysis report.
///
/// # Arguments
/// * `manifest_path` — Path to the ephapaxiser.toml file.
/// * `output_dir` — Directory to write generated files to.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}

/// Convenience function: load manifest, validate, analyse sources for violations.
///
/// # Arguments
/// * `manifest_path` — Path to the ephapaxiser.toml file.
/// * `base_dir` — Base directory for resolving relative source paths.
///
/// # Returns
/// An `AnalysisResult` with detected violations (if any).
pub fn analyse(manifest_path: &str, base_dir: &str) -> anyhow::Result<AnalysisResult> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::analyse_manifest(&m, base_dir)
}
