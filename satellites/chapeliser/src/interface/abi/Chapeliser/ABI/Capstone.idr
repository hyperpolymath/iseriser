-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Chapeliser ABI Soundness CAPSTONE (Layer 5)
|||
||| This module is the END-TO-END certificate: it ASSEMBLES the already-proven
||| facts of every prior ABI layer into a SINGLE inhabited value. It proves no
||| new domain theorem of its own — its entire content is that the prior layers
||| compose, and that one record can be built from their real exported witnesses.
||| If any earlier layer were unsound (its witness retracted or weakened), the
||| value `abiContractDischarged` below would simply fail to typecheck and the
||| proof build would go red.
|||
||| The contract it ties together, manifest -> ABI proofs -> FFI seam:
|||
|||   * Layer 2 (flagship property, `Proofs.idr`): the canonical positive-control
|||     partition `tenAcrossTwo` is a VALID partition — complete AND disjoint
|||     (`Proofs.tenAcrossTwoValid : ValidPartition Proofs.tenAcrossTwo`). This is
|||     the manifest-level "no item lost or double-placed" guarantee on a concrete
|||     instance.
|||
|||   * Layer 3 (deeper invariant, `Invariants.idr`): the REAL block-partition
|||     strategy (the div/mod counts the codegen actually emits) is complete for
|||     all n and k>0 — discharged here on the canonical 10-over-3 instance via
|||     `Invariants.blockPartitionIsComplete`, the packaged `PartitionComplete`
|||     object. We also carry the GENERAL theorem `blockCountsComplete` as a field
|||     so the certificate witnesses universal, not merely pointwise, completeness.
|||
|||   * Layer 4 (FFI seam, `FfiSeam.idr`): the `resultToInt` encoder crossing the
|||     Zig/C boundary is INJECTIVE — distinct ABI outcomes never collide on the
|||     wire (`FfiSeam.resultToIntInjective`). This is the seam soundness the FFI
|||     wrappers depend on.
|||
||| One value below inhabits all of these at once: that is the soundness
||| certificate. A deliberately-FALSE field is rejected by the type checker (see
||| the adversarial control in /tmp during the build procedure), so the record is
||| non-vacuous: it cannot be built from a bogus component.
|||
||| All composition is genuine: no `believe_me`, `idris_crash`, `assert_total`,
||| `postulate`, `sorry`, or `%hint` hacks. Every field is filled with a name
||| actually exported by the module it comes from.

module Chapeliser.ABI.Capstone

import Chapeliser.ABI.Types
import Chapeliser.ABI.Proofs
import Chapeliser.ABI.Partition
import Chapeliser.ABI.Invariants
import Chapeliser.ABI.FfiSeam

import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The capstone certificate type
--------------------------------------------------------------------------------

||| `ABISound` is the end-to-end ABI soundness certificate. Each field is a KEY
||| proven fact of a prior layer, reused verbatim — the record is inhabited iff
||| every layer it names is itself sound.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2 flagship: the canonical positive-control partition is VALID
  ||| (complete and non-overlapping). Reuses `Proofs.tenAcrossTwoValid`.
  flagshipValid : ValidPartition Proofs.tenAcrossTwo

  ||| Layer 3 invariant, concrete: the REAL block partition of 10 items over 3
  ||| locales is complete (`PartitionComplete` object). Reuses
  ||| `Invariants.blockPartitionIsComplete`.
  blockComplete :
    PartitionComplete
      (MkPartition {n = 10} {k = 3} (contiguousFrom 0 (blockCounts 10 2)))

  ||| Layer 3 invariant, GENERAL: the block partition's per-locale counts sum to
  ||| exactly `n` for every item count `n` and every positive locale count
  ||| `S k'`. Reuses `Invariants.blockCountsComplete` (universal, not pointwise).
  blockCompleteAll : (n, k' : Nat) -> sumNat (blockCounts n k') = n

  ||| Layer 4 FFI seam: the `resultToInt` encoder is injective — distinct ABI
  ||| outcomes never collide on the wire. Reuses `FfiSeam.resultToIntInjective`.
  ffiInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: the contract, discharged
--------------------------------------------------------------------------------

||| THE CAPSTONE. A single inhabited `ABISound`, assembled entirely from the
||| existing exported witnesses/theorems of Layers 2, 3 and 4. Its mere
||| typechecking is the proof that the full ABI contract — manifest-level
||| partition validity, real-strategy completeness, and FFI-seam injectivity —
||| is discharged together, end to end. Weaken any contributing proof and this
||| value stops typechecking.
export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    Proofs.tenAcrossTwoValid
    (Invariants.blockPartitionIsComplete 10 2)
    Invariants.blockCountsComplete
    FfiSeam.resultToIntInjective
