-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Monotonicity invariants for Eclexiaiser (Idris2 ABI Layer 3).
|||
||| Layer 2 (`Eclexiaiser.ABI.Semantics`) proved *conservation*: cost is exactly
||| additive over composition (an equality). This module proves the deeper,
||| distinct *ordering* structure of cost accounting — monotonicity and the
||| downward-closure of budget compliance — reusing the Layer-2 model
||| (`Ledger`, `totalCost`, `WithinBudget`) without redefining any datatype:
|||
|||   1. `costMonotoneAppend` — appending a step never DECREASES total cost:
|||        LTE (totalCost xs) (totalCost (xs ++ [c])).
|||      This is an inequality, not the Layer-2 equality, and is the core
|||      monotonicity guarantee: instrumentation can only ever add cost.
|||
|||   2. `prefixMonotone` — any prefix is no more costly than the whole ledger:
|||        LTE (totalCost xs) (totalCost (xs ++ ys)).
|||      The general monotonicity law of which (1) is the singleton case.
|||
|||   3. `budgetWeakening` — budget compliance is downward-closed in the budget:
|||        WithinBudget b l -> LTE b b2 -> WithinBudget b2 l.
|||      A larger budget can never reject a ledger a smaller one accepted; this
|||      uses LTE transitivity over the Layer-2 `WithinBudget` proposition.
|||
|||   4. `decBudgetLE` — a sound+complete decision for the budget-ordering side
|||      condition (LTE on Nat), so the weakening lemma is mechanically usable.
|||
||| Controls: a POSITIVE inhabited witness (monotone step on a concrete ledger,
||| and a weakened budget witness), plus a NEGATIVE / non-vacuity control
||| (`appendStrictlyIncreasesNotEq`: a `Not` proof that a non-zero step makes the
||| totals differ, ruling out the vacuous "cost never changes" reading; and a
||| `Not (LTE ...)` showing weakening genuinely needs the ordering side condition).

module Eclexiaiser.ABI.Invariants

import Eclexiaiser.ABI.Types
import Eclexiaiser.ABI.Semantics
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- 1. Monotonicity: appending a step never decreases total cost
--------------------------------------------------------------------------------

||| The general monotonicity law: the cost of a prefix is no greater than the
||| cost of the whole. Proven by rewriting through Layer-2 conservation
||| (`additivity`) and then observing `n <= n + m`.
export
prefixMonotone : (xs, ys : Ledger) ->
                 LTE (totalCost xs) (totalCost (xs ++ ys))
prefixMonotone xs ys =
  rewrite additivity xs ys in
    lteAddRight (totalCost xs)

||| Appending a single step never decreases the total cost — the singleton
||| instance of `prefixMonotone`. Instrumentation can only add cost.
export
costMonotoneAppend : (xs : Ledger) -> (c : Nat) ->
                     LTE (totalCost xs) (totalCost (xs ++ [c]))
costMonotoneAppend xs c = prefixMonotone xs [c]

--------------------------------------------------------------------------------
-- 2. A sound+complete decision for the budget-ordering side condition
--------------------------------------------------------------------------------

||| Decide the budget-ordering side condition used by weakening.  `isLTE` from
||| Data.Nat is already sound+complete; we expose it under a domain name.
export
decBudgetLE : (b, b2 : Nat) -> Dec (LTE b b2)
decBudgetLE = isLTE

--------------------------------------------------------------------------------
-- 3. Downward-closure: a larger budget still admits a compliant ledger
--------------------------------------------------------------------------------

||| Budget compliance is downward-closed in the budget: if a ledger fits within
||| `b`, and `b <= b2`, then it fits within `b2`.  This is *not* the Layer-2
||| conservation law; it is a structural property of `WithinBudget` proven by
||| transitivity of LTE.
||| Concrete transitivity of LTE, hand-proven so it does not depend on the
||| `Transitive` interface method (whose implicits are runtime-relevant and so
||| clash with the erased budget/ledger arguments here).
lteTrans : {0 x, y, z : Nat} -> LTE x y -> LTE y z -> LTE x z
lteTrans LTEZero       _            = LTEZero
lteTrans (LTESucc p)   (LTESucc q)  = LTESucc (lteTrans p q)

export
budgetWeakening : {0 b : Nat} -> {0 b2 : Nat} -> {0 l : Ledger} ->
                  WithinBudget b l -> LTE b b2 -> WithinBudget b2 l
budgetWeakening (Within prf) ble = Within (lteTrans prf ble)

--------------------------------------------------------------------------------
-- 4. Positive controls
--------------------------------------------------------------------------------

||| Concrete monotone step: cost of [3,4] (= 7) is <= cost of [3,4,5] (= 12).
export
monotoneStepEx : LTE (totalCost [3, 4]) (totalCost ([3, 4] ++ [5]))
monotoneStepEx = costMonotoneAppend [3, 4] 5

||| Concrete prefix monotonicity on a split.
export
prefixMonotoneEx : LTE (totalCost [3, 4]) (totalCost ([3, 4] ++ [5, 6]))
prefixMonotoneEx = prefixMonotone [3, 4] [5, 6]

||| Weakening a budget keeps an accepted ledger accepted: `withinEx` is within
||| 10; since 10 <= 20, it is within 20.  The side condition `LTE 10 20` is
||| obtained from the sound+complete decision procedure (no hand-built proof).
export
weakenedWitness : WithinBudget 20 [3, 4]
weakenedWitness =
  case decBudgetLE 10 20 of
    Yes le => budgetWeakening withinEx le
    No  contra => absurd (contra (lteAddRight 10))

--------------------------------------------------------------------------------
-- 5. Negative / non-vacuity controls
--------------------------------------------------------------------------------

||| Non-vacuity of monotonicity: with a *non-zero* step the totals genuinely
||| DIFFER, so `costMonotoneAppend` is a real strict-increase witness and not the
||| vacuous "cost is unchanged".  Both sides reduce to constructor-headed Nats
||| (12 vs 7), so the equality is refuted by a top-level `impossible` clause.
export
appendStrictlyIncreasesNotEq :
  Not (totalCost ([3, 4] ++ [5]) = totalCost [3, 4])
appendStrictlyIncreasesNotEq Refl impossible

||| Non-vacuity of the weakening side condition: weakening genuinely *requires*
||| `b <= b2`.  Here the ordering it would need (20 <= 10) does NOT hold, so the
||| lemma could not have been applied in this direction.  Machine-checked `Not`.
export
weakeningNeedsOrder : Not (LTE 20 10)
weakeningNeedsOrder le = absurd (notLTE le)
  where
    notLTE : LTE 20 10 -> Void
    notLTE (LTESucc (LTESucc (LTESucc (LTESucc (LTESucc (LTESucc (LTESucc (LTESucc (LTESucc (LTESucc x))))))))))
      = absurd x
