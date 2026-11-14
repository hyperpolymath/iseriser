// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// TypedQLiser plugin for typed-wasm — WebAssembly linear memory as a query target.
//
// Maps TypedQLiser's 10-level type safety framework to typed-wasm's region schemas.
// A region declaration is the "schema"; a region.get/set is the "query".
//
// This enables end-to-end verification: a database query is type-checked by
// TypedQLiser, and the memory region holding its results is type-checked by
// typed-wasm through this shared plugin interface.

use anyhow::{Result, anyhow};

use super::{NullIssue, QueryLanguagePlugin, Schema, SchemaIssue, TypeIssue};

/// TypedQLiser plugin for typed-wasm (.twasm) programs.
///
/// Treats region declarations as schemas and region.get/set as queries.
/// Implements Levels 1-4 of the TypedQLiser framework.
pub struct WasmPlugin;

impl Default for WasmPlugin {
    fn default() -> Self {
        Self::new()
    }
}

impl WasmPlugin {
    pub fn new() -> Self {
        WasmPlugin
    }
}

/// Parsed typed-wasm instruction (minimal subset for TypedQLiser integration).
#[derive(Debug, Clone)]
enum TwasmInstruction {
    /// region NAME { field: type; ... } [COUNT]
    RegionDef {
        name: String,
        fields: Vec<(String, String)>,
        count: Option<usize>,
    },
    /// region.get REGION[INDEX] .FIELD
    Get {
        region: String,
        index: Option<usize>,
        field: String,
    },
    /// region.set REGION .FIELD, VALUE
    Set { region: String, field: String },
    /// module NAME export/import region NAME { ... }
    ModuleRegion {
        module_name: String,
        direction: String, // "export" or "import"
        region_name: String,
        fields: Vec<(String, String)>,
    },
}

/// Parse a minimal .twasm program into instructions.
fn parse_twasm_minimal(content: &str) -> Result<Vec<TwasmInstruction>> {
    let mut instructions = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with(";;") || line.starts_with("//") {
            continue;
        }

        // region NAME { field: type; ... } [COUNT]
        if line.starts_with("region ") && line.contains('{') {
            let after = &line["region ".len()..];
            let name_end = after
                .find(|c: char| c == '{' || c.is_whitespace())
                .unwrap_or(after.len());
            let name = after[..name_end].trim().to_string();

            let brace_open = line
                .find('{')
                .ok_or_else(|| anyhow!("Missing '{{' in region"))?;
            let brace_close = line
                .rfind('}')
                .ok_or_else(|| anyhow!("Missing '}}' in region"))?;

            let fields_str = &line[brace_open + 1..brace_close];
            let fields = parse_field_list(fields_str)?;

            let after_brace = line[brace_close + 1..].trim();
            let count = if after_brace.starts_with('[') && after_brace.ends_with(']') {
                after_brace[1..after_brace.len() - 1].parse::<usize>().ok()
            } else {
                None
            };

            instructions.push(TwasmInstruction::RegionDef {
                name,
                fields,
                count,
            });
            continue;
        }

        // region.get REGION[INDEX] .FIELD
        if let Some(rest) = line.strip_prefix("region.get ") {
            let (region, index, field) = parse_access(rest)?;
            instructions.push(TwasmInstruction::Get {
                region,
                index,
                field,
            });
            continue;
        }

        // region.set REGION .FIELD, VALUE
        if let Some(rest) = line.strip_prefix("region.set ") {
            let dot_pos = rest
                .find('.')
                .ok_or_else(|| anyhow!("Missing '.' in set"))?;
            let region = rest[..dot_pos].trim().to_string();
            let after_dot = &rest[dot_pos + 1..];
            let comma_pos = after_dot.find(',').unwrap_or(after_dot.len());
            let field = after_dot[..comma_pos].trim().to_string();
            instructions.push(TwasmInstruction::Set { region, field });
            continue;
        }

        // module NAME export/import region NAME { ... }
        if line.starts_with("module ") {
            let parts: Vec<&str> = line.splitn(5, ' ').collect();
            if parts.len() >= 5 && (parts[2] == "export" || parts[2] == "import") {
                let module_name = parts[1].to_string();
                let direction = parts[2].to_string();
                // parts[3] should be "region"
                let region_rest = parts[4..].join(" ");
                let brace_open = region_rest.find('{');
                let brace_close = region_rest.rfind('}');
                if let (Some(bo), Some(bc)) = (brace_open, brace_close) {
                    let region_name = region_rest[..bo].trim().to_string();
                    let fields = parse_field_list(&region_rest[bo + 1..bc])?;
                    instructions.push(TwasmInstruction::ModuleRegion {
                        module_name,
                        direction,
                        region_name,
                        fields,
                    });
                }
            }
            continue;
        }
    }

    Ok(instructions)
}

/// Parse a semicolon-separated field list like "name: type; name2: type2"
fn parse_field_list(s: &str) -> Result<Vec<(String, String)>> {
    let mut fields = Vec::new();
    for entry in s.split(';') {
        let entry = entry.trim();
        if entry.is_empty() {
            continue;
        }
        let parts: Vec<&str> = entry.splitn(2, ':').collect();
        if parts.len() != 2 {
            return Err(anyhow!("Invalid field: '{}'", entry));
        }
        fields.push((parts[0].trim().to_string(), parts[1].trim().to_string()));
    }
    Ok(fields)
}

/// Parse a region access like "REGION[INDEX] .FIELD"
fn parse_access(s: &str) -> Result<(String, Option<usize>, String)> {
    let dot_pos = s
        .find('.')
        .ok_or_else(|| anyhow!("Missing '.' in access"))?;
    let before_dot = s[..dot_pos].trim();
    let field = s[dot_pos + 1..].trim().to_string();

    let (region, index) = if let Some(bracket_open) = before_dot.find('[') {
        let bracket_close = before_dot.find(']').ok_or_else(|| anyhow!("Missing ']'"))?;
        let region = before_dot[..bracket_open].trim().to_string();
        let idx = before_dot[bracket_open + 1..bracket_close]
            .trim()
            .parse::<usize>()
            .ok();
        (region, idx)
    } else {
        (before_dot.to_string(), None)
    };

    Ok((region, index, field))
}

/// Valid typed-wasm primitive types.
const VALID_TYPES: &[&str] = &[
    "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "v128", "bool",
];

impl QueryLanguagePlugin for WasmPlugin {
    fn name(&self) -> &str {
        "wasm"
    }

    /// Level 1: Check that the .twasm program parses correctly.
    fn parse_check(&self, query: &str) -> Result<()> {
        let instructions = parse_twasm_minimal(query)?;
        if instructions.is_empty() {
            return Err(anyhow!(
                "No typed-wasm instructions found. Expected region definitions or access operations."
            ));
        }
        Ok(())
    }

    /// Level 2: Check that all region.get/set references resolve to declared regions and fields.
    fn schema_check(&self, query: &str, _schema: &Schema) -> Result<Vec<SchemaIssue>> {
        let instructions = parse_twasm_minimal(query)?;
        let mut issues = Vec::new();

        // Collect declared regions and their fields.
        let mut regions: std::collections::HashMap<String, Vec<(String, String)>> =
            std::collections::HashMap::new();

        for instr in &instructions {
            match instr {
                TwasmInstruction::RegionDef { name, fields, .. } => {
                    regions.insert(name.clone(), fields.clone());
                }
                TwasmInstruction::ModuleRegion {
                    region_name,
                    fields,
                    ..
                } => {
                    regions
                        .entry(region_name.clone())
                        .or_insert_with(|| fields.clone());
                }
                _ => {}
            }
        }

        // Check all accesses resolve.
        for instr in &instructions {
            match instr {
                TwasmInstruction::Get {
                    region,
                    field,
                    index,
                } => {
                    if let Some(fields) = regions.get(region) {
                        if !fields.iter().any(|(n, _)| n == field) {
                            issues.push(SchemaIssue {
                                message: format!(
                                    "Field '{}' not found in region '{}'. Available: {}",
                                    field,
                                    region,
                                    fields
                                        .iter()
                                        .map(|(n, _)| n.as_str())
                                        .collect::<Vec<_>>()
                                        .join(", ")
                                ),
                            });
                        }
                        // Check bounds if count is known.
                        if let Some(idx) = index
                            && let Some(TwasmInstruction::RegionDef { count, .. }) =
                                instructions.iter().find(|i| match i {
                                    TwasmInstruction::RegionDef { name, .. } => name == region,
                                    _ => false,
                                })
                            && let Some(c) = count
                            && *idx >= *c
                        {
                            issues.push(SchemaIssue {
                                message: format!(
                                    "Index {} out of bounds for region '{}' (count {})",
                                    idx, region, c
                                ),
                            });
                        }
                    } else {
                        issues.push(SchemaIssue {
                            message: format!("Region '{}' not declared", region),
                        });
                    }
                }
                TwasmInstruction::Set { region, field } => {
                    if let Some(fields) = regions.get(region) {
                        if !fields.iter().any(|(n, _)| n == field) {
                            issues.push(SchemaIssue {
                                message: format!(
                                    "Field '{}' not found in region '{}'",
                                    field, region
                                ),
                            });
                        }
                    } else {
                        issues.push(SchemaIssue {
                            message: format!("Region '{}' not declared", region),
                        });
                    }
                }
                _ => {}
            }
        }

        // Check multi-module schema agreement.
        let mut exports: std::collections::HashMap<String, Vec<(String, String)>> =
            std::collections::HashMap::new();
        let mut imports: Vec<(String, String, Vec<(String, String)>)> = Vec::new();

        for instr in &instructions {
            if let TwasmInstruction::ModuleRegion {
                module_name,
                direction,
                region_name,
                fields,
            } = instr
            {
                if direction == "export" {
                    exports.insert(region_name.clone(), fields.clone());
                } else if direction == "import" {
                    imports.push((module_name.clone(), region_name.clone(), fields.clone()));
                }
            }
        }

        for (module, region, import_fields) in &imports {
            if let Some(export_fields) = exports.get(region) {
                for (iname, itype) in import_fields {
                    if let Some((_, etype)) = export_fields.iter().find(|(n, _)| n == iname) {
                        if itype != etype {
                            issues.push(SchemaIssue {
                                message: format!(
                                    "Module '{}' imports region '{}' field '{}' as {} but export declares {}",
                                    module, region, iname, itype, etype
                                ),
                            });
                        }
                    } else {
                        issues.push(SchemaIssue {
                            message: format!(
                                "Module '{}' imports field '{}' from region '{}' but export does not declare it",
                                module, iname, region
                            ),
                        });
                    }
                }
            }
        }

        Ok(issues)
    }

    /// Level 3: Check type compatibility of access operations.
    fn type_check(&self, query: &str, _schema: &Schema) -> Result<Vec<TypeIssue>> {
        let instructions = parse_twasm_minimal(query)?;
        let mut issues = Vec::new();

        // Collect region field types.
        let mut field_types: std::collections::HashMap<(String, String), String> =
            std::collections::HashMap::new();

        for instr in &instructions {
            if let TwasmInstruction::RegionDef { name, fields, .. } = instr {
                for (fname, ftype) in fields {
                    field_types.insert((name.clone(), fname.clone()), ftype.clone());
                }
            }
            if let TwasmInstruction::ModuleRegion {
                region_name,
                fields,
                ..
            } = instr
            {
                for (fname, ftype) in fields {
                    field_types.insert((region_name.clone(), fname.clone()), ftype.clone());
                }
            }
        }

        // Validate all field types are known WASM types.
        for ((region, field), ftype) in &field_types {
            // Strip modifiers like "linear " or "nullable ".
            let base_type = ftype
                .trim_start_matches("linear ")
                .trim_start_matches("nullable ")
                .trim();
            if !VALID_TYPES.contains(&base_type) && !base_type.starts_with("ptr<") {
                issues.push(TypeIssue {
                    message: format!(
                        "Unknown type '{}' for field '{}.{}'. Valid: {}",
                        ftype,
                        region,
                        field,
                        VALID_TYPES.join(", ")
                    ),
                });
            }
        }

        Ok(issues)
    }

    /// Level 4: Check null safety — nullable fields must be handled.
    fn null_check(&self, query: &str, _schema: &Schema) -> Result<Vec<NullIssue>> {
        let instructions = parse_twasm_minimal(query)?;
        let mut issues = Vec::new();

        // Collect nullable fields.
        let mut nullable_fields: std::collections::HashSet<(String, String)> =
            std::collections::HashSet::new();

        for instr in &instructions {
            if let TwasmInstruction::RegionDef { name, fields, .. } = instr {
                for (fname, ftype) in fields {
                    if ftype.contains("nullable") || ftype.starts_with("opt<") {
                        nullable_fields.insert((name.clone(), fname.clone()));
                    }
                }
            }
        }

        // Check accesses to nullable fields.
        for instr in &instructions {
            if let TwasmInstruction::Get { region, field, .. } = instr
                && nullable_fields.contains(&(region.clone(), field.clone()))
            {
                issues.push(NullIssue {
                        message: format!(
                            "Accessing nullable field '{}.{}' without null check. Use 'match' or 'unwrap_or'.",
                            region, field
                        ),
                        column: field.clone(),
                    });
            }
        }

        Ok(issues)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_check_valid() {
        let plugin = WasmPlugin::new();
        let result = plugin.parse_check("region R { x: i32; y: f64 } [100]");
        assert!(result.is_ok());
    }

    #[test]
    fn test_parse_check_empty() {
        let plugin = WasmPlugin::new();
        let result = plugin.parse_check("");
        assert!(result.is_err());
    }

    #[test]
    fn test_schema_check_valid_access() {
        let plugin = WasmPlugin::new();
        let program = "region R { x: i32; y: f64 } [10]\nregion.get R[0] .x";
        let issues = plugin
            .schema_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert!(issues.is_empty(), "Valid access should have no issues");
    }

    #[test]
    fn test_schema_check_unknown_field() {
        let plugin = WasmPlugin::new();
        let program = "region R { x: i32 } [10]\nregion.get R[0] .y";
        let issues = plugin
            .schema_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert_eq!(issues.len(), 1);
        assert!(issues[0].message.contains("not found"));
    }

    #[test]
    fn test_schema_check_oob() {
        let plugin = WasmPlugin::new();
        let program = "region R { x: i32 } [5]\nregion.get R[10] .x";
        let issues = plugin
            .schema_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert!(issues.iter().any(|i| i.message.contains("out of bounds")));
    }

    #[test]
    fn test_type_check_valid() {
        let plugin = WasmPlugin::new();
        let program = "region R { x: i32; y: f64 } [10]";
        let issues = plugin
            .type_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert!(issues.is_empty());
    }

    #[test]
    fn test_type_check_invalid_type() {
        let plugin = WasmPlugin::new();
        let program = "region R { x: string } [10]";
        let issues = plugin
            .type_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert_eq!(issues.len(), 1);
        assert!(issues[0].message.contains("Unknown type"));
    }

    #[test]
    fn test_null_check_nullable_field() {
        let plugin = WasmPlugin::new();
        let program = "region R { x: nullable i32 } [10]\nregion.get R[0] .x";
        let issues = plugin
            .null_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert_eq!(issues.len(), 1);
        assert!(issues[0].message.contains("nullable"));
    }

    #[test]
    fn test_multi_module_agreement() {
        let plugin = WasmPlugin::new();
        let program =
            "module A export region Shared { x: i32 }\nmodule B import region Shared { x: f64 }";
        let issues = plugin
            .schema_check(program, &Schema { tables: vec![] })
            .unwrap();
        assert!(
            issues
                .iter()
                .any(|i| i.message.contains("i32") && i.message.contains("f64"))
        );
    }
}
