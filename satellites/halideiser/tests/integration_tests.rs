// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for halideiser.
//
// These tests exercise the full pipeline: parse manifest -> validate ->
// resolve -> generate Halide C++ / CMake, verifying that the generated
// artifacts contain the expected Halide constructs.

use halideiser::codegen::build_gen;
use halideiser::codegen::halide_gen;
use halideiser::codegen::parser;
use halideiser::manifest;

/// Full pipeline manifest for a multi-stage image filter.
const FULL_PIPELINE_TOML: &str = r#"
[project]
name = "photo_enhance"
version = "1.0.0"
description = "Multi-stage photo enhancement pipeline"

[[stages]]
name = "denoise"
operation = "blur"
kernel-size = 3
sigma = 0.8

[[stages]]
name = "sharpen_detail"
operation = "sharpen"
kernel-size = 3

[[stages]]
name = "find_edges"
operation = "edge-detect"

[target]
arch = "x86"
vectorize = true
parallelize = true

[pipeline]
input-format = "png"
output-format = "png"
bit-depth = "uint8"
"#;

/// Manifest with all seven operation types exercised.
const ALL_OPERATIONS_TOML: &str = r#"
[project]
name = "all_ops"

[[stages]]
name = "blur_it"
operation = "blur"
kernel-size = 5
sigma = 1.2

[[stages]]
name = "sharpen_it"
operation = "sharpen"

[[stages]]
name = "resize_it"
operation = "resize"
width = 1920
height = 1080

[[stages]]
name = "convolve_it"
operation = "convolve"
kernel-size = 3
kernel = [0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0]

[[stages]]
name = "detect_edges"
operation = "edge-detect"

[[stages]]
name = "threshold_it"
operation = "threshold"
value = 128.0

[[stages]]
name = "to_grayscale"
operation = "color-convert"
color-space = "grayscale"

[target]
arch = "x86"
vectorize = true
parallelize = true

[pipeline]
input-format = "png"
output-format = "png"
bit-depth = "uint8"
"#;

// ---------------------------------------------------------------------------
// Test 1: Full pipeline — parse, validate, resolve, generate
// ---------------------------------------------------------------------------

#[test]
fn test_full_pipeline_end_to_end() {
    let m = manifest::parse_manifest(FULL_PIPELINE_TOML).unwrap();
    manifest::validate(&m).unwrap();
    let resolved = parser::resolve_pipeline(&m).unwrap();

    assert_eq!(resolved.stages.len(), 3);
    assert_eq!(resolved.stages[0].func_name, "denoise");
    assert_eq!(resolved.stages[1].func_name, "sharpen_detail");
    assert_eq!(resolved.stages[2].func_name, "find_edges");

    // Generate Halide C++.
    let code = halide_gen::generate_halide_generator(&m, &resolved);
    assert!(code.contains("class photo_enhanceGenerator"));
    assert!(code.contains("HALIDE_REGISTER_GENERATOR"));
    assert!(code.contains("denoise"));
    assert!(code.contains("sharpen_detail"));
    assert!(code.contains("find_edges"));
    // Verify it chains stages: output should reference the last stage.
    assert!(code.contains("output(x, y, c) = find_edges(x, y, c)"));
}

// ---------------------------------------------------------------------------
// Test 2: All seven operations generate valid Halide code
// ---------------------------------------------------------------------------

#[test]
fn test_all_seven_operations() {
    let m = manifest::parse_manifest(ALL_OPERATIONS_TOML).unwrap();
    manifest::validate(&m).unwrap();
    let resolved = parser::resolve_pipeline(&m).unwrap();

    assert_eq!(resolved.stages.len(), 7);

    let code = halide_gen::generate_halide_generator(&m, &resolved);

    // Blur uses gaussian_weight.
    assert!(code.contains("gaussian_weight"));
    // Sharpen uses unsharp mask.
    assert!(code.contains("Unsharp mask"));
    // Resize uses bilinear interpolation.
    assert!(code.contains("Bilinear interpolation"));
    // Convolve uses a kernel buffer.
    assert!(code.contains("convolve_it_kernel"));
    // Edge detect uses Sobel.
    assert!(code.contains("Sobel"));
    // Threshold uses select().
    assert!(code.contains("select("));
    // Color convert references 0.299 (luminance coefficient).
    assert!(code.contains("0.299"));
}

// ---------------------------------------------------------------------------
// Test 3: CUDA target generates GPU-specific schedule
// ---------------------------------------------------------------------------

#[test]
fn test_cuda_target_generates_gpu_schedule() {
    let toml_str = r#"
[project]
name = "gpu_pipeline"

[[stages]]
name = "gpu_blur"
operation = "blur"
kernel-size = 5
sigma = 2.0

[target]
arch = "cuda"
vectorize = true
parallelize = true

[pipeline]
input-format = "raw"
output-format = "raw"
bit-depth = "float32"
"#;
    let m = manifest::parse_manifest(toml_str).unwrap();
    manifest::validate(&m).unwrap();
    let resolved = parser::resolve_pipeline(&m).unwrap();

    let code = halide_gen::generate_halide_generator(&m, &resolved);
    // GPU targets should use gpu_tile instead of CPU tile+parallel.
    assert!(code.contains("gpu_tile"));
    assert!(code.contains("block_x"));
    assert!(code.contains("block_y"));
    // Pixel type should be float.
    assert!(code.contains("Buffer<float, 3>"));
}

// ---------------------------------------------------------------------------
// Test 4: CMake generation includes correct target and features
// ---------------------------------------------------------------------------

#[test]
fn test_cmake_generation_complete() {
    let m = manifest::parse_manifest(FULL_PIPELINE_TOML).unwrap();
    let cmake = build_gen::generate_cmake(&m);

    // Structure checks.
    assert!(cmake.contains("cmake_minimum_required(VERSION 3.22)"));
    assert!(cmake.contains("find_package(Halide REQUIRED)"));
    assert!(cmake.contains("add_executable(photo_enhance_generator"));
    assert!(cmake.contains("add_halide_library(photo_enhance_halide"));
    assert!(cmake.contains("add_executable(photo_enhance_runner"));
    assert!(cmake.contains("Halide::Generator"));
    assert!(cmake.contains("Halide::ImageIO"));

    // x86 features.
    assert!(cmake.contains("avx2"));
    assert!(cmake.contains("fma"));

    // Install rule.
    assert!(cmake.contains("install(TARGETS photo_enhance_runner"));
}

// ---------------------------------------------------------------------------
// Test 5: Manifest validation catches errors
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_validation_errors() {
    // Empty project name.
    let bad_name = r#"
[project]
name = ""

[[stages]]
name = "s"
operation = "blur"

[target]
arch = "x86"

[pipeline]
input-format = "png"
output-format = "png"
"#;
    let m = manifest::parse_manifest(bad_name).unwrap();
    assert!(manifest::validate(&m).is_err());

    // Invalid C identifier in project name.
    let bad_ident = r#"
[project]
name = "has-dashes"

[[stages]]
name = "s"
operation = "blur"

[target]
arch = "x86"

[pipeline]
input-format = "png"
output-format = "png"
"#;
    let m = manifest::parse_manifest(bad_ident).unwrap();
    assert!(manifest::validate(&m).is_err());

    // Duplicate stage names.
    let dup_stages = r#"
[project]
name = "dup"

[[stages]]
name = "blur"
operation = "blur"

[[stages]]
name = "blur"
operation = "sharpen"

[target]
arch = "x86"

[pipeline]
input-format = "png"
output-format = "png"
"#;
    let m = manifest::parse_manifest(dup_stages).unwrap();
    assert!(manifest::validate(&m).is_err());

    // Resize without dimensions.
    let no_dims = r#"
[project]
name = "nodim"

[[stages]]
name = "resize_bad"
operation = "resize"

[target]
arch = "arm"

[pipeline]
input-format = "jpg"
output-format = "jpg"
"#;
    let m = manifest::parse_manifest(no_dims).unwrap();
    let resolved = parser::resolve_pipeline(&m);
    assert!(resolved.is_err());
}

// ---------------------------------------------------------------------------
// Test 6: File generation writes to disk correctly
// ---------------------------------------------------------------------------

#[test]
fn test_generate_writes_files_to_disk() {
    let m = manifest::parse_manifest(FULL_PIPELINE_TOML).unwrap();
    manifest::validate(&m).unwrap();

    let tmp_dir = tempfile::tempdir().unwrap();
    let output_dir = tmp_dir.path().to_str().unwrap();

    halideiser::codegen::generate_all(&m, output_dir).unwrap();

    // Check that all three expected files were created.
    let generator_path = tmp_dir.path().join("photo_enhance_generator.cpp");
    let runner_path = tmp_dir.path().join("photo_enhance_runner.cpp");
    let cmake_path = tmp_dir.path().join("CMakeLists.txt");

    assert!(generator_path.exists(), "Generator C++ file should exist");
    assert!(runner_path.exists(), "Runner C++ file should exist");
    assert!(cmake_path.exists(), "CMakeLists.txt should exist");

    // Verify file contents are non-empty and contain expected markers.
    let gen_content = std::fs::read_to_string(&generator_path).unwrap();
    assert!(gen_content.contains("#include \"Halide.h\""));
    assert!(gen_content.len() > 500, "Generator should be substantial");

    let runner_content = std::fs::read_to_string(&runner_path).unwrap();
    assert!(runner_content.contains("int main("));

    let cmake_content = std::fs::read_to_string(&cmake_path).unwrap();
    assert!(cmake_content.contains("find_package(Halide"));
}

// ---------------------------------------------------------------------------
// Test 7: WebAssembly target with SIMD features
// ---------------------------------------------------------------------------

#[test]
fn test_wasm_target_features() {
    let toml_str = r#"
[project]
name = "wasm_filter"

[[stages]]
name = "threshold_binary"
operation = "threshold"
value = 200.0

[target]
arch = "wasm"
vectorize = true
parallelize = false

[pipeline]
input-format = "png"
output-format = "png"
bit-depth = "uint8"
"#;
    let m = manifest::parse_manifest(toml_str).unwrap();
    manifest::validate(&m).unwrap();

    let cmake = build_gen::generate_cmake(&m);
    assert!(cmake.contains("wasm-32-wasmrt"));
    assert!(cmake.contains("wasm_simd128"));

    let resolved = parser::resolve_pipeline(&m).unwrap();
    let code = halide_gen::generate_halide_generator(&m, &resolved);
    // Threshold should use select with the specified value.
    assert!(code.contains("200"));
    // WASM: should NOT have gpu_tile.
    assert!(!code.contains("gpu_tile"));
}

// ---------------------------------------------------------------------------
// Test 8: ARM target with colour conversion
// ---------------------------------------------------------------------------

#[test]
fn test_arm_color_convert_pipeline() {
    let toml_str = r#"
[project]
name = "arm_color"

[[stages]]
name = "to_yuv"
operation = "color-convert"
color-space = "yuv"

[target]
arch = "arm"
vectorize = true
parallelize = true

[pipeline]
input-format = "raw"
output-format = "raw"
bit-depth = "uint16"
"#;
    let m = manifest::parse_manifest(toml_str).unwrap();
    manifest::validate(&m).unwrap();

    let resolved = parser::resolve_pipeline(&m).unwrap();
    let code = halide_gen::generate_halide_generator(&m, &resolved);
    // YUV conversion coefficients.
    assert!(code.contains("0.299"));
    assert!(code.contains("0.587"));
    assert!(code.contains("0.114"));
    // ARM target string.
    let cmake = build_gen::generate_cmake(&m);
    assert!(cmake.contains("arm-64-linux"));
    assert!(cmake.contains("arm_dot_prod"));
    // uint16 pixel type.
    assert!(code.contains("uint16_t"));
}
