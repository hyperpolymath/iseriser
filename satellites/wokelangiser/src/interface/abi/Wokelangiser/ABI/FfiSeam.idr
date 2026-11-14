-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — ABI<->FFI seam soundness proofs for Wokelangiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris and Zig
||| result-code enums agree by name+value. This module supplies the *proof-side*
||| guarantee that the encoding itself is SOUND:
|||
|||   * faithful/lossless: a decoder round-trips every ABI value through its
|||     C integer (`resultRoundTrip`, reused from Types via `resultFromInt`);
|||   * unambiguous: distinct ABI outcomes never collide on the wire
|||     (`resultToIntInjective`), DERIVED from the round-trip via
|||     `justInjective . cong`;
|||   * non-vacuous: at least two distinct codes carry distinct integers,
|||     machine-checked (`okErrorDistinct`).
|||
||| The same injectivity is established for the other FFI enum encoders that
||| ship in this ABI: `consentToInt` and `wcagToInt`.
|||
||| All proofs are genuine: no believe_me / idris_crash / assert_total /
||| postulate / %hint hacks.

module Wokelangiser.ABI.FfiSeam

import Wokelangiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Constructor injectivity helper
--------------------------------------------------------------------------------

||| `Just` is injective. Used to peel the `Just` wrapper off the round-trip
||| equality when deriving encoder injectivity. (Standalone helper because this
||| stdlib exposes injectivity only through the `Injective Just` interface
||| method, not a named `justInjective`.)
public export
justInj : {0 a, b : t} -> Just a = Just b -> a = b
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Result: faithful round-trip and derived injectivity
--------------------------------------------------------------------------------

||| The Result encoding round-trips losslessly through its C integer.
||| (Re-exported through the seam module from the decoder/proof in Types so the
||| seam guarantee stands on its own named theorem.)
public export
resultRoundTripSeam : (r : Result) -> resultFromInt (resultToInt r) = Just r
resultRoundTripSeam = resultRoundTrip

||| The Result encoding is injective: distinct ABI outcomes never collide on the
||| wire. Derived from the round-trip — if `resultToInt a = resultToInt b`, then
||| applying `resultFromInt` (via cong) to both sides and the round-trip law
||| gives `Just a = Just b`, whence `a = b` by `justInjective`.
public export
resultToIntInjective : (a, b : Result)
                    -> resultToInt a = resultToInt b
                    -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTripSeam a)) $
    trans (cong resultFromInt prf) (resultRoundTripSeam b)

--------------------------------------------------------------------------------
-- ConsentType: faithful round-trip and derived injectivity
--------------------------------------------------------------------------------

||| The ConsentType encoding round-trips losslessly through its C integer.
public export
consentRoundTripSeam : (ct : ConsentType)
                    -> consentFromInt (consentToInt ct) = Just ct
consentRoundTripSeam = consentRoundTrip

||| The ConsentType encoding is injective, derived from the round-trip.
public export
consentToIntInjective : (a, b : ConsentType)
                     -> consentToInt a = consentToInt b
                     -> a = b
consentToIntInjective a b prf =
  justInj $
    trans (sym (consentRoundTripSeam a)) $
    trans (cong consentFromInt prf) (consentRoundTripSeam b)

--------------------------------------------------------------------------------
-- WCAGLevel: faithful round-trip and derived injectivity
--------------------------------------------------------------------------------

||| The WCAGLevel encoding round-trips losslessly through its C integer.
public export
wcagRoundTripSeam : (wl : WCAGLevel) -> wcagFromInt (wcagToInt wl) = Just wl
wcagRoundTripSeam = wcagRoundTrip

||| The WCAGLevel encoding is injective, derived from the round-trip.
public export
wcagToIntInjective : (a, b : WCAGLevel)
                  -> wcagToInt a = wcagToInt b
                  -> a = b
wcagToIntInjective a b prf =
  justInj $
    trans (sym (wcagRoundTripSeam a)) $
    trans (cong wcagFromInt prf) (wcagRoundTripSeam b)

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes = Refl)
--------------------------------------------------------------------------------

||| Concrete decode control: integer 0 decodes to Ok.
public export
decodeOkControl : resultFromInt (the Bits32 0) = Just Ok
decodeOkControl = Refl

||| Concrete decode control: integer 7 decodes to I18nError (last code).
public export
decodeLastControl : resultFromInt (the Bits32 7) = Just I18nError
decodeLastControl = Refl

||| Concrete round-trip control for a mid-range code.
public export
roundTripNullPointerControl
  : resultFromInt (resultToInt NullPointer) = Just NullPointer
roundTripNullPointerControl = Refl

||| Concrete out-of-range decode control: 8 is not a valid code.
public export
decodeOutOfRangeControl : resultFromInt (the Bits32 8) = Nothing
decodeOutOfRangeControl = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes carry DISTINCT integers, so the
||| injectivity statement is not vacuously true. Machine-checked: the two
||| primitive Bits32 literals (0 and 1) are provably unequal, refuted by the
||| coverage checker discharging `Refl impossible`.
public export
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct = \case Refl impossible

||| A second non-vacuity witness across a wider gap (NullPointer=4 vs
||| I18nError=7) to underline the encoding genuinely separates outcomes.
public export
nullI18nDistinct : Not (resultToInt NullPointer = resultToInt I18nError)
nullI18nDistinct = \case Refl impossible
