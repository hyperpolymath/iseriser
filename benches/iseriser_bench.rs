// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// benches/iseriser_bench.rs — Criterion benchmarks for the iseriser crate.
//
// Benchmarks cover the two hottest paths in normal usage:
//
//   1. **Manifest parsing** (`parse_manifest`) — called once per `iseriser`
//      invocation but must be fast enough to support tooling that calls it in
//      a loop across hundreds of repos.
//
//   2. **Manifest validation** (`validate`) — validates the parsed manifest
//      against ABI constraints.
//
//   3. **Repo scanning** (`scan_repo`) — walks a directory tree and emits
//      recommendations; the most I/O-bound hot path.
//
//   4. **Manifest → LanguageModel conversion** (`to_language_model`) — the
//      ABI boundary conversion exercised on every code-generation run.
//
// Run with:
//   cargo bench --bench iseriser_bench

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use iseriser::manifest::{parse_manifest, validate};

// ---------------------------------------------------------------------------
// Manifest TOML fixtures
// ---------------------------------------------------------------------------

/// Minimal well-formed manifest — the common case for quick tooling calls.
const MINIMAL_MANIFEST: &str = r#"
[project]
name = "chapeliser"
version = "0.1.0"

[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task", "locale", "domain", "forall", "sync"]

[output]
repo-name = "chapeliser"
github-org = "hyperpolymath"
description = "Chapel interop -iser for distributed HPC"
"#;

/// A richer manifest with many key-primitives — stress-tests the Vec allocation
/// in `LanguageConfig::key_primitives`.
const RICH_MANIFEST: &str = r#"
[project]
name = "juliaiser"
version = "0.2.0"

[language]
name = "Julia"
paradigm = "functional"
type-system = "gradual"
compilation-target = "jvm"
key-primitives = [
  "macro", "ccall", "llvmcall", "generated", "invokelatest",
  "world-age", "multiple-dispatch", "abstract-type", "parametric",
  "union-type", "where-clause", "tuple-type", "named-tuple",
  "vararg", "keyword-arg", "optional-arg", "type-alias",
  "inner-constructor", "outer-constructor", "conversion",
]

[output]
repo-name = "juliaiser"
github-org = "hyperpolymath"
description = "Julia FFI/ABI interop meta-iser"
"#;

/// A functional-paradigm Gleam manifest — exercises enum variant parsing.
const GLEAM_MANIFEST: &str = r#"
[project]
name = "gleamiser"
version = "0.1.0"

[language]
name = "Gleam"
paradigm = "functional"
type-system = "dependent"
compilation-target = "beam"
key-primitives = ["process", "message", "otp", "actor", "channel", "gleam-stdlib"]

[output]
repo-name = "gleamiser"
github-org = "hyperpolymath"
description = "Gleam interop -iser targeting the BEAM runtime"
"#;

// ---------------------------------------------------------------------------
// Manifest parsing benchmarks
// ---------------------------------------------------------------------------

/// Benchmark parsing a minimal iseriser.toml.
fn bench_parse_minimal(c: &mut Criterion) {
    c.bench_function("parse_manifest/minimal", |b| {
        b.iter(|| {
            let m = parse_manifest(black_box(MINIMAL_MANIFEST))
                .expect("minimal manifest must parse");
            black_box(m);
        });
    });
}

/// Benchmark parsing a manifest with many key-primitives.
fn bench_parse_rich(c: &mut Criterion) {
    c.bench_function("parse_manifest/rich_20_primitives", |b| {
        b.iter(|| {
            let m = parse_manifest(black_box(RICH_MANIFEST))
                .expect("rich manifest must parse");
            black_box(m);
        });
    });
}

/// Benchmark parsing a functional-paradigm manifest.
fn bench_parse_gleam(c: &mut Criterion) {
    c.bench_function("parse_manifest/gleam_beam_target", |b| {
        b.iter(|| {
            let m = parse_manifest(black_box(GLEAM_MANIFEST))
                .expect("gleam manifest must parse");
            black_box(m);
        });
    });
}

// ---------------------------------------------------------------------------
// Manifest validation benchmarks
// ---------------------------------------------------------------------------

/// Benchmark validation of a well-formed manifest.
fn bench_validate_valid(c: &mut Criterion) {
    let manifest = parse_manifest(MINIMAL_MANIFEST).expect("parse");
    c.bench_function("validate/valid_manifest", |b| {
        b.iter(|| {
            let result = validate(black_box(&manifest));
            black_box(result.expect("valid manifest must pass validation"));
        });
    });
}

/// Benchmark validation of a rich manifest (more fields to check).
fn bench_validate_rich(c: &mut Criterion) {
    let manifest = parse_manifest(RICH_MANIFEST).expect("parse rich");
    c.bench_function("validate/rich_20_primitives", |b| {
        b.iter(|| {
            let result = validate(black_box(&manifest));
            black_box(result.expect("rich manifest must pass validation"));
        });
    });
}

// ---------------------------------------------------------------------------
// LanguageModel conversion benchmarks
// ---------------------------------------------------------------------------

/// Benchmark the manifest → LanguageModel ABI conversion.
///
/// Called on every code-generation run at the ABI boundary.
fn bench_to_language_model(c: &mut Criterion) {
    let manifest = parse_manifest(MINIMAL_MANIFEST).expect("parse");
    c.bench_function("to_language_model/chapel", |b| {
        b.iter(|| {
            let model = black_box(&manifest).to_language_model();
            black_box(model);
        });
    });
}

/// Benchmark conversion of a manifest with many primitives.
fn bench_to_language_model_rich(c: &mut Criterion) {
    let manifest = parse_manifest(RICH_MANIFEST).expect("parse rich");
    c.bench_function("to_language_model/julia_20_primitives", |b| {
        b.iter(|| {
            let model = black_box(&manifest).to_language_model();
            black_box(model);
        });
    });
}

// ---------------------------------------------------------------------------
// Repo scanning benchmark
// ---------------------------------------------------------------------------

/// Benchmark scanning the iseriser repo itself.
///
/// Uses the repo root as the scan target — this is a real directory walk
/// with file presence checks, exercising the most I/O-bound path in the crate.
fn bench_scan_repo(c: &mut Criterion) {
    // Use the repo root (two levels up from benches/).
    let repo_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .to_str()
        .expect("valid UTF-8 path")
        .to_owned();

    c.bench_function("scan_repo/iseriser_root", |b| {
        b.iter(|| {
            let recs = iseriser::scan::scan_repo(black_box(&repo_root))
                .expect("scan must succeed");
            black_box(recs);
        });
    });
}

// ---------------------------------------------------------------------------
// Criterion registration
// ---------------------------------------------------------------------------

criterion_group!(
    parse_benches,
    bench_parse_minimal,
    bench_parse_rich,
    bench_parse_gleam,
);

criterion_group!(
    validate_benches,
    bench_validate_valid,
    bench_validate_rich,
);

criterion_group!(
    abi_benches,
    bench_to_language_model,
    bench_to_language_model_rich,
);

criterion_group!(scan_benches, bench_scan_repo);

criterion_main!(parse_benches, validate_benches, abi_benches, scan_benches);
