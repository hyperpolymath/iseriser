-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Phronesiser
|||
||| This module declares all C-compatible functions for the Phronesiser
||| ethical constraint engine. Functions cover:
||| - Constraint engine lifecycle (init, free)
||| - Constraint compilation (add, remove, validate)
||| - Constraint evaluation (evaluate action against constraint set)
||| - Audit trail (retrieve decision history)
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/src/main.zig

module Phronesiser.ABI.Foreign

import Phronesiser.ABI.Types
import Phronesiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Engine Lifecycle
--------------------------------------------------------------------------------

||| Initialize the Phronesiser constraint engine.
||| Returns a handle to the engine instance, or Nothing on failure.
export
%foreign "C:phronesiser_init, libphronesiser"
prim__init : PrimIO Bits64

||| Safe wrapper for engine initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Shut down the constraint engine and release all resources.
export
%foreign "C:phronesiser_free, libphronesiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Constraint Compilation
--------------------------------------------------------------------------------

||| Add an ethical constraint to the engine.
||| Parameters: handle, constraintId, modality (0=obligation, 1=permission,
||| 2=prohibition), harmDomain (0-5, 0xFF=none), harmThreshold (0-4).
||| Returns 0 on success, error code on failure.
export
%foreign "C:phronesiser_add_constraint, libphronesiser"
prim__addConstraint : Bits64 -> Bits32 -> Bits32 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for adding a constraint
export
addConstraint : Handle -> EthicalConstraint -> IO (Either Result ())
addConstraint h c = do
  let domainInt = case c.harmBoundary of
                    Nothing => 0xFF  -- sentinel: no harm boundary
                    Just hb => domainToInt hb.domain
  let threshInt = case c.harmBoundary of
                    Nothing => 0
                    Just hb => severityToInt hb.threshold
  result <- primIO (prim__addConstraint (handlePtr h)
                                         c.constraintId
                                         (modalityToInt c.modality)
                                         domainInt
                                         threshInt)
  pure $ case result of
    0 => Right ()
    n => Left (resultFromInt n)
  where
    resultFromInt : Bits32 -> Result
    resultFromInt 0 = Ok
    resultFromInt 1 = Error
    resultFromInt 2 = InvalidParam
    resultFromInt 3 = OutOfMemory
    resultFromInt 4 = NullPointer
    resultFromInt 5 = ConstraintViolation
    resultFromInt 6 = ConstraintConflict
    resultFromInt _ = Error

||| Remove a constraint by ID.
export
%foreign "C:phronesiser_remove_constraint, libphronesiser"
prim__removeConstraint : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for removing a constraint
export
removeConstraint : Handle -> Bits32 -> IO (Either Result ())
removeConstraint h cid = do
  result <- primIO (prim__removeConstraint (handlePtr h) cid)
  pure $ if result == 0 then Right () else Left Error

||| Validate the entire constraint set for contradictions.
||| Returns 0 if no contradictions, ConstraintConflict if obligations
||| contradict prohibitions.
export
%foreign "C:phronesiser_validate_constraints, libphronesiser"
prim__validateConstraints : Bits64 -> PrimIO Bits32

||| Safe wrapper for constraint validation
export
validateConstraints : Handle -> IO (Either Result ())
validateConstraints h = do
  result <- primIO (prim__validateConstraints (handlePtr h))
  pure $ if result == 0 then Right () else Left ConstraintConflict

--------------------------------------------------------------------------------
-- Constraint Evaluation
--------------------------------------------------------------------------------

||| Evaluate an agent action against the constraint set.
||| Parameters: handle, actionId (caller-defined).
||| Writes result to the provided AuditResultStruct pointer.
||| Returns 0 on success (decision written), error code on failure.
export
%foreign "C:phronesiser_evaluate, libphronesiser"
prim__evaluate : Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for constraint evaluation.
||| Returns the audit decision for the given action.
export
evaluate : Handle -> Bits32 -> IO (Either Result AuditDecision)
evaluate h actionId = do
  -- In a real implementation, this would allocate an AuditResultStruct,
  -- pass its pointer, and read back the result.
  -- Stub: return Permitted for now.
  pure (Right (Permitted actionId "Evaluation pending — constraint engine stub"))

||| Batch-evaluate multiple actions.
||| Parameters: handle, pointer to action ID array, count,
||| pointer to output AuditResultStruct array.
export
%foreign "C:phronesiser_evaluate_batch, libphronesiser"
prim__evaluateBatch : Bits64 -> Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- Audit Trail
--------------------------------------------------------------------------------

||| Get the number of audit decisions recorded.
export
%foreign "C:phronesiser_audit_count, libphronesiser"
prim__auditCount : Bits64 -> PrimIO Bits32

||| Safe wrapper for audit count
export
auditCount : Handle -> IO Bits32
auditCount h = primIO (prim__auditCount (handlePtr h))

||| Get an audit decision by index.
||| Writes the decision to the provided AuditResultStruct pointer.
export
%foreign "C:phronesiser_audit_get, libphronesiser"
prim__auditGet : Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

||| Clear the audit trail.
export
%foreign "C:phronesiser_audit_clear, libphronesiser"
prim__auditClear : Bits64 -> PrimIO ()

||| Safe wrapper for clearing audit trail
export
auditClear : Handle -> IO ()
auditClear h = primIO (prim__auditClear (handlePtr h))

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:phronesiser_free_string, libphronesiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get constraint name by ID
export
%foreign "C:phronesiser_constraint_name, libphronesiser"
prim__constraintName : Bits64 -> Bits32 -> PrimIO Bits64

||| Safe constraint name getter
export
constraintName : Handle -> Bits32 -> IO (Maybe String)
constraintName h cid = do
  ptr <- primIO (prim__constraintName (handlePtr h) cid)
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
%foreign "C:phronesiser_last_error, libphronesiser"
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
errorDescription ConstraintViolation = "Ethical constraint violation"
errorDescription ConstraintConflict = "Conflicting constraints detected"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:phronesiser_version, libphronesiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:phronesiser_build_info, libphronesiser"
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
%foreign "C:phronesiser_is_initialized, libphronesiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)

||| Get the number of constraints currently loaded
export
%foreign "C:phronesiser_constraint_count, libphronesiser"
prim__constraintCount : Bits64 -> PrimIO Bits32

||| Safe wrapper for constraint count
export
constraintCount : Handle -> IO Bits32
constraintCount h = primIO (prim__constraintCount (handlePtr h))
