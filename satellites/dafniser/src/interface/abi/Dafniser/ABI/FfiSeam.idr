-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — Sealing the ABI<->FFI seam for Dafniser.
|||
||| The structural gate (`scripts/abi-ffi-gate.py`) checks that the Idris2
||| `Result` enum and the Zig FFI enum agree by name and value.  This module
||| provides the PROOF-SIDE guarantee that the on-the-wire encoding is SOUND:
|||
|||   (a) `resultToIntInjective` — distinct ABI outcomes never collide on the
|||       integer wire (the encoding is unambiguous).
|||   (b) `intToResult` + `resultRoundTrip` — the C integer faithfully
|||       round-trips back to the originating ABI value (lossless decoding).
|||
||| Injectivity (a) is DERIVED from the round-trip (b): if `resultToInt a`
||| equals `resultToInt b`, applying the decoder to both sides and rewriting
||| with the round-trip lemma yields `Just a = Just b`, hence `a = b`.
|||
||| Positive controls pin concrete decodes; a machine-checked negative control
||| witnesses non-vacuity (two distinct result codes have distinct integers).
|||
||| No `believe_me`, `idris_crash`, `assert_total`, `postulate`, `sorry`, or
||| `%hint` hacks: this is a genuine, total proof.

module Dafniser.ABI.FfiSeam

import Dafniser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Decoder: integer wire -> ABI Result
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`.
|||
||| Built with boolean `Bits32` equality (`==`) rather than a `case` on
||| literal patterns: `==` on concrete `Bits32` constants reduces
||| definitionally, so the round-trip `Refl`s below check.  Any integer
||| outside the encoded range `[0,4]` decodes to `Nothing`, so the decoder
||| is total and the round-trip is the only way to land on a `Just`.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else Nothing

--------------------------------------------------------------------------------
-- (b) Faithful / lossless encoding: round-trip
--------------------------------------------------------------------------------

||| The encoding is lossless: decoding the integer produced by `resultToInt`
||| recovers exactly the original `Result`.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok           = Refl
resultRoundTrip Error        = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory  = Refl
resultRoundTrip NullPointer  = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity of the encoding, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| `Just` is injective.  Defined locally to keep the dependency surface to
||| `Dafniser.ABI.Types` alone (no extra Prelude/Data imports needed).
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

||| The encoding is unambiguous: if two `Result`s encode to the same integer,
||| they are the same `Result`.  Proof: apply `intToResult` to both sides of
||| the integer equality (`cong`), then rewrite each side with its round-trip
||| (`resultRoundTrip`) to obtain `Just a = Just b`, and conclude by `justInj`.
public export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj (trans (sym (resultRoundTrip a))
                 (trans (cong intToResult prf) (resultRoundTrip b)))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked = Refl)
--------------------------------------------------------------------------------

||| Decoding `0` yields `Ok`.
public export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding `4` yields `NullPointer` (the top of the encoded range).
public export
decodeFourIsNullPointer : intToResult 4 = Just NullPointer
decodeFourIsNullPointer = Refl

||| Any out-of-range integer decodes to `Nothing` (here, `5`).
public export
decodeOutOfRangeIsNothing : intToResult 5 = Nothing
decodeOutOfRangeIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (distinct codes => distinct integers)
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes have DISTINCT integer encodings.
||| If `resultToInt Ok` (= 0) equalled `resultToInt Error` (= 1) the encoding
||| would be collapsing; `0 = 1` on `Bits32` is uninhabited, so the coverage
||| checker discharges the `impossible` branch.  This guarantees the seam is
||| not trivially satisfied by a constant encoder.
public export
okAndErrorDiffer : Not (resultToInt Ok = resultToInt Error)
okAndErrorDiffer prf = case prf of Refl impossible
