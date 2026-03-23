// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for iseriser.
// Rust-side types mirroring the Idris2 ABI formal definitions in
// src/interface/abi/Types.idr.  The Idris2 proofs guarantee correctness
// at the ABI boundary; this module provides runtime representations.

use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::PathBuf;

// ---------------------------------------------------------------------------
// Paradigm
// ---------------------------------------------------------------------------

/// Programming paradigm of the target language.
/// Determines the shape of the generated codegen engine and template suite.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Paradigm {
    /// Functional (Haskell, Idris, Gleam, Elixir, OCaml)
    Functional,
    /// Imperative (C, Zig, Rust, Ada)
    Imperative,
    /// Array / tensor oriented (BQN, J, Julia, Futhark)
    Array,
    /// Logic / constraint (Prolog, Mercury)
    Logic,
    /// Dataflow / reactive (LabVIEW, Max, Lustre)
    Dataflow,
}

impl fmt::Display for Paradigm {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Paradigm::Functional => write!(f, "functional"),
            Paradigm::Imperative => write!(f, "imperative"),
            Paradigm::Array => write!(f, "array"),
            Paradigm::Logic => write!(f, "logic"),
            Paradigm::Dataflow => write!(f, "dataflow"),
        }
    }
}

// ---------------------------------------------------------------------------
// TypeSystemFeature
// ---------------------------------------------------------------------------

/// Type system features that a target language may support.
/// Maps 1:1 to the Idris2 `TypeSystemFeature` in Types.idr.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TypeSystemFeature {
    /// Dependent types (Idris2, Lean, Agda) — deepest ABI proofs
    Dependent,
    /// Linear / affine types (Rust, Pony, ATS) — ownership-aware FFI
    Linear,
    /// Refinement types (Dafny, Liquid Haskell) — contract-checked FFI
    Refinement,
    /// Session types (concurrent protocol safety)
    Session,
    /// Algebraic data types (most ML-family languages)
    Algebraic,
    /// Array / tensor types (BQN, Futhark, Julia) — bulk data FFI
    #[serde(rename = "array")]
    ArrayTypes,
    /// Simple types (basic type checking only)
    Simple,
    /// Gradual types (optional type annotations)
    Gradual,
    /// No type system
    None,
}

impl fmt::Display for TypeSystemFeature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TypeSystemFeature::Dependent => write!(f, "dependent"),
            TypeSystemFeature::Linear => write!(f, "linear"),
            TypeSystemFeature::Refinement => write!(f, "refinement"),
            TypeSystemFeature::Session => write!(f, "session"),
            TypeSystemFeature::Algebraic => write!(f, "algebraic"),
            TypeSystemFeature::ArrayTypes => write!(f, "array"),
            TypeSystemFeature::Simple => write!(f, "simple"),
            TypeSystemFeature::Gradual => write!(f, "gradual"),
            TypeSystemFeature::None => write!(f, "none"),
        }
    }
}

// ---------------------------------------------------------------------------
// CompilationTarget
// ---------------------------------------------------------------------------

/// Primary compilation target for the language.
/// Determines the calling convention and FFI bridge shape.
/// Maps 1:1 to the Idris2 `CompilationTarget` in Types.idr.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CompilationTarget {
    /// Native code via C ABI (Rust, C, C++, Zig)
    Native,
    /// JVM bytecode (Java, Kotlin, Scala, Clojure)
    Jvm,
    /// BEAM VM (Erlang, Elixir, Gleam)
    Beam,
    /// WebAssembly (browser, edge, WASI)
    Wasm,
    /// JavaScript / ECMAScript (ReScript, Elm, PureScript)
    Js,
    /// Interpreted with C extension API (Ruby, Lua)
    Interpreted,
    /// GPU-targeted (Futhark, Halide)
    Gpu,
}

impl fmt::Display for CompilationTarget {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CompilationTarget::Native => write!(f, "native"),
            CompilationTarget::Jvm => write!(f, "jvm"),
            CompilationTarget::Beam => write!(f, "beam"),
            CompilationTarget::Wasm => write!(f, "wasm"),
            CompilationTarget::Js => write!(f, "js"),
            CompilationTarget::Interpreted => write!(f, "interpreted"),
            CompilationTarget::Gpu => write!(f, "gpu"),
        }
    }
}

// ---------------------------------------------------------------------------
// LanguageModel
// ---------------------------------------------------------------------------

/// Complete description of a target language, as consumed by the iseriser
/// scaffolding engine.  Corresponds to the Idris2 `LanguageModel` record
/// in Types.idr.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LanguageModel {
    /// Language name (e.g. "Chapel", "Julia", "BQN").
    /// Used as the stem for the generated -iser name.
    pub name: String,

    /// Primary programming paradigm.
    pub paradigm: Paradigm,

    /// Type system classification.
    /// Determines the depth of generated ABI proofs.
    #[serde(rename = "type-system")]
    pub type_system: TypeSystemFeature,

    /// Primary compilation target.
    /// Determines the FFI bridge shape.
    #[serde(rename = "compilation-target")]
    pub compilation_target: CompilationTarget,

    /// Key language primitives that need FFI bindings.
    /// E.g. ["task", "locale", "domain"] for Chapel.
    #[serde(rename = "key-primitives")]
    pub key_primitives: Vec<String>,
}

impl LanguageModel {
    /// Derive the -iser repository name from the language name.
    /// E.g. "Chapel" -> "chapeliser", "BQN" -> "bqniser".
    pub fn iser_name(&self) -> String {
        format!("{}iser", self.name.to_lowercase())
    }

    /// Return the appropriate calling convention string for the target.
    pub fn calling_convention(&self) -> &'static str {
        match self.compilation_target {
            CompilationTarget::Native => "c",
            CompilationTarget::Beam => "beam_nif",
            CompilationTarget::Jvm => "jni",
            CompilationTarget::Wasm => "wasm",
            CompilationTarget::Js => "js_ffi",
            CompilationTarget::Interpreted => "c_ext",
            CompilationTarget::Gpu => "gpu_kernel",
        }
    }

    /// Whether the language has a rich enough type system that the
    /// generated ABI should include deep proofs (dependent / linear /
    /// refinement types).
    pub fn needs_deep_abi_proofs(&self) -> bool {
        matches!(
            self.type_system,
            TypeSystemFeature::Dependent
                | TypeSystemFeature::Linear
                | TypeSystemFeature::Refinement
        )
    }

    /// Whether the target supports direct C ABI calls (no wrapper needed).
    pub fn has_c_abi(&self) -> bool {
        matches!(
            self.compilation_target,
            CompilationTarget::Native | CompilationTarget::Wasm
        )
    }
}

// ---------------------------------------------------------------------------
// GeneratedRepo
// ---------------------------------------------------------------------------

/// Represents a single generated file within the scaffolded -iser repo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeneratedFile {
    /// Relative path within the generated repo (e.g. "src/main.rs").
    pub path: PathBuf,
    /// Rendered file content.
    pub content: String,
}

/// The complete result of scaffolding a new -iser repository.
/// Corresponds to the Idris2 `GeneratedArtifact` / `GenerationComplete`
/// proofs in Types.idr.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeneratedRepo {
    /// Name of the generated -iser (e.g. "chapeliser").
    pub name: String,
    /// Root directory where the repo was written.
    pub root: PathBuf,
    /// All generated files (relative paths + content).
    pub files: Vec<GeneratedFile>,
}

impl GeneratedRepo {
    /// Check that the repo contains the mandatory artifact categories
    /// (mirrors the Idris2 `GenerationComplete` proof).
    pub fn is_complete(&self) -> bool {
        let paths: Vec<String> = self
            .files
            .iter()
            .map(|f| f.path.display().to_string())
            .collect();
        let has = |needle: &str| paths.iter().any(|p| p.contains(needle));

        has("Cargo.toml")
            && has("src/")
            && has("src/abi/")
            && has("ffi/zig/")
            && has(".github/workflows/")
            && has("README")
            && has("LICENSE")
    }

    /// Number of files generated.
    pub fn file_count(&self) -> usize {
        self.files.len()
    }
}

// ---------------------------------------------------------------------------
// ScaffoldResult
// ---------------------------------------------------------------------------

/// Outcome of a scaffold operation.
/// Separates success (with the full repo) from categorised errors.
#[derive(Debug)]
pub enum ScaffoldResult {
    /// Scaffolding completed successfully.
    Success(GeneratedRepo),
    /// The language description was invalid.
    InvalidLanguage(String),
    /// Template expansion failed.
    TemplateError(String),
    /// Could not write to the output directory.
    OutputError(String),
}

impl ScaffoldResult {
    /// True if the scaffold succeeded.
    pub fn is_success(&self) -> bool {
        matches!(self, ScaffoldResult::Success(_))
    }

    /// Extract the generated repo, or `None` on failure.
    pub fn repo(&self) -> Option<&GeneratedRepo> {
        match self {
            ScaffoldResult::Success(r) => Some(r),
            _ => None,
        }
    }

    /// Extract the error message, or `None` on success.
    pub fn error_message(&self) -> Option<&str> {
        match self {
            ScaffoldResult::InvalidLanguage(msg)
            | ScaffoldResult::TemplateError(msg)
            | ScaffoldResult::OutputError(msg) => Some(msg),
            ScaffoldResult::Success(_) => None,
        }
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_iser_name_derivation() {
        let model = LanguageModel {
            name: "Chapel".to_string(),
            paradigm: Paradigm::Imperative,
            type_system: TypeSystemFeature::Simple,
            compilation_target: CompilationTarget::Native,
            key_primitives: vec!["task".to_string()],
        };
        assert_eq!(model.iser_name(), "chapeliser");
    }

    #[test]
    fn test_calling_convention() {
        let model = LanguageModel {
            name: "Gleam".to_string(),
            paradigm: Paradigm::Functional,
            type_system: TypeSystemFeature::Algebraic,
            compilation_target: CompilationTarget::Beam,
            key_primitives: vec!["result".to_string()],
        };
        assert_eq!(model.calling_convention(), "beam_nif");
    }

    #[test]
    fn test_needs_deep_abi_proofs() {
        let dep = LanguageModel {
            name: "Idris2".to_string(),
            paradigm: Paradigm::Functional,
            type_system: TypeSystemFeature::Dependent,
            compilation_target: CompilationTarget::Native,
            key_primitives: vec!["Nat".to_string()],
        };
        assert!(dep.needs_deep_abi_proofs());

        let simple = LanguageModel {
            name: "Lua".to_string(),
            paradigm: Paradigm::Imperative,
            type_system: TypeSystemFeature::Gradual,
            compilation_target: CompilationTarget::Interpreted,
            key_primitives: vec!["table".to_string()],
        };
        assert!(!simple.needs_deep_abi_proofs());
    }

    #[test]
    fn test_paradigm_display() {
        assert_eq!(format!("{}", Paradigm::Functional), "functional");
        assert_eq!(format!("{}", Paradigm::Array), "array");
    }

    #[test]
    fn test_scaffold_result_variants() {
        let err = ScaffoldResult::InvalidLanguage("missing name".to_string());
        assert!(!err.is_success());
        assert_eq!(err.error_message(), Some("missing name"));
        assert!(err.repo().is_none());
    }
}
