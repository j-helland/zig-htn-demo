const std = @import("std");
const game = @import("game");

const htn = @import("htn.zig");
const PrimitiveTask = htn.PrimitiveTask;

pub const EffectFunction = *const fn ([]WorldStateValue) void;
pub const WorldStateSensorFunction = *const fn ([]WorldStateValue, *const game.GameState) void;

pub const WorldStateKey = enum(usize) {

    // For testing
    WsTest,
};

pub const WorldStateValue = enum {
    Invalid,

    // For testing
    Test,
    TestSwitched,
};

pub const WorldState = struct {
    allocator: std.mem.Allocator,
    state: []WorldStateValue,
    sensors: std.ArrayList(WorldStateSensorFunction),

    // All world state values will be initialized as .Invalid
    pub fn init(allocator: std.mem.Allocator) WorldState {
        var state = allocator.alloc(WorldStateValue, std.meta.fields(WorldStateKey).len) catch unreachable;
        for (state) |_, i| state[i] = .Invalid;

        return WorldState{
            .allocator = allocator,
            .state = state,
            .sensors = std.ArrayList(WorldStateSensorFunction).init(allocator),
        };
    }

    pub fn deinit(self: *WorldState) void {
        self.allocator.free(self.state);
        self.sensors.deinit();
    }

    pub fn registerSensor(self: *WorldState, sensor: WorldStateSensorFunction) void {
        self.sensors.append(sensor) catch unreachable;
    }

    /// Applies updates from sensors
    pub fn updateSensors(self: *WorldState, gameState: *const game.GameState) void {
        for (self.sensors.items) |sensor| sensor(self.state, gameState);
    }
};

pub fn applyEffects(task: htn.PrimitiveTask, worldState: []WorldStateValue) void {
    for (task.effects) |e| e(worldState);
}


const expect = std.testing.expect;

fn sensorTest(ws: []WorldStateValue, _: *const game.GameState) void {
    ws[@enumToInt(WorldStateKey.WsTest)] = .Test;
}

fn effectTest(ws: []WorldStateValue) void {
    ws[@enumToInt(WorldStateKey.WsTest)] = .TestSwitched;
}

test "apply effects" {
    var ws = WorldState.init(std.testing.allocator);
    defer ws.deinit();

    const task = PrimitiveTask{
        .effects = &[_]EffectFunction{effectTest},
    };
    applyEffects(task, ws.state);
    try expect(ws.state[0] == .TestSwitched);
}

test "htn world state sensors" {
    var worldState = WorldState.init(std.testing.allocator);
    defer worldState.deinit();

    const gameState = try game.GameState.init(std.testing.allocator);
    defer gameState.deinit();

    try expect(worldState.state[@enumToInt(WorldStateKey.WsTest)] == .Invalid);
    worldState.registerSensor(sensorTest);
    worldState.updateSensors(gameState);
    try expect(worldState.state[@enumToInt(WorldStateKey.WsTest)] == .Test);
}
