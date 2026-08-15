// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub workload: WorkloadConfig,
    pub data: DataConfig,
    #[serde(default)]
    pub options: Options,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkloadConfig {
    pub name: String,
    pub entry: String,
    #[serde(default)]
    pub strategy: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataConfig {
    #[serde(rename = "input-type")]
    pub input_type: String,
    #[serde(rename = "output-type")]
    pub output_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Options {
    #[serde(default)]
    pub flags: Vec<String>,
}

pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content =
        std::fs::read_to_string(path).with_context(|| format!("Failed to read: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse: {}", path))
}

pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.workload.name.is_empty() {
        anyhow::bail!("workload.name required");
    }
    if manifest.workload.entry.is_empty() {
        anyhow::bail!("workload.entry required");
    }
    Ok(())
}

pub fn init_manifest(path: &str) -> Result<()> {
    let p = Path::new(path).join("a2mliser.toml");
    if p.exists() {
        anyhow::bail!("a2mliser.toml already exists");
    }
    std::fs::write(
        &p,
        "# a2mliser manifest\n[workload]\nname = \"my-workload\"\nentry = \"src/lib.rs::process\"\n\n[data]\ninput-type = \"Vec<Item>\"\noutput-type = \"Vec<Result>\"\n",
    )?;
    println!("Created {}", p.display());
    Ok(())
}

pub fn print_info(m: &Manifest) {
    println!(
        "=== {} ===\nEntry: {}\nInput: {}\nOutput: {}",
        m.workload.name, m.workload.entry, m.data.input_type, m.data.output_type
    );
}
