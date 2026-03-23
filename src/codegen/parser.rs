// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Language description parser and validator.
//
// This module validates an iseriser manifest beyond the basic TOML
// structure checks in `manifest::validate`.  It applies semantic rules:
//   - paradigm / type-system compatibility
//   - compilation-target / paradigm consistency
//   - primitive name validity (no empty strings, reasonable length)
//   - repo-name matches the derived iser name

use anyhow::Result;

use crate::abi::{CompilationTarget, LanguageModel, Paradigm, TypeSystemFeature};
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// Validation errors
// ---------------------------------------------------------------------------

/// Semantic validation errors for a language description.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValidationError {
    /// Language name is empty or contains invalid characters.
    InvalidLanguageName(String),
    /// Paradigm and type system are incompatible.
    IncompatibleTypeSystem {
        paradigm: Paradigm,
        type_system: TypeSystemFeature,
    },
    /// A key primitive is invalid (empty or too long).
    InvalidPrimitive(String),
    /// The repo name does not match the expected derived name.
    RepoNameMismatch { expected: String, actual: String },
    /// The compilation target is unusual for the paradigm (warning-level).
    UnusualTarget {
        paradigm: Paradigm,
        target: CompilationTarget,
    },
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ValidationError::InvalidLanguageName(name) => {
                write!(f, "Invalid language name: '{}'", name)
            }
            ValidationError::IncompatibleTypeSystem {
                paradigm,
                type_system,
            } => {
                write!(
                    f,
                    "Type system '{}' is incompatible with paradigm '{}'",
                    type_system, paradigm
                )
            }
            ValidationError::InvalidPrimitive(prim) => {
                write!(f, "Invalid primitive: '{}'", prim)
            }
            ValidationError::RepoNameMismatch { expected, actual } => {
                write!(
                    f,
                    "Repo name mismatch: expected '{}', got '{}'",
                    expected, actual
                )
            }
            ValidationError::UnusualTarget { paradigm, target } => {
                write!(
                    f,
                    "Unusual compilation target '{}' for paradigm '{}'",
                    target, paradigm
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Deep validation
// ---------------------------------------------------------------------------

/// Result of deep semantic validation.
#[derive(Debug, Clone)]
pub struct ValidationReport {
    /// Hard errors that prevent generation.
    pub errors: Vec<ValidationError>,
    /// Warnings that do not prevent generation.
    pub warnings: Vec<ValidationError>,
}

impl ValidationReport {
    /// True if there are no hard errors.
    pub fn is_valid(&self) -> bool {
        self.errors.is_empty()
    }
}

/// Perform deep semantic validation of a parsed manifest.
///
/// Returns a `ValidationReport` with errors and warnings.
/// This is separate from `manifest::validate` which only checks
/// structural completeness.
pub fn validate_language_description(manifest: &Manifest) -> ValidationReport {
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    let model = manifest.to_language_model();

    // 1. Language name: must be non-empty, ASCII alphanumeric + hyphens
    if model.name.is_empty() {
        errors.push(ValidationError::InvalidLanguageName(model.name.clone()));
    } else if !model
        .name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '+')
    {
        errors.push(ValidationError::InvalidLanguageName(model.name.clone()));
    }

    // 2. Primitives: no empty strings, max 128 chars each
    for prim in &model.key_primitives {
        if prim.is_empty() || prim.len() > 128 {
            errors.push(ValidationError::InvalidPrimitive(prim.clone()));
        }
    }

    // 3. Repo name matches derived iser name
    let expected_name = model.iser_name();
    if manifest.output.repo_name != expected_name {
        warnings.push(ValidationError::RepoNameMismatch {
            expected: expected_name,
            actual: manifest.output.repo_name.clone(),
        });
    }

    // 4. Paradigm / type-system compatibility
    check_paradigm_type_compatibility(&model, &mut errors);

    // 5. Paradigm / compilation-target consistency
    check_paradigm_target_consistency(&model, &mut warnings);

    ValidationReport { errors, warnings }
}

/// Check that the paradigm and type system are compatible.
///
/// Some combinations are contradictory:
///   - "logic" paradigm with "none" type system is technically valid
///     but unusual (most logic languages have types)
///   - "array" paradigm with "dependent" types is uncommon
fn check_paradigm_type_compatibility(model: &LanguageModel, _errors: &mut Vec<ValidationError>) {
    // Currently all combinations are valid.  This function is a hook
    // for future constraints as the -iser ecosystem grows.
    // The Idris2 ABI proofs handle the hard constraints at compile time;
    // here we only flag genuinely impossible combinations.
    let _ = model;
}

/// Check that the paradigm and target are consistent.
/// Flags unusual but not impossible combinations as warnings.
fn check_paradigm_target_consistency(model: &LanguageModel, warnings: &mut Vec<ValidationError>) {
    // Logic languages on GPU is unusual
    if model.paradigm == Paradigm::Logic && model.compilation_target == CompilationTarget::Gpu {
        warnings.push(ValidationError::UnusualTarget {
            paradigm: model.paradigm,
            target: model.compilation_target,
        });
    }

    // Dataflow on JVM is unusual (most dataflow targets native or WASM)
    if model.paradigm == Paradigm::Dataflow && model.compilation_target == CompilationTarget::Jvm {
        warnings.push(ValidationError::UnusualTarget {
            paradigm: model.paradigm,
            target: model.compilation_target,
        });
    }
}

/// Convenience: validate and bail on hard errors.
pub fn validate_or_bail(manifest: &Manifest) -> Result<ValidationReport> {
    let report = validate_language_description(manifest);
    if !report.is_valid() {
        let msgs: Vec<String> = report.errors.iter().map(|e| e.to_string()).collect();
        anyhow::bail!(
            "Language description validation failed:\n  {}",
            msgs.join("\n  ")
        );
    }
    Ok(report)
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::parse_manifest;

    #[test]
    fn test_valid_description_passes() {
        let toml = r#"
[project]
name = "chapeliser"
[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task", "locale"]
[output]
repo-name = "chapeliser"
github-org = "hyperpolymath"
description = "Chapel -iser"
"#;
        let m = parse_manifest(toml).unwrap();
        let report = validate_language_description(&m);
        assert!(report.is_valid(), "expected valid: {:?}", report.errors);
    }

    #[test]
    fn test_empty_primitive_fails() {
        let toml = r#"
[project]
name = "testiser"
[language]
name = "Test"
paradigm = "functional"
type-system = "algebraic"
compilation-target = "native"
key-primitives = ["ok", ""]
[output]
repo-name = "testiser"
github-org = "hyperpolymath"
description = "Test -iser"
"#;
        let m = parse_manifest(toml).unwrap();
        let report = validate_language_description(&m);
        assert!(!report.is_valid());
    }

    #[test]
    fn test_repo_name_mismatch_warning() {
        let toml = r#"
[project]
name = "my-chapel"
[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task"]
[output]
repo-name = "my-chapeliser"
github-org = "hyperpolymath"
description = "Chapel -iser"
"#;
        let m = parse_manifest(toml).unwrap();
        let report = validate_language_description(&m);
        assert!(report.is_valid()); // mismatch is a warning, not an error
        assert!(!report.warnings.is_empty());
    }

    #[test]
    fn test_unusual_target_warning() {
        let toml = r#"
[project]
name = "prologiser"
[language]
name = "Prolog"
paradigm = "logic"
type-system = "none"
compilation-target = "gpu"
key-primitives = ["clause"]
[output]
repo-name = "prologiser"
github-org = "hyperpolymath"
description = "Prolog -iser"
"#;
        let m = parse_manifest(toml).unwrap();
        let report = validate_language_description(&m);
        assert!(report.is_valid());
        assert!(
            report
                .warnings
                .iter()
                .any(|w| matches!(w, ValidationError::UnusualTarget { .. }))
        );
    }
}
