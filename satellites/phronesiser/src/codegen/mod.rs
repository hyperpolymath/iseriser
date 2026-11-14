// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen module for phronesiser — orchestrates parsing, engine construction,
// and audit trail generation from a phronesiser manifest.

pub mod audit;
pub mod engine;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;

use crate::manifest::Manifest;

/// Generate all Phase 1 artifacts from a validated manifest.
///
/// Writes to `output_dir`:
/// - `constraints.json`: The parsed constraint set in JSON format.
/// - `engine_config.json`: Engine configuration (mode, thresholds).
/// - `README.txt`: A human-readable summary of the generated constraint engine.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir).context("Failed to create output dir")?;

    // Parse constraints into ABI-level types.
    let parsed = parser::parse_constraints(manifest)?;

    // Write parsed constraints as JSON.
    let constraints_json = serde_json::to_string_pretty(&parsed.constraints)
        .context("Failed to serialize constraints")?;
    let constraints_path = format!("{}/constraints.json", output_dir);
    fs::write(&constraints_path, &constraints_json)
        .with_context(|| format!("Failed to write {}", constraints_path))?;
    println!("  [codegen] Wrote {}", constraints_path);

    // Write engine configuration.
    let engine_config = serde_json::json!({
        "enforcement_mode": format!("{}", manifest.enforcement.mode),
        "escalation_threshold": manifest.enforcement.escalation_threshold,
        "audit_log": manifest.enforcement.audit_log,
        "agent_name": manifest.agent.name,
        "agent_capabilities": manifest.agent.capabilities,
        "constraint_count": parsed.constraints.len(),
    });
    let config_path = format!("{}/engine_config.json", output_dir);
    fs::write(
        &config_path,
        serde_json::to_string_pretty(&engine_config).expect("TODO: handle error"),
    )
    .with_context(|| format!("Failed to write {}", config_path))?;
    println!("  [codegen] Wrote {}", config_path);

    // Write human-readable summary.
    let summary = generate_summary(manifest, &parsed);
    let summary_path = format!("{}/README.txt", output_dir);
    fs::write(&summary_path, &summary)
        .with_context(|| format!("Failed to write {}", summary_path))?;
    println!("  [codegen] Wrote {}", summary_path);

    println!(
        "  [codegen] Generated {} constraint(s) for agent '{}'",
        parsed.constraints.len(),
        parsed.agent_name
    );

    Ok(())
}

/// Build the generated artifacts (currently a validation pass).
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    let parsed = parser::parse_constraints(manifest)?;
    println!(
        "Building phronesiser constraint engine: {} constraint(s) for '{}'",
        parsed.constraints.len(),
        parsed.agent_name
    );
    // Construct the engine to verify it can be built.
    let _engine = engine::ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );
    println!("  [build] Constraint engine built successfully.");
    Ok(())
}

/// Run the constraint engine interactively (placeholder for Phase 2 REPL).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    let parsed = parser::parse_constraints(manifest)?;
    let eng = engine::ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );
    println!(
        "Running phronesiser constraint engine for agent '{}' ({} constraints)",
        parsed.agent_name,
        manifest.constraints.len()
    );
    println!("  Enforcement mode: {}", manifest.enforcement.mode);
    println!(
        "  Escalation threshold: {}",
        manifest.enforcement.escalation_threshold
    );
    println!("  Audit log: {}", manifest.enforcement.audit_log);

    // Demonstrate a quick self-test: evaluate each agent capability.
    let mut trail = audit::AuditTrail::new(manifest.enforcement.audit_log);
    for cap in &parsed.agent_capabilities {
        let action = crate::abi::AgentAction {
            agent_name: parsed.agent_name.clone(),
            action: cap.clone(),
            subject: "agent".to_string(),
            context: std::collections::HashMap::new(),
        };
        let result = eng.evaluate(&action);
        println!("  [self-test] {} -> {}", cap, result.decision);
        trail.record(result);
    }

    if !trail.is_empty() {
        println!("\n{}", trail.render_report());
    }

    Ok(())
}

/// Generate a human-readable summary of the constraint set.
fn generate_summary(manifest: &Manifest, parsed: &parser::ParsedConstraintSet) -> String {
    let mut summary = String::new();
    let project_name = if manifest.project.name.is_empty() {
        &manifest.workload.name
    } else {
        &manifest.project.name
    };

    summary.push_str(&format!("Phronesis Constraint Engine — {}\n", project_name));
    summary.push_str(&format!(
        "Generated by phronesiser v{}\n\n",
        env!("CARGO_PKG_VERSION")
    ));

    summary.push_str(&format!("Agent: {}\n", parsed.agent_name));
    summary.push_str(&format!(
        "Capabilities: {}\n",
        parsed.agent_capabilities.join(", ")
    ));
    summary.push_str(&format!("Enforcement: {}\n", manifest.enforcement.mode));
    summary.push_str(&format!(
        "Escalation threshold: {}\n",
        manifest.enforcement.escalation_threshold
    ));
    summary.push_str(&format!(
        "Audit log: {}\n\n",
        manifest.enforcement.audit_log
    ));

    summary.push_str(&format!("Constraints ({}):\n", parsed.constraints.len()));
    for c in &parsed.constraints {
        let cond = c.condition.as_deref().unwrap_or("(unconditional)");
        summary.push_str(&format!(
            "  [{:>11}] {} — subject={} action={} condition={} priority={}\n",
            c.modality.to_string(),
            c.name,
            c.subject,
            c.action,
            cond,
            c.priority,
        ));
    }

    summary
}
