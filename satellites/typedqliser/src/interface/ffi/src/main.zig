// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// TypedQLiser FFI Implementation
//
// C-ABI FFI surface for embedding TypedQLiser in other languages. The Idris2 ABI
// (src/interface/abi/Typedqliser/ABI/Foreign.idr and .../Types.idr) is the
// SOURCE OF TRUTH: every exported `typedqliser_*` symbol, its arity, and the
// integer encodings below match the Idris declarations exactly.

const std = @import("std");

// Version information (keep in sync with project)
const VERSION = "0.1.0";
const BUILD_INFO = "TypedQLiser built with Zig " ++ @import("builtin").zig_version_string;

/// The ten cumulative type-safety levels are ordinals 1..10
/// (see Typedqliser.ABI.Types.SafetyLevel / levelNat). 0 means "no query
/// checked yet". This is the maximum certifiable level.
const MAX_SAFETY_LEVEL: u32 = 10;

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
// Core Types (must match Typedqliser.ABI.Types)
//==============================================================================

/// Result codes — MUST match Typedqliser.ABI.Types.resultToInt EXACTLY:
///   Ok=0, Error=1, InvalidQuery=2, SchemaError=3, NullPointer=4
pub const Result = enum(c_int) {
    ok = 0,
    err = 1, // Idris `Error`
    invalid_query = 2, // Idris `InvalidQuery`
    schema_error = 3, // Idris `SchemaError`
    null_pointer = 4, // Idris `NullPointer`
};

fn code(r: Result) c_int {
    return @intFromEnum(r);
}

/// Library handle — a struct internally; C only ever sees it as an opaque
/// pointer (its fields are never exposed in the header). The Idris ABI threads
/// the handle as a `Bits64` pointer value; `init` returns it and the domain
/// functions reconstruct it via `handleFromPtr`.
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    /// Whether a schema has been registered. A default schema is registered at
    /// init so `check_query` is usable out of the box; real wiring replaces it.
    schema_registered: bool,
    /// Highest safety level the last checked query achieved (0 if none).
    certificate_level: u32,
};

/// Reconstruct a `*Handle` from the `Bits64` pointer value the Idris ABI passes.
/// Returns null for a null/zero pointer.
fn handleFromPtr(ptr: u64) ?*Handle {
    if (ptr == 0) return null;
    return @ptrFromInt(ptr);
}

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the library. Returns a handle (as an opaque pointer / Bits64),
/// or null on failure. Matches `typedqliser_init : PrimIO Bits64`.
export fn typedqliser_init() callconv(.C) ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .schema_registered = true,
        .certificate_level = 0,
    };

    clearError();
    return handle;
}

/// Free the library handle. Matches `typedqliser_free : Bits64 -> PrimIO ()`.
export fn typedqliser_free(handle: ?*Handle) callconv(.C) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Core Domain Operations (declared in Typedqliser.ABI.Foreign)
//==============================================================================

/// Check a null-terminated query string against the registered schema, up to
/// the requested safety level. Returns a Result code.
///
/// Matches `typedqliser_check_query : Bits64 -> String -> Bits32 -> PrimIO Bits32`
/// i.e. (handle pointer, query C-string, requested level) -> result code.
///
/// Reference semantics:
///   * null handle                       -> NullPointer (4)
///   * null / empty / unbalanced query   -> InvalidQuery (2)
///   * no schema registered              -> SchemaError (3)
///   * otherwise                         -> Ok (0); records the achieved
///     certificate level (capped at the requested level and MAX_SAFETY_LEVEL).
export fn typedqliser_check_query(
    handle_ptr: u64,
    query: ?[*:0]const u8,
    level: u32,
) callconv(.C) u32 {
    const h = handleFromPtr(handle_ptr) orelse {
        setError("Null handle");
        return @intCast(code(.null_pointer));
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intCast(code(.err));
    }

    const q = query orelse {
        setError("Null query");
        h.certificate_level = 0;
        return @intCast(code(.invalid_query));
    };

    const slice = std.mem.span(q);
    if (!isWellFormedQuery(slice)) {
        setError("Malformed query");
        h.certificate_level = 0;
        return @intCast(code(.invalid_query));
    }

    if (!h.schema_registered) {
        setError("No schema registered");
        h.certificate_level = 0;
        return @intCast(code(.schema_error));
    }

    // Reference proof engine: a well-formed query against a registered schema
    // is certified up to the requested level, bounded by the ten-level ceiling.
    const requested = if (level == 0) MAX_SAFETY_LEVEL else level;
    h.certificate_level = @min(requested, MAX_SAFETY_LEVEL);

    clearError();
    return @intCast(code(.ok));
}

/// Highest safety level the last checked query achieved (0 if none).
///
/// Matches `typedqliser_certificate_level : Bits64 -> PrimIO Bits32`.
export fn typedqliser_certificate_level(handle_ptr: u64) callconv(.C) u32 {
    const h = handleFromPtr(handle_ptr) orelse return 0;
    if (!h.initialized) return 0;
    return h.certificate_level;
}

/// Minimal structural validity check for the reference engine: non-empty and
/// balanced parentheses. (Full parsing is the codegen/proof-engine's job.)
fn isWellFormedQuery(query: []const u8) bool {
    if (query.len == 0) return false;
    var depth: i64 = 0;
    for (query) |c| {
        switch (c) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth < 0) return false;
            },
            else => {},
        }
    }
    return depth == 0;
}

//==============================================================================
// Auxiliary Operations (superset of the ABI; harmless extras)
//==============================================================================

/// Process data (example operation)
export fn typedqliser_process(handle: ?*Handle, input: u32) callconv(.C) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .err;
    }

    _ = input;

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (example). Caller must free the returned string.
export fn typedqliser_get_string(handle: ?*Handle) callconv(.C) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "Example result") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn typedqliser_free_string(str: ?[*:0]const u8) callconv(.C) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;

    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Array/Buffer Operations
//==============================================================================

/// Process an array of data
export fn typedqliser_process_array(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) callconv(.C) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const buf = buffer orelse {
        setError("Null buffer");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .err;
    }

    const data = buf[0..len];
    _ = data;

    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message. Returns null if no error.
export fn typedqliser_last_error() callconv(.C) ?[*:0]const u8 {
    const err = last_error orelse return null;

    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version. Matches `typedqliser_version : PrimIO Bits64`
/// (the Idris side reads the returned pointer with idris2_getString).
export fn typedqliser_version() callconv(.C) [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn typedqliser_build_info() callconv(.C) [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Callback Support
//==============================================================================

/// Callback function type (C ABI)
pub const Callback = *const fn (u64, u32) callconv(.C) u32;

/// Register a callback
export fn typedqliser_register_callback(
    handle: ?*Handle,
    callback: ?Callback,
) callconv(.C) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const cb = callback orelse {
        setError("Null callback");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .err;
    }

    _ = cb;

    clearError();
    return .ok;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn typedqliser_is_initialized(handle: ?*Handle) callconv(.C) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = typedqliser_init() orelse return error.InitFailed;
    defer typedqliser_free(handle);

    try std.testing.expect(typedqliser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = typedqliser_process(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = typedqliser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = typedqliser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "result codes match Typedqliser.ABI.Types.resultToInt" {
    try std.testing.expectEqual(@as(c_int, 0), code(.ok));
    try std.testing.expectEqual(@as(c_int, 1), code(.err));
    try std.testing.expectEqual(@as(c_int, 2), code(.invalid_query)); // InvalidQuery
    try std.testing.expectEqual(@as(c_int, 3), code(.schema_error)); // SchemaError
    try std.testing.expectEqual(@as(c_int, 4), code(.null_pointer));
}

test "check_query and certificate_level" {
    const handle = typedqliser_init() orelse return error.InitFailed;
    defer typedqliser_free(handle);
    const ptr: u64 = @intFromPtr(handle);

    // No query checked yet.
    try std.testing.expectEqual(@as(u32, 0), typedqliser_certificate_level(ptr));

    // A well-formed query at the maximum level is certified up to level 10.
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.ok))),
        typedqliser_check_query(ptr, "select(id) from users", 10),
    );
    try std.testing.expectEqual(@as(u32, 10), typedqliser_certificate_level(ptr));

    // Requesting level 0 means "as high as possible" -> capped at 10.
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.ok))),
        typedqliser_check_query(ptr, "count()", 0),
    );
    try std.testing.expectEqual(@as(u32, 10), typedqliser_certificate_level(ptr));

    // A lower requested level bounds the certificate.
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.ok))),
        typedqliser_check_query(ptr, "id", 3),
    );
    try std.testing.expectEqual(@as(u32, 3), typedqliser_certificate_level(ptr));
}

test "check_query rejects malformed queries with InvalidQuery (2)" {
    const handle = typedqliser_init() orelse return error.InitFailed;
    defer typedqliser_free(handle);
    const ptr: u64 = @intFromPtr(handle);

    // Empty query.
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.invalid_query))),
        typedqliser_check_query(ptr, "", 5),
    );
    // Unbalanced parentheses.
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.invalid_query))),
        typedqliser_check_query(ptr, "select(id", 5),
    );
    // Failed checks reset the certificate level to 0.
    try std.testing.expectEqual(@as(u32, 0), typedqliser_certificate_level(ptr));
}

test "check_query reports SchemaError (3) when no schema is registered" {
    const handle = typedqliser_init() orelse return error.InitFailed;
    defer typedqliser_free(handle);
    const ptr: u64 = @intFromPtr(handle);

    handle.schema_registered = false;
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.schema_error))),
        typedqliser_check_query(ptr, "select(id)", 5),
    );
}

test "check_query and certificate_level reject the null handle" {
    try std.testing.expectEqual(
        @as(u32, @intCast(code(.null_pointer))),
        typedqliser_check_query(0, "select(id)", 5),
    );
    try std.testing.expectEqual(@as(u32, 0), typedqliser_certificate_level(0));
}
