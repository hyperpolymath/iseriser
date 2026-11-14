-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the TypedQLiser ABI.
|||
||| These are propositional statements the Idris2 type checker must discharge at
||| compile time — not runtime tests. If the certificate descriptor were
||| misaligned, a level ordinal wrong, the status encoding off, or a "complete"
||| certificate admitted a non-Proven level, this module would fail to typecheck.

module Typedqliser.ABI.Proofs

import Typedqliser.ABI.Types
import Typedqliser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The certificate descriptor is provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the certificate descriptor divides its alignment:
||| 0|8, 8|8, 16|4, 20|4, 24|8, 32|4, 36|4.
export
certificateDescCompliant : CABICompliant Layout.certificateDescLayout
certificateDescCompliant =
  CABIOk Layout.certificateDescLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 8 Refl)
    (ConsField _ _ (DivideBy 9 Refl)
     NoFields)))))))

--------------------------------------------------------------------------------
-- Level ordinals + cumulative ordering.
--------------------------------------------------------------------------------

||| ParseSafe is level 1 (the floor).
export
parseSafeIsOne : levelNat ParseSafe = 1
parseSafeIsOne = Refl

||| LinearSafe is level 10 (the ceiling).
export
linearSafeIsTen : levelNat LinearSafe = 10
linearSafeIsTen = Refl

||| Cumulativity is reflected in the ordering: the top level dominates every
||| other. A query at LinearSafe has therefore discharged InjectionFree.
export
linearDominatesInjectionFree : So (levelDominates LinearSafe InjectionFree)
linearDominatesInjectionFree = Oh

||| The ordering is *not* symmetric: InjectionFree does not dominate LinearSafe.
export
injectionFreeBelowLinear : So (not (levelDominates InjectionFree LinearSafe))
injectionFreeBelowLinear = Oh

--------------------------------------------------------------------------------
-- Proof-status encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
provenIsZero : statusToInt Proven = 0
provenIsZero = Refl

export
timeoutIsThree : statusToInt Timeout = 3
timeoutIsThree = Refl

--------------------------------------------------------------------------------
-- Certificate completeness (non-vacuous).
--------------------------------------------------------------------------------

||| A certificate whose ten levels are all Proven is complete. The obligation is
||| real: see `incompleteRejected` for the negative side.
export
tenAllProven : CertifiedComplete (replicate 10 Proven)
tenAllProven = Complete Oh

||| A certificate with one Refuted level is NOT all-proven — witnessing that
||| `CertifiedComplete`'s obligation `So (allProven v)` is not vacuously true
||| (there is no `Complete` for this vector).
export
incompleteNotAllProven :
  So (not (allProven [Proven, Proven, Refuted, Proven]))
incompleteNotAllProven = Oh
