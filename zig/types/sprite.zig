const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const procedural = root.procedural;

/// Sprite IDs, based on src/main-Sheet.png
pub const Sprite = enum(u16) {
    none,
    player,
    edge_stone, // has visual variation
    _edge_stone,
    strange_stone,
    strange_stone_other,
    blue_stone,
    seagreen_stone,
    green_stone,
    stone, // visual variations are in a 2x2
    _stone,
    __stone,
    ___stone,
    lava_stone,
    copper,
    iron,
    silver,
    gold,
    amethyst,
    sapphire,
    emerald,
    ruby,
    gem_mask, // 8 masks for gems
    _gem_mask,
    __gem_mask,
    ___gem_mask,
    geode_mask,
    _geode_mask,
    __geode_mask,
    ___geode_mask,
    _o0, // 16 hp sprites
    _o1,
    _o2,
    _o3,
    _o4,
    _o5,
    _o6,
    _o7,
    _o8,
    _o9,
    _o10,
    _o11,
    _o12,
    _o13,
    _o14,
    _o15,
    spiral_plant,
    ceiling_flower,
    mushroom, // there is another variant of mushrooms
    _mushroom, // visual variation
    torch,
    unchanged = 65535,
    _, // non-exhaustive for heatmap

    /// Determines if the sprite's type is one that should interact with the edge flags and procedural generation.
    /// This returns false for edge stone, unlike `is_solid`. Assumes invalid block types are impossible.
    pub inline fn is_foundation(self: @This()) bool {
        return switch (self) {
            .none,
            .spiral_plant,
            .ceiling_flower,
            .torch,
            .mushroom,
            .edge_stone,
            ._edge_stone,
            => false,
            else => true,
        };
    }

    /// Determines if the sprite's type is valid. Includes the empty block.
    pub inline fn is_valid(self: @This()) bool {
        return switch (self) {
            .player,
            ._edge_stone,
            .stone,
            ._stone,
            .__stone,
            .___stone,
            .gem_mask,
            ._gem_mask,
            .__gem_mask,
            .___gem_mask,
            .geode_mask,
            ._geode_mask,
            .__geode_mask,
            .___geode_mask,
            ._o0,
            ._o1,
            ._o2,
            ._o3,
            ._o4,
            ._o5,
            ._o6,
            ._o7,
            ._o8,
            ._o9,
            ._o10,
            ._o11,
            ._o12,
            ._o13,
            ._o14,
            ._o15,
            ._mushroom,
            => false,
            else => true,
        };
    }

    /// Determines if the sprite's type is considered solid, and should interact with the physics, player, and edge flags.
    /// This returns true for edge stone, unlike `is_solid`.
    pub inline fn is_solid(self: @This()) bool {
        return switch (self) {
            .none,
            .spiral_plant,
            .ceiling_flower,
            .torch,
            .mushroom,
            => false,
            else => true,
        };
    }

    /// Determines if the sprite's type is `none` (air/void).
    pub inline fn is_empty(self: @This()) bool {
        return self == .none;
    }

    /// Determines if the sprite is stone (or a variation). Excludes edge stone.
    pub inline fn is_stone(self: @This()) bool {
        return switch (self) {
            .stone,
            .lava_stone,
            .blue_stone,
            .seagreen_stone,
            .green_stone,
            .strange_stone,
            .strange_stone_other,
            => true,
            else => false,
        };
    }

    /// Determines if the sprite is an ore.
    pub inline fn is_ore(self: @This()) bool {
        return switch (self) {
            .copper,
            .iron,
            .silver,
            .gold,
            => true,
            else => false,
        };
    }

    /// Determines if the sprite is a gem.
    pub inline fn is_gem(self: @This()) bool {
        return switch (self) {
            .amethyst,
            .sapphire,
            .emerald,
            .ruby,
            => true,
            else => false,
        };
    }

    /// Determines if the sprite is a heatmap (types 256-512).
    pub inline fn is_heatmap(self: @This()) bool {
        return root.is_debug and procedural.USE_BASE_HEATMAP and @intFromEnum(self) >= 256 and @intFromEnum(self) <= 512;
    }
};

/// The total number of foundation sprites.
pub const foundation_sprite_count: usize = blk: {
    const fields = @typeInfo(Sprite).@"enum".fields;
    var count: usize = 0;
    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite != .unchanged and (sprite.is_valid())) {
            count += 1;
        }
    }
    break :blk count;
};

/// An array of all `Sprite` values that return true for `is_foundation()`.
pub const foundation_sprites = blk: {
    const fields = @typeInfo(Sprite).@"enum".fields;
    var result: [foundation_sprite_count]Sprite = undefined;
    var index: usize = 0;

    // Populate the array!
    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite != .unchanged and (sprite.is_valid())) {
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
        // Skip the "unchanged" field by name
        if (std.mem.eql(u8, field.name, "unchanged")) continue;

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
