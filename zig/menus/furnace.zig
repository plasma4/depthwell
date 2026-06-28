//! Draws the furnace smelting menu.
const dw = @import("../root.zig");

const Vec2f32 = dw.utils.Vec2f32;
const addEntitySized = dw.entity.addEntitySized;
const toSize = dw.entity.toSizeUv;

const SMELTING_STEPS = 12;
const FRAMES_PER_STEP = 3;
var smelting_progress: u16 = 0;

pub fn draw() void {
    @setFloatMode(.optimized);
    const menu_pos: Vec2f32 = .{ 0.02, 0.75 };
    const menu_size: Vec2f32 = toSize(0.3) * Vec2f32{ 1.0, 0.5 };
    const menu_center: Vec2f32 = menu_pos + menu_size / Vec2f32{ 2.0, 2.0 };

    // draw the menu...
    addEntitySized(.{ // box rect (top left alignment)
        .sprite = .rectangle,
        .position = menu_pos,
        .size = menu_size,
        .lcha = .{ 0.26, 0.2, 3.2, 1.0 },
    });

    addEntitySized(.{ // draw item frames
        .sprite = .wood_icon,
        .position = menu_center - Vec2f32{ 0.1, 0.0 },
        .size = toSize(0.04),
        .system = .center_uv,
        .lcha = .{ 0.65, -0.08, 0.0, 1.0 },
    });
    addEntitySized(.{
        .sprite = .wood_icon,
        .position = menu_center + Vec2f32{ 0.1, 0.0 },
        .size = toSize(0.04),
        .system = .center_uv,
        .lcha = .{ 0.65, -0.08, 0.0, 1.0 },
    });

    // draw progress bar for ore smelting
    dw.progress.drawBar(
        SMELTING_STEPS,
        smelting_progress / FRAMES_PER_STEP,
        menu_center,
        0.15,
        .center_uv,
        .{ 1.04, 0.12, -0.6, 1.0 },
    );
}

/// Updates smelting progress and logic.
pub fn updateSmelting() void {
    smelting_progress += 1;
    if (smelting_progress > SMELTING_STEPS * FRAMES_PER_STEP) smelting_progress = 0;
}
