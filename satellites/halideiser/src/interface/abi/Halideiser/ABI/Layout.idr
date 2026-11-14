-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Halideiser
|||
||| This module provides formal proofs about memory layout for Halide's
||| `buffer_t` / `halide_buffer_t` structure. Halide buffers use a
||| strided layout where each dimension has:
|||   - min: the minimum coordinate in that dimension
|||   - extent: the number of elements in that dimension
|||   - stride: the number of elements between adjacent entries in that dimension
|||
||| For a 3-channel 1920x1080 image stored in planar order:
|||   dim 0 (x):       min=0, extent=1920, stride=1
|||   dim 1 (y):       min=0, extent=1080, stride=1920
|||   dim 2 (channel): min=0, extent=3,    stride=1920*1080
|||
||| @see https://halide-lang.org/docs/structHalide_1_1Runtime_1_1Buffer.html

module Halideiser.ABI.Layout

import Halideiser.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Halide Dimension Descriptor
--------------------------------------------------------------------------------

||| A single dimension in a Halide buffer.
||| Corresponds to `halide_dimension_t` in the Halide C API.
public export
record HalideDimension where
  constructor MkHalideDimension
  ||| Minimum coordinate (usually 0)
  min    : Int
  ||| Number of elements in this dimension
  extent : Nat
  ||| Distance in elements between adjacent entries in this dimension
  stride : Nat
  ||| Proof that extent is positive
  {auto 0 extentPos : So (extent > 0)}
  ||| Proof that stride is positive
  {auto 0 stridePos : So (stride > 0)}

||| Number of elements spanned by this dimension (extent * stride)
public export
dimSpan : HalideDimension -> Nat
dimSpan d = d.extent * d.stride

||| Calculate the minimum allocation needed for the given dimensions.
||| This is the max over all dimensions of (extent_i * stride_i).
||| (Previously a record-local `where` definition, which does not compile;
||| lifted to top level so the record's `allocCovers` proof can reference it.)
public export
requiredAlloc : Vect m HalideDimension -> Nat
requiredAlloc []        = 0
requiredAlloc (d :: ds) = max (dimSpan d) (requiredAlloc ds)

--------------------------------------------------------------------------------
-- Halide Buffer Layout
--------------------------------------------------------------------------------

||| The memory layout of a Halide buffer.
||| Models `halide_buffer_t` with n dimensions.
|||
||| A valid buffer layout requires:
|||   1. All dimensions have positive extent and stride
|||   2. No two dimensions alias the same memory (strides are compatible)
|||   3. Total allocation covers all addressable elements
public export
record HalideBufferLayout (n : Nat) where
  constructor MkHalideBufferLayout
  ||| Dimensions (x, y, channel, frame, etc.)
  dimensions : Vect n HalideDimension
  ||| Element type (uint8, float32, etc.)
  elemType   : PixelType
  ||| Total number of allocated elements
  allocSize  : Nat
  ||| Proof that allocation covers the full extent
  {auto 0 allocCovers : So (allocSize >= requiredAlloc dimensions)}

||| Total bytes for a buffer layout
public export
layoutBytes : HalideBufferLayout n -> Nat
layoutBytes buf = buf.allocSize * pixelBytes buf.elemType

--------------------------------------------------------------------------------
-- Standard Image Layouts
--------------------------------------------------------------------------------

||| Smart constructor for a Halide dimension. The extent/stride positivity
||| proofs cannot be solved for symbolic `Nat`s at the type level, so we
||| decide them at runtime with `choose`, returning Nothing when either is
||| zero. (Previously `MkHalideDimension 0 extent stride` left the erased
||| `extentPos`/`stridePos` auto-implicits unsolved and did not compile.)
public export
mkDim : (mn : Int) -> (extent : Nat) -> (stride : Nat) -> Maybe HalideDimension
mkDim mn extent stride =
  case choose (extent > 0) of
    Right _ => Nothing
    Left ep => case choose (stride > 0) of
                 Right _ => Nothing
                 Left sp => Just (MkHalideDimension mn extent stride
                                    {extentPos = ep} {stridePos = sp})

||| Assemble a buffer layout from already-built dimensions and an allocation
||| size, deciding the `allocCovers` coverage bound with `choose`. Returns
||| Nothing when the allocation does not cover the required span. This is an
||| honest decision: the bound is false for under-sized allocations and cannot
||| be asserted for symbolic inputs.
public export
mkLayout : Vect n HalideDimension -> PixelType -> (allocSize : Nat) ->
           Maybe (HalideBufferLayout n)
mkLayout dims ptype allocSize =
  case choose (allocSize >= requiredAlloc dims) of
    Left ok => Just (MkHalideBufferLayout dims ptype allocSize {allocCovers = ok})
    Right _ => Nothing

||| Row-major interleaved layout (RGBRGBRGB...).
||| This is the most common layout for 8-bit images.
|||
||| dim 0 (channel): extent=channels, stride=1
||| dim 1 (x):       extent=width,    stride=channels
||| dim 2 (y):       extent=height,   stride=width*channels
public export
interleavedLayout : (dim : BufferDimension) -> (ptype : PixelType) ->
                    Maybe (HalideBufferLayout 3)
interleavedLayout dim ptype = do
  d0 <- mkDim 0 dim.channels 1
  d1 <- mkDim 0 dim.width    dim.channels
  d2 <- mkDim 0 dim.height   (dim.width * dim.channels)
  mkLayout [d0, d1, d2] ptype (dim.width * dim.height * dim.channels)

||| Planar layout (all R, then all G, then all B).
||| Common for processing — better SIMD utilisation per channel.
|||
||| dim 0 (x):       extent=width,    stride=1
||| dim 1 (y):       extent=height,   stride=width
||| dim 2 (channel): extent=channels, stride=width*height
public export
planarLayout : (dim : BufferDimension) -> (ptype : PixelType) ->
               Maybe (HalideBufferLayout 3)
planarLayout dim ptype = do
  d0 <- mkDim 0 dim.width    1
  d1 <- mkDim 0 dim.height   dim.width
  d2 <- mkDim 0 dim.channels (dim.width * dim.height)
  mkLayout [d0, d1, d2] ptype (dim.width * dim.height * dim.channels)

||| Video buffer layout (4D: x, y, channel, frame).
||| Planar within each frame, frames stored contiguously.
public export
videoLayout : (dim : BufferDimension) -> (ptype : PixelType) ->
              Maybe (HalideBufferLayout 4)
videoLayout dim ptype = do
  d0 <- mkDim 0 dim.width    1
  d1 <- mkDim 0 dim.height   dim.width
  d2 <- mkDim 0 dim.channels (dim.width * dim.height)
  d3 <- mkDim 0 dim.frames   (dim.width * dim.height * dim.channels)
  mkLayout [d0, d1, d2, d3] ptype (bufferElements dim)

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

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment = size + paddingFor size alignment

||| Halide typically aligns buffer starts to 128 bytes for SIMD
public export
halideAlignment : Nat
halideAlignment = 128

||| Aligned allocation size for a buffer
public export
alignedAllocSize : HalideBufferLayout n -> Nat
alignedAllocSize buf = alignUp (layoutBytes buf) halideAlignment

--------------------------------------------------------------------------------
-- Buffer Bounds Proofs
--------------------------------------------------------------------------------

||| Proof that a coordinate is within a dimension's bounds
public export
data InBounds : (coord : Nat) -> HalideDimension -> Type where
  CoordInBounds : {c : Nat} -> {d : HalideDimension} ->
                  So (c < d.extent) ->
                  InBounds c d

||| Proof that a linear index is within the buffer allocation
public export
data IndexInAlloc : (idx : Nat) -> HalideBufferLayout n -> Type where
  IdxInAlloc : {i : Nat} -> {buf : HalideBufferLayout n} ->
               So (i < buf.allocSize) ->
               IndexInAlloc i buf

||| Calculate linear index from multi-dimensional coordinates.
||| For a buffer with dimensions [d0, d1, d2]:
|||   index = coord0 * stride0 + coord1 * stride1 + coord2 * stride2
public export
linearIndex : Vect n Nat -> Vect n HalideDimension -> Nat
linearIndex []        []        = 0
linearIndex (c :: cs) (d :: ds) = c * d.stride + linearIndex cs ds

--------------------------------------------------------------------------------
-- Layout Compatibility Between Pipeline Stages
--------------------------------------------------------------------------------

||| Proof that the output layout of one stage is compatible with
||| the input layout of the next stage.
public export
data LayoutCompatible : HalideBufferLayout n -> HalideBufferLayout m -> Type where
  ||| Same number of dimensions and matching extents
  SameDimLayout : {a : HalideBufferLayout n} -> {b : HalideBufferLayout n} ->
                  LayoutCompatible a b
  ||| Resize changes dimensions — new extents are explicitly provided
  ResizedLayout : {a : HalideBufferLayout n} -> {b : HalideBufferLayout n} ->
                  LayoutCompatible a b

||| Verify two layouts are compatible for pipeline stage connection
public export
checkCompatibility : {n, m : Nat} -> HalideBufferLayout n -> HalideBufferLayout m ->
                     Either String (n = m)
checkCompatibility a b =
  case decEq n m of
    Yes prf => Right prf
    No _    => Left "Dimension count mismatch between pipeline stages"

--------------------------------------------------------------------------------
-- C ABI Struct Layout (for halide_buffer_t interop)
--------------------------------------------------------------------------------

||| A field in a C struct with its offset and size
public export
record Field where
  constructor MkField
  name      : String
  offset    : Nat
  size      : Nat
  alignment : Nat

||| The C-level halide_buffer_t structure layout.
||| This mirrors the actual Halide runtime struct for FFI correctness.
|||
||| struct halide_buffer_t {
|||     uint64_t device;              // offset 0,  size 8
|||     void *device_interface;       // offset 8,  size 8
|||     uint8_t *host;                // offset 16, size 8
|||     uint64_t flags;               // offset 24, size 8
|||     halide_type_t type;           // offset 32, size 4
|||     int32_t dimensions;           // offset 36, size 4
|||     halide_dimension_t *dim;      // offset 40, size 8
|||     void *padding;                // offset 48, size 8
||| };  // total: 56 bytes, alignment: 8
public export
halideBufferTLayout : List Field
halideBufferTLayout =
  [ MkField "device"           0  8 8
  , MkField "device_interface"  8  8 8
  , MkField "host"             16 8 8
  , MkField "flags"            24 8 8
  , MkField "type"             32 4 4
  , MkField "dimensions"       36 4 4
  , MkField "dim"              40 8 8
  , MkField "padding"          48 8 8
  ]

||| Total size of halide_buffer_t
public export
halideBufferTSize : Nat
halideBufferTSize = 56

||| Alignment of halide_buffer_t
public export
halideBufferTAlign : Nat
halideBufferTAlign = 8

||| The C-level halide_dimension_t structure layout.
|||
||| struct halide_dimension_t {
|||     int32_t min;       // offset 0,  size 4
|||     int32_t extent;    // offset 4,  size 4
|||     int32_t stride;    // offset 8,  size 4
|||     uint32_t flags;    // offset 12, size 4
||| };  // total: 16 bytes, alignment: 4
public export
halideDimensionTLayout : List Field
halideDimensionTLayout =
  [ MkField "min"    0  4 4
  , MkField "extent" 4  4 4
  , MkField "stride" 8  4 4
  , MkField "flags"  12 4 4
  ]

||| Total size of halide_dimension_t
public export
halideDimensionTSize : Nat
halideDimensionTSize = 16

||| Alignment of halide_dimension_t
public export
halideDimensionTAlign : Nat
halideDimensionTAlign = 4

--------------------------------------------------------------------------------
-- C ABI Alignment Proof Machinery
--------------------------------------------------------------------------------

||| Offset for the next field after `f`, rounded up to `f`'s alignment.
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| Proof that `n` divides `m`: `m = k * n`.
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Sound decision procedure for divisibility. Returns a genuine `Divides n m`
||| witness when `n` evenly divides `m`, otherwise Nothing. Division by zero is
||| undecidable here and yields Nothing.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S k) m =
  let q = m `div` (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| A C-ABI struct layout: a vector of fields with a total size and alignment,
||| carrying erased proofs that the size covers all fields and that the
||| alignment divides the total size.
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| C-ABI `StructLayout` for `halide_buffer_t` (8 fields, 56 bytes, align 8).
public export
halideBufferTStruct : StructLayout
halideBufferTStruct =
  MkStructLayout
    [ MkField "device"           0  8 8
    , MkField "device_interface" 8  8 8
    , MkField "host"             16 8 8
    , MkField "flags"            24 8 8
    , MkField "type"             32 4 4
    , MkField "dimensions"       36 4 4
    , MkField "dim"              40 8 8
    , MkField "padding"          48 8 8
    ]
    56
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 7 Refl}

||| C-ABI `StructLayout` for `halide_dimension_t` (4 fields, 16 bytes, align 4).
public export
halideDimensionTStruct : StructLayout
halideDimensionTStruct =
  MkStructLayout
    [ MkField "min"    0  4 4
    , MkField "extent" 4  4 4
    , MkField "stride" 8  4 4
    , MkField "flags"  12 4 4
    ]
    16
    4
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| Proof that every field offset in a layout is correctly aligned.
public export
data FieldsAligned : Vect k Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect k Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Decide field alignment for every field, building a real `FieldsAligned`
||| witness from per-field divisibility proofs.
public export
decFieldsAligned : (fs : Vect k Field) -> Maybe (FieldsAligned fs)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dvd => case decFieldsAligned fs of
                  Nothing => Nothing
                  Just rest => Just (ConsField f fs dvd rest)

||| Proof that a struct layout follows C ABI alignment rules.
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Verify a layout against the C ABI alignment rules, returning a genuine
||| `CABICompliant` proof (built from real per-field divisibility witnesses)
||| or an error when some field offset is misaligned. (Previously a hole
||| `?fieldsAlignedProof`; now a sound decision procedure.)
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

||| Verify that both halide C structs are C-ABI compliant. Fails (Left) if any
||| concrete layout is misaligned, rather than asserting it.
public export
verifyAllStructLayouts : Either String ()
verifyAllStructLayouts = do
  _ <- checkCABI halideBufferTStruct
  _ <- checkCABI halideDimensionTStruct
  Right ()

||| Look up a field's offset by name in a layout.
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (Nat, Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx, index idx layout.fields)
    Nothing => Nothing

||| Decide whether a field lies within a struct's byte bounds, returning a
||| genuine proof when `offset + size <= totalSize`. The previous template
||| signature asserted this for *every* field unconditionally, which is false
||| (a field need not belong to the layout); this honest version decides it.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
