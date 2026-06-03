//! Handles procedural generation logic for the game.
const std = @import("std");
const root = @import("../root.zig");
const types = root.types;
const logger = root.logger;
const memory = root.memory;
const seeding = root.seeding;
const world = root.world;

const POW_2_32 = seeding.POW_2_32;
const CHUNK_SIZE = memory.CHUNK_SIZE;

const Sprite = root.Sprite;
const EdgeFlags = types.EdgeFlags;
const oddsNum = seeding.oddsNum;
const HashState = seeding.HashState;
const FastHash = seeding.FastHash;
const Seed = seeding.Seed;
const Vec2f = memory.Vec2f;
const Vec2u = memory.Vec2u;

// Lots of values controllable by debug sliders here!
pub const dual_value_scale = TuningFloat(16.0);
pub const base_gem_odds = TuningFloat(0.1);
pub const procedural_cell_size = TuningFloat(1.0);
pub const fbm_scale = TuningFloat(1.0);
pub const density_min = TuningFloat(0.26);
pub const density_max = TuningFloat(0.9);

/// Returns a struct with an a `value: f64` and `getF32()`.
/// Allows for numbers to act like variables in Debug mode and constant-fold in all Release modes.
inline fn TuningFloat(comptime default_value: f64) type {
    if (root.is_debug) {
        return struct {
            pub var value: f64 = default_value;
            pub inline fn getF32() f32 {
                return @floatCast(value);
            }
        };
    } else {
        return struct {
            pub const value: f64 = default_value;
            pub inline fn getF32() f32 {
                return @floatCast(value);
            }
        };
    }
}

/// Returns a struct with an a `value: bool`. (TODO: switch to using this instead of current heatmap logic)
/// Allows for booleans to act like variables in Debug mode and dead code elimination in all Release modes.
inline fn TuningBool(comptime default_value: bool) type {
    if (root.is_debug) {
        return struct {
            pub var value: bool = default_value;
        };
    } else {
        return struct {
            pub const value: bool = default_value;
        };
    }
}

/// Determines whether to use a heatmap or not for base terrain. Ignored if `root.is_debug` is false.
pub var USE_BASE_HEATMAP = false;
/// Determines whether to use a heatmap or not for ore generation. Ignored if `root.is_debug` is false.
pub var USE_ORE_HEATMAP = false;

/// Configuration options passed to the FBM (Fractal Brownian Motion) and Worley
/// noise generation algorithm (`getFbmWorleyValue`).
const TerrainOptions = struct {
    /// Controls the scale of the primary noise grid cells.
    /// Larger values stretch out the noise patterns.
    cell_size: comptime_float,

    /// The maximum offset distance applied during the FBM domain warping step.
    /// Higher values cause more severe "displacement" or squiggly distortion in the terrain.
    /// Setting this to 0 eliminates any distortion.
    fbm_shift_size: comptime_float,

    /// When true, stretches out the vertical sampling coordinates by a factor of 2 (horizontal stretching of 2x).
    horizontally_wide: bool = false,

    /// Determines whether the algorithm computes true Worley cellular noise metrics (F2 - F1 distance).
    ///
    /// - If `true`, performs an optimized 4-tap cellular distance check (essential for jagged cave walls or sharp ore veins).
    /// - If `false`, bypasses cellular logic entirely and falls back to a much faster, basic bilinear value noise interpolation.
    use_f2_f1: bool = true,
};

/// Temporary data produced during the first pass of structural generation.
const BaseTerrainData = struct {
    sprite: Sprite,
    moisture: f32,
    density: f32,
};

const STRUCTURE_AREA = 32; // must be a power of 2 for simplicity
comptime {
    if (!std.math.isPowerOfTwo(STRUCTURE_AREA)) @compileError("Structure position area must be a positive power of 2.");
}

/// Adds larger structures across multiple blocks in a deterministic fashion. Water is a structure.
/// Continues from steps 1-3 in `getBaseSpriteType()`.
///
/// 4. Disperses ores using Worley noise. Assumes that `isStone()` was checked before calling.
pub inline fn addStructures(wx: u32, wy: u32, struct_seed: Vec2u, density_seed: Vec2u) ?Sprite {
    const struct_x_coord = wx / STRUCTURE_AREA;
    const struct_y_coord = @as(u64, @intCast(wy / STRUCTURE_AREA));
    const block_x_hash = struct_x_coord + (struct_y_coord << 32);

    var hash = HashState{
        .value = FastHash.hash2d(struct_seed, block_x_hash, 0),
        .seed_vector = struct_seed,
        .x = block_x_hash,
        .y = 0,
    };
    _ = density_seed;
    const size_x = 8;
    const size_y = 5;

    const x_in_area: i32 = @intCast(wx % STRUCTURE_AREA);
    const y_in_area: i32 = @intCast(wy % STRUCTURE_AREA);

    // Prevent horizontal clipping entirely by wrapping within safe bounds
    const max_pos_x: u64 = STRUCTURE_AREA - size_x;
    const max_pos_y: u64 = STRUCTURE_AREA - size_y;

    // Consuming bits in-place from our HashState at compile time without runtime branch overhead
    const pos_x = hash.getLimit(i32, max_pos_x);
    const pos_y = hash.getLimit(i32, max_pos_y);

    // Reject if placement clips the top boundary of the grid cell
    if (pos_y < 0) return null;

    const struct_x = x_in_area - pos_x;
    const struct_y = y_in_area - pos_y;

    // Reject if not inside the structure rectangle
    if (struct_x < 0 or struct_y < 0 or struct_x >= size_x or struct_y >= size_y) {
        return null;
    }

    // Draw the structural outer shell
    if (struct_x == 0 or struct_y == 0 or
        struct_x == size_x - 1 or struct_y == size_y - 1)
    {
        return .seagreen_stone;
    }

    // Add a chest along the bottom row inside the structure
    const chest_x = hash.getRange(i32, 1, size_x + 1);
    if (struct_y == size_y - 2) {
        if (struct_x == chest_x) return .chest;
    }

    // Return .none (air) for the interior blocks to hollow out any solid stone
    return .none;
}

/// A highly optimized bilinear value noise implementation.
/// Bypasses domain warping and multi-tap cellular distance lookups entirely.
pub fn getBilinearValueNoise(seed_vector: Vec2u, x: u32, y: u32, cell_size: f32) f32 {
    const fx = @as(f32, @floatFromInt(x)) / cell_size;
    const fy = @as(f32, @floatFromInt(y)) / cell_size;

    const x0 = @floor(fx);
    const y0 = @floor(fy);
    const tx = fx - x0;
    const ty = fy - y0;

    const ix0: u64 = @intFromFloat(x0);
    const iy0: u64 = @intFromFloat(y0);

    // Fade curves (hermite/smoothstep variant basically)
    const u = tx * tx * (3.0 - 2.0 * tx);
    const v = ty * ty * (3.0 - 2.0 * ty);

    // Direct 4-tap lookup
    const h00 = FastHash.hash2d(seed_vector, ix0, iy0);
    const h10 = FastHash.hash2d(seed_vector, ix0 +% 1, iy0);
    const h01 = FastHash.hash2d(seed_vector, ix0, iy0 +% 1);
    const h11 = FastHash.hash2d(seed_vector, ix0 +% 1, iy0 +% 1);

    const v00 = @as(f32, @floatFromInt(h00 & 0xFFFFFFFF)) / POW_2_32;
    const v10 = @as(f32, @floatFromInt(h10 & 0xFFFFFFFF)) / POW_2_32;
    const v01 = @as(f32, @floatFromInt(h01 & 0xFFFFFFFF)) / POW_2_32;
    const v11 = @as(f32, @floatFromInt(h11 & 0xFFFFFFFF)) / POW_2_32;

    const nx0 = v00 + u * (v10 - v00);
    const nx1 = v01 + u * (v11 - v01);
    return nx0 + v * (nx1 - nx0);
}

/// Returns a value between 0-1, used as a terrain starting point for the default depth of 3.
/// Optimizations applied: If F2-F1 calculations are not required, uses ultra-fast bilinear interpolation.
fn getFbmWorleyValue(seed_vector: Vec2u, x: u32, y: u32, comptime options: TerrainOptions) f32 {
    // If we don't need cellular Worley structures (such as simplified ore/decor boundaries), value noise is faster.
    if (!options.use_f2_f1) {
        return getBilinearValueNoise(seed_vector, x, y, options.cell_size);
    }

    const fx: f32 = @floatFromInt(x);
    const fy: f32 = @floatFromInt(if (options.horizontally_wide) y * 2 else y);

    const h_stretch = 1.5;
    const fbm_octaves = 3;
    var warp_x: f32 = 0;
    var warp_y: f32 = 0;

    var freq: u64 = 1;
    var amp: f32 = options.fbm_shift_size;
    amp /= fbm_scale.getF32();
    if (amp > 0) {
        // basic FBM warping
        inline for (0..fbm_octaves) |_| {
            const noise = getDualValueNoise(seed_vector, x * freq, y * freq);
            warp_x += noise[0] * amp;
            warp_y += noise[1] * amp;
            amp *= 0.5;
            freq *%= 2;
        }
    }

    const cell_size = options.cell_size * procedural_cell_size.getF32();
    const wx = fx + warp_x;
    const wy = fy + warp_y;
    const cell_w = cell_size * h_stretch;

    const cx_f = @floor(wx / cell_w);
    const cy_f = @floor(wy / cell_size);
    const cx_i: i64 = @intFromFloat(cx_f);
    const cy_i: i64 = @intFromFloat(cy_f);

    var d1_sq = std.math.inf(f32);
    var d2_sq = std.math.inf(f32);

    // Optimized 2x2 Worley Search (downward right-hand quadrant)
    // Dropping from 9-tap to 4-tap lookup yields a ~55% reduction in hashing and math operations
    inline for (0..2) |ox| {
        inline for (0..2) |oy| {
            const cur_x: u64 = @bitCast(cx_i + ox);
            const cur_y: u64 = @bitCast(cy_i + oy);

            const h = FastHash.hash2d(seed_vector, cur_x, cur_y);
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

    return @min((@sqrt(d2_sq) - @sqrt(d1_sq)) / cell_size, 1.0);
}

/// Generates a block for seeding (based on previous procedural generation logic).
/// The terms moisture/density are used extremely loosely here.
/// Moisture is over a larger area, acting as the "biome" for structure logic.
pub fn generateSpriteFromValues(moisture: f64, density: f64) Sprite {
    // check is_debug because these will always be off in non-dev
    // sprite IDs in this range create a heatmap
    if (root.is_debug and USE_BASE_HEATMAP and !USE_ORE_HEATMAP)
        return @enumFromInt(65000 + @as(u20, @intFromFloat(moisture * 256.0)));
    if (root.is_debug and USE_BASE_HEATMAP and USE_ORE_HEATMAP) return .stone;

    if (moisture <= 0.12) {
        return .water; // TODO: improve
    }

    if (density <= 0.04 and moisture >= 0.3 and moisture <= 0.4) {
        return .blue_strange_stone;
    } else if (density <= density_min.getF32() or density >= density_max.getF32()) {
        return if (moisture >= 0.93 and moisture <= 0.97) .purple_strange_stone else .none;
    }

    if (moisture >= 0.93 and moisture <= 0.94) return .red_stone;
    if (moisture >= 0.88 and moisture <= 0.92) return .lava_stone;
    if (moisture >= 0.50 and density <= 0.53 and density <= 0.6) return .green_stone;

    if (moisture >= 0.58 and density >= 0.83) return .seagreen_stone;
    if (moisture <= 0.65 and density >= 0.60 and density <= 0.7) return .blue_stone;
    if (density >= 0.40 and density <= 0.55) return .contrast_blue_stone;

    if (moisture >= 0.20 and moisture <= 0.26) return .mossy_stone;
    if (moisture >= 0.98) return .old_stone;
    return .stone;
}

/// Returns a base sprite type. Does 3 passes:
///
/// 1. Generate an initial terrain density+moisture value using the seed vectors.
/// 2. Generate a block from those values.
/// 3. Generates larger structures with FBM Worley and valid placement checks.
pub inline fn getBaseSpriteType(
    chunk_x: u32,
    chunk_y: u32,
    block_x: u4,
    block_y: u4,
) BaseTerrainData {
    const moisture = getFbmWorleyValue( // acts as a biome selector
        memory.game.seed2[0..2].*, // code is INLINED, so this is okay presumably
        // .{ 0, 0 },
        chunk_x * 16 + block_x,
        chunk_y * 16 + block_y,
        .{
            .cell_size = 600.0, // very LARGE cells for biome generation
            .fbm_shift_size = 20.0, // minimize shift potential
            .horizontally_wide = false,
        },
    );
    const density = getFbmWorleyValue( // more granular density
        memory.game.seed2[2..4].*,
        // .{ 0, 0 },
        chunk_x * 16 + block_x,
        chunk_y * 16 + block_y,
        .{
            .cell_size = 80.0, // smaller cells for cave terrain
            .fbm_shift_size = 24.0,
            .horizontally_wide = true,
        },
    );

    const sprite = generateSpriteFromValues(moisture, density);

    // drawing sprite change in WebGPU now after tile unpacking, quite silly to be here
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

/// Returns two independent noise values (32-bit float) based on the classic Value Noise algorithm.
fn getDualValueNoise(seed: Vec2u, x: u64, y: u64) memory.Vec2f32 {
    const fx_raw = @as(f32, @floatFromInt(x)) / dual_value_scale.getF32();
    const fy_raw = @as(f32, @floatFromInt(y)) / dual_value_scale.getF32();

    const x0: u64 = @trunc(fx_raw);
    const y0: u64 = @trunc(fy_raw);
    const tx = fx_raw - @trunc(fx_raw);
    const ty = fy_raw - @trunc(fy_raw);

    // Fade curves
    const u = tx * tx * tx * (tx * (tx * 6 - 15) + 10);
    const v = ty * ty * ty * (ty * (ty * 6 - 15) + 10);

    const h00 = FastHash.hash2d(seed, x0, y0); // ChaCha12 is too slow ):
    const h10 = FastHash.hash2d(seed, x0 +% 1, y0);
    const h01 = FastHash.hash2d(seed, x0, y0 +% 1);
    const h11 = FastHash.hash2d(seed, x0 +% 1, y0 +% 1);

    var res: memory.Vec2f32 = .{ 0, 0 };
    inline for (0..2) |i| {
        const shift: u6 = @intCast(i * 32);
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
/// Continues from step 4 in `getStructureBlock()`.
///
/// 5. Disperses ores using Worley noise. Assumes that `isStone()` was checked before calling.
pub fn addOres(
    base_data: BaseTerrainData,
    seed_vector_1: Vec2u,
    seed_vector_2: Vec2u,
    seed_vector_3: Vec2u,
    seed_vector_4: Vec2u,
    x: u32,
    y: u32,
) Sprite {
    var sprite = base_data.sprite;

    // Generate new density for ores: the seed vector should be different from the `getFbmWorleyDensity()` vector.
    const v1 = getFbmWorleyValue( // smaller cells, less FBM variation
        seed_vector_1,
        x,
        y,
        .{
            .cell_size = 20.0,
            .fbm_shift_size = 30.0,
            .horizontally_wide = false,
            .use_f2_f1 = true,
        },
    );
    const v2 = getFbmWorleyValue( // larger cells, much more FBM variation
        seed_vector_2,
        x,
        y,
        .{
            .cell_size = 36.0,
            .fbm_shift_size = 60.0,
            .horizontally_wide = false,
            .use_f2_f1 = true,
        },
    );

    // sprite IDs in this range use a neat heatmap (using only the first variation value), overriding normal ore logic
    if (root.is_debug and USE_ORE_HEATMAP) return @enumFromInt(65000 + @as(u20, @intFromFloat(v1 * 256.0)));

    if (base_data.density >= 0.45 and base_data.density <= 0.65) {
        // Generate various ore types
        sprite = selectSprite(
            .{ sprite, .copper },
            true,
            .{ v2, 0.0, 0.2 },
        );
        if (sprite == .copper or v2 >= 0.7) return sprite;

        sprite = selectSprite(
            .{ sprite, .iron },
            true,
            .{ v1, 0.55, 0.65 },
        );
        if (sprite == .iron and base_data.sprite != .blue_strange_stone) return sprite;

        sprite = selectSprite(
            .{ sprite, .silver },
            base_data.density <= 0.48,
            .{ v1, 0.2, 0.26 },
        );
        sprite = selectSprite(
            .{ sprite, .silver },
            base_data.sprite == .blue_strange_stone,
            .{ v1, 0.18, 0.2 },
        );
        if (sprite == .iron or sprite == .silver) return sprite;

        sprite = selectSprite(
            .{ sprite, .gold },
            base_data.density >= 0.63 or (base_data.density >= 0.59 and base_data.sprite == .lava_stone),
            .{ v2, 0.3, 0.4 },
        );
        if (sprite == .gold) return sprite;
    } else {
        // Logic for generating gems
        const gem_v2_bound: f32 = if (sprite == .purple_strange_stone) 0.4 else 0.3;
        if (base_data.density >= 0.3 and base_data.density <= 0.5 and v2 >= 0.1 and v2 <= gem_v2_bound) {
            const random_value = FastHash.float2d(seed_vector_3, @intCast(x), @intCast(y));

            if (random_value <= base_gem_odds.value) {
                const v3 = getFbmWorleyValue(
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

                sprite = selectSprite(
                    .{ sprite, .amethyst },
                    v3 <= 0.4 and random_value <= 0.4 * base_gem_odds.value,
                    null,
                );
                if (sprite == .amethyst) return sprite;

                sprite = selectSprite(
                    .{ sprite, .sapphire },
                    v3 >= 0.75 and random_value <= 0.65 * base_gem_odds.value,
                    null,
                );
                if (sprite == .sapphire) return sprite;

                sprite = selectSprite(
                    .{ sprite, .emerald },
                    v3 >= 0.45 and v3 <= 0.65 and random_value <= 0.86 * base_gem_odds.value,
                    null,
                );
                if (sprite == .emerald) return sprite;

                sprite = selectSprite(
                    .{ sprite, .ruby },
                    v3 >= 0.22 and v3 <= 0.3,
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
/// Technical definition: returns the second `Sprite` in the pair if `condition` is satisfied `range[0]` falls within `range[1]`.
/// Returns the first `Sprite` otherwise.
///
/// Example usage:
/// ```zig
/// // Returns iron if density is larger than 0.6 AND my_value is between 0.6 and 0.7 (inclusive), and stone otherwise.
/// Sprite sprite = cw(.iron, my_density >= 0.6, my_value, 0.6, 0.7, .stone);
/// ```
pub inline fn selectSprite(sprites: SpritePair, condition: bool, range: ?ValueRange) Sprite {
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
pub inline fn isWithin(v: f32, min: comptime_float, max: comptime_float) bool {
    if (max <= min) @compileError("Maximum value must be larger than minimum value.");
    return v >= min and v <= max; // inclusive may mean more aggressive LLVM optimizations when inlining, for free
}

/// Generates decorative blocks (such as mushrooms or ceiling plants).
/// Continues from step 5 in `addOres()`.
///
/// 6. Adds decorative blocks.
pub fn addDecorations(target_chunk: *memory.Chunk, rng_decor: *seeding.ChaCha12) void {
    // Extra decor passes (doesn't worry about cross-chunk sadly)
    for (0..CHUNK_SIZE) |block_y| {
        var forced_next_sprite_type: Sprite = .none; // .none means nothing is forced
        for (0..CHUNK_SIZE) |block_x| {
            const idx = block_x + block_y * CHUNK_SIZE;
            var block = &target_chunk.blocks[idx];
            if (forced_next_sprite_type != .none) {
                // semantically, .none makes sense, simply an alternative to optional type
                block.id = forced_next_sprite_type;
                forced_next_sprite_type = .none;
                continue;
            }

            if (!block.isEmpty()) continue;
            if (block.isAdjacentBlockSolid(EdgeFlags.BOTTOM)) {
                const val = rng_decor.next();
                // const is_left = block_x % 2 == 0; // no longer needed

                // returns Z+1 if Z is even and Z-1 if Z is odd
                const other_block_x = block_x ^ 1; // guaranteed to be from 0-15, no OOB block x-value

                // Only if the other block is also empty AND can have a decor do we create a 2x1 decor sprite!
                const other_block = &target_chunk.blocks[other_block_x + block_y * CHUNK_SIZE];
                if (other_block.isEmpty() and other_block.isAdjacentBlockSolid(EdgeFlags.BOTTOM)) {
                    if (val >= oddsNum(0.98)) {
                        // we are modifying the block on the left. force the type of the block to the right too!
                        block.id = .big_tree1_left;
                        forced_next_sprite_type = .big_tree1_right;
                        continue;
                    } else if (val >= oddsNum(0.97)) {
                        block.id = .big_tree2_left;
                        forced_next_sprite_type = .big_tree2_right;
                        continue;
                    }
                }

                if (val <= oddsNum(0.03)) {
                    block.id = .bush;
                } else if (val <= oddsNum(0.1)) {
                    block.id = .rock;
                } else if (val <= oddsNum(0.13)) {
                    block.id = .mushroom;
                }
            }
        }
    }

    for (0..CHUNK_SIZE) |block_y| {
        for (0..CHUNK_SIZE) |block_x| {
            const idx = block_x + block_y * CHUNK_SIZE;
            var block = &target_chunk.blocks[idx];
            if (!block.isEmpty()) continue;
            const has_ceiling = block.isAdjacentBlockSolid(types.EdgeFlags.getFlagBit(0, -1));

            // Local check for spiral plant growth (allowed to be chunk-local).
            const is_spiral_above = if (block_y > 0)
                target_chunk.blocks[idx - CHUNK_SIZE].id == .spiral_plant
            else
                false;

            const val = rng_decor.next();
            if (is_spiral_above) {
                if (val <= oddsNum(0.7)) {
                    block.id = .spiral_plant;
                }
            } else if (has_ceiling) {
                if (val <= oddsNum(0.3)) {
                    block.id = .ceiling_flower;
                } else if (val <= oddsNum(0.35)) {
                    block.id = .spiral_plant;
                }
            }
        }
    }

    // final pass to reset edge flags for blocks that should NOT be eroded
    // update: now logic is in chunk.zig
    // for (0..memory.CHUNK_SIZE_SQ) |id| {
    //     var block = &target_chunk.blocks[id];
    //     if (!block.isFoundation()) block.edge_flags = 0xFF;
    // }
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
pub fn getTestNoise(seed: *const Seed, x: f64, y: f64) f64 {
    _ = .{ x, y };
    var prng = seeding.ChaCha12.init(seed);
    return @as(f64, @floatFromInt(prng.next() & 127)) / 128;
}
