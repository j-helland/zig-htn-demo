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
const math = @import("math.zig");
const input = @import("input.zig");
const nav = @import("nav.zig");
const settings = @import("settings.zig");
const Queue = @import("queue.zig").Queue;

pub fn cAlways(_: []const htn.WorldStateValue) bool {
    return true;
}

pub fn cIsUnseen(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsSeen) == .False;
}

pub fn cIsSeen(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsSeen) == .True;
}

pub fn cIsHunting(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsHunting) == .True;
}

pub fn cIsSeenAndNotHunting(state: []const htn.WorldStateValue) bool {
    return cIsSeen(state) and !cIsHunting(state);
}

pub fn cIsUnseenAndHunting(state: []const htn.WorldStateValue) bool {
    return cIsUnseen(state) and cIsHunting(state);
}

pub fn eNoOp(_: []htn.WorldStateValue) void {}

pub fn eHide(state: []htn.WorldStateValue) void {
    htn.wsSet(state, .WsIsSeen, .False);
    htn.wsSet(state, .WsIsHunting, .True);
}

pub fn oSearchCover(
    entity: game.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *game.GameState,
) htn.TaskStatus {
    _ = entity;
    _ = worldState;
    _ = gameState;
    std.log.info("Searching cover", .{});
    return .Running;
}

/// Locate cover point on nearest cover entity
pub fn oFindCover(
    entity: game.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *game.GameState,
) htn.TaskStatus {
    _ = worldState;

    // Find the nearest wall
    const position = gameState.ecs.componentManager.get(entity, game.Position) orelse {
        std.log.err("Could not get Position component for entity {d}", .{entity});
        @panic("Could not get Position component for entity");
    };
    const center = math.Vec2(f32){
        .x = position.x,
        .y = position.y,
    };
    const nearestWallEntity = game.findNearestWallEntity(&center, gameState) orelse {
        std.log.err("No cover found for entity {d}", .{entity});
        return .Failed;
    };
    const wallPosition =
        gameState.ecs.componentManager.getKnown(nearestWallEntity, game.Position);
    const wallRect = math.Rect(f32){
        .x = wallPosition.x,
        .y = wallPosition.y,
        .w = wallPosition.w,
        .h = wallPosition.h,
    };

    // Find cover on selected wall
    const wallCoverRect = math.Rect(f32){
        .x = wallPosition.x - gameState.navMeshGrid.cellSize,
        .y = wallPosition.y - gameState.navMeshGrid.cellSize,
        .w = wallPosition.w + 2 * gameState.navMeshGrid.cellSize,
        .h = wallPosition.h + 2 * gameState.navMeshGrid.cellSize,
    };
    var wallCoverCellIds = std.ArrayList(usize).init(gameState.allocator);
    defer wallCoverCellIds.deinit();
    nav.getRectExteriorCellIds(&wallCoverRect, &gameState.navMeshGrid, &wallCoverCellIds);

    // Get the furthest cover point from the player.
    const player = gameState.entities.player;
    const playerPosition = gameState.ecs.componentManager.getKnown(player, game.Position);
    const playerPositionPoint = math.Vec2(f32){
        .x = playerPosition.x + playerPosition.scale * playerPosition.w,
        .y = playerPosition.y + playerPosition.scale * playerPosition.h,
    };

    var coverCellId: ?usize = null;
    var dist: f32 = 0;
    for (wallCoverCellIds.items) |cellId| {
        const coverPoint = gameState.navMeshGrid.getCellCenter(cellId).*;
        const line = math.Line(f32){
            .a = playerPositionPoint,
            .b = coverPoint,
        };
        // Check LoS for only the selected wall by directly checking intersection between LoS vector and wall polygon.
        // This avoids iterating over every wall with a full LoS check.
        if (game.isCollidingLineXRect(&line, &wallRect)) {
            const p = gameState.navMeshGrid.getCellCenter(cellId);
            var coverDist = p.sqDist(playerPositionPoint);
            if (coverDist > dist) {
                dist = coverDist;
                coverCellId = cellId;
            }
        }
    }
    if (coverCellId == null){
        std.log.err(
            "No cover point found on cover {d} for entity {d}",
            .{nearestWallEntity, entity});
        return .Failed;
    }

    // Update target location
    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    const coverCell = gameState.navMeshGrid.getCellCenter(coverCellId.?);
    ai.targetNavLocation = coverCell.*;

    return .Succeeded;
}

pub fn oNavTo(
    entity: game.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *game.GameState,
) htn.TaskStatus {
    _ = worldState;

    const ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    const targetNavLoc = ai.targetNavLocation orelse {
        std.log.err("No targetNavLocation for entity {d}", .{entity});
        return .Failed;
    };

    var position = gameState.ecs.componentManager.getKnown(entity, game.Position);
    const initCellId = gameState.navMeshGrid.getCellId(&.{ .x = position.x, .y = position.y });
    const targetCellId = gameState.navMeshGrid.getCellId(&targetNavLoc);

    if (initCellId == targetCellId) return .Succeeded;

    var path = std.ArrayList(usize).init(gameState.allocator);
    defer path.deinit();

    nav.pathfind(initCellId, targetCellId, &gameState.navMeshGrid, &gameState.blockedCells, &path);
    game.moveAlongPath(position, path.items, &gameState.navMeshGrid);

    return .Running;
}

pub fn oNavToLastKnownPlayerLocation(
    entity: game.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *game.GameState,
) htn.TaskStatus {
    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    if (ai.lastSeenPlayerLocation == null) return .Failed;
    ai.targetNavLocation = ai.lastSeenPlayerLocation;

    return oNavTo(entity, worldState, gameState);
}

pub fn oHide(
    entity: game.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *game.GameState,
) htn.TaskStatus {
    _ = entity;
    _ = gameState;

    htn.wsSet(worldState, .WsIsHunting, .True);
    const seenState = htn.wsGet(worldState, .WsIsSeen);
    switch (seenState) {
        .True => return .Running,
        .False => return .Succeeded,

        else => {
            std.log.err("Invalid world state for key WsIsSeen: {any}", .{seenState});
            @panic("Invalid world state for key WsIsSeen");
        }
    }
}

// pub fn oFindLastKnownPlayerLocation(
//     entity: game.EntityType,
//     worldState: []htn.WorldStateValue,
//     gameState: *game.GameState,
// ) htn.TaskStatus{
//     _ = worldState;

//     var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
//     if (ai.lastSeenPlayerLocation == null) return .Failed;
//     ai.targetNavLocation = ai.lastSeenPlayerLocation;
//     return .Succeeded;
// }

pub const EnemyFlankerAI = struct {
    allocator: std.mem.Allocator,

    // HTN state
    domain: htn.Domain,
    planner: htn.HtnPlanner,
    worldState: htn.WorldState,
    currentPlanQueue: ?Queue(*htn.Task) = null,

    // Nav state
    targetNavLocation: ?math.Vec2(f32) = null,
    lastSeenPlayerLocation: ?math.Vec2(f32) = null,

    pub fn init(allocator: std.mem.Allocator) EnemyFlankerAI {
        var domain = htn.DomainBuilder.init(allocator)
            .task("searchCover", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .effect("noop", eNoOp)
                .operator("searchCoverOperator", oSearchCover)
            .end()

            .task("findNextCover", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .effect("noop", eNoOp)
                .operator("findNextCoverOperator", oFindCover)
            .end()

            // .task("findLastKnownPlayerLocation", .PrimitiveTask)
            //     .condition("isHunting", cIsHunting)
            //     .effect("noop", eNoOp)
            //     .operator("findLastKnownPlayerLocation", oFindLastKnownPlayerLocation)
            // .end()

            .task("navToLastPlayerLocation", .PrimitiveTask)
                .condition("isHunting", cIsHunting)
                .effect("noop", eNoOp)
                .operator("navToOperator", oNavToLastKnownPlayerLocation)
            .end()

            .task("hide", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .effect("hide effect", eHide)
                .operator("hide operator", oHide)
            .end()

            .task("navToCover", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .effect("noop", eNoOp)
                .operator("navToOperator", oNavTo)
            .end()

            .task("findNearestCover", .PrimitiveTask)
                .condition("seen", cIsSeen)
                .operator("findNearestCoverOperator", oFindCover)
            .end()

            .task("beEnemyFlanker", .CompoundTask)
                .method("hideFromPlayer")
                    .condition("seen and not hunting", cIsSeenAndNotHunting)
                    .subtask("findNearestCover")
                    .subtask("navToCover")
                    .subtask("hide")
                .end()
                .method("huntPlayer")
                    .condition("unseen and hunting", cIsUnseenAndHunting)
                    // .subtask("findLastKnownPlayerLocation")
                    .subtask("navToLastPlayerLocation")
                .end()
                .method("default")
                    .condition("alwaysTrue", cAlways)
                    .subtask("findNextCover")
                    .subtask("navToCover")
                    .subtask("searchCover")
                .end()
            .end()
            .build();

        var rootTask = domain.getTaskByName("beEnemyFlanker").?;
        var planner = htn.HtnPlanner.init(allocator, rootTask);

        var worldState = htn.WorldState.init(allocator);
        worldState.registerSensor(sIsSeen);

        return EnemyFlankerAI{
            .allocator = allocator,
            .domain = domain,
            .planner = planner,
            .worldState = worldState,
        };
    }

    pub fn deinit(self: *EnemyFlankerAI) void {
        self.domain.deinit();
        self.planner.deinit();
        self.worldState.deinit();
        if (self.currentPlanQueue != null) self.currentPlanQueue.?.deinit();
    }

    pub fn needsPlan(self: *const EnemyFlankerAI) bool {
        return self.currentPlanQueue == null or self.currentPlanQueue.?.len == 0;
    }
};

// pub fn sLocation(
//     entity: usize,
//     worldState: []htn.WorldStateValue,
//     gameState: *const game.GameState,
// ) void {
//     _ = worldState;
//     _ = gameState;

//     // TODO: anything needed here?
//     std.log.info("Sensing location for entity {d}", .{entity});
//     // if (!gameState.ecs.hasComponent(entity, game.Position)) {
//     //     return;
//     // }
//     // const position = gameState.ecs.componentManager.getKnown(entity, game.Position);
// }

/// HTN sensor to determine if entity is seen by the player.
pub fn sIsSeen(
    entity: game.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *game.GameState,
) void {
    const enemyPosition =
        gameState.ecs.componentManager.get(entity, game.Position) orelse return;
    const playerPosition =
        gameState.ecs.componentManager.getKnown(gameState.entities.player, game.Position);

    const line: math.Line(f32) = .{
        .a = .{
            .x = playerPosition.x,
            .y = playerPosition.y,
        },
        .b = .{
            .x = enemyPosition.x,
            .y = enemyPosition.y,
        },
    };

    const playerToMouse = input.getMousePos().sub(line.a);
    const isSeen =
        game.isPointInLineOfSight(gameState, line.b, line.a, playerToMouse, settings.PLAYER_FOV);
    if (isSeen) {
        htn.wsSet(worldState, .WsIsSeen, .True);

        // Update last known player location
        var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
        ai.lastSeenPlayerLocation = line.a;

    } else {
        htn.wsSet(worldState, .WsIsSeen, .False);
    }
}
