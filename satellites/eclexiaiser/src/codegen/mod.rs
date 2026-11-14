// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen module for eclexiaiser — orchestrates parsing, instrumentation, and
// report generation for energy/carbon sustainability enforcement.
//
// Submodules:
// - `parser`       — Parse function annotations, validate energy/carbon budgets
// - `instrumenter` — Generate energy measurement instrumentation code
// - `reporter`     — Generate sustainability reports with budget compliance

pub mod instrumenter;
pub mod parser;
pub mod reporter;

use anyhow::{Context, Result};
use std::fs;

use crate::abi::SustainabilityReport;
use crate::manifest::Manifest;

/// Generate all eclexiaiser artifacts from a validated manifest.
///
/// This is the main entry point for code generation. It:
/// 1. Parses and validates function budget annotations via `parser`
/// 2. Generates instrumentation wrappers via `instrumenter`
/// 3. Generates a sustainability report template via `reporter`
///
/// All output files are written under `output_dir`.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir).context("Failed to create output directory")?;

    // Step 1: Parse and validate all function budget annotations.
    let parsed_functions = parser::parse_function_budgets(&manifest.functions)?;
    println!(
        "  [parse] Validated {} function budget(s)",
        parsed_functions.len()
    );

    // Step 2: Generate instrumentation wrapper code.
    let instrumentation_code = instrumenter::generate_instrumentation(manifest, &parsed_functions)?;
    let instrumentation_path = format!("{output_dir}/eclexia_instrument.rs");
    fs::write(&instrumentation_path, &instrumentation_code)
        .with_context(|| format!("Failed to write instrumentation: {instrumentation_path}"))?;
    println!("  [instrument] Generated {instrumentation_path}");

    // Step 3: Generate Eclexia energy constraint definitions.
    let constraints_code = instrumenter::generate_constraints(manifest, &parsed_functions)?;
    let constraints_path = format!("{output_dir}/eclexia_constraints.ecl");
    fs::write(&constraints_path, &constraints_code)
        .with_context(|| format!("Failed to write constraints: {constraints_path}"))?;
    println!("  [constraints] Generated {constraints_path}");

    // Step 4: Generate a sustainability report template.
    let report = reporter::generate_report_template(manifest)?;
    let report_path = format!("{output_dir}/sustainability_report");
    reporter::write_report(&report, &manifest.report, &report_path)?;
    println!("  [report] Generated sustainability report at {report_path}.*");

    println!(
        "  [done] eclexiaiser generation complete for '{}'",
        manifest.project.name
    );
    Ok(())
}

/// Build the generated eclexiaiser artifacts (placeholder for Phase 2).
///
/// In a full implementation, this would compile the generated instrumentation
/// code and link it with the target project. For Phase 1, it validates that
/// the generated files exist.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!(
        "Building eclexiaiser instrumentation for: {}",
        manifest.project.name
    );
    println!("  [note] Full build integration planned for Phase 2");
    Ok(())
}

/// Run the instrumented workload (placeholder for Phase 2).
///
/// In a full implementation, this would execute the target project with
/// energy measurement hooks active, collecting real measurements and
/// producing a live sustainability report.
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("Running eclexiaiser workload: {}", manifest.project.name);
    println!("  [note] Live measurement integration planned for Phase 2");
    Ok(())
}

/// Generate a sustainability report from simulated measurements.
///
/// This is useful for testing the report pipeline without real energy data.
/// It creates a report where each function uses exactly `usage_fraction` of
/// its energy budget.
pub fn generate_report_from_simulated(
    manifest: &Manifest,
    usage_fraction: f64,
) -> Result<SustainabilityReport> {
    reporter::generate_simulated_report(manifest, usage_fraction)
}
