-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the tlaiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If the concrete ABI layout
||| were misaligned, the result-code encoding wrong, or a decision procedure
||| mis-defined, this module would fail to typecheck and the proof build would
||| go red.
|||
||| The C-ABI compliance witness is built directly from per-field divisibility
||| proofs (`DivideBy k Refl`, where `offset = k * alignment`). Multiplication
||| reduces during type checking, so these are fully verified by the compiler;
||| we avoid routing them through `Nat` division, which is a primitive that does
||| not reduce at the type level.

module Tlaiser.ABI.Proofs

import Tlaiser.ABI.Types
import Tlaiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layout is provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the ModelCheckRequest layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|8, 24|4, 28|4, 32|8, 40|4, 44|4.
||| Each `DivideBy k Refl` witnesses `offset = k * alignment`.
export
modelCheckRequestCompliant : CABICompliant Layout.modelCheckRequestLayout
modelCheckRequestCompliant =
  CABIOk modelCheckRequestLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 10 Refl)
    (ConsField _ _ (DivideBy 11 Refl)
     NoFields)))))))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

||| Success is encoded as 0 — the value the Zig FFI tests for on the happy path.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The terminal state-space-exhaustion code is exactly 7.
export
stateSpaceExhaustedIsSeven : resultToInt StateSpaceExhausted = 7
stateSpaceExhaustedIsSeven = Refl

||| The result-code encoding is injective on the two codes the wrapper layer
||| switches on directly (Ok vs. TlcError): distinct constructors map to
||| distinct integers, so a round-trip through the FFI boundary is unambiguous.
export
okDistinctFromTlcError : Not (resultToInt Ok = resultToInt TlcError)
okDistinctFromTlcError = \case Refl impossible
