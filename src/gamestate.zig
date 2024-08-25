const std = @import("std");

const sdl = @import("sdl.zig");
const settings = @import("settings.zig");
const math = @import("math.zig");

const nav = @import("nav.zig");
pub const NavMeshGrid = nav.NavMeshGrid;

pub const EntityType = @import("ecs/ecs.zig").EntityType;
const Ecs = @import("ecs/ecs.zig").Ecs;

const components = @import("ecs/ecs.zig").components;
pub const Texture = components.Texture;
pub const Position = components.Position;
pub const Player = components.Player;
pub const Camera = components.Camera;
pub const Enemy = components.Enemy;
pub const Wall = components.Wall;
pub const EnemyFlankerAI = @import("ai.zig").EnemyFlankerAI;

const ComponentTypes = .{
    Texture,
    Position,
    Player,
    Camera,
    Enemy,
    Wall,
    EnemyFlankerAI,
};

pub const GameState = struct {
    allocator: std.mem.Allocator,
    rng: std.Random.DefaultPrng,

    timer: std.time.Timer,
    deltaTime: f32 = 0.0,

    // Entity Component System (ECS) state
    ecs: Ecs(ComponentTypes),
    entities: struct {
        player: EntityType = undefined,
        camera: EntityType = undefined,
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
            .w = normalizeWidth(settings.DEFAULT_WORLD_WIDTH),
            .h = normalizeHeight(settings.DEFAULT_WORLD_HEIGHT),
        };

        const state = try allocator.create(GameState);
        state.* = GameState{
            .allocator = allocator,
            .timer = try std.time.Timer.start(),
            .rng = std.Random.DefaultPrng.init(0),
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
        self.deltaTime = @as(f32, @floatFromInt(self.timer.lap())) / 1000000000.0;
    }
};

pub fn normalizeWidth(w: f32) f32 {
    return w / @as(f32, @floatFromInt(settings.DEFAULT_WORLD_WIDTH));
}

pub fn unnormalizeWidth(w: f32) f32 {
    return @as(f32, @floatFromInt(settings.DEFAULT_WORLD_WIDTH)) * (w);
}

pub fn normalizeHeight(h: f32) f32 {
    return h / @as(f32, @floatFromInt(settings.DEFAULT_WORLD_HEIGHT));
}

pub fn unnormalizeHeight(h: f32) f32 {
    return @as(f32, @floatFromInt(settings.DEFAULT_WORLD_HEIGHT)) * (h);
}

/// Get the current mouse position in world coordinates.
pub fn getMousePos(state: *GameState) math.Vec2(f32) {
    const loggingContext = "game.zig::getMousePos";

    // Get mouse position in world coordinates assuming that the camera is positioned at the origin.
    var x: i32 = undefined;
    var y: i32 = undefined;
    _ = sdl.SDL_GetMouseState(&x, &y);
    const mousePos = math.Vec2(f32){
        .x = normalizeWidth(@as(f32, @floatFromInt(x))),
        .y = normalizeHeight(@as(f32, @floatFromInt(y))),
    };

    // Offset the mouse position using the camera position to get the actual world coordinates.
    const camera = state.ecs.componentManager.get(state.entities.camera, Camera) orelse {
        std.log.err("[{s}] e:{d} could not get Camera component", .{ loggingContext, state.entities.camera });
        @panic("Could not get Camera");
    };
    return camera.unnormalize(mousePos);
}
