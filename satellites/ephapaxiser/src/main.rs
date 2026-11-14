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
// ephapaxiser CLI — Enforce single-use linear type semantics on resources via Ephapax.
//
// Commands:
//   init      — Create a new ephapaxiser.toml manifest in the current directory
//   validate  — Check an ephapaxiser.toml for correctness
//   analyse   — Parse sources and detect linear type violations
//   generate  — Generate Ephapax linear type wrappers and analysis report
//   build     — Build the generated artefacts (Phase 2)
//   run       — Run analysis as a standalone pass (Phase 2)
//   info      — Print manifest summary

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// ephapaxiser — Enforce single-use linear type semantics on resources via Ephapax
/// (ephapax = "once for all" in Greek)
#[derive(Parser)]
#[command(name = "ephapaxiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new ephapaxiser.toml manifest.
    Init {
        /// Directory to create the manifest in.
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate an ephapaxiser.toml manifest.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "ephapaxiser.toml")]
        manifest: String,
    },
    /// Analyse source files for linear type violations.
    Analyse {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "ephapaxiser.toml")]
        manifest: String,
    },
    /// Generate Ephapax linear type wrappers and analysis report.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "ephapaxiser.toml")]
        manifest: String,
        /// Output directory for generated files.
        #[arg(short, long, default_value = "generated/ephapaxiser")]
        output: String,
    },
    /// Build the generated artefacts.
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "ephapaxiser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Run the analysis.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "ephapaxiser.toml")]
        manifest: String,
        /// Additional arguments.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "ephapaxiser.toml")]
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
            println!("Valid: {}", m.project.name);
        }
        Commands::Analyse { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            let result = codegen::analyse_manifest(&m, ".")?;
            if result.is_clean() {
                println!("No violations found in '{}'.", m.project.name);
            } else {
                println!("Violations in '{}':", m.project.name);
                for v in &result.violations {
                    println!("  {}", v);
                }
                std::process::exit(1);
            }
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
