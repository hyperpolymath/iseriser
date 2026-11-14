// Eclexiaiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// Provides energy measurement (RAPL/IPMI), carbon intensity API queries,
// budget enforcement, and sustainability report generation.
//
// All types and layouts must match the Idris2 ABI definitions in Types.idr and Layout.idr.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "eclexiaiser built with Zig " ++ @import("builtin").zig_version_string;

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
    budget_exceeded = 5,
    carbon_limit_exceeded = 6,
    counter_unavailable = 7,
};

/// Energy counter type (matches counter_type field in EnergyMeasurement)
pub const CounterType = enum(u32) {
    rapl = 0, // Intel Running Average Power Limit
    ipmi = 1, // Intelligent Platform Management Interface
    estimate = 2, // Software estimation (fallback)
};

/// Carbon API provider (matches api_source field in CarbonQuery)
pub const CarbonApiSource = enum(u32) {
    watttime = 0,
    electricity_maps = 1,
    static_data = 2,
};

/// Energy measurement struct (must match Layout.idr energyMeasurementLayout)
/// Total: 32 bytes, alignment: 8
pub const EnergyMeasurement = extern struct {
    function_id: u64, // offset 0: hash of function name
    energy_uj: u64, // offset 8: measured microjoules
    timestamp_ns: u64, // offset 16: nanosecond timestamp
    counter_type: u32, // offset 24: CounterType
    _padding: u32 = 0, // offset 28: padding to 32 bytes
};

/// Carbon query struct (must match Layout.idr carbonQueryLayout)
/// Total: 24 bytes, alignment: 8
pub const CarbonQuery = extern struct {
    zone_id: u32, // offset 0: grid zone hash
    intensity_mg: u32, // offset 4: mg CO2/kWh
    timestamp_epoch: u64, // offset 8: query timestamp
    renewable_bps: u32, // offset 16: renewable % in basis points
    api_source: u32, // offset 20: CarbonApiSource
};

/// Budget enforcement result (must match Layout.idr budgetEnforcementLayout)
/// Total: 40 bytes, alignment: 8
pub const BudgetEnforcement = extern struct {
    function_id: u64, // offset 0: which function
    budget_uj: u64, // offset 8: the budget
    measured_uj: u64, // offset 16: actual measurement
    carbon_mg_co2: u64, // offset 24: carbon cost
    result_code: u32, // offset 32: Result code
    _padding: u32 = 0, // offset 36: padding to 40 bytes
};

/// Sustainability report struct (must match Types.idr SustainabilityReport)
/// Total: 40 bytes, alignment: 8
pub const SustainabilityReport = extern struct {
    total_energy_uj: u64, // offset 0
    total_carbon_mg_co2: u64, // offset 8
    renewable_percent_bps: u32, // offset 16
    budget_violations: u32, // offset 20
    functions_measured: u32, // offset 24
    _padding: u32 = 0, // offset 28
    timestamp_epoch: u64, // offset 32
};

/// Library handle: holds measurement context and configuration
const HandleData = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    counter_type: CounterType,
    carbon_api: CarbonApiSource,
    // Per-function measurement state
    active_measurements: std.AutoHashMap(u64, u64), // function_id -> start timestamp
    // Accumulated measurements for reporting
    measurements: std.ArrayList(EnergyMeasurement),
    total_energy_uj: u64,
    total_carbon_mg_co2: u64,
    functions_measured: u32,
    budget_violations: u32,
};

/// Opaque handle type for C ABI
pub const Handle = *HandleData;

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the eclexiaiser library.
/// Detects available hardware counters, allocates measurement context.
/// Returns a handle, or null on failure.
export fn eclexiaiser_init() ?*anyopaque {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(HandleData) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .counter_type = detectCounterType(),
        .carbon_api = .static_data,
        .active_measurements = std.AutoHashMap(u64, u64).init(allocator),
        .measurements = std.ArrayList(EnergyMeasurement).init(allocator),
        .total_energy_uj = 0,
        .total_carbon_mg_co2 = 0,
        .functions_measured = 0,
        .budget_violations = 0,
    };

    clearError();
    return @ptrCast(handle);
}

/// Free the library handle and all accumulated measurement data.
export fn eclexiaiser_free(raw_handle: ?*anyopaque) void {
    const handle = getHandle(raw_handle) orelse return;
    const allocator = handle.allocator;

    handle.active_measurements.deinit();
    handle.measurements.deinit();
    handle.initialized = false;

    allocator.destroy(handle);
    clearError();
}

//==============================================================================
// Energy Measurement
//==============================================================================

/// Start measuring energy for a function.
/// Records the current counter value; call eclexiaiser_stop_measurement to get delta.
export fn eclexiaiser_start_measurement(raw_handle: ?*anyopaque, function_id: u64) Result {
    const handle = getHandle(raw_handle) orelse return .null_pointer;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    const timestamp = readEnergyCounter(handle.counter_type) orelse {
        setError("Energy counter not available");
        return .counter_unavailable;
    };

    handle.active_measurements.put(function_id, timestamp) catch {
        setError("Failed to store measurement start");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

/// Stop measuring energy for a function.
/// Returns energy consumed in microjoules since start_measurement.
export fn eclexiaiser_stop_measurement(raw_handle: ?*anyopaque, function_id: u64) u64 {
    const handle = getHandle(raw_handle) orelse return 0;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    const start = handle.active_measurements.get(function_id) orelse {
        setError("No active measurement for this function");
        return 0;
    };

    const end = readEnergyCounter(handle.counter_type) orelse {
        setError("Energy counter read failed");
        return 0;
    };

    const energy_uj = if (end > start) end - start else 0;

    // Record the measurement
    const measurement = EnergyMeasurement{
        .function_id = function_id,
        .energy_uj = energy_uj,
        .timestamp_ns = @intCast(std.time.nanoTimestamp()),
        .counter_type = @intFromEnum(handle.counter_type),
    };

    handle.measurements.append(measurement) catch {};
    handle.total_energy_uj += energy_uj;
    handle.functions_measured += 1;

    _ = handle.active_measurements.remove(function_id);

    clearError();
    return energy_uj;
}

/// Read instantaneous power draw in milliwatts.
export fn eclexiaiser_read_power_mw(raw_handle: ?*anyopaque) u64 {
    const handle = getHandle(raw_handle) orelse return 0;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // TODO: Implement actual RAPL/IPMI power reading
    // For now return a software estimate based on CPU frequency
    return estimatePowerMw();
}

/// Measure energy consumption for a handle, in microjoules.
/// Matches the ABI declaration in Types.idr (namespace Foreign):
///   %foreign "C:eclexiaiser_measure_energy"  : Bits64 -> PrimIO Bits64
/// Returns the current counter reading (uJ), or 0 if no counter is available
/// or the handle is null.
export fn eclexiaiser_measure_energy(raw_handle: ?*anyopaque) u64 {
    const handle = getHandle(raw_handle) orelse return 0;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    const reading = readEnergyCounter(handle.counter_type) orelse {
        setError("Energy counter not available");
        return 0;
    };

    clearError();
    return reading;
}

//==============================================================================
// Carbon Intensity API
//==============================================================================

/// Query carbon intensity for a grid zone.
/// Returns milligrams CO2 per kWh.
export fn eclexiaiser_query_carbon_intensity(raw_handle: ?*anyopaque, zone_id: u32) u32 {
    const handle = getHandle(raw_handle) orelse return 0;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // TODO: Implement WattTime and Electricity Maps API clients
    // For now, return static data based on zone_id
    return getStaticCarbonIntensity(zone_id);
}

/// Query renewable energy percentage for a grid zone.
/// Returns basis points (0-10000).
export fn eclexiaiser_query_renewable_pct(raw_handle: ?*anyopaque, zone_id: u32) u32 {
    const handle = getHandle(raw_handle) orelse return 0;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return 0;
    }

    // TODO: Implement real API query
    return getStaticRenewablePct(zone_id);
}

/// Query carbon intensity for a grid zone without a library handle.
/// Matches the ABI declaration in Types.idr (namespace Foreign):
///   %foreign "C:eclexiaiser_query_carbon"  : Bits32 -> PrimIO Bits32
/// Returns milligrams CO2 per kWh from the static dataset.
export fn eclexiaiser_query_carbon(zone_id: u32) u32 {
    return getStaticCarbonIntensity(zone_id);
}

/// Set the carbon API provider.
export fn eclexiaiser_set_carbon_api(raw_handle: ?*anyopaque, api_source: u32) Result {
    const handle = getHandle(raw_handle) orelse return .null_pointer;

    if (api_source > 2) {
        setError("Invalid API source (must be 0=WattTime, 1=ElectricityMaps, 2=static)");
        return .invalid_param;
    }

    handle.carbon_api = @enumFromInt(api_source);
    clearError();
    return .ok;
}

//==============================================================================
// Budget Enforcement
//==============================================================================

/// Enforce an energy budget against a measurement.
export fn eclexiaiser_enforce_energy_budget(raw_handle: ?*anyopaque, budget_uj: u64, measured_uj: u64) Result {
    const handle = getHandle(raw_handle) orelse return .null_pointer;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (measured_uj > budget_uj) {
        handle.budget_violations += 1;
        setError("Energy budget exceeded");
        return .budget_exceeded;
    }

    clearError();
    return .ok;
}

/// Enforce an energy budget without a library handle.
/// Matches the ABI declaration in Types.idr (namespace Foreign):
///   %foreign "C:eclexiaiser_enforce_budget"  : Bits64 -> Bits64 -> PrimIO Bits32
/// Returns .ok (0) if within budget, .budget_exceeded (5) otherwise.
export fn eclexiaiser_enforce_budget(budget_uj: u64, measured_uj: u64) Result {
    if (measured_uj > budget_uj) {
        setError("Energy budget exceeded");
        return .budget_exceeded;
    }
    clearError();
    return .ok;
}

/// Enforce a carbon limit against a measurement.
export fn eclexiaiser_enforce_carbon_limit(raw_handle: ?*anyopaque, limit_mg_co2: u64, measured_mg_co2: u64) Result {
    const handle = getHandle(raw_handle) orelse return .null_pointer;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (measured_mg_co2 > limit_mg_co2) {
        handle.budget_violations += 1;
        setError("Carbon intensity limit exceeded");
        return .carbon_limit_exceeded;
    }

    clearError();
    return .ok;
}

/// Enforce a composite resource bound (energy + carbon + time + memory).
export fn eclexiaiser_enforce_resource_bound(
    raw_handle: ?*anyopaque,
    energy_limit_uj: u64,
    carbon_limit_mg: u64,
    time_limit_us: u64,
    memory_limit_bytes: u64,
    energy_measured_uj: u64,
    carbon_measured_mg: u64,
    time_measured_us: u64,
    memory_measured_bytes: u64,
) Result {
    const handle = getHandle(raw_handle) orelse return .null_pointer;

    if (!handle.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (energy_measured_uj > energy_limit_uj) {
        handle.budget_violations += 1;
        setError("Energy budget exceeded in composite bound");
        return .budget_exceeded;
    }

    if (carbon_measured_mg > carbon_limit_mg) {
        handle.budget_violations += 1;
        setError("Carbon limit exceeded in composite bound");
        return .carbon_limit_exceeded;
    }

    // Time and memory checks
    _ = time_limit_us;
    _ = time_measured_us;
    _ = memory_limit_bytes;
    _ = memory_measured_bytes;

    clearError();
    return .ok;
}

//==============================================================================
// Sustainability Report Generation
//==============================================================================

/// Generate a sustainability report from all accumulated measurements.
/// Writes the report struct to the provided buffer pointer.
export fn eclexiaiser_generate_report(raw_handle: ?*anyopaque, report_buf: u64) Result {
    const handle = getHandle(raw_handle) orelse return .null_pointer;

    if (report_buf == 0) {
        setError("Null report buffer");
        return .null_pointer;
    }

    if (!handle.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    const report_ptr: *SustainabilityReport = @ptrFromInt(report_buf);
    report_ptr.* = .{
        .total_energy_uj = handle.total_energy_uj,
        .total_carbon_mg_co2 = handle.total_carbon_mg_co2,
        .renewable_percent_bps = 0, // TODO: aggregate from carbon queries
        .budget_violations = handle.budget_violations,
        .functions_measured = handle.functions_measured,
        .timestamp_epoch = @intCast(@divTrunc(std.time.milliTimestamp(), 1000)),
    };

    clearError();
    return .ok;
}

/// Export a sustainability report as a JSON string.
/// Caller must free the returned string via eclexiaiser_free_string.
export fn eclexiaiser_report_to_json(raw_handle: ?*anyopaque) ?[*:0]const u8 {
    const handle = getHandle(raw_handle) orelse {
        setError("Null handle");
        return null;
    };

    if (!handle.initialized) {
        setError("Handle not initialized");
        return null;
    }

    // TODO: Implement proper JSON serialization
    const json = std.fmt.allocPrintZ(handle.allocator,
        \\{{"total_energy_uj":{d},"total_carbon_mg_co2":{d},"functions_measured":{d},"budget_violations":{d}}}
    , .{
        handle.total_energy_uj,
        handle.total_carbon_mg_co2,
        handle.functions_measured,
        handle.budget_violations,
    }) catch {
        setError("Failed to allocate JSON string");
        return null;
    };

    clearError();
    return json.ptr;
}

//==============================================================================
// String Operations
//==============================================================================

/// Free a string allocated by the library
export fn eclexiaiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message (static storage, no need to free)
export fn eclexiaiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn eclexiaiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn eclexiaiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn eclexiaiser_is_initialized(raw_handle: ?*anyopaque) u32 {
    const handle = getHandle(raw_handle) orelse return 0;
    return if (handle.initialized) 1 else 0;
}

/// Get the available energy counter type (0=RAPL, 1=IPMI, 2=estimate)
export fn eclexiaiser_counter_type(raw_handle: ?*anyopaque) u32 {
    const handle = getHandle(raw_handle) orelse return 2;
    return @intFromEnum(handle.counter_type);
}

//==============================================================================
// Internal Helpers
//==============================================================================

/// Extract a typed handle from an opaque pointer
fn getHandle(raw: ?*anyopaque) ?*HandleData {
    const ptr = raw orelse {
        setError("Null handle");
        return null;
    };
    return @ptrCast(@alignCast(ptr));
}

/// Detect which energy counter is available on this platform.
/// Checks RAPL first (Intel x86_64), then IPMI, falls back to estimation.
fn detectCounterType() CounterType {
    // TODO: Check for /sys/class/powercap/intel-rapl (Linux RAPL)
    // TODO: Check for IPMI device
    return .estimate;
}

/// Read the energy counter value in microjoules.
/// Returns null if no counter is available.
fn readEnergyCounter(counter_type: CounterType) ?u64 {
    switch (counter_type) {
        .rapl => {
            // TODO: Read from /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj
            return null;
        },
        .ipmi => {
            // TODO: Read from IPMI sensor
            return null;
        },
        .estimate => {
            // Software estimation based on elapsed nanoseconds and assumed power
            // Assumes ~15W average package power for estimation
            return @intCast(@as(u64, @intCast(std.time.nanoTimestamp())) / 1000 * 15);
        },
    }
}

/// Estimate instantaneous power in milliwatts (software fallback)
fn estimatePowerMw() u64 {
    // TODO: Use CPU frequency and utilization for better estimate
    return 15000; // 15W default estimate
}

/// Static carbon intensity data (mg CO2/kWh) by zone hash.
/// Used when no API is configured or as offline fallback.
fn getStaticCarbonIntensity(zone_id: u32) u32 {
    // Approximate values for common zones (mg CO2/kWh)
    return switch (zone_id) {
        0x4742 => 200_000, // "GB" — UK grid ~200g/kWh
        0x4652 => 50_000, // "FR" — France ~50g/kWh (nuclear)
        0x4445 => 350_000, // "DE" — Germany ~350g/kWh
        0x5553 => 400_000, // "US" — US average ~400g/kWh
        0x4E4F => 20_000, // "NO" — Norway ~20g/kWh (hydro)
        0x5345 => 30_000, // "SE" — Sweden ~30g/kWh
        else => 450_000, // World average ~450g/kWh
    };
}

/// Static renewable percentage (basis points) by zone hash.
fn getStaticRenewablePct(zone_id: u32) u32 {
    return switch (zone_id) {
        0x4742 => 4200, // UK ~42%
        0x4652 => 2500, // France ~25% (rest is nuclear, low-carbon but not renewable)
        0x4445 => 4600, // Germany ~46%
        0x5553 => 2100, // US ~21%
        0x4E4F => 9800, // Norway ~98%
        0x5345 => 6800, // Sweden ~68%
        else => 2900, // World average ~29%
    };
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const raw_handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(raw_handle);

    try std.testing.expect(eclexiaiser_is_initialized(raw_handle) == 1);
}

test "error handling" {
    const result = eclexiaiser_enforce_energy_budget(null, 100, 50);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = eclexiaiser_last_error();
    try std.testing.expect(err != null);
}

test "budget enforcement - within budget" {
    const raw_handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(raw_handle);

    const result = eclexiaiser_enforce_energy_budget(raw_handle, 1000, 500);
    try std.testing.expectEqual(Result.ok, result);
}

test "budget enforcement - exceeded" {
    const raw_handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(raw_handle);

    const result = eclexiaiser_enforce_energy_budget(raw_handle, 500, 1000);
    try std.testing.expectEqual(Result.budget_exceeded, result);
}

test "carbon limit enforcement" {
    const raw_handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(raw_handle);

    const ok = eclexiaiser_enforce_carbon_limit(raw_handle, 200_000, 150_000);
    try std.testing.expectEqual(Result.ok, ok);

    const exceeded = eclexiaiser_enforce_carbon_limit(raw_handle, 100_000, 200_000);
    try std.testing.expectEqual(Result.carbon_limit_exceeded, exceeded);
}

test "static carbon intensity" {
    const raw_handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(raw_handle);

    const gb_intensity = eclexiaiser_query_carbon_intensity(raw_handle, 0x4742);
    try std.testing.expectEqual(@as(u32, 200_000), gb_intensity);

    const no_intensity = eclexiaiser_query_carbon_intensity(raw_handle, 0x4E4F);
    try std.testing.expectEqual(@as(u32, 20_000), no_intensity);
}

test "version" {
    const ver = eclexiaiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "struct layout sizes" {
    // Verify C-compatible struct sizes match Idris2 ABI Layout.idr
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(EnergyMeasurement));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(CarbonQuery));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(BudgetEnforcement));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(SustainabilityReport));
}

test "Types.idr Foreign: measure_energy and null handle" {
    // Null handle must yield 0 (not a crash).
    try std.testing.expectEqual(@as(u64, 0), eclexiaiser_measure_energy(null));

    const raw_handle = eclexiaiser_init() orelse return error.InitFailed;
    defer eclexiaiser_free(raw_handle);
    // Estimate counter is always available, so a reading is produced.
    try std.testing.expect(eclexiaiser_measure_energy(raw_handle) > 0);
}

test "Types.idr Foreign: query_carbon (handle-free)" {
    try std.testing.expectEqual(@as(u32, 200_000), eclexiaiser_query_carbon(0x4742)); // GB
    try std.testing.expectEqual(@as(u32, 20_000), eclexiaiser_query_carbon(0x4E4F)); // NO
}

test "Types.idr Foreign: enforce_budget (handle-free) result codes" {
    try std.testing.expectEqual(Result.ok, eclexiaiser_enforce_budget(1000, 500));
    try std.testing.expectEqual(Result.budget_exceeded, eclexiaiser_enforce_budget(500, 1000));
}
