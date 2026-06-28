//! Contains logic to handle tick updates.
const dw = @import("../root.zig");
const inventory = dw.inventory;
const memory = dw.memory;
const KeyBits = dw.KeyBits;

/// Sets if the Z key should increase the depth recursively until D=32 is reached.
var debug_recursively_increase_depth = false;

pub fn handleTick(logic_speed: f64, iterations: u32) void {
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
    if (debug_recursively_increase_depth and memory.game.depth < dw.HORIZON_DEPTH) {
        dw.world.pushLayer(
            .none,
            memory.game.getPlayerCoord(),
            memory.game.getBlockXInChunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.getBlockYInChunk(),
        );
        if (memory.game.depth == dw.HORIZON_DEPTH) {
            dw.logger.quick(.{ "{h}Position", memory.game.getPlayerCoord().asDepthCoordinate(memory.game.depth) });
            debug_recursively_increase_depth = false;
        }
    }

    // of course, we must TODO: also make this switch when we implement portal logic
    const just_increased_depth = dw.is_debug and KeyBits.isSet(KeyBits.zoom, memory.game.keys_pressed_mask);
    // increase the depth (testing hotkey)
    if (just_increased_depth) {
        dw.world.pushLayer(
            .none,
            memory.game.getPlayerCoord(),
            memory.game.getBlockXInChunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.getBlockYInChunk(),
        );
        // debug_recursively_increase_depth = true;
        if (memory.game.depth > dw.HORIZON_DEPTH and
            memory.game.depth < dw.HORIZON_DEPTH * 2 + dw.startup.STARTING_ZOOM_TIMES)
        {
            var key = memory.game.getPlayerCoord().asDepthCoordinate(memory.game.depth);
            const target_depth = memory.game.depth - dw.HORIZON_DEPTH;
            while (key.depth > target_depth) {
                key = key.getParent();
            }
            dw.logger.quick(.{ "{h}Resulting key/current depth", memory.game.depth, key });
        }

        dw.mining.selected_hp = 255;
        dw.mouse.mouse_chunk_coord = null;
    }

    // Iterations may be > 1 if FPS is low.
    for (0..iterations) |_| {
        // Smelting only advances while the furnace menu is open (paused otherwise).
        if (dw.indicators.menus.furnace) @import("../menus/furnace.zig").updateSmelting();
        if (!just_increased_depth) dw.mining.handleMiningAndPlacing(logic_speed); // mouse block and mining/placing logic all updated in this function
        dw.player.move(logic_speed); // logic that moves the player/camera based on keys
        dw.water.tickWater(); // fluid sim
        memory.game.frame +%= 1;
    }

    // Process item animation ticks and inventory collection!
    inventory.tickDroppedItems();

    // Generate chunks around the SimBuffer in the background.
    dw.world.SimBuffer.precacheChunks(
        memory.game.getPlayerCoord(),
        memory.game.player_velocity,
        2,
        4,
    );
}
