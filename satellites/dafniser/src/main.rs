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
// dafniser CLI — Generate correct-by-construction code via Dafny verification.
// Takes function specifications (pre/postconditions, invariants, decreases
// clauses) and generates Dafny code that the Z3-based verifier proves correct,
// then compiles to a target language (C#, Java, Go, Python, JS).
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// dafniser — Generate verified code via Dafny.
///
/// Reads function specifications from a dafniser.toml manifest and generates
/// Dafny source files with requires/ensures/decreases clauses. The Dafny
/// verifier (Z3 backend) automatically proves correctness. Verified code is
/// then compiled to the configured target language.
#[derive(Parser)]
#[command(name = "dafniser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new dafniser.toml manifest in the current directory.
    Init {
        /// Directory to create the manifest in (defaults to current directory).
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a dafniser.toml manifest for correctness.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "dafniser.toml")]
        manifest: String,
    },
    /// Generate Dafny .dfy files and build commands from the manifest.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "dafniser.toml")]
        manifest: String,
        /// Output directory for generated artifacts.
        #[arg(short, long, default_value = "generated/dafniser")]
        output: String,
    },
    /// Show build plan for the generated Dafny artifacts.
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "dafniser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Show run plan for the compiled workload.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "dafniser.toml")]
        manifest: String,
        /// Extra arguments passed to the compiled binary.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest (functions, targets, contracts).
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "dafniser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising dafniser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!("Manifest valid: {}", m.project.name);
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated Dafny artifacts in: {}", output);
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::build(&m, release)?;
        }
        Commands::Run { manifest, args } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::run(&m, &args)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
