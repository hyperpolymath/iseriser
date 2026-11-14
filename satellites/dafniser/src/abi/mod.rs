// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for dafniser.
// Defines the core types for Dafny verification contracts: preconditions,
// postconditions, loop invariants, decreases clauses, function specifications,
// module structures, verification results, and target language selection.
// These types form the internal representation that the parser produces and
// the code generator consumes.

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Contract primitives
// ---------------------------------------------------------------------------

/// A precondition (Dafny `requires` clause).
/// Each precondition is a boolean expression that must hold on method entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Precondition {
    /// The Dafny expression, e.g. "sorted(arr)".
    pub expression: String,
    /// Optional human-readable description for diagnostics.
    pub description: Option<String>,
}

/// A postcondition (Dafny `ensures` clause).
/// Each postcondition is a boolean expression that must hold on method exit.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Postcondition {
    /// The Dafny expression, e.g. "result >= 0 ==> arr[result] == key".
    pub expression: String,
    /// Optional human-readable description for diagnostics.
    pub description: Option<String>,
}

/// A loop invariant (Dafny `invariant` clause).
/// Placed inside loop bodies to guide the verifier.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoopInvariant {
    /// The Dafny boolean expression that holds at every iteration.
    pub expression: String,
    /// Optional label identifying which loop this invariant belongs to.
    pub loop_label: Option<String>,
}

/// A decreases clause (Dafny `decreases` clause).
/// Proves termination by specifying an expression that strictly decreases
/// on each recursive call or loop iteration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DecreasesClause {
    /// The Dafny expression that decreases, e.g. "hi - lo" or "arr.Length".
    pub expression: String,
}

// ---------------------------------------------------------------------------
// Function / module structures
// ---------------------------------------------------------------------------

/// A single typed parameter in a Dafny method signature.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DafnyParam {
    /// Parameter name.
    pub name: String,
    /// Dafny type, e.g. "seq<int>", "int", "array<int>".
    pub dafny_type: String,
    /// Preconditions specific to this parameter (merged into method requires).
    pub requires: Vec<String>,
}

/// A Dafny return specification.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DafnyReturn {
    /// Dafny type of the return value.
    pub dafny_type: String,
    /// Postconditions (ensures clauses) referencing `result`.
    pub ensures: Vec<String>,
}

/// Complete specification for a single Dafny method or function.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DafnyFunction {
    /// Method/function name.
    pub name: String,
    /// Typed parameters.
    pub params: Vec<DafnyParam>,
    /// Return type and postconditions.
    pub returns: DafnyReturn,
    /// Global preconditions (in addition to per-parameter requires).
    pub preconditions: Vec<Precondition>,
    /// Global postconditions (in addition to per-return ensures).
    pub postconditions: Vec<Postcondition>,
    /// Decreases clause for termination proofs.
    pub decreases: Option<DecreasesClause>,
    /// Loop invariants used inside the method body.
    pub loop_invariants: Vec<LoopInvariant>,
    /// Whether this is a `function` (pure, ghost) or `method` (imperative).
    pub is_function: bool,
}

/// A Dafny module grouping related functions and predicates.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DafnyModule {
    /// Module name (becomes the Dafny `module Name { ... }` wrapper).
    pub name: String,
    /// Functions and methods contained in this module.
    pub functions: Vec<DafnyFunction>,
    /// Helper predicates the module defines (e.g. `sorted`, `multiset`).
    pub helper_predicates: Vec<String>,
}

// ---------------------------------------------------------------------------
// Verification result
// ---------------------------------------------------------------------------

/// Outcome of running the Dafny verifier on a function or module.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum VerificationResult {
    /// All assertions, pre/postconditions, and invariants verified.
    Verified {
        /// Name of the verified function/module.
        name: String,
        /// Wall-clock time in milliseconds.
        elapsed_ms: u64,
    },
    /// Verification failed with one or more diagnostics.
    Failed {
        /// Name of the function/module that failed.
        name: String,
        /// Diagnostic messages from the verifier.
        diagnostics: Vec<String>,
    },
    /// Verification exceeded the configured timeout.
    Timeout {
        /// Name of the function/module that timed out.
        name: String,
        /// Configured timeout in seconds.
        timeout_seconds: u32,
        /// Partial diagnostics emitted before timeout.
        diagnostics: Vec<String>,
    },
}

// ---------------------------------------------------------------------------
// Target language
// ---------------------------------------------------------------------------

/// Dafny compilation targets.
/// Dafny can compile verified code to several backend languages.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TargetLanguage {
    /// C# (.NET) backend.
    CSharp,
    /// Java backend.
    Java,
    /// Go backend.
    Go,
    /// Python backend.
    Python,
    /// JavaScript backend.
    #[serde(alias = "javascript")]
    Js,
}

impl TargetLanguage {
    /// Returns the Dafny CLI flag value for `--target`.
    pub fn dafny_target_flag(&self) -> &'static str {
        match self {
            TargetLanguage::CSharp => "cs",
            TargetLanguage::Java => "java",
            TargetLanguage::Go => "go",
            TargetLanguage::Python => "py",
            TargetLanguage::Js => "js",
        }
    }

    /// File extension for the generated output.
    pub fn file_extension(&self) -> &'static str {
        match self {
            TargetLanguage::CSharp => "cs",
            TargetLanguage::Java => "java",
            TargetLanguage::Go => "go",
            TargetLanguage::Python => "py",
            TargetLanguage::Js => "js",
        }
    }

    /// All supported targets (useful for validation).
    pub fn all() -> &'static [TargetLanguage] {
        &[
            TargetLanguage::CSharp,
            TargetLanguage::Java,
            TargetLanguage::Go,
            TargetLanguage::Python,
            TargetLanguage::Js,
        ]
    }
}

impl std::fmt::Display for TargetLanguage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.dafny_target_flag())
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_target_language_flag() {
        assert_eq!(TargetLanguage::Go.dafny_target_flag(), "go");
        assert_eq!(TargetLanguage::CSharp.dafny_target_flag(), "cs");
        assert_eq!(TargetLanguage::Python.dafny_target_flag(), "py");
    }

    #[test]
    fn test_all_targets_valid() {
        let targets = TargetLanguage::all();
        assert_eq!(targets.len(), 5);
        // Each target must have a non-empty flag and extension.
        for t in targets {
            assert!(!t.dafny_target_flag().is_empty());
            assert!(!t.file_extension().is_empty());
        }
    }

    #[test]
    fn test_verification_result_variants() {
        let verified = VerificationResult::Verified {
            name: "binary_search".into(),
            elapsed_ms: 42,
        };
        let failed = VerificationResult::Failed {
            name: "broken_fn".into(),
            diagnostics: vec!["postcondition might not hold".into()],
        };
        let timeout = VerificationResult::Timeout {
            name: "slow_fn".into(),
            timeout_seconds: 30,
            diagnostics: vec![],
        };
        // Ensure pattern matching works (no panic).
        assert!(matches!(verified, VerificationResult::Verified { .. }));
        assert!(matches!(failed, VerificationResult::Failed { .. }));
        assert!(matches!(timeout, VerificationResult::Timeout { .. }));
    }
}
