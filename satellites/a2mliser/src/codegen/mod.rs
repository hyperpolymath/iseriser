// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
use crate::manifest::Manifest;
use anyhow::{Context, Result};
use std::fs;

pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir).context("Failed to create output dir")?;
    println!(
        "  [stub] A2ML codegen for '{}' — implementation pending",
        manifest.workload.name
    );
    Ok(())
}

pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!("Building a2mliser workload: {}", manifest.workload.name);
    Ok(())
}

pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("Running a2mliser workload: {}", manifest.workload.name);
    Ok(())
}
