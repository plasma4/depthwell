//! Root file. Imports startup.zig and handles exporting functions to WASM.
//! All functions here (excluding internal ones like panic) should be `pub` to expose functions to `generate_types.zig`,
//! and `extern` for WASM (with no other exported functions within other Zig files).
const std = @import("std");
const builtin = @import("builtin");

/// Points to definitions from zig/root.zig.
pub const root = @This();

pub const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;
pub const is_debug = builtin.is_test or builtin.mode == .Debug;

pub const memory = @import("memory.zig");
pub const startup = @import("startup.zig");

// The width of the screen for the internal viewport. Normalized to 0-1 before being used in WGSL.
pub const SCREEN_WIDTH = 480;
// The height of the screen for the internal viewport. Normalized to 0-1 before being used in WGSL.
pub const SCREEN_HEIGHT = 270;
// Half the internal viewport width.
pub const SCREEN_WIDTH_HALF = SCREEN_WIDTH / 2;
// Half the internal viewport height.
pub const SCREEN_HEIGHT_HALF = SCREEN_HEIGHT / 2;

pub const utils = @import("internal/utils.zig");
pub const GenerateOffsets = @import("internal/offsets.zig").GenerateOffsets;
pub const SegmentedList = @import("internal/SegmentedList.zig").SegmentedList;
pub const ColorRGBA = @import("visual/color_rgba.zig").ColorRGBA;

pub const render = @import("render/render.zig");
pub const chunks = @import("render/chunk.zig");
pub const particle = @import("render/particle.zig");
pub const entity = @import("render/entity.zig");

pub const types = @import("types/types.zig");
pub const KeyBits = types.KeyBits;
pub const geometry = @import("types/geometry.zig");

pub const sprite = @import("types/sprite.zig");
pub const Sprite = sprite.Sprite;

pub const seeding = @import("state/seeding.zig");
pub const procedural = @import("state/procedural.zig");
pub const player = @import("state/player.zig");
pub const world = @import("state/world.zig");

pub const logger = @import("tools/logger.zig");
pub const debug_ui = @import("tools/debug_ui.zig");

pub const inventory = @import("input/inventory.zig");
pub const mining = @import("input/mining.zig");
pub const mouse = @import("input/mouse.zig");

pub export fn setup() void {
    // TODO destroy World/GameState values as needed if !alreadyStarted
    memory.game = .{}; // initialize GameState
    world.mod_store = world.ModificationStore.init(world.alloc, 64);
    world.quad_cache = .{
        .path_hashes = undefined,
        .hash_cache_1 = undefined,
        .left_path = SegmentedList(u64, 1024){}, // easiest to do prealloc with larger stack size in case
        .top_path = SegmentedList(u64, 1024){},
        .ancestor_materials = .{.none} ** 4,
    };

    logger.write(3,
        \\Left-clicking places blocks; click on inventory slots directly to select block types.
        \\Use the pickaxe icon to mine and WASD/arrow keys to move around.
        \\
        \\For inventory hotkeys:
        \\- Use backquote and 0-9 keys to change inventory selection.
        \\- Q moves up a row in the inventory while E moves down a row.
    );
}
pub export fn init() void {
    startup.init();
}
pub export fn prepare_visible_data(time_interpolated: f64, time_diff: f64, canvas_w: f64, canvas_h: f64) void {
    render.prepare_visible_data(time_interpolated, time_diff, canvas_w, canvas_h);
}

pub export fn get_tiles_per_row() u32 {
    return 8; // Sprites are saved as a .png in a sprite sheet 128 pixels wide, and each asset is 16x16.
}
pub export fn get_tiles_per_column() u32 {
    return sprite.max_sprite_value / 8 + 1; // works out from 0-indexing
}
pub export fn get_stone_start() u32 {
    return @intCast(@intFromEnum(Sprite.stone));
}
pub export fn get_ore_start() u32 {
    return @intCast(@intFromEnum(Sprite.copper));
}
pub export fn get_gem_start() u32 {
    return @intCast(@intFromEnum(Sprite.amethyst));
}
pub export fn get_gem_mask_start() u32 {
    return @intCast(@intFromEnum(Sprite.gem_mask));
}
pub export fn get_decor_start() u32 {
    return @intCast(@intFromEnum(Sprite.spiral_plant));
}

pub export fn handle_mouse(mouse_x: f64, mouse_y: f64, action: u32) void {
    mouse.handle_mouse(mouse_x, mouse_y, action);
}

pub export fn tick(speed: f64, iterations: u32) void {
    var buffer: inventory.SlotBuffer = undefined;
    const active_slots = inventory.get_active_slots(&buffer);

    // handles M and 0 cases, see code in function for details
    if (KeyBits.is_set(KeyBits.inventory_up, memory.game.keys_pressed_mask)) inventory.selected_row -|= 1;
    if (KeyBits.is_set(KeyBits.inventory_down, memory.game.keys_pressed_mask)) inventory.selected_row += 1;
    if (KeyBits.is_set(KeyBits.mine, memory.game.keys_pressed_mask)) {
        inventory.selected_row = 0;
        inventory.selected_sprite = .none;
    } else {
        const selected_column = KeyBits.get_number(memory.game.keys_held_mask);
        if (!(inventory.selected_sprite == .unselected and selected_column == 65535)) {
            const slot_len = active_slots.len;
            const current_column = inventory.get_selected_index() % 10;
            inventory.selected_row = @min(
                @as(u16, @intCast(slot_len / 10)), // zeroth row holds 10 slots, so this works out
                inventory.selected_row,
            );
            // get index of selected sprite by checking already selected sprite type
            var selected_id = inventory.selected_row * 10 +
                if (selected_column == 65535) current_column else selected_column;

            // Only allow this selection if the slot actually exists
            if (selected_id >= slot_len) {
                if (selected_id >= 10) {
                    selected_id -= 10;
                    inventory.selected_row -= 1;
                }
            } else {
                inventory.selected_sprite = active_slots[selected_id];
            }
        }
    }

    // increase the depth (testing hotkey)
    if (KeyBits.is_set(KeyBits.zoom, memory.game.keys_pressed_mask)) {
        // if (in_debug_mode) {
        world.push_layer(
            Sprite.none,
            memory.game.get_player_coord(),
            memory.game.get_block_x_in_chunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.get_block_y_in_chunk(),
        );
        // }
        mining.selected_hp = 255;
        mouse.mouse_chunk = null;
    } else {
        // mouse block and mining/placing logic all updated in this function
        mining.handle_mining_and_placing();
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
pub export fn get_memory_layout_ptr() u64 { // pointer-like *const memory.MemoryLayout, Memory64 hack
    return @intFromPtr(memory.get_memory_layout_ptr());
}
pub export fn scratch_alloc(len: usize) u64 { // pointer-like [*]u8, Memory64 hack
    return @intFromPtr(memory.scratch_alloc(len));
}
pub export fn wasm_alloc(len: usize) u64 { // pointer-like [*]u8, Memory64 hack
    return @intFromPtr(memory.wasm_alloc(len));
}
pub export fn wasm_free(ptr: u64, len: usize) void {
    memory.wasm_free(@ptrFromInt(@as(usize, @intCast(ptr))), len); // Memory64 hack
}

pub export fn debug_build_ui_metadata() void {
    if (is_debug) debug_ui.build_metadata();
}
pub export fn debug_ui_slider_change(id: u32, val: f32) void {
    if (is_debug) debug_ui.slider_change(id, val);
}
pub export fn debug_ui_button_click(id: u32) void {
    if (is_debug) debug_ui.button_click(id);
}

/// Returns if code is in debugging mode for JS to see.
pub export fn isDebug() bool {
    return is_debug;
}

// Import debugging API if optimization level is Debug.
comptime {
    _ = if (is_debug) struct {
        pub export fn test_logs() void {
            logger.test_logs(true);
        }

        pub export fn test_scratch_allocation() void {
            memory.run_scratch_allocation_tests();
        }

        pub export fn log_inventory() void {
            inventory.log_inventory();
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
        @import("visual/color_rgba.zig"),
        @import("state/seeding.zig"),
        @import("tools/logger.zig"),
    };

    inline for (modules) |mod| {
        std.testing.refAllDecls(mod);
    }
}
