// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! End-to-end tests for TypedQLiser.
//!
//! Each test follows the canonical pipeline:
//!   parse query string  →  transform (type/null/schema checks)  →  validate output
//!
//! Tests exercise all four implemented levels (L1–L4) and the pipeline's
//! ability to report failures at the correct level.

use typedqliser::plugins::{ColumnDef, Schema, TableDef, get_plugin};

// ---------------------------------------------------------------------------
// Shared schema fixture
// ---------------------------------------------------------------------------

/// Minimal schema used across all E2E tests.
fn schema() -> Schema {
    Schema {
        tables: vec![
            TableDef {
                name: "accounts".to_string(),
                columns: vec![
                    ColumnDef {
                        name: "id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: true,
                    },
                    ColumnDef {
                        name: "username".to_string(),
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
                        name: "balance".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "verified".to_string(),
                        col_type: "boolean".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                ],
            },
            TableDef {
                name: "transactions".to_string(),
                columns: vec![
                    ColumnDef {
                        name: "id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: true,
                    },
                    ColumnDef {
                        name: "account_id".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "amount".to_string(),
                        col_type: "integer".to_string(),
                        nullable: false,
                        primary_key: false,
                    },
                    ColumnDef {
                        name: "note".to_string(),
                        col_type: "text".to_string(),
                        nullable: true,
                        primary_key: false,
                    },
                ],
            },
        ],
    }
}

// ---------------------------------------------------------------------------
// E2E 1: Happy-path query passes all four levels
// ---------------------------------------------------------------------------

/// A well-formed query against known non-nullable columns must pass L1→L4
/// without any issues.
#[test]
fn e2e_clean_query_passes_all_levels() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT id, username FROM accounts WHERE id = 1";

    assert!(plugin.parse_check(query).is_ok(), "E2E L1 failed");
    let l2 = plugin.schema_check(query, &s).unwrap();
    assert!(l2.is_empty(), "E2E L2 failed: {:?}", l2);
    let l3 = plugin.type_check(query, &s).unwrap();
    assert!(l3.is_empty(), "E2E L3 failed: {:?}", l3);
    let l4 = plugin.null_check(query, &s).unwrap();
    assert!(l4.is_empty(), "E2E L4 failed: {:?}", l4);
}

// ---------------------------------------------------------------------------
// E2E 2: Query fails at L1 — completely invalid syntax
// ---------------------------------------------------------------------------

/// Syntactically broken input must fail immediately at L1 before any
/// downstream level is consulted.
#[test]
fn e2e_invalid_syntax_fails_at_l1() {
    let plugin = get_plugin("sql").unwrap();
    let query = "SELCET ??? FROM !!!";
    assert!(
        plugin.parse_check(query).is_err(),
        "E2E: gibberish must fail L1"
    );
}

// ---------------------------------------------------------------------------
// E2E 3: Query passes L1 but fails at L2 — unknown table
// ---------------------------------------------------------------------------

/// A syntactically valid query against a non-existent table must pass L1
/// and produce at least one issue at L2.
#[test]
fn e2e_unknown_table_fails_at_l2() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT id FROM ghost_table";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l2 = plugin.schema_check(query, &s).unwrap();
    assert!(!l2.is_empty(), "E2E: unknown table must produce L2 issues");
    assert!(
        l2.iter().any(|i| i.message.contains("ghost_table")),
        "L2 issue must mention the missing table name"
    );
}

// ---------------------------------------------------------------------------
// E2E 4: Query passes L1–L2 but fails at L3 — type mismatch
// ---------------------------------------------------------------------------

/// Comparing an integer column to a string literal must pass L1 and L2 but
/// produce issues at L3.
#[test]
fn e2e_type_mismatch_fails_at_l3() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT id FROM accounts WHERE id = 'not-an-integer'";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l2 = plugin.schema_check(query, &s).unwrap();
    assert!(l2.is_empty(), "L2 must pass");
    let l3 = plugin.type_check(query, &s).unwrap();
    assert!(!l3.is_empty(), "E2E: id vs string must produce L3 issues");
}

// ---------------------------------------------------------------------------
// E2E 5: Query passes L1–L3 but flags nullable column at L4
// ---------------------------------------------------------------------------

/// Selecting a nullable column (`email`) must pass L1–L3 and produce a
/// null-safety issue at L4.
#[test]
fn e2e_nullable_column_flagged_at_l4() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT email FROM accounts WHERE id = 1";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l2 = plugin.schema_check(query, &s).unwrap();
    assert!(l2.is_empty(), "L2 must pass");
    let l3 = plugin.type_check(query, &s).unwrap();
    assert!(l3.is_empty(), "L3 must pass");
    let l4 = plugin.null_check(query, &s).unwrap();
    assert!(
        l4.iter().any(|i| i.column == "email"),
        "E2E: nullable 'email' must be flagged at L4"
    );
}

// ---------------------------------------------------------------------------
// E2E 6: INSERT into valid table passes L1–L2
// ---------------------------------------------------------------------------

/// An INSERT statement targeting a known table must parse successfully (L1)
/// and produce no schema issues (L2).
#[test]
fn e2e_insert_valid_table_passes_l1_l2() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "INSERT INTO accounts (username, balance) VALUES ('alice', 500)";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l2 = plugin.schema_check(query, &s).unwrap();
    let table_errors: Vec<_> = l2
        .iter()
        .filter(|i| i.message.contains("not found in schema"))
        .collect();
    assert!(
        table_errors.is_empty(),
        "E2E: INSERT into known table must not produce table-not-found L2 issues"
    );
}

// ---------------------------------------------------------------------------
// E2E 7: UPDATE with correct type passes L3
// ---------------------------------------------------------------------------

/// An UPDATE that compares an integer column (`balance`) to an integer literal
/// must produce no type issues at L3.
#[test]
fn e2e_update_integer_vs_integer_passes_l3() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "UPDATE accounts SET balance = 1000 WHERE id = 42";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l3 = plugin.type_check(query, &s).unwrap();
    assert!(
        l3.is_empty(),
        "E2E: integer UPDATE must not produce L3 issues: {:?}",
        l3
    );
}

// ---------------------------------------------------------------------------
// E2E 8: DELETE against unknown table fails L2
// ---------------------------------------------------------------------------

#[test]
fn e2e_delete_unknown_table_fails_l2() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "DELETE FROM archived_accounts WHERE id = 1";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l2 = plugin.schema_check(query, &s).unwrap();
    assert!(
        l2.iter().any(|i| i.message.contains("archived_accounts")),
        "E2E: DELETE against unknown table must be flagged at L2"
    );
}

// ---------------------------------------------------------------------------
// E2E 9: JOIN across two known tables — all levels checked
// ---------------------------------------------------------------------------

/// A JOIN across `accounts` and `transactions` using qualified column names
/// must pass L1 and L2 without issues.
#[test]
fn e2e_join_two_known_tables_passes_l1_l2() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT accounts.id, transactions.amount \
                 FROM accounts \
                 JOIN transactions ON accounts.id = transactions.account_id \
                 WHERE accounts.id = 5";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l2 = plugin.schema_check(query, &s).unwrap();
    assert!(
        l2.is_empty(),
        "E2E: qualified-name join must pass L2. Got: {:?}",
        l2.iter().map(|i| &i.message).collect::<Vec<_>>()
    );
}

// ---------------------------------------------------------------------------
// E2E 10: Boolean column type check
// ---------------------------------------------------------------------------

/// Comparing a boolean column (`verified`) to an integer must produce a type
/// issue at L3.
#[test]
fn e2e_boolean_vs_integer_fails_l3() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT id FROM accounts WHERE verified = 99";

    assert!(plugin.parse_check(query).is_ok(), "L1 must pass");
    let l3 = plugin.type_check(query, &s).unwrap();
    assert!(
        !l3.is_empty(),
        "E2E: boolean vs integer must produce L3 issues"
    );
}

// ---------------------------------------------------------------------------
// E2E 11: CTE (WITH clause) parses at L1
// ---------------------------------------------------------------------------

/// A Common Table Expression must parse successfully at L1.
#[test]
fn e2e_cte_parses_at_l1() {
    let plugin = get_plugin("sql").unwrap();
    let query = "WITH top_accounts AS (SELECT id FROM accounts WHERE balance > 100) \
                 SELECT id FROM top_accounts";
    assert!(
        plugin.parse_check(query).is_ok(),
        "E2E: CTE must parse at L1"
    );
}

// ---------------------------------------------------------------------------
// E2E 12: Nullable column in transactions flagged at L4
// ---------------------------------------------------------------------------

/// The `note` column on `transactions` is nullable; selecting it directly must
/// produce a null-safety issue at L4.
#[test]
fn e2e_nullable_note_flagged_at_l4() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT note FROM transactions WHERE id = 1";

    let l4 = plugin.null_check(query, &s).unwrap();
    assert!(
        l4.iter().any(|i| i.column == "note"),
        "E2E: nullable 'note' column must be flagged at L4"
    );
}
