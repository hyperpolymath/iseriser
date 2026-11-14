-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked ABI theorems for Eclexiaiser.
|||
||| This module carries the load-bearing correctness proofs for the
||| eclexiaiser ABI: every concrete C-struct layout is proven C-ABI
||| compliant by exhibiting a FieldsAligned witness directly (one
||| DivideBy per field, with field.offset = k * field.alignment, which
||| reduces by multiplication during typechecking), plus a couple of
||| result-code encoding pins.

module Eclexiaiser.ABI.Proofs

import Eclexiaiser.ABI.Types
import Eclexiaiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI Compliance of Concrete Struct Layouts
--------------------------------------------------------------------------------

||| EnergyMeasurement is C-ABI compliant: all field offsets are multiples
||| of their alignment (0=0*8, 8=1*8, 16=2*8, 24=6*4).
export
energyMeasurementCompliant : CABICompliant Layout.energyMeasurementLayout
energyMeasurementCompliant =
  CABIOk Layout.energyMeasurementLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
     NoFields))))

||| CarbonQuery is C-ABI compliant: offsets 0=0*4, 4=1*4, 8=1*8, 16=4*4, 20=5*4.
export
carbonQueryCompliant : CABICompliant Layout.carbonQueryLayout
carbonQueryCompliant =
  CABIOk Layout.carbonQueryLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
     NoFields)))))

||| BudgetEnforcement is C-ABI compliant: offsets 0=0*8, 8=1*8, 16=2*8,
||| 24=3*8, 32=8*4.
export
budgetEnforcementCompliant : CABICompliant Layout.budgetEnforcementLayout
budgetEnforcementCompliant =
  CABIOk Layout.budgetEnforcementLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
     NoFields)))))

--------------------------------------------------------------------------------
-- Result-Code Encoding Pins
--------------------------------------------------------------------------------

||| The success code encodes to zero at the C boundary.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The budget-exceeded code encodes to 5 (matching the Zig FFI contract).
export
budgetExceededIsFive : resultToInt BudgetExceeded = 5
budgetExceededIsFive = Refl

||| Distinct result constructors encode to distinct integers: a concrete
||| instance pinning that Ok (0) and Error (1) are not confusable.
export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible
