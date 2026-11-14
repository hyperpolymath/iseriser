-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — ABI<->FFI seam soundness proof for Futharkiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris
||| `Result` enum and the Zig FFI enum agree by name and value. This module
||| supplies the PROOF-SIDE guarantee that the encoding itself is SOUND:
|||
|||   (a) `resultToIntInjective` — distinct ABI outcomes never collide on the
|||       wire: if two `Result`s encode to the same C integer, they are equal.
|||   (b) `intToResult` / `resultRoundTrip` — the encoding is faithful and
|||       lossless: decoding the encoded integer recovers the original value.
|||
||| Together these certify that the C integer crossing the FFI boundary
||| faithfully round-trips back to the ABI value, with no aliasing.
|||
||| The repo's only canonical FFI result-code encoder in the ABI Types module
||| is `resultToInt`; there is no `ProofStatus`/`statusToInt` here, so part (c)
||| of the seam mandate is vacuous for this repo.

module Futharkiser.ABI.FfiSeam

import Futharkiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Primitive Bits32 disequality helpers
--------------------------------------------------------------------------------

||| Distinct primitive Bits32 literals are provably unequal. Idris's coverage
||| checker discharges `Refl impossible` for distinct primitive constants, so
||| each pair we actually need can be refuted directly at the use site below.

--------------------------------------------------------------------------------
-- (a) Injectivity of the encoding (proved directly)
--------------------------------------------------------------------------------

||| The result-code encoding is injective: if two outcomes encode to the same
||| C integer they must be the same outcome. Distinct outcomes therefore never
||| collide on the wire. Proved by nested case on both results: the diagonal is
||| `Refl`; every off-diagonal case is refuted because the two distinct integer
||| literals cannot be equal (`\case Refl impossible`).
public export
resultToIntInjective : (a, b : Result) ->
                       resultToInt a = resultToInt b -> a = b
resultToIntInjective Ok                 Ok                 _    = Refl
resultToIntInjective Error              Error              _    = Refl
resultToIntInjective InvalidParam       InvalidParam       _    = Refl
resultToIntInjective OutOfMemory        OutOfMemory        _    = Refl
resultToIntInjective NullPointer        NullPointer        _    = Refl
resultToIntInjective CompilationFailed  CompilationFailed  _    = Refl
resultToIntInjective BackendUnavailable BackendUnavailable _    = Refl
resultToIntInjective ShapeMismatch      ShapeMismatch      _    = Refl
resultToIntInjective Ok                 Error              prf  = case prf of Refl impossible
resultToIntInjective Ok                 InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective Ok                 OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective Ok                 NullPointer        prf  = case prf of Refl impossible
resultToIntInjective Ok                 CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective Ok                 BackendUnavailable prf  = case prf of Refl impossible
resultToIntInjective Ok                 ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective Error              Ok                 prf  = case prf of Refl impossible
resultToIntInjective Error              InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective Error              OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective Error              NullPointer        prf  = case prf of Refl impossible
resultToIntInjective Error              CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective Error              BackendUnavailable prf  = case prf of Refl impossible
resultToIntInjective Error              ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       Ok                 prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       Error              prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       NullPointer        prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       BackendUnavailable prf  = case prf of Refl impossible
resultToIntInjective InvalidParam       ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        Ok                 prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        Error              prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        NullPointer        prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        BackendUnavailable prf  = case prf of Refl impossible
resultToIntInjective OutOfMemory        ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective NullPointer        Ok                 prf  = case prf of Refl impossible
resultToIntInjective NullPointer        Error              prf  = case prf of Refl impossible
resultToIntInjective NullPointer        InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective NullPointer        OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective NullPointer        CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective NullPointer        BackendUnavailable prf  = case prf of Refl impossible
resultToIntInjective NullPointer        ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  Ok                 prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  Error              prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  NullPointer        prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  BackendUnavailable prf  = case prf of Refl impossible
resultToIntInjective CompilationFailed  ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable Ok                 prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable Error              prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable NullPointer        prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective BackendUnavailable ShapeMismatch      prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      Ok                 prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      Error              prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      InvalidParam       prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      OutOfMemory        prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      NullPointer        prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      CompilationFailed  prf  = case prf of Refl impossible
resultToIntInjective ShapeMismatch      BackendUnavailable prf  = case prf of Refl impossible

--------------------------------------------------------------------------------
-- (b) Faithful (lossless) decoding
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`. Built with boolean `==` on
||| concrete `Bits32` literals (which reduces definitionally), so the
||| round-trip lemma's `Refl`s check. Out-of-range integers decode to
||| `Nothing` (no spurious ABI value is invented from the wire).
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if      x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just CompilationFailed
  else if x == 6 then Just BackendUnavailable
  else if x == 7 then Just ShapeMismatch
  else Nothing

||| Faithful round-trip: encoding a `Result` and decoding the integer recovers
||| exactly the original value. This certifies the C integer crossing the FFI
||| boundary loses no information.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok                 = Refl
resultRoundTrip Error              = Refl
resultRoundTrip InvalidParam       = Refl
resultRoundTrip OutOfMemory        = Refl
resultRoundTrip NullPointer        = Refl
resultRoundTrip CompilationFailed  = Refl
resultRoundTrip BackendUnavailable = Refl
resultRoundTrip ShapeMismatch      = Refl

||| `Just` is injective (local lemma; not exported by the stdlib used here).
justEq : {0 x, y : Result} -> Just x = Just y -> x = y
justEq Refl = Refl

||| Injectivity DERIVED from the round-trip (independent of the direct proof
||| above): if two results encode equally, decoding both gives the same
||| `Just`, and `Just` is injective. Demonstrates the round-trip is strong
||| enough to imply non-collision on its own.
public export
roundTripInjective : (a, b : Result) ->
                     resultToInt a = resultToInt b -> a = b
roundTripInjective a b prf =
  justEq $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked)
--------------------------------------------------------------------------------

||| Positive control: the integer 0 decodes to `Ok`.
public export
decodeOk : intToResult 0 = Just Ok
decodeOk = Refl

||| Positive control: the integer 7 decodes to `ShapeMismatch` (the top code).
public export
decodeShapeMismatch : intToResult 7 = Just ShapeMismatch
decodeShapeMismatch = Refl

||| Positive control: an out-of-range integer decodes to `Nothing` (the wire
||| cannot smuggle in an undefined ABI outcome).
public export
decodeOutOfRange : intToResult 8 = Nothing
decodeOutOfRange = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control (machine-checked)
--------------------------------------------------------------------------------

||| Non-vacuity: two DISTINCT result codes have DISTINCT integer encodings.
||| If this were not machine-checkable, injectivity could hold vacuously. The
||| coverage checker discharges the impossible `Refl` for distinct primitive
||| `Bits32` constants (0 vs 1), so the disequality is genuinely inhabited.
public export
okErrorDistinct : Not (resultToInt Ok = resultToInt Error)
okErrorDistinct = \case Refl impossible

||| A second non-vacuity witness across a non-adjacent pair (0 vs 7).
public export
okShapeMismatchDistinct : Not (resultToInt Ok = resultToInt ShapeMismatch)
okShapeMismatchDistinct = \case Refl impossible
