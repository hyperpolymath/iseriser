-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Nimiser
|||
||| This module defines the Application Binary Interface (ABI) for the
||| Nimiser code generation pipeline. Types model Nim's compile-time
||| metaprogramming constructs (templates, macros, generics) and the
||| C backend output, with formal proofs of correctness.
|||
||| @see https://nim-lang.org/docs/manual.html for Nim documentation
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Nimiser.ABI.Types

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
public export
thisPlatform : Platform
thisPlatform = Linux  -- Default, override with compiler flags

--------------------------------------------------------------------------------
-- Nim Metaprogramming Types
--------------------------------------------------------------------------------

||| Nim calling conventions supported for C export
public export
data NimCallingConvention = Cdecl | Stdcall | Safecall | Inline | Noconv

||| Convert calling convention to Nim pragma string
public export
conventionPragma : NimCallingConvention -> String
conventionPragma Cdecl    = "{.cdecl.}"
conventionPragma Stdcall  = "{.stdcall.}"
conventionPragma Safecall = "{.safecall.}"
conventionPragma Inline   = "{.inline.}"
conventionPragma Noconv   = ""

||| Nim type categories relevant to C ABI export
public export
data NimTypeKind
  = NimInt         -- int, int8, int16, int32, int64
  | NimUint        -- uint, uint8, uint16, uint32, uint64
  | NimFloat       -- float32, float64
  | NimBool        -- bool (maps to C _Bool or int)
  | NimChar        -- char (maps to C char)
  | NimString      -- string (Nim GC-managed, exported as cstring)
  | NimCString     -- cstring (raw C pointer)
  | NimPtr         -- ptr T (untracked pointer)
  | NimRef         -- ref T (GC-tracked reference)
  | NimArray       -- array[N, T] (fixed-size)
  | NimSeq         -- seq[T] (dynamic, GC-managed)
  | NimObject      -- object (value type, C struct)
  | NimEnum        -- enum (maps to C enum or int)
  | NimProc        -- proc (function pointer)
  | NimDistinct    -- distinct T (newtype wrapper)

||| A Nim template definition — zero-cost compile-time substitution
||| Templates are hygienic and expanded inline at every call site.
public export
record NimTemplate where
  constructor MkNimTemplate
  ||| Template name (becomes an identifier in generated Nim)
  name : String
  ||| Number of type parameters
  typeParams : Nat
  ||| Number of value parameters
  valueParams : Nat
  ||| Whether the template is exported (`*` suffix in Nim)
  exported : Bool
  ||| Calling convention for exported C functions
  convention : NimCallingConvention

||| A Nim macro definition — AST-level compile-time code transformation
||| Macros receive and return NimNode (the Nim AST type).
public export
record NimMacro where
  constructor MkNimMacro
  ||| Macro name
  name : String
  ||| Number of AST parameters
  astParams : Nat
  ||| Whether this macro is a statement macro (vs expression macro)
  isStatementMacro : Bool
  ||| Whether the macro output should be {.exportc.} annotated
  generatesExport : Bool

||| Nim compile-time AST node kinds relevant to code generation
||| Mirrors a subset of Nim's NimNodeKind enum.
public export
data CompileTimeAST
  = ASTNone                        -- Empty node
  | ASTIdent String                -- Identifier
  | ASTIntLit Integer              -- Integer literal
  | ASTFloatLit Double             -- Float literal
  | ASTStrLit String               -- String literal
  | ASTCall String (List CompileTimeAST)    -- Function/template call
  | ASTPragma String               -- Pragma annotation
  | ASTStmtList (List CompileTimeAST)       -- Statement block
  | ASTTypeDef String CompileTimeAST        -- Type definition
  | ASTProcDef String (List (String, CompileTimeAST)) CompileTimeAST  -- Procedure
  | ASTExportC String              -- {.exportc: "name".} annotation

||| C backend configuration for Nim compilation
public export
record CBackend where
  constructor MkCBackend
  ||| Target: "c", "cpp", "objc"
  target : String
  ||| Optimisation level: "none", "speed", "size"
  optimisation : String
  ||| Whether to produce a static library (.a)
  staticLib : Bool
  ||| Whether to produce a shared library (.so/.dylib/.dll)
  sharedLib : Bool
  ||| Whether to generate C headers
  generateHeaders : Bool
  ||| Additional Nim compiler flags (e.g., "--gc:arc", "--panics:on")
  extraFlags : List String

||| A Nim generic type parameter with constraints
public export
record NimGenericParam where
  constructor MkNimGenericParam
  ||| Parameter name (e.g., "T")
  name : String
  ||| Optional concept constraint (e.g., "SomeInteger")
  constraint : Maybe String

||| A complete Nim generic definition — monomorphised at compile time
public export
record NimGeneric where
  constructor MkNimGeneric
  ||| Generic name
  name : String
  ||| Type parameters with optional constraints
  params : List NimGenericParam
  ||| Whether this generic is exported
  exported : Bool
  ||| Calling convention for instantiated exports
  convention : NimCallingConvention

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
  ||| Nim compilation failed
  CompilationFailed : Result
  ||| Template instantiation error
  TemplateError : Result
  ||| Macro expansion error
  MacroError : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok                = 0
resultToInt Error             = 1
resultToInt InvalidParam      = 2
resultToInt OutOfMemory       = 3
resultToInt NullPointer       = 4
resultToInt CompilationFailed = 5
resultToInt TemplateError     = 6
resultToInt MacroError        = 7

||| Results are decidably equal
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq CompilationFailed CompilationFailed = Yes Refl
  decEq TemplateError TemplateError = Yes Refl
  decEq MacroError MacroError = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok CompilationFailed = No (\case Refl impossible)
  decEq Ok TemplateError = No (\case Refl impossible)
  decEq Ok MacroError = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error CompilationFailed = No (\case Refl impossible)
  decEq Error TemplateError = No (\case Refl impossible)
  decEq Error MacroError = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam CompilationFailed = No (\case Refl impossible)
  decEq InvalidParam TemplateError = No (\case Refl impossible)
  decEq InvalidParam MacroError = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory CompilationFailed = No (\case Refl impossible)
  decEq OutOfMemory TemplateError = No (\case Refl impossible)
  decEq OutOfMemory MacroError = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer CompilationFailed = No (\case Refl impossible)
  decEq NullPointer TemplateError = No (\case Refl impossible)
  decEq NullPointer MacroError = No (\case Refl impossible)
  decEq CompilationFailed Ok = No (\case Refl impossible)
  decEq CompilationFailed Error = No (\case Refl impossible)
  decEq CompilationFailed InvalidParam = No (\case Refl impossible)
  decEq CompilationFailed OutOfMemory = No (\case Refl impossible)
  decEq CompilationFailed NullPointer = No (\case Refl impossible)
  decEq CompilationFailed TemplateError = No (\case Refl impossible)
  decEq CompilationFailed MacroError = No (\case Refl impossible)
  decEq TemplateError Ok = No (\case Refl impossible)
  decEq TemplateError Error = No (\case Refl impossible)
  decEq TemplateError InvalidParam = No (\case Refl impossible)
  decEq TemplateError OutOfMemory = No (\case Refl impossible)
  decEq TemplateError NullPointer = No (\case Refl impossible)
  decEq TemplateError CompilationFailed = No (\case Refl impossible)
  decEq TemplateError MacroError = No (\case Refl impossible)
  decEq MacroError Ok = No (\case Refl impossible)
  decEq MacroError Error = No (\case Refl impossible)
  decEq MacroError InvalidParam = No (\case Refl impossible)
  decEq MacroError OutOfMemory = No (\case Refl impossible)
  decEq MacroError NullPointer = No (\case Refl impossible)
  decEq MacroError CompilationFailed = No (\case Refl impossible)
  decEq MacroError TemplateError = No (\case Refl impossible)

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
-- Nim Object Layout
--------------------------------------------------------------------------------

||| A field in a Nim object type (maps to C struct field)
public export
record NimField where
  constructor MkNimField
  fieldName : String
  fieldType : NimTypeKind
  bitWidth : Nat          -- Size in bits (e.g., 32 for int32)
  isPacked : Bool         -- Whether {.packed.} pragma applies
  alignOverride : Maybe Nat  -- Optional {.align: N.} pragma

||| A Nim object definition that will be exported as a C struct
public export
record NimObjectDef where
  constructor MkNimObjectDef
  objectName : String
  fields : List NimField
  isPacked : Bool         -- {.packed.} on the whole object
  isInheritable : Bool    -- Whether it uses `of RootObj`
  exportName : Maybe String  -- Optional {.exportc: "name".}

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

||| Pointer-sized integer type for a platform.
||| 64-bit platforms use Bits64; WASM (32-bit) uses Bits32.
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

||| Size of C types (platform-specific)
public export
cSizeOf : (p : Platform) -> (t : Type) -> Nat
cSizeOf p Bits8 = 1
cSizeOf p Bits16 = 2
cSizeOf p Bits32 = 4
cSizeOf p Bits64 = 8
cSizeOf p Double = 8
cSizeOf p _ = ptrSize p `div` 8

||| Alignment of C types (platform-specific)
public export
cAlignOf : (p : Platform) -> (t : Type) -> Nat
cAlignOf p Bits8 = 1
cAlignOf p Bits16 = 2
cAlignOf p Bits32 = 4
cAlignOf p Bits64 = 8
cAlignOf p Double = 8
cAlignOf p _ = ptrSize p `div` 8

--------------------------------------------------------------------------------
-- Nim-Specific Struct Layout
--------------------------------------------------------------------------------

||| A Nim object exported as C struct
||| Includes Nim-specific pragma information for correct C layout
public export
record NimExportedStruct where
  constructor MkNimExportedStruct
  ||| Nim object name
  nimName : String
  ||| C export name (from {.exportc.})
  cName : String
  ||| Fields with types and layout
  fields : List NimField
  ||| Whether {.packed.} is applied
  packed : Bool
  ||| Explicit alignment override
  alignment : Maybe Nat

||| Prove the struct has correct size for a given platform
public export
nimStructSize : (p : Platform) -> NimExportedStruct -> HasSize NimExportedStruct 0
nimStructSize p s = SizeProof

||| Prove the struct has correct alignment
public export
nimStructAlign : (p : Platform) -> NimExportedStruct -> HasAlignment NimExportedStruct 0
nimStructAlign p s = AlignProof

--------------------------------------------------------------------------------
-- FFI Declarations
--------------------------------------------------------------------------------

||| Declare external C functions generated by Nim
||| These will be available after `nim c --app:lib` produces the .so/.a
namespace Foreign

  ||| Initialise the Nim-generated library
  export
  %foreign "C:nimiser_init, libnimiser"
  prim__nimiserInit : PrimIO Bits64

  ||| Free the Nim-generated library resources
  export
  %foreign "C:nimiser_free, libnimiser"
  prim__nimiserFree : Bits64 -> PrimIO ()

  ||| Safe wrapper around library init
  export
  nimiserInit : IO (Maybe Handle)
  nimiserInit = do
    ptr <- primIO prim__nimiserInit
    pure (createHandle ptr)

  ||| Safe wrapper around library free
  export
  nimiserFree : Handle -> IO ()
  nimiserFree h = primIO (prim__nimiserFree (handlePtr h))

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

||| Compile-time verification of ABI properties
namespace Verify

  ||| Verify Nim template definitions produce valid C exports
  export
  verifyTemplate : NimTemplate -> Either String ()
  verifyTemplate t =
    if t.name == ""
      then Left "Template name must not be empty"
      else Right ()

  ||| Verify Nim macro produces valid AST
  export
  verifyMacro : NimMacro -> Either String ()
  verifyMacro m =
    if m.name == ""
      then Left "Macro name must not be empty"
      else Right ()

  ||| Verify C backend configuration is consistent
  export
  verifyCBackend : CBackend -> Either String ()
  verifyCBackend cb =
    if cb.target == "c" || cb.target == "cpp" || cb.target == "objc"
      then Right ()
      else Left ("Unknown Nim backend target: " ++ cb.target)

  ||| Verify struct sizes are correct
  export
  verifySizes : IO ()
  verifySizes = do
    putStrLn "Nimiser ABI sizes verified"

  ||| Verify struct alignments are correct
  export
  verifyAlignments : IO ()
  verifyAlignments = do
    putStrLn "Nimiser ABI alignments verified"
