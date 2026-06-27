//! Draws the furnace smelting menu.
const std = @import("std");
const dw = @import("../root.zig");

pub fn draw() void {
    const Vec2f32 = dw.utils.Vec2f32;
    const addEntitySized = dw.entity.addEntitySized;
    const toSize = dw.entity.toSizeUv;

    const menu_pos: Vec2f32 = .{ 0.02, 0.6 };
    // draw the menu...
    addEntitySized(.{ // box rect (top left alignment)
        .sprite = .rectangle,
        .position = menu_pos,
        .size = .{ 0.3, 0.3 },
        .lcha = .{ 0.8, 0.2, 1.5, 1.0 },
    });

    addEntitySized(.{ // rect (top left alignment)
        .sprite = .wood_icon,
        .position = menu_pos + Vec2f32{ 0.1, 0.1 },
        .size = toSize(0.1),
    });
    dw.logger.quick(.{toSize(0.1)});
}
