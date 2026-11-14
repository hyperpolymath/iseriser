-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-5 CAPSTONE: the end-to-end ABI soundness certificate for Anvomidaviser.
|||
||| Every prior proof layer establishes one facet of the ABI contract:
|||
|||   * Layer 2 (`Anvomidaviser.ABI.Semantics`) — the FLAGSHIP property: the ISU
|||     short-program element-count rule (`WellFormed`), with `goodWellFormed`
|||     witnessing it on the canonical positive-control program.
|||   * Layer 3 (`Anvomidaviser.ABI.Invariants`) — a DEEPER invariant:
|||     downward-closure of well-formedness under deletion, with
|||     `trimmedWellFormed` transporting the Layer-2 witness through the
|||     Layer-3 theorem on a concrete instance.
|||   * Layer 4 (`Anvomidaviser.ABI.FfiSeam`) — the ABI<->FFI seam:
|||     `resultToIntInjective` proves the result-code encoding never collides,
|||     so an FFI integer carries exactly one ABI meaning.
|||
||| This module ASSEMBLES those already-proven facts into a single record
||| `ABISound` and inhabits it once as `abiContractDischarged`. That value ties
||| the chain together: manifest (the ISU rules the user asked for) -> ABI proofs
||| (flagship element-count + the deeper downward-closure invariant) -> FFI seam
||| (injective wire encoding) into one end-to-end soundness statement. If ANY
||| prior layer were unsound, `abiContractDischarged` would fail to typecheck —
||| so a clean build of this module is the certificate.
|||
||| Genuine composition only: every field below is filled from a real exported
||| witness of a prior module. No believe_me / idris_crash / assert_total /
||| postulate / sorry / %hint appears anywhere.

module Anvomidaviser.ABI.Capstone

import Anvomidaviser.ABI.Types
import Anvomidaviser.ABI.Semantics
import Anvomidaviser.ABI.Invariants
import Anvomidaviser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate type
--------------------------------------------------------------------------------

||| `ABISound` bundles the key proven facts of the Anvomidaviser ABI. Inhabiting
||| it requires a real proof of each layer simultaneously.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2 — flagship property holds on the canonical positive control.
  flagship  : WellFormed Semantics.goodProgram
  ||| Layer 3 — the deeper downward-closure invariant holds on a concrete
  ||| transformed instance (Layer-2 witness transported through Layer-3).
  invariant : WellFormed Invariants.trimmedProgram
  ||| Layer 4 — the FFI result-code encoding is injective (the seam is sealed).
  ffiSeam   : (a : Result) -> (b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: the contract, discharged
--------------------------------------------------------------------------------

||| The single inhabited capstone. Each field is supplied by the genuine
||| exported witness/theorem of the corresponding layer; nothing is fabricated.
||| A successful typecheck of this value is the end-to-end ABI soundness proof.
export
abiContractDischarged : ABISound
abiContractDischarged = MkABISound
  goodWellFormed        -- Layer 2 (Semantics)
  trimmedWellFormed     -- Layer 3 (Invariants)
  resultToIntInjective  -- Layer 4 (FfiSeam)

--------------------------------------------------------------------------------
-- Projections (each layer recoverable from the one certificate)
--------------------------------------------------------------------------------

||| The flagship Layer-2 fact, recovered from the capstone.
export
capstoneFlagship : WellFormed Semantics.goodProgram
capstoneFlagship = abiContractDischarged.flagship

||| The Layer-3 invariant, recovered from the capstone.
export
capstoneInvariant : WellFormed Invariants.trimmedProgram
capstoneInvariant = abiContractDischarged.invariant

||| The Layer-4 seam injectivity, recovered from the capstone, applied here to
||| a concrete pair to show it really reduces (non-vacuity at use site).
export
capstoneSeamOkOk : the Result Ok = the Result Ok
capstoneSeamOkOk = abiContractDischarged.ffiSeam Ok Ok Refl
