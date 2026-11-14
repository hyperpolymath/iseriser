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
// eclexiaiser CLI — Add energy, carbon, and resource-cost awareness to existing
// software via Eclexia economics-as-code.
//
// Commands:
//   init       — Scaffold a new eclexiaiser.toml manifest
//   validate   — Check a manifest for correctness
//   generate   — Produce instrumentation code, constraints, and reports
//   report     — Generate a sustainability report from simulated measurements
//   build      — Build generated artifacts (Phase 2)
//   run        — Run instrumented workload (Phase 2)
//   info       — Display manifest summary

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// eclexiaiser — Add energy, carbon, and resource-cost awareness to existing
/// software via Eclexia economics-as-code.
#[derive(Parser)]
#[command(name = "eclexiaiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a new eclexiaiser.toml manifest with template budgets.
    Init {
        /// Directory to create the manifest in.
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate an eclexiaiser.toml manifest for correctness.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "eclexiaiser.toml")]
        manifest: String,
    },
    /// Generate instrumentation code, Eclexia constraints, and sustainability report.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "eclexiaiser.toml")]
        manifest: String,
        /// Output directory for generated artifacts.
        #[arg(short, long, default_value = "generated/eclexiaiser")]
        output: String,
    },
    /// Generate a sustainability report from simulated measurements.
    Report {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "eclexiaiser.toml")]
        manifest: String,
        /// Simulated usage fraction (0.0 = no usage, 1.0 = at budget, 1.5 = 50% over).
        #[arg(short, long, default_value = "0.75")]
        usage: f64,
        /// Output path base for the report file (extension added automatically).
        #[arg(short, long, default_value = "sustainability_report")]
        output: String,
    },
    /// Build the generated eclexiaiser artifacts (Phase 2).
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "eclexiaiser.toml")]
        manifest: String,
        /// Build in release mode.
        #[arg(long)]
        release: bool,
    },
    /// Run the instrumented workload (Phase 2).
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "eclexiaiser.toml")]
        manifest: String,
        /// Additional arguments passed to the workload.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Display a human-readable summary of the manifest.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "eclexiaiser.toml")]
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
                "Valid: {} ({} function(s))",
                m.project.name,
                m.functions.len()
            );
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
        }
        Commands::Report {
            manifest,
            usage,
            output,
        } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            let report = codegen::generate_report_from_simulated(&m, usage)?;
            codegen::reporter::write_report(&report, &m.report, &output)?;
            println!(
                "Report generated: {}.* (compliance: {})",
                output,
                if report.all_compliant { "PASS" } else { "FAIL" }
            );
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
