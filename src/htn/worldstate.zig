const std = @import("std");
const game = @import("game");

const htn = @import("htn.zig");
const PrimitiveTask = htn.PrimitiveTask;

pub const EffectFunction = *const fn ([]WorldStateValue) void;
pub const WorldStateSensorFunction = *const fn (usize, []WorldStateValue, *game.GameState) void;

pub const WorldStateKey = enum(usize) {
    WsIsPlayerSeenByEntity,
    WsIsEntitySeenByPlayer,
    WsIsHunting,
    WsLocation,
    WsIsPlayerInRange,

    // For testing
    WsTest,
};

pub const WorldStateValue = enum {
    Invalid,
    True,
    False,

    // Location
    NearestCoverLocRef,
    NextCoverLocRef,
    LastPlayerLocRef,

    // For testing
    Test,
    TestSwitched,
};

pub const WorldState = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    state: []WorldStateValue,
    sensors: std.ArrayList(WorldStateSensorFunction),

    // All world state values will be initialized as .Invalid
    pub fn init(allocator: std.mem.Allocator) This {
        var state = allocator.alloc(WorldStateValue, std.meta.fields(WorldStateKey).len) catch unreachable;
        for (state) |_, i| state[i] = .Invalid;

        return This{
            .allocator = allocator,
            .state = state,
            .sensors = std.ArrayList(WorldStateSensorFunction).init(allocator),
        };
    }

    pub fn deinit(self: *This) void {
        self.allocator.free(self.state);
        self.sensors.deinit();
    }

    pub fn get(self: *This, key: WorldStateKey) WorldStateValue {
        return self.state[@enumToInt(key)];
    }

    pub fn set(self: *This, key: WorldStateKey, val: WorldStateValue) void {
        self.state[@enumToInt(key)] = val;
    }

    pub fn registerSensor(self: *This, sensor: WorldStateSensorFunction) void {
        self.sensors.append(sensor) catch unreachable;
    }

    /// Applies updates from sensors
    pub fn updateSensors(self: *This, entity: usize, gameState: *game.GameState) void {
        for (self.sensors.items) |sensor| sensor(entity, self.state, gameState);
    }
};

pub fn wsSet(ws: []WorldStateValue, key: WorldStateKey, val: WorldStateValue) void {
    ws[@enumToInt(key)] = val;
}

pub fn wsGet(ws: []const WorldStateValue, key: WorldStateKey) WorldStateValue {
    return ws[@enumToInt(key)];
}

pub fn applyEffects(task: htn.PrimitiveTask, worldState: []WorldStateValue) void {
    for (task.effects) |e| e(worldState);
}


// // TODO: move to separate file to avoid error where tests cause WorldState to depend on itself.
// const expect = std.testing.expect;

// fn sensorTest(ws: []WorldStateValue, _: *const game.GameState) void {
//     ws[@enumToInt(WorldStateKey.WsTest)] = .Test;
// }

// fn effectTest(ws: []WorldStateValue) void {
//     ws[@enumToInt(WorldStateKey.WsTest)] = .TestSwitched;
// }

// test "apply effects" {
//     var ws = WorldState.init(std.testing.allocator);
//     defer ws.deinit();

//     const task = PrimitiveTask{
//         .effects = &[_]EffectFunction{effectTest},
//     };
//     applyEffects(task, ws.state);
//     try expect(ws.get(.WsTest) == .TestSwitched);
// }

// test "htn world state sensors" {
//     var worldState = WorldState.init(std.testing.allocator);
//     defer worldState.deinit();

//     const gameState = try game.GameState.init(std.testing.allocator);
//     defer gameState.deinit();

//     try expect(worldState.state[@enumToInt(WorldStateKey.WsTest)] == .Invalid);
//     worldState.registerSensor(sensorTest);
//     worldState.updateSensors(gameState);
//     try expect(worldState.state[@enumToInt(WorldStateKey.WsTest)] == .Test);
// }
