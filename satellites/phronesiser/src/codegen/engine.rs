// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Constraint evaluation engine — checks an agent action against all applicable
// constraints and produces an EvaluationResult with decision and reasoning.
//
// The engine follows these rules:
// 1. Collect all constraints matching the action's (subject, action) pair.
// 2. Evaluate condition predicates against the action's context.
// 3. Apply highest-priority matching constraint to determine the decision.
// 4. In strict mode: prohibitions -> Denied (or Escalated if priority >= threshold).
// 5. In advisory mode: prohibitions -> Permitted with a warning in reasoning.
// 6. Unfulfilled obligations are reported (Denied in strict, warned in advisory).

use crate::abi::{AgentAction, AuditDecision, Constraint, DeonticModality, EvaluationResult};
use crate::manifest::EnforcementMode;

/// The constraint evaluation engine. Holds a set of parsed constraints and
/// the enforcement policy parameters.
#[derive(Debug, Clone)]
pub struct ConstraintEngine {
    /// Constraints sorted by descending priority.
    constraints: Vec<Constraint>,

    /// Enforcement mode (strict or advisory).
    enforcement_mode: EnforcementMode,

    /// Priority threshold at or above which violations are escalated.
    escalation_threshold: i32,
}

impl ConstraintEngine {
    /// Create a new constraint engine from a parsed constraint set and
    /// enforcement configuration.
    pub fn new(
        constraints: Vec<Constraint>,
        enforcement_mode: EnforcementMode,
        escalation_threshold: i32,
    ) -> Self {
        ConstraintEngine {
            constraints,
            enforcement_mode,
            escalation_threshold,
        }
    }

    /// Evaluate an agent action against all applicable constraints.
    ///
    /// Returns an `EvaluationResult` containing the decision, reasoning,
    /// and lists of applicable/violated constraints.
    pub fn evaluate(&self, action: &AgentAction) -> EvaluationResult {
        let timestamp = chrono::Utc::now().to_rfc3339();
        let mut reasoning: Vec<String> = Vec::new();
        let mut applicable: Vec<String> = Vec::new();
        let mut violated: Vec<String> = Vec::new();
        let mut decision = AuditDecision::Permitted;

        // Collect constraints that match the action's subject and action.
        let matching: Vec<&Constraint> = self
            .constraints
            .iter()
            .filter(|c| c.subject == action.subject && c.action == action.action)
            .collect();

        if matching.is_empty() {
            reasoning.push(format!(
                "No constraints found for subject='{}' action='{}'; action is permitted by default.",
                action.subject, action.action
            ));
            return EvaluationResult {
                action: action.clone(),
                decision: AuditDecision::Permitted,
                reasoning,
                applicable_constraints: applicable,
                violated_constraints: violated,
                timestamp,
            };
        }

        // Evaluate each matching constraint (already sorted by descending priority).
        for constraint in &matching {
            // Check if the condition predicate holds.
            let condition_met = evaluate_condition(&constraint.condition, &action.context);

            if !condition_met {
                reasoning.push(format!(
                    "Constraint '{}' ({}): condition '{}' not met; skipping.",
                    constraint.name,
                    constraint.modality,
                    constraint.condition.as_deref().unwrap_or("(none)")
                ));
                continue;
            }

            applicable.push(constraint.name.clone());

            match constraint.modality {
                DeonticModality::Prohibition => {
                    violated.push(constraint.name.clone());
                    let new_decision = if constraint.priority >= self.escalation_threshold {
                        reasoning.push(format!(
                            "Constraint '{}' (PROHIBITION, priority={}) violated: action '{}' \
                             is forbidden. Priority >= escalation threshold ({}); escalating.",
                            constraint.name,
                            constraint.priority,
                            action.action,
                            self.escalation_threshold,
                        ));
                        AuditDecision::Escalated
                    } else {
                        match self.enforcement_mode {
                            EnforcementMode::Strict => {
                                reasoning.push(format!(
                                    "Constraint '{}' (PROHIBITION, priority={}) violated: \
                                     action '{}' is forbidden. Enforcement=strict; denying.",
                                    constraint.name, constraint.priority, action.action,
                                ));
                                AuditDecision::Denied
                            }
                            EnforcementMode::Advisory => {
                                reasoning.push(format!(
                                    "Constraint '{}' (PROHIBITION, priority={}) violated: \
                                     action '{}' is forbidden. Enforcement=advisory; \
                                     logging warning but permitting.",
                                    constraint.name, constraint.priority, action.action,
                                ));
                                AuditDecision::Permitted
                            }
                        }
                    };
                    // Escalated > Denied > Permitted — keep the most restrictive.
                    decision = most_restrictive(decision, new_decision);
                }
                DeonticModality::Obligation => {
                    // An obligation means the agent MUST perform this action.
                    // If the agent is requesting to perform it, the obligation is
                    // satisfied. We note it in reasoning.
                    reasoning.push(format!(
                        "Constraint '{}' (OBLIGATION, priority={}): agent is fulfilling \
                         obligation to perform '{}'.",
                        constraint.name, constraint.priority, action.action,
                    ));
                }
                DeonticModality::Permission => {
                    reasoning.push(format!(
                        "Constraint '{}' (PERMISSION, priority={}): agent is explicitly \
                         permitted to perform '{}'.",
                        constraint.name, constraint.priority, action.action,
                    ));
                }
            }
        }

        EvaluationResult {
            action: action.clone(),
            decision,
            reasoning,
            applicable_constraints: applicable,
            violated_constraints: violated,
            timestamp,
        }
    }

    /// Check whether any obligation constraints are unfulfilled for the agent.
    ///
    /// Returns a list of obligation constraints whose actions the agent has
    /// not yet performed (based on a set of performed action names).
    pub fn check_unfulfilled_obligations(
        &self,
        agent_subject: &str,
        performed_actions: &[String],
        context: &std::collections::HashMap<String, String>,
    ) -> Vec<String> {
        self.constraints
            .iter()
            .filter(|c| {
                c.modality == DeonticModality::Obligation
                    && c.subject == agent_subject
                    && evaluate_condition(&c.condition, context)
                    && !performed_actions.contains(&c.action)
            })
            .map(|c| {
                format!(
                    "Unfulfilled obligation '{}': agent must perform '{}' (priority={})",
                    c.name, c.action, c.priority
                )
            })
            .collect()
    }
}

/// Evaluate a simple condition predicate against the action's context.
///
/// Supported condition forms:
/// - `None` / empty -> always true (unconditional).
/// - `"key"` -> true if `context["key"]` is `"true"`.
/// - `"not key"` -> true if `context["key"]` is absent or not `"true"`.
/// - `"key = value"` -> true if `context["key"] == "value"`.
///
/// This is intentionally simple — the Idris2 ABI layer provides formal
/// verification of more complex predicates. The Rust engine handles the
/// common cases for runtime evaluation.
fn evaluate_condition(
    condition: &Option<String>,
    context: &std::collections::HashMap<String, String>,
) -> bool {
    let cond = match condition {
        None => return true,
        Some(c) if c.is_empty() => return true,
        Some(c) => c.trim(),
    };

    // "not <key>" form
    if let Some(key) = cond.strip_prefix("not ") {
        let key = key.trim();
        return context.get(key).is_none_or(|v| v != "true");
    }

    // "key = value" form
    if let Some((key, value)) = cond.split_once('=') {
        let key = key.trim();
        let value = value.trim();
        return context.get(key).is_some_and(|v| v == value);
    }

    // Simple key presence: true if context[key] == "true"
    context.get(cond).is_some_and(|v| v == "true")
}

/// Return the more restrictive of two decisions.
/// Escalated > Denied > Permitted.
fn most_restrictive(a: AuditDecision, b: AuditDecision) -> AuditDecision {
    match (a, b) {
        (AuditDecision::Escalated, _) | (_, AuditDecision::Escalated) => AuditDecision::Escalated,
        (AuditDecision::Denied, _) | (_, AuditDecision::Denied) => AuditDecision::Denied,
        _ => AuditDecision::Permitted,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn prohibition(name: &str, subject: &str, action: &str, priority: i32) -> Constraint {
        Constraint {
            name: name.into(),
            modality: DeonticModality::Prohibition,
            subject: subject.into(),
            action: action.into(),
            condition: None,
            priority,
        }
    }

    fn permission(name: &str, subject: &str, action: &str, priority: i32) -> Constraint {
        Constraint {
            name: name.into(),
            modality: DeonticModality::Permission,
            subject: subject.into(),
            action: action.into(),
            condition: None,
            priority,
        }
    }

    #[test]
    fn test_no_matching_constraints_permits() {
        let engine = ConstraintEngine::new(vec![], EnforcementMode::Strict, 100);
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "read".into(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Permitted);
    }

    #[test]
    fn test_prohibition_strict_denies() {
        let engine = ConstraintEngine::new(
            vec![prohibition("no-delete", "agent", "delete", 50)],
            EnforcementMode::Strict,
            100,
        );
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "delete".into(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Denied);
        assert_eq!(result.violated_constraints, vec!["no-delete"]);
    }

    #[test]
    fn test_prohibition_advisory_permits_with_warning() {
        let engine = ConstraintEngine::new(
            vec![prohibition("no-delete", "agent", "delete", 50)],
            EnforcementMode::Advisory,
            100,
        );
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "delete".into(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Permitted);
        assert!(!result.violated_constraints.is_empty());
        assert!(result.reasoning.iter().any(|r| r.contains("advisory")));
    }

    #[test]
    fn test_prohibition_escalates_above_threshold() {
        let engine = ConstraintEngine::new(
            vec![prohibition("critical", "agent", "harm", 100)],
            EnforcementMode::Strict,
            100,
        );
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "harm".into(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Escalated);
    }

    #[test]
    fn test_condition_not_met_skips_constraint() {
        let mut c = prohibition("no-delete", "agent", "delete", 50);
        c.condition = Some("data-sensitive".into());
        let engine = ConstraintEngine::new(vec![c], EnforcementMode::Strict, 100);
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "delete".into(),
            subject: "agent".into(),
            context: HashMap::new(), // no "data-sensitive" key
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Permitted);
    }

    #[test]
    fn test_condition_met_applies_constraint() {
        let mut c = prohibition("no-delete", "agent", "delete", 50);
        c.condition = Some("data-sensitive".into());
        let engine = ConstraintEngine::new(vec![c], EnforcementMode::Strict, 100);
        let mut ctx = HashMap::new();
        ctx.insert("data-sensitive".into(), "true".into());
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "delete".into(),
            subject: "agent".into(),
            context: ctx,
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Denied);
    }

    #[test]
    fn test_not_condition() {
        let mut c = prohibition("no-access-without-consent", "agent", "access-data", 50);
        c.condition = Some("not user-consent-given".into());
        let engine = ConstraintEngine::new(vec![c], EnforcementMode::Strict, 100);

        // Without consent -> prohibition applies
        let action_no_consent = AgentAction {
            agent_name: "bot".into(),
            action: "access-data".into(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        assert_eq!(
            engine.evaluate(&action_no_consent).decision,
            AuditDecision::Denied
        );

        // With consent -> prohibition does not apply
        let mut ctx = HashMap::new();
        ctx.insert("user-consent-given".into(), "true".into());
        let action_with_consent = AgentAction {
            agent_name: "bot".into(),
            action: "access-data".into(),
            subject: "agent".into(),
            context: ctx,
        };
        assert_eq!(
            engine.evaluate(&action_with_consent).decision,
            AuditDecision::Permitted
        );
    }

    #[test]
    fn test_evaluate_condition_key_equals_value() {
        let cond = Some("role = admin".to_string());
        let mut ctx = HashMap::new();
        ctx.insert("role".into(), "admin".into());
        assert!(evaluate_condition(&cond, &ctx));

        ctx.insert("role".into(), "user".into());
        assert!(!evaluate_condition(&cond, &ctx));
    }

    #[test]
    fn test_most_restrictive() {
        assert_eq!(
            most_restrictive(AuditDecision::Permitted, AuditDecision::Denied),
            AuditDecision::Denied
        );
        assert_eq!(
            most_restrictive(AuditDecision::Denied, AuditDecision::Escalated),
            AuditDecision::Escalated
        );
        assert_eq!(
            most_restrictive(AuditDecision::Permitted, AuditDecision::Permitted),
            AuditDecision::Permitted
        );
    }

    #[test]
    fn test_permission_noted_in_reasoning() {
        let engine = ConstraintEngine::new(
            vec![permission("can-read", "agent", "read", 10)],
            EnforcementMode::Strict,
            100,
        );
        let action = AgentAction {
            agent_name: "bot".into(),
            action: "read".into(),
            subject: "agent".into(),
            context: HashMap::new(),
        };
        let result = engine.evaluate(&action);
        assert_eq!(result.decision, AuditDecision::Permitted);
        assert!(result.reasoning.iter().any(|r| r.contains("PERMISSION")));
    }

    #[test]
    fn test_unfulfilled_obligations() {
        let engine = ConstraintEngine::new(
            vec![Constraint {
                name: "must-log".into(),
                modality: DeonticModality::Obligation,
                subject: "agent".into(),
                action: "write-log".into(),
                condition: None,
                priority: 50,
            }],
            EnforcementMode::Strict,
            100,
        );
        let unfulfilled = engine.check_unfulfilled_obligations("agent", &[], &HashMap::new());
        assert_eq!(unfulfilled.len(), 1);
        assert!(unfulfilled[0].contains("must-log"));

        // After performing the action, no unfulfilled obligations.
        let performed = vec!["write-log".to_string()];
        let unfulfilled =
            engine.check_unfulfilled_obligations("agent", &performed, &HashMap::new());
        assert!(unfulfilled.is_empty());
    }
}
