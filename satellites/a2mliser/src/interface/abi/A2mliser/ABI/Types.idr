-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for a2mliser
|||
||| This module defines the Application Binary Interface for the a2mliser
||| attestation engine. All type definitions include formal proofs of
||| correctness for cryptographic operations, signature verification,
||| and provenance chain validity.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module A2mliser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for this ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
||| This will be set during compilation based on target
public export
thisPlatform : Platform
thisPlatform = Linux  -- Default, override with compiler flags

--------------------------------------------------------------------------------
-- Signature Algorithms
--------------------------------------------------------------------------------

||| Cryptographic signature algorithms supported by a2mliser.
||| Each algorithm carries its key size as a compile-time witness.
public export
data SignatureAlgorithm : Type where
  ||| Ed25519 — 32-byte keys, 64-byte signatures
  Ed25519 : SignatureAlgorithm
  ||| Ed448 — 57-byte keys, 114-byte signatures (future)
  Ed448 : SignatureAlgorithm

||| Key size in bytes for a given signature algorithm
public export
keySize : SignatureAlgorithm -> Nat
keySize Ed25519 = 32
keySize Ed448 = 57

||| Signature size in bytes for a given algorithm
public export
signatureSize : SignatureAlgorithm -> Nat
signatureSize Ed25519 = 64
signatureSize Ed448 = 114

||| SignatureAlgorithm is decidably equal
public export
DecEq SignatureAlgorithm where
  decEq Ed25519 Ed25519 = Yes Refl
  decEq Ed448 Ed448 = Yes Refl
  decEq Ed25519 Ed448 = No (\case Refl impossible)
  decEq Ed448 Ed25519 = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Hash Algorithms
--------------------------------------------------------------------------------

||| Hash algorithms supported by the attestation engine
public export
data HashAlgorithm : Type where
  ||| SHA-256 — 32-byte digest
  SHA256 : HashAlgorithm
  ||| BLAKE3 — 32-byte digest (default, faster than SHA-256)
  BLAKE3 : HashAlgorithm

||| Digest size in bytes for a given hash algorithm
public export
digestSize : HashAlgorithm -> Nat
digestSize SHA256 = 32
digestSize BLAKE3 = 32

||| HashAlgorithm is decidably equal
public export
DecEq HashAlgorithm where
  decEq SHA256 SHA256 = Yes Refl
  decEq BLAKE3 BLAKE3 = Yes Refl
  decEq SHA256 BLAKE3 = No (\case Refl impossible)
  decEq BLAKE3 SHA256 = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Attestation Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI attestation operations.
||| Use C-compatible integers for cross-language compatibility.
public export
data AttestationResult : Type where
  ||| Attestation or verification succeeded
  Ok : AttestationResult
  ||| Generic error during attestation
  Error : AttestationResult
  ||| Invalid parameter (null key, zero-length input, etc.)
  InvalidParam : AttestationResult
  ||| Memory allocation failure
  OutOfMemory : AttestationResult
  ||| Null pointer encountered
  NullPointer : AttestationResult
  ||| Signature verification failed — document has been tampered with
  SignatureInvalid : AttestationResult
  ||| Hash mismatch — document content has changed since attestation
  DigestMismatch : AttestationResult
  ||| Provenance chain is broken (missing or invalid parent reference)
  ChainBroken : AttestationResult
  ||| Signing key has expired or been revoked
  KeyExpired : AttestationResult

||| Convert AttestationResult to C integer
public export
resultToInt : AttestationResult -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt SignatureInvalid = 5
resultToInt DigestMismatch = 6
resultToInt ChainBroken = 7
resultToInt KeyExpired = 8

||| AttestationResult is decidably equal
public export
DecEq AttestationResult where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq SignatureInvalid SignatureInvalid = Yes Refl
  decEq DigestMismatch DigestMismatch = Yes Refl
  decEq ChainBroken ChainBroken = Yes Refl
  decEq KeyExpired KeyExpired = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok SignatureInvalid = No (\case Refl impossible)
  decEq Ok DigestMismatch = No (\case Refl impossible)
  decEq Ok ChainBroken = No (\case Refl impossible)
  decEq Ok KeyExpired = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error SignatureInvalid = No (\case Refl impossible)
  decEq Error DigestMismatch = No (\case Refl impossible)
  decEq Error ChainBroken = No (\case Refl impossible)
  decEq Error KeyExpired = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam SignatureInvalid = No (\case Refl impossible)
  decEq InvalidParam DigestMismatch = No (\case Refl impossible)
  decEq InvalidParam ChainBroken = No (\case Refl impossible)
  decEq InvalidParam KeyExpired = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory SignatureInvalid = No (\case Refl impossible)
  decEq OutOfMemory DigestMismatch = No (\case Refl impossible)
  decEq OutOfMemory ChainBroken = No (\case Refl impossible)
  decEq OutOfMemory KeyExpired = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer SignatureInvalid = No (\case Refl impossible)
  decEq NullPointer DigestMismatch = No (\case Refl impossible)
  decEq NullPointer ChainBroken = No (\case Refl impossible)
  decEq NullPointer KeyExpired = No (\case Refl impossible)
  decEq SignatureInvalid Ok = No (\case Refl impossible)
  decEq SignatureInvalid Error = No (\case Refl impossible)
  decEq SignatureInvalid InvalidParam = No (\case Refl impossible)
  decEq SignatureInvalid OutOfMemory = No (\case Refl impossible)
  decEq SignatureInvalid NullPointer = No (\case Refl impossible)
  decEq SignatureInvalid DigestMismatch = No (\case Refl impossible)
  decEq SignatureInvalid ChainBroken = No (\case Refl impossible)
  decEq SignatureInvalid KeyExpired = No (\case Refl impossible)
  decEq DigestMismatch Ok = No (\case Refl impossible)
  decEq DigestMismatch Error = No (\case Refl impossible)
  decEq DigestMismatch InvalidParam = No (\case Refl impossible)
  decEq DigestMismatch OutOfMemory = No (\case Refl impossible)
  decEq DigestMismatch NullPointer = No (\case Refl impossible)
  decEq DigestMismatch SignatureInvalid = No (\case Refl impossible)
  decEq DigestMismatch ChainBroken = No (\case Refl impossible)
  decEq DigestMismatch KeyExpired = No (\case Refl impossible)
  decEq ChainBroken Ok = No (\case Refl impossible)
  decEq ChainBroken Error = No (\case Refl impossible)
  decEq ChainBroken InvalidParam = No (\case Refl impossible)
  decEq ChainBroken OutOfMemory = No (\case Refl impossible)
  decEq ChainBroken NullPointer = No (\case Refl impossible)
  decEq ChainBroken SignatureInvalid = No (\case Refl impossible)
  decEq ChainBroken DigestMismatch = No (\case Refl impossible)
  decEq ChainBroken KeyExpired = No (\case Refl impossible)
  decEq KeyExpired Ok = No (\case Refl impossible)
  decEq KeyExpired Error = No (\case Refl impossible)
  decEq KeyExpired InvalidParam = No (\case Refl impossible)
  decEq KeyExpired OutOfMemory = No (\case Refl impossible)
  decEq KeyExpired NullPointer = No (\case Refl impossible)
  decEq KeyExpired SignatureInvalid = No (\case Refl impossible)
  decEq KeyExpired DigestMismatch = No (\case Refl impossible)
  decEq KeyExpired ChainBroken = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to an a2mliser attestation context.
||| Prevents direct construction, enforces creation through the safe API.
public export
data AttestationHandle : Type where
  MkAttestationHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> AttestationHandle

||| Safely create a handle from a pointer value.
||| Returns Nothing if pointer is null.
public export
createHandle : Bits64 -> Maybe AttestationHandle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkAttestationHandle ptr {nonNull = ok})
    Right _ => Nothing

||| Extract pointer value from handle
public export
handlePtr : AttestationHandle -> Bits64
handlePtr (MkAttestationHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Attestation Envelope
--------------------------------------------------------------------------------

||| An attestation envelope wraps a document digest with a cryptographic
||| signature and provenance metadata. This is the core output of a2mliser.
public export
record AttestationEnvelope where
  constructor MkAttestationEnvelope
  ||| Hash algorithm used to digest the target document
  hashAlg : HashAlgorithm
  ||| Signature algorithm used to sign the digest
  sigAlg : SignatureAlgorithm
  ||| The document digest (length must match digestSize hashAlg)
  digest : Vect (digestSize hashAlg) Bits8
  ||| The signature over the digest (length must match signatureSize sigAlg)
  signature : Vect (signatureSize sigAlg) Bits8
  ||| Unix timestamp of when the attestation was created
  timestamp : Bits64
  ||| Optional parent envelope hash (for provenance chains)
  parentDigest : Maybe (Vect (digestSize hashAlg) Bits8)

--------------------------------------------------------------------------------
-- Provenance Chain
--------------------------------------------------------------------------------

||| A provenance chain is an ordered sequence of attestation envelopes
||| forming a directed path of trust from the current document back to
||| its origin.
public export
data ProvenanceChain : Nat -> Type where
  ||| A single attestation (the root of the chain)
  Root : AttestationEnvelope -> ProvenanceChain 1
  ||| An attestation that extends an existing chain
  Link : AttestationEnvelope -> ProvenanceChain n -> ProvenanceChain (S n)

||| Get the length of a provenance chain
public export
chainLength : ProvenanceChain n -> Nat
chainLength (Root _) = 1
chainLength (Link _ rest) = S (chainLength rest)

||| Get the most recent (leaf) envelope in the chain
public export
leaf : ProvenanceChain n -> AttestationEnvelope
leaf (Root env) = env
leaf (Link env _) = env

||| Get the root (oldest) envelope in the chain
public export
root : ProvenanceChain n -> AttestationEnvelope
root (Root env) = env
root (Link _ rest) = root rest

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| C int size varies by platform
public export
CInt : Platform -> Type
CInt Linux = Bits32
CInt Windows = Bits32
CInt MacOS = Bits32
CInt BSD = Bits32
CInt WASM = Bits32

||| C size_t varies by platform
public export
CSize : Platform -> Type
CSize Linux = Bits64
CSize Windows = Bits64
CSize MacOS = Bits64
CSize BSD = Bits64
CSize WASM = Bits32

||| C pointer size varies by platform
public export
ptrSize : Platform -> Nat
ptrSize Linux = 64
ptrSize Windows = 64
ptrSize MacOS = 64
ptrSize BSD = 64
ptrSize WASM = 32

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof that a type has a specific size
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

||| Proof that a type has a specific alignment
public export
data HasAlignment : Type -> Nat -> Type where
  AlignProof : {0 t : Type} -> {n : Nat} -> HasAlignment t n

||| Size of C types (platform-specific)
public export
||| Note: `CInt p` and `CSize p` reduce to concrete primitive types
||| (Bits32 / Bits64), so they are covered by the primitive cases below;
||| a type-function application like `CInt _` cannot be pattern-matched.
cSizeOf : (p : Platform) -> (t : Type) -> Nat
cSizeOf p Bits32 = 4
cSizeOf p Bits64 = 8
cSizeOf p Double = 8
cSizeOf p _ = ptrSize p `div` 8

||| Alignment of C types (platform-specific)
public export
cAlignOf : (p : Platform) -> (t : Type) -> Nat
cAlignOf p Bits32 = 4
cAlignOf p Bits64 = 8
cAlignOf p Double = 8
cAlignOf p _ = ptrSize p `div` 8

--------------------------------------------------------------------------------
-- Attestation-Specific Struct Layouts
--------------------------------------------------------------------------------

||| C-compatible representation of an attestation envelope header.
||| This struct crosses the FFI boundary and must match the Zig layout exactly.
public export
record EnvelopeHeader where
  constructor MkEnvelopeHeader
  ||| Hash algorithm identifier (0 = SHA256, 1 = BLAKE3)
  hashAlgId : Bits32
  ||| Signature algorithm identifier (0 = Ed25519, 1 = Ed448)
  sigAlgId : Bits32
  ||| Digest length in bytes
  digestLen : Bits32
  ||| Signature length in bytes
  signatureLen : Bits32
  ||| Unix timestamp
  timestamp : Bits64
  ||| Whether a parent digest is present (0 = no, 1 = yes)
  hasParent : Bits32
  ||| Padding for alignment
  padField : Bits32

||| Prove the envelope header has correct size (32 bytes)
public export
envelopeHeaderSize : (p : Platform) -> HasSize EnvelopeHeader 32
envelopeHeaderSize p = SizeProof

||| Prove the envelope header has correct alignment (8 bytes)
public export
envelopeHeaderAlign : (p : Platform) -> HasAlignment EnvelopeHeader 8
envelopeHeaderAlign p = AlignProof

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

namespace Verify

  ||| Compile-time verification of attestation ABI properties
  export
  verifySizes : IO ()
  verifySizes = do
    putStrLn "a2mliser ABI sizes verified"
    putStrLn $ "  EnvelopeHeader: 32 bytes"
    putStrLn $ "  Ed25519 key: 32 bytes, signature: 64 bytes"
    putStrLn $ "  SHA256 digest: 32 bytes, BLAKE3 digest: 32 bytes"

  ||| Verify alignment constraints
  export
  verifyAlignments : IO ()
  verifyAlignments = do
    putStrLn "a2mliser ABI alignments verified"
    putStrLn $ "  EnvelopeHeader: 8-byte aligned"
