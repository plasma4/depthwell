//! Contains important datatypes, some of which bridge WASM and Zig, as well as scratch buffer logic. Also contains some structs and commonly used constants.
const std = @import("std");
const builtin = @import("builtin");
const root = @import("root").root;
const Sprite = root.Sprite;
const types = root.types;
const logger = root.logger;
const player = root.player;
const ColorRGBA = root.ColorRGBA;
const seeding = root.seeding;
const world = root.world;

/// Represents log2(SPAN).
pub const SPAN_LOG2: comptime_int = 4;
/// The main number (as an integer) representing the number of blocks in a chunk, number of pixels in a block, and number of subpixels in a pixel. (Note that changing these values WILL break the code!)
pub const SPAN: comptime_int = 16;
/// The main number (as a float) representing the number of blocks in a chunk, number of pixels in a block, and number of subpixels in a pixel.
pub const SPAN_FLOAT: comptime_float = @floatFromInt(SPAN);
/// An integer representing the number of subpixels in a block, pixels in a chunk, number of blocks in a chunk, number of pixels in a block, and number of possible subpixel positions within a pixel.
pub const SPAN_SQ: comptime_int = SPAN * SPAN;
/// A float representing the number of subpixels in a block, pixels in a chunk, number of blocks in a chunk, number of pixels in a block, and number of possible subpixel positions within a pixel.
pub const SPAN_FLOAT_SQ: comptime_float = SPAN_FLOAT * SPAN_FLOAT;
/// An integer representing the number of subpixels within a chunk. The player's X and Y coordinate should wrap around such that it is between 0 and this value (inclusive).
pub const SUBPIXELS_IN_CHUNK: comptime_int = SPAN * SPAN * SPAN;

pub const Vec2i = @Vector(2, i64);
pub const Vec2u = @Vector(2, u64);
pub const Vec2f = @Vector(2, f64);
pub const Vec2f32 = @Vector(2, f32);

/// Non-pointer data (short known length) representing part of the game state.
/// Data is reserved for numbers or positions that are guaranteed to take a constant amount of memory, or pointers.
/// Important data is meant to be placed at the start with less important data later. Data can be rearranged, but requires using the -Dgen-enums for pointer locations to be reflected in TypeScript. See game_state_offsets in types.zig for enum export details.
pub const GameState = extern struct {
    /// Represents the player's subpixel position within the CURRENT chunk (0 to 4095), from the CENTER of the sprite.
    player_pos: Vec2i align(MAIN_ALIGN_BYTES) = .{ 0, 0 },
    /// Represents the player's previous subpixel position.
    /// Importantly, this is not necessarily equal to the player's velocity, as this handles teleports!
    last_player_pos: Vec2i = .{ 0, 0 },
    /// Represents the player's active chunk coordinate.
    player_chunk: Vec2u = .{ 0, 0 },
    /// Represents the player's current movement velocity.
    player_velocity: Vec2f = .{ 0, 0 },
    /// Represents the camera's position.
    camera_pos: Vec2i = .{ 0, 0 },
    /// Represents the camera's movement in a frame (derivative of `camera_pos`).
    last_camera_pos: Vec2i = .{ 0, 0 },
    /// Represents the camera's zoom scale.
    camera_scale: f64 = player.CAMERA_MAX_ZOOM,
    /// Represents the camera's zoom scale change rate (multiplier, acts as derivative of camera_scale change).
    camera_scale_change: f64 = 1.0,
    /// Represents how many layers deep the player is (defaults to 3).
    depth: u64 = 0,

    /// Represents which quadrant (0-3) of the `QuadCache` the player is in (starts at 0 when depth is <= 16).
    /// (0: NW, 1: NE, 2: SW, 3: SE)
    player_quadrant: u32 = 0,

    /// Current frame ID. 32-bit; expect wrap-arounds and access with powers-of-2 checks.
    frame: u32 = 0,

    // /// Represents if the grid needs to be recalculated/passed to WGSL.
    // grid_dirty: bool = true,
    // last_grid_min_bx: u32 = 0,
    // last_grid_min_by: u32 = 0,
    // last_player_chunk_x: u64 = 0,
    // last_player_chunk_y: u64 = 0,

    /// Represents the keys that were pressed THIS FRAME. (On the next frame, this will be reset to 0.)
    ///
    /// Example:
    /// ```zig
    /// logger.log(@src(), "{}", .{KeyBits.isSet(KeyBits.up, memory.game.keys_pressed_mask)}); // Gets if UP key was pressed this frame.
    /// ```
    keys_pressed_mask: u32 = 0,
    /// Represents the keys that are currently HELD DOWN.
    ///
    /// Example:
    /// ```zig
    /// logger.log(@src(), "{}", .{KeyBits.isSet(KeyBits.up, memory.game.keys_held_mask)}); // Gets if UP key is being held down.
    /// ```
    keys_held_mask: u32 = 0,

    /// The initial or "global" seed from which all generation starts.
    seed: seeding.Seed align(16) = std.mem.zeroes(seeding.Seed),

    /// Second seed based on the original `seed` value: derived from `ChaCha12` for use in `FastHash`.
    seed2: [16]u64 align(16) = std.mem.zeroes([16]u64),

    /// Gets the player's current chunk location as a `Coordinate`.
    pub inline fn getPlayerCoord(self: *const @This()) Coordinate {
        return .{ .quadrant = @intCast(self.player_quadrant), .suffix = self.player_chunk };
    }

    /// Gets which (x-coordinate) block the player is "on" within a chunk. Based on the player's center, rounded down.
    pub inline fn getBlockXInChunk(self: *const @This()) u4 {
        return @intCast(@divTrunc(self.player_pos[0], SPAN_SQ));
    }
    /// Gets which (y-coordinate) block the player is "on" within a chunk. Based on the player's center, rounded down.
    pub inline fn getBlockYInChunk(self: *const @This()) u4 {
        return @intCast(@divTrunc(self.player_pos[1], SPAN_SQ));
    }

    /// Teleports the player, resetting the player position and camera position, as well as movement constants such as gravity.
    ///
    /// Also fully clears caches.
    pub inline fn teleport(self: *@This(), coord: ?Coordinate, new_position: Vec2i) void {
        player.subpixel_accum = .{ 0.0, 0.0 };
        self.player_velocity = .{ 0.0, 0.0 };
        if (coord) |c| {
            self.player_quadrant = c.quadrant;
            self.player_chunk = c.suffix;
        }
        self.player_pos = new_position;
        self.last_player_pos = new_position;
        self.camera_pos = .{ 0.0, 0.0 };
        world.clearCaches();
    }

    /// Sets the player position within a chunk, teleporting the previous position as well. Also clears subpixel accumulation/velocity.
    /// Considered dumb. Do not use for movement, as this neither does frame interpolation nor takes `Coordinate` input for correct quadrant changes.
    ///
    /// It is probably better to use `teleport()`, unless you need the player position to change but not the camera.
    /// This function also fails to handle caches properly.
    pub inline fn setPlayerPosDumb(self: *@This(), new_position: Vec2i) void {
        player.subpixel_accum = .{ 0.0, 0.0 };
        self.player_velocity = .{ 0.0, 0.0 };
        self.player_pos = new_position;
        self.last_player_pos = new_position;
    }

    /// Sets the camera position within a chunk, teleporting the previous position as well.
    /// Do not use for movement. Also clears subpixel accumulation.
    ///
    /// It is probably better to use `teleport()`, unless you need the camera position to change but not the player.
    /// This function also fails to handle caches properly.
    pub inline fn setCameraPosDumb(self: *@This(), new_position: Vec2i) void {
        player.subpixel_accum = .{ 0.0, 0.0 };
        self.camera_pos = new_position;
        self.last_camera_pos = new_position;
    }
};

/// The state of the current game, containing pre-allocated properties.
pub var game: GameState = undefined;

/// System-level allocator for pages. On WASM, this grows the linear heap. On native, this
/// requests pages from the OS. Use as a backing for other allocators.
pub const page_allocator = if (builtin.is_test) std.testing.allocator else std.heap.page_allocator;

/// An instance of the general-purpose allocator (or testing allocator when running tests).
/// Use `makeArena()` to create an `ArenaAllocator` around this (WASM has no SMP allocator support).
const main_allocator = if (builtin.is_test) std.testing.allocator else if (builtin.single_threaded) std.heap.brk_allocator else std.heap.smp_allocator; // use .allocator() for instance

/// Creates an `ArenaAllocator` around either the WASM allocator, testing allocator, or GPA, as necessary. It is usually preferable to utilize the scratch buffer for temporary calculations through a callee, store `len` from the caller, and re-access `scratch_ptr`.
///
/// Example:
/// ```zig
/// var arena = memory.makeArena();
/// const allocator = arena.allocator();
/// defer arena.deinit();
/// var list: std.ArrayList(u64) = .empty;
/// list.append(allocator, 12345) catch {};
/// ```
pub fn makeArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(page_allocator);
}

/// Start the scratch buffer with 4 MiB when allocating for the first time.
const STARTING_SCRATCH_BUFFER_SIZE = 4 * MemorySizes.MiB;

/// 64 bytes is an all-round good alignment size in terms of cache pages.
pub const MAIN_ALIGN_BYTES: usize = 64;
/// Type-safe alignment for use with `std.mem.Allocator` functions.
/// Derived from `MAIN_ALIGN_BYTES`.
pub const MAIN_ALIGN = std.mem.Alignment.fromByteUnits(MAIN_ALIGN_BYTES);
/// Type-safe alignment for use with `std.mem.Allocator` functions.
/// Derived from `MAIN_ALIGN_BYTES`.
pub const GPU_ALIGN = std.mem.Alignment.fromByteUnits(MAIN_ALIGN_BYTES);

/// Struct for various memory sizes.
pub const MemorySizes = struct {
    /// Represents 1,024 bytes.
    pub const KiB = 1024;
    /// Represents 1,024 * 1,024 bytes.
    pub const MiB = 1024 * 1024;
    /// Represents 1,024 * 1,024 * 1,024 bytes.
    pub const GiB = 1024 * 1024 * 1024;
    /// Represents the size of a WebAssembly page (64KiB).
    pub const wasm_page = 64 * 1024;
};

/// A single block within a chunk. Each block uses 8 bytes.
pub const Block = packed struct(u64) {
    /// Internal sprite ID.
    id: Sprite,
    /// Edge flags: which neighbors are air (for edge-darkening and culling).
    /// Starts from top left, then middle left, and ending at bottom right (skipping itself).
    edge_flags: u8,
    /// The brightness of the tile.
    light: u8,

    /// Per-block seed for procedural variation in the shader.
    seed: u28,
    /// How "mined" the block is. 0 is least mined, 15 is most mined.
    hp: u4,

    /// Makes a simple block of a certain type, with max light and no edge flags and mine level.
    /// Using the BOTTOM 28 bits from `seed_bits` to place into `seed`.
    pub inline fn makeBasicBlock(sprite_type: Sprite, seed_bits: u64) Block {
        return .{
            .id = sprite_type,
            .hp = 0,
            .edge_flags = 0,

            // light only applies to ores in WGSL
            .light = 0,
            .seed = @truncate(seed_bits),
        };
    }

    /// Determines if the block's type is one that should interact with the edge flags and procedural generation. This returns false for edge stone, unlike `is_solid`.
    pub inline fn isFoundation(self: @This()) bool {
        return self.id.isFoundation();
    }

    /// Determines if the block's type is considered solid, and should interact with the physics, player, and edge flags. This returns true for edge stone, unlike `is_solid`.
    pub inline fn isSolid(self: @This()) bool {
        return self.id.isSolid();
    }

    /// Determines if the block's type is `none` (air/void).
    pub inline fn isEmpty(self: @This()) bool {
        return self.id.isEmpty();
    }

    /// Determines if the sprite is stone (or a variation). Excludes edge stone.
    pub inline fn isStone(self: @This()) bool {
        return self.id.isStone();
    }

    /// Determines if the sprite is an ore.
    pub inline fn isOre(self: @This()) bool {
        return self.id.isOre();
    }

    /// Determines if the sprite is a gem.
    pub inline fn isGem(self: @This()) bool {
        return self.id.isGem();
    }

    /// Determines if the sprite is a heatmap (types 65000-65256).
    pub inline fn isHeatmap(self: @This()) bool {
        return self.id.isHeatmap();
    }

    /// Determines if there is a solid block adjacent based on edge flags.
    pub inline fn isAdjacentBlockSolid(self: @This(), direction: comptime_int) bool {
        return (self.edge_flags & direction) != 0;
    }
};

/// 16x16 fixed grid of blocks. Each chunk is 2KiB in size.
pub const Chunk = struct {
    blocks: [SPAN_SQ]Block align(MAIN_ALIGN_BYTES),

    pub inline fn getBlock(self: @This(), x: u4, y: u4) Block {
        return self.blocks[(@as(usize, y) << SPAN_LOG2) | @as(usize, x)];
    }
};

/// Represents a "coordinate", relative to a quad-cache. Stores an "active suffix" as well as the quadrant this coordinate belongs to.
pub const Coordinate = struct {
    // Active suffix (stored as a vector). You can think of the active suffix like 16 u4s packed together for the X and Y coordinate that can be merged with the correct QuadCache quadrant to produce a "complete" path (see `README.md` for more details).
    suffix: Vec2u,
    /// Quadrant ID (00: NW, 1: NE, 2: SW, 3: SE).
    quadrant: u2,

    /// Checks equality between two `Coordinate` values.
    pub fn eql(a: ?Coordinate, b: ?Coordinate) bool {
        if (a == null and b == null) return true;
        if (a == null or b == null) return false;

        return @reduce(.And, a.?.suffix == b.?.suffix) and
            a.?.quadrant == b.?.quadrant;
    }

    /// Adds both an X and Y value, creating a new Coordinate and handling quadrants.
    /// Returns `null` if this change would exceed a quadrant's boundaries (or the game's when depth is <= 16).
    pub fn move(self: @This(), shift: Vec2i) ?Coordinate {
        const dx = shift[0];
        const dy = shift[1];
        if (dx == 0 and dy == 0) return self;
        const depth = game.depth;
        var res = self;

        // X Axis
        if (dx != 0) {
            const is_pos = dx > 0;
            const delta: u64 = if (is_pos) @intCast(dx) else @intCast(-%dx);
            const ov = if (is_pos) @addWithOverflow(res.suffix[0], delta) else @subWithOverflow(res.suffix[0], delta);
            if (ov[1] != 0) {
                if (depth <= 16) return null;
                if (is_pos == ((res.quadrant & 1) != 0)) return null;
                res.quadrant ^= 1;
            }
            res.suffix[0] = ov[0];
        }

        // Y Axis
        if (dy != 0) {
            const is_pos = dy > 0;
            const delta: u64 = if (is_pos) @intCast(dy) else @intCast(-%dy);
            const ov = if (is_pos) @addWithOverflow(res.suffix[1], delta) else @subWithOverflow(res.suffix[1], delta);
            if (ov[1] != 0) {
                if (depth <= 16) return null;
                if (is_pos == ((res.quadrant & 2) != 0)) return null;
                res.quadrant ^= 2;
            }
            res.suffix[1] = ov[0];
        }
        return res;
    }

    /// Adds a certain X value, creating a new Coordinate and handling quadrants.
    /// Returns `null` if this change would exceed a quadrant's boundaries (or the game's when depth is <= 16).
    pub inline fn moveX(self: @This(), x: i64) ?Coordinate {
        return self.move(.{ x, 0 });
    }

    /// Adds a certain Y value, creating a new Coordinate and handling quadrants.
    /// Returns `null` if this change would exceed a quadrant's boundaries (or the game's when depth is <= 16).
    pub inline fn moveY(self: @This(), y: i64) ?Coordinate {
        return self.move(.{ 0, y });
    }
};

/// Dense storage for a modified chunk.
pub const ModifiedChunk = struct {
    /// 256 bits representing which blocks have been modified.
    /// Bit index corresponds to (y * 16 + x).
    modified_mask: [4]u64,
    /// The specific modified block IDs. Only indices with a 1 in `modified_mask` are valid.
    blocks: [SPAN_SQ]Sprite,

    /// Helper to check if a specific local block is modified
    pub inline fn isModified(self: *const @This(), lx: u4, ly: u4) bool {
        const index = (@as(u8, ly) << SPAN_LOG2) | @as(u8, lx);
        const slot = index >> 6;
        const bit = @as(u6, @truncate(index));
        return (self.modified_mask[slot] & (@as(u64, 1) << bit)) != 0;
    }
};

/// Data for a single particle (converted to `WGSLEntity` before sending to WGSL).
pub const Particle = struct {
    /// Current position (based on internal viewport).
    position: Vec2f32,

    /// Velocity vector for position.
    d_position: Vec2f32,

    /// The color of the particle (alpha is multiplied by time and how long the particle lasts).
    color: ColorRGBA,
    /// The size of the particle.
    size: f32,
    /// The opacity of the particle (based on time start/end).
    opacity: f32,

    /// The rotation of the particle (radians).
    rotation: f32,
    /// The rate of change of rotation of the particle (radians).
    d_rotation: f32,

    /// The time at which the particle spawned in from (performance.now()).
    time_start: f64,

    /// The time at which the particle will disappear.
    time_end: f64,
};

pub const DEFAULT_ENTITY_LCHA: @Vector(4, f32) = .{ 1.0, 0.0, 0.0, 1.0 };

/// Entity data (before being sent to WGSL, using internal viewport).
/// Allows for size, rotation, and OKLCH + alpha (opacity) changes to any chosen sprite.
pub const Entity = struct {
    /// The light, chroma, hue, and opacity components (HSL + alpha).
    /// L (lightness) and alpha components are multiplied by the sprite's color in WGSL.
    /// H (hue, in radians) and C (chroma) are shifted additively.
    lcha: @Vector(4, f32) = DEFAULT_ENTITY_LCHA,

    /// Current position (based on internal viewport).
    position: Vec2f32,

    /// The size of the entity (based on internal viewport).
    size: f32 = 16.0,

    /// The rotation of the entity (radians).
    rotation: f32 = 0.0,

    /// The sprite type of the entity to use.
    sprite: Sprite = .none,
};

/// Tightly packed data for a entity to be sent directly to WGSL (using UV coordinates).
/// Allows for size, rotation, and OKLCH + alpha (opacity) changes to any chosen sprite.
pub const WGSLEntity = extern struct {
    /// The light, chroma, hue, and opacity components (HSL + alpha).
    /// L (lightness) and alpha components are multiplied by the sprite's color in WGSL.
    /// H (hue) and C (chroma) are shifted additively in radians.
    lcha: @Vector(4, f32) align(16),

    /// Current position (based on UV, not the internal viewport).
    position: Vec2f32,

    /// The width and height of the entity (based on UV, not the internal viewport).
    size: Vec2f32,

    /// The rotation of the entity (radians).
    rotation: f32,

    /// The ID of the entity (sprite type).
    id: u32,
};

/// A dynamically expandable scratch buffer for fast one-time passing through of data like strings or temporary particle data.
/// Assumes fully single-thread communication. A separate, smaller logging_buffer is used in logger.zig.
///
/// Information in the scratch buffer should be assumed to be corrupted as soon as any other function that could modify the scratch buffer is called and thought of as a temporary "handshake" between Zig and TypeScript.
pub var scratch_buffer: []align(MAIN_ALIGN_BYTES) u8 = &[_]u8{};
var is_dynamic_scratch: bool = false;

/// The layout structure shared with TypeScript. The MemoryLayout instance will not change locations, but its properties may.
pub const MemoryLayout = extern struct {
    /// 64-bit integeric pointer to the scratch buffer.
    scratch_ptr: u64 align(MAIN_ALIGN_BYTES),
    /// The current length or offset used within the scratch buffer.
    scratch_len: u64,
    /// The total capacity of the fixed scratch buffer (starts off at 4 MiB).
    scratch_capacity: u64,
    /// 64-bit integeric pointer to the GameState.
    game_ptr: u64,
    /// Additional properties for sending additional (numeric, pointer, or short fixed-length) properties. Information in the scratch properties should be assumed to be corrupted as soon as any other function that could modify the scratch buffer is called. This array should be thought of as a temporary "handshake" to trade information between Zig and TypeScript. Consider utilizing function arguments instead when sending data to Zig.
    scratch_properties: [20]u64,
};

/// Global static instance of the layout so the pointer remains valid for JS. Starts near the start of a WASM page.
pub var mem: MemoryLayout align(MAIN_ALIGN_BYTES) = .{
    .scratch_ptr = 0, // pointer is set in startup.zig's init
    .scratch_len = 0,
    .scratch_capacity = 0,
    .game_ptr = 0,
    .scratch_properties = std.mem.zeroes([20]u64), // start with empty
};

/// Returns the pointer to the memory layout for TypeScript to consume.
pub fn getMemoryLayoutPtr() *align(MAIN_ALIGN_BYTES) const MemoryLayout {
    mem.scratch_ptr = @intFromPtr(&scratch_buffer);
    mem.game_ptr = @intFromPtr(&game);
    return &mem;
}

/// Allocates memory in WASM that JS can write to.
pub fn wasmAlloc(len: usize) ?[*]u8 {
    const slice = main_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

/// Frees memory allocated via wasm_alloc.
pub fn wasmFree(ptr: [*]u8, len: usize) void {
    main_allocator.free(ptr[0..len]);
}

/// Determines if scratch_buffer has at least `len` additional available capacity while aligning with `MAIN_ALIGN`.
/// If not, expands with the system's page allocator.
/// Does NOT set the `scratch_len` property; only allocates sufficiently (using `scratch_capacity`).
pub fn scratchAlloc(len: usize) [*]u8 {
    const base_addr = @intFromPtr(scratch_buffer.ptr);
    const current_used: usize = @intCast(mem.scratch_len);
    const current_addr = base_addr + current_used;
    const aligned_addr = std.mem.alignForward(usize, current_addr, MAIN_ALIGN_BYTES);
    const new_scratch_len = (aligned_addr - base_addr) + len;

    if (!is_dynamic_scratch or new_scratch_len > scratch_buffer.len) {
        @branchHint(.cold);
        return growScratchBuffer(len, new_scratch_len);
    }

    // Fits in existing buffer already, fast!
    mem.scratch_len = @intCast(new_scratch_len);
    return @ptrFromInt(aligned_addr);
}

/// Internal function to grow the scratch buffer.
fn growScratchBuffer(len: usize, new_scratch_len: usize) [*]u8 {
    const current_used: usize = @intCast(mem.scratch_len);

    // Final capacity becomes 256KiB, 1.5x growth, or the requested length, whichever is largest.
    const growth_150_percent = scratch_buffer.len + (scratch_buffer.len >> 1);
    const clamped_growth = @min(growth_150_percent, scratch_buffer.len + (32 * MemorySizes.MiB));
    const new_cap = @max(STARTING_SCRATCH_BUFFER_SIZE, clamped_growth, new_scratch_len);

    if (!is_dynamic_scratch) {
        @branchHint(.cold);
        scratch_buffer = page_allocator.alignedAlloc(u8, MAIN_ALIGN, new_cap) catch @panic("Ran out of memory for scratch allocation!");
        is_dynamic_scratch = true;
    } else {
        scratch_buffer = page_allocator.realloc(scratch_buffer, new_cap) catch @panic("Ran out of memory for scratch allocation!");
    }

    // Update JS metadata
    mem.scratch_ptr = @intFromPtr(scratch_buffer.ptr);
    mem.scratch_capacity = scratch_buffer.len;

    // Re-calculate the return pointer based on the new base address
    const updated_base = @intFromPtr(scratch_buffer.ptr);
    const updated_aligned = std.mem.alignForward(usize, updated_base + current_used, MAIN_ALIGN_BYTES);
    mem.scratch_len = @intCast((updated_aligned - updated_base) + len);
    return @ptrFromInt(updated_aligned);
}

/// Allocates one instance of a type in a scratch buffer.
/// This is the ideal fast way to write generic data (like entities) if the total amount is unknown.
///
/// The `byte_count_before_end` property, if `null`, makes the data aligned to `MAIN_ALIGN_BYTES`.
/// If unaligned, it is required to start the data at an aligned location (such as right after `scratch_reset` or `mem.scratch_len` set).
pub inline fn scratchAllocType(comptime T: type, byte_count_before_end: ?*usize) *T {
    const type_size: usize = @sizeOf(T);
    const mod = type_size % MAIN_ALIGN_BYTES;
    if (byte_count_before_end == null or mod == 0) {
        const ptr = scratchAlloc(type_size);
        return @as(T, @ptrCast(@alignCast(ptr)));
    }

    // ask for more and find the right position!
    const before_end = byte_count_before_end.?.*;
    var diff = type_size -| before_end;
    const old_len = mem.scratch_len; // can't trust scratch_alloc lengths

    if (diff == 0) diff = type_size;
    const ptr: [*]u8 = @ptrFromInt(
        @as(usize, @intCast(mem.scratch_ptr + mem.scratch_len)),
    );
    if (type_size < MAIN_ALIGN_BYTES and diff > 0) _ = scratchAlloc(diff);
    mem.scratch_len = old_len + type_size;

    byte_count_before_end.?.* = (before_end + MAIN_ALIGN_BYTES - type_size) % MAIN_ALIGN_BYTES;
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

/// Allocates a typed slice in the scratch buffer (aligned).
/// This is the ideal fast way to write structural data (like chunks) directly into the buffer if length is known up front.
pub inline fn scratchAllocSlice(comptime T: type, count: usize) []T {
    const byte_count = count * @sizeOf(T);
    const ptr = scratchAlloc(byte_count);
    return @as([*]T, @ptrCast(@alignCast(ptr)))[0..count];
}

/// Views the entire used portion of the scratch buffer as a single typed slice.
/// Note: This will error if `mem.scratch_len` is not an exact multiple of `@sizeOf(T)`.
///
/// Only use this if the entire frame's scratch buffer contains a single data type.
pub inline fn scratchAsSlice(comptime T: type) []T {
    const bytes = scratch_buffer[0..mem.scratch_len];
    return std.mem.bytesAsSlice(T, bytes);
}

/// Runs a set of tests (which should be called from JS) for the scratch allocation. (See root.zig for export logic.)
pub fn runScratchAllocTests() void {
    scratchReset();

    // Force starting scratch allocation (if it hadn't existed already).
    const len1 = 100;
    _ = scratchAlloc(len1);

    const heap_cap = scratch_buffer.len;
    const current_used = std.mem.alignForward(usize, @intCast(mem.scratch_len), MAIN_ALIGN_BYTES);
    if (STARTING_SCRATCH_BUFFER_SIZE < len1 or scratch_buffer.len != STARTING_SCRATCH_BUFFER_SIZE) @panic("Scratch buffer length does not match starting buffer size");

    if (heap_cap <= current_used) @panic("Bootstrap failed to provide excess capacity");
    const rem = heap_cap - current_used;

    // Fill to the exact amount of capacity
    _ = scratchAlloc(rem);
    if (scratch_buffer.len != heap_cap) @panic("Buffer expanded before reaching capacity");
    logger.log(@src(), "Requested {d} bytes successfully without buffer expansion.", .{rem});

    // force expansion and reallocate
    const len_exp = 64;
    _ = scratchAlloc(len_exp);

    if (scratch_buffer.len <= heap_cap) @panic("Buffer failed to grow after exceeding capacity");
    if (mem.scratch_ptr != @intFromPtr(scratch_buffer.ptr)) @panic("JS pointer desync");

    scratchReset();
    logger.log(@src(), "Scratch tests passed! Final capacity: {d} bytes.", .{scratch_buffer.len});
}

/// Resets the scratch offset for the next frame/operation. (JS doesn't call this and instead uses handy functions in engine.ts.)
pub inline fn scratchReset() void {
    mem.scratch_len = 0;
}

/// Sets a scratch property (uses generic compile-time inferences).
pub inline fn setScratchProp(index: usize, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .float => mem.scratch_properties[index] = @bitCast(@as(f64, @floatCast(value))),
        .int => |int_info| {
            if (int_info.signedness == .signed) {
                mem.scratch_properties[index] = @bitCast(@as(i64, @intCast(value)));
            } else {
                mem.scratch_properties[index] = @as(u64, @intCast(value));
            }
        },
        .comptime_float => mem.scratch_properties[index] = @bitCast(@as(f64, value)),
        .comptime_int => mem.scratch_properties[index] = @bitCast(@as(i64, value)),
        else => @compileError("Unsupported type for set_scratch_prop: " ++ @typeName(T)),
    }
}

/// Gets a scratch property as u64.
pub inline fn getScratchProp(index: usize) u64 {
    return mem.scratch_properties[index];
}

/// Gets a scratch property as i64.
pub inline fn getSignedScratchProp(index: usize) i64 {
    return @bitCast(mem.scratch_properties[index]);
}

/// Gets a scratch property as f64.
pub inline fn getFloatScratchProp(index: usize) f64 {
    return @bitCast(mem.scratch_properties[index]);
}

const _ = {
    if (STARTING_SCRATCH_BUFFER_SIZE <= 0 || (STARTING_SCRATCH_BUFFER_SIZE % @alignOf(@TypeOf(scratch_buffer)) != 0)) {
        @compileError("Buffer size must be a positive multiple of its alignment.");
    }
    if (MAIN_ALIGN_BYTES < 16 || (MAIN_ALIGN_BYTES % 16 > 0)) {
        @compileError("MAIN_ALIGN_BYTES should be a positive multiple of 16 for SIMD alignment.");
    }
    if (@sizeOf(Block) != 8) {
        @compileError("Memory size for each block should be 8 bytes.");
    }
    if (@sizeOf(WGSLEntity) != 48) {
        @compileError("WGSL entity must be 48 bytes!");
    }
};
