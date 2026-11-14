// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Codegen module for mylangiser — orchestrates the generation of
// progressive-disclosure wrapper code from a parsed manifest.
//
// Submodules:
// - `parser`    — Parse endpoint definitions, extract parameters with types
// - `scorer`    — Calculate complexity scores with weighted factors
// - `layer_gen` — Generate beginner/intermediate/expert wrapper layers

pub mod layer_gen;
pub mod parser;
pub mod scorer;

use anyhow::{Context, Result};
use std::fs;

use crate::manifest::Manifest;

/// Generate all artifacts from a manifest: score endpoints, assign levels,
/// and produce layered wrapper code in the output directory.
///
/// Output structure:
/// ```text
/// <output_dir>/
///   summary.txt          — Complexity scores and level assignments
///   beginner/             — Beginner-layer wrappers
///   intermediate/         — Intermediate-layer wrappers
///   expert/               — Expert-layer (full API) wrappers
/// ```
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    fs::create_dir_all(output_dir).context("Failed to create output dir")?;

    // Phase 1: Score all endpoints and assign disclosure levels.
    let scored = scorer::score_all_endpoints(&manifest.endpoints, &manifest.levels);
    println!("Scored {} endpoints:", scored.len());
    for (name, score, level) in &scored {
        println!(
            "  {} — complexity: {}, level: {:?}",
            name, score.value, level
        );
    }

    // Phase 2: Generate layered wrappers.
    let layers = layer_gen::generate_layers(manifest);

    // Phase 3: Write output files.
    // Summary file with scores and assignments.
    let mut summary_lines = Vec::new();
    summary_lines.push(format!(
        "# mylangiser disclosure summary for '{}'",
        manifest.project.name
    ));
    summary_lines.push(format!(
        "# Thresholds: beginner <= {}, expert >= {}",
        manifest.levels.beginner_threshold, manifest.levels.expert_threshold
    ));
    summary_lines.push(String::new());

    for (name, score, level) in &scored {
        summary_lines.push(format!(
            "{}: complexity={}, level={:?}",
            name, score.value, level
        ));
    }
    fs::write(
        format!("{}/summary.txt", output_dir),
        summary_lines.join("\n"),
    )
    .context("Failed to write summary")?;

    // Write layer files for each level.
    for level_dir in &["beginner", "intermediate", "expert"] {
        fs::create_dir_all(format!("{}/{}", output_dir, level_dir))
            .context("Failed to create level dir")?;
    }

    for wrapper in &layers {
        fs::write(
            format!("{}/beginner/{}.mylang", output_dir, wrapper.endpoint_name),
            &wrapper.beginner_code,
        )
        .context("Failed to write beginner wrapper")?;

        fs::write(
            format!(
                "{}/intermediate/{}.mylang",
                output_dir, wrapper.endpoint_name
            ),
            &wrapper.intermediate_code,
        )
        .context("Failed to write intermediate wrapper")?;

        fs::write(
            format!("{}/expert/{}.mylang", output_dir, wrapper.endpoint_name),
            &wrapper.expert_code,
        )
        .context("Failed to write expert wrapper")?;
    }

    println!(
        "Generated {} layered wrappers in '{}'",
        layers.len(),
        output_dir
    );
    Ok(())
}

/// Build the generated artifacts (placeholder for Phase 2 — My-Lang compilation).
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!(
        "Building mylangiser project: {} (compilation not yet implemented)",
        manifest.project.name
    );
    Ok(())
}

/// Run the generated workload (placeholder for Phase 2 — My-Lang execution).
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!(
        "Running mylangiser project: {} (execution not yet implemented)",
        manifest.project.name
    );
    Ok(())
}
