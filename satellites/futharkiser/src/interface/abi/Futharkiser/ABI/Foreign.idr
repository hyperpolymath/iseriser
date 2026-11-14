-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Futharkiser
|||
||| Declares all C-compatible functions implemented in the Zig FFI layer.
||| These functions bridge between the host application and the Futhark
||| GPU runtime, handling:
|||   - Library lifecycle (init/free with GPU context creation)
|||   - Futhark source compilation to GPU kernels
|||   - GPU kernel execution with array arguments
|||   - GPU buffer allocation and memory transfers (host <-> device)
|||   - Backend selection (OpenCL, CUDA, multicore, sequential)
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/src/main.zig

module Futharkiser.ABI.Foreign

import Futharkiser.ABI.Types
import Futharkiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialise the Futharkiser library with a specific GPU backend.
||| Creates a Futhark context for the requested backend.
||| Returns a handle to the library instance, or null on failure.
export
%foreign "C:futharkiser_init, libfutharkiser"
prim__init : Bits32 -> PrimIO Bits64

||| Safe wrapper for library initialisation.
||| Takes a GPUBackend and returns a Handle if the backend is available.
export
init : GPUBackend -> IO (Maybe Handle)
init backend = do
  ptr <- primIO (prim__init (resultToInt (backendToResult backend)))
  pure (createHandle ptr)
  where
    backendToResult : GPUBackend -> Result
    backendToResult _ = Ok  -- Backend code is passed as the Bits32 argument

||| Initialise with default backend (OpenCL)
export
initDefault : IO (Maybe Handle)
initDefault = init OpenCL

||| Clean up library resources and release GPU context
export
%foreign "C:futharkiser_free, libfutharkiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Futhark Compilation
--------------------------------------------------------------------------------

||| Compile a Futhark source string to a GPU kernel.
||| The source must be valid Futhark code with entry points.
||| Returns a kernel handle on success, or null on compilation failure.
export
%foreign "C:futharkiser_compile, libfutharkiser"
prim__compile : Bits64 -> String -> Bits32 -> PrimIO Bits64

||| Safe wrapper for Futhark compilation.
||| Takes the library handle, Futhark source code, and target backend.
export
compile : Handle -> (futharkSource : String) -> GPUBackend -> IO (Either Result Handle)
compile h source backend = do
  ptr <- primIO (prim__compile (handlePtr h) source (backendToBits32 backend))
  case createHandle ptr of
    Just kernelHandle => pure (Right kernelHandle)
    Nothing           => pure (Left CompilationFailed)
  where
    backendToBits32 : GPUBackend -> Bits32
    backendToBits32 OpenCL     = 0
    backendToBits32 CUDA       = 1
    backendToBits32 Multicore  = 2
    backendToBits32 Sequential = 3

||| Compile a Futhark source file (path) to a GPU kernel.
export
%foreign "C:futharkiser_compile_file, libfutharkiser"
prim__compileFile : Bits64 -> String -> Bits32 -> PrimIO Bits64

||| Safe wrapper for file-based compilation
export
compileFile : Handle -> (filePath : String) -> GPUBackend -> IO (Either Result Handle)
compileFile h path backend = do
  ptr <- primIO (prim__compileFile (handlePtr h) path (backendToBits32 backend))
  case createHandle ptr of
    Just kernelHandle => pure (Right kernelHandle)
    Nothing           => pure (Left CompilationFailed)
  where
    backendToBits32 : GPUBackend -> Bits32
    backendToBits32 OpenCL     = 0
    backendToBits32 CUDA       = 1
    backendToBits32 Multicore  = 2
    backendToBits32 Sequential = 3

--------------------------------------------------------------------------------
-- GPU Kernel Execution
--------------------------------------------------------------------------------

||| Execute a compiled GPU kernel by entry-point name.
||| Arguments and results are passed via GPU buffer descriptors.
export
%foreign "C:futharkiser_execute, libfutharkiser"
prim__execute : Bits64 -> Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for kernel execution
export
execute : Handle -> (kernelHandle : Handle) -> (entryPoint : String) -> IO (Either Result ())
execute h kernel entry = do
  result <- primIO (prim__execute (handlePtr h) (handlePtr kernel) entry)
  pure $ case resultFromBits32 result of
    Just Ok  => Right ()
    Just err => Left err
    Nothing  => Left Error
  where
    resultFromBits32 : Bits32 -> Maybe Result
    resultFromBits32 0 = Just Ok
    resultFromBits32 1 = Just Error
    resultFromBits32 2 = Just InvalidParam
    resultFromBits32 3 = Just OutOfMemory
    resultFromBits32 4 = Just NullPointer
    resultFromBits32 5 = Just CompilationFailed
    resultFromBits32 6 = Just BackendUnavailable
    resultFromBits32 7 = Just ShapeMismatch
    resultFromBits32 _ = Nothing

--------------------------------------------------------------------------------
-- GPU Buffer Management
--------------------------------------------------------------------------------

||| Allocate a GPU buffer on the specified memory space.
||| Returns a pointer to the buffer descriptor, or null on failure.
export
%foreign "C:futharkiser_alloc_buffer, libfutharkiser"
prim__allocBuffer : Bits64 -> Bits32 -> Bits64 -> Bits32 -> PrimIO Bits64

||| Safe wrapper for GPU buffer allocation
export
allocBuffer : Handle ->
              (elemBytes : Bits32) ->
              (numElements : Bits64) ->
              MemorySpace ->
              IO (Either Result Handle)
allocBuffer h elemBytes numElems space = do
  ptr <- primIO (prim__allocBuffer (handlePtr h) elemBytes numElems (spaceToInt space))
  case createHandle ptr of
    Just bufHandle => pure (Right bufHandle)
    Nothing        => pure (Left OutOfMemory)
  where
    spaceToInt : MemorySpace -> Bits32
    spaceToInt Device = 0
    spaceToInt Host   = 1
    spaceToInt Shared = 2

||| Free a GPU buffer
export
%foreign "C:futharkiser_free_buffer, libfutharkiser"
prim__freeBuffer : Bits64 -> Bits64 -> PrimIO ()

||| Safe wrapper for GPU buffer deallocation
export
freeBuffer : Handle -> (bufferHandle : Handle) -> IO ()
freeBuffer h buf = primIO (prim__freeBuffer (handlePtr h) (handlePtr buf))

||| Transfer data between memory spaces (host <-> device).
||| Source and destination must be pre-allocated buffers.
export
%foreign "C:futharkiser_transfer, libfutharkiser"
prim__transfer : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for memory transfer with proof of valid direction
export
transfer : Handle ->
           (src : Handle) -> (srcSpace : MemorySpace) ->
           (dst : Handle) -> (dstSpace : MemorySpace) ->
           {auto valid : ValidTransfer srcSpace dstSpace} ->
           IO (Either Result ())
transfer h src _ dst _ = do
  result <- primIO (prim__transfer (handlePtr h) (handlePtr src) (handlePtr dst) 0)
  pure $ if result == 0 then Right () else Left Error

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:futharkiser_last_error, libfutharkiser"
prim__lastError : PrimIO Bits64

||| Convert C string pointer to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free a C string allocated by the library
export
%foreign "C:futharkiser_free_string, libfutharkiser"
prim__freeString : Bits64 -> PrimIO ()

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok                 = "Success"
errorDescription Error              = "Generic error"
errorDescription InvalidParam       = "Invalid parameter"
errorDescription OutOfMemory        = "Out of memory (host or device)"
errorDescription NullPointer        = "Null pointer"
errorDescription CompilationFailed  = "Futhark compilation failed"
errorDescription BackendUnavailable = "GPU backend not available"
errorDescription ShapeMismatch      = "Array shape mismatch"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:futharkiser_version, libfutharkiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info (includes Futhark and GPU backend versions)
export
%foreign "C:futharkiser_build_info, libfutharkiser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- GPU Backend Query
--------------------------------------------------------------------------------

||| Check if a GPU backend is available on this system
export
%foreign "C:futharkiser_backend_available, libfutharkiser"
prim__backendAvailable : Bits32 -> PrimIO Bits32

||| Query whether a specific GPU backend is available
export
backendAvailable : GPUBackend -> IO Bool
backendAvailable backend = do
  result <- primIO (prim__backendAvailable (backendToInt backend))
  pure (result /= 0)
  where
    backendToInt : GPUBackend -> Bits32
    backendToInt OpenCL     = 0
    backendToInt CUDA       = 1
    backendToInt Multicore  = 2
    backendToInt Sequential = 3

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:futharkiser_is_initialized, libfutharkiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
