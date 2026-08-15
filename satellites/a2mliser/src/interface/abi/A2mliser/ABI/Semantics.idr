-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for a2mliser: attestation binding soundness.
|||
||| Headline domain property (A2ML cryptographic attestation):
||| an attestation tag is bound to the exact content it was issued over.
||| An attestation `Verifies` a document if and only if the digest carried
||| by the attestation equals the digest of the document. Consequently a
||| TAMPERED document (content changed while keeping the old attestation)
||| has NO `Verifiable` proof: the bad case is uninhabited.
|||
||| This is the faithful core of "verify succeeds only for the content it
||| was issued over". We model a content digest as a `Nat` (an abstract
||| collision-free fingerprint of markup bytes); the binding logic is
||| algorithm-agnostic, exactly as in the real engine.

module A2mliser.ABI.Semantics

import A2mliser.ABI.Types
import Data.So
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful domain model
--------------------------------------------------------------------------------

||| A document is some markup content fingerprinted to a digest.
||| `contentDigest` is the abstract fingerprint of the markup bytes; two
||| documents with different content have different digests (collision-free
||| model). The `markup` field is carried for faithfulness but the binding
||| is over the digest, mirroring sign-the-digest cryptography.
public export
record Document where
  constructor MkDocument
  markup        : String
  contentDigest : Nat

||| An attestation tag binds to one specific content digest. It is the
||| (abstract) signature whose payload is `boundDigest`.
public export
record Attestation where
  constructor MkAttestation
  ||| The digest the attestation was issued over (what the signature covers).
  boundDigest : Nat
  ||| The signing algorithm (reuses the real ABI type for faithfulness).
  algorithm   : SignatureAlgorithm

||| Issue an attestation over a document: it binds to that document's digest.
||| This is the ONLY honest way to mint an attestation for a document.
public export
attest : SignatureAlgorithm -> Document -> Attestation
attest alg doc = MkAttestation (contentDigest doc) alg

--------------------------------------------------------------------------------
-- The headline property: attestation binding
--------------------------------------------------------------------------------

||| `Verifies att doc` is inhabited exactly when the attestation's bound
||| digest equals the document's content digest. There is precisely ONE
||| constructor, and it DEMANDS the binding equality as evidence. There is
||| NO constructor for the mismatched (tampered) case — that case is
||| uninhabited by construction.
public export
data Verifies : Attestation -> Document -> Type where
  ||| The attestation was issued over exactly this content.
  Bound : (prf : boundDigest att = contentDigest doc) -> Verifies att doc

||| A document/attestation pair is `Verifiable` iff a `Verifies` proof exists.
public export
Verifiable : Attestation -> Document -> Type
Verifiable = Verifies

--------------------------------------------------------------------------------
-- Sound + complete decision procedure
--------------------------------------------------------------------------------

||| Decide verifiability. Sound: a `Yes` carries a real `Verifies` witness.
||| Complete: a `No` carries a refutation of every possible witness.
public export
decVerifies : (att : Attestation) -> (doc : Document) -> Dec (Verifies att doc)
decVerifies att doc =
  case decEq (boundDigest att) (contentDigest doc) of
    Yes prf => Yes (Bound prf)
    No  ctra => No (\(Bound prf) => ctra prf)

--------------------------------------------------------------------------------
-- Certifier + soundness fact
--------------------------------------------------------------------------------

||| Internal: map a raw `Dec` outcome to the ABI's own result code.
||| Kept top-level so it reduces by pattern matching in the proofs below.
public export
certifyVia : Dec (Verifies att doc) -> AttestationResult
certifyVia (Yes _) = Ok
certifyVia (No  _) = DigestMismatch

||| Map a verification attempt to the ABI's own result code.
public export
certify : Attestation -> Document -> AttestationResult
certify att doc = certifyVia (decVerifies att doc)

||| Soundness: if the certifier returns `Ok`, a genuine binding proof exists.
||| (Forces `Ok` to mean the attestation truly covers this content.)
public export
certifyOkSound : (att : Attestation) -> (doc : Document)
              -> certify att doc = Ok -> Verifies att doc
certifyOkSound att doc okEq with (decVerifies att doc)
  certifyOkSound att doc okEq | Yes ok = ok
  certifyOkSound att doc Refl | No  _  impossible

||| Completeness/contrapositive: a `DigestMismatch` certificate means the
||| pair is genuinely NOT verifiable.
public export
certifyMismatchRefutes : (att : Attestation) -> (doc : Document)
                      -> certify att doc = DigestMismatch -> Not (Verifies att doc)
certifyMismatchRefutes att doc mmEq with (decVerifies att doc)
  certifyMismatchRefutes att doc Refl | Yes _   impossible
  certifyMismatchRefutes att doc mmEq | No ctra = ctra

--------------------------------------------------------------------------------
-- Core theorems about attestation binding
--------------------------------------------------------------------------------

||| An honestly-issued attestation always verifies the document it was
||| issued over (the engine never rejects untampered content).
public export
attestVerifies : (alg : SignatureAlgorithm) -> (doc : Document)
              -> Verifies (attest alg doc) doc
attestVerifies alg doc = Bound Refl

||| Binding soundness (tamper-evidence): if an attestation verifies BOTH a
||| document and a re-issued document, their content digests are identical.
||| Therefore you cannot make one attestation verify two contents that
||| differ — exactly the "bound to the content it was issued over" guarantee.
public export
bindingUnique : (att : Attestation) -> (d1, d2 : Document)
             -> Verifies att d1 -> Verifies att d2
             -> contentDigest d1 = contentDigest d2
bindingUnique att d1 d2 (Bound p1) (Bound p2) = trans (sym p1) p2

--------------------------------------------------------------------------------
-- Positive control (inhabited witness)
--------------------------------------------------------------------------------

||| A concrete document and the attestation honestly issued over it.
public export
goodDoc : Document
goodDoc = MkDocument "<a2ml:doc>hello</a2ml:doc>" 1729

public export
goodAtt : Attestation
goodAtt = attest Ed25519 goodDoc

||| POSITIVE CONTROL: the honest attestation verifies the original document.
public export
goodVerifies : Verifies Semantics.goodAtt Semantics.goodDoc
goodVerifies = Bound Refl

--------------------------------------------------------------------------------
-- Negative control (the tampered document is not verifiable)
--------------------------------------------------------------------------------

||| The SAME document content edited (tampered): different digest, but an
||| attacker tries to reuse the old `goodAtt`.
public export
tamperedDoc : Document
tamperedDoc = MkDocument "<a2ml:doc>HELLO (edited)</a2ml:doc>" 9999

||| NEGATIVE CONTROL: the original attestation does NOT verify the tampered
||| document. Machine-checked: any putative `Verifies` proof yields the
||| absurd equality `1729 = 9999`, which reduces to `Refl impossible`.
public export
tamperedNotVerifiable : Not (Verifies Semantics.goodAtt Semantics.tamperedDoc)
tamperedNotVerifiable (Bound prf) = absurdEq prf
  where
    ||| `prf` definitionally has type `1729 = 9999`; name the concrete,
    ||| constructor-headed equality so its refutation reduces.
    absurdEq : (the Nat 1729 = the Nat 9999) -> Void
    absurdEq Refl impossible
