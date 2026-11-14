// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for halideiser.
// Rust-side types mirroring the Idris2 ABI formal definitions.
// The Idris2 proofs guarantee correctness; this module provides runtime types.
//
// These types model the core Halide concepts:
//   - PipelineStage: a named step in an image/video pipeline
//   - HalideOperation: the algorithm applied at each stage
//   - SchedulePrimitive: scheduling directives (tile, vectorize, etc.)
//   - HardwareTarget: CPU/GPU/WASM backend selection
//   - PixelType: pixel data representation

use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// HalideOperation — the algorithm applied at each pipeline stage
// ---------------------------------------------------------------------------

/// Supported image/video processing operations.
/// Each variant maps to a specific Halide algorithm pattern.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HalideOperation {
    /// Gaussian or box blur with configurable kernel size and sigma.
    Blur,
    /// Sharpening via unsharp mask or Laplacian.
    Sharpen,
    /// Bilinear/bicubic/nearest-neighbour resize.
    Resize,
    /// Arbitrary convolution with a user-supplied kernel.
    Convolve,
    /// Edge detection (Sobel, Canny, Laplacian).
    EdgeDetect,
    /// Binary or adaptive thresholding.
    Threshold,
    /// Colour space conversion (RGB/BGR/YUV/grayscale).
    ColorConvert,
}

impl fmt::Display for HalideOperation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            HalideOperation::Blur => write!(f, "blur"),
            HalideOperation::Sharpen => write!(f, "sharpen"),
            HalideOperation::Resize => write!(f, "resize"),
            HalideOperation::Convolve => write!(f, "convolve"),
            HalideOperation::EdgeDetect => write!(f, "edge-detect"),
            HalideOperation::Threshold => write!(f, "threshold"),
            HalideOperation::ColorConvert => write!(f, "color-convert"),
        }
    }
}

// ---------------------------------------------------------------------------
// SchedulePrimitive — scheduling directives that Halide applies
// ---------------------------------------------------------------------------

/// Halide scheduling primitives.
/// These control how the generated code is tiled, vectorized, and parallelized.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum SchedulePrimitive {
    /// Tile the computation in x/y with given tile sizes.
    Tile { x_size: u32, y_size: u32 },
    /// Vectorize the innermost loop with the given width (e.g. 8 for AVX-256).
    Vectorize { width: u32 },
    /// Parallelize the given dimension (typically the outermost y tiles).
    Parallelize { dimension: String },
    /// Compute a producer function at a specific consumer dimension.
    ComputeAt {
        producer: String,
        consumer: String,
        dimension: String,
    },
    /// Store a producer at a specific consumer dimension for locality.
    StoreAt {
        producer: String,
        consumer: String,
        dimension: String,
    },
    /// Reorder loop dimensions for better cache/SIMD behaviour.
    Reorder { dimensions: Vec<String> },
}

impl fmt::Display for SchedulePrimitive {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SchedulePrimitive::Tile { x_size, y_size } => {
                write!(f, "tile({}, {})", x_size, y_size)
            }
            SchedulePrimitive::Vectorize { width } => {
                write!(f, "vectorize({})", width)
            }
            SchedulePrimitive::Parallelize { dimension } => {
                write!(f, "parallelize({})", dimension)
            }
            SchedulePrimitive::ComputeAt {
                producer,
                consumer,
                dimension,
            } => {
                write!(f, "compute_at({}, {}, {})", producer, consumer, dimension)
            }
            SchedulePrimitive::StoreAt {
                producer,
                consumer,
                dimension,
            } => {
                write!(f, "store_at({}, {}, {})", producer, consumer, dimension)
            }
            SchedulePrimitive::Reorder { dimensions } => {
                write!(f, "reorder({})", dimensions.join(", "))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// HardwareTarget — CPU/GPU/WASM backend
// ---------------------------------------------------------------------------

/// Target hardware architecture for Halide code generation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HardwareTarget {
    /// x86-64 with SSE4.2 / AVX / AVX2 / AVX-512.
    X86,
    /// ARM with NEON / SVE.
    Arm,
    /// NVIDIA CUDA.
    Cuda,
    /// OpenCL (cross-vendor GPU).
    Opencl,
    /// WebAssembly (browser / edge).
    Wasm,
}

impl fmt::Display for HardwareTarget {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            HardwareTarget::X86 => write!(f, "x86-64-linux-avx2"),
            HardwareTarget::Arm => write!(f, "arm-64-linux-arm_dot_prod"),
            HardwareTarget::Cuda => write!(f, "host-cuda"),
            HardwareTarget::Opencl => write!(f, "host-opencl"),
            HardwareTarget::Wasm => write!(f, "wasm-32-wasmrt"),
        }
    }
}

impl HardwareTarget {
    /// Return the SIMD vector width (in 32-bit elements) for this target.
    /// Used by the schedule auto-generator to pick vectorize widths.
    pub fn natural_vector_width(&self) -> u32 {
        match self {
            HardwareTarget::X86 => 8,   // AVX2: 256-bit = 8x float32
            HardwareTarget::Arm => 4,   // NEON: 128-bit = 4x float32
            HardwareTarget::Cuda => 32, // warp size
            HardwareTarget::Opencl => 16,
            HardwareTarget::Wasm => 4, // WASM SIMD: 128-bit
        }
    }
}

// ---------------------------------------------------------------------------
// PixelType — pixel data representation
// ---------------------------------------------------------------------------

/// Pixel data type for pipeline input/output buffers.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum PixelType {
    /// 8-bit unsigned integer (0-255).
    Uint8,
    /// 16-bit unsigned integer (0-65535).
    Uint16,
    /// 32-bit floating point (0.0-1.0 normalized).
    Float32,
    /// 64-bit floating point (double precision).
    Float64,
}

impl fmt::Display for PixelType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PixelType::Uint8 => write!(f, "uint8_t"),
            PixelType::Uint16 => write!(f, "uint16_t"),
            PixelType::Float32 => write!(f, "float"),
            PixelType::Float64 => write!(f, "double"),
        }
    }
}

impl PixelType {
    /// Return the Halide type name string for this pixel type.
    pub fn halide_type(&self) -> &'static str {
        match self {
            PixelType::Uint8 => "UInt(8)",
            PixelType::Uint16 => "UInt(16)",
            PixelType::Float32 => "Float(32)",
            PixelType::Float64 => "Float(64)",
        }
    }

    /// Return the bit depth of this pixel type.
    pub fn bit_depth(&self) -> u32 {
        match self {
            PixelType::Uint8 => 8,
            PixelType::Uint16 => 16,
            PixelType::Float32 => 32,
            PixelType::Float64 => 64,
        }
    }
}

// ---------------------------------------------------------------------------
// PipelineStage — a named step in a processing pipeline
// ---------------------------------------------------------------------------

/// A single stage in an image/video processing pipeline.
/// Each stage has a name, an operation, and operation-specific parameters.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PipelineStage {
    /// Human-readable name for this stage (used as the Halide Func name).
    pub name: String,
    /// The operation this stage performs.
    pub operation: HalideOperation,
    /// Operation-specific parameters.
    #[serde(default)]
    pub params: StageParams,
}

/// Operation-specific parameters for a pipeline stage.
/// All fields are optional; codegen uses sensible defaults.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct StageParams {
    /// Kernel size for blur, sharpen, convolve, edge-detect (must be odd).
    #[serde(rename = "kernel-size")]
    pub kernel_size: Option<u32>,
    /// Sigma for Gaussian blur.
    pub sigma: Option<f64>,
    /// Output width for resize operations.
    pub width: Option<u32>,
    /// Output height for resize operations.
    pub height: Option<u32>,
    /// Target colour space for color-convert (e.g. "grayscale", "yuv").
    #[serde(rename = "color-space")]
    pub color_space: Option<String>,
    /// Threshold value (0-255 or 0.0-1.0 depending on pixel type).
    pub value: Option<f64>,
    /// Custom convolution kernel as a flat row-major vector.
    pub kernel: Option<Vec<f64>>,
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/// Validate a pipeline stage's parameters against its operation type.
/// Returns an error message if the parameters are inconsistent.
pub fn validate_stage(stage: &PipelineStage) -> Result<(), String> {
    match &stage.operation {
        HalideOperation::Blur => {
            if let Some(ks) = stage.params.kernel_size
                && ks % 2 == 0
            {
                return Err(format!(
                    "Stage '{}': kernel-size must be odd, got {}",
                    stage.name, ks
                ));
            }
        }
        HalideOperation::Sharpen => {
            if let Some(ks) = stage.params.kernel_size
                && ks % 2 == 0
            {
                return Err(format!(
                    "Stage '{}': kernel-size must be odd, got {}",
                    stage.name, ks
                ));
            }
        }
        HalideOperation::Resize => {
            if stage.params.width.is_none() && stage.params.height.is_none() {
                return Err(format!(
                    "Stage '{}': resize requires at least one of width or height",
                    stage.name
                ));
            }
        }
        HalideOperation::Convolve => {
            if let Some(ref kernel) = stage.params.kernel {
                let ks = stage.params.kernel_size.unwrap_or(3) as usize;
                if kernel.len() != ks * ks {
                    return Err(format!(
                        "Stage '{}': kernel length {} does not match kernel-size {}x{}",
                        stage.name,
                        kernel.len(),
                        ks,
                        ks
                    ));
                }
            }
        }
        HalideOperation::EdgeDetect => {
            // No required params; kernel-size defaults to 3 (Sobel).
        }
        HalideOperation::Threshold => {
            if stage.params.value.is_none() {
                return Err(format!(
                    "Stage '{}': threshold requires a 'value' parameter",
                    stage.name
                ));
            }
        }
        HalideOperation::ColorConvert => {
            if stage.params.color_space.is_none() {
                return Err(format!(
                    "Stage '{}': color-convert requires a 'color-space' parameter",
                    stage.name
                ));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hardware_target_display() {
        assert_eq!(HardwareTarget::X86.to_string(), "x86-64-linux-avx2");
        assert_eq!(HardwareTarget::Cuda.to_string(), "host-cuda");
        assert_eq!(HardwareTarget::Wasm.to_string(), "wasm-32-wasmrt");
    }

    #[test]
    fn test_pixel_type_halide_mapping() {
        assert_eq!(PixelType::Uint8.halide_type(), "UInt(8)");
        assert_eq!(PixelType::Float32.halide_type(), "Float(32)");
        assert_eq!(PixelType::Uint8.bit_depth(), 8);
        assert_eq!(PixelType::Float64.bit_depth(), 64);
    }

    #[test]
    fn test_validate_stage_blur_even_kernel() {
        let stage = PipelineStage {
            name: "bad_blur".into(),
            operation: HalideOperation::Blur,
            params: StageParams {
                kernel_size: Some(4),
                ..Default::default()
            },
        };
        let result = validate_stage(&stage);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("odd"));
    }

    #[test]
    fn test_validate_stage_resize_no_dimensions() {
        let stage = PipelineStage {
            name: "bad_resize".into(),
            operation: HalideOperation::Resize,
            params: StageParams::default(),
        };
        assert!(validate_stage(&stage).is_err());
    }

    #[test]
    fn test_validate_stage_threshold_requires_value() {
        let stage = PipelineStage {
            name: "bad_thresh".into(),
            operation: HalideOperation::Threshold,
            params: StageParams::default(),
        };
        assert!(validate_stage(&stage).is_err());
    }

    #[test]
    fn test_schedule_primitive_display() {
        let tile = SchedulePrimitive::Tile {
            x_size: 32,
            y_size: 8,
        };
        assert_eq!(tile.to_string(), "tile(32, 8)");

        let vec = SchedulePrimitive::Vectorize { width: 8 };
        assert_eq!(vec.to_string(), "vectorize(8)");
    }
}
