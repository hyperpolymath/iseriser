// Futharkiser FFI Build Configuration
//
// Builds the Zig FFI shared/static library that bridges between the host
// application and Futhark-compiled GPU kernels.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -----------------------------------------------------------------------
    // Shared library (.so / .dylib / .dll)
    // -----------------------------------------------------------------------
    const lib = b.addSharedLibrary(.{
        .name = "futharkiser",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.version = .{ .major = 0, .minor = 1, .patch = 0 };

    // -----------------------------------------------------------------------
    // Static library (.a)
    // -----------------------------------------------------------------------
    const lib_static = b.addStaticLibrary(.{
        .name = "futharkiser",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install artifacts
    b.installArtifact(lib);
    b.installArtifact(lib_static);

    // Install C header for interop
    const header = b.addInstallHeader(
        b.path("include/futharkiser.h"),
        "futharkiser.h",
    );
    b.getInstallStep().dependOn(&header.step);

    // -----------------------------------------------------------------------
    // Unit tests (test declarations inside src/main.zig)
    // -----------------------------------------------------------------------
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library unit tests");
    test_step.dependOn(&run_lib_tests.step);

    // -----------------------------------------------------------------------
    // Integration tests (test/integration_test.zig links against the library)
    // -----------------------------------------------------------------------
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.linkLibrary(lib);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // -----------------------------------------------------------------------
    // Documentation generation
    // -----------------------------------------------------------------------
    const docs = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const docs_step = b.step("docs", "Generate API documentation");
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    // -----------------------------------------------------------------------
    // Benchmark executable
    // -----------------------------------------------------------------------
    const bench = b.addExecutable(.{
        .name = "futharkiser-bench",
        .root_source_file = b.path("bench/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench.linkLibrary(lib);
    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
