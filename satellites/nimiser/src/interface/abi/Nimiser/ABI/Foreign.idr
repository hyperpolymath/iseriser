-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Nimiser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. These functions bridge between
||| the Rust CLI orchestrator and the Nim-generated C library.
|||
||| The Nim compiler (`nim c --app:lib`) produces a C shared/static library
||| with functions annotated by `{.exportc.}`. This FFI layer provides
||| type-safe access to those exported functions.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Nimiser.ABI.Foreign

import Nimiser.ABI.Types
import Nimiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the Nimiser runtime and Nim GC
||| Returns a handle to the library instance, or Nothing on failure.
||| The Nim runtime requires initialisation before any exported functions
||| can be called (NimMain() or equivalent).
export
%foreign "C:nimiser_init, libnimiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources and shut down Nim GC
export
%foreign "C:nimiser_free, libnimiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- String Marshalling (declared early; used by the generation wrappers below)
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

--------------------------------------------------------------------------------
-- Nim Compilation Pipeline
--------------------------------------------------------------------------------

||| Invoke the Nim compiler on generated source code
||| Parameters:
|||   handle   - library handle
|||   nimSrc   - path to generated Nim source file (C string)
|||   backend  - backend selector: 0=c, 1=cpp, 2=objc, 3=js
|||   optimise - optimisation level: 0=none, 1=speed, 2=size
||| Returns: 0 on success, error code on failure
export
%foreign "C:nimiser_compile, libnimiser"
prim__compile : Bits64 -> String -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper for Nim compilation
export
compile : Handle -> (nimSource : String) -> CBackend -> IO (Either Result ())
compile h src backend = do
  let backendCode = case backend.target of
                      "c"   => 0
                      "cpp" => 1
                      "objc" => 2
                      _     => 0
  let optCode = case backend.optimisation of
                  "speed" => 1
                  "size"  => 2
                  _       => 0
  result <- primIO (prim__compile (handlePtr h) src backendCode optCode)
  pure $ case result of
    0 => Right ()
    5 => Left CompilationFailed
    n => Left Error

||| Generate Nim template code from a template definition
||| Returns a C string containing generated Nim source, or null on error.
export
%foreign "C:nimiser_gen_template, libnimiser"
prim__genTemplate : Bits64 -> String -> Bits32 -> Bits32 -> Bits32 -> PrimIO Bits64

||| Safe wrapper for template generation
export
genTemplate : Handle -> NimTemplate -> IO (Either Result String)
genTemplate h tmpl = do
  ptr <- primIO (prim__genTemplate
                   (handlePtr h)
                   tmpl.name
                   (cast tmpl.typeParams)
                   (cast tmpl.valueParams)
                   (if tmpl.exported then 1 else 0))
  if ptr == 0
    then pure (Left TemplateError)
    else do
      let str = prim__getString ptr
      pure (Right str)

||| Generate Nim macro code from a macro definition
||| Returns a C string containing generated Nim source, or null on error.
export
%foreign "C:nimiser_gen_macro, libnimiser"
prim__genMacro : Bits64 -> String -> Bits32 -> Bits32 -> PrimIO Bits64

||| Safe wrapper for macro generation
export
genMacro : Handle -> NimMacro -> IO (Either Result String)
genMacro h mac = do
  ptr <- primIO (prim__genMacro
                   (handlePtr h)
                   mac.name
                   (cast mac.astParams)
                   (if mac.generatesExport then 1 else 0))
  if ptr == 0
    then pure (Left MacroError)
    else do
      let str = prim__getString ptr
      pure (Right str)

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Free C string allocated by the Nim library
export
%foreign "C:nimiser_free_string, libnimiser"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:nimiser_get_string, libnimiser"
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
-- Nim AST Inspection
--------------------------------------------------------------------------------

||| Dump the compile-time AST of a generated Nim source file
||| Useful for debugging macro expansion and template instantiation.
export
%foreign "C:nimiser_dump_ast, libnimiser"
prim__dumpAST : Bits64 -> String -> PrimIO Bits64

||| Safe wrapper for AST dump
export
dumpAST : Handle -> (nimSource : String) -> IO (Maybe String)
dumpAST h src = do
  ptr <- primIO (prim__dumpAST (handlePtr h) src)
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Generated Library Inspection
--------------------------------------------------------------------------------

||| List exported symbols from a Nim-generated C library
export
%foreign "C:nimiser_list_exports, libnimiser"
prim__listExports : Bits64 -> String -> PrimIO Bits64

||| Safe wrapper to list exported symbols
export
listExports : Handle -> (libraryPath : String) -> IO (Maybe String)
listExports h libPath = do
  ptr <- primIO (prim__listExports (handlePtr h) libPath)
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Array/Buffer Operations
--------------------------------------------------------------------------------

||| Process array data through a Nim-generated function
export
%foreign "C:nimiser_process_array, libnimiser"
prim__processArray : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe array processor
export
processArray : Handle -> (buffer : Bits64) -> (len : Bits32) -> IO (Either Result ())
processArray h buf len = do
  result <- primIO (prim__processArray (handlePtr h) buf len)
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
    resultFromInt 5 = Just CompilationFailed
    resultFromInt 6 = Just TemplateError
    resultFromInt 7 = Just MacroError
    resultFromInt _ = Nothing

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:nimiser_last_error, libnimiser"
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
errorDescription Ok                = "Success"
errorDescription Error             = "Generic error"
errorDescription InvalidParam      = "Invalid parameter"
errorDescription OutOfMemory       = "Out of memory"
errorDescription NullPointer       = "Null pointer"
errorDescription CompilationFailed = "Nim compilation failed"
errorDescription TemplateError     = "Nim template instantiation error"
errorDescription MacroError        = "Nim macro expansion error"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:nimiser_version, libnimiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info (includes Nim compiler version)
export
%foreign "C:nimiser_build_info, libnimiser"
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

||| Callback function type (C ABI)
public export
Callback : Type
Callback = Bits64 -> Bits32 -> Bits32

||| Register a callback for compilation events (progress, warnings, errors)
export
%foreign "C:nimiser_register_callback, libnimiser"
prim__registerCallback : Bits64 -> AnyPtr -> PrimIO Bits32

-- TODO: Implement safe callback registration.
-- The callback must be wrapped via a proper FFI callback mechanism.
-- Do NOT use cast -- it is banned per project safety standards.
-- See: https://idris2.readthedocs.io/en/latest/ffi/ffi.html#callbacks

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:nimiser_is_initialized, libnimiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)

||| Check if Nim compiler is available on the system
export
%foreign "C:nimiser_nim_available, libnimiser"
prim__nimAvailable : PrimIO Bits32

||| Check Nim compiler availability
export
nimAvailable : IO Bool
nimAvailable = do
  result <- primIO prim__nimAvailable
  pure (result /= 0)

||| Get Nim compiler version string
export
%foreign "C:nimiser_nim_version, libnimiser"
prim__nimVersion : PrimIO Bits64

||| Get the version of the Nim compiler on this system
export
nimVersion : IO (Maybe String)
nimVersion = do
  ptr <- primIO prim__nimVersion
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))
