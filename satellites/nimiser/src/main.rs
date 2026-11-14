#![forbid(unsafe_code)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// nimiser CLI — Generate performant C libraries via Nim metaprogramming.
// Part of the hyperpolymath -iser family. See README.adoc for architecture.
//
// Usage:
//   nimiser init [--path .]         Create a new nimiser.toml manifest
//   nimiser validate [-m file]      Validate a manifest
//   nimiser generate [-m file]      Generate .nim source and build commands
//   nimiser build [-m file]         Compile the generated Nim to C library
//   nimiser run [-m file]           Run the compiled binary
//   nimiser info [-m file]          Print manifest summary

use anyhow::Result;
use clap::{Parser, Subcommand};

use nimiser::codegen;
use nimiser::manifest;

/// nimiser — Generate performant C libraries via Nim metaprogramming
#[derive(Parser)]
#[command(name = "nimiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new nimiser.toml manifest in the current directory.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a nimiser.toml manifest.
    Validate {
        #[arg(short, long, default_value = "nimiser.toml")]
        manifest: String,
    },
    /// Generate Nim wrapper code and build commands from the manifest.
    Generate {
        #[arg(short, long, default_value = "nimiser.toml")]
        manifest: String,
        #[arg(short, long)]
        output: Option<String>,
    },
    /// Build the generated Nim library into a C library.
    Build {
        #[arg(short, long, default_value = "nimiser.toml")]
        manifest: String,
        #[arg(long)]
        release: bool,
    },
    /// Run the compiled workload.
    Run {
        #[arg(short, long, default_value = "nimiser.toml")]
        manifest: String,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest.
    Info {
        #[arg(short, long, default_value = "nimiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising nimiser manifest in: {}", path);
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
            let out_dir = output.unwrap_or_else(|| m.nim.out_dir.clone());
            codegen::generate_all(&m, &out_dir)?;
            println!("Generated Nim artifacts in: {}", out_dir);
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
