// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for mylangiser — parses and validates mylangiser.toml manifests
// that define API endpoints, complexity thresholds, and smart defaults for
// progressive-disclosure interface generation.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Top-level manifest structure representing a mylangiser.toml file.
/// Contains the project metadata, endpoint definitions, disclosure level
/// thresholds, and smart default values.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata (name, description).
    pub project: ProjectConfig,
    /// API endpoint definitions — each describes a function/endpoint with
    /// its parameters, required fields, and optional defaults.
    #[serde(default, rename = "endpoints")]
    pub endpoints: Vec<EndpointDef>,
    /// Disclosure level thresholds controlling how functions are bucketed
    /// into beginner/intermediate/expert tiers.
    #[serde(default)]
    pub levels: LevelConfig,
    /// Smart defaults applied when parameters are omitted at lower
    /// disclosure levels.
    #[serde(default)]
    pub defaults: HashMap<String, toml::Value>,
}

/// Project-level configuration — the `[project]` section of the manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name (used in generated wrapper module names).
    pub name: String,
    /// Optional project description.
    #[serde(default)]
    pub description: String,
}

/// A single API endpoint definition — one `[[endpoints]]` entry.
/// Describes a function with its parameter list, which parameters are
/// required, and any endpoint-specific metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndpointDef {
    /// The endpoint/function name (e.g., "create_user", "search").
    pub name: String,
    /// Parameter list in "name: type" or "name?: type" format.
    /// A trailing '?' on the name indicates the parameter is optional.
    #[serde(default)]
    pub params: Vec<String>,
    /// Names of parameters that are required (no '?' suffix).
    #[serde(default)]
    pub required: Vec<String>,
    /// Optional human-readable description of what this endpoint does.
    #[serde(default)]
    pub description: String,
}

/// Disclosure level thresholds — the `[levels]` section.
/// Complexity scores below `beginner_threshold` are beginner-tier,
/// above `expert_threshold` are expert-tier, and everything in between
/// is intermediate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LevelConfig {
    /// Maximum complexity score for beginner-level disclosure (inclusive).
    #[serde(rename = "beginner-threshold", default = "default_beginner_threshold")]
    pub beginner_threshold: u32,
    /// Minimum complexity score for expert-level disclosure (inclusive).
    #[serde(rename = "expert-threshold", default = "default_expert_threshold")]
    pub expert_threshold: u32,
}

/// Default beginner threshold: complexity score 0-30.
fn default_beginner_threshold() -> u32 {
    30
}

/// Default expert threshold: complexity score 70-100.
fn default_expert_threshold() -> u32 {
    70
}

impl Default for LevelConfig {
    fn default() -> Self {
        Self {
            beginner_threshold: default_beginner_threshold(),
            expert_threshold: default_expert_threshold(),
        }
    }
}

/// Load and deserialise a mylangiser.toml manifest from `path`.
///
/// # Errors
/// Returns an error if the file cannot be read or if the TOML is malformed.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content =
        std::fs::read_to_string(path).with_context(|| format!("Failed to read: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse: {}", path))
}

/// Validate a parsed manifest for structural correctness.
///
/// Checks:
/// - `project.name` is non-empty
/// - At least one endpoint is defined
/// - Each endpoint has a non-empty name and at least one parameter
/// - `beginner_threshold` < `expert_threshold`
/// - All `required` fields appear in the `params` list
///
/// # Errors
/// Returns an error describing the first validation failure encountered.
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }
    if manifest.endpoints.is_empty() {
        anyhow::bail!("at least one [[endpoints]] entry is required");
    }
    if manifest.levels.beginner_threshold >= manifest.levels.expert_threshold {
        anyhow::bail!(
            "beginner-threshold ({}) must be less than expert-threshold ({})",
            manifest.levels.beginner_threshold,
            manifest.levels.expert_threshold
        );
    }
    for ep in &manifest.endpoints {
        if ep.name.is_empty() {
            anyhow::bail!("endpoint name is required");
        }
        if ep.params.is_empty() {
            anyhow::bail!("endpoint '{}' must have at least one parameter", ep.name);
        }
        // Verify all required params exist in the params list (by base name).
        let param_names: Vec<String> = ep.params.iter().map(|p| extract_param_name(p)).collect();
        for req in &ep.required {
            if !param_names.contains(req) {
                anyhow::bail!(
                    "endpoint '{}': required param '{}' not found in params list",
                    ep.name,
                    req
                );
            }
        }
    }
    Ok(())
}

/// Extract the parameter name from a "name: type" or "name?: type" string.
/// Strips the trailing '?' and everything after the ':'.
pub fn extract_param_name(param_str: &str) -> String {
    let name_part = param_str.split(':').next().unwrap_or("").trim();
    name_part.trim_end_matches('?').to_string()
}

/// Create a new mylangiser.toml manifest at the given path with example
/// content demonstrating progressive-disclosure configuration.
///
/// # Errors
/// Returns an error if a manifest already exists or the file cannot be written.
pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("mylangiser.toml");
    if p.exists() {
        anyhow::bail!("mylangiser.toml already exists");
    }
    let template = r#"# SPDX-License-Identifier: MPL-2.0
# mylangiser manifest — progressive-disclosure interface definition

[project]
name = "my-api"
description = "Progressive-disclosure wrapper for my API"

[[endpoints]]
name = "create_user"
params = ["username: string", "email: string", "role?: string", "permissions?: list", "mfa?: bool", "locale?: string"]
required = ["username", "email"]

[[endpoints]]
name = "search"
params = ["query: string", "filters?: map", "sort?: string", "page?: int", "limit?: int"]
required = ["query"]

[levels]
beginner-threshold = 30
expert-threshold = 70

[defaults]
role = "user"
limit = 20
page = 1
locale = "en-GB"
"#;
    std::fs::write(&p, template)?;
    println!("Created {}", p.display());
    Ok(())
}

/// Print a summary of the manifest to stdout, including endpoint count,
/// disclosure thresholds, and configured defaults.
pub fn print_info(m: &Manifest) {
    println!("=== {} ===", m.project.name);
    if !m.project.description.is_empty() {
        println!("  {}", m.project.description);
    }
    println!("Endpoints: {}", m.endpoints.len());
    println!(
        "Levels: beginner < {}, intermediate {}-{}, expert > {}",
        m.levels.beginner_threshold,
        m.levels.beginner_threshold,
        m.levels.expert_threshold,
        m.levels.expert_threshold
    );
    if !m.defaults.is_empty() {
        println!("Defaults:");
        for (key, val) in &m.defaults {
            println!("  {} = {}", key, val);
        }
    }
    for ep in &m.endpoints {
        let optional_count = ep.params.len() - ep.required.len();
        println!(
            "  [{}] {} params ({} required, {} optional)",
            ep.name,
            ep.params.len(),
            ep.required.len(),
            optional_count
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_param_name_required() {
        assert_eq!(extract_param_name("username: string"), "username");
    }

    #[test]
    fn test_extract_param_name_optional() {
        assert_eq!(extract_param_name("role?: string"), "role");
    }

    #[test]
    fn test_validate_empty_name_fails() {
        let m = Manifest {
            project: ProjectConfig {
                name: String::new(),
                description: String::new(),
            },
            endpoints: vec![],
            levels: LevelConfig::default(),
            defaults: HashMap::new(),
        };
        assert!(validate(&m).is_err());
    }
}
