const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");

const GameState = @import("gamestate.zig").GameState;
const math = @import("math.zig");

pub const Event = enum {
    exit,
    ok,
};

pub fn handleInput(state: *GameState) Event {
    var event: sdl.SDL_Event = undefined;

    while (sdl.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            sdl.SDL_QUIT => return .exit,
            sdl.SDL_KEYDOWN => handleKeyDown(&event.key, state),
            sdl.SDL_KEYUP => handleKeyUp(&event.key, state),
            sdl.SDL_MOUSEBUTTONUP => handleMouseUp(&event.button, state),
            sdl.SDL_MOUSEBUTTONDOWN => handleMouseDown(&event.button, state),
            else => {},
        }
    }
    return .ok;
}

pub fn handleKeyDown(event: *sdl.SDL_KeyboardEvent, state: *GameState) void {
    if (event.repeat == 0 and event.keysym.scancode < settings.MAX_KEYBOARD_KEYS) {
        state.keyboard[event.keysym.scancode] = true;
    }
}

pub fn handleKeyUp(event: *sdl.SDL_KeyboardEvent, state: *GameState) void {
    if (event.repeat == 0 and event.keysym.scancode < settings.MAX_KEYBOARD_KEYS) {
        state.keyboard[event.keysym.scancode] = false;
    }
}

pub fn handleMouseDown(event: *sdl.SDL_MouseButtonEvent, state: *GameState) void {
    if (event.clicks == 1 and event.button < settings.MAX_MOUSE_BUTTONS) {
        state.mouse[event.button] = true;
    }
}

pub fn handleMouseUp(event: *sdl.SDL_MouseButtonEvent, state: *GameState) void {
    if (event.button < settings.MAX_MOUSE_BUTTONS) {
        state.mouse[event.button] = false;
    }
}
