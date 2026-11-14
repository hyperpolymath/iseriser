-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 — the ABI SOUNDNESS CERTIFICATE for Nimiser.
|||
||| This capstone proves nothing new. Instead it ASSEMBLES the four prior
||| proof layers of the Nimiser ABI into a single inhabited value, so that
||| "the whole ABI contract is discharged" becomes one typechecked fact:
|||
|||   * Layer 2 (flagship semantics) — `Semantics.samplePreserved`, the
|||     positive-control witness that the code generator's output for the
|||     canonical `proc add(a,b: int): int` provably PRESERVES the source
|||     signature (arity + per-argument/return Nim->C lowering).
|||   * Layer 3 (deeper invariant) — `Invariants.composedArgsWitness`, a
|||     concrete `ArgsLower` witness BUILT by composing two sub-witnesses
|||     through the distributivity/composition lemma (`argsLowerAppend`),
|||     i.e. the generator is a monoid homomorphism on argument lists.
|||   * Layer 3 (whole-signature injectivity) — `Invariants.genBindingInjective`,
|||     the theorem that distinct Nim signatures lower to distinct C bindings
|||     (no codegen-introduced symbol/ABI aliasing).
|||   * Layer 4 (FFI seam) — `FfiSeam.resultToIntInjective`, soundness of the
|||     ABI<->C `Result` encoding: distinct ABI outcomes never collide on the
|||     wire.
|||
||| The certificate threads the chain manifest -> ABI proofs (flagship +
||| invariant) -> FFI seam into one end-to-end soundness statement. The single
||| inhabited value `abiContractDischarged` cannot be constructed unless EVERY
||| referenced witness/theorem from the prior layers still typechecks; if any
||| earlier layer regressed into unsoundness, this module would fail to build.
||| That is the point of a capstone: one value that stands or falls with the
||| entire stack.

module Nimiser.ABI.Capstone

import Nimiser.ABI.Types
import Nimiser.ABI.Semantics
import Nimiser.ABI.Invariants
import Nimiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The certificate record
--------------------------------------------------------------------------------

||| `ABISound` bundles the key proven facts of the Nimiser ABI. Each field is a
||| genuine proof object reused verbatim from the layer that established it — no
||| field is re-proved here, and none can be faked. An inhabitant of this record
||| is exactly a certificate that all four layers hold simultaneously.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2 (flagship): the generated C binding for the canonical sample
  ||| signature provably preserves it (name + arity + per-type lowering).
  flagshipPreserved :
    SigPreserved Semantics.sampleNimSig Semantics.sampleCSig
  ||| Layer 3 (composition invariant): a concrete composed `ArgsLower` witness
  ||| for an extended argument list, demonstrating lowering is a homomorphism
  ||| over list concatenation.
  invariantComposed :
    ArgsLower (Invariants.baseSig.sigArgs ++ Invariants.extraArgs)
              [CIntT, CDoubleT, CCharStarT]
  ||| Layer 3 (whole-signature injectivity): distinct Nim signatures lower to
  ||| distinct C bindings — the generator introduces no ABI aliasing.
  bindingInjective :
    (s1, s2 : NimSig) -> genBinding s1 = genBinding s2 -> s1 = s2
  ||| Layer 4 (FFI seam): the ABI<->C `Result` encoding is injective, so
  ||| distinct ABI outcomes never collide on the wire.
  ffiSeamInjective :
    (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value
--------------------------------------------------------------------------------

||| THE CAPSTONE. A single inhabited `ABISound`, constructed entirely from the
||| existing exported witnesses/theorems of Layers 2-4. This value is the
||| end-to-end ABI soundness certificate for Nimiser: it typechecks iff the
||| flagship semantic property, the deeper composition invariant, whole-signature
||| injectivity, and the FFI-seam encoding soundness are ALL discharged together.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    Semantics.samplePreserved
    Invariants.composedArgsWitness
    Invariants.genBindingInjective
    FfiSeam.resultToIntInjective
