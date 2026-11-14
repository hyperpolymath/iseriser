// Oblibeniser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for reversible operations, audit trails, and undo stack management.

const std = @import("std");
const testing = std.testing;

// Import FFI functions (linked from liboblibeniser)
extern fn oblibeniser_init() ?*opaque {};
extern fn oblibeniser_free(?*opaque {}) void;
extern fn oblibeniser_is_initialized(?*opaque {}) u32;
extern fn oblibeniser_record_forward(?*opaque {}, u64, u64) u64;
extern fn oblibeniser_finalise_forward(?*opaque {}, u64, u64) c_int;
extern fn oblibeniser_compute_inverse(?*opaque {}, u64) c_int;
extern fn oblibeniser_apply_inverse(?*opaque {}, u64) c_int;
extern fn oblibeniser_verify_inverse(?*opaque {}, u64) c_int;
extern fn oblibeniser_audit_append(?*opaque {}, u64, u64, u64, u32) c_int;
extern fn oblibeniser_audit_verify_chain(?*opaque {}) c_int;
extern fn oblibeniser_audit_query(?*opaque {}, u64) u64;
extern fn oblibeniser_undo_push(?*opaque {}, u64) c_int;
extern fn oblibeniser_undo_pop(?*opaque {}) u64;
extern fn oblibeniser_undo_depth(?*opaque {}) u32;
extern fn oblibeniser_time_travel(?*opaque {}, u64) c_int;
extern fn oblibeniser_get_string(?*opaque {}) ?[*:0]const u8;
extern fn oblibeniser_free_string(?[*:0]const u8) void;
extern fn oblibeniser_last_error() ?[*:0]const u8;
extern fn oblibeniser_version() [*:0]const u8;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const initialized = oblibeniser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = oblibeniser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Operation Recording Tests
//==============================================================================

test "record forward operation" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    try testing.expect(op_id != 0);
}

test "record and finalise forward operation" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    try testing.expect(op_id != 0);

    const result = oblibeniser_finalise_forward(handle, op_id, 0);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "record with null handle returns zero" {
    const op_id = oblibeniser_record_forward(null, 0, 0);
    try testing.expectEqual(@as(u64, 0), op_id);
}

test "multiple operations get unique IDs" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const id1 = oblibeniser_record_forward(handle, 0, 0);
    const id2 = oblibeniser_record_forward(handle, 0, 0);
    const id3 = oblibeniser_record_forward(handle, 0, 0);

    try testing.expect(id1 != id2);
    try testing.expect(id2 != id3);
    try testing.expect(id1 != id3);
}

//==============================================================================
// Inverse Computation Tests
//==============================================================================

test "compute inverse of finalised operation" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    _ = oblibeniser_finalise_forward(handle, op_id, 0);

    const result = oblibeniser_compute_inverse(handle, op_id);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "compute inverse of non-finalised operation fails" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    // Do NOT finalise

    const result = oblibeniser_compute_inverse(handle, op_id);
    try testing.expectEqual(@as(c_int, 5), result); // 5 = not_reversible
}

test "apply inverse after compute" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    _ = oblibeniser_finalise_forward(handle, op_id, 0);
    _ = oblibeniser_compute_inverse(handle, op_id);

    const result = oblibeniser_apply_inverse(handle, op_id);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "apply inverse without compute fails" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const op_id = oblibeniser_record_forward(handle, 0, 0);
    _ = oblibeniser_finalise_forward(handle, op_id, 0);
    // Do NOT compute inverse

    const result = oblibeniser_apply_inverse(handle, op_id);
    try testing.expectEqual(@as(c_int, 7), result); // 7 = inverse_proof_failed
}

//==============================================================================
// Audit Trail Tests
//==============================================================================

test "append audit entries" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const r1 = oblibeniser_audit_append(handle, 1, 0, 0xDEAD, 1);
    try testing.expectEqual(@as(c_int, 0), r1);

    const r2 = oblibeniser_audit_append(handle, 2, 0, 0xBEEF, 1);
    try testing.expectEqual(@as(c_int, 0), r2);
}

test "verify empty audit chain is ok" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const result = oblibeniser_audit_verify_chain(handle);
    try testing.expectEqual(@as(c_int, 0), result);
}

test "verify populated audit chain" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    _ = oblibeniser_audit_append(handle, 1, 0, 0xAA, 1);
    _ = oblibeniser_audit_append(handle, 2, 0, 0xBB, 1);
    _ = oblibeniser_audit_append(handle, 3, 0, 0xCC, 0); // undo operation

    const result = oblibeniser_audit_verify_chain(handle);
    try testing.expectEqual(@as(c_int, 0), result);
}

test "query audit trail by operation" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    _ = oblibeniser_audit_append(handle, 42, 0, 0xAA, 1);
    _ = oblibeniser_audit_append(handle, 99, 0, 0xBB, 1);
    _ = oblibeniser_audit_append(handle, 42, 0, 0xCC, 0);

    const result_ptr = oblibeniser_audit_query(handle, 42);
    try testing.expect(result_ptr != 0); // Should find 2 entries for op 42
}

test "query non-existent operation returns null" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const result_ptr = oblibeniser_audit_query(handle, 999);
    try testing.expectEqual(@as(u64, 0), result_ptr);
}

//==============================================================================
// Undo Stack Tests
//==============================================================================

test "push and pop undo stack" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    _ = oblibeniser_undo_push(handle, 10);
    _ = oblibeniser_undo_push(handle, 20);
    _ = oblibeniser_undo_push(handle, 30);

    try testing.expectEqual(@as(u32, 3), oblibeniser_undo_depth(handle));

    try testing.expectEqual(@as(u64, 30), oblibeniser_undo_pop(handle));
    try testing.expectEqual(@as(u64, 20), oblibeniser_undo_pop(handle));
    try testing.expectEqual(@as(u32, 1), oblibeniser_undo_depth(handle));
}

test "pop empty undo stack returns zero" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const result = oblibeniser_undo_pop(handle);
    try testing.expectEqual(@as(u64, 0), result);
}

test "undo depth with null handle" {
    try testing.expectEqual(@as(u32, 0), oblibeniser_undo_depth(null));
}

//==============================================================================
// String and Error Tests
//==============================================================================

test "get string result" {
    const handle = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(handle);

    const str = oblibeniser_get_string(handle);
    defer if (str) |s| oblibeniser_free_string(s);

    try testing.expect(str != null);
}

test "last error after null handle operation" {
    _ = oblibeniser_compute_inverse(null, 0);

    const err = oblibeniser_last_error();
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
    const ver = oblibeniser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = oblibeniser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(h1);

    const h2 = oblibeniser_init() orelse return error.InitFailed;
    defer oblibeniser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    const id1 = oblibeniser_record_forward(h1, 0, 0);
    const id2 = oblibeniser_record_forward(h2, 0, 0);
    try testing.expect(id1 != 0);
    try testing.expect(id2 != 0);
}

test "free null is safe" {
    oblibeniser_free(null); // Should not crash
}
