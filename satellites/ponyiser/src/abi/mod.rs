// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for ponyiser.
// Rust-side types mirroring the Idris2 ABI formal definitions.
// The Idris2 proofs guarantee correctness; this module provides runtime types.
//
// Pony's 6 reference capabilities form a subtyping lattice:
//   tag ⊆ box ⊆ val   (read path)
//   tag ⊆ box ⊆ ref   (write path)
//   iso, trn, val are sendable across actor boundaries
//   iso is the unique/isolated capability (read + write, exclusive)
//   trn is transitional (write, becomes val when consumed)

use serde::{Deserialize, Serialize};
use std::fmt;

/// The 6 Pony reference capabilities.
///
/// These form a subtyping lattice that guarantees data-race freedom at
/// compile time without locks. Each capability restricts how a reference
/// may be aliased and whether it permits reads, writes, or both.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RefCapability {
    /// Isolated: read-write, no other aliases exist. Sendable.
    Iso,
    /// Value: read-only, deeply immutable. Sendable.
    Val,
    /// Reference: read-write, locally aliasable. Not sendable.
    Ref,
    /// Box: read-only, locally aliasable. Not sendable.
    Box,
    /// Transitional: read-write, becomes val on consumption. Sendable.
    Trn,
    /// Tag: opaque identity only, no read/write. Sendable.
    Tag,
}

impl fmt::Display for RefCapability {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RefCapability::Iso => write!(f, "iso"),
            RefCapability::Val => write!(f, "val"),
            RefCapability::Ref => write!(f, "ref"),
            RefCapability::Box => write!(f, "box"),
            RefCapability::Trn => write!(f, "trn"),
            RefCapability::Tag => write!(f, "tag"),
        }
    }
}

impl RefCapability {
    /// Parse a reference capability from a string.
    ///
    /// Accepts lowercase Pony keywords: iso, val, ref, box, trn, tag.
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Option<RefCapability> {
        match s.trim().to_lowercase().as_str() {
            "iso" => Some(RefCapability::Iso),
            "val" => Some(RefCapability::Val),
            "ref" => Some(RefCapability::Ref),
            "box" => Some(RefCapability::Box),
            "trn" => Some(RefCapability::Trn),
            "tag" => Some(RefCapability::Tag),
            _ => None,
        }
    }

    /// Returns true if this capability allows reading the referenced data.
    pub fn can_read(&self) -> bool {
        matches!(
            self,
            RefCapability::Iso
                | RefCapability::Val
                | RefCapability::Ref
                | RefCapability::Box
                | RefCapability::Trn
        )
    }

    /// Returns true if this capability allows writing the referenced data.
    pub fn can_write(&self) -> bool {
        matches!(
            self,
            RefCapability::Iso | RefCapability::Ref | RefCapability::Trn
        )
    }

    /// Returns true if a value with this capability can be sent across actor boundaries.
    ///
    /// In Pony, only iso, val, and tag are sendable. trn can be consumed
    /// to produce a val for sending.
    pub fn is_sendable(&self) -> bool {
        matches!(
            self,
            RefCapability::Iso | RefCapability::Val | RefCapability::Tag
        )
    }

    /// Returns all 6 reference capabilities in lattice order.
    pub fn all() -> &'static [RefCapability] {
        &[
            RefCapability::Iso,
            RefCapability::Trn,
            RefCapability::Ref,
            RefCapability::Val,
            RefCapability::Box,
            RefCapability::Tag,
        ]
    }
}

/// Result of a subtyping check between two reference capabilities.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubtypingResult {
    /// `sub` is a subtype of `sup` — the assignment is valid.
    Valid {
        sub: RefCapability,
        sup: RefCapability,
    },
    /// `sub` is NOT a subtype of `sup` — the assignment is invalid.
    Invalid {
        sub: RefCapability,
        sup: RefCapability,
        reason: String,
    },
}

impl SubtypingResult {
    /// Returns true if the subtyping check passed.
    pub fn is_valid(&self) -> bool {
        matches!(self, SubtypingResult::Valid { .. })
    }
}

/// Check whether `sub` is a subtype of `sup` in the Pony capability lattice.
///
/// The Pony subtyping lattice:
///   - Every capability is a subtype of itself (reflexivity).
///   - tag ⊆ box ⊆ val (read path: val is the "most readable")
///   - tag ⊆ box ⊆ ref (write path: ref is "most mutable locally")
///   - iso ⊆ trn ⊆ ref (unique/transitional path)
///   - iso ⊆ trn ⊆ val (unique/transitional to immutable)
///   - iso ⊆ val, iso ⊆ ref (iso is the top/most specific)
///   - tag is the bottom (least specific)
///
/// In Pony's actual type system, a more specific capability (higher in the
/// lattice) can be used where a less specific one is expected. iso is the
/// most specific, tag is the least.
pub fn check_subtype(sub: RefCapability, sup: RefCapability) -> SubtypingResult {
    if is_subtype(sub, sup) {
        SubtypingResult::Valid { sub, sup }
    } else {
        SubtypingResult::Invalid {
            sub,
            sup,
            reason: format!(
                "capability '{}' is not a subtype of '{}' in the Pony lattice",
                sub, sup
            ),
        }
    }
}

/// Returns true if `sub` <: `sup` in the Pony capability subtyping lattice.
///
/// The lattice (from most to least specific):
///   iso -> trn -> ref -> box -> tag
///   iso -> trn -> val -> box -> tag
///   iso -> val (shortcut)
pub fn is_subtype(sub: RefCapability, sup: RefCapability) -> bool {
    use RefCapability::*;
    if sub == sup {
        return true;
    }
    match (sub, sup) {
        // iso is subtype of everything (most specific)
        (Iso, _) => true,
        // trn is subtype of ref, val, box, tag
        (Trn, Ref) | (Trn, Val) | (Trn, Box) | (Trn, Tag) => true,
        // ref is subtype of box, tag
        (Ref, Box) | (Ref, Tag) => true,
        // val is subtype of box, tag
        (Val, Box) | (Val, Tag) => true,
        // box is subtype of tag
        (Box, Tag) => true,
        // tag is subtype of nothing else
        _ => false,
    }
}

/// A field belonging to an actor, annotated with a reference capability.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Field {
    /// Field name (e.g., "connections").
    pub name: String,
    /// Type of the field (e.g., "Array[TCPConnection]").
    pub field_type: String,
    /// Reference capability for this field.
    pub capability: RefCapability,
}

/// An actor definition — the fundamental unit of concurrency in Pony.
///
/// Actors are objects with their own heap and message queue.
/// All fields are private to the actor; external access happens through behaviours.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Actor {
    /// Actor name (e.g., "ConnectionManager").
    pub name: String,
    /// Fields owned by this actor, each with a capability annotation.
    pub fields: Vec<Field>,
    /// Optional docstring describing the actor's purpose.
    #[serde(default)]
    pub doc: Option<String>,
}

/// A parameter to a behaviour, with a required capability.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BehaviourParam {
    /// Parameter name.
    pub name: String,
    /// Parameter type.
    pub param_type: String,
    /// Required reference capability for this parameter.
    pub capability: RefCapability,
}

/// A behaviour definition — an asynchronous message handler on an actor.
///
/// Behaviours are the only way to interact with an actor from outside.
/// They execute asynchronously: the caller sends a message and continues.
/// Parameters must satisfy sendability constraints for cross-actor messaging.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Behaviour {
    /// Name of the actor this behaviour belongs to.
    pub actor: String,
    /// Behaviour name (e.g., "accept_connection").
    pub name: String,
    /// Parameters this behaviour accepts.
    pub params: Vec<BehaviourParam>,
    /// Capabilities required on the receiver side.
    #[serde(default)]
    pub capability_requirements: Vec<RefCapability>,
    /// Optional docstring.
    #[serde(default)]
    pub doc: Option<String>,
}

/// A capability violation detected during analysis.
///
/// These represent potential data races that Pony's capability system
/// would catch at compile time.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityViolation {
    /// Which actor the violation occurs in.
    pub actor: String,
    /// Which behaviour (if applicable) the violation occurs in.
    pub behaviour: Option<String>,
    /// The field or parameter involved.
    pub target: String,
    /// The capability that was expected.
    pub expected: RefCapability,
    /// The capability that was found.
    pub found: RefCapability,
    /// Human-readable description of the violation.
    pub message: String,
}

impl fmt::Display for CapabilityViolation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "[{}] {}: expected '{}', found '{}' — {}",
            self.actor, self.target, self.expected, self.found, self.message
        )
    }
}

/// Validate that all behaviour parameters satisfy sendability requirements.
///
/// In Pony, data sent between actors must use sendable capabilities
/// (iso, val, or tag). This function checks each behaviour's parameters
/// and returns any violations found.
pub fn validate_sendability(
    actors: &[Actor],
    behaviours: &[Behaviour],
) -> Vec<CapabilityViolation> {
    let mut violations = Vec::new();

    for behaviour in behaviours {
        for param in &behaviour.params {
            if !param.capability.is_sendable() {
                violations.push(CapabilityViolation {
                    actor: behaviour.actor.clone(),
                    behaviour: Some(behaviour.name.clone()),
                    target: param.name.clone(),
                    expected: RefCapability::Val, // suggest val as safe default
                    found: param.capability,
                    message: format!(
                        "parameter '{}' of behaviour '{}' has capability '{}' which is not \
                         sendable across actor boundaries; use iso, val, or tag instead",
                        param.name, behaviour.name, param.capability
                    ),
                });
            }
        }
    }

    // Check that actors referenced by behaviours actually exist
    let actor_names: std::collections::HashSet<&str> =
        actors.iter().map(|a| a.name.as_str()).collect();
    for behaviour in behaviours {
        if !actor_names.contains(behaviour.actor.as_str()) {
            violations.push(CapabilityViolation {
                actor: behaviour.actor.clone(),
                behaviour: Some(behaviour.name.clone()),
                target: behaviour.actor.clone(),
                expected: RefCapability::Tag,
                found: RefCapability::Tag,
                message: format!(
                    "behaviour '{}' references actor '{}' which is not defined",
                    behaviour.name, behaviour.actor
                ),
            });
        }
    }

    violations
}

/// Suggest the most permissive sendable capability that satisfies the given needs.
///
/// This is used by the capability inference engine to recommend capabilities
/// for parameters that need to be sent across actor boundaries.
pub fn suggest_sendable_capability(needs_read: bool, needs_write: bool) -> RefCapability {
    match (needs_read, needs_write) {
        (_, true) => RefCapability::Iso,      // unique mutable reference
        (true, false) => RefCapability::Val,  // shared immutable
        (false, false) => RefCapability::Tag, // identity only
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_subtyping_reflexivity() {
        for cap in RefCapability::all() {
            assert!(
                is_subtype(*cap, *cap),
                "{} should be subtype of itself",
                cap
            );
        }
    }

    #[test]
    fn test_iso_is_top() {
        for cap in RefCapability::all() {
            assert!(
                is_subtype(RefCapability::Iso, *cap),
                "iso should be subtype of {}",
                cap
            );
        }
    }

    #[test]
    fn test_tag_is_bottom() {
        for cap in RefCapability::all() {
            assert!(
                is_subtype(*cap, RefCapability::Tag),
                "{} should be subtype of tag",
                cap
            );
        }
    }

    #[test]
    fn test_read_path() {
        // tag ⊆ box ⊆ val
        assert!(is_subtype(RefCapability::Tag, RefCapability::Tag));
        assert!(is_subtype(RefCapability::Box, RefCapability::Tag));
        assert!(is_subtype(RefCapability::Val, RefCapability::Box));
        assert!(is_subtype(RefCapability::Val, RefCapability::Tag));
    }

    #[test]
    fn test_write_path() {
        // tag ⊆ box ⊆ ref
        assert!(is_subtype(RefCapability::Box, RefCapability::Tag));
        assert!(is_subtype(RefCapability::Ref, RefCapability::Box));
        assert!(is_subtype(RefCapability::Ref, RefCapability::Tag));
    }

    #[test]
    fn test_sendability() {
        assert!(RefCapability::Iso.is_sendable());
        assert!(RefCapability::Val.is_sendable());
        assert!(RefCapability::Tag.is_sendable());
        assert!(!RefCapability::Ref.is_sendable());
        assert!(!RefCapability::Box.is_sendable());
        assert!(!RefCapability::Trn.is_sendable());
    }

    #[test]
    fn test_non_subtypes() {
        assert!(!is_subtype(RefCapability::Tag, RefCapability::Iso));
        assert!(!is_subtype(RefCapability::Box, RefCapability::Ref));
        assert!(!is_subtype(RefCapability::Box, RefCapability::Val));
        assert!(!is_subtype(RefCapability::Ref, RefCapability::Val));
        assert!(!is_subtype(RefCapability::Val, RefCapability::Ref));
    }

    #[test]
    fn test_can_read_write() {
        assert!(RefCapability::Iso.can_read());
        assert!(RefCapability::Iso.can_write());
        assert!(RefCapability::Val.can_read());
        assert!(!RefCapability::Val.can_write());
        assert!(RefCapability::Ref.can_read());
        assert!(RefCapability::Ref.can_write());
        assert!(RefCapability::Box.can_read());
        assert!(!RefCapability::Box.can_write());
        assert!(RefCapability::Trn.can_read());
        assert!(RefCapability::Trn.can_write());
        assert!(!RefCapability::Tag.can_read());
        assert!(!RefCapability::Tag.can_write());
    }
}
