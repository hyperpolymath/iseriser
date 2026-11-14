-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — Sealing the ABI<->FFI seam for BQNiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2
||| `Result` enum and the Zig FFI enum agree by name+value.  This module
||| supplies the PROOF-SIDE guarantee: that the encoding `resultToInt` is
||| SOUND — distinct ABI outcomes never collide on the wire, and the C
||| integer faithfully round-trips back to the ABI value.
|||
||| We prove:
|||   (a) resultToIntInjective — the encoding is unambiguous (injective).
|||   (b) intToResult / resultRoundTrip — the encoding is lossless: the
|||       decoder recovers the original Result from its integer.
|||   (c) bqnTypeToIntInjective — the SAME injectivity for the other FFI
|||       enum encoder in this ABI (`bqnTypeToInt : BQNType -> Bits32`).
|||
||| Controls: positive (concrete decode = Refl), and a non-vacuity /
||| negative control (two distinct codes have distinct ints, machine-checked).
|||
||| @see Bqniser.ABI.Types  (Result, resultToInt, BQNType, bqnTypeToInt)

module Bqniser.ABI.FfiSeam

import Bqniser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Injectivity of the Just constructor
--------------------------------------------------------------------------------

||| `Just` is injective: equal `Just` wrappers have equal contents.
||| Used to lift the decoder round-trip back to equality of the originals.
justInj : {0 a, b : t} -> Just a = Just b -> a = b
justInj Refl = Refl

--------------------------------------------------------------------------------
-- (b) Faithful decoder + round-trip for Result
--------------------------------------------------------------------------------

||| Decode a C integer back into a Result.  Built with boolean Bits32 `==`
||| (which reduces on concrete literals) so the round-trip Refls check.
||| Any out-of-range integer decodes to Nothing.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just EvalError
  else Nothing

||| The encoding is lossless: decoding an encoded Result recovers it exactly.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok           = Refl
resultRoundTrip Error        = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory  = Refl
resultRoundTrip NullPointer  = Refl
resultRoundTrip EvalError    = Refl

--------------------------------------------------------------------------------
-- (a) Injectivity of resultToInt
--------------------------------------------------------------------------------

||| The encoding is unambiguous: equal integer encodings imply equal Results.
||| DERIVED from the round-trip (cleanest): if resultToInt a = resultToInt b,
||| then applying intToResult to both sides and using the round-trip gives
||| Just a = Just b, whence a = b by injectivity of Just.
public export
resultToIntInjective : (a, b : Result)
                    -> resultToInt a = resultToInt b
                    -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) (trans (cong intToResult prf) (resultRoundTrip b))

--------------------------------------------------------------------------------
-- (c) Injectivity of bqnTypeToInt (the other FFI enum encoder)
--------------------------------------------------------------------------------

||| Decode a CBQN type tag back into a BQNType.
public export
intToBQNType : Bits32 -> Maybe BQNType
intToBQNType x =
  if x == 0 then Just BQNNumber
  else if x == 1 then Just BQNCharacter
  else if x == 2 then Just BQNFunction
  else if x == 3 then Just BQN1Modifier
  else if x == 4 then Just BQN2Modifier
  else if x == 5 then Just BQNNamespace
  else if x == 6 then Just BQNArray
  else Nothing

||| The type-tag encoding is lossless.
public export
bqnTypeRoundTrip : (t : BQNType) -> intToBQNType (bqnTypeToInt t) = Just t
bqnTypeRoundTrip BQNNumber    = Refl
bqnTypeRoundTrip BQNCharacter = Refl
bqnTypeRoundTrip BQNFunction  = Refl
bqnTypeRoundTrip BQN1Modifier = Refl
bqnTypeRoundTrip BQN2Modifier = Refl
bqnTypeRoundTrip BQNNamespace = Refl
bqnTypeRoundTrip BQNArray     = Refl

||| The type-tag encoding is unambiguous (injective), derived from round-trip.
public export
bqnTypeToIntInjective : (a, b : BQNType)
                     -> bqnTypeToInt a = bqnTypeToInt b
                     -> a = b
bqnTypeToIntInjective a b prf =
  justInj $
    trans (sym (bqnTypeRoundTrip a)) (trans (cong intToBQNType prf) (bqnTypeRoundTrip b))

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes reduce to Refl)
--------------------------------------------------------------------------------

||| Positive control: 0 decodes to Ok.
public export
decodeOkControl : intToResult 0 = Just Ok
decodeOkControl = Refl

||| Positive control: 5 decodes to EvalError (last code).
public export
decodeEvalErrorControl : intToResult 5 = Just EvalError
decodeEvalErrorControl = Refl

||| Positive control: an out-of-range integer decodes to Nothing.
public export
decodeOutOfRangeControl : intToResult 6 = Nothing
decodeOutOfRangeControl = Refl

||| Positive control for the type-tag decoder: 6 decodes to BQNArray.
public export
decodeArrayControl : intToBQNType 6 = Just BQNArray
decodeArrayControl = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity control: two DISTINCT result codes have DISTINCT ints.
||| If this were not so, injectivity would be vacuous.  Machine-checked:
||| the coverage checker refutes `resultToInt Ok = resultToInt Error`
||| (i.e. (the Bits32 0) = 1) as impossible.
public export
okNeqError : Not (resultToInt Ok = resultToInt Error)
okNeqError = \case Refl impossible

||| A second non-vacuity control across non-adjacent codes.
public export
okNeqEvalError : Not (resultToInt Ok = resultToInt EvalError)
okNeqEvalError = \case Refl impossible

||| Non-vacuity control for the type-tag encoder.
public export
numberNeqArray : Not (bqnTypeToInt BQNNumber = bqnTypeToInt BQNArray)
numberNeqArray = \case Refl impossible
