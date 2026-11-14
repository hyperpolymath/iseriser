-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Mylangiser.
|||
||| Headline: "Generate progressive-disclosure interfaces via My-Lang".
|||
||| We model a progressive-disclosure interface as a *sequence of revealed-item
||| sets* (each step reveals more of the API to the user). The defining safety
||| property of progressive disclosure is MONOTONICITY: a disclosure step may
||| only ADD revealed items, never REMOVE a previously-shown one. An interface
||| that hides an item the user has already seen is disorienting and breaks the
||| progressive-disclosure contract.
|||
||| We make this property a *type*: a transition `Reveal before after` only has
||| an inhabitant when `before` is a subset of `after`. A step that hides a
||| previously-revealed item is then provably NOT a valid transition
||| (negative control), while a genuine add-only step has an explicit witness
||| (positive control). A whole disclosure run is `MonotoneRun`, the reflexive-
||| transitive closure of valid steps; we provide a sound + complete decision
||| procedure `decRun`, a certifier into `Result`, and a soundness lemma.

module Mylangiser.ABI.Semantics

import Mylangiser.ABI.Types
import Data.List
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Domain model: revealed-item sets
--------------------------------------------------------------------------------

||| An item identifier exposed in the interface (e.g. a parameter or feature).
||| We use Nat ids so equality is decidable and lists reduce on literals.
public export
Item : Type
Item = Nat

||| A disclosure state is the set of items currently revealed, modelled as a
||| list of item ids. (Order is irrelevant to the property; membership is what
||| matters.)
public export
State : Type
State = List Item

||| A disclosure run is the ordered sequence of states the interface passes
||| through as the user progresses.
public export
Run : Type
Run = List State

--------------------------------------------------------------------------------
-- Subset relation (the heart of monotonicity)
--------------------------------------------------------------------------------

||| `Subset xs ys` holds when every item revealed in `xs` is also revealed in
||| `ys`. This is the "add-only" guarantee at the level of a single step.
public export
data Subset : State -> State -> Type where
  ||| The empty state is a subset of anything (nothing to preserve).
  SubNil  : Subset [] ys
  ||| If the head is still revealed in `ys` and the tail is preserved, the whole
  ||| state is preserved.
  SubCons : Elem x ys -> Subset xs ys -> Subset (x :: xs) ys

--------------------------------------------------------------------------------
-- Valid disclosure transition: a step may only ADD items
--------------------------------------------------------------------------------

||| `Reveal before after` is the type of *valid* progressive-disclosure steps.
||| There is exactly ONE constructor, and it demands `Subset before after`:
||| every item visible before must still be visible after. There is NO
||| constructor that lets a step drop a revealed item.
public export
data Reveal : State -> State -> Type where
  MkReveal : Subset before after -> Reveal before after

||| A monotone run: the reflexive-transitive closure of valid steps over the
||| sequence of states. An empty or single-state run is trivially monotone;
||| each adjacent pair must be a valid `Reveal`.
public export
data MonotoneRun : Run -> Type where
  ||| The empty run is monotone.
  RunNil  : MonotoneRun []
  ||| A single-state run is monotone (no transitions to check).
  RunOne  : MonotoneRun [s]
  ||| Prepend a valid step onto a monotone tail.
  RunStep : Reveal s0 s1 -> MonotoneRun (s1 :: rest) ->
            MonotoneRun (s0 :: s1 :: rest)

--------------------------------------------------------------------------------
-- Decision procedure for Subset (sound + complete)
--------------------------------------------------------------------------------

||| If a cons-state is a subset, so is its tail. (Inversion lemma.)
subsetTail : Subset (x :: xs) ys -> Subset xs ys
subsetTail (SubCons _ rest) = rest

||| If a cons-state is a subset, its head is a member of the target.
subsetHead : Subset (x :: xs) ys -> Elem x ys
subsetHead (SubCons e _) = e

||| Decide whether `xs` is a subset of `ys`. Returns a real proof or a real
||| refutation for every input.
public export
decSubset : (xs : State) -> (ys : State) -> Dec (Subset xs ys)
decSubset [] ys = Yes SubNil
decSubset (x :: xs) ys =
  case isElem x ys of
    No notThere => No (\sub => notThere (subsetHead sub))
    Yes there =>
      case decSubset xs ys of
        Yes rest => Yes (SubCons there rest)
        No notRest => No (\sub => notRest (subsetTail sub))

--------------------------------------------------------------------------------
-- Decision procedure for a valid step
--------------------------------------------------------------------------------

||| Decide whether a single step `before -> after` is a valid (add-only)
||| disclosure transition.
public export
decReveal : (before : State) -> (after : State) -> Dec (Reveal before after)
decReveal before after =
  case decSubset before after of
    Yes sub => Yes (MkReveal sub)
    No notSub => No (\(MkReveal sub) => notSub sub)

--------------------------------------------------------------------------------
-- Decision procedure for a whole run
--------------------------------------------------------------------------------

||| Inversion: the tail of a monotone run is itself monotone.
runTail : MonotoneRun (s0 :: s1 :: rest) -> MonotoneRun (s1 :: rest)
runTail (RunStep _ tl) = tl

||| Inversion: the leading step of a monotone run is a valid Reveal.
runStepHead : MonotoneRun (s0 :: s1 :: rest) -> Reveal s0 s1
runStepHead (RunStep r _) = r

||| Worker for `decRun`: decides monotonicity of the run `prev :: rest`,
||| recursing structurally on `rest` (which strictly decreases each step), so
||| totality is manifest to the checker.
decRunFrom : (prev : State) -> (rest : Run) -> Dec (MonotoneRun (prev :: rest))
decRunFrom prev [] = Yes RunOne
decRunFrom prev (s1 :: more) =
  case decReveal prev s1 of
    No notStep => No (\mr => notStep (runStepHead mr))
    Yes step =>
      case decRunFrom s1 more of
        Yes tl => Yes (RunStep step tl)
        No notTl => No (\mr => notTl (runTail mr))

||| Decide whether a run is monotone. Sound + complete.
public export
decRun : (r : Run) -> Dec (MonotoneRun r)
decRun [] = Yes RunNil
decRun (s0 :: rest) = decRunFrom s0 rest

--------------------------------------------------------------------------------
-- Certifier into the ABI Result type + soundness
--------------------------------------------------------------------------------

||| Certify a run: `Ok` exactly when the run is monotone, `InvalidParam`
||| otherwise. (Reuses the canonical ABI `Result` from Types.)
public export
certifyRun : Run -> Result
certifyRun r =
  case decRun r of
    Yes _ => Ok
    No _  => InvalidParam

||| Soundness: whenever the certifier says `Ok`, the run really is monotone.
||| This is a genuine extraction from the decision procedure, not an axiom.
public export
certifyRunSound : (r : Run) -> certifyRun r = Ok -> MonotoneRun r
certifyRunSound r prf with (decRun r)
  certifyRunSound r prf       | Yes mr = mr
  certifyRunSound r Refl      | No _ impossible

--------------------------------------------------------------------------------
-- POSITIVE control: a genuine add-only disclosure run has a witness
--------------------------------------------------------------------------------

||| A concrete progressive-disclosure run that only ever adds items:
|||   {1}  ->  {1,2}  ->  {1,2,3}
||| modelling Beginner -> Intermediate -> Expert with strictly growing surface.
public export
goodRun : Run
goodRun = [[1], [1, 2], [1, 2, 3]]

||| The good run is monotone — explicit, machine-checked witness.
public export
goodRunMonotone : MonotoneRun Semantics.goodRun
goodRunMonotone =
  RunStep (MkReveal (SubCons Here SubNil))
    (RunStep (MkReveal (SubCons Here (SubCons (There Here) SubNil)))
      RunOne)

--------------------------------------------------------------------------------
-- NEGATIVE control: a step that HIDES a revealed item is NOT a valid transition
--------------------------------------------------------------------------------

||| A run that hides a previously-revealed item: {1,2} -> {1}. Item 2 was shown
||| then taken away — this violates progressive disclosure.
public export
hidingRun : Run
hidingRun = [[1, 2], [1]]

||| The single step {1,2} -> {1} is provably NOT a valid Reveal: there is no
||| way for item 2 (member of the before-state) to be a member of [1].
||| This is the headline non-vacuity guarantee, machine-checked.
public export
hidingStepInvalid : Not (Reveal [1, 2] [1])
hidingStepInvalid (MkReveal sub) = twoNotInOne (subsetHead (subsetTail2 sub))
  where
    ||| Item 2 is not an element of the singleton list [1].
    twoNotInOne : Elem (the Item 2) [the Item 1] -> Void
    twoNotInOne (There later) = absurd later
    -- `Here` would require 2 = 1, which is impossible, so the only remaining
    -- case is `There`, whose argument is `Elem 2 []` (uninhabited).

    ||| Drop the head of a Subset whose source is `1 :: 2 :: xs`, exposing the
    ||| subset proof for `2 :: xs`.
    subsetTail2 : Subset (the Item 1 :: the Item 2 :: xs) ys ->
                  Subset (the Item 2 :: xs) ys
    subsetTail2 (SubCons _ rest) = rest

||| Therefore the whole hiding run is NOT monotone.
public export
hidingRunNotMonotone : Not (MonotoneRun Semantics.hidingRun)
hidingRunNotMonotone mr = hidingStepInvalid (runStepHead mr)
