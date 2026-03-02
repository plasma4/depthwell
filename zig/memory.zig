//! Manages memory for WASM.
const std = @import("std");
const builtin = @import("builtin");
const ColorRGBA = @import("color_rgba.zig").ColorRGBA;
pub const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;

// Only create an actual GPA instance if building for native.
var gpa = if (!is_wasm and !builtin.is_test)
    std.heap.GeneralPurposeAllocator(.{}){}
else
    struct {}{};

pub const allocator = if (is_wasm)
    std.heap.wasm_allocator
else if (builtin.is_test)
    std.testing.allocator
else
    gpa.allocator();

/// 64 bytes is a good alignment size.
pub const MAIN_ALIGN: usize = 64;
/// 64 bytes for WebGPU alignment.
pub const GPU_ALIGN: usize = 64;

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

/// Tightly packed data for a block to be sent to WebGPU.
const BlockInstance = extern struct {
    /// Position in screen-space pixels (after camera transform)
    location: @Vector(2, f32),
    /// Which sprite to use (index into texture atlas)
    sprite_id: u16,
    /// Edge flags: which neighbors are air (for edge darkening shader).
    /// Starts from top left, then middle left, and ending at bottom right (skipping itself).
    edge_flags: u8,
    /// Light level (0-255, shader interpretation TODO)
    light: u8,
    /// Per-block seed for procedural variation in shader. Separate from seeding when zooming in/time-based changes in lighting or shaders.
    variation_seed: u32,

    /// Returns x-coordinate of a block's location.
    pub inline fn x(self: anytype) f32 {
        return self.location[0];
    }
    /// Returns x-coordinate of a block's location.
    pub inline fn y(self: anytype) f32 {
        return self.location[1];
    }
};

/// Tightly packed data for a square particle to be sent to WebGPU.
const Particle = extern struct {
    position: @Vector(2, f32),
    d_position: @Vector(2, f32),
    color: ColorRGBA,
    size: f32,
    rotation: f32,
    d_rotation: f32,
};

/// A 256KiB scratch buffer for fast one-time passing through of data like strings or temporary particle data. Assumes fully single-thread communication. A separate, smaller logging_buffer is used in memory.zig.
pub var scratch_buffer: [256 * MemorySizes.KiB]u8 align(MAIN_ALIGN) = undefined;
const fba: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(&scratch_buffer);
const arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(fba.allocator());

/// Data is reserved for numbers or positions that are guaranteed to take a constant amount of memory, or pointers.
/// Important data is meant to be placed at the start with less important data later. See game_state_offsets in types.zig for export to JS.
pub const GameState = extern struct {
    /// Represents the player's position.
    player_pos: @Vector(2, f64) align(MAIN_ALIGN) = .{ 0.0, 0.0 },
    camera_pos: @Vector(2, f64) = .{ 0.0, 0.0 },
    camera_scale: f64 = 1.0,
    seed: [8]u64 align(16) = std.mem.zeroes([8]u64),
};

/// The state of the current game.
pub var game: GameState = .{};

/// The layout structure shared with TypeScript. The MemoryLayout instance will not change locations, but its properties may.
pub const MemoryLayout = extern struct {
    /// Pointer to the scratch buffer.
    scratch_ptr: u64 align(MAIN_ALIGN),
    /// The current length or offset used within the scratch buffer.
    scratch_len: u64,
    /// The total capacity of the fixed scratch buffer (4MB).
    scratch_capacity: u64,
    /// Additional properties for configuring the scratch buffer's meaning (with types.zig and commands.zig) if necessary.
    scratch_properties: [4]u64,
    /// Pointer to the GameState. (Can safely be pointer instead of u64 as it is the LAST property.)
    mem_ptr: *GameState,
};

/// Global static instance of the layout so the pointer remains valid for JS. Starts near the start of a WASM page.
pub var mem: MemoryLayout align(MAIN_ALIGN) = .{
    .scratch_ptr = 0, // pointer is set in main.zig's init
    .scratch_len = 0,
    .scratch_capacity = 0,
    .mem_ptr = &game,
    .scratch_properties = std.mem.zeroes([4]u64), // start with empty
};

/// Returns the pointer to the memory layout for TypeScript to consume.
pub fn get_memory_layout_ptr() *align(MAIN_ALIGN) const MemoryLayout {
    return &mem;
}

/// Allocates memory in WASM that JS can write to.
pub fn wasm_alloc(len: usize) ?[*]u8 {
    const slice = allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

/// Frees memory allocated via wasm_alloc.
pub fn wasm_free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

/// Allocation in the scratch buffer using the offset. Expands via the system allocator if full.
pub fn scratch_alloc(len: usize) ?[*]u8 {
    const addr = @intFromPtr(&scratch_buffer);
    // Use usize for WASM32 compatibility
    const current_addr = addr + @as(usize, @intCast(mem.scratch_len));
    const aligned_addr = std.mem.alignForward(usize, current_addr, MAIN_ALIGN);
    const new_offset = (aligned_addr - addr) + len;

    if (new_offset <= scratch_buffer.len) {
        mem.scratch_len = new_offset;
        return @ptrFromInt(aligned_addr);
    }

    const slice = allocator.alignedAlloc(u8, comptime std.mem.Alignment.fromByteUnits(MAIN_ALIGN), len) catch return null;
    return slice.ptr;
}

/// Allocates space in scratch buffer and copies the provided data into it if necessary.
pub fn scratch_copy(data: []const u8) ?[*]u8 {
    const ptr = scratch_alloc(data.len) orelse return null;
    @memcpy(ptr[0..data.len], data);
    return ptr;
}

/// Resets the scratch offset for the next frame/operation. (JS doesn't call this and instead uses handy functions in engine.ts.)
pub inline fn scratch_reset() void {
    mem.scratch_len = 0;
}

const _ = {
    if (MAIN_ALIGN < 16 || (MAIN_ALIGN % 16 > 0)) {
        @compileError("MAIN_ALIGN should be a positive multiple of 16 for SIMD alignment.");
    }
    if (GPU_ALIGN < 64 || (GPU_ALIGN % 64 > 0)) {
        @compileError("GPU_ALIGN should be a positive multiple of 64 for WebGPU alignment.");
    }
};
