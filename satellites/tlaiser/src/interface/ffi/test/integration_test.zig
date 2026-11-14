// Tlaiser Integration Tests
//
// Verify that the Zig FFI correctly implements the Idris2 ABI declared
// in src/interface/abi/{Types,Layout,Foreign}.idr.
//
// Tests cover: lifecycle, state extraction, TLA+ generation, TLC execution,
// error handling, version info, memory safety, and thread safety.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");
const testing = std.testing;

// Import FFI functions (linked from libtlaiser)
extern fn tlaiser_init() ?*opaque {};
extern fn tlaiser_free(?*opaque {}) void;
extern fn tlaiser_extract_state_machine(?*opaque {}, ?[*:0]const u8) c_int;
extern fn tlaiser_get_state_count(?*opaque {}) u32;
extern fn tlaiser_get_transition_count(?*opaque {}) u32;
extern fn tlaiser_generate_tlaplus(?*opaque {}, ?[*:0]const u8) c_int;
extern fn tlaiser_generate_pluscal(?*opaque {}, ?[*:0]const u8) c_int;
extern fn tlaiser_add_safety_property(?*opaque {}, ?[*:0]const u8, ?[*:0]const u8) c_int;
extern fn tlaiser_add_liveness_property(?*opaque {}, ?[*:0]const u8, ?[*:0]const u8) c_int;
extern fn tlaiser_run_tlc(?*opaque {}, ?[*:0]const u8, u32, u64) c_int;
extern fn tlaiser_get_result_type(?*opaque {}) u32;
extern fn tlaiser_get_states_explored(?*opaque {}) u64;
extern fn tlaiser_get_trace_length(?*opaque {}) u32;
extern fn tlaiser_get_trace_string(?*opaque {}) ?[*:0]const u8;
extern fn tlaiser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn tlaiser_free_string(?[*:0]const u8) void;
extern fn tlaiser_last_error() ?[*:0]const u8;
extern fn tlaiser_version() [*:0]const u8;
extern fn tlaiser_build_info() [*:0]const u8;
extern fn tlaiser_is_initialized(?*opaque {}) u32;

// ===========================================================================
// Lifecycle Tests
// ===========================================================================

test "create and destroy engine handle" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized after creation" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    const initialized = tlaiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = tlaiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

// ===========================================================================
// State Extraction Tests
// ===========================================================================

test "extract with null handle returns null_pointer" {
    const result = tlaiser_extract_state_machine(null, null);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "extract with null path returns null_pointer" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    const result = tlaiser_extract_state_machine(handle, null);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "state count is zero before extraction" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    try testing.expectEqual(@as(u32, 0), tlaiser_get_state_count(handle));
    try testing.expectEqual(@as(u32, 0), tlaiser_get_transition_count(handle));
}

// ===========================================================================
// TLA+ Generation Tests
// ===========================================================================

test "generate tlaplus with null handle" {
    const result = tlaiser_generate_tlaplus(null, null);
    try testing.expectEqual(@as(c_int, 4), result);
}

test "generate pluscal with null handle" {
    const result = tlaiser_generate_pluscal(null, null);
    try testing.expectEqual(@as(c_int, 4), result);
}

test "add safety property with null handle" {
    const result = tlaiser_add_safety_property(null, "MutualExclusion", "pc[1] /= \"cs\" \\/ pc[2] /= \"cs\"");
    try testing.expectEqual(@as(c_int, 4), result);
}

test "add liveness property with null handle" {
    const result = tlaiser_add_liveness_property(null, "EventualAccess", "<>(pc[1] = \"cs\")");
    try testing.expectEqual(@as(c_int, 4), result);
}

// ===========================================================================
// TLC Execution Tests
// ===========================================================================

test "run TLC with null handle" {
    const result = tlaiser_run_tlc(null, null, 0, 0);
    try testing.expectEqual(@as(c_int, 4), result);
}

test "result type is not_run before TLC execution" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    const result_type = tlaiser_get_result_type(handle);
    try testing.expectEqual(@as(u32, 255), result_type); // 255 = not_run
}

test "states explored is zero before TLC execution" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    try testing.expectEqual(@as(u64, 0), tlaiser_get_states_explored(handle));
}

test "trace length is zero before TLC execution" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    try testing.expectEqual(@as(u32, 0), tlaiser_get_trace_length(handle));
}

// ===========================================================================
// Error Handling Tests
// ===========================================================================

test "last error after null handle operation" {
    _ = tlaiser_extract_state_machine(null, null);

    const err = tlaiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
        tlaiser_free_string(e);
    }
}

test "no error after successful init" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    // Error should be cleared after successful operation
    const err = tlaiser_last_error();
    try testing.expect(err == null);
}

// ===========================================================================
// Version Tests
// ===========================================================================

test "version string is not empty" {
    const ver = tlaiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = tlaiser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains tlaiser" {
    const info = tlaiser_build_info();
    const info_str = std.mem.span(info);

    try testing.expect(std.mem.indexOf(u8, info_str, "tlaiser") != null);
}

// ===========================================================================
// Memory Safety Tests
// ===========================================================================

test "multiple handles are independent" {
    const h1 = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(h1);

    const h2 = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = tlaiser_extract_state_machine(h1, "dummy.rs");
    _ = tlaiser_extract_state_machine(h2, "other.rs");
}

test "free null is safe" {
    tlaiser_free(null); // Should not crash
}

test "free string null is safe" {
    tlaiser_free_string(null); // Should not crash
}

// ===========================================================================
// Thread Safety Tests
// ===========================================================================

test "concurrent operations on separate handles" {
    const h1 = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(h1);

    const h2 = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(h2);

    const ThreadContext = struct {
        h: *opaque {},
        id: u32,
    };

    const thread_fn = struct {
        fn run(ctx: ThreadContext) void {
            _ = tlaiser_extract_state_machine(ctx.h, "test.rs");
            _ = tlaiser_get_state_count(ctx.h);
        }
    }.run;

    var threads: [2]std.Thread = undefined;
    threads[0] = try std.Thread.spawn(.{}, thread_fn, .{
        ThreadContext{ .h = h1, .id = 0 },
    });
    threads[1] = try std.Thread.spawn(.{}, thread_fn, .{
        ThreadContext{ .h = h2, .id = 1 },
    });

    for (threads) |thread| {
        thread.join();
    }
}
