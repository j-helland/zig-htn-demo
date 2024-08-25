const std = @import("std");

const sdl = @import("sdl.zig");
const gamestate = @import("gamestate.zig");
const Texture = gamestate.Texture;
const Position = gamestate.Position;
const Wall = gamestate.Wall;
const Camera = gamestate.Camera;
const NavMeshGrid = gamestate.NavMeshGrid;

/// Plain black background.
pub fn prepareScene(state: *gamestate.GameState) void {
    _ = sdl.SDL_SetRenderDrawColor(state.renderer, 0, 0, 0, 255);
    _ = sdl.SDL_RenderClear(state.renderer);
}

/// Wrapper around SDL rendering
pub fn presentScene(state: *gamestate.GameState) void {
    sdl.SDL_RenderPresent(state.renderer);
}

pub fn loadTexture(renderer: *sdl.SDL_Renderer, filename: [*c]const u8) !*sdl.SDL_Texture {
    std.log.info("Loading {s}", .{filename});
    return sdl.IMG_LoadTexture(renderer, filename) orelse return error.SDLImageLoadFailed;
}

/// Generic rendering function for textures.
pub fn drawEntity(
    renderer: *sdl.SDL_Renderer,
    texture: *const Texture,
    position: *const Position,
    camera: *const Camera,
) void {
    const p = camera.normalize(.{
        .x = position.x - position.w / 2,
        .y = position.y - position.h / 2,
    });
    blit(
        renderer,
        texture.sdlTexture,
        @as(i32, @intFromFloat(gamestate.unnormalizeWidth(p.x))),
        @as(i32, @intFromFloat(gamestate.unnormalizeHeight(p.y))),
        texture.scale,
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
        .x = wall.rect.x - @as(i32, @intFromFloat(gamestate.unnormalizeWidth(camera.rect.x))),
        .y = wall.rect.y - @as(i32, @intFromFloat(gamestate.unnormalizeHeight(camera.rect.y))),
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
        .w = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(camera.rect.w))) - 2 * offset,
        .h = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(camera.rect.h))) - 2 * offset,
    });
    _ = sdl.SDL_RenderDrawRect(renderer, &sdl.SDL_Rect{
        .x = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(camera.rect.w / 2))),
        .y = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(camera.rect.h / 2))),
        .w = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(0.01))),
        .h = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(0.01))),
    });
}

pub fn drawWorldBounds(
    renderer: *sdl.SDL_Renderer,
) void {
    const offset = 2;

    _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
    _ = sdl.SDL_RenderDrawRect(renderer, &sdl.SDL_Rect{
        .x = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(0))),
        .y = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(0))),
        .w = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(1))) - 2 * offset,
        .h = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(1))) - 2 * offset,
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

    for (navMeshGrid.grid, 0..) |cell, id| {
        const cellCamera = camera.normalize(cell);
        const p = sdl.SDL_Point{
            .x = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(cellCamera.x))),
            .y = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(cellCamera.y))),
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
    _ = sdl.SDL_RenderDrawPoints(renderer, @as([*c]sdl.SDL_Point, @ptrCast(renderPoints.items)), @as(i32, @intCast(renderPoints.items.len)));

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
    dest.w = @as(i32, @intFromFloat(scale * @as(f32, @floatFromInt(dest.w))));
    dest.h = @as(i32, @intFromFloat(scale * @as(f32, @floatFromInt(dest.h))));
    _ = sdl.SDL_RenderCopy(renderer, texture, null, &dest);
}
