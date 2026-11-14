// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Pipeline parser and validator for halideiser.
//
// Validates the sequence of pipeline stages, resolves default parameters,
// and produces a `ResolvedPipeline` that the Halide code generator can
// directly consume.

use anyhow::{Result, bail};

use crate::abi::{
    HalideOperation, HardwareTarget, PipelineStage, SchedulePrimitive, validate_stage,
};
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// ResolvedPipeline — fully validated and defaulted pipeline
// ---------------------------------------------------------------------------

/// A fully resolved pipeline ready for Halide code generation.
/// All defaults have been applied and all stages validated.
#[derive(Debug, Clone)]
pub struct ResolvedPipeline {
    /// The resolved stages with defaults filled in.
    pub stages: Vec<ResolvedStage>,
    /// Auto-generated schedule primitives for each stage.
    pub schedules: Vec<Vec<SchedulePrimitive>>,
}

/// A single resolved stage with all defaults applied.
#[derive(Debug, Clone)]
pub struct ResolvedStage {
    /// The pipeline stage with resolved parameters.
    pub stage: PipelineStage,
    /// The Halide Func name (derived from stage name).
    pub func_name: String,
    /// Halide Var names used by this stage.
    pub var_names: Vec<String>,
    /// Whether this stage uses a reduction domain (RDom).
    pub uses_rdom: bool,
}

// ---------------------------------------------------------------------------
// Resolution logic
// ---------------------------------------------------------------------------

/// Resolve a manifest into a fully validated pipeline.
/// This is the main entry point for the parser module.
///
/// Steps:
///   1. Validate each stage's parameters via `abi::validate_stage`
///   2. Apply default parameters where not specified
///   3. Generate auto-schedule primitives based on target
///   4. Check for inter-stage compatibility
pub fn resolve_pipeline(manifest: &Manifest) -> Result<ResolvedPipeline> {
    let mut resolved_stages = Vec::with_capacity(manifest.stages.len());
    let mut schedules = Vec::with_capacity(manifest.stages.len());

    for manifest_stage in &manifest.stages {
        // Convert to ABI type and validate.
        let mut pipeline_stage = manifest_stage.to_pipeline_stage();

        // Apply defaults for missing parameters.
        apply_defaults(&mut pipeline_stage);

        // Validate after defaults are applied.
        validate_stage(&pipeline_stage).map_err(|e| anyhow::anyhow!("{}", e))?;

        // Determine if this stage needs a reduction domain.
        let uses_rdom = stage_uses_rdom(&pipeline_stage.operation);

        // Determine Halide variable names.
        let var_names = stage_var_names(&pipeline_stage.operation);

        // Generate schedule primitives for this stage.
        let stage_schedule = auto_schedule(
            &pipeline_stage,
            &manifest.target.arch,
            manifest.target.vectorize,
            manifest.target.parallelize,
        );

        let func_name = pipeline_stage.name.clone();

        resolved_stages.push(ResolvedStage {
            stage: pipeline_stage,
            func_name,
            var_names,
            uses_rdom,
        });

        schedules.push(stage_schedule);
    }

    // Verify inter-stage compatibility.
    validate_stage_sequence(&resolved_stages)?;

    Ok(ResolvedPipeline {
        stages: resolved_stages,
        schedules,
    })
}

/// Apply default parameters for operations that have missing optional values.
fn apply_defaults(stage: &mut PipelineStage) {
    match &stage.operation {
        HalideOperation::Blur => {
            if stage.params.kernel_size.is_none() {
                stage.params.kernel_size = Some(3);
            }
            if stage.params.sigma.is_none() {
                // Default sigma based on kernel size: sigma = (kernel_size - 1) / 6.0
                let ks = stage.params.kernel_size.expect("TODO: handle error") as f64;
                stage.params.sigma = Some((ks - 1.0) / 6.0);
            }
        }
        HalideOperation::Sharpen => {
            if stage.params.kernel_size.is_none() {
                stage.params.kernel_size = Some(3);
            }
        }
        HalideOperation::EdgeDetect => {
            if stage.params.kernel_size.is_none() {
                stage.params.kernel_size = Some(3);
            }
        }
        HalideOperation::Convolve => {
            if stage.params.kernel_size.is_none() {
                stage.params.kernel_size = Some(3);
            }
        }
        HalideOperation::ColorConvert => {
            if stage.params.color_space.is_none() {
                stage.params.color_space = Some("grayscale".to_string());
            }
        }
        HalideOperation::Threshold => {
            // value is required, no default
        }
        HalideOperation::Resize => {
            // width/height: at least one is required, no defaults
        }
    }
}

/// Determine whether a Halide operation uses a reduction domain (RDom).
/// Operations that sum over a kernel window need RDom.
fn stage_uses_rdom(op: &HalideOperation) -> bool {
    matches!(
        op,
        HalideOperation::Blur | HalideOperation::Convolve | HalideOperation::EdgeDetect
    )
}

/// Return the Halide Var names used by a given operation.
/// Most 2D operations use (x, y, c); resize also uses (xo, yo).
fn stage_var_names(op: &HalideOperation) -> Vec<String> {
    match op {
        HalideOperation::Resize => {
            vec!["x".into(), "y".into(), "c".into()]
        }
        _ => {
            vec!["x".into(), "y".into(), "c".into()]
        }
    }
}

/// Generate automatic schedule primitives for a stage based on the target.
fn auto_schedule(
    stage: &PipelineStage,
    target: &HardwareTarget,
    vectorize: bool,
    parallelize: bool,
) -> Vec<SchedulePrimitive> {
    let mut sched = Vec::new();
    let vec_width = target.natural_vector_width();

    // Tile sizes depend on target: GPU prefers larger tiles, CPU prefers cache-friendly.
    let (tile_x, tile_y) = match target {
        HardwareTarget::Cuda | HardwareTarget::Opencl => (32, 32),
        HardwareTarget::X86 => (256, 32),
        HardwareTarget::Arm => (128, 32),
        HardwareTarget::Wasm => (64, 16),
    };

    // Most stages benefit from tiling.
    sched.push(SchedulePrimitive::Tile {
        x_size: tile_x,
        y_size: tile_y,
    });

    // Vectorize inner loop if enabled.
    if vectorize {
        sched.push(SchedulePrimitive::Vectorize { width: vec_width });
    }

    // Parallelize outer loop if enabled and not targeting GPU (GPU has its own parallelism).
    if parallelize && !matches!(target, HardwareTarget::Cuda | HardwareTarget::Opencl) {
        sched.push(SchedulePrimitive::Parallelize {
            dimension: "yo".into(),
        });
    }

    // For operations with reduction domains, compute the producer at the consumer's tile level.
    if stage_uses_rdom(&stage.operation) {
        // Reorder to put channel dimension innermost for vectorization.
        sched.push(SchedulePrimitive::Reorder {
            dimensions: vec![
                "c".into(),
                "xi".into(),
                "yi".into(),
                "xo".into(),
                "yo".into(),
            ],
        });
    }

    sched
}

/// Validate that the sequence of stages is compatible.
/// For now, checks that:
///   - No duplicate func names (already checked in manifest::validate)
///   - A resize stage is not followed by another resize (unusual pattern)
fn validate_stage_sequence(stages: &[ResolvedStage]) -> Result<()> {
    for window in stages.windows(2) {
        let current = &window[0];
        let next = &window[1];

        // Warn about consecutive resize operations (likely a mistake).
        if current.stage.operation == HalideOperation::Resize
            && next.stage.operation == HalideOperation::Resize
        {
            bail!(
                "Consecutive resize stages '{}' and '{}' detected. \
                 Combine them into a single resize for efficiency.",
                current.stage.name,
                next.stage.name
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::StageParams;
    use crate::manifest::parse_manifest;

    #[test]
    fn test_resolve_simple_pipeline() {
        let toml_str = r#"
[project]
name = "test_pipe"

[[stages]]
name = "blur_it"
operation = "blur"

[target]
arch = "x86"

[pipeline]
input-format = "png"
output-format = "png"
"#;
        let m = parse_manifest(toml_str).expect("TODO: handle error");
        let resolved = resolve_pipeline(&m).expect("TODO: handle error");
        assert_eq!(resolved.stages.len(), 1);
        assert!(resolved.stages[0].uses_rdom);
        // Defaults should be applied: kernel_size=3, sigma=(3-1)/6.
        assert_eq!(resolved.stages[0].stage.params.kernel_size, Some(3));
        assert!(resolved.stages[0].stage.params.sigma.is_some());
    }

    #[test]
    fn test_resolve_multi_stage() {
        let toml_str = r#"
[project]
name = "multi"

[[stages]]
name = "blur_first"
operation = "blur"
kernel-size = 5
sigma = 1.0

[[stages]]
name = "edge_detect"
operation = "edge-detect"

[[stages]]
name = "threshold_it"
operation = "threshold"
value = 128.0

[target]
arch = "arm"
vectorize = true
parallelize = false

[pipeline]
input-format = "raw"
output-format = "png"
bit-depth = "uint16"
"#;
        let m = parse_manifest(toml_str).expect("TODO: handle error");
        let resolved = resolve_pipeline(&m).expect("TODO: handle error");
        assert_eq!(resolved.stages.len(), 3);
        assert!(resolved.stages[0].uses_rdom); // blur
        assert!(resolved.stages[1].uses_rdom); // edge-detect
        assert!(!resolved.stages[2].uses_rdom); // threshold
    }

    #[test]
    fn test_consecutive_resize_rejected() {
        let toml_str = r#"
[project]
name = "bad_pipe"

[[stages]]
name = "resize_1"
operation = "resize"
width = 640
height = 480

[[stages]]
name = "resize_2"
operation = "resize"
width = 320
height = 240

[target]
arch = "wasm"

[pipeline]
input-format = "jpg"
output-format = "jpg"
"#;
        let m = parse_manifest(toml_str).expect("TODO: handle error");
        let result = resolve_pipeline(&m);
        assert!(result.is_err());
        assert!(
            result
                .unwrap_err()
                .to_string()
                .contains("Consecutive resize")
        );
    }

    #[test]
    fn test_auto_schedule_gpu_no_parallelize() {
        let stage = PipelineStage {
            name: "gpu_blur".into(),
            operation: HalideOperation::Blur,
            params: StageParams {
                kernel_size: Some(3),
                sigma: Some(1.0),
                ..Default::default()
            },
        };
        let sched = auto_schedule(&stage, &HardwareTarget::Cuda, true, true);
        // GPU should NOT have a Parallelize primitive (GPU has its own parallelism).
        assert!(
            !sched
                .iter()
                .any(|s| matches!(s, SchedulePrimitive::Parallelize { .. })),
            "GPU schedule should not include explicit Parallelize"
        );
    }
}
