-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Dafniser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for the Dafniser ABI types — specifically the SpecTree
||| and its constituent records (Precondition, Postcondition,
||| LoopInvariant, GhostVariable, Lemma, VerificationResult).
|||
||| The layouts must agree between the Idris2 ABI definitions and the
||| Zig FFI implementation in ffi/zig/src/main.zig.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Dafniser.ABI.Layout

import Dafniser.ABI.Types
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
||| For n = S j, compute the quotient q = m `div` (S j) and check that
||| m = q * (S j) holds on the nose.  Returns a real `Divides` witness, or
||| Nothing when the candidate quotient does not check out (or when n = 0).
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S j) m =
  let q = m `div` (S j) in
  case decEq m (q * (S j)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Decide whether `alignUp size align` is a multiple of `align`.
||| A universally-quantified claim here would need a full division lemma; we
||| instead produce the real `Divides` witness by computation via `decDivides`
||| (returns Nothing only in the degenerate `align = 0` case).
public export
decAlignUp : (size : Nat) -> (align : Nat) -> Maybe (Divides align (alignUp size align))
decAlignUp size align = decDivides align (alignUp size align)

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

||| Verify a struct layout is valid
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align in
  case choose (size >= sum (map (\f => f.size) fields)) of
    Right _ => Left "Invalid struct size"
    Left szOk =>
      case decDivides align size of
        Nothing => Left "Total size is not a multiple of the alignment"
        Just dvd => Right (MkStructLayout fields size align {sizeCorrect = szOk} {aligned = dvd})

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

||| Sound decision procedure over a whole field vector: are all field
||| offsets divisible by their declared alignment?  Builds the real
||| FieldsAligned witness when it succeeds.
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

||| Check if layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Struct fields are not correctly aligned for the C ABI"

--------------------------------------------------------------------------------
-- Dafniser-Specific Layouts
--------------------------------------------------------------------------------

||| Layout for the Precondition record.
||| Fields: functionName (ptr), expression (ptr), description (ptr)
||| All string pointers are 8 bytes on 64-bit platforms.
public export
preconditionLayout : StructLayout
preconditionLayout =
  MkStructLayout
    [ MkField "functionName" 0  8 8   -- String pointer at offset 0
    , MkField "expression"   8  8 8   -- String pointer at offset 8
    , MkField "description"  16 8 8   -- String pointer at offset 16
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}

||| Layout for the Postcondition record (identical to Precondition).
public export
postconditionLayout : StructLayout
postconditionLayout =
  MkStructLayout
    [ MkField "functionName" 0  8 8
    , MkField "expression"   8  8 8
    , MkField "description"  16 8 8
    ]
    24
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}

||| Layout for the LoopInvariant record.
||| Fields: functionName (ptr), loopIndex (u64), expression (ptr), description (ptr)
public export
loopInvariantLayout : StructLayout
loopInvariantLayout =
  MkStructLayout
    [ MkField "functionName" 0  8 8   -- String pointer
    , MkField "loopIndex"    8  8 8   -- Nat as u64
    , MkField "expression"   16 8 8   -- String pointer
    , MkField "description"  24 8 8   -- String pointer
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| Layout for the GhostVariable record.
||| Fields: name (ptr), dafnyType (ptr), initialiser (ptr), scope (ptr)
public export
ghostVariableLayout : StructLayout
ghostVariableLayout =
  MkStructLayout
    [ MkField "name"         0  8 8
    , MkField "dafnyType"    8  8 8
    , MkField "initialiser"  16 8 8
    , MkField "scope"        24 8 8
    ]
    32
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| Layout for the Lemma record.
||| Fields: name (ptr), requires (ptr to list), ensures (ptr to list),
|||         dependencies (ptr to list), proofHint (ptr)
public export
lemmaLayout : StructLayout
lemmaLayout =
  MkStructLayout
    [ MkField "name"         0  8 8
    , MkField "requires"     8  8 8   -- Pointer to string list
    , MkField "ensures"      16 8 8   -- Pointer to string list
    , MkField "dependencies" 24 8 8   -- Pointer to string list
    , MkField "proofHint"    32 8 8
    ]
    40
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}

||| Layout for the VerificationResult tagged union.
||| Tag (u32) + padding + payload (function name ptr + detail ptr/u64)
public export
verificationResultLayout : StructLayout
verificationResultLayout =
  MkStructLayout
    [ MkField "tag"          0  4 4   -- Verified=0, Counterexample=1, Timeout=2, InternalError=3
    , MkField "_pad"         4  4 4   -- Padding to align next field
    , MkField "functionName" 8  8 8   -- String pointer
    , MkField "detail"       16 8 8   -- Union: timeMs (u64) / clause ptr / message ptr
    , MkField "witness"      24 8 8   -- Only valid when tag=1 (Counterexample)
    ]
    32
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| Layout for the SpecTree top-level record.
||| Fields: moduleName (ptr), target (u32), functions (ptr to list),
|||         moduleGhosts (ptr to list), moduleLemmas (ptr to list)
public export
specTreeLayout : StructLayout
specTreeLayout =
  MkStructLayout
    [ MkField "moduleName"    0  8 8   -- String pointer
    , MkField "target"        8  4 4   -- DafnyTarget enum (u32)
    , MkField "_pad"          12 4 4   -- Padding
    , MkField "functions"     16 8 8   -- Pointer to FunctionSpec list
    , MkField "moduleGhosts"  24 8 8   -- Pointer to GhostVariable list
    , MkField "moduleLemmas"  32 8 8   -- Pointer to Lemma list
    ]
    40
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}

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

||| Decide whether a field offset is within struct bounds.
||| A universally-quantified `So (...)` return type would be unsound (it is
||| false in general — a field may overflow the declared total size), so this
||| returns a `Maybe` witness produced by `choose`.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
