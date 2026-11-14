-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4: Sealing the ABI <-> FFI seam for atsiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris
||| `Result` enum and the Zig FFI enum agree by name and value. This module
||| supplies the PROOF-SIDE guarantee that the integer encoding `resultToInt`
||| is SOUND:
|||
|||   * Faithfulness (round-trip): a decoder `intToResult` recovers exactly
|||     the `Result` that `resultToInt` produced — the C integer faithfully
|||     round-trips back to the ABI value, losing nothing.
|||   * Injectivity: distinct ABI outcomes never collide on the wire. This is
|||     DERIVED from the round-trip via `justInjective` + `cong`, the cleanest
|||     route, since the round-trip `Refl`s reduce definitionally.
|||
||| Positive controls (concrete decodes = Refl) and a non-vacuity / negative
||| control (two distinct codes have distinct ints, machine-checked) guard
||| against a vacuously-true encoding.

module Atsiser.ABI.FfiSeam

import Atsiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Decoder
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`.
|||
||| Built with boolean `Bits32` `==` chained through `if ... then ... else`,
||| because that form reduces definitionally on concrete literals — so the
||| round-trip `Refl`s below check. Any integer outside the defined range
||| decodes to `Nothing` (no spurious ABI value is fabricated).
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just OwnershipViolation
  else if x == 6 then Just BoundsViolation
  else Nothing

--------------------------------------------------------------------------------
-- Faithfulness: round-trip
--------------------------------------------------------------------------------

||| The encoding is lossless: decoding the encoding of any `Result` returns
||| exactly that `Result`. Each case reduces by `Refl` because the `if`/`==`
||| decoder evaluates on the concrete `Bits32` literal that `resultToInt`
||| emits.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip OwnershipViolation = Refl
resultRoundTrip BoundsViolation = Refl

--------------------------------------------------------------------------------
-- Injectivity (derived from the round-trip)
--------------------------------------------------------------------------------

||| The encoding is injective: distinct ABI outcomes never collide on the
||| wire. If `resultToInt a = resultToInt b`, then decoding both sides yields
||| the same `Just`, and `justInjective` extracts `a = b`.
|||
||| Derivation:
|||   Just a = intToResult (resultToInt a)   -- sym (resultRoundTrip a)
|||          = intToResult (resultToInt b)   -- cong intToResult prf
|||          = Just b                        -- resultRoundTrip b
||| then `Just a = Just b` is inverted to `a = b` (constructors are injective).
public export
resultToIntInjective : (a, b : Result)
                    -> resultToInt a = resultToInt b
                    -> a = b
resultToIntInjective a b prf =
  let justEq : (the (Maybe Result) (Just a) = Just b)
             = trans (sym (resultRoundTrip a))
                     (trans (cong intToResult prf) (resultRoundTrip b))
  in case justEq of Refl => Refl

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes)
--------------------------------------------------------------------------------

||| Concrete decode: integer 0 decodes to success.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Concrete decode: integer 6 decodes to the bounds-violation code.
export
decodeSixIsBounds : intToResult 6 = Just BoundsViolation
decodeSixIsBounds = Refl

||| Concrete decode: an out-of-range integer decodes to nothing — no ABI
||| value is invented for codes the contract does not define.
export
decodeOutOfRangeIsNothing : intToResult 7 = Nothing
decodeOutOfRangeIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes encode to DISTINCT integers, so
||| the injectivity theorem above is not vacuously true. Discharged by the
||| coverage checker — distinct primitive `Bits32` literals (0 and 1) are
||| provably unequal.
export
okEncodesDistinctFromError : Not (resultToInt Ok = resultToInt Error)
okEncodesDistinctFromError = \case Refl impossible

||| A second distinct pair, machine-checked the same way (success vs. the
||| highest code), to underline that the separation is not an artefact of one
||| adjacent pair.
export
okEncodesDistinctFromBounds : Not (resultToInt Ok = resultToInt BoundsViolation)
okEncodesDistinctFromBounds = \case Refl impossible
