//! Root file. Imports startup.zig and handles exporting functions to WASM.
//! All functions here (excluding internal ones like panic) should be `pub` to expose functions to `generate_types.zig`,
//! and `extern` for WASM (with no other exported functions within other Zig files).
const std = @import("std");
const builtin = @import("builtin");

/// Whether to force `is_debug` to true regardless of build mode.
/// Goes without saying: these should be false in prod.
pub const FORCE_DEBUG = true;

/// Set to true if the CPU architecture is set to `wasm32` or `wasm64`.
pub const is_wasm = builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64;
/// Set to true if either test mode or `Debug` mode is used.
pub const is_debug = FORCE_DEBUG or builtin.is_test or builtin.mode == .Debug;

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
pub const Fifo = @import("internal/fifo.zig").UnboundedFifo;
pub const ColorRgba = @import("visual/color_rgba.zig").ColorRgba;

pub const render = @import("render/render.zig");
pub const sound = @import("render/sound.zig");
pub const chunks = @import("render/chunk.zig");
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
pub const water = @import("state/water.zig");

pub const logger = @import("tools/logger.zig");

pub const inventory = @import("input/inventory.zig");
pub const mining = @import("input/mining.zig");
pub const mouse = @import("input/mouse.zig");

pub fn main() callconv(.c) void {
    // TODO destroy World/GameState values as needed if !alreadyStarted
    world.flag_worklist = std.ArrayList(world.UpdateItem).initCapacity(world.alloc, 1024) catch unreachable;
    world.mod_store = .init(world.alloc);
}

comptime {
    if (is_wasm) {
        @export(&main, .{
            .name = "main",
            .linkage = .strong,
        });
    }
}

pub export fn init() void {
    startup.init();
}
pub export fn prepareVisibleData(time_interpolated: f64, time_diff: f64, canvas_w: f64, canvas_h: f64) void {
    render.prepareVisibleData(time_interpolated, time_diff, canvas_w, canvas_h);
}

pub export fn getTilesPerRow() u32 {
    return 8; // Sprites are saved as a .png in a sprite sheet 128 pixels wide, and each individual sprite is 16x16.
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
    return sprite.MASK_START;
}
pub export fn getGearStart() u32 {
    return @intCast(@intFromEnum(Sprite.gear));
}
pub export fn getWaterStart() u32 {
    return @intCast(@intFromEnum(Sprite.water));
}

pub export fn handleMouse(mouse_x: f64, mouse_y: f64, action: u32) void {
    mouse.handleMouse(mouse_x, mouse_y, action);
}

/// Sets if the Z key should increase the depth recursively until D=32 is reached.
var debug_recursively_increase_depth = false;

pub export fn tick(logic_speed: f64, iterations: u32) void {
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
            const INVENTORY_WIDTH = inventory.INVENTORY_WIDTH;
            const slot_len = active_slots.len;
            const current_column = inventory.getSelectedIndex() % INVENTORY_WIDTH;
            inventory.selected_row = @min(
                @as(u16, @intCast(slot_len / INVENTORY_WIDTH)), // zeroth row holds 10 slots, so this works out
                inventory.selected_row,
            );
            // get index of selected sprite by checking already selected sprite type
            var selected_id = inventory.selected_row * INVENTORY_WIDTH +
                if (selected_column == 65535) current_column else selected_column;

            // Only allow this selection if the slot actually exists
            if (selected_id >= slot_len) {
                if (selected_id >= INVENTORY_WIDTH) {
                    selected_id -= INVENTORY_WIDTH;
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

    // of course, we must TODO: also make this switch when we implement portal logic
    const just_increased_depth = is_debug and KeyBits.isSet(KeyBits.zoom, memory.game.keys_pressed_mask);
    // increase the depth (testing hotkey)
    if (just_increased_depth) {
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
            const target_depth = memory.game.depth - memory.HORIZON_DEPTH;
            while (key.depth > target_depth) {
                key = key.getParent();
            }
            logger.quick(.{ "{h}Resulting key/current depth", memory.game.depth, key });
        }

        mining.selected_hp = 255;
        mouse.mouse_chunk_coord = null;
    }

    for (0..iterations) |_| { // iterations is guaranteed to be positive
        if (!just_increased_depth) mining.handleMiningAndPlacing(logic_speed); // mouse block and mining/placing logic all updated in this function
        player.move(logic_speed); // logic that moves the player/camera based on keys
        water.tickWater(); // fluid sim
        memory.game.frame +%= 1;
    }

    // Process item animation ticks and inventory collection!
    inventory.tickDroppedItems();

    // Generate chunks around the SimBuffer in the background.
    world.SimBuffer.precacheChunks(
        memory.game.getPlayerCoord(),
        memory.game.player_velocity,
        2,
        4,
    );

    // give some helpful info!
    // this gets cleared every frame since writeOnce() is used

    logger.writeOnce(3, .{
        "{mh}Selected sprite ID",
        inventory.selected_sprite,
        "{mh}Hovered sprite details",
        if (mouse.mouse_chunk_coord) |coord| world.getChunk(coord).getBlock(mouse.mouse_block_x, mouse.mouse_block_y) else null,
    });
}

pub export fn mixSeed(number: u64) i64 {
    // IMPORTANT! For some reason, it appears that this returns an `i64` even with `u64` return type.
    // Therefore, that's the type we return.
    return @intCast(seeding.mixBaseSeed(memory.game.seed, number).value[0] >> 1);
}
pub export fn mixSeedF64(number: u64) f64 { // same thing as mix_seed but f64
    return @as(f64, @floatFromInt(
        seeding.mixBaseSeed(memory.game.seed, number).value[0] >> 1,
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

/// Returns if code is in debugging mode for JS to see.
pub export fn isDebug() bool {
    return is_debug;
}

// Import debugging API and functions if optimization level is Debug.
comptime {
    _ = if (is_debug) struct {
        pub const debug_ui = @import("tools/debug_ui.zig");
        pub export fn debugBuildUiMetadata() void {
            if (is_debug) debug_ui.buildMetadata();
        }
        pub export fn changeDebugUiSlider(id: u32, val: f32) void {
            if (is_debug) debug_ui.changeSlider(id, val);
        }
        pub export fn clickDebugUiButton(id: u32) void {
            if (is_debug) debug_ui.clickButton(id);
        }

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

fn customPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    @branchHint(.cold);
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
