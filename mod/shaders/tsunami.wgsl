// Orbital Laser's post pass for the Tsunami (laser 14). Like the Hurricane's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, hash, pcg) less the other lasers' own functions, followed by this file, and
// sets it for a tsunami strike only. Validate with tools/check-shader.sh.

// ---- laser 14: the tsunami ----------------------------------------------------------------------------------------
// No beam. A wave of dark, debris-laden water 130 blocks high and nearly three kilometres wide rises on the horizon and
// crosses the land at about 100 blocks a second: everything in its way is swept up in its foam, it towers over the
// player and washes over them, then drains away leaving mud and wreckage.
// The whole wave is closed-form, a function of where (s, u: along its way and across it) and when, so nothing is kept
// from frame to frame and a strike started part way in lands where it should: the front reaches a point at `ts_arr`,
// the water there rises over `ts_rise`, holds, then drains. strike/tsunami.rs keeps the TS_* and these functions in
// step (the model: the arrival, the envelope, the profile) and hands the pass its table (render.set-data).
const TS_LEN: f32 = 42.0;       // the strike's length (lasers.rs)
const TS_T: f32 = 9.0;          // when the front crosses the target
const TS_V0: f32 = 100.0;       // its speed there, blocks a second, slowing past it
const TS_C: f32 = 1.07e-5;      // (time to s: s / V0 + C s^2)
const TS_SEA: f32 = 100.0;      // the level the wave rises from, under the target's ground
const TS_A: f32 = 230.0;        // how far over that it rises at full strength: 130 over the target's ground
const TS_FACE: f32 = 70.0;      // the face's width, blocks
const TS_HOLD: f32 = 7.5;       // seconds the water holds at its height, then
const TS_DRAIN: f32 = 10.0;     // drains away over
const TS_LEAN: f32 = 0.34;      // seconds the crest leans out over the face (its overhang, about 35 blocks)

fn ts_sq(x: f32) -> f32 { return x * x; }

struct TsG {
    m: vec2<f32>,      // the way it moves (towards the player), on the ground
    n: vec2<f32>,      // across it
    dp: f32,           // how far the player stood from the target as it fired
    send: f32,         // how far past the target it runs before it is spent
    sd: f32,           // the strike's seed
}
fn ts_geo() -> TsG {
    var g: TsG;
    let a = wing_a();
    g.m = vec2<f32>(cos(a), sin(a));
    g.n = vec2<f32>(-g.m.y, g.m.x);
    let me = vec2<f32>(frame.mod_params[3].x, frame.mod_params[3].z) - anchor_xz();
    g.dp = length(me);
    g.send = min(g.dp + 160.0, 720.0);
    g.sd = fract(seed_v() * 0.6180339) * 40.0;
    return g;
}
// How long the front takes to reach distance s past the target.
fn ts_tau(s: f32) -> f32 {
    let sp = max(s, 0.0);
    return s / TS_V0 + TS_C * sp * sp;
}
// The front's speed at s, blocks a second.
fn ts_vel(s: f32) -> f32 {
    return 1.0 / (1.0 / TS_V0 + 2.0 * TS_C * max(s, 0.0));
}
// Where the middle of the front is at `t` (the inverse of ts_tau).
fn ts_front(t: f32) -> f32 {
    let tt = t - TS_T;
    if (tt < 0.0) {
        return tt * TS_V0;
    }
    let b = 1.0 / TS_V0;
    return (-b + sqrt(b * b + 4.0 * TS_C * tt)) / (2.0 * TS_C);
}
// The front's lead or lag along its length (seconds): bowed back at its flanks, in lobes that run ahead along some
// stretches of it.
fn ts_lag(s: f32, u: f32, sd: f32) -> f32 {
    let c = 9.0e-7 * u * u;
    let l1 = (fvnoise(vec2<f32>(u * 0.0042 + sd, s * 0.0014)) - 0.5) * 1.0;
    let l2 = (fvnoise(vec2<f32>(u * 0.017 + 3.1 + sd, s * 0.004 + 9.0)) - 0.5) * 0.22;
    return c + l1 + l2;
}
fn ts_arr(s: f32, u: f32, sd: f32) -> f32 {
    return TS_T + ts_tau(s) + ts_lag(s, u, sd);
}
// How strong the wave is where (s, u): grown over the first thousand blocks (shoaling), weaker as it runs inland, spent
// at its end, weaker towards its flanks, its height lumpy along the front. 1 at full strength.
fn ts_env(s: f32, u: f32, g: TsG) -> f32 {
    let shoal = 0.57 + 0.43 * smoothstep(-1000.0, -400.0, s);
    let dec = 1.0 - 0.45 * smoothstep(0.0, g.send, s);
    let end = 1.0 - smoothstep(g.send - 80.0, g.send + 30.0, s);
    let lat = 1.0 - smoothstep(650.0, 1400.0, abs(u));
    let lump = 1.0 + 0.03 * (fvnoise(vec2<f32>(u * 0.012 + g.sd, s * 0.003)) - 0.5) * 2.0 + 0.035 * (fvnoise(vec2<f32>(u * 0.045, s * 0.01 + 4.0)) - 0.5) * 2.0 + 0.02 * (fvnoise(vec2<f32>(u * 0.2, s * 0.02 + 7.0)) - 0.5) * 2.0;
    return shoal * dec * end * lat * lump;
}
// The water's height over its sea (0 to 1) `tau` seconds after the front reached a point whose front is `s` out: up the
// face, held, drained.
fn ts_prof(tau: f32, s: f32) -> f32 {
    if (tau <= 0.0) {
        return 0.0;
    }
    let tr = TS_FACE / ts_vel(s);
    let rr = clamp(tau / tr, 0.0, 1.0);
    let rise = 1.0 - pow(1.0 - rr, 2.3);
    let x = clamp((tau - tr - TS_HOLD) / TS_DRAIN, 0.0, 1.0);
    let drain = 1.0 - x * x * (3.0 - 2.0 * x);
    return rise * drain;
}
// The water's surface function at a point (relative to the target's ground): negative inside the water, positive in the
// air above it, and a big number where there is none.
fn ts_f(pa: vec3<f32>, t: f32, g: TsG) -> f32 {
    let s = dot(pa.xz, g.m);
    let u = dot(pa.xz, g.n);
    let env = ts_env(s, u, g);
    if (env < 0.03) {
        return 1.0e4;
    }
    let a = TS_A * env;
    let yb = clamp((pa.y + TS_SEA) / a, 0.0, 1.0);
    let tau = t - ts_arr(s, u, g.sd) + TS_LEAN * yb * yb + 0.05 * (fvnoise(vec2<f32>(u * 0.06 + g.sd, pa.y * 0.045)) - 0.5);
    let p = ts_prof(tau, s);
    if (p <= 0.0) {
        return 1.0e4;
    }
    return pa.y - (a * p - TS_SEA);
}

struct TsHit {
    t: f32,
    hit: bool,
}
// The first place the ray (from `ro`, relative to the target's ground) is in the water, between t0 and t1: marched down
// the way to the front's reach, with steps of a seventh of the way to the surface, then bisected.
fn ts_march(ro: vec3<f32>, rd: vec3<f32>, t0: f32, t1: f32, time: f32, g: TsG, j: f32) -> TsHit {
    var h: TsHit;
    h.hit = false;
    h.t = t1;
    let s0 = dot(ro.xz, g.m);
    let rs = dot(rd.xz, g.m);
    // (the wave lies behind its front, a little ahead of it where a lobe runs on: a ray that starts ahead of that and
    // heads away from it never meets it)
    let sf = ts_front(time) + 240.0;
    var tin = t0;
    if (s0 > sf) {
        if (rs >= -1.0e-4) {
            return h;
        }
        tin = max(tin, (s0 - sf) / -rs);
    }
    let ytop = TS_A - TS_SEA + 30.0;
    if (ro.y > ytop) {
        if (rd.y >= -1.0e-4) {
            return h;
        }
        tin = max(tin, (ro.y - ytop) / -rd.y);
    }
    var t = tin + j * 2.0;
    var tp = tin;
    for (var i = 0; i < 80; i = i + 1) {
        if (t > t1) {
            break;
        }
        let f = ts_f(ro + rd * t, time, g);
        if (f < 0.0) {
            // (bisected between the last step and this one)
            var a = tp;
            var b = t;
            for (var k = 0; k < 7; k = k + 1) {
                let mid = 0.5 * (a + b);
                if (ts_f(ro + rd * mid, time, g) < 0.0) {
                    b = mid;
                } else {
                    a = mid;
                }
            }
            h.t = b;
            h.hit = true;
            return h;
        }
        tp = t;
        t = t + clamp(f * 0.14, 0.7 + t * 0.0012, 60.0);
    }
    return h;
}
fn ts_normal(p: vec3<f32>, t: f32, g: TsG) -> vec3<f32> {
    let e = 1.2;
    let dx = ts_f(p + vec3<f32>(e, 0.0, 0.0), t, g) - ts_f(p - vec3<f32>(e, 0.0, 0.0), t, g);
    let dy = ts_f(p + vec3<f32>(0.0, e, 0.0), t, g) - ts_f(p - vec3<f32>(0.0, e, 0.0), t, g);
    let dz = ts_f(p + vec3<f32>(0.0, 0.0, e), t, g) - ts_f(p - vec3<f32>(0.0, 0.0, e), t, g);
    return normalize(vec3<f32>(dx, dy, dz) + vec3<f32>(1.0e-5));
}

fn ts_vn3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(fh31(i), fh31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(fh31(i + vec3<f32>(0.0, 1.0, 0.0)), fh31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(fh31(i + vec3<f32>(0.0, 0.0, 1.0)), fh31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(fh31(i + vec3<f32>(0.0, 1.0, 1.0)), fh31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}
fn ts_fbm3(p: vec3<f32>, oct: i32) -> f32 {
    var a = 0.5;
    var q = p;
    var s = 0.0;
    var n = 0.0;
    for (var i = 0; i < oct; i = i + 1) {
        s = s + a * ts_vn3(q);
        n = n + a;
        a = a * 0.5;
        // (turned a little between octaves so no octave's grid lines up with the last's)
        q = vec3<f32>(q.x * 0.8 - q.z * 0.6, q.y, q.x * 0.6 + q.z * 0.8) * 2.07 + vec3<f32>(5.1, 1.3, 7.7);
    }
    return s / n;
}

// What the light is: matched to the scene's, as the Hurricane's.
struct TsLight {
    L: vec3<f32>,
    amb: vec3<f32>,
    sunc: vec3<f32>,
    skyl: vec3<f32>,
    fogl: vec3<f32>,
    day: f32,
}


// The water's surface over (s, u) at `t`, relative to the target's ground (a big negative number where there is none).
fn ts_surf_y(s: f32, u: f32, t: f32, g: TsG) -> f32 {
    let env = ts_env(s, u, g);
    if (env < 0.03) {
        return -1.0e4;
    }
    let tau = t - ts_arr(s, u, g.sd);
    let p = ts_prof(tau, s);
    if (p <= 0.0) {
        return -1.0e4;
    }
    return TS_A * env * p - TS_SEA;
}

// ---- the debris: the land the wave swept up, in the game's own block textures ---------------------------------------
// Logs, planks, cobblestone, wool, hay, leaves, soil: tumbling pieces riding the face and the foam, and past the camera
// under the water. What kinds follow the land it is over (a map in the table: the share of each 16 by 16 cell with trees
// and with buildings), so a wood throws up logs and leaves, a village planks, stone and glass. Each is a box, a block or a
// few (a log four long), turning; each cell of a grid in the wave's own frame holds at most one.
@group(0) @binding(8) var block_sprites: texture_2d_array<f32>;
@group(0) @binding(9) var block_sampler: sampler;
const TSB: u32 = 64u;           // the block types' words (tsunami.rs's TS_KINDS, TSBW words each)
const TSBW: u32 = 12u;
const TSM: u32 = 384u;          // the map of what the land has on it
const TSM_S: u32 = 64u;
const TSM_U: u32 = 32u;

fn ts_ud(i: u32) -> u32 {
    if (i >= arrayLength(&mod_data)) {
        return 0u;
    }
    return mod_data[i];
}
fn ts_have() -> bool {
    return arrayLength(&mod_data) > TSM + TSM_S * TSM_U;
}
fn ts_565(c: u32) -> vec3<f32> {
    return srgb_to_linear(vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0));
}
fn ts_lod(t: f32) -> f32 {
    let px = 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    return log2(max(t * px * 16.0, 1.0e-4));
}
fn ts_face_st(m: u32, uv: vec2<f32>) -> vec2<f32> {
    let q = vec3<f32>(vec3<u32>(m, m >> 2u, m >> 4u) & vec3<u32>(3u)) - 1.0;
    let r = vec3<f32>(vec3<u32>(m >> 6u, m >> 8u, m >> 10u) & vec3<u32>(3u)) - 1.0;
    return fract(vec2<f32>(q.x + uv.x * q.z + uv.y * r.y, q.y + uv.x * r.x + uv.y * r.z) * 0.99999 + 0.000005);
}
fn ts_tint(c: u32) -> vec3<f32> {
    if (c == 0xFFFFu) {
        return vec3<f32>(1.0);
    }
    return vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0);
}
// The colour of block type `bk`'s face `face` (0 top, 1 bottom, 2 a side) at `uv` on it, linear: the game's own texture where
// the table has it (its overlay laid over it), else its average.
fn ts_face(bk: u32, face: u32, uv: vec2<f32>, lod: f32) -> vec3<f32> {
    let o = TSB + bk * TSBW;
    let a = ts_ud(o);
    let b = ts_ud(o + 1u);
    let avg = ts_565(select(select(a >> 16u, b & 0xFFFFu, face == 1u), a & 0xFFFFu, face == 0u));
    let f0 = ts_ud(o + 2u + 3u * face);
    if ((f0 & 1u) == 0u || lod > 3.5) {
        return avg;
    }
    let st = ts_face_st(ts_ud(o + 4u + 3u * face), uv);
    let lv = clamp(lod, 0.0, f32(textureNumLevels(block_sprites) - 1));
    let c0 = textureSampleLevel(block_sprites, block_sampler, st, i32((f0 >> 2u) & 0x1FFFu), lv);
    var rgb = srgb_to_linear(c0.rgb * ts_tint(f0 >> 16u));
    if ((f0 & 2u) != 0u && c0.a < 0.5) {
        rgb = avg * 0.3;
    }
    let f1 = ts_ud(o + 3u + 3u * face);
    if ((f1 & 1u) != 0u) {
        let c1 = textureSampleLevel(block_sprites, block_sampler, st, i32((f1 >> 2u) & 0x1FFFu), lv);
        rgb = mix(rgb, srgb_to_linear(c1.rgb * ts_tint(f1 >> 16u)), c1.a);
    }
    return rgb;
}
// What the land holds under the wave at (s, u): the share of trees (x) and of buildings (y).
fn ts_map(s: f32, u: f32) -> vec2<f32> {
    if (!ts_have()) {
        return vec2<f32>(0.5, 0.12);
    }
    let i = i32(floor((s + 320.0) / 16.0));
    let j = i32(floor((u + 256.0) / 16.0));
    if (i < 0 || j < 0 || i >= 64 || j >= 32) {
        return vec2<f32>(0.25, 0.0);
    }
    let w = ts_ud(TSM + u32(j) * TSM_S + u32(i));
    return vec2<f32>(f32(w & 255u), f32((w >> 8u) & 255u)) / 255.0;
}
// A kind (TS_KINDS' order) for a roll `r` (0 to 1) and a second `r2`, by the land's trees `tr` and buildings `bd`.
fn ts_kind(r: f32, r2: f32, tr: f32, bd: f32) -> u32 {
    let wl = 3.0 * tr + 0.25;
    let wp = 2.6 * bd + 0.12;
    let ws = 2.2 * bd + 0.05;
    let wo = 1.4 * bd;
    let wf = 3.5 * tr + 0.1;
    let wd = 1.7;
    var x = r * (wl + wp + ws + wo + wf + wd);
    if (x < wl) {
        return u32(r2 * 4.0) % 4u;
    }
    x = x - wl;
    if (x < wp) {
        return select(select(4u, 5u, r2 > 0.4), 22u, r2 > 0.85);
    }
    x = x - wp;
    if (x < ws) {
        return select(select(6u, 7u, r2 > 0.35), select(8u, 18u, r2 > 0.9), r2 > 0.65);
    }
    x = x - ws;
    if (x < wo) {
        return 9u + u32(r2 * 6.0) % 6u;
    }
    x = x - wo;
    if (x < wf) {
        return 12u + u32(r2 * 2.0) % 2u;
    }
    return select(select(14u, 15u, r2 > 0.3), select(16u, 17u, r2 > 0.8), r2 > 0.55);
}
fn ts_rodrigues(ax: vec3<f32>, a: f32) -> mat3x3<f32> {
    let c = cos(a);
    let s = sin(a);
    let k = 1.0 - c;
    return mat3x3<f32>(
        vec3<f32>(c + ax.x * ax.x * k, ax.y * ax.x * k + ax.z * s, ax.z * ax.x * k - ax.y * s),
        vec3<f32>(ax.x * ax.y * k - ax.z * s, c + ax.y * ax.y * k, ax.z * ax.y * k + ax.x * s),
        vec3<f32>(ax.x * ax.z * k + ax.y * s, ax.y * ax.z * k - ax.x * s, c + ax.z * ax.z * k));
}
struct TsPieceHit {
    t: f32,
    rgb: vec3<f32>,
    hit: bool,
}
// The ray against one piece: a box of half-sizes `h` at `c`, turned by `m`, a block type `kind`, lit by the pass's light.
fn ts_piece_hit(ro: vec3<f32>, rd: vec3<f32>, c: vec3<f32>, h: vec3<f32>, m: mat3x3<f32>, kind: u32, li: TsLight, wet: f32) -> TsPieceHit {
    var out: TsPieceHit;
    out.hit = false;
    let mt = transpose(m);
    let o = mt * (ro - c);
    let d = mt * rd;
    let inv = 1.0 / (d + vec3<f32>(select(1.0e-6, -1.0e-6, d.x < 0.0), select(1.0e-6, -1.0e-6, d.y < 0.0), select(1.0e-6, -1.0e-6, d.z < 0.0)));
    let t1 = (-h - o) * inv;
    let t2 = (h - o) * inv;
    let tn = min(t1, t2);
    let tf = max(t1, t2);
    let tnear = max(max(tn.x, tn.y), tn.z);
    let tfar = min(min(tf.x, tf.y), tf.z);
    if (tnear >= tfar || tfar <= 0.0 || tnear <= 0.0) {
        return out;
    }
    let p = o + d * tnear;
    // (which face: the axis it entered through)
    var nl = vec3<f32>(0.0);
    var uv = vec2<f32>(0.0);
    var face = 2u;
    if (tnear == tn.y) {
        nl.y = -sign(d.y);
        uv = fract(p.xz + h.xz);
        face = select(1u, 0u, nl.y > 0.0);
    } else if (tnear == tn.x) {
        nl.x = -sign(d.x);
        uv = fract(vec2<f32>(p.z + h.z, 1.0 - (p.y + h.y)));
    } else {
        nl.z = -sign(d.z);
        uv = fract(vec2<f32>(p.x + h.x, 1.0 - (p.y + h.y)));
    }
    let nw = m * nl;
    let alb = ts_face(kind, face, uv, ts_lod(tnear));
    let dif = saturate(dot(nw, li.L));
    var rgb = alb * (li.amb * (1.3 + 0.6 * nw.y) + li.sunc * dif * 0.85 + vec3<f32>(0.025));
    // (wet through, dirtied by the water)
    rgb = mix(rgb, rgb * vec3<f32>(0.8, 0.74, 0.62) + vec3<f32>(0.01, 0.008, 0.004), wet);
    out.t = tnear;
    out.rgb = rgb;
    out.hit = true;
    return out;
}
// A piece from the hash `hh` at `ctr`, spinning with `time`, grown from nothing by `grow` (0 to 1); the nearest hit of the ray
// with it. `tr`, `bd` the land's trees and buildings there.
fn ts_piece(ro: vec3<f32>, rd: vec3<f32>, hh: u32, ctr: vec3<f32>, time: f32, grow: f32, scale: f32, tr: f32, bd: f32, li: TsLight, wet: f32) -> TsPieceHit {
    let h2 = pcg(hh ^ 0x68E31DA4u);
    let h3 = pcg(h2 + 0x1B873593u);
    let r = vec4<f32>(vec4<u32>(hh & 0xFFFFu, hh >> 16u, h2 & 0xFFFFu, h2 >> 16u)) / 65536.0;
    let r2 = vec3<f32>(vec3<u32>(h3 & 0x3FFu, (h3 >> 10u) & 0x3FFu, (h3 >> 20u) & 0x3FFu)) / 1024.0;
    let kind = ts_kind(r.x, r2.x, tr, bd);
    let log = kind < 4u;
    // (their sizes: a trunk five to twelve blocks long, a clump of leaves, a panel of planks, a lump of stone, a slab of earth)
    var half = vec3<f32>(0.5);
    if (log) {
        half = vec3<f32>(0.5, 0.5, 2.5 + 3.5 * r2.y);
    } else if (kind == 12u || kind == 13u) {
        half = vec3<f32>(1.1 + 0.5 * r2.y);
    } else if (kind == 4u || kind == 5u || kind == 22u) {
        half = select(vec3<f32>(1.5, 0.5, 1.0 + 0.5 * r2.y), vec3<f32>(1.0, 1.0, 0.5), r2.z > 0.6);
    } else if (kind == 6u || kind == 7u || kind == 8u || kind == 18u) {
        half = select(vec3<f32>(0.5), vec3<f32>(1.0, 0.5, 0.5 + 0.5 * r2.y), r2.z > 0.45);
    } else if (kind == 14u || kind == 15u || kind == 16u || kind == 17u || kind == 23u) {
        half = vec3<f32>(1.3 + 0.4 * r2.y, 0.6, 1.3 + 0.4 * r2.z);
    }
    half = half * grow * scale;
    let ax = normalize(vec3<f32>(r.y - 0.5, r.z - 0.5, r.w - 0.5) + vec3<f32>(0.001, 0.002, 0.003));
    let ang = r2.z * 6.283 + time * (0.35 + 1.2 * r2.x) * select(1.0, 0.4, log);
    let m = ts_rodrigues(ax, ang);
    return ts_piece_hit(ro, rd, ctr, half, m, kind, li, wet);
}
// The drift of the water's own parcels from where the front found them: about four fifths of the front's speed while it
// rises, slowing as it holds, back the way it came as it drains (the integral of surge.rs's flow).
fn ts_ism(a: f32, b: f32, x: f32) -> f32 {
    let u = clamp((x - a) / (b - a), 0.0, 1.0);
    let inside = (b - a) * (u * u * u - 0.5 * u * u * u * u);
    return inside + max(x - b, 0.0);
}
fn ts_drift(s: f32, u: f32, time: f32, g: TsG) -> f32 {
    let tau = max(time - ts_arr(s, u, g.sd), 0.0);
    let v = ts_vel(s);
    let tr = TS_FACE / v;
    let d1 = 0.8 * v * (tau - 0.85 * ts_ism(tr, tr + TS_HOLD, tau));
    let t1 = tr + TS_HOLD;
    let d2 = 16.0 * (ts_ism(t1, t1 + TS_DRAIN, tau) - ts_ism(t1 + TS_DRAIN, t1 + TS_DRAIN + 3.0, tau));
    return d1 - d2;
}
// Pieces riding the face and the foam near where the ray met the water at `hp`: the cells of the wave's frame round that
// point, one piece in a cell at most, on the surface (partly sunk in it), the more the nearer the front.
// (the water's height over the ground at (s, u): for the foot, where the debris is thickest)
fn a_h_y(s: f32, u: f32, time: f32, g: TsG) -> f32 {
    return max(ts_surf_y(s, u, time, g), 0.0);
}
fn ts_deb_ext(ro: vec3<f32>, rd: vec3<f32>, hp: vec3<f32>, t_hit: f32, time: f32, g: TsG, li: TsLight) -> TsPieceHit {
    var best: TsPieceHit;
    best.hit = false;
    best.t = 1.0e9;
    if (t_hit > 900.0) {
        return best;
    }
    let sfm = ts_front(time);
    let cs = 7.0;
    let a_h = dot(hp.xz, g.m) - sfm;
    let u_h = dot(hp.xz, g.n);
    let ia0 = i32(floor(a_h / cs));
    let iu0 = i32(floor(u_h / cs));
    for (var di = -1; di <= 1; di = di + 1) {
        for (var dj = -1; dj <= 1; dj = dj + 1) {
            let ia = ia0 + di;
            let iu = iu0 + dj;
            let hc = pcg(u32(ia * 7919 + 100003) ^ pcg(u32(iu * 104729 + 7)));
            for (var k = 0u; k < 2u; k = k + 1u) {
                let hh = pcg(hc + k * 0x7F4A7C15u);
                let r0 = f32(hh & 0xFFFFu) / 65536.0;
                let r1 = f32(hh >> 16u) / 65536.0;
                let h2 = pcg(hh + 0x9E3779B9u);
                let r2 = f32(h2 & 0xFFFFu) / 65536.0;
                let r3 = f32(h2 >> 16u) / 65536.0;
                // (drifting back along the wave's way through its cell, shrunk away at the ends so none pops)
                let f = fract(r1 + time * 0.2);
                let grow = smoothstep(0.0, 0.16, f) * smoothstep(1.0, 0.84, f);
                let a_c = (f32(ia) + f) * cs;
                let u_c = (f32(iu) + r2) * cs;
                let s_c = sfm + a_c;
                let tau_c = time - ts_arr(s_c, u_c, g.sd);
                let dens = 0.7 * smoothstep(0.0, 0.4, tau_c) * (1.0 - smoothstep(35.0, 130.0, -a_c)) * (1.0 + 1.2 * (1.0 - smoothstep(0.0, 45.0, a_h_y(s_c, u_c, time, g)))) + 0.035;
                if (r0 > dens || grow < 0.05) {
                    continue;
                }
                let lvl = ts_surf_y(s_c, u_c, time, g);
                if (lvl < -1000.0) {
                    continue;
                }
                let y_c = lvl - 0.8 + (r3 - 0.4) * 3.0;
                let ctr = vec3<f32>(g.m.x * s_c + g.n.x * u_c, y_c, g.m.y * s_c + g.n.y * u_c);
                let mp = ts_map(s_c, u_c);
                let ph = ts_piece(ro, rd, pcg(hh ^ h2), ctr, time, grow, 1.5 + clamp(t_hit / 110.0, 0.0, 3.5), mp.x, mp.y, li, 0.55);
                if (ph.hit && ph.t < best.t && ph.t < t_hit + 5.0) {
                    best = ph;
                }
            }
        }
    }
    return best;
}
// Pieces in the water the camera is in: a grid of cells riding the water's own drift, sampled along the ray as far as it
// can be seen through the murk; the camera's carry and the flow past it make them rush by.
fn ts_deb_under(ro: vec3<f32>, rd: vec3<f32>, lw: f32, time: f32, cs: f32, cu: f32, g: TsG, li: TsLight, j: f32) -> TsPieceHit {
    var best: TsPieceHit;
    best.hit = false;
    best.t = 1.0e9;
    let dr = ts_drift(cs, cu, time, g);
    let rop = ro - vec3<f32>(g.m.x * dr, 0.0, g.m.y * dr);
    let cell = 7.0;
    let mp = ts_map(cs, cu);
    var last = vec3<i32>(1 << 20);
    let n = 14;
    let reach = min(lw, 46.0);
    for (var i = 0; i < n; i = i + 1) {
        let t = (f32(i) + j) * reach / f32(n);
        let p = rop + rd * t;
        let ic = vec3<i32>(floor(p / cell));
        if (all(ic == last)) {
            continue;
        }
        last = ic;
        let hh = pcg(u32(ic.x * 73856 + 5) ^ pcg(u32(ic.y * 19349 + 11) ^ pcg(u32(ic.z * 83492 + 3))));
        let r0 = f32(hh & 0xFFFFu) / 65536.0;
        if (r0 > 0.2 || ic.y < -90) {
            continue;
        }
        let h2 = pcg(hh + 0x85EBCA6Bu);
        let jit = vec3<f32>(f32(h2 & 255u), f32((h2 >> 8u) & 255u), f32((h2 >> 16u) & 255u)) / 255.0;
        let ctr = (vec3<f32>(ic) + 0.15 + 0.7 * jit) * cell;
        let ph = ts_piece(rop, rd, pcg(hh ^ h2), ctr, time, 1.0, 1.0, mp.x, mp.y, li, 0.3);
        if (ph.hit && ph.t < best.t) {
            best = ph;
        }
    }
    return best;
}

// The wave's surface where the ray met it: its colour (linear), and how much of the picture it takes (a thin foot lets
// the ground show through).
fn ts_surface(p: vec3<f32>, rd: vec3<f32>, ht: f32, time: f32, g: TsG, li: TsLight) -> vec4<f32> {
    let nrm0 = ts_normal(p, time, g);
    let s = dot(p.xz, g.m);
    let u = dot(p.xz, g.n);
    let env = ts_env(s, u, g);
    let a = TS_A * env;
    let tau = time - ts_arr(s, u, g.sd);
    let w = tau * ts_vel(s);
    let ybar = clamp((p.y + TS_SEA) / a, 0.0, 1.0);
    let hg = max(p.y, 0.0);
    // (the detail shrinks to nothing with distance: a pixel is many blocks out there)
    let lod = clamp(2.8 - log2(max(ht, 1.0) * 0.004 + 1.0) * 1.2, 0.0, 3.0);
    let noct = i32(clamp(lod + 1.0, 1.0, 4.0));
    let tv = vec3<f32>(p.x * 0.0, 0.0, 0.0);
    let uc = u * 0.05;
    let turb = ts_fbm3(vec3<f32>(uc, (p.y + time * 9.0) * 0.045, w * 0.05), noct);
    let strk = ts_vn3(vec3<f32>(u * 0.13, p.y * 0.011 + time * 0.9, w * 0.02));
    let fine = ts_fbm3(vec3<f32>(u * 0.4, (p.y + time * 14.0) * 0.3, w * 0.4), 2);
    // how steep the face is here
    let steep = 1.0 - abs(nrm0.y);
    var nrm = nrm0;
    // (the face's ripples: its normal jostled by the turbulence)
    let jit = vec3<f32>(turb - 0.5, 0.3 * (fine - 0.5), ts_vn3(vec3<f32>(uc + 7.0, p.y * 0.05, w * 0.05 + 3.0)) - 0.5) * 0.55 * lod / 3.0;
    nrm = normalize(nrm + jit);
    // ---- foam: the crest, patches on the face, tongues running down from the crest, and a churning foot ----------------
    let ragged = ts_fbm3(vec3<f32>(uc * 2.0 + 3.0, p.y * 0.1 + time * 2.0, w * 0.1), noct);
    let behind = smoothstep(95.0, 210.0, w);
    let crestF = smoothstep(0.87 - 0.06 * ragged, 0.97, ybar) * (1.0 - 0.85 * behind);
    let patchf = smoothstep(0.7, 0.88, turb + 0.12 * ybar);
    let tongue = smoothstep(0.66, 0.86, strk) * smoothstep(0.55, 0.93, ybar + 0.25 * (ragged - 0.5)) * (0.5 + 0.5 * turb);
    let foot = (1.0 - smoothstep(4.0, 30.0 + 18.0 * turb, hg)) * smoothstep(0.38, 0.62, turb);
    var foam = clamp(crestF * (0.45 + 0.8 * ragged) + 0.6 * patchf * (0.3 + 0.7 * ybar) + 0.85 * tongue * (1.0 - behind) + 0.85 * foot + 0.35 * behind * smoothstep(0.6, 0.8, turb), 0.0, 1.0);
    foam = foam * (0.55 + 0.45 * smoothstep(0.2, 0.55, fine + 0.35 * foam));
    // ---- the water: dark, brown-green, murky; at the thin, sunlit crest a green glow --------------------------------
    let fresnel = 0.03 + 0.97 * pow(1.0 - saturate(dot(nrm, -rd)), 5.0);
    let refl = reflect(rd, nrm);
    let skyc = mix(li.fogl, li.skyl, smoothstep(0.0, 0.55, refl.y)) * (0.55 + 0.45 * li.day);
    let dif = saturate(dot(nrm, li.L));
    let mud = vec3<f32>(0.135, 0.1, 0.058);
    let green = vec3<f32>(0.06, 0.11, 0.075);
    let thin = smoothstep(0.72, 1.0, ybar) * (0.4 + 0.6 * turb);
    var body = mix(mud, green, 0.35 + 0.4 * thin) * (li.amb * 1.4 + li.sunc * dif * 0.55 + vec3<f32>(0.004));
    let tra = pow(saturate(dot(rd, li.L)), 3.0) * thin;
    body = body + vec3<f32>(0.06, 0.26, 0.17) * li.sunc * tra * 1.2;
    // (under the lip it overhangs: dark)
    body = body * (1.0 - 0.6 * smoothstep(0.05, -0.5, nrm0.y));
    let wet = mix(body, skyc * 0.75, fresnel * (1.0 - 0.7 * foam));
    let spec = pow(saturate(dot(refl, li.L)), 90.0) * li.sunc * 2.0 * (1.0 - foam);
    let foamc = vec3<f32>(0.8, 0.79, 0.74) * (mix(li.amb, vec3<f32>(luminance(li.amb)), 0.5) * 1.5 + li.sunc * (0.3 + 0.5 * dif)) * (0.8 + 0.3 * fine);
    var c = mix(wet, foamc, foam) + spec;
    // the thin water at the foot lets the ground through
    let alpha = 1.0;
    return vec4<f32>(c, alpha);
}

// The flow's velocity at (s, u) at `t` (blocks a second, on the ground, along the wave's way positive): fast as the
// face goes over, slowing as it holds, back the way it came as it drains (surge.rs's flow, kept in step: the carry holds
// the player at half of it, so what the water carries goes past them at about the other half).
fn ts_flow(s: f32, u: f32, t: f32) -> f32 {
    let tau = t - TS_T - ts_tau(s) - 0.0 * u;
    let tr = TS_FACE / ts_vel(s);
    let rise = 0.25 * ts_vel(s) * (1.0 - 0.8 * smoothstep(tr, tr + TS_HOLD, tau));
    let dr = smoothstep(tr + TS_HOLD, tr + TS_HOLD + TS_DRAIN, tau);
    return rise * (1.0 - dr) - 16.0 * dr * (1.0 - smoothstep(tr + TS_HOLD + TS_DRAIN, tr + TS_HOLD + TS_DRAIN + 3.0, tau));
}

// The camera in the water: the land and the sky seen through a murk of mud, suspended silt and bubbles streaming past,
// a bright, broken surface above (where the ray leaves the water), and for the first seconds the white of the front
// that went over. `scene` is what the game drew at the pixel (the land, or the sky), `rd` the view ray, the camera at `ro`
// (relative to the target's ground).
fn ts_under(ro: vec3<f32>, rd: vec3<f32>, scene_len: f32, scene: vec3<f32>, time: f32, g: TsG, li: TsLight, j: f32, sky: bool) -> vec3<f32> {
    let cs = dot(ro.xz, g.m);
    let cu = dot(ro.xz, g.n);
    let surf_c = ts_surf_y(cs, cu, time, g);
    let dep_c = max(surf_c - ro.y, 0.0);
    // where the ray leaves the water (up through its surface, or out of the front or the back of it)
    var t_exit = 1.0e9;
    var tp = 0.0;
    for (var i = 0; i < 26; i = i + 1) {
        let fi = f32(i) + j;
        let t = 0.5 + fi * fi * 0.19;
        if (t > scene_len) {
            break;
        }
        if (ts_f(ro + rd * t, time, g) > 0.0) {
            var a = tp;
            var b = t;
            for (var k = 0; k < 6; k = k + 1) {
                let mid = 0.5 * (a + b);
                if (ts_f(ro + rd * mid, time, g) > 0.0) {
                    b = mid;
                } else {
                    a = mid;
                }
            }
            t_exit = b;
            break;
        }
        tp = t;
    }
    var lw = min(min(scene_len, t_exit), 140.0);
    // (a piece of what the wave swept up, nearer than all that, rushing by)
    let deb = ts_deb_under(ro, rd, lw, time, cs, cu, g, li, j);
    var piece = false;
    if (deb.hit && deb.t < lw) {
        lw = deb.t;
        piece = true;
    }
    // (how the murk thickens, by colour: the red goes last)
    let sig = vec3<f32>(0.060, 0.075, 0.100);
    let tr = exp(-sig * lw);
    // the light down here: brighter nearer the surface
    let mid = ro + rd * (0.5 * lw);
    let ms = dot(mid.xz, g.m);
    let mu = dot(mid.xz, g.n);
    let dep = max(ts_surf_y(ms, mu, time, g) - mid.y, 0.0);
    let day = li.day;
    let lit = (0.22 + 0.78 * exp(-dep / 38.0)) * (0.35 + 0.65 * day);
    // the flow past the camera (about half of it, the carry has the rest), as 3D motion of what the water holds
    let fl = ts_flow(cs, cu, time) * 3.0;
    let vel = vec3<f32>(g.m.x * fl, 0.0, g.m.y * fl);
    var silt = 0.0;
    var bub = 0.0;
    for (var i = 0; i < 12; i = i + 1) {
        let t = (f32(i) + j) * lw / 12.0;
        let q = ro + rd * t;
        let wgt = exp(-t * 0.04);
        let w = q - vel * time;
        silt = silt + wgt * smoothstep(0.55, 0.85, ts_fbm3(w * vec3<f32>(0.07, 0.11, 0.07), 2));
        bub = bub + wgt * smoothstep(0.80, 0.9, ts_vn3(w * 0.55 + vec3<f32>(vel.z * 0.0, 0.0, 0.0)));
    }
    silt = silt / 12.0;
    bub = bub / 12.0;
    // the light's shafts down through it, off the broken surface
    var shaft = 0.0;
    for (var i = 0; i < 8; i = i + 1) {
        let t = (f32(i) + j) * lw / 8.0;
        let q = ro + rd * t;
        let sd = max(ts_surf_y(dot(q.xz, g.m), dot(q.xz, g.n), time, g) - q.y, 0.0);
        let pat = smoothstep(0.45, 0.8, ts_vn3(vec3<f32>(q.x * 0.045, q.z * 0.045, time * 0.5)));
        shaft = shaft + pat * exp(-sd / 55.0) * (1.0 / 8.0);
    }
    let ambn = max(vec3<f32>(luminance(li.amb)), vec3<f32>(0.035));
    let mud = vec3<f32>(0.11, 0.082, 0.045);
    let green = vec3<f32>(0.06, 0.085, 0.045);
    var ins = mix(mud, green, 0.3 + 0.3 * silt) * (ambn * 2.6 + vec3<f32>(0.008)) * lit * (0.75 + 0.5 * silt);
    ins = ins + vec3<f32>(0.5, 0.55, 0.4) * li.sunc * shaft * 0.16 * lit;
    ins = ins + vec3<f32>(0.5, 0.52, 0.46) * bub * 0.18 * lit * (0.5 + 0.5 * day);
    // what is at the end of it: the land, the sky through the surface, or the surface seen from below
    var far_col = scene;
    if (piece) {
        far_col = deb.rgb;
    } else if (t_exit < scene_len) {
        let up = saturate(-rd.y);
        let window = smoothstep(0.45, 0.8, up);
        let pe = ro + rd * t_exit;
        let ns = ts_fbm3(vec3<f32>(pe.x * 0.09, pe.z * 0.09, time * 0.7), 3);
        // (through the window the sky, bright and rippling; past it the murk's own light back)
        let skyc = mix(li.fogl, li.skyl, 0.6) * (0.5 + 0.7 * ns);
        let foamb = smoothstep(0.55, 0.8, ns) * 0.7;
        far_col = mix(ins * 1.6, skyc * (0.55 + 0.45 * day), window) + vec3<f32>(0.6) * foamb * (0.3 + 0.7 * day) * li.amb;
    }
    // (what is seen through it lit as dimly as the water round it: the sun's light thins with depth)
    far_col = far_col * mix(1.0, 0.25 + 0.75 * lit, 0.85);
    var out = far_col * tr + ins * (1.0 - tr);
    // the front that went over them: white water, thinning over a second or two
    let tau = time - ts_arr(cs, cu, g.sd);
    let aer = exp(-max(tau, 0.0) / 1.0);
    let wash = ts_fbm3(vec3<f32>(rd.x * 3.0, rd.y * 3.0 + time * 2.0, rd.z * 3.0), 3);
    out = mix(out, vec3<f32>(0.64, 0.62, 0.56) * (ambn * 1.6 + li.sunc * 0.25) * (0.75 + 0.5 * wash), aer * (0.55 + 0.4 * wash));
    return out;
}

// The spray and the mist: a cloud thrown up off the crest and over it, a skirt of mist along the ground ahead of the
// face, marched in the band the wave's front lies in, over the water's own surface only, up to `t1` (what is in front of
// the surface or the land). rgb premultiplied, a the light left (1 none).
fn ts_spray(ro: vec3<f32>, rd: vec3<f32>, t0: f32, t1: f32, time: f32, g: TsG, li: TsLight, j: f32) -> vec4<f32> {
    let s0 = dot(ro.xz, g.m);
    let rs = dot(rd.xz, g.m);
    let sf = ts_front(time);
    // the band: from 200 behind the front to 260 ahead
    var ta = t0;
    var tb = t1;
    if (abs(rs) > 1.0e-4) {
        let ca = (sf - 200.0 - s0) / rs;
        let cb = (sf + 260.0 - s0) / rs;
        ta = max(ta, min(ca, cb));
        tb = min(tb, max(ca, cb));
    } else if (s0 < sf - 200.0 || s0 > sf + 260.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // (and under the plume's top)
    let ytop = TS_A - TS_SEA + 90.0;
    if (rd.y > 1.0e-4) {
        tb = min(tb, (ytop - ro.y) / rd.y);
    } else if (rd.y < -1.0e-4 && ro.y > ytop) {
        ta = max(ta, (ro.y - ytop) / -rd.y);
    } else if (ro.y > ytop) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    if (tb <= ta) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let n = 16;
    let dt = (tb - ta) / f32(n);
    var tr = 1.0;
    var acc = vec3<f32>(0.0);
    let ambn = vec3<f32>(luminance(li.amb));
    let lightc = ambn * 1.5 + li.sunc * 0.5;
    for (var i = 0; i < n; i = i + 1) {
        let t = ta + (f32(i) + j) * dt;
        let p = ro + rd * t;
        let s = dot(p.xz, g.m);
        let u = dot(p.xz, g.n);
        let env = ts_env(s, u, g);
        if (env < 0.2) {
            continue;
        }
        let tau = time - ts_arr(s, u, g.sd);
        let da = -tau * ts_vel(s);
        let lc = TS_A * env - TS_SEA;
        let ls = ts_surf_y(s, u, time, g);
        if (p.y < ls) {
            continue;
        }
        // (thrown up off the crest and over it, streaming ahead of it; and a skirt of mist along the ground ahead)
        let hc = max(p.y - lc, 0.0);
        let plume = exp(-pow(hc / 30.0, 2.0)) * smoothstep(-120.0, -8.0, da) * (1.0 - smoothstep(10.0, 120.0, da)) * smoothstep(0.55 * lc, 0.95 * lc, p.y);
        let skirt = smoothstep(-2.0, 14.0, p.y) * (1.0 - smoothstep(0.4 * lc, 0.95 * lc, p.y)) * exp(-max(da, 0.0) / 85.0) * (1.0 - smoothstep(-2.0, -30.0, da));
        let w = p * 0.045 + vec3<f32>(-g.m.x, 0.0, -g.m.y) * 0.0 - vec3<f32>(0.0, 0.0, 0.0);
        let nz = ts_fbm3(vec3<f32>(u * 0.03, p.y * 0.05 - time * 0.6, (s - ts_front(time)) * 0.03 + time * 0.2), 3);
        let dens = (plume * 1.0 + skirt * 0.45) * smoothstep(0.38, 0.8, nz) * env;
        if (dens < 0.001) {
            continue;
        }
        let ext = dens * dt * 0.02;
        let a = 1.0 - exp(-ext);
        // (brighter at its top and where the sun lights it, darker deep in it)
        let lit = 0.6 + 0.5 * smoothstep(0.0, lc, p.y);
        acc = acc + tr * a * lightc * lit * mix(vec3<f32>(0.74, 0.69, 0.6), vec3<f32>(0.84, 0.84, 0.82), smoothstep(0.0, 70.0, p.y));
        tr = tr * (1.0 - a);
        if (tr < 0.02) {
            break;
        }
    }
    return vec4<f32>(acc, tr);
}

fn tsunami(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let time = now();
    let k = intensity_v();
    let cam = frame.camera_position.xyz;
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    // (off the camera without its f32 rounding: far from the origin the camera moves in 1/128 block steps)
    let C = (vec3<f32>(anc.x, gy, anc.y) - cam) - camera_rest();
    let d = depth_at(uv);
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let g = ts_geo();
    let ro = -C;

    let sun = frame.sun.xyz;
    var li: TsLight;
    li.day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    li.L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    li.skyl = srgb_to_linear(frame.sky_color.rgb);
    li.fogl = srgb_to_linear(frame.fog_color.rgb);
    li.amb = mix(vec3<f32>(0.02, 0.025, 0.035), li.skyl * 0.6 + vec3<f32>(0.03), li.day);
    li.sunc = mix(vec3<f32>(1.25, 1.18, 1.05), vec3<f32>(1.4, 0.62, 0.3), warm) * sun_up + vec3<f32>(0.05, 0.07, 0.11) * (1.0 - sun_up);

    let pj = vec2<u32>(floor(in.position.xy));
    let j = f32(pcg(pj.x * 0x9E3779B1u ^ pcg(pj.y * 0x85EBCA6Bu ^ u32(time * 60.0))) & 0xFFFFu) / 65536.0;

    if (ts_f(ro, time, g) < 0.0) {
        col = ts_under(ro, rd, scene_len, scene, time, g, li, j, sky);
        return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
    }
    let h = ts_march(ro, rd, 0.0, min(scene_len, 6000.0), time, g, j);
    var t_front = min(scene_len, 6000.0);
    if (h.hit) {
        t_front = h.t;
        let sf = ts_surface(ro + rd * h.t, rd, h.t, time, g, li);
        // (thin water over the land lets it show through, tinted: the film the drain leaves, a shallow edge)
        var a = sf.a;
        var under = scene;
        if (scene_len < 1.0e8) {
            let path = max(scene_len - h.t, 0.0);
            a = max(a * 0.0, 1.0 - exp(-path / 5.0));
            under = scene * exp(-vec3<f32>(0.10, 0.12, 0.16) * path);
        }
        col = mix(under, sf.rgb, a);
        // (what the wave has swept up, riding its face and its foam)
        let deb = ts_deb_ext(ro, rd, ro + rd * h.t, h.t, time, g, li);
        var t_see = h.t;
        if (deb.hit) {
            col = deb.rgb;
            t_see = deb.t;
        }
        // (the haze of the distance)
        let haze = 1.0 - exp(-t_see * 0.00032);
        col = mix(col, li.fogl * 0.95, haze * 0.8);
    }
    let sp = ts_spray(ro, rd, 0.0, t_front, time, g, li, j);
    col = col * sp.a + sp.rgb;
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return tsunami(in);
}
