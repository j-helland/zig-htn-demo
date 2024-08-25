pub usingnamespace @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    //    // @cInclude("SDL2/SDL_mixer.h");
});

const std = @import("std");

const gamestate = @import("gamestate.zig");
const settings = @import("settings.zig");
const sdl = @This();

pub fn initSDL(state: *gamestate.GameState) !void {
    const rendererFlags = sdl.SDL_RENDERER_ACCELERATED;
    const windowFlags = sdl.SDL_WINDOW_RESIZABLE;

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) < 0) {
        return error.SDLInitFailed;
    }

    // Window
    state.window = sdl.SDL_CreateWindow(
        "HTN Demo",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        settings.DEFAULT_WINDOW_WIDTH,
        settings.DEFAULT_WINDOW_HEIGHT,
        windowFlags,
    ) orelse return error.SDLWindowInitFailed;

    // Renderer
    _ = sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_SCALE_QUALITY, "linear");
    state.renderer = sdl.SDL_CreateRenderer(state.window, -1, rendererFlags) orelse return error.SDLRendererInitFailed;

    // Image IO
    _ = sdl.IMG_Init(sdl.IMG_INIT_PNG);

    // // Sound
    // if (sdl.Mix_OpenAudio(44100, sdl.MIX_DEFAULT_FORMAT, 2, 1024) == -1) {
    //     return error.SDLMixerInitFailed;
    // }
    // _ = sdl.Mix_AllocateChannels(settings.MAX_SOUND_CHANNELS);
}

pub fn deinitSDL(state: *gamestate.GameState) void {
    sdl.SDL_DestroyRenderer(state.renderer);
    sdl.SDL_DestroyWindow(state.window);
}
