// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for anvomidaviser — Parses and validates anvomidaviser.toml
// manifest files that describe ISU figure skating competition programs.
// The manifest specifies discipline, segment, level, element codes, and
// scoring season to fully define a program for formal analysis.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::{Discipline, Level, Segment};

/// Top-level manifest structure parsed from anvomidaviser.toml.
/// Describes a complete figure skating competition program.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata
    pub project: ProjectConfig,
    /// Program configuration (discipline, segment, level)
    pub program: ProgramConfig,
    /// Ordered list of program elements in ISU notation
    pub elements: Vec<ElementEntry>,
    /// Scoring configuration
    #[serde(default)]
    pub scoring: ScoringConfig,
}

/// Project-level metadata for the manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable name for this program/competition entry
    pub name: String,
}

/// Program parameters: discipline, segment, and competitive level.
/// These determine which ISU technical rules apply.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgramConfig {
    /// The skating discipline (singles, pairs, ice-dance)
    pub discipline: Discipline,
    /// The program segment (short or free)
    pub segment: Segment,
    /// The competitive level (senior, junior, novice)
    pub level: Level,
}

/// A single element entry in the manifest, specified by ISU notation code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElementEntry {
    /// ISU element notation code (e.g. "3Lz+3T", "CCoSp4", "StSq3")
    pub code: String,
}

/// Scoring configuration: which ISU scoring season tables to use.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoringConfig {
    /// ISU scoring season for base value tables (e.g. "2024-2025")
    #[serde(rename = "goe-table", default = "default_goe_table")]
    pub goe_table: String,
}

impl Default for ScoringConfig {
    fn default() -> Self {
        Self {
            goe_table: default_goe_table(),
        }
    }
}

/// Default GOE table season string.
fn default_goe_table() -> String {
    "2024-2025".to_string()
}

/// Load a manifest from the given TOML file path.
///
/// # Errors
/// Returns an error if the file cannot be read or parsed as valid TOML.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a loaded manifest for basic structural correctness.
/// This checks manifest-level constraints (non-empty name, non-empty elements).
/// ISU rule validation (Zayak, element limits) is handled by the validator module.
///
/// # Errors
/// Returns an error if required fields are missing or invalid.
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required and must not be empty");
    }
    if manifest.elements.is_empty() {
        anyhow::bail!("At least one [[elements]] entry is required");
    }
    for (i, elem) in manifest.elements.iter().enumerate() {
        if elem.code.trim().is_empty() {
            anyhow::bail!("Element {} has an empty code", i + 1);
        }
    }
    Ok(())
}

/// Create a new anvomidaviser.toml manifest at the given directory path,
/// pre-populated with example elements for a free skate program.
///
/// # Errors
/// Returns an error if the file already exists or cannot be written.
pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("anvomidaviser.toml");
    if p.exists() {
        anyhow::bail!("anvomidaviser.toml already exists at {}", p.display());
    }
    let content = r#"# SPDX-License-Identifier: MPL-2.0
# anvomidaviser manifest — ISU figure skating program description

[project]
name = "competition-program"

[program]
discipline = "singles"
segment = "free"
level = "senior"

[[elements]]
code = "3Lz+3T"

[[elements]]
code = "3F"

[[elements]]
code = "CCoSp4"

[[elements]]
code = "StSq3"

[[elements]]
code = "2A"

[scoring]
goe-table = "2024-2025"
"#;
    std::fs::write(&p, content)?;
    println!("Created {}", p.display());
    Ok(())
}

/// Print summary information about a loaded manifest to stdout.
pub fn print_info(m: &Manifest) {
    println!("=== {} ===", m.project.name);
    println!(
        "Program: {} {} ({})",
        m.program.level, m.program.discipline, m.program.segment
    );
    println!("Elements ({}):", m.elements.len());
    for (i, elem) in m.elements.iter().enumerate() {
        println!("  {}. {}", i + 1, elem.code);
    }
    println!("Scoring table: {}", m.scoring.goe_table);
}
