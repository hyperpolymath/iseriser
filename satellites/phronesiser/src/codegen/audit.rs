// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Audit trail generator — produces structured audit logs from constraint
// evaluation results. Supports both human-readable and machine-readable
// (JSON) output formats.

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::abi::EvaluationResult;

/// An audit trail accumulating evaluation results over time.
///
/// The trail can be written to disk as a JSON array for machine consumption
/// or rendered as a human-readable report.
#[derive(Debug, Clone)]
pub struct AuditTrail {
    /// All evaluation results recorded in this trail.
    entries: Vec<EvaluationResult>,

    /// Whether audit logging is enabled. When false, `record()` is a no-op.
    enabled: bool,
}

impl AuditTrail {
    /// Create a new audit trail. If `enabled` is false, all `record()` calls
    /// are silently ignored.
    pub fn new(enabled: bool) -> Self {
        AuditTrail {
            entries: Vec::new(),
            enabled,
        }
    }

    /// Record an evaluation result in the audit trail.
    ///
    /// Does nothing if the trail is disabled.
    pub fn record(&mut self, result: EvaluationResult) {
        if self.enabled {
            self.entries.push(result);
        }
    }

    /// Return a reference to all recorded entries.
    pub fn entries(&self) -> &[EvaluationResult] {
        &self.entries
    }

    /// Return the number of recorded entries.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Return whether the trail is empty.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Serialize the audit trail to a JSON string.
    pub fn to_json(&self) -> Result<String> {
        serde_json::to_string_pretty(&self.entries)
            .context("Failed to serialize audit trail to JSON")
    }

    /// Write the audit trail to a JSON file at the given path.
    ///
    /// Creates parent directories if they do not exist.
    pub fn write_json(&self, path: &str) -> Result<()> {
        if let Some(parent) = Path::new(path).parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!("Failed to create audit log directory: {}", parent.display())
            })?;
        }
        let json = self.to_json()?;
        fs::write(path, &json).with_context(|| format!("Failed to write audit log: {}", path))?;
        Ok(())
    }

    /// Render a human-readable report of the audit trail.
    ///
    /// Each entry is formatted as a block showing the action, decision,
    /// reasoning, and constraint references.
    pub fn render_report(&self) -> String {
        let mut report = String::new();
        report.push_str("=== Phronesis Audit Report ===\n");
        report.push_str(&format!("Total evaluations: {}\n\n", self.entries.len()));

        for (idx, entry) in self.entries.iter().enumerate() {
            report.push_str(&format!("--- Evaluation #{} ---\n", idx + 1));
            report.push_str(&format!("Timestamp: {}\n", entry.timestamp));
            report.push_str(&format!(
                "Agent: {} | Subject: {} | Action: {}\n",
                entry.action.agent_name, entry.action.subject, entry.action.action
            ));
            report.push_str(&format!("Decision: {}\n", entry.decision));

            if !entry.applicable_constraints.is_empty() {
                report.push_str(&format!(
                    "Applicable constraints: {}\n",
                    entry.applicable_constraints.join(", ")
                ));
            }
            if !entry.violated_constraints.is_empty() {
                report.push_str(&format!(
                    "Violated constraints: {}\n",
                    entry.violated_constraints.join(", ")
                ));
            }

            report.push_str("Reasoning:\n");
            for reason in &entry.reasoning {
                report.push_str(&format!("  - {}\n", reason));
            }
            report.push('\n');
        }

        // Summary statistics
        let permitted = self
            .entries
            .iter()
            .filter(|e| e.decision == crate::abi::AuditDecision::Permitted)
            .count();
        let denied = self
            .entries
            .iter()
            .filter(|e| e.decision == crate::abi::AuditDecision::Denied)
            .count();
        let escalated = self
            .entries
            .iter()
            .filter(|e| e.decision == crate::abi::AuditDecision::Escalated)
            .count();

        report.push_str("=== Summary ===\n");
        report.push_str(&format!("Permitted: {}\n", permitted));
        report.push_str(&format!("Denied: {}\n", denied));
        report.push_str(&format!("Escalated: {}\n", escalated));

        report
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::{AgentAction, AuditDecision, EvaluationResult};
    use std::collections::HashMap;

    fn sample_result(decision: AuditDecision) -> EvaluationResult {
        EvaluationResult {
            action: AgentAction {
                agent_name: "test-bot".into(),
                action: "read-data".into(),
                subject: "agent".into(),
                context: HashMap::new(),
            },
            decision,
            reasoning: vec!["Test reasoning.".into()],
            applicable_constraints: vec!["c1".into()],
            violated_constraints: if decision == AuditDecision::Denied {
                vec!["c1".into()]
            } else {
                vec![]
            },
            timestamp: "2026-03-21T00:00:00Z".into(),
        }
    }

    #[test]
    fn test_audit_trail_enabled() {
        let mut trail = AuditTrail::new(true);
        trail.record(sample_result(AuditDecision::Permitted));
        assert_eq!(trail.len(), 1);
        assert!(!trail.is_empty());
    }

    #[test]
    fn test_audit_trail_disabled() {
        let mut trail = AuditTrail::new(false);
        trail.record(sample_result(AuditDecision::Permitted));
        assert_eq!(trail.len(), 0);
        assert!(trail.is_empty());
    }

    #[test]
    fn test_audit_trail_to_json() {
        let mut trail = AuditTrail::new(true);
        trail.record(sample_result(AuditDecision::Permitted));
        trail.record(sample_result(AuditDecision::Denied));
        let json = trail.to_json().expect("TODO: handle error");
        assert!(json.contains("Permitted"));
        assert!(json.contains("Denied"));
    }

    #[test]
    fn test_render_report() {
        let mut trail = AuditTrail::new(true);
        trail.record(sample_result(AuditDecision::Permitted));
        trail.record(sample_result(AuditDecision::Denied));
        trail.record(sample_result(AuditDecision::Escalated));
        let report = trail.render_report();
        assert!(report.contains("Phronesis Audit Report"));
        assert!(report.contains("Total evaluations: 3"));
        assert!(report.contains("Permitted: 1"));
        assert!(report.contains("Denied: 1"));
        assert!(report.contains("Escalated: 1"));
    }

    #[test]
    fn test_write_json_to_tempfile() {
        let mut trail = AuditTrail::new(true);
        trail.record(sample_result(AuditDecision::Permitted));
        let dir = tempfile::tempdir().expect("TODO: handle error");
        let path = dir.path().join("audit.json");
        trail
            .write_json(path.to_str().expect("TODO: handle error"))
            .expect("TODO: handle error");
        let content = std::fs::read_to_string(&path).expect("TODO: handle error");
        assert!(content.contains("Permitted"));
    }
}
