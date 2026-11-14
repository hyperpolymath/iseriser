-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Atsiser
|||
||| This module declares all C-compatible functions for the atsiser FFI layer.
||| Functions cover C source analysis, ATS2 wrapper generation, ownership graph
||| construction, and round-trip compilation (ATS2 → C).
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Atsiser.ABI.Foreign

import Atsiser.ABI.Types
import Atsiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the atsiser analysis engine.
||| Returns a handle to the engine instance, or Nothing on failure.
export
%foreign "C:atsiser_init, libatsiser"
prim__init : PrimIO Bits64

||| Safe wrapper for engine initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up engine resources and free all analysis state
export
%foreign "C:atsiser_free, libatsiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- C Source Analysis
--------------------------------------------------------------------------------

||| Parse a C header file and populate the analysis state.
||| Returns 0 on success, error code on failure.
export
%foreign "C:atsiser_parse_header, libatsiser"
prim__parseHeader : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for C header parsing
export
parseHeader : Handle -> (headerPath : String) -> IO (Either Result ())
parseHeader h path = do
  result <- primIO (prim__parseHeader (handlePtr h) path)
  pure $ case result of
    0 => Right ()
    2 => Left InvalidParam
    n => Left Error

||| Analyse allocation patterns in parsed C sources.
||| Identifies malloc/calloc/realloc/free call pairs and builds
||| the allocation-site map.
export
%foreign "C:atsiser_analyse_allocations, libatsiser"
prim__analyseAllocations : Bits64 -> PrimIO Bits32

||| Safe wrapper for allocation analysis
export
analyseAllocations : Handle -> IO (Either Result Nat)
analyseAllocations h = do
  result <- primIO (prim__analyseAllocations (handlePtr h))
  pure $ case result of
    0 => Left Error  -- No allocations found (might be valid)
    n => Right (cast n)

||| Build the pointer ownership graph from analysed sources.
||| Tracks which functions allocate, borrow, transfer, and free pointers.
export
%foreign "C:atsiser_build_ownership_graph, libatsiser"
prim__buildOwnershipGraph : Bits64 -> PrimIO Bits32

||| Safe wrapper for ownership graph construction
export
buildOwnershipGraph : Handle -> IO (Either Result ())
buildOwnershipGraph h = do
  result <- primIO (prim__buildOwnershipGraph (handlePtr h))
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Detect buffer access patterns (array indexing, pointer arithmetic).
||| Returns the number of buffer access sites found.
export
%foreign "C:atsiser_detect_buffers, libatsiser"
prim__detectBuffers : Bits64 -> PrimIO Bits32

||| Safe wrapper for buffer detection
export
detectBuffers : Handle -> IO (Either Result Nat)
detectBuffers h = do
  result <- primIO (prim__detectBuffers (handlePtr h))
  pure $ Right (cast result)

--------------------------------------------------------------------------------
-- ATS2 Wrapper Generation
--------------------------------------------------------------------------------

||| Generate ATS2 viewtype wrappers for all tracked pointers.
||| Writes .sats (signature) and .dats (implementation) files to the output dir.
export
%foreign "C:atsiser_generate_viewtypes, libatsiser"
prim__generateViewtypes : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for viewtype generation
export
generateViewtypes : Handle -> (outputDir : String) -> IO (Either Result ())
generateViewtypes h dir = do
  result <- primIO (prim__generateViewtypes (handlePtr h) dir)
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Generate ATS2 proof obligations (praxi/prfun) for ownership transfer.
export
%foreign "C:atsiser_generate_proofs, libatsiser"
prim__generateProofs : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for proof generation
export
generateProofs : Handle -> (outputDir : String) -> IO (Either Result ())
generateProofs h dir = do
  result <- primIO (prim__generateProofs (handlePtr h) dir)
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Generate array bounds proofs for detected buffer accesses.
export
%foreign "C:atsiser_generate_bounds_proofs, libatsiser"
prim__generateBoundsProofs : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for bounds proof generation
export
generateBoundsProofs : Handle -> (outputDir : String) -> IO (Either Result ())
generateBoundsProofs h dir = do
  result <- primIO (prim__generateBoundsProofs (handlePtr h) dir)
  pure $ case result of
    0 => Right ()
    n => Left Error

--------------------------------------------------------------------------------
-- ATS2 Compilation (Round-Trip)
--------------------------------------------------------------------------------

||| Invoke patsopt to typecheck and compile ATS2 wrappers to C.
||| Returns 0 on success. Non-zero means proof obligations failed.
export
%foreign "C:atsiser_compile_ats2, libatsiser"
prim__compileAts2 : Bits64 -> String -> String -> PrimIO Bits32

||| Safe wrapper for ATS2 → C compilation
export
compileAts2 : Handle -> (ats2Dir : String) -> (cOutputDir : String) -> IO (Either Result ())
compileAts2 h atsDir cDir = do
  result <- primIO (prim__compileAts2 (handlePtr h) atsDir cDir)
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Verify that generated C code links against the original library.
export
%foreign "C:atsiser_verify_linkage, libatsiser"
prim__verifyLinkage : Bits64 -> String -> String -> PrimIO Bits32

||| Safe wrapper for linkage verification
export
verifyLinkage : Handle -> (generatedC : String) -> (originalLib : String) -> IO (Either Result ())
verifyLinkage h cPath libPath = do
  result <- primIO (prim__verifyLinkage (handlePtr h) cPath libPath)
  pure $ case result of
    0 => Right ()
    n => Left Error

--------------------------------------------------------------------------------
-- Analysis Results
--------------------------------------------------------------------------------

||| Get the number of allocation sites found
export
%foreign "C:atsiser_allocation_count, libatsiser"
prim__allocationCount : Bits64 -> PrimIO Bits32

||| Get allocation site count
export
allocationCount : Handle -> IO Nat
allocationCount h = do
  n <- primIO (prim__allocationCount (handlePtr h))
  pure (cast n)

||| Get the number of ownership edges in the graph
export
%foreign "C:atsiser_ownership_edge_count, libatsiser"
prim__ownershipEdgeCount : Bits64 -> PrimIO Bits32

||| Get ownership edge count
export
ownershipEdgeCount : Handle -> IO Nat
ownershipEdgeCount h = do
  n <- primIO (prim__ownershipEdgeCount (handlePtr h))
  pure (cast n)

||| Get the number of proof obligations generated
export
%foreign "C:atsiser_proof_count, libatsiser"
prim__proofCount : Bits64 -> PrimIO Bits32

||| Get proof obligation count
export
proofCount : Handle -> IO Nat
proofCount h = do
  n <- primIO (prim__proofCount (handlePtr h))
  pure (cast n)

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:atsiser_free_string, libatsiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get analysis report as JSON string
export
%foreign "C:atsiser_analysis_report, libatsiser"
prim__analysisReport : Bits64 -> PrimIO Bits64

||| Get analysis report
export
analysisReport : Handle -> IO (Maybe String)
analysisReport h = do
  ptr <- primIO (prim__analysisReport (handlePtr h))
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
%foreign "C:atsiser_last_error, libatsiser"
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
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"
errorDescription OwnershipViolation = "Ownership violation (double-free or use-after-free)"
errorDescription BoundsViolation = "Buffer bounds exceeded"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:atsiser_version, libatsiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:atsiser_build_info, libatsiser"
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

||| Check if engine is initialized
export
%foreign "C:atsiser_is_initialized, libatsiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
