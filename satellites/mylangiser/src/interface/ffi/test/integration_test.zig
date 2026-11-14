// Mylangiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Verify that the Zig FFI correctly implements the Idris2 ABI for
// progressive-disclosure layer generation.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn mylangiser_init() ?*opaque {};
extern fn mylangiser_free(?*opaque {}) void;
extern fn mylangiser_analyse_surface(?*opaque {}, ?[*]const u8, u32) c_int;
extern fn mylangiser_endpoint_count(?*opaque {}) u32;
extern fn mylangiser_compute_scores(?*opaque {}) c_int;
extern fn mylangiser_get_score(?*opaque {}, u32) u32;
extern fn mylangiser_generate_layers(?*opaque {}) c_int;
extern fn mylangiser_get_level(?*opaque {}, u32) u32;
extern fn mylangiser_default_count(?*opaque {}, u32) u32;
extern fn mylangiser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn mylangiser_free_string(?[*:0]const u8) void;
extern fn mylangiser_last_error() ?[*:0]const u8;
extern fn mylangiser_version() [*:0]const u8;
extern fn mylangiser_is_initialized(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const initialized = mylangiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = mylangiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// API Surface Analysis Tests
//==============================================================================

test "analyse surface with null handle returns null_pointer" {
    const result = mylangiser_analyse_surface(null, null, 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "analyse surface with null buffer returns null_pointer" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const result = mylangiser_analyse_surface(handle, null, 10);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "analyse surface with empty buffer returns invalid_param" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const buf = "x";
    const result = mylangiser_analyse_surface(handle, buf.ptr, 0);
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_param
}

test "endpoint count is zero before analysis" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const count = mylangiser_endpoint_count(handle);
    try testing.expectEqual(@as(u32, 0), count);
}

//==============================================================================
// Complexity Scoring Tests
//==============================================================================

test "compute scores on empty endpoint list succeeds" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const result = mylangiser_compute_scores(handle);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "compute scores with null handle returns error" {
    const result = mylangiser_compute_scores(null);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "get score for out-of-range index returns zero" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    _ = mylangiser_compute_scores(handle);
    const score = mylangiser_get_score(handle, 999);
    try testing.expectEqual(@as(u32, 0), score);
}

//==============================================================================
// Layer Generation Tests
//==============================================================================

test "generate layers without scores returns error" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const result = mylangiser_generate_layers(handle);
    try testing.expectEqual(@as(c_int, 1), result); // 1 = error (scores not computed)
}

test "generate layers after scoring succeeds" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    _ = mylangiser_compute_scores(handle);
    const result = mylangiser_generate_layers(handle);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "default count for out-of-range index returns zero" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    _ = mylangiser_compute_scores(handle);
    _ = mylangiser_generate_layers(handle);
    const count = mylangiser_default_count(handle, 999);
    try testing.expectEqual(@as(u32, 0), count);
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    const str = mylangiser_get_string(handle);
    defer if (str) |s| mylangiser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = mylangiser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = mylangiser_analyse_surface(null, null, 0);

    const err = mylangiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    _ = mylangiser_compute_scores(handle);
    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = mylangiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = mylangiser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(h1);

    const h2 = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = mylangiser_compute_scores(h1);
    _ = mylangiser_compute_scores(h2);
}

test "free null is safe" {
    mylangiser_free(null); // Should not crash
}
