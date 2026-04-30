//! Handles fractal ancestry, caching of D-1 chunks, and deterministic holes.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const world = root.world;
const procedural = root.procedural;
const seeding = root.seeding;

const STARTING_ZOOM_TIMES = root.startup.STARTING_ZOOM_TIMES;
const Sprite = root.Sprite;
const Coordinate = memory.Coordinate;
const Chunk = memory.Chunk;

/// A cache specifically designed to hold chunks from the previous depth.
/// Caching here prevents `getInheritedMaterial` from recalculating the ancestry
/// of 256 blocks redundantly when adjacent chunks at Depth D share the same D-1 parent.
///
/// Static; does not need initialization.
pub const AncestorCache = struct {
    pub const CACHE_SIZE = 16;

    var keys: [CACHE_SIZE]?Coordinate = [_]?Coordinate{null} ** CACHE_SIZE;
    var chunks: [CACHE_SIZE]Chunk = undefined;
    var clock_bits: std.StaticBitSet(CACHE_SIZE) = std.StaticBitSet(CACHE_SIZE).initEmpty();
    var hand: usize = 0;

    /// Retrieves a D-1 chunk if it exists, marking it as recently used.
    pub fn get(coord_d_minus_1: Coordinate) ?*Chunk {
        for (&keys, 0..) |maybe_key, i| {
            if (maybe_key) |k| {
                if (k.eql(coord_d_minus_1)) {
                    clock_bits.set(i);
                    return &chunks[i];
                }
            }
        }
        return null;
    }

    /// Allocates a slot for a D-1 chunk, evicting an old one using a clock algorithm.
    pub fn allocateSlot(coord_d_minus_1: Coordinate) *Chunk {
        while (true) {
            const id = hand;
            hand = (hand + 1) % CACHE_SIZE;

            if (clock_bits.isSet(id)) {
                clock_bits.setValue(id, false);
            } else {
                keys[id] = coord_d_minus_1;
                clock_bits.set(id);
                return &chunks[id];
            }
        }
    }

    /// Retrieves the 6x6 grid of parent blocks at Depth D-1 corresponding to the provided chunk at Depth D.
    /// The inner 4x4 grid (indices 1..4) represents the direct parents of the 16x16 child chunk.
    /// The outer ring provides a 1-block margin for edge calculations.
    pub fn getAncestorNeighborhood(target_depth: u64, coord_d: Coordinate) [6][6]Sprite {
        var result: [6][6]Sprite = undefined;

        // No ancestors exist below base depth. Return fallback safety blocks.
        if (target_depth <= STARTING_ZOOM_TIMES) {
            for (0..6) |y| {
                @memset(&result[y], .stone);
            }
            return result;
        }

        const parent_depth = target_depth - 1;
        // Get the parent info for the top-left-most child block (0, 0)
        const p_info = getParentInfo(coord_d, 0, 0);

        for (0..6) |y_id| {
            for (0..6) |x_id| {
                const dx: i32 = @as(i32, @intCast(x_id)) - 1;
                const dy: i32 = @as(i32, @intCast(y_id)) - 1;

                const nx: i32 = @as(i32, p_info.bx) + dx;
                const ny: i32 = @as(i32, p_info.by) + dy;

                var neighbor_coord = p_info.coord;
                var out_of_bounds = false;

                // Handle neighbor crossing chunk boundaries at Depth D-1
                if (nx < 0 or nx >= memory.CHUNK_SIZE or ny < 0 or ny >= memory.CHUNK_SIZE) {
                    if (p_info.coord.move(.{ @divFloor(nx, memory.CHUNK_SIZE), @divFloor(ny, memory.CHUNK_SIZE) })) |nc| {
                        neighbor_coord = nc;
                    } else {
                        out_of_bounds = true;
                    }
                }

                if (out_of_bounds) {
                    result[y_id][x_id] = .edge_stone; // Hard edge of the simulation
                } else {
                    const lbx: u4 = @intCast(@mod(nx, memory.CHUNK_SIZE));
                    const lby: u4 = @intCast(@mod(ny, memory.CHUNK_SIZE));
                    result[y_id][x_id] = getInheritedMaterial(parent_depth, neighbor_coord, lbx, lby);
                }
            }
        }
        return result;
    }

    /// Clears the `AncestorCache`.
    pub fn clear() void {
        @memset(&keys, null);
        clock_bits = std.StaticBitSet(CACHE_SIZE).initEmpty();
        hand = 0;
    }
};

/// Parent coordinate and block offset info.
pub const ParentInfo = struct {
    coord: Coordinate,
    bx: u4,
    by: u4,
};

/// Shifts the suffix and incorporates the local block position to find the exact parent chunk and block.
pub fn getParentInfo(coord: Coordinate, bx: u4, by: u4) ParentInfo {
    const zoom_shift = memory.ZOOM_LOG2;
    const parent_block_shift = memory.CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2;

    return .{
        .coord = .{
            .suffix = .{
                coord.suffix[0] >> zoom_shift,
                coord.suffix[1] >> zoom_shift,
            },
            .quadrant = coord.quadrant,
        },
        .bx = @intCast(((coord.suffix[0] & (memory.ZOOM_FACTOR - 1)) << parent_block_shift) | (bx >> zoom_shift)),
        .by = @intCast(((coord.suffix[1] & (memory.ZOOM_FACTOR - 1)) << parent_block_shift) | (by >> zoom_shift)),
    };
}

/// Applies deterministic holes based on coordinate and depth. For testing purposes.
/// TODO replace with actual cool logic!
pub fn applyDeterministicHoles(sprite: Sprite, coord: Coordinate, bx: u4, by: u4, depth: u64) Sprite {
    if (sprite == .none) return .none;

    var hasher = std.hash.Wyhash.init(depth);
    std.hash.autoHash(&hasher, coord.quadrant);
    std.hash.autoHash(&hasher, coord.suffix[0]);
    std.hash.autoHash(&hasher, coord.suffix[1]);
    std.hash.autoHash(&hasher, bx);
    std.hash.autoHash(&hasher, by);

    // chance for hole: 20%
    if (hasher.final() < root.seeding.oddsNum(0.2)) {
        return .none;
    }
    return sprite;
}

/// Generates a chunk entirely for the base depth (D=3).
/// Re-uses procedural logic, but returns the specific block requested.
/// Highly optimized targeted lookup for a single base-depth block.
/// This prevents quadratic time-complexity as it just looks up requested block and necessary neighbors.
pub fn evaluateBaseDepth(coord: Coordinate, bx: u4, by: u4) Sprite {
    const cx: u32 = @truncate(coord.suffix[0]);
    const cy: u32 = @truncate(coord.suffix[1]);

    // Get the primary block state (Stone/Ores)
    const sprite = getBaseProceduralSprite(cx, cy, bx, by);

    // If the block is not empty, it's a foundation/ore block; decorations can't spawn here.
    if (!sprite.isEmpty()) return sprite;
    return .none;
}

/// Helper to get the stone ore ore state for an absolute coordinate.
fn getBaseProceduralSprite(cx: u32, cy: u32, bx: u4, by: u4) Sprite {
    const seed_vec1: memory.Vec2u = .{ memory.game.seed2[0], memory.game.seed2[1] };
    const seed_vec2: memory.Vec2u = .{ memory.game.seed2[2], memory.game.seed2[3] };
    const seed_vec3: memory.Vec2u = .{ memory.game.seed2[4], memory.game.seed2[5] };
    const seed_vec4: memory.Vec2u = .{ memory.game.seed2[6], memory.game.seed2[6] };
    const seed_vec5: memory.Vec2u = .{ memory.game.seed2[7], memory.game.seed2[8] };
    const seed_vec6: memory.Vec2u = .{ memory.game.seed2[9], memory.game.seed2[10] };

    const base_data = procedural.getBaseSpriteType(seed_vec1, seed_vec2, cx, cy, bx, by);
    if (base_data.sprite.isStone() or base_data.sprite.isHeatmap()) {
        return procedural.addOres(base_data, seed_vec3, seed_vec4, seed_vec5, seed_vec6, cx * 16 + bx, cy * 16 + by);
    }
    return base_data.sprite;
}

/// Helper to get base procedural state relative to a chunk/block, handling boundaries.
fn getBaseProceduralSpriteRelative(coord: Coordinate, bx: u4, by: u4, dx: i32, dy: i32) Sprite {
    const nx = @as(i32, bx) + dx;
    const ny = @as(i32, by) + dy;

    var target_coord = coord;
    if (nx < 0 or nx >= 16 or ny < 0 or ny >= 16) {
        target_coord = coord.move(.{ @divFloor(nx, 16), @divFloor(ny, 16) }) orelse return .edge_stone;
    }

    return getBaseProceduralSprite(@truncate(target_coord.suffix[0]), @truncate(target_coord.suffix[1]), @intCast(@mod(nx, 16)), @intCast(@mod(ny, 16)));
}

/// Recursively traces the lineage of a block from the target depth down to max(D-31, STARTING_ZOOM_TIMES).
/// Updated logic to trace ancestry without exponential block-by-block recursion.
pub fn getInheritedMaterial(target_depth: u64, coord: Coordinate, bx: u4, by: u4) Sprite {
    const mod_key = world.ModKey{
        .suffix = coord.suffix,
        .quadrant = coord.quadrant,
        .depth = target_depth,
    };
    if (world.mod_store.get(mod_key)) |modified_chunk| {
        return modified_chunk.blocks[(@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx].id;
    }

    if (target_depth == memory.game.depth - 1 and target_depth >= 3) {
        if (AncestorCache.get(coord)) |cached_chunk| {
            return cached_chunk.blocks[(@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx].id;
        }

        const new_chunk = AncestorCache.allocateSlot(coord);
        const original_depth = memory.game.depth;
        memory.game.depth = target_depth;

        // writeChunkSkip triggers the full generation pass (including decorations)
        world.writeChunkSkip(new_chunk, coord);

        memory.game.depth = original_depth;
        return new_chunk.blocks[(@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx].id;
    }

    if (target_depth <= STARTING_ZOOM_TIMES) {
        return evaluateBaseDepth(coord, bx, by);
    }

    const parent_info = getParentInfo(coord, bx, by);
    const parent_sprite = getInheritedMaterial(target_depth - 1, parent_info.coord, parent_info.bx, parent_info.by);
    return applyDeterministicHoles(parent_sprite, coord, bx, by, target_depth);
}

/// Retrieves the 6x6 grid of parent blocks at Depth D-1 corresponding to the provided chunk at Depth D.
/// The inner 4x4 grid (indices 1..4) represents the direct parents of the 16x16 child chunk.
/// The outer ring provides a 1-block margin for edge calculations.
pub fn getAncestorNeighborhood(target_depth: u64, coord_d: Coordinate) [6][6]Sprite {
    var result: [6][6]Sprite = undefined;

    // No ancestors exist below base depth. Return fallback safety blocks.
    if (target_depth <= STARTING_ZOOM_TIMES) {
        for (0..6) |y| {
            @memset(&result[y], .stone);
        }
        return result;
    }

    const parent_depth = target_depth - 1;
    // Get the parent info for the top-left-most child block (0, 0)
    const p_info = getParentInfo(coord_d, 0, 0);

    for (0..6) |y_id| {
        for (0..6) |x_id| {
            const dx: i32 = @as(i32, @intCast(x_id)) - 1;
            const dy: i32 = @as(i32, @intCast(y_id)) - 1;

            const nx: i32 = @as(i32, p_info.bx) + dx;
            const ny: i32 = @as(i32, p_info.by) + dy;

            var neighbor_coord = p_info.coord;
            var out_of_bounds = false;

            // Handle neighbor crossing chunk boundaries at Depth D-1
            if (nx < 0 or nx >= memory.CHUNK_SIZE or ny < 0 or ny >= memory.CHUNK_SIZE) {
                if (p_info.coord.move(.{ @divFloor(nx, memory.CHUNK_SIZE), @divFloor(ny, memory.CHUNK_SIZE) })) |nc| {
                    neighbor_coord = nc;
                } else {
                    out_of_bounds = true;
                }
            }

            if (out_of_bounds) {
                result[y_id][x_id] = .edge_stone; // Hard edge of the simulation
            } else {
                const lbx: u4 = @intCast(@mod(nx, memory.CHUNK_SIZE));
                const lby: u4 = @intCast(@mod(ny, memory.CHUNK_SIZE));
                result[y_id][x_id] = getInheritedMaterial(parent_depth, neighbor_coord, lbx, lby);
            }
        }
    }
    return result;
}
