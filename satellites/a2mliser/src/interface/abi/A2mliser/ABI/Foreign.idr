-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for a2mliser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer (src/interface/ffi/src/main.zig).
|||
||| All functions are declared here with type signatures and safety proofs.
||| The functions cover: library lifecycle, hashing, signing, verification,
||| envelope creation, and provenance chain operations.

module A2mliser.ABI.Foreign

import A2mliser.ABI.Types
import A2mliser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the a2mliser attestation engine.
||| Returns a handle to the engine instance, or Nothing on failure.
export
%foreign "C:a2mliser_init, liba2mliser"
prim__init : PrimIO Bits64

||| Safe wrapper for engine initialization
export
init : IO (Maybe AttestationHandle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up attestation engine resources
export
%foreign "C:a2mliser_free, liba2mliser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : AttestationHandle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Hashing Operations
--------------------------------------------------------------------------------

||| Compute a SHA-256 digest of a byte buffer.
||| The output buffer must be at least 32 bytes.
export
%foreign "C:a2mliser_hash_sha256, liba2mliser"
prim__hashSha256 : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Compute a BLAKE3 digest of a byte buffer.
||| The output buffer must be at least 32 bytes.
export
%foreign "C:a2mliser_hash_blake3, liba2mliser"
prim__hashBlake3 : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for hashing — dispatches to the correct algorithm
export
hash : AttestationHandle -> HashAlgorithm -> (inputPtr : Bits64) -> (inputLen : Bits32) -> IO (Either AttestationResult Bits64)
hash h SHA256 inputPtr inputLen = do
  result <- primIO (prim__hashSha256 (handlePtr h) inputPtr inputLen)
  pure $ case result of
    0 => Left Error
    digestPtr => Right (cast digestPtr)
hash h BLAKE3 inputPtr inputLen = do
  result <- primIO (prim__hashBlake3 (handlePtr h) inputPtr inputLen)
  pure $ case result of
    0 => Left Error
    digestPtr => Right (cast digestPtr)

--------------------------------------------------------------------------------
-- Signing Operations
--------------------------------------------------------------------------------

||| Sign a digest with Ed25519.
||| Takes: handle, private key pointer, digest pointer, output signature pointer.
||| Returns: 0 on success, error code on failure.
export
%foreign "C:a2mliser_sign_ed25519, liba2mliser"
prim__signEd25519 : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for Ed25519 signing
export
signEd25519 : AttestationHandle -> (privKeyPtr : Bits64) -> (digestPtr : Bits64) -> (sigOutPtr : Bits64) -> IO (Either AttestationResult ())
signEd25519 h privKeyPtr digestPtr sigOutPtr = do
  result <- primIO (prim__signEd25519 (handlePtr h) privKeyPtr digestPtr sigOutPtr)
  pure $ case result of
    0 => Right ()
    n => Left (resultFromInt n)
  where
    resultFromInt : Bits32 -> AttestationResult
    resultFromInt 1 = Error
    resultFromInt 2 = InvalidParam
    resultFromInt 3 = OutOfMemory
    resultFromInt 4 = NullPointer
    resultFromInt 8 = KeyExpired
    resultFromInt _ = Error

--------------------------------------------------------------------------------
-- Verification Operations
--------------------------------------------------------------------------------

||| Verify an Ed25519 signature against a digest.
||| Takes: handle, public key pointer, digest pointer, signature pointer.
||| Returns: 0 if valid, 5 (SignatureInvalid) if verification fails.
export
%foreign "C:a2mliser_verify_ed25519, liba2mliser"
prim__verifyEd25519 : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for Ed25519 verification
export
verifyEd25519 : AttestationHandle -> (pubKeyPtr : Bits64) -> (digestPtr : Bits64) -> (sigPtr : Bits64) -> IO (Either AttestationResult ())
verifyEd25519 h pubKeyPtr digestPtr sigPtr = do
  result <- primIO (prim__verifyEd25519 (handlePtr h) pubKeyPtr digestPtr sigPtr)
  pure $ case result of
    0 => Right ()
    5 => Left SignatureInvalid
    n => Left Error

--------------------------------------------------------------------------------
-- Envelope Operations
--------------------------------------------------------------------------------

||| Create an attestation envelope from a document.
||| Takes: handle, document buffer pointer, document length,
|||         hash algorithm id, signature algorithm id, private key pointer.
||| Returns: pointer to the allocated envelope, or null on failure.
export
%foreign "C:a2mliser_create_envelope, liba2mliser"
prim__createEnvelope : Bits64 -> Bits64 -> Bits32 -> Bits32 -> Bits32 -> Bits64 -> PrimIO Bits64

||| Safe wrapper for envelope creation
export
createEnvelope : AttestationHandle -> (docPtr : Bits64) -> (docLen : Bits32) -> HashAlgorithm -> SignatureAlgorithm -> (privKeyPtr : Bits64) -> IO (Either AttestationResult Bits64)
createEnvelope h docPtr docLen hashAlg sigAlg privKeyPtr = do
  let hashId = case hashAlg of { SHA256 => 0; BLAKE3 => 1 }
  let sigId = case sigAlg of { Ed25519 => 0; Ed448 => 1 }
  result <- primIO (prim__createEnvelope (handlePtr h) docPtr docLen hashId sigId privKeyPtr)
  pure $ if result == 0
    then Left Error
    else Right result

||| Free an attestation envelope
export
%foreign "C:a2mliser_free_envelope, liba2mliser"
prim__freeEnvelope : Bits64 -> Bits64 -> PrimIO ()

||| Safe wrapper for envelope deallocation
export
freeEnvelope : AttestationHandle -> (envelopePtr : Bits64) -> IO ()
freeEnvelope h envPtr = primIO (prim__freeEnvelope (handlePtr h) envPtr)

||| Verify an attestation envelope against its document.
||| Takes: handle, envelope pointer, document pointer, document length,
|||         public key pointer.
||| Returns: 0 if valid; error code otherwise.
export
%foreign "C:a2mliser_verify_envelope, liba2mliser"
prim__verifyEnvelope : Bits64 -> Bits64 -> Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for envelope verification
export
verifyEnvelope : AttestationHandle -> (envelopePtr : Bits64) -> (docPtr : Bits64) -> (docLen : Bits32) -> (pubKeyPtr : Bits64) -> IO (Either AttestationResult ())
verifyEnvelope h envPtr docPtr docLen pubKeyPtr = do
  result <- primIO (prim__verifyEnvelope (handlePtr h) envPtr docPtr docLen pubKeyPtr)
  pure $ case result of
    0 => Right ()
    5 => Left SignatureInvalid
    6 => Left DigestMismatch
    8 => Left KeyExpired
    _ => Left Error

--------------------------------------------------------------------------------
-- Provenance Chain Operations
--------------------------------------------------------------------------------

||| Extend a provenance chain with a new attestation.
||| Takes: handle, parent envelope pointer (or null for root), document pointer,
|||         document length, private key pointer.
||| Returns: pointer to the new chain entry, or null on failure.
export
%foreign "C:a2mliser_chain_extend, liba2mliser"
prim__chainExtend : Bits64 -> Bits64 -> Bits64 -> Bits32 -> Bits64 -> PrimIO Bits64

||| Safe wrapper for chain extension
export
chainExtend : AttestationHandle -> Maybe Bits64 -> (docPtr : Bits64) -> (docLen : Bits32) -> (privKeyPtr : Bits64) -> IO (Either AttestationResult Bits64)
chainExtend h parentPtr docPtr docLen privKeyPtr = do
  let parent = case parentPtr of { Nothing => 0; Just p => p }
  result <- primIO (prim__chainExtend (handlePtr h) parent docPtr docLen privKeyPtr)
  pure $ if result == 0
    then Left Error
    else Right result

||| Verify an entire provenance chain from leaf to root.
||| Takes: handle, chain leaf pointer, public key pointer.
||| Returns: 0 if valid; 7 (ChainBroken) if any link is invalid.
export
%foreign "C:a2mliser_chain_verify, liba2mliser"
prim__chainVerify : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for chain verification
export
chainVerify : AttestationHandle -> (chainLeafPtr : Bits64) -> (pubKeyPtr : Bits64) -> IO (Either AttestationResult ())
chainVerify h leafPtr pubKeyPtr = do
  result <- primIO (prim__chainVerify (handlePtr h) leafPtr pubKeyPtr)
  pure $ case result of
    0 => Right ()
    7 => Left ChainBroken
    5 => Left SignatureInvalid
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
%foreign "C:a2mliser_free_string, liba2mliser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:a2mliser_get_string, liba2mliser"
prim__getResult : Bits64 -> PrimIO Bits64

||| Safe string getter
export
getString : AttestationHandle -> IO (Maybe String)
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
%foreign "C:a2mliser_last_error, liba2mliser"
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
errorDescription : AttestationResult -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"
errorDescription SignatureInvalid = "Signature verification failed"
errorDescription DigestMismatch = "Document digest does not match envelope"
errorDescription ChainBroken = "Provenance chain is broken"
errorDescription KeyExpired = "Signing key has expired or been revoked"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:a2mliser_version, liba2mliser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:a2mliser_build_info, liba2mliser"
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

||| Check if attestation engine is initialized
export
%foreign "C:a2mliser_is_initialized, liba2mliser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : AttestationHandle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
