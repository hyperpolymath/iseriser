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
// bqniser library API.
//
// Detect array computation patterns in code and rewrite as optimised
// BQN array primitives. Provides manifest parsing, pattern analysis,
// BQN code generation, and CBQN FFI bridge generation.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{ArrayPattern, ArrayPatternKind, BQNPrimitive, BQNProgram, FFIDeclaration};
pub use manifest::{BqnConfig, Manifest, PatternEntry, SourcePattern, load_manifest, validate};

/// Convenience: load, validate, and generate all artifacts in one call.
///
/// Reads `manifest_path`, validates it, then writes generated BQN,
/// C header, and Zig FFI files into `output_dir`.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
