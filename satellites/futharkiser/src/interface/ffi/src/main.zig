// Futharkiser FFI Implementation
//
// Implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// Bridges between the host application and Futhark-compiled GPU kernels.
// All types and layouts must match the Idris2 ABI definitions in Types.idr.
//
// This layer handles:
//   - Library lifecycle (GPU context creation/teardown)
//   - Futhark source compilation dispatch
//   - GPU buffer allocation and memory space tracking
//   - Kernel execution with buffer arguments
//   - Backend availability detection
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// ---------------------------------------------------------------------------
// Version information (keep in sync with Cargo.toml)
// ---------------------------------------------------------------------------

const VERSION = "0.1.0";
const BUILD_INFO = "Futharkiser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage for the last error message.
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message.
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error.
fn clearError() void {
    last_error = null;
}

// ===========================================================================
// Core Types (must match src/interface/abi/Types.idr)
// ===========================================================================

/// Result codes matching the Idris2 Result type in Types.idr.
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    compilation_failed = 5,
    backend_unavailable = 6,
    shape_mismatch = 7,
};

/// GPU compilation backends matching GPUBackend in Types.idr.
pub const GPUBackend = enum(u32) {
    opencl = 0,
    cuda = 1,
    multicore = 2,
    sequential = 3,
};

/// Memory spaces matching MemorySpace in Types.idr.
pub const MemorySpace = enum(u32) {
    device = 0,
    host = 1,
    shared = 2,
};

/// GPU buffer descriptor matching the layout in Layout.idr (32 bytes, 8-byte aligned).
/// Fields and offsets must agree with gpuBufferDescriptorLayout.
pub const GPUBufferDescriptor = extern struct {
    /// Pointer to the actual buffer data (8 bytes, offset 0)
    data_ptr: u64,
    /// Number of elements in the buffer (8 bytes, offset 8)
    num_elements: u64,
    /// Size in bytes of each element (4 bytes, offset 16)
    element_bytes: u32,
    /// Number of array dimensions / rank (4 bytes, offset 20)
    rank: u32,
    /// Memory space enum value (4 bytes, offset 24)
    space: u32,
    /// Padding for 8-byte struct alignment (4 bytes, offset 28)
    _padding: u32 = 0,
};

// Compile-time layout verification (must match Idris2 Layout.idr)
comptime {
    std.debug.assert(@sizeOf(GPUBufferDescriptor) == 32);
    std.debug.assert(@alignOf(GPUBufferDescriptor) == 8);
    std.debug.assert(@offsetOf(GPUBufferDescriptor, "data_ptr") == 0);
    std.debug.assert(@offsetOf(GPUBufferDescriptor, "num_elements") == 8);
    std.debug.assert(@offsetOf(GPUBufferDescriptor, "element_bytes") == 16);
    std.debug.assert(@offsetOf(GPUBufferDescriptor, "rank") == 20);
    std.debug.assert(@offsetOf(GPUBufferDescriptor, "space") == 24);
}

/// Library handle — holds the Futhark context and GPU state.
/// Opaque to C callers; all access is through exported functions.
const FutharkiserHandle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    backend: GPUBackend,
    // TODO: Add futhark_context pointer once Futhark C API is linked
    // futhark_ctx: ?*futhark_context,
};

// ===========================================================================
// Library Lifecycle
// ===========================================================================

/// Initialise the Futharkiser library with a specific GPU backend.
/// The backend argument selects OpenCL (0), CUDA (1), multicore (2), or sequential (3).
/// Returns an opaque handle, or null on failure.
export fn futharkiser_init(backend_id: u32) ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const backend: GPUBackend = std.meta.intToEnum(GPUBackend, backend_id) catch {
        setError("Invalid GPU backend identifier");
        return null;
    };

    const handle = allocator.create(FutharkiserHandle) catch {
        setError("Failed to allocate Futharkiser handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .backend = backend,
    };

    clearError();
    return @ptrCast(handle);
}

/// Free the Futharkiser library handle and release GPU resources.
export fn futharkiser_free(raw_handle: ?*anyopaque) void {
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse return));
    const allocator = handle.allocator;

    // TODO: Call futhark_context_free when Futhark C API is linked
    handle.initialized = false;
    allocator.destroy(handle);
    clearError();
}

// ===========================================================================
// Futhark Compilation
// ===========================================================================

/// Compile a Futhark source string to a GPU kernel.
/// Returns a kernel handle on success, or null on compilation failure.
export fn futharkiser_compile(
    raw_handle: ?*anyopaque,
    source: [*:0]const u8,
    backend_id: u32,
) ?*anyopaque {
    _ = source;
    _ = backend_id;
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse {
        setError("Null library handle");
        return null;
    }));

    if (!handle.initialized) {
        setError("Library not initialised");
        return null;
    }

    // TODO: Invoke Futhark compiler on source string
    // 1. Write source to temp file
    // 2. Run `futhark <backend> --library <tempfile>`
    // 3. Compile generated C code
    // 4. Return handle to compiled kernel

    setError("Futhark compilation not yet implemented");
    return null;
}

/// Compile a Futhark source file to a GPU kernel.
export fn futharkiser_compile_file(
    raw_handle: ?*anyopaque,
    file_path: [*:0]const u8,
    backend_id: u32,
) ?*anyopaque {
    _ = file_path;
    _ = backend_id;
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse {
        setError("Null library handle");
        return null;
    }));

    if (!handle.initialized) {
        setError("Library not initialised");
        return null;
    }

    // TODO: Invoke Futhark compiler on file path
    setError("Futhark file compilation not yet implemented");
    return null;
}

// ===========================================================================
// GPU Kernel Execution
// ===========================================================================

/// Execute a compiled GPU kernel by entry-point name.
export fn futharkiser_execute(
    raw_handle: ?*anyopaque,
    kernel_handle: ?*anyopaque,
    entry_point: [*:0]const u8,
) Result {
    _ = kernel_handle;
    _ = entry_point;
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse {
        setError("Null library handle");
        return .null_pointer;
    }));

    if (!handle.initialized) {
        setError("Library not initialised");
        return .@"error";
    }

    // TODO: Look up entry point in compiled kernel and execute
    setError("Kernel execution not yet implemented");
    return .@"error";
}

// ===========================================================================
// GPU Buffer Management
// ===========================================================================

/// Allocate a GPU buffer on the specified memory space.
/// Returns a pointer to a GPUBufferDescriptor, or null on failure.
export fn futharkiser_alloc_buffer(
    raw_handle: ?*anyopaque,
    element_bytes: u32,
    num_elements: u64,
    space_id: u32,
) ?*anyopaque {
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse {
        setError("Null library handle");
        return null;
    }));

    if (!handle.initialized) {
        setError("Library not initialised");
        return null;
    }

    const space: MemorySpace = std.meta.intToEnum(MemorySpace, space_id) catch {
        setError("Invalid memory space identifier");
        return null;
    };

    const allocator = handle.allocator;
    const total_bytes = num_elements * element_bytes;

    // Allocate the data buffer
    const data = allocator.alloc(u8, total_bytes) catch {
        setError("Failed to allocate GPU buffer data");
        return null;
    };

    // Allocate the descriptor
    const desc = allocator.create(GPUBufferDescriptor) catch {
        allocator.free(data);
        setError("Failed to allocate buffer descriptor");
        return null;
    };

    desc.* = .{
        .data_ptr = @intFromPtr(data.ptr),
        .num_elements = num_elements,
        .element_bytes = element_bytes,
        .rank = 1, // Default to 1D; caller can update
        .space = @intFromEnum(space),
    };

    clearError();
    return @ptrCast(desc);
}

/// Free a GPU buffer and its descriptor.
export fn futharkiser_free_buffer(
    raw_handle: ?*anyopaque,
    raw_buffer: ?*anyopaque,
) void {
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse return));
    const desc: *GPUBufferDescriptor = @ptrCast(@alignCast(raw_buffer orelse return));
    const allocator = handle.allocator;

    // Free the data
    if (desc.data_ptr != 0) {
        const data_ptr: [*]u8 = @ptrFromInt(desc.data_ptr);
        const total = desc.num_elements * desc.element_bytes;
        allocator.free(data_ptr[0..total]);
    }

    // Free the descriptor
    allocator.destroy(desc);
    clearError();
}

/// Transfer data between memory spaces (host <-> device).
export fn futharkiser_transfer(
    raw_handle: ?*anyopaque,
    src_handle: ?*anyopaque,
    dst_handle: ?*anyopaque,
    flags: u64,
) Result {
    _ = src_handle;
    _ = dst_handle;
    _ = flags;
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse {
        setError("Null library handle");
        return .null_pointer;
    }));

    if (!handle.initialized) {
        setError("Library not initialised");
        return .@"error";
    }

    // TODO: Implement actual GPU memory transfer via Futhark runtime
    // For now, this is a stub that succeeds (host-only buffers need no transfer)
    clearError();
    return .ok;
}

// ===========================================================================
// GPU Backend Query
// ===========================================================================

/// Check if a GPU backend is available on this system.
/// Returns 1 if available, 0 if not.
export fn futharkiser_backend_available(backend_id: u32) u32 {
    const backend = std.meta.intToEnum(GPUBackend, backend_id) catch return 0;

    return switch (backend) {
        // Multicore and sequential are always available
        .multicore, .sequential => 1,
        // TODO: Probe for OpenCL/CUDA runtime libraries
        .opencl => 0,
        .cuda => 0,
    };
}

// ===========================================================================
// Error Handling
// ===========================================================================

/// Get the last error message. Returns null if no error.
/// Caller must free the returned string with futharkiser_free_string.
export fn futharkiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

/// Free a string allocated by the library.
export fn futharkiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

// ===========================================================================
// Version Information
// ===========================================================================

/// Get the library version string.
export fn futharkiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information string (includes Zig version, backend info).
export fn futharkiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

// ===========================================================================
// Utility Functions
// ===========================================================================

/// Check if a handle is initialised. Returns 1 if yes, 0 if no.
export fn futharkiser_is_initialized(raw_handle: ?*anyopaque) u32 {
    const handle: *FutharkiserHandle = @ptrCast(@alignCast(raw_handle orelse return 0));
    return if (handle.initialized) 1 else 0;
}

// ===========================================================================
// Tests
// ===========================================================================

test "lifecycle — init and free" {
    const handle = futharkiser_init(3); // sequential backend
    try std.testing.expect(handle != null);

    if (handle) |h| {
        try std.testing.expect(futharkiser_is_initialized(h) == 1);
        futharkiser_free(h);
    }
}

test "lifecycle — free null is safe" {
    futharkiser_free(null);
}

test "error handling — null handle returns null_pointer" {
    const result = futharkiser_execute(null, null, "main");
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = futharkiser_last_error();
    try std.testing.expect(err != null);
    if (err) |e| futharkiser_free_string(e);
}

test "version — string is non-empty" {
    const ver = futharkiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "backend query — sequential is always available" {
    try std.testing.expectEqual(@as(u32, 1), futharkiser_backend_available(3));
}

test "backend query — multicore is always available" {
    try std.testing.expectEqual(@as(u32, 1), futharkiser_backend_available(2));
}

test "backend query — invalid backend returns 0" {
    try std.testing.expectEqual(@as(u32, 0), futharkiser_backend_available(99));
}

test "buffer — allocate and free" {
    const handle = futharkiser_init(3) orelse return error.InitFailed;
    defer futharkiser_free(handle);

    const buf = futharkiser_alloc_buffer(handle, 4, 1024, 1); // 1024 f32s on host
    try std.testing.expect(buf != null);

    if (buf) |b| {
        futharkiser_free_buffer(handle, b);
    }
}

test "GPU buffer descriptor layout — size and alignment" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(GPUBufferDescriptor));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(GPUBufferDescriptor));
}
