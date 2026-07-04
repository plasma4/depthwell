//! Placeholder crafting menu opened by in-world core indicators (.core_off / .core1-.core4).
//!
//! Opening is toggled by clicking a core's indicator, which flips `dw.indicators.menus.corecraft`.
//! This menu is INDEPENDENT of the furnace menu: both can be open at once (see render/indicators.zig).
//! Real crafting is TODO; for now this only renders a static panel.
//! (Which cores are nearby is already tracked in `dw.indicators.nearby_cores` for future recipe/tier logic.)
const dw = @import("../root.zig");

const Vec2f = dw.utils.Vec2f;
const Vec2f32 = dw.utils.Vec2f32;
const addEntity = dw.entity.addEntity;
const addEntitySized = dw.entity.addEntitySized;
const toSize = dw.entity.toSizeUv;
const mouse = dw.mouse;

/// Menu panel size and placement in UV space (top-left aligned).
/// Placed at the bottom-right so it never overlaps the bottom-left furnace panel (both can be open at once).
/// Single-sourced so `draw()` and the `isHoveringOnMenu()` hit test can never drift apart.
const MENU_SIZE: Vec2f32 = toSize(0.3) * Vec2f32{ 1.0, 0.5 };
const MENU_POS: Vec2f32 = .{ 0.98 - MENU_SIZE[0], 0.75 };

/// Round-rect hitbox covering the whole menu panel, in viewport pixels.
fn menuHitbox() dw.geometry.Shape {
    const px_scale: Vec2f = .{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT };
    return dw.geometry.Shape.roundSquare(
        .{ @as(f64, MENU_POS[0]) * px_scale[0], @as(f64, MENU_POS[1]) * px_scale[1] },
        @as(f64, MENU_SIZE[0]) * px_scale[0],
        0.05,
    );
}

/// Whether the cursor is over the corecraft panel. Always false while the menu is closed.
/// Used by `mouse.processDownCaptures()` to keep pointerdown from falling through to the world.
pub fn isHoveringOnMenu() bool {
    if (!dw.indicators.menus.corecraft) return false;
    return menuHitbox().contains(mouse.uv_position * Vec2f{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT });
}

/// Resets the state of the corecraft menu.
pub fn reset() void {}

pub fn draw() void {
    @setFloatMode(.optimized);
    // The menu is only visible/interactive while opened via a core indicator.
    if (!dw.indicators.menus.corecraft) return;

    const px_scale: Vec2f = .{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT };
    const menu_center: Vec2f32 = MENU_POS + MENU_SIZE / Vec2f32{ 2.0, 2.0 };
    const center_px: Vec2f = .{ @as(f64, menu_center[0]) * px_scale[0], @as(f64, menu_center[1]) * px_scale[1] };

    // background panel
    addEntitySized(.{
        .sprite = .rectangle,
        .position = MENU_POS,
        .size = MENU_SIZE,
        .lcha = .{ 0.22, 0.16, 5.0, 1.0 },
    });

    // campfire preview near the top of the panel; brighter once a powered core is nearby
    addEntity(.{
        .sprite = .campfire,
        .position = .{ @floatCast(center_px[0]), @floatCast(center_px[1] - 14.0) },
        .size = 16.0,
        .lcha = if (dw.indicators.nearby_cores.anyPowered()) .{ 1.0, 0.0, 0.0, 1.0 } else .{ 0.55, 0.0, 0.0, 1.0 },
    });

    // placeholder crafting slots (non-interactive for now)
    const SLOT_SIZE: f32 = 18.0;
    inline for (.{ -12.0, 12.0 }) |off_x| {
        addEntity(.{
            .sprite = .wood_icon,
            .position = .{ @floatCast(center_px[0] + off_x), @floatCast(center_px[1] + 6.0) },
            .size = SLOT_SIZE,
            .lcha = .{ 0.6, -0.08, 0.0, 1.0 },
        });
    }
}
