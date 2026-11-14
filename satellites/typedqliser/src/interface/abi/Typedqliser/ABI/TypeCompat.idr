-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Semantic proof for TypedQLiser's `TypeCompat` level (level 3:
||| "operand types compatible").
|||
||| Alongside `Semantics.InjectionFree` (level 5) and `SchemaBound.SchemaBound`
||| (level 2), this makes `TypeCompat` (level 3) a real, machine-checked property
||| over the shared query AST: every comparison in the WHERE predicate compares a
||| column against a value whose type matches the column's declared type. A bound
||| parameter adopts the column's type (so it is always compatible); a literal is
||| `TInt` and a raw string is `TText`, so comparing them against a column of a
||| different type has *no* proof. It provides:
|||
|||   1. a small SQL type universe and a typed column environment;
|||   2. `ValueCompat`/`PredTypeCompat`/`QueryTypeCompat` — the proposition that
|||      every comparison's operands are type-compatible (uninhabited on a clash);
|||   3. `decQueryTypeCompat`, a sound + complete `Dec`, so "Proven" is backed by
|||      a constructive witness and a type clash can never be certified;
|||   4. a certifier proven sound (`certifyTypeCompatSound`), level-ordinal
|||      identity, and positive + negative controls.
|||
||| The query AST (`Query`/`Pred`/`Value`) is reused verbatim from `Semantics`.

module Typedqliser.ABI.TypeCompat

import Typedqliser.ABI.Types
import Typedqliser.ABI.Semantics

%default total

--------------------------------------------------------------------------------
-- A minimal SQL type universe + typed column environment
--------------------------------------------------------------------------------

||| The column/value types this level distinguishes.
public export
data SqlType = TInt | TText | TBool

||| A typed column environment: declared columns with their types (the resolved
||| form of a table's schema, as produced by the SchemaBound level).
public export
ColEnv : Type
ColEnv = List (String, SqlType)

||| Resolve a column's declared type by name (first match wins).
public export
lookupType : String -> ColEnv -> Maybe SqlType
lookupType _ []              = Nothing
lookupType c ((n, ty) :: xs) = if n == c then Just ty else lookupType c xs

||| `Just` is injective. A top-level function clause (its `Refl` covers cleanly,
||| whereas an inline `case … of Refl` on a resolver equation does not, because
||| coverage does not reduce `lookupType` under a lifted scrutinee).
justInj : Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Value/column type compatibility as a genuine proposition
--------------------------------------------------------------------------------

||| `ValueCompat ct v` holds when value `v` may be compared against a column of
||| type `ct`. A bound parameter adopts any column type; a literal is `TInt`; a
||| raw splice is `TText`. There is no constructor for a mismatch (e.g. a literal
||| against a `TText` column), so such a `ValueCompat` is uninhabited.
public export
data ValueCompat : (ct : SqlType) -> Value -> Type where
  ParamAny  : ValueCompat ct (Param i)        -- a bound parameter adopts ct
  LitInt    : ValueCompat TInt (Lit n)        -- integer literal ↔ TInt column
  SpliceTxt : ValueCompat TText (RawSplice s) -- string splice ↔ TText column

-- Refutations of the type clashes (single impossible clauses; the value index
-- prunes the non-matching constructors).
litNotText : Not (ValueCompat TText (Lit n))
litNotText LitInt impossible

litNotBool : Not (ValueCompat TBool (Lit n))
litNotBool LitInt impossible

spliceNotInt : Not (ValueCompat TInt (RawSplice s))
spliceNotInt SpliceTxt impossible

spliceNotBool : Not (ValueCompat TBool (RawSplice s))
spliceNotBool SpliceTxt impossible

||| Sound + complete decision for one value against a column type.
public export
decValueCompat : (ct : SqlType) -> (v : Value) -> Dec (ValueCompat ct v)
decValueCompat _    (Param i)      = Yes ParamAny
decValueCompat TInt  (Lit n)       = Yes LitInt
decValueCompat TText (Lit n)       = No litNotText
decValueCompat TBool (Lit n)       = No litNotBool
decValueCompat TInt  (RawSplice s) = No spliceNotInt
decValueCompat TText (RawSplice s) = Yes SpliceTxt
decValueCompat TBool (RawSplice s) = No spliceNotBool

||| A predicate is type-compatible (w.r.t. an environment) when every comparison
||| resolves its column's type and the compared value matches that type.
public export
data PredTypeCompat : (env : ColEnv) -> Pred -> Type where
  CmpTC : (colType : lookupType col env = Just ct) -> ValueCompat ct v ->
          PredTypeCompat env (Cmp col v)
  AndTC : PredTypeCompat env p -> PredTypeCompat env q -> PredTypeCompat env (And p q)
  OrTC  : PredTypeCompat env p -> PredTypeCompat env q -> PredTypeCompat env (Or p q)

||| Sound + complete decision for predicate type-compatibility. The `Cmp` case
||| resolves the column type via a `proof`-bound equation, exactly as the
||| SchemaBound level resolves table columns.
public export
decPredTypeCompat : (env : ColEnv) -> (p : Pred) -> Dec (PredTypeCompat env p)
decPredTypeCompat env (Cmp col v) with (lookupType col env) proof eq
  _ | Nothing = No $ \(CmpTC colType _) => case trans (sym eq) colType of Refl impossible
  _ | Just ct = case decValueCompat ct v of
      Yes vc => Yes (CmpTC eq vc)
      No nvc => No $ \(CmpTC colType vc) => case trans (sym colType) eq of Refl => nvc vc
decPredTypeCompat env (And p q) = case decPredTypeCompat env p of
  No np  => No (\(AndTC pp _) => np pp)
  Yes pp => case decPredTypeCompat env q of
    Yes qq => Yes (AndTC pp qq)
    No nq  => No (\(AndTC _ qq) => nq qq)
decPredTypeCompat env (Or p q) = case decPredTypeCompat env p of
  No np  => No (\(OrTC pp _) => np pp)
  Yes pp => case decPredTypeCompat env q of
    Yes qq => Yes (OrTC pp qq)
    No nq  => No (\(OrTC _ qq) => nq qq)

||| A query is type-compatible when its WHERE predicate is.
public export
data QueryTypeCompat : (env : ColEnv) -> Query -> Type where
  MkQTC : PredTypeCompat env w -> QueryTypeCompat env (Select t sel w)

||| The headline decision procedure for the query level.
public export
decQueryTypeCompat : (env : ColEnv) -> (q : Query) -> Dec (QueryTypeCompat env q)
decQueryTypeCompat env (Select t sel w) = case decPredTypeCompat env w of
  Yes pc => Yes (MkQTC pc)
  No npc => No (\(MkQTC pc) => npc pc)

--------------------------------------------------------------------------------
-- Certifier soundness: a `Proven` TypeCompat status is never a lie
--------------------------------------------------------------------------------

||| Certify the TypeCompat (level 3) obligation for a query against a typed
||| environment. `Proven` only when the decision procedure produced a real proof.
public export
certifyTypeCompat : (env : ColEnv) -> (q : Query) -> ProofStatus
certifyTypeCompat env q = case decQueryTypeCompat env q of
  Yes _ => Proven
  No _  => Refuted

||| Soundness: a `Proven` verdict entails the property. With `decQueryTypeCompat`
||| being a `Dec`, a type-incompatible query can never be reported `Proven`.
export
certifyTypeCompatSound : (env : ColEnv) -> (q : Query) ->
  certifyTypeCompat env q = Proven -> QueryTypeCompat env q
certifyTypeCompatSound env q prf with (decQueryTypeCompat env q)
  certifyTypeCompatSound env q prf  | Yes ok = ok
  certifyTypeCompatSound env q Refl | No _ impossible

||| `TypeCompat` is level 3 — the certified obligation is the third of ten.
export
typeCompatIsLevelThree : levelNat TypeCompat = 3
typeCompatIsLevelThree = Refl

--------------------------------------------------------------------------------
-- Positive control: a well-typed query is provably type-compatible
--------------------------------------------------------------------------------

||| `users(id : Int, name : Text, age : Int)`.
public export
exampleEnv : ColEnv
exampleEnv = [("id", TInt), ("name", TText), ("age", TInt)]

||| `SELECT id, name FROM users WHERE age = 18 AND name = $1` — `age` (Int) vs an
||| integer literal, and `name` (Text) vs a bound parameter: both compatible.
public export
goodQuery : Query
goodQuery =
  Select "users" ["id", "name"] (And (Cmp "age" (Lit 18)) (Cmp "name" (Param 1)))

||| Machine-checked: the query is type-compatible against `exampleEnv`.
export
goodQueryTypeCompat : QueryTypeCompat TypeCompat.exampleEnv TypeCompat.goodQuery
goodQueryTypeCompat = MkQTC (AndTC (CmpTC Refl LitInt) (CmpTC Refl ParamAny))

||| …and the certifier reports `Proven` for it (computes to `Proven`).
export
goodQueryCertifiesProven :
  certifyTypeCompat TypeCompat.exampleEnv TypeCompat.goodQuery = Proven
goodQueryCertifiesProven = Refl

--------------------------------------------------------------------------------
-- Negative control: a type clash CANNOT be certified
--------------------------------------------------------------------------------

||| `SELECT id FROM users WHERE name = 42` — comparing a `Text` column against an
||| integer literal is a type clash.
public export
badQuery : Query
badQuery = Select "users" ["id"] (Cmp "name" (Lit 42))

||| Machine-checked: there is **no** proof that the clash is type-compatible.
||| `name` resolves to `TText`, but `ValueCompat TText (Lit 42)` is uninhabited,
||| so the property is genuinely refuted (this is what makes it non-vacuous).
||| The witness is transported at the term level (`replace`/`justInj`) rather
||| than via `case … of Refl`, which coverage rejects on the stuck resolver LHS.
export
badQueryNotTypeCompat : Not (QueryTypeCompat TypeCompat.exampleEnv TypeCompat.badQuery)
badQueryNotTypeCompat (MkQTC (CmpTC {ct} colType vc)) =
  litNotText (replace {p = \x => ValueCompat x (Lit 42)} (sym (justInj colType)) vc)
