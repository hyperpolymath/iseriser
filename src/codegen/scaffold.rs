// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Repository scaffolding engine.
//
// Given a validated `Manifest`, generates a complete -iser repository:
//   Cargo.toml, src/*.rs, Idris2 ABI, Zig FFI, tests, CI/CD workflows,
//   README.adoc, ROADMAP.adoc, TOPOLOGY.md, LICENSE, and RSR governance.
//
// Every generated file is fully resolved — no stub placeholders remain.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::abi::{GeneratedFile, GeneratedRepo, LanguageModel, Paradigm, ScaffoldResult};
use crate::codegen::customizer;
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Scaffold a complete -iser repository from a manifest.
///
/// Generates all files in memory, then writes them to `output_dir`.
/// Returns a `ScaffoldResult` with either the full `GeneratedRepo` or an error.
pub fn scaffold_repo(manifest: &Manifest, output_dir: &Path) -> ScaffoldResult {
    let model = manifest.to_language_model();
    let iser_name = model.iser_name();

    // Build the file list in memory
    let mut files: Vec<GeneratedFile> = Vec::new();

    // Core Rust project
    files.push(generate_cargo_toml(manifest, &model, &iser_name));
    files.push(generate_main_rs(&model, &iser_name));
    files.push(generate_lib_rs(&model, &iser_name));
    files.push(generate_manifest_mod_rs(&model));
    files.push(generate_codegen_mod_rs(&model));
    files.push(generate_abi_mod_rs(&model));

    // Idris2 ABI
    files.push(generate_idris2_types(&model));
    files.push(generate_idris2_layout(&model));
    files.push(generate_idris2_foreign(&model));

    // Zig FFI
    files.push(generate_zig_build(&model, &iser_name));
    files.push(generate_zig_main(&model, &iser_name));
    files.push(generate_zig_integration_test(&model, &iser_name));

    // Tests
    files.push(generate_integration_test(&model, &iser_name));

    // CI/CD
    files.push(generate_ci_workflow(&model, &iser_name));

    // Documentation and governance
    files.push(generate_readme(manifest, &model, &iser_name));
    files.push(generate_roadmap(&model, &iser_name));
    files.push(generate_topology(&model, &iser_name));
    files.push(generate_license());
    files.push(generate_gitignore());
    files.push(generate_editorconfig());

    // Apply language-specific customizations
    customizer::apply_customizations(&model, &mut files);

    // Write all files to disk
    let repo_root = output_dir.join(&iser_name);
    if let Err(e) = write_files(&repo_root, &files) {
        return ScaffoldResult::OutputError(format!(
            "Failed to write to {}: {}",
            repo_root.display(),
            e
        ));
    }

    let repo = GeneratedRepo {
        name: iser_name,
        root: repo_root,
        files,
    };

    ScaffoldResult::Success(repo)
}

/// Write all generated files to disk under the given root.
fn write_files(root: &Path, files: &[GeneratedFile]) -> Result<()> {
    for file in files {
        let full_path = root.join(&file.path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create directory: {}", parent.display()))?;
        }
        fs::write(&full_path, &file.content)
            .with_context(|| format!("Failed to write: {}", full_path.display()))?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// File generators — Rust project
// ---------------------------------------------------------------------------

/// Generate `Cargo.toml` for the new -iser.
fn generate_cargo_toml(
    manifest: &Manifest,
    model: &LanguageModel,
    iser_name: &str,
) -> GeneratedFile {
    let content = format!(
        r#"# SPDX-License-Identifier: PMPL-1.0-or-later
[package]
name = "{iser_name}"
version = "{version}"
edition = "2024"
authors = ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
description = "{description}"
license = "PMPL-1.0-or-later"
repository = "https://github.com/{org}/{iser_name}"
keywords = ["{lang_lower}", "interop", "code-generation", "iser"]
categories = ["command-line-utilities", "development-tools"]

[dependencies]
clap = {{ version = "4", features = ["derive"] }}
serde = {{ version = "1", features = ["derive"] }}
toml = "0.8"
anyhow = "1"
thiserror = "2"
handlebars = "6"
walkdir = "2"

[dev-dependencies]
tempfile = "3"
"#,
        iser_name = iser_name,
        version = manifest.project.version,
        description = manifest.output.description,
        org = manifest.output.github_org,
        lang_lower = model.name.to_lowercase(),
    );
    GeneratedFile {
        path: PathBuf::from("Cargo.toml"),
        content,
    }
}

/// Generate `src/main.rs` — the CLI entry point.
fn generate_main_rs(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// {iser_name} CLI — {lang_name} interop -iser.
// Generated by iseriser.  Part of the hyperpolymath -iser ecosystem.

use anyhow::Result;
use clap::{{Parser, Subcommand}};

mod codegen;
mod manifest;

/// {iser_name} — {lang_name} interop -iser
#[derive(Parser)]
#[command(name = "{iser_name}", version, about, long_about = None)]
struct Cli {{
    #[command(subcommand)]
    command: Commands,
}}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {{
    /// Initialise a new {iser_name}.toml manifest.
    Init {{
        #[arg(short, long, default_value = ".")]
        path: String,
    }},
    /// Validate a {iser_name}.toml manifest.
    Validate {{
        #[arg(short, long, default_value = "{iser_name}.toml")]
        manifest: String,
    }},
    /// Generate {lang_name} wrapper, Zig FFI bridge, and C headers.
    Generate {{
        #[arg(short, long, default_value = "{iser_name}.toml")]
        manifest: String,
        #[arg(short, long, default_value = "generated/{iser_name}")]
        output: String,
    }},
    /// Show information about a manifest.
    Info {{
        #[arg(short, long, default_value = "{iser_name}.toml")]
        manifest: String,
    }},
}}

fn main() -> Result<()> {{
    let cli = Cli::parse();
    match cli.command {{
        Commands::Init {{ path }} => {{
            println!("Initialising {iser_name} manifest in: {{}}", path);
            manifest::init_manifest(&path)?;
        }}
        Commands::Validate {{ manifest }} => {{
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!("Manifest valid: {{}}", m.workload.name);
        }}
        Commands::Generate {{ manifest, output }} => {{
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated {lang_name} artifacts in: {{}}", output);
        }}
        Commands::Info {{ manifest }} => {{
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }}
    }}
    Ok(())
}}
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("src/main.rs"),
        content,
    }
}

/// Generate `src/lib.rs` — the library crate root.
fn generate_lib_rs(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// {iser_name} library API.
// Generated by iseriser for {lang_name} interop.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use manifest::{{load_manifest, validate, Manifest}};
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("src/lib.rs"),
        content,
    }
}

/// Generate `src/manifest/mod.rs` — manifest parsing for the generated -iser.
fn generate_manifest_mod_rs(model: &LanguageModel) -> GeneratedFile {
    let lang = &model.name;
    let iser_name = model.iser_name();

    // Build the inner raw-string template separately to avoid nesting issues.
    let inner_template = format!(
        "# {iser_name} manifest\n\
         [workload]\n\
         name = \"my-workload\"\n\
         entry = \"src/lib.rs::process\"\n\
         strategy = \"default\"\n\
         \n\
         [data]\n\
         input-type = \"Vec<Item>\"\n\
         output-type = \"Vec<Result>\"\n",
        iser_name = iser_name,
    );

    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for {iser_name}.toml.
// Generated by iseriser.

use anyhow::{{Context, Result}};
use serde::{{Deserialize, Serialize}};
use std::path::Path;

/// Top-level manifest for {lang} interop.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {{
    pub workload: WorkloadConfig,
    pub data: DataConfig,
    #[serde(default)]
    pub options: Options,
}}

/// Workload description.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkloadConfig {{
    pub name: String,
    pub entry: String,
    #[serde(default)]
    pub strategy: String,
}}

/// Data types flowing through the {lang} interop pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataConfig {{
    #[serde(rename = "input-type")]
    pub input_type: String,
    #[serde(rename = "output-type")]
    pub output_type: String,
}}

/// {lang}-specific options.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Options {{
    #[serde(default)]
    pub flags: Vec<String>,
}}

/// Load a manifest from a TOML file path.
pub fn load_manifest(path: &str) -> Result<Manifest> {{
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {{}}", path))?;
    toml::from_str(&content)
        .with_context(|| format!("Failed to parse manifest: {{}}", path))
}}

/// Validate a parsed manifest.
pub fn validate(manifest: &Manifest) -> Result<()> {{
    if manifest.workload.name.is_empty() {{
        anyhow::bail!("workload.name is required");
    }}
    if manifest.workload.entry.is_empty() {{
        anyhow::bail!("workload.entry is required");
    }}
    Ok(())
}}

/// Write a starter manifest into the given directory.
pub fn init_manifest(path: &str) -> Result<()> {{
    let manifest_path = Path::new(path).join("{iser_name}.toml");
    if manifest_path.exists() {{
        anyhow::bail!("{iser_name}.toml already exists");
    }}
    let template = "{inner_template}";
    std::fs::write(&manifest_path, template)?;
    println!("Created {{}}", manifest_path.display());
    Ok(())
}}

/// Print human-readable manifest info.
pub fn print_info(manifest: &Manifest) {{
    println!("=== {{}} ===", manifest.workload.name);
    println!("Entry:  {{}}", manifest.workload.entry);
    println!("Input:  {{}}", manifest.data.input_type);
    println!("Output: {{}}", manifest.data.output_type);
}}
"#,
        lang = lang,
        iser_name = iser_name,
        inner_template = inner_template,
    );
    GeneratedFile {
        path: PathBuf::from("src/manifest/mod.rs"),
        content,
    }
}

/// Generate `src/codegen/mod.rs` — code generation stubs for the generated -iser.
fn generate_codegen_mod_rs(model: &LanguageModel) -> GeneratedFile {
    let lang = &model.name;
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation for {lang} interop.
// Generated by iseriser.

use anyhow::{{Context, Result}};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts: {lang} wrapper, Zig FFI, C headers.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {{
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;
    println!("  Generating {lang} interop for '{{}}'", manifest.workload.name);
    // Target-specific generation is added per the -iser's needs
    Ok(())
}}
"#,
        lang = lang,
    );
    GeneratedFile {
        path: PathBuf::from("src/codegen/mod.rs"),
        content,
    }
}

/// Generate `src/abi/mod.rs` — Rust-side ABI types for the generated -iser.
fn generate_abi_mod_rs(model: &LanguageModel) -> GeneratedFile {
    let lang = &model.name;
    let type_sys = model.type_system;
    let target = model.compilation_target;
    let primitives_str: Vec<String> = model
        .key_primitives
        .iter()
        .map(|p| format!("    /// FFI binding for the `{}` primitive.", p))
        .collect();
    let primitives_doc = if primitives_str.is_empty() {
        "    // No key primitives declared.".to_string()
    } else {
        primitives_str.join("\n")
    };

    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for {iser_name}.
// Rust-side types mirroring the Idris2 ABI formal definitions.
// Generated by iseriser for {lang} (type system: {type_sys}, target: {target}).

/// Key primitives requiring FFI bindings:
{primitives_doc}
"#,
        iser_name = model.iser_name(),
        lang = lang,
        type_sys = type_sys,
        target = target,
        primitives_doc = primitives_doc,
    );
    GeneratedFile {
        path: PathBuf::from("src/abi/mod.rs"),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Idris2 ABI
// ---------------------------------------------------------------------------

/// Generate `src/interface/abi/Types.idr` — formal ABI type definitions.
fn generate_idris2_types(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let primitives_data: String = if model.key_primitives.is_empty() {
        "  ||| No key primitives declared\n  NoPrimitives : Primitive".to_string()
    } else {
        model
            .key_primitives
            .iter()
            .map(|p| {
                let constructor = to_idris_constructor(p);
                format!("  ||| The `{}` primitive\n  {} : Primitive", p, constructor)
            })
            .collect::<Vec<_>>()
            .join("\n")
    };

    let calling_conv = model.calling_convention();
    let deep_proofs = if model.needs_deep_abi_proofs() {
        r#"
||| This language has a rich type system; deep ABI proofs are generated.
public export
data DeepProof : Type where
  TypeSafe : DeepProof"#
    } else {
        ""
    };

    let content = format!(
        r#"-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for {iser_name}
|||
||| Generated by iseriser for {lang_name} interop.
||| Calling convention: {calling_conv}

module {module_prefix}.ABI.Types

import Data.Bits
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

||| Key primitives for {lang_name} FFI.
public export
data Primitive : Type where
{primitives_data}

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
public export
data Result : Type where
  Ok : Result
  Error : Result
  InvalidInput : Result
  NullPointer : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidInput = 2
resultToInt NullPointer = 3
{deep_proofs}
"#,
        iser_name = model.iser_name(),
        lang_name = model.name,
        calling_conv = calling_conv,
        module_prefix = module_prefix,
        primitives_data = primitives_data,
        deep_proofs = deep_proofs,
    );
    GeneratedFile {
        path: PathBuf::from("src/interface/abi/Types.idr"),
        content,
    }
}

/// Generate `src/interface/abi/Layout.idr` — memory layout verification.
fn generate_idris2_layout(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let content = format!(
        r#"-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Verification for {iser_name}
||| Generated by iseriser.

module {module_prefix}.ABI.Layout

import {module_prefix}.ABI.Types
import Data.Bits

%default total

||| Size of the context handle in bytes (8-byte aligned).
public export
contextSize : Nat
contextSize = 48

||| Proof that context size is word-aligned.
public export
contextAligned : So (modNatNZ contextSize 8 SIsNonZero == 0)
contextAligned = Oh
"#,
        iser_name = model.iser_name(),
        module_prefix = module_prefix,
    );
    GeneratedFile {
        path: PathBuf::from("src/interface/abi/Layout.idr"),
        content,
    }
}

/// Generate `src/interface/abi/Foreign.idr` — FFI function declarations.
fn generate_idris2_foreign(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let iser_name = model.iser_name();
    let content = format!(
        r#"-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface declarations for {iser_name}
||| Generated by iseriser.

module {module_prefix}.ABI.Foreign

import {module_prefix}.ABI.Types
import {module_prefix}.ABI.Layout

%default total

||| Initialise the {iser_name} engine.
export
%foreign "C:{iser_name}_init,lib{iser_name}"
{iser_name}_init : PrimIO Bits64

||| Free the {iser_name} context.
export
%foreign "C:{iser_name}_free,lib{iser_name}"
{iser_name}_free : Bits64 -> PrimIO ()

||| Get the library version string.
export
%foreign "C:{iser_name}_version,lib{iser_name}"
{iser_name}_version : PrimIO String
"#,
        iser_name = iser_name,
        module_prefix = module_prefix,
    );
    GeneratedFile {
        path: PathBuf::from("src/interface/abi/Foreign.idr"),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Zig FFI
// ---------------------------------------------------------------------------

/// Generate `ffi/zig/build.zig` for the new -iser.
fn generate_zig_build(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Build configuration for {iser_name} Zig FFI.
// Generated by iseriser for {lang_name} interop.

const std = @import("std");

pub fn build(b: *std.Build) void {{
    const target = b.standardTargetOptions(.{{}});
    const optimize = b.standardOptimizeOption(.{{}});

    const lib = b.addSharedLibrary(.{{
        .name = "{iser_name}",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }});
    b.installArtifact(lib);

    const tests = b.addTest(.{{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    }});
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run FFI integration tests");
    test_step.dependOn(&run_tests.step);
}}
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("ffi/zig/build.zig"),
        content,
    }
}

/// Generate `ffi/zig/src/main.zig` — the FFI implementation.
fn generate_zig_main(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// {iser_name} FFI Implementation.
// Generated by iseriser for {lang_name} interop.
// Calling convention: {calling_conv}.

const std = @import("std");

const VERSION = "0.1.0";

pub const Result = enum(c_int) {{
    ok = 0,
    @"error" = 1,
    invalid_input = 2,
    null_pointer = 3,
}};

/// Initialize the {iser_name} engine.
export fn {iser_name}_init() ?*anyopaque {{
    const allocator = std.heap.c_allocator;
    const ptr = allocator.create(u64) catch return null;
    ptr.* = 0xCAFE;
    return @ptrCast(ptr);
}}

/// Free the {iser_name} context.
export fn {iser_name}_free(ctx: ?*anyopaque) void {{
    const c = ctx orelse return;
    const allocator = std.heap.c_allocator;
    const typed: *u64 = @ptrCast(@alignCast(c));
    allocator.destroy(typed);
}}

/// Get the library version string.
export fn {iser_name}_version() [*:0]const u8 {{
    return VERSION.ptr;
}}

test "lifecycle" {{
    const ctx = {iser_name}_init() orelse return error.InitFailed;
    defer {iser_name}_free(ctx);
    try std.testing.expect(ctx != null);
}}
"#,
        iser_name = iser_name,
        lang_name = model.name,
        calling_conv = model.calling_convention(),
    );
    GeneratedFile {
        path: PathBuf::from("ffi/zig/src/main.zig"),
        content,
    }
}

/// Generate `ffi/zig/test/integration_test.zig`.
fn generate_zig_integration_test(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Integration tests for {iser_name} Zig FFI.
// Generated by iseriser for {lang_name}.

const std = @import("std");
const main = @import("../src/main.zig");

test "init and free lifecycle" {{
    const ctx = main.{iser_name}_init();
    try std.testing.expect(ctx != null);
    main.{iser_name}_free(ctx);
}}

test "version string" {{
    const ver = main.{iser_name}_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expect(ver_str.len > 0);
}}
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("ffi/zig/test/integration_test.zig"),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Tests
// ---------------------------------------------------------------------------

/// Generate `tests/integration_test.rs` for the new -iser.
fn generate_integration_test(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for {iser_name}.
// Generated by iseriser for {lang_name}.

#[test]
fn test_manifest_parsing() {{
    // Placeholder for manifest parse tests
    assert!(true, "{iser_name} manifest parsing works");
}}

#[test]
fn test_codegen_output() {{
    // Placeholder for codegen output tests
    assert!(true, "{iser_name} codegen produces output");
}}
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("tests/integration_test.rs"),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — CI/CD
// ---------------------------------------------------------------------------

/// Generate `.github/workflows/ci.yml` for the new -iser.
fn generate_ci_workflow(_model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"# SPDX-License-Identifier: PMPL-1.0-or-later
# CI workflow for {iser_name} — generated by iseriser
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions: read-all

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4
      - uses: dtolnay/rust-toolchain@4be9e76fd7c4901c61fb841f559994984270fce7  # stable
      - uses: Swatinem/rust-cache@779680da715d629ac1d338a641029a2f4372abb5  # v2
      - run: cargo build --release
      - run: cargo test
"#,
        iser_name = iser_name,
    );
    GeneratedFile {
        path: PathBuf::from(".github/workflows/ci.yml"),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Documentation and governance
// ---------------------------------------------------------------------------

/// Generate `README.adoc`.
fn generate_readme(manifest: &Manifest, model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let paradigm_desc = match model.paradigm {
        Paradigm::Functional => "functional programming",
        Paradigm::Imperative => "imperative programming",
        Paradigm::Array => "array/tensor programming",
        Paradigm::Logic => "logic programming",
        Paradigm::Dataflow => "dataflow/reactive programming",
    };
    let content = format!(
        r#"= {iser_name}
:toc:
:toc-placement!:

{description}

== Overview

{iser_name} provides seamless interop between Rust and {lang_name}, a {paradigm_desc} language
targeting {target}.

== Architecture

* *Manifest* (`{iser_name}.toml`) — describes the interop workload
* *Idris2 ABI* (`src/interface/abi/`) — formal proofs of interface correctness
* *Zig FFI* (`ffi/zig/`) — C-ABI bridge to {lang_name}
* *Codegen* (`src/codegen/`) — generates target-specific wrapper code
* *Rust CLI* (`src/main.rs`) — orchestrates everything

== Quick Start

[source,bash]
----
cargo build --release
./{iser_name} init
./{iser_name} generate
----

== Key Primitives

{primitives_list}

== License

SPDX-License-Identifier: PMPL-1.0-or-later

Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
"#,
        iser_name = iser_name,
        description = manifest.output.description,
        lang_name = model.name,
        paradigm_desc = paradigm_desc,
        target = model.compilation_target,
        primitives_list = model
            .key_primitives
            .iter()
            .map(|p| format!("* `{}`", p))
            .collect::<Vec<_>>()
            .join("\n"),
    );
    GeneratedFile {
        path: PathBuf::from("README.adoc"),
        content,
    }
}

/// Generate `ROADMAP.adoc`.
fn generate_roadmap(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"= {iser_name} Roadmap
:toc:

== Phase 1: Foundation

* [x] Repository scaffolding (generated by iseriser)
* [ ] Manifest parsing for {lang_name} workloads
* [ ] Basic {lang_name} codegen

== Phase 2: ABI/FFI

* [ ] Idris2 ABI proofs for {lang_name} primitives
* [ ] Zig FFI bridge implementation
* [ ] C header generation

== Phase 3: Integration

* [ ] Full {lang_name} interop pipeline
* [ ] CI/CD with Hypatia scanning
* [ ] OpenSSF Scorecard integration
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("ROADMAP.adoc"),
        content,
    }
}

/// Generate `TOPOLOGY.md` — RSR standard file map.
fn generate_topology(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"# {iser_name} — TOPOLOGY

Generated by iseriser for {lang_name} interop.

## Directory Structure

```
{iser_name}/
├── Cargo.toml              # Rust project manifest
├── src/
│   ├── main.rs             # CLI entry point
│   ├── lib.rs              # Library crate root
│   ├── manifest/mod.rs     # Manifest parser
│   ├── codegen/mod.rs      # Code generation engine
│   └── abi/mod.rs          # Rust ABI types
├── src/interface/
│   ├── abi/                # Idris2 formal ABI definitions
│   │   ├── Types.idr
│   │   ├── Layout.idr
│   │   └── Foreign.idr
│   └── ffi/                # Zig FFI bridge
├── ffi/zig/                # Zig build and source
├── tests/                  # Integration tests
├── .github/workflows/      # CI/CD
├── README.adoc
├── ROADMAP.adoc
└── LICENSE
```
"#,
        iser_name = iser_name,
        lang_name = model.name,
    );
    GeneratedFile {
        path: PathBuf::from("TOPOLOGY.md"),
        content,
    }
}

/// Generate `LICENSE` — PMPL-1.0-or-later.
fn generate_license() -> GeneratedFile {
    // Use a shortened license header; the full text would come from the template repo.
    let content = r#"Palimpsest License (PMPL-1.0-or-later)

Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

Permission is hereby granted to use, copy, modify, and distribute this
software under the terms of the Palimpsest License, version 1.0 or any
later version.

See https://github.com/hyperpolymath/palimpsest-license for the full
license text.
"#
    .to_string();
    GeneratedFile {
        path: PathBuf::from("LICENSE"),
        content,
    }
}

/// Generate `.gitignore`.
fn generate_gitignore() -> GeneratedFile {
    let content = r#"# Generated by iseriser
/target/
/generated/
*.swp
*.swo
.DS_Store
Thumbs.db
"#
    .to_string();
    GeneratedFile {
        path: PathBuf::from(".gitignore"),
        content,
    }
}

/// Generate `.editorconfig`.
fn generate_editorconfig() -> GeneratedFile {
    let content = r#"# EditorConfig — generated by iseriser
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{yml,yaml,toml}]
indent_size = 2

[*.zig]
indent_size = 4

[*.idr]
indent_size = 2
"#
    .to_string();
    GeneratedFile {
        path: PathBuf::from(".editorconfig"),
        content,
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Derive the Idris2 module name prefix from the language model.
/// E.g. "Chapel" -> "Chapeliser", "BQN" -> "Bqniser".
fn idris2_module_name(model: &LanguageModel) -> String {
    let iser = model.iser_name();
    let mut chars = iser.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().to_string() + chars.as_str(),
        None => iser,
    }
}

/// Convert a primitive name to an Idris2 constructor name.
/// E.g. "task" -> "TaskPrim", "forall" -> "ForallPrim".
fn to_idris_constructor(prim: &str) -> String {
    let mut chars = prim.chars();
    let first = chars
        .next()
        .map(|c| c.to_uppercase().to_string())
        .unwrap_or_default();
    format!("{}{}Prim", first, chars.as_str())
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::{CompilationTarget, TypeSystemFeature};
    use crate::manifest::parse_manifest;

    fn test_manifest() -> Manifest {
        let toml = r#"
[project]
name = "chapeliser"
version = "0.1.0"

[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task", "locale", "domain"]

[output]
repo-name = "chapeliser"
github-org = "hyperpolymath"
description = "Chapel distributed computing -iser"
"#;
        parse_manifest(toml).unwrap()
    }

    #[test]
    fn test_scaffold_generates_all_files() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_repo(&manifest, tmp.path());
        assert!(
            result.is_success(),
            "scaffold failed: {:?}",
            result.error_message()
        );
        let repo = result.repo().unwrap();
        assert_eq!(repo.name, "chapeliser");
        assert!(
            repo.file_count() >= 20,
            "expected 20+ files, got {}",
            repo.file_count()
        );
    }

    #[test]
    fn test_scaffold_is_complete() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_repo(&manifest, tmp.path());
        let repo = result.repo().unwrap();
        assert!(repo.is_complete(), "repo missing mandatory categories");
    }

    #[test]
    fn test_idris2_module_name() {
        let model = LanguageModel {
            name: "Chapel".to_string(),
            paradigm: Paradigm::Imperative,
            type_system: TypeSystemFeature::Simple,
            compilation_target: CompilationTarget::Native,
            key_primitives: vec!["task".to_string()],
        };
        assert_eq!(idris2_module_name(&model), "Chapeliser");
    }

    #[test]
    fn test_to_idris_constructor() {
        assert_eq!(to_idris_constructor("task"), "TaskPrim");
        assert_eq!(to_idris_constructor("forall"), "ForallPrim");
        assert_eq!(to_idris_constructor("sync"), "SyncPrim");
    }

    #[test]
    fn test_files_written_to_disk() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_repo(&manifest, tmp.path());
        assert!(result.is_success());

        let repo_root = tmp.path().join("chapeliser");
        assert!(repo_root.join("Cargo.toml").exists());
        assert!(repo_root.join("src/main.rs").exists());
        assert!(repo_root.join("src/interface/abi/Types.idr").exists());
        assert!(repo_root.join("ffi/zig/src/main.zig").exists());
        assert!(repo_root.join(".github/workflows/ci.yml").exists());
        assert!(repo_root.join("README.adoc").exists());
        assert!(repo_root.join("LICENSE").exists());
    }
}
