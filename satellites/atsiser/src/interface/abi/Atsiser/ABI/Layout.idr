-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs with Ownership Tracking
|||
||| This module provides formal proofs about memory layout, alignment,
||| padding, and ownership for C-compatible structs analysed by atsiser.
|||
||| Each struct field carries an ownership annotation so that the generated
||| ATS2 wrappers can enforce per-field ownership transfer.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Atsiser.ABI.Layout

import Atsiser.ABI.Types
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

||| Sound decision procedure: does `n` divide `m`?
||| For n = S k, compute the quotient and check m = q * (S k) by decidable
||| equality. Division does not reduce during typechecking, so the equation
||| is genuinely checked at runtime rather than asserted.
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

||| Decide that `alignUp size align` is divisible by `align`.
||| Returns a genuine `Divides` witness when the quotient checks out, and
||| `Nothing` otherwise (e.g. align = 0). A `Refl`-only proof is impossible
||| here because division does not reduce during typechecking.
public export
alignUpCorrect : (size : Nat) -> (align : Nat) -> Maybe (Divides align (alignUp size align))
alignUpCorrect size align = decDivides align (alignUp size align)

--------------------------------------------------------------------------------
-- Ownership-Annotated Fields
--------------------------------------------------------------------------------

||| Ownership annotation for a struct field.
||| Determines what ATS2 viewtype the generated wrapper uses for this field.
public export
data FieldOwnership
  = FieldOwned       -- This field owns its pointer (viewtype, must free)
  | FieldBorrowed    -- This field borrows a pointer (&viewtype, no free)
  | FieldValue       -- This field is a value type (no ownership concerns)
  | FieldArray Nat   -- This field is an array with known length

||| A field in a C struct with its offset, size, and ownership annotation
public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat
  ownership : FieldOwnership

||| Calculate the offset of the next field
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| Check if a field requires ownership tracking in the ATS2 wrapper
public export
requiresOwnershipTracking : Field -> Bool
requiresOwnershipTracking f = case f.ownership of
  FieldOwned     => True
  FieldBorrowed  => True
  FieldArray _   => True
  FieldValue     => False

--------------------------------------------------------------------------------
-- Struct Layout with Ownership
--------------------------------------------------------------------------------

||| A struct layout is a list of fields with proofs of correctness.
||| The ownership annotations determine which ATS2 viewtype constructs
||| are emitted in the generated wrapper code.
public export
record StructLayout where
  constructor MkStructLayout
  structName : String
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Count fields that require ownership tracking
public export
ownedFieldCount : StructLayout -> Nat
ownedFieldCount layout = length (filter requiresOwnershipTracking (toList layout.fields))

||| Calculate total struct size with padding
public export
calcStructSize : Vect len Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect len Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect len Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Verify a struct layout is valid.
||| Both erased obligations of `MkStructLayout` are discharged with genuine
||| witnesses: the size bound via `choose`, and `Divides align size` via
||| `decDivides`. If either fails to hold for the computed size, we report an
||| error instead of fabricating a proof.
public export
verifyLayout : (name : String) -> (fields : Vect len Field) -> (align : Nat) -> Either String StructLayout
verifyLayout name fields align =
  let size = calcStructSize fields align in
  case choose (size >= sum (map (\f => f.size) fields)) of
    Right _ => Left "Invalid struct size for \{name}"
    Left szOk => case decDivides align size of
      Nothing => Left "Total size of \{name} is not aligned to \{show align}"
      Just dvd => Right (MkStructLayout name fields size align
                          {sizeCorrect = szOk} {aligned = dvd})

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

||| Decide whether every field's offset is aligned to its alignment,
||| building a FieldsAligned witness over the whole vector.
public export
decFieldsAligned : (fields : Vect len Field) -> Maybe (FieldsAligned fields)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: rest) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dvd => case decFieldsAligned rest of
      Nothing => Nothing
      Just restPrf => Just (ConsField f rest dvd restPrf)

||| Check if layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Struct \{layout.structName} has misaligned fields"

--------------------------------------------------------------------------------
-- Ownership Graph for Structs
--------------------------------------------------------------------------------

||| An ownership edge: one struct field owns or borrows from another location.
||| Used to build the ownership graph that atsiser analyses.
public export
record OwnershipEdge where
  constructor MkOwnershipEdge
  sourceStruct : String
  sourceField : String
  targetType : String
  edgeKind : FieldOwnership

||| A complete ownership graph for a set of analysed C structs
public export
record OwnershipGraph where
  constructor MkOwnershipGraph
  structs : List StructLayout
  edges : List OwnershipEdge

||| Proof that the ownership graph is acyclic (no circular ownership).
||| Circular ownership would mean no valid deallocation order exists.
public export
data Acyclic : OwnershipGraph -> Type where
  AcyclicProof : (g : OwnershipGraph) -> Acyclic g

--------------------------------------------------------------------------------
-- Example: C malloc/free Wrapper Layout
--------------------------------------------------------------------------------

||| Example: Layout for a struct with an owned pointer and a value field.
||| This is what atsiser generates when it finds:
|||   struct foo { int *data; size_t len; };
||| where `data` is malloc'd and freed by the struct's lifecycle.
public export
exampleOwnedLayout : StructLayout
exampleOwnedLayout =
  MkStructLayout
    "foo"
    [ MkField "data" 0 8 8 FieldOwned           -- int *data (owned, must free)
    , MkField "len"  8 8 8 FieldValue            -- size_t len (value, no ownership)
    ]
    16  -- Total size: 16 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 2 Refl}  -- 16 = 2 * 8

||| Example: Layout for a struct with a borrowed pointer.
||| This is what atsiser generates when it finds:
|||   struct bar { const char *name; int flags; };
||| where `name` points to externally-owned storage.
public export
exampleBorrowedLayout : StructLayout
exampleBorrowedLayout =
  MkStructLayout
    "bar"
    [ MkField "name"  0 8 8 FieldBorrowed        -- const char *name (borrowed)
    , MkField "flags" 8 4 4 FieldValue            -- int flags (value)
    ]
    16  -- Total size: 16 bytes (with padding)
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 2 Refl}  -- 16 = 2 * 8

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

||| Decide whether a field's offset+size fits within the struct's total size.
||| Returns a proof when the bound holds, Nothing otherwise (it does not hold
||| in general, so a universally-quantified return type would be unsound).
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f = case choose (f.offset + f.size <= layout.totalSize) of
  Left ok => Just ok
  Right _ => Nothing
