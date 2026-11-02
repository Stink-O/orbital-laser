// Orbital Laser's post pass for the Hurricane (laser 13). Like the Supercell's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, mh, ign) less the other lasers' own functions, followed by this file, and
// sets it for a hurricane strike only. Validate with tools/check-shader.sh.

// ---- laser 13: the hurricane --------------------------------------------------------------------------------------
// No beam. A spiral cloud deck gathers over the target and starts to turn, its bands reaching out for the best part of
// a kilometre; the eye clears and the eyewall towers round it, sloping out as it rises; rain falls in the bands, the
// light goes grey and the land under it darkens and runs wet. The wind spins up, and from the eyewall out it tears the
// land up: thousands of blocks in the land's own colours (the mod reads them: strike/hurricane.rs) fly round the
// eyewall in rings, climbing it into the cloud, skimming the land further out (`hu_debris`), whole trees among them
// tumbling as they go (`hu_trees`, their trunks and canopies as they stood), a wall of dust and spray churning round
// its foot. Then the winds drop: everything is flung out and falls, and the cloud breaks up.
// strike/hurricane.rs keeps the HU_* in step and hands the pass its table (render.set-data): the trees, each ring's
// colours (what was torn up under it) and the land's height round the middle.
const HU_LEN: f32 = 64.0;          // the strike's length (lasers.rs)
const HU_FORM: f32 = 10.0;         // the cloud formed and turning,
const HU_EYE_T: f32 = 14.0;        // the eye clear,
const HU_F0: f32 = 15.0;           // the wind tearing at the land from the eyewall,
const HU_F1: f32 = 35.0;           // out to HU_R_LIFT by here,
const HU_FLING: f32 = 46.0;        // the winds dropping, everything flung out,
const HU_CLEAR: f32 = 54.0;        // the cloud breaking up from here
const HU_R_EYE: f32 = 26.0;        // the eye (calm),
const HU_R_IN: f32 = 32.0;         // where the wind starts to tear at the land,
const HU_R_W: f32 = 62.0;          // the eyewall (the strongest wind),
const HU_R_LIFT: f32 = 150.0;      // how far out it uproots the trees,
const HU_R_PLANTS: f32 = 175.0;    // and strips the plants
const HU_V: f32 = 40.0;            // the wind at the eyewall at its height, blocks a second
const HU_SPIN: f32 = -1.0;         // cyclonic: seen from above, east to north
const HU_NR: i32 = 13;             // the rings the blocks fly round in (hurricane.rs's HU_NR, HU_RING0, HU_RING_W)
const HU_RING0: f32 = 30.0;
const HU_RING_W: f32 = 10.0;
const HU_CELL: f32 = 3.0;          // their cells, a block at most in each
const HU_PAL: u32 = 64u;           // the table: each ring's blocks from HU_PAL (HU_PN a ring, each a block type),
const HU_PN: u32 = 32u;
const HU_BK: u32 = 512u;           // the block types from HU_BK (HU_BKW words each: hurricane.rs's bk_words),
const HU_BKW: u32 = 12u;
const HU_T: u32 = 6656u;           // the trees from HU_T (HU_TW words each: hurricane.rs's TreeRec::words),
const HU_TW: u32 = 28u;
const HU_NT: u32 = 128u;
const HU_G: u32 = 10240u;           // the land's height round the middle from HU_G (HU_GR rings of HU_GA)
const HU_GR: u32 = 16u;
const HU_GA: u32 = 64u;
const HU_G_STEP: f32 = 11.0;
// The cloud: the deck's base and top over the middle's ground near the eyewall, how far out it reaches.
const HU_BASE: f32 = 92.0;
const HU_TOP: f32 = 250.0;
const HU_DECK: f32 = 950.0;
const HU_WALL_TOP: f32 = 330.0;    // the eyewall's top over the middle's ground

// The game's block textures (the atlas capability, the fork's API 10): every vanilla texture a layer of the first array,
// gamma-encoded, sampled nearest as the terrain is (docs/mods.md, "Block textures in a post pass").
@group(0) @binding(8) var block_sprites: texture_2d_array<f32>;
@group(0) @binding(9) var block_sampler: sampler;

fn hu_u(i: u32) -> u32 {
    if (i >= arrayLength(&mod_data)) {
        return 0u;
    }
    return mod_data[i];
}
fn hu_w(i: u32) -> f32 {
    return bitcast<f32>(hu_u(i));
}
fn hu_have() -> bool {
    return arrayLength(&mod_data) > HU_G;
}
fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}
fn hu_565(c: u32) -> vec3<f32> {
    return srgb_to_linear(vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0));
}

// ---- the wind (hurricane.rs's spin, spin_int, wind_shape, omega, phase, front_t) -----------------------------------
fn hu_spin(t: f32) -> f32 {
    var k = array<vec2<f32>, 7>(vec2<f32>(0.0, 0.04), vec2<f32>(8.0, 0.15), vec2<f32>(26.0, 1.0), vec2<f32>(44.0, 1.0), vec2<f32>(50.0, 0.35), vec2<f32>(58.0, 0.08), vec2<f32>(64.0, 0.0));
    for (var i = 0; i < 6; i = i + 1) {
        let a = k[i];
        let b = k[i + 1];
        if (t <= b.x) {
            return mix(a.y, b.y, clamp((t - a.x) / (b.x - a.x), 0.0, 1.0));
        }
    }
    return 0.0;
}
fn hu_spin_int(t: f32) -> f32 {
    var k = array<vec2<f32>, 7>(vec2<f32>(0.0, 0.04), vec2<f32>(8.0, 0.15), vec2<f32>(26.0, 1.0), vec2<f32>(44.0, 1.0), vec2<f32>(50.0, 0.35), vec2<f32>(58.0, 0.08), vec2<f32>(64.0, 0.0));
    var s = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        let a = k[i];
        let b = k[i + 1];
        if (t <= a.x) {
            break;
        }
        let e = min(t, b.x);
        let se = a.y + (b.y - a.y) * (e - a.x) / (b.x - a.x);
        s = s + 0.5 * (a.y + se) * (e - a.x);
    }
    return s;
}
fn hu_shape(r: f32) -> f32 {
    return select(pow(HU_R_W / max(r, 1.0), 0.55), r / HU_R_W, r < HU_R_W);
}
fn hu_omega(r: f32) -> f32 {
    return HU_V * hu_shape(r) / max(r, 1.0);
}
fn hu_front(r: f32) -> f32 {
    if (r < HU_R_IN || r > HU_R_PLANTS) {
        return 1.0e9;
    }
    if (r < HU_R_W) {
        return HU_F0 + 3.0 * (HU_R_W - r) / (HU_R_W - HU_R_IN);
    }
    return HU_F0 + (HU_F1 - HU_F0) * pow((r - HU_R_W) / (HU_R_LIFT - HU_R_W), 1.25);
}
// How far the storm has formed, how much of it is left as it breaks up, how clear its eye is.
fn hu_form(t: f32) -> f32 {
    return smoothstep(0.0, HU_FORM, t);
}
fn hu_fade(t: f32) -> f32 {
    return 1.0 - smoothstep(HU_CLEAR, HU_LEN - 1.0, t);
}
fn hu_eye(t: f32) -> f32 {
    return smoothstep(7.0, HU_EYE_T, t);
}
// How hard it rains (0 to 1), how far out the deck reaches.
fn hu_rain(t: f32) -> f32 {
    return smoothstep(4.0, 12.0, t) * (1.0 - smoothstep(HU_CLEAR - 3.0, HU_CLEAR + 4.0, t));
}
fn hu_deck_r(t: f32) -> f32 {
    return 160.0 + (HU_DECK - 160.0) * smoothstep(0.0, HU_FORM + 4.0, t);
}

// ---- the land's height round the middle (the table's HU_G) ----------------------------------------------------------
fn hu_g_at(i: u32, a: u32) -> f32 {
    let v = hu_w(HU_G + min(i, HU_GR - 1u) * HU_GA + (a % HU_GA));
    return select(0.0, v, v == v);
}
// The ground over the middle's at q (off the middle).
fn hu_ground(q: vec2<f32>) -> f32 {
    if (!hu_have()) {
        return 0.0;
    }
    let r = length(q) / HU_G_STEP - 0.5;
    let a = fract(atan2(q.y, q.x) / TAU) * f32(HU_GA) - 0.5;
    let ri = clamp(floor(r), 0.0, f32(HU_GR - 1u));
    let fr = clamp(r - ri, 0.0, 1.0);
    let ai = floor(a);
    let fa = a - ai;
    let i0 = u32(ri);
    let i1 = min(i0 + 1u, HU_GR - 1u);
    let a0 = u32(ai + f32(HU_GA)) % HU_GA;
    let a1 = (a0 + 1u) % HU_GA;
    return mix(mix(hu_g_at(i0, a0), hu_g_at(i0, a1), fa), mix(hu_g_at(i1, a0), hu_g_at(i1, a1), fa), fr);
}

// ---- the blocks flying round the eyewall (hurricane.rs's ring_*; keep in step) ---------------------------------------
fn hu_ring_r(k: i32) -> f32 {
    return HU_RING0 + HU_RING_W * (f32(k) + 0.5);
}
fn hu_ring_h(r: f32) -> f32 {
    return 16.0 + 232.0 * (1.0 - smoothstep(70.0, 150.0, r));
}
fn hu_ring_rise(r: f32) -> f32 {
    return 2.0 + 7.0 * (1.0 - smoothstep(60.0, 140.0, r));
}
fn hu_ring_dens(r: f32) -> f32 {
    return 0.045 + 0.115 * (1.0 - smoothstep(105.0, 160.0, r));
}
fn hu_ring_on(r: f32, t: f32) -> f32 {
    let f = hu_front(r);
    return smoothstep(f, f + 2.5, t) * (1.0 - smoothstep(HU_FLING + 1.0, HU_FLING + 6.5, t));
}
// The fling: how far out everything has been thrown since HU_FLING, and how far it has risen and fallen.
fn hu_flung(t: f32) -> vec2<f32> {
    let s = max(t - HU_FLING, 0.0);
    return vec2<f32>(9.0 * s, 4.0 * s - 7.0 * s * s);
}
// A turn by `a` about unit `ax` (Rodrigues), as a matrix.
fn hu_rot(ax: vec3<f32>, a: f32) -> mat3x3<f32> {
    let c = cos(a);
    let s = sin(a);
    let k = 1.0 - c;
    let x = ax.x;
    let y = ax.y;
    let z = ax.z;
    return mat3x3<f32>(
        vec3<f32>(k * x * x + c, k * x * y + s * z, k * x * z - s * y),
        vec3<f32>(k * x * y - s * z, k * y * y + c, k * y * z + s * x),
        vec3<f32>(k * x * z + s * y, k * y * z - s * x, k * z * z + c));
}
fn hu_unit(h: u32) -> vec3<f32> {
    let v = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) / 511.5 - 1.0;
    return normalize(v + vec3<f32>(1.0e-3, 2.0e-3, 0.0));
}

struct HuHit {
    t: f32,
    n: vec3<f32>,
    // the block type it is (the table's HU_BK), which of its faces (0 its top, 1 its bottom, 2 a side) and where on
    // that face (0 to 1 across it), and how the face is lit apart from the light (a leaf's dapple)
    bk: u32,
    face: u32,
    uv: vec2<f32>,
    shade: f32,
    // what it was: -2048 nothing, -1 - i tree i, else a block (its packed cell, `hu_pack`)
    id: vec2<f32>,
}
fn hu_none() -> HuHit {
    var h: HuHit;
    h.t = 1.0e9;
    h.n = vec3<f32>(0.0, 1.0, 0.0);
    h.bk = 0u;
    h.face = 2u;
    h.uv = vec2<f32>(0.5);
    h.shade = 1.0;
    h.id = vec2<f32>(-2048.0, 0.0);
    return h;
}
// The colour of block type `bk`'s face `face` (0 top, 1 bottom, 2 a side) at `uv` on it (0 to 1 along the side's two
// axes, as the game's block sprites name them), linear, `lod` the mip level its texels are seen at: the game's own
// texture where the mod packed one for it (hurricane.rs's bk_words: the face, the overlay laid over it (a grass block's
// tinted side), each tinted as the game tints it; a cut-out texture's clear pixels dark, as fast leaves are), else
// (and far off, where a block is a few pixels) its texture's average colour.
fn hu_face(bk: u32, face: u32, uv: vec2<f32>, lod: f32) -> vec3<f32> {
    let o = HU_BK + bk * HU_BKW;
    let a = hu_u(o);
    let b = hu_u(o + 1u);
    let avg = hu_565(select(select(a >> 16u, b & 0xFFFFu, face == 1u), a & 0xFFFFu, face == 0u));
    let f0 = hu_u(o + 2u + 3u * face);
    if ((f0 & 1u) == 0u || lod > 3.5) {
        return avg;
    }
    let m = hu_u(o + 4u + 3u * face);
    let q = vec3<f32>(vec3<u32>(m, m >> 2u, m >> 4u) & vec3<u32>(3u)) - 1.0;
    let r = vec3<f32>(vec3<u32>(m >> 6u, m >> 8u, m >> 10u) & vec3<u32>(3u)) - 1.0;
    // (u0, v0, du-u | du-v, dv-u, dv-v)
    let st = fract(vec2<f32>(q.x + uv.x * q.z + uv.y * r.y, q.y + uv.x * r.x + uv.y * r.z) * 0.99999 + 0.000005);
    let lv = clamp(lod, 0.0, f32(textureNumLevels(block_sprites) - 1));
    let c0 = textureSampleLevel(block_sprites, block_sampler, st, i32((f0 >> 2u) & 0x3FFFu), lv);
    var rgb = srgb_to_linear(c0.rgb * hu_tint(f0 >> 16u));
    if ((f0 & 2u) != 0u && c0.a < 0.5) {
        rgb = avg * 0.3;
    }
    let f1 = hu_u(o + 3u + 3u * face);
    if ((f1 & 1u) != 0u) {
        let c1 = textureSampleLevel(block_sprites, block_sampler, st, i32((f1 >> 2u) & 0x3FFFu), lv);
        rgb = mix(rgb, srgb_to_linear(c1.rgb * hu_tint(f1 >> 16u)), c1.a);
    }
    return rgb;
}
// A face's tint (5-6-5; 0xFFFF none), gamma-encoded as the game multiplies the texture by it.
fn hu_tint(c: u32) -> vec3<f32> {
    if (c == 0xFFFFu) {
        return vec3<f32>(1.0);
    }
    return vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0);
}
// Which face of a block a local normal `nl` (its own axes) is.
fn hu_face_of(nl: vec3<f32>) -> u32 {
    return select(2u, select(1u, 0u, nl.y > 0.0), abs(nl.y) > 0.5);
}
// A block's cell (ring k, round it iu, up it iv) packed into two half-floats exactly, and back.
fn hu_pack(k: i32, iu: i32, iv: i32) -> vec2<f32> {
    return vec2<f32>(f32(iu + 512 * (k & 3)), f32(iv + 128 + 512 * (k >> 2u)));
}
fn hu_unpack(id: vec2<f32>) -> vec3<i32> {
    let a = i32(id.x + 0.5);
    let b = i32(id.y + 0.5);
    return vec3<i32>((a >> 9u) | ((b >> 9u) << 2u), a & 511, (b & 511) - 128);
}

// Ray rd (from the eye) against the block in cell (k, iu, iv) at `t`, the middle at C (off the eye): its hit, if
// nearer than `best`. St: the wind's sum to now, Sf: to the fling (the climb stops there).
fn hu_block(rd: vec3<f32>, C: vec3<f32>, k: i32, iu: i32, iv: i32, t: f32, St: f32, Sf: f32, seed: u32, best: ptr<function, HuHit>) {
    let rk = hu_ring_r(k);
    let h = pcg(u32(k) * 0x9E3779B1u ^ pcg(bitcast<u32>(iu) ^ pcg(bitcast<u32>(iv) * 0x85EBCA6Bu ^ seed)));
    let dens = hu_ring_dens(rk) * hu_ring_on(rk, t);
    if (f32(h & 0xFFFFu) * (1.0 / 65535.0) >= dens) {
        return;
    }
    let h2 = pcg(h);
    let h3 = pcg(h2 ^ 0x51u);
    let nu = floor(TAU * rk / HU_CELL);
    let ju = (f32(h2 & 255u) / 255.0 - 0.5) * 0.4;
    let jv = (f32((h2 >> 8u) & 255u) / 255.0 - 0.5) * 0.4;
    let jr = (f32((h2 >> 16u) & 255u) / 255.0 - 0.5) * 7.0;
    let pick = h2 >> 24u;
    var size = select(select(1.5, 0.55, pick < 230u), 1.0, pick < 166u);
    let fl = hu_flung(t);
    let a = HU_SPIN * hu_omega(rk) * St + (f32(iu) + 0.5 + ju) * TAU / nu;
    let r = rk + jr + fl.x;
    let y = hu_ring_rise(rk) * Sf + (f32(iv) + 0.5 + jv) * HU_CELL + fl.y;
    let pc = vec2<f32>(cos(a), sin(a)) * r;
    // (rising out of the land, thinning out towards the top of its ring; gone into the land as it falls)
    let g = hu_ground(pc);
    let yr = y - g;
    let hk = hu_ring_h(rk);
    size = size * smoothstep(-1.0, 3.0, yr) * (1.0 - smoothstep(0.72 * hk, hk, yr));
    if (size < 0.12) {
        return;
    }
    let P = C + vec3<f32>(pc.x, y, pc.y);
    // (bounding sphere first)
    let b = dot(P, rd);
    let hs = 0.5 * size;
    let c = dot(P, P) - 0.76 * size * size;
    if (b * b < c || b - 1.0 > (*best).t) {
        return;
    }
    let m = hu_rot(hu_unit(h3), (1.5 + 3.0 * f32(h3 >> 22u) / 1023.0) * t + f32(h3 & 63u));
    let o = m * (-P);
    let d = m * rd;
    let inv = 1.0 / select(d, vec3<f32>(1.0e-6), abs(d) < vec3<f32>(1.0e-6));
    let t0 = (vec3<f32>(-hs) - o) * inv;
    let t1 = (vec3<f32>(hs) - o) * inv;
    let tn = min(t0, t1);
    let tf = max(t0, t1);
    let near = max(max(tn.x, tn.y), tn.z);
    let far = min(min(tf.x, tf.y), tf.z);
    // (none closer than a block or two to the eye: one going past it would fill the picture)
    if (near > far || far < 0.0 || near >= (*best).t || near < 1.5) {
        return;
    }
    var nl = vec3<f32>(0.0);
    if (near == tn.x) {
        nl.x = -sign(d.x);
    } else if (near == tn.y) {
        nl.y = -sign(d.y);
    } else {
        nl.z = -sign(d.z);
    }
    (*best).t = near;
    (*best).n = transpose(m) * nl;
    // (which block it is, which face of it, and where on that face)
    (*best).bk = hu_u(HU_PAL + u32(k) * HU_PN + ((h3 >> 8u) % HU_PN));
    (*best).face = hu_face_of(nl);
    let pl = (o + d * near) / size + 0.5;
    (*best).uv = select(select(pl.xy, pl.xz, abs(nl.y) > 0.5), pl.zy, abs(nl.x) > 0.5);
    (*best).shade = 0.85 + 0.3 * f32((h3 >> 4u) & 15u) / 15.0;
    (*best).id = hu_pack(k, iu, iv);
}

// The blocks along ray rd up to `t_max`: marched through the rings' cells, nearest first; each cell's block (if any)
// tried once.
fn hu_debris(rd: vec3<f32>, C: vec3<f32>, t_max: f32, t: f32, St: f32, Sf: f32, seed: u32, steps: i32, best: ptr<function, HuHit>) {
    let fl = hu_flung(t);
    if (hu_ring_on(HU_R_W, t) + hu_ring_on(140.0, t) < 0.001) {
        return;
    }
    let o = -C;
    let ro = HU_RING0 + f32(HU_NR) * HU_RING_W + fl.x + 1.5;
    let ri = HU_RING0 + fl.x - 1.5;
    // (the rings' cylinder, and the heights its blocks reach)
    let qa = dot(rd.xz, rd.xz);
    let qb = dot(o.xz, rd.xz);
    let qc = dot(o.xz, o.xz) - ro * ro;
    let disc = qb * qb - qa * qc;
    if (disc <= 0.0 || qa < 1.0e-8) {
        return;
    }
    let sq = sqrt(disc);
    var t0 = max((-qb - sq) / qa, 0.0);
    var t1 = min((-qb + sq) / qa, t_max);
    let ylo = -60.0 + min(fl.y, 0.0);
    let yhi = 262.0 + max(fl.y, 0.0);
    if (abs(rd.y) > 1.0e-5) {
        let ta = (ylo - o.y) / rd.y;
        let tb = (yhi - o.y) / rd.y;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    }
    if (t1 <= t0) {
        return;
    }
    // (the eye's: the march leaps over it)
    let qci = dot(o.xz, o.xz) - ri * ri;
    let disci = qb * qb - qa * qci;
    var ti0 = 1.0e9;
    var ti1 = -1.0e9;
    if (disci > 0.0) {
        let s2 = sqrt(disci);
        ti0 = (-qb - s2) / qa;
        ti1 = (-qb + s2) / qa;
    }
    var tt = t0;
    var last = vec3<i32>(-99);
    var stop = 1.0e9;
    for (var i = 0; i < steps; i = i + 1) {
        if (tt > t1 || tt > stop) {
            break;
        }
        if (tt > ti0 && tt < ti1) {
            tt = ti1 + 0.01;
            continue;
        }
        let q = o + rd * tt;
        let r = length(q.xz);
        let dt = clamp(0.7 + 0.0045 * tt, 0.75, 2.4);
        let k = i32(floor((r - fl.x - HU_RING0) / HU_RING_W));
        if (k < 0 || k >= HU_NR) {
            tt = tt + dt;
            continue;
        }
        let rk = hu_ring_r(k);
        // (above where this ring's blocks go: on quickly)
        if (q.y > hu_ring_h(rk) + 30.0 + max(fl.y, 0.0)) {
            tt = tt + max(dt, 4.0);
            continue;
        }
        let nu = floor(TAU * rk / HU_CELL);
        let ph = HU_SPIN * hu_omega(rk) * St;
        let iu = i32(floor(fract((atan2(q.z, q.x) - ph) / TAU) * nu));
        let iv = i32(floor((q.y - hu_ring_rise(rk) * Sf - fl.y) / HU_CELL));
        let cell = vec3<i32>(k, iu, iv);
        if (any(cell != last)) {
            last = cell;
            let before = (*best).t;
            hu_block(rd, C, k, iu, iv, t, St, Sf, seed, best);
            if ((*best).t < before) {
                stop = (*best).t + 2.5;
            }
        }
        tt = tt + dt;
    }
}

// ---- the trees, whole -------------------------------------------------------------------------------------------------
// Tree i's middle at `t` (off the target's middle, as hurricane.rs's tree_at), its turn, and whether it is up.
struct HuTree {
    p: vec3<f32>,
    m: mat3x3<f32>,
    cm: f32,
    up: bool,
}
fn hu_tree_lifted(base: u32, i: u32, t: f32, St: f32, seed: u32) -> vec3<f32> {
    let x0 = hu_w(base);
    let z0 = hu_w(base + 1u);
    let gdy = hu_w(base + 2u);
    let t_up = hu_w(base + 3u);
    let s_up = hu_w(base + 7u);
    let trunk = f32(hu_u(base + 4u) & 31u);
    let r_orb = 70.0 + 50.0 * mh(i, seed, 0xa1u);
    let y_orb = 25.0 + 115.0 * pow(mh(i, seed, 0xa2u), 1.4);
    let tau = max(t - t_up, 0.0);
    let r0 = length(vec2<f32>(x0, z0));
    let a0 = atan2(z0, x0);
    let r = r_orb + (r0 - r_orb) * exp(-tau / 5.0);
    let ly = 1.0 - exp(-max(tau - 0.5, 0.0) / 3.5);
    let cm = 0.6 * max(trunk, 3.0);
    let y = gdy + cm + (y_orb - gdy) * ly;
    let a = a0 + HU_SPIN * hu_omega(r) * (St - s_up);
    return vec3<f32>(r * cos(a), y, r * sin(a));
}
fn hu_tree_at(i: u32, t: f32, St: f32, seed: u32) -> HuTree {
    var o: HuTree;
    let base = HU_T + i * HU_TW;
    let t_up = hu_w(base + 3u);
    o.cm = 0.6 * max(f32(hu_u(base + 4u) & 31u), 3.0);
    o.up = t >= t_up;
    if (!o.up) {
        return o;
    }
    if (t <= HU_FLING || t_up >= HU_FLING) {
        o.p = hu_tree_lifted(base, i, t, St, seed);
    } else {
        let pf = hu_tree_lifted(base, i, HU_FLING, hu_spin_int(HU_FLING), seed);
        let rf = max(length(pf.xz), 1.0);
        let ov = pf.xz / rf;
        let tv = vec2<f32>(-ov.y, ov.x) * HU_SPIN;
        let vt = hu_omega(rf) * rf * hu_spin(HU_FLING) * 0.6;
        let vo = 6.0 + 6.0 * mh(i, seed, 0xa3u);
        let vu = 3.0 + 4.0 * mh(i, seed, 0xa4u);
        let s = t - HU_FLING;
        let v = tv * vt + ov * vo;
        o.p = vec3<f32>(pf.x + v.x * s, pf.y + vu * s - 7.0 * s * s, pf.z + v.y * s);
        o.up = o.p.y > hu_ground(o.p.xz) + 1.0;
    }
    // (it rocks over on its roots the way the wind blows, then tumbles end over end as it goes)
    let tau = max(t - t_up, 0.0);
    let x0 = hu_w(base);
    let z0 = hu_w(base + 1u);
    let a0 = atan2(z0, x0);
    let h = pcg(i * 0x2545F491u ^ seed);
    let ax = normalize(vec3<f32>(cos(a0), 0.0, sin(a0)) + 0.7 * hu_unit(h));
    let rate = 0.6 + 1.4 * f32(h >> 22u) / 1023.0;
    let ang = 1.1 * smoothstep(0.0, 1.0, tau) + rate * (tau - 1.2 * (1.0 - exp(-tau / 1.2)));
    o.m = hu_rot(ax, ang * HU_SPIN);
    return o;
}
// What tree `base`'s cell (i, y, j) of its 7 by 7 columns holds: 0 nothing, 1 its trunk, 2 leaves.
fn hu_tree_cell(base: u32, i: i32, y: i32, j: i32, trunk: i32) -> u32 {
    if (i < 0 || i > 6 || j < 0 || j > 6 || y < 0) {
        return 0u;
    }
    if (i == 3 && j == 3 && y < trunk) {
        return 1u;
    }
    let c = u32(j * 7 + i);
    let v = (hu_u(base + 8u + c / 3u) >> (10u * (c % 3u))) & 1023u;
    let lo = i32(v & 31u);
    let hi = i32(v >> 5u);
    if (hi >= lo && y + 1 >= lo && y + 1 <= hi) {
        return 2u;
    }
    return 0u;
}
fn hu_trees(rd: vec3<f32>, C: vec3<f32>, t: f32, St: f32, seed: u32, only: i32, best: ptr<function, HuHit>) {
    if (!hu_have()) {
        return;
    }
    let n = min(u32(hu_w(0u) + 0.5), HU_NT);
    var i0 = 0u;
    var i1 = n;
    if (only >= 0) {
        i0 = u32(only);
        i1 = min(i0 + 1u, n);
    }
    for (var i = i0; i < i1; i = i + 1u) {
        let base = HU_T + i * HU_TW;
        if (t < hu_w(base + 3u)) {
            continue;
        }
        let tr = hu_tree_at(i, t, St, seed);
        if (!tr.up) {
            continue;
        }
        let shape = hu_u(base + 4u);
        let trunk = i32(shape & 31u);
        let hm = f32((shape >> 5u) & 31u) + 1.0;
        let P = C + tr.p;
        let rad = 0.5 * sqrt(98.0 + hm * hm) + 0.8 + abs(tr.cm - 0.5 * hm);
        let b = dot(P, rd);
        let c = dot(P, P) - rad * rad;
        if (b * b < c || b - rad > (*best).t) {
            continue;
        }
        // (the ray in the tree's own frame: its trunk's foot at 0, its middle at cm)
        let o = tr.m * (-P) + vec3<f32>(0.0, tr.cm, 0.0);
        let d = tr.m * rd;
        let inv = 1.0 / select(d, vec3<f32>(1.0e-6), abs(d) < vec3<f32>(1.0e-6));
        let lo = vec3<f32>(-3.5, 0.0, -3.5);
        let hi = vec3<f32>(3.5, hm, 3.5);
        let ta = (lo - o) * inv;
        let tb = (hi - o) * inv;
        let near = max(max(min(ta.x, tb.x), min(ta.y, tb.y)), min(ta.z, tb.z));
        let far = min(min(max(ta.x, tb.x), max(ta.y, tb.y)), max(ta.z, tb.z));
        if (near > far || far < 0.0 || near > (*best).t || length(P) < 6.0) {
            continue;
        }
        // (through its blocks, a cell at a time)
        let ts = max(near, 0.0) + 1.0e-3;
        let p0 = o + d * ts + vec3<f32>(3.5, 0.0, 3.5);
        var cell = vec3<i32>(floor(p0));
        let stp = vec3<i32>(sign(d));
        let tdel = abs(inv);
        var tmx = (vec3<f32>(cell) + max(sign(d), vec3<f32>(0.0)) - p0) * inv + vec3<f32>(ts);
        var axis = select(select(2, 1, near == min(ta.y, tb.y)), 0, near == min(ta.x, tb.x));
        for (var s = 0; s < 44; s = s + 1) {
            let what = hu_tree_cell(base, cell.x, cell.y, cell.z, trunk);
            if (what > 0u) {
                let th = select(ts, select(select(tmx.z - tdel.z, tmx.y - tdel.y, axis == 1), tmx.x - tdel.x, axis == 0), s > 0);
                if (th < (*best).t) {
                    var nl = vec3<f32>(0.0);
                    if (axis == 0) {
                        nl.x = -sign(d.x);
                    } else if (axis == 1) {
                        nl.y = -sign(d.y);
                    } else {
                        nl.z = -sign(d.z);
                    }
                    (*best).t = th;
                    (*best).n = transpose(tr.m) * nl;
                    let kinds = hu_u(base + 5u);
                    (*best).face = hu_face_of(nl);
                    let pl = fract(o + d * th + vec3<f32>(3.5, 0.0, 3.5));
                    (*best).uv = select(select(pl.xy, pl.xz, axis == 1), pl.zy, axis == 0);
                    if (what == 1u) {
                        (*best).bk = kinds & 0xFFFFu;
                        (*best).shade = 1.0;
                    } else {
                        (*best).bk = kinds >> 16u;
                        let hh = pcg(u32(cell.x + 7 * cell.z) ^ pcg(u32(cell.y) ^ i));
                        (*best).shade = 0.7 + 0.5 * f32(hh & 255u) / 255.0;
                    }
                    (*best).id = vec2<f32>(-1.0 - f32(i), 0.0);
                }
                break;
            }
            if (tmx.x < tmx.y && tmx.x < tmx.z) {
                cell.x = cell.x + stp.x;
                tmx.x = tmx.x + tdel.x;
                axis = 0;
            } else if (tmx.y < tmx.z) {
                cell.y = cell.y + stp.y;
                tmx.y = tmx.y + tdel.y;
                axis = 1;
            } else {
                cell.z = cell.z + stp.z;
                tmx.z = tmx.z + tdel.z;
                axis = 2;
            }
            if (cell.x < -1 || cell.x > 7 || cell.z < -1 || cell.z > 7 || cell.y < -1 || f32(cell.y) > hm + 1.0) {
                break;
            }
        }
    }
}

// ---- the cloud, the rain and the dust -----------------------------------------------------------------------------------
fn hu_over(h: ptr<function, vec4<f32>>, c: vec3<f32>, x: f32) {
    *h = vec4<f32>((*h).rgb * (1.0 - x) + c * x, (*h).a * (1.0 - x));
}
// The eyewall's inner face at height y over the land (the stadium: wider as it rises), and its outer edge.
fn hu_wall_in(y: f32) -> f32 {
    return HU_R_EYE + 6.0 + 0.22 * max(y, 0.0);
}
fn hu_wall_out(y: f32) -> f32 {
    return hu_wall_in(y) + 50.0 + 0.12 * max(y, 0.0);
}
// The cloud's turn by `t` at r: the rain bands go round all of a piece (a sweep you can see), the cloud close round
// the eye faster with the wind, drawn out into streaks.
fn hu_cloud_turn(r: f32, St: f32) -> f32 {
    return HU_SPIN * (0.11 + 0.45 * hu_omega(max(r, 25.0)) * (1.0 - smoothstep(110.0, 260.0, r))) * St;
}
// The spiral arms' strength at (r, a) in the cloud's turning frame: four bands wound in towards the eye.
fn hu_arms(r: f32, a: f32) -> f32 {
    return 0.5 + 0.5 * cos(4.0 * a + 4.6 * log(max(r, 40.0) / 70.0));
}
// The cloud's density at q (off the middle's ground): x its density, y how much of it is the eyewall (its foot dark,
// its top sunlit), z the arms' strength there (dark rain cores in them).
fn hu_den(q: vec3<f32>, t: f32, St: f32, fine: bool) -> vec3<f32> {
    let r = length(q.xz);
    let form = hu_form(t);
    let fade = hu_fade(t);
    let eye = hu_eye(t);
    let p2 = rot2(q.xz, -hu_cloud_turn(r, St));
    let a = atan2(p2.y, p2.x);
    // ---- the eyewall: a towering ring of cloud from low over the land up to HU_WALL_TOP, sloping out as it rises, in
    // tall towers, wound with striations that spiral up it the way it turns
    let win = hu_wall_in(q.y);
    let wout = hu_wall_out(q.y);
    let wk = eye * smoothstep(5.0, 13.0, t);
    let wtop = HU_WALL_TOP - 50.0 * (1.0 - smoothstep(6.0, 18.0, t));
    var wall = min(min((r - win) / 6.0, (wout - r) / 14.0), min((q.y - 10.0) / 6.0, (wtop - q.y) / 18.0));
    let stri = 0.5 + 0.5 * sin(a * 9.0 + q.y * 0.045 * HU_SPIN + 2.0 * gnoise3(vec3<f32>(p2.x * 0.03, q.y * 0.01, p2.y * 0.03)));
    let tow = gnoise3(vec3<f32>(p2.x * (1.0 / 24.0), q.y * (1.0 / 80.0), p2.y * (1.0 / 24.0)));
    wall = (wall + 1.5 * (tow - 0.5) + 0.9 * (stri - 0.5)) * wk;
    // ---- the rain bands: spiral arms from the eyewall out, broken by clear gaps, their bases low
    let arm = hu_arms(r, a);
    let reach = hu_deck_r(t);
    let ab = HU_BASE - 15.0 + 25.0 * smoothstep(150.0, 900.0, r) + 18.0 * (1.0 - form);
    let at = 190.0 - 40.0 * smoothstep(300.0, 900.0, r);
    let inner = smoothstep(wout - 10.0, wout + 50.0, r);
    // (the arms a mask: open sky between them, so the eyewall shows through from the land round it)
    let am = (arm - 0.5 + 0.3 * (1.0 - smoothstep(140.0, 320.0, r))) * 4.5;
    let bands = min(min(min(q.y - ab, at - q.y) / 14.0, (reach - r) / 120.0), am) - 2.5 * (1.0 - inner);
    // ---- over it all, high, the outflow: a thin shield spreading from the eyewall's top, its edge feathered by the arms
    let shield = min(min(q.y - (HU_WALL_TOP - 30.0), HU_WALL_TOP + 15.0 - q.y) / 8.0, (190.0 + 90.0 * arm - r) / 60.0) - 1.4 - 1.0 * (1.0 - smoothstep(win, wout, r)) * eye;
    let body = max(max(wall, bands * form), shield * smoothstep(8.0, 20.0, t));
    let s = select(1.0 / 46.0, 1.0 / 34.0, fine);
    var nz = gnoise3(vec3<f32>(p2.x * s, q.y * s * 1.6 + t * 0.03, p2.y * s));
    if (fine) {
        nz = 0.65 * nz + 0.35 * gnoise3(vec3<f32>(p2.x, q.y * 1.5, p2.y) * (1.0 / 12.0) + vec3<f32>(3.1, 0.0, 7.7));
    }
    let d = body + (nz - 0.52) * 2.2 - 1.8 * (1.0 - form) - 7.0 * pow(1.0 - fade, 1.4);
    return vec3<f32>(saturate(d), saturate(wall * 0.6 + 0.3) * step(max(bands, shield), wall), smoothstep(0.55, 0.95, arm) * inner);
}

// The dust, spray and fine debris churned up round the eyewall, at q: x the dust (thick at the eyewall's foot, in
// streaks), y the haze of debris too small to see one by one, filling the rings as high as their blocks go.
fn hu_dust(q: vec3<f32>, t: f32, St: f32, g: f32) -> vec2<f32> {
    let r = length(q.xz);
    let on = hu_ring_on(clamp(r, HU_R_IN, 160.0), t);
    if (on < 0.01) {
        return vec2<f32>(0.0);
    }
    let yr = q.y - g;
    let p2 = rot2(q.xz, -HU_SPIN * hu_omega(max(r, 30.0)) * St * 0.9);
    let n = gnoise3(vec3<f32>(p2.x * (1.0 / 16.0), yr * (1.0 / 11.0) - t * 0.5, p2.y * (1.0 / 16.0)));
    let hgt = 8.0 + 34.0 * (1.0 - smoothstep(70.0, 190.0, r));
    let foot = smoothstep(HU_R_IN - 2.0, HU_R_IN + 12.0, r) * (1.0 - smoothstep(110.0, 200.0, r)) * (1.0 - smoothstep(0.25 * hgt, hgt, yr)) * smoothstep(-3.0, 1.0, yr);
    let dust = on * hu_spin(t) * foot * smoothstep(0.45, 0.8, n) * (0.4 + 1.4 * hu_shape(r));
    let rh = hu_ring_h(r);
    let haze = on * smoothstep(HU_RING0, HU_RING0 + 8.0, r) * (1.0 - smoothstep(150.0, 165.0, r)) * smoothstep(-2.0, 2.0, yr) * (1.0 - smoothstep(0.6 * rh, rh, yr)) * hu_ring_dens(r) * (0.6 + 0.8 * n);
    return vec2<f32>(dust, haze);
}

struct HuVol {
    c: vec4<f32>,
    t: f32,
}
// The cloud, the rain and the dust along rd (camera-relative), as far as `len` (the land, or a block in front of it).
fn hu_volume(rd: vec3<f32>, len: f32, C: vec3<f32>, t: f32, St: f32, j: f32, L: vec3<f32>, amb: vec3<f32>, sunc: vec3<f32>, fine: bool) -> HuVol {
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var tmid = 0.0;
    var wmid = 0.0;
    let o = -C;
    let form = hu_form(t);
    let fade = hu_fade(t);
    let qa = dot(rd.xz, rd.xz);
    let qb = dot(o.xz, rd.xz);
    // ---- the cloud: between the eyewall's foot and the deck's top, inside its reach --------------------------------
    let reach = hu_deck_r(t) + 30.0;
    var t0 = 0.0;
    var t1 = len;
    let ylo = 8.0;
    let yhi = HU_WALL_TOP + 30.0;
    if (abs(rd.y) > 1.0e-5) {
        let ta = (ylo - o.y) / rd.y;
        let tb = (yhi - o.y) / rd.y;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    } else if (o.y < ylo || o.y > yhi) {
        t1 = -1.0;
    }
    let qc = dot(o.xz, o.xz) - reach * reach;
    let disc = qb * qb - qa * qc;
    if (disc <= 0.0 || qa < 1.0e-8) {
        if (qc > 0.0) {
            t1 = -1.0;
        }
    } else {
        let sq = sqrt(disc);
        t0 = max(t0, (-qb - sq) / qa);
        t1 = min(t1, (-qb + sq) / qa);
    }
    if (t1 > t0 && form * fade > 0.001) {
        let n = select(34, 52, fine);
        let span = t1 - t0;
        let dt0 = clamp(span / f32(n), 3.0, 14.0);
        var dt = dt0;
        var tt = t0 + dt * j;
        for (var i = 0; i < 90; i = i + 1) {
            if (tt > t1 || acc.a < 0.03) {
                break;
            }
            let q = o + rd * tt;
            let dn = hu_den(q, t, St, fine);
            if (dn.x > 0.004) {
                let r = length(q.xz);
                // (lit from above: sunlit on the eyewall's top and the shield, dark in its depths and under the bands;
                // the eyewall's inner face lit down the clear eye; its foot near black with the rain wrapped round it)
                let h01 = saturate((q.y - 15.0) / (HU_WALL_TOP - 15.0));
                var sun_t = exp(-min(max(HU_WALL_TOP - q.y, 0.0), 160.0) * 0.016) * mix(1.0, 0.75, dn.z);
                let face = (1.0 - smoothstep(hu_wall_in(q.y) - 2.0, hu_wall_in(q.y) + 12.0, r)) * hu_eye(t) * smoothstep(0.0, 0.3, L.y);
                sun_t = max(sun_t, face * (0.45 + 0.55 * h01));
                // (and the side of the eyewall towards the sun lit, the far side in its own shadow: its roundness)
                let side = 0.6 + 0.4 * dot(normalize(vec3<f32>(q.x, 0.0, q.z) + vec3<f32>(1.0e-3, 0.0, 0.0)), normalize(vec3<f32>(L.x, 0.0, L.z) + vec3<f32>(1.0e-3, 0.0, 0.0)));
                sun_t = sun_t * mix(1.0, side, dn.y);
                let foot = mix(vec3<f32>(0.2, 0.21, 0.23), vec3<f32>(0.05, 0.055, 0.06), max(dn.y, dn.z));
                // (the eyewall pale from a little way up its flanks, a towering sunlit wall over the bands' dark undersides)
                let pale = mix(smoothstep(0.05, 0.75, h01), smoothstep(-0.05, 0.4, h01), dn.y);
                let alb = mix(foot, vec3<f32>(0.78, 0.79, 0.82), pale);
                let c = alb * (amb * (0.45 + 0.6 * h01) * (2.0 - fade) + sunc * mix(0.7, sun_t, fade) * 1.05);
                let ext = dn.x * 0.06 * dt * (0.4 + 0.6 * fade);
                let al = 1.0 - exp(-ext);
                hu_over(&acc, c, al);
                tmid = tmid + acc.a * al * tt;
                wmid = wmid + acc.a * al;
                dt = dt0 * (0.8 + 0.4 * fract(j + f32(i) * 0.618));
            } else {
                dt = dt0 * select(1.0, 2.2, dn.x < 0.0001 && i > 2);
            }
            tt = tt + dt;
        }
    }
    // ---- the rain: grey veils falling out of the bands, driven slanting round by the wind, and the murk under it ----
    let rk = hu_rain(t) * fade;
    if (rk > 0.001) {
        let rr = hu_deck_r(t) * 0.8;
        var r0 = 0.0;
        var r1 = len;
        if (abs(rd.y) > 1.0e-5) {
            let ta = (-8.0 - o.y) / rd.y;
            let tb = (HU_BASE + 20.0 - o.y) / rd.y;
            r0 = max(r0, min(ta, tb));
            r1 = min(r1, max(ta, tb));
        }
        let qc2 = dot(o.xz, o.xz) - rr * rr;
        let disc2 = qb * qb - qa * qc2;
        if (disc2 > 0.0 && qa > 1.0e-8) {
            let sq = sqrt(disc2);
            r0 = max(r0, (-qb - sq) / qa);
            r1 = min(r1, (-qb + sq) / qa);
        } else if (qc2 > 0.0) {
            r1 = -1.0;
        }
        r1 = min(r1, r0 + 900.0);
        if (r1 > r0) {
            let nr = select(8, 12, fine);
            let dtr = (r1 - r0) / f32(nr);
            var tr = 1.0;
            var cr = vec3<f32>(0.0);
            for (var i = 0; i < nr; i = i + 1) {
                let tt = r0 + (f32(i) + j) * dtr;
                let q = o + rd * tt;
                let r = length(q.xz);
                // (the bands it falls in, the wind driving it round: the curtains lean over and drift with it)
                let p2 = rot2(q.xz, -hu_cloud_turn(r, St) - 0.004 * q.y * HU_SPIN);
                let arm = hu_arms(r, atan2(p2.y, p2.x));
                let curtain = gnoise3(vec3<f32>(p2.x * (1.0 / 30.0), q.y * (1.0 / 120.0), p2.y * (1.0 / 30.0)));
                let fall = gnoise3(vec3<f32>(p2.x * (1.0 / 4.0), (q.y + 40.0 * t) * (1.0 / 26.0), p2.y * (1.0 / 4.0)));
                var den = rk * mix(0.25, 1.0, smoothstep(0.4, 0.8, arm)) * smoothstep(hu_wall_out(q.y) - 20.0, hu_wall_out(q.y) + 30.0, r) * smoothstep(0.38, 0.62, curtain) * (0.55 + 0.9 * smoothstep(0.45, 0.75, fall));
                den = den * (1.0 - smoothstep(rr * 0.75, rr, r)) * smoothstep(HU_R_EYE, HU_R_EYE + 30.0, r) * smoothstep(20.0, 90.0, tt);
                den = den * smoothstep(-6.0, 4.0, q.y) * (1.0 - smoothstep(HU_BASE, HU_BASE + 18.0, q.y));
                if (den > 0.001) {
                    let c = vec3<f32>(0.42, 0.45, 0.48) * (amb * 0.85 + sunc * 0.12);
                    let al = 1.0 - exp(-den * 0.04 * dtr);
                    cr = cr + tr * al * c;
                    tr = tr * (1.0 - al);
                }
            }
            // (the murk of the rain over the whole of the land under the storm: what is far off greys out)
            let murk = exp(-max(r1 - max(r0, 40.0), 0.0) * 0.0018 * rk * form);
            let mc = vec3<f32>(0.4, 0.43, 0.46) * (amb * 0.9 + sunc * 0.1);
            cr = cr + tr * (1.0 - murk) * mc;
            tr = tr * murk;
            // (under the cloud: in front of what the cloud gathered for an eye under it, never hiding all behind it)
            let keep = max(tr, 0.3);
            cr = cr * (1.0 - keep) / max(1.0 - tr, 1.0e-4);
            acc = vec4<f32>(cr + keep * acc.rgb, keep * acc.a);
            if (tr < 0.98 && wmid < 1.0e-3) {
                tmid = 0.5 * (r0 + r1);
                wmid = 1.0;
            }
        }
    }
    // ---- the dust and the spray round the eyewall's foot, churning round with the debris -------------------------------
    if (hu_ring_on(HU_R_W, t) > 0.01) {
        let rd0 = 230.0;
        let qc3 = dot(o.xz, o.xz) - rd0 * rd0;
        let disc3 = qb * qb - qa * qc3;
        if (disc3 > 0.0 && qa > 1.0e-8) {
            let sq = sqrt(disc3);
            var d0 = max((-qb - sq) / qa, 0.0);
            var d1 = min((-qb + sq) / qa, len);
            if (abs(rd.y) > 1.0e-5) {
                let ta = (-50.0 - o.y) / rd.y;
                let tb = (250.0 - o.y) / rd.y;
                d0 = max(d0, min(ta, tb));
                d1 = min(d1, max(ta, tb));
            }
            if (d1 > d0) {
                let nd = select(16, 24, fine);
                let ddt = (d1 - d0) / f32(nd);
                var da = vec4<f32>(0.0, 0.0, 0.0, 1.0);
                var dtm = 0.0;
                let g = hu_ground(vec2<f32>(0.0));
                for (var i = 0; i < nd; i = i + 1) {
                    let tt = d0 + (f32(i) + j) * ddt;
                    let q = o + rd * tt;
                    let dd = hu_dust(q, t, St, g) * smoothstep(8.0, 50.0, tt);
                    if (dd.x + dd.y > 0.002) {
                        let c = (vec3<f32>(0.3, 0.26, 0.21) * dd.x + vec3<f32>(0.12, 0.1, 0.085) * dd.y) / (dd.x + dd.y) * (amb * 1.2 + sunc * 0.25);
                        let al = 1.0 - exp(-(dd.x * 0.05 + dd.y * 0.014) * ddt);
                        dtm = dtm + tt * al * da.a;
                        hu_over(&da, c, al);
                        if (da.a < 0.05) {
                            break;
                        }
                    }
                }
                // (in front of the cloud if nearer than what the cloud gathered, else behind it: under the deck, its top
                // lost in the cloud)
                if (da.a < 0.999) {
                    let dmid = dtm / max(1.0 - da.a, 1.0e-3);
                    let cmid = tmid / max(wmid, 1.0e-4);
                    if (wmid < 1.0e-3 || dmid < cmid) {
                        acc = vec4<f32>(da.rgb + da.a * acc.rgb, da.a * acc.a);
                    } else {
                        acc = vec4<f32>(acc.rgb + acc.a * da.rgb, da.a * acc.a);
                    }
                }
            }
        }
    }
    var v: HuVol;
    v.c = acc;
    v.t = select(1.0e9, tmid / max(wmid, 1.0e-4), wmid > 1.0e-4);
    return v;
}

struct PlOut {
    c: vec4<f32>,
    e: vec4<f32>,
}

// A block or tree hit, lit: the storm's grey daylight on it, its own colour.
fn hu_lit(h: HuHit, L: vec3<f32>, amb: vec3<f32>, sunc: vec3<f32>, under: f32) -> vec3<f32> {
    // (the mip level a block's sixteen texels are seen at, this far off)
    let px = 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    let lod = log2(max(h.t * px * 16.0, 1.0e-4));
    let alb = hu_face(h.bk, h.face, h.uv, lod) * h.shade;
    let n = h.n;
    let dif = max(dot(n, L), 0.0) * mix(1.0, 0.25, under);
    return alb * (amb * (1.5 + 0.6 * n.y) + sunc * dif * 0.9 + vec3<f32>(0.012));
}

// The pass, in one of three stages: 0 the whole of it at full size (fs_main); 1 the half-size stage (fs_half: the
// cloud, the rain, the dust and which block or tree each two by two of the picture's pixels sees), as premultiplied
// colour and transmittance with what it saw; 2 the join (fs_join: the blocks and the trees the half-size stage found
// round this pixel tried again sharp, then the rest, with the half-size stage's cloud laid over).
fn hurricane(in: StageIn, stage: u32, up: vec4<f32>, ids0: array<vec2<f32>, 4>) -> PlOut {
    var ids = ids0;
    var uv = in.uv;
    let time = now();
    let k = intensity_v();
    let seed = u32(seed_v());
    let anc = anchor_xz();
    let cam = frame.camera_position.xyz;
    let gy = block_y() + 1.0 + select(0.0, hu_w(1u), hu_have());
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    var d = 0.0;
    if (stage == 1u) {
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
        let d0 = textureLoad(scene_depth, q, 0);
        let d1 = textureLoad(scene_depth, vec2<i32>(q1.x, q.y), 0);
        let d2 = textureLoad(scene_depth, vec2<i32>(q.x, q1.y), 0);
        let d3 = textureLoad(scene_depth, q1, 0);
        let hq = vec2<i32>(floor(in.position.xy));
        d = select(min(min(d0, d1), min(d2, d3)), max(max(d0, d1), max(d2, d3)), ((hq.x + hq.y) & 1) == 0);
        uv = (vec2<f32>(q) + 1.0) * frame.resolution.zw;
    } else {
        d = depth_at(uv);
    }
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let form = hu_form(time) * hu_fade(time);
    let St = hu_spin_int(time);
    let Sf = hu_spin_int(min(time, HU_FLING));

    // (the light, matched to the scene's, dimmed and greyed under the storm)
    let skyl = srgb_to_linear(frame.sky_color.rgb);
    let amb0 = mix(vec3<f32>(0.02, 0.025, 0.035), skyl * 0.55 + vec3<f32>(0.03), day);
    let amb = amb0 * mix(1.0, 0.6, form);
    let sunc = (mix(vec3<f32>(1.25, 1.18, 1.05), vec3<f32>(1.4, 0.62, 0.3), warm) * sun_up + vec3<f32>(0.05, 0.07, 0.11) * moon) * mix(1.0, 0.55, form);

    // ---- what it carries: the blocks round the eyewall and the trees, nearest first ---------------------------------
    var hit = hu_none();
    if (time < HU_LEN && hu_have()) {
        if (stage == 2u) {
            // (the ones the half-size stage saw round this pixel, tried again sharp)
            for (var n = 0; n < 4; n = n + 1) {
                let id = ids[n];
                if (id.x <= -2047.0) {
                    continue;
                }
                if (id.x < 0.0) {
                    hu_trees(rd, C, time, St, seed, i32(-id.x - 0.5), &hit);
                } else {
                    let c = hu_unpack(id);
                    hu_block(rd, C, c.x, c.y, c.z, time, St, Sf, seed, &hit);
                }
            }
        } else {
            hu_debris(rd, C, min(scene_len, 2500.0), time, St, Sf, seed, select(240, 170, stage == 1u), &hit);
            hu_trees(rd, C, time, St, seed, -1, &hit);
        }
    }
    let hit_len = min(scene_len, hit.t);

    // ---- the land under the storm: darker, greyer, wet ------------------------------------------------------------------
    if (stage != 1u) {
        if (!sky) {
            let rr = length((rel - C).xz);
            let cover = form * (1.0 - smoothstep(hu_deck_r(time) * 0.8, hu_deck_r(time) * 1.05, rr));
            let wet = hu_rain(time) * hu_fade(time) * (1.0 - smoothstep(hu_deck_r(time) * 0.6, hu_deck_r(time) * 0.85, rr));
            let shade = form * (1.0 - smoothstep(hu_deck_r(time), hu_deck_r(time) * 1.8, rr));
            // (the eye's land lit, the sun down through it)
            let eye = hu_eye(time) * (1.0 - smoothstep(HU_R_EYE - 4.0, HU_R_EYE + 14.0, rr));
            col = col * (1.0 - 0.28 * form - 0.4 * cover * (1.0 - 0.7 * eye)) * (1.0 - 0.25 * shade * (1.0 - cover)) * mix(vec3<f32>(1.0), vec3<f32>(0.86, 0.9, 0.94), wet);
        } else {
            let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
            col = mix(col, vec3<f32>(lum) * vec3<f32>(0.93, 0.97, 1.0), 0.65 * form) * (1.0 - 0.55 * form);
        }
        if (hit.t < scene_len) {
            let under = form * (1.0 - hu_eye(time) * 0.6);
            col = hu_lit(hit, L, amb, sunc, under);
        }
    }

    // ---- the cloud, the rain and the dust -----------------------------------------------------------------------------
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    } else if (time < HU_LEN) {
        let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
        let v = hu_volume(rd, hit_len, C, time, St, j, L, amb, sunc, stage == 0u);
        if (stage == 0u) {
            col = col * mix(1.0, v.c.a, k) + v.c.rgb * k;
        } else {
            return PlOut(vec4<f32>(v.c.rgb * k, mix(1.0, v.c.a, k)), vec4<f32>(min(hit_len, 6.0e4), select(1.0e9, v.t, v.t < 1.0e8), hit.id.x, hit.id.y));
        }
    }

    // ---- the rain close by, driven slanting by the wind, thicker the stronger it blows --------------------------------
    let rk = hu_rain(time) * hu_fade(time);
    if (rk > 0.01) {
        let res = frame.resolution.xy;
        let sc = res.y / 1080.0;
        let near = 1.0 - smoothstep(hu_deck_r(time) * 0.6, hu_deck_r(time) * 0.8, length((-C).xz));
        let wind = hu_spin(time);
        var streak = 0.0;
        for (var layer = 0; layer < 3; layer = layer + 1) {
            let fl2 = f32(layer);
            let dk = 3.5 + 5.0 * fl2 + 4.0 * fl2 * fl2;
            if (scene_len < dk || hit.t < dk) {
                continue;
            }
            let wp = rd * dk - C;
            if (wp.y > HU_BASE) {
                continue;
            }
            let w = (10.0 - 3.0 * fl2) * sc;
            let slant = 0.2 + 1.1 * wind;
            let pp = in.position.xy + vec2<f32>(in.position.y * slant, 0.0);
            let cidx = floor(pp.x / w);
            let h = fh21(vec2<f32>(cidx, fl2 * 17.0));
            let h2 = fh21(vec2<f32>(cidx * 1.7, fl2 * 5.0 + 3.0));
            let ln = (240.0 - 50.0 * fl2) * sc;
            let vv = fract((pp.y - time * (2600.0 + 1800.0 * wind - 600.0 * fl2) * sc) / ln + h);
            let across = 1.0 - abs(fract(pp.x / w) - 0.5) * 2.0;
            streak = streak + smoothstep(0.88, 1.0, vv) * step(0.66 - 0.2 * wind, h2) * pow(across, 9.0) * (0.5 - 0.12 * fl2);
        }
        col = col + vec3<f32>(0.6, 0.64, 0.7) * streak * rk * near * (amb0 * 0.8 + vec3<f32>(0.03)) * k;
    }

    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return PlOut(vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0), vec4<f32>(0.0));
    }
    return PlOut(vec4<f32>(srgb, 1.0), vec4<f32>(0.0));
}

fn hu_no_ids() -> array<vec2<f32>, 4> {
    return array<vec2<f32>, 4>(vec2<f32>(-2048.0), vec2<f32>(-2048.0), vec2<f32>(-2048.0), vec2<f32>(-2048.0));
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return hurricane(in, 0u, vec4<f32>(0.0), hu_no_ids()).c;
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): the cloud, the rain and the dust drawn at half the width and
// height by fs_half, which also finds the block or tree each of its pixels sees; fs_join lays the cloud over the
// full-size picture and draws the blocks and trees its four nearest found sharp, at full size. A game without the
// stages compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct PlHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> PlHalf {
    let o = hurricane(in, 1u, vec4<f32>(0.0), hu_no_ids());
    return PlHalf(o.c, o.e);
}
@fragment
fn fs_join(in: StageIn) -> @location(0) vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(in.position.xy) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    var ids = hu_no_ids();
    for (var n = 0; n < 4; n = n + 1) {
        let q = clamp(i0 + vec2<i32>(n & 1, n >> 1u), vec2<i32>(0), hs - vec2<i32>(1));
        ids[n] = textureLoad(half_extra, q, 0).zw;
    }
    // (the cloud upsampled against the depth it was marched to: the land's, or a block's in front of it)
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    for (var n = 0; n < 4; n = n + 1) {
        let o = vec2<i32>(n & 1, n >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        let dz = abs(min(e.x, lp) - lp) / max(lp, 1.0);
        let w = bw * exp(-dz * 24.0);
        acc = acc + c * w;
        sw = sw + w;
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
        }
    }
    let up = select(acc / max(sw, 1.0e-6), near_c, sw < 1.0e-3);
    return hurricane(in, 2u, up, ids).c;
}
// [end half stage]
