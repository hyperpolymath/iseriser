-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Deeper algebraic invariants for Dafniser (Idris2 ABI Layer 3).
|||
||| Layer 2 (`Dafniser.ABI.Semantics`) proves a single generated function —
||| `max` over `Nat` — meets its declared postcondition.  That is the
||| correct-by-construction guarantee for ONE function in isolation.
|||
||| Layer 3 goes deeper.  Correct-by-construction code generation is only
||| trustworthy if the generated operators obey the *algebraic laws* a human
||| would expect of them, and if *families* of generated functions relate to
||| one another correctly.  This module establishes three such properties over
||| the SAME model (`MaxPost` / `genMax` from `Semantics`, reused unchanged):
|||
|||   (1) COMMUTATIVITY of the max contract — a relational algebraic law:
|||       `MaxPost a b r  <->  MaxPost b a r`.  The contract does not depend on
|||       argument order.  This is NOT the Layer-2 theorem (which is about a
|||       single fixed argument order); it is a structural symmetry of the spec.
|||
|||   (2) A DUAL generated function — `min` — built correct-by-construction in
|||       exactly the Layer-2 style (`MinPost` / `genMin`), proven to meet its
|||       own postcondition.  A second, distinct checker.
|||
|||   (3) A min/max DUALITY theorem tying the two operators together:
|||       `max a b + min a b = a + b`.  This is the deepest result here — it is
|||       a property of the *pair* of generated functions, provable only because
|||       both meet their contracts.  It is the kind of cross-function lemma Z3
|||       would have to discharge for a Dafny program that uses both.
|||
||| The proofs are genuine: every proposition is built from propositional `LTE`
||| and equalities, the bad cases are uninhabited, there is a sound + complete
||| `Dec` for the new contract, and both a positive (inhabited witness) and a
||| negative (`Not (...)`) control are machine-checked.

module Dafniser.ABI.Invariants

import Dafniser.ABI.Types
import Dafniser.ABI.Semantics
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- (1) Commutativity of the max contract  (relational algebraic law)
--------------------------------------------------------------------------------

||| The max postcondition is symmetric in its two inputs: a correct maximum of
||| `a` and `b` is also a correct maximum of `b` and `a`.  This is a genuine
||| algebraic law about the *contract*, distinct from the Layer-2 claim that a
||| particular generated body satisfies the contract.
public export
maxPostComm : MaxPost a b r -> MaxPost b a r
maxPostComm (FromLeft geA)  = FromRight geA   -- r = a; a dominates b  ==>  for (b,a), r = a is the right input
maxPostComm (FromRight geB) = FromLeft geB    -- r = b; b dominates a  ==>  for (b,a), r = b is the left input

||| Commutativity is an involution: applying it twice is the identity.
||| This rules out a vacuous `maxPostComm` that throws information away.
public export
maxPostCommInvolutive : (p : MaxPost a b r) -> maxPostComm (maxPostComm p) = p
maxPostCommInvolutive (FromLeft geA)  = Refl
maxPostCommInvolutive (FromRight geB) = Refl

--------------------------------------------------------------------------------
-- (2) The DUAL generated function: min, correct-by-construction
--------------------------------------------------------------------------------

||| The postcondition of the generated `min` function, as a real proposition.
||| `MinPost a b r` holds exactly when `r` is a correct minimum of `a` and `b`:
||| it is dominated by both inputs and is equal to one of them.  As with
||| `MaxPost`, the type itself is the contract — no incorrect minimum inhabits it.
public export
data MinPost : (a, b, r : Nat) -> Type where
  ||| `r` came from the left input: r = a, and a is dominated by b.
  MinLeft  : (leA : LTE a b) -> MinPost a b a
  ||| `r` came from the right input: r = b, and b is dominated by a.
  MinRight : (leB : LTE b a) -> MinPost a b b

||| The *generated* body of `min`.  Correct-by-construction: returned together
||| with a proof it satisfies `MinPost`.
public export
genMin : (a, b : Nat) -> (r : Nat ** MinPost a b r)
genMin a b with (isLTE a b)
  genMin a b | Yes prf   = (a ** MinLeft prf)
  genMin a b | No contra = (b ** MinRight (lteSuccLeft (notLTEImpliesGT contra)))

||| `MinPost` implies the result is dominated by the left input.
public export
minBelowLeft : {a, r : Nat} -> MinPost a b r -> LTE r a
minBelowLeft (MinLeft leA)  = reflexive
minBelowLeft (MinRight leB) = leB

||| `MinPost` implies the result is dominated by the right input.
public export
minBelowRight : {b, r : Nat} -> MinPost a b r -> LTE r b
minBelowRight (MinLeft leA)  = leA
minBelowRight (MinRight leB) = reflexive

||| `MinPost` implies the result equals one of the inputs.
public export
minIsOneInput : MinPost a b r -> Either (r = a) (r = b)
minIsOneInput (MinLeft leA)  = Left Refl
minIsOneInput (MinRight leB) = Right Refl

||| Headline correctness for the dual: for ALL inputs there EXISTS a generated
||| result meeting every `min` postcondition clause simultaneously.
public export
genMinCorrect : (a, b : Nat) ->
                (r : Nat ** (LTE r a, LTE r b, Either (r = a) (r = b)))
genMinCorrect a b =
  let (r ** pf) = genMin a b in
  (r ** (minBelowLeft pf, minBelowRight pf, minIsOneInput pf))

--------------------------------------------------------------------------------
-- Soundness of the dual contract: the bad case has no inhabitant
--------------------------------------------------------------------------------

||| No natural number is strictly above itself (S r <= r is impossible).
||| (Stated locally so this module does not depend on a private Semantics name.)
notSuccLTE' : {r : Nat} -> Not (LTE (S r) r)
notSuccLTE' {r = 0}   le = absurd le
notSuccLTE' {r = S k} (LTESucc le) = notSuccLTE' le

||| A result strictly ABOVE the left input can NEVER satisfy `MinPost`.
||| The non-vacuity core for the dual contract: it refutes "incorrect min".
public export
noOvershootLeft : {a, r : Nat} -> LT a r -> Not (MinPost a b r)
noOvershootLeft ltAR post =
  -- r <= a (from the postcondition) together with a < r (i.e. S a <= r)
  -- gives S a <= a, which is absurd.
  let leRA  = minBelowLeft post          -- r <= a
      saLea = transitive ltAR leRA       -- S a <= a
  in notSuccLTE' saLea

--------------------------------------------------------------------------------
-- Sound + complete decision procedure for the dual contract
--------------------------------------------------------------------------------

||| If `r` equals neither input then no `min` postcondition holds.
notNeitherMin : {0 a, b, r : Nat} -> Not (r = a) -> Not (r = b) -> Not (MinPost a b r)
notNeitherMin na nb (MinLeft leA)  = na Refl
notNeitherMin na nb (MinRight leB) = nb Refl

||| Decide the `min` postcondition for concrete inputs, returning a real proof.
||| A valid result must equal one of the inputs, and the OTHER input must
||| dominate it; anything else is refuted.
public export
decMinPost : (a, b, r : Nat) -> Dec (MinPost a b r)
decMinPost a b r with (decEq r a)
  decMinPost a b a | Yes Refl with (isLTE a b)
    decMinPost a b a | Yes Refl | Yes leA = Yes (MinLeft leA)
    decMinPost a b a | Yes Refl | No nLeA with (decEq a b)
      -- r = a = b: MinRight reflexive is a valid witness.
      decMinPost a a a | Yes Refl | No nLeA | Yes Refl = Yes (MinRight reflexive)
      -- r = a, a /= b, and not (a <= b): genuinely no witness.
      decMinPost a b a | Yes Refl | No nLeA | No nEqAB = No notLeftBad
        where
          notLeftBad : Not (MinPost a b a)
          notLeftBad p = case p of
            MinLeft leA  => nLeA leA
            MinRight leB => nLeA leB
  decMinPost a b r | No nEqA with (decEq r b)
    decMinPost a b b | No nEqA | Yes Refl with (isLTE b a)
      decMinPost a b b | No nEqA | Yes Refl | Yes leB = Yes (MinRight leB)
      decMinPost a b b | No nEqA | Yes Refl | No nLeB = No notRightBad
        where
          notRightBad : Not (MinPost a b b)
          notRightBad p = case p of
            MinRight leB => nLeB leB
            MinLeft leA  => nLeB leA
    decMinPost a b r | No nEqA | No nEqB = No (notNeitherMin nEqA nEqB)

||| Certify a generated `min` instance against its postcondition, producing the
||| ABI's `VerificationResult`.  `Verified` only when a real `MinPost` exists.
public export
certifyMin : (a, b, r : Nat) -> VerificationResult
certifyMin a b r = case decMinPost a b r of
  Yes _ => Verified "min" 0
  No  _ => Counterexample "min" "ensures result<=a && result<=b && (result==a||result==b)" "incorrect result"

||| Soundness of the dual certifier: a `Verified` verdict guarantees the
||| postcondition genuinely holds.
public export
certifyMinSound : (a, b, r : Nat) -> certifyMin a b r = Verified "min" 0 -> MinPost a b r
certifyMinSound a b r prf with (decMinPost a b r)
  certifyMinSound a b r prf | Yes post = post
  certifyMinSound a b r prf | No _ = absurd (counterNotVerified prf)
    where
      counterNotVerified : Counterexample "min" _ _ = Verified "min" 0 -> Void
      counterNotVerified Refl impossible

--------------------------------------------------------------------------------
-- (3) The min/max DUALITY theorem: max a b + min a b = a + b
--------------------------------------------------------------------------------
--
-- This is the deepest property in the module.  It is a law about the PAIR of
-- generated functions, provable only because each meets its contract.  We prove
-- it RELATIONALLY: given any correct max-result rmax and any correct
-- min-result rmin for the same inputs, their sum equals a + b.  Then we obtain
-- the concrete corollary for the generated bodies genMax / genMin.

||| Relational duality: for the SAME inputs, any correct maximum and any correct
||| minimum sum to a + b.  Proof is by case analysis on which input each result
||| came from; the two "diagonal" cases use antisymmetry of LTE to collapse.
public export
maxMinSum : {a, b : Nat} ->
            MaxPost a b rmax -> MinPost a b rmin -> rmax + rmin = a + b
-- max = a (b <= a), min = b (b <= a):  a + b = a + b.
maxMinSum (FromLeft  geA) (MinRight leB) = Refl
-- max = b (a <= b), min = a (a <= b):  b + a = a + b.
maxMinSum (FromRight geB) (MinLeft  leA) = plusCommutative b a
-- max = a (b <= a), min = a (a <= b):  here a = b by antisymmetry, so a + a = a + b.
maxMinSum (FromLeft  geA) (MinLeft  leA) =
  rewrite antisymmetric leA geA in Refl
-- max = b (a <= b), min = b (b <= a):  here a = b by antisymmetry, so b + b = a + b.
maxMinSum (FromRight geB) (MinRight leB) =
  rewrite antisymmetric geB leB in Refl

||| Concrete duality corollary for the generated bodies: the Dafniser-emitted
||| `max` and `min` sum to a + b on every input.  This is the cross-function
||| obligation a Dafny program using both operators would need discharged.
||| Helper: the sum law lifted to the dependent-pair packaging, so it can be
||| applied directly to whatever `genMax` / `genMin` return without needing the
||| opaque `fst (genMax ...)` application to reduce.
dpairSum : {a, b : Nat} ->
           (p : (r : Nat ** MaxPost a b r)) ->
           (q : (s : Nat ** MinPost a b s)) ->
           fst p + fst q = a + b
dpairSum (rmax ** pmax) (rmin ** pmin) = maxMinSum pmax pmin

public export
genMaxMinSum : (a, b : Nat) -> fst (genMax a b) + fst (genMin a b) = a + b
genMaxMinSum a b = dpairSum (genMax a b) (genMin a b)

--------------------------------------------------------------------------------
-- Positive controls: explicit inhabited witnesses / concrete instances
--------------------------------------------------------------------------------

||| genMin 7 3 produces 3, and 3 is a correct min of 7 and 3.
public export
minPositive : MinPost 7 3 3
minPositive = MinRight %search

||| The generated min body agrees with the witness on concrete inputs.
public export
genMinConcrete : fst (genMin 7 3) = 3
genMinConcrete = Refl

||| The dual certifier accepts the correct instance.
public export
certifyMinAccepts : certifyMin 7 3 3 = Verified "min" 0
certifyMinAccepts = Refl

||| The commutativity law in action: a correct max of (7,3) gives a correct
||| max of (3,7) for the same result 7.
public export
commPositive : MaxPost 3 7 7
commPositive = maxPostComm maxPositive

||| Concrete duality check: max 7 3 + min 7 3 = 10 = 7 + 3.
public export
dualityConcrete : fst (genMax 7 3) + fst (genMin 7 3) = 10
dualityConcrete = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls: bad cases machine-checked impossible
--------------------------------------------------------------------------------

||| There is NO correct-min proof for result 7 on inputs 7 and 3 (7 overshoots
||| the right input 3, and the genuine minimum is 3).  Negative control for the
||| dual contract.
public export
minNegative : Not (MinPost 7 3 7)
minNegative (MinLeft leA) = absurd leA   -- would need LTE 7 3, which is uninhabited
-- MinRight would need 7 = 3 (r = b); that case does not unify, so it is absent.

||| The dual certifier rejects the incorrect instance.
public export
certifyMinRejects : certifyMin 7 3 7
                  = Counterexample "min" "ensures result<=a && result<=b && (result==a||result==b)" "incorrect result"
certifyMinRejects = Refl

||| Non-vacuity of the duality law: a WRONG pairing (the true max 7 with a wrong
||| "min" 7) cannot satisfy the duality sum, because that wrong min has no
||| `MinPost` proof at all.  We exhibit the refutation of its premise.
public export
dualityNonVacuous : Not (MinPost 7 3 7)
dualityNonVacuous = minNegative
