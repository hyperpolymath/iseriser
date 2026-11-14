// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for nimiser.
// Rust-side types representing Nim procedure declarations, types, pragmas,
// templates, compilation targets, and garbage collection strategies.
// These mirror the Idris2 ABI formal definitions and provide runtime types
// for code generation.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Nim compilation backend target.
/// Nim can compile to C, C++, or JavaScript.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum CompilationTarget {
    /// Compile to C (default, best for system libraries).
    #[default]
    C,
    /// Compile to C++ (for C++ interop).
    Cpp,
    /// Compile to JavaScript (for browser/Deno targets).
    Js,
}

impl fmt::Display for CompilationTarget {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CompilationTarget::C => write!(f, "c"),
            CompilationTarget::Cpp => write!(f, "cpp"),
            CompilationTarget::Js => write!(f, "js"),
        }
    }
}

/// Nim garbage collection strategy.
/// ARC and ORC are the modern, deterministic options; None disables GC entirely.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum GcStrategy {
    /// ARC — deterministic reference counting with move semantics.
    #[default]
    Arc,
    /// ORC — ARC + cycle collector for cyclic data structures.
    Orc,
    /// No GC — fully manual memory management.
    None,
}

impl fmt::Display for GcStrategy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GcStrategy::Arc => write!(f, "arc"),
            GcStrategy::Orc => write!(f, "orc"),
            GcStrategy::None => write!(f, "none"),
        }
    }
}

/// Nim pragma applied to a proc or type.
/// Pragmas control ABI, calling convention, packing, and more.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NimPragma {
    /// {.exportc.} — export the symbol with C naming.
    Exportc,
    /// {.exportc: "custom_name".} — export with a specific C symbol name.
    ExportcNamed(String),
    /// {.cdecl.} — use C calling convention.
    Cdecl,
    /// {.stdcall.} — use stdcall calling convention.
    Stdcall,
    /// {.packed.} — pack struct fields without alignment padding.
    Packed,
    /// {.noSideEffect.} — proc has no side effects (pure).
    NoSideEffect,
    /// {.inline.} — hint to inline the proc.
    Inline,
    /// {.raises: [].} — proc raises no exceptions.
    RaisesNone,
    /// {.dynlib.} — load from a dynamic library.
    Dynlib(String),
    /// {.header: "file.h".} — include a C header.
    Header(String),
}

impl fmt::Display for NimPragma {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NimPragma::Exportc => write!(f, "exportc"),
            NimPragma::ExportcNamed(name) => write!(f, "exportc: \"{}\"", name),
            NimPragma::Cdecl => write!(f, "cdecl"),
            NimPragma::Stdcall => write!(f, "stdcall"),
            NimPragma::Packed => write!(f, "packed"),
            NimPragma::NoSideEffect => write!(f, "noSideEffect"),
            NimPragma::Inline => write!(f, "inline"),
            NimPragma::RaisesNone => write!(f, "raises: []"),
            NimPragma::Dynlib(lib) => write!(f, "dynlib: \"{}\"", lib),
            NimPragma::Header(hdr) => write!(f, "header: \"{}\"", hdr),
        }
    }
}

/// Nim type representation.
/// Covers primitive types, pointer types, arrays, sequences, objects, and aliases.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum NimType {
    /// Primitive types: int, int8, int16, int32, int64, uint, uint8, etc.
    /// Also: float, float32, float64, bool, char, string, cstring, pointer, void.
    Primitive(String),
    /// ptr T — untraced pointer to T.
    Ptr(Box<NimType>),
    /// ref T — traced (GC-managed) reference.
    Ref(Box<NimType>),
    /// array[N, T] — fixed-size array.
    Array { size: usize, element: Box<NimType> },
    /// seq[T] — dynamic sequence.
    Seq(Box<NimType>),
    /// object type with named fields.
    Object {
        name: String,
        fields: Vec<NimField>,
        pragmas: Vec<NimPragma>,
    },
    /// A named type alias.
    Alias(String),
}

impl fmt::Display for NimType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NimType::Primitive(name) => write!(f, "{}", name),
            NimType::Ptr(inner) => write!(f, "ptr {}", inner),
            NimType::Ref(inner) => write!(f, "ref {}", inner),
            NimType::Array { size, element } => write!(f, "array[{}, {}]", size, element),
            NimType::Seq(inner) => write!(f, "seq[{}]", inner),
            NimType::Object { name, .. } => write!(f, "{}", name),
            NimType::Alias(name) => write!(f, "{}", name),
        }
    }
}

/// A field within a Nim object type.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NimField {
    /// Field name.
    pub name: String,
    /// Field type.
    pub nim_type: NimType,
}

/// A parameter in a Nim proc.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NimParam {
    /// Parameter name.
    pub name: String,
    /// Parameter type.
    pub nim_type: NimType,
}

/// A Nim procedure declaration.
/// Represents a fully-qualified proc with name, parameters, return type, and pragmas.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NimProc {
    /// Procedure name.
    pub name: String,
    /// Procedure parameters.
    pub params: Vec<NimParam>,
    /// Return type (None means void/no return).
    pub return_type: Option<NimType>,
    /// Pragmas applied to this proc.
    pub pragmas: Vec<NimPragma>,
    /// Optional doc comment.
    pub doc: Option<String>,
}

impl NimProc {
    /// Format the pragma list as a Nim pragma annotation string.
    /// Returns empty string if no pragmas, otherwise "{.pragma1, pragma2.}".
    pub fn pragma_string(&self) -> String {
        if self.pragmas.is_empty() {
            return String::new();
        }
        let pragma_parts: Vec<String> = self.pragmas.iter().map(|p| p.to_string()).collect();
        format!(" {{.{}.}}", pragma_parts.join(", "))
    }

    /// Render this proc as a Nim proc declaration (signature only, no body).
    pub fn render_signature(&self) -> String {
        let params_str = if self.params.is_empty() {
            String::new()
        } else {
            let parts: Vec<String> = self
                .params
                .iter()
                .map(|p| format!("{}: {}", p.name, p.nim_type))
                .collect();
            format!("({})", parts.join(", "))
        };

        let ret_str = match &self.return_type {
            Some(t) => format!(": {}", t),
            None => String::new(),
        };

        let pragmas = self.pragma_string();

        format!("proc {}{}{}{}", self.name, params_str, ret_str, pragmas)
    }
}

/// A Nim template declaration.
/// Templates are compile-time code substitution mechanisms — zero overhead at runtime.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NimTemplate {
    /// Template name.
    pub name: String,
    /// Template parameters.
    pub params: Vec<NimParam>,
    /// Return type (None means untyped).
    pub return_type: Option<NimType>,
    /// Template body (Nim code).
    pub body: String,
    /// Optional doc comment.
    pub doc: Option<String>,
}

impl NimTemplate {
    /// Render this template as a full Nim template declaration with body.
    pub fn render(&self) -> String {
        let params_str = if self.params.is_empty() {
            String::new()
        } else {
            let parts: Vec<String> = self
                .params
                .iter()
                .map(|p| format!("{}: {}", p.name, p.nim_type))
                .collect();
            format!("({})", parts.join(", "))
        };

        let ret_str = match &self.return_type {
            Some(t) => format!(": {}", t),
            None => String::new(),
        };

        let mut lines = Vec::new();
        if let Some(ref doc) = self.doc {
            lines.push(format!("  ## {}", doc));
        }
        lines.push(format!("  {}", self.body));

        format!(
            "template {}{}{} =\n{}",
            self.name,
            params_str,
            ret_str,
            lines.join("\n")
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compilation_target_display() {
        assert_eq!(CompilationTarget::C.to_string(), "c");
        assert_eq!(CompilationTarget::Cpp.to_string(), "cpp");
        assert_eq!(CompilationTarget::Js.to_string(), "js");
    }

    #[test]
    fn test_gc_strategy_display() {
        assert_eq!(GcStrategy::Arc.to_string(), "arc");
        assert_eq!(GcStrategy::Orc.to_string(), "orc");
        assert_eq!(GcStrategy::None.to_string(), "none");
    }

    #[test]
    fn test_pragma_display() {
        assert_eq!(NimPragma::Exportc.to_string(), "exportc");
        assert_eq!(NimPragma::Cdecl.to_string(), "cdecl");
        assert_eq!(
            NimPragma::ExportcNamed("myFunc".into()).to_string(),
            "exportc: \"myFunc\""
        );
    }

    #[test]
    fn test_nim_type_display() {
        assert_eq!(NimType::Primitive("int32".into()).to_string(), "int32");
        assert_eq!(
            NimType::Ptr(Box::new(NimType::Primitive("float".into()))).to_string(),
            "ptr float"
        );
        assert_eq!(
            NimType::Array {
                size: 16,
                element: Box::new(NimType::Primitive("uint8".into()))
            }
            .to_string(),
            "array[16, uint8]"
        );
    }

    #[test]
    fn test_nim_proc_render_signature() {
        let proc = NimProc {
            name: "add".into(),
            params: vec![
                NimParam {
                    name: "a".into(),
                    nim_type: NimType::Primitive("cint".into()),
                },
                NimParam {
                    name: "b".into(),
                    nim_type: NimType::Primitive("cint".into()),
                },
            ],
            return_type: Some(NimType::Primitive("cint".into())),
            pragmas: vec![NimPragma::Exportc, NimPragma::Cdecl],
            doc: None,
        };
        assert_eq!(
            proc.render_signature(),
            "proc add(a: cint, b: cint): cint {.exportc, cdecl.}"
        );
    }

    #[test]
    fn test_nim_proc_no_params_no_return() {
        let proc = NimProc {
            name: "init".into(),
            params: vec![],
            return_type: None,
            pragmas: vec![NimPragma::Exportc],
            doc: None,
        };
        assert_eq!(proc.render_signature(), "proc init {.exportc.}");
    }

    #[test]
    fn test_nim_template_render() {
        let tmpl = NimTemplate {
            name: "withLock".into(),
            params: vec![NimParam {
                name: "body".into(),
                nim_type: NimType::Primitive("untyped".into()),
            }],
            return_type: None,
            body: "acquire(); body; release()".into(),
            doc: Some("Execute body while holding the lock.".into()),
        };
        let rendered = tmpl.render();
        assert!(rendered.contains("template withLock(body: untyped) ="));
        assert!(rendered.contains("## Execute body while holding the lock."));
        assert!(rendered.contains("acquire(); body; release()"));
    }
}
