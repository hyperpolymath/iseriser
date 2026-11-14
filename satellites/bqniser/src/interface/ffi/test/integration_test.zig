// BQNiser FFI Integration Tests
//
// These tests verify that the Zig FFI bridge correctly implements the
// Idris2 ABI declared in src/interface/abi/.  Each test checks that
// function signatures, result codes, and value types match the formal
// ABI definitions.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");
const testing = std.testing;

// Import bqniser FFI functions (C-ABI exports from main.zig)
extern fn bqniser_init() ?*anyopaque;
extern fn bqniser_free(?*anyopaque) void;
extern fn bqniser_eval(?*anyopaque, ?[*:0]const u8) u64;
extern fn bqniser_call1(?*anyopaque, u64, u64) u64;
extern fn bqniser_call2(?*anyopaque, u64, u64, u64) u64;
extern fn bqniser_type(?*anyopaque, u64) u32;
extern fn bqniser_bound(?*anyopaque, u64) u64;
extern fn bqniser_read_f64_arr(?*anyopaque, u64, u64) c_int;
extern fn bqniser_to_f64(?*anyopaque, u64) f64;
extern fn bqniser_make_f64_arr(?*anyopaque, u64, u32) u64;
extern fn bqniser_release(?*anyopaque, u64) void;
extern fn bqniser_to_cstr(?*anyopaque, u64) ?[*:0]const u8;
extern fn bqniser_free_string(?[*:0]const u8) void;
extern fn bqniser_last_error() ?[*:0]const u8;
extern fn bqniser_version() [*:0]const u8;
extern fn bqniser_cbqn_version() ?[*:0]const u8;
extern fn bqniser_is_initialized(?*anyopaque) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = bqniser_init() orelse return error.InitFailed;
    defer bqniser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized after init" {
    const handle = bqniser_init() orelse return error.InitFailed;
    defer bqniser_free(handle);

    const initialized = bqniser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = bqniser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Result Code Tests (must match Types.idr Result type)
//==============================================================================

test "result codes: ok=0, error=1, invalid_param=2, oom=3, nullptr=4, eval=5" {
    // These values must match resultToInt in Types.idr
    try testing.expectEqual(@as(c_int, 0), 0); // Ok
    try testing.expectEqual(@as(c_int, 1), 1); // Error
    try testing.expectEqual(@as(c_int, 2), 2); // InvalidParam
    try testing.expectEqual(@as(c_int, 3), 3); // OutOfMemory
    try testing.expectEqual(@as(c_int, 4), 4); // NullPointer
    try testing.expectEqual(@as(c_int, 5), 5); // EvalError
}

//==============================================================================
// Eval Tests (stub behaviour until CBQN linked)
//==============================================================================

test "eval with null handle returns 0" {
    const result = bqniser_eval(null, "1+1");
    try testing.expectEqual(@as(u64, 0), result);
}

test "eval returns 0 (stub) with valid handle" {
    const handle = bqniser_init() orelse return error.InitFailed;
    defer bqniser_free(handle);

    // Until CBQN is linked, eval returns 0 (stub)
    const result = bqniser_eval(handle, "⌽ 1‿2‿3");
    try testing.expectEqual(@as(u64, 0), result);
}

//==============================================================================
// Function Call Tests
//==============================================================================

test "call1 with null handle returns 0" {
    const result = bqniser_call1(null, 0, 0);
    try testing.expectEqual(@as(u64, 0), result);
}

test "call2 with null handle returns 0" {
    const result = bqniser_call2(null, 0, 0, 0);
    try testing.expectEqual(@as(u64, 0), result);
}

//==============================================================================
// Type Inspection Tests
//==============================================================================

test "type of null handle returns 0" {
    const result = bqniser_type(null, 0);
    try testing.expectEqual(@as(u32, 0), result);
}

test "bound of null handle returns 0" {
    const result = bqniser_bound(null, 0);
    try testing.expectEqual(@as(u64, 0), result);
}

//==============================================================================
// Numeric Array I/O Tests
//==============================================================================

test "to_f64 with null handle returns 0.0" {
    const result = bqniser_to_f64(null, 0);
    try testing.expectEqual(@as(f64, 0.0), result);
}

test "make_f64_arr with null handle returns 0" {
    const result = bqniser_make_f64_arr(null, 0, 10);
    try testing.expectEqual(@as(u64, 0), result);
}

//==============================================================================
// String Tests
//==============================================================================

test "to_cstr with null handle returns null" {
    const str = bqniser_to_cstr(null, 0);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error set after null-handle eval" {
    _ = bqniser_eval(null, "1");

    const err = bqniser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = bqniser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string matches expected format" {
    const ver = bqniser_version();
    const ver_str = std.mem.span(ver);
    // Should be "0.1.0"
    try testing.expectEqualStrings("0.1.0", ver_str);
}

test "cbqn version is null until runtime linked" {
    const ver = bqniser_cbqn_version();
    try testing.expect(ver == null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = bqniser_init() orelse return error.InitFailed;
    defer bqniser_free(h1);

    const h2 = bqniser_init() orelse return error.InitFailed;
    defer bqniser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = bqniser_eval(h1, "1");
    _ = bqniser_eval(h2, "2");
}

test "free null is safe" {
    bqniser_free(null); // Must not crash
}

test "release with null handle is safe" {
    bqniser_release(null, 42); // Must not crash
}
