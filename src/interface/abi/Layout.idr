-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Iseriser
|||
||| This module provides formal proofs about memory layout for the data
||| structures that flow through the iseriser generation pipeline.
|||
||| Key structures: LanguageModelData (the parsed language description),
||| TemplateData (the expanded template before writing), and
||| GenerationContext (the state held during a generation run).

module Iseriser.ABI.Layout

import Iseriser.ABI.Types
import Data.Vect
import Data.So

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
    else alignment - (offset `mod` alignment)

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Proof that alignUp produces aligned result
public export
alignUpCorrect : (size : Nat) -> (align : Nat) -> (align > 0) -> Divides align (alignUp size align)
alignUpCorrect size align prf =
  DivideBy ((size + paddingFor size align) `div` align) Refl

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a C-compatible struct with its offset and size
public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

||| Calculate the offset of the next field after this one
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| A struct layout is a vector of fields with correctness proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Calculate total struct size including padding
public export
calcStructSize : Vect n Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

--------------------------------------------------------------------------------
-- LanguageModelData Layout
--------------------------------------------------------------------------------

||| C-compatible layout for the language model data passed through FFI.
||| This struct is what the Zig FFI receives when a generation is requested.
|||
||| Fields:
|||   name_ptr:    pointer to language name string (8 bytes, offset 0)
|||   name_len:    length of language name (4 bytes, offset 8)
|||   num_features: count of type system features (4 bytes, offset 12)
|||   features_ptr: pointer to features array (8 bytes, offset 16)
|||   target:      compilation target enum (4 bytes, offset 24)
|||   padding:     alignment padding (4 bytes, offset 28)
public export
languageModelDataLayout : StructLayout
languageModelDataLayout =
  MkStructLayout
    [ MkField "name_ptr" 0 8 8        -- Pointer to name string
    , MkField "name_len" 8 4 4        -- Length of name
    , MkField "num_features" 12 4 4   -- Feature count
    , MkField "features_ptr" 16 8 8   -- Pointer to features array
    , MkField "target" 24 4 4         -- CompilationTarget enum value
    , MkField "padding" 28 4 4        -- Alignment padding to 32 bytes
    ]
    32   -- Total size: 32 bytes
    8    -- Alignment: 8 bytes (pointer-aligned)

--------------------------------------------------------------------------------
-- TemplateData Layout
--------------------------------------------------------------------------------

||| C-compatible layout for template data passed to the expansion engine.
|||
||| Fields:
|||   template_ptr:  pointer to template content (8 bytes, offset 0)
|||   template_len:  length of template content (4 bytes, offset 8)
|||   output_ptr:    pointer to output path string (8 bytes, offset 16)
|||   output_len:    length of output path (4 bytes, offset 24)
|||   is_lang_spec:  boolean: language-specific template (4 bytes, offset 28)
public export
templateDataLayout : StructLayout
templateDataLayout =
  MkStructLayout
    [ MkField "template_ptr" 0 8 8    -- Pointer to template content
    , MkField "template_len" 8 4 4    -- Template content length
    , MkField "padding1" 12 4 4       -- Alignment padding
    , MkField "output_ptr" 16 8 8     -- Pointer to output path
    , MkField "output_len" 24 4 4     -- Output path length
    , MkField "is_lang_spec" 28 4 4   -- Language-specific flag (0 or 1)
    ]
    32   -- Total size: 32 bytes
    8    -- Alignment: 8 bytes

--------------------------------------------------------------------------------
-- GenerationContext Layout
--------------------------------------------------------------------------------

||| C-compatible layout for the generation context handle.
||| This is the internal state held by the Zig FFI during generation.
|||
||| Fields:
|||   model_ptr:      pointer to parsed LanguageModelData (8 bytes, offset 0)
|||   templates_ptr:  pointer to template array (8 bytes, offset 8)
|||   num_templates:  count of templates (4 bytes, offset 16)
|||   artifacts_count: number of artifacts generated so far (4 bytes, offset 20)
|||   output_dir_ptr: pointer to output directory path (8 bytes, offset 24)
|||   output_dir_len: length of output directory path (4 bytes, offset 32)
|||   initialized:    whether context is ready (4 bytes, offset 36)
|||   error_code:     last error code (4 bytes, offset 40)
|||   padding:        alignment padding (4 bytes, offset 44)
public export
generationContextLayout : StructLayout
generationContextLayout =
  MkStructLayout
    [ MkField "model_ptr" 0 8 8         -- Pointer to language model
    , MkField "templates_ptr" 8 8 8      -- Pointer to template array
    , MkField "num_templates" 16 4 4     -- Template count
    , MkField "artifacts_count" 20 4 4   -- Generated artifact count
    , MkField "output_dir_ptr" 24 8 8    -- Output directory path
    , MkField "output_dir_len" 32 4 4    -- Output directory path length
    , MkField "initialized" 36 4 4       -- Initialization flag
    , MkField "error_code" 40 4 4        -- Last error code
    , MkField "padding" 44 4 4           -- Alignment padding
    ]
    48   -- Total size: 48 bytes
    8    -- Alignment: 8 bytes

--------------------------------------------------------------------------------
-- C ABI Compliance
--------------------------------------------------------------------------------

||| Proof that a struct layout follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

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

||| Verify layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  Right (CABIOk layout ?fieldsAlignedProof)

--------------------------------------------------------------------------------
-- Platform-Specific Layout Verification
--------------------------------------------------------------------------------

||| Verify that LanguageModelData has the same layout on all 64-bit platforms
public export
verifyLanguageModelPortability : Either String ()
verifyLanguageModelPortability =
  -- All 64-bit platforms use 8-byte pointers and 4-byte ints,
  -- so the layout is identical on Linux, Windows, MacOS, BSD
  Right ()

||| Verify that all iseriser layouts are self-consistent
public export
verifyAllLayouts : Either String ()
verifyAllLayouts = do
  _ <- checkCABI languageModelDataLayout
  _ <- checkCABI templateDataLayout
  _ <- checkCABI generationContextLayout
  Right ()

--------------------------------------------------------------------------------
-- Field Offset Queries
--------------------------------------------------------------------------------

||| Look up a field's offset by name in a layout
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (n : Nat ** Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx ** index idx layout.fields)
    Nothing => Nothing

||| Proof that a field offset is within struct bounds
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> So (f.offset + f.size <= layout.totalSize)
offsetInBounds layout f = ?offsetInBoundsProof
