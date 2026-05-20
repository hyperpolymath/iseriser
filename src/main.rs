#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push
)]
#![forbid(unsafe_code)]
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// iseriser CLI — Meta-framework: generate new -iser projects from
// language descriptions.
// Part of the hyperpolymath -iser family.  See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;
mod scan;

/// iseriser — Meta-framework: generate new -iser projects
#[derive(Parser)]
#[command(name = "iseriser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new iseriser.toml manifest in the current directory.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate an iseriser.toml manifest (structural + semantic).
    Validate {
        #[arg(short, long, default_value = "iseriser.toml")]
        manifest: String,
    },
    /// Generate a complete -iser repository from the manifest.
    Generate {
        #[arg(short, long, default_value = "iseriser.toml")]
        manifest: String,
        #[arg(short, long, default_value = ".")]
        output: String,
    },
    /// Show information about a manifest.
    Info {
        #[arg(short, long, default_value = "iseriser.toml")]
        manifest: String,
    },
    /// Scan a repository and recommend applicable -iser tools.
    Scan {
        /// Path to the repository to scan (default: current directory).
        #[arg(short, long, default_value = ".")]
        path: String,
        /// Output recommendations as JSON instead of a table.
        #[arg(long, default_value_t = false)]
        json: bool,
    },
    /// Verify a cartridge's Zig FFI against its Idris2-derived ABI manifest.
    /// Phase 1 of standards#92: structural CI gate, not codegen.
    AbiVerify {
        /// Path to the ABI manifest JSON.
        #[arg(long)]
        manifest: String,
        /// Path to the Zig FFI source file.
        #[arg(long)]
        zig_ffi: String,
        /// Emit the report as JSON on stdout instead of the human form.
        #[arg(long, default_value_t = false)]
        json: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising iseriser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            let report = codegen::parser::validate_or_bail(&m)?;
            println!("Manifest valid: {}", m.project.name);
            if !report.warnings.is_empty() {
                for w in &report.warnings {
                    eprintln!("warning: {}", w);
                }
            }
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
        Commands::Scan { path, json } => {
            let recommendations = scan::scan_repo(&path)?;
            if json {
                println!("{}", serde_json::to_string_pretty(&recommendations)?);
            } else {
                scan::print_table(&recommendations);
            }
        }
        Commands::AbiVerify { manifest, zig_ffi, json } => {
            let report = abi::verify::verify_paths(
                std::path::Path::new(&manifest),
                std::path::Path::new(&zig_ffi),
            )?;
            if json {
                println!("{}", serde_json::to_string_pretty(&report)?);
            } else {
                report.print();
            }
            if !report.is_clean() {
                std::process::exit(2);
            }
        }
    }
    Ok(())
}
