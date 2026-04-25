//! Handles logic for inventory management.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const mouse = root.mouse;
const sprite = root.sprite;
const Sprite = sprite.Sprite;

const v2f32 = memory.v2f32;
const add_entity = root.entity.add_entity;
const draw_number = root.entity.draw_number;

/// Currently selected inventory slot index (0 to active_count - 1).
pub var selected_id: u8 = 0;
/// Current sprite (index) selected (to place, set to 0 if to mining instead).
pub var selected_sprite: Sprite = .none;

/// Dense storage: index is @intFromEnum(Sprite), value is quantity.
pub var inventory_counts = [_]u32{0} ** (sprite.max_sprite_value + 1);

/// Animation progress for each potential slot.
pub var inventory_animation_t = [_]f32{0.0} ** (sprite.max_sprite_value + 1);

/// Increments the count for a mined block.
pub fn add_to_inventory(id: Sprite) void {
    const idx = @intFromEnum(id);
    if (idx < inventory_counts.len) {
        inventory_counts[idx] += 1;
    }
}

/// Decrements the count for a block. Returns whether successful.
pub fn remove_from_inventory(id: Sprite) bool {
    if (id == .none or id == .unselected) return false;

    const idx = @intFromEnum(id);
    if (idx >= inventory_counts.len or inventory_counts[idx] == 0) return false;

    inventory_counts[idx] -= 1;

    // If we used the last one, unselect it immediately
    if (inventory_counts[idx] == 0 and selected_sprite == id) {
        selected_sprite = .unselected;
    }

    return true;
}

/// Helper to get the list of sprites currently in the
/// Always starts with .none, followed by owned foundation sprites sorted by ID.
pub fn get_active_slots(buffer: *[sprite.foundation_sprite_count + 1]Sprite) []Sprite {
    buffer[0] = .none;
    var count: usize = 1;
    // foundation_sprites is already sorted by enum ID because of how it's generated in sprite.zig
    for (sprite.foundation_sprites) |s| {
        if (s == .none) continue;
        if (inventory_counts[@intFromEnum(s)] > 0) {
            buffer[count] = s;
            count += 1;
        }
    }
    return buffer[0..count];
}

/// Back easing function: provides a slight negative dip before smoothing to the target.
fn ease_back(t: f32) f32 {
    const c1 = 1.70158;
    const c3 = c1 + 1.0;
    return c3 * t * t * t - c1 * t * t; // cubic func
}

/// Draws the inventory slots, wrapping into new rows every 10 items.
pub fn draw_inventory(time_diff: f64) void {
    var slot_buffer: [sprite.foundation_sprite_count + 1]Sprite = undefined;
    const active_slots = get_active_slots(&slot_buffer);

    const animation_step: f32 = 200.0;
    const base_size = 16.0;
    const spacing = 1.25 * base_size;

    for (active_slots, 0..) |active_sprite, i| {
        // For each slot, find the sprite ID, handle animations, and draw sprite and its shadow
        const id = @intFromEnum(active_sprite);
        const is_selected = active_sprite == selected_sprite;

        const target: f32 = if (is_selected) 1.0 else 0.0;
        const animation_speed = @as(f32, @floatCast(time_diff)) / animation_step;

        if (inventory_animation_t[id] < target) {
            inventory_animation_t[id] = @min(target, inventory_animation_t[id] + animation_speed);
        } else if (inventory_animation_t[id] > target) {
            inventory_animation_t[id] = @max(target, inventory_animation_t[id] - animation_speed);
        }

        const t_eased = ease_back(inventory_animation_t[id]);
        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;

        const col = @as(f32, @floatFromInt(i % 10));
        const row = @as(f32, @floatFromInt(i / 10));
        const inventory_pos: v2f32 = .{ 32 + col * spacing, 32 + row * spacing };

        const is_mine_type = active_sprite == .none;

        // Background sizing (using is_selected directly for instant feedback on bg)
        const bg_size: f32 = if (is_selected) base_size * 1.125 else if (is_mine_type) base_size * 0.9 else base_size;
        const bg_pos = inventory_pos - v2f32{ bg_size / 4.0, bg_size / 4.0 };

        // replace with pickaxe for UI
        const rendered_sprite = if (is_mine_type) Sprite.pickaxe else active_sprite;
        add_entity(.{
            .sprite = if (is_selected) .inventory_selected else .inventory,
            .position = bg_pos,
            .size = bg_size,
        });

        const pos = inventory_pos - v2f32{ current_size / 4.0, current_size / 4.0 } - v2f32{ 1.0, 1.0 };
        add_entity(.{ // item shadow
            .sprite = rendered_sprite,
            .position = pos - v2f32{ 1.0, 1.0 },
            .size = current_size,
            .lcha = .{ 0.2, 0.0, 0.0, 0.5 },
        });

        add_entity(.{ // actual item
            .sprite = rendered_sprite,
            .position = pos,
            .size = current_size,
        });
    }

    // Second pass for numbers to ensure they are at the top of inventory rendering
    for (active_slots, 0..) |s, i| {
        if (s == .none) continue;

        const id = @intFromEnum(s);
        const t_eased = ease_back(inventory_animation_t[id]);

        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;
        const size_vec = v2f32{ current_size, current_size };

        const col = @as(f32, @floatFromInt(i % 10));
        const row = @as(f32, @floatFromInt(i / 10));
        const inventory_pos: v2f32 = .{ 32 + col * spacing, 32 + row * spacing };
        const pos = inventory_pos - size_vec / v2f32{ base_size / 4.0, base_size / 4.0 } - v2f32{ base_size / 16.0, base_size / 16.0 };

        const count = inventory_counts[@intFromEnum(s)];
        const color_hue = @as(f32, @floatFromInt(i)) * 0.2;

        draw_number( // shadow
            count,
            pos + v2f32{ base_size / 3.6, base_size / 3.6 },
            .{
                .lcha = .{ 0.5, 0.2, color_hue, 0.8 },
                .font_size = base_size / 3.0,
                .ltr = true,
            },
        );

        draw_number( // actual number
            count,
            pos + v2f32{ base_size / 3.2, base_size / 3.2 },
            .{
                .lcha = .{ 1.0, 0.2, @as(f32, @floatFromInt(i)) * 0.1, 1.0 },
                .font_size = base_size / 3.0,
                .ltr = true,
            },
        );
    }
}
