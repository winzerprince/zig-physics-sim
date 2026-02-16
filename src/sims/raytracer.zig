const rl = @import("raylib");
const Vec3 = @import("../core/vec3.zig").Vec3;

// ── Types ──────────────────────────────────────────────────────────────

const Material = struct {
    color: Vec3, // albedo
    emission: Vec3 = .{}, // emissive color
    roughness: f32 = 1.0, // 0 = mirror, 1 = diffuse
    metallic: f32 = 0.0, // 0 = dielectric, 1 = metal
};

const Sphere = struct {
    center: Vec3,
    radius: f32,
    mat: Material,
};

const Plane = struct {
    point: Vec3,
    normal: Vec3,
    mat: Material,
};

const HitInfo = struct {
    t: f32,
    pos: Vec3,
    normal: Vec3,
    mat: Material,
};

const Ray = struct {
    origin: Vec3,
    dir: Vec3,

    fn at(self: Ray, t: f32) Vec3 {
        return self.origin.add(self.dir.scale(t));
    }
};

// ── Scene ──────────────────────────────────────────────────────────────

const MAX_SPHERES = 16;
const MAX_PLANES = 4;

const Scene = struct {
    spheres: [MAX_SPHERES]Sphere = undefined,
    sphere_count: usize = 0,
    planes: [MAX_PLANES]Plane = undefined,
    plane_count: usize = 0,
    sky_color_top: Vec3 = .{ .x = 0.3, .y = 0.5, .z = 1.0 },
    sky_color_bot: Vec3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },

    fn addSphere(self: *Scene, s: Sphere) void {
        if (self.sphere_count < MAX_SPHERES) {
            self.spheres[self.sphere_count] = s;
            self.sphere_count += 1;
        }
    }

    fn addPlane(self: *Scene, p: Plane) void {
        if (self.plane_count < MAX_PLANES) {
            self.planes[self.plane_count] = p;
            self.plane_count += 1;
        }
    }

    fn skyColor(self: *const Scene, dir: Vec3) Vec3 {
        const t = 0.5 * (dir.normalize().y + 1.0);
        return Vec3.lerp(self.sky_color_bot, self.sky_color_top, t);
    }
};

// ── RNG (xoshiro128+) ─────────────────────────────────────────────────

const Rng = struct {
    s: [4]u32,

    fn init(seed: u64) Rng {
        var r: Rng = undefined;
        r.s[0] = @truncate(seed);
        r.s[1] = @truncate(seed >> 16);
        r.s[2] = @truncate(seed >> 32);
        r.s[3] = @truncate(seed >> 48);
        if (r.s[0] == 0) r.s[0] = 0xDEADBEEF;
        return r;
    }

    fn next(self: *Rng) u32 {
        const result = self.s[0] +% self.s[3];
        const t = self.s[1] << 9;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = (self.s[3] << 11) | (self.s[3] >> 21);
        return result;
    }

    /// Random float in [0, 1)
    fn float(self: *Rng) f32 {
        return @as(f32, @floatFromInt(self.next() >> 8)) / 16777216.0;
    }

    /// Random float in [-1, 1)
    fn floatSigned(self: *Rng) f32 {
        return self.float() * 2.0 - 1.0;
    }

    /// Random unit vector on hemisphere around normal
    fn hemisphereDir(self: *Rng, normal: Vec3) Vec3 {
        const v = self.randomOnSphere();
        if (v.dot(normal) < 0) return v.negate();
        return v;
    }

    fn randomOnSphere(self: *Rng) Vec3 {
        while (true) {
            const v = Vec3{ .x = self.floatSigned(), .y = self.floatSigned(), .z = self.floatSigned() };
            const len_sq = v.lengthSq();
            if (len_sq > 0.001 and len_sq <= 1.0) return v.normalize();
        }
    }
};

// ── Intersection ───────────────────────────────────────────────────────

fn hitSphere(ray: Ray, sphere: Sphere, t_min: f32, t_max: f32) ?HitInfo {
    const oc = ray.origin.sub(sphere.center);
    const a = ray.dir.dot(ray.dir);
    const half_b = oc.dot(ray.dir);
    const c = oc.dot(oc) - sphere.radius * sphere.radius;
    const disc = half_b * half_b - a * c;
    if (disc < 0) return null;

    const sqrt_disc = @sqrt(disc);
    var t = (-half_b - sqrt_disc) / a;
    if (t < t_min or t > t_max) {
        t = (-half_b + sqrt_disc) / a;
        if (t < t_min or t > t_max) return null;
    }

    const pos = ray.at(t);
    const normal = pos.sub(sphere.center).scale(1.0 / sphere.radius);
    return .{ .t = t, .pos = pos, .normal = normal, .mat = sphere.mat };
}

fn hitPlane(ray: Ray, plane: Plane, t_min: f32, t_max: f32) ?HitInfo {
    const denom = plane.normal.dot(ray.dir);
    if (@abs(denom) < 0.0001) return null;
    const t = plane.point.sub(ray.origin).dot(plane.normal) / denom;
    if (t < t_min or t > t_max) return null;

    const pos = ray.at(t);

    // Checkerboard pattern for ground plane
    const mat = blk: {
        var m = plane.mat;
        const fx = @floor(pos.x * 0.5);
        const fz = @floor(pos.z * 0.5);
        const checker = @mod(@as(i32, @intFromFloat(fx)) + @as(i32, @intFromFloat(fz)), 2);
        if (checker == 0) {
            m.color = m.color.scale(0.4);
        }
        break :blk m;
    };

    return .{ .t = t, .pos = pos, .normal = plane.normal, .mat = mat };
}

fn traceScene(scene: *const Scene, ray: Ray) ?HitInfo {
    var closest: ?HitInfo = null;
    var best_t: f32 = 1e30;

    for (0..scene.sphere_count) |i| {
        if (hitSphere(ray, scene.spheres[i], 0.001, best_t)) |hit| {
            best_t = hit.t;
            closest = hit;
        }
    }
    for (0..scene.plane_count) |i| {
        if (hitPlane(ray, scene.planes[i], 0.001, best_t)) |hit| {
            best_t = hit.t;
            closest = hit;
        }
    }
    return closest;
}

// ── Path Tracer ────────────────────────────────────────────────────────

const MAX_BOUNCES = 6;

fn pathTrace(scene: *const Scene, initial_ray: Ray, rng: *Rng) Vec3 {
    var ray = initial_ray;
    var throughput = Vec3{ .x = 1, .y = 1, .z = 1 };
    var color = Vec3{};

    for (0..MAX_BOUNCES) |_| {
        const hit = traceScene(scene, ray) orelse {
            // Sky
            color = color.add(throughput.mul(scene.skyColor(ray.dir)));
            break;
        };

        // Add emission
        color = color.add(throughput.mul(hit.mat.emission));

        // Russian roulette after bounce 2
        const p = throughput.maxComp();
        if (p < 0.01) break;

        // BRDF sampling: mix diffuse and specular based on roughness/metallic
        const diffuse_dir = hit.normal.add(rng.randomOnSphere()).normalize();
        const reflect_dir = ray.dir.reflect(hit.normal);
        const sample_dir = Vec3.lerp(reflect_dir, diffuse_dir, hit.mat.roughness).normalize();

        throughput = throughput.mul(hit.mat.color);

        ray = .{
            .origin = hit.pos.add(hit.normal.scale(0.001)),
            .dir = sample_dir,
        };
    }

    return color;
}

// ── Sim State ──────────────────────────────────────────────────────────

const RT_W = 400;
const RT_H = 300;
const TILE_SIZE = 16;

pub const RaytracerSim = struct {
    scene: Scene = .{},
    pixels: [RT_W * RT_H]rl.Color = undefined,
    accum: [RT_W * RT_H]Vec3 = undefined,
    sample_count: u32 = 0,
    texture: ?rl.Texture2D = null,
    image: ?rl.Image = null,
    screen_w: f32,
    screen_h: f32,
    camera_angle: f32 = 0, // horizontal rotation
    scene_idx: u8 = 0,
    rng: Rng = Rng.init(42),
    rendering: bool = true,

    pub fn init(w: f32, h: f32) RaytracerSim {
        var sim = RaytracerSim{ .screen_w = w, .screen_h = h };
        sim.setupScene(0);
        sim.clearAccum();
        sim.initTexture();
        return sim;
    }

    fn initTexture(self: *RaytracerSim) void {
        const img = rl.Image{
            .data = @ptrCast(&self.pixels),
            .width = RT_W,
            .height = RT_H,
            .mipmaps = 1,
            .format = .uncompressed_r8g8b8a8,
        };
        self.image = img;
        self.texture = rl.loadTextureFromImage(img) catch null;
    }

    fn setupScene(self: *RaytracerSim, idx: u8) void {
        self.scene = .{};
        self.scene_idx = idx;

        switch (idx) {
            0 => {
                // Cornell box-ish scene
                // Light (emissive sphere on top)
                self.scene.addSphere(.{
                    .center = .{ .x = 0, .y = 5, .z = -3 },
                    .radius = 2,
                    .mat = .{ .color = .{ .x = 1, .y = 1, .z = 1 }, .emission = .{ .x = 8, .y = 7, .z = 5 } },
                });
                // Red sphere
                self.scene.addSphere(.{
                    .center = .{ .x = -1.5, .y = 0.5, .z = -4 },
                    .radius = 0.5,
                    .mat = .{ .color = .{ .x = 0.9, .y = 0.1, .z = 0.1 }, .roughness = 0.3 },
                });
                // Blue sphere
                self.scene.addSphere(.{
                    .center = .{ .x = 0, .y = 0.5, .z = -3 },
                    .radius = 0.5,
                    .mat = .{ .color = .{ .x = 0.1, .y = 0.1, .z = 0.9 }, .roughness = 0.8 },
                });
                // Mirror sphere
                self.scene.addSphere(.{
                    .center = .{ .x = 1.5, .y = 0.5, .z = -4 },
                    .radius = 0.5,
                    .mat = .{ .color = .{ .x = 0.9, .y = 0.9, .z = 0.9 }, .roughness = 0.05, .metallic = 1 },
                });
                // Gold sphere
                self.scene.addSphere(.{
                    .center = .{ .x = 0.5, .y = 1, .z = -5 },
                    .radius = 1,
                    .mat = .{ .color = .{ .x = 1, .y = 0.8, .z = 0.3 }, .roughness = 0.2, .metallic = 1 },
                });
                // Ground
                self.scene.addPlane(.{
                    .point = .{ .x = 0, .y = 0, .z = 0 },
                    .normal = .{ .x = 0, .y = 1, .z = 0 },
                    .mat = .{ .color = .{ .x = 0.8, .y = 0.8, .z = 0.8 }, .roughness = 0.9 },
                });
            },
            1 => {
                // Many spheres scene
                self.scene.addSphere(.{
                    .center = .{ .x = 0, .y = 10, .z = -5 },
                    .radius = 3,
                    .mat = .{ .color = .{ .x = 1, .y = 1, .z = 1 }, .emission = .{ .x = 10, .y = 9, .z = 7 } },
                });
                // Grid of varied spheres
                var i: i32 = -2;
                while (i <= 2) : (i += 1) {
                    var j: i32 = -2;
                    while (j <= 0) : (j += 1) {
                        const fi = @as(f32, @floatFromInt(i));
                        const fj = @as(f32, @floatFromInt(j));
                        const hue = (@as(f32, @floatFromInt(i + 2)) + @as(f32, @floatFromInt(j + 2)) * 0.3) / 5.0;
                        self.scene.addSphere(.{
                            .center = .{ .x = fi * 1.2, .y = 0.4, .z = -4 + fj * 1.5 },
                            .radius = 0.4,
                            .mat = .{
                                .color = hsvToRgb(hue, 0.8, 0.9),
                                .roughness = 0.1 + @as(f32, @floatFromInt(i + 2)) * 0.2,
                                .metallic = if (j == 0) 1.0 else 0.0,
                            },
                        });
                    }
                }
                // Ground
                self.scene.addPlane(.{
                    .point = .{ .x = 0, .y = 0, .z = 0 },
                    .normal = .{ .x = 0, .y = 1, .z = 0 },
                    .mat = .{ .color = .{ .x = 0.7, .y = 0.7, .z = 0.75 }, .roughness = 0.5 },
                });
            },
            else => self.setupScene(0),
        }
    }

    fn clearAccum(self: *RaytracerSim) void {
        for (0..RT_W * RT_H) |i| {
            self.accum[i] = .{};
            self.pixels[i] = rl.Color.init(0, 0, 0, 255);
        }
        self.sample_count = 0;
    }

    pub fn update(self: *RaytracerSim, _: f32) void {
        // Controls
        if (rl.isKeyPressed(.tab)) {
            self.scene_idx = (self.scene_idx + 1) % 2;
            self.setupScene(self.scene_idx);
            self.clearAccum();
        }
        if (rl.isKeyPressed(.space)) self.rendering = !self.rendering;
        if (rl.isKeyPressed(.r)) self.clearAccum();

        // Camera rotation
        var cam_changed = false;
        if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) {
            self.camera_angle -= 0.02;
            cam_changed = true;
        }
        if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) {
            self.camera_angle += 0.02;
            cam_changed = true;
        }
        if (cam_changed) self.clearAccum();

        if (!self.rendering) return;

        // Render some samples this frame (progressive)
        const samples_per_frame: u32 = 1;
        const aspect = @as(f32, RT_W) / @as(f32, RT_H);
        const fov_scale: f32 = 1.0; // tan(fov/2) roughly

        // Camera
        const cam_pos = Vec3{ .x = @sin(self.camera_angle) * 2, .y = 1.5, .z = @cos(self.camera_angle) * 2 };
        const look_at = Vec3{ .x = 0, .y = 0.5, .z = -3 };
        const cam_fwd = look_at.sub(cam_pos).normalize();
        const world_up = Vec3{ .x = 0, .y = 1, .z = 0 };
        const cam_right = cam_fwd.cross(world_up).normalize();
        const cam_up = cam_right.cross(cam_fwd);

        for (0..samples_per_frame) |_| {
            for (0..RT_H) |py| {
                for (0..RT_W) |px| {
                    const fpx = @as(f32, @floatFromInt(px));
                    const fpy = @as(f32, @floatFromInt(py));

                    // Jittered UV
                    const u = ((fpx + self.rng.float()) / @as(f32, RT_W) * 2.0 - 1.0) * aspect * fov_scale;
                    const v = (1.0 - (fpy + self.rng.float()) / @as(f32, RT_H) * 2.0) * fov_scale;

                    const dir = cam_fwd.add(cam_right.scale(u)).add(cam_up.scale(v)).normalize();
                    const ray = Ray{ .origin = cam_pos, .dir = dir };
                    const color = pathTrace(&self.scene, ray, &self.rng);

                    const idx = py * RT_W + px;
                    self.accum[idx] = self.accum[idx].add(color);
                }
            }
            self.sample_count += 1;
        }

        // Tonemap and write to pixel buffer
        const inv_n = 1.0 / @as(f32, @floatFromInt(self.sample_count));
        for (0..RT_W * RT_H) |i| {
            const c = self.accum[i].scale(inv_n);
            // Reinhard tonemap + gamma
            self.pixels[i] = rl.Color.init(
                toU8(gammaCorrect(c.x / (c.x + 1.0))),
                toU8(gammaCorrect(c.y / (c.y + 1.0))),
                toU8(gammaCorrect(c.z / (c.z + 1.0))),
                255,
            );
        }

        // Update GPU texture
        if (self.texture) |tex| {
            rl.updateTexture(tex, @ptrCast(&self.pixels));
        }
    }

    pub fn draw(self: *RaytracerSim) void {
        if (self.texture) |tex| {
            // Scale to fit screen
            const scale_x = self.screen_w / @as(f32, RT_W);
            const scale_y = self.screen_h / @as(f32, RT_H);
            const s = @min(scale_x, scale_y);
            const ox = (self.screen_w - @as(f32, RT_W) * s) / 2;
            const oy = (self.screen_h - @as(f32, RT_H) * s) / 2;

            rl.drawTextureEx(tex, .{ .x = ox, .y = oy }, 0, s, .white);
        }

        // HUD
        rl.drawText(rl.textFormat("Samples: %d", .{@as(c_int, @intCast(self.sample_count))}), 10, 10, 20, .white);
        rl.drawText(rl.textFormat("Scene: %d/2", .{@as(c_int, @intCast(self.scene_idx + 1))}), 10, 35, 20, .white);
        const status = if (self.rendering) "Rendering..." else "PAUSED";
        rl.drawText(@ptrCast(status), 10, 60, 16, if (self.rendering) .green else .yellow);
        rl.drawText("A/D: rotate camera | TAB: scene | SPACE: pause | R: reset | ESC: menu", 10, self.intFromFloat(self.screen_h) - 25, 16, .light_gray);
    }

    fn intFromFloat(_: *RaytracerSim, v: f32) c_int {
        return @intFromFloat(v);
    }

    pub fn deinit(self: *RaytracerSim) void {
        if (self.texture) |tex| {
            rl.unloadTexture(tex);
            self.texture = null;
        }
    }
};

// ── Helpers ────────────────────────────────────────────────────────────

fn toU8(v: f32) u8 {
    const clamped = @max(0, @min(1, v));
    return @intFromFloat(clamped * 255.0);
}

fn gammaCorrect(v: f32) f32 {
    return @sqrt(@max(0, v));
}

fn hsvToRgb(h: f32, s: f32, v: f32) Vec3 {
    const hh = @mod(h * 6.0, 6.0);
    const i = @as(u32, @intFromFloat(@floor(hh)));
    const f = hh - @floor(hh);
    const p = v * (1.0 - s);
    const q = v * (1.0 - s * f);
    const t = v * (1.0 - s * (1.0 - f));
    return switch (i % 6) {
        0 => Vec3{ .x = v, .y = t, .z = p },
        1 => Vec3{ .x = q, .y = v, .z = p },
        2 => Vec3{ .x = p, .y = v, .z = t },
        3 => Vec3{ .x = p, .y = q, .z = v },
        4 => Vec3{ .x = t, .y = p, .z = v },
        5 => Vec3{ .x = v, .y = p, .z = q },
        else => Vec3{ .x = v, .y = v, .z = v },
    };
}
