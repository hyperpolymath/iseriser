// Betlangiser Integration Tests
// SPDX-License-Identifier: MPL-2.0
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI.
// Coverage: lifecycle, distribution creation, sampling, ternary logic,
// error handling, version, and memory safety.

const std = @import("std");
const testing = std.testing;

// Import FFI functions — distribution engine
extern fn betlangiser_init() ?*anyopaque;
extern fn betlangiser_free(?*anyopaque) void;
extern fn betlangiser_is_initialized(?*anyopaque) u32;

// Distribution creation
extern fn betlangiser_dist_normal(?*anyopaque, f64, f64) u64;
extern fn betlangiser_dist_uniform(?*anyopaque, f64, f64) u64;
extern fn betlangiser_dist_beta(?*anyopaque, f64, f64) u64;
extern fn betlangiser_dist_bernoulli(?*anyopaque, f64) u64;
extern fn betlangiser_dist_free(?*anyopaque, u64) void;

// Sampling
extern fn betlangiser_sample_one(?*anyopaque, u64) f64;
extern fn betlangiser_sample_many(?*anyopaque, u64, u64, u64) c_int;

// Distribution combination
extern fn betlangiser_dist_add(?*anyopaque, u64, u64) u64;

// Distribution properties
extern fn betlangiser_dist_mean(?*anyopaque, u64) f64;
extern fn betlangiser_dist_variance(?*anyopaque, u64) f64;
extern fn betlangiser_dist_tag(?*anyopaque, u64) u32;

// Ternary logic
extern fn betlangiser_ternary_compare(?*anyopaque, u64, f64, f64) u32;
extern fn betlangiser_ternary_and(u32, u32) u32;
extern fn betlangiser_ternary_or(u32, u32) u32;
extern fn betlangiser_ternary_not(u32) u32;

// String and error operations
extern fn betlangiser_get_string(?*anyopaque) ?[*:0]const u8;
extern fn betlangiser_free_string(?[*:0]const u8) void;
extern fn betlangiser_last_error() ?[*:0]const u8;
extern fn betlangiser_version() [*:0]const u8;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy engine" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    try testing.expect(handle != null);
}

test "engine is initialized" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const initialized = betlangiser_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = betlangiser_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Distribution Creation Tests
//==============================================================================

test "create normal distribution" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_normal(handle, 0.0, 1.0);
    try testing.expect(dist != 0);

    try testing.expectEqual(@as(u32, 0), betlangiser_dist_tag(handle, dist)); // normal = 0
}

test "create uniform distribution" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_uniform(handle, 0.0, 1.0);
    try testing.expect(dist != 0);

    try testing.expectEqual(@as(u32, 1), betlangiser_dist_tag(handle, dist)); // uniform = 1
}

test "create beta distribution" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_beta(handle, 2.0, 5.0);
    try testing.expect(dist != 0);

    try testing.expectEqual(@as(u32, 2), betlangiser_dist_tag(handle, dist)); // beta = 2
}

test "create bernoulli distribution" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_bernoulli(handle, 0.5);
    try testing.expect(dist != 0);

    try testing.expectEqual(@as(u32, 3), betlangiser_dist_tag(handle, dist)); // bernoulli = 3
}

test "reject invalid normal distribution (negative stddev)" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_normal(handle, 0.0, -1.0);
    try testing.expectEqual(@as(u64, 0), dist);
}

test "reject invalid uniform distribution (low >= high)" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_uniform(handle, 10.0, 5.0);
    try testing.expectEqual(@as(u64, 0), dist);
}

test "reject invalid bernoulli distribution (p > 1)" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_bernoulli(handle, 1.5);
    try testing.expectEqual(@as(u64, 0), dist);
}

//==============================================================================
// Distribution Properties Tests
//==============================================================================

test "normal distribution mean" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_normal(handle, 42.0, 5.0);
    try testing.expect(dist != 0);

    const mean = betlangiser_dist_mean(handle, dist);
    try testing.expectApproxEqAbs(@as(f64, 42.0), mean, 0.001);
}

test "uniform distribution mean" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_uniform(handle, 10.0, 20.0);
    try testing.expect(dist != 0);

    const mean = betlangiser_dist_mean(handle, dist);
    try testing.expectApproxEqAbs(@as(f64, 15.0), mean, 0.001);
}

test "bernoulli distribution variance" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_bernoulli(handle, 0.3);
    try testing.expect(dist != 0);

    const variance = betlangiser_dist_variance(handle, dist);
    try testing.expectApproxEqAbs(@as(f64, 0.21), variance, 0.001); // 0.3 * 0.7
}

//==============================================================================
// Distribution Combination Tests
//==============================================================================

test "add two normal distributions" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const d1 = betlangiser_dist_normal(handle, 10.0, 3.0);
    const d2 = betlangiser_dist_normal(handle, 5.0, 4.0);
    try testing.expect(d1 != 0);
    try testing.expect(d2 != 0);

    const sum = betlangiser_dist_add(handle, d1, d2);
    try testing.expect(sum != 0);

    // Sum of normals: mean = 10+5 = 15
    const mean = betlangiser_dist_mean(handle, sum);
    try testing.expectApproxEqAbs(@as(f64, 15.0), mean, 0.001);

    // Variance: sqrt(9 + 16) = 5.0
    const variance = betlangiser_dist_variance(handle, sum);
    try testing.expectApproxEqAbs(@as(f64, 25.0), variance, 0.001); // stddev^2 = 25
}

//==============================================================================
// Ternary Logic Tests
//==============================================================================

test "ternary NOT truth table" {
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_not(0)); // NOT False = True
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_not(1)); // NOT True = False
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_not(2)); // NOT Unknown = Unknown
}

test "ternary AND truth table (Kleene)" {
    // False dominates
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(0, 0));
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(0, 1));
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(0, 2));
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(1, 0));
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(2, 0));

    // True AND x = x
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_and(1, 1));
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_and(1, 2));

    // Unknown cases
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_and(2, 1));
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_and(2, 2));
}

test "ternary OR truth table (Kleene)" {
    // True dominates
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(1, 0));
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(1, 1));
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(1, 2));
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(0, 1));
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(2, 1));

    // False OR x = x
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_or(0, 0));
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_or(0, 2));

    // Unknown cases
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_or(2, 0));
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_or(2, 2));
}

test "ternary NOT is involution" {
    // NOT (NOT x) = x for all ternary values
    try testing.expectEqual(@as(u32, 0), betlangiser_ternary_not(betlangiser_ternary_not(0)));
    try testing.expectEqual(@as(u32, 1), betlangiser_ternary_not(betlangiser_ternary_not(1)));
    try testing.expectEqual(@as(u32, 2), betlangiser_ternary_not(betlangiser_ternary_not(2)));
}

//==============================================================================
// Sampling Tests
//==============================================================================

test "sample from normal distribution" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_normal(handle, 0.0, 1.0);
    try testing.expect(dist != 0);

    // Draw a sample — just verify it returns a finite value
    const sample = betlangiser_sample_one(handle, dist);
    try testing.expect(std.math.isFinite(sample));
}

test "sample from bernoulli distribution" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist = betlangiser_dist_bernoulli(handle, 0.5);
    try testing.expect(dist != 0);

    const sample = betlangiser_sample_one(handle, dist);
    // Bernoulli should return 0.0 or 1.0
    try testing.expect(sample == 0.0 or sample == 1.0);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = betlangiser_sample_many(null, 0, 0, 0);

    const err = betlangiser_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "get string with null handle" {
    const str = betlangiser_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = betlangiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = betlangiser_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple engines are independent" {
    const h1 = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(h1);

    const h2 = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(h2);

    try testing.expect(h1 != h2);

    // Distributions on h1 should not affect h2
    const d1 = betlangiser_dist_normal(h1, 1.0, 1.0);
    const d2 = betlangiser_dist_normal(h2, 2.0, 1.0);
    try testing.expect(d1 != 0);
    try testing.expect(d2 != 0);

    try testing.expectApproxEqAbs(@as(f64, 1.0), betlangiser_dist_mean(h1, d1), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.0), betlangiser_dist_mean(h2, d2), 0.001);
}

test "free null is safe" {
    betlangiser_free(null); // Should not crash
}
