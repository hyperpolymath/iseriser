// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen parser — transforms manifest OperationDef entries into typed
// ReversibleOperation ABI structures ready for inverse generation and
// audit trail code emission.

use anyhow::{Context, Result};

use crate::abi::{InverseStrategy, OperationParam, ReversibleOperation};
use crate::manifest::{Manifest, OperationDef};

/// Parsed representation of the full manifest, ready for code generation.
/// Contains typed operation definitions and configuration extracted from the manifest.
#[derive(Debug, Clone)]
pub struct ParsedManifest {
    /// Project name from the manifest.
    pub project_name: String,
    /// Project version from the manifest.
    pub project_version: String,
    /// All operations parsed into typed ReversibleOperation structs.
    pub operations: Vec<ReversibleOperation>,
    /// Whether hash-chaining is enabled for the audit trail.
    pub hash_chain_enabled: bool,
    /// Audit storage backend ("file" or "memory").
    pub audit_storage: String,
    /// Maximum audit entries to retain.
    pub audit_max_entries: usize,
    /// Maximum undo stack depth.
    pub undo_max_depth: usize,
    /// Auto-checkpoint interval (operations between snapshots).
    pub auto_checkpoint_interval: usize,
}

/// Parse a single OperationDef from the manifest into a typed ReversibleOperation.
/// Validates the inverse strategy and parses "name:type" parameter strings.
fn parse_operation(op_def: &OperationDef) -> Result<ReversibleOperation> {
    let strategy = op_def
        .parsed_strategy()
        .with_context(|| format!("Parsing operation '{}'", op_def.name))?;

    let params: Vec<OperationParam> = op_def
        .parsed_params()
        .into_iter()
        .map(|(name, param_type)| OperationParam { name, param_type })
        .collect();

    Ok(ReversibleOperation::new(
        op_def.name.clone(),
        op_def.forward_fn.clone(),
        params,
        strategy,
    ))
}

/// Parse the entire manifest into a ParsedManifest ready for code generation.
/// This is the main entry point for the parser — it bridges between the
/// TOML-level manifest types and the ABI-level code generation types.
pub fn parse_manifest(manifest: &Manifest) -> Result<ParsedManifest> {
    let operations: Result<Vec<ReversibleOperation>> =
        manifest.operations.iter().map(parse_operation).collect();

    Ok(ParsedManifest {
        project_name: manifest.project.name.clone(),
        project_version: manifest.project.version.clone(),
        operations: operations?,
        hash_chain_enabled: manifest.audit.hash_chain,
        audit_storage: manifest.audit.storage.clone(),
        audit_max_entries: manifest.audit.max_entries,
        undo_max_depth: manifest.undo.max_depth,
        auto_checkpoint_interval: manifest.undo.auto_checkpoint_interval,
    })
}

/// Validate that parsed operations form a coherent set:
/// - No duplicate operation names.
/// - All mirror-strategy operations have at least one parameter.
/// - Parameter names are unique within each operation.
pub fn validate_operations(parsed: &ParsedManifest) -> Result<()> {
    let mut seen_names = std::collections::HashSet::new();
    for op in &parsed.operations {
        if !seen_names.insert(&op.name) {
            anyhow::bail!("Duplicate operation name: '{}'", op.name);
        }

        // Mirror strategy requires at least one parameter to derive an inverse from.
        if op.inverse_strategy == InverseStrategy::Mirror && op.params.is_empty() {
            anyhow::bail!(
                "Operation '{}' uses 'mirror' strategy but has no parameters. \
                 Mirror requires parameters to derive an algebraic inverse.",
                op.name
            );
        }

        // Check for duplicate parameter names within an operation.
        let mut param_names = std::collections::HashSet::new();
        for param in &op.params {
            if !param_names.insert(&param.name) {
                anyhow::bail!(
                    "Operation '{}' has duplicate parameter name: '{}'",
                    op.name,
                    param.name
                );
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest;

    #[test]
    fn test_parse_manifest_roundtrip() {
        let toml = r#"
[project]
name = "test-project"
version = "1.0.0"

[[operations]]
name = "insert"
forward-fn = "db::insert"
params = ["key:String", "value:Vec<u8>"]
inverse-strategy = "mirror"

[[operations]]
name = "backup"
forward-fn = "sys::backup"
inverse-strategy = "snapshot"
"#;
        let m = manifest::parse_manifest(toml).expect("TODO: handle error");
        let parsed = parse_manifest(&m).expect("TODO: handle error");
        assert_eq!(parsed.project_name, "test-project");
        assert_eq!(parsed.operations.len(), 2);
        assert_eq!(parsed.operations[0].params.len(), 2);
        assert_eq!(parsed.operations[0].inverse_fn_name, "insert_inverse");
        assert_eq!(
            parsed.operations[0].inverse_strategy,
            InverseStrategy::Mirror
        );
    }

    #[test]
    fn test_validate_duplicate_names() {
        let toml = r#"
[project]
name = "test"

[[operations]]
name = "same_name"
forward-fn = "a::b"
params = ["x:i32"]
inverse-strategy = "mirror"

[[operations]]
name = "same_name"
forward-fn = "c::d"
params = ["y:i32"]
inverse-strategy = "mirror"
"#;
        let m = manifest::parse_manifest(toml).expect("TODO: handle error");
        let parsed = parse_manifest(&m).expect("TODO: handle error");
        assert!(validate_operations(&parsed).is_err());
    }

    #[test]
    fn test_validate_mirror_needs_params() {
        let toml = r#"
[project]
name = "test"

[[operations]]
name = "empty_mirror"
forward-fn = "a::b"
inverse-strategy = "mirror"
"#;
        let m = manifest::parse_manifest(toml).expect("TODO: handle error");
        let parsed = parse_manifest(&m).expect("TODO: handle error");
        assert!(validate_operations(&parsed).is_err());
    }
}
