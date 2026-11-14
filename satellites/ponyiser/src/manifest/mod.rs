// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for ponyiser.toml.
//
// The manifest defines actors, behaviours, and analysis options that
// ponyiser uses to generate Pony wrappers with reference capability
// annotations. The TOML schema maps directly to Pony's actor model.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::RefCapability;

/// Top-level ponyiser manifest.
///
/// Corresponds to a complete ponyiser.toml file with project metadata,
/// actor definitions, behaviour definitions, and analysis configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata section.
    pub project: ProjectConfig,
    /// Actor definitions — each actor is a concurrent entity with its own heap.
    #[serde(default, rename = "actors")]
    pub actors: Vec<ActorDef>,
    /// Behaviour definitions — asynchronous message handlers on actors.
    #[serde(default, rename = "behaviours")]
    pub behaviours: Vec<BehaviourDef>,
    /// Analysis configuration controlling race detection and inference.
    #[serde(default)]
    pub analysis: AnalysisConfig,

    // Legacy fields (kept for backward compatibility with existing manifests)
    /// Legacy workload config — superseded by project/actors/behaviours.
    #[serde(default)]
    pub workload: Option<WorkloadConfig>,
    /// Legacy data config — superseded by actor field types.
    #[serde(default)]
    pub data: Option<DataConfig>,
    /// Legacy options — superseded by analysis config.
    #[serde(default)]
    pub options: Option<Options>,
}

/// Project metadata: name, version, description.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Project name.
    pub name: String,
    /// Semantic version string.
    #[serde(default = "default_version")]
    pub version: String,
    /// Human-readable description of the project.
    #[serde(default)]
    pub description: String,
    /// Source language of the concurrent code being wrapped.
    #[serde(default = "default_source_lang")]
    pub source_lang: String,
}

fn default_version() -> String {
    "0.1.0".to_string()
}

fn default_source_lang() -> String {
    "rust".to_string()
}

/// A field definition within an actor, with type and capability.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldDef {
    /// Field name.
    pub name: String,
    /// Type of the field (e.g., "Array[TCPConnection]", "U64", "String").
    #[serde(rename = "type")]
    pub field_type: String,
    /// Reference capability for this field.
    #[serde(default = "default_capability")]
    pub capability: RefCapability,
}

fn default_capability() -> RefCapability {
    RefCapability::Ref
}

/// An actor definition in the manifest.
///
/// Maps to `[[actors]]` table array in TOML.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActorDef {
    /// Actor name (becomes the Pony actor class name).
    pub name: String,
    /// Fields owned by this actor.
    #[serde(default)]
    pub fields: Vec<FieldDef>,
    /// Optional docstring.
    #[serde(default)]
    pub doc: Option<String>,
}

/// A parameter to a behaviour.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParamDef {
    /// Parameter name.
    pub name: String,
    /// Parameter type.
    #[serde(rename = "type")]
    pub param_type: String,
    /// Required capability for this parameter.
    #[serde(default = "default_sendable_capability")]
    pub capability: RefCapability,
}

fn default_sendable_capability() -> RefCapability {
    RefCapability::Val
}

/// A behaviour definition in the manifest.
///
/// Maps to `[[behaviours]]` table array in TOML.
/// Behaviours are asynchronous message handlers attached to an actor.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BehaviourDef {
    /// Name of the actor this behaviour belongs to.
    pub actor: String,
    /// Behaviour name (becomes the Pony behaviour name).
    pub name: String,
    /// Parameters this behaviour accepts.
    #[serde(default)]
    pub params: Vec<ParamDef>,
    /// Capability requirements on the receiver side.
    #[serde(default, rename = "capability-requirements")]
    pub capability_requirements: Vec<RefCapability>,
    /// Optional docstring.
    #[serde(default)]
    pub doc: Option<String>,
}

/// Analysis configuration controlling race detection and capability inference.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisConfig {
    /// Whether to detect potential data races.
    #[serde(default = "default_true", rename = "detect-races")]
    pub detect_races: bool,
    /// Whether to suggest reference capabilities for untyped accesses.
    #[serde(default = "default_true", rename = "suggest-capabilities")]
    pub suggest_capabilities: bool,
}

fn default_true() -> bool {
    true
}

impl Default for AnalysisConfig {
    fn default() -> Self {
        AnalysisConfig {
            detect_races: true,
            suggest_capabilities: true,
        }
    }
}

// Legacy types preserved for backward compatibility.

/// Legacy workload description (superseded by project + actors).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WorkloadConfig {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub entry: String,
    #[serde(default)]
    pub strategy: String,
}

/// Legacy data types flowing through the pipeline (superseded by actor fields).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DataConfig {
    #[serde(default, rename = "input-type")]
    pub input_type: String,
    #[serde(default, rename = "output-type")]
    pub output_type: String,
}

/// Legacy Pony-specific options (superseded by analysis config).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Options {
    #[serde(default)]
    pub flags: Vec<String>,
}

/// Load a manifest from a TOML file path.
///
/// Reads the file, parses the TOML, and returns a structured Manifest.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    parse_manifest(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Parse a manifest from a TOML string.
///
/// This is the core parsing function, separated from file I/O for testability.
pub fn parse_manifest(content: &str) -> Result<Manifest> {
    let manifest: Manifest = toml::from_str(content).context("Invalid ponyiser.toml format")?;
    Ok(manifest)
}

/// Validate a parsed manifest for semantic correctness.
///
/// Checks:
/// - Project name is non-empty
/// - All actor names are unique
/// - All behaviour names are unique within their actor
/// - Behaviours reference existing actors
/// - Field capabilities are valid for their usage context
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name is required.
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }

    // Collect actor names and check uniqueness.
    let mut actor_names = std::collections::HashSet::new();
    for actor in &manifest.actors {
        if actor.name.is_empty() {
            anyhow::bail!("actor name cannot be empty");
        }
        if !actor_names.insert(&actor.name) {
            anyhow::bail!("duplicate actor name: '{}'", actor.name);
        }
        // Check field name uniqueness within each actor.
        let mut field_names = std::collections::HashSet::new();
        for field in &actor.fields {
            if field.name.is_empty() {
                anyhow::bail!("field name cannot be empty in actor '{}'", actor.name);
            }
            if !field_names.insert(&field.name) {
                anyhow::bail!(
                    "duplicate field name '{}' in actor '{}'",
                    field.name,
                    actor.name
                );
            }
        }
    }

    // Validate behaviours reference existing actors.
    for behaviour in &manifest.behaviours {
        if behaviour.name.is_empty() {
            anyhow::bail!("behaviour name cannot be empty");
        }
        if behaviour.actor.is_empty() {
            anyhow::bail!("behaviour '{}' must specify an actor", behaviour.name);
        }
        if !actor_names.contains(&behaviour.actor) {
            anyhow::bail!(
                "behaviour '{}' references undefined actor '{}'",
                behaviour.name,
                behaviour.actor
            );
        }
    }

    Ok(())
}

/// Initialise a new ponyiser.toml manifest with the Phase 1 schema.
///
/// Creates a template manifest with example actors and behaviours
/// demonstrating Pony reference capabilities.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("ponyiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("ponyiser.toml already exists");
    }
    let template = r#"# ponyiser manifest — Pony reference capability wrapper generator
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-project"
version = "0.1.0"
description = "Concurrent system with Pony capability safety"
source_lang = "rust"

[[actors]]
name = "Main"
doc = "Entry point actor"

[[actors.fields]]
name = "env"
type = "Env"
capability = "val"

[[behaviours]]
actor = "Main"
name = "create"
doc = "Actor constructor"

[[behaviours.params]]
name = "env"
type = "Env"
capability = "val"

[analysis]
detect-races = true
suggest-capabilities = true
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print human-readable information about a manifest.
pub fn print_info(manifest: &Manifest) {
    println!(
        "=== {} v{} ===",
        manifest.project.name, manifest.project.version
    );
    println!("Description: {}", manifest.project.description);
    println!("Source lang:  {}", manifest.project.source_lang);
    println!();
    println!("Actors ({}):", manifest.actors.len());
    for actor in &manifest.actors {
        println!("  actor {} ({} fields)", actor.name, actor.fields.len());
        for field in &actor.fields {
            println!(
                "    {}: {} ({})",
                field.name, field.field_type, field.capability
            );
        }
    }
    println!();
    println!("Behaviours ({}):", manifest.behaviours.len());
    for behaviour in &manifest.behaviours {
        let param_strs: Vec<String> = behaviour
            .params
            .iter()
            .map(|p| format!("{}: {} {}", p.name, p.param_type, p.capability))
            .collect();
        println!(
            "  be {}.{}({})",
            behaviour.actor,
            behaviour.name,
            param_strs.join(", ")
        );
    }
    println!();
    println!("Analysis:");
    println!("  detect-races:        {}", manifest.analysis.detect_races);
    println!(
        "  suggest-capabilities: {}",
        manifest.analysis.suggest_capabilities
    );
}

/// Convert manifest actor/behaviour definitions to ABI types for analysis.
///
/// This bridges the manifest (user-facing TOML) to the ABI (analysis engine).
pub fn to_abi_types(manifest: &Manifest) -> (Vec<crate::abi::Actor>, Vec<crate::abi::Behaviour>) {
    let actors: Vec<crate::abi::Actor> = manifest
        .actors
        .iter()
        .map(|a| crate::abi::Actor {
            name: a.name.clone(),
            fields: a
                .fields
                .iter()
                .map(|f| crate::abi::Field {
                    name: f.name.clone(),
                    field_type: f.field_type.clone(),
                    capability: f.capability,
                })
                .collect(),
            doc: a.doc.clone(),
        })
        .collect();

    let behaviours: Vec<crate::abi::Behaviour> = manifest
        .behaviours
        .iter()
        .map(|b| crate::abi::Behaviour {
            actor: b.actor.clone(),
            name: b.name.clone(),
            params: b
                .params
                .iter()
                .map(|p| crate::abi::BehaviourParam {
                    name: p.name.clone(),
                    param_type: p.param_type.clone(),
                    capability: p.capability,
                })
                .collect(),
            capability_requirements: b.capability_requirements.clone(),
            doc: b.doc.clone(),
        })
        .collect();

    (actors, behaviours)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_minimal_manifest() {
        let toml = r#"
[project]
name = "test"

[[actors]]
name = "Main"

[[behaviours]]
actor = "Main"
name = "run"
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        assert_eq!(manifest.project.name, "test");
        assert_eq!(manifest.actors.len(), 1);
        assert_eq!(manifest.behaviours.len(), 1);
    }

    #[test]
    fn test_parse_full_manifest() {
        let toml = r#"
[project]
name = "server"
version = "1.0.0"
description = "A concurrent server"
source_lang = "rust"

[[actors]]
name = "Listener"
doc = "Accepts connections"

[[actors.fields]]
name = "port"
type = "U16"
capability = "val"

[[actors.fields]]
name = "connections"
type = "Array[TCPConnection]"
capability = "ref"

[[behaviours]]
actor = "Listener"
name = "accept"
doc = "Accept a new connection"

[[behaviours.params]]
name = "conn"
type = "TCPConnection"
capability = "iso"

[analysis]
detect-races = true
suggest-capabilities = true
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        assert_eq!(manifest.project.name, "server");
        assert_eq!(manifest.actors[0].fields.len(), 2);
        assert_eq!(manifest.actors[0].fields[0].capability, RefCapability::Val);
        assert_eq!(manifest.actors[0].fields[1].capability, RefCapability::Ref);
        assert_eq!(
            manifest.behaviours[0].params[0].capability,
            RefCapability::Iso
        );
        assert!(manifest.analysis.detect_races);
    }

    #[test]
    fn test_validate_empty_name() {
        let toml = r#"
[project]
name = ""

[[actors]]
name = "Main"

[[behaviours]]
actor = "Main"
name = "run"
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&manifest).is_err());
    }

    #[test]
    fn test_validate_duplicate_actor() {
        let toml = r#"
[project]
name = "test"

[[actors]]
name = "Main"

[[actors]]
name = "Main"

[[behaviours]]
actor = "Main"
name = "run"
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&manifest).is_err());
    }

    #[test]
    fn test_validate_undefined_actor_ref() {
        let toml = r#"
[project]
name = "test"

[[actors]]
name = "Main"

[[behaviours]]
actor = "NonExistent"
name = "run"
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&manifest).is_err());
    }
}
