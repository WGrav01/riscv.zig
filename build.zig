const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_emit_bin = b.option(bool, "no-emit-bin", "Whether to not emit a binary (useful if emitting docs only)") orelse false;

    const lib = b.addLibrary(.{
        .name = "riscv",
        .root_module = b.addModule("riscv", .{
            .root_source_file = b.path("lib/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (!no_emit_bin) b.installArtifact(lib);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    const app = b.addExecutable(.{
        .name = "riscv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "riscv", .module = lib.root_module },
            },
        }),
    });

    if (!no_emit_bin) b.installArtifact(app);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(app);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_filter = b.option([]const []const u8, "test-filter", "Skip tests that don't match the specified filters") orelse &.{};

    const lib_test_mod = b.addModule("lib_tests", .{
        .root_source_file = b.path("lib/tests/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "riscv", .module = lib.root_module },
        },
    });
    const lib_tests = b.addTest(.{
        .root_module = lib_test_mod,
        .filters = test_filter,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const lib_test_step = b.step("lib-test", "Run all library tests");
    lib_test_step.dependOn(&run_lib_tests.step);

    const app_test_mod = b.addModule("app_tests", .{
        .root_source_file = b.path("app/tests/root.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "riscv-app", .module = app.root_module },
        },
    });
    const app_tests = b.addTest(.{
        .root_module = app_test_mod,
        .filters = test_filter,
    });
    const run_app_tests = b.addRunArtifact(app_tests);
    const app_test_step = b.step("app-test", "Run all application tests");
    app_test_step.dependOn(&run_app_tests.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_app_tests.step);
}
