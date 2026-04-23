//! Handles entities and stores functions relating on how to add them.
const std = @import("std");
const root = @import("root").root;
const SegmentedList = root.SegmentedList;
const memory = root.memory;
const ColorRGBA = root.ColorRGBA;
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

/// Array of entities.
pub var entities: SegmentedList(WGSLEntity, 1024) = .{}; // easiest to do prealloc with larger stack size in case

pub fn update_entities() void {
    // Every entity needs a position, size, rotation, LCHA, and sprite associated with it.
    // Some properties are optional with defaults (size, rotation, LCHA).

    for (0..10) |i| {
        add_entity(.{ // draw shadow of inventory
            .sprite = if (i == 0) .inventory_selected else .inventory,
            .position = .{ 30 + 20 * @as(f32, @floatFromInt(i)), 30 },
            .lcha = .{ if (i == 0) 0.8 else 0.7, 0.0, 0.0, 1.0 },
        });
    }

    for (0..10) |i| {
        add_entity(.{
            .sprite = if (i == 0) .inventory_selected else .inventory,
            .position = .{ 32 + 20 * @as(f32, @floatFromInt(i)), 32 },
        });
    }

    // example usage (TODO remove)
    const progress = root.mining.selected_hp;
    const pos: v2f32 = .{ 4, 31 };
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
/// Modifies the original entity instance.
pub inline fn add_entity(entity: Entity) void {
    const wgsl_entity: WGSLEntity = .{
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
    entities.append(root.world.alloc, wgsl_entity) catch @panic("Failed to add more entities!");
}
