-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Anvomidaviser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer for ISU notation parsing,
||| program scoring, and rule validation.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in ffi/zig/

module Anvomidaviser.ABI.Foreign

import Anvomidaviser.ABI.Types
import Anvomidaviser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the anvomidaviser library
||| Returns a handle to the scoring engine instance, or Nothing on failure
export
%foreign "C:anvomidaviser_init, libanvomidaviser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources
export
%foreign "C:anvomidaviser_free, libanvomidaviser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- ISU Element Parsing
--------------------------------------------------------------------------------

||| Parse an ISU element code string (e.g. "3Lz", "CCoSp4", "StSq3")
||| Returns a handle to the parsed element, or null on parse failure
export
%foreign "C:anvomidaviser_parse_element, libanvomidaviser"
prim__parseElement : String -> PrimIO Bits64

||| Safe element parser
export
parseElement : String -> IO (Maybe Handle)
parseElement code = do
  ptr <- primIO (prim__parseElement code)
  pure (createHandle ptr)

||| Parse a combination element (e.g. "3Lz+3T", "3F+2T+2Lo")
export
%foreign "C:anvomidaviser_parse_combination, libanvomidaviser"
prim__parseCombination : String -> PrimIO Bits64

||| Safe combination parser
export
parseCombination : String -> IO (Maybe Handle)
parseCombination code = do
  ptr <- primIO (prim__parseCombination code)
  pure (createHandle ptr)

||| Parse a full ISU protocol (XML or IJS format)
export
%foreign "C:anvomidaviser_parse_protocol, libanvomidaviser"
prim__parseProtocol : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe protocol parser — takes a buffer of ISU protocol data
export
parseProtocol : Handle -> (buffer : Bits64) -> (len : Bits32) -> IO (Either Result ())
parseProtocol h buf len = do
  result <- primIO (prim__parseProtocol buf len)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error
  where
    resultFromInt : Bits32 -> Maybe Result
    resultFromInt 0 = Just Ok
    resultFromInt 1 = Just Error
    resultFromInt 2 = Just InvalidParam
    resultFromInt 3 = Just OutOfMemory
    resultFromInt 4 = Just NullPointer
    resultFromInt 5 = Just RuleViolation
    resultFromInt _ = Nothing

--------------------------------------------------------------------------------
-- Scoring Operations
--------------------------------------------------------------------------------

||| Look up the base value for an element code
||| Returns the base value in hundredths of a point (e.g. 590 = 5.90)
export
%foreign "C:anvomidaviser_base_value, libanvomidaviser"
prim__baseValue : Bits64 -> PrimIO Bits32

||| Safe base value lookup
export
baseValue : Handle -> IO (Either Result Bits32)
baseValue h = do
  result <- primIO (prim__baseValue (handlePtr h))
  pure (Right result)

||| Calculate the GOE adjustment for an element given a GOE grade
||| Returns the adjustment in hundredths of a point
export
%foreign "C:anvomidaviser_goe_adjustment, libanvomidaviser"
prim__goeAdjustment : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe GOE adjustment calculation
export
goeAdjustment : Handle -> Bits32 -> IO (Either Result Bits32)
goeAdjustment h goe = do
  result <- primIO (prim__goeAdjustment (handlePtr h) goe)
  pure (Right result)

||| Score a complete program and return the total segment score
export
%foreign "C:anvomidaviser_score_program, libanvomidaviser"
prim__scoreProgram : Bits64 -> PrimIO Bits32

||| Safe program scorer
export
scoreProgram : Handle -> IO (Either Result Bits32)
scoreProgram h = do
  result <- primIO (prim__scoreProgram (handlePtr h))
  pure (Right result)

--------------------------------------------------------------------------------
-- Rule Validation
--------------------------------------------------------------------------------

||| Validate a program against ISU technical rules
||| Returns 0 if valid, 1 if violations found, error code otherwise
export
%foreign "C:anvomidaviser_validate_program, libanvomidaviser"
prim__validateProgram : Bits64 -> PrimIO Bits32

||| Safe program validator
export
validateProgram : Handle -> IO (Either Result Bool)
validateProgram h = do
  result <- primIO (prim__validateProgram (handlePtr h))
  pure $ case result of
    0 => Right True   -- Program is valid
    1 => Right False  -- Program has rule violations
    _ => Left Error

||| Check for repeated jump violations (Zayak rule)
||| A jump of more than 2 rotations may be repeated only once, and one must
||| be in combination
export
%foreign "C:anvomidaviser_check_zayak, libanvomidaviser"
prim__checkZayak : Bits64 -> PrimIO Bits32

||| Safe Zayak rule checker
export
checkZayak : Handle -> IO (Either Result Bool)
checkZayak h = do
  result <- primIO (prim__checkZayak (handlePtr h))
  pure $ case result of
    0 => Right True   -- No Zayak violation
    1 => Right False  -- Zayak violation detected
    _ => Left Error

||| Verify element count requirements (short program vs free skate)
export
%foreign "C:anvomidaviser_check_element_count, libanvomidaviser"
prim__checkElementCount : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe element count checker
||| programType: 0 = short program, 1 = free skate
export
checkElementCount : Handle -> (programType : Bits32) -> IO (Either Result Bool)
checkElementCount h pt = do
  result <- primIO (prim__checkElementCount (handlePtr h) pt)
  pure $ case result of
    0 => Right True   -- Correct element count
    1 => Right False  -- Too many or too few elements
    _ => Left Error

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:anvomidaviser_free_string, libanvomidaviser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library (e.g. formatted score sheet)
export
%foreign "C:anvomidaviser_get_string, libanvomidaviser"
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
-- Anvomidav Codegen
--------------------------------------------------------------------------------

||| Generate Anvomidav formal program description from parsed elements
export
%foreign "C:anvomidaviser_generate_anvomidav, libanvomidaviser"
prim__generateAnvomidav : Bits64 -> PrimIO Bits64

||| Safe Anvomidav codegen — returns the generated program source as a string
export
generateAnvomidav : Handle -> IO (Maybe String)
generateAnvomidav h = do
  ptr <- primIO (prim__generateAnvomidav (handlePtr h))
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
%foreign "C:anvomidaviser_last_error, libanvomidaviser"
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
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"
errorDescription RuleViolation = "ISU rule violation detected"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:anvomidaviser_version, libanvomidaviser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:anvomidaviser_build_info, libanvomidaviser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Callback Support
--------------------------------------------------------------------------------

||| Callback function type for scoring progress (C ABI)
public export
Callback : Type
Callback = Bits64 -> Bits32 -> Bits32

||| Register a callback for scoring progress
export
%foreign "C:anvomidaviser_register_callback, libanvomidaviser"
prim__registerCallback : Bits64 -> AnyPtr -> PrimIO Bits32

-- TODO: Implement safe callback registration.
-- The callback must be wrapped via a proper FFI callback mechanism.
-- Do NOT use cast — it is banned per project safety standards.
-- See: https://idris2.readthedocs.io/en/latest/ffi/ffi.html#callbacks

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:anvomidaviser_is_initialized, libanvomidaviser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
