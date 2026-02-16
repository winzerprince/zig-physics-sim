const rl = @import("raylib");

/// 2D vector for physics calculations
pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return .{ .x = self.x * s, .y = self.y * s };
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn lengthSq(self: Vec2) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub fn normalize(self: Vec2) Vec2 {
        const len = self.length();
        if (len == 0) return .{ .x = 0, .y = 0 };
        return self.scale(1.0 / len);
    }

    pub fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn dist(self: Vec2, other: Vec2) f32 {
        return self.sub(other).length();
    }

    pub fn toRaylib(self: Vec2) rl.Vector2 {
        return .{ .x = self.x, .y = self.y };
    }
};
