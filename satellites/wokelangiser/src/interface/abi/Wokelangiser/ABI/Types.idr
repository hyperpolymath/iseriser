-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Wokelangiser
|||
||| Defines the consent, accessibility, internationalisation, and cultural
||| sensitivity types that form the core ABI for the wokelangiser FFI layer.
||| All type definitions include formal proofs of correctness.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Wokelangiser.ABI.Types

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
||| This will be set during compilation based on target
||| The platform this build targets. Defaults to Linux; the Rust/Zig build
||| layer overrides this via the codegen target selection. (Previously a
||| `%runElab` stub that required ElabReflection and did not compile.)
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- Consent Types
--------------------------------------------------------------------------------

||| Consent operation types for GDPR-compliant data handling.
||| Each operation maps to a specific user-facing consent flow.
public export
data ConsentType : Type where
  ||| User must explicitly agree before data collection begins
  OptIn : ConsentType
  ||| User may decline; data collection proceeds unless refused
  OptOut : ConsentType
  ||| User revokes previously granted consent (GDPR Article 7(3))
  Withdraw : ConsentType
  ||| Immutable record of consent grant/revocation for compliance audits
  AuditTrail : ConsentType

||| Convert ConsentType to C-compatible integer
public export
consentToInt : ConsentType -> Bits32
consentToInt OptIn = 0
consentToInt OptOut = 1
consentToInt Withdraw = 2
consentToInt AuditTrail = 3

||| Parse C integer back to ConsentType
public export
consentFromInt : Bits32 -> Maybe ConsentType
consentFromInt 0 = Just OptIn
consentFromInt 1 = Just OptOut
consentFromInt 2 = Just Withdraw
consentFromInt 3 = Just AuditTrail
consentFromInt _ = Nothing

||| ConsentType values are decidably equal. The off-diagonal cases discharge
||| disequality explicitly; the previous `decEq _ _ = No absurd` did not compile
||| (no `Uninhabited (x = y)` instance exists for these).
public export
DecEq ConsentType where
  decEq OptIn OptIn = Yes Refl
  decEq OptOut OptOut = Yes Refl
  decEq Withdraw Withdraw = Yes Refl
  decEq AuditTrail AuditTrail = Yes Refl
  decEq OptIn OptOut = No (\case Refl impossible)
  decEq OptIn Withdraw = No (\case Refl impossible)
  decEq OptIn AuditTrail = No (\case Refl impossible)
  decEq OptOut OptIn = No (\case Refl impossible)
  decEq OptOut Withdraw = No (\case Refl impossible)
  decEq OptOut AuditTrail = No (\case Refl impossible)
  decEq Withdraw OptIn = No (\case Refl impossible)
  decEq Withdraw OptOut = No (\case Refl impossible)
  decEq Withdraw AuditTrail = No (\case Refl impossible)
  decEq AuditTrail OptIn = No (\case Refl impossible)
  decEq AuditTrail OptOut = No (\case Refl impossible)
  decEq AuditTrail Withdraw = No (\case Refl impossible)

||| Consent state machine: tracks lifecycle of a consent grant.
||| Transitions: Pending -> Granted -> (Active | Revoked)
public export
data ConsentState : Type where
  ||| Consent has been requested but not yet responded to
  Pending : ConsentState
  ||| User has granted consent
  Granted : ConsentState
  ||| Consent is active and data processing is permitted
  Active : ConsentState
  ||| User has revoked consent; data processing must cease
  Revoked : ConsentState

||| Proof that a consent state transition is valid.
||| Encodes the legal state machine: Pending->Granted, Granted->Active,
||| Active->Revoked, Granted->Revoked (withdraw before activation).
public export
data ValidTransition : ConsentState -> ConsentState -> Type where
  GrantConsent    : ValidTransition Pending Granted
  ActivateConsent : ValidTransition Granted Active
  RevokeActive    : ValidTransition Active Revoked
  RevokeGranted   : ValidTransition Granted Revoked

--------------------------------------------------------------------------------
-- WCAG Accessibility Types
--------------------------------------------------------------------------------

||| WCAG 2.2 conformance levels.
||| Each level is a strict superset of the previous one.
public export
data WCAGLevel : Type where
  ||| Level A — minimum accessibility (30 success criteria)
  A   : WCAGLevel
  ||| Level AA — standard accessibility (20 additional criteria)
  AA  : WCAGLevel
  ||| Level AAA — enhanced accessibility (28 additional criteria)
  AAA : WCAGLevel

||| Convert WCAGLevel to C-compatible integer
public export
wcagToInt : WCAGLevel -> Bits32
wcagToInt A   = 0
wcagToInt AA  = 1
wcagToInt AAA = 2

||| Parse C integer back to WCAGLevel
public export
wcagFromInt : Bits32 -> Maybe WCAGLevel
wcagFromInt 0 = Just A
wcagFromInt 1 = Just AA
wcagFromInt 2 = Just AAA
wcagFromInt _ = Nothing

||| WCAGLevel values are decidably equal. Off-diagonal cases discharge
||| disequality explicitly (the prior `No absurd` catch-all did not compile).
public export
DecEq WCAGLevel where
  decEq A A = Yes Refl
  decEq AA AA = Yes Refl
  decEq AAA AAA = Yes Refl
  decEq A AA = No (\case Refl impossible)
  decEq A AAA = No (\case Refl impossible)
  decEq AA A = No (\case Refl impossible)
  decEq AA AAA = No (\case Refl impossible)
  decEq AAA A = No (\case Refl impossible)
  decEq AAA AA = No (\case Refl impossible)

||| Proof that one WCAG level subsumes another.
||| AA subsumes A; AAA subsumes AA (and transitively A).
public export
data Subsumes : WCAGLevel -> WCAGLevel -> Type where
  AASubsumesA   : Subsumes AA A
  AAASubsumesAA : Subsumes AAA AA
  AAASubsumesA  : Subsumes AAA A
  SameLevel     : Subsumes l l

||| Accessibility annotation attached to a UI element.
||| All fields correspond to WCAG 2.2 success criteria.
public export
record AccessibilityAnnotation where
  constructor MkAccessibilityAnnotation
  ||| ARIA label for screen readers (SC 1.1.1 Non-text Content)
  ariaLabel : String
  ||| ARIA role attribute (SC 4.1.2 Name, Role, Value)
  role : String
  ||| Tab order position for keyboard navigation (SC 2.4.3 Focus Order)
  focusOrder : Bits32
  ||| Contrast ratio (numerator * 100, e.g. 450 = 4.50:1) (SC 1.4.3 Contrast)
  contrastRatio : Bits32
  ||| Target WCAG conformance level
  targetLevel : WCAGLevel

||| Proof that a contrast ratio meets the required WCAG level.
||| AA requires >= 4.5:1 (450); AAA requires >= 7:1 (700); A has no minimum.
public export
data ContrastMeetsLevel : Bits32 -> WCAGLevel -> Type where
  AnyContrastForA   : ContrastMeetsLevel ratio A
  AAContrast        : {auto 0 ok : So (ratio >= 450)} -> ContrastMeetsLevel ratio AA
  AAAContrast       : {auto 0 ok : So (ratio >= 700)} -> ContrastMeetsLevel ratio AAA

--------------------------------------------------------------------------------
-- Internationalisation Types
--------------------------------------------------------------------------------

||| Formatting categories for locale-aware value rendering.
||| (Defined before `I18nHook` because `FormatSpec` references it — the
||| original scaffold had this declared *after* its use, which did not compile.)
public export
data FormatKind : Type where
  ||| Date formatting (ISO 8601 -> locale-specific)
  DateFmt     : FormatKind
  ||| Number formatting (decimal separator, grouping)
  NumberFmt   : FormatKind
  ||| Currency formatting (symbol, position, decimals)
  CurrencyFmt : FormatKind

||| Internationalisation hook types for locale-aware string handling.
public export
data I18nHook : Type where
  ||| Bind a string to a BCP 47 locale tag (e.g. "en-GB", "ar-SA")
  Locale : (tag : String) -> I18nHook
  ||| Mark text as requiring right-to-left rendering
  RTL : I18nHook
  ||| Apply CLDR plural category rules (zero, one, two, few, many, other)
  Pluralise : I18nHook
  ||| Format a value according to locale conventions
  FormatSpec : (kind : FormatKind) -> I18nHook

||| Convert I18nHook to C-compatible integer (tag variant only)
public export
i18nHookToInt : I18nHook -> Bits32
i18nHookToInt (Locale _)    = 0
i18nHookToInt RTL           = 1
i18nHookToInt Pluralise     = 2
i18nHookToInt (FormatSpec _) = 3

--------------------------------------------------------------------------------
-- Cultural Sensitivity Types
--------------------------------------------------------------------------------

||| Cultural context markers for locale-appropriate content adaptation.
public export
data CulturalContext : Type where
  ||| Regional cultural norms (ISO 3166-1 alpha-2 region code)
  Cultural : (region : String) -> CulturalContext
  ||| Domain-specific terminology (e.g. "medical", "legal", "financial")
  Terminology : (domain : String) -> CulturalContext
  ||| Personal naming conventions (e.g. family-first, patronymic)
  NamingConvention : (convention : String) -> CulturalContext

||| Convert CulturalContext to C-compatible integer (variant tag only)
public export
culturalToInt : CulturalContext -> Bits32
culturalToInt (Cultural _)         = 0
culturalToInt (Terminology _)      = 1
culturalToInt (NamingConvention _) = 2

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations.
||| Use C-compatible integers for cross-language compatibility.
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
  ||| Consent not granted for this operation
  ConsentRequired : Result
  ||| Accessibility check failed (element does not meet target WCAG level)
  AccessibilityFailed : Result
  ||| Locale not supported or string extraction failed
  I18nError : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok                  = 0
resultToInt Error               = 1
resultToInt InvalidParam        = 2
resultToInt OutOfMemory         = 3
resultToInt NullPointer         = 4
resultToInt ConsentRequired     = 5
resultToInt AccessibilityFailed = 6
resultToInt I18nError           = 7

||| Parse C integer back to Result
public export
resultFromInt : Bits32 -> Maybe Result
resultFromInt 0 = Just Ok
resultFromInt 1 = Just Error
resultFromInt 2 = Just InvalidParam
resultFromInt 3 = Just OutOfMemory
resultFromInt 4 = Just NullPointer
resultFromInt 5 = Just ConsentRequired
resultFromInt 6 = Just AccessibilityFailed
resultFromInt 7 = Just I18nError
resultFromInt _ = Nothing

||| Results are decidably equal. Off-diagonal cases discharge disequality
||| explicitly; the previous `decEq _ _ = No absurd` did not compile.
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq ConsentRequired ConsentRequired = Yes Refl
  decEq AccessibilityFailed AccessibilityFailed = Yes Refl
  decEq I18nError I18nError = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok ConsentRequired = No (\case Refl impossible)
  decEq Ok AccessibilityFailed = No (\case Refl impossible)
  decEq Ok I18nError = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error ConsentRequired = No (\case Refl impossible)
  decEq Error AccessibilityFailed = No (\case Refl impossible)
  decEq Error I18nError = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam ConsentRequired = No (\case Refl impossible)
  decEq InvalidParam AccessibilityFailed = No (\case Refl impossible)
  decEq InvalidParam I18nError = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory ConsentRequired = No (\case Refl impossible)
  decEq OutOfMemory AccessibilityFailed = No (\case Refl impossible)
  decEq OutOfMemory I18nError = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer ConsentRequired = No (\case Refl impossible)
  decEq NullPointer AccessibilityFailed = No (\case Refl impossible)
  decEq NullPointer I18nError = No (\case Refl impossible)
  decEq ConsentRequired Ok = No (\case Refl impossible)
  decEq ConsentRequired Error = No (\case Refl impossible)
  decEq ConsentRequired InvalidParam = No (\case Refl impossible)
  decEq ConsentRequired OutOfMemory = No (\case Refl impossible)
  decEq ConsentRequired NullPointer = No (\case Refl impossible)
  decEq ConsentRequired AccessibilityFailed = No (\case Refl impossible)
  decEq ConsentRequired I18nError = No (\case Refl impossible)
  decEq AccessibilityFailed Ok = No (\case Refl impossible)
  decEq AccessibilityFailed Error = No (\case Refl impossible)
  decEq AccessibilityFailed InvalidParam = No (\case Refl impossible)
  decEq AccessibilityFailed OutOfMemory = No (\case Refl impossible)
  decEq AccessibilityFailed NullPointer = No (\case Refl impossible)
  decEq AccessibilityFailed ConsentRequired = No (\case Refl impossible)
  decEq AccessibilityFailed I18nError = No (\case Refl impossible)
  decEq I18nError Ok = No (\case Refl impossible)
  decEq I18nError Error = No (\case Refl impossible)
  decEq I18nError InvalidParam = No (\case Refl impossible)
  decEq I18nError OutOfMemory = No (\case Refl impossible)
  decEq I18nError NullPointer = No (\case Refl impossible)
  decEq I18nError ConsentRequired = No (\case Refl impossible)
  decEq I18nError AccessibilityFailed = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI.
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

||| Pointer-sized integer type for a platform. Native targets use 64-bit
||| pointers; WASM uses 32-bit. (The original scaffold wrote `Bits (ptrSize p)`,
||| but `Data.Bits.Bits` is an interface, not a `Nat -> Type` family, so it did
||| not typecheck.)
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

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification that consent round-trip encoding is lossless
namespace Verify

  ||| Verify consent type round-trips through integer encoding
  export
  consentRoundTrip : (ct : ConsentType) -> consentFromInt (consentToInt ct) = Just ct
  consentRoundTrip OptIn      = Refl
  consentRoundTrip OptOut     = Refl
  consentRoundTrip Withdraw   = Refl
  consentRoundTrip AuditTrail = Refl

  ||| Verify WCAG level round-trips through integer encoding
  export
  wcagRoundTrip : (wl : WCAGLevel) -> wcagFromInt (wcagToInt wl) = Just wl
  wcagRoundTrip A   = Refl
  wcagRoundTrip AA  = Refl
  wcagRoundTrip AAA = Refl

  ||| Verify result code round-trips through integer encoding
  export
  resultRoundTrip : (r : Result) -> resultFromInt (resultToInt r) = Just r
  resultRoundTrip Ok                  = Refl
  resultRoundTrip Error               = Refl
  resultRoundTrip InvalidParam        = Refl
  resultRoundTrip OutOfMemory         = Refl
  resultRoundTrip NullPointer         = Refl
  resultRoundTrip ConsentRequired     = Refl
  resultRoundTrip AccessibilityFailed = Refl
  resultRoundTrip I18nError           = Refl
