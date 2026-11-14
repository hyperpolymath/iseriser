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
// phronesiser CLI — Add provably safe ethical constraints to AI agent
// decision-making via Phronesis. Encodes deontic logic (obligations,
// permissions, prohibitions) as formal propositions ensuring AI respects
// boundaries before acting.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// phronesiser — Add provably safe ethical constraints to AI agent decision-making via Phronesis
#[derive(Parser)]
#[command(name = "phronesiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new phronesiser.toml manifest with example constraints.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a phronesiser.toml manifest (checks deontic logic consistency).
    Validate {
        #[arg(short, long, default_value = "phronesiser.toml")]
        manifest: String,
    },
    /// Generate Phronesis constraint engine artifacts.
    Generate {
        #[arg(short, long, default_value = "phronesiser.toml")]
        manifest: String,
        #[arg(short, long, default_value = "generated/phronesiser")]
        output: String,
    },
    /// Build the generated constraint engine (validation pass).
    Build {
        #[arg(short, long, default_value = "phronesiser.toml")]
        manifest: String,
        #[arg(long)]
        release: bool,
    },
    /// Run the constraint engine with a self-test against agent capabilities.
    Run {
        #[arg(short, long, default_value = "phronesiser.toml")]
        manifest: String,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information including all constraints and enforcement policy.
    Info {
        #[arg(short, long, default_value = "phronesiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            let name = if m.project.name.is_empty() {
                &m.workload.name
            } else {
                &m.project.name
            };
            println!("Valid: {} ({} constraints)", name, m.constraints.len());
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::build(&m, release)?;
        }
        Commands::Run { manifest, args } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::run(&m, &args)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
