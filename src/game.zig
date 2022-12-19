const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const init = @import("init.zig");
const input = @import("input.zig");
const draw = @import("draw.zig");
const sound = @import("sound.zig");
const nav = @import("nav.zig");

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Rect = math.Rect;
const Line = math.Line;

const EntityType = @import("ecs/ecs.zig").EntityType;
const Ecs = @import("ecs/ecs.zig").Ecs;

const components = @import("ecs/ecs.zig").components;
pub const Position = components.Position;
pub const Player = components.Player;
pub const Enemy = components.Enemy;
pub const Wall = components.Wall;
pub const Entity = components.Entity;
pub const AIFlanker = components.AIFlanker;
pub const ComponentTypes = components.ComponentTypes;

pub const NavMeshGrid = nav.NavMeshGrid;

const structs = @import("structs.zig");

pub fn EntityIdMap(comptime T: type) type {
    return std.AutoArrayHashMap(u32, T);
}

pub const GameState = struct {
    allocator: std.mem.Allocator,

    timer: std.time.Timer,

    ecs: Ecs(ComponentTypes),
    entities: struct {
        player: EntityType = undefined,
    } = .{},

    frame: usize = 0,

    keyboard: [settings.MAX_KEYBOARD_KEYS]bool = [_]bool{false} ** settings.MAX_KEYBOARD_KEYS,
    mouse: [settings.MAX_MOUSE_BUTTONS]bool = [_]bool{false} ** settings.MAX_MOUSE_BUTTONS,
    renderer: *sdl.SDL_Renderer = undefined,
    window: *sdl.SDL_Window = undefined,
    textures: struct {
        player_texture: *sdl.SDL_Texture = undefined,
        enemy_texture: *sdl.SDL_Texture = undefined,
    } = .{},

    sounds: sound.Sounds = undefined,

    navMeshGrid: NavMeshGrid = undefined,
    blockedCells: std.AutoArrayHashMap(usize, bool) = undefined,

    delegate: struct {
        update: *const fn (*GameState) void,
        draw: *const fn (*GameState) void,
    } = undefined,

    pub fn init(allocator: std.mem.Allocator) !*GameState {
        const worldRegion = math.Rect(f32){
            .x = normalizeWidth(0),
            .y = normalizeHeight(0),
            .w = normalizeWidth(settings.DEFAULT_WINDOW_WIDTH),
            .h = normalizeHeight(settings.DEFAULT_WINDOW_HEIGHT),
        };

        const state = try allocator.create(GameState);
        state.* = GameState{
            .allocator = allocator,
            .timer = try std.time.Timer.start(),
            .ecs = try Ecs(ComponentTypes).init(allocator),
            .navMeshGrid = NavMeshGrid.init(allocator, worldRegion, settings.NAV_MESH_GRID_CELL_SIZE),
            .blockedCells = std.AutoArrayHashMap(usize, bool).init(allocator),
        };
        return state;
    }

    pub fn deinit(self: *GameState) void {
        self.ecs.deinit();
        self.navMeshGrid.deinit();
        self.blockedCells.deinit();
        self.allocator.destroy(self);
    }

    pub fn update(self: *GameState) !void {
        self.delegate.update(self);
    }

    pub fn draw(self: *GameState) void {
        self.delegate.draw(self);
    }
};

pub const LOGGER = std.log;

pub var GAME_STATE: *GameState = undefined;

pub fn handlePlayer(state: *GameState) void {
    var player = state.ecs.componentManager.get(state.entities.player, Entity) catch undefined orelse undefined;
    var position = state.ecs.componentManager.get(state.entities.player, Position) catch undefined orelse undefined;

    position.dx = 0;
    position.dy = 0;

    if (player.reload > 0) {
        player.reload -= 1;
    }

    // Handle keyboard events.
    if (state.keyboard[sdl.SDL_SCANCODE_UP] or state.keyboard[sdl.SDL_SCANCODE_W]) {
        position.dy = -settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_DOWN] or state.keyboard[sdl.SDL_SCANCODE_S]) {
        position.dy = settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_LEFT] or state.keyboard[sdl.SDL_SCANCODE_A]) {
        position.dx -= settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_RIGHT] or state.keyboard[sdl.SDL_SCANCODE_D]) {
        position.dx += settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_SPACE] and player.reload <= 0) {
        sound.playSound(state.sounds.player_fire, .ch_any);
        spawnEnemy(state) catch |e| LOGGER.err("Failed to spawn enemy {}", .{e});
        player.reload = 8;
    }

    // Handle mouse events.
    if (state.mouse[sdl.SDL_BUTTON_LEFT] and !state.keyboard[sdl.SDL_SCANCODE_LCTRL] and player.reload <= 0) {
        spawnWall(state) catch |e| LOGGER.err("Failed to spawn wall {}", .{e});
        player.reload = 1;
    } else if (state.mouse[sdl.SDL_BUTTON_LEFT] and state.keyboard[sdl.SDL_SCANCODE_LCTRL]) {
        handleDeleteClick(state);
    }

    position.x += position.dx;
    position.y += position.dy;

    // Maintain world bounds
    clampPositionToWorldBounds(position);
}

pub fn clampPositionToWorldBounds(position: *Position) void {
    const halfW = position.scale * position.w / 2;
    const halfH = position.scale * position.h / 2;
    const left = position.x - halfW;
    const right = position.x + halfW;
    const top = position.y - halfH;
    const bottom = position.y + halfH;
    if (left < normalizeWidth(0)) {
        position.x = normalizeWidth(0) + halfW;
    } else if (right >= 1.0) {
        position.x = 1.0 - halfW;
    }
    if (top < normalizeHeight(0)) {
        position.y = normalizeHeight(0) + halfH;
    } else if (bottom >= 1.0) {
        position.y = 1.0 - halfH;
    }
}

pub fn handleDeleteClick(state: *GameState) void {
    var entitiesToDelete = std.ArrayList(EntityType).init(state.allocator);
    defer {
        for (entitiesToDelete.items) |entity| {
            state.ecs.removeEntity(entity);
        }
        entitiesToDelete.deinit();
    }

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |kv| {
        const entity = kv.key_ptr.*;
        if (entity != state.entities.player) {
            const position = state.ecs.componentManager.getKnown(entity, Position);
            const mousePos = input.getMousePos();

            var collisionBox: Rect(f32) = undefined;
            if (state.ecs.hasComponent(entity, Wall)) {
                collisionBox = Rect(f32){
                    .x = position.x, .y = position.y,
                    .w = position.w, .h = position.h,
                };
            } else {
                collisionBox = Rect(f32){
                    .x = position.x - position.scale * position.w / 2,
                    .y = position.y - position.scale * position.h / 2,
                    .w = position.scale * position.w,
                    .h = position.scale * position.h,
                };
            }

            if (!math.isCollidingPointxRect(&mousePos, &collisionBox)) {
                continue;
            }

            // Clear deleted entities at the end.
            entitiesToDelete.append(entity) catch unreachable;

            // Update occupied cells.
            if (state.ecs.hasComponent(entity, Wall)) {
                var occupiedCellIds = std.ArrayList(usize).init(state.allocator);
                defer occupiedCellIds.deinit();

                nav.getRectExteriorCellIds(
                    &Rect(f32){
                        .x = position.x,
                        .y = position.y,
                        .w = position.w,
                        .h = position.h,
                    },
                    &state.navMeshGrid,
                    &occupiedCellIds,
                );
                for (occupiedCellIds.items) |cellId| {
                    state.blockedCells.put(cellId, false) catch undefined;
                }
            }
        }
    }
}

pub fn spawnWall(state: *GameState) !void {
    const w = 50;
    const h = 50;

    var x: i32 = 0;
    var y: i32 = 0;
    _ = sdl.SDL_GetMouseState(&x, &y);

    const wall = state.ecs.registerEntity() catch return;
    errdefer _ = state.ecs.entityManager.removeEntity(wall);
    try state.ecs.setComponent(wall, Wall, .{ .rect = .{ .x = (x - w / 2), .y = (y - h / 2), .w = w, .h = h }, .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 } });

    const position = Position{
        .x = normalizeWidth(@intToFloat(f32, x - w / 2)),
        .y = normalizeHeight(@intToFloat(f32, y - h / 2)),
        .w = normalizeWidth(w),
        .h = normalizeHeight(h),
    };
    try state.ecs.setComponent(wall, Position, position);

    // Mark off occupied grid cells as blocked.
    var cellIds = std.ArrayList(usize).init(state.allocator);
    defer cellIds.deinit();

    nav.getRectExteriorCellIds(
        &Rect(f32){
            .x = position.x,
            .y = position.y,
            .w = position.w,
            .h = position.h,
        },
        &state.navMeshGrid,
        &cellIds,
    );
    for (cellIds.items) |cellId| {
        state.blockedCells.put(cellId, true) catch undefined;
    }
}

pub fn spawnEnemy(state: *GameState) !void {
    var entity = Entity{
        .health = 1,
        .texture = state.textures.enemy_texture,
    };

    var x: i32 = 0;
    var y: i32 = 0;
    _ = sdl.SDL_GetMouseState(&x, &y);

    var position = Position{
        .x = normalizeWidth(@intToFloat(f32, x)),
        .y = normalizeHeight(@intToFloat(f32, y)),
        .x0 = normalizeWidth(@intToFloat(f32, x)),
        .y0 = normalizeHeight(@intToFloat(f32, y)),
        .dx = settings.ENEMY_SPEED,
        .scale = 0.25,
    };

    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(entity.texture, null, null, &w, &h);
    position.w = normalizeWidth(@intToFloat(f32, w));
    position.h = normalizeHeight(@intToFloat(f32, h));

    const enemy = state.ecs.registerEntity() catch return;
    errdefer _ = state.ecs.entityManager.removeEntity(enemy);
    try state.ecs.setComponent(enemy, Enemy, .{});
    try state.ecs.setComponent(enemy, Entity, entity);
    try state.ecs.setComponent(enemy, Position, position);
    try state.ecs.setComponent(enemy, AIFlanker, .{});
}

pub fn handleEnemies(state: *GameState) void {
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyValue| {
        const entity = keyValue.key_ptr.*;
        if (state.ecs.hasComponent(entity, Enemy)) {
            var enemy = state.ecs.componentManager.getKnown(entity, Entity);
            var position = state.ecs.componentManager.getKnown(entity, Position);

            const a = @intToFloat(f32, enemy.frame) * std.math.pi / 180.0;
            const rx = 0.34 * @sin(0.25 * a);
            position.x += rx * @cos(a) - (position.x - position.x0);
            position.y += rx * @sin(a) - (position.y - position.y0);
            enemy.frame += 1;

            const scale = 0.25 * (@cos(2.1 * @intToFloat(f32, enemy.frame) * std.math.pi / 180.0) + 1.2);
            position.scale = scale;

            clampPositionToWorldBounds(position);
        }
    }
}

pub fn findPlayer(state: *GameState) void {
    // Do pathfinding
    const player = state.entities.player;
    const playerPosition = state.ecs.componentManager.getKnown(player, Position);
    const cellTarget = state.navMeshGrid.getCellId(&.{ .x = playerPosition.x, .y = playerPosition.y });

    var path = std.ArrayList(usize).init(state.allocator);
    defer path.deinit();

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        if (state.ecs.hasComponent(entity, Enemy) and state.ecs.hasComponent(entity, AIFlanker)) {
            // const aiFlanker = state.ecs.componentManager.getKnown(entity, AIFlanker);
            var enemyPosition = state.ecs.componentManager.getKnown(entity, Position);

            const cellInit = state.navMeshGrid.getCellId(&.{ .x = enemyPosition.x, .y = enemyPosition.y });

            path.clearRetainingCapacity();
            nav.pathfind(cellInit, cellTarget, &state.navMeshGrid, &state.blockedCells, &path);

            // // Draw the route
            // // TODO: make toggleable
            // _ = sdl.SDL_SetRenderDrawColor(state.renderer, 0, 255, 255, 255);
            // for (path.items) |cellId| {
            //     const center = state.navMeshGrid.getCellCenter(cellId);
            //     const x = @floatToInt(i32, unnormalizeWidth(center.x));
            //     const y = @floatToInt(i32, unnormalizeHeight(center.y));
            //     _ = sdl.SDL_RenderDrawPoint(state.renderer, x, y);
            // }

            // Handle movement updates based on path
            // if (!aiFlanker.isSeen and path.items.len > 0) {
                moveAlongPath(enemyPosition, path.items, &state.navMeshGrid);
            // }
        }
    }
}

pub fn findCover(state: *GameState) void {
    const player = state.entities.player;
    const playerPosition = state.ecs.componentManager.getKnown(player, Position);
    const playerPositionPoint = Vec2(f32){
        .x = playerPosition.x + playerPosition.scale * playerPosition.w,
        .y = playerPosition.y + playerPosition.scale * playerPosition.h,
    };

    var path = std.ArrayList(usize).init(state.allocator);
    defer path.deinit();

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        if (state.ecs.hasComponent(entity, Enemy) and state.ecs.hasComponent(entity, AIFlanker)) {
            var position = state.ecs.componentManager.getKnown(entity, Position);
            const center = Vec2(f32){
                .x = position.x,
                .y = position.y,
            };

            // Find nearest wall
            const nearestWallEntity = findNearestWallEntity(&center, state)
                // If no wall could be found, we shouldn't bother trying to find cover again.
                orelse break;
            const wallPosition = state.ecs.componentManager.getKnown(nearestWallEntity, Position);
            const wallRect = Rect(f32){
                .x = wallPosition.x,
                .y = wallPosition.y,
                .w = wallPosition.w,
                .h = wallPosition.h,
            };

            // Find cover on selected wall 
            const wallCoverRect = Rect(f32){
                .x = wallPosition.x - state.navMeshGrid.cellSize,
                .y = wallPosition.y - state.navMeshGrid.cellSize,
                .w = wallPosition.w + 2 * state.navMeshGrid.cellSize,
                .h = wallPosition.h + 2 * state.navMeshGrid.cellSize,
            };
            var wallCoverCellIds = std.ArrayList(usize).init(state.allocator);
            defer wallCoverCellIds.deinit();
            nav.getRectExteriorCellIds(&wallCoverRect, &state.navMeshGrid, &wallCoverCellIds);

            // // DEBUG: draw exterior cells
            // for (wallCoverCellIds.items) |cellId| {
            //     const p = state.navMeshGrid.getCellCenter(cellId);
            //     const x = @floatToInt(i32, unnormalizeWidth(p.x));
            //     const y = @floatToInt(i32, unnormalizeHeight(p.y));
            //     _ = sdl.SDL_SetRenderDrawColor(state.renderer, 0, 255, 255, 255);
            //     _ = sdl.SDL_RenderDrawPoint(state.renderer, x, y);
            // }

            // Get the furthest cover point from the player.
            var coverCellId: ?usize = null;
            var dist: f32 = 0;
            for (wallCoverCellIds.items) |cellId| {
                const coverPoint = state.navMeshGrid.getCellCenter(cellId).*;
                const line = Line(f32){
                    .a = playerPositionPoint,
                    .b = coverPoint,
                };
                // Check LoS for only the selected wall by directly checking intersection between LoS vector and wall polygon.
                // This avoids iterating over every wall with a full LoS check.
                if(isCollidingLineXRect(&line, &wallRect)) {
                    const p = state.navMeshGrid.getCellCenter(cellId);

                    // const x = @floatToInt(i32, unnormalizeWidth(p.x));
                    // const y = @floatToInt(i32, unnormalizeHeight(p.y));
                    // _ = sdl.SDL_SetRenderDrawColor(state.renderer, 255, 0, 255, 255);
                    // _ = sdl.SDL_RenderDrawPoint(state.renderer, x, y);

                    var coverDist = p.sqDist(playerPositionPoint);
                    if (coverDist > dist) {
                        dist = coverDist;
                        coverCellId = cellId;
                    }
                }
            }
            if (coverCellId == null) continue;

            const cellInit = state.navMeshGrid.getCellId(&center);

            path.clearRetainingCapacity();
            nav.pathfind(cellInit, coverCellId.?, &state.navMeshGrid, &state.blockedCells, &path);

            moveAlongPath(position, path.items, &state.navMeshGrid);
        }
    }
}

pub fn moveAlongPath(position: *Position, path: []usize, grid: *const NavMeshGrid) void {
    if (path.len == 0) return;
    if (grid.getCellId(&.{ .x = position.x, .y = position.y }) == path[0]) return;

    var gridAvg: Vec2(f32) = .{ .x = 0, .y = 0 };
    var i: usize = 0;
    const numPathSamples = 1;
    while (i < numPathSamples and i < path.len) : (i += 1) {
        gridAvg = gridAvg.add(grid.getCellCenter(path[i]).*);
    }
    gridAvg = gridAvg.div(@intToFloat(f32, i));

    const direction = gridAvg.sub(.{ .x = position.x, .y = position.y });
    const velocity = direction.mult(settings.ENEMY_SPEED).div(@sqrt(direction.dot(direction)));
    position.x += velocity.x;
    position.y += velocity.y;
}

pub fn findNearestWallEntity(point: *const Vec2(f32), state: *GameState) ?EntityType {
    var minDist = std.math.inf_f32;
    var nearestWall: ?EntityType = null;

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        if (state.ecs.hasComponent(entity, Wall)) {
            var wallPosition = state.ecs.componentManager.getKnown(entity, Position);
            const dist = point.sqDist(.{ .x = wallPosition.x, .y = wallPosition.y });
            if (dist < minDist) {
                minDist = dist;
                nearestWall = entity;
            }
        }
    }
    return nearestWall;
}

pub fn handleLineOfSight(state: *GameState) void {
    const player = state.entities.player;
    const playerPosition = state.ecs.componentManager.getKnown(player, Position);
    const px = @floatToInt(i32, unnormalizeWidth(playerPosition.x));
    const py = @floatToInt(i32, unnormalizeHeight(playerPosition.y));

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        if (state.ecs.hasComponent(entity, Enemy) and state.ecs.hasComponent(entity, AIFlanker)) {
            const enemyPosition = state.ecs.componentManager.getKnown(entity, Position);
            const ex = @floatToInt(i32, unnormalizeWidth(enemyPosition.x));
            const ey = @floatToInt(i32, unnormalizeHeight(enemyPosition.y));

            const line: Line(f32) = .{
                .a = .{
                    .x = playerPosition.x,
                    .y = playerPosition.y,
                },
                .b = .{
                    .x = enemyPosition.x,
                    .y = enemyPosition.y,
                },
            };

            // Check if within player FoV
            var ai = state.ecs.componentManager.getKnown(entity, AIFlanker);
            const playerToMouse = input.getMousePos().sub(line.a);
            ai.isSeen = isPointInLineOfSight(state, line.b, line.a, playerToMouse, settings.PLAYER_FOV);

            // Adjust LoS line color based on whether target is within player view
            var color: struct { r: u8, g: u8, b: u8, a: u8 } = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
            if (ai.isSeen) {
                color.r = 0;
                color.g = 255;
            }

            // _ = ey;
            // _ = ex;
            // _ = py;
            // _ = px;
            _ = sdl.SDL_SetRenderDrawColor(state.renderer, color.r, color.g, color.b, color.a);
            _ = sdl.SDL_RenderDrawLine(state.renderer, px, py, ex, ey);
        }
    }
}

pub fn isPointInLineOfSight(
    state: *GameState,
    point: Vec2(f32),
    looker: Vec2(f32),
    direction: Vec2(f32),
    fov: f32,
) bool {
    // Check if within player FoV
    const lookerToPoint = point.sub(looker);
    var isWithinFov = math.angle(lookerToPoint, direction) <= fov;

    if (isWithinFov) {
        // Check LoS collision with walls
        const line = Line(f32){
            .a = looker,
            .b = point,
        };
        var it = state.ecs.entityManager.iterator();
        while (it.next()) |keyVal| {
            const entity = keyVal.key_ptr.*;
            if (state.ecs.hasComponent(entity, Wall)) {
                const position = state.ecs.componentManager.getKnown(entity, Position);
                const rect: math.Rect(f32) = .{
                    .x = position.x,
                    .y = position.y,
                    .w = position.w,
                    .h = position.h,
                };
                if (isCollidingLineXRect(&line, &rect)) {
                    return false;
                }
            }
        }
    }
    return isWithinFov;
}

pub fn isCollidingLineXRect(line: *const Line(f32), rect: *const math.Rect(f32)) bool {
    const l1: Line(f32) = .{
        .a = .{ .x = rect.x, .y = rect.y },
        .b = .{ .x = rect.x + rect.w, .y = rect.y },
    };
    const l2: Line(f32) = .{
        .a = .{ .x = rect.x + rect.w, .y = rect.y },
        .b = .{ .x = rect.x + rect.w, .y = rect.y + rect.h },
    };
    const l3: Line(f32) = .{
        .a = .{ .x = rect.x + rect.w, .y = rect.y + rect.h },
        .b = .{ .x = rect.x, .y = rect.y + rect.h },
    };
    const l4: Line(f32) = .{
        .a = .{ .x = rect.x, .y = rect.y + rect.h },
        .b = .{ .x = rect.x, .y = rect.y },
    };
    return isCollidingLineXLine(line, &l1) or
        isCollidingLineXLine(line, &l2) or
        isCollidingLineXLine(line, &l3) or
        isCollidingLineXLine(line, &l4);
}

pub fn isCollidingLineXLine(l1: *const Line(f32), l2: *const Line(f32)) bool {
    const s1 = l1.b.sub(l1.a);
    const s2 = l2.b.sub(l2.a);
    const s1xs2 = s1.cross(s2) + 1e-8;  // avoid division by 0

    const u = l1.a.sub(l2.a);
    const s1xu = s1.cross(u);
    const s2xu = s2.cross(u);

    const s = s1xu / s1xs2;
    const t = s2xu / s1xs2;

    // var intersection = Vec2(f32){ .x = 0, .y = 0 };
    // if (s >= 0 and s <= 1 and t >= 0 and t <= 1) {
    //     intersection.x = l1.a.x + t * s1.x;
    //     intersection.y = l1.a.y + t * s1.y;
    //     return true;
    // }
    // return false;

    return (s >= 0 and s <= 1 and t >= 0 and t <= 1);
}

// pub fn handlePhysics(state: *GameState) void {
//     const dt = deltaTime(&state.timer);
//     _ = state.physics.world.stepSimulation(dt, .{});

//     var it = state.ecs.entityManager.iterator();
//     while (it.next()) |keyValue| {
//         const entityId = keyValue.key_ptr.*;
//         if (state.ecs.hasComponent(entityId, Physics)) {
//             var position = state.ecs.componentManager.getKnown(entityId, Position);
//             // var physics = state.ecs.componentManager.getKnown(entityId, Physics);
//             _ = position;
//             // _ = physics;
//             // var it2 = state.ecs.entityManager.iterator();
//             // while (it2.next()) |keyValue2| {
//             //     const entityId2 = keyValue2.key_ptr.*;
//             //     if (entityId == entityId2) continue;
//             //     if (state.ecs.hasComponent(entityId, Physics)) {
//             //         var position2 = state.ecs.componentManager.getKnown(entityId2, Position);
//             //         if (isColliding(position, position2)) {
//             //             LOGGER.info("collision!", .{});
//             //         }
//             //     }
//             // }
//         }
//     }
// }

// const MAX_FPS: f32 = 60 * 1000000000;
// var TIME_DELTA: u64 = 0;
// pub fn deltaTime(timer: *std.time.Timer) f32 {
//     const time = timer.read();
//     const delta = @intToFloat(f32, time - TIME_DELTA) / 1000000000.0;
//     TIME_DELTA = time;
//     return delta;
// }

pub fn update(state: *GameState) void {
    // handlePhysics(state);
    handlePlayer(state);
    // handleEnemies(state);
    // handleLineOfSight(state);
    findCover(state);
    // findPlayer(state);
}

pub fn drawScene(state: *GameState) void {
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;

        if (state.ecs.hasComponent(entity, Enemy)) {
            const enemy = state.ecs.componentManager.getKnown(entity, Entity);
            const position = state.ecs.componentManager.getKnown(entity, Position);
            draw.drawEntity(state.renderer, enemy, position);
        } else if (state.ecs.hasComponent(entity, Player)) {
            const player = state.ecs.componentManager.getKnown(entity, Entity);
            const position = state.ecs.componentManager.getKnown(entity, Position);
            draw.drawEntity(state.renderer, player, position);
        } else if (state.ecs.hasComponent(entity, Wall)) {
            const wall = state.ecs.componentManager.getKnown(entity, Wall);
            draw.drawWall(state.renderer, wall);
        }

        // // Render nav mesh grid
        // draw.drawGrid(state.renderer, &state.navMeshGrid, &state.blockedCells);
    }
    draw.presentScene(state);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    GAME_STATE = try GameState.init(allocator);
    defer GAME_STATE.deinit();

    GAME_STATE.delegate = .{
        .update = &update,
        .draw = &drawScene,
    };

    // Init SDL
    init.initSDL(GAME_STATE) catch |err| {
        LOGGER.err("Failed to initialize: {s}", .{sdl.SDL_GetError()});
        return err;
    };
    defer {
        LOGGER.info("Shutting down...", .{});
        init.deinitSDL(GAME_STATE);
    }

    // Load textures
    GAME_STATE.textures = .{
        .player_texture = try draw.loadTexture(GAME_STATE.renderer, "assets/olive-oil.png"),
        .enemy_texture = try draw.loadTexture(GAME_STATE.renderer, "assets/ainsley.png"),
    };

    // Initialize entities
    GAME_STATE.entities.player = try GAME_STATE.ecs.registerEntity();
    try GAME_STATE.ecs.setComponent(GAME_STATE.entities.player, Player, .{});
    try GAME_STATE.ecs.setComponent(
        GAME_STATE.entities.player,
        Entity,
        Entity{ .texture = GAME_STATE.textures.player_texture },
    );
    var playerPosition = Position{
        .x = normalizeWidth(0.0),
        .y = normalizeHeight(0.0),
        .scale = settings.PLAYER_SCALE,
    };
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(
        GAME_STATE.textures.player_texture,
        null,
        null,
        &w,
        &h,
    );
    playerPosition.w = @fabs(normalizeWidth(@intToFloat(f32, w)));
    playerPosition.h = @fabs(normalizeHeight(@intToFloat(f32, h)));
    try GAME_STATE.ecs.setComponent(
        GAME_STATE.entities.player,
        Position,
        playerPosition,
    );

    // Initialize sound + music
    GAME_STATE.sounds = sound.initSounds();

    // sound.loadMusic("assets/doom-chant.mp3");
    // defer sdl.Mix_Quit();
    // sound.playMusic(true);

    // Main game loop
    while (input.handleInput(GAME_STATE) != .exit and !GAME_STATE.keyboard[sdl.SDL_SCANCODE_ESCAPE]) : (GAME_STATE.frame += 1) {
        draw.prepareScene(GAME_STATE);

        try GAME_STATE.update();
        GAME_STATE.draw();

        sdl.SDL_Delay(16);
    }
}

pub fn normalizeWidth(w: f32) f32 {
    return w / @intToFloat(f32, settings.DEFAULT_WINDOW_WIDTH);
}

pub fn unnormalizeWidth(w: f32) f32 {
    return @intToFloat(f32, settings.DEFAULT_WINDOW_WIDTH) * (w);
}

pub fn normalizeHeight(h: f32) f32 {
    return h / @intToFloat(f32, settings.DEFAULT_WINDOW_HEIGHT);
}

pub fn unnormalizeHeight(h: f32) f32 {
    return @intToFloat(f32, settings.DEFAULT_WINDOW_HEIGHT) * (h);
}
