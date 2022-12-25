const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const init = @import("init.zig");
const input = @import("input.zig");
const draw = @import("draw.zig");
// const sound = @import("sound.zig");

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

const components = @import("ecs/ecs.zig").components;
pub const Position = components.Position;
pub const Player = components.Player;
pub const Enemy = components.Enemy;
pub const Wall = components.Wall;
pub const Entity = components.Entity;
pub const EnemyFlankerAI = @import("ai.zig").EnemyFlankerAI;

const ComponentTypes = .{
    Position,
    Player,
    Enemy,
    Wall,
    Entity,
    EnemyFlankerAI,
};

//**************************************************
// GAME STATE
//**************************************************
pub const GameState = struct {
    allocator: std.mem.Allocator,
    rng: std.rand.DefaultPrng,

    timer: std.time.Timer,
    deltaTime: f32 = 0.0,

    // Entity Component System (ECS) state
    ecs: Ecs(ComponentTypes),
    entities: struct {
        player: EntityType = undefined,
    } = .{},

    // Universal navigation state
    navMeshGrid: NavMeshGrid = undefined,
    blockedCells: std.AutoArrayHashMap(usize, bool) = undefined,
    visibleCells: std.AutoArrayHashMap(usize, bool) = undefined,

    // Input + GFX
    keyboard: [settings.MAX_KEYBOARD_KEYS]bool = [_]bool{false} ** settings.MAX_KEYBOARD_KEYS,
    mouse: [settings.MAX_MOUSE_BUTTONS]bool = [_]bool{false} ** settings.MAX_MOUSE_BUTTONS,
    renderer: *sdl.SDL_Renderer = undefined,
    window: *sdl.SDL_Window = undefined,
    textures: struct {
        player_texture: *sdl.SDL_Texture = undefined,
        enemy_texture: *sdl.SDL_Texture = undefined,
    } = .{},
    // sounds: sound.Sounds = undefined,

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
            .rng = std.rand.DefaultPrng.init(0),
            .ecs = try Ecs(ComponentTypes).init(allocator),
            .navMeshGrid = NavMeshGrid.init(allocator, worldRegion, settings.NAV_MESH_GRID_CELL_SIZE),
            .blockedCells = std.AutoArrayHashMap(usize, bool).init(allocator),
            .visibleCells = std.AutoArrayHashMap(usize, bool).init(allocator),
        };
        return state;
    }

    pub fn deinit(self: *GameState) void {
        self.ecs.deinit();
        self.navMeshGrid.deinit();
        self.blockedCells.deinit();
        self.visibleCells.deinit();
        self.allocator.destroy(self);
    }

    pub fn updateDeltaTime(self: *GameState) void {
        self.deltaTime = @intToFloat(f32, self.timer.lap()) / 1000000000.0;
    }
};

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
    init.initSDL(gameState) catch |err| {
        std.log.err("Failed to initialize: {s}", .{sdl.SDL_GetError()});
        return err;
    };
    defer {
        std.log.info("Shutting down...", .{});
        init.deinitSDL(gameState);
    }

    // Load textures
    gameState.textures = .{
        .player_texture = try draw.loadTexture(gameState.renderer, "assets/olive-oil.png"),
        .enemy_texture = try draw.loadTexture(gameState.renderer, "assets/ainsley.png"),
    };

    // Initialize entities
    try initPlayer(gameState);

    // // TODO: sound disabled for now
    // // Initialize sound + music
    // initSound(gameState);
    // defer sdl.Mix_Quit();

    // Main game loop
    var frameDelta: f32 = 0;
    const invMaxFps: f32 = 1.0 / settings.MAX_FPS;
    while (
        (input.handleInput(gameState) != .exit) and !gameState.keyboard[sdl.SDL_SCANCODE_ESCAPE]
    ) : (
        gameState.updateDeltaTime()
    ) {
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
    try state.ecs.setComponent(
        state.entities.player,
        Entity,
        Entity{ .texture = state.textures.player_texture },
    );
    var playerPosition = Position{
        .x = normalizeWidth(0.0),
        .y = normalizeHeight(0.0),
        .scale = settings.PLAYER_SCALE,
    };
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(
        state.textures.player_texture,
        null,
        null,
        &w,
        &h,
    );
    playerPosition.w = @fabs(normalizeWidth(@intToFloat(f32, w)));
    playerPosition.h = @fabs(normalizeHeight(@intToFloat(f32, h)));
    try state.ecs.setComponent(
        state.entities.player,
        Position,
        playerPosition,
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
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;

        if (state.ecs.hasComponent(entity, Player) and !state.ecs.componentManager.getKnown(entity, Player).isAlive) {
            continue;
        }

        if (state.ecs.hasComponent(entity, Enemy) or state.ecs.hasComponent(entity, Player)) {
            // TODO: Enemy and Player should be replaced with a more generic component e.g. `Renderer` or `Texture`.
            const entityComponent = state.ecs.componentManager.getKnown(entity, Entity);
            const positionComponent = state.ecs.componentManager.getKnown(entity, Position);
            draw.drawEntity(state.renderer, entityComponent, positionComponent);

        } else if (state.ecs.hasComponent(entity, Wall)) {
            // Walls do not currently have textures, so they need to be rendered separately.
            const wall = state.ecs.componentManager.getKnown(entity, Wall);
            draw.drawWall(state.renderer, wall);
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
    // TODO: only for debug purposes
    // Render nav mesh grid
    draw.drawGrid(state.renderer, &state.navMeshGrid, &state.visibleCells);

    handleEnemyAI(state);
    handlePlayer(state);
}

pub fn handlePlayer(state: *GameState) void {
    var player = state.ecs.componentManager.get(state.entities.player, Entity) orelse {
        std.log.err("Could not get player Entity component", .{});
        return;
    };
    var position = state.ecs.componentManager.get(state.entities.player, Position) orelse {
        std.log.err("Could not get player Position component", .{});
        return;
    };

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

    position.x += position.dx;
    position.y += position.dy;

    // Maintain world bounds
    clampPositionToWorldBounds(position);

    const playerPoint = math.Vec2(f32){ .x = position.x, .y = position.y };
    const mousePoint = input.getMousePos();

    // Update visibility map
    for (state.navMeshGrid.grid) |cell, cellId| {
        const isSeen = isPointInLineOfSight(state, cell, playerPoint, mousePoint.sub(playerPoint), settings.PLAYER_FOV);
        state.visibleCells.put(cellId, isSeen) catch unreachable;
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
                    .x = position.x,
                    .y = position.y,
                    .w = position.w,
                    .h = position.h,
                };
            } else {
                collisionBox = Rect(f32){
                    .x = position.x - position.scale * position.w / 2,
                    .y = position.y - position.scale * position.h / 2,
                    .w = position.scale * position.w,
                    .h = position.scale * position.h,
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
        var task = enemyAI.currentPlanQueue.?.peek() orelse continue;
        var primitiveTask = task.primitiveTask.?;

        // Handle task failure due to preconditions invalidated.
        if (!primitiveTask.checkPreconditions(enemyAI.worldState.state)) {
            std.log.info("e:{d} plan failed due to task condition {s}", .{entity, task.name});
            for (primitiveTask.onFailureFunctions) |f| f(entity, enemyAI.worldState.state, state);
            enemyAI.currentPlanQueue.?.deinit();
            enemyAI.currentPlanQueue = null;
            continue;
        }

        // Run the task and handle its response.
        const status = primitiveTask.operator(entity, enemyAI.worldState.state, state);
        switch (status) {
            .Running => {},
            .Succeeded => { _ = enemyAI.currentPlanQueue.?.pop(); },
            .Failed => {
                std.log.info("e:{d} plan failed due to task response {s}", .{entity, task.name});
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

    try state.ecs.setComponent(enemy, EnemyFlankerAI, EnemyFlankerAI.init(state.allocator));
}

//**************************************************
// MISC. HELPER FUNCTIONS
//**************************************************
fn clampPositionToWorldBounds(position: *Position) void {
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
                if (line.intersectsRect(rect)) {
                    return false;
                }
            }
        }
    }
    return isWithinFov;
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
