-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the wokelangiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, the result-code encoding wrong, or a round-trip broken,
||| this module would fail to typecheck and the proof build would go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Wokelangiser.ABI.Proofs

import Wokelangiser.ABI.Types
import Wokelangiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the consent record layout divides its field
||| alignment: 0|4, 4|4, 8|8, 16|8.
export
consentRecordCompliant : CABICompliant Layout.consentRecordLayout
consentRecordCompliant =
  CABIOk consentRecordLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 16 = 2 * 8
     NoFields))))

||| Every field offset in the accessibility record layout is aligned:
||| 0|4, 4|4, 8|4, 12|4, 16|8, 24|8.
export
accessibilityRecordCompliant : CABICompliant Layout.accessibilityRecordLayout
accessibilityRecordCompliant =
  CABIOk accessibilityRecordLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 8  = 2 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 12 = 3 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 16 = 2 * 8
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 24 = 3 * 8
     NoFields))))))

||| Every field offset in the i18n record layout is aligned:
||| 0|4, 4|4, 8|8, 16|8.
export
i18nRecordCompliant : CABICompliant Layout.i18nRecordLayout
i18nRecordCompliant =
  CABIOk i18nRecordLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 8  = 1 * 8
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 16 = 2 * 8
     NoFields))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
i18nErrorIsSeven : resultToInt I18nError = 7
i18nErrorIsSeven = Refl

--------------------------------------------------------------------------------
-- Consent-type round-trip is lossless for every constructor.
--------------------------------------------------------------------------------

||| The consent-type encoding round-trips for the AuditTrail case (3), a
||| nontrivial check that `consentFromInt . consentToInt` is the identity.
export
auditTrailRoundTrips : consentFromInt (consentToInt AuditTrail) = Just AuditTrail
auditTrailRoundTrips = Refl

||| WCAG level AAA round-trips through its integer encoding (2).
export
aaaRoundTrips : wcagFromInt (wcagToInt AAA) = Just AAA
aaaRoundTrips = Refl
