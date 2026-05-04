//! Handles fractal ancestry and lookup logic.
const std = @import("std");
const root = @import("../root.zig");
const memory = root.memory;
const world = root.world;
const procedural = root.procedural;
const seeding = root.seeding;

const STARTING_ZOOM_TIMES = root.startup.STARTING_ZOOM_TIMES;
const Sprite = root.Sprite;
const Coordinate = memory.Coordinate;
const Chunk = memory.Chunk;
const ModKey = world.ModKey;

/// Optimized per-depth tier cache for ancestors of chunks.
pub const AncestorCache = struct {
    /// 32 chunks per depth to allow full horizontal sweeps without evicting local dependencies.
    pub const TIER_SIZE = 32;
    /// The number of depth tiers to cache. Modulo is used to map depths into tiers safely.
    /// TODO: evaluate if +SZT is needed
    pub const NUM_TIERS = 32 + STARTING_ZOOM_TIMES;

    var keys: [NUM_TIERS][TIER_SIZE]?ModKey = [_][TIER_SIZE]?ModKey{[_]?ModKey{null} ** TIER_SIZE} ** NUM_TIERS;
    var chunks: [NUM_TIERS][TIER_SIZE]Chunk = undefined;
    var clock: [NUM_TIERS]std.StaticBitSet(TIER_SIZE) = [_]std.StaticBitSet(TIER_SIZE){std.StaticBitSet(TIER_SIZE).initEmpty()} ** NUM_TIERS;
    var hand: [NUM_TIERS]usize = [_]usize{0} ** NUM_TIERS;

    /// Retrieves a chunk by ModKey. Searches the specific depth tier.
    /// Returns a mutable pointer to allow for in-place updates or direct reads.
    pub fn get(key: ModKey) ?*Chunk {
        const d = @as(usize, @intCast(key.depth % NUM_TIERS));

        for (&keys[d], 0..) |maybe_key, i| {
            if (maybe_key) |k| {
                if (k.depth == key.depth and k.quadrant == key.quadrant and @reduce(.And, k.suffix == key.suffix)) {
                    clock[d].set(i);
                    return &chunks[d][i];
                }
            }
        }
        return null;
    }

    /// Allocates a slot in the appropriate tier based on depth and returns a mutable pointer.
    /// This allows `generateChunk` to write directly into the cache memory.
    pub fn allocateSlot(key: ModKey) *Chunk {
        const d = @as(usize, @intCast(key.depth % NUM_TIERS));

        while (true) {
            const id = hand[d];
            hand[d] = (id + 1) % TIER_SIZE;

            if (clock[d].isSet(id)) {
                // Give second chance and clear reference bit.
                clock[d].setValue(id, false);
            } else {
                // Found eviction candidate.
                keys[d][id] = key;
                clock[d].set(id); // Set reference bit for the new entry.
                return &chunks[d][id];
            }
        }
    }

    /// Allocates a slot and inserts a chunk directly.
    pub fn insert(key: ModKey, chunk: Chunk) *const Chunk {
        const slot = allocateSlot(key);
        slot.* = chunk;
        return slot;
    }

    /// Clears the `AncestorCache` and resets clock data.
    pub fn clear() void {
        for (0..NUM_TIERS) |i| {
            @memset(&keys[i], null);
            clock[i] = std.StaticBitSet(TIER_SIZE).initEmpty();
            hand[i] = 0;
        }
    }
};

/// Parent coordinate and block offset info.
pub const ParentInfo = struct {
    coord: Coordinate,
    bx: u4,
    by: u4,
};

/// Shifts the suffix and incorporates the local block position to find the exact parent chunk and block.
pub fn getParentInfo(coord: Coordinate, bx: u4, by: u4, target_depth: u64) ParentInfo {
    _ = target_depth; // Prevent unused parameter err in case it's used for quadrants later
    const zoom_shift = memory.ZOOM_LOG2;
    const parent_block_shift = memory.CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2;

    // Calculate local parent block indices including potential underflow/overflow
    const raw_px: i32 = @as(i32, @intCast(coord.suffix[0] & (memory.ZOOM_FACTOR - 1))) << parent_block_shift;
    const raw_py: i32 = @as(i32, @intCast(coord.suffix[1] & (memory.ZOOM_FACTOR - 1))) << parent_block_shift;

    const final_bx: u4 = @intCast(@as(u32, @intCast(raw_px)) | (bx >> zoom_shift));
    const final_by: u4 = @intCast(@as(u32, @intCast(raw_py)) | (by >> zoom_shift));

    return .{
        // Moving the chunk coordinate handles quadrant/boundary logic correctly
        .coord = .{
            .suffix = .{ coord.suffix[0] >> zoom_shift, coord.suffix[1] >> zoom_shift },
            .quadrant = coord.quadrant,
        },
        .bx = final_bx,
        .by = final_by,
    };
}

/// Applies deterministic holes based on coordinate and depth. For testing purposes; naive.
/// TODO replace with actual cool logic!
pub fn applyDeterministicHoles(sprite: Sprite, coord: Coordinate, bx: u4, by: u4, depth: u64) Sprite {
    if (sprite == .none) return .none;
    if (!sprite.isFoundation()) return sprite; // Keep decor/edge stone!

    var hasher = std.hash.Wyhash.init(depth);
    std.hash.autoHash(&hasher, coord.quadrant);
    std.hash.autoHash(&hasher, coord.suffix[0]);
    std.hash.autoHash(&hasher, coord.suffix[1]);
    std.hash.autoHash(&hasher, bx);
    std.hash.autoHash(&hasher, by);
    const noise = hasher.final();

    // chance for hole!
    if (noise <= seeding.oddsNum(0.20)) {
        return .none;
    }

    // funny test pattern
    // if ((bx ^ by) & 4 == 3) {
    //     return .none;
    // }
    return sprite;
}
/// Traces the lineage of a single block type.
pub fn getInheritedMaterial(target_depth: u64, coord: Coordinate, bx: u4, by: u4) Sprite {
    // Quadrant fallback case!
    if (target_depth + memory.QUADRANTLESS_DEPTH <= memory.game.depth) {
        // Depth shouldn't be smaller ("skipping").
        std.debug.assert(target_depth + memory.QUADRANTLESS_DEPTH == memory.game.depth);
        return world.quad_cache.ancestor_materials[coord.quadrant];
    }

    // High-speed cache check
    const mod_key = world.ModKey{
        .suffix = coord.suffix,
        .quadrant = coord.quadrant,
        .depth = target_depth,
    };

    if (AncestorCache.get(mod_key)) |cached| {
        return cached.blocks[(@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx].id;
    }

    // Check modification store for any changes with this depth!
    if (world.mod_store.get(mod_key)) |modified| {
        return modified.blocks[(@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx].id;
    }

    // At STARTING_ZOOM_TIMES; this is the base case depth.
    // Break the recursion loop by generating the actual base chunk and caching it.
    if (target_depth == STARTING_ZOOM_TIMES) {
        const slot = AncestorCache.allocateSlot(mod_key);
        world.generateChunk(slot, coord, target_depth);
        return slot.blocks[(@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx].id;
    }

    // Probe the parent ID.
    const p_info = getParentInfo(coord, bx, by, target_depth);
    const parent_sprite = getInheritedMaterial(target_depth - 1, p_info.coord, p_info.bx, p_info.by);

    // Scale-up logic: If parent is solid, child is solid.
    if (parent_sprite.isFoundation()) {
        return applyDeterministicHoles(parent_sprite, coord, bx, by, target_depth);
    }

    // Parent was air or decoration, allow!
    return parent_sprite;
}

/// Fetches a 6x6 neighborhood of parent IDs for the generator.
/// Optimized to fetch 3x3 parent chunks once rather than 36 individual block lookups.
pub fn getAncestorNeighborhood(target_depth: u64, coord_d: Coordinate) [6][6]Sprite {
    var result: [6][6]Sprite = undefined;
    const parent_depth = target_depth - 1;

    // Base Case
    if (target_depth == STARTING_ZOOM_TIMES) {
        for (0..6) |y| @memset(&result[y], .stone);
        return result;
    }

    // Identify the top-left-most parent block required (index -1, -1 relative to child origin)
    const p_info_origin = getParentInfo(coord_d, 0, 0, target_depth);
    const start_px: i32 = @as(i32, @intCast(p_info_origin.bx)) - 1;
    const start_py: i32 = @as(i32, @intCast(p_info_origin.by)) - 1;

    // Fetch the 3x3 chunk grid that covers the 6x6 block area
    var parent_chunks: [3][3]?*const Chunk = [_][3]?*const Chunk{[_]?*const Chunk{null} ** 3} ** 3;
    inline for (.{ -1, 0, 1 }) |cy| {
        inline for (.{ -1, 0, 1 }) |cx| {
            // Directly offset the chunk coordinate relative to the origin chunk
            const nc = p_info_origin.coord.moveAtDepth(.{ cx, cy }, parent_depth);

            if (nc) |coord| {
                const key = world.ModKey{ .suffix = coord.suffix, .quadrant = coord.quadrant, .depth = parent_depth };
                // Use getInheritedMaterial logic but specifically for the chunk pointer
                parent_chunks[@intCast(cy + 1)][@intCast(cx + 1)] = if (AncestorCache.get(key)) |c| c else if (world.mod_store.get(key)) |m| m else blk: {
                    // If not cached, we MUST generate it
                    const slot = AncestorCache.allocateSlot(key);
                    world.generateChunk(slot, coord, parent_depth);
                    break :blk slot;
                };
            }
        }
    }

    // Fill the 6x6 sprite result from the 3x3 chunk grid
    for (0..6) |y_idx| {
        for (0..6) |x_idx| {
            const lx = start_px + @as(i32, @intCast(x_idx));
            const ly = start_py + @as(i32, @intCast(y_idx));

            const chunk_x = @divFloor(lx, memory.CHUNK_SIZE) + 1;
            const chunk_y = @divFloor(ly, memory.CHUNK_SIZE) + 1;

            if (chunk_x >= 0 and chunk_x < 3 and chunk_y >= 0 and chunk_y < 3) {
                if (parent_chunks[@intCast(chunk_y)][@intCast(chunk_x)]) |c| {
                    const bx: usize = @intCast(@mod(lx, memory.CHUNK_SIZE));
                    const by: usize = @intCast(@mod(ly, memory.CHUNK_SIZE));
                    result[y_idx][x_idx] = c.blocks[by * memory.CHUNK_SIZE + bx].id;
                    continue;
                }
            }

            const max_s = world.getMaxSuffixAtDepth(parent_depth);
            const is_edge_x = (chunk_x < 1 and p_info_origin.coord.suffix[0] == 0) or
                (chunk_x >= 2 and p_info_origin.coord.suffix[0] == max_s);
            const is_edge_y = (chunk_y < 1 and p_info_origin.coord.suffix[1] == 0) or
                (chunk_y >= 2 and p_info_origin.coord.suffix[1] == max_s);

            result[y_idx][x_idx] = if (is_edge_x or is_edge_y) .edge_stone else world.quad_cache.ancestor_materials[coord_d.quadrant];
        }
    }
    return result;
}
