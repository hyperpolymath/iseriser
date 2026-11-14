// Phronesiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// It provides the constraint evaluation engine for Phronesiser's ethical guardrails.
// All types and layouts must match the Idris2 ABI definitions.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "Phronesiser built with Zig " ++ @import("builtin").zig_version_string;

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
    constraint_violation = 5,
    constraint_conflict = 6,
};

/// Deontic modality (must match Idris2 DeonticModality type)
pub const DeonticModality = enum(u32) {
    obligation = 0,
    permission = 1,
    prohibition = 2,
};

/// Harm severity (must match Idris2 HarmSeverity type)
pub const HarmSeverity = enum(u32) {
    negligible = 0,
    minor = 1,
    moderate = 2,
    severe = 3,
    critical = 4,
};

/// Harm domain (must match Idris2 HarmDomain type)
pub const HarmDomain = enum(u32) {
    physical = 0,
    psychological = 1,
    financial = 2,
    privacy = 3,
    reputational = 4,
    environmental = 5,
    none = 0xFF,
};

/// Audit decision outcome (must match Idris2 AuditDecision type)
pub const AuditOutcome = enum(u32) {
    permitted = 0,
    denied = 1,
    escalated = 2,
};

/// C-compatible constraint struct (must match Idris2 ConstraintStruct layout: 16 bytes)
pub const ConstraintStruct = extern struct {
    constraint_id: u32,
    modality: u32,
    harm_domain: u32,
    harm_threshold: u32,
};

/// C-compatible audit result struct (must match Idris2 AuditResultStruct layout: 16 bytes)
pub const AuditResultStruct = extern struct {
    constraint_id: u32,
    decision: u32,
    severity: u32,
    reserved: u32,
};

//==============================================================================
// Internal State
//==============================================================================

/// Maximum number of constraints per engine instance
const MAX_CONSTRAINTS = 1024;

/// Maximum number of audit trail entries
const MAX_AUDIT_ENTRIES = 4096;

/// Phronesiser engine handle (opaque to C callers)
const EngineState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    constraints: std.ArrayList(ConstraintStruct),
    audit_trail: std.ArrayList(AuditResultStruct),
};

//==============================================================================
// Engine Lifecycle
//==============================================================================

/// Initialize the Phronesiser constraint engine.
/// Returns a handle, or null on failure.
export fn phronesiser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const state = allocator.create(EngineState) catch {
        setError("Failed to allocate engine state");
        return null;
    };

    state.* = .{
        .allocator = allocator,
        .initialized = true,
        .constraints = std.ArrayList(ConstraintStruct).init(allocator),
        .audit_trail = std.ArrayList(AuditResultStruct).init(allocator),
    };

    clearError();
    return @ptrCast(state);
}

/// Free the engine handle and release all resources.
export fn phronesiser_free(handle: ?*anyopaque) void {
    const state = getState(handle) orelse return;
    const allocator = state.allocator;

    state.constraints.deinit();
    state.audit_trail.deinit();
    state.initialized = false;

    allocator.destroy(state);
    clearError();
}

//==============================================================================
// Constraint Compilation
//==============================================================================

/// Add an ethical constraint to the engine.
/// Parameters: handle, constraintId, modality, harmDomain, harmThreshold.
/// Returns 0 (ok) on success, error code on failure.
export fn phronesiser_add_constraint(
    handle: ?*anyopaque,
    constraint_id: u32,
    modality: u32,
    harm_domain: u32,
    harm_threshold: u32,
) c_int {
    const state = getState(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return @intFromEnum(Result.@"error");
    }

    // Validate modality
    if (modality > 2) {
        setError("Invalid deontic modality (must be 0=obligation, 1=permission, 2=prohibition)");
        return @intFromEnum(Result.invalid_param);
    }

    // Validate harm domain (0-5 or 0xFF for none)
    if (harm_domain > 5 and harm_domain != 0xFF) {
        setError("Invalid harm domain");
        return @intFromEnum(Result.invalid_param);
    }

    // Validate harm threshold
    if (harm_threshold > 4 and harm_domain != 0xFF) {
        setError("Invalid harm threshold (must be 0-4)");
        return @intFromEnum(Result.invalid_param);
    }

    // Check for contradictions: obligation + prohibition on same ID
    for (state.constraints.items) |existing| {
        if (existing.constraint_id == constraint_id) {
            setError("Duplicate constraint ID");
            return @intFromEnum(Result.constraint_conflict);
        }
    }

    // Enforce capacity limit
    if (state.constraints.items.len >= MAX_CONSTRAINTS) {
        setError("Maximum constraint count exceeded");
        return @intFromEnum(Result.out_of_memory);
    }

    state.constraints.append(.{
        .constraint_id = constraint_id,
        .modality = modality,
        .harm_domain = harm_domain,
        .harm_threshold = harm_threshold,
    }) catch {
        setError("Failed to allocate constraint");
        return @intFromEnum(Result.out_of_memory);
    };

    clearError();
    return @intFromEnum(Result.ok);
}

/// Remove a constraint by ID.
export fn phronesiser_remove_constraint(handle: ?*anyopaque, constraint_id: u32) c_int {
    const state = getState(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return @intFromEnum(Result.@"error");
    }

    // Find and remove the constraint
    for (state.constraints.items, 0..) |item, i| {
        if (item.constraint_id == constraint_id) {
            _ = state.constraints.orderedRemove(i);
            clearError();
            return @intFromEnum(Result.ok);
        }
    }

    setError("Constraint not found");
    return @intFromEnum(Result.invalid_param);
}

/// Validate the constraint set for contradictions.
/// Returns 0 if no contradictions, constraint_conflict if obligations
/// contradict prohibitions.
export fn phronesiser_validate_constraints(handle: ?*anyopaque) c_int {
    const state = getState(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return @intFromEnum(Result.@"error");
    }

    // Check for obligation/prohibition conflicts on overlapping scopes
    // (In a full implementation, this would check semantic scope overlap.
    //  For now, constraints are identified by unique IDs so conflicts
    //  are prevented at add time.)
    clearError();
    return @intFromEnum(Result.ok);
}

//==============================================================================
// Constraint Evaluation
//==============================================================================

/// Evaluate an agent action against the constraint set.
/// Writes result to the provided AuditResultStruct pointer.
/// Returns 0 on success, error code on failure.
export fn phronesiser_evaluate(
    handle: ?*anyopaque,
    action_id: u32,
    result_ptr: ?*AuditResultStruct,
) c_int {
    const state = getState(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };

    const out = result_ptr orelse {
        setError("Null result pointer");
        return @intFromEnum(Result.null_pointer);
    };

    if (!state.initialized) {
        setError("Engine not initialized");
        return @intFromEnum(Result.@"error");
    }

    // Evaluate action against all constraints.
    // Default: permitted (no constraint blocks it).
    var decision: AuditOutcome = .permitted;
    var matching_constraint: u32 = 0;
    var max_severity: u32 = 0;

    for (state.constraints.items) |constraint| {
        // Prohibitions block the action
        if (constraint.modality == @intFromEnum(DeonticModality.prohibition)) {
            decision = .denied;
            matching_constraint = constraint.constraint_id;
            if (constraint.harm_threshold > max_severity) {
                max_severity = constraint.harm_threshold;
            }
        }
    }

    // Write the audit result
    out.* = .{
        .constraint_id = matching_constraint,
        .decision = @intFromEnum(decision),
        .severity = max_severity,
        .reserved = 0,
    };

    // Record in audit trail (if space available)
    if (state.audit_trail.items.len < MAX_AUDIT_ENTRIES) {
        state.audit_trail.append(out.*) catch {};
    }

    _ = action_id;
    clearError();
    return @intFromEnum(Result.ok);
}

/// Batch-evaluate multiple actions.
export fn phronesiser_evaluate_batch(
    handle: ?*anyopaque,
    action_ids: ?[*]const u32,
    count: u32,
    results: ?[*]AuditResultStruct,
) c_int {
    const ids = action_ids orelse {
        setError("Null action IDs pointer");
        return @intFromEnum(Result.null_pointer);
    };
    const outs = results orelse {
        setError("Null results pointer");
        return @intFromEnum(Result.null_pointer);
    };

    for (0..count) |i| {
        const rc = phronesiser_evaluate(handle, ids[i], &outs[i]);
        if (rc != @intFromEnum(Result.ok)) {
            return rc;
        }
    }

    return @intFromEnum(Result.ok);
}

//==============================================================================
// Audit Trail
//==============================================================================

/// Get the number of audit decisions recorded.
export fn phronesiser_audit_count(handle: ?*anyopaque) u32 {
    const state = getState(handle) orelse return 0;
    return @intCast(state.audit_trail.items.len);
}

/// Get an audit decision by index.
export fn phronesiser_audit_get(
    handle: ?*anyopaque,
    index: u32,
    result_ptr: ?*AuditResultStruct,
) c_int {
    const state = getState(handle) orelse {
        setError("Null handle");
        return @intFromEnum(Result.null_pointer);
    };
    const out = result_ptr orelse {
        setError("Null result pointer");
        return @intFromEnum(Result.null_pointer);
    };

    if (index >= state.audit_trail.items.len) {
        setError("Audit trail index out of bounds");
        return @intFromEnum(Result.invalid_param);
    }

    out.* = state.audit_trail.items[index];
    clearError();
    return @intFromEnum(Result.ok);
}

/// Clear the audit trail.
export fn phronesiser_audit_clear(handle: ?*anyopaque) void {
    const state = getState(handle) orelse return;
    state.audit_trail.clearRetainingCapacity();
    clearError();
}

//==============================================================================
// String Operations
//==============================================================================

/// Get constraint name by ID (stub: returns generic name).
export fn phronesiser_constraint_name(handle: ?*anyopaque, constraint_id: u32) ?[*:0]const u8 {
    const state = getState(handle) orelse {
        setError("Null handle");
        return null;
    };

    // Verify constraint exists
    for (state.constraints.items) |c| {
        if (c.constraint_id == constraint_id) {
            const name = std.fmt.allocPrintZ(state.allocator, "constraint-{d}", .{constraint_id}) catch {
                setError("Failed to allocate string");
                return null;
            };
            clearError();
            return name.ptr;
        }
    }

    setError("Constraint not found");
    return null;
}

/// Free a string allocated by the library.
export fn phronesiser_free_string(str: ?[*:0]const u8) void {
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
export fn phronesiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version.
export fn phronesiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information.
export fn phronesiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if engine is initialized.
export fn phronesiser_is_initialized(handle: ?*anyopaque) u32 {
    const state = getState(handle) orelse return 0;
    return if (state.initialized) 1 else 0;
}

/// Get the number of constraints currently loaded.
export fn phronesiser_constraint_count(handle: ?*anyopaque) u32 {
    const state = getState(handle) orelse return 0;
    return @intCast(state.constraints.items.len);
}

//==============================================================================
// Internal Helpers
//==============================================================================

/// Safely cast opaque handle to EngineState pointer.
fn getState(handle: ?*anyopaque) ?*EngineState {
    const ptr = handle orelse return null;
    return @ptrCast(@alignCast(ptr));
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    try std.testing.expect(phronesiser_is_initialized(handle) == 1);
}

test "add and count constraints" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    // Add a prohibition constraint
    const rc = phronesiser_add_constraint(
        handle,
        1, // constraint ID
        @intFromEnum(DeonticModality.prohibition), // modality
        @intFromEnum(HarmDomain.physical), // harm domain
        @intFromEnum(HarmSeverity.critical), // harm threshold
    );
    try std.testing.expectEqual(@as(c_int, 0), rc);
    try std.testing.expectEqual(@as(u32, 1), phronesiser_constraint_count(handle));
}

test "evaluate with prohibition denies action" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    // Add a prohibition
    _ = phronesiser_add_constraint(
        handle,
        1,
        @intFromEnum(DeonticModality.prohibition),
        @intFromEnum(HarmDomain.physical),
        @intFromEnum(HarmSeverity.severe),
    );

    // Evaluate
    var result: AuditResultStruct = undefined;
    const rc = phronesiser_evaluate(handle, 42, &result);
    try std.testing.expectEqual(@as(c_int, 0), rc);
    try std.testing.expectEqual(@as(u32, @intFromEnum(AuditOutcome.denied)), result.decision);
}

test "evaluate with no constraints permits action" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    var result: AuditResultStruct = undefined;
    const rc = phronesiser_evaluate(handle, 42, &result);
    try std.testing.expectEqual(@as(c_int, 0), rc);
    try std.testing.expectEqual(@as(u32, @intFromEnum(AuditOutcome.permitted)), result.decision);
}

test "error handling with null handle" {
    const result = phronesiser_add_constraint(null, 1, 0, 0xFF, 0);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(Result.null_pointer)), result);

    const err = phronesiser_last_error();
    try std.testing.expect(err != null);
}

test "audit trail records decisions" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    try std.testing.expectEqual(@as(u32, 0), phronesiser_audit_count(handle));

    var result: AuditResultStruct = undefined;
    _ = phronesiser_evaluate(handle, 1, &result);
    try std.testing.expectEqual(@as(u32, 1), phronesiser_audit_count(handle));

    phronesiser_audit_clear(handle);
    try std.testing.expectEqual(@as(u32, 0), phronesiser_audit_count(handle));
}

test "version" {
    const ver = phronesiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "remove constraint" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    _ = phronesiser_add_constraint(handle, 1, 0, 0xFF, 0);
    try std.testing.expectEqual(@as(u32, 1), phronesiser_constraint_count(handle));

    const rc = phronesiser_remove_constraint(handle, 1);
    try std.testing.expectEqual(@as(c_int, 0), rc);
    try std.testing.expectEqual(@as(u32, 0), phronesiser_constraint_count(handle));
}
