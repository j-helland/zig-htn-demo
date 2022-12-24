const std = @import("std");

pub fn Rect(comptime T: type) type {
    return struct{ x: T, y: T, w: T, h: T };
}

pub fn Line(comptime T: type) type {
    return struct { a: Vec2(T), b: Vec2(T) };
}

pub fn Vec2(comptime T: type) type {
    return struct{
        const This = @This();

        x: T,
        y: T,

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

        pub fn norm(self: *const This) T {
            return @sqrt(self.dot(self.*));
        }
    };
}

pub fn clamp(x: anytype, a: anytype, b: anytype) @TypeOf(x) {
    return @max(a, @min(b, x));
}

pub fn angle(u: Vec2(f32), v: Vec2(f32)) f32 {
    return std.math.acos( u.dot(v) / (u.norm() * v.norm() + 1e-8) ) * (180.0 / std.math.pi);
}

pub fn isCollidingPointxRect(p: *const Vec2(f32), rect: *const Rect(f32)) bool {
    return
        p.x < rect.x + rect.w and
        p.x > rect.x and
        p.y < rect.y + rect.h and
        p.y > rect.y;
}

pub fn isCollidingRectXRect(p1: *const Rect(f32), p2: *const Rect(f32)) bool {
    const p1_r = p1.x + p1.w;
    const p1_b = p1.y + p1.h;
    const p2_r = p2.x + p2.w;
    const p2_b = p2.y + p2.h;
    return p1.x < p2_r and p1_r > p2.x and p1.y < p2_b and p1_b > p2.y;
}
