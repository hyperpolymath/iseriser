// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation engine for iseriser.
//
// Submodules:
//   - parser:     Validates language descriptions (semantic rules)
//   - scaffold:   Generates complete -iser repository structures
//   - customizer: Applies language-feature-specific modifications

pub mod customizer;
pub mod parser;
pub mod scaffold;

use anyhow::Result;
use std::path::Path;

use crate::abi::ScaffoldResult;
use crate::manifest::Manifest;

/// Validate, scaffold, and write a complete -iser repository.
///
/// This is the main entry point for the generation pipeline:
///   1. Deep-validate the language description (parser)
///   2. Generate the full file set (scaffold)
///   3. Apply language-specific customizations (customizer — called by scaffold)
///   4. Write everything to disk (scaffold)
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<ScaffoldResult> {
    // Step 1: Deep validation
    let report = parser::validate_or_bail(manifest)?;

    // Print warnings (non-fatal)
    for warning in &report.warnings {
        eprintln!("warning: {}", warning);
    }

    // Step 2 + 3 + 4: Scaffold (includes customization and disk write)
    let result = scaffold::scaffold_repo(manifest, Path::new(output_dir));

    match &result {
        ScaffoldResult::Success(repo) => {
            println!(
                "Generated {} ({} files) at {}",
                repo.name,
                repo.file_count(),
                repo.root.display()
            );
        }
        _ => {
            if let Some(msg) = result.error_message() {
                eprintln!("error: {}", msg);
            }
        }
    }

    Ok(result)
}
