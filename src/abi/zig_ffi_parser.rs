// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Minimal Zig FFI parser — extracts the ABI-relevant shapes (enums +
// the `isValidTransition` switch table) from the Zig FFI bridges that
// mirror the Idris2 ABI.
//
// This is deliberately small and shape-specific to the hyperpolymath
// cartridge convention (see `boj-server/cartridges/{ssg,k9iser}-mcp/ffi/`).
// It does NOT try to be a general Zig parser.
//
// Phase 1 of standards#89 sub-issue 3 / standards#92.

use anyhow::{Context, Result, anyhow};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZigEnum {
    pub name: String,
    /// Variant snake_case name → assigned integer.
    pub variants: BTreeMap<String, i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZigTransitionTable {
    /// Underlying enum type name (e.g. "SsgState").
    pub state_enum: String,
    /// For each `from` arm, the set of `to` variant names accepted.
    /// Both keys + values are snake_case Zig variant names.
    pub arms: BTreeMap<String, Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZigFfi {
    pub enums: Vec<ZigEnum>,
    pub transition_table: Option<ZigTransitionTable>,
}

/// Parse a Zig FFI file. Returns the enums + the (single, by convention)
/// `isValidTransition` switch table, if present.
pub fn parse(src: &str) -> Result<ZigFfi> {
    let enums = parse_enums(src)?;
    let transition_table = parse_transition_table(src)?;
    Ok(ZigFfi {
        enums,
        transition_table,
    })
}

/// Parse all `pub const <Name> = enum(c_int) { ... };` blocks.
fn parse_enums(src: &str) -> Result<Vec<ZigEnum>> {
    let mut out = Vec::new();
    let needle = "= enum(c_int) {";
    let mut rest = src;
    while let Some(eq_pos) = rest.find(needle) {
        // Walk backwards from `eq_pos` to find the enum name + the
        // `pub const` keyword.
        let pre = &rest[..eq_pos];
        let pre_trim = pre.trim_end();
        let name_start = pre_trim
            .rfind(|c: char| c.is_whitespace())
            .map(|i| i + 1)
            .unwrap_or(0);
        let name = pre_trim[name_start..].trim().to_string();
        // Look backwards for `pub const` before the name; if absent,
        // skip this match (defensive — keeps the parser honest about
        // the shape it expects).
        let lead = pre[..name_start].trim_end();
        if !lead.ends_with("pub const") && !lead.ends_with("const") {
            rest = &rest[eq_pos + needle.len()..];
            continue;
        }
        // Find the matching closing brace `};`.
        let body_start = eq_pos + needle.len();
        let body_src = &rest[body_start..];
        let close = body_src
            .find("};")
            .ok_or_else(|| anyhow!("unterminated enum body for `{}`", name))?;
        let body = &body_src[..close];
        let variants = parse_enum_body(body)
            .with_context(|| format!("parsing variants for enum `{}`", name))?;
        out.push(ZigEnum { name, variants });
        rest = &body_src[close + 2..];
    }
    Ok(out)
}

fn parse_enum_body(body: &str) -> Result<BTreeMap<String, i64>> {
    let mut variants = BTreeMap::new();
    let stripped = strip_line_comments(body);
    for raw in stripped.split(',') {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        let mut parts = line.splitn(2, '=');
        let name = parts
            .next()
            .ok_or_else(|| anyhow!("empty variant entry"))?
            .trim()
            .to_string();
        let value_str = parts
            .next()
            .ok_or_else(|| anyhow!("variant `{}` missing `= <int>` value", name))?
            .trim();
        let value: i64 = value_str
            .parse()
            .with_context(|| format!("variant `{}` value `{}` is not an integer", name, value_str))?;
        if variants.insert(name.clone(), value).is_some() {
            return Err(anyhow!("duplicate variant `{}` in enum body", name));
        }
    }
    Ok(variants)
}

/// Locate the canonical `fn isValidTransition(from: T, to: T) bool` and
/// parse its `switch (from)` arms into `from → [to, to, …]`.
fn parse_transition_table(src: &str) -> Result<Option<ZigTransitionTable>> {
    let sig_idx = match src.find("fn isValidTransition") {
        Some(i) => i,
        None => return Ok(None),
    };
    let after_sig = &src[sig_idx..];
    let from_type = extract_from_type(after_sig)
        .context("could not extract `from:` parameter type of isValidTransition")?;
    // Find the `switch (from)` block inside the function body.
    let switch_kw = after_sig
        .find("switch (from)")
        .ok_or_else(|| anyhow!("isValidTransition has no `switch (from)` block"))?;
    let body_start_offset = after_sig[switch_kw..]
        .find('{')
        .ok_or_else(|| anyhow!("`switch (from)` has no opening brace"))?;
    let body_start = switch_kw + body_start_offset + 1;
    // Brace-balance to find the matching close.
    let body_src = &after_sig[body_start..];
    let mut depth: i32 = 1;
    let mut end_idx = None;
    for (i, c) in body_src.char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    end_idx = Some(i);
                    break;
                }
            }
            _ => {}
        }
    }
    let end =
        end_idx.ok_or_else(|| anyhow!("`switch (from)` body is unterminated"))?;
    let body = &body_src[..end];
    let arms = parse_switch_arms(body)?;
    Ok(Some(ZigTransitionTable {
        state_enum: from_type,
        arms,
    }))
}

/// Extract the type of the `from:` parameter from
/// `fn isValidTransition(from: T, to: T) bool`.
fn extract_from_type(after_sig: &str) -> Result<String> {
    let open = after_sig
        .find('(')
        .ok_or_else(|| anyhow!("isValidTransition has no opening paren"))?;
    let close = after_sig
        .find(')')
        .ok_or_else(|| anyhow!("isValidTransition has no closing paren"))?;
    let params = &after_sig[open + 1..close];
    let first_param = params
        .split(',')
        .next()
        .ok_or_else(|| anyhow!("isValidTransition has no parameters"))?;
    let mut parts = first_param.splitn(2, ':');
    let _name = parts.next();
    let ty = parts
        .next()
        .ok_or_else(|| anyhow!("first param of isValidTransition is missing a type"))?
        .trim()
        .to_string();
    Ok(ty)
}

/// Strip `// …` line comments line-by-line, leaving newlines intact so
/// the comma-split downstream is not broken by a comment swallowing the
/// next variant.
fn strip_line_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    for line in src.split_inclusive('\n') {
        match line.find("//") {
            Some(i) => {
                out.push_str(&line[..i]);
                if line.ends_with('\n') {
                    out.push('\n');
                }
            }
            None => out.push_str(line),
        }
    }
    out
}

/// Parse `switch (from) { ... }` arms. Recognises:
///   `.<from_variant> => to == .<to1> or to == .<to2> ...,`
/// Ignores `else => ...` (treated as the implicit "everything else rejected"
/// arm; if present and not just `false`, that's a drift the verifier
/// surfaces via missing `from`-arm coverage rather than guessing here).
fn parse_switch_arms(body: &str) -> Result<BTreeMap<String, Vec<String>>> {
    let mut arms = BTreeMap::new();
    let stripped = strip_line_comments(body);
    // Arms are comma-separated at depth 0; the bodies don't contain
    // nested braces in the cartridge convention, so a plain split is fine.
    for raw in stripped.split(',') {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        let arrow = match line.find("=>") {
            Some(i) => i,
            None => continue,
        };
        let from = line[..arrow].trim();
        let body_part = line[arrow + 2..].trim();
        if from == "else" {
            // Implicit reject (or non-trivial else) — surface that the
            // FFI uses an `else` arm so the verifier can refuse to
            // certify it. We model this as a special sentinel key.
            let entry = arms.entry("_else".to_string()).or_insert_with(Vec::new);
            entry.push(body_part.to_string());
            continue;
        }
        let from = from
            .strip_prefix('.')
            .ok_or_else(|| anyhow!("switch arm `{}` does not start with `.`", from))?
            .to_string();
        let tos = parse_arm_targets(body_part).with_context(|| {
            format!("parsing targets of switch arm for `{}`", from)
        })?;
        if arms.insert(from.clone(), tos).is_some() {
            return Err(anyhow!("duplicate switch arm for `{}`", from));
        }
    }
    Ok(arms)
}

/// Parse `to == .<v1> or to == .<v2> or to == .<v3>` → `["v1","v2","v3"]`.
/// Also accepts the singleton form `to == .<v>`.
///
/// Terminal-state shorthand: a body of `false` (with optional trailing
/// `,` / `;` and surrounding whitespace) is accepted as the empty
/// allowed-set — i.e. "no outgoing transitions allowed from this
/// state". Cartridges like bsp-mcp, container-mcp, dap-mcp, lsp-mcp,
/// vault-mcp use this form for their `exited` / terminal arms.
fn parse_arm_targets(body: &str) -> Result<Vec<String>> {
    let trimmed = body
        .trim()
        .trim_end_matches(',')
        .trim_end_matches(';')
        .trim();
    if trimmed == "false" {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    for chunk in body.split(" or ") {
        let chunk = chunk.trim();
        let rhs = chunk
            .strip_prefix("to ==")
            .or_else(|| chunk.strip_prefix("to=="))
            .ok_or_else(|| anyhow!("arm chunk `{}` does not match `to == .<v>`", chunk))?
            .trim();
        let variant = rhs
            .strip_prefix('.')
            .ok_or_else(|| anyhow!("arm target `{}` does not start with `.`", rhs))?
            .trim()
            .trim_end_matches(',')
            .trim_end_matches(';')
            .to_string();
        out.push(variant);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_simple_enum() {
        let src = r#"
            pub const Foo = enum(c_int) {
                a = 0,
                b = 1,
                c = 2,
            };
        "#;
        let f = parse(src).unwrap();
        assert_eq!(f.enums.len(), 1);
        assert_eq!(f.enums[0].name, "Foo");
        assert_eq!(f.enums[0].variants.get("a"), Some(&0));
        assert_eq!(f.enums[0].variants.get("b"), Some(&1));
        assert_eq!(f.enums[0].variants.get("c"), Some(&2));
    }

    #[test]
    fn parses_enum_with_trailing_comments() {
        let src = r#"
            pub const State = enum(c_int) {
                empty = 0,
                ready = 1, // ready to go
                done = 2,  // finished
            };
        "#;
        let f = parse(src).unwrap();
        assert_eq!(f.enums[0].variants.len(), 3);
    }

    #[test]
    fn parses_transition_table() {
        let src = r#"
            pub const S = enum(c_int) { a = 0, b = 1, c = 2 };
            fn isValidTransition(from: S, to: S) bool {
                return switch (from) {
                    .a => to == .b,
                    .b => to == .c or to == .a,
                    .c => to == .a,
                };
            }
        "#;
        let f = parse(src).unwrap();
        let tt = f.transition_table.unwrap();
        assert_eq!(tt.state_enum, "S");
        assert_eq!(tt.arms.get("a"), Some(&vec!["b".to_string()]));
        assert_eq!(
            tt.arms.get("b"),
            Some(&vec!["c".to_string(), "a".to_string()])
        );
        assert_eq!(tt.arms.get("c"), Some(&vec!["a".to_string()]));
    }

    #[test]
    fn captures_else_arm() {
        let src = r#"
            fn isValidTransition(from: S, to: S) bool {
                return switch (from) {
                    .a => to == .b,
                    else => false,
                };
            }
        "#;
        let f = parse(src).unwrap();
        let tt = f.transition_table.unwrap();
        assert!(tt.arms.contains_key("_else"));
    }

    #[test]
    fn tolerates_terminal_false_arm() {
        // bsp-mcp / container-mcp / dap-mcp / lsp-mcp / vault-mcp shape:
        // the terminal state's arm body is the literal `false` (meaning
        // no outgoing transitions allowed), not a `to == .<v>` chunk.
        // Without this tolerance the verifier mis-classifies the cartridge
        // as a parser error rather than the correct "empty allowed-set"
        // semantics.
        let src = r#"
            pub const BspState = enum(c_int) {
                uninitialized = 0,
                initializing = 1,
                ready = 2,
                exited = 3,
            };
            fn isValidTransition(from: BspState, to: BspState) bool {
                return switch (from) {
                    .uninitialized => to == .initializing,
                    .initializing  => to == .ready or to == .exited,
                    .ready         => to == .exited,
                    .exited        => false,
                };
            }
        "#;
        let f = parse(src).unwrap();
        let tt = f.transition_table.unwrap();
        // The terminal arm parses and lands in the arms map with an
        // empty allowed-set; it MUST be present (otherwise the verifier
        // would surface accept-by-omission as drift) but it MUST be
        // empty (no targets).
        assert_eq!(tt.arms.get("exited"), Some(&Vec::<String>::new()));
        // The other arms still parse correctly.
        assert_eq!(
            tt.arms.get("uninitialized"),
            Some(&vec!["initializing".to_string()])
        );
        assert_eq!(
            tt.arms.get("initializing"),
            Some(&vec!["ready".to_string(), "exited".to_string()])
        );
    }
}
