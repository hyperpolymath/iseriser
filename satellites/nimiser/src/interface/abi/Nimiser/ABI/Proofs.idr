-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked theorems for the Nimiser ABI.
|||
||| Each concrete `StructLayout` value is proven `CABICompliant` by building
||| the `FieldsAligned` witness directly (one `DivideBy` per field, where the
||| field offset equals `k * alignment`). Multiplication reduces during
||| typechecking; division does not — so these witnesses are built by hand
||| rather than via `decFieldsAligned`.

module Nimiser.ABI.Proofs

import Nimiser.ABI.Types
import Nimiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI compliance of the concrete struct layouts
--------------------------------------------------------------------------------

||| The `nimiser_buffer` layout is C-ABI compliant.
||| Fields: data @0 align 8 (0 = 0*8), len @8 align 4 (8 = 2*4),
||| cap @12 align 4 (12 = 3*4).
export
nimBufferCompliant : CABICompliant Layout.nimBufferLayout
nimBufferCompliant =
  CABIOk nimBufferLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 2 Refl)
        (ConsField _ _ (DivideBy 3 Refl) NoFields)))

||| The `nimiser_result` layout is C-ABI compliant.
||| Fields: code @0 align 4 (0 = 0*4), message @8 align 8 (8 = 1*8).
export
nimResultCompliant : CABICompliant Layout.nimResultLayout
nimResultCompliant =
  CABIOk nimResultLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl) NoFields))

--------------------------------------------------------------------------------
-- Result-code encoding facts
--------------------------------------------------------------------------------

||| The success result encodes to the C integer 0.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The null-pointer result encodes to the C integer 4 (a nontrivial, distinct
||| code in the middle of the enumeration).
export
nullPointerIsFour : resultToInt NullPointer = 4
nullPointerIsFour = Refl

||| The result encoding is injective on the two error codes we pin here:
||| distinct constructors map to distinct integers, witnessed structurally.
export
okDistinctFromError : Not (resultToInt Ok = resultToInt Error)
okDistinctFromError = \case Refl impossible
