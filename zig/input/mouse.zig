//! Updates public values describing the mouse's position for other parts of the game, such as mining.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const main = root.startup;
const logger = root.logger;
const sprite = root.sprite;
const world = root.world;
const inventory = root.inventory;

const SPAN = memory.SPAN;
const SPAN_SQ = memory.SPAN_SQ;
const SCREEN_WIDTH = root.SCREEN_WIDTH;
const SCREEN_HEIGHT = root.SCREEN_HEIGHT;

/// Chunk the mouse is on.
/// Assume to be invalid if `is_mouse_down` is false.
pub var mouse_chunk: ?memory.Coordinate = null;
/// Subpixel of the chunk the mouse is on.
/// Assume to be invalid if `is_mouse_down` is false.
pub var mouse_subpixel: ?memory.v2u64 = null;
/// X block location the mouse is on (within the chunk).
/// Assume to be invalid if `is_mouse_down` is false.
pub var mouse_block_x: u4 = 0;
/// Y block location the mouse is on (within the chunk).
/// Assume to be invalid if `is_mouse_down` is false.
pub var mouse_block_y: u4 = 0;
/// Whether the mouse's block position changed. If coordinate is out of bounds, then set to true.
/// Is reset in `handle_mining()`, called from `tick()` in zig/root.zig.
pub var block_position_changed = true;

/// X-coordinate of the mouse (based on the UV).
/// Assume to be invalid if `is_mouse_down` is false.
pub var mouse_x: f64 = undefined;
/// Y-coordinate of the mouse (based on the UV).
/// Assume to be invalid if `is_mouse_down` is false.
pub var mouse_y: f64 = undefined;

pub var is_mouse_down: bool = false;

/// Handles mouse logic, where `x` and `y` values are between 0-1, acting like a UV over the whole canvas from HTML.
/// Action 0 (LEFT CLICK) : pointermove
/// Action 1 (LEFT CLICK) : pointerdown
/// Action 2 (LEFT CLICK) : pointerup
/// Action 3 (RIGHT CLICK): pointerdown
/// Action 4 (RIGHT CLICK): pointerup
/// Action 5 (INVALIDATE) : N/A (blur/resize happened, mouse_down becomes false)
pub fn handle_mouse(x: f64, y: f64, action: u32) void {
    if (action == 1) is_mouse_down = true;
    if (action == 2 or action == 5) is_mouse_down = false;
    mouse_x = x;
    mouse_y = y;
}

/// Updates the block/chunk the mouse is in.
pub fn update_mouse_block() void {
    if (!is_mouse_down) {
        return;
    }

    const game = &memory.game;
    const screen_dx = (mouse_x - 0.5) * SCREEN_WIDTH;
    const screen_dy = (mouse_y - 0.5) * SCREEN_HEIGHT;

    const world_dx = screen_dx / game.camera_scale * SPAN; // 1 pixel = 16 subpixels
    const world_dy = screen_dy / game.camera_scale * SPAN;

    const target_sx = game.camera_pos[0] + @as(i64, @round(world_dx));
    const target_sy = game.camera_pos[1] + @as(i64, @round(world_dy));

    const old_coord = mouse_chunk;
    const chunk_offset_x = @divFloor(target_sx, memory.SUBPIXELS_IN_CHUNK);
    const chunk_offset_y = @divFloor(target_sy, memory.SUBPIXELS_IN_CHUNK);

    const player_coord = game.get_player_coord();
    if (player_coord.move(.{ chunk_offset_x, chunk_offset_y })) |coord| {
        mouse_chunk = coord;

        const lx = @mod(target_sx, memory.SUBPIXELS_IN_CHUNK);
        const ly = @mod(target_sy, memory.SUBPIXELS_IN_CHUNK);

        const old_x = mouse_block_x;
        const old_y = mouse_block_y;
        mouse_block_x = @intCast(@divFloor(lx, SPAN_SQ));
        mouse_block_y = @intCast(@divFloor(ly, SPAN_SQ));
        block_position_changed =
            mouse_block_x != old_x or
            mouse_block_y != old_y or
            !memory.Coordinate.eql(coord, old_coord);
    } else {
        mouse_chunk = null;
        block_position_changed = true; // doesn't matter
    }
}
