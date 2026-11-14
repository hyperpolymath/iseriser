// Anvomidaviser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr
// All types and layouts must match the Idris2 ABI definitions.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "Anvomidaviser built with Zig " ++ @import("builtin").zig_version_string;

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

/// Result codes (must match Idris2 Result type)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    rule_violation = 5,
};

/// Library handle. Opaque to C (passed as a pointer); fields are private to
/// this module. A concrete struct (not Zig `opaque`) so internal state can be
/// stored and accessed here.
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the anvomidaviser scoring engine
/// Returns a handle, or null on failure
export fn anvomidaviser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    // Initialize handle
    handle.* = .{
        .allocator = allocator,
        .initialized = true,
    };

    clearError();
    return handle;
}

/// Free the library handle
export fn anvomidaviser_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    // Clean up resources
    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// ISU Element Parsing
//==============================================================================

/// Parse an ISU element code string (e.g. "3Lz", "CCoSp4", "StSq3")
export fn anvomidaviser_parse_element(code: ?[*:0]const u8) ?*Handle {
    const c = code orelse {
        setError("Null element code");
        return null;
    };

    _ = c;

    // TODO: Implement ISU element code parsing
    // Parse jump codes (e.g. 3Lz, 4T, 2A), spin codes (e.g. CCoSp4),
    // step sequences (e.g. StSq3), and lifts
    setError("Element parsing not yet implemented");
    return null;
}

/// Parse a combination element (e.g. "3Lz+3T", "3F+2T+2Lo")
export fn anvomidaviser_parse_combination(code: ?[*:0]const u8) ?*Handle {
    const c = code orelse {
        setError("Null combination code");
        return null;
    };

    _ = c;

    // TODO: Implement combination element parsing
    setError("Combination parsing not yet implemented");
    return null;
}

/// Parse a full ISU protocol (XML or IJS format)
export fn anvomidaviser_parse_protocol(
    buffer: ?[*]const u8,
    len: u32,
) Result {
    const buf = buffer orelse {
        setError("Null buffer");
        return .null_pointer;
    };

    const data = buf[0..len];
    _ = data;

    // TODO: Implement ISU protocol parsing (XML/IJS format)
    setError("Protocol parsing not yet implemented");
    return .@"error";
}

//==============================================================================
// Scoring Operations
//==============================================================================

/// Look up the base value for a parsed element
/// Returns the base value in hundredths of a point (e.g. 590 = 5.90)
export fn anvomidaviser_base_value(handle: ?*Handle) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // TODO: Look up base value from ISU Code of Points table
    clearError();
    return 0;
}

/// Calculate the GOE adjustment for an element
export fn anvomidaviser_goe_adjustment(handle: ?*Handle, goe: u32) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    _ = goe;

    // TODO: Calculate GOE adjustment per ISU Communication 2472
    clearError();
    return 0;
}

/// Score a complete program (example operation)
export fn anvomidaviser_score_program(handle: ?*Handle) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 0;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // TODO: Score program (sum base values + GOE adjustments - deductions)
    clearError();
    return 0;
}

/// Process data (generic operation, retained for ABI compatibility)
export fn anvomidaviser_process(handle: ?*Handle, input: u32) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    _ = input;

    clearError();
    return .ok;
}

//==============================================================================
// Rule Validation
//==============================================================================

/// Validate a program against ISU technical rules
export fn anvomidaviser_validate_program(handle: ?*Handle) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 2; // error
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 2;
    }

    // TODO: Validate against ISU technical rules
    clearError();
    return 0; // valid
}

/// Check for Zayak rule violations (repeated jump restriction)
export fn anvomidaviser_check_zayak(handle: ?*Handle) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 2;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 2;
    }

    // TODO: Check Zayak rule — triple/quad jumps may only be repeated once,
    // and one occurrence must be in combination
    clearError();
    return 0; // no violation
}

/// Check element count requirements for short/free program
export fn anvomidaviser_check_element_count(handle: ?*Handle, program_type: u32) u32 {
    const h = handle orelse {
        setError("Null handle");
        return 2;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return 2;
    }

    _ = program_type;

    // TODO: Verify element count per ISU rules
    // Short program: 7 elements (singles/pairs), 7 elements (ice dance)
    // Free skate: max 12 elements (singles), 11 (pairs)
    clearError();
    return 0;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (e.g. formatted score sheet)
/// Caller must free the returned string
export fn anvomidaviser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "Anvomidaviser score pending") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn anvomidaviser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;

    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Anvomidav Codegen
//==============================================================================

/// Generate Anvomidav formal program description from parsed elements
export fn anvomidaviser_generate_anvomidav(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    // TODO: Generate Anvomidav source from parsed ISU elements
    setError("Anvomidav codegen not yet implemented");
    return null;
}

//==============================================================================
// Array/Buffer Operations
//==============================================================================

/// Process an array of data (e.g. batch element parsing)
export fn anvomidaviser_process_array(
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
export fn anvomidaviser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn anvomidaviser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn anvomidaviser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Callback Support
//==============================================================================

/// Callback function type (C ABI)
pub const Callback = *const fn (u64, u32) callconv(.C) u32;

/// Register a callback for scoring progress
export fn anvomidaviser_register_callback(
    handle: ?*Handle,
    callback: ?Callback,
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
export fn anvomidaviser_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = anvomidaviser_init() orelse return error.InitFailed;
    defer anvomidaviser_free(handle);

    try std.testing.expect(anvomidaviser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = anvomidaviser_process(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = anvomidaviser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = anvomidaviser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
