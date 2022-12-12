const std = @import("std");
const sdl = @import("sdl.zig");
const settings = @import("settings.zig");

pub const Entity = struct {
    // x: f32 = 0,
    // y: f32 = 0,
    // x0: f32 = 0,
    // y0: f32 = 0,
    // dx: f32 = 0,
    // dy: f32 = 0,
    // w: f32 = 0,
    // h: f32 = 0,
    health: i32 = 0,
    reload: i32 = 0,
    texture: *sdl.SDL_Texture = undefined,
    frame: usize = 0,
};

pub const Stage = struct {
    bullets: std.ArrayList(Entity) = undefined,
};
