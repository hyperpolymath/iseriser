-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Chapeliser Foreign Function Interface Declarations
|||
||| Declares all C-compatible functions that the Chapeliser runtime calls.
||| These functions are implemented in the Zig FFI layer, which delegates
||| to the user's workload-specific code.
|||
||| The function signatures here MUST match:
|||   1. The Chapel `extern proc` declarations in the generated .chpl file
|||   2. The Zig `export fn` signatures in the generated _ffi.zig file
|||   3. The C function declarations in the generated .h header
|||
||| Any mismatch is a linking error caught at Chapel compile time.

module Chapeliser.ABI.Foreign

import Chapeliser.ABI.Types
import Chapeliser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialise the workload library. Called once on Chapel locale 0
||| before any items are loaded or processed.
||| Returns 0 on success, non-zero error code on failure.
export
%foreign "C:c_init, libchapeliser_ffi"
prim__init : PrimIO Bits32

||| Safe wrapper for initialisation
export
init : IO (Either Result ())
init = do
  rc <- primIO prim__init
  pure $ if rc == 0 then Right () else Left Error

||| Shut down the workload library. Called once on locale 0
||| after all results have been stored.
export
%foreign "C:c_shutdown, libchapeliser_ffi"
prim__shutdown : PrimIO Bits32

||| Safe wrapper for shutdown
export
shutdown : IO (Either Result ())
shutdown = do
  rc <- primIO prim__shutdown
  pure $ if rc == 0 then Right () else Left Error

--------------------------------------------------------------------------------
-- Data I/O
--------------------------------------------------------------------------------

||| Get the total number of input items. Called on locale 0.
||| Returns item count (>= 0), or negative on error.
export
%foreign "C:c_get_total_items, libchapeliser_ffi"
prim__getTotalItems : PrimIO Bits32

||| Safe wrapper
export
getTotalItems : IO (Either Result Nat)
getTotalItems = do
  n <- primIO prim__getTotalItems
  pure $ Right (cast n)

||| Load (serialise) input item at index `idx` into buffer `buf`.
||| On entry, `*len` is the buffer capacity (maxItemBytes).
||| On exit, `*len` is the actual serialised size.
||| Returns 0 on success.
export
%foreign "C:c_load_item, libchapeliser_ffi"
prim__loadItem : Bits32 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Store (receive) a processed result at index `idx`.
||| `buf` contains `len` bytes of serialised result data.
||| Returns 0 on success.
export
%foreign "C:c_store_result, libchapeliser_ffi"
prim__storeResult : Bits32 -> Bits64 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- Item Processing
--------------------------------------------------------------------------------

||| Process a single serialised item.
||| Reads from (in_buf, in_len), writes result to (out_buf, *out_len).
||| Called on any locale — the user's function must be thread-safe.
||| Returns 0 on success.
export
%foreign "C:c_process_item, libchapeliser_ffi"
prim__processItem : Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Process a chunk of items (for chunk partition strategy).
||| items_buf contains item_count items at the given offsets and sizes.
||| Returns 0 on success.
export
%foreign "C:c_process_chunk, libchapeliser_ffi"
prim__processChunk : Bits64 -> Bits32 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- Reduction
--------------------------------------------------------------------------------

||| Combine two serialised results into one.
||| Used by reduce and tree-reduce gather strategies.
||| Reads (a_buf, a_len) and (b_buf, b_len), writes to (out_buf, *out_len).
||| The reduce function must be associative for tree-reduce correctness.
||| Returns 0 on success.
export
%foreign "C:c_reduce, libchapeliser_ffi"
prim__reduce : Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- Match Predicate (for 'first' gather)
--------------------------------------------------------------------------------

||| Test whether a serialised result matches the search criterion.
||| Returns 1 if the result matches, 0 if not.
||| Used by the 'first' gather strategy to stop early.
export
%foreign "C:c_is_match, libchapeliser_ffi"
prim__isMatch : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper
export
isMatch : (bufPtr : Bits64) -> (len : Bits64) -> IO Bool
isMatch buf len = do
  rc <- primIO (prim__isMatch buf len)
  pure (rc == 1)

--------------------------------------------------------------------------------
-- Key Hash (for keyed partition)
--------------------------------------------------------------------------------

||| Compute a hash of the item's distribution key.
||| Items with the same hash (mod numLocales) land on the same locale.
||| Returns an unsigned 32-bit hash value.
export
%foreign "C:c_key_hash, libchapeliser_ffi"
prim__keyHash : Bits64 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- Checkpoint (optional)
--------------------------------------------------------------------------------

||| Save checkpoint data with a string tag.
||| Returns 0 on success, -1 if checkpointing is not implemented.
export
%foreign "C:c_checkpoint_save, libchapeliser_ffi"
prim__checkpointSave : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Load checkpoint data by tag.
||| On entry, *len is buffer capacity. On exit, *len is data size.
||| Returns 0 on success, -1 if no checkpoint exists or not implemented.
export
%foreign "C:c_checkpoint_load, libchapeliser_ffi"
prim__checkpointLoad : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Chapeliser ABI version (major * 1000 + minor)
||| Used to detect ABI mismatches at runtime.
export
chapeliserABIVersion : Bits32
chapeliserABIVersion = 1000  -- v1.0

--------------------------------------------------------------------------------
-- Verification: Partition + Gather Composition
--------------------------------------------------------------------------------

||| The full Chapeliser pipeline is correct if:
|||   1. The partition is valid (complete + disjoint)
|||   2. Each item is processed exactly once
|||   3. The gather preserves all results
|||
||| This type witnesses that a workload configuration satisfies all three.
public export
data PipelineCorrect : WorkloadConfig -> Type where
  MkPipelineCorrect :
    {cfg : WorkloadConfig} ->
    -- The partition is taken abstractly (any Partition of totalItems across
    -- numLocales — e.g. one built by perItemSlices) so the *type* carries no
    -- construction-time `So (numLocales > 0)` obligation; validity is the
    -- witness that matters.
    {p : Partition cfg.totalItems cfg.numLocales} ->
    (partition : ValidPartition p) ->
    (gather : GatherConservation (MkGatherInput (replicate cfg.numLocales (cfg.totalItems `div` cfg.numLocales))) cfg.totalItems) ->
    PipelineCorrect cfg
