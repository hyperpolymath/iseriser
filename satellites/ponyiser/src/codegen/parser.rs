// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser for actor and behaviour definitions from the manifest.
//
// Transforms the TOML manifest representation into the ABI types used
// by the capability analysis and code generation engines. Also validates
// structural constraints that go beyond basic TOML parsing.

use anyhow::{Context, Result};

use crate::abi::{Actor, Behaviour, BehaviourParam, Field};
use crate::manifest::{ActorDef, BehaviourDef, Manifest};

/// A fully parsed and validated set of actor/behaviour definitions
/// ready for capability analysis and code generation.
#[derive(Debug, Clone)]
pub struct ParsedDefinitions {
    /// All parsed actor definitions with ABI types.
    pub actors: Vec<Actor>,
    /// All parsed behaviour definitions with ABI types.
    pub behaviours: Vec<Behaviour>,
    /// Mapping from actor name to its index in the actors vector.
    pub actor_index: std::collections::HashMap<String, usize>,
    /// Mapping from (actor_name, behaviour_name) to behaviour index.
    pub behaviour_index: std::collections::HashMap<(String, String), usize>,
}

/// Parse all actor and behaviour definitions from a manifest.
///
/// This function:
/// 1. Converts manifest types to ABI types
/// 2. Builds lookup indices for efficient cross-referencing
/// 3. Validates structural relationships (e.g., behaviour->actor references)
///
/// Returns a ParsedDefinitions struct ready for analysis.
pub fn parse_definitions(manifest: &Manifest) -> Result<ParsedDefinitions> {
    let mut actors = Vec::with_capacity(manifest.actors.len());
    let mut actor_index = std::collections::HashMap::new();

    // Parse actors and build index.
    for (i, actor_def) in manifest.actors.iter().enumerate() {
        let actor = parse_actor(actor_def)
            .with_context(|| format!("Failed to parse actor '{}'", actor_def.name))?;
        actor_index.insert(actor.name.clone(), i);
        actors.push(actor);
    }

    // Parse behaviours with actor validation.
    let mut behaviours = Vec::with_capacity(manifest.behaviours.len());
    let mut behaviour_index = std::collections::HashMap::new();

    for (i, behaviour_def) in manifest.behaviours.iter().enumerate() {
        // Validate actor reference exists.
        if !actor_index.contains_key(&behaviour_def.actor) {
            anyhow::bail!(
                "behaviour '{}' references undefined actor '{}'",
                behaviour_def.name,
                behaviour_def.actor
            );
        }
        let behaviour = parse_behaviour(behaviour_def)
            .with_context(|| format!("Failed to parse behaviour '{}'", behaviour_def.name))?;
        behaviour_index.insert((behaviour.actor.clone(), behaviour.name.clone()), i);
        behaviours.push(behaviour);
    }

    Ok(ParsedDefinitions {
        actors,
        behaviours,
        actor_index,
        behaviour_index,
    })
}

/// Parse a single actor definition from manifest format to ABI format.
fn parse_actor(def: &ActorDef) -> Result<Actor> {
    let fields: Vec<Field> = def
        .fields
        .iter()
        .map(|f| {
            Ok(Field {
                name: f.name.clone(),
                field_type: f.field_type.clone(),
                capability: f.capability,
            })
        })
        .collect::<Result<Vec<_>>>()?;

    Ok(Actor {
        name: def.name.clone(),
        fields,
        doc: def.doc.clone(),
    })
}

/// Parse a single behaviour definition from manifest format to ABI format.
fn parse_behaviour(def: &BehaviourDef) -> Result<Behaviour> {
    let params: Vec<BehaviourParam> = def
        .params
        .iter()
        .map(|p| {
            Ok(BehaviourParam {
                name: p.name.clone(),
                param_type: p.param_type.clone(),
                capability: p.capability,
            })
        })
        .collect::<Result<Vec<_>>>()?;

    Ok(Behaviour {
        actor: def.actor.clone(),
        name: def.name.clone(),
        params,
        capability_requirements: def.capability_requirements.clone(),
        doc: def.doc.clone(),
    })
}

/// Get all behaviours belonging to a specific actor.
///
/// Useful during code generation to group behaviours under their actor.
pub fn behaviours_for_actor<'a>(
    defs: &'a ParsedDefinitions,
    actor_name: &str,
) -> Vec<&'a Behaviour> {
    defs.behaviours
        .iter()
        .filter(|b| b.actor == actor_name)
        .collect()
}

/// Validate that an actor name follows Pony naming conventions.
///
/// In Pony, type names (including actors) must start with an uppercase letter.
pub fn validate_pony_name(name: &str) -> Result<()> {
    if name.is_empty() {
        anyhow::bail!("name cannot be empty");
    }
    let first = name.chars().next().expect("TODO: handle error");
    if !first.is_ascii_uppercase() {
        anyhow::bail!(
            "Pony actor/type name '{}' must start with an uppercase letter",
            name
        );
    }
    // Check for invalid characters (Pony allows alphanumeric and underscore).
    for ch in name.chars() {
        if !ch.is_ascii_alphanumeric() && ch != '_' {
            anyhow::bail!("Pony name '{}' contains invalid character '{}'", name, ch);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::parse_manifest;

    #[test]
    fn test_parse_definitions_from_manifest() {
        let toml = r#"
[project]
name = "test"

[[actors]]
name = "Server"

[[actors.fields]]
name = "port"
type = "U16"
capability = "val"

[[behaviours]]
actor = "Server"
name = "listen"

[[behaviours.params]]
name = "port"
type = "U16"
capability = "val"
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        let defs = parse_definitions(&manifest).expect("TODO: handle error");
        assert_eq!(defs.actors.len(), 1);
        assert_eq!(defs.behaviours.len(), 1);
        assert!(defs.actor_index.contains_key("Server"));
        assert!(
            defs.behaviour_index
                .contains_key(&("Server".to_string(), "listen".to_string()))
        );
    }

    #[test]
    fn test_behaviours_for_actor() {
        let toml = r#"
[project]
name = "test"

[[actors]]
name = "A"

[[actors]]
name = "B"

[[behaviours]]
actor = "A"
name = "foo"

[[behaviours]]
actor = "A"
name = "bar"

[[behaviours]]
actor = "B"
name = "baz"
"#;
        let manifest = parse_manifest(toml).expect("TODO: handle error");
        let defs = parse_definitions(&manifest).expect("TODO: handle error");
        let a_behaviours = behaviours_for_actor(&defs, "A");
        assert_eq!(a_behaviours.len(), 2);
        let b_behaviours = behaviours_for_actor(&defs, "B");
        assert_eq!(b_behaviours.len(), 1);
    }

    #[test]
    fn test_validate_pony_name() {
        assert!(validate_pony_name("Main").is_ok());
        assert!(validate_pony_name("TCPListener").is_ok());
        assert!(validate_pony_name("My_Actor").is_ok());
        assert!(validate_pony_name("lowercase").is_err());
        assert!(validate_pony_name("").is_err());
        assert!(validate_pony_name("Bad-Name").is_err());
    }
}
