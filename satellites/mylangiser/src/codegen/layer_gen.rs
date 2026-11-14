// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Layer generator for mylangiser — produces beginner/intermediate/expert
// wrapper layers from scored API endpoints. Each layer progressively
// discloses more parameters:
//
// - Beginner:      Only required params; all optional params get smart defaults
// - Intermediate:  Required + commonly-used optional params
// - Expert:        All params exposed, no defaults applied

use std::collections::HashMap;

use crate::abi::{DisclosureLevel, LayeredWrapper, SmartDefault};
use crate::codegen::parser::{ParsedParam, parse_endpoint_params};
use crate::manifest::{EndpointDef, Manifest};

/// Generate the full set of layered wrappers for all endpoints in the manifest.
/// Each endpoint gets up to three wrapper signatures (beginner, intermediate, expert).
pub fn generate_layers(manifest: &Manifest) -> Vec<LayeredWrapper> {
    manifest
        .endpoints
        .iter()
        .map(|ep| generate_endpoint_layers(ep, &manifest.defaults))
        .collect()
}

/// Generate a `LayeredWrapper` for a single endpoint, producing wrapper
/// function signatures for beginner, intermediate, and expert levels.
///
/// Smart defaults are resolved from the manifest's `[defaults]` table:
/// if a default value is defined for an optional parameter, that value
/// is used when the parameter is omitted at lower disclosure levels.
fn generate_endpoint_layers(
    endpoint: &EndpointDef,
    defaults: &HashMap<String, toml::Value>,
) -> LayeredWrapper {
    let params = parse_endpoint_params(endpoint);
    let smart_defaults = resolve_smart_defaults(&params, defaults);

    // Beginner layer: required params only.
    let beginner_params: Vec<String> = params
        .iter()
        .filter(|p| !p.optional)
        .map(format_param)
        .collect();

    // Intermediate layer: required + optional params that have a known default
    // or whose type is scalar (string/int/bool). Complex types (map/list) are
    // deferred to expert level.
    let intermediate_params: Vec<String> = params
        .iter()
        .filter(|p| !p.optional || defaults.contains_key(&p.name) || is_commonly_used_type(p))
        .map(format_param)
        .collect();

    // Expert layer: all params.
    let expert_params: Vec<String> = params.iter().map(format_param).collect();

    // Generate the wrapper code strings for each level.
    let beginner_code = generate_wrapper_code(
        &endpoint.name,
        &beginner_params,
        &smart_defaults,
        DisclosureLevel::Beginner,
    );
    let intermediate_code = generate_wrapper_code(
        &endpoint.name,
        &intermediate_params,
        &smart_defaults,
        DisclosureLevel::Intermediate,
    );
    let expert_code = generate_wrapper_code(
        &endpoint.name,
        &expert_params,
        &smart_defaults,
        DisclosureLevel::Expert,
    );

    LayeredWrapper {
        endpoint_name: endpoint.name.clone(),
        beginner_signature: beginner_params,
        intermediate_signature: intermediate_params,
        expert_signature: expert_params,
        smart_defaults,
        beginner_code,
        intermediate_code,
        expert_code,
    }
}

/// Resolve smart defaults for all optional parameters from the manifest
/// defaults table. Returns a SmartDefault for each optional param that
/// has a matching entry in the `[defaults]` section.
fn resolve_smart_defaults(
    params: &[ParsedParam],
    defaults: &HashMap<String, toml::Value>,
) -> Vec<SmartDefault> {
    params
        .iter()
        .filter(|p| p.optional)
        .filter_map(|p| {
            defaults.get(&p.name).map(|val| SmartDefault {
                param_name: p.name.clone(),
                default_value: toml_value_to_string(val),
            })
        })
        .collect()
}

/// Format a parsed parameter into a "name: type" display string.
/// Optional params get a '?' suffix on the name.
fn format_param(param: &ParsedParam) -> String {
    let suffix = if param.optional { "?" } else { "" };
    format!("{}{}: {:?}", param.name, suffix, param.param_type)
}

/// Determine if a parameter type is "commonly used" — scalar types that
/// most developers would want to see at the intermediate level even if
/// they're optional.
fn is_commonly_used_type(param: &ParsedParam) -> bool {
    use crate::codegen::parser::ParamType;
    matches!(
        param.param_type,
        ParamType::String | ParamType::Int | ParamType::Bool
    )
}

/// Convert a TOML value to a human-readable default string.
fn toml_value_to_string(val: &toml::Value) -> String {
    match val {
        toml::Value::String(s) => format!("\"{}\"", s),
        toml::Value::Integer(i) => i.to_string(),
        toml::Value::Boolean(b) => b.to_string(),
        toml::Value::Float(f) => f.to_string(),
        other => format!("{}", other),
    }
}

/// Generate wrapper function code for a specific disclosure level.
/// The generated code is a pseudo-code/My-Lang representation showing
/// the function signature, defaults application, and delegation to the
/// underlying API.
fn generate_wrapper_code(
    name: &str,
    params: &[String],
    smart_defaults: &[SmartDefault],
    level: DisclosureLevel,
) -> String {
    let level_prefix = match level {
        DisclosureLevel::Beginner => "beginner",
        DisclosureLevel::Intermediate => "intermediate",
        DisclosureLevel::Expert => "expert",
    };

    let mut lines = Vec::new();
    lines.push(format!("/// {}-level wrapper for `{}`", level_prefix, name));
    lines.push(format!(
        "fn {}_{}({}) {{",
        level_prefix,
        name,
        params.join(", ")
    ));

    // At non-expert levels, apply smart defaults for omitted params.
    if level != DisclosureLevel::Expert {
        for sd in smart_defaults {
            // Only include defaults for params NOT in the current signature.
            let param_present = params.iter().any(|p| p.starts_with(&sd.param_name));
            if !param_present {
                lines.push(format!(
                    "    let {} = {};  // smart default",
                    sd.param_name, sd.default_value
                ));
            }
        }
    }

    lines.push(format!("    {}(/* delegate to full API */)", name));
    lines.push("}".to_string());
    lines.join("\n")
}

/// Retrieve the beginner-layer wrapper for a specific endpoint by name.
/// Useful for rendering single-endpoint documentation or code snippets.
pub fn get_beginner_wrapper(manifest: &Manifest, endpoint_name: &str) -> Option<LayeredWrapper> {
    manifest
        .endpoints
        .iter()
        .find(|ep| ep.name == endpoint_name)
        .map(|ep| generate_endpoint_layers(ep, &manifest.defaults))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{EndpointDef, LevelConfig, Manifest, ProjectConfig};

    fn test_manifest() -> Manifest {
        let mut defaults = HashMap::new();
        defaults.insert("role".to_string(), toml::Value::String("user".to_string()));
        defaults.insert("limit".to_string(), toml::Value::Integer(20));
        defaults.insert("page".to_string(), toml::Value::Integer(1));
        defaults.insert(
            "locale".to_string(),
            toml::Value::String("en-GB".to_string()),
        );

        Manifest {
            project: ProjectConfig {
                name: "test-api".to_string(),
                description: String::new(),
            },
            endpoints: vec![
                EndpointDef {
                    name: "create_user".to_string(),
                    params: vec![
                        "username: string".to_string(),
                        "email: string".to_string(),
                        "role?: string".to_string(),
                        "permissions?: list".to_string(),
                        "mfa?: bool".to_string(),
                        "locale?: string".to_string(),
                    ],
                    required: vec!["username".to_string(), "email".to_string()],
                    description: String::new(),
                },
                EndpointDef {
                    name: "search".to_string(),
                    params: vec![
                        "query: string".to_string(),
                        "filters?: map".to_string(),
                        "sort?: string".to_string(),
                        "page?: int".to_string(),
                        "limit?: int".to_string(),
                        "cursor?: string".to_string(),
                        "facets?: list".to_string(),
                    ],
                    required: vec!["query".to_string()],
                    description: String::new(),
                },
            ],
            levels: LevelConfig::default(),
            defaults,
        }
    }

    #[test]
    fn test_beginner_layer_only_required_params() {
        let m = test_manifest();
        let layers = generate_layers(&m);
        let create_user = &layers[0];
        // Beginner layer should only have required params (username, email).
        assert_eq!(
            create_user.beginner_signature.len(),
            2,
            "beginner should only expose required params"
        );
    }

    #[test]
    fn test_expert_layer_all_params() {
        let m = test_manifest();
        let layers = generate_layers(&m);
        let create_user = &layers[0];
        // Expert layer should have all 6 params.
        assert_eq!(
            create_user.expert_signature.len(),
            6,
            "expert should expose all params"
        );
    }

    #[test]
    fn test_smart_defaults_resolved() {
        let m = test_manifest();
        let layers = generate_layers(&m);
        let create_user = &layers[0];
        // Should have smart defaults for 'role' and 'locale' (matching
        // optional params that have entries in [defaults]).
        let default_names: Vec<&str> = create_user
            .smart_defaults
            .iter()
            .map(|sd| sd.param_name.as_str())
            .collect();
        assert!(
            default_names.contains(&"role"),
            "should have default for 'role'"
        );
        assert!(
            default_names.contains(&"locale"),
            "should have default for 'locale'"
        );
    }

    #[test]
    fn test_beginner_code_includes_defaults() {
        let m = test_manifest();
        let layers = generate_layers(&m);
        let create_user = &layers[0];
        // Beginner code should contain smart default assignments for
        // params not in the beginner signature.
        assert!(
            create_user.beginner_code.contains("smart default"),
            "beginner code should apply smart defaults"
        );
    }

    #[test]
    fn test_intermediate_has_more_params_than_beginner() {
        let m = test_manifest();
        let layers = generate_layers(&m);
        let search = &layers[1];
        assert!(
            search.intermediate_signature.len() > search.beginner_signature.len(),
            "intermediate should expose more params than beginner"
        );
    }
}
