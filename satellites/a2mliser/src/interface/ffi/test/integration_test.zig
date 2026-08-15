// a2mliser Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for the a2mliser attestation engine.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn a2mliser_init() ?*opaque {};
extern fn a2mliser_free(?*opaque {}) void;
extern fn a2mliser_hash_sha256(?*opaque {}, ?[*]const u8, u32) c_int;
extern fn a2mliser_hash_blake3(?*opaque {}, ?[*]const u8, u32) c_int;
extern fn a2mliser_sign_ed25519(?*opaque {}, ?[*]const u8, ?[*]const u8, ?[*]u8) c_int;
extern fn a2mliser_verify_ed25519(?*opaque {}, ?[*]const u8, ?[*]const u8, ?[*]const u8) c_int;
extern fn a2mliser_create_envelope(?*opaque {}, ?[*]const u8, u32, u32, u32, ?[*]const u8) ?*anyopaque;
extern fn a2mliser_free_envelope(?*opaque {}, ?*anyopaque) void;
extern fn a2mliser_verify_envelope(?*opaque {}, ?*const anyopaque, ?[*]const u8, u32, ?[*]const u8) c_int;
extern fn a2mliser_chain_extend(?*opaque {}, ?*const anyopaque, ?[*]const u8, u32, ?[*]const u8) ?*anyopaque;
extern fn a2mliser_chain_verify(?*opaque {}, ?*const anyopaque, ?[*]const u8) c_int;
extern fn a2mliser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn a2mliser_free_string(?[*:0]const u8) void;
extern fn a2mliser_last_error() ?[*:0]const u8;
extern fn a2mliser_version() [*:0]const u8;
extern fn a2mliser_is_initialized(?*opaque {}) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    const initialized = a2mliser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = a2mliser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Hashing Tests
//==============================================================================

test "sha256 with valid handle and data" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    var data = [_]u8{ 'h', 'e', 'l', 'l', 'o' };
    const result = a2mliser_hash_sha256(handle, &data, 5);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "blake3 with valid handle and data" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    var data = [_]u8{ 'w', 'o', 'r', 'l', 'd' };
    const result = a2mliser_hash_blake3(handle, &data, 5);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "hash with null handle returns error" {
    const result = a2mliser_hash_sha256(null, null, 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "hash with null input returns error" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    const result = a2mliser_hash_sha256(handle, null, 0);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// Signing Tests
//==============================================================================

test "sign with null handle returns error" {
    const result = a2mliser_sign_ed25519(null, null, null, null);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

test "sign with null key returns invalid_param" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    const result = a2mliser_sign_ed25519(handle, null, null, null);
    try testing.expectEqual(@as(c_int, 2), result); // invalid_param
}

//==============================================================================
// Verification Tests
//==============================================================================

test "verify with null handle returns error" {
    const result = a2mliser_verify_ed25519(null, null, null, null);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

//==============================================================================
// Envelope Tests
//==============================================================================

test "create envelope with valid inputs" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    var doc = [_]u8{ 't', 'e', 's', 't' };
    var key = [_]u8{0} ** 32;

    const envelope = a2mliser_create_envelope(handle, &doc, 4, 1, 0, &key);
    defer if (envelope) |env| a2mliser_free_envelope(handle, env);

    try testing.expect(envelope != null);
}

test "create envelope with null handle returns null" {
    const envelope = a2mliser_create_envelope(null, null, 0, 0, 0, null);
    try testing.expect(envelope == null);
}

//==============================================================================
// Provenance Chain Tests
//==============================================================================

test "chain extend creates root entry" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    var doc = [_]u8{ 'r', 'o', 'o', 't' };
    var key = [_]u8{0} ** 32;

    // null parent = root of chain
    const entry = a2mliser_chain_extend(handle, null, &doc, 4, &key);
    defer if (entry) |e| a2mliser_free_envelope(handle, e);

    try testing.expect(entry != null);
}

test "chain verify with null handle returns error" {
    const result = a2mliser_chain_verify(null, null, null);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(handle);

    const str = a2mliser_get_string(handle);
    defer if (str) |s| a2mliser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = a2mliser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = a2mliser_hash_sha256(null, null, 0);

    const err = a2mliser_last_error();
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
    const ver = a2mliser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = a2mliser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(h1);

    const h2 = a2mliser_init() orelse return error.InitFailed;
    defer a2mliser_free(h2);

    try testing.expect(h1 != h2);
}

test "free null is safe" {
    a2mliser_free(null); // Should not crash
}
