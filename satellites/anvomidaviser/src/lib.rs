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
#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// anvomidaviser library — Public API for ISU notation parsing, validation,
// and formal program generation. Use this crate as a library to integrate
// ISU figure skating program analysis into other tools.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, validate};

/// Parse, validate, and generate a formal program description from a manifest file.
///
/// This is the high-level entry point for library consumers. It loads the
/// manifest, validates it, and writes generated artifacts to the output directory.
///
/// # Errors
/// Returns an error if the manifest is invalid, elements cannot be parsed,
/// or output files cannot be written.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
