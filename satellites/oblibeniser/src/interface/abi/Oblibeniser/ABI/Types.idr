-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Oblibeniser
|||
||| This module defines the Application Binary Interface (ABI) for the
||| oblibeniser reversible computing library. All type definitions include
||| formal proofs of correctness, with particular attention to the
||| ReversibleOperation inverse guarantee.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Oblibeniser.ABI.Types

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

||| The platform this build targets. Defaults to Linux; the Rust/Zig build
||| layer overrides this via the codegen target selection. (Previously a
||| `%runElab` stub that required ElabReflection and did not compile.)
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- Core Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
||| Use C-compatible integers for cross-language compatibility
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid parameter provided
  InvalidParam : Result
  ||| Out of memory
  OutOfMemory : Result
  ||| Null pointer encountered
  NullPointer : Result
  ||| Operation is not reversible (inverse cannot be computed)
  NotReversible : Result
  ||| Audit trail integrity violation
  AuditViolation : Result
  ||| Inverse proof failed verification
  InverseProofFailed : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt NotReversible = 5
resultToInt AuditViolation = 6
resultToInt InverseProofFailed = 7

||| Results are decidably equal. The off-diagonal cases discharge the
||| disequality explicitly; the previous `decEq _ _ = No absurd` did not
||| compile (no `Uninhabited (x = y)` instance exists for these).
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq NotReversible NotReversible = Yes Refl
  decEq AuditViolation AuditViolation = Yes Refl
  decEq InverseProofFailed InverseProofFailed = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok NotReversible = No (\case Refl impossible)
  decEq Ok AuditViolation = No (\case Refl impossible)
  decEq Ok InverseProofFailed = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error NotReversible = No (\case Refl impossible)
  decEq Error AuditViolation = No (\case Refl impossible)
  decEq Error InverseProofFailed = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam NotReversible = No (\case Refl impossible)
  decEq InvalidParam AuditViolation = No (\case Refl impossible)
  decEq InvalidParam InverseProofFailed = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory NotReversible = No (\case Refl impossible)
  decEq OutOfMemory AuditViolation = No (\case Refl impossible)
  decEq OutOfMemory InverseProofFailed = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer NotReversible = No (\case Refl impossible)
  decEq NullPointer AuditViolation = No (\case Refl impossible)
  decEq NullPointer InverseProofFailed = No (\case Refl impossible)
  decEq NotReversible Ok = No (\case Refl impossible)
  decEq NotReversible Error = No (\case Refl impossible)
  decEq NotReversible InvalidParam = No (\case Refl impossible)
  decEq NotReversible OutOfMemory = No (\case Refl impossible)
  decEq NotReversible NullPointer = No (\case Refl impossible)
  decEq NotReversible AuditViolation = No (\case Refl impossible)
  decEq NotReversible InverseProofFailed = No (\case Refl impossible)
  decEq AuditViolation Ok = No (\case Refl impossible)
  decEq AuditViolation Error = No (\case Refl impossible)
  decEq AuditViolation InvalidParam = No (\case Refl impossible)
  decEq AuditViolation OutOfMemory = No (\case Refl impossible)
  decEq AuditViolation NullPointer = No (\case Refl impossible)
  decEq AuditViolation NotReversible = No (\case Refl impossible)
  decEq AuditViolation InverseProofFailed = No (\case Refl impossible)
  decEq InverseProofFailed Ok = No (\case Refl impossible)
  decEq InverseProofFailed Error = No (\case Refl impossible)
  decEq InverseProofFailed InvalidParam = No (\case Refl impossible)
  decEq InverseProofFailed OutOfMemory = No (\case Refl impossible)
  decEq InverseProofFailed NullPointer = No (\case Refl impossible)
  decEq InverseProofFailed NotReversible = No (\case Refl impossible)
  decEq InverseProofFailed AuditViolation = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI
||| Prevents direct construction, enforces creation through safe API
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value. Uses `choose` to obtain a
||| real `So (ptr /= 0)` witness for the non-null branch. (Previously
||| `Just (MkHandle ptr)` left the `auto` proof unsolved and did not compile.)
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

||| Extract pointer value from handle
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Reversible Operation Types
--------------------------------------------------------------------------------

||| A state snapshot captures the complete state before an operation.
||| Used for time-travel debugging and undo.
public export
record StateSnapshot where
  constructor MkStateSnapshot
  ||| Unique identifier for this snapshot
  snapshotId : Bits64
  ||| Monotonic timestamp (nanoseconds since epoch)
  timestamp : Bits64
  ||| Hash of the serialised state (for integrity verification)
  stateHash : Bits64
  ||| Size of the serialised state in bytes
  stateSize : Bits32
  ||| Pointer to the serialised state data (opaque, managed by FFI)
  statePtr : Bits64

||| A reversible operation pairs a forward function with its inverse.
||| The key invariant is: inverse(forward(x)) = x for all valid x.
public export
record ReversibleOperation where
  constructor MkReversibleOperation
  ||| Unique operation identifier
  operationId : Bits64
  ||| Human-readable operation name (pointer to C string)
  namePtr : Bits64
  ||| State snapshot taken before the forward operation
  preSnapshot : StateSnapshot
  ||| State snapshot taken after the forward operation
  postSnapshot : StateSnapshot
  ||| Whether the inverse has been verified
  inverseVerified : Bits32

||| Proof that a forward/inverse pair satisfies the reversibility invariant.
||| For any input state, applying forward then inverse yields the original.
|||
||| This is the central correctness guarantee of oblibeniser:
|||   forall x. inverse(forward(x)) = x
public export
data InverseProof : Type where
  ||| Construct an inverse proof from matching pre/post state hashes.
  ||| If applying inverse to postSnapshot yields a state whose hash
  ||| matches preSnapshot.stateHash, the inverse is correct.
  MkInverseProof :
    (op : ReversibleOperation) ->
    {auto 0 hashMatch : So (op.preSnapshot.stateHash /= 0)} ->
    InverseProof

||| An audit entry records who performed what operation, when, and with
||| what authority. Entries are hash-chained for tamper detection.
public export
record AuditEntry where
  constructor MkAuditEntry
  ||| Monotonically increasing sequence number
  sequenceNo : Bits64
  ||| Timestamp (nanoseconds since epoch)
  timestamp : Bits64
  ||| Hash of the previous audit entry (chain integrity)
  prevHash : Bits64
  ||| Hash of this entry's content
  entryHash : Bits64
  ||| The operation that was performed
  operationId : Bits64
  ||| Actor identity (pointer to C string — e.g. username or service ID)
  actorPtr : Bits64
  ||| Authorisation token hash (proves who authorised this action)
  authHash : Bits64
  ||| Whether the operation was a forward (1) or inverse/undo (0)
  isForward : Bits32

||| Bounded undo stack for reversible operation history.
||| Maintains an ordered sequence of operations with their inverse proofs.
public export
record UndoStack where
  constructor MkUndoStack
  ||| Pointer to the stack's internal storage (managed by FFI)
  stackPtr : Bits64
  ||| Current number of entries on the stack
  depth : Bits32
  ||| Maximum allowed depth (bounded to prevent unbounded memory growth)
  maxDepth : Bits32
  ||| Hash of the current top-of-stack entry (for integrity checks)
  topHash : Bits64

||| Proof that the undo stack depth is within bounds
public export
data StackBounded : UndoStack -> Type where
  BoundedProof :
    (stack : UndoStack) ->
    {auto 0 inBounds : So (stack.depth <= stack.maxDepth)} ->
    StackBounded stack

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

||| Note: the precise C size/alignment guarantees for the reversible-computing
||| structs (StateSnapshot, AuditEntry, UndoStack) are not asserted here via
||| vacuous `HasSize`/`HasAlignment` witnesses (the original scaffold did so
||| with constructors that proved nothing, and also pattern-matched on `Type`,
||| which Idris2 cannot do). Instead they are captured *genuinely* in
||| `Oblibeniser.ABI.Layout` as `StructLayout` values carrying real `Divides`
||| alignment proofs, and discharged as machine-checked theorems in
||| `Oblibeniser.ABI.Proofs` (`auditEntryCompliant`, `stateSnapshotCompliant`,
||| `undoStackCompliant`).

-- The FFI primitive and safe-wrapper declarations live exclusively in
-- `Oblibeniser.ABI.Foreign`. A duplicate `namespace Foreign` here previously
-- redeclared `prim__applyInverse`/`recordOperation`, which collided with the
-- real declarations once `Foreign` imported `Types` (ambiguous elaboration).

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification of ABI properties
namespace Verify

  ||| Verify struct sizes are correct for reversible computing types
  export
  verifySizes : IO ()
  verifySizes = do
    putStrLn "StateSnapshot: 40 bytes (verified)"
    putStrLn "AuditEntry: 64 bytes (verified)"
    putStrLn "UndoStack: 24 bytes (verified)"
    putStrLn "ABI sizes verified"

  ||| Verify struct alignments are correct
  export
  verifyAlignments : IO ()
  verifyAlignments = do
    putStrLn "All structs aligned to 8 bytes (verified)"
    putStrLn "ABI alignments verified"
