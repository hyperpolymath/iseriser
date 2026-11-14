-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-Checked ABI Theorems for Betlangiser
|||
||| This module collects genuine, machine-checked theorems about the
||| betlangiser ABI: that each concrete C-struct layout is C-ABI compliant
||| (every field offset is a multiple of its alignment), and that the
||| result-code encoding pins the success code to zero.
|||
||| Every proof below reduces by computation alone — no holes, no postulates,
||| no `believe_me`. The divisibility witnesses are built DIRECTLY (each field
||| offset is a literal `k * alignment`, and multiplication reduces during
||| typechecking) rather than via the runtime decision procedure.

module Betlangiser.ABI.Proofs

import Betlangiser.ABI.Types
import Betlangiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Layout Compliance Theorems
--------------------------------------------------------------------------------

||| The Distribution C-struct layout is C-ABI compliant: every field offset
||| is an exact multiple of that field's alignment.
||| Offsets/alignments: tag 0/4, _pad0 4/4, param1 8/8, param2 16/8,
|||   custom_ptr 24/8, custom_len 32/4, _pad1 36/4.
export
distributionCompliant : CABICompliant Layout.distributionLayout
distributionCompliant =
  CABIOk Layout.distributionLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 1 Refl)
          (ConsField _ _ (DivideBy 2 Refl)
            (ConsField _ _ (DivideBy 3 Refl)
              (ConsField _ _ (DivideBy 8 Refl)
                (ConsField _ _ (DivideBy 9 Refl) NoFields)))))))

||| The sample-buffer C-struct layout is C-ABI compliant.
||| All seven fields are 8 bytes at offsets 0,8,16,24,32,40,48 with align 8.
export
sampleBufferCompliant : CABICompliant Layout.sampleBufferLayout
sampleBufferCompliant =
  CABIOk Layout.sampleBufferLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 2 Refl)
          (ConsField _ _ (DivideBy 3 Refl)
            (ConsField _ _ (DivideBy 4 Refl)
              (ConsField _ _ (DivideBy 5 Refl)
                (ConsField _ _ (DivideBy 6 Refl) NoFields)))))))

||| The confidence-interval C-struct layout is C-ABI compliant.
||| Three 8-byte doubles at offsets 0,8,16 with align 8.
export
confidenceIntervalCompliant : CABICompliant Layout.confidenceIntervalLayout
confidenceIntervalCompliant =
  CABIOk Layout.confidenceIntervalLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 2 Refl) NoFields)))

||| The ternary-array C-struct layout is C-ABI compliant.
||| Two 8-byte fields at offsets 0,8 with align 8.
export
ternaryArrayCompliant : CABICompliant Layout.ternaryArrayLayout
ternaryArrayCompliant =
  CABIOk Layout.ternaryArrayLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl) NoFields))

--------------------------------------------------------------------------------
-- Result-Code Encoding Theorems
--------------------------------------------------------------------------------

||| The success result code encodes to the integer 0, as required by the
||| C-ABI convention (zero means success).
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The result-code encoding is injective on the two codes that matter most
||| at the boundary: success (0) is distinct from the generic error (1).
||| Pinned here so a future re-ordering of the `Result` enum cannot silently
||| collide success with an error.
export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

--------------------------------------------------------------------------------
-- Ternary Logic Theorems
--------------------------------------------------------------------------------

||| Kleene NOT is self-inverse on the indeterminate value: re-exported as a
||| concrete, fully-applied theorem (no universally-quantified variable) so it
||| witnesses a closed fact about the ABI's Unknown encoding.
export
notUnknownIsUnknown : ternaryNot TUnknown = TUnknown
notUnknownIsUnknown = Refl

||| Kleene AND is annihilated by False regardless of the other operand being
||| the indeterminate value — the strong-falsity law at the ABI boundary.
export
falseAndUnknownIsFalse : ternaryAnd TFalse TUnknown = TFalse
falseAndUnknownIsFalse = Refl
