//! Handles entities and stores functions relating on how to add them.
const std = @import("std");
const root = @import("root").root;
const SegmentedList = root.SegmentedList;
const memory = root.memory;
const sprite = root.sprite;
const ColorRGBA = root.ColorRGBA;
const inventory = root.inventory;
const Entity = memory.Entity;
const WGSLEntity = memory.WGSLEntity;

const v2f32 = memory.v2f32;

/// Extra spacing between number characters.
const spacing = 0.25;
/// Pre-calculated widths of every number sprite from 0 to 9.
const number_widths: [10]f32 = .{
    0.5625 + spacing,
    0.375 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.75 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
};

// not needed: entities are generated directly in the scratch alloc
// /// Array of entities.
// pub var entities: SegmentedList(WGSLEntity, 1024) = .{}; // easiest to do prealloc with larger stack size in case

/// Special variable so that `scratch_alloc_type` adds entities compactly.
var entity_byte_count_before_end: usize = 0;

/// Current number of entities (reset every frame).
var entity_count: u64 = undefined;

/// Updates all entities by adding them to the scratch buffer. Does not actually inform JS.
pub fn updateEntities(time_diff: f64) void {
    memory.scratchReset();
    entity_count = 0;
    entity_byte_count_before_end = 0;

    root.mouse.mouse_type = .initial;
    inventory.drawInventory(time_diff);
    root.render.dispatchMouseType();
    root.mouse.just_mouse_down = false;

    // Every entity needs a position, size, rotation, LCHA, and sprite associated with it.
    // Some properties are optional with defaults (size, rotation, LCHA).

    // draw selected HP (for testing)
    const progress = root.mining.selected_hp;
    const pos: v2f32 = .{ 10, 28 };
    const font_size = 10.0;

    if (progress != 255 and progress != 0) {
        const value_hue = 0.2 + @as(f32, @floatFromInt(progress)) * (std.math.pi / 8.0);
        // draw shadow of text
        drawNumber(progress, pos - v2f32{ 1.5, 1.5 }, .{
            .lcha = .{
                0.5, // darken
                0.4,
                value_hue, // hue changing as progress increases!
                0.8,
            },
            .font_size = font_size,
            .ltr = false,
        });

        // draw the actual number now
        drawNumber(progress, pos, .{
            .lcha = .{
                0.75,
                0.4,
                value_hue, // hue changing too
                1.0,
            },
            .font_size = font_size,
            .ltr = false,
        });
    }

    memory.setScratchProp(0, entity_count);
    // entities are cleared in the render code afterward
}

/// Configuration for drawing a number.
pub const TextConfig = struct {
    /// The light, chroma, hue, and opacity components (HSL + alpha).
    /// L (lightness) and alpha components are multiplied by the sprite's color in WGSL.
    /// H (hue, in radians) and C (chroma) are shifted additively.
    lcha: @Vector(4, f32) = memory.DEFAULT_ENTITY_LCHA,
    /// The font size of the text.
    font_size: f32 = 16.0,
    /// The rotation of the text.
    rotation: f32 = 0.0,
    ltr: bool = true,
};

/// Draws an unsigned integer by creating entities; should NEVER be called outside of `updateEntities()`.
pub fn drawNumber(
    number: u64,
    position: v2f32,
    options: TextConfig,
) void {
    const lcha = options.lcha;
    const font_size = options.font_size;
    const rotation = options.rotation;
    const ltr = options.ltr;

    // Fast path for zero-rotation cases
    if (rotation == 0.0) {
        drawNumberFast(number, position, options);
        return;
    }

    if (number == 0) {
        addEntity(.{
            .sprite = @enumFromInt(sprite.NUMBER_START),
            .lcha = lcha,
            .position = position,
            .size = font_size,
            .rotation = rotation,
        });
        return;
    }

    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var n = number;

    while (n > 0) : (n /= 10) {
        digits[count] = @intCast(n % 10);
        count += 1;
    }

    // Precompute trig for the entire string
    const cos_r = @cos(rotation);
    const sin_r = @sin(rotation);

    // We track the relative X offset from the pivot point
    var rel_x: f32 = 0.0;

    if (ltr) {
        // Initial shift for LTR logic
        rel_x -= number_widths[@intCast(digits[count - 1])] * font_size;

        var i: usize = count;
        while (i > 0) {
            i -= 1;
            const digit = digits[i];
            rel_x += number_widths[@intCast(digit)] * font_size;

            // Rotate the relative offset vector (rel_x, 0)
            const rotated_offset = v2f32{ rel_x * cos_r, rel_x * sin_r };

            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = position + rotated_offset,
                .size = font_size,
                .rotation = rotation,
            });
        }
    } else {
        for (digits[0..count]) |digit| {
            const rotated_offset = v2f32{ rel_x * cos_r, rel_x * sin_r };

            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = position + rotated_offset,
                .size = font_size,
                .rotation = rotation,
            });
            rel_x -= number_widths[@intCast(digit)] * font_size;
        }
    }
}

/// Optimized version of draw_number for when rotation is exactly 0.
fn drawNumberFast(number: u64, position: v2f32, options: TextConfig) void {
    const lcha = options.lcha;
    const font_size = options.font_size;
    const ltr = options.ltr;

    if (number == 0) {
        addEntity(.{
            .sprite = @enumFromInt(sprite.NUMBER_START),
            .lcha = lcha,
            .position = position,
            .size = font_size,
        });
        return;
    }

    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var n = number;

    while (n > 0) : (n /= 10) {
        digits[count] = @intCast(n % 10);
        count += 1;
    }

    var current_pos = position;

    if (ltr) {
        current_pos[0] -= number_widths[@intCast(digits[count - 1])] * font_size;
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            const digit = digits[i];
            current_pos[0] += number_widths[@intCast(digit)] * font_size;

            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = current_pos,
                .size = font_size,
            });
        }
    } else {
        for (digits[0..count]) |digit| {
            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = current_pos,
                .size = font_size,
            });
            current_pos[0] -= number_widths[@intCast(digit)] * font_size;
        }
    }
}

/// Adds a single entity to the `entities` array, changing position to use UV.
/// Modifies the original entity instance. Does not do anything if the sprite type is `none`.
pub inline fn addEntity(entity: Entity) void {
    entity_count += 1;
    const wgsl_entity = memory.scratchAllocType(WGSLEntity, &entity_byte_count_before_end);
    wgsl_entity.* = .{
        .lcha = entity.lcha,
        .position = entity.position /
            v2f32{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT },
        .size = v2f32{
            entity.size / root.SCREEN_WIDTH,
            entity.size / root.SCREEN_HEIGHT,
        },
        .rotation = entity.rotation,
        .id = @intFromEnum(entity.sprite),
    };
    // root.logger.quick(.{ "{h}Entity ID", (@intFromPtr(wgsl_entity) - memory.mem.scratch_ptr) / @sizeOf(WGSLEntity) });
}
