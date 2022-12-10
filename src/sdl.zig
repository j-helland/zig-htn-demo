const std = @import("std");

pub usingnamespace @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_sound.h");
    @cInclude("SDL2/SDL_mixer.h");
});

