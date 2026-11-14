-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — ABI<->FFI seam soundness proofs for Nimiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris
||| `Result` enum and the Zig FFI enum agree by name+value. This module
||| supplies the PROOF-SIDE guarantee that the encoding itself is sound:
|||
|||   (a) `resultToInt` is injective — distinct ABI outcomes never collide
|||       on the wire (`resultToIntInjective`).
|||   (b) there is a total decoder `intToResult` and a round-trip law
|||       `resultRoundTrip` showing the C integer faithfully reconstructs
|||       the ABI value (lossless / faithful encoding).
|||
||| Injectivity is then DERIVED from the round-trip via `justInjective . cong`,
||| which is the cleanest route and depends only on the round-trip Refls
||| reducing. The decoder is written with boolean `==` on Bits32 so that
||| `intToResult (resultToInt r)` reduces definitionally for each concrete
||| constructor, making every round-trip clause `Refl`.
|||
||| There is no `ProofStatus`/`statusToInt` (or any other FFI enum encoder)
||| in this repo's ABI, so `Result` is the sole seam to seal here.

module Nimiser.ABI.FfiSeam

import Nimiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local helper
--------------------------------------------------------------------------------

||| `Just` is injective: equal wrapped values come from equal payloads.
||| (Defined locally; the base library in this toolchain does not export it.)
private
justInjective : {0 x, y : a} -> Just x = Just y -> x = y
justInjective Refl = Refl

--------------------------------------------------------------------------------
-- Decoder: C integer -> ABI Result
--------------------------------------------------------------------------------

||| Decode a C integer result code back into the ABI `Result`.
||| Uses boolean `==` on Bits32 (which reduces on concrete literals) so the
||| round-trip law below holds definitionally. Unknown codes decode to Nothing.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just CompilationFailed
  else if x == 6 then Just TemplateError
  else if x == 7 then Just MacroError
  else Nothing

--------------------------------------------------------------------------------
-- Round-trip: faithful / lossless encoding
--------------------------------------------------------------------------------

||| Every ABI result survives a round trip through its C integer encoding:
||| decoding the encoded value reconstructs exactly the original `Result`.
||| Each clause reduces to `Refl` because the boolean `==` comparisons on the
||| concrete literal produced by `resultToInt` evaluate at type-check time.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok                = Refl
resultRoundTrip Error             = Refl
resultRoundTrip InvalidParam      = Refl
resultRoundTrip OutOfMemory       = Refl
resultRoundTrip NullPointer       = Refl
resultRoundTrip CompilationFailed = Refl
resultRoundTrip TemplateError     = Refl
resultRoundTrip MacroError        = Refl

--------------------------------------------------------------------------------
-- Injectivity, derived from the round trip
--------------------------------------------------------------------------------

||| The encoding is unambiguous: distinct ABI outcomes never collide on the
||| wire. Derived cleanly from the round-trip law — if two results encode to
||| the same integer, decoding that integer gives `Just a` and `Just b`, so
||| `Just a = Just b`, hence `a = b`.
export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInjective $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked)
--------------------------------------------------------------------------------

||| Positive control: the integer 0 decodes to `Ok`.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Positive control: the integer 7 (the largest code) decodes to `MacroError`.
export
decodeSevenIsMacroError : intToResult 7 = Just MacroError
decodeSevenIsMacroError = Refl

||| Positive control: an out-of-range code (8) decodes to `Nothing`.
export
decodeEightIsNothing : intToResult 8 = Nothing
decodeEightIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (machine-checked)
--------------------------------------------------------------------------------

||| Non-vacuity control: two DISTINCT result codes have DISTINCT integers.
||| If the encoding were trivial/collapsing, this proof would be impossible.
||| Distinct primitive Bits32 literals are provably unequal, discharged by the
||| coverage checker via `Refl impossible`.
export
okIntDistinctFromErrorInt : Not (resultToInt Ok = resultToInt Error)
okIntDistinctFromErrorInt = \case Refl impossible
