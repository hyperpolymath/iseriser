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
// wokelangiser CLI — Add consent patterns, accessibility compliance, and
// internationalisation to existing code via WokeLang.
//
// Commands:
//   init      — Create a new wokelangiser.toml manifest
//   validate  — Validate an existing manifest
//   generate  — Run the full codegen pipeline (consent gates, a11y report, i18n)
//   build     — Build the generated artifacts
//   run       — Run compliance analysis (report only, no file output)
//   info      — Print manifest configuration summary

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// wokelangiser — Add consent patterns, accessibility, and i18n to existing code via WokeLang.
#[derive(Parser)]
#[command(name = "wokelangiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new wokelangiser.toml manifest in the given directory.
    Init {
        /// Directory to create the manifest in (defaults to current directory).
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a wokelangiser.toml manifest for correctness and consistency.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "wokelangiser.toml")]
        manifest: String,
    },
    /// Generate consent gates, accessibility reports, and i18n locale files.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "wokelangiser.toml")]
        manifest: String,
        /// Output directory for generated files.
        #[arg(short, long, default_value = "generated/wokelangiser")]
        output: String,
    },
    /// Build the generated artifacts.
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "wokelangiser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Run compliance analysis (prints report without generating files).
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "wokelangiser.toml")]
        manifest: String,
        /// Additional arguments.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Print manifest configuration summary.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "wokelangiser.toml")]
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
