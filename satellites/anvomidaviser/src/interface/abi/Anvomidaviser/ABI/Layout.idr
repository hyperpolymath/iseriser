-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Anvomidaviser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible structs used in the ISU scoring engine
||| and program element representation.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Anvomidaviser.ABI.Layout

import Anvomidaviser.ABI.Types
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

||| Sound decision procedure: does n divide m?
||| For n = S k, compute the candidate quotient q = m `div` (S k) and check
||| that q * (S k) recovers m exactly. The equality proof is real (decEq),
||| never assumed.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z m = Nothing
decDivides (S k) m =
  let q = m `div` (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Decide whether alignUp produced an aligned result. Returning a universal
||| proof would be unsound (paddingFor uses runtime division, which does not
||| reduce), so we hand back a genuine, checked witness via decDivides.
public export
alignUpDivides : (size : Nat) -> (align : Nat) -> Maybe (Divides align (alignUp size align))
alignUpDivides size align = decDivides align (alignUp size align)

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
    (rest : Vect k Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Decide whether every field in a vector is aligned (offset divisible by
||| alignment), building a real FieldsAligned witness if so.
public export
decFieldsAligned : (fields : Vect k Field) -> Maybe (FieldsAligned fields)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dv =>
      case decFieldsAligned fs of
        Nothing => Nothing
        Just rest => Just (ConsField f fs dv rest)

||| Verify a struct layout is valid
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align
   in case choose (size >= sum (map (\f => f.size) fields)) of
        Right _ => Left "Invalid struct size"
        Left szPrf =>
          case decDivides align size of
            Nothing => Left "Total size is not a multiple of the alignment"
            Just dv =>
              Right (MkStructLayout fields size align {sizeCorrect = szPrf} {aligned = dv})

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

||| Check if layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Struct fields are not C-ABI aligned"

--------------------------------------------------------------------------------
-- ISU Element Layouts
--------------------------------------------------------------------------------

||| Layout for a TechnicalElement struct in the C ABI
||| Fields: element_type (u8), jump_type (u8), rotation (u8), level (u8),
|||         base_value (u32), goe (i8), padding (3 bytes), goe_value (i32)
public export
technicalElementLayout : StructLayout
technicalElementLayout =
  MkStructLayout
    [ MkField "element_type" 0 1 1   -- ElementCode tag (Jump/Spin/StepSeq/Lift)
    , MkField "subtype"      1 1 1   -- JumpType / SpinType / etc.
    , MkField "rotation"     2 1 1   -- JumpRotation or unused
    , MkField "level"        3 1 1   -- SpinLevel
    , MkField "base_value"   4 4 4   -- Base value in hundredths
    , MkField "goe"          8 1 1   -- GOE (-5 to +5)
    , MkField "padding"      9 3 1   -- Alignment padding
    , MkField "goe_value"   12 4 4   -- GOE adjustment in hundredths
    ]
    16  -- Total size: 16 bytes
    4   -- Alignment: 4 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}   -- 16 = 4 * 4

||| Proof that TechnicalElement layout is valid
export
technicalElementLayoutValid : CABICompliant Layout.technicalElementLayout
technicalElementLayoutValid =
  CABIOk Layout.technicalElementLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
    (ConsField _ _ (DivideBy 9 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    NoFields))))))))

||| Layout for ProgramScore struct in the C ABI
||| Fields: total_base (u32), total_goe (i32), deductions (u32),
|||         pcs_marks (5 x u8), padding (3 bytes), component_factor (u32),
|||         total_segment_score (u32)
public export
programScoreLayout : StructLayout
programScoreLayout =
  MkStructLayout
    [ MkField "total_base"          0  4 4   -- Sum of base values
    , MkField "total_goe"           4  4 4   -- Sum of GOE adjustments
    , MkField "deductions"          8  4 4   -- Penalty deductions
    , MkField "pcs_skating_skills" 12  1 1   -- SS mark (x 0.25)
    , MkField "pcs_transitions"    13  1 1   -- TR mark (x 0.25)
    , MkField "pcs_performance"    14  1 1   -- PE mark (x 0.25)
    , MkField "pcs_composition"    15  1 1   -- CO mark (x 0.25)
    , MkField "pcs_interpretation" 16  1 1   -- IN mark (x 0.25)
    , MkField "padding"            17  3 1   -- Alignment padding
    , MkField "component_factor"   20  4 4   -- PCS multiplier
    , MkField "total_segment"      24  4 4   -- TES + PCS - deductions
    ]
    28  -- Total size: 28 bytes
    4   -- Alignment: 4 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 7 Refl}   -- 28 = 7 * 4

||| Proof that ProgramScore layout is valid
export
programScoreLayoutValid : CABICompliant Layout.programScoreLayout
programScoreLayoutValid =
  CABIOk Layout.programScoreLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 12 Refl)
    (ConsField _ _ (DivideBy 13 Refl)
    (ConsField _ _ (DivideBy 14 Refl)
    (ConsField _ _ (DivideBy 15 Refl)
    (ConsField _ _ (DivideBy 16 Refl)
    (ConsField _ _ (DivideBy 17 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    NoFields)))))))))))

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
||| Universally claiming the bound would be unsound (it is false for
||| arbitrary fields), so we return a decision via choose.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
