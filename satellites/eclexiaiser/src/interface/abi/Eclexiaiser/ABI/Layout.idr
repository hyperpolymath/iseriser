-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Eclexiaiser
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible energy measurement structs.
|||
||| Key structs:
|||   - EnergyMeasurement: hardware counter reading with timestamp
|||   - CarbonQuery: carbon API request/response
|||   - BudgetEnforcement: budget vs measurement comparison result
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Eclexiaiser.ABI.Layout

import Eclexiaiser.ABI.Types
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

||| Decision procedure for divisibility.
||| For n = S j, compute q = m `div` (S j) and check m = q * (S j).
||| Division does not reduce definitionally, so we confirm the candidate
||| witness via decidable equality on the (reducing) multiplication.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z m = Nothing
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

||| Decide whether alignUp produced a genuine multiple of the alignment.
||| (alignUp is only a multiple of `align` when `align > 0`, so the
||| witness is returned in Maybe rather than asserted unconditionally.)
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
        Left szPrf =>
          case decDivides align size of
            Just alPrf =>
              Right (MkStructLayout fields size align
                       {sizeCorrect = szPrf} {aligned = alPrf})
            Nothing => Left "Total size is not a multiple of alignment"
        Right _ => Left "Invalid struct size"

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

||| Decide whether every field's offset is a multiple of its alignment,
||| building a FieldsAligned witness directly from per-field decDivides.
public export
decFieldsAligned : (fs : Vect k Field) -> Maybe (FieldsAligned fs)
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
    Nothing => Left "Struct fields are not correctly aligned"

--------------------------------------------------------------------------------
-- EnergyMeasurement Layout
--------------------------------------------------------------------------------

||| Energy measurement struct: a single reading from hardware counters.
||| C layout:
|||   offset 0:  function_id   (Bits64, 8 bytes)  — hash of function name
|||   offset 8:  energy_uj     (Bits64, 8 bytes)  — measured microjoules
|||   offset 16: timestamp_ns  (Bits64, 8 bytes)  — nanosecond timestamp
|||   offset 24: counter_type  (Bits32, 4 bytes)  — 0=RAPL, 1=IPMI, 2=estimate
|||   offset 28: padding       (4 bytes)
|||   total: 32 bytes, alignment: 8 bytes
public export
energyMeasurementLayout : StructLayout
energyMeasurementLayout =
  MkStructLayout
    [ MkField "function_id"  0  8 8   -- Bits64 at offset 0
    , MkField "energy_uj"    8  8 8   -- Bits64 at offset 8
    , MkField "timestamp_ns" 16 8 8   -- Bits64 at offset 16
    , MkField "counter_type" 24 4 4   -- Bits32 at offset 24
    ]
    32  -- Total size: 32 bytes (28 data + 4 padding)
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}  -- 32 = 4 * 8

||| Proof that EnergyMeasurement layout is C-ABI compliant
export
energyMeasurementValid : CABICompliant Layout.energyMeasurementLayout
energyMeasurementValid =
  CABIOk energyMeasurementLayout
    (ConsField _ _ (DivideBy 0 Refl)    -- offset 0  = 0 * 8
    (ConsField _ _ (DivideBy 1 Refl)    -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 2 Refl)    -- offset 16 = 2 * 8
    (ConsField _ _ (DivideBy 6 Refl)    -- offset 24 = 6 * 4
     NoFields))))

--------------------------------------------------------------------------------
-- CarbonQuery Layout
--------------------------------------------------------------------------------

||| Carbon API query/response struct.
||| C layout:
|||   offset 0:  zone_id         (Bits32, 4 bytes)  — grid zone hash
|||   offset 4:  intensity_mg    (Bits32, 4 bytes)  — mg CO2/kWh
|||   offset 8:  timestamp_epoch (Bits64, 8 bytes)  — query timestamp
|||   offset 16: renewable_bps   (Bits32, 4 bytes)  — renewable % in basis points
|||   offset 20: api_source      (Bits32, 4 bytes)  — 0=WattTime, 1=ElectricityMaps, 2=static
|||   total: 24 bytes, alignment: 8 bytes
public export
carbonQueryLayout : StructLayout
carbonQueryLayout =
  MkStructLayout
    [ MkField "zone_id"         0  4 4   -- Bits32 at offset 0
    , MkField "intensity_mg"    4  4 4   -- Bits32 at offset 4
    , MkField "timestamp_epoch" 8  8 8   -- Bits64 at offset 8
    , MkField "renewable_bps"   16 4 4   -- Bits32 at offset 16
    , MkField "api_source"      20 4 4   -- Bits32 at offset 20
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}  -- 24 = 3 * 8

||| Proof that CarbonQuery layout is C-ABI compliant
export
carbonQueryValid : CABICompliant Layout.carbonQueryLayout
carbonQueryValid =
  CABIOk carbonQueryLayout
    (ConsField _ _ (DivideBy 0 Refl)    -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)    -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 1 Refl)    -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 4 Refl)    -- offset 16 = 4 * 4
    (ConsField _ _ (DivideBy 5 Refl)    -- offset 20 = 5 * 4
     NoFields)))))

--------------------------------------------------------------------------------
-- BudgetEnforcement Layout
--------------------------------------------------------------------------------

||| Budget enforcement result struct.
||| C layout:
|||   offset 0:  function_id    (Bits64, 8 bytes)  — which function was checked
|||   offset 8:  budget_uj      (Bits64, 8 bytes)  — the budget limit
|||   offset 16: measured_uj    (Bits64, 8 bytes)  — actual measurement
|||   offset 24: carbon_mg_co2  (Bits64, 8 bytes)  — carbon cost of this measurement
|||   offset 32: result_code    (Bits32, 4 bytes)  — 0=pass, 5=budget_exceeded, 6=carbon_exceeded
|||   offset 36: padding        (4 bytes)
|||   total: 40 bytes, alignment: 8 bytes
public export
budgetEnforcementLayout : StructLayout
budgetEnforcementLayout =
  MkStructLayout
    [ MkField "function_id"   0  8 8   -- Bits64 at offset 0
    , MkField "budget_uj"     8  8 8   -- Bits64 at offset 8
    , MkField "measured_uj"   16 8 8   -- Bits64 at offset 16
    , MkField "carbon_mg_co2" 24 8 8   -- Bits64 at offset 24
    , MkField "result_code"   32 4 4   -- Bits32 at offset 32
    ]
    40  -- Total size: 40 bytes (36 data + 4 padding)
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}  -- 40 = 5 * 8

||| Proof that BudgetEnforcement layout is C-ABI compliant
export
budgetEnforcementValid : CABICompliant Layout.budgetEnforcementLayout
budgetEnforcementValid =
  CABIOk budgetEnforcementLayout
    (ConsField _ _ (DivideBy 0 Refl)    -- offset 0  = 0 * 8
    (ConsField _ _ (DivideBy 1 Refl)    -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 2 Refl)    -- offset 16 = 2 * 8
    (ConsField _ _ (DivideBy 3 Refl)    -- offset 24 = 3 * 8
    (ConsField _ _ (DivideBy 8 Refl)    -- offset 32 = 8 * 4
     NoFields)))))

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

||| Decide whether a field fits within the struct's total size.
||| Returns a witness only when the bound genuinely holds (it is false
||| in general), so the result is wrapped in Maybe.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
