(function(){const t=document.createElement("link").relList;if(t&&t.supports&&t.supports("modulepreload"))return;for(const e of document.querySelectorAll('link[rel="modulepreload"]'))r(e);new MutationObserver(e=>{for(const s of e)if(s.type==="childList")for(const a of s.addedNodes)a.tagName==="LINK"&&a.rel==="modulepreload"&&r(a)}).observe(document,{childList:!0,subtree:!0});function n(e){const s={};return e.integrity&&(s.integrity=e.integrity),e.referrerPolicy&&(s.referrerPolicy=e.referrerPolicy),e.crossOrigin==="use-credentials"?s.credentials="include":e.crossOrigin==="anonymous"?s.credentials="omit":s.credentials="same-origin",s}function r(e){if(e.ep)return;e.ep=!0;const s=n(e);fetch(e.href,s)}})();const o={zoom:131072,drop:262144,minus:32768,plus:65536,up:2048,left:4096,down:8192,right:16384,k0:1,k1:2,k2:4,k3:8,k4:16,k5:32,k6:64,k7:128,k8:256,k9:512},T={player_pos:0,last_player_pos:16,player_chunk:32,player_velocity:48,camera_pos:64,last_camera_pos:80,camera_scale:96,camera_scale_change:104,depth:112,player_quadrant:120,frame:124,keys_pressed_mask:128,keys_held_mask:132,seed:144,seed2:208},q="abcdefghijklmnopqrstuvwxyz",v=26n;function N(i=100){if(i<=0)return"";const t=new Uint8Array(72);crypto.getRandomValues(t);let n=0n;const r=new DataView(t.buffer);for(let a=0;a<t.length;a+=8)n=n<<64n|r.getBigUint64(a);let e="",s=n%v**BigInt(i);for(;s>=0n&&(e+=q[Number(s%v)],s=s/v-1n,!(s<0n)););return e}function F(i){let t=0n;for(let n=0;n<i.length;n++){const r=BigInt(i.charCodeAt(n)-97);t=t*v+(r+1n)}return t}async function V(i,t){const n=F(i),r=new DataView(new ArrayBuffer(64));for(let c=0;c<8;c++)r.setBigUint64(c*8,n>>BigInt((7-c)*64)&0xffffffffffffffffn);let e=new Uint8Array(r.buffer,0,32),s=new Uint8Array(r.buffer,32,32);const a=await Promise.all([0,1,2,3].map(c=>crypto.subtle.importKey("raw",new Uint8Array([c]),{name:"HMAC",hash:"SHA-256"},!1,["sign"])));for(const c of a){const f=new Uint8Array(await crypto.subtle.sign("HMAC",c,s)),p=new Uint8Array(32);for(let h=0;h<32;h++)p[h]=e[h]^f[h];e=s,s=p}const u=new Uint8Array(64);return u.set(e,0),u.set(s,32),t.set(new BigUint64Array(u.buffer)),t}const k={Minus:o.minus,Equal:o.plus,KeyZ:o.zoom,KeyQ:o.drop,ArrowUp:o.up,KeyW:o.up,ArrowLeft:o.left,KeyA:o.left,ArrowDown:o.down,KeyS:o.down,ArrowRight:o.right,KeyD:o.right,Digit0:o.k0,Digit1:o.k1,Digit2:o.k2,Digit3:o.k3,Digit4:o.k4,Digit5:o.k5,Digit6:o.k6,Digit7:o.k7,Digit8:o.k8,Digit9:o.k9};function C(){let i={};const t={heldMask:0,keysHeld:0,keysPressed:0,currentlyHeld:0,horizontalPriority:0,verticalPriority:0,plusMinusPriority:0};function n(){i={},t.horizontalPriority=0,t.verticalPriority=0,t.plusMinusPriority=0,t.currentlyHeld=0,t.heldMask=0,t.keysPressed=0}return window.addEventListener("keydown",r=>{if(r.repeat||r.altKey||r.ctrlKey||r.metaKey||r.shiftKey)return;const e=k[r.code];e&&(t.heldMask|=e,i[e]=(i[e]||0)+1,e&(o.left|o.right)&&(t.horizontalPriority=e),e&(o.up|o.down)&&(t.verticalPriority=e),e&(o.plus|o.minus)&&(t.plusMinusPriority=e))}),window.addEventListener("keyup",r=>{const e=k[r.code];e&&(i[e]=Math.max(0,(i[e]||0)-1),i[e]===0&&(t.heldMask&=~e,e===t.horizontalPriority&&(t.horizontalPriority=t.heldMask&o.left||t.heldMask&o.right||0),e===t.verticalPriority&&(t.verticalPriority=t.heldMask&o.up||t.heldMask&o.down||0),e===t.plusMinusPriority&&(t.plusMinusPriority=t.heldMask&o.plus||t.heldMask&o.minus||0)))}),window.addEventListener("blur",n),document.addEventListener("visibilitychange",n),window.addEventListener("contextmenu",n),t}function H(i){const t=o.up|o.down|o.left|o.right;let n=i.heldMask&~t;n|=i.horizontalPriority,n|=i.verticalPriority,n|=i.plusMinusPriority,i.keysPressed=n&~i.keysHeld,i.currentlyHeld=n,i.keysHeld=n}const W=""+new URL("main-Ckne6iMJ.wasm",import.meta.url).href,K=`/*
 * Main shader for Depthwell. ADD ?raw FOR DEBUGGING SHADER TO THE END OF engineMaker.ts's \`SHADER_SOURCE\` VARIABLE TO NOT COMPRESS.
 */

// These are sprite sheet constants. Sprites are saved as a .png, and each asset is 16x16. See zig/world.zig's Sprite definitions for what these all are.
// These first three values are dynamically patched in from TypeScript, so do not set them here.
const TILES_PER_ROW: f32 = /* TILES_PER_ROW */ 1 /* TILES_PER_ROW */;
const TILES_PER_COLUMN: f32 = /* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */;
const DECOR_START: u32 = /* DECOR_START */ 1 /* DECOR_START */;

const TILE_SIZE: f32 = 16.0;
const PIXEL_UV_SIZE: f32 = 1.0 / TILE_SIZE;
const ATLAS_WIDTH: f32 = TILE_SIZE * TILES_PER_ROW;
const ATLAS_HEIGHT: f32 = TILE_SIZE * TILES_PER_COLUMN;
// const TEXTURE_BLEEDING_EPSILON = 0 / TILE_SIZE;

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
    edge_flags: u32,
};

@group(0) @binding(0) var<uniform> scene: SceneUniforms;
@group(0) @binding(1) var<storage, read> tiles: array<TileData>;
@group(0) @binding(2) var sprite_atlas: texture_2d<f32>;
@group(0) @binding(3) var pixel_sampler: sampler;

// Data passed from the Vertex step (per-corner) to the Fragment step (per-pixel)
struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,

    // @interpolate(flat) tells the GPU NOT to blend these values between the 4 corners of the quad.
    @location(1) @interpolate(flat) sprite_id: u32,
    @location(2) @interpolate(flat) edge_flags: u32,
    @location(3) @interpolate(flat) light: f32,
    @location(4) @interpolate(flat) seed: u32, // these 28 bits are used as efficently as possible
    @location(5) @interpolate(flat) seed2: u32, // murmurmix32'ed from seed

    // Local UV (0.0 to 1.0) across the surface of the specific tile.
    @location(6) local_uv: vec2f,
    // Where on the chunk a tile is
    @location(7) @interpolate(flat) tile_coords: vec2u,
};

// Extracts the specific bit ranges in the Block type (see zig/memory.zig).
fn unpack_tile(data: TileData) -> UnpackedTile {
    var out: UnpackedTile;

    out.sprite_id = extractBits(data.word0, 0u, 16u);
    out.edge_flags = extractBits(data.word0, 16u, 8u);
    // out.edge_flags = 0u; // test

    let light_u = extractBits(data.word0, 24u, 8u);
    out.light = f32(light_u) / 3000.0 + 1.0; // allow for (and expect) light > 1, no longer square-rooted

    // out.light = 1.0; // test
    out.hp = extractBits(data.word1, 0u, 4u);
    out.seed = extractBits(data.word1, 4u, 28u); // 28-bit seed
    out.seed2 = murmurmix32(out.seed);

    let random_mod = extractBits(out.seed, 16u, 2u);
    if (out.sprite_id == (DECOR_START + 2u) && (random_mod == 0u)) { // extract bits 16-18 for random modifications
        out.sprite_id++; // 2 mushroom type sprites
    }

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

        let ndc = vec2f(
            (screen_pos.x / scene.viewport_size.x) * 2.0 - 1.0,
            1.0 - (screen_pos.y / scene.viewport_size.y) * 2.0
        );

        // Prevent "texture bleeding"
        // let local_pos = clamp(local_pos, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));

        let atlas_uv = vec2f(
            (1 + local_pos.x) * TILE_SIZE / ATLAS_WIDTH,
            (0 + local_pos.y) * TILE_SIZE / ATLAS_HEIGHT
        );

        out.position = vec4f(ndc, 0.1, 1.0);
        out.uv = atlas_uv;
        out.edge_flags = 255u;
        out.sprite_id = 1u;
        out.light = 1.0;
        out.local_uv = local_pos;
        return out;
    }

    let tile = unpack_tile(tiles[instance_index]);

    // Cull empty sprites
    if (tile.sprite_id == 0u && scene.wireframe_opacity == 0.0) {
        out.position = vec4f(2.0, 2.0, 1.0, 1.0); // ideal outcode
        return out;
    }

    let tile_x = instance_index % scene.map_size.x;
    let tile_y = instance_index / scene.map_size.x;
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
            tile.sprite_id == (DECOR_START + 0u) || tile.sprite_id == (DECOR_START + 1u) // spiral plant, ceiling flower
        ),
        -2.0 * scene.zoom,
        tile.sprite_id == (DECOR_START + 2u) || tile.sprite_id == (DECOR_START + 3u) // mushroom sprites
    );

    // apply to screen_pos.y before converting to NDC
    // subtract from Y because in screen space, lower values are "higher" up
    let adjusted_y = screen_pos.y - vertical_offset;

    let ndc = vec2f(
        (screen_pos.x / scene.viewport_size.x) * 2.0 - 1.0,
        1.0 - (adjusted_y / scene.viewport_size.y) * 2.0
    );

    // Calculate which sprite in the atlas to sample
    let sprite_col = f32(tile.sprite_id % u32(TILES_PER_ROW));
    let sprite_row = f32(tile.sprite_id / u32(TILES_PER_ROW));

    // Prevent "texture bleeding"
    // let local_pos = clamp(local_pos, vec2f(TEXTURE_BLEEDING_EPSILON), vec2f(1.0 - TEXTURE_BLEEDING_EPSILON));

    let atlas_uv = vec2f(
        (sprite_col + local_pos.x) * TILE_SIZE / ATLAS_WIDTH,
        (sprite_row + local_pos.y) * TILE_SIZE / ATLAS_HEIGHT
    );

    out.position = vec4f(ndc, 0.2, 1.0);
    out.uv = atlas_uv;
    out.sprite_id = tile.sprite_id;
    out.edge_flags = tile.edge_flags;
    out.tile_coords = vec2u(tile_x, tile_y);
    out.light = tile.light;
    out.seed = tile.seed;
    out.seed2 = tile.seed2;
    out.local_uv = local_pos;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    var erode_mask: u32 = 1u;
    if (in.edge_flags != 0xFFu) {
        erode_mask = erosion(in.local_uv, in.edge_flags, in.seed2);
        if (scene.wireframe_opacity == 0.0 && erode_mask == 0u) {
            discard; // discard early
        }
    }

    // put here to prevent control flow breakage error
    var tex_color = textureSample(sprite_atlas, pixel_sampler, in.uv);

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

    // we use 10 out of the 24 seed bits here
    let extracted_l = f32(extractBits(in.seed, 0u, 4u));
    let extracted_a = f32(extractBits(in.seed, 4u, 3u));
    let l_nudge = extracted_l / 15.0;
    let a_nudge = extracted_a / 7.0;
    let b_nudge = f32(extractBits(in.seed, 7u, 3u)) / 4.0;

    // DISABLED
    lch.x += (l_nudge - 0.5) * 0.02; // shift lightness (0-1)
    lch.y *= 1.0 + a_nudge * 0.25; // shift chroma, which acts similar to saturation (0-1)
    lch.z += (b_nudge - 0.5) * 0.1; // shift hue (in RADIANS, red isn't exactly 0)

    var final_rgb = vec3f(0.0);
    lch.x *= in.light;
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
fn erosion(local_uv: vec2f, edge_flags: u32, seed2: u32) -> u32 {
    let px = u32(local_uv.x * TILE_SIZE);
    let py = u32(local_uv.y * TILE_SIZE);

    let se = seed2;
    let sc = murmurmix32(seed2);

    let has_top    = (edge_flags & EDGE_TOP) != 0u;
    let has_bottom = (edge_flags & EDGE_BOTTOM) != 0u;
    let has_left   = (edge_flags & EDGE_LEFT) != 0u;
    let has_right  = (edge_flags & EDGE_RIGHT) != 0u;
    let has_tl     = (edge_flags & EDGE_TOP_LEFT) != 0u;
    let has_tr     = (edge_flags & EDGE_TOP_RIGHT) != 0u;
    let has_bl     = (edge_flags & EDGE_BOTTOM_LEFT) != 0u;
    let has_br     = (edge_flags & EDGE_BOTTOM_RIGHT) != 0u;

    // Precompute outer corner radii from sc (used by both corner arcs and straight-edge safe zones)
    let r_tl = 4u + extractBits(sc, 0u, 1u);  // top-left: 2 or 3
    let r_tr = 4u + extractBits(sc, 2u, 1u);  // top-right: 4 or 5
    let r_bl = 4u + extractBits(sc, 4u, 1u);  // bottom-left: 4 or 5
    let r_br = 4u + extractBits(sc, 6u, 1u);  // bottom-right: 4 or 5

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
        let base_depth = 2u + extractBits(se, 0u, 1u); // 2 or 3 pixels inward
        let notch_pos = extractBits(se, 1u, 4u);
        let notch_dir = extractBits(se, 5u, 1u);
        let notch_width = 2u + extractBits(se, 6u, 2u);

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
        let base_depth = 2u + extractBits(se, 8u, 1u);
        let notch_pos = extractBits(se, 9u, 4u);
        let notch_dir = extractBits(se, 13u, 1u);
        let notch_width = 2u + extractBits(se, 14u, 2u);

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
        let base_depth = 2u + extractBits(se, 16u, 1u);
        let notch_pos = extractBits(se, 17u, 4u);
        let notch_dir = extractBits(se, 21u, 1u);
        let notch_width = 2u + extractBits(se, 22u, 2u);

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
        let base_depth = 2u + extractBits(se, 24u, 1u);
        let notch_pos = extractBits(se, 25u, 4u);
        let notch_dir = extractBits(se, 29u, 1u);
        let notch_width = 2u + extractBits(se, 30u, 2u);

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
        let r = 2u + extractBits(sc, 8u, 1u); // 2 or 3 pixel radius
        if (px < r && py < r) {
            let dx = px + 1u; // +1 so the circle center is at (-0.5, -0.5) effectively
            let dy = py + 1u;
            let dist_sq = dx * dx + dy * dy;
            if (dist_sq <= r * r) { return 0u; }
            if (dist_sq <= (r + 1u) * (r + 1u)) { return 2u; }
        }
    }

    if (!has_tr && has_top && has_right) {
        let r = 2u + extractBits(sc, 10u, 1u);
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
        let r = 2u + extractBits(sc, 12u, 1u);
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
        let r = 2u + extractBits(sc, 14u, 1u);
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
    let edge_width = 0.20 + f32(extractBits(seed, 10u, 3u)) / 32.0;
    let edge_strength = 0.25 + f32(extractBits(seed, 13u, 3u)) / 64.0;
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
    out.position = vec4f(x, y, 1.0, 1.0);

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

    // Direct bit-manipulation hack to float [0, 1)
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
`,Q="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAVAAAAAQCAMAAAB3GdczAAAAAXNSR0IArs4c6QAAAZ5QTFRFAAAAf8rLUsC6WN20VM6oR6F9srKyW1tbRkZGAAAAAAAAAAAAeo+3XXeqZG6OSVl8OktaPGpql0vbdzq3fDmVaDl+XxBqgxB1ncj8f7DgZY29W3ShOWdxAAAAlcmzSJZ+f6+bZp2HXYdxN2lXk7SBYaBsUolkJ3VVV35zRF1Wy8PDraeniYGHcW1yT05NAAAAm5eXdGpqUE5MMTEw8Lol9VYU9bKPy3QwiWBLWk5EWDw7NiUZ5NzWu5R1gltGb29vPC0tST0x2+XqrrK3fYmVSmt2OUhYLjM09fLL8OGAsZY3m3oJa0UZMScRufzSkvLQYOW8EMaBJJxsGoBsGcE/KXEo7Tc38JOT4yNt9cPqcvG0L+R/LKQba7tr/6PBzjU12bXbt4q732HBLKQbK06VJ4nNeGTGnIvbiqH2ydT9kFK8Qr/oSUGCRXLjAAAAAAAAEl83HZc5HkxKO4+QWaOlWMCXisevLWOGI61tNehAAAAAAAAAAAAA0EIz95Ag98ggd0IaqnxYjl03mlglAAAAAAAAAAAAAAAAAAAAAAAAT/Hz1wAAAIp0Uk5TAP//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////L+YP8AAACg9JREFUWIW1mOtz4uYVxsmqu92dEZIQkjCgWRBCQtigQYDQBXRDF5CExMXfvN7tJpM0vc4kbZK2H5qmyT/eOcL2rr1bezdtjj0S2J/e35znPM95S6WH69lNvec7gaMYhpYJFCcqeIUgGJqkKLLKkDRTo2sMw7JsnW022MZJnW2yLMtx7Rbf4Ti+0+Ge8x2u3+tJUq/b74mCIHX73eFwMJAHg4EsF6+BOlJVdaKOxuOJOlImU13XdMPUtZk+M3RDn7ueZzmOtXBsz7Ndx/X9IFgF0cqPglW0CsJNEsdpBs9NnCSbdIvk2y2y3263hz2C5MjVGS9KL2+d+dNPPwDMz6xnz24ThfeTm+94uYxiZQwHnjhR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";async function Z(i,t){const n=await navigator.gpu.requestAdapter({powerPreference:t&&t.highPerformance?"high-performance":"low-power"});if(!n)throw new DOMException("Couldn't request WebGPU adapter.","NotSupportedError");const r=await n.requestDevice();let e=null;if(r.addEventListener("uncapturederror",d=>{const g=d.error;if(e===null)if(globalThis.reportError)reportError(g);else throw g;else if(!e.destroyed){e.destroy("fatal WebGPU error",g);return}}),r.lost.then(d=>console.error(`WebGPU Device lost: ${d.message}`)),i===void 0){if(i=document.getElementsByTagName("canvas")[0],i===void 0)throw Error("No canvas element or ID string provided, and no canvas was not found in the HTML.")}else if(typeof i=="string"){const d=document.getElementById(i);if(!(d instanceof HTMLCanvasElement))throw Error(`Element with ID "${i}" is not a canvas element.`);i=d}const s=i.getContext("webgpu");if(!s)throw Error("Could not get WebGPU context from canvas.");const a=r.features.has("canvas-rgba16float-support")?"rgba16float":"bgra8unorm";s.configure({device:r,format:a,alphaMode:"opaque"});const u=await WebAssembly.instantiateStreaming(fetch(W),{env:{js_message:(d,g,y)=>{let _=new TextDecoder().decode(new Uint8Array(f.buffer,Number(d),Number(g)));_.charAt(0)!=="]"?_="["+(e?.LOGGING_PREFIX||"")+_:_=_.slice(1),y===1?console.info("%c"+_,"font-weight: 600"):[console.log,console.info,console.warn,console.error][y](_)},js_write_text:(d,g,y)=>{const _=new Uint8Array(f.buffer,Number(g),Number(y)),M=new TextDecoder().decode(_),z=document.getElementById(`text${d+1}`);z.textContent=M},js_get_time:()=>performance.now(),js_handle_visible_chunks:d=>e?.handleVisibleChunks(d)}}),c=u.instance.exports,f=c.memory,p=r.createShaderModule({label:"Main shader",code:K.replace("/* TILES_PER_ROW */ 1 /* TILES_PER_ROW */",""+c.get_tiles_per_row()).replace("/* TILES_PER_COLUMN */ 1 /* TILES_PER_COLUMN */",""+c.get_tiles_per_column()).replace("/* DECOR_START */ 1 /* DECOR_START */",""+c.get_decor_start())}),h=r.createBindGroupLayout({label:"Main bind group layout",entries:[{binding:0,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"uniform",hasDynamicOffset:!0}},{binding:1,visibility:GPUShaderStage.VERTEX|GPUShaderStage.FRAGMENT,buffer:{type:"read-only-storage"}},{binding:2,visibility:GPUShaderStage.FRAGMENT,texture:{}},{binding:3,visibility:GPUShaderStage.FRAGMENT,sampler:{}}]}),m=r.createPipelineLayout({label:"Shared Pipeline Layout",bindGroupLayouts:[h]}),I=r.createRenderPipeline({label:"Tilemap pipeline",layout:m,vertex:{module:p,entryPoint:"vs_main"},fragment:{module:p,entryPoint:"fs_main",targets:[{format:a,blend:{color:{srcFactor:"src-alpha",dstFactor:"one-minus-src-alpha"},alpha:{srcFactor:"one",dstFactor:"one-minus-src-alpha"}}}]},primitive:{topology:"triangle-list",cullMode:"none"}}),L=r.createRenderPipeline({label:"Background pipeline",layout:m,vertex:{module:p,entryPoint:"vs_background"},fragment:{module:p,entryPoint:"fs_background",targets:[{format:a}]},primitive:{topology:"triangle-list"}});e=new S(i,n,r,s,u,I,L),e.exports.setup(),await e.setSeed(N(100)),e.exports.init();const D=new ResizeObserver(e.onResize);e.resizeObserver=D,e.updateCanvasStyle();try{e.resizeObserver.observe(i,{box:"device-pixel-content-box"})}catch{console.log("ResizeObserver property device-pixel-content-box not supported, falling back to content-box."),e.resizeObserver.observe(i,{box:"content-box"})}e.onResize([{contentRect:{width:i.clientWidth,height:i.clientHeight}}]);const O=await S.loadTexture(r,Q),U=r.createSampler({magFilter:"nearest",minFilter:"nearest",addressModeU:"clamp-to-edge",addressModeV:"clamp-to-edge"});e.atlasTextureView=O.createView(),e.pixelSampler=U;const G=r.createBuffer({label:"SceneUniforms",size:256*P,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});return e.uniformBuffer=G,e}var R=(i=>(i[i.Uint8=8]="Uint8",i[i.Uint16=16]="Uint16",i[i.Uint32=32]="Uint32",i[i.Uint64=64]="Uint64",i[i.Int8=-8]="Int8",i[i.Int16=-16]="Int16",i[i.Int32=-32]="Int32",i[i.Int64=-64]="Int64",i[i.Uint8Clamped=-80]="Uint8Clamped",i[i.Float32=-320]="Float32",i[i.Float64=-640]="Float64",i))(R||{});globalThis.WasmTypeCode=R;const B={8:Uint8Array,16:Uint16Array,32:Uint32Array,64:BigUint64Array,[-8]:Int8Array,[-16]:Int16Array,[-32]:Int32Array,[-64]:BigInt64Array,[-80]:Uint8ClampedArray,[-320]:Float32Array,[-640]:Float64Array},P=4;class S{engineModule;exports;memory;LAYOUT_PTR;GAME_STATE_PTR;canvas;adapter;device;context;bindGroups=Array(P);uniformBuffer;tileBuffers=Array(P);tileBufferDirty=!1;atlasTextureView;pixelSampler;renderPipeline;bgPipeline;renderPass=null;currentEncoder=null;currentTextureView=null;renderCallId=0;sceneDataBuffer=new ArrayBuffer(256);sceneDataF32=new Float32Array(this.sceneDataBuffer);sceneDataU32=new Uint32Array(this.sceneDataBuffer);inputState;resizeObserver;forceAspectRatio=!0;previousForceAspectRatio=null;tileMapWidth;tileMapHeight;prepare_visible_chunks_time=0;isVisibleDataNew=!0;wireframeOpacity=0;startTime=performance.now();seed="";destroyed=!1;destroyedError=null;encoder=new TextEncoder;decoder=new TextDecoder;LOGGING_PREFIX="";constructor(t,n,r,e,s,a,u){this.canvas=t,this.adapter=n,this.device=r,this.context=e,this.engineModule=s,this.renderPipeline=a,this.bgPipeline=u,this.exports=s.instance.exports,this.memory=s.instance.exports.memory,this.LAYOUT_PTR=Number(this.exports.get_memory_layout_ptr()),this.GAME_STATE_PTR=Number(this.getScratchView()[3]),this.inputState=C()}static async create(t,n){return await Z(t,n)}destroy(t="unknown reason",n=null){this.resizeObserver.disconnect(),this.destroyed=t,this.destroyedError=n}static async loadTexture(t,n){const e=await(await fetch(n)).blob(),s=await createImageBitmap(e),a=t.createTexture({label:`Texture from  ${n}`,size:[s.width,s.height],format:t.features.has("canvas-rgba16float-support")?"rgba16float":"bgra8unorm",usage:GPUTextureUsage.TEXTURE_BINDING|GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT});return t.queue.copyExternalImageToTexture({source:s},{texture:a},[s.width,s.height]),a}uploadVisibleChunks(t=1){const n=performance.now();this.exports.prepare_visible_chunks(t,this.canvas.width,this.canvas.height),this.prepare_visible_chunks_time=performance.now()-n}handleVisibleChunks(t){if(!this.currentEncoder||!this.currentTextureView||!this.renderPass)return;const n=this.getScratchPtr();if(this.getScratchLen()===0)return;const e=Number(this.getScratchProperty(0)),s=Number(this.getScratchProperty(1)),a=e*s*2;this.tileMapWidth=e,this.tileMapHeight=s;const u=new Uint32Array(this.memory.buffer,n,a),c=a*4;this.recreateBufferAndBindGroup(c),this.renderPass.setPipeline(this.renderPipeline),this.renderPass.setBindGroup(0,this.bindGroups[this.renderCallId],[this.renderCallId*256]),this.renderPass.setViewport(0,0,this.canvas.width,this.canvas.height,0,1),this.setSceneData(t,e,s),this.device.queue.writeBuffer(this.tileBuffers[this.renderCallId],0,u);const f=e*s+1;this.renderPass.draw(6,f),this.isVisibleDataNew=!1,this.renderCallId++}setSceneData(t,n,r){const e=this.getScratchProperty(2,-640),s=this.getScratchProperty(3,-640),a=this.getScratchProperty(4,-640),u=this.getScratchProperty(5,-640),c=this.getScratchProperty(6,-640);this.sceneDataF32[0]=e,this.sceneDataF32[1]=s,this.sceneDataF32[2]=this.canvas.width,this.sceneDataF32[3]=this.canvas.height;const f=6e4,h=(performance.now()-this.startTime)%(f*2);let m;h<f?m=h/1e3:m=(f-(h-f))/1e3,this.sceneDataF32[4]=m,this.sceneDataF32[5]=a,this.sceneDataF32[6]=a<.25?0:this.wireframeOpacity,this.sceneDataF32[7]=t,this.sceneDataF32[8]=u,this.sceneDataF32[9]=c,this.sceneDataU32[10]=n,this.sceneDataU32[11]=r,this.device.queue.writeBuffer(this.uniformBuffer,this.renderCallId*256,this.sceneDataF32)}recreateBufferAndBindGroup(t){const n=this.renderCallId;(!this.tileBuffers[n]||this.tileBuffers[n].size<t)&&(this.tileBuffers[n]=this.device.createBuffer({label:`Tile grid slot ${n}`,size:t,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST}),this.bindGroups[n]=this.device.createBindGroup({label:`Bind group slot ${n}`,layout:this.renderPipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer:this.uniformBuffer,offset:0,size:256}},{binding:1,resource:{buffer:this.tileBuffers[n]}},{binding:2,resource:this.atlasTextureView},{binding:3,resource:this.pixelSampler}]}))}getWASMMemoryMB(){return this.memory.buffer.byteLength/1024/1024}getGameView(t,n=0,r){return new B[t](this.memory.buffer,this.GAME_STATE_PTR+n,r)}getRawView(t,n,r){return new B[t](this.memory.buffer,n,r)}_tempScratchView=null;getScratchView(){return(this._tempScratchView===null||this._tempScratchView.buffer!==this.memory.buffer)&&(this._tempScratchView=new BigUint64Array(this.memory.buffer,this.LAYOUT_PTR,24)),this._tempScratchView}getScratchPtr(){return Number(this.getScratchView()[0])}getScratchLen(){return Number(this.getScratchView()[1])}setScratchLen(t){this.getScratchView()[1]=BigInt(t)}getScratchCapacity(){return Number(this.getScratchView()[2])}getScratchProperty(t,n=64){(this._tempScratchView===null||this._tempScratchView.buffer!==this.memory.buffer)&&(this._tempScratchView=new BigUint64Array(this.memory.buffer,this.LAYOUT_PTR,24));let r=this._tempScratchView;return n==-640&&(r=new Float64Array(r.buffer,r.byteOffset,r.length)),Number(r[t+4])}readStr(t=this.getScratchPtr(),n=this.getScratchLen()){const r=new Uint8Array(this.memory.buffer,t,n);return this.decoder.decode(r)}writeStr(t,n=!0){const r=t.length;if(r===0)return null;n&&this.setScratchLen(0);const e=this.exports.scratch_alloc(r);if(e===0n)return null;const s=new Uint8Array(this.memory.buffer,Number(e),r);if(this.encoder.encodeInto(t,s).read<r)throw new RangeError("String truncated with non-ASCII characters detected.");return Number(e)}async setSeed(t){this.seed=t,await V(t,this.getGameView(64,T.seed,8))}updateCanvasStyle(){this.forceAspectRatio!==this.previousForceAspectRatio&&(this.previousForceAspectRatio=this.forceAspectRatio,this.forceAspectRatio?(this.canvas.style.maxWidth=`calc(100vh*${16/9})`,this.canvas.style.maxHeight=`calc(100vw*${9/16})`):(this.canvas.style.maxWidth="none",this.canvas.style.maxHeight="none"))}onResize=t=>{const n=t[0];let r,e;if(n.devicePixelContentBoxSize)r=n.devicePixelContentBoxSize[0].inlineSize,e=n.devicePixelContentBoxSize[0].blockSize;else if(n.contentBoxSize){const s=n.contentBoxSize[0].inlineSize,a=n.contentBoxSize[0].blockSize;r=Math.round(s*devicePixelRatio),e=Math.round(a*devicePixelRatio)}else{const s=n.contentRect.width,a=n.contentRect.height;r=Math.round(s*devicePixelRatio),e=Math.round(a*devicePixelRatio)}(this.canvas.width!==r||this.canvas.height!==e)&&(this.canvas.width=r,this.canvas.height=e)};renderFrame(t,n){if(this.renderCallId=0,this.destroyed!==!1)return;this.updateCanvasStyle(),this.currentEncoder=this.device.createCommandEncoder(),this.currentTextureView=this.context.getCurrentTexture().createView();const e=this.currentEncoder.beginRenderPass({colorAttachments:[{view:this.currentTextureView,loadOp:"load",clearValue:{r:0,g:0,b:0,a:1},storeOp:"store"}]});this.renderPass=e,this.recreateBufferAndBindGroup(1024),this.sceneDataF32[7]=1,this.device.queue.writeBuffer(this.uniformBuffer,this.renderCallId*256,this.sceneDataF32),this.renderPass.setPipeline(this.bgPipeline),this.renderPass.setBindGroup(0,this.bindGroups[this.renderCallId],[this.renderCallId++*256]),this.renderPass.draw(3),this.uploadVisibleChunks(t),this.renderPass.end(),this.device.queue.submit([this.currentEncoder.finish()]),this.currentEncoder=null,this.currentTextureView=null}tick(t){const n=this.getGameView(32,T.keys_pressed_mask,2);H(this.inputState),n[0]=this.inputState.keysPressed,n[1]=this.inputState.keysHeld,this.exports.tick(t)}}location.protocol==="file:"&&alert("This game cannot run from a local file:// context; use an online version or test from localhost instead.");isSecureContext||alert("This game cannot run in a non-secure context.");navigator.gpu||alert("WebGPU is not supported by your browser; try playing this on an alternate or more modern browser.");const J=await navigator.gpu.requestAdapter();J||alert("WebGPU is supported, but no compatible GPU was found.");const Y=["text1","text2","text3","text4","logicText","renderText"];document.addEventListener("wheel",function(i){i.ctrlKey},{passive:!1});let l=await S.create();l.getTimeoutLength=function(){return++X%3==2?16:17};l.getFrameRate=function(){return 60};l.baseSpeed=1;let x=performance.now(),b=0,X=0;globalThis.engine=l;console.log("Engine initialized successfully:",l),console.log("Exported functions and memory:",l.exports);window.addEventListener("blur",()=>x=1/0);const w=Array(60).fill(0),E=Array(60).fill(0),A=Array(60).fill(0);l.isDebug=!!l.exports.isDebug();l.renderLoop=function(i){let t=performance.now(),n=x===1/0?0:t-x,r=Math.min(n*l.getFrameRate()/1e3,l.getFrameRate());if(l.logicLoop(Math.floor(b+r)),b=(b+r)%1,l.isDebug){E.shift(),E.push(n),A.shift(),A.push(l.prepare_visible_chunks_time);const s=Math.max.apply(null,E),a=Math.max.apply(null,A);let u="#cccccc";s>55?u="#e83769":s>30?u="#f39c19":s>20&&(u="#f7ce1a");const c=document.getElementById("renderText");c.textContent=`Time since last render/prepare_visible_chunks time: ${n.toFixed(1)}ms, ${l.prepare_visible_chunks_time.toFixed(1)}ms
Worst (past 60 frames): ${s.toFixed(1)}ms, ${a.toFixed(1)}ms`,c.style.fontWeight=s>40?s>55?700:600:500,c.style.color=u}let e=Math.min(b-1,0);l.renderFrame(e,x),requestAnimationFrame(l.renderLoop)};l.logicLoop=function(i){const t=performance.now();for(let r=0;r<i;r++)l.tick(60/l.getFrameRate()*l.baseSpeed);x=performance.now();let n=x-t;if(l.isDebug){w.shift(),w.push(n);const r=Math.max.apply(null,w);let e="#cccccc";r>30?e="#e83769":r>15?e="#f39c19":r>10&&(e="#f7ce1a");const s=document.getElementById("logicText");s.textContent=`Logic diff: ${n.toFixed(1)}ms for ${i} tick${i==1?"":"s"}
Worst (past 60 frames): ${r.toFixed(1)}ms
`,s.style.fontWeight=r>20?r>40?700:600:500,s.style.color=e}};globalThis.Zig={KeyBits:o,game_state_offsets:T};l.isDebug?(console.log("Zig code is in debug mode. Use engine.exports to see its functions, variables, and memory, such as engine.exports.test_logs."),Y.forEach(i=>{document.getElementById(i).style.display="inline"})):console.log('Note: engine is in verbose mode, but Zig code is not in -Doptimize=Debug; run just "zig build" to enable additional testing features and safety checks if possible.');setTimeout(function(){l.renderLoop(0)},17);
