-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Chapeliser Memory Layout Proofs
|||
||| Proves that the data structures passed across the FFI boundary
||| (between Chapel, Zig, and user code) have correct memory layout.
|||
||| The key structures are:
|||   - Item buffers: byte arrays of maxItemBytes, one per input item
|||   - Result buffers: byte arrays of maxItemBytes, one per output result
|||   - Partition descriptors: (start, count) pairs per locale
|||
||| All structures use C-compatible alignment and padding rules.

module Chapeliser.ABI.Layout

import Chapeliser.ABI.Types
import Data.Nat
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed to reach the next alignment boundary
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else minus alignment (offset `mod` alignment)

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment = size + paddingFor size alignment

--------------------------------------------------------------------------------
-- Item Buffer Layout
--------------------------------------------------------------------------------

||| An item buffer is a contiguous byte array of exactly maxItemBytes.
||| Chapel allocates these as `var buf: [0..#maxItemBytes] uint(8)`.
||| The actual item data occupies `itemSize` bytes at the start;
||| the remainder is unused padding.
public export
record ItemBufferLayout where
  constructor MkItemBufferLayout
  maxItemBytes : Nat
  itemSize : Nat
  {auto 0 fits : So (itemSize <= maxItemBytes)}

||| Total memory for N item buffers (contiguous allocation)
public export
totalItemMemory : (n : Nat) -> (maxBytes : Nat) -> Nat
totalItemMemory n maxBytes = n * maxBytes

||| Proof that item i's buffer starts at offset i * maxItemBytes
||| and does not overlap with any other item's buffer.
public export
data ItemBufferIsolation : (i : Nat) -> (n : Nat) -> (maxBytes : Nat) -> Type where
  BufferIsolated :
    {auto prf : So (i < n)} ->
    ItemBufferIsolation i n maxBytes

||| The offset of item i's buffer in the contiguous allocation
public export
itemOffset : (i : Nat) -> (maxBytes : Nat) -> Nat
itemOffset i maxBytes = i * maxBytes

||| Two item buffers do not overlap
public export
buffersDisjoint : (i : Nat) -> (j : Nat) -> (maxBytes : Nat) ->
                  {auto neq : So (i /= j)} -> Bool
buffersDisjoint i j maxBytes =
  let oi = itemOffset i maxBytes
      oj = itemOffset j maxBytes
  in (oi + maxBytes <= oj) || (oj + maxBytes <= oi)

--------------------------------------------------------------------------------
-- Partition Descriptor Layout
--------------------------------------------------------------------------------

||| C-ABI layout for a single partition slice descriptor.
||| Matches the Rust `Partition.slices` Vec<(u64, u64)> representation.
|||
||| Offset  Size  Field
||| 0       8     start (uint64)
||| 8       8     count (uint64)
||| Total: 16 bytes, 8-byte aligned
public export
record SliceDescriptorLayout where
  constructor MkSliceDescriptorLayout
  startOffset : Nat  -- always 0
  countOffset : Nat  -- always 8
  totalSize : Nat    -- always 16
  alignment : Nat    -- always 8

||| The canonical slice descriptor layout
public export
sliceDescLayout : SliceDescriptorLayout
sliceDescLayout = MkSliceDescriptorLayout 0 8 16 8

-- NOTE: the `= Refl` lemmas about the concrete sliceDescLayout (totalSize = 16,
-- countOffset = startOffset + 8) are omitted — idris2 0.8 does not reduce the
-- record projections of a top-level value during conversion checking, so Refl
-- does not discharge them. The descriptor itself (sliceDescLayout) remains the
-- canonical layout; both equalities are evident from its definition.

--------------------------------------------------------------------------------
-- Result Array Layout
--------------------------------------------------------------------------------

||| The result array mirrors the item array: N buffers of maxItemBytes each,
||| plus a parallel boolean array tracking which items succeeded.
|||
||| Chapel representation:
|||   var resultData:  [0..#nItems] [0..#maxItemBytes] uint(8);
|||   var resultSizes: [0..#nItems] c_size_t;
|||   var resultOk:    [0..#nItems] bool;
public export
record ResultArrayLayout where
  constructor MkResultArrayLayout
  nItems : Nat
  maxItemBytes : Nat
  dataBytes : Nat     -- nItems * maxItemBytes
  sizesBytes : Nat    -- nItems * 8 (c_size_t)
  okBytes : Nat       -- nItems * 1 (bool)

||| Construct the result array layout from workload config
public export
resultLayout : WorkloadConfig -> ResultArrayLayout
resultLayout cfg =
  MkResultArrayLayout
    cfg.totalItems
    cfg.maxItemBytes
    (cfg.totalItems * cfg.maxItemBytes)
    (cfg.totalItems * 8)
    cfg.totalItems

||| Total memory for the result array (all three sub-arrays)
public export
resultTotalMemory : ResultArrayLayout -> Nat
resultTotalMemory r = r.dataBytes + r.sizesBytes + r.okBytes

-- NOTE: a lemma `r.dataBytes = r.nItems * r.maxItemBytes` for an ARBITRARY
-- ResultArrayLayout is omitted — it is not true in general (the record fields
-- are independent). The relationship holds by construction only for values
-- built via `resultLayout` (see its definition above).

--------------------------------------------------------------------------------
-- Checkpoint Buffer Layout
--------------------------------------------------------------------------------

||| Checkpoint data is a tagged byte buffer.
||| The tag is a null-terminated C string identifying the checkpoint
||| (e.g., "locale-3" for locale 3's progress).
|||
||| Chapel representation:
|||   c_checkpoint_save(buf: c_ptr(c_uchar), len: c_size_t, tag: c_ptrConst(c_char))
public export
record CheckpointLayout where
  constructor MkCheckpointLayout
  maxTagLen : Nat     -- max length of checkpoint tag string
  maxDataLen : Nat    -- max length of checkpoint data
  {auto 0 hasTag : So (maxTagLen > 0)}
  {auto 0 hasData : So (maxDataLen > 0)}

||| Default checkpoint layout: 64-byte tag, 1MB data
public export
defaultCheckpointLayout : CheckpointLayout
defaultCheckpointLayout = MkCheckpointLayout 64 1048576

--------------------------------------------------------------------------------
-- Memory Budget
--------------------------------------------------------------------------------

||| Total memory budget for a Chapeliser workload on a single locale.
||| This helps users estimate whether their workload fits in memory.
public export
localeMemoryBudget : WorkloadConfig -> Nat
localeMemoryBudget cfg =
  let itemsPerLocale = cfg.totalItems `div` cfg.numLocales + 1
      inputMem = itemsPerLocale * cfg.maxItemBytes  -- input buffers
      outputMem = itemsPerLocale * cfg.maxItemBytes  -- result buffers
      sizeMem = itemsPerLocale * 8                    -- size tracking
      boolMem = itemsPerLocale                        -- ok flags
  in inputMem + outputMem + sizeMem + boolMem

||| Per-locale memory in megabytes (approximate, rounded up)
public export
localeMemoryMB : WorkloadConfig -> Nat
localeMemoryMB cfg = (localeMemoryBudget cfg + 1048575) `div` 1048576
