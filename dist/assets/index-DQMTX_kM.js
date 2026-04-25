(function(){const t=document.createElement("link").relList;if(t&&t.supports&&t.supports("modulepreload"))return;for(const e of document.querySelectorAll('link[rel="modulepreload"]'))r(e);new MutationObserver(e=>{for(const s of e)if(s.type==="childList")for(const o of s.addedNodes)o.tagName==="LINK"&&o.rel==="modulepreload"&&r(o)}).observe(document,{childList:!0,subtree:!0});function n(e){const s={};return e.integrity&&(s.integrity=e.integrity),e.referrerPolicy&&(s.referrerPolicy=e.referrerPolicy),e.crossOrigin==="use-credentials"?s.credentials="include":e.crossOrigin==="anonymous"?s.credentials="omit":s.credentials="same-origin",s}function r(e){if(e.ep)return;e.ep=!0;const s=n(e);fetch(e.href,s)}})();const a={zoom:131072,drop:262144,minus:32768,plus:65536,up:2048,left:4096,down:8192,right:16384,k0:1,k1:2,k2:4,k3:8,k4:16,k5:32,k6:64,k7:128,k8:256,k9:512},R={player_pos:0,last_player_pos:16,player_chunk:32,player_velocity:48,camera_pos:64,last_camera_pos:80,camera_scale:96,camera_scale_change:104,depth:112,player_quadrant:120,frame:124,keys_pressed_mask:128,keys_held_mask:132,seed:144,seed2:208},C="abcdefghijklmnopqrstuvwxyz",y=26n;function V(i=100){if(i<=0)return"";const t=new Uint8Array(72);crypto.getRandomValues(t);let n=0n;const r=new DataView(t.buffer);for(let o=0;o<t.length;o+=8)n=n<<64n|r.getBigUint64(o);let e="",s=n%y**BigInt(i);for(;s>=0n&&(e+=C[Number(s%y)],s=s/y-1n,!(s<0n)););return e}function q(i){let t=0n;for(let n=0;n<i.length;n++){const r=BigInt(i.charCodeAt(n)-97);t=t*y+(r+1n)}return t}async function H(i,t){const n=q(i),r=new DataView(new ArrayBuffer(64));for(let l=0;l<8;l++)r.setBigUint64(l*8,n>>BigInt((7-l)*64)&0xffffffffffffffffn);let e=new Uint8Array(r.buffer,0,32),s=new Uint8Array(r.buffer,32,32);const o=await Promise.all([0,1,2,3].map(l=>crypto.subtle.importKey("raw",new Uint8Array([l]),{name:"HMAC",hash:"SHA-256"},!1,["sign"])));for(const l of o){const _=new Uint8Array(await crypto.subtle.sign("HMAC",l,s)),p=new Uint8Array(32);for(let f=0;f<32;f++)p[f]=e[f]^_[f];e=s,s=p}const u=new Uint8Array(64);return u.set(e,0),u.set(s,32),t.set(new BigUint64Array(u.buffer)),t}const k={Minus:a.minus,Equal:a.plus,KeyZ:a.zoom,KeyQ:a.drop,Space:a.up,ArrowUp:a.up,KeyW:a.up,ArrowLeft:a.left,KeyA:a.left,ArrowDown:a.down,KeyS:a.down,ArrowRight:a.right,KeyD:a.right,Digit0:a.k0,Digit1:a.k1,Digit2:a.k2,Digit3:a.k3,Digit4:a.k4,Digit5:a.k5,Digit6:a.k6,Digit7:a.k7,Digit8:a.k8,Digit9:a.k9};function W(){let i={};const t={heldMask:0,keysHeld:0,keysPressed:0,currentlyHeld:0,horizontalPriority:0,verticalPriority:0,plusMinusPriority:0};function n(){i={},t.horizontalPriority=0,t.verticalPriority=0,t.plusMinusPriority=0,t.currentlyHeld=0,t.heldMask=0,t.keysPressed=0}return window.addEventListener("keydown",r=>{if(r.repeat)return;if(r.ctrlKey||r.metaKey){n();return}const e=k[r.code];e&&(e<=512&&(t.heldMask=t.heldMask&4294966272),t.heldMask|=e,i[e]=(i[e]||0)+1,e&(a.left|a.right)&&(t.horizontalPriority=e),e&(a.up|a.down)&&(t.verticalPriority=e),e&(a.plus|a.minus)&&(t.plusMinusPriority=e))}),window.addEventListener("keyup",r=>{const e=k[r.code];e&&(i[e]=Math.max(0,(i[e]||0)-1),i[e]===0&&(t.heldMask&=~e,e===t.horizontalPriority&&(t.horizontalPriority=t.heldMask&a.left||t.heldMask&a.right||0),e===t.verticalPriority&&(t.verticalPriority=t.heldMask&a.up||t.heldMask&a.down||0),e===t.plusMinusPriority&&(t.plusMinusPriority=t.heldMask&a.plus||t.heldMask&a.minus||0)))}),window.addEventListener("blur",n),document.addEventListener("visibilitychange",n),window.addEventListener("contextmenu",n),t}function K(i){const t=a.up|a.down|a.left|a.right;let n=i.heldMask&~t;n|=i.horizontalPriority,n|=i.verticalPriority,n|=i.plusMinusPriority,i.keysPressed=n&~i.keysHeld,i.currentlyHeld=n,i.keysHeld=n}const X=""+new URL("main-DQTKC8er.wasm",import.meta.url).href,Z=`/*
 * Main shader for Depthwell. ADD ?raw FOR DEBUGGING SHADER TO THE END OF engineMaker.ts's \`SHADER_SOURCE\` VARIABLE TO NOT COMPRESS.
 */

// These are sprite sheet constants. Sprites are saved as a .png in a sprite sheet 160 pixels wide, and each asset is 16x16.
// See zig/state/world.zig's Sprite definitions for sprite type list.
// These const values values with /* VARIABLE_NAME */ are dynamically patched in from TypeScript, so do not set them here.
const TILES_PER_ROW: f32 = /* TILES_PER_ROW */ 1 /* TILES_PER_ROW */;
const TILES_PER_COLUMN: f32 = /* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */;
const STONE_START: u32 = /* STONE_START */ 1 /* STONE_START */;
const ORE_START: u32 = /* ORE_START */ 1 /* ORE_START */;
const GEM_START: u32 = /* GEM_START */ 1 /* GEM_START */;
const GEM_MASK_START: u32 = /* GEM_MASK_START */ 1 /* GEM_MASK_START */;
const DECOR_START: u32 = /* DECOR_START */ 1 /* DECOR_START */;

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
    _extra_padding: array<vec4u, 13>, // Pad to 256 bytes for dynamic offsets
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

    @location(3) @interpolate(flat) sprite_id: u32,
    @location(4) @interpolate(flat) edge_flags: u32,
    @location(5) @interpolate(flat) light: f32,
    @location(6) @interpolate(flat) hp: u32,
    @location(7) @interpolate(flat) seeds: vec3u, // seed1: these 28 bits are used as efficently as possible, seed2: murmurmix32'ed from seed, seed3: murmurmix32'ed from seed2
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
    out.hp = extractBits(data.word1, 28u, 4u);
    let s1 = data.word1; // hp takes up the top 4 bits perfectly
    let s2 = murmurmix32(s1);
    let s3 = murmurmix32(s2);
    out.seeds = vec3u(s1, s2, s3);
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

    if (instance_index == total_tiles) {
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
    if (tile.sprite_id == 0u && scene.wireframe_opacity == 0.0) {
        out.position = vec4f(2.0, 2.0, 2.0, 1.0); // ideal outcode
        return out;
    }

    let tile_coords = vec2u(instance_index % scene.map_size.x, instance_index / scene.map_size.x);
    var id = tile.sprite_id;

    if (id == STONE_START) {
        // 2x2 grid stone pattern
        let offset = (tile_coords.y % 2u) * 2u + (tile_coords.x % 2u);
        id += offset;
    } else if (id == 2) { // edge stone (too lazy to make constant, like player)
        let offset = (tile_coords.x % 2u) ^ (tile_coords.y % 2u); // checkerboard
        id += offset;
    } else if (id == (DECOR_START + 2u)) {
        // seed-based variation for Mushrooms
        let random_mod = extractBits(tile.seeds[0], 16u, 2u);
        if (random_mod == 0u) {
            id++;
        }
    }

    let world_pixel_pos = (vec2f(tile_coords) + local_pos) * TILE_SIZE;
    let screen_pos = ((world_pixel_pos - scene.camera) * scene.zoom) + (scene.viewport_size * 0.5);

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

    // apply to screen_pos.y before converting to normalized device coordinates
    // subtract from Y because in screen space, lower values are "higher" up
    let adjusted_screen_pos = screen_pos - vec2f(0.0, vertical_offset);
    let ndc = (adjusted_screen_pos / scene.viewport_size) * vec2f(2.0, -2.0) + vec2f(-1.0, 1.0);

    // Calculate which sprite in the atlas to sample
    let origin = vec2f(f32(id % TILES_PER_ROW_U), f32(id / TILES_PER_ROW_U)) * vec2f(SPRITE_W, SPRITE_H);

    out.position = vec4f(ndc, 0.0, 1.0);
    out.sprite_uv_origin = origin;
    out.sprite_id = id;
    out.hp = tile.hp;
    out.seeds = tile.seeds;
    out.edge_flags = tile.edge_flags;
    out.tile_coords = tile_coords;
    out.light = tile.light;
    out.local_uv = local_pos;
    return out;
}

@fragment
fn fs_main(in: TileOutput) -> @location(0) vec4f {
    var erode_mask: u32 = 1u;
    let safe_local_uv = clamp(in.local_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));

    if (in.edge_flags != 0xFFu) {
        erode_mask = erosion(in.local_uv, in.edge_flags, in.seeds[1], in.seeds[2]);
        if (scene.wireframe_opacity == 0.0 && erode_mask == 0u) {
            discard; // discard early
        }
    }

    if (in.sprite_id >= 256u && in.sprite_id <= 512u) {
        // Heatmap logic!
        let color = (f32(in.sprite_id) - 256.0) / 256.0;
        var lch = vec3f(0.2 + color * 0.8, 0.2, 1.0); // lightness, chroma, hue
        let lab = oklch_to_oklab(lch);
        let final_rgb = oklab_to_linear_srgb(lab);
        return vec4f(final_rgb, 1.0);
    }

    let seed = in.seeds[0];
    var final_uv = in.sprite_uv_origin + safe_local_uv * vec2f(SPRITE_W, SPRITE_H);
    if (in.sprite_id >= GEM_START && in.sprite_id < GEM_MASK_START) {
        let shift_bits = extractBits(seed, 18u, 8u); // shift the gem sprite around 0-15 pixels using bits 18-26
        let shift = vec2f(vec2u(shift_bits & 0xFu, shift_bits >> 4u)) / 16.0;
        let wrapped_local = fract(in.local_uv + shift); // there are 1 pixel boundaries so fract() being imprecise is okay
        let safe_wrapped = clamp(wrapped_local, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
        final_uv = in.sprite_uv_origin + safe_wrapped * vec2f(SPRITE_W, SPRITE_H);
    }

    let hp_id = HP_SAMPLE_START + in.hp;
    let hp_grid = vec2f(f32(hp_id % TILES_PER_ROW_U), f32(hp_id / TILES_PER_ROW_U));
    let hp_uv = (hp_grid + safe_local_uv) * vec2f(SPRITE_W, SPRITE_H);

    // Sample the primary color (the actual original sprite, gem or not)
    var hp_darkness_mult = textureSampleLevel(sprite_atlas, pixel_sampler, hp_uv, 0.0).r;
    var tex_color = textureSampleLevel(sprite_atlas, pixel_sampler, final_uv, 0.0);
    tex_color = vec4f(tex_color.rgb * hp_darkness_mult, tex_color.a);

    // ore sampling pixel logic
    if (in.sprite_id >= GEM_START && in.sprite_id < GEM_MASK_START) {
        let mask_variation = extractBits(seed, 15u, 3u); // 8 masks
        let mask_id = GEM_MASK_START + mask_variation;

        let flip = vec2f(vec2u(extractBits(seed, 25u, 1u), extractBits(seed, 26u, 1u)));
        let flipped_uv = mix(in.local_uv, 1.0 - in.local_uv, flip);
        // Use 2x2 grid logic for the background stone's ID
        let bg_id = STONE_START + (in.tile_coords.y % 2u) * 2u + (in.tile_coords.x % 2u);

        // Calculate UVs for the background stone
        let bg_grid = vec2f(f32(bg_id % TILES_PER_ROW_U), f32(bg_id / TILES_PER_ROW_U));
        let stone_uv = (bg_grid + safe_local_uv) * vec2f(SPRITE_W, SPRITE_H);

        // Calculate UVs for the mask (using the UNSHIFTED uv)
        let safe_flipped_uv = clamp(flipped_uv, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));
        let mask_grid = vec2f(f32(mask_id % TILES_PER_ROW_U), f32(mask_id / TILES_PER_ROW_U));
        let mask_uv = (mask_grid + safe_flipped_uv) * vec2f(SPRITE_W, SPRITE_H);

        let tex_stone = textureSampleLevel(sprite_atlas, pixel_sampler, stone_uv, 0.0);
        let tex_mask = textureSampleLevel(sprite_atlas, pixel_sampler, mask_uv, 0.0);

        let abs_dist = abs(in.local_uv - 0.5);
        let u_dist = max(abs_dist.x, abs_dist.y);

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
            let mods = in.tile_coords & vec2u(15u);

            if (in.sprite_id == 1u) {
                wire_color = vec4f(1.0, 0.5, 0.0, 1.0);
            } else {
                // Is this pixel on the edge of a CHUNK?
                let is_chunk_edge = any((mods == vec2u(0u)) & (in.local_uv < vec2f(inv_tile_scale))) ||
                                    any((mods == vec2u(15u)) & (in.local_uv > vec2f(1.0 - inv_tile_scale)));

                if (is_chunk_edge) {
                    wire_color = vec4f(1.0, 1.0, 0.0, min(1.0, scene.wireframe_opacity * 2.5));
                } else {
                    // neat-lookin' fancy wireframe coloring
                    let rg = vec2f(mods) * 0.0625;
                    let b = 0.5 + f32(mods.x ^ mods.y) * 0.03125;
                    wire_color = vec4f(rg.x, rg.y, b, scene.wireframe_opacity);
                }
            }
        }
    }

    // convert to oklab and nudge values with seed
    var lab = linear_srgb_to_oklab(tex_color.rgb);
    var lch = oklab_to_oklch(lab);

    // we use 9 out of the 28 seed bits here
    let lab_nudge_bits = vec3u(
        extractBits(seed, 0u, 3u), // shift lightness (0-1)
        extractBits(seed, 3u, 3u), // shift chroma, which acts similar to saturation (0-1)
        extractBits(seed, 6u, 3u) // shift hue (in RADIANS, red isn't exactly 0)
    );
    let nudges = vec3f(lab_nudge_bits) / 7.0;

    // Apply light and nudges in a single MAD operation where possible
    lch *= vec3f(in.light, 1.0 + nudges.y * 0.2, 1.0) +
        vec3f(nudges.x * 0.02, 0.0, nudges.z * 0.1);

    var final_rgb = vec3f(0.0);
    if (in.edge_flags != 0xFFu) {
        // add the edge darkening and base light value, with the function using bits 10-16
        let darkening = calculate_edge_darkening(in.local_uv, in.edge_flags, seed);
        lch.x *= (1.0 - darkening);

        if (erode_mask == 2u) {
            lch *= vec3f(0.6 + f32(lab_nudge_bits.x) * 0.01, 1.3 + f32(lab_nudge_bits.y) * 0.04, 1.0);
        }
    }

    lab = oklch_to_oklab(lch);
    final_rgb = oklab_to_linear_srgb(lab);
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
    let edge_width = 0.40 + f32(extractBits(seed, 9u, 3u)) / 32.0;
    let edge_strength = 0.25 + f32(extractBits(seed, 12u, 3u)) / 64.0;

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
    BACKGROUND
    ----
*/

// FBM background logic
struct BackgroundOutput {
    @builtin(position) position: vec4f,
    @location(0) world_uv: vec2f,
    @location(1) time: f32,
    @location(2) time2: f32,
};

// Main vertex shader for rendering the fancy background.
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
    // Vectorized construction of coordinate vectors
    let ix = i.x + vec4u(0u, 1u, 0u, 1u);
    let iy = i.y + vec4u(0u, 0u, 1u, 1u);

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
    // if (entity.id == 0u) {
    //     out.position = vec4f(2.0, 2.0, 2.0, 1.0); // ideal outcode
    // }

    let local_pos = vec2f((vec2u(50u, 44u) >> vec2u(vertex_index)) & vec2u(1u));
    let centered_pos = local_pos - 0.5;

    // Rotate sprite as needed
    let c = cos(entity.rotation);
    let s = sin(entity.rotation);
    let rotated_pos = vec2f(
        centered_pos.x * c - centered_pos.y * s,
        centered_pos.x * s + centered_pos.y * c
    );

    let pixel_pos = entity.position + (rotated_pos * entity.size);

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

    let tex_color =
        textureSampleLevel(sprite_atlas, pixel_sampler, final_uv, 0.0) *
        textureSampleLevel(sprite_atlas_mask, pixel_sampler, final_uv, 0.0);
    // Early discard if the pixel is fully transparent (maybe)
    // if (tex_color.a <= 0.0) { 
    //     discard; 
    // }
    var lab = linear_srgb_to_oklab(tex_color.rgb);
    var lch = oklab_to_oklch(lab);

    // Apply modifications from lcha (vec4f: L, C, H, A), see zig/render/entity.zig
    lch.x *= in.lcha.x; // mult light
    lch.y += in.lcha.y; // add chroma
    lch.z += in.lcha.z; // add hue

    lab = oklch_to_oklab(lch);
    let final_rgb = oklab_to_linear_srgb(lab);

    // apply alpha after being back to RGB!
    let final_a = tex_color.a * in.lcha.w;
    return vec4f(final_rgb, final_a);
}



/*
    ----
    OKLAB Conversions
    ----
*/
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
    let result = m2 * lms;
    return max(result, vec3f(0.0)); // prevent out of range values
}

fn oklab_to_oklch(lab: vec3f) -> vec3f {
    let chroma = length(lab.yz);
    let hue = select(atan2(lab.z, lab.y), 0.0, chroma < 0.0001); // prevent invalid numbers
    return vec3f(lab.x, chroma, hue);
}

fn oklch_to_oklab(lch: vec3f) -> vec3f {
    return vec3f(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z));
}`,Y=""+new URL("main-D42D3_rz.png",import.meta.url).href,j="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAKAAAABwCAMAAACuL4swAAAAAXNSR0IArs4c6QAAAi5QTFRF////f8rLUsC6WN20VM6oR6F9srKyW1tboaGhRkZG0tLS////eo+3XXeqZG6OSVl8OktaPGpql0vbdzq3fDmVaDl+XxBqgxB1ncj8f7DgZY29W3ShOWdxAAAAmtC5SpqCf6+bZp2HXYdxN2lXk7SBYaBsUolkJ3VVV35zRF1WtoVkl3BUbE0zUj0gQykYLR4Pm5eXdGpqUE5MLS0t8Lol9VYUnJychoSEbmtuTElHLK0cNIg2v76+pJ+ehICCcW1yT05NAAAAwLehqZ+WhIJ7d2VTVEtDMC8o8cCfzHg5iWBLWk5EWDw7NiUZ5NzWu5R1gltGb29vPC0tST0x2+XqrrK3fYmVSmt2OUhYLjM09fLL8OGAsZY3onQQa0UZMScR6q7ytGPgfkHsdi6+XyeXLBFqttL7Y5/gUHSbCnDPJDOcESlqufzSkvLQYOW8EMaBIJFjDF9P/OLl9aK654BuvkxDnDAkfRwXOQ2gIlOBSNRx3V5YAAAAAAAAGcE/KXEo7Tc38JOT4yNt9cPqcvG0L+R/LKQba7tr/6PBzjU12bXbt4q732HBLKQbK06VJ4nNeGTGnIvbiqH2ydT9kFK8Qr/oSUGCRXLjAAAAAAAAEl83HZc5HkxKO4+QWaOlWMCXisevLWOGI61tPdFGAAAAAAAAAAAA0EIz95Ag98ggd0IaqnxYjl03mlglVcj2Q8H0MLbnJavcLJ3LLImvVvXTQvXdMejoJdvbLb/MLqix60aoDwAAALp0Uk5TAP//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////NfB1eQAAAT5JREFUeJzt2bFyg0AMhGFVPjm8//tmfMbm7Ir1HgpJ/u224PRRwIghFjMR0Z6JnrndB7atZD9/breBbWwZ07sLbG91dgcIECBAgH8dGNfX86Z3Gzie2NePyd0HHrxuqRf8xA1sp+3Yz3TgxP1wz34mA6fuhzseexVov2YAAgQIEODJgep+pgLtfVDdz2SgvR+ef93yooI/uMFfAMx7Lo+hSq8A5lfPsqwCqRcA13m3kZeQ+/HAbd59otiLgSn3AmB7A2j9eOA4sX/mab0AuE3M9SlVegXwMTGf7zmhlwAjr+N8qdcAbxOH+UovAka+zBd6FfDjADx6gBuAbgC6AegGoBuAbgC6AegGoBuAbgC6AegGoBuAbgC6AegGoBuAbgC6AegGoBuAbgC6AegG4Pn/mAMECBAgQIAAAf5r4Dc/LqPlsE3EKgAAAABJRU5ErkJggg==";async function Q(i,t){const n=await navigator.gpu.requestAdapter({powerPreference:t&&t.highPerformance?"high-performance":"low-power"});if(!n)throw new DOMException("Couldn't request WebGPU adapter.","NotSupportedError");const r=await n.requestDevice();let e=null;if(r.addEventListener("uncapturederror",d=>{const m=d.error;if(e===null)if(globalThis.reportError)reportError(m);else throw m;else if(!e.destroyed){e.destroy("fatal WebGPU error",m);return}}),r.lost.then(d=>console.error(`WebGPU Device lost: ${d.message}`)),i===void 0){if(i=document.getElementsByTagName("canvas")[0],i===void 0)throw Error("No canvas element or ID string provided, and no canvas was not found in the HTML.")}else if(typeof i=="string"){const d=document.getElementById(i);if(!(d instanceof HTMLCanvasElement))throw Error(`Element with ID "${i}" is not a canvas element.`);i=d}const s=i.getContext("webgpu");if(!s)throw Error("Could not get WebGPU context from canvas.");const o=r.features.has("canvas-rgba16float-support")?"rgba16float":"bgra8unorm";s.configure({device:r,format:o,alphaMode:"opaque"});const u=await WebAssembly.instantiateStreaming(fetch(X),{env:{js_message:(d,m,b)=>{let h=new TextDecoder().decode(new Uint8Array(_.buffer,Number(d),Number(m)));h.charAt(0)!=="]"?h="["+(e.LOGGING_PREFIX||"")+h:h=h.slice(1),b===1?console.info("%c"+h,"font-weight: 600"):[console.log,console.info,console.warn,console.error][b](h)},js_write_text:(d,m,b)=>{const h=new Uint8Array(_.buffer,Number(m),Number(b)),F=new TextDecoder().decode(h),N=document.getElementById(`text${d+1}`);N.textContent=F},js_get_time:()=>performance.now(),js_handle_visible_chunks:d=>e.handleVisibleChunks(d),js_handle_visible_entities:()=>e.handleVisibleEntities()}}),l=u.instance.exports,_=l.memory,p=r.createShaderModule({label:"Main shader",code:Z.replace("/* TILES_PER_ROW */ 1 /* TILES_PER_ROW */",""+l.get_tiles_per_row()).replace("/* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */",""+l.get_tiles_per_column()).replace("/* STONE_START */ 1 /* STONE_START */",""+l.get_stone_start()).replace("/* ORE_START */ 1 /* ORE_START */",""+l.get_ore_start()).replace("/* GEM_START */ 1 /* GEM_START */",""+l.get_gem_start()).replace("/* GEM_MASK_START */ 1 /* GEM_MASK_START */",""+l.get_gem_mask_start()).replace("/* DECOR_START */ 1 /* DECOR_START */",""+l.get_decor_start())}),f=r.createBindGroupLayout({label:"Main bind group layout",entries:[{binding:0,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"uniform",hasDynamicOffset:!0}},{binding:1,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"read-only-storage"}},{binding:2,visibility:GPUShaderStage.FRAGMENT,texture:{}},{binding:3,visibility:GPUShaderStage.FRAGMENT,texture:{}},{binding:4,visibility:GPUShaderStage.FRAGMENT,sampler:{}},{binding:5,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"read-only-storage"}}]}),g=r.createPipelineLayout({label:"Shared Pipeline Layout",bindGroupLayouts:[f]}),I=r.createRenderPipeline({label:"Tilemap pipeline",layout:g,vertex:{module:p,entryPoint:"vs_tile"},fragment:{module:p,entryPoint:"fs_main",targets:[{format:o,blend:{color:{srcFactor:"src-alpha",dstFactor:"one-minus-src-alpha"},alpha:{srcFactor:"one",dstFactor:"one-minus-src-alpha"}}}]},primitive:{topology:"triangle-list",cullMode:"none"}}),U=r.createRenderPipeline({label:"Background pipeline",layout:g,vertex:{module:p,entryPoint:"vs_background"},fragment:{module:p,entryPoint:"fs_background",targets:[{format:o}]},primitive:{topology:"triangle-list"}}),O=r.createRenderPipeline({label:"Entity pipeline",layout:g,vertex:{module:p,entryPoint:"vs_entity"},fragment:{module:p,entryPoint:"fs_entity",targets:[{format:o,blend:{color:{srcFactor:"src-alpha",dstFactor:"one-minus-src-alpha"},alpha:{srcFactor:"one",dstFactor:"one-minus-src-alpha"}}}]},primitive:{topology:"triangle-list"}});e=new T(i,n,r,s,u,I,U,O),e.exports.setup(),await e.setSeed(V(100)),e.startDelta=Number(l.mix_seed(60n)%120000n),e.exports.init();const G=new ResizeObserver(e.onResize);e.resizeObserver=G,e.updateCanvasStyle();try{e.resizeObserver.observe(i,{box:"device-pixel-content-box"})}catch{console.log("ResizeObserver property device-pixel-content-box not supported, falling back to content-box."),e.resizeObserver.observe(i,{box:"content-box"})}e.onResize([{contentRect:{width:i.clientWidth,height:i.clientHeight}}]);const M=await T.loadTexture(r,Y),D=await T.loadTexture(r,j),z=r.createSampler({magFilter:"nearest",minFilter:"nearest",addressModeU:"clamp-to-edge",addressModeV:"clamp-to-edge"});return e.atlasTextureView=M.createView(),e.atlasTextureMaskView=D.createView(),e.pixelSampler=z,e.uniformBuffer=r.createBuffer({label:"SceneUniforms",size:256*E,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST}),e.entityBuffer=e.device.createBuffer({label:"Entities",size:4800,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),e}var L=(i=>(i[i.Uint8=8]="Uint8",i[i.Uint16=16]="Uint16",i[i.Uint32=32]="Uint32",i[i.Uint64=64]="Uint64",i[i.Int8=-8]="Int8",i[i.Int16=-16]="Int16",i[i.Int32=-32]="Int32",i[i.Int64=-64]="Int64",i[i.Uint8Clamped=-80]="Uint8Clamped",i[i.Float32=-320]="Float32",i[i.Float64=-640]="Float64",i))(L||{});globalThis.WasmTypeCode=L;const B={8:Uint8Array,16:Uint16Array,32:Uint32Array,64:BigUint64Array,[-8]:Int8Array,[-16]:Int16Array,[-32]:Int32Array,[-64]:BigInt64Array,[-80]:Uint8ClampedArray,[-320]:Float32Array,[-640]:Float64Array},E=4;class T{engineModule;exports;memory;LAYOUT_PTR;GAME_STATE_PTR;canvas;adapter;device;context;bindGroups=Array(E);uniformBuffer;tileBuffers=Array(E);entityBuffer;tileBufferDirty=!1;atlasTextureView;atlasTextureMaskView;pixelSampler;tilePipeline;bgPipeline;entityPipeline;renderPass=null;currentEncoder=null;currentTextureView=null;renderCallId=0;sceneDataBuffer=new ArrayBuffer(256);sceneDataF32=new Float32Array(this.sceneDataBuffer);sceneDataU32=new Uint32Array(this.sceneDataBuffer);inputState;resizeObserver;forceAspectRatio=!0;previousForceAspectRatio=null;tileMapWidth;tileMapHeight;last_upload_visible_chunks_time=0;prepare_visible_data_time=0;isVisibleDataNew=!0;wireframeOpacity=0;startTime=performance.now();startDelta;seed="";destroyed=!1;destroyedError=null;encoder=new TextEncoder;decoder=new TextDecoder;LOGGING_PREFIX="";constructor(t,n,r,e,s,o,u,l){this.canvas=t,this.adapter=n,this.device=r,this.context=e,this.engineModule=s,this.tilePipeline=o,this.bgPipeline=u,this.entityPipeline=l,this.exports=s.instance.exports,this.memory=s.instance.exports.memory,this.LAYOUT_PTR=Number(this.exports.get_memory_layout_ptr()),this.GAME_STATE_PTR=Number(this.getScratchView()[3]),this.inputState=W()}static async create(t,n){return await Q(t,n)}destroy(t="unknown reason",n=null){this.resizeObserver.disconnect(),this.destroyed=t,this.destroyedError=n}static async loadTexture(t,n){const e=await(await fetch(n)).blob(),s=await createImageBitmap(e),o=t.createTexture({label:`Texture from ${n}`,size:[s.width,s.height],format:t.features.has("canvas-rgba16float-support")?"rgba16float":"bgra8unorm",usage:GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT});return t.queue.copyExternalImageToTexture({source:s},{texture:o},[s.width,s.height]),o}uploadVisibleChunks(t=1){const n=performance.now();this.exports.prepare_visible_data(t,n-this.last_upload_visible_chunks_time,this.canvas.width,this.canvas.height),this.last_upload_visible_chunks_time=n,this.prepare_visible_data_time=performance.now()-n}handleVisibleChunks(t){if(!this.currentEncoder||!this.currentTextureView||!this.renderPass)return;const n=this.getScratchPtr();if(this.getScratchLen()===0)return;const e=Number(this.getScratchProperty(0)),s=Number(this.getScratchProperty(1)),o=e*s*2;this.tileMapWidth=e,this.tileMapHeight=s;const u=new Uint32Array(this.memory.buffer,n,o);this.recreateBufferAndBindGroup(o*4),this.renderPass.setPipeline(this.tilePipeline),this.renderPass.setBindGroup(0,this.bindGroups[this.renderCallId],[this.renderCallId*256]),this.renderPass.setViewport(0,0,this.canvas.width,this.canvas.height,0,1),this.setSceneData(t,e,s),this.device.queue.writeBuffer(this.tileBuffers[this.renderCallId],0,u);const l=e*s+1;this.renderPass.draw(6,l),this.renderCallId++}handleVisibleEntities(){const t=this.getScratchPtr(),n=this.getScratchLen();if(n===0||!this.renderPass)return;let r=!1;(!this.entityBuffer||this.entityBuffer.size<n)&&(this.entityBuffer=this.device.createBuffer({label:"Entities",size:Math.max(n,1024),usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),r=!0);const e=new Uint8Array(this.memory.buffer,t,n);this.device.queue.writeBuffer(this.entityBuffer,0,e),r&&this.recreateBufferAndBindGroup(this.tileBuffers[0]?.size||256),this.renderPass.setPipeline(this.entityPipeline),this.renderPass.setBindGroup(0,this.bindGroups[0],[0]),this.renderPass.draw(6,n/48)}setSceneData(t,n,r){const e=this.getScratchProperty(2,-640),s=this.getScratchProperty(3,-640),o=this.getScratchProperty(4,-640),u=this.getScratchProperty(5,-640),l=this.getScratchProperty(6,-640);this.sceneDataF32[0]=e,this.sceneDataF32[1]=s,this.sceneDataF32[2]=this.canvas.width,this.sceneDataF32[3]=this.canvas.height;const _=6e4,f=(performance.now()-this.startTime+this.startDelta)%(_*2);let g;f<_?g=f/1e3:g=(_-(f-_))/1e3,this.sceneDataF32[4]=g,this.sceneDataF32[5]=o,this.sceneDataF32[6]=o<.25?0:this.wireframeOpacity,this.sceneDataF32[7]=t,this.sceneDataF32[8]=u,this.sceneDataF32[9]=l,this.sceneDataU32[10]=n,this.sceneDataU32[11]=r,this.device.queue.writeBuffer(this.uniformBuffer,this.renderCallId*256,this.sceneDataF32)}recreateBufferAndBindGroup(t){const n=this.renderCallId;(!this.tileBuffers[n]||this.tileBuffers[n].size<t)&&(this.tileBuffers[n]=this.device.createBuffer({label:`Tile grid slot ${n}`,size:t,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),this.bindGroups[n]=this.device.createBindGroup({label:`Bind group slot ${n}`,layout:this.tilePipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:this.uniformBuffer,offset:0,size:256}},{binding:1,resource:{buffer:this.tileBuffers[n]}},{binding:2,resource:this.atlasTextureView},{binding:3,resource:this.atlasTextureMaskView},{binding:4,resource:this.pixelSampler},{binding:5,resource:{buffer:this.entityBuffer}}]}))}getWASMMemoryMB(){return this.memory.buffer.byteLength/1024/1024}getGameView(t,n=0,r){return new B[t](this.memory.buffer,this.GAME_STATE_PTR+n,r)}getRawView(t,n,r){return new B[t](this.memory.buffer,n,r)}_tempScratchViewU64=null;_tempScratchViewF64=null;getScratchView(){return(this._tempScratchViewU64===null||this._tempScratchViewU64.buffer!==this.memory.buffer)&&(this._tempScratchViewU64=new BigUint64Array(this.memory.buffer,this.LAYOUT_PTR,24)),this._tempScratchViewU64}getScratchPtr(){return Number(this.getScratchView()[0])}getScratchLen(){return Number(this.getScratchView()[1])}setScratchLen(t){this.getScratchView()[1]=BigInt(t)}getScratchCapacity(){return Number(this.getScratchView()[2])}getScratchProperty(t,n=64){(this._tempScratchViewU64===null||this._tempScratchViewU64.buffer!==this.memory.buffer)&&(this._tempScratchViewU64=new BigUint64Array(this.memory.buffer,this.LAYOUT_PTR,24));let r=this._tempScratchViewU64;return n==-640&&((this._tempScratchViewF64===null||this._tempScratchViewF64.buffer!==this.memory.buffer)&&(this._tempScratchViewF64=new Float64Array(r.buffer,r.byteOffset,r.length)),r=this._tempScratchViewF64),Number(r[t+4])}readStr(t=this.getScratchPtr(),n=this.getScratchLen()){const r=new Uint8Array(this.memory.buffer,t,n);return this.decoder.decode(r)}writeStr(t,n=!0){const r=t.length;if(r===0)return null;n&&this.setScratchLen(0);const e=this.exports.scratch_alloc(r);if(e===0n)return null;const s=new Uint8Array(this.memory.buffer,Number(e),r);if(this.encoder.encodeInto(t,s).read<r)throw new RangeError("String truncated with non-ASCII characters detected.");return Number(e)}async setSeed(t){this.seed=t,await H(t,this.getGameView(64,R.seed,8))}updateCanvasStyle(){this.forceAspectRatio!==this.previousForceAspectRatio&&(this.previousForceAspectRatio=this.forceAspectRatio,this.forceAspectRatio?(this.canvas.style.maxWidth=`calc(100vh*${16/9})`,this.canvas.style.maxHeight=`calc(100vw*${9/16})`):(this.canvas.style.maxWidth="none",this.canvas.style.maxHeight="none"))}onResize=t=>{const n=t[0];let r,e;if(n.devicePixelContentBoxSize)r=n.devicePixelContentBoxSize[0].inlineSize,e=n.devicePixelContentBoxSize[0].blockSize;else if(n.contentBoxSize){const s=n.contentBoxSize[0].inlineSize,o=n.contentBoxSize[0].blockSize;r=Math.round(s*devicePixelRatio),e=Math.round(o*devicePixelRatio)}else{const s=n.contentRect.width,o=n.contentRect.height;r=Math.round(s*devicePixelRatio),e=Math.round(o*devicePixelRatio)}(this.canvas.width!==r||this.canvas.height!==e)&&(this.canvas.width=r,this.canvas.height=e)};renderFrame(t,n){if(this.renderCallId=0,this.destroyed!==!1)return;this.updateCanvasStyle(),this.currentEncoder=this.device.createCommandEncoder(),this.currentTextureView=this.context.getCurrentTexture().createView();const r=this.currentEncoder.beginRenderPass({colorAttachments:[{view:this.currentTextureView,loadOp:"clear",clearValue:{r:0,g:0,b:0,a:1},storeOp:"store"}]});this.renderPass=r,this.recreateBufferAndBindGroup(256*E),this.sceneDataF32[7]=1,this.device.queue.writeBuffer(this.uniformBuffer,this.renderCallId*256,this.sceneDataF32),this.renderPass.setPipeline(this.bgPipeline),this.renderPass.setBindGroup(0,this.bindGroups[this.renderCallId],[this.renderCallId++*256]),this.renderPass.draw(3),this.uploadVisibleChunks(t),this.renderPass.end(),this.device.queue.submit([this.currentEncoder.finish()]),this.currentEncoder=null,this.currentTextureView=null}tick(t,n){const r=this.getGameView(32,R.keys_pressed_mask,2);K(this.inputState),r[0]=this.inputState.keysPressed,r[1]=this.inputState.keysHeld,this.exports.tick(t,n)}}location.protocol==="file:"&&alert("This game cannot run from a local file:// context; use an online version or test from localhost instead.");isSecureContext||alert("This game cannot run in a non-secure context.");navigator.gpu||alert("WebGPU is not supported by your browser; try playing this on an alternate or more modern browser.");const $=await navigator.gpu.requestAdapter();$||alert("WebGPU is supported, but no compatible GPU was found.");globalThis.Zig={KeyBits:a,game_state_offsets:R};console.log("Zig code is in debug mode. Use engine.exports to see its functions, variables, and memory, such as engine.exports.test_logs."),document.body.innerHTML+=`
    <div id="textTop">
        <div id="text1"></div>
        <div id="text2"></div>
    </div>
    <div id="textBottom">
        <div id="text3"></div>
        <div id="text4"></div>
    </div>
    <div id="logicText"></div>
    <div id="renderText"></div>
    <div id="debugContainer"></div>`;document.addEventListener("wheel",function(i){i.ctrlKey},{passive:!1});let c=await T.create();c.getTimeoutLength=function(){return++J%3==2?16:17};c.getFrameRate=function(){return 60};c.baseSpeed=1;let v=performance.now(),x=0,J=0;globalThis.engine=c;console.log("Engine initialized successfully:",c),console.log("Exported functions and memory:",c.exports);window.addEventListener("blur",()=>v=1/0);const S=Array(60).fill(0),w=Array(60).fill(0),A=Array(60).fill(0);c.isDebug=!!c.exports.isDebug();c.renderLoop=function(i){let t=performance.now(),n=v===1/0?0:t-v,r=Math.min(n*c.getFrameRate()/1e3,c.getFrameRate());c.logicLoop(Math.max(Math.floor(x+r),1)),x=(x+r)%1;{w.shift(),w.push(n),A.shift(),A.push(c.prepare_visible_data_time);const s=Math.max.apply(null,w),o=Math.max.apply(null,A);let u="#cccccc";s>55?u="#e83769":s>30?u="#f39c19":s>20&&(u="#f7ce1a");const l=document.getElementById("renderText");l.textContent=`Time since last render/prepare_visible_data time: ${n.toFixed(1)}ms, ${c.prepare_visible_data_time.toFixed(1)}ms
Worst (past 60 frames): ${s.toFixed(1)}ms, ${o.toFixed(1)}ms`,l.style.fontWeight=s>40?s>55?700:600:500,l.style.color=u}let e=Math.min(x-1,0);c.renderFrame(e,v),requestAnimationFrame(c.renderLoop)};c.logicLoop=function(i){const t=performance.now();c.tick(60/c.getFrameRate()*c.baseSpeed,i),v=performance.now();let n=v-t;{S.shift(),S.push(n);const r=Math.max.apply(null,S);let e="#cccccc";r>30?e="#e83769":r>15?e="#f39c19":r>10&&(e="#f7ce1a");const s=document.getElementById("logicText");s.textContent=`Logic diff: ${n.toFixed(1)}ms for ${i} tick${i==1?"":"s"}
Worst (past 60 frames): ${r.toFixed(1)}ms
`,s.style.fontWeight=r>20?r>40?700:600:500,s.style.color=e}};const P=(i,t)=>{const n=c.canvas.getBoundingClientRect(),r=(i.clientX-n.left)/n.width,e=(i.clientY-n.top)/n.height;r>=0&&r<=1&&e>=0&&e<=1&&c.exports.handle_mouse(r,e,t)};document.addEventListener("pointermove",i=>{i.buttons>0&&P(i,0)});document.addEventListener("pointerdown",i=>{if(!i.target||i.target.id==="debugContainer")return;const t=i.button===2?3:1;P(i,t)});document.addEventListener("pointerup",i=>{const t=i.button===2?4:2;P(i,t)});c.canvas.style.touchAction="none";document.addEventListener("contextmenu",i=>i.preventDefault());{const i=c.exports;i.debug_build_ui_metadata();const t=c.readStr(),n=JSON.parse(t),r=document.getElementById("debugContainer");n.buttons.forEach(e=>{const s=document.createElement("button");s.textContent=e.name,s.onclick=()=>i.debug_ui_button_click(e.id),r.appendChild(s)}),n.sliders.forEach(e=>{const s=document.createElement("div");s.style.display="flex",s.style.flexDirection="column";const o=document.createElement("label");o.textContent=`${e.name}: ${e.val.toFixed(2)}`,o.style.fontSize="12px";const u=document.createElement("input");u.type="range",u.min=e.min,u.max=e.max,u.step=((e.max-e.min)/1e3).toString(),u.value=e.val,u.oninput=l=>{const _=parseFloat(l.target.value);o.textContent=`${e.name}: ${_.toFixed(2)}`,i.debug_ui_slider_change(e.id,_)},s.appendChild(o),s.appendChild(u),r.appendChild(s)}),document.body.appendChild(r)}setTimeout(function(){c.renderLoop(0)},17);
