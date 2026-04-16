//! Contains initialization and render update functions. See root.zig for exporting these functions (and others) to WASM.
const builtin = @import("builtin");
const std = @import("std");
const memory = @import("memory.zig");
const logger = @import("logger.zig");
const seeding = @import("seeding.zig");
const world = @import("world.zig");
const player = @import("player.zig");

const SPAN = memory.SPAN;
const SPAN_SQ = memory.SPAN_SQ;
const SPAN_FLOAT = memory.SPAN_FLOAT;
const SUBPIXELS_IN_CHUNK = memory.SUBPIXELS_IN_CHUNK;
const SCREEN_WIDTH = 480;
const SCREEN_HEIGHT = 270;
const SCREEN_WIDTH_HALF = SCREEN_WIDTH / 2;
const SCREEN_HEIGHT_HALF = SCREEN_HEIGHT / 2;

/// Sets the number of times the push_layer function is called at the start. (If set to 3 (default), the game will start off by being 4096x4096 chunks. If set to 1, for example, it will be 1 chunk with 16x16 blocks instead.)
const STARTING_ZOOM_TIMES = 3;
/// Sets the player's spawn randomly (if `STARTING_ZOOM_TIMES` > 0).
const SET_PLAYER_SPAWN_RANDOMLY = true;

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn js_handle_visible_chunks(opacity: f64) void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handle_visible_chunks(opacity: f64) void {
    if (memory.is_wasm) {
        return js_handle_visible_chunks(opacity);
    } else {
        return; // no native impl yet
    }
}

var alreadyStarted = false;

/// Initializes the game.
pub fn init() void {
    if (!alreadyStarted) {
        alreadyStarted = true;
        logger.log(@src(), "Hello from Zig!", .{});
    }
    var temp_seed = seeding.ChaCha12.init(seeding.mix_base_seed(&memory.game.seed, 1));
    memory.game.seed2 = .{
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
    };
    // Start off by determining where the player starts off exactly with layer pushing
    var rng = seeding.ChaCha12.init(seeding.mix_base_seed(&memory.game.seed, 2));
    for (0..STARTING_ZOOM_TIMES) |_| {
        // Set the player position to somewhere random in the current chunk
        if (SET_PLAYER_SPAWN_RANDOMLY) memory.game.set_player_pos(.{
            @intCast(rng.next() & (memory.SUBPIXELS_IN_CHUNK - 1)),
            @intCast(rng.next() & (memory.SUBPIXELS_IN_CHUNK - 1)),
        });

        world.push_layer(
            .none,
            memory.game.get_player_coord(),
            memory.game.get_block_x_in_chunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.get_block_y_in_chunk(),
        );
    }

    if (SET_PLAYER_SPAWN_RANDOMLY) {
        find_safe_spawn();
        // world.SimBuffer.sync(memory.game.get_player_coord(), .{ 16, 16 });
    }
}

/// Searches for a safe grounded spawn point using a spiral pattern.
fn find_safe_spawn() void {
    const game = &memory.game;
    var current_coord = game.get_player_coord();

    // Cache the current chunk pointers to avoid thousands of linear scans
    var cached_chunk = world.get_chunk(current_coord);
    var cached_coord = current_coord;

    var bx: i16 = @intCast(game.get_block_x_in_chunk());
    var by: i16 = @intCast(game.get_block_y_in_chunk());

    var side_len: i32 = 1;
    var dx: i32 = 1;
    var dy: i32 = 0;
    var segment_passed: i32 = 0;

    // up to 1 MILLION checks, in case there's some really odd issue
    for (0..1000000) |_| {
        // Only update chunk pointer if coordinates actually changed
        if (!current_coord.eql(cached_coord)) {
            cached_chunk = world.get_chunk(current_coord);
            cached_coord = current_coord;
        }

        const block = cached_chunk.blocks[@as(usize, @intCast(by)) * SPAN + @as(usize, @intCast(bx))];

        if (block.is_empty()) {
            // Resolve block below. Most likely same chunk, check bx/by first.
            var b_chunk = cached_chunk;
            var bby = by + 1;

            if (bby >= SPAN) {
                if (current_coord.move_y(1)) |nc| {
                    // Check if the below-chunk is different from our current cached one
                    b_chunk = world.get_chunk(nc);
                    bby = 0;
                }
            }

            if (b_chunk.blocks[@as(usize, @intCast(bby)) * SPAN + @as(usize, @intCast(bx))].is_solid()) {
                game.player_quadrant = current_coord.quadrant;
                game.player_chunk = current_coord.suffix;
                game.set_player_pos(.{ @as(i64, bx) * SPAN_SQ + 128, @as(i64, by) * SPAN_SQ + 96 });
                game.set_camera_pos(game.player_pos);
                return;
            }
        }

        bx += @intCast(dx);
        by += @intCast(dy);

        // Chunk-wrapping logic
        if (bx < 0 or bx >= SPAN or by < 0 or by >= SPAN) {
            const shift_x = @divFloor(@as(i32, bx), SPAN);
            const shift_y = @divFloor(@as(i32, by), SPAN);
            if (current_coord.move(.{ shift_x, shift_y })) |nc| {
                current_coord = nc;
                bx = @intCast(@mod(bx, SPAN));
                by = @intCast(@mod(by, SPAN));
            } else segment_passed = side_len;
        }

        segment_passed += 1;
        if (segment_passed >= side_len) {
            segment_passed = 0;
            const temp = dx;
            dx = -dy;
            dy = temp;
            if (dy == 0) side_len += 1;
        }
    }

    // fallback
    game.set_player_pos(.{ 2048, 2048 });
}

/// Processes data for renderFrame in TypeScript.
pub fn prepare_visible_chunks(time_interpolated: f64, canvas_w: f64, canvas_h: f64) void {
    _ = canvas_h;
    const w = world;
    const game = &memory.game;

    // this variable allows for super smooth frame interpolation :)
    const dt = time_interpolated;

    // calculate effective zoom
    const resolution_scale = canvas_w / @as(f64, SCREEN_WIDTH);
    // since interpolated doesn't really influence logic, std.math.pow can be non-deterministic
    const interpolated_zoom = game.camera_scale * std.math.pow(f64, game.camera_scale_change, dt);
    const effective_zoom = interpolated_zoom * resolution_scale;

    // calculate the screen's half-extents in world sub-pixels (as floats to preserve zoom precision)
    const subpixels_per_chunk: f64 = @floatFromInt(SUBPIXELS_IN_CHUNK);
    const half_w_sp = (@as(f64, SCREEN_WIDTH_HALF) / interpolated_zoom) * SPAN;
    const half_h_sp = (@as(f64, SCREEN_HEIGHT_HALF) / interpolated_zoom) * SPAN;

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

    memory.scratch_reset(); // scratch allocator always needs to be reset!
    const out = memory.scratch_alloc_slice(memory.Block, wb * hb) orelse return;

    const world_limit: u64 = world.max_possible_suffix;
    const player_coord = memory.game.get_player_coord();

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
                            @memset(out[row_start .. row_start + SPAN], world.AIR_BLOCK);
                        }
                        continue;
                    }
                }

                w.write_chunk(&chunk, target_coord);
                for (0..SPAN) |ly| {
                    @memcpy(out[(gy * SPAN + ly) * wb + gx * SPAN ..][0..SPAN], chunk.blocks[ly * SPAN ..][0..SPAN]);
                }
            } else {
                for (0..SPAN) |ly| {
                    const row_start = (gy * SPAN + ly) * wb + gx * SPAN;
                    @memset(out[row_start .. row_start + SPAN], world.AIR_BLOCK);
                }
            }
        }
    }

    update_render_properties(game, interp_cam_x, interp_cam_y, wb, hb, min_cx, min_cy, dt, effective_zoom);
    handle_visible_chunks(1.0);
}

/// Sets scratch properties containing information to TypeScript for renderFrame.
inline fn update_render_properties(game: *memory.GameState, interp_cam_x: f64, interp_cam_y: f64, wb: u32, hb: u32, min_cx: i32, min_cy: i32, dt: f64, effective_zoom: f64) void {
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
    memory.set_scratch_prop(0, wb);
    memory.set_scratch_prop(1, hb);
    memory.set_scratch_prop(2, cam_x_shader);
    memory.set_scratch_prop(3, cam_y_shader);
    memory.set_scratch_prop(4, effective_zoom);
    memory.set_scratch_prop(5, player_render_x);
    memory.set_scratch_prop(6, player_render_y);

    if (builtin.mode == .Debug) {
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
            logger.write_once(2, .{
                "{mh}Left quadrant path",
                qc.left_path,
                "{mh}X suffix array",
                suffix_array_x,
            });
            logger.write_once(3, .{
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
            logger.write_once(0, .{
                "{mh}Quadrant name",
                quadrant_name,
                "{mh}Number of digits in the current (hypothetical) width of the game world",
                @as(u64, @floor(std.math.log10(16.0) * @as(f64, @floatFromInt(game.depth + 1)))) + 1,
            });
        } else {
            logger.write_once(0, .{
                "{h}Chunk active suffix X/Y",
                suffix_array_x[0..d],
                suffix_array_y[0..d],
            });
        }

        logger.write_once(1, .{
            "{mh}Velocity",
            game.player_velocity,
            "{mh}Depth/position",
            .{ game.depth, @as(memory.v2f64, @floatFromInt(game.player_pos)) / memory.v2f64{ SPAN_SQ, SPAN_SQ } },
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
pub fn portal_zoom_in(bx: u4, by: u4) void {
    _ = bx;
    _ = by;
    // TODO complete, utilizing `push_layer`
}

/// Resets the game state.
pub fn reset() void {}
