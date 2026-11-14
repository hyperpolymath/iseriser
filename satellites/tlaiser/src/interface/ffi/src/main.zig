// Tlaiser FFI Implementation
//
// Implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// Provides the state extraction engine, TLA+/PlusCal code generation, and
// TLC model checker process management.
//
// All types and layouts must match the Idris2 ABI definitions in Types.idr
// and Layout.idr exactly.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// ---------------------------------------------------------------------------
// Version information (keep in sync with Cargo.toml)
// ---------------------------------------------------------------------------
const VERSION = "0.1.0";
const BUILD_INFO = "tlaiser built with Zig " ++ @import("builtin").zig_version_string;

// ---------------------------------------------------------------------------
// Thread-local error storage
// ---------------------------------------------------------------------------

/// Thread-local error message for the last failed operation
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error (called on success)
fn clearError() void {
    last_error = null;
}

// ===========================================================================
// Core Types (must match src/interface/abi/Types.idr)
// ===========================================================================

/// Result codes for FFI operations.
/// Integer values must match Tlaiser.ABI.Types.resultToInt exactly.
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    tlc_error = 5,
    spec_syntax_error = 6,
    state_space_exhausted = 7,
};

/// Model check result type codes.
/// Returned by tlaiser_get_result_type after a TLC run.
pub const ResultType = enum(u32) {
    all_properties_hold = 0,
    safety_violation = 1,
    liveness_violation = 2,
    deadlock = 3,
    interrupted = 4,
    not_run = 255,
};

/// Internal state for a TLAiser engine instance.
/// Opaque to callers — accessed only via exported functions.
const EngineState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,

    // State machine extraction results
    state_count: u32,
    transition_count: u32,

    // Generated spec content
    generated_spec: ?[]const u8,

    // TLC results
    result_type: ResultType,
    states_explored: u64,
    trace_length: u32,
    trace_string: ?[]const u8,

    // Safety and liveness property names
    safety_properties: std.ArrayList([]const u8),
    liveness_properties: std.ArrayList([]const u8),
};

// ===========================================================================
// Library Lifecycle
// ===========================================================================

/// Initialize the TLAiser engine.
/// Allocates internal state for state machine extraction and TLC management.
/// Returns a pointer to the engine state, or null on failure.
export fn tlaiser_init() ?*EngineState {
    const allocator = std.heap.c_allocator;

    const state = allocator.create(EngineState) catch {
        setError("Failed to allocate engine state");
        return null;
    };

    state.* = .{
        .allocator = allocator,
        .initialized = true,
        .state_count = 0,
        .transition_count = 0,
        .generated_spec = null,
        .result_type = .not_run,
        .states_explored = 0,
        .trace_length = 0,
        .trace_string = null,
        .safety_properties = std.ArrayList([]const u8).init(allocator),
        .liveness_properties = std.ArrayList([]const u8).init(allocator),
    };

    clearError();
    return state;
}

/// Free the engine handle and all associated resources.
export fn tlaiser_free(handle: ?*EngineState) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    // Free generated spec content
    if (h.generated_spec) |spec| {
        allocator.free(spec);
    }

    // Free trace string
    if (h.trace_string) |trace| {
        allocator.free(trace);
    }

    // Free property lists
    h.safety_properties.deinit();
    h.liveness_properties.deinit();

    h.initialized = false;
    allocator.destroy(h);
    clearError();
}

// ===========================================================================
// State Machine Extraction
// ===========================================================================

/// Extract a state machine from source code at the given path.
/// Parses the source and identifies state/transition patterns.
export fn tlaiser_extract_state_machine(handle: ?*EngineState, source_path: ?[*:0]const u8) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = source_path orelse {
        setError("Null source path");
        return .null_pointer;
    };

    // TODO: Implement actual state machine extraction from source code.
    // For now, set placeholder counts.
    h.state_count = 0;
    h.transition_count = 0;

    clearError();
    return .ok;
}

/// Get the number of states in the most recently extracted state machine.
export fn tlaiser_get_state_count(handle: ?*EngineState) u32 {
    const h = handle orelse return 0;
    return h.state_count;
}

/// Get the number of transitions in the most recently extracted state machine.
export fn tlaiser_get_transition_count(handle: ?*EngineState) u32 {
    const h = handle orelse return 0;
    return h.transition_count;
}

// ===========================================================================
// TLA+ Specification Generation
// ===========================================================================

/// Generate a TLA+ specification from the extracted state machine.
export fn tlaiser_generate_tlaplus(handle: ?*EngineState, output_path: ?[*:0]const u8) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = output_path orelse {
        setError("Null output path");
        return .null_pointer;
    };

    // TODO: Generate TLA+ spec from extracted state machine IR.
    clearError();
    return .ok;
}

/// Generate a PlusCal algorithm from the extracted state machine.
export fn tlaiser_generate_pluscal(handle: ?*EngineState, output_path: ?[*:0]const u8) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = output_path orelse {
        setError("Null output path");
        return .null_pointer;
    };

    // TODO: Generate PlusCal from extracted state machine IR.
    clearError();
    return .ok;
}

/// Add a safety property (invariant) to the generated specification.
export fn tlaiser_add_safety_property(
    handle: ?*EngineState,
    name: ?[*:0]const u8,
    expr: ?[*:0]const u8,
) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    const n = name orelse {
        setError("Null property name");
        return .null_pointer;
    };

    _ = expr orelse {
        setError("Null property expression");
        return .null_pointer;
    };

    h.safety_properties.append(std.mem.span(n)) catch {
        setError("Failed to store safety property");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

/// Add a liveness property to the generated specification.
export fn tlaiser_add_liveness_property(
    handle: ?*EngineState,
    name: ?[*:0]const u8,
    expr: ?[*:0]const u8,
) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    const n = name orelse {
        setError("Null property name");
        return .null_pointer;
    };

    _ = expr orelse {
        setError("Null property expression");
        return .null_pointer;
    };

    h.liveness_properties.append(std.mem.span(n)) catch {
        setError("Failed to store liveness property");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

// ===========================================================================
// TLC Model Checker Execution
// ===========================================================================

/// Run the TLC model checker on the given specification file.
/// Invokes TLC as a subprocess, parses output, and stores results.
export fn tlaiser_run_tlc(
    handle: ?*EngineState,
    spec_path: ?[*:0]const u8,
    num_workers: u32,
    max_states: u64,
) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    _ = spec_path orelse {
        setError("Null spec path");
        return .null_pointer;
    };

    _ = num_workers;
    _ = max_states;

    // TODO: Invoke TLC via subprocess:
    //   java -jar tla2tools.jar -workers <num_workers> <spec_path>
    // Parse stdout/stderr for:
    //   - "Model checking completed. No error has been found." => all_properties_hold
    //   - "Invariant ... is violated." => safety_violation
    //   - "Temporal properties were violated." => liveness_violation
    //   - "Deadlock reached." => deadlock
    // Extract counterexample traces.

    h.result_type = .not_run;
    h.states_explored = 0;
    h.trace_length = 0;

    clearError();
    return .ok;
}

/// Get the model check result type after a TLC run.
export fn tlaiser_get_result_type(handle: ?*EngineState) u32 {
    const h = handle orelse return @intFromEnum(ResultType.not_run);
    return @intFromEnum(h.result_type);
}

/// Get the number of states explored during the last TLC run.
export fn tlaiser_get_states_explored(handle: ?*EngineState) u64 {
    const h = handle orelse return 0;
    return h.states_explored;
}

/// Get the counterexample trace length (0 if no violation found).
export fn tlaiser_get_trace_length(handle: ?*EngineState) u32 {
    const h = handle orelse return 0;
    return h.trace_length;
}

/// Get the counterexample trace as a formatted string.
/// Caller must free the returned string with tlaiser_free_string.
export fn tlaiser_get_trace_string(handle: ?*EngineState) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null engine handle");
        return null;
    };

    const trace = h.trace_string orelse return null;

    const result = h.allocator.dupeZ(u8, trace) catch {
        setError("Failed to allocate trace string");
        return null;
    };

    return result.ptr;
}

// ===========================================================================
// String Operations
// ===========================================================================

/// Get a string result from the engine (e.g., generated spec content).
/// Caller must free the returned string with tlaiser_free_string.
export fn tlaiser_get_string(handle: ?*EngineState) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null engine handle");
        return null;
    };

    if (!h.initialized) {
        setError("Engine not initialized");
        return null;
    }

    const spec = h.generated_spec orelse {
        setError("No generated content available");
        return null;
    };

    const result = h.allocator.dupeZ(u8, spec) catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the TLAiser engine.
export fn tlaiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

// ===========================================================================
// Error Handling
// ===========================================================================

/// Get the last error message.
/// Returns null if no error. Caller must free the returned string.
export fn tlaiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

// ===========================================================================
// Version Information
// ===========================================================================

/// Get the library version string (semantic version)
export fn tlaiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information (compiler, platform, date)
export fn tlaiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

// ===========================================================================
// Callback Support
// ===========================================================================

/// Progress callback type (C ABI).
/// Called during TLC execution to report progress.
/// Arguments: (statesExplored: u64, depth: u32) -> shouldContinue: u32
pub const ProgressCallback = *const fn (u64, u32) callconv(.C) u32;

/// Register a progress callback for TLC model check runs.
export fn tlaiser_register_progress_callback(
    handle: ?*EngineState,
    callback: ?ProgressCallback,
) Result {
    const h = handle orelse {
        setError("Null engine handle");
        return .null_pointer;
    };

    const cb = callback orelse {
        setError("Null callback");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Engine not initialized");
        return .@"error";
    }

    // TODO: Store callback for use during TLC execution
    _ = cb;

    clearError();
    return .ok;
}

// ===========================================================================
// Utility Functions
// ===========================================================================

/// Check if engine handle is initialized and ready for use
export fn tlaiser_is_initialized(handle: ?*EngineState) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

// ===========================================================================
// Tests
// ===========================================================================

test "lifecycle" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    try std.testing.expect(tlaiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = tlaiser_extract_state_machine(null, null);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = tlaiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = tlaiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "state extraction with null path" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    const result = tlaiser_extract_state_machine(handle, null);
    try std.testing.expectEqual(Result.null_pointer, result);
}

test "result type before run" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    const result_type = tlaiser_get_result_type(handle);
    try std.testing.expectEqual(@as(u32, 255), result_type); // not_run
}

test "states explored before run" {
    const handle = tlaiser_init() orelse return error.InitFailed;
    defer tlaiser_free(handle);

    const explored = tlaiser_get_states_explored(handle);
    try std.testing.expectEqual(@as(u64, 0), explored);
}
