-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Oblibeniser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. The FFI surface covers:
|||   - Library lifecycle (init/free)
|||   - Operation recording (capture forward operations)
|||   - Inverse computation (compute and apply undo)
|||   - Audit trail (append, query, verify chain integrity)
|||   - Undo stack management (push, pop, peek, time-travel)
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Oblibeniser.ABI.Foreign

import Oblibeniser.ABI.Types
import Oblibeniser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the oblibeniser library
||| Returns a handle to the library instance, or Nothing on failure
export
%foreign "C:oblibeniser_init, liboblibeniser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources and flush audit trail
export
%foreign "C:oblibeniser_free, liboblibeniser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Operation Recording
--------------------------------------------------------------------------------

||| Record a forward operation with a pre-state snapshot.
||| Returns the operation ID for later inverse lookup.
export
%foreign "C:oblibeniser_record_forward, liboblibeniser"
prim__recordForward : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: record a forward operation
||| Takes a handle, operation name pointer, and pre-state snapshot pointer.
||| Returns the assigned operation ID, or Nothing on failure.
export
recordForward : Handle -> (namePtr : Bits64) -> (snapshotPtr : Bits64) -> IO (Maybe Bits64)
recordForward h namePtr snapPtr = do
  opId <- primIO (prim__recordForward (handlePtr h) namePtr snapPtr)
  pure (if opId == 0 then Nothing else Just opId)

||| Finalise a forward operation with its post-state snapshot.
||| Must be called after the operation completes to close the record.
export
%foreign "C:oblibeniser_finalise_forward, liboblibeniser"
prim__finaliseForward : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: finalise a forward operation
export
finaliseForward : Handle -> (opId : Bits64) -> (postSnapshotPtr : Bits64) -> IO (Either Result ())
finaliseForward h opId snapPtr = do
  result <- primIO (prim__finaliseForward (handlePtr h) opId snapPtr)
  pure $ case result of
    0 => Right ()
    _ => Left Error

--------------------------------------------------------------------------------
-- Inverse Computation
--------------------------------------------------------------------------------

||| Compute the inverse of a recorded operation.
||| The inverse is derived from the pre/post state snapshots.
export
%foreign "C:oblibeniser_compute_inverse, liboblibeniser"
prim__computeInverse : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: compute inverse for an operation
export
computeInverse : Handle -> (opId : Bits64) -> IO (Either Result ())
computeInverse h opId = do
  result <- primIO (prim__computeInverse (handlePtr h) opId)
  pure $ case result of
    0 => Right ()
    5 => Left NotReversible
    7 => Left InverseProofFailed
    _ => Left Error

||| Apply the inverse of a recorded operation (undo).
||| Restores the system to the pre-operation state.
export
%foreign "C:oblibeniser_apply_inverse, liboblibeniser"
prim__applyInverse : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: apply inverse (undo an operation)
export
applyInverse : Handle -> (opId : Bits64) -> IO (Either Result ())
applyInverse h opId = do
  result <- primIO (prim__applyInverse (handlePtr h) opId)
  pure $ case result of
    0 => Right ()
    5 => Left NotReversible
    7 => Left InverseProofFailed
    _ => Left Error

||| Verify that an operation's inverse is correct.
||| Checks that inverse(forward(x)) = x by comparing state hashes.
export
%foreign "C:oblibeniser_verify_inverse, liboblibeniser"
prim__verifyInverse : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: verify inverse correctness
export
verifyInverse : Handle -> (opId : Bits64) -> IO (Either Result ())
verifyInverse h opId = do
  result <- primIO (prim__verifyInverse (handlePtr h) opId)
  pure $ case result of
    0 => Right ()
    7 => Left InverseProofFailed
    _ => Left Error

--------------------------------------------------------------------------------
-- Audit Trail
--------------------------------------------------------------------------------

||| Append an entry to the audit trail.
||| The entry is hash-chained to the previous entry for tamper detection.
export
%foreign "C:oblibeniser_audit_append, liboblibeniser"
prim__auditAppend : Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: append an audit entry
||| Takes handle, operation ID, actor pointer, auth hash, and direction flag.
export
auditAppend : Handle -> (opId : Bits64) -> (actorPtr : Bits64) -> (authHash : Bits64) -> (isForward : Bool) -> IO (Either Result ())
auditAppend h opId actorPtr authHash isForward = do
  let flag : Bits32 = if isForward then 1 else 0
  result <- primIO (prim__auditAppend (handlePtr h) opId actorPtr authHash flag)
  pure $ case result of
    0 => Right ()
    6 => Left AuditViolation
    _ => Left Error

||| Verify the integrity of the entire audit chain.
||| Returns Ok if all hash links are valid, AuditViolation otherwise.
export
%foreign "C:oblibeniser_audit_verify_chain, liboblibeniser"
prim__auditVerifyChain : Bits64 -> PrimIO Bits32

||| Safe wrapper: verify audit chain integrity
export
auditVerifyChain : Handle -> IO (Either Result ())
auditVerifyChain h = do
  result <- primIO (prim__auditVerifyChain (handlePtr h))
  pure $ case result of
    0 => Right ()
    6 => Left AuditViolation
    _ => Left Error

||| Query audit entries by operation ID.
||| Returns a pointer to a list of matching entries, or null.
export
%foreign "C:oblibeniser_audit_query, liboblibeniser"
prim__auditQuery : Bits64 -> Bits64 -> PrimIO Bits64

||| Safe wrapper: query audit trail for an operation
export
auditQuery : Handle -> (opId : Bits64) -> IO (Maybe Bits64)
auditQuery h opId = do
  ptr <- primIO (prim__auditQuery (handlePtr h) opId)
  pure (if ptr == 0 then Nothing else Just ptr)

--------------------------------------------------------------------------------
-- Undo Stack Management
--------------------------------------------------------------------------------

||| Push an operation onto the undo stack.
export
%foreign "C:oblibeniser_undo_push, liboblibeniser"
prim__undoPush : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: push to undo stack
export
undoPush : Handle -> (opId : Bits64) -> IO (Either Result ())
undoPush h opId = do
  result <- primIO (prim__undoPush (handlePtr h) opId)
  pure $ case result of
    0 => Right ()
    3 => Left OutOfMemory
    _ => Left Error

||| Pop and apply the inverse of the top operation (undo).
export
%foreign "C:oblibeniser_undo_pop, liboblibeniser"
prim__undoPop : Bits64 -> PrimIO Bits64

||| Safe wrapper: pop from undo stack (performs undo)
export
undoPop : Handle -> IO (Maybe Bits64)
undoPop h = do
  opId <- primIO (prim__undoPop (handlePtr h))
  pure (if opId == 0 then Nothing else Just opId)

||| Get the current undo stack depth.
export
%foreign "C:oblibeniser_undo_depth, liboblibeniser"
prim__undoDepth : Bits64 -> PrimIO Bits32

||| Safe wrapper: query undo stack depth
export
undoDepth : Handle -> IO Bits32
undoDepth h = primIO (prim__undoDepth (handlePtr h))

||| Time-travel: rewind to a specific operation in the stack.
||| Applies all inverses from the top down to the target operation.
export
%foreign "C:oblibeniser_time_travel, liboblibeniser"
prim__timeTravel : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper: time-travel to a specific operation
export
timeTravel : Handle -> (targetOpId : Bits64) -> IO (Either Result ())
timeTravel h targetOpId = do
  result <- primIO (prim__timeTravel (handlePtr h) targetOpId)
  pure $ case result of
    0 => Right ()
    5 => Left NotReversible
    _ => Left Error

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:oblibeniser_free_string, liboblibeniser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:oblibeniser_get_string, liboblibeniser"
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
%foreign "C:oblibeniser_last_error, liboblibeniser"
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
errorDescription NotReversible = "Operation is not reversible"
errorDescription AuditViolation = "Audit trail integrity violation"
errorDescription InverseProofFailed = "Inverse proof verification failed"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:oblibeniser_version, liboblibeniser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:oblibeniser_build_info, liboblibeniser"
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
%foreign "C:oblibeniser_is_initialized, liboblibeniser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
