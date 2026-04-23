//! Handles logic for inventory management.
const root = @import("root").root;
const memory = root.memory;
const Sprite = root.sprite.Sprite;

const v2f32 = memory.v2f32;
const add_entity = root.entity.add_entity;
const draw_number = root.entity.draw_number;

/// Currently selected inventory ID (0-9).
pub var selected_id: u8 = 9;

/// Block types in each inventory slot.
// pub var inventory_blocks: [10]Sprite = .{.none} ** 10;
pub var inventory_blocks: [10]Sprite = .{
    .stone,
    .lava_stone,
    .strange_stone,
    .copper,
    .iron,
    .silver,
    .gold,
    .amethyst,
    .sapphire,
    .none,
};

/// Animation progress for each slot (0.0 = unselected, 1.0 = selected).
pub var inventory_animation_t: [10]f32 = [_]f32{0.0} ** 10;

/// Back easing function: provides a slight negative dip before smoothing to the target.
fn ease_back(t: f32) f32 {
    const c1 = 1.70158;
    const c3 = c1 + 1.0;
    // Cubic "Back In" formula for the dip, or "Back Out" for the landing.
    // Here we use a variation that creates a dip when starting the transition.
    return c3 * t * t * t - c1 * t * t;
}

/// Gets the position in internal viewport of an inventory ID.
pub inline fn get_inventory_pos(i: usize) v2f32 {
    return .{ 32 + 20 * @as(f32, @floatFromInt(i)), 32 };
}

/// Draws the 10 inventory slots and the blocks within them.
pub fn draw_inventory(dt: f64) void {
    _ = dt; // dt is an interpolation factor between -1 and 0; ignored for UI step

    // Progress the animation by a fixed amount per frame.
    // 0.1 completes the animation in 10 frames (approx. 0.16s at 60Hz).
    const animation_step: f32 = 0.1;

    for (0..10) |i| {
        // Update animation state per slot
        const target: f32 = if (i == selected_id) 1.0 else 0.0;

        if (inventory_animation_t[i] < target) {
            inventory_animation_t[i] = @min(target, inventory_animation_t[i] + animation_step);
        } else if (inventory_animation_t[i] > target) {
            inventory_animation_t[i] = @max(target, inventory_animation_t[i] - animation_step);
        }

        // Calculate visual scale using the easing formula
        const t_eased = ease_back(inventory_animation_t[i]);

        const size_normal: f32 = 10;
        const size_selected: f32 = 12;

        // Interpolate size based on eased t
        const current_size = size_normal + (size_selected - size_normal) * t_eased;
        const size_vec = v2f32{ current_size, current_size };

        // Center item based on size
        const pos = get_inventory_pos(i) - size_vec / v2f32{ 4, 4 } - v2f32{ 1, 1 };

        // Calculate background scale offset to keep it centered with the item
        const bg_size: f32 = if (i == selected_id) 18.0 else 16.0;
        const bg_vec = v2f32{ bg_size, bg_size };
        const bg_pos = get_inventory_pos(i) - bg_vec / v2f32{ 4, 4 };

        add_entity(.{ // draw inventory slot
            .sprite = if (i == selected_id) .inventory_selected else .inventory,
            .position = bg_pos,
            .size = bg_size,
        });

        add_entity(.{ // Item shadow
            .sprite = inventory_blocks[i],
            .position = pos - v2f32{ 1, 1 },
            .size = current_size,
            .lcha = .{ 0.7, 0.0, 0.0, 0.8 }, // darken with LCHA
        });

        add_entity(.{ // actual item inside
            .sprite = inventory_blocks[i],
            .position = pos,
            .size = current_size,
        });
    }
}
