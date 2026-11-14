-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — ABI<->FFI seam soundness proofs for Affinescriptiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2
||| `Result` enum and the Zig FFI enum agree by name and value. This module
||| supplies the PROOF-SIDE guarantee that the encoding itself is sound:
|||
|||   * `resultToIntInjective` — distinct ABI outcomes never collide on the
|||     wire (the encoding is unambiguous).
|||   * `intToResult` + `resultRoundTrip` — the C integer faithfully
|||     round-trips back to the exact ABI value (the encoding is lossless).
|||
||| Injectivity is then DERIVED from the round-trip via `justInjective . cong`,
||| so the two guarantees share a single source of truth.
|||
||| The decoder is written with boolean `Bits32` equality (`if x == n`), which
||| reduces on concrete literals, so each `resultRoundTrip r = Refl` checks
||| definitionally.

module Affinescriptiser.ABI.FfiSeam

import Affinescriptiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local helper: Just is injective
--------------------------------------------------------------------------------

||| `Just` is injective: equal options carrying `Just` have equal payloads.
||| Proved here directly (rather than imported) so the module's only
||| dependency is the ABI Types it certifies.
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Decoder: C integer -> ABI Result
--------------------------------------------------------------------------------

||| Decode a C result code back into the ABI `Result` value.
||| Built with boolean `Bits32` equality so the encode/decode round-trip
||| reduces definitionally on the concrete literals 0..6.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if      x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just AffineViolation
  else if x == 6 then Just ResourceLeak
  else                Nothing

--------------------------------------------------------------------------------
-- Round-trip: encoding is faithful / lossless
--------------------------------------------------------------------------------

||| The C integer faithfully round-trips back to the exact ABI value.
||| `intToResult (resultToInt r) = Just r` for every result code.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok              = Refl
resultRoundTrip Error           = Refl
resultRoundTrip InvalidParam    = Refl
resultRoundTrip OutOfMemory     = Refl
resultRoundTrip NullPointer     = Refl
resultRoundTrip AffineViolation = Refl
resultRoundTrip ResourceLeak    = Refl

--------------------------------------------------------------------------------
-- Injectivity: distinct outcomes never collide on the wire
--------------------------------------------------------------------------------

||| The encoding is unambiguous: equal C integers imply equal ABI outcomes.
||| Derived from the round-trip — if `resultToInt a = resultToInt b` then
||| `Just a = Just b` (by `cong intToResult` + round-trip rewriting), and
||| `justInjective` strips the `Just`.
public export
resultToIntInjective : (a, b : Result)
                    -> resultToInt a = resultToInt b
                    -> a = b
resultToIntInjective a b prf =
  justInj $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked)
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
public export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| Decoding 6 yields ResourceLeak (the highest code).
public export
decodeSixIsResourceLeak : intToResult 6 = Just ResourceLeak
decodeSixIsResourceLeak = Refl

||| An out-of-range code (7) decodes to Nothing (no spurious value).
public export
decodeSevenIsNothing : intToResult 7 = Nothing
decodeSevenIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes encode to DISTINCT C integers.
||| If `resultToInt Ok = resultToInt Error` then by injectivity `Ok = Error`,
||| which is refuted by coverage. This guards against a degenerate encoder
||| that maps everything to the same wire value.
public export
okErrorDistinctOnWire : Not (resultToInt Ok = resultToInt Error)
okErrorDistinctOnWire prf = case resultToIntInjective Ok Error prf of
  Refl impossible

||| A second distinct pair, proved directly from the primitive literals:
||| the C integer 5 (AffineViolation) is not the C integer 6 (ResourceLeak).
public export
affineViolationResourceLeakDistinct
  : Not (resultToInt AffineViolation = resultToInt ResourceLeak)
affineViolationResourceLeakDistinct prf = case resultToIntInjective AffineViolation ResourceLeak prf of
  Refl impossible
