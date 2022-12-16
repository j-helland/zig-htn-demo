const sdl = @import("../../sdl.zig");
const zbt = @import("zbullet");

pub const ComponentTypes = .{
    Entity,
    Player,
    Enemy,
    Wall,
    Position,
    // Physics,
    AIFlanker,
};

pub const Entity = struct {
    health: i32 = 0,
    reload: i32 = 0,
    texture: *sdl.SDL_Texture = undefined,
    frame: usize = 0,
};

pub const Player = struct {};
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

pub const AIFlanker = struct {};

pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
    x0: f32 = 0,
    y0: f32 = 0,
    dx: f32 = 0,
    dy: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    scale: f32 = 1.0,
};

// pub const Physics = struct {
//     // body: zbt.Body,
// };
