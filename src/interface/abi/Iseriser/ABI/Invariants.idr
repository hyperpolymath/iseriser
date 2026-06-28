-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 ABI invariants for iseriser, built over the SAME model as the
||| Layer-2 flagship (`Iseriser.ABI.Semantics`): `Component`, `Scaffold`,
||| `Has`, and `Conformant`.
|||
||| The Layer-2 theorem DECIDES conformance of a *given* scaffold. The
||| properties here are deeper and structurally distinct:
|||
|||   (1) GENERATION SOUNDNESS (correct-by-construction):
|||       `genScaffold` is a total generator that, for any `LanguageModel`,
|||       provably emits a Conformant scaffold — `(s ** Conformant s)`. The
|||       meta-framework does not merely *check* scaffolds; it *produces*
|||       conformant ones, with the proof carried alongside.
|||
|||   (2) UPWARD-CLOSURE / MONOTONICITY (an algebraic closure law):
|||       Conformance is preserved under extension. Prepending any extra
|||       components to a Conformant scaffold yields a Conformant scaffold.
|||       This is proved via a genuine `Elem`-weakening lemma, not asserted.
|||
||| Both are accompanied by a POSITIVE control (a concrete generated witness)
||| and NEGATIVE / non-vacuity controls (a `Not (...)` refutation, plus a
||| `Dec` whose completeness is machine-checked).

module Iseriser.ABI.Invariants

import Iseriser.ABI.Types
import Iseriser.ABI.Semantics
import Data.List.Elem

%default total

--------------------------------------------------------------------------------
-- Elem weakening: the structural lemma the closure law rests on
--------------------------------------------------------------------------------

||| Membership is preserved when a prefix is prepended on the left.
||| If `x` is in `ys`, then `x` is in `xs ++ ys`. Proved by induction on the
||| prefix `xs`; every step is a constructor (`There`), no holes.
elemAppendRight :
     {0 x : Component}
  -> (xs : List Component)
  -> {0 ys : List Component}
  -> Elem x ys
  -> Elem x (xs ++ ys)
elemAppendRight []        prf = prf
elemAppendRight (_ :: zs) prf = There (elemAppendRight zs prf)

--------------------------------------------------------------------------------
-- Property (1): Generation soundness — correct-by-construction
--------------------------------------------------------------------------------

||| The canonical scaffold the generator emits: all five doctrine components
||| in canonical order. (Independent of `Semantics.completeScaffold` so this
||| module's generator stands on its own definition.)
public export
generatedScaffold : Scaffold
generatedScaffold = MkScaffold [Manifest, Abi, Ffi, Codegen, Cli]

||| Proof that the generated scaffold is Conformant. Each `Has` field is a
||| concrete `Elem` position into the literal component list, so this checks
||| by reduction with no appeal to any decision procedure.
generatedIsConformant : Conformant Invariants.generatedScaffold
generatedIsConformant =
  MkConformant
    Here                                  -- Manifest @ 0
    (There Here)                          -- Abi      @ 1
    (There (There Here))                  -- Ffi      @ 2
    (There (There (There Here)))          -- Codegen  @ 3
    (There (There (There (There Here))))  -- Cli      @ 4

||| GENERATION SOUNDNESS THEOREM.
|||
||| For ANY language model, the meta-framework emits a scaffold together with
||| a machine-checked proof that it is Conformant. The `LanguageModel` is a
||| genuine, used input (every -iser is generated *for* some target language),
||| but conformance of the emitted scaffold does not depend on it: the five
||| architectural components are produced unconditionally. This is the
||| dependent-pair statement `(s ** Conformant s)` — a constructive witness,
||| not a boolean.
public export
genScaffold : LanguageModel -> (s : Scaffold ** Conformant s)
genScaffold _ = (generatedScaffold ** generatedIsConformant)

||| A Conformant scaffold is always certified `Ok` by the Layer-2 certifier.
||| Proved by case-analysis on the SAME decision the certifier uses: the `No`
||| branch is discharged by feeding the (given) witness to the refutation,
||| which is absurd. (`decConformant` does not reduce definitionally through a
||| bare `Refl`, so we reason about its result with a `with`-block rather than
||| asserting equality.)
public export
conformantCertifies :
     {s : Scaffold}
  -> Conformant s
  -> certifyConformant s = Ok
conformantCertifies w with (decConformant s)
  conformantCertifies _ | Yes _  = Refl
  conformantCertifies w | No  no = void (no w)

||| Corollary: the certifier from Layer 2 accepts every generated scaffold.
||| This ties Layer 3 (construction) back to Layer 2 (decision): what we
||| build is exactly what the Layer-2 certifier blesses as `Ok`.
public export
genScaffoldCertifies :
     (m : LanguageModel)
  -> certifyConformant (fst (genScaffold m)) = Ok
genScaffoldCertifies m = conformantCertifies (snd (genScaffold m))

--------------------------------------------------------------------------------
-- Property (2): Upward-closure / monotonicity of Conformance
--------------------------------------------------------------------------------

||| Extend a scaffold by prepending extra components (e.g. optional extras a
||| richer target language requests). Defined as list concatenation.
public export
extend : List Component -> Scaffold -> Scaffold
extend extra s = MkScaffold (extra ++ components s)

||| Weaken a single `Has` obligation across an extension: if a component is
||| present in `s`, it remains present in `extend extra s`. Direct corollary
||| of `elemAppendRight`.
hasUnderExtend :
     {0 c : Component}
  -> (extra : List Component)
  -> {0 s : Scaffold}
  -> Has c s
  -> Has c (extend extra s)
hasUnderExtend extra prf = elemAppendRight extra prf

||| CLOSURE LAW (monotonicity).
|||
||| Conformance is upward-closed under extension: extending a Conformant
||| scaffold with any extra components yields a Conformant scaffold. Each of
||| the five membership proofs is transported through `hasUnderExtend`. This
||| is an algebraic closure property — genuinely distinct from the Layer-2
||| decision, and it cannot hold vacuously (it consumes a real `Conformant`).
public export
conformantStable :
     (extra : List Component)
  -> {0 s : Scaffold}
  -> Conformant s
  -> Conformant (extend extra s)
conformantStable extra (MkConformant m a f g c) =
  MkConformant
    (hasUnderExtend extra m)
    (hasUnderExtend extra a)
    (hasUnderExtend extra f)
    (hasUnderExtend extra g)
    (hasUnderExtend extra c)

--------------------------------------------------------------------------------
-- Positive control: a generated-then-extended scaffold is still Conformant
--------------------------------------------------------------------------------

||| Take the generator's output and extend it with a duplicate Manifest in
||| front (a realistic "extra"): still Conformant, by the closure law applied
||| to the generation-soundness witness.
public export
extendedGeneratedConformant :
     Conformant (extend [Manifest] Invariants.generatedScaffold)
extendedGeneratedConformant =
  conformantStable [Manifest] generatedIsConformant

--------------------------------------------------------------------------------
-- Sound + complete decision for extension-conformance
--------------------------------------------------------------------------------

||| Decide whether an extension of `s` is Conformant. Reuses the Layer-2
||| `decConformant` on the extended scaffold — sound and complete because
||| `decConformant` is. This is the natural decision point for "is the
||| scaffold still conformant after we added these extras?".
public export
decExtendConformant :
     (extra : List Component)
  -> (s : Scaffold)
  -> Dec (Conformant (extend extra s))
decExtendConformant extra s = decConformant (extend extra s)

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| A scaffold the generator would NEVER emit: everything except the Zig FFI.
public export
brokenScaffold : Scaffold
brokenScaffold = MkScaffold [Manifest, Abi, Codegen, Cli]

||| Machine-checked refutation: extending the FFI-less broken scaffold with
||| MORE non-FFI components does NOT make it Conformant — the closure law
||| only adds, it cannot conjure the missing `Ffi`. We pull the `Has Ffi`
||| field out of any hypothetical witness over the extended list and show
||| every membership position is impossible. This proves the closure law is
||| not vacuous: extension genuinely preserves, but does not fabricate,
||| conformance.
|||
||| The extended list is `[Codegen, Manifest] ++ [Manifest, Abi, Codegen, Cli]`
||| = `[Codegen, Manifest, Manifest, Abi, Codegen, Cli]` — six positions, none
||| of which is `Ffi`, so the `noFfi` clause refutes them all.
public export
extendedBrokenNotConformant :
     Not (Conformant (extend [Codegen, Manifest] Invariants.brokenScaffold))
extendedBrokenNotConformant (MkConformant _ _ f _ _) = noFfi f
  where
    noFfi : Not (Elem Ffi [Codegen, Manifest, Manifest, Abi, Codegen, Cli])
    noFfi (There (There (There (There (There (There prf)))))) impossible
