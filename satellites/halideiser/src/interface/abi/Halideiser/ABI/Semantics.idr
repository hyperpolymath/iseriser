-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Halideiser: SCHEDULE EQUIVALENCE.
|||
||| Halide's central guarantee is that a *schedule* changes only HOW a
||| computation executes (loop order, tiling, splitting), never WHAT it
||| computes. This module makes that guarantee machine-checked for the
||| canonical schedule transformation: the loop SPLIT.
|||
||| Domain model
||| ------------
||| A 1-D pipeline stage is a pure pointwise function `f : Nat -> Nat`
||| applied at every index of an iteration domain `[0 .. n-1]`.
|||
|||   * unscheduled execution  : evaluate f at the flat index list
|||                              `range n = [0,1,...,n-1]` in order.
|||   * scheduled (split f=k)  : split the domain into `outer` blocks of
|||                              `inner` iterations (n = outer * inner),
|||                              run the nested loop, and reconstruct each
|||                              global index as `o*inner + i`.
|||
||| Headline property (`SplitEquivalent`): for every stage `f` and every
||| split `(outer, inner)`, the scheduled result equals the unscheduled
||| result over the domain of size `outer * inner`. This is a genuine,
||| non-vacuous theorem: the proof rests on a structural lemma that the
||| split enumeration reproduces the flat index enumeration exactly.
|||
||| The bad case (a schedule that silently REORDERS or DROPS work and so
||| changes the result) has NO inhabitant of `SplitEquivalent`: the
||| negative control exhibits a concrete fake "schedule" whose output
||| differs, and proves it is `Not` equivalent.
module Halideiser.ABI.Semantics

import Halideiser.ABI.Types
import Data.Nat
import Data.List
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Iteration domain: the flat index list executed by the unscheduled loop
--------------------------------------------------------------------------------

||| `range n = [0, 1, ..., n-1]` — the iteration domain of a 1-D stage.
public export
range : Nat -> List Nat
range Z     = []
range (S k) = range k ++ [k]

||| Unscheduled execution: apply the pointwise stage `f` at every index.
public export
runFlat : (f : Nat -> Nat) -> (n : Nat) -> List Nat
runFlat f n = map f (range n)

--------------------------------------------------------------------------------
-- The SPLIT schedule
--------------------------------------------------------------------------------

||| Reconstruct the global index from an (outer, inner) loop pair.
||| This is exactly Halide's `split(x, xo, xi, inner)` index arithmetic:
||| the original index is `xo * inner + xi`.
public export
splitIndex : (inner : Nat) -> (o : Nat) -> (i : Nat) -> Nat
splitIndex inner o i = o * inner + i

||| Run one inner block: for a fixed outer `o`, apply `f` at every inner
||| index `i in [0 .. inner-1]`, reconstructing the global index each time.
public export
runInner : (f : Nat -> Nat) -> (inner : Nat) -> (o : Nat) -> List Nat
runInner f inner o = map (\i => f (splitIndex inner o i)) (range inner)

||| Concatenate a list of blocks left-to-right. Defined by explicit
||| structural recursion (NOT `concatMap`/`foldl`) so it reduces cleanly
||| during proof: `concatBlocks (b :: bs) = b ++ concatBlocks bs`.
public export
concatBlocks : List (List a) -> List a
concatBlocks []        = []
concatBlocks (b :: bs) = b ++ concatBlocks bs

||| Scheduled execution under `split` with `outer` blocks of `inner`
||| iterations each: concatenate the inner blocks in outer order.
public export
runSplit : (f : Nat -> Nat) -> (outer : Nat) -> (inner : Nat) -> List Nat
runSplit f outer inner =
  concatBlocks (map (runInner f inner) (range outer))

--------------------------------------------------------------------------------
-- Structural lemmas about `range` under splitting
--------------------------------------------------------------------------------

||| `map` distributes over `++`. (Local, total; avoids relying on the
||| exact library lemma name.)
mapAppendL : (g : a -> b) -> (xs, ys : List a) ->
             map g (xs ++ ys) = map g xs ++ map g ys
mapAppendL g []        ys = Refl
mapAppendL g (x :: xs) ys = cong (g x ::) (mapAppendL g xs ys)

||| `map` fuses: mapping `g` then `h` is mapping `(h . g)`.
mapFusionL : (h : b -> c) -> (g : a -> b) -> (xs : List a) ->
             map h (map g xs) = map (\x => h (g x)) xs
mapFusionL h g []        = Refl
mapFusionL h g (x :: xs) = cong (h (g x) ::) (mapFusionL h g xs)

||| `concatBlocks` distributes over `++` of block-lists.
concatBlocksAppend : (xs, ys : List (List a)) ->
                     concatBlocks (xs ++ ys)
                       = concatBlocks xs ++ concatBlocks ys
concatBlocksAppend []        ys = Refl
concatBlocksAppend (b :: bs) ys =
  rewrite concatBlocksAppend bs ys in
    appendAssociative b (concatBlocks bs) (concatBlocks ys)

||| Peel the last block: `concatBlocks (bs ++ [b]) = concatBlocks bs ++ b`.
concatBlocksSnoc : (bs : List (List a)) -> (b : List a) ->
                   concatBlocks (bs ++ [b]) = concatBlocks bs ++ b
concatBlocksSnoc bs b =
  rewrite concatBlocksAppend bs [b] in
    cong (concatBlocks bs ++) (appendNilRightNeutral b)

||| Decompose a range at an addition point:
||| `range (a + b) = range a ++ map (+ a) (range b)`.
||| The new block `[a, a+1, ..., a+b-1]` is exactly the old indices of
||| `range b` shifted up by `a`. Proof by induction on `b` using the snoc
||| structure of `range`.
rangeAppend : (a, b : Nat) ->
              range (a + b) = range a ++ map (\i => i + a) (range b)
rangeAppend a Z = rewrite plusZeroRightNeutral a in
                  sym (appendNilRightNeutral (range a))
rangeAppend a (S k) =
  rewrite sym (plusSuccRightSucc a k) in
  -- LHS: range (S (a+k)) = range (a+k) ++ [a+k]
  rewrite rangeAppend a k in
  -- LHS: (range a ++ map (+a) (range k)) ++ [a+k]
  rewrite mapAppendL (\i => i + a) (range k) [k] in
  -- RHS inner: map (+a) (range k) ++ [k+a]
  rewrite plusCommutative k a in
  -- now [k+a] becomes [a+k] on the RHS, matching the LHS snoc element
    sym (appendAssociative (range a) (map (\i => i + a) (range k)) [a + k])

||| One outer block, expressed flatly: applying `f` after the inner-index
||| reconstruction `(+ o*inner)` equals `f` mapped over the shifted range.
||| This lines `runInner f inner o` up with the block that `rangeAppend`
||| produces for the flat run.
runInnerAsFlat :
  (f : Nat -> Nat) -> (inner, o : Nat) ->
  runInner f inner o = map f (map (\i => i + o * inner) (range inner))
runInnerAsFlat f inner o =
  rewrite mapFusionL f (\i => i + o * inner) (range inner) in
    mapExtFn (range inner)
  where
    ||| `splitIndex inner o i = o*inner + i = i + o*inner`, pointwise.
    mapExtFn : (xs : List Nat) ->
               map (\i => f (splitIndex inner o i)) xs
                 = map (\i => f (i + o * inner)) xs
    mapExtFn []        = Refl
    mapExtFn (x :: xs) =
      cong2 (::)
        (cong f (plusCommutative (o * inner) x))
        (mapExtFn xs)

||| The heart of the theorem. Enumerating the FLAT domain
||| `range (outer * inner)` and applying `f`, versus enumerating the SPLIT
||| nested domain and reconstructing each index via `o*inner + i`, produce
||| the SAME list.
|||
||| Proof by induction on `outer`. The successor case peels the last outer
||| block off both sides: `runSplit` via `concatBlocksSnoc`, and `runFlat`
||| via `rangeAppend` (`S o * inner = o*inner + inner`). The two peeled
||| blocks coincide by `runInnerAsFlat`.
splitEnumerates :
  (f : Nat -> Nat) -> (outer : Nat) -> (inner : Nat) ->
  runSplit f outer inner = runFlat f (outer * inner)
splitEnumerates f Z inner = Refl
splitEnumerates f (S o) inner =
  -- LHS: concatBlocks (map (runInner f inner) (range o ++ [o]))
  rewrite mapAppendL (runInner f inner) (range o) [o] in
  rewrite concatBlocksSnoc (map (runInner f inner) (range o)) (runInner f inner o) in
  -- LHS = runSplit f o inner ++ runInner f inner o
  rewrite splitEnumerates f o inner in
  -- LHS = map f (range (o*inner)) ++ runInner f inner o
  rewrite runInnerAsFlat f inner o in
  -- LHS = map f (range (o*inner)) ++ map f (map (+ o*inner) (range inner))
  rewrite sym (mapAppendL f (range (o * inner)) (map (\i => i + o * inner) (range inner))) in
  -- LHS = map f (range (o*inner) ++ map (+ o*inner) (range inner))
  rewrite sym (rangeAppend (o * inner) inner) in
  -- LHS = map f (range (o*inner + inner))
  -- RHS: map f (range (S o * inner)) ; S o * inner = inner + o*inner.
  -- Show o*inner + inner = S o * inner so the ranges match.
  rewrite plusCommutative (o * inner) inner in
    Refl

--------------------------------------------------------------------------------
-- Headline property
--------------------------------------------------------------------------------

||| `SplitEquivalent f outer inner` is the proposition that the scheduled
||| (split) run equals the unscheduled (flat) run over the domain of size
||| `outer * inner`. There is NO way to inhabit this for a schedule that
||| changes the result — the only constructor demands a real equality.
public export
data SplitEquivalent : (f : Nat -> Nat) -> (outer, inner : Nat) -> Type where
  MkSplitEquivalent :
    runSplit f outer inner = runFlat f (outer * inner) ->
    SplitEquivalent f outer inner

||| The theorem: EVERY split schedule is equivalent to the flat schedule.
public export
splitPreservesResult :
  (f : Nat -> Nat) -> (outer, inner : Nat) -> SplitEquivalent f outer inner
splitPreservesResult f outer inner =
  MkSplitEquivalent (splitEnumerates f outer inner)

--------------------------------------------------------------------------------
-- Certifier
--------------------------------------------------------------------------------

||| Certify a split schedule against a stage. Always returns `Ok` because
||| `splitPreservesResult` shows every split is sound; the soundness fact
||| below ties the `Ok` verdict back to the equivalence proposition.
public export
certifySplit : (f : Nat -> Nat) -> (outer, inner : Nat) -> Result
certifySplit f outer inner = Ok

||| Soundness of the certifier: an `Ok` verdict really does imply the
||| scheduled and unscheduled runs agree.
public export
certifySplitSound :
  (f : Nat -> Nat) -> (outer, inner : Nat) ->
  certifySplit f outer inner = Ok ->
  runSplit f outer inner = runFlat f (outer * inner)
certifySplitSound f outer inner _ = splitEnumerates f outer inner

--------------------------------------------------------------------------------
-- Positive control: a concrete schedule equivalence witness
--------------------------------------------------------------------------------

||| A concrete stage: double each pixel index value.
public export
double : Nat -> Nat
double n = n + n

||| POSITIVE CONTROL. Splitting an extent-12 domain into 3 outer blocks of
||| 4 inner iterations is equivalent to running it flat. An inhabited
||| witness — the proof obligation is discharged by the general theorem.
public export
doubleSplit3x4Equivalent : SplitEquivalent Semantics.double 3 4
doubleSplit3x4Equivalent = splitPreservesResult double 3 4

||| And the underlying lists are literally equal on this concrete case.
public export
doubleSplit3x4Concrete : runSplit Semantics.double 3 4 = runFlat Semantics.double 12
doubleSplit3x4Concrete = Refl

--------------------------------------------------------------------------------
-- Negative control: a result-changing "schedule" is NOT equivalent
--------------------------------------------------------------------------------

||| A FAKE schedule that drops the last block (executes only `outer-1`
||| blocks). This models an unsound schedule that silently omits work.
public export
runSplitDropLast : (f : Nat -> Nat) -> (outer, inner : Nat) -> List Nat
runSplitDropLast f outer inner =
  concatMap (runInner f inner) (range (pred outer))

||| NEGATIVE CONTROL. On the concrete extent-12 case, the work-dropping
||| schedule does NOT reproduce the flat run: their output lists differ.
||| Machine-checked: the two concrete lists are unequal.
public export
dropLastNotEquivalent :
  Not (runSplitDropLast Semantics.double 3 4 = runFlat Semantics.double 12)
dropLastNotEquivalent eq = case eq of Refl impossible
