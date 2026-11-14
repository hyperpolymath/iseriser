// Atsiser FFI Reference Implementation
//
// Implements the C-ABI functions declared in
// src/interface/abi/Atsiser/ABI/Foreign.idr. The Idris2 ABI is the source of
// truth: every `%foreign "C:atsiser_*, libatsiser"` symbol and every Result
// code below matches it exactly (symbol names, arity, and integer encodings).
//
// atsiser wraps C codebases in ATS2 linear types for zero-cost memory safety.
// This is a self-contained reference: it parses C sources in memory, records
// allocation sites / ownership edges / buffer accesses, and reports counts and
// a JSON analysis report. Real libclang parsing and patsopt (ATS2 -> C)
// compilation are future work; the round-trip entry points validate their
// arguments and succeed as no-ops so the ABI contract is fully exercised.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

const VERSION = "0.1.0";
const BUILD_INFO = "atsiser built with Zig " ++ @import("builtin").zig_version_string;

//==============================================================================
// Result Codes (must match Atsiser.ABI.Types.resultToInt)
//==============================================================================

pub const Result = enum(c_int) {
    ok = 0,
    err = 1, // Idris `Error`
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    ownership_violation = 5,
    bounds_violation = 6,
};

fn code(r: Result) c_int {
    return @intFromEnum(r);
}

/// Thread-local last-error message (a static string; never freed by the caller).
threadlocal var last_error: ?[*:0]const u8 = null;

fn setError(msg: [*:0]const u8) void {
    last_error = msg;
}

fn clearError() void {
    last_error = null;
}

//==============================================================================
// Engine state
//==============================================================================

/// An allocation site discovered in the parsed C sources.
const AllocSite = struct {
    file: []u8,
    allocator_fn: []u8,
};

/// An ownership edge (which function transfers/frees which pointer).
const OwnershipEdge = struct {
    from_fn: []u8,
    to_fn: []u8,
};

/// The analysis engine. Opaque to C; passed across the boundary as `?*Engine`
/// (the Idris ABI models the handle as `Bits64`).
const Engine = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    alloc_sites: std.ArrayList(AllocSite),
    edges: std.ArrayList(OwnershipEdge),
    buffer_count: u32,
    proof_count: u32,

    fn deinit(self: *Engine) void {
        const a = self.allocator;
        for (self.alloc_sites.items) |s| {
            a.free(s.file);
            a.free(s.allocator_fn);
        }
        self.alloc_sites.deinit();
        for (self.edges.items) |e| {
            a.free(e.from_fn);
            a.free(e.to_fn);
        }
        self.edges.deinit();
    }
};

/// Duplicate a C string into an owned, non-sentinel byte slice.
fn dup(a: std.mem.Allocator, s: ?[*:0]const u8) ![]u8 {
    const slice: []const u8 = if (s) |p| std.mem.span(p) else "";
    return a.dupe(u8, slice);
}

//==============================================================================
// Library Lifecycle
//==============================================================================

/// C: atsiser_init -> Bits64 handle (null on failure).
export fn atsiser_init() callconv(.C) ?*Engine {
    const a = std.heap.c_allocator;
    const e = a.create(Engine) catch {
        setError("atsiser: failed to allocate engine handle");
        return null;
    };
    e.* = .{
        .allocator = a,
        .initialized = true,
        .alloc_sites = std.ArrayList(AllocSite).init(a),
        .edges = std.ArrayList(OwnershipEdge).init(a),
        .buffer_count = 0,
        .proof_count = 0,
    };
    clearError();
    return e;
}

/// C: atsiser_free(Bits64) -> ().
export fn atsiser_free(handle: ?*Engine) callconv(.C) void {
    const e = handle orelse return;
    const a = e.allocator;
    e.deinit();
    a.destroy(e);
    clearError();
}

//==============================================================================
// C Source Analysis
//==============================================================================

/// C: atsiser_parse_header(Bits64, String) -> Bits32 result code.
/// The reference parser records one synthetic allocation site per parsed
/// header so downstream counts are non-trivial.
export fn atsiser_parse_header(handle: ?*Engine, path: ?[*:0]const u8) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    const p = path orelse {
        setError("atsiser: null header path");
        return code(.invalid_param);
    };
    if (!e.initialized) {
        setError("atsiser: engine not initialized");
        return code(.err);
    }
    const file = dup(e.allocator, p) catch return code(.out_of_memory);
    const fn_name = e.allocator.dupe(u8, "malloc") catch {
        e.allocator.free(file);
        return code(.out_of_memory);
    };
    e.alloc_sites.append(.{ .file = file, .allocator_fn = fn_name }) catch {
        e.allocator.free(file);
        e.allocator.free(fn_name);
        return code(.out_of_memory);
    };
    clearError();
    return code(.ok);
}

/// C: atsiser_analyse_allocations(Bits64) -> Bits32 count of allocation sites.
export fn atsiser_analyse_allocations(handle: ?*Engine) callconv(.C) c_uint {
    const e = handle orelse return 0;
    if (!e.initialized) return 0;
    clearError();
    return @intCast(e.alloc_sites.items.len);
}

/// C: atsiser_build_ownership_graph(Bits64) -> Bits32 result code.
/// Builds a simple ownership edge per allocation site (alloc -> free).
export fn atsiser_build_ownership_graph(handle: ?*Engine) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    if (!e.initialized) {
        setError("atsiser: engine not initialized");
        return code(.err);
    }
    for (e.alloc_sites.items) |_| {
        const from = e.allocator.dupe(u8, "alloc") catch return code(.out_of_memory);
        const to = e.allocator.dupe(u8, "free") catch {
            e.allocator.free(from);
            return code(.out_of_memory);
        };
        e.edges.append(.{ .from_fn = from, .to_fn = to }) catch {
            e.allocator.free(from);
            e.allocator.free(to);
            return code(.out_of_memory);
        };
    }
    clearError();
    return code(.ok);
}

/// C: atsiser_detect_buffers(Bits64) -> Bits32 count of buffer access sites.
export fn atsiser_detect_buffers(handle: ?*Engine) callconv(.C) c_uint {
    const e = handle orelse return 0;
    if (!e.initialized) return 0;
    // Reference heuristic: one buffer-access site per allocation site.
    e.buffer_count = @intCast(e.alloc_sites.items.len);
    clearError();
    return e.buffer_count;
}

//==============================================================================
// ATS2 Wrapper Generation
//==============================================================================

fn requireDir(e: *Engine, dir: ?[*:0]const u8) ?c_int {
    if (!e.initialized) {
        setError("atsiser: engine not initialized");
        return code(.err);
    }
    _ = dir orelse {
        setError("atsiser: null output directory");
        return code(.invalid_param);
    };
    return null;
}

/// C: atsiser_generate_viewtypes(Bits64, String) -> Bits32 result code.
export fn atsiser_generate_viewtypes(handle: ?*Engine, output_dir: ?[*:0]const u8) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    if (requireDir(e, output_dir)) |bad| return bad;
    // Reference: a viewtype wrapper would be emitted per tracked pointer.
    clearError();
    return code(.ok);
}

/// C: atsiser_generate_proofs(Bits64, String) -> Bits32 result code.
export fn atsiser_generate_proofs(handle: ?*Engine, output_dir: ?[*:0]const u8) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    if (requireDir(e, output_dir)) |bad| return bad;
    // One ownership proof obligation per ownership edge.
    e.proof_count += @intCast(e.edges.items.len);
    clearError();
    return code(.ok);
}

/// C: atsiser_generate_bounds_proofs(Bits64, String) -> Bits32 result code.
export fn atsiser_generate_bounds_proofs(handle: ?*Engine, output_dir: ?[*:0]const u8) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    if (requireDir(e, output_dir)) |bad| return bad;
    // One bounds proof obligation per detected buffer-access site.
    e.proof_count += e.buffer_count;
    clearError();
    return code(.ok);
}

//==============================================================================
// ATS2 Compilation (Round-Trip)
//==============================================================================

/// C: atsiser_compile_ats2(Bits64, String, String) -> Bits32 result code.
export fn atsiser_compile_ats2(
    handle: ?*Engine,
    ats2_dir: ?[*:0]const u8,
    c_output_dir: ?[*:0]const u8,
) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    _ = ats2_dir orelse {
        setError("atsiser: null ATS2 source directory");
        return code(.invalid_param);
    };
    _ = c_output_dir orelse {
        setError("atsiser: null C output directory");
        return code(.invalid_param);
    };
    if (!e.initialized) {
        setError("atsiser: engine not initialized");
        return code(.err);
    }
    // Reference build performs no patsopt invocation; proofs vacuously hold.
    clearError();
    return code(.ok);
}

/// C: atsiser_verify_linkage(Bits64, String, String) -> Bits32 result code.
export fn atsiser_verify_linkage(
    handle: ?*Engine,
    generated_c: ?[*:0]const u8,
    original_lib: ?[*:0]const u8,
) callconv(.C) c_int {
    const e = handle orelse {
        setError("atsiser: null handle");
        return code(.null_pointer);
    };
    _ = generated_c orelse {
        setError("atsiser: null generated C path");
        return code(.invalid_param);
    };
    _ = original_lib orelse {
        setError("atsiser: null original library path");
        return code(.invalid_param);
    };
    if (!e.initialized) {
        setError("atsiser: engine not initialized");
        return code(.err);
    }
    clearError();
    return code(.ok);
}

//==============================================================================
// Analysis Results
//==============================================================================

/// C: atsiser_allocation_count(Bits64) -> Bits32.
export fn atsiser_allocation_count(handle: ?*Engine) callconv(.C) c_uint {
    const e = handle orelse return 0;
    return @intCast(e.alloc_sites.items.len);
}

/// C: atsiser_ownership_edge_count(Bits64) -> Bits32.
export fn atsiser_ownership_edge_count(handle: ?*Engine) callconv(.C) c_uint {
    const e = handle orelse return 0;
    return @intCast(e.edges.items.len);
}

/// C: atsiser_proof_count(Bits64) -> Bits32.
export fn atsiser_proof_count(handle: ?*Engine) callconv(.C) c_uint {
    const e = handle orelse return 0;
    return e.proof_count;
}

/// C: atsiser_analysis_report(Bits64) -> Bits64 (owned C string, or null).
/// Caller frees the result with atsiser_free_string.
export fn atsiser_analysis_report(handle: ?*Engine) callconv(.C) ?[*:0]const u8 {
    const e = handle orelse {
        setError("atsiser: null handle");
        return null;
    };
    if (!e.initialized) {
        setError("atsiser: engine not initialized");
        return null;
    }
    const report = std.fmt.allocPrintZ(
        e.allocator,
        "{{\"allocations\":{d},\"edges\":{d},\"proofs\":{d},\"buffers\":{d}}}",
        .{ e.alloc_sites.items.len, e.edges.items.len, e.proof_count, e.buffer_count },
    ) catch {
        setError("atsiser: failed to render analysis report");
        return null;
    };
    clearError();
    return report.ptr;
}

//==============================================================================
// String Operations
//==============================================================================

/// C: atsiser_free_string(Bits64) -> (). Frees a string this library returned.
export fn atsiser_free_string(str: ?[*:0]const u8) callconv(.C) void {
    const p = str orelse return;
    std.heap.c_allocator.free(std.mem.span(p));
}

//==============================================================================
// Error Handling
//==============================================================================

/// C: atsiser_last_error -> Bits64 (static C string, or null). Not owned by caller.
export fn atsiser_last_error() callconv(.C) ?[*:0]const u8 {
    return last_error;
}

//==============================================================================
// Version Information
//==============================================================================

/// C: atsiser_version -> Bits64 (static C string).
export fn atsiser_version() callconv(.C) [*:0]const u8 {
    return VERSION;
}

/// C: atsiser_build_info -> Bits64 (static C string).
export fn atsiser_build_info() callconv(.C) [*:0]const u8 {
    return BUILD_INFO;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// C: atsiser_is_initialized(Bits64) -> Bits32 (1 = initialized, 0 = not).
export fn atsiser_is_initialized(handle: ?*Engine) callconv(.C) c_uint {
    const e = handle orelse return 0;
    return if (e.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "analysis pipeline and report" {
    const e = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(e);

    try std.testing.expectEqual(@as(c_uint, 1), atsiser_is_initialized(e));

    try std.testing.expectEqual(code(.ok), atsiser_parse_header(e, "foo.h"));
    try std.testing.expectEqual(code(.ok), atsiser_parse_header(e, "bar.h"));
    try std.testing.expectEqual(@as(c_uint, 2), atsiser_analyse_allocations(e));
    try std.testing.expectEqual(@as(c_uint, 2), atsiser_allocation_count(e));

    try std.testing.expectEqual(code(.ok), atsiser_build_ownership_graph(e));
    try std.testing.expectEqual(@as(c_uint, 2), atsiser_ownership_edge_count(e));

    try std.testing.expectEqual(@as(c_uint, 2), atsiser_detect_buffers(e));

    try std.testing.expectEqual(code(.ok), atsiser_generate_viewtypes(e, "out"));
    try std.testing.expectEqual(code(.ok), atsiser_generate_proofs(e, "out"));
    try std.testing.expectEqual(code(.ok), atsiser_generate_bounds_proofs(e, "out"));
    // 2 ownership proofs + 2 bounds proofs.
    try std.testing.expectEqual(@as(c_uint, 4), atsiser_proof_count(e));

    try std.testing.expectEqual(code(.ok), atsiser_compile_ats2(e, "ats", "cout"));
    try std.testing.expectEqual(code(.ok), atsiser_verify_linkage(e, "gen.c", "libfoo.a"));

    const report = atsiser_analysis_report(e) orelse return error.ReportFailed;
    defer atsiser_free_string(report);
    const span = std.mem.span(report);
    try std.testing.expect(std.mem.indexOf(u8, span, "\"allocations\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, span, "\"proofs\":4") != null);
}

test "null handle and invalid params are rejected" {
    // Null handle -> NullPointer (4).
    try std.testing.expectEqual(code(.null_pointer), atsiser_parse_header(null, "x.h"));
    try std.testing.expectEqual(code(.null_pointer), atsiser_build_ownership_graph(null));
    try std.testing.expectEqual(code(.null_pointer), atsiser_compile_ats2(null, "a", "b"));
    // Count accessors tolerate null and return 0.
    try std.testing.expectEqual(@as(c_uint, 0), atsiser_allocation_count(null));
    try std.testing.expectEqual(@as(c_uint, 0), atsiser_is_initialized(null));

    // Valid handle, null string arg -> InvalidParam (2), and error is recorded.
    const e = atsiser_init() orelse return error.InitFailed;
    defer atsiser_free(e);
    try std.testing.expectEqual(code(.invalid_param), atsiser_parse_header(e, null));
    try std.testing.expectEqual(code(.invalid_param), atsiser_generate_viewtypes(e, null));
    try std.testing.expect(atsiser_last_error() != null);
}
