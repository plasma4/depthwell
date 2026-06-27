const std = @import("std");
const dw = @import("../root.zig");

const is_debug = dw.is_debug;
const memory = dw.memory;
const procedural = dw.procedural;

const Coordinate = dw.world.Coordinate;

/// Index where stone-like sprites begin.
const STONE_START = 4;
/// Index where stone-like sprites end.
const STONE_END = STONE_START + 13;

/// Index where ore sprites begin.
const ORE_START = STONE_END + 4;

/// Index where gem sprites begin.
pub const GEM_START = ORE_START + 4;

/// Number of gem sprites.
pub const GEM_COUNT = 4;

/// Index where gem masks (not gem sprites) begin.
pub const MASK_START = GEM_START + GEM_COUNT * 2;
/// Index after the HP mask ends, and decorations begin.
const DECOR_START = MASK_START + 24;

/// Number of fruit sprites.
const FRUIT_COUNT = 10;
/// ID for `Sprite.gear`, which is after a list of fruit drops.
const GEAR_ID = DECOR_START + 5 + FRUIT_COUNT;

/// Index where inventory slot sprites start.
pub const INVENTORY_START = GEAR_ID + 18;
/// Index where numbers (0-9) start.
pub const NUMBER_START = INVENTORY_START + 4;

/// Hitbox geometry variants for various block shapes.
pub const HitboxKind = enum(u3) {
    full,
    small_bottom_decor,
    large_bottom_decor,
    ceiling_decor,
    thin_strip,
};

/// Strategy to resolve whether a block was placed in a valid position.
/// Works for all (valid) sprite types.
pub const AnchorKind = enum(u2) {
    /// No requirements: this sprite type can be placed anywhere.
    none = 0,
    /// The sprite type must be directly above a solid block.
    floor = 1,
    /// The sprite type must be directly below a solid block.
    ceiling = 2,
    /// This sprite type must be directly below a solid block or itself.
    suspended = 3,
};

/// Strategy to resolve block drop items upon destruction.
pub const DropStrategy = enum {
    /// Drops itself if `.isItem()` returns true.
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

/// Contains custom functions for `dynamic_fn` in the `DropConfig`.
pub const DropHandlers = struct {
    /// Converts a bush drop to various fruits based on world coordinates and seeds.
    pub fn bushDrop(coord: Coordinate, bx: u4, by: u4) []const Sprite {
        const oddsNum = dw.seeding.oddsNum;
        const depth = memory.game.depth;
        const key = coord.asDepthCoordinate(depth);
        const chunk_seeds = dw.world.quad_cache.getChunkSeeds(key);

        // Deterministic hash based on the absolute block coordinate in the world
        const abs_x = coord.suffix[0] *% 16 + bx; // (no +% needed)
        const abs_y = coord.suffix[1] *% 16 + by;
        const seed_val = dw.seeding.FastHash.hash2d(
            chunk_seeds.value[3].value[0..2].*,
            abs_x,
            abs_y,
        );

        const roll = seed_val;
        if (roll <= oddsNum(0.05)) {
            return &[_]Sprite{.fruit_ruby_candy};
        } else if (roll <= oddsNum(0.15)) {
            return &[_]Sprite{.fruit_splitty};
        } else if (roll <= oddsNum(0.30)) {
            return &[_]Sprite{.fruit_teal_lemon};
        } else if (roll <= oddsNum(0.45)) {
            return &[_]Sprite{.fruit_blue_lemon};
        } else if (roll <= oddsNum(0.60)) {
            return &[_]Sprite{.copperfruit};
        } else if (roll <= oddsNum(0.70)) {
            return &[_]Sprite{.ploopus1};
        } else if (roll <= oddsNum(0.80)) {
            return &[_]Sprite{.ploopus2};
        } else if (roll <= oddsNum(0.90)) {
            return &[_]Sprite{.divato};
        } else if (roll <= oddsNum(0.96)) {
            return &[_]Sprite{.circuspin};
        } else {
            return &[_]Sprite{.bacon};
        }
    }
};

/// Consolidated properties of each sprite.
pub const SpriteProps = struct {
    in_world: bool = false,
    item: bool = false,
    solid: bool = false,
    liquid: bool = false,
    foundation: bool = false,
    stone: bool = false,
    ore: bool = false,
    gem: bool = false,
    strength: u64 = 0,
    hitbox: HitboxKind = .full,
    anchor: AnchorKind = .none,
    drops: DropConfig = .{ .strategy = .self },
    evolves_to: ?Sprite = null,
};

/// Tightly packed 16-bit struct for high-performance, cache-friendly lookups.
pub const SpriteFlags = packed struct(u16) {
    in_world: bool = false,
    item: bool = false,
    solid: bool = false,
    liquid: bool = false,
    foundation: bool = false,
    stone: bool = false,
    ore: bool = false,
    gem: bool = false,
    hitbox: HitboxKind = .full, // 3 bits
    anchor: AnchorKind = .none, // 2 bits
    padding: u3 = 0,
};

/// Targeting selector for assigning properties at compile-time.
const Target = union(enum) {
    single: Sprite,
    range: [2]Sprite,
    list: []const Sprite,
};

/// Contains targets describing what to select and what SpriteProps to apply to them.
const SpriteRule = struct {
    Target, // unnamed tuples are cool
    SpriteProps,
};

/// Centralized database describing all sprite properties.
/// Rules are checked in order, with later rules overriding earlier ones.
const rules = [_]SpriteRule{
    // Stone blocks
    .{
        .{ .range = .{ .blue_strange_stone, .stone } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .stone = true,
            .strength = 15,
        },
    },
    // Ores
    .{
        .{ .range = .{ .copper, .gold } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .ore = true,
            .strength = 30,
        },
    },
    // Gems
    .{
        .{ .range = .{ .amethyst, .ruby } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .gem = true,
            .strength = 15,
        },
    },
    // Edge stone
    .{
        .{ .single = .edge_stone },
        .{ .in_world = true, .solid = true },
    },
    // Normal decor
    .{
        .{ .list = &[_]Sprite{
            .rock,           .bush,     .small_tree,   .spiral_plant,
            .ceiling_flower, .mushroom, .big_mushroom, .forest_furnace,
            .lava_furnace,   .torch,    .chest,        .portal,
        } },
        .{
            .in_world = true,
            .item = true,
        },
    },
    // Non-item decor (corresponds to small_tree)
    .{
        .{ .list = &[_]Sprite{
            .big_tree1_left,
            .big_tree1_right,
            .big_tree2_left,
            .big_tree2_right,
        } },
        .{ .in_world = true },
    },
    // Liquids
    .{
        .{ .single = .water },
        .{
            .in_world = true,
            .item = true,
            .liquid = true,
        },
    },
    // empty block
    .{
        .{ .single = .none },
        .{ .in_world = true },
    },
    // Fruits
    .{
        .{
            .range = .{ .fruit_blue_lemon, .bacon },
        },
        .{ .item = true },
    },

    // specific overrides
    .{
        .{ .single = .bush },
        .{
            .strength = 1,
            .drops = .{
                .strategy = .dynamic,
                .dynamic_fn = &DropHandlers.bushDrop,
            },
        },
    },
    .{
        .{ .single = .iron },
        .{ .strength = 35 },
    },
    .{
        .{ .single = .mushroom },
        .{ .hitbox = .small_bottom_decor },
    },
    .{
        .{ .single = .mossy_stone },
        .{ .evolves_to = .spiral_plant },
    },
    .{
        .{ .single = .purple_strange_stone },
        .{ .evolves_to = .red_stone },
    },
    .{
        .{ .single = .red_stone },
        .{ .evolves_to = .redder_stone },
    },
    .{
        .{ .single = .redder_stone },
        .{ .evolves_to = .lava_stone },
    },
    .{
        .{ .list = &[_]Sprite{
            .big_tree1_left,
            .big_tree1_right,
            .big_tree2_left,
            .big_tree2_right,
        } },
        .{
            .in_world = true,
            .drops = .{
                .strategy = .static,
                .static_items = &[_]Sprite{.small_tree},
            },
        },
    },

    // Anchor rules!
    // Floor-anchored decorations/interactables
    .{
        .{ .list = &[_]Sprite{
            .rock,
            .bush,
            .mushroom,
            .big_mushroom,
            .chest,
            .small_tree,
            .big_tree1_left,
            .big_tree1_right,
            .big_tree2_left,
            .big_tree2_right,
            .portal,
            .lava_furnace,
            .forest_furnace,
        } },
        .{ .anchor = .floor },
    },
    // Ceiling-anchored decorations
    .{
        .{ .single = .ceiling_flower },
        .{ .anchor = .ceiling },
    },
    // Suspended anchor (like ceiling, but can be directly below itself too)
    .{
        .{ .single = .spiral_plant },
        .{ .anchor = .suspended },
    },
};

/// Helper function to match target variants at compile time.
fn matchesTarget(s: Sprite, target: Target) bool {
    switch (target) {
        .single => |t| return s == t,
        .range => |ra| {
            const val = @intFromEnum(s);
            const min_val = @min(@intFromEnum(ra[0]), @intFromEnum(ra[1]));
            const max_val = @max(@intFromEnum(ra[0]), @intFromEnum(ra[1]));
            return val >= min_val and val <= max_val;
        },
        .list => |list| {
            for (list) |t| {
                if (s == t) return true;
            }
            return false;
        },
    }
}

/// Recursively merges specified properties from `src` into the default/destination struct `dest`.
fn mergeProps(dest: *SpriteProps, src: SpriteProps) void {
    if (src.in_world) dest.in_world = src.in_world;
    if (src.item) dest.item = src.item;
    if (src.solid) dest.solid = src.solid;
    if (src.liquid) dest.liquid = src.liquid;
    if (src.foundation) dest.foundation = src.foundation;
    if (src.stone) dest.stone = src.stone;
    if (src.ore) dest.ore = src.ore;
    if (src.gem) dest.gem = src.gem;
    if (src.strength != 0) dest.strength = src.strength;
    if (src.hitbox != .full) dest.hitbox = src.hitbox;
    if (src.anchor != .none) dest.anchor = src.anchor;
    if (src.drops.strategy != .self or src.drops.static_items.len != 0 or src.drops.dynamic_fn != null) {
        dest.drops = src.drops;
    }
    if (src.evolves_to != null) dest.evolves_to = src.evolves_to;
}

/// Constant-time lookup of precomputed full sprite properties.
pub inline fn getSpriteProps(s: Sprite) SpriteProps {
    const val = @intFromEnum(s);
    if (val < MAX_SPRITE_ID) return dense_props_table[val];
    if (s == .unselected) return unselected_props;
    return SpriteProps{};
}

/// Evaluates compile-time rules to build properties for a specific `Sprite`.
fn getPropsForSprite(comptime s: Sprite) SpriteProps {
    @setEvalBranchQuota(70000);
    var p: SpriteProps = .{};
    for (rules) |rule| {
        if (matchesTarget(s, rule[0])) {
            mergeProps(&p, rule[1]);
        }
    }
    if (is_debug and s == .inventory_selected_invalid) {
        p.in_world = true;
        p.item = true;
    }
    return p;
}

/// Maximum valid sprite ID (exclusive upper bound for dense table).
pub const MAX_SPRITE_ID = blk: {
    @setEvalBranchQuota(1000);
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
    break :blk max_val + 1; // Make it an exclusive limit
};

/// Constant alias to map perfectly with older reference pointers.
pub const max_sprite_value = MAX_SPRITE_ID - 1;

/// Precomputed full SpriteProps LUT.
const dense_props_table: [MAX_SPRITE_ID]SpriteProps = blk: {
    @setEvalBranchQuota(20000);
    var table: [MAX_SPRITE_ID]SpriteProps = undefined;

    var i: u16 = 0;
    while (i < MAX_SPRITE_ID) : (i += 1) {
        const exists = blk2: {
            const fields = @typeInfo(Sprite).@"enum".fields;
            for (fields) |field| {
                if (field.value == i) break :blk2 true;
            }
            break :blk2 false;
        };

        if (!exists) {
            table[i] = .{};
            continue;
        }

        table[i] = getPropsForSprite(@enumFromInt(i));
    }
    break :blk table;
};

/// Precomputed compact `SpriteFlags` LUT.
const dense_flags_table: [MAX_SPRITE_ID]SpriteFlags = blk: {
    @setEvalBranchQuota(20000);
    var table: [MAX_SPRITE_ID]SpriteFlags = undefined;

    for (0..MAX_SPRITE_ID) |i| {
        const p = dense_props_table[i];
        table[i] = .{
            .in_world = p.in_world,
            .item = p.item,
            .solid = p.solid,
            .liquid = p.liquid,
            .foundation = p.foundation,
            .stone = p.stone,
            .ore = p.ore,
            .gem = p.gem,
            .hitbox = p.hitbox,
            .anchor = p.anchor,
        };
    }
    break :blk table;
};

/// Sparse fallback values for `.unselected` (65535)
const unselected_props = getPropsForSprite(.unselected);
const unselected_flags: SpriteFlags = .{
    .in_world = unselected_props.in_world,
    .item = unselected_props.item,
    .solid = unselected_props.solid,
    .liquid = unselected_props.liquid,
    .foundation = unselected_props.foundation,
    .stone = unselected_props.stone,
    .ore = unselected_props.ore,
    .gem = unselected_props.gem,
    .hitbox = unselected_props.hitbox,
    .anchor = unselected_props.anchor,
};

/// Constant-time lookup of precomputed packed sprite flags. O(1) array access.
pub inline fn getSpriteFlags(s: Sprite) SpriteFlags {
    const val = @intFromEnum(s);
    if (val < MAX_SPRITE_ID) return dense_flags_table[val];
    if (s == .unselected) return unselected_flags;
    return SpriteFlags{};
}

/// Sprite IDs with numbers based on their location in the sprite sheet.
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
    wood,
    blue_stone,
    alt_blue_stone,
    pink_stone,
    red_stone,
    seagreen_stone,
    green_stone,
    lava_stone,
    redder_stone,
    mossy_stone,
    ancient_stone,
    /// "Plain" stone type, with 2x2 variations to prevent an overly tiling look.
    stone = STONE_END,

    // ores!
    copper = ORE_START,
    iron,
    silver,
    // no gap between ores and gems: use the = GEM_START part to check we didn't skip ID indices
    gold = GEM_START - 1,

    // gems!
    amethyst = GEM_START,
    sapphire,
    emerald,
    ruby,

    // Internal assets (not valid for placement/foundation)
    gem_mask = MASK_START, // 8 masks
    hp_mask = MASK_START + 8, // 16 masks

    // Decor (THIS IS COUPLED TO WGSL CODE)
    small_tree = DECOR_START,
    big_tree1_left,
    big_tree1_right,
    big_tree2_left,
    big_tree2_right,
    fruit_blue_lemon = GEAR_ID - FRUIT_COUNT,
    fruit_teal_lemon,
    fruit_splitty,
    fruit_ruby_candy,
    copperfruit,
    ploopus1,
    ploopus2,
    divato,
    circuspin,
    bacon,
    gear = GEAR_ID,
    rock,
    bush, // 2 variations
    spiral_plant = GEAR_ID + 4,
    ceiling_flower = GEAR_ID + 5, // 2 variations
    mushroom = GEAR_ID + 7, // 3 variations
    big_mushroom = GEAR_ID + 10, // 3 variations
    forest_furnace = GEAR_ID + 13,
    lava_furnace,
    torch,
    chest,
    portal = INVENTORY_START - 1,

    /// Unselected inventory sprite.
    inventory = INVENTORY_START,
    /// Selected (currently used) inventory sprite.
    inventory_selected,
    inventory_selected_invalid, // TODO: use with mining radius
    /// Wooden-textured rounded rectangle.
    wood_icon,

    text_0 = NUMBER_START, // sprite with text 0

    /// Sprite for a particle; a full white rectangle but with corner pixels cut off.
    particle = NUMBER_START + 10,
    /// Full rectangle sprite; no corner pixels cut off.
    rectangle,
    /// Simple up arrow icon.
    arrow,
    /// Pickaxe icon.
    pickaxe,
    /// Generic water block (filled). Default internal water type.
    water = NUMBER_START + 13 + (@as(u16, @intCast(@intFromEnum(dw.mining.PickaxeType.gold))) + 1),
    water_icon,

    /// A special type used for inventory purposes. Doesn't exist as an actual sprite.
    unselected = 65535,
    _, // non-exhaustive for debugging heatmaps

    /// Retrieves the fully compile-time property data for this sprite.
    pub inline fn props(self: @This()) SpriteFlags {
        return getSpriteFlags(self);
    }

    /// Determines if the sprite's type is one that should interact with the edge flags and procedural generation.
    /// This returns false for edge stone, unlike `is_solid`. Assumes invalid block types are impossible.
    pub inline fn isFoundation(self: @This()) bool {
        return self.props().foundation;
    }

    /// Determines if the sprite's type is a valid block that could exist in any chunk.
    /// Separate from `isItem()`.
    /// Includes the empty block, and excludes entities.
    ///
    /// If this code is wrong, invalid (or unnamed) enums may appear and wreak havoc.
    pub inline fn isInWorld(self: @This()) bool {
        return self.props().in_world;
    }

    /// Determines if the sprite's type is something that could be in the player's inventory.
    pub inline fn isItem(self: @This()) bool {
        return self.props().item;
    }

    /// Determines if the sprite's type is considered solid, and should interact with the physics, player, and edge flags.
    /// This returns true for edge stone, unlike `is_solid`.
    pub inline fn isSolid(self: @This()) bool {
        return self.props().solid;
    }

    /// Determines if the sprite's type is a liquid (such as water).
    pub inline fn isLiquid(self: @This()) bool {
        return self.props().liquid;
    }

    /// Determines if the sprite's type is `none` (air/void).
    pub inline fn isEmpty(self: @This()) bool {
        return self == .none;
    }

    /// Determines if the sprite is stone (or a variation). Excludes edge stone.
    pub inline fn isStone(self: @This()) bool {
        return self.props().stone;
    }

    /// Determines if the sprite is an ore.
    pub inline fn isOre(self: @This()) bool {
        return self.props().ore;
    }

    /// Determines if the sprite is a gem.
    pub inline fn isGem(self: @This()) bool {
        return self.props().gem;
    }

    /// Returns the cascade anchoring rules for this sprite.
    pub inline fn anchor(self: @This()) AnchorKind {
        return self.props().anchor;
    }

    /// Determines if the sprite is a heatmap (between types 65000-65256).
    pub inline fn isHeatmap(self: @This()) bool {
        const id = @intFromEnum(self);
        return is_debug and id >= 65000 and id <= 65256;
    }

    /// Extracts the evolved form of this sprite at compile time.
    /// If it doesn't evolve, returns itself!
    pub inline fn evolvesTo(self: @This()) Sprite {
        const val = @intFromEnum(self);
        if (val < MAX_SPRITE_ID) {
            if (dense_props_table[val].evolves_to) |evolution| {
                return evolution;
            }
        }
        return self;
    }

    /// Returns whether a block is empty (air), a liquid, or a waterloggable decoration.
    /// Precondition: the sprite is valid.
    pub inline fn isFlowable(self: @This()) bool {
        return self.isEmpty() or self.isLiquid() or self.isDecor();
    }

    /// Returns whether a sprite is a decoration block.
    /// Precondition: the sprite is valid.
    pub inline fn isDecor(self: @This()) bool {
        const val = @intFromEnum(self);
        return val >= DECOR_START and !self.isSolid() and self != .water;
    }
};

/// The total number of valid sprites that are considered valid items.
pub const item_sprite_count: usize = blk: {
    @setEvalBranchQuota(1e6);
    var count: usize = 0;
    for (0..MAX_SPRITE_ID) |i| {
        if (dense_flags_table[i].item) count += 1;
    }
    if (unselected_flags.item) count += 1;
    break :blk count;
};

/// An array of all `Sprite` values that could be items using lookups.
pub const possible_item_sprites = blk: {
    @setEvalBranchQuota(1e6);
    const fields = @typeInfo(Sprite).@"enum".fields;
    var result: [item_sprite_count]Sprite = undefined;
    var index: usize = 0;

    for (fields) |field| {
        const sprite: Sprite = @enumFromInt(field.value);
        if (sprite.isItem()) {
            result[index] = sprite;
            index += 1;
        }
    }
    break :blk result;
};

/// Empty block of id `Sprite.none`.
pub const AIR_BLOCK: memory.Block = .{
    .id = .none,
    .seed = 0,
    .light = 0,
    .hp = 0,
    .edge_flags = 0xFF,
};

// Comptime sanity validation check
comptime {
    @setEvalBranchQuota(1e6);
    if ((@as(Sprite, @enumFromInt(65535))).isInWorld())
        @compileError("isInWorld() returned true for the unselected type! Ranges are wrong.");

    var i: u16 = 0;
    var wentToHeatmap = false;
    while (i < 65535) : (i += 1) {
        if (!wentToHeatmap and i == max_sprite_value + 256) {
            i = 60000;
            wentToHeatmap = true;
        }
        const s: Sprite = @enumFromInt(i);
        if (s.isInWorld()) {
            var is_mapped = false;
            for (@typeInfo(Sprite).@"enum".fields) |field| {
                if (field.value == i) {
                    is_mapped = true;
                    break;
                }
            }
            if (!is_mapped) {
                @compileError("isInWorld() returned true for an unmapped sprite ID! Ranges are wrong.");
            }
        }
    }
}
