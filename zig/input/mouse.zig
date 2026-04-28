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

/// The possible things the mouse started selecting on mouse down.
pub const MouseState = enum(u32) {
    /// Nothing (not even the canvas) was selected.
    /// If the state is set to this, then `uv_position` should also have negative X and Y values.
    none = 0,
    /// The canvas was selected on mouse down.
    canvas = 1,
    /// The inventory was selected on mouse down.
    inventory = 2,
};

/// The possible mouse cursors to use.
pub const MouseType = enum(u32) {
    initial = 0,
    pointer = 1,
};

/// The state the mouse is in (based on what it selected on mouse down).
pub var mouse_state: MouseState = .none;
/// The type of mouse cursor to use.
/// Reset at the start of every render tick and dispatched to JS at the end.
pub var mouse_type: MouseType = .initial;

/// Chunk the mouse is on; only updated when `updateMouseBlock()` is called.
/// Assume to be invalid if null.
pub var mouse_chunk: ?memory.Coordinate = null;
/// Subpixel of the chunk the mouse is on; only updated when `updateMouseBlock()` is called.
/// Assume to be invalid if null.
pub var mouse_subpixel: ?memory.Vec2u = null;
/// X block location the mouse is on (within the chunk).
/// Assume to be invalid if `mouse_chunk` or `mouse_subpixel` are null.
pub var mouse_block_x: u4 = 0;
/// Y block location the mouse is on (within the chunk).
/// Assume to be invalid if `mouse_chunk` or `mouse_subpixel` are null.
pub var mouse_block_y: u4 = 0;
/// Whether the mouse's block position changed. If coordinate is out of bounds, then set to true.
/// Is reset in `handleMining()`, called from `tick()` in zig/root.zig.
pub var block_position_changed = true;

/// Point coordinate of the mouse (based on the UV).
/// Assume to be invalid if values are negative (both will be -1.0 if invalid).
pub var uv_position: memory.Vec2f = .{ -1.0, -1.0 };

/// Determines if the mouse was just set to be down; reset at the end of a render frame.
pub var just_mouse_down: bool = false;

/// Handles mouse logic, where `x` and `y` values are between 0-1, acting like a UV over the whole canvas from HTML.
/// Action 0 (LEFT CLICK) : pointermove
/// Action 1 (LEFT CLICK) : pointerdown
/// Action 2 (LEFT CLICK) : pointerup
/// Action 3 (RIGHT CLICK): pointerdown
/// Action 4 (RIGHT CLICK): pointerup
/// Action 5 (INVALIDATE) : N/A (blur/resize happened, `mouse_state` resets)
pub fn handleMouse(x: f64, y: f64, action: u32) void {
    if (action == 1) {
        just_mouse_down = true;
        mouse_state = .canvas;
    } else if (action == 2 or action == 5) {
        just_mouse_down = false;
        mouse_state = .none;
    }
    uv_position = .{ x, y };
}

/// Updates the block/chunk the mouse is in.
pub fn updateMouseBlock() void {
    if (uv_position[0] < 0) {
        mouse_chunk = null;
        mouse_subpixel = null;
        return; // position must be invalid!
    }

    const game = &memory.game;
    const screen_dx = (uv_position[0] - 0.5) * SCREEN_WIDTH;
    const screen_dy = (uv_position[1] - 0.5) * SCREEN_HEIGHT;

    const world_dx = screen_dx / game.camera_scale * SPAN; // 1 pixel = 16 subpixels
    const world_dy = screen_dy / game.camera_scale * SPAN;

    const target_sx = game.camera_pos[0] + @as(i64, @round(world_dx));
    const target_sy = game.camera_pos[1] + @as(i64, @round(world_dy));

    const old_coord = mouse_chunk;
    const chunk_offset_x = @divFloor(target_sx, memory.SUBPIXELS_IN_CHUNK);
    const chunk_offset_y = @divFloor(target_sy, memory.SUBPIXELS_IN_CHUNK);

    const player_coord = game.getPlayerCoord();
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
