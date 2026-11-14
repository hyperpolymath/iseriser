// Ephapaxiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
//
// Ephapaxiser enforces single-use linear type semantics on resources. The FFI
// layer provides the runtime bridge for resource tracking, lifecycle management,
// and linearity enforcement. Proofs are erased at compile time; this layer
// handles the operational bookkeeping.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "ephapaxiser built with Zig " ++ @import("builtin").zig_version_string;

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

/// Result codes (must match Idris2 Result type in Ephapaxiser.ABI.Types)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    already_consumed = 5,
    resource_leaked = 6,
    double_free = 7,
};

/// Resource kind classification (must match Idris2 ResourceKind)
pub const ResourceKind = enum(u32) {
    file_handle = 0,
    socket = 1,
    db_connection = 2,
    gpu_buffer = 3,
    crypto_key = 4,
    session_token = 5,
    heap_alloc = 6,
    custom = 255,
};

/// Resource lifecycle states (must match Idris2 ResourceLifecycle)
pub const ResourceLifecycle = enum(u32) {
    acquired = 0,
    in_use = 1,
    consumed = 2,
};

/// Usage count states (must match Idris2 UsageCount)
pub const UsageCount = enum(u32) {
    unused = 0,
    used_once = 1,
    used_multiple = 2,
};

/// Tracked resource: a raw resource handle with linearity metadata.
/// Layout must match Ephapaxiser.ABI.Layout.resourceTrackerLayout:
///   handle    : u64 (8 bytes, offset 0)
///   kind      : u32 (4 bytes, offset 8)
///   lifecycle : u32 (4 bytes, offset 12)
///   usage     : u32 (4 bytes, offset 16)
///   _padding  : u32 (4 bytes, offset 20)
///   Total: 24 bytes, 8-byte aligned
pub const TrackedResource = extern struct {
    handle: u64,
    kind: ResourceKind,
    lifecycle: ResourceLifecycle,
    usage: UsageCount,
    _padding: u32 = 0,
};

/// Library handle (opaque to C callers)
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    /// Registry of tracked resources (handle pointer -> tracked resource)
    resources: std.AutoHashMap(u64, *TrackedResource),
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the ephapaxiser library.
/// Returns a handle, or null on failure.
export fn ephapaxiser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate ephapaxiser handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .resources = std.AutoHashMap(u64, *TrackedResource).init(allocator),
    };

    clearError();
    return handle;
}

/// Free the library handle and all tracked resources.
export fn ephapaxiser_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    // Clean up all tracked resources
    var it = h.resources.valueIterator();
    while (it.next()) |tracked| {
        allocator.destroy(tracked.*);
    }
    h.resources.deinit();

    h.initialized = false;
    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Resource Analysis
//==============================================================================

/// Analyse a source file for resource handles.
/// Returns the number of detected resource handles, or 0 on error.
export fn ephapaxiser_analyse_file(handle: ?*Handle, path_ptr: u64) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // Stub: real implementation will parse source files
    _ = path_ptr;
    clearError();
    return 0;
}

/// Analyse the loaded source for resource handles; returns the count detected.
/// (ABI: Ephapaxiser.ABI.Types Foreign.prim__analyse — `Bits64 -> Bits32`.)
export fn ephapaxiser_analyse(handle: ?*Handle) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }
    // Stub: real implementation will analyse the loaded source for handles.
    clearError();
    return 0;
}

/// Detect paired acquire/release operations in analysed code.
/// Returns the number of detected pairs.
export fn ephapaxiser_detect_pairs(handle: ?*Handle) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // Stub: real implementation will match acquire/release patterns
    clearError();
    return 0;
}

/// Get the resource graph as a serialised structure.
/// Returns a handle to the graph, or null on failure.
export fn ephapaxiser_get_resource_graph(handle: ?*Handle) ?*anyopaque {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    // Stub: real implementation will serialise the resource dependency graph
    clearError();
    return null;
}

//==============================================================================
// Linearity Enforcement
//==============================================================================

/// Wrap a raw resource handle with linearity tracking.
/// The kind parameter identifies the resource type (0=FileHandle, 1=Socket, etc.).
/// Returns a pointer to the tracked resource, or null on failure.
export fn ephapaxiser_wrap_resource(handle: ?*Handle, raw_ptr: u64, kind: u32) ?*anyopaque {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    if (raw_ptr == 0) {
        setError("Cannot wrap null resource pointer");
        return null;
    }

    const resource_kind: ResourceKind = std.meta.intToEnum(ResourceKind, kind) catch .custom;

    const tracked = h.allocator.create(TrackedResource) catch {
        setError("Failed to allocate tracked resource");
        return null;
    };

    tracked.* = .{
        .handle = raw_ptr,
        .kind = resource_kind,
        .lifecycle = .acquired,
        .usage = .unused,
    };

    h.resources.put(raw_ptr, tracked) catch {
        h.allocator.destroy(tracked);
        setError("Failed to register tracked resource");
        return null;
    };

    clearError();
    return tracked;
}

/// Consume (release) a tracked resource.
/// Returns Ok if the resource was properly consumed.
/// Returns AlreadyConsumed if the resource was already consumed (use-after-free).
/// Returns DoubleFree if consumption is attempted on an already-consumed resource.
export fn ephapaxiser_consume_resource(handle: ?*Handle, resource_ptr: u64) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    const tracked = h.resources.get(resource_ptr) orelse {
        setError("Unknown resource pointer — not tracked");
        return .invalid_param;
    };

    // Enforce linearity: only InUse resources can be consumed
    switch (tracked.lifecycle) {
        .consumed => {
            setError("Resource already consumed — double-free attempt");
            return .double_free;
        },
        .acquired => {
            // Transition: acquired -> in_use -> consumed (auto-use-and-consume)
            tracked.lifecycle = .consumed;
            tracked.usage = .used_once;
            clearError();
            return .ok;
        },
        .in_use => {
            if (tracked.usage != .used_once) {
                setError("Resource used multiple times before consumption");
                return .already_consumed;
            }
            tracked.lifecycle = .consumed;
            clearError();
            return .ok;
        },
    }
}

/// Check whether a tracked resource has been consumed.
/// Returns 1 if consumed, 0 otherwise.
export fn ephapaxiser_is_consumed(handle: ?*Handle, resource_ptr: u64) u32 {
    const h = handle orelse return 0;
    if (!h.initialized) return 0;

    const tracked = h.resources.get(resource_ptr) orelse return 0;
    return if (tracked.lifecycle == .consumed) 1 else 0;
}

/// Get the lifecycle state of a tracked resource.
/// Returns 0=Acquired, 1=InUse, 2=Consumed.
export fn ephapaxiser_get_lifecycle(handle: ?*Handle, resource_ptr: u64) u32 {
    const h = handle orelse return 2;
    if (!h.initialized) return 2;

    const tracked = h.resources.get(resource_ptr) orelse return 2;
    return @intFromEnum(tracked.lifecycle);
}

/// Get the usage count of a tracked resource.
/// Returns 0=Unused, 1=UsedOnce, 2=UsedMultiple.
export fn ephapaxiser_get_usage_count(handle: ?*Handle, resource_ptr: u64) u32 {
    const h = handle orelse return 0;
    if (!h.initialized) return 0;

    const tracked = h.resources.get(resource_ptr) orelse return 0;
    return @intFromEnum(tracked.usage);
}

//==============================================================================
// Codegen
//==============================================================================

/// Generate Ephapax wrapper code for detected resources.
/// Output is written to the path specified by out_path_ptr.
export fn ephapaxiser_generate_wrappers(handle: ?*Handle, out_path_ptr: u64) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Stub: real implementation will emit Ephapax wrapper code
    _ = out_path_ptr;
    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (e.g., diagnostic message).
/// Caller must free the returned string with ephapaxiser_free_string.
export fn ephapaxiser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "ephapaxiser: resource linearity enforcer") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library.
export fn ephapaxiser_free_string(str: ?[*:0]const u8) void {
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
export fn ephapaxiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version.
export fn ephapaxiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information.
export fn ephapaxiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized.
export fn ephapaxiser_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    try std.testing.expect(ephapaxiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = ephapaxiser_consume_resource(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = ephapaxiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = ephapaxiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "wrap and consume resource" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    // Wrap a fake resource pointer
    const fake_ptr: u64 = 0xDEAD_BEEF;
    const tracked = ephapaxiser_wrap_resource(handle, fake_ptr, 0);
    try std.testing.expect(tracked != null);

    // Resource should not yet be consumed
    try std.testing.expectEqual(@as(u32, 0), ephapaxiser_is_consumed(handle, fake_ptr));

    // Consume the resource
    const result = ephapaxiser_consume_resource(handle, fake_ptr);
    try std.testing.expectEqual(Result.ok, result);

    // Resource should now be consumed
    try std.testing.expectEqual(@as(u32, 1), ephapaxiser_is_consumed(handle, fake_ptr));
}

test "double consume returns double_free" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0xCAFE_BABE;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 1);

    // First consume: ok
    const first = ephapaxiser_consume_resource(handle, fake_ptr);
    try std.testing.expectEqual(Result.ok, first);

    // Second consume: double-free
    const second = ephapaxiser_consume_resource(handle, fake_ptr);
    try std.testing.expectEqual(Result.double_free, second);
}

test "cannot wrap null pointer" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const tracked = ephapaxiser_wrap_resource(handle, 0, 0);
    try std.testing.expect(tracked == null);
}
