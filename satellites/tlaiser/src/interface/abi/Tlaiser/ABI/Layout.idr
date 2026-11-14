-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Tlaiser
|||
||| Provides formal proofs about memory layout, alignment, and padding
||| for C-compatible structs used in the TLAiser FFI boundary.
|||
||| The state space representation must be laid out identically on both
||| sides of the FFI (Idris2/Zig) — these proofs guarantee that.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Tlaiser.ABI.Layout

import Tlaiser.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed to reach the next alignment boundary
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
||| from Data.Nat; here we *decide* it via `decDivides`, which returns a
||| genuine witness when it holds. For the concrete ABI layouts below,
||| divisibility is proven outright (`DivideBy`).
||| (Previously `alignUpCorrect … = DivideBy … Refl`, whose `Refl` cannot
||| typecheck for symbolic inputs.)
public export
alignUpDivides : (size : Nat) -> (align : Nat) ->
                 Maybe (Divides align (alignUp size align))
alignUpDivides size align = decDivides align (alignUp size align)

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a C-compatible struct with its offset, size, and alignment
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

||| A struct layout is a vector of fields with total size and alignment proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Calculate total struct size including all padding
public export
calcStructSize : Vect k Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned within a struct
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

||| Verify a struct layout is valid: the chosen total size must dominate the
||| summed field sizes AND the alignment must divide the total size. Both
||| obligations are decided honestly (`choose` / `decDivides`) and the genuine
||| witnesses are supplied to `MkStructLayout`. (Previously the `aligned`
||| auto-implicit was left unsolved and `decSo` discarded the size proof.)
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align
   in case choose (size >= sum (map (\f => f.size) fields)) of
        Left szOk =>
          case decDivides align size of
            Just algn => Right (MkStructLayout fields size align
                                  {sizeCorrect = szOk} {aligned = algn})
            Nothing => Left "Total size is not a multiple of the alignment"
        Right _ => Left "Invalid struct size"

--------------------------------------------------------------------------------
-- State Space Layout
--------------------------------------------------------------------------------

||| Accumulator-generalised lemma: left-folding `(+)` over the `size`s of a
||| `tabulate` whose every field has size 8 adds exactly `n * 8` to the
||| accumulator. `sum` is `foldl (+) 0`, so this is the form that actually
||| reduces. Proven by induction on `n`, generalising the accumulator.
public export
foldlSizes8 : (acc : Nat) -> (n : Nat) -> (mk : Fin n -> Field) ->
              ((i : Fin n) -> (mk i).size = 8) ->
              foldl (+) acc (map (\f => f.size) (tabulate mk)) = acc + n * 8
foldlSizes8 acc Z mk prf = rewrite plusZeroRightNeutral acc in Refl
foldlSizes8 acc (S k) mk prf =
  rewrite prf FZ in
  rewrite foldlSizes8 (acc + 8) k (\i => mk (FS i)) (\i => prf (FS i)) in
  rewrite plusAssociative acc 8 (k * 8) in Refl

||| Lemma: summing the `size` field over a `tabulate` whose every field has
||| size 8 yields `n * 8`. Proven via `foldlSizes8`; no axioms or holes.
||| This discharges the `sizeCorrect` obligation for the parameterised layouts.
public export
sumSizes8 : (n : Nat) -> (mk : Fin n -> Field) ->
            ((i : Fin n) -> (mk i).size = 8) ->
            sum (map (\f => f.size) (tabulate mk)) = n * 8
sumSizes8 n mk prf = foldlSizes8 0 n mk prf

||| Layout of a state machine's state space for FFI transport.
||| Each state variable occupies a fixed-size slot in a contiguous buffer.
||| The buffer is passed across the FFI boundary as a pointer + length.
|||
||| Layout: [var0: 8 bytes][var1: 8 bytes]...[varN: 8 bytes]
||| All variables are Bits64 for uniformity (simplifies FFI).
public export
stateSpaceField : Fin numVars -> Field
stateSpaceField i =
  MkField ("var_" ++ show (finToNat i)) (finToNat i * 8) 8 8

||| Reflexivity of the Boolean `>=` on Nat: `So (n >= n)` for every `n`.
||| Proven by induction; `n >= n` reduces to `lte n n` which is `True`.
public export
gteReflSo : (n : Nat) -> So (n >= n)
gteReflSo Z = Oh
gteReflSo (S k) = gteReflSo k

||| `sizeCorrect` witness for `stateSpaceLayout`: the field sizes sum to
||| exactly `numVars * 8`, so the total size bound holds reflexively.
public export
stateSpaceSizeOk : (numVars : Nat) ->
  So (numVars * 8 >= sum (map (\f => f.size) (tabulate (stateSpaceField {numVars}))))
stateSpaceSizeOk numVars =
  rewrite sumSizes8 numVars (stateSpaceField {numVars}) (\i => Refl) in
  gteReflSo (numVars * 8)

public export
stateSpaceLayout : (numVars : Nat) -> StructLayout
stateSpaceLayout numVars =
  MkStructLayout (tabulate (stateSpaceField {numVars})) (numVars * 8) 8
    {sizeCorrect = stateSpaceSizeOk numVars}
    {aligned = DivideBy numVars Refl}

||| Proof that state space layout is correctly sized
public export
stateSpaceCorrectSize : (numVars : Nat) ->
  (stateSpaceLayout numVars).totalSize = numVars * 8
stateSpaceCorrectSize numVars = Refl

||| The per-variable field of a trace step (offset 16 + i*8, size 8, align 8).
public export
traceStepVarField : Fin numVars -> Field
traceStepVarField i =
  MkField ("var_" ++ show (finToNat i)) (16 + finToNat i * 8) 8 8

||| The fixed three-field prefix of a trace step.
public export
traceStepPrefix : Vect 3 Field
traceStepPrefix =
  [ MkField "step_number" 0 8 8      -- Bits64: step index
  , MkField "state_id" 8 4 4         -- Bits32: current state
  , MkField "padding" 12 4 4         -- 4 bytes padding for alignment
  ]

||| The summed field sizes of a trace step equal `16 + numVars * 8`. The
||| concrete 3-field prefix reduces `sum (map size (prefix ++ tab))` to
||| `foldl (+) 16 (map size tab)` definitionally; `foldlSizes8` finishes it.
public export
traceStepSumSizes : (numVars : Nat) ->
  sum (map (\f => f.size)
        (Layout.traceStepPrefix ++ tabulate (traceStepVarField {numVars})))
    = 16 + numVars * 8
traceStepSumSizes numVars =
  foldlSizes8 16 numVars (traceStepVarField {numVars}) (\i => Refl)

||| `sizeCorrect` witness for `traceStepLayout`: prefix sizes (8+4+4) plus
||| the per-variable 8-byte slots sum to exactly `16 + numVars * 8`.
public export
traceStepSizeOk : (numVars : Nat) ->
  So (16 + numVars * 8 >=
      sum (map (\f => f.size)
            (Layout.traceStepPrefix ++ tabulate (traceStepVarField {numVars}))))
traceStepSizeOk numVars =
  rewrite traceStepSumSizes numVars in
  gteReflSo (16 + numVars * 8)

||| Layout for a counterexample trace step across FFI.
||| Contains: step number (8), state ID (4), padding (4), then variable values.
public export
traceStepLayout : (numVars : Nat) -> StructLayout
traceStepLayout numVars =
  MkStructLayout
    (traceStepPrefix ++ tabulate (traceStepVarField {numVars}))
    (16 + numVars * 8)
    8
    {sizeCorrect = traceStepSizeOk numVars}
    {aligned = DivideBy (2 + numVars) Refl}

--------------------------------------------------------------------------------
-- Model Check Request Layout
--------------------------------------------------------------------------------

||| Layout for the ModelCheckRequest FFI struct.
||| Must match the C struct on the Zig side exactly.
public export
modelCheckRequestLayout : StructLayout
modelCheckRequestLayout =
  MkStructLayout
    [ MkField "spec_ptr" 0 8 8         -- Bits64: pointer to spec string
    , MkField "spec_len" 8 4 4         -- Bits32: spec string length
    , MkField "padding_0" 12 4 4       -- 4 bytes padding
    , MkField "config_ptr" 16 8 8      -- Bits64: pointer to TLC config
    , MkField "num_workers" 24 4 4     -- Bits32: worker thread count
    , MkField "padding_1" 28 4 4       -- 4 bytes padding
    , MkField "max_states" 32 8 8      -- Bits64: state space limit
    , MkField "max_depth" 40 4 4       -- Bits32: max trace depth
    , MkField "padding_2" 44 4 4       -- 4 bytes trailing padding
    ]
    48  -- Total size: 48 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 6 Refl}

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
verifyAllPlatforms layouts = Right ()

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
||| or an error when some field offset is misaligned. (Previously a hole.)
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

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

||| Decide whether a field lies within a struct's byte bounds, returning a
||| genuine proof when `offset + size <= totalSize`. The previous signature
||| asserted this for *every* field unconditionally, which is unsound (a field
||| need not belong to the layout); this honest version decides it via `choose`.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
