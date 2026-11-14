// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for dafniser.toml.
// Parses Dafny function specifications including pre/postconditions,
// decreases clauses, parameter types, return types, and compilation targets.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

// ---------------------------------------------------------------------------
// Top-level manifest
// ---------------------------------------------------------------------------

/// Top-level dafniser.toml manifest.
///
/// Contains the project metadata, function specifications, and Dafny
/// compilation settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    pub project: ProjectConfig,
    /// Function specifications with contracts.
    #[serde(default, rename = "functions")]
    pub functions: Vec<FunctionSpec>,
    /// Dafny compiler and verifier settings.
    #[serde(default)]
    pub dafny: DafnyConfig,
}

/// Project metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name.
    pub name: String,
    /// Optional description.
    #[serde(default)]
    pub description: Option<String>,
}

// ---------------------------------------------------------------------------
// Function specifications
// ---------------------------------------------------------------------------

/// A single function specification with typed parameters and contracts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionSpec {
    /// Function name (becomes the Dafny method name).
    pub name: String,
    /// Typed parameters, each optionally carrying a `requires` clause.
    pub params: Vec<ParamSpec>,
    /// Return type and postconditions.
    pub returns: ReturnSpec,
    /// Decreases clause expression for termination proof.
    #[serde(default)]
    pub decreases: Option<String>,
    /// Additional preconditions beyond per-parameter requires.
    #[serde(default)]
    pub requires: Vec<String>,
    /// Additional postconditions beyond per-return ensures.
    #[serde(default)]
    pub ensures: Vec<String>,
    /// Whether this is a pure Dafny `function` rather than a `method`.
    #[serde(default)]
    pub is_function: bool,
}

/// A typed parameter with optional precondition.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParamSpec {
    /// Parameter name.
    pub name: String,
    /// Dafny type expression (e.g. "seq<int>", "int", "array<int>").
    #[serde(rename = "type")]
    pub param_type: String,
    /// Precondition on this parameter (e.g. "sorted(arr)").
    #[serde(default)]
    pub requires: Option<String>,
}

/// Return type with postconditions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReturnSpec {
    /// Dafny type expression.
    #[serde(rename = "type")]
    pub return_type: String,
    /// Postcondition expression referencing `result`.
    #[serde(default)]
    pub ensures: Option<String>,
}

// ---------------------------------------------------------------------------
// Dafny configuration
// ---------------------------------------------------------------------------

/// Dafny compiler and verifier settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DafnyConfig {
    /// Compilation target language (csharp, java, go, python, js).
    #[serde(default = "default_target")]
    pub target: String,
    /// Verification timeout in seconds per function.
    #[serde(default = "default_verify_timeout", rename = "verify-timeout")]
    pub verify_timeout: u32,
    /// Extra flags passed to the Dafny CLI.
    #[serde(default)]
    pub extra_flags: Vec<String>,
}

impl Default for DafnyConfig {
    fn default() -> Self {
        Self {
            target: default_target(),
            verify_timeout: default_verify_timeout(),
            extra_flags: Vec::new(),
        }
    }
}

/// Default target language: C#.
fn default_target() -> String {
    "csharp".to_string()
}

/// Default verification timeout: 30 seconds.
fn default_verify_timeout() -> u32 {
    30
}

// ---------------------------------------------------------------------------
// Manifest operations
// ---------------------------------------------------------------------------

/// Load and deserialize a dafniser.toml manifest from disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a parsed manifest for required fields and consistency.
///
/// Checks:
/// - project.name is non-empty
/// - at least one function is defined
/// - every function has at least one parameter
/// - target language is recognised
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }
    if manifest.functions.is_empty() {
        anyhow::bail!("at least one [[functions]] entry is required");
    }
    for func in &manifest.functions {
        if func.name.is_empty() {
            anyhow::bail!("function name is required");
        }
        if func.params.is_empty() {
            anyhow::bail!("function '{}' must have at least one parameter", func.name);
        }
    }
    let valid_targets = ["csharp", "java", "go", "python", "js"];
    if !valid_targets.contains(&manifest.dafny.target.as_str()) {
        anyhow::bail!(
            "unknown target '{}'; valid targets: {}",
            manifest.dafny.target,
            valid_targets.join(", ")
        );
    }
    Ok(())
}

/// Create a new dafniser.toml manifest with Dafny function spec template.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("dafniser.toml");
    if manifest_path.exists() {
        anyhow::bail!("dafniser.toml already exists");
    }
    let template = r#"# SPDX-License-Identifier: MPL-2.0
# dafniser manifest — Dafny verified code generation

[project]
name = "my-verified-project"

[[functions]]
name = "binary_search"
params = [
  { name = "arr", type = "seq<int>", requires = "sorted(arr)" },
  { name = "key", type = "int" }
]
returns = { type = "int", ensures = "result >= 0 ==> arr[result] == key" }
decreases = "arr.Length"

[dafny]
target = "csharp"
verify-timeout = 30
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print a summary of the manifest to stdout.
pub fn print_info(manifest: &Manifest) {
    println!("=== {} ===", manifest.project.name);
    println!("Target:  {}", manifest.dafny.target);
    println!("Timeout: {}s", manifest.dafny.verify_timeout);
    println!("Functions ({}):", manifest.functions.len());
    for func in &manifest.functions {
        let param_list: Vec<String> = func
            .params
            .iter()
            .map(|p| format!("{}: {}", p.name, p.param_type))
            .collect();
        println!(
            "  {} ({}) -> {}",
            func.name,
            param_list.join(", "),
            func.returns.return_type
        );
        if let Some(dec) = &func.decreases {
            println!("    decreases {}", dec);
        }
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a minimal valid manifest for testing.
    fn sample_manifest() -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "test-project".to_string(),
                description: None,
            },
            functions: vec![FunctionSpec {
                name: "binary_search".to_string(),
                params: vec![
                    ParamSpec {
                        name: "arr".to_string(),
                        param_type: "seq<int>".to_string(),
                        requires: Some("sorted(arr)".to_string()),
                    },
                    ParamSpec {
                        name: "key".to_string(),
                        param_type: "int".to_string(),
                        requires: None,
                    },
                ],
                returns: ReturnSpec {
                    return_type: "int".to_string(),
                    ensures: Some("result >= 0 ==> arr[result] == key".to_string()),
                },
                decreases: Some("arr.Length".to_string()),
                requires: vec![],
                ensures: vec![],
                is_function: false,
            }],
            dafny: DafnyConfig::default(),
        }
    }

    #[test]
    fn test_validate_valid_manifest() {
        let m = sample_manifest();
        assert!(validate(&m).is_ok());
    }

    #[test]
    fn test_validate_empty_name() {
        let mut m = sample_manifest();
        m.project.name = String::new();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_no_functions() {
        let mut m = sample_manifest();
        m.functions.clear();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_bad_target() {
        let mut m = sample_manifest();
        m.dafny.target = "ruby".to_string();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_roundtrip_toml() {
        let m = sample_manifest();
        let serialized = toml::to_string(&m).expect("serialise");
        let deserialized: Manifest = toml::from_str(&serialized).expect("deserialise");
        assert_eq!(deserialized.project.name, m.project.name);
        assert_eq!(deserialized.functions.len(), 1);
        assert_eq!(deserialized.functions[0].name, "binary_search");
    }
}
