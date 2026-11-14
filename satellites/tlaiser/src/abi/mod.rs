// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for tlaiser.
// Rust-side types mirroring the Idris2 ABI formal definitions.
// These types represent TLA+ state machines, transitions, temporal
// properties, and model-checking results.

use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// A named state within a state machine.
///
/// Each state has a unique name (used as a TLA+ constant) and an optional
/// human-readable description for documentation.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct State {
    /// Unique identifier for this state (must be a valid TLA+ identifier).
    pub name: String,
    /// Optional human-readable description.
    #[serde(default)]
    pub description: Option<String>,
}

impl fmt::Display for State {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.name)
    }
}

// ---------------------------------------------------------------------------
// Transition
// ---------------------------------------------------------------------------

/// A transition between two states in a state machine.
///
/// Transitions form the edges of the state graph. Each has a source state,
/// a destination state, an optional guard condition (a TLA+ boolean
/// expression), and an optional action (a TLA+ action formula describing
/// variable updates).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Transition {
    /// Source state name.
    pub from: String,
    /// Destination state name.
    pub to: String,
    /// Optional guard condition (TLA+ boolean expression).
    /// When absent, the transition is always enabled.
    #[serde(default)]
    pub guard: Option<String>,
    /// Optional action body (TLA+ primed-variable assignments).
    /// When absent, only the state variable changes.
    #[serde(default)]
    pub action: Option<String>,
    /// Optional human-readable label for this transition.
    #[serde(default)]
    pub label: Option<String>,
}

impl fmt::Display for Transition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.label {
            Some(lbl) => write!(f, "{} --[{}]--> {}", self.from, lbl, self.to),
            None => write!(f, "{} --> {}", self.from, self.to),
        }
    }
}

// ---------------------------------------------------------------------------
// Variable
// ---------------------------------------------------------------------------

/// A TLA+ variable tracked by the state machine.
///
/// Variables hold auxiliary state beyond the current state-machine node.
/// Each has a name, an initial value expression, and an optional type hint
/// used in the TLC model checker configuration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Variable {
    /// Variable name (must be a valid TLA+ identifier).
    pub name: String,
    /// Initial value as a TLA+ expression string.
    pub init: String,
    /// Optional type hint for TLC (e.g., "Int", "BOOLEAN", "1..10").
    #[serde(default, rename = "type")]
    pub type_hint: Option<String>,
}

// ---------------------------------------------------------------------------
// TemporalProperty
// ---------------------------------------------------------------------------

/// A temporal logic property to verify against the state machine.
///
/// TLA+ supports several temporal operators:
/// - Always (box, `[]`): a predicate holds in every reachable state.
/// - Eventually (diamond, `<>`): a predicate holds in some future state.
/// - LeadsTo (`~>`): if P holds, then Q eventually holds.
/// - WeakFairness (`WF_vars(action)`): if an action is continuously enabled,
///   it must eventually be taken.
/// - StrongFairness (`SF_vars(action)`): if an action is repeatedly enabled,
///   it must eventually be taken.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "formula")]
pub enum TemporalProperty {
    /// `[]P` — P holds in every reachable state (safety).
    #[serde(rename = "safety")]
    Always(String),
    /// `<>P` — P holds in some future state (liveness).
    #[serde(rename = "liveness")]
    Eventually(String),
    /// `P ~> Q` — whenever P holds, Q eventually holds.
    #[serde(rename = "leads-to")]
    LeadsTo {
        antecedent: String,
        consequent: String,
    },
    /// `WF_vars(Action)` — weak fairness constraint.
    #[serde(rename = "weak-fairness")]
    WeakFairness { vars: String, action: String },
    /// `SF_vars(Action)` — strong fairness constraint.
    #[serde(rename = "strong-fairness")]
    StrongFairness { vars: String, action: String },
}

impl fmt::Display for TemporalProperty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TemporalProperty::Always(p) => write!(f, "[]{}", p),
            TemporalProperty::Eventually(p) => write!(f, "<>{}", p),
            TemporalProperty::LeadsTo {
                antecedent,
                consequent,
            } => {
                write!(f, "{} ~> {}", antecedent, consequent)
            }
            TemporalProperty::WeakFairness { vars, action } => {
                write!(f, "WF_{}({})", vars, action)
            }
            TemporalProperty::StrongFairness { vars, action } => {
                write!(f, "SF_{}({})", vars, action)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Property (manifest-level wrapper)
// ---------------------------------------------------------------------------

/// A named property from the manifest, wrapping a TemporalProperty with
/// metadata used for reporting.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Property {
    /// Human-readable name for this property.
    pub name: String,
    /// The kind of property: "safety", "liveness", "fairness".
    pub kind: String,
    /// The TLA+ formula string.
    pub formula: String,
}

// ---------------------------------------------------------------------------
// StateMachine
// ---------------------------------------------------------------------------

/// A complete state machine definition.
///
/// This is the central type in the tlaiser ABI. A StateMachine captures
/// everything needed to generate a TLA+ specification:
/// - The set of states and transitions (the state graph)
/// - Auxiliary variables and their initial values
/// - The initial state
/// - Temporal properties to check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateMachine {
    /// Unique name for this state machine (becomes the TLA+ module name).
    pub name: String,
    /// All states in the machine.
    pub states: Vec<State>,
    /// The name of the initial state (must match one entry in `states`).
    pub initial_state: String,
    /// All transitions between states.
    pub transitions: Vec<Transition>,
    /// Auxiliary variables beyond the implicit `state` variable.
    #[serde(default)]
    pub variables: Vec<Variable>,
    /// Optional description for documentation.
    #[serde(default)]
    pub description: Option<String>,
}

impl StateMachine {
    /// Returns the set of all state names referenced (states + transition endpoints).
    /// Useful for validation: every transition endpoint must be a declared state.
    pub fn all_state_names(&self) -> Vec<&str> {
        self.states.iter().map(|s| s.name.as_str()).collect()
    }

    /// Validates internal consistency of the state machine.
    ///
    /// Checks:
    /// 1. At least one state exists.
    /// 2. The initial state is a declared state.
    /// 3. Every transition references declared states.
    /// 4. No duplicate state names.
    pub fn validate(&self) -> Result<(), Vec<String>> {
        let mut errors = Vec::new();
        let names = self.all_state_names();

        // Check: at least one state
        if self.states.is_empty() {
            errors.push(format!("State machine '{}' has no states", self.name));
        }

        // Check: no duplicate state names
        let mut seen = std::collections::HashSet::new();
        for state in &self.states {
            if !seen.insert(&state.name) {
                errors.push(format!(
                    "Duplicate state name '{}' in machine '{}'",
                    state.name, self.name
                ));
            }
        }

        // Check: initial state exists
        if !names.contains(&self.initial_state.as_str()) {
            errors.push(format!(
                "Initial state '{}' is not a declared state in machine '{}'",
                self.initial_state, self.name
            ));
        }

        // Check: transition endpoints exist
        for t in &self.transitions {
            if !names.contains(&t.from.as_str()) {
                errors.push(format!(
                    "Transition source '{}' is not a declared state in machine '{}'",
                    t.from, self.name
                ));
            }
            if !names.contains(&t.to.as_str()) {
                errors.push(format!(
                    "Transition target '{}' is not a declared state in machine '{}'",
                    t.to, self.name
                ));
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }
}

// ---------------------------------------------------------------------------
// ModelCheckResult
// ---------------------------------------------------------------------------

/// The outcome of a TLC model-checking run.
///
/// Captures whether properties were satisfied, any counterexample traces,
/// and performance metrics from the run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelCheckResult {
    /// Name of the state machine that was checked.
    pub machine_name: String,
    /// Overall outcome: true if all properties held.
    pub success: bool,
    /// Number of distinct states explored by TLC.
    pub states_explored: u64,
    /// Number of distinct states found.
    pub distinct_states: u64,
    /// Per-property results.
    pub property_results: Vec<PropertyResult>,
    /// If a violation was found, the counterexample trace.
    #[serde(default)]
    pub counterexample: Option<Vec<CounterexampleStep>>,
    /// Wall-clock duration of the TLC run in milliseconds.
    pub duration_ms: u64,
}

/// Result for a single property check.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PropertyResult {
    /// Name of the property.
    pub name: String,
    /// Whether this property held.
    pub satisfied: bool,
    /// If violated, a human-readable description of the violation.
    #[serde(default)]
    pub violation: Option<String>,
}

/// A single step in a counterexample trace.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CounterexampleStep {
    /// Step number (0-indexed).
    pub step: usize,
    /// Variable assignments at this step (variable_name -> value_string).
    pub variables: std::collections::HashMap<String, String>,
    /// Which action/transition was taken to reach this step.
    #[serde(default)]
    pub action: Option<String>,
}

// ---------------------------------------------------------------------------
// TLC Configuration
// ---------------------------------------------------------------------------

/// Configuration for the TLC model checker, parsed from the `[tlc]` section
/// of the manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TlcConfig {
    /// Number of worker threads for TLC (default: number of CPUs).
    #[serde(default = "default_workers")]
    pub workers: u32,
    /// Maximum number of states to explore (0 = unlimited).
    #[serde(default)]
    pub max_states: u64,
    /// Whether to use symmetry reduction.
    #[serde(default)]
    pub symmetry: bool,
    /// Additional TLC command-line flags.
    #[serde(default)]
    pub extra_flags: Vec<String>,
}

impl Default for TlcConfig {
    fn default() -> Self {
        Self {
            workers: default_workers(),
            max_states: 0,
            symmetry: false,
            extra_flags: Vec::new(),
        }
    }
}

/// Default number of TLC workers: 4.
fn default_workers() -> u32 {
    4
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test that a well-formed state machine passes validation.
    #[test]
    fn test_valid_state_machine() {
        let sm = StateMachine {
            name: "TestMachine".to_string(),
            states: vec![
                State {
                    name: "Idle".into(),
                    description: None,
                },
                State {
                    name: "Running".into(),
                    description: None,
                },
            ],
            initial_state: "Idle".into(),
            transitions: vec![Transition {
                from: "Idle".into(),
                to: "Running".into(),
                guard: None,
                action: None,
                label: Some("start".into()),
            }],
            variables: vec![],
            description: None,
        };
        assert!(sm.validate().is_ok());
    }

    /// Test that a state machine with an invalid initial state fails.
    #[test]
    fn test_invalid_initial_state() {
        let sm = StateMachine {
            name: "Bad".to_string(),
            states: vec![State {
                name: "A".into(),
                description: None,
            }],
            initial_state: "NonExistent".into(),
            transitions: vec![],
            variables: vec![],
            description: None,
        };
        let errs = sm.validate().unwrap_err();
        assert!(errs.iter().any(|e| e.contains("NonExistent")));
    }

    /// Test that transitions referencing undeclared states fail validation.
    #[test]
    fn test_invalid_transition_target() {
        let sm = StateMachine {
            name: "Bad".to_string(),
            states: vec![State {
                name: "A".into(),
                description: None,
            }],
            initial_state: "A".into(),
            transitions: vec![Transition {
                from: "A".into(),
                to: "B".into(),
                guard: None,
                action: None,
                label: None,
            }],
            variables: vec![],
            description: None,
        };
        let errs = sm.validate().unwrap_err();
        assert!(errs.iter().any(|e| e.contains("'B'")));
    }

    /// Test TemporalProperty Display formatting.
    #[test]
    fn test_temporal_property_display() {
        let always = TemporalProperty::Always("safe".into());
        assert_eq!(format!("{}", always), "[]safe");

        let eventually = TemporalProperty::Eventually("done".into());
        assert_eq!(format!("{}", eventually), "<>done");

        let leads_to = TemporalProperty::LeadsTo {
            antecedent: "req".into(),
            consequent: "resp".into(),
        };
        assert_eq!(format!("{}", leads_to), "req ~> resp");

        let wf = TemporalProperty::WeakFairness {
            vars: "vars".into(),
            action: "Act".into(),
        };
        assert_eq!(format!("{}", wf), "WF_vars(Act)");
    }

    /// Test Transition Display formatting.
    #[test]
    fn test_transition_display() {
        let t = Transition {
            from: "A".into(),
            to: "B".into(),
            guard: None,
            action: None,
            label: Some("go".into()),
        };
        assert_eq!(format!("{}", t), "A --[go]--> B");

        let t2 = Transition {
            from: "X".into(),
            to: "Y".into(),
            guard: None,
            action: None,
            label: None,
        };
        assert_eq!(format!("{}", t2), "X --> Y");
    }
}
