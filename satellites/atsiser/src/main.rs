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
// atsiser CLI — Wrap C codebases in ATS2 linear types for zero-cost memory safety.
//
// atsiser analyses C code to identify memory patterns (malloc/free, buffer accesses,
// pointer arithmetic), generates ATS2 wrappers with linear type annotations
// (viewtypes, dataviewtypes), proves memory safety at compile time, and compiles
// back to C via ATS2's C backend with zero runtime overhead.
//
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// atsiser — Wrap C codebases in ATS2 linear types for zero-cost memory safety.
///
/// Analyses C code, generates ATS2 viewtype wrappers, proves memory safety at
/// compile time, and compiles back to C with zero runtime overhead.
#[derive(Parser)]
#[command(name = "atsiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands for the atsiser CLI.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new atsiser.toml manifest in the given directory.
    Init {
        /// Directory in which to create the manifest.
        #[arg(short, long, default_value = ".")]
        path: String,
    },

    /// Validate an atsiser.toml manifest for correctness.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "atsiser.toml")]
        manifest: String,
    },

    /// Generate ATS2 viewtype wrappers from the manifest.
    ///
    /// Parses C headers, applies ownership rules, and produces .sats/.dats files
    /// with linear type annotations that prove memory safety.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "atsiser.toml")]
        manifest: String,

        /// Output directory for generated ATS2 files.
        #[arg(short, long)]
        output: Option<String>,
    },

    /// Build the generated ATS2 artifacts into a C library.
    ///
    /// Invokes patsopt for type-checking and patscc for C compilation.
    /// Type-check failures indicate memory safety violations in the original C code.
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "atsiser.toml")]
        manifest: String,

        /// Enable release-mode optimisations.
        #[arg(long)]
        release: bool,
    },

    /// Run the compiled workload binary.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "atsiser.toml")]
        manifest: String,

        /// Arguments passed to the compiled binary.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },

    /// Show information about a manifest.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "atsiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising atsiser manifest in: {}", path);
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
            let output_dir = output.unwrap_or_else(|| m.project.output_dir.clone());
            codegen::generate_all(&m, &output_dir)?;
            println!("Generated ATS2 artifacts in: {}", output_dir);
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
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
