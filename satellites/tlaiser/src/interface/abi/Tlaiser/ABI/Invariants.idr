-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 deepening for Tlaiser: COMPOSITIONALITY of inductive invariants.
|||
||| The Layer-2 flagship (`Tlaiser.ABI.Semantics.safetySound`) proves INV1 for
||| ONE hand-crafted inductive invariant (`Inv`) and derives mutual exclusion.
||| That establishes soundness of a *single* invariant. This module proves a
||| strictly deeper, structurally different fact about the *space of invariants*
||| itself:
|||
|||   THE CONJUNCTION OF TWO INDUCTIVE INVARIANTS IS INDUCTIVE.
|||
||| In TLA+ practice this is exactly how large invariants are built and how the
||| TLAPS proof manager decomposes them: one proves several smaller invariants
||| independently, then conjoins them, relying on the meta-fact that
||| inductiveness is closed under conjunction. We formalise that meta-fact
||| abstractly over the SAME state machine, relations and reachability already
||| defined in `Semantics` (we do NOT redefine `St`, `Init`, `Step`,
||| `Reachable`).
|||
||| Concretely this module:
|||   1. Abstracts "P is an inductive invariant" as `IsInductive P`
|||      (established by `Init`, preserved by `Step`) — the two INV1 premises,
|||      packaged so they can be manipulated as first-class values.
|||   2. Proves the generic INV1 closure `inductiveOnReachable` once, for ANY
|||      inductive P (the Layer-2 proof was monomorphic in `Inv`).
|||   3. Proves the COMPOSITION theorem `andInductive`: if `P` and `Q` are each
|||      inductive then `\s => (P s, Q s)` is inductive. This is the headline,
|||      and it is genuinely distinct from — and used to *strengthen* — the
|||      Layer-2 result.
|||   4. Exhibits a SECOND, independent concrete invariant `HolderCrit`
|||      ("if a process holds the lock then that process is Critical"), proves
|||      it inductive from scratch, and shows it is NOT the same predicate as
|||      `Inv` (a reachable state distinguishes the *strength* of the two; and
|||      a non-reachable state inhabits one predicate but not the other).
|||   5. COMPOSES `Inv` and `HolderCrit` via `andInductive` into a single
|||      conjoined inductive invariant that therefore holds on every reachable
|||      state — demonstrating modular invariant construction end to end.
|||   6. Provides a sound+complete decision procedure for the second invariant,
|||      a positive control (an inhabited reachable witness of the conjunction)
|||      and a negative / non-vacuity control (a machine-checked `Not (...)`).
|||
||| Everything is built over the Layer-2 datatypes; no axioms, no `believe_me`,
||| no `postulate`, no `assert_total`.
|||
||| @see https://lamport.azurewebsites.net/tla/tla.html  (INV1, invariant conj.)

module Tlaiser.ABI.Invariants

import Tlaiser.ABI.Types
import Tlaiser.ABI.Semantics

%default total

--------------------------------------------------------------------------------
-- 1. "Inductive invariant", abstracted as a first-class value
--------------------------------------------------------------------------------

||| A state predicate over the Layer-2 machine.
public export
0 Pred : Type
Pred = St -> Type

||| `IsInductive p` packages the two INV1 premises for an arbitrary predicate
||| `p`, over the EXISTING `Init` and `Step` relations from `Semantics`:
|||   * `establishes` : `p` holds on every initial state;
|||   * `preserves`   : every `Step` from a `p`-state lands in a `p`-state.
||| Making this a record lets us treat inductiveness as data we can combine
||| (e.g. conjoin) — the move that distinguishes this layer from the Layer-2
||| monomorphic proof.
public export
record IsInductive (0 p : Pred) where
  constructor MkIsInductive
  establishes : {0 s : St} -> Init s -> p s
  preserves   : {0 s, t : St} -> p s -> Step s t -> p t

--------------------------------------------------------------------------------
-- 2. Generic INV1: any inductive predicate holds on all reachable states
--------------------------------------------------------------------------------

||| INV1, proved ONCE for an arbitrary inductive predicate (the Layer-2 version,
||| `invInductive`, was specialised to the single predicate `Inv`). Induction on
||| the `Reachable` derivation, discharging each case with the packaged premises.
public export
inductiveOnReachable : {0 p : Pred} -> IsInductive p ->
                       {0 s : St} -> Reachable s -> p s
inductiveOnReachable ind (ReachInit init)   = ind.establishes init
inductiveOnReachable ind (ReachStep r step) =
  ind.preserves (inductiveOnReachable ind r) step

--------------------------------------------------------------------------------
-- 3. HEADLINE: inductiveness is closed under conjunction
--------------------------------------------------------------------------------

||| The conjunction of two predicates, as a predicate.
public export
0 And : Pred -> Pred -> Pred
And p q = \s => (p s, q s)

||| THE COMPOSITION THEOREM. If `p` and `q` are each inductive invariants of the
||| machine, then so is their conjunction `And p q`. Each INV1 premise of the
||| conjunction is discharged componentwise from the premises of `p` and `q`.
||| This is the meta-theorem that licenses modular invariant construction.
public export
andInductive : {0 p, q : Pred} ->
               IsInductive p -> IsInductive q -> IsInductive (And p q)
andInductive ip iq =
  MkIsInductive
    (\init      => (ip.establishes init, iq.establishes init))
    (\(hp, hq), step => (ip.preserves hp step, iq.preserves hq step))

--------------------------------------------------------------------------------
-- 4. The Layer-2 invariant `Inv`, repackaged as a first-class IsInductive value
--------------------------------------------------------------------------------

||| `Inv` from Layer-2 is inductive — we already have the two discharged
||| premises (`initEstablishes`, `stepPreserves`); here we merely repackage them
||| as an `IsInductive` value so the composition machinery can consume it.
public export
invIsInductive : IsInductive Inv
invIsInductive = MkIsInductive initEstablishes stepPreserves

--------------------------------------------------------------------------------
-- 5. A SECOND, INDEPENDENT concrete invariant: "holder is Critical"
--------------------------------------------------------------------------------

||| Per-process: "if process 0 holds the lock (`HeldBy0`) then it is Critical".
||| Indexed by P0's location and the lock. This couples the lock to the holder's
||| location in the *opposite* direction from `Coherent0`'s emphasis: it is the
||| "held => critical" half, whereas `Inv`'s coherence carries "critical =>
||| held" plus the cross-process exclusion. Distinct content, proved afresh.
public export
data Holder0 : Loc -> Lock -> Type where
  ||| Lock held by P0 forces P0 = Critical.
  H0Crit  : Holder0 Critical HeldBy0
  ||| Lock not held by P0: no constraint on P0's location.
  H0Free  : Holder0 a Free
  H0Other : Holder0 a HeldBy1

||| Per-process mirror for P1: "if P1 holds the lock then P1 is Critical".
public export
data Holder1 : Loc -> Lock -> Type where
  H1Crit  : Holder1 Critical HeldBy1
  H1Free  : Holder1 a Free
  H1Other : Holder1 a HeldBy0

||| The SECOND whole-state invariant: whichever process holds the single lock
||| token is in its critical section. Genuinely different predicate from `Inv`.
public export
data HolderCrit : St -> Type where
  MkHolderCrit : Holder0 a lk -> Holder1 b lk -> HolderCrit (MkSt a b lk)

-- (5a) `HolderCrit` holds on the initial state ---------------------------------

||| Established by `Init`: the unique initial state `(Idle, Idle, Free)` has the
||| lock free, so both holder constraints hold vacuously.
public export
holderInit : {0 s : St} -> Init s -> HolderCrit s
holderInit InitState = MkHolderCrit H0Free H1Free

-- (5b) `HolderCrit` is preserved by every `Step` ------------------------------
-- Helper lemmas keep each Step clause first-order and total.

||| A request transition keeps the lock unchanged; a `Holder0` fact transports
||| across any location change because for a *fixed* lock it is determined only
||| by the lock except in the `HeldBy0` case, and a requesting/releasing process
||| in the relevant clauses is never the `HeldBy0`/Critical witness we must keep.
||| We discharge preservation directly per Step constructor below instead, which
||| is clearer than generic transport; these tiny lemmas cover the lock-retag
||| cases (acquire/release) where the holder's own slot is fixed.

||| When P1 acquires (lock Free -> HeldBy1), P0's holder fact retags Free->HeldBy1.
holder0FreeToHB1 : Holder0 a Free -> Holder0 a HeldBy1
holder0FreeToHB1 H0Free = H0Other

||| When P0 acquires (lock Free -> HeldBy0), P1's holder fact retags Free->HeldBy0.
holder1FreeToHB0 : Holder1 b Free -> Holder1 b HeldBy0
holder1FreeToHB0 H1Free = H1Other

||| When P0 releases (lock HeldBy0 -> Free), P1's holder fact retags HeldBy0->Free.
holder1HB0ToFree : Holder1 b HeldBy0 -> Holder1 b Free
holder1HB0ToFree H1Other = H1Free

||| When P1 releases (lock HeldBy1 -> Free), P0's holder fact retags HeldBy1->Free.
holder0HB1ToFree : Holder0 a HeldBy1 -> Holder0 a Free
holder0HB1ToFree H0Other = H0Free

||| Preservation of the second invariant under every transition, by case
||| analysis on `Step`. Acquire creates the `Critical`/`HeldBy_i` pairing
||| (`H?Crit`); release returns the lock to `Free` (`H?Free`); request leaves
||| the lock untouched so the (lock-determined) constraint on the *moving*
||| process is re-derived and the other process's fact is unchanged.
public export
holderStep : {0 s, t : St} -> HolderCrit s -> Step s t -> HolderCrit t
-- P0 Idle->Waiting, lock l unchanged. P0's constraint for any held-by-other / free
-- lock is unconstrained (H0Free / H0Other); if l were HeldBy0 the source would need
-- Holder0 Idle HeldBy0, which is uninhabited, so that case cannot arise.
holderStep (MkHolderCrit H0Free  h1) P0Request = MkHolderCrit H0Free  h1
holderStep (MkHolderCrit H0Other h1) P0Request = MkHolderCrit H0Other h1
-- P1 Idle->Waiting, lock unchanged. Symmetric.
holderStep (MkHolderCrit h0 H1Free)  P1Request = MkHolderCrit h0 H1Free
holderStep (MkHolderCrit h0 H1Other) P1Request = MkHolderCrit h0 H1Other
-- P0 acquires: Waiting->Critical, lock Free->HeldBy0. P0 becomes the holder and
-- is Critical (H0Crit); retag P1's free fact to HeldBy0.
holderStep (MkHolderCrit _ h1) P0Acquire = MkHolderCrit H0Crit (holder1FreeToHB0 h1)
-- P1 acquires: symmetric.
holderStep (MkHolderCrit h0 _) P1Acquire = MkHolderCrit (holder0FreeToHB1 h0) H1Crit
-- P0 releases: Critical->Idle, lock HeldBy0->Free. P0 no longer holds (H0Free);
-- retag P1's HeldBy0 fact to Free.
holderStep (MkHolderCrit _ h1) P0Release = MkHolderCrit H0Free (holder1HB0ToFree h1)
-- P1 releases: symmetric.
holderStep (MkHolderCrit h0 _) P1Release = MkHolderCrit (holder0HB1ToFree h0) H1Free

||| The second invariant, packaged as a first-class `IsInductive` value.
public export
holderIsInductive : IsInductive HolderCrit
holderIsInductive = MkIsInductive holderInit holderStep

--------------------------------------------------------------------------------
-- 6. COMPOSE the two invariants and reap the conjoined result on reachable states
--------------------------------------------------------------------------------

||| The conjoined invariant `Inv ∧ HolderCrit`, proved inductive purely by
||| feeding the two component proofs through the composition theorem. No new
||| case analysis: this is the payoff of `andInductive`.
public export
combinedIsInductive : IsInductive (And Inv HolderCrit)
combinedIsInductive = andInductive invIsInductive holderIsInductive

||| Headline Layer-3 corollary: the CONJUNCTION of the two independently-proved
||| invariants holds on EVERY reachable state — obtained generically, not by
||| re-running an induction over `Reachable`.
public export
combinedOnReachable : {0 s : St} -> Reachable s -> (Inv s, HolderCrit s)
combinedOnReachable r = inductiveOnReachable combinedIsInductive r

--------------------------------------------------------------------------------
-- 7. Decision procedure for the SECOND invariant (sound + complete)
--------------------------------------------------------------------------------

||| `Holder0` is decidable for a concrete location/lock pair.
decHolder0 : (a : Loc) -> (lk : Lock) -> Dec (Holder0 a lk)
decHolder0 _        Free    = Yes H0Free
decHolder0 _        HeldBy1 = Yes H0Other
decHolder0 Critical HeldBy0 = Yes H0Crit
decHolder0 Idle     HeldBy0 = No (\case H0Crit impossible)
decHolder0 Waiting  HeldBy0 = No (\case H0Crit impossible)

||| `Holder1` is decidable for a concrete location/lock pair.
decHolder1 : (b : Loc) -> (lk : Lock) -> Dec (Holder1 b lk)
decHolder1 _        Free    = Yes H1Free
decHolder1 _        HeldBy0 = Yes H1Other
decHolder1 Critical HeldBy1 = Yes H1Crit
decHolder1 Idle     HeldBy1 = No (\case H1Crit impossible)
decHolder1 Waiting  HeldBy1 = No (\case H1Crit impossible)

||| Recover the P0-component from a whole-state `HolderCrit`.
holderProj0 : HolderCrit (MkSt a b lk) -> Holder0 a lk
holderProj0 (MkHolderCrit h0 _) = h0

||| Recover the P1-component from a whole-state `HolderCrit`.
holderProj1 : HolderCrit (MkSt a b lk) -> Holder1 b lk
holderProj1 (MkHolderCrit _ h1) = h1

||| Sound AND complete decision of the second invariant for any state.
public export
decHolderCrit : (s : St) -> Dec (HolderCrit s)
decHolderCrit (MkSt a b lk) =
  case decHolder0 a lk of
    No notH0 => No (\hc => notH0 (holderProj0 hc))
    Yes h0   => case decHolder1 b lk of
      No notH1 => No (\hc => notH1 (holderProj1 hc))
      Yes h1   => Yes (MkHolderCrit h0 h1)

||| Certifier for the second invariant, reusing the existing `Result` ABI
||| vocabulary: `Ok` iff the state satisfies `HolderCrit`, else `TlcError`.
public export
certifyHolder : (s : St) -> Result
certifyHolder s = case decHolderCrit s of
  Yes _ => Ok
  No _  => TlcError

||| Soundness of that certifier on reachable states: every reachable state
||| satisfies `HolderCrit` (it is a conjunct of `combinedOnReachable`), so it
||| certifies `Ok`. Ties decision + reachability + composition together.
public export
certifyHolderReachableSound : (s : St) -> Reachable s -> certifyHolder s = Ok
certifyHolderReachableSound s r with (decHolderCrit s)
  _ | Yes _    = Refl
  _ | No notHC = absurd (notHC (snd (combinedOnReachable r)))

--------------------------------------------------------------------------------
-- 8. POSITIVE control: an inhabited reachable witness of the CONJUNCTION
--------------------------------------------------------------------------------

||| POSITIVE control: the concrete reachable state `(Critical, Idle, HeldBy0)`
||| (reached in `Semantics.reachP0Critical`) satisfies BOTH invariants at once —
||| obtained through the composed inductive proof, exercising the whole pipeline.
public export
positiveControl : (Inv (MkSt Critical Idle HeldBy0), HolderCrit (MkSt Critical Idle HeldBy0))
positiveControl = combinedOnReachable reachP0Critical

||| POSITIVE control, second face: the second invariant decides `Yes` on that
||| same concrete state (the decision procedure agrees with the proof).
public export
positiveControlDecided : certifyHolder (MkSt Critical Idle HeldBy0) = Ok
positiveControlDecided = Refl

--------------------------------------------------------------------------------
-- 9. NEGATIVE / NON-VACUITY controls
--------------------------------------------------------------------------------

||| NEGATIVE control #1 (the second invariant is non-trivial): the state
||| `(Idle, Idle, HeldBy0)` — lock held by P0 yet P0 is Idle, NOT Critical —
||| violates `HolderCrit`. Machine-checked `Not (...)`. This is the witness that
||| `HolderCrit` actually constrains states (it is not all-inhabited), so the
||| inductiveness result above is non-vacuous.
||| There is no `Holder0 Idle HeldBy0` proof (no constructor pairs Idle with
||| HeldBy0). Stated as a refuting helper with a top-level impossible clause.
holder0IdleHB0Absurd : Not (Holder0 Idle HeldBy0)
holder0IdleHB0Absurd H0Crit impossible

public export
negativeControl : Not (HolderCrit (MkSt Idle Idle HeldBy0))
negativeControl (MkHolderCrit h0 _) = holder0IdleHB0Absurd h0

||| NEGATIVE / DISTINCTNESS control #2 (the two invariants are GENUINELY
||| DIFFERENT predicates — the second is not a restatement of `Inv`): we exhibit
||| a single state that SATISFIES the second invariant `HolderCrit` yet VIOLATES
||| the Layer-2 invariant `Inv`. Such a separating witness proves the two
||| predicates are not equal as `St -> Type` (HolderCrit does NOT imply Inv), so
||| this layer adds new, non-derivable content.
|||
||| Witness: `(Critical, Critical, Free)`. With the lock Free, neither process
||| is the holder, so both `Holder0`/`Holder1` constraints hold vacuously
||| (`H0Free`/`H1Free`) and `HolderCrit` is inhabited. But `Inv` requires both
||| processes coherent with the (Free) lock, and `Coherent0 Critical Free` is
||| uninhabited (Critical demands `HeldBy0`), so `Inv` fails. (Note: this state
||| is mutual-exclusion-violating and is precisely UNREACHABLE — see
||| `Semantics.badStateUnreachable` — which is *why* the strictly weaker
||| `HolderCrit` cannot on its own imply mutual exclusion: it needs `Inv` as the
||| second conjunct. That is the whole point of composing them.)
public export
holderHoldsButInvFails :
  (HolderCrit (MkSt Critical Critical Free), Not (Inv (MkSt Critical Critical Free)))
holderHoldsButInvFails =
  ( MkHolderCrit H0Free H1Free
  , invCriticalFreeAbsurd
  )
  where
    ||| `Inv (Critical, Critical, Free)` is uninhabited: its P0 component would
    ||| be `Coherent0 Critical Free`, which has no constructor.
    invCriticalFreeAbsurd : Not (Inv (MkSt Critical Critical Free))
    invCriticalFreeAbsurd (MkInv c0 _) = case c0 of
      C0CritHolds impossible
