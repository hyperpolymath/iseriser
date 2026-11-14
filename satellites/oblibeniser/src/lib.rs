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
// oblibeniser library — Make operations reversible and auditable via Oblíbený.
//
// This crate provides:
//   - `abi`: Core types (ReversibleOperation, InverseStrategy, AuditEntry, UndoStack, TimeTravel)
//   - `manifest`: TOML manifest parsing and validation
//   - `codegen`: Code generation for inverse functions and audit trails

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{Manifest, load_manifest, parse_manifest, validate};

/// Convenience function: load a manifest, validate it, and generate all artifacts.
/// This is the primary library entry point for programmatic use.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
