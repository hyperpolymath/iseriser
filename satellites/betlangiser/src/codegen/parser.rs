// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser module — Converts manifest variable declarations into validated
// ABI distribution types. This is the bridge between the TOML manifest
// representation and the internal ABI types used by the code generator.

use crate::abi::{Distribution, SimulationConfig as AbiSimConfig};
use crate::manifest::{Manifest, SimulationConfig, VariableDecl};

/// A parsed variable ready for code generation — pairs a name with
/// its validated ABI distribution type.
#[derive(Debug, Clone)]
pub struct ParsedVariable {
    /// The variable's identifier in generated Betlang code.
    pub name: String,
    /// The validated probability distribution.
    pub distribution: Distribution,
}

/// Parse all variable declarations from a manifest into validated
/// `ParsedVariable` instances.
///
/// Each variable's distribution string is matched to the corresponding
/// ABI `Distribution` variant, and parameters are extracted and validated
/// via the `Distribution::new_*` constructors.
///
/// Returns an error if any variable has invalid distribution parameters.
pub fn parse_variables(manifest: &Manifest) -> Result<Vec<ParsedVariable>, String> {
    let mut parsed = Vec::with_capacity(manifest.variables.len());

    for var in &manifest.variables {
        let distribution = parse_distribution(var)?;
        parsed.push(ParsedVariable {
            name: var.name.clone(),
            distribution,
        });
    }

    Ok(parsed)
}

/// Parse a single variable declaration into an ABI Distribution.
///
/// Dispatches on the `distribution` field string and extracts the
/// required parameters for each distribution family.
fn parse_distribution(var: &VariableDecl) -> Result<Distribution, String> {
    match var.distribution.as_str() {
        "normal" => {
            let mean = var
                .mean
                .ok_or_else(|| format!("Variable '{}': normal requires 'mean'", var.name))?;
            let std_dev = var
                .std_dev
                .ok_or_else(|| format!("Variable '{}': normal requires 'std-dev'", var.name))?;
            Distribution::new_normal(mean, std_dev)
                .map_err(|e| format!("Variable '{}': {}", var.name, e))
        }
        "uniform" => {
            let min = var
                .min
                .ok_or_else(|| format!("Variable '{}': uniform requires 'min'", var.name))?;
            let max = var
                .max
                .ok_or_else(|| format!("Variable '{}': uniform requires 'max'", var.name))?;
            Distribution::new_uniform(min, max)
                .map_err(|e| format!("Variable '{}': {}", var.name, e))
        }
        "beta" => {
            let alpha = var
                .alpha
                .ok_or_else(|| format!("Variable '{}': beta requires 'alpha'", var.name))?;
            let beta = var
                .beta_param
                .ok_or_else(|| format!("Variable '{}': beta requires 'beta-param'", var.name))?;
            Distribution::new_beta(alpha, beta)
                .map_err(|e| format!("Variable '{}': {}", var.name, e))
        }
        "bernoulli" => {
            let prob = var.probability.ok_or_else(|| {
                format!("Variable '{}': bernoulli requires 'probability'", var.name)
            })?;
            Distribution::new_bernoulli(prob).map_err(|e| format!("Variable '{}': {}", var.name, e))
        }
        "custom" => {
            let expr = var
                .expression
                .clone()
                .ok_or_else(|| format!("Variable '{}': custom requires 'expression'", var.name))?;
            Distribution::new_custom(expr).map_err(|e| format!("Variable '{}': {}", var.name, e))
        }
        other => Err(format!(
            "Variable '{}': unknown distribution '{}'",
            var.name, other
        )),
    }
}

/// Convert the manifest's simulation config into the ABI simulation config type.
pub fn parse_simulation_config(sim: &SimulationConfig) -> AbiSimConfig {
    AbiSimConfig {
        samples: sim.samples,
        confidence: sim.confidence,
        seed: sim.seed,
        output_format: sim.output_format.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{Manifest, ProjectConfig, SimulationConfig, VariableDecl};

    /// Helper to create a minimal manifest with one variable.
    fn make_manifest(var: VariableDecl) -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "test".to_string(),
                description: None,
            },
            variables: vec![var],
            simulation: SimulationConfig::default(),
        }
    }

    #[test]
    fn test_parse_normal_variable() {
        let var = VariableDecl {
            name: "price".to_string(),
            distribution: "normal".to_string(),
            mean: Some(100.0),
            std_dev: Some(5.0),
            min: None,
            max: None,
            alpha: None,
            beta_param: None,
            probability: None,
            expression: None,
        };
        let m = make_manifest(var);
        let parsed = parse_variables(&m).expect("TODO: handle error");
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].name, "price");
        assert_eq!(parsed[0].distribution.kind(), "normal");
    }

    #[test]
    fn test_parse_all_distribution_types() {
        let vars = vec![
            VariableDecl {
                name: "a".to_string(),
                distribution: "normal".to_string(),
                mean: Some(0.0),
                std_dev: Some(1.0),
                min: None,
                max: None,
                alpha: None,
                beta_param: None,
                probability: None,
                expression: None,
            },
            VariableDecl {
                name: "b".to_string(),
                distribution: "uniform".to_string(),
                mean: None,
                std_dev: None,
                min: Some(0.0),
                max: Some(10.0),
                alpha: None,
                beta_param: None,
                probability: None,
                expression: None,
            },
            VariableDecl {
                name: "c".to_string(),
                distribution: "beta".to_string(),
                mean: None,
                std_dev: None,
                min: None,
                max: None,
                alpha: Some(2.0),
                beta_param: Some(5.0),
                probability: None,
                expression: None,
            },
            VariableDecl {
                name: "d".to_string(),
                distribution: "bernoulli".to_string(),
                mean: None,
                std_dev: None,
                min: None,
                max: None,
                alpha: None,
                beta_param: None,
                probability: Some(0.7),
                expression: None,
            },
            VariableDecl {
                name: "e".to_string(),
                distribution: "custom".to_string(),
                mean: None,
                std_dev: None,
                min: None,
                max: None,
                alpha: None,
                beta_param: None,
                probability: None,
                expression: Some("mixture(0.5, normal(0,1), normal(5,2))".to_string()),
            },
        ];
        let m = Manifest {
            project: ProjectConfig {
                name: "test".to_string(),
                description: None,
            },
            variables: vars,
            simulation: SimulationConfig::default(),
        };
        let parsed = parse_variables(&m).expect("TODO: handle error");
        assert_eq!(parsed.len(), 5);
        assert_eq!(parsed[0].distribution.kind(), "normal");
        assert_eq!(parsed[1].distribution.kind(), "uniform");
        assert_eq!(parsed[2].distribution.kind(), "beta");
        assert_eq!(parsed[3].distribution.kind(), "bernoulli");
        assert_eq!(parsed[4].distribution.kind(), "custom");
    }

    #[test]
    fn test_parse_invalid_distribution_rejected() {
        let var = VariableDecl {
            name: "bad".to_string(),
            distribution: "exponential".to_string(),
            mean: None,
            std_dev: None,
            min: None,
            max: None,
            alpha: None,
            beta_param: None,
            probability: None,
            expression: None,
        };
        let m = make_manifest(var);
        assert!(parse_variables(&m).is_err());
    }

    #[test]
    fn test_parse_missing_params_rejected() {
        // Normal without std-dev.
        let var = VariableDecl {
            name: "incomplete".to_string(),
            distribution: "normal".to_string(),
            mean: Some(0.0),
            std_dev: None,
            min: None,
            max: None,
            alpha: None,
            beta_param: None,
            probability: None,
            expression: None,
        };
        let m = make_manifest(var);
        assert!(parse_variables(&m).is_err());
    }
}
