-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Mylangiser
|||
||| Declares all C-compatible functions implemented in the Zig FFI layer.
||| These functions cover the full lifecycle of progressive-disclosure
||| generation: library init, API surface analysis, complexity scoring,
||| disclosure-level assignment, and layered wrapper generation.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/src/main.zig

module Mylangiser.ABI.Foreign

import Mylangiser.ABI.Types
import Mylangiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialise the mylangiser library.
||| Returns a handle to the library instance, or Nothing on failure.
export
%foreign "C:mylangiser_init, libmylangiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialisation
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources
export
%foreign "C:mylangiser_free, libmylangiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- API Surface Analysis
--------------------------------------------------------------------------------

||| Analyse an API surface from a serialised manifest buffer.
||| Populates the internal endpoint table; call after init.
||| Returns 0 on success, error code otherwise.
export
%foreign "C:mylangiser_analyse_surface, libmylangiser"
prim__analyseSurface : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: analyse API surface from a manifest buffer
export
analyseSurface : Handle -> (bufferPtr : Bits64) -> (bufferLen : Bits32) -> IO (Either Result ())
analyseSurface h buf len = do
  result <- primIO (prim__analyseSurface (handlePtr h) buf len)
  pure $ case result of
    0 => Right ()
    2 => Left InvalidParam
    5 => Left EndpointNotFound
    _ => Left Error

||| Get the number of endpoints discovered during analysis
export
%foreign "C:mylangiser_endpoint_count, libmylangiser"
prim__endpointCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: get endpoint count
export
endpointCount : Handle -> IO Bits32
endpointCount h = primIO (prim__endpointCount (handlePtr h))

--------------------------------------------------------------------------------
-- Complexity Scoring
--------------------------------------------------------------------------------

||| Compute complexity scores for all analysed endpoints.
||| Must be called after analyseSurface. Populates internal score table.
export
%foreign "C:mylangiser_compute_scores, libmylangiser"
prim__computeScores : Bits64 -> PrimIO Bits32

||| Safe wrapper: compute complexity scores
export
computeScores : Handle -> IO (Either Result ())
computeScores h = do
  result <- primIO (prim__computeScores (handlePtr h))
  pure $ case result of
    0 => Right ()
    _ => Left Error

||| Get the complexity score for a specific endpoint by index.
||| Returns the score (0-100) or an error code.
export
%foreign "C:mylangiser_get_score, libmylangiser"
prim__getScore : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: get complexity score for an endpoint
export
getScore : Handle -> (endpointIndex : Bits32) -> IO (Either Result ComplexityScore)
getScore h idx = do
  raw <- primIO (prim__getScore (handlePtr h) idx)
  pure $ case mkComplexityScore raw of
    Just s  => Right s
    Nothing => Left InvalidScore

--------------------------------------------------------------------------------
-- Layer Generation
--------------------------------------------------------------------------------

||| Generate layered wrappers for all endpoints.
||| Must be called after computeScores. Allocates internal wrapper table.
export
%foreign "C:mylangiser_generate_layers, libmylangiser"
prim__generateLayers : Bits64 -> PrimIO Bits32

||| Safe wrapper: generate disclosure-level layers
export
generateLayers : Handle -> IO (Either Result ())
generateLayers h = do
  result <- primIO (prim__generateLayers (handlePtr h))
  pure $ case result of
    0 => Right ()
    _ => Left Error

||| Get the assigned disclosure level for an endpoint by index.
||| Returns 0=Beginner, 1=Intermediate, 2=Expert.
export
%foreign "C:mylangiser_get_level, libmylangiser"
prim__getLevel : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: get disclosure level for an endpoint
export
getLevel : Handle -> (endpointIndex : Bits32) -> IO (Either Result DisclosureLevel)
getLevel h idx = do
  raw <- primIO (prim__getLevel (handlePtr h) idx)
  pure $ case raw of
    0 => Right Beginner
    1 => Right Intermediate
    2 => Right Expert
    _ => Left InvalidParam

||| Get the number of smart defaults applied to an endpoint.
export
%foreign "C:mylangiser_default_count, libmylangiser"
prim__defaultCount : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: get smart default count for an endpoint
export
defaultCount : Handle -> (endpointIndex : Bits32) -> IO Bits32
defaultCount h idx = primIO (prim__defaultCount (handlePtr h) idx)

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:mylangiser_free_string, libmylangiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:mylangiser_get_string, libmylangiser"
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
%foreign "C:mylangiser_last_error, libmylangiser"
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
errorDescription Ok               = "Success"
errorDescription Error            = "Generic error"
errorDescription InvalidParam     = "Invalid parameter"
errorDescription OutOfMemory      = "Out of memory"
errorDescription NullPointer      = "Null pointer"
errorDescription EndpointNotFound = "Endpoint not found in API surface"
errorDescription InvalidScore     = "Complexity score out of valid range (0-100)"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:mylangiser_version, libmylangiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:mylangiser_build_info, libmylangiser"
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

||| Check if library is initialised
export
%foreign "C:mylangiser_is_initialized, libmylangiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialisation status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
