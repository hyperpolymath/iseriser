-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for BQNiser
|||
||| This module declares all C-compatible functions for interfacing with
||| the CBQN runtime.  The Zig FFI layer (src/interface/ffi/) implements
||| a thin wrapper around CBQN's C API.
|||
||| CBQN C API reference: https://github.com/dzaima/CBQN/blob/master/include/bqnffi.h
|||
||| Key CBQN functions we wrap:
|||   bqn_init()           — initialise the CBQN runtime
|||   bqn_free()           — shut down the CBQN runtime
|||   bqn_eval(src)        — evaluate a BQN expression string
|||   bqn_call1(f, x)      — call a monadic BQN function
|||   bqn_call2(f, w, x)   — call a dyadic BQN function
|||   bqn_readF64Arr(v, buf) — read numeric array into f64 buffer
|||   bqn_toF64(v)         — extract scalar f64 from BQN value
|||   bqn_type(v)          — get type tag of a BQN value
|||   bqn_bound(v)         — get element count of a BQN array

module Bqniser.ABI.Foreign

import Bqniser.ABI.Types
import Bqniser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- CBQN Runtime Lifecycle
--------------------------------------------------------------------------------

||| Initialise the CBQN runtime.
||| Must be called before any other CBQN function.
||| Returns a handle to the runtime instance, or Nothing on failure.
export
%foreign "C:bqniser_init, libbqniser"
prim__init : PrimIO Bits64

||| Safe wrapper for CBQN runtime initialisation.
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Shut down the CBQN runtime and release all resources.
export
%foreign "C:bqniser_free, libbqniser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for CBQN runtime shutdown.
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- BQN Expression Evaluation
--------------------------------------------------------------------------------

||| Evaluate a BQN expression string.
||| Returns a CBQN value handle (BQNV), or 0 on error.
||| The expression is compiled and executed by CBQN's bytecode VM.
export
%foreign "C:bqniser_eval, libbqniser"
prim__eval : Bits64 -> String -> PrimIO Bits64

||| Safe wrapper: evaluate a BQN expression.
||| Example: eval handle "⌽ 1‿2‿3" evaluates to 3‿2‿1.
export
eval : Handle -> String -> IO (Either Result Bits64)
eval h expr = do
  result <- primIO (prim__eval (handlePtr h) expr)
  if result == 0
    then pure (Left EvalError)
    else pure (Right result)

--------------------------------------------------------------------------------
-- BQN Function Application
--------------------------------------------------------------------------------

||| Call a monadic BQN function: F x.
||| Both f and x are CBQN value handles (BQNV).
export
%foreign "C:bqniser_call1, libbqniser"
prim__call1 : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe monadic call: apply function f to argument x.
export
call1 : Handle -> (f : Bits64) -> (x : Bits64) -> IO (Either Result Bits64)
call1 h f x = do
  result <- primIO (prim__call1 (handlePtr h) f x)
  if result == 0
    then pure (Left Error)
    else pure (Right result)

||| Call a dyadic BQN function: w F x.
||| f, w, x are all CBQN value handles.
export
%foreign "C:bqniser_call2, libbqniser"
prim__call2 : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits64

||| Safe dyadic call: apply function f with left arg w and right arg x.
export
call2 : Handle -> (f : Bits64) -> (w : Bits64) -> (x : Bits64) -> IO (Either Result Bits64)
call2 h f w x = do
  result <- primIO (prim__call2 (handlePtr h) f w x)
  if result == 0
    then pure (Left Error)
    else pure (Right result)

--------------------------------------------------------------------------------
-- BQN Value Type Inspection
--------------------------------------------------------------------------------

||| Get the type tag of a CBQN value.
||| Returns one of: 0=number, 1=char, 2=fn, 3=1mod, 4=2mod, 5=ns, 6=array
export
%foreign "C:bqniser_type, libbqniser"
prim__type : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe type inspection.
export
valueType : Handle -> Bits64 -> IO (Maybe BQNType)
valueType h val = do
  tag <- primIO (prim__type (handlePtr h) val)
  pure $ case tag of
    0 => Just BQNNumber
    1 => Just BQNCharacter
    2 => Just BQNFunction
    3 => Just BQN1Modifier
    4 => Just BQN2Modifier
    5 => Just BQNNamespace
    6 => Just BQNArray
    _ => Nothing

||| Get the element count (bound) of a BQN array value.
export
%foreign "C:bqniser_bound, libbqniser"
prim__bound : Bits64 -> Bits64 -> PrimIO Bits64

||| Safe bound query: how many elements in this array?
export
bound : Handle -> Bits64 -> IO Bits64
bound h val = primIO (prim__bound (handlePtr h) val)

--------------------------------------------------------------------------------
-- Numeric Array I/O
--------------------------------------------------------------------------------

||| Read a BQN numeric array into an f64 buffer.
||| The buffer must be pre-allocated with at least `bound` elements.
export
%foreign "C:bqniser_read_f64_arr, libbqniser"
prim__readF64Arr : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe numeric array reader.
||| Returns Ok if the read succeeded, or an error code.
export
readF64Arr : Handle -> (val : Bits64) -> (buf : Bits64) -> IO (Either Result ())
readF64Arr h val buf = do
  result <- primIO (prim__readF64Arr (handlePtr h) val buf)
  pure $ case result of
    0 => Right ()
    _ => Left Error

||| Extract a scalar f64 from a BQN numeric value.
export
%foreign "C:bqniser_to_f64, libbqniser"
prim__toF64 : Bits64 -> Bits64 -> PrimIO Double

||| Safe scalar extraction.
export
toF64 : Handle -> Bits64 -> IO Double
toF64 h val = primIO (prim__toF64 (handlePtr h) val)

||| Create a BQN numeric array from an f64 buffer.
export
%foreign "C:bqniser_make_f64_arr, libbqniser"
prim__makeF64Arr : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits64

||| Safe numeric array constructor.
||| Takes a pointer to contiguous f64 data and element count.
export
makeF64Arr : Handle -> (buf : Bits64) -> (len : Bits32) -> IO (Either Result Bits64)
makeF64Arr h buf len = do
  result <- primIO (prim__makeF64Arr (handlePtr h) buf len)
  if result == 0
    then pure (Left OutOfMemory)
    else pure (Right result)

--------------------------------------------------------------------------------
-- BQN Value Lifecycle
--------------------------------------------------------------------------------

||| Release a CBQN value (decrement reference count).
export
%foreign "C:bqniser_release, libbqniser"
prim__release : Bits64 -> Bits64 -> PrimIO ()

||| Safe value release.
export
release : Handle -> Bits64 -> IO ()
release h val = primIO (prim__release (handlePtr h) val)

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert a BQN character array to a C string.
export
%foreign "C:bqniser_to_cstr, libbqniser"
prim__toCStr : Bits64 -> Bits64 -> PrimIO Bits64

||| Free a C string allocated by bqniser_to_cstr.
export
%foreign "C:bqniser_free_string, libbqniser"
prim__freeString : Bits64 -> PrimIO ()

||| Convert C string to Idris String (from Idris2 support library)
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Safe BQN string extraction.
export
getString : Handle -> Bits64 -> IO (Maybe String)
getString h val = do
  ptr <- primIO (prim__toCStr (handlePtr h) val)
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get the last error message from the CBQN bridge.
export
%foreign "C:bqniser_last_error, libbqniser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string.
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Human-readable error description for result codes.
export
errorDescription : Result -> String
errorDescription Ok           = "Success"
errorDescription Error        = "Generic CBQN error"
errorDescription InvalidParam = "Invalid parameter (bad rank, wrong type)"
errorDescription OutOfMemory  = "Out of memory (CBQN heap exhausted)"
errorDescription NullPointer  = "Null pointer (uninitialised BQN value)"
errorDescription EvalError    = "BQN evaluation error (syntax or runtime)"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get the bqniser FFI bridge version.
export
%foreign "C:bqniser_version, libbqniser"
prim__version : PrimIO Bits64

||| Get version as string.
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get CBQN runtime version (if available).
export
%foreign "C:bqniser_cbqn_version, libbqniser"
prim__cbqnVersion : PrimIO Bits64

||| Get CBQN version.
export
cbqnVersion : IO (Maybe String)
cbqnVersion = do
  ptr <- primIO prim__cbqnVersion
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if CBQN runtime is initialised.
export
%foreign "C:bqniser_is_initialized, libbqniser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialisation status.
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
