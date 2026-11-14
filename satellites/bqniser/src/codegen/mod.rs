// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation orchestrator for bqniser.
//
// Coordinates three sub-modules:
// - parser: identifies array computation patterns in the manifest
// - bqn_gen: emits .bqn files with the correct BQN primitives
// - ffi_gen: emits a CBQN FFI bridge (C header + Zig implementation)

pub mod bqn_gen;
pub mod ffi_gen;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts from a validated manifest.
///
/// Writes into `output_dir/`:
/// - `<project>.bqn`  — BQN source with all pattern implementations
/// - `bqniser_ffi.h`  — C header for the CBQN FFI bridge
/// - `bqniser_ffi.zig` — Zig FFI implementation calling CBQN
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Step 1: Parse the manifest patterns into ABI-layer ArrayPatterns.
    let program = parser::analyse_manifest(manifest)?;

    // Step 2: Emit the .bqn file.
    let bqn_path = out.join(format!("{}.bqn", program.project_name.replace(' ', "_")));
    let bqn_source = bqn_gen::generate_bqn(&program)?;
    fs::write(&bqn_path, &bqn_source)
        .with_context(|| format!("Failed to write {}", bqn_path.display()))?;
    println!("  [bqn]  {}", bqn_path.display());

    // Step 3: Emit the FFI bridge.
    let header_path = out.join("bqniser_ffi.h");
    let zig_path = out.join("bqniser_ffi.zig");
    let (header_src, zig_src) = ffi_gen::generate_ffi(&program)?;
    fs::write(&header_path, &header_src)
        .with_context(|| format!("Failed to write {}", header_path.display()))?;
    fs::write(&zig_path, &zig_src)
        .with_context(|| format!("Failed to write {}", zig_path.display()))?;
    println!("  [ffi]  {}", header_path.display());
    println!("  [ffi]  {}", zig_path.display());

    Ok(())
}

/// Build generated artifacts by invoking CBQN (placeholder — CBQN must be installed).
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    let name = crate::manifest::effective_name(manifest);
    println!("Building bqniser workload: {}", name);
    println!("  (CBQN compilation not yet wired — run the .bqn file directly with BQN)");
    Ok(())
}

/// Run the workload via CBQN (placeholder — CBQN must be installed).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    let name = crate::manifest::effective_name(manifest);
    println!("Running bqniser workload: {}", name);
    println!("  (CBQN execution not yet wired — run the .bqn file directly with BQN)");
    Ok(())
}
