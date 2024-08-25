const std = @import("std");
const gamestate = @import("../gamestate.zig");

const htn = @import("htn.zig");
const WorldState = htn.WorldState;
const WorldStateKey = htn.WorldStateKey;
const WorldStateValue = htn.WorldStateValue;
const EffectFunction = htn.EffectFunction;
const HtnPlanner = htn.HtnPlanner;

const ConditionFunction = *const fn ([]const WorldStateValue) bool;
const OperatorFunction = *const fn (usize, []WorldStateValue, *gamestate.GameState) TaskStatus;
const OnFailureFunction = *const fn (usize, []WorldStateValue, *gamestate.GameState) void;

pub const ConditionOperator = enum {
    Any,
    All,
};

pub const TaskType = enum {
    CompoundTask,
    PrimitiveTask,
};

pub const TaskStatus = enum {
    Succeeded,
    Failed,
    Running,
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

    pub fn findSatisfiedMethod(self: *const CompoundTask, ws: []const WorldStateValue) ?Method {
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
    onFailureFunctions: []const OnFailureFunction = undefined,

    pub fn free(self: *PrimitiveTask, allocator: std.mem.Allocator) void {
        allocator.free(self.preconditions);
        allocator.free(self.effects);
        allocator.free(self.onFailureFunctions);
    }

    pub fn checkPreconditions(self: *const PrimitiveTask, worldState: []const WorldStateValue) bool {
        return switch (self.conditionOperator) {
            .Any => {
                var result = false;
                for (self.preconditions) |precondition| {
                    result = result or precondition(worldState);
                }
                return result;
            },
            .All => {
                var result = true;
                for (self.preconditions) |precondition| {
                    result = result and precondition(worldState);
                }
                return result;
            },
        };
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

    pub fn getTaskByName(self: *Domain, name: []const u8) ?Task {
        for (self.tasks.items) |t| {
            if (std.mem.eql(u8, t.name, name)) return t;
        }
        return null;
    }
};

pub const DomainBuilder = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    tasksOrdered: std.ArrayList(Task),
    tasksIndexMap: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator) *This {
        const this = allocator.create(This) catch unreachable;
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
        const builder = _TaskBuilderType(T).init(self.allocator, self, name);
        return builder;
    }

    /// Returns a `Domain` struct.
    /// NOTE: The caller is responsible for calling `deinit` on the returned domain.
    pub fn build(self: *This) Domain {
        const domain = Domain.init(self.allocator, self.tasksOrdered);
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
            std.log.err("Task name {s} already exists", .{t.name});
            @panic(t.name);
        };
        self.tasksOrdered.append(t) catch unreachable;
    }

    /// NOTE: For internal use only.
    /// Used to comptime get the return type for the `task` function.
    fn _TaskBuilderType(comptime T: TaskType) type {
        return switch (T) {
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
        const this = allocator.create(This) catch unreachable;
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
        const task = self.compoundTaskBuilder.domainBuilder._getTaskByName(name) orelse {
            std.log.err("No task with name {s} exists", .{name});
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
        const subtasks = self.allocator.alloc(*Task, self.subtasks.items.len) catch unreachable;
        @memcpy(subtasks, self.subtasks.items);

        var compoundTaskBuilder = self.compoundTaskBuilder;
        compoundTaskBuilder._addMethod(Method{
            .condition = self.conditionFunctionValue,
            .subtasks = subtasks,
        });

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
        domainBuilder._addTask(Task{
            .name = name,
            .taskType = .CompoundTask,
        });

        const this = allocator.create(This) catch unreachable;
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
        const builder = MethodBuilder.init(self.allocator, self, name);
        return builder;
    }

    pub fn end(self: *This) *DomainBuilder {
        const methods = self.allocator.alloc(Method, self.methods.items.len) catch unreachable;
        @memcpy(methods, self.methods.items);

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
    onFailureFunctions: std.ArrayList(OnFailureFunction),

    pub fn init(allocator: std.mem.Allocator, domainBuilder: *DomainBuilder, name: []const u8) *This {
        const this = allocator.create(This) catch unreachable;
        this.* = This{
            .allocator = allocator,
            .domainBuilder = domainBuilder,
            .name = name,
            .conditions = std.ArrayList(ConditionFunction).init(allocator),
            .effects = std.ArrayList(EffectFunction).init(allocator),
            .onFailureFunctions = std.ArrayList(OnFailureFunction).init(allocator),
        };
        return this;
    }

    pub fn deinit(self: *This) void {
        self.conditions.deinit();
        self.effects.deinit();
        self.onFailureFunctions.deinit();
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

    pub fn onFailure(self: *This, _: []const u8, f: OnFailureFunction) *This {
        self.onFailureFunctions.append(f) catch unreachable;
        return self;
    }

    pub fn end(self: *This) *DomainBuilder {
        const conditionValues = self.conditions.items;
        const conditions = self.allocator.alloc(ConditionFunction, conditionValues.len) catch unreachable;
        @memcpy(conditions, conditionValues);

        const effectValues = self.effects.items;
        const effects = self.allocator.alloc(EffectFunction, effectValues.len) catch unreachable;
        @memcpy(effects, effectValues);

        const onFailureFunctions =
            self.allocator.alloc(OnFailureFunction, self.onFailureFunctions.items.len) catch unreachable;
        @memcpy(onFailureFunctions, self.onFailureFunctions.items);

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
                    .onFailureFunctions = onFailureFunctions,
                },
            },
        );

        self.deinit();
        return domainBuilder;
    }
};

pub fn isMethodConditionSatisfied(method: Method, worldState: []WorldStateValue) bool {
    return method.condition(worldState);
}

const expect = std.testing.expect;

fn alwaysReturnTrue(_: []const WorldStateValue) bool {
    return true;
}

fn alwaysReturnFalse(_: []const WorldStateValue) bool {
    return false;
}

fn worldStateTest(ws: []const WorldStateValue) bool {
    return ws[@intFromEnum(WorldStateKey.WsTest)] == .Test;
}

fn effectSwitchTestWorldState(ws: []WorldStateValue) void {
    ws[@intFromEnum(WorldStateKey.WsTest)] = .TestSwitched;
}

fn operatorNoOp(_: usize, _: []WorldStateValue, _: *gamestate.GameState) TaskStatus {
    return .Succeeded;
}

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
    const rootTask = domain.tasks.items[2];
    const planner = HtnPlanner.init(std.testing.allocator, rootTask);
    defer planner.deinit();

    var worldState = WorldState.init(std.testing.allocator);
    defer worldState.deinit();

    // The first method has two subtasks whose conditions are always met, meaning that the final plan should have both.
    // The ordering for the subtasks is preserved by the planner.
    var plan = planner
        .processTasks(&worldState)
        .getPlan();
    defer plan.deinit();

    try expect(plan.items.len == 2);
    try expect(plan.items[0].taskType == .PrimitiveTask);
    try expect(std.mem.eql(u8, plan.items[0].name, "another task name"));
    try expect(std.mem.eql(u8, plan.items[1].name, "task name"));
}

test "method condition on world state" {
    var task = Task{};
    const method = Method{
        .condition = worldStateTest,
        .subtasks = &[_]*Task{&task},
    };
    var worldState = WorldState.init(std.testing.allocator);
    defer worldState.deinit();

    worldState.set(.WsTest, .Test);
    try expect(isMethodConditionSatisfied(method, worldState.state));
}

test "primitive task preconditions" {
    var task = PrimitiveTask{
        .preconditions = &[_]ConditionFunction{ alwaysReturnTrue, alwaysReturnFalse },
    };
    const worldState = &[_]WorldStateValue{};

    task.conditionOperator = .Any;
    try expect(task.checkPreconditions(worldState));

    task.conditionOperator = .All;
    try expect(!task.checkPreconditions(worldState));
}

test "compound task findSatisfiedMethod" {
    const task = CompoundTask{
        .methods = &[_]Method{
            .{ .condition = alwaysReturnTrue },
            .{ .condition = alwaysReturnFalse },
            .{ .condition = worldStateTest },
        },
    };
    const worldState = &[_]WorldStateValue{.Test};
    const method = task.findSatisfiedMethod(worldState);
    try expect(method != null);
    try expect(method.?.condition == &alwaysReturnTrue);
}
