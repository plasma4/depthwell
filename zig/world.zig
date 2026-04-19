//! Defines the architecture of the fractal world, contains cache data, and some ore definitions.
const std = @import("std");
const SegmentedList = @import("SegmentedList.zig").SegmentedList;
const is_debug = @import("builtin").mode == .Debug;
const Sprite = @import("sprite.zig").Sprite;
const utils = @import("utils.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const logger = @import("logger.zig");
const seeding = @import("seeding.zig");
const procedural = @import("procedural.zig");
const player = @import("player.zig");

const v2i64 = memory.v2i64;
const v2u64 = memory.v2u64;
const v2f64 = memory.v2f64;
const Chunk = memory.Chunk;
const Block = memory.Block;
const Coordinate = memory.Coordinate;
const SPAN = memory.SPAN;
const SPAN_SQ = memory.SPAN_SQ;
const SPAN_FLOAT = memory.SPAN_FLOAT;
const SPAN_LOG2 = memory.SPAN_LOG2;

const odds_num = seeding.odds_num;

/// A full 256-block (chunk) of modifications.
pub const ChunkMod = [SPAN_SQ]Block;

pub const ModificationStore = struct {
    index: std.HashMap(ModKey, usize, ModKeyContext, std.hash_map.default_max_load_percentage),
    history: std.ArrayList(ChunkMod),

    pub fn init(allocator: std.mem.Allocator, starting_capacity: comptime_int) ModificationStore {
        return .{
            .index = std.HashMap(ModKey, usize, ModKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .history = std.ArrayList(ChunkMod).initCapacity(allocator, starting_capacity) catch @panic("modification history creation failed!"),
        };
    }

    /// Gets an existing modification for reading.
    pub fn get(self: *const @This(), key: ModKey) ?*const ChunkMod {
        const idx = self.index.get(key) orelse return null;
        return &self.history.items[idx];
    }
};

pub var mod_store: ModificationStore = undefined;

/// Stores where a modification is, as well as its depth to easily identify it.
pub const ModKey = extern struct {
    // Active suffix (stored as a vector). You can think of the active suffix like 16 u4s packed together for the X and Y coordinate that can be merged with the correct QuadCache quadrant to produce a "complete" path (see `README.md` for more details).
    suffix: v2u64,
    /// Quadrant ID (00: NW, 1: NE, 2: SW, 3: SE).
    quadrant: u32,
    /// The depth of the modification.
    depth: u64,

    pub inline fn from(coord: Coordinate) @This() {
        return .{
            .suffix = coord.suffix,
            .quadrant = @intCast(coord.quadrant),
            .depth = memory.game.depth,
        };
    }
};

/// Context for the `ModKey` (providing hashing and equality checks).
pub const ModKeyContext = struct {
    pub inline fn hash(self: @This(), key: ModKey) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(key.depth);
        // Hash exact fields explicitly to avoid padding ambiguities
        std.hash.autoHash(&hasher, key.quadrant);
        std.hash.autoHash(&hasher, key.suffix);
        return hasher.final();
    }

    pub inline fn eql(self: @This(), a: ModKey, b: ModKey) bool {
        _ = self;
        return a.depth == b.depth and a.quadrant == b.quadrant and @reduce(.And, a.suffix == b.suffix);
    }
};

/// Width of the simulation buffer.
const SIM_BUFFER_WIDTH = 16;
/// Size of the simulation buffer (`SIM_BUFFER_WIDTH` squared).
const SIM_BUFFER_SIZE = SIM_BUFFER_WIDTH * SIM_BUFFER_WIDTH;
/// Size of the chunk cache (can be arbitrarily adjusted).
const CHUNK_CACHE_SIZE = 256;
/// Total size of the chunk pool, which is in one contiguous memory block (simulation and cache buffer size added together).
const CHUNK_POOL_SIZE = SIM_BUFFER_SIZE + CHUNK_CACHE_SIZE;

/// A combined pool of SimBuffer and chunk cache data.
var chunk_pool: [CHUNK_POOL_SIZE]Chunk = undefined;

/// The simulation buffer containing 16x16 chunks, centered around the player.
pub const SimBuffer = struct {
    /// Size of the outside ring `background_generation_tick` uses.
    const RING_SIZE = 68;
    const RING_OFFSETS = blk: {
        var offs: [RING_SIZE]v2i64 = undefined;
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

    /// The coordinate corresponding to the chunk at the "logical" (0,0) of the 16x16 window.
    var origin: ?Coordinate = null;
    var ring_x: u4 = 0;
    var ring_y: u4 = 0;

    /// Mask for the 16x16 buffer.
    const SIM_MASK = SIM_BUFFER_WIDTH - 1;
    const _ = {
        if (!std.math.isPowerOfTwo(SIM_BUFFER_WIDTH)) @compileError("Sim buffer width must be a positive power of 2.");
    };

    /// Represents log2(SIM_BUFFER_WIDTH).
    const LOG_2_MASK = std.math.log2(SIM_BUFFER_WIDTH);

    /// Attempts to retrieve a chunk from the buffer, returning `null` if non-existent.
    pub fn get(coord: Coordinate) ?*Chunk {
        const og = origin orelse return null;
        if (coord.quadrant != og.quadrant) {
            return null;
        }

        const dx = coord.suffix[0] -% og.suffix[0];
        const dy = coord.suffix[1] -% og.suffix[1];

        if (dx < SIM_BUFFER_WIDTH and dy < SIM_BUFFER_WIDTH) {
            const id = get_index(@intCast(dx), @intCast(dy));
            if (keys[id]) |k| {
                if (k.eql(coord)) return &sim_buffer_ptr[id];
            }
        }
        return null;
    }

    /// Returns the internal index into the chunk array.
    pub inline fn get_index(cx: u4, cy: u4) usize {
        const rx = (ring_x +% cx) & SIM_MASK;
        const ry = (ring_y +% cy) & SIM_MASK;
        return (@as(usize, ry) << LOG_2_MASK) | rx;
    }

    /// Clears the whole `SimBuffer`, invalidating previous data.
    pub inline fn clear() void {
        @memset(sim_buffer_ptr, std.mem.zeroes(Chunk));
        @memset(&keys, null);
        origin = null;
        ring_x = 0;
        ring_y = 0;
    }

    /// Helper to safely step an origin coordinate, returning the furthest possible coordinate
    /// if a game boundary is hit (when Coordinate.move returns null).
    fn get_clamped_move(coord: Coordinate, dx: i64, dy: i64) Coordinate {
        // Fast path: attempt direct move
        if (coord.move(.{ dx, dy })) |target| return target;

        // Slow path: step-clamping (only for hard world boundaries)
        var curr = coord;
        inline for (.{ 0, 1 }) |axis| {
            var remaining = if (axis == 0) dx else dy;
            while (remaining != 0) {
                const step = std.math.sign(remaining);
                const next = if (axis == 0) curr.move_x(step) else curr.move_y(step);
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
    pub fn sync(coord: Coordinate, shift: v2i64) void {
        const og = origin orelse {
            full_refresh(get_clamped_move(coord, -8, -8));
            return;
        };

        // Use shift directly for incremental updates if distance is small
        if (@abs(shift[0]) < SIM_BUFFER_WIDTH and @abs(shift[1]) < SIM_BUFFER_WIDTH) {
            if (shift[0] != 0 or shift[1] != 0) {
                incremental_refresh(shift[0], shift[1]);
            }
            return;
        }

        // Teleport or large jump fallback
        const target_origin = get_clamped_move(coord, -8, -8);
        if (!og.eql(target_origin)) full_refresh(target_origin);
    }

    fn full_refresh(new_origin: Coordinate) void {
        origin = new_origin;
        ring_x = 0;
        ring_y = 0;

        for (0..SIM_BUFFER_WIDTH) |cy| {
            for (0..SIM_BUFFER_WIDTH) |cx| {
                const id = (cy << LOG_2_MASK) | cx;
                if (new_origin.move(.{ @intCast(cx), @intCast(cy) })) |cell_coord| {
                    keys[id] = cell_coord;
                    write_chunk_skip(&sim_buffer_ptr[id], cell_coord);
                } else {
                    keys[id] = null;
                }
            }
        }
    }

    fn incremental_refresh(dx: i64, dy: i64) void {
        const old_origin = origin.?;
        const new_origin = get_clamped_move(old_origin, dx, dy);
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
                    const id = get_index(@intCast(cx_log), @intCast(cy_log));
                    if (new_origin.move(.{ @intCast(cx_log), @intCast(cy_log) })) |cell_coord| {
                        keys[id] = cell_coord;
                        write_chunk_skip(&sim_buffer_ptr[id], cell_coord);
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
                    const id = get_index(@intCast(cx_log), @intCast(cy_log));
                    if (new_origin.move(.{ @intCast(cx_log), @intCast(cy_log) })) |cell_coord| {
                        keys[id] = cell_coord;
                        write_chunk_skip(&sim_buffer_ptr[id], cell_coord);
                    } else {
                        keys[id] = null;
                    }
                }
            }
        }
    }

    /// Background caching heuristic: scans the boundary immediately outside the 16x16 chunk in the
    /// direction of movement and creates it in ChunkCache before the player reaches it.
    ///
    /// Fairly naive, generating `default_amount` chunks when called (suggested value of 1-2).
    /// It is recommended to set a higher `max_amount` (so more budget is available in high-velocity falling situations).
    pub fn background_generation_tick(player_coord: Coordinate, velocity: v2f64, default_amount: comptime_int, max_amount: comptime_int) void {
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
            [_]v2i64{ .{ 0, ty }, .{ -1, ty }, .{ 1, ty } } // Vertical lead
        else
            [_]v2i64{ .{ tx, 0 }, .{ tx, -1 }, .{ tx, 1 } }; // Horizontal lead

        for (targets) |off| {
            if (generated_count >= budget) break;
            if (player_coord.move(off)) |c| {
                if (get(c) == null and ChunkCache.get(c) == null) {
                    const slot = ChunkCache.allocate_slot(c);
                    generate_chunk(slot, c);
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
                if (get(c) == null and ChunkCache.get(c) == null) {
                    const slot = ChunkCache.allocate_slot(c);
                    generate_chunk(slot, c);
                    generated_count += 1;
                }
            }
        }
    }
};

pub const ChunkCache = struct {
    var cache_keys: [CHUNK_CACHE_SIZE]?Coordinate = [_]?Coordinate{null} ** CHUNK_CACHE_SIZE;
    var cache_chunk_data: *[CHUNK_CACHE_SIZE]Chunk = chunk_pool[0..CHUNK_CACHE_SIZE];

    // Clock metadata
    var cache_clock_bits: std.StaticBitSet(CHUNK_CACHE_SIZE) = std.StaticBitSet(CHUNK_CACHE_SIZE).initEmpty();
    var cache_hand: usize = 0;

    /// Retrieves a chunk if it exists, marking it as "recently used"
    pub fn get(coord: Coordinate) ?*Chunk {
        for (&cache_keys, 0..) |maybe_key, i| {
            if (maybe_key) |k| {
                if (k.eql(coord)) {
                    cache_clock_bits.set(i); // give it a second chance (ref_bit becomes 1)
                    return &cache_chunk_data[i];
                }
            }
        }
        return null;
    }

    pub fn allocate_slot(coord: Coordinate) *Chunk {
        while (true) {
            const id = cache_hand;
            cache_hand = (cache_hand + 1) % CHUNK_CACHE_SIZE;

            if (cache_clock_bits.isSet(id)) {
                // Give second chance: clear bit and move hand
                cache_clock_bits.setValue(id, false);
            } else {
                // Found a "victim" (either null key or ref_bit was 0)
                cache_keys[id] = coord;
                cache_clock_bits.set(id); // Mark as recently used
                return &cache_chunk_data[id];
            }
        }
    }

    /// Inserts a chunk using the clock algorithm to find an eviction candidate.
    pub fn insert(coord: Coordinate, chunk: Chunk) *Chunk {
        while (true) {
            const id = cache_hand;

            // Advance the hand for next time
            cache_hand = (cache_hand + 1) % CHUNK_CACHE_SIZE;

            // Clock logic: second chance if ref_bit is 1, otherwise evict
            if (cache_clock_bits.isSet(id)) {
                cache_clock_bits.setValue(id, false);
            } else {
                cache_keys[id] = coord;
                cache_chunk_data[id] = chunk;
                cache_clock_bits.set(id); // new entries start with ref bit as 1
                return &cache_chunk_data[id];
            }
        }
    }

    /// Clears the whole `ChunkCache`, invalidating previous data.
    pub fn clear() void {
        @memset(&cache_keys, null); // reset all keys
        cache_clock_bits = std.StaticBitSet(CHUNK_CACHE_SIZE).initEmpty(); // clear bitset
        cache_hand = 0; // reset hand
    }
};

/// UNUSED DUE TO BEING UNNECESSARY. Adds 1 to the `path` as if the `ArrayList` represented one giant number. Performs allocation; the caller should deinit the path eventually using `arena`.
fn carry_path(path: *const std.ArrayList(u64)) std.ArrayList(u64) {
    const new_path = path.clone(arena.allocator()) catch @panic("carry alloc for QuadCache coordinates failed");
    arena.reset(.retain_capacity); // TODO decide
    var carry: u1 = 1;

    for (new_path.items) |*word| {
        const add_res = @addWithOverflow(word.*, @as(u64, carry));
        word.* = add_res[0];
        carry = add_res[1];

        if (carry == 0) break;
    }

    // If we still have a carry after the loop, the coordinate grew. However, this is NOT POSSIBLE because the quadrant logic should specifically disallow this (impl TODO)
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

/// A static 2x2 grid of seeds only updated on entering a portal/game startup. See `README.md` for a more detailed and intuitive explanation for what this does.
pub const QuadCache = struct {
    /// The 512-bit hashes for the 4 active quadrants (sequentially from D to D-15).
    /// (0: NW, 1: NE, 2: SW, 3: SE)
    path_hashes: [4]seeding.Seed align(memory.MAIN_ALIGN_BYTES),
    /// TODO actual logic
    hash_cache_1: [4]seeding.Seed,
    /// The block IDs for each of the 4 places the QuadCache represents.
    ancestor_materials: [4]Sprite,
    /// A list representing the prefix stack of the top left quadrant's X-coordinate.
    left_path: SegmentedList(u64, 0),
    /// Stores the topmost QuadCache's Y-coordinate.
    top_path: SegmentedList(u64, 0),

    // These 4 properties are used to determine if a QuadCache is at the very edge of the world for chunk gen/zooming in
    most_top: bool = true,
    most_bottom: bool = true,
    most_left: bool = true,
    most_right: bool = true,

    // /// Returns the X-coordinate path of a specific quadrant. Unreachable call if path is empty (if depth is not > 16). Call `cleanup_path` afterward.
    // pub inline fn get_quadrant_path_x(self: *const @This(), quadrant: u2) std.ArrayList(u64) {
    //     return if (quadrant % 2 == 0) self.left_path else carry_path(&self.left_path);
    // }

    // /// Returns the Y-coordinate path of a specific quadrant. Unreachable call if path is empty (if depth is not > 16). Call `cleanup_path` afterward.
    // pub inline fn get_quadrant_path_y(self: *const @This(), quadrant: u2) std.ArrayList(u64) {
    //     return if (quadrant < 2) self.top_path else carry_path(&self.top_path);
    // }

    // /// Deallocates a temporary instance of a QuadCache path. (THIS DOESN'T WORK WITH ARENA)
    // pub inline fn cleanup_path(self: *const @This(), path: std.ArrayList(u64)) void {
    //     // Memory comparison is safe because QuadCache will never be de-initialized, top_left_path is always non-empty (so nothing weird), and there's no multicore/async shenanigans here.
    //     if (self.left_path.items.ptr != path.items.ptr and self.top_path.items.ptr != path.items.ptr) {
    //         path.deinit(arena);
    //     }
    // }

    /// Returns the 512-bit seed of a specified quadrant (or the global seed if the current depth is <= 16).
    pub inline fn get_quadrant_seed(self: *const @This(), quadrant: u2) seeding.Seed {
        if (memory.game.depth <= 16) return memory.game.seed;
        return self.path_hashes[quadrant];
    }

    /// Resolves the chunk seeds. If depth > 16, uses the quadrant seeds.
    pub inline fn get_chunk_seeds(self: *const @This(), coord: Coordinate) [4]seeding.Seed {
        return seeding.mix_chunk_seeds(&self.get_quadrant_seed(coord.quadrant), coord.suffix);
    }

    /// Returns details on a specific quadrant and what "edges" of the world it touches.
    pub inline fn get_quadrant_edge_details(self: *const @This(), quadrant: u2) QuadrantEdgeDetails {
        // Quadrant IDs for reference: 00: NW, 1: NE, 2: SW, 3: SE
        if (memory.game.depth <= 16) {
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
pub var quad_cache: QuadCache = undefined;

/// Represents the answer to the question "what is the largest possible suffix value"? 15 at depth 1, 255 at depth 2, capped at 2**64-1 at depth 16 and beyond.
pub var max_possible_suffix: u64 = 0;

/// `ArenaAllocator` instance used for the world.
pub var arena = memory.make_arena();
/// Allocator used for the world.
pub var alloc = arena.allocator();

/// Creates a new instance of a `Chunk` where specified, given a coordinate. Copies over from cache if possible.
pub fn write_chunk(chunk: *Chunk, coord: Coordinate) void {
    if (SimBuffer.get(coord)) |cached_ptr| {
        chunk.* = cached_ptr.*;
        return;
    }

    if (ChunkCache.get(coord)) |cached_ptr| {
        chunk.* = cached_ptr.*;
        return;
    }

    const new_slot_ptr = ChunkCache.allocate_slot(coord);
    const key = ModKey.from(coord);

    if (mod_store.get(key)) |modified_chunk| {
        // Fast path: copy the fully cached modified state
        new_slot_ptr.blocks = modified_chunk.*;
    } else {
        // Slow path: generate procedurally
        generate_chunk(new_slot_ptr, coord);
    }

    chunk.* = new_slot_ptr.*;
}

/// Same as `write_chunk`, but avoids checking `SimBuffer` first.
pub fn write_chunk_skip(chunk: *Chunk, coord: Coordinate) void {
    if (ChunkCache.get(coord)) |cached_ptr| {
        chunk.* = cached_ptr.*;
        return;
    }

    const new_slot_ptr = ChunkCache.allocate_slot(coord);
    const key = ModKey.from(coord);

    if (mod_store.get(key)) |modified_chunk| {
        new_slot_ptr.blocks = modified_chunk.*;
    } else {
        generate_chunk(new_slot_ptr, coord);
    }

    chunk.* = new_slot_ptr.*;
}

/// Creates a new instance of a `Chunk`. Does not update edge flags.
pub inline fn get_chunk(coord: Coordinate) Chunk {
    var chunk: Chunk = undefined;
    write_chunk(&chunk, coord);
    return chunk;
}

/// Internal function to generate a whole chunk (considering modifications), given a pointer to where the chunk should be stored and coordinates.
/// Does not go through the cache; use `write_chunk` to create a chunk at a specified location and `get_chunk` for a new one.
fn generate_chunk(chunk: *Chunk, coord: Coordinate) void {
    const chunk_seeds = quad_cache.get_chunk_seeds(coord);

    const seed_vec1: v2u64 = .{ memory.game.seed2[0], memory.game.seed2[1] };
    const seed_vec2: v2u64 = .{ memory.game.seed2[2], memory.game.seed2[3] };
    const seed_vec3: v2u64 = .{ memory.game.seed2[4], memory.game.seed2[5] };
    const seed_vec4: v2u64 = .{ memory.game.seed2[6], memory.game.seed2[6] };
    const seed_vec5: v2u64 = .{ memory.game.seed2[7], memory.game.seed2[8] };
    const seed_vec6: v2u64 = .{ memory.game.seed2[9], memory.game.seed2[10] };

    var rng1 = seeding.ChaCha12.init(chunk_seeds[0]); // Block generation.
    var rng4 = seeding.ChaCha12.init(chunk_seeds[3]); // Visual touches only.

    const cx = coord.suffix[0];
    const cy = coord.suffix[1];
    const quadrant_edge_details = quad_cache.get_quadrant_edge_details(coord.quadrant);

    for (0..SPAN) |block_y| {
        for (0..SPAN) |block_x| {
            const id = block_x + block_y * SPAN;

            // simple edge-of-the-world solid block logic
            const is_absolute_edge_x = (cx == 0 and block_x < 2 and quadrant_edge_details.most_left) or (cx == max_possible_suffix and block_x >= (SPAN - 2) and quadrant_edge_details.most_right);
            const is_absolute_edge_y = (cy == 0 and block_y < 2 and quadrant_edge_details.most_top) or (cy == max_possible_suffix and block_y >= (SPAN - 2) and quadrant_edge_details.most_bottom);
            if (is_absolute_edge_x or is_absolute_edge_y) {
                chunk.blocks[id] = Block.make_basic_block(
                    // drawing sprite change in WGSL now after tile unpacking, quite silly to be here
                    // if ((block_x % 2) + (block_y % 2) == 1) ._edge_stone else .edge_stone,
                    .edge_stone,
                    rng4.next(),
                );
                // This does mean there are fewer PRNG .next() calls but this doesn't matter here
                continue;
            }

            // TODO finish for higher depths with some cubic bezier-like upscaling method

            // BASE CASE: depth = 3.
            const base_data = procedural.get_base_sprite_type(
                seed_vec1,
                seed_vec2,
                @intCast(cx),
                @intCast(cy),
                @intCast(block_x),
                @intCast(block_y),
            );
            var sprite = base_data.sprite;
            if (sprite.is_stone() or sprite.is_heatmap()) sprite = procedural.add_ores(
                base_data,
                seed_vec3,
                seed_vec4,
                seed_vec5,
                seed_vec6,
                @intCast(cx * 16 + block_x),
                @intCast(cy * 16 + block_y),
            );

            chunk.blocks[id] = Block.make_basic_block(
                sprite,
                rng4.next(),
            ); // edge flags updated in second pass
        }
    }

    add_edge_flags(chunk, coord, &rng1);
    procedural.add_decorations(chunk, &rng1);
}

/// Adds edge flags to an already generated chunk. Utilizes `get_base_sprite_type` to prevent a chunk creation dependency loop.
fn add_edge_flags(target_chunk: *Chunk, coord: Coordinate, rng1: *seeding.ChaCha12) void {
    const vec1: v2u64 = .{ memory.game.seed2[0], memory.game.seed2[1] };
    const vec2: v2u64 = .{ memory.game.seed2[2], memory.game.seed2[3] };
    _ = rng1;

    // Interior (easy)
    for (1..SPAN - 1) |block_y| {
        for (1..SPAN - 1) |block_x| {
            const id = block_y * SPAN + block_x;
            const current_sprite = target_chunk.blocks[id].id;
            var flags: u8 = 0;
            inline for (.{ -1, 0, 1 }) |dy| {
                inline for (.{ -1, 0, 1 }) |dx| {
                    if (dx == 0 and dy == 0) continue;
                    const nx = block_x +% @as(usize, @bitCast(@as(isize, dx)));
                    const ny = block_y +% @as(usize, @bitCast(@as(isize, dy)));
                    if (should_have_edge_flags(target_chunk.blocks[ny * SPAN + nx].id, current_sprite)) {
                        flags |= types.EdgeFlags.get_flag_bit(dx, dy);
                    }
                }
            }
            target_chunk.blocks[id].edge_flags = flags;
        }
    }

    // Get neighbor contexts if existent in SimBuffer
    const NeighborCtx = struct { coord: ?Coordinate, chunk: ?*Chunk };
    var neighbors: [9]NeighborCtx = undefined;
    inline for (.{ -1, 0, 1 }) |dy| {
        inline for (.{ -1, 0, 1 }) |dx| {
            const idx = @as(usize, (dy + 1) * 3 + (dx + 1));
            if (dx == 0 and dy == 0) {
                neighbors[idx] = .{ .coord = coord, .chunk = target_chunk };
                continue;
            }
            const nc = coord.move(.{ dx, dy });
            neighbors[idx] = .{
                .coord = nc,
                .chunk = if (nc) |c| SimBuffer.get(c) else null,
            };
        }
    }

    // 3. Perimeter: 4 linear passes to avoid the "if (interior) continue" branch.
    const edge_rects = [4][4]usize{
        .{ 0, SPAN, 0, 1 }, // Top Row (incl. corners)
        .{ 0, SPAN, SPAN - 1, SPAN }, // Bottom Row (incl. corners)
        .{ 0, 1, 1, SPAN - 1 }, // Left Column (sans corners)
        .{ SPAN - 1, SPAN, 1, SPAN - 1 }, // Right Column (sans corners)
    };

    inline for (edge_rects) |r| {
        for (r[2]..r[3]) |block_y| {
            for (r[0]..r[1]) |block_x| {
                const id = block_y * SPAN + block_x;
                const current_sprite = target_chunk.blocks[id].id;
                var flags: u8 = 0;

                inline for (.{ -1, 0, 1 }) |dy| {
                    inline for (.{ -1, 0, 1 }) |dx| {
                        if (dx == 0 and dy == 0) continue;

                        const nx = @as(i32, @intCast(block_x)) + dx;
                        const ny = @as(i32, @intCast(block_y)) + dy;

                        // Resolve sprite using pre-cached neighbors
                        const sprite = if (nx >= 0 and nx < SPAN and ny >= 0 and ny < SPAN)
                            target_chunk.blocks[@as(usize, @intCast(ny * SPAN + nx))].id
                        else blk: {
                            // Correct neighbor index is based strictly on the SHIFT, not the block coord
                            const n_idx = @as(usize, (if (ny < 0) @as(usize, 0) else if (ny >= SPAN) @as(usize, 2) else 1) * 3 + (if (nx < 0) @as(usize, 0) else if (nx >= SPAN) @as(usize, 2) else 1));
                            const n = neighbors[n_idx];

                            // only get 1 block, instead if naively asking for a whole chunk
                            if (n.chunk) |c| {
                                break :blk c.blocks[@as(usize, @intCast(ny & 15)) * SPAN + @as(usize, @intCast(nx & 15))].id;
                            } else if (n.coord) |c| {
                                break :blk procedural.get_base_sprite_type(vec1, vec2, @intCast(c.suffix[0]), @intCast(c.suffix[1]), @intCast(nx & 15), @intCast(ny & 15)).sprite;
                            }
                            break :blk .none;
                        };

                        if (should_have_edge_flags(sprite, current_sprite)) {
                            flags |= types.EdgeFlags.get_flag_bit(dx, dy);
                        }
                    }
                }
                target_chunk.blocks[id].edge_flags = flags;
            }
        }
    }
}

inline fn should_have_edge_flags(sprite: Sprite, current_sprite: Sprite) bool {
    _ = .{current_sprite};
    // return (sprite.is_foundation() and !sprite.is_ore() and current_sprite.is_foundation() and !current_sprite.is_ore()) or sprite == current_sprite;
    return sprite.is_foundation();
}

/// Applies a block modification. Mutates ModStore and caches in-place.
pub fn apply_modification(coord: memory.Coordinate, bx: u4, by: u4, new_sprite: Sprite) void {
    const key = ModKey.from(coord);
    const id: usize = @as(usize, by) * memory.SPAN + bx;

    // Ensure entry exists in history
    const entry_idx = mod_store.index.get(key) orelse blk: {
        const new_idx = mod_store.history.items.len;
        // Seed new modification with current generated state if it's the first edit
        const base_chunk = get_chunk(coord);
        mod_store.history.append(alloc, base_chunk.blocks) catch return;
        mod_store.index.put(key, new_idx) catch return;
        break :blk new_idx;
    };

    mod_store.history.items[entry_idx][id].id = new_sprite;

    // Update caches so changes appear immediately
    if (SimBuffer.get(coord)) |sim_chunk| {
        sim_chunk.blocks[id].id = new_sprite;
    }
    if (ChunkCache.get(coord)) |cache_chunk| {
        cache_chunk.blocks[id].id = new_sprite;
    }

    update_local_edge_flags(coord, bx, by);
}

/// Recalculates edge flags for a specific block and its 8 neighbors.
fn update_local_edge_flags(coord: memory.Coordinate, bx: u4, by: u4) void {
    // We must update the 3x3 area around the modification
    for ([_]i32{ -1, 0, 1 }) |dy| {
        for ([_]i32{ -1, 0, 1 }) |dx| {
            const nx: i32 = @as(i32, bx) + dx;
            const ny: i32 = @as(i32, by) + dy;

            // Resolve target block coordinate and local indices
            var target_coord = coord;
            if (nx < 0 or nx >= SPAN or ny < 0 or ny >= SPAN) {
                target_coord = coord.move(.{ @divFloor(nx, SPAN), @divFloor(ny, SPAN) }) orelse continue;
            }

            const lbx: u4 = @intCast(@mod(nx, SPAN));
            const lby: u4 = @intCast(@mod(ny, SPAN));

            // Fetch the chunk from cache. If it's not cached, it doesn't need live flag updates.
            const target_chunk = SimBuffer.get(target_coord) orelse ChunkCache.get(target_coord) orelse continue;
            const target_id = @as(usize, lby) * SPAN + lbx;
            const current_sprite = target_chunk.blocks[target_id].id;

            if (!current_sprite.is_foundation()) { // correct here because we aren't doing procedural stuff
                target_chunk.blocks[target_id].edge_flags = 0xFF;
                continue;
            }

            var new_flags: u8 = 0;
            // Recalculate 8 neighbors for this specific block
            inline for (.{ -1, 0, 1 }) |ndy| {
                inline for (.{ -1, 0, 1 }) |ndx| {
                    if (ndx == 0 and ndy == 0) continue;

                    const nnx: i32 = @as(i32, lbx) + ndx;
                    const nny: i32 = @as(i32, lby) + ndy;

                    const sprite = if (nnx >= 0 and nnx < SPAN and nny >= 0 and nny < SPAN)
                        target_chunk.blocks[@as(usize, @intCast(nny * SPAN + nnx))].id
                    else blk: {
                        const neighbor_coord = target_coord.move(.{ @divFloor(nnx, SPAN), @divFloor(nny, SPAN) }) orelse break :blk .none;
                        const nc = SimBuffer.get(neighbor_coord) orelse ChunkCache.get(neighbor_coord) orelse break :blk .none;
                        break :blk nc.blocks[@as(usize, @intCast(nny & 15)) * SPAN + @as(usize, @intCast(nnx & 15))].id;
                    };

                    if (should_have_edge_flags(sprite, current_sprite)) {
                        new_flags |= types.EdgeFlags.get_flag_bit(ndx, ndy);
                    }
                }
            }
            target_chunk.blocks[target_id].edge_flags = new_flags;
        }
    }
}

// /// The 16-step ascendent projection read loop thingy
// /// Called when the SimBuffer generates a chunk.
// pub fn get_effective_modification(self: *@This(), cx: u64, cy: u64) ?*ChunkMod {
//     var search_cx = cx;
//     var search_cy = cy;

//     // Start from current depth (0) and look up to 15 ancestors
//     // We use the cached path_stack so we don't have to reverse hashes
//     const max_lookback = @min(16, memory.game.depth);

//     for (0..max_lookback) |i| {
//         const key = ModKey{
//             .path_hash = quad_cache.TODO[i],
//             .cx = search_cx,
//             .cy = search_cy,
//         };

//         if (mod_store.index.get(key)) |id| {
//             return &mod_store.history.items[id];
//         }

//         // Move to parent coordinate: shift off the lowest 4 bits (the block coordinates)
//         search_cx >>= 4;
//         search_cy >>= 4;
//     }
//     return null;
// }

pub fn clear_caches() void {
    SimBuffer.clear();
    ChunkCache.clear();
}

/// Handles increasing the depth.
/// `coord` is the chunk the portal is in. `bx` and `by` represent the specific block within a chunk the zoom should be in.
pub fn push_layer(parent_id: Sprite, coord: Coordinate, bx: u4, by: u4) void {
    _ = parent_id;
    memory.game.depth += 1;
    const depth = memory.game.depth;

    memory.game.player_velocity = .{ 0, 0 };

    // Mask the last 12 bits (0-4095)
    const player_mask: i64 = SPAN * SPAN * SPAN - 1;
    const new_pos: memory.v2i64 = .{
        (memory.game.player_pos[0] << SPAN_LOG2) & player_mask,
        (memory.game.player_pos[1] << SPAN_LOG2) & player_mask,
    };

    memory.game.teleport(null, new_pos);
    // TODO migrate to this logic when implementing portals instead
    // memory.game.set_player_pos(.{ 2048, 2048 });
    // memory.game.set_camera_pos(.{ 2048, 2048 });

    if (depth <= 16) {
        // Just filling up the 64-bit suffix. No rebasing needed yet.
        memory.game.player_chunk[0] = (coord.suffix[0] << SPAN_LOG2) | bx;
        memory.game.player_chunk[1] = (coord.suffix[1] << SPAN_LOG2) | by;

        // Update the maximum possible suffix value here using some fancy bit-shifting logic
        max_possible_suffix = if (depth == 16)
            std.math.maxInt(u64)
        else
            (@as(u64, 1) << @intCast(depth * SPAN_LOG2)) - 1;

        return;
    }

    // Here, we use a fixed-point rebasing algorithm.
    // Basically, our goal is to maximize the distance the player has to go before the game crashes (from being unable to represent a Coordinate using a valid quadrant).
    // We can consider this problem on depth increase (handled in this function) as turning the ordinary 2x2 grid of "cells" (4 quadrants) into a 32x32 grid instead (since we are increasing by a depth, this makes logical sense).
    // We're trying to "select" which cell should be our top left one with this algorithm.

    // Using the coordinate, we determine which cell in the current 32x32 grid the player is. Call this cell's coordinates (x, y). In this cell, we find which corner the player is closest to (using coordinate and bx/by as tie-breaker).
    // If the player is on the left half of a cell, we shift the window left by 1 (subtract 1).
    // If they are on the right half, we keep the window aligned with the cell (no subtraction).

    // This ensures the player always has at least 1 cell of padding in all directions before hitting the edge of the 2x2 QuadCache.
    // We also clamp both axes for the new cell's coordinates to be between 0 and 30, so the 2x2 window doesn't exceed the parent's 32x32 bounds.

    // The actual implementation applies all this logic by doing a bunch of management work between the "prefix" (big ArrayList) and "suffix" (coordinate of the player), and updates the quadrant of where the player is as necessary. We want to select the right prefix, and move the player to the correct quadrant and position.

    // identify the bits falling off the top (the "oldest" part of the suffix that will get merged into the QC path)
    const shift = 64 - SPAN_LOG2; // 60
    const top_x = coord.suffix[0] >> shift;
    const top_y = coord.suffix[1] >> shift;

    // determine if the player is in the left/top half of the new zoomed-in area
    // do this by masking out the top 4 bits to look at the remaining 60 bits of precision
    const midpoint: u64 = 1 << (shift - 1);
    const is_more_left = (coord.suffix[0] & 0x0FFFFFFF_FFFFFFFF) < midpoint;
    const is_more_top = (coord.suffix[1] & 0x0FFFFFFF_FFFFFFFF) < midpoint;

    const parent_quadrant_x = utils.intFromBool(u64, (memory.game.player_quadrant % 2) != 0); // old quadrant
    const parent_quadrant_y = utils.intFromBool(u64, (memory.game.player_quadrant / 2) != 0);
    const naive_cell_x = (parent_quadrant_x << SPAN_LOG2) | top_x; // value from 0-31 that does not consider the midpoint calculation
    const naive_cell_y = (parent_quadrant_y << SPAN_LOG2) | top_y;

    // determine the origin for the NEW QuadCache window relative to the OLD origin
    // subtract 1 if the player is in the left or top half to keep them centered.
    const highest_possible_top_left_cell = (SPAN - 1) * 2; // a mouthful!
    var left_cell_x: u64 = naive_cell_x -| utils.intFromBool(u64, is_more_left); // saturating subtraction effectively acts as @max(n, 0) without @as casting
    var top_cell_y: u64 = naive_cell_y -| utils.intFromBool(u64, is_more_top);
    left_cell_x = @min(left_cell_x, highest_possible_top_left_cell); // clamp (explained above in the big comment section)
    top_cell_y = @min(top_cell_y, highest_possible_top_left_cell);

    // update edge flags used in generate_chunk()
    quad_cache.most_left = quad_cache.most_left and left_cell_x == 0;
    quad_cache.most_right = quad_cache.most_right and left_cell_x == highest_possible_top_left_cell;
    quad_cache.most_top = quad_cache.most_top and top_cell_y == 0;
    quad_cache.most_bottom = quad_cache.most_bottom and top_cell_y == highest_possible_top_left_cell;

    const old_hashes = quad_cache.path_hashes;
    // update the seed lineage for all 4 quadrants
    inline for (0..4) |q_id| {
        const cell_x = left_cell_x + utils.intFromBool(u64, q_id % 2 == 1);
        const cell_y = top_cell_y + utils.intFromBool(u64, q_id >= 2);

        // map this cell back to the specific parent quadrant (0-3)
        const old_q_id = utils.intFromBool(usize, cell_x >= SPAN) + utils.intFromBool(usize, cell_y >= SPAN) * 2;

        quad_cache.path_hashes[q_id] = seeding.mix_coordinate_seed(
            &old_hashes[old_q_id],
            cell_x % SPAN,
            cell_y % SPAN,
        );
    }

    // update the prefix path (which is an ArrayList)
    if ((depth - (SPAN + 1)) % SPAN == 0) {
        quad_cache.left_path.append(arena.allocator(), left_cell_x) catch @panic("quad-cache append failed");
        quad_cache.top_path.append(arena.allocator(), top_cell_y) catch @panic("quad-cache append failed");
    } else {
        // quad_cache.left_path.len - 1 = (depth - 1) / 16 - 1
        const last_path_index: usize = @intCast((depth - 1) / 16 - 1);
        const l_ptr: *u64 = quad_cache.left_path.at(last_path_index);
        const t_ptr: *u64 = quad_cache.top_path.at(last_path_index);

        l_ptr.* = (l_ptr.* << SPAN_LOG2) + left_cell_x;
        t_ptr.* = (t_ptr.* << SPAN_LOG2) + top_cell_y;
    }

    // finalize player state
    memory.game.player_chunk[0] = (coord.suffix[0] << SPAN_LOG2) | bx;
    memory.game.player_chunk[1] = (coord.suffix[1] << SPAN_LOG2) | by;

    const quadrant_x = naive_cell_x - left_cell_x;
    const quadrant_y = naive_cell_y - top_cell_y;
    memory.game.player_quadrant = @intCast(quadrant_x + (quadrant_y * 2));
}

// /// Convert screen pixels to a world block coordinate
// pub fn screen_to_world(screen_x: f64, screen_y: f64, viewport_w: f64, viewport_h: f64, cam_x: f64, cam_y: f64, zoom: f64) @Vector(2, f64) {
//     const target_chunk_offset_x = @divFloor(world_subpixel_x, 4096);
//     const target_chunk_offset_y = @divFloor(world_subpixel_y, 4096);

//     const target_chunk_x = game.player_chunk[0] +% @as(u64, @bitCast(target_chunk_offset_x));
//     const target_chunk_y = game.player_chunk[1] +% @as(u64, @bitCast(target_chunk_offset_y));

//     const block_x = @divFloor(@mod(world_subpixel_x, 4096), 256);
//     const block_y = @divFloor(@mod(world_subpixel_y, 4096), 256);

//     // Returns exact block coordinate. @floor() this to get the integer block index.
//     return .{ world_x / SPAN, world_y / SPAN };
// }
