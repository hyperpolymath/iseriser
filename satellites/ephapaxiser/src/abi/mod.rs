// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for ephapaxiser — Core types for linear resource analysis.
//
// Defines the fundamental types used throughout ephapaxiser:
// - ResourceKind: Classification of system resources (file descriptors, sockets, etc.)
// - OwnershipState: Tracks the lifecycle state of a resource (Uninitialized → Owned → Consumed)
// - LinearResource: A resource handle with its allocator/deallocator pair and current state
// - Violation: Detected misuse of a resource (leak, double-free, use-after-free)
// - AnalysisResult: Aggregated output from analysing a codebase
//
// Design note: When Idris2 proofs conflict with Ephapax linear types, Idris2 ALWAYS wins.
// The Rust types here mirror the Idris2 ABI definitions in src/interface/abi/ but are
// subordinate to the formal proofs.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Classification of system resources that ephapaxiser can track.
///
/// Each kind maps to a family of allocator/deallocator pairs. For example,
/// `FileDescriptor` typically pairs `open`/`close`, while `DbConnection`
/// pairs `connect`/`disconnect`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ResourceKind {
    /// File descriptors: open/close, fopen/fclose, etc.
    FileDescriptor,
    /// Network sockets: socket/close, connect/shutdown, etc.
    Socket,
    /// Mutual exclusion locks: lock/unlock, acquire/release, etc.
    Lock,
    /// Heap allocations: malloc/free, alloc/dealloc, etc.
    Allocation,
    /// GPU buffer handles: allocate_buffer/release_buffer, etc.
    GpuBuffer,
    /// Database connections: connect/disconnect, open/close, etc.
    DbConnection,
    /// User-defined resource kind with a descriptive label.
    Custom(String),
}

impl ResourceKind {
    /// Parse a resource kind from a string (as used in ephapaxiser.toml).
    ///
    /// Recognised values: "file-descriptor", "socket", "lock", "allocation",
    /// "gpu-buffer", "db-connection". Anything else becomes `Custom(s)`.
    pub fn from_str_loose(s: &str) -> Self {
        match s {
            "file-descriptor" => Self::FileDescriptor,
            "socket" => Self::Socket,
            "lock" => Self::Lock,
            "allocation" => Self::Allocation,
            "gpu-buffer" => Self::GpuBuffer,
            "db-connection" => Self::DbConnection,
            other => Self::Custom(other.to_string()),
        }
    }

    /// Return the canonical string representation (matches ephapaxiser.toml format).
    pub fn as_str(&self) -> &str {
        match self {
            Self::FileDescriptor => "file-descriptor",
            Self::Socket => "socket",
            Self::Lock => "lock",
            Self::Allocation => "allocation",
            Self::GpuBuffer => "gpu-buffer",
            Self::DbConnection => "db-connection",
            Self::Custom(s) => s.as_str(),
        }
    }
}

impl fmt::Display for ResourceKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Lifecycle state of a linear resource.
///
/// Resources follow a strict linear path:
///   Uninitialized → Owned → Consumed
/// with optional Borrowed states in between.
///
/// Any deviation from this path is a violation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OwnershipState {
    /// Resource has been declared but not yet allocated.
    Uninitialized,
    /// Resource has been allocated and is owned by the current scope.
    Owned,
    /// Resource is temporarily borrowed (e.g., passed by reference).
    Borrowed,
    /// Resource has been deallocated / consumed. Further use is a violation.
    Consumed,
}

impl fmt::Display for OwnershipState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Uninitialized => write!(f, "uninitialized"),
            Self::Owned => write!(f, "owned"),
            Self::Borrowed => write!(f, "borrowed"),
            Self::Consumed => write!(f, "consumed"),
        }
    }
}

/// A source location (file, line, column) for error reporting.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceLocation {
    /// Path to the source file.
    pub file: String,
    /// 1-based line number.
    pub line: usize,
    /// 1-based column number (0 if unknown).
    pub column: usize,
}

impl fmt::Display for SourceLocation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.column > 0 {
            write!(f, "{}:{}:{}", self.file, self.line, self.column)
        } else {
            write!(f, "{}:{}", self.file, self.line)
        }
    }
}

/// A tracked linear resource with its allocator/deallocator pair and current state.
///
/// Each `LinearResource` represents one resource handle that must be used exactly once:
/// allocated exactly once, and deallocated exactly once.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinearResource {
    /// Human-readable name for this resource (e.g., "FileHandle", "DbConnection").
    pub name: String,
    /// The function/method that allocates this resource (e.g., "open", "connect").
    pub allocator: String,
    /// The function/method that deallocates this resource (e.g., "close", "disconnect").
    pub deallocator: String,
    /// Classification of this resource.
    pub kind: ResourceKind,
    /// Current ownership state (used during analysis).
    pub state: OwnershipState,
    /// Where this resource was allocated (set during analysis).
    pub allocation_site: Option<SourceLocation>,
    /// Which region this resource belongs to (if any).
    ///
    /// When set, the resource's lifetime is bounded by the region — it cannot
    /// escape the region's scope. At region exit, all linear resources in the
    /// region must have been consumed (AllLinearsConsumed from the formal proofs).
    /// This field mirrors Ephapax's region-linear fusion: the region constraint
    /// is orthogonal to the ownership state tracking.
    pub region: Option<String>,
}

impl LinearResource {
    /// Create a new linear resource definition (from manifest configuration).
    pub fn new(name: &str, allocator: &str, deallocator: &str, kind: ResourceKind) -> Self {
        Self {
            name: name.to_string(),
            allocator: allocator.to_string(),
            deallocator: deallocator.to_string(),
            kind,
            state: OwnershipState::Uninitialized,
            allocation_site: None,
            region: None,
        }
    }
}

/// A detected violation of linear resource semantics.
///
/// Each variant captures the resource name and the location(s) involved.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Violation {
    /// Resource was allocated but never deallocated — it leaks.
    Leak {
        /// Name of the leaked resource.
        resource_name: String,
        /// Where the resource was allocated.
        allocation_site: SourceLocation,
    },
    /// Resource was deallocated more than once — double-free.
    DoubleFree {
        /// Name of the double-freed resource.
        resource_name: String,
        /// Where the first deallocation occurred.
        first_free: SourceLocation,
        /// Where the second (invalid) deallocation occurred.
        second_free: SourceLocation,
    },
    /// Resource escapes its region scope — region escape.
    RegionEscape {
        /// Name of the escaping resource.
        resource_name: String,
        /// The region the resource belongs to.
        region: String,
        /// Where the escape was detected.
        escape_site: SourceLocation,
    },
    /// Linear resource in a region not consumed before region exit.
    RegionLinearNotConsumed {
        /// Name of the unconsumed resource.
        resource_name: String,
        /// The region that is exiting.
        region: String,
        /// Where the resource was allocated.
        allocation_site: SourceLocation,
    },
    /// Resource was used after being deallocated — use-after-free.
    UseAfterFree {
        /// Name of the misused resource.
        resource_name: String,
        /// Where the resource was deallocated.
        free_site: SourceLocation,
        /// Where the resource was (invalidly) used after deallocation.
        use_site: SourceLocation,
    },
}

impl fmt::Display for Violation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Leak {
                resource_name,
                allocation_site,
            } => {
                write!(
                    f,
                    "LEAK: '{}' allocated at {} was never deallocated",
                    resource_name, allocation_site
                )
            }
            Self::DoubleFree {
                resource_name,
                first_free,
                second_free,
            } => {
                write!(
                    f,
                    "DOUBLE-FREE: '{}' freed at {} and again at {}",
                    resource_name, first_free, second_free
                )
            }
            Self::RegionEscape {
                resource_name,
                region,
                escape_site,
            } => {
                write!(
                    f,
                    "REGION-ESCAPE: '{}' in region '{}' escapes at {}",
                    resource_name, region, escape_site
                )
            }
            Self::RegionLinearNotConsumed {
                resource_name,
                region,
                allocation_site,
            } => {
                write!(
                    f,
                    "REGION-LINEAR-NOT-CONSUMED: '{}' in region '{}' allocated at {} not consumed before region exit",
                    resource_name, region, allocation_site
                )
            }
            Self::UseAfterFree {
                resource_name,
                free_site,
                use_site,
            } => {
                write!(
                    f,
                    "USE-AFTER-FREE: '{}' freed at {} but used at {}",
                    resource_name, free_site, use_site
                )
            }
        }
    }
}

/// Aggregated result from analysing a codebase for linear resource violations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResult {
    /// Resources that were successfully tracked (allocated and properly deallocated).
    pub tracked_resources: Vec<LinearResource>,
    /// Detected violations.
    pub violations: Vec<Violation>,
    /// Total number of allocation sites found.
    pub allocation_count: usize,
    /// Total number of deallocation sites found.
    pub deallocation_count: usize,
}

impl AnalysisResult {
    /// Create an empty analysis result.
    pub fn new() -> Self {
        Self {
            tracked_resources: Vec::new(),
            violations: Vec::new(),
            allocation_count: 0,
            deallocation_count: 0,
        }
    }

    /// Returns true if no violations were detected.
    pub fn is_clean(&self) -> bool {
        self.violations.is_empty()
    }

    /// Count violations by category.
    pub fn leak_count(&self) -> usize {
        self.violations
            .iter()
            .filter(|v| matches!(v, Violation::Leak { .. }))
            .count()
    }

    /// Count double-free violations.
    pub fn double_free_count(&self) -> usize {
        self.violations
            .iter()
            .filter(|v| matches!(v, Violation::DoubleFree { .. }))
            .count()
    }

    /// Count use-after-free violations.
    pub fn use_after_free_count(&self) -> usize {
        self.violations
            .iter()
            .filter(|v| matches!(v, Violation::UseAfterFree { .. }))
            .count()
    }
}

impl Default for AnalysisResult {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify all resource kinds round-trip through string conversion.
    #[test]
    fn test_all_resource_kinds() {
        let kinds = vec![
            ("file-descriptor", ResourceKind::FileDescriptor),
            ("socket", ResourceKind::Socket),
            ("lock", ResourceKind::Lock),
            ("allocation", ResourceKind::Allocation),
            ("gpu-buffer", ResourceKind::GpuBuffer),
            ("db-connection", ResourceKind::DbConnection),
            (
                "custom-thing",
                ResourceKind::Custom("custom-thing".to_string()),
            ),
        ];
        for (s, expected) in &kinds {
            let parsed = ResourceKind::from_str_loose(s);
            assert_eq!(&parsed, expected, "round-trip failed for '{}'", s);
            assert_eq!(parsed.as_str(), *s, "as_str mismatch for '{}'", s);
        }
    }

    /// Verify ownership state display formatting.
    #[test]
    fn test_ownership_state_display() {
        assert_eq!(
            format!("{}", OwnershipState::Uninitialized),
            "uninitialized"
        );
        assert_eq!(format!("{}", OwnershipState::Owned), "owned");
        assert_eq!(format!("{}", OwnershipState::Borrowed), "borrowed");
        assert_eq!(format!("{}", OwnershipState::Consumed), "consumed");
    }

    /// Verify violation display formatting includes location info.
    #[test]
    fn test_violation_display() {
        let loc = SourceLocation {
            file: "test.rs".to_string(),
            line: 10,
            column: 5,
        };
        let leak = Violation::Leak {
            resource_name: "fd".to_string(),
            allocation_site: loc.clone(),
        };
        assert!(format!("{}", leak).contains("test.rs:10:5"));
        assert!(format!("{}", leak).contains("LEAK"));
    }

    /// Verify AnalysisResult counting methods.
    #[test]
    fn test_analysis_result_counts() {
        let loc = SourceLocation {
            file: "t.rs".to_string(),
            line: 1,
            column: 0,
        };
        let mut result = AnalysisResult::new();
        assert!(result.is_clean());

        result.violations.push(Violation::Leak {
            resource_name: "a".to_string(),
            allocation_site: loc.clone(),
        });
        result.violations.push(Violation::DoubleFree {
            resource_name: "b".to_string(),
            first_free: loc.clone(),
            second_free: loc.clone(),
        });
        assert!(!result.is_clean());
        assert_eq!(result.leak_count(), 1);
        assert_eq!(result.double_free_count(), 1);
        assert_eq!(result.use_after_free_count(), 0);
    }
}
