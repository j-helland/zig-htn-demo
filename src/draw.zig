const std = @import("std");

const sdl = @import("sdl.zig");
const game = @import("game");
const Entity = game.Entity;
const Position = game.Position;
const Wall = game.Wall;
const Camera = game.Camera;
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
    camera: *const Camera,
) void {
    const p = camera.normalize(.{
        .x = position.x - position.scale * position.w / 2,
        .y = position.y - position.scale * position.h / 2,
    });
    blit(
        renderer,
        entity.texture,
        @floatToInt(i32, game.unnormalizeWidth(p.x)),
        @floatToInt(i32, game.unnormalizeHeight(p.y)),
        position.scale,
    );
}

/// Since walls are currently just SDL Rects instead of textures, we need a separate rendering method for them.
pub fn drawWall(
    renderer: *sdl.SDL_Renderer,
    wall: *const Wall,
    camera: *const Camera,
) void {
    _ = sdl.SDL_SetRenderDrawColor(renderer, wall.color.r, wall.color.g, wall.color.b, wall.color.a);
    _ = sdl.SDL_RenderFillRect(renderer, &sdl.SDL_Rect{
        .x = wall.rect.x - @floatToInt(i32, game.unnormalizeWidth(camera.rect.x)),
        .y = wall.rect.y - @floatToInt(i32, game.unnormalizeHeight(camera.rect.y)),
        .w = wall.rect.w,
        .h = wall.rect.h,
    });
}

pub fn drawCamera(
    renderer: *sdl.SDL_Renderer,
    camera: *const Camera,
) void {
    const offset = 2;

    _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
    _ = sdl.SDL_RenderDrawRect(renderer, &sdl.SDL_Rect{
        .x = 0 + offset,
        .y = 0 + offset,
        .w = @floatToInt(i32, game.unnormalizeWidth(camera.rect.w)) - 2 * offset,
        .h = @floatToInt(i32, game.unnormalizeHeight(camera.rect.h)) - 2 * offset,
    });
    _ = sdl.SDL_RenderDrawRect(renderer, &sdl.SDL_Rect{
        .x = @floatToInt(i32, game.unnormalizeWidth(camera.rect.w / 2)),
        .y = @floatToInt(i32, game.unnormalizeHeight(camera.rect.h / 2)),
        .w = @floatToInt(i32, game.unnormalizeWidth(0.01)),
        .h = @floatToInt(i32, game.unnormalizeHeight(0.01)),
    });
}

pub fn drawWorldBounds(
    renderer: *sdl.SDL_Renderer,
) void {
    const offset = 2;

    _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
    _ = sdl.SDL_RenderDrawRect(renderer, &sdl.SDL_Rect{
        .x = @floatToInt(i32, game.unnormalizeWidth(0)),
        .y = @floatToInt(i32, game.unnormalizeHeight(0)),
        .w = @floatToInt(i32, game.unnormalizeWidth(1)) - 2 * offset,
        .h = @floatToInt(i32, game.unnormalizeHeight(1)) - 2 * offset,
    });
}

/// Render a NavMeshGrid by drawing the center points as SDL Points. In particular, only cells marked as visible will be drawn so that the player view field is represented.
pub fn drawGrid(
    allocator: std.mem.Allocator,
    renderer: *sdl.SDL_Renderer,
    navMeshGrid: *const NavMeshGrid,
    visibleCellIds: *const std.AutoArrayHashMap(usize, bool),
    camera: *const Camera,
) void {
    var renderPoints = std.ArrayList(sdl.SDL_Point).init(allocator);
    defer renderPoints.deinit();

    for (navMeshGrid.grid) |cell, id| {
        const cellCamera = camera.normalize(cell);
        const p = sdl.SDL_Point{
            .x = @floatToInt(i32, game.unnormalizeWidth(cellCamera.x)),
            .y = @floatToInt(i32, game.unnormalizeHeight(cellCamera.y)),
        };
        if (visibleCellIds.get(id) orelse false) {
            renderPoints.append(p) catch unreachable;
            _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        }
        // else {
        //     _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        // }
        // _ = sdl.SDL_RenderDrawPoint(renderer, p.x, p.y);
    }

    _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
    _ = sdl.SDL_RenderDrawPoints(renderer, @ptrCast([*c]sdl.SDL_Point, renderPoints.items), @intCast(i32, renderPoints.items.len));

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
