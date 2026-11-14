// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for ephapaxiser.
//
// Tests cover:
// - Manifest initialisation (init command creates valid ephapaxiser.toml)
// - Wrapper generation (generate command produces linear type wrappers)
// - Violation detection: leaks, double-frees, use-after-free
// - All resource kinds round-trip correctly
//
// Design note: When Idris2 proofs conflict with Ephapax linear types, Idris2 ALWAYS wins.

use ephapaxiser::abi::{LinearResource, OwnershipState, ResourceKind, SourceLocation, Violation};
use ephapaxiser::codegen::analyzer;
use ephapaxiser::codegen::parser::{self, CallSite, CallSiteKind};
use ephapaxiser::codegen::wrapper_gen;
use ephapaxiser::manifest::{
    AnalysisConfig, Manifest, ProjectConfig, ResourceEntry, SourceEntry, SourceLanguage,
};

/// Helper: create a minimal valid manifest for testing.
fn test_manifest() -> Manifest {
    Manifest {
        project: ProjectConfig {
            name: "test-project".to_string(),
        },
        sources: vec![SourceEntry {
            name: "test-source".to_string(),
            path: "src/test.rs".to_string(),
            language: SourceLanguage::Rust,
        }],
        resources: vec![
            ResourceEntry {
                name: "FileHandle".to_string(),
                allocator: "open".to_string(),
                deallocator: "close".to_string(),
                kind: "file-descriptor".to_string(),
            },
            ResourceEntry {
                name: "DbConnection".to_string(),
                allocator: "connect".to_string(),
                deallocator: "disconnect".to_string(),
                kind: "db-connection".to_string(),
            },
        ],
        analysis: AnalysisConfig::default(),
    }
}

/// Helper: create a source location.
fn loc(file: &str, line: usize) -> SourceLocation {
    SourceLocation {
        file: file.to_string(),
        line,
        column: 0,
    }
}

// ---------------------------------------------------------------------------
// Test: init creates a valid manifest
// ---------------------------------------------------------------------------

#[test]
fn test_init_creates_manifest() {
    let tmp_dir = tempfile::tempdir().expect("Failed to create temp dir");
    let path = tmp_dir.path().to_str().expect("Invalid temp path");

    // Init should succeed and create the file.
    ephapaxiser::manifest::init_manifest(path).expect("init_manifest failed");

    let manifest_path = tmp_dir.path().join("ephapaxiser.toml");
    assert!(
        manifest_path.exists(),
        "ephapaxiser.toml should exist after init"
    );

    // The created manifest should be parseable and valid.
    let manifest = ephapaxiser::manifest::load_manifest(manifest_path.to_str().unwrap())
        .expect("Failed to load generated manifest");
    ephapaxiser::manifest::validate(&manifest).expect("Generated manifest should be valid");
    assert_eq!(manifest.project.name, "my-safe-resources");
    assert!(!manifest.resources.is_empty());

    // Init should fail if manifest already exists.
    let result = ephapaxiser::manifest::init_manifest(path);
    assert!(
        result.is_err(),
        "init_manifest should fail if file already exists"
    );
}

// ---------------------------------------------------------------------------
// Test: generate produces wrappers
// ---------------------------------------------------------------------------

#[test]
fn test_generate_produces_wrappers() {
    let m = test_manifest();
    let output = wrapper_gen::generate_wrappers(&m.resources, &m.project.name);

    // Verify wrappers were generated for each resource.
    assert!(
        output.contains("pub struct LinearFileHandle<T>"),
        "Should generate LinearFileHandle wrapper"
    );
    assert!(
        output.contains("pub struct LinearDbConnection<T>"),
        "Should generate LinearDbConnection wrapper"
    );

    // Verify essential methods are present.
    assert!(
        output.contains("pub fn new(raw: T) -> Self"),
        "Should have constructor"
    );
    assert!(
        output.contains("pub fn consume(mut self) -> T"),
        "Should have consume method"
    );
    assert!(
        output.contains("pub fn borrow(&self) -> &T"),
        "Should have borrow method"
    );

    // Verify Drop is implemented (leak detection at runtime).
    assert!(
        output.contains("impl<T> Drop for LinearFileHandle<T>"),
        "Should implement Drop for leak detection"
    );

    // Verify the wrappers reference the correct allocator/deallocator names.
    assert!(
        output.contains("open()"),
        "Should reference allocator in docs"
    );
    assert!(
        output.contains("close()"),
        "Should reference deallocator in docs"
    );
}

// ---------------------------------------------------------------------------
// Test: generate writes files to output directory
// ---------------------------------------------------------------------------

#[test]
fn test_generate_writes_files() {
    let tmp_dir = tempfile::tempdir().expect("Failed to create temp dir");
    let output_dir = tmp_dir.path().join("output");
    let m = test_manifest();

    // generate_all should create the output directory and write wrappers.rs.
    ephapaxiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all failed");

    let wrappers_path = output_dir.join("wrappers.rs");
    assert!(wrappers_path.exists(), "wrappers.rs should be generated");

    let content = std::fs::read_to_string(&wrappers_path).expect("Failed to read wrappers.rs");
    assert!(
        content.contains("LinearFileHandle"),
        "wrappers.rs should contain LinearFileHandle"
    );
}

// ---------------------------------------------------------------------------
// Test: detect leak
// ---------------------------------------------------------------------------

#[test]
fn test_detect_leak() {
    let resources = vec![ResourceEntry {
        name: "FileHandle".to_string(),
        allocator: "open".to_string(),
        deallocator: "close".to_string(),
        kind: "file-descriptor".to_string(),
    }];

    // Source with allocation but no deallocation — leak.
    let source = "let fd = open(\"test.txt\");\n// no close\n";
    let sites = parser::parse_source(source, "test.rs", &resources);
    let result = analyzer::analyse(&sites, &resources, &AnalysisConfig::default());

    assert_eq!(result.leak_count(), 1, "Should detect exactly one leak");
    assert_eq!(result.double_free_count(), 0);
    assert_eq!(result.use_after_free_count(), 0);

    // Verify the violation details.
    match &result.violations[0] {
        Violation::Leak {
            resource_name,
            allocation_site,
        } => {
            assert_eq!(resource_name, "FileHandle");
            assert_eq!(allocation_site.line, 1);
        }
        other => panic!("Expected Leak violation, got {:?}", other),
    }
}

// ---------------------------------------------------------------------------
// Test: detect double-free
// ---------------------------------------------------------------------------

#[test]
fn test_detect_double_free() {
    let resources = vec![ResourceEntry {
        name: "FileHandle".to_string(),
        allocator: "open".to_string(),
        deallocator: "close".to_string(),
        kind: "file-descriptor".to_string(),
    }];

    // Source with allocation and two deallocations — double-free.
    let source = "let fd = open(\"test.txt\");\nclose(fd);\nclose(fd);\n";
    let sites = parser::parse_source(source, "test.rs", &resources);
    let result = analyzer::analyse(&sites, &resources, &AnalysisConfig::default());

    assert_eq!(
        result.double_free_count(),
        1,
        "Should detect exactly one double-free"
    );
    assert_eq!(result.leak_count(), 0);

    // Verify the violation details.
    match &result.violations[0] {
        Violation::DoubleFree {
            resource_name,
            first_free,
            second_free,
        } => {
            assert_eq!(resource_name, "FileHandle");
            assert_eq!(first_free.line, 2);
            assert_eq!(second_free.line, 3);
        }
        other => panic!("Expected DoubleFree violation, got {:?}", other),
    }
}

// ---------------------------------------------------------------------------
// Test: detect use-after-free
// ---------------------------------------------------------------------------

#[test]
fn test_detect_use_after_free() {
    let resources = vec![ResourceEntry {
        name: "FileHandle".to_string(),
        allocator: "open".to_string(),
        deallocator: "close".to_string(),
        kind: "file-descriptor".to_string(),
    }];

    // Build call sites manually (parser does not detect generic "usage" in Phase 1,
    // so we construct the scenario directly via the analyzer API).
    let sites = vec![
        CallSite {
            resource_name: "FileHandle".to_string(),
            kind: CallSiteKind::Allocation,
            location: loc("test.rs", 1),
            binding: Some("fd".to_string()),
        },
        CallSite {
            resource_name: "FileHandle".to_string(),
            kind: CallSiteKind::Deallocation,
            location: loc("test.rs", 3),
            binding: Some("fd".to_string()),
        },
        CallSite {
            resource_name: "FileHandle".to_string(),
            kind: CallSiteKind::Usage,
            location: loc("test.rs", 5),
            binding: Some("fd".to_string()),
        },
    ];

    let result = analyzer::analyse(&sites, &resources, &AnalysisConfig::default());

    assert_eq!(
        result.use_after_free_count(),
        1,
        "Should detect exactly one use-after-free"
    );
    assert_eq!(result.leak_count(), 0);
    assert_eq!(result.double_free_count(), 0);

    // Verify the violation details.
    match &result.violations[0] {
        Violation::UseAfterFree {
            resource_name,
            free_site,
            use_site,
        } => {
            assert_eq!(resource_name, "FileHandle");
            assert_eq!(free_site.line, 3);
            assert_eq!(use_site.line, 5);
        }
        other => panic!("Expected UseAfterFree violation, got {:?}", other),
    }
}

// ---------------------------------------------------------------------------
// Test: all resource kinds
// ---------------------------------------------------------------------------

#[test]
fn test_all_resource_kinds() {
    // Verify every ResourceKind variant can be created, displayed, and round-tripped.
    let test_cases = vec![
        ("file-descriptor", ResourceKind::FileDescriptor),
        ("socket", ResourceKind::Socket),
        ("lock", ResourceKind::Lock),
        ("allocation", ResourceKind::Allocation),
        ("gpu-buffer", ResourceKind::GpuBuffer),
        ("db-connection", ResourceKind::DbConnection),
        (
            "my-custom-resource",
            ResourceKind::Custom("my-custom-resource".to_string()),
        ),
    ];

    for (string_repr, expected_kind) in &test_cases {
        // from_str_loose should produce the expected variant.
        let parsed = ResourceKind::from_str_loose(string_repr);
        assert_eq!(&parsed, expected_kind, "Failed to parse '{}'", string_repr);

        // as_str should round-trip back to the original string.
        assert_eq!(
            parsed.as_str(),
            *string_repr,
            "as_str mismatch for '{}'",
            string_repr
        );

        // Display should produce the same string.
        assert_eq!(
            format!("{}", parsed),
            *string_repr,
            "Display mismatch for '{}'",
            string_repr
        );
    }

    // Verify ResourceEntry.resource_kind() works.
    let entry = ResourceEntry {
        name: "TestSocket".to_string(),
        allocator: "socket".to_string(),
        deallocator: "close".to_string(),
        kind: "socket".to_string(),
    };
    assert_eq!(entry.resource_kind(), ResourceKind::Socket);

    // Verify LinearResource can hold any kind.
    for (_, kind) in &test_cases {
        let resource = LinearResource::new("test", "alloc", "dealloc", kind.clone());
        assert_eq!(&resource.kind, kind);
        assert_eq!(resource.state, OwnershipState::Uninitialized);
    }
}

// ---------------------------------------------------------------------------
// Test: clean analysis (no violations)
// ---------------------------------------------------------------------------

#[test]
fn test_clean_analysis() {
    let resources = vec![ResourceEntry {
        name: "FileHandle".to_string(),
        allocator: "open".to_string(),
        deallocator: "close".to_string(),
        kind: "file-descriptor".to_string(),
    }];

    // Source with proper open/close pair — no violations.
    let source = "let fd = open(\"test.txt\");\nclose(fd);\n";
    let sites = parser::parse_source(source, "test.rs", &resources);
    let result = analyzer::analyse(&sites, &resources, &AnalysisConfig::default());

    assert!(
        result.is_clean(),
        "Properly paired alloc/dealloc should produce no violations"
    );
    assert_eq!(result.allocation_count, 1);
    assert_eq!(result.deallocation_count, 1);
}

// ---------------------------------------------------------------------------
// Test: manifest validation
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_validation() {
    // Valid manifest should pass.
    let m = test_manifest();
    assert!(ephapaxiser::manifest::validate(&m).is_ok());

    // Empty project name should fail.
    let mut bad = test_manifest();
    bad.project.name = String::new();
    assert!(ephapaxiser::manifest::validate(&bad).is_err());

    // No sources should fail.
    let mut bad = test_manifest();
    bad.sources.clear();
    assert!(ephapaxiser::manifest::validate(&bad).is_err());

    // No resources should fail.
    let mut bad = test_manifest();
    bad.resources.clear();
    assert!(ephapaxiser::manifest::validate(&bad).is_err());

    // Empty allocator should fail.
    let mut bad = test_manifest();
    bad.resources[0].allocator = String::new();
    assert!(ephapaxiser::manifest::validate(&bad).is_err());
}

// ---------------------------------------------------------------------------
// Test: example manifest loads and validates
// ---------------------------------------------------------------------------

#[test]
fn test_example_manifest_loads() {
    let manifest_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/examples/safe-files/ephapaxiser.toml"
    );
    let m = ephapaxiser::manifest::load_manifest(manifest_path)
        .expect("Failed to load example manifest");
    ephapaxiser::manifest::validate(&m).expect("Example manifest should be valid");
    assert_eq!(m.project.name, "safe-files-example");
    assert_eq!(m.sources.len(), 1);
    assert_eq!(m.resources.len(), 2);
}

// ---------------------------------------------------------------------------
// Test: full pipeline on example
// ---------------------------------------------------------------------------

#[test]
fn test_example_full_pipeline() {
    let manifest_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/examples/safe-files/ephapaxiser.toml"
    );
    let base_dir = concat!(env!("CARGO_MANIFEST_DIR"), "/examples/safe-files");

    let m = ephapaxiser::manifest::load_manifest(manifest_path)
        .expect("Failed to load example manifest");

    let result =
        ephapaxiser::codegen::analyse_manifest(&m, base_dir).expect("analyse_manifest failed");

    // The example has intentional bugs. With Phase 1's flat (scope-unaware) analysis:
    // - leaky_file_usage's "fd" leak is masked by double_close's re-allocation of "fd"
    // - leaky_db_usage's "conn" leak IS detected (no subsequent re-allocation of "conn")
    // - double_close's second close(fd) IS detected as a double-free
    // Phase 2 (scope-aware CFG analysis) will catch ALL leaks including masked ones.
    assert!(!result.is_clean(), "Example should have violations");
    assert_eq!(
        result.leak_count(),
        1,
        "Phase 1 detects 1 leak (conn; fd leak masked by reuse)"
    );
    assert_eq!(result.double_free_count(), 1, "Example has 1 double-free");
}
