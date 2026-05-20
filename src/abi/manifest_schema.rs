// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI manifest schema — the Idris2-derived, language-neutral
// description of a cartridge's ABI surface. The verifier (verify.rs)
// diffs this against a parsed Zig FFI file to detect drift.
//
// Phase 1 of standards#89 sub-issue 3 / standards#92.
// Phase 1b will emit this from the Idris2 build instead of hand-authoring.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AbiManifest {
    pub schema_version: String,
    pub cartridge: String,
    pub source_idris: String,
    pub enums: Vec<EnumDecl>,
    #[serde(default)]
    pub transition_table: Option<TransitionTable>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnumDecl {
    pub name: String,
    pub variants: Vec<EnumVariant>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnumVariant {
    pub name: String,
    pub value: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransitionTable {
    pub state_enum: String,
    pub rows: Vec<TransitionRow>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransitionRow {
    pub from: String,
    pub to: String,
    pub allowed: bool,
}

/// CamelCase → snake_case using the Zig convention used by hyperpolymath
/// cartridges: underscore is inserted before every uppercase letter whose
/// previous character is a lowercase letter or digit, then the whole string
/// is lowercased. Examples (hand-verified against both real cartridges):
///   `ManifestLoaded` → `manifest_loaded`
///   `K9Error`        → `k9_error`
///   `SsgError`       → `ssg_error`
///   `ReadyToDeploy`  → `ready_to_deploy`
pub fn to_snake_case(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len() + 4);
    for (i, c) in chars.iter().enumerate() {
        if i > 0 && c.is_ascii_uppercase() {
            let prev = chars[i - 1];
            if prev.is_ascii_lowercase() || prev.is_ascii_digit() {
                out.push('_');
            }
        }
        out.push(c.to_ascii_lowercase());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snake_case_matches_cartridge_conventions() {
        assert_eq!(to_snake_case("Empty"), "empty");
        assert_eq!(to_snake_case("ManifestLoaded"), "manifest_loaded");
        assert_eq!(to_snake_case("ContentLoaded"), "content_loaded");
        assert_eq!(to_snake_case("K9Error"), "k9_error");
        assert_eq!(to_snake_case("SsgError"), "ssg_error");
        assert_eq!(to_snake_case("ReadyToDeploy"), "ready_to_deploy");
        assert_eq!(to_snake_case("Hugo"), "hugo");
    }
}
