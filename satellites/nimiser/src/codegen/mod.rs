// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation orchestrator for nimiser.
// Coordinates parser, nim_gen, and build_gen to produce:
//   - <name>.nim        Nim library source with proc declarations
//   - nim.cfg           Nim compiler configuration
//   - build.sh          Build script for compilation

pub mod build_gen;
pub mod nim_gen;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts from a manifest.
/// Creates the output directory and writes the .nim source, nim.cfg, and build.sh.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Step 1: Parse function signatures from manifest into NimProc ABI types.
    let procs = parser::parse_functions(manifest)
        .context("Failed to parse function declarations from manifest")?;

    // Step 2: Generate the Nim library source file.
    let nim_source = nim_gen::generate_nim_source(manifest, &procs);
    let lib_name = manifest.project.name.replace('-', "_");
    let nim_file = out.join(format!("{}.nim", lib_name));
    fs::write(&nim_file, &nim_source)
        .with_context(|| format!("Failed to write {}", nim_file.display()))?;
    println!("  [nim]  {}", nim_file.display());

    // Step 3: Generate the nim.cfg configuration file.
    let cfg_content = build_gen::generate_nim_cfg(manifest);
    let cfg_file = out.join("nim.cfg");
    fs::write(&cfg_file, &cfg_content)
        .with_context(|| format!("Failed to write {}", cfg_file.display()))?;
    println!("  [cfg]  {}", cfg_file.display());

    // Step 4: Generate the build.sh script.
    let build_script = build_gen::generate_build_script(manifest, &format!("{}.nim", lib_name));
    let build_file = out.join("build.sh");
    fs::write(&build_file, &build_script)
        .with_context(|| format!("Failed to write {}", build_file.display()))?;
    // Make build.sh executable on Unix.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let perms = std::fs::Permissions::from_mode(0o755);
        fs::set_permissions(&build_file, perms)
            .with_context(|| format!("Failed to set permissions on {}", build_file.display()))?;
    }
    println!("  [sh]   {}", build_file.display());

    Ok(())
}

/// Build generated artifacts by invoking the Nim compiler.
pub fn build(manifest: &Manifest, release: bool) -> Result<()> {
    let lib_name = manifest.project.name.replace('-', "_");
    let source_file = format!("{}/{}.nim", manifest.nim.out_dir, lib_name);

    if !Path::new(&source_file).exists() {
        anyhow::bail!(
            "Generated source '{}' not found. Run `nimiser generate` first.",
            source_file
        );
    }

    let cmd = build_gen::build_command_from_manifest(manifest, &source_file, release);
    let command_str = cmd.render();

    println!("Building {} with Nim...", manifest.project.name);
    println!("  {}", command_str);

    let status = std::process::Command::new("nim")
        .arg(&cmd.backend)
        .arg(&cmd.gc_flag)
        .args(if !cmd.opt_flag.is_empty() {
            vec![cmd.opt_flag.as_str()]
        } else {
            vec![]
        })
        .arg(&cmd.opt_level_flag)
        .args(if cmd.as_library {
            vec!["--app:lib", "--noMain"]
        } else {
            vec![]
        })
        .args(&cmd.extra_flags)
        .arg(format!("-o:{}", cmd.output_name))
        .arg(&cmd.source_file)
        .status()
        .context("Failed to invoke Nim compiler. Is `nim` installed?")?;

    if !status.success() {
        anyhow::bail!("Nim compilation failed with exit code: {:?}", status.code());
    }

    println!("Built: {}", cmd.output_name);
    Ok(())
}

/// Run the compiled workload binary.
pub fn run(manifest: &Manifest, args: &[String]) -> Result<()> {
    let lib_name = manifest.project.name.replace('-', "_");
    let binary = format!("lib{}.so", lib_name);

    if !Path::new(&binary).exists() {
        anyhow::bail!(
            "Compiled library '{}' not found. Run `nimiser build` first.",
            binary
        );
    }

    println!("Running nimiser workload: {}", manifest.project.name);
    let status = std::process::Command::new(format!("./{}", binary))
        .args(args)
        .status()
        .with_context(|| format!("Failed to run {}", binary))?;

    if !status.success() {
        anyhow::bail!("Workload exited with code: {:?}", status.code());
    }

    Ok(())
}
