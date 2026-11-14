// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser submodule — validates function budget annotations from the manifest
// and produces a structured representation suitable for code generation.
//
// The parser ensures that all function budgets are semantically valid before
// any code is generated, catching issues like missing sources, invalid budget
// ranges, and conflicting annotations early.

use anyhow::{Result, bail};

use crate::abi::{CarbonBudget, EnergyBudget, FunctionBudget};

/// A fully validated function budget, ready for instrumentation code generation.
///
/// This is the output of the parsing/validation stage. Unlike `FunctionBudget`
/// (which comes directly from TOML deserialization), a `ParsedFunctionBudget`
/// has been checked for semantic correctness and has pre-built `EnergyBudget`
/// and `CarbonBudget` objects.
#[derive(Debug, Clone)]
pub struct ParsedFunctionBudget {
    /// Function name.
    pub name: String,
    /// Source file path.
    pub source: String,
    /// Validated energy budget (None if unbounded).
    pub energy_budget: Option<EnergyBudget>,
    /// Validated carbon budget (None if unbounded).
    pub carbon_budget: Option<CarbonBudget>,
}

/// Parse and validate a list of function budgets from the manifest.
///
/// This converts raw `FunctionBudget` entries (from TOML) into validated
/// `ParsedFunctionBudget` entries, checking:
/// - Names are non-empty and valid identifiers
/// - Source paths are non-empty
/// - Budget values are non-negative
/// - At least one budget (energy or carbon) is specified per function
///
/// # Errors
/// Returns an error if any function budget fails validation.
pub fn parse_function_budgets(functions: &[FunctionBudget]) -> Result<Vec<ParsedFunctionBudget>> {
    let mut parsed = Vec::with_capacity(functions.len());

    for func in functions {
        let pf = parse_single_function(func)?;
        parsed.push(pf);
    }

    Ok(parsed)
}

/// Parse and validate a single function budget entry.
fn parse_single_function(func: &FunctionBudget) -> Result<ParsedFunctionBudget> {
    // Validate function name is a plausible identifier.
    let name = func.name.trim();
    if name.is_empty() {
        bail!("Function name cannot be empty");
    }
    if !is_valid_identifier(name) {
        bail!(
            "Function name '{}' is not a valid identifier (must be alphanumeric + underscores)",
            name
        );
    }

    // Validate source path.
    let source = func.source.trim();
    if source.is_empty() {
        bail!("Function '{}' must have a non-empty source path", name);
    }

    // Validate energy budget if present.
    if let Some(energy) = func.energy_budget_mj
        && energy < 0.0
    {
        bail!(
            "Function '{}' has invalid energy budget: {} mJ (must be >= 0)",
            name,
            energy
        );
    }

    // Validate carbon budget if present.
    if let Some(carbon) = func.carbon_budget_mg
        && carbon < 0.0
    {
        bail!(
            "Function '{}' has invalid carbon budget: {} mg CO2 (must be >= 0)",
            name,
            carbon
        );
    }

    // At least one budget should be specified (warn-worthy but not fatal for Phase 1).
    // We still allow fully unbounded functions for monitoring-only use cases.

    Ok(ParsedFunctionBudget {
        name: name.to_string(),
        source: source.to_string(),
        energy_budget: func.energy_budget_mj.map(EnergyBudget::new),
        carbon_budget: func.carbon_budget_mg.map(CarbonBudget::new),
    })
}

/// Check whether a string is a valid function identifier.
///
/// Accepts alphanumeric characters, underscores, and double-colons (for Rust
/// path-qualified names like `module::function`).
fn is_valid_identifier(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    // First character must be alphabetic or underscore.
    let mut chars = s.chars();
    let first = chars.next().expect("TODO: handle error");
    if !first.is_alphabetic() && first != '_' {
        return false;
    }
    // Remaining characters: alphanumeric, underscore, or colon (for path-qualified names).
    for ch in chars {
        if !ch.is_alphanumeric() && ch != '_' && ch != ':' {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::FunctionBudget;

    #[test]
    fn test_parse_valid_function() {
        let funcs = vec![FunctionBudget {
            name: "process_batch".to_string(),
            source: "src/batch.rs".to_string(),
            energy_budget_mj: Some(50.0),
            carbon_budget_mg: Some(10.0),
        }];
        let parsed = parse_function_budgets(&funcs).expect("TODO: handle error");
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].name, "process_batch");
        assert!(parsed[0].energy_budget.is_some());
        assert!(parsed[0].carbon_budget.is_some());
    }

    #[test]
    fn test_parse_invalid_name() {
        let funcs = vec![FunctionBudget {
            name: "123invalid".to_string(),
            source: "src/lib.rs".to_string(),
            energy_budget_mj: Some(10.0),
            carbon_budget_mg: None,
        }];
        assert!(parse_function_budgets(&funcs).is_err());
    }

    #[test]
    fn test_parse_path_qualified_name() {
        let funcs = vec![FunctionBudget {
            name: "module::process".to_string(),
            source: "src/lib.rs".to_string(),
            energy_budget_mj: Some(10.0),
            carbon_budget_mg: None,
        }];
        let parsed = parse_function_budgets(&funcs).expect("TODO: handle error");
        assert_eq!(parsed[0].name, "module::process");
    }

    #[test]
    fn test_parse_negative_energy_budget() {
        let funcs = vec![FunctionBudget {
            name: "bad_func".to_string(),
            source: "src/lib.rs".to_string(),
            energy_budget_mj: Some(-1.0),
            carbon_budget_mg: None,
        }];
        assert!(parse_function_budgets(&funcs).is_err());
    }

    #[test]
    fn test_valid_identifiers() {
        assert!(is_valid_identifier("process_batch"));
        assert!(is_valid_identifier("_private"));
        assert!(is_valid_identifier("module::func"));
        assert!(!is_valid_identifier(""));
        assert!(!is_valid_identifier("123abc"));
        assert!(!is_valid_identifier("has space"));
    }
}
