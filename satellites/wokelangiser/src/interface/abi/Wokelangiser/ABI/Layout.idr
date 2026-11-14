-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Wokelangiser
|||
||| Formal proofs about memory layout, alignment, and padding for the
||| consent record, accessibility annotation, and i18n hook structures
||| that cross the FFI boundary.
|||
||| @see Wokelangiser.ABI.Types for type definitions

module Wokelangiser.ABI.Layout

import Wokelangiser.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment. Uses `minus` (Nat subtraction)
||| because `Nat` has no `Neg` instance — `alignment - (...)` did not compile.
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

||| Sound divisibility check for an aligned size. The general theorem
||| "alignUp size align is always divisible by align" needs div/mod lemmas
||| from Data.Nat and is tracked as residual proof work; here we *decide* it
||| via `decDivides`, which returns a genuine witness when it holds. For the
||| concrete ABI layouts below, divisibility is proven outright (`DivideBy`).
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

||| A struct layout is a vector of fields with size and alignment proofs.
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
-- C ABI Compatibility
--------------------------------------------------------------------------------

||| Proof that a struct follows C ABI alignment rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Verify a layout against the C ABI alignment rules, returning a genuine
||| `CABICompliant` proof (built from real per-field divisibility witnesses)
||| or an error when some field offset is misaligned. (Previously a `?hole`.)
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

--------------------------------------------------------------------------------
-- Consent Record Layout
--------------------------------------------------------------------------------

||| Memory layout for a consent record crossing the FFI boundary.
|||
||| C-equivalent struct:
|||   struct ConsentRecord {
|||     uint32_t consent_type;   // 0: OptIn, 1: OptOut, 2: Withdraw, 3: AuditTrail
|||     uint32_t state;          // 0: Pending, 1: Granted, 2: Active, 3: Revoked
|||     uint64_t timestamp;      // Unix epoch seconds (consent event time)
|||     uint64_t subject_id;     // Opaque identifier for the data subject
|||   };
public export
consentRecordLayout : StructLayout
consentRecordLayout =
  MkStructLayout
    [ MkField "consent_type" 0  4 4   -- Bits32 at offset 0
    , MkField "state"        4  4 4   -- Bits32 at offset 4 (no padding)
    , MkField "timestamp"    8  8 8   -- Bits64 at offset 8 (naturally aligned)
    , MkField "subject_id"   16 8 8   -- Bits64 at offset 16
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes (max field alignment)
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}  -- 24 = 3 * 8

--------------------------------------------------------------------------------
-- Accessibility Annotation Layout
--------------------------------------------------------------------------------

||| Memory layout for an accessibility annotation crossing the FFI boundary.
|||
||| C-equivalent struct:
|||   struct AccessibilityRecord {
|||     uint32_t wcag_level;     // 0: A, 1: AA, 2: AAA
|||     uint32_t focus_order;    // Tab order position
|||     uint32_t contrast_ratio; // Ratio * 100 (e.g. 450 = 4.50:1)
|||     uint32_t _padding;       // Alignment padding
|||     uint64_t aria_label_ptr; // Pointer to ARIA label string
|||     uint64_t role_ptr;       // Pointer to role string
|||   };
public export
accessibilityRecordLayout : StructLayout
accessibilityRecordLayout =
  MkStructLayout
    [ MkField "wcag_level"     0  4 4   -- Bits32 at offset 0
    , MkField "focus_order"    4  4 4   -- Bits32 at offset 4
    , MkField "contrast_ratio" 8  4 4   -- Bits32 at offset 8
    , MkField "_padding"       12 4 4   -- Bits32 padding for 8-byte alignment
    , MkField "aria_label_ptr" 16 8 8   -- Bits64 at offset 16
    , MkField "role_ptr"       24 8 8   -- Bits64 at offset 24
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}  -- 32 = 4 * 8

--------------------------------------------------------------------------------
-- I18n Hook Layout
--------------------------------------------------------------------------------

||| Memory layout for an i18n hook record crossing the FFI boundary.
|||
||| C-equivalent struct:
|||   struct I18nRecord {
|||     uint32_t hook_type;      // 0: Locale, 1: RTL, 2: Pluralise, 3: FormatSpec
|||     uint32_t format_kind;    // 0: Date, 1: Number, 2: Currency (if hook_type == 3)
|||     uint64_t locale_tag_ptr; // Pointer to BCP 47 tag string (if hook_type == 0)
|||     uint64_t source_ptr;     // Pointer to source string being localised
|||   };
public export
i18nRecordLayout : StructLayout
i18nRecordLayout =
  MkStructLayout
    [ MkField "hook_type"      0  4 4   -- Bits32 at offset 0
    , MkField "format_kind"    4  4 4   -- Bits32 at offset 4
    , MkField "locale_tag_ptr" 8  8 8   -- Bits64 at offset 8
    , MkField "source_ptr"     16 8 8   -- Bits64 at offset 16
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}  -- 24 = 3 * 8

||| Verify that all wokelangiser layouts are C-ABI compliant. Fails (Left) if
||| any concrete layout is misaligned, rather than asserting it.
public export
verifyAllLayouts : Either String ()
verifyAllLayouts = do
  _ <- checkCABI consentRecordLayout
  _ <- checkCABI accessibilityRecordLayout
  _ <- checkCABI i18nRecordLayout
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
||| asserted this for *every* field unconditionally with a universally
||| quantified `So (...)` return type, which is unsound (false in general);
||| this honest version decides it via `choose`.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
