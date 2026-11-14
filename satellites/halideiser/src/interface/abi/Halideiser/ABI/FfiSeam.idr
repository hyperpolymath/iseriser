-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — sealing the ABI<->FFI seam for halideiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris
||| `Result` enum and the Zig FFI enum agree by name+value. This module is
||| the PROOF-SIDE complement: it shows the on-the-wire encoding is SOUND.
|||
|||   * `resultToInt` is INJECTIVE — distinct ABI outcomes never collide on
|||     the C integer they are transmitted as.
|||   * a decoder `intToResult` exists and the encoding ROUND-TRIPS losslessly
|||     (`intToResult (resultToInt r) = Just r`), so the C integer faithfully
|||     reconstructs the ABI value on the far side of the seam.
|||
||| Injectivity is then DERIVED from the round-trip (the cleanest route):
||| if two results encode to the same int, applying the decoder to both
||| sides yields `Just a = Just b`, and `Just` is injective.
|||
||| Genuine proof only: no believe_me / postulate / assert_total / idris_crash.

module Halideiser.ABI.FfiSeam

import Halideiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local lemma: Just is injective
--------------------------------------------------------------------------------

||| Total extractor with an explicit fallback, used to make `Just` injective
||| via `cong`. The fallback is supplied so `fromMaybe` is total.
private
fromMaybe : ty -> Maybe ty -> ty
fromMaybe _ (Just x) = x
fromMaybe d Nothing  = d

||| `Just` is injective. Proved by `cong` through `fromMaybe a`, which maps
||| `Just a` to `a` and `Just b` to `b`.
private
justInj : {a, b : ty} -> Just a = Just b -> a = b
justInj prf = cong (fromMaybe a) prf

--------------------------------------------------------------------------------
-- Decoder
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`.
|||
||| Built with boolean `==` on concrete `Bits32` literals (rather than
||| pattern-matching on literals) so that the round-trip equations below
||| reduce definitionally and check by `Refl`.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just CompileFailed
  else if x == 6 then Just InvalidSchedule
  else if x == 7 then Just DimensionMismatch
  else Nothing

--------------------------------------------------------------------------------
-- Round-trip (faithful / lossless encoding)
--------------------------------------------------------------------------------

||| The encoding round-trips: decoding the encoded value of any `Result`
||| recovers exactly that `Result`. This is the load-bearing seam guarantee.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok                = Refl
resultRoundTrip Error             = Refl
resultRoundTrip InvalidParam      = Refl
resultRoundTrip OutOfMemory       = Refl
resultRoundTrip NullPointer       = Refl
resultRoundTrip CompileFailed     = Refl
resultRoundTrip InvalidSchedule   = Refl
resultRoundTrip DimensionMismatch = Refl

--------------------------------------------------------------------------------
-- Injectivity (derived from the round-trip)
--------------------------------------------------------------------------------

||| `resultToInt` is injective: distinct ABI outcomes never share a wire code.
|||
||| Proof: if `resultToInt a = resultToInt b`, then applying the decoder to
||| both sides (via `cong`) gives `intToResult (resultToInt a)
||| = intToResult (resultToInt b)`. Rewriting both ends with the round-trip
||| yields `Just a = Just b`, whose `Just`-injectivity delivers `a = b`.
export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked by Refl)
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding 7 yields DimensionMismatch (the last code).
export
decodeSevenIsDimensionMismatch : intToResult 7 = Just DimensionMismatch
decodeSevenIsDimensionMismatch = Refl

||| Decoding an out-of-range code fails (no spurious `Result` is invented).
export
decodeOutOfRangeIsNothing : intToResult 8 = Nothing
decodeOutOfRangeIsNothing = Refl

||| A concrete round-trip instance.
export
roundTripCompileFailed : intToResult (resultToInt CompileFailed) = Just CompileFailed
roundTripCompileFailed = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Distinct primitive `Bits32` literals are provably unequal; the coverage
||| checker discharges `Refl impossible`.
distinctCodes : Not (the Bits32 0 = 1)
distinctCodes = \case Refl impossible

||| NON-VACUITY: two DISTINCT result codes really do encode to DISTINCT ints.
||| If `resultToInt Ok = resultToInt Error` held, then `0 = 1` would hold —
||| which `distinctCodes` refutes. This proves the seam is not trivially
||| satisfiable (e.g. by a constant encoder).
export
okEncodesDistinctlyFromError : Not (resultToInt Ok = resultToInt Error)
okEncodesDistinctlyFromError prf = distinctCodes prf
