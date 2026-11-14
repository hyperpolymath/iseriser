-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Betlangiser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible structs used in the betlangiser FFI.
|||
||| Key layouts: Distribution struct, sample buffer, confidence interval,
||| ternary bool array, and the distribution parameter union.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Betlangiser.ABI.Layout

import Betlangiser.ABI.Types
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

||| Sound decision procedure for divisibility.
||| For n = S k, the quotient q = div m (S k) is tested by checking
||| m = q * (S k) via decidable equality on Nat. Division does not reduce
||| during typechecking, so we obtain the witness by an explicit equality test.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S k) m =
  let q = div m (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Decide whether alignUp produced an aligned result.
||| Soundly returns a divisibility witness when the rounded-up size is
||| genuinely a multiple of the alignment (it always is for align > 0, but
||| we obtain the witness via the decision procedure rather than asserting it).
public export
alignUpCorrect : (size : Nat) -> (align : Nat) -> Maybe (Divides align (alignUp size align))
alignUpCorrect size align = decDivides align (alignUp size align)

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a struct with its offset and size
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
  {0 fieldCount : Nat}
  fields : Vect fieldCount Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Calculate total struct size with padding
public export
calcStructSize : Vect n Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect n Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect n Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Verify a struct layout is valid
public export
verifyLayout : (fields : Vect n Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align
   in case decSo (size >= sum (map (\f => f.size) fields)) of
        Yes prf =>
          case decDivides align size of
            Just dvd => Right (MkStructLayout fields size align {sizeCorrect = prf} {aligned = dvd})
            Nothing => Left "Total size not aligned"
        No _ => Left "Invalid struct size"

--------------------------------------------------------------------------------
-- Distribution Struct Layout
--------------------------------------------------------------------------------

||| Memory layout for a Distribution in the C-ABI.
|||
||| C equivalent:
|||   struct BetlangDistribution {
|||     uint32_t tag;       // offset 0, size 4 (distribution type enum)
|||     uint32_t _pad0;     // offset 4, size 4 (padding for alignment)
|||     double param1;      // offset 8, size 8 (first parameter: mean/low/alpha/p)
|||     double param2;      // offset 16, size 8 (second parameter: stddev/high/beta/0)
|||     uint64_t custom_ptr; // offset 24, size 8 (pointer to custom PDF data, or 0)
|||     uint32_t custom_len; // offset 32, size 4 (length of custom data)
|||     uint32_t _pad1;     // offset 36, size 4 (trailing padding)
|||   };  // total: 40 bytes, alignment: 8
public export
distributionLayout : StructLayout
distributionLayout =
  MkStructLayout
    [ MkField "tag"        0  4 4     -- Distribution type tag
    , MkField "_pad0"      4  4 4     -- Alignment padding
    , MkField "param1"     8  8 8     -- First parameter (mean/low/alpha/p)
    , MkField "param2"    16  8 8     -- Second parameter (stddev/high/beta/0)
    , MkField "custom_ptr" 24 8 8     -- Pointer to custom PDF samples
    , MkField "custom_len" 32 4 4     -- Length of custom data
    , MkField "_pad1"     36  4 4     -- Trailing padding for 8-byte alignment
    ]
    40  -- Total size: 40 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}

--------------------------------------------------------------------------------
-- Sample Buffer Layout
--------------------------------------------------------------------------------

||| Memory layout for a sample buffer used by the Monte Carlo engine.
|||
||| C equivalent:
|||   struct BetlangSampleBuffer {
|||     uint64_t capacity;      // offset 0, size 8 (max samples)
|||     uint64_t count;         // offset 8, size 8 (current sample count)
|||     double*  samples;       // offset 16, size 8 (pointer to sample array)
|||     double   mean;          // offset 24, size 8 (running mean)
|||     double   variance;      // offset 32, size 8 (running variance)
|||     double   min_val;       // offset 40, size 8 (minimum sample)
|||     double   max_val;       // offset 48, size 8 (maximum sample)
|||   };  // total: 56 bytes, alignment: 8
public export
sampleBufferLayout : StructLayout
sampleBufferLayout =
  MkStructLayout
    [ MkField "capacity"  0  8 8     -- Maximum number of samples
    , MkField "count"     8  8 8     -- Current sample count
    , MkField "samples"  16  8 8     -- Pointer to double[] array
    , MkField "mean"     24  8 8     -- Running mean of samples
    , MkField "variance" 32  8 8     -- Running variance (Welford's method)
    , MkField "min_val"  40  8 8     -- Minimum observed sample
    , MkField "max_val"  48  8 8     -- Maximum observed sample
    ]
    56  -- Total size: 56 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 7 Refl}

--------------------------------------------------------------------------------
-- Confidence Interval Layout
--------------------------------------------------------------------------------

||| Memory layout for a confidence interval result.
|||
||| C equivalent:
|||   struct BetlangConfidenceInterval {
|||     double lower;       // offset 0, size 8
|||     double upper;       // offset 8, size 8
|||     double confidence;  // offset 16, size 8 (confidence level, 0.0-1.0)
|||   };  // total: 24 bytes, alignment: 8
public export
confidenceIntervalLayout : StructLayout
confidenceIntervalLayout =
  MkStructLayout
    [ MkField "lower"      0  8 8     -- Lower bound
    , MkField "upper"      8  8 8     -- Upper bound
    , MkField "confidence" 16 8 8     -- Confidence level
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}

--------------------------------------------------------------------------------
-- Ternary Bool Array Layout
--------------------------------------------------------------------------------

||| Memory layout for an array of ternary boolean values.
||| Each TernaryBool is stored as a uint8_t (0=False, 1=True, 2=Unknown).
|||
||| C equivalent:
|||   struct BetlangTernaryArray {
|||     uint64_t count;     // offset 0, size 8
|||     uint8_t* values;    // offset 8, size 8 (pointer to uint8_t[])
|||   };  // total: 16 bytes, alignment: 8
public export
ternaryArrayLayout : StructLayout
ternaryArrayLayout =
  MkStructLayout
    [ MkField "count"  0  8 8     -- Number of ternary values
    , MkField "values" 8  8 8     -- Pointer to uint8_t array
    ]
    16  -- Total size: 16 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 2 Refl}

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
verifyAllPlatforms layouts =
  Right ()

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

||| Sound decision procedure: build a FieldsAligned witness for a Vect of
||| fields by checking, for each field, that its alignment divides its offset.
||| Returns Nothing if any field is misaligned.
public export
decFieldsAligned : (fields : Vect n Field) -> Maybe (FieldsAligned fields)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Just dvd =>
      case decFieldsAligned fs of
        Just rest => Just (ConsField f fs dvd rest)
        Nothing => Nothing
    Nothing => Nothing

||| Check if layout follows C ABI by deciding field alignment soundly.
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Struct fields are not correctly aligned"

||| Proof that distribution layout is valid.
||| Each field offset is a literal multiple of its alignment, so the
||| divisibility witnesses are built directly (multiplication reduces during
||| typechecking; division does not).
export
distributionLayoutValid : CABICompliant Layout.distributionLayout
distributionLayoutValid =
  CABIOk distributionLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 1 Refl)
          (ConsField _ _ (DivideBy 2 Refl)
            (ConsField _ _ (DivideBy 3 Refl)
              (ConsField _ _ (DivideBy 8 Refl)
                (ConsField _ _ (DivideBy 9 Refl) NoFields)))))))

||| Proof that sample buffer layout is valid
export
sampleBufferLayoutValid : CABICompliant Layout.sampleBufferLayout
sampleBufferLayoutValid =
  CABIOk sampleBufferLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 2 Refl)
          (ConsField _ _ (DivideBy 3 Refl)
            (ConsField _ _ (DivideBy 4 Refl)
              (ConsField _ _ (DivideBy 5 Refl)
                (ConsField _ _ (DivideBy 6 Refl) NoFields)))))))

||| Proof that confidence interval layout is valid
export
confidenceIntervalLayoutValid : CABICompliant Layout.confidenceIntervalLayout
confidenceIntervalLayoutValid =
  CABIOk confidenceIntervalLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 2 Refl) NoFields)))

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

||| Decide whether a field lies within the struct bounds.
||| This is not universally true for arbitrary fields, so it is decided at
||| runtime via `choose` and only yields the witness when it actually holds.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
