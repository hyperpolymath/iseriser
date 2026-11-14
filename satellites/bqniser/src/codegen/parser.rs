// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Pattern parser for bqniser.
//
// Analyses the manifest's [[patterns]] entries to identify which array
// computation idioms are present and maps each to the appropriate BQN
// primitive rewrite. The output is a fully-populated BQNProgram ready
// for the code generation stage.

use anyhow::Result;

use crate::abi::{ArrayPattern, BQNPrimitive, BQNProgram, FFIDeclaration, pattern_from_entry};
use crate::manifest::{Manifest, SourcePattern, effective_name};

/// Analyse the manifest and produce a BQNProgram.
///
/// For each `[[patterns]]` entry:
/// 1. Convert to an ABI-layer `ArrayPattern` (determines BQN primitives).
/// 2. Generate the corresponding BQN expression string.
/// 3. Generate the FFI declaration for calling via CBQN.
pub fn analyse_manifest(manifest: &Manifest) -> Result<BQNProgram> {
    let project_name = effective_name(manifest);
    let mut patterns: Vec<ArrayPattern> = Vec::new();
    let mut ffi_declarations: Vec<FFIDeclaration> = Vec::new();

    for entry in &manifest.patterns {
        let array_pattern = pattern_from_entry(entry);
        let bqn_expr = bqn_expression_for_pattern(&entry.source_pattern, &entry.input_type);
        let c_name = format!("bqniser_{}", entry.name.replace(['-', ' '], "_"));
        let (param_types, return_type) =
            c_types_for_pattern(&entry.source_pattern, &entry.input_type, &entry.output_type);

        ffi_declarations.push(FFIDeclaration {
            c_name,
            bqn_expr,
            param_types,
            return_type,
        });

        patterns.push(array_pattern);
    }

    Ok(BQNProgram {
        project_name,
        source: String::new(), // filled by bqn_gen
        patterns,
        ffi_declarations,
        optimised: manifest.bqn.optimize,
    })
}

/// Generate the BQN expression that implements a given source pattern.
///
/// These expressions use standard BQN primitives:
/// - loop-sum:         `+´` (fold with addition)
/// - map-transform:    `F¨` (each — placeholder F for user function)
/// - filter-predicate: `P/` (replicate by boolean predicate mask)
/// - sort:             `⊏˜⍋` (select by grade-up permutation)
/// - group-by:         `⊔` (group — BQN's native group primitive)
fn bqn_expression_for_pattern(source_pattern: &SourcePattern, _input_type: &str) -> String {
    match source_pattern {
        SourcePattern::LoopSum => "+´ 𝕩".to_string(),
        SourcePattern::MapTransform => "𝕗¨ 𝕩".to_string(),
        SourcePattern::FilterPredicate => "(𝕗 𝕩) / 𝕩".to_string(),
        SourcePattern::Sort => "(⍋𝕩) ⊏ 𝕩".to_string(),
        SourcePattern::GroupBy => "𝕗 ⊔ 𝕩".to_string(),
    }
}

/// Determine C parameter types and return type for a pattern's FFI bridge.
///
/// Conventions:
/// - Array inputs are passed as `const T*` + `size_t` (pointer + length).
/// - Scalar results (e.g. sum) return the scalar type directly.
/// - Array results return via an out-pointer + length.
fn c_types_for_pattern(
    source_pattern: &SourcePattern,
    input_type: &str,
    _output_type: &str,
) -> (Vec<String>, String) {
    let c_elem = rust_type_to_c(input_type);
    match source_pattern {
        SourcePattern::LoopSum => {
            // (const double* data, size_t len) -> double
            (
                vec![format!("const {}*", c_elem), "size_t".to_string()],
                c_elem.to_string(),
            )
        }
        SourcePattern::MapTransform => {
            // (const double* data, size_t len, double* out) -> size_t
            (
                vec![
                    format!("const {}*", c_elem),
                    "size_t".to_string(),
                    format!("{}*", c_elem),
                ],
                "size_t".to_string(),
            )
        }
        SourcePattern::FilterPredicate => {
            // (const double* data, size_t len, double* out) -> size_t
            (
                vec![
                    format!("const {}*", c_elem),
                    "size_t".to_string(),
                    format!("{}*", c_elem),
                ],
                "size_t".to_string(),
            )
        }
        SourcePattern::Sort => {
            // (const double* data, size_t len, double* out) -> size_t
            (
                vec![
                    format!("const {}*", c_elem),
                    "size_t".to_string(),
                    format!("{}*", c_elem),
                ],
                "size_t".to_string(),
            )
        }
        SourcePattern::GroupBy => {
            // (const double* data, const int64_t* keys, size_t len) -> void
            // Groups are returned via callback or separate query; simplified here.
            (
                vec![
                    format!("const {}*", c_elem),
                    "const int64_t*".to_string(),
                    "size_t".to_string(),
                ],
                "void".to_string(),
            )
        }
    }
}

/// Map a Rust-style type name to the corresponding C type name.
///
/// Supports common numeric types; defaults to "double" for unknown types.
fn rust_type_to_c(rust_type: &str) -> &str {
    match rust_type {
        "f64" => "double",
        "f32" => "float",
        "i32" => "int32_t",
        "i64" => "int64_t",
        "u32" => "uint32_t",
        "u64" => "uint64_t",
        "u8" => "uint8_t",
        "i8" => "int8_t",
        "u16" => "uint16_t",
        "i16" => "int16_t",
        _ => "double", // sensible default for numeric array work
    }
}

/// Map a BQN primitive to a brief inline BQN comment.
pub fn primitive_comment(prim: BQNPrimitive) -> &'static str {
    match prim {
        BQNPrimitive::Join => "# ∾ Join — concatenate arrays",
        BQNPrimitive::Reverse => "# ⌽ Reverse — reverse element order",
        BQNPrimitive::GradeUp => "# ⍋ Grade Up — ascending sort permutation",
        BQNPrimitive::Replicate => "# / Replicate — filter by mask",
        BQNPrimitive::Select => "# ⊏ Select — index into array",
        BQNPrimitive::Reshape => "# ⥊ Reshape — change array shape",
        BQNPrimitive::Fold => "# ´ Fold — reduce with binary function",
        BQNPrimitive::Scan => "# ` Scan — cumulative fold",
        BQNPrimitive::Each => "# ¨ Each — apply function element-wise",
        BQNPrimitive::Table => "# ⌜ Table — outer product",
    }
}
