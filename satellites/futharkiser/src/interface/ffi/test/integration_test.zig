// Futharkiser Integration Tests
//
// Verify that the Zig FFI correctly implements the Idris2 ABI declared in
// src/interface/abi/Foreign.idr. These tests exercise the full lifecycle:
// init, buffer allocation, compilation (stubbed), execution (stubbed), and cleanup.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");
const testing = std.testing;

// ---------------------------------------------------------------------------
// Import FFI functions (linked from libfutharkiser)
// ---------------------------------------------------------------------------

extern fn futharkiser_init(backend_id: u32) ?*anyopaque;
extern fn futharkiser_free(handle: ?*anyopaque) void;
extern fn futharkiser_compile(handle: ?*anyopaque, source: [*:0]const u8, backend: u32) ?*anyopaque;
extern fn futharkiser_compile_file(handle: ?*anyopaque, path: [*:0]const u8, backend: u32) ?*anyopaque;
extern fn futharkiser_execute(handle: ?*anyopaque, kernel: ?*anyopaque, entry: [*:0]const u8) c_int;
extern fn futharkiser_alloc_buffer(handle: ?*anyopaque, elem_bytes: u32, num_elements: u64, space: u32) ?*anyopaque;
extern fn futharkiser_free_buffer(handle: ?*anyopaque, buffer: ?*anyopaque) void;
extern fn futharkiser_transfer(handle: ?*anyopaque, src: ?*anyopaque, dst: ?*anyopaque, flags: u64) c_int;
extern fn futharkiser_backend_available(backend_id: u32) u32;
extern fn futharkiser_last_error() ?[*:0]const u8;
extern fn futharkiser_free_string(str: ?[*:0]const u8) void;
extern fn futharkiser_version() [*:0]const u8;
extern fn futharkiser_build_info() [*:0]const u8;
extern fn futharkiser_is_initialized(handle: ?*anyopaque) u32;

// ===========================================================================
// Lifecycle Tests
// ===========================================================================

test "create and destroy handle with sequential backend" {
    const handle = futharkiser_init(3); // sequential
    try testing.expect(handle != null);
    defer futharkiser_free(handle);
}

test "create and destroy handle with multicore backend" {
    const handle = futharkiser_init(2); // multicore
    try testing.expect(handle != null);
    defer futharkiser_free(handle);
}

test "handle is initialized after init" {
    const handle = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(handle);

    const initialized = futharkiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = futharkiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

test "free null handle is safe" {
    futharkiser_free(null);
}

// ===========================================================================
// Backend Query Tests
// ===========================================================================

test "sequential backend is always available" {
    try testing.expectEqual(@as(u32, 1), futharkiser_backend_available(3));
}

test "multicore backend is always available" {
    try testing.expectEqual(@as(u32, 1), futharkiser_backend_available(2));
}

test "invalid backend id returns unavailable" {
    try testing.expectEqual(@as(u32, 0), futharkiser_backend_available(255));
}

// ===========================================================================
// Compilation Tests (stubs — verify error handling)
// ===========================================================================

test "compile with null handle returns null" {
    const kernel = futharkiser_compile(null, "entry main = 42", 3);
    try testing.expect(kernel == null);
}

test "compile file with null handle returns null" {
    const kernel = futharkiser_compile_file(null, "/nonexistent.fut", 3);
    try testing.expect(kernel == null);
}

// ===========================================================================
// Execution Tests (stubs — verify error handling)
// ===========================================================================

test "execute with null library handle returns error" {
    const result = futharkiser_execute(null, null, "main");
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "execute with valid handle but null kernel returns error" {
    const handle = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(handle);

    const result = futharkiser_execute(handle, null, "main");
    // Should return an error since kernel is null (implementation-specific)
    try testing.expect(result != 0);
}

// ===========================================================================
// Buffer Management Tests
// ===========================================================================

test "allocate host buffer" {
    const handle = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(handle);

    // Allocate 1024 f32 elements on host (space=1)
    const buf = futharkiser_alloc_buffer(handle, 4, 1024, 1);
    try testing.expect(buf != null);

    if (buf) |b| {
        futharkiser_free_buffer(handle, b);
    }
}

test "allocate device buffer" {
    const handle = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(handle);

    // Allocate 512 f64 elements on device (space=0)
    const buf = futharkiser_alloc_buffer(handle, 8, 512, 0);
    try testing.expect(buf != null);

    if (buf) |b| {
        futharkiser_free_buffer(handle, b);
    }
}

test "allocate buffer with null handle returns null" {
    const buf = futharkiser_alloc_buffer(null, 4, 1024, 1);
    try testing.expect(buf == null);
}

test "free null buffer is safe" {
    const handle = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(handle);

    futharkiser_free_buffer(handle, null);
}

// ===========================================================================
// Memory Transfer Tests
// ===========================================================================

test "transfer with null handle returns error" {
    const result = futharkiser_transfer(null, null, null, 0);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

// ===========================================================================
// Error Handling Tests
// ===========================================================================

test "last error after null handle operation" {
    _ = futharkiser_execute(null, null, "main");

    const err = futharkiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
        futharkiser_free_string(e);
    }
}

// ===========================================================================
// Version Tests
// ===========================================================================

test "version string is non-empty" {
    const ver = futharkiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string contains a dot (semver)" {
    const ver = futharkiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info is non-empty" {
    const info = futharkiser_build_info();
    const info_str = std.mem.span(info);
    try testing.expect(info_str.len > 0);
}

// ===========================================================================
// Memory Safety Tests
// ===========================================================================

test "multiple handles are independent" {
    const h1 = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(h1);

    const h2 = futharkiser_init(2) orelse return error.InitFailed;
    defer futharkiser_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    try testing.expectEqual(@as(u32, 1), futharkiser_is_initialized(h1));
    try testing.expectEqual(@as(u32, 1), futharkiser_is_initialized(h2));
}
