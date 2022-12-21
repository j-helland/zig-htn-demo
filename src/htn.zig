const std = @import("std");
const game = @import("game");

const ConditionFunction = *const fn ([]const WorldStates) bool;
const EffectFunction = *const fn ([]WorldStates) void;
const OperatorFunction = *const fn (*game.GameState) void;
const WorldStateSensorFunction = *const fn ([]WorldStates, *const game.GameState) void;

pub const ConditionOperator = enum {
    Any,
    All,
};

pub const HtnWorldStateProperties = enum(usize) {

    // For testing
    WsTest,
};

pub const WorldStates = enum {
    Invalid,

    // For testing
    Test,
    TestSwitched,
};

pub const TaskType = enum {
    CompoundTask,
    PrimitiveTask,
};

pub const Task = struct {
    name: []const u8 = undefined,
    taskType: TaskType = undefined,
    compoundTask: ?CompoundTask = null,
    primitiveTask: ?PrimitiveTask = null,

    pub fn free(self: *Task, allocator: std.mem.Allocator) void {
        if (self.compoundTask != null) self.compoundTask.?.free(allocator);
        if (self.primitiveTask != null) self.primitiveTask.?.free(allocator);
    }
};

pub const Method = struct {
    condition: ConditionFunction = undefined,
    subtasks: []const *Task = undefined,

    pub fn free(self: *const Method, allocator: std.mem.Allocator) void {
        allocator.free(self.subtasks);
    }
};

pub const CompoundTask = struct {
    methods: []const Method,

    pub fn findSatisfiedMethod(self: *const CompoundTask, ws: []const WorldStates) ?Method {
        for (self.methods) |method| {
            if (method.condition(ws)) return method;
        }
        return null;
    }

    pub fn free(self: *CompoundTask, allocator: std.mem.Allocator) void {
        for (self.methods) |*method| method.free(allocator);
        allocator.free(self.methods);
    }
};

pub const PrimitiveTask = struct {
    preconditions: []const ConditionFunction = undefined,
    conditionOperator: ConditionOperator = .All,
    effects: []const EffectFunction = undefined,
    operator: OperatorFunction = undefined,

    pub fn free(self: *PrimitiveTask, allocator: std.mem.Allocator) void {
        allocator.free(self.preconditions);
        allocator.free(self.effects);
    }
};

pub const Domain = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(Task),

    /// NOTE: Copies `tasks`.
    pub fn init(allocator: std.mem.Allocator, tasks: std.ArrayList(Task)) Domain {
        return Domain{
            .allocator = allocator,
            .tasks = tasks,
        };
    }

    pub fn deinit(self: *Domain) void {
        for (self.tasks.items) |*t| t.free(self.allocator);
        self.tasks.deinit();
    }
};

pub const DomainBuilder = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    tasksOrdered: std.ArrayList(Task),
    tasksIndexMap: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator) *This {
        var this = allocator.create(This) catch unreachable;
        this.* = This{
            .allocator = allocator,
            .tasksOrdered = std.ArrayList(Task).init(allocator),
            .tasksIndexMap = std.StringHashMap(usize).init(allocator),
        };
        return this;
    }

    pub fn deinit(self: *This) void {
        self.tasksIndexMap.deinit();
        self.allocator.destroy(self);
    }

    /// Starts creation of either a primitive or compound task.
    /// The `name` must be unique.
    pub fn task(self: *This, name: []const u8, comptime T: TaskType) *_TaskBuilderType(T) {
        var builder = _TaskBuilderType(T).init(self.allocator, self, name);
        return builder;
    }

    /// Returns a `Domain` struct.
    /// NOTE: The caller is responsible for calling `deinit` on the returned domain.
    pub fn build(self: *This) Domain {
        var domain = Domain.init(self.allocator, self.tasksOrdered);
        self.deinit();
        return domain;
    }

    /// NOTE: For internal use only.
    /// Used by MethodBuilder to retrieve tasks that are then added as subtasks. This is how recursion is implemented in the HTN domain.
    pub fn _getTaskByName(self: *This, name: []const u8) ?*Task {
        const idx = self.tasksIndexMap.get(name) orelse return null;
        return &self.tasksOrdered.items[idx];
    }

    /// NOTE: For internal use only.
    /// Used by other builders to insert created tasks.
    pub fn _addTask(self: *This, t: Task) void {
        self.tasksIndexMap.putNoClobber(t.name, self.tasksOrdered.items.len) catch {
            std.log.err("Task name {s} already exists", .{ t.name });
            @panic(t.name);
        };
        self.tasksOrdered.append(t) catch unreachable;
    }

    /// NOTE: For internal use only.
    /// Used to comptime get the return type for the `task` function.
    fn _TaskBuilderType(comptime T: TaskType) type {
        return switch(T) {
            .PrimitiveTask => PrimitiveTaskBuilder,
            .CompoundTask => CompoundTaskBuilder,
        };
    }
};

pub const MethodBuilder = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    compoundTaskBuilder: *CompoundTaskBuilder,
    nameValue: []const u8,
    conditionFunctionValue: ConditionFunction = undefined,
    subtasks: std.ArrayList(*Task),

    pub fn init(allocator: std.mem.Allocator, compoundTaskBuilder: *CompoundTaskBuilder, name: []const u8) *This {
        var this = allocator.create(This) catch unreachable;
        this.* = This{
            .allocator = allocator,
            .compoundTaskBuilder = compoundTaskBuilder,
            .nameValue = name,
            .subtasks = std.ArrayList(*Task).init(allocator),
        };
        return this;
    }

    pub fn deinit(self: *This) void {
        self.subtasks.deinit();
        self.allocator.destroy(self);
    }

    pub fn condition(self: *This, _: []const u8, f: ConditionFunction) *This {
        self.conditionFunctionValue = f;
        return self;
    }

    pub fn subtask(self: *This, name: []const u8) *This {
        var task = self.compoundTaskBuilder.domainBuilder._getTaskByName(name) orelse {
            std.log.err("No task with name {s} exists", .{ name });
            @panic(name);
        };
        self.subtasks.append(task) catch unreachable;
        return self;
    }

    // /// For subtasks that haven't been added to the graph already.
    // pub fn subtaskNew(self: *This, task: Task) *This {
    //     self.compoundTaskBuilder.domainBuilder._addTask(task);
    //     return self.subtask(task.name);
    // }

    pub fn end(self: *This) *CompoundTaskBuilder {
        var subtasks = self.allocator.alloc(*Task, self.subtasks.items.len) catch unreachable;
        std.mem.copy(*Task, subtasks, self.subtasks.items);

        var compoundTaskBuilder = self.compoundTaskBuilder;
        compoundTaskBuilder._addMethod(
            Method{
                .condition = self.conditionFunctionValue,
                .subtasks = subtasks,
            }
        );

        self.deinit();
        return compoundTaskBuilder;
    }
};

pub const CompoundTaskBuilder = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    domainBuilder: *DomainBuilder,
    name: []const u8,
    methods: std.ArrayList(Method),

    pub fn init(allocator: std.mem.Allocator, domainBuilder: *DomainBuilder, name: []const u8) *This {
        // Need to immediately create a container for this compound task in case any of its methods recursively reference it as a subtask.
        domainBuilder._addTask(
            Task{
                .name = name,
                .taskType = .CompoundTask,
            }
        );

        var this = allocator.create(This) catch unreachable;
        this.* = This{
            .allocator = allocator,
            .domainBuilder = domainBuilder,
            .name = name,
            .methods = std.ArrayList(Method).init(allocator),
        };
        return this;
    }

    pub fn deinit(self: *This) void {
        self.methods.deinit();
        self.allocator.destroy(self);
    }

    pub fn method(self: *This, name: []const u8) *MethodBuilder {
        var builder = MethodBuilder.init(self.allocator, self, name);
        return builder;
    }

    pub fn end(self: *This) *DomainBuilder {
        var methods = self.allocator.alloc(Method, self.methods.items.len) catch unreachable;
        std.mem.copy(Method, methods, self.methods.items);

        // Update the task container we made during the `init` call.
        var domainBuilder = self.domainBuilder;
        domainBuilder._getTaskByName(self.name).?.*.compoundTask = CompoundTask{
            .methods = methods,
        };

        self.deinit();
        return domainBuilder;
    }

    /// For internal use only
    pub fn _addMethod(self: *This, m: Method) void {
        self.methods.append(m) catch unreachable;
    }
};

pub const PrimitiveTaskBuilder = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    domainBuilder: *DomainBuilder,
    name: []const u8,
    conditions: std.ArrayList(ConditionFunction),
    effects: std.ArrayList(EffectFunction),
    conditionOperatorValue: ConditionOperator = undefined,
    operatorFunctionValue: OperatorFunction = undefined,

    pub fn init(allocator: std.mem.Allocator, domainBuilder: *DomainBuilder, name: []const u8) *This {
        var this = allocator.create(This) catch unreachable;
        this.* = This{
            .allocator = allocator,
            .domainBuilder = domainBuilder,
            .name = name,
            .conditions = std.ArrayList(ConditionFunction).init(allocator),
            .effects = std.ArrayList(EffectFunction).init(allocator),
        };
        return this;
    }

    pub fn deinit(self: *This) void {
        self.conditions.deinit();
        self.effects.deinit();
        self.allocator.destroy(self);
    }

    pub fn condition(self: *This, name: []const u8, f: ConditionFunction) *This {
        _ = name;
        self.conditions.append(f) catch unreachable;
        return self;
    }

    pub fn conditionOperator(self: *This, op: ConditionOperator) *This {
        self.conditionOperatorValue = op;
        return self;
    }

    pub fn effect(self: *This, name: []const u8, f: EffectFunction) *This {
        _ = name;
        self.effects.append(f) catch unreachable;
        return self;
    }

    pub fn operator(self: *This, _: []const u8, op: OperatorFunction) *This {
        self.operatorFunctionValue = op;
        return self;
    }

    pub fn end(self: *This) *DomainBuilder {
        const conditionValues = self.conditions.items;
        var conditions = self.allocator.alloc(ConditionFunction, conditionValues.len) catch unreachable;
        std.mem.copy(ConditionFunction, conditions, conditionValues);

        const effectValues = self.effects.items;
        var effects = self.allocator.alloc(EffectFunction, effectValues.len) catch unreachable;
        std.mem.copy(EffectFunction, effects, effectValues);

        var domainBuilder = self.domainBuilder;
        domainBuilder._addTask(
            Task{
                .name = self.name,
                .taskType = .PrimitiveTask,
                .primitiveTask = PrimitiveTask{
                    .preconditions = conditions,
                    .conditionOperator = self.conditionOperatorValue,
                    .effects = effects,
                    .operator = self.operatorFunctionValue,
                },
            },
        );

        self.deinit();
        return domainBuilder;
    }
};

pub const WorldState = struct {
    allocator: std.mem.Allocator,
    state: []WorldStates,
    sensors: std.ArrayList(WorldStateSensorFunction),

    // All world state values will be initialized as .Invalid
    pub fn init(allocator: std.mem.Allocator) WorldState {
        var state = allocator.alloc(WorldStates, std.meta.fields(HtnWorldStateProperties).len) catch unreachable;
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
    pub fn update(self: *WorldState, gameState: *const game.GameState) void {
        for (self.sensors.items) |sensor| sensor(self.state, gameState);
    }
};

pub const HtnPlannerState = struct {
    plan: std.ArrayList(*Task),
    tasksToProcess: std.ArrayList(*Task),
    worldState: []WorldStates,
};

pub const HtnPlanner = struct {
    allocator: std.mem.Allocator,
    rootTask: Task,
    finalPlan: std.ArrayList(*Task),
    worldState: WorldState,
    decompHistory: std.ArrayList(HtnPlannerState),

    pub fn init(allocator: std.mem.Allocator, rootTask: Task) HtnPlanner {
        return .{
            .allocator = allocator,
            .rootTask = rootTask,
            .finalPlan = std.ArrayList(*Task).init(allocator),
            .worldState = WorldState.init(allocator),
            .decompHistory = std.ArrayList(HtnPlannerState).init(allocator),
        };
    }

    pub fn deinit(self: *HtnPlanner) void {
        self.finalPlan.deinit();
        self.clearDecompHistory();
        self.decompHistory.deinit();
        self.worldState.deinit();
    }

    pub fn processTasks(self: *HtnPlanner) *HtnPlanner {
        var workingWorldState = self.copyWorldState(self.worldState.state);
        defer self.allocator.free(workingWorldState);

        var tasksToProcess = std.ArrayList(*Task).init(self.allocator);
        defer tasksToProcess.deinit();

        tasksToProcess.append(&self.rootTask) catch unreachable;
        while (tasksToProcess.items.len > 0) {
            const task = tasksToProcess.pop();
            switch (task.taskType) {
                .CompoundTask => {
                    const compoundTask = task.compoundTask.?;
                    const method = compoundTask.findSatisfiedMethod(workingWorldState) orelse {
                        self.restoreToLastDecomposedTask(&tasksToProcess, workingWorldState);
                        continue;
                    };

                    self.recordDecompositionOfTask(task, &tasksToProcess, workingWorldState);
                    tasksToProcess.appendSlice(method.subtasks) catch unreachable;
                },

                .PrimitiveTask => {
                    const primitiveTask = task.primitiveTask.?;
                    if (checkPrimitiveTaskConditions(primitiveTask, workingWorldState)) {
                        applyEffects(primitiveTask, workingWorldState);
                        self.finalPlan.append(task) catch unreachable;
                    } else {
                        self.restoreToLastDecomposedTask(&tasksToProcess, workingWorldState);
                    }
                },
            }
        }
        return self;
    }

    /// Get the current plan and clear the history. Should be called after `processTasks`.
    pub fn getPlan(self: *HtnPlanner) std.ArrayList(*Task) {
        defer self.clearDecompHistory();
        defer self.finalPlan.clearRetainingCapacity();
        return self.finalPlan.clone() catch unreachable;
    }

    /// Intended for internal use only.
    pub fn recordDecompositionOfTask(self: *HtnPlanner, currentTask: *Task, tasksToProcess: *std.ArrayList(*Task), ws: []const WorldStates) void {
        var tasksToProcessClone = tasksToProcess.clone() catch unreachable;
        tasksToProcessClone.append(currentTask) catch unreachable;

        self.decompHistory.append(HtnPlannerState{
            .plan = self.finalPlan.clone() catch unreachable,
            .tasksToProcess = tasksToProcessClone,
            .worldState = self.copyWorldState(ws),
        }) catch unreachable;
    }

    /// Intended for internal use only.
    pub fn restoreToLastDecomposedTask(self: *HtnPlanner, tasksToProcess: *std.ArrayList(*Task), ws: []WorldStates) void {
        const state = self.decompHistory.popOrNull() orelse {
            std.log.warn("[HTN] Tried to pop empty decompHistory stack", .{});
            return;
        };

        self.finalPlan.clearRetainingCapacity();
        self.finalPlan.appendSlice(state.plan.items) catch unreachable;
        state.plan.deinit();

        std.mem.copy(WorldStates, ws, state.worldState);
        self.allocator.free(state.worldState);

        tasksToProcess.clearRetainingCapacity();
        tasksToProcess.appendSlice(state.tasksToProcess.items) catch unreachable;
        state.tasksToProcess.deinit();
    }

    /// Intended for internal use only.
    pub fn copyWorldState(self: *HtnPlanner, ws: []const WorldStates) []WorldStates {
        var copy = self.allocator.alloc(WorldStates, ws.len) catch unreachable;
        std.mem.copy(WorldStates, copy, ws);
        return copy;
    }

    fn clearDecompHistory(self: *HtnPlanner) void {
        for (self.decompHistory.items) |state| {
            state.plan.deinit();
            state.tasksToProcess.deinit();
            self.allocator.free(state.worldState);
        }
        self.decompHistory.clearRetainingCapacity();
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
            var result = true;
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

fn operatorNoOp(_: *game.GameState) void {}

test "domain builder" {
    var domain = DomainBuilder.init(std.testing.allocator)
        .task("task name", .PrimitiveTask)
            .condition("first condtion", alwaysReturnTrue)
            .condition("second condition", alwaysReturnTrue)
            .effect("first effect", effectSwitchTestWorldState)
            .operator("operator name", operatorNoOp)
        .end()

        .task("another task name", .PrimitiveTask)
            .condition("first condtion", alwaysReturnTrue)
            .condition("second condition", alwaysReturnTrue)
            .effect("first effect", effectSwitchTestWorldState)
            .operator("operator name", operatorNoOp)
        .end()

        .task("compound task name", .CompoundTask)
            .method("first method name")
                .condition("method condition", alwaysReturnTrue)
                .subtask("another task name")
                .subtask("task name")
            .end()
            .method("second method name")
                .condition("method condition", alwaysReturnTrue)
                // This compound task recursively references itself.
                .subtask("compound task name")
            .end()
        .end()

        .build();

    defer domain.deinit();

    // Ordering of tasks must be preserved.
    try expect(domain.tasks.items.len == 3);
    try expect(std.mem.eql(u8, domain.tasks.items[0].name, "task name"));
    try expect(std.mem.eql(u8, domain.tasks.items[1].name, "another task name"));
    try expect(std.mem.eql(u8, domain.tasks.items[2].name, "compound task name"));

    // Compound task must contain other tasks as subtasks.
    try expect(domain.tasks.items[2].compoundTask != null);
    try expect(domain.tasks.items[2].compoundTask.?.methods.len == 2);
    try expect(domain.tasks.items[2].compoundTask.?.methods[0].subtasks.len == 2);
    try expect(domain.tasks.items[2].compoundTask.?.methods[1].subtasks.len == 1);
    // Ensure subtask ordering is preserved.
    try expect(std.mem.eql(u8, domain.tasks.items[2].compoundTask.?.methods[0].subtasks[0].name, "another task name"));
    try expect(std.mem.eql(u8, domain.tasks.items[2].compoundTask.?.methods[0].subtasks[1].name, "task name"));
    try expect(std.mem.eql(u8, domain.tasks.items[2].compoundTask.?.methods[1].subtasks[0].name, "compound task name"));

    // Ensure that the HTN planner traverses the graph properly.
    var rootTask = domain.tasks.items[2];
    var planner = HtnPlanner.init(std.testing.allocator, rootTask);
    defer planner.deinit();

    // The first method has two subtasks whose conditions are always met, meaning that the final plan should have both.
    // The ordering for the subtasks is stack-based.
    var plan = planner
        .processTasks()
        .getPlan();
    defer plan.deinit();

    try expect(plan.items.len == 2);
    try expect(plan.items[0].taskType == .PrimitiveTask);
    try expect(std.mem.eql(u8, plan.items[0].name, "task name"));
    try expect(std.mem.eql(u8, plan.items[1].name, "another task name"));
}

test "method condition on world state" {
    var task = Task{};
    const method = Method{
        .condition = worldStateTest,
        .subtasks = &[_]*Task{&task},
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

fn sensorWsTest(ws: []WorldStates, _: *const game.GameState) void {
    ws[@enumToInt(HtnWorldStateProperties.WsTest)] = .Test;
}

test "htn world state sensors" {
    var worldState = WorldState.init(std.testing.allocator);
    defer worldState.deinit();

    const gameState = try game.GameState.init(std.testing.allocator);
    defer gameState.deinit();

    try expect(worldState.state[@enumToInt(HtnWorldStateProperties.WsTest)] == .Invalid);
    worldState.registerSensor(sensorWsTest);
    worldState.update(gameState);
    try expect(worldState.state[@enumToInt(HtnWorldStateProperties.WsTest)] == .Test);
}

test "htn planner state restoration" {
    const rootTask = Task{};
    var planner = HtnPlanner.init(std.testing.allocator, rootTask);
    defer planner.deinit();

    planner.worldState.state[@enumToInt(HtnWorldStateProperties.WsTest)] = .Test;

    var task = Task{};
    var tasksToProcess = std.ArrayList(*Task).init(std.testing.allocator);
    defer tasksToProcess.deinit();

    planner.recordDecompositionOfTask(&task, &tasksToProcess, planner.worldState.state);
    try expect(planner.decompHistory.items.len == 1);
    try expect(tasksToProcess.items.len == 0);

    planner.worldState.state[@enumToInt(HtnWorldStateProperties.WsTest)] = .TestSwitched;

    planner.restoreToLastDecomposedTask(&tasksToProcess, planner.worldState.state);
    try expect(planner.decompHistory.items.len == 0);
    try expect(planner.worldState.state[@enumToInt(HtnWorldStateProperties.WsTest)] == .Test);
    try expect(tasksToProcess.items.len == 1);
}

