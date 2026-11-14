// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// ABI module — Rust-side types that mirror the Idris2 ABI definitions.
//
// The Idris2 proofs in src/interface/abi/*.idr guarantee at compile time:
//   1. Partition completeness — no items lost or duplicated
//   2. Partition disjointness — no two slices overlap
//   3. Gather conservation — all results preserved
//   4. Serialisation round-trip — deserialize(serialize(x)) ≡ x
//   5. Retry isolation — retrying item i only affects slot i
//
// This Rust module provides the runtime types and runtime verification.
// The Idris2 proofs provide the compile-time guarantees.

use serde::{Deserialize, Serialize};

/// FFI result codes. Must match Chapeliser.ABI.Types.Result in Types.idr.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum FfiResult {
    /// Operation succeeded (0)
    Ok = 0,
    /// Generic error (1)
    Error = 1,
    /// Invalid parameter (2)
    InvalidParam = 2,
    /// Out of memory — buffer too small (3)
    OutOfMemory = 3,
    /// Null pointer in FFI call (4)
    NullPointer = 4,
    /// Item processing failed after all retries (5)
    RetryExhausted = 5,
    /// Checkpoint save/load failed (6)
    CheckpointError = 6,
}

/// Partition strategy. Must match Chapeliser.ABI.Types.PartitionStrategy.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PartitionStrategy {
    /// Even distribution: locale i gets items [i*N/K .. (i+1)*N/K)
    PerItem,
    /// Fixed-size chunks of grainSize items, round-robin across locales
    Chunk,
    /// Dynamic work-stealing via Chapel's DynamicIters
    Adaptive,
    /// Block-distributed domain decomposition
    Spatial,
    /// Route by key hash: same key → same locale
    Keyed,
}

impl PartitionStrategy {
    /// Parse from manifest string
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "per-item" => Some(Self::PerItem),
            "chunk" => Some(Self::Chunk),
            "adaptive" => Some(Self::Adaptive),
            "spatial" => Some(Self::Spatial),
            "keyed" => Some(Self::Keyed),
            _ => None,
        }
    }
}

/// Gather strategy. Must match Chapeliser.ABI.Types.GatherStrategy.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GatherStrategy {
    /// Concatenate all results
    Merge,
    /// Fold results into one via reduce function
    Reduce,
    /// Logarithmic pairwise reduction across locales
    TreeReduce,
    /// Results available incrementally
    Stream,
    /// Return first result matching a predicate
    First,
}

impl GatherStrategy {
    /// Parse from manifest string
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "merge" => Some(Self::Merge),
            "reduce" => Some(Self::Reduce),
            "tree-reduce" => Some(Self::TreeReduce),
            "stream" => Some(Self::Stream),
            "first" => Some(Self::First),
            _ => None,
        }
    }
}

/// A contiguous range of items assigned to one locale.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Slice {
    /// First item index in this slice
    pub start: u64,
    /// Number of items in this slice
    pub count: u64,
}

/// A partition of N items across K locales.
/// Proven properties (from Idris2 ABI):
///   - Union of all slices == original collection (completeness)
///   - Intersection of any two slices == empty (no duplicates)
///   - Sum of slice lengths == N (conservation)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Partition {
    /// Total number of items being partitioned.
    pub total_items: u64,
    /// Number of locales (partitions).
    pub num_locales: u32,
    /// Grain size: items per task.
    pub grain_size: u32,
    /// Slice assignments: one per locale.
    pub slices: Vec<Slice>,
}

impl Partition {
    /// Create a per-item partition: each locale gets total/K items.
    /// First (N mod K) locales get one extra item.
    pub fn per_item(total_items: u64, num_locales: u32) -> Self {
        let k = num_locales as u64;
        let base = total_items / k;
        let remainder = total_items % k;

        let mut slices = Vec::with_capacity(num_locales as usize);
        let mut offset = 0u64;
        for i in 0..k {
            let count = base + if i < remainder { 1 } else { 0 };
            slices.push(Slice {
                start: offset,
                count,
            });
            offset += count;
        }

        Self {
            total_items,
            num_locales,
            grain_size: 1,
            slices,
        }
    }

    /// Create a chunked partition: items grouped into chunks of `grain_size`.
    pub fn chunked(total_items: u64, num_locales: u32, grain_size: u32) -> Self {
        let g = grain_size as u64;
        let num_chunks = total_items.div_ceil(g);
        let chunks_per_locale = num_chunks.div_ceil(num_locales as u64);

        let mut slices = Vec::with_capacity(num_locales as usize);
        let mut offset = 0u64;
        for _ in 0..num_locales {
            let items_this_locale = (chunks_per_locale * g).min(total_items.saturating_sub(offset));
            slices.push(Slice {
                start: offset,
                count: items_this_locale,
            });
            offset += items_this_locale;
        }

        Self {
            total_items,
            num_locales,
            grain_size,
            slices,
        }
    }

    /// Verify partition completeness: sum of all slice counts == total_items.
    /// This is the runtime check; the Idris2 ABI proves it at compile time.
    pub fn verify_completeness(&self) -> bool {
        let sum: u64 = self.slices.iter().map(|s| s.count).sum();
        sum == self.total_items
    }

    /// Verify no overlaps: no two slices share any index.
    pub fn verify_no_overlap(&self) -> bool {
        for (i, a) in self.slices.iter().enumerate() {
            for b in self.slices.iter().skip(i + 1) {
                let end_a = a.start + a.count;
                let end_b = b.start + b.count;
                if a.start < end_b && b.start < end_a {
                    return false;
                }
            }
        }
        true
    }

    /// Verify this is a valid partition (complete + disjoint).
    pub fn verify(&self) -> bool {
        self.verify_completeness() && self.verify_no_overlap()
    }
}

/// Metadata about a serialisation format.
/// Idris2 ABI proves: deserialize(serialize(x)) == x for all x.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerializationContract {
    /// Name of the serialisation format (matches manifest options).
    pub format: String,
    /// Maximum buffer size needed for any single item.
    pub max_item_bytes: usize,
    /// Whether the format is self-describing (JSON, CBOR) or schema-dependent (bincode).
    pub self_describing: bool,
}

/// Result of a gather operation.
/// Proven property: |gathered| == sum(|locale_results|) for merge strategy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatherResult {
    /// Total results gathered across all locales.
    pub total_results: u64,
    /// Per-locale result counts (for verification).
    pub locale_counts: Vec<u64>,
    /// Gather strategy used.
    pub strategy: GatherStrategy,
}

impl GatherResult {
    /// Verify that total_results == sum of locale_counts (gather conservation).
    pub fn verify_conservation(&self) -> bool {
        let sum: u64 = self.locale_counts.iter().sum();
        sum == self.total_results
    }
}

/// Per-locale memory budget estimate.
/// Helps users determine whether their workload fits in available RAM.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryBudget {
    /// Items assigned to this locale
    pub items_per_locale: u64,
    /// Input buffer memory (bytes)
    pub input_bytes: u64,
    /// Output buffer memory (bytes)
    pub output_bytes: u64,
    /// Size tracking arrays (bytes)
    pub metadata_bytes: u64,
    /// Total estimated memory per locale (bytes)
    pub total_bytes: u64,
    /// Total in megabytes (rounded up)
    pub total_mb: u64,
}

impl MemoryBudget {
    /// Calculate the per-locale memory budget for a workload.
    pub fn calculate(total_items: u64, num_locales: u32, max_item_bytes: u64) -> Self {
        let items_per_locale = total_items / num_locales as u64 + 1;
        let input_bytes = items_per_locale * max_item_bytes;
        let output_bytes = items_per_locale * max_item_bytes;
        let metadata_bytes = items_per_locale * 9; // 8 bytes size_t + 1 byte bool
        let total_bytes = input_bytes + output_bytes + metadata_bytes;
        let total_mb = total_bytes.div_ceil(1_048_576);

        Self {
            items_per_locale,
            input_bytes,
            output_bytes,
            metadata_bytes,
            total_bytes,
            total_mb,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn per_item_partition_is_valid() {
        let p = Partition::per_item(100, 4);
        assert!(p.verify(), "per-item partition should be valid");
        assert_eq!(p.slices.len(), 4);
        // 100 / 4 = 25 each
        assert_eq!(p.slices[0].count, 25);
        assert_eq!(p.slices[3].count, 25);
    }

    #[test]
    fn per_item_partition_handles_remainder() {
        let p = Partition::per_item(10, 3);
        assert!(p.verify());
        // 10 / 3 = 3 base, 1 remainder → first locale gets 4, others get 3
        assert_eq!(p.slices[0].count, 4);
        assert_eq!(p.slices[1].count, 3);
        assert_eq!(p.slices[2].count, 3);
    }

    #[test]
    fn chunked_partition_is_valid() {
        let p = Partition::chunked(100, 4, 10);
        assert!(p.verify(), "chunked partition should be valid");
    }

    #[test]
    fn gather_conservation() {
        let g = GatherResult {
            total_results: 100,
            locale_counts: vec![25, 25, 25, 25],
            strategy: GatherStrategy::Merge,
        };
        assert!(g.verify_conservation());
    }

    #[test]
    fn memory_budget_calculation() {
        let budget = MemoryBudget::calculate(500, 64, 10_485_760);
        // 500/64 + 1 = 8+1 = 9 items per locale (rounded)
        assert!(budget.items_per_locale > 0);
        assert!(budget.total_mb > 0);
        // With 10MB per item and ~9 items: ~180MB per locale
        assert!(budget.total_mb < 500, "should be reasonable for 9 items");
    }

    #[test]
    fn partition_strategy_parsing() {
        assert_eq!(
            PartitionStrategy::from_str("per-item"),
            Some(PartitionStrategy::PerItem)
        );
        assert_eq!(
            PartitionStrategy::from_str("adaptive"),
            Some(PartitionStrategy::Adaptive)
        );
        assert_eq!(PartitionStrategy::from_str("invalid"), None);
    }

    // -----------------------------------------------------------------------
    // Additional partition tests
    // -----------------------------------------------------------------------

    /// Partition 1 item across many locales — only the first locale gets the
    /// item, all others get zero-length slices. The partition must still be
    /// complete and non-overlapping.
    #[test]
    fn per_item_partition_1_item_many_locales() {
        let p = Partition::per_item(1, 16);
        assert!(p.verify(), "1 item across 16 locales should be valid");
        assert_eq!(p.slices.len(), 16);
        // Exactly one locale gets the item
        assert_eq!(p.slices[0].count, 1, "First locale should get the 1 item");
        for s in &p.slices[1..] {
            assert_eq!(s.count, 0, "Remaining locales should have 0 items");
        }
    }

    /// Partition a prime number of items — ensures the remainder distribution
    /// is correct (first N%K locales get one extra).
    #[test]
    fn per_item_partition_prime_items() {
        // 97 items across 8 locales: 97/8 = 12 base, 97%8 = 1 remainder
        let p = Partition::per_item(97, 8);
        assert!(p.verify(), "97 items across 8 locales should be valid");
        assert_eq!(p.slices.len(), 8);
        assert_eq!(p.slices[0].count, 13, "First locale gets 12+1 = 13");
        for s in &p.slices[1..] {
            assert_eq!(s.count, 12, "Remaining locales get 12 each");
        }
        // Verify total: 13 + 7*12 = 13 + 84 = 97
        let total: u64 = p.slices.iter().map(|s| s.count).sum();
        assert_eq!(total, 97);
    }

    /// Another prime: 13 items across 5 locales (13/5 = 2 base, 3 remainder).
    #[test]
    fn per_item_partition_prime_items_2() {
        let p = Partition::per_item(13, 5);
        assert!(p.verify());
        // First 3 locales get 3, last 2 get 2
        assert_eq!(p.slices[0].count, 3);
        assert_eq!(p.slices[1].count, 3);
        assert_eq!(p.slices[2].count, 3);
        assert_eq!(p.slices[3].count, 2);
        assert_eq!(p.slices[4].count, 2);
    }

    /// Chunked partition with 1 item — single chunk, single locale gets it.
    #[test]
    fn chunked_partition_1_item() {
        let p = Partition::chunked(1, 4, 10);
        assert!(p.verify(), "Chunked partition of 1 item should be valid");
        let non_empty: Vec<_> = p.slices.iter().filter(|s| s.count > 0).collect();
        assert_eq!(non_empty.len(), 1, "Only one locale should have the item");
        assert_eq!(non_empty[0].count, 1);
    }

    /// Chunked partition where grain_size > total_items.
    #[test]
    fn chunked_partition_large_grain() {
        let p = Partition::chunked(5, 4, 100);
        assert!(
            p.verify(),
            "Chunked partition with large grain should be valid"
        );
        // All items in one chunk on one locale
        let total: u64 = p.slices.iter().map(|s| s.count).sum();
        assert_eq!(total, 5);
    }

    // -----------------------------------------------------------------------
    // Additional GatherResult tests
    // -----------------------------------------------------------------------

    /// GatherResult with 0 total results and empty locale_counts.
    #[test]
    fn gather_result_zero_results() {
        let g = GatherResult {
            total_results: 0,
            locale_counts: vec![],
            strategy: GatherStrategy::Merge,
        };
        assert!(
            g.verify_conservation(),
            "0 results with empty locale_counts should be conserved"
        );
    }

    /// GatherResult with 0 total results but non-empty (all zero) locale_counts.
    #[test]
    fn gather_result_zero_results_many_locales() {
        let g = GatherResult {
            total_results: 0,
            locale_counts: vec![0, 0, 0, 0],
            strategy: GatherStrategy::Reduce,
        };
        assert!(
            g.verify_conservation(),
            "0 results across 4 locales should be conserved"
        );
    }

    /// GatherResult conservation fails when total_results != sum(locale_counts).
    #[test]
    fn gather_result_conservation_fails() {
        let g = GatherResult {
            total_results: 100,
            locale_counts: vec![25, 25, 25, 24], // sum=99, not 100
            strategy: GatherStrategy::Merge,
        };
        assert!(
            !g.verify_conservation(),
            "Mismatched total should fail conservation check"
        );
    }

    /// GatherResult with a single locale holding all results.
    #[test]
    fn gather_result_single_locale() {
        let g = GatherResult {
            total_results: 42,
            locale_counts: vec![42],
            strategy: GatherStrategy::First,
        };
        assert!(g.verify_conservation());
    }

    // -----------------------------------------------------------------------
    // Additional MemoryBudget tests
    // -----------------------------------------------------------------------

    /// MemoryBudget with 0 max_item_bytes — everything should be zero except
    /// the metadata overhead.
    #[test]
    fn memory_budget_zero_item_bytes() {
        let budget = MemoryBudget::calculate(100, 4, 0);
        assert_eq!(
            budget.input_bytes, 0,
            "0 max_item_bytes means 0 input buffer"
        );
        assert_eq!(
            budget.output_bytes, 0,
            "0 max_item_bytes means 0 output buffer"
        );
        assert!(
            budget.metadata_bytes > 0,
            "Metadata bytes should still be non-zero"
        );
        assert_eq!(
            budget.total_bytes, budget.metadata_bytes,
            "Total should be metadata only"
        );
    }

    /// MemoryBudget with 1 locale — all items on one node.
    #[test]
    fn memory_budget_single_locale() {
        let budget = MemoryBudget::calculate(100, 1, 1024);
        // items_per_locale = 100/1 + 1 = 101
        assert_eq!(budget.items_per_locale, 101);
        assert_eq!(budget.input_bytes, 101 * 1024);
        assert_eq!(budget.output_bytes, 101 * 1024);
    }

    /// MemoryBudget with very large item size — check total_mb calculation.
    #[test]
    fn memory_budget_large_items() {
        // 10 items, 2 locales, 100MB per item
        let budget = MemoryBudget::calculate(10, 2, 100 * 1_048_576);
        // items_per_locale = 10/2 + 1 = 6
        assert_eq!(budget.items_per_locale, 6);
        // input = 6 * 100MB = 600MB, output = 600MB, meta = 6*9 = 54
        assert_eq!(budget.input_bytes, 6 * 100 * 1_048_576);
        assert!(budget.total_mb >= 1200, "Should be at least 1200MB");
    }

    /// MemoryBudget with 1 item and many locales — items_per_locale should be 1.
    #[test]
    fn memory_budget_1_item_many_locales() {
        let budget = MemoryBudget::calculate(1, 100, 4096);
        // items_per_locale = 1/100 + 1 = 0 + 1 = 1
        assert_eq!(budget.items_per_locale, 1);
        assert_eq!(budget.input_bytes, 4096);
        assert_eq!(budget.output_bytes, 4096);
    }

    // -----------------------------------------------------------------------
    // Additional strategy parsing tests
    // -----------------------------------------------------------------------

    /// All five partition strategy strings parse correctly.
    #[test]
    fn partition_strategy_all_valid() {
        let pairs = [
            ("per-item", PartitionStrategy::PerItem),
            ("chunk", PartitionStrategy::Chunk),
            ("adaptive", PartitionStrategy::Adaptive),
            ("spatial", PartitionStrategy::Spatial),
            ("keyed", PartitionStrategy::Keyed),
        ];
        for (s, expected) in &pairs {
            assert_eq!(
                PartitionStrategy::from_str(s),
                Some(*expected),
                "'{s}' should parse to {expected:?}"
            );
        }
    }

    /// All five gather strategy strings parse correctly.
    #[test]
    fn gather_strategy_all_valid() {
        let pairs = [
            ("merge", GatherStrategy::Merge),
            ("reduce", GatherStrategy::Reduce),
            ("tree-reduce", GatherStrategy::TreeReduce),
            ("stream", GatherStrategy::Stream),
            ("first", GatherStrategy::First),
        ];
        for (s, expected) in &pairs {
            assert_eq!(
                GatherStrategy::from_str(s),
                Some(*expected),
                "'{s}' should parse to {expected:?}"
            );
        }
    }

    /// Invalid strategy strings return None for both partition and gather.
    #[test]
    fn strategy_parsing_rejects_invalid() {
        let invalids = ["", "MERGE", "per_item", "Per-Item", "tree_reduce", " merge"];
        for s in &invalids {
            assert_eq!(
                PartitionStrategy::from_str(s),
                None,
                "Partition should reject '{s}'"
            );
            assert_eq!(
                GatherStrategy::from_str(s),
                None,
                "Gather should reject '{s}'"
            );
        }
    }
}
