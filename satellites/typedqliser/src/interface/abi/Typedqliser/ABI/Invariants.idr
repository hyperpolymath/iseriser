-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Semantic proof for TypedQLiser's `NullSafe` level (level 4: "nullable paths
||| explicitly handled").
|||
||| This is the Layer-3, *deeper* companion to `Semantics.InjectionFree` (level
||| 5). Where InjectionFree is a purely structural property (no `RawSplice` node
||| occurs anywhere), null-safety is genuinely **context-sensitive**: whether a
||| projected nullable column may be returned depends on what the WHERE clause
||| has guarded. The novel ingredient is *guard discovery with disjunctive
||| weakening*:
|||
|||   * A comparison `Cmp col v` in the WHERE clause is, in SQL three-valued
|||     logic, NULL (and so filters the row) when `col` is NULL — it therefore
|||     **guards** `col`, establishing that any surviving row has `col` non-null.
|||   * Under `And p q`, a column is guarded if EITHER conjunct guards it (each
|||     conjunct must hold, so either filter suffices) — set union.
|||   * Under `Or p q`, a column is guarded only if BOTH branches guard it, since
|||     a surviving row may have satisfied either branch — set intersection.
|||   * A SELECTed nullable column is null-safe only if the WHERE clause guards
|||     it; a non-nullable projected column is always safe.
|||
||| The disjunctive weakening (intersection under `Or`) is what makes this strict
||| ly deeper than the InjectionFree structural check, and distinct from
||| SchemaBound (membership) and TypeCompat (type matching): the same projected
||| column can be safe or unsafe depending on the boolean shape of the WHERE
||| predicate, not merely on which nodes occur.
|||
||| Contents:
|||   1. `guardsOf`, the columns a WHERE predicate guards (`And` = union, `Or` =
|||      intersection);
|||   2. `ColNullSafe`/`QueryNullSafe`, the proposition that every projected
|||      nullable column is guarded;
|||   3. `decQueryNullSafe`, a sound + complete decision procedure (`Dec`);
|||   4. `certifyNullSafeSound` (a `Proven` verdict entails the property), the
|||      level-ordinal identity, and positive + non-vacuity controls.
|||
||| The query AST (`Query`/`Pred`/`Value`) is reused verbatim from `Semantics`.

module Typedqliser.ABI.Invariants

import Typedqliser.ABI.Types
import Typedqliser.ABI.Semantics
import Data.List
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Nullable-column environment + guard discovery
--------------------------------------------------------------------------------

||| The set of column names declared NULLABLE. A column not in this set is
||| non-nullable and may be projected freely.
public export
NullEnv : Type
NullEnv = List String

||| Set intersection of column-name lists, written so it *reduces*
||| definitionally on concrete literals (`Data.List.intersect` gets stuck under
||| its `Eq` wrapper, which would block the `Refl`/`impossible` controls).
||| Keeps a left-hand column iff it also appears on the right.
public export
inter : List String -> List String -> List String
inter xs ys = filter (\x => elem x ys) xs

||| Set union of column-name lists (right side appended where absent), likewise
||| written to reduce on literals.
public export
uni : List String -> List String -> List String
uni xs ys = xs ++ filter (\y => not (elem y xs)) ys

||| The columns a WHERE predicate GUARDS (proves non-null for surviving rows).
||| A bare comparison guards its column; `And` takes the union (either filter
||| suffices, since both conjuncts must hold); `Or` takes the intersection (only
||| columns guarded on BOTH branches survive, since either branch may have held).
public export
guardsOf : Pred -> List String
guardsOf (Cmp col _) = [col]
guardsOf (And p q)   = uni (guardsOf p) (guardsOf q)
guardsOf (Or p q)    = inter (guardsOf p) (guardsOf q)

||| Decidable membership of a column name in a string list, as a real `Dec`.
public export
decColElem : (c : String) -> (xs : List String) -> Dec (Elem c xs)
decColElem c xs = isElem c xs

--------------------------------------------------------------------------------
-- NullSafe as a genuine, context-sensitive proposition
--------------------------------------------------------------------------------

||| `ColNullSafe env gs col` holds when projecting `col` is null-safe given the
||| nullable set `env` and the set of columns `gs` guarded by the WHERE clause:
||| either `col` is not nullable, or it has been guarded. There is no third
||| constructor, so projecting an unguarded nullable column has no proof — the
||| heart of the guarantee.
public export
data ColNullSafe : (env : NullEnv) -> (gs : List String) -> (col : String) -> Type where
  ||| `col` is not in the nullable set, so projecting it is unconditionally safe.
  NotNullable : Not (Elem col env) -> ColNullSafe env gs col
  ||| `col` is nullable but the WHERE clause guards it.
  Guarded     : Elem col gs -> ColNullSafe env gs col

||| Every projected column is null-safe under the WHERE clause's guard set.
public export
data ColsNullSafe : (env : NullEnv) -> (gs : List String) -> List String -> Type where
  NilNS  : ColsNullSafe env gs []
  ConsNS : ColNullSafe env gs col -> ColsNullSafe env gs cols ->
           ColsNullSafe env gs (col :: cols)

||| A query is null-safe when every column it PROJECTS is null-safe with respect
||| to the columns its WHERE predicate guards.
public export
data QueryNullSafe : (env : NullEnv) -> Query -> Type where
  SelectNS : ColsNullSafe env (guardsOf w) cols ->
             QueryNullSafe env (Select t cols w)

--------------------------------------------------------------------------------
-- Refutation helper
--------------------------------------------------------------------------------

||| A nullable, unguarded column cannot be `ColNullSafe`.
notColNullSafe : Elem col env -> Not (Elem col gs) -> Not (ColNullSafe env gs col)
notColNullSafe inEnv _   (NotNullable notIn) = notIn inEnv
notColNullSafe _     notG (Guarded g)        = notG g

--------------------------------------------------------------------------------
-- Sound + complete decision procedure (returns a real proof)
--------------------------------------------------------------------------------

||| Decide one projected column. Nullable + unguarded is the only refuted case.
public export
decColNullSafe : (env : NullEnv) -> (gs : List String) -> (col : String) ->
                 Dec (ColNullSafe env gs col)
decColNullSafe env gs col = case decColElem col env of
  No notIn  => Yes (NotNullable notIn)
  Yes inEnv => case decColElem col gs of
    Yes g   => Yes (Guarded g)
    No notG => No (notColNullSafe inEnv notG)

||| Decide a whole projection list.
public export
decColsNullSafe : (env : NullEnv) -> (gs : List String) -> (cols : List String) ->
                  Dec (ColsNullSafe env gs cols)
decColsNullSafe env gs []           = Yes NilNS
decColsNullSafe env gs (col :: cols) = case decColNullSafe env gs col of
  No nc  => No (\(ConsNS c _) => nc c)
  Yes c  => case decColsNullSafe env gs cols of
    Yes cs => Yes (ConsNS c cs)
    No ncs => No (\(ConsNS _ cs) => ncs cs)

||| The headline decision procedure: decide query null-safety, returning a
||| genuine `QueryNullSafe` witness when it holds.
public export
decQueryNullSafe : (env : NullEnv) -> (q : Query) -> Dec (QueryNullSafe env q)
decQueryNullSafe env (Select t cols w) = case decColsNullSafe env (guardsOf w) cols of
  Yes ok => Yes (SelectNS ok)
  No no   => No (\(SelectNS ok) => no ok)

--------------------------------------------------------------------------------
-- Certifier soundness: a `Proven` NullSafe status is never a lie
--------------------------------------------------------------------------------

||| Certify the NullSafe (level 4) obligation for a query against a nullable set.
||| `Proven` is emitted only when the decision procedure produced a real proof.
public export
certifyNullSafe : (env : NullEnv) -> (q : Query) -> ProofStatus
certifyNullSafe env q = case decQueryNullSafe env q of
  Yes _ => Proven
  No _  => Refuted

||| Soundness: if the certifier reports `Proven`, the query really is null-safe.
||| (As `decQueryNullSafe` is a `Dec`, a query that is *not* null-safe can never
||| be reported `Proven`.)
export
certifyNullSafeSound : (env : NullEnv) -> (q : Query) ->
                       certifyNullSafe env q = Proven -> QueryNullSafe env q
certifyNullSafeSound env q prf with (decQueryNullSafe env q)
  certifyNullSafeSound env q prf  | Yes ok = ok
  certifyNullSafeSound env q Refl | No _ impossible

||| `NullSafe` is level 4 — distinct from InjectionFree (level 5).
export
nullSafeIsLevelFour : levelNat NullSafe = 4
nullSafeIsLevelFour = Refl

||| And it is a strictly different obligation from the Layer-2 theorem
||| (InjectionFree, level 5): their ordinals are not equal.
export
nullSafeNotInjectionFree : levelNat NullSafe = levelNat InjectionFree -> Void
nullSafeNotInjectionFree Refl impossible

--------------------------------------------------------------------------------
-- Positive controls
--------------------------------------------------------------------------------

||| The nullable set for the controls: only `email` may be NULL.
public export
nullableCols : NullEnv
nullableCols = ["email"]

||| `SELECT email FROM users WHERE email = $1`.
||| Projecting nullable `email` is null-safe because the WHERE comparison on
||| `email` guards it (a NULL email is filtered out).
public export
guardedQuery : Query
guardedQuery = Select "users" ["email"] (Cmp "email" (Param 1))

||| Machine-checked: the guarded query is null-safe.
export
guardedQueryNullSafe : QueryNullSafe Invariants.nullableCols Invariants.guardedQuery
guardedQueryNullSafe = SelectNS (ConsNS (Guarded Here) NilNS)

||| …and the certifier reports `Proven` for it (computes to `Proven`).
export
guardedQueryCertifiesProven :
  certifyNullSafe Invariants.nullableCols Invariants.guardedQuery = Proven
guardedQueryCertifiesProven = Refl

||| Second positive control: a non-nullable projected column needs no guard.
||| `SELECT id FROM users WHERE email = $1` — `id` is not nullable.
public export
nonNullQuery : Query
nonNullQuery = Select "users" ["id"] (Cmp "email" (Param 1))

export
nonNullQueryNullSafe : QueryNullSafe Invariants.nullableCols Invariants.nonNullQuery
nonNullQueryNullSafe = SelectNS (ConsNS (NotNullable idNotNullable) NilNS)
  where
    idNotNullable : Not (Elem "id" ["email"])
    idNotNullable (There rest) impossible

||| Third positive control: `And` guards via union. `SELECT email ... WHERE
||| id = $1 AND email = $2` — the second conjunct guards `email`.
public export
andGuardedQuery : Query
andGuardedQuery =
  Select "users" ["email"]
    (And (Cmp "id" (Param 1)) (Cmp "email" (Param 2)))

export
andGuardedQueryCertifiesProven :
  certifyNullSafe Invariants.nullableCols Invariants.andGuardedQuery = Proven
andGuardedQueryCertifiesProven = Refl

--------------------------------------------------------------------------------
-- Non-vacuity / negative controls: an unguarded nullable projection has no proof
--------------------------------------------------------------------------------

||| `SELECT email FROM users WHERE id = $1`.
||| Nullable `email` is projected but only `id` is guarded — the returned email
||| may be NULL, so there is no null-safety proof.
public export
unguardedQuery : Query
unguardedQuery = Select "users" ["email"] (Cmp "id" (Param 1))

||| Machine-checked non-vacuity: there is **no** `QueryNullSafe` proof. Were the
||| property vacuous, this would be unprovable; that it holds shows the guard
||| discipline bites.
export
unguardedQueryNotNullSafe :
  Not (QueryNullSafe Invariants.nullableCols Invariants.unguardedQuery)
unguardedQueryNotNullSafe (SelectNS (ConsNS ok _)) = case ok of
  NotNullable notIn => notIn Here
  Guarded g         => emailNotInId g
  where
    emailNotInId : Not (Elem "email" ["id"])
    emailNotInId (There rest) impossible

||| And the certifier refuses (computes to `Refuted`, not `Proven`).
export
unguardedQueryCertifiesRefuted :
  certifyNullSafe Invariants.nullableCols Invariants.unguardedQuery = Refuted
unguardedQueryCertifiesRefuted = Refl

||| Disjunctive weakening control: `SELECT email ... WHERE email = $1 OR id = $2`.
||| Although the LEFT branch guards `email`, the right branch does not, and `Or`
||| keeps only the intersection — so `email` ends up UNGUARDED. A row could have
||| satisfied `id = $2` with a NULL email. Machine-checked: no proof. This is the
||| case the structural (InjectionFree) view would miss entirely.
public export
orWeakenedQuery : Query
orWeakenedQuery =
  Select "users" ["email"]
    (Or (Cmp "email" (Param 1)) (Cmp "id" (Param 2)))

export
orWeakenedQueryNotNullSafe :
  Not (QueryNullSafe Invariants.nullableCols Invariants.orWeakenedQuery)
orWeakenedQueryNotNullSafe (SelectNS (ConsNS ok _)) = case ok of
  NotNullable notIn => notIn Here
  Guarded g         => emailNotGuarded g
  where
    -- `guardsOf (Or (Cmp "email" _) (Cmp "id" _)) = inter ["email"] ["id"]`
    -- reduces to `[]`, which has no `Elem`.
    emailNotGuarded : Not (Elem "email" (inter ["email"] ["id"]))
    emailNotGuarded Here impossible
    emailNotGuarded (There rest) impossible
