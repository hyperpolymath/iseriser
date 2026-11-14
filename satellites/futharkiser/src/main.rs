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
// futharkiser CLI — compile annotated array operations to GPU kernels via Futhark.
//
// Futhark (Troels Henriksen, DIKU Copenhagen) is a purely functional array
// language that compiles to OpenCL/CUDA with guaranteed data-race freedom.
// futharkiser takes kernel descriptions from a TOML manifest and generates
// idiomatic Futhark programs using SOACs (second-order array combinators),
// then compiles them to the selected GPU backend.
//
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// futharkiser — compile array operations to GPU kernels via Futhark.
#[derive(Parser)]
#[command(name = "futharkiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new futharkiser.toml manifest in the current directory.
    Init {
        /// Directory to create the manifest in.
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a futharkiser.toml manifest.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "futharkiser.toml")]
        manifest: String,
    },
    /// Generate Futhark source, C-ABI header, and build script from the manifest.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "futharkiser.toml")]
        manifest: String,
        /// Output directory for generated artifacts.
        #[arg(short, long, default_value = "generated/futharkiser")]
        output: String,
    },
    /// Build the generated Futhark artifacts (requires futhark in PATH).
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "futharkiser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Run the compiled Futhark program.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "futharkiser.toml")]
        manifest: String,
        /// Additional arguments passed to the Futhark program.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "futharkiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising futharkiser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!(
                "Manifest valid: {} ({} kernels)",
                m.project.name,
                m.kernels.len()
            );
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated Futhark artifacts in: {}", output);
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
