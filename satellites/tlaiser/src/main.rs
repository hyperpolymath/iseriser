#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// tlaiser CLI — Extract state machines from code and model-check with TLA+/PlusCal.
// Part of the hyperpolymath -iser family. See README.adoc for architecture.
//
// TLA+ (Leslie Lamport) is the gold standard for specifying and verifying
// concurrent/distributed systems. The TLC model checker exhaustively explores
// all reachable states. tlaiser generates TLA+ specs, PlusCal algorithms,
// and TLC configurations from declarative manifest definitions.

use anyhow::Result;
use clap::{Parser, Subcommand};

use tlaiser::codegen;
use tlaiser::manifest;

/// tlaiser — Model-check state machines via TLA+/PlusCal
#[derive(Parser)]
#[command(name = "tlaiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands for the tlaiser CLI.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new tlaiser.toml manifest in the current directory.
    Init {
        /// Directory path in which to create the manifest.
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a tlaiser.toml manifest for correctness.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "tlaiser.toml")]
        manifest: String,
    },
    /// Generate TLA+ specs, PlusCal algorithms, and TLC config from the manifest.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "tlaiser.toml")]
        manifest: String,
        /// Output directory for generated artifacts.
        #[arg(short, long, default_value = "generated/tlaiser")]
        output: String,
    },
    /// Build generated artifacts (invoke TLC model checker).
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "tlaiser.toml")]
        manifest: String,
        /// Use release/optimised settings.
        #[arg(long)]
        release: bool,
    },
    /// Run the TLC model checker on generated specifications.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "tlaiser.toml")]
        manifest: String,
        /// Additional arguments passed to TLC.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest (state machines, properties, config).
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "tlaiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising tlaiser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!(
                "Manifest valid: {} ({} state machines, {} properties)",
                m.project.name,
                m.state_machines.len(),
                m.properties.len()
            );
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated TLA+ artifacts in: {}", output);
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
