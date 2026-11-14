-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — ABI<->FFI seam soundness proofs for Ponyiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks the Idris `Result`
||| enum and the Zig FFI enum agree by name+value. This module supplies the
||| PROOF-SIDE guarantee that the on-the-wire encoding is itself sound:
|||
|||   * distinct ABI outcomes never collide on the wire (injectivity), and
|||   * the C integer faithfully round-trips back to the ABI value
|||     (lossless / faithful encoding).
|||
||| Injectivity is DERIVED from the round-trip via `justInjective` + `cong`:
||| if `resultToInt a = resultToInt b`, then applying `intToResult` to both
||| sides and rewriting through the round-trip yields `Just a = Just b`, hence
||| `a = b`. The decoder is written with pattern-matching on concrete `Bits32`
||| literals; the round-trip `Refl`s reduce (mirroring the existing
||| `capRoundtrip` in Types.idr, which uses the same idiom and compiles).
|||
||| The same treatment is applied to `RefCapability`/`capToInt`, the repo's
||| other FFI enum encoder.
|||
||| @see Ponyiser.ABI.Types

module Ponyiser.ABI.FfiSeam

import Ponyiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Generic helper
--------------------------------------------------------------------------------

||| `Just` is injective. Proved directly by matching the equality witness; no
||| library dependency. (Base 0.7.0 exposes an `Injective Just` interface but no
||| bare `justInjective` function.)
public export
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Result: faithful decoder
--------------------------------------------------------------------------------

||| Decode a C integer back into a Result outcome. Total: unknown codes map to
||| Nothing. This is the inverse of `resultToInt` on the image of `resultToInt`.
public export
intToResult : Bits32 -> Maybe Result
intToResult 0 = Just Ok
intToResult 1 = Just Error
intToResult 2 = Just InvalidParam
intToResult 3 = Just OutOfMemory
intToResult 4 = Just NullPointer
intToResult 5 = Just InvalidCapability
intToResult 6 = Just SendabilityViolation
intToResult 7 = Just ActorNotFound
intToResult _ = Nothing

||| Faithful/lossless encoding: decoding an encoded Result recovers it exactly.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip InvalidCapability = Refl
resultRoundTrip SendabilityViolation = Refl
resultRoundTrip ActorNotFound = Refl

||| (a) The encoding is unambiguous: distinct ABI outcomes never collide on the
||| wire. Derived from the round-trip — apply `intToResult` to both sides of the
||| hypothesis (via `cong`), rewrite through the round-trip on each side, and
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
-- RefCapability: the repo's other FFI enum encoder
--------------------------------------------------------------------------------

||| (c) Same injectivity for `capToInt`. `intToCap` and its round-trip
||| (`capRoundtrip`) already live in Types.idr; we reuse them here.
public export
capToIntInjective : (a, b : RefCapability)
                 -> capToInt a = capToInt b
                 -> a = b
capToIntInjective a b prf =
  justInj $
    rewrite sym (capRoundtrip a) in
    rewrite sym (capRoundtrip b) in
    cong intToCap prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes = Refl)
--------------------------------------------------------------------------------

||| Concrete decode: code 0 is Ok.
public export
decodeOkControl : intToResult 0 = Just Ok
decodeOkControl = Refl

||| Concrete decode: code 7 is ActorNotFound (highest code).
public export
decodeActorNotFoundControl : intToResult 7 = Just ActorNotFound
decodeActorNotFoundControl = Refl

||| Concrete decode: unknown code 8 is rejected.
public export
decodeUnknownControl : intToResult 8 = Nothing
decodeUnknownControl = Refl

||| Concrete decode: capability code 5 is Tag (highest cap code).
public export
decodeTagControl : intToCap 5 = Just Tag
decodeTagControl = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Distinct primitive Bits32 literals are provably unequal; the coverage
||| checker discharges the impossible diagonal. Establishes non-vacuity: the
||| encoding genuinely separates outcomes rather than collapsing them.
public export
okIntNotErrorInt : Not (resultToInt Ok = resultToInt Error)
okIntNotErrorInt = \case Refl impossible

||| Lifted to the ABI level via injectivity: Ok and Error are distinct, so the
||| seam never conflates a success with a failure on the wire.
public export
okNotError : Not (Ok = Error)
okNotError prf = okIntNotErrorInt (cong resultToInt prf)

||| Non-vacuity for the capability encoder too: Iso and Tag differ on the wire.
public export
isoIntNotTagInt : Not (capToInt Iso = capToInt Tag)
isoIntNotTagInt = \case Refl impossible
