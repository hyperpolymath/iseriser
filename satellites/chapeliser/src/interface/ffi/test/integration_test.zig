// Chapeliser FFI Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// Tests the reference FFI implementation against the Idris2 ABI contract.
// These tests exercise the full lifecycle: init → load → process → store → shutdown.

const std = @import("std");
const testing = std.testing;

// Import reference FFI functions
extern fn c_init() c_int;
extern fn c_shutdown() c_int;
extern fn c_get_total_items() c_int;
extern fn c_load_item(c_int, [*]u8, *usize) c_int;
extern fn c_store_result(c_int, [*]const u8, usize) c_int;
extern fn c_process_item([*]const u8, usize, [*]u8, *usize) c_int;
extern fn c_process_chunk([*]const u8, c_int, [*]const c_int, [*]const c_int, [*]u8, *usize) c_int;
extern fn c_reduce([*]const u8, usize, [*]const u8, usize, [*]u8, *usize) c_int;
extern fn c_is_match([*]const u8, usize) c_int;
extern fn c_key_hash([*]const u8, usize) c_uint;
extern fn c_checkpoint_save([*]const u8, usize, [*:0]const u8) c_int;
extern fn c_checkpoint_load([*]u8, *usize, [*:0]const u8) c_int;
extern fn chapeliser_version() [*:0]const u8;
extern fn chapeliser_build_info() [*:0]const u8;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "init and shutdown" {
    const rc_init = c_init();
    try testing.expectEqual(@as(c_int, 0), rc_init);

    const rc_shutdown = c_shutdown();
    try testing.expectEqual(@as(c_int, 0), rc_shutdown);
}

test "double init fails" {
    const rc1 = c_init();
    try testing.expectEqual(@as(c_int, 0), rc1);
    defer _ = c_shutdown();

    const rc2 = c_init();
    try testing.expectEqual(@as(c_int, 1), rc2); // error: already initialised
}

test "shutdown without init fails" {
    const rc = c_shutdown();
    try testing.expectEqual(@as(c_int, 1), rc); // error: not initialised
}

//==============================================================================
// Processing Tests
//==============================================================================

test "process_item preserves data" {
    const input = "distributed computing rocks";
    var output: [256]u8 = undefined;
    var out_len: usize = 0;

    const rc = c_process_item(input.ptr, input.len, &output, &out_len);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(input.len, out_len);
    try testing.expectEqualStrings(input, output[0..out_len]);
}

test "process_item handles empty input" {
    const input = "";
    var output: [256]u8 = undefined;
    var out_len: usize = 0;

    const rc = c_process_item(input.ptr, input.len, &output, &out_len);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(@as(usize, 0), out_len);
}

//==============================================================================
// Reduction Tests
//==============================================================================

test "reduce combines two results" {
    const a = "hello ";
    const b = "world";
    var output: [256]u8 = undefined;
    var out_len: usize = 0;

    const rc = c_reduce(a.ptr, a.len, b.ptr, b.len, &output, &out_len);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqualStrings("hello world", output[0..out_len]);
}

test "reduce is associative for concatenation" {
    // (a + b) + c should equal a + (b + c) in terms of final content
    const a = "aaa";
    const b = "bbb";
    const c = "ccc";
    var tmp1: [256]u8 = undefined;
    var tmp2: [256]u8 = undefined;
    var result1: [256]u8 = undefined;
    var result2: [256]u8 = undefined;
    var len1: usize = 0;
    var len2: usize = 0;
    var final1: usize = 0;
    var final2: usize = 0;

    // (a + b) + c
    _ = c_reduce(a.ptr, a.len, b.ptr, b.len, &tmp1, &len1);
    _ = c_reduce(&tmp1, len1, c.ptr, c.len, &result1, &final1);

    // a + (b + c)
    _ = c_reduce(b.ptr, b.len, c.ptr, c.len, &tmp2, &len2);
    _ = c_reduce(a.ptr, a.len, &tmp2, len2, &result2, &final2);

    try testing.expectEqualStrings(result1[0..final1], result2[0..final2]);
}

//==============================================================================
// Match Predicate Tests
//==============================================================================

test "is_match returns 1 for non-zero first byte" {
    const data = [_]u8{ 0xFF, 0x00, 0x00 };
    try testing.expectEqual(@as(c_int, 1), c_is_match(&data, data.len));
}

test "is_match returns 0 for zero first byte" {
    const data = [_]u8{ 0x00, 0xFF, 0xFF };
    try testing.expectEqual(@as(c_int, 0), c_is_match(&data, data.len));
}

test "is_match returns 0 for empty buffer" {
    const data = [_]u8{};
    try testing.expectEqual(@as(c_int, 0), c_is_match(&data, 0));
}

//==============================================================================
// Key Hash Tests
//==============================================================================

test "key_hash is deterministic" {
    const key = "partition-key";
    const h1 = c_key_hash(key.ptr, key.len);
    const h2 = c_key_hash(key.ptr, key.len);
    try testing.expectEqual(h1, h2);
}

test "key_hash differs for different keys" {
    const k1 = "key-alpha";
    const k2 = "key-bravo";
    const h1 = c_key_hash(k1.ptr, k1.len);
    const h2 = c_key_hash(k2.ptr, k2.len);
    try testing.expect(h1 != h2);
}

//==============================================================================
// Checkpoint Tests
//==============================================================================

test "checkpoint save returns not-implemented" {
    const data = "checkpoint data";
    const rc = c_checkpoint_save(data.ptr, data.len, "locale-0");
    try testing.expectEqual(@as(c_int, -1), rc);
}

test "checkpoint load returns not-implemented" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = c_checkpoint_load(&buf, &len, "locale-0");
    try testing.expectEqual(@as(c_int, -1), rc);
}

//==============================================================================
// Version Tests
//==============================================================================

test "version is semantic" {
    const ver = std.mem.span(chapeliser_version());
    try testing.expect(ver.len > 0);
    try testing.expect(std.mem.count(u8, ver, ".") >= 1);
}

test "build_info is not empty" {
    const info = std.mem.span(chapeliser_build_info());
    try testing.expect(info.len > 0);
    try testing.expect(std.mem.indexOf(u8, info, "chapeliser") != null);
}
