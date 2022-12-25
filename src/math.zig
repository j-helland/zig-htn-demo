const std = @import("std");

pub fn Rect(comptime T: type) type {
    return struct {
        const This = @This();

        x: T, y: T, w: T, h: T,

        pub fn sqDistPoint(self: *const This, p: Vec2(T)) T {
            return p.sqDistRect(self.*);
        }

        pub fn intersectsPoint(self: *const This, p: Vec2(T)) bool {
            return p.intersectsRect(self.*);
        }

        pub fn intersectsLine(self: *const This, l: Line(T)) bool {
            return l.intersectsRect(self.*);
        }

        pub fn intersectsRect(self: *const This, r: Rect(T)) bool {
            const r1_r = self.x + self.w;
            const r1_b = self.y + self.h;
            const r2_r = r.x + r.w;
            const r2_b = r.y + r.h;
            return self.x < r2_r and r1_r > r.x and self.y < r2_b and r1_b > r.y;
        }
    };
}

pub fn Line(comptime T: type) type {
    return struct {
        const This = @This();

        a: Vec2(T), b: Vec2(T),

        pub fn getIntersection(self: *const This, other: Line(T)) ?Vec2(T) {
            const s1 = self.b.sub(self.a);
            const s2 = other.b.sub(other.a);
            const s1xs2 = s1.cross(s2) + 1e-8;

            const u = self.a.sub(other.a);
            const s1xu = s1.cross(u);
            const s2xu = s2.cross(u);

            const s = s1xu / s1xs2;
            const t = s2xu / s1xs2;

            var intersection = Vec2(f32){ .x = 0, .y = 0 };
            if (s >= 0 and s <= 1 and t >= 0 and t <= 1) {
                intersection.x = self.a.x + t * s1.x;
                intersection.y = self.a.y + t * s1.y;
                return intersection;
            }
            return null;
        }

        pub fn intersectsLine(self: *const This, other: Line(T)) bool {
            // NOTE: code duplication. This method is used frequently, so I want to avoid branching and copies where possible.
            const s1 = self.b.sub(self.a);
            const s2 = other.b.sub(other.a);
            const s1xs2 = s1.cross(s2) + 1e-8;

            const u = self.a.sub(other.a);
            const s1xu = s1.cross(u);
            const s2xu = s2.cross(u);

            const s = s1xu / s1xs2;
            const t = s2xu / s1xs2;

            return (s >= 0 and s <= 1 and t >= 0 and t <= 1);
        }

        pub fn intersectsRect(self: *const This, r: Rect(T)) bool {
            const l1: Line(f32) = .{
                .a = .{ .x = r.x, .y = r.y },
                .b = .{ .x = r.x + r.w, .y = r.y },
            };
            const l2: Line(f32) = .{
                .a = .{ .x = r.x + r.w, .y = r.y },
                .b = .{ .x = r.x + r.w, .y = r.y + r.h },
            };
            const l3: Line(f32) = .{
                .a = .{ .x = r.x + r.w, .y = r.y + r.h },
                .b = .{ .x = r.x, .y = r.y + r.h },
            };
            const l4: Line(f32) = .{
                .a = .{ .x = r.x, .y = r.y + r.h },
                .b = .{ .x = r.x, .y = r.y },
            };
            return self.intersectsLine(l1) or
                self.intersectsLine(l2) or
                self.intersectsLine(l3) or
                self.intersectsLine(l4);
        }
    };
}

pub fn Vec2(comptime T: type) type {
    return struct {
        const This = @This();

        x: T, y: T,

        pub fn add(self: *const This, v: This) This {
            return .{ .x = self.x + v.x, .y = self.y + v.y };
        }

        pub fn sub(self: *const This, v: This) This {
            return .{ .x = self.x - v.x, .y = self.y - v.y };
        }

        pub fn mult(self: *const This, a: T) This {
            return .{ .x = a * self.x, .y = a * self.y };
        }

        pub fn div(self: *const This, a: T) This {
            const d = a + 1e-8;
            return .{ .x = self.x / d, .y = self.y / d };
        }

        pub fn dot(self: *const This, u: This) T {
            return self.x * u.x + self.y * u.y;
        }

        pub fn cross(self: *const This, u: This) T {
            return self.x * u.y - self.y * u.x;
        }

        pub fn norm(self: *const This) T {
            return @sqrt(self.dot(self.*));
        }

        pub fn sqDist(self: *const This, u: This) T {
            const v = self.sub(u);
            return v.dot(v);
        }

        /// Distance to nearest vertex of rect
        pub fn sqDistRect(self: *const This, r: Rect(T)) T {
            const v1 = Vec2(f32){ .x = r.x, .y = r.y };
            const v2 = Vec2(f32){ .x = r.x + r.w, .y = r.y };
            const v3 = Vec2(f32){ .x = r.x + r.w, .y = r.y + r.h };
            const v4 = Vec2(f32){ .x = r.x, .y = r.y + r.h };

            return @min(
                @min(self.sqDist(v1), self.sqDist(v2)),
                @min(self.sqDist(v3), self.sqDist(v4)),
            );
        }

        pub fn intersectsRect(self: *const This, r: Rect(T)) bool {
            return
                self.x < r.x + r.w and
                self.x > r.x and
                self.y < r.y + r.h and
                self.y > r.y;
            }
    };
}

pub fn clamp(x: anytype, a: anytype, b: anytype) @TypeOf(x) {
    return @max(a, @min(b, x));
}

/// Angle between two vectors in degrees.
pub fn angle(u: Vec2(f32), v: Vec2(f32)) f32 {
    return std.math.acos( u.dot(v) / (u.norm() * v.norm() + 1e-8) ) * (180.0 / std.math.pi);
}


const expect = std.testing.expect;

fn isClose(x: f32, y: f32) bool {
    return @fabs(x - y) < 1e-6;
}

fn multMatVec(v: Vec2(f32), m: [4]f32) Vec2(f32) {
    return .{
        .x = m[0] * v.x + m[1] * v.y,
        .y = m[2] * v.x + m[3] * v.y,
    };
}

test "line intersection" {
    // Intersection at the origin
    var l1 = Line(f32){
        .a = .{ .x = -1, .y = 0 },
        .b = .{ .x = 1, .y = 0 },
    };
    var l2 = Line(f32){
        .a = .{ .x = 0, .y = -1 },
        .b = .{ .x = 0, .y = 1 },
    };
    var intersection = l1.getIntersection(l2);
    try expect(intersection != null);
    try expect(isClose(intersection.?.x, 0) and isClose(intersection.?.y, 0));

    // Translate the intersection point
    const u = Vec2(f32){ .x = 1, .y = 1 };
    l1.a = l1.a.add(u);
    l1.b = l1.b.add(u);
    l2.a = l2.a.add(u);
    l2.b = l2.b.add(u);
    intersection = l1.getIntersection(l2);
    try expect(intersection != null);
    try expect(isClose(intersection.?.x, u.x) and isClose(intersection.?.y, u.y));

    // Rotate the intersection point
    const theta = std.math.pi * 38.0 / 180.0;
    const rot = [_]f32{ @cos(theta), -@sin(theta), @sin(theta), @cos(theta) };
    l1.a = multMatVec(l1.a, rot);
    l1.b = multMatVec(l1.b, rot);
    l2.a = multMatVec(l2.a, rot);
    l2.b = multMatVec(l2.b, rot);
    intersection = l1.getIntersection(l2);
    const expected = multMatVec(.{ .x = 1, .y = 1 }, rot);
    try expect(intersection != null);
    try expect(isClose(intersection.?.x, expected.x) and isClose(intersection.?.y, expected.y));
}
