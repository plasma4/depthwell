// ------
// Main shader for Depthwell. Meant to work for both Mach Engine and web.
// Does not work. Mach Engine work has been paused until Zig SPIR-V support completes.
// ------

// Flags usage:
// #ifdef WEB_TARGET
// #else
// #endif

// These are sprite sheet constants.
// Sprites are saved as a .png in a sprite sheet 160 pixels wide, and each asset is 16x16.
// See zig/state/world.zig's Sprite definitions for sprite type list.
override TILES_PER_ROW: f32 = 1.0;
override TILES_PER_COLUMN: f32 = 1.0;
override STONE_START: u32 = 1u;
override ORE_START: u32 = 1u;
override GEM_START: u32 = 1u;
override GEM_MASK_START: u32 = 1u;
override GEAR_ID: u32 = 1u;
override WATER_START: u32 = 1u;

const PI = radians(180.0);
const TAU = radians(360.0);

override TILES_PER_ROW_U: u32 = u32(TILES_PER_ROW);
override HP_SAMPLE_START: u32 = GEM_MASK_START + 8u; // there are 8 gem masks and 16 HP masks
override DECOR_START: u32 = HP_SAMPLE_START + 16u;

const TILE_SIZE: f32 = 16.0;
const PIXEL_UV_SIZE: f32 = 1.0 / TILE_SIZE;
override ATLAS_WIDTH: f32 = TILE_SIZE * TILES_PER_ROW;
override ATLAS_HEIGHT: f32 = TILE_SIZE * TILES_PER_COLUMN;
override SPRITE_W: f32 = TILE_SIZE / ATLAS_WIDTH;
override SPRITE_H: f32 = TILE_SIZE / ATLAS_HEIGHT;
const TEXTURE_BLEEDING_EPSILON = 0.5 / TILE_SIZE;

// See EdgeFlags in zig/types/types.zig.
const EDGE_TOP: u32 = 0x02u;
const EDGE_BOTTOM: u32 = 0x40u;
const EDGE_LEFT: u32 = 0x08u;
const EDGE_RIGHT: u32 = 0x10u;
const EDGE_TOP_LEFT: u32 = 0x01u;
const EDGE_TOP_RIGHT: u32 = 0x04u;
const EDGE_BOTTOM_LEFT: u32 = 0x20u;
const EDGE_BOTTOM_RIGHT: u32 = 0x80u;

// Necessary as a polyfill for Mach Engine builds. (Replaced with extractBits if using JS)
fn extract_bits(v: u32, offset: u32, count: u32) -> u32 {
    return (v >> offset) & ((1u << count) - 1u);
}

// Uniforms are cached on the GPU. This is updated once per frame by Zig.
struct SceneUniforms {
    camera: vec2<f32>,
    viewport_size: vec2<f32>,
    time: f32,
    zoom: f32,
    wireframe_opacity: f32,
    chunk_opacity: f32,
    player_screen_pos: vec2<f32>,
    map_size: vec2<u32>,
    flags: vec4<u32>, // .a: is_p3; .b: is_8bit (.b is unused)
    grid_origin: vec4<f32>, // absolute position of min_cx/min_cy in tiles (.xy used)
    _extra_padding: array<vec4<u32>, 11>, // pad to 256 bytes for dynamic offsets
};

@group(0) @binding(0) var<uniform> scene: SceneUniforms;
@group(0) @binding(1) var<storage, read> tiles: array<TileData>;
@group(0) @binding(2) var sprite_atlas: texture_2d<f32>;
@group(0) @binding(3) var sprite_atlas_mask: texture_2d<f32>;
@group(0) @binding(4) var pixel_sampler: sampler;
@group(0) @binding(5) var<storage, read> entities: array<WGSLEntity>;

// ------
// TILE SECTION
// ------

// Data passed from the Vertex step (per-corner) to the Fragment step (per-pixel)
struct TileOutput {
    @builtin(position) position: vec4<f32>,
    // Local UV (0.0 to 1.0) across the surface of the specific tile.
    @location(0) local_uv: vec2<f32>,
    // Where on the chunk a tile is
    // @interpolate(flat) tells the GPU NOT to blend these values between the 4 corners of the quad.
    @location(1) @interpolate(flat) tile_coords: vec2<u32>, // X and Y of the tile
    @location(2) @interpolate(flat) sprite_uv_origin: vec2<f32>, // base UV of the sprite
    @location(3) @interpolate(flat) sprite_id: u32, // do note that an extra u16 id is injected to the top half of bits with gems
    @location(4) @interpolate(flat) edge_flags: u32,
    @location(5) @interpolate(flat) light: f32,
    @location(6) @interpolate(flat) hp: u32,
    // seed1: murmurmix32'ed from raw seed data and HP mixed
    // seed2: murmurmix32'ed from seed1
    // seed3: murmurmix32'ed from seed2
    @location(7) @interpolate(flat) seeds: vec3<u32>,
    @location(8) @interpolate(flat) waterlogged: u32,
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
    seeds: vec3<u32>,
    edge_flags: u32,
    waterlogged: u32,
};

fn unpack_tile(data: TileData) -> UnpackedTile {
    var out: UnpackedTile;

    out.sprite_id = extract_bits(data.word0, 0u, 16u);
    out.edge_flags = extract_bits(data.word0, 16u, 8u);
    // out.edge_flags = 0u; // test

    // only apply to ores
    // let light_u = extract_bits(data.word0, 24u, 8u);
    // out.light = select(1.0, f32(light_u) / 3000.0 + 1.0, out.sprite_id >= ORE_START && out.sprite_id < GEM_START);

    out.light = 1.0;

    out.hp = extract_bits(data.word1, 20u, 4u);
    // hp takes up the top 4 bits perfectly, 24-bit total
    let s1 = murmurmix32(select(extract_bits(data.word1, 0u, 24u), extract_bits(data.word1, 0u, 20u), out.sprite_id >= DECOR_START));
    let s2 = murmurmix32(s1);
    let s3 = murmurmix32(s2);
    out.seeds = vec3<u32>(s1, s2, s3);
    out.waterlogged = extract_bits(data.word1, 27u, 5u); // Also see meaning in zig/memory.zig.
    return out;
}

// Main vertex shader for tiles.
@vertex
fn vs_tile(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32
) -> TileOutput {
    // A bitmask where bits 1, 4, and 5 are set (0b110010 = 50) and bits 2, 3, and 5 are set (0b101100 = 44)
    let bit_shift_x = (50u >> vertex_index) & 1u;
    let bit_shift_y = (44u >> vertex_index) & 1u;

    let local_pos = vec2<f32>(f32(bit_shift_x), f32(bit_shift_y));

    let total_tiles = scene.map_size.x * scene.map_size.y;
    var out: TileOutput;

    if instance_index == total_tiles {
        // There's intentionally one more instance than the number of tiles to render the player!
        let world_pos = scene.player_screen_pos + local_pos * TILE_SIZE;
        let screen_pos = (world_pos - scene.camera) * scene.zoom + (scene.viewport_size * 0.5);

        // normalized device coordinates
        let ndc = (screen_pos / scene.viewport_size) * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);

        out.position = vec4<f32>(ndc, 0.0, 1.0);
        out.sprite_uv_origin = vec2<f32>(1.0 * SPRITE_W, 0.0 * SPRITE_H);
        out.edge_flags = 255u;
        out.sprite_id = 1u;
        out.light = 1.0;
        out.local_uv = local_pos;
        return out;
    }

    let tile = unpack_tile(tiles[instance_index]);
    if tile.sprite_id == 0u && scene.wireframe_opacity == 0.0 {
        out.position = vec4<f32>(2.0, 2.0, 2.0, 1.0); // ideal outcode
        return out;
    }

    let tile_coords = vec2<u32>(instance_index % scene.map_size.x, instance_index / scene.map_size.x);
    var id = tile.sprite_id;

    let world_pixel_pos = (vec2<f32>(tile_coords) + local_pos) * TILE_SIZE;
    let screen_pos = ((world_pixel_pos - scene.camera) * scene.zoom) + (scene.viewport_size * 0.5);

    // normalize coordinates
    // first, make sure spiral plant and ceiling flower move up (visually) by 2 pixels
    // var vertical_offset = select(
    //     0.0,
    //     2.0 * scene.zoom,
    //     // spiral plant, ceiling flower
    //     id == GEAR_ID + 4u || id == GEAR_ID + 5u
    // );
    // update: this messes with water visually
    const vertical_offset = 0;

    // add to ID based on pre-determined shifts
    if id == STONE_START {
        // 2x2 grid stone pattern (like a 32x32 sprite)
        let offset1 = ((tile_coords.y & 1u) << 1u) | (tile_coords.x & 1u);
        id += offset1;
    } else if id == 2 { // (IDs here hard-coded, like player)
        // edge stone alternates in a checkerboard pattern
        let offset2 = (tile_coords.x & 1u) ^ (tile_coords.y & 1u);
        id += offset2;
    } else if id == GEAR_ID + 2u || id == GEAR_ID + 5u {
        // seed-based variation for bushes and ceiling flowers
        id = select(id, id + 1, extract_bits(tile.seeds[0], 16u, 1u) == 1u); // 50% odds to select the variation

        // for 25%:
        // let random_mod = extract_bits(tile.seeds[0], 16u, 2u);
        // if random_mod == 0u {
        //     id++;
        // }
    } else if id == GEAR_ID + 7u || id == GEAR_ID + 10u { // variation for mushrooms
        let bits = extract_bits(tile.seeds[0], 16u, 2u);
        id += select(bits, 0u, bits == 3u); // select variation (0, +1, or +2, 50% odds of 0)
    }

    // apply to screen_pos.y before converting to normalized device coordinates
    // subtract from Y because in screen space, lower values are "higher" up
    let adjusted_screen_pos = screen_pos - vec2<f32>(0.0, vertical_offset);
    let ndc = (adjusted_screen_pos / scene.viewport_size) * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);

    // Calculate which sprite in the atlas to sample
    let origin = vec2<f32>(f32(id % TILES_PER_ROW_U), f32(id / TILES_PER_ROW_U)) * vec2<f32>(SPRITE_W, SPRITE_H);

    out.position = vec4<f32>(ndc, 0.0, 1.0);
    out.sprite_uv_origin = origin;
    let is_gem = id >= GEM_START && id < GEM_MASK_START;
    // if is_gem {
    //     out.sprite_id = extract_bits(tiles[instance_index].word0, 0u, 16u) | id;
    // } else {
    //     out.sprite_id = id;
    // }
    out.sprite_id = id;
    out.hp = tile.hp;
    out.seeds = tile.seeds;
    out.edge_flags = tile.edge_flags;
    out.tile_coords = tile_coords;
    out.light = tile.light;
    out.local_uv = local_pos;
    out.waterlogged = tile.waterlogged;
    return out;
}

@fragment
fn fs_tile(
    @location(0) local_uv: vec2<f32>,
    @location(1) @interpolate(flat) tile_coords: vec2<u32>,
    @location(2) @interpolate(flat) sprite_uv_origin: vec2<f32>,
    @location(3) @interpolate(flat) sprite_id: u32,
    @location(4) @interpolate(flat) edge_flags: u32,
    @location(5) @interpolate(flat) light: f32,
    @location(6) @interpolate(flat) hp: u32,
    @location(7) @interpolate(flat) seeds: vec3<u32>,
    @location(8) @interpolate(flat) waterlogged: u32
) -> @location(0) vec4<f32> {
    var erode_mask: u32 = 1u;
    let id = sprite_id;
    let is_decor = id >= DECOR_START;

    if id == WATER_START || id == WATER_START + 1u {
        let has_liquid_above = (waterlogged & 1u) != 0u;
        let has_solid_above = ((edge_flags & EDGE_TOP) != 0u) && !has_liquid_above;
        let has_top = has_liquid_above || (has_solid_above && (hp == 15u));

        if !has_top {
            // This is the top surface of the water body!
            let t = scene.time;
            let world_pos = wrap_water_coords((vec2<f32>(tile_coords) + scene.grid_origin.xy) * TILE_SIZE + local_uv * TILE_SIZE);

            // Sine-wave ripple effect at the surface (frequency is periodic over 65536.0 pixels)
            let base_height = f32(hp) * 0.06 + 0.10;
            let ripple_freq = 4172.0 * TAU / 65536.0;
            let ripple = sin(world_pos.x * ripple_freq + t * 5.0) * 0.05;
            var current_height = base_height + ripple;

            // If the pixel is above the water surface, discard it
            if local_uv.y < (1.0 - current_height) {
                discard;
            }
        }
        return water_body(tile_coords, local_uv);
    }

    if sprite_id >= 65000u && sprite_id <= 65256u {
        // Heatmap logic!
        let color = (f32(sprite_id - 65000u)) / 256.0;
        var lch = vec3<f32>(0.2 + color * 0.8, 0.2, 1.0); // lightness, chroma, and hue
        let lab = oklch_to_oklab(lch);
        let final_rgb = oklab_to_linear_srgb(lab);
        return vec4<f32>(final_rgb, 1.0);
    }

    // Determine waterlogged decoration state
    let is_waterlogged_decor = is_decor && hp > 0u;
    var is_decor_pixel_underwater = false;
    if is_waterlogged_decor {
        let wl_top = (waterlogged & 1u) != 0u;
        let wl_ripple = (waterlogged & 4u) != 0u;
        let has_top = wl_top || (((edge_flags & EDGE_TOP) != 0u) && hp == 15u);
        var current_height = 1.0;
        if !has_top {
            let base_height = f32(hp) * 0.06 + 0.10;
            let t = scene.time;
            let world_pos = wrap_water_coords((vec2<f32>(tile_coords) + scene.grid_origin.xy) * TILE_SIZE + local_uv * TILE_SIZE);
            let ripple_freq = 4172.0 * TAU / 65536.0;
            let ripple = sin(world_pos.x * ripple_freq + t * 5.0) * 0.05;
            current_height = base_height + ripple;
        }
        if local_uv.y >= (1.0 - current_height) {
            is_decor_pixel_underwater = true;
        }
    }

    let safe_local_uv = clamp(local_uv, vec2<f32>(TEXTURE_BLEEDING_EPSILON), vec2<f32>(1.0 - TEXTURE_BLEEDING_EPSILON));

    if edge_flags != 0xFFu && !is_decor {
        erode_mask = erosion(local_uv, edge_flags, seeds[1], seeds[2]);
        if erode_mask == 0u {
            if waterlogged != 0u {
                let is_water_top = (waterlogged & 1u) != 0u;
                let is_water_bottom = (waterlogged & 2u) != 0u;
                let apply_ripple = (waterlogged & 4u) != 0u;
                let is_water_left = (waterlogged & 8u) != 0u;
                let is_water_right = (waterlogged & 16u) != 0u;

                var is_water_pixel = false;
                if is_water_top && local_uv.y < 0.5 {
                    is_water_pixel = true;
                }
                if is_water_bottom && local_uv.y >= 0.5 {
                    is_water_pixel = true;
                }
                if is_water_left && local_uv.x < 0.5 {
                    is_water_pixel = true;
                }
                if is_water_right && local_uv.x >= 0.5 {
                    is_water_pixel = true;
                }

                if is_water_pixel {
                    if apply_ripple {
                        let t = scene.time;
                        let world_pos = wrap_water_coords((vec2<f32>(tile_coords) + scene.grid_origin.xy) * TILE_SIZE + local_uv * TILE_SIZE);

                        // Synchronized ripple effect utilizing the adjacent water's actual volume
                        // TODO
                        let base_height = f32(15) * 0.06 + 0.10;
                        let ripple_freq = 4172.0 * TAU / 65536.0;
                        let ripple = sin(world_pos.x * ripple_freq + t * 5.0) * 0.05;
                        let current_height = base_height + ripple;

                        if local_uv.y < (1.0 - current_height) {
                            is_water_pixel = false;
                        }
                    }
                }

                if is_water_pixel { return water_body(tile_coords, local_uv); }
            }
            discard; // discard early
        }
    }

    let seed = seeds[0];
    let is_gem = id >= GEM_START && id < GEM_MASK_START;
    let is_ore = id >= ORE_START && id < GEM_START;

    var final_uv = sprite_uv_origin + safe_local_uv * vec2<f32>(SPRITE_W, SPRITE_H);

    // Apply 0-15 pixel shift for gems and ores using bits 16-23 of seed3
    if is_gem || is_ore {
        let shift_bits = extract_bits(seeds[2], 16u, 8u);
        let shift = vec2<f32>(vec2<u32>(shift_bits & 0xFu, shift_bits >> 4u)) / 16.0;
        let wrapped_local = fract(local_uv + shift);
        let safe_wrapped = clamp(wrapped_local, vec2<f32>(TEXTURE_BLEEDING_EPSILON), vec2<f32>(1.0 - TEXTURE_BLEEDING_EPSILON));
        final_uv = sprite_uv_origin + safe_wrapped * vec2<f32>(SPRITE_W, SPRITE_H);
    }

    // Avoid HP mask texture sample for undamaged tiles or decor sprites
    var hp_darkness_mult = 1.0;
    if hp > 0u && !is_decor {
        let hp_id = HP_SAMPLE_START + hp;
        let hp_grid = vec2<f32>(f32(hp_id % TILES_PER_ROW_U), f32(hp_id / TILES_PER_ROW_U));
        let hp_uv = (hp_grid + safe_local_uv) * vec2<f32>(SPRITE_W, SPRITE_H);
        hp_darkness_mult = textureSampleLevel(sprite_atlas, pixel_sampler, hp_uv, 0.0).r;
    }

    var tex_color = textureSampleLevel(sprite_atlas, pixel_sampler, final_uv, 0.0);
    tex_color = vec4<f32>(srgb_to_linear(tex_color.rgb) * hp_darkness_mult, tex_color.a);

    // ore sampling pixel logic
    if is_gem || is_ore {
        // 8 masks, first 4 for gems, second 4 for ore
        let mask_variation = extract_bits(seed, 15u, 2u) + select(4u, 0u, is_gem);
        let mask_id = GEM_MASK_START + mask_variation;

        let flip = vec2<f32>(vec2<u32>(extract_bits(seed, 25u, 1u), extract_bits(seed, 26u, 1u)));
        // #ifdef WEB_TARGET
        // let flipped_uv = mix(local_uv, 1.0 - local_uv, flip);
        // #else
        let flipped_uv_x = mix(local_uv.x, 1.0 - local_uv.x, flip.x);
        let flipped_uv_y = mix(local_uv.y, 1.0 - local_uv.y, flip.y);
        let flipped_uv = vec2(flipped_uv_x, flipped_uv_y);
        // #endif
        // Use 2x2 grid logic for the background stone's ID
        let bg_id = STONE_START + (((tile_coords.y & 1u) << 1u) | (tile_coords.x & 1u));

        // Calculate UVs for the background stone
        let bg_grid = vec2<f32>(f32(bg_id % TILES_PER_ROW_U), f32(bg_id / TILES_PER_ROW_U));
        let stone_uv = (bg_grid + safe_local_uv) * vec2<f32>(SPRITE_W, SPRITE_H);

        // Calculate UVs for the mask (using the UNSHIFTED uv)
        let safe_flipped_uv = clamp(flipped_uv, vec2<f32>(TEXTURE_BLEEDING_EPSILON), vec2<f32>(1.0 - TEXTURE_BLEEDING_EPSILON));
        let mask_grid = vec2<f32>(f32(mask_id % TILES_PER_ROW_U), f32(mask_id / TILES_PER_ROW_U));
        let mask_uv = (mask_grid + safe_flipped_uv) * vec2<f32>(SPRITE_W, SPRITE_H);

        let tex_stone = textureSampleLevel(sprite_atlas, pixel_sampler, stone_uv, 0.0);
        let tex_mask = textureSampleLevel(sprite_atlas, pixel_sampler, mask_uv, 0.0);

        let abs_dist = abs(local_uv - 0.5); // higher value means closer to EDGES
        let u_dist = 0.5 - max(abs_dist.x, abs_dist.y); // higher value means closer to CENTER

        // with linear RGB: r component of mask determines brightness, vary ore brightness, multiply stone brightness based on dist
        let final_rgb_ore = mix(
             // stone pixels near center become darker based on HP
            srgb_to_linear(tex_stone.rgb) * vec3<f32>(1.2 - 0.22 * f32(hp) * u_dist), 
            // gem pixels near center become brighter
            tex_color.rgb * vec3<f32>(tex_mask.r + 0.3 * u_dist),
            tex_mask.a + u_dist
        );
        tex_color = vec4<f32>(final_rgb_ore, tex_color.a);
    }

    var wire_color = vec4<f32>(0.0);

    if scene.wireframe_opacity != 0.0 {
        // render wireframe due to being at the edge of a block?
        let inv_tile_scale = 1.00001 / (TILE_SIZE * scene.zoom);
        let is_block_edge = any(local_uv < vec2<f32>(inv_tile_scale)) || any(local_uv > vec2<f32>(1.0 - inv_tile_scale));

        if is_block_edge {
            // Evaluated: Refactored vector bitwise & into component-wise scalar operation
            let mods = vec2<u32>(tile_coords.x & 15u, tile_coords.y & 15u);

            if id == 1u {
                wire_color = vec4<f32>(1.0, 0.5, 0.0, 1.0);
            } else {
                // Evaluated: Refactored boolean vector bitwise AND/OR into standard logical operators
                let is_chunk_edge = (mods.x == 0u && local_uv.x < inv_tile_scale) ||
                                    (mods.y == 0u && local_uv.y < inv_tile_scale) ||
                                    (mods.x == 15u && local_uv.x > (1.0 - inv_tile_scale)) ||
                                    (mods.y == 15u && local_uv.y > (1.0 - inv_tile_scale));

                if is_chunk_edge {
                    wire_color = vec4<f32>(1.0, 1.0, 0.0, min(1.0, scene.wireframe_opacity * 2.5));
                } else {
                    // neat-lookin' fancy wireframe coloring
                    let rg = vec2<f32>(mods) * 0.0625;
                    let b = 0.5 + f32(mods.x ^ mods.y) * 0.03125;
                    wire_color = vec4<f32>(rg.x, rg.y, b, scene.wireframe_opacity);
                }
            }
        } else {
            // Replaced the trailing 'else if' with an explicit 'else' enclosing 'if'
            if erode_mask == 0u {
                discard;
            }
        }
    }

    // convert to oklab and nudge values with seed
    var lab = linear_srgb_to_oklab(tex_color.rgb);
    var lch = oklab_to_oklch(lab);

    // we use 9 out of the 28 seed bits here
    let lab_nudge_bits = vec3<u32>(
        extract_bits(seed, 0u, 3u), // shift lightness (0-1)
        extract_bits(seed, 3u, 3u), // shift chroma, which acts similar to saturation (in practice, between 0-0.4)
        extract_bits(seed, 6u, 3u)// shift hue (in RADIANS, red isn't exactly 0)
    );
    let nudges = vec3<f32>(lab_nudge_bits) / 7.0;

    // Apply light and nudges in a single MAD operation where possible
    lch *= vec3<f32>(light, 1.0 + nudges.y * 0.2, 1.0) +
        vec3<f32>(nudges.x * 0.02, 0.0, nudges.z * 0.1);

    var final_rgb = vec3<f32>(0.0);
    if edge_flags != 0xFFu {
        // add the edge darkening and base light value, with the function using bits 10-16
        let darkening = calculate_edge_darkening(local_uv, edge_flags, seed);
        lch.x *= (1.0 - darkening);

        if erode_mask == 2u {
            lch *= vec3<f32>(0.6 + f32(lab_nudge_bits.x) * 0.01, 1.3 + f32(lab_nudge_bits.y) * 0.04, 1.0);
        }
    }

    // convert OKLCH result to OKLAB, then finally back to float-based RGB
    lab = oklch_to_oklab(lch);
    final_rgb = oklab_to_linear_srgb(lab);

    var final_a = tex_color.a * select(scene.chunk_opacity, 1.0, id == 1u); // use chunk_opacity, unless this sprite is for the player

    // Overlay semi-transparent water body if this decoration pixel is underwater
    if is_decor_pixel_underwater {
        let water_col = water_body_linear(tile_coords, local_uv);

        // Blending curve: maps original alpha to water weight
        let weight = 1.0 - 0.5 * pow(tex_color.a, 7.0);

        final_rgb = oklab_water(final_rgb, water_col.rgb, weight);
        final_a = mix(water_col.a, 1.0, tex_color.a);
    }

    if scene.wireframe_opacity != 0.0 {
        // Correctly mix the wireframe dynamically depending on whether the block exists below it.
        final_rgb = mix(final_rgb, wire_color.rgb, wire_color.a);
        final_a = max(final_a, wire_color.a);
    }

    return vec4<f32>(apply_color_management(final_rgb), final_a);
}

// Bijective mixer for 32-bit integers
fn murmurmix32(number: u32) -> u32 {
    var h = max(number, 1u);
    h ^= h >> 16;
    h *= 0x85ebca6b;
    h ^= h >> 13;
    h *= 0xc2b2ae35;
    h ^= h >> 16;
    return h;
}

// Complex logic that returns 0u if a pixel should be TRANSPARENT ("eroded"), 1u for NORMAL, or 2u for BORDER (darkened).
fn erosion(local_uv: vec2<f32>, edge_flags: u32, seed2: u32, seed3: u32) -> u32 { // uv of sprite, edge flags, and mixed seeds
    let px = u32(local_uv.x * TILE_SIZE);
    let py = u32(local_uv.y * TILE_SIZE);

    let has_top = (edge_flags & EDGE_TOP) != 0u;
    let has_bottom = (edge_flags & EDGE_BOTTOM) != 0u;
    let has_left = (edge_flags & EDGE_LEFT) != 0u;
    let has_right = (edge_flags & EDGE_RIGHT) != 0u;
    let has_tl = (edge_flags & EDGE_TOP_LEFT) != 0u;
    let has_tr = (edge_flags & EDGE_TOP_RIGHT) != 0u;
    let has_bl = (edge_flags & EDGE_BOTTOM_LEFT) != 0u;
    let has_br = (edge_flags & EDGE_BOTTOM_RIGHT) != 0u;

    // Precompute outer corner radii from sc (used by both corner arcs and straight-edge safe zones)
    let r_tl = 3u + extract_bits(seed3, 0u, 2u);
    let r_tr = 3u + extract_bits(seed3, 2u, 2u);
    let r_bl = 3u + extract_bits(seed3, 4u, 2u);
    let r_br = 3u + extract_bits(seed3, 6u, 2u);

    // The "center" of the circle is at the corner! Do some pixel-perfect circle edge logic.

    // Top-left outer corner (top AND left both missing)
    if !has_top && !has_left {
        let r_sq = r_tl * r_tl;
        let dx = r_tl - px;
        let dy = r_tl - py;
        if px < r_tl && py < r_tl {
            let dist_sq = dx * dx + dy * dy;
            if dist_sq > r_sq { return 0u; }
            if dist_sq > r_sq - r_tl { return 2u; } // darken ring of 1 pixel
        }
    }

    // Top-right outer corner
    if !has_top && !has_right {
        let r_sq = r_tr * r_tr;
        let fpx = 15u - px; // flip x
        if fpx < r_tr && py < r_tr {
            let dx = r_tr - fpx;
            let dy = r_tr - py;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq > r_sq { return 0u; }
            if dist_sq > r_sq - r_tr { return 2u; }
        }
    }

    // Bottom-left outer corner
    if !has_bottom && !has_left {
        let r_sq = r_bl * r_bl;
        let fpy = 15u - py;
        if px < r_bl && fpy < r_bl {
            let dx = r_bl - px;
            let dy = r_bl - fpy;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq > r_sq { return 0u; }
            if dist_sq > r_sq - r_bl { return 2u; }
        }
    }

    // Bottom-right outer corner
    if !has_bottom && !has_right {
        let r_sq = r_br * r_br;
        let fpx = 15u - px;
        let fpy = 15u - py;
        if fpx < r_br && fpy < r_br {
            let dx = r_br - fpx;
            let dy = r_br - fpy;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq > r_sq { return 0u; }
            if dist_sq > r_sq - r_br { return 2u; }
        }
    }

    // Straight edges (8 bits each from se: bits 0-7 top, 8-15 bottom, 16-23 left, 24-31 right)

    // Top edge
    if !has_top {
        let base_depth = extract_bits(seed2, 0u, 1u); // 0 or 1 pixels inward for each edge
        let notch_pos = extract_bits(seed2, 1u, 4u);
        let notch_dir = extract_bits(seed2, 5u, 1u);
        let notch_width = 2u + extract_bits(seed2, 6u, 2u);

        var depth = base_depth;
        if px >= notch_pos && px < notch_pos + notch_width {
            if notch_dir == 0u { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        // Only apply straight edge outside the corner rounding zones
        let left_safe = select(0u, r_tl, !has_left);
        let right_safe = select(16u, 16u - r_tr, !has_right);

        if px >= left_safe && px < right_safe {
            if py < depth { return 0u; }
            if py == depth { return 2u; }
        }
    }

    // Bottom edge
    if !has_bottom {
        let base_depth = extract_bits(seed2, 8u, 1u);
        let notch_pos = extract_bits(seed2, 9u, 4u);
        let notch_dir = extract_bits(seed2, 13u, 1u);
        let notch_width = 2u + extract_bits(seed2, 14u, 2u);

        var depth = base_depth;
        if px >= notch_pos && px < notch_pos + notch_width {
            if notch_dir == 0u { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        let left_safe = select(0u, r_bl, !has_left);
        let right_safe = select(16u, 16u - r_br, !has_right);

        if px >= left_safe && px < right_safe {
            if py > 15u - depth { return 0u; }
            if py == 15u - depth { return 2u; }
        }
    }

    // Left edge
    if !has_left {
        let base_depth = extract_bits(seed2, 16u, 1u);
        let notch_pos = extract_bits(seed2, 17u, 4u);
        let notch_dir = extract_bits(seed2, 21u, 1u);
        let notch_width = 2u + extract_bits(seed2, 22u, 2u);

        var depth = base_depth;
        if py >= notch_pos && py < notch_pos + notch_width {
            if notch_dir == 0u { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        let top_safe = select(0u, r_tl, !has_top);
        let bottom_safe = select(16u, 16u - r_bl, !has_bottom);

        if py >= top_safe && py < bottom_safe {
            if px < depth { return 0u; }
            if px == depth { return 2u; }
        }
    }

    // Right edge
    if !has_right {
        let base_depth = extract_bits(seed2, 24u, 1u);
        let notch_pos = extract_bits(seed2, 25u, 4u);
        let notch_dir = extract_bits(seed2, 29u, 1u);
        let notch_width = 2u + extract_bits(seed2, 30u, 2u);

        var depth = base_depth;
        if py >= notch_pos && py < notch_pos + notch_width {
            if notch_dir == 0u { depth += 1u; } else { depth = max(depth, 1u) - 1u; }
        }

        let top_safe = select(0u, r_tr, !has_top);
        let bottom_safe = select(16u, 16u - r_br, !has_bottom);

        if py >= top_safe && py < bottom_safe {
            if px > 15u - depth { return 0u; }
            if px == 15u - depth { return 2u; }
        }
    }

    // Inner corners (no diagonal neighbor)

    if !has_tl && has_top && has_left {
        let r = 1u + extract_bits(seed3, 8u, 2u); // 1-4 pixel radius
        if px < r && py < r {
            let dx = px + 1u; // +1, so the circle center is at (-0.5, -0.5) effectively
            let dy = py + 1u;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq <= r * r { return 0u; }
            if dist_sq <= (r + 1u) * (r + 1u) { return 2u; }
        }
    }

    if !has_tr && has_top && has_right {
        let r = 1u + extract_bits(seed3, 10u, 2u);
        let fpx = 15u - px;
        if fpx < r && py < r {
            let dx = fpx + 1u;
            let dy = py + 1u;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq <= r * r { return 0u; }
            if dist_sq <= (r + 1u) * (r + 1u) { return 2u; }
        }
    }

    if !has_bl && has_bottom && has_left {
        let r = 1u + extract_bits(seed3, 12u, 2u);
        let fpy = 15u - py;
        if px < r && fpy < r {
            let dx = px + 1u;
            let dy = fpy + 1u;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq <= r * r { return 0u; }
            if dist_sq <= (r + 1u) * (r + 1u) { return 2u; }
        }
    }

    if !has_br && has_bottom && has_right {
        let r = 1u + extract_bits(seed3, 14u, 2u);
        let fpx = 15u - px;
        let fpy = 15u - py;
        if fpx < r && fpy < r {
            let dx = fpx + 1u;
            let dy = fpy + 1u;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq <= r * r { return 0u; }
            if dist_sq <= (r + 1u) * (r + 1u) { return 2u; }
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
fn calculate_edge_darkening(local_uv: vec2<f32>, edge_flags: u32, seed: u32) -> f32 {
    let edge_width = 0.40 + f32(extract_bits(seed, 9u, 3u)) / 32.0;
    let edge_strength = 0.4 + f32(extract_bits(seed, 12u, 3u)) / 32.0;

    let dists = vec4<f32>(local_uv.y, 1.0 - local_uv.y, local_uv.x, 1.0 - local_uv.x);
    // #ifdef WEB_TARGET
    // let edge_masks = vec4<u32>(edge_flags) & vec4<u32>(EDGE_TOP, EDGE_BOTTOM, EDGE_LEFT, EDGE_RIGHT);
    // #else
    let edge_masks = vec4<u32>(
        edge_flags & EDGE_TOP,
        edge_flags & EDGE_BOTTOM,
        edge_flags & EDGE_LEFT,
        edge_flags & EDGE_RIGHT
    );
    // #endif
    let is_edge = edge_masks == vec4<u32>(0u);

    let edge_darkenings = select(
        vec4<f32>(0.0),
        (1.0 - smoothstep(vec4<f32>(0.0), vec4<f32>(edge_width), dists)) * edge_strength,
        is_edge
    );

    return max(max(edge_darkenings.x, edge_darkenings.y), max(edge_darkenings.z, edge_darkenings.w));
}

// ------
// WATER
// ------

fn wrap_water_coords(coords: vec2<f32>) -> vec2<f32> {
    return coords - floor(coords / 65536.0) * 65536.0;
}

// World-space pixel coordinate of this fragment (floating point, any value)
fn water_world(tile_coords: vec2<u32>, local_uv: vec2<f32>) -> vec2<f32> {
    return (vec2<f32>(tile_coords) + scene.grid_origin.xy) * TILE_SIZE + local_uv * TILE_SIZE;
}

// Shared base LCH that cycles hue between teal and blue.
fn water_base_lch(t: f32) -> vec3<f32> {
    let H = 3.8 + sin(t * (TAU / 3600.0)) * 0.34;
    return vec3<f32>(0.42, 0.12, H);
}

fn water_effect(coord: vec2<f32>, t: f32) -> f32 {
    let R = 256.0; // grid repeat period
    let L_FREQ = TAU / 3600.0; // base frequency per time loop
    // Every multiplier below is now an exact integer multiplied by L_FREQ
    let warp_val = sin((coord.y * 2.0) / R * TAU + t * (20.0 * L_FREQ)) * 5.5 + cos((coord.x * 3.0) / R * TAU - t * (12.0 * L_FREQ)) * 4.0;

    let world = coord + vec2<f32>(warp_val, -warp_val);
    let world2 = coord - vec2<f32>(warp_val, -warp_val);

    // First caustic layer
    // All layers are made to be periodic every 65536 pixels.
    let d_a = world.x * 0.906 - world.y * 0.423;
    let a1 = sin((d_a + t * 15.0) / (65536.0 / 1489.0) * TAU) * 0.5 + 0.5;
    let a2 = sin((d_a * 1.15 + t * 13.0) / (65536.0 / 1638.0) * TAU) * 0.5 + 0.5;
    let band_a = a1 * a2 * 0.24;

    // Second layer (which crosses directions)
    let d_b = world2.x * 0.643 - world.y * -0.766;
    let b1 = sin((d_b * 3.2 + t * 4.0) / 32.0 * TAU) * 0.5 + 0.5;
    let b2 = sin((d_b * 4.2 + t * 5.42) / (65536.0 / 2341.0) * TAU) * 0.5 + 0.5;
    let temp_b = b1 * b2;
    let band_b = temp_b * temp_b * 0.03;

    let d_c = world.x * 0.906 + world2.y * 0.423;
    let band_c = max(0.0, sin((d_c + t * 15.0) / (65536.0 / 1489.0) * TAU));

    // Warping distortion using periodic wavelengths
    let warp_y_freq = 1043.0 * TAU / 65536.0;
    let warp_x_freq = 834.0 * TAU / 65536.0;
    let warp = sin(world.y * warp_y_freq + t * 0.3) * 4.0 + cos(world.x * warp_x_freq - t * 0.3) * 4.0;

    // Apply warp to a new diagonal direction for the curvy streak
    let d_curvy = (world.x + warp) * 0.5 + (world.y - warp) * 0.866;
    let c1 = sin((d_curvy + t * 1.2) / (65536.0 / 1311.0) * TAU) * 0.5 + 0.5;
    let c2 = cos((d_curvy - t * 0.35) / (65536.0 / 1872.0) * TAU) * 0.5 + 0.5;
    let temp_c = c1 * c2;
    let temp_c2 = temp_c * temp_c;
    let curvy_streak = temp_c2 * temp_c2 * temp_c2 * 0.3;

    return band_a + band_b + band_c * band_c * 0.2 + curvy_streak;
}

// Procedural effect for lighting (linear sRGB)
fn water_body_linear(tile_coords: vec2<u32>, local_uv: vec2<f32>) -> vec4<f32> {
    let world = water_world(tile_coords, local_uv);
    let t = scene.time;

    var lch = water_base_lch(t);

    // Depth gradient that's lighter near y=0 (surface), darker going down.
    let depth_t = clamp(world.y / 192.0, 0.0, 1.0); // 192px
    lch.x = mix(0.52, 0.34, depth_t); // light surface
    lch.y = mix(0.10, 0.14, depth_t);// slightly more saturated deep

    // Horizontal color band (depth striping)
    let band_t = sin(world.y / 24.0 + t * 0.4) * 0.5 + 0.5;
    lch.x += band_t * 0.04;

    let caustic = water_effect(world, t);
    lch.x = clamp(lch.x + caustic, 0.26, 0.90);
    lch.y = clamp(lch.y + caustic * 0.10, 0.04, 0.28);

    let rgb = oklab_to_linear_srgb(oklch_to_oklab(lch));
    return vec4<f32>(rgb, 0.5);
}

// Procedural effect for all but the top water sprite (backwards compatible, returns color-managed sRGB)
fn water_body(tile_coords: vec2<u32>, local_uv: vec2<f32>) -> vec4<f32> {
    let water_col = water_body_linear(tile_coords, local_uv);
    return vec4<f32>(apply_color_management(water_col.rgb), water_col.a);
}

// Perceptually blends sprite color with water in OKLAB space.
fn oklab_water(sprite_rgb: vec3<f32>, water_rgb: vec3<f32>, weight: f32) -> vec3<f32> {
    let lab_sprite = linear_srgb_to_oklab(sprite_rgb);
    let lab_water = linear_srgb_to_oklab(water_rgb);
    let lab_mixed = mix(lab_sprite, lab_water, weight);
    return oklab_to_linear_srgb(lab_mixed);
}

// ------
// BACKGROUND SECTION
// ------

// FBM background logic
struct BackgroundOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) screen_offset: vec2<f32>,
    @location(1) time: f32,
    @location(2) time2: f32,
};

// Main vertex shader for rendering the fancy background.
@vertex
fn vs_background(@builtin(vertex_index) vertex_index: u32) -> BackgroundOutput {
    // Full-screen triangle to draw: [(-1, -1), (3, -1), (-1, 3)]
    let x = f32((i32(vertex_index & 1u) << 2u) - 1);
    let y = f32((i32(vertex_index & 2u) << 1u) - 1);

    var out: BackgroundOutput;
    out.position = vec4<f32>(x, y, 0.0, 1.0);

    let screen_uv = vec2<f32>(x, -y) * 0.5 + 0.5;

    // Center the scale pivot to the screen center (camera and player viewport center)
    out.screen_offset = ((screen_uv - 0.5) * scene.viewport_size) / scene.zoom;

    // Zig-zag wrapping for colors
    let t_val1 = scene.time * 0.3;
    var t_wrap = t_val1 - 2.0 * floor(t_val1 / 2.0);
    if t_wrap > 1.0 { t_wrap = 2.0 - t_wrap; }

    let t_val2 = 3.0 + scene.time * 0.072;
    var t_wrap_2 = t_val2 - 2.0 * floor(t_val2 / 2.0);
    if t_wrap_2 > 1.0 { t_wrap_2 = 2.0 - t_wrap_2; }

    out.time = t_wrap;
    out.time2 = t_wrap_2;

    return out;
}

@fragment
fn fs_background(
    @location(0) screen_offset: vec2<f32>,
    @location(1) time: f32,
    @location(2) time2: f32
) -> @location(0) vec4<f32> {
    const base_scale = 0.015625; // Exactly 1.0 / 64.0 for seamless 256-chunk alignment
    let absolute_camera = scene.grid_origin.zw;
    let t = scene.time;

    // The farthest background layer (64x "slower")
    let st1 = (screen_offset + absolute_camera * 0.015625) * base_scale;
    let angle1 = (t / 600.0) * TAU; // 10-minute cycle!
    let drift1 = vec2<f32>(cos(angle1), sin(angle1)) * 0.5;

    let q1 = noise(st1 * 0.45 + drift1);
    let f1 = noise(st1 * 0.85 + q1 * 1.5);

    let color1 = mix(
        vec3<f32>(0.12, 0.22, 0.05),
        vec3<f32>(0.12, 0.11, 0.03),
        f1
    );

    let layer1_intensity = clamp(f1 * f1 * 0.4, 0.1, 1.0);
    let layer1_rgb = layer1_intensity * color1;

    // Far background layer (32x "slower")
    let st2 = (screen_offset + absolute_camera * 0.03125) * base_scale;
    let angle2 = (t / 180.0) * TAU; // 3-minute cycle
    let drift2_x = vec2<f32>(cos(angle2), sin(angle2)) * 1.0;
    let drift2_y = vec2<f32>(sin(angle2), -cos(angle2)) * 0.8;

    var q2 = vec2<f32>(0.0);
    q2.x = noise(st2 * 0.3 + drift2_x * 0.1);
    q2.y = noise(st2 * 0.3 + vec2<f32>(1.0, 0.3) + drift2_y * 0.1);

    let f2 = fbm_3(st2 * 0.5 + 2.0 * q2);

    let mix_blue = mix(0.0, 0.4, time);
    let color2 = mix(
        vec3<f32>(0.0, 0.005, mix_blue * mix_blue * 0.5),
        vec3<f32>(0.05, 0.15, 0.25),
        clamp(f2 * f2 * 3.0, 0.0, 1.0)
    );
    let layer2_intensity = max(f2 * f2 * sqrt(f2) * 1.5 - 0.1, 0.0);
    let layer2_rgb = layer2_intensity * color2;

    // Middle background layer (8x "slower")
    let st3 = (screen_offset + absolute_camera * 0.125) * base_scale;
    let angle3 = (t / 60.0) * TAU; // only 60s
    let drift3_x = vec2<f32>(cos(angle3), sin(angle3)) * 1.8;
    let drift3_y = vec2<f32>(sin(angle3), -cos(angle3)) * 1.5;

    var q3 = vec2<f32>(0.0);
    q3.x = noise(st3 * 0.6 + drift3_x * 0.2);
    q3.y = noise(st3 * 0.6 + vec2<f32>(2.4, 1.1) + drift3_y * 0.2);

    var r3 = vec2<f32>(0.0);
    r3.x = fbm_2(st3 * 1.8 + 3.0 * q3 + drift3_x);
    r3.y = fbm_2(st3 * 1.8 + 3.0 * q3 + drift3_y);

    let f3 = fbm_4(st3 * 1.2 + 2.5 * r3);

    let mix_red = mix(0.0, 0.3, time + time2);
    let mix_green = mix(0.0, 0.6, time2);
    let color3 = mix(
        vec3<f32>(0.01, 0.05, 0.1),
        vec3<f32>(mix_red * mix_red, mix_green * mix_green, 0.5),
        clamp(length(q3 * r3), 0.0, 1.0)
    );
    let layer3_intensity = max(f3 * f3 * f3 * 2.5 - 0.2, 0.0);
    let layer3_rgb = layer3_intensity * color3;

    // Additive screen blend of both seamless layers
    let final_rgb = layer1_rgb + layer2_rgb + layer3_rgb;

    let opacity = scene.chunk_opacity;
    return vec4<f32>(final_rgb * opacity, opacity);
}

fn noise(st: vec2<f32>) -> f32 {
    let i = vec2<u32>(vec2<i32>(floor(st)));
    let f = fract(st);

    // Make the grid noise perfectly periodic with a period of 32 units
    let ix = (i.x + vec4<u32>(0u, 1u, 0u, 1u)) % vec4<u32>(32u);
    let iy = (i.y + vec4<u32>(0u, 0u, 1u, 1u)) % vec4<u32>(32u);

    let h = hash_2d(ix, iy);

    // Quintic interpolation for smoother gradients
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    return mix(
        mix(h.x, h.y, u.x), // Mix bottom
        mix(h.z, h.w, u.x), // Mix top
        u.y
    );
}

fn fbm_2(p: vec2<f32>) -> f32 { // simple fractal brownian motion algorithm
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    for (var i = 0; i < 2; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn fbm_3(p: vec2<f32>) -> f32 { // same as above but 3 iters
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    for (var i = 0; i < 3; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn fbm_4(p: vec2<f32>) -> f32 { // same as above but 4 iters (wow, who could have guessed!)
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// #ifdef WEB_TARGET
// fn hash_2d(x: vec4u, y: vec4u) -> vec4f {
//     var state = (x * 1597334673u) ^ (y * 3812015487u);

//     // 32-bit permutation step, yippee!
//     state = state * 747796405u + 2891336453u;
//     let shift = (state >> vec4u(28u)) + vec4u(4u);
//     let word = ((state >> shift) ^ state) * 277803737u;
//     let result = (word >> vec4u(22u)) ^ word;

//     // Direct bit-manipulation hack to convert to a float from [0, 1)
//     return bitcast<vec4f>((result >> vec4u(9u)) | vec4u(0x3f800000u)) - 1.0;
// }
// #else
fn hash_2d(x: vec4<u32>, y: vec4<u32>) -> vec4<f32> {
    return vec4<f32>(
        hash_1d(x.x, y.x),
        hash_1d(x.y, y.y),
        hash_1d(x.z, y.z),
        hash_1d(x.w, y.w)
    );
}

fn hash_1d(x: u32, y: u32) -> f32 {
    var state = (x * 1597334673u) ^ (y * 3812015487u);

    // 32-bit permutation step
    state = state * 747796405u + 2891336453u;
    let shift = (state >> 28u) + 4u;
    let word = ((state >> shift) ^ state) * 277803737u;
    let result = (word >> 22u) ^ word;

    // Avoid bitcast to bypass sysgpu translation bug
    return f32(result) / 4294967296.0;
}
// #endif

// ------
// ENTITY SECTION
// ------

struct WGSLEntity {
    lcha: vec4<f32>,
    position: vec2<f32>,
    size: vec2<f32>,
    rotation: f32,
    id: u32,
    _pad: vec2<u32>,
}

struct EntityOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) local_uv: vec2<f32>,
    @location(1) @interpolate(flat) lcha: vec4<f32>,
    @location(2) @interpolate(flat) id: u32,
    @location(3) @interpolate(flat) sprite_uv_origin: vec2<f32>,
};

// Main vertex shader for generic entities (uses the mask).
@vertex
fn vs_entity(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32
) -> EntityOutput {
    let entity = entities[instance_index];
    // presume ID 0 is unreasonable
    // var out: EntityOutput;
    // if entity.id == 0u {
    //     out.position = vec4<f32>(2.0, 2.0, 2.0, 1.0); // ideal outcode
    // }

    // A bitmask where bits 1, 4, and 5 are set (0b110010 = 50) and bits 2, 3, and 5 are set (0b101100 = 44)
    let bit_shift_x = (50u >> vertex_index) & 1u;
    let bit_shift_y = (44u >> vertex_index) & 1u;

    let local_pos = vec2<f32>(f32(bit_shift_x), f32(bit_shift_y));
    let centered_pos = local_pos - 0.5f;

    // Rotate sprite as needed (in radians)
    let c = cos(entity.rotation);
    let s = sin(entity.rotation);
    let rotated_pos = vec2<f32>(
        centered_pos.x * c - centered_pos.y * s,
        centered_pos.x * s + centered_pos.y * c
    );

    let pixel_pos = entity.position + rotated_pos * entity.size;

    // Convert to normalized device coords
    let ndc = pixel_pos * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);

    // Calculate UV origin
    var origin = vec2<f32>(
        f32(entity.id % TILES_PER_ROW_U),
        f32(entity.id / TILES_PER_ROW_U)
    ) * vec2<f32>(SPRITE_W, SPRITE_H);

    var out: EntityOutput;
    out.position = vec4<f32>(ndc, 0.0, 1.0);
    out.local_uv = local_pos;
    out.lcha = entity.lcha;
    out.id = entity.id;
    out.sprite_uv_origin = origin;
    return out;
}

@fragment
fn fs_entity(input: EntityOutput) -> @location(0) vec4<f32> {
    // Calculate UVs with bleeding protection
    let safe_local_uv = clamp(input.local_uv, vec2<f32>(TEXTURE_BLEEDING_EPSILON), vec2<f32>(1.0 - TEXTURE_BLEEDING_EPSILON));
    let final_uv = input.sprite_uv_origin + safe_local_uv * vec2<f32>(SPRITE_W, SPRITE_H);

    // Both the original sprite and the mask are sampled. The mask is pre-made: for many sprites it is white.
    // For gems, there's a special gem mask, and ores have a rounded rectangular mask with darkening.
    // This is multiplied with RGBA instead of OKLCH for simplicity.

    // in the future we can also make the sample of either change over time for some neat effects
    let raw_tex = textureSampleLevel(sprite_atlas, pixel_sampler, final_uv, 0.0);
    let raw_mask = textureSampleLevel(sprite_atlas_mask, pixel_sampler, final_uv, 0.0);

    // make raw mask stronger
    let tex_rgb = srgb_to_linear(raw_tex.rgb * raw_mask.rgb);
    let tex_a = raw_tex.a * raw_mask.a;
    // Early discard if the pixel is fully transparent (maybe)
    // if tex_color.a <= 0.0 {
    //     discard;
    // }
    var lab = linear_srgb_to_oklab(tex_rgb);
    var lch = oklab_to_oklch(lab);

    // Apply modifications from lcha (vec4<f32>: L, C, H, A), see zig/render/entity.zig
    lch.x *= input.lcha.x; // mult light
    lch.y += input.lcha.y; // add chroma
    lch.z += input.lcha.z; // add hue

    lab = oklch_to_oklab(lch);
    let final_rgb = oklab_to_linear_srgb(lab);

    // apply alpha after being back to RGB!
    let final_a = tex_a * input.lcha.w;
    return vec4<f32>(apply_color_management(final_rgb), final_a);
}

// ------
// OKLAB AND COLOR SPACE
// (There are a lot of magic numbers here.)
// ------

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>( // convert to LMS
        vec3<f32>(0.4122214708, 0.2119034982, 0.0883024619),
        vec3<f32>(0.5363325363, 0.6806995451, 0.2817188376),
        vec3<f32>(0.0514459929, 0.1073969566, 0.6299787005));
    let lms = max(m1 * c, vec3<f32>(0.0));
    let lms_ = pow(lms, vec3<f32>(1.0 / 3.0));

    let m2 = mat3x3<f32>( // convert to OKLAB
        vec3<f32>(0.2104542553, 1.9779984951, 0.0259040371),
        vec3<f32>(0.7936177850, -2.4285922050, 0.7827717662),
        vec3<f32>(-0.0040720468, 0.4505937099, -0.8086758031));
    return m2 * lms_;
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>( // LMS
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.3963377774, -0.1055613458, -0.0894841775),
        vec3<f32>(0.2158037573, -0.0638541728, -1.2914855480));
    let lms_ = m1 * c;
    let lms = lms_ * lms_ * lms_;

    let m2 = mat3x3<f32>( // convert back to normal srgb
        vec3<f32>(4.0767416621, -1.2684380046, -0.0041960863),
        vec3<f32>(-3.3077115913, 2.6097574011, -0.7034186147),
        vec3<f32>(0.2309699292, -0.3413193965, 1.7076127010));
    let result = m2 * lms;
    return max(result, vec3<f32>(0.0));
}

fn linear_srgb_to_display_p3(rgb: vec3<f32>) -> vec3<f32> {
    let m = mat3x3<f32>(
        vec3<f32>(0.822462, 0.033194, 0.017083),
        vec3<f32>(0.177538, 0.966806, 0.072397),
        vec3<f32>(0.000000, 0.000000, 0.910520)
    );
    return max(m * rgb, vec3<f32>(0.0));
}

fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return select(
        c / 12.92,
        pow((c + 0.055) / 1.055, vec3<f32>(2.4)),
        c > vec3<f32>(0.04045)
    );
}

fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    let safe_c = max(c, vec3<f32>(0.0));
    return select(
        12.92 * safe_c,
        1.055 * pow(safe_c, vec3<f32>(1.0 / 2.4)) - 0.055,
        safe_c > vec3<f32>(0.0031308)
    );
}

fn oklab_to_oklch(lab: vec3<f32>) -> vec3<f32> {
    let chroma = length(lab.yz);
    var hue = 0.0;
    // prevent invalid numbers with this check
    if chroma > 0.0001 {
        hue = atan2(lab.z, lab.y);
    }
    return vec3<f32>(lab.x, chroma, hue);
}

fn oklch_to_oklab(lch: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z));
}

// Change the final RGB value based on color space info.
fn apply_color_management(linear_rgb: vec3<f32>) -> vec3<f32> {
    var out = linear_rgb;
    // Convert color space while still linear
    if scene.flags.x == 1u { // isP3
        out = linear_srgb_to_display_p3(out);
    }
    return linear_to_srgb(out); // always apply transfer function
}
