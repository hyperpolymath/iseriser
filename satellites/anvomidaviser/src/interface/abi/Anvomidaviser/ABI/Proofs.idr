-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked ABI theorems for Anvomidaviser
|||
||| This module collects genuine, compiler-verified proofs about the
||| concrete C-ABI struct layouts and the result-code encoding used at the
||| FFI boundary. Every witness here is built directly so that it reduces
||| during typechecking — no holes, no postulates, no believe_me.

module Anvomidaviser.ABI.Proofs

import Anvomidaviser.ABI.Types
import Anvomidaviser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI Compliance of Concrete Layouts
--------------------------------------------------------------------------------

||| The TechnicalElement struct layout is C-ABI compliant: every field offset
||| is an exact multiple of that field's alignment. Each DivideBy witness is
||| built directly (field.offset = k * field.alignment), since multiplication
||| reduces during typechecking while division does not.
export
technicalElementCompliant : CABICompliant Layout.technicalElementLayout
technicalElementCompliant =
  CABIOk Layout.technicalElementLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- element_type: offset 0  = 0 * 1
    (ConsField _ _ (DivideBy 1 Refl)   -- subtype:      offset 1  = 1 * 1
    (ConsField _ _ (DivideBy 2 Refl)   -- rotation:     offset 2  = 2 * 1
    (ConsField _ _ (DivideBy 3 Refl)   -- level:        offset 3  = 3 * 1
    (ConsField _ _ (DivideBy 1 Refl)   -- base_value:   offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 8 Refl)   -- goe:          offset 8  = 8 * 1
    (ConsField _ _ (DivideBy 9 Refl)   -- padding:      offset 9  = 9 * 1
    (ConsField _ _ (DivideBy 3 Refl)   -- goe_value:    offset 12 = 3 * 4
    NoFields))))))))

||| The ProgramScore struct layout is C-ABI compliant.
export
programScoreCompliant : CABICompliant Layout.programScoreLayout
programScoreCompliant =
  CABIOk Layout.programScoreLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- total_base:          offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- total_goe:           offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- deductions:          offset 8  = 2 * 4
    (ConsField _ _ (DivideBy 12 Refl)  -- pcs_skating_skills:  offset 12 = 12 * 1
    (ConsField _ _ (DivideBy 13 Refl)  -- pcs_transitions:     offset 13 = 13 * 1
    (ConsField _ _ (DivideBy 14 Refl)  -- pcs_performance:     offset 14 = 14 * 1
    (ConsField _ _ (DivideBy 15 Refl)  -- pcs_composition:     offset 15 = 15 * 1
    (ConsField _ _ (DivideBy 16 Refl)  -- pcs_interpretation:  offset 16 = 16 * 1
    (ConsField _ _ (DivideBy 17 Refl)  -- padding:             offset 17 = 17 * 1
    (ConsField _ _ (DivideBy 5 Refl)   -- component_factor:    offset 20 = 5 * 4
    (ConsField _ _ (DivideBy 6 Refl)   -- total_segment:       offset 24 = 6 * 4
    NoFields)))))))))))

--------------------------------------------------------------------------------
-- Result-Code Encoding
--------------------------------------------------------------------------------

||| The success result encodes to the C integer 0.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The result-code encoding is injective at the two boundary cases we rely on
||| at the FFI layer: Ok and Error encode to distinct integers.
export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

||| RuleViolation pins to 5, the highest defined error code.
export
ruleViolationIsFive : resultToInt RuleViolation = 5
ruleViolationIsFive = Refl
