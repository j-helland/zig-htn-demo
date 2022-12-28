const sdl = @import("../sdl.zig");
const math = @import("../math.zig");

pub const Entity = struct {
    health: i32 = 0,
    reload: i32 = 0,
    texture: *sdl.SDL_Texture = undefined,
    frame: usize = 0,
};

pub const Player = struct {
    isAlive: bool = true,
};

pub const Camera = struct {
    rect: math.Rect(f32),

    pub fn normalize(self: *const Camera, p: math.Vec2(f32)) math.Vec2(f32) {
        return .{
            .x = p.x - self.rect.x,
            .y = p.y - self.rect.y,
        };
    }

    pub fn unnormalize(self: *const Camera, p: math.Vec2(f32)) math.Vec2(f32) {
        return .{
            .x = p.x + self.rect.x,
            .y = p.y + self.rect.y,
        };
    }
};

pub const Enemy = struct {};

pub const Wall = struct {
    rect: sdl.SDL_Rect,
    color: struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
};

pub const AIFlanker = struct {
    isSeen: bool = false,
};

pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    scale: f32 = 1,
};

