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
// mylangiser library — progressive-disclosure interface generation from
// complex APIs via My-Lang. This crate provides:
//
// - `manifest` — Parse and validate mylangiser.toml manifests
// - `codegen`  — Score complexity, assign levels, generate layered wrappers
// - `abi`      — Core type definitions (DisclosureLevel, ComplexityScore, etc.)

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{APIEndpoint, ComplexityScore, DisclosureLevel, LayeredWrapper, SmartDefault};
pub use manifest::{Manifest, load_manifest, validate};

/// Convenience function: load a manifest, validate it, and generate all
/// layered wrapper code in the specified output directory.
///
/// # Errors
/// Returns an error if the manifest is invalid or file I/O fails.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
