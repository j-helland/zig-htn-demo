const std = @import("std");

pub fn Queue(comptime Child: type) type {
    return struct {
        const This = @This();
        const Node = struct {
            data: Child,
            next: ?*Node,
        };
        gpa: std.mem.Allocator,
        start: ?*Node,
        end: ?*Node,
        len: usize = 0,

        pub fn init(gpa: std.mem.Allocator) This {
            return This{
                .gpa = gpa,
                .start = null,
                .end = null,
            };
        }

        pub fn deinit(self: *This) void {
            while (self.pop()) |_| {}
        }

        pub fn peek(this: *This) ?Child {
            const start = this.start orelse return null;
            return start.data;
        }

        pub fn push(this: *This, value: Child) !void {
            defer this.len += 1;
            const node = try this.gpa.create(Node);
            node.* = .{ .data = value, .next = null };
            if (this.end) |end| end.next = node //
            else this.start = node;
            this.end = node;
        }

        pub fn pop(this: *This) ?Child {
            const start = this.start orelse return null;
            defer this.len -= 1;
            defer this.gpa.destroy(start);
            if (start.next) |next|
                this.start = next
            else {
                this.start = null;
                this.end = null;
            }
            return start.data;
        }

        pub fn pushSlice(this: *This, slice: []Child) !void {
            for (slice) |item| try this.push(item);
        }
    };
}

const expect = std.testing.expect;

test "queue" {
    const vals = [_]i32{ 1, 2, 3, 4, 5, 6 };

    var queue = Queue(i32).init(std.testing.allocator);
    try expect(queue.len == 0);
    try expect(queue.peek() == null);
    try expect(queue.pop() == null);

    for (vals) |v| try queue.push(v);
    try expect(queue.len == vals.len);
    for (vals) |v| {
        const q = queue.pop();
        try expect(q != null);
        try expect(q.? == v);
    }

    try expect(queue.len == 0);
    try expect(queue.peek() == null);
    try expect(queue.pop() == null);
}
