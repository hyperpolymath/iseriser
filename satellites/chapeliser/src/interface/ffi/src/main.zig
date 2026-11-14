// Chapeliser FFI Reference Implementation
//
// This module provides a REFERENCE implementation of the Chapeliser FFI —
// the 12 C-ABI functions that the generated Chapel code calls via extern proc.
//
// In production, users implement these functions in their own code (Rust, C, Zig).
// This reference implementation is useful for:
//   1. Testing the generated Chapel code without user code
//   2. Documenting the expected behaviour of each function
//   3. Providing a template users can copy and modify
//
// The generated Zig bridge (codegen/zig.rs output) delegates Chapel's c_* calls
// to the user's workload-specific functions. This file implements those functions
// for a trivial "echo" workload that copies input items to output unchanged.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "chapeliser built with Zig " ++ @import("builtin").zig_version_string;

//==============================================================================
// Result Codes (must match Chapeliser.ABI.Types.Result)
//==============================================================================

pub const Result = enum(c_int) {
    ok = 0,
    err = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    retry_exhausted = 5,
    checkpoint_error = 6,
};

//==============================================================================
// Reference Workload State
//==============================================================================

/// Simple reference state: stores items as byte buffers in memory.
/// A real workload would load from files, databases, network, etc.
const ReferenceState = struct {
    initialized: bool = false,
    items: std.ArrayList([]u8),
    results: std.ArrayList([]u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) ReferenceState {
        return .{
            .initialized = true,
            .items = std.ArrayList([]u8).init(allocator),
            .results = std.ArrayList([]u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *ReferenceState) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit();
        for (self.results.items) |result| self.allocator.free(result);
        self.results.deinit();
        self.initialized = false;
    }
};

var state: ?ReferenceState = null;

//==============================================================================
// Lifecycle — called once on Chapel locale 0
//==============================================================================

/// Initialise the reference workload. Returns 0 on success.
export fn c_init() callconv(.C) c_int {
    if (state != null) return @intFromEnum(Result.err); // already initialised
    state = ReferenceState.init(std.heap.c_allocator);
    return @intFromEnum(Result.ok);
}

/// Shut down the reference workload. Returns 0 on success.
export fn c_shutdown() callconv(.C) c_int {
    if (state) |*s| {
        s.deinit();
        state = null;
        return @intFromEnum(Result.ok);
    }
    return @intFromEnum(Result.err); // not initialised
}

//==============================================================================
// Data I/O — called on Chapel locale 0
//==============================================================================

/// Return the total number of input items.
export fn c_get_total_items() callconv(.C) c_int {
    if (state) |s| {
        return @intCast(s.items.items.len);
    }
    return 0;
}

/// Serialise input item `idx` into `buf`. Set `*len` to bytes written.
export fn c_load_item(idx: c_int, buf: [*]u8, len: *usize) callconv(.C) c_int {
    const s = &(state orelse return @intFromEnum(Result.err));
    const i: usize = @intCast(idx);
    if (i >= s.items.items.len) return @intFromEnum(Result.invalid_param);

    const item = s.items.items[i];
    if (item.len > len.*) return @intFromEnum(Result.out_of_memory);

    @memcpy(buf[0..item.len], item);
    len.* = item.len;
    return @intFromEnum(Result.ok);
}

/// Receive a processed result at index `idx`.
export fn c_store_result(idx: c_int, buf: [*]const u8, len: usize) callconv(.C) c_int {
    const s = &(state orelse return @intFromEnum(Result.err));

    // Copy the result data
    const copy = s.allocator.alloc(u8, len) catch return @intFromEnum(Result.out_of_memory);
    @memcpy(copy, buf[0..len]);

    // Store at the right index, growing if needed
    const i: usize = @intCast(idx);
    while (s.results.items.len <= i) {
        s.results.append(&[_]u8{}) catch return @intFromEnum(Result.out_of_memory);
    }
    // Free old result if any
    if (s.results.items[i].len > 0) s.allocator.free(s.results.items[i]);
    s.results.items[i] = copy;

    return @intFromEnum(Result.ok);
}

//==============================================================================
// Processing — called on any Chapel locale
//==============================================================================

/// Process a single item: for the reference implementation, just echo it back.
export fn c_process_item(
    in_buf: [*]const u8,
    in_len: usize,
    out_buf: [*]u8,
    out_len: *usize,
) callconv(.C) c_int {
    // Echo: copy input to output unchanged
    @memcpy(out_buf[0..in_len], in_buf[0..in_len]);
    out_len.* = in_len;
    return @intFromEnum(Result.ok);
}

/// Process a chunk of items: for reference, process each individually.
export fn c_process_chunk(
    items_buf: [*]const u8,
    item_count: c_int,
    item_offsets: [*]const c_int,
    item_sizes: [*]const c_int,
    out_buf: [*]u8,
    out_len: *usize,
) callconv(.C) c_int {
    // For chunk processing, just concatenate all items as the "result"
    var offset: usize = 0;
    const count: usize = @intCast(item_count);
    for (0..count) |i| {
        const item_off: usize = @intCast(item_offsets[i]);
        const item_sz: usize = @intCast(item_sizes[i]);
        @memcpy(out_buf[offset .. offset + item_sz], items_buf[item_off .. item_off + item_sz]);
        offset += item_sz;
    }
    out_len.* = offset;
    return @intFromEnum(Result.ok);
}

//==============================================================================
// Reduction — for reduce/tree-reduce gather
//==============================================================================

/// Combine two results: for reference, concatenate them.
export fn c_reduce(
    a_buf: [*]const u8,
    a_len: usize,
    b_buf: [*]const u8,
    b_len: usize,
    out_buf: [*]u8,
    out_len: *usize,
) callconv(.C) c_int {
    @memcpy(out_buf[0..a_len], a_buf[0..a_len]);
    @memcpy(out_buf[a_len .. a_len + b_len], b_buf[0..b_len]);
    out_len.* = a_len + b_len;
    return @intFromEnum(Result.ok);
}

//==============================================================================
// Match Predicate — for 'first' gather
//==============================================================================

/// Check if a result matches: for reference, match if first byte is non-zero.
export fn c_is_match(buf: [*]const u8, len: usize) callconv(.C) c_int {
    if (len == 0) return 0;
    return if (buf[0] != 0) 1 else 0;
}

//==============================================================================
// Key Hash — for keyed partition
//==============================================================================

/// Hash an item's key: for reference, use FNV-1a on the first 8 bytes.
export fn c_key_hash(buf: [*]const u8, len: usize) callconv(.C) c_uint {
    const hash_len = @min(len, 8);
    var h: u32 = 2166136261; // FNV offset basis
    for (buf[0..hash_len]) |b| {
        h ^= b;
        h *%= 16777619; // FNV prime
    }
    return h;
}

//==============================================================================
// Checkpoint — optional
//==============================================================================

/// Save checkpoint: reference implementation is a no-op.
export fn c_checkpoint_save(
    _: [*]const u8,
    _: usize,
    _: [*:0]const u8,
) callconv(.C) c_int {
    return -1; // not implemented
}

/// Load checkpoint: reference implementation is a no-op.
export fn c_checkpoint_load(
    _: [*]u8,
    _: *usize,
    _: [*:0]const u8,
) callconv(.C) c_int {
    return -1; // not implemented
}

//==============================================================================
// Version
//==============================================================================

export fn chapeliser_version() callconv(.C) [*:0]const u8 {
    return VERSION.ptr;
}

export fn chapeliser_build_info() callconv(.C) [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const rc_init = c_init();
    try std.testing.expectEqual(@as(c_int, 0), rc_init);
    defer _ = c_shutdown();

    // Double init should fail
    const rc_double = c_init();
    try std.testing.expectEqual(@as(c_int, 1), rc_double);
}

test "process_item echo" {
    const input = "hello chapeliser";
    var output: [256]u8 = undefined;
    var out_len: usize = 0;

    const rc = c_process_item(input.ptr, input.len, &output, &out_len);
    try std.testing.expectEqual(@as(c_int, 0), rc);
    try std.testing.expectEqual(input.len, out_len);
    try std.testing.expectEqualStrings(input, output[0..out_len]);
}

test "reduce concatenates" {
    const a = "foo";
    const b = "bar";
    var output: [256]u8 = undefined;
    var out_len: usize = 0;

    const rc = c_reduce(a.ptr, a.len, b.ptr, b.len, &output, &out_len);
    try std.testing.expectEqual(@as(c_int, 0), rc);
    try std.testing.expectEqualStrings("foobar", output[0..out_len]);
}

test "key_hash deterministic" {
    const data = "testkey1";
    const h1 = c_key_hash(data.ptr, data.len);
    const h2 = c_key_hash(data.ptr, data.len);
    try std.testing.expectEqual(h1, h2);
}

test "is_match" {
    const yes = [_]u8{ 0x42, 0x00 };
    const no = [_]u8{ 0x00, 0x42 };
    try std.testing.expectEqual(@as(c_int, 1), c_is_match(&yes, yes.len));
    try std.testing.expectEqual(@as(c_int, 0), c_is_match(&no, no.len));
}

test "checkpoint not implemented" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    try std.testing.expectEqual(@as(c_int, -1), c_checkpoint_save(&buf, len, "test"));
    try std.testing.expectEqual(@as(c_int, -1), c_checkpoint_load(&buf, &len, "test"));
}

test "version" {
    const ver = std.mem.span(chapeliser_version());
    try std.testing.expectEqualStrings("0.1.0", ver);
}
