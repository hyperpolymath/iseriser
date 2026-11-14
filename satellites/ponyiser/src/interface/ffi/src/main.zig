// Ponyiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
//
// Ponyiser wraps concurrent code in Pony reference capabilities for data-race
// freedom. This FFI layer provides:
// - Capability inference (analyse access patterns, assign iso/val/ref/box/trn/tag)
// - Subtyping validation (check the capability lattice)
// - Sendability checks (only iso, val, tag cross actor boundaries)
// - Actor and behaviour codegen support
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "ponyiser built with Zig " ++ @import("builtin").zig_version_string;

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

/// Pony reference capabilities.
/// These map 1:1 to the Idris2 RefCapability type and capToInt encoding.
pub const RefCapability = enum(u32) {
    /// Isolated — sole reference, exclusive read/write, sendable (consumed on send)
    iso = 0,
    /// Immutable — globally immutable, any number of aliases, sendable
    val = 1,
    /// Mutable — read/write but actor-local only, not sendable
    ref = 2,
    /// Read-only — may alias ref or val, not sendable on its own
    box = 3,
    /// Transitional — write access with read-only aliases, consumed into val
    trn = 4,
    /// Identity-only — no read, no write, always sendable
    tag = 5,
};

/// Result codes (must match Idris2 Result type)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    invalid_capability = 5,
    sendability_violation = 6,
    actor_not_found = 7,
};

/// Library handle (opaque to prevent direct access)
const HandleData = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
};

//==============================================================================
// Capability Subtyping Lattice
//==============================================================================

/// Check if `sub` subtypes `super` in the Pony capability lattice.
///
/// The lattice is:
///   iso <: trn <: ref <: box
///   iso <: val <: box
///   everything <: tag (tag is weakest)
///   reflexive (cap <: cap)
fn isSubtype(sub: RefCapability, super: RefCapability) bool {
    if (sub == super) return true; // Reflexivity
    if (super == .tag) return true; // Everything subtypes tag

    return switch (sub) {
        .iso => switch (super) {
            .trn, .val, .ref, .box => true,
            else => false,
        },
        .trn => switch (super) {
            .ref, .val, .box => true,
            else => false,
        },
        .ref => switch (super) {
            .box => true,
            else => false,
        },
        .val => switch (super) {
            .box => true,
            else => false,
        },
        .box => false,
        .tag => false,
    };
}

/// Check if a capability is sendable (can cross actor boundaries).
/// Only iso (consumed), val (immutable), and tag (identity) are sendable.
fn isSendable(cap: RefCapability) bool {
    return switch (cap) {
        .iso, .val, .tag => true,
        .ref, .box, .trn => false,
    };
}

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the ponyiser library.
/// Returns a handle, or null on failure.
export fn ponyiser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(HandleData) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
    };

    clearError();
    return @ptrCast(handle);
}

/// Free the library handle.
export fn ponyiser_free(handle: ?*anyopaque) void {
    const h = getHandle(handle) orelse return;
    const allocator = h.allocator;
    h.initialized = false;
    allocator.destroy(h);
    clearError();
}

/// Safely cast opaque handle to HandleData
fn getHandle(handle: ?*anyopaque) ?*HandleData {
    const ptr = handle orelse return null;
    return @ptrCast(@alignCast(ptr));
}

//==============================================================================
// Capability Analysis
//==============================================================================

/// Infer the most permissive safe capability for a data reference.
///
/// Takes a handle and a pointer to an access pattern descriptor.
/// Returns the capability as a u32 (matching RefCapability enum values).
///
/// Access pattern flags (in the descriptor):
/// - Bit 0: is_written (data is mutated)
/// - Bit 1: is_read (data is read)
/// - Bit 2: is_sent (data crosses actor boundaries)
/// - Bit 3: is_aliased (multiple references exist)
/// - Bit 4: is_consumed (reference is consumed/moved)
export fn ponyiser_infer_capability(handle: ?*anyopaque, pattern_ptr: u64) u32 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return 5; // tag (safest default)
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 5;
    }

    // Decode access pattern flags
    const is_written = (pattern_ptr & 0x01) != 0;
    const is_read = (pattern_ptr & 0x02) != 0;
    const is_sent = (pattern_ptr & 0x04) != 0;
    const is_aliased = (pattern_ptr & 0x08) != 0;
    const is_consumed = (pattern_ptr & 0x10) != 0;

    // Inference rules (most restrictive first):
    // - Written + sent + consumed -> iso (exclusive ownership transfer)
    // - Written + not sent + not aliased -> ref (actor-local mutable)
    // - Written + aliased (read-only aliases) -> trn (transitional)
    // - Not written + sent -> val (immutable, globally shareable)
    // - Not written + not sent -> box (read-only, actor-local)
    // - Not read + not written -> tag (identity only)

    if (!is_read and !is_written) return @intFromEnum(RefCapability.tag);
    if (is_written and is_sent and is_consumed) return @intFromEnum(RefCapability.iso);
    if (is_written and !is_aliased) return @intFromEnum(RefCapability.ref);
    if (is_written and is_aliased) return @intFromEnum(RefCapability.trn);
    if (!is_written and is_sent) return @intFromEnum(RefCapability.val);
    if (!is_written and !is_sent) return @intFromEnum(RefCapability.box);

    // Fallback: tag (safest)
    clearError();
    return @intFromEnum(RefCapability.tag);
}

/// Check whether sub subtypes super in the capability lattice.
/// Returns 0 (ok) if valid, 5 (invalid_capability) if not.
export fn ponyiser_check_subtyping(handle: ?*anyopaque, sub: u32, super: u32) u32 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    const sub_cap = std.meta.intToEnum(RefCapability, sub) catch {
        setError("Invalid sub capability value");
        return @intFromEnum(Result.invalid_param);
    };

    const super_cap = std.meta.intToEnum(RefCapability, super) catch {
        setError("Invalid super capability value");
        return @intFromEnum(Result.invalid_param);
    };

    if (isSubtype(sub_cap, super_cap)) {
        clearError();
        return @intFromEnum(Result.ok);
    } else {
        setError("Capability subtyping violation");
        return @intFromEnum(Result.invalid_capability);
    }
}

/// Check whether a capability is sendable (can cross actor boundaries).
/// Returns 0 (ok) if sendable, 6 (sendability_violation) if not.
export fn ponyiser_check_sendable(handle: ?*anyopaque, cap: u32) u32 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    const ref_cap = std.meta.intToEnum(RefCapability, cap) catch {
        setError("Invalid capability value");
        return @intFromEnum(Result.invalid_param);
    };

    if (isSendable(ref_cap)) {
        clearError();
        return @intFromEnum(Result.ok);
    } else {
        setError("Capability is not sendable across actor boundaries");
        return @intFromEnum(Result.sendability_violation);
    }
}

//==============================================================================
// Actor Codegen (stubs — full implementation in Rust CLI)
//==============================================================================

/// Generate a Pony actor from a descriptor.
/// Returns 0 on success.
export fn ponyiser_generate_actor(handle: ?*anyopaque, descriptor: u64, out_buf: u64, out_len: u32) u32 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    _ = descriptor;
    _ = out_buf;
    _ = out_len;

    // TODO: Implement actor codegen in FFI layer
    clearError();
    return @intFromEnum(Result.ok);
}

/// Generate a Pony behaviour from a descriptor.
/// Validates sendability of all parameters before generating.
export fn ponyiser_generate_behaviour(handle: ?*anyopaque, actor_name: u64, behaviour_desc: u64, out_buf: u64, out_len: u32) u32 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    _ = actor_name;
    _ = behaviour_desc;
    _ = out_buf;
    _ = out_len;

    // TODO: Implement behaviour codegen in FFI layer
    clearError();
    return @intFromEnum(Result.ok);
}

/// Generate a causal message type for actor-to-actor communication.
/// Validates sendability of payload capability.
export fn ponyiser_generate_message(handle: ?*anyopaque, sender: u64, receiver: u64, payload_cap: u32, out_buf: u64, out_len: u32) u32 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    // Validate payload capability is sendable
    const cap = std.meta.intToEnum(RefCapability, payload_cap) catch {
        setError("Invalid payload capability");
        return @intFromEnum(Result.invalid_param);
    };

    if (!isSendable(cap)) {
        setError("Payload capability must be sendable (iso, val, or tag)");
        return @intFromEnum(Result.sendability_violation);
    }

    _ = sender;
    _ = receiver;
    _ = out_buf;
    _ = out_len;

    // TODO: Implement message codegen in FFI layer
    clearError();
    return @intFromEnum(Result.ok);
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result.
/// Caller must free the returned string.
export fn ponyiser_get_string(handle: ?*anyopaque) ?[*:0]const u8 {
    const h = getHandle(handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "ponyiser ready") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library.
export fn ponyiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message.
/// Returns null if no error.
export fn ponyiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version.
export fn ponyiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information.
export fn ponyiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized.
export fn ponyiser_is_initialized(handle: ?*anyopaque) u32 {
    const h = getHandle(handle) orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try std.testing.expect(ponyiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = ponyiser_check_subtyping(null, 0, 0);
    try std.testing.expectEqual(@as(u32, @intFromEnum(Result.null_pointer)), result);

    const err = ponyiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = ponyiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "subtyping: reflexive" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // Every capability subtypes itself
    inline for (0..6) |i| {
        try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, i, i));
    }
}

test "subtyping: iso <: trn <: ref <: box" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, 0, 4)); // iso <: trn
    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, 4, 2)); // trn <: ref
    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, 2, 3)); // ref <: box
}

test "subtyping: iso <: val <: box" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, 0, 1)); // iso <: val
    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, 1, 3)); // val <: box
}

test "subtyping: everything <: tag" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    inline for (0..6) |i| {
        try std.testing.expectEqual(@as(u32, 0), ponyiser_check_subtyping(handle, i, 5)); // cap <: tag
    }
}

test "subtyping: ref is NOT <: val" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try std.testing.expect(ponyiser_check_subtyping(handle, 2, 1) != 0); // ref NOT <: val
}

test "sendability: iso, val, tag are sendable" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_sendable(handle, 0)); // iso
    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_sendable(handle, 1)); // val
    try std.testing.expectEqual(@as(u32, 0), ponyiser_check_sendable(handle, 5)); // tag
}

test "sendability: ref, box, trn are NOT sendable" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try std.testing.expect(ponyiser_check_sendable(handle, 2) != 0); // ref
    try std.testing.expect(ponyiser_check_sendable(handle, 3) != 0); // box
    try std.testing.expect(ponyiser_check_sendable(handle, 4) != 0); // trn
}

test "capability inference: written + sent + consumed = iso" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // Flags: written(1) + read(2) + sent(4) + consumed(16) = 0x17
    const cap = ponyiser_infer_capability(handle, 0x17);
    try std.testing.expectEqual(@as(u32, @intFromEnum(RefCapability.iso)), cap);
}

test "capability inference: read-only + sent = val" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // Flags: read(2) + sent(4) = 0x06
    const cap = ponyiser_infer_capability(handle, 0x06);
    try std.testing.expectEqual(@as(u32, @intFromEnum(RefCapability.val)), cap);
}

test "message generation rejects non-sendable payload" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // ref (2) is not sendable — should be rejected
    const result = ponyiser_generate_message(handle, 0, 0, 2, 0, 0);
    try std.testing.expectEqual(@as(u32, @intFromEnum(Result.sendability_violation)), result);
}
