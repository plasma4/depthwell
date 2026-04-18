//! Handles procedural generation logic for the game.
const std = @import("std");
const is_debug = @import("builtin").mode == .Debug;
const types = @import("types.zig");
const logger = @import("logger.zig");
const memory = @import("memory.zig");
const seeding = @import("seeding.zig");
const world = @import("world.zig");

/// Represents 2^32.
const POW_2_32 = 4294967296;
const POW_2_64 = seeding.POW_2_64;
const SPAN = memory.SPAN;

const EdgeFlags = types.EdgeFlags;
const odds_num = seeding.odds_num;
const FastHash = seeding.FastHash;
const Seed = seeding.Seed;
const Sprite = world.Sprite;
const v2f64 = memory.v2f64;
const v2u64 = memory.v2u64;

pub var procedural_cell_size: f64 = 1.0;
pub var fbm_power: f64 = 1.0;
pub var density_min: f64 = 0.32;
pub var density_max: f64 = 0.9;
/// Determines whether to use a heatmap or not for base terrain. Ignored if `is_debug` is false.
pub var USE_BASE_HEATMAP = false;
/// Determines whether to use a heatmap or not for ore generation. Ignored if `is_debug` is false.
pub var USE_ORE_HEATMAP = false;

/// Options for the FBM+Worley implementation.
const TerrainOptions = struct {
    cell_size: comptime_float,
    fbm_shift_size: comptime_float,
    horizontally_wide: bool = false,
    use_f2_f1: bool = true,
};

/// Base data for sprites
const BaseTerrainData = struct {
    sprite: Sprite,
    moisture: f32,
    density: f32,
};

/// Generates a block for seeding (based on previous procedural generation logic).
/// The terms moisture/density are used extremely loosely here.
pub inline fn generate_sprite_from_values(moisture: f64, density: f64) Sprite {
    if (is_debug and USE_BASE_HEATMAP) return @enumFromInt(256 + @as(u20, @intFromFloat(density * 256.0))); // sprite IDs from 256-512 create a neat little heatmap

    if (density <= 0.08 and moisture >= 0.3 and moisture <= 0.4) {
        return .strange_stone;
    } else if (density <= density_min or density >= density_max) {
        return if (moisture >= 0.93 and moisture <= 0.99) .strange_stone_other else .none;
    }

    if (moisture >= 0.88 and moisture <= 0.92) return .lava_stone;
    if (moisture <= 0.5) return .stone;
    if (moisture <= 0.53 and density <= 0.5) return .green_stone;
    if (moisture <= 0.58 and density >= 0.4) return .seagreen_stone;
    if (moisture <= 0.65 and density >= 0.6) return .blue_stone;
    return .stone;
}

/// Returns a base sprite type. Does 3 passes:
///
/// 1. Generate an initial terrain density+moisture value using the seed vectors.
/// 2. Generate a block from those values.
/// 3. Generates larger structures with FBM Worley and valid placement checks.
pub fn get_base_sprite_type(vec1: v2u64, vec2: v2u64, chunk_x: u32, chunk_y: u32, block_x: u32, block_y: u32) BaseTerrainData {
    const moisture = get_fbm_worley_value( // acts as a biome
        vec2,
        chunk_x * 16 + block_x,
        chunk_y * 16 + block_y,
        .{
            .cell_size = 400.0, // very LARGE cells for biome generation
            .fbm_shift_size = 160.0,
            .horizontally_wide = false,
        },
    );
    const density = get_fbm_worley_value(
        vec1,
        chunk_x * 16 + block_x,
        chunk_y * 16 + block_y,
        .{
            .cell_size = 80.0, // smaller cells for cave terrain
            .fbm_shift_size = 24.0,
            .horizontally_wide = true,
        },
    );

    const sprite = generate_sprite_from_values(moisture, density);

    // drawing sprite change in WGSL now after tile unpacking, quite silly to be here
    // if (sprite == .stone) {
    //     if (block_y % 2 == 0) {
    //         sprite = if (block_x == 0) .stone else ._stone;
    //     } else {
    //         sprite = if (block_x == 0) .__stone else .___stone;
    //     }
    // }
    return .{
        .sprite = sprite,
        .moisture = moisture,
        .density = density,
    };
}

/// Returns a value between 0-1, used as a terrain starting point for the default depth (D = 3).
/// Acts as the "parent" from which all blocks at higher depths ("more zoomed in") get generated from.
/// This function is called 256 times per chunk and is performance-sensitive.
///
/// This function uses fractal brownian motion with value noise in an initial pass for domain warping,
/// then Worley noise to generate terrain.
fn get_fbm_worley_value(seed_vector: v2u64, x: u32, y: u32, comptime options: TerrainOptions) f32 {
    const fx = @as(f32, @floatFromInt(x));
    const fy = @as(f32, @floatFromInt(if (options.horizontally_wide) y * 2 else y)); // scaled Y

    // buncha config options
    const h_stretch = 1.5;
    const fbm_octaves = 3; // amount of octaves to use for FBM
    var warp_x: f32 = 0; // 32-bit means possible performance gains from SIMD and stuff, possibly
    var warp_y: f32 = 0;

    var freq: u64 = 1;
    var amp = options.fbm_shift_size * @as(f32, @floatCast(fbm_power));
    if (amp > 0) {
        // FBM warping
        inline for (0..fbm_octaves) |_| {
            const noise = get_dual_value_noise(seed_vector, x * freq, y * freq); // make shifting smooth!
            warp_x += noise[0] * amp;
            warp_y += noise[1] * amp;
            amp *= 0.5;
            freq *%= 2;
        }
    }

    const cell_size = options.cell_size * @as(f32, @floatCast(procedural_cell_size));
    const wx = fx + warp_x;
    const wy = fy + warp_y;
    const cell_w = cell_size * h_stretch;

    const cx_f = @floor(wx / cell_w);
    const cy_f = @floor(wy / cell_size);
    const cx_i = @as(i64, @intFromFloat(cx_f));
    const cy_i = @as(i64, @intFromFloat(cy_f));

    var d1_sq = std.math.inf(f32); // highest possible values
    var d2_sq = std.math.inf(f32);

    // Worley search
    inline for (.{ -1, 0, 1 }) |ox| {
        inline for (.{ -1, 0, 1 }) |oy| {
            const cur_x = @as(u64, @bitCast(cx_i + ox));
            const cur_y = @as(u64, @bitCast(cy_i + oy));

            // Hash once for both offsets
            const h = FastHash.hash_2d(seed_vector, cur_x, cur_y);
            const off_x = @as(f32, @floatFromInt(h % POW_2_32)) / POW_2_32;
            const off_y = @as(f32, @floatFromInt(h / POW_2_32)) / POW_2_32;

            const px = (@as(f32, @floatFromInt(cx_i + ox)) + off_x) * cell_w;
            const py = (@as(f32, @floatFromInt(cy_i + oy)) + off_y) * cell_size;

            const dx = wx - px;
            const dy = wy - py;
            const dist_sq = dx * dx + dy * dy;

            if (dist_sq < d1_sq) {
                d2_sq = d1_sq;
                d1_sq = dist_sq;
            } else if (dist_sq < d2_sq) {
                d2_sq = dist_sq;
            }
        }
    }

    if (options.use_f2_f1) {
        return @min((@sqrt(d2_sq) - @sqrt(d1_sq)) / cell_size, 1.0);
    } else {
        return @min(@sqrt(d1_sq) / cell_size, 1.0);
    }
}

/// Returns two independent noise values (32-bit float) based on the classic Value Noise algorithm.
fn get_dual_value_noise(seed: v2u64, x: u64, y: u64) @Vector(2, f32) {
    const scale: f32 = 16.0;
    const fx_raw = @as(f32, @floatFromInt(x)) / scale;
    const fy_raw = @as(f32, @floatFromInt(y)) / scale;

    const x0 = @as(u64, @floor(fx_raw));
    const y0 = @as(u64, @floor(fy_raw));
    const tx = fx_raw - @floor(fx_raw);
    const ty = fy_raw - @floor(fy_raw);

    // Fade curves
    const u = tx * tx * tx * (tx * (tx * 6 - 15) + 10);
    const v = ty * ty * ty * (ty * (ty * 6 - 15) + 10);

    const h00 = FastHash.hash_2d(seed, x0, y0); // ChaCha12 is too slow ):
    const h10 = FastHash.hash_2d(seed, x0 +% 1, y0);
    const h01 = FastHash.hash_2d(seed, x0, y0 +% 1);
    const h11 = FastHash.hash_2d(seed, x0 +% 1, y0 +% 1);

    var res: @Vector(2, f32) = .{ 0, 0 };
    inline for (0..2) |i| {
        const shift = @as(u6, @intCast(i * 32));
        const v00 = @as(f32, @floatFromInt(@as(u32, @truncate(h00 >> shift)))) / POW_2_32;
        const v10 = @as(f32, @floatFromInt(@as(u32, @truncate(h10 >> shift)))) / POW_2_32;
        const v01 = @as(f32, @floatFromInt(@as(u32, @truncate(h01 >> shift)))) / POW_2_32;
        const v11 = @as(f32, @floatFromInt(@as(u32, @truncate(h11 >> shift)))) / POW_2_32;

        const nx0 = v00 + u * (v10 - v00);
        const nx1 = v01 + u * (v11 - v01);
        res[i] = nx0 + v * (nx1 - nx0);
    }
    return res;
}

/// Generates ores over certain types of blocks, returning a sprite type (possibly changed to an ore type).
/// Continues from steps 1-3 in `get_base_sprite_type()`.
///
/// 4. Disperses ores using Worley noise. Assumes that `is_stone()` was checked before calling.
pub fn add_ores(
    base_data: BaseTerrainData,
    seed_vector_1: v2u64,
    seed_vector_2: v2u64,
    seed_vector_3: v2u64,
    seed_vector_4: v2u64,
    x: u32,
    y: u32,
) Sprite {
    var sprite = base_data.sprite;

    // Generate new density for ores: the seed vector should be different from the `get_fbm_worley_density()` vector.
    const v1 = get_fbm_worley_value( // smaller cells, less FBM variation
        seed_vector_1,
        x,
        y,
        .{
            .cell_size = 20.0,
            .fbm_shift_size = 30.0,
            .horizontally_wide = false,
            .use_f2_f1 = false,
        },
    );
    const v2 = get_fbm_worley_value( // larger cells, much more FBM variation
        seed_vector_2,
        x,
        y,
        .{
            .cell_size = 36.0,
            .fbm_shift_size = 60.0,
            .horizontally_wide = false,
            .use_f2_f1 = false,
        },
    );

    // sprite IDs from 256-512 create a neat little heatmap (using only the first value), overriding normal ore logic
    if (is_debug and USE_ORE_HEATMAP) return @enumFromInt(256 + @as(u20, @intFromFloat(v1 * 256.0)));

    if (base_data.density >= 0.45 and base_data.density <= 0.65) {
        // Generate various ore types
        sprite = select_sprite(
            .{ sprite, .copper },
            true,
            .{ v2, 0.0, 0.2 },
        );
        if (sprite == .copper or v2 >= 0.7) return sprite;

        sprite = select_sprite(
            .{ sprite, .iron },
            true,
            .{ v1, 0.55, 0.65 },
        );
        if (sprite == .iron and base_data.sprite != .strange_stone) return sprite;

        sprite = select_sprite(
            .{ sprite, .silver },
            base_data.density <= 0.55,
            .{ v1, 0.2, 0.26 },
        );
        sprite = select_sprite(
            .{ sprite, .silver },
            base_data.sprite == .strange_stone,
            .{ v1, 0.18, 0.2 },
        );
        if (sprite == .iron or sprite == .silver) return sprite;

        sprite = select_sprite(
            .{ sprite, .gold },
            base_data.density >= 0.62 or (base_data.density >= 0.58 and base_data.sprite == .lava_stone),
            .{ v2, 0.3, 0.4 },
        );
        if (sprite == .gold) return sprite;
    } else {
        // Logic for generating gems
        const gem_v2_bound: f32 = if (sprite == .strange_stone_other) 0.35 else 0.25;
        if (base_data.density >= 0.3 and base_data.density <= 0.5 and v2 >= 0.1 and v2 <= gem_v2_bound) {
            const random_value = FastHash.hash_2d(seed_vector_3, @intCast(x), @intCast(y));

            const base_odds = 0.1;
            if (random_value <= odds_num(base_odds)) {
                const v3 = get_fbm_worley_value(
                    seed_vector_4,
                    y,
                    x,
                    .{
                        .cell_size = 35.0,
                        .fbm_shift_size = 0.0,
                        .horizontally_wide = false,
                        .use_f2_f1 = false,
                    },
                );

                sprite = select_sprite(
                    .{ sprite, .amethyst },
                    v3 <= 0.4 and random_value <= odds_num(0.4 * base_odds),
                    null,
                );
                if (sprite == .amethyst) return sprite;

                sprite = select_sprite(
                    .{ sprite, .sapphire },
                    v3 >= 0.75 and random_value <= odds_num(0.65 * base_odds),
                    null,
                );
                if (sprite == .sapphire) return sprite;

                sprite = select_sprite(
                    .{ sprite, .emerald },
                    v3 >= 0.45 and v3 >= 0.65 and random_value <= odds_num(0.86 * base_odds),
                    null,
                );
                if (sprite == .emerald) return sprite;

                sprite = select_sprite(
                    .{ sprite, .ruby },
                    v3 >= 0.22 and v3 >= 0.3 and random_value <= odds_num(1.0 * base_odds),
                    null,
                );
                if (sprite == .ruby) return sprite;
            }
        }
    }

    return sprite;
}

/// Represents 3 values: `v`, `min`, and `max`.
const ValueRange = struct { f32, f32, f32 };

/// Represents 2 sprites: `old_sprite` and `new_sprite`.
const SpritePair = struct { Sprite, Sprite };

/// Reads like a sentence: returns the new sprite if condition holds and v is between min and max, but the old sprite otherwise.
///
/// Technical definition: returns the second `Sprite` in the pair if `condition` is satisfied `range[0]` falls within `range[1]`, and the first `Sprite` otherwise.
///
/// Example usage:
/// ```zig
/// // Returns iron if density is larger than 0.6 AND my_value is between 0.6 and 0.7 (inclusive), and stone otherwise.
/// Sprite sprite = cw(.iron, my_density >= 0.6, my_value, 0.6, 0.7, .stone);
/// ```
pub inline fn select_sprite(sprites: SpritePair, condition: bool, range: ?ValueRange) Sprite {
    const old_sprite = sprites[0];
    const new_sprite = sprites[1];
    if (range) |r| {
        const v = r[0];
        const min = r[1];
        const max = r[2];
        return if (condition and v >= min and v <= max) new_sprite else old_sprite;
    } else {
        return if (condition) new_sprite else old_sprite;
    }
}

/// Returns true if `v` is between `min` and `max` (inclusive).
pub inline fn is_within(v: f32, min: comptime_float, max: comptime_float) bool {
    if (max <= min) @compileError("Maximum value must be larger than minimum value.");
    return v >= min and v <= max; // inclusive may mean more aggressive LLVM optimizations when inlining, for free
}

/// Generates decorative blocks (such as mushrooms or ceiling plants).
/// Continues from step 4 in `add_ores()`.
///
/// 5. Adds decorative blocks.
/// 6. Critically, sets `edge_flags` of all blocks that are not `is_foundation()` blocks to `0xFF` to prevent erosion.
pub fn add_decorations(target_chunk: *memory.Chunk, rng1: *seeding.ChaCha12) void {
    // Extra decor passes (doesn't worry about cross-chunk sadly)
    for (0..SPAN) |block_y| {
        for (0..SPAN) |block_x| {
            const id = block_x + block_y * SPAN;
            var block = &target_chunk.blocks[id];
            if (!block.is_empty()) continue;
            if (block.is_adjacent_block_solid(EdgeFlags.BOTTOM)) {
                const val = rng1.next();
                if (val <= odds_num(0.3)) {
                    block.id = .mushroom;
                }
            }
        }
    }

    for (1..SPAN) |block_y| { // TODO decide if this failing across chunk boundaries really matters or not
        for (0..SPAN) |block_x| {
            const id = block_x + block_y * SPAN;
            var block = &target_chunk.blocks[id];
            if (block.is_foundation() or target_chunk.blocks[id - 16].is_empty()) continue;
            if (target_chunk.blocks[id - 16].id == .spiral_plant and rng1.next() <= odds_num(0.7)) {
                block.id = .spiral_plant;
            } else if (target_chunk.blocks[id - 16].is_foundation() and block.is_empty()) {
                const val = rng1.next();
                if (val <= odds_num(0.3)) {
                    block.id = .ceiling_flower;
                } else if (val <= odds_num(0.35)) {
                    block.id = .spiral_plant;
                }
            }
        }
    }

    // final pass to reset edge flags for blocks that should NOT be eroded
    for (0..memory.SPAN_SQ) |id| {
        var block = &target_chunk.blocks[id];
        if (!block.is_foundation()) block.edge_flags = 0xFF;
    }
}

/// Linearly interpolates between a and b.
inline fn lerp(a: f64, b: f64, time: f64) f64 {
    return a + time * (b - a);
}

/// Smootherstep formula.
inline fn fade(t: f64) f64 {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

/// Simple noise for testing. Unused.
pub fn get_test_noise(seed: *const Seed, x: f64, y: f64) f64 {
    _ = .{ x, y };
    var prng = seeding.ChaCha12.init(seed);
    return @as(f64, @floatFromInt(prng.next() & 127)) / 128;
}
