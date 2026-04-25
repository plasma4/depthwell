//! Handles logic for inventory management.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const sprite = root.sprite;
const Sprite = sprite.Sprite;

const v2f32 = memory.v2f32;
const add_entity = root.entity.add_entity;
const draw_number = root.entity.draw_number;

/// Currently selected inventory slot index (0 to active_count - 1).
pub var selected_id: u8 = 0;

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

/// Helper to get the list of sprites currently in the inventory.
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

/// Draws the 10 inventory slots and the blocks within them.
pub fn draw_inventory(time_diff: f64) void {
    var slot_buffer: [sprite.foundation_sprite_count + 1]Sprite = undefined;
    const active_slots = get_active_slots(&slot_buffer);

    // Clamp selected_id if the inventory changed
    if (selected_id >= active_slots.len) selected_id = @intCast(active_slots.len - 1);

    // Animation progression (in milliseconds).
    const animation_step: f32 = 200.0;
    // base size of inventory slots
    const base_size = 16.0;

    for (active_slots, 0..) |s, i| {
        // Update animation state per slot
        const target: f32 = if (i == selected_id) 1.0 else 0.0;
        const animation_speed = @as(f32, @floatCast(time_diff)) / animation_step;

        if (inventory_animation_t[i] < target) {
            inventory_animation_t[i] = @min(target, inventory_animation_t[i] + animation_speed);
        } else if (inventory_animation_t[i] > target) {
            inventory_animation_t[i] = @max(target, inventory_animation_t[i] - animation_speed);
        }

        // Calculate visual scale using the easing formula
        const t_eased = ease_back(inventory_animation_t[i]);
        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;

        // Interpolate size based on eased t
        const current_size = size_normal + (size_selected - size_normal) * t_eased;
        const size_vec = v2f32{ current_size, current_size };

        // Center item based on size
        const inventory_pos: v2f32 = .{ 32 + 1.25 * base_size * @as(f32, @floatFromInt(i)), 32 };
        const pos = inventory_pos - size_vec / v2f32{ 4.0, 4.0 } - v2f32{ 1.0, 1.0 };

        // Calculate inventory square background position to keep it centered with the item
        const bg_size: f32 = if (i == selected_id) base_size + 2.0 else base_size;
        const bg_pos = inventory_pos - v2f32{ bg_size / 4.0, bg_size / 4.0 };

        add_entity(.{ // draw inventory slot
            .sprite = if (i == selected_id) .inventory_selected else .inventory,
            .position = bg_pos,
            .size = bg_size,
        });

        if (s != .none) {
            // Item shadow
            add_entity(.{
                .sprite = s,
                .position = pos - v2f32{ 1.0, 1.0 },
                .size = current_size,
                .lcha = .{ 0.2, 0.0, 0.0, 0.5 }, // do some filtering with chroma
            });

            // actual item inside
            add_entity(.{
                .sprite = s,
                .position = pos,
                .size = current_size,
            });
        }
    }

    // Second pass: Draw the text (amount) after everything else
    for (active_slots, 0..) |s, i| {
        if (s == .none) continue;

        const t_eased = ease_back(inventory_animation_t[i]);
        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;
        const size_vec = v2f32{ current_size, current_size };

        const inventory_pos: v2f32 = .{ 32 + 1.25 * base_size * @as(f32, @floatFromInt(i)), 32 };
        const pos = inventory_pos - size_vec / v2f32{ 4.0, 4.0 } - v2f32{ 1.0, 1.0 };

        // Draw the AMOUNT (inventory_counts)
        const color_hue = @as(f32, @floatFromInt(i)) * 0.2;
        const count = inventory_counts[@intFromEnum(s)];

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
