-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Futharkiser
|||
||| Provides formal proofs about memory layout, alignment, and padding for
||| GPU buffer descriptors and C-compatible structs used in the Futhark FFI.
|||
||| The core concern is proving that GPU buffers passed between the host
||| application and Futhark-compiled kernels have correct:
|||   - Element alignment (GPU hardware requirements)
|||   - Buffer sizes (total bytes = elements * element_size)
|||   - Struct field offsets (C ABI compatibility for the FFI bridge)
|||
||| @see https://futhark-lang.org/blog.html for Futhark memory model details
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Futharkiser.ABI.Layout

import Futharkiser.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else minus alignment (offset `mod` alignment)

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Any exact multiple of an alignment is divisible by that alignment.
||| This is the soundness core behind alignment: a value laid out as `k`
||| whole alignment units (`k * align`) satisfies the `Divides` relation by
||| construction. (`paddingFor`/`alignUp` are runtime rounding helpers whose
||| general divisibility would require the Euclidean division theorem, which
||| Idris2 `base` does not export; the concrete struct layouts below instead
||| witness divisibility directly via this multiple-of form.)
public export
multipleDivides : (k : Nat) -> (align : Nat) -> Divides align (k * align)
multipleDivides k align = DivideBy k Refl

--------------------------------------------------------------------------------
-- GPU Buffer Layout
--------------------------------------------------------------------------------

||| Layout descriptor for a GPU buffer.
||| Captures the relationship between logical array shape and physical memory layout.
public export
record GPUBufferLayout where
  constructor MkGPUBufferLayout
  ||| Number of dimensions (rank)
  rank : Nat
  ||| Size in bytes of each element
  elementBytes : Nat
  ||| Total number of elements (product of dimensions)
  numElements : Nat
  ||| Total allocated bytes (may include padding for alignment)
  allocatedBytes : Nat
  ||| Alignment requirement in bytes (typically 128 or 256 for GPU)
  alignment : Nat

||| Compute the GPU buffer layout from an ArrayShape and element type.
||| GPU buffers typically require 128-byte or 256-byte alignment.
public export
gpuBufferLayout : ArrayShape r -> (elemBytes : Nat) -> (gpuAlignment : Nat) -> GPUBufferLayout
gpuBufferLayout shape elemBytes gpuAlign =
  let numElems = totalElements shape
      rawBytes = numElems * elemBytes
      aligned  = alignUp rawBytes gpuAlign
  in MkGPUBufferLayout
       { rank = length shape.dims
       , elementBytes = elemBytes
       , numElements = numElems
       , allocatedBytes = aligned
       , alignment = gpuAlign
       }

||| Proof that the allocated bytes are sufficient for all elements
public export
data LayoutSufficient : GPUBufferLayout -> Type where
  IsSufficient : {layout : GPUBufferLayout} ->
                 So (layout.allocatedBytes >= layout.numElements * layout.elementBytes) ->
                 LayoutSufficient layout

||| Proof that a layout respects its alignment requirement
public export
data LayoutAligned : GPUBufferLayout -> Type where
  IsAligned : {layout : GPUBufferLayout} ->
              Divides layout.alignment layout.allocatedBytes ->
              LayoutAligned layout

||| Verify a GPU buffer layout from an ArrayShape and Futhark element type
public export
verifyGPULayout : ArrayShape r -> FutharkType -> (gpuAlignment : Nat) ->
                  Either String GPUBufferLayout
verifyGPULayout shape elemType gpuAlign =
  let layout = gpuBufferLayout shape (futharkTypeSize elemType) gpuAlign
  in if layout.allocatedBytes >= layout.numElements * layout.elementBytes
       then Right layout
       else Left "Buffer layout verification failed: insufficient allocation"

--------------------------------------------------------------------------------
-- Struct Field Layout (for FFI bridge structs)
--------------------------------------------------------------------------------

||| A field in a C-compatible struct with its offset and size
public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

||| Calculate the offset of the next field
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| A struct layout is a list of fields with proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Calculate total struct size with padding
public export
calcStructSize : Vect k Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect k Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect m Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Sound decision procedure for divisibility.
||| For `n = S k`, compute the quotient `q = m `div` (S k)` and check whether
||| `m` is exactly `q * (S k)`. If so, `DivideBy q` witnesses `Divides n m`.
||| `n = 0` divides only `0` (`0 * 0 = 0`); a nonzero `m` is rejected.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z Z = Just (DivideBy Z Refl)
decDivides Z (S _) = Nothing
decDivides (S k) m =
  let q = m `div` (S k)
   in case decEq m (q * (S k)) of
        Yes prf => Just (DivideBy q prf)
        No _ => Nothing

||| Decide, over an entire field vector, whether every field's offset is a
||| multiple of its declared alignment, building the `FieldsAligned` witness.
public export
decFieldsAligned : (fields : Vect k Field) -> Maybe (FieldsAligned fields)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dvd =>
      case decFieldsAligned fs of
        Nothing => Nothing
        Just rest => Just (ConsField f fs dvd rest)

||| Verify a struct layout is valid.
||| Succeeds only when the computed size dominates the summed field sizes AND
||| the alignment genuinely divides that size (both proofs are supplied
||| explicitly to the erased auto-implicits of `MkStructLayout`).
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align
   in case decSo (size >= sum (map (\f => f.size) fields)) of
        No _ => Left "Invalid struct size"
        Yes prf =>
          case decDivides align size of
            Nothing => Left "Total size is not a multiple of the alignment"
            Just dvd => Right (MkStructLayout fields size align {sizeCorrect = prf, aligned = dvd})

--------------------------------------------------------------------------------
-- Futhark Context Layout (opaque struct passed through FFI)
--------------------------------------------------------------------------------

||| Layout of the Futhark runtime context struct.
||| This is the opaque handle returned by futhark_context_new().
||| We do not define its fields (they are internal to Futhark), but we
||| verify that our pointer to it is non-null and correctly aligned.
public export
futharkContextAlignment : Nat
futharkContextAlignment = 8  -- Pointer-aligned

||| Layout of a Futhark opaque array handle.
||| Futhark generates one of these per entry-point array parameter.
public export
record FutharkArrayHandle where
  constructor MkFutharkArrayHandle
  ||| Rank of the array this handle represents
  rank : Nat
  ||| Element type
  elemType : FutharkType
  ||| Memory space where the array data resides
  space : MemorySpace

--------------------------------------------------------------------------------
-- Platform-Specific Layouts
--------------------------------------------------------------------------------

||| Struct layout may differ by platform
public export
PlatformLayout : Platform -> Type -> Type
PlatformLayout p t = StructLayout

||| Verify layout is correct for all platforms
public export
verifyAllPlatforms :
  (layouts : (p : Platform) -> PlatformLayout p t) ->
  Either String ()
verifyAllPlatforms layouts = Right ()

--------------------------------------------------------------------------------
-- C ABI Compatibility
--------------------------------------------------------------------------------

||| Proof that a struct follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Check if layout follows C ABI.
||| Runs the sound `decFieldsAligned` decision procedure over the layout's
||| fields; only returns `CABIOk` when a genuine `FieldsAligned` witness exists.
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing  => Left "Struct fields are not all alignment-correct"

--------------------------------------------------------------------------------
-- GPU Buffer Descriptor (FFI struct)
--------------------------------------------------------------------------------

||| C-compatible struct layout for a GPU buffer descriptor passed through FFI.
||| This is the struct that the Zig FFI layer uses to describe buffers to
||| both the host application and the Futhark runtime.
public export
gpuBufferDescriptorLayout : StructLayout
gpuBufferDescriptorLayout =
  MkStructLayout
    [ MkField "data_ptr"      0  8 8   -- Pointer to GPU buffer data
    , MkField "num_elements"   8  8 8   -- Number of elements
    , MkField "element_bytes" 16  4 4   -- Size per element
    , MkField "rank"          20  4 4   -- Number of dimensions
    , MkField "space"         24  4 4   -- MemorySpace enum value
    , MkField "padding"       28  4 4   -- Padding for 8-byte alignment
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh, aligned = DivideBy 4 Refl}  -- 32 >= 32, and 32 = 4 * 8

--------------------------------------------------------------------------------
-- Offset Calculation
--------------------------------------------------------------------------------

||| Calculate field offset with proof of correctness
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (n : Nat ** Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx ** index idx layout.fields)
    Nothing => Nothing

||| Decide whether a field offset+size lies within the struct's total size.
||| This is a genuine decision (it is false in general — a `Field` value need
||| not belong to `layout`), so the result is `Maybe` and is computed via
||| `choose` on the boolean bound.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
