//! Handles procedural generation logic for the game.
const std = @import("std");
const logger = @import("logger.zig");
const memory = @import("memory.zig");
const seeding = @import("seeding.zig");
const world = @import("world.zig");

const POW_2_64 = seeding.POW_2_64;
const Seed = seeding.Seed;
const Sprite = world.Sprite;

/// Generates an initial block for seeding.
pub inline fn generate_initial_block(moisture: f64, density: f64, height: f64) Sprite {
    _ = moisture;
    _ = height;

    if (density < 0.35) return .none;
    // if (density < 0.4) return .spiral_plant;
    // if (density < 0.45) return .green_stone;
    // if (density < 0.5) return .seagreen_stone;
    // if (density < 0.55) return .blue_stone;
    // if (density < 0.65) return .stone;
    // if (density < 0.8) return .iron;
    // if (density < 0.88) return .silver;
    // if (density < 0.9) return .gold;
    return .stone;
}

// TODO improve (pretty bad currently)
/// Generates an initial set of blocks for depth 3.
/// Acts as the "parent" from which all blocks at higher depths ("more zoomed in") get generated from.
pub fn get_cave_density(seed: Seed, world_x: u64, world_y: u64) f64 {
    const scale = 0.05; // Adjust for cave size
    const x = @as(f64, @floatFromInt(world_x)) * scale;
    const y = @as(f64, @floatFromInt(world_y)) * scale;

    const ix = @as(i64, @intFromFloat(@floor(x)));
    const iy = @as(i64, @intFromFloat(@floor(y)));
    const fx = x - @as(f64, @floatFromInt(ix));
    const fy = y - @as(f64, @floatFromInt(iy));

    var dist1: f64 = 10.0; // Closest point
    var dist2: f64 = 10.0; // Second closest point

    // Check 3x3 neighborhood of cells
    var ox: i64 = -1;
    while (ox <= 1) : (ox += 1) {
        var oy: i64 = -1;
        while (oy <= 1) : (oy += 1) {
            const point = get_cell_point(seed, ix + ox, iy + oy);

            // Calculate Manhattan distance (|dx| + |dy|)
            // Manhattan creates "sharp/diamond" shapes.
            // Use (dx*dx + dy*dy) for "bubble/round" sponge caves.
            const dx = @as(f64, @floatFromInt(ox)) + point[0] - fx;
            const dy = @as(f64, @floatFromInt(oy)) + point[1] - fy;
            const d = @abs(dx) + @abs(dy);

            if (d < dist1) {
                dist2 = dist1;
                dist1 = d;
            } else if (d < dist2) {
                dist2 = d;
            }
        }
    }

    // F2 - F1 creates a "cellular boundary" look (the walls of a sponge).
    var density = dist2 - dist1;

    // Applying a high-contrast curve makes the "tunnels" wide and "walls" thin/sharp!
    density = std.math.pow(f64, density, 0.75); // Expands the corridors
    return @max(0.0, @min(1.0, density));
}

/// Returns a value between 0-1, used as a terrain starting point for the default depth (D = 3).
pub fn get_density_value(world_seed: Seed, x: u64, y: u64, cell_size: f64) f64 {
    const fx = @as(f64, @floatFromInt(x));
    const fy = @as(f64, @floatFromInt(y));

    // Configuration
    const h_stretch: f64 = 1.3;
    const octaves: usize = 3;
    const persistence: f64 = 0.5;
    const lacunarity: f64 = 2.0;

    // FbM warping
    var warp_x: f64 = 0;
    var warp_y: f64 = 0;
    var amp: f64 = 10.0; // Warp intensity
    var freq: f64 = 1.0 / (cell_size * 2.0);

    for (0..octaves) |_| {
        const h: memory.v2f64 = seeding.ChaCha12.hash_2d(f64, world_seed, @as(u64, @intFromFloat(fx * freq + 1e6)), @as(u64, @intFromFloat(fy * freq)));
        warp_x += (h[0] - 0.5) * amp;
        warp_y += (h[1] - 0.5) * amp;
        amp *= persistence;
        freq *= lacunarity;
    }

    const wx = fx + warp_x;
    const wy = fy + warp_y;

    // Stacked Worley logic
    const cell_w = cell_size * h_stretch;
    const cell_h = cell_size;

    const cx = @floor(wx / cell_w);
    const cy = @floor(wy / cell_h);

    var min_dist: f64 = 1e10;

    var ox: i32 = -1;
    while (ox <= 1) : (ox += 1) {
        var oy: i32 = -1;
        while (oy <= 1) : (oy += 1) {
            const cur_cx_i = @as(i64, @intFromFloat(cx)) + ox;
            const cur_cy_i = @as(i64, @intFromFloat(cy)) + oy;

            const cur_cx_u = @as(u64, @bitCast(cur_cx_i));
            const cur_cy_u = @as(u64, @bitCast(cur_cy_i));

            const offset = seeding.ChaCha12.hash_2d(f64, world_seed, cur_cx_u, cur_cy_u);

            const px = (@as(f64, @floatFromInt(cur_cx_i)) + offset[0]) * cell_w;
            const py = (@as(f64, @floatFromInt(cur_cy_i)) + offset[1]) * cell_h;

            // Manhattan distance for non-circularity
            const dx = @abs(wx - px) / h_stretch;
            const dy = @abs(wy - py);
            const dist = dx + dy;

            if (dist < min_dist) min_dist = dist;
        }
    }

    var density = min_dist / cell_size; // remap density
    density = std.math.pow(f64, density, 0.8); // idk
    return @min(1.0, density);
}

/// Simply calls `hash_2d`.
fn get_cell_point(seed: Seed, cx: i64, cy: i64) memory.v2f64 {
    return seeding.ChaCha12.hash_2d(f64, seed, @bitCast(cx), @bitCast(cy));
}

/// Multiplies a float by 2**64, returning an integer x such that a random u64 value has its probability to be less than x equal to the chance variable.
pub inline fn odds_num(chance: comptime_float) u64 {
    return @intFromFloat(chance * POW_2_64);
}

// UNUSED AREA

pub fn get_value_noise(base_seed: seeding.Seed, world_x: f64, world_y: f64) f64 {
    const x0 = @floor(world_x);
    const y0 = @floor(world_y);

    const fx = world_x - x0;
    const fy = world_y - y0;

    // Get 4 random values for the corners
    const v00 = get_random_value(base_seed, @intFromFloat(x0), @intFromFloat(y0));
    const v10 = get_random_value(base_seed, @intFromFloat(x0 + 1), @intFromFloat(y0));
    const v01 = get_random_value(base_seed, @intFromFloat(x0), @intFromFloat(y0 + 1));
    const v11 = get_random_value(base_seed, @intFromFloat(x0 + 1), @intFromFloat(y0 + 1));

    // Smooth the coordinates
    const u = fade(fx);
    const v = fade(fy);

    // Bilinear interpolation
    return lerp(lerp(v00, v10, u), lerp(v01, v11, u), v);
}

/// Linearly interpolates between a and b.
inline fn lerp(a: f64, b: f64, time: f64) f64 {
    return a + time * (b - a);
}

/// Smootherstep formula.
inline fn fade(t: f64) f64 {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

/// Returns a random deterministic value based on an X and Y value.
fn get_random_value(seed: Seed, x: u64, y: u64) f64 {
    return @as(f64, @floatFromInt(
        seeding.ChaCha12.hash_2d(seed, x, y),
    )) * (1.0 / POW_2_64);
}

/// Simple noise for testing. Unused.
pub fn get_test_noise(seed: Seed, x: f64, y: f64) f64 {
    _ = .{ x, y };
    var prng = seeding.ChaCha12.init(seed);
    return @as(f64, @floatFromInt(prng.next() & 127)) / 128;
}
