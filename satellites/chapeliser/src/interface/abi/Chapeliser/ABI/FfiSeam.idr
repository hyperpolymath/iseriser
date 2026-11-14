-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Chapeliser ABI <-> FFI Seam Soundness Proofs (Layer 4)
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2
||| `resultToInt` encoder and the Zig FFI enum agree by name+value. This
||| module supplies the PROOF-SIDE guarantee that the encoding itself is
||| SOUND, independent of any external comparison:
|||
|||   1. resultRoundTrip — the C integer faithfully ROUND-TRIPS back to the
|||      ABI `Result` value (the encoding is lossless / faithful). A decoder
|||      `intToResult : Bits32 -> Maybe Result` recovers exactly the encoded
|||      constructor.
|||   2. resultToIntInjective — distinct ABI outcomes NEVER collide on the
|||      wire (the encoding is unambiguous). This is DERIVED from the
|||      round-trip via `justInj . cong intToResult`, so injectivity is
|||      a corollary of faithfulness rather than a separate hand proof.
|||
||| Together these seal the ABI<->FFI seam: every `Result` maps to a unique
||| C integer, and that integer decodes back to the same `Result`.
|||
||| All proofs are genuine and machine-checked — no `believe_me`,
||| `idris_crash`, `assert_total`, `postulate`, `sorry`, or `%hint` hacks.

module Chapeliser.ABI.FfiSeam

import Chapeliser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local helper: Just is injective
--------------------------------------------------------------------------------

||| `Just` is injective. Proved locally (rather than relying on a Prelude name)
||| by matching the single `Refl` constructor of the hypothesis.
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Decoder: C integer back to ABI Result
--------------------------------------------------------------------------------

||| Decode a C-compatible integer back to a `Result`.
|||
||| Built with boolean `==` on concrete `Bits32` literals (rather than a
||| `case`/pattern match on literals) precisely so the comparison REDUCES
||| definitionally on closed literals — this is what lets the `resultRoundTrip`
||| witnesses below check as plain `Refl`. Unknown codes decode to `Nothing`.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just RetryExhausted
  else if x == 6 then Just CheckpointError
  else Nothing

--------------------------------------------------------------------------------
-- (b) Faithful / lossless encoding: round-trip
--------------------------------------------------------------------------------

||| The encoding is FAITHFUL: decoding the C integer produced by `resultToInt`
||| recovers exactly the original `Result`. One clause per constructor; each
||| reduces to `Refl` because the boolean `==` in `intToResult` evaluates on
||| the concrete `Bits32` literal that `resultToInt` emits.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip RetryExhausted = Refl
resultRoundTrip CheckpointError = Refl

--------------------------------------------------------------------------------
-- (a) Unambiguous encoding: injectivity (DERIVED from the round-trip)
--------------------------------------------------------------------------------

||| The encoding is INJECTIVE: distinct ABI outcomes never collide on the wire.
|||
||| Derived from `resultRoundTrip`: if `resultToInt a = resultToInt b` then
||| applying `intToResult` to both sides (via `cong`) gives
||| `Just a = Just b` (rewriting through the two round-trip equalities), and
||| `justInj` strips the `Just`. No constructor case analysis needed.
public export
resultToIntInjective : (a, b : Result) ->
                       resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes = Refl)
--------------------------------------------------------------------------------

||| Positive control: code 0 decodes to `Ok`.
decodeOk : intToResult 0 = Just Ok
decodeOk = Refl

||| Positive control: code 6 (the largest) decodes to `CheckpointError`.
decodeCheckpointError : intToResult 6 = Just CheckpointError
decodeCheckpointError = Refl

||| Positive control: an out-of-range code decodes to `Nothing` (the decoder
||| is total and rejects codes that no `Result` maps to).
decodeUnknown : intToResult 7 = Nothing
decodeUnknown = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| NON-VACUITY: two DISTINCT result codes have DISTINCT integers, machine
||| checked. `resultToInt Ok` reduces to the literal `0` and `resultToInt
||| Error` to `1`; distinct primitive `Bits32` literals are provably unequal,
||| so the coverage checker discharges the impossible `Refl`. This rules out
||| the trivial (vacuous) world in which the encoder is constant.
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct Refl impossible

||| A second distinctness witness across a non-adjacent pair, for good measure.
nullCheckpointDistinct : Not (resultToInt NullPointer = resultToInt CheckpointError)
nullCheckpointDistinct Refl impossible
