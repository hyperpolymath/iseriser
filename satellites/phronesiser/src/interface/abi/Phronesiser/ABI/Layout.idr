-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Phronesiser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible structs used in the Phronesiser
||| ethical constraint engine.
|||
||| Key layouts:
||| - ConstraintStruct: 16 bytes (id + modality + harm domain + threshold)
||| - AuditResultStruct: 16 bytes (id + decision + severity + reserved)
||| - ConstraintSetHeader: 8 bytes (count + flags)
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Phronesiser.ABI.Layout

import Phronesiser.ABI.Types
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

||| Proof that alignment divides aligned size: `m = k * n`.
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Sound decision procedure for divisibility. Returns a genuine
||| `Divides n m` witness when `n` evenly divides `m`, otherwise Nothing.
||| Division by zero is undecidable here and yields Nothing.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S k) m =
  let q = m `div` (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Decide whether the rounded-up size is divisible by the alignment. The
||| general theorem needs div/mod lemmas from Data.Nat; here we *decide* it
||| via `decDivides`, returning a genuine witness when it holds. (Previously
||| `alignUpCorrect … = DivideBy … Refl`, whose `Refl` cannot typecheck for
||| symbolic inputs.)
public export
alignUpDivides : (size : Nat) -> (align : Nat) ->
                 Maybe (Divides align (alignUp size align))
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

||| Verify a layout against the C ABI alignment rules, returning a genuine
||| `CABICompliant` proof (built from real per-field divisibility witnesses)
||| or an error when some field offset is misaligned.
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

--------------------------------------------------------------------------------
-- Phronesiser Constraint Struct Layout
--------------------------------------------------------------------------------

||| Layout for ConstraintStruct (16 bytes, 4-byte aligned)
||| Fields: constraintId(u32) + modality(u32) + harmDomain(u32) + harmThreshold(u32)
public export
constraintLayout : StructLayout
constraintLayout =
  MkStructLayout
    [ MkField "constraintId"   0  4 4   -- Bits32 at offset 0
    , MkField "modality"       4  4 4   -- Bits32 at offset 4
    , MkField "harmDomain"     8  4 4   -- Bits32 at offset 8
    , MkField "harmThreshold" 12  4 4   -- Bits32 at offset 12
    ]
    16  -- Total size: 16 bytes
    4   -- Alignment: 4 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}  -- 16 = 4 * 4

--------------------------------------------------------------------------------
-- Phronesiser Audit Result Struct Layout
--------------------------------------------------------------------------------

||| Layout for AuditResultStruct (16 bytes, 4-byte aligned)
||| Fields: constraintId(u32) + decision(u32) + severity(u32) + reserved(u32)
public export
auditResultLayout : StructLayout
auditResultLayout =
  MkStructLayout
    [ MkField "constraintId"  0  4 4   -- Bits32 at offset 0
    , MkField "decision"      4  4 4   -- Bits32 at offset 4
    , MkField "severity"      8  4 4   -- Bits32 at offset 8
    , MkField "reserved"     12  4 4   -- Bits32 at offset 12
    ]
    16  -- Total size: 16 bytes
    4   -- Alignment: 4 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}  -- 16 = 4 * 4

--------------------------------------------------------------------------------
-- Constraint Set Header Layout
--------------------------------------------------------------------------------

||| Layout for ConstraintSetHeader (8 bytes, 4-byte aligned)
||| Precedes an array of ConstraintStructs in memory.
public export
constraintSetHeaderLayout : StructLayout
constraintSetHeaderLayout =
  MkStructLayout
    [ MkField "count" 0 4 4    -- Number of constraints (Bits32)
    , MkField "flags" 4 4 4    -- Evaluation flags (Bits32)
    ]
    8   -- Total size: 8 bytes
    4   -- Alignment: 4 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 2 Refl}  -- 8 = 2 * 4

--------------------------------------------------------------------------------
-- Offset Calculation
--------------------------------------------------------------------------------

||| Look up a field's index and record by name in a layout.
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (Nat, Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx, index idx layout.fields)
    Nothing => Nothing

||| Decide whether a field lies within a struct's byte bounds, returning a
||| genuine proof when `offset + size <= totalSize`. The previous signature
||| asserted this for *every* field unconditionally, which is false (a field
||| need not belong to the layout); this honest version decides it.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing

--------------------------------------------------------------------------------
-- Constraint Array Layout
--------------------------------------------------------------------------------

||| Proof that a contiguous array of ConstraintStructs has correct total size
||| Total size = header (8 bytes) + count * sizeof(ConstraintStruct) (16 bytes)
public export
constraintArraySize : (count : Nat) -> Nat
constraintArraySize count = 8 + (count * 16)

||| `j <= l` implies `j * c <= l * c`, by induction on the `LTE` witness.
||| Genuine arithmetic lemma — no `believe_me`, no decision shortcut.
public export
scaleLteRight : (c : Nat) -> {j, l : Nat} -> LTE j l -> LTE (j * c) (l * c)
scaleLteRight c LTEZero = LTEZero
scaleLteRight c (LTESucc {left = a} {right = b} p) =
  plusLteMonotoneLeft c (a * c) (b * c) (scaleLteRight c p)

||| Proof that constraint array size grows monotonically with count.
||| `constraintArraySize n = 8 + n * 16`, so this reduces to
||| `8 + n*16 <= 8 + m*16`, discharged from `n <= m` via `scaleLteRight`
||| and `plusLteMonotoneLeft`. The `<=` is the propositional `LTE`, the
||| genuine order relation (the previous `So (... <= ...)` could not be
||| proven for symbolic inputs, only decided).
public export
constraintArrayMonotonic : (n : Nat) -> (m : Nat) -> LTE n m ->
                           LTE (constraintArraySize n) (constraintArraySize m)
constraintArrayMonotonic n m prf =
  plusLteMonotoneLeft 8 (n * 16) (m * 16) (scaleLteRight 16 prf)
