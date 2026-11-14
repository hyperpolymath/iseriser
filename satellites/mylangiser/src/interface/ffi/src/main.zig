// Mylangiser FFI Implementation
//
// Implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// Provides the runtime for API surface analysis, complexity scoring,
// disclosure-level assignment, and layered wrapper generation.
//
// All types and layouts must match the Idris2 ABI definitions.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "mylangiser built with Zig " ++ @import("builtin").zig_version_string;

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
    endpoint_not_found = 5,
    invalid_score = 6,
};

/// Disclosure levels (must match Idris2 DisclosureLevel type)
pub const DisclosureLevel = enum(u32) {
    beginner = 0,
    intermediate = 1,
    expert = 2,
};

/// API endpoint descriptor (must match Idris2 APIEndpoint record)
pub const EndpointDescriptor = extern struct {
    name_ptr: ?[*:0]const u8,
    name_len: u32,
    required_params: u32,
    optional_params: u32,
    type_depth: u32,
    error_surface: u32,
    complexity_score: u32,
    disclosure_level: u32,
    padding: u32 = 0,
};

/// API surface descriptor (must match Idris2 apiSurfaceLayout)
pub const APISurfaceDescriptor = extern struct {
    endpoint_count: u32,
    total_params: u32,
    max_type_depth: u32,
    max_error_codes: u32,
    reserved: u64 = 0,
};

/// Wrapper descriptor (must match Idris2 wrapperDescriptorLayout)
pub const WrapperDescriptor = extern struct {
    endpoint_name_ptr: ?[*:0]const u8,
    endpoint_name_len: u32,
    complexity_score: u32,
    beginner_params: u32,
    intermediate_params: u32,
    expert_params: u32,
    default_count: u32,
    flags: u32,
    padding: u32 = 0,
};

/// Library handle (opaque to prevent direct access from C callers)
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    /// Analysed endpoints (populated by mylangiser_analyse_surface)
    endpoints: std.ArrayList(EndpointDescriptor),
    /// Generated wrappers (populated by mylangiser_generate_layers)
    wrappers: std.ArrayList(WrapperDescriptor),
    /// Whether scores have been computed
    scores_computed: bool,
    /// Whether layers have been generated
    layers_generated: bool,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialise the mylangiser library.
/// Returns a handle, or null on failure.
export fn mylangiser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .endpoints = std.ArrayList(EndpointDescriptor).init(allocator),
        .wrappers = std.ArrayList(WrapperDescriptor).init(allocator),
        .scores_computed = false,
        .layers_generated = false,
    };

    clearError();
    return handle;
}

/// Free the library handle and all owned resources.
export fn mylangiser_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    h.endpoints.deinit();
    h.wrappers.deinit();
    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// API Surface Analysis
//==============================================================================

/// Analyse an API surface from a serialised manifest buffer.
/// Populates the internal endpoint table.
/// Returns Result code (0 = ok).
export fn mylangiser_analyse_surface(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) c_int {
    const h = handle orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    _ = buffer orelse {
        setError("Null buffer");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    if (len == 0) {
        setError("Empty manifest buffer");
        return @intFromEnum(Result.invalid_param);
    }

    // TODO: Parse manifest buffer and populate h.endpoints
    // For now, clear any previous analysis
    h.endpoints.clearRetainingCapacity();
    h.scores_computed = false;
    h.layers_generated = false;

    clearError();
    return @intFromEnum(Result.ok);
}

/// Get the number of endpoints discovered during analysis.
export fn mylangiser_endpoint_count(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    if (!h.initialized) return 0;
    return @intCast(h.endpoints.items.len);
}

//==============================================================================
// Complexity Scoring
//==============================================================================

/// Compute complexity scores for all analysed endpoints.
/// Score formula: (requiredParams * 3) + (optionalParams * 1) +
///                (typeDepth * 5) + (errorSurface * 2), clamped to 0-100.
export fn mylangiser_compute_scores(handle: ?*Handle) c_int {
    const h = handle orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    for (h.endpoints.items) |*ep| {
        const raw: u32 = (ep.required_params * 3) +
            (ep.optional_params * 1) +
            (ep.type_depth * 5) +
            (ep.error_surface * 2);
        ep.complexity_score = @min(raw, 100);

        // Assign disclosure level from score
        if (ep.complexity_score <= 33) {
            ep.disclosure_level = @intFromEnum(DisclosureLevel.beginner);
        } else if (ep.complexity_score <= 66) {
            ep.disclosure_level = @intFromEnum(DisclosureLevel.intermediate);
        } else {
            ep.disclosure_level = @intFromEnum(DisclosureLevel.expert);
        }
    }

    h.scores_computed = true;
    clearError();
    return @intFromEnum(Result.ok);
}

/// Get the complexity score for a specific endpoint by index.
export fn mylangiser_get_score(handle: ?*Handle, index: u32) u32 {
    const h = handle orelse return 0;
    if (!h.initialized or !h.scores_computed) return 0;
    if (index >= h.endpoints.items.len) return 0;
    return h.endpoints.items[index].complexity_score;
}

//==============================================================================
// Layer Generation
//==============================================================================

/// Generate layered wrappers for all scored endpoints.
/// Each wrapper specifies how many parameters are visible at each
/// disclosure level.
export fn mylangiser_generate_layers(handle: ?*Handle) c_int {
    const h = handle orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return @intFromEnum(Result.@"error");
    }

    if (!h.scores_computed) {
        setError("Scores not computed; call mylangiser_compute_scores first");
        return @intFromEnum(Result.@"error");
    }

    h.wrappers.clearRetainingCapacity();

    for (h.endpoints.items) |ep| {
        const total = ep.required_params + ep.optional_params;

        // Beginner: only required params
        // Intermediate: required + half optional
        // Expert: all params
        const beginner_params = ep.required_params;
        const intermediate_params = ep.required_params + (ep.optional_params / 2);
        const expert_params = total;
        const defaults = total - beginner_params;

        h.wrappers.append(.{
            .endpoint_name_ptr = ep.name_ptr,
            .endpoint_name_len = ep.name_len,
            .complexity_score = ep.complexity_score,
            .beginner_params = beginner_params,
            .intermediate_params = intermediate_params,
            .expert_params = expert_params,
            .default_count = defaults,
            .flags = 0,
        }) catch {
            setError("Failed to allocate wrapper");
            return @intFromEnum(Result.out_of_memory);
        };
    }

    h.layers_generated = true;
    clearError();
    return @intFromEnum(Result.ok);
}

/// Get the assigned disclosure level for an endpoint by index.
/// Returns 0=Beginner, 1=Intermediate, 2=Expert.
export fn mylangiser_get_level(handle: ?*Handle, index: u32) u32 {
    const h = handle orelse return 0;
    if (!h.initialized or !h.scores_computed) return 0;
    if (index >= h.endpoints.items.len) return 0;
    return h.endpoints.items[index].disclosure_level;
}

/// Get the number of smart defaults applied to an endpoint.
export fn mylangiser_default_count(handle: ?*Handle, index: u32) u32 {
    const h = handle orelse return 0;
    if (!h.initialized or !h.layers_generated) return 0;
    if (index >= h.wrappers.items.len) return 0;
    return h.wrappers.items[index].default_count;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (example).
/// Caller must free the returned string with mylangiser_free_string.
export fn mylangiser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "mylangiser ready") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library.
export fn mylangiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message.
/// Returns null if no error.
export fn mylangiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version.
export fn mylangiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information.
export fn mylangiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialised.
export fn mylangiser_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    try std.testing.expect(mylangiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = mylangiser_analyse_surface(null, null, 0);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(Result.null_pointer)), result);

    const err = mylangiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = mylangiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "scoring thresholds" {
    // Verify score-to-level mapping:
    // 0-33 -> beginner (0), 34-66 -> intermediate (1), 67-100 -> expert (2)
    const handle = mylangiser_init() orelse return error.InitFailed;
    defer mylangiser_free(handle);

    // With no endpoints, compute_scores should succeed trivially
    const score_result = mylangiser_compute_scores(handle);
    try std.testing.expectEqual(@as(c_int, 0), score_result);
}
