// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for bqniser.
//
// Rust-side types mirroring the Idris2 ABI formal definitions.
// The Idris2 proofs (in src/abi/*.idr) guarantee correctness of the
// interface layout; this module provides runtime type representations
// that the codegen layer uses to emit BQN programs and FFI bridges.

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// BQN Primitives
// ---------------------------------------------------------------------------

/// All BQN primitives that bqniser can emit.
///
/// Each variant carries the Unicode glyph, a human-readable description,
/// and the arity (monadic = 1 argument, dyadic = 2 arguments).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum BQNPrimitive {
    /// `∾` — Join: concatenate arrays.
    Join,
    /// `⌽` — Reverse: reverse array element order.
    Reverse,
    /// `⍋` — Grade Up: produce ascending sort permutation.
    GradeUp,
    /// `/` — Replicate: filter by boolean mask or repeat by counts.
    Replicate,
    /// `⊏` — Select: index into an array.
    Select,
    /// `⥊` — Reshape: change the shape of an array.
    Reshape,
    /// `´` — Fold: reduce an array with a binary function.
    Fold,
    /// `` ` `` — Scan: prefix-scan (cumulative fold) over an array.
    Scan,
    /// `¨` — Each: apply a function to every element.
    Each,
    /// `⌜` — Table: outer-product / cartesian application.
    Table,
}

impl BQNPrimitive {
    /// Return the BQN Unicode glyph for this primitive.
    pub fn glyph(self) -> &'static str {
        match self {
            BQNPrimitive::Join => "∾",
            BQNPrimitive::Reverse => "⌽",
            BQNPrimitive::GradeUp => "⍋",
            BQNPrimitive::Replicate => "/",
            BQNPrimitive::Select => "⊏",
            BQNPrimitive::Reshape => "⥊",
            BQNPrimitive::Fold => "´",
            BQNPrimitive::Scan => "`",
            BQNPrimitive::Each => "¨",
            BQNPrimitive::Table => "⌜",
        }
    }

    /// Return a human-readable name.
    pub fn label(self) -> &'static str {
        match self {
            BQNPrimitive::Join => "Join",
            BQNPrimitive::Reverse => "Reverse",
            BQNPrimitive::GradeUp => "Grade Up",
            BQNPrimitive::Replicate => "Replicate",
            BQNPrimitive::Select => "Select",
            BQNPrimitive::Reshape => "Reshape",
            BQNPrimitive::Fold => "Fold",
            BQNPrimitive::Scan => "Scan",
            BQNPrimitive::Each => "Each",
            BQNPrimitive::Table => "Table",
        }
    }

    /// Return the arity: 1 for monadic primitives, 2 for dyadic.
    ///
    /// Modifiers (Fold, Scan, Each, Table) are technically 1-modifiers
    /// applied to a function, but they operate on arrays so we report
    /// their effective arity with the operand included.
    pub fn arity(self) -> u8 {
        match self {
            BQNPrimitive::Join => 2,
            BQNPrimitive::Reverse => 1,
            BQNPrimitive::GradeUp => 1,
            BQNPrimitive::Replicate => 2,
            BQNPrimitive::Select => 2,
            BQNPrimitive::Reshape => 2,
            BQNPrimitive::Fold => 1, // modifier applied to a function, then to array
            BQNPrimitive::Scan => 1,
            BQNPrimitive::Each => 1,
            BQNPrimitive::Table => 2,
        }
    }
}

impl std::fmt::Display for BQNPrimitive {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} ({})", self.label(), self.glyph())
    }
}

// ---------------------------------------------------------------------------
// Array Patterns
// ---------------------------------------------------------------------------

/// Describes an array computation pattern detected in source code.
///
/// Links a user-visible name, the detected pattern family, and the
/// BQN primitive(s) that will replace it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArrayPattern {
    /// User-chosen name (from the manifest [[patterns]] entry).
    pub name: String,

    /// The kind of source-level pattern detected.
    pub kind: ArrayPatternKind,

    /// The BQN primitive(s) used in the rewrite.
    /// Most rewrites use a single primitive; some (e.g. sort) compose two.
    pub primitives: Vec<BQNPrimitive>,

    /// Element type flowing into the pattern (e.g. "f64").
    pub input_type: String,

    /// Result type after the BQN rewrite (e.g. "f64", "Vec<f64>").
    pub output_type: String,
}

/// Classification of source-level array patterns.
///
/// Mirrors `SourcePattern` from the manifest but lives in the ABI layer
/// so that the Idris2 proofs can reference it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ArrayPatternKind {
    /// Accumulator loop that sums/reduces values.
    LoopSum,
    /// Map/transform applying a function element-wise.
    MapTransform,
    /// Filter selecting elements matching a predicate.
    FilterPredicate,
    /// Sorting by a key or comparison function.
    Sort,
    /// Group-by aggregating elements by a classifier.
    GroupBy,
}

impl ArrayPatternKind {
    /// Return the primary BQN primitive(s) for this pattern kind.
    ///
    /// Some patterns compose multiple primitives:
    /// - LoopSum -> [Fold] with +
    /// - MapTransform -> [Each]
    /// - FilterPredicate -> [Replicate]
    /// - Sort -> [GradeUp, Select]
    /// - GroupBy -> each element's group via / or ⊔
    pub fn primary_primitives(self) -> Vec<BQNPrimitive> {
        match self {
            ArrayPatternKind::LoopSum => vec![BQNPrimitive::Fold],
            ArrayPatternKind::MapTransform => vec![BQNPrimitive::Each],
            ArrayPatternKind::FilterPredicate => vec![BQNPrimitive::Replicate],
            ArrayPatternKind::Sort => vec![BQNPrimitive::GradeUp, BQNPrimitive::Select],
            ArrayPatternKind::GroupBy => vec![BQNPrimitive::Replicate, BQNPrimitive::Each],
        }
    }
}

// ---------------------------------------------------------------------------
// BQN Program
// ---------------------------------------------------------------------------

/// A complete BQN program ready for emission.
///
/// Holds the source text, metadata about which patterns it implements,
/// and the CBQN FFI function signatures needed to call it from native code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BQNProgram {
    /// The project name this program belongs to.
    pub project_name: String,

    /// BQN source code (Unicode).
    pub source: String,

    /// The array patterns this program implements.
    pub patterns: Vec<ArrayPattern>,

    /// CBQN FFI function declarations for calling this program.
    pub ffi_declarations: Vec<FFIDeclaration>,

    /// Whether optimisation was applied during generation.
    pub optimised: bool,
}

/// A single FFI function declaration for the CBQN bridge.
///
/// Describes a C-callable function that invokes a BQN expression via CBQN.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FFIDeclaration {
    /// C function name (e.g. "bqniser_sum_values").
    pub c_name: String,

    /// BQN expression this function evaluates.
    pub bqn_expr: String,

    /// C parameter types (e.g. ["const double*", "size_t"]).
    pub param_types: Vec<String>,

    /// C return type (e.g. "double").
    pub return_type: String,
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

/// Convert a manifest SourcePattern to the ABI ArrayPatternKind.
pub fn source_pattern_to_kind(sp: &crate::manifest::SourcePattern) -> ArrayPatternKind {
    match sp {
        crate::manifest::SourcePattern::LoopSum => ArrayPatternKind::LoopSum,
        crate::manifest::SourcePattern::MapTransform => ArrayPatternKind::MapTransform,
        crate::manifest::SourcePattern::FilterPredicate => ArrayPatternKind::FilterPredicate,
        crate::manifest::SourcePattern::Sort => ArrayPatternKind::Sort,
        crate::manifest::SourcePattern::GroupBy => ArrayPatternKind::GroupBy,
    }
}

/// Build an ArrayPattern from a manifest PatternEntry.
pub fn pattern_from_entry(entry: &crate::manifest::PatternEntry) -> ArrayPattern {
    let kind = source_pattern_to_kind(&entry.source_pattern);
    ArrayPattern {
        name: entry.name.clone(),
        kind,
        primitives: kind.primary_primitives(),
        input_type: entry.input_type.clone(),
        output_type: entry.output_type.clone(),
    }
}
