-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Betlangiser (Idris2 ABI Layer 2).
|||
||| Betlangiser's headline is "ternary probabilistic modelling". The logical
||| substrate is three-valued (Kleene) logic over `Trit = T | U | F` (true /
||| unknown / false). This module proves that substrate is algebraically sound:
|||
|||   1. negation is an involution (`doubleNeg`: not3 (not3 x) = x);
|||   2. De Morgan holds (`deMorgan`: not3 (and3 x y) = or3 (not3 x) (not3 y));
|||   3. `Designated` (classical truth, = T) is a decidable proposition with a
|||      sound+complete `Dec`, a certifier proven sound, and `and3` preserves it;
|||   4. positive + negative controls, the negative ones machine-checking that the
|||      laws are non-vacuous (negation is genuinely not the identity; U and F are
|||      genuinely not designated).

module Betlangiser.ABI.Semantics

import Betlangiser.ABI.Types
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- The three truth values and the Kleene connectives
--------------------------------------------------------------------------------

public export
data Trit = T | U | F

public export
not3 : Trit -> Trit
not3 T = F
not3 U = U
not3 F = T

||| Kleene conjunction (the min under F < U < T).
public export
and3 : Trit -> Trit -> Trit
and3 F _ = F
and3 _ F = F
and3 T T = T
and3 T U = U
and3 U T = U
and3 U U = U

||| Kleene disjunction (the max under F < U < T).
public export
or3 : Trit -> Trit -> Trit
or3 T _ = T
or3 _ T = T
or3 F F = F
or3 F U = U
or3 U F = U
or3 U U = U

--------------------------------------------------------------------------------
-- Algebraic laws (universally quantified, proven by total case analysis)
--------------------------------------------------------------------------------

||| Negation is an involution.
export
doubleNeg : (x : Trit) -> not3 (not3 x) = x
doubleNeg T = Refl
doubleNeg U = Refl
doubleNeg F = Refl

||| De Morgan: negating a conjunction is the disjunction of the negations.
export
deMorgan : (x, y : Trit) -> not3 (and3 x y) = or3 (not3 x) (not3 y)
deMorgan T T = Refl
deMorgan T U = Refl
deMorgan T F = Refl
deMorgan U T = Refl
deMorgan U U = Refl
deMorgan U F = Refl
deMorgan F T = Refl
deMorgan F U = Refl
deMorgan F F = Refl

--------------------------------------------------------------------------------
-- Designated truth as a decidable proposition (no inhabitant for U or F)
--------------------------------------------------------------------------------

||| A `Designated` value is classically true — in Kleene logic, exactly `T`.
||| There is no constructor for `U` or `F`.
public export
data Designated : Trit -> Type where
  DesT : Designated T

export
Uninhabited (Designated U) where
  uninhabited DesT impossible

export
Uninhabited (Designated F) where
  uninhabited DesT impossible

public export
decDesignated : (t : Trit) -> Dec (Designated t)
decDesignated T = Yes DesT
decDesignated U = No absurd
decDesignated F = No absurd

||| Truth-functional soundness: conjunction preserves designation.
export
andDesignated : Designated x -> Designated y -> Designated (and3 x y)
andDesignated DesT DesT = DesT

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound
--------------------------------------------------------------------------------

public export
certifyDesignated : Trit -> Result
certifyDesignated t = case decDesignated t of
  Yes _ => Ok
  No _  => Error

export
certifyDesignatedSound : (t : Trit) -> certifyDesignated t = Ok -> Designated t
certifyDesignatedSound t prf with (decDesignated t)
  certifyDesignatedSound t prf  | Yes d = d
  certifyDesignatedSound t Refl | No _ impossible

--------------------------------------------------------------------------------
-- Positive controls
--------------------------------------------------------------------------------

export
tDesignated : Designated T
tDesignated = DesT

export
andTTDesignated : Designated (and3 T T)
andTTDesignated = andDesignated DesT DesT

export
certifyTAccepts : certifyDesignated T = Ok
certifyTAccepts = Refl

--------------------------------------------------------------------------------
-- Negative controls — the laws are non-vacuous
--------------------------------------------------------------------------------

||| Negation is genuinely not the identity (so `doubleNeg` is non-trivial).
export
negationNotIdentity : Not (not3 T = T)
negationNotIdentity Refl impossible

||| `U` is not designated — Kleene "unknown" is not classical truth.
export
uNotDesignated : Not (Designated U)
uNotDesignated = absurd

||| `F` is not designated.
export
fNotDesignated : Not (Designated F)
fNotDesignated = absurd
