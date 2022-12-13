const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");

const game = @import("game");
const math = @import("math.zig");

pub const Event = enum {
    exit,
    ok,
};

pub fn getMousePos() math.Vec2(f32) {
    var x: i32 = undefined;
    var y: i32 = undefined;
    _ = sdl.SDL_GetMouseState(&x, &y);
    return .{
        .x = game.normalizeWidth(@intToFloat(f32, x)),
        .y = game.normalizeHeight(@intToFloat(f32, y)),
    };
}

pub fn handleInput(state: *game.GameState) Event {
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

pub fn handleMouseDown(event: *sdl.SDL_MouseButtonEvent, state: *game.GameState) void {
    if (event.clicks == 1 and event.button < settings.MAX_MOUSE_BUTTONS) {
        state.mouse[event.button] = true;
    }
}

pub fn handleMouseUp(event: *sdl.SDL_MouseButtonEvent, state: *game.GameState) void {
    if (event.button < settings.MAX_MOUSE_BUTTONS) {
        state.mouse[event.button] = false;
    }
}
