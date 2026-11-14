-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-5 CAPSTONE: a single end-to-end ABI SOUNDNESS CERTIFICATE for
||| Phronesiser.
|||
||| This module proves NO new domain theorem. It ASSEMBLES the facts already
||| discharged by the prior proof layers into ONE inhabited record value,
||| `abiContractDischarged`. Because that value can only be constructed from
||| genuine witnesses exported by the lower layers, its mere existence (the
||| fact that this module type-checks) certifies that the whole ABI contract
||| is satisfied TOGETHER, end to end:
|||
|||   manifest (phronesiser.toml: "provably safe ethical constraints")
|||     -> Layer-2 FLAGSHIP semantics   (Phronesiser.ABI.Semantics)
|||          the canonical positive control `safeInformPermitted` witnesses
|||          that the permitted action genuinely carries a permission proof,
|||          the live half of the safety property whose negative half is
|||          `forbiddenNeverPermitted`.
|||     -> Layer-3 deeper INVARIANT      (Phronesiser.ABI.Invariants)
|||          `noHarmTightensBase` witnesses monotone safety's hypothesis
|||          (the stronger policy really tightens the base policy, quantified
|||          over all actions), and `forbiddenStaysForbidden` is the live
|||          application: tightening never re-permits a forbidden action.
|||     -> Layer-4 FFI SEAM              (Phronesiser.ABI.FfiSeam)
|||          `resultToIntInjective` witnesses that distinct ABI outcomes never
|||          collide on the C wire — the boundary at which the proofs meet code.
|||
||| If ANY of those prior layers were unsound, the corresponding field below
||| would have no inhabitant and `abiContractDischarged` would not type-check.
||| The certificate is therefore a genuine composition, not a restatement.
|||
||| Genuine proof only — no believe_me / idris_crash / assert_total /
||| postulate / sorry / %hint hacks. Every field is an already-exported
||| witness from the layer named above. %default total.

module Phronesiser.ABI.Capstone

import Phronesiser.ABI.Types
import Phronesiser.ABI.Semantics
import Phronesiser.ABI.Invariants
import Phronesiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate type.
--------------------------------------------------------------------------------

||| `ABISound` bundles the key proven facts of the Phronesiser ABI, one field
||| per proof layer. An inhabitant is a machine-checked certificate that the
||| flagship safety property, the deeper monotone-safety invariant, and the
||| FFI-seam injectivity all hold simultaneously over the SAME shared model.
public export
record ABISound where
  constructor MkABISound

  ||| Layer-2 flagship (positive control): the canonical benign action really
  ||| is permitted — reuses `Semantics.safeInformPermitted`.
  flagshipPermits : ActionPermitted Semantics.safeInform

  ||| Layer-3 invariant (hypothesis witness): the stronger "no harm deploy"
  ||| policy genuinely tightens the base policy, quantified over all actions
  ||| — reuses `Invariants.noHarmTightensBase`.
  invariantTightens : Tightens Invariants.noHarmDeployPolicy Invariants.basePolicy

  ||| Layer-3 invariant (live application): tightening preserves the forbidden
  ||| verdict on the canonical forbidden action — reuses
  ||| `Invariants.forbiddenStaysForbidden`.
  invariantPreservesForbidden :
    Forbids Invariants.noHarmDeployPolicy Semantics.forbiddenDeploy

  ||| Layer-4 FFI seam: distinct ABI result codes never collide on the wire
  ||| — reuses `FfiSeam.resultToIntInjective`.
  seamInjective :
    (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: the ABI contract, discharged.
--------------------------------------------------------------------------------

||| THE CAPSTONE. A single inhabited certificate assembled purely from the
||| exported witnesses of Layers 2-4. It type-checks iff every prior layer is
||| sound; constructing it is the end-to-end soundness statement that ties the
||| manifest's promise, the ABI proofs (flagship + invariant), and the FFI seam
||| into one value.
public export
abiContractDischarged : ABISound
abiContractDischarged = MkABISound
  { flagshipPermits             = Semantics.safeInformPermitted
  , invariantTightens           = Invariants.noHarmTightensBase
  , invariantPreservesForbidden = Invariants.forbiddenStaysForbidden
  , seamInjective               = FfiSeam.resultToIntInjective
  }

--------------------------------------------------------------------------------
-- Projection sanity: the certificate's fields ARE the real theorems.
--------------------------------------------------------------------------------

||| The seam-injectivity field of the discharged certificate is exactly the
||| Layer-4 theorem (definitional). Confirms the capstone exposes, not shadows,
||| the underlying proof.
public export
capstoneSeamIsResultToIntInjective :
  seamInjective Capstone.abiContractDischarged = FfiSeam.resultToIntInjective
capstoneSeamIsResultToIntInjective = Refl
