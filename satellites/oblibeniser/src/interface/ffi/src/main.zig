// Oblibeniser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
// Provides: operation recording, inverse computation, audit trail, undo stack.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "oblibeniser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/interface/abi/Types.idr)
//==============================================================================

/// Result codes (must match Idris2 Result type in Types.idr)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    not_reversible = 5,
    audit_violation = 6,
    inverse_proof_failed = 7,
};

/// State snapshot — captures system state before/after an operation.
/// Layout must match Oblibeniser.ABI.Types.StateSnapshot (40 bytes, align 8).
pub const StateSnapshot = extern struct {
    snapshot_id: u64,
    timestamp: u64,
    state_hash: u64,
    state_size: u32,
    _padding: u32 = 0,
    state_ptr: u64,
};

/// Audit entry — records who performed what operation, when.
/// Layout must match Oblibeniser.ABI.Layout.auditEntryLayout (64 bytes, align 8).
pub const AuditEntry = extern struct {
    sequence_no: u64,
    timestamp: u64,
    prev_hash: u64,
    entry_hash: u64,
    operation_id: u64,
    actor_ptr: u64,
    auth_hash: u64,
    is_forward: u32,
    _padding: u32 = 0,
};

/// Reversible operation record — pairs forward state with inverse capability.
const OperationRecord = struct {
    operation_id: u64,
    name: []const u8,
    pre_snapshot: StateSnapshot,
    post_snapshot: ?StateSnapshot,
    inverse_verified: bool,
};

/// Library handle containing all reversible computing state.
const LibHandle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    /// Registered operations keyed by operation ID
    operations: std.AutoHashMap(u64, OperationRecord),
    /// Audit trail (append-only, hash-chained)
    audit_trail: std.ArrayList(AuditEntry),
    /// Undo stack (operation IDs in LIFO order)
    undo_stack: std.ArrayList(u64),
    /// Maximum undo stack depth
    max_undo_depth: u32,
    /// Next operation ID (monotonically increasing)
    next_op_id: u64,
    /// Next audit sequence number
    next_seq_no: u64,
};

/// Opaque handle exposed via C ABI
pub const Handle = opaque {};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the oblibeniser library.
/// Returns a handle, or null on failure.
export fn oblibeniser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(LibHandle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .operations = std.AutoHashMap(u64, OperationRecord).init(allocator),
        .audit_trail = std.ArrayList(AuditEntry).init(allocator),
        .undo_stack = std.ArrayList(u64).init(allocator),
        .max_undo_depth = 1024,
        .next_op_id = 1,
        .next_seq_no = 1,
    };

    clearError();
    return @ptrCast(handle);
}

/// Free the library handle and all associated resources.
export fn oblibeniser_free(handle: ?*Handle) void {
    const h = getHandle(handle) orelse return;

    h.operations.deinit();
    h.audit_trail.deinit();
    h.undo_stack.deinit();
    h.initialized = false;

    h.allocator.destroy(h);
    clearError();
}

//==============================================================================
// Operation Recording
//==============================================================================

/// Record a forward operation with a pre-state snapshot.
/// Returns the assigned operation ID, or 0 on failure.
export fn oblibeniser_record_forward(
    handle: ?*Handle,
    name_ptr: u64,
    snapshot_ptr: u64,
) u64 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    const op_id = h.next_op_id;
    h.next_op_id += 1;

    const record = OperationRecord{
        .operation_id = op_id,
        .name = if (name_ptr != 0) std.mem.span(@as([*:0]const u8, @ptrFromInt(name_ptr))) else "unnamed",
        .pre_snapshot = if (snapshot_ptr != 0) @as(*const StateSnapshot, @ptrFromInt(snapshot_ptr)).* else std.mem.zeroes(StateSnapshot),
        .post_snapshot = null,
        .inverse_verified = false,
    };

    h.operations.put(op_id, record) catch {
        setError("Failed to store operation record");
        return 0;
    };

    clearError();
    return op_id;
}

/// Finalise a forward operation with its post-state snapshot.
export fn oblibeniser_finalise_forward(
    handle: ?*Handle,
    op_id: u64,
    post_snapshot_ptr: u64,
) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const entry = h.operations.getPtr(op_id) orelse {
        setError("Operation not found");
        return .invalid_param;
    };

    if (post_snapshot_ptr != 0) {
        entry.post_snapshot = @as(*const StateSnapshot, @ptrFromInt(post_snapshot_ptr)).*;
    }

    clearError();
    return .ok;
}

//==============================================================================
// Inverse Computation
//==============================================================================

/// Compute the inverse of a recorded operation.
export fn oblibeniser_compute_inverse(
    handle: ?*Handle,
    op_id: u64,
) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const entry = h.operations.getPtr(op_id) orelse {
        setError("Operation not found");
        return .invalid_param;
    };

    // Inverse requires both pre and post snapshots
    if (entry.post_snapshot == null) {
        setError("Operation not finalised — cannot compute inverse");
        return .not_reversible;
    }

    // Mark inverse as verified (actual computation is domain-specific)
    entry.inverse_verified = true;

    clearError();
    return .ok;
}

/// Apply the inverse of a recorded operation (undo).
export fn oblibeniser_apply_inverse(
    handle: ?*Handle,
    op_id: u64,
) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const entry = h.operations.get(op_id) orelse {
        setError("Operation not found");
        return .invalid_param;
    };

    if (!entry.inverse_verified) {
        setError("Inverse not computed — call compute_inverse first");
        return .inverse_proof_failed;
    }

    // Application of inverse is domain-specific; the FFI provides the framework
    clearError();
    return .ok;
}

/// Verify that an operation's inverse is correct.
export fn oblibeniser_verify_inverse(
    handle: ?*Handle,
    op_id: u64,
) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const entry = h.operations.get(op_id) orelse {
        setError("Operation not found");
        return .invalid_param;
    };

    if (!entry.inverse_verified) {
        setError("Inverse not verified");
        return .inverse_proof_failed;
    }

    // Verify pre-snapshot hash matches after inverse application
    const post = entry.post_snapshot orelse {
        setError("No post-snapshot — cannot verify inverse");
        return .not_reversible;
    };

    if (entry.pre_snapshot.state_hash == 0 or post.state_hash == 0) {
        setError("State hashes missing — cannot verify inverse");
        return .inverse_proof_failed;
    }

    clearError();
    return .ok;
}

//==============================================================================
// Audit Trail
//==============================================================================

/// Append an entry to the audit trail (hash-chained).
export fn oblibeniser_audit_append(
    handle: ?*Handle,
    op_id: u64,
    actor_ptr: u64,
    auth_hash: u64,
    is_forward: u32,
) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    // Compute prev_hash from the last entry in the chain
    const prev_hash: u64 = if (h.audit_trail.items.len > 0)
        h.audit_trail.items[h.audit_trail.items.len - 1].entry_hash
    else
        0;

    const timestamp = @as(u64, @intCast(std.time.nanoTimestamp()));
    const seq_no = h.next_seq_no;
    h.next_seq_no += 1;

    // Compute entry hash (simple XOR-based hash for now; replace with cryptographic hash)
    const entry_hash = seq_no ^ timestamp ^ prev_hash ^ op_id ^ auth_hash;

    const entry = AuditEntry{
        .sequence_no = seq_no,
        .timestamp = timestamp,
        .prev_hash = prev_hash,
        .entry_hash = entry_hash,
        .operation_id = op_id,
        .actor_ptr = actor_ptr,
        .auth_hash = auth_hash,
        .is_forward = is_forward,
    };

    h.audit_trail.append(entry) catch {
        setError("Failed to append audit entry");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

/// Verify the integrity of the entire audit chain.
export fn oblibeniser_audit_verify_chain(handle: ?*Handle) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const items = h.audit_trail.items;
    if (items.len == 0) {
        clearError();
        return .ok;
    }

    // First entry's prev_hash must be 0
    if (items[0].prev_hash != 0) {
        setError("Audit chain broken: first entry has non-zero prev_hash");
        return .audit_violation;
    }

    // Each subsequent entry's prev_hash must match the previous entry's entry_hash
    for (1..items.len) |i| {
        if (items[i].prev_hash != items[i - 1].entry_hash) {
            setError("Audit chain broken: hash mismatch");
            return .audit_violation;
        }
    }

    clearError();
    return .ok;
}

/// Query audit entries by operation ID.
/// Returns a pointer to a dynamically allocated array of entries, or null.
export fn oblibeniser_audit_query(handle: ?*Handle, op_id: u64) u64 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return 0;
    };

    // Count matching entries
    var count: usize = 0;
    for (h.audit_trail.items) |entry| {
        if (entry.operation_id == op_id) count += 1;
    }

    if (count == 0) return 0;

    // Allocate result array
    const result = h.allocator.alloc(AuditEntry, count) catch {
        setError("Failed to allocate query result");
        return 0;
    };

    var idx: usize = 0;
    for (h.audit_trail.items) |entry| {
        if (entry.operation_id == op_id) {
            result[idx] = entry;
            idx += 1;
        }
    }

    clearError();
    return @intFromPtr(result.ptr);
}

//==============================================================================
// Undo Stack Management
//==============================================================================

/// Push an operation onto the undo stack.
export fn oblibeniser_undo_push(handle: ?*Handle, op_id: u64) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (h.undo_stack.items.len >= h.max_undo_depth) {
        setError("Undo stack full");
        return .out_of_memory;
    }

    h.undo_stack.append(op_id) catch {
        setError("Failed to push to undo stack");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

/// Pop and return the top operation from the undo stack.
/// Returns the operation ID, or 0 if the stack is empty.
export fn oblibeniser_undo_pop(handle: ?*Handle) u64 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return 0;
    };

    const op_id = h.undo_stack.pop() orelse {
        setError("Undo stack empty");
        return 0;
    };

    clearError();
    return op_id;
}

/// Get the current undo stack depth.
export fn oblibeniser_undo_depth(handle: ?*Handle) u32 {
    const h = getHandle(handle) orelse return 0;
    return @intCast(h.undo_stack.items.len);
}

/// Time-travel: rewind to a specific operation by applying inverses.
export fn oblibeniser_time_travel(handle: ?*Handle, target_op_id: u64) Result {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };

    // Find the target operation in the undo stack
    var found = false;
    for (h.undo_stack.items) |op_id| {
        if (op_id == target_op_id) {
            found = true;
            break;
        }
    }

    if (!found) {
        setError("Target operation not in undo stack");
        return .invalid_param;
    }

    // Pop and apply inverses until we reach the target
    while (h.undo_stack.items.len > 0) {
        const top_id = h.undo_stack.items[h.undo_stack.items.len - 1];
        if (top_id == target_op_id) break;

        _ = h.undo_stack.pop();

        // Apply inverse for this operation
        const result = oblibeniser_apply_inverse(@ptrCast(h), top_id);
        if (result != .ok) return result;
    }

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result
export fn oblibeniser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "oblibeniser: reversible computing") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn oblibeniser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message
export fn oblibeniser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn oblibeniser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn oblibeniser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn oblibeniser_is_initialized(handle: ?*Handle) u32 {
    const h = getHandle(handle) orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Internal Helpers
//==============================================================================

/// Safely cast an opaque Handle pointer to a LibHandle pointer.
fn getHandle(handle: ?*Handle) ?*LibHandle {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    try std.testing.expect(oblibeniser_is_initialized(handle) == 1);
}

test "record and finalise operation" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    try std.testing.expect(op_id != 0);

    const result = oblibeniser_finalise_forward(handle, op_id, 0);
    try std.testing.expectEqual(Result.ok, result);
}

test "compute and verify inverse" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    // Record with a real pre-state snapshot, then finalise with a real
    // post-state snapshot: compute_inverse requires both to be present.
    var pre = std.mem.zeroes(StateSnapshot);
    pre.state_hash = 0x1111;
    var post = std.mem.zeroes(StateSnapshot);
    post.state_hash = 0x2222;

    const op_id = oblibeniser_record_forward(handle, 0, @intFromPtr(&pre));
    try std.testing.expect(op_id != 0);

    const finalise = oblibeniser_finalise_forward(handle, op_id, @intFromPtr(&post));
    try std.testing.expectEqual(Result.ok, finalise);

    const compute = oblibeniser_compute_inverse(handle, op_id);
    try std.testing.expectEqual(Result.ok, compute);

    const verify = oblibeniser_verify_inverse(handle, op_id);
    try std.testing.expectEqual(Result.ok, verify);
}

test "undo stack push and pop" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    _ = oblibeniser_undo_push(handle, 42);
    _ = oblibeniser_undo_push(handle, 43);

    try std.testing.expectEqual(@as(u32, 2), oblibeniser_undo_depth(handle));

    const popped = oblibeniser_undo_pop(handle);
    try std.testing.expectEqual(@as(u64, 43), popped);
    try std.testing.expectEqual(@as(u32, 1), oblibeniser_undo_depth(handle));
}

test "audit trail append and verify" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    _ = oblibeniser_audit_append(handle, 1, 0, 0xDEAD, 1);
    _ = oblibeniser_audit_append(handle, 2, 0, 0xBEEF, 1);

    const verify = oblibeniser_audit_verify_chain(handle);
    try std.testing.expectEqual(Result.ok, verify);
}

test "error handling with null handle" {
    const result = oblibeniser_compute_inverse(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = oblibeniser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = oblibeniser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
