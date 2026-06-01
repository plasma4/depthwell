//! Handles logic for inventory management.
const std = @import("std");
const root = @import("../root.zig");
const memory = root.memory;
const logger = root.logger;
const sprite = root.sprite;
const Sprite = sprite.Sprite;
const mouse = root.mouse;

const Vec2f32 = memory.Vec2f32;
const addEntity = root.entity.addEntity;
const drawNumber = root.entity.drawNumber;

/// Debug option, allowing for unlimited block placement.
/// NOT a comptime value because we may want this in the future during a release build.
pub var IN_CREATIVE = false;
/// Debug option, changing whether to show all inventory item slots and items or not.
pub const SHOW_ALL_INVENTORY_ITEMS = false;
/// Determines how wide each row of the inventory is.
const inventory_width = 10;

/// How many frames (logical) before an item enters the player's inventory.
fn getMaxItemDropLifespan() u16 {
    return if (IN_CREATIVE) 20 else 100;
}

/// Represents a single dropped item, including its type, position, and frames until addition to inventory.
const DroppedItem = struct {
    /// Which item is dropped.
    id: Sprite,
    /// Which chunk the dropped item is in.
    position: memory.Coordinate,
    /// Which subpixel X-coordinate the dropped item is in within the chunk position.
    /// May be temporarily negative or above 4096.
    subpixel_x: i32,
    /// Which subpixel Y-coordinate the dropped item is in within the chunk position.
    /// May be temporarily negative or above 4096.
    subpixel_y: i32,
    /// The previous chunk coordinate of the dropped item.
    last_position: memory.Coordinate,
    /// The subpixel X-coordinate of the dropped item for the previous frame.
    last_subpixel_x: i32,
    /// The subpixel Y-coordinate of the dropped item for the previous frame.
    last_subpixel_y: i32,
    /// How many frames before the item will be added to the player's inventory.
    frames_left: u16,
    /// Direction of sprite rotation.
    is_clockwise: bool,
};
pub var dropped_items: root.Fifo(DroppedItem) = .{};

pub inline fn isInCreative() bool {
    return root.is_debug and IN_CREATIVE;
}
pub inline fn shouldShowAllItems() bool {
    return root.is_debug and (IN_CREATIVE or SHOW_ALL_INVENTORY_ITEMS);
}

/// Which row the selected sprite is in.
/// Used for finding which active slot should be used and navigated through Q and E keys.
pub var selected_row: u16 = 0;

/// Slice array tyoe for possible slots.
pub const SlotBuffer = [sprite.item_sprite_count + 1]Sprite;

/// Current sprite selected to place.
pub var selected_sprite: Sprite = .none;

/// Dense storage: index is `@intFromEnum(Sprite)`, value is the number of that item in the inventory.
pub var inventory_counts: [sprite.max_sprite_value + 1]u64 = @splat(0);

/// Animation progress for each potential slot. Always between 0 (idle) and 1 (fully triggered).
pub var inventory_anim_progress: [sprite.max_sprite_value + 1]f32 = @splat(0.0);

/// Animation progress for the wobble effect of text. Always between -1 and 1; 0 if idle.
pub var inventory_wobble_progress: [sprite.max_sprite_value + 1]f32 = @splat(0.0);

/// Logs data on what is inside the inventory.
pub fn logInventory() void {
    // .quick and {h} work best here as you don't have to do a bunch of work figuring out formatting
    logger.quick(.{ "{h}Inventory counts", inventory_counts });
    logger.quick(.{ "{h}Selected sprite", selected_sprite });
}

/// Increments the amount of an item in the inventory, bypassing dropping.
pub fn addToInventory(id: Sprite, amount: u64) void {
    const idx = @intFromEnum(id);
    if (idx < inventory_counts.len) {
        inventory_counts[idx] += amount;
        if (inventory_wobble_progress[idx] == 0.0) inventory_wobble_progress[idx] = 1.0;
    }
}

/// Amount of dropped item sprites that were created.
var item_count: u64 = 0;

/// Creates an item drop animation and adds a `DroppedItem`.
pub fn dropItem(id: Sprite, chunk: memory.Coordinate, block_x: u4, block_y: u4) void {
    // Drop at the center of the block horizontally (+128), and the bottom vertically (+256)
    const px = @as(i32, block_x) * 256 + 128;
    const py = @as(i32, block_y) * 256 + 256;
    const seed = root.seeding.FastHash.hash2d(
        memory.game.seed2[14..16].*,
        memory.game.frame,
        item_count,
    );
    item_count +%= 1;
    addToInventory(id, 1);
    dropped_items.addOne(.{
        .id = id,
        .position = chunk,
        .subpixel_x = px + @as(i32, @intCast(seed % 128)) - 64,
        .subpixel_y = py + @as(i32, @intCast(seed / 128 % 128)) - 64,
        .last_position = chunk,
        .last_subpixel_x = px,
        .last_subpixel_y = py,
        .is_clockwise = (seed / (128 * 128) % 2 == 1),
        .frames_left = getMaxItemDropLifespan() * 3 / 4 +
            // monumentally silly code to get a block position to influence frames left
            // TODO: maybe this indicates we should really simplify things?
            @as(u16, @intCast((seed / (128 * 128 * 2)) % (getMaxItemDropLifespan() * 1 / 4))),
    }, root.world.alloc) catch memory.oom();
}

/// Calls `addEntity()` for each element in `dropped_items`, handling camera pan logic.
pub fn addDroppedItemsAsEntities(time_diff: f64) void {
    @setFloatMode(.optimized);
    _ = time_diff;
    const Context = struct {
        fn render_item(_: void, item: *DroppedItem) void {
            const player_coord = memory.game.getPlayerCoord();

            // Previous tick position
            const prev_diff_x = @as(i64, @bitCast(item.last_position.suffix[0] -% player_coord.suffix[0]));
            const prev_diff_y = @as(i64, @bitCast(item.last_position.suffix[1] -% player_coord.suffix[1]));
            const prev_item_sp_x = prev_diff_x * 4096 + @as(i64, item.last_subpixel_x);
            const prev_item_sp_y = prev_diff_y * 4096 + @as(i64, item.last_subpixel_y);

            // Current tick position
            const curr_diff_x = @as(i64, @bitCast(item.position.suffix[0] -% player_coord.suffix[0]));
            const curr_diff_y = @as(i64, @bitCast(item.position.suffix[1] -% player_coord.suffix[1]));
            const curr_item_sp_x = curr_diff_x * 4096 + @as(i64, item.subpixel_x);
            const curr_item_sp_y = curr_diff_y * 4096 + @as(i64, item.subpixel_y);

            // Interpolate using the global dt from chunk rendering
            const dt = root.chunks.current_dt + 1.0;
            const interp_item_sp_x = @as(f64, @floatFromInt(prev_item_sp_x)) +
                @as(f64, @floatFromInt(curr_item_sp_x - prev_item_sp_x)) * dt;
            const interp_item_sp_y = @as(f64, @floatFromInt(prev_item_sp_y)) +
                @as(f64, @floatFromInt(curr_item_sp_y - prev_item_sp_y)) * dt;

            // Camera interpolated position
            const cam_vel_x = memory.game.camera_pos[0] - memory.game.last_camera_pos[0];
            const cam_vel_y = memory.game.camera_pos[1] - memory.game.last_camera_pos[1];
            const interp_cam_x = @as(f64, @floatFromInt(memory.game.camera_pos[0])) + (@as(f64, @floatFromInt(cam_vel_x)) * dt);
            const interp_cam_y = @as(f64, @floatFromInt(memory.game.camera_pos[1])) + (@as(f64, @floatFromInt(cam_vel_y)) * dt);

            const delta_x_sp = interp_item_sp_x - interp_cam_x;
            const delta_y_sp = interp_item_sp_y - interp_cam_y;

            // do the same interpolation change
            const interpolated_zoom = memory.game.camera_scale * std.math.pow(f64, memory.game.camera_scale_change, dt);

            // Translate subpixels offset to screen space (1 pixel becomes 16 subpixels!)
            const screen_x = @as(f32, @floatCast(@as(f64, root.SCREEN_WIDTH_HALF) + delta_x_sp * (interpolated_zoom / 16.0)));
            const screen_y = @as(f32, @floatCast(@as(f64, root.SCREEN_HEIGHT_HALF) + delta_y_sp * (interpolated_zoom / 16.0)));

            const half_lifespan = getMaxItemDropLifespan() / 2;
            const life_fraction = @min(@as(f32, @floatFromInt(item.frames_left)) / half_lifespan, 1.0);
            // Shrink as it approaches player
            const item_size = if (life_fraction == 1.0) 16.0 else 4.0 + 12.0 * life_fraction;
            const rotation_mult: f32 = if (item.is_clockwise) 1 else -1;
            // Rotate as it flies (so peak)
            const rotation: f32 = if (life_fraction == 1.0) 0.0 else @as(f32, @floatFromInt(half_lifespan - item.frames_left)) *
                (std.math.pi / @as(f32, half_lifespan)) * rotation_mult;

            addEntity(.{
                .sprite = item.id,
                .position = .{ screen_x, screen_y },
                .size = item_size * @as(f32, @floatCast(interpolated_zoom)),
                .rotation = rotation,
                .lcha = .{ 1.0, 0.0, 0.0, @min(life_fraction * 1.8 - 0.8, 0.6) },
            });
        }
    };

    dropped_items.forEach({}, Context.render_item);
}

/// Executes logical updates for dropped items once a frame (60FPS).
pub fn tickDroppedItems() void {
    @setFloatMode(.optimized);
    const Context = struct {
        fn update(_: void, item: *DroppedItem) void {
            if (item.frames_left == 0) return;
            item.last_position = item.position;
            item.last_subpixel_x = item.subpixel_x;
            item.last_subpixel_y = item.subpixel_y;

            const player_coord = memory.game.getPlayerCoord();
            const diff_x = @as(i64, @bitCast(item.position.suffix[0] -% player_coord.suffix[0]));
            const diff_y = @as(i64, @bitCast(item.position.suffix[1] -% player_coord.suffix[1]));

            const item_sp_x_float: f64 = @floatFromInt(diff_x * 4096 + @as(i64, item.subpixel_x));
            const item_sp_y_float: f64 = @floatFromInt(diff_y * 4096 + @as(i64, item.subpixel_y));

            const target_sp_x = memory.game.player_pos[0];
            const target_sp_y = memory.game.player_pos[1];

            // Magnetic factor (per frame) gradually increases to 100% as frames run out
            const factor = 0.96 / std.math.pow(f64, @as(f64, @floatFromInt(item.frames_left)), 0.8) + 0.04;

            const next_sp_x = item_sp_x_float +
                (@as(f64, @floatFromInt(target_sp_x)) - item_sp_x_float) * factor;
            const next_sp_y = item_sp_y_float +
                (@as(f64, @floatFromInt(target_sp_y)) - item_sp_y_float) * factor;

            const chunk_dx = @as(i64, @intFromFloat(@floor(next_sp_x / 4096.0)));
            const chunk_dy = @as(i64, @intFromFloat(@floor(next_sp_y / 4096.0)));

            if (player_coord.move(.{ chunk_dx, chunk_dy })) |new_coord| {
                item.position = new_coord;
            }

            const rem_x = next_sp_x - @as(f64, @floatFromInt(chunk_dx)) * 4096.0;
            const rem_y = next_sp_y - @as(f64, @floatFromInt(chunk_dy)) * 4096.0;
            item.subpixel_x = @intFromFloat(rem_x);
            item.subpixel_y = @intFromFloat(rem_y);

            item.frames_left -= 1;
        }
    };

    dropped_items.forEach({}, Context.update);

    // Filter and collect items that reached their target at the head of the FIFO
    while (dropped_items.count > 0) {
        const head_item = &dropped_items.buf[dropped_items.head];
        if (head_item.frames_left == 0) {
            // addToInventory(head_item.id);
            _ = dropped_items.pop();
        } else {
            break;
        }
    }
}

/// Decrements the amount of an item in the inventory by 1.
/// Returns whether the removal was successful (as in, if there was at least one item, and the decrement worked).
pub fn removeFromInventory(id: Sprite) bool {
    if (id.isEmpty() or id == .unselected) return false;

    const idx = @intFromEnum(id);
    if (!isInCreative()) {
        if (idx >= inventory_counts.len or inventory_counts[idx] == 0) return false;
        inventory_counts[idx] -= 1;
    }
    if (inventory_wobble_progress[idx] == 0.0) inventory_wobble_progress[idx] = -1.0;

    // If we used the last one, unselect it immediately
    if (!isInCreative() and inventory_counts[idx] == 0 and selected_sprite == id) {
        selected_sprite = .unselected;
    }

    return true;
}

/// Helper to get the list of sprites currently in the inventory. Creates a temporary buffer in the stack.
/// Always starts with .none, followed by owned foundation sprites sorted by ID.
/// Requires a buffer to prevent dangling pointer (from local array) issues.
pub fn getSpritesInInventory(buffer: *SlotBuffer) []Sprite {
    var count: usize = 1;
    buffer[0] = .none; // slot 0 (pickaxe) must always exist

    // foundation_sprites is already sorted by enum ID because of how it's generated in zig/types/sprite.zig
    inline for (sprite.possible_item_sprites) |s| {
        if (s.isEmpty()) continue;
        if (shouldShowAllItems() or inventory_counts[@intFromEnum(s)] > 0) {
            buffer[count] = s;
            count += 1;
            // logger.quick(.{ s, buffer.len, sprite.max_sprite_value });
        }
    }

    return buffer[0..count];
}

/// Gets the index of `selected_sprite` in the active slots.
pub fn getSelectedIndex() u16 {
    if (selected_sprite.isEmpty() or selected_sprite == .unselected) return 0;
    var count: usize = 1;
    // foundation_sprites is already sorted by enum ID because of how it's generated in zig/types/sprite.zig
    inline for (sprite.possible_item_sprites) |s| {
        if (s.isEmpty()) continue;
        if (shouldShowAllItems() or inventory_counts[@intFromEnum(s)] > 0) {
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
pub fn getHoveredInventorySprite() ?Sprite {
    var buffer: SlotBuffer = undefined;
    const active_slots = getSpritesInInventory(&buffer);

    const base_size = 16.0;
    const spacing = 1.25 * base_size;
    const mouse_pos = mouse.uv_position * memory.Vec2f{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT };

    for (active_slots, 0..) |active_sprite, i| {
        const col: f32 = @floatFromInt(i % inventory_width);
        const row: f32 = @floatFromInt(i / inventory_width);

        const inventory_pos: Vec2f32 = .{ 32 + col * spacing, 32 + row * spacing };

        // Match the background sizing logic from the drawInventory() function
        const is_mine_type = active_sprite.isEmpty();
        const is_selected = active_sprite == selected_sprite;
        const bg_size: f32 = if (is_selected) base_size * 1.125 else if (is_mine_type) base_size * 0.9 else base_size;
        const bg_pos = inventory_pos - Vec2f32{ bg_size / 4.0, bg_size / 4.0 };

        const hitbox: root.geometry.Shape = .roundSquare(
            bg_pos - Vec2f32{ bg_size / 2.0, bg_size / 2.0 },
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
pub fn drawInventory(time_diff: f64) void {
    @setFloatMode(.optimized); // safe here, tis all rendering/mouse logic
    var buffer: SlotBuffer = undefined;
    const active_slots = getSpritesInInventory(&buffer);
    // logger.quick(.{ root.mining.selected_hp, inventory_counts });

    const wobble_decay_speed: f32 = 2.0; // controls wobble decay speed
    const wobble_speed: f32 = 10.0; // multiplier of sine of wobble for for values from -1 to 1
    const wobble_size: f32 = 1.0; // how many radians to rotate to the right or left
    const wobble_animation_length: f32 = 800.0; // controls wobble animation ms length
    const size_animation_length: f32 = 200.0; // item/background size animation change ms length
    const base_size = 16.0; // base size of inventory sprites
    const spacing = 1.25 * base_size; // spacing between sprites (must be at least base_size)

    var hovered_inventory_sprite: ?Sprite = null;
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

        const t_eased = easeBack(inventory_anim_progress[id]);
        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;

        const col: f32 = @floatFromInt(i % inventory_width);
        const row: f32 = @floatFromInt(i / inventory_width);

        const inventory_pos: Vec2f32 = .{ 32 + col * spacing, 32 + row * spacing };

        const is_mine_type = active_sprite.isEmpty();

        // Background sizing (using is_selected directly for instant feedback on bg)
        const bg_size: f32 = if (is_selected) base_size * 1.125 else if (is_mine_type) base_size * 0.9 else base_size;
        const bg_pos = inventory_pos - Vec2f32{ bg_size / 4.0, bg_size / 4.0 };

        // replace with pickaxe for UI
        const rendered_sprite = if (is_mine_type) Sprite.pickaxe else active_sprite;
        addEntity(.{
            .sprite = if (is_selected) .inventory_selected else .inventory,
            .position = bg_pos,
            .size = bg_size,
        });

        const pos = inventory_pos - Vec2f32{ current_size / 4.0, current_size / 4.0 } - Vec2f32{ 1.0, 1.0 };
        inline for (.{ 0, 1 }) |shadow_i| { // use array literal to make it comptime
            addEntity(.{ // item shadow
                .sprite = rendered_sprite,
                .position = pos - Vec2f32{
                    @cos(std.math.pi / 4.5 - 0.05 * col) * (shadow_i + 1) * 0.8,
                    @sin(std.math.pi / 4.5 - 0.05 * col) * (shadow_i + 1) * 0.8,
                },
                .size = current_size,
                // a little bit of chroma addition and variation here!
                // the shadow is more like the original sprite for stone sprites and much more bland otherwise
                .lcha = .{
                    (if (rendered_sprite.isStone()) (0.9 - shadow_i * 0.15) else (0.7 - shadow_i * 0.15)), // lightness mult
                    0.03 + 0.02 * shadow_i, // a side effect of this is that perfectly gray sprites' shadows become more red
                    0.0, // no hue shift
                    0.4, // opacity
                },
            });
        }

        addEntity(.{ // actual item
            .sprite = rendered_sprite,
            .position = pos,
            .size = current_size,
        });

        const hitbox: root.geometry.Shape = .roundSquare(
            bg_pos - Vec2f32{ bg_size / 2.0, bg_size / 2.0 },
            bg_size,
            0.2,
        );
        if (hitbox.contains(mouse.uv_position * memory.Vec2f{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT })) {
            hovered_inventory_sprite = active_sprite;
        }
    }

    if (hovered_inventory_sprite) |s| {
        if (mouse.just_mouse_down) {
            selected_sprite = s;
            selected_row = getSelectedIndex() / 10; // this works I suppose
            mouse.mouse_state = .inventory;
        }
        if (mouse.mouse_state == .none or mouse.mouse_state == .inventory) root.mouse.mouse_type = .pointer;
    }

    // Second pass for numbers to ensure they are at the top of inventory rendering
    for (active_slots, 0..) |active_sprite, i| {
        if (active_sprite.isEmpty()) continue;

        const id = @intFromEnum(active_sprite);
        const t_eased = easeBack(inventory_anim_progress[id]);

        const dt = @as(f32, @floatCast(time_diff)) / wobble_animation_length; // delta time in ms
        const wobble_progress = inventory_wobble_progress[id];
        if (wobble_progress != 0) {
            if (inventory_wobble_progress[id] > 0) {
                inventory_wobble_progress[id] = @max(0.0, inventory_wobble_progress[id] - dt * wobble_decay_speed);
            } else {
                inventory_wobble_progress[id] = @min(0.0, inventory_wobble_progress[id] + dt * wobble_decay_speed);
            }
        }
        const size_normal: f32 = 10.0 / 16.0 * base_size;
        const size_selected: f32 = 12.0 / 16.0 * base_size;
        const current_size = size_normal + (size_selected - size_normal) * t_eased;
        const size_vec = Vec2f32{ current_size, current_size };

        const col: f32 = @floatFromInt(i % inventory_width);
        const row: f32 = @floatFromInt(i / inventory_width);

        const inventory_pos: Vec2f32 = .{ 32 + col * spacing, 32 + row * spacing };
        const pos = inventory_pos - size_vec / Vec2f32{ base_size / 4.0, base_size / 4.0 } - Vec2f32{ base_size / 16.0, base_size / 16.0 };

        // number automatically resizes to be smaller for large values!
        const count = inventory_counts[@intFromEnum(active_sprite)];
        const digit_count_minus_one: f32 = if (count == 0) 1 else std.math.log10_int(count);
        const number_size = base_size * (1.0 + 0.3 * wobble_progress) / (@max(3.0, digit_count_minus_one + 0.5));

        // calculate wobble angle with sine wave (angle is in radians)
        // if the item is implied to be more common (more digit count in the number), then wobble less!
        const item_wobble = inventory_wobble_progress[id];
        const wobble_angle = std.math.sin(item_wobble * wobble_speed) * item_wobble * wobble_size / (digit_count_minus_one + 1.0);

        // wrap and convert hue to f32
        // hue is affected by ID in active slots AND wobble angles!
        const color_hue: f32 = @floatCast(@rem(@as(f64, @floatFromInt(i)) * 0.2 - @abs(wobble_angle * 2.0), std.math.tau));

        if (!isInCreative()) {
            drawNumber( // shadow of inventory number
                count,
                pos + Vec2f32{ base_size / 3.5, base_size / 3.5 },
                .{
                    .lcha = .{ 0.5, 0.2, color_hue, 0.8 },
                    .font_size = number_size,
                    .ltr = false,
                    .rotation = wobble_angle, // text wobbles when you mine something!
                },
            );

            drawNumber( // actual value
                count,
                pos + Vec2f32{ base_size / 3.2, base_size / 3.2 },
                .{
                    .lcha = .{ 0.9, 0.2, color_hue, 1.0 },
                    .font_size = number_size,
                    .ltr = false,
                    .rotation = wobble_angle,
                },
            );
        }
    }
}

/// Back easing function (time-based)
/// Has a slight negative dip before smoothing to the target.
fn easeBack(target: f32) f32 {
    const a = 1.70158;
    const b = a + 1.0;
    return b * target * target * target - a * target * target; // cubic func
}
