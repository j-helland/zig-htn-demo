/// Compound Task [BeEnemyFlanker]
///   Method [isSeen == true]
///     Subtasks [navigateToCover()]
///   Method [isSeen == false]
///     Subtasks [navigateToPlayer()]
///
/// Primitive Task [navigateToCover]
///   Preconditions [isSeen == true]
///   Operator [navigateToCoverOperator]
///   Effects [WsLocation = CoverLocationRef]
/// Primitive Task [navigateToPlayer]
///   Preconditions [isSeen == false]
///   Operator [navigateToPlayerOperator]
///   Effects [WsLocation = PlayerLocationRef]
const std = @import("std");
const game = @import("game");

const ConditionFunction = *const fn ([]const WorldStates) bool;
const EffectFunction = *const fn ([]WorldStates) void;
const OperatorFunction = *const fn (*game.GameState) void;

pub const ConditionOperator = enum {
    Any,
    All,
};

pub const HtnWorldStateProperties = enum(usize) {
    WsTest,
};

pub const WorldStates = enum {
    Test,
    TestSwitched,
};

pub const TaskType = enum {
    CompoundTask,
    PrimitiveTask,
};

pub const Task = struct {
    taskType: TaskType = undefined,
    compoundTask: ?CompoundTask = null,
    primitiveTask: ?PrimitiveTask = null,
};

pub const Method = struct {
    condition: ConditionFunction = undefined,
    subTasks: []const Task = undefined,
};

pub const CompoundTask = struct {
    methods: []const Method,

    pub fn findSatisfiedMethod(self: *const CompoundTask, ws: []const WorldStates) ?Method {
        for (self.methods) |method| {
            if (method.condition(ws)) return method;
        }
        return null;
    }
};

pub const PrimitiveTask = struct {
    preconditions: []const ConditionFunction = undefined,
    conditionOperator: ConditionOperator = .All,
    effects: []const EffectFunction = undefined,
    operator: OperatorFunction = undefined,
};

pub const HtnPlanner = struct {
    allocator: std.mem.Allocator,
    rootTask: Task,
    finalPlan: std.ArrayList(Task),
    currentWorldState: []WorldStates,

    pub fn init(allocator: std.mem.Allocator, rootTask: Task) HtnPlanner {
        var worldState = [_]WorldStates{.Test} ** std.meta.fields(HtnWorldStateProperties).len;

        return .{
            .allocator = allocator,
            .rootTask = rootTask,
            .finalPlan = std.ArrayList(Task).init(allocator),
            .currentWorldState = &worldState,
        };
    }

    pub fn deinit(self: *HtnPlanner) void {
        self.finalPlan.deinit();
    }

    pub fn processTasks(self: *HtnPlanner) void {
        var workingWorldState = self.allocator.alloc(WorldStates, self.currentWorldState.len);
        std.mem.copy(WorldStates, workingWorldState, self.currentWorldState);
        defer self.allocator.free(workingWorldState);

        var tasksToProcess = std.ArrayList(Task).init(self.allocator);
        defer tasksToProcess.deinit();

        tasksToProcess.append(self.rootTask) catch unreachable;
        while (tasksToProcess.items.len > 0) {
            const task = tasksToProcess.pop();
            switch (task.taskType) {
                .CompoundTask => {
                    const method = self.findSatisfiedMethod() orelse self.restoreToLastDecomposedTask();

                    self.recordDecompositionOfTask(task);
                    tasksToProcess.appendSlice(method.subTasks);
                },

                .PrimitiveTask => {
                    if (checkPrimitiveConditionOperator(task, workingWorldState)) {
                        applyEffects(task, workingWorldState);
                        self.finalPlan.append(task) orelse unreachable;
                    } else {
                        self.restoreToLastDecomposedTask();
                    }
                },

                else => unreachable,
            }
        }
    }

    pub fn recordDecompositionOfTask(self: *HtnPlanner, currentTask: Task) void {
        // TODO
        _ = self;
        _ = currentTask;
    }

    pub fn restoreToLastDecomposedTask(self: *HtnPlanner) void {
        // TODO
        _ = self;
    }
};

pub fn applyEffects(task: PrimitiveTask, ws: []WorldStates) void {
    for (task.effects) |effect| {
        effect(ws);
    }
}

pub fn checkPrimitiveTaskConditions(task: PrimitiveTask, worldState: []const WorldStates) bool {
    return switch (task.conditionOperator) {
        .Any => {
            var result = false;
            for (task.preconditions) |precondition| {
                result = result or precondition(worldState);
            }
            return result;
        },
        .All => {
            var result = false;
            for (task.preconditions) |precondition| {
                result = result and precondition(worldState);
            }
            return result;
        },
    };
}

pub fn isMethodConditionSatisfied(method: Method, worldState: []WorldStates) bool {
    return method.condition(worldState);
}

const expect = std.testing.expect;

fn alwaysReturnTrue(_: []const WorldStates) bool {
    return true;
}

fn alwaysReturnFalse(_: []const WorldStates) bool {
    return false;
}

fn worldStateTest(ws: []const WorldStates) bool {
    return ws[@enumToInt(HtnWorldStateProperties.WsTest)] == .Test;
}

fn effectSwitchTestWorldState(ws: []WorldStates) void {
    ws[@enumToInt(HtnWorldStateProperties.WsTest)] = .TestSwitched;
}

test "method condition on world state" {
    const method = Method{
        .condition = worldStateTest,
        .subTasks = &[_]Task{.{}},
    };
    var worldState = [_]WorldStates{.Test};

    try expect(isMethodConditionSatisfied(method, &worldState));
}

test "primitive task preconditions" {
    var task = PrimitiveTask{
        .preconditions = &[_]ConditionFunction{ alwaysReturnTrue, alwaysReturnFalse },
    };
    const worldState = &[_]WorldStates{};

    task.conditionOperator = .Any;
    try expect(checkPrimitiveTaskConditions(task, worldState));

    task.conditionOperator = .All;
    try expect(!checkPrimitiveTaskConditions(task, worldState));
}

test "compound task findSatisfiedMethod" {
    const task = CompoundTask{
        .methods = &[_]Method{
            .{ .condition = alwaysReturnTrue },
            .{ .condition = alwaysReturnFalse },
            .{ .condition = worldStateTest },
        },
    };
    const worldState = &[_]WorldStates{.Test};
    const method = task.findSatisfiedMethod(worldState);
    try expect(method != null);
    try expect(method.?.condition == &alwaysReturnTrue);
}

test "apply effects" {
    const task = PrimitiveTask{
        .effects = &[_]EffectFunction{effectSwitchTestWorldState},
    };
    var ws = [_]WorldStates{.Test};
    applyEffects(task, &ws);
    try expect(ws[0] == .TestSwitched);
}

test "test" {
    const rootTask = Task{};
    const planner = HtnPlanner.init(std.testing.allocator, rootTask);
    _ = planner;
}
