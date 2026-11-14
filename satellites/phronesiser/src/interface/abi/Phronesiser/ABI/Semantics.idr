-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Phronesiser: ethical safety of action gating.
|||
||| Headline domain property ("Add provably safe ethical constraints to AI
||| agents"): a deontic policy partitions an agent's candidate actions into
||| PERMITTED and FORBIDDEN. We define an `ActionPermitted` proposition that
||| has NO constructor for a forbidden action. Therefore a forbidden action
||| can NEVER be certified permitted — the safety guarantee an ethical
||| constraint engine must provide. The decision procedure is sound AND
||| complete (returns a genuine `Dec`), and the certifier's soundness is
||| machine-checked: if `certifyPermitted a = Permitted`, then `ActionPermitted`
||| holds. Positive and negative controls pin non-vacuity.
|||
||| This is not a runtime test: every fact below is discharged by the Idris2
||| type checker. The negative control `forbiddenNeverPermitted` is the core
||| safety theorem in `Not (...)` form.

module Phronesiser.ABI.Semantics

import Phronesiser.ABI.Types
import Data.So
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A faithful, minimal model of agent actions.
--------------------------------------------------------------------------------

||| The classification a policy assigns to an action.
||| - Allow: the action is permissible.
||| - Deny : the action is forbidden (a prohibition applies).
public export
data Verdict = Allow | Deny

||| A candidate agent action, carrying the policy verdict the ethical engine
||| has resolved for it. `DeployHarm` models an action a sound policy must
||| forbid (it carries harm); `Inform` / `Query` model benign actions.
|||
||| The verdict field is the faithful link to the deontic model in Types.idr:
||| a `Prohibition`-modality constraint that fires yields `Deny`, an
||| absent/`Permission` constraint yields `Allow`.
public export
data Action : Type where
  ||| A purely informational action (e.g. answer a question). Policy: Allow.
  Inform : (verdict : Verdict) -> Action
  ||| A read-only query action. Policy: Allow.
  Query : (verdict : Verdict) -> Action
  ||| An action that deploys harm of a given domain/severity. A sound ethical
  ||| policy assigns this `Deny`. This is the "bad case".
  DeployHarm : (domain : HarmDomain) -> (severity : HarmSeverity) ->
               (verdict : Verdict) -> Action

||| Project the policy verdict out of an action (total over all constructors).
public export
verdictOf : Action -> Verdict
verdictOf (Inform v)         = v
verdictOf (Query v)          = v
verdictOf (DeployHarm _ _ v) = v

--------------------------------------------------------------------------------
-- The safety proposition: NO constructor for a denied action.
--------------------------------------------------------------------------------

||| `ActionPermitted a` is inhabited exactly when the policy verdict for `a`
||| is `Allow`. There is deliberately NO constructor admitting `Deny`: a
||| forbidden action is structurally uncertifiable. This is the core encoding
||| of "provably safe ethical constraints".
public export
data ActionPermitted : Action -> Type where
  ||| The sole way to obtain a permission witness: the verdict is `Allow`.
  PermitAllow : (prf : verdictOf a = Allow) -> ActionPermitted a

--------------------------------------------------------------------------------
-- Verdicts are decidably equal (needed for a sound+complete decision).
--------------------------------------------------------------------------------

||| `Deny = Allow` is absurd — the contradiction that powers safety.
public export
Uninhabited (Deny = Allow) where
  uninhabited Refl impossible

||| `Allow = Deny` is absurd too.
public export
Uninhabited (Allow = Deny) where
  uninhabited Refl impossible

||| Term-level transport helper (no case-of-Refl on stuck terms, per idioms):
||| from `verdictOf a = Allow` rebuild any needed equality. Here we only need
||| `Uninhabited` instances above, so no extra transport is required.

--------------------------------------------------------------------------------
-- Sound + complete decision procedure returning a genuine `Dec`.
--------------------------------------------------------------------------------

||| Decide whether an action is permitted. SOUND: a `Yes` carries a real
||| `ActionPermitted` witness. COMPLETE: a `No` carries a real refutation,
||| so nothing permitted is ever rejected.
public export
decActionPermitted : (a : Action) -> Dec (ActionPermitted a)
decActionPermitted a with (verdictOf a) proof eq
  _ | Allow = Yes (PermitAllow eq)
  _ | Deny  = No (\ (PermitAllow prf) =>
                   -- prf : verdictOf a = Allow, eq : verdictOf a = Deny
                   -- trans (sym eq) prf : Deny = Allow, which is absurd.
                   absurd (trans (sym eq) prf))

--------------------------------------------------------------------------------
-- Certifier + machine-checked soundness.
--------------------------------------------------------------------------------

||| The ethical engine's certification verdict for an action.
||| Reuses the ABI `Result` type from Types.idr for the FFI boundary:
||| `Ok` == certified permitted, `ConstraintViolation` == refused.
public export
certifyPermitted : (a : Action) -> Result
certifyPermitted a = case decActionPermitted a of
  Yes _ => Ok
  No  _ => ConstraintViolation

||| SOUNDNESS of the certifier: if it returns `Ok`, the action really is
||| permitted. The proof inspects the same `Dec` the certifier used.
public export
certifyPermittedSound : (a : Action) -> certifyPermitted a = Ok -> ActionPermitted a
certifyPermittedSound a prf with (decActionPermitted a)
  certifyPermittedSound a prf      | Yes w = w
  certifyPermittedSound a Refl     | No _ impossible

--------------------------------------------------------------------------------
-- Concrete sample actions.
--------------------------------------------------------------------------------

||| A benign informational action the policy allows.
public export
safeInform : Action
safeInform = Inform Allow

||| A harmful deployment action the policy forbids (critical physical harm).
public export
forbiddenDeploy : Action
forbiddenDeploy = DeployHarm Physical Critical Deny

--------------------------------------------------------------------------------
-- POSITIVE control: an explicit, inhabited permission witness.
--------------------------------------------------------------------------------

||| The allowed action genuinely carries a permission witness.
public export
safeInformPermitted : ActionPermitted Semantics.safeInform
safeInformPermitted = PermitAllow Refl

--------------------------------------------------------------------------------
-- NEGATIVE control (the core safety theorem): a forbidden action can NEVER
-- be certified permitted.
--------------------------------------------------------------------------------

||| SAFETY: there is no permission witness for the forbidden action.
||| `verdictOf forbiddenDeploy = Deny`, so any `PermitAllow prf` would give
||| `Deny = Allow`, which is absurd. Machine-checked.
public export
forbiddenNeverPermitted : Not (ActionPermitted Semantics.forbiddenDeploy)
forbiddenNeverPermitted (PermitAllow prf) = absurd prf

||| Corollary at the certifier level: the forbidden action is never `Ok`.
||| If it were, soundness would hand us a witness the safety theorem refutes.
public export
forbiddenNeverCertifiedOk : Not (certifyPermitted Semantics.forbiddenDeploy = Ok)
forbiddenNeverCertifiedOk prf =
  forbiddenNeverPermitted (certifyPermittedSound Semantics.forbiddenDeploy prf)
