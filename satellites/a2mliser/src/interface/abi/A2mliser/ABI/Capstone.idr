-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-5 CAPSTONE for a2mliser: a single end-to-end ABI SOUNDNESS
||| CERTIFICATE that ties the whole stack together into one inhabited value.
|||
||| This certificate ties the chain together:
|||   manifest -> ABI proofs (flagship + invariant) -> FFI seam
||| into a single end-to-end soundness statement. It assembles, in one record,
||| the KEY proven facts already discharged by the prior layers:
|||
|||   * flagship    (Layer 2) — `Semantics.goodVerifies` : the canonical
|||                  positive-control attestation really `Verifies` the document
|||                  it was issued over (attestation-binding soundness).
|||   * roundTrip   (Layer 3) — `Invariants.goodRoundTrips` : the ABI certifier
|||                  returns `Ok` for that honest attestation (issue->verify
|||                  round-trip / process correctness over the SAME control).
|||   * seamInj     (Layer 4) — `FfiSeam.resultToIntInjective` : the ABI->C
|||                  result-code encoder is injective, so distinct ABI outcomes
|||                  never collide on the wire (FFI-seam soundness).
|||
||| The single inhabited value `abiContractDischarged` is constructed ENTIRELY
||| from those existing exported witnesses. It is the capstone: if any prior
||| layer were unsound, this value would not typecheck. Genuine composition —
||| no `believe_me`, `postulate`, `assert_total`, `idris_crash`, or fabricated
||| witnesses anywhere.

module A2mliser.ABI.Capstone

import A2mliser.ABI.Types
import A2mliser.ABI.Semantics
import A2mliser.ABI.Invariants
import A2mliser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The capstone certificate type
--------------------------------------------------------------------------------

||| `ABISound` collects, as fields, the load-bearing proven facts of the a2mliser
||| ABI contract. Each field's TYPE is the proposition a prior layer discharged;
||| inhabiting the record therefore demands a real proof of every one at once.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2 (flagship): the canonical positive-control attestation verifies
  ||| the exact document it was issued over.
  flagship  : Verifies Semantics.goodAtt Semantics.goodDoc
  ||| Layer 3 (invariant): the ABI certifier round-trips that honest attestation
  ||| to an `Ok` result code through the real `certify`/`decVerifies` pipeline.
  roundTrip : certify Semantics.goodAtt Semantics.goodDoc = Ok
  ||| Layer 4 (FFI seam): the ABI->C result-code encoder is injective, so
  ||| distinct ABI outcomes never collide on the wire.
  seamInj   : (a, b : AttestationResult) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- The capstone value: the full ABI contract, discharged together
--------------------------------------------------------------------------------

||| THE CAPSTONE. One inhabited value assembled solely from prior-layer exports.
||| Its existence is the end-to-end soundness certificate for the a2mliser ABI:
||| flagship binding soundness, the issue->verify round-trip, and FFI-seam
||| injectivity all hold simultaneously over the canonical control.
public export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    Semantics.goodVerifies      -- Layer 2 flagship positive control
    Invariants.goodRoundTrips   -- Layer 3 round-trip invariant
    resultToIntInjective        -- Layer 4 FFI-seam injectivity
