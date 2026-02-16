const rl = @import("raylib");
const ParticleSim = @import("sims/particles.zig").ParticleSim;
const OrbitalSim = @import("sims/orbital.zig").OrbitalSim;
const RigidBodySim = @import("sims/rigid_body.zig").RigidBodySim;
const RaytracerSim = @import("sims/raytracer.zig").RaytracerSim;
const Vec2 = @import("core/vec2.zig").Vec2;

const SCREEN_W = 1200;
const SCREEN_H = 800;

const Mode = enum {
    menu,
    particles,
    orbital,
    rigid_body,
    raytracer,
};

pub fn main() !void {
    rl.initWindow(SCREEN_W, SCREEN_H, "⚛ Zig Physics Simulator");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var mode: Mode = .menu;
    var particle_sim = ParticleSim.init(SCREEN_W, SCREEN_H);
    var orbital_sim = OrbitalSim.init(SCREEN_W, SCREEN_H);
    var rigid_sim = RigidBodySim.init(SCREEN_W, SCREEN_H);
    var rt_sim = RaytracerSim.init(SCREEN_W, SCREEN_H);
    defer rt_sim.deinit();

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();

        switch (mode) {
            .menu => {
                if (rl.isKeyPressed(.one)) mode = .particles;
                if (rl.isKeyPressed(.two)) mode = .orbital;
                if (rl.isKeyPressed(.three)) mode = .rigid_body;
                if (rl.isKeyPressed(.four)) mode = .raytracer;
            },
            .particles => {
                // Input
                if (rl.isMouseButtonDown(.left)) {
                    const mx = @as(f32, @floatFromInt(rl.getMouseX()));
                    const my = @as(f32, @floatFromInt(rl.getMouseY()));
                    particle_sim.spawn(.{ .x = mx, .y = my }, .{ .x = 0, .y = 0 }, 4);
                }
                if (rl.isMouseButtonPressed(.right)) {
                    const mx = @as(f32, @floatFromInt(rl.getMouseX()));
                    const my = @as(f32, @floatFromInt(rl.getMouseY()));
                    particle_sim.spawnBurst(.{ .x = mx, .y = my }, 30);
                }
                if (rl.isKeyPressed(.g)) particle_sim.gravity_on = !particle_sim.gravity_on;
                if (rl.isKeyPressed(.c)) particle_sim.clear();
                if (rl.isKeyPressed(.escape)) mode = .menu;

                particle_sim.update(dt);
            },
            .orbital => {
                if (rl.isKeyPressed(.r)) orbital_sim.reset();
                if (rl.isKeyPressed(.escape)) mode = .menu;

                orbital_sim.update(dt);
            },
            .rigid_body => {
                if (rl.isKeyPressed(.escape)) mode = .menu;
                rigid_sim.update(dt);
            },
            .raytracer => {
                if (rl.isKeyPressed(.escape)) {
                    mode = .menu;
                } else {
                    rt_sim.update(dt);
                }
            },
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.init(15, 15, 25, 255));

        switch (mode) {
            .menu => drawMenu(),
            .particles => particle_sim.draw(),
            .orbital => orbital_sim.draw(),
            .rigid_body => rigid_sim.draw(),
            .raytracer => rt_sim.draw(),
        }
    }
}

fn drawMenu() void {
    const cx = SCREEN_W / 2;
    const title = "ZIG PHYSICS SIMULATOR";
    const tw = rl.measureText(title, 40);
    rl.drawText(title, cx - @divFloor(tw, 2), 100, 40, rl.Color.init(0, 228, 225, 255));

    const subtitle = "Choose a simulation:";
    const sw = rl.measureText(subtitle, 20);
    rl.drawText(subtitle, cx - @divFloor(sw, 2), 170, 20, .light_gray);

    const items = [_]struct { key: []const u8, label: []const u8, desc: []const u8 }{
        .{ .key = "[1]", .label = "Particle Sandbox", .desc = "Spawn particles, gravity, collisions, bursts" },
        .{ .key = "[2]", .label = "Orbital Mechanics", .desc = "N-body gravity, planetary orbits, fly a rocket" },
        .{ .key = "[3]", .label = "Rigid Body Physics", .desc = "Circles & boxes, collisions, stacking" },
        .{ .key = "[4]", .label = "Ray Tracer", .desc = "Path-traced global illumination, reflections, soft shadows" },
    };

    for (items, 0..) |item, i| {
        const y: c_int = 250 + @as(c_int, @intCast(i)) * 100;

        // Key badge
        rl.drawText(@ptrCast(item.key), cx - 200, y, 30, .yellow);
        // Label
        rl.drawText(@ptrCast(item.label), cx - 130, y, 28, .white);
        // Description
        rl.drawText(@ptrCast(item.desc), cx - 130, y + 35, 16, .gray);
    }

    rl.drawText("ESC to quit | Select with number keys", cx - 180, SCREEN_H - 60, 16, rl.Color.init(100, 100, 100, 255));
}
