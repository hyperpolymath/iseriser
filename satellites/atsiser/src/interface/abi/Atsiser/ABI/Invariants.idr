-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Transition-soundness invariants for Atsiser (Idris2 ABI Layer 3).
|||
||| Layer 2 (`Atsiser.ABI.Semantics`) proves the STATIC property that a `Freed`
||| pointer has no `Accessible` witness — so use-after-free / double-free are
||| unrepresentable. This module proves a DEEPER, DISTINCT property: the
||| DYNAMIC soundness of the linear state machine's single transition `free`.
||| Concretely, for every live pointer with access right `Acc`:
|||
|||   1. `freeYieldsFreed`   — `state (free p Acc) = Freed`
|||      (the transition always lands in the post-state — progress);
|||   2. `freePreservesAddr` — `addr (free p Acc) = addr p`
|||      (the transition is address-preserving — it frees THIS pointer, not
|||      some other one — frame/locality);
|||   3. `freedResultUnusable` — the result of `free` is never `Accessible`,
|||      so it can never be fed back into another `free` (no reuse / no
|||      double-free), derived here as a CONSEQUENCE of (1) + Layer 2 rather
|||      than restating the Layer-2 theorem;
|||   4. terminality — a `Freed` pointer is at a fixed point of the state
|||      machine; no further transition exists (`noFurtherFree`).
|||
||| All are built over the SAME `Ptr` / `PtrState` / `Accessible` / `free` from
||| Layer 2 (imported, not redefined), plus a sound+complete `Dec` for the
||| terminal-state predicate, and positive + negative machine-checked controls.

module Atsiser.ABI.Invariants

import Atsiser.ABI.Types
import Atsiser.ABI.Semantics
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- (1) Progress: free always lands in the Freed post-state
--------------------------------------------------------------------------------

||| The transition function `free` is sound w.r.t. the target state: whatever
||| live pointer and access witness it consumes, its result is in state `Freed`.
||| The address is bound explicitly as `a` (a bare lowercase free name would
||| warn / risk shadowing a global).
export
freeYieldsFreed : (a : Nat) -> state (free (MkPtr a Live) Acc) = Freed
freeYieldsFreed a = Refl

--------------------------------------------------------------------------------
-- (2) Frame: free preserves the address it operates on
--------------------------------------------------------------------------------

||| `free` does not relocate: the freed pointer carries the same address as the
||| pointer that was consumed. This locality guarantee distinguishes
||| "free p" from "free some-other-pointer".
export
freePreservesAddr : (a : Nat) -> addr (free (MkPtr a Live) Acc) = a
freePreservesAddr a = Refl

--------------------------------------------------------------------------------
-- (3) No reuse: the result of free is never Accessible (consequence, not
--     a restatement). We use (1) to rewrite the result's state to Freed,
--     then Layer 2's `freedNotAcc` to refute accessibility.
--------------------------------------------------------------------------------

||| A pointer whose state is `Freed` (for any address) is not accessible.
||| This is a clean reusable corollary phrased on the post-state.
export
freedAtAddrNotAcc : (a : Nat) -> Not (Accessible (MkPtr a Freed))
freedAtAddrNotAcc a = freedNotAcc

||| The DEEPER theorem: nothing produced by `free` can be accessed again.
||| Given a live pointer at address `a`, the result of freeing it admits no
||| `Accessible` witness — so it can never be passed to `free` a second time.
||| `free (MkPtr a Live) Acc` reduces to `MkPtr a Freed`, so an accessibility
||| witness for the result is, definitionally, an accessibility witness for the
||| freed pointer, which Layer 2's `freedNotAcc` refutes. This composes the
||| transition `free` with the Layer-2 refutation — it is not Layer 2 alone.
export
freedResultUnusable : (a : Nat) -> Not (Accessible (free (MkPtr a Live) Acc))
freedResultUnusable a acc = freedNotAcc acc

--------------------------------------------------------------------------------
-- (4) Terminality: Freed is a fixed point — no further transition exists.
--     `free` demands an `Accessible` witness, which a Freed pointer cannot
--     supply; so there is no well-typed `free` from the Freed state. We
--     express the fixed point as: any accessibility claim on a freed pointer
--     is absurd, hence `free` is unreachable there.
--------------------------------------------------------------------------------

||| If you somehow had an access right to a freed pointer, anything follows —
||| witnessing that the Freed state is terminal (no real successor transition).
export
noFurtherFree : (a : Nat) -> Accessible (MkPtr a Freed) -> Void
noFurtherFree a = freedNotAcc

--------------------------------------------------------------------------------
-- Sound + complete decision for the terminal-state predicate
--------------------------------------------------------------------------------

||| Predicate: this pointer is at the terminal Freed state.
public export
data AtTerminal : Ptr -> Type where
  IsFreed : {0 a : Nat} -> AtTerminal (MkPtr a Freed)

||| A Live pointer is not at the terminal state.
export
liveNotTerminal : {0 a : Nat} -> Not (AtTerminal (MkPtr a Live))
liveNotTerminal IsFreed impossible

||| Sound + complete decision procedure.
public export
decAtTerminal : (p : Ptr) -> Dec (AtTerminal p)
decAtTerminal (MkPtr a Live)  = No liveNotTerminal
decAtTerminal (MkPtr a Freed) = Yes IsFreed

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound, and reflecting termination
--------------------------------------------------------------------------------

||| Certify that a pointer is at the terminal Freed state.
public export
certifyTerminal : Ptr -> Result
certifyTerminal p = case decAtTerminal p of
  Yes _ => Ok
  No  _ => Error

||| Soundness: an `Ok` certificate genuinely entails the terminal predicate.
export
certifyTerminalSound : (p : Ptr) -> certifyTerminal p = Ok -> AtTerminal p
certifyTerminalSound p prf with (decAtTerminal p)
  certifyTerminalSound p prf  | Yes t = t
  certifyTerminalSound p Refl | No _ impossible

||| The result of `free` always certifies as terminal — ties the certifier to
||| the progress lemma.
export
freeResultTerminal : (a : Nat) -> certifyTerminal (free (MkPtr a Live) Acc) = Ok
freeResultTerminal a = Refl

--------------------------------------------------------------------------------
-- Positive controls (inhabited witnesses / concrete instances)
--------------------------------------------------------------------------------

||| Concrete free transition lands in Freed, preserving the address 4096.
export
freeConcreteState : state (free (MkPtr 4096 Live) Acc) = Freed
freeConcreteState = Refl

export
freeConcreteAddr : addr (free (MkPtr 4096 Live) Acc) = 4096
freeConcreteAddr = Refl

||| The freed result of a concrete live pointer is at terminal.
export
freeConcreteTerminal : AtTerminal (free (MkPtr 4096 Live) Acc)
freeConcreteTerminal = IsFreed

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls
--------------------------------------------------------------------------------

||| A concrete freed pointer is NOT accessible — the no-reuse core, machine
||| checked at a literal address.
export
freeConcreteUnusable : Not (Accessible (free (MkPtr 4096 Live) Acc))
freeConcreteUnusable = freedResultUnusable 4096

||| A live pointer is NOT at the terminal state (rejects a false certificate).
export
liveConcreteNotTerminal : Not (AtTerminal (MkPtr 4096 Live))
liveConcreteNotTerminal = liveNotTerminal

||| The certifier rejects a live pointer.
export
certifyLiveNotTerminal : certifyTerminal (MkPtr 4096 Live) = Error
certifyLiveNotTerminal = Refl
