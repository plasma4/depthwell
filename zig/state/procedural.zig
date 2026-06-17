//! Handles procedural generation logic for the game.
const std = @import("std");
const r = @import("../root.zig");
const types = r.types;
const logger = r.logger;
const memory = r.memory;
const seeding = r.seeding;
const world = r.world;

const POW_2_32 = seeding.POW_2_32;
const INV_POW_2_32 = seeding.INV_POW_2_32;
const POW_2_64 = seeding.POW_2_64;
const CHUNK_SIZE = memory.CHUNK_SIZE;

const Sprite = r.Sprite;
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
    if (r.is_debug) {
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
    if (r.is_debug) {
        return struct {
            pub var value: bool = default_value;
        };
    } else {
        return struct {
            pub const value: bool = default_value;
        };
    }
}

/// Determines whether to use a heatmap or not for base terrain. Ignored if `r.is_debug` is false.
pub var USE_BASE_HEATMAP = false;
/// Determines whether to use a heatmap or not for ore generation. Ignored if `r.is_debug` is false.
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

/// Creates a `HashState` given a seed, coordinates, and power-of-two area where a structure may appear within.
pub inline fn makeStructureHash(
    struct_seed: Vec2u,
    wx: u32,
    wy: u32,
    structure_area: comptime_int,
    unique_id: comptime_int,
) HashState {
    std.debug.assert(std.math.isPowerOfTwo(structure_area));
    const struct_x_coord = wx / structure_area;
    const struct_y_coord = @as(u64, @intCast(wy / structure_area));
    const hash_val = struct_x_coord + (struct_y_coord << 32);
    const init_y = @as(u64, unique_id) << 32;

    return .{
        .value = FastHash.hash2d(struct_seed, hash_val, init_y),
        .seed_vector = struct_seed,
        .x = hash_val,
        .y = init_y,
        .bits_left = 64,
    };
}

/// Adds larger structures across multiple blocks in a deterministic fashion.
/// Continues from steps 1-3 in `getBaseSpriteType()`.
///
/// 4. Disperses ores using Worley noise. Assumes that `isStone()` was checked before calling.
pub fn addStructures(
    starting_sprite: Sprite,
    wx: u32,
    wy: u32,
    struct_seed: Vec2u,
    density_seed: Vec2u,
) Sprite {
    _ = density_seed;
    // IMPORTANT: structure areas should be a power of 2 so that the modulo becomes an & instruction.

    // Structure 1: basic rect with chest inside
    // SSSSSSSSSS
    // S        S
    // S c      S
    // SSSSSSSSSS
    {
        const structure_area = 32;
        var state1 = makeStructureHash(struct_seed, wx, wy, structure_area, 0);

        // Fast odds check (3% chance)
        if (state1.getChance(0.03)) {
            const size_x = 8;
            const size_y = 5;

            const x_in_area: i32 = @intCast(wx % structure_area); // modulo optimized to AND
            const y_in_area: i32 = @intCast(wy % structure_area);

            const max_pos_x = structure_area - size_x;
            const max_pos_y = structure_area - size_y;

            // Extract values using the state generator instead of manual bit-slicing
            const pos_x = @as(i32, @intCast(state1.getLimit(u32, max_pos_x)));
            const pos_y = @as(i32, @intCast(state1.getLimit(u32, max_pos_y)));
            const chest_x = 1 + @as(i32, @intCast(state1.getLimit(u32, size_x - 2)));

            const struct_x = x_in_area - pos_x;
            const struct_y = y_in_area - pos_y;

            if (struct_x >= 0 and struct_y >= 0 and struct_x < size_x and struct_y < size_y) {
                if (struct_x == 0 or struct_y == 0 or struct_x == size_x - 1 or struct_y == size_y - 1) {
                    return .seagreen_stone;
                }

                if (struct_y == size_y - 2 and struct_x == chest_x) {
                    return .chest;
                }

                return if (starting_sprite.isLiquid()) starting_sprite else .none;
            }
        }
    }

    // Structure 2: ancient (fossil-like) run with chest inside
    //   SSSS
    //  SS  SS
    // SS c SSS
    //  SSSSSS
    {
        const structure_area = 64;
        var state2 = makeStructureHash(struct_seed, wx, wy, structure_area, 1);

        if (state2.getChance(0.32)) {
            const base_radius_x = state2.getRange(i32, 6, 12); // [6, 12)
            const base_radius_y = state2.getRange(i32, 4, 7); // [4, 7)

            const padding = 3;
            const size_x = (base_radius_x + padding) * 2;
            const size_y = (base_radius_y + padding) * 2;

            const x_in_area: i32 = @intCast(wx % structure_area);
            const y_in_area: i32 = @intCast(wy % structure_area);

            const max_pos_x: i32 = @max(1, @as(i32, structure_area) - size_x);
            const max_pos_y: i32 = @max(1, @as(i32, structure_area) - size_y);

            // TODO: is it bad that these aren't comptime?
            const pos_x = state2.getLimit(i32, max_pos_x);
            const pos_y = state2.getLimit(i32, max_pos_y);

            const struct_x = x_in_area - pos_x;
            const struct_y = y_in_area - pos_y;

            // Reject early if outside bounding box
            if (struct_x >= 0 and struct_y >= 0 and struct_x < size_x and struct_y < size_y) {
                const center_x = size_x >> 1;
                const center_y = size_y >> 1;
                const dx = struct_x - center_x;
                const dy = struct_y - center_y;

                const skew_x = state2.getRange(i32, -1, 2); // [-1, 2)
                const skew_y = state2.getRange(i32, -1, 2); // [-1, 2)
                const local_noise_x = state2.getRange(i32, -1, 1); // [-1, 1)

                const rx = base_radius_x + skew_x + local_noise_x;
                const ry = base_radius_y + skew_y;

                if (rx > 0 and ry > 0) {
                    const dist_sq = (dx * dx * ry * ry) + (dy * dy * rx * rx);
                    const outer_bound = rx * rx * ry * ry;

                    const wall_thickness = 2;
                    const inner_rx: i32 = @max(1, rx - wall_thickness);
                    const inner_ry: i32 = @max(1, ry - wall_thickness);

                    if (dist_sq <= outer_bound) {
                        // Mathematically correct elliptical inner boundary check
                        const inner_dist_sq = (dx * dx * inner_ry * inner_ry) + (dy * dy * inner_rx * inner_rx);
                        const inner_bound = inner_rx * inner_rx * inner_ry * inner_ry;

                        if (inner_dist_sq > inner_bound) {
                            const erosion_factor = (wx ^ wy) % 7;
                            if (erosion_factor == 0) return .none;
                            return .ancient_stone;
                        } else {
                            const floor_y = center_y + inner_ry - 1;

                            // Prevent boundary clipping by limiting chest selection to inner_rx/2
                            const chest_range = inner_rx;
                            const chest_offset = (-inner_rx >> 1) + state2.getLimit(i32, chest_range);
                            const chest_x = center_x + chest_offset;

                            if (struct_y == floor_y and struct_x == chest_x) {
                                return .chest;
                            }
                            return .none;
                        }
                    }
                }
            }
        }
    }

    // Structure 3: Pillar thing
    // Spawns with water
    // SSSSSSSSSSSSSSSS
    // S   P     P    S
    // S   P     P    S
    // S      c       S
    // S     SSS      S
    // SSSSSSSSSSSSSSSS
    {
        const structure_area = 128;
        var state3 = makeStructureHash(struct_seed, wx, wy, structure_area, 2);

        if (state3.getChance(0.08)) {
            const size_x = 24;
            const size_y = 12;

            const x_in_area: i32 = @intCast(wx % structure_area);
            const y_in_area: i32 = @intCast(wy % structure_area);

            const max_pos_x = structure_area - size_x;
            const max_pos_y = structure_area - size_y;

            const pos_x = @as(i32, @intCast(state3.getLimit(u32, max_pos_x)));
            const pos_y = @as(i32, @intCast(state3.getLimit(u32, max_pos_y)));
            const bit = state3.getChance(0.5);

            const struct_x = x_in_area - pos_x;
            const struct_y = y_in_area - pos_y;

            // Bounding box check
            if (struct_x >= 0 and struct_y >= 0 and struct_x < size_x and struct_y < size_y) {
                // Outermost stone frame
                if (struct_x == 0 or struct_y == 0 or struct_x == size_x - 1 or struct_y == size_y - 1) {
                    return .ancient_stone;
                }

                // Columns are placed every 5 blocks on the x-axis, centered vertically
                const rel_col_x = @rem((struct_x - 3), 5);
                const is_pillar_column = rel_col_x == 1;
                const is_pillar_row = (struct_y >= 3 and struct_y <= size_y - 4);

                if (is_pillar_column and is_pillar_row) {
                    // Don't block the very center where the tomb altar sits
                    const is_near_center = (struct_x >= size_x / 2 - 3 and struct_x <= size_x / 2 + 2);
                    if (!is_near_center) {
                        return .mossy_stone;
                    }
                }

                // Central altar and chest placement
                const altar_x = size_x / 2;
                const altar_y = size_y - 3;
                if (struct_y == altar_y and struct_x == altar_x) {
                    return .chest;
                }
                if (struct_y == altar_y + 1 and (struct_x >= altar_x - 1 and struct_x <= altar_x + 1)) {
                    return .seagreen_stone; // Solid base under chest
                }

                if (struct_y == size_y - 2) {
                    return .water;
                } else if (struct_y == size_y - 3) {
                    return .water;
                } else if (bit and struct_y == size_y - 3) {
                    return .water;
                }

                return .none;
            }
        }
    }

    return starting_sprite;
}

/// A highly optimized bilinear value noise implementation.
/// Bypasses domain warping and multi-tap cellular distance lookups entirely.
fn getBilinearValueNoise(seed_vector: Vec2u, x: u32, y: u32, cell_size: f32) f32 {
    const fx = @as(f32, @floatFromInt(x)) / cell_size;
    const fy = @as(f32, @floatFromInt(y)) / cell_size;

    const x0 = @floor(fx);
    const y0 = @floor(fy);
    const tx = fx - x0;
    const ty = fy - y0;

    const ix0: u64 = @intFromFloat(x0);
    const iy0: u64 = @intFromFloat(y0);

    // Fade curves! In this case, -20t^7 + 70t^6 - 84t^5 + 35t^4.
    const u = tx * tx * tx * tx * (tx * (tx * (35.0 - 20.0 * tx) - 84.0) + 70.0);
    const v = ty * ty * ty * ty * (ty * (ty * (35.0 - 20.0 * ty) - 84.0) + 70.0);

    // Direct 4-tap lookup
    const h00 = FastHash.hash2d(seed_vector, ix0, iy0);
    const h10 = FastHash.hash2d(seed_vector, ix0 +% 1, iy0);
    const h01 = FastHash.hash2d(seed_vector, ix0, iy0 +% 1);
    const h11 = FastHash.hash2d(seed_vector, ix0 +% 1, iy0 +% 1);

    const v00 = @as(f32, @floatFromInt(h00)) / POW_2_64;
    const v10 = @as(f32, @floatFromInt(h10)) / POW_2_64;
    const v01 = @as(f32, @floatFromInt(h01)) / POW_2_64;
    const v11 = @as(f32, @floatFromInt(h11)) / POW_2_64;

    const nx0 = v00 + u * (v10 - v00);
    const nx1 = v01 + u * (v11 - v01);
    return nx0 + v * (nx1 - nx0);
}

/// Returns a value between 0-1, used as a terrain starting point for the default depth of 3.
/// Note that of F2-F1 calculations are not required, `getBilinearValueNoise()` is called instead.
fn getFbmWorleyValue(seed_vector: Vec2u, x: u32, y: u32, comptime options: TerrainOptions) f32 {
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

    const inv_fbm_scale = 1.0 / fbm_scale.getF32();
    const inv_dual_value_scale = 1.0 / dual_value_scale.getF32();
    amp *= inv_fbm_scale;

    if (amp > 0) {
        inline for (0..fbm_octaves) |_| {
            const noise = getDualValueNoise(seed_vector, x * freq, y * freq, inv_dual_value_scale);
            warp_x += noise[0] * amp;
            warp_y += noise[1] * amp;
            amp *= 0.55; // 55%, not 50%!
            freq *%= 2;
        }
    }

    const cell_size = options.cell_size * procedural_cell_size.getF32();
    const inv_cell_size = 1.0 / cell_size;
    const cell_w = cell_size * h_stretch;
    const inv_cell_w = 1.0 / cell_w;

    const wx = fx + warp_x;
    const wy = fy + warp_y;

    // Fast division-free float-to-int mapping
    const cx_f = @floor(wx * inv_cell_w);
    const cy_f = @floor(wy * inv_cell_size);
    const cx_i: i64 = @intFromFloat(cx_f);
    const cy_i: i64 = @intFromFloat(cy_f);

    var d1_sq = std.math.inf(f32);
    var d2_sq = std.math.inf(f32);

    // Worley search stuff! Uses a lot of optimization tricks.
    inline for (0..2) |ox| {
        inline for (0..2) |oy| {
            const cur_x: u64 = @bitCast(cx_i + ox);
            const cur_y: u64 = @bitCast(cy_i + oy);

            const h = FastHash.hash2d(seed_vector, cur_x, cur_y);
            const off_x = @as(f32, @floatFromInt(@as(u32, @truncate(h)))) * INV_POW_2_32;
            const off_y = @as(f32, @floatFromInt(@as(u32, @truncate(h >> 32)))) * INV_POW_2_32;

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

    return @min((@sqrt(d2_sq) - @sqrt(d1_sq)) * inv_cell_size, 1.0);
}

/// Generates a block for seeding (based on previous procedural generation logic).
/// The terms moisture/density are used extremely loosely here.
/// Moisture is over a larger area, acting as the "biome" for structure logic.
pub fn generateBaseProceduralSprite(moisture: f64, density: f64) Sprite {
    // check is_debug because these will always be off in non-dev
    // sprite IDs in this range create a heatmap
    if (r.is_debug and USE_BASE_HEATMAP and !USE_ORE_HEATMAP)
        return @enumFromInt(65000 + @as(u20, @intFromFloat(moisture * 256.0)));
    if (r.is_debug and USE_BASE_HEATMAP and USE_ORE_HEATMAP) return .stone;

    if (density <= density_min.getF32() or density >= density_max.getF32()) {
        if (moisture >= 0.93 and moisture <= 0.94) return .purple_strange_stone;
        return .none;
    } else if (density <= 0.04 and moisture >= 0.3 and moisture <= 0.4) {
        return .blue_strange_stone;
    }

    if (moisture >= 0.98) return .ancient_stone;
    if (moisture > 0.9) return .none;

    if (moisture >= 0.93 and moisture <= 0.94) return .red_stone;
    if (moisture >= 0.88 and moisture <= 0.92) return .lava_stone;
    if (moisture >= 0.50 and density <= 0.53 and density <= 0.6) return .green_stone;

    if (moisture >= 0.62 and density >= 0.83) return .seagreen_stone;
    if (moisture <= 0.55 and density >= 0.60 and density <= 0.72) return .blue_stone;
    if (density >= 0.45 and density <= 0.50 and moisture < 0.30) return .water;
    if (density >= 0.40 and density <= 0.55) return .contrast_blue_stone;

    if (moisture >= 0.20 and moisture <= 0.26) return .mossy_stone;
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
        memory.game.getHashSeed(.moisture), // code is INLINED, so this is okay presumably
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
        memory.game.getHashSeed(.density),
        // .{ 0, 0 },
        chunk_x * 16 + block_x,
        chunk_y * 16 + block_y,
        .{
            .cell_size = 80.0, // smaller cells for cave terrain
            .fbm_shift_size = 24.0,
            .horizontally_wide = true,
        },
    );

    const sprite = generateBaseProceduralSprite(moisture, density);

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

/// Returns two independent noise values (32-bit float) using vectorized 4-corner value noise.
fn getDualValueNoise(seed: Vec2u, x: u64, y: u64, inv_scale: f32) memory.Vec2f32 {
    const fx_raw = @as(f32, @floatFromInt(x)) * inv_scale;
    const fy_raw = @as(f32, @floatFromInt(y)) * inv_scale;

    const x0_f = @floor(fx_raw);
    const y0_f = @floor(fy_raw);
    const x0: u64 = @intFromFloat(x0_f);
    const y0: u64 = @intFromFloat(y0_f);

    const tx = fx_raw - x0_f;
    const ty = fy_raw - y0_f;

    // Fade curves
    const u = tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0);
    const v = ty * ty * ty * (ty * (ty * 6.0 - 15.0) + 10.0);

    // Prepare 4 corners: (x0, y0), (x0+1, y0), (x0, y0+1), (x0+1, y0+1)
    const Vec4u = @Vector(4, u64);
    const vx: Vec4u = .{ x0, x0 +% 1, x0, x0 +% 1 };
    const vy: Vec4u = .{ y0, y0, y0 +% 1, y0 +% 1 };

    // Single SIMD pipeline execution
    const h_vec = FastHash.hash2d_4x(seed, vx, vy);

    var res: memory.Vec2f32 = .{ 0, 0 };

    inline for (0..2) |i| {
        const shift: u6 = @intCast(i * 32);
        const shifted = h_vec >> @as(Vec4u, @splat(shift));
        const truncated: @Vector(4, u32) = @truncate(shifted);
        const floats: @Vector(4, f32) = @floatFromInt(truncated);
        const v_vec = floats * @as(@Vector(4, f32), @splat(INV_POW_2_32));

        const v00 = v_vec[0];
        const v10 = v_vec[1];
        const v01 = v_vec[2];
        const v11 = v_vec[3];

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
    if (r.is_debug and USE_ORE_HEATMAP) return @enumFromInt(65000 + @as(u20, @intFromFloat(v1 * 256.0)));

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
    if (range) |val| {
        const v = val[0];
        const min = val[1];
        const max = val[2];
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
/// 6. Adds blocks, primarily decorations, that require certain anchor types (`AnchorKind` in types/sprite.zig).
pub fn addDecorations(target_chunk: *memory.Chunk, rng_decor: *seeding.ChaCha12) void {
    // While these don't fully work across chunks, it's almost impossible to practically notice.

    // First, we handle blocks with a floor anchor kind.
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
            // Check calculated bitmask directly to avoid isAdjacentBlockSolid logic discrepancies
            if ((block.edge_flags & types.EdgeFlags.BOTTOM) != 0) {
                const val = rng_decor.next();

                // Only initiate 2x1 tree placement on even columns to prevent asymmetric overwrites
                if (block_x % 2 == 0 and block_x != CHUNK_SIZE - 1) {
                    const other_block_x = block_x + 1;
                    const other_block = &target_chunk.blocks[other_block_x + block_y * CHUNK_SIZE];
                    if (other_block.isEmpty() and ((other_block.edge_flags & types.EdgeFlags.BOTTOM) != 0)) {
                        if (val >= oddsNum(0.98)) {
                            block.id = .big_tree1_left;
                            forced_next_sprite_type = .big_tree1_right;
                            continue;
                        } else if (val >= oddsNum(0.97)) {
                            block.id = .big_tree2_left;
                            forced_next_sprite_type = .big_tree2_right;
                            continue;
                        }
                    }
                }

                if (val <= oddsNum(0.03)) {
                    block.id = .bush;
                } else if (val <= oddsNum(0.1)) {
                    block.id = .rock;
                } else if (val <= oddsNum(0.13)) {
                    block.id = .mushroom;
                } else if (val <= oddsNum(0.14)) {
                    block.id = .forest_furnace;
                } else if (val <= oddsNum(0.15)) {
                    block.id = .lava_furnace;
                }
            }
        }
    }

    // Now, we handle blocks with a ceiling/suspended anchor kind.
    for (0..CHUNK_SIZE) |block_y| {
        for (0..CHUNK_SIZE) |block_x| {
            const idx = block_x + block_y * CHUNK_SIZE;
            var block = &target_chunk.blocks[idx];
            if (!block.isEmpty()) continue;
            // Direct bitmask query to bypass isAdjacentBlockSolid inconsistencies
            const has_ceiling = (block.edge_flags & types.EdgeFlags.TOP) != 0;

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
