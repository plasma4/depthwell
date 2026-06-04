(function(){const e=document.createElement("link").relList;if(e&&e.supports&&e.supports("modulepreload"))return;for(const t of document.querySelectorAll('link[rel="modulepreload"]'))i(t);new MutationObserver(t=>{for(const s of t)if(s.type==="childList")for(const a of s.addedNodes)a.tagName==="LINK"&&a.rel==="modulepreload"&&i(a)}).observe(document,{childList:!0,subtree:!0});function n(t){const s={};return t.integrity&&(s.integrity=t.integrity),t.referrerPolicy&&(s.referrerPolicy=t.referrerPolicy),t.crossOrigin==="use-credentials"?s.credentials="include":t.crossOrigin==="anonymous"?s.credentials="omit":s.credentials="same-origin",s}function i(t){if(t.ep)return;t.ep=!0;const s=n(t);fetch(t.href,s)}})();const o={zoom:131072,mine:262144,inventory_up:524288,inventory_down:1048576,minus:32768,plus:65536,up:2048,left:4096,down:8192,right:16384,k0:1,k1:2,k2:4,k3:8,k4:16,k5:32,k6:64,k7:128,k8:256,k9:512},k={player_pos:0,last_player_pos:16,player_chunk:32,player_velocity:48,camera_pos:64,last_camera_pos:80,camera_scale:96,camera_scale_change:104,depth:112,player_quadrant:120,frame:124,items_mined:128,keys_pressed_mask:136,keys_held_mask:140,seed:144,seed2:208},V="abcdefghijklmnopqrstuvwxyz",x=26n;function H(r=100){if(r<=0)return"";const e=new Uint8Array(72);crypto.getRandomValues(e);let n=0n;const i=new DataView(e.buffer);for(let a=0;a<e.length;a+=8)n=n<<64n|i.getBigUint64(a);let t="",s=n%x**BigInt(r);for(;s>=0n&&(t+=V[Number(s%x)],s=s/x-1n,!(s<0n)););return t}function W(r){let e=0n;for(let n=0;n<r.length;n++){const i=BigInt(r.charCodeAt(n)-97);e=e*x+(i+1n)}return e}async function K(r,e){const n=W(r),i=new DataView(new ArrayBuffer(64));for(let c=0;c<8;c++)i.setBigUint64(c*8,n>>BigInt((7-c)*64)&0xffffffffffffffffn);let t=new Uint8Array(i.buffer,0,32),s=new Uint8Array(i.buffer,32,32);const a=await Promise.all([0,1,2,3].map(c=>crypto.subtle.importKey("raw",new Uint8Array([c]),{name:"HMAC",hash:"SHA-256"},!1,["sign"])));for(const c of a){const f=new Uint8Array(await crypto.subtle.sign("HMAC",c,s)),p=new Uint8Array(32);for(let d=0;d<32;d++)p[d]=t[d]^f[d];t=s,s=p}const l=new Uint8Array(64);return l.set(t,0),l.set(s,32),e.set(new BigUint64Array(l.buffer)),e}const B={Minus:o.minus,Equal:o.plus,KeyZ:o.zoom,Backquote:o.mine,KeyQ:o.inventory_up,KeyE:o.inventory_down,Space:o.up,ArrowUp:o.up,KeyW:o.up,ArrowLeft:o.left,KeyA:o.left,ArrowDown:o.down,KeyS:o.down,ArrowRight:o.right,KeyD:o.right,Digit0:o.k0,Digit1:o.k1,Digit2:o.k2,Digit3:o.k3,Digit4:o.k4,Digit5:o.k5,Digit6:o.k6,Digit7:o.k7,Digit8:o.k8,Digit9:o.k9},I=o.up|o.down|o.left|o.right;function $(){let r={};const e={heldMask:0,keysHeld:0,keysPressed:0,currentlyHeld:0,horizontalPriority:0,verticalPriority:0,plusMinusPriority:0};function n(){r={},e.horizontalPriority=0,e.verticalPriority=0,e.plusMinusPriority=0,e.currentlyHeld=0,e.heldMask=0,e.keysPressed=0}return window.addEventListener("keydown",i=>{if(i.repeat)return;if(i.ctrlKey||i.metaKey){n();return}const t=B[i.code];t&&(t<=512&&(e.heldMask=e.heldMask&4294966272),e.heldMask|=t,t&I&&(r[t]=(r[t]||0)+1),t&(o.left|o.right)&&(e.horizontalPriority=t),t&(o.up|o.down)&&(e.verticalPriority=t),t&(o.plus|o.minus)&&(e.plusMinusPriority=t))}),window.addEventListener("keyup",i=>{const t=B[i.code];t&&(t&I?(r[t]=Math.max(0,(r[t]||0)-1),r[t]===0&&(e.heldMask&=~t)):e.heldMask&=~t,e.heldMask&t||(t===e.horizontalPriority&&(e.horizontalPriority=e.heldMask&o.left||e.heldMask&o.right||0),t===e.verticalPriority&&(e.verticalPriority=e.heldMask&o.up||e.heldMask&o.down||0),t===e.plusMinusPriority&&(e.plusMinusPriority=e.heldMask&o.plus||e.heldMask&o.minus||0)))}),window.addEventListener("blur",n),document.addEventListener("visibilitychange",n),window.addEventListener("contextmenu",n),e}function Z(r){const e=o.up|o.down|o.left|o.right;let n=r.heldMask&~e;n|=r.horizontalPriority,n|=r.verticalPriority,n|=r.plusMinusPriority,r.keysPressed=n&~r.keysHeld,r.currentlyHeld=n,r.keysHeld=n}const X=""+new URL("main-dbq7Puew.wasm",import.meta.url).href,j=`/*
 * Main shader for Depthwell. ADD ?raw FOR DEBUGGING SHADER TO THE END OF engineMaker.ts's \`SHADER_SOURCE\` VARIABLE TO NOT COMPRESS.
 */

// These are sprite sheet constants. Sprites are saved as a .png in a sprite sheet 160 pixels wide, and each asset is 16x16.
// See zig/state/world.zig's Sprite definitions for sprite type list.
// These const values with /* VARIABLE_NAME */ are dynamically patched in from TypeScript, so do not set them here.
const TILES_PER_ROW: f32 = /* TILES_PER_ROW */ 1 /* TILES_PER_ROW */;
const TILES_PER_COLUMN: f32 = /* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */;
const STONE_START: u32 = /* STONE_START */ 1 /* STONE_START */;
const ORE_START: u32 = /* ORE_START */ 1 /* ORE_START */;
const GEM_START: u32 = /* GEM_START */ 1 /* GEM_START */;
const GEM_MASK_START: u32 = /* GEM_MASK_START */ 1 /* GEM_MASK_START */;
const DECOR_START: u32 = /* DECOR_START */ 1 /* DECOR_START */;
const WATER_START: u32 = /* WATER_START */ 1 /* WATER_START */;

const PI = radians(180.0);
const TAU = radians(360.0);

const TILES_PER_ROW_U: u32 = u32(TILES_PER_ROW);
const HP_SAMPLE_START = GEM_MASK_START + 8; // there are 8 gem masks and 16 HP masks

const TILE_SIZE: f32 = 16.0;
const PIXEL_UV_SIZE: f32 = 1.0 / TILE_SIZE;
const ATLAS_WIDTH: f32 = TILE_SIZE * TILES_PER_ROW;
const ATLAS_HEIGHT: f32 = TILE_SIZE * TILES_PER_COLUMN;
const SPRITE_W = TILE_SIZE / ATLAS_WIDTH;
const SPRITE_H = TILE_SIZE / ATLAS_HEIGHT;
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
    flags: vec4u, // .a: is_p3; .b: is_8bit (.b is unused)
    grid_origin: vec4f, // absolute position of min_cx/min_cy in tiles (.xy used)
    _extra_padding: array<vec4u, 11>, // pad to 256 bytes for dynamic offsets
};

@group(0) @binding(0) var<uniform> scene: SceneUniforms;
@group(0) @binding(1) var<storage, read> tiles: array<TileData>;
@group(0) @binding(2) var sprite_atlas: texture_2d<f32>;
@group(0) @binding(3) var sprite_atlas_mask: texture_2d<f32>;
@group(0) @binding(4) var pixel_sampler: sampler;
@group(0) @binding(5) var<storage, read> entities: array<WGSLEntity>;

/*
    ----
    TILES
    ----
*/

// Data passed from the Vertex step (per-corner) to the Fragment step (per-pixel)
struct TileOutput {
    @builtin(position) position: vec4f,
    // Local UV (0.0 to 1.0) across the surface of the specific tile.
    @location(0) local_uv: vec2f,
    // Where on the chunk a tile is
    // @interpolate(flat) tells the GPU NOT to blend these values between the 4 corners of the quad.
    @location(1) @interpolate(flat) tile_coords: vec2u, // X and Y of the tile
    @location(2) @interpolate(flat) sprite_uv_origin: vec2f, // base UV of the sprite
    @location(3) @interpolate(flat) sprite_id: u32, // do note that an extra u16 id is injected to the top half of bits with gems
    @location(4) @interpolate(flat) edge_flags: u32,
    @location(5) @interpolate(flat) light: f32,
    @location(6) @interpolate(flat) hp: u32,
    @location(7) @interpolate(flat) seeds: vec3u, // seed1: these 20 bits are used as efficently as possible, seed2: murmurmix32'ed from seed, seed3: murmurmix32'ed from seed2
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
    seeds: vec3u,
    edge_flags: u32,
    waterlogged: u32,
};

// Extracts the specific bit ranges in the Block type (see zig/memory.zig).
fn unpack_tile(data: TileData) -> UnpackedTile {
    var out: UnpackedTile;

    out.sprite_id = extractBits(data.word0, 0u, 16u);
    out.edge_flags = extractBits(data.word0, 16u, 8u);
    // out.edge_flags = 0u; // test

    // only apply to ores
    // let light_u = extractBits(data.word0, 24u, 8u);
    // out.light = select(1.0, f32(light_u) / 3000.0 + 1.0, out.sprite_id >= ORE_START && out.sprite_id < GEM_START);

    out.light = 1.0;
    out.hp = extractBits(data.word1, 20u, 4u);
    // hp takes up the top 4 bits perfectly, 24-bit total
    let s1 = murmurmix32(extractBits(data.word1, 0u, 24u));
    let s2 = murmurmix32(s1);
    let s3 = murmurmix32(s2);
    out.seeds = vec3u(s1, s2, s3);
    out.waterlogged = extractBits(data.word1, 28u, 4u);
    return out;
}

// Main vertex shader for tiles.
@vertex
fn vs_tile(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32
) -> TileOutput {
    // A bitmask where bits 1, 4, and 5 are set (0b110010 = 50) and bits 2, 3, and 5 are set (0b101100 = 44)
    let local_pos = vec2f((vec2u(50u, 44u) >> vec2u(vertex_index)) & vec2u(1u));

    let total_tiles = scene.map_size.x * scene.map_size.y;
    var out: TileOutput;

    if instance_index == total_tiles {
        // There's intentionally one more instance than the number of tiles to render the player!
        let world_pos = scene.player_screen_pos + local_pos * TILE_SIZE;
        let screen_pos = (world_pos - scene.camera) * scene.zoom + (scene.viewport_size * 0.5);

        // normalized device coordinates
        let ndc = (screen_pos / scene.viewport_size) * vec2f(2.0, -2.0) + vec2f(-1.0, 1.0);

        out.position = vec4f(ndc, 0.0, 1.0);
        out.sprite_uv_origin = vec2f(1.0 * SPRITE_W, 0.0 * SPRITE_H);
        out.edge_flags = 255u;
        out.sprite_id = 1u;
        out.light = 1.0;
        out.local_uv = local_pos;
        return out;
    }

    let tile = unpack_tile(tiles[instance_index]);
    if tile.sprite_id == 0u && scene.wireframe_opacity == 0.0 {
        out.position = vec4f(2.0, 2.0, 2.0, 1.0); // ideal outcode
        return out;
    }

    let tile_coords = vec2u(instance_index % scene.map_size.x, instance_index / scene.map_size.x);
    var id = tile.sprite_id;

    let world_pixel_pos = (vec2f(tile_coords) + local_pos) * TILE_SIZE;
    let screen_pos = ((world_pixel_pos - scene.camera) * scene.zoom) + (scene.viewport_size * 0.5);

    // normalize coordinates
    // first, make sure spiral plant and ceiling flower move up (visually) by 2 pixels
    var vertical_offset = select(
        0.0,
        2.0 * scene.zoom,
        // spiral plant, ceiling flower
        id == DECOR_START + 0u || id == DECOR_START + 1u
    );

    // add to ID based on pre-determined shifts
    if id == STONE_START {
        // 2x2 grid stone pattern (like a 32x32 sprite)
        let offset = ((tile_coords.y & 1u) << 1u) | (tile_coords.x & 1u);
        id += offset;
    } else if id == 2 { // (IDs here hard-coded, like player)
        // edge stone alternates in a checkerboard pattern
        let offset = (tile_coords.x & 1u) ^ (tile_coords.y & 1u);
        id += offset;
    } else if id == DECOR_START + 1u {
        // seed-based variation for ceiling flowers
        id = select(id, id + 1, extractBits(tile.seeds[0], 16u, 1u) == 1u); // 50% odds to select the variation

        // for 25%:
        // let random_mod = extractBits(tile.seeds[0], 16u, 2u);
        // if random_mod == 0u {
        //     id++;
        // }
    } else if id == DECOR_START + 5u || id == DECOR_START + 8u { // variation for mushrooms
        let bits = extractBits(tile.seeds[0], 16u, 2u);
        id -= select(0u, bits, bits == 3u); // select variation (0, +1, or +2, 50% odds of 0)
    }

    // apply to screen_pos.y before converting to normalized device coordinates
    // subtract from Y because in screen space, lower values are "higher" up
    let adjusted_screen_pos = screen_pos - vec2f(0.0, vertical_offset);
    let ndc = (adjusted_screen_pos / scene.viewport_size) * vec2f(2.0, -2.0) + vec2f(-1.0, 1.0);

    // Calculate which sprite in the atlas to sample
    let origin = vec2f(f32(id % TILES_PER_ROW_U), f32(id / TILES_PER_ROW_U)) * vec2f(SPRITE_W, SPRITE_H);

    out.position = vec4f(ndc, 0.0, 1.0);
    out.sprite_uv_origin = origin;
    let is_gem = id >= GEM_START && id < GEM_MASK_START;
    // if is_gem {
    //     out.sprite_id = extractBits(tiles[instance_index].word0, 0u, 16u) | id;
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
fn fs_tile(in: TileOutput) -> @location(0) vec4f {
    var erode_mask: u32 = 1u;
    let id = in.sprite_id /* & 65535 */;
    if id == WATER_START || id == WATER_START + 1u {
        let has_top = (in.edge_flags & EDGE_TOP) != 0u;

        if !has_top {
            // This is the top surface of the water body!
            let t = scene.time;
            let world_pos = wrap_water_coords((vec2f(in.tile_coords) + scene.grid_origin.xy) * TILE_SIZE + in.local_uv * TILE_SIZE);

            // Sine-wave ripple effect at the surface (frequency is periodic over 65536.0 pixels)
            let base_height = 1.0 - (f32(in.hp) / 21.0);
            let ripple_freq = 4172.0 * TAU / 65536.0;
            let ripple = sin(world_pos.x * ripple_freq + t * 5.0) * 0.08 * base_height;
            let current_height = base_height + ripple - 0.2;

            // If the pixel is above the water surface, discard it
            if in.local_uv.y < (1.0 - current_height) {
                discard;
            }
        }
        return water_body(in);
    }
    let safe_local_uv = clamp(in.local_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));

    if in.edge_flags != 0xFFu {
        erode_mask = erosion(in.local_uv, in.edge_flags, in.seeds[1], in.seeds[2]);
        if scene.wireframe_opacity == 0.0 && erode_mask == 0u {
            if in.waterlogged != 0u {
                let is_water_top = (in.waterlogged & 1u) != 0u;
                let apply_ripple = (in.waterlogged & 2u) != 0u;
                let is_water_left = (in.waterlogged & 4u) != 0u;
                let is_water_right = (in.waterlogged & 8u) != 0u;

                var is_water_pixel = false;
                if is_water_top && in.local_uv.y < 0.5 {
                    is_water_pixel = true;
                }
                if is_water_left && in.local_uv.x < 0.5 {
                    is_water_pixel = true;
                }
                if is_water_right && in.local_uv.x >= 0.5 {
                    is_water_pixel = true;
                }

                if is_water_pixel {
                    if apply_ripple {
                        let t = scene.time;
                        let world_pos = wrap_water_coords((vec2f(in.tile_coords) + scene.grid_origin.xy) * TILE_SIZE + in.local_uv * TILE_SIZE);

                        // Sine-wave ripple effect at the surface (frequency adjusted to be periodic over 65536.0 pixels)
                        let base_height = 1.0 - (f32(in.hp) / 21.0);
                        let ripple_freq = 4172.0 * TAU / 65536.0;
                        let ripple = sin(world_pos.x * ripple_freq + t * 5.0) * 0.08 * base_height;
                        let current_height = base_height + ripple - 0.2;

                        // Fall back to the solid block texture above the ripple line
                        if in.local_uv.y < (1.0 - current_height) {
                            is_water_pixel = false;
                        }
                    }
                }

                if is_water_pixel { return water_body(in); }
            }
            discard; // discard early
        }
    }

    let seed = in.seeds[0];
    let is_gem = id >= GEM_START && id < GEM_MASK_START;
    let is_ore = id >= ORE_START && id < GEM_START;

    var final_uv = in.sprite_uv_origin + safe_local_uv * vec2f(SPRITE_W, SPRITE_H);

    // Apply 0-15 pixel shift for gems and ores using bits 16-23 of seed3
    if is_gem || is_ore {
        let shift_bits = extractBits(in.seeds[2], 16u, 8u);
        let shift = vec2f(vec2u(shift_bits & 0xFu, shift_bits >> 4u)) / 16.0;
        let wrapped_local = fract(in.local_uv + shift);
        let safe_wrapped = clamp(wrapped_local, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
        final_uv = in.sprite_uv_origin + safe_wrapped * vec2f(SPRITE_W, SPRITE_H);
    }

    let hp_id = HP_SAMPLE_START + in.hp;
    let hp_grid = vec2f(f32(hp_id % TILES_PER_ROW_U), f32(hp_id / TILES_PER_ROW_U));
    let hp_uv = (hp_grid + safe_local_uv) * vec2f(SPRITE_W, SPRITE_H);

    // Sample the primary color (this will now be shifted for both Ores and Gems)
    var hp_darkness_mult = textureSampleLevel(sprite_atlas, pixel_sampler, hp_uv, 0.0).r;
    var tex_color = textureSampleLevel(sprite_atlas, pixel_sampler, final_uv, 0.0);
    tex_color = vec4f(srgb_to_linear(tex_color.rgb) * hp_darkness_mult, tex_color.a);

    // ore sampling pixel logic
    if is_gem || is_ore {
        // 8 masks, first 4 for gems, second 4 for ore
        let mask_variation = extractBits(seed, 15u, 2u) + select(4u, 0u, is_gem);
        let mask_id = GEM_MASK_START + mask_variation;

        let flip = vec2f(vec2u(extractBits(seed, 25u, 1u), extractBits(seed, 26u, 1u)));
        let flipped_uv = mix(in.local_uv, 1.0 - in.local_uv, flip);
        // Use 2x2 grid logic for the background stone's ID
        let bg_id = STONE_START + (((in.tile_coords.y & 1u) << 1u) | (in.tile_coords.x & 1u));

        // Calculate UVs for the background stone
        let bg_grid = vec2f(f32(bg_id % TILES_PER_ROW_U), f32(bg_id / TILES_PER_ROW_U));
        let stone_uv = (bg_grid + safe_local_uv) * vec2f(SPRITE_W, SPRITE_H);

        // Calculate UVs for the mask (using the UNSHIFTED uv)
        let safe_flipped_uv = clamp(flipped_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
        let mask_grid = vec2f(f32(mask_id % TILES_PER_ROW_U), f32(mask_id / TILES_PER_ROW_U));
        let mask_uv = (mask_grid + safe_flipped_uv) * vec2f(SPRITE_W, SPRITE_H);

        let tex_stone = textureSampleLevel(sprite_atlas, pixel_sampler, stone_uv, 0.0);
        let tex_mask = textureSampleLevel(sprite_atlas, pixel_sampler, mask_uv, 0.0);

        let abs_dist = abs(in.local_uv - 0.5); // higher value means closer to EDGES
        let u_dist = 0.5 - max(abs_dist.x, abs_dist.y); // higher value means closer to CENTER

        // with linear RGB: r component of mask determines brightness, vary ore brightness, multiply stone brightness based on dist
        let final_rgb_ore = mix(
            srgb_to_linear(tex_stone.rgb) * vec3f(1.2 - 1.2 * u_dist),
            tex_color.rgb * vec3f(tex_mask.r),
            tex_mask.a + u_dist
        );
        tex_color = vec4f(final_rgb_ore, tex_color.a);
    }

    var wire_color = vec4f(0.0);

    if scene.wireframe_opacity != 0.0 {
        // render wireframe due to being at the edge of a block?
        let inv_tile_scale = 1.00001 / (TILE_SIZE * scene.zoom);
        let is_block_edge = any(in.local_uv < vec2f(inv_tile_scale)) || any(in.local_uv > vec2f(1.0 - inv_tile_scale));

        if is_block_edge {
            let mods = in.tile_coords & vec2u(15u);

            if id == 1u {
                wire_color = vec4f(1.0, 0.5, 0.0, 1.0);
            } else {
                // Is this pixel on the edge of a CHUNK?
                let is_chunk_edge = any((mods == vec2u(0u)) & (in.local_uv < vec2f(inv_tile_scale))) ||
                                    any((mods == vec2u(15u)) & (in.local_uv > vec2f(1.0 - inv_tile_scale)));

                if is_chunk_edge {
                    wire_color = vec4f(1.0, 1.0, 0.0, min(1.0, scene.wireframe_opacity * 2.5));
                } else {
                    // neat-lookin' fancy wireframe coloring
                    let rg = vec2f(mods) * 0.0625;
                    let b = 0.5 + f32(mods.x ^ mods.y) * 0.03125;
                    wire_color = vec4f(rg.x, rg.y, b, scene.wireframe_opacity);
                }
            }
        } else if erode_mask == 0u {
            discard;
        }
    }

    // convert to oklab and nudge values with seed
    var lab = linear_srgb_to_oklab(tex_color.rgb);
    var lch = oklab_to_oklch(lab);

    // we use 9 out of the 28 seed bits here
    let lab_nudge_bits = vec3u(
        extractBits(seed, 0u, 3u), // shift lightness (0-1)
        extractBits(seed, 3u, 3u), // shift chroma, which acts similar to saturation (in practice, between 0-0.4)
        extractBits(seed, 6u, 3u)// shift hue (in RADIANS, red isn't exactly 0)
    );
    let nudges = vec3f(lab_nudge_bits) / 7.0;

    // Apply light and nudges in a single MAD operation where possible
    lch *= vec3f(in.light, 1.0 + nudges.y * 0.2, 1.0) +
        vec3f(nudges.x * 0.02, 0.0, nudges.z * 0.1);

    var final_rgb = vec3f(0.0);
    if in.edge_flags != 0xFFu {
        // add the edge darkening and base light value, with the function using bits 10-16
        let darkening = calculate_edge_darkening(in.local_uv, in.edge_flags, seed);
        lch.x *= (1.0 - darkening);

        if erode_mask == 2u {
            lch *= vec3f(0.6 + f32(lab_nudge_bits.x) * 0.01, 1.3 + f32(lab_nudge_bits.y) * 0.04, 1.0);
        }
    }

    // convert OKLCH result to OKLAB, then finally back to float-based RGB
    lab = oklch_to_oklab(lch);
    final_rgb = oklab_to_linear_srgb(lab);

    var final_a = tex_color.a * select(scene.chunk_opacity, 1.0, id == 1u); // use chunk_opacity, unless this sprite is for the player

    if scene.wireframe_opacity != 0.0 {
        // Correctly mix the wireframe dynamically depending on whether the block exists below it.
        final_rgb = mix(final_rgb, wire_color.rgb, wire_color.a);
        final_a = max(final_a, wire_color.a);
    }

    return vec4f(apply_color_management(final_rgb), final_a);
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

// Complex logic that returns 0u if a pixel should be TRANSPARENT ("eroded"), 1u for NORMAL, or 2u for BORDER (darkened).
fn erosion(local_uv: vec2f, edge_flags: u32, seed2: u32, seed3: u32) -> u32 { // uv of sprite, edge flags, and mixed seeds
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
    let r_tl = 3u + extractBits(seed3, 0u, 2u);
    let r_tr = 3u + extractBits(seed3, 2u, 2u);
    let r_bl = 3u + extractBits(seed3, 4u, 2u);
    let r_br = 3u + extractBits(seed3, 6u, 2u);

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
        let base_depth = extractBits(seed2, 0u, 1u); // 0 or 1 pixels inward for each edge
        let notch_pos = extractBits(seed2, 1u, 4u);
        let notch_dir = extractBits(seed2, 5u, 1u);
        let notch_width = 2u + extractBits(seed2, 6u, 2u);

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
        let base_depth = extractBits(seed2, 8u, 1u);
        let notch_pos = extractBits(seed2, 9u, 4u);
        let notch_dir = extractBits(seed2, 13u, 1u);
        let notch_width = 2u + extractBits(seed2, 14u, 2u);

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
        let base_depth = extractBits(seed2, 16u, 1u);
        let notch_pos = extractBits(seed2, 17u, 4u);
        let notch_dir = extractBits(seed2, 21u, 1u);
        let notch_width = 2u + extractBits(seed2, 22u, 2u);

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
        let base_depth = extractBits(seed2, 24u, 1u);
        let notch_pos = extractBits(seed2, 25u, 4u);
        let notch_dir = extractBits(seed2, 29u, 1u);
        let notch_width = 2u + extractBits(seed2, 30u, 2u);

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
        let r = 1u + extractBits(seed3, 8u, 2u); // 1-4 pixel radius
        if px < r && py < r {
            let dx = px + 1u; // +1, so the circle center is at (-0.5, -0.5) effectively
            let dy = py + 1u;
            let dist_sq = dx * dx + dy * dy;
            if dist_sq <= r * r { return 0u; }
            if dist_sq <= (r + 1u) * (r + 1u) { return 2u; }
        }
    }

    if !has_tr && has_top && has_right {
        let r = 1u + extractBits(seed3, 10u, 2u);
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
        let r = 1u + extractBits(seed3, 12u, 2u);
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
        let r = 1u + extractBits(seed3, 14u, 2u);
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
fn calculate_edge_darkening(local_uv: vec2f, edge_flags: u32, seed: u32) -> f32 {
    let edge_width = 0.40 + f32(extractBits(seed, 9u, 3u)) / 32.0;
    let edge_strength = 0.4 + f32(extractBits(seed, 12u, 3u)) / 32.0;

    let dists = vec4f(local_uv.y, 1.0 - local_uv.y, local_uv.x, 1.0 - local_uv.x);
    let edge_masks = vec4u(edge_flags) & vec4u(EDGE_TOP, EDGE_BOTTOM, EDGE_LEFT, EDGE_RIGHT);
    let is_edge = edge_masks == vec4u(0u);

    let edge_darkenings = select(
        vec4f(0.0),
        (1.0 - smoothstep(vec4f(0.0), vec4f(edge_width), dists)) * edge_strength,
        is_edge
    );

    return max(max(edge_darkenings.x, edge_darkenings.y), max(edge_darkenings.z, edge_darkenings.w));
}

/*
    ----
    WATER
    ----
*/

fn wrap_water_coords(coords: vec2f) -> vec2f {
    return coords - floor(coords / 65536.0) * 65536.0;
}

// World-space pixel coordinate of this fragment (floating point, any value)
fn water_world(in: TileOutput) -> vec2f {
    return (vec2f(in.tile_coords) + scene.grid_origin.xy) * TILE_SIZE + in.local_uv * TILE_SIZE;
}

// Shared base LCH that cycles hue between teal and blue.
fn water_base_lch(t: f32) -> vec3f {
    let H = 3.8 + sin(t * (TAU / 3600.0)) * 0.34;
    return vec3f(0.42, 0.12, H);
}
fn water_effect(coord: vec2f, t: f32) -> f32 {
    let R = 256.0; // grid repeat period
    let L_FREQ = TAU / 3600.0; // base frequency per time loop
    // Every multiplier below is now an exact integer multiplied by L_FREQ
    let warp_val = sin((coord.y * 2.0) / R * TAU + t * (20.0 * L_FREQ)) * 4.0 + cos((coord.x * 3.0) / R * TAU - t * (12.0 * L_FREQ)) * 4.0;

    let world = coord + vec2f(warp_val, -warp_val);

    // First caustic layer
    // All layers are mades ure to be periodic every 65536 pixels.
    let d_a = world.x * 0.906 - world.y * 0.423;
    let a1 = sin((d_a + t * 15.0) / (65536.0 / 1489.0) * TAU) * 0.5 + 0.5;
    let a2 = sin((d_a * 1.15 + t * 13.0) / (65536.0 / 1638.0) * TAU) * 0.5 + 0.5;
    let band_a = a1 * a2 * 0.24;

    // Second layer (which crosses directions)
    let d_b = world.x * 0.643 - world.y * -0.766;
    let b1 = sin((d_b * 3.2 + t * 4.0) / 32.0 * TAU) * 0.5 + 0.5;
    let b2 = sin((d_b * 4.2 + t * 5.42) / (65536.0 / 2341.0) * TAU) * 0.5 + 0.5;
    let temp_b = b1 * b2;
    let band_b = temp_b * temp_b * 0.03;

    let d_c = world.x * 0.906 + world.y * 0.423;
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

// Procedural effect for all but the top water sprite
fn water_body(in: TileOutput) -> vec4f {
    let world = water_world(in);
    let t = scene.time;

    var lch = water_base_lch(t);

    // Depth gradient: lighter near y=0 (surface), darker going down.
    let depth_t = clamp(world.y / 192.0, 0.0, 1.0); // 192px
    lch.x = mix(0.52, 0.34, depth_t); // light surface
    lch.y = mix(0.10, 0.14, depth_t);// slightly more saturated deep

    // Horizontal color band (Celeste's characteristic depth striping)
    let band_t = sin(world.y / 24.0 + t * 0.4) * 0.5 + 0.5;
    lch.x += band_t * 0.04;

    let caustic = water_effect(world, t);
    lch.x = clamp(lch.x + caustic, 0.26, 0.90);
    lch.y = clamp(lch.y + caustic * 0.10, 0.04, 0.28);

    let rgb = oklab_to_linear_srgb(oklch_to_oklab(lch));
    return vec4f(apply_color_management(rgb), 0.5);
}

/*
    ----
    BACKGROUND
    ----
*/

// FBM background logic
struct BackgroundOutput {
    @builtin(position) position: vec4f,
    @location(0) screen_offset: vec2f,
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
    out.position = vec4f(x, y, 0.0, 1.0);

    let screen_uv = vec2f(x, -y) * 0.5 + 0.5;

    // Center the scale pivot to the screen center (camera and player viewport center)
    out.screen_offset = ((screen_uv - 0.5) * scene.viewport_size) / scene.zoom;

    // Zig-zag wrapping for colors
    var t_wrap = (scene.time * 0.3) % 2.0;
    if t_wrap > 1.0 { t_wrap = 2.0 - t_wrap; }

    var t_wrap_2 = (3.0 + scene.time * 0.072) % 2.0;
    if t_wrap_2 > 1.0 { t_wrap_2 = 2.0 - t_wrap_2; }

    out.time = t_wrap;
    out.time2 = t_wrap_2;

    return out;
}

@fragment
fn fs_background(in: BackgroundOutput) -> @location(0) vec4f {
    const base_scale = 0.015625; // Exactly 1.0 / 64.0 for seamless 256-chunk alignment
    let absolute_camera = scene.grid_origin.zw;
    let t = scene.time;

    // The farthest background layer (64x "slower")
    let st1 = (in.screen_offset + absolute_camera * 0.015625) * base_scale;
    let angle1 = (t / 600.0) * TAU; // 10-minute cycle!
    let drift1 = vec2f(cos(angle1), sin(angle1)) * 0.5;

    let q1 = noise(st1 * 0.45 + drift1);
    let f1 = noise(st1 * 0.85 + q1 * 1.5);

    let color1 = mix(
        vec3f(0.12, 0.22, 0.05),
        vec3f(0.12, 0.11, 0.03),
        f1
    );

    let layer1_intensity = clamp(f1 * f1 * 0.4, 0.1, 1.0);
    let layer1_rgb = layer1_intensity * color1;

    // Far background layer (32x "slower")
    let st2 = (in.screen_offset + absolute_camera * 0.03125) * base_scale;
    let angle2 = (t / 180.0) * TAU; // 3-minute cycle
    let drift2_x = vec2f(cos(angle2), sin(angle2)) * 1.0;
    let drift2_y = vec2f(sin(angle2), -cos(angle2)) * 0.8;

    var q2 = vec2f(0.0);
    q2.x = noise(st2 * 0.3 + drift2_x * 0.1);
    q2.y = noise(st2 * 0.3 + vec2f(1.0, 0.3) + drift2_y * 0.1);

    let f2 = fbm_3(st2 * 0.5 + 2.0 * q2);

    let mix_blue = mix(0.0, 0.4, in.time);
    let color2 = mix(
        vec3f(0.0, 0.005, mix_blue * mix_blue * 0.5),
        vec3f(0.05, 0.15, 0.25),
        clamp(f2 * f2 * 3.0, 0.0, 1.0)
    );
    let layer2_intensity = max(f2 * f2 * sqrt(f2) * 1.5 - 0.1, 0.0);
    let layer2_rgb = layer2_intensity * color2;

    // Middle background layer (8x "slower")
    let st3 = (in.screen_offset + absolute_camera * 0.125) * base_scale;
    let angle3 = (t / 60.0) * TAU; // only 60s
    let drift3_x = vec2f(cos(angle3), sin(angle3)) * 1.8;
    let drift3_y = vec2f(sin(angle3), -cos(angle3)) * 1.5;

    var q3 = vec2f(0.0);
    q3.x = noise(st3 * 0.6 + drift3_x * 0.2);
    q3.y = noise(st3 * 0.6 + vec2f(2.4, 1.1) + drift3_y * 0.2);

    var r3 = vec2f(0.0);
    r3.x = fbm_2(st3 * 1.8 + 3.0 * q3 + drift3_x);
    r3.y = fbm_2(st3 * 1.8 + 3.0 * q3 + drift3_y);

    let f3 = fbm_4(st3 * 1.2 + 2.5 * r3);

    let mix_red = mix(0.0, 0.3, in.time + in.time2);
    let mix_green = mix(0.0, 0.6, in.time2);
    let color3 = mix(
        vec3f(0.01, 0.05, 0.1),
        vec3f(mix_red * mix_red, mix_green * mix_green, 0.5),
        clamp(length(q3 * r3), 0.0, 1.0)
    );
    let layer3_intensity = max(f3 * f3 * f3 * 2.5 - 0.2, 0.0);
    let layer3_rgb = layer3_intensity * color3;

    // Additive screen blend of both seamless layers
    let final_rgb = layer1_rgb + layer2_rgb + layer3_rgb;

    let opacity = scene.chunk_opacity;
    return vec4f(final_rgb * opacity, opacity);
}

fn noise(st: vec2f) -> f32 {
    let i = vec2u(vec2i(floor(st)));
    let f = fract(st);

    // Make the grid noise perfectly periodic with a period of 32 units
    let ix = (i.x + vec4u(0u, 1u, 0u, 1u)) % vec4u(32u);
    let iy = (i.y + vec4u(0u, 0u, 1u, 1u)) % vec4u(32u);

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

fn fbm_3(p: vec2f) -> f32 { // same as above but 3 iters
    var v = 0.0;
    var a = 0.5;
    var shift = vec2f(100.0);
    var pos = p;
    for (var i = 0; i < 3; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn fbm_4(p: vec2f) -> f32 { // same as above but 4 iters (wow, who could have guessed!)
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
        0.0514459929, 0.1073969566, 0.6299787005);
    let lms = max(m1 * c, vec3f(0.0));
    let lms_ = pow(lms, vec3f(1.0 / 3.0));

    let m2 = mat3x3f( // convert to OKLAB
        0.2104542553, 1.9779984951, 0.0259040371,
        0.7936177850, -2.4285922050, 0.7827717662,
        -0.0040720468, 0.4505937099, -0.8086758031);
    return m2 * lms_;
}

/*
    ----
    ENTITIES
    ----
*/

struct WGSLEntity {
    lcha: vec4f,
    position: vec2f,
    size: vec2f,
    rotation: f32,
    id: u32,
    _pad: vec2u,
}

struct EntityOutput {
    @builtin(position) position: vec4f,
    @location(0) local_uv: vec2f,
    @location(1) @interpolate(flat) lcha: vec4f,
    @location(2) @interpolate(flat) id: u32,
    @location(3) @interpolate(flat) sprite_uv_origin: vec2f,
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
    //     out.position = vec4f(2.0, 2.0, 2.0, 1.0); // ideal outcode
    // }

    // A bitmask where bits 1, 4, and 5 are set (0b110010 = 50) and bits 2, 3, and 5 are set (0b101100 = 44)
    let local_pos = vec2f((vec2u(50u, 44u) >> vec2u(vertex_index)) & vec2u(1u));
    let centered_pos = local_pos - 0.5f;

    // Rotate sprite as needed (in radians)
    let c = cos(entity.rotation);
    let s = sin(entity.rotation);
    let rotated_pos = vec2f(
        centered_pos.x * c - centered_pos.y * s,
        centered_pos.x * s + centered_pos.y * c
    );

    let pixel_pos = entity.position + rotated_pos * entity.size;

    // Convert to normalized device coords
    let ndc = pixel_pos * vec2f(2.0, -2.0) + vec2f(-1.0, 1.0);

    // Calculate UV origin
    var origin = vec2f(
        f32(entity.id % TILES_PER_ROW_U),
        f32(entity.id / TILES_PER_ROW_U)
    ) * vec2f(SPRITE_W, SPRITE_H);

    var out: EntityOutput;
    out.position = vec4f(ndc, 0.0, 1.0);
    out.local_uv = local_pos;
    out.lcha = entity.lcha;
    out.id = entity.id;
    out.sprite_uv_origin = origin;
    return out;
}

@fragment
fn fs_entity(in: EntityOutput) -> @location(0) vec4f {
    // Calculate UVs with bleeding protection
    let safe_local_uv = clamp(in.local_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
    let final_uv = in.sprite_uv_origin + safe_local_uv * vec2f(SPRITE_W, SPRITE_H);

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

    // Apply modifications from lcha (vec4f: L, C, H, A), see zig/render/entity.zig
    lch.x *= in.lcha.x; // mult light
    lch.y += in.lcha.y; // add chroma
    lch.z += in.lcha.z; // add hue

    lab = oklch_to_oklab(lch);
    let final_rgb = oklab_to_linear_srgb(lab);

    // apply alpha after being back to RGB!
    let final_a = tex_a * in.lcha.w;
    return vec4f(apply_color_management(final_rgb), final_a);
}

/*
    ----
    OKLAB AND COLOR SPACE
    (There are a lot of magic numbers here.)
    ----
*/
fn oklab_to_linear_srgb(c: vec3f) -> vec3f {
    let m1 = mat3x3f( // LMS
        1.0, 1.0, 1.0,
        0.3963377774, -0.1055613458, -0.0894841775,
        0.2158037573, -0.0638541728, -1.2914855480);
    let lms_ = m1 * c;
    let lms = lms_ * lms_ * lms_;

    let m2 = mat3x3f( // convert back to normal srgb
        4.0767416621, -1.2684380046, -0.0041960863,
        -3.3077115913, 2.6097574011, -0.7034186147,
        0.2309699292, -0.3413193965, 1.7076127010);
    let result = m2 * lms;
    return max(result, vec3f(0.0)); // prevent out of range values
}

fn oklab_to_oklch(lab: vec3f) -> vec3f {
    let chroma = length(lab.yz);
    var hue = 0.0;
    // prevent invalid numbers with this check
    if chroma > 0.0001 {
        hue = atan2(lab.z, lab.y);
    }
    return vec3f(lab.x, chroma, hue);
}

fn oklch_to_oklab(lch: vec3f) -> vec3f {
    return vec3f(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z));
}

fn srgb_to_linear(c: vec3f) -> vec3f {
    return select(
        c / 12.92,
        pow((c + 0.055) / 1.055, vec3f(2.4)),
        c > vec3f(0.04045)
    );
}

fn linear_to_srgb(c: vec3f) -> vec3f {
    let safe_c = max(c, vec3f(0.0));
    return select(
        12.92 * safe_c,
        1.055 * pow(safe_c, vec3f(1.0 / 2.4)) - 0.055,
        safe_c > vec3f(0.0031308)
    );
}

fn linear_srgb_to_display_p3(rgb: vec3f) -> vec3f {
    let m = mat3x3f(
        0.822462, 0.033194, 0.017083,
        0.177538, 0.966806, 0.072397,
        0.000000, 0.000000, 0.910520
    );
    return max(m * rgb, vec3f(0.0));
}

// Change the final RGB value based on color space info.
fn apply_color_management(linear_rgb: vec3f) -> vec3f {
    var out = linear_rgb;
    // Convert color space while still linear
    if scene.flags.x == 1u { // isP3
        out = linear_srgb_to_display_p3(out);
    }
    return linear_to_srgb(out); // always apply transfer function
}
`,Y=""+new URL("main.png",import.meta.url).href,Q=""+new URL("mainMasked.png",import.meta.url).href;async function J(r,e){const n=await navigator.gpu.requestAdapter({powerPreference:e&&e.highPerformance?"high-performance":"low-power"});if(!n)throw new DOMException("Couldn't request WebGPU adapter.","NotSupportedError");const i=await n.requestDevice();let t=null;if(i.addEventListener("uncapturederror",_=>{const h=_.error;if(t===null)if(globalThis.reportError)reportError(h);else throw h;else if(!t.destroyed){t.destroy("fatal WebGPU error",h);return}}),i.lost.then(_=>console.error(`WebGPU Device lost: ${_.message}`)),r===void 0){if(r=document.getElementsByTagName("canvas")[0],r===void 0)throw Error("No canvas element or ID string provided, and no canvas was not found in the HTML.")}else if(typeof r=="string"){const _=document.getElementById(r);if(!(_ instanceof HTMLCanvasElement))throw Error(`Element with ID "${r}" is not a canvas element.`);r=_}const s=r.getContext("webgpu");if(!s)throw Error("Could not get WebGPU context from canvas.");const a=window.matchMedia("(color-gamut: p3)").matches,l=i.features.has("canvas-rgba16float-support")?"rgba16float":"bgra8unorm";s.configure({device:i,format:l,colorSpace:a&&l==="rgba16float"?"display-p3":"srgb",alphaMode:"opaque"});const c=await WebAssembly.instantiateStreaming(fetch(X),{env:{jsMessage:(_,h,m)=>{let g=new TextDecoder().decode(new Uint8Array(p.buffer,Number(_),Number(h)));g.charAt(0)!=="]"?g="["+(t.LOGGING_PREFIX||"")+g:g=g.slice(1),m===1?console.info("%c"+g,"font-weight: 600"):[console.log,console.info,console.warn,console.error][m](g)},jsWriteText:(_,h,m)=>{const g=new Uint8Array(p.buffer,Number(h),Number(m)),z=new TextDecoder().decode(g),q=document.getElementById(`text${_+1}`);q.textContent=z},jsGetTime:()=>performance.now(),jsHandleVisibleChunks:(_,h)=>t.handleVisibleChunks(_,h),jsHandleVisibleEntities:()=>t.handleVisibleEntities(),jsSetMouseType:_=>t.setMouseType(_),jsPlaySound:(_,h,m)=>t.playSound(_,h,m)}}),f=c.instance.exports,p=f.memory,d=i.createShaderModule({label:"Main shader",code:j.replace("/* TILES_PER_ROW */ 1 /* TILES_PER_ROW */",""+f.getTilesPerRow()).replace("/* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */",""+f.getTilesPerColumn()).replace("/* STONE_START */ 1 /* STONE_START */",""+f.getStoneStart()).replace("/* ORE_START */ 1 /* ORE_START */",""+f.getOreStart()).replace("/* GEM_START */ 1 /* GEM_START */",""+f.getGemStart()).replace("/* GEM_MASK_START */ 1 /* GEM_MASK_START */",""+f.getGemMaskStart()).replace("/* DECOR_START */ 1 /* DECOR_START */",""+f.getDecorStart()).replace("/* WATER_START */ 1 /* WATER_START */",""+f.getWaterStart())}),E=i.createBindGroupLayout({label:"Main bind group layout",entries:[{binding:0,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"uniform",hasDynamicOffset:!0}},{binding:1,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"read-only-storage"}},{binding:2,visibility:GPUShaderStage.FRAGMENT,texture:{}},{binding:3,visibility:GPUShaderStage.FRAGMENT,texture:{}},{binding:4,visibility:GPUShaderStage.FRAGMENT,sampler:{}},{binding:5,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"read-only-storage"}}]}),S=i.createPipelineLayout({label:"Shared Pipeline Layout",bindGroupLayouts:[E]}),O=i.createRenderPipeline({label:"Tilemap pipeline",layout:S,vertex:{module:d,entryPoint:"vs_tile"},fragment:{module:d,entryPoint:"fs_tile",targets:[{format:l,blend:{color:{srcFactor:"src-alpha",dstFactor:"one-minus-src-alpha"},alpha:{srcFactor:"one",dstFactor:"one-minus-src-alpha"}}}]},primitive:{topology:"triangle-list",cullMode:"none"}}),M=i.createRenderPipeline({label:"Background pipeline",layout:S,vertex:{module:d,entryPoint:"vs_background"},fragment:{module:d,entryPoint:"fs_background",targets:[{format:l}]},primitive:{topology:"triangle-list"}}),D=i.createRenderPipeline({label:"Entity pipeline",layout:S,vertex:{module:d,entryPoint:"vs_entity"},fragment:{module:d,entryPoint:"fs_entity",targets:[{format:l,blend:{color:{srcFactor:"src-alpha",dstFactor:"one-minus-src-alpha"},alpha:{srcFactor:"one",dstFactor:"one-minus-src-alpha"}}}]},primitive:{topology:"triangle-list"}});t=new w(r,n,i,s,c,O,M,D),t.exports.main(),await t.setSeed(H(100)),t.startDelta=Number(f.mixSeed(60n)%120000n),t.exports.init();const G=new ResizeObserver(t.onResize);t.resizeObserver=G,t.updateCanvasStyle();try{t.resizeObserver.observe(r,{box:"device-pixel-content-box"})}catch{console.log("ResizeObserver property device-pixel-content-box not supported, falling back to content-box."),t.resizeObserver.observe(r,{box:"content-box"})}t.onResize([{contentRect:{width:r.clientWidth,height:r.clientHeight}}]);const C=await w.loadTexture(i,Y),F=await w.loadTexture(i,Q,"rgba8unorm"),N=i.createSampler({magFilter:"nearest",minFilter:"nearest",addressModeU:"clamp-to-edge",addressModeV:"clamp-to-edge"});return t.atlasTextureView=C.createView(),t.atlasTextureMaskView=F.createView(),t.pixelSampler=N,t.uniformBuffer=i.createBuffer({label:"SceneUniforms",size:256*v,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST}),t.entityBuffer=t.device.createBuffer({label:"Entities",size:2400,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),t.isP3=a&&l==="rgba16float",t.is8Bit=l==="bgra8unorm",t.gamutMediaQuery=window.matchMedia("(color-gamut: p3)"),t.gamutMediaQuery.addEventListener("change",_=>{const h=_.matches&&l==="rgba16float";h!==t.isP3&&(t.isP3=h,s.configure({device:i,format:l,colorSpace:h?"display-p3":"srgb",alphaMode:"opaque"}))}),t}var U=(r=>(r[r.Uint8=8]="Uint8",r[r.Uint16=16]="Uint16",r[r.Uint32=32]="Uint32",r[r.Uint64=64]="Uint64",r[r.Int8=-8]="Int8",r[r.Int16=-16]="Int16",r[r.Int32=-32]="Int32",r[r.Int64=-64]="Int64",r[r.Uint8Clamped=1]="Uint8Clamped",r[r.Float32=2]="Float32",r[r.Float64=4]="Float64",r))(U||{});globalThis.WasmTypeCode=U;const L={8:Uint8Array,16:Uint16Array,32:Uint32Array,64:BigUint64Array,[-8]:Int8Array,[-16]:Int16Array,[-32]:Int32Array,[-64]:BigInt64Array,1:Uint8ClampedArray,2:Float32Array,4:Float64Array},v=4;class w{engineModule;exports;memory;LAYOUT_PTR;GAME_STATE_PTR;mouseType;canvas;adapter;device;context;bindGroups=Array(v);uniformBuffer;tileBuffers=Array(v);entityBuffer;tileBufferDirty=!1;atlasTextureView;atlasTextureMaskView;pixelSampler;tilePipeline;bgPipeline;entityPipeline;renderPass=null;currentEncoder=null;currentTextureView=null;renderCallId=0;sceneDataBuffer=new ArrayBuffer(256);sceneDataF32=new Float32Array(this.sceneDataBuffer);sceneDataU32=new Uint32Array(this.sceneDataBuffer);inputState;resizeObserver;forceAspectRatio=!0;previousForceAspectRatio=null;tileMapWidth;tileMapHeight;last_upload_visible_chunks_time=0;prepare_visible_data_time=0;isVisibleDataNew=!0;wireframeOpacity=0;startTime=performance.now();startDelta;seed="";destroyed=!1;destroyedError=null;encoder=new TextEncoder;decoder=new TextDecoder;isP3=!1;is8Bit=!1;gamutMediaQuery=null;LOGGING_PREFIX="";audioCtx=null;audioBuffers=new Map;audioLoading=new Map;constructor(e,n,i,t,s,a,l,c){this.canvas=e,this.adapter=n,this.device=i,this.context=t,this.engineModule=s,this.tilePipeline=a,this.bgPipeline=l,this.entityPipeline=c,this.exports=s.instance.exports,this.memory=s.instance.exports.memory,this.LAYOUT_PTR=Number(this.exports.getMemoryLayoutPtr()),this.GAME_STATE_PTR=Number(this.getScratchView()[3]),this.inputState=$()}static async create(e,n){return await J(e,n)}destroy(e="unknown reason",n=null){this.resizeObserver.disconnect(),this.destroyed=e,this.destroyedError=n}static async loadTexture(e,n,i){const s=await(await fetch(n)).blob(),a=await createImageBitmap(s),l=i||(e.features.has("canvas-rgba16float-support")?"rgba16float":"bgra8unorm"),c=e.createTexture({label:`Texture from ${n}`,size:[a.width,a.height],format:l,usage:GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT});return e.queue.copyExternalImageToTexture({source:a},{texture:c},[a.width,a.height]),c}uploadVisibleChunks(e=1){const n=performance.now();this.exports.prepareVisibleData(e,n-this.last_upload_visible_chunks_time,this.canvas.width,this.canvas.height),this.last_upload_visible_chunks_time=n,this.prepare_visible_data_time=performance.now()-n}handleVisibleChunks(e,n){if(this.wireframeOpacity=n,!this.currentEncoder||!this.currentTextureView||!this.renderPass)return;const i=this.getScratchPtr();if(this.getScratchLen()===0)return;const s=Number(this.getScratchProperty(0)),a=Number(this.getScratchProperty(1)),l=s*a*2;this.tileMapWidth=s,this.tileMapHeight=a;const c=new Uint32Array(this.memory.buffer,i,l);this.recreateBufferAndBindGroup(l*4),this.renderPass.setPipeline(this.tilePipeline),this.renderPass.setBindGroup(0,this.bindGroups[this.renderCallId],[this.renderCallId*256]),this.renderPass.setViewport(0,0,this.canvas.width,this.canvas.height,0,1),this.setSceneData(e,s,a),this.device.queue.writeBuffer(this.tileBuffers[this.renderCallId],0,c);const f=s*a+1;this.renderPass.draw(6,f),this.renderCallId++}handleVisibleEntities(){this.renderCallId=0;const e=this.getScratchPtr(),n=this.getScratchProperty(0)*48;if(n===0||!this.renderPass)return;this.entityBuffer.size<n&&(this.entityBuffer=this.device.createBuffer({label:"Entities",size:n,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),this.recreateBufferAndBindGroup(0));const i=new Uint8Array(this.memory.buffer,e,n);this.device.queue.writeBuffer(this.entityBuffer,0,i),this.renderPass.setPipeline(this.entityPipeline),this.renderPass.setBindGroup(0,this.bindGroups[0],[0]),this.renderPass.draw(8,n/48)}setMouseType(e){e==0?this.mouseType!=0&&(this.canvas.style.cursor=null):e==1&&this.mouseType!=0&&(this.canvas.style.cursor="pointer"),this.mouseType=e}setSceneData(e,n,i){const t=this.getScratchProperty(2,4),s=this.getScratchProperty(3,4),a=this.getScratchProperty(4,4),l=this.getScratchProperty(5,4),c=this.getScratchProperty(6,4),f=this.getScratchProperty(7,4),p=this.getScratchProperty(8,4),d=this.getScratchProperty(9,4),E=this.getScratchProperty(10,4);this.sceneDataF32[0]=t,this.sceneDataF32[1]=s,this.sceneDataF32[2]=this.canvas.width,this.sceneDataF32[3]=this.canvas.height,this.sceneDataF32[4]=(performance.now()-this.startTime+this.startDelta)%(3600*1e3)/1e3,this.sceneDataF32[5]=a,this.sceneDataF32[6]=a<.25?0:this.wireframeOpacity,this.sceneDataF32[7]=e,this.sceneDataF32[8]=l,this.sceneDataF32[9]=c,this.sceneDataU32[10]=n,this.sceneDataU32[11]=i,this.sceneDataU32[12]=this.isP3?1:0,this.sceneDataU32[13]=this.is8Bit?1:0,this.sceneDataF32[16]=f,this.sceneDataF32[17]=p,this.sceneDataF32[18]=d,this.sceneDataF32[19]=E,this.device.queue.writeBuffer(this.uniformBuffer,this.renderCallId*256,this.sceneDataF32)}recreateBufferAndBindGroup(e){const n=this.renderCallId;(e===0||!this.tileBuffers[n]||this.tileBuffers[n].size<e)&&(this.tileBuffers[n]=this.device.createBuffer({label:`Tile grid slot ${n}`,size:Math.max(e,256*v),usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),this.bindGroups[n]=this.device.createBindGroup({label:`Bind group slot ${n}`,layout:this.tilePipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:this.uniformBuffer,offset:0,size:256}},{binding:1,resource:{buffer:this.tileBuffers[n]}},{binding:2,resource:this.atlasTextureView},{binding:3,resource:this.atlasTextureMaskView},{binding:4,resource:this.pixelSampler},{binding:5,resource:{buffer:this.entityBuffer}}]}))}async getAudioBuffer(e){if(this.audioBuffers.has(e))return this.audioBuffers.get(e);if(this.audioLoading.has(e))return this.audioLoading.get(e);this.audioCtx||(this.audioCtx=new(window.AudioContext||window.webkitAudioContext));const n=this.audioCtx,i=(async()=>{try{const t=await fetch(["",`assets/mining${e}.mp3`,`assets/mining${e}.mp3`,`assets/mining${e}.mp3`,"assets/grass1.mp3","assets/grass2.mp3","assets/place.mp3"][e]);if(!t.ok)throw new Error(`HTTP error! status: ${t.status}`);const s=await t.arrayBuffer(),a=await n.decodeAudioData(s);return this.audioBuffers.set(e,a),a}catch(t){throw this.audioLoading.delete(e),t}finally{this.audioLoading.delete(e)}})();return this.audioLoading.set(e,i),i}playSound(e,n,i){this.audioCtx&&this.audioCtx.state==="suspended"&&this.audioCtx.resume(),this.getAudioBuffer(e).then(t=>{const s=this.audioCtx,a=s.createBufferSource();a.buffer=t;const l=s.createGain();l.gain.setValueAtTime(n,s.currentTime),a.playbackRate.setValueAtTime(i,s.currentTime),a.connect(l),l.connect(s.destination),a.start(0)}).catch(t=>{console.warn(`Could not play sound ${e}:`,t)})}getWASMMemoryMB(){return this.memory.buffer.byteLength/1024/1024}getGameView(e,n=0,i){return new L[e](this.memory.buffer,this.GAME_STATE_PTR+n,i)}getRawView(e,n,i){return new L[e](this.memory.buffer,n,i)}_tempScratchViewU64=null;_tempScratchViewF64=null;getScratchView(){return(this._tempScratchViewU64===null||this._tempScratchViewU64.buffer!==this.memory.buffer)&&(this._tempScratchViewU64=new BigUint64Array(this.memory.buffer,this.LAYOUT_PTR,24)),this._tempScratchViewU64}getScratchPtr(){return Number(this.getScratchView()[0])}getScratchLen(){return Number(this.getScratchView()[1])}setScratchLen(e){this.getScratchView()[1]=BigInt(e)}getScratchCapacity(){return Number(this.getScratchView()[2])}getScratchProperty(e,n=64){(this._tempScratchViewU64===null||this._tempScratchViewU64.buffer!==this.memory.buffer)&&(this._tempScratchViewU64=new BigUint64Array(this.memory.buffer,this.LAYOUT_PTR,24));let i=this._tempScratchViewU64;return n==4&&((this._tempScratchViewF64===null||this._tempScratchViewF64.buffer!==this.memory.buffer)&&(this._tempScratchViewF64=new Float64Array(i.buffer,i.byteOffset,i.length)),i=this._tempScratchViewF64),Number(i[e+4])}readStr(e=this.getScratchPtr(),n=this.getScratchLen()){const i=new Uint8Array(this.memory.buffer,e,n);return this.decoder.decode(i)}writeStr(e,n=!0){const i=e.length;if(i===0)return null;n&&this.setScratchLen(0);const t=this.exports.scratchAlloc(i);if(t===0n)return null;const s=new Uint8Array(this.memory.buffer,Number(t),i);if(this.encoder.encodeInto(e,s).read<i)throw new RangeError("String truncated with non-ASCII characters detected.");return Number(t)}async setSeed(e){this.seed=e,await K(e,this.getGameView(64,k.seed,8))}updateCanvasStyle(){this.forceAspectRatio!==this.previousForceAspectRatio&&(this.previousForceAspectRatio=this.forceAspectRatio,this.forceAspectRatio?(this.canvas.style.maxWidth=`calc(100vh*${16/9})`,this.canvas.style.maxHeight=`calc(100vw*${9/16})`):(this.canvas.style.maxWidth="none",this.canvas.style.maxHeight="none"))}onResize=e=>{const n=e[0];let i,t;if(n.devicePixelContentBoxSize)i=n.devicePixelContentBoxSize[0].inlineSize,t=n.devicePixelContentBoxSize[0].blockSize;else if(n.contentBoxSize){const s=n.contentBoxSize[0].inlineSize,a=n.contentBoxSize[0].blockSize;i=Math.round(s*devicePixelRatio),t=Math.round(a*devicePixelRatio)}else{const s=n.contentRect.width,a=n.contentRect.height;i=Math.round(s*devicePixelRatio),t=Math.round(a*devicePixelRatio)}(this.canvas.width!==i||this.canvas.height!==t)&&(this.canvas.width=i,this.canvas.height=t)};renderFrame(e,n){if(this.renderCallId=0,this.destroyed!==!1)return;this.updateCanvasStyle(),this.currentEncoder=this.device.createCommandEncoder(),this.currentTextureView=this.context.getCurrentTexture().createView();const i=this.currentEncoder.beginRenderPass({colorAttachments:[{view:this.currentTextureView,loadOp:"clear",clearValue:{r:0,g:0,b:0,a:1},storeOp:"store"}]});this.renderPass=i,this.recreateBufferAndBindGroup(256*v),this.sceneDataF32[7]=1,this.sceneDataU32[12]=this.isP3?1:0,this.sceneDataU32[13]=this.is8Bit?1:0,this.device.queue.writeBuffer(this.uniformBuffer,this.renderCallId*256,this.sceneDataF32),this.renderPass.setPipeline(this.bgPipeline),this.renderPass.setBindGroup(0,this.bindGroups[this.renderCallId],[this.renderCallId++*256]),this.renderPass.draw(3),this.uploadVisibleChunks(e),this.renderPass.end(),this.device.queue.submit([this.currentEncoder.finish()]),this.currentEncoder=null,this.currentTextureView=null}tick(e,n){const i=this.getGameView(32,k.keys_pressed_mask,2);Z(this.inputState),i[0]=this.inputState.keysPressed,i[1]=this.inputState.keysHeld,this.exports.tick(e,n)}}location.protocol==="file:"&&alert("This game cannot run from a local file:// context; use an online version or test from localhost instead.");isSecureContext||alert("This game cannot run in a non-secure context.");navigator.gpu||alert("WebGPU is not supported by your browser; try playing this on an alternate or more modern browser.");const ee=await navigator.gpu.requestAdapter();ee||alert("WebGPU is supported by the browser, but no compatible GPU was found. Your GPU may be too old to play this game.");globalThis.Zig={KeyBits:o,game_state_offsets:k};console.log("Zig code is in debug mode. Use engine.exports to see its functions, variables, and memory, such as engine.exports.test_logs."),document.body.innerHTML+=`<div id="textContainer">
        <div id="text1"></div>
        <div id="text2"></div>
        <div id="text3"></div>
        <div id="text4"></div>
    </div>
    <div id="logicText"></div>
    <div id="renderText"></div>
    <div id="debugContainer"></div>`;{const r=(e,n,i,t)=>{const s=e||{};let l=`An error occurred: ${s.message||String(e||"Unknown error")}`;const c=i||s.line,f=t||s.column;if(n||c||f){const d=n?n.split("/").pop()||n:"unknown";l+=`
Source: ${d}:${c||"?"}:${f||"?"}`}let p=globalThis.engine?.destroyedError;if(globalThis.engine?.destroyedError&&(l+=`
Details: ${p.message||p}`),s.stack)l+=`

Stack trace:
${s.stack}`;else if(typeof e=="object"&&e!==null)try{const d=JSON.stringify(e);d!=="{}"&&(l+=`
Object state: ${d}`)}catch{l+=`
(Object state hidden: circular reference)`}alert(l)};window.onerror=(e,n,i,t,s)=>{r(s||e,n,i,t)},window.onunhandledrejection=e=>{r(e.reason)},console.error=(...e)=>{const n=e.find(i=>i instanceof Error)||e[0];r(n)}}document.addEventListener("wheel",function(r){r.ctrlKey},{passive:!1});let u=await w.create();u.getTimeoutLength=function(){return++te%3==2?16:17};u.getFrameRate=function(){return 60};u.baseSpeed=1;let y=performance.now(),b=0,te=0;globalThis.engine=u;const R=Array(60).fill(0),A=Array(60).fill(0),P=Array(60).fill(0);u.isDebug=!!u.exports.isDebug();u.renderLoop=function(r){let e=performance.now(),n=y===1/0?0:e-y;y=e;const i=1e3/u.getFrameRate(),t=n/i,s=Math.min(b+t,5);let a=Math.floor(s);a>0?(u.logicLoop(a),b=s-a):b=s;{A.shift(),A.push(n),P.shift(),P.push(u.prepare_visible_data_time);const c=Math.max.apply(null,A),f=Math.max.apply(null,P);let p="#cccccc";c>55?p="#e83769":c>30?p="#f39c19":c>20&&(p="#f7ce1a");const d=document.getElementById("renderText");d.textContent=`Time since last render/prepare_visible_data time: ${n.toFixed(1)}ms, ${u.prepare_visible_data_time.toFixed(1)}ms
Worst (past 60 frames): ${c.toFixed(1)}ms, ${f.toFixed(1)}ms`,d.style.fontWeight=c>40?c>55?700:600:500,d.style.color=p}let l=Math.min(b-1,0);u.renderFrame(l,y),requestAnimationFrame(u.renderLoop)};u.logicLoop=function(r){const e=performance.now(),n=60/u.getFrameRate()*u.baseSpeed;u.tick(n,r);let i=performance.now()-e;{R.shift(),R.push(i);const t=Math.max.apply(null,R);let s="#cccccc";t>30?s="#e83769":t>15?s="#f39c19":t>10&&(s="#f7ce1a");const a=document.getElementById("logicText");a.textContent=`Logic diff: ${i.toFixed(1)}ms for ${r} tick${r==1?"":"s"}
Worst (past 60 frames): ${t.toFixed(1)}ms
`,a.style.fontWeight=t>20?t>40?700:600:500,a.style.color=s}};const T=(r,e)=>{const n=u.canvas.getBoundingClientRect();if(r==null){u.exports.handleMouse(-1,-1,5);return}const i=(r.clientX-n.left)/n.width,t=(r.clientY-n.top)/n.height;i>=0&&i<=1&&t>=0&&t<=1?u.exports.handleMouse(i,t,e):u.exports.handleMouse(-1,-1,e)};window.addEventListener("blur",()=>{y=1/0,T(null,0)});document.addEventListener("pointermove",r=>{T(r,0)});document.addEventListener("pointerdown",r=>{const e=r.target;if(!e||document.getElementById("debugContainer").contains(e))return;const n=r.button===2?3:1;T(r,n)});document.addEventListener("pointerup",r=>{const e=r.button===2?4:2;T(r,e)});u.canvas.style.touchAction="none";document.addEventListener("contextmenu",r=>r.preventDefault());if(u.isDebug){u.exports.debugBuildUiMetadata();const r=u.readStr(),e=JSON.parse(r),n=document.getElementById("debugContainer");n.style.display="none",document.addEventListener("keydown",function(i){i.code==="KeyM"&&(n.style.display==="none"?n.removeAttribute("style"):n.style.display="none")}),e.buttons.forEach(i=>{const t=document.createElement("button");t.textContent=i.name,t.onclick=()=>u.exports.clickDebugUiButton(i.id),n.appendChild(t)}),e.sliders.forEach(i=>{const t=document.createElement("div");t.style.display="flex",t.style.flexDirection="column";const s=document.createElement("label");s.textContent=`${i.name}: ${i.val.toFixed(2)}`,s.style.fontSize="12px";const a=document.createElement("input");a.type="range",a.min=i.min,a.max=i.max,a.step=((i.max-i.min)/1e3).toString(),a.value=i.val,a.oninput=l=>{const c=parseFloat(l.target.value);s.textContent=`${i.name}: ${c.toFixed(2)}`,u.exports.changeDebugUiSlider(i.id,c)},t.appendChild(s),t.appendChild(a),n.appendChild(t)}),document.body.appendChild(n)}setTimeout(function(){u.renderLoop(0)},17);
