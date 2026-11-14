// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for phronesiser — end-to-end tests exercising the full
// pipeline from manifest loading through constraint evaluation to audit output.

use std::collections::HashMap;

use phronesiser::abi::{AgentAction, AuditDecision, DeonticModality};
use phronesiser::codegen::audit::AuditTrail;
use phronesiser::codegen::engine::ConstraintEngine;
use phronesiser::codegen::parser::parse_constraints;
use phronesiser::manifest::{
    AgentConfig, Constraint, ConstraintKind, EnforcementConfig, EnforcementMode, Manifest,
    ProjectConfig,
};

/// Helper: build a manifest from constraint definitions.
fn make_manifest(
    constraints: Vec<Constraint>,
    mode: EnforcementMode,
    escalation_threshold: i32,
) -> Manifest {
    Manifest {
        project: ProjectConfig {
            name: "integration-test".into(),
            version: "1.0.0".into(),
            description: "Integration test manifest".into(),
        },
        constraints,
        enforcement: EnforcementConfig {
            mode,
            escalation_threshold,
            audit_log: true,
        },
        agent: AgentConfig {
            name: "test-agent".into(),
            capabilities: vec!["read-data".into(), "write-log".into()],
        },
        workload: Default::default(),
        data: Default::default(),
        options: Default::default(),
    }
}

// ---------------------------------------------------------------------------
// Test 1: Full pipeline — prohibition blocks action in strict mode
// ---------------------------------------------------------------------------

#[test]
fn test_full_pipeline_prohibition_strict() {
    let manifest = make_manifest(
        vec![Constraint {
            name: "no-delete-records".into(),
            kind: ConstraintKind::Prohibition,
            subject: "agent".into(),
            action: "delete-records".into(),
            condition: None,
            priority: 50,
        }],
        EnforcementMode::Strict,
        100,
    );

    // Parse
    let parsed = parse_constraints(&manifest).unwrap();
    assert_eq!(parsed.constraints.len(), 1);
    assert_eq!(parsed.constraints[0].modality, DeonticModality::Prohibition);

    // Build engine
    let engine = ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );

    // Evaluate an action that violates the prohibition
    let action = AgentAction {
        agent_name: "test-agent".into(),
        action: "delete-records".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    let result = engine.evaluate(&action);
    assert_eq!(result.decision, AuditDecision::Denied);
    assert_eq!(result.violated_constraints, vec!["no-delete-records"]);

    // Audit trail captures the result
    let mut trail = AuditTrail::new(true);
    trail.record(result);
    assert_eq!(trail.len(), 1);
    let report = trail.render_report();
    assert!(report.contains("DENIED"));
    assert!(report.contains("no-delete-records"));
}

// ---------------------------------------------------------------------------
// Test 2: Advisory mode — prohibition logged but action permitted
// ---------------------------------------------------------------------------

#[test]
fn test_full_pipeline_prohibition_advisory() {
    let manifest = make_manifest(
        vec![Constraint {
            name: "no-send-email".into(),
            kind: ConstraintKind::Prohibition,
            subject: "agent".into(),
            action: "send-email".into(),
            condition: None,
            priority: 30,
        }],
        EnforcementMode::Advisory,
        100,
    );

    let parsed = parse_constraints(&manifest).unwrap();
    let engine = ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );

    let action = AgentAction {
        agent_name: "test-agent".into(),
        action: "send-email".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    let result = engine.evaluate(&action);

    // In advisory mode, the action is permitted even though it violates a prohibition
    assert_eq!(result.decision, AuditDecision::Permitted);
    assert!(!result.violated_constraints.is_empty());
    assert!(result.reasoning.iter().any(|r| r.contains("advisory")));
}

// ---------------------------------------------------------------------------
// Test 3: Escalation — high-priority prohibition triggers escalation
// ---------------------------------------------------------------------------

#[test]
fn test_full_pipeline_escalation() {
    let manifest = make_manifest(
        vec![Constraint {
            name: "no-harm-human".into(),
            kind: ConstraintKind::Prohibition,
            subject: "agent".into(),
            action: "cause-harm".into(),
            condition: None,
            priority: 200,
        }],
        EnforcementMode::Strict,
        100,
    );

    let parsed = parse_constraints(&manifest).unwrap();
    let engine = ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );

    let action = AgentAction {
        agent_name: "test-agent".into(),
        action: "cause-harm".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    let result = engine.evaluate(&action);
    assert_eq!(result.decision, AuditDecision::Escalated);
    assert!(result.reasoning.iter().any(|r| r.contains("escalating")));
}

// ---------------------------------------------------------------------------
// Test 4: Conditional constraints with context
// ---------------------------------------------------------------------------

#[test]
fn test_conditional_constraint_with_context() {
    let manifest = make_manifest(
        vec![Constraint {
            name: "no-access-without-consent".into(),
            kind: ConstraintKind::Prohibition,
            subject: "agent".into(),
            action: "access-personal-data".into(),
            condition: Some("not user-consent-given".into()),
            priority: 80,
        }],
        EnforcementMode::Strict,
        100,
    );

    let parsed = parse_constraints(&manifest).unwrap();
    let engine = ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );

    // Without consent: action is denied
    let action_no_consent = AgentAction {
        agent_name: "test-agent".into(),
        action: "access-personal-data".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    assert_eq!(
        engine.evaluate(&action_no_consent).decision,
        AuditDecision::Denied
    );

    // With consent: prohibition condition is false, action permitted
    let mut ctx = HashMap::new();
    ctx.insert("user-consent-given".into(), "true".into());
    let action_with_consent = AgentAction {
        agent_name: "test-agent".into(),
        action: "access-personal-data".into(),
        subject: "agent".into(),
        context: ctx,
    };
    assert_eq!(
        engine.evaluate(&action_with_consent).decision,
        AuditDecision::Permitted
    );
}

// ---------------------------------------------------------------------------
// Test 5: Multiple constraints with priority resolution
// ---------------------------------------------------------------------------

#[test]
fn test_multiple_constraints_priority_resolution() {
    let manifest = make_manifest(
        vec![
            Constraint {
                name: "allow-read".into(),
                kind: ConstraintKind::Permission,
                subject: "agent".into(),
                action: "read-data".into(),
                condition: None,
                priority: 10,
            },
            Constraint {
                name: "obligation-log".into(),
                kind: ConstraintKind::Obligation,
                subject: "agent".into(),
                action: "write-log".into(),
                condition: None,
                priority: 50,
            },
            Constraint {
                name: "no-delete".into(),
                kind: ConstraintKind::Prohibition,
                subject: "agent".into(),
                action: "delete-data".into(),
                condition: None,
                priority: 90,
            },
        ],
        EnforcementMode::Strict,
        100,
    );

    let parsed = parse_constraints(&manifest).unwrap();
    let engine = ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );

    // Read is permitted
    let read_action = AgentAction {
        agent_name: "test-agent".into(),
        action: "read-data".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    assert_eq!(
        engine.evaluate(&read_action).decision,
        AuditDecision::Permitted
    );

    // Write-log fulfils an obligation
    let log_action = AgentAction {
        agent_name: "test-agent".into(),
        action: "write-log".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    let log_result = engine.evaluate(&log_action);
    assert_eq!(log_result.decision, AuditDecision::Permitted);
    assert!(
        log_result
            .reasoning
            .iter()
            .any(|r| r.contains("OBLIGATION"))
    );

    // Delete is denied
    let delete_action = AgentAction {
        agent_name: "test-agent".into(),
        action: "delete-data".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    assert_eq!(
        engine.evaluate(&delete_action).decision,
        AuditDecision::Denied
    );
}

// ---------------------------------------------------------------------------
// Test 6: Manifest round-trip — load from TOML file
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_load_from_file() {
    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("phronesiser.toml");
    std::fs::write(
        &manifest_path,
        r#"
[project]
name = "file-test"
version = "0.1.0"
description = "Test loading from file"

[[constraints]]
name = "no-harm"
kind = "prohibition"
subject = "agent"
action = "harm"
priority = 100

[[constraints]]
name = "must-audit"
kind = "obligation"
subject = "agent"
action = "audit"
priority = 50

[enforcement]
mode = "strict"
escalation-threshold = 80
audit-log = true

[agent]
name = "file-agent"
capabilities = ["read", "audit"]
"#,
    )
    .unwrap();

    let m = phronesiser::load_manifest(manifest_path.to_str().unwrap()).unwrap();
    phronesiser::validate(&m).unwrap();
    assert_eq!(m.project.name, "file-test");
    assert_eq!(m.constraints.len(), 2);
    assert_eq!(m.agent.name, "file-agent");
    assert_eq!(m.enforcement.escalation_threshold, 80);

    // Parse and evaluate
    let parsed = parse_constraints(&m).unwrap();
    let engine = ConstraintEngine::new(
        parsed.constraints,
        m.enforcement.mode.clone(),
        m.enforcement.escalation_threshold,
    );

    // "harm" at priority 100 >= threshold 80 should escalate
    let action = AgentAction {
        agent_name: "file-agent".into(),
        action: "harm".into(),
        subject: "agent".into(),
        context: HashMap::new(),
    };
    assert_eq!(engine.evaluate(&action).decision, AuditDecision::Escalated);
}

// ---------------------------------------------------------------------------
// Test 7: Audit trail JSON serialization round-trip
// ---------------------------------------------------------------------------

#[test]
fn test_audit_trail_json_roundtrip() {
    let manifest = make_manifest(
        vec![
            Constraint {
                name: "no-delete".into(),
                kind: ConstraintKind::Prohibition,
                subject: "agent".into(),
                action: "delete".into(),
                condition: None,
                priority: 50,
            },
            Constraint {
                name: "allow-read".into(),
                kind: ConstraintKind::Permission,
                subject: "agent".into(),
                action: "read".into(),
                condition: None,
                priority: 10,
            },
        ],
        EnforcementMode::Strict,
        100,
    );

    let parsed = parse_constraints(&manifest).unwrap();
    let engine = ConstraintEngine::new(
        parsed.constraints,
        manifest.enforcement.mode.clone(),
        manifest.enforcement.escalation_threshold,
    );

    let mut trail = AuditTrail::new(true);

    // Evaluate multiple actions
    for action_name in &["delete", "read", "unknown-action"] {
        let action = AgentAction {
            agent_name: "test-agent".into(),
            action: action_name.to_string(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        trail.record(engine.evaluate(&action));
    }

    assert_eq!(trail.len(), 3);

    // Serialize to JSON and back
    let json = trail.to_json().unwrap();
    let deserialized: Vec<phronesiser::EvaluationResult> = serde_json::from_str(&json).unwrap();
    assert_eq!(deserialized.len(), 3);
    assert_eq!(deserialized[0].decision, AuditDecision::Denied);
    assert_eq!(deserialized[1].decision, AuditDecision::Permitted);
    assert_eq!(deserialized[2].decision, AuditDecision::Permitted); // no constraints match
}

// ---------------------------------------------------------------------------
// Test 8: Codegen generate_all writes artifacts to disk
// ---------------------------------------------------------------------------

#[test]
fn test_codegen_generate_all() {
    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("phronesiser.toml");
    std::fs::write(
        &manifest_path,
        r#"
[project]
name = "gen-test"
version = "0.1.0"

[[constraints]]
name = "c1"
kind = "prohibition"
subject = "agent"
action = "bad-action"
priority = 50

[enforcement]
mode = "strict"
escalation-threshold = 100
audit-log = true

[agent]
name = "gen-agent"
capabilities = ["good-action"]
"#,
    )
    .unwrap();

    let output_dir = dir.path().join("output");
    phronesiser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    )
    .unwrap();

    // Verify files were created
    assert!(output_dir.join("constraints.json").exists());
    assert!(output_dir.join("engine_config.json").exists());
    assert!(output_dir.join("README.txt").exists());

    // Verify constraints.json content
    let constraints_json = std::fs::read_to_string(output_dir.join("constraints.json")).unwrap();
    assert!(constraints_json.contains("c1"));
    assert!(constraints_json.contains("Prohibition"));

    // Verify engine_config.json content
    let config_json = std::fs::read_to_string(output_dir.join("engine_config.json")).unwrap();
    assert!(config_json.contains("gen-agent"));
    assert!(config_json.contains("strict"));
}
