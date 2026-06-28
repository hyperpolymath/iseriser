// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Idris2 → ABI-manifest emitter — parses the cartridge-style `Safe*.idr`
// sources and emits the JSON manifest the `abi-verify` subcommand consumes.
//
// Phase 1b of standards#89 sub-issue 3 / standards#92. Together with
// Phase 1 (verify.rs + zig_ffi_parser.rs) this closes the loop: the
// Idris2 source is now the single authority — the manifest is derived
// from it at build time, and the Zig FFI is verified against the
// derived manifest. Hand-authoring drops out.
//
// Scope (deliberately narrow for Phase 1b — matches what the cartridge
// convention actually produces; not a general Idris2 parser):
//   * `data <Name> = A | B | C` (one-line form)
//   * `data <Name>` followed by `= A` / `| B` / `| C Params` (multi-line)
//   * `<name>ToInt A = 0` integer encoding equations
//   * `canTransition A B = True` allowed-transition equations
//   * `canTransition _ _ = False` catch-all is skipped (the verifier
//     already catches accept-by-omission as drift)
//
// Variants with parameters (e.g. `Custom String`) are included in the
// enum if their `<name>ToInt` equation has a matching pattern
// (`(Custom _)`); otherwise they are skipped — the manifest is about
// the C-ABI encoding, not the full Idris2 ADT shape.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use anyhow::{Context, Result, anyhow};

use crate::abi::manifest_schema::{
    AbiManifest, EnumDecl, EnumVariant, TransitionRow, TransitionTable,
};

/// Parse an Idris2 source and emit an `AbiManifest`.
///
/// `cartridge_name` becomes the manifest's `cartridge` field (e.g.
/// `"ssg-mcp"`). `source_path` becomes the manifest's `source_idris`
/// field (relative-to-repo display path, NOT necessarily the same as
/// the on-disk path the parser reads — pass the canonical repo path).
pub fn emit_from_idris_path(
    idris_path: &Path,
    cartridge_name: &str,
    source_path_for_manifest: &str,
) -> Result<AbiManifest> {
    let src = fs::read_to_string(idris_path)
        .with_context(|| format!("reading Idris2 source `{}`", idris_path.display()))?;
    emit_from_idris_src(&src, cartridge_name, source_path_for_manifest)
}

pub fn emit_from_idris_src(
    src: &str,
    cartridge_name: &str,
    source_path_for_manifest: &str,
) -> Result<AbiManifest> {
    let stripped = strip_line_comments(src);
    let enum_decls = parse_enum_declarations(&stripped)?;
    let int_maps = parse_to_int_equations(&stripped)?;
    let to_int_sigs = parse_to_int_signatures(&stripped)?;
    let transitions = parse_can_transition_equations(&stripped)?;

    // Compose enums by joining the declarations with the int-mappings.
    // The function whose mappings apply to each enum is found via the
    // `<fn> : <Enum> -> Int` type signature — the cartridge convention
    // doesn't always name the function after the enum (e.g. `SsgEngine`
    // uses `engineToInt`, `K9Format` uses `formatToInt`).
    let mut enums = Vec::new();
    for (enum_name, variant_names) in &enum_decls {
        let to_int_fn = to_int_sigs.get(enum_name);
        let mapping = to_int_fn.and_then(|fn_name| int_maps.get(fn_name));
        let mut variants = Vec::new();
        for variant_name in variant_names {
            if let Some(map) = mapping
                && let Some(&value) = map.get(variant_name)
            {
                variants.push(EnumVariant {
                    name: variant_name.clone(),
                    value,
                });
            }
        }
        if !variants.is_empty() {
            enums.push(EnumDecl {
                name: enum_name.clone(),
                variants,
            });
        }
    }

    // Compose the transition table. The "state enum" is whichever enum
    // appears in the parsed canTransition equations (by convention there
    // is exactly one per Safe*.idr cartridge module).
    let transition_table = if transitions.is_empty() {
        None
    } else {
        // Pick the enum that contains every variant mentioned in the
        // transitions — that's the state enum.
        let mentioned: std::collections::BTreeSet<&str> = transitions
            .iter()
            .flat_map(|(from, to)| [from.as_str(), to.as_str()])
            .collect();
        let state_enum = enums
            .iter()
            .find(|e| {
                let known: std::collections::BTreeSet<&str> =
                    e.variants.iter().map(|v| v.name.as_str()).collect();
                mentioned.iter().all(|m| known.contains(m))
            })
            .ok_or_else(|| {
                anyhow!(
                    "no enum in the source covers every variant mentioned in canTransition: {:?}",
                    mentioned
                )
            })?;
        let rows = transitions
            .into_iter()
            .map(|(from, to)| TransitionRow {
                from,
                to,
                allowed: true,
            })
            .collect();
        Some(TransitionTable {
            state_enum: state_enum.name.clone(),
            rows,
        })
    };

    Ok(AbiManifest {
        schema_version: "1.0".into(),
        cartridge: cartridge_name.to_string(),
        source_idris: source_path_for_manifest.to_string(),
        enums,
        transition_table,
    })
}

/// Strip `--` line comments, preserving newlines so downstream
/// line-oriented parsers are not broken by a swallowed newline.
fn strip_line_comments(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    for line in src.split_inclusive('\n') {
        let trim = line.trim_start();
        // `|||` is the Idris2 doc comment; treat as a comment too.
        if trim.starts_with("|||") {
            out.push('\n');
            continue;
        }
        match line.find("--") {
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

/// Walk `data X = ...` declarations and return `enum_name → [variants…]`.
/// Variant names are the head identifier only (e.g. `Custom String` → `Custom`).
/// Insertion order is the source order, which matters because the manifest
/// preserves it.
fn parse_enum_declarations(src: &str) -> Result<Vec<(String, Vec<String>)>> {
    let mut out = Vec::new();
    let mut rest = src;
    while let Some(idx) = find_data_keyword(rest) {
        let after = &rest[idx + "data".len()..];
        // Eat whitespace, capture the enum name (identifier).
        let after = after.trim_start();
        let name_end = after
            .find(|c: char| !is_ident_char(c))
            .unwrap_or(after.len());
        if name_end == 0 {
            rest = after;
            continue;
        }
        let name = after[..name_end].to_string();
        let body_src = &after[name_end..];

        let (variants, consumed) = collect_data_body(body_src)?;
        if !variants.is_empty() {
            out.push((name, variants));
        }
        rest = &body_src[consumed..];
    }
    Ok(out)
}

/// Find the next `data` keyword that's a top-level declaration (preceded
/// by start-of-input, newline, or whitespace; followed by whitespace).
fn find_data_keyword(src: &str) -> Option<usize> {
    let bytes = src.as_bytes();
    let mut search_from = 0;
    while let Some(pos) = src[search_from..].find("data") {
        let abs = search_from + pos;
        let before_ok = abs == 0 || matches!(bytes[abs - 1], b'\n' | b' ' | b'\t');
        let after = abs + 4;
        let after_ok = after < bytes.len() && matches!(bytes[after], b' ' | b'\t' | b'\n');
        if before_ok && after_ok {
            return Some(abs);
        }
        search_from = abs + 4;
    }
    None
}

/// After the enum name, collect the variant list. Handles both
/// `= A | B | C` (one-line) and `\n  = A\n  | B\n  | C` (multi-line).
/// Returns the variant names + the number of bytes consumed from `src`.
///
/// Also handles GADT-style declarations (`data Foo : Type -> Type where …`)
/// by skipping them: they are proof/relation types, not exported enums,
/// and have no place in the ABI manifest. Returns an empty variant list
/// with the byte-count needed to walk past the GADT block.
fn collect_data_body(src: &str) -> Result<(Vec<String>, usize)> {
    // GADT detection: the body starts with `:` (signature form), not `=`
    // (variant-list form). Examples seen in the wild:
    //   `data MonotonicDegradation : State -> State -> Type where
    //      StayHealthy : MonotonicDegradation Healthy Healthy
    //      …`
    // These declare proof relations, not data with variants.
    let trimmed = src.trim_start();
    if trimmed.starts_with(':') {
        return Ok((Vec::new(), skip_gadt_block(src)));
    }

    // Find the `=` that opens the variant list.
    let eq_idx = src
        .find('=')
        .ok_or_else(|| anyhow!("data declaration has no `=`"))?;
    // From there, accumulate until we hit a blank line or a new top-level
    // declaration (a line that doesn't start with whitespace and isn't
    // a continuation `|` line).
    let after_eq = &src[eq_idx + 1..];
    let mut variants_text = String::new();
    let mut consumed = eq_idx + 1;
    let mut first_line = true;
    for line in after_eq.split_inclusive('\n') {
        let trimmed = line.trim_end_matches('\n');
        if first_line {
            variants_text.push_str(trimmed);
            consumed += line.len();
            first_line = false;
            continue;
        }
        let ltrim = trimmed.trim_start();
        // Continuation: indented `|` line, OR continuation of the
        // current expression (indented non-`|` line — e.g. a single
        // continued variant).
        let starts_with_ws = trimmed.starts_with(' ') || trimmed.starts_with('\t');
        if starts_with_ws && (ltrim.starts_with('|') || !ltrim.is_empty()) {
            variants_text.push(' ');
            variants_text.push_str(ltrim);
            consumed += line.len();
            continue;
        }
        break;
    }
    // Now `variants_text` is something like `Empty | ContentLoaded | Built ...`
    // OR `| Hugo | Zola | Astro | Casket | Custom String`.
    // Split on `|`, take the head identifier of each piece.
    let mut variants = Vec::new();
    for piece in variants_text.split('|') {
        let p = piece.trim();
        if p.is_empty() {
            continue;
        }
        let head_end = p.find(|c: char| !is_ident_char(c)).unwrap_or(p.len());
        if head_end == 0 {
            continue;
        }
        let head = &p[..head_end];
        variants.push(head.to_string());
    }
    Ok((variants, consumed))
}

/// Skip past a GADT-style `data Foo : … where …` declaration. The block
/// ends at the first non-indented, non-blank line (or end of input). The
/// declaration itself contributes nothing to the manifest.
fn skip_gadt_block(src: &str) -> usize {
    // First: consume the type signature line(s) up to `where` (or end of
    // declaration if there is no `where`, e.g. `data Empty : Type`).
    let where_pos = src.find("where");
    let header_end = match where_pos {
        Some(w) => {
            // Consume through the rest of that line.
            src[w..].find('\n').map(|i| w + i + 1).unwrap_or(src.len())
        }
        None => {
            // No `where` — single-line `data Foo : ...`. Consume through eol.
            src.find('\n').map(|i| i + 1).unwrap_or(src.len())
        }
    };

    // No constructor block to walk if we already hit EOF.
    if header_end >= src.len() {
        return src.len();
    }

    // Now consume the indented constructor block (if any).
    let mut consumed = header_end;
    for line in src[header_end..].split_inclusive('\n') {
        let trimmed = line.trim_end_matches('\n');
        // Blank lines are tolerated inside the block; they don't end it.
        if trimmed.is_empty() {
            consumed += line.len();
            continue;
        }
        // A line not starting with whitespace ends the GADT block.
        let starts_with_ws = trimmed.starts_with(' ') || trimmed.starts_with('\t');
        if !starts_with_ws {
            break;
        }
        consumed += line.len();
    }
    consumed
}

/// Parse all `<fn> <variant> = <int>` equations grouped by function name.
/// Returns `fn_name → (variant_name → integer)`. Patterns of the form
/// `(VariantName _)` are accepted (parameterised constructor); patterns
/// of the form `_` (catch-all) are skipped.
fn parse_to_int_equations(src: &str) -> Result<BTreeMap<String, BTreeMap<String, i64>>> {
    let mut out: BTreeMap<String, BTreeMap<String, i64>> = BTreeMap::new();
    for line in src.lines() {
        let l = line.trim();
        if l.is_empty() {
            continue;
        }
        // Look for ` = <int>` at the tail.
        let Some(eq_pos) = l.rfind('=') else {
            continue;
        };
        let rhs = l[eq_pos + 1..].trim();
        let value: i64 = match rhs.parse() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let lhs = l[..eq_pos].trim();
        // lhs shape: `<fnname> <pattern>` — split on first whitespace.
        let mut parts = lhs.splitn(2, char::is_whitespace);
        let fn_name = parts.next().unwrap_or("").trim();
        let pattern = parts.next().unwrap_or("").trim();
        if fn_name.is_empty() || pattern.is_empty() {
            continue;
        }
        if !fn_name.ends_with("ToInt") {
            continue;
        }
        let variant_name = match extract_variant_from_pattern(pattern) {
            Some(v) => v,
            None => continue,
        };
        out.entry(fn_name.to_string())
            .or_default()
            .insert(variant_name, value);
    }
    Ok(out)
}

/// Extract the head variant name from a pattern like `Empty`, `(Custom _)`,
/// `Custom`. Returns `None` for `_` or empty / non-identifier patterns.
fn extract_variant_from_pattern(pattern: &str) -> Option<String> {
    let p = pattern.trim_start_matches('(').trim_end_matches(')').trim();
    let head_end = p.find(|c: char| !is_ident_char(c)).unwrap_or(p.len());
    if head_end == 0 {
        return None;
    }
    let head = &p[..head_end];
    if head == "_" || !head.chars().next().unwrap().is_ascii_uppercase() {
        return None;
    }
    Some(head.to_string())
}

/// Parse `canTransition <From> <To> = True` equations. Skips the
/// catch-all `canTransition _ _ = False`.
/// Returns the list of (from, to) pairs in source order.
fn parse_can_transition_equations(src: &str) -> Result<Vec<(String, String)>> {
    let mut out = Vec::new();
    for line in src.lines() {
        let l = line.trim();
        if !l.starts_with("canTransition") {
            continue;
        }
        // Skip the type signature line `canTransition : ...`.
        if let Some(after) = l.strip_prefix("canTransition")
            && after.trim_start().starts_with(':')
        {
            continue;
        }
        let Some(eq_pos) = l.rfind('=') else {
            continue;
        };
        let rhs = l[eq_pos + 1..].trim();
        if rhs != "True" {
            continue;
        }
        let lhs = l[..eq_pos].trim();
        let after_fn = lhs
            .strip_prefix("canTransition")
            .ok_or_else(|| anyhow!("expected canTransition prefix on `{}`", l))?
            .trim();
        // Split into two patterns (handle parens, but cartridge sources
        // don't currently use parameterised patterns on the state enums).
        let tokens: Vec<&str> = after_fn.split_whitespace().collect();
        if tokens.len() < 2 {
            continue;
        }
        let from = match extract_variant_from_pattern(tokens[0]) {
            Some(v) => v,
            None => continue,
        };
        let to = match extract_variant_from_pattern(tokens[1]) {
            Some(v) => v,
            None => continue,
        };
        out.push((from, to));
    }
    Ok(out)
}

/// Parse `<fnName> : <EnumName> -> Int` type signatures. Returns a map
/// `EnumName → fnName` (only `*ToInt`-style functions returning `Int`).
/// This is how the emitter associates each enum with its integer-encoding
/// function — the cartridge convention is loose (`SsgEngine` uses
/// `engineToInt`, `K9Format` uses `formatToInt`), so naive name derivation
/// doesn't work.
fn parse_to_int_signatures(src: &str) -> Result<BTreeMap<String, String>> {
    let mut out = BTreeMap::new();
    for line in src.lines() {
        let l = line.trim();
        // Match `<ident> : <T> -> Int` (allowing extra whitespace).
        let Some(colon) = l.find(':') else {
            continue;
        };
        let fn_name = l[..colon].trim();
        if fn_name.is_empty() || !fn_name.ends_with("ToInt") {
            continue;
        }
        // Verify it's a valid identifier (no spaces).
        if fn_name.chars().any(|c| !is_ident_char(c)) {
            continue;
        }
        let rhs = l[colon + 1..].trim();
        // Expect `<EnumName> -> Int` (or `... -> Int`).
        let Some(arrow) = rhs.find("->") else {
            continue;
        };
        let enum_name = rhs[..arrow].trim();
        let ret = rhs[arrow + 2..].trim();
        if ret != "Int" {
            continue;
        }
        if enum_name.is_empty() || enum_name.chars().any(|c| !is_ident_char(c)) {
            continue;
        }
        out.insert(enum_name.to_string(), fn_name.to_string());
    }
    Ok(out)
}

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_one_line_data_decl() {
        let src = "
data Foo = A | B | C
fooToInt : Foo -> Int
fooToInt A = 0
fooToInt B = 1
fooToInt C = 2
";
        let m = emit_from_idris_src(src, "demo", "Foo.idr").unwrap();
        assert_eq!(m.enums.len(), 1);
        assert_eq!(m.enums[0].name, "Foo");
        assert_eq!(m.enums[0].variants.len(), 3);
        assert_eq!(m.enums[0].variants[0].name, "A");
        assert_eq!(m.enums[0].variants[0].value, 0);
        assert_eq!(m.enums[0].variants[2].value, 2);
    }

    #[test]
    fn parses_multi_line_data_decl_with_param_variant() {
        let src = "
data Engine
  = Hugo
  | Zola
  | Custom String

engineToInt : Engine -> Int
engineToInt Hugo        = 1
engineToInt Zola        = 2
engineToInt (Custom _)  = 99
";
        let m = emit_from_idris_src(src, "demo", "Engine.idr").unwrap();
        let e = m.enums.iter().find(|e| e.name == "Engine").unwrap();
        let names: Vec<&str> = e.variants.iter().map(|v| v.name.as_str()).collect();
        assert_eq!(names, vec!["Hugo", "Zola", "Custom"]);
        assert_eq!(e.variants[2].value, 99);
    }

    #[test]
    fn signature_associates_loose_fn_name_with_enum() {
        // Real cartridge convention: SsgEngine uses engineToInt, not
        // ssgEngineToInt. The type signature is the authority.
        let src = "
data SsgEngine = Hugo | Zola | Astro

engineToInt : SsgEngine -> Int
engineToInt Hugo  = 1
engineToInt Zola  = 2
engineToInt Astro = 3
";
        let m = emit_from_idris_src(src, "demo", "Engine.idr").unwrap();
        let e = m.enums.iter().find(|e| e.name == "SsgEngine").unwrap();
        assert_eq!(e.variants.len(), 3);
        assert_eq!(e.variants[0].value, 1);
    }

    #[test]
    fn drops_variant_without_to_int_mapping() {
        let src = "
data Mood = Happy | Sad | Indifferent

moodToInt : Mood -> Int
moodToInt Happy = 0
moodToInt Sad   = 1
-- Indifferent has no mapping
";
        let m = emit_from_idris_src(src, "demo", "Mood.idr").unwrap();
        let e = &m.enums[0];
        let names: Vec<&str> = e.variants.iter().map(|v| v.name.as_str()).collect();
        assert_eq!(names, vec!["Happy", "Sad"]);
    }

    #[test]
    fn parses_can_transition_skipping_catch_all() {
        let src = "
data S = A | B | C

sToInt : S -> Int
sToInt A = 0
sToInt B = 1
sToInt C = 2

canTransition : S -> S -> Bool
canTransition A B = True
canTransition B C = True
canTransition C A = True
canTransition _ _ = False
";
        let m = emit_from_idris_src(src, "demo", "S.idr").unwrap();
        let tt = m.transition_table.unwrap();
        assert_eq!(tt.state_enum, "S");
        assert_eq!(tt.rows.len(), 3);
        for row in &tt.rows {
            assert!(row.allowed);
        }
        let pairs: Vec<(String, String)> = tt
            .rows
            .iter()
            .map(|r| (r.from.clone(), r.to.clone()))
            .collect();
        assert!(pairs.contains(&("A".into(), "B".into())));
        assert!(pairs.contains(&("B".into(), "C".into())));
        assert!(pairs.contains(&("C".into(), "A".into())));
    }

    #[test]
    fn strips_idris_doc_comments() {
        let src = "
||| this is a doc comment
data Foo = A | B

||| another doc comment
fooToInt : Foo -> Int
fooToInt A = 0
fooToInt B = 1
";
        let m = emit_from_idris_src(src, "demo", "Foo.idr").unwrap();
        assert_eq!(m.enums[0].variants.len(), 2);
    }

    #[test]
    fn skips_gadt_data_declaration() {
        // vordr-mcp shape: a real ADT `IntegrityState` plus a GADT proof
        // relation `MonotonicDegradation` over it. The GADT must be
        // skipped — it has no `=`-form variant list — but the surrounding
        // enum and the to-int mapping must still be picked up.
        let src = "
data IntegrityState = Healthy | Drifted | Tampered | Unknown

data MonotonicDegradation : IntegrityState -> IntegrityState -> Type where
  StayHealthy  : MonotonicDegradation Healthy Healthy
  HealthyDrift : MonotonicDegradation Healthy Drifted
  HealthyTamp  : MonotonicDegradation Healthy Tampered
  DriftedStay  : MonotonicDegradation Drifted Drifted
  DriftedTamp  : MonotonicDegradation Drifted Tampered
  TamperedStay : MonotonicDegradation Tampered Tampered

stateToInt : IntegrityState -> Int
stateToInt Healthy   = 0
stateToInt Drifted   = 1
stateToInt Tampered  = 2
stateToInt Unknown   = 3
";
        let m = emit_from_idris_src(src, "vordr-mcp", "SafeVordr.idr").unwrap();
        // The GADT must have been skipped, not emitted as an enum.
        assert_eq!(m.enums.len(), 1, "expected only IntegrityState in manifest");
        let e = &m.enums[0];
        assert_eq!(e.name, "IntegrityState");
        let names: Vec<&str> = e.variants.iter().map(|v| v.name.as_str()).collect();
        assert_eq!(names, vec!["Healthy", "Drifted", "Tampered", "Unknown"]);
        assert_eq!(e.variants[3].value, 3);
    }

    #[test]
    fn skips_signature_only_gadt_data_declaration() {
        // Degenerate GADT with no `where` block (single-line empty type)
        // followed by a real ADT that must still be picked up.
        let src = "
data Phantom : Type

data Real = Yes | No

realToInt : Real -> Int
realToInt Yes = 1
realToInt No  = 0
";
        let m = emit_from_idris_src(src, "demo", "P.idr").unwrap();
        assert_eq!(m.enums.len(), 1);
        assert_eq!(m.enums[0].name, "Real");
    }
}
