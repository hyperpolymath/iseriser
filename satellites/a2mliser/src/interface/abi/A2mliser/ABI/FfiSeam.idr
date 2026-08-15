-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-4 ABI<->FFI seam soundness proofs for a2mliser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris ABI
||| `resultToInt` encoder and the Zig FFI result enum agree by name+value.
||| This module supplies the PROOF-SIDE guarantee that the encoding itself is
||| SOUND: distinct ABI outcomes never collide on the wire, and the C integer
||| faithfully round-trips back to the ABI value.
|||
||| THEOREMS:
|||   * intToResult        — a total decoder Bits32 -> Maybe AttestationResult
|||   * resultRoundTrip    — intToResult (resultToInt r) = Just r  (lossless)
|||   * resultToIntInjective — derived from the round-trip via justInjective+cong
|||
||| Plus positive controls (concrete decode = Refl) and a machine-checked
||| non-vacuity / negative control (distinct codes have distinct ints).

module A2mliser.ABI.FfiSeam

import A2mliser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Decoder (faithful inverse of resultToInt)
--------------------------------------------------------------------------------

||| Decode a C integer back to an AttestationResult.
|||
||| Built with boolean Bits32 `==` (which reduces on concrete literals) rather
||| than by pattern-matching on Bits32 literals (which does not reduce
||| definitionally). This makes the round-trip Refls below check.
public export
intToResult : Bits32 -> Maybe AttestationResult
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just SignatureInvalid
  else if x == 6 then Just DigestMismatch
  else if x == 7 then Just ChainBroken
  else if x == 8 then Just KeyExpired
  else Nothing

--------------------------------------------------------------------------------
-- (b) Faithful / lossless round-trip
--------------------------------------------------------------------------------

||| The encoding is lossless: decoding an encoded result recovers it exactly.
||| Each clause reduces by computing the concrete boolean `==` chain.
public export
resultRoundTrip : (r : AttestationResult) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip SignatureInvalid = Refl
resultRoundTrip DigestMismatch = Refl
resultRoundTrip ChainBroken = Refl
resultRoundTrip KeyExpired = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| Injectivity of the `Just` constructor (proved locally to avoid any
||| dependency beyond the prelude).
justInj : {0 x, y : AttestationResult} -> Just x = Just y -> x = y
justInj Refl = Refl

||| The encoding is unambiguous: distinct ABI outcomes never collide on the
||| wire. Derived cleanly from the round-trip: if `resultToInt a = resultToInt b`
||| then applying `intToResult` to both sides and using the round-trip on each
||| gives `Just a = Just b`, whence `a = b` by injectivity of `Just`.
public export
resultToIntInjective : (a, b : AttestationResult)
                    -> resultToInt a = resultToInt b
                    -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) $
    trans (cong intToResult prf) (resultRoundTrip b)

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes)
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
public export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding 8 yields KeyExpired (the largest valid code).
public export
decodeEightIsKeyExpired : intToResult 8 = Just KeyExpired
decodeEightIsKeyExpired = Refl

||| Decoding an out-of-range code yields Nothing.
public export
decodeNineIsNothing : intToResult 9 = Nothing
decodeNineIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes encode to DISTINCT ints, machine
||| checked. `resultToInt Ok` reduces to `0` and `resultToInt Error` to `1`;
||| distinct primitive Bits32 literals are provably unequal, so the coverage
||| checker discharges `Refl impossible`.
public export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

||| A second distinct pair, for good measure.
public export
okNotKeyExpired : Not (resultToInt Ok = resultToInt KeyExpired)
okNotKeyExpired = \case Refl impossible
