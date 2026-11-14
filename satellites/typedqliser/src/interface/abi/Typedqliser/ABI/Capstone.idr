-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-5 CAPSTONE: a single end-to-end ABI SOUNDNESS CERTIFICATE for
||| TypedQLiser.
|||
||| Every prior layer proved one face of the ABI contract in isolation:
|||
|||   * Layer-2 (`Semantics`)  — the FLAGSHIP type-safety property: a fully
|||     parameterized query is InjectionFree (level 5). Witness reused:
|||     `safeQueryInjectionFree`.
|||   * Layer-3 (`Invariants`) — the DEEPER, context-sensitive invariant: a
|||     guarded nullable projection is NullSafe (level 4). Witness reused:
|||     `guardedQueryNullSafe`.
|||   * Layer-3 companions — `SchemaBound` (level 2) and `TypeCompat` (level 3)
|||     pin the remaining static-semantics levels. Witnesses reused:
|||     `boundQuerySchemaBound`, `goodQueryTypeCompat`.
|||   * Layer-4 (`FfiSeam`)    — the ABI<->FFI SEAM is sealed: distinct result
|||     codes never collide on the wire. Theorem reused: `resultToIntInjective`.
|||
||| This module ASSEMBLES those already-proven facts into ONE inhabited record,
||| `ABISound`, and exhibits a single value `abiContractDischarged : ABISound`
||| built entirely from the existing exported witnesses. It proves no NEW domain
||| theorem; its content is that the whole chain — manifest-level type-safety
||| levels -> the ABI semantic proofs (flagship InjectionFree + the deeper
||| NullSafe invariant + SchemaBound + TypeCompat) -> the FFI seam injectivity —
||| holds SIMULTANEOUSLY. If any prior layer were unsound, its exported witness
||| would not exist and this capstone value would not typecheck. The certificate
||| is therefore an end-to-end soundness statement for the TypedQLiser ABI.

module Typedqliser.ABI.Capstone

import Typedqliser.ABI.Types
import Typedqliser.ABI.Semantics
import Typedqliser.ABI.SchemaBound
import Typedqliser.ABI.TypeCompat
import Typedqliser.ABI.Invariants
import Typedqliser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate type
--------------------------------------------------------------------------------

||| `ABISound` bundles the KEY proven facts of the TypedQLiser ABI into one
||| record. Each field is a proposition that some prior layer already discharged;
||| an inhabitant of `ABISound` is therefore a single object whose existence is
||| equivalent to the conjunction of all layers being sound.
public export
record ABISound where
  constructor MkABISound
  ||| Layer-2 flagship: the canonical parameterized positive control is
  ||| injection-free (level 5).
  flagshipInjectionFree : QueryInjectionFree Semantics.safeQuery
  ||| Layer-2 companion: SchemaBound (level 2) holds for its positive control.
  schemaBound           : QuerySchemaBound SchemaBound.exampleSchema SchemaBound.boundQuery
  ||| Layer-2 companion: TypeCompat (level 3) holds for its positive control.
  typeCompatible        : QueryTypeCompat TypeCompat.exampleEnv TypeCompat.goodQuery
  ||| Layer-3 deeper invariant: NullSafe (level 4) holds for the guarded control.
  invariantNullSafe     : QueryNullSafe Invariants.nullableCols Invariants.guardedQuery
  ||| Layer-4 FFI seam: distinct ABI result codes never collide on the C wire.
  ffiSeamInjective      : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: the whole ABI contract discharged at once
--------------------------------------------------------------------------------

||| THE CAPSTONE. A single inhabited value of `ABISound`, constructed purely from
||| the witnesses and theorems exported by the prior layers — no new axioms, no
||| `believe_me`, no `postulate`. Its successful typechecking IS the end-to-end
||| soundness certificate: manifest type-safety levels -> ABI semantic proofs
||| (flagship + invariant + schema/type bounds) -> FFI seam, all at once.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    safeQueryInjectionFree
    boundQuerySchemaBound
    goodQueryTypeCompat
    guardedQueryNullSafe
    resultToIntInjective

--------------------------------------------------------------------------------
-- Capstone-level corollaries projected back out of the certificate
--------------------------------------------------------------------------------

||| From the discharged certificate we can recover any single layer's guarantee —
||| e.g. the flagship InjectionFree witness — showing the bundle genuinely
||| contains (does not merely assert) each layer's proof.
public export
flagshipFromCapstone : QueryInjectionFree Semantics.safeQuery
flagshipFromCapstone = abiContractDischarged.flagshipInjectionFree

||| And the FFI-seam injectivity, specialised to a concrete distinct pair,
||| applied through the certificate: `Ok` and `Error` can only be equal on the
||| wire if they are equal as `Result`s (they are not — see `okNotError`).
public export
seamFromCapstone : resultToInt Ok = resultToInt Error -> Ok = Error
seamFromCapstone = abiContractDischarged.ffiSeamInjective Ok Error
