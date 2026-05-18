//! Root file. Imports startup.zig and handles exporting functions to WASM.
//! All functions here (excluding internal ones like panic) should be `pub` to expose functions to `generate_types.zig`,
//! and `extern` for WASM (with no other exported functions within other Zig files).
const std = @import("std");
const builtin = @import("builtin");

pub const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;
pub const is_debug = builtin.is_test or builtin.mode == .Debug;

pub const memory = @import("memory.zig");
pub const startup = @import("startup.zig");

// The width of the screen for the internal viewport. Normalized to 0-1 before being used in WebGPU.
pub const SCREEN_WIDTH = 480;
// The height of the screen for the internal viewport. Normalized to 0-1 before being used in WebGPU.
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
pub const ancestor = @import("state/ancestor.zig");

pub const logger = @import("tools/logger.zig");
pub const debug_ui = @import("tools/debug_ui.zig");

pub const inventory = @import("input/inventory.zig");
pub const mining = @import("input/mining.zig");
pub const mouse = @import("input/mouse.zig");

pub export fn setup() void {
    // TODO destroy World/GameState values as needed if !alreadyStarted
    memory.game = .{}; // initialize GameState
    world.mod_store = world.ModificationStore.init(world.alloc);
}
pub export fn init() void {
    startup.init();
}
pub export fn prepareVisibleData(time_interpolated: f64, time_diff: f64, canvas_w: f64, canvas_h: f64) void {
    render.prepareVisibleData(time_interpolated, time_diff, canvas_w, canvas_h);
}

pub export fn getTilesPerRow() u32 {
    return 8; // Sprites are saved as a .png in a sprite sheet 128 pixels wide, and each asset is 16x16.
}
pub export fn getTilesPerColumn() u32 {
    return sprite.max_sprite_value / 8 + 1; // works out from 0-indexing
}
pub export fn getStoneStart() u32 {
    return @intCast(@intFromEnum(Sprite.stone));
}
pub export fn getOreStart() u32 {
    return @intCast(@intFromEnum(Sprite.copper));
}
pub export fn getGemStart() u32 {
    return @intCast(@intFromEnum(Sprite.amethyst));
}
pub export fn getGemMaskStart() u32 {
    return @intCast(@intFromEnum(Sprite.gem_mask));
}
pub export fn getDecorStart() u32 {
    return @intCast(@intFromEnum(Sprite.spiral_plant));
}

pub export fn handleMouse(mouse_x: f64, mouse_y: f64, action: u32) void {
    mouse.handleMouse(mouse_x, mouse_y, action);
}

/// Sets if the Z key should increase the depth recursively until D=32 is reached.
var debug_recursively_increase_depth = false;

pub export fn tick(speed: f64, iterations: u32) void {
    var buffer: inventory.SlotBuffer = undefined;
    const active_slots = inventory.getSpritesInInventory(&buffer);

    // handles M and 0 cases, see code in function for details
    if (KeyBits.isSet(KeyBits.inventory_up, memory.game.keys_pressed_mask)) inventory.selected_row -|= 1;
    if (KeyBits.isSet(KeyBits.inventory_down, memory.game.keys_pressed_mask)) inventory.selected_row += 1;
    if (KeyBits.isSet(KeyBits.mine, memory.game.keys_pressed_mask)) {
        inventory.selected_row = 0;
        inventory.selected_sprite = .none;
    } else {
        const selected_column = KeyBits.getNumber(memory.game.keys_held_mask);
        if (!(inventory.selected_sprite == .unselected and selected_column == 65535)) {
            const slot_len = active_slots.len;
            const current_column = inventory.getSelectedIndex() % 10;
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

    // in prod, add is_debug here!
    if (debug_recursively_increase_depth and memory.game.depth < memory.HORIZON_DEPTH) {
        world.pushLayer(
            Sprite.none,
            memory.game.getPlayerCoord(),
            memory.game.getBlockXInChunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.getBlockYInChunk(),
        );
        if (memory.game.depth == memory.HORIZON_DEPTH) {
            logger.quick(.{ "{h}Position", memory.game.getPlayerCoord().asDepthCoordinate(memory.game.depth) });
            debug_recursively_increase_depth = false;
        }
    }

    // increase the depth (testing hotkey)
    if (is_debug and KeyBits.isSet(KeyBits.zoom, memory.game.keys_pressed_mask)) {
        world.pushLayer(
            Sprite.none,
            memory.game.getPlayerCoord(),
            memory.game.getBlockXInChunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.getBlockYInChunk(),
        );
        // debug_recursively_increase_depth = true;
        if (memory.game.depth > memory.HORIZON_DEPTH and
            memory.game.depth < memory.HORIZON_DEPTH * 2 + startup.STARTING_ZOOM_TIMES)
        {
            var key = memory.game.getPlayerCoord().asDepthCoordinate(memory.game.depth);
            while (key.depth > memory.HORIZON_DEPTH) {
                key = key.getParent();
            }
            logger.quick(.{ "{h}Resulting key/current depth", memory.game.depth, key });
        }

        mining.selected_hp = 255;
        mouse.mouse_chunk = null;
    } else {
        // mouse block and mining/placing logic all updated in this function
        mining.handleMiningAndPlacing();
    }

    for (0..iterations) |_| { // iterations is guaranteed to be positive
        player.move(speed);
        memory.game.frame +%= 1;
    }

    // Generate chunks around the SimBuffer in the background.
    world.SimBuffer.precacheChunks(
        memory.game.getPlayerCoord(),
        memory.game.player_velocity,
        2,
        4,
    );

    // give some helpful info! logging is a bit hacky
    // we use a {h} header but can write multiple lines, this gets cleared every frame since writeOnce() is used
    logger.writeOnce(3, .{
        \\{h}Left-clicking places blocks; click on inventory slots directly to select block types.
        \\Use the pickaxe icon to mine and WASD/arrow keys to move around.
        \\
        \\For inventory hotkeys:
        \\- Use backquote and 0-9 keys to change inventory selection.
        \\- Q moves up a row in the inventory while E moves down a row.
        \\
        \\Selected sprite ID
        ,
        inventory.selected_sprite,
    });
}

pub export fn mixSeed(number: u64) i64 {
    // IMPORTANT! For some reason, it appears that this returns an `i64` even with `u64` return type.
    // Therefore, that's the type we return.
    return @intCast(seeding.mixBaseSeed(&memory.game.seed, number)[0] >> 1);
}
pub export fn mixSeedF64(number: u64) f64 { // same thing as mix_seed but f64
    return @as(f64, @floatFromInt(
        seeding.mixBaseSeed(&memory.game.seed, number)[0] >> 1,
    )) / seeding.POW_2_64;
}

pub export fn wasmSeedFromString() void {
    seeding.wasmSeedFromString(
        memory.scratch_buffer.ptr,
        memory.mem.scratch_len,
        &memory.game.seed,
    );
}

// Layout logic
pub export fn getMemoryLayoutPtr() u64 { // pointer-like *const memory.MemoryLayout, Memory64 hack
    return @intFromPtr(memory.getMemoryLayoutPtr());
}
pub export fn scratchAlloc(len: usize) u64 { // pointer-like [*]u8, Memory64 hack
    return @intFromPtr(memory.scratchAlloc(len));
}
pub export fn wasmAlloc(len: usize) u64 { // pointer-like [*]u8, Memory64 hack
    return @intFromPtr(memory.wasmAlloc(len));
}
pub export fn wasmFree(ptr: u64, len: usize) void {
    memory.wasmFree(@ptrFromInt(@as(usize, @intCast(ptr))), len); // Memory64 hack
}

pub export fn debugBuildUiMetadata() void {
    if (is_debug) debug_ui.buildMetadata();
}
pub export fn changeDebugUiSlider(id: u32, val: f32) void {
    if (is_debug) debug_ui.changeSlider(id, val);
}
pub export fn clickDebugUiButton(id: u32) void {
    if (is_debug) debug_ui.clickButton(id);
}

/// Returns if code is in debugging mode for JS to see.
pub export fn isDebug() bool {
    return is_debug;
}

// Import debugging API if optimization level is Debug.
comptime {
    _ = if (is_debug) struct {
        pub export fn testLogs() void {
            logger.testLogs(true);
        }

        pub export fn testScratchAlloc() void {
            memory.runScratchAllocTests();
        }

        pub export fn logInventory() void {
            inventory.logInventory();
        }

        pub export fn testPanic() void {
            logger.log(@src(), "A call to @panic() will be dispatched. This should trap or abort the program.", .{});
            @panic("Panic test!");
        }

        // pub export fn getParent(x: u64, y: u64, quadrant: u32, depth: u32) void {
        //     if (depth < startup.STARTING_ZOOM_TIMES)
        //         logger.quick("Depth is too small! ):")
        //     else if (depth > memory.game.depth)
        //         logger.quick("Depth is higher than current game depth!")
        //     else {
        //         var key = world.DepthCoordinate{
        //             .quadrant = quadrant,
        //             .suffix = .{ x, y },
        //             .depth = memory.game.depth,
        //         };
        //         while (key.depth > depth) {
        //             key = key.getParent();
        //         }
        //         logger.quick(.{ "{h}Resulting key", key });
        //     }
        // }

        // pub export fn getPlayerPosAtDepth(depth: u32) void {
        //     logger.quick(.{ "{h}Current depth", memory.game.depth });
        //     if (depth == 0) {
        //         logger.quick(.{ "{h}Current coord", memory.game.getPlayerCoord() });
        //         return;
        //     }
        //     var key = memory.game.getPlayerCoord().asDepthCoordinate(depth);
        //     while (key.depth > depth) {
        //         key = key.getParent();
        //     }
        //     logger.quick(.{ "{h}Resulting key", key });
        // }
    };
}

/// Custom override panic function that calls `logger.err()` and either traps or aborts the process.
pub const panic = std.debug.FullPanic(customPanic);

pub fn customPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (ret_addr) |addr| {
        logger.err(@src(), "PANIC [addr: 0x{x}]: {s}", .{ addr, msg });
    } else logger.err(@src(), "PANIC: {s}", .{msg});
    if (is_wasm) @trap() else std.process.abort();
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
