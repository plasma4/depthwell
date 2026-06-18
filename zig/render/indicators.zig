//! Draws visual indicators above certain block types.
const std = @import("std");
const dw = @import("../root.zig");
const memory = dw.memory;

/// Iterates active chunks looking for furnace blocks and overlays contextual UI indicators.
pub fn drawFurnaceIndicators() void {
    @setFloatMode(.optimized);
    const game = &memory.game;
    const player_coord = game.getPlayerCoord();

    // Fetch camera interpolation time fraction
    const dt = dw.chunks.current_dt + 1.0;
    const interpolated_zoom = game.camera_scale * std.math.pow(f64, game.camera_scale_change, dt);

    // Compute interpolated camera positions
    const cam_vel_x = game.camera_pos[0] - game.last_camera_pos[0];
    const cam_vel_y = game.camera_pos[1] - game.last_camera_pos[1];
    const interp_cam_x = @as(f64, @floatFromInt(game.camera_pos[0])) + (@as(f64, @floatFromInt(cam_vel_x)) * dt);
    const interp_cam_y = @as(f64, @floatFromInt(game.camera_pos[1])) + (@as(f64, @floatFromInt(cam_vel_y)) * dt);

    const mouse_pixel_pos = dw.mouse.uv_position * dw.utils.Vec2f{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT };
    var closest_dist = std.math.inf(f64);

    const player_bx = game.getBlockXInChunk();
    const player_by = game.getBlockYInChunk();

    // Scan a local 33x33 block window centered around the player
    var dy: i32 = -16;
    while (dy <= 16) : (dy += 1) {
        var dx: i32 = -16;
        while (dx <= 16) : (dx += 1) {
            const target_bx = @as(i32, player_bx) + dx;
            const target_by = @as(i32, player_by) + dy;

            const chunk_dx = @divFloor(target_bx, 16);
            const chunk_dy = @divFloor(target_by, 16);
            const local_bx: u4 = @intCast(@mod(target_bx, 16));
            const local_by: u4 = @intCast(@mod(target_by, 16));

            const target_coord = player_coord.move(.{ chunk_dx, chunk_dy }) orelse continue;
            const chunk = dw.world.SimBuffer.get(target_coord) orelse continue;
            const block = chunk.getBlock(local_bx, local_by);

            if (block.id == .forest_furnace or block.id == .lava_furnace) {
                // Calculate furnace center subpixels relative to player coordinates
                const block_sub_x = chunk_dx * 4096 + @as(i64, local_bx) * 256 + 128;
                const block_sub_y = chunk_dy * 4096 + @as(i64, local_by) * 256 + 128;

                const dx_sub = block_sub_x - game.player_pos[0];
                const dy_sub = block_sub_y - game.player_pos[1];
                const dist_sq = dx_sub * dx_sub + dy_sub * dy_sub;
                const distance = @sqrt(@as(f64, @floatFromInt(dist_sq)));

                if (distance < closest_dist) {
                    closest_dist = distance;
                }

                const max_dist = 4.0 * 256.0; // Show icon starting 4 blocks away
                const min_dist = 1.5 * 256.0; // Fully scaled at 1.5 blocks

                if (distance < max_dist) {
                    const t = if (distance <= min_dist) 1.0 else (max_dist - distance) / (max_dist - min_dist);

                    // Opacity & scaling metrics
                    const opacity: f32 = @floatCast(t);
                    const slot_size: f32 = @floatCast((10.0 + 5.0 * t) * memory.game.camera_scale);

                    // Position slightly above the physical block (-200 subpixels)
                    const delta_x_sp = @as(f64, @floatFromInt(block_sub_x)) - interp_cam_x;
                    const delta_y_sp = @as(f64, @floatFromInt(block_sub_y - 200)) - interp_cam_y;

                    const screen_x = @as(f32, @floatCast(@as(f64, dw.SCREEN_WIDTH_HALF) + delta_x_sp * (interpolated_zoom / 16.0)));
                    const screen_y = @as(f32, @floatCast(@as(f64, dw.SCREEN_HEIGHT_HALF) + delta_y_sp * (interpolated_zoom / 16.0)));

                    // Handle hovering and cursor pointer transformations
                    const dx_mouse = @as(f32, @floatCast(mouse_pixel_pos[0])) - screen_x;
                    const dy_mouse = @as(f32, @floatCast(mouse_pixel_pos[1])) - screen_y;
                    const hitbox: dw.geometry.Shape = .roundSquare(
                        .{ -slot_size / 2.0, -slot_size / 2.0 },
                        slot_size,
                        0.2,
                    );

                    var active_sprite: dw.Sprite = .inventory;
                    const is_hovering = hitbox.contains(.{ dx_mouse, dy_mouse }) and opacity > 0.2;

                    if (is_hovering) {
                        // Try to claim down click state. Permits upgrading .canvas or .none -> .indicator
                        _ = dw.mouse.tryCaptureDown(.indicator, is_hovering);

                        // Only change mouse appearance if current focus permits UI actions
                        if (dw.mouse.click_focus.permits(.indicator)) {
                            dw.mouse.requestCursorType(.pointer);
                        }

                        // Perform toggle logic safely when click sequence starts and ends on indicator
                        if (dw.mouse.isClicked(.indicator, is_hovering)) {
                            dw.inventory.in_furnace = !dw.inventory.in_furnace;
                        }

                        active_sprite = .inventory_selected;
                    }

                    // Background inventory slot
                    dw.entity.addEntity(.{
                        // sprite override if in menu already
                        .sprite = if (dw.inventory.in_furnace) .inventory_selected_invalid else active_sprite,
                        .position = .{ screen_x, screen_y },
                        .size = slot_size,
                        .lcha = .{ 1.0, 0.0, 0.0, opacity },
                    });

                    // Mini furnace preview centered inside the container slot
                    dw.entity.addEntity(.{
                        .sprite = if (block.id == .forest_furnace) .forest_furnace else .lava_furnace,
                        .position = .{ screen_x, screen_y },
                        .size = slot_size * 0.6,
                        .lcha = .{ 1.0, 0.0, 0.0, opacity },
                    });
                }
            }
        }
    }

    // Player moved away >5 blocks, so autoclose
    if (dw.inventory.in_furnace and closest_dist > 5.0 * 256.0) {
        dw.inventory.in_furnace = false;
    }
}

/// Checks if the mouse is currently hovering over any active furnace indicator.
pub fn isHoveringFurnaceIndicator() bool {
    @setFloatMode(.optimized);
    const game = &memory.game;
    const player_coord = game.getPlayerCoord();

    // Fetch camera interpolation time fraction
    const dt = dw.chunks.current_dt + 1.0;
    const interpolated_zoom = game.camera_scale * std.math.pow(f64, game.camera_scale_change, dt);

    // Compute interpolated camera positions
    const cam_vel_x = game.camera_pos[0] - game.last_camera_pos[0];
    const cam_vel_y = game.camera_pos[1] - game.last_camera_pos[1];
    const interp_cam_x = @as(f64, @floatFromInt(game.camera_pos[0])) + (@as(f64, @floatFromInt(cam_vel_x)) * dt);
    const interp_cam_y = @as(f64, @floatFromInt(game.camera_pos[1])) + (@as(f64, @floatFromInt(cam_vel_y)) * dt);

    const mouse_pixel_pos = dw.mouse.uv_position * dw.utils.Vec2f{ dw.SCREEN_WIDTH, dw.SCREEN_HEIGHT };

    const player_bx = game.getBlockXInChunk();
    const player_by = game.getBlockYInChunk();

    // Scan a local 33x33 block window centered around the player
    var dy: i32 = -16;
    while (dy <= 16) : (dy += 1) {
        var dx: i32 = -16;
        while (dx <= 16) : (dx += 1) {
            const target_bx = @as(i32, player_bx) + dx;
            const target_by = @as(i32, player_by) + dy;

            const chunk_dx = @divFloor(target_bx, 16);
            const chunk_dy = @divFloor(target_by, 16);
            const local_bx: u4 = @intCast(@mod(target_bx, 16));
            const local_by: u4 = @intCast(@mod(target_by, 16));

            const target_coord = player_coord.move(.{ chunk_dx, chunk_dy }) orelse continue;
            const chunk = dw.world.SimBuffer.get(target_coord) orelse continue;
            const block = chunk.getBlock(local_bx, local_by);

            if (block.id == .forest_furnace or block.id == .lava_furnace) {
                const block_sub_x = chunk_dx * 4096 + @as(i64, local_bx) * 256 + 128;
                const block_sub_y = chunk_dy * 4096 + @as(i64, local_by) * 256 + 128;

                const dx_sub = block_sub_x - game.player_pos[0];
                const dy_sub = block_sub_y - game.player_pos[1];
                const dist_sq = dx_sub * dx_sub + dy_sub * dy_sub;
                const distance = @sqrt(@as(f64, @floatFromInt(dist_sq)));

                const max_dist = 4.0 * 256.0;
                const min_dist = 1.5 * 256.0;

                if (distance < max_dist) {
                    const t = if (distance <= min_dist) 1.0 else (max_dist - distance) / (max_dist - min_dist);
                    const opacity: f32 = @floatCast(t);
                    const slot_size: f32 = @floatCast((10.0 + 5.0 * t) * memory.game.camera_scale);

                    const delta_x_sp = @as(f64, @floatFromInt(block_sub_x)) - interp_cam_x;
                    const delta_y_sp = @as(f64, @floatFromInt(block_sub_y - 200)) - interp_cam_y;

                    const screen_x = @as(f32, @floatCast(@as(f64, dw.SCREEN_WIDTH_HALF) + delta_x_sp * (interpolated_zoom / 16.0)));
                    const screen_y = @as(f32, @floatCast(@as(f64, dw.SCREEN_HEIGHT_HALF) + delta_y_sp * (interpolated_zoom / 16.0)));

                    const dx_mouse = @as(f32, @floatCast(mouse_pixel_pos[0])) - screen_x;
                    const dy_mouse = @as(f32, @floatCast(mouse_pixel_pos[1])) - screen_y;
                    const hitbox: dw.geometry.Shape = .roundSquare(
                        .{ -slot_size / 2.0, -slot_size / 2.0 },
                        slot_size,
                        0.2,
                    );

                    if (hitbox.contains(.{ dx_mouse, dy_mouse }) and opacity > 0.2) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}
