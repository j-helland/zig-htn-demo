const std = @import("std");
const builtin = @import("builtin");

const GAME_NAME = "game";
const GAME_PATH = "src/game.zig";

const Options = struct {
    optimize: std.builtin.Mode,
    target: std.Build.ResolvedTarget,
};

pub fn addTests(
    b: *std.Build,
    options: *const Options,
) void {
    const tests = .{
        "src/queue.zig",
        "src/ecs/ecs.zig",
        "src/htn/domain.zig",
        "src/htn/planner.zig",
        "src/htn/worldstate.zig",
        "src/nav.zig",
        "src/math.zig",
    };
    const stepTest = b.step("test", "Run unit tests");
    inline for (tests) |path| {
        var exe = b.addTest(.{
            .root_source_file = .{ .cwd_relative = path },
            .target = options.target,
            .optimize = options.optimize,
        });

        // SDL2 lib
        exe.addIncludePath(.{ .cwd_relative = "/usr/local/include/SDL2" });
        exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        exe.linkSystemLibrary("sdl2");
        exe.linkSystemLibrary("sdl2_image");
        // exe.linkSystemLibrary("sdl2_mixer");
        exe.linkLibC();

        const game_module = b.addModule(GAME_NAME, .{ .root_source_file = .{ .cwd_relative = GAME_PATH } });
        exe.root_module.addImport(GAME_NAME, game_module);

        stepTest.dependOn(&exe.step);
    }
}

pub fn build(b: *std.Build) void {
    const options: Options = .{
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .x86_64 } }),
    };
    //var exe = createExe(b, "run", "src/game.zig");
    const name = "run";
    const source = "src/game.zig";

    var exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .cwd_relative = source },
        .target = options.target,
        .optimize = options.optimize,
    });

    addDependencies(b, options, exe);

    b.installArtifact(exe);

    const game_module = b.addModule(GAME_NAME, .{ .root_source_file = .{ .cwd_relative = GAME_PATH } });
    exe.root_module.addImport(GAME_NAME, game_module);

    const run_cmd = b.addRunArtifact(exe);
    const exe_step = b.step("run", b.fmt("run {s}.zig", .{name}));
    run_cmd.step.dependOn(b.getInstallStep());
    exe_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);

    addTests(b, &options);
}

fn addDependencies(_: *std.Build, _: Options, exe: *std.Build.Step.Compile) void {
    // SDL2 lib
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/include/SDL2" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.linkSystemLibrary("sdl2");
    exe.linkSystemLibrary("sdl2_image");
    //// exe.linkSystemLibrary("sdl2_mixer");
    exe.linkLibC();
}

fn createTestExecutable(b: *std.Build, opts: Options) void {
    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    addDependencies(b, opts, exe_unit_tests);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
