-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-4 proof: SEALING THE ABI<->FFI SEAM for iseriser.
|||
||| The ABI defines `resultToInt : Result -> Bits32`, the integer the Zig FFI
||| returns to C. The estate's structural gate (`scripts/abi-ffi-gate.py`)
||| checks the Idris and Zig enums agree by name+value. THIS module supplies
||| the PROOF-SIDE guarantee that the encoding is SOUND:
|||
|||   * `intToResult`         — a decoder Bits32 -> Maybe Result
|||   * `resultRoundTrip`     — the encoding is faithful/lossless: decoding an
|||                             encoded result recovers exactly that result
|||   * `resultToIntInjective`— distinct ABI outcomes never collide on the wire,
|||                             DERIVED from the round-trip via cong + justInjective
|||
||| Plus positive controls (concrete decodes by Refl) and a machine-checked
||| NON-VACUITY control (two distinct codes have distinct ints).

module Iseriser.ABI.FfiSeam

import Iseriser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Decoder: the inverse of resultToInt
--------------------------------------------------------------------------------

||| Decode a C integer back to a `Result`. Built with boolean `==` on Bits32
||| literals (which reduces on concrete constants) so the round-trip `Refl`s
||| check definitionally. Any value outside 0..5 is not a valid ABI code.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidLanguage
  else if x == 3 then Just TemplateError
  else if x == 4 then Just OutputError
  else if x == 5 then Just NullPointer
  else Nothing

--------------------------------------------------------------------------------
-- Faithfulness: the encoding is lossless (round-trips through the wire)
--------------------------------------------------------------------------------

||| Decoding the encoding of any `Result` recovers exactly that `Result`.
||| Each clause reduces because `resultToInt` produces a concrete Bits32
||| literal and the decoder's boolean `==` chain evaluates on that literal.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidLanguage = Refl
resultRoundTrip TemplateError = Refl
resultRoundTrip OutputError = Refl
resultRoundTrip NullPointer = Refl

--------------------------------------------------------------------------------
-- Injectivity: distinct ABI outcomes never collide on the wire
--------------------------------------------------------------------------------

||| `Just` is injective: recover the underlying equality from wrapped values.
||| (Local helper to avoid depending on a Prelude name that may not be in
||| scope; the off-diagonal `Just x = Nothing` cannot arise here.)
justEq : {0 x, y : Result} -> Just x = Just y -> x = y
justEq Refl = Refl

||| The encoding is unambiguous: if two results encode to the same integer,
||| they ARE the same result. Derived from the round-trip — applying the
||| decoder to both sides of `resultToInt a = resultToInt b` and chaining the
||| two round-trip facts forces `Just a = Just b`, hence `a = b`.
public export
resultToIntInjective : (a, b : Result) ->
                       resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justEq $
    trans (sym (resultRoundTrip a))
          (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes by Refl)
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding 5 yields NullPointer (the highest valid code).
decodeFiveIsNullPointer : intToResult 5 = Just NullPointer
decodeFiveIsNullPointer = Refl

||| An out-of-range code decodes to Nothing.
decodeSixIsNothing : intToResult 6 = Nothing
decodeSixIsNothing = Refl

||| Concrete round-trip control through the middle of the range.
roundTripTemplateError : intToResult (resultToInt TemplateError) = Just TemplateError
roundTripTemplateError = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (machine-checked)
--------------------------------------------------------------------------------

||| Distinct primitive Bits32 literals are provably unequal: the coverage
||| checker discharges `Refl impossible` for `0 = 1`.
okIntNotErrorInt : Not (the Bits32 0 = the Bits32 1)
okIntNotErrorInt = \case Refl impossible

||| NON-VACUITY: two DISTINCT result codes have DISTINCT wire integers.
||| `resultToInt Ok = 0` and `resultToInt Error = 1` reduce, so any proof
||| that they are equal would prove `0 = 1`, which is refuted above. This
||| guarantees `resultToIntInjective` is not vacuously true.
public export
okEncodingNotErrorEncoding : Not (resultToInt Ok = resultToInt Error)
okEncodingNotErrorEncoding prf = okIntNotErrorInt prf
