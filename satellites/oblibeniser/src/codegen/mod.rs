// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen module for oblibeniser — orchestrates parsing of manifest definitions,
// generation of inverse functions, and emission of audit trail code.
//
// Submodules:
//   - parser:      transforms manifest OperationDef → typed ReversibleOperation
//   - inverse_gen: generates inverse function code per strategy (mirror/log-replay/snapshot)
//   - audit_gen:   generates hash-chained audit trail module code

pub mod audit_gen;
pub mod inverse_gen;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all oblibeniser artifacts from a validated manifest.
/// Creates the output directory and writes:
///   - `inverses.rs`     — inverse functions for all operations
///   - `audit.rs`        — hash-chained audit trail module
///   - `verify_audit.rs` — standalone audit verification script
///   - `summary.txt`     — human-readable generation summary
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let output_path = Path::new(output_dir);
    fs::create_dir_all(output_path).context("Failed to create output directory")?;

    // Parse the manifest into typed structures.
    let parsed = parser::parse_manifest(manifest)
        .context("Failed to parse manifest into codegen structures")?;

    // Validate the parsed operations for logical consistency.
    parser::validate_operations(&parsed).context("Operation validation failed")?;

    // Generate inverse functions module.
    let inverse_module = inverse_gen::generate_inverse_module(&parsed)
        .context("Failed to generate inverse functions")?;
    let inverse_path = output_path.join("inverses.rs");
    fs::write(&inverse_path, &inverse_module)
        .with_context(|| format!("Failed to write {}", inverse_path.display()))?;
    println!("  [ok] Generated {}", inverse_path.display());

    // Generate audit trail module.
    let audit = audit_gen::generate_audit_module(&parsed)
        .context("Failed to generate audit trail module")?;
    let audit_path = output_path.join("audit.rs");
    fs::write(&audit_path, &audit.module_code)
        .with_context(|| format!("Failed to write {}", audit_path.display()))?;
    println!("  [ok] Generated {}", audit_path.display());

    // Generate audit verification script.
    let verify_script = audit_gen::generate_verification_script(&parsed);
    let verify_path = output_path.join("verify_audit.rs");
    fs::write(&verify_path, &verify_script)
        .with_context(|| format!("Failed to write {}", verify_path.display()))?;
    println!("  [ok] Generated {}", verify_path.display());

    // Write generation summary.
    let summary = generate_summary(&parsed, &audit);
    let summary_path = output_path.join("summary.txt");
    fs::write(&summary_path, &summary)
        .with_context(|| format!("Failed to write {}", summary_path.display()))?;
    println!("  [ok] Generated {}", summary_path.display());

    println!(
        "\n  oblibeniser: generated {} files for '{}' ({} operations)",
        4,
        parsed.project_name,
        parsed.operations.len()
    );

    Ok(())
}

/// Build the generated artifacts (compile check).
/// In Phase 1, this validates the manifest and reports readiness.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    let parsed = parser::parse_manifest(manifest)?;
    parser::validate_operations(&parsed)?;
    println!(
        "Build check passed for '{}': {} operations, audit={}, undo-depth={}",
        parsed.project_name,
        parsed.operations.len(),
        parsed.audit_storage,
        parsed.undo_max_depth
    );
    Ok(())
}

/// Run the workload (placeholder for Phase 1 — prints configuration summary).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    let parsed = parser::parse_manifest(manifest)?;
    println!(
        "Running oblibeniser workload '{}' with {} reversible operations",
        parsed.project_name,
        parsed.operations.len()
    );
    for op in &parsed.operations {
        println!(
            "  {} → {} (inverse: {}, strategy: {})",
            op.name, op.forward_fn, op.inverse_fn_name, op.inverse_strategy
        );
    }
    Ok(())
}

/// Generate a human-readable summary of what was generated.
fn generate_summary(parsed: &parser::ParsedManifest, audit: &audit_gen::GeneratedAudit) -> String {
    let mut summary = String::new();
    summary.push_str(&format!(
        "oblibeniser generation summary\n\
         ==============================\n\
         Project: {} v{}\n\
         Operations: {}\n\n",
        parsed.project_name,
        parsed.project_version,
        parsed.operations.len()
    ));

    for op in &parsed.operations {
        summary.push_str(&format!(
            "  {} → {} (strategy: {}, inverse: {})\n",
            op.name, op.forward_fn, op.inverse_strategy, op.inverse_fn_name
        ));
        for param in &op.params {
            summary.push_str(&format!(
                "    param: {}: {}\n",
                param.name, param.param_type
            ));
        }
    }

    summary.push_str(&format!(
        "\nAudit trail:\n  hash-chain: {}\n  storage: {}\n  max-entries: {}\n\nUndo stack:\n  max-depth: {}\n  auto-checkpoint-interval: {}\n",
        audit.hash_chain_enabled,
        audit.storage_backend,
        parsed.audit_max_entries,
        parsed.undo_max_depth,
        parsed.auto_checkpoint_interval,
    ));

    summary
}
