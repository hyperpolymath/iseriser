-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — Sealing the ABI<->FFI seam for Eclexiaiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris
||| `Result` enum and the Zig FFI enum agree by name and value. THIS module is
||| the proof-side counterpart: it shows the on-the-wire encoding
||| `resultToInt : Result -> Bits32` is SOUND.
|||
||| Soundness here means two things:
|||   1. FAITHFUL / LOSSLESS — there is a decoder `intToResult` such that
||| every ABI outcome round-trips through the C integer back to itself
||| (`resultRoundTrip`).
|||   2. UNAMBIGUOUS / INJECTIVE — distinct ABI outcomes never collide on the
||| wire (`resultToIntInjective`), DERIVED from the round-trip so the two
||| facts cannot drift apart.
|||
||| Genuine proof only: no believe_me / idris_crash / assert_total / postulate /
||| sorry. Every claim is machine-checked by the totality + coverage checker.
|||
||| @see Eclexiaiser.ABI.Types for the `Result` enum and `resultToInt`.

module Eclexiaiser.ABI.FfiSeam

import Eclexiaiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Decoder: C integer -> ABI Result
--------------------------------------------------------------------------------

||| Decode a C integer (as produced by the Zig FFI) back into an ABI `Result`.
||| Unknown codes decode to `Nothing` — the wire format is closed.
|||
||| Built with concrete `==` tests on primitive `Bits32` literals: these reduce
||| definitionally on concrete constants, so the round-trip proofs below check
||| by `Refl`.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just BudgetExceeded
  else if x == 6 then Just CarbonLimitExceeded
  else if x == 7 then Just CounterUnavailable
  else Nothing

--------------------------------------------------------------------------------
-- (b) Faithful / lossless encoding: the round-trip law
--------------------------------------------------------------------------------

||| FAITHFULNESS: encoding a `Result` to its C integer and decoding it back
||| recovers exactly the original outcome. Nothing is lost across the seam.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip BudgetExceeded = Refl
resultRoundTrip CarbonLimitExceeded = Refl
resultRoundTrip CounterUnavailable = Refl

--------------------------------------------------------------------------------
-- (a) Unambiguous encoding: injectivity, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| `Just` is injective — local lemma so injectivity is derived cleanly from the
||| round-trip without depending on a particular base-library name.
||| Both arguments are bound explicitly as erased implicits (no auto-bind warn).
private
justInj : {0 a, b : Result} -> Just a = Just b -> a = b
justInj Refl = Refl

||| UNAMBIGUITY: `resultToInt` is injective — distinct ABI outcomes can never
||| collide on the wire. Derived from `resultRoundTrip`: if two results encode
||| to the same integer, decoding that integer gives the same `Just`, and the
||| round-trip law pins each side back to its own constructor.
export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a))
          (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked = Refl)
--------------------------------------------------------------------------------

||| The success code 0 decodes to `Ok`.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| The budget-exceeded code 5 decodes to `BudgetExceeded` (Zig FFI contract).
export
decodeFiveIsBudgetExceeded : intToResult 5 = Just BudgetExceeded
decodeFiveIsBudgetExceeded = Refl

||| The highest defined code 7 decodes to `CounterUnavailable`.
export
decodeSevenIsCounterUnavailable : intToResult 7 = Just CounterUnavailable
decodeSevenIsCounterUnavailable = Refl

||| An out-of-range code decodes to `Nothing` — the wire format is closed.
export
decodeUnknownIsNothing : intToResult 8 = Nothing
decodeUnknownIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| NON-VACUITY: two DISTINCT result codes really do encode to DISTINCT
||| integers. Without this, an encoding mapping everything to 0 would satisfy
||| injectivity vacuously. Machine-checked: 0 = 1 is refuted by the coverage
||| checker on primitive `Bits32` literals.
export
okEncodingDiffersFromError : Not (resultToInt Ok = resultToInt Error)
okEncodingDiffersFromError = \case Refl impossible

||| A second non-vacuity witness on a non-adjacent pair, to pin that the
||| separation is not an artefact of the first two codes.
export
okEncodingDiffersFromCounterUnavailable :
  Not (resultToInt Ok = resultToInt CounterUnavailable)
okEncodingDiffersFromCounterUnavailable = \case Refl impossible
