# Zig Physics Simulator ⚛

A multi-mode physics simulator written in Zig with raylib for rendering.

## Simulations

1. **Particle Sandbox** — Spawn particles with gravity, wall bouncing, and inter-particle collisions
2. **Orbital Mechanics** — N-body gravitational simulation with planets and a controllable rocket
3. **Rigid Body Physics** — Circles and rectangles with AABB collision detection and impulse resolution

## Building

```bash
zig build run
```

## Controls

### Menu
- `1/2/3` — Select simulation
- `ESC` — Quit

### Particle Sandbox
- **Click** — Spawn particle
- **Right-click** — Particle burst
- `G` — Toggle gravity
- `C` — Clear all
- `ESC` — Back to menu

### Orbital Mechanics
- **WASD / Arrows** — Fly the rocket
- **Scroll** — Zoom in/out
- `+/-` — Speed up/slow down time
- `R` — Reset
- `ESC` — Back to menu

### Rigid Body
- **Click** — Spawn circle
- **Right-click** — Spawn box
- `G` — Toggle gravity
- `C` — Clear & reset
- `ESC` — Back to menu

## Tech

- **Language:** Zig 0.15+
- **Rendering:** raylib (via raylib-zig bindings)
- **Physics:** Hand-rolled — Euler integration, elastic collisions, N-body gravity
