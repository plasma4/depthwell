//! CPU lighting pass over the visible block buffer. Writes 0..255 brightness to `Block.light`.
//! WGSL multiplies tile colors by `light / 255`.
//!
//! Uses a non-additive BFS flood-fill algorithm.
//! Spreads to 8 neighbors with a sqrt(2) diagonal cost for an approximated circular falloff.
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
pub const AMBIENT_LIGHT_DEBUG: u8 = 192;

pub var DEBUG_LIGHT = false;

// Light strength values for various sources:
pub const PLAYER_LIGHT: u16 = 340;
pub const CAMPFIRE_LIGHT: u16 = 300;
pub const PLATE_LIGHT: u16 = 140;

// Orthogonal decay rates per block type. Air should always be the lowest (decay slowest)!
pub const AIR_FALLOFF: u16 = 10;
pub const SOLID_FALLOFF: u16 = 48;
pub const LIQUID_FALLOFF: u16 = 18;

/// Simulates the worst-case (straight line, air) light path to find max reach distance in blocks.
fn maxAirReachBlocks() comptime_int {
    comptime {
        var brightest_possible_source: u16 = @max(PLAYER_LIGHT, @max(CAMPFIRE_LIGHT, PLATE_LIGHT));
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
    return comptime @intFromFloat(@round(@as(f64, @floatFromInt(ortho)) * @sqrt(2.0)));
}

inline fn blockEmission(id: Sprite) u16 {
    return switch (id) {
        .campfire => CAMPFIRE_LIGHT,
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
/// Reusable high-precision light calculation buffer (packed: upper 16-bits = non-orange, lower 16-bits = orange).
var light_buffer: std.ArrayList(u32) = .empty;

inline fn packLight(orange: u16, other: u16) u32 {
    return @as(u32, orange) | (@as(u32, other) << 16);
}

inline fn unpackOrange(p: u32) u16 {
    return @as(u16, @intCast(p & 0xFFFF));
}

inline fn unpackOther(p: u32) u16 {
    return @as(u16, @intCast(p >> 16));
}

const ORANGE_MASK: u16 = 0x8000;
const LIGHT_MASK: u16 = 0x7FFF;

/// Returns true if the block is an orange/campfire-type light source, which creates a warm glow in the shader.
inline fn isOrangeSource(id: Sprite) bool {
    return switch (id) {
        .campfire => true,
        else => false,
    };
}

/// Seeds the 2x2 cells surrounding the player using their continuous sub-pixel position.
/// Light drops off similar to Euclidean distance through `stepCost()`.
inline fn seedPlayerLight(out: []const Block, light_slice: []u32, w: i32, h: i32, px: f32, py: f32) void {
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
                    const current_packed = light_slice[i];
                    const current_other = unpackOther(current_packed);
                    if (val > current_other) {
                        const current_orange = unpackOrange(current_packed);
                        light_slice[i] = packLight(current_orange, val);
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

    // Reset buffer to ambient and seed static world emissive blocks with their respective type.
    for (out, 0..) |block, i| {
        const emission = blockEmission(block.id);
        if (emission > ambient) {
            const is_orange = isOrangeSource(block.id);
            if (is_orange) {
                light_slice[i] = packLight(emission, ambient);
            } else {
                light_slice[i] = packLight(ambient, emission);
            }
            queue.append(memory.page_allocator, @intCast(i)) catch memory.oom();
        } else {
            light_slice[i] = packLight(ambient, ambient);
        }
    }

    // Seed continuous player source into the u32 buffer.
    seedPlayerLight(out, light_slice, w, h, player_bx, player_by);

    // BFS flood: Expand to 8 neighbors. Re-enqueue neighbors if a brighter (better) path is found.
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const idx = queue.items[head];
        const packed_light = light_slice[idx];
        const orange_light = unpackOrange(packed_light);
        const other_light = unpackOther(packed_light);
        if (orange_light <= ambient and other_light <= ambient) continue;

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

                const new_orange: u16 = if (orange_light > cost) orange_light - cost else ambient;
                const new_other: u16 = if (other_light > cost) other_light - cost else ambient;

                const neighbor_packed = light_slice[ni];
                const neighbor_orange = unpackOrange(neighbor_packed);
                const neighbor_other = unpackOther(neighbor_packed);

                // Relax both fields simultaneously using branchless max evaluations
                if (new_orange > neighbor_orange or new_other > neighbor_other) {
                    const next_orange = @max(new_orange, neighbor_orange);
                    const next_other = @max(new_other, neighbor_other);
                    light_slice[ni] = packLight(next_orange, next_other);
                    queue.append(memory.page_allocator, @intCast(ni)) catch memory.oom();
                }
            }
        }
    }

    // Write the final high-precision values back to the u8 block buffer clamped to MAX_LIGHT.
    for (out, light_slice) |*block, l| {
        const orange = unpackOrange(l);
        const other = unpackOther(l);
        const max_light = @max(orange, other);
        block.light = @intCast(@min(max_light, @as(u16, MAX_LIGHT)));

        // Block is orange if it receives more orange light than non-orange, or is in the core radius (>= 255)
        const is_orange = (orange >= other) or (orange >= 255);
        block.lighting_color = @intFromBool(is_orange and max_light > ambient);
    }
}
