// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Function signature parser for nimiser.
// Converts manifest FunctionConfig declarations into typed ABI NimProc
// structures that the Nim code generator can render.

use anyhow::{Context, Result};

use crate::abi::{NimParam, NimPragma, NimProc, NimType};
use crate::manifest::{FunctionConfig, Manifest};

/// Parse all function declarations from a manifest into NimProc ABI types.
pub fn parse_functions(manifest: &Manifest) -> Result<Vec<NimProc>> {
    manifest.functions.iter().map(parse_function).collect()
}

/// Parse a single FunctionConfig into a NimProc.
fn parse_function(func: &FunctionConfig) -> Result<NimProc> {
    let params: Vec<NimParam> = func
        .params
        .iter()
        .map(|p| NimParam {
            name: p.name.clone(),
            nim_type: parse_type(&p.param_type),
        })
        .collect();

    let return_type = if func.return_type.is_empty() {
        None
    } else {
        Some(parse_type(&func.return_type))
    };

    let pragmas: Vec<NimPragma> = func
        .pragmas
        .iter()
        .map(|p| parse_pragma(p))
        .collect::<Result<Vec<_>>>()
        .with_context(|| format!("Failed to parse pragmas for function '{}'", func.name))?;

    let doc = if func.doc.is_empty() {
        None
    } else {
        Some(func.doc.clone())
    };

    Ok(NimProc {
        name: func.name.clone(),
        params,
        return_type,
        pragmas,
        doc,
    })
}

/// Parse a type string into a NimType.
/// Handles "ptr T", "ref T", "seq[T]", "array[N, T]", and bare type names.
pub fn parse_type(type_str: &str) -> NimType {
    let trimmed = type_str.trim();

    // Handle pointer types: "ptr T"
    if let Some(inner) = trimmed.strip_prefix("ptr ") {
        return NimType::Ptr(Box::new(parse_type(inner)));
    }

    // Handle reference types: "ref T"
    if let Some(inner) = trimmed.strip_prefix("ref ") {
        return NimType::Ref(Box::new(parse_type(inner)));
    }

    // Handle sequence types: "seq[T]"
    if trimmed.starts_with("seq[") && trimmed.ends_with(']') {
        let inner = &trimmed[4..trimmed.len() - 1];
        return NimType::Seq(Box::new(parse_type(inner)));
    }

    // Handle fixed array types: "array[N, T]"
    if trimmed.starts_with("array[") && trimmed.ends_with(']') {
        let inner = &trimmed[6..trimmed.len() - 1];
        if let Some(comma_pos) = inner.find(',') {
            let size_str = inner[..comma_pos].trim();
            let elem_str = inner[comma_pos + 1..].trim();
            if let Ok(size) = size_str.parse::<usize>() {
                return NimType::Array {
                    size,
                    element: Box::new(parse_type(elem_str)),
                };
            }
        }
    }

    // Everything else is a primitive or alias type name.
    NimType::Primitive(trimmed.to_string())
}

/// Parse a pragma string into a NimPragma enum variant.
fn parse_pragma(pragma_str: &str) -> Result<NimPragma> {
    match pragma_str.trim() {
        "exportc" => Ok(NimPragma::Exportc),
        "cdecl" => Ok(NimPragma::Cdecl),
        "stdcall" => Ok(NimPragma::Stdcall),
        "packed" => Ok(NimPragma::Packed),
        "noSideEffect" => Ok(NimPragma::NoSideEffect),
        "inline" => Ok(NimPragma::Inline),
        "raises_none" => Ok(NimPragma::RaisesNone),
        other => anyhow::bail!("Unknown pragma: '{}'", other),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::ParamConfig;

    #[test]
    fn test_parse_type_primitive() {
        assert_eq!(parse_type("cint"), NimType::Primitive("cint".into()));
        assert_eq!(parse_type("cfloat"), NimType::Primitive("cfloat".into()));
    }

    #[test]
    fn test_parse_type_ptr() {
        assert_eq!(
            parse_type("ptr cint"),
            NimType::Ptr(Box::new(NimType::Primitive("cint".into())))
        );
    }

    #[test]
    fn test_parse_type_ref() {
        assert_eq!(
            parse_type("ref string"),
            NimType::Ref(Box::new(NimType::Primitive("string".into())))
        );
    }

    #[test]
    fn test_parse_type_seq() {
        assert_eq!(
            parse_type("seq[float]"),
            NimType::Seq(Box::new(NimType::Primitive("float".into())))
        );
    }

    #[test]
    fn test_parse_type_array() {
        assert_eq!(
            parse_type("array[16, uint8]"),
            NimType::Array {
                size: 16,
                element: Box::new(NimType::Primitive("uint8".into()))
            }
        );
    }

    #[test]
    fn test_parse_function_basic() {
        let func = FunctionConfig {
            name: "greet".into(),
            params: vec![ParamConfig {
                name: "name".into(),
                param_type: "cstring".into(),
            }],
            return_type: "cstring".into(),
            pragmas: vec!["exportc".into(), "cdecl".into()],
            doc: "Say hello.".into(),
        };
        let proc = parse_function(&func).expect("TODO: handle error");
        assert_eq!(proc.name, "greet");
        assert_eq!(proc.params.len(), 1);
        assert_eq!(proc.return_type, Some(NimType::Primitive("cstring".into())));
        assert_eq!(proc.pragmas.len(), 2);
        assert_eq!(proc.doc, Some("Say hello.".into()));
    }

    #[test]
    fn test_parse_function_void_return() {
        let func = FunctionConfig {
            name: "init".into(),
            params: vec![],
            return_type: String::new(),
            pragmas: vec!["exportc".into()],
            doc: String::new(),
        };
        let proc = parse_function(&func).expect("TODO: handle error");
        assert!(proc.return_type.is_none());
        assert!(proc.doc.is_none());
    }

    #[test]
    fn test_parse_pragma_unknown() {
        assert!(parse_pragma("nonexistent").is_err());
    }
}
