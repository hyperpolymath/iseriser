// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for phronesiser — Rust-side type definitions mirroring the Idris2
// formal proofs for Phronesis interface correctness.
//
// These types define the core domain model for deontic constraint evaluation:
// - DeonticModality: The three modalities (obligation, permission, prohibition).
// - Constraint: A fully resolved constraint ready for evaluation.
// - AgentAction: An action the agent is attempting to perform.
// - AuditDecision: The outcome of evaluating an action against constraints.
// - EvaluationResult: The complete result including decision and reasoning.

use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// DeonticModality — the three pillars of deontic logic
// ---------------------------------------------------------------------------

/// The three fundamental modalities of deontic logic, mirroring the Idris2
/// ABI definition in `src/interface/abi/Types.idr`.
///
/// - `Obligation`: The agent MUST perform the action.
/// - `Permission`: The agent MAY perform the action.
/// - `Prohibition`: The agent MUST NOT perform the action.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum DeonticModality {
    /// The agent is required to perform the action.
    Obligation = 0,
    /// The agent is allowed (but not required) to perform the action.
    Permission = 1,
    /// The agent is forbidden from performing the action.
    Prohibition = 2,
}

impl fmt::Display for DeonticModality {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DeonticModality::Obligation => write!(f, "OBLIGATION"),
            DeonticModality::Permission => write!(f, "PERMISSION"),
            DeonticModality::Prohibition => write!(f, "PROHIBITION"),
        }
    }
}

impl From<&crate::manifest::ConstraintKind> for DeonticModality {
    fn from(kind: &crate::manifest::ConstraintKind) -> Self {
        match kind {
            crate::manifest::ConstraintKind::Obligation => DeonticModality::Obligation,
            crate::manifest::ConstraintKind::Permission => DeonticModality::Permission,
            crate::manifest::ConstraintKind::Prohibition => DeonticModality::Prohibition,
        }
    }
}

// ---------------------------------------------------------------------------
// Constraint — a resolved constraint ready for runtime evaluation
// ---------------------------------------------------------------------------

/// A fully resolved constraint that the evaluation engine checks at runtime.
///
/// This is the ABI-level representation, distinct from the manifest-level
/// `manifest::Constraint` which is a serialisation format. The ABI constraint
/// carries a compiled condition predicate.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Constraint {
    /// Unique identifier for this constraint.
    pub name: String,

    /// The deontic modality governing this constraint.
    pub modality: DeonticModality,

    /// The entity the constraint applies to (e.g. "agent", "subsystem").
    pub subject: String,

    /// The action being constrained (e.g. "delete-records", "send-email").
    pub action: String,

    /// An optional condition string. When `None`, the constraint applies
    /// unconditionally. When `Some(pred)`, the constraint only applies
    /// when `pred` evaluates to true in the current context.
    pub condition: Option<String>,

    /// Numeric priority for conflict resolution. Higher values win.
    pub priority: i32,
}

impl From<&crate::manifest::Constraint> for Constraint {
    fn from(mc: &crate::manifest::Constraint) -> Self {
        Constraint {
            name: mc.name.clone(),
            modality: DeonticModality::from(&mc.kind),
            subject: mc.subject.clone(),
            action: mc.action.clone(),
            condition: mc.condition.clone(),
            priority: mc.priority,
        }
    }
}

// ---------------------------------------------------------------------------
// AgentAction — an action the agent is attempting to perform
// ---------------------------------------------------------------------------

/// Represents an action that an agent is requesting permission to perform.
/// The constraint engine evaluates this against all applicable constraints.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentAction {
    /// The agent performing the action.
    pub agent_name: String,

    /// The action the agent wants to perform (must match constraint `action` fields).
    pub action: String,

    /// The subject/target of the action (must match constraint `subject` fields).
    pub subject: String,

    /// Key-value context that condition predicates are evaluated against.
    /// For example: `{"user-consent-given": "true", "data-classification": "public"}`.
    pub context: std::collections::HashMap<String, String>,
}

// ---------------------------------------------------------------------------
// AuditDecision — the outcome of constraint evaluation
// ---------------------------------------------------------------------------

/// The decision produced by the constraint engine for a given action.
///
/// - `Permitted`: The action is allowed (no prohibitions apply, or an explicit
///   permission overrides).
/// - `Denied`: The action violates one or more prohibitions in strict mode.
/// - `Escalated`: The violated constraint has priority >= the escalation
///   threshold, requiring human review.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum AuditDecision {
    /// The action is permitted to proceed.
    Permitted = 0,
    /// The action is denied due to constraint violation.
    Denied = 1,
    /// The action requires human escalation before proceeding.
    Escalated = 2,
}

impl fmt::Display for AuditDecision {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AuditDecision::Permitted => write!(f, "PERMITTED"),
            AuditDecision::Denied => write!(f, "DENIED"),
            AuditDecision::Escalated => write!(f, "ESCALATED"),
        }
    }
}

// ---------------------------------------------------------------------------
// EvaluationResult — full evaluation output with reasoning
// ---------------------------------------------------------------------------

/// The complete result of evaluating an agent action against the constraint set.
///
/// Includes the decision, reasoning trail, and references to the constraints
/// that influenced the outcome.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvaluationResult {
    /// The action that was evaluated.
    pub action: AgentAction,

    /// The final decision: permitted, denied, or escalated.
    pub decision: AuditDecision,

    /// Human-readable reasoning explaining why the decision was reached.
    pub reasoning: Vec<String>,

    /// Names of constraints that applied to this evaluation.
    pub applicable_constraints: Vec<String>,

    /// Names of constraints that were violated (empty if permitted).
    pub violated_constraints: Vec<String>,

    /// ISO-8601 timestamp of the evaluation.
    pub timestamp: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deontic_modality_display() {
        assert_eq!(DeonticModality::Obligation.to_string(), "OBLIGATION");
        assert_eq!(DeonticModality::Permission.to_string(), "PERMISSION");
        assert_eq!(DeonticModality::Prohibition.to_string(), "PROHIBITION");
    }

    #[test]
    fn test_audit_decision_display() {
        assert_eq!(AuditDecision::Permitted.to_string(), "PERMITTED");
        assert_eq!(AuditDecision::Denied.to_string(), "DENIED");
        assert_eq!(AuditDecision::Escalated.to_string(), "ESCALATED");
    }

    #[test]
    fn test_deontic_modality_repr() {
        assert_eq!(DeonticModality::Obligation as u8, 0);
        assert_eq!(DeonticModality::Permission as u8, 1);
        assert_eq!(DeonticModality::Prohibition as u8, 2);
    }

    #[test]
    fn test_audit_decision_repr() {
        assert_eq!(AuditDecision::Permitted as u8, 0);
        assert_eq!(AuditDecision::Denied as u8, 1);
        assert_eq!(AuditDecision::Escalated as u8, 2);
    }

    #[test]
    fn test_constraint_from_manifest() {
        let mc = crate::manifest::Constraint {
            name: "no-delete".into(),
            kind: crate::manifest::ConstraintKind::Prohibition,
            subject: "agent".into(),
            action: "delete".into(),
            condition: Some("data-critical".into()),
            priority: 80,
        };
        let c = Constraint::from(&mc);
        assert_eq!(c.modality, DeonticModality::Prohibition);
        assert_eq!(c.name, "no-delete");
        assert_eq!(c.condition, Some("data-critical".into()));
    }
}
