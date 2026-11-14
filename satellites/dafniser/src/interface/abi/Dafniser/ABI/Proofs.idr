-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked ABI theorems for Dafniser.
|||
||| Every concrete `StructLayout` declared in `Dafniser.ABI.Layout` is shown
||| to be C-ABI-compliant: each field's offset is an exact multiple of its
||| declared alignment.  The witnesses are built DIRECTLY (one `DivideBy k Refl`
||| per field, where `offset = k * alignment`) because multiplication reduces
||| during typechecking whereas division does not — so we never route these
||| through the `decFieldsAligned` decision procedure.
|||
||| We also pin the FFI result-code encoding.

module Dafniser.ABI.Proofs

import Dafniser.ABI.Types
import Dafniser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI compliance of every concrete layout
--------------------------------------------------------------------------------

||| Precondition layout: offsets 0, 8, 16 are 0*8, 1*8, 2*8.
export
preconditionCompliant : CABICompliant Layout.preconditionLayout
preconditionCompliant =
  CABIOk Layout.preconditionLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields)))

||| Postcondition layout: identical shape to Precondition.
export
postconditionCompliant : CABICompliant Layout.postconditionLayout
postconditionCompliant =
  CABIOk Layout.postconditionLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields)))

||| LoopInvariant layout: offsets 0, 8, 16, 24 over alignment 8.
export
loopInvariantCompliant : CABICompliant Layout.loopInvariantLayout
loopInvariantCompliant =
  CABIOk Layout.loopInvariantLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields))))

||| GhostVariable layout: offsets 0, 8, 16, 24 over alignment 8.
export
ghostVariableCompliant : CABICompliant Layout.ghostVariableLayout
ghostVariableCompliant =
  CABIOk Layout.ghostVariableLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields))))

||| Lemma layout: offsets 0, 8, 16, 24, 32 over alignment 8.
export
lemmaCompliant : CABICompliant Layout.lemmaLayout
lemmaCompliant =
  CABIOk Layout.lemmaLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
     NoFields)))))

||| VerificationResult layout: tag(0,align4)=0*4, _pad(4,align4)=1*4,
||| functionName(8,align8)=1*8, detail(16,align8)=2*8, witness(24,align8)=3*8.
export
verificationResultCompliant : CABICompliant Layout.verificationResultLayout
verificationResultCompliant =
  CABIOk Layout.verificationResultLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields)))))

||| SpecTree layout: moduleName(0,a8)=0*8, target(8,a4)=2*4, _pad(12,a4)=3*4,
||| functions(16,a8)=2*8, moduleGhosts(24,a8)=3*8, moduleLemmas(32,a8)=4*8.
export
specTreeCompliant : CABICompliant Layout.specTreeLayout
specTreeCompliant =
  CABIOk Layout.specTreeLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
     NoFields))))))

--------------------------------------------------------------------------------
-- Result-code encoding
--------------------------------------------------------------------------------

||| The success code is zero, as the C ABI expects.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The error codes are pairwise distinct from success: Error encodes to 1.
export
errorIsOne : resultToInt Error = 1
errorIsOne = Refl

||| The five result codes are encoded as the contiguous range 0..4.
||| NullPointer is the largest, encoding to 4.
export
nullPointerIsFour : resultToInt NullPointer = 4
nullPointerIsFour = Refl
