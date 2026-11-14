// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Query language plugin system.
// Each supported query language implements the QueryLanguagePlugin trait.

pub mod sql;
pub mod wasm;

use anyhow::Result;
use serde::{Deserialize, Serialize};

/// A query extracted from a source file, with its location.
#[derive(Debug, Clone)]
pub struct LocatedQuery {
    /// The query text.
    pub query: String,
    /// Source file path.
    pub file: String,
    /// Line number in the source file (1-indexed).
    pub line: usize,
}

/// Database schema: tables, columns, types.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Schema {
    pub tables: Vec<TableDef>,
}

/// A table definition with columns.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TableDef {
    pub name: String,
    pub columns: Vec<ColumnDef>,
}

/// A column definition with name, type, and nullability.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColumnDef {
    pub name: String,
    #[serde(rename = "type")]
    pub col_type: String,
    #[serde(default)]
    pub nullable: bool,
    #[serde(default)]
    pub primary_key: bool,
}

/// Trait that all query language plugins implement.
pub trait QueryLanguagePlugin: Send + Sync {
    /// Plugin name (e.g., "sql", "graphql").
    fn name(&self) -> &str;

    /// Parse a query string. Returns Ok(()) if syntactically valid (Level 1).
    fn parse_check(&self, query: &str) -> Result<()>;

    /// Check that all referenced tables/columns exist in the schema (Level 2).
    fn schema_check(&self, query: &str, schema: &Schema) -> Result<Vec<SchemaIssue>>;

    /// Check type compatibility of operations (Level 3).
    fn type_check(&self, query: &str, schema: &Schema) -> Result<Vec<TypeIssue>>;

    /// Check null safety — all nullable paths handled (Level 4).
    fn null_check(&self, query: &str, schema: &Schema) -> Result<Vec<NullIssue>>;
}

/// A schema binding issue (Level 2 failure).
#[derive(Debug, Clone)]
pub struct SchemaIssue {
    pub message: String,
}

/// A type compatibility issue (Level 3 failure).
#[derive(Debug, Clone)]
pub struct TypeIssue {
    pub message: String,
}

/// A null safety issue (Level 4 failure).
#[derive(Debug, Clone)]
pub struct NullIssue {
    pub message: String,
    pub column: String,
}

/// Get the plugin for a given language name.
pub fn get_plugin(language: &str) -> Result<Box<dyn QueryLanguagePlugin>> {
    match language {
        "sql" | "postgresql" | "mysql" | "sqlite" => Ok(Box::new(sql::SqlPlugin::new(language))),
        "wasm" | "twasm" | "typed-wasm" => Ok(Box::new(wasm::WasmPlugin::new())),
        _ => anyhow::bail!(
            "Unsupported language: {}. Run `typedqliser languages` to see options.",
            language
        ),
    }
}

/// Print supported query languages.
pub fn print_languages() {
    println!("=== Supported Query Languages ===");
    println!();
    println!(
        "  {:12} {:40} {:10} Status",
        "Language", "Databases", "Max Level"
    );
    println!(
        "  {:12} {:40} {:10} ------",
        "--------", "---------", "---------"
    );
    println!(
        "  {:12} {:40} {:10} Active (MVP)",
        "sql", "PostgreSQL, MySQL, SQLite, MSSQL", "6"
    );
    println!(
        "  {:12} {:40} {:10} Planned",
        "graphql", "Any GraphQL API", "6"
    );
    println!(
        "  {:12} {:40} {:10} Planned",
        "cypher", "Neo4j, Memgraph, Apache AGE", "4"
    );
    println!(
        "  {:12} {:40} {:10} Planned",
        "sparql", "Any RDF triplestore", "4"
    );
    println!(
        "  {:12} {:40} {:10} Active",
        "wasm", "WebAssembly linear memory (typed-wasm)", "10"
    );
    println!(
        "  {:12} {:40} {:10} Planned (via VCL-total)",
        "vcl", "VeriSimDB", "10"
    );
    println!(
        "  {:12} {:40} {:10} Planned",
        "kql", "Azure Data Explorer / Kusto", "4"
    );
    println!(
        "  {:12} {:40} {:10} Planned",
        "gql", "ISO GQL databases", "4"
    );
    println!("  {:12} {:40} {:10} Planned", "fqldt", "Lithoglyph", "10");
    println!(
        "  {:12} {:40} {:10} Plugin API",
        "custom", "User-defined grammar", "var"
    );
}
