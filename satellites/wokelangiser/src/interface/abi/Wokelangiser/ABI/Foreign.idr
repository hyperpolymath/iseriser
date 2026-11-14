-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Wokelangiser
|||
||| Declares all C-compatible functions implemented in the Zig FFI layer.
||| Covers consent injection, accessibility checking, i18n formatting,
||| and cultural sensitivity analysis.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Wokelangiser.ABI.Foreign

import Wokelangiser.ABI.Types
import Wokelangiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the wokelangiser library.
||| Returns a handle to the library instance, or Nothing on failure.
export
%foreign "C:wokelangiser_init, libwokelangiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources
export
%foreign "C:wokelangiser_free, libwokelangiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Consent Operations
--------------------------------------------------------------------------------

||| Inject a consent point into the target source at the given location.
||| The consent_type parameter encodes ConsentType (0=OptIn, 1=OptOut, etc.).
||| The location_ptr points to a C string describing the source location.
export
%foreign "C:wokelangiser_inject_consent, libwokelangiser"
prim__injectConsent : Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for consent injection
export
injectConsent : Handle -> ConsentType -> (locationPtr : Bits64) -> IO (Either Result ())
injectConsent h ct locPtr = do
  result <- primIO (prim__injectConsent (handlePtr h) (consentToInt ct) locPtr)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

||| Check whether consent has been granted for a specific operation.
||| Returns Ok (0) if consent is active, ConsentRequired (5) if not.
export
%foreign "C:wokelangiser_check_consent, libwokelangiser"
prim__checkConsent : Bits64 -> Bits32 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for consent checking
export
checkConsent : Handle -> ConsentType -> (subjectId : Bits64) -> IO (Either Result ())
checkConsent h ct subjectId = do
  result <- primIO (prim__checkConsent (handlePtr h) (consentToInt ct) subjectId)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

||| Record a consent state transition in the audit trail.
||| The from/to states are encoded as Bits32 (0=Pending, 1=Granted, 2=Active, 3=Revoked).
export
%foreign "C:wokelangiser_record_consent_transition, libwokelangiser"
prim__recordConsentTransition : Bits64 -> Bits64 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for consent transition recording
export
recordConsentTransition : Handle -> (subjectId : Bits64) -> (fromState : Bits32) -> (toState : Bits32) -> IO (Either Result ())
recordConsentTransition h subjectId from to = do
  result <- primIO (prim__recordConsentTransition (handlePtr h) subjectId from to)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

--------------------------------------------------------------------------------
-- Accessibility Operations
--------------------------------------------------------------------------------

||| Check whether a UI element meets the specified WCAG level.
||| The element_ptr points to a serialised AccessibilityRecord.
||| Returns Ok if compliant, AccessibilityFailed if not.
export
%foreign "C:wokelangiser_check_accessibility, libwokelangiser"
prim__checkAccessibility : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for accessibility checking
export
checkAccessibility : Handle -> (elementPtr : Bits64) -> WCAGLevel -> IO (Either Result ())
checkAccessibility h elemPtr level = do
  result <- primIO (prim__checkAccessibility (handlePtr h) elemPtr (wcagToInt level))
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

||| Annotate a UI element with accessibility metadata.
||| Writes ARIA label, role, focus order, and contrast ratio into the record.
export
%foreign "C:wokelangiser_annotate_element, libwokelangiser"
prim__annotateElement : Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for element annotation
export
annotateElement : Handle -> (elementPtr : Bits64) -> (ariaLabelPtr : Bits64) -> (rolePtr : Bits64) -> (focusOrder : Bits32) -> (contrastRatio : Bits32) -> IO (Either Result ())
annotateElement h elemPtr ariaPtr rolePtr focus contrast = do
  result <- primIO (prim__annotateElement (handlePtr h) elemPtr ariaPtr rolePtr focus contrast)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

||| Calculate the contrast ratio between two colours.
||| Colours are encoded as 24-bit RGB (0xRRGGBB).
||| Returns the ratio * 100 (e.g. 450 = 4.50:1).
export
%foreign "C:wokelangiser_contrast_ratio, libwokelangiser"
prim__contrastRatio : Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for contrast ratio calculation
export
contrastRatio : (foreground : Bits32) -> (background : Bits32) -> IO Bits32
contrastRatio fg bg = primIO (prim__contrastRatio fg bg)

--------------------------------------------------------------------------------
-- Internationalisation Operations
--------------------------------------------------------------------------------

||| Extract hardcoded strings from source code for localisation.
||| The source_ptr points to source file content; results written to output_ptr.
export
%foreign "C:wokelangiser_extract_strings, libwokelangiser"
prim__extractStrings : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for string extraction
export
extractStrings : Handle -> (sourcePtr : Bits64) -> (outputPtr : Bits64) -> IO (Either Result ())
extractStrings h srcPtr outPtr = do
  result <- primIO (prim__extractStrings (handlePtr h) srcPtr outPtr)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

||| Format a value according to the specified locale.
||| The hook_type selects the formatting rule; locale_ptr is a BCP 47 tag.
export
%foreign "C:wokelangiser_format_locale, libwokelangiser"
prim__formatLocale : Bits64 -> Bits32 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for locale formatting
export
formatLocale : Handle -> I18nHook -> (localePtr : Bits64) -> (valuePtr : Bits64) -> IO (Either Result ())
formatLocale h hook localePtr valPtr = do
  result <- primIO (prim__formatLocale (handlePtr h) (i18nHookToInt hook) localePtr valPtr)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

--------------------------------------------------------------------------------
-- Cultural Sensitivity Operations
--------------------------------------------------------------------------------

||| Check source content for culturally sensitive terms.
||| Returns Ok if no issues found, or a pointer to a report of flagged terms.
export
%foreign "C:wokelangiser_check_sensitivity, libwokelangiser"
prim__checkSensitivity : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for sensitivity checking
export
checkSensitivity : Handle -> (contentPtr : Bits64) -> CulturalContext -> IO (Either Result ())
checkSensitivity h contentPtr ctx = do
  result <- primIO (prim__checkSensitivity (handlePtr h) contentPtr (culturalToInt ctx))
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

||| Suggest culturally appropriate alternatives for flagged terms.
||| Writes suggestions to the output buffer.
export
%foreign "C:wokelangiser_suggest_alternative, libwokelangiser"
prim__suggestAlternative : Bits64 -> Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for alternative suggestions
export
suggestAlternative : Handle -> (termPtr : Bits64) -> (outputPtr : Bits64) -> CulturalContext -> IO (Either Result ())
suggestAlternative h termPtr outPtr ctx = do
  result <- primIO (prim__suggestAlternative (handlePtr h) termPtr outPtr (culturalToInt ctx))
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:wokelangiser_free_string, libwokelangiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:wokelangiser_get_string, libwokelangiser"
prim__getResult : Bits64 -> PrimIO Bits64

||| Safe string getter
export
getString : Handle -> IO (Maybe String)
getString h = do
  ptr <- primIO (prim__getResult (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:wokelangiser_last_error, libwokelangiser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok                  = "Success"
errorDescription Error               = "Generic error"
errorDescription InvalidParam        = "Invalid parameter"
errorDescription OutOfMemory         = "Out of memory"
errorDescription NullPointer         = "Null pointer"
errorDescription ConsentRequired     = "Consent not granted for this operation"
errorDescription AccessibilityFailed = "Element does not meet target WCAG level"
errorDescription I18nError           = "Locale not supported or string extraction failed"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:wokelangiser_version, libwokelangiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:wokelangiser_build_info, libwokelangiser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:wokelangiser_is_initialized, libwokelangiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
