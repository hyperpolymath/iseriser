-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — Sealing the ABI<->FFI seam for Tlaiser.
|||
||| The estate's structural gate (scripts/abi-ffi-gate.py) checks that the
||| Idris `Result` enum and the Zig FFI enum agree by name+value. This module
||| supplies the PROOF-SIDE guarantee that the wire encoding `resultToInt`
||| is SOUND:
|||
|||   * injective   — distinct ABI outcomes never collide on the wire, so a
|||                   C caller can never confuse two error conditions;
|||   * lossless    — there is a total decoder `intToResultSeam` such that
|||                   every `Result` round-trips faithfully through the C
|||                   integer (encode-then-decode = identity).
|||
||| Injectivity is DERIVED from the round-trip (the cleanest route): the
||| decoder is built with boolean `Bits32` `==` so the round-trip `Refl`s
||| reduce definitionally on each concrete literal, and injectivity then
||| follows from `cong` + `justInjective`.
|||
||| Genuine proof only: no believe_me / idris_crash / assert_total / postulate.
|||
||| @see Tlaiser.ABI.Types for the `Result` enum and `resultToInt` encoder.

module Tlaiser.ABI.FfiSeam

import Tlaiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local lemma: Just is injective
--------------------------------------------------------------------------------

||| `Just` is injective. Proved structurally (single `Refl` clause); no
||| appeal to any unsafe primitive. Used to peel the `Just` off both sides
||| of the round-trip equation when deriving injectivity.
justInjectiveSeam : {0 x, y : a} -> Just x = Just y -> x = y
justInjectiveSeam Refl = Refl

--------------------------------------------------------------------------------
-- Faithful decoder (Bits32 -> Maybe Result)
--------------------------------------------------------------------------------

||| Total decoder from the C wire integer back to a `Result`. Built with
||| boolean `Bits32` equality (`==`) so that each concrete literal branch
||| reduces definitionally — this is what lets the round-trip proofs below
||| close with `Refl`. Unknown codes decode to `Nothing` (the encoding is
||| total but not surjective: only 0..7 are valid).
public export
intToResultSeam : Bits32 -> Maybe Result
intToResultSeam x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just TlcError
  else if x == 6 then Just SpecSyntaxError
  else if x == 7 then Just StateSpaceExhausted
  else Nothing

--------------------------------------------------------------------------------
-- (b) Faithful / lossless encoding: round-trip
--------------------------------------------------------------------------------

||| The encoding is lossless: decoding the C integer produced for any
||| `Result` recovers exactly that `Result`. Each clause closes with `Refl`
||| because `resultToInt` yields a concrete literal and the `==` branches
||| of `intToResultSeam` reduce on it.
export
resultRoundTrip : (r : Result) -> intToResultSeam (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip TlcError = Refl
resultRoundTrip SpecSyntaxError = Refl
resultRoundTrip StateSpaceExhausted = Refl

--------------------------------------------------------------------------------
-- (a) Encoding is unambiguous: injectivity (DERIVED from round-trip)
--------------------------------------------------------------------------------

||| `resultToInt` is injective: distinct ABI outcomes can never collide on
||| the wire. Derived from `resultRoundTrip` via `cong` + `justInjectiveSeam`:
||| if `resultToInt a = resultToInt b`, applying the decoder to both sides
||| gives `Just a = Just b`, hence `a = b`.
export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInjectiveSeam
    (trans (sym (resultRoundTrip a))
           (trans (cong intToResultSeam prf)
                  (resultRoundTrip b)))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked = Refl)
--------------------------------------------------------------------------------

||| Positive control: code 0 decodes to `Ok`.
export
decodeOk : intToResultSeam 0 = Just Ok
decodeOk = Refl

||| Positive control: code 7 decodes to `StateSpaceExhausted` (the highest
||| valid code — guards the upper end of the table).
export
decodeStateSpaceExhausted : intToResultSeam 7 = Just StateSpaceExhausted
decodeStateSpaceExhausted = Refl

||| Positive control: an out-of-range code decodes to `Nothing` (the
||| encoding is not surjective — only 0..7 are valid wire values).
export
decodeUnknownIsNothing : intToResultSeam 8 = Nothing
decodeUnknownIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes have DISTINCT wire integers. This
||| rules out the degenerate world in which every `resultToInt` collapsed to
||| one value (where injectivity would hold vacuously). `resultToInt Ok` is
||| `0` and `resultToInt Error` is `1`; the two primitive `Bits32` literals
||| are provably unequal, discharged by the coverage checker.
export
okNeqErrorOnWire : Not (resultToInt Ok = resultToInt Error)
okNeqErrorOnWire = \case Refl impossible
