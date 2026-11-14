-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Eclexiaiser (Idris2 ABI Layer 2).
|||
||| Eclexiaiser's headline is "add energy/carbon/resource-cost awareness". The
||| foundational guarantee of any cost-accounting layer is that accounting
||| *conserves* cost — the cost of a composite computation is exactly the sum of
||| its parts, so the accounting can neither lose nor invent cost. This module
||| proves:
|||
|||   1. `additivity` — totalCost (xs ++ ys) = totalCost xs + totalCost ys, by
|||      induction (the conservation law);
|||   2. `WithinBudget` — budget compliance as a decidable proposition with a
|||      sound+complete `Dec`, a certifier proven sound, and positive + negative
|||      controls (an over-budget ledger is provably rejected).

module Eclexiaiser.ABI.Semantics

import Eclexiaiser.ABI.Types
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A cost ledger and its total
--------------------------------------------------------------------------------

||| A ledger of per-step resource costs.
public export
Ledger : Type
Ledger = List Nat

public export
totalCost : Ledger -> Nat
totalCost []        = 0
totalCost (c :: cs) = c + totalCost cs

--------------------------------------------------------------------------------
-- Conservation: cost is additive over composition
--------------------------------------------------------------------------------

||| The conservation law: the cost of concatenated work equals the sum of the
||| costs — accounting neither loses nor invents resource cost.
export
additivity : (xs, ys : Ledger) -> totalCost (xs ++ ys) = totalCost xs + totalCost ys
additivity []        ys = Refl
additivity (x :: xs) ys =
  trans (cong (x +) (additivity xs ys))
        (plusAssociative x (totalCost xs) (totalCost ys))

--------------------------------------------------------------------------------
-- Budget compliance as a decidable proposition
--------------------------------------------------------------------------------

public export
data WithinBudget : (budget : Nat) -> Ledger -> Type where
  Within : {0 b : Nat} -> {0 l : Ledger} -> LTE (totalCost l) b -> WithinBudget b l

public export
decWithinBudget : (b : Nat) -> (l : Ledger) -> Dec (WithinBudget b l)
decWithinBudget b l = case isLTE (totalCost l) b of
  Yes prf => Yes (Within prf)
  No  no  => No (\(Within p) => no p)

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound
--------------------------------------------------------------------------------

public export
certifyBudget : Nat -> Ledger -> Result
certifyBudget b l = case decWithinBudget b l of
  Yes _ => Ok
  No  _ => Error

export
certifyBudgetSound : (b : Nat) -> (l : Ledger) ->
  certifyBudget b l = Ok -> WithinBudget b l
certifyBudgetSound b l prf with (decWithinBudget b l)
  certifyBudgetSound b l prf  | Yes w = w
  certifyBudgetSound b l Refl | No _ impossible

--------------------------------------------------------------------------------
-- Positive controls
--------------------------------------------------------------------------------

||| Conservation holds on a concrete split.
export
splitConserves : totalCost ([3, 4] ++ [5]) = totalCost [3, 4] + totalCost [5]
splitConserves = additivity [3, 4] [5]

export
certifyWithinAccepts : certifyBudget 10 [3, 4] = Ok
certifyWithinAccepts = Refl

||| A genuine `WithinBudget` witness, derived from the sound certifier.
export
withinEx : WithinBudget 10 [3, 4]
withinEx = certifyBudgetSound 10 [3, 4] certifyWithinAccepts

--------------------------------------------------------------------------------
-- Negative control: an over-budget ledger is rejected (non-vacuity)
--------------------------------------------------------------------------------

export
certifyOverRejects : certifyBudget 5 [3, 4] = Error
certifyOverRejects = Refl
