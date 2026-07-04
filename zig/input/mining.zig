//! Handles mining and placing blocks.
const std = @import("std");
const dw = @import("../root.zig");
const sprite = dw.sprite;
const Sprite = sprite.Sprite;
const memory = dw.memory;
const inventory = dw.inventory;
const world = dw.world;
const mouse = dw.mouse;

/// How far the player has progressed to increase `hp`.
pub var mining_progress: u64 = 0;

/// How much the player increases `mining_progress` every tick.
pub var mining_speed: u64 = 8;

/// How much `hp` the tool takes off the block every time `mining_progress` reaches the block's strength.
pub var mining_strength: u4 = 1;

/// Current selected block's HP. Should be from 0-15 normally, and 255 if block is empty.
pub var selected_hp: u8 = 0;

/// Frame for mining (for sound effects); reset when not mining for long enough with `not_mining_frame`.
pub var mining_frame: u64 = 0;

/// Frame count for not mining.
pub var not_mining_frame: u64 = 0;

/// List of possible pickaxe type options (player starts with stone).
pub const PickaxeType = enum {
    stone,
    bronze,
    iron,
    silver,
    gold,
};

/// Type of pickaxe equipped.
pub var pickaxe_type: PickaxeType = .stone;

/// Updates mining and placing blocks. Should be called from `tick()` inside root.zig.
pub fn handleMiningAndPlacing(logic_speed: f64) void {
    mouse.updateMouseLocation(); // update to get correct mouse position data

    if (mouse.block_position_changed) {
        mouse.block_position_changed = false;
        mining_progress = 0;
    }

    // Only allow mining if the click focus is currently dedicated to the world canvas.
    // This prevents drag-clicks from bleeding into mining actions.
    if (mouse.click_focus != .canvas) {
        selected_hp = 255;
        return;
    }

    mouse.updateMouseLocation(); // update to get correct mouse position data

    const sprite_type = inventory.selected_sprite;
    if (sprite_type == .unselected) {
        selected_hp = 255;
        return;
    }

    const mouse_block = mouse.getMouseBlock();
    if (mouse_block) |block| {
        // Don't mine a block of the same type you're trying to place!
        if (sprite_type != .none and block.id == sprite_type) {
            selected_hp = 0;
            mining_progress = 0;
            return;
        }

        // Are we breaking something, or placing into empty air?
        if (sprite_type.isEmpty() or !block.isEmpty()) {
            // mining or replacing case
            mining_progress += if (logic_speed == 1.0)
                mining_speed
            else
                @as(u64, @intFromFloat(@as(f64, @floatFromInt(mining_speed)) * logic_speed));
            const in_creative = inventory.isInCreative();

            const strength = getSpriteStrength(block.id) orelse std.math.maxInt(u64);

            // Chip particles while actively mining; better pickaxes chip more often and in bigger "clusters".
            if (!block.isEmpty() and strength > 0) {
                if (mouse.getMouseBlockCenterPx()) |center| {
                    const power: f32 = @floatFromInt(@intFromEnum(pickaxe_type));
                    dw.particles.maybeSpawnSpriteBurst(
                        0.15 + 0.06 * power,
                        block.id,
                        center,
                        .{
                            .count = if (!in_creative and strength == std.math.maxInt(u64))
                                1
                            else
                                5 + @as(usize, @intFromEnum(pickaxe_type)) * 2,
                        },
                    );
                }
            }

            if (in_creative or (strength != std.math.maxInt(u64) and mining_progress >= strength) and
                (!block.isLiquid() or block.hp == memory.Block.MAX_HP))
            {
                mining_progress = 0;
                // sprite type being none check also prevents unneeded memory waste with data update
                const was_deleted = block.isEmpty() or world.modifyBlockHp(
                    mouse.mouse_chunk_coord.?, // mouse block successful, this must be valid then!
                    mouse.mouse_block_x,
                    mouse.mouse_block_y,
                    block,
                    // instantly mine (0 value special-case in modifyBlockHp) if block type has no strength
                    if (!in_creative and strength > 0) mining_strength else 0,
                );

                {
                    // Sound effects time!
                    if (block.isFoundation()) {
                        @setFloatMode(.optimized);
                        const FRAMES_PER_SOUND = if (in_creative)
                            3
                        else
                            std.math.clamp(240 / (mining_speed - 1) + 1, 3, 12);
                        not_mining_frame = 0;
                        // create a mining sound every so often!
                        if (mining_frame % FRAMES_PER_SOUND == 0)
                            dw.sound.playSound(
                                @intCast((mining_frame / FRAMES_PER_SOUND) % 3 + 1),
                                if (in_creative) 1 else (0.4 + 0.6 * @as(f32, @floatFromInt(mining_strength))),
                                0.2,
                                if (block.isGem()) 0.7 else if (block.isOre()) 0.55 else 0.45,
                            );
                        mining_frame +%= 1;
                    } else if (was_deleted and !block.isEmpty() and !block.isFoundation()) {
                        not_mining_frame = 0;
                        // play a grassy sound
                        dw.sound.playSound(
                            4 + (memory.game.frame % 2),
                            0.3, // 30% volume
                            0.1,
                            0.3,
                        );
                    }
                }

                if (was_deleted) {
                    if (!block.isEmpty()) {
                        // The block broke: burst of its own colors, larger with better pickaxes.
                        if (mouse.getMouseBlockCenterPx()) |center| {
                            dw.particles.spawnSpriteBurst(block.id, center, .{
                                .count = 20,
                                .speed_max = 2.4,
                            });
                        }

                        if (block.isFoundation()) memory.game.blocks_mined +%= 1;
                        inventory.dropItem(
                            block.id,
                            mouse.mouse_chunk_coord.?,
                            mouse.mouse_block_x,
                            mouse.mouse_block_y,
                        );

                        // Only auto-replace if the block being mined is different from the held item.
                        if (sprite_type.isInWorld()) {
                            if (inventory.removeFromInventory(sprite_type)) { // make sure it's possible to use
                                if (world.modifyBlockType(
                                    mouse.mouse_chunk_coord.?, // mouse block successful already
                                    mouse.mouse_block_x,
                                    mouse.mouse_block_y,
                                    sprite_type,
                                    block, // pre-mined block seeds the ore's underlay (see modifyBlockType)
                                )) {
                                    // If TRUE, then the block was NOT successfully modified. Revert selection if so.
                                    // This fixes funny issues involving deselection due to invalid placement
                                    inventory.selected_sprite = sprite_type;
                                }

                                mining_progress = 0;
                                selected_hp = 0;
                                return;
                            }
                        }
                    }

                    selected_hp = 255;
                } else if (block.isLiquid()) {
                    selected_hp = block.hp + mining_strength;
                }
            }
        } else if (block.isEmpty() and sprite_type.isInWorld()) {
            // placing into empty air!
            if (inventory.removeFromInventory(sprite_type)) {
                if (world.modifyBlockType(
                    mouse.mouse_chunk_coord.?,
                    mouse.mouse_block_x,
                    mouse.mouse_block_y,
                    sprite_type,
                    block, // empty here (placing into air), so ores fall back to a plain-stone underlay
                )) {
                    // If TRUE, then the block was NOT successfully modified. Revert selection if so.
                    // This fixes funny issues involving instant deselection with invalid placement
                    // (for example: placing your last ceiling flower in an invalid spot would deselect without this)
                    inventory.selected_sprite = sprite_type;
                } else {
                    dw.sound.playSound(
                        6,
                        if (sprite_type.isFoundation()) 0.75 else 0.2,
                        0.1,
                        0.2,
                    );
                }
                selected_hp = 0;
                mining_progress = 0;
            }
        }
    } else {
        not_mining_frame +%= 1;
        if (not_mining_frame == 60) mining_frame = 0;
        selected_hp = 255;
    }

    // pickaxe upgrade testing (auto-upgrades)
    if (memory.game.blocks_mined >= 40) {
        pickaxe_type = .gold;
        mining_speed = 20;
        mining_strength = 2;
    } else if (memory.game.blocks_mined >= 20) {
        pickaxe_type = .silver;
        mining_speed = 12;
        mining_strength = 2;
    } else if (memory.game.blocks_mined >= 8) {
        pickaxe_type = .iron;
        mining_speed = 15;
    } else if (memory.game.blocks_mined >= 4) {
        pickaxe_type = .bronze;
        mining_speed = 11;
    }
}

/// Returns how "strong" a `Sprite` is; how much mining_progress must be contributed to increase `hp` of a block.
inline fn getSpriteStrength(s: Sprite) ?u64 {
    const props = sprite.getSpriteProps(s);
    if (!props.in_world) return null;
    if (!props.solid or props.instant_mine) return 0;
    if (props.strength == 0) return null;
    return props.strength;
}

comptime {
    for (@typeInfo(Sprite).@"enum".fields) |field| {
        const field_sprite: Sprite = @enumFromInt(field.value);
        if (std.mem.eql(u8, field.name, "_") or
            std.mem.eql(u8, field.name, "unselected")) continue;

        // If it's a valid, solid block, it MUST have a defined mining strength.
        if (field_sprite.isInWorld() and field_sprite.isFoundation()) {
            if (getSpriteStrength(field_sprite) == null) {
                @compileError("Sprite is valid and foundation but has strength value of 0 in get_sprite_strength: " ++ field.name);
            }
        }
    }
}
