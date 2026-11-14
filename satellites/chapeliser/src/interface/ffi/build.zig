// Chapeliser FFI Build Configuration
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared library (.so, .dylib, .dll).
    // NOTE: no explicit `.version` — a versioned shared library trips a null
    // deref in Zig 0.14's InstallArtifact (major_only_filename); Chapel links
    // the static archive anyway.
    const lib = b.addSharedLibrary(.{
        .name = "chapeliser_ffi",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC(); // main.zig uses std.heap.c_allocator

    // Static library (.a) — Chapel links against this
    const lib_static = b.addStaticLibrary(.{
        .name = "chapeliser_ffi",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_static.linkLibC();

    b.installArtifact(lib);
    b.installArtifact(lib_static);

    // Unit tests (from main.zig)
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.linkLibC();

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.linkLibC();
    integration_tests.linkLibrary(lib);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);
}
