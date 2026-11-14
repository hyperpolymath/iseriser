// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Type-checking engine for TypedQLiser.
// Uses the plugin system to delegate language-specific checks.

use crate::manifest::Manifest;
use crate::plugins::{self, Schema};
use anyhow::{Context, Result};

/// Result of type-checking a single query.
#[derive(Debug, Clone)]
pub struct CheckResult {
    /// Source file and line where the query was found.
    pub location: String,
    /// The query text (truncated for display).
    pub query_preview: String,
    /// Maximum type safety level achieved (1-10).
    pub level_achieved: u8,
    /// Per-level results.
    pub level_results: Vec<LevelResult>,
}

/// Result of checking one type safety level.
#[derive(Debug, Clone)]
pub struct LevelResult {
    pub level: u8,
    pub name: &'static str,
    pub status: LevelStatus,
    pub messages: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LevelStatus {
    Passed,
    Failed,
    Skipped,
}

static LEVEL_NAMES: [&str; 10] = [
    "Parse-time safety",
    "Schema-binding safety",
    "Type-compatible operations",
    "Null-safety",
    "Injection-proof safety",
    "Result-type safety",
    "Cardinality safety",
    "Effect-tracking safety",
    "Temporal safety",
    "Linearity safety",
];

/// Load the schema from the configured source.
fn load_schema(manifest: &Manifest) -> Result<Option<Schema>> {
    match manifest.typedql.schema_source.as_str() {
        "file" => {
            let path = manifest
                .database
                .schema_file
                .as_ref()
                .context("schema-source is 'file' but database.schema-file not set")?;
            let content = std::fs::read_to_string(path)
                .with_context(|| format!("Failed to read schema file: {}", path))?;
            let schema: Schema = serde_json::from_str(&content)
                .with_context(|| format!("Failed to parse schema file: {}", path))?;
            Ok(Some(schema))
        }
        "introspect" => {
            // TODO: connect to database and introspect schema
            eprintln!(
                "Warning: schema introspection not yet implemented. Use schema-source = \"file\" with a schema JSON file."
            );
            Ok(None)
        }
        "none" => Ok(None),
        other => anyhow::bail!("Unknown schema-source: {}", other),
    }
}

/// Check queries against type safety levels using the appropriate language plugin.
pub fn check_queries(
    manifest: &Manifest,
    single_query: Option<&str>,
    _proofs: bool,
) -> Result<Vec<CheckResult>> {
    let plugin = plugins::get_plugin(&manifest.typedql.language)?;
    let schema = load_schema(manifest)?;
    let mut results = Vec::new();

    if let Some(q) = single_query {
        let result = check_single_query(q, "<inline>", manifest, plugin.as_ref(), schema.as_ref())?;
        results.push(result);
    } else {
        for pattern in &manifest.paths.queries {
            for entry in glob::glob(pattern)? {
                let path = entry?;
                let content = std::fs::read_to_string(&path)?;
                // Check each SQL statement in the file
                let result = check_single_query(
                    &content,
                    &path.display().to_string(),
                    manifest,
                    plugin.as_ref(),
                    schema.as_ref(),
                )?;
                results.push(result);
            }
        }
    }

    Ok(results)
}

/// Check a single query against all applicable levels.
fn check_single_query(
    query: &str,
    location: &str,
    manifest: &Manifest,
    plugin: &dyn plugins::QueryLanguagePlugin,
    schema: Option<&Schema>,
) -> Result<CheckResult> {
    let mut level_results = Vec::new();
    let mut max_level = 0u8;
    let mut stop = false;

    for (i, name) in LEVEL_NAMES.iter().enumerate() {
        let level = (i + 1) as u8;

        // Skip if configured to skip, or if a previous level failed
        if manifest.levels.skip.contains(&level) || stop {
            level_results.push(LevelResult {
                level,
                name,
                status: LevelStatus::Skipped,
                messages: vec![],
            });
            continue;
        }

        let (status, messages) = match level {
            // Level 1: Parse-time safety
            1 => match plugin.parse_check(query) {
                Ok(()) => (LevelStatus::Passed, vec![]),
                Err(e) => (LevelStatus::Failed, vec![format!("{}", e)]),
            },

            // Level 2: Schema-binding safety
            2 => {
                if let Some(s) = schema {
                    match plugin.schema_check(query, s) {
                        Ok(issues) if issues.is_empty() => (LevelStatus::Passed, vec![]),
                        Ok(issues) => {
                            let msgs: Vec<String> =
                                issues.iter().map(|i| i.message.clone()).collect();
                            (LevelStatus::Failed, msgs)
                        }
                        Err(e) => (LevelStatus::Failed, vec![format!("{}", e)]),
                    }
                } else {
                    (LevelStatus::Skipped, vec!["No schema loaded".to_string()])
                }
            }

            // Level 3: Type-compatible operations
            3 => {
                if let Some(s) = schema {
                    match plugin.type_check(query, s) {
                        Ok(issues) if issues.is_empty() => (LevelStatus::Passed, vec![]),
                        Ok(issues) => {
                            let msgs: Vec<String> =
                                issues.iter().map(|i| i.message.clone()).collect();
                            (LevelStatus::Failed, msgs)
                        }
                        Err(e) => (LevelStatus::Failed, vec![format!("{}", e)]),
                    }
                } else {
                    (LevelStatus::Skipped, vec!["No schema loaded".to_string()])
                }
            }

            // Level 4: Null-safety
            4 => {
                if let Some(s) = schema {
                    match plugin.null_check(query, s) {
                        Ok(issues) if issues.is_empty() => (LevelStatus::Passed, vec![]),
                        Ok(issues) => {
                            let msgs: Vec<String> =
                                issues.iter().map(|i| i.message.clone()).collect();
                            // Null issues are warnings at level 4, not hard failures
                            if manifest.levels.enforce.contains(&4) {
                                (LevelStatus::Failed, msgs)
                            } else {
                                (LevelStatus::Passed, msgs)
                            }
                        }
                        Err(e) => (LevelStatus::Failed, vec![format!("{}", e)]),
                    }
                } else {
                    (LevelStatus::Skipped, vec!["No schema loaded".to_string()])
                }
            }

            // Level 5: Injection-proof safety
            5 => {
                // Check for string interpolation patterns that suggest injection risk.
                // A query with $1, $2 (parameterised) is safe. A query with concatenation is not.
                // For MVP: pass if query contains parameter placeholders, warn if it contains quotes around variables.
                let has_params =
                    query.contains("$1") || query.contains("?") || query.contains(":param");
                let has_concat =
                    query.contains("' +") || query.contains("' ||") || query.contains("format!");
                if has_concat {
                    (
                        LevelStatus::Failed,
                        vec![
                            "Query appears to use string concatenation — injection risk"
                                .to_string(),
                        ],
                    )
                } else if has_params || !query.contains('\'') {
                    (LevelStatus::Passed, vec![])
                } else {
                    (LevelStatus::Passed, vec![])
                }
            }

            // Levels 6-10: not yet implemented
            _ => (
                LevelStatus::Skipped,
                vec!["Not yet implemented".to_string()],
            ),
        };

        if status == LevelStatus::Failed && manifest.levels.enforce.contains(&level) {
            stop = true; // Stop checking higher levels after an enforced failure
        }

        if status == LevelStatus::Passed {
            max_level = level;
        }

        level_results.push(LevelResult {
            level,
            name,
            status,
            messages,
        });
    }

    // Truncate query for display
    let preview = if query.len() > 80 {
        format!("{}...", &query[..77])
    } else {
        query.trim().to_string()
    };

    Ok(CheckResult {
        location: location.to_string(),
        query_preview: preview,
        level_achieved: max_level,
        level_results,
    })
}

/// Report results to stdout.
pub fn report_results(results: &[CheckResult], manifest: &Manifest, ci: bool) -> Result<()> {
    let mut errors = 0u32;

    for result in results {
        let target = manifest.typedql.level;
        let achieved = result.level_achieved;
        let status_str = if achieved >= target {
            "\x1b[32mPASS\x1b[0m"
        } else {
            "\x1b[31mFAIL\x1b[0m"
        };

        println!(
            "{} [L{}/{}] {}",
            status_str, achieved, target, result.location
        );

        if achieved < target {
            errors += 1;
        }

        // Show per-level detail for failures or when verbose
        for lr in &result.level_results {
            let icon = match lr.status {
                LevelStatus::Passed => "\x1b[32m✓\x1b[0m",
                LevelStatus::Failed => "\x1b[31m✗\x1b[0m",
                LevelStatus::Skipped => "\x1b[90m-\x1b[0m",
            };
            if lr.status == LevelStatus::Failed {
                println!("  {} L{}: {}", icon, lr.level, lr.name);
                for msg in &lr.messages {
                    println!("      {}", msg);
                }
            }
        }
    }

    println!(
        "\n{} queries checked, {} passed, {} failed",
        results.len(),
        results.len() as u32 - errors,
        errors
    );

    if ci && errors > 0 {
        std::process::exit(1);
    }

    Ok(())
}
