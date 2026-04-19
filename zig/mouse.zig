//! Handles block selection from the mouse mining aspects.
const std = @import("std");
const memory = @import("memory.zig");
const main = @import("main.zig");
const sprite = @import("sprite.zig");
const world = @import("world.zig");

const SPAN = memory.SPAN;
const SPAN_SQ = memory.SPAN_SQ;
const SCREEN_WIDTH = main.SCREEN_WIDTH;
const SCREEN_HEIGHT = main.SCREEN_HEIGHT;

/// Chunk the mouse is on.
pub var mouse_chunk: ?memory.Coordinate = null;
/// Subpixel of the chunk the mouse is on.
pub var mouse_subpixel: ?memory.v2u64 = null;
/// X block location the mouse is on (within the chunk).
pub var mouse_block_x: u4 = 0;
/// Y block location the mouse is on (within the chunk).
pub var mouse_block_y: u4 = 0;
/// Current sprite (index) selected.
pub var selected_sprite: usize = 0;

var is_mouse_down: bool = false;

/// Handles mouse logic, where `x` and `y` values are between 0-1, acting like a UV over the whole canvas from HTML.
/// Action 0 (LEFT CLICK): mousemove  (or touch equivalent)
/// Action 1 (LEFT CLICK): mousedown  (or touch equivalent)
/// Action 2 (LEFT CLICK): mouseup    (or touch equivalent)
/// Action 3 (RIGHT CLICK): mousedown (or touch equivalent)
/// Action 4 (RIGHT CLICK): mouseup   (or touch equivalent)
pub fn handle_mouse(x: f64, y: f64, action: u32) void {
    const game = &memory.game;
    if (action == 1) is_mouse_down = true;
    if (action == 2) is_mouse_down = false;
    if (action == 3) selected_sprite = (selected_sprite + 1) % sprite.foundation_sprite_count;

    const screen_dx = (x - 0.5) * SCREEN_WIDTH;
    const screen_dy = (y - 0.5) * SCREEN_HEIGHT;

    const world_dx = screen_dx / game.camera_scale * SPAN; // 1 pixel = 16 subpixels
    const world_dy = screen_dy / game.camera_scale * SPAN;

    const target_sx = @as(i64, @intFromFloat(@round(@as(f64, @floatFromInt(game.camera_pos[0])) + world_dx)));
    const target_sy = @as(i64, @intFromFloat(@round(@as(f64, @floatFromInt(game.camera_pos[1])) + world_dy)));

    const chunk_offset_x = @divFloor(target_sx, memory.SUBPIXELS_IN_CHUNK);
    const chunk_offset_y = @divFloor(target_sy, memory.SUBPIXELS_IN_CHUNK);

    const player_coord = game.get_player_coord();
    if (player_coord.move(.{ chunk_offset_x, chunk_offset_y })) |coord| {
        mouse_chunk = coord;

        const lx = @mod(target_sx, memory.SUBPIXELS_IN_CHUNK);
        const ly = @mod(target_sy, memory.SUBPIXELS_IN_CHUNK);

        mouse_block_x = @intCast(@divFloor(lx, SPAN_SQ));
        mouse_block_y = @intCast(@divFloor(ly, SPAN_SQ));

        if (is_mouse_down) {
            world.apply_modification(coord, mouse_block_x, mouse_block_y, sprite.foundation_sprites[selected_sprite]);
        }
    } else {
        mouse_chunk = null;
    }
}
