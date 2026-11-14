// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for eclexiaiser — parses and validates `eclexiaiser.toml` files
// that declare per-function energy/carbon budgets, carbon intensity providers,
// and sustainability report configuration.
//
// The manifest is the user-facing contract: developers describe WHAT resource
// constraints they want enforced, and eclexiaiser generates the instrumentation
// and reporting code to enforce them.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::{CarbonConfig, CarbonProvider, FunctionBudget, ReportConfig, ReportFormat};

/// Top-level eclexiaiser manifest, deserialized from `eclexiaiser.toml`.
///
/// Example manifest:
/// ```toml
/// [project]
/// name = "green-service"
///
/// [[functions]]
/// name = "process_batch"
/// source = "src/batch.rs"
/// energy-budget-mj = 50.0
/// carbon-budget-mg = 10.0
///
/// [carbon]
/// provider = "static"
/// region = "GB"
/// static-intensity = 200.0
///
/// [report]
/// format = "text"
/// include-recommendations = true
/// ```
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    pub project: ProjectConfig,
    /// Per-function energy and carbon budgets.
    #[serde(default)]
    pub functions: Vec<FunctionBudget>,
    /// Carbon intensity configuration.
    #[serde(default = "default_carbon_config")]
    pub carbon: CarbonConfig,
    /// Report generation configuration.
    #[serde(default = "default_report_config")]
    pub report: ReportConfig,
}

/// Project-level configuration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name.
    pub name: String,
}

/// Provide a sensible default carbon configuration (static provider, GB region).
fn default_carbon_config() -> CarbonConfig {
    CarbonConfig {
        provider: CarbonProvider::Static,
        region: "GB".to_string(),
        static_intensity: 200.0,
    }
}

/// Provide a sensible default report configuration (text format with recommendations).
fn default_report_config() -> ReportConfig {
    ReportConfig {
        format: ReportFormat::Text,
        include_recommendations: true,
    }
}

/// Load a manifest from a TOML file at the given path.
///
/// Returns a fully parsed `Manifest` or an error with context about what failed.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {path}"))?;
    parse_manifest(&content).with_context(|| format!("Failed to parse manifest: {path}"))
}

/// Parse a manifest from a TOML string. Useful for testing without filesystem access.
pub fn parse_manifest(toml_content: &str) -> Result<Manifest> {
    let manifest: Manifest =
        toml::from_str(toml_content).context("Invalid eclexiaiser.toml syntax")?;
    Ok(manifest)
}

/// Validate a parsed manifest for semantic correctness.
///
/// Checks:
/// - Project name is non-empty
/// - At least one function budget is declared
/// - All energy/carbon budgets are non-negative
/// - Source files are non-empty strings
/// - Static provider has a positive intensity value
/// - No duplicate function names
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name must be present.
    if manifest.project.name.trim().is_empty() {
        anyhow::bail!("project.name is required and cannot be empty");
    }

    // At least one function must be declared.
    if manifest.functions.is_empty() {
        anyhow::bail!("At least one [[functions]] entry is required");
    }

    // Validate each function budget.
    let mut seen_names = std::collections::HashSet::new();
    for func in &manifest.functions {
        if func.name.trim().is_empty() {
            anyhow::bail!("Function name cannot be empty");
        }
        if func.source.trim().is_empty() {
            anyhow::bail!("Function '{}' must have a non-empty source path", func.name);
        }
        if !seen_names.insert(&func.name) {
            anyhow::bail!("Duplicate function name: '{}'", func.name);
        }
        if let Some(energy) = func.energy_budget_mj
            && energy < 0.0
        {
            anyhow::bail!(
                "Function '{}' has negative energy budget: {energy}",
                func.name
            );
        }
        if let Some(carbon) = func.carbon_budget_mg
            && carbon < 0.0
        {
            anyhow::bail!(
                "Function '{}' has negative carbon budget: {carbon}",
                func.name
            );
        }
    }

    // Validate carbon config: static provider needs positive intensity.
    if manifest.carbon.provider == CarbonProvider::Static && manifest.carbon.static_intensity <= 0.0
    {
        anyhow::bail!(
            "Carbon provider 'static' requires a positive static-intensity value, got: {}",
            manifest.carbon.static_intensity
        );
    }

    // Validate region is non-empty.
    if manifest.carbon.region.trim().is_empty() {
        anyhow::bail!("carbon.region cannot be empty");
    }

    Ok(())
}

/// Write a template `eclexiaiser.toml` manifest to the given directory path.
///
/// This is invoked by the `eclexiaiser init` CLI command to scaffold a new project.
pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("eclexiaiser.toml");
    if p.exists() {
        anyhow::bail!("eclexiaiser.toml already exists at {}", p.display());
    }
    let template = r#"# eclexiaiser manifest — energy/carbon resource budgets
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-service"

[[functions]]
name = "process_batch"
source = "src/batch.rs"
energy-budget-mj = 50.0
carbon-budget-mg = 10.0

[[functions]]
name = "render_page"
source = "src/web.rs"
energy-budget-mj = 5.0

[carbon]
provider = "static"
region = "GB"
static-intensity = 200.0

[report]
format = "text"
include-recommendations = true
"#;
    std::fs::write(&p, template)?;
    println!("Created {}", p.display());
    Ok(())
}

/// Print a human-readable summary of the manifest to stdout.
pub fn print_info(manifest: &Manifest) {
    println!("=== eclexiaiser: {} ===", manifest.project.name);
    println!(
        "Carbon provider: {} (region: {})",
        manifest.carbon.provider.display_name(),
        manifest.carbon.region
    );
    if manifest.carbon.provider == CarbonProvider::Static {
        println!(
            "Static intensity: {} mg CO2/kWh",
            manifest.carbon.static_intensity
        );
    }
    println!("Report format: {:?}", manifest.report.format);
    println!(
        "Include recommendations: {}",
        manifest.report.include_recommendations
    );
    println!("Functions ({}):", manifest.functions.len());
    for func in &manifest.functions {
        let energy = func
            .energy_budget_mj
            .map(|v| format!("{v} mJ"))
            .unwrap_or_else(|| "unbounded".to_string());
        let carbon = func
            .carbon_budget_mg
            .map(|v| format!("{v} mg CO2"))
            .unwrap_or_else(|| "unbounded".to_string());
        println!(
            "  {} ({}) — energy: {energy}, carbon: {carbon}",
            func.name, func.source
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_toml() -> &'static str {
        r#"
[project]
name = "test-service"

[[functions]]
name = "do_work"
source = "src/lib.rs"
energy-budget-mj = 100.0
carbon-budget-mg = 20.0

[carbon]
provider = "static"
region = "GB"
static-intensity = 200.0

[report]
format = "text"
include-recommendations = true
"#
    }

    #[test]
    fn test_parse_valid_manifest() {
        let m = parse_manifest(sample_toml()).expect("TODO: handle error");
        assert_eq!(m.project.name, "test-service");
        assert_eq!(m.functions.len(), 1);
        assert_eq!(m.functions[0].name, "do_work");
        assert_eq!(m.functions[0].energy_budget_mj, Some(100.0));
        assert_eq!(m.carbon.provider, CarbonProvider::Static);
    }

    #[test]
    fn test_validate_empty_name() {
        let mut m = parse_manifest(sample_toml()).expect("TODO: handle error");
        m.project.name = "".to_string();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_no_functions() {
        let toml = r#"
[project]
name = "empty"

[carbon]
provider = "static"
region = "GB"
static-intensity = 200.0

[report]
format = "text"
include-recommendations = false
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_negative_budget() {
        let mut m = parse_manifest(sample_toml()).expect("TODO: handle error");
        m.functions[0].energy_budget_mj = Some(-5.0);
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_duplicate_function_names() {
        let toml = r#"
[project]
name = "dup-test"

[[functions]]
name = "process"
source = "src/a.rs"
energy-budget-mj = 10.0

[[functions]]
name = "process"
source = "src/b.rs"
energy-budget-mj = 20.0

[carbon]
provider = "static"
region = "GB"
static-intensity = 200.0

[report]
format = "text"
include-recommendations = false
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }
}
