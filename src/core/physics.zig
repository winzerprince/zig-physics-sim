const Vec2 = @import("vec2.zig").Vec2;

pub const Particle = struct {
    pos: Vec2,
    vel: Vec2 = .{},
    acc: Vec2 = .{},
    mass: f32 = 1.0,
    radius: f32 = 4.0,
    color_idx: u8 = 0,
    alive: bool = true,

    /// Semi-implicit Euler integration
    pub fn integrate(self: *Particle, dt: f32) void {
        self.vel = self.vel.add(self.acc.scale(dt));
        self.pos = self.pos.add(self.vel.scale(dt));
        self.acc = .{}; // reset forces
    }

    pub fn applyForce(self: *Particle, force: Vec2) void {
        // F = ma, so a = F/m
        self.acc = self.acc.add(force.scale(1.0 / self.mass));
    }
};
