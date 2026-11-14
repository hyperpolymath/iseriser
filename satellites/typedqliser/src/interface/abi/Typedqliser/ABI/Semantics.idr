-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Semantic proofs for TypedQLiser's type-safety levels.
|||
||| The ten levels in `Types.idr` are, on their own, abstract labels carrying a
||| per-level `ProofStatus`. This module makes one of them — `InjectionFree`
||| (level 5: "no string interpolation in structure", i.e. the no-SQL-injection
||| guarantee) — a *real*, machine-checked property over an actual query model:
|||
|||   1. a minimal but faithful query AST whose value leaves are either bound
|||      parameters / literals (safe) or raw spliced strings (an injection vector);
|||   2. `QueryInjectionFree`, the proposition that no raw splice occurs anywhere;
|||   3. `decInjectionFree`, a sound + complete decision procedure returning a
|||      genuine proof (`Dec`), so a "Proven" InjectionFree certificate is backed
|||      by a constructive witness and a raw splice can never be certified safe;
|||   4. a certifier whose `Proven` verdict is *proven* to entail the property
|||      (`certifyProvenSound`), plus positive and negative controls.

module Typedqliser.ABI.Semantics

import Typedqliser.ABI.Types
import Data.So
import Data.Vect
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A minimal but faithful query model
--------------------------------------------------------------------------------

||| A value appearing in a query. Only `RawSplice` — an interpolated string
||| spliced into the query structure — is an injection vector; bound parameters
||| and literals are safe.
public export
data Value : Type where
  Param     : (idx : Nat) -> Value      -- bound parameter placeholder ($1, $2, …)
  Lit       : (n : Integer) -> Value    -- literal constant
  RawSplice : (s : String) -> Value     -- interpolated string fragment (UNSAFE)

||| A WHERE predicate over columns and values.
public export
data Pred : Type where
  Cmp : (col : String) -> (v : Value) -> Pred
  And : Pred -> Pred -> Pred
  Or  : Pred -> Pred -> Pred

||| A SELECT query.
public export
data Query : Type where
  Select : (table : String) -> (cols : List String) -> (where_ : Pred) -> Query

--------------------------------------------------------------------------------
-- InjectionFree as a genuine proposition (no RawSplice node anywhere)
--------------------------------------------------------------------------------

||| A value is injection-safe unless it is a raw splice. There is deliberately
||| no constructor for `RawSplice`, so `ValueOk (RawSplice s)` is uninhabited.
public export
data ValueOk : Value -> Type where
  ParamOk : ValueOk (Param i)
  LitOk   : ValueOk (Lit n)

||| No `ValueOk` witnesses a raw splice — the heart of the guarantee.
public export
Uninhabited (ValueOk (RawSplice s)) where
  uninhabited ParamOk impossible
  uninhabited LitOk impossible

||| A predicate is injection-free when every comparison value is safe.
public export
data PredInjectionFree : Pred -> Type where
  CmpFree : ValueOk v -> PredInjectionFree (Cmp col v)
  AndFree : PredInjectionFree p -> PredInjectionFree q -> PredInjectionFree (And p q)
  OrFree  : PredInjectionFree p -> PredInjectionFree q -> PredInjectionFree (Or p q)

||| A query is injection-free when its WHERE predicate is.
public export
data QueryInjectionFree : Query -> Type where
  SelectFree : PredInjectionFree w -> QueryInjectionFree (Select t c w)

--------------------------------------------------------------------------------
-- Sound + complete decision procedure (returns a real proof)
--------------------------------------------------------------------------------

public export
decValueOk : (v : Value) -> Dec (ValueOk v)
decValueOk (Param i)     = Yes ParamOk
decValueOk (Lit n)       = Yes LitOk
decValueOk (RawSplice s) = No absurd

public export
decPredFree : (p : Pred) -> Dec (PredInjectionFree p)
decPredFree (Cmp col v) = case decValueOk v of
  Yes ok => Yes (CmpFree ok)
  No no   => No (\(CmpFree ok) => no ok)
decPredFree (And p q) = case decPredFree p of
  No np  => No (\(AndFree pp _) => np pp)
  Yes pp => case decPredFree q of
    Yes qq => Yes (AndFree pp qq)
    No nq  => No (\(AndFree _ qq) => nq qq)
decPredFree (Or p q) = case decPredFree p of
  No np  => No (\(OrFree pp _) => np pp)
  Yes pp => case decPredFree q of
    Yes qq => Yes (OrFree pp qq)
    No nq  => No (\(OrFree _ qq) => nq qq)

||| The headline decision procedure: decide injection-freedom, returning a
||| genuine `QueryInjectionFree` witness when it holds.
public export
decInjectionFree : (q : Query) -> Dec (QueryInjectionFree q)
decInjectionFree (Select t c w) = case decPredFree w of
  Yes ok => Yes (SelectFree ok)
  No no   => No (\(SelectFree ok) => no ok)

--------------------------------------------------------------------------------
-- Certifier soundness: a `Proven` InjectionFree status is never a lie
--------------------------------------------------------------------------------

||| Certify the InjectionFree (level 5) obligation for a query. `Proven` is
||| emitted only when the decision procedure produced a real proof.
public export
certifyInjectionFree : (q : Query) -> ProofStatus
certifyInjectionFree q = case decInjectionFree q of
  Yes _ => Proven
  No _  => Refuted

||| Soundness: if the certifier reports `Proven`, the query really is
||| injection-free. (Together with `decInjectionFree` being a `Dec`, this also
||| means a query that is *not* injection-free can never be reported `Proven`.)
export
certifyProvenSound : (q : Query) -> certifyInjectionFree q = Proven -> QueryInjectionFree q
certifyProvenSound q prf with (decInjectionFree q)
  certifyProvenSound q prf  | Yes ok = ok
  certifyProvenSound q Refl | No _ impossible

||| `InjectionFree` is level 5 — the certified obligation is the fifth of ten.
export
injectionFreeIsLevelFive : levelNat InjectionFree = 5
injectionFreeIsLevelFive = Refl

--------------------------------------------------------------------------------
-- Positive control: a parameterized query is provably injection-free
--------------------------------------------------------------------------------

||| `SELECT id, name FROM users WHERE id = $1` — fully parameterized.
public export
safeQuery : Query
safeQuery = Select "users" ["id", "name"] (Cmp "id" (Param 1))

||| Machine-checked: the parameterized query is injection-free.
export
safeQueryInjectionFree : QueryInjectionFree Semantics.safeQuery
safeQueryInjectionFree = SelectFree (CmpFree ParamOk)

||| …and the certifier reports `Proven` for it (computes to `Proven`).
export
safeQueryCertifiesProven : certifyInjectionFree Semantics.safeQuery = Proven
safeQueryCertifiesProven = Refl

--------------------------------------------------------------------------------
-- Negative control: an interpolated query CANNOT be certified injection-free
--------------------------------------------------------------------------------

||| `SELECT id FROM users WHERE name = '<spliced user input>'` — a classic
||| injection vector built by string interpolation.
public export
unsafeQuery : Query
unsafeQuery =
  Select "users" ["id"] (Cmp "name" (RawSplice "'; DROP TABLE users;--"))

||| Machine-checked: there is **no** proof that the interpolated query is
||| injection-free. This is what makes the guarantee non-vacuous — `ValueOk`
||| has no constructor for a raw splice, so the property is genuinely refuted.
export
unsafeQueryNotInjectionFree : Not (QueryInjectionFree Semantics.unsafeQuery)
unsafeQueryNotInjectionFree (SelectFree (CmpFree ok)) = absurd ok
