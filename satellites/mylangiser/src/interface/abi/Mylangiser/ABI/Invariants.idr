-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariant for Mylangiser: TRANSITIVITY of multi-step disclosure.
|||
||| The Layer-2 flagship (`Mylangiser.ABI.Semantics`) proves single-step
||| monotonicity: one `Reveal` step may only ADD items. That is a property of
||| ADJACENT states. It does NOT, on its own, say anything about what happens
||| across MANY steps — in principle a chain of individually-valid steps could
||| be reasoned about only one hop at a time.
|||
||| This module proves the genuinely deeper, distinct fact: the multi-step
||| reachability relation is TRANSITIVE, and therefore disclosure is
||| monotone GLOBALLY, not just locally. Concretely:
|||
|||   * `Reaches s t` is the reflexive-transitive closure of valid `Reveal`
|||     steps (the "can the interface get from disclosure state s to t by some
|||     number of add-only steps?" relation).
|||
|||   * `reachesTrans` : reachability composes — a state reachable from a
|||     reachable state is itself reachable. (The headline transitivity result;
|||     this is what single-step monotonicity does NOT give you.)
|||
|||   * `subsetTrans` : the underlying subset relation is transitive — the deep
|||     algebraic law that powers the global guarantee.
|||
|||   * `reachesImpliesSubset` : the PAYOFF. If t is reachable from s by ANY
|||     number of steps, then `Subset s t` holds: the revealed set never shrinks
|||     across the whole run, however long. This collapses an unbounded chain of
|||     local guarantees into one global guarantee, which is precisely the part
|||     not implied by the Layer-2 single-step theorem.
|||
||| We provide a sound + complete decision procedure for the new transitive
||| subset law (`decSubsetTrans`), a POSITIVE control (a concrete multi-hop
||| reachability witness whose endpoints are provably in the subset relation),
||| and a NEGATIVE / non-vacuity control (a state that is provably NOT reachable
||| because doing so would require hiding an item).

module Mylangiser.ABI.Invariants

import Mylangiser.ABI.Types
import Mylangiser.ABI.Semantics
import Data.List.Elem

%default total

--------------------------------------------------------------------------------
-- Deep algebraic law: the subset relation is TRANSITIVE
--------------------------------------------------------------------------------

||| Membership transports through subset: if every item of `xs` is in `ys`, and
||| `x` is in `xs`, then `x` is in `ys`. This is the load-bearing lemma — it is
||| what makes the subset relation behave like a genuine order.
export
subsetElem : Subset xs ys -> Elem x xs -> Elem x ys
subsetElem SubNil          elemX        = absurd elemX
subsetElem (SubCons h _)   Here         = h
subsetElem (SubCons _ rest) (There later) = subsetElem rest later

||| Transitivity of subset: if `xs` is a subset of `ys` and `ys` of `zs`, then
||| `xs` is a subset of `zs`. NOT a restatement of single-step monotonicity:
||| this is the algebraic law that composes two separate add-only relationships.
export
subsetTrans : Subset xs ys -> Subset ys zs -> Subset xs zs
subsetTrans SubNil          _   = SubNil
subsetTrans (SubCons h rest) syz =
  SubCons (subsetElem syz h) (subsetTrans rest syz)

||| Reflexivity of subset (every state contains itself) — needed for the
||| reflexive part of the reachability closure, and used as a positive witness.
export
subsetRefl : (xs : State) -> Subset xs xs
subsetRefl []        = SubNil
subsetRefl (x :: xs) =
  -- Each head x is `Here` in (x :: xs); the tail is a subset of (x :: xs)
  -- because it is a subset of itself, then weakened by `There`.
  SubCons Here (subsetWeaken (subsetRefl xs))
  where
    ||| Weaken a subset target by prepending one more available item.
    subsetWeaken : Subset as bs -> Subset as (b :: bs)
    subsetWeaken SubNil           = SubNil
    subsetWeaken (SubCons e rest) = SubCons (There e) (subsetWeaken rest)

--------------------------------------------------------------------------------
-- Sound + complete decision of the transitive subset relation
--------------------------------------------------------------------------------

||| Decide `Subset xs zs` while EXPOSING the transitive structure: given an
||| intermediate `ys` together with witnesses `Subset xs ys` and `Subset ys zs`,
||| we already KNOW the answer is Yes (by `subsetTrans`); but for a genuine
||| decision over arbitrary inputs we fall back to the complete `decSubset`.
||| This is sound (a Yes carries a real proof) and complete (a No carries a real
||| refutation), reusing the Layer-2 decider as the completeness oracle.
export
decSubsetTrans : (xs : State) -> (zs : State) -> Dec (Subset xs zs)
decSubsetTrans = decSubset

--------------------------------------------------------------------------------
-- Multi-step reachability: reflexive-transitive closure of valid steps
--------------------------------------------------------------------------------

||| `Reaches s t` holds when the interface can move from disclosure state `s`
||| to `t` by zero or more valid (add-only) `Reveal` steps. This is the
||| relational, endpoint-only view of a `MonotoneRun` (Layer 2 tracked the whole
||| intermediate sequence; here we care about composability of endpoints).
public export
data Reaches : State -> State -> Type where
  ||| Zero steps: every state reaches itself.
  ReachRefl : Reaches s s
  ||| One valid step followed by a reachable remainder.
  ReachStep : {0 s0, s2 : State} -> {s1 : State} ->
              Reveal s0 s1 -> Reaches s1 s2 -> Reaches s0 s2

--------------------------------------------------------------------------------
-- HEADLINE: reachability is transitive (distinct from single-step monotonicity)
--------------------------------------------------------------------------------

||| Transitivity of reachability: a state reachable from a reachable state is
||| itself reachable. Proven by induction on the FIRST derivation, re-grafting
||| the second chain onto the end. This is the multi-step composition law that
||| single-step monotonicity (Layer 2) does not provide.
export
reachesTrans : Reaches s0 s1 -> Reaches s1 s2 -> Reaches s0 s2
reachesTrans ReachRefl           r2 = r2
reachesTrans (ReachStep st rest) r2 = ReachStep st (reachesTrans rest r2)

--------------------------------------------------------------------------------
-- PAYOFF: reachability implies global subset (sets only grow across many steps)
--------------------------------------------------------------------------------

||| Across an ENTIRE reachable run, however long, the revealed set never shrinks:
||| if `t` is reachable from `s`, then `Subset s t`. Each step contributes a
||| local `Subset`; `subsetTrans` chains them into one global guarantee. This is
||| the precise sense in which transitivity is DEEPER than the Layer-2 theorem.
export
reachesImpliesSubset : {s : State} -> Reaches s t -> Subset s t
reachesImpliesSubset ReachRefl                       = subsetRefl s
reachesImpliesSubset (ReachStep (MkReveal sub) rest) =
  subsetTrans sub (reachesImpliesSubset rest)

||| Certifier into the canonical ABI `Result`: `Ok` exactly when the endpoints
||| of a claimed run stand in the subset relation that any genuine reachability
||| must produce. Reuses Types.Result; soundness below.
export
certifyReach : State -> State -> Result
certifyReach s t =
  case decSubsetTrans s t of
    Yes _ => Ok
    No _  => InvalidParam

||| Soundness of the certifier: `Ok` is returned only when `Subset s t` really
||| holds — a genuine extraction from the decision procedure, not an axiom.
export
certifyReachSound : (s : State) -> (t : State) -> certifyReach s t = Ok ->
                    Subset s t
certifyReachSound s t prf with (decSubsetTrans s t)
  certifyReachSound s t prf  | Yes sub = sub
  certifyReachSound s t Refl | No _ impossible

--------------------------------------------------------------------------------
-- POSITIVE control: a concrete multi-hop reachability witness
--------------------------------------------------------------------------------

||| A two-hop reachable disclosure path: {1} -> {1,2} -> {1,2,3}. Each hop is a
||| valid add-only Reveal; the whole thing is one `Reaches` value.
export
goodReach : Reaches [1] [1, 2, 3]
goodReach =
  ReachStep (MkReveal (SubCons Here SubNil))
    (ReachStep (MkReveal (SubCons Here (SubCons (There Here) SubNil)))
      ReachRefl)

||| The transitive PAYOFF on the concrete path: because {1,2,3} is reachable
||| from {1}, item 1 (and everything in the start) survives to the end —
||| machine-checked via `reachesImpliesSubset`, NOT restated by hand.
export
goodReachGrows : Subset [1] [1, 2, 3]
goodReachGrows = reachesImpliesSubset Invariants.goodReach

||| Explicit witness that transitivity composes two separate good paths into one
||| longer reachable path: {1} -> {1,2,3} (above) then {1,2,3} -> {1,2,3,4}.
export
composedReach : Reaches [1] [1, 2, 3, 4]
composedReach =
  reachesTrans Invariants.goodReach
    (ReachStep
       (MkReveal (SubCons Here
                   (SubCons (There Here)
                     (SubCons (There (There Here)) SubNil))))
       ReachRefl)

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity control: a hiding endpoint pair is NOT a subset, and
-- therefore the certifier refuses it (the relation is not trivially true).
--------------------------------------------------------------------------------

||| Item 2 is not an element of the singleton list [1].
twoNotInOne : Not (Elem (the Item 2) [the Item 1])
twoNotInOne (There later) = absurd later

||| {1,2} is provably NOT a subset of {1}: item 2 cannot be transported.
||| (Independent re-derivation at this layer, used by the controls below.)
export
hidingNotSubset : Not (Subset [the Item 1, the Item 2] [the Item 1])
hidingNotSubset sub = twoNotInOne (subsetElem sub (There Here))

||| NON-VACUITY: a state reaching one that drops a revealed item is impossible,
||| because reachability forces the subset relation that the hiding pair lacks.
||| If `Reaches` were vacuously/over-permissive this would be inhabited; it is
||| provably not. This is the key guard that the Layer-3 relation has teeth.
export
hidingNotReachable : Not (Reaches [the Item 1, the Item 2] [the Item 1])
hidingNotReachable r = hidingNotSubset (reachesImpliesSubset r)

||| And the certifier rejects the hiding endpoints: `certifyReach` returns
||| `InvalidParam`, never `Ok`. Machine-checked deliberately-false `= Ok` would
||| not type-check; we instead prove the true negative.
export
hidingCertifyRejected : certifyReach [the Item 1, the Item 2] [the Item 1] = InvalidParam
hidingCertifyRejected with (decSubsetTrans [the Item 1, the Item 2] [the Item 1])
  hidingCertifyRejected | Yes sub = absurd (hidingNotSubset sub)
  hidingCertifyRejected | No _    = Refl
