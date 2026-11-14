-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Futharkiser (Idris2 ABI Layer 2).
|||
||| Futharkiser compiles annotated array operations to GPU kernels via Futhark.
||| The single most important optimisation that justifies that pipeline is
||| MAP FUSION: rewriting `map f (map g xs)` into `map (f . g) xs`. Futhark's
||| whole performance story rests on fusing chained SOACs so that intermediate
||| arrays are never materialised on the device. If fusion is not semantically
||| sound, the generated GPU kernel computes the WRONG answer.
|||
||| This module gives a faithful, length-indexed model of `map` over a Futhark
||| array (a `Vect n a`) and proves, as a real propositional equality, that:
|||
|||   (1) map preserves length            : mapV f xs : Vect n b  (by construction)
|||   (2) FUSION LAW                       : mapV f (mapV g xs) = mapV (f . g) xs
|||   (3) IDENTITY LAW (functor identity)  : mapV id xs = xs
|||
||| (2) is the headline. Both are proved by structural induction with no
||| escape hatches (no believe_me / postulate / assert). A certifier maps a
||| concrete fused/unfused pair to a ProofStatus-like verdict, and there is a
||| positive control (a witnessed instance of the law) plus a negative control
||| (a machine-checked refutation of a DELIBERATELY wrong fusion).

module Futharkiser.ABI.Semantics

import Data.Vect
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful model of the Futhark `map` SOAC over a length-indexed array.
--------------------------------------------------------------------------------

||| `mapV` is our model of the Futhark `map` second-order array combinator.
||| The output Vect has exactly the same length `n` as the input: the type
||| itself is the proof that `map` preserves array length / shape, which is the
||| rank-and-length invariant the GPU codegen relies on.
public export
mapV : (a -> b) -> Vect n a -> Vect n b
mapV f []        = []
mapV f (x :: xs) = f x :: mapV f xs

--------------------------------------------------------------------------------
-- Length preservation (made explicit as a value-level fact).
--------------------------------------------------------------------------------

||| `mapV` preserves length. This is true by construction (the result type is
||| `Vect n b` for input `Vect n a`), and we record it as an explicit equality
||| on the runtime `length`.
public export
mapPreservesLength : (f : a -> b) -> (xs : Vect n a) ->
                     length (mapV f xs) = length xs
mapPreservesLength f []        = Refl
mapPreservesLength f (x :: xs) = cong S (mapPreservesLength f xs)

--------------------------------------------------------------------------------
-- THE HEADLINE: the map-fusion law (sound fusion of chained SOACs).
--------------------------------------------------------------------------------

||| Map fusion law: applying `map g` then `map f` is exactly the same array as
||| applying `map (f . g)` once. This is what licenses Futhark's kernel-fusion
||| optimisation — eliminating the intermediate device array is observationally
||| equivalent to the unfused pipeline, element for element.
|||
||| Proved by structural induction on the input vector; the cons case rewrites
||| under the inductive hypothesis. No axioms.
public export
mapFusion : (f : b -> c) -> (g : a -> b) -> (xs : Vect n a) ->
            mapV f (mapV g xs) = mapV (\x => f (g x)) xs
mapFusion f g []        = Refl
mapFusion f g (x :: xs) = cong (f (g x) ::) (mapFusion f g xs)

||| Functor identity law: fusing with the identity function is a no-op. Together
||| with `mapFusion` this makes `mapV` a lawful functor, so any chain of fused
||| maps in the generated kernel is equal to the unfused source pipeline.
public export
mapIdentity : (xs : Vect n a) -> mapV (\x => x) xs = xs
mapIdentity []        = Refl
mapIdentity (x :: xs) = cong (x ::) (mapIdentity xs)

--------------------------------------------------------------------------------
-- Fusion verdict + soundness certifier.
--------------------------------------------------------------------------------

||| Verdict of checking a proposed fusion rewrite.
public export
data FusionVerdict = FusionSound | FusionUnsound

public export
DecEq FusionVerdict where
  decEq FusionSound   FusionSound   = Yes Refl
  decEq FusionUnsound FusionUnsound = Yes Refl
  decEq FusionSound   FusionUnsound = No (\case Refl impossible)
  decEq FusionUnsound FusionSound   = No (\case Refl impossible)

||| Certify that fusing `map f . map g` into `map (f . g)` over a CONCRETE
||| witness vector produces the identical array. Because the fusion law holds
||| for ALL vectors, the certifier can always return `FusionSound` and discharge
||| its own soundness obligation with `mapFusion`.
public export
certifyFusion : (f : b -> c) -> (g : a -> b) -> (xs : Vect n a) -> FusionVerdict
certifyFusion f g xs = FusionSound

||| Soundness of the certifier: whenever it reports `FusionSound`, the fused and
||| unfused pipelines really are the same array.
public export
certifyFusionSound : (f : b -> c) -> (g : a -> b) -> (xs : Vect n a) ->
                     certifyFusion f g xs = FusionSound ->
                     mapV f (mapV g xs) = mapV (\x => f (g x)) xs
certifyFusionSound f g xs _ = mapFusion f g xs

--------------------------------------------------------------------------------
-- POSITIVE CONTROL: an inhabited witness of the fusion law on real data.
--------------------------------------------------------------------------------

||| Concrete input array.
public export
sampleArray : Vect 3 Nat
sampleArray = [10, 20, 30]

||| `g = (+1)`, `f = (*2)`. The fused and unfused pipelines must agree.
||| This is a fully evaluated, machine-checked instance of the headline law:
|||   map (*2) (map (+1) [10,20,30]) = map (\x => (x+1)*2) [10,20,30] = [22,42,62]
public export
fusionWitness : mapV (\x => x * 2) (mapV (\x => x + 1) Semantics.sampleArray)
                = mapV (\x => (x + 1) * 2) Semantics.sampleArray
fusionWitness = Refl

||| The same instance routed through the general theorem (not just `Refl`),
||| showing the proof term is the genuine inductive one.
public export
fusionWitnessViaTheorem : mapV (\x => x * 2) (mapV (\x => x + 1) Semantics.sampleArray)
                          = mapV (\x => (x + 1) * 2) Semantics.sampleArray
fusionWitnessViaTheorem = mapFusion (\x => x * 2) (\x => x + 1) Semantics.sampleArray

--------------------------------------------------------------------------------
-- NEGATIVE CONTROL: a DELIBERATELY wrong fusion is refuted (non-vacuity).
--------------------------------------------------------------------------------

||| A bogus "fusion" that drops the inner map's effect: claiming
|||   map (*2) (map (+1) xs) = map (*2) xs
||| This is FALSE for our sample data, and we prove the inequality.
||| If this `Not (...)` were inhabitable, the fusion law would be vacuous.
public export
wrongFusionRefuted :
  Not (mapV (\x => x * 2) (mapV (\x => x + 1) Semantics.sampleArray)
       = mapV (\x => x * 2) Semantics.sampleArray)
wrongFusionRefuted Refl impossible
