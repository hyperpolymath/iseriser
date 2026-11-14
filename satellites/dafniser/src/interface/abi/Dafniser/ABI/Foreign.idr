-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Dafniser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer (ffi/zig/src/main.zig).
|||
||| The FFI surface covers two domains:
|||   1. Library lifecycle (init, free, version)
|||   2. Dafny compilation and Z3 verification pipeline
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Dafniser.ABI.Foreign

import Dafniser.ABI.Types
import Dafniser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the dafniser library.
||| Returns a handle to the library instance, or Nothing on failure.
export
%foreign "C:dafniser_init, libdafniser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up dafniser library resources.
export
%foreign "C:dafniser_free, libdafniser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Specification Loading
--------------------------------------------------------------------------------

||| Load a specification tree from a TOML manifest file.
||| The path is a null-terminated C string.
||| Returns a handle to the parsed SpecTree, or null on parse failure.
export
%foreign "C:dafniser_load_spec, libdafniser"
prim__loadSpec : Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: load a spec tree from a manifest path.
export
loadSpec : Handle -> (manifestPath : Bits64) -> IO (Maybe Handle)
loadSpec h path = do
  ptr <- primIO (prim__loadSpec (handlePtr h) path)
  pure (createHandle ptr)

||| Free a previously loaded spec tree.
export
%foreign "C:dafniser_free_spec, libdafniser"
prim__freeSpec : Bits64 -> PrimIO ()

||| Safe wrapper: release spec tree resources.
export
freeSpec : Handle -> IO ()
freeSpec h = primIO (prim__freeSpec (handlePtr h))

--------------------------------------------------------------------------------
-- Dafny Code Generation
--------------------------------------------------------------------------------

||| Generate Dafny source code from a loaded spec tree.
||| Writes .dfy files to the output directory (null-terminated C string).
||| Returns 0 on success, non-zero on failure.
export
%foreign "C:dafniser_generate_dafny, libdafniser"
prim__generateDafny : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: generate Dafny source from a spec tree.
export
generateDafny : Handle -> (outputDir : Bits64) -> IO (Either Result ())
generateDafny h outDir = do
  result <- primIO (prim__generateDafny (handlePtr h) outDir)
  pure $ case result of
    0 => Right ()
    _ => Left Error

--------------------------------------------------------------------------------
-- Z3 Verification
--------------------------------------------------------------------------------

||| Invoke the Dafny verifier (Z3 backend) on generated .dfy files.
||| Returns a handle to the verification results, or null on failure.
export
%foreign "C:dafniser_verify, libdafniser"
prim__verify : Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: run Z3 verification on generated Dafny source.
export
verify : Handle -> (dafnyDir : Bits64) -> IO (Maybe Handle)
verify h dir = do
  ptr <- primIO (prim__verify (handlePtr h) dir)
  pure (createHandle ptr)

||| Query the number of verification results.
export
%foreign "C:dafniser_result_count, libdafniser"
prim__resultCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: how many functions were verified?
export
resultCount : Handle -> IO Bits32
resultCount h = primIO (prim__resultCount (handlePtr h))

||| Query the verification status of a specific function by index.
||| Returns the tag: 0=Verified, 1=Counterexample, 2=Timeout, 3=InternalError
export
%foreign "C:dafniser_result_status, libdafniser"
prim__resultStatus : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: get verification status for function at index.
export
resultStatus : Handle -> (index : Bits32) -> IO Bits32
resultStatus h idx = primIO (prim__resultStatus (handlePtr h) idx)

||| Get the counterexample witness string for a failed verification.
||| Returns null if the result at the given index is not a Counterexample.
export
%foreign "C:dafniser_result_witness, libdafniser"
prim__resultWitness : Bits64 -> Bits32 -> PrimIO Bits64

--------------------------------------------------------------------------------
-- Target Language Compilation
--------------------------------------------------------------------------------

||| Compile verified Dafny to a target language.
||| The target is an integer: 0=C#, 1=Java, 2=Go, 3=Python, 4=JavaScript
||| Returns 0 on success, non-zero on failure.
export
%foreign "C:dafniser_compile_target, libdafniser"
prim__compileTarget : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: compile verified Dafny to a target language.
export
compileTarget : Handle -> (dafnyDir : Bits64) -> DafnyTarget -> IO (Either Result ())
compileTarget h dir target = do
  let targetInt = case target of
        CSharp     => 0
        Java       => 1
        Go         => 2
        Python     => 3
        JavaScript => 4
  result <- primIO (prim__compileTarget (handlePtr h) dir targetInt)
  pure $ case result of
    0 => Right ()
    _ => Left Error

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free a C string allocated by the library
export
%foreign "C:dafniser_free_string, libdafniser"
prim__freeString : Bits64 -> PrimIO ()

||| Get a string result from the library
export
%foreign "C:dafniser_get_string, libdafniser"
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
%foreign "C:dafniser_last_error, libdafniser"
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

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:dafniser_version, libdafniser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:dafniser_build_info, libdafniser"
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
%foreign "C:dafniser_is_initialized, libdafniser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
