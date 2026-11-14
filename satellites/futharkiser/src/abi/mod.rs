// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for futharkiser.
// Defines the core type system for Futhark kernel compilation: SOACs
// (second-order array combinators), GPU backends, Futhark types, kernel
// configurations, and compilation results. These types are the shared
// vocabulary between the manifest parser, code generator, and build system.

use std::fmt;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// SOAC — Second-Order Array Combinator
// ---------------------------------------------------------------------------

/// A Futhark SOAC pattern. Each variant maps directly to a Futhark built-in
/// parallel combinator that the compiler can lower to efficient GPU code.
///
/// * `Map`       — element-wise transformation (`map f xs`)
/// * `Reduce`    — fold with an associative operator (`reduce op ne xs`)
/// * `Scan`      — inclusive prefix scan (`scan op ne xs`)
/// * `Scatter`   — indirect write (`scatter dest is vs`)
/// * `Histogram` — binned counting/reduction (`reduce_by_index`)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SOAC {
    Map,
    Reduce,
    Scan,
    Scatter,
    Histogram,
}

impl SOAC {
    /// Return the Futhark built-in function name for this SOAC.
    pub fn futhark_name(&self) -> &'static str {
        match self {
            SOAC::Map => "map",
            SOAC::Reduce => "reduce",
            SOAC::Scan => "scan",
            SOAC::Scatter => "scatter",
            SOAC::Histogram => "reduce_by_index",
        }
    }

    /// All valid SOAC variants (useful for validation error messages).
    pub fn all_names() -> &'static [&'static str] {
        &["map", "reduce", "scan", "scatter", "histogram"]
    }
}

impl fmt::Display for SOAC {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.futhark_name())
    }
}

// ---------------------------------------------------------------------------
// GPUBackend — Futhark compilation target
// ---------------------------------------------------------------------------

/// GPU compilation backend. Futhark supports multiple targets; each produces
/// a C library with an identical ABI but different runtime characteristics.
///
/// * `OpenCL`    — `futhark opencl` (widest GPU support)
/// * `CUDA`      — `futhark cuda`   (NVIDIA only)
/// * `Multicore` — `futhark multicore` (CPU parallelism via pthreads)
/// * `C`         — `futhark c` (sequential, for debugging/testing)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GPUBackend {
    OpenCL,
    CUDA,
    Multicore,
    C,
}

impl GPUBackend {
    /// The Futhark compiler flag for this backend.
    pub fn compiler_flag(&self) -> &'static str {
        match self {
            GPUBackend::OpenCL => "opencl",
            GPUBackend::CUDA => "cuda",
            GPUBackend::Multicore => "multicore",
            GPUBackend::C => "c",
        }
    }

    /// All valid backend names (for validation messages).
    pub fn all_names() -> &'static [&'static str] {
        &["opencl", "cuda", "multicore", "c"]
    }
}

impl fmt::Display for GPUBackend {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.compiler_flag())
    }
}

// ---------------------------------------------------------------------------
// FutharkType — scalar and array element types
// ---------------------------------------------------------------------------

/// Element types supported in Futhark array declarations. Each variant maps
/// to a Futhark primitive type name used in `entry` signatures.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FutharkType {
    F32,
    F64,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    Bool,
}

impl FutharkType {
    /// Parse a bracket-wrapped Futhark array type string like `[f32]` or `[i64]`.
    /// Returns `None` if the format is unrecognised.
    pub fn from_array_str(s: &str) -> Option<Self> {
        let trimmed = s.trim();
        // Strip surrounding brackets: "[f32]" -> "f32"
        let inner = trimmed.strip_prefix('[')?.strip_suffix(']')?;
        Self::from_scalar_str(inner)
    }

    /// Parse a bare scalar type name like `f32`, `u8`, `bool`.
    pub fn from_scalar_str(s: &str) -> Option<Self> {
        match s.trim() {
            "f32" => Some(FutharkType::F32),
            "f64" => Some(FutharkType::F64),
            "i32" => Some(FutharkType::I32),
            "i64" => Some(FutharkType::I64),
            "u8" => Some(FutharkType::U8),
            "u16" => Some(FutharkType::U16),
            "u32" => Some(FutharkType::U32),
            "u64" => Some(FutharkType::U64),
            "bool" => Some(FutharkType::Bool),
            _ => None,
        }
    }

    /// The Futhark source name for this type.
    pub fn futhark_name(&self) -> &'static str {
        match self {
            FutharkType::F32 => "f32",
            FutharkType::F64 => "f64",
            FutharkType::I32 => "i32",
            FutharkType::I64 => "i64",
            FutharkType::U8 => "u8",
            FutharkType::U16 => "u16",
            FutharkType::U32 => "u32",
            FutharkType::U64 => "u64",
            FutharkType::Bool => "bool",
        }
    }

    /// The C type name for this Futhark type (used in generated C-ABI headers).
    pub fn c_type(&self) -> &'static str {
        match self {
            FutharkType::F32 => "float",
            FutharkType::F64 => "double",
            FutharkType::I32 => "int32_t",
            FutharkType::I64 => "int64_t",
            FutharkType::U8 => "uint8_t",
            FutharkType::U16 => "uint16_t",
            FutharkType::U32 => "uint32_t",
            FutharkType::U64 => "uint64_t",
            FutharkType::Bool => "bool",
        }
    }

    /// The neutral element for reduction/scan with common operators.
    /// Returns the additive identity for `+` and multiplicative identity for `*`.
    pub fn neutral_element(&self, operator: &str) -> &'static str {
        match operator {
            "+" => match self {
                FutharkType::F32 | FutharkType::F64 => "0.0",
                FutharkType::Bool => "false",
                _ => "0",
            },
            "*" => match self {
                FutharkType::F32 | FutharkType::F64 => "1.0",
                FutharkType::Bool => "true",
                _ => "1",
            },
            "&&" => "true",
            "||" => "false",
            _ => "0",
        }
    }

    /// All valid type name strings.
    pub fn all_names() -> &'static [&'static str] {
        &[
            "f32", "f64", "i32", "i64", "u8", "u16", "u32", "u64", "bool",
        ]
    }
}

impl fmt::Display for FutharkType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.futhark_name())
    }
}

// ---------------------------------------------------------------------------
// KernelConfig — parsed kernel descriptor
// ---------------------------------------------------------------------------

/// A fully validated kernel configuration, produced by the manifest parser.
/// Each `KernelConfig` maps to one Futhark `entry` function.
#[derive(Debug, Clone, PartialEq)]
pub struct KernelConfig {
    /// Unique kernel name (used as the Futhark entry point name).
    pub name: String,
    /// The SOAC pattern to apply.
    pub pattern: SOAC,
    /// Element type of the input array.
    pub input_type: FutharkType,
    /// Element type of the output array.
    pub output_type: FutharkType,
    /// Human-readable description (emitted as a Futhark comment).
    pub description: String,
    /// For reduce/scan: the binary operator (e.g. "+", "*", "&&").
    pub operator: Option<String>,
    /// For histogram: the number of bins.
    pub bins: Option<u64>,
}

// ---------------------------------------------------------------------------
// ArrayShape — dimensionality descriptor
// ---------------------------------------------------------------------------

/// Describes the shape of an array argument. Phase 1 uses 1-D arrays only,
/// but this type is designed for future multi-dimensional support.
#[derive(Debug, Clone, PartialEq)]
pub struct ArrayShape {
    /// Number of dimensions (1 for `[]t`, 2 for `[][]t`, etc.).
    pub dimensions: u32,
    /// Element type.
    pub element_type: FutharkType,
}

impl ArrayShape {
    /// Create a 1-D array shape.
    pub fn one_dimensional(element_type: FutharkType) -> Self {
        ArrayShape {
            dimensions: 1,
            element_type,
        }
    }

    /// Render as a Futhark type string, e.g. `[]f32` or `[][]i64`.
    pub fn futhark_type_str(&self) -> String {
        let brackets: String = "[]".repeat(self.dimensions as usize);
        format!("{}{}", brackets, self.element_type.futhark_name())
    }
}

impl fmt::Display for ArrayShape {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.futhark_type_str())
    }
}

// ---------------------------------------------------------------------------
// CompilationResult — output of the generation/build pipeline
// ---------------------------------------------------------------------------

/// Captures the result of a code-generation or compilation step, including
/// the paths of all produced artifacts and any diagnostics.
#[derive(Debug, Clone)]
pub struct CompilationResult {
    /// Whether the operation succeeded.
    pub success: bool,
    /// Path to the generated `.fut` source file.
    pub futhark_source: Option<PathBuf>,
    /// Path to the generated C-ABI header file.
    pub c_header: Option<PathBuf>,
    /// Path to the build script (shell/just).
    pub build_script: Option<PathBuf>,
    /// The GPU backend that was targeted.
    pub backend: GPUBackend,
    /// Informational or warning messages from the pipeline.
    pub messages: Vec<String>,
}

impl CompilationResult {
    /// Create a successful result with no artifacts yet.
    pub fn ok(backend: GPUBackend) -> Self {
        CompilationResult {
            success: true,
            futhark_source: None,
            c_header: None,
            build_script: None,
            backend,
            messages: Vec::new(),
        }
    }

    /// Create a failed result with an error message.
    pub fn fail(backend: GPUBackend, message: String) -> Self {
        CompilationResult {
            success: false,
            futhark_source: None,
            c_header: None,
            build_script: None,
            backend,
            messages: vec![message],
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_soac_futhark_names() {
        assert_eq!(SOAC::Map.futhark_name(), "map");
        assert_eq!(SOAC::Reduce.futhark_name(), "reduce");
        assert_eq!(SOAC::Scan.futhark_name(), "scan");
        assert_eq!(SOAC::Scatter.futhark_name(), "scatter");
        assert_eq!(SOAC::Histogram.futhark_name(), "reduce_by_index");
    }

    #[test]
    fn test_backend_compiler_flags() {
        assert_eq!(GPUBackend::OpenCL.compiler_flag(), "opencl");
        assert_eq!(GPUBackend::CUDA.compiler_flag(), "cuda");
        assert_eq!(GPUBackend::Multicore.compiler_flag(), "multicore");
        assert_eq!(GPUBackend::C.compiler_flag(), "c");
    }

    #[test]
    fn test_futhark_type_parsing() {
        assert_eq!(FutharkType::from_array_str("[f32]"), Some(FutharkType::F32));
        assert_eq!(FutharkType::from_array_str("[u8]"), Some(FutharkType::U8));
        assert_eq!(
            FutharkType::from_array_str("[bool]"),
            Some(FutharkType::Bool)
        );
        assert_eq!(FutharkType::from_array_str("bad"), None);
    }

    #[test]
    fn test_futhark_type_c_mapping() {
        assert_eq!(FutharkType::F32.c_type(), "float");
        assert_eq!(FutharkType::I64.c_type(), "int64_t");
        assert_eq!(FutharkType::Bool.c_type(), "bool");
    }

    #[test]
    fn test_array_shape_display() {
        let shape = ArrayShape::one_dimensional(FutharkType::F64);
        assert_eq!(shape.futhark_type_str(), "[]f64");
        assert_eq!(shape.dimensions, 1);
    }

    #[test]
    fn test_neutral_elements() {
        assert_eq!(FutharkType::F32.neutral_element("+"), "0.0");
        assert_eq!(FutharkType::I32.neutral_element("*"), "1");
        assert_eq!(FutharkType::Bool.neutral_element("&&"), "true");
    }

    #[test]
    fn test_compilation_result_constructors() {
        let ok = CompilationResult::ok(GPUBackend::OpenCL);
        assert!(ok.success);
        assert!(ok.messages.is_empty());

        let fail = CompilationResult::fail(GPUBackend::CUDA, "test error".into());
        assert!(!fail.success);
        assert_eq!(fail.messages[0], "test error");
    }
}
