// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for futharkiser.toml.
//
// A futharkiser manifest declares a project with one or more GPU kernels.
// Each kernel specifies a SOAC pattern (map, reduce, scan, scatter, histogram),
// input/output array types, and optional parameters like reduction operators
// or histogram bin counts. The `[gpu]` section selects the compilation backend.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::abi::{FutharkType, GPUBackend, KernelConfig, SOAC};

// ---------------------------------------------------------------------------
// Top-level manifest structure (mirrors futharkiser.toml)
// ---------------------------------------------------------------------------

/// Top-level futharkiser manifest, deserialised from `futharkiser.toml`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata.
    pub project: ProjectConfig,
    /// One or more kernel definitions.
    #[serde(rename = "kernels")]
    pub kernels: Vec<RawKernelConfig>,
    /// GPU compilation settings.
    #[serde(default)]
    pub gpu: GpuConfig,
}

/// Project-level metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Human-readable project name.
    pub name: String,
}

/// Raw (unvalidated) kernel descriptor as it appears in TOML. Validation and
/// type resolution happen in `parse_kernels()`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawKernelConfig {
    /// Unique kernel name (becomes the Futhark `entry` function name).
    pub name: String,
    /// SOAC pattern: "map", "reduce", "scan", "scatter", or "histogram".
    pub pattern: String,
    /// Input array type in bracket notation, e.g. `[f32]`.
    #[serde(rename = "input-type")]
    pub input_type: String,
    /// Output array type in bracket notation, e.g. `[f32]`.
    #[serde(rename = "output-type")]
    pub output_type: String,
    /// Human-readable description (optional, defaults to empty string).
    #[serde(default)]
    pub description: String,
    /// Binary operator for reduce/scan patterns (e.g. "+", "*").
    #[serde(default)]
    pub operator: Option<String>,
    /// Number of histogram bins (required for histogram pattern).
    #[serde(default)]
    pub bins: Option<u64>,
}

/// GPU compilation settings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GpuConfig {
    /// Target backend: "opencl", "cuda", "multicore", or "c".
    #[serde(default = "default_backend")]
    pub backend: String,
    /// Whether to run Futhark's auto-tuner after compilation.
    #[serde(default)]
    pub tuning: bool,
}

impl Default for GpuConfig {
    fn default() -> Self {
        GpuConfig {
            backend: "opencl".to_string(),
            tuning: false,
        }
    }
}

/// Default backend when `[gpu]` section is absent.
fn default_backend() -> String {
    "opencl".to_string()
}

// ---------------------------------------------------------------------------
// Loading and validation
// ---------------------------------------------------------------------------

/// Load a manifest from a TOML file on disk.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate the manifest: checks project name, kernel definitions, types,
/// patterns, and GPU backend. Returns an error on the first problem found.
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name must be non-empty.
    if manifest.project.name.trim().is_empty() {
        bail!("project.name is required and must be non-empty");
    }

    // Must define at least one kernel.
    if manifest.kernels.is_empty() {
        bail!("At least one [[kernels]] entry is required");
    }

    // Validate GPU backend.
    parse_backend(&manifest.gpu.backend)?;

    // Validate each kernel definition.
    let mut seen_names = std::collections::HashSet::new();
    for (index, kernel) in manifest.kernels.iter().enumerate() {
        validate_kernel(kernel, index, &mut seen_names)?;
    }

    Ok(())
}

/// Validate a single raw kernel descriptor.
fn validate_kernel(
    kernel: &RawKernelConfig,
    index: usize,
    seen_names: &mut std::collections::HashSet<String>,
) -> Result<()> {
    let ctx = format!("kernels[{}] (name='{}')", index, kernel.name);

    // Name must be non-empty and unique.
    if kernel.name.trim().is_empty() {
        bail!("{}: kernel name is required", ctx);
    }
    if !seen_names.insert(kernel.name.clone()) {
        bail!("{}: duplicate kernel name '{}'", ctx, kernel.name);
    }

    // Name must be a valid Futhark identifier (alphanumeric + underscore).
    if !kernel
        .name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        bail!(
            "{}: kernel name must contain only alphanumeric characters and underscores",
            ctx
        );
    }

    // Pattern must be a recognised SOAC.
    let pattern = parse_pattern(&kernel.pattern)
        .with_context(|| format!("{}: invalid pattern '{}'", ctx, kernel.pattern))?;

    // Input and output types must be valid Futhark array types.
    FutharkType::from_array_str(&kernel.input_type).ok_or_else(|| {
        anyhow::anyhow!(
            "{}: unrecognised input-type '{}'. Valid types: {:?}",
            ctx,
            kernel.input_type,
            FutharkType::all_names()
        )
    })?;

    FutharkType::from_array_str(&kernel.output_type).ok_or_else(|| {
        anyhow::anyhow!(
            "{}: unrecognised output-type '{}'. Valid types: {:?}",
            ctx,
            kernel.output_type,
            FutharkType::all_names()
        )
    })?;

    // Pattern-specific checks.
    match pattern {
        SOAC::Reduce | SOAC::Scan => {
            if kernel.operator.is_none() {
                bail!(
                    "{}: '{}' pattern requires an 'operator' field (e.g. \"+\", \"*\")",
                    ctx,
                    pattern
                );
            }
        }
        SOAC::Histogram if (kernel.bins.is_none() || kernel.bins == Some(0)) => {
            bail!(
                "{}: 'histogram' pattern requires a 'bins' field with a positive integer",
                ctx
            );
        }
        _ => {}
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

/// Parse a pattern string into a `SOAC` enum variant.
pub fn parse_pattern(s: &str) -> Result<SOAC> {
    match s.trim().to_lowercase().as_str() {
        "map" => Ok(SOAC::Map),
        "reduce" => Ok(SOAC::Reduce),
        "scan" => Ok(SOAC::Scan),
        "scatter" => Ok(SOAC::Scatter),
        "histogram" => Ok(SOAC::Histogram),
        other => bail!(
            "Unknown SOAC pattern '{}'. Valid patterns: {:?}",
            other,
            SOAC::all_names()
        ),
    }
}

/// Parse a backend string into a `GPUBackend` enum variant.
pub fn parse_backend(s: &str) -> Result<GPUBackend> {
    match s.trim().to_lowercase().as_str() {
        "opencl" => Ok(GPUBackend::OpenCL),
        "cuda" => Ok(GPUBackend::CUDA),
        "multicore" => Ok(GPUBackend::Multicore),
        "c" => Ok(GPUBackend::C),
        other => bail!(
            "Unknown GPU backend '{}'. Valid backends: {:?}",
            other,
            GPUBackend::all_names()
        ),
    }
}

/// Convert all raw kernel configs in a manifest into validated `KernelConfig`
/// values. Call `validate()` first to get human-readable errors; this function
/// assumes the manifest has already passed validation.
pub fn parse_kernels(manifest: &Manifest) -> Result<Vec<KernelConfig>> {
    manifest
        .kernels
        .iter()
        .map(|raw| {
            let pattern = parse_pattern(&raw.pattern)?;
            let input_type = FutharkType::from_array_str(&raw.input_type)
                .ok_or_else(|| anyhow::anyhow!("Bad input-type: {}", raw.input_type))?;
            let output_type = FutharkType::from_array_str(&raw.output_type)
                .ok_or_else(|| anyhow::anyhow!("Bad output-type: {}", raw.output_type))?;
            Ok(KernelConfig {
                name: raw.name.clone(),
                pattern,
                input_type,
                output_type,
                description: raw.description.clone(),
                operator: raw.operator.clone(),
                bins: raw.bins,
            })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// Init — create a new futharkiser.toml
// ---------------------------------------------------------------------------

/// Create a new `futharkiser.toml` manifest with a sensible example that
/// demonstrates all five SOAC patterns.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("futharkiser.toml");
    if manifest_path.exists() {
        bail!(
            "futharkiser.toml already exists at {}",
            manifest_path.display()
        );
    }
    let template = r#"# futharkiser manifest — GPU kernel definitions
# See https://github.com/hyperpolymath/futharkiser for documentation.

[project]
name = "my-project"

[[kernels]]
name = "transform"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
description = "Element-wise transformation"

[[kernels]]
name = "total"
pattern = "reduce"
input-type = "[f64]"
output-type = "[f64]"
operator = "+"
description = "Sum all elements"

[gpu]
backend = "opencl"
tuning = false
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

// ---------------------------------------------------------------------------
// Info — pretty-print manifest contents
// ---------------------------------------------------------------------------

/// Print a human-readable summary of the manifest to stdout.
pub fn print_info(manifest: &Manifest) {
    println!("=== {} ===", manifest.project.name);
    println!(
        "Backend: {} (tuning: {})",
        manifest.gpu.backend, manifest.gpu.tuning
    );
    println!("Kernels: {}", manifest.kernels.len());
    for (i, k) in manifest.kernels.iter().enumerate() {
        println!(
            "  [{}] {} — {} ({} -> {})",
            i, k.name, k.pattern, k.input_type, k.output_type
        );
        if !k.description.is_empty() {
            println!("      {}", k.description);
        }
        if let Some(ref op) = k.operator {
            println!("      operator: {}", op);
        }
        if let Some(bins) = k.bins {
            println!("      bins: {}", bins);
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: create a minimal valid manifest TOML string.
    fn minimal_toml() -> String {
        r#"
[project]
name = "test"

[[kernels]]
name = "k1"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"

[gpu]
backend = "c"
"#
        .to_string()
    }

    #[test]
    fn test_parse_minimal_manifest() {
        let m: Manifest = toml::from_str(&minimal_toml()).expect("TODO: handle error");
        assert_eq!(m.project.name, "test");
        assert_eq!(m.kernels.len(), 1);
        assert_eq!(m.kernels[0].name, "k1");
        assert_eq!(m.gpu.backend, "c");
    }

    #[test]
    fn test_validate_minimal() {
        let m: Manifest = toml::from_str(&minimal_toml()).expect("TODO: handle error");
        validate(&m).expect("minimal manifest should be valid");
    }

    #[test]
    fn test_validate_empty_project_name() {
        let toml_str = r#"
[project]
name = ""
[[kernels]]
name = "k"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_reduce_requires_operator() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "sum"
pattern = "reduce"
input-type = "[f64]"
output-type = "[f64]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("operator"));
    }

    #[test]
    fn test_validate_histogram_requires_bins() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "hist"
pattern = "histogram"
input-type = "[u8]"
output-type = "[i64]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("bins"));
    }

    #[test]
    fn test_validate_bad_pattern() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "k"
pattern = "flatmap"
input-type = "[f32]"
output-type = "[f32]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_bad_type() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "k"
pattern = "map"
input-type = "[string]"
output-type = "[f32]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_validate_duplicate_names() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "dup"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
[[kernels]]
name = "dup"
pattern = "map"
input-type = "[i32]"
output-type = "[i32]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("duplicate"));
    }

    #[test]
    fn test_parse_kernels() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "blur"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
description = "Gaussian blur"
[[kernels]]
name = "total"
pattern = "reduce"
input-type = "[f64]"
output-type = "[f64]"
operator = "+"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        let kernels = parse_kernels(&m).expect("TODO: handle error");
        assert_eq!(kernels.len(), 2);
        assert_eq!(kernels[0].pattern, SOAC::Map);
        assert_eq!(kernels[0].input_type, FutharkType::F32);
        assert_eq!(kernels[1].pattern, SOAC::Reduce);
        assert_eq!(kernels[1].operator, Some("+".to_string()));
    }

    #[test]
    fn test_parse_all_backends() {
        assert_eq!(
            parse_backend("opencl").expect("TODO: handle error"),
            GPUBackend::OpenCL
        );
        assert_eq!(
            parse_backend("cuda").expect("TODO: handle error"),
            GPUBackend::CUDA
        );
        assert_eq!(
            parse_backend("multicore").expect("TODO: handle error"),
            GPUBackend::Multicore
        );
        assert_eq!(
            parse_backend("c").expect("TODO: handle error"),
            GPUBackend::C
        );
        assert!(parse_backend("vulkan").is_err());
    }

    #[test]
    fn test_parse_all_patterns() {
        assert_eq!(parse_pattern("map").expect("TODO: handle error"), SOAC::Map);
        assert_eq!(
            parse_pattern("reduce").expect("TODO: handle error"),
            SOAC::Reduce
        );
        assert_eq!(
            parse_pattern("scan").expect("TODO: handle error"),
            SOAC::Scan
        );
        assert_eq!(
            parse_pattern("scatter").expect("TODO: handle error"),
            SOAC::Scatter
        );
        assert_eq!(
            parse_pattern("histogram").expect("TODO: handle error"),
            SOAC::Histogram
        );
    }

    #[test]
    fn test_default_gpu_config() {
        let toml_str = r#"
[project]
name = "test"
[[kernels]]
name = "k"
pattern = "map"
input-type = "[f32]"
output-type = "[f32]"
"#;
        let m: Manifest = toml::from_str(toml_str).expect("TODO: handle error");
        assert_eq!(m.gpu.backend, "opencl");
        assert!(!m.gpu.tuning);
    }
}
