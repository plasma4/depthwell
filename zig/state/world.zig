//! Defines the architecture of the fractal world, contains cache data, and some ore definitions.
const std = @import("std");
const root = @import("../root.zig");
const SegmentedList = root.SegmentedList;
const Sprite = root.Sprite;
const utils = root.utils;
const types = root.types;
const memory = root.memory;
const logger = root.logger;
const seeding = root.seeding;
const procedural = root.procedural;
const player = root.player;

const Vec2i = memory.Vec2i;
const Vec2u = memory.Vec2u;
const Vec2f = memory.Vec2f;
const Chunk = memory.Chunk;
const Block = memory.Block;
const Coordinate = memory.Coordinate;
const ChunkSeeds = seeding.ChunkSeeds;

const STARTING_ZOOM_TIMES = root.startup.STARTING_ZOOM_TIMES;
const HORIZON_DEPTH = memory.HORIZON_DEPTH;
const CHUNK_SIZE = memory.CHUNK_SIZE;
const CHUNK_SIZE_SQ = memory.CHUNK_SIZE_SQ;
const CHUNK_SIZE_FLOAT = memory.CHUNK_SIZE_FLOAT;
const CHUNK_SIZE_LOG2 = memory.CHUNK_SIZE_LOG2;
const ZOOM_FACTOR = memory.ZOOM_FACTOR;

/// Stores and handles modifications of chunks. Functions across depths.
pub const ModificationStore = struct {
    /// `HashMap`-based system to store indexes to `history`.
    index: std.HashMap(
        DepthCoordinate,
        usize,
        DepthCoordinateContext,
        std.hash_map.default_max_load_percentage,
    ),
    /// TODO: evaluate if this is slow, and if `Arraylist` would fit better for native?
    /// Or maybe it's too slow even for WASM?
    history: SegmentedList(Chunk, 128) = .{},

    pub fn init(allocator: std.mem.Allocator) ModificationStore {
        return .{
            .index = std.HashMap(
                DepthCoordinate,
                usize,
                DepthCoordinateContext,
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
        };
    }

    /// Gets an existing modification for reading.
    pub fn get(self: *const @This(), key: DepthCoordinate) ?*const Chunk {
        const id = self.index.get(key) orelse return null;
        return self.history.at(id);
    }

    /// Completely wipes all user modifications. Should be followed by `world.clearCaches(true)`.
    pub fn clear(self: *@This()) void {
        self.index.clearRetainingCapacity();
        self.history.clearRetainingCapacity();
    }
};

/// Stores and handles modifications of chunks across various depths.
pub var mod_store: ModificationStore = undefined;

/// Stores what location a modification with an active suffix and quadrant, as well as its depth, to easily identify it.
pub const DepthCoordinate = struct {
    /// Represents an invalid `DepthCoordinate`, which has `depth` equal to 0.
    /// Semantically equivalent to `null`.
    pub const invalid = DepthCoordinate{
        .depth = 0,
        .quadrant = undefined,
        .suffix = undefined,
    };

    /// Active suffix (stored as a vector). Should not be set manually; must call `getParent()` to decrease the depth for depths beyond `HORIZON_DEPTH`.
    /// Most likely, a "path" of accessing D->D-1->D-2->...->H will occur.
    /// You can think of the active suffix like 32 `u2` values packed together for the X and Y coordinate.
    /// This coordinate can then be merged with the correct `QuadCache` quadrant to go all the way to H.
    /// See `README.md` for more details on what D/H mean.
    suffix: Vec2u,
    /// The depth of the modification.
    depth: u64,
    /// Quadrant ID (00: NW, 1: NE, 2: SW, 3: SE).
    quadrant: u32,

    /// Checks for equality between two `DepthCoordinate` values.
    pub inline fn eql(a: DepthCoordinate, b: DepthCoordinate) bool {
        return a.depth == b.depth and a.quadrant == b.quadrant and @reduce(.And, a.suffix == b.suffix);
    }

    /// Converts any `Coordinate` to a `DepthCoordinate` at the current depth.
    pub inline fn from(coord: Coordinate) @This() {
        return .{
            .suffix = coord.suffix,
            .quadrant = @intCast(coord.quadrant),
            .depth = memory.game.depth,
        };
    }

    /// Converts a `DepthCoordinate` to a `Coordinate`, removing information about depth.
    pub inline fn asCoord(key: @This()) Coordinate {
        return .{
            .suffix = key.suffix,
            .quadrant = @intCast(key.quadrant),
        };
    }

    /// Gets the correct location of D-1, in a `DepthCoordinate` format.
    /// Handles depth decrement, acting as the `pushLayer()` "inverse" for a `DepthCoordinate`.
    pub inline fn getParent(self: @This()) @This() {
        const parent_depth = self.depth - 1;

        // No rebasing exists at or below the horizon so bit-shifting does the trick.
        if (self.depth <= memory.HORIZON_DEPTH) {
            return .{
                .suffix = self.suffix >> @splat(memory.ZOOM_LOG2),
                .depth = parent_depth,
                .quadrant = self.quadrant, // below horizon, quadrant is always 0.
            };
        }

        std.debug.assert(self.depth + memory.HORIZON_DEPTH >= memory.game.depth); // can't go to D-33

        // Rebase case! child_depth is larger than the horizon (> 32).
        // Recover the exact 3-bit rebase origin mapped to THIS depth transition.
        const origin_x = quad_cache.getOriginX(self.depth);
        const origin_y = quad_cache.getOriginY(self.depth);

        // The absolute cell within the parent QuadCache uses BOTH the origin offset AND the child's quadrant.
        const child_qx = self.quadrant % 2;
        const child_qy = self.quadrant / 2;

        const cell_x = origin_x + child_qx;
        const cell_y = origin_y + child_qy;

        // Parent quadrant is the macro-cell this child belonged to.
        const parent_qx = cell_x / ZOOM_FACTOR;
        const parent_qy = cell_y / ZOOM_FACTOR;
        const parent_quadrant: u32 = @intCast(parent_qx + parent_qy * 2);

        // The top bits that "fell off" are the remainder!
        const top_x = cell_x % ZOOM_FACTOR;
        const top_y = cell_y % ZOOM_FACTOR;

        // Effectively, take bottom 4 bits of top X/Y, and add in the 62 significant bits of the original suffix at the bottom.
        const shift: u6 = 64 - memory.ZOOM_LOG2;
        const px = (top_x << shift) | (self.suffix[0] >> memory.ZOOM_LOG2);
        const py = (top_y << shift) | (self.suffix[1] >> memory.ZOOM_LOG2);

        return .{
            .suffix = .{ px, py },
            .depth = parent_depth,
            .quadrant = parent_quadrant,
        };
    }
};

/// Context for the `DepthCoordinate` (providing hashing and equality checks).
pub const DepthCoordinateContext = struct {
    /// Basic hash function for modifications. Equality is checked if hashes are identical as a fallback.
    pub inline fn hash(self: @This(), key: DepthCoordinate) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(key.depth);
        // Hash exact fields explicitly to avoid padding ambiguities
        std.hash.autoHash(&hasher, key.quadrant);
        std.hash.autoHash(&hasher, key.suffix);
        return hasher.final();
    }

    /// Checks for equality between two `DepthCoordinate` values.
    pub inline fn eql(self: @This(), a: DepthCoordinate, b: DepthCoordinate) bool {
        _ = self;
        return a.depth == b.depth and a.quadrant == b.quadrant and @reduce(.And, a.suffix == b.suffix);
    }
};

/// Width of the simulation buffer.
const SIM_BUFFER_WIDTH = 16;
/// Represents log2(SIM_BUFFER_WIDTH).
const SIM_WIDTH_LOG2 = std.math.log2(SIM_BUFFER_WIDTH);
/// Size of the chunk cache (can be an arbitrarily adjusted constant).
/// Calculating new chunks is very expensive, but logic uses a naive linear scan for every chunk cache access.
const CHUNK_CACHE_SIZE = 128;
/// Size of the seed cache (can be an arbitrarily adjusted constant).
/// Calculating new seeds can be somewhat expensive, but logic uses a naive linear scan for every seed access.
const SEED_CACHE_SIZE = 32;

/// Size of the simulation buffer (`SIM_BUFFER_WIDTH` squared).
const SIM_BUFFER_SIZE = SIM_BUFFER_WIDTH * SIM_BUFFER_WIDTH;
/// Total size of the chunk pool, which is in one contiguous memory block (simulation and cache buffer size added together).
const CHUNK_POOL_SIZE = SIM_BUFFER_SIZE + CHUNK_CACHE_SIZE;

/// A combined pool of SimBuffer and chunk cache data.
var chunk_pool: [CHUNK_POOL_SIZE]Chunk = undefined;

const _ = {
    if (!std.math.isPowerOfTwo(SIM_BUFFER_WIDTH)) @compileError("Sim buffer width must be a positive power of 2.");
};

/// The simulation buffer containing 16x16 chunks, centered around the player.
pub const SimBuffer = struct {
    /// Size of the outside ring `background_generation_tick` uses.
    const RING_SIZE = 68;
    const RING_OFFSETS = blk: {
        var offs: [RING_SIZE]Vec2i = undefined;
        var i: usize = 0;
        // Top and bottom rows (18 chunks each)
        var x: i64 = -9;
        while (x <= 8) : (x += 1) {
            offs[i] = .{ x, -9 };
            i += 1;
            offs[i] = .{ x, 8 };
            i += 1;
        }
        // Left and right columns (16 chunks each, avoiding corners already covered)
        var y: i64 = -8;
        while (y <= 7) : (y += 1) {
            offs[i] = .{ -9, y };
            i += 1;
            offs[i] = .{ 8, y };
            i += 1;
        }
        break :blk offs;
    };
    var bg_scan_id: usize = 0;

    const sim_buffer_ptr: *[SIM_BUFFER_SIZE]Chunk = chunk_pool[CHUNK_CACHE_SIZE..][0..SIM_BUFFER_SIZE];
    var keys: [SIM_BUFFER_SIZE]?Coordinate = [_]?Coordinate{null} ** SIM_BUFFER_SIZE;

    /// The coordinate corresponding to the chunk at the "logical" (0, 0) of the 16x16 window.
    var origin: ?Coordinate = null;
    var ring_x: u4 = 0;
    var ring_y: u4 = 0;

    /// Mask for the 16x16 buffer.
    const SIM_MASK = SIM_BUFFER_WIDTH - 1;

    /// Attempts to retrieve a chunk from the buffer, returning `null` if non-existent.
    pub fn get(coord: Coordinate) ?*Chunk {
        const og = origin orelse return null;
        if (coord.quadrant != og.quadrant) {
            return null;
        }

        const dx = coord.suffix[0] -% og.suffix[0];
        const dy = coord.suffix[1] -% og.suffix[1];

        if ((dx | dy) < SIM_BUFFER_WIDTH) {
            const id = getIndex(@intCast(dx), @intCast(dy));
            if (keys[id]) |k| {
                if (k.eql(coord)) return &sim_buffer_ptr[id];
            }
        }
        return null;
    }

    /// Returns the internal index into the chunk array.
    pub inline fn getIndex(cx: u4, cy: u4) usize {
        const rx = (ring_x +% cx) & SIM_MASK;
        const ry = (ring_y +% cy) & SIM_MASK;
        return (@as(usize, ry) << SIM_WIDTH_LOG2) | rx;
    }

    /// Clears the whole `SimBuffer`, invalidating previous data.
    pub inline fn clear() void {
        @memset(&keys, null);
        origin = null;
        ring_x = 0;
        ring_y = 0;
    }

    /// Helper to safely step an origin coordinate, returning the furthest possible coordinate
    /// if a game boundary is hit (when Coordinate.move returns null).
    fn getClampedMove(coord: Coordinate, dx: i64, dy: i64) Coordinate {
        // Fast path: attempt direct move
        if (coord.move(.{ dx, dy })) |target| return target;

        // Slow path: step-clamping (only for hard world boundaries)
        var curr = coord;
        inline for (.{ 0, 1 }) |axis| {
            var remaining = if (axis == 0) dx else dy;
            while (remaining != 0) {
                const step = std.math.sign(remaining);
                const next = if (axis == 0) curr.moveX(step) else curr.moveY(step);
                if (next) |n| {
                    curr = n;
                    remaining -= step;
                } else break;
            }
        }
        return curr;
    }

    /// Synchronizes the buffer to center on the provided coordinate/position.
    /// Safely handles shifts exceeding 1 chunk per frame via `shift`.
    pub fn sync(coord: Coordinate, shift: Vec2i) void {
        const og = origin orelse {
            fullRefresh(getClampedMove(coord, -8, -8));
            return;
        };

        // Use shift directly for incremental updates if distance is small
        if (@abs(shift[0]) < SIM_BUFFER_WIDTH and @abs(shift[1]) < SIM_BUFFER_WIDTH) {
            if (shift[0] != 0 or shift[1] != 0) {
                incrementalRefresh(shift[0], shift[1]);
            }
            return;
        }

        // Teleport or large jump fallback
        const target_origin = getClampedMove(coord, -8, -8);
        if (!og.eql(target_origin)) fullRefresh(target_origin);
    }

    fn fullRefresh(new_origin: Coordinate) void {
        origin = new_origin;
        ring_x = 0;
        ring_y = 0;

        for (0..SIM_BUFFER_WIDTH) |cy| {
            for (0..SIM_BUFFER_WIDTH) |cx| {
                const id = (cy << SIM_WIDTH_LOG2) | cx;
                if (new_origin.move(.{ @intCast(cx), @intCast(cy) })) |cell_coord| {
                    keys[id] = cell_coord;
                    writeChunkSkip(&sim_buffer_ptr[id], cell_coord);
                } else {
                    keys[id] = null;
                }
            }
        }
    }

    fn incrementalRefresh(dx: i64, dy: i64) void {
        const old_origin = origin.?;
        const new_origin = getClampedMove(old_origin, dx, dy);
        origin = new_origin;

        ring_x = @intCast((@as(u32, ring_x) +% @as(u32, @bitCast(@as(i32, @intCast(dx))))) & SIM_MASK);
        ring_y = @intCast((@as(u32, ring_y) +% @as(u32, @bitCast(@as(i32, @intCast(dy))))) & SIM_MASK);

        const adx: usize = @intCast(@abs(dx));
        const ady: usize = @intCast(@abs(dy));

        // Refresh new columns
        if (dx != 0) {
            for (0..SIM_BUFFER_WIDTH) |cy_log| {
                for (0..adx) |i| {
                    // New columns are at the leading edge in the direction of travel
                    const cx_log: u4 = if (dx > 0)
                        @intCast(SIM_BUFFER_WIDTH - adx + i)
                    else
                        @intCast(i);
                    const id = getIndex(@intCast(cx_log), @intCast(cy_log));
                    if (new_origin.move(.{ @intCast(cx_log), @intCast(cy_log) })) |cell_coord| {
                        keys[id] = cell_coord;
                        writeChunkSkip(&sim_buffer_ptr[id], cell_coord);
                    } else {
                        keys[id] = null;
                    }
                }
            }
        }

        // Refresh new rows (avoid double-refreshing corners)
        if (dy != 0) {
            for (0..SIM_BUFFER_WIDTH) |cx_log| {
                for (0..ady) |i| {
                    const cy_log: u4 = if (dy > 0)
                        @intCast(SIM_BUFFER_WIDTH - ady + i)
                    else
                        @intCast(i);
                    const id = getIndex(@intCast(cx_log), @intCast(cy_log));
                    if (new_origin.move(.{ @intCast(cx_log), @intCast(cy_log) })) |cell_coord| {
                        keys[id] = cell_coord;
                        writeChunkSkip(&sim_buffer_ptr[id], cell_coord);
                    } else {
                        keys[id] = null;
                    }
                }
            }
        }
    }

    /// Background caching heuristic: scans the boundary immediately outside the 16x16 chunk in the
    /// direction of movement and creates it in `ChunkCache` before the player reaches it.
    ///
    /// Fairly naive, generating `default_amount` chunks when called (suggested value of 1-2).
    /// It is recommended to set a higher `max_amount` (so more budget is available in high-velocity falling situations).
    pub fn precacheChunks(
        player_coord: Coordinate,
        velocity: Vec2f,
        default_amount: comptime_int,
        max_amount: comptime_int,
    ) void {
        if (default_amount < 1 or max_amount < 1) {
            @compileError("Amount of chunks to generate in the background must be positive!");
        }
        const game = &memory.game;
        var generated_count: u32 = 0;

        // Determine primary sweep direction based on highest absolute velocity
        const vx = velocity[0];
        const vy = velocity[1];
        const budget: u32 = if (vx * vx + vy * vy < 500.0) default_amount else max_amount;

        // Priority target based on movement
        const tx: i64 = if (vx > 1.0) 8 else if (vx < -1.0) -9 else (if (game.frame % 2 == 0) @as(i64, 8) else -9);
        const ty: i64 = if (vy > 1.0) 8 else if (vy < -1.0) -9 else 8; // Default downward for gravity

        // Check the three chunks in the primary direction of travel
        const targets = if (@abs(vy) > @abs(vx))
            [_]Vec2i{ .{ 0, ty }, .{ -1, ty }, .{ 1, ty } } // Vertical lead
        else
            [_]Vec2i{ .{ tx, 0 }, .{ tx, -1 }, .{ tx, 1 } }; // Horizontal lead

        for (targets) |off| {
            if (generated_count >= budget) break;
            if (player_coord.move(off)) |c| {
                if (get(c) == null and ChunkCache.findIndex(c) == null) {
                    const slot = ChunkCache.allocateIndex(c);
                    generateChunk(&ChunkCache.chunks[slot], c.asDepthCoordinate(memory.game.depth));
                    generated_count += 1;
                }
            }
        }

        // Standard ring sweep for remaining budget
        var checked: usize = 0;
        while (generated_count < budget and checked < RING_SIZE) : (checked += 1) {
            const off = RING_OFFSETS[bg_scan_id];
            bg_scan_id = (bg_scan_id + 1) % RING_SIZE;
            if (player_coord.move(off)) |c| {
                if (get(c) == null and ChunkCache.findIndex(c) == null) {
                    const slot = ChunkCache.allocateIndex(c);
                    generateChunk(&ChunkCache.chunks[slot], c.asDepthCoordinate(memory.game.depth));
                    generated_count += 1;
                }
            }
        }
    }
};

/// A static cache that caches chunks when a generation is attempted.
pub const ChunkCache = struct {
    /// Keys storing `Coordinate` values; index points to a chunk in `chunks` at the current depth.
    var keys: [CHUNK_CACHE_SIZE]?Coordinate = [_]?Coordinate{null} ** CHUNK_CACHE_SIZE;
    /// Chunks referenced by `keys` at the current depth.
    var chunks: *[CHUNK_CACHE_SIZE]Chunk = chunk_pool[0..CHUNK_CACHE_SIZE];

    /// Data for clock data structure implementation.
    var clock_bits: std.StaticBitSet(CHUNK_CACHE_SIZE) = std.StaticBitSet(CHUNK_CACHE_SIZE).initEmpty();
    /// Where the hand is located in the clock data structure.
    var hand: usize = 0;

    /// Finds the index of a `Coordinate` in the cache, marking it as "recently used".
    /// Returns `CHUNK_CACHE_SIZE` in place of `null`.
    pub inline fn findIndex(coord: Coordinate) ?usize {
        for (&keys, 0..) |maybe_key, i| {
            if (maybe_key) |k| {
                if (k.eql(coord)) {
                    clock_bits.set(i);
                    return i;
                }
            }
        }
        return null;
    }

    /// Evicts an entry using the clock algorithm and returns the index for the new coordinate.
    pub inline fn allocateIndex(coord: Coordinate) usize {
        while (true) {
            const id = hand;
            hand = (hand + 1) % CHUNK_CACHE_SIZE;

            if (clock_bits.isSet(id)) {
                clock_bits.setValue(id, false);
            } else {
                keys[id] = coord;
                clock_bits.set(id);
                return id;
            }
        }
    }

    /// Clears the whole `ChunkCache`, invalidating previous data.
    pub inline fn clear() void {
        @memset(&keys, null);
        clock_bits = std.StaticBitSet(CHUNK_CACHE_SIZE).initEmpty();
        hand = 0;
    }
};

/// UNUSED DUE TO BEING UNNECESSARY. Adds 1 to the `path` as if the `ArrayList` represented one giant number.
/// Performs allocation; the caller should deinit the path eventually using `arena`.
fn carryPath(path: *const std.ArrayList(u64)) std.ArrayList(u64) {
    const new_path = path.clone(alloc) catch @panic("carry alloc for QuadCache coordinates failed");
    // arena.reset(.retain_capacity);
    var carry: u1 = 1;

    for (new_path.items) |*word| {
        const add_res = @addWithOverflow(word.*, @as(u64, carry));
        word.* = add_res[0];
        carry = add_res[1];

        if (carry == 0) break;
    }

    // If we still have a carry after the loop, the coordinate grew.
    // However, this is NOT POSSIBLE because the quadrant logic should specifically disallow this.
    if (carry == 1) {
        unreachable;
    }

    return new_path;
}

const QuadrantEdgeDetails = struct {
    most_top: bool,
    most_bottom: bool,
    most_left: bool,
    most_right: bool,
};

/// A static 2x2 grid of seeds only updated when depth increases or game startup. See `README.md` for a more detailed and intuitive explanation for what this does.
pub const QuadCache = struct {
    pub const PATH_PREALLOC_SIZE = 256;

    /// The 512-bit hashes for the 4 active quadrants (sequentially from D to D-31).
    /// (0: NW, 1: NE, 2: SW, 3: SE)
    path_hashes: ChunkSeeds align(memory.MAIN_ALIGN_BYTES),
    /// The 4-by-4 material grid representing the "event horizon" at D-32.
    /// The inner 2-by-2 (indices [1..2][1..2]) corresponds to the active quadrants.
    ancestor_materials: [4][4]Block,
    /// A list representing the prefix stack of the top left quadrant's X-coordinate.
    left_path: SegmentedList(u64, PATH_PREALLOC_SIZE),
    /// A list representing the prefix stack of the top left quadrant's Y-coordinate.
    top_path: SegmentedList(u64, PATH_PREALLOC_SIZE),

    // These 4 properties are used to determine if a QuadCache is at the very edge of the world for chunk gen/zooming in.
    most_top: bool = true,
    most_bottom: bool = true,
    most_left: bool = true,
    most_right: bool = true,

    /// Direct-mapped cache for chunk seeds for BLAKE3 hashing.
    /// If depth = 0, then it's implied to be `undefined`.
    seed_cache_keys: [SEED_CACHE_SIZE]DepthCoordinate = [_]DepthCoordinate{DepthCoordinate.invalid} ** SEED_CACHE_SIZE,
    /// Cached seed values corresponding to seed_cache_keys.
    seed_cache_values: [SEED_CACHE_SIZE]seeding.ChunkSeeds = undefined,
    /// Data for clock data structure implementation specifically for seeds.
    seed_clock_bits: std.StaticBitSet(SEED_CACHE_SIZE) = std.StaticBitSet(SEED_CACHE_SIZE).initEmpty(),
    /// Where the hand is located in the seed cache clock data structure.
    seed_hand: usize = 0,

    // /// Returns the X-coordinate path of a specific quadrant. Unreachable call if path is empty (if depth is not > HORIZON_DEPTH). Call `cleanup_path` afterward.
    // pub inline fn getQuadrantPathX(self: *const @This(), quadrant: u2) std.ArrayList(u64) {
    //     return if (quadrant % 2 == 0) self.left_path else carryPath(&self.left_path);
    // }

    // /// Returns the Y-coordinate path of a specific quadrant. Unreachable call if path is empty (if depth is not > HORIZON_DEPTH). Call `cleanup_path` afterward.
    // pub inline fn getQuadrantPathY(self: *const @This(), quadrant: u2) std.ArrayList(u64) {
    //     return if (quadrant < 2) self.top_path else carryPath(&self.top_path);
    // }

    // /// Deallocates a temporary instance of a QuadCache path. (THIS DOESN'T WORK WITH ARENA)
    // pub inline fn cleanupPath(self: *const @This(), path: std.ArrayList(u64)) void {
    //     // Memory comparison is safe because QuadCache will never be de-initialized, top_left_path is always non-empty (so nothing weird), and there's no multicore/async shenanigans here.
    //     if (self.left_path.items.ptr != path.items.ptr and self.top_path.items.ptr != path.items.ptr) {
    //         path.deinit(arena);
    //     }
    // }

    /// Gets the rebase origin X for a given depth (which is asserted to be > `HORIZON_DEPTH`).
    pub inline fn getOriginX(self: *const @This(), depth: u64) u64 {
        std.debug.assert(depth > memory.HORIZON_DEPTH);
        const idx = depth - memory.HORIZON_DEPTH - 1;
        const slot: usize = @intCast(idx / 21);
        const shift: u6 = @intCast((idx % 21) * 3);
        return (self.left_path.at(slot).* >> shift) & 7;
    }

    /// Gets the rebase origin X for a given depth (which is asserted to be > `HORIZON_DEPTH`).
    pub inline fn getOriginY(self: *const @This(), depth: u64) u64 {
        std.debug.assert(depth > memory.HORIZON_DEPTH);
        const idx = depth - memory.HORIZON_DEPTH - 1;
        const slot: usize = @intCast(idx / 21);
        const shift: u6 = @intCast((idx % 21) * 3);
        return (self.top_path.at(slot).* >> shift) & 7;
    }

    /// Gets the `ancestor_materials` sprite for a specific quadrant.
    /// Asserts the current game depth is large enough for ancestor materials to be valid.
    ///
    /// Effectively returns the ancestor block type when `isHorizonDepth()` is true.
    pub inline fn getQuadrantSpriteAncestor(self: *const @This(), quadrant: u2) Sprite {
        std.debug.assert(memory.game.depth > HORIZON_DEPTH);
        return self.ancestor_materials[1 + (quadrant >> 1)][1 + quadrant % 2];
    }

    /// Returns the 512-bit seed of a specified quadrant (or the global seed if the current depth is <= HORIZON_DEPTH).
    pub inline fn getQuadrantSeed(self: *const @This(), quadrant: u2, depth: u64) seeding.Seed {
        if (depth <= HORIZON_DEPTH) return memory.game.seed;
        return self.path_hashes[quadrant];
    }

    /// Resolves the chunk seeds. If depth > 32, uses the quadrant seeds.
    /// Uses a direct-mapped cache to optimize fractal generation and boundary checks.
    pub inline fn getChunkSeeds(self: *@This(), key: DepthCoordinate) ChunkSeeds {
        for (&self.seed_cache_keys, 0..) |cache_key, i| {
            if (cache_key.depth != 0 and cache_key.eql(key)) {
                self.seed_clock_bits.set(i);
                return self.seed_cache_values[i];
            }
        }

        const seed = self.getQuadrantSeed(@intCast(key.quadrant), key.depth);
        const chunk_seeds = seeding.mixChunkSeeds(
            &seed,
            key.suffix,
            key.depth,
        );

        // Evict an entry using the clock algorithm and store the new result to prevent re-hashing.
        while (true) {
            const id = self.seed_hand;
            self.seed_hand = (self.seed_hand + 1) % SEED_CACHE_SIZE;

            if (self.seed_clock_bits.isSet(id)) {
                self.seed_clock_bits.setValue(id, false);
            } else {
                self.seed_cache_keys[id] = key;
                self.seed_cache_values[id] = chunk_seeds;
                self.seed_clock_bits.set(id);
                return chunk_seeds;
            }
        }
    }

    /// Returns details on a specific quadrant and what "edges" of the world it touches.
    pub inline fn getQuadrantEdgeDetails(self: *const @This(), quadrant: u2, depth: u64) QuadrantEdgeDetails {
        // Quadrant IDs for reference: 00: NW, 1: NE, 2: SW, 3: SE
        if (depth <= HORIZON_DEPTH) {
            return .{
                .most_top = true,
                .most_bottom = true,
                .most_left = true,
                .most_right = true,
            };
        }
        return .{
            .most_top = quadrant < 2 and self.most_top,
            .most_bottom = quadrant >= 2 and self.most_bottom,
            .most_left = (quadrant % 2 == 0) and self.most_left,
            .most_right = (quadrant % 2 == 1) and self.most_right,
        };
    }
};

/// The QuadCache that stores information about the 4 quadrants and their seeds.
pub var quad_cache: QuadCache = .{
    .path_hashes = undefined,
    .left_path = SegmentedList(u64, QuadCache.PATH_PREALLOC_SIZE){}, // easiest to do prealloc with larger stack size in case
    .top_path = SegmentedList(u64, QuadCache.PATH_PREALLOC_SIZE){},
    .ancestor_materials = undefined,
};

/// Represents the answer to the question "what is the largest possible suffix value"?
/// 15 at depth 1, 255 at depth 2, capped at 2**64-1 at depth 16 and beyond.
pub var max_possible_suffix: u64 = 0;

/// Gets the maximum possible suffix at a certain depth (see `max_possible_suffix` for details on meaning).
pub inline fn getMaxSuffixAtDepth(depth: u64) u64 {
    if (depth >= memory.HORIZON_DEPTH) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(depth * memory.ZOOM_LOG2)) - 1;
}

/// `ArenaAllocator` instance used for the world.
pub var arena = memory.makeArena();
/// Allocator used for the world.
pub var alloc = arena.allocator();

/// TODO: convert this mess of functions to use a comptime-based flags system.
/// Creates a new instance of a `Chunk` where specified, given a coordinate. Copies over from cache if possible.
pub fn writeChunk(chunk: *Chunk, coord: Coordinate) void {
    if (SimBuffer.get(coord)) |cached_ptr| {
        chunk.* = cached_ptr.*;
        return;
    }

    if (ChunkCache.findIndex(coord)) |i| {
        chunk.* = ChunkCache.chunks[i];
        return;
    }

    const slot_index = ChunkCache.allocateIndex(coord);
    const key = DepthCoordinate.from(coord);

    if (mod_store.get(key)) |modified_chunk| {
        // Modified state!
        ChunkCache.chunks[slot_index].blocks = modified_chunk.*.blocks;
    } else { // generate procedurally
        generateChunk(&ChunkCache.chunks[slot_index], coord.asDepthCoordinate(memory.game.depth));
    }

    chunk.* = ChunkCache.chunks[slot_index];
}

/// Same as `write_chunk`, but avoids checking `SimBuffer` first.
pub fn writeChunkSkip(chunk: *Chunk, coord: Coordinate) void {
    if (ChunkCache.findIndex(coord)) |i| {
        chunk.* = ChunkCache.chunks[i];
        return;
    }

    const slot_index = ChunkCache.allocateIndex(coord);
    const key = DepthCoordinate.from(coord);

    if (mod_store.get(key)) |modified_chunk| {
        // Modified state!
        ChunkCache.chunks[slot_index].blocks = modified_chunk.*.blocks;
    } else { // generate procedurally
        generateChunk(&ChunkCache.chunks[slot_index], coord.asDepthCoordinate(memory.game.depth));
    }

    chunk.* = ChunkCache.chunks[slot_index];
}

/// Same as `write_chunk`, but avoids checking `mod_store`.
pub fn writeChunkModless(chunk: *Chunk, coord: Coordinate) void {
    if (SimBuffer.get(coord)) |cached_ptr| {
        chunk.* = cached_ptr.*;
        return;
    }

    if (ChunkCache.findIndex(coord)) |i| {
        chunk.* = ChunkCache.chunks[i];
        return;
    }

    const slot_index = ChunkCache.allocateIndex(coord);
    const key = DepthCoordinate.from(coord);
    generateChunk(&ChunkCache.chunks[slot_index], key);
    chunk.* = ChunkCache.chunks[slot_index];
}

/// Gets a new instance of a `Chunk` at the current depth. Does not update edge flags.
pub inline fn getChunk(coord: Coordinate) Chunk {
    var chunk: Chunk = undefined;
    writeChunk(&chunk, coord);
    return chunk;
}

/// Internal function to generate a whole chunk (considering modifications), given a pointer to where the chunk should be stored and coordinates.
///
/// Does not go through the cache, as its goal is to generate chunks from scratch; branches into base procedural generation or fractal scaling depending on depth.
/// Internal function to generate a whole chunk (considering modifications), given a pointer to where the chunk should be stored and coordinates.
pub fn generateChunk(chunk: *Chunk, key: DepthCoordinate) void {
    if (key.depth == STARTING_ZOOM_TIMES) {
        generateBaseChunk(chunk, key.asCoord());
        return;
    }

    const chunk_seeds = quad_cache.getChunkSeeds(key);
    var rng4 = seeding.ChaCha12.init(chunk_seeds[3]);

    const parent_neighborhood = root.ancestor.getAncestorNeighborhood(key);
    for (0..CHUNK_SIZE) |block_y| {
        for (0..CHUNK_SIZE) |block_x| {
            const id = block_x + block_y * CHUNK_SIZE;

            const py = (block_y / ZOOM_FACTOR) + 1;
            const px = (block_x / ZOOM_FACTOR) + 1;

            const parent_sprite = parent_neighborhood[py][px];

            // Extract the 8 neighbors from our 6x6 parent neighborhood matrix
            const neighbors: [8]Block align(8) = .{
                parent_neighborhood[py - 1][px - 1],
                parent_neighborhood[py - 1][px],
                parent_neighborhood[py - 1][px + 1],
                parent_neighborhood[py][px - 1],
                parent_neighborhood[py][px + 1],
                parent_neighborhood[py + 1][px - 1],
                parent_neighborhood[py + 1][px],
                parent_neighborhood[py + 1][px + 1],
            };

            const final_sprite = root.ancestor.applyAncestorLogic(
                parent_sprite,
                neighbors,
                key,
                @intCast(block_x),
                @intCast(block_y),
            );
            chunk.blocks[id] = Block.makeBasicBlock(final_sprite.id, rng4.next());
        }
    }

    addEdgeFlagsFractal(chunk, key, parent_neighborhood);
}

/// Adds edge flags for deeper depths by applying seeding logic.
fn addEdgeFlagsFractal(target_chunk: *Chunk, key: DepthCoordinate, parent_neighborhood: [6][6]Block) void {
    _ = parent_neighborhood; // No longer used for halo calculation to prevent indexing overflows
    for (0..CHUNK_SIZE) |block_y| {
        for (0..CHUNK_SIZE) |block_x| {
            const id = block_x + block_y * CHUNK_SIZE;
            const current_sprite = target_chunk.blocks[id].id;
            if (current_sprite.isEmpty()) continue;

            if (!current_sprite.isFoundation()) {
                target_chunk.blocks[id].edge_flags = 0xFF;
                continue;
            }

            var flags: u8 = 0;
            inline for (.{ -1, 0, 1 }) |dy| {
                inline for (.{ -1, 0, 1 }) |dx| {
                    if (dx == 0 and dy == 0) continue;
                    const nx = @as(i32, @intCast(block_x)) + dx;
                    const ny = @as(i32, @intCast(block_y)) + dy;

                    const block: Block = if (nx >= 0 and nx < CHUNK_SIZE and ny >= 0 and ny < CHUNK_SIZE)
                        target_chunk.blocks[@as(usize, @intCast(ny * CHUNK_SIZE + nx))]
                    else blk: {
                        // Safely resolve the coordinate of the adjacent chunk
                        const nc = key.asCoord().moveAtDepth(
                            .{ @divFloor(nx, CHUNK_SIZE), @divFloor(ny, CHUNK_SIZE) },
                            key.depth,
                        ) orelse break :blk .empty;

                        // Use inherited material lookup which handles its own neighbor-reconstruction
                        break :blk root.ancestor.getInheritedMaterial(
                            nc.asDepthCoordinate(key.depth),
                            @intCast(@mod(nx, CHUNK_SIZE)),
                            @intCast(@mod(ny, CHUNK_SIZE)),
                        );
                    };

                    if (shouldHaveEdgeFlags(block.id, current_sprite)) {
                        flags |= types.EdgeFlags.getFlagBit(dx, dy);
                    }
                }
            }
            target_chunk.blocks[id].edge_flags = flags;
        }
    }
}

/// Generates a starting chunk at depth `STARTING_ZOOM_TIMES`.
/// Is procedural and does not require all other chunks are pre-calculated.
/// As in, it does not use something like cellular noise that needs a whole map up front.
pub fn generateBaseChunk(chunk: *Chunk, coord: Coordinate) void {
    const depth = STARTING_ZOOM_TIMES;
    const chunk_seeds = quad_cache.getChunkSeeds(coord.asDepthCoordinate(depth));

    const seeds = memory.game.seed2;
    const seed_vec1: memory.Vec2u = seeds[0..2].*;
    const seed_vec2: memory.Vec2u = seeds[2..4].*;
    const seed_vec3: memory.Vec2u = seeds[4..6].*;
    const seed_vec4: memory.Vec2u = seeds[6..8].*;
    const seed_vec5: memory.Vec2u = seeds[8..10].*;
    const seed_vec6: memory.Vec2u = seeds[10..12].*;

    var rng4 = seeding.ChaCha12.init(chunk_seeds[3]); // Visual touches only.

    const suffix = coord.suffix;
    const cx = suffix[0];
    const cy = suffix[1];
    const max_suffix = getMaxSuffixAtDepth(depth);
    for (0..CHUNK_SIZE) |block_y| {
        for (0..CHUNK_SIZE) |block_x| {
            const id = block_x + block_y * CHUNK_SIZE;

            const is_absolute_edge_x =
                (cx == 0 and block_x < 2) or
                (cx == max_suffix and block_x >= (CHUNK_SIZE - 2));
            const is_absolute_edge_y =
                (cy == 0 and block_y < 2) or
                (cy == max_suffix and block_y >= (CHUNK_SIZE - 2));
            if (is_absolute_edge_x or is_absolute_edge_y) {
                chunk.blocks[id] = Block.makeBasicBlock(.edge_stone, rng4.next());
                continue;
            }

            const base_data = procedural.getBaseSpriteType(
                seed_vec1,
                seed_vec2,
                @intCast(cx),
                @intCast(cy),
                @intCast(block_x),
                @intCast(block_y),
            );
            var sprite = base_data.sprite;
            if (sprite.isStone()) sprite = procedural.addOres(
                base_data,
                seed_vec3,
                seed_vec4,
                seed_vec5,
                seed_vec6,
                @intCast(cx * 16 + block_x),
                @intCast(cy * 16 + block_y),
            );

            chunk.blocks[id] = Block.makeBasicBlock(
                sprite,
                rng4.next(),
            );
        }
    }

    addEdgeFlags(chunk, coord, depth);
    // Decorate the base chunk here so that child depths inherit the results
    var rng_decor = seeding.ChaCha12.init(quad_cache.getChunkSeeds(coord.asDepthCoordinate(depth))[0]);
    procedural.addDecorations(chunk, &rng_decor);
}

/// Adds edge flags to an already generated chunk using a stack-safe halo buffer.
/// Intentionally does NOT skip non-foundation blocks so `addDecorations()` functions for procedural logic.
fn addEdgeFlags(target_chunk: *Chunk, coord: Coordinate, depth: u64) void {
    var halo: [18][18]Sprite = undefined;

    // Fill the center 16x16 from our already generated blocks
    for (0..CHUNK_SIZE) |y| {
        for (0..CHUNK_SIZE) |x| {
            halo[y + 1][x + 1] = target_chunk.blocks[y * CHUNK_SIZE + x].id;
        }
    }

    const is_base = (depth == STARTING_ZOOM_TIMES);
    const seeds = memory.game.seed2;

    // Fill the 1-pixel border (72 pixels total)
    var hy: i32 = -1;
    while (hy <= CHUNK_SIZE) : (hy += 1) {
        var hx: i32 = -1;
        while (hx <= CHUNK_SIZE) : (hx += 1) {
            if (hx >= 0 and hx < CHUNK_SIZE and hy >= 0 and hy < CHUNK_SIZE) continue;

            const target_nc = coord.moveAtDepth(.{ @divFloor(hx, CHUNK_SIZE), @divFloor(hy, CHUNK_SIZE) }, depth) orelse {
                halo[@intCast(hy + 1)][@intCast(hx + 1)] = .none;
                continue;
            };

            const lx: u4 = @intCast(@mod(hx, CHUNK_SIZE));
            const ly: u4 = @intCast(@mod(hy, CHUNK_SIZE));

            halo[@intCast(hy + 1)][@intCast(hx + 1)] = if (is_base) blk: {
                const abs_nc = target_nc.suffix;
                const base_data = procedural.getBaseSpriteType(
                    seeds[0..2].*,
                    seeds[2..4].*,
                    @intCast(abs_nc[0]),
                    @intCast(abs_nc[1]),
                    lx,
                    ly,
                );
                var s = base_data.sprite;
                if (s.isStone()) s = procedural.addOres(
                    base_data,
                    seeds[4..6].*,
                    seeds[6..8].*,
                    seeds[8..10].*,
                    seeds[10..12].*,
                    @intCast(abs_nc[0] * 16 + lx),
                    @intCast(abs_nc[1] * 16 + ly),
                );
                break :blk s;
            } else root.ancestor.getInheritedMaterial(
                target_nc.asDepthCoordinate(depth),
                lx,
                ly,
            ).id;
        }
    }

    // Calculate flags using the static halo buffer
    for (0..CHUNK_SIZE) |y| {
        for (0..CHUNK_SIZE) |x| {
            const current_sprite = halo[y + 1][x + 1];

            var flags: u8 = 0;
            inline for (.{ -1, 0, 1 }) |dy| {
                inline for (.{ -1, 0, 1 }) |dx| {
                    if (dx == 0 and dy == 0) continue;

                    const neighbor_sprite = halo[@intCast(@as(i32, @intCast(y + 1)) + dy)][@intCast(@as(i32, @intCast(x + 1)) + dx)];

                    if (shouldHaveEdgeFlags(neighbor_sprite, current_sprite)) {
                        flags |= types.EdgeFlags.getFlagBit(dx, dy);
                    }
                }
            }
            target_chunk.blocks[y * CHUNK_SIZE + x].edge_flags = flags;
        }
    }
}

/// Returns whether a sprite should have edge flag logic applied to it.
/// Can be modified for testing as necessary; defaults to `isFoundation()`.
inline fn shouldHaveEdgeFlags(sprite: Sprite, current_sprite: Sprite) bool {
    _ = .{current_sprite};
    // return (sprite.isFoundation() and !sprite.isOre() and current_sprite.isFoundation() and !current_sprite.isOre()) or sprite == current_sprite;
    return sprite.isFoundation();
}

/// Applies a block modification, changing the `Sprite` type and resetting `hp`.
/// Mutates ModStore and caches in-place.
/// Returns whether `update_local_edge_flags` instantly removed the current block due to being in an invalid position.
pub fn modifyBlockType(coord: Coordinate, bx: u4, by: u4, new_sprite: Sprite) bool {
    const key = DepthCoordinate.from(coord);
    const id = @as(usize, by) * CHUNK_SIZE + bx;

    const entry_id = mod_store.index.get(key) orelse blk: {
        const new_id = mod_store.history.len;
        _ = mod_store.history.addOne(alloc) catch @panic("Mod history allocation failed");

        // Use a temporary buffer to avoid holding mod_store pointers during generation
        writeChunkModless(mod_store.history.at(new_id), coord);

        mod_store.index.put(key, new_id) catch @panic("Mod index insertion failed");
        break :blk new_id;
    };

    const c: *Chunk = mod_store.history.at(entry_id);
    c.blocks[id].id = new_sprite;
    c.blocks[id].hp = 0;
    // Explicitly reset edge flags to 255 for non-foundation blocks (to fix rendering artifacts)!
    const edge_flags_val: u8 = if (new_sprite.isFoundation()) 0 else 0xFF;
    c.blocks[id].edge_flags = edge_flags_val;

    if (SimBuffer.get(coord)) |sim_chunk| {
        const block: *Block = &sim_chunk.blocks[id];
        block.id = new_sprite;
        block.hp = 0;
        block.edge_flags = edge_flags_val;
    }

    if (ChunkCache.findIndex(coord)) |index| {
        const block: *Block = &ChunkCache.chunks[index].blocks[id];
        block.id = new_sprite;
        block.hp = 0;
        block.edge_flags = edge_flags_val;
    }

    return updateLocalEdgeFlags(coord, bx, by);
}

const UpdateItem = struct { coord: Coordinate, bx: u4, by: u4 };
/// Max amount of edge flags to check before exiting. If 0, never exits.
const CHECK_LIMIT = 0;
/// Dedicated worklist for local edge flag updating.
var worklist: SegmentedList(UpdateItem, 256) = .{};

/// Recalculates edge flags for a specific block its 8 neighbors. Also breaks any non-foundation blocks.
/// Returns whether the current block was removed due to being in an invalid position.
fn updateLocalEdgeFlags(coord: Coordinate, bx: u4, by: u4) bool {
    worklist.append(alloc, .{
        .coord = coord,
        .bx = bx,
        .by = by,
    }) catch @panic("Edge flags worklist failed!");
    defer worklist.clearRetainingCapacity();

    var original_block_broken = false;
    var checks_done: usize = 0; // prevent running out of memory
    while (worklist.pop()) |item| {
        if (CHECK_LIMIT != 0 and checks_done >= CHECK_LIMIT) break;
        checks_done += 1;

        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                const nx = @as(i32, item.bx) + dx;
                const ny = @as(i32, item.by) + dy;

                var target_coord = item.coord;
                if (nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE) {
                    target_coord = item.coord.move(.{ @divFloor(nx, CHUNK_SIZE), @divFloor(ny, CHUNK_SIZE) }) orelse continue;
                }

                const lbx: u4 = @intCast(@mod(nx, CHUNK_SIZE));
                const lby: u4 = @intCast(@mod(ny, CHUNK_SIZE));
                const block_id = @as(usize, lby) * CHUNK_SIZE + lbx;
                const current_block = getBlockAt(target_coord, lbx, lby, memory.game.depth);
                const current_sprite = current_block.id;

                // Cascade logic
                var broken = false;
                if (current_sprite == .mushroom) {
                    const below = if (lby < 15)
                        getBlockAt(target_coord, lbx, lby + 1, memory.game.depth).id
                    else
                        getBlockAt(target_coord.moveY(1) orelse target_coord, lbx, 0, memory.game.depth).id;
                    if (!below.isSolid()) broken = true;
                } else if (current_sprite == .ceiling_flower or current_sprite == .spiral_plant) {
                    const above = if (lby > 0)
                        getBlockAt(target_coord, lbx, lby - 1, memory.game.depth).id
                    else
                        getBlockAt(target_coord.moveY(-1) orelse target_coord, lbx, 15, memory.game.depth).id;
                    if (current_sprite == .ceiling_flower) {
                        if (!above.isSolid()) broken = true;
                    } else if (!above.isSolid() and above != .spiral_plant) broken = true;
                }

                if (broken) {
                    if (item.bx == bx and item.by == by and item.coord.eql(coord)) original_block_broken = true;
                    root.inventory.addToInventory(current_sprite);

                    // Internal block modification to avoid recursion
                    const key = DepthCoordinate.from(target_coord);
                    const mod_id = mod_store.index.get(key) orelse blk: {
                        const new_id = mod_store.history.len;
                        _ = mod_store.history.addOne(alloc) catch @panic("Failed to add to modification storage!");
                        writeChunkModless(mod_store.history.at(new_id), target_coord);
                        mod_store.index.put(key, new_id) catch @panic("Failed to put into modification storage!");
                        break :blk new_id;
                    };
                    const target_chunk: *Chunk = mod_store.history.at(mod_id);
                    target_chunk.blocks[block_id].id = .none;
                    target_chunk.blocks[block_id].edge_flags = 0xFF;

                    if (SimBuffer.get(target_coord)) |sc| {
                        sc.blocks[block_id].id = .none;
                        sc.blocks[block_id].edge_flags = 0xFF;
                    }
                    if (ChunkCache.findIndex(target_coord)) |index| {
                        ChunkCache.chunks[index].blocks[block_id].id = .none;
                        ChunkCache.chunks[index].blocks[block_id].edge_flags = 0xFF;
                    }

                    worklist.append(alloc, .{ // use append() instead of at() to prevent panics
                        .coord = target_coord,
                        .bx = lbx,
                        .by = lby,
                    }) catch @panic("Edge flags worklist failed!");
                    continue;
                }

                if (!current_sprite.isFoundation()) continue;

                // Recalculate flags for foundation blocks
                var new_flags: u8 = 0;
                inline for (.{ -1, 0, 1 }) |ndy| {
                    inline for (.{ -1, 0, 1 }) |ndx| {
                        if (ndx == 0 and ndy == 0) continue;
                        const neighbor_block = getBlockAt(
                            target_coord.move(.{
                                @divFloor(@as(i32, lbx) + ndx, CHUNK_SIZE),
                                @divFloor(@as(i32, lby) + ndy, CHUNK_SIZE),
                            }) orelse
                                target_coord,
                            @intCast(@mod(@as(i32, lbx) + ndx, CHUNK_SIZE)),
                            @intCast(@mod(@as(i32, lby) + ndy, CHUNK_SIZE)),
                            memory.game.depth,
                        );
                        if (shouldHaveEdgeFlags(neighbor_block.id, current_sprite)) {
                            new_flags |= types.EdgeFlags.getFlagBit(ndx, ndy);
                        }
                    }
                }

                if (SimBuffer.get(target_coord)) |c| c.blocks[block_id].edge_flags = new_flags;
                if (ChunkCache.findIndex(target_coord)) |index| {
                    ChunkCache.chunks[index].blocks[block_id].edge_flags = new_flags;
                }
                const m_key = DepthCoordinate.from(target_coord);
                if (mod_store.index.get(m_key)) |id| {
                    mod_store.history.at(id).blocks[block_id].edge_flags = new_flags;
                }
            }
        }
    }

    return original_block_broken;
}

/// Increases a block's `hp` by a specified amount (making it more mined).
/// If the new `hp` becomes larger than 15, the sprite is mined.
/// If `hp_to_add` is 0, the sprite is instantly mined. Returns if the block became/was type `none`.
pub fn modifyBlockHp(coord: Coordinate, bx: u4, by: u4, block: Block, hp_to_add: u4) bool {
    const key = DepthCoordinate.from(coord);
    const id: usize = @as(usize, by) * CHUNK_SIZE + bx;

    // Ensure entry exists in history
    const entry_id = mod_store.index.get(key) orelse blk: {
        const new_id = mod_store.history.len;
        // Seed new modification with current generated state if it's the first edit
        var base_chunk: Chunk = undefined;
        writeChunkModless(&base_chunk, coord);
        mod_store.history.append(alloc, base_chunk) catch @panic("Failed to add to modification storage!");
        mod_store.index.put(key, new_id) catch @panic("Failed to add to modification storage!");
        break :blk new_id;
    };

    const overflow_hp = @addWithOverflow(hp_to_add, block.hp); // overflows past 15
    if (overflow_hp[1] == 1 or hp_to_add == 0 or !block.isSolid()) {
        // The block should be removed.
        if (block.id.isEmpty()) return true;
        mod_store.history.at(entry_id).blocks[id].id = .none;

        // Update caches so changes appear immediately
        if (SimBuffer.get(coord)) |sim_chunk| {
            sim_chunk.blocks[id].id = .none;
        }
        if (ChunkCache.findIndex(coord)) |index| {
            ChunkCache.chunks[index].blocks[id].id = .none;
        }

        _ = updateLocalEdgeFlags(coord, bx, by);
        return true;
    } else {
        const new_hp: u4 = overflow_hp[0];
        mod_store.history.at(entry_id).blocks[id].hp = new_hp;

        if (SimBuffer.get(coord)) |sim_chunk| {
            sim_chunk.blocks[id].hp = new_hp;
        }
        if (ChunkCache.findIndex(coord)) |index| {
            ChunkCache.chunks[index].blocks[id].hp = new_hp;
        }
    }
    return false;
}

/// Basic lookup to find a block's `Sprite` type for flag calculation.
/// Checks caches, then modifications, then falls back to procedural logic.
/// Ensures that we do not accidentally read SimBuffer data if checking an ancestor depth!
pub fn getBlockAt(coord: Coordinate, lx: u4, ly: u4, depth: u64) Block {
    if (depth == memory.game.depth) { // easy!
        if (SimBuffer.get(coord)) |chunk| return chunk.blocks[(@as(usize, ly) << CHUNK_SIZE_LOG2) | lx];
        if (ChunkCache.findIndex(coord)) |i| {
            return ChunkCache.chunks[i].blocks[(@as(usize, ly) << CHUNK_SIZE_LOG2) | lx];
        }

        const slot_index = ChunkCache.allocateIndex(coord);
        const key = DepthCoordinate.from(coord);

        if (mod_store.get(key)) |modified_chunk| {
            // Modified state!
            ChunkCache.chunks[slot_index].blocks = modified_chunk.*.blocks;
        } else { // generate procedurally
            generateChunk(&ChunkCache.chunks[slot_index], key);
        }
        return ChunkCache.chunks[slot_index].blocks[(@as(usize, ly) << CHUNK_SIZE_LOG2) | lx];
    }

    if (memory.game.depth >= memory.HORIZON_DEPTH) {
        const horizon_depth = memory.game.depth - memory.HORIZON_DEPTH;
        if (depth == horizon_depth) {
            // Evaluates where within the D-32 active event horizon query corresponds to, bypassing standard `getInheritedMaterial` calls.
            var center_coord = memory.game.getPlayerCoord().asDepthCoordinate(memory.game.depth);
            var t_bx = memory.game.getBlockXInChunk();
            var t_by = memory.game.getBlockYInChunk();
            while (center_coord.depth > horizon_depth) {
                const p = root.ancestor.getParentInfo(center_coord, t_bx, t_by);
                center_coord = p.coord.asDepthCoordinate(center_coord.depth - 1);
                t_bx = p.bx;
                t_by = p.by;
            }

            const shift_amt: u7 = if (horizon_depth >= memory.HORIZON_DEPTH) 64 else @intCast(horizon_depth * memory.ZOOM_LOG2);

            const p_qx: i128 = coord.quadrant % 2;
            const old_qx: i128 = center_coord.quadrant % 2;
            const abs_chunk_x_p: i128 = (p_qx << shift_amt) | @as(i128, coord.suffix[0]);
            const abs_chunk_x_old: i128 = (old_qx << shift_amt) | @as(i128, center_coord.suffix[0]);
            const diff_chunk_x: i64 = @intCast(abs_chunk_x_p - abs_chunk_x_old);

            const p_qy: i128 = coord.quadrant / 2;
            const old_qy: i128 = center_coord.quadrant / 2;
            const abs_chunk_y_p: i128 = (p_qy << shift_amt) | @as(i128, coord.suffix[1]);
            const abs_chunk_y_old: i128 = (old_qy << shift_amt) | @as(i128, center_coord.suffix[1]);
            const diff_chunk_y: i64 = @intCast(abs_chunk_y_p - abs_chunk_y_old);

            const diff_block_x = diff_chunk_x * 16 + @as(i64, lx) - @as(i64, t_bx);
            const diff_block_y = diff_chunk_y * 16 + @as(i64, ly) - @as(i64, t_by);

            // Use offset 1 to center queries within the 4x4 fallback buffer
            const x_idx = diff_block_x + 1 + @as(i64, memory.game.player_quadrant % 2);
            const y_idx = diff_block_y + 1 + @as(i64, memory.game.player_quadrant / 2);

            if (x_idx >= 0 and x_idx < 4 and y_idx >= 0 and y_idx < 4) {
                return quad_cache.ancestor_materials[@intCast(y_idx)][@intCast(x_idx)];
            }
            return .empty;
        }
    }

    // not the current depth ):
    // use this function, which also checks AncestorCache
    return root.ancestor.getInheritedMaterial(
        coord.asDepthCoordinate(depth),
        lx,
        ly,
    );
}

/// Clears all caches.
pub fn clearCaches(comptime clear_ancestors: bool) void {
    SimBuffer.clear();
    ChunkCache.clear();
    // TODO: we should probably switch to hashmaps and consolidate within ChunkCache for seed logic here
    quad_cache.seed_clock_bits = std.StaticBitSet(SEED_CACHE_SIZE).initEmpty();
    quad_cache.seed_hand = 0;

    if (clear_ancestors) root.ancestor.AncestorCache.clear();
}

/// Increases the game's depth by 1, invalidates caches, moves the player, and handles data modification.
/// `coord` is the chunk the portal is in or where the depth should take place.
/// `bx` and `by` represent the specific block within a chunk the zoom should be in.
pub fn pushLayer(parent_id: Sprite, coord: Coordinate, bx: u4, by: u4) void {
    _ = parent_id;
    const old_quadrant = memory.game.player_quadrant;
    clearCaches(true);
    memory.game.depth += 1;
    const depth = memory.game.depth;

    const scale_vec = Vec2i{ ZOOM_FACTOR, ZOOM_FACTOR };
    // Magic vertical pivot compensation (384 for factor 4 and block size 256)
    const pivot_y: i64 = (ZOOM_FACTOR - 1) * memory.CHUNK_SIZE_SQ / 2;

    // Mask the last 12 bits (0-4095)
    var new_pos: memory.Vec2i = @mod(memory.game.player_pos * scale_vec, @as(Vec2i, @splat(memory.SUBPIXELS_IN_CHUNK))) + Vec2i{ 0, pivot_y };
    var chunk_offset = Vec2i{ 0, 0 };

    // Safely shift the chunk downwards if the vertical pivot overflowed the chunk bounds!
    if (new_pos[1] >= memory.SUBPIXELS_IN_CHUNK) {
        new_pos[1] -= memory.SUBPIXELS_IN_CHUNK;
        chunk_offset[1] = 1;
    }
    memory.game.teleport(null, new_pos); // make sure to teleport!

    if (depth <= HORIZON_DEPTH) {
        // Zooming by 4x means the suffix shifts by 2 bits.
        // Pull the most significant bits from the block offset (bx, by) to fill the new suffix bits.
        var target_coord = Coordinate{
            .suffix = .{
                (coord.suffix[0] *% ZOOM_FACTOR) | (bx >> (CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2)),
                (coord.suffix[1] *% ZOOM_FACTOR) | (by >> (CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2)),
            },
            .quadrant = @intCast(memory.game.player_quadrant),
        };
        if (chunk_offset[1] != 0) {
            target_coord = target_coord.moveAtDepth(chunk_offset, depth) orelse target_coord;
        }

        memory.game.player_chunk = target_coord.suffix;
        memory.game.player_quadrant = target_coord.quadrant;

        // Max possible suffix is now reached at depth 32 (64 bits).
        max_possible_suffix = getMaxSuffixAtDepth(depth);
        return;
    }

    // identify bits for rebasing...
    const shift = 64 - memory.ZOOM_LOG2;
    const top_x = coord.suffix[0] >> shift;
    const top_y = coord.suffix[1] >> shift;
    const midpoint: u64 = 1 << (shift - 1);
    const is_more_left = (coord.suffix[0] & ((@as(u64, 1) << shift) - 1)) < midpoint;
    const is_more_top = (coord.suffix[1] & ((@as(u64, 1) << shift) - 1)) < midpoint;

    const parent_quadrant_x = utils.intFromBool(u64, (memory.game.player_quadrant % 2) != 0);
    const parent_quadrant_y = utils.intFromBool(u64, (memory.game.player_quadrant / 2) != 0);
    const naive_cell_x = (parent_quadrant_x * ZOOM_FACTOR) | top_x;
    const naive_cell_y = (parent_quadrant_y * ZOOM_FACTOR) | top_y;

    const highest_possible_top_left_cell = (ZOOM_FACTOR - 1) * 2;
    var left_cell_x: u64 = naive_cell_x -| utils.intFromBool(u64, is_more_left);
    var top_cell_y: u64 = naive_cell_y -| utils.intFromBool(u64, is_more_top);
    left_cell_x = @min(left_cell_x, highest_possible_top_left_cell);
    top_cell_y = @min(top_cell_y, highest_possible_top_left_cell);

    quad_cache.most_left = quad_cache.most_left and left_cell_x == 0;
    quad_cache.most_right = quad_cache.most_right and left_cell_x == highest_possible_top_left_cell;
    quad_cache.most_top = quad_cache.most_top and top_cell_y == 0;
    quad_cache.most_bottom = quad_cache.most_bottom and top_cell_y == highest_possible_top_left_cell;

    const old_hashes = if (depth == HORIZON_DEPTH + 1) [_]seeding.Seed{memory.game.seed} ** 4 else quad_cache.path_hashes;

    inline for (0..4) |q_id| {
        const cell_x = left_cell_x + utils.intFromBool(u64, q_id % 2 == 1);
        const cell_y = top_cell_y + utils.intFromBool(u64, q_id >= 2);
        const old_q_id = utils.intFromBool(usize, cell_x >= ZOOM_FACTOR) + utils.intFromBool(usize, cell_y >= ZOOM_FACTOR) * 2;
        quad_cache.path_hashes[q_id] = seeding.mixCoordinateSeed(&old_hashes[old_q_id], cell_x % ZOOM_FACTOR, cell_y % ZOOM_FACTOR, depth);
    }

    const path_start_depth = memory.HORIZON_DEPTH + 1;
    if (depth >= path_start_depth) {
        const path_idx = depth - path_start_depth;
        const slot: usize = @intCast(path_idx / 21);
        const bit_shift: u6 = @intCast((path_idx % 21) * 3);
        if (bit_shift == 0) {
            quad_cache.left_path.append(alloc, left_cell_x) catch @panic("path alloc failed");
            quad_cache.top_path.append(alloc, top_cell_y) catch @panic("path alloc failed");
        } else {
            quad_cache.left_path.at(slot).* |= (left_cell_x << bit_shift);
            quad_cache.top_path.at(slot).* |= (top_cell_y << bit_shift);
        }
    }

    // finalize player state
    memory.game.player_chunk[0] = (coord.suffix[0] *% ZOOM_FACTOR) | (bx >> (CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2));
    memory.game.player_chunk[1] = (coord.suffix[1] *% ZOOM_FACTOR) | (by >> (CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2));

    const quadrant_x = naive_cell_x - left_cell_x;
    const quadrant_y = naive_cell_y - top_cell_y;
    var target_coord = Coordinate{
        .suffix = .{
            (coord.suffix[0] *% ZOOM_FACTOR) | (bx >> (CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2)),
            (coord.suffix[1] *% ZOOM_FACTOR) | (by >> (CHUNK_SIZE_LOG2 - memory.ZOOM_LOG2)),
        },
        .quadrant = @intCast(quadrant_x + (quadrant_y * 2)),
    };
    if (chunk_offset[1] != 0) {
        target_coord = target_coord.moveAtDepth(chunk_offset, depth) orelse target_coord;
    }

    memory.game.player_chunk = target_coord.suffix;
    memory.game.player_quadrant = target_coord.quadrant;

    const target_horizon_depth = depth - memory.HORIZON_DEPTH;
    if (target_horizon_depth >= STARTING_ZOOM_TIMES) {
        var next_materials: [4][4]Block = undefined;

        // Ancestor at H = D-32. Find the exact block we are located in to summarize the region correctly.
        var trace_coord = memory.game.getPlayerCoord().asDepthCoordinate(depth);
        var t_bx: u4 = @intCast(@divTrunc(new_pos[0], memory.CHUNK_SIZE_SQ));
        var t_by: u4 = @intCast(@divTrunc(new_pos[1], memory.CHUNK_SIZE_SQ));

        var i: u32 = 0;
        while (i < 32) : (i += 1) {
            const p = root.ancestor.getParentInfo(trace_coord, t_bx, t_by);
            trace_coord = p.coord.asDepthCoordinate(trace_coord.depth - 1);
            t_bx = p.bx;
            t_by = p.by;
        }

        var old_trace_coord = trace_coord;
        var old_t_bx = t_bx;
        var old_t_by = t_by;
        if (target_horizon_depth > STARTING_ZOOM_TIMES) {
            const pp = root.ancestor.getParentInfo(trace_coord, t_bx, t_by);
            old_trace_coord = pp.coord.asDepthCoordinate(old_trace_coord.depth - 1);
            old_t_bx = pp.bx;
            old_t_by = pp.by;
        }

        const qx: i32 = @intCast(memory.game.player_quadrant % 2);
        const qy: i32 = @intCast(memory.game.player_quadrant / 2);
        const shift_amt: u7 = if (old_trace_coord.depth >= memory.HORIZON_DEPTH) 64 else @intCast(old_trace_coord.depth * memory.ZOOM_LOG2);
        const old_qx = @as(i128, old_trace_coord.quadrant % 2);
        const old_qy = @as(i128, old_trace_coord.quadrant / 2);

        for (0..4) |y_idx| {
            for (0..4) |x_idx| {
                const delta_bx: i32 = @as(i32, @intCast(x_idx)) - 1 - qx;
                const delta_by: i32 = @as(i32, @intCast(y_idx)) - 1 - qy;
                const absolute_bx: i32 = @as(i32, @intCast(t_bx)) + delta_bx;
                const absolute_by: i32 = @as(i32, @intCast(t_by)) + delta_by;
                const chunk_dx = @divFloor(absolute_bx, 16);
                const chunk_dy = @divFloor(absolute_by, 16);
                const local_bx: u4 = @intCast(@mod(absolute_bx, 16));
                const local_by: u4 = @intCast(@mod(absolute_by, 16));

                if (trace_coord.asCoord().moveAtDepth(.{ chunk_dx, chunk_dy }, target_horizon_depth)) |nc| {
                    const child_key = nc.asDepthCoordinate(target_horizon_depth);
                    if (mod_store.get(child_key)) |mod| {
                        next_materials[y_idx][x_idx] = mod.blocks[(@as(usize, local_by) << 4) | local_bx];
                    } else if (target_horizon_depth == STARTING_ZOOM_TIMES) {
                        next_materials[y_idx][x_idx] = root.ancestor.getInheritedMaterial(child_key, local_bx, local_by);
                    } else {
                        const p = root.ancestor.getParentInfo(child_key, local_bx, local_by);
                        const p_qx_128: i128 = p.coord.quadrant % 2;
                        const p_qy_128: i128 = p.coord.quadrant / 2;
                        const diff_chunk_x: i64 = @intCast(((p_qx_128 << shift_amt) |
                            @as(i128, p.coord.suffix[0])) - ((old_qx << shift_amt) |
                            @as(i128, old_trace_coord.suffix[0])));
                        const diff_chunk_y: i64 = @intCast(((p_qy_128 << shift_amt) |
                            @as(i128, p.coord.suffix[1])) - ((old_qy << shift_amt) |
                            @as(i128, old_trace_coord.suffix[1])));

                        const p_x_idx = diff_chunk_x * 16 + @as(i64, p.bx) - @as(i64, old_t_bx) + 1 + @as(i64, old_quadrant % 2);
                        const p_y_idx = diff_chunk_y * 16 + @as(i64, p.by) - @as(i64, old_t_by) + 1 + @as(i64, old_quadrant / 2);

                        var parent_block: Block = .empty;
                        var p_neighbors: [8]Block align(8) = [_]Block{.empty} ** 8;

                        if (p_x_idx >= 0 and p_x_idx < 4 and p_y_idx >= 0 and p_y_idx < 4) {
                            parent_block = quad_cache.ancestor_materials[@intCast(p_y_idx)][@intCast(p_x_idx)];

                            // Populate neighbors for applyAncestorLogic from the current 4x4 ancestor grid
                            var n_idx: usize = 0;
                            var ndy: i32 = -1;
                            while (ndy <= 1) : (ndy += 1) {
                                var ndx: i32 = -1;
                                while (ndx <= 1) : (ndx += 1) {
                                    if (ndx == 0 and ndy == 0) continue;
                                    const nx = p_x_idx + ndx;
                                    const ny = p_y_idx + ndy;

                                    if (nx >= 0 and nx < 4 and ny >= 0 and ny < 4) {
                                        p_neighbors[n_idx] = quad_cache.ancestor_materials[@intCast(ny)][@intCast(nx)];
                                    } else {
                                        p_neighbors[n_idx] = .empty;
                                    }
                                    n_idx += 1;
                                }
                            }
                        }

                        next_materials[y_idx][x_idx] = root.ancestor.applyAncestorLogic(
                            parent_block,
                            p_neighbors,
                            child_key,
                            local_bx,
                            local_by,
                        );
                    }
                } else next_materials[y_idx][x_idx] = .empty;
            }
        }

        quad_cache.ancestor_materials = next_materials;
    }
}
