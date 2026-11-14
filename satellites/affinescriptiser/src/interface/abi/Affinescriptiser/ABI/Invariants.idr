-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Structural invariants for Affinescriptiser (ABI Layer 3).
|||
||| This module proves a SECOND, deeper property over the SAME affine-usage
||| model defined in `Affinescriptiser.ABI.Semantics` (the `Trace`/`AffineOk`
||| datatypes are imported, not redefined). Where Layer 2 establishes a
||| sound+complete *checker* for a single trace ("no variable used twice"),
||| Layer 3 establishes an *algebraic composition law* for that checker:
|||
|||   COMPOSITION (the headline Layer-3 theorem):
|||     If two usage traces are each affine-safe AND their variable sets are
|||     disjoint, then their concatenation is affine-safe. Formally
|||         Disjoint t1 t2 -> AffineOk t1 -> AffineOk t2 -> AffineOk (t1 ++ t2)
|||     This is the soundness justification for the codegen *sequencing* two
|||     already-checked program fragments over disjoint locals into one fragment
|||     without re-running the whole affine check.
|||
|||   DECOMPOSITION (the converse structural law):
|||     Affine-safety is preserved under taking the *suffix* of a concatenation:
|||         AffineOk (t1 ++ t2) -> AffineOk t2
|||     i.e. dropping a safe prefix can never break affine-safety of the rest.
|||
||| Both directions are genuine, machine-checked, total proofs. Disjointness is
||| given a sound+complete decision procedure (`decDisjoint`). We supply a
||| POSITIVE control (a concrete inhabited composition witness) and TWO NEGATIVE
||| controls: a `Not` showing overlapping traces compose to an unsafe trace, and
||| a `Not` showing a wide-gap double-use trace is rejected.
|||
||| Quality bar (identical to Layer 2): no believe_me, no idris_crash, no
||| assert_total, no postulate, no sorry, no %hint hacks, no asserted equalities.

module Affinescriptiser.ABI.Invariants

import Affinescriptiser.ABI.Types
import Affinescriptiser.ABI.Semantics
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Membership-over-append lemmas (the technical core)
--------------------------------------------------------------------------------

||| If `x` occurs in `xs ++ ys` then it occurs in `xs` or in `ys`.
||| Proved by induction on `xs`. `Here`/`There` are constructor-headed, so the
||| recursive case-splits reduce cleanly with no stuck `case ... of Refl`.
export
elemAppSplit : {0 x : Var} -> (xs : Trace) -> Elem x (xs ++ ys) -> Either (Elem x xs) (Elem x ys)
elemAppSplit []        el          = Right el
elemAppSplit (y :: ys) Here        = Left Here
elemAppSplit (y :: ys) (There el)  =
  case elemAppSplit ys el of
    Left  inXs => Left  (There inXs)
    Right inYs => Right inYs

||| Conversely, membership in `ys` injects into membership in `xs ++ ys`.
||| Induction on `xs` again; each step is just one `There`.
export
elemAppRight : {0 x : Var} -> (xs : Trace) -> Elem x ys -> Elem x (xs ++ ys)
elemAppRight []        el = el
elemAppRight (y :: ys) el = There (elemAppRight ys el)

||| If `x` is in neither `xs` nor `ys`, it is not in `xs ++ ys`.
||| This is the contrapositive of `elemAppSplit`, packaged for direct use.
export
notElemApp : {0 x : Var}
          -> (xs : Trace)
          -> Not (Elem x xs)
          -> Not (Elem x ys)
          -> Not (Elem x (xs ++ ys))
notElemApp xs nxs nys el =
  case elemAppSplit xs el of
    Left  inXs => nxs inXs
    Right inYs => nys inYs

--------------------------------------------------------------------------------
-- Disjointness of variable sets
--------------------------------------------------------------------------------

||| Two traces are `Disjoint` when no variable appears in both. This is the
||| precondition under which sequencing two affine fragments stays affine: each
||| fragment may reuse names internally only if those names do not collide.
public export
Disjoint : Trace -> Trace -> Type
Disjoint xs ys = (v : Var) -> Elem v xs -> Not (Elem v ys)

||| The empty trace is disjoint from anything (vacuously: nothing is in `[]`).
export
disjointNilLeft : (ys : Trace) -> Disjoint [] ys
disjointNilLeft ys v el = absurd el

||| Drop the head of the left trace and disjointness is preserved.
export
disjointTail : {0 x : Var} -> Disjoint (x :: xs) ys -> Disjoint xs ys
disjointTail dj v inXs = dj v (There inXs)

||| The head of a disjoint left trace is not present in the right trace.
||| `x` is bound explicitly (quantity 1) because we use it at the term level.
export
disjointHeadNotRight : {x : Var} -> Disjoint (x :: xs) ys -> Not (Elem x ys)
disjointHeadNotRight dj = dj x Here

||| Build a disjointness witness by consing onto the left trace: if the new
||| head `x` is absent from `ys` and `xs` is already disjoint from `ys`, then
||| `x :: xs` is disjoint from `ys`. Matching on the LEFT membership refines the
||| variable cleanly (avoiding the Nat-literal coverage pitfalls).
export
consDisjoint : {0 x : Var} -> Not (Elem x ys) -> Disjoint xs ys -> Disjoint (x :: xs) ys
consDisjoint nx _   v Here          = nx
consDisjoint _  dxs v (There inXs)  = dxs v inXs

--------------------------------------------------------------------------------
-- Sound + complete decision procedure for disjointness
--------------------------------------------------------------------------------

||| Decide whether two traces are disjoint. A `Yes` carries a real witness
||| (a function refuting any shared membership), a `No` carries a real overlap.
||| Built only from `isElem` (Data.List.Elem) and the structural lemmas above.
public export
decDisjoint : (xs : Trace) -> (ys : Trace) -> Dec (Disjoint xs ys)
decDisjoint []        ys = Yes (disjointNilLeft ys)
decDisjoint (x :: xs) ys =
  case isElem x ys of
    -- x is shared: the pair cannot be disjoint, since x is in both sides.
    Yes xInYs => No (\dj => disjointHeadNotRight dj xInYs)
    No  xNotYs =>
      case decDisjoint xs ys of
        Yes djRest =>
          Yes (\v, inHead =>
                 case inHead of
                   Here       => xNotYs
                   There inXs => djRest v inXs)
        No notRest =>
          No (\dj => notRest (disjointTail dj))

--------------------------------------------------------------------------------
-- HEADLINE Layer-3 theorem: composition of affine traces over disjoint vars
--------------------------------------------------------------------------------

||| COMPOSITION. Sequencing two affine-safe traces whose variable sets are
||| disjoint yields an affine-safe trace. Proved by induction on the structure
||| of the first trace via its `AffineOk` witness:
|||
|||   * `[] ++ t2` reduces to `t2`, whose safety we already have.
|||   * `(v :: vs) ++ t2` reduces to `v :: (vs ++ t2)`. The new `notLater`
|||     obligation — `v` not in `vs ++ t2` — is discharged by `notElemApp`:
|||     `v` is absent from `vs` (head of t1's witness) and absent from `t2`
|||     (disjointness). The tail is handled by recursion.
export
concatAffine : (t1 : Trace)
            -> Disjoint t1 t2
            -> AffineOk t1
            -> AffineOk t2
            -> AffineOk (t1 ++ t2)
concatAffine []        _  _                  ok2 = ok2
concatAffine (v :: vs) dj (ConsOk nv ok1) ok2 =
  let notInVs   : Not (Elem v vs)        := nv
      notInT2   : Not (Elem v t2)        := disjointHeadNotRight dj
      notInBoth : Not (Elem v (vs ++ t2)) := notElemApp vs notInVs notInT2
      restOk    : AffineOk (vs ++ t2)     := concatAffine vs (disjointTail dj) ok1 ok2
   in ConsOk notInBoth restOk

--------------------------------------------------------------------------------
-- Converse structural law: affine-safety of a suffix
--------------------------------------------------------------------------------

||| DECOMPOSITION. If a concatenation is affine-safe, so is its suffix `t2`.
||| (Dropping a safe prefix never breaks the rest.) Induction on `t1`: each
||| `ConsOk` we strip exposes the `AffineOk (vs ++ t2)` witness for recursion;
||| the base case `[] ++ t2 = t2` returns the witness directly.
export
suffixAffine : (t1 : Trace) -> AffineOk (t1 ++ t2) -> AffineOk t2
suffixAffine []        ok               = ok
suffixAffine (v :: vs) (ConsOk _ rest)  = suffixAffine vs rest

--------------------------------------------------------------------------------
-- Positive control: a concrete inhabited composition
--------------------------------------------------------------------------------

||| Left fragment uses variables 0 and 1 (each once).
export
fragLeftOk : AffineOk [0, 1]
fragLeftOk =
  ConsOk (\el => case el of
                   There el1 => absurd el1)
         (ConsOk absurd NilOk)

||| Right fragment uses variables 2 and 3 (each once).
export
fragRightOk : AffineOk [2, 3]
fragRightOk =
  ConsOk (\el => case el of
                   There el1 => absurd el1)
         (ConsOk absurd NilOk)

||| 0 is not an element of [2,3]: the diagonal `Here`/`There Here` shapes would
||| require 0 = 2 / 0 = 3 (automatically pruned), so only the empty tail
||| `There (There el)` remains, discharged by `absurd`.
zeroNotIn23 : Not (Elem (the Var 0) [2, 3])
zeroNotIn23 (There (There el)) = absurd el

||| 1 is not an element of [2,3]. Same structure as `zeroNotIn23`.
oneNotIn23 : Not (Elem (the Var 1) [2, 3])
oneNotIn23 (There (There el)) = absurd el

||| The two fragments use disjoint variable sets {0,1} and {2,3}. Built
||| compositionally with `consDisjoint` from the per-element refutations
||| `zeroNotIn23` / `oneNotIn23` and the vacuous `disjointNilLeft` — a genuine
||| witness, no assertion.
export
fragsDisjoint : Disjoint [0, 1] [2, 3]
fragsDisjoint =
  consDisjoint zeroNotIn23 (consDisjoint oneNotIn23 (disjointNilLeft [2, 3]))

||| POSITIVE CONTROL: composing the two disjoint affine fragments produces an
||| affine-safe trace [0,1,2,3] — built by the headline theorem, not by hand.
export
composedOk : AffineOk ([0, 1] ++ [2, 3])
composedOk = concatAffine [0, 1] fragsDisjoint fragLeftOk fragRightOk

--------------------------------------------------------------------------------
-- Negative control 1: overlapping fragments are NOT disjoint
--------------------------------------------------------------------------------

||| Fragments [0,1] and [1,2] share variable 1, so they are NOT disjoint.
||| Machine-checked refutation: any disjointness witness would have to refute
||| `Elem 1 [1,2]`, but 1 is `Here`.
export
overlapNotDisjoint : Not (Disjoint [0, 1] [1, 2])
overlapNotDisjoint dj = dj 1 (There Here) Here

||| And their concatenation [0,1,1,2] is genuinely unsafe: variable 1 occurs
||| twice. No `AffineOk` witness exists — the head-1 obligation would have to
||| refute `Elem 1 [1,2]`, which is `Here`.
export
overlapConcatNotAffine : Not (AffineOk ([0, 1] ++ [1, 2]))
overlapConcatNotAffine ok = headNotLater (tailOk ok) Here

--------------------------------------------------------------------------------
-- Negative control 2: a wide-gap double use is rejected
--------------------------------------------------------------------------------

||| A reuse separated by several distinct intervening uses is still caught:
||| variable 9 appears at the head and again after 4 other variables in
||| [9, 1, 2, 3, 4, 9]. Refuted because 9 reappears later in the tail.
export
wideGapDoubleUseNotAffine : Not (AffineOk [9, 1, 2, 3, 4, 9])
wideGapDoubleUseNotAffine ok =
  headNotLater ok (There (There (There (There Here))))
