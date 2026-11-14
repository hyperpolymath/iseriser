// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for ponyiser.
//
// Tests the full pipeline: manifest parsing -> capability analysis -> code generation.
// Each test exercises a different aspect of Pony reference capability wrapping.

use ponyiser::abi::{
    Actor, Behaviour, BehaviourParam, Field, RefCapability, check_subtype, is_subtype,
    validate_sendability,
};
use ponyiser::codegen::capability::{analyse, infer_capability};
use ponyiser::codegen::parser::parse_definitions;
use ponyiser::codegen::pony_gen::{GenerationOptions, generate_pony_files};
use ponyiser::manifest::{parse_manifest, validate};

use std::fs;
use tempfile::TempDir;

// ---------------------------------------------------------------------------
// Test 1: Full pipeline — manifest to .pony output (concurrent server)
// ---------------------------------------------------------------------------

#[test]
fn test_full_pipeline_concurrent_server() {
    let toml = r#"
[project]
name = "concurrent-server"
version = "0.1.0"
description = "A concurrent TCP server with Pony capability safety"
source_lang = "rust"

[[actors]]
name = "Listener"
doc = "Listens for incoming TCP connections"

[[actors.fields]]
name = "port"
type = "U16"
capability = "val"

[[actors.fields]]
name = "connections"
type = "Array[TCPConnection]"
capability = "ref"

[[actors]]
name = "Handler"
doc = "Handles a single client connection"

[[actors.fields]]
name = "conn"
type = "TCPConnection"
capability = "iso"

[[actors.fields]]
name = "buffer"
type = "Array[U8]"
capability = "iso"

[[behaviours]]
actor = "Listener"
name = "accept"
doc = "Accept a new connection and spawn a handler"

[[behaviours.params]]
name = "conn"
type = "TCPConnection"
capability = "iso"

[[behaviours]]
actor = "Handler"
name = "received"
doc = "Handle received data"

[[behaviours.params]]
name = "data"
type = "Array[U8]"
capability = "val"

[[behaviours]]
actor = "Handler"
name = "closed"
doc = "Handle connection close"

[analysis]
detect-races = true
suggest-capabilities = true
"#;

    // Parse manifest.
    let manifest = parse_manifest(toml).expect("Failed to parse manifest");
    assert_eq!(manifest.project.name, "concurrent-server");
    assert_eq!(manifest.actors.len(), 2);
    assert_eq!(manifest.behaviours.len(), 3);

    // Validate manifest.
    validate(&manifest).expect("Manifest validation failed");

    // Parse definitions.
    let defs = parse_definitions(&manifest).expect("Failed to parse definitions");
    assert_eq!(defs.actors.len(), 2);
    assert_eq!(defs.behaviours.len(), 3);

    // Run capability analysis.
    let result = analyse(&defs.actors, &defs.behaviours, true);
    assert!(
        result.is_race_free,
        "Expected race-free system, got violations: {:?}",
        result.violations
    );

    // Generate Pony files.
    let files =
        generate_pony_files(&defs, &GenerationOptions::default()).expect("Code generation failed");
    assert_eq!(files.len(), 2, "Expected 2 .pony files (one per actor)");

    // Verify Listener file content.
    let listener_file = files
        .iter()
        .find(|f| f.filename == "listener.pony")
        .unwrap();
    assert!(
        listener_file.content.contains("actor Listener"),
        "Should declare Listener actor"
    );
    assert!(
        listener_file.content.contains("var _port: U16 val"),
        "Should have val port field"
    );
    assert!(
        listener_file
            .content
            .contains("var _connections: Array[TCPConnection] ref"),
        "Should have ref connections field"
    );
    assert!(
        listener_file
            .content
            .contains("be accept(conn: TCPConnection iso)"),
        "Should have accept behaviour with iso parameter"
    );

    // Verify Handler file content.
    let handler_file = files.iter().find(|f| f.filename == "handler.pony").unwrap();
    assert!(
        handler_file.content.contains("actor Handler"),
        "Should declare Handler actor"
    );
    assert!(
        handler_file
            .content
            .contains("be received(data: Array[U8] val)"),
        "Should have received behaviour with val parameter"
    );
}

// ---------------------------------------------------------------------------
// Test 2: Capability subtyping lattice completeness
// ---------------------------------------------------------------------------

#[test]
fn test_capability_subtyping_lattice() {
    // Reflexivity: every capability is subtype of itself.
    for cap in RefCapability::all() {
        assert!(is_subtype(*cap, *cap), "{} <: {} should hold", cap, cap);
    }

    // iso is top (most specific) — subtype of everything.
    for cap in RefCapability::all() {
        assert!(
            is_subtype(RefCapability::Iso, *cap),
            "iso <: {} should hold",
            cap
        );
    }

    // tag is bottom — everything is subtype of tag.
    for cap in RefCapability::all() {
        assert!(
            is_subtype(*cap, RefCapability::Tag),
            "{} <: tag should hold",
            cap
        );
    }

    // Read path: val -> box -> tag
    assert!(is_subtype(RefCapability::Val, RefCapability::Box));
    assert!(is_subtype(RefCapability::Box, RefCapability::Tag));
    assert!(is_subtype(RefCapability::Val, RefCapability::Tag));

    // Write path: ref -> box -> tag
    assert!(is_subtype(RefCapability::Ref, RefCapability::Box));
    assert!(is_subtype(RefCapability::Box, RefCapability::Tag));

    // Transitional path: trn -> ref, trn -> val
    assert!(is_subtype(RefCapability::Trn, RefCapability::Ref));
    assert!(is_subtype(RefCapability::Trn, RefCapability::Val));
    assert!(is_subtype(RefCapability::Trn, RefCapability::Box));
    assert!(is_subtype(RefCapability::Trn, RefCapability::Tag));

    // Negative tests: incomparable pairs.
    assert!(
        !is_subtype(RefCapability::Ref, RefCapability::Val),
        "ref <: val should NOT hold"
    );
    assert!(
        !is_subtype(RefCapability::Val, RefCapability::Ref),
        "val <: ref should NOT hold"
    );
    assert!(
        !is_subtype(RefCapability::Tag, RefCapability::Box),
        "tag <: box should NOT hold"
    );
    assert!(
        !is_subtype(RefCapability::Box, RefCapability::Val),
        "box <: val should NOT hold"
    );
    assert!(
        !is_subtype(RefCapability::Box, RefCapability::Ref),
        "box <: ref should NOT hold"
    );
}

// ---------------------------------------------------------------------------
// Test 3: Sendability violations detected
// ---------------------------------------------------------------------------

#[test]
fn test_sendability_violation_detection() {
    let actors = vec![Actor {
        name: "Worker".to_string(),
        fields: vec![],
        doc: None,
    }];

    // Behaviour with a ref parameter — NOT sendable across actor boundaries.
    let behaviours = vec![Behaviour {
        actor: "Worker".to_string(),
        name: "process".to_string(),
        params: vec![BehaviourParam {
            name: "shared_data".to_string(),
            param_type: "Buffer".to_string(),
            capability: RefCapability::Ref, // ref is NOT sendable
        }],
        capability_requirements: vec![],
        doc: None,
    }];

    let result = analyse(&actors, &behaviours, false);
    assert!(!result.is_race_free, "Should detect sendability violation");
    assert_eq!(result.violations.len(), 1);
    assert_eq!(result.violations[0].target, "shared_data");
    assert!(
        result.violations[0].message.contains("not sendable"),
        "Violation message should mention sendability"
    );

    // Now test with val (sendable) — should pass.
    let clean_behaviours = vec![Behaviour {
        actor: "Worker".to_string(),
        name: "process".to_string(),
        params: vec![BehaviourParam {
            name: "data".to_string(),
            param_type: "Buffer".to_string(),
            capability: RefCapability::Val, // val IS sendable
        }],
        capability_requirements: vec![],
        doc: None,
    }];

    let clean_result = analyse(&actors, &clean_behaviours, false);
    assert!(
        clean_result.is_race_free,
        "val parameters should be race-free"
    );
}

// ---------------------------------------------------------------------------
// Test 4: Capability inference engine
// ---------------------------------------------------------------------------

#[test]
fn test_capability_inference() {
    // Sent + written = iso (unique mutable, sendable).
    assert_eq!(
        infer_capability(true, true, false, true),
        RefCapability::Iso
    );

    // Sent + read-only = val (shared immutable, sendable).
    assert_eq!(
        infer_capability(true, false, false, true),
        RefCapability::Val
    );

    // Sent + identity-only = tag (sendable, no access).
    assert_eq!(
        infer_capability(false, false, false, true),
        RefCapability::Tag
    );

    // Local + written + not shared = ref (local mutable).
    assert_eq!(
        infer_capability(true, true, false, false),
        RefCapability::Ref
    );

    // Local + read-only + shared = box (read-only aliasable).
    assert_eq!(
        infer_capability(true, false, true, false),
        RefCapability::Box
    );

    // Local + read-only + not shared = val (immutable).
    assert_eq!(
        infer_capability(true, false, false, false),
        RefCapability::Val
    );

    // Neither read nor written = tag.
    assert_eq!(
        infer_capability(false, false, false, false),
        RefCapability::Tag
    );
}

// ---------------------------------------------------------------------------
// Test 5: Manifest validation catches errors
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_validation_errors() {
    // Empty project name.
    let result = parse_manifest(
        r#"
[project]
name = ""
"#,
    );
    let manifest = result.unwrap();
    assert!(validate(&manifest).is_err(), "Empty name should fail");

    // Duplicate actor names.
    let dup_manifest = parse_manifest(
        r#"
[project]
name = "test"

[[actors]]
name = "Dup"

[[actors]]
name = "Dup"
"#,
    )
    .unwrap();
    assert!(
        validate(&dup_manifest).is_err(),
        "Duplicate actor names should fail"
    );

    // Behaviour references undefined actor.
    let bad_ref = parse_manifest(
        r#"
[project]
name = "test"

[[actors]]
name = "Real"

[[behaviours]]
actor = "Ghost"
name = "haunt"
"#,
    )
    .unwrap();
    assert!(
        validate(&bad_ref).is_err(),
        "Reference to undefined actor should fail"
    );

    // Valid manifest should pass.
    let valid = parse_manifest(
        r#"
[project]
name = "valid"

[[actors]]
name = "Main"

[[behaviours]]
actor = "Main"
name = "run"
"#,
    )
    .unwrap();
    assert!(validate(&valid).is_ok(), "Valid manifest should pass");
}

// ---------------------------------------------------------------------------
// Test 6: End-to-end file generation to disk
// ---------------------------------------------------------------------------

#[test]
fn test_file_generation_to_disk() {
    let toml = r#"
[project]
name = "chat-server"
version = "0.2.0"
description = "Multi-room chat server"

[[actors]]
name = "Room"
doc = "A chat room actor"

[[actors.fields]]
name = "members"
type = "Array[Client]"
capability = "ref"

[[actors.fields]]
name = "name"
type = "String"
capability = "val"

[[actors]]
name = "Client"
doc = "A connected client"

[[actors.fields]]
name = "conn"
type = "TCPConnection"
capability = "iso"

[[behaviours]]
actor = "Room"
name = "join"
doc = "A client joins the room"

[[behaviours.params]]
name = "client"
type = "Client"
capability = "tag"

[[behaviours]]
actor = "Room"
name = "broadcast"
doc = "Send a message to all members"

[[behaviours.params]]
name = "message"
type = "String"
capability = "val"

[[behaviours]]
actor = "Client"
name = "send"
doc = "Send data to the client"

[[behaviours.params]]
name = "data"
type = "Array[U8]"
capability = "val"

[analysis]
detect-races = true
suggest-capabilities = true
"#;

    let manifest = parse_manifest(toml).expect("Parse failed");
    validate(&manifest).expect("Validation failed");

    let defs = parse_definitions(&manifest).expect("Parse definitions failed");
    let result = analyse(&defs.actors, &defs.behaviours, true);
    assert!(result.is_race_free, "Chat server should be race-free");

    // Write to temp directory.
    let tmp_dir = TempDir::new().expect("Failed to create temp dir");
    let output_path = tmp_dir.path().join("pony_output");
    fs::create_dir_all(&output_path).expect("Failed to create output dir");

    let files =
        generate_pony_files(&defs, &GenerationOptions::default()).expect("Generation failed");
    assert_eq!(files.len(), 2);

    for file in &files {
        let path = output_path.join(&file.filename);
        fs::write(&path, &file.content).expect("Failed to write file");
        assert!(path.exists(), "Generated file should exist on disk");
        let read_back = fs::read_to_string(&path).expect("Failed to read back");
        assert_eq!(read_back, file.content, "File content should match");
    }

    // Verify Room file.
    let room_content = fs::read_to_string(output_path.join("room.pony")).unwrap();
    assert!(room_content.contains("actor Room"));
    assert!(room_content.contains("be join(client: Client tag)"));
    assert!(room_content.contains("be broadcast(message: String val)"));

    // Verify Client file.
    let client_content = fs::read_to_string(output_path.join("client.pony")).unwrap();
    assert!(client_content.contains("actor Client"));
    assert!(client_content.contains("be send(data: Array[U8] val)"));
}

// ---------------------------------------------------------------------------
// Test 7: SubtypingResult API
// ---------------------------------------------------------------------------

#[test]
fn test_subtyping_result_api() {
    // Valid subtyping.
    let valid = check_subtype(RefCapability::Iso, RefCapability::Val);
    assert!(valid.is_valid());

    // Invalid subtyping.
    let invalid = check_subtype(RefCapability::Tag, RefCapability::Val);
    assert!(!invalid.is_valid());

    match invalid {
        ponyiser::SubtypingResult::Invalid { sub, sup, reason } => {
            assert_eq!(sub, RefCapability::Tag);
            assert_eq!(sup, RefCapability::Val);
            assert!(reason.contains("not a subtype"));
        }
        _ => panic!("Expected Invalid result"),
    }
}

// ---------------------------------------------------------------------------
// Test 8: Validate sendability across actor boundaries
// ---------------------------------------------------------------------------

#[test]
fn test_cross_actor_sendability() {
    let actors = vec![
        Actor {
            name: "Producer".to_string(),
            fields: vec![Field {
                name: "buffer".to_string(),
                field_type: "Array[U8]".to_string(),
                capability: RefCapability::Iso,
            }],
            doc: None,
        },
        Actor {
            name: "Consumer".to_string(),
            fields: vec![Field {
                name: "data".to_string(),
                field_type: "Array[U8]".to_string(),
                capability: RefCapability::Val,
            }],
            doc: None,
        },
    ];

    // box parameter is not sendable.
    let bad_behaviours = vec![Behaviour {
        actor: "Consumer".to_string(),
        name: "consume".to_string(),
        params: vec![BehaviourParam {
            name: "payload".to_string(),
            param_type: "Array[U8]".to_string(),
            capability: RefCapability::Box, // NOT sendable
        }],
        capability_requirements: vec![],
        doc: None,
    }];

    let violations = validate_sendability(&actors, &bad_behaviours);
    assert_eq!(violations.len(), 1);
    assert_eq!(violations[0].found, RefCapability::Box);
    assert!(violations[0].message.contains("not sendable"));

    // iso parameter IS sendable.
    let good_behaviours = vec![Behaviour {
        actor: "Consumer".to_string(),
        name: "consume".to_string(),
        params: vec![BehaviourParam {
            name: "payload".to_string(),
            param_type: "Array[U8]".to_string(),
            capability: RefCapability::Iso, // sendable
        }],
        capability_requirements: vec![],
        doc: None,
    }];

    let no_violations = validate_sendability(&actors, &good_behaviours);
    assert!(no_violations.is_empty());
}
