-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Iseriser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. These functions drive the
||| iseriser generation pipeline: creating a generation context,
||| loading a language model, expanding templates, and writing
||| the generated -iser repository to disk.
|||
||| All functions are declared here with type signatures and safety wrappers.
||| Implementations live in src/interface/ffi/src/main.zig

module Iseriser.ABI.Foreign

import Iseriser.ABI.Types
import Iseriser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the iseriser generation engine.
||| Returns a handle to the generation context, or Nothing on failure.
export
%foreign "C:iseriser_init, libiseriser"
prim__init : PrimIO Bits64

||| Safe wrapper for engine initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up generation engine resources
export
%foreign "C:iseriser_free, libiseriser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Language Model Operations
--------------------------------------------------------------------------------

||| Load a language model from a TOML manifest file.
||| The manifest path is a null-terminated C string.
export
%foreign "C:iseriser_load_language, libiseriser"
prim__loadLanguage : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper: load a language description into the generation context
export
loadLanguage : Handle -> String -> IO (Either Result ())
loadLanguage h manifestPath = do
  result <- primIO (prim__loadLanguage (handlePtr h) manifestPath)
  pure $ case result of
    0 => Right ()
    1 => Left Error
    2 => Left InvalidLanguage
    _ => Left Error

||| Get the name of the loaded language model
export
%foreign "C:iseriser_language_name, libiseriser"
prim__languageName : Bits64 -> PrimIO Bits64

||| Safe wrapper: retrieve loaded language name
export
languageName : Handle -> IO (Maybe String)
languageName h = do
  ptr <- primIO (prim__languageName (handlePtr h))
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getString : Bits64 -> String

||| Get the number of type features in the loaded language model
export
%foreign "C:iseriser_feature_count, libiseriser"
prim__featureCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: retrieve feature count
export
featureCount : Handle -> IO Nat
featureCount h = do
  n <- primIO (prim__featureCount (handlePtr h))
  pure (cast n)

--------------------------------------------------------------------------------
-- Template Expansion
--------------------------------------------------------------------------------

||| Expand all templates for the loaded language model.
||| Generates all artifacts into the specified output directory.
export
%foreign "C:iseriser_expand_templates, libiseriser"
prim__expandTemplates : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper: expand templates and write generated -iser repo
export
expandTemplates : Handle -> String -> IO (Either Result ())
expandTemplates h outputDir = do
  result <- primIO (prim__expandTemplates (handlePtr h) outputDir)
  pure $ case result of
    0 => Right ()
    1 => Left Error
    3 => Left TemplateError
    4 => Left OutputError
    _ => Left Error

||| Get the number of artifacts generated in the last expansion
export
%foreign "C:iseriser_artifact_count, libiseriser"
prim__artifactCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: retrieve generated artifact count
export
artifactCount : Handle -> IO Nat
artifactCount h = do
  n <- primIO (prim__artifactCount (handlePtr h))
  pure (cast n)

--------------------------------------------------------------------------------
-- Repo Generation (High-Level)
--------------------------------------------------------------------------------

||| Generate a complete -iser repository in one call.
||| This is the main entry point: load manifest, expand templates, write output.
export
%foreign "C:iseriser_generate_repo, libiseriser"
prim__generateRepo : Bits64 -> String -> String -> PrimIO Bits32

||| Safe wrapper: one-shot repo generation
||| Takes the manifest path and output directory, produces a complete -iser repo.
export
generateRepo : Handle -> (manifestPath : String) -> (outputDir : String) -> IO (Either Result ())
generateRepo h manifest outDir = do
  result <- primIO (prim__generateRepo (handlePtr h) manifest outDir)
  pure $ case result of
    0 => Right ()
    1 => Left Error
    2 => Left InvalidLanguage
    3 => Left TemplateError
    4 => Left OutputError
    _ => Left Error

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

||| Validate a language model without generating output.
||| Returns Ok if the model is well-formed, or an error code.
export
%foreign "C:iseriser_validate_language, libiseriser"
prim__validateLanguage : Bits64 -> String -> PrimIO Bits32

||| Safe wrapper: validate a language description
export
validateLanguage : Handle -> String -> IO (Either Result ())
validateLanguage h manifestPath = do
  result <- primIO (prim__validateLanguage (handlePtr h) manifestPath)
  pure $ case result of
    0 => Right ()
    2 => Left InvalidLanguage
    _ => Left Error

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:iseriser_last_error, libiseriser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getString : Bits64 -> String

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidLanguage = "Invalid language description"
errorDescription TemplateError = "Template expansion failed"
errorDescription OutputError = "Output directory not writable"
errorDescription NullPointer = "Null pointer"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:iseriser_version, libiseriser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)
  where
    %foreign "support:idris2_getString, libidris2_support"
    prim__getString : Bits64 -> String

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if the generation context is initialized and has a loaded model
export
%foreign "C:iseriser_is_initialized, libiseriser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)

||| Check if a language model is currently loaded
export
%foreign "C:iseriser_has_model, libiseriser"
prim__hasModel : Bits64 -> PrimIO Bits32

||| Check whether a language model is loaded in the context
export
hasModel : Handle -> IO Bool
hasModel h = do
  result <- primIO (prim__hasModel (handlePtr h))
  pure (result /= 0)
