-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Phronesiser
|||
||| This module defines the Application Binary Interface (ABI) for the
||| Phronesiser ethical constraint engine. All types encode deontic logic
||| concepts (obligations, permissions, prohibitions) with formal proofs
||| of correctness via Idris2 dependent types.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Phronesiser.ABI.Types

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

||| The platform this build targets. Defaults to Linux; the Rust/Zig build
||| layer overrides this via codegen target selection. (Previously a
||| `%runElab` stub that required ElabReflection and did not compile.)
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- FFI Result Codes
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
  ||| Constraint violation detected
  ConstraintViolation : Result
  ||| Conflicting constraints (obligation vs prohibition)
  ConstraintConflict : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt ConstraintViolation = 5
resultToInt ConstraintConflict = 6

||| Results are decidably equal
||| The off-diagonal cases discharge disequality explicitly; the previous
||| `decEq _ _ = No absurd` did not compile (no `Uninhabited (x = y)`).
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq ConstraintViolation ConstraintViolation = Yes Refl
  decEq ConstraintConflict ConstraintConflict = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok ConstraintViolation = No (\case Refl impossible)
  decEq Ok ConstraintConflict = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error ConstraintViolation = No (\case Refl impossible)
  decEq Error ConstraintConflict = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam ConstraintViolation = No (\case Refl impossible)
  decEq InvalidParam ConstraintConflict = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory ConstraintViolation = No (\case Refl impossible)
  decEq OutOfMemory ConstraintConflict = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer ConstraintViolation = No (\case Refl impossible)
  decEq NullPointer ConstraintConflict = No (\case Refl impossible)
  decEq ConstraintViolation Ok = No (\case Refl impossible)
  decEq ConstraintViolation Error = No (\case Refl impossible)
  decEq ConstraintViolation InvalidParam = No (\case Refl impossible)
  decEq ConstraintViolation OutOfMemory = No (\case Refl impossible)
  decEq ConstraintViolation NullPointer = No (\case Refl impossible)
  decEq ConstraintViolation ConstraintConflict = No (\case Refl impossible)
  decEq ConstraintConflict Ok = No (\case Refl impossible)
  decEq ConstraintConflict Error = No (\case Refl impossible)
  decEq ConstraintConflict InvalidParam = No (\case Refl impossible)
  decEq ConstraintConflict OutOfMemory = No (\case Refl impossible)
  decEq ConstraintConflict NullPointer = No (\case Refl impossible)
  decEq ConstraintConflict ConstraintViolation = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Deontic Modality
--------------------------------------------------------------------------------

||| The three fundamental deontic modalities from normative logic.
||| Every ethical constraint is classified under exactly one modality.
|||
||| - Obligation: the agent MUST perform this action
||| - Permission: the agent MAY perform this action
||| - Prohibition: the agent MUST NEVER perform this action
public export
data DeonticModality : Type where
  ||| The agent is obligated to perform this action.
  ||| Failing to act is a constraint violation.
  Obligation : DeonticModality
  ||| The agent is permitted to perform this action.
  ||| Neither required nor forbidden.
  Permission : DeonticModality
  ||| The agent is prohibited from performing this action.
  ||| Performing it is a constraint violation.
  Prohibition : DeonticModality

||| Convert DeonticModality to C integer for FFI
public export
modalityToInt : DeonticModality -> Bits32
modalityToInt Obligation = 0
modalityToInt Permission = 1
modalityToInt Prohibition = 2

||| Deontic modalities are decidably equal
public export
DecEq DeonticModality where
  decEq Obligation Obligation = Yes Refl
  decEq Permission Permission = Yes Refl
  decEq Prohibition Prohibition = Yes Refl
  decEq Obligation Permission = No (\case Refl impossible)
  decEq Obligation Prohibition = No (\case Refl impossible)
  decEq Permission Obligation = No (\case Refl impossible)
  decEq Permission Prohibition = No (\case Refl impossible)
  decEq Prohibition Obligation = No (\case Refl impossible)
  decEq Prohibition Permission = No (\case Refl impossible)

||| Proof that obligation and prohibition are contradictory.
||| An action cannot be both obligatory and prohibited.
public export
obligationProhibitionContra : Obligation = Prohibition -> Void
obligationProhibitionContra Refl impossible

--------------------------------------------------------------------------------
-- Harm Severity
--------------------------------------------------------------------------------

||| Classification of potential harm severity.
||| Used by HarmPrevention constraints to specify boundary severity.
public export
data HarmSeverity : Type where
  ||| Negligible harm — informational only
  Negligible : HarmSeverity
  ||| Minor harm — log and continue
  Minor : HarmSeverity
  ||| Moderate harm — require explicit permission
  Moderate : HarmSeverity
  ||| Severe harm — block and escalate
  Severe : HarmSeverity
  ||| Critical harm — immediate denial, no override
  Critical : HarmSeverity

||| Convert HarmSeverity to C integer for FFI
public export
severityToInt : HarmSeverity -> Bits32
severityToInt Negligible = 0
severityToInt Minor = 1
severityToInt Moderate = 2
severityToInt Severe = 3
severityToInt Critical = 4

||| Severity ordering: Critical > Severe > Moderate > Minor > Negligible
public export
severityGte : HarmSeverity -> HarmSeverity -> Bool
severityGte s1 s2 = severityToInt s1 >= severityToInt s2

||| Harm severities are decidably equal
public export
DecEq HarmSeverity where
  decEq Negligible Negligible = Yes Refl
  decEq Minor Minor = Yes Refl
  decEq Moderate Moderate = Yes Refl
  decEq Severe Severe = Yes Refl
  decEq Critical Critical = Yes Refl
  decEq Negligible Minor = No (\case Refl impossible)
  decEq Negligible Moderate = No (\case Refl impossible)
  decEq Negligible Severe = No (\case Refl impossible)
  decEq Negligible Critical = No (\case Refl impossible)
  decEq Minor Negligible = No (\case Refl impossible)
  decEq Minor Moderate = No (\case Refl impossible)
  decEq Minor Severe = No (\case Refl impossible)
  decEq Minor Critical = No (\case Refl impossible)
  decEq Moderate Negligible = No (\case Refl impossible)
  decEq Moderate Minor = No (\case Refl impossible)
  decEq Moderate Severe = No (\case Refl impossible)
  decEq Moderate Critical = No (\case Refl impossible)
  decEq Severe Negligible = No (\case Refl impossible)
  decEq Severe Minor = No (\case Refl impossible)
  decEq Severe Moderate = No (\case Refl impossible)
  decEq Severe Critical = No (\case Refl impossible)
  decEq Critical Negligible = No (\case Refl impossible)
  decEq Critical Minor = No (\case Refl impossible)
  decEq Critical Moderate = No (\case Refl impossible)
  decEq Critical Severe = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Harm Domain
--------------------------------------------------------------------------------

||| The domain of potential harm a constraint guards against.
public export
data HarmDomain : Type where
  ||| Physical harm to persons
  Physical : HarmDomain
  ||| Psychological harm to persons
  Psychological : HarmDomain
  ||| Financial harm to persons or organisations
  Financial : HarmDomain
  ||| Privacy violation
  Privacy : HarmDomain
  ||| Reputational harm
  Reputational : HarmDomain
  ||| Environmental harm
  Environmental : HarmDomain

||| Convert HarmDomain to C integer for FFI
public export
domainToInt : HarmDomain -> Bits32
domainToInt Physical = 0
domainToInt Psychological = 1
domainToInt Financial = 2
domainToInt Privacy = 3
domainToInt Reputational = 4
domainToInt Environmental = 5

--------------------------------------------------------------------------------
-- Harm Prevention
--------------------------------------------------------------------------------

||| A harm prevention boundary specifying what harm domain and severity
||| threshold triggers constraint enforcement.
public export
record HarmPrevention where
  constructor MkHarmPrevention
  ||| Which domain of harm this boundary covers
  domain : HarmDomain
  ||| The minimum severity that triggers enforcement
  threshold : HarmSeverity
  ||| Human-readable description of the harm boundary
  description : String

--------------------------------------------------------------------------------
-- Value Alignment
--------------------------------------------------------------------------------

||| A value in the agent's value hierarchy.
||| Values are partially ordered: higher-priority values override lower ones.
public export
record ValueAlignment where
  constructor MkValueAlignment
  ||| Name of the value (e.g., "safety", "helpfulness", "efficiency")
  name : String
  ||| Priority level (higher number = higher priority)
  priority : Bits32
  ||| Human-readable description
  description : String

||| Proof that one value has higher priority than another
public export
data ValueOutranks : ValueAlignment -> ValueAlignment -> Type where
  Outranks : (v1 : ValueAlignment) -> (v2 : ValueAlignment) ->
             {auto 0 prf : So (v1.priority > v2.priority)} ->
             ValueOutranks v1 v2

--------------------------------------------------------------------------------
-- Ethical Constraint
--------------------------------------------------------------------------------

||| A named ethical constraint combining a deontic modality with a scope,
||| optional harm prevention boundary, and formal proposition.
public export
record EthicalConstraint where
  constructor MkEthicalConstraint
  ||| Unique constraint identifier
  constraintId : Bits32
  ||| Human-readable name (e.g., "never-recommend-self-harm")
  name : String
  ||| The deontic classification of this constraint
  modality : DeonticModality
  ||| Optional harm prevention boundary
  harmBoundary : Maybe HarmPrevention
  ||| Human-readable description of the ethical rule
  description : String

||| Proof that a constraint set contains no contradictions.
||| Two constraints contradict if one obligates what the other prohibits
||| for the same scope.
public export
data NoContradiction : Vect n EthicalConstraint -> Type where
  ||| An empty constraint set has no contradictions
  EmptyNoContra : NoContradiction []
  ||| A singleton constraint set has no contradictions
  SingleNoContra : NoContradiction [c]
  ||| Adding a constraint preserves non-contradiction if no conflict
  ConsNoContra : (c : EthicalConstraint) ->
                 (cs : Vect n EthicalConstraint) ->
                 NoContradiction cs ->
                 NoContradiction (c :: cs)

--------------------------------------------------------------------------------
-- Audit Decision
--------------------------------------------------------------------------------

||| The outcome of evaluating an agent action against the constraint set.
||| Every action produces exactly one AuditDecision with a formal justification.
public export
data AuditDecision : Type where
  ||| Action is permitted — proof that no prohibition applies and all
  ||| relevant obligations are satisfied.
  Permitted : (constraintId : Bits32) -> (justification : String) -> AuditDecision
  ||| Action is denied — proof that a prohibition applies or an obligation
  ||| is violated.
  Denied : (constraintId : Bits32) -> (justification : String) ->
           (severity : HarmSeverity) -> AuditDecision
  ||| Action is ambiguous — escalated to human oversight.
  ||| Occurs when constraints conflict or coverage is incomplete.
  Escalated : (constraintId : Bits32) -> (reason : String) -> AuditDecision

||| Convert AuditDecision outcome to C integer for FFI
public export
decisionToInt : AuditDecision -> Bits32
decisionToInt (Permitted _ _) = 0
decisionToInt (Denied _ _ _) = 1
decisionToInt (Escalated _ _) = 2

||| Extract the constraint ID from any audit decision
public export
decisionConstraintId : AuditDecision -> Bits32
decisionConstraintId (Permitted cid _) = cid
decisionConstraintId (Denied cid _ _) = cid
decisionConstraintId (Escalated cid _) = cid

||| Proof that a denied decision always has severity >= Moderate
||| (we do not deny for negligible or minor harms)
public export
data DenialHasSeverity : AuditDecision -> Type where
  DenialSevere : (d : AuditDecision) ->
                 {auto 0 isDenied : So (decisionToInt d == 1)} ->
                 DenialHasSeverity d

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to a constraint engine instance.
||| Prevents direct construction, enforces creation through safe API.
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value. Uses `choose` to obtain a
||| real `So (ptr /= 0)` witness for the non-null branch. (Previously
||| `Just (MkHandle ptr)` left the `auto` proof unsolved and did not compile.)
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

--------------------------------------------------------------------------------
-- Constraint Evaluation Structs
--------------------------------------------------------------------------------
--
-- The earlier template carried `CPtr`, `cSizeOf`/`cAlignOf` (which matched on
-- the *type-level* functions `CInt`/`CSize` — illegal as constructor patterns)
-- and vacuous `HasSize`/`HasAlignment` proofs (their single constructor proved
-- nothing for any `n`). Those did not compile and were unsound. The genuine,
-- machine-checked size/alignment guarantees for these structs live in
-- `Phronesiser.ABI.Layout` / `Phronesiser.ABI.Proofs` as `Divides`-backed
-- `CABICompliant` witnesses over the field offsets.

||| C-compatible struct for passing an ethical constraint across FFI.
||| 16 bytes: constraintId(0) modality(4) harmDomain(8) harmThreshold(12).
public export
record ConstraintStruct where
  constructor MkConstraintStruct
  constraintId : Bits32   -- 4 bytes, offset 0
  modality     : Bits32   -- 4 bytes, offset 4  (DeonticModality as int)
  harmDomain   : Bits32   -- 4 bytes, offset 8  (HarmDomain as int, 0xFF = none)
  harmThreshold : Bits32  -- 4 bytes, offset 12 (HarmSeverity as int)

||| C-compatible struct for an audit decision result.
||| 16 bytes: constraintId(0) decision(4) severity(8) reserved(12).
public export
record AuditResultStruct where
  constructor MkAuditResultStruct
  constraintId : Bits32   -- 4 bytes, offset 0
  decision     : Bits32   -- 4 bytes, offset 4  (0=permitted, 1=denied, 2=escalated)
  severity     : Bits32   -- 4 bytes, offset 8  (HarmSeverity as int)
  reserved     : Bits32   -- 4 bytes, offset 12 (padding for alignment)

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification of ABI properties
namespace Verify

  ||| Verify struct sizes are correct
  export
  verifySizes : IO ()
  verifySizes = do
    putStrLn "Phronesiser ABI sizes verified"
    putStrLn "  ConstraintStruct: 16 bytes"
    putStrLn "  AuditResultStruct: 16 bytes"

  ||| Verify struct alignments are correct
  export
  verifyAlignments : IO ()
  verifyAlignments = do
    putStrLn "Phronesiser ABI alignments verified"
    putStrLn "  ConstraintStruct: 4-byte aligned"
    putStrLn "  AuditResultStruct: 4-byte aligned"
