-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Deeper algebraic invariants for Betlangiser (Idris2 ABI Layer 3).
|||
||| Layer 2 (`Betlangiser.ABI.Semantics`) proved *unary/local* laws of the
||| Kleene substrate `Trit = T | U | F`: that negation is an involution and
||| that De Morgan relates `and3`/`or3`. This module proves a genuinely
||| DEEPER and DISTINCT structural fact: that `(Trit, and3)` is a commutative,
||| associative, idempotent semilattice whose order is exactly the Kleene
||| information order `F <= U <= T`, and that `and3` is the *meet* (greatest
||| lower bound) for that order. None of these restate the Layer-2 theorems.
|||
||| Contents:
|||   1. `and3Comm`      — commutativity of `and3` (9-case analysis);
|||   2. `and3Assoc`     — associativity of `and3` (full 27-case analysis);
|||   3. `and3Idem`      — idempotence (`and3 x x = x`);
|||   4. `Leq3`          — the Kleene order as an inductive relation, with a
|||                        sound+complete decision procedure `decLeq3`;
|||   5. `and3IsMeet`    — `and3 x y` is a lower bound of both `x` and `y`,
|||                        and the greatest such (meet / GLB);
|||   6. positive controls (inhabited witnesses) AND a negative / non-vacuity
|||      control (`Not (...)`) machine-checked.

module Betlangiser.ABI.Invariants

import Betlangiser.ABI.Semantics

%default total

--------------------------------------------------------------------------------
-- 1. Commutativity of and3 (distinct from Layer-2 doubleNeg / De Morgan)
--------------------------------------------------------------------------------

||| `and3` is commutative.
export
and3Comm : (x, y : Trit) -> and3 x y = and3 y x
and3Comm T T = Refl
and3Comm T U = Refl
and3Comm T F = Refl
and3Comm U T = Refl
and3Comm U U = Refl
and3Comm U F = Refl
and3Comm F T = Refl
and3Comm F U = Refl
and3Comm F F = Refl

--------------------------------------------------------------------------------
-- 2. Associativity of and3 (the deep law — full 27-case analysis)
--------------------------------------------------------------------------------

||| `and3` is associative. Proven by exhaustive case analysis on all three
||| arguments; every case reduces definitionally to `Refl`.
export
and3Assoc : (x, y, z : Trit) -> and3 (and3 x y) z = and3 x (and3 y z)
and3Assoc T T T = Refl
and3Assoc T T U = Refl
and3Assoc T T F = Refl
and3Assoc T U T = Refl
and3Assoc T U U = Refl
and3Assoc T U F = Refl
and3Assoc T F T = Refl
and3Assoc T F U = Refl
and3Assoc T F F = Refl
and3Assoc U T T = Refl
and3Assoc U T U = Refl
and3Assoc U T F = Refl
and3Assoc U U T = Refl
and3Assoc U U U = Refl
and3Assoc U U F = Refl
and3Assoc U F T = Refl
and3Assoc U F U = Refl
and3Assoc U F F = Refl
and3Assoc F T T = Refl
and3Assoc F T U = Refl
and3Assoc F T F = Refl
and3Assoc F U T = Refl
and3Assoc F U U = Refl
and3Assoc F U F = Refl
and3Assoc F F T = Refl
and3Assoc F F U = Refl
and3Assoc F F F = Refl

--------------------------------------------------------------------------------
-- 3. Idempotence — completes the semilattice laws
--------------------------------------------------------------------------------

||| `and3` is idempotent: `and3 x x = x`.
export
and3Idem : (x : Trit) -> and3 x x = x
and3Idem T = Refl
and3Idem U = Refl
and3Idem F = Refl

--------------------------------------------------------------------------------
-- 4. The Kleene information order, decided soundly and completely
--------------------------------------------------------------------------------

||| The Kleene/information order on `Trit`: `F <= U <= T`. Encoded as an
||| inductive relation so that proofs are first-class. Reflexivity is built in
||| per-constructor; the strict steps `LFU`, `LUT`, `LFT` give the chain.
public export
data Leq3 : Trit -> Trit -> Type where
  LFF : Leq3 F F
  LUU : Leq3 U U
  LTT : Leq3 T T
  LFU : Leq3 F U
  LUT : Leq3 U T
  LFT : Leq3 F T

||| Reflexivity of the order.
export
leq3Refl : (x : Trit) -> Leq3 x x
leq3Refl T = LTT
leq3Refl U = LUU
leq3Refl F = LFF

||| Transitivity of the order (full case analysis on the witnesses).
export
leq3Trans : Leq3 x y -> Leq3 y z -> Leq3 x z
leq3Trans LFF p = p
leq3Trans LUU p = p
leq3Trans LTT p = p
leq3Trans LFU LUU = LFU
leq3Trans LFU LUT = LFT
leq3Trans LUT LTT = LUT
leq3Trans LFT LTT = LFT

-- The genuinely impossible compositions are ruled out structurally: there is
-- no `Leq3` constructor with U or T on the left that lands below it, so the
-- clauses above are exhaustive for total checking.

-- Refutations needed for a complete decision procedure (top-level `impossible`
-- clauses, per the 0.7.0 idiom — NOT nested case-impossible).
notLeqUF : Leq3 U F -> Void
notLeqUF LFF impossible
notLeqUF LUU impossible
notLeqUF LTT impossible
notLeqUF LFU impossible
notLeqUF LUT impossible
notLeqUF LFT impossible

notLeqTF : Leq3 T F -> Void
notLeqTF LFF impossible
notLeqTF LUU impossible
notLeqTF LTT impossible
notLeqTF LFU impossible
notLeqTF LUT impossible
notLeqTF LFT impossible

notLeqTU : Leq3 T U -> Void
notLeqTU LFF impossible
notLeqTU LUU impossible
notLeqTU LTT impossible
notLeqTU LFU impossible
notLeqTU LUT impossible
notLeqTU LFT impossible

||| Sound + complete decision of the Kleene order. `Yes` returns a real proof;
||| `No` returns a real refutation — there is no `believe_me`/`postulate`.
public export
decLeq3 : (x, y : Trit) -> Dec (Leq3 x y)
decLeq3 F F = Yes LFF
decLeq3 F U = Yes LFU
decLeq3 F T = Yes LFT
decLeq3 U F = No notLeqUF
decLeq3 U U = Yes LUU
decLeq3 U T = Yes LUT
decLeq3 T F = No notLeqTF
decLeq3 T U = No notLeqTU
decLeq3 T T = Yes LTT

--------------------------------------------------------------------------------
-- 5. and3 is the MEET (greatest lower bound) for Leq3
--------------------------------------------------------------------------------

||| Lower-bound part: `and3 x y` is below `x`.
export
and3LowerL : (x, y : Trit) -> Leq3 (and3 x y) x
and3LowerL T T = LTT
and3LowerL T U = LUT
and3LowerL T F = LFT
and3LowerL U T = LUU
and3LowerL U U = LUU
and3LowerL U F = LFU
and3LowerL F T = LFF
and3LowerL F U = LFF
and3LowerL F F = LFF

||| Lower-bound part: `and3 x y` is below `y`.
export
and3LowerR : (x, y : Trit) -> Leq3 (and3 x y) y
and3LowerR T T = LTT
and3LowerR T U = LUU
and3LowerR T F = LFF
and3LowerR U T = LUT
and3LowerR U U = LUU
and3LowerR U F = LFF
and3LowerR F T = LFT
and3LowerR F U = LFU
and3LowerR F F = LFF

||| Greatest part: any common lower bound `z` of `x` and `y` is below the meet
||| `and3 x y`. Together with `and3LowerL`/`and3LowerR` this proves `and3` is
||| the greatest lower bound (meet) for the Kleene order.
export
and3Greatest : (x, y, z : Trit) ->
               Leq3 z x -> Leq3 z y -> Leq3 z (and3 x y)
-- For each (x,y), `and3 x y` is fixed and the goal is `Leq3 z (and3 x y)`.
-- Where z cannot be a common lower bound of x and y, one of the supplied
-- witnesses is uninhabited and we refute it.
and3Greatest T T z zx zy = zx            -- and3 T T = T, goal Leq3 z T = zx
and3Greatest T U z zx zy = zy            -- and3 T U = U, goal Leq3 z U = zy
and3Greatest T F z zx zy = zy            -- and3 T F = F, goal Leq3 z F = zy
and3Greatest U T z zx zy = zx            -- and3 U T = U, goal Leq3 z U = zx
and3Greatest U U z zx zy = zx            -- and3 U U = U, goal Leq3 z U = zx
and3Greatest U F z zx zy = zy            -- and3 U F = F, goal Leq3 z F = zy
and3Greatest F T z zx zy = zx            -- and3 F T = F, goal Leq3 z F = zx
and3Greatest F U z zx zy = zx            -- and3 F U = F, goal Leq3 z F = zx
and3Greatest F F z zx zy = zx            -- and3 F F = F, goal Leq3 z F = zx

--------------------------------------------------------------------------------
-- 6. Positive controls (inhabited witnesses / concrete instances)
--------------------------------------------------------------------------------

||| Concrete instance of associativity at a mixed point.
export
assocUTF : and3 (and3 U T) F = and3 U (and3 T F)
assocUTF = and3Assoc U T F

||| Concrete order fact: `U` sits between `F` and `T`.
export
fLeqU : Leq3 F U
fLeqU = LFU

||| The decision procedure accepts a true ordering.
export
decAcceptsFU : (Leq3 F U)
decAcceptsFU = case decLeq3 F U of
  Yes p => p
  No contra => absurd (contra LFU)

||| Meet of `T` and `U` is `U`, and it is genuinely below both — a witnessed
||| greatest-lower-bound instance.
export
meetTU_belowU : Leq3 (and3 T U) U
meetTU_belowU = and3LowerR T U

--------------------------------------------------------------------------------
-- 7. Negative / non-vacuity controls (machine-checked refutations)
--------------------------------------------------------------------------------

||| The order is genuinely a *partial* order, not total agreement: `T` is NOT
||| below `U`. If this were provable, `decLeq3` would be unsound.
export
tNotLeqU : Not (Leq3 T U)
tNotLeqU = notLeqTU

||| `and3` is genuinely not constant: associativity is non-vacuous because the
||| values it relates actually differ from a fixed value. Here `and3 U U = U`,
||| which is NOT `T`, so the semilattice is not collapsed to the top.
export
andUUNotTop : Not (and3 U U = T)
andUUNotTop Refl impossible

||| The meet genuinely loses information: `and3 T F = F`, which is strictly
||| below `T`; it is NOT the case that `T` is below the meet `and3 T F`.
export
topNotBelowMeetTF : Not (Leq3 T (and3 T F))
topNotBelowMeetTF = notLeqTF
