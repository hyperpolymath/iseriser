// Ponyiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for Pony reference capability analysis, subtyping, and sendability.

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn ponyiser_init() ?*anyopaque;
extern fn ponyiser_free(?*anyopaque) void;
extern fn ponyiser_infer_capability(?*anyopaque, u64) u32;
extern fn ponyiser_check_subtyping(?*anyopaque, u32, u32) u32;
extern fn ponyiser_check_sendable(?*anyopaque, u32) u32;
extern fn ponyiser_generate_actor(?*anyopaque, u64, u64, u32) u32;
extern fn ponyiser_generate_behaviour(?*anyopaque, u64, u64, u64, u32) u32;
extern fn ponyiser_generate_message(?*anyopaque, u64, u64, u32, u64, u32) u32;
extern fn ponyiser_get_string(?*anyopaque) ?[*:0]const u8;
extern fn ponyiser_free_string(?[*:0]const u8) void;
extern fn ponyiser_last_error() ?[*:0]const u8;
extern fn ponyiser_version() [*:0]const u8;
extern fn ponyiser_is_initialized(?*anyopaque) u32;

// Capability constants (matching RefCapability enum)
const CAP_ISO: u32 = 0;
const CAP_VAL: u32 = 1;
const CAP_REF: u32 = 2;
const CAP_BOX: u32 = 3;
const CAP_TRN: u32 = 4;
const CAP_TAG: u32 = 5;

// Result constants
const RES_OK: u32 = 0;
const RES_NULL_PTR: u32 = 4;
const RES_INVALID_CAP: u32 = 5;
const RES_SENDABILITY: u32 = 6;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    const initialized = ponyiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = ponyiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Capability Subtyping Tests
//==============================================================================

test "subtyping: reflexive for all capabilities" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // Every capability subtypes itself
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_ISO, CAP_ISO));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_VAL, CAP_VAL));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_REF, CAP_REF));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_BOX, CAP_BOX));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_TRN, CAP_TRN));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_TAG, CAP_TAG));
}

test "subtyping: iso <: trn <: ref <: box (left branch)" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_ISO, CAP_TRN));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_TRN, CAP_REF));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_REF, CAP_BOX));
    // Transitive: iso <: ref, iso <: box
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_ISO, CAP_REF));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_ISO, CAP_BOX));
}

test "subtyping: iso <: val <: box (right branch)" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_ISO, CAP_VAL));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_VAL, CAP_BOX));
}

test "subtyping: everything <: tag" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_ISO, CAP_TAG));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_VAL, CAP_TAG));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_REF, CAP_TAG));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_BOX, CAP_TAG));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_TRN, CAP_TAG));
    try testing.expectEqual(RES_OK, ponyiser_check_subtyping(handle, CAP_TAG, CAP_TAG));
}

test "subtyping: invalid directions are rejected" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // ref is NOT <: val (mutable is not immutable)
    try testing.expect(ponyiser_check_subtyping(handle, CAP_REF, CAP_VAL) != RES_OK);
    // box is NOT <: ref (read-only is not mutable)
    try testing.expect(ponyiser_check_subtyping(handle, CAP_BOX, CAP_REF) != RES_OK);
    // tag is NOT <: anything except tag
    try testing.expect(ponyiser_check_subtyping(handle, CAP_TAG, CAP_ISO) != RES_OK);
    try testing.expect(ponyiser_check_subtyping(handle, CAP_TAG, CAP_VAL) != RES_OK);
    try testing.expect(ponyiser_check_subtyping(handle, CAP_TAG, CAP_REF) != RES_OK);
}

test "subtyping: null handle returns error" {
    const result = ponyiser_check_subtyping(null, CAP_ISO, CAP_VAL);
    try testing.expectEqual(RES_NULL_PTR, result);
}

//==============================================================================
// Sendability Tests
//==============================================================================

test "sendability: iso, val, tag are sendable" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try testing.expectEqual(RES_OK, ponyiser_check_sendable(handle, CAP_ISO));
    try testing.expectEqual(RES_OK, ponyiser_check_sendable(handle, CAP_VAL));
    try testing.expectEqual(RES_OK, ponyiser_check_sendable(handle, CAP_TAG));
}

test "sendability: ref, box, trn are NOT sendable" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    try testing.expectEqual(RES_SENDABILITY, ponyiser_check_sendable(handle, CAP_REF));
    try testing.expectEqual(RES_SENDABILITY, ponyiser_check_sendable(handle, CAP_BOX));
    try testing.expectEqual(RES_SENDABILITY, ponyiser_check_sendable(handle, CAP_TRN));
}

//==============================================================================
// Capability Inference Tests
//==============================================================================

test "infer: written + sent + consumed = iso" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // written(1) + read(2) + sent(4) + consumed(16) = 0x17
    try testing.expectEqual(CAP_ISO, ponyiser_infer_capability(handle, 0x17));
}

test "infer: read-only + sent = val" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // read(2) + sent(4) = 0x06
    try testing.expectEqual(CAP_VAL, ponyiser_infer_capability(handle, 0x06));
}

test "infer: written + not aliased = ref" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // written(1) + read(2) = 0x03
    try testing.expectEqual(CAP_REF, ponyiser_infer_capability(handle, 0x03));
}

test "infer: written + aliased = trn" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // written(1) + read(2) + aliased(8) = 0x0B
    try testing.expectEqual(CAP_TRN, ponyiser_infer_capability(handle, 0x0B));
}

test "infer: read-only + not sent = box" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // read(2) = 0x02
    try testing.expectEqual(CAP_BOX, ponyiser_infer_capability(handle, 0x02));
}

test "infer: no access = tag" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // No flags
    try testing.expectEqual(CAP_TAG, ponyiser_infer_capability(handle, 0x00));
}

//==============================================================================
// Message Generation Tests
//==============================================================================

test "message gen: sendable payload accepted" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // iso payload (sendable)
    try testing.expectEqual(RES_OK, ponyiser_generate_message(handle, 0, 0, CAP_ISO, 0, 0));
    // val payload (sendable)
    try testing.expectEqual(RES_OK, ponyiser_generate_message(handle, 0, 0, CAP_VAL, 0, 0));
    // tag payload (sendable)
    try testing.expectEqual(RES_OK, ponyiser_generate_message(handle, 0, 0, CAP_TAG, 0, 0));
}

test "message gen: non-sendable payload rejected" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    // ref payload (not sendable)
    try testing.expectEqual(RES_SENDABILITY, ponyiser_generate_message(handle, 0, 0, CAP_REF, 0, 0));
    // box payload (not sendable)
    try testing.expectEqual(RES_SENDABILITY, ponyiser_generate_message(handle, 0, 0, CAP_BOX, 0, 0));
    // trn payload (not sendable)
    try testing.expectEqual(RES_SENDABILITY, ponyiser_generate_message(handle, 0, 0, CAP_TRN, 0, 0));
}

//==============================================================================
// String and Version Tests
//==============================================================================

test "get string result" {
    const handle = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(handle);

    const str = ponyiser_get_string(handle);
    defer if (str) |s| ponyiser_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = ponyiser_get_string(null);
    try testing.expect(str == null);
}

test "version string is not empty" {
    const ver = ponyiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = ponyiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = ponyiser_check_subtyping(null, 0, 0);

    const err = ponyiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(h1);

    const h2 = ponyiser_init() orelse return error.InitFailed;
    defer ponyiser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = ponyiser_check_subtyping(h1, CAP_ISO, CAP_VAL);
    _ = ponyiser_check_subtyping(h2, CAP_REF, CAP_BOX);
}

test "free null is safe" {
    ponyiser_free(null); // Should not crash
}
