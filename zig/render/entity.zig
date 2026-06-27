//! Handles entities and stores functions relating on how to add them.
const std = @import("std");
const dw = @import("../root.zig");
const SegmentedList = dw.SegmentedList;
const memory = dw.memory;
const sprite = dw.sprite;
const ColorRgba = dw.ColorRgba;
const inventory = dw.inventory;

const CHUNK_SIZE = dw.CHUNK_SIZE;
const Entity = memory.Entity;
const WGSLEntity = memory.WGSLEntity;
const Vec2f32 = dw.utils.Vec2f32;

/// Scale of tiles in the small chunk preview.
pub var preview_tile_size: f64 = 0.0;

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

/// Special variable so that `scratch_alloc_type` adds entities compactly.
pub var entity_byte_count_before_end: usize = 0;

/// Current number of entities (reset every frame).
pub var entity_count: u64 = 0;

/// Updates all entities by adding them to the scratch buffer. Does not actually inform JS by calling `handleVisibleEntities()`.
/// Every entity needs a position, size, rotation, LCHA, and sprite associated with it.
/// Some properties are optional with defaults (size, rotation, LCHA).
pub fn updateEntities(time_diff: f64) void {
    memory.scratchReset();
    // we're doing a new pass of drawing entities, clear anything before
    entity_count = 0;
    entity_byte_count_before_end = 0;

    inventory.addDroppedItemsAsEntities(time_diff); // pass in delta time in ms

    // draw indicators (icons above certain sprites)
    dw.indicators.drawIndicators();
    // if (dw.indicators.menus.furnace) @import("furnace_menu.zig").draw();
    @import("furnace_menu.zig").draw();

    // draw the inventory items/all items if in creative
    inventory.drawInventory(time_diff);

    // update mouse type logic and reset for next render frame
    dw.render.dispatchMouseType();
    dw.mouse.cursor_type = .initial;
    dw.mouse.clearFrameFlags();

    // draw chunk preview at the front
    if (dw.is_debug and preview_tile_size > 0.0) {
        dw.chunk_preview.drawChunkPreview();
    }

    memory.setScratchProp(0, entity_count);
    // entity rendering is dispatched to JS right after this function completes
}

/// Configuration for drawing a number.
pub const TextConfig = struct {
    /// The light, chroma, hue, and opacity components (HSL + alpha).
    /// L (lightness) and alpha components are multiplied by the sprite's color in WebGPU.
    /// H (hue, in radians) and C (chroma) are shifted additively.
    lcha: @Vector(4, f32) = memory.DEFAULT_ENTITY_LCHA,
    /// The font size of the text.
    font_size: f32 = 16.0,
    /// The rotation of the text.
    rotation: f32 = 0.0,
    /// Whether text is rendered from left-to-right (defaults to true; as in, left-aligned text).
    ltr: bool = true,
};

/// Draws an unsigned integer by creating entities; should NEVER be called outside of `updateEntities()`.
pub fn drawNumber(
    number: u64,
    position: Vec2f32,
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

    // Track the relative X offset from the pivot point
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
            const rotated_offset: Vec2f32 = .{ rel_x * cos_r, rel_x * sin_r };

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
            const rotated_offset: Vec2f32 = .{ rel_x * cos_r, rel_x * sin_r };

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
fn drawNumberFast(number: u64, position: Vec2f32, options: TextConfig) void {
    std.debug.assert(options.rotation == 0);
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

/// Adds a single entity to the `entities` array by adding a UV-based `WGSLEntity` to the scratch buffer.
pub fn addRawEntity(entity: WGSLEntity) void {
    @setFloatMode(.optimized);
    if (entity.size[0] == 0.0 or entity.size[1] == 0.0) return;
    if (entity.lcha[3] <= 0.0) return;

    // Viewport-based culling (accounting for rotation)
    const half_diag = entity.size * @as(Vec2f32, @splat(if (entity.rotation == 0.0) 0.5 else 1.0 / std.math.sqrt(2.0)));
    const min_x = entity.position[0] - half_diag[0];
    const max_x = entity.position[0] + half_diag[0];
    const min_y = entity.position[1] - half_diag[1];
    const max_y = entity.position[1] + half_diag[1];

    if (max_x < 0.0 or min_x > dw.SCREEN_WIDTH or max_y < 0.0 or min_y > dw.SCREEN_HEIGHT) {
        return;
    }

    entity_count += 1;
    const wgsl_entity = memory.scratchAllocType(WGSLEntity, &entity_byte_count_before_end);
    wgsl_entity.* = entity;
    // dw.logger.quick(.{ "{h}Entity ID", (@intFromPtr(wgsl_entity) - memory.mem.scratch_ptr) / @sizeOf(WGSLEntity) });
}

/// Adds a single entity to the `entities` array by adding a UV-based `WGSLEntity` to the scratch buffer.
/// No-op if the sprite type is `none`.
pub inline fn addEntity(entity: Entity) void {
    @setFloatMode(.optimized);
    if (entity.sprite.isEmpty()) return;
    const id = @intFromEnum(entity.sprite);
    @call(.always_inline, addRawEntity, .{WGSLEntity{
        .lcha = entity.lcha,
        .position = entity.position /
            Vec2f32{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT },
        .size = .{
            entity.size / dw.SCREEN_WIDTH,
            entity.size / dw.SCREEN_HEIGHT,
        },
        .rotation = entity.rotation,
        .id = if (id >= sprite.GEM_START and id < sprite.GEM_START + sprite.GEM_COUNT) id + sprite.GEM_COUNT else if (entity.sprite.isLiquid()) id + 1 else id,
    }});
}

/// Adds a single entity to the `entities` array by adding a UV-based `WGSLEntity` to the scratch buffer.
/// No-op if the sprite type is `none`.
pub inline fn addEntitySized(entity: memory.SizedEntity) void {
    @setFloatMode(.optimized);
    if (entity.sprite.isEmpty()) return;
    const id = @intFromEnum(entity.sprite);
    @call(.always_inline, addRawEntity, .{WGSLEntity{
        .lcha = entity.lcha,
        // See PositionType def for an explanation of this "magic formula"
        .position = .{
            entity.position + entity.size / Vec2f32{ 2.0, 2.0 },
            entity.position /
                Vec2f32{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT } + entity.size / Vec2f32{ 2.0, 2.0 },
            entity.position,
            entity.position /
                Vec2f32{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT },
        }[@intFromEnum(entity.system)],
        .size = if (entity.system == .top_left_viewport or entity.system == .center_viewport)
            entity.size /
                Vec2f32{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT }
        else
            entity.size,
        .rotation = entity.rotation,
        .id = if (id >= sprite.GEM_START and id < sprite.GEM_START + sprite.GEM_COUNT) id + sprite.GEM_COUNT else if (entity.sprite.isLiquid()) id + 1 else id,
    }});
}

/// Converts a horizontal width of a sprite to a square within UV coordinates.
pub inline fn toSizeUv(horizontal_width: f32) Vec2f32 {
    return @as(Vec2f32, @splat(horizontal_width)) * Vec2f32{ 1, @as(comptime_float, dw.SCREEN_WIDTH) / @as(comptime_float, dw.SCREEN_HEIGHT) };
}

/// Converts viewport coordinates to UV ones.
pub inline fn toViewport(uv: Vec2f32) Vec2f32 {
    return uv / Vec2f32{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT };
}

/// Converts UV coordinates to viewport ones.
pub inline fn toUv(viewport: Vec2f32) Vec2f32 {
    return viewport * Vec2f32{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT };
}
