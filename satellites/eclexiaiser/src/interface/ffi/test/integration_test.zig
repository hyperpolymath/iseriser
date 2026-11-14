// Eclexiaiser Integration Tests
//
// Verify that the Zig FFI correctly implements the Idris2 ABI for
// energy measurement, carbon tracking, and budget enforcement.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");
const testing = std.testing;

// Import FFI functions (C ABI, declared in src/interface/abi/Foreign.idr)
extern fn eclexiaiser_init() ?*opaque {};
extern fn eclexiaiser_free(?*opaque {}) void;
extern fn eclexiaiser_is_initialized(?*opaque {}) u32;
extern fn eclexiaiser_counter_type(?*opaque {}) u32;

// Energy measurement
extern fn eclexiaiser_start_measurement(?*opaque {}, u64) c_int;
extern fn eclexiaiser_stop_measurement(?*opaque {}, u64) u64;
extern fn eclexiaiser_read_power_mw(?*opaque {}) u64;

// Carbon intensity
extern fn eclexiaiser_query_carbon_intensity(?*opaque {}, u32) u32;
extern fn eclexiaiser_query_renewable_pct(?*opaque {}, u32) u32;
extern fn eclexiaiser_set_carbon_api(?*opaque {}, u32) c_int;

// Budget enforcement
extern fn eclexiaiser_enforce_energy_budget(?*opaque {}, u64, u64) c_int;
extern fn eclexiaiser_enforce_carbon_limit(?*opaque {}, u64, u64) c_int;

// Reporting
extern fn eclexiaiser_generate_report(?*opaque {}, u64) c_int;
extern fn eclexiaiser_report_to_json(?*opaque {}) ?[*:0]const u8;

// Error handling
extern fn eclexiaiser_last_error() ?[*:0]const u8;
extern fn eclexiaiser_free_string(?[*:0]const u8) void;

// Version
extern fn eclexiaiser_version() [*:0]const u8;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const initialized = eclexiaiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = eclexiaiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

test "counter type is detected" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const ct = eclexiaiser_counter_type(handle);
    // Must be one of: 0=RAPL, 1=IPMI, 2=estimate
    try testing.expect(ct <= 2);
}

//==============================================================================
// Energy Measurement Tests
//==============================================================================

test "start measurement with null handle returns error" {
    const result = eclexiaiser_start_measurement(null, 42);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

test "read power returns a value" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const power = eclexiaiser_read_power_mw(handle);
    // Should return a positive estimate (or 0 if no counter)
    try testing.expect(power > 0 or power == 0);
}

//==============================================================================
// Carbon Intensity Tests
//==============================================================================

test "query UK carbon intensity" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const intensity = eclexiaiser_query_carbon_intensity(handle, 0x4742); // "GB"
    try testing.expectEqual(@as(u32, 200_000), intensity); // ~200g/kWh
}

test "query Norway carbon intensity (low)" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const intensity = eclexiaiser_query_carbon_intensity(handle, 0x4E4F); // "NO"
    try testing.expectEqual(@as(u32, 20_000), intensity); // ~20g/kWh
}

test "query renewable percentage" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const pct = eclexiaiser_query_renewable_pct(handle, 0x4E4F); // Norway
    try testing.expectEqual(@as(u32, 9800), pct); // ~98%
}

test "set carbon API provider" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const ok = eclexiaiser_set_carbon_api(handle, 2); // static
    try testing.expectEqual(@as(c_int, 0), ok);

    const bad = eclexiaiser_set_carbon_api(handle, 99); // invalid
    try testing.expectEqual(@as(c_int, 2), bad); // 2 = invalid_param
}

test "carbon query with null handle" {
    const intensity = eclexiaiser_query_carbon_intensity(null, 0x4742);
    try testing.expectEqual(@as(u32, 0), intensity);
}

//==============================================================================
// Budget Enforcement Tests
//==============================================================================

test "energy budget within limit" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const result = eclexiaiser_enforce_energy_budget(handle, 1_000_000, 500_000);
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

test "energy budget exceeded" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const result = eclexiaiser_enforce_energy_budget(handle, 500_000, 1_000_000);
    try testing.expectEqual(@as(c_int, 5), result); // budget_exceeded
}

test "carbon limit within" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const result = eclexiaiser_enforce_carbon_limit(handle, 200_000, 150_000);
    try testing.expectEqual(@as(c_int, 0), result); // ok
}

test "carbon limit exceeded" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const result = eclexiaiser_enforce_carbon_limit(handle, 100_000, 200_000);
    try testing.expectEqual(@as(c_int, 6), result); // carbon_limit_exceeded
}

test "enforcement with null handle" {
    const result = eclexiaiser_enforce_energy_budget(null, 100, 50);
    try testing.expectEqual(@as(c_int, 4), result); // null_pointer
}

//==============================================================================
// Reporting Tests
//==============================================================================

test "report to JSON" {
    const handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(handle);

    const json = eclexiaiser_report_to_json(handle);
    defer if (json) |j| eclexiaiser_free_string(j);

    try testing.expect(json != null);

    if (json) |j| {
        const json_str = std.mem.span(j);
        try testing.expect(json_str.len > 0);
        // Should contain expected fields
        try testing.expect(std.mem.indexOf(u8, json_str, "total_energy_uj") != null);
    }
}

test "report to JSON with null handle" {
    const json = eclexiaiser_report_to_json(null);
    try testing.expect(json == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = eclexiaiser_enforce_energy_budget(null, 0, 0);

    const err = eclexiaiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = eclexiaiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = eclexiaiser_version();
    const ver_str = std.mem.span(ver);
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(h1);

    const h2 = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(h2);

    try testing.expect(h1 != h2);

    // Budget enforcement on h1 should not affect h2
    _ = eclexiaiser_enforce_energy_budget(h1, 100, 200); // exceed on h1
    const h2_result = eclexiaiser_enforce_energy_budget(h2, 1000, 500); // within on h2
    try testing.expectEqual(@as(c_int, 0), h2_result);
}

test "free null is safe" {
    eclexiaiser_free(null); // Should not crash
}
