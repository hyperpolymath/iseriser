// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for typedqliser.toml.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub typedql: TypedQLConfig,
    pub database: DatabaseConfig,
    pub paths: PathsConfig,
    #[serde(default)]
    pub output: OutputConfig,
    #[serde(default)]
    pub levels: LevelsConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TypedQLConfig {
    pub name: String,
    pub language: String,
    #[serde(default = "default_level")]
    pub level: u8,
    #[serde(rename = "schema-source", default = "default_schema_source")]
    pub schema_source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    #[serde(rename = "target-db")]
    pub target_db: String,
    #[serde(rename = "connection-string", default)]
    pub connection_string: Option<String>,
    #[serde(rename = "schema-file", default)]
    pub schema_file: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathsConfig {
    #[serde(default = "default_queries")]
    pub queries: Vec<String>,
    #[serde(default = "default_embedding")]
    pub embedding: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutputConfig {
    #[serde(rename = "proof-certificates", default)]
    pub proof_certificates: bool,
    #[serde(rename = "error-format", default = "default_error_format")]
    pub error_format: String,
    #[serde(rename = "ci-mode", default)]
    pub ci_mode: bool,
}

impl Default for OutputConfig {
    fn default() -> Self {
        Self {
            proof_certificates: false,
            error_format: default_error_format(),
            ci_mode: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LevelsConfig {
    #[serde(default = "default_enforce")]
    pub enforce: Vec<u8>,
    #[serde(default)]
    pub warn: Vec<u8>,
    #[serde(default)]
    pub skip: Vec<u8>,
}

impl Default for LevelsConfig {
    fn default() -> Self {
        Self {
            enforce: default_enforce(),
            warn: vec![7, 8],
            skip: vec![9, 10],
        }
    }
}

fn default_level() -> u8 {
    6
}
fn default_schema_source() -> String {
    "introspect".to_string()
}
fn default_queries() -> Vec<String> {
    vec!["src/**/*.sql".to_string()]
}
fn default_embedding() -> String {
    "standalone".to_string()
}
fn default_error_format() -> String {
    "human".to_string()
}
fn default_enforce() -> Vec<u8> {
    vec![1, 2, 3, 4, 5, 6]
}

pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content =
        std::fs::read_to_string(path).with_context(|| format!("Failed to read: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse: {}", path))
}

pub fn init_manifest(language: &str, database: &str) -> Result<()> {
    let path = "typedqliser.toml";
    if std::path::Path::new(path).exists() {
        anyhow::bail!("typedqliser.toml already exists");
    }

    let ext = match language {
        "graphql" => "graphql",
        "cypher" => "cypher",
        "sparql" => "sparql",
        _ => "sql",
    };

    let template = format!(
        r#"# TypedQLiser manifest — formal type safety for {language} queries
# Docs: https://github.com/hyperpolymath/typedqliser

[typedql]
name = "my-project"
language = "{language}"
level = 6                        # enforce levels 1-6 (established)
schema-source = "introspect"     # introspect | file | inline

[database]
target-db = "{database}"
# connection-string = "{database}://localhost/mydb"

[paths]
queries = ["src/**/*.{ext}"]
embedding = "standalone"          # standalone | string-literal | tagged-template

[output]
proof-certificates = false
error-format = "human"            # human | gcc | json | sarif
ci-mode = false

[levels]
enforce = [1, 2, 3, 4, 5, 6]
warn = [7, 8]
skip = [9, 10]
"#
    );

    std::fs::write(path, template)?;
    println!("Created typedqliser.toml for {} on {}", language, database);
    Ok(())
}

pub fn print_info(m: &Manifest) {
    println!("=== TypedQLiser: {} ===", m.typedql.name);
    println!("Language:    {}", m.typedql.language);
    println!("Target DB:   {}", m.database.target_db);
    println!("Max level:   {}", m.typedql.level);
    println!("Schema:      {}", m.typedql.schema_source);
    println!("Query paths: {:?}", m.paths.queries);
    println!("Embedding:   {}", m.paths.embedding);
    println!("Enforce:     {:?}", m.levels.enforce);
    println!("Warn:        {:?}", m.levels.warn);
    println!("Skip:        {:?}", m.levels.skip);
}
