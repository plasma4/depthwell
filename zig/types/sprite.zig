const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const procedural = root.procedural;

/// Index where stone-like sprites begin.
const STONE_START = 4;

/// Index where ore sprites begin.
const ORE_START = STONE_START + 12;

/// Index where gem sprites begin.
const GEM_START = ORE_START + 4;

/// Index where gem masks (not gem sprites) begin.
const MASK_START = GEM_START + 4;
/// Index where the HP mask ends.
/// Between `MASK_START` and `MASK_END` are 8 ore masks and 16 HP masks.
const DECOR_START = MASK_START + 24;

/// Index where numbers (0-9) start.
pub const NUMBER_START = DECOR_START + 8;

/// Sprite IDs with values based on their sprite sheet location
/// Packed sprite sheet located at src/main.png.
pub const Sprite = enum(u16) {
    none = 0,
    player = 1,

    // Edge stone (2 variations)
    edge_stone = 2,

    // Stone types
    strange_stone = STONE_START,
    strange_stone_other,
    blue_stone,
    seagreen_stone,
    green_stone,
    lava_stone,
    mossy_stone,
    old_stone,
    stone, // 2x2 variations of stone exist

    // ores
    copper = ORE_START,
    iron,
    silver,
    gold,

    // gems!
    amethyst = GEM_START,
    sapphire,
    emerald,
    ruby,

    // Internal assets (not valid for placement/foundation)
    gem_mask = MASK_START, // 8 masks
    hp_mask = MASK_START + 8, // 16 masks

    // Decor
    spiral_plant = DECOR_START,
    ceiling_flower = DECOR_START + 1, // 2 variations
    mushroom = DECOR_START + 3, // 2 variations
    torch = DECOR_START + 5,

    inventory = DECOR_START + 6,
    inventory_selected = DECOR_START + 7,
    text_0 = NUMBER_START,
    particle = NUMBER_START + 10,
    pickaxe,

    /// A special type used for inventory purposes. Doesn't exist as an actual sprite.
    unselected,

    _, // heatmap range

    /// Determines if the sprite's type is one that should interact with the edge flags and procedural generation.
    /// This returns false for edge stone, unlike `is_solid`. Assumes invalid block types are impossible.
    pub inline fn is_foundation(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= STONE_START and id < MASK_START;
    }

    /// Determines if the sprite's type is valid. Includes the empty block.
    pub inline fn is_valid(self: @This()) bool {
        // do note that heatmap isn't valid
        const id = @intFromEnum(self);
        return self == .none or self == .spiral_plant or self == .ceiling_flower or self == .mushroom or self == .torch or
            (id >= STONE_START and id < MASK_START);
    }

    /// Determines if the sprite's type is considered solid, and should interact with the physics, player, and edge flags.
    /// This returns true for edge stone, unlike `is_solid`.
    pub inline fn is_solid(self: @This()) bool {
        if (self == Sprite.none or self == .player) return false;

        const id = @intFromEnum(self);
        if (id >= @intFromEnum(Sprite.gem_mask) and id < @intFromEnum(Sprite.spiral_plant)) return false;
        return switch (self) {
            .spiral_plant, .ceiling_flower, .mushroom, .torch, .none, .player => false,
            else => true,
        };
    }

    /// Determines if the sprite's type is `none` (air/void).
    pub inline fn is_empty(self: @This()) bool {
        return self == .none;
    }

    /// Determines if the sprite is stone (or a variation). Excludes edge stone.
    pub inline fn is_stone(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= STONE_START and id < ORE_START;
    }

    /// Determines if the sprite is an ore.
    pub inline fn is_ore(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= ORE_START and id < GEM_START;
    }

    /// Determines if the sprite is a gem.
    pub inline fn is_gem(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= GEM_START and id < MASK_START;
    }

    /// Determines if the sprite is a heatmap (between types 256-512).
    pub inline fn is_heatmap(self: @This()) bool {
        const id = @intFromEnum(self);
        return root.is_debug and procedural.USE_BASE_HEATMAP and id >= 256 and id <= 512;
    }
};

/// The total number of foundation sprites.
pub const foundation_sprite_count: usize = blk: {
    const fields = @typeInfo(Sprite).@"enum".fields;
    var count: usize = 0;
    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite.is_valid()) {
            count += 1;
        }
    }
    break :blk count;
};

/// An array of all `Sprite` values that are considered valid (according to `is_valid()`).
pub const foundation_sprites = blk: {
    const fields = @typeInfo(Sprite).@"enum".fields;
    var result: [foundation_sprite_count]Sprite = undefined;
    var index: usize = 0;

    // Populate the array!
    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite.is_valid()) {
            result[index] = sprite;
            index += 1;
        }
    }

    break :blk result;
};

/// Maximum possible sprite value.
pub const max_sprite_value = blk: {
    var max_val: u16 = 0;
    const fields = @typeInfo(Sprite).@"enum".fields;

    for (fields) |field| {
        if (field.value > max_val) {
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
