// Wokelangiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for consent injection, accessibility checking, i18n formatting, and
// cultural sensitivity analysis.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn wokelangiser_init() ?*opaque {};
extern fn wokelangiser_free(?*opaque {}) void;
extern fn wokelangiser_inject_consent(?*opaque {}, u32, u64) c_int;
extern fn wokelangiser_check_consent(?*opaque {}, u32, u64) c_int;
extern fn wokelangiser_record_consent_transition(?*opaque {}, u64, u32, u32) c_int;
extern fn wokelangiser_check_accessibility(?*opaque {}, u64, u32) c_int;
extern fn wokelangiser_annotate_element(?*opaque {}, u64, u64, u64, u32, u32) c_int;
extern fn wokelangiser_contrast_ratio(u32, u32) u32;
extern fn wokelangiser_extract_strings(?*opaque {}, u64, u64) c_int;
extern fn wokelangiser_format_locale(?*opaque {}, u32, u64, u64) c_int;
extern fn wokelangiser_check_sensitivity(?*opaque {}, u64, u32) c_int;
extern fn wokelangiser_suggest_alternative(?*opaque {}, u64, u64, u32) c_int;
extern fn wokelangiser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn wokelangiser_free_string(?[*:0]const u8) void;
extern fn wokelangiser_last_error() ?[*:0]const u8;
extern fn wokelangiser_version() [*:0]const u8;
extern fn wokelangiser_is_initialized(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const initialized = wokelangiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = wokelangiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Consent Tests
//==============================================================================

test "inject consent with valid handle" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    // Inject OptIn consent at a dummy location
    const result = wokelangiser_inject_consent(handle, 0, 1); // 0=OptIn, ptr=1 (non-null)
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "inject consent with null handle returns null_pointer" {
    const result = wokelangiser_inject_consent(null, 0, 1);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "inject consent with invalid type returns invalid_param" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_inject_consent(handle, 99, 1);
    try testing.expectEqual(@as(c_int, 2), result); // 2 = invalid_param
}

test "check consent without grant returns consent_required" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_check_consent(handle, 0, 12345); // Check OptIn for subject 12345
    try testing.expectEqual(@as(c_int, 5), result); // 5 = consent_required
}

test "consent state transitions" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    // Valid: Pending (0) -> Granted (1)
    const valid1 = wokelangiser_record_consent_transition(handle, 1, 0, 1);
    try testing.expectEqual(@as(c_int, 0), valid1); // ok

    // Valid: Granted (1) -> Active (2)
    const valid2 = wokelangiser_record_consent_transition(handle, 1, 1, 2);
    try testing.expectEqual(@as(c_int, 0), valid2); // ok

    // Valid: Active (2) -> Revoked (3)
    const valid3 = wokelangiser_record_consent_transition(handle, 1, 2, 3);
    try testing.expectEqual(@as(c_int, 0), valid3); // ok

    // Invalid: Pending (0) -> Active (2) — must go through Granted
    const invalid = wokelangiser_record_consent_transition(handle, 1, 0, 2);
    try testing.expectEqual(@as(c_int, 2), invalid); // invalid_param
}

//==============================================================================
// Accessibility Tests
//==============================================================================

test "contrast ratio black on white" {
    const ratio = wokelangiser_contrast_ratio(0x000000, 0xFFFFFF);
    try testing.expect(ratio >= 2000); // ~21:1
}

test "contrast ratio same colour" {
    const ratio = wokelangiser_contrast_ratio(0x808080, 0x808080);
    try testing.expect(ratio <= 110); // ~1:1
}

test "check accessibility with null handle" {
    const result = wokelangiser_check_accessibility(null, 1, 1);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "check accessibility with null element" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_check_accessibility(handle, 0, 1);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

//==============================================================================
// I18n Tests
//==============================================================================

test "extract strings with null handle" {
    const result = wokelangiser_extract_strings(null, 1, 1);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "format locale with invalid hook type" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_format_locale(handle, 99, 1, 1);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

//==============================================================================
// Cultural Sensitivity Tests
//==============================================================================

test "check sensitivity with null content" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_check_sensitivity(handle, 0, 0);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "check sensitivity with invalid context type" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_check_sensitivity(handle, 1, 99);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const str = wokelangiser_get_string(handle);
    defer if (str) |s| wokelangiser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = wokelangiser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = wokelangiser_inject_consent(null, 0, 0);

    const err = wokelangiser_last_error();
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
    const ver = wokelangiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = wokelangiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(h1);

    const h2 = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(h2);

    try testing.expect(h1 != h2);
}

test "free null is safe" {
    wokelangiser_free(null); // Should not crash
}
