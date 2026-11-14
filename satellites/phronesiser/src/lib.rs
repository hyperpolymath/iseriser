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
// phronesiser library — public API for embedding Phronesis ethical constraint
// evaluation into Rust applications.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{AgentAction, AuditDecision, Constraint, DeonticModality, EvaluationResult};
pub use codegen::audit::AuditTrail;
pub use codegen::engine::ConstraintEngine;
pub use codegen::parser::{ParsedConstraintSet, parse_constraints};
pub use manifest::{Manifest, load_manifest, validate};

/// Convenience function: load, validate, and generate constraint artifacts.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)
}

/// Convenience function: load a manifest and build a ready-to-use constraint engine.
pub fn build_engine(manifest_path: &str) -> anyhow::Result<ConstraintEngine> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    let parsed = parse_constraints(&m)?;
    Ok(ConstraintEngine::new(
        parsed.constraints,
        m.enforcement.mode.clone(),
        m.enforcement.escalation_threshold,
    ))
}
