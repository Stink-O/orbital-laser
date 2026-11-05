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
const TS_A: f32 = 420.0;        // how far over that it stands at full strength, far out: 320 over the target's ground
const TS_FACE: f32 = 105.0;     // the face's width, blocks
const TS_HOLD: f32 = 6.5;       // seconds the water holds at its height, then
const TS_DRAIN: f32 = 14.0;     // drains away over
const TS_LOW: f32 = 0.15;       // how far the water behind the crest sits under it (a share)

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
// stretches of it. (Sines, not noise: this is asked for hundreds of times a pixel.)
fn ts_lag(s: f32, u: f32, sd: f32) -> f32 {
    let c = 3.0e-7 * u * u;
    return c + (0.34 * sin(u * 0.0043 + sd + s * 0.0011) + 0.13 * sin(u * 0.0127 + sd * 1.7 - s * 0.0023) + 0.05 * sin(u * 0.0331 + sd * 0.6 + s * 0.0041)) * smoothstep(-650.0, -150.0, s);
}
fn ts_arr(s: f32, u: f32, sd: f32) -> f32 {
    return TS_T + ts_tau(s) + ts_lag(s, u, sd);
}
// How strong the wave is where (s, u): stood up out of the sea in the first second and a bit (the horizon rising), at its
// tallest far out, losing height as it breaks and runs in over the land, spent at its end, weaker towards its flanks, its
// crest uneven along the front. 1 at full strength.
fn ts_env(s: f32, u: f32, g: TsG) -> f32 {
    let up = 0.2 + 0.8 * smoothstep(-905.0, -770.0, s);
    let dec = 1.0 - 0.345 * smoothstep(-640.0, -40.0, s);
    let run = 1.0 - 0.13 * smoothstep(0.0, g.send, s);
    let end = 1.0 - smoothstep(g.send - 80.0, g.send + 30.0, s);
    let lat = 1.0 - smoothstep(1500.0, 2700.0, abs(u));
    let lump = 1.0 + 0.028 * sin(u * 0.0063 + g.sd * 1.7 + s * 0.0016) + 0.024 * sin(u * 0.0171 + g.sd * 0.9 - s * 0.0031) + 0.016 * sin(u * 0.0419 + g.sd * 2.3 + s * 0.0047);
    return up * dec * run * end * lat * lump;
}
// Where along the crest it is breaking at (s, u), 0 a smooth dark shoulder, 1 its lip thrown out and avalanching down the
// face: stretches a few hundred blocks long that move along the crest as it comes. Only the pass has this.
fn ts_break(s: f32, u: f32, sd: f32) -> f32 {
    return smoothstep(-0.25, 0.7, sin(u * 0.0094 + sd + s * 0.0037) + 0.6 * sin(u * 0.0231 - s * 0.0083 + sd * 3.1) + 0.3 * sin(u * 0.0577 + s * 0.011 + sd * 1.3));
}
// How far it has drained at `s` at `t`, 0 to 1. All the land's water goes together, not in the order it came: it starts when
// the player's has held long enough, the seaward side a little first, so the whole sheet tilts away and runs back.
fn ts_x(t: f32, s: f32, g: TsG) -> f32 {
    let t0 = TS_T + ts_tau(g.dp) + TS_FACE / ts_vel(g.dp) + TS_HOLD + 0.0016 * (s - g.dp);
    return clamp((t - t0) / TS_DRAIN, 0.0, 1.0);
}
// The water's height over its sea (0 to 1) `tau` seconds after the front reached a point whose front is `s` out: up the
// concave face to its crest, down behind it to where it holds.
fn ts_prof(tau: f32, s: f32) -> f32 {
    if (tau <= 0.0) {
        return 0.0;
    }
    let tr = TS_FACE / ts_vel(s);
    let rr = clamp(tau / tr, 0.0, 1.0);
    return pow(rr, 1.7) * (1.0 - TS_LOW * smoothstep(tr, tr * 3.0, tau));
}
// The level `lv` (over the target's ground) as it drains, `x`: down hard at first, slowing as it nears the land (hilltops
// out first, the plains under a few blocks of running water for a while, the hollows last).
fn ts_fall(lv: f32, x: f32) -> f32 {
    if (x <= 0.0) {
        return lv;
    }
    let e = smoothstep(0.0, 0.42, x);
    return mix(lv, 12.0 - 118.0 * x * x, e);
}
// The water's surface function at a point (relative to the target's ground): negative inside the water, positive in the
// air above it, and a big number where there is none. The crest leans out over the face, more where it is breaking.
fn ts_f(pa: vec3<f32>, t: f32, g: TsG) -> f32 {
    let s = dot(pa.xz, g.m);
    let u = dot(pa.xz, g.n);
    let env = ts_env(s, u, g);
    if (env < 0.03) {
        return 1.0e4;
    }
    let a = TS_A * env;
    let yb = clamp((pa.y + TS_SEA) / a, 0.0, 1.0);
    let y2 = yb * yb;
    let lean = (0.1 + 0.34 * ts_break(s, u, g.sd)) * y2 * y2 * yb;
    let tau = t - ts_arr(s, u, g.sd) + lean;
    let p = ts_prof(tau, s);
    let x = ts_x(t, s, g);
    if (p <= 0.0 || x >= 1.0) {
        return 1.0e4;
    }
    // (the crest torn along its length)
    let tear = (fvnoise(vec2<f32>(u * 0.052 + g.sd, t * 0.9 + s * 0.01)) - 0.5) * 16.0 * smoothstep(0.8, 1.0, yb);
    return pa.y - ts_fall(a * p - TS_SEA + tear, x);
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
    let ytop = TS_A * 1.12 - TS_SEA + 30.0;
    if (ro.y > ytop) {
        if (rd.y >= -1.0e-4) {
            return h;
        }
        tin = max(tin, (ro.y - ytop) / -rd.y);
    }
    var t = tin + j * 2.0;
    var tp = tin;
    for (var i = 0; i < 90; i = i + 1) {
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
        // (over the water behind the front the surface is nearly level, and a ray going over it can stride)
        let far_back = dot((ro + rd * t).xz, g.m) < sf - 480.0;
        t = t + clamp(f * select(0.14, 0.7, far_back), 0.7 + t * 0.0012, 60.0);
    }
    return h;
}
fn ts_normal(p: vec3<f32>, t: f32, g: TsG) -> vec3<f32> {
    let e = 1.5;
    let k = vec2<f32>(1.0, -1.0);
    return normalize(k.xyy * ts_f(p + k.xyy * e, t, g) + k.yyx * ts_f(p + k.yyx * e, t, g) + k.yxy * ts_f(p + k.yxy * e, t, g) + k.xxx * ts_f(p + k.xxx * e, t, g) + vec3<f32>(1.0e-5));
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
    // (a floor under the night's light, so the water and its foam still read by the moon)
    nightw: vec3<f32>,
}


// The water's surface over (s, u) at `t`, relative to the target's ground (a big negative number where there is none).
fn ts_surf_y(s: f32, u: f32, t: f32, g: TsG) -> f32 {
    let env = ts_env(s, u, g);
    if (env < 0.03) {
        return -1.0e4;
    }
    let tau = t - ts_arr(s, u, g.sd);
    let p = ts_prof(tau, s);
    let x = ts_x(t, s, g);
    if (p <= 0.0 || x >= 1.0) {
        return -1.0e4;
    }
    return ts_fall(TS_A * env * p - TS_SEA, x);
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
const TSM_U: u32 = 44u;

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
    let j = i32(floor((u + 352.0) / 16.0));
    if (i < 0 || j < 0 || i >= 64 || j >= 44) {
        return vec2<f32>(0.25, 0.0);
    }
    let w = ts_ud(TSM + u32(j) * TSM_S + u32(i));
    return vec2<f32>(f32(w & 255u), f32((w >> 8u) & 255u)) / 255.0;
}
// The land's height over the target's ground at (s, u), from the same map (bilinear), 0 where it hasn't been read.
fn ts_gcell(i: i32, j: i32) -> f32 {
    if (i < 0 || j < 0 || i >= 64 || j >= 44) {
        return 0.0;
    }
    let w = ts_ud(TSM + u32(j) * TSM_S + u32(i)) >> 16u;
    return select(f32(w) - 2048.0, 0.0, w == 0u);
}
fn ts_ground(s: f32, u: f32) -> f32 {
    if (!ts_have()) {
        return 0.0;
    }
    let x = (s + 320.0) / 16.0 - 0.5;
    let y = (u + 352.0) / 16.0 - 0.5;
    let i = i32(floor(x));
    let j = i32(floor(y));
    let f = vec2<f32>(x - floor(x), y - floor(y));
    return mix(mix(ts_gcell(i, j), ts_gcell(i + 1, j), f.x), mix(ts_gcell(i, j + 1), ts_gcell(i + 1, j + 1), f.x), f.y);
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
        half = vec3<f32>(0.7 + 0.5 * r2.y, 0.5 + 0.4 * r2.z, 0.8 + 0.5 * r2.x);
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
    let d2 = 24.0 * (ts_ism(t1, t1 + TS_DRAIN, tau) - ts_ism(t1 + TS_DRAIN, t1 + TS_DRAIN + 3.0, tau));
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
                let dens = 0.5 * smoothstep(0.0, 0.4, tau_c) * (1.0 - smoothstep(35.0, 130.0, -a_c)) * (1.0 - smoothstep(10.0, 42.0, a_h_y(s_c, u_c, time, g))) + 0.012 + 0.06 * ts_x(time, s_c, g);
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
                let ph = ts_piece(ro, rd, pcg(hh ^ h2), ctr, time, grow, 1.2 + clamp(t_hit / 200.0, 0.0, 2.0), mp.x, mp.y, li, 0.55);
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
        if (r0 > 0.13 || ic.y < -90) {
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

// Worley noise: the distance to the nearest two points of a jittered grid (the cells of foam's lace are its F2 - F1).
fn ts_vor(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = p - i;
    var d1 = 9.0;
    var d2 = 9.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let c = vec2<i32>(i32(i.x) + x, i32(i.y) + y);
            let h = pcg(u32(c.x * 8191 + 100003) ^ pcg(u32(c.y * 131071 + 7)));
            let o = vec2<f32>(f32(h & 0xFFFFu), f32(h >> 16u)) / 65536.0;
            let r = vec2<f32>(f32(x), f32(y)) + o - f;
            let d = dot(r, r);
            if (d < d1) {
                d2 = d1;
                d1 = d;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    return sqrt(vec2<f32>(d1, d2));
}
// Foam's lace: the thin bright network left on dark water, its cells stretched along (y) the way the water is drawn.
fn ts_lace(p: vec2<f32>, warp: f32) -> f32 {
    let q = p + vec2<f32>(warp, warp * 0.6) * 0.9;
    let v = ts_vor(q);
    return 1.0 - smoothstep(0.0, 0.16, v.y - v.x);
}
// The sum of a few directional waves, sharpened at their crests: the height's slope (x along `p.x`, y along `p.y`).
// `f` fades the small ones with distance (0 only the biggest, 1 all).
fn ts_ripple(p: vec2<f32>, t: f32, f: f32) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    var a = 1.0;
    var w = 0.11;
    var ang = 0.7;
    for (var i = 0; i < 6; i = i + 1) {
        let d = vec2<f32>(cos(ang), sin(ang));
        let ph = dot(d, p) * w + t * sqrt(w * 9.8) * 1.6 + f32(i) * 1.9;
        // (sin raised to a power rounds the troughs and points the crests)
        let c = 0.5 + 0.5 * sin(ph);
        let k = a * pow(c, 2.0) * cos(ph);
        g = g + d * k;
        let fade = clamp(f * 6.0 - f32(i), 0.0, 1.0);
        a = a * 0.72 * fade;
        w = w * 1.62;
        ang = ang + 2.399;
    }
    return g;
}
// The sky a reflected ray sees, or the dark land and water under it.
fn ts_skyr(r: vec3<f32>, li: TsLight) -> vec3<f32> {
    let hor = mix(li.fogl, li.skyl, smoothstep(0.0, 0.5, r.y));
    return mix(vec3<f32>(0.012, 0.03, 0.03) * (0.3 + li.day), hor, smoothstep(-0.12, 0.04, r.y));
}

// The wave's surface where the ray met it: its colour (linear). `hg` how far over the land under it this is (a big number
// over the sky), `path` how far the ray runs on through the water to the land.
fn ts_surface(p: vec3<f32>, rd: vec3<f32>, ht: f32, time: f32, g: TsG, li: TsLight, hg: f32, j: f32) -> vec3<f32> {
    let nrm0 = ts_normal(p, time, g);
    let s = dot(p.xz, g.m);
    let u = dot(p.xz, g.n);
    let env = ts_env(s, u, g);
    let a = TS_A * env;
    let tau = time - ts_arr(s, u, g.sd);
    let vel = ts_vel(s);
    let w = tau * vel;
    let ybar = clamp((p.y + TS_SEA) / a, 0.0, 1.05);
    let dtop = max(a - TS_SEA - p.y, 0.0);
    let bk = ts_break(s, u, g.sd);
    // how many blocks a pixel covers here: what is too fine for it fades out
    let px = ht * 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    let near = 1.0 - smoothstep(0.4, 2.4, px);
    let mid = 1.0 - smoothstep(2.0, 10.0, px);
    let face = 1.0 - smoothstep(0.35, 0.8, nrm0.y);
    // (the coordinate along the water's way: up the face on the face, along the flow behind it)
    let v = p.y - w;
    let warp = ts_fbm3(vec3<f32>(u * 0.016, v * 0.012, time * 0.13 + g.sd), 2 + i32(mid * 2.0));
    let warp2 = ts_fbm3(vec3<f32>(u * 0.06 + 3.0, v * 0.03, time * 0.25), 2);

    // ---- the white water: thrown off the lip, avalanching down the face in tongues, heaped at the foot ------------------
    let drop = 38.0;
    let vd = v + drop * time;
    let tongue = (0.5 + 0.5 * sin(u * 0.041 + 6.0 * warp + g.sd)) * 0.5 + 0.5 * warp;
    let reach = (10.0 + 16.0 * env) + (a - TS_SEA) * (0.03 + 0.62 * bk * bk * smoothstep(0.3, 0.75, tongue) * smoothstep(-520.0, -180.0, s));
    // (the sheets fray into falling threads at their ends)
    let fray = ts_fbm3(vec3<f32>(u * 0.21, vd * 0.012, 3.0), 2 + i32(mid));
    let wc = 1.0 - dtop / reach + (warp2 - 0.5) * 1.0 + (fray - 0.5) * 1.5;
    var white = smoothstep(0.1, 0.42, wc) * smoothstep(-20.0, 90.0, w + 60.0);
    // (the foot: a churning bore where the face meets the land, thrown up in lumps)
    let boil = ts_fbm3(vec3<f32>(u * 0.024, (p.y + time * 15.0) * 0.03, s * 0.017 - time * 0.5), 2 + i32(mid * 2.0));
    let foot = (1.0 - smoothstep(8.0 + 30.0 * boil, 22.0 + 44.0 * boil, hg + 24.0 * (fray - 0.5)));
    white = max(white, foot);
    // (the last of it, right in front of the eye: whatever part of the face this is, it is coming apart and thrown at them)
    let rush = 1.0 - smoothstep(4.0, 58.0, ht);
    var rushn = 0.0;
    if (rush > 0.0) {
        rushn = ts_fbm3(vec3<f32>(u * 0.09, (p.y + time * 34.0) * 0.05, w * 0.08 + time * 2.0), 4);
        white = max(white, smoothstep(0.62 - 0.5 * rush, 0.8 - 0.42 * rush, rushn + 0.2 * rush));
    }
    // behind the crest: the broken water it leaves
    let back = smoothstep(0.82, 0.96, nrm0.y) * smoothstep(40.0, 130.0, w);
    // ---- the billows of the white water, lit from their own relief ----------------------------------------------------
    // (no finer than a couple of pixels: past that the foam only sparkles)
    let oct = clamp(i32(log2(5.0 / max(px, 0.05))) + 1, 1, 5);
    let de = 0.35;
    // (the falling sheets' relief, drawn out down the face; the foot's own, tumbling, where there is a foot)
    var b0 = 0.0;
    var bx = 0.0;
    var by = 0.0;
    if (foot < 0.99) {
        let bq = vec3<f32>(u * 0.075, vd * 0.013, time * 0.3);
        b0 = ts_fbm3(bq, oct);
        bx = ts_fbm3(bq + vec3<f32>(de, 0.0, 0.0), oct);
        by = ts_fbm3(bq + vec3<f32>(0.0, de, 0.0), oct);
    }
    if (foot > 0.01) {
        let fq = vec3<f32>(u * 0.1, (p.y + time * 20.0) * 0.095, s * 0.06 - time * 1.1);
        b0 = mix(b0, ts_fbm3(fq, oct), foot);
        bx = mix(bx, ts_fbm3(fq + vec3<f32>(de, 0.0, 0.0), oct), foot);
        by = mix(by, ts_fbm3(fq + vec3<f32>(0.0, de, 0.0), oct), foot);
    }
    let tn = vec3<f32>(g.n.x, 0.0, g.n.y);
    let tu = normalize(cross(nrm0, tn));
    let bump = (b0 - bx) * tn + (b0 - by) * tu;
    let wn = normalize(nrm0 + bump * (1.2 + (2.2 + 3.0 * foot) * mid));
    let bdif = saturate(dot(wn, li.L));
    let cav = mix(0.62, smoothstep(0.3 + 0.08 * foot, 0.66, b0), 0.15 + 0.85 * (1.0 - smoothstep(0.4, 2.2, px)));
    // ---- the dark water's own surface -------------------------------------------------------------------------------
    let rp = vec2<f32>(u, v + 30.0 * time);
    let sl = ts_ripple(rp * vec2<f32>(1.0, 0.5), time, near + 0.35 * mid);
    let stretch = (0.09 + 0.2 * mid) * (0.2 + 0.8 * (1.0 - smoothstep(220.0, 800.0, ht)));
    var nrm = normalize(nrm0 + (tn * sl.x + tu * sl.y) * stretch);
    if (dot(nrm, rd) > -0.02) {
        nrm = normalize(nrm + rd * (dot(nrm, rd) + 0.02) * -1.0);
    }
    let cosv = saturate(dot(nrm, -rd));
    let fresnel = 0.035 + 0.965 * pow(1.0 - cosv, 5.0);
    let refl = reflect(rd, nrm);
    let skyc = ts_skyr(refl, li);
    // the water's own colour: almost black in the deep of the face, green where it thins towards the crest
    let thin = exp(-dtop / 46.0);
    let thin2 = exp(-dtop / 13.0);
    let deep = mix(vec3<f32>(0.0045, 0.016, 0.018), vec3<f32>(0.009, 0.036, 0.034), smoothstep(0.2, 0.85, ybar));
    // (the water takes the sun's colour only a little, however red it goes)
    let sunw = mix(li.sunc, vec3<f32>(luminance(li.sunc)), 0.65);
    let lightw = li.amb * 1.3 + sunw * (0.22 + 0.5 * saturate(dot(nrm, li.L))) + li.nightw;
    // (the folds of the water, its heave, show as it turns to the sky and from it)
    var body = deep * lightw * 2.4 * (1.0 + 1.6 * clamp(sl.y * stretch * 2.2, -0.7, 1.4));
    body = body + vec3<f32>(0.012, 0.085, 0.066) * thin * thin * (li.amb * 2.0 + li.sunc * 0.6 + li.nightw * 2.0);
    // (the sun through the thinnest of it: looking towards it, the lip lights up)
    let tra = pow(saturate(dot(rd, li.L) * 0.5 + 0.5), 4.0);
    body = body + vec3<f32>(0.035, 0.42, 0.3) * li.sunc * tra * thin2 * (0.7 + 0.6 * warp);
    // (the mud it is tearing up, towards its foot)
    let mudk = (1.0 - smoothstep(6.0, 55.0, hg)) * smoothstep(-500.0, -200.0, s);
    body = mix(body, vec3<f32>(0.05, 0.036, 0.021) * lightw * 1.4, mudk * 0.75);
    // (under the lip it overhangs: the sky is shut out)
    let lip = smoothstep(0.05, -0.55, nrm0.y);
    body = body * (1.0 - 0.75 * lip);
    // (the sun on it: glitter, not a lamp)
    let rl = saturate(dot(refl, li.L));
    let spk = smoothstep(0.42, 0.62, ts_vn3(vec3<f32>(u * 0.9, v * 0.5 + time * 7.0, time * 2.0))) * near + (1.0 - near) * 0.5;
    let spec = min(pow(rl, 420.0) * 1.5, 1.1) * li.sunc * (0.15 + 1.3 * spk) + pow(rl, 40.0) * li.sunc * 0.05;
    // (the toe of the face looks at the shut-out sky under the wave's own shoulder)
    let shut = (1.0 - 0.8 * lip) * (0.16 + 0.3 * smoothstep(0.1, 0.75, ybar));
    var wet = mix(body, skyc * shut, saturate(fresnel * (1.0 - 0.4 * face) + 0.4 * saturate(sl.y * 0.5) * stretch)) + spec;
    // ---- foam on the dark water: lace drawn up the face, thin and bright, in streaks ---------------------------------
    // (marbled streaks at any distance, the fine net of cells only near; patches of it, not all over)
    let vr = (v - 22.0 * time);
    let mar = ts_vn3(vec3<f32>(u * 0.07 + 7.0 * warp, vr * 0.009, 2.0));
    let streak = 1.0 - abs(2.0 * mar - 1.0);
    var lace = pow(streak, 3.0) * 0.16;
    if (near > 0.01) {
        lace = lace + near * 0.07 * ts_lace(vec2<f32>(u * 0.27, vr * 0.07), 2.2 * warp2);
    }
    // (and a heavier, ragged scum dragged up the toe of the face out of the white water)
    let drag = (1.0 - smoothstep(0.42, 0.72, ybar)) * smoothstep(0.42, 0.62, ts_vn3(vec3<f32>(u * 0.05 + 1.5 * warp2, vr * 0.024, 4.0)) * 0.6 + warp * 0.5);
    let lacek = smoothstep(0.42, 0.66, warp + 0.2 * ybar - 0.1 + 0.2 * back);
    let foamthin = saturate(lace * lacek * (0.35 + 0.65 * smoothstep(0.2, 0.8, ybar) + back) + drag * 0.34) * mid + (1.0 - mid) * lacek * 0.1;
    // ---- all together ----------------------------------------------------------------------------------------------
    let ambw = mix(li.amb, vec3<f32>(luminance(li.amb)), 0.6);
    let shade = ambw * (1.5 + 0.5 * wn.y) * (0.45 + 0.75 * cav) + mix(sunw, li.sunc, 0.4) * bdif * (0.6 + 0.4 * cav) + li.nightw * 2.6 * (0.6 + 0.6 * cav);
    var whitec = vec3<f32>(0.9, 0.92, 0.93) * shade;
    // (the foot: churned mud, nearly black, thrown up in lumps with white breaking on them)
    let sharp = 1.0 - smoothstep(0.35, 1.6, px);
    let flk = mix(smoothstep(0.42, 0.66, boil) * 0.55, smoothstep(0.44, 0.6, b0 + 0.12 * (boil - 0.5) + 0.2 * near * (fray - 0.5)), sharp);
    let mudl = vec3<f32>(0.16, 0.115, 0.075) * (0.5 + 0.9 * cav) * (ambw * 1.4 + li.sunc * (0.15 + 0.6 * bdif) + li.nightw * 2.0);
    whitec = mix(whitec, mix(mudl, vec3<f32>(0.74, 0.66, 0.55) * shade, flk), max(mudk * 0.6, foot));
    // (the crevices of the white water go blue-green: light that has come through water)
    whitec = whitec + vec3<f32>(0.0, 0.03, 0.03) * (1.0 - cav) * (li.amb + li.sunc * 0.25);
    let cover = saturate(white * (0.8 + 0.45 * b0) + 0.0);
    var c = mix(wet, vec3<f32>(0.8, 0.83, 0.84) * shade * 0.9, foamthin * (1.0 - cover));
    c = mix(c, whitec, cover);
    return c;
}

// The water as it drains: a brown torrent going back the way it came, streaming, torn into streaks of dirty foam, its
// edge a line of scum round whatever stands out of it. `hg`: how deep it is here.
fn ts_torrent(p: vec3<f32>, rd: vec3<f32>, ht: f32, time: f32, g: TsG, li: TsLight, hg: f32) -> vec3<f32> {
    let s = dot(p.xz, g.m);
    let u = dot(p.xz, g.n);
    let px = ht * 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    let near = 1.0 - smoothstep(0.3, 1.8, px);
    let mid = 1.0 - smoothstep(1.5, 9.0, px);
    // (it runs back along m, faster in its channels; the meander of those)
    let w0 = ts_fbm3(vec3<f32>(s * 0.008, u * 0.014, time * 0.1), 2);
    let run = s + time * (26.0 + 26.0 * w0) + 22.0 * sin(u * 0.03 + 4.0 * w0);
    let cross_ = u + 40.0 * (w0 - 0.5);
    let sl = ts_ripple(vec2<f32>(cross_ * 3.1, run * 0.95), time * 1.4, near + 0.5 * mid);
    let tn = vec3<f32>(g.n.x, 0.0, g.n.y);
    let tm = vec3<f32>(g.m.x, 0.0, g.m.y);
    var nrm = normalize(vec3<f32>(0.0, 1.0, 0.0) + (tn * sl.x + tm * sl.y) * (0.05 + 0.2 * mid));
    let cosv = saturate(dot(nrm, -rd));
    let fresnel = 0.03 + 0.97 * pow(1.0 - cosv, 5.0);
    let refl = reflect(rd, nrm);
    // (thick with mud: a body you can't see into)
    let n1 = ts_fbm3(vec3<f32>(cross_ * 0.03, run * 0.008, 1.0), 2 + i32(mid * 2.0));
    let dif = saturate(dot(nrm, li.L));
    let lw = mix(li.amb, vec3<f32>(luminance(li.amb)), 0.8) * 1.25 + li.sunc * (0.25 + 0.5 * dif) + li.nightw;
    var body = mix(vec3<f32>(0.08, 0.052, 0.024), vec3<f32>(0.15, 0.1, 0.05), n1) * lw;
    let rl = saturate(dot(refl, li.L));
    var c = mix(body, ts_skyr(refl, li) * vec3<f32>(0.5, 0.44, 0.34), fresnel) + pow(rl, 300.0) * li.sunc * 1.8 + pow(rl, 30.0) * li.sunc * 0.05;
    // the streaks of dirty foam, long along the way it runs, torn
    let st = ts_fbm3(vec3<f32>(cross_ * 0.3, run * 0.03, time * 0.2), 2 + i32(mid * 2.0));
    let tear = ts_fbm3(vec3<f32>(cross_ * 0.05, run * 0.035, 7.0), 2);
    var foam = smoothstep(0.56, 0.68, st) * smoothstep(0.42, 0.62, tear);
    // (scum and white water where it breaks round what stands out of it)
    if (hg < 8.0) {
        foam = max(foam, (1.0 - smoothstep(0.2, 1.4 + 2.0 * n1, hg)) * smoothstep(0.3, 0.55, st + 0.1));
    }
    let foamc = vec3<f32>(0.66, 0.57, 0.44) * (mix(li.amb, vec3<f32>(luminance(li.amb)), 0.8) * 1.6 + li.sunc * (0.3 + 0.55 * dif) + li.nightw * 2.4);
    return mix(c, foamc, foam * 0.75);
}

// The flow's velocity at (s, u) at `t` (blocks a second, on the ground, along the wave's way positive): fast as the
// face goes over, slowing as it holds, back the way it came as it drains (surge.rs's flow, kept in step: the carry holds
// the player at half of it, so what the water carries goes past them at about the other half).
fn ts_flow(s: f32, u: f32, t: f32, g: TsG) -> f32 {
    let tau = t - TS_T - ts_tau(s);
    let tr = TS_FACE / ts_vel(s);
    let rise = 0.25 * ts_vel(s) * (1.0 - 0.8 * smoothstep(tr, tr + TS_HOLD, tau));
    let x = ts_x(t, s, g);
    let dr = smoothstep(0.0, 0.5, x);
    return rise * (1.0 - dr) - 24.0 * dr * (1.0 - smoothstep(0.8, 1.0, x));
}

// What the wave took and carries whole past the camera: a tree, its trunk and crown, and a corner of a house, walls, floor,
// a window and a piece of its roof, each a few boxes of the game's own textures turning slowly as one.
const TS_BIGN: i32 = 3;
fn ts_bigbox(w: i32, i: i32) -> vec4<f32> {
    // xyz: the box's middle in the object, w: its kind
    if (w == 1) {
        switch i {
            case 0: { return vec4<f32>(0.0, -3.0, 0.0, 5.0); }    // a wall of planks
            case 1: { return vec4<f32>(-5.5, -3.0, 4.5, 4.0); }   // the wall round the corner
            case 2: { return vec4<f32>(0.0, -7.0, 2.0, 6.0); }    // the footing, cobble
            case 3: { return vec4<f32>(2.0, -2.5, -0.1, 9.0); }   // its window
            case 4: { return vec4<f32>(0.0, 3.0, 4.0, 8.0); }     // the roof, brick
            default: { return vec4<f32>(-3.0, 5.0, 3.0, 8.0); }
        }
    }
    switch i {
        case 0: { return vec4<f32>(0.0, 0.0, 0.0, 0.0); }         // the trunk, along z
        case 1: { return vec4<f32>(0.0, 0.0, 9.0, 12.0); }        // the crown
        case 2: { return vec4<f32>(2.2, 1.5, 6.0, 12.0); }
        case 3: { return vec4<f32>(-2.0, -1.5, 11.0, 12.0); }
        case 4: { return vec4<f32>(0.0, 2.0, 12.0, 13.0); }
        default: { return vec4<f32>(0.6, -2.0, 5.0, 13.0); }
    }
}
fn ts_bighalf(w: i32, i: i32) -> vec3<f32> {
    if (w == 1) {
        switch i {
            case 0: { return vec3<f32>(6.0, 3.0, 0.5); }
            case 1: { return vec3<f32>(0.5, 3.0, 5.0); }
            case 2: { return vec3<f32>(6.5, 1.0, 5.5); }
            case 3: { return vec3<f32>(1.0, 1.0, 0.56); }
            case 4: { return vec3<f32>(7.0, 0.5, 5.5); }
            default: { return vec3<f32>(4.0, 1.0, 3.5); }
        }
    }
    switch i {
        case 0: { return vec3<f32>(0.75, 0.75, 13.0); }
        case 1: { return vec3<f32>(3.5, 3.5, 3.0); }
        case 2: { return vec3<f32>(2.5, 2.5, 2.5); }
        case 3: { return vec3<f32>(3.0, 2.5, 3.0); }
        case 4: { return vec3<f32>(2.5, 2.0, 2.5); }
        default: { return vec3<f32>(2.0, 2.0, 2.0); }
    }
}
// The big pieces at the moments the sounds have them (`el` seconds after the water closed over the camera): each comes
// down the flow from well ahead and goes by close.
fn ts_bigs(ro: vec3<f32>, rd: vec3<f32>, el: f32, g: TsG, li: TsLight) -> TsPieceHit {
    var best: TsPieceHit;
    best.hit = false;
    best.t = 1.0e9;
    for (var k = 0; k < TS_BIGN; k = k + 1) {
        // (when it passes, what it is, how far to the side and up it goes by)
        var tp = 2.55;
        var w = 0;
        var off = vec2<f32>(11.0, 3.0);
        if (k == 1) {
            tp = 3.75;
            w = 1;
            off = vec2<f32>(-15.0, -1.0);
        } else if (k == 2) {
            tp = 5.3;
            w = 0;
            off = vec2<f32>(-7.0, 7.0);
        }
        let dt = el - tp;
        if (abs(dt) > 1.6) {
            continue;
        }
        // (fast by us, slowing a little after)
        let along = -dt * 52.0;
        let side = vec3<f32>(g.n.x, 0.0, g.n.y);
        let c = ro - vec3<f32>(g.m.x, 0.0, g.m.y) * along + side * off.x + vec3<f32>(0.0, off.y + dt * 1.5, 0.0);
        let oc = c - ro;
        let br = 24.0;
        let b = dot(oc, rd);
        if (dot(oc, oc) - b * b > br * br || b < -br) {
            continue;
        }
        let ax = normalize(vec3<f32>(0.5, 0.25 + 0.5 * f32(k), -0.6));
        let m = ts_rodrigues(ax, 0.9 * el + 1.7 * f32(k) + 0.5);
        for (var i = 0; i < 6; i = i + 1) {
            let bx = ts_bigbox(w, i);
            let ph = ts_piece_hit(ro, rd, c + m * bx.xyz, ts_bighalf(w, i), m, u32(bx.w), li, 0.3);
            if (ph.hit && ph.t < best.t) {
                best = ph;
            }
        }
    }
    return best;
}

// The camera in the water. First the blow: a white flash, then seconds of foam thrown past at a violent speed, billows of
// it with dark water between, which thin as it is dragged under. Then the water itself: green over brown, bright overhead,
// silt and bubbles streaming by, light coming down through it, wreckage going past, the broken surface above. `scene` is what
// the game drew at the pixel (the land, or the sky), `rd` the view ray, the camera at `ro` (relative to the target's ground).
fn ts_under(ro: vec3<f32>, rd: vec3<f32>, scene_len: f32, scene: vec3<f32>, time: f32, el: f32, g: TsG, li: TsLight, j: f32, sky: bool) -> vec3<f32> {
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
    var lw = min(min(scene_len, t_exit), 150.0);
    // (a piece of what the wave swept up, nearer than all that, rushing by)
    var deb = ts_deb_under(ro, rd, lw, time, cs, cu, g, li, j);
    let big = ts_bigs(ro, rd, el, g, li);
    if (big.hit && big.t < deb.t) {
        deb = big;
    }
    var piece = false;
    if (deb.hit && deb.t < lw) {
        lw = deb.t;
        piece = true;
    }
    // how far it can be seen: the water thick with silt, the red going last, but clear enough to see what passes
    let sig = vec3<f32>(0.034, 0.038, 0.052);
    let tr = exp(-sig * lw);
    let day = max(li.day, 0.0);
    let night = 1.0 - smoothstep(0.1, 0.55, li.day);
    // the light down here: brighter nearer the surface, and always some, so it reads on a phone
    let lit = (0.5 + 0.5 * exp(-dep_c / 55.0)) * (0.5 + 0.5 * day);
    let up = smoothstep(-0.7, 0.9, rd.y);
    var waterc = mix(vec3<f32>(0.052, 0.058, 0.03), mix(vec3<f32>(0.1, 0.16, 0.085), vec3<f32>(0.3, 0.42, 0.27), up * up), smoothstep(0.1, 0.9, up));
    waterc = mix(waterc, mix(vec3<f32>(0.014, 0.024, 0.04), vec3<f32>(0.04, 0.085, 0.13), up), night);
    // the flow past the camera: much faster in the first seconds
    let fl = (ts_flow(cs, cu, time, g) * 2.4 + 70.0 * exp(-max(el, 0.0) / 1.1));
    let vel = vec3<f32>(g.m.x * fl, 0.0, g.m.y * fl);
    let tn = vec3<f32>(g.n.x, 0.0, g.n.y);
    let swirl = 1.7 * time;
    // ---- what the water holds, marched along the ray: billows of foam, then silt; bubbles over them ----------------------
    let th = 0.42 + 0.2 * smoothstep(0.1, 2.6, el);
    let reach = mix(36.0, 90.0, smoothstep(0.3, 3.0, el));
    var acc = vec3<f32>(0.0);
    var trf = 1.0;
    var bub = 0.0;
    let foamlit = mix(vec3<f32>(1.0, 1.02, 1.0), vec3<f32>(0.24, 0.24, 0.15), smoothstep(0.3, 2.6, el)) * (0.42 + 0.58 * day) + li.nightw * 2.0;
    for (var i = 0; i < 12; i = i + 1) {
        let t = (f32(i) + 0.5 + (j - 0.5) * 0.3) * reach / 12.0;
        let q = ro + rd * t;
        var w = q - vel * time;
        // (streamed out along the flow, and rolling round it)
        let al = dot(w.xz, g.m);
        let ac = dot(w.xz, g.n);
        let ca = cos(swirl + al * 0.012);
        let sa = sin(swirl + al * 0.012);
        let wr = vec3<f32>(ac * ca - w.y * sa, ac * sa + w.y * ca, al * 0.38);
        if (t > lw) {
            break;
        }
        // (big rolling masses of it, cut up small: water full of air is never smooth)
        let big0 = ts_fbm3(wr * 0.035, 2);
        let fine = ts_fbm3(wr * 0.3 + vec3<f32>(big0 * 3.0), 3);
        let n = big0 * 0.62 + fine * 0.38;
        let bl = smoothstep(th - 0.03, th + 0.2, n);
        if (bl > 0.0) {
            let a = 1.0 - exp(-bl * reach / 12.0 * (0.018 + 0.9 * (1.0 - smoothstep(0.2, 2.2, el))));
            // (the air in it white, dark where the mass is deep)
            let shade = 0.55 + 0.75 * smoothstep(0.3, 0.68, fine) * smoothstep(0.32, 0.6, big0 + 0.1);
            acc = acc + trf * a * foamlit * shade * exp(-t * 0.016);
            trf = trf * (1.0 - a);
        }
        bub = bub + exp(-t * 0.05) * smoothstep(0.8, 0.9, ts_vn3(vec3<f32>(wr.x, wr.y + time * 12.0, wr.z) * 0.62));
    }
    bub = bub / 12.0;
    // the light's shafts down through it, off the broken surface
    var shaft = 0.0;
    for (var i = 0; i < 8; i = i + 1) {
        let t = (f32(i) + j) * min(lw, 70.0) / 8.0;
        let q = ro + rd * t;
        let sd = max(surf_c - q.y, 0.0);
        let dsun = q.xz + li.L.xz / max(li.L.y, 0.2) * sd;
        let pat = smoothstep(0.42, 0.72, ts_vn3(vec3<f32>(dsun.x * 0.05, dsun.y * 0.05, time * 0.6)));
        shaft = shaft + pat * exp(-sd / 80.0) * (1.0 / 8.0);
    }
    var ins = waterc * lit;
    ins = ins + vec3<f32>(0.42, 0.5, 0.34) * li.sunc * shaft * 0.34 * lit;
    ins = ins + vec3<f32>(0.75, 0.8, 0.72) * bub * 0.55 * lit;
    // what is at the end of it: the land, the sky through the surface, or the surface seen from below
    var far_col = scene * (0.45 + 0.55 * lit);
    if (piece) {
        far_col = deb.rgb * (0.7 + 0.5 * lit) + waterc * lit * 0.2;
    } else if (t_exit < scene_len) {
        let w_up = saturate(-0.0 + rd.y);
        let window = smoothstep(0.35, 0.75, w_up);
        let pe = ro + rd * t_exit;
        let ns = ts_fbm3(vec3<f32>(pe.x * 0.07, pe.z * 0.07, time * 0.9), 3);
        let skyc = mix(li.fogl, li.skyl, 0.6) * (0.75 + 0.9 * ns) + li.sunc * pow(saturate(dot(rd, li.L)), 12.0) * 1.4;
        let foamb = smoothstep(0.52, 0.72, ns) * 0.8;
        far_col = mix(ins * 1.5, skyc * (0.6 + 0.5 * day), window) + vec3<f32>(0.75, 0.78, 0.7) * foamb * (0.2 + 0.8 * day) * (0.3 + 0.7 * window);
    }
    var out = far_col * tr + ins * (1.0 - tr);
    out = out * trf + acc;
    // the blow itself: a white flash, the picture blown out for a moment
    let e = max(el, 0.0);
    out = out + vec3<f32>(1.5, 1.5, 1.45) * exp(-e / 0.075) * (0.25 + 0.75 * day);
    return out;
}

// The spray and the mist: a torn veil blown up off the crest and back over it, far taller where the wave is still out at
// sea and breaking, and a skirt of mist along the ground ahead of the face, marched in the band the wave's front lies in,
// over the water's own surface only, up to `t1` (what is in front of the surface or the land). rgb premultiplied, a the
// light left (1 none).
fn ts_spray(ro: vec3<f32>, rd: vec3<f32>, t0: f32, t1: f32, time: f32, g: TsG, li: TsLight, j: f32) -> vec4<f32> {
    let s0 = dot(ro.xz, g.m);
    let rs = dot(rd.xz, g.m);
    let sf = ts_front(time);
    // the band: from 330 behind the front to 300 ahead
    var ta = t0;
    var tb = t1;
    if (abs(rs) > 1.0e-4) {
        let ca = (sf - 330.0 - s0) / rs;
        let cb = (sf + 300.0 - s0) / rs;
        ta = max(ta, min(ca, cb));
        tb = min(tb, max(ca, cb));
    } else if (s0 < sf - 330.0 || s0 > sf + 300.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // (and under the plume's top)
    let ytop = TS_A * 1.1 - TS_SEA + 210.0;
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
    let n = 18;
    let dt = (tb - ta) / f32(n);
    let jj = 0.5 + (j - 0.5) * 0.35;
    var tr = 1.0;
    var acc = vec3<f32>(0.0);
    let ambn = vec3<f32>(luminance(li.amb));
    let lightc = ambn * 1.7 + li.sunc * 0.62 + li.nightw * 2.2;
    for (var i = 0; i < n; i = i + 1) {
        let t = ta + (f32(i) + jj) * dt;
        let p = ro + rd * t;
        let s = dot(p.xz, g.m);
        let u = dot(p.xz, g.n);
        let env = ts_env(s, u, g);
        if (env < 0.12) {
            continue;
        }
        let tau = time - ts_arr(s, u, g.sd);
        // (how far ahead of the crest this is)
        let dc = (TS_FACE / ts_vel(s) - tau) * ts_vel(s);
        let lc = TS_A * env - TS_SEA;
        let ls = ts_surf_y(s, u, time, g);
        if (p.y < ls) {
            continue;
        }
        let bk = ts_break(s, u, g.sd);
        // (out at sea it throws a great curtain up; over the land less)
        let tall = (55.0 + 150.0 * (1.0 - smoothstep(-650.0, -120.0, s))) * (0.45 + 0.55 * bk);
        let hc = max(p.y - lc, 0.0);
        let plume = exp(-pow(hc / tall, 1.6)) * smoothstep(-300.0, -60.0, dc - hc * 0.9) * (1.0 - smoothstep(0.0, 70.0 + hc * 0.12, dc - hc * 0.5)) * smoothstep(0.6 * lc, 0.97 * lc, p.y);
        // (the skirt: mist rolling ahead of the face, near the ground)
        let skirt = smoothstep(-6.0, 12.0, p.y) * (1.0 - smoothstep(10.0, 0.55 * lc, p.y)) * exp(-max(dc, 0.0) / 75.0) * smoothstep(-110.0, 0.0, dc);
        if (plume + skirt < 0.004) {
            continue;
        }
        // (torn into wisps blown back and up)
        let nz = ts_fbm3(vec3<f32>(u * 0.012, (p.y - time * 16.0) * 0.016, (s - sf + time * 12.0) * 0.012), 3);
        let wisp = ts_fbm3(vec3<f32>(u * 0.024, (p.y - time * 30.0) * 0.011, (s - sf + time * 34.0) * 0.024), 2);
        let dens = plume * 0.75 * smoothstep(0.42, 0.8, nz * 0.75 + wisp * 0.45) + skirt * 0.4 * smoothstep(0.3, 0.7, nz);
        if (dens < 0.001) {
            continue;
        }
        let ext = dens * dt * 0.024 * smoothstep(0.1, 0.3, env);
        let a = 1.0 - exp(-ext);
        // (brighter high up where the sun has it, darker low in its own shade)
        let lit = 0.55 + 0.6 * smoothstep(0.3 * lc, lc + 40.0, p.y);
        acc = acc + tr * a * lightc * lit * mix(vec3<f32>(0.66, 0.62, 0.55), vec3<f32>(0.88, 0.9, 0.92), smoothstep(0.0, 60.0, p.y));
        tr = tr * (1.0 - a);
        if (tr < 0.02) {
            break;
        }
    }
    return vec4<f32>(acc, tr);
}

// How much of the sky's light the wave shuts out where the camera is (0 to 1): the sky turning as it comes, more the nearer.
fn ts_dim(cs: f32, time: f32) -> f32 {
    let dist = cs - ts_front(time);
    return (0.3 * smoothstep(0.2, 3.0, time) + 0.42 * (1.0 - smoothstep(30.0, 620.0, dist))) * (1.0 - smoothstep(130.0, 500.0, -dist));
}

// How long the water has been over a point at height y (blocks over the target's ground) at (s, u): negative before it
// got there. The inverse of the face's rise.
fn ts_closed(y: f32, s: f32, u: f32, time: f32, g: TsG) -> f32 {
    let a = TS_A * ts_env(s, u, g);
    let x = pow(clamp((y + TS_SEA) / max(a, 1.0), 0.0, 1.0), 1.0 / 1.7);
    return time - ts_arr(s, u, g.sd) - x * TS_FACE / ts_vel(s);
}

// Land the water has been over: dark and wet, a film of water on it shining, and rills running off it, down the faces of
// the blocks and over the ground the way the water went. `k` how much (it dries off towards the strike's end).
fn ts_wet(col: vec3<f32>, pl: vec3<f32>, rel: vec3<f32>, uv: vec2<f32>, rd: vec3<f32>, time: f32, k: f32, g: TsG, li: TsLight) -> vec3<f32> {
    // (the block face's normal from the depth round it)
    let px = frame.resolution.zw;
    let rx = world_offset(uv + vec2<f32>(px.x, 0.0), depth_at(uv + vec2<f32>(px.x, 0.0))) - rel;
    let ry = world_offset(uv + vec2<f32>(0.0, px.y), depth_at(uv + vec2<f32>(0.0, px.y))) - rel;
    var nrm = normalize(cross(ry, rx));
    if (dot(nrm, rd) > 0.0) {
        nrm = -nrm;
    }
    let s = dot(pl.xz, g.m);
    let u = dot(pl.xz, g.n);
    let top = smoothstep(0.5, 0.8, nrm.y);
    let dist = length(rel);
    let fine = 1.0 - smoothstep(60.0, 220.0, dist);
    // what the rills are: thin lines over the ground, sheets down the sides
    let w0 = fvnoise(vec2<f32>(s * 0.03, u * 0.05));
    let line = fvnoise(vec2<f32>(u * 0.6 + 6.0 * w0, (s + time * 9.0) * 0.05));
    let rtop = pow(saturate(1.0 - abs(2.0 * line - 1.0)), 26.0);
    let sheet = fvnoise(vec2<f32>((pl.x + pl.z) * 0.8, (pl.y + time * 7.0) * 0.09));
    let rside = smoothstep(0.58, 0.74, sheet) * (1.0 - smoothstep(20.0, 70.0, dist));
    let rill = mix(rside * 0.7, rtop, top) * fine;
    let dark = mix(vec3<f32>(1.0), vec3<f32>(0.5, 0.45, 0.4), k);
    var c = col * dark;
    let fr = 0.04 + 0.96 * pow(1.0 - saturate(dot(nrm, -rd)), 5.0);
    let refl = reflect(rd, normalize(nrm + vec3<f32>(0.0, 0.02 * (w0 - 0.5), 0.0)));
    // (the film on it, and the sun in it)
    c = mix(c, ts_skyr(refl, li) * 0.7, fr * top * k * 0.5);
    c = c + li.sunc * pow(saturate(dot(refl, li.L)), 150.0) * 0.7 * top * k;
    // (the rills' water, brown and catching the sky)
    let wc = vec3<f32>(0.11, 0.08, 0.05) * (li.amb * 1.6 + li.sunc * 0.6 + li.nightw) + ts_skyr(vec3<f32>(rd.x, abs(rd.y) + 0.2, rd.z), li) * 0.14;
    return mix(c, wc, rill * k * 0.85);
}

fn tsunami(in: StageIn) -> vec4<f32> {
    var uv = in.uv;
    let time = now();
    let k = intensity_v();
    let cam = frame.camera_position.xyz;
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    // (off the camera without its f32 rounding: far from the origin the camera moves in 1/128 block steps)
    let C = (vec3<f32>(anc.x, gy, anc.y) - cam) - camera_rest();
    let g = ts_geo();
    let ro = -C;
    let cs0 = dot(ro.xz, g.m);
    let cu0 = dot(ro.xz, g.n);
    let inw = ts_f(ro, time, g) < 0.0;
    let el = ts_closed(ro.y, cs0, cu0, time, g);
    // (in its grip the whole picture is thrown round, and rocks after that)
    if (inw) {
        let ee = max(el, 0.0);
        let aspect = frame.resolution.x * frame.resolution.w;
        let ang = 0.62 * sin(ee * 3.1 + 0.5) * exp(-ee / 1.1) + 0.05 * sin(time * 1.1) + 0.03 * sin(time * 2.3 + 1.0);
        let zoom = 1.0 - 0.14 * exp(-ee / 1.4) * (0.5 + 0.5 * sin(ee * 7.0 + 1.0)) - 0.03;
        let c = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
        let r = vec2<f32>(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang)) * zoom;
        uv = r / vec2<f32>(aspect, 1.0) + vec2<f32>(0.5);
    }
    let d = depth_at(uv);
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;

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
    li.nightw = vec3<f32>(0.03, 0.045, 0.075) * (1.0 - smoothstep(0.1, 0.55, li.day));

    let pj = vec2<u32>(floor(in.position.xy));
    let j = f32(pcg(pj.x * 0x9E3779B1u ^ pcg(pj.y * 0x85EBCA6Bu ^ u32(time * 60.0))) & 0xFFFFu) / 65536.0;

    let cs = cs0;
    let sf = ts_front(time);
    let dim = ts_dim(cs, time);
    // (the water sees the same dying sky)
    li.skyl = li.skyl * (1.0 - 0.55 * dim);
    li.fogl = li.fogl * (1.0 - 0.6 * dim);
    li.amb = li.amb * (1.0 - 0.5 * dim);
    // ---- the light going as it comes: the world dims and cools, and the sky over it goes the colour of a bruise ----------
    if (sky) {
        // (towards the wave the dark climbs the sky first)
        let tow = saturate(0.5 - 0.5 * dot(rd.xz, g.m));
        let band = (0.5 + 0.5 * tow) * (1.0 - smoothstep(0.0, 0.5 + 0.35 * dim, rd.y - 0.15 * tow));
        let lum = luminance(col);
        let storm = mix(vec3<f32>(lum), vec3<f32>(0.2, 0.25, 0.3) * (lum + 0.05) * 2.0, 0.75);
        col = mix(col, storm * 0.6, saturate(dim * 1.1) * (0.55 + 0.45 * band));
    } else {
        let lum = luminance(col);
        col = mix(col, mix(vec3<f32>(lum), col, 0.6) * vec3<f32>(0.62, 0.68, 0.76), saturate(dim * 1.35));
        // (the wave's own shadow on the land ahead of it: towards the sun the ray climbs over it or doesn't)
        let pl = ro + rel;
        let ps = dot(pl.xz, g.m);
        let ahead = ps - (sf + 0.0);
        if (ahead > -60.0 && ahead < 900.0) {
            let Ls = dot(li.L.xz, g.m);
            var sh = 0.0;
            if (Ls < -0.02) {
                let tc = (ahead + 60.0) / -Ls;
                let top = TS_A * ts_env(ps - ahead, dot(pl.xz, g.n), g) - TS_SEA + 20.0;
                sh = 1.0 - smoothstep(top - 40.0, top + 40.0, pl.y + tc * li.L.y);
            }
            // (and the sky itself shut out close under it, whatever the sun)
            let close = 1.0 - smoothstep(0.0, 170.0, ahead);
            let dark = max(sh * 0.72, close * 0.55) * (0.4 + 0.6 * li.day);
            col = col * (1.0 - dark);
        }
        // (what the water has been over, as it comes out from under it)
        let pu = dot(pl.xz, g.n);
        let tau_p = time - ts_arr(ps, pu, g.sd);
        if (tau_p > 1.0 && pl.y < TS_A * ts_env(ps, pu, g) - TS_SEA) {
            col = ts_wet(col, pl, rel, uv, rd, time, 1.0 - smoothstep(35.0, 41.5, time), g, li);
        }
    }

    if (inw) {
        col = ts_under(ro, rd, scene_len, scene, time, el, g, li, j, sky);
        return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
    }
    let h = ts_march(ro, rd, 0.0, min(scene_len, 6000.0), time, g, j);
    var t_front = min(scene_len, 6000.0);
    if (h.hit) {
        t_front = h.t;
        let pw = ro + rd * h.t;
        // (how far over the land it is: the land's map under the wave, the scene's own depth for the shallows)
        let hg0 = pw.y - ts_ground(dot(pw.xz, g.m), dot(pw.xz, g.n));
        var hg = hg0;
        var hgs = 1.0e4;
        if (!sky && rd.y < -0.02) {
            hgs = max(scene_len - h.t, 0.0) * -rd.y;
        }
        // (the wave, or what is left of it going back)
        let ps_h = dot(pw.xz, g.m);
        let trh = TS_FACE / ts_vel(ps_h);
        let dr = max(smoothstep(0.0, 0.12, ts_x(time, ps_h, g)), smoothstep(trh + 0.8, trh + 3.0, time - ts_arr(ps_h, dot(pw.xz, g.n), g.sd)));
        var sf_c = vec3<f32>(0.0);
        if (dr < 1.0) {
            sf_c = ts_surface(pw, rd, h.t, time, g, li, hg, j);
        }
        if (dr > 0.0) {
            sf_c = mix(sf_c, ts_torrent(pw, rd, h.t, time, g, li, hgs), dr);
        }
        // (thin water over the land lets it show through, tinted: the film the drain leaves, a shallow edge)
        var a = 1.0;
        var under = col;
        if (!sky) {
            let path = max(scene_len - h.t, 0.0);
            a = 1.0 - exp(-path / 5.0);
            under = col * exp(-vec3<f32>(0.10, 0.12, 0.16) * path);
        }
        col = mix(under, sf_c, a);
        // (what the wave has swept up, riding its face and its foam)
        let deb = ts_deb_ext(ro, rd, ro + rd * h.t, h.t, time, g, li);
        var t_see = h.t;
        if (deb.hit) {
            col = deb.rgb;
            t_see = deb.t;
        }
        // (the haze of the distance, thin: the wave is a dark mass, not a pale one)
        let haze = 1.0 - exp(-t_see * 0.00013);
        col = mix(col, li.fogl * 0.72 * (1.0 - 0.5 * dim), haze * 0.75);
    }
    let sp = ts_spray(ro, rd, 0.0, t_front, time, g, li, j);
    col = col * sp.a + sp.rgb;
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return tsunami(in);
}
