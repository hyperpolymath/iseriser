-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked ABI theorems for Mylangiser.
|||
||| Each concrete StructLayout defined in Mylangiser.ABI.Layout is proven to be
||| C-ABI compliant by constructing the FieldsAligned witness directly. For every
||| field, offset = k * alignment, witnessed by `DivideBy k Refl` (multiplication
||| reduces during typechecking; division does not, so the witnesses are built by
||| hand rather than via decFieldsAligned).
|||
||| We also pin the FFI result-code encoding.

module Mylangiser.ABI.Proofs

import Mylangiser.ABI.Types
import Mylangiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI compliance of the concrete layouts
--------------------------------------------------------------------------------

||| The API-surface descriptor layout obeys C-ABI field alignment.
||| Field offsets: 0=0*4, 4=1*4, 8=2*4, 12=3*4, 16=2*8.
export
apiSurfaceCompliant : CABICompliant Layout.apiSurfaceLayout
apiSurfaceCompliant =
  CABIOk Layout.apiSurfaceLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields)))))

||| The endpoint descriptor layout obeys C-ABI field alignment.
||| Field offsets: 0=0*8, 8=2*4, 12=3*4, 16=4*4, 20=5*4, 24=6*4, 28=7*4,
||| 32=8*4, 36=9*4.
export
endpointDescriptorCompliant : CABICompliant Layout.endpointDescriptorLayout
endpointDescriptorCompliant =
  CABIOk Layout.endpointDescriptorLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
    (ConsField _ _ (DivideBy 9 Refl)
     NoFields)))))))))

||| The wrapper descriptor layout obeys C-ABI field alignment.
||| Field offsets: 0=0*8, 8=2*4, 12=3*4, 16=4*4, 20=5*4, 24=6*4, 28=7*4,
||| 32=8*4, 36=9*4.
export
wrapperDescriptorCompliant : CABICompliant Layout.wrapperDescriptorLayout
wrapperDescriptorCompliant =
  CABIOk Layout.wrapperDescriptorLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
    (ConsField _ _ (DivideBy 9 Refl)
     NoFields)))))))))

--------------------------------------------------------------------------------
-- Result-code encoding
--------------------------------------------------------------------------------

||| The success code Ok encodes to the C integer 0.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The result-code encoding is injective on the first two codes:
||| Ok and Error map to distinct integers, so the encoding distinguishes them.
export
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct = \case Refl impossible

||| Beginner is the least disclosure level: it encodes to 0.
export
beginnerIsZero : disclosureLevelToInt Beginner = 0
beginnerIsZero = Refl
