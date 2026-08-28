// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation engine for iseriser.
//
// Submodules:
//   - parser:     Validates language descriptions (semantic rules)
//   - scaffold:   Generates complete -iser repository structures
//   - cartridge:  Generates boj-server cartridge skeletons (standards#89 Phase 2b)
//   - customizer: Applies language-feature-specific modifications

pub mod cartridge;
pub mod customizer;
pub mod parser;
pub mod scaffold;

use anyhow::Result;
use std::path::Path;

use crate::abi::ScaffoldResult;
use crate::manifest::Manifest;

/// Validate, scaffold, and write a complete -iser repository *and* its
/// boj-server cartridge.
///
/// This is the main entry point for the generation pipeline:
///   1. Deep-validate the language description (parser)
///   2. Generate the full file set (scaffold)
///   3. Apply language-specific customizations (customizer — called by scaffold)
///   4. Write everything to disk (scaffold)
///   5. Scaffold the `<iser>-mcp` cartridge alongside it (cartridge)
///
/// Step 5 is what makes the unified transaction-gated adapter and its SSE
/// surface arrive *by construction* for every new -iser, which is what
/// hyperpolymath/standards#90 asks for.  The cartridge is written as a
/// **sibling** of the repo, at `<output_dir>/<iser>-mcp/`, never inside it:
/// the adapter belongs in the `hyperpolymath/boj-server-cartridges` registry,
/// and emitting it into the -iser repo produced a non-building stub that
/// PR #23 had to revert.
///
/// Use [`generate_repo_only`] when the cartridge is not wanted.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<ScaffoldResult> {
    let result = generate_repo_only(manifest, output_dir)?;

    // Only pair a cartridge with a repo that was actually written. The
    // manifest is already validated above, so scaffold directly rather than
    // going through `generate_cartridge` and re-emitting the same warnings.
    if result.is_success() {
        let cartridge = cartridge::scaffold_cartridge(manifest, Path::new(output_dir));
        match &cartridge {
            cartridge::CartridgeScaffoldResult::Success(c) => println!(
                "Generated cartridge {} ({} files) at {}",
                c.name,
                c.file_count(),
                c.root.display()
            ),
            _ => anyhow::bail!(
                "cartridge scaffolding failed: {}",
                cartridge.error_message().unwrap_or("unknown error")
            ),
        }
        println!(
            "Cartridge home: the hyperpolymath/boj-server-cartridges registry, \
             at cartridges/domains/<domain>/ — pick the domain directory and set \
             cartridge.json's \"domain\" field to match."
        );
    }

    Ok(result)
}

/// Validate, scaffold, and write the -iser repository only, without its
/// boj-server cartridge.
pub fn generate_repo_only(manifest: &Manifest, output_dir: &str) -> Result<ScaffoldResult> {
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

/// Validate the manifest then scaffold a boj-server cartridge skeleton.
///
/// Output goes to `<output_dir>/<iser_name>-mcp/`.  Meant to be placed
/// in the `hyperpolymath/boj-server-cartridges` registry, at
/// `cartridges/domains/<domain>/`; the cartridge vendors the ADR-0006
/// invoke-shim at `ffi/cartridge_shim.zig` and so builds wherever it sits.
///
/// See `cartridge` module docs and standards#89 Phase 2b for context.
pub fn generate_cartridge(
    manifest: &Manifest,
    output_dir: &str,
) -> Result<cartridge::CartridgeScaffoldResult> {
    let report = parser::validate_or_bail(manifest)?;
    for warning in &report.warnings {
        eprintln!("warning: {}", warning);
    }

    let result = cartridge::scaffold_cartridge(manifest, Path::new(output_dir));

    match &result {
        cartridge::CartridgeScaffoldResult::Success(repo) => {
            println!(
                "Generated cartridge {} ({} files) at {}",
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
