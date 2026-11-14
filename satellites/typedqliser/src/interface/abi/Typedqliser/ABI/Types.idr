-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for TypedQLiser.
|||
||| Models the ten cumulative type-safety levels a query may achieve, the
||| per-level proof status, and the proof certificate that crosses the FFI
||| boundary. The levels are cumulative: a query certified at level N has
||| satisfied the obligations of every level 1..N.

module Typedqliser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Platform
--------------------------------------------------------------------------------

public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Default build platform (overridden by the codegen/build layer).
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- The ten type-safety levels
--------------------------------------------------------------------------------

||| The ten cumulative type-safety levels (see src/abi/mod.rs).
public export
data SafetyLevel : Type where
  ParseSafe     : SafetyLevel  -- 1: total parser produces Right ast
  SchemaBound   : SafetyLevel  -- 2: all references resolve in the schema
  TypeCompat    : SafetyLevel  -- 3: operand types compatible
  NullSafe      : SafetyLevel  -- 4: nullable paths explicitly handled
  InjectionFree : SafetyLevel  -- 5: no string interpolation in structure
  ResultTyped   : SafetyLevel  -- 6: return type statically known
  CardinalSafe  : SafetyLevel  -- 7: result cardinality bounded
  EffectTracked : SafetyLevel  -- 8: side-effects declared and verified
  TemporalSafe  : SafetyLevel  -- 9: time-dependent predicates valid
  LinearSafe    : SafetyLevel  -- 10: resources consumed exactly once

||| The 1-based ordinal of a level. This is the cumulative ordering: a query
||| at level `levelNat l` has discharged every obligation with a smaller ordinal.
public export
levelNat : SafetyLevel -> Nat
levelNat ParseSafe     = 1
levelNat SchemaBound   = 2
levelNat TypeCompat    = 3
levelNat NullSafe      = 4
levelNat InjectionFree = 5
levelNat ResultTyped   = 6
levelNat CardinalSafe  = 7
levelNat EffectTracked = 8
levelNat TemporalSafe  = 9
levelNat LinearSafe    = 10

public export
Eq SafetyLevel where
  a == b = levelNat a == levelNat b

||| `a` is at least as strong as `b` when its ordinal dominates. Cumulativity
||| means achieving `a` entails every level `b` with `levelDominates a b`.
public export
levelDominates : SafetyLevel -> SafetyLevel -> Bool
levelDominates a b = levelNat b <= levelNat a

--------------------------------------------------------------------------------
-- Per-level proof status
--------------------------------------------------------------------------------

public export
data ProofStatus = Proven | Refuted | Skipped | Timeout

public export
Eq ProofStatus where
  Proven  == Proven  = True
  Refuted == Refuted = True
  Skipped == Skipped = True
  Timeout == Timeout = True
  _       == _       = False

||| C encoding for the proof status (must match the Zig FFI).
public export
statusToInt : ProofStatus -> Bits32
statusToInt Proven  = 0
statusToInt Refuted = 1
statusToInt Skipped = 2
statusToInt Timeout = 3

--------------------------------------------------------------------------------
-- FFI result codes
--------------------------------------------------------------------------------

public export
data Result : Type where
  Ok           : Result
  Error        : Result
  InvalidQuery : Result
  SchemaError  : Result
  NullPointer  : Result

public export
resultToInt : Result -> Bits32
resultToInt Ok           = 0
resultToInt Error        = 1
resultToInt InvalidQuery = 2
resultToInt SchemaError  = 3
resultToInt NullPointer  = 4

--------------------------------------------------------------------------------
-- Opaque handle
--------------------------------------------------------------------------------

public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely build a handle; a null pointer yields Nothing. `choose` supplies the
||| real `So (ptr /= 0)` witness for the non-null branch.
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Proof certificate
--------------------------------------------------------------------------------

||| One level's proof outcome.
public export
record LevelProof where
  constructor MkLevelProof
  level  : SafetyLevel
  status : ProofStatus

||| A certificate: the highest level reached, and the per-level outcomes.
public export
record ProofCertificate (n : Nat) where
  constructor MkProofCertificate
  maxLevel : SafetyLevel
  proofs   : Vect n ProofStatus

||| Decidable predicate: every level in the vector was Proven.
public export
allProven : Vect n ProofStatus -> Bool
allProven v = all (== Proven) v

||| Proof that a certificate is *complete*: every one of its `n` levels is
||| `Proven`. A single `Refuted`/`Skipped`/`Timeout` makes this uninhabited —
||| the obligation `So (allProven v)` is genuine, not a free assertion.
public export
data CertifiedComplete : Vect n ProofStatus -> Type where
  Complete : {v : Vect n ProofStatus} -> So (allProven v) -> CertifiedComplete v

||| Decide certificate completeness, returning a real proof or Nothing.
public export
checkComplete : (v : Vect n ProofStatus) -> Maybe (CertifiedComplete v)
checkComplete v =
  case choose (allProven v) of
    Left ok => Just (Complete ok)
    Right _ => Nothing
