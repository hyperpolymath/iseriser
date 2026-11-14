#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push
)]
#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Chapeliser CLI — General-purpose Chapel acceleration framework.
// Distributes any workload across Chapel clusters without the user writing Chapel code.
// See README.adoc for architecture overview.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod codegen;
mod manifest;

/// Chapeliser — distribute any workload across Chapel clusters
/// without writing Chapel code.
#[derive(Parser)]
#[command(name = "chapeliser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands for the Chapeliser CLI.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new chapeliser.toml manifest in the current directory.
    /// Analyses the project structure and suggests workload configuration.
    Init {
        /// Path to the project root (default: current directory)
        #[arg(short, long, default_value = ".")]
        path: String,
    },

    /// Validate a chapeliser.toml manifest without generating anything.
    /// Checks that entry points exist, types are resolvable, and
    /// partition/gather strategies are compatible.
    Validate {
        /// Path to chapeliser.toml (default: ./chapeliser.toml)
        #[arg(short, long, default_value = "chapeliser.toml")]
        manifest: String,
    },

    /// Generate Chapel wrapper, Zig FFI bridge, and C headers from the manifest.
    /// Output goes to generated/ directory by default.
    Generate {
        /// Path to chapeliser.toml
        #[arg(short, long, default_value = "chapeliser.toml")]
        manifest: String,

        /// Output directory for generated files
        #[arg(short, long, default_value = "generated/chapeliser")]
        output: String,
    },

    /// Build the generated Chapel + FFI code.
    /// Requires Chapel compiler (`chpl`) on PATH.
    Build {
        /// Path to chapeliser.toml
        #[arg(short, long, default_value = "chapeliser.toml")]
        manifest: String,

        /// Build in release mode (optimisations enabled)
        #[arg(long)]
        release: bool,
    },

    /// Run the Chapelised workload.
    /// With no flags, runs locally (single locale).
    /// With -n, distributes across N Chapel locales.
    Run {
        /// Path to chapeliser.toml
        #[arg(short, long, default_value = "chapeliser.toml")]
        manifest: String,

        /// Number of Chapel locales (nodes) to use
        #[arg(short = 'n', long, default_value = "1")]
        locales: u32,

        /// Path to cluster configuration file
        #[arg(long)]
        cluster: Option<String>,

        /// Additional arguments passed through to the workload
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },

    /// Show information about a chapeliser.toml manifest:
    /// detected workload characteristics, estimated parallelism,
    /// and recommended scaling parameters.
    Info {
        /// Path to chapeliser.toml
        #[arg(short, long, default_value = "chapeliser.toml")]
        manifest: String,
    },

    /// List available partition and gather strategies with descriptions.
    Strategies,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init { path } => {
            println!("Initialising chapeliser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!(
                "Manifest valid: workload '{}', partition={}, gather={}",
                m.workload.name, m.workload.partition, m.workload.gather
            );
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!(
                "Generated Chapel wrapper, Zig FFI bridge, and C headers in: {}",
                output
            );
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::build(&m, release)?;
        }
        Commands::Run {
            manifest,
            locales,
            cluster,
            args,
        } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::run(&m, locales, cluster.as_deref(), &args)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
        Commands::Strategies => {
            manifest::print_strategies();
        }
    }

    Ok(())
}
