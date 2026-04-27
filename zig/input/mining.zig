//! Handles mining and placing blocks.
const std = @import("std");
const root = @import("root").root;
const sprite = root.sprite;
const Sprite = sprite.Sprite;
const inventory = root.inventory;
const world = root.world;
const mouse = root.mouse;

/// Whether to instantly mine blocks or not (effectively infinite strength and speed).
const INSTANT_MINE = false;

/// How far the player has progressed to increase `hp`.
pub var mining_progress: u64 = 0;

/// How much the player increases `mining_progress` every tick.
pub var mining_speed: u64 = 10;

/// How much `hp` the tool takes off the block every time `mining_progress` reaches the block's strength.
pub var mining_strength: u4 = 1;

/// Current selected block's HP. Should be from 0-15 normally, and 255 if block is empty.
pub var selected_hp: u8 = 1;

/// Updates mining and placing blocks. Should be called from `tick()` inside zig/root.zig.
pub fn handle_mining_and_placing() void {
    if (mouse.just_mouse_down and inventory.get_hovered_inventory_sprite() != null) {
        mouse.mouse_state = .inventory; // prevent mouse block placement issue, TODO figure out if something more robust works too
    }

    mouse.update_mouse_block(); // update to get correct mouse position data

    if (mouse.block_position_changed) {
        mouse.block_position_changed = false;
        mining_progress = 0;
    }
    if (mouse.mouse_state != .canvas) {
        // mouse must be down for mining actions to occur
        selected_hp = 255;
        return;
    }

    const sprite_type = inventory.selected_sprite;
    if (sprite_type == .unselected) {
        selected_hp = 255;
        return;
    }
    if (mouse.mouse_chunk) |mouse_chunk| {
        const block = world.get_chunk(mouse_chunk).get_block(mouse.mouse_block_x, mouse.mouse_block_y);

        // Don't mine a block of the same type you're trying to place!
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

            if (INSTANT_MINE or (strength != std.math.maxInt(u64) and mining_progress >= strength)) {
                mining_progress = 0;
                // sprite type being none check also prevents unneeded memory waste with ModKey
                const was_deleted = block.id == .none or world.modify_block_hp(
                    mouse_chunk,
                    mouse.mouse_block_x,
                    mouse.mouse_block_y,
                    block,
                    if (!INSTANT_MINE and strength > 0) mining_strength else 0, // instantly mine (0 value) if block type has no strength
                );

                if (was_deleted) {
                    if (block.id != .none) {
                        inventory.add_to_inventory(block.id);

                        // Only auto-replace if the block being mined is different from the held item.
                        if (sprite_type != .none and sprite_type != .unselected) {
                            if (inventory.remove_from_inventory(sprite_type)) { // make sure it's possible to use
                                if (world.modify_block_type(
                                    mouse_chunk,
                                    mouse.mouse_block_x,
                                    mouse.mouse_block_y,
                                    sprite_type,
                                )) {
                                    // If TRUE, then the block was NOT successfully modified. Revert selection if so.
                                    // This fixes funny issues involving deselection due to invalid placement
                                    inventory.selected_sprite = sprite_type;
                                }

                                mining_progress = 0;
                                selected_hp = 0;
                                return;
                            }
                        }
                    }

                    selected_hp = 255;
                } else {
                    selected_hp = block.hp + mining_strength;
                }
            }
        } else if (block.id == .none and sprite_type != .none) {
            // placing into empty air!
            if (inventory.remove_from_inventory(sprite_type)) {
                if (world.modify_block_type(mouse_chunk, mouse.mouse_block_x, mouse.mouse_block_y, sprite_type)) {
                    // If TRUE, then the block was NOT successfully modified. Revert selection if so.
                    // This fixes funny issues involving deselection due to invalid placement
                    inventory.selected_sprite = sprite_type;
                }
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
    } else if (root.is_debug) return std.math.maxInt(u64) else unreachable;
}

comptime {
    for (@typeInfo(Sprite).@"enum".fields) |field| {
        const field_sprite: Sprite = @enumFromInt(field.value);

        // If it's a valid, solid block, it MUST have a defined mining strength.
        if (field_sprite.is_valid() and field_sprite.is_solid()) {
            if (get_sprite_strength(field_sprite) == std.math.maxInt(u64)) {
                @compileError("Sprite is valid and solid but missing a strength value in get_sprite_strength: " ++ field.name);
            }
        }
    }
}
