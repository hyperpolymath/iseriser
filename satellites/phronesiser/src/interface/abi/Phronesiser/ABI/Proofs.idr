-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the phronesiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, a result/modality/severity encoding wrong, or a decision
||| procedure mis-defined, this module would fail to typecheck and the proof
||| build would go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we never route them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Phronesiser.ABI.Proofs

import Phronesiser.ABI.Types
import Phronesiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| ConstraintStruct layout: offsets 0,4,8,12 each 4-byte aligned, so
||| 0 = 0*4, 4 = 1*4, 8 = 2*4, 12 = 3*4.
export
constraintLayoutCompliant : CABICompliant Layout.constraintLayout
constraintLayoutCompliant =
  CABIOk constraintLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields))))

||| AuditResultStruct layout: offsets 0,4,8,12 each 4-byte aligned.
export
auditResultLayoutCompliant : CABICompliant Layout.auditResultLayout
auditResultLayoutCompliant =
  CABIOk auditResultLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields))))

||| ConstraintSetHeader layout: offsets 0,4 each 4-byte aligned, so
||| 0 = 0*4, 4 = 1*4.
export
constraintSetHeaderLayoutCompliant : CABICompliant Layout.constraintSetHeaderLayout
constraintSetHeaderLayoutCompliant =
  CABIOk constraintSetHeaderLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
     NoFields))

--------------------------------------------------------------------------------
-- Result-code encoding: the integers the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
constraintConflictIsSix : resultToInt ConstraintConflict = 6
constraintConflictIsSix = Refl

--------------------------------------------------------------------------------
-- Deontic / severity encodings used across the FFI boundary.
--------------------------------------------------------------------------------

||| The three deontic modalities encode to 0, 1, 2 — pinned for the Zig side.
export
prohibitionIsTwo : modalityToInt Prohibition = 2
prohibitionIsTwo = Refl

||| Obligation and prohibition are genuinely distinct propositions: an action
||| cannot be both obligatory and prohibited. (Re-exported as a Proofs-level
||| theorem so the proof build pins the deontic contradiction directly.)
export
obligationNotProhibition : Obligation = Prohibition -> Void
obligationNotProhibition Refl impossible

||| Severity encodes Critical as the maximum code 4.
export
criticalIsFour : severityToInt Critical = 4
criticalIsFour = Refl

--------------------------------------------------------------------------------
-- Constraint-array sizing is strictly determined and grows with count.
--------------------------------------------------------------------------------

||| An empty constraint array is exactly the 8-byte header.
export
emptyArrayIsHeader : constraintArraySize 0 = 8
emptyArrayIsHeader = Refl

||| One constraint occupies header (8) + one 16-byte struct = 24 bytes.
export
oneConstraintArraySize : constraintArraySize 1 = 24
oneConstraintArraySize = Refl

||| Monotonicity instantiated: a 2-element set is no larger than a 5-element
||| set. Exercises `constraintArrayMonotonic` with a concrete `LTE` witness.
export
arrayGrows : LTE (constraintArraySize 2) (constraintArraySize 5)
arrayGrows = constraintArrayMonotonic 2 5 (LTESucc (LTESucc LTEZero))
