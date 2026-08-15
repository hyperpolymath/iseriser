#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// a2mliser CLI — Add cryptographic attestation and verification to any markup or configuration via A2ML

use anyhow::Result;
use clap::{Parser, Subcommand};

mod codegen;
mod manifest;

/// a2mliser — Add cryptographic attestation and verification to any markup or configuration via A2ML
#[derive(Parser)]
#[command(name = "a2mliser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new a2mliser.toml manifest.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a a2mliser.toml manifest.
    Validate {
        #[arg(short, long, default_value = "a2mliser.toml")]
        manifest: String,
    },
    /// Generate A2ML wrapper, Zig FFI bridge, and C headers.
    Generate {
        #[arg(short, long, default_value = "a2mliser.toml")]
        manifest: String,
        #[arg(short, long, default_value = "generated/a2mliser")]
        output: String,
    },
    /// Build the generated artifacts.
    Build {
        #[arg(short, long, default_value = "a2mliser.toml")]
        manifest: String,
        #[arg(long)]
        release: bool,
    },
    /// Run the workload.
    Run {
        #[arg(short, long, default_value = "a2mliser.toml")]
        manifest: String,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information.
    Info {
        #[arg(short, long, default_value = "a2mliser.toml")]
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
            println!("Valid: {}", m.workload.name);
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
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
