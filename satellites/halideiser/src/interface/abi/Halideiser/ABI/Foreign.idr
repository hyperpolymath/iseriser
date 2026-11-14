-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Halideiser
|||
||| This module declares all C-compatible functions for Halide pipeline
||| compilation and execution. These functions are implemented in the
||| Zig FFI layer (src/interface/ffi/src/main.zig).
|||
||| The lifecycle for a compiled pipeline is:
|||   1. halideiser_init()              — create a pipeline context
|||   2. halideiser_add_stage()         — add processing stages
|||   3. halideiser_set_schedule()      — configure scheduling primitives
|||   4. halideiser_compile_pipeline()  — compile to native code for target
|||   5. halideiser_execute_pipeline()  — run on input buffers
|||   6. halideiser_autotune()          — (optional) search for faster schedules
|||   7. halideiser_free()              — release all resources
|||
||| @see Halideiser.ABI.Types for type definitions
||| @see Halideiser.ABI.Layout for buffer layout proofs

module Halideiser.ABI.Foreign

import Halideiser.ABI.Types
import Halideiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialise a Halide pipeline context.
||| Returns a handle to the context, or Nothing on failure.
export
%foreign "C:halideiser_init, libhalideiser"
prim__init : PrimIO Bits64

||| Safe wrapper for pipeline context initialisation
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Release all resources associated with a pipeline context.
export
%foreign "C:halideiser_free, libhalideiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Pipeline Construction
--------------------------------------------------------------------------------

||| Add a processing stage to the pipeline.
||| Stages are executed in the order they are added.
|||
||| @param handle  Pipeline context
||| @param stageTag  Stage type (see stageToInt in Types.idr)
||| @param param1    Stage-specific parameter 1 (e.g. sigma for GaussianBlur)
||| @param param2    Stage-specific parameter 2 (e.g. amount for Sharpen)
export
%foreign "C:halideiser_add_stage, libhalideiser"
prim__addStage : Bits64 -> Bits32 -> Double -> Double -> PrimIO Bits32

||| Safe wrapper: add a pipeline stage
export
addStage : Handle -> PipelineStage -> IO (Either Result ())
addStage h stage = do
  let (tag, p1, p2) = stageParams stage
  result <- primIO (prim__addStage (handlePtr h) tag p1 p2)
  pure $ resultFromInt result
 where
  stageParams : PipelineStage -> (Bits32, Double, Double)
  stageParams (GaussianBlur sigma)           = (0, sigma, 0.0)
  stageParams (BoxBlur radius)               = (1, cast radius, 0.0)
  stageParams (Sharpen amount sigma)         = (2, amount, sigma)
  stageParams (Resize fx fy)                 = (3, fx, fy)
  stageParams (Convolve ks)                  = (4, cast ks, 0.0)
  stageParams SobelEdge                      = (5, 0.0, 0.0)
  stageParams (CannyEdge low high)           = (6, low, high)
  stageParams (ColourConvert _ _)            = (7, 0.0, 0.0)
  stageParams HistogramEq                    = (8, 0.0, 0.0)
  stageParams (BrightnessContrast br co)     = (9, br, co)
  stageParams (Pointwise _)                  = (10, 0.0, 0.0)
  stageParams (Reduce _ dim)                 = (11, cast dim, 0.0)

  resultFromInt : Bits32 -> Either Result ()
  resultFromInt 0 = Right ()
  resultFromInt 1 = Left Error
  resultFromInt 2 = Left InvalidParam
  resultFromInt 3 = Left OutOfMemory
  resultFromInt 4 = Left NullPointer
  resultFromInt 5 = Left CompileFailed
  resultFromInt 6 = Left InvalidSchedule
  resultFromInt 7 = Left DimensionMismatch
  resultFromInt _ = Left Error

--------------------------------------------------------------------------------
-- Buffer Configuration
--------------------------------------------------------------------------------

||| Set input buffer dimensions for the pipeline.
|||
||| @param handle    Pipeline context
||| @param width     Image width in pixels
||| @param height    Image height in pixels
||| @param channels  Number of colour channels (1=grey, 3=RGB, 4=RGBA)
||| @param frames    Number of frames (1 for images, >1 for video)
||| @param elemType  Pixel element type (0=uint8, 1=uint16, 2=uint32, 3=float32, 4=float64)
export
%foreign "C:halideiser_set_input_buffer, libhalideiser"
prim__setInputBuffer : Bits64 -> Bits32 -> Bits32 -> Bits32 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: set input buffer dimensions
export
setInputBuffer : Handle -> BufferDimension -> PixelType -> IO (Either Result ())
setInputBuffer h dim ptype = do
  result <- primIO (prim__setInputBuffer
    (handlePtr h)
    (cast dim.width)
    (cast dim.height)
    (cast dim.channels)
    (cast dim.frames)
    (pixelTypeToInt ptype))
  pure $ if result == 0 then Right () else Left Error
 where
  pixelTypeToInt : PixelType -> Bits32
  pixelTypeToInt UInt8   = 0
  pixelTypeToInt UInt16  = 1
  pixelTypeToInt UInt32  = 2
  pixelTypeToInt Float32 = 3
  pixelTypeToInt Float64 = 4

--------------------------------------------------------------------------------
-- Schedule Configuration
--------------------------------------------------------------------------------

||| Set the hardware target for schedule generation.
|||
||| @param handle  Pipeline context
||| @param target  Hardware target (see targetToInt in Types.idr)
export
%foreign "C:halideiser_set_target, libhalideiser"
prim__setTarget : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: set hardware target
export
setTarget : Handle -> HardwareTarget -> IO (Either Result ())
setTarget h target = do
  result <- primIO (prim__setTarget (handlePtr h) (targetToInt target))
  pure $ if result == 0 then Right () else Left Error

||| Apply a scheduling primitive to a pipeline stage.
|||
||| @param handle      Pipeline context
||| @param stageIndex  Index of the stage in the pipeline (0-based)
||| @param schedTag    Schedule primitive type (see scheduleToInt)
||| @param param1      Primitive-specific parameter 1
||| @param param2      Primitive-specific parameter 2
export
%foreign "C:halideiser_apply_schedule, libhalideiser"
prim__applySchedule : Bits64 -> Bits32 -> Bits32 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: apply a scheduling primitive to a stage
export
applySchedule : Handle -> (stageIndex : Nat) -> SchedulePrimitive -> IO (Either Result ())
applySchedule h idx sched = do
  let (tag, p1, p2) = schedParams sched
  result <- primIO (prim__applySchedule (handlePtr h) (cast idx) tag p1 p2)
  pure $ if result == 0 then Right () else Left Error
 where
  schedParams : SchedulePrimitive -> (Bits32, Bits32, Bits32)
  schedParams (Tile tx ty)       = (0, cast tx, cast ty)
  schedParams (Vectorize w)      = (1, cast w, 0)
  schedParams Parallelize        = (2, 0, 0)
  schedParams (ComputeAt cs vi)  = (3, cast cs, cast vi)
  schedParams (StoreAt cs vi)    = (4, cast cs, cast vi)
  schedParams (Reorder _)        = (5, 0, 0)  -- Full order sent separately
  schedParams (Unroll f)         = (6, cast f, 0)
  schedParams (GPUBlocks bx by)  = (7, cast bx, cast by)
  schedParams (GPUThreads tx ty) = (8, cast tx, cast ty)
  schedParams (Split f)          = (9, cast f, 0)
  schedParams Fuse               = (10, 0, 0)
  schedParams (Prefetch o)       = (11, cast o, 0)

--------------------------------------------------------------------------------
-- Pipeline Compilation
--------------------------------------------------------------------------------

||| Compile the configured pipeline to native code for the target hardware.
||| The pipeline must have at least one stage and a valid target set.
|||
||| @param handle  Pipeline context with stages and schedule configured
export
%foreign "C:halideiser_compile_pipeline, libhalideiser"
prim__compilePipeline : Bits64 -> PrimIO Bits32

||| Safe wrapper: compile the pipeline
export
compilePipeline : Handle -> IO (Either Result ())
compilePipeline h = do
  result <- primIO (prim__compilePipeline (handlePtr h))
  pure $ if result == 0 then Right () else Left CompileFailed

--------------------------------------------------------------------------------
-- Pipeline Execution
--------------------------------------------------------------------------------

||| Execute the compiled pipeline on an input buffer, writing to an output buffer.
|||
||| @param handle     Pipeline context (must be compiled)
||| @param inputPtr   Pointer to input pixel data
||| @param outputPtr  Pointer to output pixel data (pre-allocated)
||| @param inputLen   Length of input data in bytes
||| @param outputLen  Length of output buffer in bytes
export
%foreign "C:halideiser_execute_pipeline, libhalideiser"
prim__executePipeline : Bits64 -> Bits64 -> Bits64 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: execute the compiled pipeline
export
executePipeline : Handle -> (inputPtr : Bits64) -> (outputPtr : Bits64) ->
                  (inputLen : Bits32) -> (outputLen : Bits32) -> IO (Either Result ())
executePipeline h inp outp inLen outLen = do
  result <- primIO (prim__executePipeline (handlePtr h) inp outp inLen outLen)
  pure $ if result == 0 then Right () else Left Error

--------------------------------------------------------------------------------
-- Auto-Tuning
--------------------------------------------------------------------------------

||| Run the auto-tuner to find an optimal schedule for the current pipeline
||| and target hardware. This performs multiple benchmark runs, varying
||| tile sizes, loop orders, and parallelism settings.
|||
||| @param handle     Pipeline context (must have stages and target set)
||| @param maxTrials  Maximum number of schedule variants to try
||| @param timeoutMs  Timeout in milliseconds for the entire search
export
%foreign "C:halideiser_autotune, libhalideiser"
prim__autotune : Bits64 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: auto-tune the pipeline schedule
export
autotune : Handle -> (maxTrials : Bits32) -> (timeoutMs : Bits32) -> IO (Either Result ())
autotune h trials timeout = do
  result <- primIO (prim__autotune (handlePtr h) trials timeout)
  pure $ if result == 0 then Right () else Left Error

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get the last error message from the pipeline context.
export
%foreign "C:halideiser_last_error, libhalideiser"
prim__lastError : PrimIO Bits64

||| Convert C string pointer to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free a C string allocated by the library
export
%foreign "C:halideiser_free_string, libhalideiser"
prim__freeString : Bits64 -> PrimIO ()

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for a result code
export
errorDescription : Result -> String
errorDescription Ok                = "Success"
errorDescription Error             = "Generic error"
errorDescription InvalidParam      = "Invalid parameter"
errorDescription OutOfMemory       = "Out of memory"
errorDescription NullPointer       = "Null pointer"
errorDescription CompileFailed     = "Pipeline compilation failed"
errorDescription InvalidSchedule   = "Schedule is invalid for target hardware"
errorDescription DimensionMismatch = "Buffer dimension mismatch between stages"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:halideiser_version, libhalideiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:halideiser_build_info, libhalideiser"
prim__buildInfo : PrimIO Bits64

||| Get build information (includes Zig version and target)
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if pipeline context is initialised
export
%foreign "C:halideiser_is_initialized, libhalideiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialisation status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)

||| Query the number of stages in the pipeline
export
%foreign "C:halideiser_stage_count, libhalideiser"
prim__stageCount : Bits64 -> PrimIO Bits32

||| Get the number of pipeline stages
export
stageCount : Handle -> IO Nat
stageCount h = do
  n <- primIO (prim__stageCount (handlePtr h))
  pure (cast n)
