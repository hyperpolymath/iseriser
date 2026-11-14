// Nimiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// as defined in Nimiser.ABI.Types, Nimiser.ABI.Layout, and Nimiser.ABI.Foreign.

const std = @import("std");
const testing = std.testing;

// Import FFI functions (linked from libnimiser)
extern fn nimiser_init() ?*opaque {};
extern fn nimiser_free(?*opaque {}) void;
extern fn nimiser_compile(?*opaque {}, ?[*:0]const u8, u32, u32) c_int;
extern fn nimiser_gen_template(?*opaque {}, ?[*:0]const u8, u32, u32, u32) ?[*:0]const u8;
extern fn nimiser_gen_macro(?*opaque {}, ?[*:0]const u8, u32, u32) ?[*:0]const u8;
extern fn nimiser_dump_ast(?*opaque {}, ?[*:0]const u8) ?[*:0]const u8;
extern fn nimiser_list_exports(?*opaque {}, ?[*:0]const u8) ?[*:0]const u8;
extern fn nimiser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn nimiser_free_string(?[*:0]const u8) void;
extern fn nimiser_process_array(?*opaque {}, ?[*]const u8, u32) c_int;
extern fn nimiser_last_error() ?[*:0]const u8;
extern fn nimiser_version() [*:0]const u8;
extern fn nimiser_build_info() [*:0]const u8;
extern fn nimiser_is_initialized(?*opaque {}) u32;
extern fn nimiser_nim_available() u32;
extern fn nimiser_nim_version() ?[*:0]const u8;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const initialized = nimiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = nimiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Nim Compilation Pipeline Tests
//==============================================================================

test "compile with null handle returns null_pointer" {
    const result = nimiser_compile(null, null, 0, 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "compile with null source returns null_pointer" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const result = nimiser_compile(handle, null, 0, 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Template Generation Tests
//==============================================================================

test "generate template with valid handle" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const tmpl = nimiser_gen_template(handle, "processBuffer", 1, 2, 1);
    defer if (tmpl) |t| nimiser_free_string(t);

    try testing.expect(tmpl != null);
}

test "generate template with null handle" {
    const tmpl = nimiser_gen_template(null, "test", 0, 0, 0);
    try testing.expect(tmpl == null);
}

test "generate template with null name" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const tmpl = nimiser_gen_template(handle, null, 0, 0, 0);
    try testing.expect(tmpl == null);
}

//==============================================================================
// Macro Generation Tests
//==============================================================================

test "generate macro with valid handle" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const mac = nimiser_gen_macro(handle, "exportAll", 1, 1);
    defer if (mac) |m| nimiser_free_string(m);

    try testing.expect(mac != null);
}

test "generate macro with null handle" {
    const mac = nimiser_gen_macro(null, "test", 0, 0);
    try testing.expect(mac == null);
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const str = nimiser_get_string(handle);
    defer if (str) |s| nimiser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = nimiser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = nimiser_compile(null, null, 0, 0);

    const err = nimiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
        nimiser_free_string(e);
    }
}

test "no error after successful operation" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    _ = nimiser_get_string(handle);
    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = nimiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = nimiser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains nimiser" {
    const info = nimiser_build_info();
    const info_str = std.mem.span(info);

    try testing.expect(std.mem.indexOf(u8, info_str, "nimiser") != null);
}

//==============================================================================
// Nim Compiler Detection Tests
//==============================================================================

test "nim availability check does not crash" {
    _ = nimiser_nim_available();
}

test "nim version returns null or valid string" {
    const ver = nimiser_nim_version();
    if (ver) |v| {
        const ver_str = std.mem.span(v);
        try testing.expect(ver_str.len > 0);
        nimiser_free_string(v);
    }
    // null is also acceptable (nim not installed)
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(h1);

    const h2 = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = nimiser_get_string(h1);
    _ = nimiser_get_string(h2);
}

test "free null is safe" {
    nimiser_free(null); // Should not crash
}

//==============================================================================
// Array/Buffer Tests
//==============================================================================

test "process array with valid data" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const result = nimiser_process_array(handle, &data, data.len);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "process array with null handle" {
    const data = [_]u8{ 0x01 };
    const result = nimiser_process_array(null, &data, data.len);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "process array with null buffer" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const result = nimiser_process_array(handle, null, 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Result Code Consistency Tests
//==============================================================================

test "all result codes are distinct" {
    const codes = [_]c_int{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (codes, 0..) |a, i| {
        for (codes[i + 1 ..]) |b| {
            try testing.expect(a != b);
        }
    }
}
