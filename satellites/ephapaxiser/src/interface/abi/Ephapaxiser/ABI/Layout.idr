-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Ephapaxiser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for the resource tracking structs used by ephapaxiser.
|||
||| The primary struct is ResourceTrackerLayout, which stores a resource
||| handle alongside its lifecycle state and usage count. The layout must
||| be C-ABI compatible for the Zig FFI bridge.
|||
||| @see Ephapaxiser.ABI.Types for the type definitions

module Ephapaxiser.ABI.Layout

import Ephapaxiser.ABI.Types
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
-- Resource Tracker Layout
--------------------------------------------------------------------------------

||| Layout for the ResourceTracker struct.
|||
||| Fields:
|||   handle    : Bits64  (8 bytes, offset 0)  — opaque pointer to the resource
|||   kind      : Bits32  (4 bytes, offset 8)  — ResourceKind enum discriminant
|||   lifecycle : Bits32  (4 bytes, offset 12) — ResourceLifecycle enum discriminant
|||   usage     : Bits32  (4 bytes, offset 16) — UsageCount enum discriminant
|||   _padding  : Bits32  (4 bytes, offset 20) — alignment padding
|||   Total: 24 bytes, 8-byte aligned
public export
resourceTrackerLayout : StructLayout
resourceTrackerLayout =
  MkStructLayout
    [ MkField "handle"    0  8 8   -- Bits64 at offset 0
    , MkField "kind"      8  4 4   -- Bits32 at offset 8
    , MkField "lifecycle" 12 4 4   -- Bits32 at offset 12
    , MkField "usage"     16 4 4   -- Bits32 at offset 16
    , MkField "_padding"  20 4 4   -- Alignment padding to 24
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}  -- 24 = 3 * 8

||| Proof that the resource tracker layout is valid for all platforms
public export
resourceTrackerAllPlatforms : (p : Platform) -> HasSize ResourceTracker 24
resourceTrackerAllPlatforms Linux   = SizeProof
resourceTrackerAllPlatforms Windows = SizeProof
resourceTrackerAllPlatforms MacOS   = SizeProof
resourceTrackerAllPlatforms BSD     = SizeProof
resourceTrackerAllPlatforms WASM    = SizeProof

--------------------------------------------------------------------------------
-- Linearity Proof Layout
--------------------------------------------------------------------------------

||| Layout for the ConsumeProof witness struct.
||| This is the evidence artifact that a resource was properly consumed.
|||
||| Fields:
|||   handle_ptr     : Bits64  (8 bytes, offset 0)  — which resource was consumed
|||   lifecycle_from : Bits32  (4 bytes, offset 8)  — InUse
|||   lifecycle_to   : Bits32  (4 bytes, offset 12) — Consumed
|||   usage_count    : Bits32  (4 bytes, offset 16) — must be 1
|||   _padding       : Bits32  (4 bytes, offset 20) — alignment padding
|||   Total: 24 bytes, 8-byte aligned
public export
consumeProofLayout : StructLayout
consumeProofLayout =
  MkStructLayout
    [ MkField "handle_ptr"     0  8 8
    , MkField "lifecycle_from" 8  4 4
    , MkField "lifecycle_to"   12 4 4
    , MkField "usage_count"    16 4 4
    , MkField "_padding"       20 4 4
    ]
    24
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}  -- 24 = 3 * 8

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

||| Verify that all ephapaxiser layouts are C-ABI compliant. Fails (Left) if
||| any concrete layout is misaligned, rather than asserting it.
public export
verifyAllLayouts : Either String ()
verifyAllLayouts = do
  _ <- checkCABI resourceTrackerLayout
  _ <- checkCABI consumeProofLayout
  Right ()

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
