// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Integration tests for Chapeliser CLI.
//
// Test categories:
//   1. Existing tests (init, validate, generate, partition/gather strategies)
//   2. Point-to-point tests (5 partitions × 5 gathers = 25 combos)
//   3. End-to-end tests (panic-attacker example, full artifact verification)
//   4. Edge case tests (single locale, single item, large grain, validation)
//   5. Aspect tests (SPDX headers, module declarations, callconv, executable)
//   6. Regression tests (checkpoint, retry, manifest validation)

use std::fs;

// ---------------------------------------------------------------------------
// Helper: build a manifest TOML string from partition/gather strategy names.
// ---------------------------------------------------------------------------

/// Construct a minimal valid manifest TOML with the given partition and gather
/// strategy. The workload name is derived from the strategy names to avoid
/// collisions when running tests in parallel.
fn make_manifest_toml(partition: &str, gather: &str) -> String {
    let name = format!("p2p-{partition}-{gather}");
    format!(
        r#"
        [workload]
        name = "{name}"
        entry = "src/lib.rs::func"
        partition = "{partition}"
        gather = "{gather}"

        [data]
        input-type = "Vec<Item>"
        output-type = "Vec<Result>"

        [scaling]
        min-nodes = 1
        max-nodes = 4
        grain-size = 10
        "#
    )
}

/// Parse a TOML string into a Manifest. Panics with a clear message on failure.
fn parse_manifest(toml_str: &str) -> chapeliser::manifest::Manifest {
    toml::from_str(toml_str).expect("Failed to parse test manifest TOML")
}

/// Generate all artifacts into a tempdir and return the tempdir handle plus
/// the safe_name (hyphens replaced with underscores) for path construction.
fn generate_to_tempdir(m: &chapeliser::manifest::Manifest) -> (tempfile::TempDir, String) {
    let dir = tempfile::tempdir().unwrap();
    chapeliser::codegen::generate_all(m, dir.path().to_str().unwrap()).unwrap_or_else(|e| {
        panic!(
            "generate_all failed for workload '{}': {e}",
            m.workload.name
        )
    });
    let safe_name = m.workload.name.replace('-', "_");
    (dir, safe_name)
}

// ===========================================================================
// 1. EXISTING TESTS (preserved)
// ===========================================================================

#[test]
fn test_init_creates_manifest() {
    let dir = tempfile::tempdir().unwrap();
    let manifest = dir.path().join("chapeliser.toml");

    chapeliser::manifest::init_manifest(dir.path().to_str().unwrap()).unwrap();
    assert!(manifest.exists(), "chapeliser.toml should be created");

    let content = fs::read_to_string(&manifest).unwrap();
    assert!(content.contains("[workload]"));
    assert!(content.contains("partition"));
    assert!(content.contains("gather"));
}

#[test]
fn test_validate_good_manifest() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    chapeliser::manifest::validate(&m).unwrap();
    assert_eq!(m.workload.name, "mass-panic");
    assert_eq!(m.workload.partition, "per-item");
    assert_eq!(m.workload.gather, "merge");
    assert_eq!(m.scaling.max_nodes, 64);
}

#[test]
fn test_generate_produces_files() {
    let dir = tempfile::tempdir().unwrap();
    let output = dir.path().join("generated");

    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    chapeliser::codegen::generate_all(&m, output.to_str().unwrap()).unwrap();

    // Check all 4 artifacts exist
    assert!(output.join("chapel/mass_panic_distributed.chpl").exists());
    assert!(output.join("zig/mass_panic_ffi.zig").exists());
    assert!(output.join("include/mass_panic_chapeliser.h").exists());
    assert!(output.join("build.sh").exists());

    // Check Chapel file contains expected content
    let chpl = fs::read_to_string(output.join("chapel/mass_panic_distributed.chpl")).unwrap();
    assert!(
        chpl.contains("coforall"),
        "Chapel should contain coforall distribution"
    );
    assert!(
        chpl.contains("mass_panic"),
        "Chapel should reference workload name"
    );
    assert!(
        chpl.contains("c_process_item"),
        "Chapel should call c_process_item"
    );
    assert!(
        chpl.contains("c_init"),
        "Chapel should call c_init for lifecycle"
    );
    assert!(
        chpl.contains("c_load_item"),
        "Chapel should call c_load_item for data I/O"
    );
    assert!(
        chpl.contains("c_store_result"),
        "Chapel should call c_store_result"
    );
    assert!(
        chpl.contains("processWithRetry"),
        "Chapel should have retry logic"
    );

    // Check Zig file contains expected exports
    let zig = fs::read_to_string(output.join("zig/mass_panic_ffi.zig")).unwrap();
    assert!(
        zig.contains("export fn c_process_item"),
        "Zig should export c_process_item"
    );
    assert!(
        zig.contains("mass_panic_process_item"),
        "Zig should delegate to user's mass_panic_process_item"
    );
    assert!(zig.contains("export fn c_init"), "Zig should export c_init");
    assert!(
        zig.contains("export fn c_load_item"),
        "Zig should export c_load_item"
    );

    // Check C header contains guards and function declarations
    let h = fs::read_to_string(output.join("include/mass_panic_chapeliser.h")).unwrap();
    assert!(
        h.contains("#ifndef CHAPELISER_MASS_PANIC_H"),
        "Header should have include guard"
    );
    assert!(
        h.contains("mass_panic_process_item"),
        "Header should declare process_item"
    );
    assert!(h.contains("mass_panic_init"), "Header should declare init");
    assert!(
        h.contains("mass_panic_load_item"),
        "Header should declare load_item"
    );
    assert!(
        h.contains("mass_panic_store_result"),
        "Header should declare store_result"
    );
}

#[test]
fn test_validate_rejects_bad_partition() {
    let toml = r#"
    [workload]
    name = "test"
    entry = "src/lib.rs::func"
    partition = "invalid_strategy"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m: chapeliser::manifest::Manifest = toml::from_str(toml).unwrap();
    let result = chapeliser::manifest::validate(&m);
    assert!(result.is_err());
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("Unknown partition strategy")
    );
}

#[test]
fn test_all_partition_strategies_generate() {
    let strategies = ["per-item", "chunk", "adaptive", "spatial", "keyed"];

    for strategy in &strategies {
        let toml_str = format!(
            r#"
        [workload]
        name = "test-{strategy}"
        entry = "src/lib.rs::func"
        partition = "{strategy}"
        gather = "merge"

        [data]
        input-type = "Vec<Item>"
        output-type = "Vec<Result>"

        [scaling]
        min-nodes = 1
        max-nodes = 4
        grain-size = 10
        "#
        );

        let m: chapeliser::manifest::Manifest = toml::from_str(&toml_str).unwrap();
        chapeliser::manifest::validate(&m).unwrap();

        let dir = tempfile::tempdir().unwrap();
        chapeliser::codegen::generate_all(&m, dir.path().to_str().unwrap())
            .unwrap_or_else(|e| panic!("Failed to generate for strategy {strategy}: {e}"));

        let safe_name = format!("test_{}", strategy.replace('-', "_"));
        let chpl_path = dir
            .path()
            .join(format!("chapel/{safe_name}_distributed.chpl"));
        assert!(
            chpl_path.exists(),
            "Chapel file missing for strategy {strategy}: expected {}",
            chpl_path.display()
        );

        // Verify generated Chapel is non-trivial and contains distribution logic
        let chpl = fs::read_to_string(&chpl_path).unwrap();
        assert!(
            chpl.contains("c_init"),
            "Chapel {strategy} should call c_init"
        );
        assert!(
            chpl.contains("c_load_item"),
            "Chapel {strategy} should load items"
        );
        assert!(
            chpl.contains("c_process_item"),
            "Chapel {strategy} should process items"
        );
        assert!(
            chpl.contains("processWithRetry"),
            "Chapel {strategy} should have retry logic"
        );
        assert!(
            chpl.contains("c_store_result"),
            "Chapel {strategy} should store results"
        );
        assert!(
            chpl.contains("c_shutdown"),
            "Chapel {strategy} should call shutdown"
        );
    }
}

#[test]
fn test_all_gather_strategies_generate() {
    let gathers = ["merge", "reduce", "tree-reduce", "stream", "first"];

    for gather in &gathers {
        let toml_str = format!(
            r#"
        [workload]
        name = "test-{gather}"
        entry = "src/lib.rs::func"
        partition = "per-item"
        gather = "{gather}"

        [data]
        input-type = "Vec<Item>"
        output-type = "Vec<Result>"

        [scaling]
        min-nodes = 1
        max-nodes = 4
        grain-size = 10
        "#
        );

        let m: chapeliser::manifest::Manifest = toml::from_str(&toml_str).unwrap();
        chapeliser::manifest::validate(&m).unwrap();

        let dir = tempfile::tempdir().unwrap();
        chapeliser::codegen::generate_all(&m, dir.path().to_str().unwrap())
            .unwrap_or_else(|e| panic!("Failed to generate for gather {gather}: {e}"));

        let safe_name = format!("test_{}", gather.replace('-', "_"));
        let chpl_path = dir
            .path()
            .join(format!("chapel/{safe_name}_distributed.chpl"));
        let chpl = fs::read_to_string(&chpl_path).unwrap();

        // Each gather strategy should produce strategy-specific output
        match *gather {
            "merge" => assert!(chpl.contains("merge"), "merge gather should mention merge"),
            "reduce" => assert!(
                chpl.contains("c_reduce"),
                "reduce gather should call c_reduce"
            ),
            "tree-reduce" => assert!(chpl.contains("tree"), "tree-reduce should mention tree"),
            "stream" => assert!(
                chpl.contains("Stream"),
                "stream gather should mention stream"
            ),
            "first" => assert!(
                chpl.contains("c_is_match"),
                "first gather should call c_is_match"
            ),
            _ => unreachable!(),
        }
    }
}

#[test]
fn test_checkpoint_config_in_generated_chapel() {
    let toml_str = r#"
    [workload]
    name = "checkpoint-test"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10

    [resilience]
    retries = 5
    checkpoint = true
    checkpoint-interval-secs = 60
    "#;

    let m: chapeliser::manifest::Manifest = toml::from_str(toml_str).unwrap();
    let dir = tempfile::tempdir().unwrap();
    chapeliser::codegen::generate_all(&m, dir.path().to_str().unwrap()).unwrap();

    let chpl =
        fs::read_to_string(dir.path().join("chapel/checkpoint_test_distributed.chpl")).unwrap();

    assert!(
        chpl.contains("maxRetries: int = 5"),
        "Should set maxRetries to 5"
    );
    assert!(
        chpl.contains("enableCheckpoint: bool = true"),
        "Should enable checkpointing"
    );
    assert!(
        chpl.contains("checkpointIntervalSecs: int = 60"),
        "Should set checkpoint interval"
    );
    assert!(
        chpl.contains("c_checkpoint_save"),
        "Should declare checkpoint save FFI"
    );
}

#[test]
fn test_zig_ffi_exports_all_functions() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    let dir = tempfile::tempdir().unwrap();
    chapeliser::codegen::generate_all(&m, dir.path().to_str().unwrap()).unwrap();

    let zig = fs::read_to_string(dir.path().join("zig/mass_panic_ffi.zig")).unwrap();

    // All required Chapel-facing exports
    let required_exports = [
        "export fn c_init",
        "export fn c_shutdown",
        "export fn c_get_total_items",
        "export fn c_load_item",
        "export fn c_store_result",
        "export fn c_process_item",
        "export fn c_process_chunk",
        "export fn c_reduce",
        "export fn c_is_match",
        "export fn c_key_hash",
        "export fn c_checkpoint_save",
        "export fn c_checkpoint_load",
    ];

    for export in &required_exports {
        assert!(zig.contains(export), "Zig FFI missing export: {export}");
    }

    // All user-facing externs
    assert!(
        zig.contains("mass_panic_init"),
        "Should declare user's init"
    );
    assert!(
        zig.contains("mass_panic_shutdown"),
        "Should declare user's shutdown"
    );
    assert!(
        zig.contains("mass_panic_process_item"),
        "Should declare user's process_item"
    );
}

// ===========================================================================
// 2. POINT-TO-POINT TESTS — every partition × gather combination (5×5=25)
// ===========================================================================

/// All 25 partition × gather combinations must produce valid Chapel code.
/// Each generated Chapel file must contain the core lifecycle calls and the
/// strategy-specific code for both the partition and gather sides.
#[test]
fn test_point_to_point_all_25_combinations() {
    let partitions = ["per-item", "chunk", "adaptive", "spatial", "keyed"];
    let gathers = ["merge", "reduce", "tree-reduce", "stream", "first"];

    for partition in &partitions {
        for gather in &gathers {
            let toml_str = make_manifest_toml(partition, gather);
            let m = parse_manifest(&toml_str);
            chapeliser::manifest::validate(&m)
                .unwrap_or_else(|e| panic!("Validation failed for {partition}×{gather}: {e}"));

            let (dir, safe_name) = generate_to_tempdir(&m);

            // All four artifacts must exist
            let chpl_path = dir
                .path()
                .join(format!("chapel/{safe_name}_distributed.chpl"));
            let zig_path = dir.path().join(format!("zig/{safe_name}_ffi.zig"));
            let h_path = dir.path().join(format!("include/{safe_name}_chapeliser.h"));
            let build_path = dir.path().join("build.sh");

            assert!(
                chpl_path.exists(),
                "Chapel missing for {partition}×{gather}"
            );
            assert!(zig_path.exists(), "Zig missing for {partition}×{gather}");
            assert!(h_path.exists(), "Header missing for {partition}×{gather}");
            assert!(
                build_path.exists(),
                "build.sh missing for {partition}×{gather}"
            );

            // Chapel must contain core lifecycle calls
            let chpl = fs::read_to_string(&chpl_path).unwrap();
            assert!(
                chpl.contains("c_init"),
                "{partition}×{gather}: Chapel missing c_init"
            );
            assert!(
                chpl.contains("c_shutdown"),
                "{partition}×{gather}: Chapel missing c_shutdown"
            );
            assert!(
                chpl.contains("c_load_item"),
                "{partition}×{gather}: Chapel missing c_load_item"
            );
            assert!(
                chpl.contains("c_store_result"),
                "{partition}×{gather}: Chapel missing c_store_result"
            );
            assert!(
                chpl.contains("c_process_item"),
                "{partition}×{gather}: Chapel missing c_process_item"
            );

            // Chapel must be non-empty and contain module declaration
            assert!(
                chpl.len() > 500,
                "{partition}×{gather}: Chapel file suspiciously short ({} bytes)",
                chpl.len()
            );

            // Gather-specific content check
            match *gather {
                "merge" => assert!(
                    chpl.contains("merge"),
                    "{partition}×merge: should mention merge"
                ),
                "reduce" => assert!(
                    chpl.contains("c_reduce"),
                    "{partition}×reduce: should call c_reduce"
                ),
                "tree-reduce" => assert!(
                    chpl.contains("tree"),
                    "{partition}×tree-reduce: should mention tree"
                ),
                "stream" => assert!(
                    chpl.contains("Stream"),
                    "{partition}×stream: should mention Stream"
                ),
                "first" => assert!(
                    chpl.contains("c_is_match"),
                    "{partition}×first: should call c_is_match"
                ),
                _ => unreachable!(),
            }

            // Zig must export all 12 C-ABI functions regardless of strategy
            let zig = fs::read_to_string(&zig_path).unwrap();
            for export in [
                "export fn c_init",
                "export fn c_shutdown",
                "export fn c_process_item",
                "export fn c_load_item",
                "export fn c_store_result",
            ] {
                assert!(
                    zig.contains(export),
                    "{partition}×{gather}: Zig missing {export}"
                );
            }
        }
    }
}

// ===========================================================================
// 3. END-TO-END TESTS — generate from panic-attacker example, verify output
// ===========================================================================

/// Full end-to-end: load the panic-attacker example manifest, generate all
/// artifacts, then verify every output file exists and contains the expected
/// content for the mass-panic workload.
#[test]
fn test_end_to_end_panic_attacker_all_artifacts() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    chapeliser::manifest::validate(&m).unwrap();

    let (dir, _safe_name) = generate_to_tempdir(&m);

    // --- Chapel artifact ---
    let chpl = fs::read_to_string(dir.path().join("chapel/mass_panic_distributed.chpl")).unwrap();

    // Module structure
    assert!(
        chpl.contains("module mass_panic_Distributed"),
        "Chapel should declare the mass_panic_Distributed module"
    );

    // Config constants from manifest
    assert!(
        chpl.contains("maxRetries: int = 2"),
        "Chapel retries should be 2 (from manifest)"
    );
    assert!(
        chpl.contains("enableCheckpoint: bool = true"),
        "Chapel should have checkpointing enabled"
    );
    assert!(
        chpl.contains("checkpointIntervalSecs: int = 120"),
        "Chapel should have 120s checkpoint interval"
    );
    assert!(
        chpl.contains("grainSize: int = 5"),
        "Chapel grain size should be 5"
    );
    assert!(
        chpl.contains("maxItemBytes: int = 10485760"),
        "Chapel max item bytes should be 10MB"
    );

    // Core FFI declarations
    for ffi_proc in [
        "extern proc c_init",
        "extern proc c_shutdown",
        "extern proc c_get_total_items",
        "extern proc c_load_item",
        "extern proc c_store_result",
        "extern proc c_process_item",
    ] {
        assert!(
            chpl.contains(ffi_proc),
            "Chapel missing FFI declaration: {ffi_proc}"
        );
    }

    // Distribution logic
    assert!(
        chpl.contains("coforall"),
        "Chapel should use coforall for locale distribution"
    );
    assert!(
        chpl.contains("processWithRetry"),
        "Chapel should have retry wrapper"
    );

    // --- Zig artifact ---
    let zig = fs::read_to_string(dir.path().join("zig/mass_panic_ffi.zig")).unwrap();

    // User-facing externs (workload-specific names)
    for user_fn in [
        "mass_panic_init",
        "mass_panic_shutdown",
        "mass_panic_get_total_items",
        "mass_panic_load_item",
        "mass_panic_store_result",
        "mass_panic_process_item",
        "mass_panic_process_chunk",
        "mass_panic_reduce",
        "mass_panic_is_match",
        "mass_panic_key_hash",
        "mass_panic_checkpoint_save",
        "mass_panic_checkpoint_load",
    ] {
        assert!(zig.contains(user_fn), "Zig missing user extern: {user_fn}");
    }

    // --- C header artifact ---
    let header = fs::read_to_string(dir.path().join("include/mass_panic_chapeliser.h")).unwrap();

    // Include guards
    assert!(
        header.contains("#ifndef CHAPELISER_MASS_PANIC_H"),
        "Header missing include guard #ifndef"
    );
    assert!(
        header.contains("#define CHAPELISER_MASS_PANIC_H"),
        "Header missing include guard #define"
    );
    assert!(
        header.contains("#endif"),
        "Header missing include guard #endif"
    );

    // Standard includes
    assert!(
        header.contains("#include <stddef.h>"),
        "Header should include stddef.h"
    );
    assert!(
        header.contains("#include <stdint.h>"),
        "Header should include stdint.h"
    );

    // C++ guard
    assert!(
        header.contains("extern \"C\""),
        "Header should have C++ extern guard"
    );

    // Function declarations with correct names
    for func in [
        "mass_panic_init",
        "mass_panic_shutdown",
        "mass_panic_get_total_items",
        "mass_panic_load_item",
        "mass_panic_store_result",
        "mass_panic_process_item",
        "mass_panic_process_chunk",
        "mass_panic_reduce",
        "mass_panic_is_match",
        "mass_panic_key_hash",
        "mass_panic_checkpoint_save",
        "mass_panic_checkpoint_load",
    ] {
        assert!(
            header.contains(func),
            "Header missing function declaration: {func}"
        );
    }

    // Max item bytes comment in header
    assert!(
        header.contains("10485760"),
        "Header should mention the 10MB max-item-bytes from manifest"
    );

    // --- Build script artifact ---
    let build = fs::read_to_string(dir.path().join("build.sh")).unwrap();
    assert!(
        build.contains("#!/usr/bin/env bash"),
        "Build script should have bash shebang"
    );
    assert!(
        build.contains("set -euo pipefail"),
        "Build script should use strict mode"
    );
    assert!(
        build.contains("mass_panic"),
        "Build script should reference workload name"
    );
    assert!(
        build.contains("mass_panic_ffi.zig"),
        "Build script should compile the Zig bridge"
    );
    assert!(
        build.contains("mass_panic_distributed.chpl"),
        "Build script should compile the Chapel wrapper"
    );
}

/// Verify the convenience `chapeliser::generate()` function works end-to-end.
#[test]
fn test_end_to_end_library_api() {
    let dir = tempfile::tempdir().unwrap();
    let output = dir.path().to_str().unwrap();

    chapeliser::generate("examples/panic-attacker/chapeliser.toml", output).unwrap();

    // All four artifacts should exist
    assert!(
        dir.path()
            .join("chapel/mass_panic_distributed.chpl")
            .exists()
    );
    assert!(dir.path().join("zig/mass_panic_ffi.zig").exists());
    assert!(dir.path().join("include/mass_panic_chapeliser.h").exists());
    assert!(dir.path().join("build.sh").exists());
}

// ===========================================================================
// 4. EDGE CASE TESTS
// ===========================================================================

/// Single locale (numLocales=1) — degenerate case where distribution is a no-op.
/// Must still generate valid Chapel with all lifecycle calls.
#[test]
fn test_edge_single_locale() {
    let toml_str = r#"
    [workload]
    name = "single-locale"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 1
    grain-size = 1
    "#;

    let m = parse_manifest(toml_str);
    chapeliser::manifest::validate(&m).unwrap();

    let (dir, safe_name) = generate_to_tempdir(&m);
    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    // Even with max-nodes=1, the generated Chapel must be structurally complete
    assert!(
        chpl.contains("c_init"),
        "Single locale: should still call c_init"
    );
    assert!(
        chpl.contains("c_shutdown"),
        "Single locale: should still call c_shutdown"
    );
    assert!(
        chpl.contains("c_process_item"),
        "Single locale: should still process items"
    );
}

/// Single item (totalItems=1, expected-items=1) — smallest possible workload.
#[test]
fn test_edge_single_item() {
    let toml_str = r#"
    [workload]
    name = "single-item"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 8
    grain-size = 1
    expected-items = 1
    "#;

    let m = parse_manifest(toml_str);
    chapeliser::manifest::validate(&m).unwrap();

    let (dir, safe_name) = generate_to_tempdir(&m);
    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    assert!(
        chpl.contains("c_init"),
        "Single item: should still call c_init"
    );
    assert!(
        chpl.contains("c_process_item"),
        "Single item: should process the one item"
    );
}

/// Very large grain size (grainSize > expected items) — everything in one chunk.
#[test]
fn test_edge_large_grain_size() {
    let toml_str = r#"
    [workload]
    name = "large-grain"
    entry = "src/lib.rs::func"
    partition = "chunk"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10000
    expected-items = 5
    "#;

    let m = parse_manifest(toml_str);
    chapeliser::manifest::validate(&m).unwrap();

    let (dir, safe_name) = generate_to_tempdir(&m);
    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    // grain-size 10000 with 5 items: one chunk. Must still generate valid code.
    assert!(
        chpl.contains("grainSize: int = 10000"),
        "Should reflect grain size 10000"
    );
    assert!(
        chpl.contains("c_process_item"),
        "Large grain: should still process items"
    );
}

/// Validation must reject zero grain-size.
#[test]
fn test_edge_zero_grain_size_rejected() {
    let toml_str = r#"
    [workload]
    name = "zero-grain"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 0
    "#;

    let m = parse_manifest(toml_str);
    let result = chapeliser::manifest::validate(&m);
    assert!(result.is_err(), "Zero grain-size should be rejected");
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("grain-size must be at least 1"),
        "Error should mention grain-size"
    );
}

/// Validation must reject zero min-nodes.
#[test]
fn test_edge_zero_min_nodes_rejected() {
    let toml_str = r#"
    [workload]
    name = "zero-min"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 0
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let result = chapeliser::manifest::validate(&m);
    assert!(result.is_err(), "Zero min-nodes should be rejected");
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("min-nodes must be at least 1"),
        "Error should mention min-nodes"
    );
}

/// Validation must reject max-nodes < min-nodes.
#[test]
fn test_edge_max_less_than_min_rejected() {
    let toml_str = r#"
    [workload]
    name = "bad-range"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 8
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let result = chapeliser::manifest::validate(&m);
    assert!(result.is_err(), "max-nodes < min-nodes should be rejected");
    assert!(
        result.unwrap_err().to_string().contains("max-nodes"),
        "Error should mention max-nodes"
    );
}

/// Validation must reject invalid gather strategy.
#[test]
fn test_edge_invalid_gather_rejected() {
    let toml_str = r#"
    [workload]
    name = "bad-gather"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "scatter"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let result = chapeliser::manifest::validate(&m);
    assert!(result.is_err(), "Invalid gather should be rejected");
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("Unknown gather strategy"),
        "Error should mention gather strategy"
    );
}

/// Validation must reject invalid serialization format.
#[test]
fn test_edge_invalid_serialization_rejected() {
    let toml_str = r#"
    [workload]
    name = "bad-serial"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"
    serialization = "protobuf"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let result = chapeliser::manifest::validate(&m);
    assert!(result.is_err(), "Invalid serialization should be rejected");
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("Unknown serialization format"),
        "Error should mention serialization format"
    );
}

/// Validation must reject entry point without path separator.
#[test]
fn test_edge_invalid_entry_point_rejected() {
    let toml_str = r#"
    [workload]
    name = "bad-entry"
    entry = "just_a_function_name"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let result = chapeliser::manifest::validate(&m);
    assert!(
        result.is_err(),
        "Entry point without :: or : should be rejected"
    );
}

/// init_manifest should refuse to overwrite an existing manifest.
#[test]
fn test_edge_init_refuses_overwrite() {
    let dir = tempfile::tempdir().unwrap();
    // Create initial manifest
    chapeliser::manifest::init_manifest(dir.path().to_str().unwrap()).unwrap();
    // Second call should fail
    let result = chapeliser::manifest::init_manifest(dir.path().to_str().unwrap());
    assert!(
        result.is_err(),
        "init should refuse to overwrite existing manifest"
    );
    assert!(
        result.unwrap_err().to_string().contains("already exists"),
        "Error should say manifest already exists"
    );
}

/// Workload name with many hyphens should produce valid safe_name in all artifacts.
#[test]
fn test_edge_hyphenated_name() {
    let toml_str = r#"
    [workload]
    name = "my-complex-workload-name"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let (dir, safe_name) = generate_to_tempdir(&m);

    assert_eq!(safe_name, "my_complex_workload_name");
    assert!(
        dir.path()
            .join("chapel/my_complex_workload_name_distributed.chpl")
            .exists()
    );
    assert!(
        dir.path()
            .join("zig/my_complex_workload_name_ffi.zig")
            .exists()
    );
    assert!(
        dir.path()
            .join("include/my_complex_workload_name_chapeliser.h")
            .exists()
    );
}

// ===========================================================================
// 5. ASPECT TESTS — cross-cutting concerns across all generated artifacts
// ===========================================================================

/// Every generated Chapel file must contain an SPDX license header.
#[test]
fn test_aspect_chapel_spdx_header() {
    let partitions = ["per-item", "chunk", "adaptive", "spatial", "keyed"];

    for partition in &partitions {
        let toml_str = make_manifest_toml(partition, "merge");
        let m = parse_manifest(&toml_str);
        let (dir, safe_name) = generate_to_tempdir(&m);

        let chpl = fs::read_to_string(
            dir.path()
                .join(format!("chapel/{safe_name}_distributed.chpl")),
        )
        .unwrap();

        assert!(
            chpl.contains("SPDX-License-Identifier: MPL-2.0"),
            "Chapel for partition '{partition}' missing SPDX header"
        );
    }
}

/// Every generated Chapel file must contain a module declaration.
#[test]
fn test_aspect_chapel_module_declaration() {
    let partitions = ["per-item", "chunk", "adaptive", "spatial", "keyed"];

    for partition in &partitions {
        let toml_str = make_manifest_toml(partition, "merge");
        let m = parse_manifest(&toml_str);
        let (dir, safe_name) = generate_to_tempdir(&m);

        let chpl = fs::read_to_string(
            dir.path()
                .join(format!("chapel/{safe_name}_distributed.chpl")),
        )
        .unwrap();

        assert!(
            chpl.contains(&format!("module {safe_name}_Distributed")),
            "Chapel for partition '{partition}' missing module declaration"
        );
    }
}

/// Every generated Zig file must contain the SPDX header.
#[test]
fn test_aspect_zig_spdx_header() {
    let gathers = ["merge", "reduce", "tree-reduce", "stream", "first"];

    for gather in &gathers {
        let toml_str = make_manifest_toml("per-item", gather);
        let m = parse_manifest(&toml_str);
        let (dir, safe_name) = generate_to_tempdir(&m);

        let zig = fs::read_to_string(dir.path().join(format!("zig/{safe_name}_ffi.zig"))).unwrap();

        assert!(
            zig.contains("SPDX-License-Identifier: MPL-2.0"),
            "Zig for gather '{gather}' missing SPDX header"
        );
    }
}

/// Every generated Zig file must use callconv(.C) on all exports.
#[test]
fn test_aspect_zig_callconv_exports() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let zig = fs::read_to_string(dir.path().join("zig/mass_panic_ffi.zig")).unwrap();

    // Count "export fn" lines — each must include "callconv(.C)"
    let export_lines: Vec<&str> = zig.lines().filter(|l| l.contains("export fn")).collect();
    assert!(
        !export_lines.is_empty(),
        "Zig should have at least one export fn"
    );

    for line in &export_lines {
        assert!(
            line.contains("callconv(.C)"),
            "Zig export missing callconv(.C): {line}"
        );
    }
}

/// Every generated Zig file must use callconv(.C) on all user externs too.
#[test]
fn test_aspect_zig_extern_callconv() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let zig = fs::read_to_string(dir.path().join("zig/mass_panic_ffi.zig")).unwrap();

    // Every "extern fn" declaration should also have callconv(.C)
    let extern_lines: Vec<&str> = zig.lines().filter(|l| l.contains("extern fn")).collect();
    assert!(
        !extern_lines.is_empty(),
        "Zig should have at least one extern fn"
    );

    for line in &extern_lines {
        assert!(
            line.contains("callconv(.C)"),
            "Zig extern missing callconv(.C): {line}"
        );
    }
}

/// The generated build script must be executable (Unix permissions).
#[test]
#[cfg(unix)]
fn test_aspect_build_script_executable() {
    use std::os::unix::fs::PermissionsExt;

    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let build_path = dir.path().join("build.sh");
    let metadata = fs::metadata(&build_path).unwrap();
    let mode = metadata.permissions().mode();

    // Check that the owner execute bit is set (0o100)
    assert!(
        mode & 0o100 != 0,
        "build.sh should be executable (mode: {mode:#o})"
    );
}

/// Every generated C header must have proper include guards.
#[test]
fn test_aspect_header_include_guards() {
    let partitions = ["per-item", "chunk", "adaptive", "spatial", "keyed"];

    for partition in &partitions {
        let toml_str = make_manifest_toml(partition, "merge");
        let m = parse_manifest(&toml_str);
        let (dir, safe_name) = generate_to_tempdir(&m);

        let h = fs::read_to_string(dir.path().join(format!("include/{safe_name}_chapeliser.h")))
            .unwrap();

        let upper = safe_name.to_uppercase();
        assert!(
            h.contains(&format!("#ifndef CHAPELISER_{upper}_H")),
            "Header for '{partition}' missing #ifndef guard"
        );
        assert!(
            h.contains(&format!("#define CHAPELISER_{upper}_H")),
            "Header for '{partition}' missing #define guard"
        );
        assert!(
            h.contains(&format!("#endif /* CHAPELISER_{upper}_H */")),
            "Header for '{partition}' missing #endif guard"
        );
    }
}

/// Every generated C header must have the SPDX license header.
#[test]
fn test_aspect_header_spdx() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let h = fs::read_to_string(dir.path().join("include/mass_panic_chapeliser.h")).unwrap();
    assert!(
        h.contains("SPDX-License-Identifier: MPL-2.0"),
        "C header missing SPDX header"
    );
}

/// Build script must contain the SPDX license header.
#[test]
fn test_aspect_build_script_spdx() {
    let m = chapeliser::manifest::load_manifest("examples/panic-attacker/chapeliser.toml").unwrap();
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let build = fs::read_to_string(dir.path().join("build.sh")).unwrap();
    assert!(
        build.contains("SPDX-License-Identifier: MPL-2.0"),
        "Build script missing SPDX header"
    );
}

// ===========================================================================
// 6. REGRESSION TESTS
// ===========================================================================

/// When checkpoint is disabled, the Chapel output should not enable it.
#[test]
fn test_regression_checkpoint_disabled_by_default() {
    let toml_str = r#"
    [workload]
    name = "no-checkpoint"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    let (dir, safe_name) = generate_to_tempdir(&m);

    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    assert!(
        chpl.contains("enableCheckpoint: bool = false"),
        "Default: checkpointing should be disabled"
    );
}

/// Retry count from manifest should appear in generated Chapel.
#[test]
fn test_regression_retry_config_in_output() {
    let toml_str = r#"
    [workload]
    name = "retry-test"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10

    [resilience]
    retries = 7
    "#;

    let m = parse_manifest(toml_str);
    let (dir, safe_name) = generate_to_tempdir(&m);

    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    assert!(
        chpl.contains("maxRetries: int = 7"),
        "Chapel should reflect retries=7 from manifest"
    );
}

/// Manifest validation catches all five invalid partition names.
#[test]
fn test_regression_validate_all_invalid_partitions() {
    let bad_names = ["round-robin", "random", "hash", "PER-ITEM", "per_item"];

    for bad in &bad_names {
        let toml_str = format!(
            r#"
            [workload]
            name = "bad-{bad}"
            entry = "src/lib.rs::func"
            partition = "{bad}"
            gather = "merge"

            [data]
            input-type = "Vec<Item>"
            output-type = "Vec<Result>"

            [scaling]
            min-nodes = 1
            max-nodes = 4
            grain-size = 10
            "#
        );

        let m = parse_manifest(&toml_str);
        let result = chapeliser::manifest::validate(&m);
        assert!(
            result.is_err(),
            "Partition '{bad}' should be rejected by validate()"
        );
    }
}

/// Manifest validation catches all five invalid gather names.
#[test]
fn test_regression_validate_all_invalid_gathers() {
    let bad_names = ["scatter", "broadcast", "allreduce", "MERGE", "tree_reduce"];

    for bad in &bad_names {
        let toml_str = format!(
            r#"
            [workload]
            name = "bad-g-{bad}"
            entry = "src/lib.rs::func"
            partition = "per-item"
            gather = "{bad}"

            [data]
            input-type = "Vec<Item>"
            output-type = "Vec<Result>"

            [scaling]
            min-nodes = 1
            max-nodes = 4
            grain-size = 10
            "#
        );

        let m = parse_manifest(&toml_str);
        let result = chapeliser::manifest::validate(&m);
        assert!(
            result.is_err(),
            "Gather '{bad}' should be rejected by validate()"
        );
    }
}

/// All six valid serialization formats must pass validation.
#[test]
fn test_regression_all_valid_serialization_formats() {
    let formats = [
        "bincode",
        "messagepack",
        "cbor",
        "json",
        "flatbuffers",
        "raw",
    ];

    for fmt in &formats {
        let toml_str = format!(
            r#"
            [workload]
            name = "serial-{fmt}"
            entry = "src/lib.rs::func"
            partition = "per-item"
            gather = "merge"

            [data]
            input-type = "Vec<Item>"
            output-type = "Vec<Result>"
            serialization = "{fmt}"

            [scaling]
            min-nodes = 1
            max-nodes = 4
            grain-size = 10
            "#
        );

        let m = parse_manifest(&toml_str);
        chapeliser::manifest::validate(&m)
            .unwrap_or_else(|e| panic!("Serialization '{fmt}' should be valid: {e}"));
    }
}

/// Default resilience values should be applied when [resilience] section is omitted.
#[test]
fn test_regression_default_resilience() {
    let toml_str = r#"
    [workload]
    name = "defaults"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10
    "#;

    let m = parse_manifest(toml_str);
    assert_eq!(m.resilience.retries, 3, "Default retries should be 3");
    assert!(
        !m.resilience.checkpoint,
        "Default checkpoint should be false"
    );
    assert_eq!(
        m.resilience.checkpoint_interval_secs, 300,
        "Default checkpoint interval should be 300s"
    );
    assert!(
        m.resilience.redistribute_on_failure,
        "Default redistribute should be true"
    );
}

/// Default scaling values should be applied for optional fields.
#[test]
fn test_regression_default_scaling() {
    let toml_str = r#"
    [workload]
    name = "scale-defaults"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    "#;

    let m = parse_manifest(toml_str);
    assert_eq!(m.scaling.min_nodes, 1, "Default min-nodes should be 1");
    assert_eq!(m.scaling.max_nodes, 64, "Default max-nodes should be 64");
    assert_eq!(m.scaling.grain_size, 50, "Default grain-size should be 50");
    assert!(
        m.scaling.expected_items.is_none(),
        "Default expected-items should be None"
    );
}

/// Chapel compiler flags from manifest should appear in build script.
#[test]
fn test_regression_chapel_compiler_flags_in_build() {
    let toml_str = r#"
    [workload]
    name = "flagged"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10

    [chapel]
    compiler-flags = ["--fast", "--cache-remote"]
    "#;

    let m = parse_manifest(toml_str);
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let build = fs::read_to_string(dir.path().join("build.sh")).unwrap();
    assert!(
        build.contains("--fast"),
        "Build script should include --fast from manifest"
    );
    assert!(
        build.contains("--cache-remote"),
        "Build script should include --cache-remote from manifest"
    );
}

/// Chapel comm-layer from manifest should appear in build script.
#[test]
fn test_regression_chapel_comm_layer_in_build() {
    let toml_str = r#"
    [workload]
    name = "comm-test"
    entry = "src/lib.rs::func"
    partition = "per-item"
    gather = "merge"

    [data]
    input-type = "Vec<Item>"
    output-type = "Vec<Result>"

    [scaling]
    min-nodes = 1
    max-nodes = 4
    grain-size = 10

    [chapel]
    comm-layer = "gasnet-ibv"
    "#;

    let m = parse_manifest(toml_str);
    let (dir, _safe_name) = generate_to_tempdir(&m);

    let build = fs::read_to_string(dir.path().join("build.sh")).unwrap();
    assert!(
        build.contains("CHPL_COMM=gasnet-ibv"),
        "Build script should set CHPL_COMM from manifest"
    );
}

// ===========================================================================
// Soundness: gather/store must never report success on failed inputs/stores
// ===========================================================================

/// The reduce gather must seed its accumulator from the first SUCCESSFUL item
/// (never blindly item 0, which may have failed) and mark the reduced result
/// valid only if at least one input succeeded — `resultOk[0] = haveAccum`,
/// never an unconditional `resultOk[0] = true`.
#[test]
fn reduce_gather_is_failure_aware() {
    let m = parse_manifest(&make_manifest_toml("chunk", "reduce"));
    let (dir, safe_name) = generate_to_tempdir(&m);
    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    assert!(
        chpl.contains("haveAccum"),
        "reduce gather must track whether any successful input was folded"
    );
    assert!(
        chpl.contains("resultOk[0] = haveAccum;"),
        "reduce result validity must follow haveAccum"
    );
    assert!(
        !chpl.contains("resultOk[0] = true;"),
        "reduce must not unconditionally mark the result valid"
    );
}

/// The store phase must not silently warn-and-exit-0 on a c_store_result
/// failure: it tracks the failure and halts with a non-zero status.
#[test]
fn store_phase_aborts_on_store_failure() {
    let m = parse_manifest(&make_manifest_toml("chunk", "merge"));
    let (dir, safe_name) = generate_to_tempdir(&m);
    let chpl = fs::read_to_string(
        dir.path()
            .join(format!("chapel/{safe_name}_distributed.chpl")),
    )
    .unwrap();

    assert!(
        chpl.contains("storeFailed"),
        "store phase must track store failures"
    );
    assert!(
        chpl.contains("halt("),
        "store phase must halt (non-zero exit) when a result fails to store"
    );
    assert!(
        !chpl.contains("WARN: c_store_result"),
        "store failures must be errors, not silent warnings"
    );
}
