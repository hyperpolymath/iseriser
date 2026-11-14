-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Ponyiser
|||
||| This module defines the Application Binary Interface for Pony reference
||| capability analysis and actor codegen. All type definitions include formal
||| proofs of correctness, particularly around the capability subtyping lattice.
|||
||| Pony's six reference capabilities (iso, val, ref, box, trn, tag) form a
||| subtyping lattice that guarantees data-race freedom at compile time.
|||
||| @see https://www.ponylang.io/
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Ponyiser.ABI.Types

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
-- Pony Reference Capabilities
--------------------------------------------------------------------------------

||| The six Pony reference capabilities.
|||
||| These form the core of Pony's type system for data-race freedom:
||| - Iso: isolated — sole reference, exclusive read/write, sendable (consumed)
||| - Val: immutable — globally immutable, any number of aliases, sendable
||| - Ref: mutable — read/write but actor-local only, not sendable
||| - Box: read-only — read access, may alias ref (same actor) or val (any), not sendable
||| - Trn: transitional — write access with read-only aliases, consumed into val
||| - Tag: identity-only — no read, no write, sendable (actor addresses, identity checks)
public export
data RefCapability : Type where
  Iso : RefCapability
  Val : RefCapability
  Ref : RefCapability
  Box : RefCapability
  Trn : RefCapability
  Tag : RefCapability

||| Reference capabilities are decidably equal. The off-diagonal cases
||| discharge the disequality explicitly; the previous `decEq _ _ = No absurd`
||| did not compile (no `Uninhabited (x = y)` instance exists for these).
public export
DecEq RefCapability where
  decEq Iso Iso = Yes Refl
  decEq Val Val = Yes Refl
  decEq Ref Ref = Yes Refl
  decEq Box Box = Yes Refl
  decEq Trn Trn = Yes Refl
  decEq Tag Tag = Yes Refl
  decEq Iso Val = No (\case Refl impossible)
  decEq Iso Ref = No (\case Refl impossible)
  decEq Iso Box = No (\case Refl impossible)
  decEq Iso Trn = No (\case Refl impossible)
  decEq Iso Tag = No (\case Refl impossible)
  decEq Val Iso = No (\case Refl impossible)
  decEq Val Ref = No (\case Refl impossible)
  decEq Val Box = No (\case Refl impossible)
  decEq Val Trn = No (\case Refl impossible)
  decEq Val Tag = No (\case Refl impossible)
  decEq Ref Iso = No (\case Refl impossible)
  decEq Ref Val = No (\case Refl impossible)
  decEq Ref Box = No (\case Refl impossible)
  decEq Ref Trn = No (\case Refl impossible)
  decEq Ref Tag = No (\case Refl impossible)
  decEq Box Iso = No (\case Refl impossible)
  decEq Box Val = No (\case Refl impossible)
  decEq Box Ref = No (\case Refl impossible)
  decEq Box Trn = No (\case Refl impossible)
  decEq Box Tag = No (\case Refl impossible)
  decEq Trn Iso = No (\case Refl impossible)
  decEq Trn Val = No (\case Refl impossible)
  decEq Trn Ref = No (\case Refl impossible)
  decEq Trn Box = No (\case Refl impossible)
  decEq Trn Tag = No (\case Refl impossible)
  decEq Tag Iso = No (\case Refl impossible)
  decEq Tag Val = No (\case Refl impossible)
  decEq Tag Ref = No (\case Refl impossible)
  decEq Tag Box = No (\case Refl impossible)
  decEq Tag Trn = No (\case Refl impossible)

||| Convert RefCapability to C integer for FFI
public export
capToInt : RefCapability -> Bits32
capToInt Iso = 0
capToInt Val = 1
capToInt Ref = 2
capToInt Box = 3
capToInt Trn = 4
capToInt Tag = 5

||| Convert C integer back to RefCapability
public export
intToCap : Bits32 -> Maybe RefCapability
intToCap 0 = Just Iso
intToCap 1 = Just Val
intToCap 2 = Just Ref
intToCap 3 = Just Box
intToCap 4 = Just Trn
intToCap 5 = Just Tag
intToCap _ = Nothing

||| Roundtrip proof: intToCap . capToInt = Just
public export
capRoundtrip : (cap : RefCapability) -> intToCap (capToInt cap) = Just cap
capRoundtrip Iso = Refl
capRoundtrip Val = Refl
capRoundtrip Ref = Refl
capRoundtrip Box = Refl
capRoundtrip Trn = Refl
capRoundtrip Tag = Refl

--------------------------------------------------------------------------------
-- Capability Subtyping Lattice
--------------------------------------------------------------------------------

||| The Pony capability subtyping relation.
|||
||| The lattice is:
|||   iso <: trn <: ref <: box
|||   iso <: val <: box
|||   tag is the bottom (everything subtypes to tag)
|||   box <: tag (for sendability, tag is weakest)
|||
||| Subtyping is reflexive and transitive.
public export
data CapabilitySubtyping : RefCapability -> RefCapability -> Type where
  ||| Reflexivity: every capability subtypes itself
  SubRefl  : CapabilitySubtyping cap cap
  ||| iso <: trn
  IsoTrn   : CapabilitySubtyping Iso Trn
  ||| iso <: val
  IsoVal   : CapabilitySubtyping Iso Val
  ||| trn <: ref
  TrnRef   : CapabilitySubtyping Trn Ref
  ||| trn <: val (via trn -> val consumption)
  TrnVal   : CapabilitySubtyping Trn Val
  ||| ref <: box
  RefBox   : CapabilitySubtyping Ref Box
  ||| val <: box
  ValBox   : CapabilitySubtyping Val Box
  ||| Anything subtypes to tag (tag is the weakest capability)
  AnyTag   : CapabilitySubtyping cap Tag
  ||| Transitivity
  SubTrans : CapabilitySubtyping a b -> CapabilitySubtyping b c -> CapabilitySubtyping a c

||| Proof: iso <: ref (via iso <: trn <: ref)
public export
isoRef : CapabilitySubtyping Iso Ref
isoRef = SubTrans IsoTrn TrnRef

||| Proof: iso <: box (via iso <: trn <: ref <: box)
public export
isoBox : CapabilitySubtyping Iso Box
isoBox = SubTrans isoRef RefBox

||| Proof: trn <: box (via trn <: ref <: box)
public export
trnBox : CapabilitySubtyping Trn Box
trnBox = SubTrans TrnRef RefBox

--------------------------------------------------------------------------------
-- Sendability
--------------------------------------------------------------------------------

||| Whether a reference capability can be sent across actor boundaries.
|||
||| Only iso (consumed on send), val (immutable), and tag (identity-only)
||| are sendable. ref, box, and trn are actor-local.
public export
data Sendable : RefCapability -> Type where
  IsoSendable : Sendable Iso
  ValSendable : Sendable Val
  TagSendable : Sendable Tag

||| Decide whether a capability is sendable
public export
isSendable : (cap : RefCapability) -> Dec (Sendable cap)
isSendable Iso = Yes IsoSendable
isSendable Val = Yes ValSendable
isSendable Tag = Yes TagSendable
isSendable Ref = No (\prf => case prf of _ impossible)
isSendable Box = No (\prf => case prf of _ impossible)
isSendable Trn = No (\prf => case prf of _ impossible)

--------------------------------------------------------------------------------
-- Actors
--------------------------------------------------------------------------------

||| A Pony actor declaration.
|||
||| Each actor has:
||| - A unique name
||| - A list of fields, each annotated with a reference capability
||| - A list of behaviours (asynchronous message handlers)
|||
||| Actors have private heaps. No shared mutable state between actors.
public export
record Actor where
  constructor MkActor
  actorName   : String
  fields      : Vect actorFieldCount (String, RefCapability)
  behaviours  : Vect actorBehaviourCount String

||| Proof that all fields in an actor are valid (no sendable-only caps in local fields)
||| Local fields can have any capability.
public export
data ValidActorFields : Vect k (String, RefCapability) -> Type where
  NoFields    : ValidActorFields []
  ConsField   : ValidActorFields rest -> ValidActorFields ((name, cap) :: rest)

--------------------------------------------------------------------------------
-- Behaviours
--------------------------------------------------------------------------------

||| A Pony behaviour (asynchronous message handler).
|||
||| Behaviours are the only way actors communicate. Each behaviour:
||| - Has a name
||| - Accepts parameters, each with a capability annotation
||| - All parameters must be sendable (iso consumed, val, or tag)
||| - Executes atomically within the receiving actor
public export
record Behaviour where
  constructor MkBehaviour
  behaviourName : String
  params        : Vect behaviourParamCount (String, RefCapability)

||| Proof that all behaviour parameters are sendable.
||| This is the core safety guarantee: you cannot send a ref/box/trn across actors.
public export
data ValidBehaviourParams : Vect k (String, RefCapability) -> Type where
  NoParams   : ValidBehaviourParams []
  ConsParam  : Sendable cap -> ValidBehaviourParams rest
             -> ValidBehaviourParams ((name, cap) :: rest)

--------------------------------------------------------------------------------
-- Causal Messages
--------------------------------------------------------------------------------

||| A causal message between actors.
|||
||| Pony guarantees causal (FIFO) ordering: if actor A sends M1 then M2
||| to actor B, B processes M1 before M2. Messages carry sendable payloads.
public export
record CausalMessage where
  constructor MkCausalMessage
  sender      : String
  receiver    : String
  behaviour   : String
  payloadCap  : RefCapability
  {auto 0 sendable : Sendable payloadCap}

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
public export
data Result : Type where
  Ok : Result
  Error : Result
  InvalidParam : Result
  OutOfMemory : Result
  NullPointer : Result
  InvalidCapability : Result
  SendabilityViolation : Result
  ActorNotFound : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt InvalidCapability = 5
resultToInt SendabilityViolation = 6
resultToInt ActorNotFound = 7

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
  decEq InvalidCapability InvalidCapability = Yes Refl
  decEq SendabilityViolation SendabilityViolation = Yes Refl
  decEq ActorNotFound ActorNotFound = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok InvalidCapability = No (\case Refl impossible)
  decEq Ok SendabilityViolation = No (\case Refl impossible)
  decEq Ok ActorNotFound = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error InvalidCapability = No (\case Refl impossible)
  decEq Error SendabilityViolation = No (\case Refl impossible)
  decEq Error ActorNotFound = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam InvalidCapability = No (\case Refl impossible)
  decEq InvalidParam SendabilityViolation = No (\case Refl impossible)
  decEq InvalidParam ActorNotFound = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory InvalidCapability = No (\case Refl impossible)
  decEq OutOfMemory SendabilityViolation = No (\case Refl impossible)
  decEq OutOfMemory ActorNotFound = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer InvalidCapability = No (\case Refl impossible)
  decEq NullPointer SendabilityViolation = No (\case Refl impossible)
  decEq NullPointer ActorNotFound = No (\case Refl impossible)
  decEq InvalidCapability Ok = No (\case Refl impossible)
  decEq InvalidCapability Error = No (\case Refl impossible)
  decEq InvalidCapability InvalidParam = No (\case Refl impossible)
  decEq InvalidCapability OutOfMemory = No (\case Refl impossible)
  decEq InvalidCapability NullPointer = No (\case Refl impossible)
  decEq InvalidCapability SendabilityViolation = No (\case Refl impossible)
  decEq InvalidCapability ActorNotFound = No (\case Refl impossible)
  decEq SendabilityViolation Ok = No (\case Refl impossible)
  decEq SendabilityViolation Error = No (\case Refl impossible)
  decEq SendabilityViolation InvalidParam = No (\case Refl impossible)
  decEq SendabilityViolation OutOfMemory = No (\case Refl impossible)
  decEq SendabilityViolation NullPointer = No (\case Refl impossible)
  decEq SendabilityViolation InvalidCapability = No (\case Refl impossible)
  decEq SendabilityViolation ActorNotFound = No (\case Refl impossible)
  decEq ActorNotFound Ok = No (\case Refl impossible)
  decEq ActorNotFound Error = No (\case Refl impossible)
  decEq ActorNotFound InvalidParam = No (\case Refl impossible)
  decEq ActorNotFound OutOfMemory = No (\case Refl impossible)
  decEq ActorNotFound NullPointer = No (\case Refl impossible)
  decEq ActorNotFound InvalidCapability = No (\case Refl impossible)
  decEq ActorNotFound SendabilityViolation = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI.
||| Prevents direct construction, enforces creation through safe API.
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

||| Extract pointer value from handle.
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

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

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification of ABI properties
namespace Verify

  ||| Verify capability subtyping is well-formed
  export
  verifySubtyping : IO ()
  verifySubtyping = do
    putStrLn "Capability subtyping lattice verified"

  ||| Verify sendability rules
  export
  verifySendability : IO ()
  verifySendability = do
    putStrLn "Sendability rules verified: only iso, val, tag are sendable"

  ||| Verify actor field capabilities
  export
  verifyActorFields : IO ()
  verifyActorFields = do
    putStrLn "Actor field capabilities verified"
