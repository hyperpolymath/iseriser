-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the halideiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete C-ABI struct
||| layout were misaligned, the result-code encoding wrong, or a decision
||| procedure mis-defined, this module would fail to typecheck and the proof
||| build would go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Halideiser.ABI.Proofs

import Halideiser.ABI.Types
import Halideiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete halide C struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in halide_buffer_t divides its alignment:
||| 0|8, 8|8, 16|8, 24|8, 32|4, 36|4, 40|8, 48|8.
export
halideBufferTCompliant : CABICompliant Layout.halideBufferTStruct
halideBufferTCompliant =
  CABIOk halideBufferTStruct
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
    (ConsField _ _ (DivideBy 9 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
     NoFields))))))))

||| Every field offset in halide_dimension_t divides its alignment:
||| 0|4, 4|4, 8|4, 12|4.
export
halideDimensionTCompliant : CABICompliant Layout.halideDimensionTStruct
halideDimensionTCompliant =
  CABIOk halideDimensionTStruct
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
dimensionMismatchIsSeven : resultToInt DimensionMismatch = 7
dimensionMismatchIsSeven = Refl

--------------------------------------------------------------------------------
-- SIMD widths and pixel byte widths are positive (sanity for codegen).
--------------------------------------------------------------------------------

||| AVX-512 carries a 16-wide float lane, as the schedule generator expects.
export
avx512Width : simdWidth X86_AVX512 = 16
avx512Width = Refl

||| Float64 pixels are 8 bytes, as the buffer byte calculation depends on.
export
float64Bytes : pixelBytes Float64 = 8
float64Bytes = Refl
