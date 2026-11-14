-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Semantic proof for TypedQLiser's `SchemaBound` level (level 2:
||| "all references resolve in the schema").
|||
||| Where `Semantics.idr` makes `InjectionFree` (level 5) a real, machine-checked
||| property, this module does the same for `SchemaBound` (level 2): a query is
||| schema-bound when its table resolves in a schema and *every* column it
||| references — both the projected columns and those mentioned in the WHERE
||| predicate — is declared for that table. It provides:
|||
|||   1. a `Schema` of table definitions (name + declared columns);
|||   2. `QuerySchemaBound`, the proposition that the query's table resolves and
|||      all referenced columns are declared;
|||   3. `decSchemaBound`, a sound + complete decision procedure returning a
|||      genuine `Dec`, so a "Proven" SchemaBound certificate is backed by a
|||      constructive witness and a dangling reference can never be certified;
|||   4. a certifier whose `Proven` verdict is *proven* to entail the property
|||      (`certifySchemaBoundSound`), plus positive and negative controls.
|||
||| The query AST (`Query`/`Pred`/`Value`) is reused verbatim from `Semantics`.

module Typedqliser.ABI.SchemaBound

import Typedqliser.ABI.Types
import Typedqliser.ABI.Semantics
import Data.List
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- A minimal but faithful schema model
--------------------------------------------------------------------------------

||| One table: its name and the columns it declares.
public export
record TableDef where
  constructor MkTable
  tableName    : String
  tableColumns : List String

||| A schema is a list of table definitions.
public export
Schema : Type
Schema = List TableDef

||| Resolve a table's declared columns by name (first match wins, as in a real
||| catalogue with unique table names). `Nothing` when the table is absent.
public export
tableCols : String -> Schema -> Maybe (List String)
tableCols _ []                        = Nothing
tableCols t (MkTable nm cs :: rest)   = if nm == t then Just cs else tableCols t rest

||| Every column a predicate references in a comparison.
public export
predRefs : Pred -> List String
predRefs (Cmp col _) = [col]
predRefs (And p q)   = predRefs p ++ predRefs q
predRefs (Or p q)    = predRefs p ++ predRefs q

--------------------------------------------------------------------------------
-- "Every reference is a declared column" as a genuine proposition
--------------------------------------------------------------------------------

||| `AllBound cols refs` holds when every name in `refs` is an element of `cols`.
||| There is no constructor that admits a `ref` absent from `cols`, so a dangling
||| reference makes the proposition uninhabited.
public export
data AllBound : (cols : List String) -> (refs : List String) -> Type where
  ABNil  : AllBound cols []
  ABCons : Elem r cols -> AllBound cols rs -> AllBound cols (r :: rs)

||| Sound + complete decision for `AllBound`, structurally over `refs`.
public export
decAllBound : (cols : List String) -> (refs : List String) -> Dec (AllBound cols refs)
decAllBound _    []        = Yes ABNil
decAllBound cols (r :: rs) = case isElem r cols of
  No nel  => No (\(ABCons el _) => nel el)
  Yes el  => case decAllBound cols rs of
    Yes rest => Yes (ABCons el rest)
    No nrest => No (\(ABCons _ rest) => nrest rest)

||| A query is schema-bound when its table resolves to some declared column set
||| `cols`, and all referenced columns (projected ++ predicate) are in `cols`.
||| The stored `tableCols t s = Just cols` equation pins `cols` to the (total,
||| deterministic) resolver — so completeness needs no separate uniqueness lemma.
public export
data QuerySchemaBound : Schema -> Query -> Type where
  MkSB :
    (cols : List String) ->
    (resolves : tableCols t s = Just cols) ->
    AllBound cols (sel ++ predRefs w) ->
    QuerySchemaBound s (Select t sel w)

--------------------------------------------------------------------------------
-- Sound + complete decision procedure (returns a real proof)
--------------------------------------------------------------------------------

||| Decide schema-boundedness, returning a genuine `QuerySchemaBound` witness
||| when it holds. The `proof eq` binding gives the resolver equation both the
||| `Yes` witness and the `No` refutation need.
public export
decSchemaBound : (s : Schema) -> (q : Query) -> Dec (QuerySchemaBound s q)
decSchemaBound s (Select t sel w) with (tableCols t s) proof eq
  _ | Nothing = No $ \(MkSB cols prf _) => case trans (sym eq) prf of Refl impossible
  _ | Just cs = case decAllBound cs (sel ++ predRefs w) of
      Yes ab => Yes (MkSB cs eq ab)
      No nab => No $ \(MkSB cols prf ab) => case trans (sym prf) eq of Refl => nab ab

--------------------------------------------------------------------------------
-- Certifier soundness: a `Proven` SchemaBound status is never a lie
--------------------------------------------------------------------------------

||| Certify the SchemaBound (level 2) obligation for a query against a schema.
||| `Proven` is emitted only when the decision procedure produced a real proof.
public export
certifySchemaBound : (s : Schema) -> (q : Query) -> ProofStatus
certifySchemaBound s q = case decSchemaBound s q of
  Yes _ => Proven
  No _  => Refuted

||| Soundness: if the certifier reports `Proven`, the query really is schema-bound
||| against that schema. With `decSchemaBound` being a `Dec`, a query that is not
||| schema-bound can therefore never be reported `Proven`.
export
certifySchemaBoundSound : (s : Schema) -> (q : Query) ->
  certifySchemaBound s q = Proven -> QuerySchemaBound s q
certifySchemaBoundSound s q prf with (decSchemaBound s q)
  certifySchemaBoundSound s q prf  | Yes ok = ok
  certifySchemaBoundSound s q Refl | No _ impossible

||| `SchemaBound` is level 2 — the certified obligation is the second of ten.
export
schemaBoundIsLevelTwo : levelNat SchemaBound = 2
schemaBoundIsLevelTwo = Refl

--------------------------------------------------------------------------------
-- Positive control: a query over declared columns is provably schema-bound
--------------------------------------------------------------------------------

||| A one-table schema: `users(id, name, email)`.
public export
exampleSchema : Schema
exampleSchema = [MkTable "users" ["id", "name", "email"]]

||| `SELECT id, name FROM users WHERE email = $1` — all references declared.
public export
boundQuery : Query
boundQuery = Select "users" ["id", "name"] (Cmp "email" (Param 1))

||| Machine-checked: the query is schema-bound against `exampleSchema`.
export
boundQuerySchemaBound : QuerySchemaBound SchemaBound.exampleSchema SchemaBound.boundQuery
boundQuerySchemaBound =
  MkSB ["id", "name", "email"] Refl
    (ABCons Here (ABCons (There Here) (ABCons (There (There Here)) ABNil)))

||| …and the certifier reports `Proven` for it (computes to `Proven`).
export
boundQueryCertifiesProven :
  certifySchemaBound SchemaBound.exampleSchema SchemaBound.boundQuery = Proven
boundQueryCertifiesProven = Refl

--------------------------------------------------------------------------------
-- Negative control: a dangling column reference CANNOT be certified
--------------------------------------------------------------------------------

||| `ssn` is not a declared column of `users`.
ssnNotInUsers : Not (Elem "ssn" ["id", "name", "email"])
ssnNotInUsers Here impossible
ssnNotInUsers (There Here) impossible
ssnNotInUsers (There (There Here)) impossible
ssnNotInUsers (There (There (There later))) = absurd later

||| The reference list `["id", "ssn", "id"]` is not all-bound by `users`'s
||| columns, because `ssn` is not among them. A top-level helper (rather than a
||| nested `case`) so coverage is checked against the concrete reference list.
noSsnBound : Not (AllBound ["id", "name", "email"] ["id", "ssn", "id"])
noSsnBound (ABCons _ (ABCons ssnEl _)) = ssnNotInUsers ssnEl

||| `Just` is injective. A top-level function clause (its `Refl` covers cleanly,
||| whereas an inline `case … of Refl` on the resolver equation does not, because
||| coverage does not reduce `tableCols` under the lifted case scrutinee).
justInj : Just x = Just y -> x = y
justInj Refl = Refl

||| `SELECT id, ssn FROM users WHERE id = $1` — `ssn` is a dangling reference.
public export
unboundQuery : Query
unboundQuery = Select "users" ["id", "ssn"] (Cmp "id" (Param 1))

||| Machine-checked: there is **no** proof that the query is schema-bound — the
||| dangling `ssn` reference has no `Elem` witness, so the property is genuinely
||| refuted (this is what makes the guarantee non-vacuous).
export
unboundQueryNotSchemaBound : Not (QuerySchemaBound SchemaBound.exampleSchema SchemaBound.unboundQuery)
unboundQueryNotSchemaBound (MkSB cols prf ab) =
  -- Transport `ab` along `cols = ["id","name","email"]` (derived by injectivity
  -- from the resolver equation) at the term level — no `case … of Refl`, so the
  -- coverage checker never has to reduce `tableCols` under a lifted scrutinee.
  noSsnBound
    (replace {p = \c => AllBound c ["id", "ssn", "id"]}
             (sym (justInj (the (Just ["id", "name", "email"] = Just cols) prf)))
             ab)
