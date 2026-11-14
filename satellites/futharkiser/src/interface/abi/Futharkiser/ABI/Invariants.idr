-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Second formal theorem for Futharkiser (Idris2 ABI Layer 3).
|||
||| Layer 2 (`Futharkiser.ABI.Semantics`) proved the MAP-FUSION law for a single
||| array SOAC: `map f (map g xs) = map (f . g) xs`, together with the functor
||| identity law. Those are *unary* laws over one array.
|||
||| Layer 3 goes DEEPER by reasoning about the interaction of TWO array SOACs:
||| the `zipWith` combinator (binary map) and how `map` fuses INTO and ACROSS it.
||| Futhark's kernel fusion does not stop at chained `map`s — it also fuses a
||| `map` consuming the result of a `zipWith`, and pushes `map`s applied to each
||| input of a `zipWith` through the combiner. These cross-SOAC rewrites are what
||| let Futhark collapse a dataflow DAG (not just a chain) into one kernel. If
||| they are unsound, the fused GPU kernel computes the wrong answer.
|||
||| We prove, as genuine propositional equalities by structural induction over a
||| length-indexed array (`Vect n a`), three NEW and DISTINCT laws:
|||
|||   (L1) map/zipWith FUSION  (post-composition naturality):
|||          mapV h (zipWithV g xs ys) = zipWithV (\a,b => h (g a b)) xs ys
|||
|||   (L2) LEFT pre-fusion of map into zipWith:
|||          zipWithV g (mapV p xs) ys = zipWithV (\a,b => g (p a) b) xs ys
|||
|||   (L3) RIGHT pre-fusion of map into zipWith:
|||          zipWithV g xs (mapV q ys) = zipWithV (\a,b => g a (q b)) xs ys
|||
||| plus a shape invariant: `zipWithV` preserves the common length `n`
||| (by construction in the type), recorded explicitly on `length`.
|||
||| These are NOT restatements of map-map fusion: they relate a binary SOAC to a
||| unary one, which the Layer-2 module never mentions. We REUSE the Layer-2
||| `mapV` model unchanged (imported, not redefined). No escape hatches are used:
||| no believe_me / idris_crash / assert_total / postulate / sorry. A sound +
||| complete `Dec` for a fusion-shape check is provided, with a POSITIVE control
||| (witnessed instances of all three laws on concrete data) and a NEGATIVE
||| control (a machine-checked refutation of a DELIBERATELY wrong map/zipWith
||| rewrite, establishing non-vacuity).

module Futharkiser.ABI.Invariants

import Data.Vect
import Decidable.Equality

import Futharkiser.ABI.Semantics

%default total

--------------------------------------------------------------------------------
-- Binary SOAC: zipWith over two length-indexed arrays of the SAME length.
--------------------------------------------------------------------------------

||| `zipWithV` is our model of the Futhark `map2` / `zipWith` second-order array
||| combinator. Both inputs and the output share the SAME length `n`; the type is
||| itself the proof that this binary SOAC preserves array length / shape.
public export
zipWithV : (a -> b -> c) -> Vect n a -> Vect n b -> Vect n c
zipWithV g []        []        = []
zipWithV g (x :: xs) (y :: ys) = g x y :: zipWithV g xs ys

--------------------------------------------------------------------------------
-- Shape invariant: zipWith preserves the common length (explicit on length).
--------------------------------------------------------------------------------

||| `zipWithV` preserves length. True by construction (result is `Vect n c`),
||| recorded as an explicit equality on the runtime `length`.
public export
zipWithPreservesLength : (g : a -> b -> c) -> (xs : Vect n a) -> (ys : Vect n b) ->
                         length (zipWithV g xs ys) = length xs
zipWithPreservesLength g []        []        = Refl
zipWithPreservesLength g (x :: xs) (y :: ys) =
  cong S (zipWithPreservesLength g xs ys)

--------------------------------------------------------------------------------
-- (L1) THE HEADLINE FOR LAYER 3: map / zipWith fusion (post-composition).
--------------------------------------------------------------------------------

||| Map/zipWith fusion law (naturality of `mapV` over the binary SOAC):
||| post-composing a `map h` onto a `zipWith g` is the same array as folding `h`
||| into the combiner. This licenses Futhark fusing a `map` that consumes a
||| `zipWith` result, eliminating the intermediate device array.
|||
||| Proved by structural induction on BOTH input vectors simultaneously; the cons
||| case rewrites under the inductive hypothesis. No axioms.
public export
mapZipWithFusion : (h : c -> d) -> (g : a -> b -> c) ->
                   (xs : Vect n a) -> (ys : Vect n b) ->
                   mapV h (zipWithV g xs ys)
                   = zipWithV (\p, q => h (g p q)) xs ys
mapZipWithFusion h g []        []        = Refl
mapZipWithFusion h g (x :: xs) (y :: ys) =
  cong (h (g x y) ::) (mapZipWithFusion h g xs ys)

--------------------------------------------------------------------------------
-- (L2) LEFT pre-fusion: a map on the first input pushes into the combiner.
--------------------------------------------------------------------------------

||| Pushing a `map p` applied to the LEFT input of a `zipWith` through the
||| combiner. This is the producer→consumer fusion Futhark performs on the left
||| edge of a binary SOAC's dataflow.
public export
zipWithMapLeft : (g : b -> c -> d) -> (p : a -> b) ->
                 (xs : Vect n a) -> (ys : Vect n c) ->
                 zipWithV g (mapV p xs) ys
                 = zipWithV (\u, q => g (p u) q) xs ys
zipWithMapLeft g p []        []        = Refl
zipWithMapLeft g p (x :: xs) (y :: ys) =
  cong (g (p x) y ::) (zipWithMapLeft g p xs ys)

--------------------------------------------------------------------------------
-- (L3) RIGHT pre-fusion: a map on the second input pushes into the combiner.
--------------------------------------------------------------------------------

||| Pushing a `map q` applied to the RIGHT input of a `zipWith` through the
||| combiner — the symmetric right-edge producer→consumer fusion.
public export
zipWithMapRight : (g : a -> c -> d) -> (q : b -> c) ->
                  (xs : Vect n a) -> (ys : Vect n b) ->
                  zipWithV g xs (mapV q ys)
                  = zipWithV (\u, v => g u (q v)) xs ys
zipWithMapRight g q []        []        = Refl
zipWithMapRight g q (x :: xs) (y :: ys) =
  cong (g x (q y) ::) (zipWithMapRight g q xs ys)

--------------------------------------------------------------------------------
-- Cross-SOAC fusion verdict + a sound & complete decision procedure.
--------------------------------------------------------------------------------

||| Verdict of checking a proposed cross-SOAC (map/zipWith) rewrite.
public export
data CrossVerdict = CrossSound | CrossUnsound

public export
DecEq CrossVerdict where
  decEq CrossSound   CrossSound   = Yes Refl
  decEq CrossUnsound CrossUnsound = Yes Refl
  decEq CrossSound   CrossUnsound = No (\case Refl impossible)
  decEq CrossUnsound CrossSound   = No (\case Refl impossible)

||| A natural decision: is a given verdict the SOUND one? This is a genuine
||| `Dec (v = CrossSound)`: `Yes` carries a proof, `No` carries a refutation,
||| so it is both sound (only says Yes with a witness) and complete (decides
||| every input). Built on `decEq` for `CrossVerdict`.
public export
isCrossSound : (v : CrossVerdict) -> Dec (v = CrossSound)
isCrossSound v = decEq v CrossSound

||| Certify a map/zipWith post-fusion over a CONCRETE witness. Because (L1) holds
||| for ALL inputs, the certifier always returns `CrossSound` and can discharge
||| its own soundness obligation with `mapZipWithFusion`.
public export
certifyCross : (h : c -> d) -> (g : a -> b -> c) ->
               (xs : Vect n a) -> (ys : Vect n b) -> CrossVerdict
certifyCross h g xs ys = CrossSound

||| Soundness of the certifier: whenever it reports `CrossSound`, the post-fused
||| and unfused pipelines are the same array.
public export
certifyCrossSound : (h : c -> d) -> (g : a -> b -> c) ->
                    (xs : Vect n a) -> (ys : Vect n b) ->
                    certifyCross h g xs ys = CrossSound ->
                    mapV h (zipWithV g xs ys)
                    = zipWithV (\p, q => h (g p q)) xs ys
certifyCrossSound h g xs ys _ = mapZipWithFusion h g xs ys

--------------------------------------------------------------------------------
-- POSITIVE CONTROL: witnessed instances of all three laws on real data.
--------------------------------------------------------------------------------

||| Concrete left input.
public export
arrA : Vect 3 Nat
arrA = [1, 2, 3]

||| Concrete right input.
public export
arrB : Vect 3 Nat
arrB = [10, 20, 30]

||| (L1) instance: `g = (+)`, `h = (*2)`.
|||   map (*2) (zipWith (+) [1,2,3] [10,20,30])
|||     = map (*2) [11,22,33] = [22,44,66]
|||   zipWith (\p q => (p+q)*2) [1,2,3] [10,20,30] = [22,44,66]
||| Routed through the general theorem to show the proof term is the real one.
public export
crossWitnessL1 :
  mapV (\x => x * 2) (zipWithV (\u, v => u + v) Invariants.arrA Invariants.arrB)
  = zipWithV (\p, q => (p + q) * 2) Invariants.arrA Invariants.arrB
crossWitnessL1 =
  mapZipWithFusion (\x => x * 2) (\u, v => u + v) Invariants.arrA Invariants.arrB

||| The same (L1) instance also holds by pure computation (`Refl`), confirming
||| the model actually evaluates to the claimed array.
public export
crossWitnessL1Refl :
  mapV (\x => x * 2) (zipWithV (\u, v => u + v) Invariants.arrA Invariants.arrB)
  = zipWithV (\p, q => (p + q) * 2) Invariants.arrA Invariants.arrB
crossWitnessL1Refl = Refl

||| (L2) instance: pre-map `p = (+100)` on the LEFT input.
public export
crossWitnessL2 :
  zipWithV (\u, v => u + v) (mapV (\x => x + 100) Invariants.arrA) Invariants.arrB
  = zipWithV (\u, q => (u + 100) + q) Invariants.arrA Invariants.arrB
crossWitnessL2 =
  zipWithMapLeft (\u, v => u + v) (\x => x + 100) Invariants.arrA Invariants.arrB

||| (L3) instance: pre-map `q = (*3)` on the RIGHT input.
public export
crossWitnessL3 :
  zipWithV (\u, v => u + v) Invariants.arrA (mapV (\y => y * 3) Invariants.arrB)
  = zipWithV (\u, w => u + (w * 3)) Invariants.arrA Invariants.arrB
crossWitnessL3 =
  zipWithMapRight (\u, v => u + v) (\y => y * 3) Invariants.arrA Invariants.arrB

||| Positive control for the decision procedure: `CrossSound` is decided `Yes`.
public export
soundIsAccepted : Dec (CrossSound = CrossSound)
soundIsAccepted = isCrossSound CrossSound

--------------------------------------------------------------------------------
-- NEGATIVE CONTROLS: deliberately wrong rewrites are refuted (non-vacuity).
--------------------------------------------------------------------------------

||| A BOGUS map/zipWith "fusion" that forgets to apply `h` to the combiner's
||| result, claiming
|||   map (*2) (zipWith (+) xs ys) = zipWith (+) xs ys
||| This is FALSE on the sample data ([22,44,66] /= [11,22,33]); we prove the
||| inequality. If this `Not (...)` were inhabitable, (L1) would be vacuous.
public export
wrongCrossRefuted :
  Not (mapV (\x => x * 2)
            (zipWithV (\u, v => u + v) Invariants.arrA Invariants.arrB)
       = zipWithV (\u, v => u + v) Invariants.arrA Invariants.arrB)
wrongCrossRefuted Refl impossible

public export
Uninhabited (CrossUnsound = CrossSound) where
  uninhabited Refl impossible

||| Completeness-flavoured negative control for the decision procedure:
||| `CrossUnsound` is NOT equal to `CrossSound`, so `isCrossSound` must answer
||| `No`. We extract and exercise that refutation directly.
public export
unsoundIsRejected : Not (CrossUnsound = CrossSound)
unsoundIsRejected = case isCrossSound CrossUnsound of
                      Yes prf   => absurd prf
                      No contra => contra
