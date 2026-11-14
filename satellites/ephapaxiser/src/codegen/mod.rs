// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen module for ephapaxiser — Orchestrates parsing, analysis, and wrapper generation.
//
// Submodules:
// - parser: Finds resource allocation/deallocation call sites in source files
// - analyzer: Tracks ownership state and detects linear type violations
// - wrapper_gen: Generates Ephapax linear type wrapper code
//
// The main entry points are:
// - `generate_all`: Parse sources, analyse, generate wrappers, write output
// - `analyse_manifest`: Parse and analyse without generating (for reporting only)
// - `build` / `run`: Placeholder build and run commands

pub mod analyzer;
pub mod parser;
pub mod wrapper_gen;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::abi::AnalysisResult;
use crate::manifest::Manifest;

/// Parse all source files in the manifest and run analysis.
///
/// Reads each source file, parses it for call sites, then runs the analyzer
/// to detect violations. Returns the aggregated analysis result.
///
/// # Arguments
/// * `manifest` — The parsed ephapaxiser manifest.
/// * `base_dir` — Base directory for resolving relative source paths.
///
/// # Returns
/// An `AnalysisResult` with all tracked resources and detected violations.
pub fn analyse_manifest(manifest: &Manifest, base_dir: &str) -> Result<AnalysisResult> {
    let mut all_sites = Vec::new();

    for source in &manifest.sources {
        let source_path = Path::new(base_dir).join(&source.path);
        let content = fs::read_to_string(&source_path)
            .with_context(|| format!("Failed to read source file: {}", source_path.display()))?;

        let sites = parser::parse_source(&content, &source.path, &manifest.resources);
        all_sites.extend(sites);
    }

    Ok(analyzer::analyse(
        &all_sites,
        &manifest.resources,
        &manifest.analysis,
    ))
}

/// Generate Ephapax linear type wrappers and analysis report.
///
/// This is the main "generate" command: it parses sources, runs analysis, generates
/// wrapper code, and writes everything to the output directory.
///
/// # Output files
/// - `wrappers.rs` — Generated linear type wrapper structs
/// - `analysis_report.txt` — Human-readable analysis report (or .json if configured)
///
/// # Arguments
/// * `manifest` — The parsed ephapaxiser manifest.
/// * `output_dir` — Directory to write generated files to.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir).context("Failed to create output directory")?;

    // Generate wrapper code (does not require source analysis).
    let wrappers = wrapper_gen::generate_wrappers(&manifest.resources, &manifest.project.name);
    let wrapper_path = Path::new(output_dir).join("wrappers.rs");
    fs::write(&wrapper_path, &wrappers)
        .with_context(|| format!("Failed to write wrappers to {}", wrapper_path.display()))?;
    println!("  Generated: {}", wrapper_path.display());

    // Attempt source analysis (may fail if source files are not at expected paths).
    let base_dir = Path::new(output_dir)
        .parent()
        .and_then(|p| p.parent())
        .unwrap_or(Path::new("."));

    match analyse_manifest(manifest, base_dir.to_str().unwrap_or(".")) {
        Ok(result) => {
            // Write analysis report.
            let report = format_report(&result, manifest);
            let report_ext = match manifest.analysis.report_format {
                crate::manifest::ReportFormat::Json => "json",
                crate::manifest::ReportFormat::A2ml => "a2ml",
                crate::manifest::ReportFormat::Text => "txt",
            };
            let report_path = Path::new(output_dir).join(format!("analysis_report.{}", report_ext));
            fs::write(&report_path, &report)
                .with_context(|| format!("Failed to write report to {}", report_path.display()))?;
            println!("  Generated: {}", report_path.display());

            // Print summary.
            println!("\n  Analysis summary for '{}':", manifest.project.name);
            println!("    Resources tracked: {}", result.tracked_resources.len());
            println!("    Allocations found: {}", result.allocation_count);
            println!("    Deallocations found: {}", result.deallocation_count);
            if result.is_clean() {
                println!("    Violations: NONE (clean)");
            } else {
                println!("    Violations: {}", result.violations.len());
                println!("      Leaks: {}", result.leak_count());
                println!("      Double-frees: {}", result.double_free_count());
                println!("      Use-after-free: {}", result.use_after_free_count());
            }
        }
        Err(e) => {
            println!(
                "  Note: Source analysis skipped ({}). Wrappers generated from manifest only.",
                e
            );
        }
    }

    Ok(())
}

/// Format an analysis result as a human-readable text report.
fn format_report(result: &AnalysisResult, manifest: &Manifest) -> String {
    match manifest.analysis.report_format {
        crate::manifest::ReportFormat::Json => {
            serde_json::to_string_pretty(result).unwrap_or_else(|_| "{}".to_string())
        }
        _ => {
            let mut report = String::new();
            report.push_str(&format!(
                "ephapaxiser analysis report for '{}'\n",
                manifest.project.name
            ));
            report.push_str("========================================\n\n");
            report.push_str(&format!("Allocations found: {}\n", result.allocation_count));
            report.push_str(&format!(
                "Deallocations found: {}\n",
                result.deallocation_count
            ));
            report.push_str(&format!(
                "Resources tracked: {}\n\n",
                result.tracked_resources.len()
            ));

            if result.is_clean() {
                report.push_str("No violations detected. All resources used exactly once.\n");
            } else {
                report.push_str(&format!("VIOLATIONS ({}):\n\n", result.violations.len()));
                for (i, violation) in result.violations.iter().enumerate() {
                    report.push_str(&format!("  {}. {}\n", i + 1, violation));
                }
            }

            report
        }
    }
}

/// Placeholder build command (Phase 2 will compile generated wrappers).
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!(
        "Building ephapaxiser wrappers for: {}",
        manifest.project.name
    );
    println!("  (Phase 1: wrappers are generated as source — compile them with your project)");
    Ok(())
}

/// Placeholder run command (Phase 2 will execute analysis as a standalone pass).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!(
        "Running ephapaxiser analysis for: {}",
        manifest.project.name
    );
    println!("  (Use 'ephapaxiser generate' to produce wrappers and analysis report)");
    Ok(())
}
