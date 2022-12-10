const game = @import("game");

const sdl = @import("sdl.zig");
const e = @import("errors.zig");
const settings = @import("settings.zig");
const structs = @import("structs.zig");

pub fn initSDL(state: *game.GameState) !void {
    const rendererFlags = sdl.SDL_RENDERER_ACCELERATED;
    const windowFlags = 0;

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) < 0) {
        return e.SDLError.SDLInitFailed;
    }

    // Window
    state.window = sdl.SDL_CreateWindow(
        "Raw Dog",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        settings.DEFAULT_WINDOW_WIDTH,
        settings.DEFAULT_WINDOW_HEIGHT,
        windowFlags,
    ) orelse return e.SDLError.WindowInitFailed;

    // Renderer
    _ = sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_SCALE_QUALITY, "linear");
    state.renderer = sdl.SDL_CreateRenderer(state.window, -1, rendererFlags) orelse return e.SDLError.RendererInitFailed;

    // Image IO
    _ = sdl.IMG_Init(sdl.IMG_INIT_PNG);

    // Sound
    if (sdl.Mix_OpenAudio(44100, sdl.MIX_DEFAULT_FORMAT, 2, 1024) == -1) {
        return e.SDLError.MixerInitFailed;
    }
    _ = sdl.Mix_AllocateChannels(settings.MAX_SOUND_CHANNELS);
}

pub fn deinitSDL(state: *game.GameState) void {
    sdl.SDL_DestroyRenderer(state.renderer);
    sdl.SDL_DestroyWindow(state.window);
}
