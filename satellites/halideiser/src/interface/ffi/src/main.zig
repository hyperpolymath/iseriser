// Halideiser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions.
//
// The FFI provides pipeline construction, compilation, and execution functions
// that bridge Halide's C++ runtime to any language via the C ABI.
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "halideiser built with Zig " ++ @import("builtin").zig_version_string;

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
    compile_failed = 5,
    invalid_schedule = 6,
    dimension_mismatch = 7,
};

/// Hardware targets (must match HardwareTarget in Types.idr)
pub const HardwareTarget = enum(u32) {
    x86_sse = 0,
    x86_avx2 = 1,
    x86_avx512 = 2,
    arm_neon = 3,
    arm_sve = 4,
    cuda = 5,
    opencl = 6,
    metal = 7,
    vulkan = 8,
    webassembly = 9,
};

/// Pipeline stage types (must match PipelineStage tags in Types.idr)
pub const StageType = enum(u32) {
    gaussian_blur = 0,
    box_blur = 1,
    sharpen = 2,
    resize = 3,
    convolve = 4,
    sobel_edge = 5,
    canny_edge = 6,
    colour_convert = 7,
    histogram_eq = 8,
    brightness_contrast = 9,
    pointwise = 10,
    reduce = 11,
};

/// Schedule primitive types (must match SchedulePrimitive tags in Types.idr)
pub const ScheduleType = enum(u32) {
    tile = 0,
    vectorize = 1,
    parallelize = 2,
    compute_at = 3,
    store_at = 4,
    reorder = 5,
    unroll = 6,
    gpu_blocks = 7,
    gpu_threads = 8,
    split = 9,
    fuse = 10,
    prefetch = 11,
};

/// Pixel element types (must match PixelType in Types.idr)
pub const PixelType = enum(u32) {
    uint8 = 0,
    uint16 = 1,
    uint32 = 2,
    float32 = 3,
    float64 = 4,
};

/// A single pipeline stage with its parameters
const PipelineStage = struct {
    stage_type: StageType,
    param1: f64,
    param2: f64,
};

/// Buffer dimensions
const BufferDims = struct {
    width: u32,
    height: u32,
    channels: u32,
    frames: u32,
    elem_type: PixelType,
};

/// A schedule directive applied to a specific stage
const ScheduleDirective = struct {
    stage_index: u32,
    schedule_type: ScheduleType,
    param1: u32,
    param2: u32,
};

/// Pipeline context handle (opaque to C callers)
const PipelineContext = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    compiled: bool,
    stages: std.ArrayList(PipelineStage),
    schedules: std.ArrayList(ScheduleDirective),
    input_dims: ?BufferDims,
    target: ?HardwareTarget,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialise a Halide pipeline context.
/// Returns a pointer to the context, or null on failure.
export fn halideiser_init() ?*PipelineContext {
    const allocator = std.heap.c_allocator;

    const ctx = allocator.create(PipelineContext) catch {
        setError("Failed to allocate pipeline context");
        return null;
    };

    ctx.* = .{
        .allocator = allocator,
        .initialized = true,
        .compiled = false,
        .stages = std.ArrayList(PipelineStage).init(allocator),
        .schedules = std.ArrayList(ScheduleDirective).init(allocator),
        .input_dims = null,
        .target = null,
    };

    clearError();
    return ctx;
}

/// Release all resources associated with a pipeline context.
export fn halideiser_free(ctx: ?*PipelineContext) void {
    const c = ctx orelse return;
    const allocator = c.allocator;

    c.stages.deinit();
    c.schedules.deinit();
    c.initialized = false;
    c.compiled = false;

    allocator.destroy(c);
    clearError();
}

//==============================================================================
// Pipeline Construction
//==============================================================================

/// Add a processing stage to the pipeline.
/// Stages are executed in the order they are added.
export fn halideiser_add_stage(
    ctx: ?*PipelineContext,
    stage_tag: u32,
    param1: f64,
    param2: f64,
) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    if (c.compiled) {
        setError("Cannot add stages to a compiled pipeline");
        return .invalid_param;
    }

    const stage_type = std.meta.intToEnum(StageType, stage_tag) catch {
        setError("Invalid stage type tag");
        return .invalid_param;
    };

    c.stages.append(.{
        .stage_type = stage_type,
        .param1 = param1,
        .param2 = param2,
    }) catch {
        setError("Failed to allocate stage");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

//==============================================================================
// Buffer Configuration
//==============================================================================

/// Set input buffer dimensions for the pipeline.
export fn halideiser_set_input_buffer(
    ctx: ?*PipelineContext,
    width: u32,
    height: u32,
    channels: u32,
    frames: u32,
    elem_type: u32,
) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    if (width == 0 or height == 0 or channels == 0 or frames == 0) {
        setError("Buffer dimensions must be positive");
        return .invalid_param;
    }

    const ptype = std.meta.intToEnum(PixelType, elem_type) catch {
        setError("Invalid pixel type");
        return .invalid_param;
    };

    c.input_dims = .{
        .width = width,
        .height = height,
        .channels = channels,
        .frames = frames,
        .elem_type = ptype,
    };

    clearError();
    return .ok;
}

//==============================================================================
// Schedule Configuration
//==============================================================================

/// Set the hardware target for schedule generation.
export fn halideiser_set_target(
    ctx: ?*PipelineContext,
    target: u32,
) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    const hw_target = std.meta.intToEnum(HardwareTarget, target) catch {
        setError("Invalid hardware target");
        return .invalid_param;
    };

    c.target = hw_target;

    clearError();
    return .ok;
}

/// Apply a scheduling primitive to a pipeline stage.
export fn halideiser_apply_schedule(
    ctx: ?*PipelineContext,
    stage_index: u32,
    sched_tag: u32,
    param1: u32,
    param2: u32,
) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    if (stage_index >= c.stages.items.len) {
        setError("Stage index out of range");
        return .invalid_param;
    }

    const sched_type = std.meta.intToEnum(ScheduleType, sched_tag) catch {
        setError("Invalid schedule primitive tag");
        return .invalid_schedule;
    };

    c.schedules.append(.{
        .stage_index = stage_index,
        .schedule_type = sched_type,
        .param1 = param1,
        .param2 = param2,
    }) catch {
        setError("Failed to allocate schedule directive");
        return .out_of_memory;
    };

    clearError();
    return .ok;
}

//==============================================================================
// Pipeline Compilation
//==============================================================================

/// Compile the configured pipeline to native code for the target hardware.
/// Requires at least one stage, input dimensions, and a target to be set.
export fn halideiser_compile_pipeline(ctx: ?*PipelineContext) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    if (c.stages.items.len == 0) {
        setError("Pipeline has no stages");
        return .invalid_param;
    }

    if (c.input_dims == null) {
        setError("Input buffer dimensions not set");
        return .invalid_param;
    }

    if (c.target == null) {
        setError("Hardware target not set");
        return .invalid_param;
    }

    // TODO: Invoke Halide AOT compiler to generate native code.
    // This will:
    //   1. Build Halide::Func definitions from pipeline stages
    //   2. Apply scheduling directives
    //   3. Call Halide::compile_to_file() or compile_jit()
    //   4. Store the compiled artifact in the context

    c.compiled = true;
    clearError();
    return .ok;
}

//==============================================================================
// Pipeline Execution
//==============================================================================

/// Execute the compiled pipeline on input/output buffers.
/// The pipeline must be compiled before execution.
export fn halideiser_execute_pipeline(
    ctx: ?*PipelineContext,
    input_ptr: u64,
    output_ptr: u64,
    input_len: u32,
    output_len: u32,
) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    if (!c.compiled) {
        setError("Pipeline not compiled — call halideiser_compile_pipeline first");
        return .@"error";
    }

    if (input_ptr == 0 or output_ptr == 0) {
        setError("Null buffer pointer");
        return .null_pointer;
    }

    if (input_len == 0 or output_len == 0) {
        setError("Buffer length must be positive");
        return .invalid_param;
    }

    // TODO: Execute the compiled Halide pipeline.
    // This will:
    //   1. Wrap input_ptr/output_ptr as halide_buffer_t
    //   2. Call the compiled pipeline function
    //   3. Return the result code
    // NB: input_ptr/output_ptr/input_len/output_len are already validated above,
    // so they must not be discarded (Zig 0.14 rejects pointless discards).

    clearError();
    return .ok;
}

//==============================================================================
// Auto-Tuning
//==============================================================================

/// Run the auto-tuner to search for an optimal schedule.
/// Performs benchmark runs with varying tile sizes, loop orders, and parallelism.
export fn halideiser_autotune(
    ctx: ?*PipelineContext,
    max_trials: u32,
    timeout_ms: u32,
) Result {
    const c = ctx orelse {
        setError("Null pipeline context");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Pipeline context not initialised");
        return .@"error";
    }

    if (c.stages.items.len == 0) {
        setError("Pipeline has no stages to tune");
        return .invalid_param;
    }

    if (c.target == null) {
        setError("Hardware target not set");
        return .invalid_param;
    }

    // TODO: Implement auto-tuning loop.
    // This will:
    //   1. Generate candidate schedules (vary tile sizes, vectorise widths, etc.)
    //   2. Compile each candidate
    //   3. Benchmark each candidate on representative data
    //   4. Select the fastest schedule
    //   5. Apply the winning schedule to the context
    _ = max_trials;
    _ = timeout_ms;

    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message. Returns null if no error.
export fn halideiser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

/// Free a string allocated by the library.
export fn halideiser_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;
    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version string.
export fn halideiser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information (includes Zig compiler version).
export fn halideiser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if pipeline context is initialised.
export fn halideiser_is_initialized(ctx: ?*PipelineContext) u32 {
    const c = ctx orelse return 0;
    return if (c.initialized) 1 else 0;
}

/// Get the number of stages in the pipeline.
export fn halideiser_stage_count(ctx: ?*PipelineContext) u32 {
    const c = ctx orelse return 0;
    return @intCast(c.stages.items.len);
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    try std.testing.expect(halideiser_is_initialized(ctx) == 1);
}

test "add stages" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    // Add a Gaussian blur stage
    const r1 = halideiser_add_stage(ctx, 0, 1.5, 0.0);
    try std.testing.expectEqual(Result.ok, r1);

    // Add a sharpen stage
    const r2 = halideiser_add_stage(ctx, 2, 0.5, 1.0);
    try std.testing.expectEqual(Result.ok, r2);

    try std.testing.expectEqual(@as(u32, 2), halideiser_stage_count(ctx));
}

test "set buffer dimensions" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_input_buffer(ctx, 1920, 1080, 3, 1, 0);
    try std.testing.expectEqual(Result.ok, result);
}

test "reject zero dimensions" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_input_buffer(ctx, 0, 1080, 3, 1, 0);
    try std.testing.expectEqual(Result.invalid_param, result);
}

test "set target" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    const result = halideiser_set_target(ctx, 1); // x86_avx2
    try std.testing.expectEqual(Result.ok, result);
}

test "compile requires stages and target" {
    const ctx = halideiser_init() orelse return error.InitFailed;
    defer halideiser_free(ctx);

    // No stages yet
    const r1 = halideiser_compile_pipeline(ctx);
    try std.testing.expectEqual(Result.invalid_param, r1);
}

test "null handle returns error" {
    const result = halideiser_add_stage(null, 0, 1.0, 0.0);
    try std.testing.expectEqual(Result.null_pointer, result);
}

test "error handling" {
    _ = halideiser_add_stage(null, 0, 0.0, 0.0);

    const err = halideiser_last_error();
    try std.testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try std.testing.expect(err_str.len > 0);
    }
}

test "version" {
    const ver = halideiser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
