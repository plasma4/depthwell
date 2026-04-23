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
    const progress = root.mining.selected_hp;
    const pos: v2f32 = .{ 10, 50 };
    const font_size = 20;
    if (progress != 255) {
        draw_number( // shadow
            progress,
            pos - @as(v2f32, .{ 1, 1 }),

            // check Entity definition for why this is correct
            // (multiplication works on pure white sprites ultimately)
            // yes, we are converting from hex->oklab->oklch, with texture from rgb->oklab->oklch
            // then mixing the two, then converting that into oklch->oklab->hex.
            comptime ColorRGBA.hex_to_oklch("#000000bb"),
            font_size,
            true,
        );

        draw_number( // actual num
            progress,
            pos,
            .{
                0.75,
                0.4,
                0.2 + @as(f32, @floatFromInt(progress)) * 0.3, // hue changing!
                1.0,
            },
            font_size,
            true,
        );
    }

    // entities are cleared in the render code afterward
}

/// Draws an unsigned integer.
pub fn draw_number(
    number: u64,
    position: v2f32,
    lcha: @Vector(4, f32),
    font_size: f32,
    comptime ltr: bool,
) void {
    // Handle zero as a special case to simplify the loop logic
    if (number == 0) {
        add_entity(.{
            .sprite = @enumFromInt(root.sprite.NUMBER_START),
            .lcha = lcha,
            .position = position,
            .size = font_size,
        });
        return;
    }

    // u64 max is 18,446,744,073,709,551,615 (20 digits)
    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var n = number;

    // Extract digits: This always results in digits[0] being the 'ones' place.
    while (n > 0) : (n /= 10) {
        digits[count] = @intCast(n % 10);
        count += 1;
    }

    var current_pos = position;

    if (ltr) {
        // left to right: start from the last digit found (most significant)
        current_pos[0] -= number_widths[@intCast(digits[count - 1])] * font_size; // subtract last digit to prevent being off
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
        // right to left: start from the first digit found (least significant)
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
