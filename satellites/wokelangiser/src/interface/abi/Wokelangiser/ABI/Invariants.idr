-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariant proof for wokelangiser: consent *withdrawal*.
|||
||| Headline property (Layer 3 — distinct from and deeper than Layer 2):
||| REVOCATION MONOTONICITY. The Layer-2 `Semantics` theorem is static — it
||| says permission requires an `Active` record. This module reasons about a
||| *state transition*: the `revoke` operation that withdraws consent (GDPR
||| Article 7(3): "It shall be as easy to withdraw as to give consent"). We
||| prove that AFTER revoking consent for an action, that action can never be
||| `Permitted` — regardless of what the ledger said before, and regardless of
||| how many prior (even Active) records exist for it. The withdrawal entry is
||| authoritative because the resolver reads the most-recent record first.
|||
||| This is genuinely different from the grant theorem:
|||   * Layer 2: `Permitted env act` <=> `lookupConsent act env = Just Active`
|||     (a property of a *fixed* ledger).
|||   * Layer 3: for the *transformed* ledger `revoke act env`, permission is
|||     IMPOSSIBLE for `act`, and the transformation is monotone in the sense
|||     that it never re-enables a permission (a property of the *operation*).
|||
||| The module supplies, over the SAME model (`Action`, `Ledger`, `Permitted`,
||| `lookupConsent` imported from `Semantics`):
|||   * `revoke` — the withdrawal operation (prepends a `Revoked` record);
|||   * `revokeResolvesRevoked` — after revoke, the lookup is `Just Revoked`;
|||   * `revokeDeniesPermission` — THE Layer-3 theorem: revoked => never Permitted;
|||   * `revokeOverridesActive` — even an explicit prior Active record is
|||     overridden (non-vacuity: the hard case really is handled);
|||   * `revokeIdempotent` — revoking twice resolves identically (algebraic law);
|||   * `revokePreservesOthers` — revoking `a` does not disturb a *different*
|||     action `b` (a non-interference / locality law, with a fresh-implicit-free
|||     signature);
|||   * a sound+complete `Dec` for "is this action revoked?";
|||   * a POSITIVE control (a concrete `IsRevoked` witness) and a NEGATIVE /
|||     non-vacuity control (`Not (Permitted (revoke ...) ...)` on a ledger that
|||     previously granted Active consent), both machine-checked.

module Wokelangiser.ABI.Invariants

import Wokelangiser.ABI.Types
import Wokelangiser.ABI.Semantics
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- decEq reflexivity helper (decEq on Action does not reduce definitionally)
--------------------------------------------------------------------------------

||| For any action, `decEq act act` is a `Yes`. We need this because the resolver
||| branches on `decEq`, which does not reduce for a symbolic `act` (idiom 4).
||| Proven by exhaustive case analysis over the four constructors — no cheats.
private
decEqActSelf : (act : Action) -> (p : (act = act) ** decEq act act = Yes p)
decEqActSelf Collect = (Refl ** Refl)
decEqActSelf Process = (Refl ** Refl)
decEqActSelf Share   = (Refl ** Refl)
decEqActSelf Store   = (Refl ** Refl)

--------------------------------------------------------------------------------
-- The withdrawal operation
--------------------------------------------------------------------------------

||| Withdraw consent for `act`: record a fresh `Revoked` entry at the head of the
||| ledger. Because `lookupConsent` returns the FIRST matching entry, this new
||| record is authoritative and shadows every earlier record for `act`. This is
||| the operational meaning of GDPR Art. 7(3) withdrawal in this model.
public export
revoke : Action -> Ledger -> Ledger
revoke act env = MkEntry act Revoked :: env

--------------------------------------------------------------------------------
-- Core resolution lemma after withdrawal
--------------------------------------------------------------------------------

||| After withdrawing consent for `act`, the ledger resolves `act` to
||| `Just Revoked`. Proven by forcing the head `decEq act act` branch via
||| `decEqActSelf` and rewriting (idiom 4: cannot rely on `Refl` through decEq).
public export
revokeResolvesRevoked :
  (act : Action) -> (env : Ledger) ->
  lookupConsent act (revoke act env) = Just Revoked
revokeResolvesRevoked act env =
  let (p ** eq) = decEqActSelf act in
  -- lookupConsent act (MkEntry act Revoked :: env)
  --   = case decEq act act of { Yes _ => Just Revoked; No _ => ... }
  rewrite eq in Refl

--------------------------------------------------------------------------------
-- THE Layer-3 theorem: revocation monotonicity
--------------------------------------------------------------------------------

||| Injectivity of `Just`, used to transport the stuck-lookup equality without a
||| `case ... of Refl` on a stuck operand (idiom 3).
private
justInj' : {0 x, y : a} -> Just x = Just y -> x = y
justInj' Refl = Refl

||| `Revoked = Active` is uninhabited; expose it as an explicit refutation.
private
revokedNotActive : Revoked = Active -> Void
revokedNotActive Refl impossible

||| REVOCATION MONOTONICITY (headline). After consent for `act` is withdrawn,
||| `act` is NOT `Permitted` under the resulting ledger — no matter what the
||| prior ledger `env` recorded. A `Permitted` witness would force the resolved
||| state to be `Active`, but withdrawal pins it to `Revoked`; the contradiction
||| `Revoked = Active` discharges the case. This complements (does not restate)
||| the Layer-2 grant theorem: that one characterised permission on a fixed
||| ledger; this one proves the withdrawal *operation* removes permission.
public export
revokeDeniesPermission :
  (act : Action) -> (env : Ledger) ->
  Not (Permitted (revoke act env) act)
revokeDeniesPermission act env (PermitActive prf) =
  -- prf : lookupConsent act (revoke act env) = Just Active
  -- revokeResolvesRevoked : lookupConsent act (revoke act env) = Just Revoked
  revokedNotActive
    (justInj' (trans (sym (revokeResolvesRevoked act env)) prf))

--------------------------------------------------------------------------------
-- Non-vacuity: the HARD case (prior Active record) is genuinely overridden
--------------------------------------------------------------------------------

||| Withdrawal overrides an explicit prior `Active` grant. This is the case that
||| makes the theorem non-trivial: even if the data subject had previously
||| activated consent, the fresh `Revoked` head shadows it. Demonstrates the
||| resolver's "most-recent-wins" semantics actually does the work.
public export
revokeOverridesActive :
  (act : Action) -> (env : Ledger) ->
  lookupConsent act (revoke act (MkEntry act Active :: env)) = Just Revoked
revokeOverridesActive act env = revokeResolvesRevoked act (MkEntry act Active :: env)

--------------------------------------------------------------------------------
-- Algebraic law: withdrawal is idempotent at the resolution level
--------------------------------------------------------------------------------

||| Withdrawing twice resolves the action exactly as withdrawing once does:
||| both yield `Just Revoked`. (An idempotence law for the operation, distinct
||| in shape from monotonicity.)
public export
revokeIdempotent :
  (act : Action) -> (env : Ledger) ->
  lookupConsent act (revoke act (revoke act env))
    = lookupConsent act (revoke act env)
revokeIdempotent act env =
  trans (revokeResolvesRevoked act (revoke act env))
        (sym (revokeResolvesRevoked act env))

--------------------------------------------------------------------------------
-- Locality / non-interference law
--------------------------------------------------------------------------------

||| Withdrawing consent for one action does not disturb the resolution of a
||| DIFFERENT action. If `a /= b`, then looking up `b` after revoking `a` gives
||| the same answer as before. The head `MkEntry a Revoked` is skipped because
||| `decEq b a = No _`. (`a`, `b` bound explicitly — no fresh-implicit warning,
||| idiom 1.)
public export
revokePreservesOthers :
  (a : Action) -> (b : Action) -> (env : Ledger) ->
  Not (b = a) ->
  lookupConsent b (revoke a env) = lookupConsent b env
revokePreservesOthers a b env neq with (decEq b a)
  revokePreservesOthers a b env neq | Yes prf = absurd (neq prf)
  revokePreservesOthers a b env neq | No  _   = Refl

--------------------------------------------------------------------------------
-- A decidable, sound+complete predicate: "is this action revoked here?"
--------------------------------------------------------------------------------

||| `IsRevoked env act` witnesses that the ledger resolves `act` to `Revoked`.
||| Sole constructor pins the lookup to `Just Revoked` (mirrors `Permitted`).
public export
data IsRevoked : (env : Ledger) -> (act : Action) -> Type where
  RevokedRecord :
    (prf : lookupConsent act env = Just Revoked) -> IsRevoked env act

||| Decide `IsRevoked env act`. Sound (`Yes` carries a real witness) and
||| complete (`No` carries a refutation). The `with ... proof eq` pins the
||| symbolic lookup so each branch can reason (idiom mirrors `decPermitted`).
public export
decIsRevoked : (env : Ledger) -> (act : Action) -> Dec (IsRevoked env act)
decIsRevoked env act with (lookupConsent act env) proof eq
  _ | Just Revoked = Yes (RevokedRecord eq)
  _ | Just Active  = No (\(RevokedRecord prf) =>
        case trans (sym prf) eq of Refl impossible)
  _ | Just Pending = No (\(RevokedRecord prf) =>
        case trans (sym prf) eq of Refl impossible)
  _ | Just Granted = No (\(RevokedRecord prf) =>
        case trans (sym prf) eq of Refl impossible)
  _ | Nothing      = No (\(RevokedRecord prf) =>
        case trans (sym prf) eq of Refl impossible)

||| Bridge: a revoked action is never permitted (links the two predicates).
||| If both held, the lookup would be `Just Revoked` and `Just Active` at once.
public export
revokedExcludesPermitted :
  (env : Ledger) -> (act : Action) ->
  IsRevoked env act -> Not (Permitted env act)
revokedExcludesPermitted env act (RevokedRecord rprf) (PermitActive pprf) =
  revokedNotActive (justInj' (trans (sym rprf) pprf))

||| The withdrawal operation always produces an `IsRevoked` witness for its
||| target — i.e. `revoke` is a constructor of revoked-state. Ties the operation
||| to the decidable predicate.
public export
revokeProducesRevoked :
  (act : Action) -> (env : Ledger) -> IsRevoked (revoke act env) act
revokeProducesRevoked act env = RevokedRecord (revokeResolvesRevoked act env)

--------------------------------------------------------------------------------
-- POSITIVE control (inhabited witness)
--------------------------------------------------------------------------------

||| A ledger that records ACTIVE consent for `Process` — the strongest possible
||| prior state, so the controls exercise the override path.
public export
priorLedger : Ledger
priorLedger = [ MkEntry Process Active ]

||| POSITIVE control: after withdrawal, `Process` is recorded `Revoked`, and we
||| exhibit a concrete `IsRevoked` witness for it (lookup reduces on data).
public export
processRevoked : IsRevoked (revoke Process Invariants.priorLedger) Process
processRevoked = RevokedRecord Refl

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls (machine-checked refutations)
--------------------------------------------------------------------------------

||| NEGATIVE control (the crux): `Process` WAS Active in `priorLedger` (so the
||| Layer-2 theorem would grant it there), yet after `revoke Process` it is NOT
||| `Permitted`. This is the concrete instance of revocation monotonicity over
||| the override case — proving the theorem is non-vacuous.
public export
processNotPermittedAfterRevoke :
  Not (Permitted (revoke Process Invariants.priorLedger) Process)
processNotPermittedAfterRevoke = revokeDeniesPermission Process Invariants.priorLedger

||| Sanity / non-vacuity counter-check: BEFORE withdrawal the same action IS
||| permitted in `priorLedger` (concrete `Permitted` witness). Together with the
||| control above this shows `revoke` genuinely *changes* the verdict — it is not
||| vacuously denying an already-denied action.
public export
processPermittedBeforeRevoke : Permitted Invariants.priorLedger Process
processPermittedBeforeRevoke = PermitActive Refl
