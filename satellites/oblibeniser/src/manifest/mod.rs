// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for oblibeniser — parses and validates the oblibeniser.toml
// configuration file. The manifest defines:
//   - [project]        : project-level metadata
//   - [[operations]]   : state-mutating operations and their inverse strategies
//   - [audit]          : hash-chained audit trail configuration
//   - [undo]           : undo/redo stack and time-travel settings

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::InverseStrategy;

/// Top-level manifest structure, corresponding to `oblibeniser.toml`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata: name, version, description.
    pub project: ProjectConfig,
    /// List of state-mutating operations that oblibeniser will make reversible.
    #[serde(default, rename = "operations")]
    pub operations: Vec<OperationDef>,
    /// Audit trail configuration (hash-chaining, storage, retention).
    #[serde(default)]
    pub audit: AuditConfig,
    /// Undo/redo stack configuration (depth limits, checkpointing).
    #[serde(default)]
    pub undo: UndoConfig,
}

/// `[project]` section — identifies the project being made reversible.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name (e.g., "my-database-layer").
    pub name: String,
    /// Semantic version of the project (e.g., "0.1.0").
    #[serde(default = "default_version")]
    pub version: String,
    /// Optional description of what the project does.
    #[serde(default)]
    pub description: String,
}

/// `[[operations]]` section — defines a single state-mutating operation.
/// Each operation has a forward function and a strategy for generating its inverse.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperationDef {
    /// Unique name for this operation (e.g., "insert_record").
    pub name: String,
    /// Path to the forward function (e.g., "db::insert" or "src/db.rs::insert").
    #[serde(rename = "forward-fn")]
    pub forward_fn: String,
    /// Parameter definitions as "name:type" strings (e.g., ["key:String", "value:Vec<u8>"]).
    #[serde(default)]
    pub params: Vec<String>,
    /// Strategy for generating the inverse: "mirror", "log-replay", or "snapshot".
    #[serde(rename = "inverse-strategy")]
    pub inverse_strategy: String,
}

impl OperationDef {
    /// Parse the inverse-strategy string into a typed InverseStrategy enum.
    /// Returns an error if the strategy is not recognised.
    pub fn parsed_strategy(&self) -> Result<InverseStrategy> {
        InverseStrategy::from_str_opt(&self.inverse_strategy).ok_or_else(|| {
            anyhow::anyhow!(
                "Unknown inverse-strategy '{}' for operation '{}'. \
                 Valid values: mirror, log-replay, snapshot",
                self.inverse_strategy,
                self.name
            )
        })
    }

    /// Parse the "name:type" parameter strings into (name, type) tuples.
    pub fn parsed_params(&self) -> Vec<(String, String)> {
        self.params
            .iter()
            .map(|p| {
                if let Some((name, typ)) = p.split_once(':') {
                    (name.trim().to_string(), typ.trim().to_string())
                } else {
                    (p.clone(), "unknown".to_string())
                }
            })
            .collect()
    }
}

/// `[audit]` section — configures the hash-chained audit trail.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditConfig {
    /// Whether to enable hash-chaining of audit entries (tamper-evidence).
    #[serde(rename = "hash-chain", default = "default_true")]
    pub hash_chain: bool,
    /// Storage backend: "file" persists to disk, "memory" is ephemeral.
    #[serde(default = "default_storage")]
    pub storage: String,
    /// Maximum number of audit entries to retain (0 = unlimited).
    #[serde(rename = "max-entries", default)]
    pub max_entries: usize,
}

impl Default for AuditConfig {
    fn default() -> Self {
        Self {
            hash_chain: true,
            storage: "file".to_string(),
            max_entries: 0,
        }
    }
}

/// `[undo]` section — configures the undo/redo stack and time-travel.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct UndoConfig {
    /// Maximum depth of the undo stack (0 = unlimited).
    #[serde(rename = "max-depth", default)]
    pub max_depth: usize,
    /// Number of operations between automatic state checkpoints (0 = disabled).
    #[serde(rename = "auto-checkpoint-interval", default)]
    pub auto_checkpoint_interval: usize,
}

// -- Default value helpers for serde --

fn default_version() -> String {
    "0.1.0".to_string()
}

fn default_true() -> bool {
    true
}

fn default_storage() -> String {
    "file".to_string()
}

/// Load and parse an oblibeniser.toml manifest from disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    parse_manifest(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Parse a manifest from a TOML string (useful for testing without disk I/O).
pub fn parse_manifest(content: &str) -> Result<Manifest> {
    toml::from_str(content).context("Invalid oblibeniser.toml format")
}

/// Validate a parsed manifest for logical consistency.
/// Checks: project name is present, operations have valid strategies,
/// storage is a recognised backend.
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }

    for op in &manifest.operations {
        if op.name.is_empty() {
            anyhow::bail!("Each [[operations]] entry must have a non-empty 'name'");
        }
        if op.forward_fn.is_empty() {
            anyhow::bail!("Operation '{}': forward-fn is required", op.name);
        }
        // Validate the inverse strategy is a known value.
        op.parsed_strategy()?;
    }

    // Validate audit storage backend.
    match manifest.audit.storage.as_str() {
        "file" | "memory" => {}
        other => anyhow::bail!(
            "Unknown audit.storage '{}'. Valid values: file, memory",
            other
        ),
    }

    Ok(())
}

/// Create a new default oblibeniser.toml manifest file at the given path.
pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("oblibeniser.toml");
    if p.exists() {
        anyhow::bail!("oblibeniser.toml already exists at {}", p.display());
    }

    let template = r#"# oblibeniser manifest — Make operations reversible via Oblíbený
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-project"
version = "0.1.0"
description = "Reversible operations for my project"

[[operations]]
name = "insert_record"
forward-fn = "db::insert"
params = ["key:String", "value:Vec<u8>"]
inverse-strategy = "mirror"

[[operations]]
name = "update_field"
forward-fn = "db::update"
params = ["id:u64", "field:String", "new_value:String"]
inverse-strategy = "log-replay"

[audit]
hash-chain = true
storage = "file"
max-entries = 10000

[undo]
max-depth = 100
auto-checkpoint-interval = 10
"#;

    std::fs::write(&p, template)?;
    println!("Created {}", p.display());
    Ok(())
}

/// Print a summary of the manifest to stdout.
pub fn print_info(m: &Manifest) {
    println!("=== {} v{} ===", m.project.name, m.project.version);
    if !m.project.description.is_empty() {
        println!("  {}", m.project.description);
    }
    println!("\nOperations ({}):", m.operations.len());
    for op in &m.operations {
        println!(
            "  - {} [{}] → {} (params: {})",
            op.name,
            op.inverse_strategy,
            op.forward_fn,
            op.params.join(", ")
        );
    }
    println!(
        "\nAudit: hash-chain={}, storage={}, max-entries={}",
        m.audit.hash_chain, m.audit.storage, m.audit.max_entries
    );
    println!(
        "Undo: max-depth={}, auto-checkpoint-interval={}",
        m.undo.max_depth, m.undo.auto_checkpoint_interval
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_minimal_manifest() {
        let toml = r#"
[project]
name = "test"

[[operations]]
name = "do_thing"
forward-fn = "mod::do_thing"
inverse-strategy = "mirror"
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert_eq!(m.project.name, "test");
        assert_eq!(m.operations.len(), 1);
        assert_eq!(m.operations[0].name, "do_thing");
    }

    #[test]
    fn test_parse_full_manifest() {
        let toml = r#"
[project]
name = "full-test"
version = "1.0.0"
description = "A fully configured project"

[[operations]]
name = "insert"
forward-fn = "db::insert"
params = ["key:String", "value:Vec<u8>"]
inverse-strategy = "mirror"

[[operations]]
name = "complex_update"
forward-fn = "db::update"
params = ["id:u64"]
inverse-strategy = "snapshot"

[audit]
hash-chain = true
storage = "memory"
max-entries = 500

[undo]
max-depth = 50
auto-checkpoint-interval = 5
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert_eq!(m.operations.len(), 2);
        assert_eq!(m.audit.storage, "memory");
        assert_eq!(m.audit.max_entries, 500);
        assert_eq!(m.undo.max_depth, 50);
        assert_eq!(m.undo.auto_checkpoint_interval, 5);
    }

    #[test]
    fn test_validate_empty_name_fails() {
        let toml = r#"
[project]
name = ""

[[operations]]
name = "op"
forward-fn = "fn"
inverse-strategy = "mirror"
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_bad_strategy_fails() {
        let toml = r#"
[project]
name = "test"

[[operations]]
name = "op"
forward-fn = "fn"
inverse-strategy = "teleport"
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_bad_storage_fails() {
        let toml = r#"
[project]
name = "test"

[audit]
storage = "cloud"
"#;
        let m = parse_manifest(toml).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_operation_parsed_params() {
        let op = OperationDef {
            name: "test".to_string(),
            forward_fn: "fn".to_string(),
            params: vec!["key:String".to_string(), "val:i64".to_string()],
            inverse_strategy: "mirror".to_string(),
        };
        let parsed = op.parsed_params();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0], ("key".to_string(), "String".to_string()));
        assert_eq!(parsed[1], ("val".to_string(), "i64".to_string()));
    }
}
