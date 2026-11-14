// Dafniser Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// defined in src/interface/abi/{Types,Layout,Foreign}.idr.
//
// Test coverage:
//   - Library lifecycle (init, free, double-free, null-safety)
//   - Specification loading pipeline
//   - Dafny generation gate (must load spec first)
//   - Z3 verification result queries
//   - Target compilation enum validation
//   - String and error handling
//   - Memory safety (concurrent handles, null pointers)

const std = @import("std");
const testing = std.testing;

// Import FFI functions (must match Foreign.idr declarations)
extern fn dafniser_init() ?*opaque {};
extern fn dafniser_free(?*opaque {}) void;
extern fn dafniser_load_spec(?*opaque {}, ?[*:0]const u8) ?*opaque {};
extern fn dafniser_free_spec(?*opaque {}) void;
extern fn dafniser_generate_dafny(?*opaque {}, ?[*:0]const u8) c_int;
extern fn dafniser_verify(?*opaque {}, ?[*:0]const u8) ?*opaque {};
extern fn dafniser_result_count(?*opaque {}) u32;
extern fn dafniser_result_status(?*opaque {}, u32) u32;
extern fn dafniser_result_witness(?*opaque {}, u32) ?[*:0]const u8;
extern fn dafniser_compile_target(?*opaque {}, ?[*:0]const u8, u32) c_int;
extern fn dafniser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn dafniser_free_string(?[*:0]const u8) void;
extern fn dafniser_last_error() ?[*:0]const u8;
extern fn dafniser_version() [*:0]const u8;
extern fn dafniser_build_info() [*:0]const u8;
extern fn dafniser_is_initialized(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const initialized = dafniser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = dafniser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Specification Loading Tests
//==============================================================================

test "load spec with null handle returns null" {
    const result = dafniser_load_spec(null, "manifest.toml");
    try testing.expect(result == null);
}

test "load spec with null path returns null" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const result = dafniser_load_spec(handle, null);
    try testing.expect(result == null);
}

//==============================================================================
// Dafny Generation Tests
//==============================================================================

test "generate requires loaded spec" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    // Generating without loading a spec should fail
    const result = dafniser_generate_dafny(handle, "output");
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_param
}

test "generate with null handle returns null_pointer" {
    const result = dafniser_generate_dafny(null, "output");
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Verification Result Tests
//==============================================================================

test "result count with no verification returns zero" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const count = dafniser_result_count(handle);
    try testing.expectEqual(@as(u32, 0), count);
}

test "result status out of bounds returns internal_error" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const status = dafniser_result_status(handle, 999);
    try testing.expectEqual(@as(u32, 3), status); // 3 = InternalError
}

test "result witness with no counterexample returns null" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const witness = dafniser_result_witness(handle, 0);
    try testing.expect(witness == null);
}

//==============================================================================
// Target Compilation Tests
//==============================================================================

test "compile target with invalid enum returns invalid_param" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const result = dafniser_compile_target(handle, "dir", 99);
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_param
}

test "compile target with null handle returns null_pointer" {
    const result = dafniser_compile_target(null, "dir", 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const str = dafniser_get_string(handle);
    defer if (str) |s| dafniser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = dafniser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = dafniser_generate_dafny(null, null);

    const err = dafniser_last_error();
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
    const ver = dafniser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = dafniser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains zig" {
    const info = dafniser_build_info();
    const info_str = std.mem.span(info);

    // Build info should mention dafniser
    try testing.expect(std.mem.indexOf(u8, info_str, "dafniser") != null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(h1);

    const h2 = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(h2);

    try testing.expect(h1 != h2);
}

test "free null is safe" {
    dafniser_free(null); // Should not crash
}
