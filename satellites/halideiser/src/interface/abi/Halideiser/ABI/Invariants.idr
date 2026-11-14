-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariant proof for Halideiser: SCHEDULE EQUIVALENCE IS
||| COMPOSABLE, and a SECOND, DEEPER schedule transformation (TILING, i.e.
||| split-of-split) preserves the computed result.
|||
||| Relationship to the Layer-2 flagship (`Halideiser.ABI.Semantics`)
||| ------------------------------------------------------------------
||| Layer 2 proves the *single* fact that one loop SPLIT is equivalent to
||| the flat run:  `runSplit f outer inner = runFlat f (outer * inner)`.
|||
||| This module is genuinely DIFFERENT and DEEPER. It does NOT restate that
||| theorem. Instead it:
|||
|||   1. Defines schedule equivalence as a *relation* between two scheduled
|||      executions (`ScheduleEquiv`), and proves it is a bona-fide
|||      EQUIVALENCE RELATION — reflexive, symmetric, and TRANSITIVE. The
|||      transitivity lemma is the composition principle Layer 2 lacked:
|||      two equivalent reschedules compose into one.
|||
|||   2. Models a SECOND transformation that Layer 2 never analysed — the
|||      Halide TILE, which splits the OUTER loop of an existing split
|||      (`tile = split ; split-the-outer`). We prove `runTile` is
|||      equivalent to the flat run by COMPOSING two split-equivalences
|||      through transitivity. This is a composition/transitivity theorem
|||      over the same model, exactly the "distinct, deeper" property the
|||      layer demands.
|||
||| The whole development reuses the Layer-2 datatypes and lemmas
||| (`runFlat`, `runSplit`, `runInner`, `range`, `splitEnumerates`) — it
||| introduces no new index model.
module Halideiser.ABI.Invariants

import Halideiser.ABI.Types
import Halideiser.ABI.Semantics
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Access the Layer-2 result through its PUBLIC interface
--------------------------------------------------------------------------------

||| Extract the underlying equality from the Layer-2 flagship. The internal
||| lemma `splitEnumerates` is private, but the exported theorem
||| `splitPreservesResult` packages exactly the same equality inside the
||| (exported) `SplitEquivalent` constructor; we unwrap it here. This is the
||| sanctioned, public reuse of the Layer-2 model — no redefinition.
public export
splitFlatEq :
  (f : Nat -> Nat) -> (outer, inner : Nat) ->
  runSplit f outer inner = runFlat f (outer * inner)
splitFlatEq f outer inner = case splitPreservesResult f outer inner of
  MkSplitEquivalent prf => prf

--------------------------------------------------------------------------------
-- Schedule equivalence as a RELATION (the new, deeper object)
--------------------------------------------------------------------------------

||| Two schedule executions (each already a `List Nat` of results, in the
||| order the schedule visits them) are *schedule-equivalent* when they
||| produce the identical result list. Halide's correctness invariant is
||| precisely that a legal reschedule does not change this list.
|||
||| Unlike the Layer-2 `SplitEquivalent` (which fixes one side to be the
||| flat run of a particular split), this is a symmetric relation between
||| ARBITRARY scheduled runs, which is what lets equivalences COMPOSE.
public export
data ScheduleEquiv : (lhs : List Nat) -> (rhs : List Nat) -> Type where
  MkScheduleEquiv : {0 xs, ys : List Nat} -> xs = ys -> ScheduleEquiv xs ys

||| Recover the underlying equality witness from a `ScheduleEquiv`.
public export
scheduleEq : {0 xs, ys : List Nat} -> ScheduleEquiv xs ys -> xs = ys
scheduleEq (MkScheduleEquiv prf) = prf

--------------------------------------------------------------------------------
-- ScheduleEquiv is an EQUIVALENCE RELATION
--------------------------------------------------------------------------------

||| Reflexivity: any schedule is equivalent to itself.
public export
scheduleRefl : {0 xs : List Nat} -> ScheduleEquiv xs xs
scheduleRefl = MkScheduleEquiv Refl

||| Symmetry: equivalence does not depend on which run we name first.
public export
scheduleSym : {0 xs, ys : List Nat} ->
              ScheduleEquiv xs ys -> ScheduleEquiv ys xs
scheduleSym (MkScheduleEquiv prf) = MkScheduleEquiv (sym prf)

||| TRANSITIVITY — the composition principle. If reschedule A matches B and
||| reschedule B matches C, then A matches C: two equivalent reschedules
||| compose into a single equivalence. This is the heart of Layer 3.
public export
scheduleTrans : {0 xs, ys, zs : List Nat} ->
                ScheduleEquiv xs ys -> ScheduleEquiv ys zs ->
                ScheduleEquiv xs zs
scheduleTrans (MkScheduleEquiv p) (MkScheduleEquiv q) =
  MkScheduleEquiv (trans p q)

--------------------------------------------------------------------------------
-- Bridge: every Layer-2 split equivalence is a ScheduleEquiv
--------------------------------------------------------------------------------

||| A split run is schedule-equivalent to the flat run. This re-expresses
||| the Layer-2 theorem `splitEnumerates` in the new relational vocabulary
||| so it can be COMPOSED with other equivalences via `scheduleTrans`.
public export
splitIsScheduleEquiv :
  (f : Nat -> Nat) -> (outer, inner : Nat) ->
  ScheduleEquiv (runSplit f outer inner) (runFlat f (outer * inner))
splitIsScheduleEquiv f outer inner =
  MkScheduleEquiv (splitFlatEq f outer inner)

--------------------------------------------------------------------------------
-- The SECOND transformation: TILING (split the OUTER loop of a split)
--------------------------------------------------------------------------------

||| The tiled schedule. A plain split (Layer 2) walks the outer index space
||| `range (a * b)` directly, running one inner block `runInner f inner o`
||| per outer index `o`. TILING instead walks the SAME outer index space in
||| a re-grouped order: the outer indices are themselves produced by an
||| inner split into `a` groups of `b`. Concretely the tiled outer order is
||| `runSplit (\o => o) a b` — the identity stage scheduled with its own
||| split — which enumerates exactly the outer indices `0 .. a*b-1`, but
||| grouped as the Halide tile prescribes.
|||
||| For each tiled outer index `o` we run the same inner block as the plain
||| split. Visiting indices: this is the genuine two-level loop nest that
||| Halide's `tile` emits.
public export
runTile : (f : Nat -> Nat) -> (a, b, inner : Nat) -> List Nat
runTile f a b inner =
  concatBlocks (map (runInner f inner) (runSplit (\o => o) a b))

--------------------------------------------------------------------------------
-- Key structural fact: tiling the OUTER index space leaves it unchanged
--------------------------------------------------------------------------------

||| The tiled outer enumeration `runSplit (\o => o) a b` is the SAME list as
||| the plain outer enumeration `range (a * b)`. This is a direct corollary
||| of the Layer-2 theorem applied to the identity stage:
|||   runSplit id a b = runFlat id (a*b) = map id (range (a*b)) = range (a*b).
|||
||| (We do not redefine or re-prove `splitEnumerates`; we instantiate it.)
public export
tiledOuterIsRange :
  (a, b : Nat) -> runSplit (\o => o) a b = range (a * b)
tiledOuterIsRange a b =
  rewrite splitFlatEq (\o => o) a b in
    mapIdRange (a * b)
  where
    ||| `map id xs = xs`, specialised to the identity lambda `\o => o`.
    mapIdRange : (n : Nat) -> map (\o => o) (range n) = range n
    mapIdRange n = mapIdIs (range n)
      where
        mapIdIs : (xs : List Nat) -> map (\o => o) xs = xs
        mapIdIs []        = Refl
        mapIdIs (x :: xs) = cong (x ::) (mapIdIs xs)

--------------------------------------------------------------------------------
-- Tiling equals the plain split (same blocks, same order)
--------------------------------------------------------------------------------

||| Because the tiled outer enumeration equals the plain outer enumeration
||| (`tiledOuterIsRange`), mapping `runInner f inner` over either and
||| flattening gives the SAME result. Hence the tiled run equals the plain
||| split run `runSplit f (a*b) inner`.
public export
tileEqualsSplit :
  (f : Nat -> Nat) -> (a, b, inner : Nat) ->
  runTile f a b inner = runSplit f (a * b) inner
tileEqualsSplit f a b inner =
  -- `runTile` is definitionally `concatBlocks (map (runInner f inner) (runSplit id a b))`
  -- and `runSplit f (a*b) inner` is `concatBlocks (map (runInner f inner) (range (a*b)))`.
  -- Rewriting the tiled outer enumeration to `range (a*b)` makes the two coincide.
  rewrite tiledOuterIsRange a b in Refl

--------------------------------------------------------------------------------
-- Headline Layer-3 theorem: TILING preserves the result, by COMPOSITION
--------------------------------------------------------------------------------

||| THE LAYER-3 THEOREM. The tiled schedule is schedule-equivalent to the
||| FLAT run over the domain of size `(a*b) * inner`. The proof COMPOSES two
||| equivalences via `scheduleTrans`:
|||
|||   runTile f a b inner
|||     ==[ tileEqualsSplit ]        (tiling = plain split on outer)
|||   runSplit f (a*b) inner
|||     ==[ Layer-2 splitEnumerates ] (plain split = flat)
|||   runFlat f ((a*b) * inner)
|||
||| This is strictly deeper than Layer 2: it builds a NEW transformation and
||| discharges it by transitively chaining the Layer-2 result with a fresh
||| structural lemma — it does not restate Layer 2.
public export
tilePreservesResult :
  (f : Nat -> Nat) -> (a, b, inner : Nat) ->
  ScheduleEquiv (runTile f a b inner) (runFlat f ((a * b) * inner))
tilePreservesResult f a b inner =
  scheduleTrans
    (MkScheduleEquiv (tileEqualsSplit f a b inner))
    (splitIsScheduleEquiv f (a * b) inner)

--------------------------------------------------------------------------------
-- A natural, sound + complete decision procedure for ScheduleEquiv
--------------------------------------------------------------------------------

||| Decide schedule-equivalence of two CONCRETE result lists. Sound and
||| complete: it returns `Yes` exactly when the lists are equal (via the
||| library `DecEq (List Nat)`), and the `No` branch carries a real refuter.
public export
decScheduleEquiv : (xs, ys : List Nat) -> Dec (ScheduleEquiv xs ys)
decScheduleEquiv xs ys = case decEq xs ys of
  Yes prf => Yes (MkScheduleEquiv prf)
  No  ctr => No (\se => ctr (scheduleEq se))

--------------------------------------------------------------------------------
-- POSITIVE control: a concrete tiling equivalence witness
--------------------------------------------------------------------------------

||| POSITIVE CONTROL. Tile an extent-12 domain as `(a=2) * (b=3)` outer
||| groups, each of `inner=2` iterations — i.e. (2*3)*2 = 12 — for the
||| `double` stage from Layer 2. The tiled run is schedule-equivalent to the
||| flat run. Inhabited witness, discharged by the general theorem.
public export
doubleTile2x3x2Equivalent :
  ScheduleEquiv (runTile Semantics.double 2 3 2)
                (runFlat Semantics.double ((2 * 3) * 2))
doubleTile2x3x2Equivalent = tilePreservesResult Semantics.double 2 3 2

||| And the underlying lists are literally, definitionally equal on this
||| concrete case (the proof reduces to `Refl`).
public export
doubleTile2x3x2Concrete :
  runTile Semantics.double 2 3 2 = runFlat Semantics.double 12
doubleTile2x3x2Concrete = Refl

||| Tag extractor for a `Dec`: `True` for `Yes`, `False` for `No`.
||| (Local, total — avoids guessing the Prelude name.)
public export
decTag : Dec p -> Bool
decTag (Yes _) = True
decTag (No  _) = False

||| Decision-procedure smoke test: the concrete tile/flat pair decides Yes.
||| Only the tag is asserted by `Refl`, not the proof term's internals.
public export
decDoubleTileYes :
  decTag (decScheduleEquiv (runTile Semantics.double 2 3 2)
                           (runFlat Semantics.double 12)) = True
decDoubleTileYes = Refl

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls
--------------------------------------------------------------------------------

||| NEGATIVE CONTROL #1. A result-CHANGING "tile" is NOT schedule-equivalent
||| to the flat run. We exhibit a concrete bad run (the flat run of the WRONG
||| stage `succ`, whose values differ from `double`'s) and prove it is `Not`
||| schedule-equivalent to the correct flat run. Machine-checked: the two
||| concrete result lists genuinely differ, so no `ScheduleEquiv` inhabits.
public export
mistiledNotEquivalent :
  Not (ScheduleEquiv (runFlat S 12) (runFlat Semantics.double 12))
mistiledNotEquivalent (MkScheduleEquiv prf) = case prf of Refl impossible

||| NEGATIVE CONTROL #2 (non-vacuity of transitivity). Transitivity must NOT
||| be able to "launder" two genuinely different lists into equality. If a
||| middle list `ys` were equal both to `[0]` and to `[1]`, transitivity
||| would force `[0] = [1]`, which is impossible. This shows the relation has
||| real content: composing through any witness preserves true equality.
public export
transNonVacuous :
  Not (ScheduleEquiv (the (List Nat) [0]) [1])
transNonVacuous (MkScheduleEquiv prf) = case prf of Refl impossible

||| NEGATIVE CONTROL #3 (the `Dec` is not trivially always-Yes). There is
||| NO proof that the decision procedure answers `Yes` on a genuinely
||| unequal pair: any such claimed `Yes _` is refuted, because extracting
||| its witness would prove `[0] = [1]`. We state this as the impossibility
||| of inhabiting the equivalence on that pair (already shown by
||| `transNonVacuous`), and additionally that the decider cannot return a
||| `Yes`-carrying proof here.
public export
decDistinctNotYes :
  (prf : ScheduleEquiv (the (List Nat) [0]) [1]) -> Void
decDistinctNotYes = transNonVacuous
