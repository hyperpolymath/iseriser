-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-4 ABI<->FFI seam proof for Anvomidaviser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris `Result`
||| enum and the Zig FFI enum agree by name and value. This module supplies the
||| PROOF-SIDE guarantee that the encoding itself is SOUND:
|||
|||   * `resultToIntInjective` — distinct ABI outcomes never collide on the wire.
|||   * `intToResult` / `resultRoundTrip` — the C integer faithfully round-trips
|||     back to the originating ABI value (the encoding is lossless).
|||
||| Together these seal the seam: an FFI result code carries exactly one ABI
||| meaning, and that meaning is recoverable.

module Anvomidaviser.ABI.FfiSeam

import Anvomidaviser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Injectivity of the encoding
--------------------------------------------------------------------------------

||| The result-code encoding is injective: if two `Result`s encode to the same
||| C integer, they are the same `Result`. Proved directly by nested case on
||| both arguments; the diagonal is `Refl`, every off-diagonal pair is refuted
||| because its two distinct primitive `Bits32` literals cannot be equal.
export
resultToIntInjective : (a : Result) -> (b : Result)
                    -> resultToInt a = resultToInt b -> a = b
resultToIntInjective Ok Ok _ = Refl
resultToIntInjective Error Error _ = Refl
resultToIntInjective InvalidParam InvalidParam _ = Refl
resultToIntInjective OutOfMemory OutOfMemory _ = Refl
resultToIntInjective NullPointer NullPointer _ = Refl
resultToIntInjective RuleViolation RuleViolation _ = Refl
resultToIntInjective Ok Error prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Ok InvalidParam prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Ok OutOfMemory prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Ok NullPointer prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Ok RuleViolation prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Error Ok prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Error InvalidParam prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Error OutOfMemory prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Error NullPointer prf = void (the Void (case prf of Refl impossible))
resultToIntInjective Error RuleViolation prf = void (the Void (case prf of Refl impossible))
resultToIntInjective InvalidParam Ok prf = void (the Void (case prf of Refl impossible))
resultToIntInjective InvalidParam Error prf = void (the Void (case prf of Refl impossible))
resultToIntInjective InvalidParam OutOfMemory prf = void (the Void (case prf of Refl impossible))
resultToIntInjective InvalidParam NullPointer prf = void (the Void (case prf of Refl impossible))
resultToIntInjective InvalidParam RuleViolation prf = void (the Void (case prf of Refl impossible))
resultToIntInjective OutOfMemory Ok prf = void (the Void (case prf of Refl impossible))
resultToIntInjective OutOfMemory Error prf = void (the Void (case prf of Refl impossible))
resultToIntInjective OutOfMemory InvalidParam prf = void (the Void (case prf of Refl impossible))
resultToIntInjective OutOfMemory NullPointer prf = void (the Void (case prf of Refl impossible))
resultToIntInjective OutOfMemory RuleViolation prf = void (the Void (case prf of Refl impossible))
resultToIntInjective NullPointer Ok prf = void (the Void (case prf of Refl impossible))
resultToIntInjective NullPointer Error prf = void (the Void (case prf of Refl impossible))
resultToIntInjective NullPointer InvalidParam prf = void (the Void (case prf of Refl impossible))
resultToIntInjective NullPointer OutOfMemory prf = void (the Void (case prf of Refl impossible))
resultToIntInjective NullPointer RuleViolation prf = void (the Void (case prf of Refl impossible))
resultToIntInjective RuleViolation Ok prf = void (the Void (case prf of Refl impossible))
resultToIntInjective RuleViolation Error prf = void (the Void (case prf of Refl impossible))
resultToIntInjective RuleViolation InvalidParam prf = void (the Void (case prf of Refl impossible))
resultToIntInjective RuleViolation OutOfMemory prf = void (the Void (case prf of Refl impossible))
resultToIntInjective RuleViolation NullPointer prf = void (the Void (case prf of Refl impossible))

--------------------------------------------------------------------------------
-- Faithful decoder + round-trip
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`. Unknown codes map to `Nothing`.
||| Implemented with boolean `Bits32` `==`, which reduces on concrete literals,
||| so the round-trip property below holds definitionally.
export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just RuleViolation
  else Nothing

||| The encoding is lossless: decoding the encoding of any `Result` recovers it.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip RuleViolation = Refl

||| `Just` is injective (local lemma, used by the round-trip derivation below).
justInj : {0 x, y : Result} -> Just x = Just y -> x = y
justInj Refl = Refl

||| Injectivity, re-derived from the round-trip law: if the encodings agree then
||| their decodings agree, and the decoder pins each back to its own `Just`.
||| An independent witness corroborating `resultToIntInjective`.
export
resultToIntInjectiveViaRoundTrip : (a : Result) -> (b : Result)
                                -> resultToInt a = resultToInt b -> a = b
resultToIntInjectiveViaRoundTrip a b prf =
  justInj $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes)
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding 5 yields RuleViolation (the highest defined code).
export
decodeFiveIsRuleViolation : intToResult 5 = Just RuleViolation
decodeFiveIsRuleViolation = Refl

||| Decoding an out-of-range code yields Nothing.
export
decodeSixIsNothing : intToResult 6 = Nothing
decodeSixIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes encode to DISTINCT integers, so the
||| injectivity theorem is not trivially satisfied by an empty domain.
export
okEncodingNotErrorEncoding : Not (resultToInt Ok = resultToInt Error)
okEncodingNotErrorEncoding = \case Refl impossible

||| A second distinct pair, for good measure: Ok and RuleViolation differ.
export
okEncodingNotRuleViolationEncoding : Not (resultToInt Ok = resultToInt RuleViolation)
okEncodingNotRuleViolationEncoding = \case Refl impossible
