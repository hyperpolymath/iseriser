// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser: transforms manifest FunctionSpec entries into ABI-level
// DafnyFunction / DafnyModule structures suitable for code generation.

use anyhow::Result;

use crate::abi::{
    DafnyFunction, DafnyModule, DafnyParam, DafnyReturn, DecreasesClause, Postcondition,
    Precondition, TargetLanguage,
};
use crate::manifest::{FunctionSpec, Manifest};

/// Parse all function specs from a manifest into a single DafnyModule.
///
/// The module name is derived from the project name (sanitised to a valid
/// Dafny identifier). Each `[[functions]]` entry becomes a DafnyFunction
/// with fully resolved preconditions, postconditions, and decreases clauses.
/// Helper predicates are auto-detected from requires/ensures expressions.
pub fn parse_manifest(manifest: &Manifest) -> Result<DafnyModule> {
    let module_name = sanitise_identifier(&manifest.project.name);
    let mut functions = Vec::with_capacity(manifest.functions.len());
    let mut helper_predicates: Vec<String> = Vec::new();

    for spec in &manifest.functions {
        let func = parse_function(spec)?;
        // Detect helper predicates referenced in contracts.
        detect_helpers(&func, &mut helper_predicates);
        functions.push(func);
    }

    Ok(DafnyModule {
        name: module_name,
        functions,
        helper_predicates,
    })
}

/// Parse a single FunctionSpec into a DafnyFunction.
///
/// Merges per-parameter `requires` with function-level `requires`, and
/// per-return `ensures` with function-level `ensures`.
pub fn parse_function(spec: &FunctionSpec) -> Result<DafnyFunction> {
    // Build typed parameters.
    let params: Vec<DafnyParam> = spec
        .params
        .iter()
        .map(|p| DafnyParam {
            name: p.name.clone(),
            dafny_type: p.param_type.clone(),
            requires: p.requires.iter().cloned().collect(),
        })
        .collect();

    // Collect all preconditions: per-parameter requires + function-level requires.
    let mut preconditions: Vec<Precondition> = Vec::new();
    for param in &spec.params {
        if let Some(req) = &param.requires {
            preconditions.push(Precondition {
                expression: req.clone(),
                description: Some(format!("parameter '{}' precondition", param.name)),
            });
        }
    }
    for req in &spec.requires {
        preconditions.push(Precondition {
            expression: req.clone(),
            description: None,
        });
    }

    // Collect all postconditions: per-return ensures + function-level ensures.
    let mut postconditions: Vec<Postcondition> = Vec::new();
    if let Some(ens) = &spec.returns.ensures {
        postconditions.push(Postcondition {
            expression: ens.clone(),
            description: Some("return postcondition".to_string()),
        });
    }
    for ens in &spec.ensures {
        postconditions.push(Postcondition {
            expression: ens.clone(),
            description: None,
        });
    }

    // Parse decreases clause.
    let decreases = spec.decreases.as_ref().map(|expr| DecreasesClause {
        expression: expr.clone(),
    });

    // Build return specification.
    let returns = DafnyReturn {
        dafny_type: spec.returns.return_type.clone(),
        ensures: postconditions
            .iter()
            .map(|p| p.expression.clone())
            .collect(),
    };

    Ok(DafnyFunction {
        name: spec.name.clone(),
        params,
        returns,
        preconditions,
        postconditions,
        decreases,
        loop_invariants: Vec::new(),
        is_function: spec.is_function,
    })
}

/// Parse a target language string into a TargetLanguage enum.
pub fn parse_target(target_str: &str) -> Result<TargetLanguage> {
    match target_str {
        "csharp" | "cs" => Ok(TargetLanguage::CSharp),
        "java" => Ok(TargetLanguage::Java),
        "go" => Ok(TargetLanguage::Go),
        "python" | "py" => Ok(TargetLanguage::Python),
        "js" | "javascript" => Ok(TargetLanguage::Js),
        other => anyhow::bail!("unknown target language: '{}'", other),
    }
}

/// Sanitise a project name into a valid Dafny identifier.
///
/// Replaces hyphens and spaces with underscores, strips non-alphanumeric
/// characters, and capitalises the first letter.
fn sanitise_identifier(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let trimmed = cleaned.trim_matches('_').to_string();
    if trimmed.is_empty() {
        return "Module".to_string();
    }
    // Capitalise first character for Dafny module naming convention.
    let mut chars = trimmed.chars();
    match chars.next() {
        None => "Module".to_string(),
        Some(first) => {
            let upper: String = first.to_uppercase().collect();
            format!("{}{}", upper, chars.collect::<String>())
        }
    }
}

/// Detect helper predicates referenced in function contracts.
///
/// Scans requires/ensures expressions for function-call patterns like
/// `sorted(...)`, `multiset(...)`, etc. and adds them to the helpers list
/// if not already present.
fn detect_helpers(func: &DafnyFunction, helpers: &mut Vec<String>) {
    let all_expressions: Vec<&str> = func
        .preconditions
        .iter()
        .map(|p| p.expression.as_str())
        .chain(func.postconditions.iter().map(|p| p.expression.as_str()))
        .collect();

    for expr in all_expressions {
        // Simple heuristic: find identifiers followed by '('.
        // This catches sorted(...), multiset(...), etc.
        let mut i = 0;
        let bytes = expr.as_bytes();
        while i < bytes.len() {
            // Find start of an identifier.
            if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
                let start = i;
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
                let ident = &expr[start..i];
                // Check if followed by '(' — indicates a predicate/function call.
                if i < bytes.len() && bytes[i] == b'(' {
                    // Skip built-in Dafny keywords and common operators.
                    let builtins = [
                        "result", "old", "fresh", "forall", "exists", "var", "if", "then", "else",
                        "true", "false", "null", "this", "seq", "set", "map", "multiset", "array",
                        "int", "nat", "real", "bool", "string",
                    ];
                    if !builtins.contains(&ident) && !helpers.contains(&ident.to_string()) {
                        helpers.push(ident.to_string());
                    }
                }
            } else {
                i += 1;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::*;

    fn sample_spec() -> FunctionSpec {
        FunctionSpec {
            name: "binary_search".to_string(),
            params: vec![
                ParamSpec {
                    name: "arr".to_string(),
                    param_type: "seq<int>".to_string(),
                    requires: Some("sorted(arr)".to_string()),
                },
                ParamSpec {
                    name: "key".to_string(),
                    param_type: "int".to_string(),
                    requires: None,
                },
            ],
            returns: ReturnSpec {
                return_type: "int".to_string(),
                ensures: Some("result >= 0 ==> arr[result] == key".to_string()),
            },
            decreases: Some("arr.Length".to_string()),
            requires: vec![],
            ensures: vec![],
            is_function: false,
        }
    }

    #[test]
    fn test_parse_function_preconditions() {
        let spec = sample_spec();
        let func = parse_function(&spec).expect("TODO: handle error");
        assert_eq!(func.preconditions.len(), 1);
        assert_eq!(func.preconditions[0].expression, "sorted(arr)");
    }

    #[test]
    fn test_parse_function_postconditions() {
        let spec = sample_spec();
        let func = parse_function(&spec).expect("TODO: handle error");
        assert_eq!(func.postconditions.len(), 1);
        assert!(
            func.postconditions[0]
                .expression
                .contains("arr[result] == key")
        );
    }

    #[test]
    fn test_parse_function_decreases() {
        let spec = sample_spec();
        let func = parse_function(&spec).expect("TODO: handle error");
        assert!(func.decreases.is_some());
        assert_eq!(
            func.decreases.expect("TODO: handle error").expression,
            "arr.Length"
        );
    }

    #[test]
    fn test_parse_target_all_valid() {
        assert_eq!(
            parse_target("csharp").expect("TODO: handle error"),
            TargetLanguage::CSharp
        );
        assert_eq!(
            parse_target("cs").expect("TODO: handle error"),
            TargetLanguage::CSharp
        );
        assert_eq!(
            parse_target("java").expect("TODO: handle error"),
            TargetLanguage::Java
        );
        assert_eq!(
            parse_target("go").expect("TODO: handle error"),
            TargetLanguage::Go
        );
        assert_eq!(
            parse_target("python").expect("TODO: handle error"),
            TargetLanguage::Python
        );
        assert_eq!(
            parse_target("py").expect("TODO: handle error"),
            TargetLanguage::Python
        );
        assert_eq!(
            parse_target("js").expect("TODO: handle error"),
            TargetLanguage::Js
        );
        assert_eq!(
            parse_target("javascript").expect("TODO: handle error"),
            TargetLanguage::Js
        );
    }

    #[test]
    fn test_parse_target_invalid() {
        assert!(parse_target("ruby").is_err());
        assert!(parse_target("").is_err());
    }

    #[test]
    fn test_sanitise_identifier() {
        assert_eq!(sanitise_identifier("verified-sort"), "Verified_sort");
        assert_eq!(sanitise_identifier("my project"), "My_project");
        assert_eq!(sanitise_identifier("---"), "Module");
    }

    #[test]
    fn test_detect_sorted_helper() {
        let spec = sample_spec();
        let func = parse_function(&spec).expect("TODO: handle error");
        let mut helpers = Vec::new();
        detect_helpers(&func, &mut helpers);
        assert!(helpers.contains(&"sorted".to_string()));
    }

    #[test]
    fn test_binary_search_spec() {
        let spec = sample_spec();
        let func = parse_function(&spec).expect("TODO: handle error");
        assert_eq!(func.name, "binary_search");
        assert_eq!(func.params.len(), 2);
        assert_eq!(func.params[0].dafny_type, "seq<int>");
        assert_eq!(func.params[1].dafny_type, "int");
        assert_eq!(func.returns.dafny_type, "int");
        assert!(!func.is_function);
    }
}
