/*
 * Main shader for Depthwell. ADD ?raw FOR DEBUGGING SHADER TO THE END OF engineMaker.ts's `SHADER_SOURCE` VARIABLE TO NOT COMPRESS.
 */

// These are sprite sheet constants. Sprites are saved as a .png, and each asset is 16x16.
// See zig/world.zig's Sprite definitions for sprite type list.
// These const values values with /* VARIABLE_NAME */ are dynamically patched in from TypeScript, so do not set them here.
const TILES_PER_ROW: f32 = /* TILES_PER_ROW */ 1 /* TILES_PER_ROW */;
const TILES_PER_COLUMN: f32 = /* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */;
const STONE_START: u32 = /* STONE_START */ 1 /* STONE_START */;
const ORE_START: u32 = /* ORE_START */ 1 /* ORE_START */;
const GEM_START: u32 = /* GEM_START */ 1 /* GEM_START */;
const GEM_MASK_START: u32 = /* GEM_MASK_START */ 1 /* GEM_MASK_START */;
const DECOR_START: u32 = /* DECOR_START */ 1 /* DECOR_START */;

const TILE_SIZE: f32 = 16.0;
const PIXEL_UV_SIZE: f32 = 1.0 / TILE_SIZE;
const ATLAS_WIDTH: f32 = TILE_SIZE * TILES_PER_ROW;
const ATLAS_HEIGHT: f32 = TILE_SIZE * TILES_PER_COLUMN;
const SPRITE_W = TILE_SIZE / ATLAS_WIDTH;
const SPRITE_H = TILE_SIZE / ATLAS_HEIGHT;
const TEXTURE_BLEEDING_EPSILON = 0.5 / TILE_SIZE;

// See EdgeFlags in zig/types.zig.
const EDGE_TOP: u32         = 0x02u;
const EDGE_BOTTOM: u32      = 0x40u;
const EDGE_LEFT: u32        = 0x08u;
const EDGE_RIGHT: u32       = 0x10u;
const EDGE_TOP_LEFT: u32    = 0x01u;
const EDGE_TOP_RIGHT: u32   = 0x04u;
const EDGE_BOTTOM_LEFT: u32 = 0x20u;
const EDGE_BOTTOM_RIGHT: u32= 0x80u;

// Uniforms are cached on the GPU. This is updated once per frame by Zig.
struct SceneUniforms {
    camera: vec2f,
    viewport_size: vec2f,
    time: f32,
    zoom: f32,
    wireframe_opacity: f32,
    chunk_opacity: f32,
    player_screen_pos: vec2f,
    map_size: vec2u,
    _extra_padding: array<vec4f, 13>, // Pad to 256 bytes for dynamic offsets
};

struct TileData {
    word0: u32,
    word1: u32,
};

// Unpacked definition of tile (also see Block in zig/memory.zig)
struct UnpackedTile {
    sprite_id: u32,
    light: f32,
    hp: u32,
    seed: u32,
    seed2: u32,
    seed3: u32,
    edge_flags: u32,
};

@group(0) @binding(0) var<uniform> scene: SceneUniforms;
@group(0) @binding(1) var<storage, read> tiles: array<TileData>;
@group(0) @binding(2) var sprite_atlas: texture_2d<f32>;
@group(0) @binding(3) var pixel_sampler: sampler;

// Data passed from the Vertex step (per-corner) to the Fragment step (per-pixel)
struct VertexOutput {
    @builtin(position) position: vec4f,
    // Local UV (0.0 to 1.0) across the surface of the specific tile.
    @location(0) local_uv: vec2f,
    // Where on the chunk a tile is
    // @interpolate(flat) tells the GPU NOT to blend these values between the 4 corners of the quad.
    @location(1) @interpolate(flat) tile_coords: vec2u, // X and Y of the tile
    @location(2) @interpolate(flat) sprite_uv_origin: vec2f, // base UV of the sprite

    @location(3) @interpolate(flat) sprite_id: u32,
    @location(4) @interpolate(flat) edge_flags: u32,
    @location(5) @interpolate(flat) light: f32,
    @location(6) @interpolate(flat) seed: u32, // these 28 bits are used as efficently as possible
    @location(7) @interpolate(flat) seed2: u32, // murmurmix32'ed from seed
    @location(8) @interpolate(flat) seed3: u32, // murmurmix32'ed from seed2
};

// Extracts the specific bit ranges in the Block type (see zig/memory.zig).
fn unpack_tile(data: TileData) -> UnpackedTile {
    var out: UnpackedTile;

    out.sprite_id = extractBits(data.word0, 0u, 16u);
    out.edge_flags = extractBits(data.word0, 16u, 8u);
    // out.edge_flags = 0u; // test

    let light_u = extractBits(data.word0, 24u, 8u);

    // only apply to ores
    out.light = select(1.0, f32(light_u) / 3000.0 + 1.0, out.sprite_id >= ORE_START && out.sprite_id < GEM_START);

    // out.light = 1.0; // test
    out.hp = extractBits(data.word1, 0u, 4u);
    out.seed = extractBits(data.word1, 4u, 28u); // 28-bit seed
    out.seed2 = murmurmix32(out.seed);
    out.seed3 = murmurmix32(out.seed2);
    return out;
}

@vertex
fn vs_main(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32
) -> VertexOutput {
    // const POSITIONS = array<vec2f, 6>(
    //     vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0), // bottom-right, top-left triangle
    //     vec2f(0.0, 1.0), vec2f(1.0, 0.0), vec2f(1.0, 1.0) // top-left, bottom-right triangle
    // );

    // A bitmask where bits 1, 4, and 5 are set (0b110010 = 50)
    let x = f32((50u >> vertex_index) & 1u);

    // A bitmask where bits 2, 3, and 5 are set (0b101100 = 44)
    let y = f32((44u >> vertex_index) & 1u);

    let local_pos = vec2f(x, y);

    let total_tiles = scene.map_size.x * scene.map_size.y;

    var out: VertexOutput;
    if (instance_index == total_tiles) {
        // There's intentionally one more instance than the number of tiles to render the player!
        let world_pos = scene.player_screen_pos + local_pos * TILE_SIZE;
        let screen_pos = (world_pos - scene.camera) * scene.zoom + (scene.viewport_size * 0.5);
        let atlas_uv = vec2f(
            (1 + local_pos.x) * SPRITE_W, // player sprite at (1, 0)
            (0 + local_pos.y) * SPRITE_H
        );

        let ndc = vec2f(
            (screen_pos.x / scene.viewport_size.x) * 2.0 - 1.0,
            1.0 - (screen_pos.y / scene.viewport_size.y) * 2.0
        );

        out.position = vec4f(ndc, 0.0, 1.0);
        out.sprite_uv_origin = vec2f(1.0 * SPRITE_W, 0.0 * SPRITE_H);
        out.edge_flags = 255u;
        out.sprite_id = 1u;
        out.light = 1.0;
        out.local_uv = local_pos;
        return out;
    }

    let tile = unpack_tile(tiles[instance_index]);
    if (tile.sprite_id == 0u && scene.wireframe_opacity == 0.0) {
        out.position = vec4f(2.0, 2.0, 2.0, 1.0); // ideal outcode
        return out;
    }

    let tile_x = instance_index % scene.map_size.x;
    let tile_y = instance_index / scene.map_size.x;

    var id = tile.sprite_id;
    if (id == STONE_START) {
        // 2x2 grid stone pattern
        let offset = (tile_y % 2u) * 2u + (tile_x % 2u);
        id += offset;
    } else if (id == 2) { // edge stone (too lazy to make constant, like player)
        let offset = (tile_x % 2u) ^ (tile_y % 2u); // checkerboard
        id += offset;
    } else if (id == (DECOR_START + 2u)) {
        // seed-based variation for Mushrooms
        let random_mod = extractBits(tile.seed, 16u, 2u);
        if (random_mod == 0u) {
            id++;
        }
    }

    let world_pixel_pos = vec2f(f32(tile_x), f32(tile_y)) * TILE_SIZE + local_pos * TILE_SIZE;

    // get offset from camera center in world pixels
    let offset_from_cam = world_pixel_pos - scene.camera;
    // scale that offset by zoom, then add the screen center
    let screen_pos = (offset_from_cam * scene.zoom) + (scene.viewport_size * 0.5);

    // normalize coordinates
    // first, make sure spiral plant and ceiling flower should move up by 3 pixels, mushroom should move down 2 pixels
    // this is necessary because otherwise, they would look like they're floating in space
    var vertical_offset = select(
        select(
            0.0,
            3.0 * scene.zoom,
            id == (DECOR_START + 0u) || id == (DECOR_START + 1u) // spiral plant, ceiling flower
        ),
        -2.0 * scene.zoom,
        id == (DECOR_START + 2u) || id == (DECOR_START + 3u) // mushroom sprites
    );

    // apply to screen_pos.y before converting to NDC
    // subtract from Y because in screen space, lower values are "higher" up
    let adjusted_y = screen_pos.y - vertical_offset;

    let ndc = vec2f(
        (screen_pos.x / scene.viewport_size.x) * 2.0 - 1.0,
        1.0 - (adjusted_y / scene.viewport_size.y) * 2.0
    );

    // Calculate which sprite in the atlas to sample
    let sprite_col = f32(id % u32(TILES_PER_ROW));
    let sprite_row = f32(id / u32(TILES_PER_ROW));
    let origin = vec2f(sprite_col * SPRITE_W, sprite_row * SPRITE_H);

    out.position = vec4f(ndc, 0.0, 1.0);
    out.sprite_uv_origin = origin;
    out.sprite_id = id;
    out.edge_flags = tile.edge_flags;
    out.tile_coords = vec2u(tile_x, tile_y);
    out.light = tile.light;
    out.seed = tile.seed;
    out.seed2 = tile.seed2;
    out.seed3 = tile.seed3;
    out.local_uv = local_pos;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    var erode_mask: u32 = 1u;
    let safe_local_uv = clamp(in.local_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));

    if (in.edge_flags != 0xFFu) {
        erode_mask = erosion(in.local_uv, in.edge_flags, in.seed2, in.seed3);
        if (scene.wireframe_opacity == 0.0 && erode_mask == 0u) {
            discard; // discard early
        }
    }

    // technically I could optimize this part
    // but it doesn't really matter because its for procedural generation testing anyway
    if (in.sprite_id >= 256u && in.sprite_id <= 512u) {
        // Heatmap logic!
        // if (in.sprite_id == 256) { discard; }
        let color = (f32(in.sprite_id) - 256.0) / 256.0;
        var lch = vec3f(0.2 + color * 0.8, 0.2, 1.0); // lightness, chroma, hue
        let lab = oklch_to_oklab(lch);
        let final_rgb = max(oklab_to_linear_srgb(lab), vec3f(0.0));
        return vec4f(final_rgb, 1.0);
    }

    var final_uv = in.sprite_uv_origin + safe_local_uv * vec2f(SPRITE_W, SPRITE_H);
    if (in.sprite_id >= GEM_START && in.sprite_id < GEM_MASK_START) {
        let shift_bits = extractBits(in.seed, 18u, 8u); // shift the gem sprite around 0-15 pixels using bits 18-26
        let shift = vec2f(
            f32(shift_bits & 0xFu) / 16.0,
            f32(shift_bits >> 4u) / 16.0
        );
        let wrapped_local = fract(in.local_uv + shift); // there are 1 pixel boundaries so fract() being imprecise is okay
        let safe_wrapped = clamp(wrapped_local, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
        final_uv = in.sprite_uv_origin + safe_wrapped * vec2f(SPRITE_W, SPRITE_H);
    }

    // Sample the primary color (the actual original sprite, gem or not)
    var tex_color = textureSampleLevel(sprite_atlas, pixel_sampler, final_uv, 0.0);

    // ore sampling pixel logic
    if (in.sprite_id >= GEM_START && in.sprite_id < GEM_MASK_START) {
        let mask_variation = extractBits(in.seed, 15u, 3u); // 8 masks
        let mask_id = GEM_MASK_START + mask_variation;

        var flipped_uv = in.local_uv;

        // for bit 26 decide horizontal flip of the ore mask
        if ((extractBits(in.seed, 25u, 1u) == 1u)) {
            flipped_uv.x = 1.0 - flipped_uv.x;
        }

        // decide vertical for bit 27
        if ((extractBits(in.seed, 26u, 1u) == 1u)) {
            flipped_uv.y = 1.0 - flipped_uv.y;
        }

        // Use 2x2 grid logic for the background stone's ID (similar to the id-determining part of vs_main)
        let bg_id = STONE_START + (in.tile_coords.y % 2u) * 2u + (in.tile_coords.x % 2u);

        // Calculate UVs for the background stone
        let bg_col = f32(bg_id % u32(TILES_PER_ROW));
        let bg_row = f32(bg_id / u32(TILES_PER_ROW));
        let stone_uv = vec2f(bg_col * SPRITE_W, bg_row * SPRITE_H) + (safe_local_uv * vec2f(SPRITE_W, SPRITE_H));

        // Calculate UVs for the mask (using the UNSHIFTED uv)
        let mask_col = f32(mask_id % u32(TILES_PER_ROW));
        let mask_row = f32(mask_id / u32(TILES_PER_ROW));
        let safe_flipped_uv = clamp(flipped_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
        let mask_uv = vec2f(mask_col * SPRITE_W, mask_row * SPRITE_H) + (safe_flipped_uv * vec2f(SPRITE_W, SPRITE_H));
        let tex_stone = textureSampleLevel(sprite_atlas, pixel_sampler, stone_uv, 0.0);
        let tex_mask = textureSampleLevel(sprite_atlas, pixel_sampler, mask_uv, 0.0);

        let u_dist = max(abs(in.local_uv.x - 0.5), abs(in.local_uv.y - 0.5));

        // with linear RGB: r component of mask determines mix amount, vary ore brightness, multiply stone brightness based on dist
        let final_rgb_ore = mix(
            tex_stone.rgb * vec3f(0.4 + u_dist * 1.2),
            tex_color.rgb,
            tex_mask.r + (0.5 - u_dist)
        );
        tex_color = vec4f(final_rgb_ore, tex_color.a);
    }

    var wire_color = vec4f(0.0);

    if (scene.wireframe_opacity != 0.0) {
        // render wireframe due to being at the edge of a block?
        let inv_tile_scale = 1.00001 / (TILE_SIZE * scene.zoom);
        let is_block_edge = any(in.local_uv < vec2f(inv_tile_scale)) || any(in.local_uv > vec2f(1.0 - inv_tile_scale));

        if (is_block_edge) {
            let x_mod = in.tile_coords.x & 15u;
            let y_mod = in.tile_coords.y & 15u;

            if (in.sprite_id == 1u) {
                wire_color = vec4f(1.0, 0.5, 0.0, 1.0);
            } else {
                // Is this pixel on the edge of a CHUNK?
                let is_chunk_edge =
                    (x_mod == 0u && in.local_uv.x < inv_tile_scale) ||
                    (x_mod == 15u && in.local_uv.x > (1.0 - inv_tile_scale)) ||
                    (y_mod == 0u && in.local_uv.y < inv_tile_scale) ||
                    (y_mod == 15u && in.local_uv.y > (1.0 - inv_tile_scale));

                if (is_chunk_edge) {
                    wire_color = vec4f(1.0, 1.0, 0.0, min(1.0, scene.wireframe_opacity * 2.5));
                } else {
                    // wire_color = vec4f(1.0, 0.0, 0.0, scene.wireframe_opacity);

                    // neat-lookin' fancy wireframe coloring
                    let r = f32(x_mod) * 0.0625;
                    let g = f32(y_mod) * 0.0625;
                    let b = 0.5 + f32(x_mod ^ y_mod) * 0.03125;
                    wire_color = vec4f(r, g, b, scene.wireframe_opacity);
                }
            }
        }
    }

    // too transparent? exit early (removed, as unlikely to matter unless wireframes are enabled: most blocks are dense)
    // if (tex_color.a < 0.005 && !is_wireframe) { discard; }

    // convert to oklab and nudge values with seed
    var lab = linear_srgb_to_oklab(tex_color.rgb);
    var lch = oklab_to_oklch(lab);

    // we use 9 out of the 28 seed bits here
    let extracted_l = f32(extractBits(in.seed, 0u, 3u));
    let extracted_a = f32(extractBits(in.seed, 3u, 3u));
    let l_nudge = extracted_l / 7.0;
    let a_nudge = extracted_a / 7.0;
    let b_nudge = f32(extractBits(in.seed, 6u, 3u)) / 7.0;

    lch.x = lch.x * in.light + l_nudge * 0.02; // shift lightness (0-1)
    lch.y *= 1.0 + a_nudge * 0.2; // shift chroma, which acts similar to saturation (0-1)
    lch.z += b_nudge * 0.1; // shift hue (in RADIANS, red isn't exactly 0)

    var final_rgb = vec3f(0.0);
    if (in.edge_flags != 0xFFu) {
        // add the edge darkening and base light value, with the function using bits 10-16
        let darkening = calculate_edge_darkening(in.local_uv, in.edge_flags, in.seed);
        lch.x = lch.x * (1.0 - darkening);

        if (erode_mask == 2u) {
            lch.x *= 0.6 + extracted_l * 0.01; // lower lightness significantly
            lch.y *= 1.3 + extracted_a * 0.04; // increase chroma
        }
    }

    lab = oklch_to_oklab(lch);
    final_rgb = max(oklab_to_linear_srgb(lab), vec3f(0.0));
    var final_a = tex_color.a * select(scene.chunk_opacity, 1.0, in.sprite_id == 1u); // use chunk_opacity, unless this sprite is for the player

    if (scene.wireframe_opacity != 0.0) {
        // Correctly mix the wireframe dynamically depending on whether the block exists below it.
        final_rgb = mix(final_rgb, wire_color.rgb, wire_color.a);
        final_a = max(final_a, wire_color.a);
    }

    return vec4f(final_rgb, final_a);
}

// Bijective mixer for 32-bit integers
fn murmurmix32(number: u32) -> u32 {
    var h = number;
    h ^= h >> 16;
    h *= 0x85ebca6b;
    h ^= h >> 13;
    h *= 0xc2b2ae35;
    h ^= h >> 16;
    return h;
}

// Complex logic that returns 0u if a pixel should be TRANSPARENT ("eroded"), NORMAL, or BORDER (darkened).
fn erosion(local_uv: vec2f, edge_flags: u32, seed2: u32, seed3: u32) -> u32 { // uv of sprite, edge flags, and mixed seeds
    let px = u32(local_uv.x * TILE_SIZE);
    let py = u32(local_uv.y * TILE_SIZE);

    let has_top    = (edge_flags & EDGE_TOP) != 0u;
    let has_bottom = (edge_flags & EDGE_BOTTOM) != 0u;
    let has_left   = (edge_flags & EDGE_LEFT) != 0u;
    let has_right  = (edge_flags & EDGE_RIGHT) != 0u;
    let has_tl     = (edge_flags & EDGE_TOP_LEFT) != 0u;
    let has_tr     = (edge_flags & EDGE_TOP_RIGHT) != 0u;
    let has_bl     = (edge_flags & EDGE_BOTTOM_LEFT) != 0u;
    let has_br     = (edge_flags & EDGE_BOTTOM_RIGHT) != 0u;

    // Precompute outer corner radii from sc (used by both corner arcs and straight-edge safe zones)
    let r_tl = 4u + extractBits(seed3, 0u, 1u);
    let r_tr = 4u + extractBits(seed3, 2u, 1u);
    let r_bl = 4u + extractBits(seed3, 4u, 1u);
    let r_br = 4u + extractBits(seed3, 6u, 1u);

    // The "center" of the circle is at the corner! Do some pixel-perfect circle edge logic.

    // Top-left outer corner (top AND left both missing)
    if (!has_top && !has_left) {
        let r_sq = r_tl * r_tl;
        let dx = r_tl - px;
        let dy = r_tl - py;
        if (px < r_tl && py < r_tl) {
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq > r_sq) { return 0u; }
            if (dist_sq > r_sq - r_tl) { return 2u; } // darken ring of 1 pixel
        }
    }

    // Top-right outer corner
    if (!has_top && !has_right) {
        let r_sq = r_tr * r_tr;
        let fpx = 15u - px; // flip x
        if (fpx < r_tr && py < r_tr) {
            let dx = r_tr - fpx;
            let dy = r_tr - py;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq > r_sq) { return 0u; }
            if (dist_sq > r_sq - r_tr) { return 2u; }
        }
    }

    // Bottom-left outer corner
    if (!has_bottom && !has_left) {
        let r_sq = r_bl * r_bl;
        let fpy = 15u - py;
        if (px < r_bl && fpy < r_bl) {
            let dx = r_bl - px;
            let dy = r_bl - fpy;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq > r_sq) { return 0u; }
            if (dist_sq > r_sq - r_bl) { return 2u; }
        }
    }

    // Bottom-right outer corner
    if (!has_bottom && !has_right) {
        let r_sq = r_br * r_br;
        let fpx = 15u - px;
        let fpy = 15u - py;
        if (fpx < r_br && fpy < r_br) {
            let dx = r_br - fpx;
            let dy = r_br - fpy;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq > r_sq) { return 0u; }
            if (dist_sq > r_sq - r_br) { return 2u; }
        }
    }

    // Straight edges (8 bits each from se: bits 0-7 top, 8-15 bottom, 16-23 left, 24-31 right)

    // Top edge
    if (!has_top) {
        let base_depth = 1u + extractBits(seed2, 0u, 1u); // 1 or 2 pixels inward for each edge
        let notch_pos = extractBits(seed2, 1u, 4u);
        let notch_dir = extractBits(seed2, 5u, 1u);
        let notch_width = 2u + extractBits(seed2, 6u, 2u);

        var depth = base_depth;
        if (px >= notch_pos && px < notch_pos + notch_width) {
            if (notch_dir == 0u) { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        // Only apply straight edge outside the corner rounding zones
        let left_safe = select(0u, r_tl, !has_left);
        let right_safe = select(16u, 16u - r_tr, !has_right);

        if (px >= left_safe && px < right_safe) {
            if (py < depth) { return 0u; }
            if (py == depth) { return 2u; }
        }
    }

    // Bottom edge
    if (!has_bottom) {
        let base_depth = 1u + extractBits(seed2, 8u, 1u);
        let notch_pos = extractBits(seed2, 9u, 4u);
        let notch_dir = extractBits(seed2, 13u, 1u);
        let notch_width = 2u + extractBits(seed2, 14u, 2u);

        var depth = base_depth;
        if (px >= notch_pos && px < notch_pos + notch_width) {
            if (notch_dir == 0u) { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        let left_safe = select(0u, r_bl, !has_left);
        let right_safe = select(16u, 16u - r_br, !has_right);

        if (px >= left_safe && px < right_safe) {
            if (py > 15u - depth) { return 0u; }
            if (py == 15u - depth) { return 2u; }
        }
    }

    // Left edge
    if (!has_left) {
        let base_depth = 1u + extractBits(seed2, 16u, 1u);
        let notch_pos = extractBits(seed2, 17u, 4u);
        let notch_dir = extractBits(seed2, 21u, 1u);
        let notch_width = 2u + extractBits(seed2, 22u, 2u);

        var depth = base_depth;
        if (py >= notch_pos && py < notch_pos + notch_width) {
            if (notch_dir == 0u) { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        let top_safe = select(0u, r_tl, !has_top);
        let bottom_safe = select(16u, 16u - r_bl, !has_bottom);

        if (py >= top_safe && py < bottom_safe) {
            if (px < depth) { return 0u; }
            if (px == depth) { return 2u; }
        }
    }

    // Right edge
    if (!has_right) {
        let base_depth = 1u + extractBits(seed2, 24u, 1u);
        let notch_pos = extractBits(seed2, 25u, 4u);
        let notch_dir = extractBits(seed2, 29u, 1u);
        let notch_width = 2u + extractBits(seed2, 30u, 2u);

        var depth = base_depth;
        if (py >= notch_pos && py < notch_pos + notch_width) {
            if (notch_dir == 0u) { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        let top_safe = select(0u, r_tr, !has_top);
        let bottom_safe = select(16u, 16u - r_br, !has_bottom);

        if (py >= top_safe && py < bottom_safe) {
            if (px > 15u - depth) { return 0u; }
            if (px == 15u - depth) { return 2u; }
        }
    }

    // Inner corners (no diagonal neighbor)

    if (!has_tl && has_top && has_left) {
        let r = 2u + extractBits(seed3, 8u, 1u); // 2 or 3 pixel radius
        if (px < r && py < r) {
            let dx = px + 1u; // +1, so the circle center is at (-0.5, -0.5) effectively
            let dy = py + 1u;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq <= r * r) { return 0u; }
            if (dist_sq <= (r + 1u) * (r + 1u)) { return 2u; }
        }
    }

    if (!has_tr && has_top && has_right) {
        let r = 2u + extractBits(seed3, 10u, 1u);
        let fpx = 15u - px;
        if (fpx < r && py < r) {
            let dx = fpx + 1u;
            let dy = py + 1u;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq <= r * r) { return 0u; }
            if (dist_sq <= (r + 1u) * (r + 1u)) { return 2u; }
        }
    }

    if (!has_bl && has_bottom && has_left) {
        let r = 2u + extractBits(seed3, 12u, 1u);
        let fpy = 15u - py;
        if (px < r && fpy < r) {
            let dx = px + 1u;
            let dy = fpy + 1u;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq <= r * r) { return 0u; }
            if (dist_sq <= (r + 1u) * (r + 1u)) { return 2u; }
        }
    }

    if (!has_br && has_bottom && has_right) {
        let r = 2u + extractBits(seed3, 14u, 1u);
        let fpx = 15u - px;
        let fpy = 15u - py;
        if (fpx < r && fpy < r) {
            let dx = fpx + 1u;
            let dy = fpy + 1u;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq <= r * r) { return 0u; }
            if (dist_sq <= (r + 1u) * (r + 1u)) { return 2u; }
        }
    }

    return 1u;
}

// Number of 1 bits in a u8 (possibly useful for edge flags, currently unused).
fn popcount8(v: u32) -> u32 {
    var n = v;
    n = n - ((n >> 1u) & 0x55u);
    n = (n & 0x33u) + ((n >> 2u) & 0x33u);
    return ((n + (n >> 4u)) & 0x0Fu);
}

// Calculates edge darkening procedurally based on flags calculated in Zig.
fn calculate_edge_darkening(local_uv: vec2f, edge_flags: u32, seed: u32) -> f32 {
    var darkening = 0.0;
    let edge_width = 0.30 + f32(extractBits(seed, 9u, 3u)) / 32.0;
    let edge_strength = 0.25 + f32(extractBits(seed, 12u, 3u)) / 64.0;
    let corner_width = 0.5;

    // Curvy shadow gradient
    if ((edge_flags & EDGE_TOP) == 0u) {
        darkening = max(darkening, (1.0 - smoothstep(0.0, edge_width, local_uv.y)) * edge_strength);
    }
    if ((edge_flags & EDGE_BOTTOM) == 0u) {
        darkening = max(darkening, (1.0 - smoothstep(0.0, edge_width, 1.0 - local_uv.y)) * edge_strength);
    }
    if ((edge_flags & EDGE_LEFT) == 0u) {
        darkening = max(darkening, (1.0 - smoothstep(0.0, edge_width, local_uv.x)) * edge_strength);
    }
    if ((edge_flags & EDGE_RIGHT) == 0u) {
        darkening = max(darkening, (1.0 - smoothstep(0.0, edge_width, 1.0 - local_uv.x)) * edge_strength);
    }

    // Additional corner darkening
    // if ((edge_flags & EDGE_TOP_LEFT) == 0u || ((edge_flags & EDGE_TOP) == 0u && (edge_flags & EDGE_LEFT) == 0u)) {
    //     let corner_dist = length(local_uv);
    //     darkening = max(darkening, (1.0 - smoothstep(0.0, corner_width * 1.414, corner_dist)) * edge_strength * 1.2);
    // }
    // if ((edge_flags & EDGE_TOP_RIGHT) == 0u || ((edge_flags & EDGE_TOP) == 0u && (edge_flags & EDGE_RIGHT) == 0u)) {
    //     let corner_dist = length(vec2f(1.0 - local_uv.x, local_uv.y));
    //     darkening = max(darkening, (1.0 - smoothstep(0.0, corner_width * 1.414, corner_dist)) * edge_strength * 1.2);
    // }
    // if ((edge_flags & EDGE_BOTTOM_LEFT) == 0u || ((edge_flags & EDGE_BOTTOM) == 0u && (edge_flags & EDGE_LEFT) == 0u)) {
    //     let corner_dist = length(vec2f(local_uv.x, 1.0 - local_uv.y));
    //     darkening = max(darkening, (1.0 - smoothstep(0.0, corner_width * 1.414, corner_dist)) * edge_strength * 1.2);
    // }
    // if ((edge_flags & EDGE_BOTTOM_RIGHT) == 0u || ((edge_flags & EDGE_BOTTOM) == 0u && (edge_flags & EDGE_RIGHT) == 0u)) {
    //     let corner_dist = length(1.0 - local_uv);
    //     darkening = max(darkening, (1.0 - smoothstep(0.0, corner_width * 1.414, corner_dist)) * edge_strength * 1.2);
    // }

    return darkening;
}



// FBM background logic
struct BackgroundOutput {
    @builtin(position) position: vec4f,
    @location(0) world_uv: vec2f,
    @location(1) time: f32,
    @location(2) time2: f32,
};

@vertex
fn vs_background(@builtin(vertex_index) vertex_index: u32) -> BackgroundOutput {
    // Full-screen triangle to draw: [(-1, -1), (3, -1), (-1, 3)]
    let x = f32(i32(vertex_index & 1u) << 2u) - 1.0;
    let y = f32(i32(vertex_index & 2u) << 1u) - 1.0;

    var out: BackgroundOutput;
    out.position = vec4f(x, y, 0.0, 1.0);

    let screen_uv = vec2f(x, -y) * 0.5 + 0.5;
    out.world_uv = (screen_uv * scene.viewport_size) / scene.zoom + scene.camera;

    // Zig-zag wrapping for colors
    var t_wrap = (scene.time * 0.3) % 2.0;
    if (t_wrap > 1.0) { t_wrap = 2.0 - t_wrap; }

    var t_wrap_2 = (3.0 + scene.time * 0.072) % 2.0;
    if (t_wrap_2 > 1.0) { t_wrap_2 = 2.0 - t_wrap_2; }

    out.time = t_wrap;
    out.time2 = t_wrap_2;

    return out;
}

@fragment
fn fs_background(in: BackgroundOutput) -> @location(0) vec4f {
    const base_scale = 0.015;
    let parallax_offset = scene.camera * 0.02;
    let st = (in.world_uv + parallax_offset) * base_scale;
    let t = scene.time;

    var q = vec2f(0.0);
    q.x = noise(st);
    q.y = noise(st + vec2f(1.0));

    var r = vec2f(0.0);
    r.x = fbm_2(st + 1.0 * q + vec2f(1.7, 9.2) + 0.15 * t);
    r.y = fbm_2(st + 1.0 * q + vec2f(8.3, 2.8) + 0.126 * t);

    let f = fbm_4(st + r);

    let mix_blue = mix(0.0, 0.4, in.time);
    var color = mix(
        vec3f(0.0, 0.01, mix_blue * mix_blue),
        vec3f(0.1, 0.4, 0.2),
        clamp((f * f) * 4.0, 0.0, 1.0)
    );

    // Apply secondary color masks with tighter thresholds for contrast
    let mix_red = mix(0.0, 0.6 * 0.5, in.time + in.time2);
    let mix_green = mix(0.0, 1.0, in.time2);
    color = mix(
        color,
        vec3f(mix_red * mix_red, mix_green * mix_green, 0.8),
        clamp(length(q), 0.0, 1.0)
    );

    let intensity = f * 1.5 - 0.4; // controls wispiness
    let final_rgb = max(intensity, 0.0) * color;

    let opacity = scene.chunk_opacity;
    return vec4f(final_rgb * opacity, opacity);
}

fn noise(st: vec2f) -> f32 {
    let i = vec2u(vec2i(floor(st)));
    let f = fract(st);

    // Grid corners: (0,0), (1,0), (0,1), (1,1)
    let ix = vec4u(i.x, i.x + 1u, i.x, i.x + 1u);
    let iy = vec4u(i.y, i.y, i.y + 1u, i.y + 1u);

    let h = hash_2d(ix, iy);

    // Quintic interpolation for smoother gradients
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    return mix(
        mix(h.x, h.y, u.x), // Mix bottom
        mix(h.z, h.w, u.x), // Mix top
        u.y
    );
}

fn fbm_2(p: vec2f) -> f32 { // simple fractal brownian motion algorithm
    var v = 0.0;
    var a = 0.5;
    var shift = vec2f(100.0);
    var pos = p;
    for (var i = 0; i < 2; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn fbm_4(p: vec2f) -> f32 { // same as above but 4 iters
    var v = 0.0;
    var a = 0.5;
    var shift = vec2f(100.0);
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn hash_2d(x: vec4u, y: vec4u) -> vec4f {
    var state = (x * 1597334673u) ^ (y * 3812015487u);

    // 32-bit permutation step, yippee!
    state = state * 747796405u + 2891336453u;
    let shift = (state >> vec4u(28u)) + vec4u(4u);
    let word = ((state >> shift) ^ state) * 277803737u;
    let result = (word >> vec4u(22u)) ^ word;

    // Direct bit-manipulation hack to convert to a float from [0, 1)
    return bitcast<vec4f>((result >> vec4u(9u)) | vec4u(0x3f800000u)) - 1.0;
}

// OKLAB stuff
fn linear_srgb_to_oklab(c: vec3f) -> vec3f {
    let m1 = mat3x3f( // convert to LMS
        0.4122214708, 0.2119034982, 0.0883024619,
        0.5363325363, 0.6806995451, 0.2817188376,
        0.0514459929, 0.1073969566, 0.6299787005
    );
    let lms = max(m1 * c, vec3f(0.0));
    let lms_ = pow(lms, vec3f(1.0 / 3.0));

    let m2 = mat3x3f( // convert to OKLAB
        0.2104542553, 1.9779984951, 0.0259040371,
        0.7936177850, -2.4285922050, 0.7827717662,
        -0.0040720468, 0.4505937099, -0.8086758031
    );
    return m2 * lms_;
}

fn oklab_to_linear_srgb(c: vec3f) -> vec3f {
    let m1 = mat3x3f( // LMS again
        1.0, 1.0, 1.0,
        0.3963377774, -0.1055613458, -0.0894841775,
        0.2158037573, -0.0638541728, -1.2914855480
    );
    let lms_ = m1 * c;
    let lms = lms_ * lms_ * lms_;

    let m2 = mat3x3f( // convert back to normal srgb
        4.0767416621, -1.2684380046, -0.0041960863,
        -3.3077115913, 2.6097574011, -0.7034186147,
        0.2309699292, -0.3413193965, 1.7076127010
    );
    return m2 * lms;
}

fn oklab_to_oklch(lab: vec3f) -> vec3f {
    let chroma = length(lab.yz);
    let hue = atan2(lab.z, lab.y);
    return vec3f(lab.x, chroma, hue);
}

fn oklch_to_oklab(lch: vec3f) -> vec3f {
    return vec3f(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z));
}
