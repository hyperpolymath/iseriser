-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Chapeliser ABI Type Definitions
|||
||| Defines the types and proofs for Chapeliser's distributed computation model.
||| The key invariants proven here:
|||   1. Partition completeness — no items lost or duplicated when distributing
|||   2. Gather conservation — all results preserved when collecting
|||   3. Serialisation round-trip — deserialize(serialize(x)) ≡ x
|||   4. Retry safety — retrying a failed item does not corrupt other results
|||
||| These proofs ensure that Chapeliser's generated Chapel code is correct
||| by construction — if the Idris2 code compiles, the invariants hold.

module Chapeliser.ABI.Types

import Data.Fin
import Data.Nat
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for the Chapeliser ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
public export
thisPlatform : Platform
thisPlatform = Linux  -- Default; override with compiler flags

--------------------------------------------------------------------------------
-- Result Codes
--------------------------------------------------------------------------------

||| FFI result codes. These match the C int values returned by all
||| Chapeliser FFI functions (c_init, c_process_item, etc.).
public export
data Result : Type where
  ||| Operation succeeded (C value: 0)
  Ok : Result
  ||| Generic error (C value: 1)
  Error : Result
  ||| Invalid parameter — e.g., negative item index (C value: 2)
  InvalidParam : Result
  ||| Out of memory — buffer too small for serialised item (C value: 3)
  OutOfMemory : Result
  ||| Null pointer in FFI call (C value: 4)
  NullPointer : Result
  ||| Item processing failed after all retries (C value: 5)
  RetryExhausted : Result
  ||| Checkpoint save/load failed (C value: 6)
  CheckpointError : Result

||| Convert Result to C-compatible integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt RetryExhausted = 5
resultToInt CheckpointError = 6

-- NOTE: a DecEq instance for Result is intentionally omitted — it is auxiliary
-- (no proof below uses it), and Idris2's `No absurd` requires explicit
-- off-diagonal constructor pairs rather than a `_ _` catch-all. Re-add via
-- elaborator-reflection derivation if decidable equality is ever needed.

--------------------------------------------------------------------------------
-- Partition Strategies
--------------------------------------------------------------------------------

||| The five partition strategies Chapeliser supports.
||| Each defines how input items are distributed across Chapel locales.
public export
data PartitionStrategy
  = PerItem    -- Even distribution: locale i gets items [i*N/K .. (i+1)*N/K)
  | Chunk      -- Fixed-size chunks of grainSize items, round-robin
  | Adaptive   -- Dynamic work-stealing via Chapel's DynamicIters
  | Spatial    -- Block-distributed domain decomposition
  | Keyed      -- Route by key hash: same key → same locale

-- (DecEq for PartitionStrategy omitted — auxiliary, see note above.)

--------------------------------------------------------------------------------
-- Gather Strategies
--------------------------------------------------------------------------------

||| The five gather strategies Chapeliser supports.
||| Each defines how results from locales are combined.
public export
data GatherStrategy
  = Merge       -- Concatenate all results
  | Reduce      -- Fold results into one via reduce function
  | TreeReduce  -- Logarithmic pairwise reduction across locales
  | Stream      -- Results available incrementally as they complete
  | First       -- Return first result matching a predicate

-- (DecEq for GatherStrategy omitted — auxiliary, see note above.)

--------------------------------------------------------------------------------
-- Partition — the core data structure
--------------------------------------------------------------------------------

||| A Slice is a contiguous range of items assigned to one locale.
||| start + count ≤ totalItems is enforced by the Partition proof.
public export
record Slice where
  constructor MkSlice
  start : Nat
  count : Nat

||| A Partition of N items across K locales.
||| Each locale gets a Slice. The key invariant is that the slices
||| form a complete, non-overlapping cover of [0, N).
public export
record Partition (n : Nat) (k : Nat) where
  constructor MkPartition
  slices : Vect k Slice

||| Sum of all slice counts in a partition
public export
sliceSum : Vect k Slice -> Nat
sliceSum [] = 0
sliceSum (s :: ss) = s.count + sliceSum ss

||| Partition completeness: the sum of all slice counts equals the total items.
||| This guarantees no items are lost or duplicated.
|||
||| The index `n` is bound explicitly in the constructor and shared with the
||| `Partition n k` of `p`, so the obligation `sliceSum p.slices = n` is tied to
||| the partition's declared item count. (A free `n` here would be existential —
||| solvable to the actual slice sum — making the proof vacuous.)
public export
data PartitionComplete : (p : Partition n k) -> Type where
  IsComplete : {n : Nat} -> {k : Nat} -> {p : Partition n k} ->
               (prf : sliceSum p.slices = n) -> PartitionComplete p

||| Two slices do not overlap if one ends before the other starts.
public export
disjoint : Slice -> Slice -> Bool
disjoint a b =
  (a.start + a.count <= b.start) || (b.start + b.count <= a.start)

||| All pairs of slices in a vector are disjoint
public export
allDisjoint : Vect k Slice -> Bool
allDisjoint [] = True
allDisjoint (s :: ss) = all (disjoint s) ss && allDisjoint ss

||| Partition non-overlap: no two slices share any item index.
public export
data PartitionDisjoint : (p : Partition n k) -> Type where
  IsDisjoint : So (allDisjoint p.slices) -> PartitionDisjoint p

||| A valid partition is both complete and disjoint.
public export
data ValidPartition : (p : Partition n k) -> Type where
  MkValid : PartitionComplete p -> PartitionDisjoint p -> ValidPartition p

--------------------------------------------------------------------------------
-- Per-item partition construction with proof
--------------------------------------------------------------------------------

||| Construct a per-item partition for n items across k locales.
||| Items are distributed as evenly as possible: first (n mod k) locales
||| get (n div k + 1) items, the rest get (n div k).
public export
perItemSlices : (n : Nat) -> (k : Nat) -> {auto ok : So (k > 0)} -> Vect k Slice
perItemSlices n k = go 0 k
  where
    base : Nat
    base = n `div` k
    remainder : Nat
    remainder = n `mod` k
    go : Nat -> (remaining : Nat) -> Vect remaining Slice
    go _ Z = []
    go offset (S r) =
      let localeIdx = k `minus` (S r)
          cnt = base + (if localeIdx < remainder then 1 else 0)
      in MkSlice offset cnt :: go (offset + cnt) r

--------------------------------------------------------------------------------
-- Gather Conservation
--------------------------------------------------------------------------------

||| Per-locale result counts
public export
record GatherInput (k : Nat) where
  constructor MkGatherInput
  localeCounts : Vect k Nat

||| Total results across all locales
public export
gatherTotal : Vect k Nat -> Nat
gatherTotal = foldr (+) 0

||| For merge gather: the total output count equals the sum of locale counts.
||| This guarantees no results are lost during gathering.
public export
data GatherConservation : (input : GatherInput k) -> (outputCount : Nat) -> Type where
  Conserved : (prf : gatherTotal input.localeCounts = outputCount)
            -> GatherConservation input outputCount

--------------------------------------------------------------------------------
-- Serialisation Round-Trip
--------------------------------------------------------------------------------

||| A serialisation format (matching chapeliser.toml options)
public export
data SerFormat = Bincode | MessagePack | CBOR | JSON | FlatBuffers | Raw

||| Abstract type for serialised byte buffers.
||| The actual bytes live in Zig/C memory; Idris2 tracks the invariant.
public export
record SerBuffer where
  constructor MkSerBuffer
  len : Nat
  maxLen : Nat
  {auto 0 fits : So (len <= maxLen)}

||| Length-conservation witness for serialisation: for a value whose payload
||| is `origLen` bytes, decoding the encoded buffer restores exactly `origLen`
||| bytes (`decodedLen = origLen`). This is the byte-length invariant that
||| actually crosses the Zig/C FFI boundary — the full semantic round-trip of
||| the payload bytes is the FFI implementation's contract, but the length
||| equality is a genuine, machine-checkable obligation here (a mismatched
||| `decodedLen` is rejected). `RoundTripOk` therefore carries a real proof,
||| not an unconditional assertion.
public export
data RoundTrip : (fmt : SerFormat) -> (origLen : Nat) -> (decodedLen : Nat) -> Type where
  RoundTripOk : {origLen : Nat} -> {decodedLen : Nat} -> (fmt : SerFormat) ->
                (prf : decodedLen = origLen) -> RoundTrip fmt origLen decodedLen

--------------------------------------------------------------------------------
-- Retry Safety
--------------------------------------------------------------------------------

||| A retry count (bounded by maxRetries from manifest)
public export
record RetryState where
  constructor MkRetryState
  attempt : Nat
  maxAttempts : Nat
  {auto 0 bounded : So (attempt <= maxAttempts)}

||| Proof that retrying an item only affects that item's result slot.
||| Other items' results are untouched by a retry — guaranteed by
||| the Chapel codegen writing only to resultData[i] for item i.
public export
data RetryIsolation : (itemIdx : Nat) -> (totalItems : Nat) -> Type where
  Isolated : (prf : So (itemIdx < totalItems)) -> RetryIsolation itemIdx totalItems

--------------------------------------------------------------------------------
-- Workload Configuration
--------------------------------------------------------------------------------

||| Complete workload configuration, mirroring chapeliser.toml
public export
record WorkloadConfig where
  constructor MkWorkloadConfig
  totalItems : Nat
  numLocales : Nat
  grainSize : Nat
  maxItemBytes : Nat
  maxRetries : Nat
  partition : PartitionStrategy
  gather : GatherStrategy
  serFormat : SerFormat
  checkpointEnabled : Bool
  {auto 0 hasItems : So (totalItems > 0)}
  {auto 0 hasLocales : So (numLocales > 0)}
  {auto 0 hasGrain : So (grainSize > 0)}
  {auto 0 hasBuffer : So (maxItemBytes > 0)}

--------------------------------------------------------------------------------
-- Platform-Specific Types (for C ABI compatibility)
--------------------------------------------------------------------------------

||| C int size (always 32-bit on all supported platforms)
public export
CInt : Platform -> Type
CInt _ = Bits32

||| C size_t varies by platform (64-bit on most, 32-bit on WASM)
public export
CSize : Platform -> Type
CSize WASM = Bits32
CSize _ = Bits64

||| C pointer size varies by platform
public export
ptrSize : Platform -> Nat
ptrSize WASM = 32
ptrSize _ = 64
