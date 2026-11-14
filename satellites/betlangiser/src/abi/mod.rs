// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for betlangiser — Core types for ternary probabilistic modelling.
//
// This module defines the Betlang type system that underpins betlangiser:
// - Distribution: probability distributions as first-class values
// - TernaryBool: Kleene strong three-valued logic (true/false/unknown)
// - ConfidenceInterval: statistical interval estimation
// - SimulationConfig / SimulationResult: Monte Carlo execution types
//
// These types form the ABI contract between betlangiser's Rust CLI,
// the generated Betlang code, and the Zig FFI bridge. In the full
// Idris2 ABI layer, each type carries dependent-type proofs of its
// invariants (e.g. std_dev > 0, probability in [0,1]).

use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// Distribution types
// ---------------------------------------------------------------------------

/// A probability distribution with validated parameters.
///
/// Each variant carries the minimum parameters needed to fully specify
/// the distribution. Parameter invariants (positivity, range membership)
/// are enforced at construction time via `Distribution::new_*` methods.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Distribution {
    /// Normal (Gaussian) distribution parameterised by mean and standard deviation.
    /// Invariant: std_dev > 0.
    Normal { mean: f64, std_dev: f64 },

    /// Continuous uniform distribution over [min, max].
    /// Invariant: max > min.
    Uniform { min: f64, max: f64 },

    /// Beta distribution parameterised by two shape parameters.
    /// Invariant: alpha > 0, beta > 0.
    /// Produces values in [0, 1] — useful for modelling probabilities.
    Beta { alpha: f64, beta: f64 },

    /// Bernoulli distribution — a single coin flip with given success probability.
    /// Invariant: probability in [0, 1].
    /// In ternary mode, low-confidence Bernoulli outcomes map to Unknown.
    Bernoulli { probability: f64 },

    /// Custom distribution defined by an expression string.
    /// Evaluated at code generation time; the expression must be a valid
    /// Betlang distribution expression.
    Custom { expression: String },
}

impl Distribution {
    /// Construct a Normal distribution, validating that std_dev > 0.
    pub fn new_normal(mean: f64, std_dev: f64) -> Result<Self, String> {
        if std_dev <= 0.0 {
            return Err(format!("Normal std_dev must be positive, got {}", std_dev));
        }
        Ok(Distribution::Normal { mean, std_dev })
    }

    /// Construct a Uniform distribution, validating that max > min.
    pub fn new_uniform(min: f64, max: f64) -> Result<Self, String> {
        if max <= min {
            return Err(format!(
                "Uniform max ({}) must be greater than min ({})",
                max, min
            ));
        }
        Ok(Distribution::Uniform { min, max })
    }

    /// Construct a Beta distribution, validating that both shape parameters are positive.
    pub fn new_beta(alpha: f64, beta: f64) -> Result<Self, String> {
        if alpha <= 0.0 {
            return Err(format!("Beta alpha must be positive, got {}", alpha));
        }
        if beta <= 0.0 {
            return Err(format!("Beta beta must be positive, got {}", beta));
        }
        Ok(Distribution::Beta { alpha, beta })
    }

    /// Construct a Bernoulli distribution, validating that probability is in [0, 1].
    pub fn new_bernoulli(probability: f64) -> Result<Self, String> {
        if !(0.0..=1.0).contains(&probability) {
            return Err(format!(
                "Bernoulli probability must be in [0, 1], got {}",
                probability
            ));
        }
        Ok(Distribution::Bernoulli { probability })
    }

    /// Construct a Custom distribution from an expression string.
    pub fn new_custom(expression: String) -> Result<Self, String> {
        if expression.is_empty() {
            return Err("Custom distribution expression must be non-empty".to_string());
        }
        Ok(Distribution::Custom { expression })
    }

    /// Return the distribution family name as a string slice.
    pub fn kind(&self) -> &str {
        match self {
            Distribution::Normal { .. } => "normal",
            Distribution::Uniform { .. } => "uniform",
            Distribution::Beta { .. } => "beta",
            Distribution::Bernoulli { .. } => "bernoulli",
            Distribution::Custom { .. } => "custom",
        }
    }

    /// Return a human-readable description of the distribution and its parameters.
    pub fn describe(&self) -> String {
        match self {
            Distribution::Normal { mean, std_dev } => {
                format!("Normal(mean={}, std_dev={})", mean, std_dev)
            }
            Distribution::Uniform { min, max } => {
                format!("Uniform(min={}, max={})", min, max)
            }
            Distribution::Beta { alpha, beta } => {
                format!("Beta(alpha={}, beta={})", alpha, beta)
            }
            Distribution::Bernoulli { probability } => {
                format!("Bernoulli(p={})", probability)
            }
            Distribution::Custom { expression } => {
                format!("Custom({})", expression)
            }
        }
    }
}

impl fmt::Display for Distribution {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.describe())
    }
}

// ---------------------------------------------------------------------------
// Ternary logic (Kleene strong three-valued logic)
// ---------------------------------------------------------------------------

/// Kleene strong three-valued logic — the foundation of Betlang's ternary
/// boolean type.
///
/// In Betlang, boolean values that depend on probabilistic inputs may not
/// be decidable to true or false. The Unknown variant represents epistemic
/// uncertainty: we do not have enough information to determine the truth value.
///
/// This implements Kleene's strong logic of indeterminacy:
/// - AND: Unknown AND False = False; Unknown AND True = Unknown
/// - OR:  Unknown OR True = True; Unknown OR False = Unknown
/// - NOT: NOT Unknown = Unknown
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TernaryBool {
    /// Definitely true — the proposition holds with certainty.
    True,
    /// Definitely false — the proposition does not hold.
    False,
    /// Unknown — insufficient information to determine truth value.
    /// Arises when a probabilistic variable's sampled value falls
    /// within an indeterminate region, or when confidence is too low.
    Unknown,
}

impl TernaryBool {
    /// Ternary AND (Kleene strong conjunction).
    ///
    /// Truth table:
    /// ```text
    ///   AND   | True    | False   | Unknown
    /// --------|---------|---------|--------
    /// True    | True    | False   | Unknown
    /// False   | False   | False   | False
    /// Unknown | Unknown | False   | Unknown
    /// ```
    pub fn and(self, other: TernaryBool) -> TernaryBool {
        match (self, other) {
            (TernaryBool::False, _) | (_, TernaryBool::False) => TernaryBool::False,
            (TernaryBool::True, TernaryBool::True) => TernaryBool::True,
            _ => TernaryBool::Unknown,
        }
    }

    /// Ternary OR (Kleene strong disjunction).
    ///
    /// Truth table:
    /// ```text
    ///   OR    | True    | False   | Unknown
    /// --------|---------|---------|--------
    /// True    | True    | True    | True
    /// False   | True    | False   | Unknown
    /// Unknown | True    | Unknown | Unknown
    /// ```
    pub fn or(self, other: TernaryBool) -> TernaryBool {
        match (self, other) {
            (TernaryBool::True, _) | (_, TernaryBool::True) => TernaryBool::True,
            (TernaryBool::False, TernaryBool::False) => TernaryBool::False,
            _ => TernaryBool::Unknown,
        }
    }

    /// Ternary NOT (Kleene strong negation).
    ///
    /// NOT True = False, NOT False = True, NOT Unknown = Unknown.
    #[allow(clippy::should_implement_trait)]
    pub fn not(self) -> TernaryBool {
        match self {
            TernaryBool::True => TernaryBool::False,
            TernaryBool::False => TernaryBool::True,
            TernaryBool::Unknown => TernaryBool::Unknown,
        }
    }

    /// Ternary implication (material conditional).
    ///
    /// Defined as: A -> B  ===  (NOT A) OR B
    pub fn implies(self, other: TernaryBool) -> TernaryBool {
        self.not().or(other)
    }

    /// Convert from a boolean value (two-valued logic embedding).
    pub fn from_bool(value: bool) -> TernaryBool {
        if value {
            TernaryBool::True
        } else {
            TernaryBool::False
        }
    }

    /// Attempt to convert to a boolean. Returns None for Unknown.
    pub fn to_bool(self) -> Option<bool> {
        match self {
            TernaryBool::True => Some(true),
            TernaryBool::False => Some(false),
            TernaryBool::Unknown => None,
        }
    }

    /// Check whether this value is definitely known (True or False).
    pub fn is_known(self) -> bool {
        self != TernaryBool::Unknown
    }
}

impl fmt::Display for TernaryBool {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TernaryBool::True => write!(f, "true"),
            TernaryBool::False => write!(f, "false"),
            TernaryBool::Unknown => write!(f, "unknown"),
        }
    }
}

// ---------------------------------------------------------------------------
// Confidence interval
// ---------------------------------------------------------------------------

/// A confidence interval computed from a Monte Carlo simulation.
///
/// Represents the range [lower, upper] within which the true value
/// is expected to fall with the given confidence level (e.g. 0.95 = 95%).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConfidenceInterval {
    /// Lower bound of the interval.
    pub lower: f64,
    /// Upper bound of the interval.
    pub upper: f64,
    /// Confidence level, in (0, 1). For example, 0.95 means 95% confidence.
    pub confidence: f64,
}

impl ConfidenceInterval {
    /// Construct a confidence interval with validation.
    ///
    /// Returns an error if:
    /// - lower > upper
    /// - confidence is not in (0, 1)
    pub fn new(lower: f64, upper: f64, confidence: f64) -> Result<Self, String> {
        if lower > upper {
            return Err(format!(
                "ConfidenceInterval lower ({}) must not exceed upper ({})",
                lower, upper
            ));
        }
        if confidence <= 0.0 || confidence >= 1.0 {
            return Err(format!(
                "ConfidenceInterval confidence must be in (0, 1), got {}",
                confidence
            ));
        }
        Ok(ConfidenceInterval {
            lower,
            upper,
            confidence,
        })
    }

    /// Width of the interval (upper - lower).
    pub fn width(&self) -> f64 {
        self.upper - self.lower
    }

    /// Midpoint of the interval — a point estimate.
    pub fn midpoint(&self) -> f64 {
        (self.lower + self.upper) / 2.0
    }

    /// Check whether a given value falls within this confidence interval.
    pub fn contains(&self, value: f64) -> bool {
        value >= self.lower && value <= self.upper
    }
}

impl fmt::Display for ConfidenceInterval {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "[{:.4}, {:.4}] ({:.0}% CI)",
            self.lower,
            self.upper,
            self.confidence * 100.0
        )
    }
}

// ---------------------------------------------------------------------------
// Simulation types
// ---------------------------------------------------------------------------

/// Configuration for a Monte Carlo simulation run.
///
/// Passed to the generated Betlang code to control how many samples
/// are drawn, what confidence level to report, and whether the run
/// should be reproducible.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationConfig {
    /// Number of Monte Carlo samples per variable.
    pub samples: u64,
    /// Confidence level for interval estimation.
    pub confidence: f64,
    /// Optional seed for reproducibility.
    pub seed: Option<u64>,
    /// Output format: "text", "json", or "csv".
    pub output_format: String,
}

/// Result of a Monte Carlo simulation for a single variable.
///
/// Captures the variable's name, distribution, computed statistics,
/// and (for Bernoulli variables) its ternary truth assessment.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    /// Name of the variable that was simulated.
    pub variable_name: String,
    /// The distribution that was sampled.
    pub distribution: Distribution,
    /// Arithmetic mean of the sampled values.
    pub sample_mean: f64,
    /// Standard deviation of the sampled values.
    pub sample_std_dev: f64,
    /// Confidence interval computed from the samples.
    pub confidence_interval: ConfidenceInterval,
    /// For Bernoulli variables: the ternary truth assessment.
    /// True if p >= 0.9, False if p <= 0.1, Unknown otherwise.
    /// None for non-Bernoulli distributions.
    pub ternary_assessment: Option<TernaryBool>,
}

impl SimulationResult {
    /// Create a new simulation result for a continuous variable
    /// (Normal, Uniform, Beta, Custom).
    pub fn new_continuous(
        variable_name: String,
        distribution: Distribution,
        sample_mean: f64,
        sample_std_dev: f64,
        confidence_interval: ConfidenceInterval,
    ) -> Self {
        SimulationResult {
            variable_name,
            distribution,
            sample_mean,
            sample_std_dev,
            confidence_interval,
            ternary_assessment: None,
        }
    }

    /// Create a new simulation result for a Bernoulli variable,
    /// including a ternary truth assessment.
    ///
    /// The ternary assessment maps the observed proportion to Kleene logic:
    /// - proportion >= 0.9 => True (high confidence the event occurs)
    /// - proportion <= 0.1 => False (high confidence the event does not occur)
    /// - otherwise => Unknown (insufficient certainty)
    pub fn new_bernoulli(
        variable_name: String,
        distribution: Distribution,
        observed_proportion: f64,
        confidence_interval: ConfidenceInterval,
    ) -> Self {
        let ternary = if observed_proportion >= 0.9 {
            TernaryBool::True
        } else if observed_proportion <= 0.1 {
            TernaryBool::False
        } else {
            TernaryBool::Unknown
        };

        SimulationResult {
            variable_name,
            distribution,
            sample_mean: observed_proportion,
            sample_std_dev: (observed_proportion * (1.0 - observed_proportion)).sqrt(),
            confidence_interval,
            ternary_assessment: Some(ternary),
        }
    }
}

impl fmt::Display for SimulationResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}: mean={:.4}, std_dev={:.4}, CI={}",
            self.variable_name, self.sample_mean, self.sample_std_dev, self.confidence_interval
        )?;
        if let Some(ternary) = self.ternary_assessment {
            write!(f, ", ternary={}", ternary)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- Distribution tests ---

    #[test]
    fn test_normal_distribution_valid() {
        let d = Distribution::new_normal(0.0, 1.0).expect("TODO: handle error");
        assert_eq!(d.kind(), "normal");
        assert_eq!(
            d,
            Distribution::Normal {
                mean: 0.0,
                std_dev: 1.0
            }
        );
    }

    #[test]
    fn test_normal_distribution_invalid_std_dev() {
        assert!(Distribution::new_normal(0.0, 0.0).is_err());
        assert!(Distribution::new_normal(0.0, -1.0).is_err());
    }

    #[test]
    fn test_uniform_distribution_valid() {
        let d = Distribution::new_uniform(0.0, 10.0).expect("TODO: handle error");
        assert_eq!(d.kind(), "uniform");
    }

    #[test]
    fn test_uniform_distribution_invalid_range() {
        assert!(Distribution::new_uniform(10.0, 10.0).is_err());
        assert!(Distribution::new_uniform(10.0, 5.0).is_err());
    }

    #[test]
    fn test_beta_distribution_valid() {
        let d = Distribution::new_beta(2.0, 5.0).expect("TODO: handle error");
        assert_eq!(d.kind(), "beta");
    }

    #[test]
    fn test_beta_distribution_invalid_params() {
        assert!(Distribution::new_beta(0.0, 1.0).is_err());
        assert!(Distribution::new_beta(1.0, -1.0).is_err());
    }

    #[test]
    fn test_bernoulli_distribution_valid() {
        let d = Distribution::new_bernoulli(0.5).expect("TODO: handle error");
        assert_eq!(d.kind(), "bernoulli");
    }

    #[test]
    fn test_bernoulli_distribution_boundary_values() {
        // Boundary values 0.0 and 1.0 are valid.
        assert!(Distribution::new_bernoulli(0.0).is_ok());
        assert!(Distribution::new_bernoulli(1.0).is_ok());
        // Out of range is invalid.
        assert!(Distribution::new_bernoulli(-0.1).is_err());
        assert!(Distribution::new_bernoulli(1.1).is_err());
    }

    #[test]
    fn test_custom_distribution_valid() {
        let d = Distribution::new_custom("mixture(0.5, normal(0,1), normal(5,2))".to_string())
            .expect("TODO: handle error");
        assert_eq!(d.kind(), "custom");
    }

    #[test]
    fn test_custom_distribution_empty_rejected() {
        assert!(Distribution::new_custom("".to_string()).is_err());
    }

    // --- TernaryBool tests ---

    #[test]
    fn test_ternary_and() {
        // True AND x
        assert_eq!(TernaryBool::True.and(TernaryBool::True), TernaryBool::True);
        assert_eq!(
            TernaryBool::True.and(TernaryBool::False),
            TernaryBool::False
        );
        assert_eq!(
            TernaryBool::True.and(TernaryBool::Unknown),
            TernaryBool::Unknown
        );
        // False AND x (short-circuits to False)
        assert_eq!(
            TernaryBool::False.and(TernaryBool::True),
            TernaryBool::False
        );
        assert_eq!(
            TernaryBool::False.and(TernaryBool::False),
            TernaryBool::False
        );
        assert_eq!(
            TernaryBool::False.and(TernaryBool::Unknown),
            TernaryBool::False
        );
        // Unknown AND x
        assert_eq!(
            TernaryBool::Unknown.and(TernaryBool::True),
            TernaryBool::Unknown
        );
        assert_eq!(
            TernaryBool::Unknown.and(TernaryBool::False),
            TernaryBool::False
        );
        assert_eq!(
            TernaryBool::Unknown.and(TernaryBool::Unknown),
            TernaryBool::Unknown
        );
    }

    #[test]
    fn test_ternary_or() {
        // True OR x (short-circuits to True)
        assert_eq!(TernaryBool::True.or(TernaryBool::True), TernaryBool::True);
        assert_eq!(TernaryBool::True.or(TernaryBool::False), TernaryBool::True);
        assert_eq!(
            TernaryBool::True.or(TernaryBool::Unknown),
            TernaryBool::True
        );
        // False OR x
        assert_eq!(TernaryBool::False.or(TernaryBool::True), TernaryBool::True);
        assert_eq!(
            TernaryBool::False.or(TernaryBool::False),
            TernaryBool::False
        );
        assert_eq!(
            TernaryBool::False.or(TernaryBool::Unknown),
            TernaryBool::Unknown
        );
        // Unknown OR x
        assert_eq!(
            TernaryBool::Unknown.or(TernaryBool::True),
            TernaryBool::True
        );
        assert_eq!(
            TernaryBool::Unknown.or(TernaryBool::False),
            TernaryBool::Unknown
        );
        assert_eq!(
            TernaryBool::Unknown.or(TernaryBool::Unknown),
            TernaryBool::Unknown
        );
    }

    #[test]
    fn test_ternary_not() {
        assert_eq!(TernaryBool::True.not(), TernaryBool::False);
        assert_eq!(TernaryBool::False.not(), TernaryBool::True);
        assert_eq!(TernaryBool::Unknown.not(), TernaryBool::Unknown);
    }

    #[test]
    fn test_ternary_implies() {
        // True -> True = True
        assert_eq!(
            TernaryBool::True.implies(TernaryBool::True),
            TernaryBool::True
        );
        // True -> False = False
        assert_eq!(
            TernaryBool::True.implies(TernaryBool::False),
            TernaryBool::False
        );
        // False -> anything = True (ex falso quodlibet)
        assert_eq!(
            TernaryBool::False.implies(TernaryBool::True),
            TernaryBool::True
        );
        assert_eq!(
            TernaryBool::False.implies(TernaryBool::False),
            TernaryBool::True
        );
        assert_eq!(
            TernaryBool::False.implies(TernaryBool::Unknown),
            TernaryBool::True
        );
    }

    #[test]
    fn test_ternary_bool_conversion() {
        assert_eq!(TernaryBool::from_bool(true), TernaryBool::True);
        assert_eq!(TernaryBool::from_bool(false), TernaryBool::False);
        assert_eq!(TernaryBool::True.to_bool(), Some(true));
        assert_eq!(TernaryBool::False.to_bool(), Some(false));
        assert_eq!(TernaryBool::Unknown.to_bool(), None);
    }

    // --- ConfidenceInterval tests ---

    #[test]
    fn test_confidence_interval_valid() {
        let ci = ConfidenceInterval::new(1.0, 5.0, 0.95).expect("TODO: handle error");
        assert_eq!(ci.width(), 4.0);
        assert_eq!(ci.midpoint(), 3.0);
        assert!(ci.contains(3.0));
        assert!(!ci.contains(0.5));
    }

    #[test]
    fn test_confidence_interval_invalid_bounds() {
        assert!(ConfidenceInterval::new(5.0, 1.0, 0.95).is_err());
    }

    #[test]
    fn test_confidence_interval_invalid_confidence() {
        assert!(ConfidenceInterval::new(1.0, 5.0, 0.0).is_err());
        assert!(ConfidenceInterval::new(1.0, 5.0, 1.0).is_err());
        assert!(ConfidenceInterval::new(1.0, 5.0, -0.5).is_err());
    }

    #[test]
    fn test_confidence_interval_degenerate() {
        // A point interval (lower == upper) is valid.
        let ci = ConfidenceInterval::new(3.0, 3.0, 0.95).expect("TODO: handle error");
        assert_eq!(ci.width(), 0.0);
        assert!(ci.contains(3.0));
    }
}
