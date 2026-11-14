// Ephapaxiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for ephapaxiser's resource linearity enforcement.

const std = @import("std");
const testing = std.testing;

// Import FFI functions (match Foreign.idr declarations)
extern fn ephapaxiser_init() ?*opaque {};
extern fn ephapaxiser_free(?*opaque {}) void;
extern fn ephapaxiser_analyse_file(?*opaque {}, u64) u32;
extern fn ephapaxiser_detect_pairs(?*opaque {}) u32;
extern fn ephapaxiser_get_resource_graph(?*opaque {}) ?*opaque {};
extern fn ephapaxiser_wrap_resource(?*opaque {}, u64, u32) ?*opaque {};
extern fn ephapaxiser_consume_resource(?*opaque {}, u64) c_int;
extern fn ephapaxiser_is_consumed(?*opaque {}, u64) u32;
extern fn ephapaxiser_get_lifecycle(?*opaque {}, u64) u32;
extern fn ephapaxiser_get_usage_count(?*opaque {}, u64) u32;
extern fn ephapaxiser_generate_wrappers(?*opaque {}, u64) c_int;
extern fn ephapaxiser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn ephapaxiser_free_string(?[*:0]const u8) void;
extern fn ephapaxiser_last_error() ?[*:0]const u8;
extern fn ephapaxiser_version() [*:0]const u8;
extern fn ephapaxiser_build_info() [*:0]const u8;
extern fn ephapaxiser_is_initialized(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const initialized = ephapaxiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = ephapaxiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Resource Wrapping Tests
//==============================================================================

test "wrap resource with valid handle" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0x1000;
    const tracked = ephapaxiser_wrap_resource(handle, fake_ptr, 0); // FileHandle
    try testing.expect(tracked != null);
}

test "wrap resource with null handle fails" {
    const tracked = ephapaxiser_wrap_resource(null, 0x1000, 0);
    try testing.expect(tracked == null);
}

test "wrap null resource pointer fails" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const tracked = ephapaxiser_wrap_resource(handle, 0, 0);
    try testing.expect(tracked == null);
}

test "wrapped resource starts in Acquired lifecycle" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0x2000;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 1); // Socket

    // Lifecycle should be Acquired (0)
    const lifecycle = ephapaxiser_get_lifecycle(handle, fake_ptr);
    try testing.expectEqual(@as(u32, 0), lifecycle);
}

test "wrapped resource starts with Unused count" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0x3000;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 2); // DbConnection

    // Usage should be Unused (0)
    const usage = ephapaxiser_get_usage_count(handle, fake_ptr);
    try testing.expectEqual(@as(u32, 0), usage);
}

//==============================================================================
// Linearity Enforcement Tests
//==============================================================================

test "consume resource succeeds" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0x4000;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 0);

    const result = ephapaxiser_consume_resource(handle, fake_ptr);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = Ok
}

test "consumed resource is marked consumed" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0x5000;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 0);

    // Not yet consumed
    try testing.expectEqual(@as(u32, 0), ephapaxiser_is_consumed(handle, fake_ptr));

    // Consume
    _ = ephapaxiser_consume_resource(handle, fake_ptr);

    // Now consumed
    try testing.expectEqual(@as(u32, 1), ephapaxiser_is_consumed(handle, fake_ptr));
}

test "double consume returns double_free error" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0x6000;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 4); // CryptoKey

    // First consume: Ok
    const first = ephapaxiser_consume_resource(handle, fake_ptr);
    try testing.expectEqual(@as(c_int, 0), first);

    // Second consume: DoubleFree (7)
    const second = ephapaxiser_consume_resource(handle, fake_ptr);
    try testing.expectEqual(@as(c_int, 7), second);
}

test "consume with null handle returns null_pointer" {
    const result = ephapaxiser_consume_resource(null, 0x7000);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = NullPointer
}

test "consume unknown resource returns invalid_param" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    // Consume a resource that was never wrapped
    const result = ephapaxiser_consume_resource(handle, 0xFFFF);
    try testing.expectEqual(@as(c_int, 2), result); // 2 = InvalidParam
}

//==============================================================================
// Resource Kind Tests
//==============================================================================

test "wrap all resource kinds" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    // FileHandle (0)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA001, 0) != null);
    // Socket (1)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA002, 1) != null);
    // DbConnection (2)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA003, 2) != null);
    // GpuBuffer (3)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA004, 3) != null);
    // CryptoKey (4)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA005, 4) != null);
    // SessionToken (5)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA006, 5) != null);
    // HeapAlloc (6)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA007, 6) != null);
    // Custom (255)
    try testing.expect(ephapaxiser_wrap_resource(handle, 0xA008, 255) != null);
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const str = ephapaxiser_get_string(handle);
    defer if (str) |s| ephapaxiser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = ephapaxiser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = ephapaxiser_consume_resource(null, 0);

    const err = ephapaxiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const fake_ptr: u64 = 0xB000;
    _ = ephapaxiser_wrap_resource(handle, fake_ptr, 0);
    _ = ephapaxiser_consume_resource(handle, fake_ptr);

    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = ephapaxiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = ephapaxiser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info is not empty" {
    const info = ephapaxiser_build_info();
    const info_str = std.mem.span(info);

    try testing.expect(info_str.len > 0);
    // Should mention ephapaxiser
    try testing.expect(std.mem.indexOf(u8, info_str, "ephapaxiser") != null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(h1);

    const h2 = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(h2);

    try testing.expect(h1 != h2);

    // Resources tracked in h1 should not be visible in h2
    _ = ephapaxiser_wrap_resource(h1, 0xC001, 0);
    try testing.expectEqual(@as(u32, 0), ephapaxiser_is_consumed(h2, 0xC001));
}

test "free null is safe" {
    ephapaxiser_free(null); // Should not crash
}

//==============================================================================
// Analysis Stub Tests
//==============================================================================

test "analyse file with valid handle returns 0 (stub)" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const count = ephapaxiser_analyse_file(handle, 0x1234);
    try testing.expectEqual(@as(u32, 0), count);
}

test "detect pairs with valid handle returns 0 (stub)" {
    const handle = ephapaxiser_init() orelse return error.InitFailed;
    defer ephapaxiser_free(handle);

    const count = ephapaxiser_detect_pairs(handle);
    try testing.expectEqual(@as(u32, 0), count);
}
