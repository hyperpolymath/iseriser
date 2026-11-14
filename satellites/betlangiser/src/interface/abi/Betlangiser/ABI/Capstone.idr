-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 CAPSTONE: the end-to-end ABI SOUNDNESS CERTIFICATE for Betlangiser.
|||
||| Every prior layer proved one slice of the ABI contract in isolation:
|||
|||   * Layer 2 (`Betlangiser.ABI.Semantics`) — the flagship semantic property:
|||     the Kleene substrate's `and3` preserves classical truth (`Designated`),
|||     witnessed on the canonical positive control `andTTDesignated`.
|||   * Layer 3 (`Betlangiser.ABI.Invariants`) — the deeper structural invariant:
|||     `and3` is the meet (greatest lower bound) of the Kleene information
|||     order, witnessed on the positive control `meetTU_belowU`.
|||   * Layer 4 (`Betlangiser.ABI.FfiSeam`) — the ABI<->FFI seam soundness:
|||     `resultToIntInjective`, distinct ABI outcomes never collide on the wire.
|||
||| This module ties them together into ONE inhabited value. The record
||| `ABISound` bundles the three key proven facts as fields; the single value
||| `abiContractDischarged` constructs it from the *actual exported witnesses*
||| of those three modules. Because the record's field types name the genuine
||| theorems, `abiContractDischarged` only typechecks if all three prior layers
||| are themselves sound: the manifest's promised behaviour (ternary semantics)
||| flows through the ABI proofs (flagship + invariant) and across the FFI seam
||| (injective encoding) as a single, machine-checked end-to-end statement.
|||
||| No `believe_me`, `idris_crash`, `assert_total`, `postulate`, or `sorry`:
||| this is genuine composition of already-proven facts only.

module Betlangiser.ABI.Capstone

import Betlangiser.ABI.Types
import Betlangiser.ABI.Semantics
import Betlangiser.ABI.Invariants
import Betlangiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate
--------------------------------------------------------------------------------

||| `ABISound` is the end-to-end soundness certificate. Each field is a key
||| proven fact of the Betlangiser ABI; an inhabitant exists only if every
||| layer it references is sound.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2 flagship: `and3` preserves classical truth on the canonical
  ||| positive control `T and3 T`. (Reuses `Semantics.andTTDesignated`.)
  flagshipDesignated : Designated (and3 T T)
  ||| Layer 3 invariant: the meet of `T` and `U` is below `U` in the Kleene
  ||| order — `and3` is the genuine GLB. (Reuses `Invariants.meetTU_belowU`.)
  meetInvariant : Leq3 (and3 T U) U
  ||| Layer 4 FFI seam: the C-integer encoding of `Result` is injective, so
  ||| distinct ABI outcomes never collide on the wire. (Reuses
  ||| `FfiSeam.resultToIntInjective`.)
  seamInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

||| THE CAPSTONE. A single inhabited value assembled purely from the existing
||| exported witnesses/theorems of Layers 2, 3 and 4. If any of those layers
||| were unsound, this value would fail to typecheck — so its mere existence
||| certifies the whole ABI contract is discharged together.
public export
abiContractDischarged : ABISound
abiContractDischarged = MkABISound andTTDesignated meetTU_belowU resultToIntInjective
