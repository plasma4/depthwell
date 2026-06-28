const std = @import("std");
const dw = @import("../root.zig");

const Sprite = dw.sprite.Sprite;
const Vec2f32 = dw.utils.Vec2f32;
const Vec4f32 = dw.utils.Vec4f32;
const addEntitySized = dw.entity.addEntitySized;
const toSize = dw.entity.toSizeUv;

/// Represents 8deg in radians.
/// The progress bar sprites have been pre-made to be shifted by 8 degrees per 4-pixel bar.
const HUE_AMOUNT = 2.0 * std.math.pi / 360.0 * 8;

/// Draws a progress bar with 4n bars (at least 8) using entities.
pub fn drawBar(
    width: u16,
    progress: u16,
    position: Vec2f32,
    render_width: f32,
    system: dw.memory.PositionType,
    base_lcha: dw.utils.Vec4f32,
) void {
    // It's quite complicated to do this!
    @setFloatMode(.optimized);

    // The width of the progress bar must be a multiple of 4 and at least 8.
    std.debug.assert(width >= 8 and width % 4 == 0);
    // The progress cannot be larger than the width of the bar itself.
    std.debug.assert(progress <= width);

    // Calculate the size of each individual progress bar sprite.
    const s = toSize(render_width / @as(f32, @floatFromInt(width / 4)));
    // If the position type is centered, then we'll want to handle that too.
    const pos =
        if (system == .center_uv or system == .center_viewport)
            position - Vec2f32{ s[0] / 2.0 * @as(f32, @floatFromInt(width / 4 - 1)), 0.0 }
        else
            position;

    // First, start by rendering the very left part of the progress bar.
    addEntitySized(.{
        // Sprites for both the left, middle, and right part of the progress bar go 0 bars, then 1, then 2, then 3, then 4.
        // Therefore, this simple formula calculates exactly what the sprite should be.
        .sprite = @enumFromInt(@intFromEnum(Sprite.progress_left) + @min(progress, 4)),
        .position = pos,
        .size = s,
        .lcha = base_lcha,
        .system = system,
    });

    var i: u16 = 1;
    while (i < width / 4 - 1) : (i += 1) {
        // Now, we draw as many center bars as needed.
        addEntitySized(.{
            // -| clamps the value so there's no integer overflow.
            .sprite = @enumFromInt(@intFromEnum(Sprite.progress_center) + @min(progress -| 4 * i, 4)),
            .position = pos + Vec2f32{ s[0] * @as(f32, @floatFromInt(i)), 0 },
            .size = s,
            .lcha = base_lcha + Vec4f32{
                0.0,
                0.0,
                // The hue increases by 32 degrees per new sprite but is also capped by the progress.
                // This makes the outline of the bar consistent when only part of the bar is filled.
                HUE_AMOUNT * @as(f32, @floatFromInt(@min(4 * i, progress -| 1))),
                0.0,
            },
            .system = system,
        });
    }

    // Finally, draw the right edge of the progress bar.
    addEntitySized(.{
        .sprite = @enumFromInt(@intFromEnum(Sprite.progress_right) + (progress -| 4 * i)),
        .position = pos + Vec2f32{ s[0] * @as(f32, @floatFromInt(i)), 0 },
        .size = s,
        .lcha = base_lcha + Vec4f32{
            0.0,
            0.0,
            HUE_AMOUNT * @as(f32, @floatFromInt(@min(4 * i, progress -| 1))),
            0.0,
        },
        .system = system,
    });
}
