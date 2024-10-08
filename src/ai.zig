const std = @import("std");
const htn = @import("htn/htn.zig");
const gamestate = @import("gamestate.zig");
const components = @import("ecs/components.zig");

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Rect = math.Rect;
const Line = math.Line;

const input = @import("input.zig");
const nav = @import("nav.zig");
const settings = @import("settings.zig");
const Queue = @import("queue.zig").Queue;

// TODO: Only used for drawing debug stuff
const sdl = @import("sdl.zig");

pub fn isPointInLineOfSight(
    state: *gamestate.GameState,
    point: Vec2(f32),
    looker: Vec2(f32),
    direction: Vec2(f32),
    fov: f32,
) bool {
    // Check if within player FoV
    const lookerToPoint = point.sub(looker);
    const isWithinFov = math.angle(lookerToPoint, direction) <= fov;

    if (isWithinFov) {
        // Check LoS collision with walls
        const line = Line(f32){
            .a = looker,
            .b = point,
        };
        var it = state.ecs.entityManager.iterator();
        while (it.next()) |keyVal| {
            const entity = keyVal.key_ptr.*;
            if (state.ecs.hasComponent(entity, gamestate.Wall)) {
                const position = state.ecs.componentManager.getKnown(entity, components.Position);
                const rect: math.Rect(f32) = .{
                    .x = position.x,
                    .y = position.y,
                    .w = position.w,
                    .h = position.h,
                };
                if (line.intersectsRect(rect)) {
                    return false;
                }
            }
        }
    }
    return isWithinFov;
}

//**************************************************
// AI IMPLEMENTATIONS
//--------------------------------------------------
// Encapsulates state required for various AI
// implementations to operate. This includes
// a `WorldState`, a `Domain`, and a `HtnPlanner`.
//**************************************************
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
    playerVisibilityMap: ?std.AutoArrayHashMap(usize, bool) = null,

    // Search state
    targetCoverEntity: ?gamestate.EntityType = null,
    currentSearchCells: std.ArrayList(usize),
    searchedCoverEntities: std.AutoArrayHashMap(gamestate.EntityType, bool),

    // Misc. state
    timer: std.time.Timer,
    isFrozenInFear: bool = false,

    pub fn init(allocator: std.mem.Allocator) EnemyFlankerAI {
        // Define the HTN domain.
        // zig fmt: off
        var domain = htn.DomainBuilder.init(allocator)
            //**************************************************
            // primitive tasks
            //**************************************************
            .task("searchCover", .PrimitiveTask)
                .condition("unseen", cIsPlayerUnseen)
                .operator("searchCoverOperator", oSearchCover)
            .end()

            .task("findNextCoverPointToSearch", .PrimitiveTask)
                .condition("unseen", cIsPlayerUnseen)
                .operator("findNextCoverPointToSearchOperator", oFindNextCoverPointToSearch)
            .end()

            .task("navToSearchCover", .PrimitiveTask)
                .condition("unseen", cIsPlayerUnseen)
                .operator("navToOperator", oNavTo)
            .end()

            .task("navToLastPlayerLocation", .PrimitiveTask)
                .condition("unseen", cIsUnseenByPlayer)
                .effect("playerInRangeEffect", ePlayerInRange)
                .operator("navToOperator", oNavToLastKnownPlayerLocation)
            .end()

            .task("attackPlayer", .PrimitiveTask)
                .condition("isPlayerInRange", cIsPlayerInRange)
                .operator("attackPlayerOperator", oAttackPlayer)
            .end()

            .task("hide", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .effect("hide effect", eHide)
                .operator("hide operator", oHide)
            .end()

            .task("navToCover", .PrimitiveTask)
                .condition("alwaysTrue", cAlways)
                .operator("navToOperator", oNavTo)
            .end()

            .task("findNearestCover", .PrimitiveTask)
                .condition("always", cAlways)
                .operator("findNearestCoverOperator", oFindCover)
            .end()

            .task("freezeInFear", .PrimitiveTask)
                .condition("seen", cIsSeenByPlayer)
                .operator("freezeInFearOperator", oFreezeInFear)
            .end()

            //**************************************************
            // compound tasks
            //**************************************************
            .task("beEnemyFlanker", .CompoundTask)
                .method("attackPlayer")
                    .condition("player in range", cIsPlayerInRange)
                    .subtask("attackPlayer")
                .end()

                .method("hideFromPlayer")
                    .condition("seen", cIsSeenByPlayer)
                    .subtask("freezeInFear")
                    .subtask("findNearestCover")
                    .subtask("navToCover")
                    .subtask("hide")
                .end()

                .method("huntPlayer")
                    .condition("unseen and hunting", cIsHuntingOrPlayerSeen)
                    .subtask("navToLastPlayerLocation")
                .end()

                .method("patrol")
                    .condition("always", cIsPlayerUnseen)
                    .subtask("findNextCoverPointToSearch")
                    .subtask("navToSearchCover")
                    .subtask("searchCover")
                .end()
            .end()
            .build();
        // zig fmt: on

        // The planner only accepts a single root task from the `Domain` above.
        // To use multiple compound tasks, the root compound task must have a connected path to each other compound task.
        const rootTask = domain.getTaskByName("beEnemyFlanker").?;
        const planner = htn.HtnPlanner.init(allocator, rootTask);

        // Register sensors that will encode `GameState` into `WorldState` each tick.
        var worldState = htn.WorldState.init(allocator);
        worldState.registerSensor(sIsPlayerSeenByEntity);
        worldState.registerSensor(sIsEntitySeenByPlayer);
        worldState.registerSensor(sIsPlayerInRange);

        return EnemyFlankerAI{
            .allocator = allocator,
            .timer = std.time.Timer.start() catch unreachable,

            .domain = domain,
            .planner = planner,
            .worldState = worldState,

            .currentSearchCells = std.ArrayList(usize).init(allocator),
            .searchedCoverEntities = std.AutoArrayHashMap(gamestate.EntityType, bool).init(allocator),
        };
    }

    pub fn deinit(self: *EnemyFlankerAI) void {
        self.domain.deinit();
        self.planner.deinit();
        self.worldState.deinit();
        if (self.currentPlanQueue != null) self.currentPlanQueue.?.deinit();

        self.currentSearchCells.deinit();
        self.searchedCoverEntities.deinit();
        if (self.playerVisibilityMap != null) self.playerVisibilityMap.?.deinit();
    }

    /// Returns true if the AI needs to request a new plan from the `HtnPlanner`.
    pub fn needsPlan(self: *const EnemyFlankerAI) bool {
        return self.currentPlanQueue == null or self.currentPlanQueue.?.len == 0;
    }
};

//**************************************************
// Condition Functions
//--------------------------------------------------
// Predicates for HTN tasks and methods.
//**************************************************
pub fn cAlways(_: []const htn.WorldStateValue) bool {
    return true;
}

pub fn cIsUnseenByPlayer(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsEntitySeenByPlayer) == .False;
}

pub fn cIsSeenByPlayer(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsEntitySeenByPlayer) == .True;
}

pub fn cIsPlayerUnseen(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsPlayerSeenByEntity) == .False;
}

pub fn cIsPlayerSeen(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsPlayerSeenByEntity) == .True;
}

pub fn cIsHunting(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsHunting) == .True;
}

pub fn cIsSeenAndNotHunting(state: []const htn.WorldStateValue) bool {
    return cIsSeenByPlayer(state) and !cIsHunting(state);
}

pub fn cIsUnseenAndHunting(state: []const htn.WorldStateValue) bool {
    return cIsUnseenByPlayer(state) and cIsHunting(state);
}

pub fn cIsPlayerInRange(state: []const htn.WorldStateValue) bool {
    return htn.wsGet(state, .WsIsPlayerInRange) == .True;
}

pub fn cIsHuntingOrPlayerSeen(state: []const htn.WorldStateValue) bool {
    return cIsHunting(state) or cIsPlayerSeen(state);
}

//**************************************************
// EFFECT FUNCTIONS
//--------------------------------------------------
// Effects on the simulated `WorldState`.
// Used for planning purposes only.
//**************************************************
pub fn eNoOp(_: []htn.WorldStateValue) void {}

pub fn eHide(state: []htn.WorldStateValue) void {
    htn.wsSet(state, .WsIsEntitySeenByPlayer, .False);
    htn.wsSet(state, .WsIsHunting, .True);
}

pub fn ePlayerInRange(state: []htn.WorldStateValue) void {
    htn.wsSet(state, .WsIsPlayerInRange, .True);
}

//**************************************************
// OPERATOR FUNCTIONS
//--------------------------------------------------
// Effects on the actual `WorldState`.
// Often include `GameState` manipulations e.g. nav.
// These are called by the task runner and are not
// used during planning.
//**************************************************
/// Updates data structures that keep track of already searched cover so that we can avoid re-searching too much.
/// If all cover has been searched, will clear the memory so search can begin anew.
pub fn oSearchCover(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = worldState;

    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    if (ai.targetCoverEntity == null) return .Failed;
    if (ai.currentSearchCells.items.len > 0) return .Succeeded;
    ai.searchedCoverEntities.put(ai.targetCoverEntity.?, true) catch unreachable;
    ai.targetCoverEntity = null;
    ai.currentSearchCells.clearRetainingCapacity();
    return .Succeeded;
}

/// Distance-based priority queue using distance between point and rect as the metric. Uses minimal distance between point and polygon vertices.
const DPQRect = std.PriorityQueue(DPQRectPair, *const math.Vec2(f32), __lessThanRectDist);
const DPQRectPair = struct {
    entity: gamestate.EntityType,
    rect: math.Rect(f32),
};
fn __lessThanRectDist(context: *const math.Vec2(f32), a: DPQRectPair, b: DPQRectPair) std.math.Order {
    return std.math.order(context.sqDistRect(a.rect), context.sqDistRect(b.rect));
}

/// Computes cover points associated with nearby cover and adds them to the search queue.
/// Specifically, will not add new cover points until the current cover has finished being searched.
pub fn oFindNextCoverPointToSearch(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = worldState;

    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);

    // If we already have search points, take the next unblocked one.
    while (ai.currentSearchCells.items.len > 0) {
        const nextCellId = ai.currentSearchCells.pop();
        if (gameState.blockedCells.get(nextCellId) orelse false) continue;

        ai.targetNavLocation = gameState.navMeshGrid.getCellCenter(nextCellId).*;
        return .Succeeded;
    }

    // Otherwise, we need to compute new search points from nearby cover.
    // Do this by sorting cover by distance and randomly picking a nearby one.
    const position = gameState.ecs.componentManager.getKnown(entity, gamestate.Position);
    const entityPoint = math.Vec2(f32){ .x = position.x, .y = position.y };

    // TODO: Although wasteful for just getting the closest point, keeping the priority queue for now in anticipation of more advanced uses e.g. randomizing which cover to search e.g. building a search route.
    var queue = DPQRect.init(gameState.allocator, &entityPoint);
    defer queue.deinit();

    var it = gameState.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const wallEntity = keyVal.key_ptr.*;
        if (!gameState.ecs.hasComponent(wallEntity, gamestate.Wall)) continue;
        if (ai.searchedCoverEntities.get(wallEntity) orelse false) {
            continue;
        }

        const coverPosition = gameState.ecs.componentManager.getKnown(wallEntity, gamestate.Position);
        const rect = math.Rect(f32){ .x = coverPosition.x, .y = coverPosition.y, .w = coverPosition.w, .h = coverPosition.h };
        std.debug.print("[DEBUG] [oFindNextCoverPointToSearch] queue.add\n", .{});
        queue.add(.{ .entity = wallEntity, .rect = rect }) catch unreachable;
    }

    // Reset to begin patrol again if cover does exist.
    if (queue.count() == 0) {
        ai.targetCoverEntity = null;
        ai.searchedCoverEntities.clearRetainingCapacity();
        return .Failed;
    }
    const pair = queue.remove();

    // Set the new search target to this entity.
    ai.targetCoverEntity = pair.entity;

    // Update the cover points to search.
    const wallCoverRect = math.Rect(f32){
        .x = pair.rect.x - gameState.navMeshGrid.cellSize,
        .y = pair.rect.y - gameState.navMeshGrid.cellSize,
        .w = pair.rect.w + 2 * gameState.navMeshGrid.cellSize,
        .h = pair.rect.h + 2 * gameState.navMeshGrid.cellSize,
    };
    var wallCoverCellIds = std.ArrayList(usize).init(gameState.allocator);
    defer wallCoverCellIds.deinit();
    ai.currentSearchCells.clearRetainingCapacity();
    nav.getRectExteriorCellIds(&wallCoverRect, &gameState.navMeshGrid, &ai.currentSearchCells);

    // Reverse search order
    if (gameState.rng.random().boolean()) {
        reverse(usize, ai.currentSearchCells.items);
    }

    return .Succeeded;
}

/// Helper function to reverse an array in-place.
fn reverse(comptime T: type, arr: []T) void {
    if (arr.len < 2) return;
    var l: usize = 0;
    var r: usize = arr.len - 1;
    while (l < r) : ({
        l += 1;
        r -= 1;
    }) {
        const val = arr[l];
        arr[l] = arr[r];
        arr[r] = val;
    }
}

/// Locate cover point on nearest cover entity.
/// Tries to find an unblocked, non-visible point around the exterior of the polygon. These points are clamped to the navigation grid.
pub fn oFindCover(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = worldState;

    // Find the nearest wall
    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    const position = gameState.ecs.componentManager.get(entity, gamestate.Position) orelse {
        std.log.err("Could not get Position component for entity {d}", .{entity});
        @panic("Could not get Position component for entity");
    };
    const center = math.Vec2(f32){
        .x = position.x,
        .y = position.y,
    };
    const nearestWallEntity = findNearestWallEntity(&center, gameState) orelse {
        std.log.err("No cover found for entity {d}", .{entity});
        return .Failed;
    };
    const wallPosition =
        gameState.ecs.componentManager.getKnown(nearestWallEntity, gamestate.Position);
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
    const playerPosition = gameState.ecs.componentManager.get(player, gamestate.Position) orelse position;
    const playerPositionPoint = math.Vec2(f32){
        .x = playerPosition.x + playerPosition.w,
        .y = playerPosition.y + playerPosition.h,
    };

    // Find a *new* cover point furthest from the player.
    const entityCellId = gameState.navMeshGrid.getCellId(&center);
    var coverCellId: ?usize = null;
    var dist: f32 = 0;
    for (wallCoverCellIds.items) |cellId| {
        // Always try to find a new cover point.
        if (cellId == entityCellId) continue;

        const coverPoint = gameState.navMeshGrid.getCellCenter(cellId).*;
        const line = math.Line(f32){
            .a = playerPositionPoint,
            .b = coverPoint,
        };
        // Check LoS for only the selected wall by directly checking intersection between LoS vector and wall polygon.
        // This avoids iterating over every wall with a full LoS check.
        if (line.intersectsRect(wallRect)) {
            const p = gameState.navMeshGrid.getCellCenter(cellId);
            const coverDist = p.sqDist(playerPositionPoint);
            if (coverDist > dist) {
                dist = coverDist;
                coverCellId = cellId;
            }
        }
    }
    if (coverCellId == null) {
        std.log.err("No cover point found on cover {d} for entity {d}", .{ nearestWallEntity, entity });
        return .Failed;
    }

    // Update target location
    const coverCell = gameState.navMeshGrid.getCellCenter(coverCellId.?);
    ai.targetNavLocation = coverCell.*;

    return .Succeeded;
}

/// Returns nearest ECS entity that has a `Wall` component.
/// Used for finding cover.
fn findNearestWallEntity(point: *const math.Vec2(f32), state: *gamestate.GameState) ?gamestate.EntityType {
    var minDist = std.math.inf(f32);
    var nearestWall: ?gamestate.EntityType = null;

    var it = state.ecs.entityManager.iterator();
    while (it.next()) |keyVal| {
        const entity = keyVal.key_ptr.*;
        if (state.ecs.hasComponent(entity, gamestate.Wall)) {
            const wallPosition = state.ecs.componentManager.getKnown(entity, gamestate.Position);
            const dist = point.sqDist(.{ .x = wallPosition.x, .y = wallPosition.y });
            if (dist < minDist) {
                minDist = dist;
                nearestWall = entity;
            }
        }
    }
    return nearestWall;
}

/// Distance-based priority queue with bias towards paths that aren't visible.
const DPQVisibility = std.PriorityQueue(nav.PathPoint, *const DPQVisibilityContext, __lessThanVisibility);
/// Context for `DPQVisibility`. Contains a visibility map of cells that should be considered visible during pathfinding.
/// The cell ids are those generated by `nav.NavMeshGrid`.
const DPQVisibilityContext = struct {
    visibleCells: *const std.AutoArrayHashMap(usize, bool),
    targetPoint: *const math.Vec2(f32),
};
/// Ordering function for `DPQVisibility`.
fn __lessThanVisibility(context: *const DPQVisibilityContext, a: nav.PathPoint, b: nav.PathPoint) std.math.Order {
    var adist = context.targetPoint.sqDist(a.point);
    var bdist = context.targetPoint.sqDist(b.point);
    const aVisible = context.visibleCells.get(a.id) orelse false;
    const bVisible = context.visibleCells.get(b.id) orelse false;

    // Make visible navpoints further away
    if (aVisible) adist *= 10;
    if (bVisible) bdist *= 10;

    return std.math.order(adist, bdist);
}

/// Generic navigation operator that will attempt to navigate the entity towards its `targetNavLocation` field of its ai component.
pub fn oNavTo(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = worldState;

    const ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    const targetNavLoc = ai.targetNavLocation orelse {
        std.log.err("No targetNavLocation for entity {d}", .{entity});
        return .Failed;
    };

    const position = gameState.ecs.componentManager.getKnown(entity, gamestate.Position);
    const initCellId = gameState.navMeshGrid.getCellId(&.{ .x = position.x, .y = position.y });
    const targetCellId = gameState.navMeshGrid.getCellId(&targetNavLoc);

    if (initCellId == targetCellId) return .Succeeded;

    var path = std.ArrayList(usize).init(gameState.allocator);
    defer path.deinit();

    if (ai.playerVisibilityMap == null) {
        // Without a player visibility map estimate, best we can do is shortest-path A*.
        var pathfinder = nav.Pathfinder(
            nav.DistancePriorityQueue,
            math.Vec2(f32),
        ).init(gameState.allocator, gameState.navMeshGrid.getCellCenter(targetCellId).*);
        defer pathfinder.deinit();
        pathfinder.pathfind(initCellId, targetCellId, &gameState.navMeshGrid, &gameState.blockedCells, &path);
    } else {
        // Otherwise, we can bias A* towards paths that stay out of player visibility.
        // Note that the visibility map can easily become stale if the player moves. This is a good thing because it allows
        // the AI to not "cheat".
        var pathfinder = nav.Pathfinder(DPQVisibility, *const DPQVisibilityContext).init(
            gameState.allocator,
            &DPQVisibilityContext{
                .visibleCells = &(ai.playerVisibilityMap.?),
                .targetPoint = gameState.navMeshGrid.getCellCenter(targetCellId),
            },
        );
        defer pathfinder.deinit();
        pathfinder.pathfind(initCellId, targetCellId, &gameState.navMeshGrid, &gameState.blockedCells, &path);
    }
    nav.moveAlongPath(position, settings.ENEMY_SPEED, path.items, &gameState.navMeshGrid);

    // TODO: Only used for debugging
    // Draw the A* route
    _ = sdl.SDL_SetRenderDrawColor(gameState.renderer, 255, 0, 0, 255);
    for (path.items) |cellId| {
        const center = gameState.navMeshGrid.getCellCenter(cellId);
        const x = @as(i32, @intFromFloat(gamestate.unnormalizeWidth(center.x)));
        const y = @as(i32, @intFromFloat(gamestate.unnormalizeHeight(center.y)));
        _ = sdl.SDL_RenderDrawPoint(gameState.renderer, x, y);
    }

    return .Running;
}

/// Attempts to navigate to the last known player location, if it exists.
/// Can fail if the AI has never spotted the player and thus never logged a location.
/// Navigation will be biased away from player visibility.
pub fn oNavToLastKnownPlayerLocation(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    if (ai.lastSeenPlayerLocation == null) return .Failed;
    ai.targetNavLocation = ai.lastSeenPlayerLocation;

    return oNavTo(entity, worldState, gameState);
}

/// Checks to make sure that we've succeeded in getting out of LoS.
/// Switches AI into hunting mode if successfully hidden.
pub fn oHide(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = entity;
    _ = gameState;

    const seenState = htn.wsGet(worldState, .WsIsEntitySeenByPlayer);
    switch (seenState) {
        .True => return .Failed,
        .False => {
            htn.wsSet(worldState, .WsIsHunting, .True);
            return .Succeeded;
        },

        else => {
            std.log.err("Invalid world state for key WsIsSeen: {any}", .{seenState});
            @panic("Invalid world state for key WsIsSeen");
        },
    }
}

pub fn oAttackPlayer(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = worldState;

    var player = gameState.ecs.componentManager.get(gameState.entities.player, gamestate.Player) orelse {
        std.log.err("[AI::oAttackPlayer] e:{d} could not get component Player for entity player", .{entity});
        return .Failed;
    };

    player.isAlive = false;
    gameState.ecs.removeEntity(gameState.entities.player);
    return .Succeeded;
}

/// With some randomization, causes the AI to freeze for a short time.
pub fn oFreezeInFear(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) htn.TaskStatus {
    _ = worldState;

    var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
    if (!ai.isFrozenInFear) {
        // Randomly decide whether or not to freeze when spotted and not currently waiting to unfreeze.
        ai.isFrozenInFear = gameState.rng.random().boolean();
        if (!ai.isFrozenInFear) return .Succeeded;

        ai.timer.reset();
        return .Running;
    }

    // Randomly perturb the time that the AI should freeze for to make it more unpredictable.
    const timeElapsed = ai.timer.read();
    if (timeElapsed >= settings.ENEMY_FREEZE_TIME + gameState.rng.random().uintAtMost(usize, settings.ENEMY_FREEZE_TIME_RNG_BOUND)) {
        ai.isFrozenInFear = false;
        return .Succeeded;
    }

    return .Running;
}

//**************************************************
// SENSOR FUNCTIONS
//--------------------------------------------------
// Encode `GameState` into `WorldState`.
// Will also typically modify AI state e.g. marking
// the last known location of a seen player.
//**************************************************
/// HTN sensor to determine if entity is seen by the player.
/// This information is used in general HTN planning.
pub fn sIsEntitySeenByPlayer(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) void {
    const enemyPosition =
        gameState.ecs.componentManager.get(entity, gamestate.Position) orelse return;
    const playerPosition =
        gameState.ecs.componentManager.get(gameState.entities.player, gamestate.Position) orelse {
        std.log.err("[AI] e:{d} could not get component Position for entity player", .{entity});
        return;
    };

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

    const playerToMouse = gamestate.getMousePos(gameState).sub(line.a);
    const isSeen = isPointInLineOfSight(gameState, line.b, line.a, playerToMouse, settings.PLAYER_FOV);
    htn.wsSet(worldState, .WsIsEntitySeenByPlayer, if (isSeen) .True else .False);
}

/// HTN sensor that monitors whether the entity has spotted the player.
/// If so, the last known player position and player visibility map are saved. This information is used during navigation, specifically in task operators for navigating.
pub fn sIsPlayerSeenByEntity(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) void {
    const enemyPosition =
        gameState.ecs.componentManager.get(entity, gamestate.Position) orelse return;
    const playerPosition =
        gameState.ecs.componentManager.get(gameState.entities.player, gamestate.Position) orelse {
        std.log.err("[AI] e:{d} Could not get Position component for player entity", .{entity});
        return;
    };

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
    const entityToPlayer = line.a.sub(line.b);

    // Check with full FOV
    const isSeen = isPointInLineOfSight(gameState, line.a, line.b, entityToPlayer, 180);
    if (isSeen) {
        htn.wsSet(worldState, .WsIsPlayerSeenByEntity, .True);

        // Update last known player location
        var ai = gameState.ecs.componentManager.getKnown(entity, EnemyFlankerAI);
        ai.lastSeenPlayerLocation = line.a;

        // Update player visibility map
        if (ai.playerVisibilityMap != null) ai.playerVisibilityMap.?.deinit();
        ai.playerVisibilityMap = gameState.visibleCells.clone() catch unreachable;
    } else {
        htn.wsSet(worldState, .WsIsPlayerSeenByEntity, .False);
    }
}

/// HTN sensor that monitors whether the player is in range.
/// This information is used for planning attacks.
pub fn sIsPlayerInRange(
    entity: gamestate.EntityType,
    worldState: []htn.WorldStateValue,
    gameState: *gamestate.GameState,
) void {
    const enemyPosition =
        gameState.ecs.componentManager.get(entity, gamestate.Position) orelse return;
    const playerPosition =
        gameState.ecs.componentManager.get(gameState.entities.player, gamestate.Position) orelse {
        std.log.err("[AI] e:{d} Could not get Position component for player entity", .{entity});
        return;
    };

    const e = math.Vec2(f32){ .x = enemyPosition.x, .y = enemyPosition.y };
    const p = math.Vec2(f32){ .x = playerPosition.x, .y = playerPosition.y };
    const d = e.sub(p).norm();

    if (d < settings.ENEMY_ATTACK_RANGE) {
        htn.wsSet(worldState, .WsIsPlayerInRange, .True);
    } else {
        htn.wsSet(worldState, .WsIsPlayerInRange, .False);
    }
}
