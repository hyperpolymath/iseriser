-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Oblibeniser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible structs used in the reversible computing
||| pipeline — particularly AuditEntry, StateSnapshot, and UndoStack.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Oblibeniser.ABI.Layout

import Oblibeniser.ABI.Types
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

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

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

||| Sound divisibility check for an aligned size. The general theorem
||| "alignUp size align is always divisible by align" needs div/mod lemmas
||| from Data.Nat and is tracked as residual proof work; here we *decide* it
||| via `decDivides`, which returns a genuine witness when it holds. For the
||| concrete ABI layouts below, divisibility is proven outright (`DivideBy`).
||| (Previously `alignUpCorrect … = DivideBy … Refl`, whose `Refl` cannot
||| typecheck for symbolic inputs.)
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

-- `verifyAllLayouts` is defined at the end of this module, after the concrete
-- layouts and `checkCABI` it depends on.

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
-- AuditEntry Layout (oblibeniser-specific)
--------------------------------------------------------------------------------

||| AuditEntry C-ABI layout:
|||   sequenceNo : Bits64 @ offset 0  (8 bytes)
|||   timestamp  : Bits64 @ offset 8  (8 bytes)
|||   prevHash   : Bits64 @ offset 16 (8 bytes)
|||   entryHash  : Bits64 @ offset 24 (8 bytes)
|||   operationId: Bits64 @ offset 32 (8 bytes)
|||   actorPtr   : Bits64 @ offset 40 (8 bytes)
|||   authHash   : Bits64 @ offset 48 (8 bytes)
|||   isForward  : Bits32 @ offset 56 (4 bytes)
|||   _padding   :        @ offset 60 (4 bytes)
|||   Total: 64 bytes, alignment: 8
public export
auditEntryLayout : StructLayout
auditEntryLayout =
  MkStructLayout
    [ MkField "sequenceNo"  0  8 8
    , MkField "timestamp"   8  8 8
    , MkField "prevHash"   16  8 8
    , MkField "entryHash"  24  8 8
    , MkField "operationId" 32  8 8
    , MkField "actorPtr"   40  8 8
    , MkField "authHash"   48  8 8
    , MkField "isForward"  56  4 4
    ]
    64  -- Total size: 64 bytes (with 4 bytes trailing padding)
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 8 Refl}

||| Proof that AuditEntry layout is C-ABI compliant. Each field offset
||| divides its alignment: 0|8, 8|8, 16|8, 24|8, 32|8, 40|8, 48|8, 56|4.
export
auditEntryLayoutValid : CABICompliant Layout.auditEntryLayout
auditEntryLayoutValid =
  CABIOk auditEntryLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 14 Refl)
     NoFields))))))))

--------------------------------------------------------------------------------
-- StateSnapshot Layout (oblibeniser-specific)
--------------------------------------------------------------------------------

||| StateSnapshot C-ABI layout:
|||   snapshotId : Bits64 @ offset 0  (8 bytes)
|||   timestamp  : Bits64 @ offset 8  (8 bytes)
|||   stateHash  : Bits64 @ offset 16 (8 bytes)
|||   stateSize  : Bits32 @ offset 24 (4 bytes)
|||   _padding   :        @ offset 28 (4 bytes)
|||   statePtr   : Bits64 @ offset 32 (8 bytes)
|||   Total: 40 bytes, alignment: 8
public export
stateSnapshotLayout : StructLayout
stateSnapshotLayout =
  MkStructLayout
    [ MkField "snapshotId"  0  8 8
    , MkField "timestamp"   8  8 8
    , MkField "stateHash"  16  8 8
    , MkField "stateSize"  24  4 4
    , MkField "statePtr"   32  8 8
    ]
    40  -- Total size: 40 bytes (with 4 bytes internal padding after stateSize)
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}

||| Proof that StateSnapshot layout is C-ABI compliant. Each field offset
||| divides its alignment: 0|8, 8|8, 16|8, 24|4, 32|8.
export
stateSnapshotLayoutValid : CABICompliant Layout.stateSnapshotLayout
stateSnapshotLayoutValid =
  CABIOk stateSnapshotLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
     NoFields)))))

--------------------------------------------------------------------------------
-- UndoStack Layout (oblibeniser-specific)
--------------------------------------------------------------------------------

||| UndoStack C-ABI layout:
|||   stackPtr : Bits64 @ offset 0  (8 bytes)
|||   depth    : Bits32 @ offset 8  (4 bytes)
|||   maxDepth : Bits32 @ offset 12 (4 bytes)
|||   topHash  : Bits64 @ offset 16 (8 bytes)
|||   Total: 24 bytes, alignment: 8
public export
undoStackLayout : StructLayout
undoStackLayout =
  MkStructLayout
    [ MkField "stackPtr"  0  8 8
    , MkField "depth"     8  4 4
    , MkField "maxDepth" 12  4 4
    , MkField "topHash"  16  8 8
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}

||| Proof that UndoStack layout is C-ABI compliant. Each field offset
||| divides its alignment: 0|8, 8|4, 12|4, 16|8.
export
undoStackLayoutValid : CABICompliant Layout.undoStackLayout
undoStackLayoutValid =
  CABIOk undoStackLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields))))

--------------------------------------------------------------------------------
-- Offset Calculation
--------------------------------------------------------------------------------

||| Look up a field's offset by name in a layout.
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

||| Verify that all oblibeniser concrete layouts are C-ABI compliant. This
||| fails (Left) if any concrete layout is misaligned, rather than asserting
||| it. Each layout's `FieldsAligned` witness is built by `checkCABI`'s sound
||| `decFieldsAligned`.
public export
verifyAllLayouts : Either String ()
verifyAllLayouts = do
  _ <- checkCABI auditEntryLayout
  _ <- checkCABI stateSnapshotLayout
  _ <- checkCABI undoStackLayout
  Right ()
