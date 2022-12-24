const std = @import("std");

const game = @import("game.zig");
const sdl = @import("sdl.zig");
const math = @import("math.zig");
const Rect = math.Rect;
const Vec2 = math.Vec2;
const Line = math.Line;

pub const NavMeshGrid = struct {
    pub const directions: [8][2]i32 = [8][2]i32{ .{ -1, 0 }, .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ -1, 1 } };

    allocator: std.mem.Allocator,
    numCols: usize,
    numRows: usize,
    grid: []Vec2(f32),
    cellSize: f32,
    neighbors: [][8]?usize,
    renderPoints: []sdl.SDL_Point,

    pub fn init(allocator: std.mem.Allocator, region: Rect(f32), cellSize: f32) NavMeshGrid {
        const cols: usize = @floatToInt(usize, (region.x + region.w) / cellSize);
        const rows: usize = @floatToInt(usize, (region.y + region.h) / cellSize);
        var grid: []Vec2(f32) = allocator.alloc(Vec2(f32), rows * cols) catch undefined;
        var neighbors: [][8]?usize = allocator.alloc([8]?usize, rows * cols) catch undefined;
        var renderPoints: []sdl.SDL_Point = allocator.alloc(sdl.SDL_Point, rows * cols) catch undefined;

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
                const idx = @intCast(usize, j) + @intCast(usize, i) * cols;
                grid[idx] = .{ .x = x, .y = y };
                renderPoints[idx] = sdl.SDL_Point{
                    .x = @floatToInt(i32, game.unnormalizeWidth(x)),
                    .y = @floatToInt(i32, game.unnormalizeHeight(y)),
                };
            }
        }

        // Fill in neighbors
        i = 0;
        while (i < rows) : (i += 1) {
            var j: i32 = 0;
            while (j < cols) : (j += 1) {
                inline for (NavMeshGrid.directions) |d, idx| {
                    const dj = j + d[0];
                    const di = i + d[1];
                    const gridIdx = @intCast(usize, j) + @intCast(usize, i) * cols;
                    if (0 <= dj and dj < cols and 0 <= di and di < rows) {
                        const neighborIdx = @intCast(usize, dj) + @intCast(usize, di) * cols;
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
            .renderPoints = renderPoints,
        };
    }

    pub fn deinit(self: *NavMeshGrid) void {
        self.allocator.free(self.grid);
        self.allocator.free(self.neighbors);
        self.allocator.free(self.renderPoints);
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

fn __getCellId(p: *const Vec2(f32), cellSize: f32, rows: usize, cols: usize) usize {
    // Clamp point to grid bounds
    const px = math.clamp(p.x, 0.0, 1.0);
    const py = math.clamp(p.y, 0.0, 1.0);
    const x = math.clamp(@floatToInt(usize, px / cellSize), 0, cols - 1);
    const y = math.clamp(@floatToInt(usize, py / cellSize), 0, rows - 1);
    return x + y * cols;
}

const CellPair = struct {
    cellId: usize,
    cell: *const Vec2(f32),
};

fn __lessThan(context: *const Vec2(f32), a: CellPair, b: CellPair) std.math.Order {
    return std.math.order(context.sqDist(a.cell.*), context.sqDist(b.cell.*));
}

const VisibilityContext = struct {
    visibleCells: *const std.AutoArrayHashMap(usize, bool),
    targetPoint: *const Vec2(f32),
};

// Bias towards navigating through cover by making navpoints that are visible be considered further away.
fn __lessThanWithVisibilityBias(context: *const VisibilityContext, a: CellPair, b: CellPair) std.math.Order {
    var adist = context.targetPoint.sqDist(a.cell.*);
    var bdist = context.targetPoint.sqDist(b.cell.*);
    const aVisible = context.visibleCells.get(a.cellId) orelse false;
    const bVisible = context.visibleCells.get(b.cellId) orelse false;
    if (aVisible) adist *= 10;
    if (bVisible) bdist *= 10;
    return std.math.order(adist, bdist);
}

pub const DistancePriorityQueue = std.PriorityQueue(CellPair, *const Vec2(f32), __lessThan);
const DistanceVisibilityPriorityQueue = std.PriorityQueue(CellPair, *const VisibilityContext, __lessThanWithVisibilityBias);

pub fn pathfindVisibilityBias(
    cellInit: usize,
    target: usize,
    grid: *const NavMeshGrid,
    blocked: ?*const std.AutoArrayHashMap(usize, bool),
    visible: ?*const std.AutoArrayHashMap(usize, bool),
    path: *std.ArrayList(usize),
) void {
    var queue =
        DistanceVisibilityPriorityQueue.init(
            grid.allocator,
            &.{ .visibleCells = visible.?, .targetPoint = grid.getCellCenter(target) });
    defer queue.deinit();

    var seen = grid.allocator.alloc(bool, grid.grid.len) catch unreachable;
    defer grid.allocator.free(seen);
    for (seen) |_, i| {
        seen[i] = false;
    }
    seen[cellInit] = true;

    var action = grid.allocator.alloc(usize, grid.grid.len) catch unreachable;
    defer grid.allocator.free(action);
    for (action) |_, i| {
        action[i] = 0;
    }

    var stack = std.ArrayList(usize).init(grid.allocator);
    defer stack.deinit();

    var found = false;
    var cellPair: CellPair = undefined;
    var cell: usize = undefined;
    queue.add(.{ .cellId = cellInit, .cell = grid.getCellCenter(cellInit) }) catch unreachable;
    while (queue.len > 0) {
        cellPair = queue.remove();
        cell = cellPair.cellId;

        if (cell == target) {
            found = true;
            break;
        }

        for (grid.getAdjacentCellIds(cell)) |neighbor, i| {
            if (neighbor == null or seen[neighbor.?] or (blocked != null and blocked.?.get(neighbor.?) orelse false)) continue;
            seen[neighbor.?] = true;
            action[neighbor.?] = i;
            queue.add(.{ .cellId = neighbor.?, .cell = grid.getCellCenter(neighbor.?) }) catch unreachable;
        }
    }

    // Empty path.
    if (!found) return;

    // Reconstruct the path by reversing the actions we took.
    // Re-use stack here as the inverse path.
    stack.append(cell) catch undefined;
    while (cell != cellInit) {
        const d = NavMeshGrid.directions[action[cell]];
        const center = grid.getCellCenter(cell);
        cell = grid.getCellId(&math.Vec2(f32){
            .x = center.x - grid.cellSize * @intToFloat(f32, d[0]),
            .y = center.y - grid.cellSize * @intToFloat(f32, d[1]),
        });
        stack.append(cell) catch undefined;
    }

    // Get the final path cellInit --> cellTarget by reversing the stack.
    // Toss the first element to avoid including current location in the path.
    _ = stack.popOrNull();
    while (stack.items.len > 0) {
        path.append(stack.pop()) catch undefined;
    }
}

/// Performs A* pathfinding. Fills in the `path` argument with the selected route.
pub fn pathfind(
    cellInit: usize,
    target: usize,
    grid: *const NavMeshGrid,
    blocked: ?*const std.AutoArrayHashMap(usize, bool),
    path: *std.ArrayList(usize),
) void {
    var queue = DistancePriorityQueue.init(grid.allocator, grid.getCellCenter(target));
    defer queue.deinit();

    var seen = grid.allocator.alloc(bool, grid.grid.len) catch unreachable;
    defer grid.allocator.free(seen);
    for (seen) |_, i| {
        seen[i] = false;
    }
    seen[cellInit] = true;

    var action = grid.allocator.alloc(usize, grid.grid.len) catch unreachable;
    defer grid.allocator.free(action);
    for (action) |_, i| {
        action[i] = 0;
    }

    var stack = std.ArrayList(usize).init(grid.allocator);
    defer stack.deinit();

    var found = false;
    var cellPair: CellPair = undefined;
    var cell: usize = undefined;
    // stack.append(cellInit) catch undefined;
    queue.add(.{ .cellId = cellInit, .cell = grid.getCellCenter(cellInit) }) catch unreachable;
    // while (stack.items.len > 0) {
    while (queue.len > 0) {
        // cell = stack.pop();
        cellPair = queue.remove();
        cell = cellPair.cellId;

        if (cell == target) {
            found = true;
            break;
        }

        for (grid.getAdjacentCellIds(cell)) |neighbor, i| {
            if (neighbor == null or seen[neighbor.?] or (blocked != null and blocked.?.get(neighbor.?) orelse false)) continue;
            seen[neighbor.?] = true;
            action[neighbor.?] = i;
            // stack.append(neighbor.?) catch undefined;
            queue.add(.{ .cellId = neighbor.?, .cell = grid.getCellCenter(neighbor.?) }) catch unreachable;
        }
    }

    // Empty path.
    if (!found) return;

    // Reconstruct the path by reversing the actions we took.
    // Re-use stack here as the inverse path.
    // stack.clearAndFree();
    stack.append(cell) catch undefined;
    while (cell != cellInit) {
        const d = NavMeshGrid.directions[action[cell]];
        const center = grid.getCellCenter(cell);
        cell = grid.getCellId(&math.Vec2(f32){
            .x = center.x - grid.cellSize * @intToFloat(f32, d[0]),
            .y = center.y - grid.cellSize * @intToFloat(f32, d[1]),
        });
        stack.append(cell) catch undefined;
    }

    // Get the final path cellInit --> cellTarget by reversing the stack.
    // Toss the first element to avoid including current location in the path.
    _ = stack.popOrNull();
    while (stack.items.len > 0) {
        path.append(stack.pop()) catch undefined;
    }
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
        const numSteps = @floatToInt(
            usize,
            @max(
                @fabs(step.x / stepSize),
                @fabs(step.y / stepSize),
            ),
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
            cellIds.append(grid.getCellId(&p))
                catch undefined;
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

    pathfind(cellInit, cellTarget, &grid, null, &path);

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
