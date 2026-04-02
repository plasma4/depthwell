//! Defines the architecture of the fractal world, which is a segmented fractal coordinate system that uses a quad-cache for coordinates and corresponding seeds.
const std = @import("std");
const memory = @import("memory.zig");
const logger = @import("logger.zig");
const types = @import("types.zig");
const seeding = @import("seeding.zig");
const procedural = @import("procedural.zig");

const Chunk = memory.Chunk;
const Block = memory.Block;
const Coordinate = memory.Coordinate;
const SPAN = memory.SPAN;
const SPAN_FLOAT = memory.SPAN_FLOAT;
const SPAN_LOG2 = memory.SPAN_LOG2;

/// Sprite IDs, based on src/main.png
pub const Sprite = enum(u20) {
    none = 0,
    player = 1,
    edge_stone = 2,
    stone = 3,
    iron = 4,
    grass = 5,
    spiral_plant = 6,
    ceiling_flower = 7,
    mushroom = 8,
    torch = 10,
    unchanged = 1048575,
};

/// Empty block of id `Sprite.none`
pub const AIR_BLOCK: Block = .{ .id = Sprite.none, .seed = 0, .light = 255, .hp = 0, .edge_flags = 0 };

/// 32-bit packed structure representing a single modified block within a chunk.
pub const BlockMod = packed struct(u32) {
    /// The type of the block being represented. (Defaults to a special sprite type that represents "same as what procedural generation would say".)
    id: Sprite = Sprite.unchanged,
    /// The edge flags. TODO decide if we want modifications to actually update edge flags or if these should be updated dynamically.
    edge_flags: u8 = undefined,
    /// How "mined" the block is. 0 is least mined, 15 is most mined. Unlike in other games like Terraria, this mined state is permanent and isn't "quietly undone" without player action.
    hp: u4 = undefined,
};

/// A full 256-block (chunk) of modifications.
pub const ChunkMod = [memory.SPAN_SQ]BlockMod;

/// A 512-bit key for the ModificationStore.
/// Fits exactly into one 64-byte cache line.
pub const ModKey = extern struct {
    /// Represents 512 bits of data.
    seed: seeding.Seed align(memory.MAIN_ALIGN_BYTES), // aligned for cache size optimization

    pub fn init(base_seed: seeding.Seed, cx: u64, cy: u64) ModKey {
        var key = ModKey{ .seed = base_seed };
        // Safe bijection as Blake3 output is uniformly distributed.
        // XORing spatial data preserves entropy!
        key.seed[0] ^= cx;
        key.seed[1] ^= cy;
        return key;
    }
};

pub const ModKeyContext = struct {
    // pub fn hash(self: @This(), key: ModKey) u64 {
    //     _ = self;
    //     // Fast "folding" of the 512-bit key into a 64-bit hash for the map.
    //     // This is extremely cheap and ensures all bits contribute to the bucket index.
    //     const s = key.seed;
    //     return s[0] ^ s[1] ^ s[2] ^ s[3] ^ s[4] ^ s[5] ^ s[6] ^ s[7];
    // }
    pub fn eql(self: @This(), a: ModKey, b: ModKey) bool {
        _ = self;
        // Zig optimizes this to SIMD if the target supports it.
        return std.mem.eql(u64, &a.seed, &b.seed);
    }
};

const SIM_BUFFER_SIZE = 256;
const CHUNK_CACHE_SIZE = 128;
const CHUNK_POOL_SIZE = SIM_BUFFER_SIZE + CHUNK_CACHE_SIZE;

/// A combined pool of SimBuffer and chunk cache data.
var chunk_pool: [CHUNK_POOL_SIZE]memory.Chunk = undefined;

pub const SimBuffer = struct {
    const sim_buffer_ptr: *[SIM_BUFFER_SIZE]memory.Chunk = chunk_pool[CHUNK_CACHE_SIZE..][0..SIM_BUFFER_SIZE];

    /// Returns the chunk from the specified x and y.
    pub inline fn get_index(cx: u64, cy: u64) usize {
        return (@as(usize, cy & 0xF) << 4) | @as(usize, cx & 0xF);
    }

    /// Sets a chunk from the specified x and y to the chunk instance given.
    pub inline fn set_index(chunk: *const memory.Chunk, cx: u64, cy: u64) void {
        sim_buffer_ptr[(@as(usize, cy & 0xF) << 4) | @as(usize, cx & 0xF)] = chunk;
    }
};

pub const ChunkCache = struct {
    var cache_keys: [CHUNK_CACHE_SIZE]?Coordinate = [_]?Coordinate{null} ** CHUNK_CACHE_SIZE;
    var cache_chunk_data: *[CHUNK_CACHE_SIZE]memory.Chunk = chunk_pool[0..CHUNK_CACHE_SIZE];

    // Clock metadata
    var cache_clock_bits: std.StaticBitSet(CHUNK_CACHE_SIZE) = std.StaticBitSet(CHUNK_CACHE_SIZE).initEmpty();
    var cache_hand: usize = 0;

    /// Retrieves a chunk if it exists, marking it as "recently used"
    pub fn get(coord: Coordinate) ?*memory.Chunk {
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

    pub fn allocate_slot(coord: Coordinate) *memory.Chunk {
        while (true) {
            const idx = cache_hand;
            cache_hand = (cache_hand + 1) % CHUNK_CACHE_SIZE;

            if (cache_clock_bits.isSet(idx)) {
                // Give second chance: clear bit and move hand
                cache_clock_bits.setValue(idx, false);
            } else {
                // Found a "victim" (either null key or ref_bit was 0)
                cache_keys[idx] = coord;
                cache_clock_bits.set(idx); // Mark as recently used
                return &cache_chunk_data[idx];
            }
        }
    }

    /// Inserts a chunk using the clock algorithm to find an eviction candidate.
    pub fn insert(coord: Coordinate, chunk: memory.Chunk) *memory.Chunk {
        while (true) {
            const idx = cache_hand;

            // Advance the hand for next time
            cache_hand = (cache_hand + 1) % CHUNK_CACHE_SIZE;

            // Clock logic: second chance if ref_bit is 1, otherwise evict
            if (cache_clock_bits.isSet(idx)) {
                cache_clock_bits.setValue(idx, false);
            } else {
                cache_keys[idx] = coord;
                cache_chunk_data[idx] = chunk;
                cache_clock_bits.set(idx); // new entries start with ref bit as 1
                return &cache_chunk_data[idx];
            }
        }
    }

    pub fn clear() void {
        @memset(&cache_keys, null); // reset all keys
        cache_clock_bits = std.StaticBitSet(CHUNK_CACHE_SIZE).initEmpty(); // clear bitset
        cache_hand = 0; // reset hand
    }
};

/// Adds 1 to the path as if the ArrayList represented one giant number. Performs allocation; the caller should deinit the path eventually.
fn carry_path(path: *const std.ArrayList(u64)) std.ArrayList(u64) {
    const new_path = path.clone(memory.allocator) catch @panic("carry alloc for QuadCache coordinates failed");
    var carry: u1 = 1;

    for (new_path.items) |*word| {
        // add_res is { .value = result, .overflow = 0 or 1 }
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
    /// The 256-bit hashes for the 4 active quadrants, used for modifications across 16 depths (sequentially from D to D-15). (0: NW, 1: NE, 2: SW, 3: SE)
    path_hashes: [4][16]seeding.Seed align(memory.MAIN_ALIGN_BYTES),
    /// Stores the leftmost QuadCache's X-coordinate.
    left_path: std.ArrayList(u64),
    /// Stores the topmost QuadCache's Y-coordinate.
    top_path: std.ArrayList(u64),
    /// The block IDs for each of the 4 places the QuadCache represents.
    ancestor_materials: [4]Sprite,

    // These 4 properties are used to determine if a QuadCache is at the very edge of the world for chunk gen
    most_top: bool = true,
    most_bottom: bool = true,
    most_left: bool = true,
    most_right: bool = true,

    /// Returns a seed from the lineage history (0 is current later, 15 is D-15.)
    pub inline fn get_lineage_seed(self: *const @This(), quadrant: u2, lookback: u4) seeding.Seed {
        return self.path_hashes[quadrant][lookback];
    }

    /// Returns the X-coordinate path of a specific quadrant. Unreachable call if path is empty (if depth is not > 16).
    pub inline fn get_quadrant_path_x(self: *const @This(), quadrant: u2) std.ArrayList(u64) {
        return if (quadrant % 2 == 0) self.left_path else carry_path(&self.left_path);
    }

    /// Returns the Y-coordinate path of a specific quadrant. Unreachable call if path is empty (if depth is not > 16).
    pub inline fn get_quadrant_path_y(self: *const @This(), quadrant: u2) std.ArrayList(u64) {
        return if (quadrant < 2) self.top_path else carry_path(&self.top_path);
    }

    /// Deallocates a temporary instance of a QuadCache path.
    pub inline fn cleanup_path(self: *const @This(), path: std.ArrayList(u64)) void {
        // Memory comparison is safe because QuadCache will never be de-initialized, top_left_path is always non-empty (so nothing weird), and there's no multicore/async shenanigans here.
        if (self.left_path.items.ptr != path.items.ptr and self.top_path.items.ptr != path.items.ptr) {
            path.deinit(memory.allocator);
        }
    }

    /// Returns the 512-bit seed of a specified quadrant.
    pub inline fn get_quadrant_seed(self: *const @This(), quadrant: u2) seeding.Seed {
        if (memory.game.depth <= 16) return memory.game.seed;
        return self.get_lineage_seed(quadrant, 0);
    }

    /// Resolves the chunk seeds. If depth > 16, uses the quadrant seeds.
    pub inline fn get_chunk_seeds(self: *const @This(), coord: Coordinate) [4]seeding.Seed {
        return seeding.mix_chunk_seeds(self.get_quadrant_seed(coord.quadrant), coord.suffix);
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
pub var quad_cache: QuadCache = .{
    .path_hashes = undefined,
    .left_path = std.ArrayList(u64){
        .items = &[_]u64{},
        .capacity = 0,
    },
    .top_path = std.ArrayList(u64){
        .items = &[_]u64{},
        .capacity = 0,
    },
    .ancestor_materials = .{Sprite.none} ** 4,
};

/// Represents the answer to the question "what is the largest possible suffix value"? 15 at depth 1, 255 at depth 2, capped at 2**64-1 at depth 16 and beyond.
pub var max_possible_suffix: u64 = 0;

/// Temporary storage data for calculations. (In order: chunk above, to the left, to the right, below)
var edge_flags_data: [9]memory.Chunk = undefined;
/// Allocator used for the world.
var alloc = std.mem.Allocator;

/// Creates a new instance of a `Chunk` where specified. Does not update edge flags.
pub fn write_chunk(chunk: *memory.Chunk, coord: Coordinate) void {
    // logger.write(3, .{ "{h}Chunk requested", coord });
    // TODO use SimBuffer

    if (ChunkCache.get(coord)) |cached_ptr| { // see if it's in the cache, if it's not in SimBuffer
        chunk.* = cached_ptr.*; // Copy from cache to caller
        return;
    }

    const new_slot_ptr = ChunkCache.allocate_slot(coord); // we must create the chunk now
    generate_chunk(new_slot_ptr, coord); // generate the data in the cache's memory
    chunk.* = new_slot_ptr.*; // make a copy for a result
    // TODO handle new modification logic when the time comes
}

/// Creates a new instance of a `Chunk`. Does not update edge flags.
pub inline fn get_chunk(coord: Coordinate) memory.Chunk {
    var chunk: memory.Chunk = undefined;
    write_chunk(&chunk, coord);
    return chunk;
}

/// Internal function to generate a whole chunk (considering modifications), given a pointer to where the chunk should be stored and coordinates. Does not go through the cache.
fn generate_chunk(chunk: *memory.Chunk, coord: Coordinate) void {
    const chunk_seeds = quad_cache.get_chunk_seeds(coord);
    const rng1 = seeding.ChaCha12.init(chunk_seeds[0]); // Block generation.
    const rng3 = seeding.ChaCha12.init(chunk_seeds[2]);
    var rng4 = seeding.ChaCha12.init(chunk_seeds[3]); // Visual touches only.

    _ = rng1;
    _ = rng3;

    const cx = coord.suffix[0];
    const cy = coord.suffix[1];
    const quadrant_edge_details = quad_cache.get_quadrant_edge_details(coord.quadrant);

    for (0..SPAN) |block_y| {
        for (0..SPAN) |block_x| {
            const id = (block_y * SPAN) + block_x;

            // TODO make this work with quadcache to still work for edges
            const is_absolute_edge_x = (cx == 0 and block_x == 0 and quadrant_edge_details.most_left) or (cx == max_possible_suffix and block_x == 15 and quadrant_edge_details.most_right);
            const is_absolute_edge_y = (cy == 0 and block_y == 0 and quadrant_edge_details.most_top) or (cy == max_possible_suffix and block_y == 15 and quadrant_edge_details.most_bottom);
            if (is_absolute_edge_x or is_absolute_edge_y) {
                chunk.blocks[id] = make_basic_block(.edge_stone);
                // This does mean there are fewer PRNG .next() calls but this doesn't matter here
                continue;
            }

            // Use density to influence block generation
            const density = procedural.get_value_noise(chunk_seeds[1], @as(f64, @floatFromInt(block_x)) / SPAN, @as(f64, @floatFromInt(block_y)) / SPAN);
            const entropy = rng4.next();
            chunk.blocks[id] = .{
                .id = procedural.generate_initial_block(0.0, density, 0.0),
                .light = @truncate(entropy),
                .seed = @truncate(entropy >> 8),
                .hp = 15,
                .edge_flags = 0, // will be updated in second pass
            };
        }
    }
}

/// Adds edge flags to an already generated chunk. Requests adjacent chunks in a 3x3.
pub fn add_edge_flags(target_chunk: *memory.Chunk, coord: Coordinate) void {
    var edge_flags_calculated = std.mem.zeroes([9]bool); // since getting chunks is way more expensive than a some branch mispredictions here, having pre-calc logic is almost certainly faster vs. generating everything up-front

    for (0..SPAN) |ly| {
        for (0..SPAN) |lx| {
            const id = (ly * SPAN) + lx;
            if (target_chunk.blocks[id].id == .none) continue;

            var flags: u8 = 0;
            inline for (.{ -1, 0, 1 }) |dy| {
                inline for (.{ -1, 0, 1 }) |dx| {
                    if (dx == 0 and dy == 0) continue;

                    const nx = @as(i32, @intCast(lx)) + dx;
                    const ny = @as(i32, @intCast(ly)) + dy;

                    const is_solid = if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16)
                        target_chunk.blocks[@as(usize, @intCast(ny * 16 + nx))].id != .none
                    else blk: {
                        // Offset the nx/ny to the neighbor chunk's space
                        const neighbor_x = @as(usize, @intCast(@mod(nx, 16)));
                        const neighbor_y = @as(usize, @intCast(@mod(ny, 16)));
                        // Determine which of the 9 chunks in our grid to sample
                        const grid_x = if (nx < 0) @as(usize, 0) else if (nx >= 16) @as(usize, 2) else 1;
                        const grid_y = if (ny < 0) @as(usize, 0) else if (ny >= 16) @as(usize, 2) else 1;
                        break :blk {
                            const idx = grid_y * 3 + grid_x;

                            if (!edge_flags_calculated[idx]) {
                                @branchHint(.unlikely); // randomly occurs once
                                const neighbor_coord = coord.move(@as(i64, @intCast(grid_x)) - 1, @as(i64, @intCast(grid_y)) - 1);
                                edge_flags_data[idx] = if (neighbor_coord) |c| get_chunk(c) else std.mem.zeroes(memory.Chunk); // assume being on the edge isn't super likely
                                edge_flags_calculated[idx] = true;
                            }
                            break :blk edge_flags_data[idx].blocks[neighbor_y * 16 + neighbor_x].id != .none;
                        };
                    };

                    if (is_solid) flags |= types.EdgeFlags.get_flag_bit(dx, dy);
                }
            }
            target_chunk.blocks[id].edge_flags = flags;
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

/// Handles entering a portal.
/// `coord` is the chunk the portal is in.
pub fn push_layer(parent_id: Sprite, coord: Coordinate, bx: u4, by: u4) void {
    _ = parent_id;
    memory.game.depth += 1;

    // Mask the last 12 bits (0-4095)
    const player_mask: i64 = SPAN * SPAN * SPAN - 1;
    const new_pos: memory.v2i64 = .{
        (memory.game.player_pos[0] << SPAN_LOG2) & player_mask,
        (memory.game.player_pos[1] << SPAN_LOG2) & player_mask,
    };
    memory.game.player_velocity = .{ 0, 0 };
    memory.game.set_player_pos(new_pos);
    memory.game.set_camera_pos(new_pos);

    // TODO also clear SimBuffer
    ChunkCache.clear();

    if (memory.game.depth <= 16) {
        // Base phase: We are just filling up the 64-bit Suffix. No rebasing needed yet.
        memory.game.player_chunk[0] = (coord.suffix[0] << SPAN_LOG2) | bx;
        memory.game.player_chunk[1] = (coord.suffix[1] << SPAN_LOG2) | by;
        // TODO create most top/left/bottom/right logic
        // Push path hash to stack now! TODO verify+complete all this
        // push_path_to_stack(quad_cache.get_lineage_seed(memory.game.get_player_coord().quadrant, 0)); // Pushes current down, adds to top

        // Update the maximum possible suffix value here using some fancy bit-shifting logic
        max_possible_suffix = if (memory.game.depth < 16)
            (@as(u64, 1) << @intCast(memory.game.depth * memory.SPAN_LOG2)) - 1
        else
            std.math.maxInt(u64);

        return;
    }

    // Extract the 4 bits that are about to fall off the edge of the u64 Suffix
    // const overflow_x = coord.suffix[0] >> 60;
    // const overflow_y = coord.suffix[1] >> 60;

    // Mix these overflow bits into the new PathHash
    // TODO figure out quadrant stuff
    // const new_path_hash = seeding.mix_chunk_seed(quad_cache.get_quadrant_seed(quadrant: u2), .{ overflow_x, overflow_y });
    // push_path_to_stack(new_path_hash);

    // Place the new top-left quadrant between max(d1, d2, d3, d4), where d1-d4 represent how many chunks it would take from the coord to the edge of the world if just travelling up, down, left, and right. Basically, make the QuadCache work for as long as possible by placing it "sort of centered", while making sure to cap it (TODO explain this more clearly)
    const ideal_center: u64 = 0x80000000_00000000;

    // TODO the actual QuadCache array readjustment
    // TODO logic to "clamp" the quadrant so it doesn't go past world bounds, no overflowing, or cap logic fixes this automatically
    memory.game.player_chunk[0] = ideal_center;
    memory.game.player_chunk[1] = ideal_center;
}

// /// Helper to maintain the sliding window of hashes for fast lookups
// fn push_path_to_stack(self: *@This(), new_hash: seeding.Seed) void {
//     // Shift everything down 1
//     var i: usize = 15;
//     while (i > 0) : (i -= 1) {
//         path_stack[i] = path_stack[i - 1];
//     }
//     // Insert new current path at index 0
//     path_stack[0] = new_hash;
// }

/// Multiplies a float by 2**64, returning an integer x such that a random u64 value has its probability to be less than x equal to the chance variable.
pub inline fn odds_num(chance: comptime_float) u64 {
    return @intFromFloat(chance * 18446744073709551616.0);
}

/// Makes a simple block of a certain type, with max light and no edge flags/custom properties.
pub inline fn make_basic_block(sprite_type: Sprite) Block {
    return .{
        .id = sprite_type,
        .seed = 0,
        .light = 255,
        .hp = 0,
        .edge_flags = 0,
    };
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
