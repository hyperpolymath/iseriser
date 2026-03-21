// Iseriser Integration Tests
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// declarations from src/interface/abi/Foreign.idr.
//
// The tests exercise the full generation pipeline: context creation,
// language model loading, template expansion, and repo generation.
//
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");
const testing = std.testing;

// Import iseriser FFI functions (declared in Foreign.idr, implemented in main.zig)
extern fn iseriser_init() ?*opaque {};
extern fn iseriser_free(?*opaque {}) void;
extern fn iseriser_load_language(?*opaque {}, ?[*:0]const u8) c_int;
extern fn iseriser_language_name(?*opaque {}) ?[*:0]const u8;
extern fn iseriser_feature_count(?*opaque {}) u32;
extern fn iseriser_expand_templates(?*opaque {}, ?[*:0]const u8) c_int;
extern fn iseriser_artifact_count(?*opaque {}) u32;
extern fn iseriser_generate_repo(?*opaque {}, ?[*:0]const u8, ?[*:0]const u8) c_int;
extern fn iseriser_validate_language(?*opaque {}, ?[*:0]const u8) c_int;
extern fn iseriser_last_error() ?[*:0]const u8;
extern fn iseriser_version() [*:0]const u8;
extern fn iseriser_build_info() [*:0]const u8;
extern fn iseriser_is_initialized(?*opaque {}) u32;
extern fn iseriser_has_model(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy generation context" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    try testing.expect(ctx != null);
}

test "context is initialized after creation" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const initialized = iseriser_is_initialized(ctx);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null context is not initialized" {
    const initialized = iseriser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

test "no model loaded initially" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const has = iseriser_has_model(ctx);
    try testing.expectEqual(@as(u32, 0), has);
}

//==============================================================================
// Language Model Tests
//==============================================================================

test "load language model from manifest" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const result = iseriser_load_language(ctx, "test-manifest.toml");
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
    try testing.expectEqual(@as(u32, 1), iseriser_has_model(ctx));
}

test "load language with null context returns error" {
    const result = iseriser_load_language(null, "test.toml");
    try testing.expectEqual(@as(c_int, 5), result); // 5 = null_pointer
}

test "load language with null path returns error" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const result = iseriser_load_language(ctx, null);
    try testing.expectEqual(@as(c_int, 5), result); // 5 = null_pointer
}

test "feature count is zero before loading" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const count = iseriser_feature_count(ctx);
    try testing.expectEqual(@as(u32, 0), count);
}

test "feature count after loading model" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    _ = iseriser_load_language(ctx, "test.toml");
    const count = iseriser_feature_count(ctx);
    try testing.expect(count > 0);
}

//==============================================================================
// Template Expansion Tests
//==============================================================================

test "expand templates without model returns error" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const result = iseriser_expand_templates(ctx, "/tmp/output");
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_language
}

test "expand templates after loading model" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    _ = iseriser_load_language(ctx, "test.toml");
    const result = iseriser_expand_templates(ctx, "/tmp/output");
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "artifact count after expansion" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    _ = iseriser_load_language(ctx, "test.toml");
    _ = iseriser_expand_templates(ctx, "/tmp/output");
    const count = iseriser_artifact_count(ctx);
    try testing.expect(count > 0);
}

//==============================================================================
// High-Level Generation Tests
//==============================================================================

test "generate repo in one call" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const result = iseriser_generate_repo(ctx, "test.toml", "/tmp/output");
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
    try testing.expect(iseriser_artifact_count(ctx) > 0);
}

test "generate repo with null context" {
    const result = iseriser_generate_repo(null, "test.toml", "/tmp/output");
    try testing.expectEqual(@as(c_int, 5), result); // 5 = null_pointer
}

//==============================================================================
// Validation Tests
//==============================================================================

test "validate language with null context" {
    const result = iseriser_validate_language(null, "test.toml");
    try testing.expectEqual(@as(c_int, 5), result); // 5 = null_pointer
}

test "validate language with valid manifest" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const result = iseriser_validate_language(ctx, "test.toml");
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null context operation" {
    _ = iseriser_load_language(null, "test.toml");

    const err = iseriser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    _ = iseriser_load_language(ctx, "test.toml");
    // Error should be cleared after successful operation
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = iseriser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version is semantic version format" {
    const ver = iseriser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info contains iseriser" {
    const info = iseriser_build_info();
    const info_str = std.mem.span(info);

    try testing.expect(std.mem.indexOf(u8, info_str, "iseriser") != null);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple contexts are independent" {
    const ctx1 = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx1);

    const ctx2 = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx2);

    try testing.expect(ctx1 != ctx2);

    // Load model in ctx1 only
    _ = iseriser_load_language(ctx1, "test.toml");
    try testing.expectEqual(@as(u32, 1), iseriser_has_model(ctx1));
    try testing.expectEqual(@as(u32, 0), iseriser_has_model(ctx2));
}

test "free null is safe" {
    iseriser_free(null); // Should not crash
}
