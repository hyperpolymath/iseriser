// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for mylangiser — core types representing the progressive-disclosure
// interface model. These types mirror the Idris2 formal proofs in src/interface/abi/
// and provide the Rust-side representations used throughout the codegen pipeline.
//
// The Idris2 ABI (Types.idr, Layout.idr, Foreign.idr) provides formal verification
// of these type relationships; this module is the Rust counterpart used at runtime.

use serde::{Deserialize, Serialize};

/// Disclosure level for a function/endpoint, determined by its complexity score.
///
/// - `Beginner`: Simple functions with few required params (score 0-30).
///   Only required parameters are exposed; all optionals get smart defaults.
/// - `Intermediate`: Moderate complexity (score 30-70). Required params plus
///   commonly-used optional params (scalar types, those with known defaults).
/// - `Expert`: Full API surface (score 70-100). Every parameter exposed,
///   no smart defaults applied.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DisclosureLevel {
    /// Simplified view: required params only, smart defaults for the rest.
    Beginner,
    /// Balanced view: required + commonly-used optional params.
    Intermediate,
    /// Full view: all parameters exposed, no defaults applied.
    Expert,
}

/// A complexity score in the range 0-100, representing how complex an
/// API endpoint is. The score is calculated from weighted factors:
/// parameter count, optional ratio, type complexity, and required count.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ComplexityScore {
    /// The numeric complexity value (0 = trivial, 100 = maximally complex).
    pub value: u32,
}

impl ComplexityScore {
    /// Create a new complexity score, clamping to the valid 0-100 range.
    pub fn new(value: u32) -> Self {
        Self {
            value: value.min(100),
        }
    }
}

impl std::fmt::Display for ComplexityScore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}/100", self.value)
    }
}

/// An API endpoint with its parsed metadata, complexity score, and
/// assigned disclosure level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct APIEndpoint {
    /// The endpoint/function name.
    pub name: String,
    /// Total number of parameters.
    pub param_count: usize,
    /// Number of required parameters.
    pub required_count: usize,
    /// Number of optional parameters.
    pub optional_count: usize,
    /// Calculated complexity score.
    pub complexity: ComplexityScore,
    /// Assigned disclosure level based on complexity thresholds.
    pub level: DisclosureLevel,
}

/// A smart default value applied to an optional parameter when it is
/// omitted at lower disclosure levels. The parameter name maps to the
/// default value (as a string representation).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SmartDefault {
    /// The parameter name this default applies to.
    pub param_name: String,
    /// The default value as a display string (e.g., `"user"`, `20`, `true`).
    pub default_value: String,
}

/// A layered wrapper for a single endpoint, containing the function
/// signatures and generated code for each disclosure level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayeredWrapper {
    /// The original endpoint name.
    pub endpoint_name: String,
    /// Beginner-level parameter list (required params only).
    pub beginner_signature: Vec<String>,
    /// Intermediate-level parameter list (required + common optional).
    pub intermediate_signature: Vec<String>,
    /// Expert-level parameter list (all params).
    pub expert_signature: Vec<String>,
    /// Smart defaults applied at beginner/intermediate levels.
    pub smart_defaults: Vec<SmartDefault>,
    /// Generated wrapper code for beginner level.
    pub beginner_code: String,
    /// Generated wrapper code for intermediate level.
    pub intermediate_code: String,
    /// Generated wrapper code for expert level.
    pub expert_code: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_complexity_score_clamped() {
        let score = ComplexityScore::new(150);
        assert_eq!(score.value, 100);
    }

    #[test]
    fn test_complexity_score_display() {
        let score = ComplexityScore::new(42);
        assert_eq!(format!("{}", score), "42/100");
    }

    #[test]
    fn test_disclosure_level_equality() {
        assert_eq!(DisclosureLevel::Beginner, DisclosureLevel::Beginner);
        assert_ne!(DisclosureLevel::Beginner, DisclosureLevel::Expert);
    }
}
