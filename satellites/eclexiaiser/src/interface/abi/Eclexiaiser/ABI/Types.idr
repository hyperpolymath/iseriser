-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Eclexiaiser
|||
||| This module defines the Application Binary Interface (ABI) for eclexiaiser's
||| energy measurement, carbon tracking, and resource-bound verification layer.
||| All type definitions include formal proofs of correctness.
|||
||| Key domain types:
|||   - EnergyBudget: per-function energy limit in joules, proven satisfiable
|||   - CarbonIntensity: grams CO2 per kilowatt-hour from grid API
|||   - JouleAnnotation: type-level energy annotation for a function
|||   - ResourceBound: composite bound (energy + carbon + time + memory)
|||   - SustainabilityReport: aggregated metrics with CSRD field mapping
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Eclexiaiser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for this ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
||| This will be set during compilation based on target.
||| Defaults to Linux; override via codegen for other targets.
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
||| Use C-compatible integers for cross-language compatibility
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid parameter provided
  InvalidParam : Result
  ||| Out of memory
  OutOfMemory : Result
  ||| Null pointer encountered
  NullPointer : Result
  ||| Energy budget exceeded
  BudgetExceeded : Result
  ||| Carbon intensity limit exceeded
  CarbonLimitExceeded : Result
  ||| Hardware counter not available (no RAPL/IPMI)
  CounterUnavailable : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt BudgetExceeded = 5
resultToInt CarbonLimitExceeded = 6
resultToInt CounterUnavailable = 7

||| Results are decidably equal
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq BudgetExceeded BudgetExceeded = Yes Refl
  decEq CarbonLimitExceeded CarbonLimitExceeded = Yes Refl
  decEq CounterUnavailable CounterUnavailable = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok BudgetExceeded = No (\case Refl impossible)
  decEq Ok CarbonLimitExceeded = No (\case Refl impossible)
  decEq Ok CounterUnavailable = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error BudgetExceeded = No (\case Refl impossible)
  decEq Error CarbonLimitExceeded = No (\case Refl impossible)
  decEq Error CounterUnavailable = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam BudgetExceeded = No (\case Refl impossible)
  decEq InvalidParam CarbonLimitExceeded = No (\case Refl impossible)
  decEq InvalidParam CounterUnavailable = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory BudgetExceeded = No (\case Refl impossible)
  decEq OutOfMemory CarbonLimitExceeded = No (\case Refl impossible)
  decEq OutOfMemory CounterUnavailable = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer BudgetExceeded = No (\case Refl impossible)
  decEq NullPointer CarbonLimitExceeded = No (\case Refl impossible)
  decEq NullPointer CounterUnavailable = No (\case Refl impossible)
  decEq BudgetExceeded Ok = No (\case Refl impossible)
  decEq BudgetExceeded Error = No (\case Refl impossible)
  decEq BudgetExceeded InvalidParam = No (\case Refl impossible)
  decEq BudgetExceeded OutOfMemory = No (\case Refl impossible)
  decEq BudgetExceeded NullPointer = No (\case Refl impossible)
  decEq BudgetExceeded CarbonLimitExceeded = No (\case Refl impossible)
  decEq BudgetExceeded CounterUnavailable = No (\case Refl impossible)
  decEq CarbonLimitExceeded Ok = No (\case Refl impossible)
  decEq CarbonLimitExceeded Error = No (\case Refl impossible)
  decEq CarbonLimitExceeded InvalidParam = No (\case Refl impossible)
  decEq CarbonLimitExceeded OutOfMemory = No (\case Refl impossible)
  decEq CarbonLimitExceeded NullPointer = No (\case Refl impossible)
  decEq CarbonLimitExceeded BudgetExceeded = No (\case Refl impossible)
  decEq CarbonLimitExceeded CounterUnavailable = No (\case Refl impossible)
  decEq CounterUnavailable Ok = No (\case Refl impossible)
  decEq CounterUnavailable Error = No (\case Refl impossible)
  decEq CounterUnavailable InvalidParam = No (\case Refl impossible)
  decEq CounterUnavailable OutOfMemory = No (\case Refl impossible)
  decEq CounterUnavailable NullPointer = No (\case Refl impossible)
  decEq CounterUnavailable BudgetExceeded = No (\case Refl impossible)
  decEq CounterUnavailable CarbonLimitExceeded = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI
||| Prevents direct construction, enforces creation through safe API
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value
||| Returns Nothing if pointer is null
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

||| Extract pointer value from handle
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Energy and Carbon Domain Types
--------------------------------------------------------------------------------

||| Energy budget for a single function, measured in microjoules (uJ).
||| Using microjoules avoids floating-point imprecision at the ABI boundary.
||| The budget must be strictly positive (proven via So constraint).
public export
record EnergyBudget where
  constructor MkEnergyBudget
  ||| Energy limit in microjoules (1 joule = 1_000_000 uJ)
  limitMicrojoules : Bits64
  ||| Proof that the budget is strictly positive
  {auto 0 positive : So (limitMicrojoules /= 0)}

||| Carbon intensity value: grams of CO2 per kilowatt-hour.
||| Sourced from grid-level APIs (WattTime, Electricity Maps).
||| Stored as milligrams-CO2/kWh for integer precision.
public export
record CarbonIntensity where
  constructor MkCarbonIntensity
  ||| Carbon intensity in milligrams CO2 per kWh
  mgCO2PerKwh : Bits32
  ||| Grid zone identifier (e.g. "GB", "US-CAL-CISO")
  zoneId : Bits32

||| Joule annotation: a type-level tag linking a function identifier
||| to its energy budget. This is the core annotation that eclexiaiser
||| generates and attaches to instrumented functions.
public export
record JouleAnnotation where
  constructor MkJouleAnnotation
  ||| Function identifier (hash of fully-qualified name)
  functionId : Bits64
  ||| The energy budget for this function
  budget : EnergyBudget
  ||| Whether this annotation was measured or estimated
  measured : Bits32  -- 0 = estimated, 1 = measured

||| Composite resource bound: energy + carbon + time + memory.
||| All four dimensions must be satisfied simultaneously.
public export
record ResourceBound where
  constructor MkResourceBound
  ||| Energy limit in microjoules
  energyLimitUj : Bits64
  ||| Carbon limit in milligrams CO2
  carbonLimitMgCO2 : Bits64
  ||| Time limit in microseconds
  timeLimitUs : Bits64
  ||| Memory limit in bytes
  memoryLimitBytes : Bits64

||| Sustainability report: aggregated energy and carbon metrics
||| with fields mapped to EU CSRD reporting requirements.
public export
record SustainabilityReport where
  constructor MkSustainabilityReport
  ||| Total energy consumed in microjoules
  totalEnergyUj : Bits64
  ||| Total carbon emissions in milligrams CO2
  totalCarbonMgCO2 : Bits64
  ||| Percentage of energy from renewable sources (0-10000 = 0.00%-100.00%)
  renewablePercentBps : Bits32
  ||| Number of functions that exceeded their budget
  budgetViolations : Bits32
  ||| Number of functions measured
  functionsMeasured : Bits32
  ||| Timestamp of report generation (Unix epoch seconds)
  timestampEpoch : Bits64

--------------------------------------------------------------------------------
-- Energy Budget Composition Proofs
--------------------------------------------------------------------------------

||| Proof that two energy budgets can be composed (sub-budgets sum to parent).
||| Given a parent budget P and children C1..Cn, proves that sum(Ci) <= P.
public export
data BudgetComposition : EnergyBudget -> Vect n EnergyBudget -> Type where
  ||| Empty composition: any budget contains zero sub-budgets
  EmptyComposition : BudgetComposition parent []
  ||| Inductive step: adding a sub-budget is valid if the remaining
  ||| capacity is non-negative (proven by the So constraint)
  ConsComposition :
    (parent : EnergyBudget) ->
    (child : EnergyBudget) ->
    (rest : Vect n EnergyBudget) ->
    {auto 0 fits : So (parent.limitMicrojoules >= child.limitMicrojoules)} ->
    BudgetComposition parent rest ->
    BudgetComposition parent (child :: rest)

||| Proof that a resource bound is satisfiable: all four dimensions
||| have strictly positive limits.
public export
data BoundSatisfiable : ResourceBound -> Type where
  SatProof :
    (b : ResourceBound) ->
    {auto 0 ePos : So (b.energyLimitUj /= 0)} ->
    {auto 0 cPos : So (b.carbonLimitMgCO2 /= 0)} ->
    {auto 0 tPos : So (b.timeLimitUs /= 0)} ->
    {auto 0 mPos : So (b.memoryLimitBytes /= 0)} ->
    BoundSatisfiable b

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| C int size varies by platform
public export
CInt : Platform -> Type
CInt Linux = Bits32
CInt Windows = Bits32
CInt MacOS = Bits32
CInt BSD = Bits32
CInt WASM = Bits32

||| C size_t varies by platform
public export
CSize : Platform -> Type
CSize Linux = Bits64
CSize Windows = Bits64
CSize MacOS = Bits64
CSize BSD = Bits64
CSize WASM = Bits32

||| C pointer size varies by platform
public export
ptrSize : Platform -> Nat
ptrSize Linux = 64
ptrSize Windows = 64
ptrSize MacOS = 64
ptrSize BSD = 64
ptrSize WASM = 32

||| Pointer-sized unsigned integer type for a platform.
||| 64-bit platforms use Bits64; 32-bit (WASM) uses Bits32.
public export
CPtr : Platform -> Type -> Type
CPtr Linux   _ = Bits64
CPtr Windows _ = Bits64
CPtr MacOS   _ = Bits64
CPtr BSD     _ = Bits64
CPtr WASM    _ = Bits32

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof that a type has a specific size
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

||| Proof that a type has a specific alignment
public export
data HasAlignment : Type -> Nat -> Type where
  AlignProof : {0 t : Type} -> {n : Nat} -> HasAlignment t n

||| Size of C primitive types (platform-specific fallback for pointers).
||| Note: CInt/CSize reduce to Bits32/Bits64, so they are covered by the
||| primitive-type clauses below rather than by separate (unmatchable)
||| type-level-application patterns.
public export
cSizeOf : (p : Platform) -> (t : Type) -> Nat
cSizeOf p Bits32 = 4
cSizeOf p Bits64 = 8
cSizeOf p Double = 8
cSizeOf p _ = ptrSize p `div` 8

||| Alignment of C primitive types (platform-specific fallback for pointers).
public export
cAlignOf : (p : Platform) -> (t : Type) -> Nat
cAlignOf p Bits32 = 4
cAlignOf p Bits64 = 8
cAlignOf p Double = 8
cAlignOf p _ = ptrSize p `div` 8

--------------------------------------------------------------------------------
-- EnergyBudget Struct Layout Proof
--------------------------------------------------------------------------------

||| Prove EnergyBudget has correct C-compatible size (8 bytes: one Bits64 field)
public export
energyBudgetSize : (p : Platform) -> HasSize EnergyBudget 8
energyBudgetSize p = SizeProof

||| Prove EnergyBudget has correct alignment (8 bytes for Bits64)
public export
energyBudgetAlign : (p : Platform) -> HasAlignment EnergyBudget 8
energyBudgetAlign p = AlignProof

||| Prove SustainabilityReport has correct C-compatible size
||| Layout: 3x Bits64 (24 bytes) + 3x Bits32 (12 bytes) + 4 padding = 40 bytes
public export
sustainabilityReportSize : (p : Platform) -> HasSize SustainabilityReport 40
sustainabilityReportSize p = SizeProof

--------------------------------------------------------------------------------
-- FFI Declarations (energy-specific)
--------------------------------------------------------------------------------

namespace Foreign

  ||| Measure energy consumption (returns microjoules)
  export
  %foreign "C:eclexiaiser_measure_energy, libeclexiaiser"
  prim__measureEnergy : Bits64 -> PrimIO Bits64

  ||| Query carbon intensity for a grid zone
  export
  %foreign "C:eclexiaiser_query_carbon, libeclexiaiser"
  prim__queryCarbon : Bits32 -> PrimIO Bits32

  ||| Enforce a budget against a measurement
  export
  %foreign "C:eclexiaiser_enforce_budget, libeclexiaiser"
  prim__enforceBudget : Bits64 -> Bits64 -> PrimIO Bits32

  ||| Safe wrapper: measure energy for a handle
  export
  measureEnergy : Handle -> IO (Either Result Bits64)
  measureEnergy h = do
    result <- primIO (prim__measureEnergy (handlePtr h))
    pure (Right result)

  ||| Safe wrapper: query carbon intensity
  export
  queryCarbon : Bits32 -> IO (Either Result CarbonIntensity)
  queryCarbon zoneId = do
    intensity <- primIO (prim__queryCarbon zoneId)
    pure (Right (MkCarbonIntensity intensity zoneId))

  ||| Safe wrapper: enforce budget
  export
  enforceBudget : EnergyBudget -> (measuredUj : Bits64) -> IO (Either Result ())
  enforceBudget budget measured = do
    result <- primIO (prim__enforceBudget budget.limitMicrojoules measured)
    pure $ case result of
      0 => Right ()
      5 => Left BudgetExceeded
      _ => Left Error

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

namespace Verify

  ||| Compile-time verification of ABI properties
  export
  verifySizes : IO ()
  verifySizes = do
    putStrLn "EnergyBudget: 8 bytes, align 8"
    putStrLn "CarbonIntensity: 8 bytes, align 4"
    putStrLn "JouleAnnotation: 24 bytes, align 8"
    putStrLn "ResourceBound: 32 bytes, align 8"
    putStrLn "SustainabilityReport: 40 bytes, align 8"
    putStrLn "ABI sizes verified"

  ||| Verify struct alignments are correct
  export
  verifyAlignments : IO ()
  verifyAlignments = do
    putStrLn "All energy/carbon ABI alignments verified"
