const std = @import("std");

const game = @import("game");
const Entity = game.Entity;
const Position = game.Position;
const Wall = game.Wall;
const NavMeshGrid = game.NavMeshGrid;

const sdl = @import("sdl.zig");
const e = @import("errors.zig");

const ImageLoadFailed = e.SDLError.ImageLoadFailed;

const LOGGER = game.LOGGER;

fn sqrt(x: usize) usize {
    return @floatToInt(usize, @sqrt(@intToFloat(f32, x)));
}

pub fn prepareScene(state: *game.GameState) void {
    // _ = sdl.SDL_SetRenderDrawColor(state.renderer, @divFloor(96, @intCast(u8, @min(255, @max(1, sqrt(state.frame))))), @divFloor(128, @intCast(u8, @min(255, @max(1, sqrt(state.frame))))), @divFloor(255, @intCast(u8, @min(255, @max(1, sqrt(state.frame))))), 255);
    _ = sdl.SDL_SetRenderDrawColor(state.renderer, 0, 0, 0, 255);
    _ = sdl.SDL_RenderClear(state.renderer);
}

pub fn presentScene(state: *game.GameState) void {
    sdl.SDL_RenderPresent(state.renderer);
}

pub fn loadTexture(renderer: *sdl.SDL_Renderer, filename: [*c]const u8) e.SDLError!*sdl.SDL_Texture {
    LOGGER.info("Loading {s}", .{filename});
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

pub fn drawEntity(
    renderer: *sdl.SDL_Renderer,
    entity: *const Entity,
    position: *const Position,
) void {
    blit(
        renderer,
        entity.texture,
        @floatToInt(i32, game.unnormalizeWidth(position.x - position.scale * position.w / 2)),
        @floatToInt(i32, game.unnormalizeHeight(position.y - position.scale * position.h / 2)),
        position.scale,
    );
}

pub fn drawWall(
    renderer: *sdl.SDL_Renderer,
    wall: *const Wall,
) void {
    _ = sdl.SDL_SetRenderDrawColor(renderer, wall.color.r, wall.color.g, wall.color.b, wall.color.a);
    _ = sdl.SDL_RenderFillRect(renderer, &wall.rect);
}

pub fn drawGrid(
    renderer: *sdl.SDL_Renderer,
    navMeshGrid: *const NavMeshGrid,
    blockedCells: *const std.AutoArrayHashMap(usize, bool),
) void {
    for (navMeshGrid.grid) |cell, id| {
        const p = sdl.SDL_Point{
            .x = @floatToInt(i32, game.unnormalizeWidth(cell.x)),
            .y = @floatToInt(i32, game.unnormalizeHeight(cell.y)),
        };
        if (blockedCells.get(id) orelse false) {
            _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        } else {
            _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        }
        _ = sdl.SDL_RenderDrawPoint(renderer, p.x, p.y);
    }
    // _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
    // _ = sdl.SDL_RenderDrawPoints(renderer, @ptrCast([*c]const sdl.SDL_Point, navMeshGrid.renderPoints), @intCast(i32, navMeshGrid.renderPoints.len));
}
