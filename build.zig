const std = @import("std");
const builtin = @import("builtin");

const Builder = std.build.Builder;

const game_pkg = std.build.Pkg{
    .name = "game",
    .source = .{ .path = "src/game.zig" },
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
    // exe.linkSystemLibrary("sdl2_gfx");
    exe.linkLibC();

    exe.install();

    exe.addPackage(game_pkg);

    const run_cmd = exe.run();
    const exe_step = b.step("run", b.fmt("run {s}.zig", .{name}));
    run_cmd.step.dependOn(b.getInstallStep());
    exe_step.dependOn(&run_cmd.step);

    return exe;
}

pub fn addTests(
    b: *Builder,
    target: std.zig.CrossTarget,
) void {
    const tests = .{
        "src/ecs/ecs.zig",
        "src/nav.zig",
    };
    const stepTest = b.step("test", "Run unit tests");
    inline for (tests) |path| {
        var exe = b.addTest(path);

        // SDL2 lib
        exe.addIncludePath("/usr/local/include/SDL2");
        exe.addLibraryPath("/usr/local/lib");
        exe.linkSystemLibrary("sdl2");
        exe.linkSystemLibrary("sdl2_image");
        exe.linkSystemLibrary("sdl2_mixer");
        // exe.linkSystemLibrary("sdl2_gfx");
        exe.linkLibC();

        exe.addPackage(game_pkg);

        exe.setTarget(target);
        exe.setBuildMode(b.standardReleaseOptions());
        stepTest.dependOn(&exe.step);
    }
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    var exe = createExe(b, target, "run", game_pkg.source.path);
    b.default_step.dependOn(&exe.step);

    addTests(b, target);
}
