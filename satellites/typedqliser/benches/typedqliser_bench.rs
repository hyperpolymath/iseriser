// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//! Criterion benchmarks for TypedQLiser — query parsing and transformation.
//!
//! Covers:
//!   - `parse_check` throughput for small, medium, and large queries.
//!   - Full L1→L4 transformation pipeline throughput.
//!   - `schema_check` and `type_check` overhead per query size.
//!   - Plugin creation cost.

use criterion::{BenchmarkId, Criterion, Throughput, black_box, criterion_group, criterion_main};
use typedqliser::plugins::{ColumnDef, Schema, TableDef, get_plugin};

// ---------------------------------------------------------------------------
// Query corpus
// ---------------------------------------------------------------------------

/// Small query (~30 bytes) — a minimal SELECT.
const SMALL_QUERY: &str = "SELECT id FROM accounts WHERE id = 1";

/// Medium query (~180 bytes) — a two-table JOIN with a WHERE clause.
const MEDIUM_QUERY: &str = "SELECT accounts.id, accounts.username, transactions.amount \
     FROM accounts \
     INNER JOIN transactions ON accounts.id = transactions.account_id \
     WHERE accounts.id > 10 AND transactions.amount > 0 \
     ORDER BY transactions.amount DESC \
     LIMIT 50";

/// Large query (~400 bytes) — a CTE + subquery + GROUP BY.
const LARGE_QUERY: &str = "WITH high_value AS ( \
       SELECT account_id, SUM(amount) AS total \
       FROM transactions \
       WHERE amount > 100 \
       GROUP BY account_id \
       HAVING SUM(amount) > 1000 \
     ) \
     SELECT a.id, a.username, hv.total \
     FROM accounts a \
     INNER JOIN high_value hv ON a.id = hv.account_id \
     WHERE a.verified = true \
       AND a.id IN ( \
           SELECT DISTINCT account_id FROM transactions WHERE amount > 0 \
       ) \
     ORDER BY hv.total DESC \
     LIMIT 20";

// ---------------------------------------------------------------------------
// Schema fixture (built once per benchmark group)
// ---------------------------------------------------------------------------

fn bench_schema() -> Schema {
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
// Benchmark 1: parse_check throughput by query size
// ---------------------------------------------------------------------------

/// Measures the L1 (`parse_check`) cost for small, medium, and large queries.
/// Throughput is reported in bytes per second.
fn bench_parse_check_throughput(c: &mut Criterion) {
    let plugin = get_plugin("sql").expect("sql plugin must load");
    let mut group = c.benchmark_group("parse_check/throughput");

    for (label, query) in [
        ("small", SMALL_QUERY),
        ("medium", MEDIUM_QUERY),
        ("large", LARGE_QUERY),
    ] {
        group.throughput(Throughput::Bytes(query.len() as u64));
        group.bench_with_input(BenchmarkId::new(label, query.len()), query, |b, q| {
            b.iter(|| plugin.parse_check(black_box(q)))
        });
    }

    group.finish();
}

// ---------------------------------------------------------------------------
// Benchmark 2: schema_check throughput by query size
// ---------------------------------------------------------------------------

/// Measures the L2 (`schema_check`) cost, which includes L1 parsing plus
/// table/column lookup against the schema.
fn bench_schema_check_throughput(c: &mut Criterion) {
    let plugin = get_plugin("sql").expect("sql plugin must load");
    let schema = bench_schema();
    let mut group = c.benchmark_group("schema_check/throughput");

    for (label, query) in [
        ("small", SMALL_QUERY),
        ("medium", MEDIUM_QUERY),
        ("large", LARGE_QUERY),
    ] {
        group.throughput(Throughput::Bytes(query.len() as u64));
        group.bench_with_input(BenchmarkId::new(label, query.len()), query, |b, q| {
            b.iter(|| plugin.schema_check(black_box(q), &schema))
        });
    }

    group.finish();
}

// ---------------------------------------------------------------------------
// Benchmark 3: Full L1→L4 pipeline throughput
// ---------------------------------------------------------------------------

/// Runs all four check levels sequentially on the same query, matching the
/// pattern used by the `check` public API.  This is the most realistic
/// single-query benchmark.
fn bench_full_pipeline(c: &mut Criterion) {
    let plugin = get_plugin("sql").expect("sql plugin must load");
    let schema = bench_schema();
    let mut group = c.benchmark_group("full_pipeline");

    for (label, query) in [
        ("small", SMALL_QUERY),
        ("medium", MEDIUM_QUERY),
        ("large", LARGE_QUERY),
    ] {
        group.bench_with_input(BenchmarkId::new(label, query.len()), query, |b, q| {
            b.iter(|| {
                let _ = plugin.parse_check(black_box(q));
                let _ = plugin.schema_check(black_box(q), &schema);
                let _ = plugin.type_check(black_box(q), &schema);
                let _ = plugin.null_check(black_box(q), &schema);
            })
        });
    }

    group.finish();
}

// ---------------------------------------------------------------------------
// Benchmark 4: Plugin creation overhead
// ---------------------------------------------------------------------------

/// Measures the cost of calling `get_plugin("sql")`.  Callers that create a
/// plugin per-request will pay this cost on every call.
fn bench_plugin_creation(c: &mut Criterion) {
    c.bench_function("plugin_creation/sql", |b| {
        b.iter(|| black_box(get_plugin("sql").unwrap()))
    });
}

// ---------------------------------------------------------------------------
// Benchmark 5: Error path — parse of invalid query
// ---------------------------------------------------------------------------

/// Measures how quickly the L1 checker rejects syntactically invalid input.
/// A fast error path is important for interactive tooling.
fn bench_error_path(c: &mut Criterion) {
    let plugin = get_plugin("sql").expect("sql plugin must load");
    let invalid = "NOT SQL AT ALL @@@ !!! ??? ###";
    c.bench_function("parse_check/error_path", |b| {
        b.iter(|| plugin.parse_check(black_box(invalid)))
    });
}

// ---------------------------------------------------------------------------
// Criterion wiring
// ---------------------------------------------------------------------------

criterion_group!(
    benches,
    bench_parse_check_throughput,
    bench_schema_check_throughput,
    bench_full_pipeline,
    bench_plugin_creation,
    bench_error_path,
);
criterion_main!(benches);
