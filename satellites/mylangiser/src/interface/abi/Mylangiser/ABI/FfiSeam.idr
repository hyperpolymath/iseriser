-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 proof: SEALING the ABI<->FFI SEAM for Mylangiser.
|||
||| The Idris2 ABI (Mylangiser.ABI.Types) defines the FFI result-code enum
||| `Result` and its on-the-wire encoding `resultToInt : Result -> Bits32`
||| (the value the Zig FFI returns to C). A separate STRUCTURAL gate
||| (scripts/abi-ffi-gate.py) checks that the Idris and Zig enums agree by
||| name + value. This module supplies the PROOF-SIDE guarantee that the
||| encoding itself is SOUND:
|||
|||   (a) resultToIntInjective — distinct ABI outcomes never collide on the
|||       wire (the encoding is unambiguous).
|||   (b) intToResult / resultRoundTrip — the C integer faithfully round-trips
|||       back to the ABI value (the encoding is lossless / faithful).
|||   (c) the same injectivity for the other FFI enum encoder in this ABI,
|||       disclosureLevelToInt : DisclosureLevel -> Bits32.
|||
||| Plus positive controls (concrete decode = Refl) and a non-vacuity /
||| negative control (two distinct codes have distinct ints, machine-checked).
|||
||| Genuine proof only: no believe_me / idris_crash / assert_total / postulate.

module Mylangiser.ABI.FfiSeam

import Mylangiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local helper: Just is injective
--------------------------------------------------------------------------------

||| `Just` is injective. Used to turn a round-trip equality `Just a = Just b`
||| into the underlying `a = b`.
private
justInj : {0 a, b : t} -> Just a = Just b -> a = b
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Primitive Bits32 disequality
--------------------------------------------------------------------------------

||| Distinct primitive Bits32 literals are provably unequal: the coverage
||| checker discharges `Refl impossible` for distinct primitive constants.
||| We only need the specific pairs that arise off the diagonal below; each is
||| a self-contained, machine-checked refutation with concrete literals.

--------------------------------------------------------------------------------
-- (b) Faithful decoder + round-trip for Result
--------------------------------------------------------------------------------

||| Decode a C integer back to a Result. Built with boolean Bits32 `==`, which
||| reduces on concrete literals, so the round-trip Refls below check.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just EndpointNotFound
  else if x == 6 then Just InvalidScore
  else Nothing

||| The encoding is lossless: decoding the encoded form recovers the value.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok               = Refl
resultRoundTrip Error            = Refl
resultRoundTrip InvalidParam     = Refl
resultRoundTrip OutOfMemory      = Refl
resultRoundTrip NullPointer      = Refl
resultRoundTrip EndpointNotFound = Refl
resultRoundTrip InvalidScore     = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity of resultToInt, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| The encoding is unambiguous: distinct ABI outcomes never collide on the
||| wire. Derived cleanly from the round-trip via cong + justInj.
|||
||| If resultToInt a = resultToInt b, applying intToResult to both sides gives
|||   intToResult (resultToInt a) = intToResult (resultToInt b)
||| i.e. Just a = Just b by the round-trip on each side, hence a = b.
export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- (c) Injectivity of disclosureLevelToInt (the other FFI enum encoder)
--------------------------------------------------------------------------------

||| Faithful decoder for DisclosureLevel (Beginner=0, Intermediate=1, Expert=2).
public export
intToDisclosureLevel : Bits32 -> Maybe DisclosureLevel
intToDisclosureLevel x =
  if x == 0 then Just Beginner
  else if x == 1 then Just Intermediate
  else if x == 2 then Just Expert
  else Nothing

||| disclosureLevelToInt is lossless.
export
disclosureLevelRoundTrip : (l : DisclosureLevel) ->
  intToDisclosureLevel (disclosureLevelToInt l) = Just l
disclosureLevelRoundTrip Beginner     = Refl
disclosureLevelRoundTrip Intermediate = Refl
disclosureLevelRoundTrip Expert       = Refl

||| disclosureLevelToInt is unambiguous, derived from its round-trip.
export
disclosureLevelToIntInjective : (a, b : DisclosureLevel) ->
  disclosureLevelToInt a = disclosureLevelToInt b -> a = b
disclosureLevelToIntInjective a b prf =
  justInj $
    trans (sym (disclosureLevelRoundTrip a))
          (trans (cong intToDisclosureLevel prf) (disclosureLevelRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decode = Refl)
--------------------------------------------------------------------------------

||| Decoding the encoding of Ok yields Just Ok.
export
decodeOk : intToResult (resultToInt Ok) = Just Ok
decodeOk = Refl

||| Decoding the encoding of InvalidScore (the highest code) yields it back.
export
decodeInvalidScore : intToResult (resultToInt InvalidScore) = Just InvalidScore
decodeInvalidScore = Refl

||| A raw integer not in range decodes to Nothing.
export
decodeUnknown : intToResult 99 = Nothing
decodeUnknown = Refl

||| Concrete disclosure-level decode.
export
decodeExpert : intToDisclosureLevel (disclosureLevelToInt Expert) = Just Expert
decodeExpert = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (distinct codes have distinct ints)
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes encode to DISTINCT integers, so the
||| injectivity theorem is not trivially true. Machine-checked: `resultToInt Ok`
||| reduces to 0 and `resultToInt Error` to 1, and 0 = 1 is impossible.
export
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct Refl impossible

||| Likewise for the disclosure-level encoder.
export
beginnerExpertDistinct : Not (disclosureLevelToInt Beginner = disclosureLevelToInt Expert)
beginnerExpertDistinct Refl impossible
