// Betlangiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
//
// Core functionality: distribution creation, sampling, combination,
// ternary logic evaluation, and confidence interval computation.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "Betlangiser built with Zig " ++ @import("builtin").zig_version_string;

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
    invalid_distribution = 5,
    sampling_failed = 6,
};

/// Distribution type tags (must match Types.idr distributionTag)
pub const DistributionTag = enum(u32) {
    normal = 0,
    uniform = 1,
    beta = 2,
    bernoulli = 3,
    custom = 4,
};

/// Ternary boolean values (must match Types.idr ternaryToInt)
pub const TernaryBool = enum(u32) {
    t_false = 0,
    t_true = 1,
    t_unknown = 2,
};

/// Distribution parameters union
/// Layout must match Layout.idr distributionLayout (40 bytes, 8-byte aligned)
pub const Distribution = struct {
    tag: DistributionTag,
    _pad0: u32 = 0,
    param1: f64, // mean / low / alpha / p
    param2: f64, // stddev / high / beta / 0
    custom_ptr: ?[*]const f64, // pointer to custom PDF samples, or null
    custom_len: u32, // length of custom data
    _pad1: u32 = 0,
};

/// Sample buffer for Monte Carlo engine
/// Layout must match Layout.idr sampleBufferLayout (56 bytes, 8-byte aligned)
pub const SampleBuffer = struct {
    capacity: u64,
    count: u64,
    samples: ?[*]f64,
    mean: f64,
    variance: f64,
    min_val: f64,
    max_val: f64,
};

/// Confidence interval result
/// Layout must match Layout.idr confidenceIntervalLayout (24 bytes, 8-byte aligned)
pub const ConfidenceInterval = struct {
    lower: f64,
    upper: f64,
    confidence: f64,
};

/// Engine handle containing allocator and PRNG state
pub const Engine = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    prng: std.Random.DefaultPrng,
    distributions: std.ArrayList(*Distribution),
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the betlangiser engine.
/// Returns a pointer to the engine, or null on failure.
export fn betlangiser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const engine = allocator.create(Engine) catch {
        setError("Failed to allocate engine");
        return null;
    };

    engine.* = .{
        .allocator = allocator,
        .initialized = true,
        .prng = std.Random.DefaultPrng.init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp())))),
        .distributions = std.ArrayList(*Distribution).init(allocator),
    };

    clearError();
    return @ptrCast(engine);
}

/// Free the engine and all owned distributions.
export fn betlangiser_free(handle: ?*anyopaque) void {
    const engine = getEngine(handle) orelse return;
    const allocator = engine.allocator;

    // Free all tracked distributions
    for (engine.distributions.items) |dist| {
        allocator.destroy(dist);
    }
    engine.distributions.deinit();

    engine.initialized = false;
    allocator.destroy(engine);
    clearError();
}

//==============================================================================
// Distribution Creation
//==============================================================================

/// Create a Normal distribution (mean, stddev).
/// Returns distribution handle, or 0 on failure.
export fn betlangiser_dist_normal(handle: ?*anyopaque, mean: f64, stddev: f64) u64 {
    const engine = getEngine(handle) orelse return 0;

    if (stddev <= 0.0) {
        setError("Normal distribution requires stddev > 0");
        return 0;
    }

    return createDist(engine, .{
        .tag = .normal,
        .param1 = mean,
        .param2 = stddev,
        .custom_ptr = null,
        .custom_len = 0,
    });
}

/// Create a Uniform distribution [low, high).
export fn betlangiser_dist_uniform(handle: ?*anyopaque, low: f64, high: f64) u64 {
    const engine = getEngine(handle) orelse return 0;

    if (low >= high) {
        setError("Uniform distribution requires low < high");
        return 0;
    }

    return createDist(engine, .{
        .tag = .uniform,
        .param1 = low,
        .param2 = high,
        .custom_ptr = null,
        .custom_len = 0,
    });
}

/// Create a Beta distribution (alpha, beta).
export fn betlangiser_dist_beta(handle: ?*anyopaque, alpha: f64, beta_param: f64) u64 {
    const engine = getEngine(handle) orelse return 0;

    if (alpha <= 0.0 or beta_param <= 0.0) {
        setError("Beta distribution requires alpha > 0 and beta > 0");
        return 0;
    }

    return createDist(engine, .{
        .tag = .beta,
        .param1 = alpha,
        .param2 = beta_param,
        .custom_ptr = null,
        .custom_len = 0,
    });
}

/// Create a Bernoulli distribution (p in [0,1]).
export fn betlangiser_dist_bernoulli(handle: ?*anyopaque, p: f64) u64 {
    const engine = getEngine(handle) orelse return 0;

    if (p < 0.0 or p > 1.0) {
        setError("Bernoulli distribution requires 0 <= p <= 1");
        return 0;
    }

    return createDist(engine, .{
        .tag = .bernoulli,
        .param1 = p,
        .param2 = 0.0,
        .custom_ptr = null,
        .custom_len = 0,
    });
}

/// Free a distribution handle.
export fn betlangiser_dist_free(handle: ?*anyopaque, dist_ptr: u64) void {
    const engine = getEngine(handle) orelse return;
    if (dist_ptr == 0) return;

    const dist: *Distribution = @ptrFromInt(dist_ptr);
    engine.allocator.destroy(dist);
    clearError();
}

//==============================================================================
// Sampling
//==============================================================================

/// Draw a single sample from a distribution.
export fn betlangiser_sample_one(handle: ?*anyopaque, dist_ptr: u64) f64 {
    const engine = getEngine(handle) orelse return 0.0;
    const dist = getDistribution(dist_ptr) orelse return 0.0;

    return sampleDistribution(engine, dist);
}

/// Draw multiple samples into a caller-provided buffer.
export fn betlangiser_sample_many(handle: ?*anyopaque, dist_ptr: u64, buf_ptr: u64, count: u64) Result {
    const engine = getEngine(handle) orelse return .null_pointer;
    const dist = getDistribution(dist_ptr) orelse return .null_pointer;

    if (buf_ptr == 0) {
        setError("Null buffer pointer");
        return .null_pointer;
    }
    if (count == 0) {
        setError("Sample count must be > 0");
        return .invalid_param;
    }

    const buffer: [*]f64 = @ptrFromInt(buf_ptr);
    for (0..count) |i| {
        buffer[i] = sampleDistribution(engine, dist);
    }

    clearError();
    return .ok;
}

//==============================================================================
// Distribution Combination
//==============================================================================

/// Add two distributions (sum/convolution).
/// For known closed forms (Normal+Normal), uses analytical result.
/// Otherwise, creates a compound distribution sampled via Monte Carlo.
export fn betlangiser_dist_add(handle: ?*anyopaque, d1_ptr: u64, d2_ptr: u64) u64 {
    const engine = getEngine(handle) orelse return 0;
    const d1 = getDistribution(d1_ptr) orelse return 0;
    const d2 = getDistribution(d2_ptr) orelse return 0;

    // Analytical: Normal + Normal = Normal
    if (d1.tag == .normal and d2.tag == .normal) {
        const new_mean = d1.param1 + d2.param1;
        const new_stddev = @sqrt(d1.param2 * d1.param2 + d2.param2 * d2.param2);
        return createDist(engine, .{
            .tag = .normal,
            .param1 = new_mean,
            .param2 = new_stddev,
            .custom_ptr = null,
            .custom_len = 0,
        });
    }

    // Fallback: create a custom distribution via sampling
    // (full implementation pending — returns 0 for now)
    setError("Non-analytical distribution addition not yet implemented");
    return 0;
}

/// Multiply two distributions.
export fn betlangiser_dist_multiply(handle: ?*anyopaque, d1_ptr: u64, d2_ptr: u64) u64 {
    _ = handle;
    _ = d1_ptr;
    _ = d2_ptr;
    setError("Distribution multiplication not yet implemented");
    return 0;
}

/// Create a mixture distribution: weight * d1 + (1-weight) * d2.
export fn betlangiser_dist_mixture(handle: ?*anyopaque, d1_ptr: u64, d2_ptr: u64, weight: f64) u64 {
    _ = handle;
    _ = d1_ptr;
    _ = d2_ptr;
    _ = weight;
    setError("Distribution mixture not yet implemented");
    return 0;
}

//==============================================================================
// Ternary Logic
//==============================================================================

/// Compare a distribution to a threshold with ternary result.
/// Returns: 1 (True) if P(dist > threshold) >= confidence,
///          0 (False) if P(dist <= threshold) >= confidence,
///          2 (Unknown) otherwise.
export fn betlangiser_ternary_compare(handle: ?*anyopaque, dist_ptr: u64, threshold: f64, confidence: f64) u32 {
    _ = handle;
    _ = dist_ptr;
    _ = threshold;
    _ = confidence;
    // Full implementation pending — Monte Carlo estimation of tail probability
    return @intFromEnum(TernaryBool.t_unknown);
}

/// Ternary AND (Kleene strong logic)
export fn betlangiser_ternary_and(a: u32, b: u32) u32 {
    const ta: TernaryBool = @enumFromInt(a);
    const tb: TernaryBool = @enumFromInt(b);

    const result: TernaryBool = switch (ta) {
        .t_false => .t_false,
        .t_true => tb,
        .t_unknown => switch (tb) {
            .t_false => .t_false,
            else => .t_unknown,
        },
    };
    return @intFromEnum(result);
}

/// Ternary OR (Kleene strong logic)
export fn betlangiser_ternary_or(a: u32, b: u32) u32 {
    const ta: TernaryBool = @enumFromInt(a);
    const tb: TernaryBool = @enumFromInt(b);

    const result: TernaryBool = switch (ta) {
        .t_true => .t_true,
        .t_false => tb,
        .t_unknown => switch (tb) {
            .t_true => .t_true,
            else => .t_unknown,
        },
    };
    return @intFromEnum(result);
}

/// Ternary NOT (Kleene)
export fn betlangiser_ternary_not(a: u32) u32 {
    const ta: TernaryBool = @enumFromInt(a);
    const result: TernaryBool = switch (ta) {
        .t_true => .t_false,
        .t_false => .t_true,
        .t_unknown => .t_unknown,
    };
    return @intFromEnum(result);
}

//==============================================================================
// Confidence Interval
//==============================================================================

/// Compute a confidence interval for a distribution.
/// Writes result to output_ptr (must point to ConfidenceInterval struct).
export fn betlangiser_confidence_interval(handle: ?*anyopaque, dist_ptr: u64, confidence: f64, output_ptr: u64) Result {
    _ = handle;
    _ = dist_ptr;
    _ = confidence;
    _ = output_ptr;
    setError("Confidence interval computation not yet implemented");
    return .@"error";
}

//==============================================================================
// Distribution Properties
//==============================================================================

/// Get the mean of a distribution (analytical where possible).
export fn betlangiser_dist_mean(handle: ?*anyopaque, dist_ptr: u64) f64 {
    _ = handle;
    const dist = getDistribution(dist_ptr) orelse return 0.0;

    return switch (dist.tag) {
        .normal => dist.param1,
        .uniform => (dist.param1 + dist.param2) / 2.0,
        .beta => dist.param1 / (dist.param1 + dist.param2),
        .bernoulli => dist.param1,
        .custom => 0.0, // Requires numerical integration
    };
}

/// Get the variance of a distribution (analytical where possible).
export fn betlangiser_dist_variance(handle: ?*anyopaque, dist_ptr: u64) f64 {
    _ = handle;
    const dist = getDistribution(dist_ptr) orelse return 0.0;

    return switch (dist.tag) {
        .normal => dist.param2 * dist.param2,
        .uniform => blk: {
            const range = dist.param2 - dist.param1;
            break :blk (range * range) / 12.0;
        },
        .beta => blk: {
            const a = dist.param1;
            const b = dist.param2;
            break :blk (a * b) / ((a + b) * (a + b) * (a + b + 1.0));
        },
        .bernoulli => dist.param1 * (1.0 - dist.param1),
        .custom => 0.0, // Requires numerical integration
    };
}

/// Get the distribution type tag.
export fn betlangiser_dist_tag(handle: ?*anyopaque, dist_ptr: u64) u32 {
    _ = handle;
    const dist = getDistribution(dist_ptr) orelse return 255;
    return @intFromEnum(dist.tag);
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result.
/// Caller must free the returned string with betlangiser_free_string.
export fn betlangiser_get_string(handle: ?*anyopaque) ?[*:0]const u8 {
    const engine = getEngine(handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!engine.initialized) {
        setError("Engine not initialized");
        return null;
    }

    const result = engine.allocator.dupeZ(u8, "betlangiser engine active") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library.
export fn betlangiser_free_string(str: ?[*:0]const u8) void {
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
export fn betlangiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version.
export fn betlangiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information.
export fn betlangiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if engine is initialized.
export fn betlangiser_is_initialized(handle: ?*anyopaque) u32 {
    const engine = getEngine(handle) orelse return 0;
    return if (engine.initialized) 1 else 0;
}

//==============================================================================
// Internal Helpers
//==============================================================================

/// Cast opaque handle to Engine pointer
fn getEngine(handle: ?*anyopaque) ?*Engine {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };
    const engine: *Engine = @ptrCast(@alignCast(h));
    if (!engine.initialized) {
        setError("Engine not initialized");
        return null;
    }
    return engine;
}

/// Cast u64 to Distribution pointer
fn getDistribution(ptr: u64) ?*Distribution {
    if (ptr == 0) {
        setError("Null distribution handle");
        return null;
    }
    return @ptrFromInt(ptr);
}

/// Allocate and track a new distribution
fn createDist(engine: *Engine, dist: Distribution) u64 {
    const d = engine.allocator.create(Distribution) catch {
        setError("Failed to allocate distribution");
        return 0;
    };
    d.* = dist;

    engine.distributions.append(d) catch {
        engine.allocator.destroy(d);
        setError("Failed to track distribution");
        return 0;
    };

    clearError();
    return @intFromPtr(d);
}

/// Sample a single value from a distribution using the engine's PRNG
fn sampleDistribution(engine: *Engine, dist: *const Distribution) f64 {
    const random = engine.prng.random();

    return switch (dist.tag) {
        .normal => blk: {
            // Box-Muller transform for normal sampling
            const unif1 = random.float(f64);
            const unif2 = random.float(f64);
            const z = @sqrt(-2.0 * @log(unif1)) * @cos(2.0 * std.math.pi * unif2);
            break :blk dist.param1 + dist.param2 * z;
        },
        .uniform => dist.param1 + (dist.param2 - dist.param1) * random.float(f64),
        .beta => 0.0, // Beta sampling requires gamma function — pending
        .bernoulli => if (random.float(f64) < dist.param1) 1.0 else 0.0,
        .custom => 0.0, // Custom sampling pending
    };
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    try std.testing.expect(betlangiser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = betlangiser_sample_many(null, 0, 0, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = betlangiser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = betlangiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "ternary logic - NOT involution" {
    try std.testing.expectEqual(@as(u32, 1), betlangiser_ternary_not(0)); // NOT False = True
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_not(1)); // NOT True = False
    try std.testing.expectEqual(@as(u32, 2), betlangiser_ternary_not(2)); // NOT Unknown = Unknown
}

test "ternary logic - AND truth table" {
    // False AND anything = False
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(0, 0));
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(0, 1));
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(0, 2));
    // True AND x = x
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(1, 0));
    try std.testing.expectEqual(@as(u32, 1), betlangiser_ternary_and(1, 1));
    try std.testing.expectEqual(@as(u32, 2), betlangiser_ternary_and(1, 2));
    // Unknown AND ...
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_and(2, 0));
    try std.testing.expectEqual(@as(u32, 2), betlangiser_ternary_and(2, 1));
    try std.testing.expectEqual(@as(u32, 2), betlangiser_ternary_and(2, 2));
}

test "ternary logic - OR truth table" {
    // True OR anything = True
    try std.testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(1, 0));
    try std.testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(1, 1));
    try std.testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(1, 2));
    // False OR x = x
    try std.testing.expectEqual(@as(u32, 0), betlangiser_ternary_or(0, 0));
    try std.testing.expectEqual(@as(u32, 1), betlangiser_ternary_or(0, 1));
    try std.testing.expectEqual(@as(u32, 2), betlangiser_ternary_or(0, 2));
}

test "distribution mean - normal" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist_ptr = betlangiser_dist_normal(handle, 42.0, 5.0);
    try std.testing.expect(dist_ptr != 0);

    const mean = betlangiser_dist_mean(handle, dist_ptr);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), mean, 0.001);
}

test "distribution mean - uniform" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    const dist_ptr = betlangiser_dist_uniform(handle, 10.0, 20.0);
    try std.testing.expect(dist_ptr != 0);

    const mean = betlangiser_dist_mean(handle, dist_ptr);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), mean, 0.001);
}

test "invalid distribution parameters rejected" {
    const handle = betlangiser_init() orelse return error.InitFailed;
    defer betlangiser_free(handle);

    // Negative stddev
    try std.testing.expectEqual(@as(u64, 0), betlangiser_dist_normal(handle, 0, -1.0));
    // low >= high
    try std.testing.expectEqual(@as(u64, 0), betlangiser_dist_uniform(handle, 10.0, 5.0));
    // p out of range
    try std.testing.expectEqual(@as(u64, 0), betlangiser_dist_bernoulli(handle, 1.5));
}
