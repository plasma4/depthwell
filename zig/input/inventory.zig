//! Handles logic for inventory management.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const logger = root.logger;
const sprite = root.sprite;
const Sprite = sprite.Sprite;
const mouse = root.mouse;

const v2f32 = memory.v2f32;
const add_entity = root.entity.add_entity;
const draw_number = root.entity.draw_number;

/// Debug option, changing whether to show all inventory item slots and items or not.
pub var SHOW_ALL_INVENTORY_ITEMS = false;
/// Determines how wide each row of the inventory is.
const inventory_width = 10;

/// Which row the selected sprite is in.
/// Used for finding which active slot should be used and navigated through Q and E keys.
pub var selected_row: u16 = 0;

/// Slice array tyoe for possible slots.
pub const SlotBuffer = [sprite.valid_sprite_count + 1]Sprite;

/// Current sprite selected to place.
pub var selected_sprite: Sprite = .none;

/// Dense storage: index is `@intFromEnum(Sprite)`, value is the number of that item in the inventory.
pub var inventory_counts = [_]u64{0} ** (sprite.max_sprite_value + 1);

/// Animation progress for each potential slot. Always between 0 (idle) and 1 (fully triggered).
pub var inventory_anim_progress = [_]f32{0.0} ** (sprite.max_sprite_value + 1);

/// Animation progress for the wobble effect of text. Always between -1 and 1; 0 if idle.
pub var inventory_wobble_progress = [_]f32{0.0} ** (sprite.max_sprite_value + 1);

/// Logs data on what is inside the inventory.
pub fn log_inventory() void {
    // .quick and {h} work best here as you don't have to do a bunch of work figuring out formatting
    logger.quick(.{ "{h}Inventory counts", inventory_counts });
    logger.quick(.{ "{h}Selected sprite", selected_sprite });
}

/// Increments the count for a mined block.
pub fn add_to_inventory(id: Sprite) void {
    const idx = @intFromEnum(id);
    if (idx < inventory_counts.len) {
        inventory_counts[idx] += 1;
        if (inventory_wobble_progress[idx] == 0.0) inventory_wobble_progress[idx] = 1.0;
    }
}

/// Decrements the count for a block. Returns whether successful.
pub fn remove_from_inventory(id: Sprite) bool {
    if (id == .none or id == .unselected) return false;

    const idx = @intFromEnum(id);
    if (idx >= inventory_counts.len or inventory_counts[idx] == 0) return false;

    inventory_counts[idx] -= 1;
    if (inventory_wobble_progress[idx] == 0.0) inventory_wobble_progress[idx] = -1.0;

    // If we used the last one, unselect it immediately
    if (inventory_counts[idx] == 0 and selected_sprite == id) {
        selected_sprite = .unselected;
    }

    return true;
}

/// Helper to get the list of sprites currently in the inventory. Creates a temporary buffer in the stack.
/// Always starts with .none, followed by owned foundation sprites sorted by ID.
/// Requires a buffer to prevent dangling pointer (from local array) issues.
pub fn get_active_slots(buffer: *SlotBuffer) []Sprite {
    var count: usize = 1;
    buffer[0] = .none; // slot 0 (pickaxe) must always exist

    // foundation_sprites is already sorted by enum ID because of how it's generated in zig/types/sprite.zig
    inline for (sprite.valid_sprites) |s| {
        if (s == .none) continue;
        if (SHOW_ALL_INVENTORY_ITEMS or inventory_counts[@intFromEnum(s)] > 0) {
            buffer[count] = s;
            count += 1;
            // logger.quick(.{ s, buffer.len, sprite.max_sprite_value });
        }
    }

    return buffer[0..count];
}

/// Gets the index of `selected_sprite` in the active slots.
pub fn get_selected_index() u16 {
    if (selected_sprite == .none or selected_sprite == .unselected) return 0;
    var count: usize = 1;
    // foundation_sprites is already sorted by enum ID because of how it's generated in zig/types/sprite.zig
    inline for (sprite.valid_sprites) |s| {
        if (s == .none) continue;
        if (SHOW_ALL_INVENTORY_ITEMS or inventory_counts[@intFromEnum(s)] > 0) {
            if (s == selected_sprite) return @intCast(count);
            count += 1;
        }
    }

    // This shouldn't be possible, unless something bad happened or `SHOW_ALL_INVENTORY_ITEMS` got toggled!
    selected_sprite = .none;
    selected_row = 0;
    return 0;
}

/// Returns the sprite being hovered if the mouse is within any inventory slot hitbox.
pub fn get_hovered_inventory_sprite() ?Sprite {
    // TODO merge with draw_inventory()?
    var buffer: SlotBuffer = undefined;
    const active_slots = get_active_slots(&buffer);

    const base_size = 16.0;
    const spacing = 1.25 * base_size;
    const mouse_pos = mouse.uv_position * memory.v2f64{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT };

    for (active_slots, 0..) |active_sprite, i| {
        const col = @as(f32, @floatFromInt(i % inventory_width));
        const row = @as(f32, @floatFromInt(i / inventory_width));

        const inventory_pos: v2f32 = .{ 32 + col * spacing, 32 + row * spacing };

        // Match the background sizing logic from the draw_inventory() function
        const is_mine_type = active_sprite == .none;
        const is_selected = active_sprite == selected_sprite;
        const bg_size: f32 = if (is_selected) base_size * 1.125 else if (is_mine_type) base_size * 0.9 else base_size;
        const bg_pos = inventory_pos - v2f32{ bg_size / 4.0, bg_size / 4.0 };

        const hitbox: root.geometry.Shape = .round_square(
            bg_pos - v2f32{ bg_size / 2.0, bg_size / 2.0 },
            bg_size,
            0.2,
        );

        if (hitbox.contains(mouse_pos)) {
            return active_sprite;
        }
    }

    return null;
}

/// Draws the inventory slots, wrapping into new rows every 10 items.
pub fn draw_inventory(time_diff: f64) void {
    var buffer: SlotBuffer = undefined;
    const active_slots = get_active_slots(&buffer);
    // logger.quick(.{ root.mining.selected_hp, inventory_counts });

    const wobble_decay_speed: f32 = 2.0; // controls wobble decay speed
    const wobble_speed: f32 = 10.0; // multiplier of sine of wobble for for values from -1 to 1
    const wobble_size: f32 = 1.0; // how many radians to rotate to the right or left
    const wobble_animation_length: f32 = 800.0; // controls wobble animation ms length
    const size_animation_length: f32 = 200.0; // item/background size animation change ms length
    const base_size = 16.0; // base size of inventory sprites
    const spacing = 1.25 * base_size; // spacing between sprites (must be at least base_size)

    var mouse_hovered_sprite: ?Sprite = null;
    for (active_slots, 0..) |active_sprite, i| {
        // For each slot, find the sprite ID, handle animations, and draw sprite and its shadow
        const id = @intFromEnum(active_sprite);
        const is_selected = active_sprite == selected_sprite;

        const target: f32 = if (is_selected) 1.0 else 0.0;
        const animation_speed = @as(f32, @floatCast(time_diff)) / size_animation_length;

        if (inventory_anim_progress[id] < target) {
            inventory_anim_progress[id] = @min(target, inventory_anim_progress[id] + animation_speed);
        } else if (inventory_anim_progress[id] > target) {
            inventory_anim_progress[id] = @max(target, inventory_anim_progress[id] - animation_speed);
        }

        const t_eased = ease_back(inventory_anim_progress[id]);
        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;

        const col = @as(f32, @floatFromInt(i % inventory_width));
        const row = @as(f32, @floatFromInt(i / inventory_width));

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
            // a little bit of chroma addition and variation here!
            // the shadow is more like the original sprite for stone sprites and much more bland otherwise
            .lcha = .{
                if (rendered_sprite.is_stone()) 0.5 else 0.3,
                0.05, // a side effect of this is that perfectly gray sprites' shadows become more red
                0.0,
                if (rendered_sprite.is_stone()) 0.9 else 0.6,
            },
        });

        add_entity(.{ // actual item
            .sprite = rendered_sprite,
            .position = pos,
            .size = current_size,
        });

        const hitbox: root.geometry.Shape = .round_square(
            bg_pos - v2f32{ bg_size / 2.0, bg_size / 2.0 },
            bg_size,
            0.2,
        );
        if (hitbox.contains(mouse.uv_position * memory.v2f64{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT })) {
            mouse_hovered_sprite = active_sprite;
        }
    }

    if (mouse_hovered_sprite) |s| {
        if (mouse.just_mouse_down) {
            selected_sprite = s;
            selected_row = get_selected_index() / 10; // this works I suppose
            mouse.mouse_state = .inventory;
        }
        if (mouse.mouse_state == .none or mouse.mouse_state == .inventory) root.mouse.mouse_type = .pointer;
    }

    // Second pass for numbers to ensure they are at the top of inventory rendering
    for (active_slots, 0..) |active_sprite, i| {
        if (active_sprite == .none) continue;

        const id = @intFromEnum(active_sprite);
        const t_eased = ease_back(inventory_anim_progress[id]);

        const dt = @as(f32, @floatCast(time_diff)) / wobble_animation_length; // delta time in ms
        const wobble_progress = inventory_wobble_progress[id];
        if (wobble_progress != 0) {
            if (inventory_wobble_progress[id] > 0) {
                inventory_wobble_progress[id] = @max(0.0, inventory_wobble_progress[id] - dt * wobble_decay_speed);
            } else {
                inventory_wobble_progress[id] = @min(0.0, inventory_wobble_progress[id] + dt * wobble_decay_speed);
            }
        }

        // calculate wobble angle with sine wave (angle is in radians)
        const item_wobble = inventory_wobble_progress[id];
        const wobble_angle = std.math.sin(item_wobble * wobble_speed) * item_wobble * wobble_size;

        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;
        const size_vec = v2f32{ current_size, current_size };

        const col = @as(f32, @floatFromInt(i % inventory_width));
        const row = @as(f32, @floatFromInt(i / inventory_width));

        const inventory_pos: v2f32 = .{ 32 + col * spacing, 32 + row * spacing };
        const pos = inventory_pos - size_vec / v2f32{ base_size / 4.0, base_size / 4.0 } - v2f32{ base_size / 16.0, base_size / 16.0 };

        // wrap and convert hue to f32
        // hue is affected by ID in active slots AND wobble angles!
        const color_hue = @as(
            f32,
            @floatCast(@rem(@as(f64, @floatFromInt(i)) * 0.2 - @abs(wobble_angle * 2.0), std.math.tau)),
        );

        // number automatically resizes to be smaller for large values!
        const count = inventory_counts[@intFromEnum(active_sprite)];
        const digit_count_minus_one: f32 = if (count == 0) 1 else std.math.log10_int(count);
        const number_size = base_size * (1.0 + 0.3 * wobble_progress) / (@max(3.0, digit_count_minus_one + 0.5));

        draw_number( // shadow of inventory number
            count,
            pos + v2f32{ base_size / 3.5, base_size / 3.5 },
            .{
                .lcha = .{ 0.5, 0.2, color_hue, 0.8 },
                .font_size = number_size,
                .ltr = false,
                .rotation = wobble_angle, // text wobbles when you mine something!
            },
        );

        draw_number( // actual value
            count,
            pos + v2f32{ base_size / 3.2, base_size / 3.2 },
            .{
                .lcha = .{ 0.9, 0.2, color_hue, 1.0 },
                .font_size = number_size,
                .ltr = false,
                .rotation = wobble_angle,
            },
        );
    }
}

/// Back easing function: provides a slight negative dip before smoothing to the target.
fn ease_back(target: f32) f32 {
    const a = 1.70158;
    const b = a + 1.0;
    return b * target * target * target - a * target * target; // cubic func
}
