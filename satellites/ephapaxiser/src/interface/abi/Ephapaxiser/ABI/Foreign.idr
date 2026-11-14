-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Ephapaxiser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer (src/interface/ffi/).
|||
||| All functions relate to resource analysis and linearity enforcement.
||| The Zig FFI implements these declarations with zero runtime overhead.
|||
||| When Idris2 proofs conflict with Ephapax linear types, Idris2 always wins.

module Ephapaxiser.ABI.Foreign

import Ephapaxiser.ABI.Types
import Ephapaxiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the ephapaxiser library
||| Returns a handle to the library instance, or Nothing on failure
export
%foreign "C:ephapaxiser_init, libephapaxiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources
export
%foreign "C:ephapaxiser_free, libephapaxiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Resource Analysis
--------------------------------------------------------------------------------

||| Analyse a source file for resource handles.
||| Returns the number of resource handles detected, or an error code.
export
%foreign "C:ephapaxiser_analyse_file, libephapaxiser"
prim__analyseFile : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for file analysis
||| Takes a library handle and a path handle (C string pointer)
export
analyseFile : Handle -> Bits64 -> IO (Either Result Bits32)
analyseFile h pathPtr = do
  result <- primIO (prim__analyseFile (handlePtr h) pathPtr)
  pure (Right result)

||| Detect paired acquire/release operations in analysed code
export
%foreign "C:ephapaxiser_detect_pairs, libephapaxiser"
prim__detectPairs : Bits64 -> PrimIO Bits32

||| Safe wrapper for pair detection
export
detectPairs : Handle -> IO (Either Result Bits32)
detectPairs h = do
  result <- primIO (prim__detectPairs (handlePtr h))
  pure (Right result)

||| Get the resource graph as a serialised structure
export
%foreign "C:ephapaxiser_get_resource_graph, libephapaxiser"
prim__getResourceGraph : Bits64 -> PrimIO Bits64

||| Safe wrapper: retrieve resource graph
export
getResourceGraph : Handle -> IO (Maybe Handle)
getResourceGraph h = do
  ptr <- primIO (prim__getResourceGraph (handlePtr h))
  pure (createHandle ptr)

--------------------------------------------------------------------------------
-- Linearity Enforcement
--------------------------------------------------------------------------------

||| Wrap a raw resource handle with linearity tracking.
||| The kind parameter identifies the resource type (FileHandle, Socket, etc.).
||| Returns a tracked resource handle, or null on failure.
export
%foreign "C:ephapaxiser_wrap_resource, libephapaxiser"
prim__wrapResource : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits64

||| Safe wrapper for resource wrapping
||| Takes a library handle, raw resource pointer, and resource kind
export
wrapResource : Handle -> Bits64 -> ResourceKind -> IO (Maybe Handle)
wrapResource h rawPtr kind = do
  let kindInt = resourceKindToInt kind
  ptr <- primIO (prim__wrapResource (handlePtr h) rawPtr kindInt)
  pure (createHandle ptr)
  where
    resourceKindToInt : ResourceKind -> Bits32
    resourceKindToInt FileHandle     = 0
    resourceKindToInt Socket         = 1
    resourceKindToInt DbConnection   = 2
    resourceKindToInt GpuBuffer      = 3
    resourceKindToInt CryptoKey      = 4
    resourceKindToInt SessionToken   = 5
    resourceKindToInt HeapAlloc      = 6
    resourceKindToInt (Custom _)     = 255

||| Consume (release) a tracked resource.
||| Returns Ok if the resource was properly consumed, or an error code
||| (AlreadyConsumed, DoubleFree) if linearity was violated.
export
%foreign "C:ephapaxiser_consume_resource, libephapaxiser"
prim__consumeResource : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for resource consumption
export
consumeTrackedResource : Handle -> Handle -> IO (Either Result ())
consumeTrackedResource lib resource = do
  result <- primIO (prim__consumeResource (handlePtr lib) (handlePtr resource))
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error
  where
    resultFromInt : Bits32 -> Maybe Result
    resultFromInt 0 = Just Ok
    resultFromInt 1 = Just Error
    resultFromInt 2 = Just InvalidParam
    resultFromInt 3 = Just OutOfMemory
    resultFromInt 4 = Just NullPointer
    resultFromInt 5 = Just AlreadyConsumed
    resultFromInt 6 = Just ResourceLeaked
    resultFromInt 7 = Just DoubleFree
    resultFromInt _ = Nothing

||| Check whether a tracked resource has been consumed
export
%foreign "C:ephapaxiser_is_consumed, libephapaxiser"
prim__isConsumed : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: check consumption status
export
isConsumed : Handle -> Handle -> IO Bool
isConsumed lib resource = do
  result <- primIO (prim__isConsumed (handlePtr lib) (handlePtr resource))
  pure (result /= 0)

||| Get the lifecycle state of a tracked resource
export
%foreign "C:ephapaxiser_get_lifecycle, libephapaxiser"
prim__getLifecycle : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: get lifecycle state
export
getLifecycle : Handle -> Handle -> IO ResourceLifecycle
getLifecycle lib resource = do
  result <- primIO (prim__getLifecycle (handlePtr lib) (handlePtr resource))
  pure $ case result of
    0 => Acquired
    1 => InUse
    _ => Consumed

||| Get the usage count of a tracked resource
export
%foreign "C:ephapaxiser_get_usage_count, libephapaxiser"
prim__getUsageCount : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: get usage count
export
getUsageCount : Handle -> Handle -> IO UsageCount
getUsageCount lib resource = do
  result <- primIO (prim__getUsageCount (handlePtr lib) (handlePtr resource))
  pure $ case result of
    0 => Unused
    1 => UsedOnce
    _ => UsedMultiple

--------------------------------------------------------------------------------
-- Ephapax Codegen
--------------------------------------------------------------------------------

||| Generate Ephapax wrapper code for a set of detected resources.
||| Output is written to the path specified by outPathPtr.
export
%foreign "C:ephapaxiser_generate_wrappers, libephapaxiser"
prim__generateWrappers : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for codegen
export
generateWrappers : Handle -> Bits64 -> IO (Either Result ())
generateWrappers lib outPathPtr = do
  result <- primIO (prim__generateWrappers (handlePtr lib) outPathPtr)
  pure $ if result == 0 then Right () else Left Error

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string allocated by the library
export
%foreign "C:ephapaxiser_free_string, libephapaxiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get a string result from the library
export
%foreign "C:ephapaxiser_get_string, libephapaxiser"
prim__getResult : Bits64 -> PrimIO Bits64

||| Safe string getter
export
getString : Handle -> IO (Maybe String)
getString h = do
  ptr <- primIO (prim__getResult (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:ephapaxiser_last_error, libephapaxiser"
prim__lastError : PrimIO Bits64

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
errorDescription Ok              = "Success"
errorDescription Error           = "Generic error"
errorDescription InvalidParam    = "Invalid parameter"
errorDescription OutOfMemory     = "Out of memory"
errorDescription NullPointer     = "Null pointer"
errorDescription AlreadyConsumed = "Resource already consumed (use-after-free)"
errorDescription ResourceLeaked  = "Resource leaked (not consumed before scope exit)"
errorDescription DoubleFree      = "Double-free attempt (resource consumed more than once)"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:ephapaxiser_version, libephapaxiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:ephapaxiser_build_info, libephapaxiser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:ephapaxiser_is_initialized, libephapaxiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
