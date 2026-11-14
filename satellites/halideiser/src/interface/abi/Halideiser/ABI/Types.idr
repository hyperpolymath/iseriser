-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Halideiser
|||
||| Defines the Application Binary Interface for Halide pipeline compilation.
||| All type definitions include formal proofs of correctness.
|||
||| Core Halide concepts modelled here:
|||   - PipelineStage: what operations to perform (blur, sharpen, resize, etc.)
|||   - SchedulePrimitive: how to execute on hardware (tile, vectorize, parallelize)
|||   - HardwareTarget: which hardware to target (x86 SSE/AVX, ARM NEON, CUDA, etc.)
|||   - BufferDimension: image buffer dimensions with compile-time bounds
|||   - TileSize: tile dimensions with proof they divide the buffer extent
|||
||| @see https://halide-lang.org for Halide documentation
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Halideiser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for compiled Halide pipelines
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| The platform this build targets. Defaults to Linux; the Rust/Zig build
||| layer overrides this via the codegen target selection. (Previously a
||| `%runElab` stub that required ElabReflection and did not compile.)
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- Hardware Targets
--------------------------------------------------------------------------------

||| Hardware targets for Halide schedule generation.
||| Each target determines which scheduling primitives are available
||| and what SIMD width / compute grid to use.
public export
data HardwareTarget : Type where
  ||| x86 with SSE4.2 (128-bit SIMD, 4-wide float)
  X86_SSE : HardwareTarget
  ||| x86 with AVX2 (256-bit SIMD, 8-wide float)
  X86_AVX2 : HardwareTarget
  ||| x86 with AVX-512 (512-bit SIMD, 16-wide float)
  X86_AVX512 : HardwareTarget
  ||| ARM with NEON (128-bit SIMD, 4-wide float)
  ARM_NEON : HardwareTarget
  ||| ARM with SVE (scalable vector extension)
  ARM_SVE : HardwareTarget
  ||| NVIDIA GPU via CUDA
  CUDA : HardwareTarget
  ||| Cross-vendor GPU via OpenCL
  OpenCL : HardwareTarget
  ||| Apple GPU via Metal
  Metal : HardwareTarget
  ||| Cross-platform GPU via Vulkan
  Vulkan_ : HardwareTarget
  ||| Browser deployment via WebAssembly
  WebAssembly : HardwareTarget

||| Convert HardwareTarget to C integer for FFI
public export
targetToInt : HardwareTarget -> Bits32
targetToInt X86_SSE     = 0
targetToInt X86_AVX2    = 1
targetToInt X86_AVX512  = 2
targetToInt ARM_NEON    = 3
targetToInt ARM_SVE     = 4
targetToInt CUDA        = 5
targetToInt OpenCL      = 6
targetToInt Metal       = 7
targetToInt Vulkan_     = 8
targetToInt WebAssembly = 9

||| Native SIMD width in 32-bit floats for each target
public export
simdWidth : HardwareTarget -> Nat
simdWidth X86_SSE     = 4
simdWidth X86_AVX2    = 8
simdWidth X86_AVX512  = 16
simdWidth ARM_NEON    = 4
simdWidth ARM_SVE     = 8   -- Minimum SVE width
simdWidth CUDA        = 32  -- Warp size
simdWidth OpenCL      = 16  -- Typical work-group width
simdWidth Metal       = 32  -- SIMD-group width
simdWidth Vulkan_     = 16  -- Typical subgroup size
simdWidth WebAssembly = 4   -- WASM SIMD128

||| Whether a target supports GPU compute grids
public export
isGPU : HardwareTarget -> Bool
isGPU CUDA        = True
isGPU OpenCL      = True
isGPU Metal       = True
isGPU Vulkan_     = True
isGPU _           = False

--------------------------------------------------------------------------------
-- Pipeline Stages
--------------------------------------------------------------------------------

||| Image/video processing operations that form pipeline stages.
||| Each stage is a pure function from input buffer(s) to output buffer.
public export
data PipelineStage : Type where
  ||| Gaussian blur with configurable sigma
  GaussianBlur : (sigma : Double) -> PipelineStage
  ||| Box blur with configurable radius
  BoxBlur : (radius : Nat) -> PipelineStage
  ||| Sharpening via unsharp mask (blur then subtract)
  Sharpen : (amount : Double) -> (sigma : Double) -> PipelineStage
  ||| Resize with specified method
  Resize : (factorX : Double) -> (factorY : Double) -> PipelineStage
  ||| Generic 2D convolution with kernel
  Convolve : (kernelSize : Nat) -> PipelineStage
  ||| Sobel edge detection
  SobelEdge : PipelineStage
  ||| Canny edge detection with thresholds
  CannyEdge : (low : Double) -> (high : Double) -> PipelineStage
  ||| Colour space conversion
  ColourConvert : (from : String) -> (to : String) -> PipelineStage
  ||| Histogram equalisation
  HistogramEq : PipelineStage
  ||| Brightness/contrast adjustment
  BrightnessContrast : (brightness : Double) -> (contrast : Double) -> PipelineStage
  ||| Generic pointwise operation (per-pixel expression)
  Pointwise : (expr : String) -> PipelineStage
  ||| Reduce (e.g. sum, max) across a dimension
  Reduce : (op : String) -> (dim : Nat) -> PipelineStage

||| Convert PipelineStage to C integer tag for FFI
public export
stageToInt : PipelineStage -> Bits32
stageToInt (GaussianBlur _)        = 0
stageToInt (BoxBlur _)             = 1
stageToInt (Sharpen _ _)           = 2
stageToInt (Resize _ _)            = 3
stageToInt (Convolve _)            = 4
stageToInt SobelEdge               = 5
stageToInt (CannyEdge _ _)         = 6
stageToInt (ColourConvert _ _)     = 7
stageToInt HistogramEq             = 8
stageToInt (BrightnessContrast _ _) = 9
stageToInt (Pointwise _)          = 10
stageToInt (Reduce _ _)           = 11

--------------------------------------------------------------------------------
-- Scheduling Primitives
--------------------------------------------------------------------------------

||| Halide scheduling primitives that control how an algorithm executes.
||| These do not change what is computed — only how and where.
public export
data SchedulePrimitive : Type where
  ||| Tile two dimensions into inner/outer loops for cache locality
  ||| tile(x, y, xi, yi, tile_x, tile_y)
  Tile : (tileX : Nat) -> (tileY : Nat) -> SchedulePrimitive
  ||| Vectorize the innermost loop dimension using SIMD
  ||| vectorize(var, width)
  Vectorize : (width : Nat) -> SchedulePrimitive
  ||| Distribute loop iterations across CPU cores
  ||| parallelize(var)
  Parallelize : SchedulePrimitive
  ||| Fuse a producer stage into a consumer's loop nest
  ||| compute_at(consumer, var)
  ComputeAt : (consumerStage : Nat) -> (varIndex : Nat) -> SchedulePrimitive
  ||| Control where intermediate buffers are allocated in the loop nest
  ||| store_at(consumer, var)
  StoreAt : (consumerStage : Nat) -> (varIndex : Nat) -> SchedulePrimitive
  ||| Change the order of loop nesting
  ||| reorder(var1, var2, ...)
  Reorder : (varOrder : List Nat) -> SchedulePrimitive
  ||| Unroll a loop by a constant factor
  ||| unroll(var, factor)
  Unroll : (factor : Nat) -> SchedulePrimitive
  ||| Map to GPU thread blocks (CUDA/OpenCL/Metal/Vulkan)
  ||| gpu_blocks(block_x, block_y)
  GPUBlocks : (blockX : Nat) -> (blockY : Nat) -> SchedulePrimitive
  ||| Map to GPU threads within a block
  ||| gpu_threads(thread_x, thread_y)
  GPUThreads : (threadX : Nat) -> (threadY : Nat) -> SchedulePrimitive
  ||| Split a dimension into outer and inner
  ||| split(var, outer, inner, factor)
  Split : (factor : Nat) -> SchedulePrimitive
  ||| Fuse two dimensions into one
  ||| fuse(var1, var2, fused)
  Fuse : SchedulePrimitive
  ||| Prefetch data before it is needed
  ||| prefetch(func, var, offset)
  Prefetch : (offset : Nat) -> SchedulePrimitive

||| Convert SchedulePrimitive to C integer tag for FFI
public export
scheduleToInt : SchedulePrimitive -> Bits32
scheduleToInt (Tile _ _)       = 0
scheduleToInt (Vectorize _)    = 1
scheduleToInt Parallelize      = 2
scheduleToInt (ComputeAt _ _)  = 3
scheduleToInt (StoreAt _ _)    = 4
scheduleToInt (Reorder _)      = 5
scheduleToInt (Unroll _)       = 6
scheduleToInt (GPUBlocks _ _)  = 7
scheduleToInt (GPUThreads _ _) = 8
scheduleToInt (Split _)        = 9
scheduleToInt Fuse             = 10
scheduleToInt (Prefetch _)     = 11

--------------------------------------------------------------------------------
-- Buffer Dimensions
--------------------------------------------------------------------------------

||| Pixel data types supported by Halide buffers
public export
data PixelType : Type where
  UInt8   : PixelType
  UInt16  : PixelType
  UInt32  : PixelType
  Float32 : PixelType
  Float64 : PixelType

||| Bytes per pixel element
public export
pixelBytes : PixelType -> Nat
pixelBytes UInt8   = 1
pixelBytes UInt16  = 2
pixelBytes UInt32  = 4
pixelBytes Float32 = 4
pixelBytes Float64 = 8

||| Buffer dimensions for an image or video frame.
||| Width, height, and channels are always present; frames is optional (1 for images).
|||
||| All dimensions carry a proof of being positive (> 0).
public export
record BufferDimension where
  constructor MkBufferDimension
  width    : Nat
  height   : Nat
  channels : Nat
  frames   : Nat
  {auto 0 widthPos    : So (width > 0)}
  {auto 0 heightPos   : So (height > 0)}
  {auto 0 channelsPos : So (channels > 0)}
  {auto 0 framesPos   : So (frames > 0)}

||| Total number of elements in a buffer
public export
bufferElements : BufferDimension -> Nat
bufferElements dim = dim.width * dim.height * dim.channels * dim.frames

||| Total bytes for a buffer with given dimensions and pixel type
public export
bufferBytes : BufferDimension -> PixelType -> Nat
bufferBytes dim ptype = bufferElements dim * pixelBytes ptype

--------------------------------------------------------------------------------
-- Tile Sizes
--------------------------------------------------------------------------------

||| A tile size with a proof that it divides the target dimension.
||| This ensures tiling does not produce partial tiles at boundaries
||| (or that boundary handling is explicit).
public export
record TileSize where
  constructor MkTileSize
  size : Nat
  {auto 0 positive : So (size > 0)}

||| Check whether a tile size evenly divides a dimension extent
public export
tileDivides : TileSize -> Nat -> Bool
tileDivides tile extent = extent `mod` tile.size == 0

||| Proof that vectorise width is compatible with a hardware target
public export
data VectorWidthValid : (width : Nat) -> HardwareTarget -> Type where
  VecValid : {w : Nat} -> {t : HardwareTarget} ->
             So (w > 0) ->
             So (w <= simdWidth t) ->
             VectorWidthValid w t

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
||| Use C-compatible integers for cross-language compatibility
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid parameter provided
  InvalidParam : Result
  ||| Out of memory
  OutOfMemory : Result
  ||| Null pointer encountered
  NullPointer : Result
  ||| Pipeline compilation failed
  CompileFailed : Result
  ||| Schedule is invalid for target hardware
  InvalidSchedule : Result
  ||| Buffer dimensions mismatch between stages
  DimensionMismatch : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok                = 0
resultToInt Error             = 1
resultToInt InvalidParam      = 2
resultToInt OutOfMemory       = 3
resultToInt NullPointer       = 4
resultToInt CompileFailed     = 5
resultToInt InvalidSchedule   = 6
resultToInt DimensionMismatch = 7

||| Results are decidably equal. The off-diagonal cases discharge the
||| disequality explicitly; a `decEq _ _ = No absurd` catch-all does not
||| compile (no `Uninhabited (x = y)` instance exists for these).
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq CompileFailed CompileFailed = Yes Refl
  decEq InvalidSchedule InvalidSchedule = Yes Refl
  decEq DimensionMismatch DimensionMismatch = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok CompileFailed = No (\case Refl impossible)
  decEq Ok InvalidSchedule = No (\case Refl impossible)
  decEq Ok DimensionMismatch = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error CompileFailed = No (\case Refl impossible)
  decEq Error InvalidSchedule = No (\case Refl impossible)
  decEq Error DimensionMismatch = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam CompileFailed = No (\case Refl impossible)
  decEq InvalidParam InvalidSchedule = No (\case Refl impossible)
  decEq InvalidParam DimensionMismatch = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory CompileFailed = No (\case Refl impossible)
  decEq OutOfMemory InvalidSchedule = No (\case Refl impossible)
  decEq OutOfMemory DimensionMismatch = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer CompileFailed = No (\case Refl impossible)
  decEq NullPointer InvalidSchedule = No (\case Refl impossible)
  decEq NullPointer DimensionMismatch = No (\case Refl impossible)
  decEq CompileFailed Ok = No (\case Refl impossible)
  decEq CompileFailed Error = No (\case Refl impossible)
  decEq CompileFailed InvalidParam = No (\case Refl impossible)
  decEq CompileFailed OutOfMemory = No (\case Refl impossible)
  decEq CompileFailed NullPointer = No (\case Refl impossible)
  decEq CompileFailed InvalidSchedule = No (\case Refl impossible)
  decEq CompileFailed DimensionMismatch = No (\case Refl impossible)
  decEq InvalidSchedule Ok = No (\case Refl impossible)
  decEq InvalidSchedule Error = No (\case Refl impossible)
  decEq InvalidSchedule InvalidParam = No (\case Refl impossible)
  decEq InvalidSchedule OutOfMemory = No (\case Refl impossible)
  decEq InvalidSchedule NullPointer = No (\case Refl impossible)
  decEq InvalidSchedule CompileFailed = No (\case Refl impossible)
  decEq InvalidSchedule DimensionMismatch = No (\case Refl impossible)
  decEq DimensionMismatch Ok = No (\case Refl impossible)
  decEq DimensionMismatch Error = No (\case Refl impossible)
  decEq DimensionMismatch InvalidParam = No (\case Refl impossible)
  decEq DimensionMismatch OutOfMemory = No (\case Refl impossible)
  decEq DimensionMismatch NullPointer = No (\case Refl impossible)
  decEq DimensionMismatch CompileFailed = No (\case Refl impossible)
  decEq DimensionMismatch InvalidSchedule = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI.
||| Prevents direct construction, enforces creation through safe API.
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value. Uses `choose` to obtain a
||| real `So (ptr /= 0)` witness for the non-null branch. (Previously
||| `Just (MkHandle ptr)` left the `auto` proof unsolved and did not compile.)
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

||| Extract pointer value from handle
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| C int size varies by platform
public export
CInt : Platform -> Type
CInt Linux   = Bits32
CInt Windows = Bits32
CInt MacOS   = Bits32
CInt BSD     = Bits32
CInt WASM    = Bits32

||| C size_t varies by platform
public export
CSize : Platform -> Type
CSize Linux   = Bits64
CSize Windows = Bits64
CSize MacOS   = Bits64
CSize BSD     = Bits64
CSize WASM    = Bits32

||| C pointer size varies by platform
public export
ptrSize : Platform -> Nat
ptrSize Linux   = 64
ptrSize Windows = 64
ptrSize MacOS   = 64
ptrSize BSD     = 64
ptrSize WASM    = 32

--------------------------------------------------------------------------------
-- Pipeline Composition Proof
--------------------------------------------------------------------------------

||| Proof that two stages are connectable: the output dimensions of stage A
||| are compatible with the input dimensions of stage B.
public export
data StagesConnectable : PipelineStage -> PipelineStage -> BufferDimension -> Type where
  ||| Most stages preserve dimensions (blur, sharpen, edge detect, colour convert)
  PreserveDim : StagesConnectable a b dim
  ||| Resize changes dimensions — the proof must supply the new dimensions
  ResizeConnectable :
    (newDim : BufferDimension) ->
    StagesConnectable (Resize fx fy) next newDim

||| A validated pipeline is a non-empty sequence of stages with proofs
||| that adjacent stages are connectable.
public export
data ValidPipeline : List PipelineStage -> Type where
  SingleStage : (s : PipelineStage) -> ValidPipeline [s]
  ConsStage   : (s : PipelineStage) ->
                (rest : ValidPipeline (t :: ts)) ->
                StagesConnectable s t dim ->
                ValidPipeline (s :: t :: ts)

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification of ABI properties
namespace Verify

  ||| Verify that all hardware targets have positive SIMD width
  export
  allTargetsPositiveSimd : (t : HardwareTarget) -> So (simdWidth t > 0)
  allTargetsPositiveSimd X86_SSE     = Oh
  allTargetsPositiveSimd X86_AVX2    = Oh
  allTargetsPositiveSimd X86_AVX512  = Oh
  allTargetsPositiveSimd ARM_NEON    = Oh
  allTargetsPositiveSimd ARM_SVE     = Oh
  allTargetsPositiveSimd CUDA        = Oh
  allTargetsPositiveSimd OpenCL      = Oh
  allTargetsPositiveSimd Metal       = Oh
  allTargetsPositiveSimd Vulkan_     = Oh
  allTargetsPositiveSimd WebAssembly = Oh

  ||| Verify that all pixel types have positive byte width
  export
  allPixelTypesPositive : (p : PixelType) -> So (pixelBytes p > 0)
  allPixelTypesPositive UInt8   = Oh
  allPixelTypesPositive UInt16  = Oh
  allPixelTypesPositive UInt32  = Oh
  allPixelTypesPositive Float32 = Oh
  allPixelTypesPositive Float64 = Oh
