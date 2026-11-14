// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Reporter submodule — generates sustainability reports with budget compliance
// status, recommendations, and EU CSRD-aligned output formats.
//
// Supports three output formats:
// - **text**: Human-readable plain text report
// - **json**: Machine-readable JSON for CI/CD integration
// - **csrd**: EU Corporate Sustainability Reporting Directive template

use anyhow::{Context, Result};

use crate::abi::{
    ComplianceStatus, FunctionMeasurement, ReportConfig, ReportFormat, SustainabilityReport,
};
use crate::manifest::Manifest;

/// Generate a sustainability report template from the manifest.
///
/// This creates a report structure with zero measurements, representing the
/// "before instrumentation" baseline. In Phase 2, actual measurements from
/// the instrumented runtime will populate this structure.
pub fn generate_report_template(manifest: &Manifest) -> Result<SustainabilityReport> {
    let measurements: Vec<FunctionMeasurement> = manifest
        .functions
        .iter()
        .map(|func| FunctionMeasurement {
            function_name: func.name.clone(),
            measured_energy_mj: 0.0,
            estimated_carbon_mg: 0.0,
            energy_compliance: if func.energy_budget_mj.is_some() {
                ComplianceStatus::Compliant
            } else {
                ComplianceStatus::Unbounded
            },
            carbon_compliance: if func.carbon_budget_mg.is_some() {
                ComplianceStatus::Compliant
            } else {
                ComplianceStatus::Unbounded
            },
        })
        .collect();

    Ok(SustainabilityReport {
        project_name: manifest.project.name.clone(),
        region: manifest.carbon.region.clone(),
        provider: manifest.carbon.provider.display_name().to_string(),
        measurements,
        total_energy_mj: 0.0,
        total_carbon_mg: 0.0,
        all_compliant: true,
        recommendations: Vec::new(),
    })
}

/// Generate a sustainability report with simulated measurements.
///
/// Each function is assigned energy equal to `usage_fraction` of its energy budget.
/// If no energy budget is set, a default of 10.0 mJ is used.
/// Carbon is estimated from energy using the manifest's carbon configuration.
///
/// This is useful for testing the full report pipeline without real measurements.
pub fn generate_simulated_report(
    manifest: &Manifest,
    usage_fraction: f64,
) -> Result<SustainabilityReport> {
    let mut measurements = Vec::new();
    let mut total_energy = 0.0;
    let mut total_carbon = 0.0;
    let mut all_compliant = true;

    for func in &manifest.functions {
        // Simulate energy usage as a fraction of the budget.
        let budget_mj = func.energy_budget_mj.unwrap_or(10.0);
        let measured_energy = budget_mj * usage_fraction;
        let measured_carbon = manifest.carbon.estimate_carbon_mg(measured_energy);

        // Determine compliance.
        let energy_compliance = match func.energy_budget_mj {
            Some(budget) => {
                let percent = (measured_energy / budget) * 100.0;
                let status = ComplianceStatus::from_usage_percent(percent);
                if status == ComplianceStatus::Exceeded {
                    all_compliant = false;
                }
                status
            }
            None => ComplianceStatus::Unbounded,
        };

        let carbon_compliance = match func.carbon_budget_mg {
            Some(budget) => {
                let percent = (measured_carbon / budget) * 100.0;
                let status = ComplianceStatus::from_usage_percent(percent);
                if status == ComplianceStatus::Exceeded {
                    all_compliant = false;
                }
                status
            }
            None => ComplianceStatus::Unbounded,
        };

        total_energy += measured_energy;
        total_carbon += measured_carbon;

        measurements.push(FunctionMeasurement {
            function_name: func.name.clone(),
            measured_energy_mj: measured_energy,
            estimated_carbon_mg: measured_carbon,
            energy_compliance,
            carbon_compliance,
        });
    }

    // Generate recommendations if requested.
    let recommendations = if manifest.report.include_recommendations {
        generate_recommendations(&measurements, manifest)
    } else {
        Vec::new()
    };

    Ok(SustainabilityReport {
        project_name: manifest.project.name.clone(),
        region: manifest.carbon.region.clone(),
        provider: manifest.carbon.provider.display_name().to_string(),
        measurements,
        total_energy_mj: total_energy,
        total_carbon_mg: total_carbon,
        all_compliant,
        recommendations,
    })
}

/// Generate actionable recommendations based on measurement results.
fn generate_recommendations(
    measurements: &[FunctionMeasurement],
    manifest: &Manifest,
) -> Vec<String> {
    let mut recs = Vec::new();

    for measurement in measurements {
        if measurement.energy_compliance == ComplianceStatus::Exceeded {
            recs.push(format!(
                "CRITICAL: '{}' exceeds energy budget ({:.2} mJ measured). \
                 Consider algorithmic optimization, caching, or batch size reduction.",
                measurement.function_name, measurement.measured_energy_mj
            ));
        } else if measurement.energy_compliance == ComplianceStatus::Warning {
            recs.push(format!(
                "WARNING: '{}' is approaching energy budget ({:.2} mJ measured). \
                 Monitor closely and consider preventive optimization.",
                measurement.function_name, measurement.measured_energy_mj
            ));
        }

        if measurement.carbon_compliance == ComplianceStatus::Exceeded {
            recs.push(format!(
                "CRITICAL: '{}' exceeds carbon budget ({:.4} mg CO2). \
                 Consider scheduling during low-carbon grid periods or switching \
                 to renewable-powered infrastructure.",
                measurement.function_name, measurement.estimated_carbon_mg
            ));
        }
    }

    // General recommendations.
    if manifest.carbon.provider == crate::abi::CarbonProvider::Static {
        recs.push(
            "Consider upgrading from 'static' to 'watttime' or 'electricity-maps' \
             carbon provider for real-time grid-aware scheduling."
                .to_string(),
        );
    }

    recs
}

/// Write a sustainability report to disk in the configured format.
///
/// The report is written to `{base_path}.txt`, `{base_path}.json`, or
/// `{base_path}.csrd.txt` depending on the report format configuration.
pub fn write_report(
    report: &SustainabilityReport,
    config: &ReportConfig,
    base_path: &str,
) -> Result<()> {
    match config.format {
        ReportFormat::Text => {
            let text = render_text_report(report);
            let path = format!("{base_path}.txt");
            std::fs::write(&path, text)
                .with_context(|| format!("Failed to write report: {path}"))?;
        }
        ReportFormat::Json => {
            let json = serde_json::to_string_pretty(report)
                .context("Failed to serialize report to JSON")?;
            let path = format!("{base_path}.json");
            std::fs::write(&path, json)
                .with_context(|| format!("Failed to write report: {path}"))?;
        }
        ReportFormat::Csrd => {
            let csrd = render_csrd_report(report);
            let path = format!("{base_path}.csrd.txt");
            std::fs::write(&path, csrd)
                .with_context(|| format!("Failed to write report: {path}"))?;
        }
    }
    Ok(())
}

/// Render a human-readable plain text sustainability report.
fn render_text_report(report: &SustainabilityReport) -> String {
    let mut out = String::with_capacity(2048);

    out.push_str(&format!(
        "=== Sustainability Report: {} ===\n",
        report.project_name
    ));
    out.push_str(&format!(
        "Region: {} | Provider: {}\n",
        report.region, report.provider
    ));
    out.push_str(&format!(
        "Overall compliance: {}\n\n",
        if report.all_compliant { "PASS" } else { "FAIL" }
    ));

    out.push_str("--- Function Measurements ---\n\n");
    for m in &report.measurements {
        out.push_str(&format!("  {} \n", m.function_name));
        out.push_str(&format!("    Energy: {:.4} mJ", m.measured_energy_mj));
        out.push_str(&format!("  [{}]\n", m.energy_compliance.label()));
        out.push_str(&format!("    Carbon: {:.6} mg CO2", m.estimated_carbon_mg));
        out.push_str(&format!("  [{}]\n\n", m.carbon_compliance.label()));
    }

    out.push_str("--- Totals ---\n");
    out.push_str(&format!(
        "  Total energy: {:.4} mJ\n",
        report.total_energy_mj
    ));
    out.push_str(&format!(
        "  Total carbon: {:.6} mg CO2\n",
        report.total_carbon_mg
    ));

    if !report.recommendations.is_empty() {
        out.push_str("\n--- Recommendations ---\n");
        for (i, rec) in report.recommendations.iter().enumerate() {
            out.push_str(&format!("  {}. {rec}\n", i + 1));
        }
    }

    out
}

/// Render an EU CSRD-aligned sustainability report.
///
/// CSRD (Corporate Sustainability Reporting Directive) requires structured
/// disclosure of environmental impact. This generates a template aligned with
/// ESRS E1 (Climate Change) disclosure requirements.
fn render_csrd_report(report: &SustainabilityReport) -> String {
    let mut out = String::with_capacity(4096);

    out.push_str("==============================================================\n");
    out.push_str("  EU CSRD Sustainability Disclosure — Software Energy Impact\n");
    out.push_str("  ESRS E1: Climate Change — Computational Resource Accounting\n");
    out.push_str("==============================================================\n\n");

    out.push_str(&format!("Project: {}\n", report.project_name));
    out.push_str(&format!("Grid Region: {}\n", report.region));
    out.push_str(&format!("Carbon Data Provider: {}\n", report.provider));
    out.push_str("Reporting Period: Generated by eclexiaiser\n\n");

    out.push_str("1. SCOPE 2 EMISSIONS — Computational Energy\n\n");
    out.push_str(&format!(
        "   Total energy consumption: {:.4} mJ ({:.6} kWh)\n",
        report.total_energy_mj,
        report.total_energy_mj / 3_600_000_000.0
    ));
    out.push_str(&format!(
        "   Total GHG emissions (CO2e): {:.6} mg ({:.9} kg)\n\n",
        report.total_carbon_mg,
        report.total_carbon_mg / 1_000_000.0
    ));

    out.push_str("2. FUNCTION-LEVEL BREAKDOWN\n\n");
    for m in &report.measurements {
        out.push_str(&format!(
            "   {}: {:.4} mJ energy, {:.6} mg CO2e\n",
            m.function_name, m.measured_energy_mj, m.estimated_carbon_mg
        ));
        out.push_str(&format!(
            "     Energy compliance: {}  |  Carbon compliance: {}\n",
            m.energy_compliance.label(),
            m.carbon_compliance.label()
        ));
    }

    out.push_str("\n3. COMPLIANCE STATUS\n\n");
    out.push_str(&format!(
        "   Overall: {}\n",
        if report.all_compliant {
            "All functions within budget"
        } else {
            "One or more functions exceed budget — corrective action required"
        }
    ));
    out.push_str(&format!(
        "   Energy violations: {}\n",
        report.energy_violations()
    ));
    out.push_str(&format!(
        "   Carbon violations: {}\n",
        report.carbon_violations()
    ));

    if !report.recommendations.is_empty() {
        out.push_str("\n4. CORRECTIVE ACTIONS\n\n");
        for (i, rec) in report.recommendations.iter().enumerate() {
            out.push_str(&format!("   4.{}. {rec}\n", i + 1));
        }
    }

    out.push_str("\n==============================================================\n");
    out.push_str("  End of CSRD Disclosure\n");
    out.push_str("==============================================================\n");

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::{CarbonConfig, CarbonProvider, FunctionBudget, ReportConfig, ReportFormat};
    use crate::manifest::{Manifest, ProjectConfig};

    fn test_manifest() -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "report-test".to_string(),
            },
            functions: vec![
                FunctionBudget {
                    name: "fast_func".to_string(),
                    source: "src/fast.rs".to_string(),
                    energy_budget_mj: Some(100.0),
                    carbon_budget_mg: Some(20.0),
                },
                FunctionBudget {
                    name: "unbounded_func".to_string(),
                    source: "src/unbounded.rs".to_string(),
                    energy_budget_mj: None,
                    carbon_budget_mg: None,
                },
            ],
            carbon: CarbonConfig {
                provider: CarbonProvider::Static,
                region: "DE".to_string(),
                static_intensity: 350.0,
            },
            report: ReportConfig {
                format: ReportFormat::Text,
                include_recommendations: true,
            },
        }
    }

    #[test]
    fn test_report_template_has_zero_measurements() {
        let m = test_manifest();
        let report = generate_report_template(&m).expect("TODO: handle error");
        assert_eq!(report.project_name, "report-test");
        assert_eq!(report.measurements.len(), 2);
        assert_eq!(report.total_energy_mj, 0.0);
        assert!(report.all_compliant);
    }

    #[test]
    fn test_simulated_report_compliant_at_50_percent() {
        let m = test_manifest();
        let report = generate_simulated_report(&m, 0.5).expect("TODO: handle error");
        assert!(report.all_compliant);
        assert_eq!(report.energy_violations(), 0);
        // At 50% usage, fast_func should use 50 mJ out of 100 mJ budget.
        assert!((report.measurements[0].measured_energy_mj - 50.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_simulated_report_exceeded_at_150_percent() {
        let m = test_manifest();
        let report = generate_simulated_report(&m, 1.5).expect("TODO: handle error");
        assert!(!report.all_compliant);
        assert!(report.energy_violations() > 0);
    }

    #[test]
    fn test_text_report_rendering() {
        let m = test_manifest();
        let report = generate_simulated_report(&m, 0.7).expect("TODO: handle error");
        let text = render_text_report(&report);
        assert!(text.contains("Sustainability Report: report-test"));
        assert!(text.contains("fast_func"));
        assert!(text.contains("unbounded_func"));
        assert!(text.contains("PASS"));
    }

    #[test]
    fn test_csrd_report_rendering() {
        let m = test_manifest();
        let report = generate_simulated_report(&m, 1.2).expect("TODO: handle error");
        let csrd = render_csrd_report(&report);
        assert!(csrd.contains("EU CSRD Sustainability Disclosure"));
        assert!(csrd.contains("ESRS E1"));
        assert!(csrd.contains("report-test"));
        assert!(csrd.contains("CORRECTIVE ACTIONS"));
    }

    #[test]
    fn test_recommendations_generated_for_exceeded() {
        let m = test_manifest();
        let report = generate_simulated_report(&m, 1.5).expect("TODO: handle error");
        assert!(!report.recommendations.is_empty());
        // Should have recommendation about fast_func exceeding budget.
        assert!(
            report
                .recommendations
                .iter()
                .any(|r| r.contains("fast_func"))
        );
    }
}
