-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the iseriser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, the result-code encoding wrong, or a decision procedure
||| mis-defined, this module would fail to typecheck and the proof build would
||| go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Iseriser.ABI.Proofs

import Iseriser.ABI.Types
import Iseriser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the LanguageModelData layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|8, 24|4, 28|4.
export
languageModelDataCompliant : CABICompliant Layout.languageModelDataLayout
languageModelDataCompliant =
  CABIOk languageModelDataLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields))))))

||| Every field offset in the TemplateData layout is aligned:
||| 0|8, 8|4, 12|4, 16|8, 24|4, 28|4.
export
templateDataCompliant : CABICompliant Layout.templateDataLayout
templateDataCompliant =
  CABIOk templateDataLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields))))))

||| Every field offset in the GenerationContext layout is aligned:
||| 0|8, 8|8, 16|4, 20|4, 24|8, 32|4, 36|4, 40|4, 44|4.
export
generationContextCompliant : CABICompliant Layout.generationContextLayout
generationContextCompliant =
  CABIOk generationContextLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
    (ConsField _ _ (DivideBy 9 Refl)
    (ConsField _ _ (DivideBy 10 Refl)
    (ConsField _ _ (DivideBy 11 Refl)
     NoFields)))))))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
nullPointerIsFive : resultToInt NullPointer = 5
nullPointerIsFive = Refl

--------------------------------------------------------------------------------
-- Generation completeness: the full required set is accepted; a short set isn't.
--------------------------------------------------------------------------------

||| The complete set of seven categories is recognised as complete.
export
fullSetComplete : So (allCategoriesPresent Types.requiredCategories)
fullSetComplete = Oh

||| A set missing RSRGovernance is correctly rejected as incomplete.
export
shortSetIncomplete : So (not (allCategoriesPresent
  [CargoToml, RustSource, Idris2ABI, ZigFFI, CIWorkflows, Documentation]))
shortSetIncomplete = Oh
