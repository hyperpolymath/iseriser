-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Tlaiser
|||
||| Declares all C-compatible functions implemented in the Zig FFI layer.
||| These functions form the bridge between the Rust CLI / Idris2 proofs
||| and the Zig-implemented state extraction engine, TLA+ code generator,
||| and TLC model checker process manager.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/src/main.zig

module Tlaiser.ABI.Foreign

import Tlaiser.ABI.Types
import Tlaiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the TLAiser engine.
||| Allocates internal state for state machine extraction and TLC management.
||| Returns a handle to the engine instance, or Nothing on failure.
export
%foreign "C:tlaiser_init, libtlaiser"
prim__init : PrimIO Bits64

||| Safe wrapper for engine initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up all engine resources: extracted state machines, generated specs,
||| TLC process handles, and allocated memory.
export
%foreign "C:tlaiser_free, libtlaiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- State Machine Extraction
--------------------------------------------------------------------------------

||| Extract a state machine from source code.
||| Parses the source file at the given path and extracts state/transition
||| patterns (enum + match arms, state tables, etc.).
|||
||| @param handle Engine handle
||| @param sourcePtr Pointer to null-terminated source file path
||| @return 0 on success, error code on failure
export
%foreign "C:tlaiser_extract_state_machine, libtlaiser"
prim__extractStateMachine : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for state machine extraction
export
extractStateMachine : Handle -> (sourcePath : Bits64) -> IO (Either Result ())
extractStateMachine h sourcePath = do
  result <- primIO (prim__extractStateMachine (handlePtr h) sourcePath)
  pure $ case result of
    0 => Right ()
    n => Left (intToResult n)
  where
    intToResult : Bits32 -> Result
    intToResult 1 = Error
    intToResult 2 = InvalidParam
    intToResult 3 = OutOfMemory
    intToResult 4 = NullPointer
    intToResult _ = Error

||| Get the number of states in the most recently extracted state machine.
export
%foreign "C:tlaiser_get_state_count, libtlaiser"
prim__getStateCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: get state count
export
getStateCount : Handle -> IO Nat
getStateCount h = do
  count <- primIO (prim__getStateCount (handlePtr h))
  pure (cast count)

||| Get the number of transitions in the most recently extracted state machine.
export
%foreign "C:tlaiser_get_transition_count, libtlaiser"
prim__getTransitionCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: get transition count
export
getTransitionCount : Handle -> IO Nat
getTransitionCount h = do
  count <- primIO (prim__getTransitionCount (handlePtr h))
  pure (cast count)

--------------------------------------------------------------------------------
-- TLA+ Specification Generation
--------------------------------------------------------------------------------

||| Generate a TLA+ specification from the extracted state machine.
||| The specification includes VARIABLES, Init, Next, and any declared
||| safety/liveness properties.
|||
||| @param handle Engine handle
||| @param outputPtr Pointer to null-terminated output file path
||| @return 0 on success, error code on failure
export
%foreign "C:tlaiser_generate_tlaplus, libtlaiser"
prim__generateTlaPlus : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for TLA+ generation
export
generateTlaPlus : Handle -> (outputPath : Bits64) -> IO (Either Result ())
generateTlaPlus h outputPath = do
  result <- primIO (prim__generateTlaPlus (handlePtr h) outputPath)
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Generate a PlusCal algorithm from the extracted state machine.
||| PlusCal is an imperative-style front-end to TLA+ that is often
||| easier to read for developers.
export
%foreign "C:tlaiser_generate_pluscal, libtlaiser"
prim__generatePlusCal : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for PlusCal generation
export
generatePlusCal : Handle -> (outputPath : Bits64) -> IO (Either Result ())
generatePlusCal h outputPath = do
  result <- primIO (prim__generatePlusCal (handlePtr h) outputPath)
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Add a safety property (invariant) to the generated specification.
||| Safety properties are checked as: □ P (P holds in every reachable state).
export
%foreign "C:tlaiser_add_safety_property, libtlaiser"
prim__addSafetyProperty : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: add a safety property by name and TLA+ expression
export
addSafetyProperty : Handle -> (namePtr : Bits64) -> (exprPtr : Bits64) -> IO (Either Result ())
addSafetyProperty h namePtr exprPtr = do
  result <- primIO (prim__addSafetyProperty (handlePtr h) namePtr exprPtr)
  pure $ case result of
    0 => Right ()
    n => Left Error

||| Add a liveness property to the generated specification.
||| Liveness properties are checked as: ◇ P or P ↝ Q.
export
%foreign "C:tlaiser_add_liveness_property, libtlaiser"
prim__addLivenessProperty : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: add a liveness property
export
addLivenessProperty : Handle -> (namePtr : Bits64) -> (exprPtr : Bits64) -> IO (Either Result ())
addLivenessProperty h namePtr exprPtr = do
  result <- primIO (prim__addLivenessProperty (handlePtr h) namePtr exprPtr)
  pure $ case result of
    0 => Right ()
    n => Left Error

--------------------------------------------------------------------------------
-- TLC Model Checker Execution
--------------------------------------------------------------------------------

||| Run the TLC model checker on the generated specification.
||| This invokes TLC as a subprocess, parses its output, and stores
||| the result (pass, safety violation, liveness violation, or deadlock).
|||
||| @param handle Engine handle
||| @param specPtr Pointer to null-terminated path to the .tla file
||| @param numWorkers Number of TLC worker threads (0 = auto)
||| @param maxStates Maximum number of states to explore (0 = unlimited)
||| @return 0 on success (check completed), error code on failure
export
%foreign "C:tlaiser_run_tlc, libtlaiser"
prim__runTlc : Bits64 -> Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for TLC execution
export
runTlc : Handle -> (specPath : Bits64) -> (numWorkers : Bits32) -> (maxStates : Bits64) -> IO (Either Result ())
runTlc h specPath workers maxSt = do
  result <- primIO (prim__runTlc (handlePtr h) specPath workers maxSt)
  pure $ case result of
    0 => Right ()
    5 => Left TlcError
    6 => Left SpecSyntaxError
    7 => Left StateSpaceExhausted
    n => Left Error

||| Get the model check result type after a TLC run.
||| Returns: 0 = all properties hold, 1 = safety violation, 2 = liveness violation,
||| 3 = deadlock, 4 = interrupted.
export
%foreign "C:tlaiser_get_result_type, libtlaiser"
prim__getResultType : Bits64 -> PrimIO Bits32

||| Safe wrapper: get result type
export
getResultType : Handle -> IO Bits32
getResultType h = primIO (prim__getResultType (handlePtr h))

||| Get the number of states explored during the last TLC run.
export
%foreign "C:tlaiser_get_states_explored, libtlaiser"
prim__getStatesExplored : Bits64 -> PrimIO Bits64

||| Safe wrapper: get states explored count
export
getStatesExplored : Handle -> IO Nat
getStatesExplored h = do
  count <- primIO (prim__getStatesExplored (handlePtr h))
  pure (cast count)

||| Get the counterexample trace length (0 if no violation).
export
%foreign "C:tlaiser_get_trace_length, libtlaiser"
prim__getTraceLength : Bits64 -> PrimIO Bits32

||| Safe wrapper: get trace length
export
getTraceLength : Handle -> IO Nat
getTraceLength h = do
  len <- primIO (prim__getTraceLength (handlePtr h))
  pure (cast len)

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string allocated by TLAiser
export
%foreign "C:tlaiser_free_string, libtlaiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result (e.g., generated spec content, error message)
export
%foreign "C:tlaiser_get_string, libtlaiser"
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

||| Get the counterexample trace as a formatted string.
export
%foreign "C:tlaiser_get_trace_string, libtlaiser"
prim__getTraceString : Bits64 -> PrimIO Bits64

||| Safe wrapper: get counterexample trace as formatted string
export
getTraceString : Handle -> IO (Maybe String)
getTraceString h = do
  ptr <- primIO (prim__getTraceString (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message from the engine
export
%foreign "C:tlaiser_last_error, libtlaiser"
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
errorDescription TlcError = "TLC model checker error"
errorDescription SpecSyntaxError = "Generated TLA+ spec has syntax errors"
errorDescription StateSpaceExhausted = "State space exhausted — too many states to explore"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version string
export
%foreign "C:tlaiser_version, libtlaiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info (compiler version, build date, etc.)
export
%foreign "C:tlaiser_build_info, libtlaiser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Callback Support
--------------------------------------------------------------------------------

||| Progress callback type (C ABI).
||| Called during TLC execution to report progress.
||| Arguments: (statesExplored : u64, depth : u32) -> shouldContinue : u32
public export
ProgressCallback : Type
ProgressCallback = Bits64 -> Bits32 -> Bits32

||| Register a progress callback for TLC runs
export
%foreign "C:tlaiser_register_progress_callback, libtlaiser"
prim__registerProgressCallback : Bits64 -> AnyPtr -> PrimIO Bits32

-- TODO: Implement safe callback registration.
-- The callback must be wrapped via a proper FFI callback mechanism.
-- Do NOT use cast — it is banned per project safety standards.
-- See: https://idris2.readthedocs.io/en/latest/ffi/ffi.html#callbacks

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if engine handle is initialized and ready
export
%foreign "C:tlaiser_is_initialized, libtlaiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
