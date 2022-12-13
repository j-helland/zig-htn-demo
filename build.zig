const std = @import("std");
const builtin = @import("builtin");

const zbullet = @import("lib/zig-gamedev/libs/zbullet/build.zig");
const zmath = @import("lib/zig-gamedev/libs/zmath/build.zig");

const Builder = std.build.Builder;

const game_pkg = std.build.Pkg{
    .name = "game",
    .source = .{ .path = "src/game.zig" },
};

const box2d_pkg = std.build.Pkg{
    .name = "box2d",
    .source = .{ .path = "lib/box2d.zig" },
};

pub fn createExe(
    b: *Builder,
    target: std.zig.CrossTarget,
    name: []const u8,
    source: []const u8,
) *std.build.LibExeObjStep {
    var exe = b.addExecutable(name, source);
    exe.setBuildMode(b.standardReleaseOptions());

    if (b.is_release) {
        if (target.isWindows()) {
            exe.subsystem = .Windows;
        } else if (builtin.os.tag == .macos and builtin.cpu.arch == std.Target.Cpu.Arch.aarch64) {
            exe.subsystem = .Posix;
        }
    }

    // SDL2 lib
    exe.addIncludePath("/usr/local/include/SDL2");
    exe.addLibraryPath("/usr/local/lib");
    exe.linkSystemLibrary("sdl2");
    exe.linkSystemLibrary("sdl2_image");
    exe.linkSystemLibrary("sdl2_mixer");
    exe.linkLibC();

    exe.install();

    // exe.addPackage(box2d_pkg);
    exe.addPackage(zbullet.pkg);
    exe.addPackage(zmath.pkg);
    exe.addPackage(game_pkg);

    zbullet.link(exe);

    const run_cmd = exe.run();
    const exe_step = b.step("run", b.fmt("run {s}.zig", .{name}));
    run_cmd.step.dependOn(b.getInstallStep());
    exe_step.dependOn(&run_cmd.step);

    return exe;
}

pub fn createTests(
    b: *Builder,
    target: std.zig.CrossTarget,
) *std.build.LibExeObjStep {
    var exe = b.addTest("src/ecs/ecs.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    return exe;
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    var exe = createExe(b, target, "run", game_pkg.source.path);
    b.default_step.dependOn(&exe.step);

    const exeTest = createTests(b, target);
    const stepTest = b.step("test", "Run unit tests");
    stepTest.dependOn(&exeTest.step);
}
