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

/// Current selected block's HP. Do NOT rely on for logic (as it's not guaranteed to be correct), only visuals.
/// Should be from 0-15 normally, and 255 if block is empty.
pub var selected_hp: u8 = 1;

/// Updates mining and placing blocks. Should be called from `tick()` inside zig/root.zig.
pub fn handle_mining_and_placing() void {
    if (mouse.block_position_changed) {
        mouse.block_position_changed = false;
        mining_progress = 0;
    }
    if (!mouse.is_mouse_down) {
        // mouse must be down for mining actions to occur
        selected_hp = 255;
        return;
    }

    const sprite_type = root.inventory.selected_sprite;
    if (sprite_type == .unselected) {
        selected_hp = 255;
        return;
    }
    if (mouse.mouse_chunk) |mouse_chunk| {
        const block = world.get_chunk(mouse_chunk).get_block(mouse.mouse_block_x, mouse.mouse_block_y);

        // Don't mine the block of the same type you're trying to place1
        if (sprite_type != .none and block.id == sprite_type) {
            selected_hp = 0;
            mining_progress = 0;
            return;
        }

        // Are we breaking something, or placing into empty air?
        if (sprite_type == .none or block.id != .none) {
            // mining or replacing case
            mining_progress += mining_speed;
            const strength = get_sprite_strength(block.id);

            if (strength != std.math.maxInt(u64) and mining_progress >= strength) {
                mining_progress = 0;
                const was_deleted = world.modify_block_hp(
                    mouse_chunk,
                    mouse.mouse_block_x,
                    mouse.mouse_block_y,
                    block,
                    if (strength > 0) mining_strength else 0,
                );

                if (was_deleted) {
                    root.inventory.add_to_inventory(block.id);

                    // Only auto-replace if the block being mined is NOT the same as the held item
                    // AND we successfully consume the item.
                    if (sprite_type != .none and sprite_type != .unselected) {
                        if (root.inventory.remove_from_inventory(sprite_type)) {
                            world.modify_block_type(mouse_chunk, mouse.mouse_block_x, mouse.mouse_block_y, sprite_type);

                            // IMPORTANT: Reset progress and set selected_hp so the next tick
                            // correctly identifies the new block ID and hits the early-exit return.
                            mining_progress = 0;
                            selected_hp = 0;
                            return;
                        }
                    }
                    selected_hp = 255;
                } else {
                    selected_hp = block.hp -| mining_strength;
                }
            }
        } else if (block.id == .none and sprite_type != .none) {
            // placing into empty air!
            if (root.inventory.remove_from_inventory(sprite_type)) {
                world.modify_block_type(mouse_chunk, mouse.mouse_block_x, mouse.mouse_block_y, sprite_type);
                selected_hp = 0;
                mining_progress = 0;
            }
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
