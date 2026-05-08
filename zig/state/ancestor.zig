//! Handles fractal ancestry and lookup logic.
const std = @import("std");
const root = @import("../root.zig");
const memory = root.memory;
const world = root.world;
const procedural = root.procedural;
const seeding = root.seeding;

const HORIZON_DEPTH = memory.HORIZON_DEPTH;
const STARTING_ZOOM_TIMES = root.startup.STARTING_ZOOM_TIMES;
const Sprite = root.Sprite;
const Coordinate = memory.Coordinate;
const Chunk = memory.Chunk;
const DepthCoordinate = world.DepthCoordinate;

/// Returns whether the specified depth is far enough from the current player depth that discrete coordinates are no longer tracked.
/// At this boundary, chunk-level detail is replaced by the global `QuadCache` 4x4 background grid.
pub inline fn isHorizonDepth(depth: u64) bool {
    // The floor is NEVER a horizon depth.
    if (depth <= STARTING_ZOOM_TIMES) return false;

    const horizon_limit = memory.HORIZON_DEPTH;
    // Horizon kicks in once we are 32 layers deep.
    if (memory.game.depth < STARTING_ZOOM_TIMES + horizon_limit) return false;

    return (depth + horizon_limit) == memory.game.depth;
}

/// Optimized per-depth tier cache for ancestors of chunks.
pub const AncestorCache = struct {
    /// Amount of chunks per depth/tier; too low and performance regressions may occur.
    pub const TIER_SIZE = 32;
    /// The number of tiers of depths to cache. Modulo is used to map depths into tiers safely.
    pub const NUM_TIERS = 33;

    var keys: [NUM_TIERS][TIER_SIZE]?DepthCoordinate = [_][TIER_SIZE]?DepthCoordinate{[_]?DepthCoordinate{null} ** TIER_SIZE} ** NUM_TIERS;
    var chunks: [NUM_TIERS][TIER_SIZE]Chunk = undefined;
    var clock: [NUM_TIERS]std.StaticBitSet(TIER_SIZE) = [_]std.StaticBitSet(TIER_SIZE){std.StaticBitSet(TIER_SIZE).initEmpty()} ** NUM_TIERS;
    var hand: [NUM_TIERS]usize = [_]usize{0} ** NUM_TIERS;

    /// Retrieves a chunk by DepthCoordinate. Searches the specific depth tier.
    /// Returns a mutable pointer to allow for in-place updates or direct reads.
    pub fn get(key: DepthCoordinate) ?*Chunk {
        std.debug.assert(!isHorizonDepth(key.depth)); // should've gone to quadrant fallback ):
        const d = @as(usize, @intCast(key.depth % NUM_TIERS)); // TODO: maybe we shouldn't be doing a % 33, which is slow?

        for (&keys[d], 0..) |maybe_key, i| {
            if (i + 1 < TIER_SIZE) {
                // small optimization
                @prefetch(&keys[d][i + 1], .{ .rw = .read, .locality = 1, .cache = .data });
            }

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
    ///
    /// Does NOT handle quadrant fallback case; asserts `depth` is high enough.
    pub fn allocateSlot(key: DepthCoordinate) *Chunk {
        std.debug.assert(!isHorizonDepth(key.depth)); // should've gone to quadrant fallback ):
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
    pub fn insert(key: DepthCoordinate, chunk: Chunk) *const Chunk {
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

/// Applies deterministic holes based on coordinate and depth (in `DepthCoordinate`). Also modifies some block types.
pub fn applyAncestorLogic(sprite: Sprite, key: DepthCoordinate, bx: u4, by: u4) Sprite {
    // TODO: pass chunk seeds here.
    if (sprite.isEmpty()) return .none;
    if (sprite == .ceiling_flower) return .none;
    if (sprite == .spiral_plant) return .spiral_plant;
    // TODO: consolidate visual variations to be factored in with seed for mushrooms.
    if (sprite == .mushroom) return if ((bx % 4 == 1 or bx % 4 == 2) and by % 4 == 3) .mushroom_big else .none;
    if (sprite == .edge_stone) return .edge_stone;
    if (!sprite.isFoundation()) return .none; // Fallthrough case! Make the ancestor nothing instead.

    // naive code for testin'
    var hasher = std.hash.Wyhash.init(key.depth);
    std.hash.autoHash(&hasher, key.quadrant);
    // std.hash.autoHash(&hasher, key.suffix[0]);
    // std.hash.autoHash(&hasher, key.suffix[1]);
    std.hash.autoHash(&hasher, key.suffix); // hashing logic in std preserves vector order, this is okay
    std.hash.autoHash(&hasher, @as(u8, by) * 4 + @as(u8, bx));
    const noise = hasher.final();

    // chance for hole!
    if (noise <= seeding.oddsNum(0.2)) {
        return .none;
    }
    // alternate funny test pattern
    // if ((bx ^ by) & 4 == 3) {
    //     return .none;
    // }

    if (sprite == .mossy_stone) return .spiral_plant;
    if (sprite == .blue_strange_stone) return .blue_stone;
    if (sprite == .purple_strange_stone) return .red_stone;
    if (sprite == .lava_stone) return .red_stone;
    if (sprite == .red_stone) return .redder_stone;
    if (sprite == .redder_stone) return .lava_stone;
    return sprite;
}

/// Traces the lineage of a single block type. Target depth is described in the `DepthCoordinate`.
pub fn getInheritedMaterial(key: DepthCoordinate, bx: u4, by: u4) Sprite {
    const target_depth = key.depth;
    // Hard check for the world floor.
    // This MUST happen before isHorizonDepth to allow bootstrapping at D=34.
    if (target_depth == STARTING_ZOOM_TIMES) {
        const new_key = DepthCoordinate{
            .suffix = key.suffix,
            .quadrant = @intCast(key.quadrant),
            .depth = target_depth,
        };
        const block_idx = (@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx;

        if (world.mod_store.get(key)) |modified| return modified.blocks[block_idx].id;
        if (AncestorCache.get(key)) |cached| return cached.blocks[block_idx].id;

        const slot = AncestorCache.allocateSlot(key);
        world.generateBaseChunk(slot, new_key.asCoord());
        return slot.blocks[block_idx].id;
    }

    if (isHorizonDepth(target_depth)) {
        return world.getBlockIdAt(key.asCoord(), bx, by, target_depth);
    }

    const new_key = DepthCoordinate{
        .suffix = key.suffix,
        .quadrant = @intCast(key.quadrant),
        .depth = target_depth,
    };
    const block_idx = (@as(usize, by) << memory.CHUNK_SIZE_LOG2) | bx;

    if (world.mod_store.get(key)) |modified| return modified.blocks[block_idx].id;
    if (AncestorCache.get(key)) |cached| return cached.blocks[block_idx].id;

    const p = getParentInfo(new_key, bx, by);
    const parent_sprite = getInheritedMaterial(p.coord.asDepthCoordinate(target_depth - 1), p.bx, p.by);

    return applyAncestorLogic(parent_sprite, new_key, bx, by);
}

/// Fetches a 6x6 neighborhood of parent IDs for the generator. Requires a specific depth and location.
pub fn getAncestorNeighborhood(key: DepthCoordinate) [6][6]Sprite {
    var result: [6][6]Sprite = undefined;
    const parent_depth = key.depth - 1;
    std.debug.assert(parent_depth >= STARTING_ZOOM_TIMES);

    const p_info_origin = getParentInfo(key, 0, 0);
    const start_px: i32 = @as(i32, @intCast(p_info_origin.bx)) - 1;
    const start_py: i32 = @as(i32, @intCast(p_info_origin.by)) - 1;

    for (0..6) |y_idx| {
        for (0..6) |x_idx| {
            const lx = start_px + @as(i32, @intCast(x_idx));
            const ly = start_py + @as(i32, @intCast(y_idx));
            const chunk_off_x = @divFloor(lx, memory.CHUNK_SIZE);
            const chunk_off_y = @divFloor(ly, memory.CHUNK_SIZE);

            const target_nc = p_info_origin.coord.moveAtDepth(.{ chunk_off_x, chunk_off_y }, parent_depth) orelse {
                // World boundary only exists at the generation floor.
                if (parent_depth == STARTING_ZOOM_TIMES) {
                    result[y_idx][x_idx] = .edge_stone;
                } else {
                    // This is unreachable in rebasing depths (>32).
                    result[y_idx][x_idx] = .none;
                }
                continue;
            };

            result[y_idx][x_idx] = getInheritedMaterial(
                target_nc.asDepthCoordinate(parent_depth),
                @intCast(@mod(lx, memory.CHUNK_SIZE)),
                @intCast(@mod(ly, memory.CHUNK_SIZE)),
            );
        }
    }
    return result;
}
