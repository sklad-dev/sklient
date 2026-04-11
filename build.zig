const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version_str = b.option([]const u8, "version", "The release version") orelse "dev";

    const exe = b.addExecutable(.{
        .name = "sklient",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    const release_step = b.step("release", "Build for all release targets");
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
    };

    for (targets) |t| {
        const resolved_target = b.resolveTargetQuery(t);
        const target_name = b.fmt("sklient-{s}-{s}-{s}", .{
            version_str,
            @tagName(t.cpu_arch.?),
            @tagName(t.os_tag.?),
        });

        const target_exe = b.addExecutable(.{
            .name = target_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = resolved_target,
                .optimize = .ReleaseSafe,
            }),
        });

        const target_install = b.addInstallArtifact(target_exe, .{});
        release_step.dependOn(&target_install.step);
    }
}
