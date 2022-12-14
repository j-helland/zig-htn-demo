const sdl = @import("sdl.zig");

pub var MUSIC: ?*sdl.Mix_Music = null;

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

pub fn loadMusic(filename: [*c]const u8) void {
    if (MUSIC != null) {
        _ = sdl.Mix_HaltMusic();
        sdl.Mix_FreeMusic(MUSIC);
        MUSIC = null;
    }
    MUSIC = sdl.Mix_LoadMUS(filename);
}

pub fn playMusic(loop: bool) void {
    _ = sdl.Mix_PlayMusic(MUSIC, if (loop) -1 else 0);
}

pub fn playSound(s: [*c]sdl.Mix_Chunk, channel: SoundChannels) void {
    _ = sdl.Mix_PlayChannel(@enumToInt(channel), s, 0);
}
