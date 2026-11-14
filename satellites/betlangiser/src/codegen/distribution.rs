// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Distribution module — Provides description and sampling logic metadata
// for each supported probability distribution. Used by the code generator
// to emit correct Betlang distribution declarations and propagation rules.

use crate::abi::Distribution;

/// Metadata about a distribution that the code generator uses to emit
/// correct Betlang code — including the Betlang constructor syntax,
/// parameter descriptions, and sampling method notes.
#[derive(Debug, Clone)]
pub struct DistributionInfo {
    /// The Betlang constructor expression for this distribution.
    /// e.g. "Normal(100.0, 5.0)" or "Bernoulli(0.7)"
    pub betlang_constructor: String,

    /// Human-readable description of the distribution.
    pub description: String,

    /// The sampling method that the Betlang runtime will use.
    /// e.g. "Box-Muller" for Normal, "inverse CDF" for Uniform.
    pub sampling_method: String,

    /// Whether this distribution produces boolean-like values
    /// (relevant for ternary logic conversion).
    pub is_boolean: bool,

    /// The support (valid range) of the distribution, as a descriptive string.
    pub support: String,
}

/// Generate a `DistributionInfo` for a given ABI distribution.
///
/// This function maps each `Distribution` variant to its Betlang
/// representation, including the constructor syntax that will appear
/// in generated code, the sampling algorithm, and whether the distribution
/// produces boolean-interpretable values.
pub fn distribution_info(dist: &Distribution) -> DistributionInfo {
    match dist {
        Distribution::Normal { mean, std_dev } => DistributionInfo {
            betlang_constructor: format!("Normal({}, {})", mean, std_dev),
            description: format!(
                "Gaussian distribution with mean {} and standard deviation {}",
                mean, std_dev
            ),
            sampling_method: "Box-Muller transform".to_string(),
            is_boolean: false,
            support: "(-inf, +inf)".to_string(),
        },

        Distribution::Uniform { min, max } => DistributionInfo {
            betlang_constructor: format!("Uniform({}, {})", min, max),
            description: format!("Continuous uniform distribution over [{}, {}]", min, max),
            sampling_method: "Inverse CDF (linear scaling of U[0,1])".to_string(),
            is_boolean: false,
            support: format!("[{}, {}]", min, max),
        },

        Distribution::Beta { alpha, beta } => DistributionInfo {
            betlang_constructor: format!("Beta({}, {})", alpha, beta),
            description: format!(
                "Beta distribution with shape parameters alpha={} and beta={}",
                alpha, beta
            ),
            sampling_method: "Joehnk's algorithm or rejection sampling".to_string(),
            is_boolean: false,
            support: "[0, 1]".to_string(),
        },

        Distribution::Bernoulli { probability } => DistributionInfo {
            betlang_constructor: format!("Bernoulli({})", probability),
            description: format!("Bernoulli trial with success probability {}", probability),
            sampling_method: "Threshold comparison against U[0,1]".to_string(),
            is_boolean: true,
            support: "{0, 1} (ternary: {true, false, unknown})".to_string(),
        },

        Distribution::Custom { expression } => DistributionInfo {
            betlang_constructor: format!("Custom(\"{}\")", expression),
            description: format!("Custom distribution: {}", expression),
            sampling_method: "User-defined (evaluated at runtime)".to_string(),
            is_boolean: false,
            support: "Defined by expression".to_string(),
        },
    }
}

/// Generate the Betlang type annotation for a distribution.
///
/// Continuous distributions map to `Prob<Float>`, Bernoulli distributions
/// map to `Prob<Ternary>`, and custom distributions use `Prob<Any>`.
pub fn betlang_type(dist: &Distribution) -> &'static str {
    match dist {
        Distribution::Normal { .. } => "Prob<Float>",
        Distribution::Uniform { .. } => "Prob<Float>",
        Distribution::Beta { .. } => "Prob<Float>",
        Distribution::Bernoulli { .. } => "Prob<Ternary>",
        Distribution::Custom { .. } => "Prob<Any>",
    }
}

/// Generate the Betlang propagation rule for arithmetic operations
/// on this distribution type.
///
/// Normal distributions propagate via linear error propagation.
/// Uniform distributions propagate via interval arithmetic.
/// Beta distributions propagate via moment matching.
/// Bernoulli distributions propagate via Kleene ternary logic.
/// Custom distributions use Monte Carlo propagation.
pub fn propagation_rule(dist: &Distribution) -> &'static str {
    match dist {
        Distribution::Normal { .. } => "linear-error-propagation",
        Distribution::Uniform { .. } => "interval-arithmetic",
        Distribution::Beta { .. } => "moment-matching",
        Distribution::Bernoulli { .. } => "kleene-ternary",
        Distribution::Custom { .. } => "monte-carlo",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normal_distribution_info() {
        let dist = Distribution::Normal {
            mean: 100.0,
            std_dev: 5.0,
        };
        let info = distribution_info(&dist);
        assert_eq!(info.betlang_constructor, "Normal(100, 5)");
        assert!(!info.is_boolean);
        assert!(info.sampling_method.contains("Box-Muller"));
    }

    #[test]
    fn test_bernoulli_is_boolean() {
        let dist = Distribution::Bernoulli { probability: 0.7 };
        let info = distribution_info(&dist);
        assert!(info.is_boolean);
        assert_eq!(betlang_type(&dist), "Prob<Ternary>");
        assert_eq!(propagation_rule(&dist), "kleene-ternary");
    }

    #[test]
    fn test_all_distributions_have_info() {
        let distributions = vec![
            Distribution::Normal {
                mean: 0.0,
                std_dev: 1.0,
            },
            Distribution::Uniform {
                min: 0.0,
                max: 10.0,
            },
            Distribution::Beta {
                alpha: 2.0,
                beta: 5.0,
            },
            Distribution::Bernoulli { probability: 0.5 },
            Distribution::Custom {
                expression: "test()".to_string(),
            },
        ];
        for dist in &distributions {
            let info = distribution_info(dist);
            assert!(!info.betlang_constructor.is_empty());
            assert!(!info.description.is_empty());
            assert!(!info.sampling_method.is_empty());
            assert!(!info.support.is_empty());

            // Type and propagation rule are non-empty.
            assert!(!betlang_type(dist).is_empty());
            assert!(!propagation_rule(dist).is_empty());
        }
    }

    #[test]
    fn test_uniform_info_contains_bounds() {
        let dist = Distribution::Uniform {
            min: 50.0,
            max: 150.0,
        };
        let info = distribution_info(&dist);
        assert!(info.betlang_constructor.contains("50"));
        assert!(info.betlang_constructor.contains("150"));
        assert_eq!(info.support, "[50, 150]");
    }

    #[test]
    fn test_beta_info() {
        let dist = Distribution::Beta {
            alpha: 2.0,
            beta: 5.0,
        };
        let info = distribution_info(&dist);
        assert_eq!(info.support, "[0, 1]");
        assert_eq!(betlang_type(&dist), "Prob<Float>");
        assert_eq!(propagation_rule(&dist), "moment-matching");
    }
}
