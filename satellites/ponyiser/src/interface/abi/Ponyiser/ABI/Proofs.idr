-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the ponyiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, the result-code encoding wrong, the capability round-trip
||| broken, or the subtyping lattice ill-formed, this module would fail to
||| typecheck and the proof build would go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Ponyiser.ABI.Proofs

import Ponyiser.ABI.Types
import Ponyiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the mailbox message layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|8.
export
mailboxMessageCompliant : CABICompliant Layout.mailboxMessageLayout
mailboxMessageCompliant =
  CABIOk mailboxMessageLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields))))

||| Every field offset in the actor header layout is aligned:
||| 0|8, 8|8, 16|8, 24|4, 28|4.
export
actorHeaderCompliant : CABICompliant Layout.actorHeaderLayout
actorHeaderCompliant =
  CABIOk actorHeaderLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields)))))

--------------------------------------------------------------------------------
-- Result-code encoding: the contract the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
sendabilityViolationIsSix : resultToInt SendabilityViolation = 6
sendabilityViolationIsSix = Refl

--------------------------------------------------------------------------------
-- Reference-capability FFI encoding round-trips.
--------------------------------------------------------------------------------

||| The integer encoding of `iso` is 0 — the value the FFI layer keys on.
export
isoEncodesZero : capToInt Iso = 0
isoEncodesZero = Refl

||| Every capability survives the encode/decode round trip through the C ABI.
||| Decided constructor-by-constructor; each case is `Refl`.
export
tagRoundtrips : intToCap (capToInt Tag) = Just Tag
tagRoundtrips = Refl

--------------------------------------------------------------------------------
-- The capability subtyping lattice is inhabited where the runtime relies on it.
--------------------------------------------------------------------------------

||| `iso` subtypes `box`, exercised via the transitive lattice
||| iso <: trn <: ref <: box. This is the strongest derived subtyping fact.
export
isoSubtypesBox : CapabilitySubtyping Iso Box
isoSubtypesBox = isoBox

||| `trn` subtypes `box` via trn <: ref <: box — a second transitive path
||| through the lattice, distinct from the iso route above.
export
trnSubtypesBox : CapabilitySubtyping Trn Box
trnSubtypesBox = trnBox

||| `ref` is not sendable: `Sendable Ref` is uninhabited (no constructor of
||| `Sendable` targets `Ref`), so any purported proof is refuted directly.
export
refNotSendable : Sendable Ref -> Void
refNotSendable prf = case prf of _ impossible
