// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for tlaiser.
//
// These tests exercise the full pipeline from manifest loading through
// validation and code generation, verifying that the generated TLA+
// specifications, PlusCal algorithms, and TLC configurations are
// structurally correct.

use std::fs;
use tempfile::TempDir;
use tlaiser::codegen;
use tlaiser::manifest;

/// Helper: write a manifest string to a temp file and return (dir, path).
fn write_manifest(content: &str) -> (TempDir, String) {
    let dir = TempDir::new().expect("Failed to create temp dir");
    let manifest_path = dir.path().join("tlaiser.toml");
    fs::write(&manifest_path, content).expect("Failed to write manifest");
    (dir, manifest_path.to_str().unwrap().to_string())
}

/// A valid minimal manifest for testing.
const MINIMAL_MANIFEST: &str = r#"
[project]
name = "test-protocol"

[[state-machines]]
name = "Simple"
states = ["A", "B"]
initial-state = "A"

  [[state-machines.transitions]]
  from = "A"
  to = "B"
  label = "go"

  [[state-machines.transitions]]
  from = "B"
  to = "A"
  label = "back"

[tlc]
workers = 2
"#;

/// A more complex manifest with variables, guards, and properties.
const MUTEX_MANIFEST: &str = r#"
[project]
name = "mutex-test"
description = "Mutex protocol for testing"

[[state-machines]]
name = "MutexProtocol"
states = ["Idle", "Waiting", "Critical"]
initial-state = "Idle"
description = "Process lifecycle in mutex protocol"

  [[state-machines.variables]]
  name = "lock"
  init = "FALSE"
  type = "BOOLEAN"

  [[state-machines.transitions]]
  from = "Idle"
  to = "Waiting"
  label = "request"

  [[state-machines.transitions]]
  from = "Waiting"
  to = "Critical"
  guard = "lock = FALSE"
  action = "lock' = TRUE"
  label = "acquire"

  [[state-machines.transitions]]
  from = "Critical"
  to = "Idle"
  action = "lock' = FALSE"
  label = "release"

[[properties]]
name = "TypeSafe"
kind = "safety"
formula = "state \\in {Idle, Waiting, Critical}"

[[properties]]
name = "EventualEntry"
kind = "liveness"
formula = "state = Critical"

[tlc]
workers = 4
max-states = 100000
symmetry = false
"#;

// -----------------------------------------------------------------------
// Test 1: Manifest loading and parsing
// -----------------------------------------------------------------------

#[test]
fn test_load_minimal_manifest() {
    let (_dir, path) = write_manifest(MINIMAL_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");

    assert_eq!(m.project.name, "test-protocol");
    assert_eq!(m.state_machines.len(), 1);
    assert_eq!(m.state_machines[0].name, "Simple");
    assert_eq!(m.state_machines[0].states, vec!["A", "B"]);
    assert_eq!(m.state_machines[0].initial_state, "A");
    assert_eq!(m.state_machines[0].transitions.len(), 2);
}

// -----------------------------------------------------------------------
// Test 2: Manifest validation succeeds for valid input
// -----------------------------------------------------------------------

#[test]
fn test_validate_valid_manifest() {
    let (_dir, path) = write_manifest(MUTEX_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");
    manifest::validate(&m).expect("Validation should succeed");
}

// -----------------------------------------------------------------------
// Test 3: Manifest validation rejects invalid input
// -----------------------------------------------------------------------

#[test]
fn test_validate_rejects_empty_name() {
    let content = r#"
[project]
name = ""

[[state-machines]]
name = "X"
states = ["A"]
initial-state = "A"

[tlc]
"#;
    let (_dir, path) = write_manifest(content);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");
    assert!(manifest::validate(&m).is_err());
}

#[test]
fn test_validate_rejects_invalid_initial_state() {
    let content = r#"
[project]
name = "bad"

[[state-machines]]
name = "Bad"
states = ["A", "B"]
initial-state = "C"

[tlc]
"#;
    let (_dir, path) = write_manifest(content);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");
    let err = manifest::validate(&m).unwrap_err();
    assert!(err.to_string().contains("C"));
}

#[test]
fn test_validate_rejects_invalid_property_kind() {
    let content = r#"
[project]
name = "bad-prop"

[[state-machines]]
name = "X"
states = ["A", "B"]
initial-state = "A"

  [[state-machines.transitions]]
  from = "A"
  to = "B"

  [[state-machines.transitions]]
  from = "B"
  to = "A"

[[properties]]
name = "BadProp"
kind = "temporal"
formula = "TRUE"

[tlc]
"#;
    let (_dir, path) = write_manifest(content);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");
    let err = manifest::validate(&m).unwrap_err();
    assert!(err.to_string().contains("temporal"));
}

// -----------------------------------------------------------------------
// Test 4: Full code generation produces expected files
// -----------------------------------------------------------------------

#[test]
fn test_generate_all_creates_files() {
    let (_dir, path) = write_manifest(MUTEX_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");
    manifest::validate(&m).expect("Validation should succeed");

    let output_dir = TempDir::new().expect("Failed to create output dir");
    let output_path = output_dir.path().to_str().unwrap();

    codegen::generate_all(&m, output_path).expect("Code generation should succeed");

    // Check that all expected files were created
    let tla_file = output_dir.path().join("MutexProtocol.tla");
    let pcal_file = output_dir.path().join("MutexProtocolPlusCal.tla");
    let cfg_file = output_dir.path().join("MutexProtocol.cfg");
    let run_file = output_dir.path().join("run_tlc_MutexProtocol.sh");

    assert!(tla_file.exists(), "TLA+ spec file should exist");
    assert!(pcal_file.exists(), "PlusCal file should exist");
    assert!(cfg_file.exists(), "TLC config file should exist");
    assert!(run_file.exists(), "Run script should exist");
}

// -----------------------------------------------------------------------
// Test 5: Generated TLA+ spec has correct structure
// -----------------------------------------------------------------------

#[test]
fn test_generated_tla_spec_structure() {
    let (_dir, path) = write_manifest(MUTEX_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");

    let output_dir = TempDir::new().expect("Failed to create output dir");
    let output_path = output_dir.path().to_str().unwrap();
    codegen::generate_all(&m, output_path).expect("Code generation should succeed");

    let tla_content = fs::read_to_string(output_dir.path().join("MutexProtocol.tla"))
        .expect("Failed to read TLA+ file");

    // Module structure
    assert!(
        tla_content.contains("MODULE MutexProtocol"),
        "Should contain module name"
    );
    assert!(
        tla_content.contains("EXTENDS Naturals"),
        "Should extend standard modules"
    );
    assert!(
        tla_content.ends_with("====\n"),
        "Should end with module footer"
    );

    // Constants for states
    assert!(
        tla_content.contains("CONSTANTS Idle, Waiting, Critical"),
        "Should declare state constants"
    );

    // Variables including the lock
    assert!(
        tla_content.contains("VARIABLES state, lock"),
        "Should declare state and lock variables"
    );

    // Init predicate
    assert!(
        tla_content.contains("state = Idle"),
        "Init should set state to Idle"
    );
    assert!(
        tla_content.contains("lock = FALSE"),
        "Init should set lock to FALSE"
    );

    // Transition actions
    assert!(
        tla_content.contains("request =="),
        "Should have request transition action"
    );
    assert!(
        tla_content.contains("acquire =="),
        "Should have acquire transition action"
    );
    assert!(
        tla_content.contains("release =="),
        "Should have release transition action"
    );

    // Guard condition on acquire
    assert!(
        tla_content.contains("lock = FALSE"),
        "Acquire should have lock guard"
    );

    // Next-state relation
    assert!(tla_content.contains("Next =="), "Should have Next relation");

    // Specification
    assert!(
        tla_content.contains("Spec == Init /\\ [][Next]_vars"),
        "Should have Spec formula"
    );

    // Properties
    assert!(
        tla_content.contains("TypeSafe =="),
        "Should have TypeSafe property"
    );
    assert!(
        tla_content.contains("[]("),
        "Safety property should use [] operator"
    );
    assert!(
        tla_content.contains("<>("),
        "Liveness property should use <> operator"
    );
}

// -----------------------------------------------------------------------
// Test 6: Generated PlusCal has correct structure
// -----------------------------------------------------------------------

#[test]
fn test_generated_pluscal_structure() {
    let (_dir, path) = write_manifest(MUTEX_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");

    let output_dir = TempDir::new().expect("Failed to create output dir");
    let output_path = output_dir.path().to_str().unwrap();
    codegen::generate_all(&m, output_path).expect("Code generation should succeed");

    let pcal_content = fs::read_to_string(output_dir.path().join("MutexProtocolPlusCal.tla"))
        .expect("Failed to read PlusCal file");

    // Module structure
    assert!(
        pcal_content.contains("MODULE MutexProtocolPlusCal"),
        "Should contain PlusCal module name"
    );
    assert!(
        pcal_content.ends_with("====\n"),
        "Should end with module footer"
    );

    // Algorithm block
    assert!(
        pcal_content.contains("--fair algorithm MutexProtocol"),
        "Should contain fair algorithm declaration"
    );
    assert!(
        pcal_content.contains("end algorithm;"),
        "Should contain algorithm end marker"
    );

    // Variables
    assert!(
        pcal_content.contains("state = Idle"),
        "Should initialise state variable"
    );
    assert!(
        pcal_content.contains("lock = FALSE"),
        "Should initialise lock variable"
    );

    // PlusCal assignment syntax
    assert!(
        pcal_content.contains("state := Waiting")
            || pcal_content.contains("state := Critical")
            || pcal_content.contains("state := Idle"),
        "Should contain PlusCal assignments"
    );

    // Translation placeholder
    assert!(
        pcal_content.contains("BEGIN TRANSLATION"),
        "Should have translation placeholder"
    );
}

// -----------------------------------------------------------------------
// Test 7: Generated TLC config has correct structure
// -----------------------------------------------------------------------

#[test]
fn test_generated_tlc_config_structure() {
    let (_dir, path) = write_manifest(MUTEX_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");

    let output_dir = TempDir::new().expect("Failed to create output dir");
    let output_path = output_dir.path().to_str().unwrap();
    codegen::generate_all(&m, output_path).expect("Code generation should succeed");

    let cfg_content = fs::read_to_string(output_dir.path().join("MutexProtocol.cfg"))
        .expect("Failed to read TLC config");

    // Specification (FairSpec because we have liveness properties)
    assert!(
        cfg_content.contains("SPECIFICATION FairSpec"),
        "Should use FairSpec due to liveness properties"
    );

    // Constants
    assert!(
        cfg_content.contains("CONSTANT Idle = Idle"),
        "Should map state constants"
    );

    // Invariants
    assert!(
        cfg_content.contains("INVARIANT TypeInvariant"),
        "Should include TypeInvariant"
    );
    assert!(
        cfg_content.contains("INVARIANT TypeSafe"),
        "Should include TypeSafe safety property as invariant"
    );

    // Temporal properties
    assert!(
        cfg_content.contains("PROPERTY EventualEntry"),
        "Should include EventualEntry liveness property"
    );
}

// -----------------------------------------------------------------------
// Test 8: Generated run script is valid bash
// -----------------------------------------------------------------------

#[test]
fn test_generated_run_script() {
    let (_dir, path) = write_manifest(MUTEX_MANIFEST);
    let m = manifest::load_manifest(&path).expect("Failed to load manifest");

    let output_dir = TempDir::new().expect("Failed to create output dir");
    let output_path = output_dir.path().to_str().unwrap();
    codegen::generate_all(&m, output_path).expect("Code generation should succeed");

    let script_content = fs::read_to_string(output_dir.path().join("run_tlc_MutexProtocol.sh"))
        .expect("Failed to read run script");

    assert!(
        script_content.starts_with("#!/usr/bin/env bash"),
        "Should have bash shebang"
    );
    assert!(
        script_content.contains("set -euo pipefail"),
        "Should use strict mode"
    );
    assert!(
        script_content.contains("-workers 4"),
        "Should pass workers from config"
    );
    assert!(
        script_content.contains("MutexProtocol.tla"),
        "Should reference the TLA+ spec"
    );
}

// -----------------------------------------------------------------------
// Test 9: Init manifest creates valid template
// -----------------------------------------------------------------------

#[test]
fn test_init_manifest_creates_template() {
    let dir = TempDir::new().expect("Failed to create temp dir");
    let dir_path = dir.path().to_str().unwrap();

    manifest::init_manifest(dir_path).expect("init_manifest should succeed");

    let manifest_path = dir.path().join("tlaiser.toml");
    assert!(manifest_path.exists(), "tlaiser.toml should be created");

    // The template should be parseable and valid
    let m = manifest::load_manifest(manifest_path.to_str().unwrap())
        .expect("Template should be parseable");
    manifest::validate(&m).expect("Template should be valid");

    // Should have the expected structure
    assert_eq!(m.state_machines.len(), 1);
    assert!(!m.properties.is_empty());
}

// -----------------------------------------------------------------------
// Test 10: Init manifest refuses to overwrite
// -----------------------------------------------------------------------

#[test]
fn test_init_manifest_refuses_overwrite() {
    let dir = TempDir::new().expect("Failed to create temp dir");
    let dir_path = dir.path().to_str().unwrap();

    // First init succeeds
    manifest::init_manifest(dir_path).expect("First init should succeed");

    // Second init fails
    let result = manifest::init_manifest(dir_path);
    assert!(
        result.is_err(),
        "Should refuse to overwrite existing manifest"
    );
}

// -----------------------------------------------------------------------
// Test 11: Mutex protocol example is valid
// -----------------------------------------------------------------------

#[test]
fn test_mutex_example_is_valid() {
    // This test validates the actual example file shipped with the repo.
    let example_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/examples/mutex-protocol/tlaiser.toml"
    );

    let m = manifest::load_manifest(example_path).expect("Example manifest should be parseable");
    manifest::validate(&m).expect("Example manifest should be valid");

    assert_eq!(m.project.name, "mutex-protocol");
    assert_eq!(m.state_machines[0].name, "MutexProtocol");
    assert_eq!(m.state_machines[0].states.len(), 3);
    assert_eq!(m.state_machines[0].transitions.len(), 3);
    assert!(m.properties.len() >= 2);
}

// -----------------------------------------------------------------------
// Test 12: End-to-end generation from example
// -----------------------------------------------------------------------

#[test]
fn test_end_to_end_mutex_example() {
    let example_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/examples/mutex-protocol/tlaiser.toml"
    );

    let output_dir = TempDir::new().expect("Failed to create output dir");
    let output_path = output_dir.path().to_str().unwrap();

    tlaiser::generate(example_path, output_path).expect("End-to-end generation should succeed");

    // Verify all artifacts exist
    assert!(output_dir.path().join("MutexProtocol.tla").exists());
    assert!(output_dir.path().join("MutexProtocolPlusCal.tla").exists());
    assert!(output_dir.path().join("MutexProtocol.cfg").exists());
    assert!(output_dir.path().join("run_tlc_MutexProtocol.sh").exists());

    // Read and verify the TLA+ spec has temporal properties
    let tla = fs::read_to_string(output_dir.path().join("MutexProtocol.tla")).unwrap();
    assert!(tla.contains("[](")); // safety
    assert!(tla.contains("<>(")); // liveness
    assert!(tla.contains("WF_vars(Next)")); // fairness in FairSpec
}
