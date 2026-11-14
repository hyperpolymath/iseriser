// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Analyzer module for ephapaxiser — Tracks resource ownership through code flow and detects violations.
//
// Given a list of call sites (from the parser), the analyzer builds a per-variable ownership
// timeline and checks for:
// - Leaks: a resource is allocated but never deallocated before scope exit
// - Double-frees: a resource is deallocated more than once
// - Use-after-free: a resource is used after being deallocated
//
// Phase 1 uses a simple sequential model: call sites are processed in source order.
// Phase 2 will add control-flow-graph awareness for branches, loops, and early returns.
//
// Design note: When Idris2 proofs conflict with Ephapax linear types, Idris2 ALWAYS wins.

use std::collections::HashMap;

use crate::abi::{
    AnalysisResult, LinearResource, OwnershipState, ResourceKind, SourceLocation, Violation,
};
use crate::codegen::parser::{CallSite, CallSiteKind};
use crate::manifest::{AnalysisConfig, ResourceEntry};

/// Internal tracking state for a single resource variable.
#[derive(Debug)]
struct TrackedVariable {
    /// Name of the resource type (from manifest).
    resource_name: String,
    /// Variable name in source code.
    variable_name: String,
    /// Current ownership state.
    state: OwnershipState,
    /// Where the resource was allocated.
    allocation_site: SourceLocation,
    /// Where the resource was first deallocated (if any).
    deallocation_site: Option<SourceLocation>,
    /// Resource kind.
    kind: ResourceKind,
}

/// Analyse a set of call sites against the manifest's resource definitions.
///
/// Walks through call sites in order, tracking ownership state for each bound variable.
/// At the end, any variable still in `Owned` state is reported as a leak.
///
/// # Arguments
/// * `call_sites` — Ordered call sites from the parser.
/// * `resources` — Resource definitions from the manifest.
/// * `config` — Analysis configuration (which violation types to detect).
///
/// # Returns
/// An `AnalysisResult` containing tracked resources and any violations found.
pub fn analyse(
    call_sites: &[CallSite],
    resources: &[ResourceEntry],
    config: &AnalysisConfig,
) -> AnalysisResult {
    let mut result = AnalysisResult::new();
    // Map from variable name to tracking state.
    let mut tracked: HashMap<String, TrackedVariable> = HashMap::new();

    // Build a lookup from resource name to resource entry for kind resolution.
    let resource_map: HashMap<&str, &ResourceEntry> =
        resources.iter().map(|r| (r.name.as_str(), r)).collect();

    for site in call_sites {
        match site.kind {
            CallSiteKind::Allocation => {
                result.allocation_count += 1;

                if let Some(ref binding) = site.binding {
                    let kind = resource_map
                        .get(site.resource_name.as_str())
                        .map(|r| r.resource_kind())
                        .unwrap_or(ResourceKind::Custom("unknown".to_string()));

                    tracked.insert(
                        binding.clone(),
                        TrackedVariable {
                            resource_name: site.resource_name.clone(),
                            variable_name: binding.clone(),
                            state: OwnershipState::Owned,
                            allocation_site: site.location.clone(),
                            deallocation_site: None,
                            kind,
                        },
                    );
                }
            }
            CallSiteKind::Deallocation => {
                result.deallocation_count += 1;

                if let Some(ref binding) = site.binding
                    && let Some(var) = tracked.get_mut(binding)
                {
                    match var.state {
                        OwnershipState::Owned | OwnershipState::Borrowed => {
                            // Valid deallocation — transition to Consumed.
                            var.state = OwnershipState::Consumed;
                            var.deallocation_site = Some(site.location.clone());
                        }
                        OwnershipState::Consumed => {
                            // Double-free: already deallocated.
                            if config.detect_double_free {
                                result.violations.push(Violation::DoubleFree {
                                    resource_name: var.resource_name.clone(),
                                    first_free: var
                                        .deallocation_site
                                        .clone()
                                        .unwrap_or_else(|| site.location.clone()),
                                    second_free: site.location.clone(),
                                });
                            }
                        }
                        OwnershipState::Uninitialized => {
                            // Deallocating an uninitialized resource — treat as use-after-free
                            // (the resource was never properly allocated under this binding).
                            if config.detect_use_after_free {
                                result.violations.push(Violation::UseAfterFree {
                                    resource_name: var.resource_name.clone(),
                                    free_site: site.location.clone(),
                                    use_site: site.location.clone(),
                                });
                            }
                        }
                    }
                }
                // If binding not tracked, it may be an external resource — skip for now.
            }
            CallSiteKind::Usage => {
                // Check for use-after-free.
                if let Some(ref binding) = site.binding
                    && let Some(var) = tracked.get(binding)
                    && var.state == OwnershipState::Consumed
                    && config.detect_use_after_free
                {
                    result.violations.push(Violation::UseAfterFree {
                        resource_name: var.resource_name.clone(),
                        free_site: var
                            .deallocation_site
                            .clone()
                            .unwrap_or_else(|| site.location.clone()),
                        use_site: site.location.clone(),
                    });
                }
            }
        }
    }

    // Check for leaks: any resource still in Owned state at end of analysis.
    if config.detect_leaks {
        for var in tracked.values() {
            if var.state == OwnershipState::Owned {
                result.violations.push(Violation::Leak {
                    resource_name: var.resource_name.clone(),
                    allocation_site: var.allocation_site.clone(),
                });
            }
        }
    }

    // Build the tracked_resources list for the result.
    for var in tracked.values() {
        result.tracked_resources.push(LinearResource {
            name: var.resource_name.clone(),
            allocator: String::new(), // Filled from manifest if needed.
            deallocator: String::new(),
            kind: var.kind.clone(),
            state: var.state.clone(),
            allocation_site: Some(var.allocation_site.clone()),
            region: None, // Phase 2: populated when scope-aware analysis is added.
        });
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper to create a resource entry.
    fn res(name: &str, alloc: &str, dealloc: &str, kind: &str) -> ResourceEntry {
        ResourceEntry {
            name: name.to_string(),
            allocator: alloc.to_string(),
            deallocator: dealloc.to_string(),
            kind: kind.to_string(),
        }
    }

    /// Helper to create a source location.
    fn loc(file: &str, line: usize) -> SourceLocation {
        SourceLocation {
            file: file.to_string(),
            line,
            column: 0,
        }
    }

    #[test]
    fn test_clean_analysis() {
        let resources = vec![res("FD", "open", "close", "file-descriptor")];
        let sites = vec![
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Allocation,
                location: loc("test.rs", 1),
                binding: Some("fd".to_string()),
            },
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Deallocation,
                location: loc("test.rs", 5),
                binding: Some("fd".to_string()),
            },
        ];
        let result = analyse(&sites, &resources, &AnalysisConfig::default());
        assert!(
            result.is_clean(),
            "Clean alloc/dealloc should produce no violations"
        );
        assert_eq!(result.allocation_count, 1);
        assert_eq!(result.deallocation_count, 1);
    }

    #[test]
    fn test_detect_leak() {
        let resources = vec![res("FD", "open", "close", "file-descriptor")];
        let sites = vec![CallSite {
            resource_name: "FD".to_string(),
            kind: CallSiteKind::Allocation,
            location: loc("test.rs", 1),
            binding: Some("fd".to_string()),
        }];
        let result = analyse(&sites, &resources, &AnalysisConfig::default());
        assert_eq!(result.leak_count(), 1);
    }

    #[test]
    fn test_detect_double_free() {
        let resources = vec![res("FD", "open", "close", "file-descriptor")];
        let sites = vec![
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Allocation,
                location: loc("test.rs", 1),
                binding: Some("fd".to_string()),
            },
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Deallocation,
                location: loc("test.rs", 3),
                binding: Some("fd".to_string()),
            },
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Deallocation,
                location: loc("test.rs", 5),
                binding: Some("fd".to_string()),
            },
        ];
        let result = analyse(&sites, &resources, &AnalysisConfig::default());
        assert_eq!(result.double_free_count(), 1);
    }

    #[test]
    fn test_detect_use_after_free() {
        let resources = vec![res("FD", "open", "close", "file-descriptor")];
        let sites = vec![
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Allocation,
                location: loc("test.rs", 1),
                binding: Some("fd".to_string()),
            },
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Deallocation,
                location: loc("test.rs", 3),
                binding: Some("fd".to_string()),
            },
            CallSite {
                resource_name: "FD".to_string(),
                kind: CallSiteKind::Usage,
                location: loc("test.rs", 5),
                binding: Some("fd".to_string()),
            },
        ];
        let result = analyse(&sites, &resources, &AnalysisConfig::default());
        assert_eq!(result.use_after_free_count(), 1);
    }

    #[test]
    fn test_config_disables_detection() {
        let resources = vec![res("FD", "open", "close", "file-descriptor")];
        let sites = vec![CallSite {
            resource_name: "FD".to_string(),
            kind: CallSiteKind::Allocation,
            location: loc("test.rs", 1),
            binding: Some("fd".to_string()),
        }];
        let config = AnalysisConfig {
            detect_leaks: false,
            detect_double_free: true,
            detect_use_after_free: true,
            ..Default::default()
        };
        let result = analyse(&sites, &resources, &config);
        assert!(
            result.is_clean(),
            "Leak detection disabled — should find no violations"
        );
    }
}
