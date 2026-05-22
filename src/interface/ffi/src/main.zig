// Iseriser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions in Types.idr and Layout.idr.
//
// Iseriser is the meta-framework that generates new -iser projects. This FFI layer
// provides the low-level generation engine: language model parsing, template expansion,
// and artifact writing — all accessible via C ABI for cross-language interop.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

// Version information
const VERSION = "0.1.0";
const BUILD_INFO = "iseriser built with Zig " ++ @import("builtin").zig_version_string;

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
    invalid_language = 2,
    template_error = 3,
    output_error = 4,
    null_pointer = 5,
};

/// Type system features (must match TypeSystemFeature in Types.idr)
pub const TypeSystemFeature = enum(u8) {
    dependent_types = 0,
    linear_types = 1,
    refinement_types = 2,
    session_types = 3,
    algebraic_types = 4,
    array_types = 5,
    simple_types = 6,
    gradual_types = 7,
};

/// Compilation targets (must match CompilationTarget in Types.idr)
pub const CompilationTarget = enum(u8) {
    native_c = 0,
    beam = 1,
    jvm = 2,
    wasm = 3,
    javascript = 4,
    interpreted = 5,
    gpu = 6,
};

/// Parsed language model held in the generation context
const LanguageModel = struct {
    name: []const u8,
    features: []const TypeSystemFeature,
    target: CompilationTarget,
    primitives: []const []const u8,
    calling_convention: []const u8,
};

/// Generation context (opaque handle)
/// Layout must match GenerationContext in Layout.idr (48 bytes, 8-byte aligned)
const GenerationContext = struct {
    allocator: std.mem.Allocator,
    model: ?LanguageModel,
    templates_loaded: bool,
    artifacts_generated: u32,
    output_dir: ?[]const u8,
    initialized: bool,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the iseriser generation engine.
/// Returns a handle to the generation context, or null on failure.
export fn iseriser_init() ?*GenerationContext {
    const allocator = std.heap.c_allocator;

    const ctx = allocator.create(GenerationContext) catch {
        setError("Failed to allocate generation context");
        return null;
    };

    ctx.* = .{
        .allocator = allocator,
        .model = null,
        .templates_loaded = false,
        .artifacts_generated = 0,
        .output_dir = null,
        .initialized = true,
    };

    clearError();
    return ctx;
}

/// Free the generation context and all associated resources.
export fn iseriser_free(ctx: ?*GenerationContext) void {
    const c = ctx orelse return;
    const allocator = c.allocator;

    c.initialized = false;
    c.model = null;

    allocator.destroy(c);
    clearError();
}

//==============================================================================
// Language Model Operations
//==============================================================================

/// Load a language model from a TOML manifest file path.
/// Returns 0 on success, error code on failure.
export fn iseriser_load_language(ctx: ?*GenerationContext, manifest_path: ?[*:0]const u8) Result {
    const c = ctx orelse {
        setError("Null context handle");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Context not initialized");
        return .@"error";
    }

    _ = manifest_path orelse {
        setError("Null manifest path");
        return .null_pointer;
    };

    // TODO: Parse TOML manifest and populate c.model
    // For now, create a placeholder model
    c.model = LanguageModel{
        .name = "placeholder",
        .features = &[_]TypeSystemFeature{.simple_types},
        .target = .native_c,
        .primitives = &[_][]const u8{},
        .calling_convention = "c",
    };

    clearError();
    return .ok;
}

/// Get the name of the currently loaded language model.
/// Returns null if no model is loaded.
export fn iseriser_language_name(ctx: ?*GenerationContext) ?[*:0]const u8 {
    const c = ctx orelse {
        setError("Null context handle");
        return null;
    };

    const model = c.model orelse {
        setError("No language model loaded");
        return null;
    };

    const name_z = c.allocator.dupeZ(u8, model.name) catch {
        setError("Failed to allocate language name string");
        return null;
    };

    return name_z.ptr;
}

/// Get the number of type system features in the loaded language model.
export fn iseriser_feature_count(ctx: ?*GenerationContext) u32 {
    const c = ctx orelse return 0;
    const model = c.model orelse return 0;
    return @intCast(model.features.len);
}

//==============================================================================
// Template Expansion
//==============================================================================

/// Expand all templates for the loaded language model into the output directory.
/// Returns 0 on success, error code on failure.
export fn iseriser_expand_templates(ctx: ?*GenerationContext, output_dir: ?[*:0]const u8) Result {
    const c = ctx orelse {
        setError("Null context handle");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Context not initialized");
        return .@"error";
    }

    _ = c.model orelse {
        setError("No language model loaded — call iseriser_load_language first");
        return .invalid_language;
    };

    _ = output_dir orelse {
        setError("Null output directory");
        return .null_pointer;
    };

    // TODO: Expand Handlebars templates and write artifacts
    // For now, increment artifact count as a stub
    c.artifacts_generated = 17; // Placeholder: 17 files generated
    c.templates_loaded = true;

    clearError();
    return .ok;
}

/// Get the number of artifacts generated in the last expansion.
export fn iseriser_artifact_count(ctx: ?*GenerationContext) u32 {
    const c = ctx orelse return 0;
    return c.artifacts_generated;
}

//==============================================================================
// High-Level Repo Generation
//==============================================================================

/// Generate a complete -iser repository in one call.
/// Loads the language model from manifest_path, expands templates, writes to output_dir.
export fn iseriser_generate_repo(
    ctx: ?*GenerationContext,
    manifest_path: ?[*:0]const u8,
    output_dir: ?[*:0]const u8,
) Result {
    const c = ctx orelse {
        setError("Null context handle");
        return .null_pointer;
    };

    // Step 1: Load language model
    const load_result = iseriser_load_language(c, manifest_path);
    if (load_result != .ok) return load_result;

    // Step 2: Expand templates
    const expand_result = iseriser_expand_templates(c, output_dir);
    if (expand_result != .ok) return expand_result;

    clearError();
    return .ok;
}

//==============================================================================
// Validation
//==============================================================================

/// Validate a language model without generating output.
export fn iseriser_validate_language(ctx: ?*GenerationContext, manifest_path: ?[*:0]const u8) Result {
    const c = ctx orelse {
        setError("Null context handle");
        return .null_pointer;
    };

    if (!c.initialized) {
        setError("Context not initialized");
        return .@"error";
    }

    _ = manifest_path orelse {
        setError("Null manifest path");
        return .null_pointer;
    };

    // TODO: Parse and validate without storing
    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message.
/// Returns null if no error has occurred.
export fn iseriser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version string.
export fn iseriser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information string.
export fn iseriser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if the generation context is initialized.
export fn iseriser_is_initialized(ctx: ?*GenerationContext) u32 {
    const c = ctx orelse return 0;
    return if (c.initialized) 1 else 0;
}

/// Check if a language model is currently loaded in the context.
export fn iseriser_has_model(ctx: ?*GenerationContext) u32 {
    const c = ctx orelse return 0;
    return if (c.model != null) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    try std.testing.expect(iseriser_is_initialized(ctx) == 1);
    try std.testing.expect(iseriser_has_model(ctx) == 0);
}

test "load language model" {
    const ctx = iseriser_init() orelse return error.InitFailed;
    defer iseriser_free(ctx);

    const result = iseriser_load_language(ctx, "test.toml");
    try std.testing.expectEqual(Result.ok, result);
    try std.testing.expect(iseriser_has_model(ctx) == 1);
}

test "error handling on null context" {
    const result = iseriser_load_language(null, "test.toml");
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = iseriser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = iseriser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "generate repo with null context" {
    const result = iseriser_generate_repo(null, "test.toml", "/tmp/out");
    try std.testing.expectEqual(Result.null_pointer, result);
}
