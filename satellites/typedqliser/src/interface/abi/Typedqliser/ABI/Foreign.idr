-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface declarations for TypedQLiser.
|||
||| C-compatible entry points implemented in the Zig FFI layer
||| (src/interface/ffi/src/main.zig). Each safe wrapper maps the raw C result
||| code back to the `Result` type from the ABI.

module Typedqliser.ABI.Foreign

import Typedqliser.ABI.Types
import Typedqliser.ABI.Layout

%default total

||| Initialise the TypedQLiser proof engine; returns a context pointer.
export
%foreign "C:typedqliser_init,libtypedqliser"
prim__init : PrimIO Bits64

export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Release the proof engine context.
export
%foreign "C:typedqliser_free,libtypedqliser"
prim__free : Bits64 -> PrimIO ()

export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

||| Check a query (null-terminated C string) against a schema, up to the
||| requested level. Returns a C result code.
export
%foreign "C:typedqliser_check_query,libtypedqliser"
prim__checkQuery : Bits64 -> String -> Bits32 -> PrimIO Bits32

export
checkQuery : Handle -> (query : String) -> (level : Bits32) -> IO (Either Result ())
checkQuery h query level = do
  rc <- primIO (prim__checkQuery (handlePtr h) query level)
  pure $ case rc of
    0 => Right ()
    2 => Left InvalidQuery
    3 => Left SchemaError
    _ => Left Error

||| Highest safety level the last checked query achieved (0 if none).
export
%foreign "C:typedqliser_certificate_level,libtypedqliser"
prim__certificateLevel : Bits64 -> PrimIO Bits32

export
certificateLevel : Handle -> IO Nat
certificateLevel h = do
  n <- primIO (prim__certificateLevel (handlePtr h))
  pure (cast n)

||| Library version string.
export
%foreign "C:typedqliser_version,libtypedqliser"
prim__version : PrimIO Bits64

export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getString : Bits64 -> String
