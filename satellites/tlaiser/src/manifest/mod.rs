// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for tlaiser.toml.
//
// The tlaiser manifest describes state machines, their transitions,
// temporal properties to verify, and TLC model checker configuration.
// This module handles parsing, validation, and initialisation of
// manifest files.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi;

// ---------------------------------------------------------------------------
// Top-level manifest
// ---------------------------------------------------------------------------

/// Top-level tlaiser manifest, parsed from `tlaiser.toml`.
///
/// Contains project metadata, one or more state machine definitions,
/// temporal properties to verify, and TLC configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    pub project: ProjectConfig,
    /// State machine definitions. At least one is required.
    #[serde(rename = "state-machines", alias = "state_machines")]
    pub state_machines: Vec<StateMachineConfig>,
    /// Temporal properties to check across all machines.
    #[serde(default, rename = "properties", alias = "property")]
    pub properties: Vec<PropertyConfig>,
    /// TLC model checker configuration.
    #[serde(default)]
    pub tlc: abi::TlcConfig,
}

// ---------------------------------------------------------------------------
// Project config
// ---------------------------------------------------------------------------

/// Project-level metadata from the `[project]` section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name.
    pub name: String,
    /// Optional version string.
    #[serde(default)]
    pub version: Option<String>,
    /// Optional description.
    #[serde(default)]
    pub description: Option<String>,
}

// ---------------------------------------------------------------------------
// State machine config
// ---------------------------------------------------------------------------

/// A single `[[state-machines]]` entry in the manifest.
///
/// Describes a state machine with its states, transitions, and variables.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateMachineConfig {
    /// Unique name for this state machine (becomes the TLA+ module name).
    pub name: String,
    /// List of state names.
    pub states: Vec<String>,
    /// The initial state (must be one of `states`).
    #[serde(rename = "initial-state", alias = "initial_state")]
    pub initial_state: String,
    /// Transitions between states.
    #[serde(default, rename = "transitions", alias = "transition")]
    pub transitions: Vec<TransitionConfig>,
    /// Auxiliary variables beyond the implicit `state` variable.
    #[serde(default)]
    pub variables: Vec<VariableConfig>,
    /// Optional description.
    #[serde(default)]
    pub description: Option<String>,
}

/// A single `[[state-machines.transitions]]` entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransitionConfig {
    /// Source state name.
    pub from: String,
    /// Destination state name.
    pub to: String,
    /// Optional guard condition (TLA+ boolean expression).
    #[serde(default)]
    pub guard: Option<String>,
    /// Optional action body (TLA+ primed-variable assignments).
    #[serde(default)]
    pub action: Option<String>,
    /// Optional label for this transition.
    #[serde(default)]
    pub label: Option<String>,
}

/// A single variable entry in `state-machines.variables`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VariableConfig {
    /// Variable name.
    pub name: String,
    /// Initial value as a TLA+ expression.
    pub init: String,
    /// Optional type hint for TLC override.
    #[serde(default, rename = "type")]
    pub type_hint: Option<String>,
}

// ---------------------------------------------------------------------------
// Property config
// ---------------------------------------------------------------------------

/// A `[[properties]]` entry describing a temporal property to check.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PropertyConfig {
    /// Human-readable property name.
    pub name: String,
    /// Kind of property: "safety", "liveness", or "fairness".
    pub kind: String,
    /// TLA+ formula string. For safety: predicate under `[]`.
    /// For liveness: predicate under `<>`. For fairness: full formula.
    pub formula: String,
}

// ---------------------------------------------------------------------------
// Conversion to ABI types
// ---------------------------------------------------------------------------

impl StateMachineConfig {
    /// Convert manifest config to the ABI StateMachine type.
    pub fn to_abi(&self) -> abi::StateMachine {
        abi::StateMachine {
            name: self.name.clone(),
            states: self
                .states
                .iter()
                .map(|s| abi::State {
                    name: s.clone(),
                    description: None,
                })
                .collect(),
            initial_state: self.initial_state.clone(),
            transitions: self
                .transitions
                .iter()
                .map(|t| abi::Transition {
                    from: t.from.clone(),
                    to: t.to.clone(),
                    guard: t.guard.clone(),
                    action: t.action.clone(),
                    label: t.label.clone(),
                })
                .collect(),
            variables: self
                .variables
                .iter()
                .map(|v| abi::Variable {
                    name: v.name.clone(),
                    init: v.init.clone(),
                    type_hint: v.type_hint.clone(),
                })
                .collect(),
            description: self.description.clone(),
        }
    }
}

impl PropertyConfig {
    /// Convert manifest property to ABI Property type.
    pub fn to_abi(&self) -> abi::Property {
        abi::Property {
            name: self.name.clone(),
            kind: self.kind.clone(),
            formula: self.formula.clone(),
        }
    }
}

// ---------------------------------------------------------------------------
// Loading and validation
// ---------------------------------------------------------------------------

/// Load a manifest from a TOML file at the given path.
///
/// Returns a parsed `Manifest` or an error if the file cannot be read
/// or parsed.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a parsed manifest for internal consistency.
///
/// Checks:
/// 1. Project name is non-empty.
/// 2. At least one state machine is defined.
/// 3. Each state machine passes ABI-level validation.
/// 4. Each property references a valid kind.
/// 5. Property formulas are non-empty.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }

    // At least one state machine
    if manifest.state_machines.is_empty() {
        anyhow::bail!("At least one [[state-machines]] entry is required");
    }

    // Validate each state machine
    for sm_cfg in &manifest.state_machines {
        let sm = sm_cfg.to_abi();
        if let Err(errors) = sm.validate() {
            anyhow::bail!(
                "State machine '{}' validation failed:\n  {}",
                sm.name,
                errors.join("\n  ")
            );
        }
    }

    // Validate properties
    let valid_kinds = ["safety", "liveness", "fairness"];
    for prop in &manifest.properties {
        if prop.name.is_empty() {
            anyhow::bail!("Property name cannot be empty");
        }
        if !valid_kinds.contains(&prop.kind.as_str()) {
            anyhow::bail!(
                "Property '{}' has invalid kind '{}'. Must be one of: {}",
                prop.name,
                prop.kind,
                valid_kinds.join(", ")
            );
        }
        if prop.formula.is_empty() {
            anyhow::bail!("Property '{}' has an empty formula", prop.name);
        }
    }

    Ok(())
}

/// Initialise a new `tlaiser.toml` manifest at the given directory path.
///
/// Creates a well-commented template with a simple two-state machine
/// and one safety property to get users started.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("tlaiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("tlaiser.toml already exists");
    }
    let template = r#"# tlaiser manifest — state machine model checking with TLA+/PlusCal
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-protocol"
version = "0.1.0"
description = "A state machine protocol to model-check"

# Define one or more state machines.
# Each becomes a separate TLA+ module.

[[state-machines]]
name = "SimpleProtocol"
states = ["Idle", "Running", "Done"]
initial-state = "Idle"
description = "A simple three-state protocol"

  [[state-machines.transitions]]
  from = "Idle"
  to = "Running"
  label = "start"

  [[state-machines.transitions]]
  from = "Running"
  to = "Done"
  label = "finish"

  [[state-machines.transitions]]
  from = "Done"
  to = "Idle"
  label = "reset"

# Temporal properties to verify.
# kind: "safety" ([] always), "liveness" (<> eventually), "fairness" (WF/SF)

[[properties]]
name = "AlwaysValid"
kind = "safety"
formula = "state \\in {\"Idle\", \"Running\", \"Done\"}"

[[properties]]
name = "EventuallyDone"
kind = "liveness"
formula = "state = \"Done\""

# TLC model checker configuration.

[tlc]
workers = 4
max-states = 100000
symmetry = false
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print human-readable information about a manifest.
pub fn print_info(manifest: &Manifest) {
    println!("=== tlaiser: {} ===", manifest.project.name);
    if let Some(ref desc) = manifest.project.description {
        println!("Description: {}", desc);
    }
    println!();
    println!("State Machines ({}):", manifest.state_machines.len());
    for sm in &manifest.state_machines {
        println!(
            "  {} — {} states, {} transitions, initial: {}",
            sm.name,
            sm.states.len(),
            sm.transitions.len(),
            sm.initial_state
        );
        if !sm.variables.is_empty() {
            println!(
                "    Variables: {}",
                sm.variables
                    .iter()
                    .map(|v| v.name.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            );
        }
    }
    println!();
    println!("Properties ({}):", manifest.properties.len());
    for p in &manifest.properties {
        println!("  [{}] {} — {}", p.kind, p.name, p.formula);
    }
    println!();
    println!(
        "TLC: {} workers, max-states={}, symmetry={}",
        manifest.tlc.workers,
        if manifest.tlc.max_states == 0 {
            "unlimited".to_string()
        } else {
            manifest.tlc.max_states.to_string()
        },
        manifest.tlc.symmetry
    );
}
