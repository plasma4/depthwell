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

/// Debugging water invariant check: when enabled, `tickWater` asserts that the total water volume is stable in SimBuffer
/// (as in, no water gets added or deleted from the game).
/// May result in performance drops, especially in Debug (where this is intended to be used).
///
/// Only logs if an invalid state occurs.
pub const VERIFY_WATER_MASS = false;

/// Sums the water volume of every loaded SimBuffer chunk. Debug helper for `VERIFY_WATER_MASS`.
fn totalSimWater() u64 {
    var total: u64 = 0;
    for (&SimBuffer.keys, 0..) |key, sim_idx| {
        if (key == null) continue;
        for (&SimBuffer.sim_buffer_ptr[sim_idx].blocks) |b| total += getVolume(b);
    }
    return total;
}

/// Global bitset of active chunks in the current frame (16x16 chunk grid).
var active_chunks: std.StaticBitSet(256) = undefined;
/// Per-cell "this cell has already taken its turn this tick" guard (prevents a cell moving twice in one sweep).
var water_updated: std.StaticBitSet(256 * 256) = undefined;
/// Per-cell "this cell RECEIVED sideways water this tick" guard. Such a cell is still allowed to fall
/// (gravity, perpendicular to the sweep, never causes runaway) but is barred from immediately re-spreading sideways,
/// which is what would chain-flow water across the sweep direction.
/// Keeping gravity enabled stops freshly-pushed water from freezing into side columns / dribbling off ledges.
var lateral_received: std.StaticBitSet(256 * 256) = undefined;
/// Bitset keeping track of which active chunks actually had water flow changes.
var chunks_to_update_flags: std.StaticBitSet(256) = undefined;
/// Chunks (logical 16x16 index) queued by manual water placement (`world.modifyBlockType`) for batched edge-flag recompute on next tick.
/// Persists between ticks (unlike `chunks_to_update_flags`) and is folded in at the flag phase.
var pending_flag_chunks: std.StaticBitSet(256) = std.StaticBitSet(256).initEmpty();

/// Queues a manually-placed water block's chunk plus its 4 orthogonal neighbors for a batched flag recompute,
/// rather than recomputing each touched water block synchronously at placement time.
/// Placement happens before `tickWater` within the same tick, so flags still resolve the same frame.
pub fn queueWaterFlags(cx: u4, cy: u4) void {
    const idx = (@as(usize, cy) << 4) | cx;
    pending_flag_chunks.set(idx);
    if (cx > 0) pending_flag_chunks.set(idx - 1);
    if (cx < 15) pending_flag_chunks.set(idx + 1);
    if (cy > 0) pending_flag_chunks.set(idx - 16);
    if (cy < 15) pending_flag_chunks.set(idx + 16);
}

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

/// Computes the water volume for a cell dynamically.
/// Supports cross-chunk reads via horizontal offsets (`bx` of -1 or 16).
/// Returns 0 if the requested neighbor chunk is missing.
inline fn getVolumeLocal(
    curr: *Chunk,
    left: ?*Chunk,
    right: ?*Chunk,
    bx: i32,
    by: i32,
) u32 {
    if (bx >= 0 and bx < 16) {
        return getVolume(curr.blocks[@as(usize, @intCast((by << 4) | bx))]);
    } else if (bx < 0) {
        const l = left orelse return 0;
        return getVolume(l.blocks[@as(usize, @intCast((by << 4) | (bx + 16)))]);
    } else {
        const r = right orelse return 0;
        return getVolume(r.blocks[@as(usize, @intCast((by << 4) | (bx - 16)))]);
    }
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
                            if (n_nb) |block| {
                                if (block.isSolid() or block.isLiquid() or getVolume(block) > 0) {
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
/// This simulation has been (somewhat) optimized and is also fully mass-conserving.
pub fn tickWater() void {
    const frame = memory.game.frame;

    // A chunk is simulated only if it has water AND is not "settled" (sleep/wake):
    // a chunk that produced no flow last tick is asleep and skipped, so large still bodies are mostly free.
    // Cross-border flow and `wake` clear neighboring settled bits (see the dirty pass below).
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

            if (SimBuffer.has_water.isSet(sim_idx) and !SimBuffer.water_settled.isSet(sim_idx)) {
                active_chunks.set(chunk_idx);
            }

            if (cx == 15) break;
        }
        if (cy == 15) break;
    }

    if (active_chunks.count() == 0) return;
    water_updated = .initEmpty();
    lateral_received = .initEmpty();
    chunks_to_update_flags = .initEmpty();

    // Fold in chunks queued by manual water placement so their edge flags get one batched pass below
    // (these chunks are active, since placement also sets their `has_water` bit)
    // Pending is preserved across early returns above, so a placement is never dropped.
    chunks_to_update_flags.setUnion(pending_flag_chunks);
    pending_flag_chunks = std.StaticBitSet(256).initEmpty();

    const water_before: u64 = if (VERIFY_WATER_MASS) totalSimWater() else 0;

    // Tracks which chunks within the 16x16 grid received any volume modifications
    var dirty_chunks = std.StaticBitSet(256).initEmpty();

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
            const bottom = if (chunk_y < 15) getChunkPtr(@intCast(rcx), @intCast(chunk_y + 1)) else null;

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

                                // Perform direct, solid transfer on SimBuffer pointers
                                setVolume(block_ptr, src_vol - amt);
                                setVolume(dp, dest_vol + amt);

                                dirty_chunks.set(chunk_idx);
                                if (by == 15 and bottom != null) {
                                    dirty_chunks.set(chunk_idx + 16);
                                }

                                src_vol = getVolume(block_ptr.*);
                                if (src_vol == 0) continue;
                            }
                        }
                    }

                    // Only spread sideways once the cell can no longer descend.
                    const down_blocked = if (down_ptr) |dp| (!dp.isFlowable() or getVolume(dp.*) >= 15) else true;
                    if (!down_blocked) continue;
                    // If this cell only just received water do NOT let it re-spread sideways again.
                    if (lateral_received.isSet(idx)) continue;

                    // Horizontal equalizing flow: water moves toward the lower-volume neighbor,
                    // equalizing a surface gradually ticks.
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

                    const src_press = getVolumeLocal(curr, left, right, rbx, by);
                    var left_press: u32 = 0;
                    var right_press: u32 = 0;

                    if (left_ptr) |b| {
                        if (b.isFlowable()) {
                            left_press = getVolumeLocal(curr, left, right, rbx - 1, by);
                            if (left_press < src_press) {
                                left_ok = true;
                                left_vol = getVolume(b.*);
                            }
                        }
                    }
                    if (right_ptr) |b| {
                        if (b.isFlowable()) {
                            right_press = getVolumeLocal(curr, left, right, rbx + 1, by);
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
                            setVolume(block_ptr, src_vol - (flow_left + flow_right));
                            dirty_chunks.set(chunk_idx);

                            if (flow_left > 0) {
                                setVolume(left_ptr.?, left_vol + flow_left);
                                if (rbx > 0) {
                                    dirty_chunks.set(chunk_idx);
                                } else if (left != null) {
                                    dirty_chunks.set(chunk_idx - 1);
                                }
                                if (rx > 0) {
                                    const left_idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx - 1));
                                    lateral_received.set(left_idx);
                                }
                            }
                            if (flow_right > 0) {
                                setVolume(right_ptr.?, right_vol + flow_right);
                                if (rbx < 15) {
                                    dirty_chunks.set(chunk_idx);
                                } else if (right != null) {
                                    dirty_chunks.set(chunk_idx + 1);
                                }
                                if (rx < 255) {
                                    const right_idx = @as(usize, @intCast(ry)) * 256 + @as(usize, @intCast(rx + 1));
                                    lateral_received.set(right_idx);
                                }
                            }
                            src_vol = getVolume(block_ptr.*);
                        }
                    }
                }
            }
        }
    }

    if (VERIFY_WATER_MASS) {
        const water_after = totalSimWater();
        if (water_after != water_before) {
            dw.logger.err(@src(), "Water mass NOT conserved in tickWater: {d} -> {d}", .{ water_before, water_after });
        }
    }

    // A chunk that was simulated but produced no flow this tick is at equilibrium
    // (this is independent of the alternating sweep direction, as a settled chunk yields zero flow under either),
    // so it can be skipped until disturbed. Chunks that DID flow are handled now!
    var act_it = active_chunks.iterator(.{});
    while (act_it.next()) |idx| {
        if (!dirty_chunks.isSet(idx)) {
            const ax: u4 = @intCast(idx & 15);
            const ay: u4 = @intCast(idx >> 4);
            SimBuffer.water_settled.set(SimBuffer.getIndex(ax, ay));
        }
    }

    // Perform flag and packing updates selectively based on dirty chunk tracking
    // Defer dirty chunk updates to history and ChunkCache to execute them in easy single-step block transfers!
    var dirty_it = dirty_chunks.iterator(.{});
    while (dirty_it.next()) |idx| {
        const dy: u4 = @intCast(idx >> 4);
        const dx: u4 = @intCast(idx & 15);
        const sim_idx = SimBuffer.getIndex(dx, dy);
        const coord = SimBuffer.keys[sim_idx] orelse continue;

        const key = world.DepthCoordinate.from(coord);
        const sim_chunk = &SimBuffer.sim_buffer_ptr[sim_idx];

        // A dirtied chunk's water content changed so re-evaluate its flag so
        // it stays active while it holds water, and it drops out of the simulation once it has fully drained.
        SimBuffer.has_water.setValue(sim_idx, SimBuffer.chunkHasWater(sim_chunk));

        const entry_idx = world.mod_store.index.get(key) orelse blk: {
            const new_idx = world.mod_store.history.len;
            _ = world.mod_store.history.addOne(world.alloc) catch memory.oom();
            world.writeChunkModless(world.mod_store.history.at(new_idx), coord);
            world.mod_store.index.put(key, new_idx) catch memory.oom();
            break :blk new_idx;
        };

        const mc = world.mod_store.history.at(entry_idx);
        mc.blocks = sim_chunk.blocks;

        if (world.ChunkCache.findIndex(coord)) |cache_idx| {
            world.ChunkCache.chunks[cache_idx].blocks = sim_chunk.blocks;
        }

        chunks_to_update_flags.set(idx);
        if (dx > 0) chunks_to_update_flags.set(idx - 1);
        if (dx < 15) chunks_to_update_flags.set(idx + 1);
        if (dy > 0) chunks_to_update_flags.set(idx - 16);
        if (dy < 15) chunks_to_update_flags.set(idx + 16);

        // Wake this chunk and its neighbors for next tick.
        SimBuffer.water_settled.unset(sim_idx);
        if (dx > 0) SimBuffer.water_settled.unset(SimBuffer.getIndex(dx - 1, dy));
        if (dx < 15) SimBuffer.water_settled.unset(SimBuffer.getIndex(dx + 1, dy));
        if (dy > 0) SimBuffer.water_settled.unset(SimBuffer.getIndex(dx, dy - 1));
        if (dy < 15) SimBuffer.water_settled.unset(SimBuffer.getIndex(dx, dy + 1));
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
            // Recompute flags for any flagged-and-loaded chunk (no longer gated on `active_chunks`, since
            // sleep/wake dropped the boundary dilation; a dirtied neighbor still needs correct flags).
            if (SimBuffer.keys[SimBuffer.getIndex(chunk_x, @intCast(chunk_y))] == null) {
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
