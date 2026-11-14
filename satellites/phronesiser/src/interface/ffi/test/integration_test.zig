// Phronesiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI
// for the Phronesiser ethical constraint engine.

const std = @import("std");
const testing = std.testing;

// Import FFI functions (phronesiser constraint engine API)
extern fn phronesiser_init() ?*anyopaque;
extern fn phronesiser_free(?*anyopaque) void;
extern fn phronesiser_add_constraint(?*anyopaque, u32, u32, u32, u32) c_int;
extern fn phronesiser_remove_constraint(?*anyopaque, u32) c_int;
extern fn phronesiser_validate_constraints(?*anyopaque) c_int;
extern fn phronesiser_evaluate(?*anyopaque, u32, ?*AuditResultStruct) c_int;
extern fn phronesiser_evaluate_batch(?*anyopaque, ?[*]const u32, u32, ?[*]AuditResultStruct) c_int;
extern fn phronesiser_audit_count(?*anyopaque) u32;
extern fn phronesiser_audit_get(?*anyopaque, u32, ?*AuditResultStruct) c_int;
extern fn phronesiser_audit_clear(?*anyopaque) void;
extern fn phronesiser_constraint_count(?*anyopaque) u32;
extern fn phronesiser_constraint_name(?*anyopaque, u32) ?[*:0]const u8;
extern fn phronesiser_free_string(?[*:0]const u8) void;
extern fn phronesiser_last_error() ?[*:0]const u8;
extern fn phronesiser_version() [*:0]const u8;
extern fn phronesiser_build_info() [*:0]const u8;
extern fn phronesiser_is_initialized(?*anyopaque) u32;

/// AuditResultStruct must match the Idris2 ABI definition (16 bytes)
const AuditResultStruct = extern struct {
    constraint_id: u32,
    decision: u32,
    severity: u32,
    reserved: u32,
};

/// Deontic modality constants
const OBLIGATION: u32 = 0;
const PERMISSION: u32 = 1;
const PROHIBITION: u32 = 2;

/// Harm domain constants
const DOMAIN_PHYSICAL: u32 = 0;
const DOMAIN_PSYCHOLOGICAL: u32 = 1;
const DOMAIN_FINANCIAL: u32 = 2;
const DOMAIN_PRIVACY: u32 = 3;
const DOMAIN_NONE: u32 = 0xFF;

/// Harm severity constants
const SEVERITY_NEGLIGIBLE: u32 = 0;
const SEVERITY_MINOR: u32 = 1;
const SEVERITY_MODERATE: u32 = 2;
const SEVERITY_SEVERE: u32 = 3;
const SEVERITY_CRITICAL: u32 = 4;

/// Audit decision constants
const DECISION_PERMITTED: u32 = 0;
const DECISION_DENIED: u32 = 1;
const DECISION_ESCALATED: u32 = 2;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy engine" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    try testing.expect(handle != null);
}

test "engine is initialized after creation" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const initialized = phronesiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = phronesiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

test "free null is safe" {
    phronesiser_free(null);
}

//==============================================================================
// Constraint Compilation Tests
//==============================================================================

test "add obligation constraint" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_add_constraint(handle, 1, OBLIGATION, DOMAIN_NONE, 0);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(@as(u32, 1), phronesiser_constraint_count(handle));
}

test "add prohibition with harm boundary" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_add_constraint(
        handle,
        1,
        PROHIBITION,
        DOMAIN_PHYSICAL,
        SEVERITY_CRITICAL,
    );
    try testing.expectEqual(@as(c_int, 0), rc);
}

test "add permission constraint" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_add_constraint(handle, 1, PERMISSION, DOMAIN_NONE, 0);
    try testing.expectEqual(@as(c_int, 0), rc);
}

test "reject duplicate constraint ID" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    _ = phronesiser_add_constraint(handle, 1, OBLIGATION, DOMAIN_NONE, 0);
    const rc = phronesiser_add_constraint(handle, 1, PROHIBITION, DOMAIN_NONE, 0);
    try testing.expectEqual(@as(c_int, 6), rc); // constraint_conflict
}

test "reject invalid modality" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_add_constraint(handle, 1, 99, DOMAIN_NONE, 0);
    try testing.expectEqual(@as(c_int, 2), rc); // invalid_param
}

test "remove constraint" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    _ = phronesiser_add_constraint(handle, 1, OBLIGATION, DOMAIN_NONE, 0);
    try testing.expectEqual(@as(u32, 1), phronesiser_constraint_count(handle));

    const rc = phronesiser_remove_constraint(handle, 1);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(@as(u32, 0), phronesiser_constraint_count(handle));
}

test "remove nonexistent constraint fails" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_remove_constraint(handle, 999);
    try testing.expectEqual(@as(c_int, 2), rc); // invalid_param
}

test "validate empty constraint set" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_validate_constraints(handle);
    try testing.expectEqual(@as(c_int, 0), rc);
}

test "add constraint with null handle" {
    const rc = phronesiser_add_constraint(null, 1, 0, 0xFF, 0);
    try testing.expectEqual(@as(c_int, 4), rc); // null_pointer
}

//==============================================================================
// Constraint Evaluation Tests
//==============================================================================

test "evaluate with no constraints permits action" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    var result: AuditResultStruct = undefined;
    const rc = phronesiser_evaluate(handle, 42, &result);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(DECISION_PERMITTED, result.decision);
}

test "evaluate with prohibition denies action" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    _ = phronesiser_add_constraint(
        handle,
        1,
        PROHIBITION,
        DOMAIN_PHYSICAL,
        SEVERITY_SEVERE,
    );

    var result: AuditResultStruct = undefined;
    const rc = phronesiser_evaluate(handle, 42, &result);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(DECISION_DENIED, result.decision);
    try testing.expectEqual(@as(u32, 1), result.constraint_id);
    try testing.expectEqual(SEVERITY_SEVERE, result.severity);
}

test "evaluate with permission permits action" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    _ = phronesiser_add_constraint(handle, 1, PERMISSION, DOMAIN_NONE, 0);

    var result: AuditResultStruct = undefined;
    const rc = phronesiser_evaluate(handle, 42, &result);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(DECISION_PERMITTED, result.decision);
}

test "evaluate with null handle fails" {
    var result: AuditResultStruct = undefined;
    const rc = phronesiser_evaluate(null, 42, &result);
    try testing.expectEqual(@as(c_int, 4), rc); // null_pointer
}

test "evaluate with null result pointer fails" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    const rc = phronesiser_evaluate(handle, 42, null);
    try testing.expectEqual(@as(c_int, 4), rc); // null_pointer
}

//==============================================================================
// Audit Trail Tests
//==============================================================================

test "audit trail starts empty" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    try testing.expectEqual(@as(u32, 0), phronesiser_audit_count(handle));
}

test "audit trail records evaluations" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    var result: AuditResultStruct = undefined;
    _ = phronesiser_evaluate(handle, 1, &result);
    _ = phronesiser_evaluate(handle, 2, &result);
    _ = phronesiser_evaluate(handle, 3, &result);

    try testing.expectEqual(@as(u32, 3), phronesiser_audit_count(handle));
}

test "audit trail retrieval by index" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    var result: AuditResultStruct = undefined;
    _ = phronesiser_evaluate(handle, 1, &result);

    var retrieved: AuditResultStruct = undefined;
    const rc = phronesiser_audit_get(handle, 0, &retrieved);
    try testing.expectEqual(@as(c_int, 0), rc);
    try testing.expectEqual(DECISION_PERMITTED, retrieved.decision);
}

test "audit trail out of bounds" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    var retrieved: AuditResultStruct = undefined;
    const rc = phronesiser_audit_get(handle, 0, &retrieved);
    try testing.expectEqual(@as(c_int, 2), rc); // invalid_param
}

test "audit trail clear" {
    const handle = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(handle);

    var result: AuditResultStruct = undefined;
    _ = phronesiser_evaluate(handle, 1, &result);
    try testing.expectEqual(@as(u32, 1), phronesiser_audit_count(handle));

    phronesiser_audit_clear(handle);
    try testing.expectEqual(@as(u32, 0), phronesiser_audit_count(handle));
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = phronesiser_add_constraint(null, 1, 0, 0xFF, 0);

    const err = phronesiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
        phronesiser_free_string(e);
    }
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = phronesiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = phronesiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

test "build info is not empty" {
    const info = phronesiser_build_info();
    const info_str = std.mem.span(info);
    try testing.expect(info_str.len > 0);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple engines are independent" {
    const h1 = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(h1);

    const h2 = phronesiser_init() orelse return error.InitFailed;
    defer phronesiser_free(h2);

    try testing.expect(h1 != h2);

    // Add constraint to h1 only
    _ = phronesiser_add_constraint(h1, 1, PROHIBITION, DOMAIN_PHYSICAL, SEVERITY_CRITICAL);

    // h2 should have no constraints
    try testing.expectEqual(@as(u32, 1), phronesiser_constraint_count(h1));
    try testing.expectEqual(@as(u32, 0), phronesiser_constraint_count(h2));
}
