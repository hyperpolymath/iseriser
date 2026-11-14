// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser module for ephapaxiser — Finds resource allocation and deallocation sites in source code.
//
// This module performs a lightweight textual scan of source files to locate calls to
// allocator and deallocator functions. It does NOT build a full AST; instead it uses
// line-by-line pattern matching to find call sites. This is intentionally simple for
// Phase 1 — a full AST-based approach (e.g., via syn for Rust, tree-sitter for C/Zig)
// is planned for Phase 2.
//
// Design note: The parser only locates sites. Ownership tracking and violation detection
// are handled by the analyzer module.

use crate::abi::SourceLocation;
use crate::manifest::ResourceEntry;

/// A detected call site in source code — either an allocation or deallocation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CallSiteKind {
    /// A call to the resource's allocator function.
    Allocation,
    /// A call to the resource's deallocator function.
    Deallocation,
    /// A use of the resource (neither allocation nor deallocation).
    /// Phase 1 does not auto-detect usage sites; they are constructed manually.
    /// Phase 2 will add usage detection via AST analysis.
    #[allow(dead_code)]
    Usage,
}

/// A detected call site with its location and associated resource.
#[derive(Debug, Clone)]
pub struct CallSite {
    /// Which resource this call site belongs to.
    pub resource_name: String,
    /// Whether this is an allocation, deallocation, or usage.
    pub kind: CallSiteKind,
    /// Location in source code.
    pub location: SourceLocation,
    /// The variable name bound to the resource (if detectable), e.g., "fd" in "let fd = open(...)".
    pub binding: Option<String>,
}

/// Parse a source file's content to find allocation, deallocation, and usage sites
/// for the given resource definitions.
///
/// This performs a simple line-by-line scan looking for function call patterns.
/// Each resource's allocator and deallocator names are matched as substrings of
/// function calls on each line.
///
/// # Arguments
/// * `source_content` — The full text content of the source file.
/// * `file_path` — The path to the source file (for location reporting).
/// * `resources` — The resource definitions from the manifest.
///
/// # Returns
/// A vector of detected call sites, in order of appearance.
pub fn parse_source(
    source_content: &str,
    file_path: &str,
    resources: &[ResourceEntry],
) -> Vec<CallSite> {
    let mut sites = Vec::new();

    for (line_idx, line) in source_content.lines().enumerate() {
        let line_number = line_idx + 1;
        let trimmed = line.trim();

        // Skip comments and empty lines.
        if trimmed.is_empty() || trimmed.starts_with("//") || trimmed.starts_with('#') {
            continue;
        }

        for resource in resources {
            // Check for allocator call: e.g., "open(" or "File::open("
            if let Some(col) = find_function_call(trimmed, &resource.allocator) {
                let binding = extract_binding(trimmed, &resource.allocator);
                sites.push(CallSite {
                    resource_name: resource.name.clone(),
                    kind: CallSiteKind::Allocation,
                    location: SourceLocation {
                        file: file_path.to_string(),
                        line: line_number,
                        column: col + 1,
                    },
                    binding,
                });
            }

            // Check for deallocator call: e.g., "close(" or "fd.close("
            if let Some(col) = find_function_call(trimmed, &resource.deallocator) {
                let binding = extract_dealloc_target(trimmed, &resource.deallocator);
                sites.push(CallSite {
                    resource_name: resource.name.clone(),
                    kind: CallSiteKind::Deallocation,
                    location: SourceLocation {
                        file: file_path.to_string(),
                        line: line_number,
                        column: col + 1,
                    },
                    binding,
                });
            }
        }
    }

    sites
}

/// Find a function call pattern in a line, returning the column offset if found.
///
/// Looks for `name(` as a word boundary — the character before `name` must not be
/// alphanumeric or underscore (to avoid matching substrings like "reopen" when
/// searching for "open").
fn find_function_call(line: &str, function_name: &str) -> Option<usize> {
    let pattern = format!("{}(", function_name);
    let mut search_from = 0;

    while let Some(pos) = line[search_from..].find(&pattern) {
        let absolute_pos = search_from + pos;
        // Check word boundary: character before must not be alphanumeric or underscore.
        if absolute_pos == 0
            || !line.as_bytes()[absolute_pos - 1].is_ascii_alphanumeric()
                && line.as_bytes()[absolute_pos - 1] != b'_'
        {
            return Some(absolute_pos);
        }
        search_from = absolute_pos + 1;
    }
    None
}

/// Extract the variable name bound to an allocator call.
///
/// Recognises patterns like:
/// - `let fd = open(...)` → Some("fd")
/// - `let mut fd = open(...)` → Some("fd")
/// - `fd = open(...)` → Some("fd")
/// - `open(...)` → None
fn extract_binding(line: &str, allocator: &str) -> Option<String> {
    let trimmed = line.trim();

    // Pattern: "let [mut] NAME = ...allocator("
    if let Some(let_pos) = trimmed.find("let ") {
        let after_let = &trimmed[let_pos + 4..];
        // Skip "mut " if present.
        let after_mut = if after_let.starts_with("mut ") {
            &after_let[4..]
        } else {
            after_let
        };
        // Extract identifier before '=' or ':'.
        let name_end = after_mut
            .find(|c: char| !c.is_alphanumeric() && c != '_')
            .unwrap_or(after_mut.len());
        if name_end > 0 {
            let name = &after_mut[..name_end];
            // Verify the allocator appears after the binding.
            if trimmed.contains(&format!("{}(", allocator)) {
                return Some(name.to_string());
            }
        }
    }

    // Pattern: "NAME = ...allocator(" (simple assignment, no let).
    if let Some(eq_pos) = trimmed.find('=') {
        // Make sure it's not '==' or preceded by '!' etc.
        if eq_pos > 0
            && (eq_pos + 1 >= trimmed.len() || trimmed.as_bytes()[eq_pos + 1] != b'=')
            && trimmed.as_bytes()[eq_pos - 1] != b'!'
            && trimmed.as_bytes()[eq_pos - 1] != b'<'
            && trimmed.as_bytes()[eq_pos - 1] != b'>'
        {
            let before_eq = trimmed[..eq_pos].trim();
            // Extract the last identifier token.
            let name_start = before_eq
                .rfind(|c: char| !c.is_alphanumeric() && c != '_')
                .map(|p| p + 1)
                .unwrap_or(0);
            let name = &before_eq[name_start..];
            if !name.is_empty()
                && name != "let"
                && name != "mut"
                && trimmed[eq_pos..].contains(&format!("{}(", allocator))
            {
                return Some(name.to_string());
            }
        }
    }

    None
}

/// Extract the target variable of a deallocator call.
///
/// Recognises patterns like:
/// - `close(fd)` → Some("fd")
/// - `fd.close()` → Some("fd")
/// - `disconnect(conn)` → Some("conn")
fn extract_dealloc_target(line: &str, deallocator: &str) -> Option<String> {
    let trimmed = line.trim();

    // Pattern: "target.deallocator(" — method call style.
    let method_pattern = format!(".{}(", deallocator);
    if let Some(dot_pos) = trimmed.find(&method_pattern) {
        let before_dot = &trimmed[..dot_pos];
        let name_start = before_dot
            .rfind(|c: char| !c.is_alphanumeric() && c != '_')
            .map(|p| p + 1)
            .unwrap_or(0);
        let name = &before_dot[name_start..];
        if !name.is_empty() {
            return Some(name.to_string());
        }
    }

    // Pattern: "deallocator(target)" — function call style.
    let call_pattern = format!("{}(", deallocator);
    if let Some(call_pos) = trimmed.find(&call_pattern) {
        let after_paren = &trimmed[call_pos + call_pattern.len()..];
        // Extract first argument.
        let arg_end = after_paren
            .find(|c: char| !c.is_alphanumeric() && c != '_')
            .unwrap_or(after_paren.len());
        if arg_end > 0 {
            let arg = &after_paren[..arg_end];
            return Some(arg.to_string());
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper to create a simple resource entry for testing.
    fn test_resource(name: &str, alloc: &str, dealloc: &str) -> ResourceEntry {
        ResourceEntry {
            name: name.to_string(),
            allocator: alloc.to_string(),
            deallocator: dealloc.to_string(),
            kind: "file-descriptor".to_string(),
        }
    }

    #[test]
    fn test_parse_finds_allocation() {
        let source = "let fd = open(\"test.txt\");\n";
        let resources = vec![test_resource("FD", "open", "close")];
        let sites = parse_source(source, "test.rs", &resources);
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].kind, CallSiteKind::Allocation);
        assert_eq!(sites[0].binding, Some("fd".to_string()));
    }

    #[test]
    fn test_parse_finds_deallocation() {
        let source = "close(fd);\n";
        let resources = vec![test_resource("FD", "open", "close")];
        let sites = parse_source(source, "test.rs", &resources);
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].kind, CallSiteKind::Deallocation);
        assert_eq!(sites[0].binding, Some("fd".to_string()));
    }

    #[test]
    fn test_parse_skips_comments() {
        let source = "// open(\"test.txt\");\nlet fd = open(\"real.txt\");\n";
        let resources = vec![test_resource("FD", "open", "close")];
        let sites = parse_source(source, "test.rs", &resources);
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].location.line, 2);
    }

    #[test]
    fn test_method_style_dealloc() {
        let source = "fd.close();\n";
        let resources = vec![test_resource("FD", "open", "close")];
        let sites = parse_source(source, "test.rs", &resources);
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].kind, CallSiteKind::Deallocation);
        assert_eq!(sites[0].binding, Some("fd".to_string()));
    }

    #[test]
    fn test_word_boundary_no_false_positive() {
        // "reopen" should NOT match allocator "open"
        let source = "let x = reopen(\"test.txt\");\n";
        let resources = vec![test_resource("FD", "open", "close")];
        let sites = parse_source(source, "test.rs", &resources);
        assert!(
            sites.is_empty(),
            "should not match 'reopen' for allocator 'open'"
        );
    }
}
