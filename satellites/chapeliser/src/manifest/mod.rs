// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Manifest parser and validator for chapeliser.toml.
// The manifest describes a workload to be distributed across Chapel locales.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Top-level manifest structure, parsed from chapeliser.toml.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Describes the workload to distribute.
    pub workload: WorkloadConfig,
    /// Data types flowing through the pipeline.
    pub data: DataConfig,
    /// Scaling parameters for Chapel distribution.
    pub scaling: ScalingConfig,
    /// Optional fault tolerance settings.
    #[serde(default)]
    pub resilience: ResilienceConfig,
    /// Optional Chapel-specific overrides.
    #[serde(default)]
    pub chapel: ChapelConfig,
}

/// Workload description — what function to distribute and how to split/gather.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkloadConfig {
    /// Human-readable workload name (used in generated code and logs).
    pub name: String,
    /// Entry point: "src/file.rs::function_name" or "src/file.zig:functionName".
    /// Chapeliser analyses this to understand the function signature.
    pub entry: String,
    /// How to partition work across locales. See `PartitionStrategy`.
    pub partition: String,
    /// How to combine results from all locales. See `GatherStrategy`.
    pub gather: String,
    /// Optional: explicit list of dependencies the entry function needs.
    /// If omitted, Chapeliser infers from the source.
    #[serde(default)]
    pub dependencies: Vec<String>,
}

/// Data type configuration — what flows in and out of the distributed workload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataConfig {
    /// Rust/C/Zig type of the input collection (e.g., "Vec<PathBuf>").
    #[serde(rename = "input-type")]
    pub input_type: String,
    /// Rust/C/Zig type of a single input item (e.g., "PathBuf").
    /// If omitted, inferred from input-type by stripping the collection wrapper.
    #[serde(rename = "item-type", default)]
    pub item_type: Option<String>,
    /// Rust/C/Zig type of the output collection (e.g., "Vec<ScanResult>").
    #[serde(rename = "output-type")]
    pub output_type: String,
    /// Serialization format for sending data between locales.
    /// Options: "bincode", "messagepack", "cbor", "json", "flatbuffers", "raw".
    #[serde(default = "default_serialization")]
    pub serialization: String,
    /// Optional: maximum size hint for a single item in bytes.
    /// Used for buffer pre-allocation and chunk sizing.
    #[serde(rename = "max-item-bytes", default)]
    pub max_item_bytes: Option<usize>,
}

/// Scaling parameters — how many nodes, how to split work.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScalingConfig {
    /// Minimum locales (nodes). Usually 1 for local-only mode.
    #[serde(rename = "min-nodes", default = "default_min_nodes")]
    pub min_nodes: u32,
    /// Maximum locales. Chapel will use up to this many.
    #[serde(rename = "max-nodes", default = "default_max_nodes")]
    pub max_nodes: u32,
    /// Items per Chapel task. Smaller = more parallelism, larger = less overhead.
    #[serde(rename = "grain-size", default = "default_grain_size")]
    pub grain_size: u32,
    /// Optional: expected total item count (helps pre-plan distribution).
    #[serde(rename = "expected-items", default)]
    pub expected_items: Option<u64>,
}

/// Fault tolerance settings — how to handle node failures and task retries.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResilienceConfig {
    /// Number of times to retry a failed task before giving up.
    #[serde(default = "default_retries")]
    pub retries: u32,
    /// Whether to checkpoint intermediate results for resumability.
    #[serde(default)]
    pub checkpoint: bool,
    /// Checkpoint interval in seconds (if checkpointing is enabled).
    #[serde(
        rename = "checkpoint-interval-secs",
        default = "default_checkpoint_interval"
    )]
    pub checkpoint_interval_secs: u64,
    /// Whether to redistribute work from failed nodes to surviving ones.
    #[serde(default = "default_true")]
    pub redistribute_on_failure: bool,
}

/// Chapel-specific overrides for advanced users.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ChapelConfig {
    /// Extra Chapel compiler flags (e.g., "--fast", "--cache-remote").
    #[serde(rename = "compiler-flags", default)]
    pub compiler_flags: Vec<String>,
    /// Chapel communication layer: "gasnet-ibv", "gasnet-udp", "ofi", "ugni".
    #[serde(rename = "comm-layer", default)]
    pub comm_layer: Option<String>,
    /// Whether to use Chapel's GPU locale model (experimental).
    #[serde(rename = "gpu-enabled", default)]
    pub gpu_enabled: bool,
}

// -- Default value functions --

fn default_serialization() -> String {
    "bincode".to_string()
}
fn default_min_nodes() -> u32 {
    1
}
fn default_max_nodes() -> u32 {
    64
}
fn default_grain_size() -> u32 {
    50
}
fn default_retries() -> u32 {
    3
}
fn default_checkpoint_interval() -> u64 {
    300
}
fn default_true() -> bool {
    true
}

impl Default for ResilienceConfig {
    fn default() -> Self {
        Self {
            retries: default_retries(),
            checkpoint: false,
            checkpoint_interval_secs: default_checkpoint_interval(),
            redistribute_on_failure: true,
        }
    }
}

/// Load and parse a chapeliser.toml manifest from disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    let manifest: Manifest =
        toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))?;
    Ok(manifest)
}

/// Validate that a parsed manifest is internally consistent.
/// Checks partition/gather strategy names, type compatibility, and scaling bounds.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Validate partition strategy name
    let valid_partitions = ["per-item", "chunk", "adaptive", "spatial", "keyed"];
    if !valid_partitions.contains(&manifest.workload.partition.as_str()) {
        bail!(
            "Unknown partition strategy '{}'. Valid: {:?}",
            manifest.workload.partition,
            valid_partitions
        );
    }

    // Validate gather strategy name
    let valid_gathers = ["merge", "reduce", "tree-reduce", "stream", "first"];
    if !valid_gathers.contains(&manifest.workload.gather.as_str()) {
        bail!(
            "Unknown gather strategy '{}'. Valid: {:?}",
            manifest.workload.gather,
            valid_gathers
        );
    }

    // Validate serialization format
    let valid_serialization = [
        "bincode",
        "messagepack",
        "cbor",
        "json",
        "flatbuffers",
        "raw",
    ];
    if !valid_serialization.contains(&manifest.data.serialization.as_str()) {
        bail!(
            "Unknown serialization format '{}'. Valid: {:?}",
            manifest.data.serialization,
            valid_serialization
        );
    }

    // Validate scaling bounds
    if manifest.scaling.min_nodes == 0 {
        bail!("min-nodes must be at least 1");
    }
    if manifest.scaling.max_nodes < manifest.scaling.min_nodes {
        bail!(
            "max-nodes ({}) must be >= min-nodes ({})",
            manifest.scaling.max_nodes,
            manifest.scaling.min_nodes
        );
    }
    if manifest.scaling.grain_size == 0 {
        bail!("grain-size must be at least 1");
    }

    // Validate entry point format: must contain "::" for Rust or ":" for Zig/C
    if !manifest.workload.entry.contains("::") && !manifest.workload.entry.contains(':') {
        bail!(
            "Entry point '{}' must be in format 'path/to/file.rs::function' or 'path/to/file.zig:function'",
            manifest.workload.entry
        );
    }

    // Spatial partition requires at least 2D data — warn if input type looks 1D
    if manifest.workload.partition == "spatial"
        && !manifest.data.input_type.contains("Matrix")
        && !manifest.data.input_type.contains("Grid")
        && !manifest.data.input_type.contains("Array2")
    {
        eprintln!(
            "Warning: spatial partition is typically used with 2D/3D data, but input-type is '{}'. \
             If your data is 1D, consider 'chunk' or 'per-item' instead.",
            manifest.data.input_type
        );
    }

    Ok(())
}

/// Create a starter chapeliser.toml in the given directory.
/// Analyses the project to suggest reasonable defaults.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("chapeliser.toml");
    if manifest_path.exists() {
        bail!(
            "chapeliser.toml already exists at {}",
            manifest_path.display()
        );
    }

    let template = r#"# Chapeliser manifest — describes a workload for Chapel distribution.
# See https://github.com/hyperpolymath/chapeliser for documentation.

[workload]
name = "my-workload"
entry = "src/lib.rs::process_batch"   # function to distribute
partition = "per-item"                 # per-item | chunk | adaptive | spatial | keyed
gather = "merge"                       # merge | reduce | tree-reduce | stream | first

[data]
input-type = "Vec<PathBuf>"            # collection type to distribute
output-type = "Vec<Result>"            # collection type to gather
serialization = "bincode"              # bincode | messagepack | cbor | json | flatbuffers | raw

[scaling]
min-nodes = 1                          # minimum Chapel locales
max-nodes = 64                         # maximum Chapel locales
grain-size = 50                        # items per Chapel task

[resilience]
retries = 3                            # retry failed tasks N times
checkpoint = false                     # enable checkpointing for resumability
redistribute-on-failure = true         # move work from dead nodes to live ones

# [chapel]                             # Advanced: Chapel-specific overrides
# compiler-flags = ["--fast"]
# comm-layer = "gasnet-udp"
# gpu-enabled = false
"#;

    std::fs::write(&manifest_path, template)
        .with_context(|| format!("Failed to write {}", manifest_path.display()))?;
    println!("Created {}", manifest_path.display());
    println!("Edit the manifest to describe your workload, then run: chapeliser generate");
    Ok(())
}

/// Print information about a parsed manifest.
pub fn print_info(manifest: &Manifest) {
    println!("=== Chapeliser Workload: {} ===", manifest.workload.name);
    println!();
    println!("Entry point:   {}", manifest.workload.entry);
    println!("Partition:     {}", manifest.workload.partition);
    println!("Gather:        {}", manifest.workload.gather);
    println!();
    println!("Input type:    {}", manifest.data.input_type);
    println!("Output type:   {}", manifest.data.output_type);
    println!("Serialization: {}", manifest.data.serialization);
    println!();
    println!(
        "Scaling:       {}-{} nodes, grain size {}",
        manifest.scaling.min_nodes, manifest.scaling.max_nodes, manifest.scaling.grain_size
    );

    if let Some(expected) = manifest.scaling.expected_items {
        let tasks = expected / manifest.scaling.grain_size as u64;
        let ideal_nodes = tasks.min(manifest.scaling.max_nodes as u64);
        println!(
            "Expected:      {} items → ~{} tasks → ideal {} nodes",
            expected, tasks, ideal_nodes
        );
    }

    println!();
    println!(
        "Resilience:    {} retries, checkpoint={}, redistribute={}",
        manifest.resilience.retries,
        manifest.resilience.checkpoint,
        manifest.resilience.redistribute_on_failure
    );
}

/// Print available partition and gather strategies.
pub fn print_strategies() {
    println!("=== Partition Strategies ===");
    println!();
    println!("  per-item    One item per Chapel task. Best for: file scanning, image processing.");
    println!("  chunk       Fixed-size chunks. Best for: data pipelines, ETL.");
    println!("  adaptive    Dynamic load balancing. Best for: heterogeneous workloads.");
    println!("  spatial     Domain decomposition. Best for: simulations, matrices.");
    println!("  keyed       Group by key. Best for: map-reduce, aggregation.");
    println!();
    println!("=== Gather Strategies ===");
    println!();
    println!("  merge        Concatenate all results into output collection.");
    println!("  reduce       Apply reduction function (sum, max, min, custom).");
    println!("  tree-reduce  Logarithmic reduction for associative operations.");
    println!("  stream       Results stream back to coordinator as they complete.");
    println!("  first        Return first successful result (for search workloads).");
}
