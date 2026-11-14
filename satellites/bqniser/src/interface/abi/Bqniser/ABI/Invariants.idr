-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Second flagship semantic proof for Bqniser (Idris2 ABI Layer 3).
|||
||| The Layer-2 module (`Bqniser.ABI.Semantics`) proves a *fold* rewrite:
||| `+´⌽𝕩 ==> +´𝕩` (sum invariant under reverse). This module proves a
||| genuinely DIFFERENT and DEEPER property: an algebraic FUSION law over the
||| Each (`¨`) primitive — composition of maps fuses into a single map:
|||
|||   f¨ g¨ 𝕩   ==>   (f∘g)¨ 𝕩          (map fusion / Each fusion)
|||
||| This is the canonical loop-fusion rewrite BQNiser performs to eliminate an
||| intermediate array: applying `g` to every element and then `f` to every
||| element is the same as applying `f∘g` once per element. We prove:
|||
|||   1. `bmapFusion` — the headline fusion equation, by induction (∀ f g xs).
|||   2. `bmapLengthPreserving` — Each preserves array length, so the rewrite
|||      preserves shape as well as element values (a deeper structural fact
|||      the fold theorem could not express, since fold collapses the array).
|||   3. `decFuses` — a SOUND + COMPLETE decision that the fused form agrees
|||      with the staged form on a concrete input (round-trip checkable).
|||   4. A certifier into the ABI `Result`, proven sound against the law.
|||   5. A POSITIVE control (concrete fusion instance) and a NEGATIVE /
|||      non-vacuity control (`bmap` is genuinely effectful — fusing the WRONG
|||      composition order is refuted, so the law is not trivially true).
|||
||| It reuses the SAME `List Nat` model as Layer 2 — no datatype is redefined.
||| (`bmap` is named to avoid clashing with Prelude `map`.)

module Bqniser.ABI.Invariants

import Bqniser.ABI.Types
import Bqniser.ABI.Semantics
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- The Each (`¨`) primitive over the shared List Nat model
--------------------------------------------------------------------------------

||| Each (`¨`): apply a function to every element of an array.
||| Defined directly so it is convenient to induct over.
public export
bmap : (Nat -> Nat) -> List Nat -> List Nat
bmap _ []        = []
bmap f (x :: xs) = f x :: bmap f xs

||| Length, named to avoid any List/Prelude ambiguity through this module.
public export
blen : List Nat -> Nat
blen []        = 0
blen (_ :: xs) = S (blen xs)

--------------------------------------------------------------------------------
-- Layer-3 theorem 1: map fusion (the headline algebraic law)
--------------------------------------------------------------------------------

||| Fusion: mapping `g` then `f` equals mapping `f ∘ g` in a single pass.
||| Proven by induction over the array; semantics-preserving for all inputs.
export
bmapFusion : (f : Nat -> Nat) -> (g : Nat -> Nat) -> (xs : List Nat) ->
             bmap f (bmap g xs) = bmap (\x => f (g x)) xs
bmapFusion _ _ []        = Refl
bmapFusion f g (x :: xs) = cong (f (g x) ::) (bmapFusion f g xs)

--------------------------------------------------------------------------------
-- Layer-3 theorem 2: Each preserves length (structural soundness)
--------------------------------------------------------------------------------

||| Each preserves array length: the rewrite is shape-preserving, not just
||| value-preserving. This is strictly deeper than the fold theorem, whose
||| result is a scalar and therefore cannot witness shape.
export
bmapLengthPreserving : (f : Nat -> Nat) -> (xs : List Nat) ->
                       blen (bmap f xs) = blen xs
bmapLengthPreserving _ []        = Refl
bmapLengthPreserving f (x :: xs) = cong S (bmapLengthPreserving f xs)

||| Corollary: the staged form and the fused form have identical length,
||| obtained purely from the two theorems above (no fresh induction).
export
fusionLengthAgrees : (f : Nat -> Nat) -> (g : Nat -> Nat) -> (xs : List Nat) ->
                     blen (bmap f (bmap g xs)) = blen (bmap (\x => f (g x)) xs)
fusionLengthAgrees f g xs = cong blen (bmapFusion f g xs)

--------------------------------------------------------------------------------
-- A sound + complete decision for fusion-agreement on a concrete input
--------------------------------------------------------------------------------

||| Decide whether the staged form and the fused form agree on a given input.
||| By `bmapFusion` they ALWAYS agree, so this is a total `Yes`; the point is
||| that it is genuinely a `Dec` of the propositional equality (sound: the
||| `Yes` carries a real proof; complete: a `No` is impossible to construct,
||| witnessed by the proof itself rather than by fiat).
public export
decFuses : (f : Nat -> Nat) -> (g : Nat -> Nat) -> (xs : List Nat) ->
           Dec (bmap f (bmap g xs) = bmap (\x => f (g x)) xs)
decFuses f g xs = Yes (bmapFusion f g xs)

||| Completeness of the decision: there is no input on which the agreement
||| fails. Anything purporting to refute fusion is itself refuted.
export
decFusesComplete : (f : Nat -> Nat) -> (g : Nat -> Nat) -> (xs : List Nat) ->
                   Not (Not (bmap f (bmap g xs) = bmap (\x => f (g x)) xs))
decFusesComplete f g xs contra = contra (bmapFusion f g xs)

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound against the fusion law
--------------------------------------------------------------------------------

||| The fusion rewrite is unconditionally valid, so the certifier reports `Ok`.
public export
certifyFusion : (Nat -> Nat) -> (Nat -> Nat) -> List Nat -> Result
certifyFusion _ _ _ = Ok

||| Soundness: whenever the certifier reports `Ok`, the fused rewrite genuinely
||| computes the same array as the staged form for that input.
export
certifyFusionSound : (f : Nat -> Nat) -> (g : Nat -> Nat) -> (xs : List Nat) ->
                     certifyFusion f g xs = Ok ->
                     bmap f (bmap g xs) = bmap (\x => f (g x)) xs
certifyFusionSound f g xs _ = bmapFusion f g xs

--------------------------------------------------------------------------------
-- Positive control: a concrete fusion instance, machine-checked
--------------------------------------------------------------------------------

||| Doubling then incrementing every element, in two passes, equals doing
||| `(+1) ∘ (*2)` in one pass, over a concrete array.
export
fusionConcrete : bmap (\x => x + 1) (bmap (\x => x * 2) [1, 2, 3])
                 = bmap (\x => (x * 2) + 1) [1, 2, 3]
fusionConcrete = bmapFusion (\x => x + 1) (\x => x * 2) [1, 2, 3]

||| The fused result is exactly what we expect (fully reduced, asserted by Refl).
export
fusionConcreteValue : bmap (\x => (x * 2) + 1) [1, 2, 3] = [3, 5, 7]
fusionConcreteValue = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Non-vacuity: fusion is order-sensitive. Mapping `(*2)` then `(+1)` is NOT
||| the same as mapping `(+1)` then `(*2)` on this input — i.e. the law genuinely
||| depends on composing in the right order, it is not "any two maps fuse to
||| anything". This refutes the WRONG fusion and proves the theorem has content.
export
fusionOrderMatters :
  Not (bmap (\x => x + 1) (bmap (\x => x * 2) [1])
       = bmap (\x => x * 2) (bmap (\x => x + 1) [1]))
fusionOrderMatters Refl impossible

||| Second non-vacuity control: `bmap` is not the constant-empty function —
||| it actually produces a non-empty array from a non-empty input, so the
||| length-preservation theorem is not vacuously about empty lists.
export
bmapNonTrivial : Not (bmap (\x => x + 1) [5] = [])
bmapNonTrivial Refl impossible
