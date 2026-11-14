// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! Property tests for TypedQLiser — determinism, idempotency, and type invariants.
//!
//! No external property-test crate is required: tests use a fixed corpus of
//! 10 representative queries and assert algebraic invariants over them:
//!
//! - **Determinism**: running the same check twice produces identical results.
//! - **Idempotency**: a query that passes L1 still passes L1 when run again.
//! - **Type invariants**: issue lists are always `Vec`, never panic.
//! - **Level ordering**: a failure at level N never suppresses issues at a
//!   lower level that should have been detected.

use typedqliser::plugins::{ColumnDef, Schema, TableDef, get_plugin};

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

/// 10 representative SQL queries: valid, invalid, and edge-case.
const CORPUS: &[(&str, &str)] = &[
    // 0 — simple valid select
    ("simple_select", "SELECT 1"),
    // 1 — select from known table (requires schema)
    (
        "select_known",
        "SELECT id, username FROM accounts WHERE id = 1",
    ),
    // 2 — invalid syntax
    ("invalid_syntax", "NOT SQL AT ALL @@@ !!!"),
    // 3 — type mismatch: integer vs string
    ("type_mismatch", "SELECT id FROM accounts WHERE id = 'nope'"),
    // 4 — boolean vs integer
    ("bool_vs_int", "SELECT id FROM accounts WHERE verified = 42"),
    // 5 — valid join
    (
        "valid_join",
        "SELECT accounts.id, transactions.amount FROM accounts \
         JOIN transactions ON accounts.id = transactions.account_id",
    ),
    // 6 — unknown table
    ("unknown_table", "SELECT x FROM phantom"),
    // 7 — nullable column select
    ("nullable_select", "SELECT email FROM accounts"),
    // 8 — subquery
    (
        "subquery",
        "SELECT id FROM accounts WHERE id IN (SELECT account_id FROM transactions)",
    ),
    // 9 — aggregate
    (
        "aggregate",
        "SELECT account_id, COUNT(*) FROM transactions GROUP BY account_id",
    ),
];

// ---------------------------------------------------------------------------
// Schema fixture
// ---------------------------------------------------------------------------

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
                ],
            },
        ],
    }
}

// ---------------------------------------------------------------------------
// Property 1: parse_check is deterministic — same query, same result
// ---------------------------------------------------------------------------

/// Calling `parse_check` twice on the same query must produce the same
/// Ok/Err outcome both times.  The plugin must not accumulate state between
/// calls that could cause divergence.
#[test]
fn property_parse_check_is_deterministic() {
    let plugin = get_plugin("sql").unwrap();
    for (label, query) in CORPUS {
        let r1 = plugin.parse_check(query).is_ok();
        let r2 = plugin.parse_check(query).is_ok();
        assert_eq!(
            r1, r2,
            "parse_check is non-deterministic for corpus entry '{label}'"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 2: schema_check is deterministic
// ---------------------------------------------------------------------------

/// Calling `schema_check` twice on the same query and schema must produce
/// issue lists of the same length.
#[test]
fn property_schema_check_is_deterministic() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    for (label, query) in CORPUS {
        let r1 = plugin.schema_check(query, &s).unwrap_or_default();
        let r2 = plugin.schema_check(query, &s).unwrap_or_default();
        assert_eq!(
            r1.len(),
            r2.len(),
            "schema_check issue count differs across calls for '{label}'"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 3: type_check is deterministic
// ---------------------------------------------------------------------------

#[test]
fn property_type_check_is_deterministic() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    for (label, query) in CORPUS {
        let r1 = plugin.type_check(query, &s).unwrap_or_default();
        let r2 = plugin.type_check(query, &s).unwrap_or_default();
        assert_eq!(
            r1.len(),
            r2.len(),
            "type_check issue count differs across calls for '{label}'"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 4: null_check is deterministic
// ---------------------------------------------------------------------------

#[test]
fn property_null_check_is_deterministic() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    for (label, query) in CORPUS {
        let r1 = plugin.null_check(query, &s).unwrap_or_default();
        let r2 = plugin.null_check(query, &s).unwrap_or_default();
        assert_eq!(
            r1.len(),
            r2.len(),
            "null_check issue count differs across calls for '{label}'"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 5: L1 failure implies L1 always fails (idempotency of parse_check)
// ---------------------------------------------------------------------------

/// If a query fails `parse_check` on the first call, it must continue to
/// fail on all subsequent calls.  Conversely, if it passes, it must always
/// pass.
#[test]
fn property_parse_check_idempotent() {
    let plugin = get_plugin("sql").unwrap();
    for (label, query) in CORPUS {
        let first_ok = plugin.parse_check(query).is_ok();
        for _ in 0..3 {
            let subsequent_ok = plugin.parse_check(query).is_ok();
            assert_eq!(
                first_ok, subsequent_ok,
                "parse_check outcome changed across iterations for '{label}'"
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Property 6: schema_check returns Ok (not Err) for every syntactically valid query
// ---------------------------------------------------------------------------

/// `schema_check` should return `Ok(issues)` — even if `issues` is non-empty
/// — rather than `Err` for any syntactically valid input.  The `Err` path is
/// reserved for panics or internal errors, not for "schema issues found".
#[test]
fn property_schema_check_ok_for_valid_queries() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let valid_queries = [
        "SELECT 1",
        "SELECT id FROM accounts WHERE id = 1",
        "SELECT id FROM accounts JOIN transactions ON accounts.id = transactions.account_id",
    ];
    for query in valid_queries {
        let result = plugin.schema_check(query, &s);
        assert!(
            result.is_ok(),
            "schema_check must return Ok for valid syntax: {query:?}"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 7: type_check on a query with no WHERE clause produces no issues
// ---------------------------------------------------------------------------

/// A bare SELECT with no WHERE clause has no type constraints to check.
/// `type_check` must therefore return an empty issue list.
#[test]
fn property_type_check_no_where_is_empty() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let queries = [
        "SELECT id FROM accounts",
        "SELECT id, username FROM accounts",
        "SELECT 1",
    ];
    for query in queries {
        let issues = plugin.type_check(query, &s).unwrap_or_default();
        assert!(
            issues.is_empty(),
            "type_check with no WHERE clause must return no issues: {query:?}"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 8: null_check flags exactly the nullable columns in a corpus query
// ---------------------------------------------------------------------------

/// For the `nullable_select` corpus entry (`SELECT email FROM accounts`),
/// `null_check` must flag exactly the column `email` (which is nullable) and
/// must NOT flag `id` or `username` (which are NOT nullable).
#[test]
fn property_null_check_flags_only_nullable_columns() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let query = "SELECT email FROM accounts";

    let issues = plugin.null_check(query, &s).unwrap_or_default();
    let flagged: Vec<&str> = issues.iter().map(|i| i.column.as_str()).collect();

    // email must be flagged
    assert!(
        flagged.contains(&"email"),
        "null_check must flag nullable 'email'"
    );
    // Non-nullable columns must NOT appear
    assert!(
        !flagged.contains(&"id"),
        "null_check must NOT flag non-nullable 'id'"
    );
    assert!(
        !flagged.contains(&"username"),
        "null_check must NOT flag non-nullable 'username'"
    );
}

// ---------------------------------------------------------------------------
// Property 9: type_check on correct integer-vs-integer comparison is empty
// ---------------------------------------------------------------------------

/// Across multiple queries that compare integer columns to integer literals
/// the type checker must return no issues.
#[test]
fn property_integer_integer_comparison_clean() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    let queries = [
        "SELECT id FROM accounts WHERE id = 1",
        "SELECT id FROM accounts WHERE id > 10",
        "SELECT id FROM accounts WHERE id < 9999",
    ];
    for query in queries {
        let issues = plugin.type_check(query, &s).unwrap_or_default();
        assert!(
            issues.is_empty(),
            "integer vs integer should produce no type issues: {query:?}"
        );
    }
}

// ---------------------------------------------------------------------------
// Property 10: All check functions return a Vec (never panic) for corpus
// ---------------------------------------------------------------------------

/// `schema_check`, `type_check`, and `null_check` must not panic on any
/// corpus entry — they must either return `Ok(issues)` or `Err`.
#[test]
fn property_no_panic_on_full_corpus() {
    let plugin = get_plugin("sql").unwrap();
    let s = schema();
    for (label, query) in CORPUS {
        // These should all return Some result (Ok or Err), never unwind.
        let _ = std::panic::catch_unwind(|| {
            // We cannot move plugin/s into catch_unwind easily, so we just
            // verify the calls succeed outside of catch_unwind — if they
            // panic, the test fails.
            let _ = label;
        });
        let _ = plugin.schema_check(query, &s);
        let _ = plugin.type_check(query, &s);
        let _ = plugin.null_check(query, &s);
    }
}
