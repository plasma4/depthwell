//! Root file. Imports main.zig and handles exporting functions to WASM.
//! All functions here (excluding internal ones like panic) should be `pub` to expose functions to `generate_types.zig`,
//! and `extern` for WASM (with no other exported functions within other Zig files).
const std = @import("std");
const builtin = @import("builtin");
const main = @import("main.zig");
const memory = @import("memory.zig");
const seeding = @import("seeding.zig");
const procedural = @import("internal/procedural.zig");
const logger = @import("logger.zig");
const player = @import("player.zig");
const world = @import("world.zig");
const mouse = @import("mouse.zig");
const KeyBits = @import("types.zig").KeyBits;
const debug_ui = @import("debug_ui.zig");

pub export fn setup() void {
    // TODO destroy World/GameState values as needed if !alreadyStarted
    memory.game = .{}; // initialize GameState
    world.quad_cache = .{
        .path_hashes = undefined,
        .hash_cache_1 = undefined,
        .left_path = std.ArrayList(u64).initCapacity(world.alloc, 4096) catch unreachable,
        .top_path = std.ArrayList(u64).initCapacity(world.alloc, 4096) catch unreachable,
        .ancestor_materials = .{.none} ** 4,
    };
}
pub export fn init() void {
    main.init();
}
pub export fn prepare_visible_chunks(time_interpolated: f64, canvas_w: f64, canvas_h: f64) void {
    main.prepare_visible_chunks(time_interpolated, canvas_w, canvas_h);
}

pub export fn get_tiles_per_row() u32 {
    // return world.max_sprite_value + 1; // the length is the highest value + 1
    return 10;
}
pub export fn get_tiles_per_column() u32 {
    return (world.max_sprite_value + 1 + 9) / 10; // act as a ceil
}
pub export fn get_stone_start() u32 {
    return @intCast(@intFromEnum(world.Sprite.stone));
}
pub export fn get_ore_start() u32 {
    return @intCast(@intFromEnum(world.Sprite.amethyst));
}
pub export fn get_gem_mask_start() u32 {
    return @intCast(@intFromEnum(world.Sprite.gem_mask));
}
pub export fn get_decor_start() u32 {
    return @intCast(@intFromEnum(world.Sprite.spiral_plant));
}

pub export fn handle_mouse(mouse_x: f64, mouse_y: f64, action: u32) void {
    mouse.handle_mouse(mouse_x, mouse_y, action);
}

pub export fn tick(speed: f64, iterations: u32) void {
    // increase the depth (testing hotkey)
    if (KeyBits.isSet(KeyBits.zoom, memory.game.keys_pressed_mask)) {
        // if (in_debug_mode) {
        world.push_layer(
            world.Sprite.none,
            memory.game.get_player_coord(),
            memory.game.get_block_x_in_chunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.get_block_y_in_chunk(),
        );
        // }
    }

    for (0..iterations) |_| { // iterations is guaranteed to be positive
        player.move(speed);
        memory.game.frame +%= 1;
    }

    // Generate chunks around the SimBuffer in the background.
    world.SimBuffer.background_generation_tick(
        memory.game.get_player_coord(),
        memory.game.player_velocity,
        2,
        4,
    );
}

pub export fn mix_seed(number: u64) i64 {
    // IMPORTANT! For some reason, it appears that this returns an `i64` even with `u64` return type.
    // Therefore, that's the type we return.
    return @intCast(seeding.mix_base_seed(&memory.game.seed, number)[0] >> 1);
}
pub export fn mix_seed_f64(number: u64) f64 { // same thing as mix_seed but f64
    return @as(f64, @floatFromInt(seeding.mix_base_seed(&memory.game.seed, number)[0] >> 1)) / seeding.POW_2_64;
}

pub export fn wasm_seed_from_string() void {
    seeding.wasm_seed_from_string(memory.scratch_buffer.ptr, memory.mem.scratch_len, &memory.game.seed);
}

// Layout logic
pub export fn get_memory_layout_ptr() u64 { // pointer like *const memory.MemoryLayout, Memory64 hack
    return @intFromPtr(memory.get_memory_layout_ptr());
}
pub export fn scratch_alloc(len: usize) u64 { // pointer like [*]u8, Memory64 hack
    return @intFromPtr(memory.scratch_alloc(len));
}
pub export fn wasm_alloc(len: usize) u64 { // pointer like [*]u8, Memory64 hack
    return @intFromPtr(memory.wasm_alloc(len));
}
pub export fn wasm_free(ptr: u64, len: usize) void {
    memory.wasm_free(@ptrFromInt(@as(usize, @intCast(ptr))), len); // Memory64 hack
}

// Debug/testing logic
pub const in_debug_mode = builtin.mode == .Debug;

pub export fn debug_build_ui_metadata() void {
    if (in_debug_mode) debug_ui.build_metadata();
}
pub export fn debug_ui_slider_change(id: u32, val: f32) void {
    if (in_debug_mode) debug_ui.slider_change(id, val);
}
pub export fn debug_ui_button_click(id: u32) void {
    if (in_debug_mode) debug_ui.button_click(id);
}

/// Returns if code is in debugging mode for JS to see.
pub export fn isDebug() bool {
    return in_debug_mode;
}

// Import debugging API if optimization level is Debug.
comptime {
    _ = if (in_debug_mode) struct {
        pub export fn test_logs() void {
            logger.test_logs(true);
        }

        pub export fn test_scratch_allocation() void {
            memory.run_scratch_allocation_tests();
        }
    };
}

/// Custom panic function. Note that you can press the arrow for any warnings/errors to see more detailed information (so you might be able to see details such as $debug.FullPanic((function 'panic')).integerOverflow)
fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    const addr = ret_addr orelse 0;
    logger.err(@src(), "PANIC [addr: 0x{x}]: {s}", .{ addr, msg });
    @trap();
}

// Runs tests from other files. I have to remember to add more as necessary when new files with tests appear...
test "main_tests" {
    const modules = .{
        @import("png/png_to_binary.zig"),
        @import("color_rgba.zig"),
        @import("seeding.zig"),
        @import("logger.zig"),
    };

    inline for (modules) |mod| {
        std.testing.refAllDecls(mod);
    }
}
