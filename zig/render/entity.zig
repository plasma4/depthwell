//! Handles entities and stores functions relating on how to add them.
const std = @import("std");
const root = @import("root").root;
const SegmentedList = root.SegmentedList;
const memory = root.memory;
const ColorRGBA = root.ColorRGBA;
const inventory = root.inventory;
const Entity = memory.Entity;
const WGSLEntity = memory.WGSLEntity;

const v2f32 = memory.v2f32;

/// Extra spacing between number characters.
const spacing = 0.25;
/// Pre-calculated widths of every number sprite from 0-10.
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
var entity_byte_count_before_end: usize = 0;

pub fn update_entities(dt: f64) void {
    entity_byte_count_before_end = 0;
    // Every entity needs a position, size, rotation, LCHA, and sprite associated with it.
    // Some properties are optional with defaults (size, rotation, LCHA).

    inventory.draw_inventory(dt);

    // draw selected HP (for testing)
    const progress = root.mining.selected_hp;
    const pos: v2f32 = .{ 2, 28 };
    const font_size = 12.0;

    if (progress != 255) {
        // draw shadow of text
        draw_number(progress, pos, .{
            .lcha = comptime ColorRGBA.hex_to_oklch("#000000bb"),
            .font_size = font_size,
            .ltr = true,
        });

        // draw the actual number now
        draw_number(progress, pos, .{
            .lcha = .{
                0.75,
                0.4,
                0.2 + @as(f32, @floatFromInt(progress)) * 0.3, // hue changing!
                1.0,
            },
            .font_size = font_size,
            .ltr = true,
        });
    }

    // entities are cleared in the render code afterward
}

/// Configuration for drawing a number.
pub const TextConfig = struct {
    lcha: @Vector(4, f32) = memory.DEFAULT_ENTITY_LCHA,
    font_size: f32 = 20.0,
    ltr: bool = true,
};

/// Draws an unsigned integer.
pub fn draw_number(
    number: u64,
    position: v2f32,
    options: TextConfig,
) void {
    const lcha = options.lcha;
    const font_size = options.font_size;
    const ltr = options.ltr;

    if (number == 0) {
        add_entity(.{
            .sprite = @enumFromInt(root.sprite.NUMBER_START),
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

            add_entity(.{
                .sprite = @enumFromInt(root.sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = current_pos,
                .size = font_size,
            });
        }
    } else {
        for (digits[0..count]) |digit| {
            add_entity(.{
                .sprite = @enumFromInt(root.sprite.NUMBER_START + digit),
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
pub inline fn add_entity(entity: Entity) void {
    if (entity.sprite == .none) return;
    const wgsl_entity = memory.scratch_alloc_type(WGSLEntity, &entity_byte_count_before_end);
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
    // root.logger.quick(.{@intFromPtr(wgsl_entity) -| @intFromPtr(memory.scratch_buffer.ptr)});
}
