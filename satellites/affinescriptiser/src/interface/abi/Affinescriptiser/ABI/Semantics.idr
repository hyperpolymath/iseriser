-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Affinescriptiser (ABI Layer 2).
|||
||| Headline domain property: AFFINE USAGE. A resource (variable) may be used
||| AT MOST ONCE. We model a program fragment as a *usage trace* — the ordered
||| sequence of variable uses the codegen emits. The property `AffineOk` holds
||| of a trace exactly when no variable is used twice: every use refers to a
||| variable that has not yet appeared earlier in the trace.
|||
||| The key faithfulness point (mirroring the typedqliser InjectionFree
||| exemplar): there is NO `AffineOk` constructor for the "bad case" (a repeated
||| use). A double-use trace is therefore *uninhabited* at the proof level —
||| the type checker can never construct a witness that a double-use program is
||| affine-safe. We give a sound+complete decision procedure returning a real
||| `Dec`, a certifier into the ABI `Result` type with a soundness theorem, and
||| both a positive control (a witness for a safe trace) and a negative control
||| (a machine-checked `Not` for a double-use trace).

module Affinescriptiser.ABI.Semantics

import Affinescriptiser.ABI.Types
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful domain model
--------------------------------------------------------------------------------

||| A variable identifier. Concrete, decidable identity (Nat has DecEq).
public export
Var : Type
Var = Nat

||| A usage trace: the ordered sequence of variable uses emitted by codegen.
||| `[]` is the empty program; `v :: rest` means "use v, then run rest".
public export
Trace : Type
Trace = List Var

--------------------------------------------------------------------------------
-- The headline property: AffineOk
--------------------------------------------------------------------------------

||| `AffineOk t` holds when no variable in trace `t` is used more than once.
|||
||| There are exactly two ways to be affine-safe:
|||   * the empty trace is trivially safe; and
|||   * a non-empty trace `v :: rest` is safe when `v` does NOT occur in `rest`
|||     (so this is `v`'s only use here) AND `rest` is itself safe.
|||
||| Crucially there is NO constructor for "v occurs again in rest" — a
||| double-use trace simply has no inhabitant of this type. Affine safety is
||| therefore a genuine structural invariant, not a runtime check.
public export
data AffineOk : Trace -> Type where
  ||| The empty program uses nothing, so it is affine-safe.
  NilOk : AffineOk []
  ||| Using `v` is safe when `v` is not used again later, and the rest is safe.
  ConsOk : (notLater : Not (Elem v rest)) -> AffineOk rest -> AffineOk (v :: rest)

--------------------------------------------------------------------------------
-- Inversion lemmas (term-level, to avoid stuck case-of-Refl)
--------------------------------------------------------------------------------

||| If `v :: rest` is affine-safe then `v` is not used again in `rest`.
export
headNotLater : AffineOk (v :: rest) -> Not (Elem v rest)
headNotLater (ConsOk notLater _) = notLater

||| If `v :: rest` is affine-safe then `rest` is affine-safe.
export
tailOk : AffineOk (v :: rest) -> AffineOk rest
tailOk (ConsOk _ ok) = ok

--------------------------------------------------------------------------------
-- Sound + complete decision procedure
--------------------------------------------------------------------------------

||| Decide affine safety of a trace. Returns a genuine `Dec (AffineOk t)`:
||| a `Yes` carries a real proof, a `No` carries a real refutation built from
||| the inversion lemmas above. No `believe_me`, no postulates.
public export
decAffineOk : (t : Trace) -> Dec (AffineOk t)
decAffineOk [] = Yes NilOk
decAffineOk (v :: rest) =
  case isElem v rest of
    -- v is used again later: any AffineOk witness would contradict it.
    Yes used => No (\ok => headNotLater ok used)
    No notLater =>
      case decAffineOk rest of
        Yes restOk => Yes (ConsOk notLater restOk)
        No restBad => No (\ok => restBad (tailOk ok))

--------------------------------------------------------------------------------
-- Certifier into the ABI Result type + soundness theorem
--------------------------------------------------------------------------------

||| Certify a trace: `Ok` when affine-safe, `AffineViolation` (an existing ABI
||| Result code) when a variable is used more than once.
public export
certifyAffine : (t : Trace) -> Result
certifyAffine t = case decAffineOk t of
  Yes _ => Ok
  No  _ => AffineViolation

||| Soundness: if the certifier says `Ok`, the trace really is affine-safe.
||| We recover the witness the decision procedure found.
export
certifyAffineSound : (t : Trace) -> certifyAffine t = Ok -> AffineOk t
certifyAffineSound t prf with (decAffineOk t)
  certifyAffineSound t prf       | Yes ok  = ok
  certifyAffineSound t Refl      | No  _   impossible

||| Completeness (other direction): if the trace is affine-safe, the certifier
||| says `Ok`. Together with soundness this makes `certifyAffine` exact.
export
certifyAffineComplete : (t : Trace) -> AffineOk t -> certifyAffine t = Ok
certifyAffineComplete t ok with (decAffineOk t)
  certifyAffineComplete t ok  | Yes _   = Refl
  certifyAffineComplete t ok  | No bad  = absurd (bad ok)

--------------------------------------------------------------------------------
-- Positive control: an inhabited witness for a safe program
--------------------------------------------------------------------------------

||| A safe trace uses three distinct variables once each: [0, 1, 2].
||| The witness is explicit — each `Not (Elem ...)` is discharged by the
||| `Uninhabited (Elem x [])` instance and off-diagonal Nat decisions, all
||| of which reduce on concrete literals.
export
safeTraceAffineOk : AffineOk [0, 1, 2]
safeTraceAffineOk =
  ConsOk (\el => case el of
                   There (There el2) => absurd el2)
         (ConsOk (\el => case el of
                           There el1 => absurd el1)
                 (ConsOk absurd NilOk))

--------------------------------------------------------------------------------
-- Negative control: a double-use program is NOT affine-safe
--------------------------------------------------------------------------------

||| Variable 0 is used twice in [0, 0]. There is no `AffineOk` witness for it:
||| the head's `notLater` proof would have to refute `Elem 0 [0]`, but `0` is
||| right there (`Here`). Machine-checked refutation, the heart of the claim.
export
doubleUseNotAffineOk : Not (AffineOk [0, 0])
doubleUseNotAffineOk ok = headNotLater ok Here

||| A subtler double-use: variable 5 is reused after an intervening distinct
||| use of 7, in [5, 7, 5]. Still refuted: 5 reappears later in the tail.
export
spacedDoubleUseNotAffineOk : Not (AffineOk [5, 7, 5])
spacedDoubleUseNotAffineOk ok = headNotLater ok (There Here)
