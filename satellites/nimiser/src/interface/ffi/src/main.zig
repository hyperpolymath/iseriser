// Nimiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// It bridges between the Rust CLI orchestrator and the Nim-generated C library.
// All types and layouts must match the Idris2 ABI definitions.
//
// The Nim compiler (`nim c --app:lib`) produces C code; this Zig layer provides
// the stable C ABI that the Rust CLI and Idris2 proofs reference.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "nimiser built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/interface/abi/Types.idr)
//==============================================================================

/// Result codes (must match Idris2 Nimiser.ABI.Types.Result)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    compilation_failed = 5,
    template_error = 6,
    macro_error = 7,
};

/// Nim calling conventions (must match Nimiser.ABI.Types.NimCallingConvention)
pub const NimCallingConvention = enum(c_int) {
    cdecl_conv = 0,
    stdcall_conv = 1,
    safecall_conv = 2,
    inline_conv = 3,
    noconv = 4,
};

/// Nim backend targets (must match CBackend.target)
pub const NimBackend = enum(c_int) {
    c = 0,
    cpp = 1,
    objc = 2,
    js = 3,
};

/// Nim optimisation levels (must match CBackend.optimisation)
pub const NimOptLevel = enum(c_int) {
    none = 0,
    speed = 1,
    size = 2,
};

/// Library handle (opaque to prevent direct access)
/// Holds state for the Nimiser code generation session.
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    /// Whether the Nim compiler was found on the system
    nim_available: bool,
    /// Nim compiler path (if found)
    nim_path: ?[]const u8,
    /// Last compilation output (stdout + stderr)
    last_output: ?[]const u8,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the Nimiser library
/// Returns a handle, or null on failure
export fn nimiser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    // Check if Nim compiler is available
    const nim_found = checkNimCompiler();

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .nim_available = nim_found,
        .nim_path = if (nim_found) "nim" else null,
        .last_output = null,
    };

    clearError();
    return handle;
}

/// Free the library handle and all associated resources
export fn nimiser_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    // Clean up owned strings
    if (h.last_output) |output| {
        allocator.free(output);
    }

    h.initialized = false;
    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Nim Compilation Pipeline
//==============================================================================

/// Invoke the Nim compiler on generated source code
/// backend: 0=c, 1=cpp, 2=objc, 3=js
/// optimise: 0=none, 1=speed, 2=size
export fn nimiser_compile(
    handle: ?*Handle,
    nim_source: ?[*:0]const u8,
    backend: u32,
    optimise: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (!h.nim_available) {
        setError("Nim compiler not found on system");
        return .compilation_failed;
    }

    _ = nim_source orelse {
        setError("Null source path");
        return .null_pointer;
    };

    _ = backend;
    _ = optimise;

    // TODO: Invoke nim c --app:lib with appropriate flags
    // For now, return success stub
    clearError();
    return .ok;
}

/// Generate Nim template code from parameters
/// Returns a C string containing Nim source, or null on error
export fn nimiser_gen_template(
    handle: ?*Handle,
    name: ?[*:0]const u8,
    type_params: u32,
    value_params: u32,
    exported: u32,
) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const tmpl_name = if (name) |n| std.mem.span(n) else {
        setError("Null template name");
        return null;
    };

    _ = type_params;
    _ = value_params;
    _ = exported;

    // TODO: Generate actual Nim template source code
    const result_str = std.fmt.allocPrintZ(h.allocator, "template {s}*() = discard", .{tmpl_name}) catch {
        setError("Failed to allocate template string");
        return null;
    };

    clearError();
    return result_str.ptr;
}

/// Generate Nim macro code from parameters
/// Returns a C string containing Nim source, or null on error
export fn nimiser_gen_macro(
    handle: ?*Handle,
    name: ?[*:0]const u8,
    ast_params: u32,
    generates_export: u32,
) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const macro_name = if (name) |n| std.mem.span(n) else {
        setError("Null macro name");
        return null;
    };

    _ = ast_params;
    _ = generates_export;

    // TODO: Generate actual Nim macro source code
    const result_str = std.fmt.allocPrintZ(h.allocator, "macro {s}*() = discard", .{macro_name}) catch {
        setError("Failed to allocate macro string");
        return null;
    };

    clearError();
    return result_str.ptr;
}

//==============================================================================
// Nim AST Inspection
//==============================================================================

/// Dump the compile-time AST of a Nim source file
/// Returns a JSON representation of the AST, or null on error
export fn nimiser_dump_ast(
    handle: ?*Handle,
    nim_source: ?[*:0]const u8,
) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    _ = nim_source orelse {
        setError("Null source path");
        return null;
    };

    // TODO: Invoke `nim dump` or parse Nim AST
    setError("AST dump not yet implemented");
    return null;
}

/// List exported symbols from a Nim-generated C library
export fn nimiser_list_exports(
    handle: ?*Handle,
    library_path: ?[*:0]const u8,
) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    _ = library_path orelse {
        setError("Null library path");
        return null;
    };

    // TODO: Use nm/objdump to list exported symbols
    setError("Export listing not yet implemented");
    return null;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result
/// Caller must free the returned string with nimiser_free_string
export fn nimiser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "nimiser ready") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn nimiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Array/Buffer Operations
//==============================================================================

/// Process an array of data through a Nim-generated function
export fn nimiser_process_array(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const buf = buffer orelse {
        setError("Null buffer");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    const data = buf[0..len];
    _ = data;

    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message
/// Returns null if no error
export fn nimiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn nimiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information (includes Zig version)
export fn nimiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Callback Support
//==============================================================================

/// Callback function type (C ABI) for compilation events
pub const CompileCallback = *const fn (u64, u32) callconv(.C) u32;

/// Register a callback for compilation progress/events
export fn nimiser_register_callback(
    handle: ?*Handle,
    callback: ?CompileCallback,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const cb = callback orelse {
        setError("Null callback");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    _ = cb;

    clearError();
    return .ok;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn nimiser_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

/// Check if Nim compiler is available on the system
export fn nimiser_nim_available() u32 {
    return if (checkNimCompiler()) 1 else 0;
}

/// Get Nim compiler version string
/// Returns null if Nim is not available
export fn nimiser_nim_version() ?[*:0]const u8 {
    // TODO: Run `nim --version` and parse output
    if (!checkNimCompiler()) return null;
    const allocator = std.heap.c_allocator;
    const ver = allocator.dupeZ(u8, "nim (version detection pending)") catch return null;
    return ver.ptr;
}

/// Internal: check if the Nim compiler is available on PATH
fn checkNimCompiler() bool {
    // TODO: Actually check for nim binary
    // For now, assume it might be available
    return false;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    try std.testing.expect(nimiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = nimiser_compile(null, null, 0, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = nimiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = nimiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "template generation" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const tmpl = nimiser_gen_template(handle, "myTemplate", 1, 2, 1);
    try std.testing.expect(tmpl != null);
    if (tmpl) |t| nimiser_free_string(t);
}

test "macro generation" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const mac = nimiser_gen_macro(handle, "myMacro", 1, 1);
    try std.testing.expect(mac != null);
    if (mac) |m| nimiser_free_string(m);
}

test "null template name" {
    const handle = nimiser_init() orelse return error.InitFailed;
    defer nimiser_free(handle);

    const tmpl = nimiser_gen_template(handle, null, 0, 0, 0);
    try std.testing.expect(tmpl == null);
}

test "nim availability check" {
    // Should not crash regardless of whether nim is installed
    _ = nimiser_nim_available();
}

test "result codes match Idris2 ABI" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(Result.ok));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(Result.@"error"));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(Result.invalid_param));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(Result.out_of_memory));
    try std.testing.expectEqual(@as(c_int, 4), @intFromEnum(Result.null_pointer));
    try std.testing.expectEqual(@as(c_int, 5), @intFromEnum(Result.compilation_failed));
    try std.testing.expectEqual(@as(c_int, 6), @intFromEnum(Result.template_error));
    try std.testing.expectEqual(@as(c_int, 7), @intFromEnum(Result.macro_error));
}
