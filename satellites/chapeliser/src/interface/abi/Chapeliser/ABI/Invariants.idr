-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariant for Chapeliser's block partition: DIV/MOD COMPLETENESS.
|||
||| `Partition.idr` (Layer 2) proves the partition is a gapless, non-overlapping
||| *tiling* for all `n`, `k`, and reduces full completeness to one residual
||| arithmetic identity it explicitly leaves open:
|||
|||     sumNat (perItemCounts n k) = n      -- "the only div/mod obligation"
|||
||| This module discharges exactly that residual — the deeper, genuinely
||| different theorem. Where the Layer-2 proof was *structural* (contiguity needs
||| no reasoning about how `div`/`mod` evaluate), THIS proof is *arithmetic*: it
||| pins down the values produced by integer division of `n` by `k` and shows
||| the per-locale counts sum to exactly `n` — every one of the `n` items is
||| covered exactly once. It rests on the Euclidean division theorem
||| `n = (n mod k) + (n div k) * k` (contrib `Data.Nat.Division`) plus a
||| self-contained count of how many locale indices receive the +1 remainder
||| slot.
|||
||| Division note (Idris2 0.7.0): the Prelude `div`/`mod` on `Nat` go through the
||| `Integral` interface to `divNat`/`modNat`, which are `export partial` and so
||| do NOT reduce at the type level (idiom: "Nat div/mod do not reduce for
||| symbolic operands"). The reducing, `public export` primitives are
||| `divNatNZ`/`modNatNZ`, and `contrib`'s `DivisionTheorem` is stated over those.
||| We therefore phrase the block counts with `divNatNZ`/`modNatNZ` — the SAME
||| values the block partition uses (Prelude `div`/`mod` on a positive `Nat`
||| literally call them), just written in the form that both reduces and matches
||| the division theorem. `blockCounts n (S k')` is thus `perItemCounts n (S k')`
||| with the division spelled in its reducing primitive.
|||
||| Combined with Layer 2 this yields, for ALL n and k>0, a partition that is
||| complete (`sliceSum = n`) AND a perfect tiling — a fully proven even
||| distribution with no items lost or duplicated.

module Chapeliser.ABI.Invariants

import Chapeliser.ABI.Types
import Chapeliser.ABI.Partition
import Data.Vect
import Data.Nat
import Data.Nat.Division
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- The block partition's per-locale counts, in reducing (NZ) form
--------------------------------------------------------------------------------

||| The block partition's per-locale counts for `n` items over `S k'` locales,
||| using the `public export` division primitives so the type checker can reduce
||| through them. This is exactly `perItemCounts n (S k')` from `Partition.idr`
||| (which calls Prelude `div`/`mod` = `divNatNZ`/`modNatNZ` on the positive
||| divisor `S k'`), reusing Partition's own `countsFrom`.
public export
blockCounts : (n, k' : Nat) -> Vect (S k') Nat
blockCounts n k' =
  countsFrom 0 (divNatNZ n (S k') SIsNonZero) (modNatNZ n (S k') SIsNonZero) (S k')

--------------------------------------------------------------------------------
-- Tiny boolean comparison facts (the `<` inside countsFrom)
--------------------------------------------------------------------------------

||| Nothing is below zero.
ltZeroFalse : (idx : Nat) -> (idx < 0) = False
ltZeroFalse Z     = Refl
ltZeroFalse (S _) = Refl

||| `S a < S b` decides identically to `a < b` (the comparison steps S/S down).
ltSuccSucc : (a, b : Nat) -> (S a < S b) = (a < b)
ltSuccSucc _ _ = Refl

--------------------------------------------------------------------------------
-- Counting the remainder ("+1") slots
--------------------------------------------------------------------------------

||| `numBelow idx rem cnt` counts how many of the `cnt` consecutive locale
||| indices `idx, idx+1, ..., idx+cnt-1` are strictly below `rem` — i.e. how many
||| of those locales receive the extra remainder item. It mirrors EXACTLY the
||| `if localeIdx < remainder then 1 else 0` decision inside `countsFrom`, using
||| the same Prelude boolean `<`, so the sum lemma below reduces structurally.
public export
numBelow : (idx, rem, cnt : Nat) -> Nat
numBelow _   _   Z     = Z
numBelow idx rem (S c) = (if idx < rem then 1 else 0) + numBelow (S idx) rem c

||| (a + b) + (c + d) = (a + c) + (b + d) — the only shuffle the sum law needs.
rearrange : (a, b, c, d : Nat) -> (a + b) + (c + d) = (a + c) + (b + d)
rearrange a b c d =
  rewrite plusAssociative (a + b) c d in
  rewrite sym (plusAssociative a b c) in
  rewrite plusCommutative b c in
  rewrite plusAssociative a c b in
  rewrite sym (plusAssociative (a + c) b d) in
  Refl

||| Structural sum law: a `countsFrom` block contributes `base` per locale plus
||| one extra for each locale index below `rem`. No div/mod facts used here — it
||| is pure bookkeeping over the `if` in `countsFrom`.
sumCountsFrom : (idx, base, rem, cnt : Nat) ->
                sumNat (countsFrom idx base rem cnt) = base * cnt + numBelow idx rem cnt
sumCountsFrom idx base rem Z =
  rewrite multZeroRightZero base in Refl
sumCountsFrom idx base rem (S c) =
  rewrite sumCountsFrom (S idx) base rem c in
  rewrite multRightSuccPlus base c in
  rearrange base (if idx < rem then 1 else 0) (base * c) (numBelow (S idx) rem c)

--------------------------------------------------------------------------------
-- Evaluating the remainder count exactly
--------------------------------------------------------------------------------

||| If the threshold is zero, no index is below it: the window contributes no
||| extra items regardless of where it starts or how long it is.
numBelowRemZero : (idx, cnt : Nat) -> numBelow idx 0 cnt = 0
numBelowRemZero idx Z     = Refl
numBelowRemZero idx (S c) =
  rewrite ltZeroFalse idx in
  numBelowRemZero (S idx) c

||| Shifting both the index and the threshold up by one leaves the count
||| unchanged: `S idx < S rem` holds exactly when `idx < rem`.
numBelowShift : (idx, rem, cnt : Nat) ->
                numBelow (S idx) (S rem) cnt = numBelow idx rem cnt
numBelowShift idx rem Z     = Refl
numBelowShift idx rem (S c) =
  -- head: (if S idx < S rem ..) = (if idx < rem ..) by ltSuccSucc;
  -- tail: numBelow (S (S idx)) (S rem) c = numBelow (S idx) rem c by IH.
  -- Combine the two equalities additively with cong2 (+).
  cong2 (+)
    (cong (\b => if b then (the Nat 1) else 0) (ltSuccSucc idx rem))
    (numBelowShift (S idx) rem c)

||| EXACT remainder count over the full locale range `[0, cnt)`: when the
||| remainder `rem` does not exceed the number of locales `cnt`, exactly `rem`
||| locales (indices 0 .. rem-1) receive the extra item. This is the heart of
||| the arithmetic argument and is where `rem <= cnt` (i.e. `n mod k < k`) is
||| consumed.
numBelowFull : (rem, cnt : Nat) -> LTE rem cnt -> numBelow 0 rem cnt = rem
numBelowFull Z     cnt     _          = numBelowRemZero 0 cnt
numBelowFull (S r) (S c) (LTESucc le) =
  -- idx 0 < S r is True (0 < S r reduces to True), so head = 1; the tail is
  -- numBelow 1 (S r) c = numBelow 0 r c (numBelowShift), then IH gives r.
  rewrite numBelowShift 0 r c in
  cong S (numBelowFull r c le)

--------------------------------------------------------------------------------
-- The remainder is below the locale count (n mod k < k)
--------------------------------------------------------------------------------

||| `n mod (S k')` (in reducing NZ form) is strictly less than `S k'`, hence
||| `<= S k'`. Strict bound from contrib's `boundModNatNZ`, then weakened.
modLEk : (n, k' : Nat) -> LTE (modNatNZ n (S k') SIsNonZero) (S k')
modLEk n k' = lteSuccLeft (boundModNatNZ n (S k') SIsNonZero)

--------------------------------------------------------------------------------
-- MAIN LAYER-3 THEOREM
--------------------------------------------------------------------------------

||| DIV/MOD COMPLETENESS, the residual left open by `Partition.idr`:
||| for every item count `n` and every POSITIVE locale count `S k'`, the block
||| partition's per-locale counts sum to exactly `n`. No item is dropped or
||| double-assigned. Quantified over ALL n, k'.
|||
||| Proof: the counts sum to `base * k + (remainder count)` (`sumCountsFrom`);
||| the remainder count is exactly `n mod k` because `n mod k <= k`
||| (`numBelowFull` + `modLEk`); and `base * k + n mod k = n div k * k + n mod k
|||  = n` by the Euclidean division theorem.
export
blockCountsComplete : (n, k' : Nat) -> sumNat (blockCounts n k') = n
blockCountsComplete n k' =
  let base : Nat
      base = divNatNZ n (S k') SIsNonZero
      rem : Nat
      rem = modNatNZ n (S k') SIsNonZero
      -- 1. structural sum law
      step1 : sumNat (blockCounts n k') = base * (S k') + numBelow 0 rem (S k')
      step1 = sumCountsFrom 0 base rem (S k')
      -- 2. the remainder count collapses to rem, using n mod k <= k
      step2 : numBelow 0 rem (S k') = rem
      step2 = numBelowFull rem (S k') (modLEk n k')
      -- 3. Euclidean division theorem: n = rem + base * (S k')
      divThm : n = rem + base * (S k')
      divThm = DivisionTheorem n (S k') SIsNonZero SIsNonZero
  in rewrite step1 in
     rewrite step2 in
     -- goal: base * (S k') + rem = n
     rewrite plusCommutative (base * (S k')) rem in
     -- goal: rem + base * (S k') = n
     sym divThm

||| Corollary in the Layer-2 vocabulary: the block partition's `sliceSum` equals
||| `n` for all n and k>0. `blockPartitionComplete` (Layer 2) reduced sliceSum to
||| `sumNat (perItemCounts n k)`; `blockCounts n k'` is that very count vector in
||| reducing form, so this closes the completeness loop for the real strategy.
export
blockSlicesSumIsN : (n, k' : Nat) ->
                    sliceSum (contiguousFrom 0 (blockCounts n k')) = n
blockSlicesSumIsN n k' =
  rewrite contiguousComplete 0 (blockCounts n k') in
  blockCountsComplete n k'

||| The full `PartitionComplete` proof OBJECT for the block partition, packaged
||| as a `Partition` (the Layer-2 invariant type `sliceSum p.slices = n`), now
||| DISCHARGED for the real block strategy at any n and k>0 — previously only
||| provable for hand-written fixed vectors in `Proofs.idr`.
export
blockPartitionIsComplete : (n, k' : Nat) ->
  PartitionComplete
    (MkPartition {n} {k = S k'} (contiguousFrom 0 (blockCounts n k')))
blockPartitionIsComplete n k' = IsComplete (blockSlicesSumIsN n k')

--------------------------------------------------------------------------------
-- Sound + complete decision for "these counts cover exactly n"
--------------------------------------------------------------------------------

||| A natural decision: do a candidate count vector's slices sum to exactly the
||| declared item total? Decidable because `sumNat` is a concrete Nat and `Nat`
||| has `DecEq`. Sound (Yes carries the equality) and complete (No carries a
||| refutation), via `decEq`.
export
decCoversExactly : (target : Nat) -> (counts : Vect k Nat) ->
                   Dec (sumNat counts = target)
decCoversExactly target counts = decEq (sumNat counts) target

||| Reduce a `Dec` to whether it is the `No` branch — a concrete projector that
||| evaluates, used by the negative-control below (the `No contra` term itself
||| does not reduce cheaply, but its tag does).
public export
decidedNo : Dec p -> Bool
decidedNo (Yes _) = False
decidedNo (No _)  = True

--------------------------------------------------------------------------------
-- POSITIVE controls: concrete inhabited instances
--------------------------------------------------------------------------------

||| Positive witness: 10 items over 3 locales. base = 3, rem = 1, so counts are
||| [4,3,3] summing to 10. Machine-checked by `Refl` (the NZ primitives reduce on
||| concrete literals) AND re-derived by the general theorem below.
export
covers10over3 : sumNat (blockCounts 10 2) = 10
covers10over3 = Refl

||| The same fact via the general Layer-3 theorem, confirming the abstract proof
||| specialises to the concrete reduct.
export
covers10over3_general : sumNat (blockCounts 10 2) = 10
covers10over3_general = blockCountsComplete 10 2

||| A second concrete instance where division is exact (rem = 0): 12 over 4 gives
||| [3,3,3,3] summing to 12. Exercises the `rem = 0` branch of the counting.
export
covers12over4 : sumNat (blockCounts 12 3) = 12
covers12over4 = Refl

||| A positive Dec witness: the decision says Yes for the [4,3,3] cover of 10.
||| `decCoversExactly` returns `Yes` here, and we project its proof.
export
dec10over3Yes : decCoversExactly 10 (blockCounts 10 2) = Yes Refl
dec10over3Yes = Refl

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls
--------------------------------------------------------------------------------

||| Non-vacuity 1: the theorem is NOT trivially true for the wrong target. The
||| block cover of 10 does not sum to 9. We derive it from the real total (10):
||| if it were also 9 then 10 = 9, absurd. (A bare `Refl : ... = 9` would itself
||| be a type error, which is the point.)
export
notCovers10as9 : Not (sumNat (blockCounts 10 2) = 9)
notCovers10as9 prf =
  -- blockCountsComplete 10 2 : sumNat (blockCounts 10 2) = 10
  uninhabited (trans (sym (blockCountsComplete 10 2)) prf)

||| Non-vacuity 2: the decision procedure genuinely says No when the target is
||| wrong (9 vs the true 10). If `decCoversExactly` always said Yes the theorem
||| would be vacuous; this `Refl` (the No tag reduces concretely) rules it out.
||| Paired with `notCovers10as9`, this is the sound+complete negative side of the
||| decision (Yes side witnessed by `dec10over3Yes`).
export
dec10over3as9No : decidedNo (decCoversExactly 9 (blockCounts 10 2)) = True
dec10over3as9No = Refl

||| Non-vacuity 3 (numBelow is real, not a constant): with threshold 0 nobody
||| gets the extra slot, but with a positive threshold somebody does — these are
||| DIFFERENT, so the remainder count truly depends on `rem`. A `Refl` here would
||| be ill-typed (0 vs 2), so the negation is the honest statement.
export
remainderCountMatters : Not (numBelow 0 0 5 = numBelow 0 2 5)
remainderCountMatters prf = uninhabited prf
