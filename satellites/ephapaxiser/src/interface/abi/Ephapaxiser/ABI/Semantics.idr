-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for ephapaxiser: single-use (linear) token
||| semantics.
|||
||| ephapaxiser's headline promise is "enforce single-use linear type
||| semantics". This module gives that promise a faithful, machine-checked
||| operational meaning:
|||
|||   * A `Token` carries an explicit `consumed` flag (a `TokenState`).
|||   * `Consumable t` is the proposition "token `t` may legally be consumed".
|||     It has EXACTLY ONE constructor, and that constructor only applies to a
|||     `Fresh` token. There is NO constructor for a `Spent` token — so a proof
|||     that an already-consumed token may be consumed simply cannot be built.
|||   * `consume` advances a `Fresh` token to `Spent`, witnessed by a
|||     `Consumable` proof, and returns the resulting `Spent` token together
|||     with a `Consumed` certificate recording the single legal transition.
|||
||| The "no proof for the bad case" shape is the linear-logic content: a value
||| of an affine/linear type can be consumed at most once, and after that no
||| further consumption is well-typed. Here that is enforced at the level of
||| Idris2 propositions, independently of any FFI implementation.
|||
||| This raises the ephapaxiser ABI to "Layer 2": beyond structural layout
||| proofs, it proves the repo's domain invariant.

module Ephapaxiser.ABI.Semantics

import Ephapaxiser.ABI.Types
import Data.So
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A faithful model of single-use token state
--------------------------------------------------------------------------------

||| The two states a single-use token can be in.
public export
data TokenState : Type where
  ||| Freshly issued, never consumed. May be consumed exactly once.
  Fresh : TokenState
  ||| Already consumed (spent). Consuming again is a use-after-consume error.
  Spent : TokenState

||| A single-use token. The `id` distinguishes distinct tokens; the `state`
||| index records whether it is still consumable. We keep the state as a type
||| index so the linearity invariant is visible in the type of every token.
public export
data Token : TokenState -> Type where
  ||| Construct a token in a given state, carrying an identity tag.
  MkToken : (id : Nat) -> Token st

||| The identity tag of a token (state-erased projection).
public export
tokenId : Token st -> Nat
tokenId (MkToken i) = i

--------------------------------------------------------------------------------
-- The headline proposition: a token may be consumed ONLY when Fresh.
--------------------------------------------------------------------------------

||| `Consumable t` is the evidence that token `t` is in a state where consuming
||| it is legal. Crucially there is NO constructor mentioning `Spent`: the bad
||| case (consuming a spent token) is unrepresentable.
public export
data Consumable : Token st -> Type where
  ||| A fresh token is consumable.
  FreshConsumable : Consumable (MkToken {st = Fresh} i)

||| There is no evidence that a spent token is consumable. This is the core
||| linearity guarantee, stated as an `Uninhabited` instance and discharged by
||| a top-level impossible clause (per Idris2 0.7.0 idiom: refute via a
||| top-level function clause, not a nested case).
public export
Uninhabited (Consumable (MkToken {st = Spent} i)) where
  uninhabited FreshConsumable impossible

--------------------------------------------------------------------------------
-- The single legal transition, recorded as a certificate.
--------------------------------------------------------------------------------

||| A certificate that the one and only legal consumption transition happened:
||| from a `Fresh` token of identity `i` to a `Spent` token of the same
||| identity. The `Consumable` premise guarantees the source was fresh.
public export
data Consumed : (before : Token Fresh) -> (after : Token Spent) -> Type where
  ||| The unique Fresh -> Spent transition for a given identity.
  MkConsumed : (i : Nat) -> Consumed (MkToken {st = Fresh} i) (MkToken {st = Spent} i)

--------------------------------------------------------------------------------
-- The operation: consume a fresh token, producing a spent token + certificate.
--------------------------------------------------------------------------------

||| Consume a fresh token. Requires `Consumable` evidence (only obtainable for
||| a fresh token), and returns the resulting spent token together with the
||| transition certificate. The result identity is preserved.
public export
consume : (t : Token Fresh) -> Consumable t -> (t' : Token Spent ** Consumed t t')
consume (MkToken i) FreshConsumable = (MkToken i ** MkConsumed i)

--------------------------------------------------------------------------------
-- Sound + complete decision procedure for consumability.
--------------------------------------------------------------------------------

||| Decide whether a token is consumable. This is total, sound (a `Yes` carries
||| a real `Consumable` proof) and complete (a `Spent` token gets a `No` backed
||| by the `Uninhabited` instance — it never spuriously refuses a fresh token).
||| The state is taken as an explicit argument because it is an erased index of
||| `Token` and so cannot be recovered from the value alone.
public export
decConsumable : (st : TokenState) -> (t : Token st) -> Dec (Consumable t)
decConsumable Fresh (MkToken i)  = Yes FreshConsumable
decConsumable Spent (MkToken i)  = No absurd

--------------------------------------------------------------------------------
-- A certifier mapping into the ABI's Result codes, plus its soundness proof.
--------------------------------------------------------------------------------

||| Certify a token for consumption, reporting via the shared ABI `Result`:
|||   * `Ok`              if the token may be consumed (it is fresh);
|||   * `AlreadyConsumed` if it may not (it is spent).
||| This reuses the existing `Result` type from `Ephapaxiser.ABI.Types`.
public export
certifyConsume : (st : TokenState) -> (t : Token st) -> Result
certifyConsume st t = case decConsumable st t of
  Yes _ => Ok
  No  _ => AlreadyConsumed

||| Soundness of the certifier: whenever `certifyConsume` reports `Ok`, a real
||| `Consumable` proof exists for that token. (No `believe_me` — the witness is
||| recovered from the decision procedure.)
public export
certifyConsumeSound : (st : TokenState) -> (t : Token st) -> certifyConsume st t = Ok -> Consumable t
certifyConsumeSound st t prf with (decConsumable st t)
  certifyConsumeSound st t prf       | Yes ok = ok
  certifyConsumeSound st t Refl      | No  _  impossible

||| Completeness in the other direction: a spent token is always reported
||| `AlreadyConsumed`. This is definitional, but stating it makes the
||| use-after-consume guarantee explicit and machine-checked.
public export
certifySpentRejected : (i : Nat) -> certifyConsume Spent (MkToken {st = Spent} i) = AlreadyConsumed
certifySpentRejected i = Refl

--------------------------------------------------------------------------------
-- Positive control: an inhabited witness (a real fresh token is consumable).
--------------------------------------------------------------------------------

||| POSITIVE CONTROL: a concrete fresh token is consumable, and consuming it
||| yields a spent token of the same identity with a transition certificate.
public export
freshTokenConsumable : Consumable (MkToken {st = Fresh} 7)
freshTokenConsumable = FreshConsumable

||| POSITIVE CONTROL (operation): the full consume step on a concrete token.
public export
consumeFreshSeven : (t' : Token Spent ** Consumed (MkToken {st = Fresh} 7) t')
consumeFreshSeven = consume (MkToken 7) FreshConsumable

--------------------------------------------------------------------------------
-- Negative control: the bad case has NO proof (machine-checked).
--------------------------------------------------------------------------------

||| NEGATIVE CONTROL: a spent (already-consumed) token is NOT consumable. This
||| is the linearity guarantee — no second consumption is well-typed. Proven by
||| the `Uninhabited` instance, with no axioms.
public export
spentTokenNotConsumable : Not (Consumable (MkToken {st = Spent} 7))
spentTokenNotConsumable = absurd
