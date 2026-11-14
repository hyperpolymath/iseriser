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
// halideiser CLI — Compile image/video processing pipelines to optimised
// Halide schedules. Part of the hyperpolymath -iser family.
//
// Subcommands:
//   init      — create a new halideiser.toml template
//   validate  — check a manifest for errors
//   generate  — emit Halide C++ generator, runner, and CMakeLists.txt
//   build     — invoke CMake to compile the generated pipeline
//   run       — execute the compiled pipeline binary
//   info      — print a summary of the manifest

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// halideiser — Compile image/video pipelines to optimised Halide schedules.
#[derive(Parser)]
#[command(name = "halideiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new halideiser.toml manifest in the given directory.
    Init {
        /// Directory to create the manifest in (default: current directory).
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a halideiser.toml manifest for correctness.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "halideiser.toml")]
        manifest: String,
    },
    /// Generate Halide C++ algorithm, schedule, and CMake build files.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "halideiser.toml")]
        manifest: String,
        /// Output directory for generated files.
        #[arg(short, long, default_value = "generated/halideiser")]
        output: String,
    },
    /// Build the generated Halide pipeline using CMake.
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "halideiser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Run the compiled pipeline binary.
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "halideiser.toml")]
        manifest: String,
        /// Run the release configuration (matches build --release).
        #[arg(long)]
        release: bool,
        /// Additional arguments passed to the pipeline binary.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Print a summary of the manifest.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "halideiser.toml")]
        manifest: String,
    },
}

/// Runs the `halideiser` command-line interface and dispatches the selected subcommand.
///
/// # Examples
///
/// ```
/// let command = "halideiser info --manifest halideiser.toml";
/// assert!(command.starts_with("halideiser "));
/// ```
///
/// # Errors
///
/// Returns an error if the selected subcommand cannot complete successfully.
fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising halideiser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!(
                "Manifest valid: {} ({} stages)",
                m.project.name,
                m.stages.len()
            );
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated Halide artifacts in: {}", output);
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::build(&m, release)?;
        }
        Commands::Run {
            manifest,
            release,
            args,
        } => {
            let m = manifest::load_manifest(&manifest)?;
            if release {
                codegen::run_configuration(&m, true, &args)?;
            } else {
                codegen::run(&m, &args)?;
            }
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
