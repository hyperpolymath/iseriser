-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-5 CAPSTONE: the end-to-end ABI SOUNDNESS CERTIFICATE for iseriser.
|||
||| This module proves NO new domain theorem. Its sole job is to ASSEMBLE the
||| already-discharged proof layers into ONE inhabited value, so that the full
||| ABI contract is shown to hold *together*. The certificate ties the chain:
|||
|||   manifest/doctrine model  (Types: Component, Scaffold, Result)
|||     -> Layer-2 flagship     (Semantics.completeIsConformant — the canonical
|||                              positive control: the complete five-component
|||                              scaffold IS Conformant)
|||     -> Layer-3 invariant    (Invariants.extendedGeneratedConformant — the
|||                              upward-closure / monotonicity witness: a
|||                              generated-then-extended scaffold stays Conformant)
|||     -> Layer-4 FFI seam     (FfiSeam.resultToIntInjective — distinct ABI
|||                              outcomes never collide on the C wire)
|||
||| into a single end-to-end soundness statement. `abiContractDischarged` is the
||| capstone value: it is constructed ENTIRELY from the existing exported
||| witnesses/theorems of the prior layers. If ANY prior layer were unsound,
||| this value would not typecheck. There is no fresh proof obligation here —
||| only genuine composition.

module Iseriser.ABI.Capstone

import Iseriser.ABI.Types
import Iseriser.ABI.Semantics
import Iseriser.ABI.Invariants
import Iseriser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate
--------------------------------------------------------------------------------

||| `ABISound` bundles the KEY proven facts of the iseriser ABI into one record.
||| Each field is the TYPE of an already-proven theorem from a prior layer; the
||| only way to inhabit the record is to supply those real witnesses.
|||
|||   * `flagship`  : the Layer-2 flagship property holds on the canonical
|||                   positive-control instance (`Semantics.completeScaffold` is
|||                   `Conformant`).
|||   * `invariant` : the Layer-3 deeper invariant holds — conformance is
|||                   upward-closed under extension, witnessed on the generated
|||                   scaffold extended by one component.
|||   * `ffiInjective` : the Layer-4 FFI-seam guarantee — `resultToInt` is
|||                   injective, so distinct ABI outcomes never collide on the
|||                   wire. Stored as the full injectivity statement.
public export
record ABISound where
  constructor MkABISound
  flagship     : Conformant Semantics.completeScaffold
  invariant    : Conformant (extend [Manifest] Invariants.generatedScaffold)
  ffiInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

||| THE CAPSTONE. A single inhabited value assembled purely from the existing
||| exported witnesses of Layers 2-4. Its mere existence certifies that the
||| flagship property, the deeper invariant, and the FFI-seam injectivity are
||| ALL simultaneously discharged for this ABI — manifest model -> ABI proofs
||| -> FFI seam, sealed end to end.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    completeIsConformant            -- Layer-2 flagship positive control
    extendedGeneratedConformant     -- Layer-3 upward-closure invariant witness
    resultToIntInjective            -- Layer-4 FFI-seam injectivity
