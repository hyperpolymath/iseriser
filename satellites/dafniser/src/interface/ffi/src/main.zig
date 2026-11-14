// Dafniser FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/abi/Foreign.idr.
// All types and layouts must match the Idris2 ABI definitions in Types.idr and Layout.idr.
//
// The FFI surface covers:
//   1. Library lifecycle (init, free, version)
//   2. Specification loading from TOML manifests
//   3. Dafny code generation from SpecTree
//   4. Z3 verification invocation and result querying
//   5. Target language compilation (C#, Java, Go, Python, JavaScript)
//
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

// Version information (keep in sync with Cargo.toml)
const VERSION = "0.1.0";
const BUILD_INFO = "dafniser built with Zig " ++ @import("builtin").zig_version_string;

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
};

/// Dafny target languages (must match Idris2 DafnyTarget type)
pub const DafnyTarget = enum(u32) {
    csharp = 0,
    java = 1,
    go = 2,
    python = 3,
    javascript = 4,
};

/// Verification result tag (must match Idris2 VerificationResult constructors)
pub const VerificationTag = enum(u32) {
    verified = 0,
    counterexample = 1,
    timeout = 2,
    internal_error = 3,
};

/// A single verification result entry
pub const VerificationEntry = struct {
    tag: VerificationTag,
    function_name: ?[*:0]const u8,
    detail: u64, // timeMs for Verified/Timeout, or pointer to clause string
    witness: ?[*:0]const u8, // only valid when tag == counterexample
};

/// Library handle (opaque to prevent direct access from C callers)
pub const Handle = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    // Spec tree state (populated after dafniser_load_spec)
    spec_loaded: bool,
    // Verification results (populated after dafniser_verify)
    verification_results: ?[]VerificationEntry,
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the dafniser library.
/// Returns a handle, or null on failure.
export fn dafniser_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    handle.* = .{
        .allocator = allocator,
        .initialized = true,
        .spec_loaded = false,
        .verification_results = null,
    };

    clearError();
    return handle;
}

/// Free the dafniser library handle and all associated resources.
export fn dafniser_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    // Free verification results if present
    if (h.verification_results) |results| {
        allocator.free(results);
    }

    h.initialized = false;
    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Specification Loading
//==============================================================================

/// Load a specification tree from a TOML manifest file.
/// Returns a handle to the parsed SpecTree, or null on parse failure.
export fn dafniser_load_spec(handle: ?*Handle, manifest_path: ?[*:0]const u8) ?*Handle {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    _ = manifest_path orelse {
        setError("Null manifest path");
        return null;
    };

    // TODO: Parse TOML manifest and build SpecTree
    // For now, mark spec as loaded (stub)
    h.spec_loaded = true;

    clearError();
    return h;
}

/// Free a previously loaded spec tree.
export fn dafniser_free_spec(handle: ?*Handle) void {
    const h = handle orelse return;
    h.spec_loaded = false;
    clearError();
}

/// Compile and verify the loaded spec in one step.
/// (ABI: Dafniser.ABI.Types Foreign.prim__compile — `Bits64 -> Bits32`.)
/// Returns 0 on success, non-zero on failure.
export fn dafniser_compile(handle: ?*Handle) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };
    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }
    // TODO: invoke `dafny verify` over the loaded spec (Phase 4 in ROADMAP).
    clearError();
    return .ok;
}

//==============================================================================
// Dafny Code Generation
//==============================================================================

/// Generate Dafny source code from a loaded spec tree.
/// Writes .dfy files to the output directory.
/// Returns 0 on success, non-zero on failure.
export fn dafniser_generate_dafny(handle: ?*Handle, output_dir: ?[*:0]const u8) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    if (!h.spec_loaded) {
        setError("No spec loaded — call dafniser_load_spec first");
        return .invalid_param;
    }

    _ = output_dir orelse {
        setError("Null output directory");
        return .null_pointer;
    };

    // TODO: Generate .dfy files with requires/ensures/invariant/decreases/ghost/lemma
    // This is the core codegen step (Phase 2 in ROADMAP.adoc)

    clearError();
    return .ok;
}

//==============================================================================
// Z3 Verification
//==============================================================================

/// Invoke the Dafny verifier (Z3 backend) on generated .dfy files.
/// Returns a handle to the verification results, or null on failure.
export fn dafniser_verify(handle: ?*Handle, dafny_dir: ?[*:0]const u8) ?*Handle {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    _ = dafny_dir orelse {
        setError("Null dafny directory");
        return null;
    };

    // TODO: Invoke `dafny verify` subprocess and parse Z3 output
    // This is the core verification step (Phase 3 in ROADMAP.adoc)

    clearError();
    return h;
}

/// Query the number of verification results.
export fn dafniser_result_count(handle: ?*Handle) u32 {
    const h = handle orelse return 0;

    if (h.verification_results) |results| {
        return @intCast(results.len);
    }
    return 0;
}

/// Query the verification status of a specific function by index.
/// Returns the tag: 0=Verified, 1=Counterexample, 2=Timeout, 3=InternalError
export fn dafniser_result_status(handle: ?*Handle, index: u32) u32 {
    const h = handle orelse return 3; // InternalError

    if (h.verification_results) |results| {
        if (index < results.len) {
            return @intFromEnum(results[index].tag);
        }
    }
    return 3; // InternalError for out-of-bounds
}

/// Get the counterexample witness string for a failed verification.
/// Returns null if the result at the given index is not a Counterexample.
export fn dafniser_result_witness(handle: ?*Handle, index: u32) ?[*:0]const u8 {
    const h = handle orelse return null;

    if (h.verification_results) |results| {
        if (index < results.len) {
            const entry = results[index];
            if (entry.tag == .counterexample) {
                return entry.witness;
            }
        }
    }
    return null;
}

//==============================================================================
// Target Language Compilation
//==============================================================================

/// Compile verified Dafny to a target language.
/// Target: 0=C#, 1=Java, 2=Go, 3=Python, 4=JavaScript
/// Returns 0 on success, non-zero on failure.
export fn dafniser_compile_target(handle: ?*Handle, dafny_dir: ?[*:0]const u8, target: u32) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    _ = dafny_dir orelse {
        setError("Null dafny directory");
        return .null_pointer;
    };

    const dafny_target = std.meta.intToEnum(DafnyTarget, target) catch {
        setError("Invalid target language");
        return .invalid_param;
    };

    // TODO: Invoke `dafny build --target:<flag>` for the selected target
    // This is Phase 4 in ROADMAP.adoc
    _ = dafny_target;

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (example)
/// Caller must free the returned string via dafniser_free_string
export fn dafniser_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    const result = h.allocator.dupeZ(u8, "dafniser result") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn dafniser_free_string(str: ?[*:0]const u8) void {
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
export fn dafniser_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn dafniser_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn dafniser_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn dafniser_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    try std.testing.expect(dafniser_is_initialized(handle) == 1);
}

test "error handling" {
    const result = dafniser_generate_dafny(null, null);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = dafniser_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = dafniser_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}

test "spec loading requires init" {
    const result = dafniser_load_spec(null, null);
    try std.testing.expect(result == null);
}

test "generate requires loaded spec" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const result = dafniser_generate_dafny(handle, "output");
    try std.testing.expectEqual(Result.invalid_param, result);
}

test "target compilation enum bounds" {
    const handle = dafniser_init() orelse return error.InitFailed;
    defer dafniser_free(handle);

    const result = dafniser_compile_target(handle, "dir", 99);
    try std.testing.expectEqual(Result.invalid_param, result);
}
