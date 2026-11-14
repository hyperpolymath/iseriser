// SPDX-License-Identifier: MPL-2.0
// Wokelangiser FFI Implementation
//
// Implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// Provides consent injection, accessibility checking, i18n formatting, and
// cultural sensitivity analysis through a C ABI bridge.
//
// All types and layouts must match the Idris2 ABI definitions in Types.idr
// and Layout.idr.
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "wokelangiser built with Zig " ++ @import("builtin").zig_version_string;

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

/// Result codes (must match Idris2 Result type in Types.idr)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    consent_required = 5,
    accessibility_failed = 6,
    i18n_error = 7,
};

/// Consent operation types (must match Idris2 ConsentType in Types.idr)
pub const ConsentType = enum(u32) {
    opt_in = 0,
    opt_out = 1,
    withdraw = 2,
    audit_trail = 3,
};

/// Consent state (must match Idris2 ConsentState in Types.idr)
pub const ConsentState = enum(u32) {
    pending = 0,
    granted = 1,
    active = 2,
    revoked = 3,
};

/// WCAG conformance levels (must match Idris2 WCAGLevel in Types.idr)
pub const WCAGLevel = enum(u32) {
    a = 0,
    aa = 1,
    aaa = 2,
};

/// I18n hook types (must match Idris2 I18nHook variant tags in Types.idr)
pub const I18nHookType = enum(u32) {
    locale = 0,
    rtl = 1,
    pluralise = 2,
    format_spec = 3,
};

/// Cultural context types (must match Idris2 CulturalContext variant tags in Types.idr)
pub const CulturalContextType = enum(u32) {
    cultural = 0,
    terminology = 1,
    naming_convention = 2,
};

/// Consent record (must match Layout.idr consentRecordLayout — 24 bytes, 8-byte aligned)
pub const ConsentRecord = extern struct {
    consent_type: u32,
    state: u32,
    timestamp: u64,
    subject_id: u64,
};

/// Accessibility record (must match Layout.idr accessibilityRecordLayout — 32 bytes, 8-byte aligned)
pub const AccessibilityRecord = extern struct {
    wcag_level: u32,
    focus_order: u32,
    contrast_ratio: u32,
    _padding: u32,
    aria_label_ptr: u64,
    role_ptr: u64,
};

/// I18n record (must match Layout.idr i18nRecordLayout — 24 bytes, 8-byte aligned)
pub const I18nRecord = extern struct {
    hook_type: u32,
    format_kind: u32,
    locale_tag_ptr: u64,
    source_ptr: u64,
};

/// Library handle (opaque to callers)
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    // Consent audit trail (simple in-memory store for now)
    consent_records: std.ArrayList(ConsentRecord),
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the wokelangiser library.
/// Returns a handle, or null on failure.
export fn wokelangiser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .consent_records = std.ArrayList(ConsentRecord).init(allocator),
    };

    clearError();
    return handle;
}

/// Free the wokelangiser library handle and all associated resources.
export fn wokelangiser_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    h.consent_records.deinit();
    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Consent Operations
//==============================================================================

/// Inject a consent point at the specified source location.
/// consent_type: 0=OptIn, 1=OptOut, 2=Withdraw, 3=AuditTrail
/// location_ptr: C string describing the source location (e.g. "src/app.rs:42")
export fn wokelangiser_inject_consent(
    handle: ?*Handle,
    consent_type: u32,
    location_ptr: u64,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (consent_type > 3) {
        setError("Invalid consent type");
        return .invalid_param;
    }

    if (location_ptr == 0) {
        setError("Null location pointer");
        return .null_pointer;
    }

    // TODO: Implement consent point injection into source AST
    // (location_ptr is validated above; injection into the source AST is future work.)

    clearError();
    return .ok;
}

/// Check whether consent has been granted for a specific operation.
/// Returns ok if consent is active, consent_required if not.
export fn wokelangiser_check_consent(
    handle: ?*Handle,
    consent_type: u32,
    subject_id: u64,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Search audit trail for active consent matching type and subject
    for (h.consent_records.items) |record| {
        if (record.subject_id == subject_id and
            record.consent_type == consent_type and
            record.state == @intFromEnum(ConsentState.active))
        {
            clearError();
            return .ok;
        }
    }

    setError("Consent not granted for this operation");
    return .consent_required;
}

/// Record a consent state transition in the audit trail.
export fn wokelangiser_record_consent_transition(
    handle: ?*Handle,
    subject_id: u64,
    from_state: u32,
    to_state: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (from_state > 3 or to_state > 3) {
        setError("Invalid consent state");
        return .invalid_param;
    }

    // Validate state transition (matches ValidTransition in Types.idr)
    const valid = switch (from_state) {
        0 => to_state == 1, // Pending -> Granted
        1 => to_state == 2 or to_state == 3, // Granted -> Active or Revoked
        2 => to_state == 3, // Active -> Revoked
        else => false,
    };

    if (!valid) {
        setError("Invalid consent state transition");
        return .invalid_param;
    }

    // Record the transition
    h.consent_records.append(.{
        .consent_type = 3, // AuditTrail
        .state = to_state,
        .timestamp = @intCast(std.time.timestamp()),
        .subject_id = subject_id,
    }) catch {
        setError("Failed to record consent transition");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

//==============================================================================
// Accessibility Operations
//==============================================================================

/// Check whether a UI element meets the specified WCAG level.
/// element_ptr: pointer to an AccessibilityRecord
/// wcag_level: 0=A, 1=AA, 2=AAA
export fn wokelangiser_check_accessibility(
    handle: ?*Handle,
    element_ptr: u64,
    wcag_level: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (element_ptr == 0) {
        setError("Null element pointer");
        return .null_pointer;
    }

    if (wcag_level > 2) {
        setError("Invalid WCAG level");
        return .invalid_param;
    }

    // Read the accessibility record from the pointer
    const record: *const AccessibilityRecord = @ptrFromInt(element_ptr);

    // Check contrast ratio against WCAG requirements
    const min_contrast: u32 = switch (wcag_level) {
        0 => 0, // Level A: no minimum contrast
        1 => 450, // Level AA: 4.5:1 minimum
        2 => 700, // Level AAA: 7:1 minimum
        else => unreachable,
    };

    if (record.contrast_ratio < min_contrast) {
        setError("Contrast ratio does not meet WCAG level requirement");
        return .accessibility_failed;
    }

    // Check that ARIA label is present (non-null pointer)
    if (record.aria_label_ptr == 0) {
        setError("Missing ARIA label");
        return .accessibility_failed;
    }

    clearError();
    return .ok;
}

/// Annotate a UI element with accessibility metadata.
export fn wokelangiser_annotate_element(
    handle: ?*Handle,
    element_ptr: u64,
    aria_label_ptr: u64,
    role_ptr: u64,
    focus_order: u32,
    contrast_ratio: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (element_ptr == 0) {
        setError("Null element pointer");
        return .null_pointer;
    }

    // Write annotation into the record
    const record: *AccessibilityRecord = @ptrFromInt(element_ptr);
    record.aria_label_ptr = aria_label_ptr;
    record.role_ptr = role_ptr;
    record.focus_order = focus_order;
    record.contrast_ratio = contrast_ratio;

    clearError();
    return .ok;
}

/// Calculate the contrast ratio between two 24-bit RGB colours.
/// Returns the ratio * 100 (e.g. 450 = 4.50:1).
/// Implements WCAG 2.2 relative luminance algorithm.
export fn wokelangiser_contrast_ratio(foreground: u32, background: u32) u32 {
    const fg_lum = relativeLuminance(foreground);
    const bg_lum = relativeLuminance(background);

    const lighter = @max(fg_lum, bg_lum);
    const darker = @min(fg_lum, bg_lum);

    // Contrast ratio = (L1 + 0.05) / (L2 + 0.05), scaled by 100.
    // Black-on-white gives (1.0 + 0.05) / (0.0 + 0.05) * 100 = 2100 (21:1).
    return @intFromFloat((lighter + 0.05) / (darker + 0.05) * 100.0);
}

/// Calculate relative luminance of a 24-bit RGB colour.
/// Per WCAG 2.2: L = 0.2126*R + 0.7152*G + 0.0722*B (after linearisation)
fn relativeLuminance(rgb: u32) f64 {
    const r_srgb: f64 = @as(f64, @floatFromInt((rgb >> 16) & 0xFF)) / 255.0;
    const g_srgb: f64 = @as(f64, @floatFromInt((rgb >> 8) & 0xFF)) / 255.0;
    const b_srgb: f64 = @as(f64, @floatFromInt(rgb & 0xFF)) / 255.0;

    const r = linearise(r_srgb);
    const g = linearise(g_srgb);
    const b = linearise(b_srgb);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Linearise an sRGB channel value per WCAG 2.2 spec
fn linearise(channel: f64) f64 {
    if (channel <= 0.04045) {
        return channel / 12.92;
    }
    return std.math.pow(f64, (channel + 0.055) / 1.055, 2.4);
}

//==============================================================================
// Internationalisation Operations
//==============================================================================

/// Extract hardcoded strings from source content for localisation.
export fn wokelangiser_extract_strings(
    handle: ?*Handle,
    source_ptr: u64,
    output_ptr: u64,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (source_ptr == 0 or output_ptr == 0) {
        setError("Null pointer");
        return .null_pointer;
    }

    // TODO: Implement string extraction from source AST
    // (source_ptr/output_ptr are validated above; extraction is future work.)

    clearError();
    return .ok;
}

/// Format a value according to the specified locale and hook type.
export fn wokelangiser_format_locale(
    handle: ?*Handle,
    hook_type: u32,
    locale_ptr: u64,
    value_ptr: u64,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (hook_type > 3) {
        setError("Invalid i18n hook type");
        return .invalid_param;
    }

    if (locale_ptr == 0 or value_ptr == 0) {
        setError("Null pointer");
        return .null_pointer;
    }

    // TODO: Implement locale-specific formatting
    // (locale_ptr/value_ptr are validated above; formatting is future work.)

    clearError();
    return .ok;
}

//==============================================================================
// Cultural Sensitivity Operations
//==============================================================================

/// Check content for culturally sensitive terms.
export fn wokelangiser_check_sensitivity(
    handle: ?*Handle,
    content_ptr: u64,
    context_type: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (content_ptr == 0) {
        setError("Null content pointer");
        return .null_pointer;
    }

    if (context_type > 2) {
        setError("Invalid cultural context type");
        return .invalid_param;
    }

    // TODO: Implement cultural sensitivity checking against term database
    // (content_ptr is validated above; sensitivity analysis is future work.)

    clearError();
    return .ok;
}

/// Suggest culturally appropriate alternatives for flagged terms.
export fn wokelangiser_suggest_alternative(
    handle: ?*Handle,
    term_ptr: u64,
    output_ptr: u64,
    context_type: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (term_ptr == 0 or output_ptr == 0) {
        setError("Null pointer");
        return .null_pointer;
    }

    if (context_type > 2) {
        setError("Invalid cultural context type");
        return .invalid_param;
    }

    // TODO: Implement alternative suggestion lookup
    // (term_ptr/output_ptr are validated above; suggestion lookup is future work.)

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result.
/// Caller must free the returned string with wokelangiser_free_string.
export fn wokelangiser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "wokelangiser result") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library.
export fn wokelangiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message. Returns null if no error.
export fn wokelangiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version string.
export fn wokelangiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information string.
export fn wokelangiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized.
export fn wokelangiser_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    try std.testing.expect(wokelangiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = wokelangiser_inject_consent(null, 0, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = wokelangiser_last_error();
    try std.testing.expect(err != null);
}

test "consent check without grant returns consent_required" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_check_consent(handle, 0, 12345);
    try std.testing.expectEqual(Result.consent_required, result);
}

test "invalid consent type rejected" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    const result = wokelangiser_inject_consent(handle, 99, 1);
    try std.testing.expectEqual(Result.invalid_param, result);
}

test "consent state transition validation" {
    const handle = wokelangiser_init() orelse return error.InitFailed;
    defer wokelangiser_free(handle);

    // Valid: Pending -> Granted
    const valid = wokelangiser_record_consent_transition(handle, 1, 0, 1);
    try std.testing.expectEqual(Result.ok, valid);

    // Invalid: Pending -> Active (must go through Granted first)
    const invalid = wokelangiser_record_consent_transition(handle, 1, 0, 2);
    try std.testing.expectEqual(Result.invalid_param, invalid);

    // Invalid: Revoked -> anything (terminal state)
    const terminal = wokelangiser_record_consent_transition(handle, 1, 3, 0);
    try std.testing.expectEqual(Result.invalid_param, terminal);
}

test "contrast ratio calculation" {
    // Black (0x000000) on White (0xFFFFFF) should give maximum contrast (~21:1 = 2100)
    const max_contrast = wokelangiser_contrast_ratio(0x000000, 0xFFFFFF);
    try std.testing.expect(max_contrast >= 2000);

    // Same colour should give ~100 (1:1 ratio)
    const no_contrast = wokelangiser_contrast_ratio(0x808080, 0x808080);
    try std.testing.expect(no_contrast <= 110);
}

test "version" {
    const ver = wokelangiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "layout size assertions" {
    // Verify struct sizes match Layout.idr definitions
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(ConsentRecord));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(AccessibilityRecord));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(I18nRecord));
}
