-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Ponyiser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. Functions cover:
||| - Library lifecycle (init/free)
||| - Capability analysis (infer capabilities for data references)
||| - Actor codegen (generate Pony actors and behaviours)
||| - Capability validation (check subtyping and sendability)
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Ponyiser.ABI.Foreign

import Ponyiser.ABI.Types
import Ponyiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the ponyiser library.
||| Returns a handle to the library instance, or Nothing on failure.
export
%foreign "C:ponyiser_init, libponyiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources.
export
%foreign "C:ponyiser_free, libponyiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Capability Analysis
--------------------------------------------------------------------------------

||| Analyse a data reference and infer the most permissive safe capability.
|||
||| Given a description of how data is accessed (read/write/send patterns),
||| returns the inferred RefCapability as a C integer:
||| 0=iso, 1=val, 2=ref, 3=box, 4=trn, 5=tag
export
%foreign "C:ponyiser_infer_capability, libponyiser"
prim__inferCapability : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for capability inference.
||| Takes a handle and a pointer to an access pattern descriptor.
export
inferCapability : Handle -> Bits64 -> IO (Maybe RefCapability)
inferCapability h patternPtr = do
  result <- primIO (prim__inferCapability (handlePtr h) patternPtr)
  pure (intToCap result)

||| Check whether a capability assignment satisfies Pony's subtyping rules.
|||
||| Given two capabilities (as C integers), checks if the first subtypes the second.
||| Returns 0 for success (valid subtyping), non-zero for error.
export
%foreign "C:ponyiser_check_subtyping, libponyiser"
prim__checkSubtyping : Bits64 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for subtyping check.
export
checkSubtyping : Handle -> RefCapability -> RefCapability -> IO (Either Result ())
checkSubtyping h sub super = do
  result <- primIO (prim__checkSubtyping (handlePtr h) (capToInt sub) (capToInt super))
  pure $ case result of
    0 => Right ()
    _ => Left InvalidCapability

||| Validate that a capability is sendable (can cross actor boundaries).
|||
||| Returns 0 if sendable, 6 (SendabilityViolation) if not.
export
%foreign "C:ponyiser_check_sendable, libponyiser"
prim__checkSendable : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for sendability check.
export
checkSendable : Handle -> RefCapability -> IO (Either Result ())
checkSendable h cap = do
  result <- primIO (prim__checkSendable (handlePtr h) (capToInt cap))
  pure $ case result of
    0 => Right ()
    _ => Left SendabilityViolation

--------------------------------------------------------------------------------
-- Actor Codegen
--------------------------------------------------------------------------------

||| Generate a Pony actor from a descriptor.
|||
||| Takes a handle and a pointer to an actor descriptor (name, fields, behaviours).
||| Writes generated Pony source to the output buffer.
||| Returns 0 on success, non-zero on error.
export
%foreign "C:ponyiser_generate_actor, libponyiser"
prim__generateActor : Bits64 -> Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for actor generation.
export
generateActor : Handle -> (descriptorPtr : Bits64) -> (outBuf : Bits64) -> (outLen : Bits32) -> IO (Either Result ())
generateActor h desc outBuf outLen = do
  result <- primIO (prim__generateActor (handlePtr h) desc outBuf outLen)
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
    resultFromInt 5 = InvalidCapability
    resultFromInt 6 = SendabilityViolation
    resultFromInt 7 = ActorNotFound
    resultFromInt _ = Error

||| Generate a Pony behaviour from a descriptor.
|||
||| Takes a handle, an actor name pointer, and a behaviour descriptor.
||| Validates that all behaviour parameters are sendable before generating.
export
%foreign "C:ponyiser_generate_behaviour, libponyiser"
prim__generateBehaviour : Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for behaviour generation.
export
generateBehaviour : Handle -> (actorNamePtr : Bits64) -> (behaviourDescPtr : Bits64) -> (outBuf : Bits64) -> (outLen : Bits32) -> IO (Either Result ())
generateBehaviour h actor beh outBuf outLen = do
  result <- primIO (prim__generateBehaviour (handlePtr h) actor beh outBuf outLen)
  pure $ case result of
    0 => Right ()
    n => Left Error

--------------------------------------------------------------------------------
-- Causal Message Generation
--------------------------------------------------------------------------------

||| Generate a causal message type for actor-to-actor communication.
|||
||| Validates sendability of the payload capability before generating.
export
%foreign "C:ponyiser_generate_message, libponyiser"
prim__generateMessage : Bits64 -> Bits64 -> Bits64 -> Bits32 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for message generation.
export
generateMessage : Handle -> (senderPtr : Bits64) -> (receiverPtr : Bits64)
               -> (payloadCap : RefCapability) -> (outBuf : Bits64)
               -> (outLen : Bits32) -> IO (Either Result ())
generateMessage h sender receiver cap outBuf outLen = do
  result <- primIO (prim__generateMessage (handlePtr h) sender receiver (capToInt cap) outBuf outLen)
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

||| Free C string
export
%foreign "C:ponyiser_free_string, libponyiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:ponyiser_get_string, libponyiser"
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
%foreign "C:ponyiser_last_error, libponyiser"
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
errorDescription InvalidCapability = "Invalid capability assignment"
errorDescription SendabilityViolation = "Capability is not sendable across actor boundaries"
errorDescription ActorNotFound = "Actor not found"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:ponyiser_version, libponyiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:ponyiser_build_info, libponyiser"
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
%foreign "C:ponyiser_is_initialized, libponyiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
