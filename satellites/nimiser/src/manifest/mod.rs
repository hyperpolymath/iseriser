// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for nimiser.toml.
//
// The nimiser manifest describes a C library interface to be generated via Nim
// metaprogramming. It contains three main sections:
//   [project]       — project name, version, description
//   [[functions]]   — function signatures with types, params, pragmas
//   [nim]           — Nim compiler settings: backend, GC, optimisation

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::{CompilationTarget, GcStrategy};

/// Top-level nimiser manifest.
/// Parsed from a `nimiser.toml` file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    pub project: ProjectConfig,
    /// Function declarations to generate.
    #[serde(default, rename = "functions")]
    pub functions: Vec<FunctionConfig>,
    /// Nim compiler configuration.
    #[serde(default)]
    pub nim: NimConfig,

    // --- Legacy fields for backward compatibility with scaffold manifests ---
    /// Legacy workload config (deprecated, use project instead).
    #[serde(default)]
    pub workload: Option<WorkloadConfig>,
    /// Legacy data config (deprecated).
    #[serde(default)]
    pub data: Option<DataConfig>,
    /// Legacy options (deprecated, use nim instead).
    #[serde(default)]
    pub options: Option<LegacyOptions>,
}

/// Project-level metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Library/project name (used for output file naming).
    pub name: String,
    /// Semantic version string.
    #[serde(default = "default_version")]
    pub version: String,
    /// Short description of the library.
    #[serde(default)]
    pub description: String,
    /// Library author.
    #[serde(default)]
    pub author: String,
}

fn default_version() -> String {
    "0.1.0".to_string()
}

/// A single function declaration in the manifest.
/// Describes one C-exported proc to be generated.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionConfig {
    /// Function name.
    pub name: String,
    /// Function parameters — list of "name: type" pairs.
    #[serde(default)]
    pub params: Vec<ParamConfig>,
    /// Return type (Nim type name). Empty or absent means void.
    #[serde(default, rename = "return-type")]
    pub return_type: String,
    /// Pragmas to apply: "exportc", "cdecl", "packed", "noSideEffect", "inline", "raises_none".
    #[serde(default)]
    pub pragmas: Vec<String>,
    /// Optional documentation comment for the generated proc.
    #[serde(default)]
    pub doc: String,
}

/// A function parameter with name and type.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParamConfig {
    /// Parameter name.
    pub name: String,
    /// Parameter type (Nim type string, e.g. "cint", "ptr cfloat", "cstring").
    #[serde(rename = "type")]
    pub param_type: String,
}

/// Nim compiler configuration section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NimConfig {
    /// Compilation backend: "c", "cpp", or "js".
    #[serde(default)]
    pub backend: CompilationTarget,
    /// Garbage collector strategy: "arc", "orc", or "none".
    #[serde(default)]
    pub gc: GcStrategy,
    /// Optimisation level: "none", "speed", "size".
    #[serde(default = "default_opt_level")]
    #[serde(rename = "opt-level")]
    pub opt_level: String,
    /// Additional Nim compiler flags.
    #[serde(default)]
    pub flags: Vec<String>,
    /// Output directory for generated .nim and build files.
    #[serde(default = "default_out_dir")]
    #[serde(rename = "out-dir")]
    pub out_dir: String,
}

fn default_opt_level() -> String {
    "speed".to_string()
}

fn default_out_dir() -> String {
    "generated/nim".to_string()
}

impl Default for NimConfig {
    fn default() -> Self {
        NimConfig {
            backend: CompilationTarget::default(),
            gc: GcStrategy::default(),
            opt_level: default_opt_level(),
            flags: Vec::new(),
            out_dir: default_out_dir(),
        }
    }
}

// --- Legacy types for backward compatibility ---

/// Legacy workload config (from scaffold era).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WorkloadConfig {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub entry: String,
    #[serde(default)]
    pub strategy: String,
}

/// Legacy data config (from scaffold era).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DataConfig {
    #[serde(default, rename = "input-type")]
    pub input_type: String,
    #[serde(default, rename = "output-type")]
    pub output_type: String,
}

/// Legacy options (from scaffold era).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LegacyOptions {
    #[serde(default)]
    pub flags: Vec<String>,
}

// --- Public API ---

/// Load and deserialise a nimiser.toml manifest from the given path.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate the manifest for required fields and logical consistency.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name is required.
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }

    // Validate each function declaration.
    for (i, func) in manifest.functions.iter().enumerate() {
        if func.name.is_empty() {
            anyhow::bail!("functions[{}].name is required", i);
        }

        // Validate pragma names.
        for pragma in &func.pragmas {
            validate_pragma_name(pragma).with_context(|| {
                format!("Invalid pragma in function '{}': {}", func.name, pragma)
            })?;
        }

        // Validate param types are non-empty.
        for param in &func.params {
            if param.name.is_empty() {
                anyhow::bail!(
                    "functions[{}] ('{}') has a parameter with an empty name",
                    i,
                    func.name
                );
            }
            if param.param_type.is_empty() {
                anyhow::bail!(
                    "functions[{}] ('{}') parameter '{}' has no type",
                    i,
                    func.name,
                    param.name
                );
            }
        }
    }

    // Validate opt-level.
    match manifest.nim.opt_level.as_str() {
        "none" | "speed" | "size" => {}
        other => anyhow::bail!(
            "Invalid nim.opt-level '{}': must be 'none', 'speed', or 'size'",
            other
        ),
    }

    Ok(())
}

/// Check that a pragma string is a recognised pragma name.
fn validate_pragma_name(pragma: &str) -> Result<()> {
    const VALID_PRAGMAS: &[&str] = &[
        "exportc",
        "cdecl",
        "stdcall",
        "packed",
        "noSideEffect",
        "inline",
        "raises_none",
    ];
    if VALID_PRAGMAS.contains(&pragma) {
        Ok(())
    } else {
        anyhow::bail!(
            "Unknown pragma '{}'. Valid pragmas: {}",
            pragma,
            VALID_PRAGMAS.join(", ")
        )
    }
}

/// Write a default nimiser.toml template into the given directory.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("nimiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("nimiser.toml already exists");
    }
    let template = r#"# nimiser manifest — generate C libraries via Nim metaprogramming
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-library"
version = "0.1.0"
description = "A high-performance C library generated via Nim"
author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"

[[functions]]
name = "add"
return-type = "cint"
pragmas = ["exportc", "cdecl"]
doc = "Add two integers."

  [[functions.params]]
  name = "a"
  type = "cint"

  [[functions.params]]
  name = "b"
  type = "cint"

[[functions]]
name = "multiply"
return-type = "cdouble"
pragmas = ["exportc", "cdecl", "noSideEffect"]
doc = "Multiply two doubles."

  [[functions.params]]
  name = "x"
  type = "cdouble"

  [[functions.params]]
  name = "y"
  type = "cdouble"

[nim]
backend = "c"
gc = "arc"
opt-level = "speed"
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print summary information about a loaded manifest.
pub fn print_info(manifest: &Manifest) {
    println!(
        "=== {} v{} ===",
        manifest.project.name, manifest.project.version
    );
    if !manifest.project.description.is_empty() {
        println!("Description: {}", manifest.project.description);
    }
    println!("Backend:     {}", manifest.nim.backend);
    println!("GC:          {}", manifest.nim.gc);
    println!("Opt level:   {}", manifest.nim.opt_level);
    println!("Functions:   {}", manifest.functions.len());
    for func in &manifest.functions {
        let ret = if func.return_type.is_empty() {
            "void".to_string()
        } else {
            func.return_type.clone()
        };
        let param_strs: Vec<String> = func
            .params
            .iter()
            .map(|p| format!("{}: {}", p.name, p.param_type))
            .collect();
        println!(
            "  - {}({}) -> {} [{}]",
            func.name,
            param_strs.join(", "),
            ret,
            func.pragmas.join(", ")
        );
    }
}
