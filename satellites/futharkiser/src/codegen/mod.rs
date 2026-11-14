// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation orchestrator for futharkiser.
//
// This module coordinates three sub-phases:
//   1. `parser`      — Parse and validate kernel descriptions from the manifest.
//   2. `futhark_gen` — Generate `.fut` source files with SOAC entry points.
//   3. `build_gen`   — Generate build commands and C-ABI header stubs.
//
// The top-level `generate_all` function runs the full pipeline. `build` and
// `run` shell out to the Futhark compiler.

pub mod build_gen;
pub mod futhark_gen;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts from a validated manifest:
///   - One `.fut` file containing all kernel entry points
///   - One C-ABI header file declaring the entry point signatures
///   - One build script with `futhark` compiler invocations
///
/// All files are written into `output_dir`.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Phase 1: Parse kernel configs from raw manifest data.
    let kernels = parser::parse_and_validate(manifest)?;

    // Phase 2: Generate Futhark source.
    let fut_path = out.join(format!("{}.fut", manifest.project.name));
    let fut_source = futhark_gen::generate_futhark_source(manifest, &kernels)?;
    fs::write(&fut_path, &fut_source)
        .with_context(|| format!("Failed to write {}", fut_path.display()))?;
    println!("  [gen] {}", fut_path.display());

    // Phase 3: Generate C-ABI header.
    let header_path = out.join(format!("{}.h", manifest.project.name));
    let header_source = build_gen::generate_c_header(manifest, &kernels)?;
    fs::write(&header_path, &header_source)
        .with_context(|| format!("Failed to write {}", header_path.display()))?;
    println!("  [gen] {}", header_path.display());

    // Phase 4: Generate build script.
    let build_path = out.join("build.sh");
    let build_source = build_gen::generate_build_script(manifest, &fut_path)?;
    fs::write(&build_path, &build_source)
        .with_context(|| format!("Failed to write {}", build_path.display()))?;
    println!("  [gen] {}", build_path.display());

    Ok(())
}

/// Build the generated Futhark artifacts by invoking the Futhark compiler.
/// In Phase 1 this prints the command that *would* be run; actual invocation
/// requires a Futhark installation on the host.
pub fn build(manifest: &Manifest, release: bool) -> Result<()> {
    let backend = &manifest.gpu.backend;
    let mode = if release { "release" } else { "debug" };
    println!(
        "Build {} ({}) — backend={}, tuning={}",
        manifest.project.name, mode, backend, manifest.gpu.tuning
    );
    println!(
        "  Would run: futhark {} {}.fut",
        backend, manifest.project.name
    );
    if manifest.gpu.tuning {
        println!(
            "  Would run: futhark autotune --backend={} {}.fut",
            backend, manifest.project.name
        );
    }
    Ok(())
}

/// Run a compiled Futhark program. In Phase 1 this is a placeholder that
/// prints the invocation that would be executed.
pub fn run(manifest: &Manifest, args: &[String]) -> Result<()> {
    println!(
        "Run {} — backend={}, args={:?}",
        manifest.project.name, manifest.gpu.backend, args
    );
    println!("  Would run: ./{}", manifest.project.name);
    Ok(())
}
