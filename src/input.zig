const game = @import("game");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");

pub const Event = enum {
    exit,
    ok,
};

pub fn handleInput(state: *game.GameState) Event {
    var event: sdl.SDL_Event = undefined;

    while (sdl.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            sdl.SDL_QUIT => return .exit,
            sdl.SDL_KEYDOWN => handleKeyDown(&event.key, state),
            sdl.SDL_KEYUP => handleKeyUp(&event.key, state),
            else => {},
        }
    }
    return .ok;
}

pub fn handleKeyDown(event: *sdl.SDL_KeyboardEvent, state: *game.GameState) void {
    if (event.repeat == 0 and event.keysym.scancode < settings.MAX_KEYBOARD_KEYS) {
        state.keyboard[event.keysym.scancode] = true;
    }
}

pub fn handleKeyUp(event: *sdl.SDL_KeyboardEvent, state: *game.GameState) void {
    if (event.repeat == 0 and event.keysym.scancode < settings.MAX_KEYBOARD_KEYS) {
        state.keyboard[event.keysym.scancode] = false;
    }
}
