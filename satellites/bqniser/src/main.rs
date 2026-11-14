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
// bqniser CLI — Detect array computation patterns in code and rewrite
// as optimised BQN array primitives.
//
// BQN (by Marshall Lochbaum) is an array language descended from APL/J/K
// with first-class functions, trains, and structural-under combinators.
//
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// bqniser — Detect array patterns and rewrite as optimised BQN primitives.
#[derive(Parser)]
#[command(name = "bqniser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new bqniser.toml manifest in the current directory.
    Init {
        /// Directory to create the manifest in.
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a bqniser.toml manifest.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "bqniser.toml")]
        manifest: String,
    },
    /// Generate BQN programs, C headers, and Zig FFI bridge from the manifest.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "bqniser.toml")]
        manifest: String,
        /// Output directory for generated artifacts.
        #[arg(short, long, default_value = "generated/bqniser")]
        output: String,
    },
    /// Build the generated artifacts (requires CBQN).
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "bqniser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Run the bqniser workload (requires CBQN).
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "bqniser.toml")]
        manifest: String,
        /// Additional arguments passed to the BQN program.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest (project, patterns, backend).
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "bqniser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising bqniser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            let name = manifest::effective_name(&m);
            println!("Manifest valid: {}", name);
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated BQN artifacts in: {}", output);
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
