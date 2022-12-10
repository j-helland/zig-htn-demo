const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const init = @import("init.zig");
const input = @import("input.zig");
const draw = @import("draw.zig");
const sound = @import("sound.zig");

const structs = @import("structs.zig");
const Entity = structs.Entity;
const Stage = structs.Stage;

pub fn EntityIdMap(comptime T: type) type {
    return std.AutoArrayHashMap(u32, T);
}

pub const GameState = struct {
    allocator: std.mem.Allocator,
    entities: EntityIdMap(*Entity),
    nextId: u32 = 0,
    frame: usize = 0,

    keyboard: [settings.MAX_KEYBOARD_KEYS]bool = [_]bool{false} ** settings.MAX_KEYBOARD_KEYS,

    player: Entity = .{},
    stage: Stage = .{},

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
            .entities = EntityIdMap(*Entity).init(allocator),
        };
        return state;
    }

    pub fn deinit(self: *GameState) void {
        self.stage.bullets.deinit();
        self.entities.deinit();
        self.allocator.destroy(self);
    }

    pub fn registerEntity(self: *GameState, entity: *Entity) !u32 {
        const id = self.nextId;
        try self.entities.put(id, entity);
        self.nextId += 1;
        return id;
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
    state.player.dx = 0;
    state.player.dy = 0;

    if (state.player.reload > 0) {
        state.player.reload -= 1;
    }

    if (state.keyboard[sdl.SDL_SCANCODE_UP] or state.keyboard[sdl.SDL_SCANCODE_W]) {
        state.player.dy = -settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_DOWN] or state.keyboard[sdl.SDL_SCANCODE_S]) {
        state.player.dy = settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_LEFT] or state.keyboard[sdl.SDL_SCANCODE_A]) {
        state.player.dx -= settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_RIGHT] or state.keyboard[sdl.SDL_SCANCODE_D]) {
        state.player.dx += settings.PLAYER_SPEED;
    }
    if (state.keyboard[sdl.SDL_SCANCODE_SPACE] and state.player.reload <= 0) {
        playSound(state.sounds.player_fire, .ch_any);
        fireBullet(state);
    }

    state.player.x += state.player.dx;
    state.player.y += state.player.dy;
}

pub fn fireBullet(state: *GameState) void {
    var bullet: Entity = .{
        .x = state.player.x,
        .y = state.player.y,
        .x0 = state.player.x,
        .y0 = state.player.y,
        .dx = settings.PLAYER_BULLET_SPEED,
        .health = 1,
        .texture = state.textures.bullet_texture,
    };

    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = sdl.SDL_QueryTexture(bullet.texture, null, null, &w, &h);
    bullet.w = @intToFloat(f32, w);
    bullet.h = @intToFloat(f32, h);

    bullet.y -= state.player.h / 2.0 + bullet.h / 2.0;
    bullet.x -= state.player.w / 2.0;

    state.player.reload = 8;

    state.stage.bullets.append(bullet) catch unreachable;
    _ = state.registerEntity(&bullet) catch unreachable;
}

pub fn handleBullets(state: *GameState) void {
    for (state.stage.bullets.items) |*bullet| {
        const a = @intToFloat(f32, bullet.frame) * std.math.pi / 180.0;
        const rx = 0.34 * @cos(0.25 * a);
        bullet.x += rx * @cos(a) - (bullet.x - bullet.x0);
        bullet.y += rx * @sin(a) - (bullet.y - bullet.y0);
        bullet.frame += 1;
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

pub fn drawPlayer(state: *GameState) void {
    draw.blit(
        state.renderer,
        state.player.texture,
        @floatToInt(i32, unnormalizeWidth(state.player.x)),
        @floatToInt(i32, unnormalizeHeight(state.player.y)),
        1.0);
}

pub fn drawBullets(state: *GameState) void {
    for (state.stage.bullets.items) |bullet| {
        const scale = (@cos(2.1 * @intToFloat(f32, bullet.frame) * std.math.pi / 180.0) + 1.2);
        draw.blit(
            state.renderer,
            bullet.texture,
            @floatToInt(i32, unnormalizeWidth(bullet.x)),
            @floatToInt(i32, unnormalizeHeight(bullet.y)),
            0.5 * scale);
    }
}

pub fn drawScene(state: *GameState) void {
    drawBullets(state);
    drawPlayer(state);

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
        .player_texture = try draw.loadTexture(GAME_STATE.renderer, "assets/ainsley.png"),
        .bullet_texture = try draw.loadTexture(GAME_STATE.renderer, "assets/ainsley.png"),
    };

    // Initialize entities
    GAME_STATE.player = Entity{
        .x = normalizeWidth(0.0),
        .y = normalizeHeight(0.0),
        .texture = GAME_STATE.textures.player_texture,
    };
    _ = try GAME_STATE.registerEntity(&GAME_STATE.player);

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
