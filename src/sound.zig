const sdl = @import("sdl.zig");

pub const SoundChannels = enum(i32) {
    ch_any = -1,
    ch_player,
    ch_enemy,
};

pub const Sounds = struct {
    player_fire: [*c]sdl.Mix_Chunk,
};

pub fn initSounds() Sounds {
    return .{
        .player_fire = sdl.Mix_LoadWAV("assets/drum.wav"),
    };
}
