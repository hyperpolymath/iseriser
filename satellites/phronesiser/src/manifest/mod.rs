// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for phronesiser — parses and validates phronesiser.toml files
// containing ethical constraint definitions (obligations, permissions, prohibitions),
// enforcement policy, and agent capability declarations.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::Path;

// ---------------------------------------------------------------------------
// Deontic constraint kind — the three modalities of deontic logic
// ---------------------------------------------------------------------------

/// Represents the three fundamental modalities of deontic logic:
/// - **Obligation**: The agent MUST perform the action when the condition holds.
/// - **Permission**: The agent MAY perform the action when the condition holds.
/// - **Prohibition**: The agent MUST NOT perform the action when the condition holds.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConstraintKind {
    /// The agent is obligated to perform the action.
    Obligation,
    /// The agent is permitted (but not required) to perform the action.
    Permission,
    /// The agent is prohibited from performing the action.
    Prohibition,
}

impl fmt::Display for ConstraintKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConstraintKind::Obligation => write!(f, "obligation"),
            ConstraintKind::Permission => write!(f, "permission"),
            ConstraintKind::Prohibition => write!(f, "prohibition"),
        }
    }
}

// ---------------------------------------------------------------------------
// Enforcement mode — how strictly constraints are applied
// ---------------------------------------------------------------------------

/// Controls how the constraint engine responds to violations:
/// - **Strict**: Violations block the action entirely.
/// - **Advisory**: Violations are logged but the action proceeds.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum EnforcementMode {
    /// Actions that violate constraints are denied outright.
    #[default]
    Strict,
    /// Violations are logged as warnings; the action is still permitted.
    Advisory,
}

impl fmt::Display for EnforcementMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EnforcementMode::Strict => write!(f, "strict"),
            EnforcementMode::Advisory => write!(f, "advisory"),
        }
    }
}

// ---------------------------------------------------------------------------
// Manifest top-level structure
// ---------------------------------------------------------------------------

/// The complete phronesiser manifest, typically loaded from `phronesiser.toml`.
///
/// Contains:
/// - `project`: Metadata about the project being constrained.
/// - `constraints`: A list of deontic constraints (obligation/permission/prohibition).
/// - `enforcement`: Policy for how constraints are evaluated and enforced.
/// - `agent`: The AI agent whose actions are being constrained.
///
/// Legacy fields (`workload`, `data`, `options`) are retained for backward
/// compatibility with the original scaffold but are not required for Phase 1.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    #[serde(default)]
    pub project: ProjectConfig,

    /// Ethical constraints expressed in deontic logic.
    #[serde(default, rename = "constraints")]
    pub constraints: Vec<Constraint>,

    /// Enforcement policy controlling how constraint violations are handled.
    #[serde(default)]
    pub enforcement: EnforcementConfig,

    /// The AI agent whose actions are being evaluated.
    #[serde(default)]
    pub agent: AgentConfig,

    // -- Legacy fields (kept for backward compatibility) --
    /// Legacy workload configuration.
    #[serde(default)]
    pub workload: WorkloadConfig,
    /// Legacy data type configuration.
    #[serde(default)]
    pub data: DataConfig,
    /// Legacy option flags.
    #[serde(default)]
    pub options: Options,
}

// ---------------------------------------------------------------------------
// Project configuration
// ---------------------------------------------------------------------------

/// Metadata about the project whose AI agents are being constrained.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProjectConfig {
    /// Human-readable name of the project (e.g. "medical-triage-bot").
    #[serde(default)]
    pub name: String,

    /// Semantic version of the constraint set.
    #[serde(default)]
    pub version: String,

    /// Free-text description of the project's ethical domain.
    #[serde(default)]
    pub description: String,
}

// ---------------------------------------------------------------------------
// Constraint definition
// ---------------------------------------------------------------------------

/// A single deontic constraint that governs an agent's behaviour.
///
/// Each constraint specifies:
/// - **name**: A unique identifier for this constraint.
/// - **kind**: One of `obligation`, `permission`, or `prohibition`.
/// - **subject**: The entity the constraint applies to (e.g. "agent", "user-data").
/// - **action**: The specific action being constrained (e.g. "delete-user-data").
/// - **condition**: An optional predicate that must hold for the constraint to apply.
/// - **priority**: Numeric priority (higher = more important) for conflict resolution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Constraint {
    /// Unique name identifying this constraint.
    pub name: String,

    /// The deontic modality: obligation, permission, or prohibition.
    pub kind: ConstraintKind,

    /// The entity the constraint applies to.
    pub subject: String,

    /// The action being constrained.
    pub action: String,

    /// An optional boolean condition (expressed as a string predicate).
    /// When absent the constraint applies unconditionally.
    #[serde(default)]
    pub condition: Option<String>,

    /// Numeric priority for conflict resolution. Higher values take precedence.
    /// Defaults to 0 when unspecified.
    #[serde(default)]
    pub priority: i32,
}

// ---------------------------------------------------------------------------
// Enforcement configuration
// ---------------------------------------------------------------------------

/// Policy controlling how the constraint engine handles violations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnforcementConfig {
    /// Whether violations block the action (`strict`) or just warn (`advisory`).
    #[serde(default)]
    pub mode: EnforcementMode,

    /// The priority threshold at which a violation triggers escalation instead
    /// of a simple deny. Constraints with `priority >= escalation_threshold`
    /// produce an `Escalated` decision rather than `Denied`.
    #[serde(
        default = "default_escalation_threshold",
        rename = "escalation-threshold"
    )]
    pub escalation_threshold: i32,

    /// Whether to produce a structured audit log of every evaluation.
    #[serde(default = "default_audit_log", rename = "audit-log")]
    pub audit_log: bool,
}

/// Default escalation threshold — constraints at priority 100+ are escalated.
fn default_escalation_threshold() -> i32 {
    100
}

/// Audit logging is enabled by default.
fn default_audit_log() -> bool {
    true
}

impl Default for EnforcementConfig {
    fn default() -> Self {
        EnforcementConfig {
            mode: EnforcementMode::default(),
            escalation_threshold: default_escalation_threshold(),
            audit_log: default_audit_log(),
        }
    }
}

// ---------------------------------------------------------------------------
// Agent configuration
// ---------------------------------------------------------------------------

/// Describes the AI agent whose actions are being evaluated against constraints.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AgentConfig {
    /// The agent's name (e.g. "triage-assistant").
    #[serde(default)]
    pub name: String,

    /// A list of capabilities the agent possesses (e.g. ["read-patient-data",
    /// "escalate-to-human"]). The constraint engine uses this to determine
    /// which constraints are applicable.
    #[serde(default)]
    pub capabilities: Vec<String>,
}

// ---------------------------------------------------------------------------
// Legacy types — backward compatibility with the original scaffold
// ---------------------------------------------------------------------------

/// Legacy workload configuration (retained for backward compatibility).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WorkloadConfig {
    /// Name of the workload.
    #[serde(default)]
    pub name: String,
    /// Entry point (e.g. "src/lib.rs::process").
    #[serde(default)]
    pub entry: String,
    /// Processing strategy.
    #[serde(default)]
    pub strategy: String,
}

/// Legacy data type configuration.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DataConfig {
    /// Input type descriptor.
    #[serde(default, rename = "input-type")]
    pub input_type: String,
    /// Output type descriptor.
    #[serde(default, rename = "output-type")]
    pub output_type: String,
}

/// Legacy option flags.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Options {
    /// Arbitrary string flags.
    #[serde(default)]
    pub flags: Vec<String>,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Load a manifest from a TOML file at `path`.
///
/// Returns an error if the file cannot be read or parsed.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content =
        std::fs::read_to_string(path).with_context(|| format!("Failed to read: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse: {}", path))
}

/// Validate a parsed manifest, ensuring all required fields are present and
/// that constraint definitions are well-formed.
///
/// Validation rules:
/// 1. `project.name` must be non-empty.
/// 2. Every constraint must have a non-empty `name`, `subject`, and `action`.
/// 3. No two constraints may share the same `name`.
/// 4. `agent.name` must be non-empty.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // -- Legacy validation (backward compat): if workload is used, require name/entry --
    if !manifest.workload.name.is_empty() && manifest.workload.entry.is_empty() {
        anyhow::bail!("workload.entry required when workload.name is set");
    }

    // -- Phase 1 validation --
    if manifest.project.name.is_empty() && manifest.workload.name.is_empty() {
        anyhow::bail!("project.name is required (or legacy workload.name)");
    }

    // Validate each constraint
    let mut seen_names = std::collections::HashSet::new();
    for (idx, constraint) in manifest.constraints.iter().enumerate() {
        if constraint.name.is_empty() {
            anyhow::bail!("constraints[{}].name is required", idx);
        }
        if !seen_names.insert(&constraint.name) {
            anyhow::bail!("duplicate constraint name: '{}'", constraint.name);
        }
        if constraint.subject.is_empty() {
            anyhow::bail!(
                "constraints[{}] '{}': subject is required",
                idx,
                constraint.name
            );
        }
        if constraint.action.is_empty() {
            anyhow::bail!(
                "constraints[{}] '{}': action is required",
                idx,
                constraint.name
            );
        }
    }

    // Agent name required when constraints are defined
    if !manifest.constraints.is_empty() && manifest.agent.name.is_empty() {
        anyhow::bail!("agent.name is required when constraints are defined");
    }

    Ok(())
}

/// Initialise a new `phronesiser.toml` manifest at the given directory path.
///
/// The generated file includes example `[project]`, `[[constraints]]`,
/// `[enforcement]`, and `[agent]` sections.
pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("phronesiser.toml");
    if p.exists() {
        anyhow::bail!("phronesiser.toml already exists");
    }
    std::fs::write(
        &p,
        r#"# phronesiser manifest — ethical constraint definitions
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-agent-project"
version = "0.1.0"
description = "Ethical constraints for my AI agent"

[[constraints]]
name = "respect-privacy"
kind = "prohibition"
subject = "agent"
action = "access-personal-data"
condition = "not user-consent-given"
priority = 90

[[constraints]]
name = "log-decisions"
kind = "obligation"
subject = "agent"
action = "write-audit-log"
priority = 50

[[constraints]]
name = "read-public-data"
kind = "permission"
subject = "agent"
action = "read-public-data"
priority = 10

[enforcement]
mode = "strict"
escalation-threshold = 100
audit-log = true

[agent]
name = "my-agent"
capabilities = ["read-public-data", "write-audit-log"]
"#,
    )?;
    println!("Created {}", p.display());
    Ok(())
}

/// Print a human-readable summary of the manifest to stdout.
pub fn print_info(m: &Manifest) {
    let name = if m.project.name.is_empty() {
        &m.workload.name
    } else {
        &m.project.name
    };
    println!("=== {} ===", name);

    if !m.project.version.is_empty() {
        println!("Version: {}", m.project.version);
    }
    if !m.project.description.is_empty() {
        println!("Description: {}", m.project.description);
    }

    println!("\nAgent: {}", m.agent.name);
    if !m.agent.capabilities.is_empty() {
        println!("Capabilities: {}", m.agent.capabilities.join(", "));
    }

    println!("\nEnforcement: {}", m.enforcement.mode);
    println!(
        "Escalation threshold: {}",
        m.enforcement.escalation_threshold
    );
    println!("Audit log: {}", m.enforcement.audit_log);

    println!("\nConstraints ({}):", m.constraints.len());
    for c in &m.constraints {
        let cond = c.condition.as_deref().unwrap_or("(unconditional)");
        println!(
            "  - [{}] {} | subject={} action={} condition={} priority={}",
            c.kind, c.name, c.subject, c.action, cond, c.priority
        );
    }

    // Legacy fields (if present)
    if !m.workload.name.is_empty() {
        println!("\nLegacy workload: {}", m.workload.name);
        println!("Entry: {}", m.workload.entry);
    }
    if !m.data.input_type.is_empty() {
        println!(
            "Input: {} -> Output: {}",
            m.data.input_type, m.data.output_type
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper to build a minimal valid manifest for testing.
    fn minimal_manifest() -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "test-project".into(),
                version: "0.1.0".into(),
                description: "A test".into(),
            },
            constraints: vec![Constraint {
                name: "c1".into(),
                kind: ConstraintKind::Prohibition,
                subject: "agent".into(),
                action: "do-harm".into(),
                condition: None,
                priority: 10,
            }],
            enforcement: EnforcementConfig::default(),
            agent: AgentConfig {
                name: "test-agent".into(),
                capabilities: vec!["read".into()],
            },
            workload: WorkloadConfig::default(),
            data: DataConfig::default(),
            options: Options::default(),
        }
    }

    #[test]
    fn test_validate_minimal() {
        let m = minimal_manifest();
        assert!(validate(&m).is_ok());
    }

    #[test]
    fn test_validate_empty_project_name_fails() {
        let mut m = minimal_manifest();
        m.project.name = String::new();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_duplicate_constraint_names() {
        let mut m = minimal_manifest();
        m.constraints.push(Constraint {
            name: "c1".into(),
            kind: ConstraintKind::Permission,
            subject: "agent".into(),
            action: "something".into(),
            condition: None,
            priority: 5,
        });
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("duplicate constraint name"));
    }

    #[test]
    fn test_constraint_kind_display() {
        assert_eq!(ConstraintKind::Obligation.to_string(), "obligation");
        assert_eq!(ConstraintKind::Permission.to_string(), "permission");
        assert_eq!(ConstraintKind::Prohibition.to_string(), "prohibition");
    }

    #[test]
    fn test_enforcement_mode_display() {
        assert_eq!(EnforcementMode::Strict.to_string(), "strict");
        assert_eq!(EnforcementMode::Advisory.to_string(), "advisory");
    }

    #[test]
    fn test_parse_manifest_from_toml() {
        let toml_str = r#"
[project]
name = "ethics-demo"
version = "1.0.0"
description = "Demo"

[[constraints]]
name = "no-harm"
kind = "prohibition"
subject = "bot"
action = "harm-user"
priority = 100

[enforcement]
mode = "strict"
escalation-threshold = 50
audit-log = true

[agent]
name = "demo-bot"
capabilities = ["chat", "search"]
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert_eq!(m.project.name, "ethics-demo");
        assert_eq!(m.constraints.len(), 1);
        assert_eq!(m.constraints[0].kind, ConstraintKind::Prohibition);
        assert_eq!(m.agent.capabilities.len(), 2);
        assert_eq!(m.enforcement.escalation_threshold, 50);
    }
}
