const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const input = @import("input.zig");
const draw = @import("draw.zig");
// const sound = @import("sound.zig");

const ai = @import("ai.zig");

const nav = @import("nav.zig");
pub const NavMeshGrid = nav.NavMeshGrid;

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Rect = math.Rect;
const Line = math.Line;

pub const Queue = @import("queue.zig").Queue;

pub const EntityType = @import("ecs/ecs.zig").EntityType;
const Ecs = @import("ecs/ecs.zig").Ecs;

const htn = @import("htn/htn.zig");

const gs = @import("gamestate.zig");
const GameState = gs.GameState;
const Texture = gs.Texture;
const Player = gs.Player;
const Position = gs.Position;
const Camera = gs.Camera;
const Enemy = gs.Enemy;
const Wall = gs.Wall;
const EnemyFlankerAI = gs.EnemyFlankerAI;
const normalizeWidth = gs.normalizeWidth;
const normalizeHeight = gs.normalizeHeight;
const unnormalizeWidth = gs.unnormalizeWidth;
const unnormalizeHeight = gs.unnormalizeHeight;

//**************************************************
// GAME STATE
//**************************************************

//**************************************************
// MAIN GAME LOOP
//**************************************************
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gameState: *GameState = try GameState.init(allocator);
    defer gameState.deinit();

    // Init SDL
    sdl.initSDL(gameState) catch |err| {
        std.log.err("Failed to initialize: {s}", .{sdl.SDL_GetError()});
        return err;
    };
    defer {
        std.log.info("Shutting down...", .{});
        sdl.deinitSDL(gameState);
    }

    // Load textures
    gameState.textures = .{
       .player_texture = try draw.loadTexture(gameState.renderer, "assets/olive-oil.png"),
       .enemy_texture = try draw.loadTexture(gameState.renderer, "assets/ainsley.png"),
    };

    // Initialize entities
    try initPlayer(gameState);
    try initCamera(gameState);

    // // TODO: sound disabled for now
    // // Initialize sound + music
    // initSound(gameState);
    // defer sdl.Mix_Quit();

    // Main game loop
    var frameDelta: f32 = 0;
    const invMaxFps: f32 = 1.0 / settings.MAX_FPS;
    while ((input.handleInput(gameState) != .exit) and !gameState.keyboard[sdl.SDL_SCANCODE_ESCAPE]) : (gameState.updateDeltaTime()) {
        frameDelta += gameState.deltaTime;
        if (frameDelta < invMaxFps) continue;
        frameDelta -= invMaxFps;

        draw.prepareScene(gameState);
        update(gameState);
        drawScene(gameState);
    }
}

//**************************************************
// INITIALIZATION HELPER FUNCTIONS
//**************************************************
pub fn initPlayer(state: *GameState) !void {
    state.entities.player = try state.ecs.registerEntity();
    try state.ecs.setComponent(state.entities.player, Player, .{});

    const texture = Texture{
        .sdlTexture = state.textures.player_texture,
        .scale = settings.PLAYER_SCALE,
    };
    try state.ecs.setComponent(
        state.entities.player,
        Texture,
        texture,
    );

    var playerPosition = Position{
        .x = normalizeWidth(0.0),
        .y = normalizeHeight(0.0),
    };
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(
        texture.sdlTexture,
        null,
        null,
        &w,
        &h,
    );
    playerPosition.w = texture.scale * @abs(normalizeWidth(@as(f32, @floatFromInt(w))));
    playerPosition.h = texture.scale * @abs(normalizeHeight(@as(f32, @floatFromInt(h))));
    try state.ecs.setComponent(
        state.entities.player,
        Position,
        playerPosition,
    );
}

pub fn initCamera(state: *GameState) !void {
    const playerPosition = state.ecs.componentManager.get(state.entities.player, Position) orelse {
        std.log.err("Player Position component must be initialized before the camera", .{});
        return error.ECSInitializationError;
    };

    const windowHW = getWindowSize(state);
    const w = windowHW.x;
    const h = windowHW.y;

    state.entities.camera = try state.ecs.registerEntity();
    try state.ecs.setComponent(
        state.entities.camera,
        Camera,
        .{
            .rect = Rect(f32){
                .x = playerPosition.x - w / 2,
                .y = playerPosition.y - h / 2,
                .w = w,
                .h = h,
            },
        },
    );
}

// pub fn initSound(state: *GameState) void {
//     state.sounds = sound.initSounds();
//     sound.loadMusic("assets/doom-chant.mp3");
//     sound.playMusic(true);
// }

//**************************************************
// RENDERING HELPER FUNCTIONS
//**************************************************
pub fn drawScene(state: *GameState) void {
    const loggingContext = "game.zig::drawScene";

    const cameraComponent = state.ecs.componentManager.get(state.entities.camera, Camera) orelse {
        std.log.err("[{s}] e:{d} Could not get Camera component", .{ loggingContext, state.entities.camera });
        @panic("Could not get camera position component");
    };

    // TODO: debug
    draw.drawCamera(state.renderer, cameraComponent);

    // TODO: debug
    // Render nav mesh grid
    draw.drawGrid(state.allocator, state.renderer, &state.navMeshGrid, &state.visibleCells, cameraComponent);

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;

        if (state.ecs.hasComponent(entity, Player) and !state.ecs.componentManager.getKnown(entity, Player).isAlive) {
            continue;
        }

        if (state.ecs.hasComponent(entity, Enemy) or state.ecs.hasComponent(entity, Player)) {
            // TODO: Enemy and Player should be replaced with a more generic component e.g. `Renderer` or `Texture`.
            const textureComponent = state.ecs.componentManager.getKnown(entity, Texture);
            const positionComponent = state.ecs.componentManager.getKnown(entity, Position);
            draw.drawEntity(state.renderer, textureComponent, positionComponent, cameraComponent);
        } else if (state.ecs.hasComponent(entity, Wall)) {
            // Walls do not currently have textures, so they need to be rendered separately.
            const wall = state.ecs.componentManager.getKnown(entity, Wall);
            draw.drawWall(state.renderer, wall, cameraComponent);
        }
    }

    draw.presentScene(state);
}

//**************************************************
// UPDATE HELPER FUNCTIONS
//--------------------------------------------------
// These are primarily ECS systems.
//**************************************************
pub fn update(state: *GameState) void {
    handleEnemyAI(state);
    handlePlayer(state);
    handleCamera(state);
}

pub fn handlePlayer(state: *GameState) void {
    const loggingContext = "game.zig::handlePlayer";

    var player = state.ecs.componentManager.get(state.entities.player, Player) orelse {
        std.log.err("[{s}] e:{d} Could not get Player component", .{ loggingContext, state.entities.player });
        return;
    };
    var position = state.ecs.componentManager.get(state.entities.player, Position) orelse {
        std.log.err("[{s}] e:{d} Could not get Position component", .{ loggingContext, state.entities.player });
        return;
    };

    var dx: f32 = 0;
    var dy: f32 = 0;

    if (player.reload > 0) {
        player.reload -= 1;
    }

    // Handle keyboard events.
    if (state.keyboard[sdl.SDL_SCANCODE_UP] or state.keyboard[sdl.SDL_SCANCODE_W]) {
        dy = -settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_DOWN] or state.keyboard[sdl.SDL_SCANCODE_S]) {
        dy = settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_LEFT] or state.keyboard[sdl.SDL_SCANCODE_A]) {
        dx -= settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_RIGHT] or state.keyboard[sdl.SDL_SCANCODE_D]) {
        dx += settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_SPACE] and player.reload <= 0) {
        spawnEnemy(state) catch |e| std.log.err("Failed to spawn enemy {}", .{e});
        player.reload = 8;
    }

    // Handle mouse events.
    if (state.mouse[sdl.SDL_BUTTON_LEFT] and !state.keyboard[sdl.SDL_SCANCODE_LCTRL] and player.reload <= 0) {
        spawnWall(state) catch |e| std.log.err("Failed to spawn wall {}", .{e});
        player.reload = 8;
    } else if (state.mouse[sdl.SDL_BUTTON_LEFT] and state.keyboard[sdl.SDL_SCANCODE_LCTRL]) {
        handleDeleteClick(state);
    }

    position.x += dx;
    position.y += dy;

    // Maintain world bounds
    clampPositionToWorldBounds(position);

    const playerPoint = math.Vec2(f32){ .x = position.x, .y = position.y };
    var mousePoint = gs.getMousePos(state);

    // Update visibility map
    for (state.navMeshGrid.grid, 0..) |cell, cellId| {
        const isSeen = ai.isPointInLineOfSight(state, cell, playerPoint, mousePoint.sub(playerPoint), settings.PLAYER_FOV);
        state.visibleCells.put(cellId, isSeen) catch unreachable;
    }
}

pub fn handleCamera(state: *GameState) void {
    const loggingContext = "game.zig::handleCamera";

    const playerPosition = state.ecs.componentManager.get(state.entities.player, Position) orelse {
        std.log.err("[{s}] e:{d} Could not get player Position component", .{ loggingContext, state.entities.player });
        return;
    };
    var camera = state.ecs.componentManager.get(state.entities.camera, Camera) orelse {
        std.log.err("[{s}] e:{d} Could not get Camera component", .{ loggingContext, state.entities.camera });
        return;
    };
    const windowHW = getWindowSize(state);

    camera.rect.x = playerPosition.x - windowHW.x / 2;
    camera.rect.y = playerPosition.y - windowHW.y / 2;
    camera.rect.w = windowHW.x;
    camera.rect.h = windowHW.y;

    // Maintain world bounds
    clampRectToWorldBounds(&camera.rect);
}

/// Delete entities intersecting with the mouse click position.
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
        if (entity != state.entities.player and entity != state.entities.camera) {
            const position = state.ecs.componentManager.getKnown(entity, Position);
            const mousePos = gs.getMousePos(state);

            var collisionBox: Rect(f32) = undefined;
            if (state.ecs.hasComponent(entity, Wall)) {
                collisionBox = Rect(f32){
                    .x = position.x,
                    .y = position.y,
                    .w = position.w,
                    .h = position.h,
                };
            } else {
                collisionBox = Rect(f32){
                    .x = position.x - position.w / 2,
                    .y = position.y - position.h / 2,
                    .w = position.w,
                    .h = position.h,
                };
            }

            if (!mousePos.intersectsRect(collisionBox)) {
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

/// Functions as the HTN task runner.
/// If the task returns a `.Running` status, it will be continued next tick.
/// If a task returns a `Succeeded` response, the next task in the queue will be attempted.
/// A task can fail for two reasons:
/// 1. The task preconditions are no longer valid.
/// 2. The task returns a `.Failed` status.
pub fn handleEnemyAI(state: *GameState) void {
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        var enemyAI = state.ecs.componentManager.get(entity, EnemyFlankerAI) orelse continue;
        enemyAI.worldState.updateSensors(entity, state);

        //// Request a plan.
        if (enemyAI.needsPlan()) {
            var plan = enemyAI.planner.processTasks(&enemyAI.worldState).getPlan();
            defer plan.deinit();

            enemyAI.currentPlanQueue = Queue(*htn.Task).init(state.allocator);
            enemyAI.currentPlanQueue.?.pushSlice(plan.items) catch unreachable;

            std.log.info("requested plan:", .{});
            for (plan.items) |t| std.log.info("e:{d} {s}", .{ entity, t.name });
            std.log.info("\n\n", .{});
        }

        //// Follow the plan.
        std.debug.print("[DEBUG] [handleEnemyAI]", .{});
        const task = enemyAI.currentPlanQueue.?.peek() orelse continue;
        var primitiveTask = task.primitiveTask.?;

        // Handle task failure due to preconditions invalidated.
        if (!primitiveTask.checkPreconditions(enemyAI.worldState.state)) {
            std.log.info("e:{d} plan failed due to task condition {s}", .{ entity, task.name });
            for (primitiveTask.onFailureFunctions) |f| f(entity, enemyAI.worldState.state, state);
            enemyAI.currentPlanQueue.?.deinit();
            enemyAI.currentPlanQueue = null;
            continue;
        }

        // Run the task and handle its response.
        const status = primitiveTask.operator(entity, enemyAI.worldState.state, state);
        switch (status) {
            .Running => {},
            .Succeeded => {
                _ = enemyAI.currentPlanQueue.?.pop();
            },
            .Failed => {
                std.log.info("e:{d} plan failed due to task response {s}", .{ entity, task.name });
                for (primitiveTask.onFailureFunctions) |f| f(entity, enemyAI.worldState.state, state);
                enemyAI.currentPlanQueue.?.deinit();
                enemyAI.currentPlanQueue = null;
                continue;
            },
        }
    }
}

//**************************************************
// ENTITY SPAWNING HELPER FUNCTIONS
//**************************************************
pub fn spawnWall(state: *GameState) !void {
    const w = settings.WALL_WIDTH;
    const h = settings.WALL_HEIGHT;

    const mousePos = gs.getMousePos(state);
    const x = @as(i32, @intFromFloat(unnormalizeWidth(mousePos.x)));
    const y = @as(i32, @intFromFloat(unnormalizeHeight(mousePos.y)));

    const wall = state.ecs.registerEntity() catch return;
    errdefer _ = state.ecs.entityManager.removeEntity(wall);
    try state.ecs.setComponent(
        wall,
        Wall,
        Wall{
            .rect = .{ .x = (x - w / 2), .y = (y - h / 2), .w = w, .h = h },
            .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        },
    );

    const position = Position{
        .x = normalizeWidth(@as(f32, @floatFromInt(x - w / 2))),
        .y = normalizeHeight(@as(f32, @floatFromInt(y - h / 2))),
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
    const texture = Texture{
        .sdlTexture = state.textures.enemy_texture,
        .scale = settings.ENEMY_SCALE,
    };

    const mousePos = gs.getMousePos(state);

    var position = Position{
        .x = mousePos.x,
        .y = mousePos.y,
    };

    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(texture.sdlTexture, null, null, &w, &h);
    position.w = texture.scale * normalizeWidth(@as(f32, @floatFromInt(w)));
    position.h = texture.scale * normalizeHeight(@as(f32, @floatFromInt(h)));

    const enemy = state.ecs.registerEntity() catch return;
    errdefer _ = state.ecs.entityManager.removeEntity(enemy);
    try state.ecs.setComponent(enemy, Enemy, .{});
    try state.ecs.setComponent(enemy, Texture, texture);
    try state.ecs.setComponent(enemy, Position, position);

    try state.ecs.setComponent(enemy, EnemyFlankerAI, EnemyFlankerAI.init(state.allocator));
}

//**************************************************
// MISC. HELPER FUNCTIONS
//**************************************************
fn clampPositionToWorldBounds(position: *Position) void {
    const w = position.w;
    const h = position.h;
    var rect = Rect(f32){
        .x = position.x - w / 2,
        .y = position.y - h / 2,
        .w = w,
        .h = h,
    };
    clampRectToWorldBounds(&rect);
    position.x = rect.x + w / 2;
    position.y = rect.y + h / 2;
}

fn clampRectToWorldBounds(rect: *Rect(f32)) void {
    if (rect.x < normalizeWidth(0)) {
        rect.x = normalizeWidth(0);
    } else if (rect.x + rect.w >= 1.0) {
        rect.x = 1.0 - rect.w;
    }
    if (rect.y < normalizeHeight(0)) {
        rect.y = normalizeHeight(0);
    } else if (rect.y + rect.h >= 1.0) {
        rect.y = 1.0 - rect.h;
    }
}

pub fn getWindowSize(state: *const GameState) Vec2(f32) {
    var iw: i32 = undefined;
    var ih: i32 = undefined;
    sdl.SDL_GetWindowSize(state.window, &iw, &ih);
    return .{
        .x = normalizeWidth(@as(f32, @floatFromInt(iw))),
        .y = normalizeHeight(@as(f32, @floatFromInt(ih))),
    };
}
