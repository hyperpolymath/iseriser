#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push
)]
#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// oblibeniser CLI — Make operations reversible and auditable via Oblíbený (Czech: "favourite").
//
// Every state-mutating operation gets an automatic inverse, enabling:
//   - Undo/redo with configurable stack depth
//   - Hash-chained audit trails for tamper-evident logging
//   - Time-travel debugging by navigating operation history
//
// Usage:
//   oblibeniser init [--path .]          Create a new oblibeniser.toml manifest
//   oblibeniser validate [--manifest ..]  Validate a manifest file
//   oblibeniser generate [--manifest ..] [--output ..] Generate reversible wrappers
//   oblibeniser build [--manifest ..]     Build-check generated artifacts
//   oblibeniser run [--manifest ..] [..]  Run the workload
//   oblibeniser info [--manifest ..]      Show manifest information

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// oblibeniser — Make operations reversible and auditable via Oblíbený.
/// Every mutation gets an inverse. Every action leaves a trail.
#[derive(Parser)]
#[command(name = "oblibeniser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available CLI subcommands for oblibeniser.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new oblibeniser.toml manifest in the target directory.
    Init {
        /// Directory to create the manifest in (defaults to current directory).
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate an oblibeniser.toml manifest for correctness.
    Validate {
        /// Path to the manifest file to validate.
        #[arg(short, long, default_value = "oblibeniser.toml")]
        manifest: String,
    },
    /// Generate Oblíbený inverse wrappers, audit trail module, and verification script.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "oblibeniser.toml")]
        manifest: String,
        /// Output directory for generated files.
        #[arg(short, long, default_value = "generated/oblibeniser")]
        output: String,
    },
    /// Build-check the generated artifacts against the manifest.
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "oblibeniser.toml")]
        manifest: String,
        /// Build in release mode (optimised).
        #[arg(long)]
        release: bool,
    },
    /// Run the reversible workload.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "oblibeniser.toml")]
        manifest: String,
        /// Additional arguments passed to the workload.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information and operation summary.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "oblibeniser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest: path } => {
            let m = manifest::load_manifest(&path)?;
            manifest::validate(&m)?;
            println!(
                "Valid: {} ({} operations)",
                m.project.name,
                m.operations.len()
            );
        }
        Commands::Generate {
            manifest: path,
            output,
        } => {
            let m = manifest::load_manifest(&path)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
        }
        Commands::Build {
            manifest: path,
            release,
        } => {
            let m = manifest::load_manifest(&path)?;
            manifest::validate(&m)?;
            codegen::build(&m, release)?;
        }
        Commands::Run {
            manifest: path,
            args,
        } => {
            let m = manifest::load_manifest(&path)?;
            manifest::validate(&m)?;
            codegen::run(&m, &args)?;
        }
        Commands::Info { manifest: path } => {
            let m = manifest::load_manifest(&path)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
