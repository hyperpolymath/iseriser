// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for halideiser.toml.
//
// The manifest describes an image/video processing pipeline with:
//   [project]     — name, version, description
//   [[stages]]    — ordered pipeline stages (blur, sharpen, resize, etc.)
//   [target]      — hardware target (x86, arm, cuda, opencl, wasm)
//   [pipeline]    — input/output format, bit depth

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::{
    HalideOperation, HardwareTarget, PipelineStage, PixelType, StageParams, validate_stage,
};

// ---------------------------------------------------------------------------
// Top-level Manifest
// ---------------------------------------------------------------------------

/// Top-level halideiser manifest parsed from halideiser.toml.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata.
    pub project: ProjectConfig,
    /// Ordered sequence of pipeline stages.
    #[serde(rename = "stages")]
    pub stages: Vec<ManifestStage>,
    /// Hardware target configuration.
    pub target: TargetConfig,
    /// Pipeline I/O configuration.
    pub pipeline: PipelineConfig,
}

// ---------------------------------------------------------------------------
// [project]
// ---------------------------------------------------------------------------

/// Project metadata from the `[project]` section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable pipeline name (used as the C++ class/namespace name).
    pub name: String,
    /// Semantic version string.
    #[serde(default = "default_version")]
    pub version: String,
    /// Optional one-line description.
    #[serde(default)]
    pub description: Option<String>,
}

fn default_version() -> String {
    "0.1.0".to_string()
}

// ---------------------------------------------------------------------------
// [[stages]]
// ---------------------------------------------------------------------------

/// A stage entry in the manifest. Mirrors `PipelineStage` from the ABI but
/// uses TOML-friendly field names.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestStage {
    /// Stage name (must be a valid C identifier).
    pub name: String,
    /// The operation to perform.
    pub operation: HalideOperation,
    /// Operation-specific parameters (all optional with sensible defaults).
    #[serde(flatten)]
    pub params: StageParams,
}

impl ManifestStage {
    /// Convert this manifest stage into the ABI `PipelineStage` type.
    pub fn to_pipeline_stage(&self) -> PipelineStage {
        PipelineStage {
            name: self.name.clone(),
            operation: self.operation.clone(),
            params: self.params.clone(),
        }
    }
}

// ---------------------------------------------------------------------------
// [target]
// ---------------------------------------------------------------------------

/// Hardware target configuration from the `[target]` section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TargetConfig {
    /// Architecture to target.
    pub arch: HardwareTarget,
    /// Whether to auto-vectorize inner loops.
    #[serde(default = "default_true")]
    pub vectorize: bool,
    /// Whether to auto-parallelize outer loops.
    #[serde(default = "default_true")]
    pub parallelize: bool,
}

fn default_true() -> bool {
    true
}

// ---------------------------------------------------------------------------
// [pipeline]
// ---------------------------------------------------------------------------

/// Pipeline I/O configuration from the `[pipeline]` section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineConfig {
    /// Input image/video format (e.g. "png", "jpg", "raw", "mp4").
    #[serde(rename = "input-format")]
    pub input_format: String,
    /// Output image/video format.
    #[serde(rename = "output-format")]
    pub output_format: String,
    /// Pixel bit depth and type.
    #[serde(rename = "bit-depth", default = "default_pixel_type")]
    pub bit_depth: PixelType,
}

fn default_pixel_type() -> PixelType {
    PixelType::Uint8
}

// ---------------------------------------------------------------------------
// Load / Validate / Init / Info
// ---------------------------------------------------------------------------

/// Load a manifest from a TOML file on disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    parse_manifest(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Parse a manifest from a TOML string (useful for testing without disk I/O).
pub fn parse_manifest(toml_str: &str) -> Result<Manifest> {
    toml::from_str(toml_str).context("Invalid halideiser.toml")
}

/// Validate a parsed manifest for semantic correctness.
/// Checks:
///   - project.name is non-empty and a valid C identifier
///   - at least one stage is defined
///   - each stage's parameters are consistent with its operation
///   - pipeline formats are non-empty
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name must be non-empty.
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }

    // Project name must be a valid C identifier (alphanumeric + underscore, not starting with digit).
    if !is_valid_c_identifier(&manifest.project.name) {
        anyhow::bail!(
            "project.name '{}' is not a valid C identifier (use [a-zA-Z_][a-zA-Z0-9_]*)",
            manifest.project.name
        );
    }

    // At least one stage.
    if manifest.stages.is_empty() {
        anyhow::bail!("At least one [[stages]] entry is required");
    }

    // Validate each stage.
    for stage in &manifest.stages {
        if stage.name.is_empty() {
            anyhow::bail!("Each stage must have a non-empty name");
        }
        if !is_valid_c_identifier(&stage.name) {
            anyhow::bail!("Stage name '{}' is not a valid C identifier", stage.name);
        }
        let ps = stage.to_pipeline_stage();
        validate_stage(&ps).map_err(|e| anyhow::anyhow!("Stage validation failed: {}", e))?;
    }

    // Check for duplicate stage names.
    let mut seen = std::collections::HashSet::new();
    for stage in &manifest.stages {
        if !seen.insert(&stage.name) {
            anyhow::bail!("Duplicate stage name: '{}'", stage.name);
        }
    }

    // Pipeline formats.
    if manifest.pipeline.input_format.is_empty() {
        anyhow::bail!("pipeline.input-format is required");
    }
    if manifest.pipeline.output_format.is_empty() {
        anyhow::bail!("pipeline.output-format is required");
    }

    Ok(())
}

/// Check if a string is a valid C identifier.
fn is_valid_c_identifier(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let mut chars = s.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// Write a template halideiser.toml to the given directory.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("halideiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("halideiser.toml already exists");
    }
    let template = r#"# halideiser manifest — image/video pipeline description
# SPDX-License-Identifier: MPL-2.0

[project]
name = "my_pipeline"
version = "0.1.0"
description = "Example image processing pipeline"

[[stages]]
name = "gaussian_blur"
operation = "blur"
kernel-size = 5
sigma = 1.4

[[stages]]
name = "sharpen_output"
operation = "sharpen"
kernel-size = 3

[target]
arch = "x86"
vectorize = true
parallelize = true

[pipeline]
input-format = "png"
output-format = "png"
bit-depth = "uint8"
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print human-readable information about a manifest.
pub fn print_info(manifest: &Manifest) {
    println!(
        "=== {} v{} ===",
        manifest.project.name, manifest.project.version
    );
    if let Some(ref desc) = manifest.project.description {
        println!("  {}", desc);
    }
    println!();
    println!("Stages ({}):", manifest.stages.len());
    for (i, stage) in manifest.stages.iter().enumerate() {
        println!("  {}. {} — {}", i + 1, stage.name, stage.operation);
    }
    println!();
    println!(
        "Target: {} (vectorize={}, parallelize={})",
        manifest.target.arch, manifest.target.vectorize, manifest.target.parallelize,
    );
    println!(
        "Pipeline: {} -> {} ({})",
        manifest.pipeline.input_format,
        manifest.pipeline.output_format,
        manifest.pipeline.bit_depth,
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal valid manifest for testing.
    pub const MINIMAL_MANIFEST: &str = r#"
[project]
name = "test_pipeline"

[[stages]]
name = "blur_stage"
operation = "blur"
kernel-size = 3

[target]
arch = "x86"

[pipeline]
input-format = "png"
output-format = "png"
"#;

    #[test]
    fn test_parse_minimal_manifest() {
        let m = parse_manifest(MINIMAL_MANIFEST).expect("TODO: handle error");
        assert_eq!(m.project.name, "test_pipeline");
        assert_eq!(m.stages.len(), 1);
        assert_eq!(m.stages[0].operation, HalideOperation::Blur);
        assert_eq!(m.target.arch, HardwareTarget::X86);
        assert!(m.target.vectorize); // default true
    }

    #[test]
    fn test_validate_empty_name() {
        let toml_str = r#"
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
        let m = parse_manifest(toml_str).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_no_stages() {
        let toml_str = r#"
[project]
name = "empty"

[target]
arch = "arm"

[pipeline]
input-format = "raw"
output-format = "raw"
"#;
        // toml parser requires at least the key; we test with empty array
        let toml_str_with_stages = r#"
[project]
name = "empty"
stages = []

[target]
arch = "arm"

[pipeline]
input-format = "raw"
output-format = "raw"
"#;
        let result = parse_manifest(toml_str_with_stages);
        if let Ok(m) = result {
            assert!(validate(&m).is_err());
        }
        // Also test that missing stages key fails parse
        assert!(parse_manifest(toml_str).is_err());
    }

    #[test]
    fn test_is_valid_c_identifier() {
        assert!(is_valid_c_identifier("foo"));
        assert!(is_valid_c_identifier("_bar"));
        assert!(is_valid_c_identifier("baz_123"));
        assert!(!is_valid_c_identifier(""));
        assert!(!is_valid_c_identifier("123abc"));
        assert!(!is_valid_c_identifier("foo-bar"));
    }
}
