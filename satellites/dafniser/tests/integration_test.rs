// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for dafniser.
// Tests the full pipeline: manifest loading, parsing, validation,
// Dafny code generation, and compiler command generation.

use dafniser::abi::TargetLanguage;
use dafniser::codegen::parser;
use dafniser::manifest;

/// Helper: load the sorting example manifest.
fn load_sorting_manifest() -> manifest::Manifest {
    manifest::load_manifest("examples/sorting/dafniser.toml")
        .expect("sorting example manifest should parse")
}

// ---------------------------------------------------------------------------
// Manifest tests
// ---------------------------------------------------------------------------

/// Test that `init_manifest` creates a valid dafniser.toml.
#[test]
fn test_init_creates_manifest() {
    let dir = tempfile::tempdir().expect("create temp dir");
    let dir_path = dir.path().to_str().unwrap();

    manifest::init_manifest(dir_path).expect("init should succeed");

    let manifest_path = dir.path().join("dafniser.toml");
    assert!(manifest_path.exists(), "dafniser.toml should be created");

    // The generated manifest should be parseable.
    let content = std::fs::read_to_string(&manifest_path).unwrap();
    let m: manifest::Manifest = toml::from_str(&content).expect("template should parse as TOML");
    assert_eq!(m.project.name, "my-verified-project");
    assert!(!m.functions.is_empty());
}

/// Test that the sorting example manifest loads and validates.
#[test]
fn test_sorting_manifest_valid() {
    let m = load_sorting_manifest();
    manifest::validate(&m).expect("sorting manifest should validate");
    assert_eq!(m.project.name, "verified-sort");
    assert_eq!(m.functions.len(), 2);
    assert_eq!(m.dafny.target, "go");
    assert_eq!(m.dafny.verify_timeout, 30);
}

// ---------------------------------------------------------------------------
// Parser tests
// ---------------------------------------------------------------------------

/// Test binary_search spec parsing from the sorting example.
#[test]
fn test_binary_search_spec() {
    let m = load_sorting_manifest();
    let module = parser::parse_manifest(&m).expect("parse should succeed");

    let binary_search = module
        .functions
        .iter()
        .find(|f| f.name == "binary_search")
        .expect("binary_search should exist");

    // Parameters.
    assert_eq!(binary_search.params.len(), 2);
    assert_eq!(binary_search.params[0].name, "arr");
    assert_eq!(binary_search.params[0].dafny_type, "seq<int>");
    assert_eq!(binary_search.params[1].name, "key");
    assert_eq!(binary_search.params[1].dafny_type, "int");

    // Preconditions (sorted(arr) from the arr param's requires).
    assert_eq!(binary_search.preconditions.len(), 1);
    assert_eq!(binary_search.preconditions[0].expression, "sorted(arr)");

    // Postconditions.
    assert_eq!(binary_search.postconditions.len(), 1);
    assert!(
        binary_search.postconditions[0]
            .expression
            .contains("arr[result] == key")
    );

    // Decreases clause.
    assert!(binary_search.decreases.is_some());
    assert_eq!(
        binary_search.decreases.as_ref().unwrap().expression,
        "arr.Length"
    );
}

/// Test insertion_sort spec parsing.
#[test]
fn test_insertion_sort_spec() {
    let m = load_sorting_manifest();
    let module = parser::parse_manifest(&m).expect("parse should succeed");

    let insertion_sort = module
        .functions
        .iter()
        .find(|f| f.name == "insertion_sort")
        .expect("insertion_sort should exist");

    assert_eq!(insertion_sort.params.len(), 1);
    assert_eq!(insertion_sort.params[0].dafny_type, "seq<int>");
    assert_eq!(insertion_sort.returns.dafny_type, "seq<int>");

    // Postcondition should reference sorted and multiset.
    assert!(
        insertion_sort.postconditions[0]
            .expression
            .contains("sorted(result)")
    );
    assert!(
        insertion_sort.postconditions[0]
            .expression
            .contains("multiset(result) == multiset(arr)")
    );
}

// ---------------------------------------------------------------------------
// Code generation tests
// ---------------------------------------------------------------------------

/// Test that generate produces .dfy files in the output directory.
#[test]
fn test_generate_produces_dfy_files() {
    let dir = tempfile::tempdir().expect("create temp dir");
    let output_dir = dir.path().to_str().unwrap();
    let m = load_sorting_manifest();

    dafniser::codegen::generate_all(&m, output_dir).expect("generate should succeed");

    // Check that a .dfy file was created.
    let dfy_path = dir.path().join("Verified_sort.dfy");
    assert!(dfy_path.exists(), ".dfy file should be created");

    // Check that commands.sh was created.
    let commands_path = dir.path().join("commands.sh");
    assert!(commands_path.exists(), "commands.sh should be created");

    // Verify the .dfy content has the expected structure.
    let dfy_content = std::fs::read_to_string(&dfy_path).unwrap();
    assert!(dfy_content.contains("module Verified_sort"));
    assert!(dfy_content.contains("method binary_search"));
    assert!(dfy_content.contains("method insertion_sort"));
}

/// Test that requires/ensures clauses appear in generated Dafny code.
#[test]
fn test_requires_ensures_generation() {
    let dir = tempfile::tempdir().expect("create temp dir");
    let output_dir = dir.path().to_str().unwrap();
    let m = load_sorting_manifest();

    dafniser::codegen::generate_all(&m, output_dir).expect("generate should succeed");

    let dfy_path = dir.path().join("Verified_sort.dfy");
    let content = std::fs::read_to_string(&dfy_path).unwrap();

    // Requires clauses.
    assert!(content.contains("requires sorted(arr)"));

    // Ensures clauses.
    assert!(content.contains("ensures result >= 0 ==> arr[result] == key"));
    assert!(content.contains("ensures sorted(result) && multiset(result) == multiset(arr)"));

    // Decreases clause.
    assert!(content.contains("decreases arr.Length"));

    // Helper predicate.
    assert!(content.contains("predicate sorted(s: seq<int>)"));
}

// ---------------------------------------------------------------------------
// Target language tests
// ---------------------------------------------------------------------------

/// Test that all valid target strings parse correctly.
#[test]
fn test_all_targets_valid() {
    let cases = vec![
        ("csharp", TargetLanguage::CSharp),
        ("cs", TargetLanguage::CSharp),
        ("java", TargetLanguage::Java),
        ("go", TargetLanguage::Go),
        ("python", TargetLanguage::Python),
        ("py", TargetLanguage::Python),
        ("js", TargetLanguage::Js),
        ("javascript", TargetLanguage::Js),
    ];
    for (input, expected) in cases {
        let result = parser::parse_target(input)
            .unwrap_or_else(|_| panic!("parse_target('{}') should succeed", input));
        assert_eq!(result, expected, "parse_target('{}') mismatch", input);
    }
}

/// Test that invalid target strings are rejected.
#[test]
fn test_invalid_target_rejected() {
    assert!(parser::parse_target("ruby").is_err());
    assert!(parser::parse_target("").is_err());
    assert!(parser::parse_target("c++").is_err());
}
