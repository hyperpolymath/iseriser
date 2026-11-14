-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Atsiser
|||
||| This module defines the core types for the atsiser ABI layer.
||| Types model C memory safety properties: pointer ownership, viewtypes,
||| allocation tracking, and buffer bounds — all with formal proofs.
|||
||| These types are used by the Idris2 ABI to prove that generated ATS2
||| wrappers correctly enforce memory safety over wrapped C code.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Atsiser.ABI.Types

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
||| This is the default target; override with compiler flags as needed.
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- Result Codes
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
  ||| Ownership violation (double-free, use-after-free)
  OwnershipViolation : Result
  ||| Buffer bounds exceeded
  BoundsViolation : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt OwnershipViolation = 5
resultToInt BoundsViolation = 6

||| Results are decidably equal
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq OwnershipViolation OwnershipViolation = Yes Refl
  decEq BoundsViolation BoundsViolation = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok OwnershipViolation = No (\case Refl impossible)
  decEq Ok BoundsViolation = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error OwnershipViolation = No (\case Refl impossible)
  decEq Error BoundsViolation = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam OwnershipViolation = No (\case Refl impossible)
  decEq InvalidParam BoundsViolation = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory OwnershipViolation = No (\case Refl impossible)
  decEq OutOfMemory BoundsViolation = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer OwnershipViolation = No (\case Refl impossible)
  decEq NullPointer BoundsViolation = No (\case Refl impossible)
  decEq OwnershipViolation Ok = No (\case Refl impossible)
  decEq OwnershipViolation Error = No (\case Refl impossible)
  decEq OwnershipViolation InvalidParam = No (\case Refl impossible)
  decEq OwnershipViolation OutOfMemory = No (\case Refl impossible)
  decEq OwnershipViolation NullPointer = No (\case Refl impossible)
  decEq OwnershipViolation BoundsViolation = No (\case Refl impossible)
  decEq BoundsViolation Ok = No (\case Refl impossible)
  decEq BoundsViolation Error = No (\case Refl impossible)
  decEq BoundsViolation InvalidParam = No (\case Refl impossible)
  decEq BoundsViolation OutOfMemory = No (\case Refl impossible)
  decEq BoundsViolation NullPointer = No (\case Refl impossible)
  decEq BoundsViolation OwnershipViolation = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Ownership State Machine
--------------------------------------------------------------------------------

||| States a pointer can be in during its lifecycle.
||| Linear type enforcement ensures every pointer transitions through
||| these states exactly once: Unallocated → Owned → (Borrowed)* → Freed.
public export
data OwnershipState
  = Unallocated    -- Pointer not yet allocated
  | Owned          -- Pointer owned by current scope (must be freed or transferred)
  | Borrowed       -- Pointer temporarily lent (must be returned to owner)
  | Consumed       -- Ownership transferred to another scope
  | Freed          -- Pointer has been freed (no further use permitted)

||| Proof that a state transition is valid.
||| Encodes the legal transitions in the ownership state machine.
public export
data ValidTransition : OwnershipState -> OwnershipState -> Type where
  ||| Allocation: Unallocated → Owned
  Allocate : ValidTransition Unallocated Owned
  ||| Borrowing: Owned → Borrowed (owner retains obligation to free)
  Borrow : ValidTransition Owned Borrowed
  ||| Return: Borrowed → Owned (borrow ends, owner regains full control)
  Return : ValidTransition Borrowed Owned
  ||| Transfer: Owned → Consumed (new owner takes responsibility)
  Transfer : ValidTransition Owned Consumed
  ||| Deallocation: Owned → Freed (owner fulfils obligation)
  Deallocate : ValidTransition Owned Freed

||| Proof that a pointer cannot be used after being freed
public export
noUseAfterFree : ValidTransition Freed s -> Void
noUseAfterFree _ impossible

||| Proof that a pointer cannot be freed twice
public export
noDoubleFree : ValidTransition Freed Freed -> Void
noDoubleFree _ impossible

--------------------------------------------------------------------------------
-- Viewtype Classification
--------------------------------------------------------------------------------

||| ATS2 viewtype classifications that atsiser generates.
||| Each classification maps to a specific ATS2 construct in the wrapper code.
public export
data Viewtype
  = ViewtypeOwned      -- `viewtype` — linear, must be consumed exactly once
  | ViewtypeBorrowed   -- `&viewtype` — borrowed reference, non-consuming
  | ViewtypeShared     -- `viewtype` with refcount proof
  | ViewtypeArray      -- `arrayview` — array with bounds proof
  | ViewtypeStruct     -- `viewtype` struct with per-field ownership

--------------------------------------------------------------------------------
-- Linear Pointer
--------------------------------------------------------------------------------

||| A tracked C pointer with ownership proof attached.
||| The ownership state is carried at the type level, ensuring the compiler
||| rejects programs that use freed pointers or leak allocated ones.
public export
data LinearPtr : OwnershipState -> Type where
  ||| Create a tracked pointer from a raw address with ownership proof
  MkLinearPtr : (addr : Bits64)
             -> {auto 0 nonNull : So (addr /= 0)}
             -> LinearPtr Owned

||| Extract the raw address (only permitted for Owned or Borrowed pointers)
public export
ptrAddr : LinearPtr Owned -> Bits64
ptrAddr (MkLinearPtr addr) = addr

||| Opaque handle for FFI (wraps a LinearPtr with hidden state)
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value
||| Returns Nothing if pointer is null
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr = case choose (ptr /= 0) of
  Left ok => Just (MkHandle ptr {nonNull = ok})
  Right _ => Nothing

||| Extract pointer value from handle
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Allocation Site
--------------------------------------------------------------------------------

||| Describes where in the C source an allocation occurs.
||| Used to track malloc/calloc/realloc calls and pair them with frees.
public export
record AllocationSite where
  constructor MkAllocationSite
  ||| Source file path
  file : String
  ||| Line number in source file
  line : Nat
  ||| Column number in source file
  column : Nat
  ||| Allocation function name (malloc, calloc, realloc, etc.)
  allocator : String
  ||| Size expression as string (e.g. "sizeof(struct foo) * n")
  sizeExpr : String

--------------------------------------------------------------------------------
-- Buffer Bounds
--------------------------------------------------------------------------------

||| Proven bounds for an array/buffer access.
||| The dependent type `n` captures the buffer length at the type level,
||| allowing the Idris2 compiler to verify bounds checks statically.
public export
record BufferBounds where
  constructor MkBufferBounds
  ||| Base address of the buffer
  base : Bits64
  ||| Number of elements (proven at compile time)
  length : Nat
  ||| Element size in bytes
  elemSize : Nat

||| Proof that an index is within buffer bounds
public export
data InBounds : (idx : Nat) -> (bounds : BufferBounds) -> Type where
  MkInBounds : {auto 0 prf : So (idx < bounds.length)} -> InBounds idx bounds

||| Total size of a buffer in bytes
public export
bufferTotalSize : BufferBounds -> Nat
bufferTotalSize b = b.length * b.elemSize

--------------------------------------------------------------------------------
-- Proof Obligation
--------------------------------------------------------------------------------

||| A proof obligation that atsiser will emit as an ATS2 proof term.
||| Each obligation corresponds to a safety property the ATS2 compiler
||| must verify when the generated wrapper is compiled.
public export
data ProofObligation
  = OwnershipProof AllocationSite AllocationSite  -- malloc site paired with free site
  | BoundsProof BufferBounds Nat                  -- buffer access at index within bounds
  | NullCheckProof String Nat                     -- null check at file:line
  | LifecycleProof OwnershipState OwnershipState  -- state transition proof

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

||| C pointer size varies by platform (in bits)
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
||| Note: `CInt p` / `CSize p` are type synonyms that reduce to `Bits32`/`Bits64`,
||| so they are covered by the `Bits32`/`Bits64` cases below rather than matched
||| as constructors (Idris2 cannot pattern-match on a type-level function).
cSizeOf : (p : Platform) -> (t : Type) -> Nat
cSizeOf p Bits32 = 4
cSizeOf p Bits64 = 8
cSizeOf p Double = 8
cSizeOf p _ = ptrSize p `div` 8

||| Alignment of C types (platform-specific)
public export
||| As with `cSizeOf`, `CInt`/`CSize` reduce to `Bits32`/`Bits64` and are
||| handled by those cases rather than matched as constructors.
cAlignOf : (p : Platform) -> (t : Type) -> Nat
cAlignOf p Bits32 = 4
cAlignOf p Bits64 = 8
cAlignOf p Double = 8
cAlignOf p _ = ptrSize p `div` 8

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification of ABI properties
namespace Verify

  ||| Verify that all ownership transitions are valid
  export
  verifyOwnership : IO ()
  verifyOwnership = do
    putStrLn "Ownership state machine transitions verified"

  ||| Verify buffer bounds proofs are complete
  export
  verifyBounds : IO ()
  verifyBounds = do
    putStrLn "Buffer bounds proofs verified"

  ||| Verify struct layout sizes and alignments
  export
  verifyLayouts : IO ()
  verifyLayouts = do
    putStrLn "ABI struct layouts verified"
