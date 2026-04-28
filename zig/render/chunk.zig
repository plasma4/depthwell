const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const logger = root.logger;
const world = root.world;
const SPAN = memory.SPAN;
const SPAN_FLOAT = memory.SPAN_FLOAT;

pub fn updateVisibleChunks(dt: f64, canvas_w: f64, canvas_h: f64) void {
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
    const half_w_sp = (@as(f64, root.SCREEN_WIDTH_HALF) / interpolated_zoom) * SPAN;
    const half_h_sp = (@as(f64, root.SCREEN_HEIGHT_HALF) / interpolated_zoom) * SPAN;

    // calculate the interpolated camera
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
    const max_cx: i32 = @as(i32, @floor(edge_right / subpixels_per_chunk)) + 1;
    const max_cy: i32 = @as(i32, @floor(edge_bottom / subpixels_per_chunk)) + 1;

    // determine the dimensions of the grid to render (cw/ch is how many chunks wide/high the current render-window is)
    const cw: u32 = @intCast(max_cx - min_cx + 1);
    const ch: u32 = @intCast(max_cy - min_cy + 1);

    // how many render tiles on each side?
    const wb = cw * SPAN;
    const hb = ch * SPAN;

    memory.scratchReset(); // scratch allocator always needs to be reset!
    const out = memory.scratchAllocSlice(memory.Block, wb * hb);

    const world_limit: u64 = world.max_possible_suffix;
    const player_coord = game.getPlayerCoord();

    var chunk: memory.Chunk = undefined;
    for (0..ch) |gy| {
        const offset_y: i64 = @as(i64, @intCast(min_cy)) + @as(i64, @intCast(gy));

        for (0..cw) |gx| {
            const offset_x: i64 = @as(i64, @intCast(min_cx)) + @as(i64, @intCast(gx));

            if (player_coord.move(.{ offset_x, offset_y })) |target_coord| {
                if (game.depth <= 16) {
                    if (target_coord.suffix[0] > world_limit or target_coord.suffix[1] > world_limit) {
                        for (0..SPAN) |ly| {
                            const row_start = (gy * SPAN + ly) * wb + gx * SPAN;
                            @memset(out[row_start .. row_start + SPAN], root.sprite.AIR_BLOCK);
                        }
                        continue;
                    }
                }

                world.writeChunk(&chunk, target_coord);
                for (0..SPAN) |ly| {
                    @memcpy(out[(gy * SPAN + ly) * wb + gx * SPAN ..][0..SPAN], chunk.blocks[ly * SPAN ..][0..SPAN]);
                }
            } else {
                for (0..SPAN) |ly| {
                    const row_start = (gy * SPAN + ly) * wb + gx * SPAN;
                    @memset(out[row_start .. row_start + SPAN], root.sprite.AIR_BLOCK);
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
    const cam_x_shader = (interp_cam_x - grid_origin_sub_x) / SPAN_FLOAT;
    const cam_y_shader = (interp_cam_y - grid_origin_sub_y) / SPAN_FLOAT;

    // Find the player's position, interpolated with dt
    const player_vel_x = game.player_pos[0] - game.last_player_pos[0];
    const player_vel_y = game.player_pos[1] - game.last_player_pos[1];
    const player_interpolated_x = @as(f64, @floatFromInt(game.player_pos[0])) + @as(f64, @floatFromInt(player_vel_x)) * dt;
    const player_interpolated_y = @as(f64, @floatFromInt(game.player_pos[1])) + @as(f64, @floatFromInt(player_vel_y)) * dt;

    // Position player in the middle of the screen plus their offset from the camera center
    const player_render_x = (player_interpolated_x - grid_origin_sub_x - SPAN_FLOAT * SPAN_FLOAT / 2) / SPAN_FLOAT;
    const player_render_y = (player_interpolated_y - grid_origin_sub_y - SPAN_FLOAT * SPAN_FLOAT / 2) / SPAN_FLOAT;

    // Update scratch properties that JS reads
    memory.setScratchProp(0, wb);
    memory.setScratchProp(1, hb);
    memory.setScratchProp(2, cam_x_shader);
    memory.setScratchProp(3, cam_y_shader);
    memory.setScratchProp(4, effective_zoom);
    memory.setScratchProp(5, player_render_x);
    memory.setScratchProp(6, player_render_y);

    if (root.is_debug) {
        const qc = world.quad_cache;
        const d = @min(memory.game.depth, 16);
        var suffix_array_x = std.mem.zeroes([16]u4); // or [_]u4{0} ** 16 :)
        var suffix_array_y = std.mem.zeroes([16]u4);
        for (0..d) |i| {
            const shift = @as(u6, @intCast(((d - 1) - i) * 4)); // un-backwards the array
            suffix_array_x[i] = @intCast((game.player_chunk[0] >> shift) & 0xF); // mask from 0-15
            suffix_array_y[i] = @intCast((game.player_chunk[1] >> shift) & 0xF);
        }

        if (game.depth > 16) {
            // logger.write(0, .{
            //     "{h}Top left quadrant X, Y, current quadrant, and active suffix",
            //     qc.left_path,
            //     qc.top_path,
            //     ([_][]const u8{ "top left", "top right", "bottom left", "bottom right" })[game.player_quadrant],
            //     suffix_array_x,
            //     suffix_array_y,
            // });
            logger.writeOnce(2, .{
                "{mh}Left quadrant path",
                qc.left_path,
                "{mh}X suffix array",
                suffix_array_x,
            });
            logger.writeOnce(3, .{
                "{mh}Top quadrant path",
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
                "{mh}Quadrant name",
                quadrant_name,
                "{mh}Number of digits in the current (hypothetical) width of the game world",
                @as(u64, @floor(std.math.log10(16.0) * @as(f64, @floatFromInt(game.depth + 1)))) + 1,
            });
        } else {
            logger.writeOnce(0, .{
                "{h}Chunk active suffix X/Y",
                suffix_array_x[0..d],
                suffix_array_y[0..d],
            });
        }

        logger.write(0, .{
            "{h}Depth/position",
            .{ game.depth, game.player_pos },
        });

        logger.writeOnce(1, .{
            "{h}Velocity",
            game.player_velocity,
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
