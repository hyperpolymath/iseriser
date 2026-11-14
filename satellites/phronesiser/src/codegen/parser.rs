// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Constraint parser — takes manifest constraint definitions and compiles them
// into ABI-level Constraint values ready for the evaluation engine.
//
// Responsibilities:
// 1. Convert manifest::Constraint -> abi::Constraint (with modality mapping).
// 2. Validate deontic logic consistency (detect contradictions).
// 3. Sort constraints by priority for deterministic evaluation order.

use anyhow::{Result, bail};

use crate::abi;
use crate::manifest::Manifest;

/// A parsed and validated constraint set ready for the evaluation engine.
///
/// Constraints are sorted by descending priority so the engine can apply
/// the highest-priority matching constraint first.
#[derive(Debug, Clone)]
pub struct ParsedConstraintSet {
    /// Constraints sorted by descending priority.
    pub constraints: Vec<abi::Constraint>,

    /// The agent name from the manifest.
    pub agent_name: String,

    /// The agent's declared capabilities.
    pub agent_capabilities: Vec<String>,
}

/// Parse all constraints from the manifest into ABI-level types.
///
/// This function:
/// 1. Converts each `manifest::Constraint` to `abi::Constraint`.
/// 2. Checks for contradictions (same subject+action with both obligation and
///    prohibition at the same priority).
/// 3. Returns the set sorted by descending priority.
pub fn parse_constraints(manifest: &Manifest) -> Result<ParsedConstraintSet> {
    let mut constraints: Vec<abi::Constraint> = manifest
        .constraints
        .iter()
        .map(abi::Constraint::from)
        .collect();

    // Detect contradictions: same (subject, action) pair with conflicting
    // modalities at the same priority level.
    detect_contradictions(&constraints)?;

    // Sort by descending priority for deterministic evaluation.
    constraints.sort_by_key(|b| std::cmp::Reverse(b.priority));

    Ok(ParsedConstraintSet {
        constraints,
        agent_name: manifest.agent.name.clone(),
        agent_capabilities: manifest.agent.capabilities.clone(),
    })
}

/// Detect contradictory constraints: an obligation and a prohibition on the
/// same (subject, action) pair at the same priority level is a logical error.
///
/// Permissions do not contradict obligations or prohibitions — they represent
/// an explicit allowance that can be overridden by higher-priority rules.
fn detect_contradictions(constraints: &[abi::Constraint]) -> Result<()> {
    for (i, a) in constraints.iter().enumerate() {
        for b in constraints.iter().skip(i + 1) {
            if a.subject == b.subject && a.action == b.action && a.priority == b.priority {
                let contradicts = matches!(
                    (&a.modality, &b.modality),
                    (
                        abi::DeonticModality::Obligation,
                        abi::DeonticModality::Prohibition
                    ) | (
                        abi::DeonticModality::Prohibition,
                        abi::DeonticModality::Obligation
                    )
                );
                if contradicts {
                    bail!(
                        "Contradictory constraints: '{}' ({}) and '{}' ({}) \
                         both target subject='{}' action='{}' at priority={}. \
                         An obligation and prohibition on the same action at the \
                         same priority is a deontic logic contradiction.",
                        a.name,
                        a.modality,
                        b.name,
                        b.modality,
                        a.subject,
                        a.action,
                        a.priority
                    );
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::*;

    fn make_manifest(constraints: Vec<Constraint>) -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "test".into(),
                version: "0.1.0".into(),
                description: String::new(),
            },
            constraints,
            enforcement: EnforcementConfig::default(),
            agent: AgentConfig {
                name: "test-agent".into(),
                capabilities: vec!["act".into()],
            },
            workload: WorkloadConfig::default(),
            data: DataConfig::default(),
            options: Options::default(),
        }
    }

    #[test]
    fn test_parse_sorts_by_priority_descending() {
        let m = make_manifest(vec![
            Constraint {
                name: "low".into(),
                kind: ConstraintKind::Permission,
                subject: "a".into(),
                action: "x".into(),
                condition: None,
                priority: 1,
            },
            Constraint {
                name: "high".into(),
                kind: ConstraintKind::Prohibition,
                subject: "a".into(),
                action: "y".into(),
                condition: None,
                priority: 99,
            },
        ]);
        let parsed = parse_constraints(&m).expect("TODO: handle error");
        assert_eq!(parsed.constraints[0].name, "high");
        assert_eq!(parsed.constraints[1].name, "low");
    }

    #[test]
    fn test_detect_contradiction() {
        let m = make_manifest(vec![
            Constraint {
                name: "must-do".into(),
                kind: ConstraintKind::Obligation,
                subject: "agent".into(),
                action: "act".into(),
                condition: None,
                priority: 50,
            },
            Constraint {
                name: "must-not-do".into(),
                kind: ConstraintKind::Prohibition,
                subject: "agent".into(),
                action: "act".into(),
                condition: None,
                priority: 50,
            },
        ]);
        let err = parse_constraints(&m).unwrap_err();
        assert!(err.to_string().contains("Contradictory constraints"));
    }

    #[test]
    fn test_no_contradiction_different_priorities() {
        let m = make_manifest(vec![
            Constraint {
                name: "must-do".into(),
                kind: ConstraintKind::Obligation,
                subject: "agent".into(),
                action: "act".into(),
                condition: None,
                priority: 50,
            },
            Constraint {
                name: "must-not-do".into(),
                kind: ConstraintKind::Prohibition,
                subject: "agent".into(),
                action: "act".into(),
                condition: None,
                priority: 100,
            },
        ]);
        assert!(parse_constraints(&m).is_ok());
    }

    #[test]
    fn test_permission_does_not_contradict() {
        let m = make_manifest(vec![
            Constraint {
                name: "allowed".into(),
                kind: ConstraintKind::Permission,
                subject: "agent".into(),
                action: "act".into(),
                condition: None,
                priority: 50,
            },
            Constraint {
                name: "forbidden".into(),
                kind: ConstraintKind::Prohibition,
                subject: "agent".into(),
                action: "act".into(),
                condition: None,
                priority: 50,
            },
        ]);
        // Permission + Prohibition at the same priority is NOT a contradiction
        // — the prohibition simply takes precedence.
        assert!(parse_constraints(&m).is_ok());
    }
}
