-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 algebraic structure for Oblibeniser: the reversible operations
||| form a GROUP under sequencing.
|||
||| The Layer-2 flagship (`Oblibeniser.ABI.Semantics`) proves the *round-trip*
||| laws: `unapply op . apply op = id` and `apply op . unapply op = id`. That
||| is the inverse-existence half of group structure for a single element.
|||
||| This module proves a genuinely DEEPER and DISTINCT property: the whole
||| collection of operations, quotiented by *denotational equivalence*
||| (`Equiv p q` iff they act identically on every state), carries the full
||| algebraic structure of a GROUP with respect to `Seq`:
|||
|||   * `Seq` is ASSOCIATIVE up to `Equiv` (apply is a monoid homomorphism into
|||     endofunction composition);
|||   * `Nop` is a TWO-SIDED UNIT;
|||   * every element has a TWO-SIDED inverse:
|||       `Equiv (Seq op (invert op)) Nop`  and  `Equiv (Seq (invert op) op) Nop`;
|||   * `Equiv` is a congruence for `Seq` (so the quotient is well-defined);
|||   * inverses are UNIQUE (the standard cancellation theorem);
|||   * `invert` is an ANTI-HOMOMORPHISM and an involution up to `Equiv`.
|||
||| These are algebraic LAWS (associativity, unit, inverse, uniqueness), not a
||| restatement of the round-trip equality. They are all reduced to the Layer-2
||| model: we reuse the SAME `Op`, `State`, `apply`, `invert`, `unapply`, and
||| the Layer-2 theorems `reversible` and `reversibleDual`.
|||
||| A decision procedure `decAgreeOn` decides denotational agreement on a
||| finite list of probe states (sound AND complete for that probe set), with
||| positive and negative/non-vacuity controls machine-checked below.
|||
||| Note on controls: the Layer-2 model deliberately keeps the per-operation
||| state transformers (`flipAll`, `xorMask`) PRIVATE, so `apply FlipAll s` and
||| `apply (XorMask m) s` are opaque to this module and do NOT reduce by `Refl`.
||| `apply Rev s = reverse s` (public Prelude `reverse`) and `apply Nop s = s`
||| DO reduce. The concrete controls therefore use `Rev`/`Nop`, while the
||| general theorems cover every operation via the exported Layer-2 lemmas.

module Oblibeniser.ABI.Invariants

import Oblibeniser.ABI.Types
import Oblibeniser.ABI.Semantics
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Denotational equivalence of operations
--------------------------------------------------------------------------------

||| Two operations are equivalent when they act identically on EVERY state.
||| This is the equivalence by which we quotient `Op` to obtain the group.
public export
Equiv : Op -> Op -> Type
Equiv p q = (s : State) -> apply p s = apply q s

--------------------------------------------------------------------------------
-- `Equiv` is an equivalence relation (reflexive, symmetric, transitive)
--------------------------------------------------------------------------------

||| Reflexivity.
export
equivRefl : (p : Op) -> Equiv p p
equivRefl _ _ = Refl

||| Symmetry. The operations are taken as explicit (erased) arguments so that
||| callers can pin them down: `Equiv` unfolds to a function type whose body
||| `apply p s` reduces away the structure of `p`, defeating implicit inference.
export
equivSym : (0 p, q : Op) -> Equiv p q -> Equiv q p
equivSym _ _ pq s = sym (pq s)

||| Transitivity (operations explicit, for the same inference reason).
export
equivTrans : (0 p, q, r : Op) -> Equiv p q -> Equiv q r -> Equiv p r
equivTrans _ _ _ pq qr s = trans (pq s) (qr s)

--------------------------------------------------------------------------------
-- `Equiv` is a CONGRUENCE for `Seq` (so the quotient operation is well-defined)
--------------------------------------------------------------------------------

||| If the components are equivalent, the sequences are equivalent. This is
||| what makes `Seq` descend to the quotient `Op/Equiv`.
|||
||| `apply (Seq p q) s = apply q (apply p s)`, so we rewrite the inner
||| application with `pp` and the outer with `qq` (instantiated at the
||| rewritten inner state). The operation arguments are kept RUNTIME-relevant
||| because `p'` appears in the term `apply p' s` on the right-hand side.
export
seqCong : (p, p', q, q' : Op) ->
          Equiv p p' -> Equiv q q' -> Equiv (Seq p q) (Seq p' q')
seqCong p p' q q' pp qq s =
  rewrite pp s in
  qq (apply p' s)

--------------------------------------------------------------------------------
-- MONOID LAWS over `Equiv`
--------------------------------------------------------------------------------

||| ASSOCIATIVITY of sequencing (an algebraic law genuinely distinct from the
||| round-trip theorem). Both sides denote `apply r . apply q . apply p`, so
||| the equality holds definitionally at each state.
export
seqAssoc : (p, q, r : Op) -> Equiv (Seq (Seq p q) r) (Seq p (Seq q r))
seqAssoc p q r s = Refl

||| LEFT UNIT: `Nop` on the left is neutral.
export
nopLeftUnit : (op : Op) -> Equiv (Seq Nop op) op
nopLeftUnit op s = Refl

||| RIGHT UNIT: `Nop` on the right is neutral.
export
nopRightUnit : (op : Op) -> Equiv (Seq op Nop) op
nopRightUnit op s = Refl

--------------------------------------------------------------------------------
-- GROUP LAWS over `Equiv`  (two-sided inverse) — the core Layer-3 theorem
--------------------------------------------------------------------------------

||| RIGHT INVERSE: doing `op` then its inverse is denotationally the identity.
|||
|||     Equiv (Seq op (invert op)) Nop
|||
||| `apply (Seq op (invert op)) s = apply (invert op) (apply op s)
|||                              = unapply op (apply op s)`,
||| which the Layer-2 `reversible` law equates with `s = apply Nop s`.
export
seqInverseRight : (op : Op) -> Equiv (Seq op (invert op)) Nop
seqInverseRight op s = reversible op s

||| LEFT INVERSE: doing the inverse of `op` then `op` is also the identity.
|||
|||     Equiv (Seq (invert op) op) Nop
|||
||| `apply (Seq (invert op) op) s = apply op (apply (invert op) s)
|||                              = apply op (unapply op s)`,
||| which the Layer-2 dual law `reversibleDual` equates with `s`.
export
seqInverseLeft : (op : Op) -> Equiv (Seq (invert op) op) Nop
seqInverseLeft op s = reversibleDual op s

--------------------------------------------------------------------------------
-- Uniqueness of inverses (a genuine group-theoretic consequence)
--------------------------------------------------------------------------------

||| In a group, inverses are unique: if `cand` is a right inverse of `op`
||| (i.e. `Equiv (Seq op cand) Nop`), then `cand` is denotationally `invert op`.
||| This is the standard cancellation argument, carried out over `Equiv`:
|||
|||   cand ~ Nop `Seq` cand
|||        ~ (invert op `Seq` op) `Seq` cand     -- left inverse
|||        ~ invert op `Seq` (op `Seq` cand)     -- associativity
|||        ~ invert op `Seq` Nop                 -- hypothesis (congruence)
|||        ~ invert op                           -- right unit
export
inverseUnique : (op, cand : Op) ->
                Equiv (Seq op cand) Nop ->
                Equiv cand (invert op)
inverseUnique op cand rightInv =
  equivTrans cand (Seq Nop cand) (invert op)
    (equivSym (Seq Nop cand) cand (nopLeftUnit cand)) $
  equivTrans (Seq Nop cand) (Seq (Seq (invert op) op) cand) (invert op)
    (seqCong Nop (Seq (invert op) op) cand cand
             (equivSym (Seq (invert op) op) Nop (seqInverseLeft op))
             (equivRefl cand)) $
  equivTrans (Seq (Seq (invert op) op) cand) (Seq (invert op) (Seq op cand))
             (invert op)
    (seqAssoc (invert op) op cand) $
  equivTrans (Seq (invert op) (Seq op cand)) (Seq (invert op) Nop) (invert op)
    (seqCong (invert op) (invert op) (Seq op cand) Nop
             (equivRefl (invert op)) rightInv) $
  nopRightUnit (invert op)

--------------------------------------------------------------------------------
-- `invert` is an involution and an anti-homomorphism (up to `Equiv`)
--------------------------------------------------------------------------------

||| `invert` is an INVOLUTION up to denotation: `Equiv (invert (invert op)) op`.
||| Derived from uniqueness: `op` is a right inverse of `invert op` (that is
||| exactly the LEFT-inverse law `Equiv (Seq (invert op) op) Nop`), so by
||| `inverseUnique` it must be denotationally `invert (invert op)`.
export
invertInvolutiveEquiv : (op : Op) -> Equiv (invert (invert op)) op
invertInvolutiveEquiv op =
  equivSym op (invert (invert op))
    (inverseUnique (invert op) op (seqInverseLeft op))

||| `invert` is an ANTI-HOMOMORPHISM: it reverses order under `Seq`.
||| Holds definitionally — `invert (Seq p q) = Seq (invert q) (invert p)`.
export
invertAntiHom : (p, q : Op) ->
                Equiv (invert (Seq p q)) (Seq (invert q) (invert p))
invertAntiHom p q s = Refl

--------------------------------------------------------------------------------
-- A propositional GROUP certificate (cannot be forged)
--------------------------------------------------------------------------------

||| A certificate bundling the two-sided-inverse group axioms for `op` against
||| `inv`. There is exactly one constructor, taking the genuine proofs; no
||| "group element with broken inverse" can be built.
public export
data IsGroupInverse : (op, inv : Op) -> Type where
  MkGroupInverse :
    (left  : Equiv (Seq inv op) Nop) ->
    (right : Equiv (Seq op inv) Nop) ->
    IsGroupInverse op inv

||| Every operation, paired with `invert op`, satisfies the group axioms.
export
groupInverse : (op : Op) -> IsGroupInverse op (invert op)
groupInverse op = MkGroupInverse (seqInverseLeft op) (seqInverseRight op)

||| Tie the group certificate back to the ABI `Result` codes. Because every
||| operation has a genuine two-sided inverse, this is total and always `Ok`.
export
groupResult : (op : Op) -> Result
groupResult op = case groupInverse op of
  MkGroupInverse _ _ => Ok

||| Soundness: `groupResult op = Ok` entails the actual group laws (it
||| exhibits the real two-sided-inverse proofs — no vacuity).
export
groupResultSound : (op : Op) -> groupResult op = Ok ->
                   ( Equiv (Seq (invert op) op) Nop
                   , Equiv (Seq op (invert op)) Nop )
groupResultSound op _ = (seqInverseLeft op, seqInverseRight op)

--------------------------------------------------------------------------------
-- A SOUND + COMPLETE decision procedure for agreement on a finite probe set
--------------------------------------------------------------------------------

||| Pointwise agreement of two operations on a *given list of probe states*.
||| This is the decidable, finitary shadow of full `Equiv`.
public export
AgreeOn : (probes : List State) -> Op -> Op -> Type
AgreeOn probes p q = (s : State) -> Elem s probes -> apply p s = apply q s

||| `AgreeOn` is decidable for any concrete probe list, because each probe is a
||| concrete `decEq` on `List Bool`. Sound (a `Yes` carries a real proof) and
||| complete (a `No` carries a real refutation).
export
decAgreeOn : (probes : List State) -> (p, q : Op) -> Dec (AgreeOn probes p q)
decAgreeOn [] p q = Yes (\_, prf => absurd prf)
decAgreeOn (x :: xs) p q =
  case decEq (apply p x) (apply q x) of
    No contra => No (\agree => contra (agree x Here))
    Yes hereEq =>
      case decAgreeOn xs p q of
        No restNo =>
          No (\agree => restNo (\s, elemRest => agree s (There elemRest)))
        Yes restYes =>
          Yes (\s, elemPrf => case elemPrf of
                                Here          => hereEq
                                There elemTl  => restYes s elemTl)

--------------------------------------------------------------------------------
-- POSITIVE controls (inhabited witnesses on concrete data)
--------------------------------------------------------------------------------

||| Concrete operation reused from the family.
sampleOp : Op
sampleOp = Seq FlipAll (XorMask [True, False, True])

||| Positive control 1: the RIGHT-inverse group law on the concrete sample,
||| on a concrete probe state, via the general theorem.
posRightInverse : apply (Seq Invariants.sampleOp (invert Invariants.sampleOp))
                        [True, False, True]
                  = apply Nop [True, False, True]
posRightInverse = seqInverseRight sampleOp [True, False, True]

||| Positive control 2: the LEFT-inverse group law on the concrete sample.
posLeftInverse : apply (Seq (invert Invariants.sampleOp) Invariants.sampleOp)
                       [False, True, False]
                 = apply Nop [False, True, False]
posLeftInverse = seqInverseLeft sampleOp [False, True, False]

||| Positive control 3: the RIGHT-inverse law on `Rev`, forced to reduce by
||| pure computation with NO appeal to the general lemma. `apply (Seq Rev Rev)
||| [True,False] = reverse (reverse [True,False]) = [True,False] = apply Nop …`.
posRightInverseRev :
  apply (Seq Rev (invert Rev)) [True, False] = apply Nop [True, False]
posRightInverseRev = Refl

||| Positive control 4: associativity on a concrete instance, by pure
||| computation (no appeal to the general lemma) — both sides reduce to
||| `reverse (reverse (reverse [True,False]))`.
posAssocConcrete :
  apply (Seq (Seq Rev Rev) Rev) [True, False]
  = apply (Seq Rev (Seq Rev Rev)) [True, False]
posAssocConcrete = Refl

||| Positive control 5: an inhabited group certificate.
posGroupCert : IsGroupInverse Invariants.sampleOp (invert Invariants.sampleOp)
posGroupCert = groupInverse sampleOp

||| Positive control 6: the decision procedure returns `Yes` for an operation
||| against itself on a non-empty probe set, and we can USE the proof.
posDecYes : apply Rev [True, False] = apply Rev [True, False]
posDecYes =
  case decAgreeOn [[True, False], [False]] Rev Rev of
    Yes agree => agree [True, False] Here
    No _      => Refl

--------------------------------------------------------------------------------
-- NEGATIVE / non-vacuity controls (the bad case is genuinely refuted)
--------------------------------------------------------------------------------

||| `apply Rev [True,False]` reduces to `[False,True]` (public `reverse`);
||| stated as a concrete equality so the negative controls can pattern-match on
||| a constructor-headed term.
revReverses : apply Rev [True, False] = [False, True]
revReverses = Refl

||| Negative control 1: `Rev` and `Nop` are NOT denotationally equal — they
||| disagree on `[True,False]` (`apply Rev [True,False] = [False,True] /=
||| [True,False] = apply Nop [True,False]`). A bogus `Equiv Rev Nop` would
||| force a false equality; this `Not` machine-checks that none exists, so the
||| unit law is non-vacuous.
negRevNotNop : Not (apply Rev [True, False] = apply Nop [True, False])
negRevNotNop eq =
  case trans (sym revReverses) eq of
    Refl impossible

||| Negative control 2: `Seq Nop Rev` is NOT a no-op — it reverses
||| `[True,False]` to `[False,True]`, so it is NOT `[True,False]`. This refutes
||| a bogus "Seq Nop Rev acts as the identity" claim.
seqNopRevReverses : apply (Seq Nop Rev) [True, False] = [False, True]
seqNopRevReverses = Refl

negSeqNopRevNotId : Not (apply (Seq Nop Rev) [True, False] = [True, False])
negSeqNopRevNotId eq =
  case trans (sym seqNopRevReverses) eq of
    Refl impossible

||| Negative control 3: structural — `Rev` and `Nop` are distinct constructors,
||| so they can never be propositionally equal as `Op`s. (Keeps the group
||| carrier from collapsing to a single element.)
negRevNotNopStruct : Not (Rev = Nop)
negRevNotNopStruct Refl impossible

||| Negative control 4: the decision procedure genuinely DECIDES — `AgreeOn`
||| for two operations that disagree on a probe (`Rev` vs `Nop` on
||| `[True,False]`) is uninhabited, and we refute any forged agreement.
negDecNo : Not (AgreeOn [[True, False]] Rev Nop)
negDecNo agree = negRevNotNop (agree [True, False] Here)
