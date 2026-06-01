//! Handles entities and stores functions relating on how to add them.
const std = @import("std");
const root = @import("../root.zig");
const SegmentedList = root.SegmentedList;
const memory = root.memory;
const sprite = root.sprite;
const ColorRGBA = root.ColorRGBA;
const inventory = root.inventory;

const CHUNK_SIZE = memory.CHUNK_SIZE;
const EdgeFlags = root.types.EdgeFlags;
const Entity = memory.Entity;
const WGSLEntity = memory.WGSLEntity;
const Vec2f32 = memory.Vec2f32;

/// Scale of tiles in the small chunk preview.
pub var preview_tile_size: f64 = 0.0;

/// Extra spacing between number characters.
const spacing = 0.25;
/// Pre-calculated widths of every number sprite from 0 to 9.
const number_widths: [10]f32 = .{
    0.5625 + spacing,
    0.375 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.75 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
    0.5625 + spacing,
};

// not needed: entities are generated directly in the scratch alloc
// /// Array of entities.
// pub var entities: SegmentedList(WGSLEntity, 1024) = .{}; // easiest to do prealloc with larger stack size in case

/// Special variable so that `scratch_alloc_type` adds entities compactly.
var entity_byte_count_before_end: usize = 0;

/// Current number of entities (reset every frame).
pub var entity_count: u64 = 0;

/// Updates all entities by adding them to the scratch buffer. Does not actually inform JS by calling `handleVisibleEntities()`.
/// Every entity needs a position, size, rotation, LCHA, and sprite associated with it.
/// Some properties are optional with defaults (size, rotation, LCHA).
pub fn updateEntities(time_diff: f64) void {
    memory.scratchReset();
    entity_count = 0;
    entity_byte_count_before_end = 0;

    inventory.addDroppedItemsAsEntities(time_diff); // delta time in ms

    if (root.is_debug and preview_tile_size > 0.0) {
        // draw a rectangle background for preview, and then the chunk inside!
        const tile_size: f32 = @floatCast(preview_tile_size);
        const preview_x_origin: f32 = 30.0;
        const preview_y_origin: f32 = 50.0;
        const background_margin: f32 = 1.0;
        var bg: Entity = .{
            .sprite = .particle,
            .position = .{
                preview_x_origin + tile_size * CHUNK_SIZE / 2 - tile_size / 2,
                preview_y_origin + tile_size * CHUNK_SIZE / 2 - tile_size / 2,
            },
            .size = tile_size * (background_margin + CHUNK_SIZE + 2.0),
            .lcha = .{ 1.0, 0.5, 1.2, 0.6 }, // translucent orange!
        };
        addEntity(bg);
        bg.size *= 1.01; // a tad larger!
        bg.lcha = .{ 1.0, 0.5, 2.3, 0.6 }; // yellower
        addEntity(bg);

        const player_coord = memory.game.getPlayerCoord();
        const chunk = root.world.getChunk(player_coord);
        const depth = memory.game.depth;

        // Fetch neighbor chunks for border flag visualization
        const neighbors = blk: {
            var n: [8]?root.memory.Chunk = @splat(null);
            const offsets = [8]root.memory.Vec2i{
                .{ 0, -1 }, .{ 0, 1 }, .{ -1, 0 }, .{ 1, 0 }, // N, S, W, E
                .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 }, // NW, NE, SW, SE
            };
            for (offsets, 0..) |off, i| {
                if (player_coord.moveAtDepth(off, depth)) |nc| {
                    n[i] = root.world.getChunk(nc);
                }
            }
            break :blk n;
        };

        const thick = tile_size * 0.08;
        const line_len = tile_size;
        const diag_size = tile_size * 0.2;
        const half = tile_size * 0.5;

        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |x| {
                const block = chunk.getBlock(@intCast(x), @intCast(y));
                const block_pos: Vec2f32 = .{
                    preview_x_origin + @as(f32, @floatFromInt(x)) * tile_size,
                    preview_y_origin + @as(f32, @floatFromInt(y)) * tile_size,
                };

                // Draw base block
                if (block.isHeatmap()) {
                    addEntity(.{
                        .sprite = .rectangle,
                        .position = block_pos,
                        .size = tile_size,
                        .lcha = .{
                            (@as(f32, @intFromEnum(block.id)) - 65000.0) / 256.0,
                            0.0,
                            0.0,
                            1.0,
                        },
                    });
                } else {
                    addEntity(.{
                        .sprite = block.id,
                        .position = block_pos,
                        .size = tile_size,
                    });
                }

                if (block.isFoundation()) {
                    const edge_flags = block.edge_flags;

                    // first handle non-diagonal directions
                    for ([4]u8{ 1, 6, 3, 4 }) |bit| {
                        if ((edge_flags & (@as(u8, 1) << @intCast(bit))) == 0) {
                            var ent: Entity = .{ .sprite = .rectangle, .position = block_pos };
                            switch (bit) {
                                1 => { // N
                                    ent.position[1] -= half - thick * 0.5;
                                    ent.size = line_len;
                                    ent.lcha = .{ 0.8, 0.35, 0.4, 1.0 };
                                    addEntityLine(ent, line_len, thick);
                                },
                                6 => { // S
                                    ent.position[1] += half - thick * 0.5;
                                    ent.lcha = .{ 0.8, 0.35, 4.2, 1.0 };
                                    addEntityLine(ent, line_len, thick);
                                },
                                3 => { // W
                                    ent.position[0] -= half - thick * 0.5;
                                    ent.lcha = .{ 0.8, 0.35, 0.4, 1.0 };
                                    addEntityLine(ent, thick, line_len);
                                },
                                4 => { // E
                                    ent.position[0] += half - thick * 0.5;
                                    ent.lcha = .{ 0.8, 0.35, 4.2, 1.0 };
                                    addEntityLine(ent, thick, line_len);
                                },
                                else => unreachable,
                            }
                        }
                    }

                    // process diagonals!
                    for ([4]u8{ 0, 2, 5, 7 }) |bit| {
                        if ((edge_flags & (@as(u8, 1) << @intCast(bit))) == 0) {
                            const dx = if (bit == 0 or bit == 5) -half + diag_size * 0.5 else half - diag_size * 0.5;
                            const dy = if (bit == 0 or bit == 2) -half + diag_size * 0.5 else half - diag_size * 0.5;
                            const c_idx =
                                if (bit == 0) @as(usize, 0) else if (bit == 2) @as(usize, 1) else if (bit == 5) @as(usize, 2) else @as(usize, 3);
                            addEntity(.{
                                .sprite = .rectangle,
                                .position = block_pos + Vec2f32{ dx, dy },
                                .size = diag_size,
                                // different purples/pinks
                                .lcha = .{
                                    0.4 + 0.2 * @as(f32, @floatFromInt(c_idx)),
                                    0.3,
                                    5.4,
                                    1.0,
                                },
                            });
                        }
                    }
                }

                // neighbor boundary flag injection (visualize flags pointing INTO the chunk)
                if (x == 0) if (neighbors[2]) |n| drawNeighborFlag(
                    &entity_byte_count_before_end,
                    &entity_count,
                    n.getBlock(15, @intCast(y)),
                    block_pos,
                    .W,
                    tile_size,
                    thick,
                );
                if (x == 15) if (neighbors[3]) |n| drawNeighborFlag(
                    &entity_byte_count_before_end,
                    &entity_count,
                    n.getBlock(0, @intCast(y)),
                    block_pos,
                    .E,
                    tile_size,
                    thick,
                );
                if (y == 0) if (neighbors[0]) |n| drawNeighborFlag(
                    &entity_byte_count_before_end,
                    &entity_count,
                    n.getBlock(@intCast(x), 15),
                    block_pos,
                    .N,
                    tile_size,
                    thick,
                );
                if (y == 15) if (neighbors[1]) |n| drawNeighborFlag(
                    &entity_byte_count_before_end,
                    &entity_count,
                    n.getBlock(@intCast(x), 0),
                    block_pos,
                    .S,
                    tile_size,
                    thick,
                );
            }
        }

        // Draw D-1 and D-2 previews to the right
        const start_zoom = root.startup.STARTING_ZOOM_TIMES;
        const bx_idx = memory.game.getBlockXInChunk();
        const by_idx = memory.game.getBlockYInChunk();
        const deeper_preview_x = preview_x_origin + background_margin + 18.5 * tile_size;
        if (!root.procedural.USE_BASE_HEATMAP and !root.procedural.USE_ORE_HEATMAP and depth > start_zoom) {
            bg.position[0] = deeper_preview_x + tile_size * 2.5;
            bg.position[1] = preview_y_origin + tile_size * 2.5;
            bg.size = tile_size * (6.0 + background_margin);
            bg.sprite = .rectangle;
            addEntity(bg); // box for D-1

            const neighborhood_d1 = root.ancestor.getAncestorNeighborhood(player_coord.asDepthCoordinate(depth));

            for (0..6) |py| {
                for (0..6) |px| {
                    addEntity(.{
                        .sprite = neighborhood_d1[py][px].id,
                        .position = .{
                            deeper_preview_x + @as(f32, @floatFromInt(px)) * tile_size,
                            preview_y_origin + @as(f32, @floatFromInt(py)) * tile_size,
                        },
                        .size = tile_size,
                        .lcha = if (px == 0 or px == 5 or py == 0 or py == 5)
                            .{ 0.6, 0.0, 0.0, 1.0 }
                        else
                            memory.DEFAULT_ENTITY_LCHA,
                    });
                }
            }

            // Render approximate player indicator in D-1
            const p_sub_x = @as(f32, @floatFromInt(bx_idx % 4)) / 4.0;
            const p_sub_y = @as(f32, @floatFromInt(by_idx % 4)) / 4.0;
            const player_entity: Entity = .{
                .sprite = .player,
                .position = .{
                    deeper_preview_x + (1.0 + @as(f32, @floatFromInt(bx_idx / 4)) + p_sub_x - 0.5) * tile_size,
                    preview_y_origin + (1.0 + @as(f32, @floatFromInt(by_idx / 4)) + p_sub_y - 0.5) * tile_size,
                },
                .size = tile_size * 0.8,
                .lcha = .{ 1.0, 0.1, -0.2, 1.0 },
            };
            var player_entity_bg = player_entity;

            // make a sort of larger border/shadow
            player_entity_bg.lcha[0] *= 0.6;
            player_entity_bg.position -= .{ tile_size / 8.0, tile_size / 8.0 };
            addEntity(player_entity_bg);
            addEntity(player_entity);

            if (depth > start_zoom + 1) {
                const p_info = root.ancestor.getParentInfo(
                    player_coord.asDepthCoordinate(depth),
                    bx_idx,
                    by_idx,
                );
                const preview_y_d2 = preview_y_origin + 7.5 * tile_size;
                const gp_info = root.ancestor.getParentInfo(
                    p_info.coord.asDepthCoordinate(depth - 1),
                    p_info.bx,
                    p_info.by,
                );

                bg.position = .{ deeper_preview_x + tile_size * 1.0, preview_y_d2 + tile_size * 1.0 };
                bg.size = tile_size * (3.0 + background_margin);
                addEntity(bg);

                var gpy: i32 = -1;
                while (gpy <= 1) : (gpy += 1) {
                    var gpx: i32 = -1;
                    while (gpx <= 1) : (gpx += 1) {
                        const target_bx = @as(i32, gp_info.bx) + gpx;
                        const target_by = @as(i32, gp_info.by) + gpy;

                        const target_nc = gp_info.coord.moveAtDepth(
                            .{ @divFloor(target_bx, 16), @divFloor(target_by, 16) },
                            depth - 2,
                        ) orelse continue;

                        // truncate it to prevent crashes!
                        const lx: u4 = @truncate(@as(u32, @bitCast(target_bx)));
                        const ly: u4 = @truncate(@as(u32, @bitCast(target_by)));

                        addEntity(.{
                            .sprite = root.world.getBlockAt(target_nc, lx, ly, depth - 2).id,
                            .position = .{
                                deeper_preview_x + @as(f32, @floatFromInt(gpx + 1)) * tile_size,
                                preview_y_d2 + @as(f32, @floatFromInt(gpy + 1)) * tile_size,
                            },
                            .size = tile_size,
                            .lcha = if (gpx == 0 and gpy == 0) memory.DEFAULT_ENTITY_LCHA else .{ 0.7, 0.0, 0.0, 1.0 },
                        });
                    }
                }

                // player indicator (poor guy is stuck in-place, since that's the current chunk)
                addEntity(.{
                    .sprite = .player,
                    .position = .{ deeper_preview_x + 1.0 * tile_size, preview_y_d2 + 1.0 * tile_size },
                    .size = tile_size * 0.8,
                    .lcha = .{ 1.0, 0.1, 0.0, 0.7 },
                });
            }
        }

        if (depth >= memory.HORIZON_DEPTH + start_zoom) {
            const preview_y_ancestor = preview_y_origin + 12.0 * tile_size; // Put it below D-2

            bg.position = .{ deeper_preview_x + tile_size * 1.5, preview_y_ancestor + tile_size * 1.5 };
            bg.size = tile_size * (4.0 + background_margin);
            bg.lcha = .{ 0.8, 0.2, 0.4, 1.0 };
            addEntity(bg);

            for (0..4) |y| {
                for (0..4) |x| {
                    addEntity(.{
                        .sprite = root.world.quad_cache.ancestor_materials[y][x].id,
                        .position = .{
                            deeper_preview_x + @as(f32, @floatFromInt(x)) * tile_size,
                            preview_y_ancestor + @as(f32, @floatFromInt(y)) * tile_size,
                        },
                        .size = tile_size,
                    });
                }
            }

            // Render approximate player indicator in the active quadrant
            const qx = memory.game.player_quadrant % 2;
            const qy = memory.game.player_quadrant / 2;
            addEntity(.{
                .sprite = .player,
                .position = .{
                    deeper_preview_x + @as(f32, @floatFromInt(qx + 1)) * tile_size,
                    preview_y_ancestor + @as(f32, @floatFromInt(qy + 1)) * tile_size,
                },
                .size = tile_size * 0.8,
                .lcha = .{ 1.0, 0.1, 0.0, 0.7 },
            });
        }

        // render the player now!
        const center_offset: memory.Vec2i = @splat(memory.CHUNK_SIZE_SQ / 2);
        const relative_pos = memory.game.player_pos - center_offset;

        const scale = tile_size / memory.CHUNK_SIZE_SQ;
        const origin = Vec2f32{ preview_x_origin, preview_y_origin };

        const player_entity: Entity = .{
            .sprite = .player,
            .position = origin + @as(Vec2f32, @floatFromInt(relative_pos)) * @as(Vec2f32, @splat(scale)),
            .size = tile_size,
        };
        var player_entity_bg = player_entity;

        player_entity_bg.position -= .{ tile_size / 8.0, tile_size / 8.0 };
        player_entity_bg.lcha = .{ 0.5, 0.0, 0.0, 0.8 };
        addEntity(player_entity_bg);
        addEntity(player_entity);
    }

    root.mouse.mouse_type = .initial;
    inventory.drawInventory(time_diff);
    root.render.dispatchMouseType();
    root.mouse.just_mouse_down = false;

    // draw selected HP (for testing)
    const progress = root.mining.selected_hp;
    const pos: Vec2f32 = .{ 10, 28 };
    const font_size = 10.0;

    if (progress != 255 and progress != 0) {
        const value_hue = 0.2 + @as(f32, @floatFromInt(progress)) * (std.math.pi / 8.0);
        // draw shadow of text
        drawNumber(progress, pos - Vec2f32{ 1.5, 1.5 }, .{
            .lcha = .{
                0.5, // darken
                0.4,
                value_hue, // hue changing as progress increases!
                0.8,
            },
            .font_size = font_size,
            .ltr = false,
        });

        // draw the actual number now
        drawNumber(progress, pos, .{
            .lcha = .{
                0.75,
                0.4,
                value_hue, // hue changing too
                1.0,
            },
            .font_size = font_size,
            .ltr = false,
        });
    }

    memory.setScratchProp(0, entity_count);
    // entities are cleared in the render code afterward
}

fn addEntityLine(entity: Entity, w: f32, h: f32) void {
    entity_count += 1;
    const wgsl_entity = memory.scratchAllocType(WGSLEntity, &entity_byte_count_before_end);
    wgsl_entity.* = .{
        .lcha = entity.lcha,
        .position = entity.position / Vec2f32{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT },
        .size = Vec2f32{ w / root.SCREEN_WIDTH, h / root.SCREEN_HEIGHT },
        .rotation = entity.rotation,
        .id = @intFromEnum(entity.sprite),
    };
}

fn drawNeighborFlag(ebc: *usize, ec: *u64, neighbor_block: root.memory.Block, pos: Vec2f32, side: enum { N, S, E, W }, pts: f32, thick: f32) void {
    if (!neighbor_block.isFoundation()) return;
    const half = pts * 0.5;
    // check the flag of the neighbor that points TOWARDS our chunk
    const target_bit: u8 = switch (side) {
        .N => EdgeFlags.BOTTOM, // Neighbor's South flag
        .S => EdgeFlags.TOP, // Neighbor's North flag
        .W => EdgeFlags.RIGHT, // Neighbor's East flag
        .E => EdgeFlags.LEFT, // Neighbor's West flag
    };
    if ((neighbor_block.edge_flags & target_bit) == 0) {
        ec.* += 1;
        const wgsl = memory.scratchAllocType(WGSLEntity, ebc);
        var f_pos = pos;
        var size: Vec2f32 = undefined;
        switch (side) {
            .N => {
                f_pos[1] -= half + thick * 0.5;
                size = .{ pts, thick };
            },
            .S => {
                f_pos[1] += half + thick * 0.5;
                size = .{ pts, thick };
            },
            .W => {
                f_pos[0] -= half + thick * 0.5;
                size = .{ thick, pts };
            },
            .E => {
                f_pos[0] += half + thick * 0.5;
                size = .{ thick, pts };
            },
        }
        wgsl.* = .{
            .lcha = .{ 1.0, 0.0, 0.0, 1.0 }, // Bright white/red for neighbor alerts
            .position = f_pos / Vec2f32{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT },
            .size = size / Vec2f32{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT },
            .rotation = 0,
            .id = @intFromEnum(root.Sprite.rectangle),
        };
    }
}

/// Configuration for drawing a number.
pub const TextConfig = struct {
    /// The light, chroma, hue, and opacity components (HSL + alpha).
    /// L (lightness) and alpha components are multiplied by the sprite's color in WebGPU.
    /// H (hue, in radians) and C (chroma) are shifted additively.
    lcha: @Vector(4, f32) = memory.DEFAULT_ENTITY_LCHA,
    /// The font size of the text.
    font_size: f32 = 16.0,
    /// The rotation of the text.
    rotation: f32 = 0.0,
    /// Whether text is rendered from left-to-right (defaults to true; as in, left-aligned text).
    ltr: bool = true,
};

/// Draws an unsigned integer by creating entities; should NEVER be called outside of `updateEntities()`.
pub fn drawNumber(
    number: u64,
    position: Vec2f32,
    options: TextConfig,
) void {
    const lcha = options.lcha;
    const font_size = options.font_size;
    const rotation = options.rotation;
    const ltr = options.ltr;

    // Fast path for zero-rotation cases
    if (rotation == 0.0) {
        drawNumberFast(number, position, options);
        return;
    }

    if (number == 0) {
        addEntity(.{
            .sprite = @enumFromInt(sprite.NUMBER_START),
            .lcha = lcha,
            .position = position,
            .size = font_size,
            .rotation = rotation,
        });
        return;
    }

    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var n = number;

    while (n > 0) : (n /= 10) {
        digits[count] = @intCast(n % 10);
        count += 1;
    }

    // Precompute trig for the entire string
    const cos_r = @cos(rotation);
    const sin_r = @sin(rotation);

    // Track the relative X offset from the pivot point
    var rel_x: f32 = 0.0;

    if (ltr) {
        // Initial shift for LTR logic
        rel_x -= number_widths[@intCast(digits[count - 1])] * font_size;

        var i: usize = count;
        while (i > 0) {
            i -= 1;
            const digit = digits[i];
            rel_x += number_widths[@intCast(digit)] * font_size;

            // Rotate the relative offset vector (rel_x, 0)
            const rotated_offset = Vec2f32{ rel_x * cos_r, rel_x * sin_r };

            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = position + rotated_offset,
                .size = font_size,
                .rotation = rotation,
            });
        }
    } else {
        for (digits[0..count]) |digit| {
            const rotated_offset = Vec2f32{ rel_x * cos_r, rel_x * sin_r };

            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = position + rotated_offset,
                .size = font_size,
                .rotation = rotation,
            });
            rel_x -= number_widths[@intCast(digit)] * font_size;
        }
    }
}

/// Optimized version of draw_number for when rotation is exactly 0.
fn drawNumberFast(number: u64, position: Vec2f32, options: TextConfig) void {
    std.debug.assert(options.rotation == 0);
    const lcha = options.lcha;
    const font_size = options.font_size;
    const ltr = options.ltr;

    if (number == 0) {
        addEntity(.{
            .sprite = @enumFromInt(sprite.NUMBER_START),
            .lcha = lcha,
            .position = position,
            .size = font_size,
        });
        return;
    }

    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var n = number;

    while (n > 0) : (n /= 10) {
        digits[count] = @intCast(n % 10);
        count += 1;
    }

    var current_pos = position;

    if (ltr) {
        current_pos[0] -= number_widths[@intCast(digits[count - 1])] * font_size;
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            const digit = digits[i];
            current_pos[0] += number_widths[@intCast(digit)] * font_size;

            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = current_pos,
                .size = font_size,
            });
        }
    } else {
        for (digits[0..count]) |digit| {
            addEntity(.{
                .sprite = @enumFromInt(sprite.NUMBER_START + digit),
                .lcha = lcha,
                .position = current_pos,
                .size = font_size,
            });
            current_pos[0] -= number_widths[@intCast(digit)] * font_size;
        }
    }
}

/// Adds a single entity to the `entities` array by adding a UV-based `WGSLEntity` to the scratch buffer.
/// No-op if the sprite type is `none`.
/// Adds a single entity to the `entities` array by adding a UV-based `WGSLEntity` to the scratch buffer.
/// No-op if the sprite type is `none`.
pub inline fn addEntity(entity: Entity) void {
    const id = @intFromEnum(entity.sprite);
    if (entity.sprite.isEmpty()) return;
    if (entity.size <= 0.0) return;
    if (entity.lcha[3] <= 0.0) return;

    // Viewport-based culling (accounting for rotation)
    const half_diagonal = if (entity.rotation == 0.0) entity.size * 0.5 else entity.size * (1.0 / std.math.sqrt(2.0));
    const min_x = entity.position[0] - half_diagonal;
    const max_x = entity.position[0] + half_diagonal;
    const min_y = entity.position[1] - half_diagonal;
    const max_y = entity.position[1] + half_diagonal;

    if (max_x < 0.0 or min_x > root.SCREEN_WIDTH or max_y < 0.0 or min_y > root.SCREEN_HEIGHT) {
        return;
    }

    entity_count += 1;
    const wgsl_entity = memory.scratchAllocType(WGSLEntity, &entity_byte_count_before_end);
    wgsl_entity.* = .{
        .lcha = entity.lcha,
        .position = entity.position /
            Vec2f32{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT },
        .size = Vec2f32{
            entity.size / root.SCREEN_WIDTH,
            entity.size / root.SCREEN_HEIGHT,
        },
        .rotation = entity.rotation,
        .id = if (id >= sprite.GEM_START and id < sprite.GEM_START + sprite.GEM_COUNT) id + sprite.GEM_COUNT else id,
    };
    // root.logger.quick(.{ "{h}Entity ID", (@intFromPtr(wgsl_entity) - memory.mem.scratch_ptr) / @sizeOf(WGSLEntity) });
}
