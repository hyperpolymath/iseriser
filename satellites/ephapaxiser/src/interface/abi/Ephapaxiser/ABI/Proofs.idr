-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the ephapaxiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, the result-code encoding wrong, or a lifecycle transition
||| mis-stated, this module would fail to typecheck and the proof build would
||| go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Ephapaxiser.ABI.Proofs

import Ephapaxiser.ABI.Types
import Ephapaxiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the ResourceTracker layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|4, 20|4.
export
resourceTrackerCompliant : CABICompliant Layout.resourceTrackerLayout
resourceTrackerCompliant =
  CABIOk resourceTrackerLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
     NoFields)))))

||| Every field offset in the ConsumeProof layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|4, 20|4.
export
consumeProofCompliant : CABICompliant Layout.consumeProofLayout
consumeProofCompliant =
  CABIOk consumeProofLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
     NoFields)))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The double-free error code is pinned to 7, as the Zig FFI bridge expects.
export
doubleFreeIsSeven : resultToInt DoubleFree = 7
doubleFreeIsSeven = Refl

--------------------------------------------------------------------------------
-- Linearity state machine: only the two legal transitions exist.
--------------------------------------------------------------------------------

||| Once a resource is consumed, no further transition out of it is valid —
||| this is the formal use-after-free guard. `consumedIsFinal` discharges the
||| absurd case for any successor state, so the proof is genuine (the type
||| `ValidTransition Consumed next` is uninhabited).
export
consumedHasNoSuccessor : (next : ResourceLifecycle) ->
                         ValidTransition Consumed next -> Void
consumedHasNoSuccessor next = consumedIsFinal

||| Using a freshly-acquired resource records exactly-once usage: the usage
||| index of the returned resource is `UsedOnce`, witnessed structurally by
||| the lifecycle transition `Acquired -> InUse`.
export
useProducesAcquiredToInUse :
  (r : LinearResource Acquired Unused) ->
  snd (useResource r) = AcquiredToInUse
useProducesAcquiredToInUse (MkLinearResource _) = Refl
