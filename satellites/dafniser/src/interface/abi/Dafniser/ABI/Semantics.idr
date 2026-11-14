-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Dafniser (Idris2 ABI Layer 2).
|||
||| Dafniser's headline: "Generate correct-by-construction code using Dafny".
||| The essence of correct-by-construction is that a *generated* function
||| provably satisfies its declared *postcondition* whenever its
||| *precondition* holds.  This module models that contract for a concrete,
||| representative generated function — integer `max` over `Nat` — and proves,
||| in the Idris2 type system, that the generated body meets the postcondition
||| Dafny would have to discharge to Z3:
|||
|||   ensures result >= a && result >= b && (result == a || result == b)
|||
||| The proof is genuine: `MaxPost` is a real proposition built from
||| propositional `LTE` and a disjunction, the postcondition for the bad case
||| (a result smaller than an input, or a result equal to neither) is
||| *uninhabited*, and we provide a sound certifier together with positive and
||| negative machine-checked controls.

module Dafniser.ABI.Semantics

import Dafniser.ABI.Types
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A faithful model of a Dafny spec: precondition + postcondition + body
--------------------------------------------------------------------------------

||| The postcondition of the generated `max` function, as a real proposition.
||| `MaxPost a b r` holds exactly when `r` is a correct maximum of `a` and `b`:
||| it dominates both inputs and is equal to one of them.  There is NO way to
||| build a `MaxPost` for an incorrect result — the type itself is the contract.
public export
data MaxPost : (a, b, r : Nat) -> Type where
  ||| `r` came from the left input: r = a, and a dominates b.
  FromLeft  : (geA : LTE b a) -> MaxPost a b a
  ||| `r` came from the right input: r = b, and b dominates a.
  FromRight : (geB : LTE a b) -> MaxPost a b b

||| The *generated* body of `max` (what Dafniser would emit as target code).
||| Correct-by-construction means: we do not merely assert it works — we return
||| the body together with a proof that it satisfies `MaxPost`.
public export
genMax : (a, b : Nat) -> (r : Nat ** MaxPost a b r)
genMax a b with (isLTE a b)
  genMax a b | Yes prf = (b ** FromRight prf)
  genMax a b | No contra = (a ** FromLeft (lteSuccLeft (notLTEImpliesGT contra)))

--------------------------------------------------------------------------------
-- The headline property: the generated body meets its postcondition
--------------------------------------------------------------------------------

||| `MaxPost` genuinely implies the three Dafny `ensures` conjuncts.
||| (a) the result dominates the left input.
public export
postDominatesLeft : {a, r : Nat} -> MaxPost a b r -> LTE a r
postDominatesLeft (FromLeft geA) = reflexive
postDominatesLeft (FromRight geB) = geB

||| (b) the result dominates the right input.
public export
postDominatesRight : {b, r : Nat} -> MaxPost a b r -> LTE b r
postDominatesRight (FromLeft geA) = geA
postDominatesRight (FromRight geB) = reflexive

||| (c) the result equals one of the two inputs.
public export
postIsOneInput : MaxPost a b r -> Either (r = a) (r = b)
postIsOneInput (FromLeft geA) = Left Refl
postIsOneInput (FromRight geB) = Right Refl

||| The headline theorem: for ALL inputs there EXISTS a generated result that
||| satisfies every clause of its postcondition simultaneously.  This is the
||| machine-checked correct-by-construction guarantee for `max`.
public export
genMaxCorrect : (a, b : Nat) ->
                (r : Nat ** (LTE a r, LTE b r, Either (r = a) (r = b)))
genMaxCorrect a b =
  let (r ** pf) = genMax a b in
  (r ** (postDominatesLeft pf, postDominatesRight pf, postIsOneInput pf))

--------------------------------------------------------------------------------
-- Soundness: the bad case has no inhabitant
--------------------------------------------------------------------------------

||| No natural number is strictly below itself (S r <= r is impossible).
notSuccLTE : {r : Nat} -> Not (LTE (S r) r)
notSuccLTE {r = 0}   le = absurd le
notSuccLTE {r = S k} (LTESucc le) = notSuccLTE le

||| A result strictly below the left input can NEVER satisfy the postcondition.
||| This is the non-vacuity core: it refutes the "incorrect max" case.
public export
noUndershootLeft : {a, b, r : Nat} -> LT r a -> Not (MaxPost a b r)
noUndershootLeft ltRA post =
  -- LTE a r (from the postcondition) together with r < a (i.e. S r <= a)
  -- gives S r <= r, which is absurd.
  let leAR  = postDominatesLeft post                -- a <= r
      srLer = transitive ltRA leAR                  -- S r <= r
  in notSuccLTE srLer

--------------------------------------------------------------------------------
-- Sound certifier over the ABI's VerificationResult type
--------------------------------------------------------------------------------

||| Generic refutation: if `r` equals neither input then no postcondition holds.
notNeither : Not (r = a) -> Not (r = b) -> Not (MaxPost a b r)
notNeither na nb (FromLeft geA) = na Refl
notNeither na nb (FromRight geB) = nb Refl

||| Every postcondition proof exposes which input the result came from,
||| as a propositional equality.  Used to discharge the awkward branch where
||| `r = a` but the proof claims `FromRight` (forcing `a = b`).
maxPostInput : MaxPost a b r -> Either (r = a) (r = b)
maxPostInput (FromLeft geA)  = Left Refl
maxPostInput (FromRight geB) = Right Refl

||| Decide the postcondition for concrete inputs, returning a real proof.
||| Strategy: a valid result must equal one of the inputs, and that input must
||| dominate the other.  We test `r = a` (needs b <= a) then `r = b`
||| (needs a <= b); anything else is refuted by `notNeither`.
public export
decMaxPost : (a, b, r : Nat) -> Dec (MaxPost a b r)
decMaxPost a b r with (decEq r a)
  decMaxPost a b a | Yes Refl with (isLTE b a)
    decMaxPost a b a | Yes Refl | Yes geA = Yes (FromLeft geA)
    decMaxPost a b a | Yes Refl | No nGeA with (decEq a b)
      -- r = a = b: FromRight reflexive is a valid witness.
      decMaxPost a a a | Yes Refl | No nGeA | Yes Refl = Yes (FromRight reflexive)
      -- r = a, a /= b, and not (b <= a): genuinely no witness.
      decMaxPost a b a | Yes Refl | No nGeA | No nEqAB = No notLeftBad
        where
          notLeftBad : Not (MaxPost a b a)
          notLeftBad p = case p of
            FromLeft geA  => nGeA geA
            FromRight geB => nGeA geB
  decMaxPost a b r | No nEqA with (decEq r b)
    decMaxPost a b b | No nEqA | Yes Refl with (isLTE a b)
      decMaxPost a b b | No nEqA | Yes Refl | Yes geB = Yes (FromRight geB)
      decMaxPost a b b | No nEqA | Yes Refl | No nGeB = No notRightBad
        where
          notRightBad : Not (MaxPost a b b)
          notRightBad p = case p of
            FromRight geB => nGeB geB
            FromLeft geA  => nGeB geA
    decMaxPost a b r | No nEqA | No nEqB = No (notNeither nEqA nEqB)

||| Certify a generated `max` instance against its postcondition, producing the
||| ABI's `VerificationResult`.  `Verified` is emitted only when a real
||| `MaxPost` proof exists; otherwise a `Counterexample` is reported.
public export
certifyMax : (a, b, r : Nat) -> VerificationResult
certifyMax a b r = case decMaxPost a b r of
  Yes _ => Verified "max" 0
  No  _ => Counterexample "max" "ensures result>=a && result>=b && (result==a||result==b)" "incorrect result"

||| Soundness of the certifier: a `Verified` verdict guarantees the
||| postcondition genuinely holds.
public export
certifyMaxSound : (a, b, r : Nat) -> certifyMax a b r = Verified "max" 0 -> MaxPost a b r
certifyMaxSound a b r prf with (decMaxPost a b r)
  certifyMaxSound a b r prf | Yes post = post
  certifyMaxSound a b r prf | No _ = absurd (counterNotVerified prf)
    where
      counterNotVerified : Counterexample "max" _ _ = Verified "max" 0 -> Void
      counterNotVerified Refl impossible

--------------------------------------------------------------------------------
-- Positive control: an explicit inhabited witness
--------------------------------------------------------------------------------

||| genMax 7 3 produces 7, and 7 is a correct max of 7 and 3.
public export
maxPositive : MaxPost 7 3 7
maxPositive = FromLeft %search

||| The generated body agrees with the witness on concrete inputs.
public export
genMaxConcrete : fst (genMax 7 3) = 7
genMaxConcrete = Refl

||| The certifier accepts the correct instance.
public export
certifyAccepts : certifyMax 7 3 7 = Verified "max" 0
certifyAccepts = Refl

--------------------------------------------------------------------------------
-- Negative control: the bad case is machine-checked impossible
--------------------------------------------------------------------------------

||| There is NO correct-max proof for result 2 on inputs 7 and 3 (2 undershoots
||| both, and equals neither).  This is the negative control: the contract
||| rejects the incorrect generated result.
public export
maxNegative : Not (MaxPost 7 3 2)
maxNegative (FromLeft geA) impossible
maxNegative (FromRight geB) impossible

||| The certifier rejects the incorrect instance.
public export
certifyRejects : certifyMax 7 3 2 = Counterexample "max" "ensures result>=a && result>=b && (result==a||result==b)" "incorrect result"
certifyRejects = Refl
