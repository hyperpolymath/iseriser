-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariants for Phronesiser: MONOTONE SAFETY under policy
||| composition — a strictly deeper property than the Layer-2 flagship.
|||
||| Layer 2 (`Phronesiser.ABI.Semantics`) proves a property of ONE action under
||| ONE fixed static verdict: a forbidden action can never be certified
||| permitted. This module proves properties of WHOLE POLICIES and their
||| composition — quantified over all actions and over the space of policies:
|||
|||   1. DOWNWARD-CLOSURE OF PERMISSION (monotone safety): if a policy `p2`
|||      *tightens* `p1` (everything `p2` permits, `p1` already permitted),
|||      then everything `p1` forbids, `p2` still forbids. Adding constraints
|||      NEVER re-permits a previously-forbidden action — the permitted set
|||      only shrinks. This is the safety-preservation law an ethical engine
|||      must satisfy when policies are strengthened at runtime.
|||
|||   2. CONJUNCTION COMPOSITION: an action permitted under the conjunction
|||      `andPolicy p1 p2` is permitted under `p1` AND under `p2` separately;
|||      and `andPolicy p1 p2` provably tightens each conjunct. So composing
|||      policies by conjunction is sound: it can only forbid more.
|||
||| Both are reused over the SAME model from `Semantics` (Action / Verdict /
||| verdictOf) — no datatype is redefined. A sound+complete `Dec (Permits ...)`
||| is provided. Positive and negative/non-vacuity controls are machine-checked.
|||
||| Every fact below is discharged by the Idris2 type checker. No `believe_me`,
||| `idris_crash`, `assert_total`, `postulate`, `sorry`, or asserted equalities.

module Phronesiser.ABI.Invariants

import Phronesiser.ABI.Types
import Phronesiser.ABI.Semantics

%default total

--------------------------------------------------------------------------------
-- Verdict trichotomy (here, dichotomy): Allow or Deny, nothing else.
--------------------------------------------------------------------------------

||| Every verdict is `Allow` or `Deny`. This total case analysis is the engine
||| behind monotone safety: "not Allow" forces "Deny".
public export
verdictDichotomy : (v : Verdict) -> Either (v = Allow) (v = Deny)
verdictDichotomy Allow = Left Refl
verdictDichotomy Deny  = Right Refl

--------------------------------------------------------------------------------
-- Policies as verdict-assignments over the shared Action model.
--------------------------------------------------------------------------------

||| A policy assigns a verdict to every candidate action. This refines the
||| static `verdictOf` from `Semantics`: different ethical rule-sets induce
||| different policies over the same action space.
public export
Policy : Type
Policy = Action -> Verdict

||| `Permits p a` : the policy `p` permits action `a`.
public export
Permits : Policy -> Action -> Type
Permits p a = p a = Allow

||| `Forbids p a` : the policy `p` forbids action `a`.
public export
Forbids : Policy -> Action -> Type
Forbids p a = p a = Deny

||| A policy cannot both permit and forbid the same action (Allow /= Deny).
||| This is the local consistency of any single policy.
public export
permitForbidExclusive : (p : Policy) -> (a : Action) ->
                        Permits p a -> Forbids p a -> Void
permitForbidExclusive p a perm forb =
  -- perm : p a = Allow ; forb : p a = Deny ; so Allow = Deny, absurd.
  absurd (trans (sym perm) forb)

--------------------------------------------------------------------------------
-- Policy tightening (the ordering on policies).
--------------------------------------------------------------------------------

||| `Tightens p2 p1` : `p2` is at least as strict as `p1` — every action `p2`
||| permits was already permitted by `p1`. Equivalently the permitted set of
||| `p2` is contained in that of `p1`.
public export
Tightens : Policy -> Policy -> Type
Tightens p2 p1 = (a : Action) -> Permits p2 a -> Permits p1 a

||| Tightening is reflexive: a policy is at least as strict as itself.
public export
tightensRefl : (p : Policy) -> Tightens p p
tightensRefl p = \a, perm => perm

||| Tightening is transitive: it is a genuine preorder on policies.
public export
tightensTrans : {p1, p2, p3 : Policy} ->
                Tightens p3 p2 -> Tightens p2 p1 -> Tightens p3 p1
tightensTrans t32 t21 = \a, perm => t21 a (t32 a perm)

--------------------------------------------------------------------------------
-- THEOREM 1: Monotone safety — the forbidden set only grows under tightening.
--------------------------------------------------------------------------------

||| MONOTONE SAFETY (downward-closure of permission, in forbidden form):
||| if `p2` tightens `p1`, then anything `p1` forbids is still forbidden by
||| `p2`. Tightening a policy never re-permits a previously-forbidden action.
|||
||| Proof: suppose `p1` forbids `a` but `p2` does NOT forbid it. By dichotomy
||| `p2 a = Allow`, i.e. `p2` permits `a`; tightening then gives `p1` permits
||| `a`, contradicting `p1` forbids `a`. So `p2 a = Deny`.
public export
tighteningPreservesForbidden : {p1, p2 : Policy} -> {a : Action} ->
                               Tightens p2 p1 -> Forbids p1 a -> Forbids p2 a
tighteningPreservesForbidden t forb1 =
  case verdictDichotomy (p2 a) of
    Right denyEq  => denyEq
    Left allowEq  =>
      -- allowEq : p2 a = Allow = Permits p2 a ; t a allowEq : Permits p1 a
      -- forb1   : p1 a = Deny ; contradiction.
      absurd (permitForbidExclusive p1 a (t a allowEq) forb1)

||| Equivalent CONTRAPOSITIVE phrasing kept for the API surface: under
||| tightening, if `p2` permits an action then `p1` permitted it (this is just
||| the definition of `Tightens`, restated as a named law).
public export
tighteningShrinksPermitted : {p1, p2 : Policy} -> {a : Action} ->
                             Tightens p2 p1 -> Permits p2 a -> Permits p1 a
tighteningShrinksPermitted t perm2 = t a perm2

--------------------------------------------------------------------------------
-- Conjunction of policies.
--------------------------------------------------------------------------------

||| Conjoin two policies: the result permits an action only when BOTH permit it,
||| and forbids it otherwise. This is how an ethical engine layers an extra
||| constraint set on top of an existing one.
public export
andPolicy : Policy -> Policy -> Policy
andPolicy p1 p2 a =
  case p1 a of
    Allow => p2 a
    Deny  => Deny

--------------------------------------------------------------------------------
-- THEOREM 2: Conjunction composition is sound.
--------------------------------------------------------------------------------

||| If the conjunction permits an action, then the FIRST conjunct permits it.
||| Proof by case on `p1 a`: if it were `Deny`, the conjunction would be `Deny`,
||| contradicting the `= Allow` hypothesis.
public export
andPermitsLeft : (p1, p2 : Policy) -> (a : Action) ->
                 Permits (andPolicy p1 p2) a -> Permits p1 a
andPermitsLeft p1 p2 a perm with (p1 a) proof eqp1
  andPermitsLeft p1 p2 a perm | Allow = Refl
  andPermitsLeft p1 p2 a perm | Deny  =
    -- with p1 a = Deny, andPolicy reduces to Deny, so perm : Deny = Allow.
    absurd perm

||| If the conjunction permits an action, then the SECOND conjunct permits it.
||| When `p1 a = Allow`, `andPolicy p1 p2 a` reduces to `p2 a`, so the
||| hypothesis IS `p2 a = Allow`.
public export
andPermitsRight : (p1, p2 : Policy) -> (a : Action) ->
                  Permits (andPolicy p1 p2) a -> Permits p2 a
andPermitsRight p1 p2 a perm with (p1 a) proof eqp1
  andPermitsRight p1 p2 a perm | Allow = perm
  andPermitsRight p1 p2 a perm | Deny  = absurd perm

||| Full composition soundness: conjunction-permission gives BOTH permissions.
public export
andPermitsBoth : (p1, p2 : Policy) -> (a : Action) ->
                 Permits (andPolicy p1 p2) a -> (Permits p1 a, Permits p2 a)
andPermitsBoth p1 p2 a perm =
  (andPermitsLeft p1 p2 a perm, andPermitsRight p1 p2 a perm)

||| Conversely, if both conjuncts permit, the conjunction permits.
||| Together with `andPermitsBoth` this is an iff: conjunction-permission is
||| exactly the pairwise conjunction of permissions.
public export
bothPermitsAnd : (p1, p2 : Policy) -> (a : Action) ->
                 Permits p1 a -> Permits p2 a -> Permits (andPolicy p1 p2) a
bothPermitsAnd p1 p2 a perm1 perm2 with (p1 a) proof eqp1
  bothPermitsAnd p1 p2 a perm1 perm2 | Allow = perm2
  bothPermitsAnd p1 p2 a perm1 perm2 | Deny  =
    -- with p1 a = Deny, perm1 : Deny = Allow is absurd.
    absurd perm1

||| Conjunction tightens its first conjunct: `andPolicy p1 p2` is at least as
||| strict as `p1`. (Hence, by Theorem 1, it can only forbid more than `p1`.)
public export
andTightensLeft : (p1, p2 : Policy) -> Tightens (andPolicy p1 p2) p1
andTightensLeft p1 p2 = \a, perm => andPermitsLeft p1 p2 a perm

||| Conjunction tightens its second conjunct too.
public export
andTightensRight : (p1, p2 : Policy) -> Tightens (andPolicy p1 p2) p2
andTightensRight p1 p2 = \a, perm => andPermitsRight p1 p2 a perm

--------------------------------------------------------------------------------
-- Sound + complete decision procedure for permission under a policy.
--------------------------------------------------------------------------------

||| Decide whether a policy permits an action. SOUND: a `Yes` carries a real
||| `Permits` proof. COMPLETE: a `No` carries a real refutation.
public export
decPermits : (p : Policy) -> (a : Action) -> Dec (Permits p a)
decPermits p a with (p a) proof eq
  decPermits p a | Allow = Yes Refl
  decPermits p a | Deny  =
    No (\perm => absurd perm)

--------------------------------------------------------------------------------
-- Sample policies built over the SHARED model.
--------------------------------------------------------------------------------

||| The static base policy: read the verdict already attached to the action.
public export
basePolicy : Policy
basePolicy = verdictOf

||| A strictly stronger policy that additionally forbids EVERY `DeployHarm`
||| action regardless of its attached verdict (e.g. a freshly added "no harm
||| deployment, ever" constraint). On non-DeployHarm actions it agrees with
||| the base policy.
public export
noHarmDeployPolicy : Policy
noHarmDeployPolicy (DeployHarm _ _ _) = Deny
noHarmDeployPolicy a                  = verdictOf a

--------------------------------------------------------------------------------
-- POSITIVE controls.
--------------------------------------------------------------------------------

||| The base policy permits the benign informational action from `Semantics`.
public export
basePermitsSafeInform : Permits Invariants.basePolicy Semantics.safeInform
basePermitsSafeInform = Refl

||| `noHarmDeployPolicy` genuinely tightens the base policy (machine-checked,
||| quantified over all actions). This is a positive instance of Theorem 1's
||| hypothesis.
public export
noHarmTightensBase : Tightens Invariants.noHarmDeployPolicy Invariants.basePolicy
noHarmTightensBase (Inform v)         perm = perm
noHarmTightensBase (Query v)          perm = perm
noHarmTightensBase (DeployHarm d s v) perm = absurd perm
  -- For DeployHarm, noHarmDeployPolicy = Deny, so perm : Deny = Allow is absurd.

||| Live application of Theorem 1: because `noHarmDeployPolicy` tightens the
||| base policy and the base policy forbids `forbiddenDeploy`, the tightened
||| policy still forbids it. (Both base and tightened forbid here; the point is
||| that monotone safety is witnessed on a concrete pair.)
public export
forbiddenStaysForbidden :
  Forbids Invariants.noHarmDeployPolicy Semantics.forbiddenDeploy
forbiddenStaysForbidden =
  tighteningPreservesForbidden
    {p1 = basePolicy} {p2 = noHarmDeployPolicy} {a = forbiddenDeploy}
    noHarmTightensBase Refl

||| Composition positive control: under `andPolicy basePolicy basePolicy`,
||| the benign action is permitted, and decomposes to both conjuncts.
public export
andPermitsSafeInform :
  ( Permits Invariants.basePolicy Semantics.safeInform
  , Permits Invariants.basePolicy Semantics.safeInform )
andPermitsSafeInform =
  andPermitsBoth basePolicy basePolicy safeInform Refl

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls.
--------------------------------------------------------------------------------

||| Non-vacuity of monotone safety: the tightened policy does NOT permit the
||| forbidden action. Any such permission would, with `forbiddenStaysForbidden`,
||| give `Deny = Allow`. Machine-checked `Not (...)`.
public export
tightenedRefusesForbidden :
  Not (Permits Invariants.noHarmDeployPolicy Semantics.forbiddenDeploy)
tightenedRefusesForbidden perm =
  absurd (trans (sym perm) forbiddenStaysForbidden)

||| Non-vacuity of composition: the conjunction of the base policy with the
||| all-DeployHarm-denying policy does NOT permit `forbiddenDeploy`. If it did,
||| `andPermitsRight` would extract a `noHarmDeployPolicy` permission, which
||| `tightenedRefusesForbidden` refutes.
public export
andRefusesForbidden :
  Not (Permits (andPolicy Invariants.basePolicy Invariants.noHarmDeployPolicy)
               Semantics.forbiddenDeploy)
andRefusesForbidden perm =
  tightenedRefusesForbidden
    (andPermitsRight basePolicy noHarmDeployPolicy forbiddenDeploy perm)

||| A policy can NEVER both permit and forbid the same action — restated as a
||| concrete refutation that `basePolicy` simultaneously permits and forbids
||| the benign action (it permits it, so "forbids" is impossible).
public export
baseNotForbidsSafeInform :
  Not (Forbids Invariants.basePolicy Semantics.safeInform)
baseNotForbidsSafeInform forb =
  permitForbidExclusive basePolicy safeInform basePermitsSafeInform forb
