const rl = @import("raylib");
const Vec2 = @import("../core/vec2.zig").Vec2;

const G: f32 = 500; // gravitational constant (scaled for visual)
const TRAIL_LEN = 200;

pub const Body = struct {
    pos: Vec2,
    vel: Vec2 = .{},
    mass: f32,
    radius: f32,
    color: rl.Color,
    trail: [TRAIL_LEN]Vec2 = undefined,
    trail_idx: usize = 0,
    trail_count: usize = 0,
    is_rocket: bool = false,

    pub fn pushTrail(self: *Body) void {
        self.trail[self.trail_idx] = self.pos;
        self.trail_idx = (self.trail_idx + 1) % TRAIL_LEN;
        if (self.trail_count < TRAIL_LEN) self.trail_count += 1;
    }
};

pub const OrbitalSim = struct {
    bodies: [32]Body = undefined,
    count: usize = 0,
    time_scale: f32 = 1.0,
    screen_w: f32,
    screen_h: f32,
    cam_offset: Vec2 = .{},
    cam_zoom: f32 = 1.0,

    pub fn init(w: f32, h: f32) OrbitalSim {
        var sim = OrbitalSim{ .screen_w = w, .screen_h = h };
        sim.setupSolarSystem();
        return sim;
    }

    fn setupSolarSystem(self: *OrbitalSim) void {
        const cx = self.screen_w / 2;
        const cy = self.screen_h / 2;

        // Sun
        self.addBody(.{ .x = cx, .y = cy }, .{}, 5000, 30, rl.Color.init(255, 220, 50, 255));

        // Planets at various orbits
        const orbits = [_]struct { dist: f32, mass: f32, radius: f32, color: rl.Color }{
            .{ .dist = 80, .mass = 5, .radius = 5, .color = rl.Color.init(180, 180, 180, 255) },
            .{ .dist = 130, .mass = 15, .radius = 8, .color = rl.Color.init(200, 150, 50, 255) },
            .{ .dist = 190, .mass = 20, .radius = 9, .color = rl.Color.init(50, 100, 255, 255) },
            .{ .dist = 260, .mass = 12, .radius = 6, .color = rl.Color.init(200, 50, 50, 255) },
            .{ .dist = 350, .mass = 200, .radius = 18, .color = rl.Color.init(220, 180, 120, 255) },
        };

        for (orbits) |o| {
            // Circular orbit: v = sqrt(G*M/r)
            const orbital_vel = @sqrt(G * 5000 / o.dist);
            self.addBody(
                .{ .x = cx + o.dist, .y = cy },
                .{ .x = 0, .y = orbital_vel },
                o.mass,
                o.radius,
                o.color,
            );
        }

        // Add rocket (small, controllable)
        self.addBody(
            .{ .x = cx + 220, .y = cy },
            .{ .x = 0, .y = @sqrt(G * 5000 / 220) },
            1,
            3,
            rl.Color.init(0, 255, 0, 255),
        );
        self.bodies[self.count - 1].is_rocket = true;
    }

    fn addBody(self: *OrbitalSim, pos: Vec2, vel: Vec2, mass: f32, radius: f32, color: rl.Color) void {
        if (self.count >= 32) return;
        self.bodies[self.count] = .{
            .pos = pos,
            .vel = vel,
            .mass = mass,
            .radius = radius,
            .color = color,
        };
        self.count += 1;
    }

    pub fn update(self: *OrbitalSim, dt: f32) void {
        const scaled_dt = dt * self.time_scale;
        const substeps: usize = 4;
        const sub_dt = scaled_dt / @as(f32, @floatFromInt(substeps));

        for (0..substeps) |_| {
            // Calculate gravitational forces
            for (0..self.count) |i| {
                for (0..self.count) |j| {
                    if (i == j) continue;
                    const a = &self.bodies[i];
                    const b = &self.bodies[j];
                    const delta = b.pos.sub(a.pos);
                    const dist_sq = @max(delta.lengthSq(), 100); // softening
                    const force_mag = G * a.mass * b.mass / dist_sq;
                    const force = delta.normalize().scale(force_mag / a.mass);
                    self.bodies[i].vel = self.bodies[i].vel.add(force.scale(sub_dt));
                }
            }

            // Rocket controls
            for (0..self.count) |i| {
                if (self.bodies[i].is_rocket) {
                    const thrust: f32 = 200;
                    if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) self.bodies[i].vel.y -= thrust * sub_dt;
                    if (rl.isKeyDown(.s) or rl.isKeyDown(.down)) self.bodies[i].vel.y += thrust * sub_dt;
                    if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) self.bodies[i].vel.x -= thrust * sub_dt;
                    if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) self.bodies[i].vel.x += thrust * sub_dt;
                }
            }

            // Integrate positions
            for (0..self.count) |i| {
                self.bodies[i].pos = self.bodies[i].pos.add(self.bodies[i].vel.scale(sub_dt));
            }
        }

        // Record trails
        for (0..self.count) |i| {
            self.bodies[i].pushTrail();
        }

        // Camera zoom
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            self.cam_zoom *= if (wheel > 0) 1.1 else 0.9;
            self.cam_zoom = @max(0.1, @min(self.cam_zoom, 5.0));
        }

        // Time controls
        if (rl.isKeyPressed(.equal)) self.time_scale = @min(self.time_scale * 1.5, 10);
        if (rl.isKeyPressed(.minus)) self.time_scale = @max(self.time_scale / 1.5, 0.1);
    }

    pub fn draw(self: *OrbitalSim) void {
        const cx = self.screen_w / 2;
        const cy = self.screen_h / 2;

        // Draw trails
        for (0..self.count) |i| {
            const b = &self.bodies[i];
            if (b.trail_count < 2) continue;
            var k: usize = 1;
            while (k < b.trail_count) : (k += 1) {
                const idx0 = (b.trail_idx + TRAIL_LEN - b.trail_count + k - 1) % TRAIL_LEN;
                const idx1 = (b.trail_idx + TRAIL_LEN - b.trail_count + k) % TRAIL_LEN;
                const alpha: u8 = @intFromFloat(@as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(b.trail_count)) * 120);
                const trail_color = rl.Color.init(b.color.r, b.color.g, b.color.b, alpha);
                const p0 = self.worldToScreen(b.trail[idx0], cx, cy);
                const p1 = self.worldToScreen(b.trail[idx1], cx, cy);
                rl.drawLineV(p0.toRaylib(), p1.toRaylib(), trail_color);
            }
        }

        // Draw bodies
        for (0..self.count) |i| {
            const b = &self.bodies[i];
            const sp = self.worldToScreen(b.pos, cx, cy);
            const sr = b.radius * self.cam_zoom;
            rl.drawCircleV(sp.toRaylib(), sr, b.color);
            if (b.is_rocket) {
                rl.drawText("ROCKET", @intFromFloat(sp.x - 20), @intFromFloat(sp.y - sr - 15), 12, .green);
            }
        }

        // HUD
        rl.drawText(rl.textFormat("Time: x%.1f  (+/- to change)", .{self.time_scale}), 10, 10, 20, .white);
        rl.drawText("WASD/Arrows: fly rocket | Scroll: zoom | ESC: menu", 10, 35, 16, .light_gray);
    }

    fn worldToScreen(self: *OrbitalSim, pos: Vec2, cx: f32, cy: f32) Vec2 {
        return .{
            .x = (pos.x - cx) * self.cam_zoom + cx + self.cam_offset.x,
            .y = (pos.y - cy) * self.cam_zoom + cy + self.cam_offset.y,
        };
    }

    pub fn reset(self: *OrbitalSim) void {
        self.count = 0;
        self.time_scale = 1.0;
        self.cam_zoom = 1.0;
        self.cam_offset = .{};
        self.setupSolarSystem();
    }
};
