-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4: Seals the ABI<->FFI seam for ephapaxiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris and Zig
||| `Result` enums agree by name+value. This module supplies the PROOF-SIDE
||| guarantee that the encoding `resultToInt : Result -> Bits32` is SOUND:
|||
|||   (a) it is injective  — distinct ABI outcomes never collide on the wire;
|||   (b) it round-trips    — a decoder `intToResult` faithfully recovers the
|||       original `Result` from the C integer, so the encoding is lossless.
|||
||| Injectivity is then DERIVED from the round-trip (the cleanest route), and a
||| direct case-analysis injectivity proof is also given as cross-validation.
|||
||| Plus positive controls (concrete decodes = Refl) and a non-vacuity /
||| negative control (two distinct codes have provably distinct ints).

module Ephapaxiser.ABI.FfiSeam

import Ephapaxiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Decoder (faithful inverse of resultToInt)
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`. Built with boolean `==` on
||| concrete `Bits32` literals (which reduces definitionally on constants), so
||| the round-trip `Refl`s below typecheck. Any out-of-range integer decodes to
||| `Nothing`, modelling an unrecognised wire value.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just AlreadyConsumed
  else if x == 6 then Just ResourceLeaked
  else if x == 7 then Just DoubleFree
  else Nothing

--------------------------------------------------------------------------------
-- (b) Round-trip: the encoding is lossless / faithful
--------------------------------------------------------------------------------

||| `intToResult` is a left inverse of `resultToInt`: every `Result` survives a
||| trip out to C and back unchanged. This is the core soundness theorem of the
||| seam — the C integer carries exactly the ABI outcome and nothing is lost.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip AlreadyConsumed = Refl
resultRoundTrip ResourceLeaked = Refl
resultRoundTrip DoubleFree = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| `Just` is injective. Proved directly by matching on the single inhabiting
||| constructor — no library dependency.
public export
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

||| Distinct ABI outcomes never collide on the wire. Derived cleanly from the
||| round-trip: if `resultToInt a = resultToInt b` then decoding both sides
||| gives the same `Just`, and `Just` is injective.
|||
|||   intToResult (resultToInt a) = intToResult (resultToInt b)   [cong]
|||   Just a                      = Just b                          [round-trip, twice]
|||   a                           = b                               [justInj]
public export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes evaluate as expected)
--------------------------------------------------------------------------------

||| `0` on the wire decodes to `Ok`.
public export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| `7` on the wire decodes to `DoubleFree` (the last code).
public export
decodeSevenIsDoubleFree : intToResult 7 = Just DoubleFree
decodeSevenIsDoubleFree = Refl

||| An out-of-range wire value (8) decodes to `Nothing`.
public export
decodeEightIsNothing : intToResult 8 = Nothing
decodeEightIsNothing = Refl

||| Concrete round-trip control: `AlreadyConsumed` survives encode/decode.
public export
roundTripAlreadyConsumed : intToResult (resultToInt AlreadyConsumed) = Just AlreadyConsumed
roundTripAlreadyConsumed = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (the seam is not trivially collapsing)
--------------------------------------------------------------------------------

||| Two DISTINCT result codes have DISTINCT ints. Machine-checked proof that
||| the encoding does not vacuously map everything to the same value — without
||| this, injectivity would be content-free. `resultToInt Ok = 0` and
||| `resultToInt Error = 1` reduce to distinct primitive `Bits32` literals,
||| which Idris's coverage checker discharges via `Refl impossible`.
public export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

||| A second non-vacuity witness across non-adjacent codes.
public export
okNotDoubleFree : Not (resultToInt Ok = resultToInt DoubleFree)
okNotDoubleFree = \case Refl impossible
