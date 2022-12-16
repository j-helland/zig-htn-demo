pub fn Rect(comptime T: type) type {
    return struct{ x: T, y: T, w: T, h: T };
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

        pub fn dot(self: *const This, u: This) T {
            return self.x * u.x + self.y * u.y;
        }

        pub fn sqDist(self: *const This, u: This) T {
            const v = self.sub(u);
            return v.dot(v);
        }
    };
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
