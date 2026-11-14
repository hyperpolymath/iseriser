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
// mylangiser CLI — Generate progressive-disclosure interfaces from complex APIs
// via My-Lang. Analyses API complexity, scores endpoints, assigns disclosure
// levels (beginner/intermediate/expert), and generates layered wrapper code
// with smart defaults for omitted parameters.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// mylangiser — Generate progressive-disclosure interfaces from complex APIs via My-Lang
#[derive(Parser)]
#[command(name = "mylangiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available CLI subcommands for mylangiser.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new mylangiser.toml manifest with example endpoints.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a mylangiser.toml manifest for structural correctness.
    Validate {
        #[arg(short, long, default_value = "mylangiser.toml")]
        manifest: String,
    },
    /// Score endpoint complexity and generate layered wrapper code.
    Generate {
        #[arg(short, long, default_value = "mylangiser.toml")]
        manifest: String,
        #[arg(short, long, default_value = "generated/mylangiser")]
        output: String,
    },
    /// Build the generated artifacts (placeholder for Phase 2).
    Build {
        #[arg(short, long, default_value = "mylangiser.toml")]
        manifest: String,
        #[arg(long)]
        release: bool,
    },
    /// Run the generated workload (placeholder for Phase 2).
    Run {
        #[arg(short, long, default_value = "mylangiser.toml")]
        manifest: String,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information including endpoint scores and levels.
    Info {
        #[arg(short, long, default_value = "mylangiser.toml")]
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
