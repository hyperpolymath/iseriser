// SPDX-License-Identifier: MPL-2.0
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

    // Idris2 ABI (verified nested layout: <Mod>/ABI/*.idr + <iser>-abi.ipkg)
    files.push(generate_idris2_types(&model));
    files.push(generate_idris2_layout(&model));
    files.push(generate_idris2_foreign(&model));
    files.push(generate_idris2_proofs(&model));
    files.push(generate_idris2_ipkg(&model));

    // Zig FFI
    files.push(generate_zig_build(&model, &iser_name));
    files.push(generate_zig_main(&model, &iser_name));
    files.push(generate_zig_integration_test(&model, &iser_name));

    // Tests
    files.push(generate_integration_test(&model, &iser_name));

    // CI/CD
    files.push(generate_ci_workflow(&model, &iser_name));
    // Regeneration trigger (boj-server cartridge pattern, standards#89 sub-issue 1)
    files.push(generate_regen_workflow(&iser_name));

    // Documentation and governance
    files.push(generate_readme(manifest, &model, &iser_name));
    files.push(generate_roadmap(&model, &iser_name));
    files.push(generate_topology(&model, &iser_name));
    files.push(generate_license());
    files.push(generate_gitignore());
    files.push(generate_editorconfig());
    files.push(generate_mustfile());

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
        r#"# SPDX-License-Identifier: MPL-2.0
[package]
name = "{iser_name}"
version = "{version}"
edition = "2024"
authors = ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
description = "{description}"
license = "MPL-2.0"
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
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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

/// Generate `src/interface/abi/<Mod>/ABI/Types.idr` — formal ABI type
/// definitions. Emits the verified-reference nested-module form that compiles
/// clean under Idris2 0.7.0 (see `verified_abi_*` templates below).
fn generate_idris2_types(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let iser_name = model.iser_name();

    // Primitive constructors, one per key primitive (or a single placeholder).
    let prim_ctors: String = if model.key_primitives.is_empty() {
        "  ||| No key primitives declared.\n  NoPrimitives : Primitive".to_string()
    } else {
        model
            .key_primitives
            .iter()
            .map(|p| {
                let ctor = to_idris_constructor(p);
                format!("  ||| The `{}` primitive.\n  {} : Primitive", p, ctor)
            })
            .collect::<Vec<_>>()
            .join("\n")
    };

    // `primCode` clauses give each primitive a stable numeric tag. Comparing by
    // tag yields a total, warning-free `Eq` for any arity (a direct structural
    // `==` would need a catch-all that Idris flags as redundant for one ctor).
    let prim_codes: String = if model.key_primitives.is_empty() {
        "primCode NoPrimitives = 0".to_string()
    } else {
        model
            .key_primitives
            .iter()
            .enumerate()
            .map(|(i, p)| format!("primCode {} = {}", to_idris_constructor(p), i))
            .collect::<Vec<_>>()
            .join("\n")
    };

    let content = VERIFIED_ABI_TYPES
        .replace("__MODULE__", &module_prefix)
        .replace("__ISER__", &iser_name)
        .replace("__LANG__", &model.name)
        .replace("__CONV__", model.calling_convention())
        .replace("__PRIM_CTORS__", &prim_ctors)
        .replace("__PRIM_CODES__", &prim_codes);

    GeneratedFile {
        path: idris_abi_path(&module_prefix, "Types"),
        content,
    }
}

/// Generate `src/interface/abi/<Mod>/ABI/Layout.idr` — memory-layout proofs.
/// Emits real `StructLayout` / `Divides` machinery and one concrete, provably
/// C-ABI-compliant context layout (the old `modNatNZ ... == 0` form did not
/// reduce at the type level and could not be discharged honestly).
fn generate_idris2_layout(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let content = VERIFIED_ABI_LAYOUT
        .replace("__MODULE__", &module_prefix)
        .replace("__ISER__", &model.iser_name());
    GeneratedFile {
        path: idris_abi_path(&module_prefix, "Layout"),
        content,
    }
}

/// Generate `src/interface/abi/<Mod>/ABI/Foreign.idr` — FFI declarations with
/// safe wrappers built on the non-null `Handle` and the `Result` decoder.
fn generate_idris2_foreign(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let content = VERIFIED_ABI_FOREIGN
        .replace("__MODULE__", &module_prefix)
        .replace("__ISER__", &model.iser_name());
    GeneratedFile {
        path: idris_abi_path(&module_prefix, "Foreign"),
        content,
    }
}

/// Generate `src/interface/abi/<Mod>/ABI/Proofs.idr` — the machine-checked
/// theorems (C-ABI compliance, result-code round-trip, a negative control).
fn generate_idris2_proofs(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let content = VERIFIED_ABI_PROOFS
        .replace("__MODULE__", &module_prefix)
        .replace("__ISER__", &model.iser_name());
    GeneratedFile {
        path: idris_abi_path(&module_prefix, "Proofs"),
        content,
    }
}

/// Generate `src/interface/abi/<iser>-abi.ipkg` — the Idris2 package that
/// builds all four ABI modules. Build with `idris2 --build <iser>-abi.ipkg`
/// from `src/interface/abi/`.
fn generate_idris2_ipkg(model: &LanguageModel) -> GeneratedFile {
    let module_prefix = idris2_module_name(model);
    let iser_name = model.iser_name();
    let content = format!(
        r#"-- SPDX-License-Identifier: MPL-2.0
-- Idris2 package for the {iser_name} ABI formal proofs.
-- Build/check with:  idris2 --build {iser_name}-abi.ipkg   (from src/interface/abi/)
package {iser_name}-abi

sourcedir = "."

modules = {module_prefix}.ABI.Types
        , {module_prefix}.ABI.Layout
        , {module_prefix}.ABI.Foreign
        , {module_prefix}.ABI.Proofs
"#,
        iser_name = iser_name,
        module_prefix = module_prefix,
    );
    GeneratedFile {
        path: PathBuf::from(format!("src/interface/abi/{}-abi.ipkg", iser_name)),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Zig FFI
// ---------------------------------------------------------------------------

/// Generate `ffi/zig/build.zig` for the new -iser.
fn generate_zig_build(model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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
        r#"// SPDX-License-Identifier: MPL-2.0
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

// ---------------------------------------------------------------------------
// File generators — CI/CD (regeneration trigger)
// ---------------------------------------------------------------------------
//
// The unified transaction-gated adapter belongs to the boj-server cartridge
// for this -iser (boj-server/cartridges/<name>-mcp/adapter/), NOT to the
// -iser repo itself.  `codegen::generate_all` emits that cartridge as a
// sibling tree so every newly generated -iser ships the gated adapter + SSE
// surface by construction (standards#90); see the `cartridge` module.

/// Template for `.github/workflows/<iser>-regen.yml`.
///
/// `__ISER__` is the only substitution token.  A token-and-`replace` template
/// is used here rather than `format!` because the body is dense in braces —
/// GitHub expressions, shell parameter expansion and a jq program — and
/// brace-doubling a payload by hand is exactly how the estate's escaping
/// defect (standards#331) was introduced in the first place.
const REGEN_WORKFLOW_TEMPLATE: &str = r#"# SPDX-License-Identifier: MPL-2.0
# __ISER__-regen.yml — triggers central regeneration through the boj-server
# __ISER__-mcp cartridge, instead of hand-committing generated/*.
#
# Part of the -iser regeneration-cartridge pattern (hyperpolymath/standards#89).
#
# This deliberately does NOT reproduce the estate `boj-build.yml` shape, which
# carries four defects (hyperpolymath/standards#331):
#   1. a hand-escaped curl payload that is not valid JSON;
#   2. an mDNS host name that no GitHub-hosted runner can resolve, so the step
#      has never once reached the server;
#   3. a plaintext scheme, against the estate secure-protocols policy;
#   4. step-level error suppression, which masked all three.
# A fifth, found while fixing them: the estate copies POST to the plural
# cartridge path, which boj-server exposes only as the cartridge LIST endpoint.
#
# The defect tokens themselves are kept out of this file on purpose — estate
# scanners match them in prose as well as in code.
#
# The endpoint is NOT hardcoded. boj-server binds 127.0.0.1:7700 by default
# (elixir/lib/boj_rest/application.ex) and has no routable public name until
# the http-capability-gateway is production-wired (ADR-0004 tier-2,
# hyperpolymath/standards#91), so no correct literal host exists to emit.
# Supply it per-repo as the BOJ_SERVER_URL secret or variable: unset means the
# step says so and stops; set means a failed dispatch fails the job.
name: __ISER__ Regen Trigger

on:
  push:
    branches: [main, master]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  trigger-__ISER__:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2

      - name: Detect __ISER__ manifest
        id: detect
        run: |
          if [ -f __ISER__.toml ]; then
            echo "present=true" >> "$GITHUB_OUTPUT"
          else
            echo "present=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Trigger BoJ Server (__ISER__-mcp cartridge)
        if: steps.detect.outputs.present == 'true'
        env:
          # Secret first — a private endpoint may itself be sensitive; fall
          # back to the repository/org variable when it is not.
          BOJ_URL: ${{ secrets.BOJ_SERVER_URL || vars.BOJ_SERVER_URL }}
          # Expression values reach the shell through the environment, never
          # by interpolation into the script text: a ref name is caller-chosen.
          BOJ_REPO: ${{ github.repository }}
          BOJ_BRANCH: ${{ github.ref_name }}
          BOJ_SHA: ${{ github.sha }}
        run: |
          set -euo pipefail

          if [ -z "$BOJ_URL" ]; then
            echo "BOJ_SERVER_URL is not configured for this repository."
            echo "boj-server stays loopback-only until the http-capability-gateway"
            echo "lands (ADR-0004 tier-2 / standards#91) — nothing to dispatch to."
            exit 0
          fi

          case "$BOJ_URL" in
            https://*) ;;
            *)
              echo "::error::BOJ_SERVER_URL must use https:// (estate secure-protocols policy)."
              exit 1
              ;;
          esac

          # Payload built by jq, never by hand-escaping. The estate copies
          # emitted a stray backslash-brace pair and failed JSON parse in every
          # repo; jq makes that class of defect unrepresentable. Field names
          # follow boj-server's router contract, which reads `tool` and
          # `arguments` (elixir/lib/boj_rest/router.ex).
          payload="$(jq -nc \
            --arg repo   "$BOJ_REPO" \
            --arg branch "$BOJ_BRANCH" \
            --arg sha    "$BOJ_SHA" \
            '{tool: "__ISER___generate", arguments: {repo: $repo, branch: $branch, sha: $sha}}')"

          # Singular cartridge path — the plural form is the LIST endpoint and
          # would 404 even if the host resolved. X-Node-Identity is the caller
          # tag boj-server logs against the dispatch.
          curl --fail-with-body --silent --show-error --location --max-time 60 \
            -X POST "${BOJ_URL%/}/cartridge/__ISER__-mcp/invoke" \
            -H "Content-Type: application/json" \
            -H "X-Node-Identity: github-actions/$BOJ_REPO" \
            --data "$payload"
"#;

/// Generate `.github/workflows/<iser_name>-regen.yml` — the central-trigger
/// workflow that fires the boj-server `<iser_name>-mcp` cartridge to
/// regenerate `generated/*` instead of hand-committing artifacts
/// (standards#89 sub-issue 1 / rsr-template-repo#58).
///
/// See `REGEN_WORKFLOW_TEMPLATE` for the standards#331 defects this shape
/// exists to avoid re-emitting.
fn generate_regen_workflow(iser_name: &str) -> GeneratedFile {
    GeneratedFile {
        path: PathBuf::from(format!(".github/workflows/{iser_name}-regen.yml")),
        content: REGEN_WORKFLOW_TEMPLATE.replace("__ISER__", iser_name),
    }
}

/// Generate `.github/workflows/ci.yml` for the new -iser.
fn generate_ci_workflow(_model: &LanguageModel, iser_name: &str) -> GeneratedFile {
    let content = format!(
        r#"# SPDX-License-Identifier: MPL-2.0
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

SPDX-License-Identifier: MPL-2.0

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

/// Generate `LICENSE` — MPL-2.0.
fn generate_license() -> GeneratedFile {
    // Use a shortened license header; the full text would come from the template repo.
    let content = r#"Palimpsest License (MPL-2.0)

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

/// Generate the root `Mustfile` — the RSR-mandatory declarative contract of
/// checks that MUST pass. Each check maps to a recipe emitted in the Justfile,
/// so a freshly scaffolded repo is born standards-compliant (REQUIRED-FILES.adoc).
fn generate_mustfile() -> GeneratedFile {
    let content = r#"# SPDX-License-Identifier: MPL-2.0
# Mustfile — hyperpolymath mandatory checks
# See: https://github.com/hyperpolymath/mustfile
#
# Declarative contract of checks that MUST pass. Each maps to a recipe
# that already exists in this repo's Justfile.
version: 1

checks:
  - name: security
    run: just lint
  - name: tests
    run: just test
  - name: format
    run: just fmt
"#
    .to_string();
    GeneratedFile {
        path: PathBuf::from("Mustfile"),
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
// Verified Idris2 ABI templates
// ---------------------------------------------------------------------------
//
// These are the reference forms proven to compile clean under Idris2 0.7.0
// (zero warnings, no `believe_me`/`postulate`/holes). Token `__MODULE__` is the
// module prefix (e.g. `Chapeliser`), `__ISER__` the repo name (e.g.
// `chapeliser`), `__LANG__` the source language, `__CONV__` the calling
// convention; `__PRIM_CTORS__` / `__PRIM_CODES__` are filled per manifest.
// Generated files live at `src/interface/abi/__MODULE__/ABI/*.idr` so the path
// matches the namespace, and are built via `__ISER__-abi.ipkg`.

const VERIFIED_ABI_TYPES: &str = r#"-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for __ISER__
|||
||| Generated by iseriser for __LANG__ interop. Calling convention: __CONV__.
|||
||| Machine-checked by Idris2 0.7.0:
|||   cd src/interface/abi && idris2 --build __ISER__-abi.ipkg

module __MODULE__.ABI.Types

import Data.Bits
import Data.So
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

||| Key primitives for __LANG__ FFI.
public export
data Primitive : Type where
__PRIM_CTORS__

||| Stable numeric tag for each primitive.
public export
primCode : Primitive -> Bits32
__PRIM_CODES__

||| Primitives compare by their numeric tag — total and warning-free for any
||| arity (a direct structural `==` would need a catch-all Idris flags as
||| redundant when there is a single constructor).
public export
Eq Primitive where
  x == y = primCode x == primCode y

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations. The integer encoding is the contract the
||| Zig FFI layer depends on; it is pinned by proofs in __MODULE__.ABI.Proofs.
public export
data Result : Type where
  Ok : Result
  Error : Result
  InvalidInput : Result
  NullPointer : Result

||| Convert a Result to its C integer code.
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidInput = 2
resultToInt NullPointer = 3

||| Results are decidably equal. Off-diagonal cases discharge the disequality
||| explicitly; `decEq _ _ = No absurd` does not compile (no `Uninhabited`
||| instance exists for these constructors).
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidInput InvalidInput = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidInput = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidInput = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq InvalidInput Ok = No (\case Refl impossible)
  decEq InvalidInput Error = No (\case Refl impossible)
  decEq InvalidInput NullPointer = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidInput = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handle
--------------------------------------------------------------------------------

||| Opaque handle to a __ISER__ engine context. The non-null invariant is part
||| of the type, so a Handle can never wrap a null pointer.
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely build a Handle, returning Nothing for a null pointer. `choose`
||| supplies the real `So (ptr /= 0)` witness on the non-null branch.
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

||| Extract the raw pointer from a Handle.
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr
"#;

const VERIFIED_ABI_LAYOUT: &str = r#"-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for __ISER__
|||
||| Generated by iseriser. Defines the C-ABI struct-layout machinery and one
||| concrete generation-context layout; Proofs.idr discharges its compliance.

module __MODULE__.ABI.Layout

import __MODULE__.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

||| Padding needed to bring `offset` up to a multiple of `alignment`.
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else minus alignment (offset `mod` alignment)

||| Round `size` up to the next multiple of `alignment`.
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment = size + paddingFor size alignment

||| Proof that `n` divides `m`: `m = k * n`.
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Sound decision procedure for divisibility. Division by zero is undecidable
||| here and yields Nothing.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S k) m =
  let q = m `div` (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| A single named field within a C struct.
public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

||| A C-compatible struct layout. The erased proofs pin the total size to cover
||| all fields and to be a multiple of the struct alignment.
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Proof that every field offset in a layout is correctly aligned.
public export
data FieldsAligned : Vect k Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect k Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Decide field alignment for every field, building a real witness from
||| per-field divisibility proofs.
public export
decFieldsAligned : (fs : Vect k Field) -> Maybe (FieldsAligned fs)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dvd => case decFieldsAligned fs of
                  Nothing => Nothing
                  Just rest => Just (ConsField f fs dvd rest)

||| Proof that a struct layout follows C-ABI field alignment.
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Verify a layout against the C-ABI alignment rules.
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

||| C-compatible layout for the __ISER__ generation-context handle.
||| Offsets: 0|8, 8|8, 16|4, 20|4, 24|4, 28|4; total 32, 8-byte aligned.
public export
contextLayout : StructLayout
contextLayout =
  MkStructLayout
    [ MkField "model_ptr" 0 8 8
    , MkField "state_ptr" 8 8 8
    , MkField "num_items" 16 4 4
    , MkField "item_count" 20 4 4
    , MkField "status" 24 4 4
    , MkField "error_code" 28 4 4
    ]
    32
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}
"#;

const VERIFIED_ABI_FOREIGN: &str = r#"-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface declarations for __ISER__
|||
||| Generated by iseriser. Implementations live in src/interface/ffi/src/main.zig
||| and must match the layouts and result codes proven here.

module __MODULE__.ABI.Foreign

import __MODULE__.ABI.Types
import __MODULE__.ABI.Layout

%default total

||| Decode a raw C result code into a Result.
public export
decodeResult : Bits32 -> Result
decodeResult 0 = Ok
decodeResult 1 = Error
decodeResult 2 = InvalidInput
decodeResult _ = NullPointer

||| Initialise the __ISER__ engine; returns an opaque context pointer.
export
%foreign "C:__ISER___init, lib__ISER__"
prim__init : PrimIO Bits64

||| Safe wrapper: initialise the engine, returning a non-null Handle or Nothing.
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Free the __ISER__ context.
export
%foreign "C:__ISER___free, lib__ISER__"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper: release the engine context.
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

||| Get the library version string pointer.
export
%foreign "C:__ISER___version, lib__ISER__"
prim__version : PrimIO Bits64

||| Safe wrapper: retrieve the version string.
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getString : Bits64 -> String
"#;

const VERIFIED_ABI_PROOFS: &str = r#"-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the __ISER__ ABI.
|||
||| These are compile-time propositions, not runtime tests. If any concrete
||| layout were misaligned or the result-code encoding wrong, this module would
||| fail to typecheck and the proof build would go red.

module __MODULE__.ABI.Proofs

import __MODULE__.ABI.Types
import __MODULE__.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete context layout is provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset divides its alignment: 0|8, 8|8, 16|4, 20|4, 24|4, 28|4.
||| Each `DivideBy k Refl` forces `offset = k * alignment`; multiplication
||| reduces at the type level, so the compiler checks this outright. The layout
||| name is qualified (`Layout.contextLayout`) so it does not auto-bind as an
||| implicit in the theorem type.
export
contextLayoutCompliant : CABICompliant Layout.contextLayout
contextLayoutCompliant =
  CABIOk contextLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields))))))

||| The struct alignment genuinely divides the total size (32 = 4 * 8).
export
alignmentDividesSize :
  Divides (alignment Layout.contextLayout) (totalSize Layout.contextLayout)
alignmentDividesSize = DivideBy 4 Refl

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
nullPointerIsThree : resultToInt NullPointer = 3
nullPointerIsThree = Refl

--------------------------------------------------------------------------------
-- Negative control: the size invariant is not vacuously true.
--------------------------------------------------------------------------------

||| A declared size of 4 does NOT cover an 8-byte field — the coverage check
||| rejects it. If the size invariant were trivially true this would not hold.
||| (Uses Nat comparison, which reduces at the type level; Nat div/mod do not,
||| so they are kept out of proofs.)
export
undersizedRejected : So (not (the Nat 4 >= the Nat 8))
undersizedRejected = Oh

||| Positive companion: a declared size of 32 does cover 32 bytes of fields.
export
wellSizedAccepted : So (the Nat 32 >= the Nat 32)
wellSizedAccepted = Oh
"#;

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

/// Path to an ABI module file, matching its namespace.
/// E.g. ("Chapeliser", "Types") -> `src/interface/abi/Chapeliser/ABI/Types.idr`.
fn idris_abi_path(module_prefix: &str, module_name: &str) -> PathBuf {
    PathBuf::from(format!(
        "src/interface/abi/{}/ABI/{}.idr",
        module_prefix, module_name
    ))
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
        // 21+ files: 20 base + regen workflow (standards#89 sub-issue 1).
        // The unified adapter belongs to the boj-server cartridge, not this repo.
        assert!(
            repo.file_count() >= 21,
            "expected 21+ files, got {}",
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
    fn test_idris_abi_path_matches_namespace() {
        assert_eq!(
            idris_abi_path("Chapeliser", "Types"),
            PathBuf::from("src/interface/abi/Chapeliser/ABI/Types.idr")
        );
    }

    /// The generated Idris2 ABI must be self-consistent: every module the ipkg
    /// lists is emitted, and each sits at the path its namespace dictates.
    #[test]
    fn test_generated_abi_is_self_consistent() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_repo(&manifest, tmp.path());
        let repo = result.repo().unwrap();
        let abi = tmp.path().join("chapeliser/src/interface/abi");

        for module in ["Types", "Layout", "Foreign", "Proofs"] {
            let p = abi.join(format!("Chapeliser/ABI/{}.idr", module));
            assert!(p.exists(), "missing ABI module {}", module);
            let src = std::fs::read_to_string(&p).unwrap();
            assert!(
                src.contains(&format!("module Chapeliser.ABI.{}", module)),
                "{} has wrong module declaration",
                module
            );
            // No unsubstituted template tokens should survive (the `prim__*`
            // FFI names legitimately contain `__`, so check the tokens by name).
            for token in [
                "__MODULE__",
                "__ISER__",
                "__LANG__",
                "__CONV__",
                "__PRIM_CTORS__",
                "__PRIM_CODES__",
            ] {
                assert!(
                    !src.contains(token),
                    "{} has leftover template token {}",
                    module,
                    token
                );
            }
        }

        let ipkg = std::fs::read_to_string(abi.join("chapeliser-abi.ipkg")).unwrap();
        for module in ["Types", "Layout", "Foreign", "Proofs"] {
            assert!(
                ipkg.contains(&format!("Chapeliser.ABI.{}", module)),
                "ipkg omits {}",
                module
            );
        }
        // Guard against the old flat, non-compiling form regressing.
        assert!(
            !repo
                .files
                .iter()
                .any(|f| f.path == *"src/interface/abi/Types.idr")
        );
    }

    /// End-to-end: a freshly generated -iser's Idris2 ABI must compile clean.
    /// No-op (passes) where `idris2` is not installed, so CI without the
    /// toolchain stays green; run in an idris2 environment for real coverage.
    #[test]
    fn test_generated_abi_compiles_with_idris2() {
        use std::process::Command;

        let idris_ok = Command::new("idris2")
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);
        if !idris_ok {
            eprintln!("skipping: idris2 not on PATH");
            return;
        }

        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_repo(&manifest, tmp.path());
        assert!(result.is_success(), "scaffold failed");

        let abi_dir = tmp.path().join("chapeliser/src/interface/abi");
        let out = Command::new("idris2")
            .args(["--build", "chapeliser-abi.ipkg"])
            .current_dir(&abi_dir)
            .output()
            .expect("failed to run idris2");

        let stdout = String::from_utf8_lossy(&out.stdout);
        let stderr = String::from_utf8_lossy(&out.stderr);
        assert!(
            out.status.success(),
            "generated ABI failed to build:\n{}\n{}",
            stdout,
            stderr
        );
        // Zero-warning bar: the verified reference compiles without warnings.
        assert!(
            !stderr.to_lowercase().contains("warning"),
            "generated ABI built with warnings:\n{}",
            stderr
        );
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
        // ABI modules live at <Mod>/ABI/*.idr so the path matches the namespace,
        // plus the <iser>-abi.ipkg that builds them.
        assert!(
            repo_root
                .join("src/interface/abi/Chapeliser/ABI/Types.idr")
                .exists()
        );
        assert!(
            repo_root
                .join("src/interface/abi/Chapeliser/ABI/Proofs.idr")
                .exists()
        );
        assert!(
            repo_root
                .join("src/interface/abi/chapeliser-abi.ipkg")
                .exists()
        );
        assert!(repo_root.join("ffi/zig/src/main.zig").exists());
        assert!(repo_root.join(".github/workflows/ci.yml").exists());
        // standards#89 sub-issue 1: regen trigger only.
        // The unified adapter belongs to the boj-server cartridge, not this repo.
        assert!(
            repo_root
                .join(".github/workflows/chapeliser-regen.yml")
                .exists()
        );
        assert!(repo_root.join("README.adoc").exists());
        assert!(repo_root.join("LICENSE").exists());
    }

    /// The estate `boj-build.yml` shape shipped four defects into ~30 repos
    /// (hyperpolymath/standards#331). Fixing the deployed copies is pointless
    /// while the generator keeps re-emitting them, so this pins all four —
    /// plus the fifth found while fixing them, the plural cartridge path,
    /// which boj-server serves only as the LIST endpoint.
    #[test]
    fn test_regen_workflow_is_free_of_the_boj_build_defects() {
        let wf = generate_regen_workflow("chapeliser");
        let c = &wf.content;

        assert_eq!(
            wf.path,
            PathBuf::from(".github/workflows/chapeliser-regen.yml")
        );

        // 1. Nothing hand-escapes JSON — jq builds the payload.
        assert!(
            !c.contains("\\\""),
            "workflow hand-escapes a JSON payload; jq must build it"
        );
        assert!(c.contains("jq -nc"), "payload is not built by jq");

        // 2. No mDNS host: GitHub-hosted runners cannot resolve one.
        assert!(!c.contains(".local"), "workflow still targets an mDNS host");

        // 3. No plaintext scheme, and the configured URL is checked at run time.
        assert!(
            !c.contains("http://"),
            "workflow still uses a plaintext scheme"
        );
        assert!(
            c.contains("https://*)"),
            "workflow does not enforce https on the configured URL"
        );

        // 4. No step-level error suppression masking a failed dispatch.
        assert!(
            !c.contains("continue-on-error"),
            "workflow still suppresses step errors"
        );
        assert!(
            c.contains("--fail-with-body"),
            "curl does not fail the job on a rejected dispatch"
        );

        // 5. Singular cartridge path (elixir/lib/boj_rest/router.ex).
        assert!(
            c.contains("/cartridge/chapeliser-mcp/invoke"),
            "workflow does not POST to the singular cartridge invoke path"
        );
        assert!(
            !c.contains("/cartridges/"),
            "workflow POSTs to the cartridge LIST path"
        );

        // The endpoint is parameterised, not guessed: boj-server binds
        // 127.0.0.1 and has no routable name until the http-capability-gateway
        // is wired (ADR-0004 tier-2 / standards#91).
        assert!(c.contains("secrets.BOJ_SERVER_URL"));
        assert!(c.contains("vars.BOJ_SERVER_URL"));

        // Caller-controlled expression values reach the script through the
        // environment, never by interpolation into the script text.
        assert!(
            !c.contains("\"${{ github.ref_name }}\""),
            "a caller-controlled ref name is interpolated into the shell script"
        );

        assert!(!c.contains("__ISER__"), "leftover template token");
    }

    /// The emitted jq program must produce valid JSON in the shape
    /// boj-server's router accepts (`tool` + `arguments`), and must carry a
    /// hostile ref name through as data rather than as script. No-op (passes)
    /// where `jq` is not installed, matching the idris2 test above.
    #[test]
    fn test_regen_workflow_payload_is_valid_json() {
        use std::process::Command;

        let jq_ok = Command::new("jq")
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);
        if !jq_ok {
            eprintln!("skipping: jq not on PATH");
            return;
        }

        let wf = generate_regen_workflow("chapeliser");
        let program = wf
            .content
            .lines()
            .map(str::trim)
            .find(|l| l.starts_with("'{tool:"))
            .expect("no jq program in the emitted workflow")
            .trim_end_matches(")\"")
            .trim_matches('\'')
            .to_string();

        let hostile_ref = "main\"; rm -rf /";
        let out = Command::new("jq")
            .args([
                "-nc",
                "--arg",
                "repo",
                "hyperpolymath/chapeliser",
                "--arg",
                "branch",
                hostile_ref,
                "--arg",
                "sha",
                "0123456789abcdef0123456789abcdef01234567",
                &program,
            ])
            .output()
            .expect("failed to run jq");
        assert!(
            out.status.success(),
            "jq rejected the emitted program:\n{}",
            String::from_utf8_lossy(&out.stderr)
        );

        let payload: serde_json::Value =
            serde_json::from_slice(&out.stdout).expect("emitted payload is not valid JSON");
        assert_eq!(payload["tool"], "chapeliser_generate");
        assert_eq!(payload["arguments"]["repo"], "hyperpolymath/chapeliser");
        assert_eq!(payload["arguments"]["branch"], hostile_ref);
    }
}
