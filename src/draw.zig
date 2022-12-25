const std = @import("std");

const sdl = @import("sdl.zig");
const game = @import("game");
const Entity = game.Entity;
const Position = game.Position;
const Wall = game.Wall;
const NavMeshGrid = game.NavMeshGrid;

/// Plain black background.
pub fn prepareScene(state: *game.GameState) void {
    _ = sdl.SDL_SetRenderDrawColor(state.renderer, 0, 0, 0, 255);
    _ = sdl.SDL_RenderClear(state.renderer);
}

/// Wrapper around SDL rendering
pub fn presentScene(state: *game.GameState) void {
    sdl.SDL_RenderPresent(state.renderer);
}

pub fn loadTexture(renderer: *sdl.SDL_Renderer, filename: [*c]const u8) !*sdl.SDL_Texture {
    std.log.info("Loading {s}", .{filename});
    return sdl.IMG_LoadTexture(renderer, filename) orelse return error.SDLImageLoadFailed;
}

/// Generic rendering function for textures.
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

/// Since walls are currently just SDL Rects instead of textures, we need a separate rendering method for thme.
pub fn drawWall(
    renderer: *sdl.SDL_Renderer,
    wall: *const Wall,
) void {
    _ = sdl.SDL_SetRenderDrawColor(renderer, wall.color.r, wall.color.g, wall.color.b, wall.color.a);
    _ = sdl.SDL_RenderFillRect(renderer, &wall.rect);
}

/// Render a NavMeshGrid by drawing the center points as SDL Points. In particular, only cells marked as visible will be drawn so that the player view field is represented.
pub fn drawGrid(
    renderer: *sdl.SDL_Renderer,
    navMeshGrid: *const NavMeshGrid,
    visibleCellIds: *const std.AutoArrayHashMap(usize, bool),
) void {
    // TODO: This should be done as two batched draw calls (see below). Doesn't really matter for now since this function is mainly used for debugging.
    for (navMeshGrid.grid) |cell, id| {
        const p = sdl.SDL_Point{
            .x = @floatToInt(i32, game.unnormalizeWidth(cell.x)),
            .y = @floatToInt(i32, game.unnormalizeHeight(cell.y)),
        };
        if (visibleCellIds.get(id) orelse false) {
            _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        } else {
            _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        }
        _ = sdl.SDL_RenderDrawPoint(renderer, p.x, p.y);
    }

    // _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
    // _ = sdl.SDL_RenderDrawPoints(renderer, @ptrCast([*c]const sdl.SDL_Point, navMeshGrid.renderPoints), @intCast(i32, navMeshGrid.renderPoints.len));
}

fn blit(renderer: *sdl.SDL_Renderer, texture: *sdl.SDL_Texture, x: i32, y: i32, scale: f32) void {
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
