//! Handles water logic, updating the physics and edge flags as necessary.
//! Water level goes from 0-15.
const std = @import("std");
const dw = @import("../root.zig");
const memory = dw.memory;
const types = dw.types;
const world = dw.world;

const SimBuffer = world.SimBuffer;
const Sprite = dw.Sprite;
const Block = memory.Block;
const Chunk = memory.Chunk;

/// Global bitset of active chunks in the current frame (16x16 chunk grid).
var active_chunks: std.StaticBitSet(256) = undefined;
var water_updated: std.StaticBitSet(256 * 256) = undefined;
/// Bitset keeping track of which active chunks actually had water flow changes.
var chunks_to_update_flags: std.StaticBitSet(256) = undefined;

/// Helper to get the volume of a block (0 to 15 for water/waterlogged blocks, 0 otherwise).
pub inline fn getVolume(ptr: Block) u4 {
    if (ptr.id == .water) {
        return ptr.hp;
    }
    if (ptr.isDecor()) {
        return ptr.hp;
    }
    return 0;
}

/// Helper to set the volume (`hp`) of a block, modifying other properties as needed.
pub inline fn setVolume(ptr: *Block, vol: u32) void {
    const capped: u4 = @intCast(@min(vol, 15));
    if (vol == 0) {
        if (ptr.isDecor()) {
            ptr.hp = 0;
        } else {
            ptr.id = .none;
            ptr.hp = 0;
            ptr.edge_flags = 0xFF;
            ptr.waterlogged = 0;
        }
    } else {
        if (ptr.isDecor()) {
            ptr.hp = capped;
        } else {
            ptr.id = .water;
            ptr.hp = capped;
        }
    }
}

/// Helper to set the volume (`hp`) of a block, modifying other properties as needed.
inline fn setVolumeSticky(rx: i32, ry: i32, vol: u32) void {
    const cx: u4 = @intCast(@divTrunc(rx, 16));
    const cy: u4 = @intCast(@divTrunc(ry, 16));
    const bx: u4 = @intCast(@mod(rx, 16));
    const by: u4 = @intCast(@mod(ry, 16));
    const sim_idx = SimBuffer.getIndex(cx, cy);
    const coord = SimBuffer.keys[sim_idx] orelse return;

    const key = world.DepthCoordinate.from(coord);
    const idx = @as(usize, by) * 16 + bx;

    const entry_idx = world.mod_store.index.get(key) orelse blk: {
        const new_idx = world.mod_store.history.len;
        _ = world.mod_store.history.addOne(world.alloc) catch memory.oom();
        world.writeChunkModless(world.mod_store.history.at(new_idx), coord);
        world.mod_store.index.put(key, new_idx) catch memory.oom();
        break :blk new_idx;
    };

    const mc = world.mod_store.history.at(entry_idx);
    const sim_chunk = &SimBuffer.sim_buffer_ptr[sim_idx];

    const capped: u4 = @intCast(@min(vol, 15));

    // Dirty the modified chunk and its 4 orthogonal neighbors for flag updates
    const chunk_idx = (@as(usize, cy) << 4) | cx;
    chunks_to_update_flags.set(chunk_idx);
    if (cx > 0) chunks_to_update_flags.set(chunk_idx - 1);
    if (cx < 15) chunks_to_update_flags.set(chunk_idx + 1);
    if (cy > 0) chunks_to_update_flags.set(chunk_idx - 16);
    if (cy < 15) chunks_to_update_flags.set(chunk_idx + 16);

    inline for (.{ mc, sim_chunk }) |c| {
        const ptr = &c.blocks[idx];
        if (vol == 0) {
            if (ptr.isDecor()) {
                ptr.hp = 0;
            } else {
                ptr.id = .none;
                ptr.hp = 0;
                ptr.edge_flags = 0xFF;
                ptr.waterlogged = 0;
            }
        } else {
            if (ptr.isDecor()) {
                ptr.hp = capped;
            } else {
                ptr.id = .water;
                ptr.hp = capped;
            }
        }
    }

    if (world.ChunkCache.findIndex(coord)) |cache_idx| {
        world.ChunkCache.chunks[cache_idx].blocks[idx] = mc.blocks[idx];
    }
}

/// Gets pre-calculated column pressure.
inline fn getPressureCached(
    col_above_local: *const [16][18]u8,
    ptr: Block,
    bx: i32,
    by: i32,
) u32 {
    const vol = getVolume(ptr);
    if (vol == 0) return 0;
    const col_above = col_above_local[@as(usize, @intCast(by))][@as(usize, @intCast(bx + 1))];
    return vol + col_above;
}

pub const WaterloggedState = struct {
    /// Directional waterlogged flags:
    /// - bit 0: top (liquid block directly above)
    /// - bit 1: bottom (full liquid block directly below at HP=15)
    /// - bit 2: whether ripple occurs from the top (top ripple cutoff)
    /// - bit 3: left (liquid block directly to the left)
    /// - bit 4: right (liquid block directly to the right)
    flags: u5,
    /// Volume of water to copy (0 to 15).
    volume: u4,
};

/// Computes the directional waterlogged flags and adjacent water volume for a Block.
pub inline fn getWaterFlags(
    top_nb: ?Block,
    bottom_nb: ?Block,
    left_nb: ?Block,
    right_nb: ?Block,
    above_left_nb: ?Block,
    above_right_nb: ?Block,
) WaterloggedState {
    var flags: u5 = 0;
    var volume: u4 = 0;

    if (top_nb) |top| {
        if (top.isLiquid()) {
            flags |= 1; // Top
            volume = @max(volume, getVolume(top));
        }
    }

    if (bottom_nb) |bottom| {
        if (bottom.isLiquid() and getVolume(bottom) == 15) {
            flags |= 2; // Bottom
            volume = 15;
        }
    }

    if (left_nb) |left| {
        if (left.isLiquid()) {
            flags |= 8; // Left
            volume = @max(volume, getVolume(left));
            if (above_left_nb == null or (!above_left_nb.?.isSolid() and !above_left_nb.?.isLiquid())) {
                flags |= 4; // Apply top ripple cutoff
            }
        }
    }

    if (right_nb) |right| {
        if (right.isLiquid()) {
            flags |= 16; // Right
            volume = @max(volume, getVolume(right));
            if (above_right_nb == null or (!above_right_nb.?.isSolid() and !above_right_nb.?.isLiquid())) {
                flags |= 4; // Apply top ripple cutoff
            }
        }
    }

    return .{ .flags = flags, .volume = volume };
}

/// Sibling helper to compute waterlogged state for halo Sprites during base chunk generation.
pub inline fn getWaterloggedStateSprites(
    top_nb: Sprite,
    bottom_nb: Sprite,
    left_nb: Sprite,
    right_nb: Sprite,
    above_left_nb: Sprite,
    above_right_nb: Sprite,
) WaterloggedState {
    var flags: u5 = 0;
    var volume: u4 = 0;

    if (top_nb.isLiquid()) {
        flags |= 1; // Top
        volume = 15; // default full water block height
    }
    if (bottom_nb.isLiquid()) {
        flags |= 2; // Bottom (in procedural gen, water blocks default to full HP/volume)
        volume = 15;
    }
    if (left_nb.isLiquid()) {
        flags |= 8; // Left
        volume = 15;
        if (!above_left_nb.isSolid() and !above_left_nb.isLiquid()) {
            flags |= 4; // Apply top ripple cutoff
        }
    }
    if (right_nb.isLiquid()) {
        flags |= 16; // Right
        volume = 15;
        if (!above_right_nb.isSolid() and !above_right_nb.isLiquid()) {
            flags |= 4; // Apply top ripple cutoff
        }
    }

    return .{ .flags = flags, .volume = volume };
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
    const vol = getVolume(ptr);
    if (vol == 0) return 0;

    var col_above: u32 = 0;
    var cy = by - 1;
    while (col_above < 15) {
        const p = getLocalBlockPtr(curr, left, right, top, bottom, rbx, cy) orelse break;
        if (getVolume(p) > 0) {
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
    const cx: u4 = @intCast(@divTrunc(x, 16));
    const cy: u4 = @intCast(@divTrunc(y, 16));
    const bx: i32 = @intCast(@mod(x, 16));
    const by: i32 = @intCast(@mod(y, 16));

    const curr = getChunkPtr(cx, cy) orelse return;
    const left = if (cx > 0) getChunkPtr(cx - 1, cy) else null;
    const right = if (cx < 15) getChunkPtr(cx + 1, cy) else null;
    const top = if (cy > 0) getChunkPtr(cx, cy - 1) else null;
    const bottom = if (cy < 15) getChunkPtr(cx, cy + 1) else null;

    const ptr = &curr.blocks[@as(usize, @intCast((by << 4) | bx))];
    if (getVolume(ptr.*) == 0 and !world.shouldHaveEdgeFlags(ptr.id)) return;

    var flags: u8 = 0;
    var waterlogged: u5 = 0;

    const left_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx - 1, by);
    const right_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx + 1, by);
    const top_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx, by - 1);
    const bottom_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx, by + 1);
    const above_left_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx - 1, by - 1);
    const above_right_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx + 1, by - 1);

    const left_nb = if (left_ptr) |b| b.* else null;
    const right_nb = if (right_ptr) |b| b.* else null;
    const top_nb = if (top_ptr) |b| b.* else null;
    const bottom_nb = if (bottom_ptr) |b| b.* else null;
    const above_left_nb = if (above_left_ptr) |b| b.* else null;
    const above_right_nb = if (above_right_ptr) |b| b.* else null;

    if (ptr.isEmpty()) {
        flags = 0xFF;
    } else {
        const state = getWaterFlags(top_nb, bottom_nb, left_nb, right_nb, above_left_nb, above_right_nb);
        waterlogged = state.flags;

        inline for (.{ -1, 0, 1 }) |dy| {
            inline for (.{ -1, 0, 1 }) |dx| {
                if (dx == 0 and dy == 0) continue;

                const neighbor = getLocalBlockPtr(curr, left, right, top, bottom, bx + dx, by + dy);
                if (neighbor) |nb| {
                    const is_solid_or_liquid = nb.isSolid() or nb.isLiquid() or getVolume(nb.*) > 0;
                    if ((!ptr.isLiquid() and world.shouldHaveEdgeFlags(nb.id)) or (ptr.isLiquid() and is_solid_or_liquid)) {
                        flags |= types.EdgeFlags.getFlagBit(dx, dy);
                    }
                } else if (ptr.edge_flags | types.EdgeFlags.getFlagBit(dx, dy) != 0) {
                    flags |= types.EdgeFlags.getFlagBit(dx, dy);
                }
            }
        }
    }

    ptr.edge_flags = flags;
    ptr.waterlogged = waterlogged;
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
            if (getVolume(ptr.*) == 0 and !world.shouldHaveEdgeFlags(ptr.id)) continue;

            var flags: u8 = 0;
            var waterlogged: u5 = 0;

            const left_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx - 1, by);
            const right_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx + 1, by);
            const top_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx, by - 1);
            const bottom_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx, by + 1);
            const above_left_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx - 1, by - 1);
            const above_right_ptr = getLocalBlockPtr(curr, left, right, top, bottom, bx + 1, by - 1);

            const left_nb = if (left_ptr) |b| b.* else null;
            const right_nb = if (right_ptr) |b| b.* else null;
            const top_nb = if (top_ptr) |b| b.* else null;
            const bottom_nb = if (bottom_ptr) |b| b.* else null;
            const above_left_nb = if (above_left_ptr) |b| b.* else null;
            const above_right_nb = if (above_right_ptr) |b| b.* else null;

            if (ptr.isEmpty()) {
                flags = 0xFF;
            } else {
                const state = getWaterFlags(top_nb, bottom_nb, left_nb, right_nb, above_left_nb, above_right_nb);
                waterlogged = state.flags;

                inline for (.{ -1, 0, 1 }) |dy| {
                    inline for (.{ -1, 0, 1 }) |dx| {
                        if (dx == 0 and dy == 0) continue;
                        const neighbor = getLocalBlockPtr(curr, left, right, top, bottom, bx + dx, by + dy);
                        if (neighbor) |nb| {
                            const is_solid_or_liquid = nb.isSolid() or nb.isLiquid() or getVolume(nb.*) > 0;
                            if ((!ptr.isLiquid() and world.shouldHaveEdgeFlags(nb.id)) or (ptr.isLiquid() and is_solid_or_liquid)) {
                                flags |= types.EdgeFlags.getFlagBit(dx, dy);
                            }
                        } else {
                            flags |= types.EdgeFlags.getFlagBit(dx, dy);
                        }
                    }
                }
            }

            ptr.edge_flags = flags;
            ptr.waterlogged = waterlogged;
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
                                if (nnb.isSolid() or nnb.isLiquid() or getVolume(nnb) > 0) {
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
            const sim_idx = SimBuffer.getIndex(cx, cy);
            if (SimBuffer.keys[sim_idx] == null) {
                if (cx == 15) break;
                continue;
            }

            const chunk = &SimBuffer.sim_buffer_ptr[sim_idx];
            var chunk_has_water = false;
            for (&chunk.blocks) |b| {
                if (b.id == .water or getVolume(b) > 0) {
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
    water_updated = @TypeOf(water_updated).initEmpty();
    chunks_to_update_flags = std.StaticBitSet(256).initEmpty();

    // Run water simulation ONLY on active chunks
    var chunk_y: i32 = 15;
    while (chunk_y >= 0) : (chunk_y -= 1) {
        const left_to_right = (frame % 2 == 0);
        var chunk_x: i32 = 0;
        while (chunk_x < 16) : (chunk_x += 1) {
            const rcx = if (left_to_right) chunk_x else 15 - chunk_x;
            const chunk_idx = (@as(usize, @intCast(chunk_y)) << 4) | @as(usize, @intCast(rcx));

            if (!active_chunks.isSet(chunk_idx)) continue;

            // For dilated boundaries that fall outside simulated buffer ranges, add safety checking
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
                            const p = l.blocks[(col_y << 4) | 15];
                            if (getVolume(p) > 0) {
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
                        while (above_count < 15) {
                            const p = t.blocks[(ty << 4) | @as(usize, @intCast(col_x))];
                            if (getVolume(p) > 0) {
                                above_count += 1;
                            } else {
                                break;
                            }
                            if (ty == 0) break;
                            ty -= 1;
                        }
                    }

                    var col_y: usize = 0;
                    const c = curr; // guaranteed non-null
                    while (col_y < 16) : (col_y += 1) {
                        col_above_local[col_y][cache_idx] = above_count;
                        const p = c.blocks[(col_y << 4) | @as(usize, @intCast(col_x))];
                        if (getVolume(p) > 0) {
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
                            const p = r.blocks[(col_y << 4) | 0];
                            if (getVolume(p) > 0) {
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

                    // Fetch block by pointer to prevent stale local copies during modifications
                    const block_ptr = &curr.blocks[@as(usize, @intCast((by << 4) | rbx))];
                    var src_vol = getVolume(block_ptr.*);
                    if (src_vol == 0) continue;

                    water_updated.set(idx);

                    // Gravity flow!
                    const down_ptr = if (by < 15)
                        &curr.blocks[@as(usize, @intCast(((by + 1) << 4) | rbx))]
                    else if (bottom) |b|
                        &b.blocks[@as(usize, @intCast(rbx))]
                    else
                        null;

                    if (down_ptr) |dp| {
                        if (dp.isFlowable()) {
                            const dest_vol = getVolume(dp.*);
                            if (dest_vol < 15) {
                                const available = 15 - dest_vol;
                                const is_free_fall = dp.id == .none;
                                const cap: u32 = if (is_free_fall) 15 else 4;
                                const amt = @min(@min(src_vol, available), cap);

                                // Perform direct, solid transfer
                                setVolumeSticky(rx, ry, src_vol - amt);
                                setVolumeSticky(rx, ry + 1, dest_vol + amt);

                                // Only mark horizontal flows as updated to prevent vertical shear
                                // const down_idx = @as(usize, @intCast(ry + 1)) * 256 + @as(usize, @intCast(rx));
                                // water_updated.set(down_idx);

                                src_vol = getVolume(block_ptr.*);
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

                    const src_press = getPressureCached(&col_above_local, block_ptr.*, rbx, by);
                    var left_press: u32 = 0;
                    var right_press: u32 = 0;

                    if (left_ptr) |b| {
                        if (b.isFlowable()) {
                            left_press = getPressureCached(&col_above_local, b.*, rbx - 1, by);
                            if (left_press < src_press) {
                                left_ok = true;
                                left_vol = getVolume(b.*);
                            }
                        }
                    }
                    if (right_ptr) |b| {
                        if (b.isFlowable()) {
                            right_press = getPressureCached(&col_above_local, b.*, rbx + 1, by);
                            if (right_press < src_press) {
                                right_ok = true;
                                right_vol = getVolume(b.*);
                            }
                        }
                    }

                    const diff_left = if (left_ok) src_press - left_press else 0;
                    const diff_right = if (right_ok) src_press - right_press else 0;

                    if (diff_left > 1 or diff_right > 1) {
                        var flow_left: u32 = if (diff_left > 1) @min(diff_left / 2, 1) else 0;
                        var flow_right: u32 = if (diff_right > 1) @min(diff_right / 2, 1) else 0;

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
                            setVolumeSticky(rx, ry, src_vol - (flow_left + flow_right));
                            if (flow_left > 0) {
                                setVolumeSticky(rx - 1, ry, left_vol + flow_left);
                                if (rx > 0) {
                                    const left_idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx - 1));
                                    water_updated.set(left_idx);
                                }
                            }
                            if (flow_right > 0) {
                                setVolumeSticky(rx + 1, ry, right_vol + flow_right);
                                if (rx < 255) {
                                    const right_idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx + 1));
                                    water_updated.set(right_idx);
                                }
                            }
                            src_vol = getVolume(block_ptr.*);
                        }
                    }
                }
            }
        }
    }

    // Perform flag and packing updates selectively based on dirty chunk tracking
    chunk_y = 0;
    while (true) : (chunk_y += 1) {
        var chunk_x: u4 = 0;
        while (true) : (chunk_x += 1) {
            const chunk_idx = (@as(usize, @intCast(chunk_y)) << 4) | chunk_x;
            if (!chunks_to_update_flags.isSet(chunk_idx)) {
                if (chunk_x == 15) break;
                continue;
            }
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
