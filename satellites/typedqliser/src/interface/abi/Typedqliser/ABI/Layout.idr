-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory-layout proofs for the TypedQLiser ABI.
|||
||| The proof certificate descriptor crosses the Zig/C FFI boundary; this module
||| pins its field layout and proves it is C-ABI aligned.

module Typedqliser.ABI.Layout

import Typedqliser.ABI.Types
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
alignUp size alignment = size + paddingFor size alignment

||| `m = k * n` — n divides m.
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Sound divisibility decision: returns a real witness when n divides m.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S k) m =
  let q = m `div` (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect k Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| The proof-certificate descriptor as it crosses the FFI (40 bytes, 8-aligned).
public export
certificateDescLayout : StructLayout
certificateDescLayout =
  MkStructLayout
    [ MkField "query_hash_ptr" 0 8 8
    , MkField "schema_ver_ptr" 8 8 8
    , MkField "max_level" 16 4 4
    , MkField "num_proofs" 20 4 4
    , MkField "proofs_ptr" 24 8 8
    , MkField "result_code" 32 4 4
    , MkField "padding" 36 4 4
    ]
    40
    8
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}

||| Every field offset in a layout is correctly aligned.
public export
data FieldsAligned : Vect len Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect len Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Decide field alignment, building a real witness from per-field divisibility.
public export
decFieldsAligned : (fs : Vect len Field) -> Maybe (FieldsAligned fs)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dvd => case decFieldsAligned fs of
                  Nothing => Nothing
                  Just rest => Just (ConsField f fs dvd rest)

public export
data CABICompliant : StructLayout -> Type where
  CABIOk : (layout : StructLayout) -> FieldsAligned layout.fields -> CABICompliant layout

||| Verify a layout against the C-ABI alignment rules; real proof or error.
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

||| Decide whether a field lies within a struct's byte bounds (honest Maybe;
||| the property is false for an arbitrary field, so it is decided not asserted).
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
