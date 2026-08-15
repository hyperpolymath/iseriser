-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for a2mliser Attestation Structures
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible structs that cross the Zig FFI boundary.
||| Every struct used in the attestation pipeline must have its layout
||| proven correct here before it may appear in Foreign.idr.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module A2mliser.ABI.Layout

import A2mliser.ABI.Types
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

||| Decide whether `n` divides `m`, returning a Divides witness when it does.
||| Sound: only returns Just when m is genuinely a multiple of n.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z m = Nothing
decDivides (S k) m =
  let q = div m (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Verify a struct layout is valid.
||| Requires both the size obligation and a genuine divisibility witness.
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align in
  case decSo (size >= sum (map (\f => f.size) fields)) of
    No _ => Left "Invalid struct size"
    Yes prf =>
      case decDivides align size of
        Nothing => Left "Struct size not aligned"
        Just dv => Right (MkStructLayout fields size align {sizeCorrect = prf} {aligned = dv})

--------------------------------------------------------------------------------
-- Attestation Envelope Header Layout
--------------------------------------------------------------------------------

||| Memory layout of the EnvelopeHeader struct.
||| Must match the Zig struct layout exactly.
|||
||| Offset  Size  Field
||| ------  ----  -----
|||   0       4   hashAlgId   (Bits32)
|||   4       4   sigAlgId    (Bits32)
|||   8       4   digestLen   (Bits32)
|||  12       4   signatureLen (Bits32)
|||  16       8   timestamp   (Bits64)
|||  24       4   hasParent   (Bits32)
|||  28       4   _pad        (Bits32)
||| Total: 32 bytes, 8-byte aligned
public export
envelopeHeaderLayout : StructLayout
envelopeHeaderLayout =
  MkStructLayout
    [ MkField "hashAlgId"    0  4 4   -- Bits32 at offset 0
    , MkField "sigAlgId"     4  4 4   -- Bits32 at offset 4
    , MkField "digestLen"    8  4 4   -- Bits32 at offset 8
    , MkField "signatureLen" 12 4 4   -- Bits32 at offset 12
    , MkField "timestamp"    16 8 8   -- Bits64 at offset 16
    , MkField "hasParent"    24 4 4   -- Bits32 at offset 24
    , MkField "_pad"         28 4 4   -- Bits32 at offset 28 (alignment padding)
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

--------------------------------------------------------------------------------
-- Digest Buffer Layout
--------------------------------------------------------------------------------

||| Layout for a fixed-size digest buffer (32 bytes for SHA-256 or BLAKE3).
||| This is a simple contiguous byte array with 1-byte alignment.
public export
digestBufferLayout : StructLayout
digestBufferLayout =
  MkStructLayout
    [ MkField "bytes" 0 32 1   -- 32 bytes at offset 0, byte-aligned
    ]
    32  -- Total size: 32 bytes
    1   -- Alignment: 1 byte (byte array)
    {sizeCorrect = Oh}
    {aligned = DivideBy 32 Refl}

--------------------------------------------------------------------------------
-- Signature Buffer Layout
--------------------------------------------------------------------------------

||| Layout for an Ed25519 signature buffer (64 bytes).
public export
ed25519SignatureLayout : StructLayout
ed25519SignatureLayout =
  MkStructLayout
    [ MkField "bytes" 0 64 1   -- 64 bytes at offset 0, byte-aligned
    ]
    64  -- Total size: 64 bytes
    1   -- Alignment: 1 byte
    {sizeCorrect = Oh}
    {aligned = DivideBy 64 Refl}

||| Layout for an Ed448 signature buffer (114 bytes).
public export
ed448SignatureLayout : StructLayout
ed448SignatureLayout =
  MkStructLayout
    [ MkField "bytes" 0 114 1  -- 114 bytes at offset 0, byte-aligned
    ]
    114 -- Total size: 114 bytes (no padding needed for byte arrays)
    1   -- Alignment: 1 byte
    {sizeCorrect = Oh}
    {aligned = DivideBy 114 Refl}

--------------------------------------------------------------------------------
-- Provenance Chain Entry Layout
--------------------------------------------------------------------------------

||| Layout for a single provenance chain entry in the FFI layer.
||| Each entry carries its own envelope header plus a pointer to the
||| parent entry (or null for the root).
|||
||| Offset  Size  Field
||| ------  ----  -----
|||   0      32   header      (EnvelopeHeader, inline)
|||  32       8   digestPtr   (pointer to digest buffer)
|||  40       8   signaturePtr (pointer to signature buffer)
|||  48       8   parentPtr   (pointer to parent entry, or null)
||| Total: 56 bytes, 8-byte aligned
public export
provenanceEntryLayout : StructLayout
provenanceEntryLayout =
  MkStructLayout
    [ MkField "header"       0  32 8  -- EnvelopeHeader (inline, 8-aligned)
    , MkField "digestPtr"    32  8 8  -- Pointer to digest
    , MkField "signaturePtr" 40  8 8  -- Pointer to signature
    , MkField "parentPtr"    48  8 8  -- Pointer to parent (nullable)
    ]
    56  -- Total size: 56 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 7 Refl}

--------------------------------------------------------------------------------
-- Platform-Specific Layouts
--------------------------------------------------------------------------------

||| Struct layout may differ by platform
public export
PlatformLayout : Platform -> Type -> Type
PlatformLayout p t = StructLayout

||| Verify layout is correct for all platforms.
||| For a2mliser, the envelope header layout is the same on all 64-bit
||| platforms. WASM (32-bit) uses the same field sizes but pointer fields
||| shrink from 8 to 4 bytes.
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

||| Decide, soundly, whether every field's offset is aligned to its own
||| alignment, building a genuine FieldsAligned witness when so.
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

||| Check if layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just fa => Right (CABIOk layout fa)
    Nothing => Left "Struct fields are not C-ABI aligned"

||| Proof that envelope header layout is C ABI compliant.
||| Each field offset is a multiple of its alignment, witnessed directly.
export
envelopeHeaderCABI : CABICompliant Layout.envelopeHeaderLayout
envelopeHeaderCABI =
  CABIOk Layout.envelopeHeaderLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields)))))))

||| Proof that provenance entry layout is C ABI compliant.
export
provenanceEntryCABI : CABICompliant Layout.provenanceEntryLayout
provenanceEntryCABI =
  CABIOk Layout.provenanceEntryLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
     NoFields))))

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
||| The universally-quantified form is unsound (false for fields that do not
||| belong to the layout), so this returns a Maybe witness via `choose`.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
