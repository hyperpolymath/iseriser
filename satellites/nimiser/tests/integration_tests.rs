// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for nimiser.
// Tests the full pipeline: manifest loading -> parsing -> code generation.

use nimiser::abi::{CompilationTarget, GcStrategy, NimPragma, NimType};
use nimiser::codegen::build_gen;
use nimiser::codegen::nim_gen;
use nimiser::codegen::parser;
use nimiser::manifest;
use std::fs;
use tempfile::TempDir;

/// Helper: create a temporary directory with a nimiser.toml containing the given content.
fn write_manifest(dir: &TempDir, content: &str) -> String {
    let path = dir.path().join("nimiser.toml");
    fs::write(&path, content).expect("Failed to write test manifest");
    path.to_str().unwrap().to_string()
}

// ---------------------------------------------------------------------------
// Test 1: Load and validate the fast-lib example manifest
// ---------------------------------------------------------------------------
#[test]
fn test_load_fast_lib_example() {
    let m = manifest::load_manifest("examples/fast-lib/nimiser.toml")
        .expect("Failed to load fast-lib example manifest");
    manifest::validate(&m).expect("fast-lib manifest should be valid");

    assert_eq!(m.project.name, "fast-lib");
    assert_eq!(m.project.version, "0.1.0");
    assert_eq!(m.functions.len(), 4);
    assert_eq!(m.nim.backend, CompilationTarget::C);
    assert_eq!(m.nim.gc, GcStrategy::Arc);
}

// ---------------------------------------------------------------------------
// Test 2: Parse function signatures from the fast-lib manifest
// ---------------------------------------------------------------------------
#[test]
fn test_parse_fast_lib_functions() {
    let m = manifest::load_manifest("examples/fast-lib/nimiser.toml").unwrap();
    let procs = parser::parse_functions(&m).expect("Failed to parse functions");

    assert_eq!(procs.len(), 4);

    // Check the first function: fast_add(a: cint, b: cint): cint
    let add = &procs[0];
    assert_eq!(add.name, "fast_add");
    assert_eq!(add.params.len(), 2);
    assert_eq!(add.params[0].name, "a");
    assert_eq!(add.params[0].nim_type, NimType::Primitive("cint".into()));
    assert_eq!(add.return_type, Some(NimType::Primitive("cint".into())));
    assert!(add.pragmas.contains(&NimPragma::Exportc));
    assert!(add.pragmas.contains(&NimPragma::Cdecl));

    // Check fast_init has no return type (void).
    let init = &procs[3];
    assert_eq!(init.name, "fast_init");
    assert!(init.return_type.is_none());
}

// ---------------------------------------------------------------------------
// Test 3: Generate Nim source and verify it contains correct proc declarations
// ---------------------------------------------------------------------------
#[test]
fn test_generate_nim_source_content() {
    let m = manifest::load_manifest("examples/fast-lib/nimiser.toml").unwrap();
    let procs = parser::parse_functions(&m).unwrap();
    let nim_source = nim_gen::generate_nim_source(&m, &procs);

    // Must contain the SPDX header.
    assert!(
        nim_source.contains("SPDX-License-Identifier: MPL-2.0"),
        "Missing SPDX header"
    );

    // Must contain the library name reference.
    assert!(
        nim_source.contains("fast-lib"),
        "Missing library name in header"
    );

    // Must contain proc declarations with correct signatures.
    assert!(
        nim_source.contains("proc fast_add(a: cint, b: cint): cint {.exportc, cdecl.} ="),
        "Missing fast_add proc declaration"
    );
    assert!(
        nim_source.contains(
            "proc fast_multiply(x: cdouble, y: cdouble): cdouble {.exportc, cdecl, noSideEffect.} ="
        ),
        "Missing fast_multiply proc declaration"
    );
    assert!(
        nim_source.contains("proc fast_init {.exportc, cdecl.} ="),
        "Missing fast_init proc declaration"
    );

    // Must contain doc comments.
    assert!(
        nim_source.contains("## Add two C integers with zero overhead."),
        "Missing doc comment for fast_add"
    );

    // Must contain the wrapExportc helper template.
    assert!(
        nim_source.contains("template wrapExportc*"),
        "Missing wrapExportc helper template"
    );
}

// ---------------------------------------------------------------------------
// Test 4: Full generate pipeline writes files to disk
// ---------------------------------------------------------------------------
#[test]
fn test_generate_all_writes_files() {
    let dir = TempDir::new().unwrap();
    let manifest_content = r#"
[project]
name = "test-lib"
version = "1.0.0"
description = "Integration test library"

[[functions]]
name = "square"
return-type = "cint"
pragmas = ["exportc", "cdecl"]

  [[functions.params]]
  name = "x"
  type = "cint"

[nim]
backend = "c"
gc = "orc"
opt-level = "size"
"#;
    let manifest_path = write_manifest(&dir, manifest_content);
    let output_dir = dir.path().join("out");

    let m = manifest::load_manifest(&manifest_path).unwrap();
    manifest::validate(&m).unwrap();
    nimiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    // Verify files were created.
    assert!(
        output_dir.join("test_lib.nim").exists(),
        "Missing generated .nim file"
    );
    assert!(
        output_dir.join("nim.cfg").exists(),
        "Missing generated nim.cfg"
    );
    assert!(
        output_dir.join("build.sh").exists(),
        "Missing generated build.sh"
    );

    // Verify .nim file content.
    let nim_content = fs::read_to_string(output_dir.join("test_lib.nim")).unwrap();
    assert!(nim_content.contains("proc square(x: cint): cint {.exportc, cdecl.} ="));

    // Verify nim.cfg content.
    let cfg_content = fs::read_to_string(output_dir.join("nim.cfg")).unwrap();
    assert!(cfg_content.contains("gc = \"orc\""));
    assert!(cfg_content.contains("opt = \"size\""));
}

// ---------------------------------------------------------------------------
// Test 5: Manifest validation rejects invalid configurations
// ---------------------------------------------------------------------------
#[test]
fn test_validate_rejects_empty_project_name() {
    let dir = TempDir::new().unwrap();
    let content = r#"
[project]
name = ""
version = "1.0.0"

[nim]
backend = "c"
gc = "arc"
opt-level = "speed"
"#;
    let path = write_manifest(&dir, content);
    let m = manifest::load_manifest(&path).unwrap();
    let result = manifest::validate(&m);
    assert!(result.is_err(), "Should reject empty project name");
    assert!(
        result.unwrap_err().to_string().contains("project.name"),
        "Error should mention project.name"
    );
}

#[test]
fn test_validate_rejects_invalid_pragma() {
    let dir = TempDir::new().unwrap();
    let content = r#"
[project]
name = "bad-pragmas"
version = "0.1.0"

[[functions]]
name = "broken"
pragmas = ["exportc", "bogus_pragma"]

[nim]
backend = "c"
gc = "arc"
opt-level = "speed"
"#;
    let path = write_manifest(&dir, content);
    let m = manifest::load_manifest(&path).unwrap();
    let result = manifest::validate(&m);
    assert!(result.is_err(), "Should reject unknown pragma");
    assert!(
        result.unwrap_err().to_string().contains("bogus_pragma"),
        "Error should mention the bad pragma name"
    );
}

#[test]
fn test_validate_rejects_invalid_opt_level() {
    let dir = TempDir::new().unwrap();
    let content = r#"
[project]
name = "bad-opt"
version = "0.1.0"

[nim]
backend = "c"
gc = "arc"
opt-level = "turbo"
"#;
    let path = write_manifest(&dir, content);
    let m = manifest::load_manifest(&path).unwrap();
    let result = manifest::validate(&m);
    assert!(result.is_err(), "Should reject invalid opt-level");
}

// ---------------------------------------------------------------------------
// Test 6: Build command generation for different backends and GC strategies
// ---------------------------------------------------------------------------
#[test]
fn test_build_commands_across_targets() {
    let dir = TempDir::new().unwrap();

    // Test C + ARC
    let content_c = r#"
[project]
name = "c-lib"
version = "1.0.0"

[nim]
backend = "c"
gc = "arc"
opt-level = "speed"
"#;
    let path = write_manifest(&dir, content_c);
    let m = manifest::load_manifest(&path).unwrap();
    let cmd = build_gen::build_command_from_manifest(&m, "c_lib.nim", true);
    let rendered = cmd.render();
    assert!(
        rendered.starts_with("nim c"),
        "C backend should use 'nim c'"
    );
    assert!(rendered.contains("--gc:arc"), "Should use ARC GC");
    assert!(
        rendered.contains("--app:lib"),
        "C target should compile as library"
    );
    assert!(
        rendered.contains("-d:release"),
        "Release build should have -d:release"
    );

    // Test JS + ORC
    let dir2 = TempDir::new().unwrap();
    let content_js = r#"
[project]
name = "js-lib"
version = "1.0.0"

[nim]
backend = "js"
gc = "orc"
opt-level = "none"
"#;
    let path_js = write_manifest(&dir2, content_js);
    let m_js = manifest::load_manifest(&path_js).unwrap();
    let cmd_js = build_gen::build_command_from_manifest(&m_js, "js_lib.nim", false);
    let rendered_js = cmd_js.render();
    assert!(
        rendered_js.starts_with("nim js"),
        "JS backend should use 'nim js'"
    );
    assert!(rendered_js.contains("--gc:orc"), "Should use ORC GC");
    assert!(
        !rendered_js.contains("--app:lib"),
        "JS target should not use --app:lib"
    );

    // Test CPP + None GC
    let dir3 = TempDir::new().unwrap();
    let content_cpp = r#"
[project]
name = "cpp-lib"
version = "1.0.0"

[nim]
backend = "cpp"
gc = "none"
opt-level = "size"
"#;
    let path_cpp = write_manifest(&dir3, content_cpp);
    let m_cpp = manifest::load_manifest(&path_cpp).unwrap();
    let cmd_cpp = build_gen::build_command_from_manifest(&m_cpp, "cpp_lib.nim", true);
    let rendered_cpp = cmd_cpp.render();
    assert!(
        rendered_cpp.starts_with("nim cpp"),
        "CPP backend should use 'nim cpp'"
    );
    assert!(rendered_cpp.contains("--gc:none"), "Should use no GC");
    assert!(
        rendered_cpp.contains("--opt:size"),
        "Should optimise for size"
    );
}

// ---------------------------------------------------------------------------
// Test 7: init_manifest creates a valid manifest
// ---------------------------------------------------------------------------
#[test]
fn test_init_creates_valid_manifest() {
    let dir = TempDir::new().unwrap();
    let dir_path = dir.path().to_str().unwrap();

    manifest::init_manifest(dir_path).expect("init_manifest should succeed");

    let manifest_path = dir.path().join("nimiser.toml");
    assert!(manifest_path.exists(), "nimiser.toml should be created");

    // The generated manifest should be loadable and valid.
    let m = manifest::load_manifest(manifest_path.to_str().unwrap())
        .expect("Generated manifest should be loadable");
    manifest::validate(&m).expect("Generated manifest should be valid");

    assert!(!m.project.name.is_empty());
    assert!(
        m.functions.len() >= 2,
        "Template should have example functions"
    );
}

// ---------------------------------------------------------------------------
// Test 8: Parser handles complex types (ptr, seq, array)
// ---------------------------------------------------------------------------
#[test]
fn test_parser_complex_types() {
    let dir = TempDir::new().unwrap();
    let content = r#"
[project]
name = "complex-types"
version = "0.1.0"

[[functions]]
name = "process_buffer"
return-type = "ptr cint"
pragmas = ["exportc", "cdecl"]

  [[functions.params]]
  name = "data"
  type = "ptr cfloat"

  [[functions.params]]
  name = "count"
  type = "cint"

[nim]
backend = "c"
gc = "arc"
opt-level = "speed"
"#;
    let path = write_manifest(&dir, content);
    let m = manifest::load_manifest(&path).unwrap();
    let procs = parser::parse_functions(&m).unwrap();

    assert_eq!(procs.len(), 1);
    let p = &procs[0];

    // Return type should be ptr cint.
    assert_eq!(
        p.return_type,
        Some(NimType::Ptr(Box::new(NimType::Primitive("cint".into()))))
    );

    // First param should be ptr cfloat.
    assert_eq!(
        p.params[0].nim_type,
        NimType::Ptr(Box::new(NimType::Primitive("cfloat".into())))
    );
}
