const std = @import("std");

const htn = @import("htn.zig");
const WorldState = htn.WorldState;
const WorldStateKey = htn.WorldStateKey;
const WorldStateValue = htn.WorldStateValue;
const Task = htn.Task;

pub const HtnPlannerState = struct {
    plan: std.ArrayList(*Task),
    tasksToProcess: std.ArrayList(*Task),
    worldState: []WorldStateValue,
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
                    if (primitiveTask.checkPreconditions(workingWorldState)) {
                        htn.applyEffects(primitiveTask, workingWorldState);
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
    pub fn recordDecompositionOfTask(self: *HtnPlanner, currentTask: *Task, tasksToProcess: *std.ArrayList(*Task), ws: []const WorldStateValue) void {
        var tasksToProcessClone = tasksToProcess.clone() catch unreachable;
        tasksToProcessClone.append(currentTask) catch unreachable;

        self.decompHistory.append(HtnPlannerState{
            .plan = self.finalPlan.clone() catch unreachable,
            .tasksToProcess = tasksToProcessClone,
            .worldState = self.copyWorldState(ws),
        }) catch unreachable;
    }

    /// Intended for internal use only.
    pub fn restoreToLastDecomposedTask(self: *HtnPlanner, tasksToProcess: *std.ArrayList(*Task), ws: []WorldStateValue) void {
        const state = self.decompHistory.popOrNull() orelse {
            std.log.warn("[HTN] Tried to pop empty decompHistory stack", .{});
            return;
        };

        self.finalPlan.clearRetainingCapacity();
        self.finalPlan.appendSlice(state.plan.items) catch unreachable;
        state.plan.deinit();

        std.mem.copy(WorldStateValue, ws, state.worldState);
        self.allocator.free(state.worldState);

        tasksToProcess.clearRetainingCapacity();
        tasksToProcess.appendSlice(state.tasksToProcess.items) catch unreachable;
        state.tasksToProcess.deinit();
    }

    /// Intended for internal use only.
    pub fn copyWorldState(self: *HtnPlanner, ws: []const WorldStateValue) []WorldStateValue {
        var copy = self.allocator.alloc(WorldStateValue, ws.len) catch unreachable;
        std.mem.copy(WorldStateValue, copy, ws);
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


const expect = std.testing.expect;

test "htn planner state restoration" {
    const rootTask = Task{};
    var planner = HtnPlanner.init(std.testing.allocator, rootTask);
    defer planner.deinit();

    planner.worldState.state[@enumToInt(WorldStateKey.WsTest)] = .Test;

    var task = Task{};
    var tasksToProcess = std.ArrayList(*Task).init(std.testing.allocator);
    defer tasksToProcess.deinit();

    planner.recordDecompositionOfTask(&task, &tasksToProcess, planner.worldState.state);
    try expect(planner.decompHistory.items.len == 1);
    try expect(tasksToProcess.items.len == 0);

    planner.worldState.state[@enumToInt(WorldStateKey.WsTest)] = .TestSwitched;

    planner.restoreToLastDecomposedTask(&tasksToProcess, planner.worldState.state);
    try expect(planner.decompHistory.items.len == 0);
    try expect(planner.worldState.state[@enumToInt(WorldStateKey.WsTest)] == .Test);
    try expect(tasksToProcess.items.len == 1);
}
