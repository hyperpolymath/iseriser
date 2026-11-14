-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Bqniser (Idris2 ABI Layer 2).
|||
||| Bqniser's headline is "detect array patterns and rewrite as optimised BQN
||| primitives". The correctness obligation for any such rewrite is that it is
||| *semantics-preserving*. This module proves a concrete, real BQN rewrite:
|||
|||   +´⌽𝕩   ==>   +´𝕩          (sum-of-reverse  ==>  sum)
|||
||| i.e. detecting a fold-sum applied to a reversed array and dropping the
||| reverse, because summation is invariant under reversal. The equivalence
||| `sumRev : bsum (brev xs) = bsum xs` is proven by induction; a certifier is
||| proven sound against it; and a negative control machine-checks that the
||| rewrite is non-trivial (reversal genuinely changes the array).
|||
||| (`bsum`/`brev` are named to avoid clashing with Prelude `sum`.)

module Bqniser.ABI.Semantics

import Bqniser.ABI.Types
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- A minimal array model with the two primitives the rewrite touches
--------------------------------------------------------------------------------

||| Fold-sum (`+´`).
public export
bsum : List Nat -> Nat
bsum []        = 0
bsum (x :: xs) = x + bsum xs

||| Reverse (`⌽`), defined directly so it is convenient to induct over.
public export
brev : List Nat -> List Nat
brev []        = []
brev (x :: xs) = brev xs ++ [x]

--------------------------------------------------------------------------------
-- Semantics-preservation of the rewrite
--------------------------------------------------------------------------------

||| Sum distributes over a snoc: bsum (xs ++ [y]) = bsum xs + y.
export
sumSnoc : (xs : List Nat) -> (y : Nat) -> bsum (xs ++ [y]) = bsum xs + y
sumSnoc []        y = plusZeroRightNeutral y
sumSnoc (x :: xs) y =
  trans (cong (x +) (sumSnoc xs y))
        (plusAssociative x (bsum xs) y)

||| The headline equivalence: summing a reversed array equals summing it, so the
||| `+´⌽ ==> +´` rewrite preserves semantics for all inputs.
export
sumRev : (xs : List Nat) -> bsum (brev xs) = bsum xs
sumRev []        = Refl
sumRev (x :: xs) =
  trans (sumSnoc (brev xs) x)
        (trans (cong (+ x) (sumRev xs))
               (plusCommutative (bsum xs) x))

--------------------------------------------------------------------------------
-- Certifier into the ABI Result, proven sound against the equivalence
--------------------------------------------------------------------------------

||| The rewrite is unconditionally valid, so the certifier always reports `Ok`.
public export
certifyRewrite : List Nat -> Result
certifyRewrite _ = Ok

||| Soundness: whenever the certifier reports `Ok`, the rewrite genuinely
||| preserves the computed result for that input.
export
certifyRewriteSound : (xs : List Nat) -> certifyRewrite xs = Ok -> bsum (brev xs) = bsum xs
certifyRewriteSound xs _ = sumRev xs

--------------------------------------------------------------------------------
-- Positive control
--------------------------------------------------------------------------------

export
rewritePreservesConcrete : bsum (brev [1, 2, 3]) = bsum [1, 2, 3]
rewritePreservesConcrete = sumRev [1, 2, 3]

--------------------------------------------------------------------------------
-- Negative control: the rewrite is non-trivial — reversal really changes the
-- array, so the equivalence is a genuine theorem, not reverse = id.
--------------------------------------------------------------------------------

export
revChangesOrder : Not (brev [1, 2] = [1, 2])
revChangesOrder Refl impossible
