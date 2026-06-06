//! Handles water logic, updating the physics and edge flags as necessary.
//! Water level goes from 0-15.
const std = @import("std");
const root = @import("../root.zig");
const memory = root.memory;
const types = root.types;
const world = root.world;

const Block = memory.Block;
const Chunk = memory.Chunk;

/// Global bitset of active chunks in the current frame (16x16 chunk grid).
var active_chunks = std.StaticBitSet(256).initEmpty();
var water_updated = std.StaticBitSet(256 * 256).initEmpty();

/// Returns whether a block is empty (air) or a liquid.
inline fn isFlowable(ptr: *Block) bool {
    return ptr.isEmpty() or ptr.isLiquid();
}

/// Helper to get the volume of a block (0 to 15 for water, 0 otherwise).
pub inline fn getVolume(ptr: *Block) u32 {
    if (ptr.id == .water) {
        if (ptr.hp == 0) return 15;
        return @as(u32, ptr.hp);
    }
    return 0;
}

/// Helper to set the volume of a block under the direct scheme.
pub inline fn setVolume(ptr: *Block, vol: u32) void {
    if (vol == 0) {
        ptr.id = .none;
        ptr.hp = 0;
        ptr.edge_flags = 0xFF;
        ptr.waterlogged = 0;
    } else {
        ptr.id = .water;
        ptr.hp = @intCast(@min(vol, 15));
    }
}

/// Helper to set the volume of a block and trigger neighbor flag updates on state transitions.
inline fn setVolumeAt(ptr: *Block, vol: u32, rx: i32, ry: i32) void {
    _ = rx;
    _ = ry;
    if (vol == 0) {
        ptr.id = .none;
        ptr.hp = 0;
        ptr.edge_flags = 0xFF;
        ptr.waterlogged = 0;
    } else {
        ptr.id = .water;
        ptr.hp = @intCast(@min(vol, 15));
    }
}

/// Gets pre-calculated column pressure.
inline fn getPressureCached(
    col_above_local: *const [16][18]u8,
    ptr: *Block,
    bx: i32,
    by: i32,
) u32 {
    if (ptr.id != .water) return 0;
    const vol = getVolume(ptr);
    const col_above = col_above_local[@as(usize, @intCast(by))][@as(usize, @intCast(bx + 1))];
    return vol + col_above;
}

/// Computes volume + height of water column above (formally called hydrostatic pressure).
/// Capped at 15 steps to guarantee O(1) worst-case performance.
fn getPressureLocal(
    curr: ?*Chunk,
    left: ?*Chunk,
    right: ?*Chunk,
    top: ?*Chunk,
    bottom: ?*Chunk,
    rbx: i32,
    by: i32,
) u32 {
    const ptr = getLocalBlockPtr(curr, left, right, top, bottom, rbx, by) orelse return 0;
    if (ptr.id != .water) return 0;
    const vol = getVolume(ptr);

    var col_above: u32 = 0;
    var cy = by - 1;
    while (col_above < 15) {
        const p = getLocalBlockPtr(curr, left, right, top, bottom, rbx, cy) orelse break;
        if (p.id == .water) {
            col_above += 1;
            cy -= 1;
        } else {
            break;
        }
    }
    return vol + col_above;
}

/// Helper to quickly fetch a `Chunk` pointer from `SimBuffer` coordinates.
inline fn getChunkPtr(cx: u4, cy: u4) ?*Chunk {
    const idx = world.SimBuffer.getIndex(cx, cy);
    if (world.SimBuffer.keys[idx] == null) return null;
    return &world.SimBuffer.sim_buffer_ptr[idx];
}

/// Gets pointer to a local block with center and orthogonal chunks.
inline fn getLocalBlockPtr(
    curr: ?*Chunk,
    left: ?*Chunk,
    right: ?*Chunk,
    top: ?*Chunk,
    bottom: ?*Chunk,
    bx: i32,
    by: i32,
) ?*Block {
    if (bx >= 0 and bx < 16 and by >= 0 and by < 16) {
        const c = curr orelse return null;
        return &c.blocks[@as(usize, @intCast((by << 4) | bx))];
    }
    if (bx < 0) {
        if (bx >= -16 and by >= 0 and by < 16) {
            const l = left orelse return null;
            return &l.blocks[@as(usize, @intCast((by << 4) | (bx + 16)))];
        }
    } else if (bx >= 16) {
        if (bx < 32 and by >= 0 and by < 16) {
            const r = right orelse return null;
            return &r.blocks[@as(usize, @intCast((by << 4) | (bx - 16)))];
        }
    } else if (by < 0) {
        if (by >= -16 and bx >= 0 and bx < 16) {
            const t = top orelse return null;
            return &t.blocks[@as(usize, @intCast(((by + 16) << 4) | bx))];
        }
    } else if (by >= 16) {
        if (by < 32 and bx >= 0 and bx < 16) {
            const b = bottom orelse return null;
            return &b.blocks[@as(usize, @intCast(((by - 16) << 4) | bx))];
        }
    }
    return null;
}

/// Recalculates water edge flags and packages neighbor heights using the local cache.
pub fn updateWaterEdgeFlags(x: i32, y: i32) void {
    if (x < 0 or x >= 256 or y < 0 or y >= 256) return;
    const cx = @as(u4, @intCast(@divTrunc(x, 16)));
    const cy = @as(u4, @intCast(@divTrunc(y, 16)));
    const bx = @as(i32, @intCast(@mod(x, 16)));
    const by = @as(i32, @intCast(@mod(y, 16)));

    const curr = getChunkPtr(cx, cy) orelse return;
    const left = if (cx > 0) getChunkPtr(cx - 1, cy) else null;
    const right = if (cx < 15) getChunkPtr(cx + 1, cy) else null;
    const top = if (cy > 0) getChunkPtr(cx, cy - 1) else null;
    const bottom = if (cy < 15) getChunkPtr(cx, cy + 1) else null;

    const ptr = &curr.blocks[@as(usize, @intCast((by << 4) | bx))];
    if (ptr.id != .water) return;

    var flags: u8 = 0;
    inline for (.{ -1, 0, 1 }) |dy| {
        inline for (.{ -1, 0, 1 }) |dx| {
            if (dx == 0 and dy == 0) continue;

            // Resolve the neighbors!
            const nx = bx + dx;
            const ny = by + dy;
            var neighbor: ?*Block = null;
            if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16) {
                neighbor = &curr.blocks[@as(usize, @intCast((ny << 4) | nx))];
            } else if (nx < 0) {
                if (ny >= 0 and ny < 16) {
                    if (left) |l| neighbor = &l.blocks[@as(usize, @intCast((ny << 4) | (nx + 16)))];
                }
            } else if (nx >= 16) {
                if (ny >= 0 and ny < 16) {
                    if (right) |r| neighbor = &r.blocks[@as(usize, @intCast((ny << 4) | (nx - 16)))];
                }
            } else if (ny < 0) {
                if (nx >= 0 and nx < 16) {
                    if (top) |t| neighbor = &t.blocks[@as(usize, @intCast(((ny + 16) << 4) | nx))];
                }
            } else if (ny >= 16) {
                if (nx >= 0 and nx < 16) {
                    if (bottom) |b| neighbor = &b.blocks[@as(usize, @intCast(((ny - 16) << 4) | nx))];
                }
            }

            if (neighbor) |nb| {
                if (nb.isSolid() or nb.isLiquid()) {
                    flags |= types.EdgeFlags.getFlagBit(dx, dy);
                }
            } else {
                flags |= types.EdgeFlags.getFlagBit(dx, dy);
            }
        }
    }
    ptr.edge_flags = flags;

    const ln = if (bx > 0)
        &curr.blocks[@as(usize, @intCast((by << 4) | (bx - 1)))]
    else if (left) |l|
        &l.blocks[@as(usize, @intCast((by << 4) | 15))]
    else
        null;

    const rn = if (bx < 15)
        &curr.blocks[@as(usize, @intCast((by << 4) | (bx + 1)))]
    else if (right) |r|
        &r.blocks[@as(usize, @intCast((by << 4) | 0))]
    else
        null;

    ptr.padding = if (ln) |l| @intCast(getVolume(l)) else 0;
    ptr.waterlogged = if (rn) |r| @intCast(getVolume(r)) else 0;
}

/// Single-pass water flags for whole chunk groups.
fn updateChunkWaterFlags(
    curr: ?*Chunk,
    left: ?*Chunk,
    right: ?*Chunk,
    top: ?*Chunk,
    bottom: ?*Chunk,
    cx: i32,
    cy: i32,
) void {
    _ = cx;
    _ = cy;
    const c = curr orelse return;
    var by: i32 = 0;
    while (by < 16) : (by += 1) {
        var bx: i32 = 0;
        while (bx < 16) : (bx += 1) {
            const ptr = &c.blocks[@as(usize, @intCast((by << 4) | bx))];
            if (ptr.id != .water) continue;

            var flags: u8 = 0;
            inline for (.{ -1, 0, 1 }) |dy| {
                inline for (.{ -1, 0, 1 }) |dx| {
                    if (dx == 0 and dy == 0) continue;

                    const nx = bx + dx;
                    const ny = by + dy;
                    var neighbor: ?*Block = null;
                    if (nx >= 0 and nx < 16 and ny >= 0 and ny < 16) {
                        neighbor = &c.blocks[@as(usize, @intCast((ny << 4) | nx))];
                    } else if (nx < 0) {
                        if (ny >= 0 and ny < 16) {
                            if (left) |l| neighbor = &l.blocks[@as(usize, @intCast((ny << 4) | (nx + 16)))];
                        }
                    } else if (nx >= 16) {
                        if (ny >= 0 and ny < 16) {
                            if (right) |r| neighbor = &r.blocks[@as(usize, @intCast((ny << 4) | (nx - 16)))];
                        }
                    } else if (ny < 0) {
                        if (nx >= 0 and nx < 16) {
                            if (top) |t| neighbor = &t.blocks[@as(usize, @intCast(((ny + 16) << 4) | nx))];
                        }
                    } else if (ny >= 16) {
                        if (nx >= 0 and nx < 16) {
                            if (bottom) |b| neighbor = &b.blocks[@as(usize, @intCast(((ny - 16) << 4) | nx))];
                        }
                    }

                    if (neighbor) |nb| {
                        if (nb.isSolid() or nb.isLiquid()) {
                            flags |= types.EdgeFlags.getFlagBit(dx, dy);
                        }
                    } else {
                        flags |= types.EdgeFlags.getFlagBit(dx, dy);
                    }
                }
            }
            ptr.edge_flags = flags;

            // Pack visual heights (using 0 as empty under the direct scheme)
            const ln = if (bx > 0)
                &c.blocks[@as(usize, @intCast((by << 4) | (bx - 1)))]
            else if (left) |l|
                &l.blocks[@as(usize, @intCast((by << 4) | 15))]
            else
                null;

            const rn = if (bx < 15)
                &c.blocks[@as(usize, @intCast((by << 4) | (bx + 1)))]
            else if (right) |r|
                &r.blocks[@as(usize, @intCast((by << 4) | 0))]
            else
                null;

            ptr.padding = if (ln) |l| @intCast(getVolume(l)) else 0;
            ptr.waterlogged = if (rn) |r| @intCast(getVolume(r)) else 0;
        }
    }
}

/// Recalculates solid neighbor edge flags when water is created or destroyed.
inline fn notifyNeighborEdgeFlags(rx: i32, ry: i32) void {
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            const nx = rx + dx;
            const ny = ry + dy;
            const neighbor = world.getSimBlockPtr(nx, ny);
            if (neighbor) |nb| {
                if (nb.isSolid() and !nb.isLiquid()) {
                    var flags: u8 = 0;
                    var ndy: i32 = -1;
                    while (ndy <= 1) : (ndy += 1) {
                        var ndx: i32 = -1;
                        while (ndx <= 1) : (ndx += 1) {
                            if (ndx == 0 and ndy == 0) continue;
                            const n_nb = world.getSimBlockPtr(nx + ndx, ny + ndy);
                            if (n_nb) |nnb| {
                                if (nnb.isSolid() or nnb.isLiquid()) {
                                    flags |= types.EdgeFlags.getFlagBit(ndx, ndy);
                                }
                            } else {
                                flags |= types.EdgeFlags.getFlagBit(ndx, ndy);
                            }
                        }
                    }
                    nb.edge_flags = flags;
                }
            }
        }
    }
}

/// Runs a single frame of the water simulation for blocks within the `SimBuffer`.
/// This simulation has been (somewhat) optimized and is also mass-conserving.
pub fn tickWater() void {
    const frame = memory.game.frame;

    // Rebuild active chunk map using a flat contiguous block scan
    active_chunks = std.StaticBitSet(256).initEmpty();

    var cy: u4 = 0;
    while (true) : (cy += 1) {
        var cx: u4 = 0;
        while (true) : (cx += 1) {
            const chunk_idx = (@as(usize, cy) << 4) | cx;
            const sim_idx = world.SimBuffer.getIndex(cx, cy);
            if (world.SimBuffer.keys[sim_idx] == null) {
                if (cx == 15) break;
                continue;
            }

            const chunk = &world.SimBuffer.sim_buffer_ptr[sim_idx];
            var chunk_has_water = false;
            for (chunk.blocks) |b| {
                if (b.id == .water or b.waterlogged > 0) {
                    chunk_has_water = true;
                    break;
                }
            }

            if (chunk_has_water) {
                active_chunks.set(chunk_idx);
                // dilate chunk boundaries (so incoming borders are correctly activated)
                if (cx > 0) active_chunks.set(chunk_idx - 1);
                if (cx < 15) active_chunks.set(chunk_idx + 1);
                if (cy > 0) active_chunks.set(chunk_idx - 16);
                if (cy < 15) active_chunks.set(chunk_idx + 16);
            }

            if (cx == 15) break;
        }
        if (cy == 15) break;
    }

    if (active_chunks.count() == 0) return;

    // Run water simulation ONLY on active chunks
    var chunk_y: i32 = 15;
    while (chunk_y >= 0) : (chunk_y -= 1) {
        const left_to_right = (frame % 2 == 0);
        var chunk_x: i32 = 0;
        while (chunk_x < 16) : (chunk_x += 1) {
            const rcx = if (left_to_right) chunk_x else 15 - chunk_x;
            const chunk_idx = (@as(usize, @intCast(chunk_y)) << 4) | @as(usize, @intCast(rcx));

            if (!active_chunks.isSet(chunk_idx)) continue;

            // FIX: Gracefully handle dilated boundaries that fall outside simulated buffer ranges
            const curr = getChunkPtr(@intCast(rcx), @intCast(chunk_y)) orelse continue;
            const left = if (rcx > 0) getChunkPtr(@intCast(rcx - 1), @intCast(chunk_y)) else null;
            const right = if (rcx < 15) getChunkPtr(@intCast(rcx + 1), @intCast(chunk_y)) else null;
            const top = if (chunk_y > 0) getChunkPtr(@intCast(rcx), @intCast(chunk_y - 1)) else null;
            const bottom = if (chunk_y < 15) getChunkPtr(@intCast(rcx), @intCast(chunk_y + 1)) else null;

            // Build high-performance local column-above cache for current chunk and horizontal borders
            var col_above_local: [16][18]u8 = undefined;
            {
                // col_x = -1 (left boundary column)
                {
                    var above_count: u8 = 0;
                    if (left) |l| {
                        var col_y: usize = 0;
                        while (col_y < 16) : (col_y += 1) {
                            col_above_local[col_y][0] = above_count;
                            const p = &l.blocks[(col_y << 4) | 15];
                            if (p.id == .water) {
                                above_count = @min(above_count + 1, 15);
                            } else {
                                above_count = 0;
                            }
                        }
                    } else {
                        var col_y: usize = 0;
                        while (col_y < 16) : (col_y += 1) {
                            col_above_local[col_y][0] = 0;
                        }
                    }
                }

                // col_x from 0 to 15
                var col_x: i32 = 0;
                while (col_x < 16) : (col_x += 1) {
                    const cache_idx: usize = @intCast(col_x + 1);
                    var above_count: u8 = 0;
                    if (top) |t| {
                        var ty: usize = 15;
                        while (ty >= 1 and above_count < 15) : (ty -= 1) {
                            const p = &t.blocks[(ty << 4) | @as(usize, @intCast(col_x))];
                            if (p.id == .water) {
                                above_count += 1;
                            } else {
                                break;
                            }
                        }
                    }

                    var col_y: usize = 0;
                    const c = curr; // guaranteed non-null
                    while (col_y < 16) : (col_y += 1) {
                        col_above_local[col_y][cache_idx] = above_count;
                        const p = &c.blocks[(col_y << 4) | @as(usize, @intCast(col_x))];
                        if (p.id == .water) {
                            above_count = @min(above_count + 1, 15);
                        } else {
                            above_count = 0;
                        }
                    }
                }

                // col_x = 16 (right boundary column)
                {
                    var above_count: u8 = 0;
                    if (right) |r| {
                        var col_y: usize = 0;
                        while (col_y < 16) : (col_y += 1) {
                            col_above_local[col_y][17] = above_count;
                            const p = &r.blocks[(col_y << 4) | 0];
                            if (p.id == .water) {
                                above_count = @min(above_count + 1, 15);
                            } else {
                                above_count = 0;
                            }
                        }
                    } else {
                        var col_y: usize = 0;
                        while (col_y < 16) : (col_y += 1) {
                            col_above_local[col_y][17] = 0;
                        }
                    }
                }
            }

            var by: i32 = 15;
            while (by >= 0) : (by -= 1) {
                var bx: i32 = 0;
                while (bx < 16) : (bx += 1) {
                    const rbx = if (left_to_right) bx else 15 - bx;
                    const rx = rcx * 16 + rbx;
                    const ry = chunk_y * 16 + by;
                    const idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx));

                    if (water_updated.isSet(idx)) continue;

                    const block_ptr = &curr.blocks[@as(usize, @intCast((by << 4) | rbx))];
                    if (block_ptr.id != .water) continue;

                    water_updated.set(idx);

                    var src_vol = getVolume(block_ptr);
                    if (src_vol == 0) continue;

                    // Gravity flow!
                    const down_ptr = if (by < 15)
                        &curr.blocks[@as(usize, @intCast(((by + 1) << 4) | rbx))]
                    else if (bottom) |b|
                        &b.blocks[@as(usize, @intCast(rbx))]
                    else
                        null;

                    if (down_ptr) |dp| {
                        if (isFlowable(dp)) {
                            const dest_vol = getVolume(dp);
                            if (dest_vol < 15) {
                                const available = 15 - dest_vol;
                                const amt = @min(src_vol, available);

                                // Perform direct, solid transfer
                                setVolumeAt(block_ptr, src_vol - amt, rx, ry);
                                setVolumeAt(dp, dest_vol + amt, rx, ry + 1);

                                const down_idx = @as(usize, @intCast(ry + 1)) * 256 + @as(usize, @intCast(rx));
                                water_updated.set(down_idx);

                                src_vol = getVolume(block_ptr);
                                if (src_vol == 0) continue;
                            }
                        }
                    }

                    // Horizontal equalizing flow using hydrostatic math
                    const left_ptr = if (rbx > 0)
                        &curr.blocks[@as(usize, @intCast((by << 4) | (rbx - 1)))]
                    else if (left) |l|
                        &l.blocks[@as(usize, @intCast((by << 4) | 15))]
                    else
                        null;

                    const right_ptr = if (rbx < 15)
                        &curr.blocks[@as(usize, @intCast((by << 4) | (rbx + 1)))]
                    else if (right) |r|
                        &r.blocks[@as(usize, @intCast((by << 4) | 0))]
                    else
                        null;

                    var left_ok = false;
                    var right_ok = false;
                    var left_vol: u32 = 0;
                    var right_vol: u32 = 0;

                    const src_press = getPressureCached(&col_above_local, block_ptr, rbx, by);
                    var left_press: u32 = 0;
                    var right_press: u32 = 0;

                    if (left_ptr) |lp| {
                        if (isFlowable(lp)) {
                            left_press = getPressureCached(&col_above_local, lp, rbx - 1, by);
                            if (left_press < src_press) {
                                left_ok = true;
                                left_vol = getVolume(lp);
                            }
                        }
                    }
                    if (right_ptr) |rp| {
                        if (isFlowable(rp)) {
                            right_press = getPressureCached(&col_above_local, rp, rbx + 1, by);
                            if (right_press < src_press) {
                                right_ok = true;
                                right_vol = getVolume(rp);
                            }
                        }
                    }

                    const diff_left = if (left_ok) src_press - left_press else 0;
                    const diff_right = if (right_ok) src_press - right_press else 0;

                    if (diff_left > 1 or diff_right > 1) {
                        var flow_left = if (diff_left > 1) diff_left / 2 else 0;
                        var flow_right = if (diff_right > 1) diff_right / 2 else 0;

                        const total_flow = flow_left + flow_right;
                        if (total_flow > src_vol - 1) {
                            const scale = @as(f32, @floatFromInt(src_vol - 1)) / @as(f32, @floatFromInt(total_flow));
                            flow_left = @intFromFloat(@as(f32, @floatFromInt(flow_left)) * scale);
                            flow_right = @intFromFloat(@as(f32, @floatFromInt(flow_right)) * scale);
                        }

                        if (left_ok) {
                            const dest_avail = 15 - left_vol;
                            flow_left = @min(flow_left, dest_avail);
                        }
                        if (right_ok) {
                            const dest_avail = 15 - right_vol;
                            flow_right = @min(flow_right, dest_avail);
                        }

                        if (flow_left > 0 or flow_right > 0) {
                            setVolume(block_ptr, src_vol - (flow_left + flow_right));
                            if (flow_left > 0) {
                                setVolume(left_ptr.?, left_vol + flow_left);
                                if (rx > 0) {
                                    const left_idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx - 1));
                                    water_updated.set(left_idx);
                                }
                            }
                            if (flow_right > 0) {
                                setVolume(right_ptr.?, right_vol + flow_right);
                                if (rx < 255) {
                                    const right_idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx + 1));
                                    water_updated.set(right_idx);
                                }
                            }
                            src_vol = getVolume(block_ptr);
                        }
                    }
                }
            }
        }
    }

    // Perform flag and packing updates using fast pointer sweeps
    chunk_y = 0;
    while (true) : (chunk_y += 1) {
        var chunk_x: u4 = 0;
        while (true) : (chunk_x += 1) {
            const chunk_idx = (@as(usize, @intCast(chunk_y)) << 4) | chunk_x;
            if (!active_chunks.isSet(chunk_idx)) {
                if (chunk_x == 15) break;
                continue;
            }

            const curr = getChunkPtr(chunk_x, @intCast(chunk_y));
            const left = if (chunk_x > 0) getChunkPtr(chunk_x - 1, @intCast(chunk_y)) else null;
            const right = if (chunk_x < 15) getChunkPtr(chunk_x + 1, @intCast(chunk_y)) else null;
            const top = if (chunk_y > 0) getChunkPtr(chunk_x, @intCast(chunk_y - 1)) else null;
            const bottom = if (chunk_y < 15) getChunkPtr(chunk_x, @intCast(chunk_y + 1)) else null;

            updateChunkWaterFlags(curr, left, right, top, bottom, @intCast(chunk_x), chunk_y);

            if (chunk_x == 15) break;
        }
        if (chunk_y == 15) break;
    }
}
