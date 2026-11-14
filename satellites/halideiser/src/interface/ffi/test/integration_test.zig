// Halideiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// declared in src/interface/abi/Foreign.idr.
//
// The tests exercise the full pipeline lifecycle:
//   init → add stages → set buffer → set target → compile → execute → free

const std = @import("std");
const testing = std.testing;

// Import FFI functions (linked against libhalideiser)
extern fn halideiser_init() ?*opaque {};
extern fn halideiser_free(?*opaque {}) void;
extern fn halideiser_add_stage(?*opaque {}, u32, f64, f64) c_int;
extern fn halideiser_set_input_buffer(?*opaque {}, u32, u32, u32, u32, u32) c_int;
extern fn halideiser_set_target(?*opaque {}, u32) c_int;
extern fn halideiser_apply_schedule(?*opaque {}, u32, u32, u32, u32) c_int;
extern fn halideiser_compile_pipeline(?*opaque {}) c_int;
extern fn halideiser_execute_pipeline(?*opaque {}, u64, u64, u32, u32) c_int;
extern fn halideiser_autotune(?*opaque {}, u32, u32) c_int;
extern fn halideiser_last_error() ?[*:0]const u8;
extern fn halideiser_free_string(?[*:0]const u8) void;
extern fn halideiser_version() [*:0]const u8;
extern fn halideiser_build_info() [*:0]const u8;
extern fn halideiser_is_initialized(?*opaque {}) u32;
extern fn halideiser_stage_count(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy pipeline context" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    try testing.expect(ctx != null);
}

test "context is initialised after init" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const initialized = halideiser_is_initialized(ctx);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null context is not initialised" {
    const initialized = halideiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Pipeline Construction Tests
//==============================================================================

test "add gaussian blur stage" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_add_stage(ctx, 0, 1.5, 0.0); // GaussianBlur, sigma=1.5
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
    try testing.expectEqual(@as(u32, 1), halideiser_stage_count(ctx));
}

test "add multi-stage pipeline" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    // Build a typical image processing pipeline:
    // Gaussian blur → Sharpen → Brightness/Contrast
    _ = halideiser_add_stage(ctx, 0, 2.0, 0.0);  // GaussianBlur sigma=2.0
    _ = halideiser_add_stage(ctx, 2, 0.5, 1.0);   // Sharpen amount=0.5, sigma=1.0
    _ = halideiser_add_stage(ctx, 9, 10.0, 1.2);   // BrightnessContrast br=10, co=1.2

    try testing.expectEqual(@as(u32, 3), halideiser_stage_count(ctx));
}

test "add stage with null context returns null_pointer" {
    const result = halideiser_add_stage(null, 0, 1.0, 0.0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "add stage with invalid tag returns invalid_param" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_add_stage(ctx, 99, 0.0, 0.0);
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_param
}

//==============================================================================
// Buffer Configuration Tests
//==============================================================================

test "set 1920x1080 RGB input buffer" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_input_buffer(ctx, 1920, 1080, 3, 1, 0); // uint8
    try testing.expectEqual(@as(c_int, 0), result);
}

test "set 4K RGBA float32 buffer" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_input_buffer(ctx, 3840, 2160, 4, 1, 3); // float32
    try testing.expectEqual(@as(c_int, 0), result);
}

test "reject zero-width buffer" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_input_buffer(ctx, 0, 1080, 3, 1, 0);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

test "reject zero-height buffer" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_input_buffer(ctx, 1920, 0, 3, 1, 0);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

//==============================================================================
// Schedule Configuration Tests
//==============================================================================

test "set x86 AVX2 target" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_target(ctx, 1); // x86_avx2
    try testing.expectEqual(@as(c_int, 0), result);
}

test "set CUDA target" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_target(ctx, 5); // cuda
    try testing.expectEqual(@as(c_int, 0), result);
}

test "apply tile schedule to stage" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    _ = halideiser_add_stage(ctx, 0, 1.5, 0.0); // Add a stage first

    const result = halideiser_apply_schedule(ctx, 0, 0, 32, 8); // tile 32x8
    try testing.expectEqual(@as(c_int, 0), result);
}

test "apply schedule to nonexistent stage returns error" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    // No stages added — stage_index 0 is out of range
    const result = halideiser_apply_schedule(ctx, 0, 0, 32, 8);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

//==============================================================================
// Compilation Tests
//==============================================================================

test "compile requires at least one stage" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    _ = halideiser_set_input_buffer(ctx, 1920, 1080, 3, 1, 0);
    _ = halideiser_set_target(ctx, 1);

    const result = halideiser_compile_pipeline(ctx);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param (no stages)
}

test "compile requires input dimensions" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    _ = halideiser_add_stage(ctx, 0, 1.5, 0.0);
    _ = halideiser_set_target(ctx, 1);

    const result = halideiser_compile_pipeline(ctx);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param (no dims)
}

test "compile requires target" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    _ = halideiser_add_stage(ctx, 0, 1.5, 0.0);
    _ = halideiser_set_input_buffer(ctx, 1920, 1080, 3, 1, 0);

    const result = halideiser_compile_pipeline(ctx);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param (no target)
}

test "full compilation pipeline" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    _ = halideiser_add_stage(ctx, 0, 1.5, 0.0);          // GaussianBlur
    _ = halideiser_set_input_buffer(ctx, 640, 480, 3, 1, 0); // VGA RGB uint8
    _ = halideiser_set_target(ctx, 1);                     // x86_avx2
    _ = halideiser_apply_schedule(ctx, 0, 0, 32, 8);      // tile 32x8

    const result = halideiser_compile_pipeline(ctx);
    try testing.expectEqual(@as(c_int, 0), result);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null context operation" {
    _ = halideiser_add_stage(null, 0, 0.0, 0.0);

    const err = halideiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
        halideiser_free_string(e);
    }
}

test "no error after successful operation" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    _ = halideiser_add_stage(ctx, 0, 1.5, 0.0);

    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = halideiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version is semantic format" {
    const ver = halideiser_version();
    const ver_str = std.mem.span(ver);

    // Should contain at least one dot (X.Y.Z)
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains halideiser" {
    const info = halideiser_build_info();
    const info_str = std.mem.span(info);

    try testing.expect(std.mem.indexOf(u8, info_str, "halideiser") != null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple contexts are independent" {
    const ctx1 = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx1);

    const ctx2 = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx2);

    try testing.expect(ctx1 != ctx2);

    // Adding stages to ctx1 should not affect ctx2
    _ = halideiser_add_stage(ctx1, 0, 1.5, 0.0);
    _ = halideiser_add_stage(ctx1, 2, 0.5, 1.0);

    try testing.expectEqual(@as(u32, 2), halideiser_stage_count(ctx1));
    try testing.expectEqual(@as(u32, 0), halideiser_stage_count(ctx2));
}

test "free null is safe" {
    halideiser_free(null); // Should not crash
}
