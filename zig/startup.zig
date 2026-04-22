//! Contains initialization and render update functions. See root.zig for exporting these functions (and others) to WASM.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const sprite = root.sprite;
const logger = root.logger;
const seeding = root.seeding;
const world = root.world;
const player = root.player;

const SPAN = memory.SPAN;
const SPAN_SQ = memory.SPAN_SQ;
const SPAN_FLOAT = memory.SPAN_FLOAT;
const SUBPIXELS_IN_CHUNK = memory.SUBPIXELS_IN_CHUNK;

/// Sets the number of times the push_layer function is called at the start. (If set to 3 (default), the game will start off by being 4096x4096 chunks. If set to 1, for example, it will be 1 chunk with 16x16 blocks instead.)
pub const STARTING_ZOOM_TIMES = 3;
/// Sets the player's spawn randomly (if `STARTING_ZOOM_TIMES` > 0).
const SET_PLAYER_SPAWN_RANDOMLY = true;

var alreadyStarted = false;

/// Initializes the game.
pub fn init() void {
    if (!alreadyStarted) {
        alreadyStarted = true;
        logger.log(@src(), "Hello from Zig!", .{});
    }
    var temp_seed = seeding.ChaCha12.init(seeding.mix_base_seed(&memory.game.seed, 1));
    memory.game.seed2 = .{
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
        temp_seed.next(),
    };
    // Start off by determining where the player starts off exactly with layer pushing
    var rng = seeding.ChaCha12.init(seeding.mix_base_seed(&memory.game.seed, 2));
    for (0..STARTING_ZOOM_TIMES) |_| {
        // Set the player position to somewhere random in the current chunk
        if (SET_PLAYER_SPAWN_RANDOMLY) memory.game.set_player_pos(.{
            @intCast(rng.next() & (memory.SUBPIXELS_IN_CHUNK - 1)),
            @intCast(rng.next() & (memory.SUBPIXELS_IN_CHUNK - 1)),
        });

        world.push_layer(
            .none,
            memory.game.get_player_coord(),
            memory.game.get_block_x_in_chunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.get_block_y_in_chunk(),
        );
    }

    if (SET_PLAYER_SPAWN_RANDOMLY) {
        find_safe_spawn();
        // world.SimBuffer.sync(memory.game.get_player_coord(), .{ 16, 16 });
    }
}

/// Searches for a safe grounded spawn point by spiraling through CHUNKS
/// and scanning all blocks within those chunks.
pub fn find_safe_spawn() void {
    const game = &memory.game;
    const start_coord = game.get_player_coord();

    var chunk: memory.Chunk = undefined; // temp buffer for performance

    // Spiral parameters (on increments of chunks)
    var side_len: i64 = 1;
    var dx: i64 = 1;
    var dy: i64 = 0;
    var segment_passed: i64 = 0;
    var cx: i64 = 0;
    var cy: i64 = 0;

    // check up to 500 chunks, in case there's some weird issues
    var i: u32 = 0;
    while (i < 500) {
        if (start_coord.move(.{ cx, cy })) |nc| {
            world.write_chunk(&chunk, nc);

            // Scan the chunk for a "safe" spot!
            var y: usize = 0;
            while (y < SPAN - 1) : (y += 1) {
                const row_idx = y * SPAN;
                const below_idx = (y + 1) * SPAN;

                for (0..SPAN) |x| {
                    const block = chunk.blocks[row_idx + x];
                    const block_below = chunk.blocks[below_idx + x];

                    if (block.is_empty() and block_below.is_solid()) {
                        // Found a valid floor!
                        game.player_quadrant = nc.quadrant;
                        game.player_chunk = nc.suffix;

                        game.set_player_pos(.{
                            @as(i64, @intCast(x)) * SPAN_SQ + (SPAN_SQ / 2),
                            @as(i64, @intCast(y)) * SPAN_SQ + (SPAN_SQ / 2) - 1, // -1 or you have to jump to move
                        });

                        game.set_camera_pos(game.player_pos);
                        return;
                    }
                }
            }

            i += 1; // increment i for next loop iter
        }

        // Update spiral to next CHUNK
        cx += dx;
        cy += dy;
        segment_passed += 1;
        if (segment_passed >= side_len) {
            segment_passed = 0;
            const temp = dx;
            dx = -dy;
            dy = temp;
            if (dy == 0) side_len += 1;
        }
    }

    // Fallback: If no ground found in nearby chunks, center in current chunk
    game.set_player_pos(.{ 2048, 2048 });
}
