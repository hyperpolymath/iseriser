// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// ABI module for TypedQLiser.
// Idris2 proof types for the 10 type safety levels.
//
// Each level corresponds to a proof obligation in the Idris2 type kernel:
//   Level 1:  ParseSafe q        — total parser produces Right ast
//   Level 2:  SchemaBound ast s  — all references resolve in schema s
//   Level 3:  TypeCompat ast     — all operations have compatible operand types
//   Level 4:  NullSafe ast       — all nullable paths are explicitly handled
//   Level 5:  InjectionFree ast  — no string interpolation in query structure
//   Level 6:  ResultTyped ast s  — return type T is statically known
//   Level 7:  CardinalSafe ast   — result set cardinality is bounded
//   Level 8:  EffectTracked ast  — side-effects declared and verified
//   Level 9:  TemporalSafe ast t — time-dependent predicates valid at time t
//   Level 10: LinearSafe ast     — resources consumed exactly once
//
// These Rust types mirror the Idris2 definitions for runtime use.
// The proofs themselves live in src/interface/abi/*.idr.

use serde::{Deserialize, Serialize};

/// A proof certificate for a query at a given level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofCertificate {
    /// The query that was checked.
    pub query_hash: String,
    /// Schema version the proof was checked against.
    pub schema_version: String,
    /// Maximum level achieved.
    pub level: u8,
    /// Per-level proof status.
    pub proofs: Vec<LevelProof>,
}

/// Proof status for one level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LevelProof {
    pub level: u8,
    pub status: ProofStatus,
    /// Serialised Idris2 proof term (if passed).
    pub proof_term: Option<String>,
    /// Counterexample (if failed).
    pub counterexample: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProofStatus {
    Proven,
    Refuted,
    Skipped,
    Timeout,
}
