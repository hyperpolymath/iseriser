#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push,
    clippy::upper_case_acronyms,
    clippy::format_in_format_args,
    clippy::enum_variant_names,
    clippy::module_inception,
    clippy::doc_lazy_continuation,
    clippy::manual_clamp,
    clippy::type_complexity
)]
#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// betlangiser CLI — Add ternary probabilistic uncertainty modelling
// to deterministic code via Betlang.
//
// This tool reads a betlangiser.toml manifest that declares probabilistic
// variables (with distributions like Normal, Uniform, Beta, Bernoulli),
// simulation parameters, and generates Betlang source code that wraps
// deterministic values in probability distributions with ternary logic
// (true/false/unknown) via Kleene algebra.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// betlangiser — Add ternary probabilistic uncertainty modelling to deterministic code via Betlang
#[derive(Parser)]
#[command(name = "betlangiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new betlangiser.toml manifest with example variables.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a betlangiser.toml manifest for correctness.
    Validate {
        #[arg(short, long, default_value = "betlangiser.toml")]
        manifest: String,
    },
    /// Generate Betlang code with distribution declarations and ternary logic.
    Generate {
        #[arg(short, long, default_value = "betlangiser.toml")]
        manifest: String,
        #[arg(short, long, default_value = "generated/betlangiser")]
        output: String,
    },
    /// Build the generated Betlang artefacts.
    Build {
        #[arg(short, long, default_value = "betlangiser.toml")]
        manifest: String,
        #[arg(long)]
        release: bool,
    },
    /// Run the Monte Carlo simulation.
    Run {
        #[arg(short, long, default_value = "betlangiser.toml")]
        manifest: String,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information (variables, distributions, simulation config).
    Info {
        #[arg(short, long, default_value = "betlangiser.toml")]
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
            println!(
                "Valid: {} ({} variables, {} samples)",
                m.project.name,
                m.variables.len(),
                m.simulation.samples
            );
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
