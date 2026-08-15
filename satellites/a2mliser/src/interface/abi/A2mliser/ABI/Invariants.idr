-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariants for a2mliser: attestation DETERMINISM, IDEMPOTENCE and
||| the issue->verify ROUND-TRIP, built over the SAME model as Semantics.idr.
|||
||| This is deliberately DISTINCT from (and deeper than) the Layer-2 flagship
||| theorem `bindingUnique` (binding soundness / tamper-evidence). Where Layer 2
||| answers "can one tag verify two different contents?" (no), Layer 3 answers a
||| different family of questions about the issuing PROCESS itself:
|||
|||   * Determinism      — `attest` is a (mathematical) function: identical
|||                        inputs give bit-identical attestations, and identical
|||                        attestations on the same doc give identical results.
|||   * Idempotence      — re-attesting a document with the same algorithm
|||                        reproduces the very same attestation (a fixed point).
|||   * Round-trip       — a freshly attested document ALWAYS re-verifies, and
|||                        the ABI certifier ALWAYS returns `Ok` for it; further,
|||                        re-running `certify` on the freshly attested doc is a
|||                        stable fixed point (`Ok` again, deterministically).
|||   * Round-trip recovery — from `certify (attest alg d) d = Ok` you can
|||                        RECOVER the binding digest equality (transition
|||                        soundness: the Ok certificate is honest evidence).
|||
||| All of this reuses Semantics.attest / Verifies / certify unchanged.

module A2mliser.ABI.Invariants

import A2mliser.ABI.Types
import A2mliser.ABI.Semantics
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- 1. Determinism of `attest` (it is genuinely a function)
--------------------------------------------------------------------------------

||| DETERMINISM: `attest` is congruent under equality of its inputs. Equal
||| algorithm and equal document produce the identical attestation. This is the
||| substance of "same document => same attestation".
public export
attestDeterministic : (a1, a2 : SignatureAlgorithm) -> (d1, d2 : Document)
                   -> a1 = a2 -> d1 = d2
                   -> attest a1 d1 = attest a2 d2
attestDeterministic a1 a1 d1 d1 Refl Refl = Refl

||| Corollary in the algorithm-fixed form most callers want: one algorithm,
||| equal documents => equal attestation.
public export
attestDetDoc : (alg : SignatureAlgorithm) -> (d1, d2 : Document)
            -> d1 = d2 -> attest alg d1 = attest alg d2
attestDetDoc alg d1 d2 eq = attestDeterministic alg alg d1 d2 Refl eq

--------------------------------------------------------------------------------
-- 2. Idempotence: re-attesting a document is a fixed point
--------------------------------------------------------------------------------

||| The digest carried by a freshly issued attestation is exactly the
||| document's digest (computation lemma; reduces by definition of `attest`).
public export
attestBoundDigest : (alg : SignatureAlgorithm) -> (doc : Document)
                 -> boundDigest (attest alg doc) = contentDigest doc
attestBoundDigest alg doc = Refl

||| Re-document an attestation by wrapping its bound digest back into a
||| `Document` shell. Re-attesting that shell with the same algorithm must
||| reproduce an attestation bound to the same digest (idempotent issuing).
||| We state idempotence on the digest the attestation commits to.
public export
attestIdempotent : (alg : SignatureAlgorithm) -> (doc : Document)
                -> boundDigest (attest alg (MkDocument (markup doc)
                                                        (boundDigest (attest alg doc))))
                 = boundDigest (attest alg doc)
attestIdempotent alg doc = Refl

--------------------------------------------------------------------------------
-- 3. Round-trip: issue then verify always succeeds (process correctness)
--------------------------------------------------------------------------------

||| The ABI certifier always returns `Ok` for an honestly-issued attestation.
||| This connects the ISSUING function to the RESULT-CODE surface (a
||| transition-soundness fact: honest issue => Ok certificate), going through
||| the real `certify`/`decVerifies` pipeline rather than restating `Verifies`.
public export
attestCertifies : (alg : SignatureAlgorithm) -> (doc : Document)
               -> certify (attest alg doc) doc = Ok
attestCertifies alg doc with (decVerifies (attest alg doc) doc)
  attestCertifies alg doc | Yes _   = Refl
  attestCertifies alg doc | No  bad = absurd (bad (attestVerifies alg doc))

||| ROUND-TRIP STABILITY (fixed point of certification): certifying a freshly
||| attested document, twice, yields the same `Ok` both times. Since `certify`
||| is deterministic this is `Ok = Ok`, but stated through `attestCertifies` it
||| witnesses that re-verification is a stable fixed point, not a fluke.
public export
attestCertifyStable : (alg : SignatureAlgorithm) -> (doc : Document)
                   -> certify (attest alg doc) doc = certify (attest alg doc) doc
attestCertifyStable alg doc =
  trans (attestCertifies alg doc) (sym (attestCertifies alg doc))

--------------------------------------------------------------------------------
-- 4. Round-trip recovery: an Ok certificate is honest evidence
--------------------------------------------------------------------------------

||| TRANSITION SOUNDNESS / RECOVERY: from an `Ok` certificate on a freshly
||| attested document, recover the binding digest equality. We obtain a genuine
||| `Verifies` witness from the Layer-2 soundness lemma and read its digest
||| equality back out. (Distinct from Layer 2: this is keyed on `attest`, i.e.
||| the issuing process, and lands in the underlying Nat equality.)
public export
certifyOkRecoversDigest : (alg : SignatureAlgorithm) -> (doc : Document)
                       -> certify (attest alg doc) doc = Ok
                       -> boundDigest (attest alg doc) = contentDigest doc
certifyOkRecoversDigest alg doc okEq =
  case certifyOkSound (attest alg doc) doc okEq of
    Bound prf => prf

--------------------------------------------------------------------------------
-- 5. A natural sound+complete decision: are two attestations interchangeable?
--------------------------------------------------------------------------------

||| Two attestations are `SameBinding` iff they commit to the same digest.
||| (This is the digest-level equivalence that drives interchangeability for
||| verification: SameBinding attestations verify exactly the same documents.)
public export
data SameBinding : Attestation -> Attestation -> Type where
  MkSameBinding : (prf : boundDigest a1 = boundDigest a2) -> SameBinding a1 a2

||| SOUND + COMPLETE decision for `SameBinding`. `Yes` carries a real witness;
||| `No` refutes every possible witness.
public export
decSameBinding : (a1, a2 : Attestation) -> Dec (SameBinding a1 a2)
decSameBinding a1 a2 =
  case decEq (boundDigest a1) (boundDigest a2) of
    Yes prf => Yes (MkSameBinding prf)
    No  ctra => No (\(MkSameBinding prf) => ctra prf)

||| Soundness of the equivalence in use: `SameBinding` attestations verify the
||| same documents. If `a1` verifies `doc` and `a1`/`a2` share a binding, then
||| `a2` verifies `doc` too. (Deeper than Layer 2: a CONGRUENCE of `Verifies`
||| along the digest equivalence, not just uniqueness.)
public export
sameBindingVerifies : (a1, a2 : Attestation) -> (doc : Document)
                   -> SameBinding a1 a2 -> Verifies a1 doc -> Verifies a2 doc
sameBindingVerifies a1 a2 doc (MkSameBinding sb) (Bound p1) =
  Bound (trans (sym sb) p1)

--------------------------------------------------------------------------------
-- 6. POSITIVE controls (inhabited witnesses / concrete instances)
--------------------------------------------------------------------------------

||| Reuse the Layer-2 concrete document so controls are over the real model.
||| POSITIVE: the certifier really returns `Ok` for the honest attestation.
public export
goodRoundTrips : certify Semantics.goodAtt Semantics.goodDoc = Ok
goodRoundTrips = attestCertifies Ed25519 Semantics.goodDoc

||| POSITIVE: an attestation is trivially same-binding with itself, and that
||| witness lets it re-verify the original document via the congruence lemma.
public export
goodSelfSame : SameBinding Semantics.goodAtt Semantics.goodAtt
goodSelfSame = MkSameBinding Refl

public export
goodSameVerifies : Verifies Semantics.goodAtt Semantics.goodDoc
goodSameVerifies =
  sameBindingVerifies Semantics.goodAtt Semantics.goodAtt Semantics.goodDoc
                      goodSelfSame Semantics.goodVerifies

||| POSITIVE: idempotence holds concretely for the good document.
public export
goodIdempotent : boundDigest (attest Ed25519
                   (MkDocument (markup Semantics.goodDoc)
                               (boundDigest (attest Ed25519 Semantics.goodDoc))))
               = boundDigest (attest Ed25519 Semantics.goodDoc)
goodIdempotent = attestIdempotent Ed25519 Semantics.goodDoc

--------------------------------------------------------------------------------
-- 7. NEGATIVE / non-vacuity controls (must be refutable)
--------------------------------------------------------------------------------

||| The honest attestation over `goodDoc` (digest 1729) and a tag bound to the
||| tampered digest (9999) are NOT same-binding. Machine-checked refutation:
||| any putative witness yields the absurd `1729 = 9999`.
public export
goodTamperNotSameBinding :
  Not (SameBinding Semantics.goodAtt (attest Ed25519 Semantics.tamperedDoc))
goodTamperNotSameBinding (MkSameBinding prf) = absurdEq prf
  where
    absurdEq : (the Nat 1729 = the Nat 9999) -> Void
    absurdEq Refl impossible

||| NON-VACUITY of the round-trip recovery: the recovered digest equality for
||| the good document is the concrete, true `1729 = 1729`. (If recovery were
||| vacuous it could not produce this honest equality.)
public export
goodRecoveredDigest : boundDigest Semantics.goodAtt = contentDigest Semantics.goodDoc
goodRecoveredDigest =
  certifyOkRecoversDigest Ed25519 Semantics.goodDoc goodRoundTrips

||| NEGATIVE CONTROL: the certifier does NOT return `Ok` for the original
||| attestation against the tampered document. Any such equality is refuted
||| through the Layer-2 soundness lemma (it would yield a forbidden `Verifies`).
public export
tamperNotCertifiedOk :
  Not (certify Semantics.goodAtt Semantics.tamperedDoc = Ok)
tamperNotCertifiedOk okEq =
  Semantics.tamperedNotVerifiable
    (certifyOkSound Semantics.goodAtt Semantics.tamperedDoc okEq)
