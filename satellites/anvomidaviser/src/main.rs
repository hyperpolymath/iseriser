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
// anvomidaviser CLI — Convert ISU figure skating notation to formal
// Anvomidav program descriptions. Parses ISU element codes (jumps, spins,
// steps), validates against ISU technical rules, calculates base values,
// and generates formal program descriptions.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// anvomidaviser — Convert ISU notation to formal figure skating programs via Anvomidav
#[derive(Parser)]
#[command(name = "anvomidaviser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new anvomidaviser.toml manifest with example elements.
    Init {
        /// Directory path to create the manifest in
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a manifest against ISU technical rules.
    Validate {
        /// Path to the anvomidaviser.toml manifest file
        #[arg(short, long, default_value = "anvomidaviser.toml")]
        manifest: String,
    },
    /// Generate formal Anvomidav program description from ISU notation.
    Generate {
        /// Path to the anvomidaviser.toml manifest file
        #[arg(short, long, default_value = "anvomidaviser.toml")]
        manifest: String,
        /// Output directory for generated artifacts
        #[arg(short, long, default_value = "generated/anvomidaviser")]
        output: String,
    },
    /// Build the generated artifacts.
    Build {
        /// Path to the anvomidaviser.toml manifest file
        #[arg(short, long, default_value = "anvomidaviser.toml")]
        manifest: String,
        /// Build in release mode
        #[arg(long)]
        release: bool,
    },
    /// Run the program analysis.
    Run {
        /// Path to the anvomidaviser.toml manifest file
        #[arg(short, long, default_value = "anvomidaviser.toml")]
        manifest: String,
        /// Additional arguments
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show manifest information and element summary.
    Info {
        /// Path to the anvomidaviser.toml manifest file
        #[arg(short, long, default_value = "anvomidaviser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest: path } => {
            let m = manifest::load_manifest(&path)?;
            manifest::validate(&m)?;
            // Also run ISU rule validation
            let codes: Vec<String> = m.elements.iter().map(|e| e.code.clone()).collect();
            let elements = codegen::parser::parse_program(&codes)?;
            let violations = codegen::validator::validate_program(&elements, m.program.segment);
            if violations.is_empty() {
                println!("Valid: {} — no ISU rule violations", m.project.name);
            } else {
                println!(
                    "Program '{}' has {} violation(s):",
                    m.project.name,
                    violations.len()
                );
                for v in &violations {
                    println!("  - {}", v);
                }
            }
        }
        Commands::Generate {
            manifest: path,
            output,
        } => {
            let m = manifest::load_manifest(&path)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
        }
        Commands::Build {
            manifest: path,
            release,
        } => {
            let m = manifest::load_manifest(&path)?;
            codegen::build(&m, release)?;
        }
        Commands::Run {
            manifest: path,
            args,
        } => {
            let m = manifest::load_manifest(&path)?;
            codegen::run(&m, &args)?;
        }
        Commands::Info { manifest: path } => {
            let m = manifest::load_manifest(&path)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
