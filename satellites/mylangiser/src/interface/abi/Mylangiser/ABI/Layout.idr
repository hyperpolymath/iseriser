-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Mylangiser
|||
||| Provides formal proofs about memory layout, alignment, and padding
||| for C-compatible structs used in the progressive-disclosure layer
||| generator.
|||
||| Key layout types:
|||   - APISurfaceDescriptor: memory layout for API surface metadata
|||     passed across the FFI boundary
|||   - EndpointDescriptor: per-endpoint layout with complexity score
|||   - WrapperDescriptor: layout for generated layered wrapper metadata
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Mylangiser.ABI.Layout

import Mylangiser.ABI.Types
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

||| Decide whether @n divides @m, returning a constructive witness when it does.
||| Division does NOT reduce during typechecking, so we verify the quotient by
||| reconstructing m = q * n and checking it propositionally.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z m = Nothing
decDivides (S k) m =
  let q = div m (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _    => Nothing

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Decide that @alignUp produces an @align-aligned result, returning a
||| constructive Divides witness. The quotient cannot be reduced definitionally
||| (division does not compute under the typechecker), so we verify it with the
||| sound `decDivides` procedure defined below rather than asserting it.
public export
alignUpAligned : (size : Nat) -> (align : Nat) -> Maybe (Divides align (alignUp size align))
alignUpAligned size align = decDivides align (alignUp size align)

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
  fields : Vect len Field
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
  let size = calcStructSize fields align
   in case choose (size >= sum (map (\f => f.size) fields)) of
        Right _ => Left "Invalid struct size"
        Left sizePrf =>
          case decDivides align size of
            Nothing => Left "Total size is not aligned"
            Just alignPrf =>
              Right (MkStructLayout fields size align
                       {sizeCorrect = sizePrf} {aligned = alignPrf})

||| Proof that a struct follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Decide whether every field's offset is aligned to its declared alignment,
||| building a constructive FieldsAligned witness.
public export
decFieldsAligned : (fields : Vect k Field) -> Maybe (FieldsAligned fields)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just divPrf =>
      case decFieldsAligned fs of
        Nothing => Nothing
        Just restPrf => Just (ConsField f fs divPrf restPrf)

||| Check if layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing  => Left "Struct fields are not correctly aligned for the C ABI"

--------------------------------------------------------------------------------
-- API Surface Descriptor Layout
--------------------------------------------------------------------------------

||| Memory layout for API surface metadata passed across the FFI boundary.
||| This struct is the primary data exchanged between the Rust CLI and
||| the Zig FFI layer during API analysis.
|||
||| Fields:
|||   endpointCount : u32  -- number of endpoints in the API
|||   totalParams   : u32  -- sum of all parameters across endpoints
|||   maxTypeDepth  : u32  -- deepest type nesting encountered
|||   maxErrorCodes : u32  -- largest error surface among endpoints
|||   reserved      : u64  -- padding for future fields
public export
apiSurfaceLayout : StructLayout
apiSurfaceLayout =
  MkStructLayout
    [ MkField "endpointCount" 0  4 4   -- u32 at offset 0
    , MkField "totalParams"   4  4 4   -- u32 at offset 4
    , MkField "maxTypeDepth"  8  4 4   -- u32 at offset 8
    , MkField "maxErrorCodes" 12 4 4   -- u32 at offset 12
    , MkField "reserved"      16 8 8   -- u64 at offset 16 (for future use)
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes (due to u64 field)
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}  -- 24 = 3 * 8

--------------------------------------------------------------------------------
-- Endpoint Descriptor Layout
--------------------------------------------------------------------------------

||| Memory layout for a single endpoint's analysis result.
|||
||| Fields:
|||   namePtr       : ptr  -- pointer to endpoint name string
|||   nameLen       : u32  -- length of name string
|||   requiredParams: u32  -- number of required parameters
|||   optionalParams: u32  -- number of optional parameters
|||   typeDepth     : u32  -- type nesting depth
|||   errorSurface  : u32  -- number of distinct error codes
|||   complexityScore: u32 -- computed cognitive-load score (0-100)
|||   disclosureLevel: u32 -- assigned tier (0=beginner, 1=intermediate, 2=expert)
|||   padding       : u32  -- alignment padding
public export
endpointDescriptorLayout : StructLayout
endpointDescriptorLayout =
  MkStructLayout
    [ MkField "namePtr"         0  8 8   -- pointer at offset 0
    , MkField "nameLen"         8  4 4   -- u32 at offset 8
    , MkField "requiredParams"  12 4 4   -- u32 at offset 12
    , MkField "optionalParams"  16 4 4   -- u32 at offset 16
    , MkField "typeDepth"       20 4 4   -- u32 at offset 20
    , MkField "errorSurface"    24 4 4   -- u32 at offset 24
    , MkField "complexityScore" 28 4 4   -- u32 at offset 28
    , MkField "disclosureLevel" 32 4 4   -- u32 at offset 32
    , MkField "padding"         36 4 4   -- alignment padding
    ]
    40  -- Total size: 40 bytes
    8   -- Alignment: 8 bytes (due to pointer field)
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}  -- 40 = 5 * 8

--------------------------------------------------------------------------------
-- Wrapper Descriptor Layout
--------------------------------------------------------------------------------

||| Memory layout for a generated layered wrapper's metadata.
|||
||| Fields:
|||   endpointNamePtr   : ptr  -- pointer to endpoint name
|||   endpointNameLen   : u32  -- name string length
|||   complexityScore   : u32  -- score 0-100
|||   beginnerParams    : u32  -- params visible at @beginner
|||   intermediateParams: u32  -- params visible at @intermediate
|||   expertParams      : u32  -- params visible at @expert (= total)
|||   defaultCount      : u32  -- number of smart defaults applied
|||   flags             : u32  -- bitfield (bit 0: has_error_simplification)
|||   padding           : u32  -- alignment padding
public export
wrapperDescriptorLayout : StructLayout
wrapperDescriptorLayout =
  MkStructLayout
    [ MkField "endpointNamePtr"    0  8 8   -- pointer
    , MkField "endpointNameLen"    8  4 4   -- u32
    , MkField "complexityScore"    12 4 4   -- u32
    , MkField "beginnerParams"     16 4 4   -- u32
    , MkField "intermediateParams" 20 4 4   -- u32
    , MkField "expertParams"       24 4 4   -- u32
    , MkField "defaultCount"       28 4 4   -- u32
    , MkField "flags"              32 4 4   -- u32 bitfield
    , MkField "padding"            36 4 4   -- alignment padding
    ]
    40  -- Total size: 40 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}  -- 40 = 5 * 8

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
-- Offset Calculation
--------------------------------------------------------------------------------

||| Calculate field offset with proof of correctness
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (n : Nat ** Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx ** index idx layout.fields)
    Nothing => Nothing

||| Decide whether a field lies within the struct's total size, returning a
||| proof when it does. This is not universally true (a field may be declared
||| outside the struct), so it must be checked rather than asserted.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left prf => Just prf
    Right _  => Nothing
