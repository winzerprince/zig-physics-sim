const rl = @import("raylib");
const Vec2 = @import("../core/vec2.zig").Vec2;

const RESTITUTION: f32 = 0.6;
const GRAVITY = Vec2{ .x = 0, .y = 400 };

pub const Shape = enum { circle, rect };

pub const RigidBody = struct {
    pos: Vec2,
    vel: Vec2 = .{},
    angle: f32 = 0,
    angular_vel: f32 = 0,
    mass: f32 = 1.0,
    inv_mass: f32 = 1.0,
    shape: Shape = .circle,
    radius: f32 = 20,
    width: f32 = 40,
    height: f32 = 40,
    color: rl.Color = rl.Color.init(0, 228, 48, 255),
    is_static: bool = false,

    pub fn init(pos: Vec2, shape: Shape, mass: f32) RigidBody {
        return .{
            .pos = pos,
            .shape = shape,
            .mass = mass,
            .inv_mass = if (mass > 0) 1.0 / mass else 0,
        };
    }
};

pub const RigidBodySim = struct {
    bodies: [128]RigidBody = undefined,
    count: usize = 0,
    screen_w: f32,
    screen_h: f32,
    gravity_on: bool = true,

    pub fn init(w: f32, h: f32) RigidBodySim {
        var sim = RigidBodySim{ .screen_w = w, .screen_h = h };
        sim.setupScene();
        return sim;
    }

    fn setupScene(self: *RigidBodySim) void {
        // Floor
        var floor = RigidBody.init(.{ .x = self.screen_w / 2, .y = self.screen_h - 20 }, .rect, 0);
        floor.width = self.screen_w;
        floor.height = 40;
        floor.is_static = true;
        floor.inv_mass = 0;
        floor.color = rl.Color.init(80, 80, 80, 255);
        self.addBody(floor);

        // Left wall
        var lw = RigidBody.init(.{ .x = 10, .y = self.screen_h / 2 }, .rect, 0);
        lw.width = 20;
        lw.height = self.screen_h;
        lw.is_static = true;
        lw.inv_mass = 0;
        lw.color = rl.Color.init(80, 80, 80, 255);
        self.addBody(lw);

        // Right wall
        var rw = RigidBody.init(.{ .x = self.screen_w - 10, .y = self.screen_h / 2 }, .rect, 0);
        rw.width = 20;
        rw.height = self.screen_h;
        rw.is_static = true;
        rw.inv_mass = 0;
        rw.color = rl.Color.init(80, 80, 80, 255);
        self.addBody(rw);

        // Some initial objects
        const colors = [_]rl.Color{
            rl.Color.init(230, 41, 55, 255),
            rl.Color.init(0, 121, 241, 255),
            rl.Color.init(253, 249, 0, 255),
            rl.Color.init(200, 122, 255, 255),
        };
        for (0..8) |i| {
            const fi = @as(f32, @floatFromInt(i));
            var b = RigidBody.init(
                .{ .x = 150 + fi * 80, .y = 100 + fi * 30 },
                if (i % 2 == 0) .circle else .rect,
                2 + fi * 0.5,
            );
            b.radius = 15 + fi * 3;
            b.width = 30 + fi * 5;
            b.height = 30 + fi * 5;
            b.color = colors[i % colors.len];
            self.addBody(b);
        }
    }

    fn addBody(self: *RigidBodySim, body: RigidBody) void {
        if (self.count >= 128) return;
        self.bodies[self.count] = body;
        self.count += 1;
    }

    pub fn update(self: *RigidBodySim, dt: f32) void {
        // Apply gravity and integrate
        for (0..self.count) |i| {
            var b = &self.bodies[i];
            if (b.is_static) continue;
            if (self.gravity_on) {
                b.vel = b.vel.add(GRAVITY.scale(dt));
            }
            b.pos = b.pos.add(b.vel.scale(dt));
            b.angle += b.angular_vel * dt;
        }

        // Collision detection & resolution
        for (0..self.count) |i| {
            for (i + 1..self.count) |j| {
                self.resolveCollision(i, j);
            }
        }

        // Spawn on click
        if (rl.isMouseButtonPressed(.left)) {
            const mx = @as(f32, @floatFromInt(rl.getMouseX()));
            const my = @as(f32, @floatFromInt(rl.getMouseY()));
            var b = RigidBody.init(.{ .x = mx, .y = my }, .circle, 3);
            b.radius = 20;
            b.color = rl.Color.init(0, 228, 225, 255);
            self.addBody(b);
        }
        if (rl.isMouseButtonPressed(.right)) {
            const mx = @as(f32, @floatFromInt(rl.getMouseX()));
            const my = @as(f32, @floatFromInt(rl.getMouseY()));
            var b = RigidBody.init(.{ .x = mx, .y = my }, .rect, 5);
            b.width = 40;
            b.height = 40;
            b.color = rl.Color.init(255, 161, 0, 255);
            self.addBody(b);
        }

        if (rl.isKeyPressed(.g)) self.gravity_on = !self.gravity_on;
        if (rl.isKeyPressed(.c)) self.reset();
    }

    fn resolveCollision(self: *RigidBodySim, i: usize, j: usize) void {
        const a = &self.bodies[i];
        const b = &self.bodies[j];

        // Circle vs Circle
        if (a.shape == .circle and b.shape == .circle) {
            const delta = b.pos.sub(a.pos);
            const dist = delta.length();
            const min_dist = a.radius + b.radius;
            if (dist < min_dist and dist > 0.001) {
                const normal = delta.normalize();
                const overlap = min_dist - dist;

                // Separate
                const total_inv = a.inv_mass + b.inv_mass;
                if (total_inv > 0) {
                    self.bodies[i].pos = self.bodies[i].pos.sub(normal.scale(overlap * a.inv_mass / total_inv));
                    self.bodies[j].pos = self.bodies[j].pos.add(normal.scale(overlap * b.inv_mass / total_inv));
                }

                // Impulse
                const rel_vel = a.vel.sub(b.vel);
                const vel_along = rel_vel.dot(normal);
                if (vel_along > 0) return;
                const imp = -(1 + RESTITUTION) * vel_along / total_inv;
                self.bodies[i].vel = self.bodies[i].vel.add(normal.scale(imp * a.inv_mass));
                self.bodies[j].vel = self.bodies[j].vel.sub(normal.scale(imp * b.inv_mass));
            }
        }

        // Circle vs Rect (AABB approximation)
        if ((a.shape == .circle and b.shape == .rect) or (a.shape == .rect and b.shape == .circle)) {
            const ci: usize = if (a.shape == .circle) i else j;
            const ri: usize = if (a.shape == .circle) j else i;
            const circle = &self.bodies[ci];
            const rect = &self.bodies[ri];

            const half_w = rect.width / 2;
            const half_h = rect.height / 2;

            // Closest point on rect to circle center
            const cx = @max(rect.pos.x - half_w, @min(circle.pos.x, rect.pos.x + half_w));
            const cy = @max(rect.pos.y - half_h, @min(circle.pos.y, rect.pos.y + half_h));
            const closest = Vec2{ .x = cx, .y = cy };

            const delta = circle.pos.sub(closest);
            const dist = delta.length();

            if (dist < circle.radius and dist > 0.001) {
                const normal = delta.normalize();
                const overlap = circle.radius - dist;

                const total_inv = circle.inv_mass + rect.inv_mass;
                if (total_inv > 0) {
                    self.bodies[ci].pos = self.bodies[ci].pos.add(normal.scale(overlap * circle.inv_mass / total_inv));
                    self.bodies[ri].pos = self.bodies[ri].pos.sub(normal.scale(overlap * rect.inv_mass / total_inv));
                }

                const rel_vel = circle.vel.sub(rect.vel);
                const vel_along = rel_vel.dot(normal);
                if (vel_along > 0) return;
                const imp = -(1 + RESTITUTION) * vel_along / total_inv;
                self.bodies[ci].vel = self.bodies[ci].vel.add(normal.scale(imp * circle.inv_mass));
                self.bodies[ri].vel = self.bodies[ri].vel.sub(normal.scale(imp * rect.inv_mass));
            }
        }

        // Rect vs Rect (AABB)
        if (a.shape == .rect and b.shape == .rect) {
            const a_left = a.pos.x - a.width / 2;
            const a_right = a.pos.x + a.width / 2;
            const a_top = a.pos.y - a.height / 2;
            const a_bottom = a.pos.y + a.height / 2;
            const b_left = b.pos.x - b.width / 2;
            const b_right = b.pos.x + b.width / 2;
            const b_top = b.pos.y - b.height / 2;
            const b_bottom = b.pos.y + b.height / 2;

            const overlap_x = @min(a_right, b_right) - @max(a_left, b_left);
            const overlap_y = @min(a_bottom, b_bottom) - @max(a_top, b_top);

            if (overlap_x > 0 and overlap_y > 0) {
                const total_inv = a.inv_mass + b.inv_mass;
                if (total_inv == 0) return;

                var normal: Vec2 = undefined;
                var overlap: f32 = undefined;
                if (overlap_x < overlap_y) {
                    overlap = overlap_x;
                    normal = if (a.pos.x < b.pos.x) Vec2{ .x = -1, .y = 0 } else Vec2{ .x = 1, .y = 0 };
                } else {
                    overlap = overlap_y;
                    normal = if (a.pos.y < b.pos.y) Vec2{ .x = 0, .y = -1 } else Vec2{ .x = 0, .y = 1 };
                }

                self.bodies[i].pos = self.bodies[i].pos.add(normal.scale(overlap * a.inv_mass / total_inv));
                self.bodies[j].pos = self.bodies[j].pos.sub(normal.scale(overlap * b.inv_mass / total_inv));

                const rel_vel = a.vel.sub(b.vel);
                const vel_along = rel_vel.dot(normal);
                if (vel_along > 0) return;
                const imp = -(1 + RESTITUTION) * vel_along / total_inv;
                self.bodies[i].vel = self.bodies[i].vel.add(normal.scale(imp * a.inv_mass));
                self.bodies[j].vel = self.bodies[j].vel.sub(normal.scale(imp * b.inv_mass));
            }
        }
    }

    pub fn draw(self: *RigidBodySim) void {
        for (0..self.count) |i| {
            const b = &self.bodies[i];
            switch (b.shape) {
                .circle => rl.drawCircleV(b.pos.toRaylib(), b.radius, b.color),
                .rect => rl.drawRectangleV(
                    (Vec2{ .x = b.pos.x - b.width / 2, .y = b.pos.y - b.height / 2 }).toRaylib(),
                    .{ .x = b.width, .y = b.height },
                    b.color,
                ),
            }
        }

        rl.drawText(rl.textFormat("Bodies: %d", .{@as(c_int, @intCast(self.count))}), 10, 10, 20, .white);
        rl.drawText("Click: circle | Right: box | G: gravity | C: clear | ESC: menu", 10, 35, 16, .light_gray);
        if (!self.gravity_on) {
            rl.drawText("Gravity: OFF", 10, 55, 16, .yellow);
        }
    }

    pub fn reset(self: *RigidBodySim) void {
        self.count = 0;
        self.gravity_on = true;
        self.setupScene();
    }
};
