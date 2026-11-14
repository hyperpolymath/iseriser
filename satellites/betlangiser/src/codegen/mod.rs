// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen module for betlangiser — Orchestrates Betlang code generation
// from parsed manifests. Delegates to submodules for parsing, distribution
// metadata, and actual code emission.

pub mod codegen;
pub mod distribution;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all Betlang output artefacts from a validated manifest.
///
/// Creates the output directory and writes the generated Betlang source
/// file containing distribution declarations, propagation rules,
/// ternary logic helpers, and the simulation entry point.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("Failed to create output directory: {}", output_dir))?;

    // Generate the main Betlang source file.
    let betlang_code = codegen::generate_betlang_code(manifest)
        .map_err(|e| anyhow::anyhow!("Code generation failed: {}", e))?;

    let output_path =
        Path::new(output_dir).join(format!("{}.bet", manifest.project.name.replace('-', "_")));

    fs::write(&output_path, &betlang_code).with_context(|| {
        format!(
            "Failed to write generated code to {}",
            output_path.display()
        )
    })?;

    println!(
        "Generated Betlang code: {} ({} bytes)",
        output_path.display(),
        betlang_code.len()
    );

    Ok(())
}

/// Build the generated artefacts (placeholder — delegates to Betlang toolchain).
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!(
        "Building betlangiser workload: {} (Betlang compilation not yet wired)",
        manifest.project.name
    );
    Ok(())
}

/// Run the generated simulation (placeholder — delegates to Betlang runtime).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!(
        "Running betlangiser workload: {} (Betlang runtime not yet wired)",
        manifest.project.name
    );
    Ok(())
}
