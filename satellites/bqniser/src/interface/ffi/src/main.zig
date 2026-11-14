// BQNiser FFI Implementation — CBQN Runtime Bridge
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// It wraps the CBQN C API (bqnffi.h) to provide a safe, lifecycle-managed bridge
// for evaluating BQN expressions and reading/writing BQN array values.
//
// All types and layouts must match the Idris2 ABI definitions in Types.idr and Layout.idr.
//
// CBQN C API: https://github.com/dzaima/CBQN/blob/master/include/bqnffi.h
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "bqniser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage for the last error message.
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message.
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error.
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/interface/abi/Types.idr)
//==============================================================================

/// Result codes — must match Idris2 Result type in Types.idr.
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    eval_error = 5,
};

/// BQN value type tags — must match BQNType in Types.idr.
pub const BQNType = enum(u32) {
    number = 0,
    character = 1,
    function = 2,
    modifier1 = 3,
    modifier2 = 4,
    namespace = 5,
    array = 6,
};

/// CBQN opaque value handle.
/// In CBQN's C API, BQNV is a typedef for a pointer-sized value.
pub const BQNV = u64;

/// Library handle — holds CBQN runtime state.
/// Opaque to callers; must be created via bqniser_init and freed via bqniser_free.
const BqniserHandle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    /// Whether bqn_init() has been called on this handle.
    cbqn_ready: bool,
};

//==============================================================================
// CBQN C API Declarations (from bqnffi.h)
// These are the raw CBQN functions we wrap.
// TODO: Link against libcbqn when CBQN integration is built.
//==============================================================================

// extern fn bqn_init() void;
// extern fn bqn_free() void;
// extern fn bqn_eval(src: [*:0]const u8) BQNV;
// extern fn bqn_call1(f: BQNV, x: BQNV) BQNV;
// extern fn bqn_call2(f: BQNV, w: BQNV, x: BQNV) BQNV;
// extern fn bqn_readF64Arr(v: BQNV, buf: [*]f64) void;
// extern fn bqn_toF64(v: BQNV) f64;
// extern fn bqn_type(v: BQNV) c_int;
// extern fn bqn_bound(v: BQNV) usize;
// extern fn bqn_makeF64Arr(n: usize, data: [*]const f64) BQNV;
// extern fn bqn_free(v: BQNV) void;

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialise the bqniser FFI bridge and CBQN runtime.
/// Returns a handle, or null on failure.
export fn bqniser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(BqniserHandle) catch {
        setError("Failed to allocate bqniser handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .cbqn_ready = false, // TODO: call bqn_init() when linked
    };

    clearError();
    return @ptrCast(handle);
}

/// Shut down the bqniser FFI bridge and release CBQN resources.
export fn bqniser_free(handle: ?*anyopaque) void {
    const h = castHandle(handle) orelse return;
    const allocator = h.allocator;

    // TODO: call bqn_free() if cbqn_ready
    h.initialized = false;
    h.cbqn_ready = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// BQN Expression Evaluation
//==============================================================================

/// Evaluate a BQN expression string via CBQN.
/// Returns a BQNV handle to the result, or 0 on error.
export fn bqniser_eval(handle: ?*anyopaque, expr: ?[*:0]const u8) BQNV {
    const h = castHandle(handle) orelse {
        setError("Null handle in bqniser_eval");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    _ = expr;
    // TODO: call bqn_eval(expr) when CBQN is linked
    setError("CBQN runtime not yet linked — eval is a stub");
    return 0;
}

//==============================================================================
// BQN Function Application
//==============================================================================

/// Monadic call: F x.
export fn bqniser_call1(handle: ?*anyopaque, f: BQNV, x: BQNV) BQNV {
    const h = castHandle(handle) orelse {
        setError("Null handle in bqniser_call1");
        return 0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }
    _ = f;
    _ = x;
    // TODO: return bqn_call1(f, x)
    setError("CBQN runtime not yet linked — call1 is a stub");
    return 0;
}

/// Dyadic call: w F x.
export fn bqniser_call2(handle: ?*anyopaque, f: BQNV, w: BQNV, x: BQNV) BQNV {
    const h = castHandle(handle) orelse {
        setError("Null handle in bqniser_call2");
        return 0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }
    _ = f;
    _ = w;
    _ = x;
    // TODO: return bqn_call2(f, w, x)
    setError("CBQN runtime not yet linked — call2 is a stub");
    return 0;
}

//==============================================================================
// BQN Value Type Inspection
//==============================================================================

/// Get the type tag of a CBQN value.
export fn bqniser_type(handle: ?*anyopaque, val: BQNV) u32 {
    const h = castHandle(handle) orelse {
        setError("Null handle in bqniser_type");
        return 0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }
    _ = val;
    // TODO: return @intCast(bqn_type(val))
    return 0;
}

/// Get the element count (bound) of a BQN array.
export fn bqniser_bound(handle: ?*anyopaque, val: BQNV) u64 {
    const h = castHandle(handle) orelse {
        setError("Null handle in bqniser_bound");
        return 0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }
    _ = val;
    // TODO: return bqn_bound(val)
    return 0;
}

//==============================================================================
// Numeric Array I/O
//==============================================================================

/// Read a BQN numeric array into a pre-allocated f64 buffer.
export fn bqniser_read_f64_arr(handle: ?*anyopaque, val: BQNV, buf: BQNV) Result {
    const h = castHandle(handle) orelse {
        setError("Null handle");
        return .null_pointer;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }
    _ = val;
    _ = buf;
    // TODO: bqn_readF64Arr(val, @ptrFromInt(buf))
    setError("CBQN runtime not yet linked — read_f64_arr is a stub");
    return .@"error";
}

/// Extract a scalar f64 from a BQN numeric value.
export fn bqniser_to_f64(handle: ?*anyopaque, val: BQNV) f64 {
    const h = castHandle(handle) orelse {
        setError("Null handle in bqniser_to_f64");
        return 0.0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0.0;
    }
    _ = val;
    // TODO: return bqn_toF64(val)
    return 0.0;
}

/// Create a BQN numeric array from an f64 buffer.
export fn bqniser_make_f64_arr(handle: ?*anyopaque, buf: BQNV, len: u32) BQNV {
    const h = castHandle(handle) orelse {
        setError("Null handle");
        return 0;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }
    _ = buf;
    _ = len;
    // TODO: return bqn_makeF64Arr(len, @ptrFromInt(buf))
    setError("CBQN runtime not yet linked — make_f64_arr is a stub");
    return 0;
}

//==============================================================================
// BQN Value Lifecycle
//==============================================================================

/// Release a CBQN value (decrement reference count).
export fn bqniser_release(handle: ?*anyopaque, val: BQNV) void {
    const h = castHandle(handle) orelse return;
    if (!h.initialized) return;
    _ = val;
    // TODO: bqn_free(val)
}

//==============================================================================
// String Operations
//==============================================================================

/// Convert a BQN character array to a null-terminated C string.
/// Caller must free via bqniser_free_string.
export fn bqniser_to_cstr(handle: ?*anyopaque, val: BQNV) ?[*:0]const u8 {
    const h = castHandle(handle) orelse {
        setError("Null handle");
        return null;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }
    _ = val;
    // TODO: read BQN char array, convert to C string
    setError("CBQN runtime not yet linked — to_cstr is a stub");
    return null;
}

/// Free a C string allocated by bqniser_to_cstr.
export fn bqniser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message.  Returns null if no error.
export fn bqniser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the bqniser FFI bridge version.
export fn bqniser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information.
export fn bqniser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

/// Get CBQN runtime version (null until CBQN is linked).
export fn bqniser_cbqn_version() ?[*:0]const u8 {
    // TODO: query CBQN for its version string
    return null;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if the bqniser handle is initialised.
export fn bqniser_is_initialized(handle: ?*anyopaque) u32 {
    const h = castHandle(handle) orelse return 0;
    return if (h.initialized) 1 else 0;
}

/// Cast an opaque pointer to BqniserHandle.
fn castHandle(ptr: ?*anyopaque) ?*BqniserHandle {
    const p = ptr orelse return null;
    return @ptrCast(@alignCast(p));
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle — init and free" {
    const handle = bqniser_init() orelse return error.InitFailed;
    defer bqniser_free(handle);

    try std.testing.expect(bqniser_is_initialized(handle) == 1);
}

test "error handling — null handle" {
    const result_type = bqniser_type(null, 0);
    try std.testing.expectEqual(@as(u32, 0), result_type);

    const err = bqniser_last_error();
    try std.testing.expect(err != null);
}

test "version string is semantic version" {
    const ver = bqniser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "cbqn version is null until linked" {
    const ver = bqniser_cbqn_version();
    try std.testing.expect(ver == null);
}
