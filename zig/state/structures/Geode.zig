//! Geode (ore shell containing yummy gems)
//!     OOOOO
//!   OO  G  OO
//! OO  G GG  OO
//!   OO   G OO
//!     OOOOO
const std = @import("std");
const dw = @import("../../root.zig");
const HashState = dw.seeding.HashState;
const Vec2u = dw.utils.Vec2u;
const Sprite = dw.Sprite;
const structures = @import("../structures.zig");
const Rect = structures.Rect;

pub const spawn_area: u32 = 128;
pub const max_w: u32 = 20;
pub const max_h: u32 = 20;
pub const target_chance: f64 = 0.30;

pub fn getBounds(state: *HashState, cx: i32, cy: i32) Rect {
    const i_area = @as(i32, @intCast(spawn_area));
    const radius = state.getRange(i32, 5, 10);
    const max_pos_x = i_area - (radius * 2);
    const max_pos_y = i_area - (radius * 2);

    const pos_x = @as(i32, @intCast(state.getLimit(u32, @intCast(max_pos_x))));
    const pos_y = @as(i32, @intCast(state.getLimit(u32, @intCast(max_pos_y))));

    const x_start = cx * i_area + pos_x;
    const y_start = cy * i_area + pos_y;
    return .{
        .x_start = x_start,
        .y_start = y_start,
        .x_end = x_start + (radius * 2),
        .y_end = y_start + (radius * 2),
    };
}

pub fn generate(
    starting_sprite: Sprite,
    wx: u32,
    wy: u32,
    cx: i32,
    cy: i32,
    bounds: Rect,
    state: *HashState,
    struct_seed: Vec2u,
) ?Sprite {
    _ = starting_sprite;
    _ = bounds;
    const i_area = @as(i32, @intCast(spawn_area));
    const i_wx = @as(i32, @bitCast(wx));
    const i_wy = @as(i32, @bitCast(wy));

    const radius = state.getRange(i32, 5, 10);
    const core_radius = radius - 2;
    const max_pos_x = i_area - (radius * 2);
    const max_pos_y = i_area - (radius * 2);

    const pos_x = @as(i32, @intCast(state.getLimit(u32, @intCast(max_pos_x))));
    const pos_y = @as(i32, @intCast(state.getLimit(u32, @intCast(max_pos_y))));

    const struct_x = i_wx - (cx * i_area + pos_x);
    const struct_y = i_wy - (cy * i_area + pos_y);

    if (struct_x >= 0 and struct_y >= 0 and struct_x < radius * 2 and struct_y < radius * 2) {
        // Get center of the geode relative to the area
        const center_x = radius;
        const center_y = radius;
        const dx = struct_x - center_x;
        const dy = struct_y - center_y;

        // Determine the shell's block type
        const shell_rand = state.getLimit(u32, 5);
        const shell: Sprite = switch (shell_rand) {
            0, 1 => .pink_stone,
            2, 3 => .purple_stone,
            4 => .redder_stone,
            else => unreachable,
        };

        // Check if within the bounding box of the geode
        const dist_sq = (dx * dx) + (dy * dy);
        if (dist_sq <= core_radius * core_radius) {
            // We are in the core (center area)! Determine whether to use stone or a gem.
            var block_state = structures.makeBlockHash(struct_seed, wx, wy, 3);
            const core_rand = block_state.getLimit(u32, 50);
            const which_stone = state.getLimit(u32, 3);
            return switch (core_rand) {
                0, 1, 2, 3, 4 => .amethyst,
                5, 6, 7, 8 => .sapphire,
                9, 10 => .emerald,
                11 => .ruby,

                // Gems weren't selected: determine a default stone type that's consistent across all blocks in the core
                else => if (dist_sq >= (core_radius - 1) * (core_radius - 1))
                    if (shell == .redder_stone) .stone else ([_]Sprite{ .stone, .alt_blue_stone, .purple_stone })[which_stone]
                else
                    .stone,
            };
        } else if (dist_sq <= radius * radius) {
            return shell;
        }
    }

    return null;
}
