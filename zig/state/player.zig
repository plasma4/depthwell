//! Handles the main player movement and camera logic.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const logger = root.logger;
const KeyBits = root.KeyBits;
const main = root.startup;
const world = root.world;
const SPAN = memory.SPAN;
const SPAN_SQ = memory.SPAN_SQ;
const SUBPIXELS_IN_CHUNK = memory.SUBPIXELS_IN_CHUNK;

const v2i64 = memory.v2i64;
const v2f64 = memory.v2f64;

/// Minimum camera zoom/scale allowed. This is strategically calculated to make sure the default render distance is safe.
/// Too small and `SimBuffer` nor `ChunkCache` would no longer be able to reliably cache and work as intended.
///
/// Setting this to a very small value is useful for testing cache validity or performance, however.
pub const CAMERA_MIN_ZOOM = 1.0 / 3.0;

/// Maximum camera zoom/scale allowed. This is strategically calculated to make sure the player always remains in the viewport.
/// Any more and it would look weird, and camera deadzone would start to no longer work.
pub const CAMERA_MAX_ZOOM = 1.0; // 100%

/// The base speed of the player.
pub var PLAYER_BASE_SPEED: f64 = 1.0;
/// How strong the gravity is.
pub var GRAVITY: f64 = 0.4;
/// How high the player jumps.
pub var JUMP_FORCE: f64 = 8.0;
/// Friction of player movement (horizontal).
pub var FRICTION_X: f64 = 0.2;
/// Friction of player movement (vertical).
pub var FRICTION_Y: f64 = 0.02;

/// The size of the player's width. The player is assumed to be centered at the bottom as a rectangle.
pub const PLAYER_HITBOX_WIDTH = 64;
/// The size of the player's height. The player is assumed to be centered at the bottom as a rectangle.
pub const PLAYER_HITBOX_HEIGHT = 160;
/// Prevent block-skipping with collisions when travelling quickly.
const CCD_STEP_SIZE = SPAN_SQ;

/// The zoom in/out keys change the zoom multiplier this fast per frame.
const CAMERA_CHANGE_SPEED = 1.02;
/// How fast the camera should adjust per frame to the new position. Larger means faster.
const CAMERA_SMOOTHING = 0.25;

/// How far the player has to move before actually panning the camera in sub-pixels (x-axis).
const CAMERA_DEADZONE_X = 10 * memory.SPAN_SQ; // memory.SPAN_SQ means 1 block, basically
/// How far the player has to move before actually panning the camera in sub-pixels (y-axis).
const CAMERA_DEADZONE_Y = 3 * memory.SPAN_SQ;

const pixel_mult: v2f64 = .{ @floatFromInt(SPAN), @floatFromInt(SPAN) };
pub var subpixel_accum: v2f64 = .{ 0.0, 0.0 }; // note that vectors are smartly aligned already

/// Determines if the player is on the ground.
var is_grounded: bool = false;

/// Moves the player, handling camera changes.
pub fn move(logic_speed: f64) void {
    const game = &memory.game;
    const dt = logic_speed;

    // handle camera zoom (.pow is safe here despite being inconsistent on different devices)
    const old_camera_scale = game.camera_scale;
    if (KeyBits.isSet(KeyBits.plus, game.keys_held_mask)) {
        game.camera_scale = @min(game.camera_scale * std.math.pow(f64, CAMERA_CHANGE_SPEED, dt), CAMERA_MAX_ZOOM);
    }
    if (KeyBits.isSet(KeyBits.minus, game.keys_held_mask)) {
        game.camera_scale = @max(game.camera_scale / std.math.pow(f64, CAMERA_CHANGE_SPEED, dt), CAMERA_MIN_ZOOM);
    }
    game.camera_scale_change = game.camera_scale / old_camera_scale;

    // Analytical velocity (basic damped linear system)
    var move_input: f64 = 0;
    if (KeyBits.isSet(KeyBits.left, game.keys_held_mask)) move_input -= PLAYER_BASE_SPEED;
    if (KeyBits.isSet(KeyBits.right, game.keys_held_mask)) move_input += PLAYER_BASE_SPEED;

    const f_x = 1.0 - FRICTION_X;
    const f_y = 1.0 - FRICTION_Y;
    const pow_fx = std.math.pow(f64, f_x, dt);
    const pow_fy = std.math.pow(f64, f_y, dt);

    // Update x velocity
    game.player_velocity[0] = (game.player_velocity[0] * pow_fx) +
        (move_input * f_x * (1.0 - pow_fx) / FRICTION_X);

    // Update y velocity with gravity
    if (is_grounded and KeyBits.isSet(KeyBits.up, game.keys_held_mask)) {
        game.player_velocity[1] = -JUMP_FORCE;
        is_grounded = false;
    } else {
        game.player_velocity[1] = (game.player_velocity[1] * pow_fy) +
            (GRAVITY * f_y * (1.0 - pow_fy) / FRICTION_Y);
    }

    // Physics displacement using average velocity!
    const displacement = game.player_velocity * @as(v2f64, @splat(dt * memory.SPAN_FLOAT));
    subpixel_accum += displacement;

    const total_move = @as(v2i64, @floor(subpixel_accum));
    subpixel_accum -= @as(v2f64, @floatFromInt(total_move));

    game.last_player_pos = game.player_pos;
    var total_chunk_shift: v2i64 = .{ 0, 0 };

    // vertical CCD
    is_grounded = false;
    var rem_y = @abs(total_move[1]);
    const step_y = if (total_move[1] > 0) @as(i64, 1) else -1;
    while (rem_y > 0) {
        const move_now = @min(rem_y, CCD_STEP_SIZE);
        if (!isColliding(game.player_pos[0], game.player_pos[1] + (step_y * move_now))) {
            game.player_pos[1] += step_y * move_now;
            total_chunk_shift[1] += handleLocalWrap(1);
            rem_y -= move_now;
        } else {
            // Perfect snap: Move 1 pixel at a time until contact
            var sub_steps = move_now;
            while (sub_steps > 0) : (sub_steps -= 1) {
                if (!isColliding(game.player_pos[0], game.player_pos[1] + step_y)) {
                    game.player_pos[1] += step_y;
                    total_chunk_shift[1] += handleLocalWrap(1);
                } else break;
            }
            if (step_y > 0) is_grounded = true;
            game.player_velocity[1] = 0;
            subpixel_accum[1] = 0;
            break;
        }
    }

    // Now do horizontal CCD
    var rem_x = @abs(total_move[0]);
    const step_x = if (total_move[0] > 0) @as(i64, 1) else -1;
    while (rem_x > 0) {
        const move_now = @min(rem_x, CCD_STEP_SIZE);
        if (!isColliding(game.player_pos[0] + (step_x * move_now), game.player_pos[1])) {
            game.player_pos[0] += step_x * move_now;
            total_chunk_shift[0] += handleLocalWrap(0);
            rem_x -= move_now;
        } else {
            var sub_steps = move_now;
            while (sub_steps > 0) : (sub_steps -= 1) {
                if (!isColliding(game.player_pos[0] + step_x, game.player_pos[1])) {
                    game.player_pos[0] += step_x;
                    total_chunk_shift[0] += handleLocalWrap(0);
                } else break;
            }
            game.player_velocity[0] = 0;
            subpixel_accum[0] = 0;
            break;
        }
    }

    // Finally, tell SimBuffer and the camera to update.
    world.SimBuffer.sync(game.getPlayerCoord(), total_chunk_shift);
    updateCamera(dt);
}

/// Updates the player_chunk and returns the chunk carry (displacement).
/// This keeps game.player_pos normalized and updates fractal quadrant logic.
fn handleLocalWrap(comptime axis: u1) i64 {
    const game = &memory.game;
    const val = game.player_pos[axis];
    if (val < 0 or val >= memory.SUBPIXELS_IN_CHUNK) {
        const carry = @divFloor(val, memory.SUBPIXELS_IN_CHUNK);
        const current_coord = game.getPlayerCoord();

        const new_coord = if (axis == 0)
            current_coord.moveX(carry)
        else
            current_coord.moveY(carry);

        if (new_coord) |c| {
            game.player_quadrant = c.quadrant;
            game.player_chunk = c.suffix;
            game.player_pos[axis] = @mod(val, memory.SUBPIXELS_IN_CHUNK);

            // Adjust last_player_pos and camera so interpolation doesn't snap
            const subpixel_offset = carry * memory.SUBPIXELS_IN_CHUNK;
            game.last_player_pos[axis] -= subpixel_offset;
            game.camera_pos[axis] -= subpixel_offset;
            return carry;
        } else {
            // World edge hit: snap back
            game.player_pos[axis] = if (val < 0) 0 else memory.SUBPIXELS_IN_CHUNK - 1;
        }
    }
    return 0;
}

/// Performs an AABB check (for the player's position) against the world grid.
pub fn isColliding(px: i64, py: i64) bool {
    const game = &memory.game;
    const corners = [4][2]i64{
        .{ px - PLAYER_HITBOX_WIDTH / 2, py + SPAN_SQ / 2 - PLAYER_HITBOX_HEIGHT },
        .{ px + PLAYER_HITBOX_WIDTH / 2 - 1, py + SPAN_SQ / 2 - PLAYER_HITBOX_HEIGHT },
        .{ px - PLAYER_HITBOX_WIDTH / 2, py + SPAN_SQ / 2 },
        .{ px + PLAYER_HITBOX_WIDTH / 2 - 1, py + SPAN_SQ / 2 },
    };

    const player_coord = game.getPlayerCoord();
    var last_coord: ?memory.Coordinate = null;
    var cached_chunk: memory.Chunk = undefined;

    for (corners) |c| {
        const cx_shift = @divFloor(c[0], SUBPIXELS_IN_CHUNK);
        const cy_shift = @divFloor(c[1], SUBPIXELS_IN_CHUNK);
        const target_coord = player_coord.move(.{ cx_shift, cy_shift }) orelse return true;

        if (last_coord == null or !target_coord.eql(last_coord.?)) {
            cached_chunk = world.getChunk(target_coord);
            last_coord = target_coord;
        }

        const lx: u4 = @intCast(@as(u64, @bitCast(@divFloor(@mod(c[0], SUBPIXELS_IN_CHUNK), memory.SPAN_SQ))));
        const ly: u4 = @intCast(@as(u64, @bitCast(@divFloor(@mod(c[1], SUBPIXELS_IN_CHUNK), memory.SPAN_SQ))));
        if (cached_chunk.blocks[@as(usize, ly) * SPAN + @as(usize, lx)].isSolid()) return true;
    }
    return false;
}

/// Updates the camera, handling deadzone and gradual panning.
fn updateCamera(logic_speed: f64) void {
    const game = &memory.game;
    game.last_camera_pos = game.camera_pos;

    const x_deadzone = @as(i64, @intFromFloat(CAMERA_DEADZONE_X / game.camera_scale));
    const y_deadzone = @as(i64, @intFromFloat(CAMERA_DEADZONE_Y / game.camera_scale));

    var shift_x: i64 = 0;
    var shift_y: i64 = 0;

    if (game.player_pos[0] < game.camera_pos[0] - x_deadzone) {
        shift_x = game.player_pos[0] - (game.camera_pos[0] - x_deadzone);
    } else if (game.player_pos[0] > game.camera_pos[0] + x_deadzone) {
        shift_x = game.player_pos[0] - (game.camera_pos[0] + x_deadzone);
    }

    if (game.player_pos[1] < game.camera_pos[1] - y_deadzone) {
        shift_y = game.player_pos[1] - (game.camera_pos[1] - y_deadzone);
    } else if (game.player_pos[1] > game.camera_pos[1] + y_deadzone) {
        shift_y = game.player_pos[1] - (game.camera_pos[1] + y_deadzone);
    }

    const smooth_speed = 1.0 - std.math.pow(f64, 1.0 - CAMERA_SMOOTHING, logic_speed);
    game.camera_pos[0] += @intFromFloat(@as(f64, @floatFromInt(shift_x)) * smooth_speed);
    game.camera_pos[1] += @intFromFloat(@as(f64, @floatFromInt(shift_y)) * smooth_speed);
}
