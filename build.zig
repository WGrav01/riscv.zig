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

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
