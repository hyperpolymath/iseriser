-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 — the CAPSTONE ABI SOUNDNESS CERTIFICATE for halideiser.
|||
||| Every prior layer proves one slice of the ABI contract in isolation:
|||
|||   * Layer 2 (`Halideiser.ABI.Semantics`) — the FLAGSHIP semantic property:
|||     a loop SPLIT schedule computes exactly what the flat run computes
|||     (`SplitEquivalent`), with the canonical positive control
|||     `doubleSplit3x4Equivalent`.
|||   * Layer 3 (`Halideiser.ABI.Invariants`) — the DEEPER invariant: schedule
|||     equivalence is a genuine equivalence relation, and TILING (split of an
|||     outer split) preserves the result by transitive composition, witnessed
|||     on the canonical positive control `doubleTile2x3x2Equivalent`.
|||   * Layer 4 (`Halideiser.ABI.FfiSeam`) — the FFI SEAM: the on-the-wire
|||     `resultToInt` encoding is INJECTIVE (`resultToIntInjective`), so the
|||     ABI's `Result` values never collide on their C integer codes.
|||
||| This module ties those three together into ONE inhabited value. The record
||| `ABISound` has one field per layer, each typed as the EXACT proven fact
||| exported by that layer. `abiContractDischarged : ABISound` is constructed
||| solely from the existing exported witnesses/theorems — no new domain
||| theorem is proved here. If ANY prior layer were unsound (its witness
||| missing or its theorem ill-typed), this single value would fail to
||| typecheck. Thus the capstone is an end-to-end statement: manifest -> ABI
||| proofs (flagship semantic equivalence + deeper tiling invariant) -> FFI
||| seam injectivity, all discharged simultaneously.
|||
||| Genuine composition only: no believe_me / idris_crash / assert_total /
||| postulate / sorry / %hint hacks. Every field is a real exported value.
module Halideiser.ABI.Capstone

import Halideiser.ABI.Types
import Halideiser.ABI.Semantics
import Halideiser.ABI.Invariants
import Halideiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate
--------------------------------------------------------------------------------

||| `ABISound` bundles the key proven facts of the halideiser ABI, one per
||| layer. To inhabit it you must supply, simultaneously:
|||
|||   * `flagship` — a Layer-2 `SplitEquivalent` witness on the canonical
|||     positive-control instance (the `double` stage, split 3x4). This is the
|||     exact type of `Semantics.doubleSplit3x4Equivalent`.
|||
|||   * `invariant` — a Layer-3 `ScheduleEquiv` witness that the tiled run of
|||     the same stage equals the flat run. This is the exact type of
|||     `Invariants.doubleTile2x3x2Equivalent`.
|||
|||   * `ffiInjective` — the Layer-4 seam theorem that `resultToInt` is
|||     injective, stored as the proven function value itself. This is the
|||     exact type of `FfiSeam.resultToIntInjective`.
|||
||| None of these can be faked: each field's type is precisely a prior layer's
||| exported proof obligation.
public export
record ABISound where
  constructor MkABISound
  flagship     : SplitEquivalent Semantics.double 3 4
  invariant    : ScheduleEquiv (runTile Semantics.double 2 3 2)
                               (runFlat Semantics.double ((2 * 3) * 2))
  ffiInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The single inhabited capstone value
--------------------------------------------------------------------------------

||| THE CAPSTONE. One inhabited certificate assembled entirely from the
||| already-exported witnesses of Layers 2, 3 and 4. Its very existence is the
||| end-to-end soundness statement: the full ABI contract — flagship semantic
||| equivalence, deeper tiling invariant, and FFI-seam injectivity — is
||| discharged together. If any prior layer regressed, this value would not
||| typecheck.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    doubleSplit3x4Equivalent     -- Layer 2: flagship positive control
    doubleTile2x3x2Equivalent    -- Layer 3: deeper tiling invariant
    resultToIntInjective         -- Layer 4: FFI seam injectivity

--------------------------------------------------------------------------------
-- Field projections (the certificate really exposes each proven fact)
--------------------------------------------------------------------------------

||| Project the Layer-2 flagship witness out of the discharged certificate.
public export
capstoneFlagship : SplitEquivalent Semantics.double 3 4
capstoneFlagship = abiContractDischarged.flagship

||| Project the Layer-3 invariant witness out of the discharged certificate.
public export
capstoneInvariant : ScheduleEquiv (runTile Semantics.double 2 3 2)
                                  (runFlat Semantics.double ((2 * 3) * 2))
capstoneInvariant = abiContractDischarged.invariant

||| Use the certificate's FFI-seam field at a concrete pair: equal codes force
||| equal results. Here the trivial `Refl` premise yields `Ok = Ok`, confirming
||| the stored injectivity proof really reduces.
public export
capstoneFfiOkOk : Ok = Ok
capstoneFfiOkOk = abiContractDischarged.ffiInjective Ok Ok Refl
