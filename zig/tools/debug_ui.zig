//! Handles debug options for sliders and buttons, and contains functions to pass these to JS.
const std = @import("std");
const root = @import("root").root;
const main = root.startup;
const logger = root.logger;
const memory = root.memory;
const world = root.world;
const player = root.player;
const seeding = root.seeding;
const procedural = root.procedural;

pub const SliderDef = struct {
    name: []const u8,
    min: f64,
    max: f64,
    val: *f64,
    on_change: ?*const fn (f64) void = null,
    regen: bool = false,
};

pub const ButtonDef = struct {
    name: []const u8,
    action: ?*const fn () void = null,
    toggle: ?*bool = null,
    regen: bool = false,
};

/// List of sliders (with a range that modifies a numeric variable)
pub const sliders = [_]SliderDef{
    .{
        .name = "Procedural scale",
        .min = 0.1,
        .max = 5.0,
        .val = &procedural.procedural_cell_size,
        .regen = true,
    },
    .{
        .name = "FBM (random domain warping) power",
        .min = 0.0,
        .max = 5.0,
        .val = &procedural.fbm_power,
        .regen = true,
    },
    .{
        .name = "Minimum stone density cutoff",
        .min = 0.0,
        .max = 1.0,
        .val = &procedural.density_min,
        .regen = true,
    },
    .{
        .name = "Maximum stone density cutoff",
        .min = 0.0,
        .max = 1.0,
        .val = &procedural.density_max,
        .regen = true,
    },
    .{
        .name = "Odds for gems to spawn",
        .min = 0.0,
        .max = 1.0,
        .val = &procedural.base_gem_odds,
        .regen = true,
    },
    .{
        .name = "Base player speed",
        .min = 0.1,
        .max = 10.0,
        .val = &player.PLAYER_BASE_SPEED,
    },
    .{
        .name = "Base player gravity",
        .min = 0.01,
        .max = 2.0,
        .val = &player.GRAVITY,
    },
    .{
        .name = "Jump force",
        .min = 1.0,
        .max = 50.0,
        .val = &player.JUMP_FORCE,
    },
    .{
        .name = "Friction (x-axis)",
        .min = 0.0,
        .max = 1.0,
        .val = &player.FRICTION_X,
    },
    .{
        .name = "Friction (y-axis)",
        .min = 0.0,
        .max = 1.0,
        .val = &player.FRICTION_Y,
    },
};

/// List of buttons that point to actions.
pub const buttons = [_]ButtonDef{
    .{
        .name = "Teleport to edge",
        .action = teleportToEdge,
    },
    .{
        .name = "Teleport randomly",
        .action = teleportRandomly,
    },
    .{
        .name = "Toggle base heatmap",
        .toggle = &procedural.USE_BASE_HEATMAP,
        .regen = true,
    },
    .{
        .name = "Toggle ore heatmap",
        .toggle = &procedural.USE_ORE_HEATMAP,
        .regen = true,
    },
    .{
        .name = "Toggle showing all items",
        .toggle = &root.inventory.SHOW_ALL_INVENTORY_ITEMS,
    },
};

/// Teleports to the top left quadrant. Then, tries to find a valid spawn point.
fn teleportToEdge() void {
    memory.game.teleport(
        .{ .quadrant = 0, .suffix = .{ 0, 0 } },
        .{ memory.SPAN_SQ * 5 / 2, memory.SPAN_SQ * 5 / 2 },
    );
    main.findSafeSpawn();
}

/// Teleports to a random valid coordinate (chunk) within the same quadrant. Then, tries to find a valid spawn point.
fn teleportRandomly() void {
    const game = &memory.game;
    const h1 = seeding.FastHash.hash2d(
        game.player_chunk & memory.v2u64{ game.seed2[0], game.seed2[1] },
        @intCast(game.player_pos[0]),
        @intCast(game.player_pos[1]),
    );
    const h2 = seeding.FastHash.hash2d(
        game.player_chunk & memory.v2u64{ game.seed2[2], game.seed2[3] },
        @intCast(game.player_pos[0]),
        @intCast(game.player_pos[1]),
    );
    game.teleport(
        .{ .quadrant = 0, .suffix = .{
            h1 & world.max_possible_suffix,
            h2 & world.max_possible_suffix,
        } },
        .{ 2048, 2048 },
    );
    main.findSafeSpawn();
}

pub fn changeSlider(id: u32, val: f64) void {
    if (id >= sliders.len and id < 0) @panic("Slider ID invalid!");
    const s = sliders[id];
    s.val.* = val;
    if (s.on_change) |func| {
        func(val);
    }
    if (s.regen) {
        world.clearCaches();
    }
}

pub fn clickButton(id: u32) void {
    if (id >= buttons.len and id < 0) @panic("Button ID invalid!");

    const b = buttons[id];
    if (b.action) |func| {
        func();
    }
    if (b.toggle) |value| {
        value.* = !value.*;
    }
    if (b.regen) {
        world.clearCaches();
    }
}

pub fn buildMetadata() void {
    var arena = memory.makeArena();
    defer arena.deinit();

    var out: std.Io.Writer.Allocating = .init(arena.allocator());

    var ws: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{},
    };

    // Start root object
    ws.beginObject() catch return;

    // Now, add "sliders" field and start array
    ws.objectField("sliders") catch return;
    ws.beginArray() catch return;

    for (sliders, 0..) |s, i| {
        ws.beginObject() catch return;

        ws.objectField("id") catch return;
        ws.write(i) catch return;

        ws.objectField("name") catch return;
        ws.write(s.name) catch return;

        ws.objectField("min") catch return;
        ws.write(s.min) catch return;

        ws.objectField("max") catch return;
        ws.write(s.max) catch return;

        ws.objectField("val") catch return;
        ws.write(s.val.*) catch return;

        ws.endObject() catch return;
    }
    ws.endArray() catch return;

    // Add "buttons" field and start array
    ws.objectField("buttons") catch return;
    ws.beginArray() catch return;
    for (buttons, 0..) |b, i| {
        ws.beginObject() catch return;
        ws.objectField("id") catch return;
        ws.write(i) catch return;
        ws.objectField("name") catch return;
        ws.write(b.name) catch return;
        ws.endObject() catch return;
    }
    ws.endArray() catch return;

    ws.endObject() catch return; // Finish!

    const written = out.written();
    memory.scratchReset();
    const scratch_ptr = memory.scratchAlloc(written.len);
    @memcpy(scratch_ptr[0..written.len], written);
}
