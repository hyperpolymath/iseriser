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
// futharkiser library API.
//
// Compile annotated array operations to GPU kernels via Futhark. This crate
// exposes the manifest parser, ABI types, and code generator as a library so
// that other tools (e.g. iseriser) can drive futharkiser programmatically.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{CompilationResult, FutharkType, GPUBackend, KernelConfig, SOAC};
pub use manifest::{Manifest, load_manifest, validate};

/// Convenience: load, validate, and generate all Futhark artifacts in one call.
///
/// Reads `manifest_path`, validates all kernel definitions and GPU settings,
/// then writes generated `.fut`, `.h`, and `build.sh` files into `output_dir`.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
