const std = @import("std");

const math = @import("math.zig");
const Rect = math.Rect;
const Vec2 = math.Vec2;

pub const NavMeshGrid = struct {
    allocator: std.mem.Allocator,
    numCols: usize,
    numRows: usize,
    grid: []Vec2(f32),
    cellSize: f32,

    pub fn init(allocator: std.mem.Allocator, region: Rect(f32), cellSize: f32) NavMeshGrid {
        const cols: usize = @floatToInt(usize, (region.x + region.w) / cellSize);
        const rows: usize = @floatToInt(usize, (region.y + region.h) / cellSize);
        var grid: []Vec2(f32) = allocator.alloc(Vec2(f32), rows * cols) catch undefined;

        // Generate grid cell values.
        var i: usize = 0;
        var y: f32 = cellSize / 2;
        while (i < rows) : ({ i += 1; y += cellSize; }) {
            var j: usize = 0;
            var x: f32 = cellSize / 2;
            while (j < cols) : ({ j += 1; x += cellSize; }) {
                grid[j + i * cols] = .{ .x = x, .y = y };
            }
        }

        return .{
            .allocator = allocator,
            .numCols = cols,
            .numRows = rows,
            .grid = grid,
            .cellSize = cellSize,
        };
    }

    pub fn deinit(self: *NavMeshGrid) void {
        self.allocator.free(self.grid);
    }

    pub fn getCellId(self: *NavMeshGrid, p: *const Vec2(f32)) usize {
        var x = @floatToInt(usize, p.x / self.cellSize);
        var y = @floatToInt(usize, p.y / self.cellSize);
        return x + y * self.numCols;
    }

    pub fn getCellCenter(self: *NavMeshGrid, cellId: usize) *const Vec2(f32) {
        return &self.grid[cellId];
    }
};


const expect = std.testing.expect;

test "test grid initialization" {
    var grid = NavMeshGrid.init(std.testing.allocator, .{.x = 0, .y = 0, .w = 1, .h = 1}, 1e-1);
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
}
