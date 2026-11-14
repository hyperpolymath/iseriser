// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Kernel description parser for futharkiser.
//
// Parses raw `[[kernels]]` TOML entries into validated `KernelConfig` values,
// checking SOAC patterns, Futhark types, operator requirements, and bin counts.
// This is the bridge between the TOML manifest and the code generator.

use anyhow::{Context, Result, bail};

use crate::abi::{FutharkType, KernelConfig, SOAC};
use crate::manifest::{self, Manifest, RawKernelConfig};

/// Parse all kernel definitions from a manifest into validated `KernelConfig`
/// values. This calls `manifest::validate()` first, then does the type-level
/// conversion from raw strings to ABI types.
pub fn parse_and_validate(manifest: &Manifest) -> Result<Vec<KernelConfig>> {
    manifest::validate(manifest).context("Manifest validation failed")?;
    manifest::parse_kernels(manifest).context("Kernel parsing failed")
}

/// Parse a single raw kernel config into a validated `KernelConfig`.
/// Useful for testing individual kernel definitions in isolation.
pub fn parse_single_kernel(raw: &RawKernelConfig) -> Result<KernelConfig> {
    let pattern = manifest::parse_pattern(&raw.pattern)?;
    let input_type = FutharkType::from_array_str(&raw.input_type).ok_or_else(|| {
        anyhow::anyhow!(
            "Unrecognised input-type '{}'. Valid: {:?}",
            raw.input_type,
            FutharkType::all_names()
        )
    })?;
    let output_type = FutharkType::from_array_str(&raw.output_type).ok_or_else(|| {
        anyhow::anyhow!(
            "Unrecognised output-type '{}'. Valid: {:?}",
            raw.output_type,
            FutharkType::all_names()
        )
    })?;

    // Pattern-specific validation.
    match pattern {
        SOAC::Reduce | SOAC::Scan => {
            if raw.operator.is_none() {
                bail!(
                    "Kernel '{}': {} pattern requires an operator",
                    raw.name,
                    pattern
                );
            }
        }
        SOAC::Histogram if (raw.bins.is_none() || raw.bins == Some(0)) => {
            bail!("Kernel '{}': histogram pattern requires bins > 0", raw.name);
        }
        _ => {}
    }

    Ok(KernelConfig {
        name: raw.name.clone(),
        pattern,
        input_type,
        output_type,
        description: raw.description.clone(),
        operator: raw.operator.clone(),
        bins: raw.bins,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper to build a `RawKernelConfig` with sensible defaults.
    fn raw_kernel(name: &str, pattern: &str, in_ty: &str, out_ty: &str) -> RawKernelConfig {
        RawKernelConfig {
            name: name.to_string(),
            pattern: pattern.to_string(),
            input_type: in_ty.to_string(),
            output_type: out_ty.to_string(),
            description: String::new(),
            operator: None,
            bins: None,
        }
    }

    #[test]
    fn test_parse_map_kernel() {
        let raw = raw_kernel("blur", "map", "[f32]", "[f32]");
        let kc = parse_single_kernel(&raw).expect("TODO: handle error");
        assert_eq!(kc.pattern, SOAC::Map);
        assert_eq!(kc.input_type, FutharkType::F32);
        assert_eq!(kc.output_type, FutharkType::F32);
    }

    #[test]
    fn test_parse_reduce_kernel() {
        let mut raw = raw_kernel("sum", "reduce", "[f64]", "[f64]");
        raw.operator = Some("+".to_string());
        let kc = parse_single_kernel(&raw).expect("TODO: handle error");
        assert_eq!(kc.pattern, SOAC::Reduce);
        assert_eq!(kc.operator, Some("+".to_string()));
    }

    #[test]
    fn test_parse_scan_kernel() {
        let mut raw = raw_kernel("prefix", "scan", "[i32]", "[i32]");
        raw.operator = Some("+".to_string());
        let kc = parse_single_kernel(&raw).expect("TODO: handle error");
        assert_eq!(kc.pattern, SOAC::Scan);
    }

    #[test]
    fn test_parse_scatter_kernel() {
        let raw = raw_kernel("write", "scatter", "[f32]", "[f32]");
        let kc = parse_single_kernel(&raw).expect("TODO: handle error");
        assert_eq!(kc.pattern, SOAC::Scatter);
    }

    #[test]
    fn test_parse_histogram_kernel() {
        let mut raw = raw_kernel("hist", "histogram", "[u8]", "[i64]");
        raw.bins = Some(256);
        let kc = parse_single_kernel(&raw).expect("TODO: handle error");
        assert_eq!(kc.pattern, SOAC::Histogram);
        assert_eq!(kc.bins, Some(256));
    }

    #[test]
    fn test_reduce_without_operator_fails() {
        let raw = raw_kernel("bad", "reduce", "[f32]", "[f32]");
        assert!(parse_single_kernel(&raw).is_err());
    }

    #[test]
    fn test_histogram_without_bins_fails() {
        let raw = raw_kernel("bad", "histogram", "[u8]", "[i64]");
        assert!(parse_single_kernel(&raw).is_err());
    }

    #[test]
    fn test_invalid_type_fails() {
        let raw = raw_kernel("bad", "map", "[complex64]", "[f32]");
        assert!(parse_single_kernel(&raw).is_err());
    }

    #[test]
    fn test_invalid_pattern_fails() {
        let raw = raw_kernel("bad", "flatmap", "[f32]", "[f32]");
        assert!(parse_single_kernel(&raw).is_err());
    }
}
