-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked theorems about the Atsiser ABI.
|||
||| These theorems pin down properties that the rest of the ABI relies on:
|||   * the example struct layouts are genuinely C-ABI compliant
|||     (every field offset is a multiple of its alignment), and
|||   * the result-code encoding agrees with the C contract.
|||
||| Each compliance witness is built DIRECTLY (one `DivideBy` per field),
||| because multiplication reduces during typechecking while division does
||| not — so these are checked, not asserted.

module Atsiser.ABI.Proofs

import Atsiser.ABI.Types
import Atsiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Struct Layout Compliance
--------------------------------------------------------------------------------

||| `exampleOwnedLayout` follows the C ABI: field `data` at offset 0 (= 0 * 8)
||| and field `len` at offset 8 (= 1 * 8) are both aligned to 8.
export
exampleOwnedCompliant : CABICompliant Layout.exampleOwnedLayout
exampleOwnedCompliant =
  CABIOk Layout.exampleOwnedLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- data: offset 0 = 0 * 8
      (ConsField _ _ (DivideBy 1 Refl) -- len:  offset 8 = 1 * 8
        NoFields))

||| `exampleBorrowedLayout` follows the C ABI: field `name` at offset 0 (= 0 * 8)
||| aligned to 8, and field `flags` at offset 8 (= 2 * 4) aligned to 4.
export
exampleBorrowedCompliant : CABICompliant Layout.exampleBorrowedLayout
exampleBorrowedCompliant =
  CABIOk Layout.exampleBorrowedLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- name:  offset 0 = 0 * 8
      (ConsField _ _ (DivideBy 2 Refl) -- flags: offset 8 = 2 * 4
        NoFields))

--------------------------------------------------------------------------------
-- Result-Code Encoding
--------------------------------------------------------------------------------

||| The success code encodes to 0, as the C FFI contract requires.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The generic-error code encodes to 1, distinct from success.
export
errorIsOne : resultToInt Error = 1
errorIsOne = Refl

||| The result encoding is injective on the two codes that the FFI layer
||| branches on most: success and bounds violation map to different integers.
export
okNotBounds : Not (resultToInt Ok = resultToInt BoundsViolation)
okNotBounds = \case Refl impossible
