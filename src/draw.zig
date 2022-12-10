const game = @import("game");

const sdl = @import("sdl.zig");
const e = @import("errors.zig");

const ImageLoadFailed = e.SDLError.ImageLoadFailed;

const LOGGER = game.LOGGER;

fn sqrt(x: usize) usize {
    return @floatToInt(usize, @sqrt(@intToFloat(f32, x)));
}

pub fn prepareScene(state: *game.GameState) void {
    _ = sdl.SDL_SetRenderDrawColor(
        state.renderer,
        @divFloor(96, @intCast(u8, @min(255, @max(1, sqrt(state.frame))))),
        @divFloor(128, @intCast(u8, @min(255, @max(1, sqrt(state.frame))))),
        @divFloor(255, @intCast(u8, @min(255, @max(1, sqrt(state.frame))))),
        255);
    _ = sdl.SDL_RenderClear(state.renderer);
}

pub fn presentScene(state: *game.GameState) void {
    sdl.SDL_RenderPresent(state.renderer);
}

pub fn loadTexture(renderer: *sdl.SDL_Renderer, filename: [*c]const u8) e.SDLError!*sdl.SDL_Texture {
    LOGGER.info("Loading {s}", .{ filename });
    return sdl.IMG_LoadTexture(renderer, filename) orelse return ImageLoadFailed;
}

pub fn blit(renderer: *sdl.SDL_Renderer, texture: *sdl.SDL_Texture, x: i32, y: i32, scale: f32) void {
    var dest = sdl.SDL_Rect{
        .x = x,
        .y = y,
        .w = undefined,
        .h = undefined,
    };
    _ = sdl.SDL_QueryTexture(texture, null, null, &dest.w, &dest.h);
    dest.w = @floatToInt(i32, scale * @intToFloat(f32, dest.w));
    dest.h = @floatToInt(i32, scale * @intToFloat(f32, dest.h));
    _ = sdl.SDL_RenderCopy(renderer, texture, null, &dest);
}
