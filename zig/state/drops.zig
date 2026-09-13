//! Block-drop resolution: handles how a destroyed block turns into item sprites.
//! `SpriteProps.drops` holds a `DropConfig`; data gets consumed in `input/inventory.zig`.
const std = @import("std");
const dw = @import("../root.zig");

const memory = dw.memory;
const Sprite = dw.Sprite;
const Coordinate = dw.world.Coordinate;

/// Strategy to resolve block drop items upon destruction.
/// Works for all (valid) sprite types.
pub const DropStrategy = enum {
    /// Drops itself by default (does not guarantee inventory visibility).
    self,
    /// Guaranteed to drop nothing.
    none,
    /// Drops a predetermined list of static items.
    static,
    /// Runs a custom function to determine drops.
    dynamic,
};

/// Type signature for deterministic coordinate-based drop calculations.
pub const DropFn = *const fn (coord: Coordinate, bx: u4, by: u4) []const Sprite;

/// Configuration defining how a block drops items.
pub const DropConfig = struct {
    strategy: DropStrategy = .self,
    static_items: []const Sprite = &.{},
    dynamic_fn: ?DropFn = null,
};

/// Deterministic 64-bit roll for one block, for a `WeightedPicker` to read.
/// It mixes only the chunk seed and the absolute block coordinate.
/// So the same block gives the same roll on every visit and by every route.
/// Frame count or item count must never enter here, or a drop changes when the player re-mines it.
fn blockRoll(coord: Coordinate, bx: u4, by: u4) u64 {
    const key = coord.asDepthCoordinate(memory.game.depth);
    const chunk_seeds = dw.world.quad_cache.getChunkSeeds(key);

    // Absolute block coordinate in the world (no +% needed for bx/by, which cannot carry)
    const abs_x = coord.suffix[0] *% 16 + bx;
    const abs_y = coord.suffix[1] *% 16 + by;
    return dw.seeding.FastHash.hash2d(
        chunk_seeds.value[3].value[0..2].*,
        abs_x,
        abs_y,
    );
}

/// Custom `dynamic_fn` handlers referenced by `DropConfig` entries in the sprite rule table.
/// Each function returns an array of sprites, with all sprites returned being dropped.
pub const DropHandlers = struct {
    /// Converts a bush to various fruits.
    pub fn bushDrop(coord: Coordinate, bx: u4, by: u4) []const Sprite {
        // Describes what a bush drops, and how often relative to the other rows.
        // Odds automatically adjust to 100%.
        const bush_drops = dw.seeding.WeightedPicker([]const Sprite, &.{
            .{ .value = &.{.ruby_candy}, .weight = 5 },
            .{ .value = &.{.splittyfruit}, .weight = 10 },
            .{ .value = &.{.teal_lemon_fruit}, .weight = 15 },
            .{ .value = &.{.blemon_fruit}, .weight = 15 },
            .{ .value = &.{.copperfruit}, .weight = 15 },
            .{ .value = &.{.ploopus1}, .weight = 8 },
            .{ .value = &.{.ploopus2}, .weight = 8 },
            .{ .value = &.{.divato}, .weight = 7 },
            .{ .value = &.{.circuspin}, .weight = 5 },
            .{ .value = &.{.bacon}, .weight = 3 },
        });

        return bush_drops.pick(blockRoll(coord, bx, by));
    }

    /// Converts a pile of sticks into 3 to 5 single sticks.
    pub fn stickDrop(coord: Coordinate, bx: u4, by: u4) []const Sprite {
        const stick_drops = dw.seeding.WeightedPicker([]const Sprite, &.{
            .{ .value = &([_]Sprite{.stick} ** 3), .weight = 3 },
            .{ .value = &([_]Sprite{.stick} ** 4), .weight = 2 },
            .{ .value = &([_]Sprite{.stick} ** 5), .weight = 1 },
        });

        return stick_drops.pick(blockRoll(coord, bx, by));
    }
};
