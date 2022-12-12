const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const init = @import("init.zig");
const input = @import("input.zig");
const draw = @import("draw.zig");
const sound = @import("sound.zig");

const EntityType = @import("ecs/ecs.zig").EntityType;
const Ecs = @import("ecs/ecs.zig").Ecs;
const components = @import("ecs/ecs.zig").components;
const Position = components.Position;
const Player = components.Player;
const Enemy = components.Enemy;

const structs = @import("structs.zig");
const Entity = structs.Entity;
const Stage = structs.Stage;

pub fn EntityIdMap(comptime T: type) type {
    return std.AutoArrayHashMap(u32, T);
}

pub const GameState = struct {
    allocator: std.mem.Allocator,

    ecs: Ecs,
    entities: struct {
        player: EntityType = undefined,
    } = .{},

    frame: usize = 0,
    stage: Stage = .{},

    keyboard: [settings.MAX_KEYBOARD_KEYS]bool = [_]bool{false} ** settings.MAX_KEYBOARD_KEYS,
    renderer: *sdl.SDL_Renderer = undefined,
    window: *sdl.SDL_Window = undefined,
    textures: struct {
        player_texture: *sdl.SDL_Texture = undefined,
        bullet_texture: *sdl.SDL_Texture = undefined,
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
            .ecs = try Ecs.init(allocator),
        };
        return state;
    }

    pub fn deinit(self: *GameState) void {
        self.stage.bullets.deinit();
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
        playSound(state.sounds.player_fire, .ch_any);
        spawnEnemy(state, position);
        player.reload = 8;
    }

    position.x += position.dx;
    position.y += position.dy;
}

pub fn spawnEnemy(state: *GameState, initialPosition: *const Position) void {
    var entity = Entity{
        .health = 1,
        .texture = state.textures.bullet_texture,
    };

    var position = Position{
        .x = initialPosition.x,
        .y = initialPosition.y,
        .x0 = initialPosition.x,
        .y0 = initialPosition.y,
        .dx = settings.PLAYER_BULLET_SPEED,
    };

    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(entity.texture, null, null, &w, &h);
    position.w = @intToFloat(f32, w);
    position.h = @intToFloat(f32, h);

    position.y -= initialPosition.h / 2.0 + position.h / 2.0;
    position.x -= initialPosition.w / 2.0;

    const enemy = state.ecs.registerEntity()
        catch return;
    errdefer state.ecs.entityManager.removeEntity(enemy);
    state.ecs.setComponent(enemy, Enemy, .{}) catch return;
    state.ecs.setComponent(enemy, Entity, entity) catch return;
    state.ecs.setComponent(enemy, Position, position) catch return;
}

pub fn handleBullets(state: *GameState) void {
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyValue| {
        const entity = keyValue.key_ptr.*;
        if (state.ecs.hasComponent(entity, Enemy)) {
            var enemy = state.ecs.componentManager.getKnown(entity, Entity);
            var position = state.ecs.componentManager.getKnown(entity, Position);

            const a = @intToFloat(f32, enemy.frame) * std.math.pi / 180.0;
            const rx = 0.34 * @cos(0.25 * a);
            position.x += rx * @cos(a) - (position.x - position.x0);
            position.y += rx * @sin(a) - (position.y - position.y0);
            enemy.frame += 1;
        }
    }

    // var i = state.stage.bullets.items.len;
    // while (i > 0 and state.stage.bullets.items[i - 1].x > settings.DEFAULT_WINDOW_WIDTH) : (i -= 1) {
    //     _ = state.stage.bullets.pop();
    // }
}

pub fn update(state: *GameState) void {
    handlePlayer(state);
    handleBullets(state);
}

pub fn drawPlayer(
    renderer: *sdl.SDL_Renderer,
    player: *const Entity,
    position: *const Position,
) void {
    draw.blit(
        renderer,
        player.texture,
        @floatToInt(i32, unnormalizeWidth(position.x)),
        @floatToInt(i32, unnormalizeHeight(position.y)),
        1.0);
}

pub fn drawEnemy(
    renderer: *sdl.SDL_Renderer,
    enemy: *const Entity,
    position: *const Position,
) void {
    const scale = (@cos(2.1 * @intToFloat(f32, enemy.frame) * std.math.pi / 180.0) + 1.2);
    draw.blit(
        renderer,
        enemy.texture,
        @floatToInt(i32, unnormalizeWidth(position.x)),
        @floatToInt(i32, unnormalizeHeight(position.y)),
        0.5 * scale);
}

pub fn drawScene(state: *GameState) void {
    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        // const signature = keyVal.value_ptr;
        if (state.ecs.hasComponent(entity, Player)) {
            const player = state.ecs.componentManager.getKnown(entity, Entity);
            const position = state.ecs.componentManager.getKnown(entity, Position);
            drawPlayer(state.renderer, player, position);

        } else if (state.ecs.hasComponent(entity, Enemy)) {
            const enemy = state.ecs.componentManager.getKnown(entity, Entity);
            const position = state.ecs.componentManager.getKnown(entity, Position);
            drawEnemy(state.renderer, enemy, position);
        }
    }

    draw.presentScene(state);
}

pub fn initStage(state: *GameState) void {
    state.delegate = .{
        .update = &update,
        .draw = &drawScene,
    };

    state.stage.bullets = std.ArrayList(Entity).init(state.allocator);
}

pub var MUSIC: ?*sdl.Mix_Music = null;
pub fn loadMusic(filename: [*c]const u8) void {
    if (MUSIC != null) {
        _ = sdl.Mix_HaltMusic();
        sdl.Mix_FreeMusic(MUSIC);
        MUSIC = null;
    }
    MUSIC = sdl.Mix_LoadMUS(filename);
}

pub fn playMusic(loop: bool) void {
    _ = sdl.Mix_PlayMusic(MUSIC, if (loop) -1 else 0);
}

pub fn playSound(s: [*c]sdl.Mix_Chunk, channel: sound.SoundChannels) void {
    _ = sdl.Mix_PlayChannel(@enumToInt(channel), s, 0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    GAME_STATE = try GameState.init(allocator);
    defer GAME_STATE.deinit();

    // Register ECS components
    try GAME_STATE.ecs.registerComponent(Entity);
    defer GAME_STATE.ecs.componentManager.deinitComponent(Entity);

    try GAME_STATE.ecs.registerComponent(Position);
    defer GAME_STATE.ecs.componentManager.deinitComponent(Position);

    try GAME_STATE.ecs.registerComponent(Player);
    defer GAME_STATE.ecs.componentManager.deinitComponent(Player);

    try GAME_STATE.ecs.registerComponent(Enemy);
    defer GAME_STATE.ecs.componentManager.deinitComponent(Enemy);

    // Stage init
    initStage(GAME_STATE);

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
        .bullet_texture = try draw.loadTexture(GAME_STATE.renderer, "assets/ainsley.png"),
    };

    // Initialize entities
    GAME_STATE.entities.player = try GAME_STATE.ecs.registerEntity();
    try GAME_STATE.ecs.setComponent(GAME_STATE.entities.player, Player, .{});
    try GAME_STATE.ecs.setComponent(
        GAME_STATE.entities.player,
        Entity,
        Entity{ .texture = GAME_STATE.textures.player_texture },
    );
    try GAME_STATE.ecs.setComponent(
        GAME_STATE.entities.player,
        Position,
        Position{
            .x = normalizeWidth(0.0),
            .y = normalizeHeight(0.0),
        },
    );

    // Initialize sound + music
    GAME_STATE.sounds = sound.initSounds();

    loadMusic("assets/doom-chant.mp3");
    defer sdl.Mix_Quit();
    playMusic(true);

    // Main game loop
    while (input.handleInput(GAME_STATE) != .exit and !GAME_STATE.keyboard[sdl.SDL_SCANCODE_ESCAPE]) : (GAME_STATE.frame += 1) {
        draw.prepareScene(GAME_STATE);

        try GAME_STATE.update();
        GAME_STATE.draw();

        sdl.SDL_Delay(16);
    }
}

pub fn normalizeWidth(w: f32) f32 {
    return w / @intToFloat(f32, settings.DEFAULT_WINDOW_WIDTH) - 0.5;
}

pub fn unnormalizeWidth(w: f32) f32 {
    return @intToFloat(f32, settings.DEFAULT_WINDOW_WIDTH) * (w + 0.5);
}

pub fn normalizeHeight(h: f32) f32 {
    return h / @intToFloat(f32, settings.DEFAULT_WINDOW_WIDTH) - 0.5;
}

pub fn unnormalizeHeight(h: f32) f32 {
    return @intToFloat(f32, settings.DEFAULT_WINDOW_WIDTH) * (h + 0.5);
}
