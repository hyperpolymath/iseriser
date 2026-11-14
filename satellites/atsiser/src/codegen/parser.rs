// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// C header parser for atsiser.
//
// Parses C header files to extract function signatures, identifying:
// - Function names, return types, and parameter types
// - Allocation patterns (functions returning pointers)
// - Deallocation patterns (functions taking pointer params and returning void)
// - Pointer parameter patterns (borrow vs. ownership transfer)
//
// This is a lightweight regex-based parser sufficient for typical C APIs.
// It does not handle the full C grammar (no preprocessor expansion, no complex
// macros). For complex headers, users should pre-process with `cpp` first.

use anyhow::{Context, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

/// A parsed C function signature extracted from a header file.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CFunctionSignature {
    /// The function name (e.g., "malloc", "fopen").
    pub name: String,

    /// The return type as a string (e.g., "void*", "FILE*", "int").
    pub return_type: String,

    /// The parameter list, each as (type, name) pairs.
    pub params: Vec<CParam>,

    /// Whether this function likely allocates memory (returns a pointer).
    pub likely_alloc: bool,

    /// Whether this function likely frees memory (void return, takes pointer).
    pub likely_free: bool,
}

/// A parsed C function parameter.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CParam {
    /// The C type of the parameter (e.g., "const char*", "size_t").
    pub c_type: String,

    /// The parameter name (may be empty for unnamed params in declarations).
    pub name: String,

    /// Whether this parameter is a pointer type.
    pub is_pointer: bool,

    /// Whether this parameter is const-qualified.
    pub is_const: bool,
}

/// Regex for matching C function declarations.
///
/// Matches patterns like:
///   void* malloc(size_t size);
///   int fclose(FILE* stream);
///   extern char* strdup(const char* s);
static FUNC_DECL_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?m)^\s*(?:extern\s+)?(?:static\s+)?(?:inline\s+)?([\w\s\*]+?)\s+(\w+)\s*\(([^)]*)\)\s*;",
    )
    .expect("Failed to compile function declaration regex")
});

/// Regex for matching individual parameters within a parameter list.
static PARAM_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"((?:const\s+)?[\w]+(?:\s*\*+)?)\s*(\w*)")
        .expect("Failed to compile parameter regex")
});

/// Parse a C header file and extract function signatures.
///
/// Reads the file at `path`, strips comments, and extracts all function
/// declarations. Each signature is annotated with heuristic flags indicating
/// whether the function likely allocates or frees memory.
///
/// # Arguments
///
/// * `path` — Path to a C header file (`.h`)
///
/// # Returns
///
/// A vector of parsed function signatures.
///
/// # Errors
///
/// Returns an error if the file cannot be read.
pub fn parse_c_header(path: &str) -> Result<Vec<CFunctionSignature>> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read C header: {}", path))?;
    parse_c_source(&content)
}

/// Parse C source text (already loaded) and extract function signatures.
///
/// This is the core parsing function, separated from file I/O for testability.
///
/// # Arguments
///
/// * `source` — The C header text to parse.
///
/// # Returns
///
/// A vector of parsed function signatures with heuristic ownership flags.
pub fn parse_c_source(source: &str) -> Result<Vec<CFunctionSignature>> {
    let cleaned = strip_comments(source);
    let mut signatures = Vec::new();

    for cap in FUNC_DECL_RE.captures_iter(&cleaned) {
        let return_type = cap[1].trim().to_string();
        let name = cap[2].to_string();
        let params_str = cap[3].trim();

        let params = parse_params(params_str);

        // Heuristic: function returns a pointer -> likely allocator
        let likely_alloc = return_type.contains('*');

        // Heuristic: void return + takes pointer param -> likely deallocator
        let likely_free =
            return_type.trim() == "void" && params.iter().any(|p| p.is_pointer && !p.is_const);

        signatures.push(CFunctionSignature {
            name,
            return_type,
            params,
            likely_alloc,
            likely_free,
        });
    }

    Ok(signatures)
}

/// Parse a comma-separated parameter list string into CParam entries.
///
/// Handles void parameters, unnamed parameters, and const qualifiers.
fn parse_params(params_str: &str) -> Vec<CParam> {
    let trimmed = params_str.trim();
    if trimmed.is_empty() || trimmed == "void" {
        return Vec::new();
    }

    let mut params = Vec::new();
    for part in trimmed.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }

        if let Some(cap) = PARAM_RE.captures(part) {
            let c_type = cap[1].trim().to_string();
            let name = cap
                .get(2)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            let is_pointer = c_type.contains('*');
            let is_const = c_type.starts_with("const");

            params.push(CParam {
                c_type,
                name,
                is_pointer,
                is_const,
            });
        }
    }

    params
}

/// Strip C-style comments (/* ... */ and // ...) from source text.
///
/// This is a simple state-machine approach that handles nested-ish comments
/// correctly for typical C headers.
fn strip_comments(source: &str) -> String {
    let mut result = String::with_capacity(source.len());
    let chars: Vec<char> = source.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        if i + 1 < len && chars[i] == '/' && chars[i + 1] == '/' {
            // Line comment — skip to end of line
            while i < len && chars[i] != '\n' {
                i += 1;
            }
        } else if i + 1 < len && chars[i] == '/' && chars[i + 1] == '*' {
            // Block comment — skip to closing */
            i += 2;
            while i + 1 < len && !(chars[i] == '*' && chars[i + 1] == '/') {
                i += 1;
            }
            i += 2; // Skip the closing */
        } else {
            result.push(chars[i]);
            i += 1;
        }
    }

    result
}

/// Detect common allocation patterns from function signature heuristics.
///
/// Returns a suggested ownership pattern string ("alloc", "free", "borrow")
/// based on the function's signature shape. Returns None if no pattern
/// can be confidently inferred.
pub fn detect_ownership_pattern(sig: &CFunctionSignature) -> Option<&'static str> {
    // Strong signal: name contains "alloc", "create", "new", "open" + returns pointer
    let name_lower = sig.name.to_lowercase();
    if sig.likely_alloc
        && (name_lower.contains("alloc")
            || name_lower.contains("create")
            || name_lower.contains("new")
            || name_lower.contains("open")
            || name_lower.contains("init"))
    {
        return Some("alloc");
    }

    // Strong signal: name contains "free", "destroy", "close", "release" + void return
    if sig.likely_free
        && (name_lower.contains("free")
            || name_lower.contains("destroy")
            || name_lower.contains("close")
            || name_lower.contains("release")
            || name_lower.contains("cleanup"))
    {
        return Some("free");
    }

    // Weak signals
    if sig.likely_alloc {
        return Some("alloc");
    }
    if sig.likely_free {
        return Some("free");
    }

    // If all pointer params are const -> borrow
    if sig.params.iter().any(|p| p.is_pointer)
        && sig
            .params
            .iter()
            .filter(|p| p.is_pointer)
            .all(|p| p.is_const)
    {
        return Some("borrow");
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_function() {
        let source = "void* malloc(size_t size);\n";
        let sigs = parse_c_source(source).expect("TODO: handle error");
        assert_eq!(sigs.len(), 1);
        assert_eq!(sigs[0].name, "malloc");
        assert!(sigs[0].return_type.contains("void*"));
        assert!(sigs[0].likely_alloc);
    }

    #[test]
    fn test_parse_free_function() {
        let source = "void free(void* ptr);\n";
        let sigs = parse_c_source(source).expect("TODO: handle error");
        assert_eq!(sigs.len(), 1);
        assert_eq!(sigs[0].name, "free");
        assert!(sigs[0].likely_free);
        assert!(!sigs[0].likely_alloc);
    }

    #[test]
    fn test_parse_borrow_function() {
        let source = "size_t strlen(const char* s);\n";
        let sigs = parse_c_source(source).expect("TODO: handle error");
        assert_eq!(sigs.len(), 1);
        assert_eq!(sigs[0].name, "strlen");
        assert!(!sigs[0].likely_alloc);
        assert!(!sigs[0].likely_free);
    }

    #[test]
    fn test_parse_multiple_functions() {
        let source = r#"
void* malloc(size_t size);
void free(void* ptr);
int printf(const char* fmt);
FILE* fopen(const char* path, const char* mode);
int fclose(FILE* fp);
"#;
        let sigs = parse_c_source(source).expect("TODO: handle error");
        assert_eq!(sigs.len(), 5);
    }

    #[test]
    fn test_strip_comments() {
        let source = r#"
// This is a line comment
void* malloc(size_t size);
/* This is a
   block comment */
void free(void* ptr);
"#;
        let cleaned = strip_comments(source);
        assert!(!cleaned.contains("line comment"));
        assert!(!cleaned.contains("block comment"));
        assert!(cleaned.contains("malloc"));
        assert!(cleaned.contains("free"));
    }

    #[test]
    fn test_detect_alloc_pattern() {
        let sig = CFunctionSignature {
            name: "mylib_create".to_string(),
            return_type: "mylib_t*".to_string(),
            params: vec![],
            likely_alloc: true,
            likely_free: false,
        };
        assert_eq!(detect_ownership_pattern(&sig), Some("alloc"));
    }

    #[test]
    fn test_detect_free_pattern() {
        let sig = CFunctionSignature {
            name: "mylib_destroy".to_string(),
            return_type: "void".to_string(),
            params: vec![CParam {
                c_type: "mylib_t*".to_string(),
                name: "handle".to_string(),
                is_pointer: true,
                is_const: false,
            }],
            likely_alloc: false,
            likely_free: true,
        };
        assert_eq!(detect_ownership_pattern(&sig), Some("free"));
    }

    #[test]
    fn test_detect_borrow_pattern() {
        let sig = CFunctionSignature {
            name: "mylib_get_name".to_string(),
            return_type: "int".to_string(),
            params: vec![CParam {
                c_type: "const mylib_t*".to_string(),
                name: "handle".to_string(),
                is_pointer: true,
                is_const: true,
            }],
            likely_alloc: false,
            likely_free: false,
        };
        assert_eq!(detect_ownership_pattern(&sig), Some("borrow"));
    }

    #[test]
    fn test_void_params() {
        let source = "int getpid(void);\n";
        let sigs = parse_c_source(source).expect("TODO: handle error");
        assert_eq!(sigs.len(), 1);
        assert!(sigs[0].params.is_empty());
    }
}
