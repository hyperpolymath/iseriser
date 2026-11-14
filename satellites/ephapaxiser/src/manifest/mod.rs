// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for ephapaxiser — Parses and validates ephapaxiser.toml configuration.
//
// The manifest describes:
// - [project]: Project metadata (name)
// - [[sources]]: Source files to analyse, with language annotation
// - [[resources]]: Resource types to track, with allocator/deallocator pairs and kind
// - [analysis]: Analysis options (which violations to detect, report format)
//
// Example ephapaxiser.toml:
// ```toml
// [project]
// name = "my-safe-resources"
//
// [[sources]]
// name = "file-handler"
// path = "src/file_ops.rs"
// language = "rust"
//
// [[resources]]
// name = "FileHandle"
// allocator = "open"
// deallocator = "close"
// kind = "file-descriptor"
//
// [analysis]
// detect-leaks = true
// detect-double-free = true
// detect-use-after-free = true
// report-format = "text"
// ```

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::ResourceKind;

/// Top-level manifest structure, corresponding to an ephapaxiser.toml file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata.
    pub project: ProjectConfig,
    /// Source files to analyse.
    #[serde(default)]
    pub sources: Vec<SourceEntry>,
    /// Resource definitions to track.
    #[serde(default)]
    pub resources: Vec<ResourceEntry>,
    /// Analysis configuration.
    #[serde(default)]
    pub analysis: AnalysisConfig,
}

/// Project-level configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name.
    pub name: String,
}

/// Supported source languages for analysis.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SourceLanguage {
    /// Rust source files (.rs).
    Rust,
    /// C source files (.c, .h).
    C,
    /// Zig source files (.zig).
    Zig,
}

impl std::fmt::Display for SourceLanguage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Rust => write!(f, "rust"),
            Self::C => write!(f, "c"),
            Self::Zig => write!(f, "zig"),
        }
    }
}

/// A source file entry in the manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceEntry {
    /// Human-readable name for this source unit.
    pub name: String,
    /// Path to the source file (relative to manifest location).
    pub path: String,
    /// Programming language of the source file.
    pub language: SourceLanguage,
}

/// A resource definition in the manifest.
///
/// Describes a resource type with its allocator/deallocator pair, used to
/// generate linear type wrappers and detect violations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceEntry {
    /// Type name for this resource (e.g., "FileHandle").
    pub name: String,
    /// Function name that allocates this resource (e.g., "open").
    pub allocator: String,
    /// Function name that deallocates this resource (e.g., "close").
    pub deallocator: String,
    /// Classification of the resource.
    pub kind: String,
}

impl ResourceEntry {
    /// Convert the string `kind` field to a typed `ResourceKind`.
    pub fn resource_kind(&self) -> ResourceKind {
        ResourceKind::from_str_loose(&self.kind)
    }
}

/// Supported output report formats.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum ReportFormat {
    /// Plain text output.
    #[default]
    Text,
    /// JSON output.
    Json,
    /// A2ML output (for machine-readable AI manifests).
    A2ml,
}

/// Analysis configuration — controls which violation types to detect and output format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisConfig {
    /// Whether to detect resource leaks (allocated but never freed).
    #[serde(rename = "detect-leaks", default = "default_true")]
    pub detect_leaks: bool,
    /// Whether to detect double-free violations.
    #[serde(rename = "detect-double-free", default = "default_true")]
    pub detect_double_free: bool,
    /// Whether to detect use-after-free violations.
    #[serde(rename = "detect-use-after-free", default = "default_true")]
    pub detect_use_after_free: bool,
    /// Output report format.
    #[serde(rename = "report-format", default)]
    pub report_format: ReportFormat,
}

/// Helper for serde default = true.
fn default_true() -> bool {
    true
}

impl Default for AnalysisConfig {
    fn default() -> Self {
        Self {
            detect_leaks: true,
            detect_double_free: true,
            detect_use_after_free: true,
            report_format: ReportFormat::Text,
        }
    }
}

/// Load and parse an ephapaxiser.toml manifest from the given path.
///
/// Returns the parsed `Manifest` or an error with context about what went wrong.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a parsed manifest for logical consistency.
///
/// Checks:
/// - Project name is non-empty
/// - At least one source file is defined
/// - At least one resource is defined
/// - Resource kinds are recognised values
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name must not be empty");
    }
    if manifest.sources.is_empty() {
        anyhow::bail!("At least one [[sources]] entry is required");
    }
    if manifest.resources.is_empty() {
        anyhow::bail!("At least one [[resources]] entry is required");
    }
    for source in &manifest.sources {
        if source.path.is_empty() {
            anyhow::bail!("Source '{}' has an empty path", source.name);
        }
    }
    for resource in &manifest.resources {
        if resource.allocator.is_empty() {
            anyhow::bail!("Resource '{}' has an empty allocator", resource.name);
        }
        if resource.deallocator.is_empty() {
            anyhow::bail!("Resource '{}' has an empty deallocator", resource.name);
        }
    }
    Ok(())
}

/// Create a new default ephapaxiser.toml in the given directory.
///
/// Writes a well-commented example manifest that users can customise.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("ephapaxiser.toml");
    if manifest_path.exists() {
        anyhow::bail!(
            "ephapaxiser.toml already exists at {}",
            manifest_path.display()
        );
    }

    let content = r#"# SPDX-License-Identifier: MPL-2.0
# ephapaxiser manifest — Enforce single-use linear type semantics on resources

[project]
name = "my-safe-resources"

# Source files to analyse for resource usage patterns.
# Supported languages: rust, c, zig
[[sources]]
name = "main-module"
path = "src/main.rs"
language = "rust"

# Resource definitions — each resource has an allocator/deallocator pair.
# Supported kinds: file-descriptor, socket, lock, allocation, gpu-buffer, db-connection, custom
[[resources]]
name = "FileHandle"
allocator = "open"
deallocator = "close"
kind = "file-descriptor"

# Analysis options
[analysis]
detect-leaks = true
detect-double-free = true
detect-use-after-free = true
report-format = "text"    # text | json | a2ml
"#;

    std::fs::write(&manifest_path, content)
        .with_context(|| format!("Failed to write manifest to {}", manifest_path.display()))?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print a summary of the manifest to stdout.
pub fn print_info(m: &Manifest) {
    println!("=== {} ===", m.project.name);
    println!("Sources ({}):", m.sources.len());
    for s in &m.sources {
        println!("  - {} ({}) [{}]", s.name, s.path, s.language);
    }
    println!("Resources ({}):", m.resources.len());
    for r in &m.resources {
        println!(
            "  - {} (alloc: {}, dealloc: {}, kind: {})",
            r.name, r.allocator, r.deallocator, r.kind
        );
    }
    println!("Analysis:");
    println!("  detect-leaks: {}", m.analysis.detect_leaks);
    println!("  detect-double-free: {}", m.analysis.detect_double_free);
    println!(
        "  detect-use-after-free: {}",
        m.analysis.detect_use_after_free
    );
    println!("  report-format: {:?}", m.analysis.report_format);
}
