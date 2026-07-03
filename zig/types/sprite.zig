const std = @import("std");
const dw = @import("../root.zig");

const is_debug = dw.is_debug;
const memory = dw.memory;
const procedural = dw.procedural;

const Coordinate = dw.world.Coordinate;

// Drop resolution lives in `state/drops.zig`.
const DropConfig = dw.drops.DropConfig;
const DropHandlers = dw.drops.DropHandlers;

/// Index where stone-like sprites begin.
pub const STONE_START = 6;
/// Index where stone-like sprites end.
const STONE_END = STONE_START + 14;

/// Index where smelted bar sprites begin.
const BAR_START = STONE_END + 4;

/// Index where ore sprites begin.
pub const ORE_START = BAR_START + 6;

/// Index where gem sprites begin.
pub const GEM_START = ORE_START + 6;

/// Number of gem types.
pub const GEM_COUNT = 5;

/// Index where gem masks (not gem sprites) begin.
pub const MASK_START = GEM_START + GEM_COUNT * 2;
/// Index after the HP mask ends, and decorations begin.
const DECOR_START = MASK_START + 24;

/// Number of fruit sprites.
const FRUIT_COUNT = 10;
/// ID for `Sprite.gear`, which is after a list of fruit drops.
const GEAR_ID = DECOR_START + 5 + FRUIT_COUNT;

/// Index where inventory slot sprites start.
pub const INVENTORY_START = GEAR_ID + 21;
/// Index where numbers (0-9) start.
pub const NUMBER_START = INVENTORY_START + 4;

/// Sprite IDs with numbers based on their location in the sprite sheet.
pub const Sprite = enum(u16) {
    /// Empty (air) sprite.
    none = 0,
    /// Sprite of the player.
    player = 1,

    /// Edge stone (2 variations).
    edge_stone = 2,

    wood = 4,
    white_plate,

    // stone types!
    blue_strange_stone = STONE_START,
    purple_strange_stone,
    blue_stone,
    alt_blue_stone,
    pink_stone,
    purple_stone,
    red_stone,
    redder_stone,
    lava_stone,
    mossy_stone,
    seagreen_stone,
    green_stone,
    ancient_stone,
    sulfuric_stone,
    /// "Plain" stone type, with 2x2 variations to prevent an overly tiling look.
    stone = STONE_END,

    // smelted bars! (item-only product of smelting ore; parallel to the ore range below)
    copper_bar = BAR_START,
    iron_bar,
    silver_bar,
    gold_bar,
    nickel_bar,
    cobalt_bar,

    // ores!
    copper = ORE_START, // notice how these constants help with fixing gaps/misplacements
    iron,
    silver,
    gold,
    nickel,
    cobalt,

    // gems!
    quartz = GEM_START,
    amethyst,
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
    campfire, // 4 variations
    chest = GEAR_ID + 15 + 4,
    portal = INVENTORY_START - 1,

    /// Unselected inventory sprite.
    inventory = INVENTORY_START,
    /// Selected (currently used) inventory sprite.
    inventory_selected,
    inventory_selected_red,
    /// Wooden-textured rounded rectangle.
    wood_icon,

    text_0 = NUMBER_START, // sprite with text 0

    /// Sprite for a particle; a full white rectangle but with corner pixels cut off.
    particle = NUMBER_START + 10,
    /// Full rectangle sprite; no corner pixels cut off.
    rectangle,
    /// Simple up-arrow icon.
    arrow,

    /// Quarter portion of a center part of the progress bar that is unfilled.
    progress_small_unfilled = NUMBER_START + 13,
    /// Quarter portion of a center part of the progress bar that is unfilled.
    progress_small_filled,
    /// Leftmost part of the progress bar.
    progress_left = NUMBER_START + 15,
    /// Center part of the progress bar.
    progress_center = NUMBER_START + 20,
    /// Right part of the progress bar.
    progress_right = NUMBER_START + 25,

    /// Pickaxe icon.
    pickaxe = NUMBER_START + 30,
    /// Generic water block (filled). Default internal water type; after all pickaxes.
    water = NUMBER_START + 30 + (@as(u16, @intCast(@intFromEnum(dw.mining.PickaxeType.gold))) + 1),
    water_icon,

    /// A special type used for inventory purposes. Doesn't exist as an actual sprite.
    unselected = 65535,
    _, // non-exhaustive for debugging heatmaps

    /// Retrieves the fully compile-time property data for this sprite.
    pub inline fn props(self: @This()) SpriteFlags {
        const val = @intFromEnum(self);
        if (val < MAX_SPRITE_ID) return dense_flags_table[val];
        if (self == .unselected) return unselected_flags;
        return .{};
    }

    /// Determines if the sprite's type is one that should interact with the edge flags and procedural generation.
    /// This returns false for edge stone, unlike `isSolid()`. Assumes invalid block types are impossible.
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
    /// This returns true for edge stone, unlike `isSolid()`.
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

    /// Maps an ore sprite to its smelted bar form.
    /// The bar range is parallel to and sits directly before the ore range,
    /// so the mapping is a constant offset. Precondition: `self.isOre()`.
    pub inline fn oreToBar(self: @This()) Sprite {
        return @enumFromInt(@intFromEnum(self) - (ORE_START - BAR_START));
    }

    /// Determines if the sprite is a gem.
    pub inline fn isGem(self: @This()) bool {
        return self.props().gem;
    }

    /// True for ore/gem overlay sprites since those composited over a `base_id` stone underlay.
    /// Ores and gems form one contiguous id range, so this is a single bounds test rather than two `props()` lookups
    /// (`isOre() or isGem()`); a comptime check tries to keep the ranges in sync.
    pub inline fn isOverlay(self: @This()) bool {
        const id = @intFromEnum(self);
        return id >= ORE_START and id < GEM_START + GEM_COUNT;
    }

    /// Returns the cascade anchoring rules for this sprite.
    pub inline fn anchor(self: @This()) AnchorKind {
        return self.props().anchor;
    }

    /// Returns the broad `Category` classification for this sprite.
    pub inline fn category(self: @This()) Category {
        return self.props().category;
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
        return self.props().category == .decor;
    }

    /// Converts a sprite into an entity ID, handling atlas ID remaps.
    pub inline fn asEntity(self: @This()) u32 {
        const id = @intFromEnum(self);
        return if (id >= GEM_START and id < GEM_START + GEM_COUNT) id + GEM_COUNT else if (self.isLiquid()) id + 1 else id;
    }
};

/// Centralized database describing all sprite properties.
/// Rules are checked in order, with later rules overriding earlier ones.
const rules = [_]SpriteRule{
    // Non-stone solid blocks
    .{
        .{ .list = &[_]Sprite{ .wood, .white_plate } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .strength = 40,
        },
    },
    // Stone blocks
    .{
        .{ .range = .{ .blue_strange_stone, .stone } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .stone = true,
            .category = .stone,
            .strength = 15,
        },
    },
    // Smelted bars (inventory items only; not placeable in the world)
    .{
        .{ .range = .{ .copper_bar, .cobalt_bar } },
        .{ .item = true, .category = .bar },
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
            .lava_furnace,   .campfire, .chest,        .portal,
        } },
        .{
            .in_world = true,
            .item = true,
            .category = .decor,
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
        .{ .in_world = true, .category = .decor },
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

    // Fruits and drop overrides
    .{
        .{
            .range = .{ .fruit_blue_lemon, .bacon },
        },
        .{ .item = true },
    },
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

    // Ores
    .{
        .{ .range = .{ .copper, .cobalt } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .ore = true,
            .category = .ore,
            .strength = 30,
        },
    },
    // Gems
    .{
        .{ .range = .{ .quartz, .ruby } },
        .{
            .in_world = true,
            .item = true,
            .solid = true,
            .foundation = true,
            .gem = true,
            .category = .gem,
            .strength = 15,
        },
    },

    // Ore/gem strengths
    .{
        .{ .single = .iron },
        .{ .strength = 35 },
    },
    .{
        .{ .single = .silver },
        .{ .strength = 45 },
    },
    .{
        .{ .single = .gold },
        .{ .strength = 60 },
    },
    .{
        .{ .single = .nickel },
        .{ .strength = 70 },
    },
    .{
        .{ .single = .cobalt },
        .{ .strength = 90 },
    },
    .{
        .{ .single = .amethyst },
        .{ .strength = 75 },
    },
    .{
        .{ .single = .sapphire },
        .{ .strength = 85 },
    },
    .{
        .{ .single = .emerald },
        .{ .strength = 95 },
    },
    .{
        .{ .single = .ruby },
        .{ .strength = 100 },
    },

    // Evolution rules on depth increase
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

    // For 2x1 trees, drop 1x1
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
            .campfire,
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

/// Broad classification of a sprite, replacing scattered ID-range arithmetic.
/// Add new variants freely; `Category` is `u3`, so up to 8 fit in `SpriteFlags`.
pub const Category = enum(u3) {
    /// No special category (air, masks, UI, water, edge stone, misc solids).
    none = 0,
    stone,
    ore,
    gem,
    /// Smelted bar (inventory-only item).
    bar,
    /// World decoration (non-solid placeable: plants, furniture, interactables).
    decor,
};

/// Consolidated properties of each sprite.
pub const SpriteProps = struct {
    in_world: bool = false,
    // This can be defaulted to true for debugging and potentially testing sprite misalignment.
    item: bool = false,
    solid: bool = false,
    liquid: bool = false,
    foundation: bool = false,
    stone: bool = false,
    ore: bool = false,
    gem: bool = false,
    category: Category = .none,
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
    category: Category = .none, // 3 bits (fills the former padding, keeping the struct 16-bit)
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
    if (src.category != .none) dest.category = src.category;
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
            .category = p.category,
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
    .category = unselected_props.category,
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

// Comptime sanity validation check
comptime {
    @setEvalBranchQuota(1e6);
    if ((@as(Sprite, @enumFromInt(65535))).isInWorld())
        @compileError("isInWorld() returned true for the unselected type! Ranges are wrong.");

    // `oreToBar()` relies on the bar range sitting directly before the ore range with the same
    // length, so the mapping is a single constant offset. Enforce that here.
    if (ORE_START - BAR_START != GEM_START - ORE_START)
        @compileError("Bar range is not parallel to the ore range; oreToBar() would be wrong.");

    // isOverlay() bounds-tests one contiguous ore+gem range; verify it matches the props table exactly.
    var o: u16 = 0;
    while (o < MAX_SPRITE_ID) : (o += 1) {
        const s: Sprite = @enumFromInt(o);
        if (s.isOverlay() != (s.isOre() or s.isGem()))
            @compileError("isOverlay() range drifted from ore/gem props; fix ORE_START/GEM_START/GEM_COUNT.");
    }

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
