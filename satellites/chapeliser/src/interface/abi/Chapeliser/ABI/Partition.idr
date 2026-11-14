-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| General partition-correctness proofs for Chapeliser.
|||
||| `Proofs.idr` verifies completeness/disjointness on a handful of *explicit*
||| slice vectors. This module proves the same invariants **for the whole
||| contiguous-partition family at once** — quantified over an arbitrary vector
||| of per-locale counts — and applies that result to the actual block-partition
||| strategy (the `div`/`mod` counts of `perItemSlices`) for **all** `n` items
||| and `k` locales.
|||
||| The key idea: contiguity is *structural*. A contiguous layout places each
||| slice exactly where the previous one ended, independently of the count
||| values, so the non-overlap guarantee needs no reasoning about `div`/`mod`
||| (which do not reduce at the type level). We capture non-overlap as a
||| `Tiling` — a gapless, overlap-free cover, strictly stronger than the pairwise
||| `disjoint` Bool check — and prove the real block partition is one for all
||| `n`, `k`. The only residual is the completeness identity
||| `sumNat (perItemCounts n k) = n`, which is isolated below.

module Chapeliser.ABI.Partition

import Chapeliser.ABI.Types
import Data.Vect
import Data.Vect.Quantifiers
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- The contiguous layout builder (a reducible, top-level form of perItemSlices)
--------------------------------------------------------------------------------

||| Lay out `k` slices contiguously from `start`, one per count: slice i begins
||| where slice i-1 ended. This is exactly the shape of `perItemSlices`' inner
||| `go`, lifted to top level so proofs can reduce through it.
public export
contiguousFrom : (start : Nat) -> Vect k Nat -> Vect k Slice
contiguousFrom _     []        = []
contiguousFrom start (c :: cs) = MkSlice start c :: contiguousFrom (start + c) cs

||| Sum of a vector of counts.
public export
sumNat : Vect k Nat -> Nat
sumNat []        = 0
sumNat (c :: cs) = c + sumNat cs

--------------------------------------------------------------------------------
-- Completeness, generalised over ALL count vectors
--------------------------------------------------------------------------------

||| For ANY start offset and ANY vector of counts, the contiguous layout's slice
||| counts sum to exactly the total of the counts — no items dropped or
||| duplicated. (`Proofs.idr` only checked this for fixed vectors.)
export
contiguousComplete : (start : Nat) -> (counts : Vect k Nat) ->
                     sliceSum (contiguousFrom start counts) = sumNat counts
contiguousComplete _     []        = Refl
contiguousComplete start (c :: cs) =
  rewrite contiguousComplete (start + c) cs in Refl

--------------------------------------------------------------------------------
-- Tiny LTE lemmas (propositional; these reduce, unlike the compare-based `<=`)
--------------------------------------------------------------------------------

lteReflexive : (n : Nat) -> LTE n n
lteReflexive Z     = LTEZero
lteReflexive (S k) = LTESucc (lteReflexive k)

lteAddR : (n, m : Nat) -> LTE n (n + m)
lteAddR Z     m = LTEZero
lteAddR (S k) m = LTESucc (lteAddR k m)

lteTrans' : LTE a b -> LTE b c -> LTE a c
lteTrans' LTEZero      _           = LTEZero
lteTrans' (LTESucc p) (LTESucc q)  = LTESucc (lteTrans' p q)

--------------------------------------------------------------------------------
-- Non-overlap as a structural tiling (gapless AND overlap-free by construction)
--------------------------------------------------------------------------------

||| `Tiling lo ss` witnesses that `ss` tiles `[lo, …)` with no gaps and no
||| overlaps: the first slice begins at `lo`, and the rest tile from exactly
||| where it ends. Strictly stronger than pairwise disjointness.
public export
data Tiling : Nat -> Vect k Slice -> Type where
  TNil  : Tiling lo []
  TCons : (c : Nat) -> Tiling (lo + c) rest ->
          Tiling lo (MkSlice lo c :: rest)

||| The contiguous layout is a perfect tiling for ANY start and ANY counts.
export
contiguousTiles : (lo : Nat) -> (counts : Vect k Nat) ->
                  Tiling lo (contiguousFrom lo counts)
contiguousTiles _  []        = TNil
contiguousTiles lo (c :: cs) = TCons c (contiguousTiles (lo + c) cs)

--------------------------------------------------------------------------------
-- Tiling ⇒ propositional pairwise non-overlap (no Bool `<=`/`all`)
--------------------------------------------------------------------------------

||| Every slice of a tiling based at `lo` starts at `lo` or later.
export
tilingStartsGE : {ss : Vect k Slice} -> Tiling lo ss ->
                 All (\s => LTE lo s.start) ss
tilingStartsGE TNil          = []
tilingStartsGE (TCons {lo} c t) =
  lteReflexive lo
    :: mapProperty (\le => lteTrans' (lteAddR lo c) le) (tilingStartsGE t)

||| Propositional non-overlap of two slices: `a` ends at or before `b` starts.
public export
NoOverlap : Slice -> Slice -> Type
NoOverlap a b = LTE (a.start + a.count) b.start

||| In a tiling, the head slice does not overlap any later slice — its end is
||| `lo + c`, and every later slice starts there or later. Genuine pairwise
||| disjointness, proven generically (not per concrete vector).
export
tilingHeadNoOverlap : {lo : Nat} -> (c : Nat) -> {rest : Vect k Slice} ->
                      Tiling (lo + c) rest ->
                      All (\s => NoOverlap (MkSlice lo c) s) rest
tilingHeadNoOverlap c t = tilingStartsGE t

--------------------------------------------------------------------------------
-- The actual block-partition strategy is correct for ALL n and k
--------------------------------------------------------------------------------

||| Per-locale counts for the even (block) partition: every locale gets `base`
||| items and the first `rem` locales get one extra. `idx` is the running locale
||| index. (This is the `div`/`mod` content of `perItemSlices`, isolated; the
||| proofs below do not depend on its values.)
public export
countsFrom : (idx, base, rem : Nat) -> (k : Nat) -> Vect k Nat
countsFrom _   _    _   Z     = []
countsFrom idx base rem (S j) =
  (base + (if idx < rem then 1 else 0)) :: countsFrom (S idx) base rem j

||| The block partition's per-locale counts for `n` items over `k` locales.
public export
perItemCounts : (n : Nat) -> (k : Nat) -> Vect k Nat
perItemCounts n k = countsFrom 0 (n `div` k) (n `mod` k) k

||| The block partition laid out contiguously.
public export
blockSlices : (n : Nat) -> (k : Nat) -> Vect k Slice
blockSlices n k = contiguousFrom 0 (perItemCounts n k)

||| MAIN RESULT: for every item count `n` and every locale count `k`, the block
||| partition is a gapless, non-overlapping tiling — no item is assigned to two
||| locales and the assigned ranges abut perfectly. Holds for ALL n, k with no
||| appeal to how `div`/`mod` evaluate.
export
blockPartitionTiles : (n : Nat) -> (k : Nat) -> Tiling 0 (blockSlices n k)
blockPartitionTiles n k = contiguousTiles 0 (perItemCounts n k)

||| Corollary: completeness of the block partition reduces to the residual
||| arithmetic identity `sumNat (perItemCounts n k) = n` — the only `div`/`mod`
||| obligation, which the type checker cannot discharge by reduction (tracked as
||| future proof work). The structural half (slice counts sum to the count
||| total) is proven here for all n, k.
export
blockPartitionComplete : (n : Nat) -> (k : Nat) ->
                         sliceSum (blockSlices n k) = sumNat (perItemCounts n k)
blockPartitionComplete n k = contiguousComplete 0 (perItemCounts n k)

--------------------------------------------------------------------------------
-- Negative control: a wrong-sum partition is genuinely NOT complete
--------------------------------------------------------------------------------

||| A 3-locale layout whose counts sum to 9 cannot be a complete partition of 10
||| items: `PartitionComplete` for `Partition 10 3` demands `sliceSum = 10`, but
||| this layout sums to 9. Witnessing the negation keeps completeness honest.
export
shortPartitionNotComplete :
  Not (PartitionComplete (MkPartition {n = 10} {k = 3} (contiguousFrom 0 [3, 3, 3])))
shortPartitionNotComplete (IsComplete Refl) impossible
