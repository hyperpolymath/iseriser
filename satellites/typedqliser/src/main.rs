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
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// TypedQLiser — formal type safety for any query language.
// #1 priority in the -iser family.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;
mod plugins;

/// TypedQLiser — add formal type safety to any query language.
#[derive(Parser)]
#[command(name = "typedqliser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialise a typedqliser.toml manifest.
    Init {
        #[arg(short, long, default_value = "sql")]
        language: String,
        #[arg(short, long, default_value = "postgresql")]
        database: String,
    },
    /// Type-check all queries in the project.
    Check {
        #[arg(short, long, default_value = "typedqliser.toml")]
        manifest: String,
        /// Single query to check (instead of scanning files).
        #[arg(short, long)]
        query: Option<String>,
        /// Generate proof certificates alongside queries.
        #[arg(long)]
        proofs: bool,
        /// CI mode: exit code 1 on type errors.
        #[arg(long)]
        ci: bool,
    },
    /// Show what type safety level each query achieves.
    Info {
        #[arg(short, long, default_value = "typedqliser.toml")]
        manifest: String,
    },
    /// List supported query languages and their max type safety levels.
    Languages,
    /// Explain the 10 type safety levels.
    Levels,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { language, database } => {
            manifest::init_manifest(&language, &database)?;
        }
        Commands::Check {
            manifest,
            query,
            proofs,
            ci,
        } => {
            let m = manifest::load_manifest(&manifest)?;
            let results = codegen::check_queries(&m, query.as_deref(), proofs)?;
            codegen::report_results(&results, &m, ci)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
        Commands::Languages => plugins::print_languages(),
        Commands::Levels => print_levels(),
    }
    Ok(())
}

/// Print the 10 type safety levels with explanations.
fn print_levels() {
    println!("=== TypedQLiser: 10 Type Safety Levels ===");
    println!();
    println!("  ESTABLISHED (enforced by default):");
    println!("    1  Parse-time safety       Query is syntactically valid");
    println!("    2  Schema-binding safety   All tables/fields/types exist in schema");
    println!("    3  Type-compatible ops     No comparing strings to integers");
    println!("    4  Null-safety             Every nullable path explicitly handled");
    println!("    5  Injection-proof safety  No user input can alter query structure");
    println!("    6  Result-type safety      Return type known at compile time");
    println!();
    println!("  RESEARCH (opt-in, experimental):");
    println!("    7  Cardinality safety      Row count provably bounded");
    println!("    8  Effect-tracking safety  Side-effects of every query declared");
    println!("    9  Temporal safety         Time-dependent predicates verified");
    println!("   10  Linearity safety        Resources consumed exactly once");
}
