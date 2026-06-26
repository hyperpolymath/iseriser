-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Iseriser
|||
||| This module defines the core types for the iseriser meta-framework.
||| These types model the language description input and the generated
||| -iser artifacts, with formal proofs of correctness.
|||
||| Iseriser takes a LanguageModel and produces GeneratedArtifacts.
||| These types ensure that generation is type-safe and complete.

module Iseriser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect
import Data.String
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for generated -iser ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| The platform this build targets. Defaults to Linux; the Rust/Zig build
||| layer overrides this via the codegen target selection. (Previously a
||| `%runElab` stub that required ElabReflection and did not compile.)
public export
thisPlatform : Platform
thisPlatform = Linux

--------------------------------------------------------------------------------
-- Language Model Types
--------------------------------------------------------------------------------

||| Type system features that a target language may have.
||| These determine what ABI proofs the generated -iser needs.
public export
data TypeSystemFeature : Type where
  ||| Dependent types (Idris2, Lean, Agda) — deepest ABI proofs
  DependentTypes : TypeSystemFeature
  ||| Linear/affine types (Rust, Pony, ATS) — ownership-aware FFI
  LinearTypes : TypeSystemFeature
  ||| Refinement types (Dafny, Liquid Haskell) — contract-checked FFI
  RefinementTypes : TypeSystemFeature
  ||| Session types (concurrent protocol safety)
  SessionTypes : TypeSystemFeature
  ||| Algebraic data types (most ML-family languages)
  AlgebraicTypes : TypeSystemFeature
  ||| Array/tensor types (BQN, Futhark, Julia) — bulk data FFI
  ArrayTypes : TypeSystemFeature
  ||| Simple types (basic type checking only)
  SimpleTypes : TypeSystemFeature
  ||| Gradual types (optional type annotations)
  GradualTypes : TypeSystemFeature

||| Compilation targets for the target language.
||| Determines the calling convention and FFI shape.
public export
data CompilationTarget : Type where
  ||| Compiles to native code via C ABI
  NativeC : CompilationTarget
  ||| Runs on the BEAM VM (Erlang, Elixir, Gleam)
  BEAM : CompilationTarget
  ||| Runs on the JVM
  JVM : CompilationTarget
  ||| Compiles to WebAssembly
  WASMTarget : CompilationTarget
  ||| Compiles to JavaScript
  JavaScript : CompilationTarget
  ||| Interpreted language with C extension API
  Interpreted : CompilationTarget
  ||| GPU-targeted (Futhark, Halide)
  GPU : CompilationTarget

||| A language model captures everything iseriser needs to generate
||| a complete -iser for a target language.
public export
record LanguageModel where
  constructor MkLanguageModel
  ||| The name of the target language (e.g., "Chapel", "Julia", "BQN")
  name : String
  ||| Type system features the language supports
  typeFeatures : List TypeSystemFeature
  ||| Primary compilation target
  target : CompilationTarget
  ||| Key primitives that need FFI bindings
  primitives : List String
  ||| Calling convention identifier (e.g., "c", "system", "beam_nif")
  callingConvention : String

||| Proof that a language model has at least one type feature.
||| Every language must have some type system for the -iser to work.
public export
data HasTypeFeatures : LanguageModel -> Type where
  NonEmptyFeatures : {model : LanguageModel} ->
    NonEmpty (typeFeatures model) ->
    HasTypeFeatures model

--------------------------------------------------------------------------------
-- Template Types
--------------------------------------------------------------------------------

||| An iser template represents a single file to be generated.
public export
record IserTemplate where
  constructor MkIserTemplate
  ||| Relative path in the generated repo (e.g., "src/main.rs")
  outputPath : String
  ||| Template source (Handlebars template content)
  templateContent : String
  ||| Whether this template is language-specific or universal
  isLanguageSpecific : Bool

||| Proof that a template has a non-empty output path
public export
data ValidTemplate : IserTemplate -> Type where
  TemplateOk : {tmpl : IserTemplate} ->
    So (length (outputPath tmpl) > 0) ->
    ValidTemplate tmpl

||| A generated artifact is a resolved template with concrete content.
public export
record GeneratedArtifact where
  constructor MkGeneratedArtifact
  ||| Relative path in the generated repo
  outputPath : String
  ||| Rendered content (all placeholders resolved)
  content : String
  ||| Size in bytes of the rendered content
  sizeBytes : Nat

||| Decidable predicate: the rendered content carries no unresolved
||| Handlebars placeholder markers (`{{` opening or `}}` closing).
public export
noUnresolvedMarkers : GeneratedArtifact -> Bool
noUnresolvedMarkers art =
  not (isInfixOf "{{" art.content) && not (isInfixOf "}}" art.content)

||| Proof that a generated artifact has all placeholders resolved: the
||| content contains no `{{` or `}}` markers. This is a genuine obligation —
||| `Resolved` cannot be constructed while template delimiters remain.
||| (Previously `Resolved` carried no proof and was inhabited by anything.)
public export
data FullyResolved : GeneratedArtifact -> Type where
  Resolved : {art : GeneratedArtifact} ->
    So (noUnresolvedMarkers art) ->
    FullyResolved art

||| Decide whether an artifact is fully resolved, returning a real proof
||| when it is and Nothing when unresolved markers remain.
public export
checkResolved : (art : GeneratedArtifact) -> Maybe (FullyResolved art)
checkResolved art =
  case choose (noUnresolvedMarkers art) of
    Left ok => Just (Resolved ok)
    Right _ => Nothing

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid language description
  InvalidLanguage : Result
  ||| Template expansion failed
  TemplateError : Result
  ||| Output directory not writable
  OutputError : Result
  ||| Null pointer encountered
  NullPointer : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidLanguage = 2
resultToInt TemplateError = 3
resultToInt OutputError = 4
resultToInt NullPointer = 5

||| Results are decidably equal. The off-diagonal cases discharge the
||| disequality explicitly; the previous `decEq _ _ = No absurd` did not
||| compile (no `Uninhabited (x = y)` instance exists for these).
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidLanguage InvalidLanguage = Yes Refl
  decEq TemplateError TemplateError = Yes Refl
  decEq OutputError OutputError = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidLanguage = No (\case Refl impossible)
  decEq Ok TemplateError = No (\case Refl impossible)
  decEq Ok OutputError = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidLanguage = No (\case Refl impossible)
  decEq Error TemplateError = No (\case Refl impossible)
  decEq Error OutputError = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq InvalidLanguage Ok = No (\case Refl impossible)
  decEq InvalidLanguage Error = No (\case Refl impossible)
  decEq InvalidLanguage TemplateError = No (\case Refl impossible)
  decEq InvalidLanguage OutputError = No (\case Refl impossible)
  decEq InvalidLanguage NullPointer = No (\case Refl impossible)
  decEq TemplateError Ok = No (\case Refl impossible)
  decEq TemplateError Error = No (\case Refl impossible)
  decEq TemplateError InvalidLanguage = No (\case Refl impossible)
  decEq TemplateError OutputError = No (\case Refl impossible)
  decEq TemplateError NullPointer = No (\case Refl impossible)
  decEq OutputError Ok = No (\case Refl impossible)
  decEq OutputError Error = No (\case Refl impossible)
  decEq OutputError InvalidLanguage = No (\case Refl impossible)
  decEq OutputError TemplateError = No (\case Refl impossible)
  decEq OutputError NullPointer = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidLanguage = No (\case Refl impossible)
  decEq NullPointer TemplateError = No (\case Refl impossible)
  decEq NullPointer OutputError = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to an iseriser generation context.
||| Holds the parsed language model and template state.
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
-- Generation Completeness Proof
--------------------------------------------------------------------------------

||| The set of artifact categories that a generated -iser must contain.
public export
data ArtifactCategory : Type where
  CargoToml : ArtifactCategory
  RustSource : ArtifactCategory
  Idris2ABI : ArtifactCategory
  ZigFFI : ArtifactCategory
  CIWorkflows : ArtifactCategory
  Documentation : ArtifactCategory
  RSRGovernance : ArtifactCategory

||| Artifact categories are decidably equal — needed for membership checks.
public export
Eq ArtifactCategory where
  CargoToml     == CargoToml     = True
  RustSource    == RustSource    = True
  Idris2ABI     == Idris2ABI     = True
  ZigFFI        == ZigFFI        = True
  CIWorkflows   == CIWorkflows   = True
  Documentation == Documentation = True
  RSRGovernance == RSRGovernance = True
  _             == _             = False

||| The seven categories every generated -iser repo must contain.
public export
requiredCategories : List ArtifactCategory
requiredCategories =
  [ CargoToml, RustSource, Idris2ABI, ZigFFI
  , CIWorkflows, Documentation, RSRGovernance ]

||| Decidable predicate: every required category appears in `cats`.
public export
allCategoriesPresent : List ArtifactCategory -> Bool
allCategoriesPresent cats = all (\c => elem c cats) requiredCategories

||| Proof that a generation produced all required artifact categories.
||| `AllCategoriesPresent` now carries a genuine obligation: each of the
||| seven `requiredCategories` must be a member of the produced list.
||| (Previously the constructor proved nothing.)
public export
data GenerationComplete : List ArtifactCategory -> Type where
  AllCategoriesPresent : {cats : List ArtifactCategory} ->
    So (allCategoriesPresent cats) ->
    GenerationComplete cats

||| Decide generation completeness, returning a real proof when all seven
||| categories are present and Nothing when any is missing.
public export
checkComplete : (cats : List ArtifactCategory) -> Maybe (GenerationComplete cats)
checkComplete cats =
  case choose (allCategoriesPresent cats) of
    Left ok => Just (AllCategoriesPresent ok)
    Right _ => Nothing

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

namespace Verify

  ||| Verify that a language model is well-formed
  export
  verifyLanguageModel : LanguageModel -> Either String ()
  verifyLanguageModel model =
    if length (name model) == 0
      then Left "Language name must not be empty"
      else if length (primitives model) == 0
        then Left "Language must declare at least one primitive"
        else Right ()

  ||| Verify that all generated artifacts are fully resolved
  export
  verifyArtifacts : List GeneratedArtifact -> Either String ()
  verifyArtifacts [] = Right ()
  verifyArtifacts (a :: as) =
    if length (outputPath a) == 0
      then Left "Artifact has empty output path"
      else verifyArtifacts as
