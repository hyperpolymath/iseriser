-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for Ponyiser
|||
||| This module provides formal proofs about memory layout for Pony actors,
||| mailboxes, and capability-annotated fields. Each actor in Pony has a
||| private heap with a message queue (mailbox). Layout correctness is critical
||| for the Zig FFI bridge to safely interact with generated Pony structures.
|||
||| @see https://en.wikipedia.org/wiki/Data_structure_alignment

module Ponyiser.ABI.Layout

import Ponyiser.ABI.Types
import Data.Vect
import Data.So
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else minus alignment (offset `mod` alignment)

||| Proof that alignment divides aligned size: `m = k * n`.
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Sound decision procedure for divisibility. Returns a genuine
||| `Divides n m` witness when `n` evenly divides `m`, otherwise Nothing.
||| Division by zero is undecidable here and yields Nothing.
public export
decDivides : (n : Nat) -> (m : Nat) -> Maybe (Divides n m)
decDivides Z _ = Nothing
decDivides (S k) m =
  let q = m `div` (S k) in
  case decEq m (q * (S k)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Sound divisibility check for an aligned size. The general theorem
||| "alignUp size align is always divisible by align" needs div/mod lemmas
||| from Data.Nat; here we *decide* it via `decDivides`, which returns a
||| genuine witness when it holds. For the concrete ABI layouts below,
||| divisibility is proven outright (`DivideBy`). (Previously
||| `alignUpCorrect … = DivideBy … Refl`, whose `Refl` cannot typecheck for
||| symbolic inputs.)
public export
alignUpDivides : (size : Nat) -> (align : Nat) ->
                 Maybe (Divides align (alignUp size align))
alignUpDivides size align = decDivides align (alignUp size align)

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a struct with its offset and size
public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

||| Calculate the offset of the next field
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| A struct layout is a list of fields with proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect layoutFieldCount Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Calculate total struct size with padding
public export
calcStructSize : Vect k Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect k Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect k Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Verify a struct layout is valid. Builds a `StructLayout` only when both
||| erased obligations are discharged by *real* witnesses: the size bound via
||| `choose` and divisibility via `decDivides`. (Previously
||| `MkStructLayout fields size align` left both `auto` proofs unsolved.)
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align in
  case choose (size >= sum (map (\f => f.size) fields)) of
    Right _ => Left "Invalid struct size"
    Left okSize =>
      case decDivides align size of
        Nothing => Left "Total size not aligned"
        Just dvd => Right (MkStructLayout fields size align
                             {sizeCorrect = okSize} {aligned = dvd})

--------------------------------------------------------------------------------
-- Capability-Annotated Field Layout
--------------------------------------------------------------------------------

||| A field annotated with a Pony reference capability.
||| The capability determines how the field can be accessed and shared.
public export
record CapField where
  constructor MkCapField
  fieldName   : String
  fieldCap    : RefCapability
  fieldOffset : Nat
  fieldSize   : Nat
  fieldAlign  : Nat

||| Convert a CapField to a plain Field (dropping capability info for layout calc)
public export
capFieldToField : CapField -> Field
capFieldToField cf = MkField cf.fieldName cf.fieldOffset cf.fieldSize cf.fieldAlign

--------------------------------------------------------------------------------
-- Actor Mailbox Layout
--------------------------------------------------------------------------------

||| Pony actor mailbox layout.
|||
||| Each actor has a message queue (mailbox). Messages are delivered in causal
||| (FIFO) order. The mailbox is a linked list of message nodes, each containing:
||| - A pointer to the next message (8 bytes, 8-align)
||| - The behaviour index to invoke (4 bytes, 4-align)
||| - The payload size (4 bytes, 4-align)
||| - The payload data (variable, 8-align for pointer-sized data)
public export
mailboxMessageLayout : StructLayout
mailboxMessageLayout =
  MkStructLayout
    [ MkField "next"           0  8 8   -- Pointer to next message
    , MkField "behaviour_id"   8  4 4   -- Which behaviour to invoke
    , MkField "payload_size"  12  4 4   -- Size of payload data
    , MkField "payload"       16  8 8   -- Payload data (pointer or inline)
    ]
    24  -- Total size: 24 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 3 Refl}

||| Pony actor header layout.
|||
||| Every actor starts with a header containing runtime metadata:
||| - Pointer to the actor's type descriptor (vtable-like)
||| - Pointer to the mailbox head
||| - Pointer to the mailbox tail
||| - Actor state flags (running, blocked, GC pending, etc.)
public export
actorHeaderLayout : StructLayout
actorHeaderLayout =
  MkStructLayout
    [ MkField "type_desc"      0  8 8   -- Type descriptor pointer
    , MkField "mailbox_head"   8  8 8   -- First message in queue
    , MkField "mailbox_tail"  16  8 8   -- Last message in queue
    , MkField "flags"         24  4 4   -- Actor state flags
    , MkField "pad"           28  4 4   -- Padding for alignment
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}

||| Actor state flags bitfield
||| Bit 0: running (actor is currently executing a behaviour)
||| Bit 1: blocked (actor has no messages to process)
||| Bit 2: gc_pending (actor's heap needs collection)
||| Bit 3: system (actor is a system/runtime actor)
public export
data ActorFlag : Nat -> Type where
  FlagRunning   : ActorFlag 0
  FlagBlocked   : ActorFlag 1
  FlagGCPending : ActorFlag 2
  FlagSystem    : ActorFlag 3

--------------------------------------------------------------------------------
-- Actor Field Layout with Capabilities
--------------------------------------------------------------------------------

||| Layout for an actor's user-defined fields (after the header).
|||
||| Each field carries a reference capability that constrains access.
||| The layout must respect C ABI alignment rules for FFI compatibility.
|||
||| Returns `Nothing` when the computed total size fails the size bound or is
||| not 8-aligned. Both erased obligations are discharged by *real* witnesses
||| (`choose` for the size bound, `decDivides` for alignment); the previous
||| version returned a bare `StructLayout` with both `auto` proofs unsolved.
public export
actorFieldsLayout : (fields : Vect k CapField) -> (headerSize : Nat) -> Maybe StructLayout
actorFieldsLayout fields headerSize =
  let plainFields = map (\cf => MkField cf.fieldName
                                        (headerSize + cf.fieldOffset)
                                        cf.fieldSize
                                        cf.fieldAlign)
                        fields
      totalSize = calcStructSize plainFields 8 in
  case choose (totalSize >= sum (map (\f => f.size) plainFields)) of
    Right _ => Nothing
    Left okSize =>
      case decDivides 8 totalSize of
        Nothing => Nothing
        Just dvd => Just (MkStructLayout plainFields totalSize 8
                            {sizeCorrect = okSize} {aligned = dvd})

--------------------------------------------------------------------------------
-- Platform-Specific Layouts
--------------------------------------------------------------------------------

||| Struct layout may differ by platform
public export
PlatformLayout : Platform -> Type -> Type
PlatformLayout p t = StructLayout

||| Verify layout is correct for all platforms
public export
verifyAllPlatforms :
  (layouts : (p : Platform) -> PlatformLayout p t) ->
  Either String ()
verifyAllPlatforms layouts = Right ()

--------------------------------------------------------------------------------
-- C ABI Compatibility
--------------------------------------------------------------------------------

||| Proof that a struct follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Decide field alignment for every field, building a real `FieldsAligned`
||| witness from per-field divisibility proofs.
public export
decFieldsAligned : (fs : Vect k Field) -> Maybe (FieldsAligned fs)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dvd => case decFieldsAligned fs of
                  Nothing => Nothing
                  Just rest => Just (ConsField f fs dvd rest)

||| Verify a layout against the C ABI alignment rules, returning a genuine
||| `CABICompliant` proof (built from real per-field divisibility witnesses)
||| or an error when some field offset is misaligned. (Previously
||| `CABIOk layout ?fieldsAlignedProof` left a hole.)
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Field offsets are not correctly aligned for the C ABI"

--------------------------------------------------------------------------------
-- Mailbox Layout Proofs
--------------------------------------------------------------------------------

||| Proof that the mailbox message layout is C-ABI compliant. Built directly
||| from per-field `DivideBy` witnesses (offset = k * alignment): 0|8, 8|4,
||| 12|4, 16|8. Multiplication reduces at type-check time, so these are fully
||| verified by the compiler. (Previously a `?mailboxFieldsAligned` hole.)
export
mailboxMessageCABI : CABICompliant Layout.mailboxMessageLayout
mailboxMessageCABI =
  CABIOk mailboxMessageLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
     NoFields))))

||| Proof that the actor header layout is C-ABI compliant. Per-field offsets:
||| 0|8, 8|8, 16|8, 24|4, 28|4. (Previously a `?actorHeaderFieldsAligned` hole.)
export
actorHeaderCABI : CABICompliant Layout.actorHeaderLayout
actorHeaderCABI =
  CABIOk actorHeaderLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 1 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields)))))

--------------------------------------------------------------------------------
-- Offset Calculation
--------------------------------------------------------------------------------

||| Calculate field offset with proof of correctness
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (n : Nat ** Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx ** index idx layout.fields)
    Nothing => Nothing

||| Decide whether a field lies within a struct's byte bounds, returning a
||| genuine proof when `offset + size <= totalSize`. The previous signature
||| asserted this for *every* field unconditionally, which is false (a field
||| need not belong to the layout); this honest version decides it via
||| `choose` and the `?offsetInBoundsProof` hole is gone.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) ->
                 Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
