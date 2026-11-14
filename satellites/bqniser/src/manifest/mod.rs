// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for bqniser.toml.
//
// The manifest describes:
// - [project]: project metadata (name, version, description)
// - [[patterns]]: array computation patterns to detect and rewrite
// - [bqn]: BQN backend configuration (backend selection, optimisation)
// - [workload] / [data] / [options]: legacy fields for iser-family compat

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

// ---------------------------------------------------------------------------
// Manifest top-level structure
// ---------------------------------------------------------------------------

/// Top-level bqniser.toml manifest.
///
/// Supports both legacy iser-family fields ([workload], [data], [options])
/// and the new BQN-specific sections ([project], [[patterns]], [bqn]).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Legacy workload config (iser-family compat).
    #[serde(default)]
    pub workload: WorkloadConfig,

    /// Legacy data config (iser-family compat).
    #[serde(default)]
    pub data: DataConfig,

    /// Legacy options (iser-family compat).
    #[serde(default)]
    pub options: Options,

    /// Project metadata — name, version, description.
    #[serde(default)]
    pub project: ProjectConfig,

    /// Array computation patterns to detect and rewrite as BQN primitives.
    #[serde(default, rename = "patterns")]
    pub patterns: Vec<PatternEntry>,

    /// BQN backend configuration.
    #[serde(default)]
    pub bqn: BqnConfig,
}

// ---------------------------------------------------------------------------
// Legacy iser-family sections
// ---------------------------------------------------------------------------

/// Workload description (legacy iser-family compat).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WorkloadConfig {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub entry: String,
    #[serde(default)]
    pub strategy: String,
}

/// Data types flowing through the pipeline (legacy iser-family compat).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DataConfig {
    #[serde(rename = "input-type", default)]
    pub input_type: String,
    #[serde(rename = "output-type", default)]
    pub output_type: String,
}

/// Miscellaneous options (legacy iser-family compat).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Options {
    #[serde(default)]
    pub flags: Vec<String>,
}

// ---------------------------------------------------------------------------
// New BQN-specific sections
// ---------------------------------------------------------------------------

/// `[project]` — project metadata.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProjectConfig {
    /// Human-readable project name.
    #[serde(default)]
    pub name: String,

    /// Semantic version string.
    #[serde(default)]
    pub version: String,

    /// Short description of what the project does.
    #[serde(default)]
    pub description: String,
}

/// Recognised source-pattern types that bqniser can detect and rewrite.
///
/// Each variant maps to a family of array computation idioms.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SourcePattern {
    /// Summation loops — rewritten as BQN fold (+´).
    LoopSum,
    /// Map/transform over arrays — rewritten as BQN each (¨) or direct application.
    MapTransform,
    /// Filter with a predicate — rewritten as BQN replicate (/).
    FilterPredicate,
    /// Sorting — rewritten as BQN grade (⍋/⍒) + select (⊏).
    Sort,
    /// Group-by operations — rewritten as BQN group (⊔).
    GroupBy,
}

impl std::fmt::Display for SourcePattern {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SourcePattern::LoopSum => write!(f, "loop-sum"),
            SourcePattern::MapTransform => write!(f, "map-transform"),
            SourcePattern::FilterPredicate => write!(f, "filter-predicate"),
            SourcePattern::Sort => write!(f, "sort"),
            SourcePattern::GroupBy => write!(f, "group-by"),
        }
    }
}

/// `[[patterns]]` — a single array computation pattern entry.
///
/// Each entry describes one pattern to detect in source code and the
/// corresponding BQN primitive rewrite.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatternEntry {
    /// User-chosen name for this pattern (e.g. "sum-prices").
    pub name: String,

    /// The source-pattern family this belongs to.
    #[serde(rename = "source-pattern")]
    pub source_pattern: SourcePattern,

    /// The type of elements flowing into the pattern (e.g. "f64", "i32").
    #[serde(rename = "input-type")]
    pub input_type: String,

    /// The type of the result (e.g. "f64", "Vec<i32>").
    #[serde(rename = "output-type")]
    pub output_type: String,
}

/// `[bqn]` — BQN backend configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BqnConfig {
    /// Which BQN backend to target. Currently only "cbqn" is supported.
    #[serde(default = "default_backend")]
    pub backend: String,

    /// Whether to enable BQN-level optimisations (e.g. fusing operations).
    #[serde(default = "default_optimize")]
    pub optimize: bool,
}

impl Default for BqnConfig {
    fn default() -> Self {
        Self {
            backend: default_backend(),
            optimize: default_optimize(),
        }
    }
}

/// Default backend is CBQN.
fn default_backend() -> String {
    "cbqn".to_string()
}

/// Default optimisation is enabled.
fn default_optimize() -> bool {
    true
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Load a bqniser.toml manifest from disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a parsed manifest.
///
/// Rules:
/// 1. Either project.name or workload.name must be non-empty.
/// 2. Every pattern must have a non-empty name, input-type, and output-type.
/// 3. The BQN backend must be "cbqn" (the only supported backend for now).
pub fn validate(manifest: &Manifest) -> Result<()> {
    // At least one name source must be present.
    let effective_name = effective_name(manifest);
    if effective_name.is_empty() {
        anyhow::bail!("Either [project].name or [workload].name is required");
    }

    // Validate each pattern entry.
    for (i, pat) in manifest.patterns.iter().enumerate() {
        if pat.name.is_empty() {
            anyhow::bail!("patterns[{}].name is required", i);
        }
        if pat.input_type.is_empty() {
            anyhow::bail!("patterns[{}].input-type is required", i);
        }
        if pat.output_type.is_empty() {
            anyhow::bail!("patterns[{}].output-type is required", i);
        }
    }

    // Backend validation.
    if manifest.bqn.backend != "cbqn" {
        anyhow::bail!(
            "Unsupported BQN backend '{}'. Only 'cbqn' is supported.",
            manifest.bqn.backend
        );
    }

    Ok(())
}

/// Initialise a new bqniser.toml in the given directory.
///
/// Creates a complete example manifest with [project], [[patterns]], and [bqn].
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("bqniser.toml");
    if manifest_path.exists() {
        anyhow::bail!("bqniser.toml already exists");
    }
    let template = r#"# bqniser manifest
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my-array-project"
version = "0.1.0"
description = "Array computation patterns rewritten as BQN primitives"

[[patterns]]
name = "sum-values"
source-pattern = "loop-sum"
input-type = "f64"
output-type = "f64"

[[patterns]]
name = "transform-items"
source-pattern = "map-transform"
input-type = "f64"
output-type = "f64"

[[patterns]]
name = "select-valid"
source-pattern = "filter-predicate"
input-type = "f64"
output-type = "Vec<f64>"

[bqn]
backend = "cbqn"
optimize = true
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print human-readable info about the manifest.
pub fn print_info(manifest: &Manifest) {
    let name = effective_name(manifest);
    println!("=== bqniser: {} ===", name);

    if !manifest.project.version.is_empty() {
        println!("Version:     {}", manifest.project.version);
    }
    if !manifest.project.description.is_empty() {
        println!("Description: {}", manifest.project.description);
    }

    println!("Backend:     {}", manifest.bqn.backend);
    println!("Optimise:    {}", manifest.bqn.optimize);
    println!("Patterns:    {}", manifest.patterns.len());

    for pat in &manifest.patterns {
        println!(
            "  - {} ({}) :: {} -> {}",
            pat.name, pat.source_pattern, pat.input_type, pat.output_type
        );
    }

    // Legacy fields if present.
    if !manifest.workload.entry.is_empty() {
        println!("Entry:       {}", manifest.workload.entry);
    }
    if !manifest.data.input_type.is_empty() {
        println!("Data input:  {}", manifest.data.input_type);
        println!("Data output: {}", manifest.data.output_type);
    }
}

/// Return the effective project name, preferring [project].name over [workload].name.
pub fn effective_name(manifest: &Manifest) -> String {
    if !manifest.project.name.is_empty() {
        manifest.project.name.clone()
    } else {
        manifest.workload.name.clone()
    }
}
