// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for oblibeniser Phase 1.
// Tests the full pipeline: manifest parsing → codegen → ABI types → audit trails.

use oblibeniser::abi::{
    AuditTrail, InverseStrategy, TimeTravel, TimeTravelDirection, UndoEntry, UndoStack,
};
use oblibeniser::codegen::audit_gen;
use oblibeniser::codegen::inverse_gen;
use oblibeniser::codegen::parser;
use oblibeniser::manifest;

/// Helper: create a standard test manifest TOML string with all sections populated.
fn full_manifest_toml() -> &'static str {
    r#"
[project]
name = "integration-test"
version = "1.0.0"
description = "Full integration test manifest"

[[operations]]
name = "db_insert"
forward-fn = "database::insert"
params = ["key:String", "value:Vec<u8>"]
inverse-strategy = "mirror"

[[operations]]
name = "db_update"
forward-fn = "database::update"
params = ["id:u64", "field:String", "new_value:String"]
inverse-strategy = "log-replay"

[[operations]]
name = "schema_migrate"
forward-fn = "schema::migrate"
params = ["version:u32"]
inverse-strategy = "snapshot"

[audit]
hash-chain = true
storage = "file"
max-entries = 1000

[undo]
max-depth = 50
auto-checkpoint-interval = 10
"#
}

// ============================================================================
// Test 1: Full manifest parse → validate → codegen pipeline
// ============================================================================

#[test]
fn test_full_pipeline_manifest_to_codegen() {
    let toml = full_manifest_toml();

    // Parse the manifest.
    let manifest = manifest::parse_manifest(toml).expect("Manifest should parse");
    assert_eq!(manifest.project.name, "integration-test");
    assert_eq!(manifest.operations.len(), 3);

    // Validate the manifest.
    manifest::validate(&manifest).expect("Manifest should be valid");

    // Parse into codegen structures.
    let parsed = parser::parse_manifest(&manifest).expect("Codegen parse should succeed");
    assert_eq!(parsed.operations.len(), 3);
    assert_eq!(
        parsed.operations[0].inverse_strategy,
        InverseStrategy::Mirror
    );
    assert_eq!(
        parsed.operations[1].inverse_strategy,
        InverseStrategy::LogReplay
    );
    assert_eq!(
        parsed.operations[2].inverse_strategy,
        InverseStrategy::Snapshot
    );

    // Validate operations for logical consistency.
    parser::validate_operations(&parsed).expect("Operations should be valid");

    // Generate inverse functions.
    let inverses =
        inverse_gen::generate_inverses(&parsed).expect("Inverse generation should succeed");
    assert_eq!(inverses.len(), 3);

    // Verify each inverse has the correct function name and strategy.
    assert_eq!(inverses[0].function_name, "db_insert_inverse");
    assert_eq!(inverses[1].function_name, "db_update_inverse");
    assert_eq!(inverses[2].function_name, "schema_migrate_inverse");

    // Generate the full inverse module.
    let module =
        inverse_gen::generate_inverse_module(&parsed).expect("Module generation should succeed");
    assert!(module.contains("pub fn db_insert_inverse"));
    assert!(module.contains("pub fn db_update_inverse"));
    assert!(module.contains("pub fn schema_migrate_inverse"));

    // Generate the audit module.
    let audit = audit_gen::generate_audit_module(&parsed).expect("Audit generation should succeed");
    assert!(audit.module_code.contains("\"db_insert\""));
    assert!(audit.module_code.contains("\"db_update\""));
    assert!(audit.module_code.contains("\"schema_migrate\""));
}

// ============================================================================
// Test 2: Audit trail hash-chain integrity
// ============================================================================

#[test]
fn test_audit_trail_hash_chain_integrity() {
    let mut trail = AuditTrail::new(0, true);

    // Record a series of operations.
    trail.record("insert", "key1_hash");
    trail.record("update", "key2_hash");
    trail.record("delete", "key3_hash");
    trail.record("insert", "key4_hash");
    trail.record("migrate", "v2_hash");

    assert_eq!(trail.len(), 5);

    // Verify the chain is intact.
    assert!(
        trail.verify_chain().is_none(),
        "Hash chain should be intact after normal recording"
    );

    // Verify that each entry links to the previous one.
    for i in 1..trail.entries.len() {
        assert_eq!(
            trail.entries[i].prev_hash,
            trail.entries[i - 1].entry_hash,
            "Entry {} should link to entry {}",
            i,
            i - 1
        );
    }

    // Verify individual entry self-consistency.
    for entry in &trail.entries {
        assert!(
            entry.verify(),
            "Entry {} should be self-consistent",
            entry.sequence
        );
    }

    // Tamper with an entry and verify the chain detects it.
    let mut tampered_trail = trail.clone();
    tampered_trail.entries[2].operation_name = "TAMPERED".to_string();
    assert!(
        tampered_trail.verify_chain().is_some(),
        "Tampered chain should be detected"
    );
    assert_eq!(
        tampered_trail.verify_chain().unwrap(),
        2,
        "Tamper should be detected at index 2"
    );
}

// ============================================================================
// Test 3: Undo/redo stack with depth limits
// ============================================================================

#[test]
fn test_undo_redo_stack_depth_and_ordering() {
    let mut stack = UndoStack::new(5, 0);

    // Push 7 operations (exceeding max_depth of 5).
    for i in 0..7 {
        stack.push(UndoEntry {
            operation_name: format!("op_{}", i),
            forward_params: vec![i as u8],
            inverse_params: vec![255 - i as u8],
            snapshot: None,
            audit_sequence: i as u64,
        });
    }

    // Only the last 5 should remain.
    assert_eq!(stack.undo_depth(), 5);

    // Undo should return operations in reverse order (most recent first).
    let u1 = stack.undo().unwrap();
    assert_eq!(u1.operation_name, "op_6");
    let u2 = stack.undo().unwrap();
    assert_eq!(u2.operation_name, "op_5");

    // Redo should return them in forward order.
    assert_eq!(stack.redo_depth(), 2);
    let r1 = stack.redo().unwrap();
    assert_eq!(r1.operation_name, "op_5");

    // New push should clear redo stack.
    stack.push(UndoEntry {
        operation_name: "new_op".to_string(),
        forward_params: vec![],
        inverse_params: vec![],
        snapshot: None,
        audit_sequence: 7,
    });
    assert_eq!(
        stack.redo_depth(),
        0,
        "Redo should be cleared after new push"
    );

    // Verify undo still works after the new push.
    let u3 = stack.undo().unwrap();
    assert_eq!(u3.operation_name, "new_op");
}

// ============================================================================
// Test 4: Time-travel forward and backward navigation
// ============================================================================

#[test]
fn test_time_travel_navigation() {
    let mut tt = TimeTravel::new(100, true, 100, 0);

    // Record 5 operations.
    for i in 0..5 {
        tt.record_operation(
            &format!("op_{}", i),
            &format!("hash_{}", i),
            vec![i as u8],
            vec![255 - i as u8],
            if i % 2 == 0 {
                Some(vec![i as u8; 10])
            } else {
                None
            },
        );
    }

    assert_eq!(tt.current_position, 4);
    assert_eq!(tt.audit_trail.len(), 5);

    // Travel backward to position 1.
    let backward_steps = tt.travel_to(1);
    assert_eq!(
        backward_steps.len(),
        3,
        "Should undo 3 operations (4→3→2→1)"
    );
    assert_eq!(tt.current_position, 1);
    for step in &backward_steps {
        assert_eq!(step.direction, TimeTravelDirection::Backward);
    }

    // Travel forward to position 3.
    let forward_steps = tt.travel_to(3);
    assert_eq!(forward_steps.len(), 2, "Should redo 2 operations (1→2→3)");
    assert_eq!(tt.current_position, 3);
    for step in &forward_steps {
        assert_eq!(step.direction, TimeTravelDirection::Forward);
    }

    // Travel to current position should be a no-op.
    let noop_steps = tt.travel_to(3);
    assert!(
        noop_steps.is_empty(),
        "Travel to current position should be no-op"
    );
}

// ============================================================================
// Test 5: Codegen generates correct code for all three strategies
// ============================================================================

#[test]
fn test_codegen_all_strategies_generate_valid_code() {
    let toml = full_manifest_toml();
    let manifest = manifest::parse_manifest(toml).unwrap();
    let parsed = parser::parse_manifest(&manifest).unwrap();
    let module = inverse_gen::generate_inverse_module(&parsed).unwrap();

    // Mirror strategy: should contain mirror-specific constructs.
    assert!(
        module.contains("Mirror inverse of `database::insert`"),
        "Mirror inverse should reference the forward function"
    );
    assert!(
        module.contains("mirror_undo"),
        "Mirror strategy should generate _mirror_undo helper"
    );

    // Log-replay strategy: should contain mutation log constructs.
    assert!(
        module.contains("Log-replay inverse of `database::update`"),
        "Log-replay inverse should reference the forward function"
    );
    assert!(
        module.contains("mutation_log"),
        "Log-replay strategy should use mutation_log parameter"
    );
    assert!(
        module.contains("MutationLog"),
        "Log-replay should reference the MutationLog type"
    );

    // Snapshot strategy: should contain state restoration constructs.
    assert!(
        module.contains("Snapshot inverse of `schema::migrate`"),
        "Snapshot inverse should reference the forward function"
    );
    assert!(
        module.contains("restore_state"),
        "Snapshot strategy should call restore_state"
    );
    assert!(
        module.contains("StateSnapshot"),
        "Snapshot should reference the StateSnapshot type"
    );

    // All strategies should record to the audit trail.
    assert!(
        module.contains("AUDIT_TRAIL.lock()"),
        "All strategies should record to the audit trail"
    );
}

// ============================================================================
// Test 6: End-to-end file generation with tempdir
// ============================================================================

#[test]
fn test_end_to_end_file_generation() {
    let dir = tempfile::tempdir().expect("Failed to create temp dir");
    let manifest_path = dir.path().join("oblibeniser.toml");

    // Write a manifest file.
    std::fs::write(&manifest_path, full_manifest_toml()).expect("Failed to write manifest");

    // Load, validate, and generate.
    let output_dir = dir.path().join("generated");
    oblibeniser::generate(
        manifest_path.to_str().unwrap(),
        output_dir.to_str().unwrap(),
    )
    .expect("Generation should succeed");

    // Verify all expected files were created.
    assert!(
        output_dir.join("inverses.rs").exists(),
        "inverses.rs should exist"
    );
    assert!(
        output_dir.join("audit.rs").exists(),
        "audit.rs should exist"
    );
    assert!(
        output_dir.join("verify_audit.rs").exists(),
        "verify_audit.rs should exist"
    );
    assert!(
        output_dir.join("summary.txt").exists(),
        "summary.txt should exist"
    );

    // Verify content of generated files.
    let inverses = std::fs::read_to_string(output_dir.join("inverses.rs")).unwrap();
    assert!(inverses.contains("SPDX-License-Identifier: MPL-2.0"));
    assert!(inverses.contains("pub fn db_insert_inverse"));

    let audit = std::fs::read_to_string(output_dir.join("audit.rs")).unwrap();
    assert!(audit.contains("hash_chain_enabled: true"));
    assert!(audit.contains("max_entries: 1000"));

    let summary = std::fs::read_to_string(output_dir.join("summary.txt")).unwrap();
    assert!(summary.contains("integration-test"));
    assert!(summary.contains("Operations: 3"));
}

// ============================================================================
// Test 7: Manifest validation rejects invalid configurations
// ============================================================================

#[test]
fn test_manifest_validation_rejects_invalid() {
    // Empty project name.
    let bad_name = r#"
[project]
name = ""
"#;
    let m = manifest::parse_manifest(bad_name).unwrap();
    assert!(
        manifest::validate(&m).is_err(),
        "Empty project name should fail"
    );

    // Invalid inverse strategy.
    let bad_strategy = r#"
[project]
name = "test"

[[operations]]
name = "op"
forward-fn = "fn"
inverse-strategy = "quantum-undo"
"#;
    let m = manifest::parse_manifest(bad_strategy).unwrap();
    assert!(
        manifest::validate(&m).is_err(),
        "Invalid strategy should fail"
    );

    // Invalid storage backend.
    let bad_storage = r#"
[project]
name = "test"

[audit]
storage = "blockchain"
"#;
    let m = manifest::parse_manifest(bad_storage).unwrap();
    assert!(
        manifest::validate(&m).is_err(),
        "Invalid storage should fail"
    );

    // Duplicate operation names (caught by parser validation).
    let dup_ops = r#"
[project]
name = "test"

[[operations]]
name = "same"
forward-fn = "a"
params = ["x:i32"]
inverse-strategy = "mirror"

[[operations]]
name = "same"
forward-fn = "b"
params = ["y:i32"]
inverse-strategy = "mirror"
"#;
    let m = manifest::parse_manifest(dup_ops).unwrap();
    let parsed = parser::parse_manifest(&m).unwrap();
    assert!(
        parser::validate_operations(&parsed).is_err(),
        "Duplicate operation names should fail"
    );
}

// ============================================================================
// Test 8: TimeTravel snapshots enable efficient state restoration
// ============================================================================

#[test]
fn test_time_travel_snapshots() {
    let mut tt = TimeTravel::new(100, true, 100, 5);

    // Record operations, some with snapshots.
    for i in 0..10 {
        let snapshot_data = if i % 3 == 0 {
            Some(format!("state_at_{}", i).into_bytes())
        } else {
            None
        };
        tt.record_operation(
            &format!("op_{}", i),
            &format!("h_{}", i),
            vec![i as u8],
            vec![],
            snapshot_data,
        );
    }

    // Verify snapshots were stored (at indices 0, 3, 6, 9).
    assert_eq!(tt.snapshots.len(), 4);

    // Find nearest snapshot to sequence 7.
    let snap = tt.nearest_snapshot(7).expect("Should find a snapshot");
    assert_eq!(
        snap.at_sequence, 6,
        "Nearest snapshot at or before 7 should be 6"
    );
    assert_eq!(snap.data, b"state_at_6");

    // Find nearest snapshot to sequence 2.
    let snap = tt.nearest_snapshot(2).expect("Should find a snapshot");
    assert_eq!(
        snap.at_sequence, 0,
        "Nearest snapshot at or before 2 should be 0"
    );

    // No snapshot before sequence 0 should exist (but 0 itself has one).
    let snap = tt.nearest_snapshot(0).expect("Should find snapshot at 0");
    assert_eq!(snap.at_sequence, 0);
}
