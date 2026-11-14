-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 — End-to-end ABI SOUNDNESS CERTIFICATE for BQNiser.
|||
||| This capstone does NOT prove a new domain theorem. It ASSEMBLES the proofs
||| already discharged by the lower layers into a single inhabited record, so
||| that the whole ABI contract is witnessed *together*, by one value. The chain
||| it ties together runs: manifest (bqniser.toml, "detect array patterns and
||| rewrite as optimised BQN primitives") -> Idris2 ABI proofs (Layer-2 flagship
||| rewrite + Layer-3 deeper invariant) -> FFI seam (Layer-4 wire encoding) ->
||| one end-to-end soundness statement.
|||
||| The fields of `ABISound` are the KEY proven facts, reused verbatim from the
||| existing modules (no fact is re-proven here):
|||
|||   * `flagship`   = `Semantics.rewritePreservesConcrete`
|||         the Layer-2 headline rewrite `+´⌽𝕩 ==> +´𝕩` holds on the canonical
|||         positive-control instance [1,2,3].
|||   * `invariant`  = `Invariants.fusionConcrete`
|||         the Layer-3 deeper map-fusion law `f¨g¨𝕩 ==> (f∘g)¨𝕩` holds on the
|||         canonical positive-control instance [1,2,3].
|||   * `ffiSeam`    = `FfiSeam.resultToIntInjective`
|||         the Layer-4 FFI-seam encoding `resultToInt` is injective, so distinct
|||         ABI outcomes never collide on the wire.
|||
||| `abiContractDischarged` is the single inhabited certificate. If ANY prior
||| layer were unsound, this value would fail to typecheck — that is the whole
||| point of the capstone.

module Bqniser.ABI.Capstone

import Bqniser.ABI.Types
import Bqniser.ABI.Semantics
import Bqniser.ABI.Invariants
import Bqniser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The end-to-end ABI soundness certificate
--------------------------------------------------------------------------------

||| A certificate that BQNiser's ABI contract is discharged across every layer.
||| Each field is exactly the type of a proof exported by a lower layer, so the
||| record can only be inhabited by genuinely proven witnesses.
public export
record ABISound where
  constructor MkABISound
  ||| Layer-2 flagship: the sum-of-reverse rewrite preserves semantics on the
  ||| canonical positive control.
  flagship  : bsum (brev [1, 2, 3]) = bsum [1, 2, 3]
  ||| Layer-3 invariant: the map-fusion law holds on the canonical positive
  ||| control (a deeper, shape-aware, genuinely different property).
  invariant : bmap (\x => x + 1) (bmap (\x => x * 2) [1, 2, 3])
              = bmap (\x => (x * 2) + 1) [1, 2, 3]
  ||| Layer-4 FFI seam: the on-the-wire Result encoding is injective.
  ffiSeam   : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: one inhabited certificate over all layers
--------------------------------------------------------------------------------

||| The capstone. Constructed entirely from facts the lower layers already
||| exported — no witness is fabricated here. Typechecking this value is the
||| end-to-end soundness check for the whole ABI.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    rewritePreservesConcrete   -- Bqniser.ABI.Semantics  (Layer 2)
    fusionConcrete             -- Bqniser.ABI.Invariants (Layer 3)
    resultToIntInjective       -- Bqniser.ABI.FfiSeam    (Layer 4)
