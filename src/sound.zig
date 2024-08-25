const sdl = @import("sdl.zig");

pub var MUSIC: ?*sdl.Mix_Music = null;

pub const SoundChannels = enum(i32) {
    ch_any = -1,
    ch_player,
    ch_enemy,
};

pub const Sounds = struct {
    enemy_spawn: [*c]sdl.Mix_Chunk,
    rub_your_meat: [*c]sdl.Mix_Chunk,
    hehe_boi: [*c]sdl.Mix_Chunk,
};

pub fn initSounds() Sounds {
    return .{
        .enemy_spawn = sdl.Mix_LoadWAV("assets/drum.wav"),
        .rub_your_meat = sdl.Mix_LoadWAV("assets/rub-your-meat.wav"),
        .hehe_boi = sdl.Mix_LoadWAV("assets/hehe-boi.wav"),
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
    _ = sdl.Mix_PlayChannel(@intFromEnum(channel), s, 0);
}
