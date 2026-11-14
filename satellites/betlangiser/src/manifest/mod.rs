// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for betlangiser — Parses and validates betlangiser.toml manifests
// that describe probabilistic variables, distribution parameters, and simulation
// configuration for ternary probabilistic modelling.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Top-level manifest structure for a betlangiser project.
///
/// A manifest defines the project metadata, the probabilistic variables
/// to model, and the simulation parameters for Monte Carlo execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata (name, description).
    pub project: ProjectConfig,

    /// List of probabilistic variable declarations, each with a
    /// distribution type and its associated parameters.
    #[serde(rename = "variables")]
    pub variables: Vec<VariableDecl>,

    /// Simulation execution parameters (sample count, confidence level,
    /// output format, optional reproducibility seed).
    #[serde(default)]
    pub simulation: SimulationConfig,
}

/// Project-level configuration — identifies the betlangiser project.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name, used in generated code headers.
    pub name: String,

    /// Optional project description for documentation.
    #[serde(default)]
    pub description: Option<String>,
}

/// A single probabilistic variable declaration.
///
/// Each variable maps a named identifier to a probability distribution
/// with validated parameters. During code generation, these become
/// Betlang distribution declarations that propagate uncertainty through
/// arithmetic and logical operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VariableDecl {
    /// Variable identifier — must be a valid Betlang identifier
    /// (alphanumeric plus underscores, starting with a letter).
    pub name: String,

    /// Distribution type: normal, uniform, beta, bernoulli, or custom.
    pub distribution: String,

    // --- Normal distribution parameters ---
    /// Mean of a normal distribution (required when distribution = "normal").
    #[serde(default)]
    pub mean: Option<f64>,

    /// Standard deviation of a normal distribution (required when distribution = "normal").
    /// Must be positive.
    #[serde(rename = "std-dev", default)]
    pub std_dev: Option<f64>,

    // --- Uniform distribution parameters ---
    /// Lower bound of a uniform distribution (required when distribution = "uniform").
    #[serde(default)]
    pub min: Option<f64>,

    /// Upper bound of a uniform distribution (required when distribution = "uniform").
    /// Must be strictly greater than min.
    #[serde(default)]
    pub max: Option<f64>,

    // --- Beta distribution parameters ---
    /// Alpha shape parameter for a beta distribution (required when distribution = "beta").
    /// Must be positive.
    #[serde(default)]
    pub alpha: Option<f64>,

    /// Beta shape parameter for a beta distribution (required when distribution = "beta").
    /// Must be positive.
    #[serde(rename = "beta-param", default)]
    pub beta_param: Option<f64>,

    // --- Bernoulli distribution parameters ---
    /// Success probability for a Bernoulli distribution (required when distribution = "bernoulli").
    /// Must be in the range [0.0, 1.0].
    #[serde(default)]
    pub probability: Option<f64>,

    // --- Custom distribution parameters ---
    /// Expression string for custom distributions — evaluated at code generation time.
    #[serde(default)]
    pub expression: Option<String>,
}

/// Simulation execution configuration — controls Monte Carlo parameters
/// and output formatting.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationConfig {
    /// Number of Monte Carlo samples to draw per variable.
    /// Higher values give more accurate estimates at the cost of runtime.
    #[serde(default = "default_samples")]
    pub samples: u64,

    /// Confidence level for interval estimation (e.g. 0.95 for a 95% CI).
    /// Must be in the range (0.0, 1.0).
    #[serde(default = "default_confidence")]
    pub confidence: f64,

    /// Optional random seed for reproducible simulations.
    /// When absent, the runtime uses a non-deterministic seed.
    #[serde(default)]
    pub seed: Option<u64>,

    /// Output format for simulation results.
    /// Supported values: "text", "json", "csv".
    #[serde(rename = "output-format", default = "default_output_format")]
    pub output_format: String,
}

/// Default sample count: 10,000 Monte Carlo draws.
fn default_samples() -> u64 {
    10_000
}

/// Default confidence level: 95%.
fn default_confidence() -> f64 {
    0.95
}

/// Default output format: human-readable text.
fn default_output_format() -> String {
    "text".to_string()
}

impl Default for SimulationConfig {
    fn default() -> Self {
        Self {
            samples: default_samples(),
            confidence: default_confidence(),
            seed: None,
            output_format: default_output_format(),
        }
    }
}

/// Load a betlangiser manifest from the given TOML file path.
///
/// Returns the parsed `Manifest` or an error if the file cannot be read
/// or the TOML structure does not match the expected schema.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a parsed manifest for semantic correctness.
///
/// Checks that:
/// - The project name is non-empty.
/// - At least one variable is declared.
/// - Each variable has a valid distribution type with correct parameters.
/// - Simulation parameters are within valid ranges.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name is mandatory.
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required and must be non-empty");
    }

    // At least one variable must be defined.
    if manifest.variables.is_empty() {
        anyhow::bail!("At least one [[variables]] entry is required");
    }

    // Validate each variable declaration.
    for var in &manifest.variables {
        validate_variable(var)?;
    }

    // Validate simulation parameters.
    validate_simulation(&manifest.simulation)?;

    Ok(())
}

/// Validate a single variable declaration — checks distribution type
/// and ensures required parameters are present and within valid ranges.
fn validate_variable(var: &VariableDecl) -> Result<()> {
    if var.name.is_empty() {
        anyhow::bail!("Variable name must be non-empty");
    }

    match var.distribution.as_str() {
        "normal" => {
            let _mean = var.mean.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': normal distribution requires 'mean'",
                    var.name
                )
            })?;
            let std_dev = var.std_dev.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': normal distribution requires 'std-dev'",
                    var.name
                )
            })?;
            if std_dev <= 0.0 {
                anyhow::bail!(
                    "Variable '{}': std-dev must be positive, got {}",
                    var.name,
                    std_dev
                );
            }
        }
        "uniform" => {
            let min_val = var.min.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': uniform distribution requires 'min'",
                    var.name
                )
            })?;
            let max_val = var.max.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': uniform distribution requires 'max'",
                    var.name
                )
            })?;
            if max_val <= min_val {
                anyhow::bail!(
                    "Variable '{}': max ({}) must be greater than min ({})",
                    var.name,
                    max_val,
                    min_val
                );
            }
        }
        "beta" => {
            let alpha = var.alpha.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': beta distribution requires 'alpha'",
                    var.name
                )
            })?;
            let beta = var.beta_param.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': beta distribution requires 'beta-param'",
                    var.name
                )
            })?;
            if alpha <= 0.0 {
                anyhow::bail!(
                    "Variable '{}': alpha must be positive, got {}",
                    var.name,
                    alpha
                );
            }
            if beta <= 0.0 {
                anyhow::bail!(
                    "Variable '{}': beta-param must be positive, got {}",
                    var.name,
                    beta
                );
            }
        }
        "bernoulli" => {
            let prob = var.probability.ok_or_else(|| {
                anyhow::anyhow!(
                    "Variable '{}': bernoulli distribution requires 'probability'",
                    var.name
                )
            })?;
            if !(0.0..=1.0).contains(&prob) {
                anyhow::bail!(
                    "Variable '{}': probability must be in [0.0, 1.0], got {}",
                    var.name,
                    prob
                );
            }
        }
        "custom" => {
            if var.expression.is_none() || var.expression.as_deref() == Some("") {
                anyhow::bail!(
                    "Variable '{}': custom distribution requires non-empty 'expression'",
                    var.name
                );
            }
        }
        other => {
            anyhow::bail!(
                "Variable '{}': unknown distribution type '{}' (expected: normal, uniform, beta, bernoulli, custom)",
                var.name,
                other
            );
        }
    }

    Ok(())
}

/// Validate simulation configuration parameters.
fn validate_simulation(sim: &SimulationConfig) -> Result<()> {
    if sim.samples == 0 {
        anyhow::bail!("simulation.samples must be positive");
    }
    if sim.confidence <= 0.0 || sim.confidence >= 1.0 {
        anyhow::bail!(
            "simulation.confidence must be in (0.0, 1.0), got {}",
            sim.confidence
        );
    }
    match sim.output_format.as_str() {
        "text" | "json" | "csv" => {}
        other => {
            anyhow::bail!(
                "simulation.output-format must be 'text', 'json', or 'csv', got '{}'",
                other
            );
        }
    }
    Ok(())
}

/// Initialise a new betlangiser.toml manifest at the given directory path.
///
/// Creates a starter manifest with example probabilistic variables
/// demonstrating normal, uniform, and bernoulli distributions.
pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("betlangiser.toml");
    if p.exists() {
        anyhow::bail!("betlangiser.toml already exists at {}", p.display());
    }

    let template = r#"# betlangiser manifest — ternary probabilistic modelling
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-model"
description = "Probabilistic model generated by betlangiser"

[[variables]]
name = "value"
distribution = "normal"
mean = 0.0
std-dev = 1.0

[[variables]]
name = "range"
distribution = "uniform"
min = 0.0
max = 100.0

[[variables]]
name = "flag"
distribution = "bernoulli"
probability = 0.5

[simulation]
samples = 10000
confidence = 0.95
output-format = "text"
"#;

    std::fs::write(&p, template)
        .with_context(|| format!("Failed to write manifest to {}", p.display()))?;
    println!("Created {}", p.display());
    Ok(())
}

/// Print human-readable summary of a parsed manifest.
pub fn print_info(m: &Manifest) {
    println!("=== {} ===", m.project.name);
    if let Some(ref desc) = m.project.description {
        println!("Description: {}", desc);
    }
    println!("Variables: {}", m.variables.len());
    for var in &m.variables {
        println!("  - {} ({})", var.name, var.distribution);
    }
    println!(
        "Simulation: {} samples, {:.0}% confidence, {} output",
        m.simulation.samples,
        m.simulation.confidence * 100.0,
        m.simulation.output_format
    );
    if let Some(seed) = m.simulation.seed {
        println!("  Seed: {}", seed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify that a well-formed manifest parses and validates without error.
    #[test]
    fn test_valid_manifest_roundtrip() {
        let toml_str = r#"
[project]
name = "test-model"

[[variables]]
name = "x"
distribution = "normal"
mean = 10.0
std-dev = 2.0

[simulation]
samples = 1000
confidence = 0.90
output-format = "json"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert!(validate(&m).is_ok());
        assert_eq!(m.project.name, "test-model");
        assert_eq!(m.variables.len(), 1);
        assert_eq!(m.variables[0].name, "x");
        assert_eq!(m.simulation.samples, 1000);
    }

    /// Verify that an empty project name is rejected.
    #[test]
    fn test_empty_project_name_rejected() {
        let toml_str = r#"
[project]
name = ""

[[variables]]
name = "x"
distribution = "normal"
mean = 0.0
std-dev = 1.0
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    /// Verify that a manifest with no variables is rejected.
    #[test]
    fn test_no_variables_rejected() {
        let toml_str = r#"
[project]
name = "empty"
"#;
        // This will fail to parse because variables is required (no default).
        let result: Result<Manifest, _> = toml::from_str(toml_str);
        assert!(result.is_err());
    }
}
