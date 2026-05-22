// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// abi-verify — diff an Idris2-derived ABI manifest against a Zig FFI
// file. Surfaces structural drift in:
//   1. enum variant integer encodings
//   2. valid state-transition relation (`isValidTransition` switch)
//
// First step of standards#92 Phase 1: replaces the cartridge's
// test-only cross-check with a CI-grade structural gate.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::abi::manifest_schema::{AbiManifest, to_snake_case, zig_variant_candidates};
use crate::abi::zig_ffi_parser::{ZigEnum, ZigFfi, parse as parse_zig};

#[derive(Debug, Clone, Serialize)]
pub struct VerifyReport {
    pub manifest: String,
    pub zig_ffi: String,
    pub cartridge: String,
    pub findings: Vec<Finding>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Finding {
    pub kind: String,
    pub detail: String,
}

impl VerifyReport {
    pub fn is_clean(&self) -> bool {
        self.findings.is_empty()
    }

    pub fn print(&self) {
        if self.is_clean() {
            println!(
                "abi-verify: OK — cartridge `{}` ABI manifest agrees with `{}`",
                self.cartridge, self.zig_ffi
            );
            return;
        }
        eprintln!(
            "abi-verify: DRIFT — cartridge `{}` ABI manifest disagrees with `{}`",
            self.cartridge, self.zig_ffi
        );
        for f in &self.findings {
            eprintln!("  [{}] {}", f.kind, f.detail);
        }
    }
}

pub fn verify_paths(manifest_path: &Path, zig_ffi_path: &Path) -> Result<VerifyReport> {
    let manifest_src = fs::read_to_string(manifest_path)
        .with_context(|| format!("reading manifest `{}`", manifest_path.display()))?;
    let manifest: AbiManifest = serde_json::from_str(&manifest_src)
        .with_context(|| format!("parsing manifest `{}`", manifest_path.display()))?;
    let zig_src = fs::read_to_string(zig_ffi_path)
        .with_context(|| format!("reading Zig FFI `{}`", zig_ffi_path.display()))?;
    let zig = parse_zig(&zig_src)
        .with_context(|| format!("parsing Zig FFI `{}`", zig_ffi_path.display()))?;
    Ok(verify(&manifest, &zig, manifest_path, zig_ffi_path))
}

pub fn verify(
    manifest: &AbiManifest,
    zig: &ZigFfi,
    manifest_path: &Path,
    zig_ffi_path: &Path,
) -> VerifyReport {
    let mut findings = Vec::new();

    // ── Enums ──────────────────────────────────────────────────────────
    let zig_enums: BTreeMap<&str, &ZigEnum> =
        zig.enums.iter().map(|e| (e.name.as_str(), e)).collect();
    for manifest_enum in &manifest.enums {
        let zig_enum = match zig_enums.get(manifest_enum.name.as_str()) {
            Some(e) => *e,
            None => {
                findings.push(Finding {
                    kind: "enum-missing-in-zig".into(),
                    detail: format!(
                        "manifest declares enum `{}` but the Zig FFI has no `pub const {} = enum(c_int)` declaration",
                        manifest_enum.name, manifest_enum.name
                    ),
                });
                continue;
            }
        };
        let mut manifest_keys: BTreeSet<String> = BTreeSet::new();
        for v in &manifest_enum.variants {
            let candidates = zig_variant_candidates(&v.name);
            // Pick the first candidate that appears in the Zig enum;
            // if none do, the variant is missing.
            let resolved: Option<(String, i64)> = candidates
                .iter()
                .find_map(|c| zig_enum.variants.get(c).map(|&val| (c.clone(), val)));
            // Record every candidate as "claimed by the manifest" so the
            // accept-by-omission check downstream doesn't flag a Zig
            // variant that the manifest legitimately covers via either
            // its primary name or its reserved-word workaround.
            for c in &candidates {
                manifest_keys.insert(c.clone());
            }
            match resolved {
                None => findings.push(Finding {
                    kind: "variant-missing-in-zig".into(),
                    detail: format!(
                        "enum `{}` variant `{}` (Zig candidates: {}) is in the manifest but absent from the Zig FFI",
                        manifest_enum.name,
                        v.name,
                        candidates
                            .iter()
                            .map(|c| format!("`{}`", c))
                            .collect::<Vec<_>>()
                            .join(" / ")
                    ),
                }),
                Some((zig_name, actual)) if actual != v.value => findings.push(Finding {
                    kind: "variant-value-mismatch".into(),
                    detail: format!(
                        "enum `{}` variant `{}` (Zig: `{}`) — manifest says {}, Zig FFI says {}",
                        manifest_enum.name, v.name, zig_name, v.value, actual
                    ),
                }),
                _ => {}
            }
        }
        for zig_variant in zig_enum.variants.keys() {
            if !manifest_keys.contains(zig_variant) {
                findings.push(Finding {
                    kind: "variant-extra-in-zig".into(),
                    detail: format!(
                        "enum `{}` has Zig variant `{}` that is not declared in the manifest",
                        manifest_enum.name, zig_variant
                    ),
                });
            }
        }
    }

    // ── Transition table ───────────────────────────────────────────────
    if let Some(tt) = &manifest.transition_table {
        let zig_tt = match &zig.transition_table {
            Some(t) => t,
            None => {
                findings.push(Finding {
                    kind: "transition-table-missing-in-zig".into(),
                    detail: format!(
                        "manifest declares transition table over `{}` but the Zig FFI has no `fn isValidTransition` switch",
                        tt.state_enum
                    ),
                });
                return finish(manifest, manifest_path, zig_ffi_path, findings);
            }
        };
        if zig_tt.state_enum != tt.state_enum {
            findings.push(Finding {
                kind: "transition-table-enum-mismatch".into(),
                detail: format!(
                    "manifest transition table is over `{}` but Zig `isValidTransition` is over `{}`",
                    tt.state_enum, zig_tt.state_enum
                ),
            });
        }
        if zig_tt.arms.contains_key("_else") {
            findings.push(Finding {
                kind: "transition-table-uses-else".into(),
                detail: "Zig `isValidTransition` uses an `else =>` arm; the gate cannot certify a non-exhaustive switch — replace with explicit arms for every state".into(),
            });
        }
        // Build the accepted-pair set from Zig.
        let mut zig_pairs: BTreeSet<(String, String)> = BTreeSet::new();
        for (from, tos) in &zig_tt.arms {
            if from == "_else" {
                continue;
            }
            for to in tos {
                zig_pairs.insert((from.clone(), to.clone()));
            }
        }
        // Build the accepted-pair set from the manifest (only `allowed: true`
        // counts; `allowed: false` is the manifest's way of pinning a
        // safety invariant — see e.g. `ContentLoaded → Previewing` in
        // ssg-mcp). Variants are resolved through `zig_variant_candidates`
        // so a Zig-reserved-word-renamed variant (e.g. Error → err)
        // matches its manifest entry.
        let resolve = |idris_name: &str| -> String {
            for c in zig_variant_candidates(idris_name) {
                if zig_pairs.iter().any(|(f, t)| f == &c || t == &c) {
                    return c;
                }
            }
            to_snake_case(idris_name)
        };
        let mut manifest_allowed: BTreeSet<(String, String)> = BTreeSet::new();
        for row in &tt.rows {
            let f = resolve(&row.from);
            let t = resolve(&row.to);
            if row.allowed {
                manifest_allowed.insert((f, t));
            } else if zig_pairs.contains(&(f.clone(), t.clone())) {
                findings.push(Finding {
                    kind: "transition-forbidden-but-accepted".into(),
                    detail: format!(
                        "manifest forbids `{} → {}` but Zig `isValidTransition` accepts it",
                        row.from, row.to
                    ),
                });
            }
        }
        for pair in &manifest_allowed {
            if !zig_pairs.contains(pair) {
                findings.push(Finding {
                    kind: "transition-allowed-but-rejected".into(),
                    detail: format!(
                        "manifest allows `{} → {}` but Zig `isValidTransition` rejects it",
                        pair.0, pair.1
                    ),
                });
            }
        }
        for pair in &zig_pairs {
            if !manifest_allowed.contains(pair) {
                // Only flag pairs Zig accepts that the manifest did not
                // explicitly list — accept-by-omission is itself drift.
                let listed_as_forbidden = tt.rows.iter().any(|r| {
                    !r.allowed
                        && zig_variant_candidates(&r.from).contains(&pair.0)
                        && zig_variant_candidates(&r.to).contains(&pair.1)
                });
                if !listed_as_forbidden {
                    findings.push(Finding {
                        kind: "transition-accepted-but-undeclared".into(),
                        detail: format!(
                            "Zig accepts `{} → {}` but the manifest neither allows nor forbids it — accept-by-omission is drift",
                            pair.0, pair.1
                        ),
                    });
                }
            }
        }
    }

    finish(manifest, manifest_path, zig_ffi_path, findings)
}

fn finish(
    manifest: &AbiManifest,
    manifest_path: &Path,
    zig_ffi_path: &Path,
    findings: Vec<Finding>,
) -> VerifyReport {
    VerifyReport {
        manifest: manifest_path.display().to_string(),
        zig_ffi: zig_ffi_path.display().to_string(),
        cartridge: manifest.cartridge.clone(),
        findings,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::manifest_schema::{EnumDecl, EnumVariant, TransitionRow, TransitionTable};
    use crate::abi::zig_ffi_parser::parse as parse_zig;

    fn make_manifest() -> AbiManifest {
        AbiManifest {
            schema_version: "1.0".into(),
            cartridge: "demo".into(),
            source_idris: "Safe.idr".into(),
            enums: vec![EnumDecl {
                name: "S".into(),
                variants: vec![
                    EnumVariant { name: "Empty".into(), value: 0 },
                    EnumVariant { name: "Ready".into(), value: 1 },
                    EnumVariant { name: "Done".into(), value: 2 },
                ],
            }],
            transition_table: Some(TransitionTable {
                state_enum: "S".into(),
                rows: vec![
                    TransitionRow { from: "Empty".into(), to: "Ready".into(), allowed: true },
                    TransitionRow { from: "Ready".into(), to: "Done".into(), allowed: true },
                    TransitionRow { from: "Done".into(), to: "Empty".into(), allowed: true },
                    TransitionRow { from: "Empty".into(), to: "Done".into(), allowed: false },
                ],
            }),
        }
    }

    fn make_zig() -> ZigFfi {
        let src = r#"
            pub const S = enum(c_int) { empty = 0, ready = 1, done = 2 };
            fn isValidTransition(from: S, to: S) bool {
                return switch (from) {
                    .empty => to == .ready,
                    .ready => to == .done,
                    .done => to == .empty,
                };
            }
        "#;
        parse_zig(src).unwrap()
    }

    #[test]
    fn clean_match_passes() {
        let m = make_manifest();
        let z = make_zig();
        let report = verify(&m, &z, Path::new("m.json"), Path::new("z.zig"));
        assert!(report.is_clean(), "{:#?}", report.findings);
    }

    #[test]
    fn detects_value_drift() {
        let src = r#"
            pub const S = enum(c_int) { empty = 0, ready = 99, done = 2 };
            fn isValidTransition(from: S, to: S) bool {
                return switch (from) {
                    .empty => to == .ready,
                    .ready => to == .done,
                    .done => to == .empty,
                };
            }
        "#;
        let z = parse_zig(src).unwrap();
        let report = verify(&make_manifest(), &z, Path::new("m.json"), Path::new("z.zig"));
        assert!(report.findings.iter().any(|f| f.kind == "variant-value-mismatch"));
    }

    #[test]
    fn detects_forbidden_transition_accepted() {
        let src = r#"
            pub const S = enum(c_int) { empty = 0, ready = 1, done = 2 };
            fn isValidTransition(from: S, to: S) bool {
                return switch (from) {
                    .empty => to == .ready or to == .done,
                    .ready => to == .done,
                    .done => to == .empty,
                };
            }
        "#;
        let z = parse_zig(src).unwrap();
        let report = verify(&make_manifest(), &z, Path::new("m.json"), Path::new("z.zig"));
        assert!(
            report.findings.iter().any(|f| f.kind == "transition-forbidden-but-accepted"),
            "{:#?}",
            report.findings
        );
    }

    #[test]
    fn detects_undeclared_transition() {
        let src = r#"
            pub const S = enum(c_int) { empty = 0, ready = 1, done = 2 };
            fn isValidTransition(from: S, to: S) bool {
                return switch (from) {
                    .empty => to == .ready,
                    .ready => to == .done or to == .ready,
                    .done => to == .empty,
                };
            }
        "#;
        let z = parse_zig(src).unwrap();
        let report = verify(&make_manifest(), &z, Path::new("m.json"), Path::new("z.zig"));
        assert!(
            report.findings.iter().any(|f| f.kind == "transition-accepted-but-undeclared"),
            "{:#?}",
            report.findings
        );
    }
}
