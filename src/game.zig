const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const init = @import("init.zig");
const input = @import("input.zig");
const draw = @import("draw.zig");
const sound = @import("sound.zig");
const math = @import("math.zig");

const EntityType = @import("ecs/ecs.zig").EntityType;
const Ecs = @import("ecs/ecs.zig").Ecs;

const components = @import("ecs/ecs.zig").components;
pub const Position = components.Position;
pub const Player = components.Player;
pub const Enemy = components.Enemy;
pub const Wall = components.Wall;
pub const Entity = components.Entity;
pub const ComponentTypes = components.ComponentTypes;

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

    delegate: struct {
        update: *const fn (*GameState) void,
        draw: *const fn (*GameState) void,
    } = undefined,

    pub fn init(allocator: std.mem.Allocator) !*GameState {
        const state = try allocator.create(GameState);
        state.* = GameState{
            .allocator = allocator,
            .timer = try std.time.Timer.start(),
            .ecs = try Ecs(ComponentTypes).init(allocator),
        };
        return state;
    }

    pub fn deinit(self: *GameState) void {
        self.ecs.deinit();
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
    var player = state.ecs.componentManager.get(state.entities.player, Entity)
        catch undefined
        orelse undefined;
    var position = state.ecs.componentManager.get(state.entities.player, Position)
        catch undefined
        orelse undefined;

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
        spawnEnemy(state) catch |e| LOGGER.err("Failed to spawn enemy {}", .{ e });
        player.reload = 2;
    }

    // Handle mouse events.
    if (state.mouse[sdl.SDL_BUTTON_LEFT] and !state.keyboard[sdl.SDL_SCANCODE_LCTRL] and player.reload <= 0) {
        spawnWall(state) catch |e| LOGGER.err("Failed to spawn wall {}", .{ e });
        player.reload = 2;
    } else if (state.mouse[sdl.SDL_BUTTON_LEFT] and state.keyboard[sdl.SDL_SCANCODE_LCTRL]) {
        handleDeleteClick(state);
    }

    position.x += position.dx;
    position.y += position.dy;

    // Maintain world bounds
    if (position.x < normalizeWidth(0)) {
        position.x = normalizeWidth(0);
    } else if (position.x + position.scale * position.w >= 1.0) {
        position.x = 1.0 - position.scale * position.w;
    }
    if (position.y < normalizeHeight(0)) {
        position.y = normalizeHeight(0);
    } else if (position.y + position.scale * position.h >= 1.0) {
        position.y = 1.0 - position.scale * position.h;
    }
}

pub fn handleDeleteClick(state: *GameState) void {
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |kv| {
        const entity = kv.key_ptr.*;
        if (state.ecs.hasComponent(entity, Wall) or state.ecs.hasComponent(entity, Enemy)) {
            const position = state.ecs.componentManager.getKnown(entity, Position);
            const mousePos = input.getMousePos();
            const collisionBox = math.Rect(f32){
                .x = position.x,
                .y = position.y,
                .w = position.scale * position.w,
                .h = position.scale * position.h,
            };
            if (math.isCollidingPointxRect(&mousePos, &collisionBox)) {
                state.ecs.removeEntity(entity);
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

    const wall = state.ecs.registerEntity()
        catch return;
    errdefer _ = state.ecs.entityManager.removeEntity(wall);
    try state.ecs.setComponent(wall, Wall, .{
        .rect = .{ .x = (x - w / 2), .y = (y - h / 2), .w = w, .h = h },
        .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 }
    });
    try state.ecs.setComponent(wall, Position, .{
        .x = normalizeWidth(@intToFloat(f32, x - w / 2)),
        .y = normalizeHeight(@intToFloat(f32, y - h / 2)),
        .w = normalizeWidth(w),
        .h = normalizeHeight(h),
    });
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
    };

    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(entity.texture, null, null, &w, &h);
    position.w = normalizeWidth(@intToFloat(f32, w));
    position.h = normalizeHeight(@intToFloat(f32, h));

    position.x -= position.w / 2;
    position.y -= position.h / 2;
    position.x0 -= position.w / 2;
    position.y0 -= position.h / 2;

    const enemy = state.ecs.registerEntity()
        catch return;
    errdefer _ = state.ecs.entityManager.removeEntity(enemy);
    try state.ecs.setComponent(enemy, Enemy, .{});
    try state.ecs.setComponent(enemy, Entity, entity);
    try state.ecs.setComponent(enemy, Position, position);
    // try state.ecs.setComponent(enemy, Physics, .{});
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

            if (position.x < normalizeWidth(0)) {
                position.x = normalizeWidth(0);
            } else if (position.x + position.scale * position.w >= 1.0) {
                position.x = 1.0 - position.scale * position.w;
            }
            if (position.y < normalizeHeight(0)) {
                position.y = normalizeHeight(0);
            } else if (position.y + position.scale * position.h >= 1.0) {
                position.y = 1.0 - position.scale * position.h;
            }
        }
    }
}

pub fn handleLineOfSight(state: *GameState) void {
    const player = state.entities.player;
    const playerPosition = state.ecs.componentManager.getKnown(player, Position);
    const px = @floatToInt(i32, unnormalizeWidth(playerPosition.x + playerPosition.scale * playerPosition.w / 2));
    const py = @floatToInt(i32, unnormalizeHeight(playerPosition.y + playerPosition.scale * playerPosition.h / 2));

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        if (state.ecs.hasComponent(entity, Enemy)) {
            const enemyPosition = state.ecs.componentManager.getKnown(entity, Position);
            const ex = @floatToInt(i32, unnormalizeWidth(enemyPosition.x + enemyPosition.scale * enemyPosition.w / 2));
            const ey = @floatToInt(i32, unnormalizeHeight(enemyPosition.y + enemyPosition.scale * enemyPosition.h / 2));

            const line: Line(f32) = .{
                .a = .{
                    .x = playerPosition.x + playerPosition.scale * playerPosition.w / 2,
                    .y = playerPosition.y + playerPosition.scale * playerPosition.h / 2,
                },
                .b = .{
                    .x = enemyPosition.x + enemyPosition.scale * enemyPosition.w / 2,
                    .y = enemyPosition.y + enemyPosition.scale * enemyPosition.h / 2,
                },
            };

            var color: struct{ r: u8, g: u8, b: u8, a: u8 } = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
            // Check LoS collision with walls
            var it2 = state.ecs.entityManager.iterator();
            while (it2.next()) |keyVal2| {
                const entity2 = keyVal2.key_ptr.*;
                if (state.ecs.hasComponent(entity2, Wall)) {
                    const wall = state.ecs.componentManager.getKnown(entity2, Wall);
                    const rect: math.Rect(f32) = .{
                        .x = normalizeWidth(@intToFloat(f32, wall.rect.x)),
                        .y = normalizeHeight(@intToFloat(f32, wall.rect.y)),
                        .w = normalizeWidth(@intToFloat(f32, wall.rect.w)),
                        .h = normalizeHeight(@intToFloat(f32, wall.rect.h)),
                    };
                    if (isCollidingLineXRect(&line, &rect)) {
                        color.r = 0;
                        color.g = 255;
                        color.b = 0;
                        color.a = 255;
                        break;  // no need to check other collisions since we found one
                    }
                }
            }

            _ = sdl.SDL_SetRenderDrawColor(state.renderer, color.r, color.g, color.b, color.a);
            _ = sdl.SDL_RenderDrawLine(state.renderer, px, py, ex, ey);
        }
    }
}

pub fn Line(comptime T: type) type {
    return struct{ a: math.Vec2(T), b: math.Vec2(T) };
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
    return
        isCollidingLineXLine(line, &l1) or
        isCollidingLineXLine(line, &l2) or
        isCollidingLineXLine(line, &l3) or
        isCollidingLineXLine(line, &l4);
}

pub fn isCollidingLineXLine(l1: *const Line(f32), l2: *const Line(f32)) bool {
    var intersection: math.Vec2(f32) = .{ .x = 0, .y = 0 };

    const a1 = l1.a;
    const a2 = l1.b;

    const b1 = l2.a;
    const b2 = l2.b;

    const b = a2.sub(a1);
    const d = b2.sub(b1);
    const bDotDPerp = b.x * d.y + b.y * d.x;

    // lines are parallel
    if (@fabs(bDotDPerp) < 1e-8) return false;

    const c = b1.sub(a1);
    const t = (c.x * d.y - c.y * d.x) / bDotDPerp;
    if (t < 0 or t > 1) return false;

    const u = (c.x * b.y - c.y * b.x) / bDotDPerp;
    if (u < 0 or u > 1) return false;

    intersection = a1.add(b.mult(t));

    return true;
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
    handleEnemies(state);
    handleLineOfSight(state);
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
        null, null,
        &w, &h,
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

    sound.loadMusic("assets/doom-chant.mp3");
    defer sdl.Mix_Quit();
    sound.playMusic(true);

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
