-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for iseriser (Layer 2 ABI).
|||
||| Headline: "Meta-framework that generates new -iser projects."
|||
||| A generated -iser scaffold is faithful only when ALL of the five
||| architectural components named in the project doctrine are present:
|||
|||   Manifest · Idris2 ABI · Zig FFI · Codegen · Rust CLI
|||
||| We model a scaffold as the set of components it actually produced, and
||| prove a `Conformant` proposition that holds EXACTLY when every required
||| component is present. The bad case (a scaffold missing any component)
||| has no `Conformant` witness — this is enforced structurally, not by an
||| opaque boolean. The decision procedure is sound AND complete, and the
||| negative control shows a scaffold missing the FFI is provably not
||| Conformant.

module Iseriser.ABI.Semantics

import Iseriser.ABI.Types
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful domain model
--------------------------------------------------------------------------------

||| The five architectural components every generated -iser must contain.
||| These mirror the doctrine in .claude/CLAUDE.md:
|||   Manifest, Idris2 ABI, Zig FFI, Codegen, Rust CLI.
public export
data Component : Type where
  Manifest : Component   -- <name>.toml: user describes WHAT they want
  Abi      : Component   -- src/interface/abi: Idris2 formal proofs
  Ffi      : Component   -- ffi/zig: C-ABI bridge
  Codegen  : Component   -- src/codegen: target-language wrapper generation
  Cli      : Component   -- src/main.rs: Rust orchestrator

||| A generated scaffold is the (finite) list of components it produced.
public export
record Scaffold where
  constructor MkScaffold
  components : List Component

--------------------------------------------------------------------------------
-- Decidable equality on Component (needed for membership)
--------------------------------------------------------------------------------

public export
DecEq Component where
  decEq Manifest Manifest = Yes Refl
  decEq Abi      Abi      = Yes Refl
  decEq Ffi      Ffi      = Yes Refl
  decEq Codegen  Codegen  = Yes Refl
  decEq Cli      Cli      = Yes Refl

  decEq Manifest Abi      = No (\case Refl impossible)
  decEq Manifest Ffi      = No (\case Refl impossible)
  decEq Manifest Codegen  = No (\case Refl impossible)
  decEq Manifest Cli      = No (\case Refl impossible)
  decEq Abi      Manifest = No (\case Refl impossible)
  decEq Abi      Ffi      = No (\case Refl impossible)
  decEq Abi      Codegen  = No (\case Refl impossible)
  decEq Abi      Cli      = No (\case Refl impossible)
  decEq Ffi      Manifest = No (\case Refl impossible)
  decEq Ffi      Abi      = No (\case Refl impossible)
  decEq Ffi      Codegen  = No (\case Refl impossible)
  decEq Ffi      Cli      = No (\case Refl impossible)
  decEq Codegen  Manifest = No (\case Refl impossible)
  decEq Codegen  Abi      = No (\case Refl impossible)
  decEq Codegen  Ffi      = No (\case Refl impossible)
  decEq Codegen  Cli      = No (\case Refl impossible)
  decEq Cli      Manifest = No (\case Refl impossible)
  decEq Cli      Abi      = No (\case Refl impossible)
  decEq Cli      Ffi      = No (\case Refl impossible)
  decEq Cli      Codegen  = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- The headline property: Conformant
--------------------------------------------------------------------------------

||| `Has c s` is a genuine membership obligation: component `c` is in the
||| scaffold's produced component list. There is NO way to construct it for
||| an absent component (it reduces to `Data.List.Elem`, which has no
||| inhabitant for the empty list).
public export
Has : Component -> Scaffold -> Type
Has c s = Elem c (components s)

||| A scaffold is `Conformant` EXACTLY when each of the five required
||| components is present. Each field is a real membership proof; the
||| proposition is uninhabited the moment any component is missing.
||| (No catch-all constructor: this cannot be faked.)
public export
data Conformant : Scaffold -> Type where
  MkConformant :
       Has Manifest s
    -> Has Abi      s
    -> Has Ffi      s
    -> Has Codegen  s
    -> Has Cli      s
    -> Conformant s

--------------------------------------------------------------------------------
-- Sound + complete decision procedure
--------------------------------------------------------------------------------

||| Decide membership of a component in a scaffold.
decHas : (c : Component) -> (s : Scaffold) -> Dec (Has c s)
decHas c s = isElem c (components s)

||| Decide whether a scaffold is Conformant. Returns a REAL proof when all
||| five components are present, and a refutation when any is missing. The
||| refutation projects the relevant field out of a hypothetical witness, so
||| completeness is machine-checked (not asserted).
public export
decConformant : (s : Scaffold) -> Dec (Conformant s)
decConformant s =
  case decHas Manifest s of
    No nm => No (\(MkConformant m _ _ _ _) => nm m)
    Yes m => case decHas Abi s of
      No na => No (\(MkConformant _ a _ _ _) => na a)
      Yes a => case decHas Ffi s of
        No nf => No (\(MkConformant _ _ f _ _) => nf f)
        Yes f => case decHas Codegen s of
          No ng => No (\(MkConformant _ _ _ g _) => ng g)
          Yes g => case decHas Cli s of
            No nc => No (\(MkConformant _ _ _ _ c) => nc c)
            Yes c => Yes (MkConformant m a f g c)

--------------------------------------------------------------------------------
-- Certifier + soundness fact
--------------------------------------------------------------------------------

||| Map a scaffold to a `ProofStatus`-shaped verdict reusing the ABI's
||| `Result` codes: `Ok` means Conformant, `InvalidLanguage` means a
||| required component is missing.
public export
certifyConformant : (s : Scaffold) -> Result
certifyConformant s =
  case decConformant s of
    Yes _ => Ok
    No  _ => InvalidLanguage

||| Soundness of the certifier: if it returns `Ok`, a genuine `Conformant`
||| witness exists. Proven by case-analysis on the SAME decision the
||| certifier uses; the `No` branch is impossible because `Ok = InvalidLanguage`
||| is absurd.
public export
certifyConformantSound :
     (s : Scaffold)
  -> certifyConformant s = Ok
  -> Conformant s
certifyConformantSound s prf with (decConformant s)
  certifyConformantSound s prf       | Yes ok = ok
  certifyConformantSound s Refl      | No  _ impossible

--------------------------------------------------------------------------------
-- Positive control: a complete scaffold IS Conformant
--------------------------------------------------------------------------------

||| A faithfully complete scaffold — all five components, in canonical order.
public export
completeScaffold : Scaffold
completeScaffold = MkScaffold [Manifest, Abi, Ffi, Codegen, Cli]

||| Explicit witness that the complete scaffold is Conformant. Each `Has`
||| proof is a concrete `Elem` position into the literal list above, so this
||| type-checks by reduction with no appeal to the decision procedure.
public export
completeIsConformant : Conformant Semantics.completeScaffold
completeIsConformant =
  MkConformant
    Here                          -- Manifest at position 0
    (There Here)                  -- Abi at position 1
    (There (There Here))          -- Ffi at position 2
    (There (There (There Here)))  -- Codegen at position 3
    (There (There (There (There Here))))  -- Cli at position 4

--------------------------------------------------------------------------------
-- Negative control: a scaffold missing the FFI is NOT Conformant
--------------------------------------------------------------------------------

||| A scaffold that produced everything EXCEPT the Zig FFI bridge.
public export
ffiMissingScaffold : Scaffold
ffiMissingScaffold = MkScaffold [Manifest, Abi, Codegen, Cli]

||| Machine-checked refutation: with no `Ffi` component, no `Conformant`
||| witness can exist. We pull the `Has Ffi` field out of any hypothetical
||| witness and discharge it — `Ffi` is not among the four present
||| components, so every membership position is impossible.
public export
ffiMissingNotConformant : Not (Conformant Semantics.ffiMissingScaffold)
ffiMissingNotConformant (MkConformant _ _ f _ _) = noFfi f
  where
    noFfi : Not (Elem Ffi [Manifest, Abi, Codegen, Cli])
    noFfi (There (There (There (There prf)))) impossible
