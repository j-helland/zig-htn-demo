const std = @import("std");

//const components = @import("ecs/ecs.zig");
const Position = @import("ecs/components.zig").Position;

// const game = @import("game.zig");
// const sdl = @import("sdl.zig");
const math = @import("math.zig");
const Rect = math.Rect;
const Vec2 = math.Vec2;
const Line = math.Line;

/// Partitions a 2D space into a lattice. The lattice cells can be used for navigation and planning purposes -- see `Pathfinder`.
pub const NavMeshGrid = struct {
    pub const directions: [8][2]i32 = [8][2]i32{ .{ -1, 0 }, .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ -1, 1 } };

    allocator: std.mem.Allocator,
    numCols: usize,
    numRows: usize,
    grid: []Vec2(f32),
    cellSize: f32,
    neighbors: [][8]?usize,
    // renderPoints: []sdl.SDL_Point,

    pub fn init(allocator: std.mem.Allocator, region: Rect(f32), cellSize: f32) NavMeshGrid {
        const cols: usize = @as(usize, @intFromFloat((region.x + region.w) / cellSize));
        const rows: usize = @as(usize, @intFromFloat((region.y + region.h) / cellSize));
        var grid: []Vec2(f32) = allocator.alloc(Vec2(f32), rows * cols) catch undefined;
        var neighbors: [][8]?usize = allocator.alloc([8]?usize, rows * cols) catch undefined;
        // var renderPoints: []sdl.SDL_Point = allocator.alloc(sdl.SDL_Point, rows * cols) catch undefined;

        // Generate grid cell values.
        var i: i32 = 0;
        var y: f32 = cellSize / 2;
        while (i < rows) : ({
            i += 1;
            y += cellSize;
        }) {
            var j: i32 = 0;
            var x: f32 = cellSize / 2;
            while (j < cols) : ({
                j += 1;
                x += cellSize;
            }) {
                const idx = @as(usize, @intCast(j)) + @as(usize, @intCast(i)) * cols;
                grid[idx] = .{ .x = x, .y = y };
                // renderPoints[idx] = sdl.SDL_Point{
                //     .x = @floatToInt(i32, game.unnormalizeWidth(x)),
                //     .y = @floatToInt(i32, game.unnormalizeHeight(y)),
                // };
            }
        }

        // Fill in neighbors -- adjacent cells.
        i = 0;
        while (i < rows) : (i += 1) {
            var j: i32 = 0;
            while (j < cols) : (j += 1) {
                inline for (NavMeshGrid.directions, 0..) |d, idx| {
                    const dj = j + d[0];
                    const di = i + d[1];
                    const gridIdx = @as(usize, @intCast(j)) + @as(usize, @intCast(i)) * cols;
                    if (0 <= dj and dj < cols and 0 <= di and di < rows) {
                        const neighborIdx = @as(usize, @intCast(dj)) + @as(usize, @intCast(di)) * cols;
                        neighbors[gridIdx][idx] = __getCellId(&grid[neighborIdx], cellSize, rows, cols);
                    } else {
                        neighbors[gridIdx][idx] = null;
                    }
                }
            }
        }

        return .{
            .allocator = allocator,
            .numCols = cols,
            .numRows = rows,
            .grid = grid,
            .neighbors = neighbors,
            .cellSize = cellSize,
            // .renderPoints = renderPoints,
        };
    }

    pub fn deinit(self: *NavMeshGrid) void {
        self.allocator.free(self.grid);
        self.allocator.free(self.neighbors);
        // self.allocator.free(self.renderPoints);
    }

    pub fn getCellId(self: *const NavMeshGrid, p: *const Vec2(f32)) usize {
        return __getCellId(p, self.cellSize, self.numRows, self.numCols);
    }

    pub fn getCellCenter(self: *const NavMeshGrid, cellId: usize) *const Vec2(f32) {
        return &self.grid[cellId];
    }

    pub fn getAdjacentCellIds(self: *const NavMeshGrid, cellId: usize) [8]?usize {
        return self.neighbors[cellId];
    }
};

/// Helper function that clamps points into the grid bounds before computing the cell in which the point resides.
fn __getCellId(p: *const Vec2(f32), cellSize: f32, rows: usize, cols: usize) usize {
    // Clamp point to grid bounds
    const px = math.clamp(p.x, 0.0, 1.0);
    const py = math.clamp(p.y, 0.0, 1.0);
    const x = math.clamp(@as(usize, @intFromFloat(px / cellSize)), 0, cols - 1);
    const y = math.clamp(@as(usize, @intFromFloat(py / cellSize)), 0, rows - 1);
    return x + y * cols;
}

/// Performs A* using the passed priority queue type and context type. Uses a `NavMeshGrid` to compute routes.
/// NOTE: The priority queue type implicitly defines the ranking heuristic in its definition, while the context provides additional information needed to compute the ranking heuristic. For example, a context might include the target point so that euclidean distance can be computed with respect to it.
pub fn Pathfinder(comptime DistancePriorityQueueType: type, comptime Context: type) type {
    return struct {
        const This = @This();

        queue: DistancePriorityQueueType,

        pub fn init(allocator: std.mem.Allocator, context: Context) This {
            return This{
                .queue = DistancePriorityQueueType.init(allocator, context),
            };
        }

        pub fn deinit(self: *This) void {
            self.queue.deinit();
        }

        pub fn pathfind(
            self: *This,
            initId: usize,
            targetId: usize,
            grid: *const NavMeshGrid,
            blockedIds: ?*const std.AutoArrayHashMap(usize, bool),
            path: *std.ArrayList(usize),
        ) void {
            var seen = grid.allocator.alloc(bool, grid.grid.len) catch unreachable;
            defer grid.allocator.free(seen);
            for (seen, 0..) |_, i| {
                seen[i] = false;
            }
            seen[initId] = true;

            var action = grid.allocator.alloc(usize, grid.grid.len) catch unreachable;
            defer grid.allocator.free(action);
            for (action, 0..) |_, i| {
                action[i] = 0;
            }

            var stack = std.ArrayList(usize).init(grid.allocator);
            defer stack.deinit();

            var found = false;
            var pair: PathPoint = undefined;
            var id: usize = undefined;

            if (self.queue.count() > 0) @panic("Queue should be empty when calling `pathfind`");
            std.debug.print("[DEBUG] [pathfind] queue.add\n", .{});
            self.queue.add(.{ .id = initId, .point = grid.getCellCenter(initId).* }) catch unreachable;

            while (self.queue.count() > 0) {
                pair = self.queue.remove();
                id = pair.id;

                if (id == targetId) {
                    found = true;
                    break;
                }

                for (grid.getAdjacentCellIds(id), 0..) |neighbor, i| {
                    if (neighbor == null or seen[neighbor.?] or (blockedIds != null and blockedIds.?.get(neighbor.?) orelse false)) continue;
                    seen[neighbor.?] = true;
                    action[neighbor.?] = i;
                    self.queue.add(.{ .id = neighbor.?, .point = grid.getCellCenter(neighbor.?).* }) catch unreachable;
                }
            }

            // Empty path.
            if (!found) return;

            // Reconstruct the path by reversing the actions we took.
            // Re-use stack here as the inverse path.
            stack.append(id) catch undefined;
            while (id != initId) {
                const d = NavMeshGrid.directions[action[id]];
                const center = grid.getCellCenter(id);
                id = grid.getCellId(&math.Vec2(f32){
                    .x = center.x - grid.cellSize * @as(f32, @floatFromInt(d[0])),
                    .y = center.y - grid.cellSize * @as(f32, @floatFromInt(d[1])),
                });
                stack.append(id) catch undefined;
            }

            // Get the final path cellInit --> cellTarget by reversing the stack.
            // Toss the first element to avoid including current location in the path.
            _ = stack.popOrNull();
            while (stack.items.len > 0) {
                path.append(stack.pop()) catch undefined;
            }
        }
    };
}

/// Distance-based priority queue. Uses squared euclidean distance between points for ordering.
pub const DistancePriorityQueue = std.PriorityQueue(PathPoint, Vec2(f32), __lessThan);
pub const PathPoint = struct {
    id: usize,
    point: Vec2(f32),
};
fn __lessThan(context: Vec2(f32), a: PathPoint, b: PathPoint) std.math.Order {
    return std.math.order(context.sqDist(a.point), context.sqDist(b.point));
}

/// Moves a `Position` component along a path from `Pathfinder`.
pub fn moveAlongPath(position: *Position, speed: f32, path: []usize, grid: *const NavMeshGrid) void {
    if (path.len == 0) return;
    if (grid.getCellId(&.{ .x = position.x, .y = position.y }) == path[0]) return;

    var gridAvg: Vec2(f32) = .{ .x = 0, .y = 0 };
    var i: usize = 0;
    const numPathSamples = 1;
    while (i < numPathSamples and i < path.len) : (i += 1) {
        gridAvg = gridAvg.add(grid.getCellCenter(path[i]).*);
    }
    gridAvg = gridAvg.div(@as(f32, @floatFromInt(i)));

    const direction = gridAvg.sub(.{ .x = position.x, .y = position.y });
    const velocity = direction.mult(speed).div(@sqrt(direction.dot(direction)));
    position.x += velocity.x;
    position.y += velocity.y;
}

/// Compute the grid cells occupied by the exterior of a rectangle.
pub fn getRectExteriorCellIds(rect: *const Rect(f32), grid: *const NavMeshGrid, cellIds: *std.ArrayList(usize)) void {
    const corners = [4]Vec2(f32){
        Vec2(f32){
            .x = rect.x,
            .y = rect.y,
        },
        Vec2(f32){
            .x = rect.x + rect.w,
            .y = rect.y,
        },
        Vec2(f32){
            .x = rect.x + rect.w,
            .y = rect.y + rect.h,
        },
        Vec2(f32){
            .x = rect.x,
            .y = rect.y + rect.h,
        },
    };

    getPolygonExteriorCellIds(
        &[_]Line(f32){
            .{
                .a = corners[0],
                .b = corners[1],
            },
            .{
                .a = corners[1],
                .b = corners[2],
            },
            .{
                .a = corners[2],
                .b = corners[3],
            },
            .{
                .a = corners[3],
                .b = corners[0],
            },
        },
        grid,
        cellIds,
    );
}

/// Compute the grid cells (may contain duplicates) occupied by a polygon exterior.
/// The algorithm takes the polygon faces and performs a line search from vertex to vertex to find occupied grid cells.
pub fn getPolygonExteriorCellIds(faces: []const Line(f32), grid: *const NavMeshGrid, cellIds: *std.ArrayList(usize)) void {
    for (faces) |face| {
        // Compute number of steps to take from vertex a to b.
        var step = face.b.sub(face.a);
        const stepSize = grid.cellSize / 2;
        const numSteps = @as(
            usize,
            @intFromFloat(@max(
                @abs(step.x / stepSize),
                @abs(step.y / stepSize),
            )),
        );

        // Normalize direction from vertex to vertex.
        step = step
            .div(step.norm())
            .mult(stepSize);

        // Collect cells along the polygon face.
        var i: usize = 0;
        var p = face.a;
        while (i < numSteps) : ({
            i += 1;
            p = p.add(step);
        }) {
            cellIds.append(grid.getCellId(&p)) catch undefined;
        }
    }
}

const expect = std.testing.expect;

test "test getCellId" {
    try expect(__getCellId(&Vec2(f32){ .x = 0, .y = 0 }, 1e-1, 10, 10) == 0);
    try expect(__getCellId(&Vec2(f32){ .x = 1, .y = 1 }, 1e-1, 10, 10) == 99);
}

test "test grid initialization" {
    var grid = NavMeshGrid.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 1, .h = 1 }, 1e-1);
    defer grid.deinit();
    try expect(grid.numCols == 10);
    try expect(grid.numRows == 10);

    var i: usize = 0;
    for (grid.grid) |cell| {
        try expect(0 < cell.x and cell.x < 1);
        try expect(0 < cell.y and cell.y < 1);

        const cellId = grid.getCellId(&cell);
        try expect(cellId == i);

        const _cell = grid.getCellCenter(cellId);
        try expect(cell.x == _cell.x and cell.y == _cell.y);

        i += 1;
    }

    // Ensure first cell has correct graph connectivity.
    //
    // x | x | x | ...
    // x | 0 | 1 | ...
    // x |0+c|1+c| ...
    try expect(grid.neighbors[0][0] == null);
    try expect(grid.neighbors[0][1] == null);
    try expect(grid.neighbors[0][2] == null);
    try expect(grid.neighbors[0][3] == null);
    try expect(grid.neighbors[0][4].? == 1);
    try expect(grid.neighbors[0][5].? == 1 + grid.numCols);
    try expect(grid.neighbors[0][6].? == grid.numCols);
    try expect(grid.neighbors[0][7] == null);

    // Ensure all interior cells have all 8 neighbors.
    i = 1;
    while (i < grid.numRows - 1) : (i += 1) {
        var j: usize = 1;
        while (j < grid.numCols - 1) : (j += 1) {
            for (grid.getAdjacentCellIds(j + i * grid.numCols)) |neighbor| {
                try expect(neighbor != null);
            }
        }
    }
}

test "test pathfinding" {
    var grid = NavMeshGrid.init(std.testing.allocator, .{ .x = 0, .y = 0, .w = 1, .h = 1 }, 1e-1);
    defer grid.deinit();
    try expect(grid.numCols == 10);
    try expect(grid.numRows == 10);

    const pInit = Vec2(f32){ .x = 1e-2, .y = 1e-2 };
    const pTarget = Vec2(f32){ .x = 1 - 1e-2, .y = 1 - 1e-2 };

    const cellInit = grid.getCellId(&pInit);
    const cellTarget = grid.getCellId(&pTarget);

    try expect(cellInit == 0);
    try expect(cellTarget == grid.grid.len - 1);

    var path = std.ArrayList(usize).init(std.testing.allocator);
    defer path.deinit();

    // pathfind(cellInit, cellTarget, &grid, null, &path);
    var pathfinder = Pathfinder(DistancePriorityQueue, Vec2(f32)).init(std.testing.allocator, grid.getCellCenter(cellTarget).*);
    defer pathfinder.deinit();
    pathfinder.pathfind(cellInit, cellTarget, &grid, null, &path);

    // Ensure that the path is connected.
    var i: usize = 0;
    while (i < path.items.len - 1) : (i += 1) {
        var found = false;
        for (grid.getAdjacentCellIds(path.items[i])) |neighbor| {
            if (neighbor != null and neighbor.? == path.items[i + 1]) {
                found = true;
                break;
            }
        }
        try expect(found);
    }
}
