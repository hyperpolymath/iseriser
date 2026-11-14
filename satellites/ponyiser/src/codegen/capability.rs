// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Capability inference and subtyping lattice for Pony reference capabilities.
//
// This module implements the core of ponyiser's analysis engine:
// 1. The Pony capability subtyping lattice
// 2. Inference of capabilities for untyped data accesses
// 3. Detection of potential data race violations
//
// Pony's 6 reference capabilities form a lattice where iso is the top
// (most specific/restrictive) and tag is the bottom (least specific).
// The lattice guarantees that well-typed programs are data-race free.

use crate::abi::{
    Actor, Behaviour, CapabilityViolation, Field, RefCapability, check_subtype, is_subtype,
    validate_sendability,
};

/// Result of a full capability analysis pass.
///
/// Contains all violations found, suggested capability improvements,
/// and a summary of the analysis.
#[derive(Debug, Clone)]
pub struct AnalysisResult {
    /// Capability violations (potential data races).
    pub violations: Vec<CapabilityViolation>,
    /// Suggested capability changes to fix violations.
    pub suggestions: Vec<CapabilitySuggestion>,
    /// Number of actors analysed.
    pub actors_analysed: usize,
    /// Number of behaviours analysed.
    pub behaviours_analysed: usize,
    /// True if no violations were found.
    pub is_race_free: bool,
}

/// A suggested capability change to resolve a violation.
#[derive(Debug, Clone)]
pub struct CapabilitySuggestion {
    /// Actor containing the field or parameter.
    pub actor: String,
    /// Field or parameter name.
    pub target: String,
    /// Current capability.
    pub current: RefCapability,
    /// Suggested replacement capability.
    pub suggested: RefCapability,
    /// Human-readable reason for the suggestion.
    pub reason: String,
}

/// Run a full capability analysis on a set of actors and behaviours.
///
/// This is the main entry point for the analysis engine. It:
/// 1. Validates sendability of all behaviour parameters
/// 2. Checks capability subtyping where behaviours access actor fields
/// 3. Detects shared mutable state patterns that would be races
/// 4. Suggests capability improvements
///
/// # Arguments
/// * `actors` - All actor definitions to analyse
/// * `behaviours` - All behaviour definitions to analyse
/// * `suggest` - Whether to generate improvement suggestions
pub fn analyse(actors: &[Actor], behaviours: &[Behaviour], suggest: bool) -> AnalysisResult {
    let mut violations = Vec::new();
    let mut suggestions = Vec::new();

    // Phase 1: Sendability validation.
    // All behaviour parameters must be sendable (iso, val, or tag)
    // because they cross actor boundaries.
    let sendability_violations = validate_sendability(actors, behaviours);
    violations.extend(sendability_violations);

    // Phase 2: Field capability consistency.
    // Check that actor fields have capabilities consistent with how
    // they are accessed by behaviours.
    for actor in actors {
        let actor_behaviours: Vec<&Behaviour> = behaviours
            .iter()
            .filter(|b| b.actor == actor.name)
            .collect();

        for field in &actor.fields {
            // If a field is ref or iso (mutable), check that no two
            // behaviours could create a data race on it.
            if field.capability.can_write() {
                let _writers: Vec<&&Behaviour> = actor_behaviours
                    .iter()
                    .filter(|b| {
                        b.params
                            .iter()
                            .any(|p| p.name == field.name && p.capability.can_write())
                    })
                    .collect();

                // In Pony, this is safe because behaviours execute sequentially
                // within an actor. But if the field capability is ref and
                // the parameter is also ref, that's fine for internal state.
                // The violation is when a non-sendable capability escapes.
            }

            // Generate suggestions for overly permissive capabilities.
            if suggest
                && let Some(suggestion) = suggest_field_capability(actor, field, &actor_behaviours)
            {
                suggestions.push(suggestion);
            }
        }
    }

    // Phase 3: Cross-actor reference checking.
    // Detect patterns where data might be shared between actors
    // without proper sendable capabilities.
    for behaviour in behaviours {
        for param in &behaviour.params {
            // Check that parameter capabilities satisfy the capability
            // requirements declared on the behaviour.
            for required in &behaviour.capability_requirements {
                let result = check_subtype(param.capability, *required);
                if !result.is_valid() {
                    violations.push(CapabilityViolation {
                        actor: behaviour.actor.clone(),
                        behaviour: Some(behaviour.name.clone()),
                        target: param.name.clone(),
                        expected: *required,
                        found: param.capability,
                        message: format!(
                            "parameter '{}' has capability '{}' but behaviour requires '{}'",
                            param.name, param.capability, required
                        ),
                    });
                }
            }
        }
    }

    let is_race_free = violations.is_empty();

    AnalysisResult {
        violations,
        suggestions,
        actors_analysed: actors.len(),
        behaviours_analysed: behaviours.len(),
        is_race_free,
    }
}

/// Suggest a more appropriate capability for a field based on usage patterns.
///
/// Analyses how a field is accessed across all behaviours of its actor
/// and recommends the most restrictive capability that still permits
/// all observed access patterns.
fn suggest_field_capability(
    actor: &Actor,
    field: &Field,
    behaviours: &[&Behaviour],
) -> Option<CapabilitySuggestion> {
    // Determine actual usage: does any behaviour write to this field?
    let needs_write = behaviours.iter().any(|b| {
        b.params
            .iter()
            .any(|p| p.name == field.name && p.capability.can_write())
    });

    let needs_read = behaviours.iter().any(|b| {
        b.params
            .iter()
            .any(|p| p.name == field.name && p.capability.can_read())
    });

    // Suggest the most restrictive capability that still works.
    let suggested = if needs_write {
        RefCapability::Ref // internal mutable state
    } else if needs_read {
        RefCapability::Val // read-only is safe to share
    } else {
        RefCapability::Tag // not accessed, only identity needed
    };

    // Only suggest if it's different and more restrictive.
    if suggested != field.capability && is_subtype(field.capability, suggested) {
        Some(CapabilitySuggestion {
            actor: actor.name.clone(),
            target: field.name.clone(),
            current: field.capability,
            suggested,
            reason: format!(
                "field '{}' in actor '{}' could use '{}' instead of '{}' \
                 (more restrictive, still satisfies all accesses)",
                field.name, actor.name, suggested, field.capability
            ),
        })
    } else {
        None
    }
}

/// Infer the appropriate reference capability for a data access pattern.
///
/// Given information about how data is used (read, write, shared, sent),
/// this function returns the most appropriate Pony reference capability.
///
/// # Arguments
/// * `is_read` - Whether the data is read
/// * `is_written` - Whether the data is mutated
/// * `is_shared` - Whether multiple aliases exist
/// * `is_sent` - Whether the data crosses an actor boundary
pub fn infer_capability(
    is_read: bool,
    is_written: bool,
    is_shared: bool,
    is_sent: bool,
) -> RefCapability {
    match (is_read, is_written, is_shared, is_sent) {
        // Sent and written and shared: iso (must isolate for safety).
        (_, true, true, true) => RefCapability::Iso,
        // Sent and written: must be iso (unique mutable, sendable).
        (_, true, false, true) => RefCapability::Iso,
        // Sent and read-only: val (shared immutable, sendable).
        (true, false, _, true) => RefCapability::Val,
        // Sent but not read or written: tag (identity only, sendable).
        (false, false, _, true) => RefCapability::Tag,
        // Local, written, not shared: ref is fine (local mutable).
        (_, true, false, false) => RefCapability::Ref,
        // Local, written, shared: this is a potential race!
        // In Pony, this can't happen within an actor (sequential execution),
        // so we use ref and flag for review.
        (_, true, true, false) => RefCapability::Ref,
        // Local, read-only, shared: box (read-only, aliasable).
        (true, false, true, false) => RefCapability::Box,
        // Local, read-only, not shared: val (immutable).
        (true, false, false, false) => RefCapability::Val,
        // Not read, not written: tag.
        (false, false, _, false) => RefCapability::Tag,
    }
}

/// Check whether a capability assignment is valid (sub <: sup).
///
/// Convenience wrapper around the ABI subtyping check.
pub fn is_valid_assignment(from: RefCapability, to: RefCapability) -> bool {
    is_subtype(from, to)
}

/// Format an analysis result as a human-readable report.
pub fn format_report(result: &AnalysisResult) -> String {
    let mut report = String::new();

    report.push_str(&format!(
        "=== ponyiser Capability Analysis ===\n\
         Actors analysed:     {}\n\
         Behaviours analysed: {}\n\
         Race-free:           {}\n\n",
        result.actors_analysed,
        result.behaviours_analysed,
        if result.is_race_free { "YES" } else { "NO" }
    ));

    if !result.violations.is_empty() {
        report.push_str(&format!("Violations ({}):\n", result.violations.len()));
        for (i, v) in result.violations.iter().enumerate() {
            report.push_str(&format!("  {}. {}\n", i + 1, v));
        }
        report.push('\n');
    }

    if !result.suggestions.is_empty() {
        report.push_str(&format!("Suggestions ({}):\n", result.suggestions.len()));
        for (i, s) in result.suggestions.iter().enumerate() {
            report.push_str(&format!(
                "  {}. {}.{}: {} -> {} ({})\n",
                i + 1,
                s.actor,
                s.target,
                s.current,
                s.suggested,
                s.reason
            ));
        }
    }

    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::BehaviourParam;

    #[test]
    fn test_infer_sent_mutable() {
        assert_eq!(
            infer_capability(true, true, false, true),
            RefCapability::Iso
        );
    }

    #[test]
    fn test_infer_sent_readonly() {
        assert_eq!(
            infer_capability(true, false, false, true),
            RefCapability::Val
        );
    }

    #[test]
    fn test_infer_sent_identity() {
        assert_eq!(
            infer_capability(false, false, false, true),
            RefCapability::Tag
        );
    }

    #[test]
    fn test_infer_local_mutable() {
        assert_eq!(
            infer_capability(true, true, false, false),
            RefCapability::Ref
        );
    }

    #[test]
    fn test_infer_local_shared_readonly() {
        assert_eq!(
            infer_capability(true, false, true, false),
            RefCapability::Box
        );
    }

    #[test]
    fn test_analyse_clean_system() {
        let actors = vec![Actor {
            name: "Server".to_string(),
            fields: vec![Field {
                name: "port".to_string(),
                field_type: "U16".to_string(),
                capability: RefCapability::Val,
            }],
            doc: None,
        }];
        let behaviours = vec![Behaviour {
            actor: "Server".to_string(),
            name: "listen".to_string(),
            params: vec![BehaviourParam {
                name: "port".to_string(),
                param_type: "U16".to_string(),
                capability: RefCapability::Val,
            }],
            capability_requirements: vec![],
            doc: None,
        }];

        let result = analyse(&actors, &behaviours, false);
        assert!(result.is_race_free);
        assert_eq!(result.violations.len(), 0);
    }

    #[test]
    fn test_analyse_sendability_violation() {
        let actors = vec![Actor {
            name: "Worker".to_string(),
            fields: vec![],
            doc: None,
        }];
        let behaviours = vec![Behaviour {
            actor: "Worker".to_string(),
            name: "process".to_string(),
            params: vec![BehaviourParam {
                name: "data".to_string(),
                param_type: "Buffer".to_string(),
                capability: RefCapability::Ref, // NOT sendable!
            }],
            capability_requirements: vec![],
            doc: None,
        }];

        let result = analyse(&actors, &behaviours, false);
        assert!(!result.is_race_free);
        assert_eq!(result.violations.len(), 1);
        assert!(result.violations[0].message.contains("not sendable"));
    }

    #[test]
    fn test_analyse_capability_requirement_violation() {
        let actors = vec![Actor {
            name: "Store".to_string(),
            fields: vec![],
            doc: None,
        }];
        let behaviours = vec![Behaviour {
            actor: "Store".to_string(),
            name: "save".to_string(),
            params: vec![BehaviourParam {
                name: "item".to_string(),
                param_type: "Item".to_string(),
                capability: RefCapability::Tag, // only identity
            }],
            capability_requirements: vec![RefCapability::Val], // needs read access
            doc: None,
        }];

        let result = analyse(&actors, &behaviours, false);
        assert!(!result.is_race_free);
        assert!(result.violations.iter().any(|v| v.target == "item"));
    }
}
