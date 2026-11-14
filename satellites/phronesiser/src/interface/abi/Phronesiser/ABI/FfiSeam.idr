-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-4 proof: SEALING THE ABI<->FFI SEAM for Phronesiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks the Idris and Zig
||| result-code enums agree by name+value. This module is the PROOF-SIDE
||| guarantee that the encoding is SOUND:
|||
|||   * distinct ABI outcomes never collide on the wire (injectivity), and
|||   * the C integer faithfully round-trips back to the ABI value
|||     (a total decoder `intToResult` is a left inverse of `resultToInt`).
|||
||| Injectivity is DERIVED from the round-trip via `justInj` + `cong`,
||| which is the cleanest route once the decoder's round-trip `Refl`s reduce.
||| The decoder is written with boolean `Bits32` `==` (which reduces on
||| concrete literals), so `resultRoundTrip Ok = Refl` etc. all check
||| definitionally.
|||
||| The same injectivity is also proved for the other FFI enum encoders
||| present in `Types`: `modalityToInt` (DeonticModality) and `severityToInt`
||| (HarmSeverity). (There is no `ProofStatus`/`statusToInt` in this repo.)
|||
||| Controls: positive (concrete decode = Refl), and a machine-checked
||| NON-VACUITY control that two DISTINCT result codes have distinct ints.
|||
||| Genuine proof only — no believe_me / idris_crash / assert_total /
||| postulate / sorry. %default total.

module Phronesiser.ABI.FfiSeam

import Phronesiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Generic helper
--------------------------------------------------------------------------------

||| `Just` is injective. Used to turn a round-trip equality through the
||| decoder back into an equality of the underlying ABI values.
public export
justInj : {0 a, b : ty} -> Just a = Just b -> a = b
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Result: faithful decoder + round-trip + derived injectivity
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`.
||| Written with boolean `Bits32` `==` so it reduces on concrete literals,
||| making the round-trip `Refl`s check definitionally. Unknown codes
||| decode to `Nothing` (the wire space is larger than the ABI space).
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just ConstraintViolation
  else if x == 6 then Just ConstraintConflict
  else Nothing

||| The decoder is a left inverse of the encoder: every ABI value round-trips
||| losslessly through its C integer. FAITHFULNESS of the encoding.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip ConstraintViolation = Refl
resultRoundTrip ConstraintConflict = Refl

||| The encoding is UNAMBIGUOUS: distinct ABI outcomes never collide on the
||| wire. Derived from the round-trip (a function with a left inverse is
||| injective) via `cong` + `justInj`.
public export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a))
          (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- DeonticModality: same guarantees (task (c))
--------------------------------------------------------------------------------

||| Decode a C integer back into a `DeonticModality`.
public export
intToModality : Bits32 -> Maybe DeonticModality
intToModality x =
  if x == 0 then Just Obligation
  else if x == 1 then Just Permission
  else if x == 2 then Just Prohibition
  else Nothing

||| Round-trip / faithfulness for the deontic-modality encoder.
public export
modalityRoundTrip : (m : DeonticModality) ->
                    intToModality (modalityToInt m) = Just m
modalityRoundTrip Obligation = Refl
modalityRoundTrip Permission = Refl
modalityRoundTrip Prohibition = Refl

||| Injectivity for the deontic-modality encoder, derived from round-trip.
public export
modalityToIntInjective : (a, b : DeonticModality) ->
                         modalityToInt a = modalityToInt b -> a = b
modalityToIntInjective a b prf =
  justInj $
    trans (sym (modalityRoundTrip a))
          (trans (cong intToModality prf) (modalityRoundTrip b))

--------------------------------------------------------------------------------
-- HarmSeverity: same guarantees (task (c))
--------------------------------------------------------------------------------

||| Decode a C integer back into a `HarmSeverity`.
public export
intToSeverity : Bits32 -> Maybe HarmSeverity
intToSeverity x =
  if x == 0 then Just Negligible
  else if x == 1 then Just Minor
  else if x == 2 then Just Moderate
  else if x == 3 then Just Severe
  else if x == 4 then Just Critical
  else Nothing

||| Round-trip / faithfulness for the harm-severity encoder.
public export
severityRoundTrip : (s : HarmSeverity) ->
                    intToSeverity (severityToInt s) = Just s
severityRoundTrip Negligible = Refl
severityRoundTrip Minor = Refl
severityRoundTrip Moderate = Refl
severityRoundTrip Severe = Refl
severityRoundTrip Critical = Refl

||| Injectivity for the harm-severity encoder, derived from round-trip.
public export
severityToIntInjective : (a, b : HarmSeverity) ->
                         severityToInt a = severityToInt b -> a = b
severityToIntInjective a b prf =
  justInj $
    trans (sym (severityRoundTrip a))
          (trans (cong intToSeverity prf) (severityRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decode = Refl, machine-checked)
--------------------------------------------------------------------------------

||| Positive control: 0 decodes to Ok.
public export
decodeOkControl : FfiSeam.intToResult 0 = Just Ok
decodeOkControl = Refl

||| Positive control: 6 decodes to ConstraintConflict (the top code).
public export
decodeConflictControl : FfiSeam.intToResult 6 = Just ConstraintConflict
decodeConflictControl = Refl

||| Positive control: an out-of-range code decodes to Nothing.
public export
decodeUnknownControl : FfiSeam.intToResult 7 = Nothing
decodeUnknownControl = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls (machine-checked)
--------------------------------------------------------------------------------

||| NON-VACUITY: two DISTINCT result codes have DISTINCT C integers.
||| If `resultToInt` were constant the seam would be vacuously "sound";
||| this rules that out. `Ok` -> 0, `Error` -> 1, and `0 = 1` is impossible
||| for distinct primitive `Bits32` literals.
public export
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct = \case Refl impossible

||| Non-vacuity at the other end of the enum: the two highest codes differ.
public export
violationConflictDistinct :
  Not (resultToInt ConstraintViolation = resultToInt ConstraintConflict)
violationConflictDistinct = \case Refl impossible

||| Non-vacuity for the deontic-modality encoder.
public export
obligationProhibitionDistinct :
  Not (modalityToInt Obligation = modalityToInt Prohibition)
obligationProhibitionDistinct = \case Refl impossible

||| Non-vacuity for the harm-severity encoder.
public export
negligibleCriticalDistinct :
  Not (severityToInt Negligible = severityToInt Critical)
negligibleCriticalDistinct = \case Refl impossible
