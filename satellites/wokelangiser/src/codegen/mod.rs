// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen orchestration module for wokelangiser — coordinates parsing,
// consent gate generation, accessibility checking, and i18n extraction
// to produce a complete compliance-augmented project output.

pub mod accessibility;
pub mod consent;
pub mod i18n;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::abi::WCAGLevel;
use crate::manifest::Manifest;

/// Run the full code generation pipeline:
/// 1. Parse project files for consent points, accessibility issues, and i18n strings
/// 2. Generate consent gates (state machine + wrapper functions + banner)
/// 3. Run accessibility checks and generate a compliance report
/// 4. Extract i18n strings and generate locale files
/// 5. Write the final compliance report
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("Failed to create output directory: {}", output_dir))?;

    println!("wokelangiser: generating for '{}'", manifest.project.name);

    // Step 1: Parse project files.
    println!("  [1/4] Scanning project files...");
    let consent_points = parser::find_consent_points(manifest)?;
    println!("    Found {} consent points", consent_points.len());

    let wcag_level =
        WCAGLevel::from_str(&manifest.accessibility.wcag_level).unwrap_or(WCAGLevel::AA);
    let accessibility_violations = parser::find_accessibility_issues(manifest, wcag_level)?;
    println!(
        "    Found {} accessibility violations",
        accessibility_violations.len()
    );

    let i18n_strings = if manifest.i18n.extract_strings {
        let strings = parser::extract_i18n_strings(manifest)?;
        println!("    Found {} translatable strings", strings.len());
        strings
    } else {
        println!("    String extraction disabled");
        Vec::new()
    };

    // Step 2: Generate consent gates.
    println!("  [2/4] Generating consent gates...");
    let gates = consent::generate_consent_gates(manifest, &consent_points, output_dir)?;

    // Step 3: Generate accessibility report.
    println!("  [3/4] Running accessibility checks...");
    let mut report =
        accessibility::generate_accessibility_report(manifest, &accessibility_violations)?;
    report.consent_gates_count = gates.len();
    report.i18n_strings_count = i18n_strings.len();

    // Step 4: Generate i18n locale files.
    println!("  [4/4] Generating i18n locale files...");
    if manifest.i18n.extract_strings {
        i18n::generate_locale_files(manifest, &i18n_strings, output_dir)?;
        i18n::generate_i18n_module(manifest, output_dir)?;
    }

    // Write the compliance report.
    let report_text = accessibility::format_report(&report, &manifest.report.format)?;
    let report_ext = match manifest.report.format.as_str() {
        "json" => "json",
        "a2ml" => "a2ml",
        _ => "txt",
    };
    let report_path = Path::new(output_dir).join(format!("compliance-report.{}", report_ext));
    fs::write(&report_path, &report_text)
        .with_context(|| format!("Failed to write report: {}", report_path.display()))?;

    // Print summary.
    let (errors, warnings, infos) = report.summary();
    println!();
    println!("  === Summary ===");
    println!("  Consent gates:     {}", gates.len());
    println!("  A11y violations:   {}", accessibility_violations.len());
    println!("  I18n strings:      {}", i18n_strings.len());
    println!(
        "  Report findings:   {} errors, {} warnings, {} info",
        errors, warnings, infos
    );
    println!(
        "  Result:            {}",
        if report.passes { "PASS" } else { "FAIL" }
    );
    println!("  Report written to: {}", report_path.display());
    println!();

    Ok(())
}

/// Build the generated artifacts (placeholder for future compilation step).
/// In Phase 1, this validates the manifest and reports readiness.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!(
        "wokelangiser: build for '{}' — generated artifacts are ready",
        manifest.project.name
    );
    Ok(())
}

/// Run the compliance analysis without generating output files.
/// Useful for CI/CD integration where only the report is needed.
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!(
        "wokelangiser: running compliance analysis for '{}'",
        manifest.project.name
    );

    let wcag_level =
        WCAGLevel::from_str(&manifest.accessibility.wcag_level).unwrap_or(WCAGLevel::AA);

    let consent_points = parser::find_consent_points(manifest)?;
    let violations = parser::find_accessibility_issues(manifest, wcag_level)?;
    let i18n_strings = if manifest.i18n.extract_strings {
        parser::extract_i18n_strings(manifest)?
    } else {
        Vec::new()
    };

    let report = accessibility::generate_accessibility_report(manifest, &violations)?;
    let report_text = accessibility::format_report(&report, &manifest.report.format)?;
    println!("{}", report_text);

    println!(
        "Consent points: {} | Violations: {} | I18n strings: {}",
        consent_points.len(),
        violations.len(),
        i18n_strings.len()
    );

    Ok(())
}
