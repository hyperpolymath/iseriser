-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-4 proof: SEALING THE ABI<->FFI SEAM for TypedQLiser.
|||
||| The Idris2 ABI (`Typedqliser.ABI.Types`) defines the FFI result-code enum
||| `Result` together with `resultToInt : Result -> Bits32` (the integer the Zig
||| FFI hands back to C), and likewise `ProofStatus` / `statusToInt`. The estate
||| has a STRUCTURAL gate (`scripts/abi-ffi-gate.py`) checking the Idris and Zig
||| enums agree by name+value. THIS module is the PROOF-SIDE guarantee: the
||| encodings are SOUND — distinct ABI outcomes never collide on the wire, and
||| the C integer faithfully round-trips back to the ABI value.
|||
||| Strategy: build total decoders with `if x == n` over boolean `Bits32` `(==)`
||| (which reduces on concrete literals), prove the round-trip lossless by `Refl`,
||| and DERIVE injectivity from the round-trip via `justInj` + `cong`.

module Typedqliser.ABI.FfiSeam

import Typedqliser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local lemma
--------------------------------------------------------------------------------

||| `Just` is injective. Proved locally (no library dependency) so the seam
||| module stands on its own.
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Result: decoder
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`. Total; unrecognised codes -> Nothing.
||| Written with `if … == …` so that the boolean `Bits32` equality reduces on
||| concrete literals and the round-trip `Refl`s below check definitionally.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidQuery
  else if x == 3 then Just SchemaError
  else if x == 4 then Just NullPointer
  else Nothing

--------------------------------------------------------------------------------
-- Result: round-trip (faithful / lossless encoding)
--------------------------------------------------------------------------------

||| The C integer round-trips back to the originating ABI value, for every
||| `Result`. This is the faithfulness of the wire encoding.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok           = Refl
resultRoundTrip Error        = Refl
resultRoundTrip InvalidQuery = Refl
resultRoundTrip SchemaError  = Refl
resultRoundTrip NullPointer  = Refl

--------------------------------------------------------------------------------
-- Result: injectivity (no two outcomes collide on the wire)
--------------------------------------------------------------------------------

||| The encoding is unambiguous: distinct `Result`s map to distinct integers.
||| DERIVED from the round-trip — if `resultToInt a = resultToInt b` then
||| `intToResult` of both sides are equal, i.e. `Just a = Just b`, hence `a = b`.
public export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- ProofStatus: decoder, round-trip, injectivity
--------------------------------------------------------------------------------

||| Decode a C integer back into a `ProofStatus`. Total; unknown -> Nothing.
public export
intToStatus : Bits32 -> Maybe ProofStatus
intToStatus x =
  if x == 0 then Just Proven
  else if x == 1 then Just Refuted
  else if x == 2 then Just Skipped
  else if x == 3 then Just Timeout
  else Nothing

||| The proof-status integer round-trips back to its `ProofStatus`.
public export
statusRoundTrip : (s : ProofStatus) -> intToStatus (statusToInt s) = Just s
statusRoundTrip Proven  = Refl
statusRoundTrip Refuted = Refl
statusRoundTrip Skipped = Refl
statusRoundTrip Timeout = Refl

||| `statusToInt` is injective — distinct proof statuses never collide on the wire.
public export
statusToIntInjective : (a, b : ProofStatus) -> statusToInt a = statusToInt b -> a = b
statusToIntInjective a b prf =
  justInj $
    trans (sym (statusRoundTrip a)) (trans (cong intToStatus prf) (statusRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes reduce to Refl)
--------------------------------------------------------------------------------

||| Decoding the wire value `0` yields `Ok`.
public export
decodeOk : intToResult 0 = Just Ok
decodeOk = Refl

||| Decoding the wire value `4` yields `NullPointer`.
public export
decodeNullPointer : intToResult 4 = Just NullPointer
decodeNullPointer = Refl

||| Decoding an out-of-range wire value yields `Nothing`.
public export
decodeUnknown : intToResult 99 = Nothing
decodeUnknown = Refl

||| Decoding the wire value `0` yields `Proven`.
public export
decodeProven : intToStatus 0 = Just Proven
decodeProven = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls (machine-checked dis-equalities)
--------------------------------------------------------------------------------

||| NON-VACUITY: two DISTINCT result codes encode to DISTINCT integers.
||| `Ok` -> 0 and `Error` -> 1, and the primitive `Bits32` literals `0` and `1`
||| are provably unequal, so the coverage checker discharges `Refl impossible`.
public export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError Refl impossible

||| NON-VACUITY: `SchemaError` (3) and `NullPointer` (4) differ on the wire.
public export
schemaNotNull : Not (resultToInt SchemaError = resultToInt NullPointer)
schemaNotNull Refl impossible

||| NON-VACUITY for `ProofStatus`: `Proven` (0) and `Refuted` (1) differ.
public export
provenNotRefuted : Not (statusToInt Proven = statusToInt Refuted)
provenNotRefuted Refl impossible
