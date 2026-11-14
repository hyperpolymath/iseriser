// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for atsiser.
//
// These tests exercise the full pipeline from manifest parsing through ATS2 code
// generation, verifying that:
// - Manifests with the new [project]/[[c-sources]]/[[ownership-rules]]/[ats2]
//   schema parse correctly
// - C header parsing extracts the right function signatures
// - Ownership pattern detection works for common C idioms
// - ATS2 code generation produces valid .sats and .dats output
// - The generated output contains correct viewtype definitions and proof terms
// - Edge cases (empty manifests, missing files, invalid patterns) are handled

use atsiser::abi::{MemorySafetyProof, OwnershipPattern, Viewtype};
use atsiser::codegen::ats_gen;
use atsiser::codegen::compiler;
use atsiser::codegen::parser;
use atsiser::manifest::{self, ATS2Config, CSource, Manifest, OwnershipRule, ProjectConfig};
use tempfile::TempDir;

// ---------------------------------------------------------------------------
// Test 1: Full manifest round-trip (parse -> validate -> info)
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_round_trip() {
    let toml_str = r#"
[project]
name = "safe-malloc"
version = "0.1.0"
description = "ATS2 wrappers for malloc/free"
output-dir = "gen"

[[c-sources]]
path = "include/stdlib.h"
include-dirs = ["include", "/usr/include"]
description = "Standard library memory functions"

[[ownership-rules]]
function = "malloc"
pattern = "alloc"
resource-type = "void"
description = "Allocates memory"

[[ownership-rules]]
function = "free"
pattern = "free"
param-index = 0
resource-type = "void"
description = "Frees memory"

[[ownership-rules]]
function = "strlen"
pattern = "borrow"
param-index = 0
description = "Reads string length without ownership"

[ats2]
patsopt = "patsopt"
patscc = "patscc"
flags = ["-DATS_MEMALLOC_LIBC"]
c-flags = ["-O2"]
"#;

    let manifest: Manifest = toml::from_str(toml_str).unwrap();

    // Validate passes
    manifest::validate(&manifest).unwrap();

    // Check parsed fields
    assert_eq!(manifest.project.name, "safe-malloc");
    assert_eq!(manifest.project.version, "0.1.0");
    assert_eq!(manifest.project.output_dir, "gen");
    assert_eq!(manifest.c_sources.len(), 1);
    assert_eq!(manifest.c_sources[0].include_dirs.len(), 2);
    assert_eq!(manifest.ownership_rules.len(), 3);
    assert_eq!(manifest.ownership_rules[0].pattern, "alloc");
    assert_eq!(manifest.ownership_rules[1].pattern, "free");
    assert_eq!(manifest.ownership_rules[2].pattern, "borrow");
    assert_eq!(manifest.ats2.flags, vec!["-DATS_MEMALLOC_LIBC"]);
}

// ---------------------------------------------------------------------------
// Test 2: C header parsing extracts correct signatures
// ---------------------------------------------------------------------------

#[test]
fn test_c_header_parsing() {
    let c_source = r#"
/* Memory allocation functions */
void* malloc(size_t size);
void free(void* ptr);
void* realloc(void* ptr, size_t new_size);
void* memcpy(void* dest, const void* src, size_t n);
size_t strlen(const char* s);
int printf(const char* fmt);
"#;

    let sigs = parser::parse_c_source(c_source).unwrap();

    // Should find all 6 functions
    assert_eq!(sigs.len(), 6);

    // malloc: returns pointer -> likely_alloc
    let malloc_sig = sigs.iter().find(|s| s.name == "malloc").unwrap();
    assert!(malloc_sig.likely_alloc);
    assert!(!malloc_sig.likely_free);
    assert_eq!(malloc_sig.params.len(), 1);

    // free: void return + pointer param -> likely_free
    let free_sig = sigs.iter().find(|s| s.name == "free").unwrap();
    assert!(free_sig.likely_free);
    assert!(!free_sig.likely_alloc);

    // strlen: non-pointer return, const pointer param -> neither alloc nor free
    let strlen_sig = sigs.iter().find(|s| s.name == "strlen").unwrap();
    assert!(!strlen_sig.likely_alloc);
    assert!(!strlen_sig.likely_free);
}

// ---------------------------------------------------------------------------
// Test 3: Ownership pattern detection heuristics
// ---------------------------------------------------------------------------

#[test]
fn test_ownership_pattern_detection() {
    // Test alloc pattern: name contains "create" + returns pointer
    let create_sig = parser::CFunctionSignature {
        name: "widget_create".to_string(),
        return_type: "widget_t*".to_string(),
        params: vec![],
        likely_alloc: true,
        likely_free: false,
    };
    assert_eq!(parser::detect_ownership_pattern(&create_sig), Some("alloc"));

    // Test free pattern: name contains "destroy" + void return + pointer param
    let destroy_sig = parser::CFunctionSignature {
        name: "widget_destroy".to_string(),
        return_type: "void".to_string(),
        params: vec![parser::CParam {
            c_type: "widget_t*".to_string(),
            name: "w".to_string(),
            is_pointer: true,
            is_const: false,
        }],
        likely_alloc: false,
        likely_free: true,
    };
    assert_eq!(parser::detect_ownership_pattern(&destroy_sig), Some("free"));

    // Test borrow pattern: all pointer params are const
    let borrow_sig = parser::CFunctionSignature {
        name: "widget_get_id".to_string(),
        return_type: "int".to_string(),
        params: vec![parser::CParam {
            c_type: "const widget_t*".to_string(),
            name: "w".to_string(),
            is_pointer: true,
            is_const: true,
        }],
        likely_alloc: false,
        likely_free: false,
    };
    assert_eq!(
        parser::detect_ownership_pattern(&borrow_sig),
        Some("borrow")
    );
}

// ---------------------------------------------------------------------------
// Test 4: ATS2 module generation from ownership rules
// ---------------------------------------------------------------------------

#[test]
fn test_ats2_module_generation() {
    let rules = vec![
        OwnershipRule {
            function: "buffer_create".to_string(),
            pattern: "alloc".to_string(),
            param_index: None,
            resource_type: Some("buffer_t".to_string()),
            description: "Allocate a new buffer".to_string(),
        },
        OwnershipRule {
            function: "buffer_destroy".to_string(),
            pattern: "free".to_string(),
            param_index: Some(0),
            resource_type: Some("buffer_t".to_string()),
            description: "Free a buffer".to_string(),
        },
        OwnershipRule {
            function: "buffer_read".to_string(),
            pattern: "borrow".to_string(),
            param_index: Some(0),
            resource_type: Some("buffer_t".to_string()),
            description: "Read from buffer without consuming".to_string(),
        },
    ];

    let c_sources = vec![CSource {
        path: "buffer.h".to_string(),
        include_dirs: vec!["include".to_string()],
        description: String::new(),
    }];

    let module = ats_gen::generate_module("safe_buffer", &[], &rules, &c_sources).unwrap();

    // Module name
    assert_eq!(module.name, "safe_buffer");

    // Should have 1 viewtype (buffer_t_vt, deduplicated)
    assert_eq!(module.viewtypes.len(), 1);
    assert_eq!(module.viewtypes[0].name, "buffer_t_vt");

    // Should have 3 functions
    assert_eq!(module.functions.len(), 3);
    assert_eq!(module.functions[0].name, "safe_buffer_create");
    assert_eq!(module.functions[0].pattern, OwnershipPattern::Alloc);
    assert_eq!(module.functions[1].name, "safe_buffer_destroy");
    assert_eq!(module.functions[1].pattern, OwnershipPattern::Free);
    assert_eq!(module.functions[2].name, "safe_buffer_read");
    assert_eq!(module.functions[2].pattern, OwnershipPattern::Borrow);

    // Should have 3 proofs
    assert_eq!(module.proofs.len(), 3);

    // Include directive
    assert!(module.includes.contains(&"buffer.h".to_string()));
}

// ---------------------------------------------------------------------------
// Test 5: ATS2 code rendering produces valid output
// ---------------------------------------------------------------------------

#[test]
fn test_ats2_code_rendering() {
    let rules = vec![
        OwnershipRule {
            function: "res_alloc".to_string(),
            pattern: "alloc".to_string(),
            param_index: None,
            resource_type: Some("resource_t".to_string()),
            description: String::new(),
        },
        OwnershipRule {
            function: "res_free".to_string(),
            pattern: "free".to_string(),
            param_index: Some(0),
            resource_type: Some("resource_t".to_string()),
            description: String::new(),
        },
    ];

    let module = ats_gen::generate_module("test_render", &[], &rules, &[]).unwrap();
    let (sats, dats) = ats_gen::render_module(&module).unwrap();

    // SATS should contain viewtype definition
    assert!(
        sats.contains("viewtypedef resource_t_vt"),
        "sats missing viewtype def"
    );

    // SATS should contain extern declarations
    assert!(
        sats.contains("extern fun res_alloc_c"),
        "sats missing extern fun"
    );
    assert!(
        sats.contains("extern fun res_free_c"),
        "sats missing extern fun"
    );

    // SATS should contain safe wrapper signatures
    assert!(
        sats.contains("fun safe_res_alloc"),
        "sats missing safe wrapper sig"
    );
    assert!(
        sats.contains("fun safe_res_free"),
        "sats missing safe wrapper sig"
    );

    // DATS should contain implementation bodies
    assert!(dats.contains("implement"), "dats missing implement keyword");
    assert!(dats.contains("$extfcall"), "dats missing $extfcall");
    assert!(dats.contains("MPL-2.0"), "dats missing license");

    // DATS should contain staload
    assert!(dats.contains("staload"), "dats missing staload");
}

// ---------------------------------------------------------------------------
// Test 6: Manifest init creates valid template
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_init_creates_template() {
    let tmpdir = TempDir::new().unwrap();
    let path = tmpdir.path().to_str().unwrap();

    manifest::init_manifest(path).unwrap();

    let manifest_path = tmpdir.path().join("atsiser.toml");
    assert!(manifest_path.exists(), "atsiser.toml should be created");

    // The generated manifest should be parseable and valid
    let content = std::fs::read_to_string(&manifest_path).unwrap();
    let m: Manifest = toml::from_str(&content).unwrap();
    manifest::validate(&m).unwrap();

    // Check it has the expected structure
    assert!(!m.project.name.is_empty());
    assert!(!m.c_sources.is_empty());
    assert!(!m.ownership_rules.is_empty());
}

// ---------------------------------------------------------------------------
// Test 7: Manifest init refuses to overwrite
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_init_no_overwrite() {
    let tmpdir = TempDir::new().unwrap();
    let path = tmpdir.path().to_str().unwrap();

    // First init succeeds
    manifest::init_manifest(path).unwrap();

    // Second init should fail
    let result = manifest::init_manifest(path);
    assert!(
        result.is_err(),
        "init should refuse to overwrite existing manifest"
    );
}

// ---------------------------------------------------------------------------
// Test 8: Validation rejects invalid ownership patterns
// ---------------------------------------------------------------------------

#[test]
fn test_validation_rejects_bad_pattern() {
    let manifest = Manifest {
        project: ProjectConfig {
            name: "test".to_string(),
            version: "0.1.0".to_string(),
            description: String::new(),
            output_dir: "out".to_string(),
        },
        c_sources: vec![],
        ownership_rules: vec![OwnershipRule {
            function: "foo".to_string(),
            pattern: "steal".to_string(), // Invalid pattern
            param_index: None,
            resource_type: None,
            description: String::new(),
        }],
        ats2: ATS2Config::default(),
        workload: None,
        data: None,
        options: None,
    };

    let err = manifest::validate(&manifest).unwrap_err();
    assert!(
        err.to_string().contains("steal"),
        "Error should mention the invalid pattern"
    );
}

// ---------------------------------------------------------------------------
// Test 9: Compiler command construction
// ---------------------------------------------------------------------------

#[test]
fn test_compiler_command_construction() {
    let manifest = Manifest {
        project: ProjectConfig {
            name: "test-lib".to_string(),
            version: "0.1.0".to_string(),
            description: String::new(),
            output_dir: "generated/ats".to_string(),
        },
        c_sources: vec![],
        ownership_rules: vec![],
        ats2: ATS2Config {
            patsopt: "/usr/bin/patsopt".to_string(),
            patscc: "/usr/bin/patscc".to_string(),
            flags: vec!["-DATS_MEMALLOC_LIBC".to_string()],
            c_flags: vec!["-Wall".to_string(), "-Werror".to_string()],
            patshome: Some("/opt/ats2".to_string()),
        },
        workload: None,
        data: None,
        options: None,
    };

    // Build command
    let build_cmd = compiler::build_command(&manifest, "out/test.dats", true).unwrap();
    assert_eq!(build_cmd.program, "/usr/bin/patscc");
    assert!(build_cmd.args.contains(&"-DATS_MEMALLOC_LIBC".to_string()));
    assert!(build_cmd.args.contains(&"out/test.dats".to_string()));
    // Release mode should add -O2
    let display = build_cmd.display();
    assert!(display.contains("-O2"), "Release build should include -O2");

    // Environment
    assert!(
        build_cmd
            .env
            .iter()
            .any(|(k, v)| k == "PATSHOME" && v == "/opt/ats2")
    );

    // Typecheck command
    let tc_cmd = compiler::typecheck_command(&manifest, "out/test.dats").unwrap();
    assert_eq!(tc_cmd.program, "/usr/bin/patsopt");
    assert!(tc_cmd.args.contains(&"--typecheck".to_string()));
}

// ---------------------------------------------------------------------------
// Test 10: End-to-end generation writes files to disk
// ---------------------------------------------------------------------------

#[test]
fn test_end_to_end_generation() {
    let tmpdir = TempDir::new().unwrap();
    let output_dir = tmpdir.path().join("output");
    let output_str = output_dir.to_str().unwrap();

    // Create a C header in the tmpdir
    let include_dir = tmpdir.path().join("include");
    std::fs::create_dir_all(&include_dir).unwrap();
    std::fs::write(
        include_dir.join("mylib.h"),
        "void* mylib_create(int config);\nvoid mylib_destroy(void* handle);\nint mylib_process(const void* handle);\n",
    ).unwrap();

    let manifest = Manifest {
        project: ProjectConfig {
            name: "mylib".to_string(),
            version: "0.1.0".to_string(),
            description: "Test library".to_string(),
            output_dir: output_str.to_string(),
        },
        c_sources: vec![CSource {
            path: include_dir.join("mylib.h").to_str().unwrap().to_string(),
            include_dirs: vec![include_dir.to_str().unwrap().to_string()],
            description: String::new(),
        }],
        ownership_rules: vec![
            OwnershipRule {
                function: "mylib_create".to_string(),
                pattern: "alloc".to_string(),
                param_index: None,
                resource_type: Some("mylib_t".to_string()),
                description: String::new(),
            },
            OwnershipRule {
                function: "mylib_destroy".to_string(),
                pattern: "free".to_string(),
                param_index: Some(0),
                resource_type: Some("mylib_t".to_string()),
                description: String::new(),
            },
            OwnershipRule {
                function: "mylib_process".to_string(),
                pattern: "borrow".to_string(),
                param_index: Some(0),
                resource_type: Some("mylib_t".to_string()),
                description: String::new(),
            },
        ],
        ats2: ATS2Config::default(),
        workload: None,
        data: None,
        options: None,
    };

    // Generate
    atsiser::codegen::generate_all(&manifest, output_str).unwrap();

    // Check that files were created
    let sats_path = output_dir.join("mylib_safe.sats");
    let dats_path = output_dir.join("mylib_safe.dats");
    assert!(sats_path.exists(), "sats file should be generated");
    assert!(dats_path.exists(), "dats file should be generated");

    // Check contents
    let sats_content = std::fs::read_to_string(&sats_path).unwrap();
    assert!(
        sats_content.contains("mylib_t_vt"),
        "sats should define mylib_t viewtype"
    );
    assert!(
        sats_content.contains("safe_mylib_create"),
        "sats should have alloc wrapper"
    );
    assert!(
        sats_content.contains("safe_mylib_destroy"),
        "sats should have free wrapper"
    );
    assert!(
        sats_content.contains("safe_mylib_process"),
        "sats should have borrow wrapper"
    );

    let dats_content = std::fs::read_to_string(&dats_path).unwrap();
    assert!(
        dats_content.contains("implement"),
        "dats should have implementations"
    );
    assert!(
        dats_content.contains("$extfcall"),
        "dats should call C functions via extfcall"
    );
}

// ---------------------------------------------------------------------------
// Test 11: Viewtype ATS2 definitions
// ---------------------------------------------------------------------------

#[test]
fn test_viewtype_ats2_definitions() {
    // Standard viewtype
    let vt = Viewtype::new("file_vt", "FILE");
    let def = vt.to_ats2_definition();
    assert!(def.starts_with("viewtypedef file_vt"));
    assert!(def.contains("FILE @ l"));
    assert!(def.contains("ptr l"));
    assert!(
        !def.contains("option_v"),
        "non-nullable should not use option_v"
    );

    // Nullable viewtype
    let nvt = Viewtype::nullable("maybe_file_vt", "FILE");
    let ndef = nvt.to_ats2_definition();
    assert!(ndef.contains("option_v"), "nullable should use option_v");

    // Sized viewtype (dependent type)
    let svt = Viewtype::sized("array_vt", "int", "n");
    let sdef = svt.to_ats2_definition();
    assert!(
        sdef.contains("array_vt(n)"),
        "sized should include size parameter"
    );
}

// ---------------------------------------------------------------------------
// Test 12: Memory safety proof generation
// ---------------------------------------------------------------------------

#[test]
fn test_memory_safety_proofs() {
    let alloc_proof = MemorySafetyProof::AllocProof {
        viewtype: "buf_vt".to_string(),
    };
    let alloc_ats = alloc_proof.to_ats2_proof();
    assert!(alloc_ats.contains("prval"), "alloc proof should use prval");
    assert!(
        alloc_ats.contains("alloc_buf_vt"),
        "alloc proof should reference viewtype"
    );

    let free_proof = MemorySafetyProof::FreeProof {
        ptr_id: "handle".to_string(),
    };
    let free_ats = free_proof.to_ats2_proof();
    assert!(
        free_ats.contains("free_handle"),
        "free proof should reference ptr_id"
    );

    let borrow_proof = MemorySafetyProof::BorrowProof {
        ptr_id: "data".to_string(),
        mutable: false,
    };
    let borrow_ats = borrow_proof.to_ats2_proof();
    assert!(
        borrow_ats.contains("borrow_v"),
        "immutable borrow should use borrow_v"
    );

    let mut_borrow = MemorySafetyProof::BorrowProof {
        ptr_id: "data".to_string(),
        mutable: true,
    };
    let mut_ats = mut_borrow.to_ats2_proof();
    assert!(
        mut_ats.contains("borrow_vw"),
        "mutable borrow should use borrow_vw"
    );

    let bounds_proof = MemorySafetyProof::BoundsProof {
        buffer_id: "arr".to_string(),
        index_expr: "i".to_string(),
    };
    let bounds_ats = bounds_proof.to_ats2_proof();
    assert!(
        bounds_ats.contains("lemma_bounds"),
        "bounds proof should use lemma_bounds"
    );

    let null_proof = MemorySafetyProof::NullCheckProof {
        ptr_id: "ptr".to_string(),
    };
    let null_ats = null_proof.to_ats2_proof();
    assert!(
        null_ats.contains("opt_unsome"),
        "null check should use opt_unsome"
    );
}
