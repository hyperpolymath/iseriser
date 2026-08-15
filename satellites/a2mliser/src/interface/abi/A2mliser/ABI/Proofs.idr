-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked theorems about the a2mliser ABI.
|||
||| This module carries genuine, compiler-verified proofs:
|||   * C-ABI compliance of every concrete struct layout, with each field's
|||     offset shown to be a multiple of its alignment via a direct `DivideBy`
|||     witness (multiplication reduces during typechecking; division does not,
|||     so the witnesses are built directly rather than via `decFieldsAligned`).
|||   * The result-code encoding is pinned (e.g. `Ok` maps to 0).
|||
||| @see A2mliser.ABI.Layout for the layout definitions being proven about.

module A2mliser.ABI.Proofs

import A2mliser.ABI.Types
import A2mliser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI Compliance of Concrete Layouts
--------------------------------------------------------------------------------

||| The envelope-header layout is C-ABI compliant: every field's offset is a
||| multiple of its alignment.
|||   hashAlgId  0 = 0*4 | sigAlgId 4 = 1*4 | digestLen 8 = 2*4
|||   signatureLen 12 = 3*4 | timestamp 16 = 2*8 | hasParent 24 = 6*4
|||   _pad 28 = 7*4
export
envelopeHeaderCompliant : CABICompliant Layout.envelopeHeaderLayout
envelopeHeaderCompliant =
  CABIOk Layout.envelopeHeaderLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields)))))))

||| The digest-buffer layout is C-ABI compliant (single byte-aligned field at 0).
export
digestBufferCompliant : CABICompliant Layout.digestBufferLayout
digestBufferCompliant =
  CABIOk Layout.digestBufferLayout
    (ConsField _ _ (DivideBy 0 Refl)
     NoFields)

||| The Ed25519 signature-buffer layout is C-ABI compliant.
export
ed25519SignatureCompliant : CABICompliant Layout.ed25519SignatureLayout
ed25519SignatureCompliant =
  CABIOk Layout.ed25519SignatureLayout
    (ConsField _ _ (DivideBy 0 Refl)
     NoFields)

||| The Ed448 signature-buffer layout is C-ABI compliant.
export
ed448SignatureCompliant : CABICompliant Layout.ed448SignatureLayout
ed448SignatureCompliant =
  CABIOk Layout.ed448SignatureLayout
    (ConsField _ _ (DivideBy 0 Refl)
     NoFields)

||| The provenance-entry layout is C-ABI compliant.
|||   header 0 = 0*8 | digestPtr 32 = 4*8
|||   signaturePtr 40 = 5*8 | parentPtr 48 = 6*8
export
provenanceEntryCompliant : CABICompliant Layout.provenanceEntryLayout
provenanceEntryCompliant =
  CABIOk Layout.provenanceEntryLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
     NoFields))))

--------------------------------------------------------------------------------
-- Result-Code Encoding
--------------------------------------------------------------------------------

||| `Ok` is encoded as the C success value 0.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| `SignatureInvalid` is encoded as 5, matching the FFI contract used by
||| `verifyEd25519` / `verifyEnvelope` in Foreign.idr.
export
signatureInvalidIsFive : resultToInt SignatureInvalid = 5
signatureInvalidIsFive = Refl

||| The result encoding is injective on the pair we rely on most at the FFI
||| boundary: success (0) is distinct from a broken provenance chain (7).
export
okNotChainBroken : Not (resultToInt Ok = resultToInt ChainBroken)
okNotChainBroken = \case Refl impossible
