// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// State machine definition validator for tlaiser.
//
// This module performs deep validation of state machine definitions
// beyond the basic structural checks in the ABI module. It verifies
// TLA+-specific constraints such as identifier validity, reachability,
// and determinism analysis.

use anyhow::{Result, bail};
use std::collections::{HashMap, HashSet, VecDeque};

use crate::abi::StateMachine;

/// Validate a state machine definition for TLA+ code generation.
///
/// Performs the following checks:
/// 1. ABI-level structural validation (states exist, transitions valid).
/// 2. All state names are valid TLA+ identifiers.
/// 3. All variable names are valid TLA+ identifiers.
/// 4. The state machine name is a valid TLA+ module name.
/// 5. Every state is reachable from the initial state.
/// 6. No orphan transitions (transitions from unreachable states).
pub fn validate_state_machine(sm: &StateMachine) -> Result<()> {
    // Structural validation via ABI
    if let Err(errors) = sm.validate() {
        bail!("Structural validation failed:\n  {}", errors.join("\n  "));
    }

    // Check: machine name is a valid TLA+ identifier
    validate_tla_identifier(&sm.name, "state machine name")?;

    // Check: all state names are valid TLA+ identifiers
    for state in &sm.states {
        validate_tla_identifier(&state.name, &format!("state name '{}'", state.name))?;
    }

    // Check: all variable names are valid TLA+ identifiers
    for var in &sm.variables {
        validate_tla_identifier(&var.name, &format!("variable name '{}'", var.name))?;
    }

    // Check: reachability — every state must be reachable from initial_state
    check_reachability(sm)?;

    Ok(())
}

/// Verify that a string is a valid TLA+ identifier.
///
/// TLA+ identifiers must:
/// - Start with a letter (a-z, A-Z)
/// - Contain only letters, digits, and underscores
/// - Not be a TLA+ reserved word
fn validate_tla_identifier(name: &str, context: &str) -> Result<()> {
    if name.is_empty() {
        bail!("{} cannot be empty", context);
    }

    let first = name.chars().next().unwrap();
    if !first.is_ascii_alphabetic() {
        bail!(
            "{} '{}' must start with a letter (got '{}')",
            context,
            name,
            first
        );
    }

    for ch in name.chars() {
        if !ch.is_ascii_alphanumeric() && ch != '_' {
            bail!(
                "{} '{}' contains invalid character '{}'. \
                 Only letters, digits, and underscores are allowed.",
                context,
                name,
                ch
            );
        }
    }

    // TLA+ reserved words that cannot be used as identifiers.
    let reserved = [
        "ASSUME",
        "ASSUMPTION",
        "AXIOM",
        "CASE",
        "CHOOSE",
        "CONSTANT",
        "CONSTANTS",
        "DOMAIN",
        "ELSE",
        "ENABLED",
        "EXCEPT",
        "EXTENDS",
        "IF",
        "IN",
        "INSTANCE",
        "LET",
        "LOCAL",
        "MODULE",
        "OTHER",
        "PRINT",
        "RECURSIVE",
        "SUBSET",
        "THEN",
        "THEOREM",
        "UNCHANGED",
        "UNION",
        "VARIABLE",
        "VARIABLES",
        "WITH",
        "WF_",
        "SF_",
        "TRUE",
        "FALSE",
    ];
    if reserved.contains(&name) {
        bail!(
            "{} '{}' is a TLA+ reserved word and cannot be used as an identifier",
            context,
            name
        );
    }

    Ok(())
}

/// Check that every declared state is reachable from the initial state
/// via the transition graph.
///
/// This uses a breadth-first search from the initial state through
/// the transition edges. Any unreachable state triggers a warning
/// (returned as an error for strictness).
fn check_reachability(sm: &StateMachine) -> Result<()> {
    // Build adjacency list from transitions
    let mut adjacency: HashMap<&str, Vec<&str>> = HashMap::new();
    for state in &sm.states {
        adjacency.entry(state.name.as_str()).or_default();
    }
    for t in &sm.transitions {
        adjacency
            .entry(t.from.as_str())
            .or_default()
            .push(t.to.as_str());
    }

    // BFS from initial state
    let mut visited: HashSet<&str> = HashSet::new();
    let mut queue: VecDeque<&str> = VecDeque::new();
    queue.push_back(sm.initial_state.as_str());
    visited.insert(sm.initial_state.as_str());

    while let Some(current) = queue.pop_front() {
        if let Some(neighbours) = adjacency.get(current) {
            for &next in neighbours {
                if visited.insert(next) {
                    queue.push_back(next);
                }
            }
        }
    }

    // Check all states were visited
    let unreachable: Vec<&str> = sm
        .states
        .iter()
        .filter(|s| !visited.contains(s.name.as_str()))
        .map(|s| s.name.as_str())
        .collect();

    if !unreachable.is_empty() {
        bail!(
            "Unreachable states in machine '{}': {}. \
             All states must be reachable from initial state '{}'.",
            sm.name,
            unreachable.join(", "),
            sm.initial_state
        );
    }

    Ok(())
}

/// Analyse the state machine for non-deterministic transitions.
///
/// Returns a list of (state, count) pairs where a state has multiple
/// outgoing transitions without guards. This is informational — TLA+
/// handles non-determinism via disjunction — but useful for user feedback.
pub fn find_nondeterministic_states(sm: &StateMachine) -> Vec<(String, usize)> {
    let mut outgoing: HashMap<&str, Vec<&crate::abi::Transition>> = HashMap::new();
    for t in &sm.transitions {
        outgoing.entry(t.from.as_str()).or_default().push(t);
    }

    let mut results = Vec::new();
    for (state, transitions) in &outgoing {
        let unguarded_count = transitions.iter().filter(|t| t.guard.is_none()).count();
        if unguarded_count > 1 {
            results.push((state.to_string(), unguarded_count));
        }
    }
    results.sort_by(|a, b| a.0.cmp(&b.0));
    results
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::{State, StateMachine, Transition};

    /// Helper to build a simple state machine for testing.
    fn simple_machine() -> StateMachine {
        StateMachine {
            name: "Test".to_string(),
            states: vec![
                State {
                    name: "A".into(),
                    description: None,
                },
                State {
                    name: "B".into(),
                    description: None,
                },
            ],
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
        }
    }

    #[test]
    fn test_valid_machine_passes() {
        let sm = simple_machine();
        assert!(validate_state_machine(&sm).is_ok());
    }

    #[test]
    fn test_invalid_identifier_rejected() {
        assert!(validate_tla_identifier("123bad", "test").is_err());
        assert!(validate_tla_identifier("has space", "test").is_err());
        assert!(validate_tla_identifier("", "test").is_err());
        assert!(validate_tla_identifier("VARIABLES", "test").is_err());
    }

    #[test]
    fn test_valid_identifier_accepted() {
        assert!(validate_tla_identifier("GoodName", "test").is_ok());
        assert!(validate_tla_identifier("state_1", "test").is_ok());
        assert!(validate_tla_identifier("X", "test").is_ok());
    }

    #[test]
    fn test_unreachable_state_rejected() {
        let sm = StateMachine {
            name: "Unreachable".to_string(),
            states: vec![
                State {
                    name: "A".into(),
                    description: None,
                },
                State {
                    name: "B".into(),
                    description: None,
                },
                State {
                    name: "C".into(),
                    description: None,
                },
            ],
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
        let result = validate_state_machine(&sm);
        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("C"));
    }

    #[test]
    fn test_nondeterministic_detection() {
        let sm = StateMachine {
            name: "NonDet".to_string(),
            states: vec![
                State {
                    name: "A".into(),
                    description: None,
                },
                State {
                    name: "B".into(),
                    description: None,
                },
                State {
                    name: "C".into(),
                    description: None,
                },
            ],
            initial_state: "A".into(),
            transitions: vec![
                Transition {
                    from: "A".into(),
                    to: "B".into(),
                    guard: None,
                    action: None,
                    label: None,
                },
                Transition {
                    from: "A".into(),
                    to: "C".into(),
                    guard: None,
                    action: None,
                    label: None,
                },
                Transition {
                    from: "B".into(),
                    to: "C".into(),
                    guard: None,
                    action: None,
                    label: None,
                },
            ],
            variables: vec![],
            description: None,
        };
        let nondet = find_nondeterministic_states(&sm);
        assert_eq!(nondet.len(), 1);
        assert_eq!(nondet[0].0, "A");
        assert_eq!(nondet[0].1, 2);
    }
}
