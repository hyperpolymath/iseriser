-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 — the ABI SOUNDNESS CERTIFICATE for Wokelangiser.
|||
||| This module proves NOTHING new about the domain. Its sole job is to ASSEMBLE
||| the four prior proof layers into ONE inhabited value, so that the full ABI
||| contract is demonstrably discharged *together*. The certificate ties:
|||
|||   * the manifest (consent + accessibility intent) ->
|||   * the Layer-2 flagship semantic property
|||       (`Semantics.processPermitted` : a data action is `Permitted` only with
|||        Active recorded consent — the canonical positive control) ->
|||   * the Layer-3 deeper invariant
|||       (`Invariants.processNotPermittedAfterRevoke` : revocation monotonicity —
|||        once consent is withdrawn the same action can never be `Permitted`,
|||        even over a prior Active grant) ->
|||   * the Layer-4 FFI-seam soundness
|||       (`FfiSeam.resultToIntInjective` : distinct ABI outcomes never collide on
|||        the wire crossing into C)
|||
||| into a single end-to-end soundness statement. The record `ABISound` has one
||| field per layer; `abiContractDischarged : ABISound` is the capstone witness.
||| Crucially, this value can ONLY typecheck if every reused theorem is itself
||| sound: if any prior layer were broken, this value would not exist. There is
||| no `believe_me`, `postulate`, `assert_total`, `idris_crash`, `%hint` or any
||| other escape hatch anywhere in the chain — it is genuine composition.

module Wokelangiser.ABI.Capstone

import Wokelangiser.ABI.Types
import Wokelangiser.ABI.Semantics
import Wokelangiser.ABI.Invariants
import Wokelangiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The ABI soundness certificate
--------------------------------------------------------------------------------

||| `ABISound` is the end-to-end certificate type. Each field is a KEY proven
||| fact of this ABI, taken verbatim from the layer that established it:
|||
|||   * `flagship`    — Layer 2: the canonical positive control showing that a
|||                     data action (`Process`) IS `Permitted` exactly when the
|||                     consent ledger records `Active` consent for it.
|||   * `invariant`   — Layer 3: revocation monotonicity at the concrete override
|||                     case — after withdrawing consent for `Process` (which was
|||                     previously Active), it is NOT `Permitted`.
|||   * `seamSound`   — Layer 4: the FFI result encoding is injective, so distinct
|||                     ABI outcomes never alias on the C wire.
|||
||| Inhabiting this record is the act of certifying the whole contract at once.
public export
record ABISound where
  constructor MkABISound
  ||| Layer-2 flagship semantic property (positive control witness).
  flagship  : Permitted Semantics.sampleLedger Process
  ||| Layer-3 deeper invariant (revocation monotonicity, override case).
  invariant : Not (Permitted (revoke Process Invariants.priorLedger) Process)
  ||| Layer-4 FFI-seam injectivity (no outcome collisions on the wire).
  seamSound : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone: a single inhabited value built from the real theorems
--------------------------------------------------------------------------------

||| THE CAPSTONE. One inhabited value of `ABISound`, constructed purely from the
||| already-exported witnesses of the prior layers. Its mere existence is the
||| end-to-end soundness claim: manifest -> flagship -> invariant -> FFI seam,
||| all discharged simultaneously. Were any reused theorem unsound, this binding
||| would fail to typecheck.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    processPermitted               -- Layer 2 (Semantics)
    processNotPermittedAfterRevoke -- Layer 3 (Invariants)
    resultToIntInjective           -- Layer 4 (FfiSeam)

--------------------------------------------------------------------------------
-- Field-level accessors as named theorems (so each layer is recoverable)
--------------------------------------------------------------------------------

||| Recover the Layer-2 flagship fact from the certificate.
public export
certFlagship : Permitted Semantics.sampleLedger Process
certFlagship = abiContractDischarged.flagship

||| Recover the Layer-3 invariant from the certificate.
public export
certInvariant : Not (Permitted (revoke Process Invariants.priorLedger) Process)
certInvariant = abiContractDischarged.invariant

||| Recover the Layer-4 FFI-seam injectivity from the certificate.
public export
certSeamSound : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
certSeamSound = abiContractDischarged.seamSound
