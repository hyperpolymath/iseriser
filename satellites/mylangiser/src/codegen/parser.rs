// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser module for mylangiser codegen — extracts structured parameter
// information from endpoint definition strings. Each parameter string
// follows the format "name: type" (required) or "name?: type" (optional).

use crate::manifest::EndpointDef;

/// A parsed parameter with its name, type, and optionality extracted
/// from the "name: type" / "name?: type" manifest format.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedParam {
    /// The parameter name (without trailing '?').
    pub name: String,
    /// The parameter type (e.g., "string", "int", "map", "list").
    pub param_type: ParamType,
    /// Whether this parameter is optional (indicated by '?' in the manifest).
    pub optional: bool,
}

/// Recognised parameter types for complexity scoring purposes.
/// Scalar types are simpler than compound types (map, list).
#[derive(Debug, Clone, PartialEq)]
pub enum ParamType {
    /// Simple string value.
    String,
    /// Integer numeric value.
    Int,
    /// Boolean flag.
    Bool,
    /// Key-value map — considered a complex compound type.
    Map,
    /// Ordered collection — considered a complex compound type.
    List,
    /// Any type not matching the recognised set.
    Unknown(std::string::String),
}

impl ParamType {
    /// Parse a type name string into a `ParamType` variant.
    /// Case-insensitive matching for the canonical types.
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Self {
        match s.trim().to_lowercase().as_str() {
            "string" | "str" => ParamType::String,
            "int" | "integer" | "i32" | "i64" | "u32" | "u64" => ParamType::Int,
            "bool" | "boolean" => ParamType::Bool,
            "map" | "hashmap" | "dict" | "object" => ParamType::Map,
            "list" | "vec" | "array" => ParamType::List,
            other => ParamType::Unknown(other.to_string()),
        }
    }

    /// Returns a complexity weight for this type. Compound types (map, list)
    /// contribute more complexity than scalar types.
    pub fn complexity_weight(&self) -> u32 {
        match self {
            ParamType::String | ParamType::Int | ParamType::Bool => 1,
            ParamType::Map => 3,
            ParamType::List => 2,
            ParamType::Unknown(_) => 2,
        }
    }
}

/// Parse a single parameter string "name: type" or "name?: type" into a
/// `ParsedParam` struct.
///
/// # Examples
/// ```text
/// "username: string"   -> ParsedParam { name: "username", param_type: String, optional: false }
/// "role?: string"      -> ParsedParam { name: "role", param_type: String, optional: true }
/// "filters?: map"      -> ParsedParam { name: "filters", param_type: Map, optional: true }
/// ```
pub fn parse_param(param_str: &str) -> ParsedParam {
    let parts: Vec<&str> = param_str.splitn(2, ':').collect();
    let (name_raw, type_raw) = if parts.len() == 2 {
        (parts[0].trim(), parts[1].trim())
    } else {
        (parts[0].trim(), "string")
    };

    let optional = name_raw.ends_with('?');
    let name = name_raw.trim_end_matches('?').to_string();
    let param_type = ParamType::from_str(type_raw);

    ParsedParam {
        name,
        param_type,
        optional,
    }
}

/// Parse all parameters from an endpoint definition into structured
/// `ParsedParam` values, cross-referencing the `required` list to
/// ensure optionality is correctly determined.
///
/// A parameter is considered optional if:
/// - Its name ends with '?' in the params list, OR
/// - It does NOT appear in the endpoint's `required` list
pub fn parse_endpoint_params(endpoint: &EndpointDef) -> Vec<ParsedParam> {
    endpoint
        .params
        .iter()
        .map(|p| {
            let mut parsed = parse_param(p);
            // If the param is in the required list, force it to non-optional
            // regardless of '?' suffix (required list takes precedence).
            if endpoint.required.contains(&parsed.name) {
                parsed.optional = false;
            }
            // If the param is NOT in required and NOT already marked optional,
            // and there IS a required list, infer optionality.
            if !endpoint.required.is_empty()
                && !endpoint.required.contains(&parsed.name)
                && !parsed.optional
            {
                parsed.optional = true;
            }
            parsed
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_required_param() {
        let p = parse_param("username: string");
        assert_eq!(p.name, "username");
        assert_eq!(p.param_type, ParamType::String);
        assert!(!p.optional);
    }

    #[test]
    fn test_parse_optional_param() {
        let p = parse_param("role?: string");
        assert_eq!(p.name, "role");
        assert!(p.optional);
    }

    #[test]
    fn test_parse_map_type() {
        let p = parse_param("filters?: map");
        assert_eq!(p.param_type, ParamType::Map);
        assert_eq!(p.param_type.complexity_weight(), 3);
    }

    #[test]
    fn test_parse_list_type() {
        let p = parse_param("facets?: list");
        assert_eq!(p.param_type, ParamType::List);
        assert_eq!(p.param_type.complexity_weight(), 2);
    }
}
