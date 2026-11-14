-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4: ABI<->FFI seam soundness for Oblibeniser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2 `Result`
||| enum and the Zig FFI enum agree by name+value. This module supplies the
||| PROOF-SIDE guarantee that the encoding `resultToInt : Result -> Bits32` is
||| SOUND: distinct ABI outcomes never collide on the wire, and the C integer
||| faithfully round-trips back to the ABI value.
|||
||| Theorems:
|||   * intToResult       — a total decoder Bits32 -> Maybe Result.
|||   * resultRoundTrip   — intToResult (resultToInt r) = Just r  (lossless).
|||   * resultToIntInjective — distinct Results never share an int code,
|||     DERIVED from the round-trip via justInjective + cong.
|||
||| Plus positive controls (concrete decodes by Refl) and a non-vacuity /
||| negative control (Ok and Error provably differ on the wire).

module Oblibeniser.ABI.FfiSeam

import Oblibeniser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local lemma
--------------------------------------------------------------------------------

||| `Just` is injective: peel it off both sides. Genuine proof by matching the
||| single inhabiting `Refl`.
private
justInj : {0 a, b : ty} -> Just a = Just b -> a = b
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Decoder
--------------------------------------------------------------------------------

||| Decode a C integer back to a Result. Built with boolean `==` on Bits32
||| literals (which reduces definitionally on concrete constants), so the
||| round-trip Refls below check. Any value outside 0..7 is unrepresentable
||| and decodes to Nothing.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just NotReversible
  else if x == 6 then Just AuditViolation
  else if x == 7 then Just InverseProofFailed
  else Nothing

--------------------------------------------------------------------------------
-- Round-trip: the encoding is lossless
--------------------------------------------------------------------------------

||| Encoding then decoding recovers the original Result exactly.
||| Each clause reduces through the boolean `==` ladder above.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok                 = Refl
resultRoundTrip Error              = Refl
resultRoundTrip InvalidParam       = Refl
resultRoundTrip OutOfMemory        = Refl
resultRoundTrip NullPointer        = Refl
resultRoundTrip NotReversible      = Refl
resultRoundTrip AuditViolation     = Refl
resultRoundTrip InverseProofFailed = Refl

--------------------------------------------------------------------------------
-- Injectivity, derived from the round-trip
--------------------------------------------------------------------------------

||| The encoding is unambiguous: distinct ABI outcomes never collide on the
||| wire. Derived purely from `resultRoundTrip`: if two Results encode to the
||| same int, then decoding that int gives `Just a` and `Just b` for the same
||| value, so `Just a = Just b`, hence `a = b`.
public export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes by Refl)
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding 7 yields InverseProofFailed (the last code).
decodeSevenIsInverseProofFailed : intToResult 7 = Just InverseProofFailed
decodeSevenIsInverseProofFailed = Refl

||| Out-of-range codes decode to Nothing.
decodeEightIsNothing : intToResult 8 = Nothing
decodeEightIsNothing = Refl

--------------------------------------------------------------------------------
-- Non-vacuity / negative control
--------------------------------------------------------------------------------

||| Machine-checked proof that two DISTINCT result codes have DISTINCT ints:
||| Ok (0) and Error (1) cannot share a wire value. This rules out a vacuous
||| injectivity statement (which would hold trivially if the encoding were
||| constant). The witness is `\case Refl impossible`: the coverage checker
||| discharges it because the primitive Bits32 literals 0 and 1 differ.
okErrorDistinctOnWire : Not (resultToInt Ok = resultToInt Error)
okErrorDistinctOnWire = \case Refl impossible
