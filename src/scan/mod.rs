// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// scan — Repository scanner that recommends applicable -iser tools.
//
// Walks a repository directory, detects signals in project files and source
// code, and recommends which isers from the hyperpolymath family should be
// applied to the repo.  Output is a sorted table (high → medium → low
// confidence) or JSON when `--json` is requested.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

/// A single recommendation produced by the scanner.
#[derive(Debug, Serialize, Deserialize)]
pub struct Recommendation {
    /// Short name of the recommended -iser tool (e.g. "k9iser").
    pub iser: String,
    /// Confidence level: "high", "medium", or "low".
    pub confidence: &'static str,
    /// Human-readable reason why this iser is recommended.
    pub reason: String,
    /// Whether the iser appears to have already been applied to the repo.
    pub already_applied: bool,
}

// ─── Public API ──────────────────────────────────────────────────────────────

/// Walk `path` and return a sorted list of iser recommendations.
///
/// The list is sorted high → medium → low confidence.  Already-applied isers
/// are still included so the caller can display their status.
pub fn scan_repo(path: &str) -> Result<Vec<Recommendation>> {
    let root = Path::new(path);
    let mut recs: Vec<Recommendation> = Vec::new();

    check_k9iser(root, &mut recs);
    check_eclexiaiser(root, &mut recs);
    check_wokelangiser(root, &mut recs);
    check_alloyiser(root, &mut recs);
    check_tlaiser(root, &mut recs);
    check_idrisiser(root, &mut recs);
    check_typedqliser(root, &mut recs);
    check_chapeliser(root, &mut recs);
    check_ephapaxiser(root, &mut recs);
    check_verisimiser(root, &mut recs);
    check_otpiser(root, &mut recs);
    check_ponyiser(root, &mut recs);
    check_dafniser(root, &mut recs);
    check_futharkiser(root, &mut recs);
    check_lustreiser(root, &mut recs);

    // Sort: high first, then medium, then low.
    recs.sort_by_key(|r| match r.confidence {
        "high" => 0u8,
        "medium" => 1,
        _ => 2,
    });

    Ok(recs)
}

/// Print recommendations as a plain-text table to stdout.
pub fn print_table(recs: &[Recommendation]) {
    if recs.is_empty() {
        println!("No iser recommendations — this repo is fully covered.");
        return;
    }
    println!(
        "{:<22} {:<10} {:<9} {}",
        "ISER", "CONFIDENCE", "APPLIED", "REASON"
    );
    println!("{}", "-".repeat(90));
    for r in recs {
        let applied = if r.already_applied { "yes" } else { "no" };
        println!(
            "{:<22} {:<10} {:<9} {}",
            r.iser, r.confidence, applied, r.reason
        );
    }
}

// ─── File/content helpers ────────────────────────────────────────────────────

/// Returns true if `root/<name>` exists as a file.
fn has_file(root: &Path, name: &str) -> bool {
    root.join(name).is_file()
}

/// Returns true if `root/<name>` exists as a directory.
fn has_dir(root: &Path, name: &str) -> bool {
    root.join(name).is_dir()
}

/// Returns true if any source file under `root/src/` (depth ≤ 4) contains
/// `pattern` as a literal substring.
///
/// Scans files with extensions: `.rs`, `.ex`, `.exs`, `.res`, `.ts`, `.js`,
/// `.zig`, `.idr`, `.gleam`, `.elm`.
fn src_contains(root: &Path, pattern: &str) -> bool {
    path_contains(root, "src", pattern)
}

/// Like `src_contains` but starts from an arbitrary subdirectory of `root`.
fn path_contains(root: &Path, subdir: &str, pattern: &str) -> bool {
    let base = root.join(subdir);
    if !base.exists() {
        return false;
    }
    walkdir::WalkDir::new(&base)
        .max_depth(4)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path().extension().map_or(false, |ext| {
                matches!(
                    ext.to_str(),
                    Some("rs" | "ex" | "exs" | "res" | "ts" | "js" | "zig" | "idr" | "gleam" | "elm")
                )
            })
        })
        .any(|e| {
            std::fs::read_to_string(e.path())
                .map(|s| s.contains(pattern))
                .unwrap_or(false)
        })
}

/// Returns true if `root` contains at least one file matching `pattern` in its
/// name (case-sensitive substring), searching up to 3 directory levels deep.
fn has_file_named(root: &Path, pattern: &str) -> bool {
    walkdir::WalkDir::new(root)
        .max_depth(3)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .any(|e| {
            e.file_name()
                .to_str()
                .map(|n| n.contains(pattern))
                .unwrap_or(false)
        })
}

/// Returns true if the -iser appears already applied.
///
/// Convention: presence of `<iser>.toml` or `.<iser>/` directory signals
/// that the tool has already been run on this repo.
fn is_applied(root: &Path, iser: &str) -> bool {
    has_file(root, &format!("{}.toml", iser)) || has_dir(root, &format!(".{}", iser))
}

// ─── Per-iser checks ─────────────────────────────────────────────────────────

/// k9iser — quality-gate pipeline for repos that have a build manifest + Justfile
/// but no k9iser configuration yet.
fn check_k9iser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_build = has_file(root, "Cargo.toml")
        || has_file(root, "mix.exs")
        || has_file(root, "deno.json")
        || has_file(root, "deno.jsonc");
    let has_just = has_file(root, "justfile") || has_file(root, "Justfile");

    if has_build && has_just {
        recs.push(Recommendation {
            iser: "k9iser".into(),
            confidence: "high",
            reason: "Build manifest + Justfile present but no k9iser.toml quality-gate config."
                .into(),
            already_applied: is_applied(root, "k9iser"),
        });
    }
}

/// eclexiaiser — container security layer for repos that have a Containerfile
/// but no eclexiaiser configuration.
fn check_eclexiaiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_container = has_file(root, "Containerfile")
        || has_file_named(root, "Containerfile")
        || has_file(root, "Dockerfile");

    if has_container {
        recs.push(Recommendation {
            iser: "eclexiaiser".into(),
            confidence: "high",
            reason: "Containerfile found — eclexiaiser adds provenance and policy checking."
                .into(),
            already_applied: is_applied(root, "eclexiaiser"),
        });
    }
}

/// wokelangiser — UI/i18n accessibility layer for repos with ReScript UI
/// components, PixiJS, React patterns, or i18n/locale files.
fn check_wokelangiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_res = walkdir::WalkDir::new(root)
        .max_depth(4)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .any(|e| {
            e.path()
                .extension()
                .and_then(|x| x.to_str())
                .map(|x| x == "res")
                .unwrap_or(false)
        });

    let has_i18n = has_dir(root, "locales")
        || has_dir(root, "i18n")
        || has_dir(root, "translations")
        || has_file_named(root, "locale")
        || src_contains(root, "Intl.")
        || src_contains(root, "i18next")
        || src_contains(root, "gettext");

    let has_ui_patterns = src_contains(root, "PixiJS")
        || src_contains(root, "React.")
        || src_contains(root, "ReactDOM")
        || src_contains(root, "useState")
        || src_contains(root, "render(");

    if has_res || has_i18n || has_ui_patterns {
        let reason = if has_i18n {
            "i18n/locale files or patterns found — wokelangiser ensures accessibility coverage."
        } else if has_res {
            "ReScript UI components found — wokelangiser adds accessibility linting."
        } else {
            "UI component patterns found — wokelangiser adds accessibility coverage."
        };
        recs.push(Recommendation {
            iser: "wokelangiser".into(),
            confidence: if has_res && has_i18n { "high" } else { "medium" },
            reason: reason.into(),
            already_applied: is_applied(root, "wokelangiser"),
        });
    }
}

/// alloyiser — model checking / invariant verification for repos that have
/// API specs (OpenAPI, GraphQL, Protobuf) or complex invariants in comments.
fn check_alloyiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_openapi = has_file(root, "openapi.yaml")
        || has_file(root, "openapi.yml")
        || has_file(root, "openapi.json")
        || has_file_named(root, "openapi")
        || has_file_named(root, ".proto");

    let has_graphql = has_file(root, "schema.graphql")
        || has_file_named(root, ".graphql")
        || has_file_named(root, ".gql");

    let has_complex_invariants = src_contains(root, "// invariant:")
        || src_contains(root, "# invariant:")
        || src_contains(root, "INVARIANT:")
        || src_contains(root, "// precondition:")
        || src_contains(root, "// postcondition:");

    if has_openapi || has_graphql {
        recs.push(Recommendation {
            iser: "alloyiser".into(),
            confidence: "high",
            reason: "API schema files (OpenAPI/GraphQL/Protobuf) found — alloyiser adds model checking.".into(),
            already_applied: is_applied(root, "alloyiser"),
        });
    } else if has_complex_invariants {
        recs.push(Recommendation {
            iser: "alloyiser".into(),
            confidence: "medium",
            reason: "Complex invariants described in source comments — alloyiser can formalise them.".into(),
            already_applied: is_applied(root, "alloyiser"),
        });
    }
}

/// tlaiser — TLA⁺ temporal-logic specifications for repos with state machine
/// patterns or concurrent protocol code.
fn check_tlaiser(root: &Path, recs: &mut Vec<Recommendation>) {
    // State machine signals.
    let has_state_enum = src_contains(root, "State {")
        || src_contains(root, "State::")
        || src_contains(root, "FSM")
        || src_contains(root, "StateMachine")
        || src_contains(root, "state_machine");

    // Concurrency / protocol signals.
    let has_concurrency = src_contains(root, "Mutex")
        || src_contains(root, "RwLock")
        || src_contains(root, "channel(")
        || src_contains(root, "mpsc::")
        || src_contains(root, "tokio::sync")
        || src_contains(root, "async_channel")
        || src_contains(root, "GenServer")
        || src_contains(root, "receive do");

    if has_state_enum && has_concurrency {
        recs.push(Recommendation {
            iser: "tlaiser".into(),
            confidence: "high",
            reason: "State machine patterns + concurrent protocol code — tlaiser adds TLA⁺ specs.".into(),
            already_applied: is_applied(root, "tlaiser"),
        });
    } else if has_state_enum {
        recs.push(Recommendation {
            iser: "tlaiser".into(),
            confidence: "medium",
            reason: "State machine / FSM patterns found — tlaiser can specify temporal behaviour.".into(),
            already_applied: is_applied(root, "tlaiser"),
        });
    } else if has_concurrency {
        recs.push(Recommendation {
            iser: "tlaiser".into(),
            confidence: "medium",
            reason: "Concurrent protocol code (channels/locks/message passing) found — tlaiser adds safety specs.".into(),
            already_applied: is_applied(root, "tlaiser"),
        });
    }
}

/// idrisiser — Idris2 proof wrapper generation for repos with safety-critical
/// parser functions or public APIs that lack proof wrappers.
fn check_idrisiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_parser = src_contains(root, "parse(")
        || src_contains(root, "parse_")
        || src_contains(root, "nom::")
        || src_contains(root, "pest::")
        || src_contains(root, "lalrpop");

    // Public API in Rust: `pub fn` in src without an existing ABI dir.
    let has_public_api = src_contains(root, "pub fn") || src_contains(root, "pub async fn");
    let has_abi_dir = has_dir(root, "src/abi") || has_dir(root, "src/interface/abi");

    if has_parser && !has_abi_dir {
        recs.push(Recommendation {
            iser: "idrisiser".into(),
            confidence: "high",
            reason: "Parser functions present without Idris2 ABI proof wrappers — idrisiser can generate them.".into(),
            already_applied: is_applied(root, "idrisiser"),
        });
    } else if has_public_api && !has_abi_dir {
        recs.push(Recommendation {
            iser: "idrisiser".into(),
            confidence: "medium",
            reason: "Public API functions found with no formal proof wrappers (no src/abi/).".into(),
            already_applied: is_applied(root, "idrisiser"),
        });
    }
}

/// typedqliser — typed query-language layer for repos with raw SQL, query
/// builders, or database query patterns.
fn check_typedqliser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_raw_sql = src_contains(root, "query(\"SELECT")
        || src_contains(root, "query(\"INSERT")
        || src_contains(root, "query(\"UPDATE")
        || src_contains(root, "query(\"DELETE")
        || src_contains(root, "execute(\"")
        || src_contains(root, "raw_query")
        || src_contains(root, "sqlx::query!")
        || src_contains(root, "Repo.query")
        || src_contains(root, "Ecto.Query");

    let has_query_builder = src_contains(root, "QueryBuilder")
        || src_contains(root, "diesel::")
        || src_contains(root, "sea_query")
        || src_contains(root, "knex(");

    if has_raw_sql {
        recs.push(Recommendation {
            iser: "typedqliser".into(),
            confidence: "high",
            reason: "Raw SQL strings found in source — typedqliser adds compile-time type safety.".into(),
            already_applied: is_applied(root, "typedqliser"),
        });
    } else if has_query_builder {
        recs.push(Recommendation {
            iser: "typedqliser".into(),
            confidence: "medium",
            reason: "Query builder patterns found — typedqliser can strengthen type guarantees.".into(),
            already_applied: is_applied(root, "typedqliser"),
        });
    }
}

/// chapeliser — distributed/parallel compute layer for repos with rayon,
/// parallel iterators, or Chapel-style batch processing patterns.
fn check_chapeliser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_rayon = src_contains(root, "rayon::")
        || src_contains(root, "par_iter()")
        || src_contains(root, "par_chunks")
        || src_contains(root, "into_par_iter");

    let has_chapel = has_file_named(root, ".chpl")
        || src_contains(root, "forall ")
        || src_contains(root, "coforall ");

    let has_parallel = src_contains(root, "thread::spawn")
        || src_contains(root, "tokio::spawn")
        || src_contains(root, "Task.async");

    if has_rayon || has_chapel {
        recs.push(Recommendation {
            iser: "chapeliser".into(),
            confidence: "high",
            reason: "Parallel/distributed compute patterns (rayon/Chapel) found — chapeliser optimises them.".into(),
            already_applied: is_applied(root, "chapeliser"),
        });
    } else if has_parallel {
        recs.push(Recommendation {
            iser: "chapeliser".into(),
            confidence: "medium",
            reason: "Concurrent task spawning found — chapeliser can add structured parallelism.".into(),
            already_applied: is_applied(root, "chapeliser"),
        });
    }
}

/// ephapaxiser — linear-type resource safety layer for repos with unchecked
/// resource handles (File, Socket, DB connections).
fn check_ephapaxiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_file_handles = src_contains(root, "File::open")
        || src_contains(root, "File::create")
        || src_contains(root, "fs::File")
        || src_contains(root, "BufWriter::new")
        || src_contains(root, "BufReader::new");

    let has_socket = src_contains(root, "TcpStream")
        || src_contains(root, "UdpSocket")
        || src_contains(root, "TcpListener")
        || src_contains(root, "UnixStream");

    let has_db_conn = src_contains(root, "PgConnection")
        || src_contains(root, "SqliteConnection")
        || src_contains(root, "MysqlConnection")
        || src_contains(root, "Pool::new")
        || src_contains(root, "get_connection");

    // Only recommend if there's no linear typing already in use.
    let has_linear_types = has_dir(root, "src/abi")
        || src_contains(root, "Linear ")
        || src_contains(root, "linear_types");

    if (has_file_handles || has_socket || has_db_conn) && !has_linear_types {
        let resource_kind = if has_db_conn {
            "database connection handles"
        } else if has_socket {
            "socket handles"
        } else {
            "file handles"
        };
        recs.push(Recommendation {
            iser: "ephapaxiser".into(),
            confidence: "medium",
            reason: format!(
                "Resource handles ({resource_kind}) found without linear typing — ephapaxiser adds linearity guarantees."
            ),
            already_applied: is_applied(root, "ephapaxiser"),
        });
    }
}

/// verisimiser — VeriSimDB integration layer for repos that perform database
/// interactions without a VeriSimDB instance.
fn check_verisimiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_db = has_file_named(root, "schema.sql")
        || has_file_named(root, "migrations")
        || has_dir(root, "migrations")
        || has_dir(root, "priv/repo/migrations")
        || src_contains(root, "sqlx::")
        || src_contains(root, "diesel::")
        || src_contains(root, "Ecto.Repo")
        || src_contains(root, "ActiveRecord");

    let has_verisimdb = has_dir(root, ".verisimdb")
        || has_file(root, "verisimdb.toml")
        || src_contains(root, "verisimdb")
        || src_contains(root, "VeriSimDB");

    if has_db && !has_verisimdb {
        recs.push(Recommendation {
            iser: "verisimiser".into(),
            confidence: "high",
            reason: "Database interactions found with no VeriSimDB instance — verisimiser adds verified query semantics.".into(),
            already_applied: is_applied(root, "verisimiser"),
        });
    }
}

/// otpiser — OTP supervision-tree auditing layer for Elixir/Erlang repos.
fn check_otpiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_elixir = has_file(root, "mix.exs");
    let has_otp = src_contains(root, "use GenServer")
        || src_contains(root, "use Supervisor")
        || src_contains(root, "use Application")
        || src_contains(root, "Supervisor.start_link")
        || src_contains(root, ":gen_server");

    if has_elixir && has_otp {
        recs.push(Recommendation {
            iser: "otpiser".into(),
            confidence: "high",
            reason: "Elixir/OTP GenServer and Supervisor patterns found — otpiser audits supervision tree correctness.".into(),
            already_applied: is_applied(root, "otpiser"),
        });
    } else if has_elixir {
        recs.push(Recommendation {
            iser: "otpiser".into(),
            confidence: "low",
            reason: "Elixir project (mix.exs) found — otpiser can audit OTP patterns if they are added.".into(),
            already_applied: is_applied(root, "otpiser"),
        });
    }
}

/// ponyiser — capability-security layer for repos with shared mutable state
/// accessed from multiple threads.
fn check_ponyiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_shared_mut = src_contains(root, "Arc<Mutex<")
        || src_contains(root, "Arc<RwLock<")
        || src_contains(root, "static mut ")
        || src_contains(root, "lazy_static!")
        || src_contains(root, "once_cell::sync::Lazy");

    let has_threads = src_contains(root, "thread::spawn")
        || src_contains(root, "tokio::spawn")
        || src_contains(root, "rayon::");

    if has_shared_mut && has_threads {
        recs.push(Recommendation {
            iser: "ponyiser".into(),
            confidence: "high",
            reason: "Shared mutable state (Arc<Mutex/RwLock>) accessed from multiple threads — ponyiser adds capability-safety analysis.".into(),
            already_applied: is_applied(root, "ponyiser"),
        });
    } else if has_shared_mut {
        recs.push(Recommendation {
            iser: "ponyiser".into(),
            confidence: "low",
            reason: "Shared mutable state patterns found — ponyiser can audit thread safety if concurrency is added.".into(),
            already_applied: is_applied(root, "ponyiser"),
        });
    }
}

/// dafniser — Dafny verification layer for repos with safety-critical
/// algorithms (crypto, parsing, sorting).
fn check_dafniser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_crypto = src_contains(root, "aes::")
        || src_contains(root, "chacha20")
        || src_contains(root, "sha2::")
        || src_contains(root, "hmac::")
        || src_contains(root, "ring::")
        || src_contains(root, "openssl::")
        || src_contains(root, "Crypto.")
        || src_contains(root, ":crypto");

    let has_sorting = src_contains(root, ".sort_by(")
        || src_contains(root, ".sort_unstable")
        || src_contains(root, "merge_sort")
        || src_contains(root, "quicksort");

    let has_safety_critical = has_crypto || (has_sorting && src_contains(root, "unsafe"));

    if has_crypto {
        recs.push(Recommendation {
            iser: "dafniser".into(),
            confidence: "high",
            reason: "Cryptographic algorithm code found — dafniser adds Dafny correctness proofs.".into(),
            already_applied: is_applied(root, "dafniser"),
        });
    } else if has_safety_critical {
        recs.push(Recommendation {
            iser: "dafniser".into(),
            confidence: "medium",
            reason: "Safety-critical algorithm patterns found — dafniser can add formal verification.".into(),
            already_applied: is_applied(root, "dafniser"),
        });
    }
}

/// futharkiser — GPU/array compute optimisation layer for repos using ndarray,
/// tch (PyTorch bindings), or candle.
fn check_futharkiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_gpu = src_contains(root, "ndarray")
        || src_contains(root, "tch::")
        || src_contains(root, "candle_core")
        || src_contains(root, "cuda::")
        || src_contains(root, "wgpu::")
        || src_contains(root, "opencl");

    if has_gpu {
        recs.push(Recommendation {
            iser: "futharkiser".into(),
            confidence: "medium",
            reason: "GPU/array compute patterns (ndarray/tch/candle/wgpu) found — futharkiser adds Futhark kernel optimisation.".into(),
            already_applied: is_applied(root, "futharkiser"),
        });
    }
}

/// lustreiser — synchronous reactive layer for repos with real-time, embedded,
/// or control-loop patterns.
fn check_lustreiser(root: &Path, recs: &mut Vec<Recommendation>) {
    let has_realtime = src_contains(root, "control_loop")
        || src_contains(root, "tick(")
        || src_contains(root, "interrupt_handler")
        || src_contains(root, "#[interrupt]")
        || src_contains(root, "embassy::")
        || src_contains(root, "rtic::")
        || src_contains(root, "cortex_m::")
        || has_file_named(root, ".lus");

    if has_realtime {
        recs.push(Recommendation {
            iser: "lustreiser".into(),
            confidence: "medium",
            reason: "Real-time/embedded/control-loop patterns found — lustreiser adds synchronous Lustre specifications.".into(),
            already_applied: is_applied(root, "lustreiser"),
        });
    }
}
