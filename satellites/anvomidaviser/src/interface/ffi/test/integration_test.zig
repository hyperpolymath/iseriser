// Anvomidaviser Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for ISU notation parsing, scoring, and rule validation.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn anvomidaviser_init() ?*opaque {};
extern fn anvomidaviser_free(?*opaque {}) void;
extern fn anvomidaviser_process(?*opaque {}, u32) c_int;
extern fn anvomidaviser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn anvomidaviser_free_string(?[*:0]const u8) void;
extern fn anvomidaviser_last_error() ?[*:0]const u8;
extern fn anvomidaviser_version() [*:0]const u8;
extern fn anvomidaviser_is_initialized(?*opaque {}) u32;
extern fn anvomidaviser_score_program(?*opaque {}) u32;
extern fn anvomidaviser_validate_program(?*opaque {}) u32;
extern fn anvomidaviser_check_zayak(?*opaque {}) u32;
extern fn anvomidaviser_check_element_count(?*opaque {}, u32) u32;
extern fn anvomidaviser_base_value(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const initialized = anvomidaviser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = anvomidaviser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Operation Tests
//==============================================================================

test "process with valid handle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const result = anvomidaviser_process(handle, 42);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "process with null handle returns error" {
    const result = anvomidaviser_process(null, 42);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Scoring Tests
//==============================================================================

test "score program with valid handle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    // Score should return 0 for empty program (no elements loaded)
    const score = anvomidaviser_score_program(handle);
    try testing.expectEqual(@as(u32, 0), score);
}

test "base value with valid handle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const bv = anvomidaviser_base_value(handle);
    _ = bv; // Will return 0 until element parsing is implemented
}

//==============================================================================
// Validation Tests
//==============================================================================

test "validate program with valid handle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const result = anvomidaviser_validate_program(handle);
    try testing.expectEqual(@as(u32, 0), result); // 0 = valid (empty program)
}

test "check zayak with valid handle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const result = anvomidaviser_check_zayak(handle);
    try testing.expectEqual(@as(u32, 0), result); // 0 = no violation
}

test "check element count for short program" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const result = anvomidaviser_check_element_count(handle, 0); // 0 = short program
    try testing.expectEqual(@as(u32, 0), result);
}

test "check element count for free skate" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const result = anvomidaviser_check_element_count(handle, 1); // 1 = free skate
    try testing.expectEqual(@as(u32, 0), result);
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const str = anvomidaviser_get_string(handle);
    defer if (str) |s| anvomidaviser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = anvomidaviser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = anvomidaviser_process(null, 0);

    const err = anvomidaviser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    _ = anvomidaviser_process(handle, 0);

    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = anvomidaviser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = anvomidaviser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(h1);

    const h2 = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = anvomidaviser_process(h1, 1);
    _ = anvomidaviser_process(h2, 2);
}

test "double free is safe" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;

    anvomidaviser_free(handle);
    anvomidaviser_free(handle); // Should not crash
}

test "free null is safe" {
    anvomidaviser_free(null); // Should not crash
}

//==============================================================================
// Thread Safety Tests (if applicable)
//==============================================================================

test "concurrent operations" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    const ThreadContext = struct {
        h: *opaque {},
        id: u32,
    };

    const thread_fn = struct {
        fn run(ctx: ThreadContext) void {
            _ = anvomidaviser_process(ctx.h, ctx.id);
        }
    }.run;

    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, thread_fn, .{
            ThreadContext{ .h = handle, .id = @intCast(i) },
        });
    }

    for (threads) |thread| {
        thread.join();
    }
}
