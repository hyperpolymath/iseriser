-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the Chapeliser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If a concrete partition were
||| incomplete, a gather lost results, a slice descriptor were mis-laid-out, or
||| the result-code encoding the Zig FFI depends on were wrong, this module
||| would fail to typecheck and the proof build would go red.
|||
||| Design note on what reduces at the type level: Idris2's `Nat` `div`/`mod`
||| and the `where`-block helpers inside `perItemSlices` do NOT reduce during
||| conversion checking, so we never route a proof through them. Instead the
||| concrete partition/gather witnesses are built from EXPLICIT slice vectors,
||| where `sliceSum`, `allDisjoint`, and `gatherTotal` reduce fully. Record
||| projections of top-level layout values reduce, so the layout pins are `Refl`.

module Chapeliser.ABI.Proofs

import Chapeliser.ABI.Types
import Chapeliser.ABI.Layout
import Data.So
import Data.Vect
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

||| Ok must encode as the C value 0 — the success sentinel every FFI wrapper
||| (`init`, `shutdown`, ...) tests against.
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| NullPointer must encode as the C value 4.
export
nullPointerIsFour : resultToInt NullPointer = 4
nullPointerIsFour = Refl

||| RetryExhausted must encode as the C value 5.
export
retryExhaustedIsFive : resultToInt RetryExhausted = 5
retryExhaustedIsFive = Refl

||| CheckpointError must encode as the C value 6 (the highest code).
export
checkpointErrorIsSix : resultToInt CheckpointError = 6
checkpointErrorIsSix = Refl

--------------------------------------------------------------------------------
-- Slice-descriptor layout: the (start, count) pair crossing the FFI boundary.
--------------------------------------------------------------------------------

||| The canonical slice descriptor is exactly 16 bytes.
export
sliceDescTotalSize : Layout.sliceDescLayout.totalSize = 16
sliceDescTotalSize = Refl

||| `start` lives at offset 0.
export
sliceDescStartOffset : Layout.sliceDescLayout.startOffset = 0
sliceDescStartOffset = Refl

||| `count` lives at offset 8.
export
sliceDescCountOffset : Layout.sliceDescLayout.countOffset = 8
sliceDescCountOffset = Refl

||| The descriptor is 8-byte aligned.
export
sliceDescAlignment : Layout.sliceDescLayout.alignment = 8
sliceDescAlignment = Refl

||| The `count` field begins exactly 8 bytes after `start` — i.e. the two
||| uint64s are adjacent with no padding between them, matching the Rust
||| `(u64, u64)` representation.
export
sliceDescCountFollowsStart :
  Layout.sliceDescLayout.countOffset = Layout.sliceDescLayout.startOffset + 8
sliceDescCountFollowsStart = Refl

--------------------------------------------------------------------------------
-- Default checkpoint layout pins.
--------------------------------------------------------------------------------

||| The default checkpoint tag buffer is 64 bytes.
export
checkpointDefaultTagLen : Layout.defaultCheckpointLayout.maxTagLen = 64
checkpointDefaultTagLen = Refl

||| The default checkpoint data buffer is exactly 1 MiB.
export
checkpointDefaultDataLen : Layout.defaultCheckpointLayout.maxDataLen = 1048576
checkpointDefaultDataLen = Refl

--------------------------------------------------------------------------------
-- Partition completeness + disjointness on a concrete, explicit partition.
--------------------------------------------------------------------------------

||| A concrete partition of 10 items across 2 locales, given by an explicit
||| slice vector (not via `perItemSlices`, whose `div`/`mod` do not reduce at
||| the type level). Locale 0 gets items [0,4), locale 1 gets items [4,10).
export
tenAcrossTwo : Partition 10 2
tenAcrossTwo = MkPartition [MkSlice 0 4, MkSlice 4 6]

||| The slices cover all 10 items with none lost or duplicated:
||| 4 + 6 = 10. This is partition completeness (invariant #1).
export
tenAcrossTwoComplete : PartitionComplete Proofs.tenAcrossTwo
tenAcrossTwoComplete = IsComplete Refl

||| The two slices do not overlap: [0,4) and [4,10) are disjoint.
export
tenAcrossTwoDisjoint : PartitionDisjoint Proofs.tenAcrossTwo
tenAcrossTwoDisjoint = IsDisjoint Oh

||| Therefore the partition is valid: complete AND disjoint. This is the full
||| correctness witness the Chapel codegen relies on to place items.
export
tenAcrossTwoValid : ValidPartition Proofs.tenAcrossTwo
tenAcrossTwoValid = MkValid tenAcrossTwoComplete tenAcrossTwoDisjoint

||| A three-locale example to show completeness is not a one-off:
||| [0,3) + [3,6) + [6,10) = 3 + 3 + 4 = 10.
export
tenAcrossThree : Partition 10 3
tenAcrossThree = MkPartition [MkSlice 0 3, MkSlice 3 3, MkSlice 6 4]

export
tenAcrossThreeValid : ValidPartition Proofs.tenAcrossThree
tenAcrossThreeValid =
  MkValid (IsComplete Refl) (IsDisjoint Oh)

--------------------------------------------------------------------------------
-- Gather conservation (invariant #2): no results lost when collecting.
--------------------------------------------------------------------------------

||| Gathering per-locale result counts [3, 3, 4] yields exactly 10 outputs —
||| the sum is conserved, matching the 10-item partition above.
export
gatherTenConserved : GatherConservation (MkGatherInput [3, 3, 4]) 10
gatherTenConserved = Conserved Refl

||| An empty gather conserves to zero (degenerate base case).
export
gatherEmptyConserved : GatherConservation (MkGatherInput []) 0
gatherEmptyConserved = Conserved Refl

--------------------------------------------------------------------------------
-- Serialisation length-conservation (invariant #3): decoded length = original.
--------------------------------------------------------------------------------

||| A 128-byte Bincode payload decodes back to exactly 128 bytes. The proof
||| obligation `decodedLen = origLen` is real: `RoundTrip Bincode 128 64` has
||| no inhabitant.
export
bincodeRoundTrips : RoundTrip Bincode 128 128
bincodeRoundTrips = RoundTripOk Bincode Refl

||| The raw (identity) format conserves a 64-byte payload's length.
export
rawRoundTrips : RoundTrip Raw 64 64
rawRoundTrips = RoundTripOk Raw Refl

--------------------------------------------------------------------------------
-- Retry isolation (invariant #4) + item-buffer isolation.
--------------------------------------------------------------------------------

||| Retrying item 3 of a 10-item workload is isolated: 3 < 10, so the retry
||| writes only to result slot 3 and cannot corrupt other items' results.
export
retryItemThreeIsolated : RetryIsolation 3 10
retryItemThreeIsolated = Isolated Oh

||| Item 2's buffer (with 16-byte buffers) starts at byte offset 32 in the
||| contiguous allocation: 2 * 16 = 32.
export
itemTwoOffset : itemOffset 2 16 = 32
itemTwoOffset = Refl

||| Items 0 and 1 occupy non-overlapping 16-byte buffers.
export
buffersZeroOneDisjoint : So (buffersDisjoint 0 1 16 {neq = Oh})
buffersZeroOneDisjoint = Oh

||| Total contiguous memory for 4 buffers of 16 bytes each is 64 bytes.
export
fourBuffersMemory : totalItemMemory 4 16 = 64
fourBuffersMemory = Refl
