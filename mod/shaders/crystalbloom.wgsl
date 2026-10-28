// Orbital Laser's post pass for the Crystal Bloom (laser 7). Like the Planet Killer's, the mod builds it from
// shaders/strike.wgsl up to its fs_main (the helpers: the noise, ray_seg, rot_axis, project_rel, mh) less the other lasers'
// own functions, followed by this file, and sets it for a crystal bloom strike only. Validate with tools/check-shader.sh.

// ---- laser 7: the crystal bloom ---------------------------------------------------------------------------------
// The land round the target wakes: a deep hum, light seeping up through cracks spreading out over it, the ground heaving
// where the first crystals are coming. They punch up out of it one after another, each breaking the ground in a burst of
// earth and rock, catching, straining, then surging up; the heart comes last, in the middle. Then the bloom: a wave of
// spires running out over the land in clusters, splayed, each growing from a shard to a tower, the tallest hundreds of
// blocks. They are solid crystal: faceted, lit from inside, catching the sky, throwing coloured light on the land and the
// clouds. They resonate: light runs up them all together, faster and faster, the air shimmers round them, shards break
// off and orbit them; a breath; and they detonate: a flash of colour, the spires bursting into a storm of shards and
// glitter, a prismatic shock running out. What is left is real blocks: the geode crater, the stumps, the shards strewn
// over the land. strike.rs places the same spires (cb_spire), breaks them at the same heights (cb_break), throws the same
// shards (cb_frag) and digs the crater when this pass opens it (cb_dig_t): keep the CB_* and cb_* in step.

const CB_N: i32 = 46;              // the spires: 0..4 the first shards, 5 the heart, then ten clusters of four
const CB_LEADS: i32 = 6;
const CB_FIELD: f32 = 150.0;       // how far out they stand
const CB_SINK: f32 = 40.0;         // how far under the target's ground each runs down
const CB_STUMP: f32 = 0.5;         // its stump as wide as this of it (its heart: the rest of it shatters)
const CB_PUNCH0: f32 = 3.5;        // the first shard breaks the ground, the next CB_PUNCH_DT after, the heart last
const CB_PUNCH_DT: f32 = 0.62;
const CB_BULGE: f32 = 0.7;         // the ground over each heaves for this long before it breaks
const CB_STRUGGLE: f32 = 0.9;      // it struggles there, then surges up over CB_SURGE
const CB_SURGE: f32 = 1.5;
const CB_BLOOM0: f32 = 7.6;        // the bloom sets out from the middle, reaching CB_FIELD CB_BLOOM_V later
const CB_BLOOM_V: f32 = 4.6;
const CB_RES: f32 = 14.0;          // they resonate from here,
const CB_ORBIT: f32 = 15.6;        // shards breaking off and orbiting them from here,
const CB_DET: f32 = 22.0;          // and detonate
const CB_END: f32 = 31.0;          // the light gone (the strike runs 32 s)
const CB_G: f32 = 22.0;            // how hard they fall
const CB_ORBITERS: i32 = 32;
const CB_BOWL: f32 = 88.0;         // the crater (strike.rs's cb_depth): CB_BOWL round, CB_BOWL_D deep, a well CB_WELL round
const CB_BOWL_D: f32 = 28.0;
const CB_WELL: f32 = 10.0;
const CB_DIG_V: f32 = 70.0;        // dug from the middle out at this many blocks a second (cb_dig_t)
const CB_CRACKS: i32 = 9;          // fissures running out from the crater to CB_CRACK_R, opening as the shock reaches them
const CB_CRACK_R: f32 = 205.0;
const CB_SHOCK_V: f32 = 170.0;

// ---- where everything is -------------------------------------------------------------------------------------------
// Spire i: x, z its foot off the target, y when it sets off (breaks the ground), w how tall it grows.
fn cb_place(i: i32, seed: f32) -> vec4<f32> {
    let s = u32(seed);
    let u = u32(i);
    if (i < 5) {
        // the first shards, round the middle
        let a = mh(0u, s, 1u) * TAU + f32(i) * 2.39996 + (mh(u, s, 2u) - 0.5) * 0.5;
        let r = 42.0 + 34.0 * mh(u, s, 3u);
        let t = CB_PUNCH0 + f32(i) * CB_PUNCH_DT + (mh(u, s, 4u) - 0.5) * 0.12;
        return vec4<f32>(cos(a) * r, sin(a) * r, t, 170.0 + 80.0 * mh(u, s, 5u));
    }
    if (i == 5) {
        return vec4<f32>((mh(u, s, 3u) - 0.5) * 4.0, (mh(u, s, 4u) - 0.5) * 4.0, CB_PUNCH0 + 5.0 * CB_PUNCH_DT + 0.1, 330.0);
    }
    // a cluster of four: the first its tallest, the others round it
    let c = (i - 6) / 4;
    let j = (i - 6) % 4;
    let fc = f32(c);
    let ac = mh(7u, s, 6u) * TAU + fc * 2.39996 + (mh(u32(c), s, 7u) - 0.5) * 0.4;
    let rc = 34.0 + 108.0 * sqrt((fc + 0.5) / 10.0) + (mh(u32(c), s, 8u) - 0.5) * 16.0;
    var x = cos(ac) * rc;
    var z = sin(ac) * rc;
    if (j > 0) {
        let aj = ac + (f32(j) - 2.0) * 1.9 + (mh(u, s, 9u) - 0.5) * 1.2;
        let dj = 7.0 + 11.0 * mh(u, s, 10u);
        x = x + cos(aj) * dj;
        z = z + sin(aj) * dj;
    }
    let r = length(vec2<f32>(x, z));
    let big = select(0.25 + 0.45 * mh(u, s, 11u), 0.75 + 0.25 * mh(u, s, 11u), j == 0);
    let h = (36.0 + 230.0 * big * big) * (1.0 - 0.45 * saturate(r / CB_FIELD));
    let t = CB_BLOOM0 + CB_BLOOM_V * saturate(r / CB_FIELD) + 0.35 * mh(u, s, 12u) + 0.12 * f32(j);
    return vec4<f32>(x, z, t, h);
}
// Spire i's shape: x its radius (the apothem of its hexagon at its foot), y how far it leans off upright (radians),
// z which way (radians round from +x), w how far it is turned about its own axis.
fn cb_form(i: i32, seed: f32, p: vec4<f32>) -> vec4<f32> {
    let s = u32(seed);
    let u = u32(i);
    let out = atan2(p.y, p.x);
    if (i == 5) {
        return vec4<f32>(30.0, 0.035, mh(u, s, 13u) * TAU, mh(u, s, 14u) * TAU);
    }
    var r = 5.0 + p.w * 0.08 + 3.0 * mh(u, s, 15u);
    var lean = 0.14 + 0.36 * mh(u, s, 16u);
    var hd = out + (mh(u, s, 17u) - 0.5) * 1.3;
    if (i < 5) {
        r = 19.0 + 6.0 * mh(u, s, 15u);
        lean = 0.08 + 0.14 * mh(u, s, 16u);
    } else if ((i - 6) % 4 > 0) {
        // (the smaller of a cluster splayed out from its tallest)
        let c = (i - 6) / 4;
        let m = cb_place(6 + c * 4, seed);
        hd = atan2(p.y - m.y, p.x - m.x) + (mh(u, s, 17u) - 0.5) * 0.7;
        lean = 0.3 + 0.45 * mh(u, s, 16u);
    }
    return vec4<f32>(r, lean, hd, mh(u, s, 14u) * TAU);
}
// Where spire i breaks as they burst: x the height up its axis (0: it shatters whole), z, w the break's tilt across it.
fn cb_break(i: i32, seed: f32, ph: f32) -> vec4<f32> {
    let s = u32(seed);
    let u = u32(i);
    if (i == 5) {
        return vec4<f32>(0.0);
    }
    // (the first shards, each cluster's tallest and a few others leave a stump; the rest shatter whole)
    if (!(i < CB_LEADS || (i - 6) % 4 == 0 || mh(u, s, 26u) < 0.3)) {
        return vec4<f32>(0.0);
    }
    let h = clamp(ph * (0.06 + 0.14 * mh(u, s, 18u)), 6.0, 34.0);
    let ta = mh(u, s, 19u) * TAU;
    let tl = 0.25 + 0.55 * mh(u, s, 20u);
    return vec4<f32>(h, 0.0, cos(ta) * tl, sin(ta) * tl);
}
// Its axis (from its lean).
fn cb_axis(f: vec4<f32>) -> vec3<f32> {
    return vec3<f32>(sin(f.y) * cos(f.z), cos(f.y), sin(f.y) * sin(f.z));
}
// Its frame: e1 and e2 across its axis, turned by f.w.
fn cb_frame(a: vec3<f32>, rot: f32) -> mat2x3<f32> {
    let u = normalize(cross(a, vec3<f32>(0.0, 0.0, 1.0)));
    let w = cross(u, a);
    let c = cos(rot);
    let s = sin(rot);
    return mat2x3<f32>(u * c + w * s, -u * s + w * c);
}
// Its tip's apex, off its axis a little (x, z in its frame, of its radius at the top).
fn cb_apex(i: i32, seed: f32) -> vec2<f32> {
    let s = u32(seed);
    return (vec2<f32>(mh(u32(i), s, 21u), mh(u32(i), s, 22u)) - 0.5) * 0.7;
}
// How far a spire `s` seconds after it set off has grown (x, of its height) and how hard it shudders (y, blocks). The
// first shards break the ground, catch, strain and give twice, gathering, then surge up out of it, a little past their
// height, and settle; the bloom's grow in two or three pushes, each easing off, the last slowest.
fn cb_ease(x: f32) -> f32 {
    let y = 1.0 - saturate(x);
    return 1.0 - y * y * y;
}
fn cb_jolt(s: f32, at: f32, k: f32) -> f32 {
    return select(0.0, exp(-(s - at) * k), s > at);
}
fn cb_grow(i: i32, s: f32, ph: f32) -> vec2<f32> {
    if (s <= 0.0) {
        return vec2<f32>(0.0);
    }
    if (i < CB_LEADS) {
        var g = 0.0;
        if (s < 0.1) {
            g = 0.06 * cb_ease(s / 0.1);
        } else if (s < 0.34) {
            g = mix(0.06, 0.068, (s - 0.1) / 0.24);
        } else if (s < 0.42) {
            g = mix(0.068, 0.1, cb_ease((s - 0.34) / 0.08));
        } else if (s < 0.66) {
            g = mix(0.1, 0.108, (s - 0.42) / 0.24);
        } else if (s < 0.74) {
            g = mix(0.108, 0.14, cb_ease((s - 0.66) / 0.08));
        } else if (s < CB_STRUGGLE) {
            g = 0.14 - 0.006 * smoothstep(0.74, CB_STRUGGLE, s);
        } else {
            let x = (s - CB_STRUGGLE) / CB_SURGE;
            if (x < 1.0) {
                g = mix(0.134, 1.03, 1.0 - pow(1.0 - x, 2.6));
            } else {
                let y = saturate((x - 1.0) * 1.5);
                g = mix(1.03, 1.0, y * y * (3.0 - 2.0 * y));
            }
        }
        let strain = smoothstep(0.75, CB_STRUGGLE, s) * f32(s < CB_STRUGGLE);
        let sh = 0.25 * f32(s < CB_STRUGGLE) + 1.6 * cb_jolt(s, 0.0, 9.0) + 1.2 * cb_jolt(s, 0.34, 10.0)
            + 1.3 * cb_jolt(s, 0.66, 10.0) + 1.4 * strain + 2.4 * cb_jolt(s, CB_STRUGGLE, 3.0);
        return vec2<f32>(g, sh);
    }
    // the bloom: three pushes, the first sharp (it breaks the ground), each easing off
    let d = 1.3 + 2.2 * saturate(ph / 260.0);
    let x = s / d;
    let g = 0.3 * cb_ease(x / 0.12) + 0.4 * cb_ease((x - 0.18) / 0.3) + 0.3 * cb_ease((x - 0.55) / 0.45);
    let sh = 0.5 * cb_jolt(s, 0.0, 8.0) + 0.3 * cb_jolt(s, 0.18 * d, 9.0) + 0.2 * cb_jolt(s, 0.55 * d, 9.0);
    return vec2<f32>(g, sh * (0.5 + ph / 120.0));
}
// When the crater `r` out has been dug (strike.rs's cb_dig_t, a chunk column at a time from the middle out), and how
// far the land at `rel2` has really been opened by `time`: after the chunk round it has been dug (strike.rs may put one
// off by up to CB_SLACK), its edge wandering.
fn cb_dig_t(r: f32) -> f32 {
    return CB_DET + 0.1 + r / CB_DIG_V;
}
fn cb_open(rel2: vec2<f32>, r: f32, time: f32) -> f32 {
    let n = gnoise2(rel2 * 0.05) - 0.5;
    return smoothstep(0.0, 0.25, time - cb_dig_t(r + 20.0 + 6.0 * n));
}
// When the fissures open `r` out (strike.rs's cb_crack_t): as the shock reaches them, not before the land over them
// has been cleared.
fn cb_crack_t(r: f32) -> f32 {
    let shock = CB_DET + 0.2 + r / CB_SHOCK_V;
    return max(shock, cb_dig_t(r + 20.0) + 0.05);
}
// Fissure i: x its heading out from the target, y how far out it runs.
fn cb_crack(i: i32, seed: f32) -> vec2<f32> {
    let s = u32(seed);
    let a = (f32(i) + 0.7 * mh(u32(i), s, 31u)) * TAU / f32(CB_CRACKS) + mh(99u, s, 32u) * TAU;
    return vec2<f32>(a, CB_BOWL + 50.0 + (CB_CRACK_R - CB_BOWL - 50.0) * mh(u32(i), s, 33u));
}

// ---- the crystal: a hexagonal prism drawing in a little up its length, under a six-faced tip, its foot run down into
// the ground; after the burst its stump, cut across at the break. Convex: every view ray meets it in one stretch, found
// exactly, plane by plane, with the face it enters by (its facets are real faces).
struct Crystal {
    B: vec3<f32>,      // its foot on the ground (camera-relative)
    a: vec3<f32>,      // its axis
    e1: vec3<f32>,
    e2: vec3<f32>,
    R: f32,            // its radius at its foot (the hexagon's apothem) and at the top of its sides
    Rt: f32,
    Hb: f32,           // where its sides end and its tip begins, up its axis, and how tall the tip is
    tip: f32,
    apex: vec2<f32>,
    cut: vec4<f32>,    // its break: inside where y + x * cut.y + z * cut.z <= cut.x (cut.w 1 when there is one)
    hue: f32,
    skew: f32,         // how uneven its faces are
    g: f32,            // how far grown
    s: f32,            // since it set off
}
const CB_DIRS = array<vec2<f32>, 6>(vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.8660254), vec2<f32>(-0.5, 0.8660254),
    vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.8660254), vec2<f32>(0.5, -0.8660254));
// Plane k of a crystal (in its frame): xyz its outward normal (not normalised), w: inside where dot(n, p) <= w.
fn cb_plane(c: Crystal, k: i32) -> vec4<f32> {
    if (k < 6) {
        let th = f32(k) * 1.0471976;
        let cs = vec2<f32>(cos(th), sin(th));
        let tp = (c.R - c.Rt) / max(c.Hb + CB_SINK, 1.0);
        // (its faces not all as wide: each side stands a little in or out)
        let sk = 1.0 + c.skew * (fract(c.hue * 91.7 + f32(k) * 0.618) - 0.5);
        return vec4<f32>(cs.x, tp, cs.y, (c.R - tp * CB_SINK) * sk);
    }
    if (k < 12) {
        let th = f32(k - 6) * 1.0471976;
        let cs = vec2<f32>(cos(th), sin(th));
        let m = (c.Rt - dot(cs, c.apex) * c.Rt) / max(c.tip, 0.5);
        return vec4<f32>(cs.x, m, cs.y, c.Rt + m * c.Hb);
    }
    if (k == 12) {
        return vec4<f32>(0.0, -1.0, 0.0, CB_SINK);
    }
    return vec4<f32>(c.cut.y, 1.0, c.cut.z, select(1.0e7, c.cut.x, c.cut.w > 0.5));
}
// The view ray (o, d in the crystal's frame) through it: x where it goes in (under 0: it misses), y where it comes out,
// z the face it goes in by.
fn cb_hit(c: Crystal, o: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    var t0 = -1.0e9;
    var t1 = 1.0e9;
    var kin = 0;
    for (var k = 0; k < 14; k = k + 1) {
        let pl = cb_plane(c, k);
        let dn = dot(pl.xyz, d);
        let num = pl.w - dot(pl.xyz, o);
        if (abs(dn) < 1.0e-7) {
            if (num < 0.0) {
                return vec3<f32>(-1.0, -1.0, 0.0);
            }
            continue;
        }
        let t = num / dn;
        if (dn < 0.0) {
            if (t > t0) {
                t0 = t;
                kin = k;
            }
        } else {
            t1 = min(t1, t);
        }
    }
    if (t0 > t1 || t1 < 0.0) {
        return vec3<f32>(-1.0, -1.0, 0.0);
    }
    return vec3<f32>(t0, t1, f32(kin));
}
// From inside it at q along d: how far to where it comes out (x) and the face it comes out by (y).
fn cb_exit(c: Crystal, q: vec3<f32>, d: vec3<f32>) -> vec2<f32> {
    var t1 = 1.0e9;
    var kout = 0;
    for (var k = 0; k < 14; k = k + 1) {
        let pl = cb_plane(c, k);
        let dn = dot(pl.xyz, d);
        if (dn > 1.0e-7) {
            let t = (pl.w - dot(pl.xyz, q)) / dn;
            if (t < t1) {
                t1 = t;
                kout = k;
            }
        }
    }
    return vec2<f32>(max(t1, 0.0), f32(kout));
}
// Spire i at `time` (cam the eye, tgt the target): its pose, how far it has grown, and its break once it has burst.
fn cb_crystal(i: i32, seed: f32, time: f32, crel: vec3<f32>) -> Crystal {
    var c: Crystal;
    let p = cb_place(i, seed);
    let f = cb_form(i, seed, p);
    let gr = cb_grow(i, time - p.z, p.w);
    let fi = f32(i);
    c.s = time - p.z;
    c.g = gr.x;
    // (it shudders as it struggles and as each push takes it)
    let sh = vec3<f32>(sin(time * 41.0 + fi * 1.3) + 0.5 * sin(time * 73.0 + fi), 0.0, sin(time * 37.0 + fi * 2.1) + 0.5 * sin(time * 67.0 + fi * 0.7)) * gr.y * 0.35;
    c.B = crel + vec3<f32>(p.x, 0.0, p.y) + sh;
    // (the first shards lean a little more while they struggle, and straighten as they surge up)
    var lean = f.y;
    if (i < CB_LEADS) {
        lean = f.y * (1.0 + 0.6 * (1.0 - smoothstep(CB_STRUGGLE, CB_STRUGGLE + 0.8, c.s))) + 0.003 * gr.y;
    }
    c.a = cb_axis(vec4<f32>(f.x, lean, f.z, f.w));
    let fr = cb_frame(c.a, f.w);
    c.e1 = fr[0];
    c.e2 = fr[1];
    let H = p.w * gr.x;
    let w = 0.38 + 0.62 * saturate(gr.x * 1.15);
    c.R = f.x * w;
    c.Rt = c.R * 0.8;
    c.tip = min(c.Rt * (1.3 + 1.5 * mh(u32(i), u32(seed), 24u)), H + CB_SINK * 0.5);
    c.skew = 0.35;
    c.Hb = H - c.tip;
    c.apex = cb_apex(i, seed);
    c.cut = vec4<f32>(0.0);
    c.hue = fract(0.13 * fi + mh(u32(i), u32(seed), 23u) * 0.18 + atan2(p.y, p.x) / TAU * 0.6);
    return c;
}
// A point (camera-relative) or a direction in a crystal's frame, and back.
fn cb_to(c: Crystal, x: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(dot(x, c.e1), dot(x, c.a), dot(x, c.e2));
}
fn cb_from(c: Crystal, v: vec3<f32>) -> vec3<f32> {
    return c.e1 * v.x + c.a * v.y + c.e2 * v.z;
}

// ---- colour ---------------------------------------------------------------------------------------------------------
// The crystals' colours round the wheel: violet, magenta, rose, ice, cyan, deep blue.
fn cb_hue(x: f32) -> vec3<f32> {
    var pal = array<vec3<f32>, 6>(
        vec3<f32>(0.58, 0.32, 1.0), vec3<f32>(0.92, 0.32, 0.92), vec3<f32>(1.0, 0.5, 0.75),
        vec3<f32>(0.8, 0.86, 1.0), vec3<f32>(0.3, 0.8, 1.0), vec3<f32>(0.32, 0.38, 1.0));
    let h = fract(x) * 6.0;
    let i = i32(floor(h));
    let f = smoothstep(0.0, 1.0, h - floor(h));
    return mix(pal[i], pal[(i + 1) % 6], f);
}
// A spectrum, for the prismatic light: red through violet as x runs 0 to 1.
fn cb_spectrum(x: f32) -> vec3<f32> {
    let h = saturate(x);
    return saturate(vec3<f32>(1.5 - abs(h - 0.15) * 4.5, 1.5 - abs(h - 0.45) * 4.5, 1.5 - abs(h - 0.78) * 4.5)) + vec3<f32>(0.5, 0.0, 0.5) * smoothstep(0.85, 1.0, h);
}
// What a facet of crystal catches of the world in direction v: the sky (darkened as the strike darkens it), the sun, a
// bright horizon, the land under it dark.
fn cb_env(v: vec3<f32>, sky_c: vec3<f32>, sun: vec3<f32>, day: f32, dark: f32, glow: vec3<f32>) -> vec3<f32> {
    let up = v.y;
    let zen = mix(vec3<f32>(0.01, 0.012, 0.03), sky_c * 0.8, day) * (1.0 - 0.6 * dark);
    let hor = mix(vec3<f32>(0.03, 0.035, 0.07), sky_c * 1.25 + vec3<f32>(0.15), day) * (1.0 - 0.5 * dark);
    var e = mix(hor, zen, smoothstep(0.0, 0.6, up));
    let ground = vec3<f32>(0.05, 0.05, 0.045) * (0.2 + 0.8 * day) * (1.0 - 0.5 * dark) + glow * 0.5;
    e = mix(e, ground, smoothstep(0.02, -0.12, up));
    let sd = max(dot(v, sun), 0.0);
    e = e + vec3<f32>(6.0, 5.6, 5.0) * pow(sd, 900.0) * day + vec3<f32>(0.6, 0.55, 0.5) * pow(sd, 18.0) * day * 0.4;
    return e;
}
fn cb_occ(t: f32, scene_len: f32, sky: bool, cloud: bool) -> f32 {
    return select(select(0.0, 0.5, cloud), 1.0, sky || t < scene_len);
}

// ---- small shards: an octahedron stretched along one axis, turned by `ax`, `ang`; how far along the view ray it is met
// (x, under 0 a miss) and the face's normal (yzw). C camera-relative, `sz` its half-size across, `ln` along.
fn cb_shard(rd: vec3<f32>, C: vec3<f32>, sz: f32, ln: f32, ax: vec3<f32>, ang: f32, tmax: f32) -> vec4<f32> {
    let tc = dot(C, rd);
    let bound = max(sz, ln) * 1.05;
    let dc2 = dot(C, C) - tc * tc;
    if (tc < 0.0 || dc2 > bound * bound || tc - bound > tmax) {
        return vec4<f32>(-1.0);
    }
    let o = rot_axis(-C, ax, -ang);
    let d = rot_axis(rd, ax, -ang);
    var t0 = -1.0e9;
    var t1 = 1.0e9;
    var nin = vec3<f32>(0.0, 1.0, 0.0);
    for (var k = 0; k < 8; k = k + 1) {
        let n = vec3<f32>(select(-1.0, 1.0, (k & 1) == 0) / sz, select(-1.0, 1.0, (k & 2) == 0) / ln, select(-1.0, 1.0, (k & 4) == 0) / sz);
        let dn = dot(n, d);
        let num = 1.0 - dot(n, o);
        if (abs(dn) < 1.0e-8) {
            continue;
        }
        let t = num / dn;
        if (dn < 0.0) {
            if (t > t0) {
                t0 = t;
                nin = n;
            }
        } else {
            t1 = min(t1, t);
        }
    }
    if (t0 > t1 || t0 < 0.0 || t0 > tmax) {
        return vec4<f32>(-1.0);
    }
    return vec4<f32>(t0, normalize(rot_axis(nin, ax, ang)));
}
// The hashes for the spires' chunks and the rest (strike.rs's cb_h3).
fn cb_h3(f: i32, k: u32, seed: f32) -> vec3<f32> {
    return vec3<f32>(pcg3d(vec3<u32>(u32(f), k, u32(seed)))) * (1.0 / 4294967295.0);
}

// ---- the break: each spire fractures into chunks as they burst --------------------------------------------------
// Each spire (above its break, or from the ground if it shatters whole) is cut across its length at CB_NSEG uneven
// heights by planes tilted every which way, so its pieces are slabs and wedges, long splinters and short fragments;
// the wider ones split again down their length. Each piece keeps the spire's own faces (it is the spire, clipped by
// its cuts) and is thrown out from where it was, tumbling as its size allows, and comes down where strike.rs builds it
// in blocks (cb_chunk there): keep the two in step.
fn cb_nseg(R: f32, span: f32) -> i32 {
    return clamp(i32(span / (8.0 + R * 1.0)), 2, 6);
}
// How high up its axis cut k of spire i is (0 its foot, nseg its top).
fn cb_cut_h(i: i32, k: i32, nseg: i32, h0: f32, span: f32, seed: f32) -> f32 {
    var tot = 0.0;
    var at = 0.0;
    for (var j = 0; j < 6; j = j + 1) {
        if (j >= nseg) {
            break;
        }
        let w = 0.45 + cb_h3(i * 16 + j, 501u, seed).x;
        if (j < k) {
            at = at + w;
        }
        tot = tot + w;
    }
    return h0 + span * at / tot;
}
// Cut k as a plane in the spire's frame: inside (below it) where dot(xyz, q) <= w.
fn cb_cut_plane(i: i32, k: i32, nseg: i32, h0: f32, span: f32, R: f32, seed: f32) -> vec4<f32> {
    let h = cb_cut_h(i, k, nseg, h0, span, seed);
    let t = (cb_h3(i * 16 + k, 502u, seed).xy - 0.5) * min(1.1, 0.4 * span / f32(nseg) / R);
    return vec4<f32>(t.x, 1.0, t.y, h);
}
// The crater's depth r out, as a chunk falling in it meets it (strike.rs's cb_bowl_dep).
fn cb_bowl_dep(r: f32) -> f32 {
    let u = saturate(r / CB_BOWL);
    return select(0.0, CB_BOWL_D * pow(1.0 - u * u, 0.75), r < CB_BOWL);
}
struct CbChunk {
    C0: vec3<f32>,     // its middle as it breaks off (off the target)
    v: vec3<f32>,      // how fast it is thrown
    spin: vec4<f32>,   // the axis it tumbles about, and how fast
    lo: vec4<f32>,     // its cuts in the spire's frame: inside where dot(xyz, q) <= w
    hi: vec4<f32>,
    sp: vec4<f32>,
    tl: f32,           // when it comes down (after the burst), and when it is built in blocks there
    tp: f32,
    L: f32,            // how long and how wide it is
    wid: f32,
}
// Piece (k, half) of spire i (its foot F off the target, its frame a, e1, e2, radius R, height H; its break brk).
fn cb_chunk(i: i32, k: i32, half: i32, seed: f32, F: vec3<f32>, a: vec3<f32>, e1: vec3<f32>, e2: vec3<f32>, R: f32, H: f32, brk: vec4<f32>) -> CbChunk {
    var o: CbChunk;
    let h0 = select(0.0, brk.x, brk.x > 0.5);
    let span = H - h0;
    let nseg = cb_nseg(R, span);
    let split = R > 7.0 && k < nseg - 1;
    if (k == 0) {
        if (brk.x > 0.5) {
            o.lo = vec4<f32>(-brk.z, -1.0, -brk.w, -brk.x);
        } else {
            o.lo = -cb_cut_plane(i, 0, nseg, h0, span, R, seed);
        }
    } else {
        o.lo = -cb_cut_plane(i, k, nseg, h0, span, R, seed);
    }
    o.hi = select(cb_cut_plane(i, k + 1, nseg, h0, span, R, seed), vec4<f32>(0.0, 1.0, 0.0, 1.0e7), k == nseg - 1);
    let ylo = cb_cut_h(i, k, nseg, h0, span, seed);
    let yhi = cb_cut_h(i, k + 1, nseg, h0, span, seed);
    var ym = (ylo + yhi) * 0.5;
    if (k == nseg - 1) {
        ym = ylo + (yhi - ylo) * 0.4;
    }
    var cx = vec2<f32>(0.0);
    o.sp = vec4<f32>(0.0, 0.0, 0.0, 1.0e7);
    o.wid = R;
    if (split) {
        let hs = cb_h3(i * 16 + k, 503u, seed);
        let ph = hs.x * TAU;
        let n = vec2<f32>(cos(ph), sin(ph));
        let w = (hs.y - 0.5) * R * 0.5;
        o.sp = select(vec4<f32>(n.x, 0.0, n.y, w), vec4<f32>(-n.x, 0.0, -n.y, -w), half == 1);
        cx = n * (w + select(-1.0, 1.0, half == 1) * R * 0.45);
        o.wid = R * 0.6;
    }
    o.L = yhi - ylo;
    o.C0 = F + e1 * cx.x + a * ym + e2 * cx.y;
    let f = i * 16 + k * 2 + half;
    let hm = cb_h3(f, 504u, seed);
    let hsn = cb_h3(f, 505u, seed);
    let out = normalize(vec2<f32>(o.C0.x + 0.01, o.C0.z));
    let az = (hm.y - 0.5) * 0.9;
    let o2 = vec2<f32>(out.x * cos(az) - out.y * sin(az), out.x * sin(az) + out.y * cos(az));
    let vy = 6.0 + 17.0 * hm.z;
    let mass = 1.4 - 0.5 * saturate(o.wid * o.L / 600.0);
    let y0 = max(o.C0.y, 0.0);
    let tl0 = (vy + sqrt(vy * vy + 2.0 * CB_G * y0)) / CB_G;
    let vh = min((11.0 + 26.0 * hm.x + y0 * 0.08) * mass, max(225.0 - length(o.C0.xz), 10.0) / tl0);
    let r1 = length(o.C0.xz + o2 * vh * tl0);
    o.tl = (vy + sqrt(vy * vy + 2.0 * CB_G * (y0 + cb_bowl_dep(r1)))) / CB_G;
    let rl = length(o.C0.xz + o2 * vh * o.tl);
    o.tp = select(o.tl, max(o.tl, cb_dig_t(rl + 20.0) + 0.15 - CB_DET), rl < 150.0);
    o.v = vec3<f32>(o2.x * vh, vy, o2.y * vh);
    let rate = (0.8 + 2.6 * hsn.x) * 14.0 / (14.0 + o.L * 0.35 + o.wid * 0.25) * select(-1.0, 1.0, hsn.y > 0.5);
    o.spin = vec4<f32>(normalize(hsn - 0.5 + vec3<f32>(0.0, 0.01, 0.0)), rate);
    return o;
}
// Where a piece is `dt` after the burst (off the target) and how far it has turned: flying, then come down and driven
// a little into the ground, lying there until it is built.
fn cb_chunk_at(o: CbChunk, dt: f32) -> vec4<f32> {
    let tf = min(dt, o.tl);
    var P = o.C0 + o.v * tf - vec3<f32>(0.0, 0.5 * CB_G * tf * tf, 0.0);
    if (dt > o.tl) {
        let vl = o.v - vec3<f32>(0.0, CB_G * o.tl, 0.0);
        P = P + normalize(vl) * 5.0 * min(dt - o.tl, 0.2);
    }
    return vec4<f32>(P, o.spin.w * tf);
}
// The view ray through a crystal's own faces (but its cut) and three more planes: x in, y out, z the face it goes in
// by (13 and on: a broken face).
fn cb_hit3(c: Crystal, o: vec3<f32>, d: vec3<f32>, x0: vec4<f32>, x1: vec4<f32>, x2: vec4<f32>) -> vec3<f32> {
    var t0 = -1.0e9;
    var t1 = 1.0e9;
    var kin = 0;
    for (var k = 0; k < 16; k = k + 1) {
        var pl: vec4<f32>;
        if (k < 13) {
            pl = cb_plane(c, k);
        } else if (k == 13) {
            pl = x0;
        } else if (k == 14) {
            pl = x1;
        } else {
            pl = x2;
        }
        let dn = dot(pl.xyz, d);
        let num = pl.w - dot(pl.xyz, o);
        if (abs(dn) < 1.0e-7) {
            if (num < 0.0) {
                return vec3<f32>(-1.0, -1.0, 0.0);
            }
            continue;
        }
        let t = num / dn;
        if (dn < 0.0) {
            if (t > t0) {
                t0 = t;
                kin = k;
            }
        } else {
            t1 = min(t1, t);
        }
    }
    if (t0 > t1 || t1 < 0.0) {
        return vec3<f32>(-1.0, -1.0, 0.0);
    }
    return vec3<f32>(t0, t1, f32(kin));
}

// ---- dust: what each crystal throws up as it breaks the ground and comes up out of it -----------------------------
// Round each of the first shards, the heart and each of the bloom's clusters (a "source": its foot, when it broke
// through, how big its dust is): a burst of earth as it breaks the ground (again as it surges, and at each push), a
// billowing column climbing with it (cb_rise), a surge rolling out over the land (cb_surge); the bloom's wall of dust
// running out ahead of its spires; and the haze all of it leaves, drifting and thinning. Each part is marched in a few
// steps over where the view ray crosses it, up to whatever is nearer (the land, a spire), and the parts are put
// together whatever their order (a weighted blend: they are all dust).
const CB_RISE_END: f32 = 6.0;       // a source's column gone this long after it surged (the haze carries on)
const CB_SURGE_END: f32 = 6.0;      // its surge gone (the bloom's soon, taken up into its wall)
const CB_SURGE_BLOOM: f32 = 3.0;
struct CbDL {
    crel: vec3<f32>,
    Ld: vec3<f32>,
    sky_l: vec3<f32>,
    sun_l: vec3<f32>,
    time: f32,
    seed: f32,
    glow_k: f32,
}
// A burst of earth `a` seconds after it was thrown, r out and y up from the foot, S the dust's size: a fountain from
// the foot, flaring as it climbs, its head falling back and spreading.
fn cb_burst(r: f32, y: f32, a: f32, S: f32) -> f32 {
    if (a <= 0.0 || a > 4.5) {
        return 0.0;
    }
    let rb = S * (0.45 + 1.5 * cb_ease(a / 1.2));
    let hb = S * (0.3 + 1.9 * cb_ease(a / 0.8)) * (1.0 - 0.45 * smoothstep(0.7, 3.5, a));
    let rf = rb * (0.5 + 0.5 * saturate(y / max(hb, 1.0)));
    let f = saturate(1.0 - length(vec2<f32>(r / rf, (y - clamp(y, 0.0, hb)) / (rb * 0.7))));
    return f * f * (3.0 - 2.0 * f) * smoothstep(0.0, 0.06, a) * exp(-a / 1.2) * 2.2;
}
// What a source throws up at p (off its foot): x how much dust, y how much of that is earth. s seconds since it broke
// the ground, S its dust's size, R its radius, Hc how high its column has climbed; dp 0 for the first shards and the
// heart (a bulge before they break, a surge after they struggle), else the time each of the bloom's pushes takes.
fn cb_rise(p: vec3<f32>, s: f32, S: f32, R: f32, Hc: f32, dp: f32) -> vec2<f32> {
    // (its column settled into the haze by the time it is CB_RISE_END old)
    let lead = dp == 0.0;
    let r = length(p.xz);
    let y = max(p.y, 0.0);
    var dirt = cb_burst(r, y, s, S);
    if (lead) {
        dirt = dirt + 1.3 * cb_burst(r, y, s - CB_STRUGGLE, S * 1.2);
    } else {
        dirt = dirt + 0.6 * cb_burst(r, y, s - 0.18 * dp, S * 0.8) + 0.45 * cb_burst(r, y, s - 0.55 * dp, S * 0.7);
    }
    var d = 0.0;
    // (before it breaks: dust seeping up round its foot as the ground heaves)
    if (lead && s < 0.3) {
        let sb = smoothstep(-CB_BULGE, 0.05, s);
        d = sb * sb * smoothstep(R + S * 0.9, R * 0.5, r) * smoothstep(S * 0.6, 0.0, y) * 0.9;
    }
    let sc = select(s, s - CB_STRUGGLE, lead);
    if (sc > -0.2) {
        let up = smoothstep(-0.2, 0.5, sc) * exp(-max(sc - 1.0, 0.0) / 4.5) * (1.0 - smoothstep(CB_RISE_END - 2.0, CB_RISE_END, sc));
        let rc = R * 1.02 + S * (0.3 + 0.55 * cb_ease(sc / 4.0)) + y * 0.16;
        let body = smoothstep(rc, R * 0.85, r) * smoothstep(Hc, Hc * 0.3, y);
        let hh = Hc * 0.82;
        let fh = saturate(1.0 - length(vec2<f32>(r / (rc * 1.35), (y - hh) / (rc * 0.9))));
        d = d + max(body, fh * fh * (3.0 - 2.0 * fh)) * up * 1.4;
    }
    return vec2<f32>(d + dirt, dirt);
}
// (it is gone `end` seconds after it set out). How far out it has rolled (sc seconds since it set out: x its middle, y how wide, z how high).
fn cb_surge_at(sc: f32, S: f32, R: f32) -> vec3<f32> {
    let e = cb_ease(sc / 3.6);
    return vec3<f32>(R + S * (0.3 + 3.4 * e), S * (0.4 + 0.7 * e), S * (0.45 + 0.6 * cb_ease(sc / 3.0)));
}
fn cb_surge(p: vec3<f32>, sc: f32, S: f32, R: f32, end: f32) -> f32 {
    let g = cb_surge_at(sc, S, R);
    let r = length(p.xz);
    let ring = exp(-pow((r - g.x) / g.y, 2.0)) + 0.2 * smoothstep(g.x, R, r);
    return ring * smoothstep(g.z, g.z * 0.05, max(p.y, 0.0)) * smoothstep(-0.2, 0.3, sc) * exp(-max(sc, 0.0) / 3.4) * (1.0 - smoothstep(end * 0.6, end, sc)) * 1.6;
}
// A cheap smooth noise (about 0..1, no lattice to show) for the dust's billows, marched many times a pixel: waves
// bent by waves, at two scales and turned to each other.
fn cb_wn3(p: vec3<f32>) -> f32 {
    let a = sin(p.x + 1.1 * sin(p.z * 0.73 + 1.3)) * sin(p.y * 1.13 + 1.2 * sin(p.x * 0.81)) * sin(p.z * 0.91 + sin(p.y * 0.62 + 2.0));
    let q = mat3x3<f32>(0.00, 0.80, 0.60, -0.80, 0.36, -0.48, -0.60, -0.48, 0.64) * p * 2.1 + vec3<f32>(1.7, 9.2, 5.3);
    let b = sin(q.x + 1.1 * sin(q.z * 0.77 + 0.4)) * sin(q.y * 1.07 + 1.1 * sin(q.x * 0.69 + 2.2)) * sin(q.z * 0.95 + sin(q.y * 0.58 + 0.7));
    return saturate(0.5 + 0.62 * a + 0.3 * b);
}
// The dust at qt (off the target) given how much of it the shapes put there (env, earth of it, its light from the
// crystals glw): its billows crisp-edged, two scales, rising and drifting, each shading itself where the light reaching
// it has come through more of it; lit by the sky and sun from above, the crystals from inside and below. x, y, z the
// light it sends back, w how dense.
fn cb_dshade(env: f32, dirt: f32, glw: vec3<f32>, qt: vec3<f32>, L: CbDL) -> vec4<f32> {
    if (env < 0.12) {
        return vec4<f32>(0.0);
    }
    let np = qt * (1.0 / 13.0) + vec3<f32>(L.seed * 0.37 - L.time * 0.12, -L.time * 0.32, L.time * 0.06);
    let n1 = cb_wn3(np);
    let n = n1 * 0.68 + cb_wn3(np * 2.3 + vec3<f32>(11.0, 3.0, 7.0)) * 0.32;
    let er = saturate((env - (1.0 - n) * 1.5) * 2.4);
    let dens = er * er * (3.0 - 2.0 * er) * (0.55 + 0.45 * min(env, 2.0));
    if (dens < 0.003) {
        return vec4<f32>(0.0);
    }
    let ns1 = cb_wn3(np + L.Ld * 0.35);
    let lit = saturate(0.5 + (n1 - ns1) * 3.5);
    let occ = 0.5 + 0.5 * exp(-env * 0.45);
    let tops = 0.7 + 0.3 * saturate(qt.y / 60.0);
    let alb = mix(vec3<f32>(0.62, 0.55, 0.47), vec3<f32>(0.36, 0.29, 0.22), saturate(dirt / env));
    let li = alb * (L.sky_l * (0.3 + 0.7 * lit) * occ * tops + L.sun_l * lit * lit * occ)
        + glw / env * (0.55 + 0.45 * (1.0 - lit)) * L.glow_k;
    return vec4<f32>(li, dens);
}
// Where the view ray (from the eye) is inside an upright cylinder, R round C (camera-relative), from y0 to y1 over it:
// x in, y out (y <= x: it misses).
fn cb_cyl(rd: vec3<f32>, C: vec3<f32>, R: f32, y0: f32, y1: f32) -> vec2<f32> {
    let a = max(dot(rd.xz, rd.xz), 1.0e-8);
    let b = -dot(rd.xz, C.xz);
    let c = dot(C.xz, C.xz) - R * R;
    let disc = b * b - a * c;
    if (disc <= 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    var t0 = (-b - sqrt(disc)) / a;
    var t1 = (-b + sqrt(disc)) / a;
    if (abs(rd.y) > 1.0e-5) {
        let ya = (C.y + y0) / rd.y;
        let yb = (C.y + y1) / rd.y;
        t0 = max(t0, min(ya, yb));
        t1 = min(t1, max(ya, yb));
    } else if (C.y + y0 > 0.0 || C.y + y1 < 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    return vec2<f32>(max(t0, 0.0), t1);
}
// One part of the dust marched over t0..t1 of the view ray: kind 0 a source's burst and column, 1 its surge (F its
// foot, v its s, S, R, Hc; dp as cb_rise's; gc its light), 2 the bloom's wall (F the target, v how far out it has run,
// how wide, how high, how thick). x, y, z the light it sends back, w how much of what is behind it shows through.
fn cb_dseg(rd: vec3<f32>, t0: f32, t1: f32, kind: i32, N: i32, F: vec3<f32>, v: vec4<f32>, dp: f32, gc: vec3<f32>, L: CbDL, jit: f32) -> vec4<f32> {
    let stp = (t1 - t0) / f32(N);
    var T = 1.0;
    var acc = vec3<f32>(0.0);
    for (var k = 0; k < N; k = k + 1) {
        let x = rd * (t0 + (f32(k) + jit) * stp);
        let p = x - F;
        let qt = x - L.crel;
        var env = 0.0;
        var dirt = 0.0;
        var glw = vec3<f32>(0.0);
        if (kind == 2) {
            let rr = length(qt.xz);
            let ang = atan2(qt.z, qt.x);
            let hw = v.z * (0.7 + 0.3 * sin(ang * 5.0 + L.seed) * sin(ang * 3.0 - 1.3 + L.seed * 0.7));
            env = exp(-pow((rr - v.x) / v.y, 2.0)) * smoothstep(hw, hw * 0.1, qt.y) * v.w;
            glw = cb_hue(ang / TAU + rr * 0.002 + L.time * 0.02) * env * 0.25 * exp(-max(qt.y, 0.0) / 15.0);
        } else {
            if (kind == 0) {
                let e = cb_rise(p, v.x, v.y, v.z, v.w, dp);
                env = e.x;
                dirt = e.y;
            } else {
                env = cb_surge(p, select(v.x, v.x - CB_STRUGGLE, dp == 0.0), v.y, v.z, select(CB_SURGE_END, CB_SURGE_BLOOM, dp > 0.0));
            }
            // (its light on the dust round it: from inside it and from below, the dust taking its colour)
            let rr = length(p.xz);
            glw = gc * (env - 0.7 * dirt) * exp(-max(rr - v.z, 0.0) / (v.y * 1.1)) * (0.35 + 0.65 * exp(-max(p.y, 0.0) / (v.y * 2.0)));
        }
        let sm = cb_dshade(env, dirt, glw, qt, L);
        if (sm.w > 0.0) {
            let al = 1.0 - exp(-sm.w * 0.11 * stp);
            acc = acc + T * al * sm.xyz;
            T = T * (1.0 - al);
            if (T < 0.02) {
                break;
            }
        }
    }
    return vec4<f32>(acc, T);
}

fn crystal_bloom(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();
    let px_a = frame.view_params.w / frame.resolution.y;      // (the angle a pixel spans)

    // ---- timeline -------------------------------------------------------------
    let wake = smoothstep(0.2, 3.0, time);
    let dt = time - CB_DET;
    let det = dt > 0.0;
    // the light going down as the land wakes, a little; back once it is over
    let dark = smoothstep(0.0, 3.0, time) * (0.8 + 0.15 * smoothstep(CB_RES, CB_DET, time)) * (1.0 - smoothstep(CB_DET + 3.0, CB_END, time));
    // the resonance: building from CB_RES, the pulses running up them faster and faster, a breath just before it bursts
    let res = smoothstep(CB_RES, CB_DET - 0.4, time) * f32(!det);
    let breath = smoothstep(CB_DET - 0.32, CB_DET - 0.12, time) * f32(!det);
    let pulse_f = 0.5 + 6.5 * res * res;
    let pulse_ph = time * 0.5 + 6.5 * max(time - CB_RES, 0.0) * res * res * 0.6;
    // the colours turning: slowly as they grow, faster as they resonate, all to white as they burst
    let hue_t = time * 0.02 + res * res * (time - CB_RES) * 0.08;
    let flash = select(0.0, exp(-dt * 6.0) * 1.2 + exp(-dt * 25.0) * 1.8, det);
    let after = 1.0 - smoothstep(CB_END - 3.0, CB_END, time);
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sky_c = srgb_to_linear(frame.sky_color.rgb);
    let pT = project_rel(crel);
    let heart = crel + vec3<f32>(0.0, 150.0, 0.0);
    let pH = project_rel(heart);

    // ---- what bends the light: the air shimmering round the spires as they resonate, the shock running out ------
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let rd0 = normalize(world_offset(uv, 0.5));
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    var off = vec2<f32>(0.0);
    if (res > 0.01) {
        var sh = 0.0;
        for (var i = 0; i < CB_LEADS; i = i + 1) {
            let pl = cb_place(i, seed);
            let fm = cb_form(i, seed, pl);
            let A = crel + vec3<f32>(pl.x, 0.0, pl.y);
            let q = ray_seg(rd0, A, A + cb_axis(fm) * pl.w);
            sh = sh + exp(-max(q.x - fm.x, 0.0) / (fm.x * 1.5)) * select(1.0, 0.0, !sky0 && q.y > length(p0 - cam) + 20.0);
        }
        let hw = vec2<f32>(gnoise2(uv * vec2<f32>(70.0, 30.0) + vec2<f32>(0.0, -time * 3.0)), gnoise2(uv * vec2<f32>(70.0, 30.0) + vec2<f32>(31.0, -time * 2.6))) - 0.5;
        off = off + hw * 0.007 * saturate(sh) * res * (0.5 + 0.5 * sin(time * pulse_f * 6.0)) * k;
    }
    if (det && dt < 4.0 && pT.z > 0.0) {
        let rs = CB_SHOCK_V * dt;
        if (!sky0) {
            let r0 = length(p0.xz - tgt.xz);
            off = off + normalize(uv - pT.xy + vec2<f32>(1.0e-5)) * exp(-pow((r0 - rs) / 8.0, 2.0)) * exp(-dt * 0.7) * 0.02 * k;
        }
        // (and through the air: a shell round the heart)
        let tcs = dot(heart, rd0);
        let dcs = length(rd0 * max(tcs, 0.0) - heart);
        let Rs = 40.0 + 260.0 * (1.0 - exp(-dt * 1.4));
        off = off + normalize(uv - pH.xy + vec2<f32>(1.0e-5)) * exp(-pow((dcs - Rs) / 10.0, 2.0)) * exp(-dt * 1.2) * 0.012 * f32(tcs > 0.0) * k;
    }
    let uv2 = clamp(uv + off, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene ------------------------------------------------------------
    let d = depth_at(uv2);
    var sky = is_sky(d);
    var solid = false;
    let rel = world_offset(uv2, select(d, 0.5, sky));
    var scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let P = cam + rel;
    var cloud = !sky && abs(P.y - CLOUD_Y - 2.0) < 6.0;
    let ca = (flash * 0.02 + res * res * 0.004) * k;
    let ca_dir = (uv2 - vec2<f32>(0.5)) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b));
    // the sky to a deep indigo, the land dimmed, so the crystals' light carries
    let night = vec3<f32>(0.008, 0.008, 0.03) + vec3<f32>(0.05, 0.03, 0.12) * exp(-abs(rd.y) / 0.1) * wake;
    if (sky) {
        col = mix(col, night, dark * k);
    } else {
        col = col * (1.0 - 0.7 * dark * k);
    }
    var add = vec3<f32>(0.0);
    let amb_c = mix(vec3<f32>(0.012, 0.014, 0.035), vec3<f32>(0.22, 0.25, 0.32), day) * (1.0 - 0.6 * dark);
    let sun_c = vec3<f32>(1.6, 1.5, 1.35) * day * (1.0 - 0.7 * dark);
    let hazec = srgb_to_linear(frame.fog_color.rgb) * (0.3 + 0.7 * day) * (1.0 - 0.7 * dark);

    // ---- the ground over the first shards heaving before they break it, cracked, light leaking up through it -----
    for (var i = 0; i < CB_LEADS; i = i + 1) {
        let pl = cb_place(i, seed);
        let s = time - pl.z;
        if (s < -CB_BULGE || s > 0.35) {
            continue;
        }
        let sb = smoothstep(-CB_BULGE, 0.0, s);
        let fm = cb_form(i, seed, pl);
        let S0 = crel + vec3<f32>(pl.x, 0.0, pl.y);
        let Rd = fm.x * 3.2;
        let Cd = S0 + vec3<f32>(0.0, fm.x * (0.45 * sb * sb + 0.15 * saturate(s * 4.0)) - Rd, 0.0);
        let tcd = dot(Cd, rd);
        let dc2 = dot(Cd, Cd) - tcd * tcd;
        if (tcd > 0.0 && dc2 < Rd * Rd && dot(Cd, Cd) > Rd * Rd) {
            let td = tcd - sqrt(Rd * Rd - dc2);
            let pd = rd * td - Cd;
            if (pd.y + Cd.y - S0.y > -0.5 && (sky || td < scene_len + 4.0)) {
                let nd = pd / Rd;
                let ang = atan2(nd.z, nd.x);
                let pw = td * px_a / 2.0;
                let w1 = max(0.01, pw * 0.7);
                let cn = abs(gnoise2(vec2<f32>(ang * 7.0, nd.y * 24.0) + vec2<f32>(f32(i) * 5.0)) - 0.5);
                let cracks = exp(-cn / w1) * pow(0.01 / w1, 1.2) * sb;
                let torn = exp(-cn / (w1 * 6.0)) * sb * 0.7;
                let slope = 0.55 + 0.6 * saturate(dot(nd, normalize(vec3<f32>(0.3, 1.0, 0.2))));
                let land = vec3<f32>(0.12, 0.14, 0.08) * (0.25 + 0.75 * day) * (1.0 - 0.5 * dark) * slope;
                col = mix(land, vec3<f32>(0.05, 0.042, 0.036) * (0.3 + 0.6 * day), saturate(torn));
                add = cb_hue(f32(i) * 0.17 + hue_t) * cracks * (1.0 + 2.0 * sb) * k;
                scene_len = td;
                sky = false;
                cloud = false;
            }
        }
    }

    // ---- the spires: solid, the nearest drawn and hiding what is behind it, hidden by anything nearer -------------
    var best = -1;
    var best_t = scene_len;
    var best_k = 0.0;
    var best_out = 0.0;
    // their light, from the first shards and each cluster's tallest: where (camera-relative, w how bright) and its colour
    var lp: array<vec4<f32>, 16>;
    var lc: array<vec3<f32>, 16>;
    var li: array<i32, 16>;                                     // (which spires, for the shards round them)
    var nl = 0;
    var near_glint = 0.0;                                       // (the light round them in the air, close to their faces)
    var near_col = vec3<f32>(0.0);
    for (var i = 0; i < CB_N; i = i + 1) {
        var brk = vec4<f32>(0.0);
        if (det) {
            // after the burst: its stump, until the real one has been built where it stands
            let pl = cb_place(i, seed);
            brk = cb_break(i, seed, pl.w);
            if (brk.x < 0.5 || time > cb_dig_t(length(pl.xy) + cb_form(i, seed, pl).x * 1.3 + brk.x * 0.8 + 20.0) + 0.15) {
                continue;
            }
        }
        var c = cb_crystal(i, seed, time, crel);
        if (c.s <= 0.0) {
            continue;
        }
        // (their glow: waking as they come up, swelling as they resonate)
        let glow_i = (0.5 + 0.5 * smoothstep(0.0, 1.5, c.s)) * (1.0 + 2.0 * res) * (1.0 - breath * 0.85);
        let H = c.Hb + c.tip;
        if (det) {
            c.cut = vec4<f32>(brk.x, brk.z, brk.w, 1.0);
            c.R = c.R * CB_STUMP;
            c.Rt = c.R * 0.8;
        }
        if ((i < CB_LEADS || (i - 6) % 4 == 0) && nl < 16 && !det) {
            lp[nl] = vec4<f32>(c.B + c.a * H * 0.45, glow_i * saturate(c.g) * (0.25 + H / 300.0));
            lc[nl] = cb_hue(c.hue + hue_t);
            li[nl] = i;
            nl = nl + 1;
        }
        let q = ray_seg(rd, c.B - c.a * 6.0, c.B + c.a * H);
        // (the air close to it lit by it as it resonates)
        near_glint = near_glint + exp(-max(q.x - c.R, 0.0) / (c.R * 0.7 + 2.0)) * glow_i * res * cb_occ(q.y, scene_len, sky, cloud) * saturate(c.g) * 0.06;
        if (q.x > c.R * 1.2 + 1.0 || q.y - c.R * 2.0 > best_t) {
            continue;
        }
        let h = cb_hit(c, cb_to(c, -c.B), cb_to(c, rd));
        if (h.x > 0.0 && h.x < best_t) {
            best = i;
            best_t = h.x;
            best_k = h.z;
            best_out = h.y;
        }
    }
    if (best >= 0) {
        var c = cb_crystal(best, seed, time, crel);
        if (det) {
            let br = cb_break(best, seed, cb_place(best, seed).w);
            c.cut = vec4<f32>(br.x, br.z, br.w, 1.0);
            c.R = c.R * CB_STUMP;
            c.Rt = c.R * 0.8;
        }
        let X = rd * best_t;
        let ql = cb_to(c, X - c.B);
        let dl = cb_to(c, rd);
        let pl = cb_plane(c, i32(best_k));
        let nlc = normalize(pl.xyz);
        let n = normalize(cb_from(c, nlc));
        let H = c.Hb + c.tip;
        let base_c = cb_hue(c.hue + hue_t);
        let burst_w = smoothstep(CB_DET - 0.6, CB_DET, time);
        let glow_c = mix(base_c, vec3<f32>(1.0, 0.97, 1.0), burst_w * 0.7);
        // the light caught on its face: the sky and the sun, more of it towards the edge on
        let cosi = max(dot(-rd, n), 0.0);
        let fres = 0.045 + 0.955 * pow(1.0 - cosi, 5.0);
        let lglow = base_c * 0.15 * (1.0 + 2.0 * res);
        let refl = cb_env(reflect(rd, n), sky_c, sun, day, dark, lglow);
        // inside it: the view ray bent in, each colour a little differently, to the face it leaves by, and out again;
        // what it sees there the sky bent and split into colours, through the crystal's body (deeper the further it goes)
        var inner = vec3<f32>(0.0);
        var path = 0.0;
        var core = 0.0;
        var kout = 0.0;
        for (var ch = 0; ch < 3; ch = ch + 1) {
            let eta = 1.0 / (1.52 + 0.025 * f32(ch));
            var dr = refract(dl, nlc, eta);
            if (dot(dr, dr) < 1.0e-6) {
                dr = reflect(dl, nlc);
            }
            dr = normalize(dr);
            let ex = cb_exit(c, ql + dr * 0.01, dr);
            let n2 = normalize(cb_plane(c, i32(ex.y)).xyz);
            var vo = refract(dr, -n2, 1.52 + 0.025 * f32(ch));
            if (dot(vo, vo) < 1.0e-6) {
                vo = reflect(dr, -n2);
            }
            let vw = normalize(cb_from(c, vo));
            let e = cb_env(vw, sky_c, sun, day, dark, lglow);
            inner[ch] = e[ch];
            if (ch == 1) {
                path = ex.x;
                kout = ex.y;
                // (how close the bent ray passes to its heart: the glow inside it, strongest down its middle)
                let mid = ql + dr * ex.x * 0.5;
                core = exp(-length(mid.xz) / (c.R * 0.5));
                // (cleavage inside it catching the light: a few flat sheets across it, each its own way)
                for (var fk = 0; fk < 3; fk = fk + 1) {
                    let hv = cb_h3(best * 3 + fk, 777u, seed);
                    let fn_ = normalize(hv - 0.5 + vec3<f32>(0.0, 0.2, 0.0));
                    let off_ = (hv.x - 0.5) * c.R * 0.8;
                    let a0 = dot(ql, fn_) - off_;
                    let a1 = dot(ql + dr * ex.x, fn_) - off_;
                    // (the sheet's light where the ray crosses it, softer the more face-on it is seen)
                    core = core + select(0.0, 0.55 * (0.4 + 0.6 * abs(dot(dr, fn_))), a0 * a1 < 0.0);
                }
            }
        }
        // its body: a deep, saturated colour, darker the further the light goes through it
        let deepc = base_c * base_c;
        let absorb = exp(-path / (c.R * 1.6) * (vec3<f32>(1.0) - deepc * 0.9) * 2.5);
        // the facets inside it: each face it comes out by a little brighter or darker than the next
        let facet = 0.35 + 1.3 * pow(fract(sin(kout * 12.9898 + f32(best) * 3.7) * 43758.5), 2.0);
        // its light from inside: down its heart, pulses running up all of them together as they resonate
        let yw = X.y + cam.y - tgt.y;
        let pls = pow(0.5 + 0.5 * sin(yw * 0.045 - pulse_ph * TAU), 10.0) * res * 3.0;
        let wakeg = (0.3 + 0.7 * smoothstep(0.0, 1.6, c.s)) * (1.0 - breath * 0.9);
        let lit_up = (0.12 + 0.9 * core * core + pls * (0.3 + core)) * wakeg * (1.0 + 1.5 * res) + burst_w * 2.0 * f32(!det);
        var cc = inner * absorb * facet * 0.35 + glow_c * lit_up * facet * absorb * 1.6 + glow_c * glow_c * 0.03 * wakeg;
        // its edges catching the light: where the face it went in by meets the next
        var edge = 1.0e9;
        for (var kk = 0; kk < 14; kk = kk + 1) {
            if (kk == i32(best_k)) {
                continue;
            }
            let pk = cb_plane(c, kk);
            edge = min(edge, (pk.w - dot(pk.xyz, ql)) / length(pk.xyz));
        }
        let ew = max(0.15, best_t * px_a * 0.8);
        let edg = exp(-max(edge, 0.0) / ew) * min(1.0, 0.15 / ew * 2.0);
        cc = cc + (refl * 0.5 + glow_c * (0.5 + 1.8 * res) * wakeg) * edg;
        // its faces: the sky and the sun on them
        cc = cc + refl * fres * 1.1 + sun_c * pow(max(dot(n, normalize(sun - rd)), 0.0), 300.0) * 3.0;
        let earth = smoothstep(4.0, -2.0, yw - (1.0 - saturate(c.s * 0.35)) * 10.0) * f32(c.cut.w < 0.5);
        cc = mix(cc, vec3<f32>(0.07, 0.058, 0.045) * (0.3 + 0.6 * day) * (1.0 - 0.4 * dark), earth * 0.85);
        let haze = 1.0 - exp(-best_t / 3000.0);
        col = mix(cc * k + col * (1.0 - k), hazec, haze * 0.7);
        add = vec3<f32>(0.0);
        scene_len = best_t;
        sky = false;
        cloud = false;
        solid = true;
    }
    add = add + near_glint * vec3<f32>(0.7, 0.6, 1.0) * k;

    // ---- on the land: cracks of light spreading out as it wakes, the spires' coloured light, the shock running out, the
    //      crater and the fissures glowing where they have opened -----------------------------------------------------
    let rel2 = P.xz - tgt.xz;
    let r = length(rel2);
    let dy = P.y - tgt.y;
    if (!sky && !solid) {
        let on_ground = 1.0 - smoothstep(20.0, 40.0, dy);
        // the spires' light, each cluster its own colour, a little on everything round
        var lt = vec3<f32>(0.0);
        for (var j = 0; j < nl; j = j + 1) {
            let L = lp[j].xyz - (P - cam);
            let dd = dot(L, L);
            lt = lt + lc[j] * lp[j].w * 9000.0 / (dd + 3000.0);
        }
        let ltc = lt / (1.0 + luminance(lt) * 0.5);
        col = col + col * ltc * 0.6 * k;
        add = add + ltc * 0.002 * on_ground * k;
        // the cracks: a web spreading out over the land as it wakes, light seeping up through it, brighter as the spires
        // resonate, gone as they burst (only light: the land is broken for real once they have)
        let front = (CB_FIELD + 40.0) * smoothstep(0.0, 3.6, time) * (0.6 + 0.4 * smoothstep(3.0, CB_BLOOM0 + 2.0, time));
        let reach = smoothstep(front, front - 30.0, r + 20.0 * (gnoise2(rel2 * 0.02 + vec2<f32>(seed)) - 0.5));
        if (reach > 0.01 && !det && on_ground > 0.01) {
            let pw = scene_len * px_a;
            let w1 = max(0.004, pw * 0.05);
            let warp = vec2<f32>(gnoise2(rel2 * 0.011 + vec2<f32>(3.0, seed)), gnoise2(rel2 * 0.011 + vec2<f32>(seed, 7.0))) * 40.0;
            let cn1 = abs(gnoise2((rel2 + warp) * 0.022 + vec2<f32>(seed * 0.37)) - 0.5);
            let cn2 = abs(gnoise2((rel2 + warp * 0.6) * 0.07 + vec2<f32>(5.0, seed)) - 0.5);
            let crk = (exp(-cn1 / w1) * min(1.0, 0.016 / w1) + 0.5 * exp(-cn2 / (w1 * 0.8)) * min(1.0, 0.008 / w1) * smoothstep(1.0, 3.0, time))
                * reach;
            let throb = 0.7 + 0.3 * sin(time * 2.2 - r * 0.04) + 1.2 * res * pow(0.5 + 0.5 * sin(pulse_ph * TAU - r * 0.03), 6.0);
            let hc = cb_hue(atan2(rel2.y, rel2.x) / TAU + r * 0.002 + hue_t);
            add = add + hc * crk * (0.6 + 1.4 * wake) * throb * (1.0 - breath * 0.8) * (1.0 + 0.5 * exp(-r / 40.0)) * on_ground * 4.5 * k;
            // (and a glow over it, low, the light coming up out of the ground)
            add = add + hc * exp(-cn1 / 0.07) * reach * 0.12 * wake * on_ground * k;
        }
        if (det) {
            // the shock running out over the land, a prismatic flash along its front, dust lifted behind it
            let rs = CB_SHOCK_V * dt * (1.0 - 0.18 * saturate(dt / 2.5));
            let fr = exp(-pow((r - rs) / 5.0, 2.0)) * exp(-dt * 1.4) * on_ground;
            add = add + mix(vec3<f32>(0.95, 0.9, 1.05), cb_spectrum(saturate((r - rs) / 16.0 + 0.5)), 0.18) * fr * 1.3 * k;
            col = mix(col, vec3<f32>(0.32, 0.29, 0.3) * (0.3 + 0.7 * day) * (1.0 - 0.4 * dark), exp(-pow((r - rs + 9.0) / 14.0, 2.0)) * 0.5 * exp(-dt * 0.4) * on_ground * k);
            // the crater where it has really been opened: its crystal lining glowing, cooling slowly, veins of light
            // through it, the well at its middle glowing deepest
            let open = cb_open(rel2, r, time);
            if (open > 0.0 && r < CB_BOWL * 1.15) {
                let n = gfbm2(rel2 * 0.07 + vec2<f32>(P.y * 0.15, seed));
                let veins = exp(-pow((n - 0.5) / 0.05, 2.0));
                let deep = saturate(-dy / CB_BOWL_D);
                let fresh = exp(-max(time - cb_dig_t(r), 0.0) / 6.0);
                let hc = cb_hue(atan2(rel2.y, rel2.x) / TAU + 0.02 * r);
                add = add + hc * (veins * (0.5 + 1.2 * fresh) + 0.5 * fresh * deep + smoothstep(CB_WELL * 1.6, 0.0, r) * 2.0) * open * after * 1.3 * k;
            }
            // the fissures as they open, light pulsing out along them
            let ang = atan2(rel2.y, rel2.x);
            if (r > CB_BOWL * 0.8 && r < CB_CRACK_R + 10.0) {
                var crack = 0.0;
                for (var i = 0; i < CB_CRACKS; i = i + 1) {
                    let cr = cb_crack(i, seed);
                    if (r > cr.y) {
                        continue;
                    }
                    let a = cr.x + 0.08 * sin(r * 0.05 + f32(i) * 3.0) + 0.04 * sin(r * 0.13 + f32(i));
                    var da = ang - a;
                    da = da - TAU * floor(da / TAU + 0.5);
                    let lat = abs(da) * r;
                    let hw = 1.0 + 2.2 * (1.0 - (r - CB_BOWL) / (cr.y - CB_BOWL));
                    let opened = smoothstep(0.0, 0.2, time - cb_crack_t(r));
                    crack = max(crack, ((1.0 - smoothstep(hw - 0.3, hw + 0.7, lat)) + exp(-lat / (hw * 2.0)) * 0.3) * opened);
                }
                let fade = 0.35 + 0.65 * exp(-max(dt - 1.5, 0.0) / 5.0);
                add = add + cb_hue(ang / TAU + 0.3) * crack * fade * on_ground * after * 1.8 * k;
            }
        }
    }
    // the light welling up out of the waking land: a low haze of colour over it, thickest over the middle, pulsing with
    // the hum, carried up by the bloom, gone as they burst
    if (!det) {
        let front = (CB_FIELD + 40.0) * smoothstep(0.0, 3.6, time);
        let Hh = 14.0 + 30.0 * smoothstep(CB_BLOOM0, CB_RES, time);
        // (where the view ray is in the slab of air over the land, up to what it meets)
        let y0 = tgt.y - 2.0 - cam.y;
        let y1 = tgt.y + Hh - cam.y;
        var ta = 0.0;
        var tb = select(scene_len, 1.0e4, sky);
        if (abs(rd.y) > 1.0e-4) {
            ta = max(min(y0 / rd.y, y1 / rd.y), 0.0);
            tb = min(tb, max(y0 / rd.y, y1 / rd.y));
        } else if (cam.y < tgt.y - 2.0 || cam.y > tgt.y + Hh) {
            tb = -1.0;
        }
        if (tb > ta) {
            // (its strength where the ray passes nearest the middle within the slab)
            let tcl = clamp(dot(crel.xz, rd.xz) / max(dot(rd.xz, rd.xz), 1.0e-6), ta, tb);
            let mid = rd * tcl - crel;
            let rm = length(mid.xz);
            let m = smoothstep(front, front * 0.4, rm) * exp(-rm / 90.0);
            let hc = mix(cb_hue(hue_t + 0.1), cb_hue(atan2(mid.z, mid.x) / TAU + hue_t), smoothstep(20.0, 120.0, rm));
            let path = min(tb - ta, 400.0);
            let throb = 0.75 + 0.25 * sin(time * 2.2) + 0.6 * res * pow(0.5 + 0.5 * sin(pulse_ph * TAU), 4.0);
            add = add + hc * (1.0 - exp(-path / 160.0)) * m * wake * throb * (1.0 - breath) * 0.6 * k;
        }
    }
    // the clouds lit from under by the spires' light, in colour
    if (cloud && nl > 0) {
        var lt = vec3<f32>(0.0);
        for (var j = 0; j < nl; j = j + 1) {
            let L = lp[j].xyz - (P - cam);
            lt = lt + lc[j] * lp[j].w * 30000.0 / (dot(L, L) + 30000.0);
        }
        add = add + lt * 0.06 * k;
    }

    // ---- what the first shards throw up as they break the ground, and rock flung out ------------------------------
    for (var i = 0; i < CB_LEADS; i = i + 1) {
        let pl = cb_place(i, seed);
        let s = time - pl.z;
        if (s < 0.0 || s > 5.0 || det) {
            continue;
        }
        let fm = cb_form(i, seed, pl);
        let F = crel + vec3<f32>(pl.x, 0.0, pl.y);
        if (ray_seg(rd, F, F + vec3<f32>(0.0, 120.0, 0.0)).x > fm.x * 6.0 + 40.0) {
            continue;
        }
        // rock flung up and out as it breaks the ground, and again as it surges, falling back
        for (var j = 0; j < 12; j = j + 1) {
            let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), u32(i), u32(seed)))) * (1.0 / 4294967295.0);
            let t_th = select(0.0, CB_STRUGGLE, j % 2 == 1);
            let a = s - t_th;
            if (a < 0.0 || a > 4.0) {
                continue;
            }
            let az = hv.x * TAU;
            let vh = 8.0 + 30.0 * hv.y;
            let vy = 18.0 + 40.0 * hv.z * hv.z;
            let s3 = F + vec3<f32>(cos(az), 0.0, sin(az)) * fm.x * 1.1 + vec3<f32>(0.0, 2.0, 0.0);
            let a1 = max(a - 0.05, 0.0);
            let pa = s3 + vec3<f32>(cos(az) * vh * a, vy * a - 16.0 * a * a, sin(az) * vh * a);
            let pb = s3 + vec3<f32>(cos(az) * vh * a1, vy * a1 - 16.0 * a1 * a1, sin(az) * vh * a1);
            if (pa.y < F.y - 2.0) {
                continue;
            }
            let qj = ray_seg(rd, pa, pb);
            let wj = 0.6 + 1.6 * hv.y;
            let cov = smoothstep(1.0, 0.5, qj.x / max(wj, qj.y * px_a)) * (wj / max(wj, qj.y * px_a));
            let vj = select(1.0, 1.0 - smoothstep(scene_len - 0.5, scene_len + 0.5, qj.y), !sky);
            col = mix(col, vec3<f32>(0.045, 0.038, 0.032) * (0.4 + 0.6 * day), cov * vj);
            add = add * (1.0 - cov * vj * 0.8);
        }
    }
    // the bloom's spires breaking the ground: a spray of earth round each as it comes up
    if (!det && time > CB_BLOOM0 - 0.1) {
        for (var i = CB_LEADS; i < CB_N; i = i + 1) {
            let pl = cb_place(i, seed);
            let s = time - pl.z;
            if (s < 0.0 || s > 2.2) {
                continue;
            }
            let F = crel + vec3<f32>(pl.x, 0.0, pl.y);
            if (ray_seg(rd, F, F + vec3<f32>(0.0, 40.0, 0.0)).x > 45.0) {
                continue;
            }
            let fm = cb_form(i, seed, pl);
            for (var j = 0; j < 6; j = j + 1) {
                let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), u32(i) + 77u, u32(seed)))) * (1.0 / 4294967295.0);
                let az = hv.x * TAU;
                let vh = 6.0 + 18.0 * hv.y;
                let vy = 12.0 + 22.0 * hv.z;
                let s3 = F + vec3<f32>(cos(az), 0.0, sin(az)) * fm.x + vec3<f32>(0.0, 1.0, 0.0);
                let a1 = max(s - 0.05, 0.0);
                let pa = s3 + vec3<f32>(cos(az) * vh * s, vy * s - 16.0 * s * s, sin(az) * vh * s);
                let pb = s3 + vec3<f32>(cos(az) * vh * a1, vy * a1 - 16.0 * a1 * a1, sin(az) * vh * a1);
                if (pa.y < F.y - 1.0) {
                    continue;
                }
                let qj = ray_seg(rd, pa, pb);
                let wj = 0.4 + 0.8 * hv.y;
                let cov = smoothstep(1.0, 0.5, qj.x / max(wj, qj.y * px_a)) * (wj / max(wj, qj.y * px_a));
                let vj = select(1.0, 1.0 - smoothstep(scene_len - 0.5, scene_len + 0.5, qj.y), !sky);
                col = mix(col, vec3<f32>(0.05, 0.042, 0.035) * (0.4 + 0.6 * day), cov * vj);
                add = add * (1.0 - cov * vj * 0.8);
            }
        }
    }

    // ---- the dust they throw up as they come up (cb_rise, cb_surge, the bloom's wall, the haze they leave), up to
    //      whatever is nearer, the land or a spire: dust in front of a spire veils it, dust behind it is hidden by it --
    let dfade = 1.0 - smoothstep(CB_RES - 1.0, CB_DET - 1.5, time);
    if (!det && time > CB_PUNCH0 - CB_BULGE && dfade > 0.0) {
        let tmax_d = select(scene_len, 1.0e9, sky);
        var L: CbDL;
        L.crel = crel;
        L.Ld = normalize(vec3<f32>(sun.x * 0.6, 1.0, sun.z * 0.6));
        L.sky_l = (amb_c * 3.0 + hazec * 0.3) * dfade;
        L.sun_l = sun_c * 0.45 * saturate(sun.y * 3.0) * dfade;
        L.time = time;
        L.seed = seed;
        L.glow_k = 0.8 * (1.0 + 0.5 * res) * dfade;
        let jit = ign(in.position.xy);
        // (the parts put together whatever their order: their light summed, weighted by how much each hides)
        var sum_c = vec3<f32>(0.0);
        var sum_a = 0.0;
        var Tall = 1.0;
        // the haze they leave over the land, low, drifting and thinning (where the view ray is in it, its strength
        // where the ray passes nearest the middle)
        let tau = time - CB_BLOOM0;
        let rw = 235.0 * (1.0 - pow(1.0 - saturate(tau / 8.0), 1.6));
        let Rh = max(70.0 + 120.0 * cb_ease((time - CB_PUNCH0 - 1.0) / 6.0), rw);
        let Hh = 14.0 + 36.0 * cb_ease((time - CB_PUNCH0 - 1.0) / 7.0);
        let ha = smoothstep(CB_PUNCH0 + 0.8, CB_PUNCH0 + 3.5, time) * (0.6 + 0.4 * smoothstep(CB_BLOOM0, CB_BLOOM0 + 3.0, time)) * dfade;
        let th = cb_cyl(rd, crel, Rh, -3.0, Hh);
        let th1 = min(th.y, tmax_d);
        if (th1 > th.x && ha > 0.0) {
            let tm = clamp(dot(crel.xz, rd.xz) / max(dot(rd.xz, rd.xz), 1.0e-6), th.x, th1);
            let mid = rd * tm - crel;
            let pat = gnoise2(mid.xz * 0.012 + vec2<f32>(seed - time * 0.05, time * 0.03));
            let m = smoothstep(Rh, Rh * 0.4, length(mid.xz)) * (0.4 + 1.2 * pat * pat);
            // (thinning with height: the depth of it along the ray through a haze falling off over hs)
            let hs = Hh * 0.4;
            let ya = max(th.x * rd.y - crel.y, 0.0);
            let yb = max(th1 * rd.y - crel.y, 0.0);
            var od = (th1 - th.x) * exp(-ya / hs);
            if (abs(rd.y) > 1.0e-3) {
                od = min(od, hs * abs(exp(-ya / hs) - exp(-yb / hs)) / abs(rd.y));
            }
            let a = (1.0 - exp(-od * 0.006 * m)) * ha * 0.85;
            let hc = (vec3<f32>(0.62, 0.55, 0.47) * (amb_c * 3.0 + hazec * 0.3) + cb_hue(hue_t + 0.1) * 0.05 * wake) * dfade;
            sum_c = sum_c + hc * a;
            sum_a = sum_a + a;
            Tall = Tall * (1.0 - a);
        }
        // round each of the first shards, the heart and each cluster of the bloom's
        for (var u = 0; u < CB_LEADS + 10; u = u + 1) {
            let bloom = u >= CB_LEADS;
            let i = select(u, CB_LEADS + (u - CB_LEADS) * 4, bloom);
            let pl = cb_place(i, seed);
            let s = time - pl.z;
            if (s < -CB_BULGE || s > 14.0) {
                continue;
            }
            let fm = cb_form(i, seed, pl);
            var S = 32.0;
            var R = fm.x;
            var dp = 0.0;
            if (i == 5) {
                S = 44.0;
                R = 24.0;
            }
            if (bloom) {
                R = fm.x + 7.0;
                S = 0.7 * fm.x + 6.0;
                dp = 1.3 + 2.2 * saturate(pl.w / 260.0);
            }
            let F = crel + vec3<f32>(pl.x, 0.0, pl.y);
            let sc = select(s - CB_STRUGGLE, s, bloom);
            let hue = fract(0.13 * f32(i) + mh(u32(i), u32(seed), 23u) * 0.18 + atan2(pl.y, pl.x) / TAU * 0.6);
            let gc = cb_hue(hue + hue_t) * (0.5 + 0.5 * smoothstep(0.0, 1.5, s)) * select(1.0, 0.7, bloom);
            // its burst and column
            if (sc < CB_RISE_END) {
                let g = cb_grow(i, max(s, 0.0), pl.w).x;
                let Hc = S * 0.7 + min(g * pl.w * select(0.6, 0.45, bloom), S * select(5.0, 3.6, bloom));
                // (bounded by its column, and by its bursts while they last)
                let bursts = s < select(5.5, 4.6 + 0.55 * dp, bloom);
                let Rc = (R * 1.02 + S * 0.85 + Hc * 0.16) * 1.35;
                let tr = cb_cyl(rd, F, select(Rc, max(Rc, R + S * 2.4), bursts), -3.0, select(Hc * 1.1, max(Hc * 1.1, S * 4.2), bursts));
                let t1 = min(tr.y, tmax_d);
                if (t1 > tr.x) {
                    let o = cb_dseg(rd, tr.x, t1, 0, select(5, 3, bloom), F, vec4<f32>(s, S, R, Hc), dp, gc, L, jit);
                    sum_c = sum_c + o.xyz;
                    sum_a = sum_a + 1.0 - o.w;
                    Tall = Tall * o.w;
                }
            }
            // its surge (the bloom's soon taken up into its wall)
            if (sc > -0.2 && sc < select(CB_SURGE_END, CB_SURGE_BLOOM, bloom)) {
                let g = cb_surge_at(sc, S, R);
                let tr = cb_cyl(rd, F, g.x + g.y * 2.0, -3.0, g.z * 1.1);
                let t1 = min(tr.y, tmax_d);
                if (t1 > tr.x) {
                    let o = cb_dseg(rd, tr.x, t1, 1, 5, F, vec4<f32>(s, S, R, 0.0), dp, gc, L, jit);
                    sum_c = sum_c + o.xyz;
                    sum_a = sum_a + 1.0 - o.w;
                    Tall = Tall * o.w;
                }
            }
        }
        // the bloom's wall of dust, running out ahead of the spires and slowing (marched where the ray crosses its
        // ring: in through it, and out through it beyond)
        if (tau > 0.0) {
            let xw = saturate(tau / 8.0);
            let ww = 12.0 + 16.0 * xw;
            let Hw = 14.0 + 52.0 * cb_ease(tau / 5.0);
            let wamp = smoothstep(0.0, 1.2, tau) * (0.4 + 0.6 * exp(-max(tau - 4.6, 0.0) / 2.5)) * 1.7;
            let wv = vec4<f32>(rw, ww, Hw, wamp);
            let to = cb_cyl(rd, crel, rw + ww * 2.2, -3.0, Hw * 1.4);
            if (to.y > to.x) {
                let ti = cb_cyl(rd, crel, max(rw - ww * 2.2, 0.0), -3.0, Hw * 1.4);
                var a0 = to.x;
                var a1 = to.y;
                var b0 = 1.0;
                var b1 = 0.0;
                if (ti.y > ti.x) {
                    a1 = ti.x;
                    b0 = ti.y;
                    b1 = to.y;
                }
                a1 = min(a1, tmax_d);
                b1 = min(b1, tmax_d);
                if (a1 > a0) {
                    let o = cb_dseg(rd, a0, a1, 2, 5, crel, wv, 0.0, vec3<f32>(0.0), L, jit);
                    sum_c = sum_c + o.xyz;
                    sum_a = sum_a + 1.0 - o.w;
                    Tall = Tall * o.w;
                }
                if (b1 > b0) {
                    let o = cb_dseg(rd, b0, b1, 2, 4, crel, wv, 0.0, vec3<f32>(0.0), L, jit);
                    sum_c = sum_c + o.xyz;
                    sum_a = sum_a + 1.0 - o.w;
                    Tall = Tall * o.w;
                }
            }
        }
        if (sum_a > 1.0e-4) {
            let dc = sum_c / sum_a * (1.0 - Tall);
            col = col * Tall + dc * k + col * (1.0 - k) * (1.0 - Tall);
            add = add * mix(1.0, Tall, 0.85);
        }
    }

    // ---- shards breaking off them as they resonate and orbiting them, faster and faster ---------------------------
    var sh_t = scene_len;
    var sh_n = vec3<f32>(0.0);
    var sh_hue = 0.0;
    var sh_glow = 0.0;
    if (time > CB_ORBIT && !det) {
        for (var j = 0; j < CB_ORBITERS; j = j + 1) {
            let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), 911u, u32(seed)))) * (1.0 / 4294967295.0);
            // (round the first shards and the clusters' tallest)
            let pi = j % 16;
            if (pi >= nl) {
                continue;
            }
            let born = CB_ORBIT + 4.0 * hv.x;
            let ot = time - born;
            if (ot < 0.0) {
                continue;
            }
            // (round the spire as it stands grown: they have all grown by now)
            let si = li[pi];
            let pl = cb_place(si, seed);
            let fm = cb_form(si, seed, pl);
            let ax = cb_axis(fm);
            let B = crel + vec3<f32>(pl.x, 0.0, pl.y);
            let ro = fm.x * (1.4 + 1.6 * hv.z) + 4.0 * saturate(ot * 0.7);
            let y0 = pl.w * (0.25 + 0.6 * hv.y);
            let qa = ray_seg(rd, B + ax * (y0 - 4.0), B + ax * (y0 + 4.0));
            if (qa.x > ro + 8.0) {
                continue;
            }
            let fr = cb_frame(ax, fm.w);
            var c: Crystal;
            c.B = B;
            c.a = ax;
            c.e1 = fr[0];
            c.e2 = fr[1];
            c.hue = fract(0.13 * f32(si) + mh(u32(si), u32(seed), 23u) * 0.18 + atan2(pl.y, pl.x) / TAU * 0.6);
            let w = (0.5 + 0.8 * hv.z) * (1.0 + 3.0 * res * res) * select(-1.0, 1.0, hv.x > 0.5);
            let ph = hv.y * TAU + w * ot + 0.6 * res * res * ot * ot;
            let A = c.B + c.a * (y0 + 3.0 * sin(time * 1.3 + hv.x * 9.0));
            let Cs = A + (c.e1 * cos(ph) + c.e2 * sin(ph)) * ro;
            let sz = (0.6 + 1.2 * hv.z) * smoothstep(0.0, 0.4, ot) * (1.0 + 0.15 * c.R / 10.0);
            let sh = cb_shard(rd, Cs, sz, sz * 2.4, normalize(hv - 0.5 + vec3<f32>(0.0, 0.01, 0.0)), time * (2.0 + 4.0 * hv.x), sh_t);
            if (sh.x > 0.0 && sh.x < sh_t) {
                sh_t = sh.x;
                sh_n = sh.yzw;
                sh_hue = c.hue;
                sh_glow = 1.0 + 2.0 * res;
            }
            // (a glint of light round each)
            let qd = ray_seg(rd, Cs, Cs + vec3<f32>(0.0, 0.01, 0.0));
            add = add + cb_hue(c.hue + hue_t) * exp(-qd.x / max(sz * 1.5, qd.y * px_a * 2.0)) * 0.08 * res * cb_occ(qd.y, scene_len, sky, cloud) * k;
        }
    }
    // ---- as they burst: each spire broken into its pieces (cb_chunk), thrown out, tumbling, coming down ---------------
    var sh_brk = 0.0;
    var sh_ci = vec3<i32>(-1);
    if (det && dt < 12.0) {
        for (var i = 0; i < CB_N; i = i + 1) {
            let pl = cb_place(i, seed);
            let fm = cb_form(i, seed, pl);
            let F = vec3<f32>(pl.x, 0.0, pl.y);
            let Fc = crel + F;
            // (all of its pieces within reach of where it stood by now)
            let reach = fm.x * 1.5 + pl.w * sin(fm.y) + (40.0 + pl.w * 0.06) * min(dt, 6.0) + 10.0;
            if (ray_seg(rd, Fc - vec3<f32>(0.0, CB_BOWL_D + 4.0, 0.0), Fc + vec3<f32>(0.0, pl.w + 30.0, 0.0)).x > reach) {
                continue;
            }
            var c = cb_crystal(i, seed, CB_DET - 0.01, crel);
            let brk = cb_break(i, seed, pl.w);
            let H = c.Hb + c.tip;
            let h0 = select(0.0, brk.x, brk.x > 0.5);
            let nseg = cb_nseg(c.R, H - h0);
            let nh = select(1, 2, c.R > 7.0);
            for (var kk = 0; kk < 6; kk = kk + 1) {
                if (kk >= nseg) {
                    break;
                }
                for (var hf = 0; hf < 2; hf = hf + 1) {
                    if (hf >= nh || (hf == 1 && kk == nseg - 1)) {
                        break;
                    }
                    let o = cb_chunk(i, kk, hf, seed, F, c.a, c.e1, c.e2, c.R, H, brk);
                    if (dt > o.tp) {
                        continue;
                    }
                    let at = cb_chunk_at(o, dt);
                    let Cw = crel + at.xyz;
                    let bnd = 0.5 * length(vec2<f32>(o.L, 2.0 * o.wid)) + 2.0;
                    let tc = dot(Cw, rd);
                    if (tc < -bnd || tc - bnd > sh_t || dot(Cw, Cw) - tc * tc > bnd * bnd) {
                        continue;
                    }
                    let oo = o.C0 + rot_axis(-Cw, o.spin.xyz, -at.w);
                    let dd = rot_axis(rd, o.spin.xyz, -at.w);
                    let h = cb_hit3(c, cb_to(c, oo - F), cb_to(c, dd), o.lo, o.hi, o.sp);
                    if (h.x > 0.0 && h.x < sh_t) {
                        let kin = i32(h.z);
                        var nl: vec3<f32>;
                        if (kin < 13) {
                            nl = cb_plane(c, kin).xyz;
                        } else if (kin == 13) {
                            nl = o.lo.xyz;
                        } else if (kin == 14) {
                            nl = o.hi.xyz;
                        } else {
                            nl = o.sp.xyz;
                        }
                        sh_t = h.x;
                        sh_n = normalize(rot_axis(cb_from(c, normalize(nl)), o.spin.xyz, at.w));
                        sh_hue = c.hue;
                        sh_brk = f32(kin >= 13);
                        sh_glow = (0.25 + 1.4 * exp(-dt * 1.5)) * (1.0 + sh_brk * 1.2);
                        sh_ci = vec3<i32>(i, kk, hf);
                    }
                }
            }
        }
    }
    // (the piece in front: its edges catching the light, as the spires' do)
    var sh_edge = 0.0;
    if (sh_ci.x >= 0 && sh_t < scene_len) {
        let i = sh_ci.x;
        let pl = cb_place(i, seed);
        let c = cb_crystal(i, seed, CB_DET - 0.01, crel);
        let o = cb_chunk(i, sh_ci.y, sh_ci.z, seed, vec3<f32>(pl.x, 0.0, pl.y), c.a, c.e1, c.e2, c.R, c.Hb + c.tip, cb_break(i, seed, pl.w));
        let at = cb_chunk_at(o, dt);
        let Xo = o.C0 + rot_axis(rd * sh_t - crel - at.xyz, o.spin.xyz, -at.w);
        let ql = cb_to(c, Xo - vec3<f32>(pl.x, 0.0, pl.y));
        var e1 = 1.0e9;
        var e2 = 1.0e9;
        for (var kk = 0; kk < 16; kk = kk + 1) {
            var pk: vec4<f32>;
            if (kk < 13) {
                pk = cb_plane(c, kk);
            } else if (kk == 13) {
                pk = o.lo;
            } else if (kk == 14) {
                pk = o.hi;
            } else {
                pk = o.sp;
            }
            let dpk = max((pk.w - dot(pk.xyz, ql)) / length(pk.xyz), 0.0);
            if (dpk < e1) {
                e2 = e1;
                e1 = dpk;
            } else {
                e2 = min(e2, dpk);
            }
        }
        let ew = max(0.12, sh_t * px_a * 0.8);
        sh_edge = exp(-e2 / ew) * min(1.0, 0.12 / ew * 2.0);
    }
    if (sh_t < scene_len) {
        // a shard: its face catching the sky, its body lit from inside
        let base_c = cb_hue(sh_hue + hue_t);
        let cosi = max(dot(-rd, sh_n), 0.0);
        let fres = 0.045 + 0.955 * pow(1.0 - cosi, 5.0);
        let refl = cb_env(reflect(rd, sh_n), sky_c, sun, day, dark, base_c * 0.2);
        let inner = cb_env(refract(rd, sh_n, 0.66), sky_c, sun, day, dark, base_c * 0.2);
        let facet = 0.6 + 0.8 * fract(sin(dot(sh_n, vec3<f32>(12.9, 78.2, 37.7))) * 43758.5);
        // (a broken face fresh and pale, glittering; the spire's own faces deep and clear)
        let deep = base_c * base_c;
        let glw_c = mix(deep, mix(base_c, vec3<f32>(1.0), 0.15), sh_brk * 0.8);
        // (light through it, bent and split: its faces each a little a different colour)
        let disp = cb_spectrum(fract(dot(sh_n, vec3<f32>(3.1, 1.7, 2.3)) + dt * 0.2));
        var cc = inner * deep * facet * 0.5 + glw_c * sh_glow * 0.6 * facet + refl * fres * 1.3
            + sun_c * pow(max(dot(sh_n, normalize(sun - rd)), 0.0), 160.0) * 3.0
            + deep * disp * 0.12 * facet * sh_glow;
        cc = cc + (refl * 0.5 + mix(base_c, vec3<f32>(1.0), 0.4) * (0.3 + sh_glow * 0.5)) * sh_edge;
        let haze = 1.0 - exp(-sh_t / 3000.0);
        col = mix(cc * k + col * (1.0 - k), hazec, haze * 0.7);
        add = add * 0.1;
        scene_len = sh_t;
        sky = false;
    }

    // ---- the glitter: a cloud of tiny shards blown out and falling, each a point of coloured light that twinkles,
    //      in shells round the heart (found where the view ray crosses each shell, a star on it per cell) -------------
    if (det && dt < 10.0) {
        let fallc = vec3<f32>(0.0, -0.5 * 9.0 * dt * dt * 0.35, 0.0);
        for (var s = 0; s < 5; s = s + 1) {
            let fs = f32(s);
            let Rg = (35.0 + 48.0 * fs) * (0.25 + (1.0 - exp(-dt * (1.6 - 0.15 * fs))) * (1.1 + 0.3 * fs));
            let C = heart - vec3<f32>(0.0, 60.0 + 10.0 * fs, 0.0) + fallc * (1.0 + 0.2 * fs);
            let tc = dot(C, rd);
            let dc2 = dot(C, C) - tc * tc;
            if (dc2 > Rg * Rg) {
                continue;
            }
            let hq = sqrt(Rg * Rg - dc2);
            for (var side = 0; side < 2; side = side + 1) {
                let th = tc + select(-hq, hq, side == 1);
                if (th < 0.0 || th > scene_len) {
                    continue;
                }
                let Q = rd * th - C;
                let v = Q / Rg;
                // (the shell turns as it spreads, each its own way)
                let lon = atan2(v.z, v.x) + dt * (0.1 + 0.05 * fs) * select(-1.0, 1.0, s % 2 == 0);
                let lat = asin(clamp(v.y, -1.0, 1.0));
                let ncell = 55.0 + 14.0 * fs;
                let g2 = vec2<f32>(lon * ncell / TAU, lat * ncell / TAU * 2.0);
                let cid = floor(g2);
                let hv = vec3<f32>(pcg3d(vec3<u32>(bitcast<vec2<u32>>(vec2<i32>(cid)), u32(s) + u32(seed) * 7u))) * (1.0 / 4294967295.0);
                if (hv.z > 0.3) {
                    continue;
                }
                let star = cid + vec2<f32>(0.2, 0.2) + hv.xy * 0.6;
                // (its distance on the shell, in blocks)
                let dd = (g2 - star) * vec2<f32>(Rg * cos(lat) * TAU / ncell, Rg * TAU / ncell * 0.5);
                let w = max(0.25, th * px_a * 0.7);
                let tw = pow(0.5 + 0.5 * sin(time * (9.0 + 14.0 * hv.x) + hv.y * 40.0), 3.0);
                let lum = exp(-dot(dd, dd) / (w * w)) * min(1.0, 0.25 / w) * (0.2 + 3.0 * tw * tw);
                // (the bottom of the cloud thinning as it falls; the whole of it thinning out)
                let dens = smoothstep(-1.0, -0.3, v.y + 0.25 * dt / 3.0) * exp(-dt / (2.5 + 0.4 * fs)) * smoothstep(0.0, 0.2, dt);
                add = add + cb_spectrum(fract(hv.x * 3.7 + dt * 0.3)) * mix(1.0, 0.4, hv.y) * lum * dens * 2.4 * k;
            }
        }
    }

    // ---- the prismatic flash and the shock dome as they burst ------------------------------------------------------
    if (det && dt < 6.0) {
        let Rs = 40.0 + 260.0 * (1.0 - exp(-dt * 1.4));
        let tcs = dot(heart, rd);
        let ps = rd * max(tcs, 0.0) - heart;
        let dcs = length(ps);
        let wpx = max(6.0 + 10.0 * dt, max(tcs, 1.0) * 0.002);
        let limb = exp(-pow((dcs - Rs) / wpx, 2.0));
        add = add + mix(vec3<f32>(0.8, 0.85, 1.0), cb_spectrum(saturate((dcs - Rs) / (wpx * 2.0) + 0.5)), 0.15) * limb * exp(-dt * 2.5) * 0.18 * cb_occ(tcs, scene_len, sky, cloud) * k;
        // a ball of white light where the heart was, fading
        let ball = exp(-dcs / (30.0 + 40.0 * dt)) * exp(-dt * 2.2) * 3.0;
        add = add + mix(vec3<f32>(1.0), cb_hue(hue_t + dcs * 0.006 + dt * 0.4), 0.25 + 0.5 * saturate(dcs / (40.0 + 60.0 * dt))) * ball * cb_occ(tcs - 30.0, scene_len, sky, cloud) * k;
    }

    // ---- the lens: bloom round the heart as they resonate and burst, a ring of colour round it ----------------------
    if (pH.z > 0.0) {
        let dd = (uv - pH.xy) * vec2<f32>(aspect, 1.0);
        let dl = length(dd);
        let l = res * res * 0.4 * (1.0 - breath) + select(0.0, exp(-dt * 1.2) * 1.5, det);
        add = add + mix(vec3<f32>(0.9, 0.8, 1.0), cb_hue(hue_t), 0.4) * l / (1.0 + dl * dl * 300.0) * 0.3 * k;
    }
    add = add + mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.85, 1.1), 0.5) * flash * flash * 0.5 * k;

    // ---- combine --------------------------------------------------------------
    var outc = (col + add) * (1.0 - breath * 0.35 * k);
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.3 * dark) * k);
    let lum_o = max(luminance(outc * 0.9), 1.0e-5);
    let hue = outc * 0.9 * (aces(vec3<f32>(lum_o)).x / lum_o);
    outc = mix(aces(outc * 0.9), hue / max(1.0, max(hue.r, max(hue.g, hue.b))), 0.45);
    let srgb = linear_to_srgb(outc);
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    return vec4<f32>(srgb, 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return crystal_bloom(in);
}
