-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked ABI theorems for Futharkiser.
|||
||| These are genuine, fully-elaborated proofs (no holes and no escape
||| hatches of any kind). They pin down two classes of fact:
|||
|||   1. C-ABI compliance of the concrete FFI struct layouts — every field's
|||      offset is an exact multiple of its declared alignment. The witnesses
|||      are built DIRECTLY as `DivideBy k Refl` (multiplication reduces during
|||      type-checking; division does not, so we never route through the
|||      `decFieldsAligned` decision procedure here).
|||
|||   2. The result-code encoding contract used across the FFI boundary
|||      (`Ok` maps to 0, distinct codes stay distinct).
|||
||| @see Futharkiser.ABI.Layout for the layout definitions
||| @see Futharkiser.ABI.Types for the result-code definitions

module Futharkiser.ABI.Proofs

import Futharkiser.ABI.Types
import Futharkiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI compliance of the concrete GPU buffer descriptor struct
--------------------------------------------------------------------------------

||| The GPU buffer descriptor struct passed through the Zig FFI is C-ABI
||| compliant: each of its six fields sits at an offset that is an exact
||| multiple of that field's alignment.
|||
|||   data_ptr      @ 0  align 8  ->  0  = 0 * 8
|||   num_elements  @ 8  align 8  ->  8  = 1 * 8
|||   element_bytes @ 16 align 4  ->  16 = 4 * 4
|||   rank          @ 20 align 4  ->  20 = 5 * 4
|||   space         @ 24 align 4  ->  24 = 6 * 4
|||   padding       @ 28 align 4  ->  28 = 7 * 4
export
gpuBufferDescriptorCompliant : CABICompliant Layout.gpuBufferDescriptorLayout
gpuBufferDescriptorCompliant =
  CABIOk Layout.gpuBufferDescriptorLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields))))))

--------------------------------------------------------------------------------
-- Divisibility primitive sanity
--------------------------------------------------------------------------------

||| The total size of the descriptor struct (32 bytes) is an exact multiple of
||| its 8-byte alignment: 32 = 4 * 8.
export
descriptorSizeAligned : Divides 8 32
descriptorSizeAligned = DivideBy 4 Refl

--------------------------------------------------------------------------------
-- Result-code encoding contract
--------------------------------------------------------------------------------

||| `Ok` is the zero result code, as the C FFI boundary relies on.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The error code is one, distinct from success.
export
errorIsOne : resultToInt Error = 1
errorIsOne = Refl

||| Success and shape-mismatch encode to genuinely different integers,
||| so callers can discriminate them across the FFI boundary.
export
okDistinctFromShapeMismatch : Not (resultToInt Ok = resultToInt ShapeMismatch)
okDistinctFromShapeMismatch = \case Refl impossible

--------------------------------------------------------------------------------
-- Element-size contract
--------------------------------------------------------------------------------

||| A 64-bit float occupies eight bytes, matching the descriptor's element
||| layout assumptions.
export
f64IsEightBytes : futharkTypeSize F64 = 8
f64IsEightBytes = Refl
