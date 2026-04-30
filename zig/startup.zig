//! Contains initialization and render update functions. See root.zig for exporting these functions (and others) to WASM.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const sprite = root.sprite;
const logger = root.logger;
const seeding = root.seeding;
const world = root.world;
const player = root.player;

const CHUNK_SIZE = memory.CHUNK_SIZE;
const CHUNK_SIZE_SQ = memory.CHUNK_SIZE_SQ;
const CHUNK_SIZE_FLOAT = memory.CHUNK_SIZE_FLOAT;
const SUBPIXELS_IN_CHUNK = memory.SUBPIXELS_IN_CHUNK;

/// Sets the number of times the push_layer function is called at the start.
/// If set to n, the game will start off by being n ** ZOOM_FACTOR chunks in either dimension.
pub const STARTING_ZOOM_TIMES = 2;
/// Sets the player's spawn randomly (if `STARTING_ZOOM_TIMES` is positive).
const SET_PLAYER_SPAWN_RANDOMLY = true;

const _ = {
    if (STARTING_ZOOM_TIMES < 1 or STARTING_ZOOM_TIMES > 4) {
        @compileError("STARTING_ZOOM_TIMES must be between 1 and 4 to prevent floating point or logic issues!");
    }
};

var alreadyStarted = false;

/// Initializes the game.
pub fn init() void {
    if (!alreadyStarted) {
        alreadyStarted = true;
        logger.log(@src(), "Hello from Zig!", .{});
    }
    var temp_seed = seeding.ChaCha12.init(seeding.mixBaseSeed(&memory.game.seed, 1));
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
    var rng = seeding.ChaCha12.init(seeding.mixBaseSeed(&memory.game.seed, 2));
    for (0..STARTING_ZOOM_TIMES) |_| {
        // Set the player position to somewhere random in the current chunk
        if (SET_PLAYER_SPAWN_RANDOMLY) memory.game.setPlayerPosDumb(.{
            @intCast(rng.next() & (memory.SUBPIXELS_IN_CHUNK - 1)),
            @intCast(rng.next() & (memory.SUBPIXELS_IN_CHUNK - 1)),
        });

        world.pushLayer(
            .none,
            memory.game.getPlayerCoord(),
            memory.game.getBlockXInChunk(), // convert a subpixel (0-4095) in a chunk to a block in a chunk (0-15)
            memory.game.getBlockYInChunk(),
        );
    }

    if (SET_PLAYER_SPAWN_RANDOMLY) {
        findSafeSpawn();
        // world.SimBuffer.sync(memory.game.getPlayerCoord(), .{ 16, 16 });
    }
}

/// Searches for a safe grounded spawn point by spiraling through CHUNKS
/// and scanning all blocks within those chunks.
pub fn findSafeSpawn() void {
    const game = &memory.game;
    const start_coord = game.getPlayerCoord();

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
            world.writeChunk(&chunk, nc);

            // Scan the chunk for a "safe" spot!
            var y: usize = 0;
            while (y < CHUNK_SIZE - 1) : (y += 1) {
                const row = y * CHUNK_SIZE;
                const column = (y + 1) * CHUNK_SIZE;

                for (0..CHUNK_SIZE) |x| {
                    const block = chunk.blocks[row + x];
                    const block_below = chunk.blocks[column + x];

                    if (block.isEmpty() and block_below.isSolid()) {
                        // Found a valid floor!
                        game.player_quadrant = nc.quadrant;
                        game.player_chunk = nc.suffix;

                        game.setPlayerPosDumb(.{
                            @as(i64, @intCast(x)) * CHUNK_SIZE_SQ + (CHUNK_SIZE_SQ / 2),
                            @as(i64, @intCast(y)) * CHUNK_SIZE_SQ + (CHUNK_SIZE_SQ / 2) - 1, // -1 or you have to jump to move
                        });

                        game.setCameraPosDumb(game.player_pos);
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
    game.setPlayerPosDumb(.{ 2048, 2048 });
}
