// compound [BeEnemyFlanker]
//   method [WsIsSeen == true and WsIsHunting == false]
//     subtasks [findNearestCover, navToCover, hide]
//   method [WsIsSeen == false and WsIsHunting == true]
//     subtasks [navToLastPlayerLocation]
//   method [true]
//     subtasks [findNextCover, navToCover, searchCover]
//
// primitive [findNearestCover]
//   operator [findNearestCoverOperator]
//
// primitive [navToCover]
//   operator [navToOperator(SelectedCoverLocRef)]
//   effects [WsLocation = SelectedCoverLocRef]
//
// primitive [hide]
//   operator [hideOperator(HideDuration)]
//   effects [WsIsSeen = false, WsIsHunting = true]
//
// primitive [navToLastPlayerLocation]
//   operator [navToOperator(LastPlayerLocRef)]
//   effects [WsLocation = LastPlayerLocRef, WsIsHunting = false]
//
// primitive [findNextCover]
//   operator [findNextCoverOperator]
//
// primitive [searchCover]
//   operator [searchCoverOperator]
const std = @import("std");
const game = @import("game");
const htn = @import("htn/htn.zig");

pub fn cAlways(_: []const htn.WorldStateValue) bool { return true; }

pub fn eNoOp(_: []const htn.WorldStateValue) void {}

pub fn searchCoverOperator(state: *game.GameState) void {
    _ = state;
    std.log.info("Searching cover", .{});
}

pub const EnemyFlankerAI = struct {
    allocator: std.mem.Allocator,
    domain: htn.Domain,
    planner: htn.HtnPlanner,

    pub fn init(allocator: std.mem.Allocator) EnemyFlankerAI {
        var domain = htn.DomainBuilder.init(allocator)
            .task("searchCover", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .effect("noop", eNoOp)
                .operator("searchCoverOperator", searchCoverOperator)
            .end()

            .build();

        var rootTask = domain.tasks.items[0];
        var planner = htn.HtnPlanner.init(allocator, rootTask);

        return EnemyFlankerAI{
            .allocator = allocator,
            .domain = domain,
            .planner = planner,
        };
    }

    pub fn deinit(self: *EnemyFlankerAI) void {
        self.domain.deinit();
        self.planner.deinit();
    }
};
