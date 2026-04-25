//! Handles mining and placing blocks.
const std = @import("std");
const root = @import("root").root;
const sprite = root.sprite;
const Sprite = sprite.Sprite;
const world = root.world;
const mouse = root.mouse;

/// How far the player has progressed to increase `hp`.
pub var mining_progress: u64 = 0;

/// How much the player increases `mining_progress` every tick.
pub var mining_speed: u64 = 10;

/// How much `hp` the tool takes off the block every time `mining_progress` reaches the block's strength.
pub var mining_strength: u4 = 1;

/// Current selected block's HP. Do NOT rely on for logic, only visuals.
/// Should be from 0-15 normally, and 255 if block is empty.
pub var selected_hp: u8 = 1;

/// Updates mining or placing blocks. Should be called from `tick()` in zig/root.zig.
pub fn handle_mining() void {
    if (mouse.block_position_changed) {
        mouse.block_position_changed = false;
        mining_progress = 0;
    }
    if (!mouse.is_mouse_down) {
        // mouse must be down for mining actions to occur
        selected_hp = 255;
        return;
    }

    const sprite_type = mouse.selected_sprite;
    if (mouse.mouse_chunk) |mouse_chunk| {
        const block = world.get_chunk(mouse_chunk).get_block(mouse.mouse_block_x, mouse.mouse_block_y);
        if (sprite_type == .none or (block.id != .none and block.id != sprite_type)) { // mining, possibly to clear out old non-empty block?
            mining_progress += mining_speed;
            const strength = get_sprite_strength(block.id);
            if (strength != std.math.maxInt(u64) and mining_progress >= strength) {
                // Reset mining progress; this intentionally doesn't carry over to the next hp mine.
                mining_progress = 0;
                const was_deleted = world.modify_block_hp(
                    mouse_chunk,
                    mouse.mouse_block_x,
                    mouse.mouse_block_y,
                    block,
                    // if no strength, set to 0 to instantly mine
                    if (strength > 0) mining_strength else 0,
                );
                if (was_deleted) root.inventory.add_to_inventory(block.id);

                // block is not modified so we actually have to recalculate
                selected_hp = if (strength > 0) block.hp -| mining_strength else 255;

                if (was_deleted and sprite_type != .none) { // place in the same frame
                    world.modify_block_type(
                        mouse_chunk,
                        mouse.mouse_block_x,
                        mouse.mouse_block_y,
                        sprite_type,
                    );
                    selected_hp = 0;
                }
            }
        } else { // placing?
            world.modify_block_type(
                mouse_chunk,
                mouse.mouse_block_x,
                mouse.mouse_block_y,
                sprite_type,
            );
            selected_hp = 0;
        }
    } else {
        selected_hp = 255;
    }
}

/// Returns how "strong" a `Sprite` is; how much mining_progress must be contributed to increase `hp` of a block.
fn get_sprite_strength(s: Sprite) u64 {
    if (!s.is_solid()) {
        return 0;
    } else if (s.is_stone()) {
        return 15;
    } else if (s.is_ore()) {
        return switch (s) {
            .copper => 30,
            .iron => 35,
            .silver => 45,
            .gold => 60,
            else => 80,
        };
    } else if (s.is_gem()) {
        return switch (s) {
            .amethyst => 75,
            .sapphire => 85,
            .emerald => 95,
            .ruby => 100,
            else => 100,
        };
    }
    return std.math.maxInt(u64);
}
