// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for iseriser.toml.
//
// The iseriser manifest has three sections:
//   [project]   — metadata about the iseriser invocation
//   [language]  — describes the target language to generate an -iser for
//   [output]    — controls where and how the generated repo is written
//
// Example:
//   [project]
//   name = "chapeliser"
//   version = "0.1.0"
//
//   [language]
//   name = "Chapel"
//   paradigm = "imperative"
//   type-system = "simple"
//   compilation-target = "native"
//   key-primitives = ["task", "locale", "domain", "forall", "sync"]
//
//   [output]
//   repo-name = "chapeliser"
//   github-org = "hyperpolymath"
//   description = "Chapel interop -iser"

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::{CompilationTarget, LanguageModel, Paradigm, TypeSystemFeature};

// ---------------------------------------------------------------------------
// Manifest structures
// ---------------------------------------------------------------------------

/// Top-level iseriser manifest (iseriser.toml).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    pub project: ProjectConfig,
    /// Description of the target language.
    pub language: LanguageConfig,
    /// Output configuration for the generated repo.
    pub output: OutputConfig,
}

/// `[project]` section — metadata about this iseriser invocation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name (often matches output.repo-name).
    pub name: String,
    /// Semantic version for the generated -iser.
    #[serde(default = "default_version")]
    pub version: String,
}

/// `[language]` section — describes the target language.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LanguageConfig {
    /// Language name (e.g. "Chapel", "Julia", "BQN").
    pub name: String,
    /// Primary paradigm: functional, imperative, array, logic, dataflow.
    pub paradigm: Paradigm,
    /// Type system classification.
    #[serde(rename = "type-system")]
    pub type_system: TypeSystemFeature,
    /// Compilation target: native, jvm, beam, wasm, js, interpreted, gpu.
    #[serde(rename = "compilation-target")]
    pub compilation_target: CompilationTarget,
    /// Key primitives that need FFI bindings.
    #[serde(rename = "key-primitives")]
    pub key_primitives: Vec<String>,
}

/// `[output]` section — controls the generated repository.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutputConfig {
    /// Name of the generated repo (e.g. "chapeliser").
    #[serde(rename = "repo-name")]
    pub repo_name: String,
    /// GitHub organisation or user (e.g. "hyperpolymath").
    #[serde(rename = "github-org")]
    pub github_org: String,
    /// One-line description for the repo.
    pub description: String,
}

/// Default version when omitted.
fn default_version() -> String {
    "0.1.0".to_string()
}

// ---------------------------------------------------------------------------
// Conversion: Manifest -> LanguageModel (ABI type)
// ---------------------------------------------------------------------------

impl Manifest {
    /// Convert the manifest language section into the ABI `LanguageModel`.
    pub fn to_language_model(&self) -> LanguageModel {
        LanguageModel {
            name: self.language.name.clone(),
            paradigm: self.language.paradigm,
            type_system: self.language.type_system,
            compilation_target: self.language.compilation_target,
            key_primitives: self.language.key_primitives.clone(),
        }
    }
}

// ---------------------------------------------------------------------------
// Loading and validation
// ---------------------------------------------------------------------------

/// Load and deserialise an iseriser manifest from a file path.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    parse_manifest(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Parse a manifest from a TOML string (useful for testing).
pub fn parse_manifest(toml_str: &str) -> Result<Manifest> {
    toml::from_str(toml_str).with_context(|| "Invalid TOML in manifest")
}

/// Validate a parsed manifest, returning a descriptive error on failure.
///
/// Validation rules:
///   - project.name must not be empty
///   - language.name must not be empty
///   - language.key-primitives must have at least one entry
///   - output.repo-name must not be empty
///   - output.repo-name must end with "iser"
///   - output.github-org must not be empty
///   - output.description must not be empty
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }
    if manifest.language.name.is_empty() {
        anyhow::bail!("language.name is required");
    }
    if manifest.language.key_primitives.is_empty() {
        anyhow::bail!("language.key-primitives must have at least one entry");
    }
    if manifest.output.repo_name.is_empty() {
        anyhow::bail!("output.repo-name is required");
    }
    if !manifest.output.repo_name.ends_with("iser") {
        anyhow::bail!(
            "output.repo-name '{}' must end with 'iser'",
            manifest.output.repo_name
        );
    }
    if manifest.output.github_org.is_empty() {
        anyhow::bail!("output.github-org is required");
    }
    if manifest.output.description.is_empty() {
        anyhow::bail!("output.description is required");
    }
    Ok(())
}

/// Write a starter iseriser.toml manifest into the given directory.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("iseriser.toml");
    if manifest_path.exists() {
        anyhow::bail!(
            "iseriser.toml already exists at {}",
            manifest_path.display()
        );
    }
    let template = r#"# iseriser manifest — describe a target language to generate an -iser for.
# SPDX-License-Identifier: PMPL-1.0-or-later

[project]
name = "newlangiser"
version = "0.1.0"

[language]
name = "NewLang"
paradigm = "functional"
type-system = "algebraic"
compilation-target = "native"
key-primitives = ["atom", "channel", "record"]

[output]
repo-name = "newlangiser"
github-org = "hyperpolymath"
description = "NewLang interop -iser — generated by iseriser"
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print human-readable information about a manifest.
pub fn print_info(manifest: &Manifest) {
    println!("=== {} ===", manifest.project.name);
    println!("Version:    {}", manifest.project.version);
    println!();
    println!("[language]");
    println!("  Name:       {}", manifest.language.name);
    println!("  Paradigm:   {}", manifest.language.paradigm);
    println!("  Type sys:   {}", manifest.language.type_system);
    println!("  Target:     {}", manifest.language.compilation_target);
    println!(
        "  Primitives: {}",
        manifest.language.key_primitives.join(", ")
    );
    println!();
    println!("[output]");
    println!("  Repo:   {}", manifest.output.repo_name);
    println!("  Org:    {}", manifest.output.github_org);
    println!("  Desc:   {}", manifest.output.description);
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal valid manifest TOML for testing.
    pub fn valid_toml() -> &'static str {
        r#"
[project]
name = "chapeliser"
version = "0.1.0"

[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task", "locale", "domain"]

[output]
repo-name = "chapeliser"
github-org = "hyperpolymath"
description = "Chapel distributed computing -iser"
"#
    }

    #[test]
    fn test_parse_valid_manifest() {
        let m = parse_manifest(valid_toml()).expect("should parse");
        assert_eq!(m.language.name, "Chapel");
        assert_eq!(m.language.paradigm, Paradigm::Imperative);
        assert_eq!(m.language.type_system, TypeSystemFeature::Simple);
        assert_eq!(m.language.compilation_target, CompilationTarget::Native);
        assert_eq!(m.language.key_primitives.len(), 3);
    }

    #[test]
    fn test_validate_valid_manifest() {
        let m = parse_manifest(valid_toml()).unwrap();
        validate(&m).expect("should validate");
    }

    #[test]
    fn test_validate_missing_name() {
        let toml = r#"
[project]
name = ""

[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task"]

[output]
repo-name = "chapeliser"
github-org = "hyperpolymath"
description = "test"
"#;
        let m = parse_manifest(toml).unwrap();
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("project.name"));
    }

    #[test]
    fn test_validate_bad_repo_name() {
        let toml = r#"
[project]
name = "chapel"

[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task"]

[output]
repo-name = "chapel-tool"
github-org = "hyperpolymath"
description = "test"
"#;
        let m = parse_manifest(toml).unwrap();
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("iser"));
    }

    #[test]
    fn test_to_language_model() {
        let m = parse_manifest(valid_toml()).unwrap();
        let lm = m.to_language_model();
        assert_eq!(lm.name, "Chapel");
        assert_eq!(lm.iser_name(), "chapeliser");
        assert_eq!(lm.calling_convention(), "c");
    }
}
