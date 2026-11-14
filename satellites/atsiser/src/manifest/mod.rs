// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for atsiser.toml.
//
// The manifest describes:
// - [project]: name, version, description of the C codebase being wrapped
// - [[c-sources]]: paths to C source/header files with include directories
// - [[ownership-rules]]: per-function ownership annotations (alloc/free/borrow/transfer)
// - [ats2]: ATS2 compiler configuration (patsopt path, flags, output directory)
//
// The manifest drives the entire pipeline: C analysis -> ATS2 generation -> compilation.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Top-level atsiser manifest, parsed from `atsiser.toml`.
///
/// This is the single source of truth for an atsiser project. It describes
/// the C codebase to be wrapped, the ownership semantics of each function,
/// and the ATS2 compiler configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata.
    pub project: ProjectConfig,

    /// C source files to analyse and wrap.
    #[serde(rename = "c-sources", default)]
    pub c_sources: Vec<CSource>,

    /// Ownership rules mapping C functions to memory patterns.
    #[serde(rename = "ownership-rules", default)]
    pub ownership_rules: Vec<OwnershipRule>,

    /// ATS2 compiler configuration.
    #[serde(default)]
    pub ats2: ATS2Config,

    // Legacy fields for backward compatibility with scaffold manifests.
    // These are optional and ignored if the new fields are present.
    #[serde(default)]
    pub workload: Option<WorkloadConfig>,
    #[serde(default)]
    pub data: Option<DataConfig>,
    #[serde(default)]
    pub options: Option<LegacyOptions>,
}

/// Project metadata section `[project]`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name.
    pub name: String,

    /// Semantic version of this atsiser configuration.
    #[serde(default = "default_version")]
    pub version: String,

    /// Brief description of the C codebase being wrapped.
    #[serde(default)]
    pub description: String,

    /// Output directory for generated ATS2 files.
    #[serde(rename = "output-dir", default = "default_output_dir")]
    pub output_dir: String,
}

fn default_version() -> String {
    "0.1.0".to_string()
}

fn default_output_dir() -> String {
    "generated/ats".to_string()
}

/// A C source file entry `[[c-sources]]`.
///
/// Each entry identifies a C header or source file to analyse for memory
/// patterns. The include directories are needed to resolve `#include`
/// directives during parsing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CSource {
    /// Path to the C header or source file (relative to manifest).
    pub path: String,

    /// Include directories for this source (passed as -I flags).
    #[serde(rename = "include-dirs", default)]
    pub include_dirs: Vec<String>,

    /// Optional description of what this source provides.
    #[serde(default)]
    pub description: String,
}

/// An ownership rule `[[ownership-rules]]`.
///
/// Maps a C function to its memory ownership pattern. This is the core
/// annotation that atsiser uses to generate the correct ATS2 linear type
/// wrappers. Each rule tells atsiser:
/// - Which C function to wrap
/// - What ownership pattern it follows (alloc/free/borrow/transfer)
/// - Optionally, which parameter or return type carries the ownership
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OwnershipRule {
    /// The C function name (e.g., "malloc", "fopen", "fclose").
    pub function: String,

    /// The ownership pattern: "alloc", "free", "borrow", or "transfer".
    pub pattern: String,

    /// Optional: which parameter index carries the owned pointer (0-based).
    /// For "free" patterns, this indicates which param is consumed.
    /// For "borrow" patterns, this indicates which param is borrowed.
    #[serde(default)]
    pub param_index: Option<usize>,

    /// Optional: the C type of the resource being managed.
    /// Used to generate the correct viewtype name.
    #[serde(rename = "resource-type", default)]
    pub resource_type: Option<String>,

    /// Optional: a human-readable description of the ownership semantics.
    #[serde(default)]
    pub description: String,
}

/// ATS2 compiler configuration `[ats2]`.
///
/// Controls how the generated ATS2 code is compiled back to C.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ATS2Config {
    /// Path to the patsopt compiler (ATS2 type-checker / compiler).
    #[serde(default = "default_patsopt")]
    pub patsopt: String,

    /// Path to the patscc wrapper (drives C compilation after ATS2).
    #[serde(default = "default_patscc")]
    pub patscc: String,

    /// Additional flags passed to patsopt.
    #[serde(default)]
    pub flags: Vec<String>,

    /// Additional flags passed to the C compiler (gcc/clang) via patscc.
    #[serde(rename = "c-flags", default)]
    pub c_flags: Vec<String>,

    /// PATSHOME environment variable override.
    #[serde(default)]
    pub patshome: Option<String>,
}

fn default_patsopt() -> String {
    "patsopt".to_string()
}

fn default_patscc() -> String {
    "patscc".to_string()
}

impl Default for ATS2Config {
    fn default() -> Self {
        Self {
            patsopt: default_patsopt(),
            patscc: default_patscc(),
            flags: Vec::new(),
            c_flags: Vec::new(),
            patshome: None,
        }
    }
}

// --- Legacy scaffold types (kept for backward compatibility) ---

/// Legacy workload config from the scaffold manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkloadConfig {
    pub name: String,
    pub entry: String,
    #[serde(default)]
    pub strategy: String,
}

/// Legacy data config from the scaffold manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataConfig {
    #[serde(rename = "input-type")]
    pub input_type: String,
    #[serde(rename = "output-type")]
    pub output_type: String,
}

/// Legacy options from the scaffold manifest.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LegacyOptions {
    #[serde(default)]
    pub flags: Vec<String>,
}

// --- Public API ---

/// Loads and deserialises an atsiser.toml manifest from disk.
///
/// # Errors
///
/// Returns an error if the file cannot be read or contains invalid TOML.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validates a manifest for correctness and completeness.
///
/// Checks:
/// - project.name is non-empty
/// - Each c-sources entry has a non-empty path
/// - Each ownership-rule has a valid pattern (alloc/free/borrow/transfer)
/// - ATS2 compiler paths are non-empty
///
/// # Errors
///
/// Returns a descriptive error for the first validation failure found.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name is required
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }

    // Validate C sources
    for (i, source) in manifest.c_sources.iter().enumerate() {
        if source.path.is_empty() {
            anyhow::bail!("c-sources[{}].path is required", i);
        }
    }

    // Validate ownership rules
    let valid_patterns = ["alloc", "free", "borrow", "transfer"];
    for (i, rule) in manifest.ownership_rules.iter().enumerate() {
        if rule.function.is_empty() {
            anyhow::bail!("ownership-rules[{}].function is required", i);
        }
        if !valid_patterns.contains(&rule.pattern.as_str()) {
            anyhow::bail!(
                "ownership-rules[{}].pattern must be one of: alloc, free, borrow, transfer (got: '{}')",
                i,
                rule.pattern
            );
        }
    }

    // Validate ATS2 config
    if manifest.ats2.patsopt.is_empty() {
        anyhow::bail!("ats2.patsopt must not be empty");
    }

    Ok(())
}

/// Writes a new atsiser.toml manifest template to the given directory.
///
/// Creates a manifest with example entries for a typical C library wrapping
/// project (malloc/free patterns).
///
/// # Errors
///
/// Returns an error if the manifest already exists or cannot be written.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("atsiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("atsiser.toml already exists");
    }
    let template = r#"# atsiser manifest — C to ATS2 linear type wrapping
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-c-library"
version = "0.1.0"
description = "ATS2 linear type wrappers for my-c-library"
output-dir = "generated/ats"

# C source files to analyse
[[c-sources]]
path = "include/mylib.h"
include-dirs = ["include"]
description = "Main library header"

# Ownership rules — annotate how each C function handles memory
[[ownership-rules]]
function = "mylib_create"
pattern = "alloc"
resource-type = "mylib_t"
description = "Allocates a new mylib handle"

[[ownership-rules]]
function = "mylib_destroy"
pattern = "free"
param-index = 0
resource-type = "mylib_t"
description = "Frees a mylib handle"

[[ownership-rules]]
function = "mylib_process"
pattern = "borrow"
param-index = 0
description = "Borrows the handle for processing"

# ATS2 compiler configuration
[ats2]
patsopt = "patsopt"
patscc = "patscc"
flags = ["-DATS_MEMALLOC_LIBC"]
c-flags = ["-O2"]
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Prints a human-readable summary of a manifest to stdout.
pub fn print_info(manifest: &Manifest) {
    println!(
        "=== {} v{} ===",
        manifest.project.name, manifest.project.version
    );
    println!("Description: {}", manifest.project.description);
    println!("Output dir:  {}", manifest.project.output_dir);
    println!();

    println!("C Sources ({}):", manifest.c_sources.len());
    for src in &manifest.c_sources {
        println!("  - {} (includes: {:?})", src.path, src.include_dirs);
    }
    println!();

    println!("Ownership Rules ({}):", manifest.ownership_rules.len());
    for rule in &manifest.ownership_rules {
        println!(
            "  - {} [{}]{}",
            rule.function,
            rule.pattern,
            rule.resource_type
                .as_deref()
                .map(|t| format!(" -> {}", t))
                .unwrap_or_default()
        );
    }
    println!();

    println!("ATS2 Config:");
    println!("  patsopt: {}", manifest.ats2.patsopt);
    println!("  patscc:  {}", manifest.ats2.patscc);
    if !manifest.ats2.flags.is_empty() {
        println!("  flags:   {:?}", manifest.ats2.flags);
    }
    if !manifest.ats2.c_flags.is_empty() {
        println!("  c-flags: {:?}", manifest.ats2.c_flags);
    }
}

/// Returns the project name from the manifest, handling both new and legacy formats.
pub fn project_name(manifest: &Manifest) -> &str {
    &manifest.project.name
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_manifest() {
        let toml_str = r#"
[project]
name = "test"
version = "1.0.0"
description = "A test project"

[[c-sources]]
path = "test.h"
include-dirs = ["/usr/include"]

[[ownership-rules]]
function = "malloc"
pattern = "alloc"

[ats2]
patsopt = "patsopt"
"#;
        let manifest: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert_eq!(manifest.project.name, "test");
        assert_eq!(manifest.c_sources.len(), 1);
        assert_eq!(manifest.ownership_rules.len(), 1);
    }

    #[test]
    fn test_validate_empty_name() {
        let manifest = Manifest {
            project: ProjectConfig {
                name: String::new(),
                version: "0.1.0".to_string(),
                description: String::new(),
                output_dir: "out".to_string(),
            },
            c_sources: vec![],
            ownership_rules: vec![],
            ats2: ATS2Config::default(),
            workload: None,
            data: None,
            options: None,
        };
        assert!(validate(&manifest).is_err());
    }

    #[test]
    fn test_validate_invalid_pattern() {
        let manifest = Manifest {
            project: ProjectConfig {
                name: "test".to_string(),
                version: "0.1.0".to_string(),
                description: String::new(),
                output_dir: "out".to_string(),
            },
            c_sources: vec![],
            ownership_rules: vec![OwnershipRule {
                function: "foo".to_string(),
                pattern: "invalid".to_string(),
                param_index: None,
                resource_type: None,
                description: String::new(),
            }],
            ats2: ATS2Config::default(),
            workload: None,
            data: None,
            options: None,
        };
        let err = validate(&manifest).unwrap_err();
        assert!(err.to_string().contains("invalid"));
    }

    #[test]
    fn test_validate_valid_manifest() {
        let manifest = Manifest {
            project: ProjectConfig {
                name: "test".to_string(),
                version: "0.1.0".to_string(),
                description: "A test".to_string(),
                output_dir: "out".to_string(),
            },
            c_sources: vec![CSource {
                path: "test.h".to_string(),
                include_dirs: vec![],
                description: String::new(),
            }],
            ownership_rules: vec![OwnershipRule {
                function: "malloc".to_string(),
                pattern: "alloc".to_string(),
                param_index: None,
                resource_type: Some("void".to_string()),
                description: String::new(),
            }],
            ats2: ATS2Config::default(),
            workload: None,
            data: None,
            options: None,
        };
        assert!(validate(&manifest).is_ok());
    }
}
