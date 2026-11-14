-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Nimiser.
|||
||| Headline domain property: "Generate high-performance C libraries via Nim
||| metaprogramming." The correctness obligation for that headline is that the
||| generated C binding *preserves the source signature* — same arity, and each
||| argument/return type lowered by the canonical Nim->C type mapping. We model
||| a Nim proc signature, the C binding signature, and the code generator, then
||| prove that the generator ALWAYS produces a signature that matches the source
||| (preservation / soundness), that signature-matching is decidable, and — the
||| load-bearing fact — that an arity or type mismatch is UNREPRESENTABLE as a
||| `SigMatch` witness. Non-vacuity is guaranteed because the Nim->C lowering is
||| injective, so a wrong C type can never be accepted as a match.
|||
||| This raises the Nimiser ABI to "Layer 2": a machine-checked semantic
||| guarantee about the codegen, not merely structural type definitions.

module Nimiser.ABI.Semantics

import Nimiser.ABI.Types
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful domain model: Nim proc signatures and their lowered C binding
--------------------------------------------------------------------------------

||| The Nim source types that Nimiser is allowed to export across the C ABI.
||| Deliberately the C-ABI-safe subset (no GC-managed `string`/`seq`/`ref`,
||| which would need wrapper logic rather than a direct lowering).
public export
data NimT = NInt | NUint | NFloat | NBool | NChar | NCString | NPtr

||| The corresponding C types that Nimiser emits in generated headers.
public export
data CT = CIntT | CUintT | CDoubleT | CBoolT | CCharT | CCharStarT | CVoidStarT

||| The canonical Nim->C type lowering performed by the code generator.
||| This is the single source of truth for "what C type does this Nim type
||| become". It is total and (proved below) injective.
public export
nimToC : NimT -> CT
nimToC NInt     = CIntT
nimToC NUint    = CUintT
nimToC NFloat   = CDoubleT
nimToC NBool    = CBoolT
nimToC NChar    = CCharT
nimToC NCString = CCharStarT
nimToC NPtr     = CVoidStarT

||| A Nim proc signature: name, ordered argument types, and a return type.
public export
record NimSig where
  constructor MkNimSig
  sigName    : String
  sigArgs    : List NimT
  sigRet     : NimT

||| A generated C binding signature: name, ordered C argument types, C return.
public export
record CSig where
  constructor MkCSig
  cName : String
  cArgs : List CT
  cRet  : CT

||| The code generator: lower a Nim signature to a C binding signature.
||| Arity is preserved structurally (map preserves length); each type is lowered
||| by `nimToC`; the symbol name is preserved verbatim (Nim {.exportc.} default).
public export
genBinding : NimSig -> CSig
genBinding (MkNimSig n args ret) = MkCSig n (map nimToC args) (nimToC ret)

--------------------------------------------------------------------------------
-- The headline property: signature preservation (no constructor for mismatch)
--------------------------------------------------------------------------------

||| Pointwise proof that a list of C types is exactly the lowering of a list of
||| Nim types. Crucially this also forces equal LENGTH: there is NO constructor
||| relating a cons to a nil, so an arity mismatch has no witness.
public export
data ArgsLower : List NimT -> List CT -> Type where
  LowerNil  : ArgsLower [] []
  LowerCons : (headEq : nimToC t = c)
           -> ArgsLower ts cs
           -> ArgsLower (t :: ts) (c :: cs)

||| Signature preservation: the C signature is exactly the lowering of the Nim
||| signature — same name, same arity, every type the canonical C type. There is
||| NO constructor for a wrong name, wrong arity, or wrong type, so any such
||| mismatch is unrepresentable.
public export
data SigPreserved : NimSig -> CSig -> Type where
  MkPreserved : (nameEq : n = cn)
             -> ArgsLower args cargs
             -> (retEq : nimToC ret = cret)
             -> SigPreserved (MkNimSig n args ret) (MkCSig cn cargs cret)

--------------------------------------------------------------------------------
-- Soundness / preservation theorem: the generator always preserves
--------------------------------------------------------------------------------

||| Helper: `genBinding`'s argument lowering is always an `ArgsLower` witness.
genArgsLower : (args : List NimT) -> ArgsLower args (map Semantics.nimToC args)
genArgsLower []        = LowerNil
genArgsLower (t :: ts) = LowerCons Refl (genArgsLower ts)

||| THEOREM (preservation): for every Nim signature, the generated C binding
||| signature provably preserves it. The code generator can never emit a binding
||| with the wrong arity or a mis-lowered type.
public export
genBindingPreserves : (s : NimSig) -> SigPreserved s (genBinding s)
genBindingPreserves (MkNimSig n args ret) =
  MkPreserved Refl (genArgsLower args) Refl

--------------------------------------------------------------------------------
-- Injectivity of the lowering (the engine of non-vacuity)
--------------------------------------------------------------------------------

||| DecEq for Nim types (needed to decide signature matching faithfully).
public export
DecEq NimT where
  decEq NInt NInt = Yes Refl
  decEq NUint NUint = Yes Refl
  decEq NFloat NFloat = Yes Refl
  decEq NBool NBool = Yes Refl
  decEq NChar NChar = Yes Refl
  decEq NCString NCString = Yes Refl
  decEq NPtr NPtr = Yes Refl
  decEq NInt NUint = No (\case Refl impossible)
  decEq NInt NFloat = No (\case Refl impossible)
  decEq NInt NBool = No (\case Refl impossible)
  decEq NInt NChar = No (\case Refl impossible)
  decEq NInt NCString = No (\case Refl impossible)
  decEq NInt NPtr = No (\case Refl impossible)
  decEq NUint NInt = No (\case Refl impossible)
  decEq NUint NFloat = No (\case Refl impossible)
  decEq NUint NBool = No (\case Refl impossible)
  decEq NUint NChar = No (\case Refl impossible)
  decEq NUint NCString = No (\case Refl impossible)
  decEq NUint NPtr = No (\case Refl impossible)
  decEq NFloat NInt = No (\case Refl impossible)
  decEq NFloat NUint = No (\case Refl impossible)
  decEq NFloat NBool = No (\case Refl impossible)
  decEq NFloat NChar = No (\case Refl impossible)
  decEq NFloat NCString = No (\case Refl impossible)
  decEq NFloat NPtr = No (\case Refl impossible)
  decEq NBool NInt = No (\case Refl impossible)
  decEq NBool NUint = No (\case Refl impossible)
  decEq NBool NFloat = No (\case Refl impossible)
  decEq NBool NChar = No (\case Refl impossible)
  decEq NBool NCString = No (\case Refl impossible)
  decEq NBool NPtr = No (\case Refl impossible)
  decEq NChar NInt = No (\case Refl impossible)
  decEq NChar NUint = No (\case Refl impossible)
  decEq NChar NFloat = No (\case Refl impossible)
  decEq NChar NBool = No (\case Refl impossible)
  decEq NChar NCString = No (\case Refl impossible)
  decEq NChar NPtr = No (\case Refl impossible)
  decEq NCString NInt = No (\case Refl impossible)
  decEq NCString NUint = No (\case Refl impossible)
  decEq NCString NFloat = No (\case Refl impossible)
  decEq NCString NBool = No (\case Refl impossible)
  decEq NCString NChar = No (\case Refl impossible)
  decEq NCString NPtr = No (\case Refl impossible)
  decEq NPtr NInt = No (\case Refl impossible)
  decEq NPtr NUint = No (\case Refl impossible)
  decEq NPtr NFloat = No (\case Refl impossible)
  decEq NPtr NBool = No (\case Refl impossible)
  decEq NPtr NChar = No (\case Refl impossible)
  decEq NPtr NCString = No (\case Refl impossible)

||| DecEq for C types.
public export
DecEq CT where
  decEq CIntT CIntT = Yes Refl
  decEq CUintT CUintT = Yes Refl
  decEq CDoubleT CDoubleT = Yes Refl
  decEq CBoolT CBoolT = Yes Refl
  decEq CCharT CCharT = Yes Refl
  decEq CCharStarT CCharStarT = Yes Refl
  decEq CVoidStarT CVoidStarT = Yes Refl
  decEq CIntT CUintT = No (\case Refl impossible)
  decEq CIntT CDoubleT = No (\case Refl impossible)
  decEq CIntT CBoolT = No (\case Refl impossible)
  decEq CIntT CCharT = No (\case Refl impossible)
  decEq CIntT CCharStarT = No (\case Refl impossible)
  decEq CIntT CVoidStarT = No (\case Refl impossible)
  decEq CUintT CIntT = No (\case Refl impossible)
  decEq CUintT CDoubleT = No (\case Refl impossible)
  decEq CUintT CBoolT = No (\case Refl impossible)
  decEq CUintT CCharT = No (\case Refl impossible)
  decEq CUintT CCharStarT = No (\case Refl impossible)
  decEq CUintT CVoidStarT = No (\case Refl impossible)
  decEq CDoubleT CIntT = No (\case Refl impossible)
  decEq CDoubleT CUintT = No (\case Refl impossible)
  decEq CDoubleT CBoolT = No (\case Refl impossible)
  decEq CDoubleT CCharT = No (\case Refl impossible)
  decEq CDoubleT CCharStarT = No (\case Refl impossible)
  decEq CDoubleT CVoidStarT = No (\case Refl impossible)
  decEq CBoolT CIntT = No (\case Refl impossible)
  decEq CBoolT CUintT = No (\case Refl impossible)
  decEq CBoolT CDoubleT = No (\case Refl impossible)
  decEq CBoolT CCharT = No (\case Refl impossible)
  decEq CBoolT CCharStarT = No (\case Refl impossible)
  decEq CBoolT CVoidStarT = No (\case Refl impossible)
  decEq CCharT CIntT = No (\case Refl impossible)
  decEq CCharT CUintT = No (\case Refl impossible)
  decEq CCharT CDoubleT = No (\case Refl impossible)
  decEq CCharT CBoolT = No (\case Refl impossible)
  decEq CCharT CCharStarT = No (\case Refl impossible)
  decEq CCharT CVoidStarT = No (\case Refl impossible)
  decEq CCharStarT CIntT = No (\case Refl impossible)
  decEq CCharStarT CUintT = No (\case Refl impossible)
  decEq CCharStarT CDoubleT = No (\case Refl impossible)
  decEq CCharStarT CBoolT = No (\case Refl impossible)
  decEq CCharStarT CCharT = No (\case Refl impossible)
  decEq CCharStarT CVoidStarT = No (\case Refl impossible)
  decEq CVoidStarT CIntT = No (\case Refl impossible)
  decEq CVoidStarT CUintT = No (\case Refl impossible)
  decEq CVoidStarT CDoubleT = No (\case Refl impossible)
  decEq CVoidStarT CBoolT = No (\case Refl impossible)
  decEq CVoidStarT CCharT = No (\case Refl impossible)
  decEq CVoidStarT CCharStarT = No (\case Refl impossible)

||| THEOREM: the Nim->C lowering is injective. Two Nim types that lower to the
||| same C type must be the same Nim type. This is what makes a type-mismatch
||| genuinely unrepresentable: you cannot smuggle a wrong source type past a
||| `SigPreserved` witness, because the C type pins the Nim type uniquely.
public export
nimToCInjective : (a, b : NimT) -> nimToC a = nimToC b -> a = b
nimToCInjective NInt     NInt     _ = Refl
nimToCInjective NUint    NUint    _ = Refl
nimToCInjective NFloat   NFloat   _ = Refl
nimToCInjective NBool    NBool    _ = Refl
nimToCInjective NChar    NChar    _ = Refl
nimToCInjective NCString NCString _ = Refl
nimToCInjective NPtr     NPtr     _ = Refl
nimToCInjective NInt     NUint    Refl impossible
nimToCInjective NInt     NFloat   Refl impossible
nimToCInjective NInt     NBool    Refl impossible
nimToCInjective NInt     NChar    Refl impossible
nimToCInjective NInt     NCString Refl impossible
nimToCInjective NInt     NPtr     Refl impossible
nimToCInjective NUint    NInt     Refl impossible
nimToCInjective NUint    NFloat   Refl impossible
nimToCInjective NUint    NBool    Refl impossible
nimToCInjective NUint    NChar    Refl impossible
nimToCInjective NUint    NCString Refl impossible
nimToCInjective NUint    NPtr     Refl impossible
nimToCInjective NFloat   NInt     Refl impossible
nimToCInjective NFloat   NUint    Refl impossible
nimToCInjective NFloat   NBool    Refl impossible
nimToCInjective NFloat   NChar    Refl impossible
nimToCInjective NFloat   NCString Refl impossible
nimToCInjective NFloat   NPtr     Refl impossible
nimToCInjective NBool    NInt     Refl impossible
nimToCInjective NBool    NUint    Refl impossible
nimToCInjective NBool    NFloat   Refl impossible
nimToCInjective NBool    NChar    Refl impossible
nimToCInjective NBool    NCString Refl impossible
nimToCInjective NBool    NPtr     Refl impossible
nimToCInjective NChar    NInt     Refl impossible
nimToCInjective NChar    NUint    Refl impossible
nimToCInjective NChar    NFloat   Refl impossible
nimToCInjective NChar    NBool    Refl impossible
nimToCInjective NChar    NCString Refl impossible
nimToCInjective NChar    NPtr     Refl impossible
nimToCInjective NCString NInt     Refl impossible
nimToCInjective NCString NUint    Refl impossible
nimToCInjective NCString NFloat   Refl impossible
nimToCInjective NCString NBool    Refl impossible
nimToCInjective NCString NChar    Refl impossible
nimToCInjective NCString NPtr     Refl impossible
nimToCInjective NPtr     NInt     Refl impossible
nimToCInjective NPtr     NUint    Refl impossible
nimToCInjective NPtr     NFloat   Refl impossible
nimToCInjective NPtr     NBool    Refl impossible
nimToCInjective NPtr     NChar    Refl impossible
nimToCInjective NPtr     NCString Refl impossible

--------------------------------------------------------------------------------
-- Decidability of argument lowering and signature preservation
--------------------------------------------------------------------------------

||| Off-diagonal refutations for ArgsLower (length mismatch has no witness).
nilConsAbsurd : ArgsLower [] (c :: cs) -> Void
nilConsAbsurd LowerNil impossible

consNilAbsurd : ArgsLower (t :: ts) [] -> Void
consNilAbsurd LowerNil impossible

||| Decide whether `cs` is exactly the lowering of `ts`. Sound and complete.
public export
decArgsLower : (ts : List NimT) -> (cs : List CT) -> Dec (ArgsLower ts cs)
decArgsLower [] [] = Yes LowerNil
decArgsLower [] (c :: cs) = No nilConsAbsurd
decArgsLower (t :: ts) [] = No consNilAbsurd
decArgsLower (t :: ts) (c :: cs) =
  case decEq (nimToC t) c of
    No contra => No (\(LowerCons hd _) => contra hd)
    Yes headEq =>
      case decArgsLower ts cs of
        No contra => No (\(LowerCons _ tl) => contra tl)
        Yes tailOk => Yes (LowerCons headEq tailOk)

||| Decide whether a candidate C signature exactly preserves a Nim signature.
||| Sound and complete: a `Yes` is a real `SigPreserved`; a `No` rules it out.
public export
decSigPreserved : (s : NimSig) -> (c : CSig) -> Dec (SigPreserved s c)
decSigPreserved (MkNimSig n args ret) (MkCSig cn cargs cret) =
  case decEq n cn of
    No contra => No (\(MkPreserved nameEq _ _) => contra nameEq)
    Yes nameEq =>
      case decEq (nimToC ret) cret of
        No contra => No (\(MkPreserved _ _ retEq) => contra retEq)
        Yes retEq =>
          case decArgsLower args cargs of
            No contra => No (\(MkPreserved _ al _) => contra al)
            Yes argsOk =>
              Yes (rewrite sym nameEq in
                   rewrite sym retEq in
                   MkPreserved Refl argsOk Refl)

--------------------------------------------------------------------------------
-- Certifier tied to the project's own Result type
--------------------------------------------------------------------------------

||| Certify that a candidate C binding preserves a Nim signature, returning a
||| project-native `Result`: `Ok` iff preservation holds.
public export
certifyBinding : NimSig -> CSig -> Result
certifyBinding s c = case decSigPreserved s c of
  Yes _ => Ok
  No  _ => Error

||| Soundness of the certifier: `Ok` implies a genuine preservation witness.
public export
certifyBindingSound : (s : NimSig) -> (c : CSig)
                   -> certifyBinding s c = Ok -> SigPreserved s c
certifyBindingSound s c prf with (decSigPreserved s c)
  certifyBindingSound s c prf       | Yes ok  = ok
  certifyBindingSound s c Refl      | No  _   impossible

||| Corollary: the generator's own output always certifies `Ok`.
public export
generatedAlwaysCertifies : (s : NimSig) -> certifyBinding s (genBinding s) = Ok
generatedAlwaysCertifies s with (decSigPreserved s (genBinding s))
  generatedAlwaysCertifies s | Yes _ = Refl
  generatedAlwaysCertifies s | No contra = absurd (contra (genBindingPreserves s))

--------------------------------------------------------------------------------
-- Positive control (inhabited witness)
--------------------------------------------------------------------------------

||| A concrete Nim proc: `proc add(a: int, b: int): int`.
public export
sampleNimSig : NimSig
sampleNimSig = MkNimSig "add" [NInt, NInt] NInt

||| The C binding the generator emits for it: `int add(int, int)`.
public export
sampleCSig : CSig
sampleCSig = genBinding sampleNimSig

||| POSITIVE CONTROL: an explicit, fully-applied preservation witness for the
||| generated binding of the sample signature. Machine-checked, no `Dec` used.
public export
samplePreserved : SigPreserved Semantics.sampleNimSig Semantics.sampleCSig
samplePreserved =
  MkPreserved Refl (LowerCons Refl (LowerCons Refl LowerNil)) Refl

--------------------------------------------------------------------------------
-- Negative controls (the bad cases are machine-checked impossible)
--------------------------------------------------------------------------------

||| NEGATIVE CONTROL 1 (type mismatch): the same arity but a wrong C return type
||| (`double` instead of `int`) does NOT preserve the signature.
public export
wrongReturnTypeNotPreserved :
  Not (SigPreserved (MkNimSig "add" [NInt, NInt] NInt)
                    (MkCSig "add" [CIntT, CIntT] CDoubleT))
wrongReturnTypeNotPreserved (MkPreserved _ _ Refl) impossible

||| NEGATIVE CONTROL 2 (arity mismatch): dropping an argument from the C binding
||| (one C arg vs two Nim args) does NOT preserve the signature.
public export
wrongArityNotPreserved :
  Not (SigPreserved (MkNimSig "add" [NInt, NInt] NInt)
                    (MkCSig "add" [CIntT] CIntT))
wrongArityNotPreserved (MkPreserved _ (LowerCons _ tl) _) = consNilAbsurd tl

||| NEGATIVE CONTROL 3 (argument-type mismatch): a wrong C argument type
||| (`char*` where `int` is required) does NOT preserve the signature.
public export
wrongArgTypeNotPreserved :
  Not (SigPreserved (MkNimSig "add" [NInt, NInt] NInt)
                    (MkCSig "add" [CCharStarT, CIntT] CIntT))
wrongArgTypeNotPreserved (MkPreserved _ (LowerCons Refl _) _) impossible
