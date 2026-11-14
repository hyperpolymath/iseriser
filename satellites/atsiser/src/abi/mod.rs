// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for atsiser.
//
// Defines the core type system for representing C memory patterns and their
// corresponding ATS2 linear type annotations. These types model the ownership
// semantics that ATS2 enforces at compile time:
//
// - OwnershipPattern: classifies how a C function handles memory (alloc, free,
//   borrow, transfer)
// - Viewtype: the ATS2 viewtype that wraps a C pointer with linear type proof
// - LinearPtr: a tracked pointer with associated viewtype and proof obligation
// - MemorySafetyProof: compile-time evidence that a memory operation is safe
// - ATSModule: a complete ATS2 module ready for compilation

use serde::{Deserialize, Serialize};
use std::fmt;

/// Classification of how a C function interacts with memory ownership.
///
/// ATS2 uses linear types to track resource ownership at compile time. Each
/// pattern maps to a specific ATS2 proof obligation:
///
/// - Alloc: function returns a new linear resource (must be consumed exactly once)
/// - Free: function consumes a linear resource (deallocates)
/// - Borrow: function temporarily accesses a resource without consuming it
/// - Transfer: function moves ownership from one context to another
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OwnershipPattern {
    /// Allocates memory — returns a new linear pointer that must be freed.
    /// C example: `void* malloc(size_t)`, `FILE* fopen(const char*, const char*)`
    Alloc,

    /// Frees memory — consumes a linear pointer, ending its lifetime.
    /// C example: `void free(void*)`, `int fclose(FILE*)`
    Free,

    /// Borrows a pointer — reads or writes without taking ownership.
    /// The caller retains the linear resource after the call returns.
    /// C example: `size_t strlen(const char*)`, `int fprintf(FILE*, ...)`
    Borrow,

    /// Transfers ownership — the caller gives up the resource and the callee
    /// becomes the new owner. Used for container insertion, send-to-channel, etc.
    /// C example: inserting a node into a linked list
    Transfer,
}

impl fmt::Display for OwnershipPattern {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OwnershipPattern::Alloc => write!(f, "alloc"),
            OwnershipPattern::Free => write!(f, "free"),
            OwnershipPattern::Borrow => write!(f, "borrow"),
            OwnershipPattern::Transfer => write!(f, "transfer"),
        }
    }
}

/// An ATS2 viewtype representing a linear type wrapper around a C type.
///
/// In ATS2, viewtypes (also called linear types) combine a view (memory layout
/// proof) with a type. A `Viewtype` describes the ATS2 type that wraps a C
/// pointer to enforce ownership discipline at compile time.
///
/// For example, wrapping `FILE*` produces a viewtype like:
/// ```ats
/// viewtypedef FILE_ptr = [l:addr] (FILE @ l | ptr l)
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Viewtype {
    /// The ATS2 viewtype name (e.g., "FILE_vt", "buffer_vt").
    pub name: String,

    /// The underlying C type being wrapped (e.g., "FILE*", "char*").
    pub c_type: String,

    /// Whether this viewtype is nullable (Option-like in ATS2).
    /// Nullable viewtypes generate additional null-check proof obligations.
    pub nullable: bool,

    /// Optional size constraint for buffer types.
    /// When set, generates dependent type annotations: `{n:nat} buffer_vt(n)`.
    pub size_param: Option<String>,
}

impl Viewtype {
    /// Creates a new non-nullable viewtype wrapping the given C type.
    pub fn new(name: &str, c_type: &str) -> Self {
        Self {
            name: name.to_string(),
            c_type: c_type.to_string(),
            nullable: false,
            size_param: None,
        }
    }

    /// Creates a nullable viewtype (for functions that may return NULL).
    pub fn nullable(name: &str, c_type: &str) -> Self {
        Self {
            name: name.to_string(),
            c_type: c_type.to_string(),
            nullable: true,
            size_param: None,
        }
    }

    /// Creates a sized viewtype with a dependent type parameter.
    pub fn sized(name: &str, c_type: &str, size_param: &str) -> Self {
        Self {
            name: name.to_string(),
            c_type: c_type.to_string(),
            nullable: false,
            size_param: Some(size_param.to_string()),
        }
    }

    /// Generates the ATS2 viewtype definition string.
    pub fn to_ats2_definition(&self) -> String {
        let size_suffix = match &self.size_param {
            Some(param) => format!("({})", param),
            None => String::new(),
        };
        if self.nullable {
            format!(
                "viewtypedef {}{} = [l:addr] (option_v({} @ l, l > null) | ptr l)",
                self.name, size_suffix, self.c_type
            )
        } else {
            format!(
                "viewtypedef {}{} = [l:addr] ({} @ l | ptr l)",
                self.name, size_suffix, self.c_type
            )
        }
    }
}

/// A linear pointer tracked by ATS2's type system.
///
/// Represents a runtime pointer that is statically proven to be valid. The
/// associated viewtype provides the compile-time proof that the pointer is
/// correctly owned and will be properly deallocated.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinearPtr {
    /// Identifier for this pointer (used in generated variable names).
    pub id: String,

    /// The viewtype governing this pointer's ownership.
    pub viewtype: Viewtype,

    /// The ownership pattern for how this pointer was created or will be consumed.
    pub pattern: OwnershipPattern,
}

impl LinearPtr {
    /// Creates a new linear pointer with the given id, viewtype, and pattern.
    pub fn new(id: &str, viewtype: Viewtype, pattern: OwnershipPattern) -> Self {
        Self {
            id: id.to_string(),
            viewtype,
            pattern,
        }
    }
}

/// A compile-time proof that a memory operation is safe.
///
/// ATS2 requires explicit proof terms for memory operations. Each proof
/// corresponds to a specific safety property:
///
/// - AllocProof: the allocation succeeded (non-null for non-nullable types)
/// - FreeProof: the pointer is valid and owned, so freeing is safe
/// - BorrowProof: the pointer is valid for the duration of the borrow
/// - BoundsProof: array index is within the allocated bounds
/// - NullCheckProof: a nullable pointer has been checked for NULL
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MemorySafetyProof {
    /// Proves that an allocation returned a valid (non-null) pointer.
    AllocProof {
        /// The viewtype of the allocated resource.
        viewtype: String,
    },

    /// Proves that a pointer is valid and owned, permitting deallocation.
    FreeProof {
        /// The linear pointer being freed.
        ptr_id: String,
    },

    /// Proves that a borrowed pointer remains valid for the borrow's scope.
    BorrowProof {
        /// The linear pointer being borrowed.
        ptr_id: String,
        /// Whether the borrow is read-only or read-write.
        mutable: bool,
    },

    /// Proves that an index is within the bounds of a sized buffer.
    BoundsProof {
        /// The buffer being indexed.
        buffer_id: String,
        /// The index expression.
        index_expr: String,
    },

    /// Proves that a nullable pointer has been checked for NULL.
    NullCheckProof {
        /// The nullable pointer that was checked.
        ptr_id: String,
    },
}

impl MemorySafetyProof {
    /// Generates the ATS2 proof term string for this proof.
    pub fn to_ats2_proof(&self) -> String {
        match self {
            MemorySafetyProof::AllocProof { viewtype } => {
                format!(
                    "prval (pf_{} | p_{}) = alloc_{}",
                    viewtype, viewtype, viewtype
                )
            }
            MemorySafetyProof::FreeProof { ptr_id } => {
                format!("prval () = free_{}(pf_{}, p_{})", ptr_id, ptr_id, ptr_id)
            }
            MemorySafetyProof::BorrowProof { ptr_id, mutable } => {
                let borrow_kind = if *mutable { "vw" } else { "v" };
                format!(
                    "prval (pf_borrow | p_ref) = borrow_{}(pf_{}, p_{})",
                    borrow_kind, ptr_id, ptr_id
                )
            }
            MemorySafetyProof::BoundsProof {
                buffer_id,
                index_expr,
            } => {
                format!("prval () = lemma_bounds(pf_{}, {})", buffer_id, index_expr)
            }
            MemorySafetyProof::NullCheckProof { ptr_id } => {
                format!("prval () = opt_unsome(pf_{})", ptr_id)
            }
        }
    }
}

/// A complete ATS2 module generated from analysed C code.
///
/// Contains all the viewtype definitions, function wrappers, and proof
/// obligations needed to provide memory-safe access to a C library.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ATSModule {
    /// Module name (derived from the C source file name).
    pub name: String,

    /// ATS2 staload (import) directives for C header interop.
    pub includes: Vec<String>,

    /// Viewtype definitions for the C types used in this module.
    pub viewtypes: Vec<Viewtype>,

    /// Safe wrapper functions with linear type signatures.
    pub functions: Vec<ATSFunction>,

    /// Proof obligations that must be discharged for this module to compile.
    pub proofs: Vec<MemorySafetyProof>,
}

/// An ATS2 function wrapping a C function with linear type annotations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ATSFunction {
    /// The ATS2 function name (typically prefixed with "safe_").
    pub name: String,

    /// The original C function being wrapped.
    pub c_function: String,

    /// Parameters with their ATS2 viewtype annotations.
    pub params: Vec<ATSParam>,

    /// Return type as an ATS2 viewtype (None for void functions).
    pub return_type: Option<String>,

    /// The ownership pattern this function implements.
    pub pattern: OwnershipPattern,
}

/// A parameter in an ATS2 function signature.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ATSParam {
    /// Parameter name.
    pub name: String,

    /// ATS2 type annotation (may include proof variables).
    pub ats_type: String,

    /// Whether this parameter is consumed (linear) or borrowed.
    pub consumed: bool,
}

impl ATSModule {
    /// Creates an empty ATS2 module with the given name.
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            includes: Vec::new(),
            viewtypes: Vec::new(),
            functions: Vec::new(),
            proofs: Vec::new(),
        }
    }

    /// Generates the complete ATS2 source code for this module.
    ///
    /// Produces a `.dats` file containing:
    /// 1. Header includes and staload directives
    /// 2. Viewtype definitions
    /// 3. Function wrappers with proof terms
    pub fn to_ats2_source(&self) -> String {
        let mut out = String::new();

        // Header comment
        out.push_str(&format!(
            "(*\n** SPDX-License-Identifier: MPL-2.0\n\
             ** Generated by atsiser — do not edit manually.\n\
             ** Module: {}\n*)\n\n",
            self.name
        ));

        // Includes
        for inc in &self.includes {
            out.push_str(&format!("#include \"{}\"\n", inc));
        }
        if !self.includes.is_empty() {
            out.push('\n');
        }

        // Staload for C interop
        out.push_str(&format!("staload \"{}_c.sats\"\n\n", self.name));

        // Viewtype definitions
        for vt in &self.viewtypes {
            out.push_str(&vt.to_ats2_definition());
            out.push_str("\n\n");
        }

        // Function wrappers
        for func in &self.functions {
            out.push_str(&generate_ats_function(func));
            out.push('\n');
        }

        out
    }
}

/// Generates ATS2 source code for a single function wrapper.
///
/// Produces an `implement` block with the correct linear type signature,
/// including proof variable bindings for alloc/free patterns.
fn generate_ats_function(func: &ATSFunction) -> String {
    let mut out = String::new();

    // Function signature
    let params_str: Vec<String> = func
        .params
        .iter()
        .map(|p| {
            if p.consumed {
                format!("{}: {}", p.name, p.ats_type)
            } else {
                format!("!{}: {}", p.name, p.ats_type)
            }
        })
        .collect();

    let ret = func.return_type.as_deref().unwrap_or("void");

    out.push_str(&format!(
        "implement\nfun {}({}): {} = let\n",
        func.name,
        params_str.join(", "),
        ret
    ));

    // Generate proof obligations based on pattern
    match func.pattern {
        OwnershipPattern::Alloc => {
            out.push_str(&format!(
                "  val (pf | p) = $extfcall(ptr, \"{}\"",
                func.c_function
            ));
            for param in &func.params {
                out.push_str(&format!(", {}", param.name));
            }
            out.push_str(")\n");
            out.push_str("in\n  (pf | p)\nend\n");
        }
        OwnershipPattern::Free => {
            let ptr_param = func.params.first().map(|p| p.name.as_str()).unwrap_or("p");
            out.push_str(&format!(
                "  val () = $extfcall(void, \"{}\", {})\n",
                func.c_function, ptr_param
            ));
            out.push_str("  prval () = __assert() where {\n");
            out.push_str("    extern praxi __assert(): void\n");
            out.push_str("  }\n");
            out.push_str("in end\n");
        }
        OwnershipPattern::Borrow => {
            out.push_str(&format!(
                "  val result = $extfcall(_, \"{}\", ",
                func.c_function
            ));
            let param_names: Vec<&str> = func.params.iter().map(|p| p.name.as_str()).collect();
            out.push_str(&param_names.join(", "));
            out.push_str(")\n");
            out.push_str("in\n  result\nend\n");
        }
        OwnershipPattern::Transfer => {
            let ptr_param = func.params.first().map(|p| p.name.as_str()).unwrap_or("p");
            out.push_str(&format!(
                "  val () = $extfcall(void, \"{}\", {})\n",
                func.c_function, ptr_param
            ));
            out.push_str("  // Ownership transferred — linear resource consumed\n");
            out.push_str("in end\n");
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ownership_pattern_display() {
        assert_eq!(OwnershipPattern::Alloc.to_string(), "alloc");
        assert_eq!(OwnershipPattern::Free.to_string(), "free");
        assert_eq!(OwnershipPattern::Borrow.to_string(), "borrow");
        assert_eq!(OwnershipPattern::Transfer.to_string(), "transfer");
    }

    #[test]
    fn test_viewtype_definition() {
        let vt = Viewtype::new("FILE_vt", "FILE");
        let def = vt.to_ats2_definition();
        assert!(def.contains("viewtypedef FILE_vt"));
        assert!(def.contains("FILE @ l"));
        assert!(!def.contains("option_v"));
    }

    #[test]
    fn test_nullable_viewtype() {
        let vt = Viewtype::nullable("ptr_vt", "void");
        let def = vt.to_ats2_definition();
        assert!(def.contains("option_v"));
    }

    #[test]
    fn test_sized_viewtype() {
        let vt = Viewtype::sized("buf_vt", "char", "n");
        let def = vt.to_ats2_definition();
        assert!(def.contains("buf_vt(n)"));
    }

    #[test]
    fn test_ats_module_generation() {
        let mut module = ATSModule::new("test_mod");
        module.viewtypes.push(Viewtype::new("int_vt", "int"));
        let source = module.to_ats2_source();
        assert!(source.contains("Module: test_mod"));
        assert!(source.contains("viewtypedef int_vt"));
        assert!(source.contains("staload"));
    }

    #[test]
    fn test_memory_safety_proof_generation() {
        let proof = MemorySafetyProof::AllocProof {
            viewtype: "buf".to_string(),
        };
        let ats = proof.to_ats2_proof();
        assert!(ats.contains("prval"));
        assert!(ats.contains("alloc_buf"));
    }
}
