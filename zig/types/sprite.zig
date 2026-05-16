const std = @import("std");
const root = @import("../root.zig");

const is_debug = root.is_debug;
const memory = root.memory;
const procedural = root.procedural;

/// Index where stone-like sprites begin.
const STONE_START = 4;
/// Index where stone-like sprites end.
const STONE_END = STONE_START + 10;

/// Index where ore sprites begin.
const ORE_START = STONE_END + 4;

/// Index where gem sprites begin.
const GEM_START = ORE_START + 4;

/// Index where gem masks (not gem sprites) begin.
const MASK_START = GEM_START + 4;
/// Index after the HP mask ends, and decorations begin.
/// Between `MASK_START` and `MASK_END` are 8 ore masks and 16 HP masks.
const DECOR_START = MASK_START + 24;

/// Index where inventory slot sprites start.
pub const INVENTORY_START = DECOR_START + 14;
/// Index where numbers (0-9) start.
pub const NUMBER_START = INVENTORY_START + 3;

/// Sprite IDs with values based on their sprite sheet location
/// Packed sprite sheet located at src/main.png.
pub const Sprite = enum(u16) {
    /// Empty (air) sprite.
    none = 0,
    /// Sprite of the player.
    player = 1,

    /// Edge stone (2 variations).
    edge_stone = 2,

    // stone types!
    blue_strange_stone = STONE_START,
    purple_strange_stone,
    blue_stone,
    red_stone,
    seagreen_stone,
    green_stone,
    lava_stone,
    redder_stone,
    mossy_stone,
    old_stone,
    /// "Plain" stone type, with 2x2 variations to prevent a tiling look.
    stone = STONE_END,

    // ores!
    copper = ORE_START,
    iron,
    silver,
    gold = GEM_START - 1, // no gap between ores and gems

    // gems!
    amethyst = GEM_START,
    sapphire,
    emerald,
    ruby = MASK_START - 1,

    // Internal assets (not valid for placement/foundation)
    gem_mask = MASK_START, // 8 masks
    hp_mask = MASK_START + 8, // 16 masks

    // Decor (THIS IS COUPLED TO WGSL CODE)
    spiral_plant = DECOR_START,
    ceiling_flower = DECOR_START + 1, // 2 variations
    mushroom = DECOR_START + 5, // 3 variations (+2) because of WGSL logic
    big_mushroom = DECOR_START + 8, // 3 variations (also +2)
    forest_furnace = DECOR_START + 9,
    lava_furnace = DECOR_START + 10,
    torch,
    chest,
    portal,

    /// Unselected inventory sprite.
    inventory = INVENTORY_START,
    /// Selected (currently used) inventory sprite.
    inventory_selected,
    inventory_selected_invalid, // unused

    text_0 = NUMBER_START, // sprite with text 0

    /// Sprite for a particle; a full white rectangle but with corner pixels cut off.
    particle = NUMBER_START + 10,
    /// Full rectangle sprite; no corner pixels cut off.
    rectangle,
    /// Pickaxe icon.
    pickaxe,
    /// Generic water block (filled). Default internal water type.
    water,
    // Generic water block (top, with small waves) is the ID afterward.
    // That gets processed and added in chunk.zig.

    /// A special type used for inventory purposes. Doesn't exist as an actual sprite.
    unselected = 65535,

    _, // non-exhaustive for heatmaps

    /// Determines if the sprite's type is one that should interact with the edge flags and procedural generation.
    /// This returns false for edge stone, unlike `is_solid`. Assumes invalid block types are impossible.
    pub inline fn isFoundation(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= STONE_START and id < MASK_START;
    }

    /// Determines if the sprite's type is a valid block that could exist in any chunk.
    /// Includes the empty block, and excludes entities.
    ///
    /// If this code is wrong, invalid (or unnamed) enums may appear and wreak havoc.
    pub fn isValid(self: @This()) bool {
        // do note that heatmap isn't valid
        return switch (self) {
            .none,
            .spiral_plant,
            .ceiling_flower,
            .mushroom,
            .big_mushroom,
            .forest_furnace,
            .lava_furnace,
            .torch,
            .chest,
            .water,
            .portal,
            => true,
            else => {
                // may be used for testing visually, as it's a clean sprite
                if (is_debug and self == .inventory_selected_invalid) return true;

                const id = @intFromEnum(self);
                return (id >= STONE_START and id <= STONE_END) or
                    (id >= ORE_START and id < MASK_START);
            },
        };
    }

    /// Determines if the sprite's type is considered solid, and should interact with the physics, player, and edge flags.
    /// This returns true for edge stone, unlike `is_solid`.
    pub fn isSolid(self: @This()) bool {
        if (self == Sprite.none or self == .player) return false;
        if (is_debug and self == .inventory_selected_invalid) return false;
        if (self == .forest_furnace or self == .lava_furnace) return true;

        const id = @intFromEnum(self);
        if (id >= MASK_START) return false;
        return true;
    }

    /// Determines if the sprite's type is a liquid (such as water).
    pub fn isLiquid(self: @This()) bool {
        return self == .water;
    }

    /// Determines if the sprite's type is `none` (air/void).
    pub inline fn isEmpty(self: @This()) bool {
        return self == .none;
    }

    /// Determines if the sprite is stone (or a variation). Excludes edge stone.
    pub inline fn isStone(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= STONE_START and id <= STONE_END;
    }

    /// Determines if the sprite is an ore.
    pub inline fn isOre(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= ORE_START and id < GEM_START;
    }

    /// Determines if the sprite is a gem.
    pub inline fn isGem(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= GEM_START and id < MASK_START;
    }

    /// Determines if the sprite is a heatmap (between types 65000-65256).
    pub inline fn isHeatmap(self: @This()) bool {
        const id = @intFromEnum(self);
        return is_debug and id >= 65000 and id <= 65256;
    }
};

/// The total number of valid sprites that are considered valid (according to `isValid()`).
pub const valid_sprite_count: usize = blk: {
    @setEvalBranchQuota(1e6);
    const fields = @typeInfo(Sprite).@"enum".fields;
    var count: usize = 0;
    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite.isValid()) {
            count += 1;
        }
    }
    break :blk count;
};

/// An array of all `Sprite` values that are considered valid (according to `isValid()`).
pub const valid_sprites = blk: {
    @setEvalBranchQuota(1e6);
    const fields = @typeInfo(Sprite).@"enum".fields;
    var result: [valid_sprite_count]Sprite = undefined;
    var index: usize = 0;

    // Populate the array!
    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite.isValid()) {
            result[index] = sprite;
            index += 1;
        }
    }

    break :blk result;
};

/// Maximum possible sprite value.
pub const max_sprite_value = blk: {
    @setEvalBranchQuota(1e6);
    var max_val: u16 = 0;
    const fields = @typeInfo(Sprite).@"enum".fields;

    for (fields) |field| {
        if (std.mem.eql(u8, field.name, "unselected")) continue;
        if (field.value > max_val) {
            if (field.value >= 60000)
                @compileError("Sprite enum values must not be between the reserved range of 60000-65534.");
            max_val = @intCast(field.value);
        }
    }
    break :blk max_val;
};

/// Empty block of id `Sprite.none`.
pub const AIR_BLOCK: memory.Block = .{
    .id = .none,
    .seed = 0,
    .light = 0,
    .hp = 0,
    .edge_flags = 0xFF,
};

comptime {
    @setEvalBranchQuota(1e6);
    // Check if isValid() is being reasonable and isn't producing unmapped results.
    // Mapped but invalid results can be checked by setting `SHOW_ALL_INVENTORY_ITEMS` to true in the zig/input/inventory.zig file.
    var i: u16 = 0;
    var wentToHeatmap = false;
    if (@as(Sprite, @enumFromInt(65535)).isValid()) @compileError("isValid() returned true for the unselected type! Ranges are wrong.");
    while (i < 65535) : (i += 1) {
        if (!wentToHeatmap and i == max_sprite_value + 256) {
            // skip some checking
            i = 60000;
            wentToHeatmap = true;
        }
        const s: Sprite = @enumFromInt(i);
        if (s.isValid()) {
            var is_mapped = false;
            for (@typeInfo(Sprite).@"enum".fields) |field| {
                if (field.value == i) {
                    is_mapped = true;
                    break;
                }
            }
            if (!is_mapped) {
                @compileError("isValid() returned true for an unmapped sprite ID! Ranges are wrong.");
            }
        }
    }
}
