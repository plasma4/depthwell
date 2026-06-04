const std = @import("std");
const root = @import("../root.zig");
const memory = root.memory;
const logger = root.logger;
const world = root.world;

const HORIZON_DEPTH = memory.HORIZON_DEPTH;
const CHUNK_SIZE = memory.CHUNK_SIZE;
const CHUNK_SIZE_FLOAT = memory.CHUNK_SIZE_FLOAT;

pub var current_dt: f64 = 0.0;

/// Adds visible chunk data to the scratch buffer, as well as properties.
/// This is used in `render.prepareVisibleData()`.
pub fn updateVisibleChunks(dt: f64, canvas_w: f64, canvas_h: f64) void {
    current_dt = dt; // Store current interpolation fraction
    _ = canvas_h;
    const game = &memory.game;
    // calculate effective zoom
    const resolution_scale = canvas_w / @as(f64, root.SCREEN_WIDTH);
    // since interpolated doesn't really influence logic, std.math.pow can be non-deterministic
    // dt allows for super smooth frame interpolation
    const interpolated_zoom = game.camera_scale * std.math.pow(f64, game.camera_scale_change, dt);
    const effective_zoom = interpolated_zoom * resolution_scale;

    // calculate the screen's half-extents in world sub-pixels (as floats to preserve zoom precision)
    const subpixels_per_chunk: f64 = @floatFromInt(memory.SUBPIXELS_IN_CHUNK);
    const half_w_sp = (@as(f64, root.SCREEN_WIDTH_HALF) / interpolated_zoom) * CHUNK_SIZE;
    const half_h_sp = (@as(f64, root.SCREEN_HEIGHT_HALF) / interpolated_zoom) * CHUNK_SIZE;

    // calculate the interpolated camera loc
    const cam_vel_x = game.camera_pos[0] - game.last_camera_pos[0];
    const cam_vel_y = game.camera_pos[1] - game.last_camera_pos[1];

    const interp_cam_x = @as(f64, @floatFromInt(game.camera_pos[0])) + (@as(f64, @floatFromInt(cam_vel_x)) * dt);
    const interp_cam_y = @as(f64, @floatFromInt(game.camera_pos[1])) + (@as(f64, @floatFromInt(cam_vel_y)) * dt);

    // find the world's sub-pixel edges
    const edge_left = interp_cam_x - half_w_sp;
    const edge_top = interp_cam_y - half_h_sp;
    const edge_right = interp_cam_x + half_w_sp;
    const edge_bottom = interp_cam_y + half_h_sp;

    // find the chunk indices that end up covering the screen, with just enough buffer
    const min_cx: i32 = @floor(edge_left / subpixels_per_chunk);
    const min_cy: i32 = @floor(edge_top / subpixels_per_chunk);
    const max_cx = @as(i32, @floor(edge_right / subpixels_per_chunk)) + 1;
    const max_cy = @as(i32, @floor(edge_bottom / subpixels_per_chunk)) + 1;

    // determine the dimensions of the grid to render (cw/ch is how many chunks wide/high the current render-window is)
    const cw: u32 = @intCast(max_cx - min_cx + 1);
    const ch: u32 = @intCast(max_cy - min_cy + 1);

    // how many render tiles on each side?
    const wb = cw * CHUNK_SIZE;
    const hb = ch * CHUNK_SIZE;

    memory.scratchReset(); // scratch allocator always needs to be reset!
    const out = memory.scratchAllocSlice(memory.Block, wb * hb);
    const player_coord = game.getPlayerCoord();

    var chunk: memory.Chunk align(memory.MAIN_ALIGN_BYTES) = undefined;
    for (0..ch) |gy| {
        const offset_y = @as(i64, @intCast(min_cy)) + @as(i64, @intCast(gy));

        for (0..cw) |gx| {
            const offset_x = @as(i64, @intCast(min_cx)) + @as(i64, @intCast(gx));

            if (player_coord.move(.{ offset_x, offset_y })) |target_coord| {
                if (game.depth <= memory.HORIZON_DEPTH) {
                    if (target_coord.suffix[0] > world.max_possible_suffix or target_coord.suffix[1] > world.max_possible_suffix) {
                        for (0..CHUNK_SIZE) |ly| {
                            const row_start = (gy * CHUNK_SIZE + ly) * wb + gx * CHUNK_SIZE;
                            @memset(out[row_start .. row_start + CHUNK_SIZE], root.sprite.AIR_BLOCK);
                        }
                        continue;
                    }
                }

                world.writeChunk(&chunk, target_coord);
                for (0..CHUNK_SIZE) |ly| {
                    const row_start = (gy * CHUNK_SIZE + ly) * wb + gx * CHUNK_SIZE;
                    const chunk_row_start = ly * CHUNK_SIZE;

                    // Iterate through each block in the row instead of doing a blind @memcpy
                    for (0..CHUNK_SIZE) |lx| {
                        var block = chunk.blocks[chunk_row_start + lx];
                        const was_liquid = block.isLiquid();

                        // Check if the block is liquid at the top, replace it with the top sprite instead if so (enum ID + 1)
                        const block_above_flag = root.types.EdgeFlags.getFlagBit(0, -1);
                        if (was_liquid and (block.edge_flags & block_above_flag == 0)) {
                            block.id = @enumFromInt(@intFromEnum(block.id) + 1);
                            // edge flags preserve
                        }

                        if (!block.isFoundation() and !was_liquid) {
                            // since decor aren't foundation/liquid blocks, they don't get edge flags
                            block.edge_flags = 0xFF;
                        }
                        out[row_start + lx] = block;
                    }
                }
            } else {
                for (0..CHUNK_SIZE) |ly| {
                    const row_start = (gy * CHUNK_SIZE + ly) * wb + gx * CHUNK_SIZE;
                    @memset(out[row_start .. row_start + CHUNK_SIZE], root.sprite.AIR_BLOCK);
                }
            }
        }
    }

    updateRenderProperties(game, interp_cam_x, interp_cam_y, wb, hb, min_cx, min_cy, dt, effective_zoom);
}

/// Sets scratch properties containing information to TypeScript for renderFrame.
inline fn updateRenderProperties(
    game: *memory.GameState,
    interp_cam_x: f64,
    interp_cam_y: f64,
    wb: u32,
    hb: u32,
    min_cx: i32,
    min_cy: i32,
    dt: f64,
    effective_zoom: f64,
) void {
    // Calculate the camera position relative to the tile grid origin
    const grid_origin_sub_x = @as(f64, @floatFromInt(min_cx)) * @as(f64, @floatFromInt(memory.SUBPIXELS_IN_CHUNK));
    const grid_origin_sub_y = @as(f64, @floatFromInt(min_cy)) * @as(f64, @floatFromInt(memory.SUBPIXELS_IN_CHUNK));

    // Final camera position (in pixels this time, relative to the grid)
    const cam_x_shader = (interp_cam_x - grid_origin_sub_x) / CHUNK_SIZE_FLOAT;
    const cam_y_shader = (interp_cam_y - grid_origin_sub_y) / CHUNK_SIZE_FLOAT;

    // Find the player's position, interpolated with dt
    const player_vel_x = game.player_pos[0] - game.last_player_pos[0];
    const player_vel_y = game.player_pos[1] - game.last_player_pos[1];
    const player_interpolated_x = @as(f64, @floatFromInt(game.player_pos[0])) + @as(f64, @floatFromInt(player_vel_x)) * dt;
    const player_interpolated_y = @as(f64, @floatFromInt(game.player_pos[1])) + @as(f64, @floatFromInt(player_vel_y)) * dt;

    // Position player in the middle of the screen plus their offset from the camera center
    const player_render_x = (player_interpolated_x - grid_origin_sub_x - CHUNK_SIZE_FLOAT * CHUNK_SIZE_FLOAT / 2) / CHUNK_SIZE_FLOAT;
    const player_render_y = (player_interpolated_y - grid_origin_sub_y - CHUNK_SIZE_FLOAT * CHUNK_SIZE_FLOAT / 2) / CHUNK_SIZE_FLOAT;

    // Modulo every 256 chunks to seamlessly loop the background!
    const player_cx_mod = @as(i64, @intCast(game.player_chunk[0] % 256));
    const player_cy_mod = @as(i64, @intCast(game.player_chunk[1] % 256));
    const abs_grid_cx = @mod(player_cx_mod + min_cx, 256);
    const abs_grid_cy = @mod(player_cy_mod + min_cy, 256);

    const abs_grid_x = @as(f64, @floatFromInt(abs_grid_cx * @as(i32, memory.CHUNK_SIZE)));
    const abs_grid_y = @as(f64, @floatFromInt(abs_grid_cy * @as(i32, memory.CHUNK_SIZE)));

    const abs_cam_x = cam_x_shader + (abs_grid_x * 16.0);
    const abs_cam_y = cam_y_shader + (abs_grid_y * 16.0);

    // Update scratch properties that JS reads
    memory.setScratchProp(0, wb);
    memory.setScratchProp(1, hb);
    memory.setScratchProp(2, cam_x_shader);
    memory.setScratchProp(3, cam_y_shader);
    memory.setScratchProp(4, effective_zoom);
    memory.setScratchProp(5, player_render_x);
    memory.setScratchProp(6, player_render_y);
    memory.setScratchProp(7, abs_grid_x);
    memory.setScratchProp(8, abs_grid_y);
    memory.setScratchProp(9, abs_cam_x);
    memory.setScratchProp(10, abs_cam_y);

    if (root.is_debug) {
        const qc = world.quad_cache;
        const d: usize = @intCast(memory.game.depth);

        const log_limit = @min(d, HORIZON_DEPTH);
        var suffix_array_x: [HORIZON_DEPTH]u64 = undefined;
        var suffix_array_y: [HORIZON_DEPTH]u64 = undefined;

        for (0..log_limit) |i| {
            suffix_array_x[log_limit - 1 - i] = (game.player_chunk[0] >> @intCast(memory.ZOOM_LOG2 * i)) % memory.ZOOM_FACTOR;
            suffix_array_y[log_limit - 1 - i] = (game.player_chunk[1] >> @intCast(memory.ZOOM_LOG2 * i)) % memory.ZOOM_FACTOR;
        }

        if (game.depth > HORIZON_DEPTH) {
            logger.writeOnce(2, .{
                "{mh}Left quadrant path (compacted)",
                qc.left_path,
                "{mh}X suffix array",
                suffix_array_x,
            });
            logger.writeOnce(3, .{
                "{mh}Top quadrant path (compacted)",
                qc.top_path,
                "{mh}Y suffix array",
                suffix_array_y,
            });

            const quadrant_name = ([_][]const u8{
                "top left quadrant (0)",
                "top right quadrant (1)",
                "bottom left quadrant (2)",
                "bottom right quadrant (3)",
            })[game.player_quadrant];
            logger.writeOnce(0, .{
                "{h}Quadrant name",
                quadrant_name,
            });
        } else {
            logger.writeOnce(0, .{
                "{h}Chunk active suffix X/Y",
                suffix_array_x[0..log_limit], // Use log_limit to avoid overflow if d > 32
                suffix_array_y[0..log_limit],
            });
        }

        logger.write(0, .{
            "{h}Depth/position",
            .{ game.depth, game.player_pos },
        });

        logger.writeOnce(1, .{
            "{mh}Velocity",
            game.player_velocity,
            "{mh}Rendered entity count",
            root.entity.entity_count,
        });

        // logger.clear(1);
        // logger.write(1, .{ "{h}Keys held down", game.keys_held_mask });

        // logger.clear(2);
        // logger.write(2, .{ "{h}Player interpolated shader position", @Vector(2, f64){ player_render_x, player_render_y } });
        // logger.write(2, .{ "{h}Camera interpolated shader position", @Vector(2, f64){ cam_x_shader, cam_y_shader } });
        // logger.write(2, .{ "{h}Camera actual location (relative to player)", game.camera_pos });
        // logger.write(2, .{ "{h}Zoom (scaled based on canvas resolution)", effective_zoom });
    }
}
