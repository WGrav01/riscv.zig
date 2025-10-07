const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_emit_bin = b.option(bool, "no-emit-bin", "Whether to not emit a binary (useful if emitting docs only)") orelse false;
    const mod = b.addModule("riscv", .{
        .root_source_file = b.path("lib/root.zig"),
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "riscv",
        .root_module = mod,
    });

    if (!no_emit_bin) b.installArtifact(lib);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    const exe = b.addExecutable(.{
        .name = "riscv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("exe/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "riscv", .module = mod },
            },
        }),
    });

    if (!no_emit_bin) b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_filter = b.option([]const []const u8, "test-filter", "Filter to specific tests") orelse &[_][]const u8{};

    const lib_test_mod = b.addModule("lib_tests", .{
        .root_source_file = b.path("lib/tests/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "riscv", .module = mod },
        },
    });

    const tests = b.addTest(.{
        .root_module = lib_test_mod,
        .filters = test_filter,
    });

    const run_lib_tests = b.addRunArtifact(tests);

    const exe_test_mod = b.addModule("exe_tests", .{
        .root_source_file = b.path("exe/tests/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "riscv", .module = mod },
        },
    });

    const exe_tests = b.addTest(.{
        .root_module = exe_test_mod,
        .filters = test_filter,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
