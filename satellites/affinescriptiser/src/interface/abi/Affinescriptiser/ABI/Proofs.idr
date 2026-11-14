-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked theorems for the Affinescriptiser ABI.
|||
||| These theorems pin down the correctness of the concrete struct layouts and
||| the FFI result-code encoding. They are checked by the Idris2 type checker:
||| if a layout's field offsets stopped being correctly aligned, or the result
||| encoding changed, this module would fail to compile.

module Affinescriptiser.ABI.Proofs

import Affinescriptiser.ABI.Types
import Affinescriptiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Layout compliance
--------------------------------------------------------------------------------

||| The tracked-file-descriptor layout is C-ABI compliant: every field's offset
||| is an exact multiple of that field's alignment.
|||
||| Field offsets: kind=0, linearity=4, ownership=8, padding=12, fd=16, each
||| with alignment 4. The DivideBy witnesses give offset = k * 4 for each:
||| 0=0*4, 4=1*4, 8=2*4, 12=3*4, 16=4*4. These multiplications reduce during
||| typechecking, so the equalities hold by Refl.
export
trackedFDCompliant : CABICompliant Layout.trackedFDLayout
trackedFDCompliant =
  CABIOk Layout.trackedFDLayout
    (ConsField _ _ (DivideBy 0 Refl)
      (ConsField _ _ (DivideBy 1 Refl)
        (ConsField _ _ (DivideBy 2 Refl)
          (ConsField _ _ (DivideBy 3 Refl)
            (ConsField _ _ (DivideBy 4 Refl)
              NoFields)))))

--------------------------------------------------------------------------------
-- Result-code encoding
--------------------------------------------------------------------------------

||| The success result encodes to the C integer 0, as required by callers that
||| test the FFI return value against zero.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The affine-violation result encodes to 5, matching the dispatch in
||| Foreign.analyse which maps 5 to AffineViolation.
export
affineViolationIsFive : resultToInt AffineViolation = 5
affineViolationIsFive = Refl

||| The resource-leak result encodes to 6, matching Foreign.analyse's mapping
||| of 6 to ResourceLeak.
export
resourceLeakIsSix : resultToInt ResourceLeak = 6
resourceLeakIsSix = Refl

--------------------------------------------------------------------------------
-- Default linearity
--------------------------------------------------------------------------------

||| Mutex locks default to Linear (exactly-once): failing to unlock is a bug, so
||| the affine "at most once" relaxation is not permitted for them.
export
mutexIsLinear : defaultLinearity MutexLock = Linear
mutexIsLinear = Refl

||| File descriptors default to Affine (at most once) — the safe default for
||| acquire/release resources.
export
fdIsAffine : defaultLinearity FileDescriptor = Affine
fdIsAffine = Refl
