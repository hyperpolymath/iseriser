-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Tlaiser: inductive-invariant soundness.
|||
||| Tlaiser's headline is "extract state machines and model-check with
||| TLA+/PlusCal". The single most important thing a model checker establishes
||| about a safety property is that it is an *inductive invariant*: it holds in
||| the initial state(s) and is preserved by every step of the next-state
||| relation. From those two facts, TLA+'s INV1 rule concludes the property
||| holds in *every reachable state*. This module models that argument faithfully
||| and proves it for real, end to end, for a two-process lock-based
||| mutual-exclusion machine (the canonical PlusCal example).
|||
||| Model (deliberately minimal but genuine):
|||   * `St` is a concrete state: a control location for each of two processes
|||     plus a single shared lock token.
|||   * `Init` is the initial-state relation.
|||   * `Step` is the next-state *relation* (nondeterministic; several enabled
|||     transitions per state), as in a real TLA+ spec.
|||   * `Reachable s` is the inductive closure of `Init` under `Step` — exactly
|||     the set of states a model checker explores.
|||   * `Safe` is the headline safety property: the two processes are never both
|||     in their critical section (mutual exclusion).
|||   * `Inv` is a *strengthened, genuinely inductive* invariant that couples
|||     "process is Critical" to "process holds the lock". `Safe` follows from
|||     `Inv`, and `Inv` is preserved by every step.
|||
||| Headline theorem (`safetySound`): the safety property holds on every
||| reachable state. The engine of the proof is `invInductive` (INV1): an
||| inductive invariant holding initially and preserved by Step holds on all
||| reachable states.
|||
||| @see https://lamport.azurewebsites.net/tla/tla.html  (INV1 inference rule)

module Tlaiser.ABI.Semantics

import Tlaiser.ABI.Types
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A faithful state-machine model
--------------------------------------------------------------------------------

||| Per-process control location. Idle -> Waiting -> Critical -> Idle. This is
||| the canonical PlusCal mutual-exclusion control flow.
public export
data Loc = Idle | Waiting | Critical

||| Lock token: Free, or Held by a specific process (P0 / P1). A single token,
||| so at most one process can hold it — this is what enforces mutual exclusion.
public export
data Lock = Free | HeldBy0 | HeldBy1

||| A state of the machine: the control location of each of the two processes
||| and the shared lock.
public export
record St where
  constructor MkSt
  p0 : Loc
  p1 : Loc
  lock : Lock

--------------------------------------------------------------------------------
-- The initial-state predicate (Init) and next-state relation (Step)
--------------------------------------------------------------------------------

||| `Init s` holds exactly for the unique initial state: both idle, lock free.
public export
data Init : St -> Type where
  InitState : Init (MkSt Idle Idle Free)

||| The next-state relation. Each constructor is one enabled transition. A state
||| typically has several successors (nondeterminism), as in a real TLA+ spec.
|||
||| Mutual exclusion is enforced *structurally* by the lock: a process can only
||| enter Critical when it acquires the (single) lock, and acquiring requires the
||| lock to be Free. This is the protocol whose safety we prove.
public export
data Step : St -> St -> Type where
  ||| P0 requests the lock: Idle -> Waiting (lock unchanged).
  P0Request : Step (MkSt Idle q l) (MkSt Waiting q l)
  ||| P1 requests the lock: Idle -> Waiting (lock unchanged).
  P1Request : Step (MkSt q Idle l) (MkSt q Waiting l)
  ||| P0 acquires the free lock and enters Critical.
  P0Acquire : Step (MkSt Waiting q Free) (MkSt Critical q HeldBy0)
  ||| P1 acquires the free lock and enters Critical.
  P1Acquire : Step (MkSt q Waiting Free) (MkSt q Critical HeldBy1)
  ||| P0 leaves Critical, releasing the lock it holds.
  P0Release : Step (MkSt Critical q HeldBy0) (MkSt Idle q Free)
  ||| P1 leaves Critical, releasing the lock it holds.
  P1Release : Step (MkSt q Critical HeldBy1) (MkSt q Idle Free)

--------------------------------------------------------------------------------
-- Reachability: the inductive closure of Init under Step
--------------------------------------------------------------------------------

||| `Reachable s` : `s` is reachable from an initial state by zero or more steps.
||| This is precisely the set of states a model checker explores.
public export
data Reachable : St -> Type where
  ||| Every initial state is reachable.
  ReachInit : Init s -> Reachable s
  ||| If `s` is reachable and `s` steps to `t`, then `t` is reachable.
  ReachStep : Reachable s -> Step s t -> Reachable t

--------------------------------------------------------------------------------
-- The headline safety property: mutual exclusion
--------------------------------------------------------------------------------

||| `Safe s` : the two processes are never *both* Critical. Phrased as a
||| proposition with NO constructor for the bad case `(Critical, Critical)` —
||| there is simply no way to inhabit `Safe (MkSt Critical Critical _)`.
public export
data Safe : St -> Type where
  ||| P0 is not critical: safe regardless of P1.
  Safe0 : Not (a = Critical) -> Safe (MkSt a b l)
  ||| P1 is not critical: safe regardless of P0.
  Safe1 : Not (b = Critical) -> Safe (MkSt a b l)

--------------------------------------------------------------------------------
-- The strengthened, genuinely inductive invariant
--------------------------------------------------------------------------------

||| `LocLock l lk` : a single process's location is consistent with whether it
||| holds the lock token `lk`. "Critical iff holds the lock."
||| Indexed by the lock-ownership boolean for THIS process.
public export
data Coherent0 : Loc -> Lock -> Type where
  ||| P0 is Critical exactly when the lock is HeldBy0.
  C0CritHolds   : Coherent0 Critical HeldBy0
  ||| P0 is not Critical: the lock is held by someone else or free.
  C0NotCritFree : Coherent0 Idle Free
  C0NotCritFreeW: Coherent0 Waiting Free
  C0NotCrit1I   : Coherent0 Idle HeldBy1
  C0NotCrit1W   : Coherent0 Waiting HeldBy1

public export
data Coherent1 : Loc -> Lock -> Type where
  C1CritHolds   : Coherent1 Critical HeldBy1
  C1NotCritFree : Coherent1 Idle Free
  C1NotCritFreeW: Coherent1 Waiting Free
  C1NotCrit0I   : Coherent1 Idle HeldBy0
  C1NotCrit0W   : Coherent1 Waiting HeldBy0

||| The full inductive invariant: both processes are coherent with the lock.
||| Because "Critical iff holds the lock" and the lock is a single token, both
||| processes cannot be Critical at once. This makes `Inv` strong enough to be
||| preserved by every step (genuinely inductive), and strong enough to imply
||| the headline `Safe` property.
public export
data Inv : St -> Type where
  MkInv : Coherent0 a lk -> Coherent1 b lk -> Inv (MkSt a b lk)

--------------------------------------------------------------------------------
-- Inv implies the headline safety property
--------------------------------------------------------------------------------

||| If P0 is Critical it must hold the lock (HeldBy0); then P1's coherence with
||| HeldBy0 forces P1 to be non-Critical. Hence mutual exclusion. This is where
||| the strengthening pays off — `Safe` is a *consequence* of `Inv`.
public export
invImpliesSafe : Inv s -> Safe s
invImpliesSafe (MkInv c0 c1) = case c1 of
  C1CritHolds    => Safe0 (notCritWhenLock1 c0)  -- lk = HeldBy1 => P0 not Critical
  C1NotCritFree  => Safe1 (\case Refl impossible)
  C1NotCritFreeW => Safe1 (\case Refl impossible)
  C1NotCrit0I    => Safe1 (\case Refl impossible)
  C1NotCrit0W    => Safe1 (\case Refl impossible)
  where
    ||| When the lock is HeldBy1, P0's coherence rules out P0 = Critical.
    notCritWhenLock1 : Coherent0 a HeldBy1 -> Not (a = Critical)
    notCritWhenLock1 C0NotCrit1I  = \case Refl impossible
    notCritWhenLock1 C0NotCrit1W  = \case Refl impossible

--------------------------------------------------------------------------------
-- Decision procedure for the headline safety property (sound + complete)
--------------------------------------------------------------------------------

||| Loc equality is decidable.
locDecEq : (x : Loc) -> (y : Loc) -> Dec (x = y)
locDecEq Idle Idle = Yes Refl
locDecEq Waiting Waiting = Yes Refl
locDecEq Critical Critical = Yes Refl
locDecEq Idle Waiting = No (\case Refl impossible)
locDecEq Idle Critical = No (\case Refl impossible)
locDecEq Waiting Idle = No (\case Refl impossible)
locDecEq Waiting Critical = No (\case Refl impossible)
locDecEq Critical Idle = No (\case Refl impossible)
locDecEq Critical Waiting = No (\case Refl impossible)

||| The unique bad shape `(Critical, Critical, _)` has no `Safe` proof.
bothCritNotSafe : Not (Safe (MkSt Critical Critical l))
bothCritNotSafe (Safe0 f) = f Refl
bothCritNotSafe (Safe1 f) = f Refl

||| Transport a `Safe` proof of an arbitrary state to the canonical bad shape,
||| given that both locations are `Critical` (term-level transport, no stuck
||| case-of-Refl). Top-level so its implicit args bind cleanly.
safeToBadShape : {0 a, b : Loc} -> {0 l : Lock} ->
                 a = Critical -> b = Critical ->
                 Safe (MkSt a b l) -> Safe (MkSt Critical Critical l)
safeToBadShape Refl Refl x = x

||| Sound and complete decision of the safety property for any state.
public export
decSafe : (s : St) -> Dec (Safe s)
decSafe (MkSt a b l) =
  case locDecEq a Critical of
    No notCritA => Yes (Safe0 notCritA)
    Yes aCrit   => case locDecEq b Critical of
      No notCritB => Yes (Safe1 notCritB)
      Yes bCrit   => No (\sf => bothCritNotSafe (safeToBadShape aCrit bCrit sf))

--------------------------------------------------------------------------------
-- Inductive-invariant hypotheses, discharged constructively
--------------------------------------------------------------------------------

||| (1) The invariant holds on every initial state `(Idle, Idle, Free)`.
public export
initEstablishes : Init s -> Inv s
initEstablishes InitState = MkInv C0NotCritFree C1NotCritFree

-- ---- coherence-preservation helper lemmas (all total, by case analysis) ----

||| P0 Idle->Waiting under unchanged lock stays coherent.
idleToWaiting0 : Coherent0 Idle lk -> Coherent0 Waiting lk
idleToWaiting0 C0NotCritFree = C0NotCritFreeW
idleToWaiting0 C0NotCrit1I   = C0NotCrit1W

||| P1 Idle->Waiting under unchanged lock stays coherent.
idleToWaiting1 : Coherent1 Idle lk -> Coherent1 Waiting lk
idleToWaiting1 C1NotCritFree = C1NotCritFreeW
idleToWaiting1 C1NotCrit0I   = C1NotCrit0W

||| When the lock was Free and P0 acquires it, re-tag P1's coherence with HeldBy0.
||| P1 was coherent with Free (Idle or Waiting), so it stays non-Critical.
freeToHeldBy0 : Coherent1 b Free -> Coherent1 b HeldBy0
freeToHeldBy0 C1NotCritFree  = C1NotCrit0I
freeToHeldBy0 C1NotCritFreeW = C1NotCrit0W

||| When the lock was Free and P1 acquires it, re-tag P0's coherence with HeldBy1.
freeToHeldBy1 : Coherent0 a Free -> Coherent0 a HeldBy1
freeToHeldBy1 C0NotCritFree  = C0NotCrit1I
freeToHeldBy1 C0NotCritFreeW = C0NotCrit1W

||| When P0 releases (lock HeldBy0 -> Free), re-tag P1's coherence with Free.
||| P1 was coherent with HeldBy0 (Idle or Waiting), so it stays non-Critical.
heldBy0ToFree : Coherent1 b HeldBy0 -> Coherent1 b Free
heldBy0ToFree C1NotCrit0I = C1NotCritFree
heldBy0ToFree C1NotCrit0W = C1NotCritFreeW

||| When P1 releases (lock HeldBy1 -> Free), re-tag P0's coherence with Free.
heldBy1ToFree : Coherent0 a HeldBy1 -> Coherent0 a Free
heldBy1ToFree C0NotCrit1I = C0NotCritFree
heldBy1ToFree C0NotCrit1W = C0NotCritFreeW

||| (2) The invariant is preserved by every transition. Proved by case analysis
||| on `Step`. Each clause re-establishes coherence of *both* processes with the
||| post-state lock. The acquire/release cases are where the lock discipline does
||| the real work — and it now goes through because `Inv` carries the coupling.
public export
stepPreserves : Inv s -> Step s t -> Inv t
-- P0 requests: P0 Idle->Waiting, lock unchanged. P0 was coherent with l while
-- Idle; Waiting is coherent with the same l in every case. Re-derive from l.
stepPreserves (MkInv c0 c1) P0Request = MkInv (idleToWaiting0 c0) c1
stepPreserves (MkInv c0 c1) P1Request = MkInv c0 (idleToWaiting1 c1)
-- P0 acquires: pre lock Free, P0 Waiting -> Critical, lock -> HeldBy0. P1 was
-- coherent with Free (so P1 is Idle or Waiting, not Critical); re-tag with HeldBy0.
stepPreserves (MkInv _ c1) P0Acquire = MkInv C0CritHolds (freeToHeldBy0 c1)
stepPreserves (MkInv c0 _) P1Acquire = MkInv (freeToHeldBy1 c0) C1CritHolds
-- P0 releases: P0 Critical -> Idle, lock HeldBy0 -> Free. P1 was coherent with
-- HeldBy0 (so P1 not Critical); re-tag with Free.
stepPreserves (MkInv _ c1) P0Release = MkInv C0NotCritFree (heldBy0ToFree c1)
stepPreserves (MkInv c0 _) P1Release = MkInv (heldBy1ToFree c0) C1NotCritFree

--------------------------------------------------------------------------------
-- The headline theorem: INV1 (inductive invariant => all reachable states)
--------------------------------------------------------------------------------

||| INV1, machine-checked. If `Inv` holds on every initial state and is
||| preserved by every `Step`, then `Inv` holds on every `Reachable` state.
||| Proof by induction on the `Reachable` derivation — exactly the model
||| checker's soundness argument for safety properties.
public export
invInductive : {0 s : St} -> Reachable s -> Inv s
invInductive (ReachInit init)   = initEstablishes init
invInductive (ReachStep r step) = stepPreserves (invInductive r) step

||| Headline safety result: mutual exclusion holds on every reachable state.
public export
safetySound : {0 s : St} -> Reachable s -> Safe s
safetySound r = invImpliesSafe (invInductive r)

--------------------------------------------------------------------------------
-- Certifier
--------------------------------------------------------------------------------

||| Certify the safety property for a state, using the existing `Result` ABI
||| vocabulary: `Ok` iff the decision says the state is Safe, else `TlcError`.
public export
certifySafe : (s : St) -> Result
certifySafe s = case decSafe s of
  Yes _ => Ok
  No _  => TlcError

||| Soundness of the certifier: every reachable state certifies `Ok`, because it
||| provably satisfies the safety property. Ties the decision procedure, the
||| reachability proof, and the headline theorem into one fact.
public export
certifyReachableSound : (s : St) -> Reachable s -> certifySafe s = Ok
certifyReachableSound s r with (decSafe s)
  _ | Yes _   = Refl
  _ | No notS = absurd (notS (safetySound r))

--------------------------------------------------------------------------------
-- POSITIVE control: an explicit reachable, safe witness
--------------------------------------------------------------------------------

||| A concrete reachable state: from init, P0 requests then acquires the lock,
||| ending in `(Critical, Idle, HeldBy0)`. Exercises the real transition relation.
public export
reachP0Critical : Reachable (MkSt Critical Idle HeldBy0)
reachP0Critical =
  ReachStep
    (ReachStep (ReachInit InitState) P0Request)  -- (Idle,Idle,Free) -> (Waiting,Idle,Free)
    P0Acquire                                     -- -> (Critical,Idle,HeldBy0)

||| POSITIVE control: that reachable state satisfies the safety property.
public export
positiveControl : Safe (MkSt Critical Idle HeldBy0)
positiveControl = safetySound reachP0Critical

--------------------------------------------------------------------------------
-- NEGATIVE control: the bad state is genuinely excluded
--------------------------------------------------------------------------------

||| NEGATIVE control: the mutual-exclusion-violating state `(Critical, Critical)`
||| has NO safety proof. Machine-checked `Not (...)`.
public export
negativeControl : Not (Safe (MkSt Critical Critical HeldBy0))
negativeControl = bothCritNotSafe

||| NEGATIVE control (stronger): the bad state is not even *reachable*. Since
||| every reachable state is Safe, and the bad state contradicts Safe,
||| reachability of the bad state is absurd. This is the real safety guarantee:
||| the model checker would never produce a counterexample because none exists.
public export
badStateUnreachable : Not (Reachable (MkSt Critical Critical HeldBy0))
badStateUnreachable r = negativeControl (safetySound r)
