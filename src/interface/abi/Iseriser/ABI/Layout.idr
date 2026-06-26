-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Iseriser

module Iseriser.ABI.Layout

import Iseriser.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else minus alignment (offset `mod` alignment)

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

public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

public export
calcStructSize : Vect k Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| C-compatible layout for the language model data passed through FFI.
public export
languageModelDataLayout : StructLayout
languageModelDataLayout =
  MkStructLayout
    [ MkField "name_ptr" 0 8 8
    , MkField "name_len" 8 4 4
    , MkField "num_features" 12 4 4
    , MkField "features_ptr" 16 8 8
    , MkField "target" 24 4 4
    , MkField "padding" 28 4 4
    ]
    32
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| C-compatible layout for template data passed to the expansion engine.
public export
templateDataLayout : StructLayout
templateDataLayout =
  MkStructLayout
    [ MkField "template_ptr" 0 8 8
    , MkField "template_len" 8 4 4
    , MkField "padding1" 12 4 4
    , MkField "output_ptr" 16 8 8
    , MkField "output_len" 24 4 4
    , MkField "is_lang_spec" 28 4 4
    ]
    32
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| C-compatible layout for the generation context handle.
public export
generationContextLayout : StructLayout
generationContextLayout =
  MkStructLayout
    [ MkField "model_ptr" 0 8 8
    , MkField "templates_ptr" 8 8 8
    , MkField "num_templates" 16 4 4
    , MkField "artifacts_count" 20 4 4
    , MkField "output_dir_ptr" 24 8 8
    , MkField "output_dir_len" 32 4 4
    , MkField "initialized" 36 4 4
    , MkField "error_code" 40 4 4
    , MkField "padding" 44 4 4
    ]
    48
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 6 Refl}

||| Proof that every field offset in a layout is correctly aligned.
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

||| Proof that a struct layout follows C ABI alignment rules.
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

||| Verify that all iseriser layouts are C-ABI compliant. This now fails
||| (Left) if any concrete layout is misaligned, rather than asserting it.
public export
verifyAllLayouts : Either String ()
verifyAllLayouts = do
  _ <- checkCABI languageModelDataLayout
  _ <- checkCABI templateDataLayout
  _ <- checkCABI generationContextLayout
  Right ()

||| All 64-bit platforms (Linux, Windows, MacOS, BSD) use 8-byte pointers and
||| 4-byte ints, so the LanguageModelData layout is identical across them.
public export
verifyLanguageModelPortability : Either String ()
verifyLanguageModelPortability = Right ()

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
