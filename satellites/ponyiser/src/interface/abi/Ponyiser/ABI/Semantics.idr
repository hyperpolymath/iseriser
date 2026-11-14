-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Ponyiser: aliasing-compatibility soundness.
|||
||| Pony's reference capabilities guarantee data-race freedom by restricting
||| which pairs of capabilities may simultaneously alias the SAME object. The
||| headline soundness fact proved here:
|||
|||   Two writable aliases to the same object are NEVER compatible.
|||
||| In Pony, a capability is *writable* if it grants mutation: iso (unique
||| read/write), ref (local read/write), trn (write-unique). If two aliases
||| could both write, an actor (or two actors) could race on the same memory.
||| The compatibility relation `Compatible` below has NO constructor that pairs
||| two writable capabilities, so `writableNotCompatible` discharges every such
||| pairing, and the `iso`-uniqueness rule has no constructor pairing `iso` with
||| anything at all.
|||
||| @see https://www.ponylang.io/
||| @see https://tutorial.ponylang.io/reference-capabilities/

module Ponyiser.ABI.Semantics

import Ponyiser.ABI.Types
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Writability: a faithful model of which caps grant write access
--------------------------------------------------------------------------------

||| A capability is *writable* iff it permits mutation of the referent.
||| Pony's writable capabilities are exactly iso, ref, and trn.
||| val (immutable), box (read-only), tag (opaque) do NOT grant write access.
public export
data Writable : RefCapability -> Type where
  IsoWrite : Writable Iso
  RefWrite : Writable Ref
  TrnWrite : Writable Trn

||| The non-writable capabilities have no `Writable` proof.
export
Uninhabited (Writable Val) where
  uninhabited IsoWrite impossible
  uninhabited RefWrite impossible
  uninhabited TrnWrite impossible

export
Uninhabited (Writable Box) where
  uninhabited IsoWrite impossible
  uninhabited RefWrite impossible
  uninhabited TrnWrite impossible

export
Uninhabited (Writable Tag) where
  uninhabited IsoWrite impossible
  uninhabited RefWrite impossible
  uninhabited TrnWrite impossible

||| Sound + complete decision for writability.
public export
isWritable : (cap : RefCapability) -> Dec (Writable cap)
isWritable Iso = Yes IsoWrite
isWritable Ref = Yes RefWrite
isWritable Trn = Yes TrnWrite
isWritable Val = No absurd
isWritable Box = No absurd
isWritable Tag = No absurd

--------------------------------------------------------------------------------
-- Aliasing compatibility (the headline relation)
--------------------------------------------------------------------------------

||| `Compatible a b` holds iff a capability `a` and a capability `b` may
||| SIMULTANEOUSLY alias the same object without breaking data-race freedom.
|||
||| The faithful rule set (Pony's denotation, restricted to alias coexistence):
|||
|||  * `iso` demands a UNIQUE reference: it is compatible with NOTHING, not even
|||    itself. (There is deliberately no constructor mentioning `Iso`.)
|||  * At most ONE writable alias may exist. So a writable cap may only coexist
|||    with a read-only cap, and two writable caps are never compatible.
|||      - `ref` (local read/write) may coexist with `box` read-only aliases.
|||      - `trn` (write-unique) may coexist with `box` read-only aliases.
|||  * Read-only caps coexist freely among themselves:
|||      - `val` (deeply immutable) with `val`, `box`, `tag`.
|||      - `box` with `box`, `tag`.
|||      - `tag` (opaque identity) with `tag`.
|||
||| Symmetry is built in by giving both orientations of the mixed rules.
||| Crucially, the relation has NO constructor whose BOTH arguments are
||| writable, and NO constructor mentioning `Iso`.
public export
data Compatible : RefCapability -> RefCapability -> Type where
  ||| one writable `ref` with a read-only `box` alias
  RefBoxAlias  : Compatible Ref Box
  BoxRefAlias  : Compatible Box Ref
  ||| one writable `trn` with a read-only `box` alias
  TrnBoxAlias  : Compatible Trn Box
  BoxTrnAlias  : Compatible Box Trn
  ||| immutable val coexists with read-only aliases
  ValValAlias  : Compatible Val Val
  ValBoxAlias  : Compatible Val Box
  BoxValAlias  : Compatible Box Val
  ValTagAlias  : Compatible Val Tag
  TagValAlias  : Compatible Tag Val
  ||| box read-only aliases coexist
  BoxBoxAlias  : Compatible Box Box
  BoxTagAlias  : Compatible Box Tag
  TagBoxAlias  : Compatible Tag Box
  ||| opaque tag identities coexist
  TagTagAlias  : Compatible Tag Tag

--------------------------------------------------------------------------------
-- HEADLINE SOUNDNESS: two writable aliases are never compatible
--------------------------------------------------------------------------------

||| The flagship theorem. If both capabilities are writable, they cannot be
||| compatible aliases. Proved by exhausting every `Compatible` constructor:
||| in each case at least one side is provably non-writable (or is `Iso`, which
||| has no `Compatible` constructor at all, so those cases never arise).
|||
||| This is the data-race-freedom guarantee at the alias level: you can never
||| hold two simultaneously-mutating views of the same object.
public export
writableNotCompatible : Writable a -> Writable b -> Not (Compatible a b)
-- iso never appears in Compatible, so any Compatible with an Iso side is absurd
-- by the constructor's own indices; the remaining writable pairs are ref/trn.
writableNotCompatible RefWrite RefWrite RefBoxAlias impossible
writableNotCompatible RefWrite RefWrite BoxRefAlias impossible
writableNotCompatible RefWrite TrnWrite RefBoxAlias impossible
writableNotCompatible RefWrite TrnWrite BoxRefAlias impossible
writableNotCompatible TrnWrite RefWrite TrnBoxAlias impossible
writableNotCompatible TrnWrite RefWrite BoxTrnAlias impossible
writableNotCompatible TrnWrite TrnWrite TrnBoxAlias impossible
writableNotCompatible TrnWrite TrnWrite BoxTrnAlias impossible

||| Corollary: `iso` is incompatible with EVERY capability (uniqueness).
||| There is no `Compatible` constructor mentioning `Iso` on either side, so
||| both directions are discharged by `impossible` over all constructors.
public export
isoIncompatibleLeft : (b : RefCapability) -> Not (Compatible Iso b)
isoIncompatibleLeft _ RefBoxAlias  impossible
isoIncompatibleLeft _ BoxRefAlias  impossible
isoIncompatibleLeft _ TrnBoxAlias  impossible
isoIncompatibleLeft _ BoxTrnAlias  impossible
isoIncompatibleLeft _ ValValAlias  impossible
isoIncompatibleLeft _ ValBoxAlias  impossible
isoIncompatibleLeft _ BoxValAlias  impossible
isoIncompatibleLeft _ ValTagAlias  impossible
isoIncompatibleLeft _ TagValAlias  impossible
isoIncompatibleLeft _ BoxBoxAlias  impossible
isoIncompatibleLeft _ BoxTagAlias  impossible
isoIncompatibleLeft _ TagBoxAlias  impossible
isoIncompatibleLeft _ TagTagAlias  impossible

public export
isoIncompatibleRight : (a : RefCapability) -> Not (Compatible a Iso)
isoIncompatibleRight _ RefBoxAlias  impossible
isoIncompatibleRight _ BoxRefAlias  impossible
isoIncompatibleRight _ TrnBoxAlias  impossible
isoIncompatibleRight _ BoxTrnAlias  impossible
isoIncompatibleRight _ ValValAlias  impossible
isoIncompatibleRight _ ValBoxAlias  impossible
isoIncompatibleRight _ BoxValAlias  impossible
isoIncompatibleRight _ ValTagAlias  impossible
isoIncompatibleRight _ TagValAlias  impossible
isoIncompatibleRight _ BoxBoxAlias  impossible
isoIncompatibleRight _ BoxTagAlias  impossible
isoIncompatibleRight _ TagBoxAlias  impossible
isoIncompatibleRight _ TagTagAlias  impossible

--------------------------------------------------------------------------------
-- Sound + complete decision procedure for compatibility
--------------------------------------------------------------------------------

||| Decide whether two capabilities may simultaneously alias the same object.
||| Returns a genuine `Dec (Compatible a b)`: every `Yes` carries a real
||| witness, every `No` carries a real refutation.
public export
decCompatible : (a : RefCapability) -> (b : RefCapability) -> Dec (Compatible a b)
-- iso: incompatible with everything (uniqueness)
decCompatible Iso b = No (isoIncompatibleLeft b)
decCompatible a Iso = No (isoIncompatibleRight a)
-- ref
decCompatible Ref Box = Yes RefBoxAlias
decCompatible Ref Ref = No (writableNotCompatible RefWrite RefWrite)
decCompatible Ref Trn = No (writableNotCompatible RefWrite TrnWrite)
decCompatible Ref Val = No (\case _ impossible)
decCompatible Ref Tag = No (\case _ impossible)
-- trn
decCompatible Trn Box = Yes TrnBoxAlias
decCompatible Trn Ref = No (writableNotCompatible TrnWrite RefWrite)
decCompatible Trn Trn = No (writableNotCompatible TrnWrite TrnWrite)
decCompatible Trn Val = No (\case _ impossible)
decCompatible Trn Tag = No (\case _ impossible)
-- val
decCompatible Val Val = Yes ValValAlias
decCompatible Val Box = Yes ValBoxAlias
decCompatible Val Tag = Yes ValTagAlias
decCompatible Val Ref = No (\case _ impossible)
decCompatible Val Trn = No (\case _ impossible)
-- box
decCompatible Box Ref = Yes BoxRefAlias
decCompatible Box Trn = Yes BoxTrnAlias
decCompatible Box Val = Yes BoxValAlias
decCompatible Box Box = Yes BoxBoxAlias
decCompatible Box Tag = Yes BoxTagAlias
-- tag
decCompatible Tag Val = Yes TagValAlias
decCompatible Tag Box = Yes TagBoxAlias
decCompatible Tag Tag = Yes TagTagAlias
decCompatible Tag Ref = No (\case _ impossible)
decCompatible Tag Trn = No (\case _ impossible)

--------------------------------------------------------------------------------
-- Certifier + soundness bridge to the ABI Result type
--------------------------------------------------------------------------------

||| Certify an alias pairing, mapping the decision onto the ABI `Result` type.
||| `Ok` iff the pairing is data-race-safe, `SendabilityViolation` otherwise.
public export
certifyAlias : (a : RefCapability) -> (b : RefCapability) -> Result
certifyAlias a b = case decCompatible a b of
  Yes _ => Ok
  No  _ => SendabilityViolation

||| Soundness of the certifier: if it returns `Ok`, a real compatibility
||| witness exists. (Completeness is the converse, via `decCompatible`.)
public export
certifyAliasSound : (a : RefCapability) -> (b : RefCapability)
                 -> certifyAlias a b = Ok -> Compatible a b
certifyAliasSound a b prf with (decCompatible a b)
  certifyAliasSound a b prf      | Yes w = w
  certifyAliasSound a b Refl     | No _  impossible

--------------------------------------------------------------------------------
-- Positive control: an inhabited compatibility witness
--------------------------------------------------------------------------------

||| POSITIVE CONTROL. A `ref` (local mutable) view may coexist with a `box`
||| (read-only) alias of the same object — this is the canonical safe pairing.
public export
safeRefBoxAlias : Compatible Ref Box
safeRefBoxAlias = RefBoxAlias

||| POSITIVE CONTROL. Two immutable `val` views coexist freely.
public export
safeValValAlias : Compatible Val Val
safeValValAlias = ValValAlias

--------------------------------------------------------------------------------
-- Negative controls: machine-checked refutations of unsafe pairings
--------------------------------------------------------------------------------

||| NEGATIVE CONTROL. Two writable `ref` aliases to the same object are NOT
||| compatible — this is exactly the data race Pony rules out.
public export
unsafeRefRefNotCompatible : Not (Compatible Ref Ref)
unsafeRefRefNotCompatible = writableNotCompatible RefWrite RefWrite

||| NEGATIVE CONTROL. A writable `ref` and a write-unique `trn` cannot both
||| alias the same object.
public export
unsafeRefTrnNotCompatible : Not (Compatible Ref Trn)
unsafeRefTrnNotCompatible = writableNotCompatible RefWrite TrnWrite

||| NEGATIVE CONTROL. An `iso` (unique) reference cannot be aliased at all,
||| not even by another `iso`.
public export
unsafeIsoIsoNotCompatible : Not (Compatible Iso Iso)
unsafeIsoIsoNotCompatible = isoIncompatibleLeft Iso
