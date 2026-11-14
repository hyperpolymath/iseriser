// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation orchestrator for ponyiser.
//
// Coordinates the three codegen stages:
// 1. parser.rs    — parse actor/behaviour definitions from the manifest
// 2. capability.rs — infer and validate Pony reference capabilities
// 3. pony_gen.rs  — generate .pony source files with capability annotations

pub mod capability;
pub mod parser;
pub mod pony_gen;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts from a ponyiser manifest.
///
/// This is the main entry point for code generation. It:
/// 1. Parses actor/behaviour definitions from the manifest
/// 2. Runs capability analysis (if enabled in manifest)
/// 3. Generates .pony source files
/// 4. Writes all generated files to the output directory
///
/// # Arguments
/// * `manifest` - The parsed ponyiser manifest
/// * `output_dir` - Directory to write generated .pony files into
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Stage 1: Parse definitions.
    let defs = parser::parse_definitions(manifest)
        .context("Failed to parse actor/behaviour definitions")?;

    println!(
        "  Parsed {} actor(s) and {} behaviour(s)",
        defs.actors.len(),
        defs.behaviours.len()
    );

    // Stage 2: Capability analysis.
    if manifest.analysis.detect_races || manifest.analysis.suggest_capabilities {
        let result = capability::analyse(
            &defs.actors,
            &defs.behaviours,
            manifest.analysis.suggest_capabilities,
        );

        let report = capability::format_report(&result);
        println!("{}", report);

        // Write analysis report alongside generated code.
        let report_path = out.join("analysis-report.txt");
        fs::write(&report_path, &report).context("Failed to write analysis report")?;
        println!("  Analysis report: {}", report_path.display());

        if !result.is_race_free {
            println!(
                "  WARNING: {} capability violation(s) detected",
                result.violations.len()
            );
        }
    }

    // Stage 3: Generate Pony source files.
    let generated_files =
        pony_gen::generate_package(&defs).context("Failed to generate Pony source files")?;

    for file in &generated_files {
        let file_path = out.join(&file.filename);
        fs::write(&file_path, &file.content)
            .with_context(|| format!("Failed to write {}", file.filename))?;
        println!("  Generated: {}", file_path.display());
    }

    println!(
        "  Generated {} file(s) in {}",
        generated_files.len(),
        out.display()
    );

    Ok(())
}

/// Build generated artifacts (invokes the Pony compiler).
///
/// Currently prints a status message; full Pony compiler integration
/// is planned for Phase 2.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!("Building ponyiser workload: {}", manifest.project.name);
    println!("  (Pony compiler invocation planned for Phase 2)");
    Ok(())
}

/// Run the generated workload.
///
/// Currently prints a status message; execution is planned for Phase 2.
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("Running ponyiser workload: {}", manifest.project.name);
    println!("  (Execution planned for Phase 2)");
    Ok(())
}
