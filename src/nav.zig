const std = @import("std");

const game = @import("game");
const sdl = @import("sdl.zig");
const math = @import("math.zig");
const Rect = math.Rect;
const Vec2 = math.Vec2;

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

    pub fn getCellId(self: *NavMeshGrid, p: *const Vec2(f32)) usize {
        return __getCellId(p, self.cellSize, self.numRows, self.numCols);
    }

    pub fn getCellCenter(self: *NavMeshGrid, cellId: usize) *const Vec2(f32) {
        return &self.grid[cellId];
    }

    pub fn getAdjacentCellIds(self: *NavMeshGrid, cellId: usize) [8]?usize {
        return self.neighbors[cellId];
    }
};

fn __getCellId(p: *const Vec2(f32), cellSize: f32, rows: usize, cols: usize) usize {
    const x = @max(0, @min(cols - 1, @floatToInt(usize, p.x / cellSize)));
    const y = @max(0, @min(rows - 1, @floatToInt(usize, p.y / cellSize)));
    return x + y * cols;
}

const CellPair = struct {
    cellId: usize,
    cell: *const Vec2(f32),
};

fn lessThan(context: *const Vec2(f32), a: CellPair, b: CellPair) std.math.Order {
    return std.math.order(context.sqDist(a.cell.*), context.sqDist(b.cell.*));
}

const DistancePriorityQueue = std.PriorityQueue(CellPair, *const Vec2(f32), lessThan);

pub fn dfs(cellInit: usize, target: usize, grid: *NavMeshGrid, path: *std.ArrayList(usize)) void {
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
            if (neighbor == null or seen[neighbor.?]) continue;
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
    while (stack.items.len > 0) {
        path.append(stack.pop()) catch undefined;
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

test "test dfs" {
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

    dfs(cellInit, cellTarget, &grid, &path);

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
