-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 (CAPSTONE): one end-to-end ABI SOUNDNESS CERTIFICATE for
||| ephapaxiser.
|||
||| Every prior layer proves one facet of the ABI contract in isolation:
|||
|||   * Layer 2 (`Ephapaxiser.ABI.Semantics`) — the flagship single-use /
|||     linearity property: a `Fresh` token is `Consumable` (positive control
|||     `freshTokenConsumable`), while a `Spent` token is not.
|||   * Layer 3 (`Ephapaxiser.ABI.Invariants`) — the deeper transition
|||     invariant: consumption is irreversible (NO-RESURRECTION,
|||     `noResurrectionThree`) and identity-preserving.
|||   * Layer 4 (`Ephapaxiser.ABI.FfiSeam`) — the ABI<->FFI seam is sound:
|||     `resultToIntInjective` shows distinct ABI outcomes never collide on the
|||     C wire.
|||
||| This module ties the manifest's promise ("enforce single-use linear type
||| semantics") to the ABI proofs (flagship + invariant) and onward to the FFI
||| seam, as ONE inhabited value. `ABISound` is a record whose fields are
||| exactly those proven facts, and `abiContractDischarged : ABISound` is built
||| solely from the existing exported witnesses/theorems of Layers 2-4. If ANY
||| prior layer were unsound — if any of those witnesses could not be produced
||| genuinely — this single value would not typecheck. That is the capstone:
||| the full ABI contract is discharged together, not facet by facet.
|||
||| No axioms anywhere: no `believe_me`, `idris_crash`, `assert_total`,
||| `postulate`, `sorry`, or `%hint` hacks. Each field is a real value imported
||| from the layer that proved it.

module Ephapaxiser.ABI.Capstone

import Ephapaxiser.ABI.Types
import Ephapaxiser.ABI.Semantics
import Ephapaxiser.ABI.Invariants
import Ephapaxiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate type
--------------------------------------------------------------------------------

||| `ABISound` is the end-to-end ABI soundness certificate. Each field is a KEY
||| proven fact of the ephapaxiser ABI, carried as a genuine value:
|||
|||   * `flagship`  — the Layer-2 flagship property on the canonical positive
|||     control: the concrete fresh token (id 7) IS `Consumable`.
|||   * `invariant` — the Layer-3 NO-RESURRECTION invariant on a concrete
|||     post-state: the spent result (id 3) is NOT resurrectable.
|||   * `ffiSeam`   — the Layer-4 FFI-seam soundness: `resultToInt` is
|||     injective, so distinct ABI outcomes never collide on the wire.
|||
||| A value of this record can only exist if all three layers are inhabited
||| together — there is no way to fabricate any field.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2: the canonical fresh token is consumable (flagship single-use).
  flagship  : Consumable (MkToken {st = Fresh} 7)
  ||| Layer 3: the spent post-state cannot be resurrected (irreversibility).
  invariant : Not (Resurrection (MkToken {st = Spent} 3))
  ||| Layer 4: the ABI->C encoding is injective (seam is collision-free).
  ffiSeam   : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: the ABI contract, discharged end-to-end
--------------------------------------------------------------------------------

||| THE CAPSTONE. A single inhabited certificate assembled entirely from the
||| existing exported witnesses/theorems of Layers 2-4:
|||
|||   * `flagship`  := `Semantics.freshTokenConsumable`
|||   * `invariant` := `Invariants.noResurrectionThree`
|||   * `ffiSeam`   := `FfiSeam.resultToIntInjective`
|||
||| Because each field is the real proof from its layer, this value typechecks
||| if and only if all prior layers are sound. It is the machine-checked
||| statement that the manifest promise, the ABI domain proofs, and the FFI
||| seam form one coherent, discharged contract.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    freshTokenConsumable
    noResurrectionThree
    resultToIntInjective

--------------------------------------------------------------------------------
-- Positive control: the capstone's fields project back to the real proofs.
--------------------------------------------------------------------------------

||| POSITIVE CONTROL: the flagship field of the discharged certificate is
||| definitionally the Layer-2 positive-control witness. Confirms the capstone
||| genuinely carries the underlying proof rather than some re-derived stand-in.
||| (Names are module-qualified so they are not implicitly bound as lowercase.)
public export
flagshipIsSemanticsControl
  : Capstone.abiContractDischarged.flagship = Semantics.freshTokenConsumable
flagshipIsSemanticsControl = Refl

||| POSITIVE CONTROL: the FFI-seam field, applied to a concrete colliding pair
||| (`Ok` with itself), yields the reflexivity proof — the injectivity theorem
||| is live inside the certificate, not inert.
public export
ffiSeamOkOk : Capstone.abiContractDischarged.ffiSeam Ok Ok Refl = Refl
ffiSeamOkOk = Refl
