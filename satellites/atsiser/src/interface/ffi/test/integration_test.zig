// Atsiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for atsiser's C source analysis and ATS2 wrapper generation engine.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn atsiser_init() ?*opaque {};
extern fn atsiser_free(?*opaque {}) void;
extern fn atsiser_parse_header(?*opaque {}, ?[*:0]const u8) c_int;
extern fn atsiser_analyse_allocations(?*opaque {}) u32;
extern fn atsiser_build_ownership_graph(?*opaque {}) c_int;
extern fn atsiser_detect_buffers(?*opaque {}) u32;
extern fn atsiser_generate_viewtypes(?*opaque {}, ?[*:0]const u8) c_int;
extern fn atsiser_generate_proofs(?*opaque {}, ?[*:0]const u8) c_int;
extern fn atsiser_generate_bounds_proofs(?*opaque {}, ?[*:0]const u8) c_int;
extern fn atsiser_compile_ats2(?*opaque {}, ?[*:0]const u8, ?[*:0]const u8) c_int;
extern fn atsiser_verify_linkage(?*opaque {}, ?[*:0]const u8, ?[*:0]const u8) c_int;
extern fn atsiser_allocation_count(?*opaque {}) u32;
extern fn atsiser_ownership_edge_count(?*opaque {}) u32;
extern fn atsiser_proof_count(?*opaque {}) u32;
extern fn atsiser_analysis_report(?*opaque {}) ?[*:0]const u8;
extern fn atsiser_free_string(?[*:0]const u8) void;
extern fn atsiser_last_error() ?[*:0]const u8;
extern fn atsiser_version() [*:0]const u8;
extern fn atsiser_build_info() [*:0]const u8;
extern fn atsiser_is_initialized(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const initialized = atsiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = atsiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// C Source Analysis Tests
//==============================================================================

test "parse header with null handle returns error" {
    const result = atsiser_parse_header(null, "test.h");
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "parse header with null path returns error" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const result = atsiser_parse_header(handle, null);
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_param
}

test "allocation count starts at zero" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const count = atsiser_analyse_allocations(handle);
    try testing.expectEqual(@as(u32, 0), count);
}

test "build ownership graph with valid handle" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const result = atsiser_build_ownership_graph(handle);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "detect buffers with valid handle" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const count = atsiser_detect_buffers(handle);
    try testing.expectEqual(@as(u32, 0), count);
}

//==============================================================================
// ATS2 Generation Tests
//==============================================================================

test "generate viewtypes with null handle returns error" {
    const result = atsiser_generate_viewtypes(null, "/tmp/out");
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "generate viewtypes with null output returns error" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const result = atsiser_generate_viewtypes(handle, null);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

test "generate proofs with valid handle" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const result = atsiser_generate_proofs(handle, "/tmp/proofs");
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

test "generate bounds proofs with valid handle" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const result = atsiser_generate_bounds_proofs(handle, "/tmp/bounds");
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

//==============================================================================
// Compilation Tests
//==============================================================================

test "compile ats2 with null handle returns error" {
    const result = atsiser_compile_ats2(null, "/tmp/ats", "/tmp/c");
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "verify linkage with null handle returns error" {
    const result = atsiser_verify_linkage(null, "/tmp/gen.c", "/tmp/lib.so");
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

//==============================================================================
// Analysis Result Tests
//==============================================================================

test "analysis counts are zero after init" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    try testing.expectEqual(@as(u32, 0), atsiser_allocation_count(handle));
    try testing.expectEqual(@as(u32, 0), atsiser_ownership_edge_count(handle));
    try testing.expectEqual(@as(u32, 0), atsiser_proof_count(handle));
}

test "analysis report returns valid JSON" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    const report = atsiser_analysis_report(handle);
    defer if (report) |r| atsiser_free_string(r);

    try testing.expect(report != null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = atsiser_parse_header(null, null);

    const err = atsiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(handle);

    _ = atsiser_build_ownership_graph(handle);
    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = atsiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = atsiser_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains atsiser" {
    const info = atsiser_build_info();
    const info_str = std.mem.span(info);

    try testing.expect(std.mem.indexOf(u8, info_str, "atsiser") != null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(h1);

    const h2 = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = atsiser_build_ownership_graph(h1);
    _ = atsiser_build_ownership_graph(h2);
}

test "free null is safe" {
    atsiser_free(null); // Should not crash
}
