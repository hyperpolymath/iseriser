// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for bqniser Phase 1.
//
// Tests cover:
// 1. Manifest parsing with [project], [[patterns]], and [bqn] sections
// 2. Manifest validation rules
// 3. Pattern analysis (parser -> ABI types)
// 4. BQN code generation (.bqn output)
// 5. FFI bridge generation (C header + Zig)
// 6. End-to-end generate pipeline
// 7. ABI primitive properties
// 8. Example manifest (examples/array-ops/)

use bqniser::abi::{ArrayPatternKind, BQNPrimitive, pattern_from_entry, source_pattern_to_kind};
use bqniser::codegen::bqn_gen::generate_bqn;
use bqniser::codegen::ffi_gen::generate_ffi;
use bqniser::codegen::parser::analyse_manifest;
use bqniser::manifest::{
    BqnConfig, Manifest, PatternEntry, SourcePattern, effective_name, load_manifest, validate,
};

/// Helper: build a minimal valid manifest in-memory.
fn sample_manifest() -> Manifest {
    Manifest {
        workload: Default::default(),
        data: Default::default(),
        options: Default::default(),
        project: bqniser::manifest::ProjectConfig {
            name: "test-project".to_string(),
            version: "0.1.0".to_string(),
            description: "Test project for bqniser".to_string(),
        },
        patterns: vec![
            PatternEntry {
                name: "sum-values".to_string(),
                source_pattern: SourcePattern::LoopSum,
                input_type: "f64".to_string(),
                output_type: "f64".to_string(),
            },
            PatternEntry {
                name: "double-each".to_string(),
                source_pattern: SourcePattern::MapTransform,
                input_type: "f64".to_string(),
                output_type: "f64".to_string(),
            },
            PatternEntry {
                name: "filter-positive".to_string(),
                source_pattern: SourcePattern::FilterPredicate,
                input_type: "f64".to_string(),
                output_type: "Vec<f64>".to_string(),
            },
            PatternEntry {
                name: "sort-asc".to_string(),
                source_pattern: SourcePattern::Sort,
                input_type: "i32".to_string(),
                output_type: "Vec<i32>".to_string(),
            },
            PatternEntry {
                name: "group-items".to_string(),
                source_pattern: SourcePattern::GroupBy,
                input_type: "f64".to_string(),
                output_type: "Vec<Vec<f64>>".to_string(),
            },
        ],
        bqn: BqnConfig {
            backend: "cbqn".to_string(),
            optimize: true,
        },
    }
}

// -----------------------------------------------------------------------
// Test 1: Manifest parsing from TOML string
// -----------------------------------------------------------------------

#[test]
fn test_manifest_parse_full() {
    let toml_str = r#"
[project]
name = "parse-test"
version = "1.0.0"
description = "Parsing test"

[[patterns]]
name = "my-sum"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[[patterns]]
name = "my-filter"
source-pattern = "filter-predicate"
input-type = "i32"
output-type = "Vec<i32>"

[bqn]
backend = "cbqn"
optimize = false
"#;

    let manifest: Manifest = toml::from_str(toml_str).expect("Failed to parse manifest");

    assert_eq!(manifest.project.name, "parse-test");
    assert_eq!(manifest.project.version, "1.0.0");
    assert_eq!(manifest.patterns.len(), 2);
    assert_eq!(manifest.patterns[0].name, "my-sum");
    assert_eq!(manifest.patterns[0].source_pattern, SourcePattern::LoopSum);
    assert_eq!(
        manifest.patterns[1].source_pattern,
        SourcePattern::FilterPredicate
    );
    assert_eq!(manifest.bqn.backend, "cbqn");
    assert!(!manifest.bqn.optimize);
}

// -----------------------------------------------------------------------
// Test 2: Manifest validation
// -----------------------------------------------------------------------

#[test]
fn test_manifest_validation_valid() {
    let m = sample_manifest();
    assert!(
        validate(&m).is_ok(),
        "Valid manifest should pass validation"
    );
}

#[test]
fn test_manifest_validation_no_name() {
    let mut m = sample_manifest();
    m.project.name = String::new();
    m.workload.name = String::new();
    let result = validate(&m);
    assert!(result.is_err(), "Manifest without name should fail");
    assert!(
        result.unwrap_err().to_string().contains("name"),
        "Error should mention 'name'"
    );
}

#[test]
fn test_manifest_validation_bad_backend() {
    let mut m = sample_manifest();
    m.bqn.backend = "dzaima".to_string();
    let result = validate(&m);
    assert!(result.is_err(), "Unsupported backend should fail");
    assert!(
        result.unwrap_err().to_string().contains("dzaima"),
        "Error should mention the unsupported backend"
    );
}

#[test]
fn test_manifest_validation_empty_pattern_name() {
    let mut m = sample_manifest();
    m.patterns[0].name = String::new();
    let result = validate(&m);
    assert!(result.is_err(), "Pattern without name should fail");
}

// -----------------------------------------------------------------------
// Test 3: Pattern analysis (parser)
// -----------------------------------------------------------------------

#[test]
fn test_parser_analyse_manifest() {
    let m = sample_manifest();
    let program = analyse_manifest(&m).expect("Analysis should succeed");

    assert_eq!(program.project_name, "test-project");
    assert_eq!(program.patterns.len(), 5);
    assert!(program.optimised);

    // Check that each pattern has the right kind.
    assert_eq!(program.patterns[0].kind, ArrayPatternKind::LoopSum);
    assert_eq!(program.patterns[1].kind, ArrayPatternKind::MapTransform);
    assert_eq!(program.patterns[2].kind, ArrayPatternKind::FilterPredicate);
    assert_eq!(program.patterns[3].kind, ArrayPatternKind::Sort);
    assert_eq!(program.patterns[4].kind, ArrayPatternKind::GroupBy);

    // Check FFI declarations match.
    assert_eq!(program.ffi_declarations.len(), 5);
    assert_eq!(program.ffi_declarations[0].c_name, "bqniser_sum_values");
    assert_eq!(program.ffi_declarations[3].c_name, "bqniser_sort_asc");
}

// -----------------------------------------------------------------------
// Test 4: BQN code generation
// -----------------------------------------------------------------------

#[test]
fn test_bqn_generation() {
    let m = sample_manifest();
    let program = analyse_manifest(&m).unwrap();
    let bqn_source = generate_bqn(&program).expect("BQN generation should succeed");

    // The output should contain BQN primitives.
    assert!(
        bqn_source.contains("+\u{00b4}"),
        "BQN source should contain +´ (fold with addition)"
    );
    assert!(
        bqn_source.contains('\u{00a8}'),
        "BQN source should contain ¨ (each)"
    );
    assert!(
        bqn_source.contains('\u{234b}'),
        "BQN source should contain ⍋ (grade up)"
    );
    assert!(
        bqn_source.contains('\u{228f}'),
        "BQN source should contain ⊏ (select)"
    );
    assert!(
        bqn_source.contains('/'),
        "BQN source should contain / (replicate)"
    );

    // Should mention the project name.
    assert!(bqn_source.contains("test-project"));

    // Should have SPDX header.
    assert!(bqn_source.contains("MPL-2.0"));

    // Should have an export namespace.
    assert!(bqn_source.contains("bqniser"));
}

// -----------------------------------------------------------------------
// Test 5: FFI bridge generation
// -----------------------------------------------------------------------

#[test]
fn test_ffi_generation() {
    let m = sample_manifest();
    let program = analyse_manifest(&m).unwrap();
    let (header, zig) = generate_ffi(&program).expect("FFI generation should succeed");

    // C header checks.
    assert!(header.contains("#ifndef BQNISER_FFI_H"));
    assert!(header.contains("bqniser_init"));
    assert!(header.contains("bqniser_cleanup"));
    assert!(header.contains("bqniser_sum_values"));
    assert!(header.contains("bqniser_sort_asc"));
    assert!(header.contains("const double*"));
    assert!(header.contains("size_t"));

    // Zig implementation checks.
    assert!(zig.contains("MPL-2.0"));
    assert!(zig.contains("cbqn.h"));
    assert!(zig.contains("bqniser_init"));
    assert!(zig.contains("bqniser_cleanup"));
    assert!(zig.contains("bqn_eval"));
    assert!(zig.contains("bqniser_sum_values"));
}

// -----------------------------------------------------------------------
// Test 6: End-to-end generate pipeline (file I/O)
// -----------------------------------------------------------------------

#[test]
fn test_end_to_end_generate() {
    let dir = tempfile::tempdir().expect("Failed to create temp dir");
    let manifest_path = dir.path().join("bqniser.toml");
    let output_dir = dir.path().join("output");

    // Write a manifest.
    let toml_content = r#"
[project]
name = "e2e-test"
version = "0.1.0"
description = "End-to-end test"

[[patterns]]
name = "total"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[[patterns]]
name = "reverse-sort"
source-pattern = "sort"
input-type = "i32"
output-type = "Vec<i32>"

[bqn]
backend = "cbqn"
optimize = true
"#;
    std::fs::write(&manifest_path, toml_content).unwrap();

    // Run the full pipeline.
    let result = bqniser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    );
    assert!(
        result.is_ok(),
        "Generate pipeline should succeed: {:?}",
        result.err()
    );

    // Check output files exist.
    assert!(
        output_dir.join("e2e-test.bqn").exists(),
        ".bqn file should exist"
    );
    assert!(
        output_dir.join("bqniser_ffi.h").exists(),
        "C header should exist"
    );
    assert!(
        output_dir.join("bqniser_ffi.zig").exists(),
        "Zig FFI should exist"
    );

    // Check .bqn content.
    let bqn = std::fs::read_to_string(output_dir.join("e2e-test.bqn")).unwrap();
    assert!(bqn.contains("e2e-test"));
    assert!(bqn.contains("+\u{00b4}")); // +´

    // Check header content.
    let header = std::fs::read_to_string(output_dir.join("bqniser_ffi.h")).unwrap();
    assert!(header.contains("bqniser_total"));
    assert!(header.contains("bqniser_reverse_sort"));
}

// -----------------------------------------------------------------------
// Test 7: ABI primitive properties
// -----------------------------------------------------------------------

#[test]
fn test_bqn_primitive_properties() {
    // Glyphs.
    assert_eq!(BQNPrimitive::Join.glyph(), "\u{223e}");
    assert_eq!(BQNPrimitive::Reverse.glyph(), "\u{233d}");
    assert_eq!(BQNPrimitive::GradeUp.glyph(), "\u{234b}");
    assert_eq!(BQNPrimitive::Replicate.glyph(), "/");
    assert_eq!(BQNPrimitive::Select.glyph(), "\u{228f}");
    assert_eq!(BQNPrimitive::Reshape.glyph(), "\u{294a}");
    assert_eq!(BQNPrimitive::Fold.glyph(), "\u{00b4}");
    assert_eq!(BQNPrimitive::Scan.glyph(), "`");
    assert_eq!(BQNPrimitive::Each.glyph(), "\u{00a8}");
    assert_eq!(BQNPrimitive::Table.glyph(), "\u{231c}");

    // Labels.
    assert_eq!(BQNPrimitive::Join.label(), "Join");
    assert_eq!(BQNPrimitive::Fold.label(), "Fold");

    // Arities.
    assert_eq!(BQNPrimitive::Join.arity(), 2);
    assert_eq!(BQNPrimitive::Reverse.arity(), 1);
    assert_eq!(BQNPrimitive::GradeUp.arity(), 1);
    assert_eq!(BQNPrimitive::Replicate.arity(), 2);
    assert_eq!(BQNPrimitive::Select.arity(), 2);
    assert_eq!(BQNPrimitive::Reshape.arity(), 2);
    assert_eq!(BQNPrimitive::Fold.arity(), 1);
    assert_eq!(BQNPrimitive::Scan.arity(), 1);
    assert_eq!(BQNPrimitive::Each.arity(), 1);
    assert_eq!(BQNPrimitive::Table.arity(), 2);
}

// -----------------------------------------------------------------------
// Test 8: Pattern kind -> primitive mapping
// -----------------------------------------------------------------------

#[test]
fn test_pattern_kind_primitives() {
    let prims = ArrayPatternKind::LoopSum.primary_primitives();
    assert_eq!(prims, vec![BQNPrimitive::Fold]);

    let prims = ArrayPatternKind::MapTransform.primary_primitives();
    assert_eq!(prims, vec![BQNPrimitive::Each]);

    let prims = ArrayPatternKind::FilterPredicate.primary_primitives();
    assert_eq!(prims, vec![BQNPrimitive::Replicate]);

    let prims = ArrayPatternKind::Sort.primary_primitives();
    assert_eq!(prims, vec![BQNPrimitive::GradeUp, BQNPrimitive::Select]);

    let prims = ArrayPatternKind::GroupBy.primary_primitives();
    assert_eq!(prims, vec![BQNPrimitive::Replicate, BQNPrimitive::Each]);
}

// -----------------------------------------------------------------------
// Test 9: Source pattern to ABI kind conversion
// -----------------------------------------------------------------------

#[test]
fn test_source_pattern_to_kind() {
    assert_eq!(
        source_pattern_to_kind(&SourcePattern::LoopSum),
        ArrayPatternKind::LoopSum
    );
    assert_eq!(
        source_pattern_to_kind(&SourcePattern::MapTransform),
        ArrayPatternKind::MapTransform
    );
    assert_eq!(
        source_pattern_to_kind(&SourcePattern::FilterPredicate),
        ArrayPatternKind::FilterPredicate
    );
    assert_eq!(
        source_pattern_to_kind(&SourcePattern::Sort),
        ArrayPatternKind::Sort
    );
    assert_eq!(
        source_pattern_to_kind(&SourcePattern::GroupBy),
        ArrayPatternKind::GroupBy
    );
}

// -----------------------------------------------------------------------
// Test 10: Pattern from manifest entry
// -----------------------------------------------------------------------

#[test]
fn test_pattern_from_entry() {
    let entry = PatternEntry {
        name: "my-sort".to_string(),
        source_pattern: SourcePattern::Sort,
        input_type: "i64".to_string(),
        output_type: "Vec<i64>".to_string(),
    };
    let pat = pattern_from_entry(&entry);
    assert_eq!(pat.name, "my-sort");
    assert_eq!(pat.kind, ArrayPatternKind::Sort);
    assert_eq!(
        pat.primitives,
        vec![BQNPrimitive::GradeUp, BQNPrimitive::Select]
    );
    assert_eq!(pat.input_type, "i64");
    assert_eq!(pat.output_type, "Vec<i64>");
}

// -----------------------------------------------------------------------
// Test 11: Effective name (project vs workload fallback)
// -----------------------------------------------------------------------

#[test]
fn test_effective_name_prefers_project() {
    let mut m = sample_manifest();
    m.project.name = "project-name".to_string();
    m.workload.name = "workload-name".to_string();
    assert_eq!(effective_name(&m), "project-name");
}

#[test]
fn test_effective_name_falls_back_to_workload() {
    let mut m = sample_manifest();
    m.project.name = String::new();
    m.workload.name = "fallback-name".to_string();
    assert_eq!(effective_name(&m), "fallback-name");
}

// -----------------------------------------------------------------------
// Test 12: Example manifest loads and generates
// -----------------------------------------------------------------------

#[test]
fn test_example_array_ops_manifest() {
    let manifest_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/examples/array-ops/bqniser.toml"
    );
    let m = load_manifest(manifest_path).expect("Example manifest should load");
    assert!(validate(&m).is_ok(), "Example manifest should be valid");
    assert_eq!(m.project.name, "array-ops-example");
    assert_eq!(m.patterns.len(), 5);

    // Generate into a temp dir.
    let dir = tempfile::tempdir().unwrap();
    let result = bqniser::generate(manifest_path, dir.path().to_str().unwrap());
    assert!(
        result.is_ok(),
        "Example generation should succeed: {:?}",
        result.err()
    );
}

// =======================================================================
// POINT-TO-POINT TESTS: Each pattern generates correct BQN primitives
// =======================================================================

/// Helper: build a manifest with a single pattern for focused testing.
fn single_pattern_manifest(
    name: &str,
    pattern: SourcePattern,
    in_ty: &str,
    out_ty: &str,
) -> Manifest {
    Manifest {
        workload: Default::default(),
        data: Default::default(),
        options: Default::default(),
        project: bqniser::manifest::ProjectConfig {
            name: "point-test".to_string(),
            version: "0.1.0".to_string(),
            description: "Point-to-point test".to_string(),
        },
        patterns: vec![PatternEntry {
            name: name.to_string(),
            source_pattern: pattern,
            input_type: in_ty.to_string(),
            output_type: out_ty.to_string(),
        }],
        bqn: BqnConfig {
            backend: "cbqn".to_string(),
            optimize: true,
        },
    }
}

// -----------------------------------------------------------------------
// Test 13: LoopSum generates +´ (fold with addition)
// -----------------------------------------------------------------------

#[test]
fn test_point_loop_sum_generates_fold() {
    let m = single_pattern_manifest("total", SourcePattern::LoopSum, "f64", "f64");
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    // Must contain +´ — the fold modifier applied to addition.
    assert!(
        bqn.contains("+\u{00B4}"),
        "LoopSum must generate +´ (fold): got:\n{}",
        bqn
    );
    // Must NOT contain primitives from other patterns.
    assert!(
        !bqn.contains('\u{2294}'),
        "LoopSum must not contain ⊔ (group)"
    );
    // FFI declaration should use the correct C name.
    let (header, _) = generate_ffi(&program).unwrap();
    assert!(
        header.contains("bqniser_total"),
        "FFI should declare bqniser_total"
    );
    // LoopSum returns a scalar — return type should be 'double', not 'size_t'.
    assert!(
        header.contains("double bqniser_total"),
        "LoopSum FFI return type should be scalar double"
    );
}

// -----------------------------------------------------------------------
// Test 14: MapTransform generates ¨ (each)
// -----------------------------------------------------------------------

#[test]
fn test_point_map_transform_generates_each() {
    let m = single_pattern_manifest("double-it", SourcePattern::MapTransform, "f64", "f64");
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    assert!(
        bqn.contains('\u{00A8}'),
        "MapTransform must generate ¨ (each): got:\n{}",
        bqn
    );
    // The BQN expression should reference 𝕗 (operand function).
    assert!(
        bqn.contains('\u{1D557}'),
        "MapTransform body should reference 𝕗 (modifier operand)"
    );
}

// -----------------------------------------------------------------------
// Test 15: FilterPredicate generates / (replicate)
// -----------------------------------------------------------------------

#[test]
fn test_point_filter_predicate_generates_replicate() {
    let m = single_pattern_manifest(
        "keep-positive",
        SourcePattern::FilterPredicate,
        "f64",
        "Vec<f64>",
    );
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    // The body should contain / (replicate) in the filter context.
    assert!(
        bqn.contains("/\u{1D569}"),
        "FilterPredicate must generate /𝕩 (replicate): got:\n{}",
        bqn
    );
    // FFI should return size_t (array result).
    let (header, _) = generate_ffi(&program).unwrap();
    assert!(
        header.contains("size_t bqniser_keep_positive"),
        "FilterPredicate FFI return type should be size_t"
    );
}

// -----------------------------------------------------------------------
// Test 16: Sort generates ⍋ (grade up) and ⊏ (select)
// -----------------------------------------------------------------------

#[test]
fn test_point_sort_generates_grade_select() {
    let m = single_pattern_manifest("sort-data", SourcePattern::Sort, "i32", "Vec<i32>");
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    assert!(
        bqn.contains('\u{234B}'),
        "Sort must generate ⍋ (grade up): got:\n{}",
        bqn
    );
    assert!(
        bqn.contains('\u{228F}'),
        "Sort must generate ⊏ (select): got:\n{}",
        bqn
    );
    // Sort pattern should use both primitives together.
    let pat = &program.patterns[0];
    assert_eq!(pat.primitives.len(), 2, "Sort needs exactly 2 primitives");
    assert_eq!(pat.primitives[0], BQNPrimitive::GradeUp);
    assert_eq!(pat.primitives[1], BQNPrimitive::Select);
}

// -----------------------------------------------------------------------
// Test 17: GroupBy generates ⊔ (group)
// -----------------------------------------------------------------------

#[test]
fn test_point_group_by_generates_group() {
    let m = single_pattern_manifest("cluster", SourcePattern::GroupBy, "f64", "Vec<Vec<f64>>");
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    // ⊔ = U+2294 (BQN group primitive).
    assert!(
        bqn.contains('\u{2294}'),
        "GroupBy must generate ⊔ (group): got:\n{}",
        bqn
    );
    // GroupBy FFI takes a keys parameter (const int64_t*).
    let (header, _) = generate_ffi(&program).unwrap();
    assert!(
        header.contains("const int64_t*"),
        "GroupBy FFI should include int64_t* keys parameter"
    );
    // GroupBy returns void (results via callback).
    assert!(
        header.contains("void bqniser_cluster"),
        "GroupBy FFI return type should be void"
    );
}

// =======================================================================
// END-TO-END TESTS: Full pipeline from manifest to files
// =======================================================================

// -----------------------------------------------------------------------
// Test 18: E2E pipeline — all five patterns together
// -----------------------------------------------------------------------

#[test]
fn test_e2e_all_five_patterns() {
    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("bqniser.toml");
    let output_dir = dir.path().join("out");

    let toml_content = r#"
[project]
name = "full-pipeline"
version = "2.0.0"
description = "All five patterns"

[[patterns]]
name = "accumulate"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[[patterns]]
name = "scale"
source-pattern = "map-transform"
input-type = "f64"
output-type = "f64"

[[patterns]]
name = "pick-valid"
source-pattern = "filter-predicate"
input-type = "f64"
output-type = "Vec<f64>"

[[patterns]]
name = "rank"
source-pattern = "sort"
input-type = "i32"
output-type = "Vec<i32>"

[[patterns]]
name = "bucket"
source-pattern = "group-by"
input-type = "f64"
output-type = "Vec<Vec<f64>>"

[bqn]
backend = "cbqn"
optimize = true
"#;
    std::fs::write(&manifest_path, toml_content).unwrap();

    let result = bqniser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    );
    assert!(result.is_ok(), "Full pipeline: {:?}", result.err());

    // All three output files must exist.
    assert!(output_dir.join("full-pipeline.bqn").exists());
    assert!(output_dir.join("bqniser_ffi.h").exists());
    assert!(output_dir.join("bqniser_ffi.zig").exists());

    // BQN file must contain all five primitives.
    let bqn = std::fs::read_to_string(output_dir.join("full-pipeline.bqn")).unwrap();
    assert!(bqn.contains("+\u{00B4}"), "Missing +´ (fold)");
    assert!(bqn.contains('\u{00A8}'), "Missing ¨ (each)");
    assert!(bqn.contains('/'), "Missing / (replicate)");
    assert!(bqn.contains('\u{234B}'), "Missing ⍋ (grade up)");
    assert!(bqn.contains('\u{2294}'), "Missing ⊔ (group)");

    // C header must declare all five functions + lifecycle.
    let header = std::fs::read_to_string(output_dir.join("bqniser_ffi.h")).unwrap();
    assert!(header.contains("bqniser_accumulate"));
    assert!(header.contains("bqniser_scale"));
    assert!(header.contains("bqniser_pick_valid"));
    assert!(header.contains("bqniser_rank"));
    assert!(header.contains("bqniser_bucket"));
    assert!(header.contains("bqniser_init"));
    assert!(header.contains("bqniser_cleanup"));

    // Zig file must reference all five function exports.
    let zig = std::fs::read_to_string(output_dir.join("bqniser_ffi.zig")).unwrap();
    assert!(zig.contains("bqniser_accumulate"));
    assert!(zig.contains("bqniser_scale"));
    assert!(zig.contains("bqniser_pick_valid"));
    assert!(zig.contains("bqniser_rank"));
    assert!(zig.contains("bqniser_bucket"));
}

// -----------------------------------------------------------------------
// Test 19: E2E pipeline — single pattern produces minimal output
// -----------------------------------------------------------------------

#[test]
fn test_e2e_single_pattern_minimal() {
    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("bqniser.toml");
    let output_dir = dir.path().join("out");

    let toml_content = r#"
[project]
name = "minimal"
version = "0.0.1"
description = "Just one pattern"

[[patterns]]
name = "add-up"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[bqn]
backend = "cbqn"
optimize = false
"#;
    std::fs::write(&manifest_path, toml_content).unwrap();

    let result = bqniser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    );
    assert!(result.is_ok(), "Minimal pipeline: {:?}", result.err());

    let bqn = std::fs::read_to_string(output_dir.join("minimal.bqn")).unwrap();
    // With optimize=false, the BQN source should not mention "Optimisation: enabled".
    assert!(
        !bqn.contains("Optimisation: enabled"),
        "optimize=false should not emit optimisation comment"
    );
    assert!(
        bqn.contains("minimal"),
        "BQN file should reference project name"
    );
}

// -----------------------------------------------------------------------
// Test 20: E2E — output directory creation is idempotent
// -----------------------------------------------------------------------

#[test]
fn test_e2e_creates_output_dir() {
    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("bqniser.toml");
    // Deeply nested output dir that does not yet exist.
    let output_dir = dir.path().join("a").join("b").join("c");

    let toml_content = r#"
[project]
name = "nested-dir"
version = "0.1.0"
description = "Tests nested output dir creation"

[[patterns]]
name = "total"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[bqn]
backend = "cbqn"
optimize = true
"#;
    std::fs::write(&manifest_path, toml_content).unwrap();

    let result = bqniser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    );
    assert!(
        result.is_ok(),
        "Should create nested output dirs: {:?}",
        result.err()
    );
    assert!(output_dir.join("nested-dir.bqn").exists());
}

// =======================================================================
// EDGE CASE TESTS
// =======================================================================

// -----------------------------------------------------------------------
// Test 21: Empty patterns list
// -----------------------------------------------------------------------

#[test]
fn test_edge_empty_patterns_list() {
    let m = Manifest {
        workload: Default::default(),
        data: Default::default(),
        options: Default::default(),
        project: bqniser::manifest::ProjectConfig {
            name: "empty-patterns".to_string(),
            version: "0.1.0".to_string(),
            description: "No patterns".to_string(),
        },
        patterns: vec![],
        bqn: BqnConfig {
            backend: "cbqn".to_string(),
            optimize: true,
        },
    };

    // Validation should pass — zero patterns is valid.
    assert!(validate(&m).is_ok(), "Empty patterns list should be valid");

    // Analysis should produce an empty program.
    let program = analyse_manifest(&m).unwrap();
    assert_eq!(program.patterns.len(), 0);
    assert_eq!(program.ffi_declarations.len(), 0);

    // BQN generation with no patterns should still produce valid output.
    let bqn = generate_bqn(&program).unwrap();
    assert!(
        bqn.contains("empty-patterns"),
        "Header should still have project name"
    );
    // Should NOT have the export namespace when there are no patterns.
    assert!(
        !bqn.contains("bqniser \u{2190} {"),
        "Empty patterns should not emit export namespace"
    );

    // FFI generation with no patterns should still produce lifecycle functions.
    let (header, zig) = generate_ffi(&program).unwrap();
    assert!(header.contains("bqniser_init"));
    assert!(header.contains("bqniser_cleanup"));
    assert!(zig.contains("bqniser_init"));
    assert!(zig.contains("bqniser_cleanup"));
}

// -----------------------------------------------------------------------
// Test 22: Duplicate pattern names (validation does not reject, but FFI
// names should differ if the source names differ — this tests same name)
// -----------------------------------------------------------------------

#[test]
fn test_edge_duplicate_pattern_names() {
    let m = Manifest {
        workload: Default::default(),
        data: Default::default(),
        options: Default::default(),
        project: bqniser::manifest::ProjectConfig {
            name: "dup-test".to_string(),
            version: "0.1.0".to_string(),
            description: "Duplicate pattern names".to_string(),
        },
        patterns: vec![
            PatternEntry {
                name: "compute".to_string(),
                source_pattern: SourcePattern::LoopSum,
                input_type: "f64".to_string(),
                output_type: "f64".to_string(),
            },
            PatternEntry {
                name: "compute".to_string(),
                source_pattern: SourcePattern::MapTransform,
                input_type: "f64".to_string(),
                output_type: "f64".to_string(),
            },
        ],
        bqn: BqnConfig {
            backend: "cbqn".to_string(),
            optimize: true,
        },
    };

    // Validation currently passes with duplicate names.
    assert!(validate(&m).is_ok());

    // Both FFI declarations get the same C name — a potential collision.
    let program = analyse_manifest(&m).unwrap();
    assert_eq!(program.ffi_declarations.len(), 2);
    assert_eq!(program.ffi_declarations[0].c_name, "bqniser_compute");
    assert_eq!(program.ffi_declarations[1].c_name, "bqniser_compute");
}

// -----------------------------------------------------------------------
// Test 23: Invalid pattern type in TOML (deserialization error)
// -----------------------------------------------------------------------

#[test]
fn test_edge_invalid_pattern_type_toml() {
    let toml_str = r#"
[project]
name = "invalid-pat"
version = "0.1.0"
description = "Bad pattern type"

[[patterns]]
name = "oops"
source-pattern = "nonexistent-pattern"
input-type = "f64"
output-type = "f64"

[bqn]
backend = "cbqn"
optimize = true
"#;

    let result: Result<Manifest, _> = toml::from_str(toml_str);
    assert!(
        result.is_err(),
        "Invalid source-pattern variant should fail deserialization"
    );
    let err_msg = result.unwrap_err().to_string();
    assert!(
        err_msg.contains("nonexistent-pattern") || err_msg.contains("unknown variant"),
        "Error should mention the bad variant: {}",
        err_msg
    );
}

// -----------------------------------------------------------------------
// Test 24: Missing required field — input-type
// -----------------------------------------------------------------------

#[test]
fn test_edge_missing_input_type() {
    let mut m = sample_manifest();
    m.patterns[0].input_type = String::new();
    let result = validate(&m);
    assert!(result.is_err(), "Empty input-type should fail validation");
    assert!(
        result.unwrap_err().to_string().contains("input-type"),
        "Error should mention input-type"
    );
}

// -----------------------------------------------------------------------
// Test 25: Missing required field — output-type
// -----------------------------------------------------------------------

#[test]
fn test_edge_missing_output_type() {
    let mut m = sample_manifest();
    m.patterns[0].output_type = String::new();
    let result = validate(&m);
    assert!(result.is_err(), "Empty output-type should fail validation");
    assert!(
        result.unwrap_err().to_string().contains("output-type"),
        "Error should mention output-type"
    );
}

// -----------------------------------------------------------------------
// Test 26: Load manifest from nonexistent file
// -----------------------------------------------------------------------

#[test]
fn test_edge_load_nonexistent_manifest() {
    let result = load_manifest("/tmp/bqniser_nonexistent_12345.toml");
    assert!(result.is_err(), "Loading nonexistent file should fail");
}

// -----------------------------------------------------------------------
// Test 27: Manifest with only legacy workload name
// -----------------------------------------------------------------------

#[test]
fn test_edge_legacy_workload_only() {
    let toml_str = r#"
[workload]
name = "legacy-work"
entry = "main.rs"
strategy = "batch"

[[patterns]]
name = "sum-all"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[bqn]
backend = "cbqn"
optimize = true
"#;

    let m: Manifest = toml::from_str(toml_str).unwrap();
    assert!(
        validate(&m).is_ok(),
        "Legacy workload name should satisfy validation"
    );
    assert_eq!(effective_name(&m), "legacy-work");
}

// -----------------------------------------------------------------------
// Test 28: Pattern name with special characters gets sanitised for C/BQN
// -----------------------------------------------------------------------

#[test]
fn test_edge_pattern_name_sanitisation() {
    let m = single_pattern_manifest("my-special_name here", SourcePattern::LoopSum, "f64", "f64");
    let program = analyse_manifest(&m).unwrap();

    // C name: hyphens and spaces become underscores.
    assert_eq!(
        program.ffi_declarations[0].c_name,
        "bqniser_my_special_name_here"
    );

    // BQN name: hyphens/underscores/spaces become camelCase.
    let bqn = generate_bqn(&program).unwrap();
    assert!(
        bqn.contains("mySpecialNameHere"),
        "BQN should use camelCase sanitised name: got:\n{}",
        bqn
    );
}

// =======================================================================
// ASPECT TESTS: Cross-cutting properties of generated artifacts
// =======================================================================

// -----------------------------------------------------------------------
// Test 29: Generated .bqn files always have SPDX headers
// -----------------------------------------------------------------------

#[test]
fn test_aspect_bqn_spdx_header() {
    // Test with multiple different manifests.
    for name in &["proj-a", "proj-b", "proj-c"] {
        let m = single_pattern_manifest("op", SourcePattern::LoopSum, "f64", "f64");
        let mut m = m;
        m.project.name = name.to_string();
        let program = analyse_manifest(&m).unwrap();
        let bqn = generate_bqn(&program).unwrap();

        assert!(
            bqn.contains("SPDX-License-Identifier: MPL-2.0"),
            "BQN file for {} missing SPDX header",
            name
        );
    }
}

// -----------------------------------------------------------------------
// Test 30: Generated C headers have proper C-ABI declarations
// -----------------------------------------------------------------------

#[test]
fn test_aspect_c_header_abi_declarations() {
    let m = sample_manifest();
    let program = analyse_manifest(&m).unwrap();
    let (header, _) = generate_ffi(&program).unwrap();

    // Include guard.
    assert!(
        header.contains("#ifndef BQNISER_FFI_H"),
        "Missing include guard"
    );
    assert!(
        header.contains("#define BQNISER_FFI_H"),
        "Missing define guard"
    );
    assert!(
        header.contains("#endif /* BQNISER_FFI_H */"),
        "Missing endif guard"
    );

    // C++ extern "C" linkage guard.
    assert!(
        header.contains("extern \"C\""),
        "Missing extern C for C++ compat"
    );
    assert!(
        header.contains("#ifdef __cplusplus"),
        "Missing __cplusplus guard"
    );

    // Standard includes for fixed-width types.
    assert!(
        header.contains("#include <stddef.h>"),
        "Missing stddef.h include"
    );
    assert!(
        header.contains("#include <stdint.h>"),
        "Missing stdint.h include"
    );

    // SPDX header.
    assert!(
        header.contains("SPDX-License-Identifier: MPL-2.0"),
        "C header missing SPDX"
    );

    // Every function has a return type and valid C identifier.
    for ffi in &program.ffi_declarations {
        assert!(
            header.contains(&ffi.c_name),
            "Header missing function: {}",
            ffi.c_name
        );
    }
}

// -----------------------------------------------------------------------
// Test 31: Generated Zig FFI has proper CBQN API usage
// -----------------------------------------------------------------------

#[test]
fn test_aspect_zig_ffi_structure() {
    let m = sample_manifest();
    let program = analyse_manifest(&m).unwrap();
    let (_, zig) = generate_ffi(&program).unwrap();

    // Zig must import CBQN C API.
    assert!(zig.contains("@cImport"), "Zig must use @cImport");
    assert!(
        zig.contains("@cInclude(\"cbqn.h\")"),
        "Zig must include cbqn.h"
    );

    // SPDX header.
    assert!(
        zig.contains("SPDX-License-Identifier: MPL-2.0"),
        "Zig FFI missing SPDX"
    );

    // All exported functions use C calling convention.
    assert!(
        zig.contains("callconv(.C)"),
        "Zig functions must use C calling convention"
    );

    // Lifecycle functions.
    assert!(zig.contains("export fn bqniser_init"));
    assert!(zig.contains("export fn bqniser_cleanup"));

    // Each pattern function is exported.
    for ffi in &program.ffi_declarations {
        assert!(
            zig.contains(&format!("export fn {}", ffi.c_name)),
            "Zig missing export for: {}",
            ffi.c_name
        );
    }
}

// -----------------------------------------------------------------------
// Test 32: BQN primitives are Unicode-correct (actual code points)
// -----------------------------------------------------------------------

#[test]
fn test_aspect_bqn_primitives_unicode_correct() {
    // Verify every primitive glyph is the correct Unicode character,
    // not a lookalike or mojibake.
    let cases: Vec<(BQNPrimitive, &str, u32)> = vec![
        (BQNPrimitive::Join, "\u{223E}", 0x223E), // ∾ INVERTED LAZY S
        (BQNPrimitive::Reverse, "\u{233D}", 0x233D), // ⌽ APL FUNCTIONAL SYMBOL CIRCLE STILE
        (BQNPrimitive::GradeUp, "\u{234B}", 0x234B), // ⍋ APL FUNCTIONAL SYMBOL DELTA STILE
        (BQNPrimitive::Replicate, "/", 0x002F),   // / SOLIDUS
        (BQNPrimitive::Select, "\u{228F}", 0x228F), // ⊏ SQUARE IMAGE OF
        (BQNPrimitive::Reshape, "\u{294A}", 0x294A), // ⥊ LEFT BARB UP RIGHT BARB DOWN HARPOON
        (BQNPrimitive::Fold, "\u{00B4}", 0x00B4), // ´ ACUTE ACCENT
        (BQNPrimitive::Scan, "`", 0x0060),        // ` GRAVE ACCENT
        (BQNPrimitive::Each, "\u{00A8}", 0x00A8), // ¨ DIAERESIS
        (BQNPrimitive::Table, "\u{231C}", 0x231C), // ⌜ TOP LEFT CORNER
    ];

    for (prim, expected_str, expected_cp) in &cases {
        let glyph = prim.glyph();
        assert_eq!(
            glyph, *expected_str,
            "{:?} glyph mismatch: expected {:?}, got {:?}",
            prim, expected_str, glyph
        );
        // Verify the actual Unicode code point.
        let first_cp = glyph.chars().next().unwrap() as u32;
        assert_eq!(
            first_cp, *expected_cp,
            "{:?} code point mismatch: expected U+{:04X}, got U+{:04X}",
            prim, expected_cp, first_cp
        );
    }
}

// -----------------------------------------------------------------------
// Test 33: Generated BQN contains proper assignment arrows
// -----------------------------------------------------------------------

#[test]
fn test_aspect_bqn_assignment_arrows() {
    let m = sample_manifest();
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    // BQN assignment arrow: ← (U+2190).
    assert!(
        bqn.contains('\u{2190}'),
        "BQN output must use ← (U+2190) for assignment"
    );
    // BQN export arrow: ⇐ (U+21D0) in the namespace block.
    assert!(
        bqn.contains('\u{21D0}'),
        "BQN output must use ⇐ (U+21D0) for exports"
    );
}

// =======================================================================
// ABI TESTS: Comprehensive primitive and pattern validation
// =======================================================================

// -----------------------------------------------------------------------
// Test 34: All BQNPrimitive variants have non-empty glyphs
// -----------------------------------------------------------------------

#[test]
fn test_abi_all_primitives_have_glyphs() {
    let all_primitives = vec![
        BQNPrimitive::Join,
        BQNPrimitive::Reverse,
        BQNPrimitive::GradeUp,
        BQNPrimitive::Replicate,
        BQNPrimitive::Select,
        BQNPrimitive::Reshape,
        BQNPrimitive::Fold,
        BQNPrimitive::Scan,
        BQNPrimitive::Each,
        BQNPrimitive::Table,
    ];

    for prim in &all_primitives {
        let glyph = prim.glyph();
        assert!(!glyph.is_empty(), "{:?} has empty glyph", prim);
        // Each glyph should be exactly one Unicode character.
        assert_eq!(
            glyph.chars().count(),
            1,
            "{:?} glyph should be exactly 1 character, got {}: {:?}",
            prim,
            glyph.chars().count(),
            glyph
        );
    }
}

// -----------------------------------------------------------------------
// Test 35: All BQNPrimitive variants have non-empty labels
// -----------------------------------------------------------------------

#[test]
fn test_abi_all_primitives_have_labels() {
    let all_primitives = vec![
        BQNPrimitive::Join,
        BQNPrimitive::Reverse,
        BQNPrimitive::GradeUp,
        BQNPrimitive::Replicate,
        BQNPrimitive::Select,
        BQNPrimitive::Reshape,
        BQNPrimitive::Fold,
        BQNPrimitive::Scan,
        BQNPrimitive::Each,
        BQNPrimitive::Table,
    ];

    for prim in &all_primitives {
        let label = prim.label();
        assert!(!label.is_empty(), "{:?} has empty label", prim);
        // Labels should start with uppercase.
        assert!(
            label.chars().next().unwrap().is_uppercase(),
            "{:?} label should be capitalised: {:?}",
            prim,
            label
        );
    }
}

// -----------------------------------------------------------------------
// Test 36: All BQNPrimitive variants have valid arity (1 or 2)
// -----------------------------------------------------------------------

#[test]
fn test_abi_all_primitives_valid_arity() {
    let all_primitives = vec![
        BQNPrimitive::Join,
        BQNPrimitive::Reverse,
        BQNPrimitive::GradeUp,
        BQNPrimitive::Replicate,
        BQNPrimitive::Select,
        BQNPrimitive::Reshape,
        BQNPrimitive::Fold,
        BQNPrimitive::Scan,
        BQNPrimitive::Each,
        BQNPrimitive::Table,
    ];

    for prim in &all_primitives {
        let arity = prim.arity();
        assert!(
            arity == 1 || arity == 2,
            "{:?} has invalid arity {}: must be 1 or 2",
            prim,
            arity
        );
    }
}

// -----------------------------------------------------------------------
// Test 37: Pattern-to-primitive mapping is exhaustive (all 5 kinds)
// -----------------------------------------------------------------------

#[test]
fn test_abi_pattern_to_primitive_exhaustive() {
    let all_kinds = vec![
        ArrayPatternKind::LoopSum,
        ArrayPatternKind::MapTransform,
        ArrayPatternKind::FilterPredicate,
        ArrayPatternKind::Sort,
        ArrayPatternKind::GroupBy,
    ];

    for kind in &all_kinds {
        let prims = kind.primary_primitives();
        assert!(!prims.is_empty(), "{:?} returned no primitives", kind);
        // Every primitive in the list must be a valid BQNPrimitive.
        for prim in &prims {
            assert!(
                !prim.glyph().is_empty(),
                "{:?} -> {:?} has empty glyph",
                kind,
                prim
            );
        }
    }
}

// -----------------------------------------------------------------------
// Test 38: ArrayPattern preserves all fields from PatternEntry
// -----------------------------------------------------------------------

#[test]
fn test_abi_array_pattern_field_preservation() {
    let entries = vec![
        PatternEntry {
            name: "alpha".to_string(),
            source_pattern: SourcePattern::LoopSum,
            input_type: "u8".to_string(),
            output_type: "u8".to_string(),
        },
        PatternEntry {
            name: "beta".to_string(),
            source_pattern: SourcePattern::MapTransform,
            input_type: "i64".to_string(),
            output_type: "i64".to_string(),
        },
        PatternEntry {
            name: "gamma".to_string(),
            source_pattern: SourcePattern::FilterPredicate,
            input_type: "f32".to_string(),
            output_type: "Vec<f32>".to_string(),
        },
        PatternEntry {
            name: "delta".to_string(),
            source_pattern: SourcePattern::Sort,
            input_type: "i16".to_string(),
            output_type: "Vec<i16>".to_string(),
        },
        PatternEntry {
            name: "epsilon".to_string(),
            source_pattern: SourcePattern::GroupBy,
            input_type: "u32".to_string(),
            output_type: "Vec<Vec<u32>>".to_string(),
        },
    ];

    for entry in &entries {
        let pat = pattern_from_entry(entry);
        assert_eq!(
            pat.name, entry.name,
            "Name not preserved for {}",
            entry.name
        );
        assert_eq!(
            pat.input_type, entry.input_type,
            "input_type not preserved for {}",
            entry.name
        );
        assert_eq!(
            pat.output_type, entry.output_type,
            "output_type not preserved for {}",
            entry.name
        );
        assert_eq!(
            pat.kind,
            source_pattern_to_kind(&entry.source_pattern),
            "kind not correct for {}",
            entry.name
        );
        assert_eq!(
            pat.primitives,
            pat.kind.primary_primitives(),
            "primitives mismatch for {}",
            entry.name
        );
    }
}

// -----------------------------------------------------------------------
// Test 39: BQNPrimitive Display trait includes glyph and label
// -----------------------------------------------------------------------

#[test]
fn test_abi_primitive_display_trait() {
    let prim = BQNPrimitive::GradeUp;
    let display = format!("{}", prim);
    assert!(
        display.contains("Grade Up"),
        "Display should include label: got {:?}",
        display
    );
    assert!(
        display.contains("\u{234B}"),
        "Display should include glyph: got {:?}",
        display
    );
}

// -----------------------------------------------------------------------
// Test 40: SourcePattern Display trait matches TOML kebab-case
// -----------------------------------------------------------------------

#[test]
fn test_abi_source_pattern_display() {
    assert_eq!(format!("{}", SourcePattern::LoopSum), "loop-sum");
    assert_eq!(format!("{}", SourcePattern::MapTransform), "map-transform");
    assert_eq!(
        format!("{}", SourcePattern::FilterPredicate),
        "filter-predicate"
    );
    assert_eq!(format!("{}", SourcePattern::Sort), "sort");
    assert_eq!(format!("{}", SourcePattern::GroupBy), "group-by");
}

// -----------------------------------------------------------------------
// Test 41: All glyphs are unique (no two primitives share a glyph)
// -----------------------------------------------------------------------

#[test]
fn test_abi_all_glyphs_unique() {
    let all_primitives = vec![
        BQNPrimitive::Join,
        BQNPrimitive::Reverse,
        BQNPrimitive::GradeUp,
        BQNPrimitive::Replicate,
        BQNPrimitive::Select,
        BQNPrimitive::Reshape,
        BQNPrimitive::Fold,
        BQNPrimitive::Scan,
        BQNPrimitive::Each,
        BQNPrimitive::Table,
    ];

    let mut seen = std::collections::HashSet::new();
    for prim in &all_primitives {
        let glyph = prim.glyph();
        assert!(
            seen.insert(glyph),
            "Duplicate glyph {:?} for {:?}",
            glyph,
            prim
        );
    }
}

// -----------------------------------------------------------------------
// Test 42: FFI C types for each Rust numeric type
// -----------------------------------------------------------------------

#[test]
fn test_abi_ffi_c_type_mapping() {
    // Build patterns with various input types to verify C type mapping.
    let type_pairs: Vec<(&str, &str)> = vec![
        ("f64", "double"),
        ("f32", "float"),
        ("i32", "int32_t"),
        ("i64", "int64_t"),
        ("u32", "uint32_t"),
        ("u64", "uint64_t"),
    ];

    for (rust_ty, expected_c) in &type_pairs {
        let m = single_pattern_manifest("typed-op", SourcePattern::LoopSum, rust_ty, rust_ty);
        let program = analyse_manifest(&m).unwrap();
        let (header, _) = generate_ffi(&program).unwrap();

        // LoopSum returns a scalar of the element type.
        assert!(
            header.contains(expected_c),
            "Input type {} should map to C type {} in header:\n{}",
            rust_ty,
            expected_c,
            header
        );
    }
}

// -----------------------------------------------------------------------
// Test 43: BQN generation with optimize=false produces unoptimised sort
// -----------------------------------------------------------------------

#[test]
fn test_abi_unoptimised_sort_body() {
    let mut m = single_pattern_manifest("sort-it", SourcePattern::Sort, "i32", "Vec<i32>");
    m.bqn.optimize = false;
    let program = analyse_manifest(&m).unwrap();
    let bqn = generate_bqn(&program).unwrap();

    // Unoptimised sort should use the two-step form with a `perm` intermediate.
    assert!(
        bqn.contains("perm"),
        "Unoptimised sort should use 'perm' intermediate variable: got:\n{}",
        bqn
    );
}

// -----------------------------------------------------------------------
// Test 44: Manifest default values (no [bqn] section)
// -----------------------------------------------------------------------

#[test]
fn test_edge_manifest_defaults() {
    let toml_str = r#"
[project]
name = "defaults-test"
version = "0.1.0"
description = "Testing defaults"

[[patterns]]
name = "s"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"
"#;

    let m: Manifest = toml::from_str(toml_str).unwrap();
    // Default backend should be "cbqn".
    assert_eq!(m.bqn.backend, "cbqn", "Default backend should be cbqn");
    // Default optimize should be true.
    assert!(m.bqn.optimize, "Default optimize should be true");
    // Validation should pass with defaults.
    assert!(validate(&m).is_ok());
}

// -----------------------------------------------------------------------
// Test 45: TOML round-trip — each SourcePattern variant deserialises
// -----------------------------------------------------------------------

#[test]
fn test_edge_all_source_patterns_from_toml() {
    let patterns_toml = vec![
        ("loop-sum", SourcePattern::LoopSum),
        ("map-transform", SourcePattern::MapTransform),
        ("filter-predicate", SourcePattern::FilterPredicate),
        ("sort", SourcePattern::Sort),
        ("group-by", SourcePattern::GroupBy),
    ];

    for (toml_name, expected) in &patterns_toml {
        let toml_str = format!(
            r#"
[project]
name = "variant-test"
version = "0.1.0"
description = "Testing {}"

[[patterns]]
name = "op"
source-pattern = "{}"
input-type = "f64"
output-type = "f64"

[bqn]
backend = "cbqn"
optimize = true
"#,
            toml_name, toml_name
        );

        let m: Manifest = toml::from_str(&toml_str)
            .unwrap_or_else(|e| panic!("Failed to parse source-pattern '{}': {}", toml_name, e));
        assert_eq!(
            m.patterns[0].source_pattern, *expected,
            "source-pattern '{}' should deserialise to {:?}",
            toml_name, expected
        );
    }
}

// -----------------------------------------------------------------------
// Test 46: E2E — project name with spaces gets underscore in filename
// -----------------------------------------------------------------------

#[test]
fn test_e2e_project_name_with_spaces() {
    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("bqniser.toml");
    let output_dir = dir.path().join("out");

    let toml_content = r#"
[project]
name = "my cool project"
version = "0.1.0"
description = "Spaces in name"

[[patterns]]
name = "op"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[bqn]
backend = "cbqn"
optimize = true
"#;
    std::fs::write(&manifest_path, toml_content).unwrap();

    let result = bqniser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    );
    assert!(result.is_ok(), "Spaces in project name: {:?}", result.err());

    // Spaces in project name become underscores in filename.
    assert!(
        output_dir.join("my_cool_project.bqn").exists(),
        "Spaces should become underscores in .bqn filename"
    );
}
