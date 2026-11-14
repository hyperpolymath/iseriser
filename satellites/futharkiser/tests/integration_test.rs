// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for futharkiser.
//
// These tests exercise the full pipeline: manifest parsing, validation, Futhark
// code generation, C-ABI header generation, and build script generation. They
// use temporary directories to avoid polluting the source tree.

use std::fs;
use tempfile::TempDir;

use futharkiser::codegen;
use futharkiser::manifest::{self, Manifest};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A full manifest TOML string with all five SOAC patterns represented.
fn full_manifest_toml() -> &'static str {
    r#"
[project]
name = "image-pipeline"

[[kernels]]
name = "blur"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
description = "Apply Gaussian blur to each pixel"

[[kernels]]
name = "histogram"
pattern = "histogram"
input-type = "[u8]"
output-type = "[i64]"
bins = 256
description = "Compute pixel intensity histogram"

[[kernels]]
name = "prefix_sum"
pattern = "scan"
input-type = "[f64]"
output-type = "[f64]"
operator = "+"
description = "Inclusive prefix sum"

[[kernels]]
name = "total"
pattern = "reduce"
input-type = "[f64]"
output-type = "[f64]"
operator = "+"
description = "Sum all elements"

[[kernels]]
name = "write_pixels"
pattern = "scatter"
input-type = "[f32]"
output-type = "[f32]"
description = "Indirect pixel write"

[gpu]
backend = "opencl"
tuning = true
"#
}

/// Write the full manifest to a temp dir and return (dir, manifest).
fn setup_full_manifest() -> (TempDir, Manifest) {
    let dir = TempDir::new().expect("Failed to create temp dir");
    let manifest_path = dir.path().join("futharkiser.toml");
    fs::write(&manifest_path, full_manifest_toml()).unwrap();
    let m = manifest::load_manifest(manifest_path.to_str().unwrap()).unwrap();
    (dir, m)
}

// ---------------------------------------------------------------------------
// test_init_creates_manifest
// ---------------------------------------------------------------------------

#[test]
fn test_init_creates_manifest() {
    let dir = TempDir::new().expect("Failed to create temp dir");
    let path = dir.path().to_str().unwrap();

    // Init should create futharkiser.toml.
    manifest::init_manifest(path).expect("init_manifest should succeed");

    let manifest_path = dir.path().join("futharkiser.toml");
    assert!(manifest_path.exists(), "futharkiser.toml should be created");

    // The created manifest should be parseable and valid.
    let content = fs::read_to_string(&manifest_path).unwrap();
    let m: Manifest = toml::from_str(&content).expect("Generated manifest should parse");
    manifest::validate(&m).expect("Generated manifest should be valid");

    // Init should refuse to overwrite an existing file.
    let result = manifest::init_manifest(path);
    assert!(result.is_err(), "init_manifest should fail if file exists");
}

// ---------------------------------------------------------------------------
// test_generate_produces_fut_files
// ---------------------------------------------------------------------------

#[test]
fn test_generate_produces_fut_files() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");

    codegen::generate_all(&m, output_dir.to_str().unwrap()).expect("generate_all should succeed");

    // Check that the .fut file was created.
    let fut_path = output_dir.join("image-pipeline.fut");
    assert!(fut_path.exists(), ".fut file should be created");

    // Check that the C header was created.
    let header_path = output_dir.join("image-pipeline.h");
    assert!(header_path.exists(), ".h file should be created");

    // Check that the build script was created.
    let build_path = output_dir.join("build.sh");
    assert!(build_path.exists(), "build.sh should be created");
}

// ---------------------------------------------------------------------------
// test_map_kernel_generation
// ---------------------------------------------------------------------------

#[test]
fn test_map_kernel_generation() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let fut_source = fs::read_to_string(output_dir.join("image-pipeline.fut")).unwrap();

    // The blur kernel should be a map entry point.
    assert!(
        fut_source.contains("entry blur"),
        "Should contain entry blur"
    );
    assert!(
        fut_source.contains("map (\\x -> x) xs"),
        "Should contain map SOAC"
    );
    assert!(
        fut_source.contains("[]f32"),
        "Should reference f32 array type"
    );
}

// ---------------------------------------------------------------------------
// test_reduce_kernel_generation
// ---------------------------------------------------------------------------

#[test]
fn test_reduce_kernel_generation() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let fut_source = fs::read_to_string(output_dir.join("image-pipeline.fut")).unwrap();

    // The total kernel should be a reduce entry point.
    assert!(
        fut_source.contains("entry total"),
        "Should contain entry total"
    );
    assert!(
        fut_source.contains("reduce (+) 0.0 xs"),
        "Should contain reduce SOAC with + and neutral element"
    );
}

// ---------------------------------------------------------------------------
// test_scan_kernel_generation
// ---------------------------------------------------------------------------

#[test]
fn test_scan_kernel_generation() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let fut_source = fs::read_to_string(output_dir.join("image-pipeline.fut")).unwrap();

    // The prefix_sum kernel should be a scan entry point.
    assert!(
        fut_source.contains("entry prefix_sum"),
        "Should contain entry prefix_sum"
    );
    assert!(
        fut_source.contains("scan (+) 0.0 xs"),
        "Should contain scan SOAC"
    );
}

// ---------------------------------------------------------------------------
// test_all_backends_valid
// ---------------------------------------------------------------------------

#[test]
fn test_all_backends_valid() {
    // Every supported backend string should parse without error.
    for backend in &["opencl", "cuda", "multicore", "c"] {
        let toml_str = format!(
            r#"
[project]
name = "test"
[[kernels]]
name = "k"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
[gpu]
backend = "{}"
"#,
            backend
        );
        let m: Manifest = toml::from_str(&toml_str).unwrap_or_else(|e| {
            panic!("Failed to parse manifest with backend '{}': {}", backend, e)
        });
        manifest::validate(&m)
            .unwrap_or_else(|e| panic!("Validation failed for backend '{}': {}", backend, e));
    }
}

// ---------------------------------------------------------------------------
// Additional integration tests
// ---------------------------------------------------------------------------

#[test]
fn test_histogram_kernel_in_output() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let fut_source = fs::read_to_string(output_dir.join("image-pipeline.fut")).unwrap();

    assert!(
        fut_source.contains("entry histogram"),
        "Should contain entry histogram"
    );
    assert!(
        fut_source.contains("reduce_by_index"),
        "Should use reduce_by_index SOAC"
    );
    assert!(fut_source.contains("replicate 256"), "Should have 256 bins");
}

#[test]
fn test_scatter_kernel_in_output() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let fut_source = fs::read_to_string(output_dir.join("image-pipeline.fut")).unwrap();

    assert!(
        fut_source.contains("entry write_pixels"),
        "Should contain entry write_pixels"
    );
    assert!(
        fut_source.contains("scatter dest is vs"),
        "Should use scatter SOAC"
    );
    assert!(
        fut_source.contains("*[]f32"),
        "Should have unique array annotation"
    );
}

#[test]
fn test_c_header_contains_all_kernels() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let header = fs::read_to_string(output_dir.join("image-pipeline.h")).unwrap();

    assert!(
        header.contains("futhark_entry_blur"),
        "Header should declare blur"
    );
    assert!(
        header.contains("futhark_entry_histogram"),
        "Header should declare histogram"
    );
    assert!(
        header.contains("futhark_entry_prefix_sum"),
        "Header should declare prefix_sum"
    );
    assert!(
        header.contains("futhark_entry_total"),
        "Header should declare total"
    );
    assert!(
        header.contains("futhark_entry_write_pixels"),
        "Header should declare write_pixels"
    );
    assert!(
        header.contains("#ifndef IMAGE_PIPELINE_H"),
        "Header should have include guard"
    );
}

#[test]
fn test_build_script_references_backend() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let script = fs::read_to_string(output_dir.join("build.sh")).unwrap();

    assert!(
        script.contains("futhark opencl"),
        "Script should use opencl backend"
    );
    assert!(
        script.contains("autotune"),
        "Script should include auto-tuning (tuning=true)"
    );
}

#[test]
fn test_generated_fut_has_spdx_header() {
    let (dir, m) = setup_full_manifest();
    let output_dir = dir.path().join("output");
    codegen::generate_all(&m, output_dir.to_str().unwrap()).unwrap();

    let fut_source = fs::read_to_string(output_dir.join("image-pipeline.fut")).unwrap();
    assert!(
        fut_source.contains("MPL-2.0"),
        ".fut file should have SPDX header"
    );
}
