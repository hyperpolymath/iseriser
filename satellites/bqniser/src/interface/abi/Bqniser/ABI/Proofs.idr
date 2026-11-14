-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the bqniser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If the concrete CBQN array
||| descriptor layout were misaligned, the FFI result-code encoding wrong, or
||| the BQN type-tag encoding wrong, this module would fail to typecheck and
||| the proof build would go red.
|||
||| The C-ABI compliance witness is built directly from per-field divisibility
||| proofs (`DivideBy k Refl`, where `offset = k * alignment`). Multiplication
||| reduces during type checking, so these are fully verified by the compiler;
||| we never route them through `Nat` division, which is a primitive that does
||| not reduce at the type level.

module Bqniser.ABI.Proofs

import Bqniser.ABI.Types
import Bqniser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete CBQN array-descriptor layout is provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the CBQN array descriptor divides its alignment:
||| 0|8 (= 0 * 8) and 8|8 (= 1 * 8).
export
cbqnArrayDescCompliant : CABICompliant Layout.cbqnArrayDescLayout
cbqnArrayDescCompliant =
  CABIOk cbqnArrayDescLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
     NoFields))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

||| Success is encoded as 0 (the C convention the FFI bridge relies on).
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| Null-pointer errors are encoded as 4, matching errorDescription/the bridge.
export
nullPointerIsFour : resultToInt NullPointer = 4
nullPointerIsFour = Refl

--------------------------------------------------------------------------------
-- BQN type-tag encoding: must match CBQN's internal tags 0..6.
--------------------------------------------------------------------------------

||| Numbers carry tag 0.
export
numberTagIsZero : bqnTypeToInt BQNNumber = 0
numberTagIsZero = Refl

||| Arrays — the fundamental compound type — carry the top tag 6.
export
arrayTagIsSix : bqnTypeToInt BQNArray = 6
arrayTagIsSix = Refl

--------------------------------------------------------------------------------
-- A scalar (rank 0) holds exactly one element.
--------------------------------------------------------------------------------

||| The empty shape vector has product 1, so a rank-0 value is a single cell.
export
scalarSingleElement : shapeProduct (the (Vect 0 Bits64) []) = 1
scalarSingleElement = Refl
