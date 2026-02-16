const rl = @import("raylib");
const Vec2 = @import("../core/vec2.zig").Vec2;
const Particle = @import("../core/physics.zig").Particle;

const MAX_PARTICLES = 2000;
const GRAVITY = Vec2{ .x = 0, .y = 500 };
const DAMPING: f32 = 0.98;
const RESTITUTION: f32 = 0.7;

const COLORS = [_]rl.Color{
    rl.Color.init(230, 41, 55, 255), // red
    rl.Color.init(0, 228, 48, 255), // green
    rl.Color.init(0, 121, 241, 255), // blue
    rl.Color.init(253, 249, 0, 255), // yellow
    rl.Color.init(255, 161, 0, 255), // orange
    rl.Color.init(200, 122, 255, 255), // purple
    rl.Color.init(0, 228, 225, 255), // cyan
    rl.Color.init(255, 109, 194, 255), // pink
};

pub const ParticleSim = struct {
    particles: [MAX_PARTICLES]Particle = undefined,
    count: usize = 0,
    gravity_on: bool = true,
    color_counter: u8 = 0,
    screen_w: f32,
    screen_h: f32,

    pub fn init(w: f32, h: f32) ParticleSim {
        return .{ .screen_w = w, .screen_h = h };
    }

    pub fn spawn(self: *ParticleSim, pos: Vec2, vel: Vec2, radius: f32) void {
        if (self.count >= MAX_PARTICLES) return;
        self.particles[self.count] = .{
            .pos = pos,
            .vel = vel,
            .radius = radius,
            .mass = radius * radius * 0.1,
            .color_idx = self.color_counter % @as(u8, @intCast(COLORS.len)),
        };
        self.count += 1;
        self.color_counter +%= 1;
    }

    pub fn update(self: *ParticleSim, dt: f32) void {
        for (0..self.count) |i| {
            var p = &self.particles[i];
            if (!p.alive) continue;

            // Apply gravity
            if (self.gravity_on) {
                p.applyForce(GRAVITY.scale(p.mass));
            }

            p.integrate(dt);

            // Damping
            p.vel = p.vel.scale(DAMPING);

            // Bounce off walls
            if (p.pos.x - p.radius < 0) {
                p.pos.x = p.radius;
                p.vel.x = -p.vel.x * RESTITUTION;
            }
            if (p.pos.x + p.radius > self.screen_w) {
                p.pos.x = self.screen_w - p.radius;
                p.vel.x = -p.vel.x * RESTITUTION;
            }
            if (p.pos.y - p.radius < 0) {
                p.pos.y = p.radius;
                p.vel.y = -p.vel.y * RESTITUTION;
            }
            if (p.pos.y + p.radius > self.screen_h) {
                p.pos.y = self.screen_h - p.radius;
                p.vel.y = -p.vel.y * RESTITUTION;
            }
        }

        // Particle-particle collisions
        self.resolveCollisions();
    }

    fn resolveCollisions(self: *ParticleSim) void {
        for (0..self.count) |i| {
            for (i + 1..self.count) |j| {
                var a = &self.particles[i];
                var b = &self.particles[j];
                if (!a.alive or !b.alive) continue;

                const delta = b.pos.sub(a.pos);
                const dist = delta.length();
                const min_dist = a.radius + b.radius;

                if (dist < min_dist and dist > 0.001) {
                    const normal = delta.normalize();

                    // Separate overlapping particles
                    const overlap = (min_dist - dist) * 0.5;
                    a.pos = a.pos.sub(normal.scale(overlap));
                    b.pos = b.pos.add(normal.scale(overlap));

                    // Elastic collision impulse
                    const rel_vel = a.vel.sub(b.vel);
                    const vel_along_normal = rel_vel.dot(normal);

                    if (vel_along_normal > 0) continue; // moving apart

                    const inv_mass_a = 1.0 / a.mass;
                    const inv_mass_b = 1.0 / b.mass;
                    const impulse = -(1.0 + RESTITUTION) * vel_along_normal / (inv_mass_a + inv_mass_b);

                    a.vel = a.vel.add(normal.scale(impulse * inv_mass_a));
                    b.vel = b.vel.sub(normal.scale(impulse * inv_mass_b));
                }
            }
        }
    }

    pub fn draw(self: *ParticleSim) void {
        for (0..self.count) |i| {
            const p = &self.particles[i];
            if (!p.alive) continue;
            const color = COLORS[p.color_idx % COLORS.len];
            rl.drawCircleV(p.pos.toRaylib(), p.radius, color);
        }

        // HUD
        const count_text = rl.textFormat("Particles: %d / %d", .{ @as(c_int, @intCast(self.count)), @as(c_int, MAX_PARTICLES) });
        rl.drawText(count_text, 10, 10, 20, .white);
        rl.drawText("Click: spawn | Right-click: burst | G: gravity | C: clear | ESC: menu", 10, 35, 16, .light_gray);
        if (!self.gravity_on) {
            rl.drawText("Gravity: OFF", 10, 55, 16, .yellow);
        }
    }

    pub fn clear(self: *ParticleSim) void {
        self.count = 0;
    }

    pub fn spawnBurst(self: *ParticleSim, center: Vec2, n: usize) void {
        for (0..n) |k| {
            const angle = @as(f32, @floatFromInt(k)) * 6.2832 / @as(f32, @floatFromInt(n));
            const speed: f32 = 150 + @as(f32, @floatFromInt(k % 5)) * 30;
            const vel = Vec2{
                .x = @cos(angle) * speed,
                .y = @sin(angle) * speed,
            };
            self.spawn(center, vel, 3 + @as(f32, @floatFromInt(k % 4)));
        }
    }
};
