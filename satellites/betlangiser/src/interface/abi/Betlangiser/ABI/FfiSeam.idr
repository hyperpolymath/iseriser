-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 proof: SEALING THE ABI<->FFI SEAM for Betlangiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2
||| `Result` enum and the Zig FFI enum agree by name and value. This module
||| supplies the PROOF-SIDE guarantee that the C-integer encoding is SOUND:
|||
|||   (a) `resultToIntInjective` — distinct ABI outcomes never collide on the
|||       wire (the encoding is unambiguous);
|||   (b) `intToResult` + `resultRoundTrip` — the C integer faithfully and
|||       losslessly round-trips back to the ABI value, and injectivity is
|||       DERIVED from the round-trip via `justInjective`;
|||   (c) the SAME guarantees for the `TernaryBool` FFI enum encoder
|||       (`ternaryToInt` / `intToTernary`), which is the other C-integer
|||       result-style encoder this ABI exposes across the seam.
|||
||| Method: the decoders are built with boolean `==` on `Bits32` so that the
||| round-trip `Refl`s reduce definitionally on the concrete primitive
||| literals. Injectivity is then derived from the round-trip. Positive
||| controls (concrete `decode = Refl`) and a machine-checked negative /
||| non-vacuity control (two distinct codes have distinct ints) are included.
|||
||| No `believe_me`, `idris_crash`, `assert_total`, `postulate`, or `sorry`:
||| this is a genuine, total proof.

module Betlangiser.ABI.FfiSeam

import Betlangiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Generic helper: injectivity of the `Just` constructor
--------------------------------------------------------------------------------

||| `Just` is injective. (Idris2 0.7.0 base does not export `justInjective`,
||| so we prove it locally by pattern matching on the equality witness.)
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- (b) Decoder + round-trip for Result
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`. Total: every `Bits32` not in the
||| valid range maps to `Nothing`. Uses boolean `==` so the comparisons reduce
||| on concrete primitive literals (enabling the round-trip `Refl`s to check).
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just InvalidDistribution
  else if x == 6 then Just SamplingFailed
  else Nothing

||| Faithful / lossless encoding: decoding the encoding of any `Result`
||| recovers exactly that `Result`. This is the core seam-soundness theorem —
||| no ABI outcome is lost or corrupted when it crosses to C and back.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip InvalidDistribution = Refl
resultRoundTrip SamplingFailed = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity of resultToInt, DERIVED from the round-trip
--------------------------------------------------------------------------------

||| The encoding is unambiguous: distinct `Result` outcomes never collide on
||| the wire. Derived cleanly from `resultRoundTrip` via `justInj`:
||| if `resultToInt a = resultToInt b`, then applying `intToResult` to both
||| sides gives `Just a = Just b`, whence `a = b`.
public export
resultToIntInjective : (a, b : Result) ->
                       resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj (rewrite sym (resultRoundTrip a) in
           rewrite prf in
           resultRoundTrip b)

--------------------------------------------------------------------------------
-- (c) Same guarantees for the TernaryBool FFI enum encoder
--------------------------------------------------------------------------------
-- Types.idr already defines `ternaryToInt` (0=False,1=True,2=Unknown) and the
-- decoder `intToTernary`. We prove the same round-trip and injectivity here so
-- the second C-integer encoder crossing the seam is equally sealed.

||| Faithful / lossless encoding for the ternary-logic FFI enum.
public export
ternaryRoundTrip : (x : TernaryBool) -> intToTernary (ternaryToInt x) = Just x
ternaryRoundTrip TFalse = Refl
ternaryRoundTrip TTrue = Refl
ternaryRoundTrip TUnknown = Refl

||| The ternary encoding is unambiguous, derived from its round-trip.
public export
ternaryToIntInjective : (x, y : TernaryBool) ->
                        ternaryToInt x = ternaryToInt y -> x = y
ternaryToIntInjective x y prf =
  justInj (rewrite sym (ternaryRoundTrip x) in
           rewrite prf in
           ternaryRoundTrip y)

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked by Refl)
--------------------------------------------------------------------------------

||| Positive control: the wire value 0 decodes to `Ok`.
public export
decodeOkControl : intToResult 0 = Just Ok
decodeOkControl = Refl

||| Positive control: the wire value 6 decodes to `SamplingFailed`.
public export
decodeSamplingFailedControl : intToResult 6 = Just SamplingFailed
decodeSamplingFailedControl = Refl

||| Positive control: the wire value 2 decodes to `TUnknown` (ternary enum).
public export
decodeTUnknownControl : intToTernary 2 = Just TUnknown
decodeTUnknownControl = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls (distinct codes => distinct ints)
--------------------------------------------------------------------------------
-- These guarantee the injectivity theorems are not vacuously true: there
-- genuinely EXIST distinct outcomes whose encodings differ. The refutations
-- are discharged by the coverage checker on distinct primitive Bits32 literals.

||| Non-vacuity: `Ok` and `Error` do NOT collide on the wire.
public export
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct = \case Refl impossible

||| Non-vacuity: `OutOfMemory` and `SamplingFailed` do NOT collide on the wire.
public export
oomSamplingDistinct : Not (resultToInt OutOfMemory = resultToInt SamplingFailed)
oomSamplingDistinct = \case Refl impossible

||| Non-vacuity for the ternary enum: `TTrue` and `TUnknown` do NOT collide.
public export
ternaryTrueUnknownDistinct : Not (ternaryToInt TTrue = ternaryToInt TUnknown)
ternaryTrueUnknownDistinct = \case Refl impossible
