-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the oblibeniser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI struct
||| layout were misaligned, the result-code encoding wrong, or a decision
||| procedure mis-defined, this module would fail to typecheck and the proof
||| build would go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Oblibeniser.ABI.Proofs

import Oblibeniser.ABI.Types
import Oblibeniser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete reversible-computing FFI struct layouts are C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the AuditEntry layout divides its alignment:
||| 0|8, 8|8, 16|8, 24|8, 32|8, 40|8, 48|8, 56|4.
export
auditEntryCompliant : CABICompliant Layout.auditEntryLayout
auditEntryCompliant =
  CABIOk auditEntryLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 14 Refl)
     NoFields))))))))

||| Every field offset in the StateSnapshot layout divides its alignment:
||| 0|8, 8|8, 16|8, 24|4, 32|8.
export
stateSnapshotCompliant : CABICompliant Layout.stateSnapshotLayout
stateSnapshotCompliant =
  CABIOk stateSnapshotLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
     NoFields)))))

||| Every field offset in the UndoStack layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|8.
export
undoStackCompliant : CABICompliant Layout.undoStackLayout
undoStackCompliant =
  CABIOk undoStackLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields))))

--------------------------------------------------------------------------------
-- Result-code encoding: the integer contract the Zig FFI depends on.
--------------------------------------------------------------------------------

||| Success is encoded as 0, matching the C convention.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| NotReversible is encoded as 5 — the inverse-computation FFI returns this
||| code and the safe wrappers decode it back to `NotReversible`.
export
notReversibleIsFive : resultToInt NotReversible = 5
notReversibleIsFive = Refl

||| InverseProofFailed is encoded as 7 — the central correctness failure code
||| for oblibeniser's reversibility guarantee.
export
inverseProofFailedIsSeven : resultToInt InverseProofFailed = 7
inverseProofFailedIsSeven = Refl
