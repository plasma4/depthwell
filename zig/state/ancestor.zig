//! Handles fractal ancestry and lookup logic.
const std = @import("std");
const root = @import("../root.zig");
const memory = root.memory;
const world = root.world;
const procedural = root.procedural;
const seeding = root.seeding;

const Sprite = root.Sprite;
const Block = memory.Block;
const Coordinate = memory.Coordinate;
const Chunk = memory.Chunk;
const DepthCoordinate = world.DepthCoordinate;

const HORIZON_DEPTH = memory.HORIZON_DEPTH;
const STARTING_ZOOM_TIMES = root.startup.STARTING_ZOOM_TIMES;

/// Returns whether the specified depth is far enough from the current player depth that discrete coordinates are no longer tracked.
/// At this boundary, chunk-level detail is replaced by the global `QuadCache` 4x4 background grid.
pub inline fn isHorizonDepth(depth: u64) bool {
    // The floor is NEVER a horizon depth.
    if (depth <= STARTING_ZOOM_TIMES) return false;

    const horizon_limit = memory.HORIZON_DEPTH;
    // The horizon (H) kicks in once we are more than 32 + STARTING_ZOOM_TIMES layers deep.
    if (memory.game.depth < STARTING_ZOOM_TIMES + horizon_limit) return false;

    return (depth + horizon_limit) == memory.game.depth;
}

/// Optimized per-depth tier cache for ancestors of chunks. Fully cleared on depth increase.
pub const AncestorCache = struct {
    /// Amount of chunks per depth/tier; too low and performance regressions may occur.
    pub const TIER_SIZE = 32;
    /// The number of tiers of depths to cache. Modulo is used to map depths into tiers safely.
    pub const NUM_TIERS = HORIZON_DEPTH;

    var keys: [NUM_TIERS][TIER_SIZE]DepthCoordinate = @splat(@splat(DepthCoordinate.invalid));
    var chunks: [NUM_TIERS][TIER_SIZE]Chunk = undefined;
    var clock: [NUM_TIERS]std.StaticBitSet(TIER_SIZE) = @splat(std.StaticBitSet(TIER_SIZE).initEmpty());
    var hand: [NUM_TIERS]usize = @splat(0);

    /// Retrieves a chunk by DepthCoordinate. Searches the specific depth tier.
    /// Returns a mutable pointer to allow for in-place updates or direct reads.
    pub fn get(key: DepthCoordinate) ?*Chunk {
        std.debug.assert(!isHorizonDepth(key.depth)); // should've gone to quadrant fallback ):

        // % is slow here if NUM_TIERS is not a power of 2 but it's insignificant
        const d: usize = @intCast(key.depth % NUM_TIERS);

        for (&keys[d], 0..) |cache_key, i| {
            if (i + 1 < TIER_SIZE) {
                // small optimization
                @prefetch(&keys[d][i + 1], .{ .rw = .read, .locality = 0, .cache = .data });
            }

            if (cache_key.depth != 0) {
                if (cache_key.eql(key)) {
                    clock[d].set(i);
                    return &chunks[d][i];
                }
            }
        }
        return null;
    }

    /// Allocates a slot in the appropriate tier based on depth and returns a mutable pointer.
    /// This allows `generateChunk` to write directly into the cache memory.
    ///
    /// Does NOT handle quadrant fallback case; asserts `depth` is high enough.
    pub fn allocateSlot(key: DepthCoordinate) *Chunk {
        std.debug.assert(!isHorizonDepth(key.depth)); // should've gone to quadrant fallback ):
        const d: usize = @intCast(key.depth % NUM_TIERS);

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
    pub fn insert(key: DepthCoordinate, chunk: Chunk) *const Chunk {
        const slot = allocateSlot(key);
        slot.* = chunk;
        return slot;
    }

    /// Clears the `AncestorCache` and resets clock data.
    pub fn clear() void {
        for (0..NUM_TIERS) |i| {
            @memset(&keys[i], .invalid);
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
/// Child's depth is described in the `DepthCoordinate`.
pub fn getParentInfo(key: DepthCoordinate, bx: u4, by: u4) ParentInfo {
    // getParent handles the 3-bit rebase origin reconstruction and quadrant shifts for D > 32.
    const parent = key.getParent();
    const zoom_log2 = memory.ZOOM_LOG2;
    const blocks_per_parent = memory.BLOCKS_PER_PARENT;

    // The LSBs of the suffix determine which 4x4 quadrant of the parent chunk this child occupies.
    const lx: u4 = @intCast(key.suffix[0] & (memory.ZOOM_FACTOR - 1));
    const ly: u4 = @intCast(key.suffix[1] & (memory.ZOOM_FACTOR - 1));

    return .{
        .coord = parent.asCoord(),
        // Map child blocks to parent blocks by shifting the child block into parent-space
        // and offsetting it by the child chunk's position within the parent.
        .bx = (lx * blocks_per_parent) + (bx >> zoom_log2),
        .by = (ly * blocks_per_parent) + (by >> zoom_log2),
    };
}

/// Retrieves a full chunk at any depth, handling cache and procedural generation.
pub fn getAncestorChunk(key: DepthCoordinate) *const Chunk {
    // Check user modifications first...
    if (world.mod_store.get(key)) |mod| return mod;

    // Check the ancestor cache
    if (AncestorCache.get(key)) |cached| return cached;

    // Generate the chunk into the cache slot
    const slot = AncestorCache.allocateSlot(key);
    world.generateChunk(slot, key);
    return slot;
}

/// Given a 4x4 string of 0s and 1s (skipping others).
/// Returns an array of values between 0-15 where there is a 1. Should be called with `comptime`.
pub inline fn get4x4List(comptime str: []const u8) []const u4 {
    comptime {
        var result: [16]u4 = undefined;
        var count: usize = 0;
        var cell_idx: usize = 0;
        var total_cells: usize = 0;

        for (str) |c| {
            if (c == '0' or c == '1') {
                if (total_cells >= 16) {
                    @compileError("Input string contains more than 16 cells.");
                }

                if (c == '1') {
                    result[count] = cell_idx;
                    count += 1;
                }

                cell_idx += 1;
                total_cells += 1;
            }
        }

        if (total_cells != 16) {
            @compileError("Input string must contain exactly 16 characters (0s or 1s).");
        }

        const final = result[0..count];
        return final;
    }
}

/// Gets the ID of a corner for values between 0-15.
/// Top left = 0, top right = 1, bottom left = 2, bottom right = 3
pub inline fn getCornerId(id: u4) u2 {
    const id_row = id % 4;
    const id_col = id / 4;
    return root.utils.intFromBool(u64, id_row >= 2) +
        2 * root.utils.intFromBool(u64, id_col >= 2);
}

/// Applies deterministic logic to a child `Block` based on its parent and 8 parent neighbors.
/// Correctly determines the child's `seed` property when returning it if the block is not empty.
/// Decorations are applied afterward in `procedural.applyAncestorDecorations()`. TODO: actually add this!
/// TODO: also add culling system for invalid decor block configurations in ancestor, see how to deal with spiral plant
pub fn applyAncestorLogic(
    parent_block: Block,
    parent_neighbors: [8]Block,
    key: DepthCoordinate,
    bx: u4,
    by: u4,
) Block {
    var parent_sprite = parent_block.id;
    // const parent_seed = parent_block.seed;

    if (parent_sprite.isEmpty()) return .empty;
    const seeds = world.quad_cache.getChunkSeeds(key);
    var noise_hash_1 = seeding.FastHash.hash2d(.{ seeds[0][0], seeds[0][1] }, bx, by);
    const noise_hash_2 = seeding.FastHash.hash2d(.{ seeds[0][2], seeds[0][3] }, bx, by);
    if (parent_sprite == .edge_stone)
        return Block.makeBasicBlock(parent_sprite, @truncate(noise_hash_2));

    // Structural logic!
    const local_id = (by % 4) * 4 + (bx % 4);
    const corner_list = comptime get4x4List(
        \\1001
        \\0000
        \\0000
        \\1001
    );
    const corners_nonempty: [4]bool = .{
        parent_neighbors[1].isFoundation() or parent_neighbors[3].isFoundation(),
        parent_neighbors[1].isFoundation() or parent_neighbors[4].isFoundation(),
        parent_neighbors[3].isFoundation() or parent_neighbors[6].isFoundation(),
        parent_neighbors[4].isFoundation() or parent_neighbors[7].isFoundation(),
    };
    inline for (corner_list) |id| {
        if (id == local_id and parent_sprite.isFoundation()) {
            const corner_id = getCornerId(id);
            const is_corner_empty = !corners_nonempty[corner_id];
            if (is_corner_empty) return .empty;
        }
    }

    // Inherit plant still!
    if (parent_sprite == .spiral_plant)
        return .makeBasicBlock(.spiral_plant, @truncate(noise_hash_2));

    if (parent_sprite == .mushroom) {
        // Only make specific sub-blocks of a mushroom parent become big mushroom!
        return if ((bx % 4 == 1 or bx % 4 == 2) and by % 4 == 3)
            .makeBasicBlock(.big_mushroom, @truncate(noise_hash_2))
        else
            .empty; // bypass edges logic too
    }

    // var seed = parent_block.seed;
    if (parent_sprite.isFoundation()) { // we don't want non-solid blocks to become solid, since the player could be in them
        const edges_list = comptime get4x4List(
            \\1111
            \\1001
            \\1001
            \\1111
        );
        inline for (edges_list) |id| {
            if (noise_hash_1 % 4 == 0) {
                // 25% odds to randomly take a parent neighbor's sprite type now!

                // each block gets different noise with right-shift
                const noise: u3 = @truncate(noise_hash_1);
                noise_hash_1 >>= @bitSizeOf(@TypeOf(noise));

                const parent = parent_neighbors[noise];
                if (!parent.isEmpty()) parent_sprite = parent.id;
                if (parent_sprite == .edge_stone) return .empty;
            } else if (noise_hash_1 % 8 == 2) {
                // 12.5% odds for edges to become empty
                const corner_id = getCornerId(id);
                const is_corner_empty = !corners_nonempty[corner_id];
                if (is_corner_empty) return .empty;
            }
        }
    }

    var evolved_sprite: Sprite = switch (parent_sprite) {
        .mossy_stone => .spiral_plant,
        .purple_strange_stone => .red_stone,
        .red_stone => .redder_stone,
        .redder_stone => .lava_stone,
        else => parent_sprite,
    };

    const noise: u8 = @truncate(noise_hash_1);
    noise_hash_1 >>= @bitSizeOf(@TypeOf(noise));
    if (evolved_sprite == .blue_strange_stone and noise < 16) {
        // 1 in 8 chance
        evolved_sprite = .blue_stone;
    }

    // Return the new block, passing the hash down as the new seed for the next generation.
    return Block.makeBasicBlock(evolved_sprite, @truncate(noise_hash_2));
}

/// Traces the lineage of a single block type. Target depth is described in the `DepthCoordinate`.
pub fn getInheritedMaterial(key: DepthCoordinate, bx: u4, by: u4) Block {
    const target_depth = key.depth;
    if (target_depth == STARTING_ZOOM_TIMES) {
        const block_idx = (@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx;

        if (world.mod_store.get(key)) |modified| return modified.blocks[block_idx];
        if (AncestorCache.get(key)) |cached| return cached.blocks[block_idx];

        const slot = AncestorCache.allocateSlot(key);
        world.generateBaseChunk(slot, key.asCoord());
        return slot.blocks[block_idx];
    }

    if (isHorizonDepth(target_depth)) {
        return world.getBlockAt(key.asCoord(), bx, by, target_depth);
    }

    const block_idx = (@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx;

    if (world.mod_store.get(key)) |modified| return modified.blocks[block_idx];
    if (AncestorCache.get(key)) |cached| return cached.blocks[block_idx];

    const p = getParentInfo(key, bx, by);
    const parent_block = getInheritedMaterial(p.coord.asDepthCoordinate(target_depth - 1), p.bx, p.by);

    // Fetch the 3x3 boundary of the parent block to pass to our ancestor logic
    var neighbors: [8]Block align(8) = undefined;
    var n_idx: usize = 0;

    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const lx = @as(i32, @intCast(p.bx)) + dx;
            const ly = @as(i32, @intCast(p.by)) + dy;
            const chunk_off_x = @divFloor(lx, memory.CHUNK_SIZE);
            const chunk_off_y = @divFloor(ly, memory.CHUNK_SIZE);

            const target_nc = p.coord.moveAtDepth(.{ chunk_off_x, chunk_off_y }, target_depth - 1) orelse {
                // neighbors[n_idx] = if (target_depth - 1 == STARTING_ZOOM_TIMES) .edge_stone else .none;
                neighbors[n_idx] = .empty;
                n_idx += 1;
                continue;
            };

            // This uses AncestorCache!
            neighbors[n_idx] = getInheritedMaterial(
                target_nc.asDepthCoordinate(target_depth - 1),
                @intCast(@mod(lx, memory.CHUNK_SIZE)),
                @intCast(@mod(ly, memory.CHUNK_SIZE)),
            );
            n_idx += 1;
        }
    }

    return applyAncestorLogic(parent_block, neighbors, key, bx, by);
}

/// Fetches a 6x6 neighborhood of parent IDs for the generator. Requires a specific depth and location.
pub fn getAncestorNeighborhood(key: DepthCoordinate) [6][6]Block {
    var result: [6][6]Block = undefined;
    const parent_depth = key.depth - 1;

    const p_info_origin = getParentInfo(key, 0, 0);
    const start_px = @as(i32, @intCast(p_info_origin.bx)) - 1;
    const start_py = @as(i32, @intCast(p_info_origin.by)) - 1;

    // Small local cache for the 1-4 parent chunks required for this neighborhood
    var cached_chunks: [4]?*const Chunk = @splat(null);
    var cached_coords: [4]Coordinate = undefined;

    for (0..6) |y_idx| {
        for (0..6) |x_idx| {
            const lx = start_px + @as(i32, @intCast(x_idx));
            const ly = start_py + @as(i32, @intCast(y_idx));
            const chunk_off_x = @divFloor(lx, 16);
            const chunk_off_y = @divFloor(ly, 16);

            const target_nc = p_info_origin.coord.moveAtDepth(
                .{ chunk_off_x, chunk_off_y },
                parent_depth,
            ) orelse {
                // result[y_idx][x_idx] = if (parent_depth == STARTING_ZOOM_TIMES) .edge_stone else .empty;
                result[y_idx][x_idx] = .empty;
                continue;
            };

            if (isHorizonDepth(parent_depth)) {
                result[y_idx][x_idx] = world.getBlockAt(
                    target_nc,
                    @intCast(@mod(lx, 16)),
                    @intCast(@mod(ly, 16)),
                    parent_depth,
                );
                continue;
            }

            var chunk: ?*const Chunk = null;
            for (0..4) |i| {
                if (cached_chunks[i]) |c| {
                    if (cached_coords[i].eql(target_nc)) {
                        chunk = c;
                        break;
                    }
                } else {
                    const new_chunk = getAncestorChunk(target_nc.asDepthCoordinate(parent_depth));
                    cached_chunks[i] = new_chunk;
                    cached_coords[i] = target_nc;
                    chunk = new_chunk;
                    break;
                }
            }

            result[y_idx][x_idx] = chunk.?.blocks[
                (@as(usize, @intCast(@mod(ly, 16))) << 4) |
                    @as(usize, @intCast(@mod(lx, 16)))
            ];
        }
    }
    return result;
}
