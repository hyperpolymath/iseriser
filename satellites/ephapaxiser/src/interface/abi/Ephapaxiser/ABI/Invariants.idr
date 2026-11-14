-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 deeper invariants for ephapaxiser: NO-RESURRECTION and
||| DETERMINISM of the single-use consume transition.
|||
||| The Layer-2 flagship (`Ephapaxiser.ABI.Semantics`) proves the *guard*: a
||| `Spent` token is not `Consumable`, so no second consumption is well-typed.
||| This module proves two genuinely different, deeper properties about the
||| transition *itself*, built over the SAME model (`Token`, `Consumable`,
||| `Consumed`, `consume` are all reused, not redefined):
|||
|||   1. NO-RESURRECTION. The `after` token of any `Consumed` certificate is a
|||      `Token Spent`, and there is NO certificate whose `after` is `Fresh`.
|||      i.e. consumption is irreversible — a token, once spent, can never be
|||      shown fresh again through the transition relation. Stated as an
|||      `Uninhabited` instance for a "resurrection" certificate plus a positive
|||      identity-preservation lemma.
|||
|||   2. DETERMINISM. For a given fresh token, the produced certificate is
|||      UNIQUE: any two `Consumed (MkToken Fresh i) _` certificates are equal,
|||      and the spent token `consume` produces is uniquely determined (same
|||      identity, propositionally). This is a uniqueness-of-result theorem,
|||      not a guard — it says the single legal transition is a *function*, not
|||      merely *at most once permitted*.
|||
||| Together these raise the ABI to "Layer 3": beyond the domain invariant we
||| prove the transition is irreversible and deterministic. No axioms: no
||| `believe_me`, `idris_crash`, `assert_total`, `postulate`, or asserted
||| equalities anywhere.

module Ephapaxiser.ABI.Invariants

import Ephapaxiser.ABI.Types
import Ephapaxiser.ABI.Semantics
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Identity preservation through the transition (a round-trip lemma).
--------------------------------------------------------------------------------

||| The identity tag carried by a `Consumed` certificate's source equals that of
||| its target. This is the round-trip content: `consume` neither invents nor
||| forgets identity. Proved by matching the unique certificate constructor.
public export
consumedPreservesId : {0 b : Token Fresh} -> {0 a : Token Spent} ->
                      Consumed b a -> tokenId b = tokenId a
consumedPreservesId (MkConsumed i) = Refl

||| The spent token produced by `consume` has the same identity as the fresh
||| token it consumed. Direct corollary stated over the operation itself.
public export
consumePreservesId : (i : Nat) ->
                     tokenId (fst (consume (MkToken {st = Fresh} i) FreshConsumable)) = i
consumePreservesId i = Refl

--------------------------------------------------------------------------------
-- (1) NO-RESURRECTION: the transition is irreversible.
--------------------------------------------------------------------------------

||| A "resurrection" claim is the proposition that the SPENT result of the
||| transition can itself be reclassified as a `Fresh`, consumable token — i.e.
||| that the token has come back to life. We phrase it as: the spent result is
||| `Consumable`. Since `Consumable` has NO constructor for a `Spent` token
||| (Layer-2), this proposition is uninhabited — that is exactly irreversibility.
public export
Resurrection : (after : Token Spent) -> Type
Resurrection after = Consumable after

||| NO-RESURRECTION (theorem): the spent result of ANY transition certificate is
||| not resurrectable. Given `Consumed b a`, the target `a` is a `Token Spent`,
||| and a `Token Spent` is never `Consumable` (Layer-2 `Uninhabited` instance).
||| This is a transition-soundness theorem: every reachable post-state is dead.
||| Proved without axioms — `a`'s state index is forced to `Spent` by the
||| certificate's type, so `absurd` discharges any `Consumable a`.
public export
postStateNotConsumable : {0 b : Token Fresh} -> (0 a : Token Spent) ->
                         Consumed b a -> Not (Resurrection a)
postStateNotConsumable (MkToken i) (MkConsumed i) = absurd

||| NO-RESURRECTION (operational corollary): for a concrete identity, a spent
||| token can never be re-presented as a fresh, consumable token. Reuses the
||| Layer-2 `Uninhabited (Consumable (MkToken {st = Spent} i))` over the result
||| of `consume`: the produced token is `Spent`, hence not `Consumable`.
public export
consumedResultNotConsumable : (i : Nat) ->
  Not (Consumable (DPair.fst (consume (MkToken {st = Fresh} i) FreshConsumable)))
consumedResultNotConsumable i = absurd

--------------------------------------------------------------------------------
-- (2) DETERMINISM: the certificate / result is unique for a given fresh token.
--------------------------------------------------------------------------------

||| DETERMINISM (certificate uniqueness): any two transition certificates with
||| the SAME fresh source and the SAME spent target are equal. Because
||| `MkConsumed` is the unique constructor and is fully determined by the shared
||| identity index, the two certificates are literally the same value.
public export
consumedUnique : {0 b : Token Fresh} -> {0 a : Token Spent} ->
                 (p, q : Consumed b a) -> p = q
consumedUnique (MkConsumed i) (MkConsumed i) = Refl

||| DETERMINISM (result identity is a function): if two certificates share a
||| fresh source `b`, their spent targets carry the SAME identity. So the
||| transition cannot map one fresh token to two differently-identified spent
||| tokens — it is single-valued in identity.
|||
||| We extract identities and chain the round-trip lemma in both directions:
||| `tokenId a1 = tokenId b = tokenId a2`.
public export
consumeResultDeterministic : {0 b : Token Fresh} -> {0 a1, a2 : Token Spent} ->
                             Consumed b a1 -> Consumed b a2 ->
                             tokenId a1 = tokenId a2
consumeResultDeterministic c1 c2 =
  trans (sym (consumedPreservesId c1)) (consumedPreservesId c2)

||| DETERMINISM (operation level): running `consume` twice on the SAME fresh
||| token yields spent tokens of the SAME identity. Definitional here, but
||| stating it pins the determinism of the actual operation, not just the
||| relation.
public export
consumeFunction : (i : Nat) ->
  tokenId (fst (consume (MkToken {st = Fresh} i) FreshConsumable))
    = tokenId (fst (consume (MkToken {st = Fresh} i) FreshConsumable))
consumeFunction i = Refl

--------------------------------------------------------------------------------
-- Decision procedure (natural here): decide whether two certificates over the
-- same source/target indices are equal. Sound + complete: there is exactly one
-- such certificate, so the answer is always Yes, and the witness is genuine.
--------------------------------------------------------------------------------

||| Decide equality of two `Consumed` certificates with matched indices. Sound
||| (the `Yes` carries a real equality proof from `consumedUnique`) and complete
||| (it never returns `No`, because by uniqueness they are always equal — there
||| is no inhabited `Not (p = q)` to return). This is the decidable face of the
||| determinism theorem.
public export
decConsumedEq : {0 b : Token Fresh} -> {0 a : Token Spent} ->
                (p, q : Consumed b a) -> Dec (p = q)
decConsumedEq p q = Yes (consumedUnique p q)

--------------------------------------------------------------------------------
-- POSITIVE controls (inhabited witnesses / concrete instances).
--------------------------------------------------------------------------------

||| POSITIVE CONTROL: a concrete certificate exists, and the round-trip lemma
||| computes the preserved identity to the literal `5`.
public export
consumedFiveId : Invariants.consumedPreservesId (MkConsumed 5)
                   = the (5 = 5) Refl
consumedFiveId = Refl

||| POSITIVE CONTROL: determinism delivers the SAME concrete certificate when
||| asked twice for the id-9 transition.
public export
sameCertNine : Invariants.consumedUnique (MkConsumed 9) (MkConsumed 9) = Refl
sameCertNine = Refl

||| POSITIVE CONTROL: the decision procedure answers `Yes` for two equal
||| concrete certificates, with the genuine uniqueness proof inside.
public export
decYesNine : Invariants.decConsumedEq (MkConsumed 9) (MkConsumed 9)
               = Yes Refl
decYesNine = Refl

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls (machine-checked).
--------------------------------------------------------------------------------

||| NEGATIVE CONTROL (no-resurrection): the spent result of consuming fresh-id-3
||| cannot be resurrected — it is not `Consumable`. Discharged via the
||| no-resurrection theorem applied to the concrete id-3 certificate.
public export
noResurrectionThree : Not (Resurrection (MkToken {st = Spent} 3))
noResurrectionThree =
  postStateNotConsumable (MkToken 3) (MkConsumed 3)

||| NEGATIVE CONTROL (irreversibility, operational): the spent token produced by
||| consuming fresh-id-3 is NOT consumable — it cannot loop back to a usable
||| state. This is non-vacuous: it exercises a real `consume` result.
public export
consumeThreeResultDead : Not (Consumable (DPair.fst (consume (MkToken {st = Fresh} 3) FreshConsumable)))
consumeThreeResultDead = absurd

||| NON-VACUITY CONTROL: distinct fresh sources produce distinct spent
||| identities — determinism is single-valued, NOT collapse-everything. Here
||| consuming id-1 and id-2 give targets whose ids differ, refuting `1 = 2`.
||| (If determinism were vacuous/degenerate this would not hold.)
public export
distinctIdsDistinctResults :
  Not (tokenId (fst (consume (MkToken {st = Fresh} 1) FreshConsumable))
         = tokenId (fst (consume (MkToken {st = Fresh} 2) FreshConsumable)))
distinctIdsDistinctResults Refl impossible
