// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! Comprehensive L3 integration tests for TypedQLiser.
//!
//! Test categories:
//!   - Point-to-point: test SQL parsing (L1), schema binding (L2),
//!     type compatibility (L3), null safety (L4) individually
//!   - End-to-end: full SQL query -> manifest -> generate -> validate
//!   - Aspect: invalid SQL, missing tables, type mismatches, nullable access
//!   - Edge cases: empty queries, nested subqueries, JOIN types, GROUP BY

use typedqliser::plugins::{ColumnDef, Schema, SchemaIssue, TableDef, get_plugin};

// ---------------------------------------------------------------------------
// Helper: build a test schema with known tables, columns, types, nullability
// ---------------------------------------------------------------------------

/// Build a schema with users, posts, and comments tables for testing.
fn test_schema() -> Schema {
    Schema {
        tables: vec![
            TableDef {
                name: "users".to_string(),
                columns: vec![
                    ColumnDef {
                        name: "id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: true,
                    },
                    ColumnDef {
                        name: "name".to_string(),
                        col_type: "text".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "email".to_string(),
                        col_type: "text".to_string(),
                        nullable: true,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "age".to_string(),
                        col_type: "integer".to_string(),
                        nullable: true,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "active".to_string(),
                        col_type: "boolean".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "created_at".to_string(),
                        col_type: "timestamp".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                ],
            },
            TableDef {
                name: "posts".to_string(),
                columns: vec![
                    ColumnDef {
                        name: "id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: true,
                    },
                    ColumnDef {
                        name: "user_id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "title".to_string(),
                        col_type: "text".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "body".to_string(),
                        col_type: "text".to_string(),
                        nullable: true,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "views".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                ],
            },
            TableDef {
                name: "comments".to_string(),
                columns: vec![
                    ColumnDef {
                        name: "id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: true,
                    },
                    ColumnDef {
                        name: "post_id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "author_name".to_string(),
                        col_type: "text".to_string(),
                        nullable: true,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "content".to_string(),
                        col_type: "text".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                ],
            },
        ],
    }
}

// ============================================================================
// Point-to-point: Level 1 — Parse-time safety
// ============================================================================

#[test]
fn l1_valid_select() {
    let plugin = get_plugin("sql").unwrap();
    assert!(plugin.parse_check("SELECT 1").is_ok());
}

#[test]
fn l1_valid_select_from() {
    let plugin = get_plugin("sql").unwrap();
    assert!(plugin.parse_check("SELECT id FROM users").is_ok());
}

#[test]
fn l1_valid_insert() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("INSERT INTO users (name) VALUES ('Alice')")
            .is_ok()
    );
}

#[test]
fn l1_valid_update() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("UPDATE users SET name = 'Bob' WHERE id = 1")
            .is_ok()
    );
}

#[test]
fn l1_valid_delete() {
    let plugin = get_plugin("sql").unwrap();
    assert!(plugin.parse_check("DELETE FROM users WHERE id = 1").is_ok());
}

#[test]
fn l1_valid_join() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT u.id, p.title FROM users u JOIN posts p ON u.id = p.user_id")
            .is_ok()
    );
}

#[test]
fn l1_valid_subquery() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT * FROM users WHERE id IN (SELECT user_id FROM posts)")
            .is_ok()
    );
}

#[test]
fn l1_valid_group_by_having() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT user_id, COUNT(*) FROM posts GROUP BY user_id HAVING COUNT(*) > 5")
            .is_ok()
    );
}

#[test]
fn l1_invalid_syntax_missing_from() {
    let plugin = get_plugin("sql").unwrap();
    // "SELECT * WHERE" is syntactically invalid in most dialects
    let result = plugin.parse_check("SELECT * WHERE id = 1");
    // sqlparser may or may not reject this; the key point is parse_check handles it
    // We just verify it doesn't panic
    let _ = result;
}

#[test]
fn l1_invalid_syntax_gibberish() {
    let plugin = get_plugin("sql").unwrap();
    let result = plugin.parse_check("NOT VALID SQL AT ALL %%% !!!");
    assert!(result.is_err(), "Gibberish should fail parse");
}

#[test]
fn l1_invalid_syntax_unclosed_paren() {
    let plugin = get_plugin("sql").unwrap();
    let result = plugin.parse_check("SELECT (id FROM users");
    assert!(result.is_err(), "Unclosed parenthesis should fail parse");
}

#[test]
fn l1_multiple_statements() {
    let plugin = get_plugin("sql").unwrap();
    assert!(plugin.parse_check("SELECT 1; SELECT 2; SELECT 3").is_ok());
}

#[test]
fn l1_postgresql_dialect() {
    let plugin = get_plugin("postgresql").unwrap();
    assert!(plugin.parse_check("SELECT 1").is_ok());
}

#[test]
fn l1_mysql_dialect() {
    let plugin = get_plugin("mysql").unwrap();
    assert!(plugin.parse_check("SELECT 1").is_ok());
}

#[test]
fn l1_sqlite_dialect() {
    let plugin = get_plugin("sqlite").unwrap();
    assert!(plugin.parse_check("SELECT 1").is_ok());
}

// ============================================================================
// Point-to-point: Level 2 — Schema-binding safety
// ============================================================================

#[test]
fn l2_valid_table_reference() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT id FROM users", &schema)
        .unwrap();
    assert!(
        issues.is_empty(),
        "Valid table should have no issues. Got: {:?}",
        issues.iter().map(|i| &i.message).collect::<Vec<_>>()
    );
}

#[test]
fn l2_missing_table() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT id FROM nonexistent", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.message.contains("nonexistent")),
        "Should detect missing table"
    );
}

#[test]
fn l2_missing_column() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT nonexistent_col FROM users", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.message.contains("nonexistent_col")),
        "Should detect missing column"
    );
}

#[test]
fn l2_valid_multi_table_join() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check(
            "SELECT u.id, p.title FROM users u JOIN posts p ON u.id = p.user_id",
            &schema,
        )
        .unwrap();
    // Aliases `u`/`p` resolve to `users`/`posts`; every column exists, so a
    // valid aliased join must produce no schema-binding issues.
    assert!(
        issues.is_empty(),
        "Aliased join over existing columns must pass L2. Got: {:?}",
        issues
    );
}

#[test]
fn l2_alias_resolves_unknown_column() {
    // The alias resolves to a real table, so a genuinely missing column on the
    // aliased table is still caught (no false negative from alias resolution).
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT u.nonexistent FROM users u", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.message.contains("nonexistent")),
        "Missing column on an aliased table must be flagged. Got: {:?}",
        issues
    );
}

#[test]
fn l3_type_check_resolves_alias() {
    // `u.name` (text) compared to a numeric literal must be caught even though
    // the column is referenced through the alias `u`.
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT u.id FROM users u WHERE u.name = 42", &schema)
        .unwrap();
    assert!(
        !issues.is_empty(),
        "Type mismatch on an alias-qualified column must be flagged"
    );
}

#[test]
fn l4_null_check_resolves_alias() {
    // `u.email` is nullable; selecting it through the alias `u` without null
    // handling must still raise a null-safety issue.
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .null_check("SELECT u.email FROM users u", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.column == "email"),
        "Nullable alias-qualified column must be flagged at L4. Got: {:?}",
        issues
    );
}

#[test]
fn l2_multiple_missing_tables() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT a.x FROM foo a JOIN bar b ON a.id = b.id", &schema)
        .unwrap();
    let table_issues: Vec<&SchemaIssue> = issues
        .iter()
        .filter(|i| i.message.contains("not found in schema"))
        .collect();
    assert!(
        table_issues.len() >= 2,
        "Should detect both missing tables foo and bar"
    );
}

#[test]
fn l2_insert_valid_table() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("INSERT INTO users (name) VALUES ('Alice')", &schema)
        .unwrap();
    let table_issues: Vec<&SchemaIssue> = issues
        .iter()
        .filter(|i| i.message.contains("Table") && i.message.contains("not found"))
        .collect();
    assert!(table_issues.is_empty(), "users table exists in schema");
}

#[test]
fn l2_insert_missing_table() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("INSERT INTO logs (msg) VALUES ('hello')", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.message.contains("logs")),
        "Should detect missing 'logs' table"
    );
}

#[test]
fn l2_delete_missing_table() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("DELETE FROM sessions WHERE expired = true", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.message.contains("sessions")),
        "Should detect missing 'sessions' table"
    );
}

#[test]
fn l2_empty_schema() {
    let plugin = get_plugin("sql").unwrap();
    let empty_schema = Schema { tables: vec![] };
    let issues = plugin
        .schema_check("SELECT id FROM users", &empty_schema)
        .unwrap();
    assert!(
        !issues.is_empty(),
        "All tables should be missing in empty schema"
    );
}

// ============================================================================
// Point-to-point: Level 3 — Type-compatible operations
// ============================================================================

#[test]
fn l3_compatible_integer_comparison() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE id = 1", &schema)
        .unwrap();
    assert!(
        issues.is_empty(),
        "Integer compared to integer literal should be compatible"
    );
}

#[test]
fn l3_compatible_text_comparison() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE name = 'Alice'", &schema)
        .unwrap();
    assert!(
        issues.is_empty(),
        "Text column compared to string literal should be compatible"
    );
}

#[test]
fn l3_incompatible_text_vs_integer() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE name = 42", &schema)
        .unwrap();
    // name is text, 42 is numeric — should be flagged
    assert!(
        !issues.is_empty(),
        "Comparing text column to integer should be flagged"
    );
}

#[test]
fn l3_incompatible_integer_vs_text() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE id = 'not_a_number'", &schema)
        .unwrap();
    assert!(
        !issues.is_empty(),
        "Comparing integer column to string should be flagged"
    );
}

#[test]
fn l3_arithmetic_on_numeric_columns() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM posts WHERE views + 1 > 100", &schema)
        .unwrap();
    assert!(
        issues.is_empty(),
        "Arithmetic on numeric columns should be fine"
    );
}

#[test]
fn l3_arithmetic_on_text_column() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE name + 1 > 0", &schema)
        .unwrap();
    // name is text — arithmetic should be flagged
    assert!(
        !issues.is_empty(),
        "Arithmetic on text column should be flagged"
    );
}

#[test]
fn l3_boolean_comparison_compatible() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE active = true", &schema)
        .unwrap();
    assert!(
        issues.is_empty(),
        "Boolean column compared to boolean literal should be compatible"
    );
}

#[test]
fn l3_no_where_clause_no_issues() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin.type_check("SELECT id FROM users", &schema).unwrap();
    assert!(
        issues.is_empty(),
        "Query without WHERE clause should have no type issues"
    );
}

// ============================================================================
// Point-to-point: Level 4 — Null safety
// ============================================================================

#[test]
fn l4_nullable_column_selected_directly() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .null_check("SELECT email FROM users", &schema)
        .unwrap();
    // email is nullable — should be flagged
    assert!(
        issues.iter().any(|i| i.column == "email"),
        "Nullable column 'email' selected without handling should be flagged"
    );
}

#[test]
fn l4_non_nullable_column_clean() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .null_check("SELECT id, name FROM users", &schema)
        .unwrap();
    // id and name are NOT nullable — should have no null issues
    assert!(
        issues.is_empty(),
        "Non-nullable columns should not be flagged. Got: {:?}",
        issues.iter().map(|i| &i.column).collect::<Vec<_>>()
    );
}

#[test]
fn l4_multiple_nullable_columns() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .null_check("SELECT email, age FROM users", &schema)
        .unwrap();
    let flagged: Vec<&str> = issues.iter().map(|i| i.column.as_str()).collect();
    assert!(flagged.contains(&"email"), "email is nullable");
    assert!(flagged.contains(&"age"), "age is nullable");
}

#[test]
fn l4_nullable_in_different_table() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .null_check("SELECT body FROM posts", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.column == "body"),
        "posts.body is nullable — should be flagged"
    );
}

#[test]
fn l4_nullable_comment_author() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .null_check("SELECT author_name FROM comments", &schema)
        .unwrap();
    assert!(
        issues.iter().any(|i| i.column == "author_name"),
        "comments.author_name is nullable"
    );
}

#[test]
fn l4_select_star_flags_nullable() {
    // `SELECT *` is expanded to the table's columns, so its nullable columns
    // (users.email, users.age) are flagged like an explicit selection would be.
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin.null_check("SELECT * FROM users", &schema).unwrap();
    assert!(
        issues.iter().any(|i| i.column == "email"),
        "SELECT * must flag nullable 'email'. Got: {:?}",
        issues
    );
    assert!(
        issues.iter().any(|i| i.column == "age"),
        "SELECT * must flag nullable 'age'. Got: {:?}",
        issues
    );
    // Non-nullable columns (id, name) must NOT be flagged.
    assert!(
        !issues
            .iter()
            .any(|i| i.column == "id" || i.column == "name"),
        "SELECT * must not flag non-nullable columns. Got: {:?}",
        issues
    );
}

#[test]
fn l2_cte_name_not_flagged_as_missing_table() {
    // A CTE name is a valid in-query table source, not a schema table, so it
    // must not be reported as "not found in schema".
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check(
            "WITH recent AS (SELECT id FROM users) SELECT id FROM recent",
            &schema,
        )
        .unwrap();
    assert!(
        !issues.iter().any(|i| i.message.contains("recent")),
        "CTE name 'recent' must not be flagged as a missing table. Got: {:?}",
        issues
    );
}

#[test]
fn l2_subquery_missing_table_flagged() {
    // A missing table inside a `WHERE ... IN (SELECT ...)` subquery must be
    // caught, not only the outermost FROM.
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check(
            "SELECT id FROM users WHERE id IN (SELECT user_id FROM nonexistent_table)",
            &schema,
        )
        .unwrap();
    assert!(
        issues
            .iter()
            .any(|i| i.message.contains("nonexistent_table")),
        "Missing table inside a subquery must be flagged. Got: {:?}",
        issues
    );
}

#[test]
fn l2_valid_subquery_no_false_positive() {
    // Both the outer and the subquery tables exist, so no table-binding issue.
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check(
            "SELECT id FROM users WHERE id IN (SELECT user_id FROM posts)",
            &schema,
        )
        .unwrap();
    assert!(
        !issues.iter().any(|i| i.message.contains("not found")),
        "Valid subquery over existing tables must not raise a binding issue. Got: {:?}",
        issues
    );
}

#[test]
fn l2_derived_table_validated() {
    // A derived table's inner FROM is validated (bogus_table flagged), while
    // the derived-table alias `sub` is a non-schema source and is not flagged.
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check(
            "SELECT sub.x FROM (SELECT id FROM bogus_table) sub",
            &schema,
        )
        .unwrap();
    assert!(
        issues.iter().any(|i| i.message.contains("bogus_table")),
        "Missing table inside a derived table must be flagged. Got: {:?}",
        issues
    );
    assert!(
        !issues.iter().any(|i| i.message.contains("'sub'")),
        "Derived-table alias 'sub' must not be flagged as a missing table. Got: {:?}",
        issues
    );
}

// ============================================================================
// End-to-end: Full query -> manifest -> check pipeline
// ============================================================================

#[test]
fn e2e_valid_query_passes_all_levels() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();

    let query = "SELECT id, name FROM users WHERE id = 1";

    // Level 1: parse
    assert!(plugin.parse_check(query).is_ok(), "L1 should pass");

    // Level 2: schema binding
    let l2 = plugin.schema_check(query, &schema).unwrap();
    assert!(l2.is_empty(), "L2 should pass");

    // Level 3: type compatibility
    let l3 = plugin.type_check(query, &schema).unwrap();
    assert!(l3.is_empty(), "L3 should pass");

    // Level 4: null safety (id and name are not nullable)
    let l4 = plugin.null_check(query, &schema).unwrap();
    assert!(l4.is_empty(), "L4 should pass");
}

#[test]
fn e2e_query_fails_at_l1() {
    let plugin = get_plugin("sql").unwrap();
    let query = "SELECTT FROM WHERE %%";
    assert!(
        plugin.parse_check(query).is_err(),
        "Gibberish query should fail at L1"
    );
}

#[test]
fn e2e_query_passes_l1_fails_l2() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let query = "SELECT id FROM nonexistent_table";

    assert!(plugin.parse_check(query).is_ok(), "L1 should pass");

    let l2 = plugin.schema_check(query, &schema).unwrap();
    assert!(!l2.is_empty(), "L2 should fail — table missing");
}

#[test]
fn e2e_query_passes_l1_l2_fails_l3() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let query = "SELECT id FROM users WHERE name = 42";

    assert!(plugin.parse_check(query).is_ok(), "L1 should pass");

    let l2 = plugin.schema_check(query, &schema).unwrap();
    assert!(l2.is_empty(), "L2 should pass");

    let l3 = plugin.type_check(query, &schema).unwrap();
    assert!(!l3.is_empty(), "L3 should fail — text vs integer");
}

#[test]
fn e2e_query_passes_l1_l2_l3_fails_l4() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    // email is nullable, comparing with = is fine for types but null not handled
    let query = "SELECT email FROM users WHERE id = 1";

    assert!(plugin.parse_check(query).is_ok(), "L1 should pass");

    let l2 = plugin.schema_check(query, &schema).unwrap();
    assert!(l2.is_empty(), "L2 should pass");

    let l3 = plugin.type_check(query, &schema).unwrap();
    assert!(l3.is_empty(), "L3 should pass");

    let l4 = plugin.null_check(query, &schema).unwrap();
    assert!(!l4.is_empty(), "L4 should fail — nullable email selected");
}

#[test]
fn e2e_multi_table_join_all_levels() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let query = "SELECT users.id, posts.title FROM users JOIN posts ON users.id = posts.user_id WHERE users.id = 1";

    assert!(plugin.parse_check(query).is_ok(), "L1 should pass");

    let l2 = plugin.schema_check(query, &schema).unwrap();
    // Both tables and columns exist with qualified names
    assert!(
        l2.is_empty(),
        "L2 should pass for qualified names. Got: {:?}",
        l2.iter().map(|i| &i.message).collect::<Vec<_>>()
    );
}

// ============================================================================
// Aspect: Invalid SQL
// ============================================================================

#[test]
fn aspect_empty_query_parse() {
    let plugin = get_plugin("sql").unwrap();
    // Empty string — sqlparser may accept it (no statements) or reject it
    let result = plugin.parse_check("");
    // Document behavior: don't assert pass/fail, just ensure no panic
    let _ = result;
}

#[test]
fn aspect_semicolon_only() {
    let plugin = get_plugin("sql").unwrap();
    let result = plugin.parse_check(";");
    let _ = result; // No panic
}

#[test]
fn aspect_comment_only() {
    let plugin = get_plugin("sql").unwrap();
    let result = plugin.parse_check("-- just a comment");
    let _ = result; // No panic
}

#[test]
fn aspect_whitespace_only() {
    let plugin = get_plugin("sql").unwrap();
    let result = plugin.parse_check("   \n   \t   ");
    let _ = result; // No panic
}

#[test]
fn aspect_very_long_query() {
    let plugin = get_plugin("sql").unwrap();
    let cols: Vec<String> = (0..500).map(|i| format!("col{}", i)).collect();
    let query = format!("SELECT {} FROM users", cols.join(", "));
    assert!(
        plugin.parse_check(&query).is_ok(),
        "Very long SELECT list should parse"
    );
}

// ============================================================================
// Aspect: Missing tables and columns
// ============================================================================

#[test]
fn aspect_typo_in_table_name() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT id FROM usres", &schema)
        .unwrap(); // "usres" typo
    assert!(
        issues.iter().any(|i| i.message.contains("usres")),
        "Should catch typo in table name"
    );
}

#[test]
fn aspect_typo_in_column_name() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check("SELECT nme FROM users", &schema)
        .unwrap(); // "nme" typo
    assert!(
        issues.iter().any(|i| i.message.contains("nme")),
        "Should catch typo in column name"
    );
}

// ============================================================================
// Aspect: Type mismatches
// ============================================================================

#[test]
fn aspect_boolean_vs_integer() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE active = 42", &schema)
        .unwrap();
    // active is boolean, 42 is numeric — should flag
    assert!(!issues.is_empty(), "Boolean vs integer should be flagged");
}

#[test]
fn aspect_text_arithmetic() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .type_check("SELECT id FROM users WHERE name * 2 > 0", &schema)
        .unwrap();
    assert!(!issues.is_empty(), "Arithmetic on text should be flagged");
}

// ============================================================================
// Edge cases: Nested subqueries
// ============================================================================

#[test]
fn edge_nested_subquery_parse() {
    let plugin = get_plugin("sql").unwrap();
    let query = "SELECT * FROM (SELECT id, name FROM users) AS sub WHERE sub.id > 0";
    assert!(plugin.parse_check(query).is_ok());
}

#[test]
fn edge_correlated_subquery_parse() {
    let plugin = get_plugin("sql").unwrap();
    let query = "SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id)";
    assert!(plugin.parse_check(query).is_ok());
}

#[test]
fn edge_deeply_nested_subquery() {
    let plugin = get_plugin("sql").unwrap();
    let query = "SELECT * FROM (SELECT * FROM (SELECT * FROM (SELECT 1 AS x) a) b) c";
    assert!(plugin.parse_check(query).is_ok());
}

// ============================================================================
// Edge cases: JOIN types
// ============================================================================

#[test]
fn edge_inner_join() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT u.id FROM users u INNER JOIN posts p ON u.id = p.user_id")
            .is_ok()
    );
}

#[test]
fn edge_left_join() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT u.id FROM users u LEFT JOIN posts p ON u.id = p.user_id")
            .is_ok()
    );
}

#[test]
fn edge_right_join() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT u.id FROM users u RIGHT JOIN posts p ON u.id = p.user_id")
            .is_ok()
    );
}

#[test]
fn edge_full_outer_join() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT u.id FROM users u FULL OUTER JOIN posts p ON u.id = p.user_id")
            .is_ok()
    );
}

#[test]
fn edge_cross_join() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT u.id FROM users u CROSS JOIN posts p")
            .is_ok()
    );
}

#[test]
fn edge_multi_join_schema_check() {
    let plugin = get_plugin("sql").unwrap();
    let schema = test_schema();
    let issues = plugin
        .schema_check(
            "SELECT users.id, posts.title, comments.content \
             FROM users \
             JOIN posts ON users.id = posts.user_id \
             JOIN comments ON posts.id = comments.post_id",
            &schema,
        )
        .unwrap();
    assert!(
        issues.is_empty(),
        "Three-table join with qualified columns should pass L2. Got: {:?}",
        issues.iter().map(|i| &i.message).collect::<Vec<_>>()
    );
}

// ============================================================================
// Edge cases: GROUP BY, HAVING, ORDER BY
// ============================================================================

#[test]
fn edge_group_by_parse() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT user_id, COUNT(*) FROM posts GROUP BY user_id")
            .is_ok()
    );
}

#[test]
fn edge_having_parse() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT user_id, COUNT(*) FROM posts GROUP BY user_id HAVING COUNT(*) > 3")
            .is_ok()
    );
}

#[test]
fn edge_order_by_limit() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT id FROM users ORDER BY id DESC LIMIT 10")
            .is_ok()
    );
}

#[test]
fn edge_union() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check("SELECT id FROM users UNION SELECT id FROM posts")
            .is_ok()
    );
}

#[test]
fn edge_cte_with_clause() {
    let plugin = get_plugin("sql").unwrap();
    assert!(
        plugin
            .parse_check(
                "WITH active_users AS (SELECT id FROM users WHERE active = true) \
                 SELECT id FROM active_users"
            )
            .is_ok()
    );
}

// ============================================================================
// Plugin system tests
// ============================================================================

#[test]
fn plugin_sql_name() {
    let plugin = get_plugin("sql").unwrap();
    assert_eq!(plugin.name(), "sql");
}

#[test]
fn plugin_postgresql_name() {
    let plugin = get_plugin("postgresql").unwrap();
    assert_eq!(plugin.name(), "postgresql");
}

#[test]
fn plugin_mysql_name() {
    let plugin = get_plugin("mysql").unwrap();
    assert_eq!(plugin.name(), "mysql");
}

#[test]
fn plugin_sqlite_name() {
    let plugin = get_plugin("sqlite").unwrap();
    assert_eq!(plugin.name(), "sqlite");
}

#[test]
fn plugin_unsupported_language() {
    let result = get_plugin("brainfuck");
    assert!(result.is_err(), "Unsupported language should error");
}

// ============================================================================
// Schema serialisation round-trip
// ============================================================================

#[test]
fn schema_json_round_trip() {
    let schema = test_schema();
    let json = serde_json::to_string_pretty(&schema).unwrap();
    let deserialized: Schema = serde_json::from_str(&json).unwrap();
    assert_eq!(deserialized.tables.len(), schema.tables.len());
    assert_eq!(deserialized.tables[0].name, "users");
    assert_eq!(deserialized.tables[0].columns.len(), 6);
    assert!(deserialized.tables[0].columns[2].nullable); // email
}

// ============================================================================
// Manifest parsing
// ============================================================================

#[test]
fn manifest_parse_minimal() {
    use typedqliser::Manifest;
    let toml_str = r#"
[typedql]
name = "test-project"
language = "sql"

[database]
target-db = "postgresql"

[paths]
queries = ["src/**/*.sql"]
embedding = "standalone"
"#;
    let manifest: Manifest = toml::from_str(toml_str).unwrap();
    assert_eq!(manifest.typedql.name, "test-project");
    assert_eq!(manifest.typedql.language, "sql");
    assert_eq!(manifest.database.target_db, "postgresql");
    assert_eq!(manifest.typedql.level, 6); // default
    assert_eq!(manifest.levels.enforce, vec![1, 2, 3, 4, 5, 6]); // default
}

#[test]
fn manifest_parse_custom_levels() {
    use typedqliser::Manifest;
    let toml_str = r#"
[typedql]
name = "strict-project"
language = "sql"
level = 10

[database]
target-db = "postgresql"

[paths]
queries = ["queries/**/*.sql"]
embedding = "standalone"

[levels]
enforce = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
warn = []
skip = []
"#;
    let manifest: Manifest = toml::from_str(toml_str).unwrap();
    assert_eq!(manifest.typedql.level, 10);
    assert_eq!(manifest.levels.enforce, vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    assert!(manifest.levels.warn.is_empty());
    assert!(manifest.levels.skip.is_empty());
}

#[test]
fn manifest_parse_with_schema_file() {
    use typedqliser::Manifest;
    let toml_str = r#"
[typedql]
name = "file-schema"
language = "sql"
schema-source = "file"

[database]
target-db = "postgresql"
schema-file = "schema.json"

[paths]
queries = ["src/**/*.sql"]
embedding = "standalone"
"#;
    let manifest: Manifest = toml::from_str(toml_str).unwrap();
    assert_eq!(manifest.typedql.schema_source, "file");
    assert_eq!(
        manifest.database.schema_file.as_deref(),
        Some("schema.json")
    );
}
