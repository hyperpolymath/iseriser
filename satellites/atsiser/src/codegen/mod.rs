// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation pipeline for atsiser.
//
// This module orchestrates the three-stage pipeline:
// 1. parser.rs  — Parse C headers to extract function signatures and memory patterns
// 2. ats_gen.rs — Generate ATS2 viewtype wrappers from parsed C signatures
// 3. compiler.rs — Drive ATS2 compilation (patsopt -> patscc -> C binary)

pub mod ats_gen;
pub mod compiler;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all ATS2 artifacts from a validated manifest.
///
/// This is the main entry point for the code generation pipeline:
/// 1. Parse each C source file listed in the manifest
/// 2. Match parsed functions against ownership rules
/// 3. Generate ATS2 viewtype definitions and wrapper functions
/// 4. Write `.sats` (signatures) and `.dats` (implementations) files
///
/// # Arguments
///
/// * `manifest` — A validated atsiser manifest
/// * `output_dir` — Directory where generated files will be written
///
/// # Errors
///
/// Returns an error if C parsing fails, ownership rules are inconsistent,
/// or the output directory cannot be created/written.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Stage 1: Parse all C sources
    let mut all_signatures = Vec::new();
    for source in &manifest.c_sources {
        let source_path = Path::new(&source.path);
        if source_path.exists() {
            let sigs = parser::parse_c_header(&source.path)
                .with_context(|| format!("Failed to parse C source: {}", source.path))?;
            all_signatures.extend(sigs);
        } else {
            // If the file does not exist, try to parse from ownership rules alone
            println!(
                "  [note] C source '{}' not found on disk; generating from ownership rules only",
                source.path
            );
        }
    }

    // Stage 2: Generate ATS2 module from signatures + ownership rules
    let module = ats_gen::generate_module(
        &manifest.project.name,
        &all_signatures,
        &manifest.ownership_rules,
        &manifest.c_sources,
    )?;

    // Stage 3: Write output files
    let sats_path = out.join(format!("{}_safe.sats", manifest.project.name));
    let dats_path = out.join(format!("{}_safe.dats", manifest.project.name));

    let (sats_content, dats_content) = ats_gen::render_module(&module)?;

    fs::write(&sats_path, &sats_content)
        .with_context(|| format!("Failed to write {}", sats_path.display()))?;
    fs::write(&dats_path, &dats_content)
        .with_context(|| format!("Failed to write {}", dats_path.display()))?;

    println!("  [ok] Generated {}", sats_path.display());
    println!("  [ok] Generated {}", dats_path.display());

    Ok(())
}

/// Build the generated ATS2 artifacts into a C library.
///
/// Invokes the ATS2 compiler (patsopt/patscc) to type-check and compile the
/// generated wrapper code. If type-checking succeeds, the generated C code is
/// compiled with the system C compiler.
///
/// # Arguments
///
/// * `manifest` — A validated atsiser manifest
/// * `release` — If true, enable optimisations (-O2)
pub fn build(manifest: &Manifest, release: bool) -> Result<()> {
    println!("Building atsiser project: {}", manifest.project.name);

    let output_dir = &manifest.project.output_dir;
    let dats_file = format!("{}/{}_safe.dats", output_dir, manifest.project.name);

    let cmd = compiler::build_command(manifest, &dats_file, release)?;
    println!("  [cmd] {}", cmd.display());

    // Check if the generated file exists before attempting compilation
    if !Path::new(&dats_file).exists() {
        anyhow::bail!(
            "Generated file '{}' not found. Run 'atsiser generate' first.",
            dats_file
        );
    }

    compiler::execute_build(&cmd)?;
    println!("  [ok] Build complete");
    Ok(())
}

/// Run the compiled workload.
///
/// Executes the binary produced by the build step.
///
/// # Arguments
///
/// * `manifest` — A validated atsiser manifest
/// * `args` — Arguments to pass to the compiled binary
pub fn run(manifest: &Manifest, args: &[String]) -> Result<()> {
    let binary = format!(
        "{}/{}_safe",
        manifest.project.output_dir, manifest.project.name
    );
    println!("Running atsiser workload: {} {:?}", binary, args);

    if !Path::new(&binary).exists() {
        anyhow::bail!("Binary '{}' not found. Run 'atsiser build' first.", binary);
    }

    compiler::execute_run(&binary, args)?;
    Ok(())
}
