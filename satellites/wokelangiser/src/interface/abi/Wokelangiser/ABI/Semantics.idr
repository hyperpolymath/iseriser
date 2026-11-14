-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for wokelangiser: consent-gated data actions.
|||
||| Headline property (Layer 2): a data action over personal data can only be
||| certified *Permitted* when the consent ledger records *Active* consent for
||| precisely that action. There is no constructor that admits a permitted
||| action without active recorded consent, so "permitted without consent" is
||| not merely discouraged — it is unrepresentable.
|||
||| The module supplies:
|||   * a faithful ADT model of data actions and a consent ledger;
|||   * the `Permitted` proposition whose sole constructor pins the ledger
|||     lookup to `Just Active` (no constructor for the bad case);
|||   * a sound + complete `Dec`ision procedure `decPermitted`;
|||   * a certifier `certifyPermitted` returning a `Result`, plus a soundness
|||     theorem `certifyPermittedSound`;
|||   * a positive control (an explicit `Permitted` witness) and a negative
|||     control (`Not (Permitted ...)` for an action whose consent is missing /
|||     not Active), both machine-checked.

module Wokelangiser.ABI.Semantics

import Wokelangiser.ABI.Types
import Data.So
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful domain model
--------------------------------------------------------------------------------

||| A data action over personal data. Each requires consent before it may run.
public export
data Action : Type where
  ||| Collect personal data from the data subject
  Collect : Action
  ||| Process previously collected data
  Process : Action
  ||| Share data with a third party
  Share   : Action
  ||| Persist data to long-term storage
  Store   : Action

||| Actions are decidably equal (used by the ledger resolver). Off-diagonal
||| cases discharge disequality explicitly (no `Uninhabited (x = y)` exists).
public export
DecEq Action where
  decEq Collect Collect = Yes Refl
  decEq Process Process = Yes Refl
  decEq Share   Share   = Yes Refl
  decEq Store   Store   = Yes Refl
  decEq Collect Process = No (\case Refl impossible)
  decEq Collect Share   = No (\case Refl impossible)
  decEq Collect Store   = No (\case Refl impossible)
  decEq Process Collect = No (\case Refl impossible)
  decEq Process Share   = No (\case Refl impossible)
  decEq Process Store   = No (\case Refl impossible)
  decEq Share   Collect = No (\case Refl impossible)
  decEq Share   Process = No (\case Refl impossible)
  decEq Share   Store   = No (\case Refl impossible)
  decEq Store   Collect = No (\case Refl impossible)
  decEq Store   Process = No (\case Refl impossible)
  decEq Store   Share   = No (\case Refl impossible)

||| A single recorded consent entry: which action it concerns, and the
||| lifecycle state of that consent (reusing `ConsentState` from Types).
public export
record ConsentEntry where
  constructor MkEntry
  forAction : Action
  state     : ConsentState

||| The consent ledger: an ordered list of recorded consent entries. This is
||| the only authority for whether an action may proceed.
public export
Ledger : Type
Ledger = List ConsentEntry

||| Resolve the recorded consent state for an action. The first matching entry
||| wins (later entries are shadowed), modelling "most authoritative record".
public export
lookupConsent : Action -> Ledger -> Maybe ConsentState
lookupConsent _ [] = Nothing
lookupConsent a (MkEntry b s :: rest) =
  case decEq a b of
    Yes _ => Just s
    No  _ => lookupConsent a rest

--------------------------------------------------------------------------------
-- The headline property: Permitted
--------------------------------------------------------------------------------

||| `Permitted env act` witnesses that action `act` is permitted under ledger
||| `env`. The SOLE constructor demands a proof that the ledger resolves `act`
||| to `Just Active`. There is deliberately NO constructor for any other
||| resolved state (Pending / Granted / Revoked) nor for `Nothing` (no record).
||| Hence an action lacking active recorded consent has no `Permitted` witness.
public export
data Permitted : (env : Ledger) -> (act : Action) -> Type where
  ||| Permission certificate: built only from a ledger lookup yielding Active.
  PermitActive :
    (prf : lookupConsent act env = Just Active) -> Permitted env act

--------------------------------------------------------------------------------
-- Term-level transport helper (avoids case-of-Refl on stuck applications)
--------------------------------------------------------------------------------

||| Injectivity of `Just`. Used to transport an equality whose LHS is a stuck
||| `lookupConsent` application into a usable `ConsentState` equality without a
||| `case ... of Refl` block (which would fail coverage on a stuck operand).
private
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Sound + complete decision procedure
--------------------------------------------------------------------------------

||| Decide `Permitted env act`. Sound: every `Yes` carries a real witness.
||| Complete: every `No` carries a refutation valid for the actual ledger.
||| The `with ... proof eq` pins the symbolic lookup result to `eq` so both
||| branches can reason about it.
public export
decPermitted : (env : Ledger) -> (act : Action) -> Dec (Permitted env act)
decPermitted env act with (lookupConsent act env) proof eq
  _ | Just Active  = Yes (PermitActive eq)
  _ | Just Pending = No (\(PermitActive prf) =>
        case trans (sym prf) eq of Refl impossible)
  _ | Just Granted = No (\(PermitActive prf) =>
        case trans (sym prf) eq of Refl impossible)
  _ | Just Revoked = No (\(PermitActive prf) =>
        case trans (sym prf) eq of Refl impossible)
  _ | Nothing      = No (\(PermitActive prf) =>
        case trans (sym prf) eq of Refl impossible)

--------------------------------------------------------------------------------
-- Certifier + soundness
--------------------------------------------------------------------------------

||| Certify an action against a ledger, returning an ABI `Result`.
||| `Ok` iff permission is provable; `ConsentRequired` otherwise.
||| Internal: map a decision to a `Result`. Kept separate so soundness /
||| completeness can `with`-match the SAME `Dec` value the certifier consumed,
||| letting the result reduce in each branch.
public export
resultOfDec : Dec p -> Result
resultOfDec (Yes _) = Ok
resultOfDec (No  _) = ConsentRequired

||| Certify an action against a ledger, returning an ABI `Result`.
||| `Ok` iff permission is provable; `ConsentRequired` otherwise.
public export
certifyPermitted : (env : Ledger) -> (act : Action) -> Result
certifyPermitted env act = resultOfDec (decPermitted env act)

||| Soundness: if the certifier returns `Ok`, a genuine `Permitted` witness
||| exists. (No way to forge `Ok` without active recorded consent.)
public export
certifyPermittedSound :
  (env : Ledger) -> (act : Action) ->
  certifyPermitted env act = Ok -> Permitted env act
certifyPermittedSound env act prf with (decPermitted env act)
  certifyPermittedSound env act prf    | Yes w = w
  certifyPermittedSound env act Refl   | No  _ impossible

||| Completeness of the certifier: a real `Permitted` witness forces `Ok`.
public export
certifyPermittedComplete :
  (env : Ledger) -> (act : Action) ->
  Permitted env act -> certifyPermitted env act = Ok
certifyPermittedComplete env act w with (decPermitted env act)
  certifyPermittedComplete env act w | Yes _    = Refl
  certifyPermittedComplete env act w | No notP  = absurd (notP w)

||| Bridge to the consent lifecycle: a permitted action's recorded consent is
||| in the `Active` state. Demonstrates the property is about real state, not a
||| token. Transport is term-level via `justInj` (idiom: no case-of-Refl on a
||| stuck `lookupConsent` LHS).
public export
permittedImpliesActive :
  (env : Ledger) -> (act : Action) ->
  Permitted env act -> lookupConsent act env = Just Active
permittedImpliesActive env act (PermitActive prf) = prf

--------------------------------------------------------------------------------
-- Positive control (inhabited witness)
--------------------------------------------------------------------------------

||| A ledger that records ACTIVE consent for `Process` (and a stale Revoked
||| entry for `Share`, to prove non-Active records do not leak permission).
public export
sampleLedger : Ledger
sampleLedger =
  [ MkEntry Process Active
  , MkEntry Share   Revoked
  ]

||| POSITIVE control: processing is permitted because the ledger records Active
||| consent for it. The lookup reduces on concrete data, so `Refl` discharges.
public export
processPermitted : Permitted Semantics.sampleLedger Process
processPermitted = PermitActive Refl

--------------------------------------------------------------------------------
-- Negative controls (machine-checked refutations of the bad case)
--------------------------------------------------------------------------------

||| NEGATIVE control 1: sharing is NOT permitted — its consent is Revoked, not
||| Active. A `Permitted` witness would force `Just Revoked = Just Active`.
public export
shareNotPermitted : Not (Permitted Semantics.sampleLedger Share)
shareNotPermitted (PermitActive prf) = case justInj prf of Refl impossible

||| NEGATIVE control 2: collection is NOT permitted — there is no record for it
||| at all, so the lookup is `Nothing` and cannot equal `Just Active`.
public export
collectNotPermitted : Not (Permitted Semantics.sampleLedger Collect)
collectNotPermitted (PermitActive prf) = case prf of Refl impossible
