// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// iseriser library API.
//
// iseriser is the meta-framework that generates new -iser projects
// from language descriptions.  This crate provides:
//   - `manifest` — parsing and validation of iseriser.toml
//   - `abi`      — Rust-side ABI types (LanguageModel, Paradigm, etc.)
//   - `codegen`  — the generation pipeline (parser, scaffold, customizer)

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{
    CompilationTarget, GeneratedFile, GeneratedRepo, LanguageModel, Paradigm, ScaffoldResult,
    TypeSystemFeature,
};
pub use manifest::{load_manifest, parse_manifest, validate, Manifest};

/// Convenience: load a manifest, validate, and generate a complete -iser repo.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<ScaffoldResult> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}
