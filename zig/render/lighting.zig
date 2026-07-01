//! CPU lighting pass over the visible block buffer. Writes 0..255 brightness to `Block.light`.
//! WGSL multiplies tile colors by `light / 255`.
//!
//! Uses a non-additive BFS flood-fill algorithm.
//! Spreads to 8 neighbors with a sqrt(2) diagonal cost for circular falloff.
//! Based on the block type (air, solid, or liquid) the decay rate of the liquid can be changed.

const std = @import("std");
const dw = @import("../root.zig");
const memory = dw.memory;

const Block = memory.Block;
const Sprite = dw.Sprite;

/// Max brightness bound by `u8`.
pub const MAX_LIGHT: u8 = 255;
/// Min baseline brightness for unlit cells.
pub const AMBIENT_LIGHT: u8 = 0;
/// Debug ambient light brightness if the debug boolean is enabled.
pub const AMBIENT_LIGHT_DEBUG: u8 = 128;

pub var DEBUG_LIGHT = false;

// Light strength values for various sources:
pub const PLAYER_LIGHT: u16 = 320;
pub const TORCH_LIGHT: u16 = 200;
pub const PLATE_LIGHT: u16 = 120;

// Orthogonal decay rates per block type. Air should always be the lowest!
pub const AIR_FALLOFF: u16 = 10;
pub const SOLID_FALLOFF: u16 = 48;
pub const LIQUID_FALLOFF: u16 = 18;

/// Simulates the worst-case (straight line, air) light path to find max reach distance in blocks.
fn maxAirReachBlocks() comptime_int {
    comptime {
        var brightest_possible_source: u16 = @max(PLAYER_LIGHT, @max(TORCH_LIGHT, PLATE_LIGHT));
        var blocks: comptime_int = 0;
        const light = @min(AMBIENT_LIGHT, AMBIENT_LIGHT_DEBUG);
        while (brightest_possible_source > AIR_FALLOFF and (brightest_possible_source - AIR_FALLOFF) > light) {
            brightest_possible_source -= AIR_FALLOFF;
            blocks += 1;
        }
        return blocks;
    }
}

/// Buffer padding margin (in chunks) to capture off-screen light bleed.
pub const CHUNK_MARGIN: u32 = @max(1, std.math.divCeil(u32, maxAirReachBlocks(), dw.CHUNK_SIZE) catch unreachable);

/// Scales orthogonal falloff to diagonal step! Always evaluated at comptime (only 3 medium types).
inline fn diagFalloff(comptime ortho: u16) u16 {
    return comptime @intFromFloat(@round(@as(f64, @floatFromInt(ortho)) * std.math.sqrt(2.0)));
}

comptime {
    // allow light u16
    // if (PLAYER_LIGHT > MAX_LIGHT or TORCH_LIGHT > MAX_LIGHT or PLATE_LIGHT > MAX_LIGHT) {
    //     @compileError("A light source emits more than MAX_LIGHT.");
    // }
    if (AIR_FALLOFF == 0) @compileError("AIR_FALLOFF must be positive so light has finite range.");
}

inline fn blockEmission(id: Sprite) u16 {
    return switch (id) {
        .torch => TORCH_LIGHT,
        .white_plate => PLATE_LIGHT,
        else => 0,
    };
}

/// Per-step light cost function for entering `block`, handling diagonal scaling.
inline fn stepCost(block: Block, comptime diagonal: bool) u16 {
    if (block.isSolid()) return if (diagonal) diagFalloff(SOLID_FALLOFF) else SOLID_FALLOFF;
    if (block.isLiquid()) return if (diagonal) diagFalloff(LIQUID_FALLOFF) else LIQUID_FALLOFF;
    return if (diagonal) diagFalloff(AIR_FALLOFF) else AIR_FALLOFF;
}

/// Reusable BFS frontier queue.
var queue: std.ArrayList(u32) = .empty;
/// Reusable high-precision light calculation buffer.
var light_buffer: std.ArrayList(u16) = .empty;

/// Seeds the 2x2 cells surrounding the player using their continuous sub-pixel position.
/// Light drops off by Euclidean distance through `stepCost()`.
inline fn seedPlayerLight(out: []const Block, light_slice: []u16, w: i32, h: i32, px: f32, py: f32) void {
    const cx0: i32 = @intFromFloat(@floor(px - 0.5));
    const cy0: i32 = @intFromFloat(@floor(py - 0.5));

    inline for (0..2) |oy| {
        inline for (0..2) |ox| {
            const cx = cx0 + @as(i32, ox);
            const cy = cy0 + @as(i32, oy);
            if (cx >= 0 and cx < w and cy >= 0 and cy < h) {
                const i: usize = @intCast(cy * w + cx);
                const dx = px - (@as(f32, @floatFromInt(cx)) + 0.5);
                const dy = py - (@as(f32, @floatFromInt(cy)) + 0.5);
                // use the cell's own medium rate, not air
                const falloff: f32 = @floatFromInt(stepCost(out[i], false));
                const drop = @round(@sqrt(dx * dx + dy * dy) * falloff);
                if (@as(f32, PLAYER_LIGHT) > drop) {
                    const val: u16 = @intFromFloat(@as(f32, PLAYER_LIGHT) - drop);
                    if (val > light_slice[i]) {
                        light_slice[i] = val;
                        queue.append(memory.page_allocator, @intCast(i)) catch memory.oom();
                    }
                }
            }
        }
    }
}

/// Executes an eight-way breadth-first search relaxation flood over the buffer.
/// Updates light property of the block in-place using continuous player coordinates.
pub fn applyLighting(out: []Block, wb: u32, hb: u32, player_bx: f32, player_by: f32) void {
    const w: i32 = @intCast(wb);
    const h: i32 = @intCast(hb);

    queue.clearRetainingCapacity();
    light_buffer.resize(memory.page_allocator, out.len) catch memory.oom();
    const light_slice = light_buffer.items;

    const ambient = if (dw.is_debug and DEBUG_LIGHT) AMBIENT_LIGHT_DEBUG else AMBIENT_LIGHT;

    // Reset buffer to ambient and seed static world emissive blocks.
    for (out, 0..) |block, i| {
        const emission = blockEmission(block.id);
        if (emission > ambient) {
            light_slice[i] = emission;
            queue.append(memory.page_allocator, @intCast(i)) catch memory.oom();
        } else {
            light_slice[i] = ambient;
        }
    }

    // Seed continuous player source into the u16 buffer.
    seedPlayerLight(out, light_slice, w, h, player_bx, player_by);

    // BFS flood: Expand to 8 neighbors. Re-enqueue neighbors if a brighter (better) path is found.
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const idx = queue.items[head];
        const light = light_slice[idx];
        if (light <= ambient) continue;

        const cx: i32 = @intCast(idx % wb);
        const cy: i32 = @intCast(idx / wb);

        inline for ([_][2]i32{
            .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 },
            .{ -1, 0 },  .{ 1, 0 },  .{ -1, 1 },
            .{ 0, 1 },   .{ 1, 1 },
        }) |d| {
            const nx = cx + d[0];
            const ny = cy + d[1];
            if (nx >= 0 and nx < w and ny >= 0 and ny < h) {
                const ni: usize = @intCast(ny * w + nx);
                const diagonal = d[0] != 0 and d[1] != 0;
                const cost = stepCost(out[ni], diagonal);

                const new_light: u16 = if (light > cost) light - cost else ambient;
                if (new_light > light_slice[ni]) {
                    light_slice[ni] = new_light;
                    queue.append(memory.page_allocator, @intCast(ni)) catch memory.oom();
                }
            }
        }
    }

    // Write the final high-precision values back to the u8 block buffer clamped to MAX_LIGHT.
    for (out, light_slice) |*block, l| {
        block.light = @intCast(@min(l, @as(u16, MAX_LIGHT)));
    }
}
