// Orbital Laser's post pass for the Rod from God (laser 11). The mod builds it from shaders/strike.wgsl up to its fs_main
// less the other lasers' own functions, followed by this file, and sets it for a rod strike only. Validate with
// tools/check-shader.sh.

// ---- laser 11: the rod from god -----------------------------------------------------------------------------------
// No beam, no explosive: a colossal rod of dark metal comes straight down out of the sky onto the target, and it is
// holy. A bright golden-white star high overhead at first, it grows fast: god rays streaming out of it and down round
// it, a column of light down its path from the sky to the target, the ionised line it lays in it, a glare of spikes
// and ghosts in the lens; for its last seconds its shape (the rod, nose down, its nose blazing, a bow of glowing air
// round it, the shock cone in its last second); the last second very fast. It strikes: impact frames (a few stark,
// stylised frames for a split second, the rod going in among them), a blinding radiant burst with god rays fanning out
// of it, the land rippling out in rings like a liquid, a narrow jet of molten rock up its path, a short plume of dust,
// a ring of dust racing out over the ground, molten spatter landing round it. It stays: standing upright in the
// crater's middle (real blocks, rod.rs's RD_ROD_UP), glowing, its light rising softly out of the crater, the air over
// it shimmering, the crater's floor white-hot round its foot and cooling over twenty seconds.
// strike/rod.rs samples the path into the table (rd_table, render.set-data): keep the PL_* in step with its RD_*.
const PL_SEEN: f32 = 1.0;          // the rod shows, high in the sky,
const PL_HIT: f32 = 7.0;           // and strikes,
const PL_BURST: f32 = 0.0;         // on the ground under the target (pl_g0)
const PL_LEN: f32 = 60.0;          // the strike's length (lasers.rs): everything fades out over its last PL_FADE
const PL_FADE: f32 = 8.0;
const PL_SOFT0: f32 = 5.0;         // the plume keeps its crisp lumps this long after the impact, then loses them
const PL_SOFT1: f32 = 10.0;        // by this, a soft, drifting haze thinning away (gone 13 s after the impact)
const PL_CHURN: f32 = 7.0;         // the head's lumps carried this long before they are let go (pl_col_sdf)
const PL_V: f32 = 343.0;           // the shockwave's front, blocks a second (with the blast's sound: rod.rs)
const PL_P: u32 = 16u;             // the table: the path's samples from PL_P, three words each,
const PL_HF: u32 = 1024u;          // the land's heightfield (rod.rs's rd_hf_words): its size, then heights, shelter
const PL_DEBRIS: i32 = 256;
const PL_DB: u32 = 10496u;         // the debris (rod.rs's rd_debris_words), PL_DW words each
const PL_DW: u32 = 10u;
fn pl_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn pl_u(i: u32) -> u32 {
    if (i >= arrayLength(&mod_data)) {
        return 0u;
    }
    return mod_data[i];
}
fn pl_n() -> i32 {
    return i32(pl_w(0u) + 0.5);
}
fn pl_sample(i: i32) -> vec3<f32> {
    let b = PL_P + 3u * u32(clamp(i, 0, pl_n() - 1));
    return vec3<f32>(pl_w(b), pl_w(b + 1u), pl_w(b + 2u));
}
// Where the object is at strike time t (from the target's ground): the samples, smoothly between (Catmull-Rom).
fn pl_head(t: f32) -> vec3<f32> {
    let u = (t - pl_w(1u)) / max(pl_w(2u), 1.0e-3);
    let i = i32(floor(u));
    let f = u - floor(u);
    let p0 = pl_sample(i - 1);
    let p1 = pl_sample(i);
    let p2 = pl_sample(i + 1);
    let p3 = pl_sample(i + 2);
    let f2 = f * f;
    let f3 = f2 * f;
    return 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f3);
}
fn pl_wind() -> vec3<f32> {
    return vec3<f32>(pl_w(3u), 0.0, pl_w(4u));
}
// When the rod's nose was at height y (from the target's ground) on its way down: the path's samples searched.
fn rd_time_at(y: f32) -> f32 {
    let n = pl_n();
    let y0 = pl_sample(0).y;
    if (y >= y0) {
        return pl_w(1u) - (y - y0) / 250.0;
    }
    if (y <= pl_sample(n - 1).y) {
        return pl_w(1u) + pl_w(2u) * f32(n - 1);
    }
    var lo = 0;
    var hi = n - 1;
    for (var k = 0; k < 8; k = k + 1) {
        if (hi - lo <= 1) {
            break;
        }
        let m = (lo + hi) / 2;
        if (pl_sample(m).y > y) {
            lo = m;
        } else {
            hi = m;
        }
    }
    let ya = pl_sample(lo).y;
    let yb = pl_sample(hi).y;
    return pl_w(1u) + pl_w(2u) * (f32(lo) + saturate((ya - y) / max(ya - yb, 1.0e-3)));
}
// The ray against the line through a and b, its nearest point kept between lo and hi along it (0 at a, 1 at b): the
// distance between them, how far along the ray, how far along ab.
fn pl_ray_seg(rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>, lo: f32, hi: f32) -> vec3<f32> {
    let ab = b - a;
    let l2 = max(dot(ab, ab), 1.0e-6);
    let rab = dot(rd, ab);
    let den = l2 - rab * rab;
    var s = clamp(select(0.0, (rab * dot(rd, a) - dot(a, ab)) / den, den > 1.0e-6), lo, hi);
    let t = max(dot(rd, a + ab * s), 0.0);
    s = clamp(dot(rd * t - a, ab) / l2, lo, hi);
    return vec3<f32>(length(rd * t - (a + ab * s)), t, s);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ---- the dust of the shockwave: a low wall racing out over the land, rising and hanging behind it ---------------
// The ground at r out where the heightfield does not reach (or before it is in): the target's, rising or falling to
// the player's as it goes out to them.
fn pl_gref(r: f32, me: vec3<f32>, C: vec3<f32>, dme: f32) -> f32 {
    return mix(0.0, me.y - C.y, smoothstep(0.0, max(dme, 1.0), r));
}
// The land at q (level, from the target): its ground (from the target's) and how sheltered it is from the blast by the
// land between (0 to 1), from the heightfield, smoothly between its cells; `gref` until it is in.
fn pl_land(q: vec2<f32>, gref: f32) -> vec2<f32> {
    let nf = pl_w(PL_HF);
    if (nf < 2.0) {
        return vec2<f32>(gref, 0.0);
    }
    let n = u32(nf + 0.5);
    if (arrayLength(&mod_data) < PL_HF + 8u + n * n) {
        return vec2<f32>(gref, 0.0);
    }
    let R = pl_w(PL_HF + 1u);
    let step = 2.0 * R / (nf - 1.0);
    let fc = clamp((q + R) / step, vec2<f32>(0.0), vec2<f32>(nf - 1.001));
    let i0 = vec2<u32>(floor(fc));
    let t = fc - floor(fc);
    var hv = vec4<f32>(0.0);
    var sv = vec4<f32>(0.0);
    for (var j = 0u; j < 4u; j = j + 1u) {
        let c = mod_data[PL_HF + 8u + (i0.y + (j >> 1u)) * n + i0.x + (j & 1u)];
        hv[j] = f32(c & 0xffffu) / 8.0 - 512.0;
        sv[j] = f32((c >> 16u) & 0xffu) / 255.0;
    }
    // (past its edge, the edge's ground carried on: not `gref`, which rises to wherever the player stood, up a tower
    // or in the air)
    let g = mix(mix(hv.x, hv.y, t.x), mix(hv.z, hv.w, t.x), t.y);
    let sh = mix(mix(sv.x, sv.y, t.x), mix(sv.z, sv.w, t.x), t.y);
    let e = smoothstep(-step, 3.0 * step, max(abs(q.x), abs(q.y)) - R);
    return vec2<f32>(g, sh * (1.0 - e));
}
// The ground under the burst (from the target's): the heightfield's round the target, so a strike aimed at a
// treetop, a ledge or the top of a slope still bursts just over the land, not over the air beside it; the target's own
// until the heightfield is in. Never over the target's (the designator hit something there).
fn pl_g0() -> f32 {
    var g = pl_land(vec2<f32>(0.0), 0.0).x;
    for (var i = 0; i < 4; i = i + 1) {
        let an = 1.5708 * f32(i) + 0.785;
        g = g + pl_land(vec2<f32>(cos(an), sin(an)) * 14.0, 0.0).x;
    }
    return clamp(g / 5.0, -40.0, 0.0);
}
// The dust at p (camera-relative), `side`: how square the ray crosses the ring there (0 along it): a dense, opaque wall
// a few blocks high just behind a crisp, billowing front, thinning behind it into haze that rises and hangs. All of it
// over the land's own ground (the heightfield, and close to where this pixel's ray meets the land, that point's own
// height: `loc`, its xz from the target, how far it stands off the heightfield there, and the reach of that squared),
// climbing the rises, filling the hollows, thinner and later in the lee of a ridge. Its density, and its height over
// the ground.
fn pl_dust(p: vec3<f32>, C: vec3<f32>, a: f32, me: vec3<f32>, dme: f32, side: f32, loc: vec4<f32>) -> vec2<f32> {
    let q = p - C;
    let r = length(q.xz);
    let w = p + frame.camera_position.xyz;
    let land = pl_land(q.xz, pl_gref(r, me, C, dme));
    let dl = q.xz - loc.xy;
    let h = q.y - land.x - loc.z * exp(-dot(dl, dl) / loc.w);
    let sh = land.y;
    if (h > 120.0 || h < -4.0) {
        return vec2<f32>(0.0, h);
    }
    // (the front billows: pushed on and held back by the turbulence it churns, more so higher up)
    let rf = PL_V * a;
    let n1 = gnoise3(w * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a, 0.0));
    // (its fine churn only near the front: well behind it, where the wall has gone, the haze's patches are big ones)
    var n2 = 0.5;
    if (rf - r - 0.25 * max(h, 0.0) - 22.0 * sh < 170.0) {
        n2 = gnoise3(w * (1.0 / 3.5) + vec3<f32>(5.0, -2.0 * a, 1.0));
    }
    // (held back in the lee of a ridge, more so the deeper it lies under it)
    let s = rf - r + (n1 - 0.5) * 14.0 + (n2 - 0.5) * 5.0 - 0.25 * max(h, 0.0) - 22.0 * sh;
    if (s < -3.0) {
        return vec2<f32>(0.0, h);
    }
    let since = max(s, 0.0) / PL_V;
    // (the wall: a person's height and more, higher as it goes and behind its front; its top ragged)
    let n3 = gnoise3(w * (1.0 / 38.0) + vec3<f32>(0.0, -0.3 * a, 9.0));
    // (tallest a little behind the front, settling lower behind it)
    // (low, as in the clips: a person's height to a tree's, not a cliff of it, so the picture over it stays clear)
    let rise = 1.0 + 0.8 * smoothstep(0.0, 25.0, s) - 0.7 * smoothstep(30.0, 140.0, s);
    // (the rod's: lower and thinner than the Nuke's, a ring of dust hugging the ground)
    let hw = (6.5 + 0.01 * r) * rise * (0.35 + 1.2 * n1) * (0.6 + 0.8 * n3) + 1.2 * min(since, 6.0);
    let up = smoothstep(hw, hw * 0.35, h) * smoothstep(-4.0, 0.0, h);
    let lead = smoothstep(-3.0, 1.5, s);
    let wall = 1.1 * exp(-s / (16.0 + 0.02 * r)) * (0.75 + 0.25 * side) * (1.0 - 0.6 * sh);
    let haze = (0.009 * exp(-since / 2.5) + 0.0025 * exp(-since / 6.0)) * (0.5 + n2);
    // (none round the column's foot: the blast cleared it, and it would tint the smoke)
    let mid = smoothstep(40.0, 120.0, r);
    // (and what it leaves low over the land for a few seconds, in drifting patches)
    let low = 0.22 * (1.0 - 0.45 * sh) * exp(-since / 3.0) * smoothstep(0.0, 30.0, s) * exp(-max(h, 0.0) / (2.5 + 2.0 * n1)) * smoothstep(0.35, 0.7, n3);
    return vec2<f32>(((wall * saturate(1.5 * n1 + 0.25 * n2) * (0.35 + 1.3 * n3) + haze * (1.0 - 0.4 * sh)) * up + low) * lead * mid, h);
}
// ---- the debris: chunks and specks of earth thrown out, falling back far round it ---------------------------------
struct PlChunk {
    p: vec3<f32>,
    v: vec3<f32>,
    s: f32,
    live: f32,
}
fn pl_chunk(i: i32, a: f32, eka: f32, C: vec3<f32>) -> PlChunk {
    var o: PlChunk;
    // (its numbers worked out once by payload.rs's pl_debris_words: its bearing, how far out it is torn up as the blast
    // reaches it, its speed out and up (most thrown a few hundred blocks, a third far), when, its size, e^(k t0))
    let b = PL_DB + PL_DW * u32(i);
    let tau = a - pl_w(b + 5u);
    o.s = pl_w(b + 6u);
    o.live = 0.0;
    if (tau <= 0.0) {
        return o;
    }
    let dir = vec3<f32>(pl_w(b), 0.0, pl_w(b + 1u));
    let vh = pl_w(b + 3u);
    let vy = pl_w(b + 4u);
    // (a little drag: they slow, and fall less than straight)
    let k = 0.06;
    let ek = eka * pl_w(b + 7u);
    let e = (1.0 - ek) / k;
    let g = 9.8;
    o.p = C + dir * (pl_w(b + 2u) + vh * e) + vec3<f32>(0.0, 2.0 + vy * e - g * (tau - e) / k, 0.0);
    o.v = dir * (vh * ek) + vec3<f32>(0.0, (vy + g / k) * ek - g / k, 0.0);
    o.live = 1.0;
    return o;
}
// How much of a chunk is still in the air (0 once it is down): the land under it looked up only when it is down near the
// highest of it, and only for the chunks near this pixel's ray.
fn pl_chunk_up(ch: PlChunk, C: vec3<f32>, me: vec3<f32>, dme: f32) -> f32 {
    let r = length((ch.p - C).xz);
    var gref = C.y + pl_gref(r, me, C, dme);
    if (ch.p.y < max(gref, C.y + pl_w(PL_HF + 3u)) + 3.0) {
        gref = C.y + pl_land((ch.p - C).xz, gref - C.y).x;
    }
    return smoothstep(gref - 1.0, gref + 2.0, ch.p.y);
}

const PL_DM: f32 = 26.0;           // the most the plume's lumps stand out of its smooth body (pl_col_sdf), which the
                                   // march's bounds, gates and long steps allow for
const PL_S: f32 = 0.85;            // the lumps' scale (the Nuke's 2.2: a small plume, fine lumps)
// ---- the plume of dust: pulverised earth thrown up out of the crater, a short column flaring into a ragged head,
// falling back and spreading low over the land round its foot, gone in half a minute ----------------------------
struct PlCol {
    a: f32,
    C: vec3<f32>,
    // (the head: its middle's height over the ground and its radius (Rt none: no roll); the column's top height and its
    // radius at the foot, in the middle and at the top; the ring (none); the base surge: its radius and its roll's width
    // and height)
    hc: f32,
    Rt: f32,
    rt: f32,
    st: f32,
    sr: vec3<f32>,
    ring: vec3<f32>,
    surge: vec3<f32>,
    lo: vec3<f32>,
    hi: vec3<f32>,
}
// How far the column's lumps have been carried along it by `a`: up fast as it is thrown up, then down as it falls back.
fn pl_boil(a: f32) -> f32 {
    return 14.0 * min(a, 2.0) + 4.0 * clamp(a - 2.0, 0.0, 4.0) - 2.2 * max(a - 7.0, 0.0);
}
fn pl_column(a: f32, C: vec3<f32>) -> PlCol {
    var o: PlCol;
    o.a = a;
    o.C = C;
    // (thrown up fast, about a hundred high within a few seconds, still drifting up as it thins; its head spreading out
    // wide as it rises and fades, a broad haze rather than a puff)
    let rise = 1.0 - exp(-a / 1.4);
    let fall = smoothstep(4.0, 13.0, a);
    o.st = 85.0 * rise + 2.5 * a + 6.0;
    // (a fan of dust out of the crater, wider and wider up it as it rises and fades: no head on a stem, the whole of it
    // spreading into a broad haze)
    o.sr = vec3<f32>(24.0 + 5.0 * saturate(a / 3.0) + 1.5 * a, 20.0 + 6.0 * saturate(a / 4.0) + 4.0 * a, 26.0 + 10.0 * saturate(a / 4.0) + 7.5 * a);
    o.rt = (0.42 * o.sr.z) * (0.4 + 0.6 * rise) * (1.0 - 0.3 * fall);
    o.hc = max(o.st - 0.5 * o.rt, 0.6 * o.rt);
    o.Rt = 0.0;
    o.ring = vec3<f32>(0.0);
    // (the base surge: what falls back, rolling out over the ground round its foot, spreading and settling)
    o.surge = vec3<f32>(30.0 + 100.0 * (1.0 - exp(-a / 8.0)), 14.0 + 0.3 * a, 5.0 + 6.0 * saturate(a / 10.0));
    let top = o.st + 0.6 * o.rt;
    let w = max(max(o.sr.z, o.rt * 1.3), o.surge.x + o.surge.y) + 40.0;
    let lean = pl_wind() * a;
    o.lo = C + vec3<f32>(-w + min(lean.x, 0.0), -24.0, -w + min(lean.z, 0.0));
    o.hi = C + vec3<f32>(w + max(lean.x, 0.0), top + 40.0, w + max(lean.z, 0.0));
    return o;
}
// The column's lean with the wind at p (its head carried furthest, its foot staying put).
fn pl_lean(col: ptr<function, PlCol>, hy: f32) -> vec3<f32> {
    return pl_wind() * ((*col).a * 0.5 * pow(saturate(hy / max((*col).st, 1.0)), 1.5));
}
// The column's smooth body at p (camera-relative): the column flaring up into its head, the base surge; .y none (no
// ring).
fn pl_col_base2(col: ptr<function, PlCol>, p: vec3<f32>) -> vec2<f32> {
    let C = (*col).C;
    let hy0 = p.y - C.y;
    let q = p - C - pl_lean(col, hy0);
    let hy = q.y;
    let rho = length(q.xz);
    let rt = (*col).rt;
    let hc = (*col).hc;
    // (the head: a ragged swelling ball, a little flattened)
    // (flattening as it spreads)
    let eq = vec3<f32>(q.x, (hy - hc) * (1.35 + 0.18 * (*col).a), q.z);
    let ek0 = length(eq / rt);
    var d = (ek0 - 1.0) * rt * 0.85;
    // (the column: from under the crater's floor up into the head, flaring)
    let u = saturate(hy / max((*col).st, 1.0));
    let sr = (*col).sr;
    let rs = mix(mix(sr.x, sr.y, smoothstep(0.0, 0.25, u)), sr.z, smoothstep(0.35, 1.0, u)) * (0.9 + 0.2 * sin(hy * 0.05 + 1.3));
    // (its top not cut flat at the head's middle but domed: highest over its axis, falling away towards its edge, so it
    // rounds off into the head and thins out there rather than ending at a ceiling (the dome's slope makes this a
    // little long as a distance: scaled down))
    let dome = hc + 0.35 * rt - 0.55 * rs * pow(saturate(rho / max(rs, 1.0)), 2.0);
    let ds = max(rho - rs, max(hy - dome, -hy - 24.0)) * 0.8;
    d = smin(d, ds, 26.0);
    // (the base surge: a low roll of dust round the foot, out where the land is)
    let sg = (*col).surge;
    let a = (*col).a;
    if (a > 0.2) {
        let e = vec2<f32>((rho - sg.x) / sg.y, (hy - 0.3 * sg.z) / sg.z);
        let inner = max(sg.x - rho, 0.0) / (sg.x * 0.9);
        let ds2 = (length(e) - 1.0) * min(sg.y, sg.z);
        // (rising out of the ground as the column falls back onto it, settling late on)
        let settle = 18.0 * smoothstep(24.0, 55.0, a) + 30.0 * (1.0 - smoothstep(1.0, 6.0, a));
        d = smin(d, ds2 + 12.0 * smoothstep(0.0, 0.6, inner) + settle, 18.0);
        // (and a low sheet of dust inside the roll, from it in to the column's foot)
        let sheet = max(rho - sg.x, abs(hy - 0.2 * sg.z) - 0.32 * sg.z);
        d = smin(d, sheet + 9.0 + settle, 16.0);
    }
    return vec2<f32>(d, 1.0e6);
}
fn pl_col_base(col: ptr<function, PlCol>, p: vec3<f32>) -> f32 {
    let b = pl_col_base2(col, p);
    return min(b.x, b.y);
}
// Cauliflower lumps: domes over a jittered lattice (a feature point in each of the eight cells round p, well jittered),
// each its own size, rounded on top and meeting in creases: about 1 on a big dome's crown, 0 in a crease.
fn pl_dome(p: vec3<f32>) -> f32 {
    let b = floor(p - 0.5);
    var hmax = 0.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let o = vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let cell = b + o;
        let q = bitcast<vec3<u32>>(vec3<i32>(cell));
        let h = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x51u)));
        let jit = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) * (0.7 / 1023.0) + 0.15;
        let sz = 0.7 + 0.55 * f32(pcg(h) & 1023u) / 1023.0;
        let e = cell + jit - p;
        hmax = max(hmax, sz * sqrt(saturate(1.0 - dot(e, e) * 1.7 / (sz * sz))));
    }
    return hmax;
}
fn pl_rot(k: i32, p: vec3<f32>) -> vec3<f32> {
    if (k == 0) {
        return mat3x3<f32>(-0.0014, 0.9977, -0.0674, -0.2224, -0.0660, -0.9727, -0.9750, 0.0136, 0.2220) * p;
    }
    if (k == 1) {
        return mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971) * p;
    }
    return mat3x3<f32>(-0.9891, -0.1223, 0.0816, 0.0968, -0.9594, -0.2651, 0.1107, -0.2543, 0.9608) * p;
}
// The cloud's surface at p: its smooth body bulged out in lumps on lumps (as the Payload's column), the lumps carried
// round the cap's roll as it churns (up its inside, out over its top, down its outside), boiling slowly up the stem.
// .x the distance, .y how far up a dome it lies, .z how soft its edge is, .w the fine fray.
fn pl_col_sdf(col: ptr<function, PlCol>, p: vec3<f32>, d0: f32, fine: bool) -> vec4<f32> {
    let a = (*col).a;
    let C = (*col).C;
    var q = p - C - pl_lean(col, p.y - C.y);
    // (the roll: the cap's big lumps carried round its core circle, up the inside, out over the top, down the outside
    // and back in under it, nearly as one through the roll and letting go outside it. Turned on and on they would wind
    // up into streaks, so they are carried for a while and then let go, two sets of them half a turn of that apart,
    // each fading in as the other fades out: the flow goes on and never winds up. The smaller lumps stay put.)
    let rho = max(length(q.xz), 1.0e-3);
    let dir = q.xz / rho;
    let uv = vec2<f32>(rho - (*col).Rt, q.y - (*col).hc);
    let wq = dot(uv, uv) / pow(1.6 * (*col).rt, 2.0);
    // (none on the axis: the lumps either side of it turn opposite ways, and turned there they parted in a seam down
    // the cap's middle)
    let wr = exp(-wq * wq) * smoothstep(0.0, 0.8 * (*col).Rt + 10.0, rho);
    // (how fast it turns, radians a second: quickening as the ring forms, slowing as it spreads)
    let om = 0.12 * exp(-a / 8.0) + 0.02;
    let ph = fract(a / PL_CHURN);
    let wA = 1.0 - abs(2.0 * ph - 1.0);
    // (and the stem's boiling up it: its lumps carried up, the same way all down it to the land, so they move without
    // stretching; let go of over most of the cap's height, under its roll, where the roll's own churn takes over)
    q.y = q.y - pl_boil(a) * (1.0 - exp(-wq * wq)) * (1.0 - smoothstep((*col).hc - 1.7 * (*col).rt, (*col).hc - 0.5 * (*col).rt, q.y));
    let S = PL_S;
    let w = gnoise3(pl_rot(1, q * (1.0 / (55.0 * S))));
    let w2 = gnoise3(pl_rot(2, q * (1.0 / (23.0 * S)) + vec3<f32>(9.2, -0.05 * a, 4.4)));
    var b1 = 0.0;
    // (the light's look at it, not the eye's: only the set more there, near enough)
    let kd = select(0, 1, wA < 0.5);
    var wsum = 0.0;
    for (var k = select(kd, 0, fine); k < select(kd + 1, 2, fine); k = k + 1) {
        let tk = fract(ph + 0.5 * f32(k)) * PL_CHURN;
        let ang = om * tk * wr;
        let cs = cos(ang);
        let sn = sin(ang);
        let uv2 = vec2<f32>(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);
        let qk = vec3<f32>(dir.x * (uv2.x + (*col).Rt), q.y + uv2.y - uv.y, dir.y * (uv2.x + (*col).Rt));
        // (each set its own lumps, a new lot each time it starts over)
        let cyc = floor(a / PL_CHURN + 0.5 * f32(k));
        wsum = wsum + select(1.0 - wA, wA, k == 0);
        b1 = b1 + select(1.0 - wA, wA, k == 0) * pl_dome(pl_rot(0, qk * (1.0 / (36.0 * S)) + vec3<f32>(3.1 + 7.3 * cyc, 0.0, 7.7 - 4.1 * cyc + 2.9 * f32(k)) + 0.3 * vec3<f32>(w2 - 0.5)));
    }
    // (two half sets added are evener than one: their spread put back)
    b1 = select(b1 / max(wsum, 1.0e-3), 0.62 + (b1 - 0.62) / sqrt(wA * wA + (1.0 - wA) * (1.0 - wA)), fine);
    let hy = p.y - C.y;
    let lump = 1.6 * (PL_S / 2.2) * (0.7 + 0.3 * smoothstep(20.0, 120.0, hy));
    let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
    let crisp = 1.0 - 0.8 * soft;
    let b2 = pl_dome(pl_rot(1, q * (1.0 / (14.0 * S)) + vec3<f32>(0.0, -0.15 * a, 1.3)));
    let up = smoothstep(40.0, 200.0, hy);
    // (the crown over the middle smoother than the roll: its big swells let down, so it stays one rounded dome)
    let crown = (1.0 - smoothstep(0.3 * (*col).Rt, (*col).Rt + 0.3 * (*col).rt, rho)) * smoothstep((*col).hc, (*col).hc + 0.5 * (*col).rt, hy);
    var d = d0 - (26.0 * (b1 - 0.45) * crisp * (0.4 + 0.6 * up) * (1.0 - 0.2 * crown) + 9.0 * (b2 - 0.45) * (1.0 - 0.7 * soft) + (18.0 + 8.0 * soft) * (w - 0.5) * (1.0 - 0.35 * crown) + 8.0 * (w2 - 0.5)) * lump;
    let ew = smoothstep(0.6, 0.82, w2);
    // (soft by the ground, and soft over its top, where it frays out into haze)
    let edge = mix(1.5, 6.0, ew) + 10.0 * (1.0 - smoothstep(0.0, 60.0, hy)) + 18.0 * smoothstep((*col).hc - 0.6 * (*col).rt, (*col).hc + 0.9 * (*col).rt, hy);
    var fray = 0.5;
    if (fine && d < 20.0 && soft < 0.99) {
        let b3 = pl_dome(pl_rot(2, q * (1.0 / (5.5 * S)) + vec3<f32>(1.7, -0.25 * a, -2.1)));
        d = d - 4.0 * (b3 - 0.45) * (1.0 - soft) * lump;
        fray = gnoise3(pl_rot(0, q * (1.0 / (1.8 * S))) + vec3<f32>(5.0, 1.0, -0.4 * a));
        d = d - 3.5 * (fray - 0.5) * (1.0 - soft) * (0.25 + 0.75 * ew);
    }
    // (the lumps' height capped smoothly at PL_DM, so that nothing stands out past the bounds the march allows)
    let bump = max(d0 - d, 0.0);
    d = d0 - bump / sqrt(sqrt(1.0 + pow(bump / PL_DM, 4.0))) + max(d - d0, 0.0);
    return vec4<f32>(d, b1 * (0.45 + 0.55 * b2), edge, fray);
}
// A ray against a box, camera-relative: the entry and exit distances.
fn pl_box(rd: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>) -> vec2<f32> {
    let inv = 1.0 / select(rd, vec3<f32>(1.0e-6), abs(rd) < vec3<f32>(1.0e-6));
    let ta = lo * inv;
    let tb = hi * inv;
    let tmin = min(ta, tb);
    let tmax = max(ta, tb);
    return vec2<f32>(max(max(tmin.x, tmin.y), max(tmin.z, 0.0)), min(min(tmax.x, tmax.y), tmax.z));
}

// What a stage of the pass gives: the picture (the whole pass and the join), or the half-size stage's (premultiplied
// colour and transmittance) and beside it how far its ray went and the column's distance (`fs_half`).
struct PlOut {
    c: vec4<f32>,
    e: vec4<f32>,
}
// Over what a half-size stage has gathered so far: smoke of colour c covering x of what is behind (col * (1 - x) + c * x).
fn pl_over(h: ptr<function, vec4<f32>>, c: vec3<f32>, x: f32) {
    *h = vec4<f32>((*h).rgb * (1.0 - x) + c * x, (*h).a * (1.0 - x));
}
// ---- the rod itself: a round dark metal rod, nose down, RD_L long and RD_R round ----------------------------------
const RD_R: f32 = 6.3;             // its radius (thirteen blocks across, as the one left standing: rod.rs's RD_ROD_R2)
const RD_L: f32 = 171.0;           // its length (rod.rs's RD_ROD_UP + RD_ROD_DOWN + 1)
const RD_NOSE: f32 = 16.0;         // its nose, rounded to a blunt point over this much of its length
const RD_DOWN: f32 = 40.0;         // how much of it ends up under the crater's floor (rod.rs's RD_ROD_DOWN)
const RD_TOP_END: f32 = 80.0;      // where its top ends up, from the target's ground (rod.rs: 50 deep, 130 over the floor)
const RD_LET_GO: f32 = 1.8;        // drawn till this long after it strikes, its blocks surely in (rod.rs: by ~1.0), then let go over a second
const RD_SINK: f32 = 0.12;         // how fast it drives in as it strikes (its tail gone under the land in a fifth of a second)
const RD_FLOOR: f32 = -50.0;       // the crater's floor under it (rod.rs's RD_CRATER_D)
const RD_RIP_V: f32 = 190.0;       // the ripple through the land: its front's speed, blocks a second,
const RD_RIP_L: f32 = 19.0;        // its rings' spacing
const RD_JV: f32 = 190.0;          // the jet: the fastest of what it throws up its path (blocks a second),
const RD_JG: f32 = 60.0;           // falling back this hard: up some 300 in three seconds, all down by six
const RD_GOLD: vec3<f32> = vec3<f32>(1.0, 0.8, 0.5);
const RD_WGOLD: vec3<f32> = vec3<f32>(1.0, 0.88, 0.64);

// Where its top ends up, from the target's ground: RD_TOP_END, or lower on land so high its top would pass the world's
// highest block (318: its top face 319), the whole rod driven in deeper, as rod.rs's rd_rod_base lays it.
fn rd_top_end() -> f32 {
    return min(RD_TOP_END, 319.0 - (block_y() + 1.0));
}
// Where its nose is (from the target's ground) at strike time t: coming down the path, then driven in, stopping with its
// top RD_TOP_END over the land (the crater dug round it).
fn rd_nose_y(t: f32) -> f32 {
    if (t < PL_HIT) {
        return pl_head(max(t, PL_SEEN)).y;
    }
    return (rd_top_end() - RD_L) * (1.0 - exp(-(t - PL_HIT) / RD_SINK));
}
// What its outside is at h up it (from its nose), as the one left standing is built (rod.rs's rd_rod_col): 0 the
// forged dark metal (polished blackstone), 1 a band of gold, 2 a carved band (chiseled blackstone).
fn rd_band(h: f32) -> i32 {
    let y = floor(h) - RD_DOWN;                           // (blocks over the crater's floor, once it stands)
    let top = RD_L - 1.0 - RD_DOWN;
    if (y == top - 2.0 || y == top - 5.0 || y == 1.0 || y == 2.0) {
        return 1;
    }
    if (y >= 4.0 && y < top - 8.0 && (y - 4.0) % 9.0 == 0.0) {
        return select(2, 1, i32((y) / 9.0) % 3 == 1);
    }
    return 0;
}
// The rod's surface at q (from its nose, up its axis): its distance (a little short, safe to step by).
fn rd_rod_sdf(q: vec3<f32>) -> f32 {
    let rho = length(q.xz);
    let u = saturate(q.y / RD_NOSE);
    let rr = RD_R * (1.0 - (1.0 - u) * (1.0 - u));
    // (its bands a little proud of it)
    let band = select(0.0, 0.18, rd_band(q.y) != 0 && q.y > RD_NOSE);
    return max((rho - rr - band) * 0.8, max(-q.y, q.y - RD_L));
}
struct RdHit {
    t: f32,
    cov: f32,
    q: vec3<f32>,
}
// The ray against the rod (its nose at N, camera-relative): how far, how much of the pixel it covers (its edge
// smoothed over a pixel), and where on it (from its nose).
fn rd_rod_hit(rd: vec3<f32>, N: vec3<f32>, px_a: f32, tmax: f32) -> RdHit {
    var o: RdHit;
    o.cov = 0.0;
    o.t = 1.0e9;
    let sg = pl_ray_seg(rd, N, N + vec3<f32>(0.0, RD_L, 0.0), 0.0, 1.0);
    if (sg.x > RD_R + 0.4 + 1.5 * sg.y * px_a || sg.y > tmax + RD_L) {
        return o;
    }
    let sn = max(length(cross(rd, vec3<f32>(0.0, 1.0, 0.0))), 0.04);
    let span = min(RD_L + 2.0 * RD_R, (RD_R + 1.0) / sn) + 2.0;
    var t = max(sg.y - span, 0.0);
    let t_end = min(sg.y + span, tmax);
    var best = 1.0e9;
    var tb = sg.y;
    for (var i = 0; i < 40; i = i + 1) {
        if (t > t_end) {
            break;
        }
        let q = rd * t - N;
        let d = rd_rod_sdf(q);
        let fp = max(t * px_a, 1.0e-3);
        if (d / fp < best) {
            best = d / fp;
            tb = t;
        }
        if (d < 0.0015 * t + 0.01) {
            best = 0.0;
            tb = t;
            break;
        }
        t = t + max(d, 0.03 + 0.2 * fp);
    }
    o.cov = 1.0 - smoothstep(0.0, 0.9, best);
    o.t = tb;
    o.q = rd * tb - N;
    return o;
}
fn rd_rod_normal(q: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.05, -0.05);
    return normalize(e.xyy * rd_rod_sdf(q + e.xyy) + e.yyx * rd_rod_sdf(q + e.yyx) + e.yxy * rd_rod_sdf(q + e.yxy) + e.xxx * rd_rod_sdf(q + e.xxx));
}

// ---- its light -------------------------------------------------------------------------------------------------------
// The shafts its light breaks into, by the way they go out from it (a unit vector): about 1 in a shaft, 0 between.
fn rd_beams(dv: vec3<f32>, time: f32) -> f32 {
    let n = 0.75 * vnoise3(dv * 8.0 + vec3<f32>(0.0, 0.04 * time, 3.0)) + 0.25 * vnoise3(dv * 17.0 + vec3<f32>(5.1, -0.07 * time, 1.3));
    return smoothstep(0.45, 0.75, n);
}
// The scene's depth (as the depth buffer holds it: reversed, 0 the sky) of a point P, camera-relative, a few blocks
// nearer: what is at a smaller depth than this lies beyond it.
fn rd_depth_of(P: vec3<f32>) -> f32 {
    let n = frame.view_params.x;
    let f = frame.view_params.y;
    let zv = max(-(frame.view * vec4<f32>(P, 1.0)).z - 6.0, n);
    return (n * f / zv - n) / (f - n);
}
// Screen-space god rays from the light at S (its place on the screen, and its depth, rd_depth_of): streaks out from
// it, broken where the land, the trees, anything nearer than it stands between (eight looks along the way to it).
fn rd_srays(uv: vec2<f32>, S: vec3<f32>, dS: f32, time: f32, j: f32) -> f32 {
    if (S.z < 0.0) {
        return 0.0;
    }
    let asp = frame.resolution.x / frame.resolution.y;
    let q = (uv - S.xy) * vec2<f32>(asp, 1.0);
    let r = length(q);
    let dir = q / max(r, 1.0e-4);
    let pat = 0.65 * vnoise(dir * 7.0 + vec2<f32>(0.05 * time, 0.0)) + 0.35 * vnoise(dir * 19.0 - vec2<f32>(0.0, 0.08 * time) + 11.0);
    let streak = smoothstep(0.3, 0.85, pat);
    let fall = exp(-r / 0.4) + 0.12 * exp(-r / 0.1);
    if ((0.08 + streak) * fall < 0.01) {
        return 0.0;
    }
    var lit = 0.0;
    for (var i = 0; i < 8; i = i + 1) {
        let su = mix(uv, S.xy, (f32(i) + j) / 8.0);
        if (any(su < vec2<f32>(0.0)) || any(su > vec2<f32>(1.0))) {
            lit = lit + 1.0;
            continue;
        }
        lit = lit + select(0.0, 1.0, depth_at(su) < dS);
    }
    return (0.08 + streak) * (lit / 8.0) * fall;
}
// How much of a light at P (camera-relative) is in sight: five looks at the depth round where it is on the screen.
fn rd_seen(P: vec3<f32>) -> f32 {
    let s = project_rel(P);
    if (s.z < 0.0) {
        return 0.0;
    }
    let dP = length(P);
    var v = 0.0;
    for (var i = 0; i < 5; i = i + 1) {
        let o = vec2<f32>(f32(i % 3) - 1.0, f32(i / 3) * 2.0 - 1.0) * 2.0 * frame.resolution.zw * select(1.0, 0.0, i == 4);
        let su = s.xy + o;
        if (any(su < vec2<f32>(0.0)) || any(su > vec2<f32>(1.0))) {
            v = v + 1.0;
            continue;
        }
        let d = depth_at(su);
        v = v + select(0.0, 1.0, is_sky(d) || length(world_offset(su, d)) > dP - 4.0);
    }
    return v / 5.0;
}
// The glare of a light at S on the screen: its bloom, a starburst of eight spikes slowly turning, an anamorphic streak
// and the ghosts of the lens strung out through the middle of the picture. `I` how bright, `sz` its spikes' reach.
fn rd_glare(uv: vec2<f32>, S: vec3<f32>, I: f32, sz: f32, time: f32) -> vec3<f32> {
    if (S.z < 0.0 || I <= 0.0) {
        return vec3<f32>(0.0);
    }
    let asp = frame.resolution.x / frame.resolution.y;
    let q = (uv - S.xy) * vec2<f32>(asp, 1.0);
    let r = length(q);
    let px = 1.0 / frame.resolution.y;
    var star = 0.0;
    let rot = 0.12 * time + 0.3;
    for (var k = 0; k < 4; k = k + 1) {
        let an = rot + f32(k) * 0.7854;
        let dir = vec2<f32>(cos(an), sin(an));
        let along = abs(dot(q, dir));
        let perp = abs(dot(q, vec2<f32>(-dir.y, dir.x)));
        let main = k % 2 == 0;
        let w = select(1.2, 1.8, main) * px + along * 0.004;
        star = star + exp(-perp / w) * exp(-along / (sz * select(0.5, 1.0, main))) * select(0.45, 1.0, main);
    }
    let bloom = 1.0 / (1.0 + pow(r / (0.005 + 0.003 * sqrt(I)), 2.0)) + 0.05 * exp(-r / 0.07);
    let streak = exp(-abs(q.y) / (1.5 * px)) * exp(-abs(q.x) / (0.3 * sz + 0.05)) * 0.35;
    var c = RD_WGOLD * (bloom * 1.4 + star * 1.6) + vec3<f32>(0.8, 0.85, 1.0) * streak;
    // (the ghosts: discs and a ring along the line from the light through the middle of the picture, each its own tint)
    let D = vec2<f32>(0.5) - S.xy;
    let on = (1.0 - smoothstep(0.45, 0.8, length(D)));
    if (on > 0.0) {
        for (var g = 0; g < 3; g = g + 1) {
            let m = array<f32, 4>(0.55, 1.25, 1.6, 2.1)[g];
            let rg = array<f32, 4>(0.025, 0.06, 0.018, 0.09)[g];
            let tint = array<vec3<f32>, 4>(vec3<f32>(1.0, 0.7, 0.35), vec3<f32>(0.4, 0.75, 1.0), vec3<f32>(0.9, 0.5, 1.0), vec3<f32>(0.5, 1.0, 0.7))[g];
            let gq = (uv - (S.xy + D * m)) * vec2<f32>(asp, 1.0);
            let e = length(gq) / rg;
            let disc = 1.0 - smoothstep(0.7, 1.0, e);
            c = c + tint * disc * 0.03 * on;
        }
    }
    return c * I;
}
// What a glowing thing is at temperature T (0 cold to 1 white-hot): dull red through orange and gold to white.
fn rd_heat(T: f32) -> vec3<f32> {
    let a = mix(vec3<f32>(0.7, 0.08, 0.02), vec3<f32>(2.4, 1.15, 0.3), saturate(T * 2.0));
    return mix(a, vec3<f32>(3.4, 3.1, 2.6), saturate(T * 2.0 - 1.0)) * T;
}
// The land rippling out from the strike like a liquid: how far it is lifted at r out, a seconds after, and its slope
// along r.
fn rd_ripple(r: f32, a: f32) -> vec2<f32> {
    let e = RD_RIP_V * a - r;
    if (e < -8.0 || r < 16.0 || a > 5.0) {
        return vec2<f32>(0.0);
    }
    let env = smoothstep(-8.0, 4.0, e) * exp(-max(e, 0.0) / 130.0) * exp(-a / 1.8) * 3.8 * sqrt(60.0 / (r + 60.0)) * smoothstep(16.0, 55.0, r);
    let ph = TAU * e / RD_RIP_L;
    return vec2<f32>(env * sin(ph), -env * cos(ph) * TAU / RD_RIP_L);
}
// The shimmer of hot air over the screen at pixel px: two pixel offsets, about -0.5 to 0.5.
fn rd_haze(px: vec2<f32>, time: f32) -> vec2<f32> {
    return vec2<f32>(gnoise3(vec3<f32>(px / 9.0, time * 2.3)), gnoise3(vec3<f32>(px / 9.0 + 17.0, time * 2.3 + 5.0))) - 0.5;
}
// The jet of molten rock up its path at p (from the target's ground), a seconds after: its density, how hot it is.
fn rd_jet(p: vec3<f32>, a: f32, w: vec3<f32>) -> vec2<f32> {
    let y = p.y;
    if (y < -4.0) {
        return vec2<f32>(0.0);
    }
    // (what is at y now was thrown up at v: from what fell back already (v under g a / 2) to the fastest)
    let v = (max(y, 0.0) + 0.5 * RD_JG * a * a) / a;
    if (v > RD_JV) {
        return vec2<f32>(0.0);
    }
    let fv = v / RD_JV;
    let peak = RD_JV / RD_JG;
    // (narrow, the slow stuff low down spreading most; wider as it comes back down; its top, the fastest of it, spread
    // out and thinned away to nothing, so it frays out into the sky rather than ending at a lid)
    let top = smoothstep(0.62, 1.0, fv);
    let R = 3.0 + a * (1.2 + 5.0 * (1.0 - fv) + 3.6 * top) + 7.0 * max(a - peak, 0.0);
    let rho = length(p.xz);
    let prof = exp(-pow(rho / R, 2.0) * 2.0);
    if (prof < 0.01) {
        return vec2<f32>(0.0);
    }
    // (streaked along it: each parcel keeps its own look as it flies, looked up by its speed)
    let n = gnoise3(vec3<f32>(w.x / (0.45 * R + 1.0), v * 0.16, w.z / (0.45 * R + 1.0)));
    let dens = prof * saturate(n * 1.7 - 0.35) * (0.35 + 0.65 * pow(1.0 - fv, 0.6) + 0.4) / (0.6 + 0.5 * a) * (1.0 - top * top * (3.0 - 2.0 * top)) / (1.0 + 2.0 * top);
    let hot = exp(-a / 1.1) * (0.4 + 0.6 * prof) + 0.25 * exp(-a / 3.0);
    return vec2<f32>(dens, hot);
}

// The pass, in one of three stages: 0 the whole of it at full size (fs_main); 1 the half-size stage (fs_half: the
// plume, the jet, the dust ring and the god rays, over a two by two of the picture's pixels, marched to alternately the
// nearest and the farthest of their depths), returned as premultiplied colour and transmittance; 2 the join (fs_join:
// the rest, sharp, at full size, with the half-size stage's `up` (colour, transmittance) laid over the picture where
// that stage drew them; `up_e`: the plume's distance, and the first and last of the debris that may be near this pixel,
// each one more than its number (0: none)).
fn rod(in: StageIn, stage: u32, up: vec4<f32>, up_e: vec3<f32>) -> PlOut {
    let up_t = up_e.x;
    var uv = in.uv;
    let time = rd_clock();                                    // (held as it strikes: the impact frames' hit-stop)
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let px_a = frame.view_params.w / frame.resolution.y;      // (the angle a pixel spans)
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;              // the strike's point, on the target's ground
    let Cb = C + vec3<f32>(0.0, pl_g0(), 0.0);              // the ground under the burst (the plume's foot)
    let Rax = vec3<f32>(floor(anc.x) + 0.5, gy, floor(anc.y) + 0.5) - cam;   // the rod's axis, on the target's ground
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z) - cam;
    let dme = length((me - C).xz);
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    // (the light: the sun's, warm orange-red as it nears the horizon and fading out as it sets; under the horizon the
    // moon's, faint and cold, from the other side of the sky)
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));

    var d = 0.0;
    if (stage == 1u) {
        // (the two by two of the picture's pixels this one stands for: its middle, and alternately the nearest and the
        // farthest of their depths, so that at an edge both sides are marched and the join finds the one it matches)
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
    var scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    let fade = 1.0 - smoothstep(PL_LEN - PL_FADE, PL_LEN, time);
    let a = time - PL_HIT;                                    // seconds since it struck
    let have = pl_n() > 1;
    // (how far down it has come, 0 to 1, and how bright it shines: a star at first, blazing as it nears; once it is in,
    // calming over a minute but never going out while the strike runs)
    let u = saturate((time - PL_SEEN) / (PL_HIT - PL_SEEN));
    let falling = have && time > PL_SEEN - 0.1 && time < PL_HIT;
    let I_fall = smoothstep(PL_SEEN - 0.1, PL_SEEN + 0.5, time) * (0.6 + 3.4 * pow(u, 4.0));
    let I_post = select(0.0, (0.3 + 0.7 * exp(-a / 10.0)) * fade, a > 0.0);
    let burst = select(0.0, exp(-a / 0.9), a > 0.0);
    let N = Rax + vec3<f32>(0.0, rd_nose_y(time), 0.0);      // its nose
    // (where its light comes from: low on it as it falls; once it stands, its glowing tip)
    let Ssrc = select(Rax + vec3<f32>(0.0, rd_top_end() - 1.0, 0.0), N + vec3<f32>(0.0, 1.0, 0.0), time < PL_HIT);

    // ---- the land heaving: the ripple's rings racing out through it, and the hot air shimmering round the rod and over
    // its crater (the picture drawn from a little way off where it is) ---------------------------------------------------
    var col = scene;
    if (stage != 1u) {
        var wuv = uv;
        var shade = 1.0;
        var lift = 0.0;
        if (!sky && a > 0.0 && a < 5.0) {
            let p = rel - C;
            let r = length(p.xz);
            let rh = rd_ripple(r, a) * k;
            if (abs(rh.x) > 0.02) {
                let pr = project_rel(rel - vec3<f32>(0.0, rh.x, 0.0));
                wuv = wuv + (pr.xy - uv);
                let nr = normalize(vec3<f32>(-rh.y * p.x / max(r, 1.0), 1.0, -rh.y * p.z / max(r, 1.0)));
                // (each ring lit by its slope towards the sun and towards the eye, and dust lifting off its crest)
                let l0 = 0.3 + 0.7 * max(L.y, 0.0);
                shade = (0.3 + 0.7 * max(dot(nr, L), 0.0)) / l0 * (1.0 + 1.2 * (dot(nr, -rd) - max(-rd.y, 0.0)));
                lift = max(rh.x, 0.0) * 0.05;
            }
        }
        var hs = 0.0;
        if (falling) {
            // (round the rod and in its wake over it)
            let sg = pl_ray_seg(rd, N, N + vec3<f32>(0.0, RD_L + 90.0, 0.0), 0.0, 1.0);
            if (sg.y < scene_len) {
                hs = hs + exp(-sg.x / (RD_R + 3.0 + 4.0 * sg.z)) * (0.4 + 0.6 * u) * 4.0 * (1.0 - 0.6 * sg.z);
            }
        }
        if (a > 0.0) {
            // (over the crater, calming but never still)
            let sg = pl_ray_seg(rd, Rax + vec3<f32>(0.0, RD_FLOOR, 0.0), Rax + vec3<f32>(0.0, rd_top_end() + 25.0, 0.0), 0.0, 1.0);
            if (sg.y < scene_len + 2.0) {
                hs = hs + (0.3 + 0.7 * exp(-a / 12.0)) * exp(-pow(sg.x / 20.0, 2.0)) * 3.5 * fade;
            }
        }
        if (hs > 0.02) {
            wuv = wuv + rd_haze(in.position.xy, time) * hs * k * frame.resolution.zw;
        }
        if (any(wuv != uv)) {
            col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, clamp(wuv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
            scene = col;
        }
        col = col * clamp(shade, 0.4, 1.8) + vec3<f32>(0.55, 0.5, 0.42) * lift * (0.3 + 0.7 * day);
    }
    // (the half-size stage's own: what it has gathered, over what lies behind)
    var hc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    // (leaves and grass whipped as the blast's front goes through them: what is green near it shaken on the screen)
    if (stage != 1u && !sky && time > PL_HIT && time < PL_HIT + 6.0) {
        let rfr = PL_V * (time - PL_HIT);
        let rs = length((rel - C).xz);
        let e = rfr - rs;
        let gust = exp(-pow(e / 14.0, 2.0)) + 0.4 * exp(-max(e, 0.0) / 50.0) * step(0.0, e);
        let green = scene.g > scene.r * 1.1 && scene.g > scene.b * 1.05;
        if (gust > 0.03 && green) {
            let fpx0 = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
            let amp = min(0.45 * fpx0 / max(scene_len, 1.0), 7.0) * gust;
            let ph = dot(floor(in.position.xy / 6.0), vec2<f32>(0.37, 0.71));
            let off = vec2<f32>(sin(time * 29.0 + ph * 5.0), cos(time * 23.0 + ph * 3.0)) * amp;
            let s2 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv + off * frame.resolution.zw, 0.0).rgb);
            if (s2.g > s2.r * 1.1 && s2.g > s2.b * 1.05) {
                col = s2;
            }
        }
    }

    // (the light, matched to the scene's: its sky from the top of the picture where it is sky, and the sun's)
    var skyl = srgb_to_linear(frame.sky_color.rgb);
    var nsk = 1.0;
    for (var s = 0; s < 3; s = s + 1) {
        let su = vec2<f32>(0.2 + 0.3 * f32(s), 0.04);
        if (is_sky(depth_at(su))) {
            skyl = skyl + srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, su, 0.0).rgb);
            nsk = nsk + 1.0;
        }
    }
    skyl = skyl / nsk;
    let amb = mix(vec3<f32>(0.03, 0.035, 0.05), skyl * 0.85 + vec3<f32>(0.04), day);
    let sunc = mix(vec3<f32>(1.35, 1.24, 1.06), mix(vec3<f32>(1.5, 0.68, 0.3), vec3<f32>(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun.y)), warm) * sun_up + vec3<f32>(0.07, 0.09, 0.14) * moon;
    let fogl = srgb_to_linear(frame.fog_color.rgb);
    let haze_c = mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day);
    // (its light is stronger against the dark: at night it lights the land and the sky much more, by day the sun
    // washes it)
    let night = 1.0 + 1.2 * (1.0 - day);

    // ---- the shockwave: a shell racing out from the strike at the speed of sound, bending the light where the eye
    // looks along it, a faint golden sheen on it for the first moments ------------------------------------------------
    let Pb = Cb + vec3<f32>(0.0, PL_BURST, 0.0);
    if (stage != 1u && a > 0.0 && a < 5.0) {
        let Rs = PL_V * a;
        let bq = dot(rd, Pb);
        let cq = dot(Pb, Pb) - Rs * Rs;
        let disc = bq * bq - cq;
        if (disc > 0.0) {
            let sq = sqrt(disc);
            var th = bq - sq;
            if (th < 0.0) {
                th = bq + sq;
            }
            let hp = rd * th;
            if (th > 0.0 && th < scene_len + 4.0 && hp.y > Cb.y - 4.0) {
                let edge = exp(-sq / (0.03 * Rs + 5.0));
                let sf = (1.0 - smoothstep(2.0, 5.0, a)) * k;
                let pb = project_rel(Pb);
                var dirs = uv - pb.xy;
                if (pb.z < 0.0) {
                    dirs = -dirs;
                }
                let off = normalize(dirs + vec2<f32>(1.0e-5)) * (0.016 * edge + 0.003 * exp(-sq / (0.25 * Rs))) * sf;
                let sc = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv - off, 0.0).rgb);
                col = mix(col, sc, saturate(edge * 4.0 + 0.5) * sf);
                col = col + RD_WGOLD * (0.3 * edge + 0.04 * exp(-sq / (0.3 * Rs))) * exp(-a / 0.8) * sf * (0.3 + 0.7 * day);
            }
        }
    }

    // ---- the land in its light: lit from above as it comes down, the shafts of its light lying on the ground round
    // the target; the burst lighting everything round it; the molten spatter landing and cooling; the crater's floor
    // white-hot round the rod's foot, cooling over twenty seconds and lighting its walls; the rod's own blocks glowing --
    if (stage != 1u && !sky) {
        if (falling) {
            let v = rel - N;
            let dl = length(v);
            let Il = (0.04 + 1.6 * pow(u, 6.0)) * night;
            col = col + scene * RD_WGOLD * Il * (0.45 + 1.1 * rd_beams(v / max(dl, 1.0), time)) / (1.0 + pow(dl / 90.0, 2.0)) * k;
        }
        if (a > 0.0) {
            let p = rel - Rax;
            let rho = length(p.xz);
            // (the burst's light over the land, a moment)
            let fl = 4.0 * exp(-a / 0.12) + 1.0 * exp(-a / 0.6) + 0.12 * exp(-a / 3.0);
            let dl = length(rel - (Cb + vec3<f32>(0.0, 3.0, 0.0)));
            col = col + scene * mix(RD_GOLD * 2.4, vec3<f32>(3.0, 3.1, 3.4), exp(-a / 0.15)) * fl * 0.8 / (1.0 + pow(dl / 140.0, 2.0)) * k * fade;
            // (the hot floor round its foot)
            let depth = -p.y;
            if (depth > 20.0 && rho < 55.0) {
                let Tc = exp(-a / 8.0);
                let m = smoothstep(30.0, 47.0, depth) * exp(-pow(rho / 16.0, 2.0));
                col = col + rd_heat(Tc * (0.35 + 0.65 * m)) * m * 1.6 * k * fade;
                let lf = length(p - vec3<f32>(0.0, RD_FLOOR, 0.0));
                col = col + scene * vec3<f32>(2.2, 1.3, 0.5) * (Tc * 1.5 + 0.1) / (1.0 + pow(lf / 22.0, 2.0)) * k * fade;
            }
            // (its blocks: a slow tide of light running up it in bands, its tip shining)
            if (rho < RD_R + 0.8 && p.y > rd_top_end() - RD_L && p.y < rd_top_end() + 0.7) {
                let bands = 0.03 + 0.9 * pow(0.5 + 0.5 * sin(p.y * 0.8 - time * 2.6), 16.0);
                let tip = smoothstep(rd_top_end() - 2.0, rd_top_end(), p.y);
                col = col * (1.0 - 0.4 * (1.0 - tip)) + RD_GOLD * (bands + 1.2 * tip) * I_post * night * k;
            }
            // (molten spatter landing round it in the ejecta's rays, glowing and cooling over a few seconds)
            let q = rel - C;
            let r = length(q.xz);
            if (a > 0.8 && a < 30.0 && r > 48.0 && r < 230.0 && abs(q.y) < 45.0) {
                let cs = 2.0;
                let cell = floor(q.xz / cs);
                let hv = hash21(cell + vec2<f32>(f32(seed % 97u), 3.0));
                let dens = 0.2 * exp(-(r - 55.0) / 45.0);
                if (hv < dens) {
                    let ctr = (cell + 0.25 + 0.5 * vec2<f32>(hash21(cell + 3.1), hash21(cell + 7.7))) * cs;
                    let tl = 1.0 + (r - 48.0) / 55.0 + 1.5 * hash21(cell + 1.7);
                    let age = a - tl;
                    if (age > 0.0) {
                        let sz = 0.35 + 0.6 * hash21(cell + 9.1);
                        let spot = 1.0 - smoothstep(sz * 0.35, sz, length(q.xz - ctr));
                        col = col + rd_heat(0.5 * exp(-age / 4.0) + 0.05) * spot * exp(-age / 6.0) * 2.2 * k * fade;
                    }
                }
            }
        }
    }

    // ---- what the half-size stage draws: the plume, the jet, the dust ring, the god rays ------------------------------
    // (the join: the half-size stage's over the picture)
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    }
    // (how far off the plume stands along this ray, where it is mostly opaque: the debris behind it hidden)
    var col_t = select(1.0e9, up_t, stage == 2u);
    if (stage != 2u && have) {
        let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
        // ---- the plume of dust: short and moderate, raymarched, self-shadowed towards the sun, its foot lit gold ----
        if (a > 0.0 && a < 13.0) {
            let C = Cb;
            let heat = exp(-a / 0.25);
            let glow = exp(-a / 0.6);
            var cl = pl_column(a, C);
            let ctop = C + vec3<f32>(0.0, cl.hc, 0.0) + pl_wind() * a;
            let cbound = pl_ray_seg(rd, C - vec3<f32>(0.0, 20.0, 0.0), ctop, 0.0, 1.0);
            let crad = max(max(cl.sr.z, cl.rt), cl.surge.x + cl.surge.y) + PL_DM + 30.0 + 0.2 * length(pl_wind()) * a;
            let tb = pl_box(rd, cl.lo, cl.hi);
            let t1 = min(tb.y, scene_len);
            if (cbound.x < crad && t1 > tb.x) {
                var t = tb.x;
                var tr = 1.0;
                var acc = vec3<f32>(0.0);
                let ph = 0.8 + (0.5 + 1.6 * warm) * pow(saturate(dot(rd, L)), 5.0);
                let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
                let thin = (0.42 - 0.2 * smoothstep(1.0, 6.0, a)) * exp(-max(a - PL_SOFT0, 0.0) / 5.0) * (1.0 - smoothstep(8.5, 13.0, a));
                var tmid = 0.0;
                var wmid = 0.0;
                var nl = 0;
                var lc_face = 0.0;
                var lc_bulk = 1.0;
                var sky_occ = 0.0;
                let sootc = mix(vec3<f32>(0.58, 0.55, 0.5), vec3<f32>(0.7, 0.68, 0.65), smoothstep(3.0, 10.0, a));
                for (var i = 0; i < 52; i = i + 1) {
                    if (t > t1 || tr < 0.04) {
                        break;
                    }
                    let p = rd * t;
                    let d0 = pl_col_base2(&cl, p).x;
                    if (d0 > PL_DM + 14.0) {
                        t = t + (d0 - PL_DM - 4.0) * 0.52;
                        continue;
                    }
                    // (longer steps as it thins: there is less in it to miss)
                    let st = max(6.0 + 4.0 * soft, t * 0.012) * (0.75 + 0.5 * j) * (1.0 + 1.5 * (1.0 - thin / 0.42));
                    var den = 0.0;
                    var sd = vec4<f32>(d0, 0.5, 4.0, 0.5);
                    if (d0 < -PL_DM - 6.0) {
                        sd = vec4<f32>(d0, 0.45, 4.0, 0.5);
                        den = thin;
                    } else if (d0 < PL_DM + 4.0) {
                        // (its fine lumps only while it is crisp: once soft they are lost in the haze)
                        sd = pl_col_sdf(&cl, p, d0, soft < 0.5);
                        let ramp = saturate(-sd.x / (sd.z + 30.0 * soft));
                        den = ramp * mix(saturate(0.15 + 1.7 * sd.w), 1.0, ramp * ramp) * thin;
                    }
                    let sw = (1.0 - smoothstep(15.0, 45.0, p.y - C.y)) * smoothstep(0.8 * cl.sr.x, 1.6 * cl.sr.x, length((p - C).xz));
                    // (thinning towards its top, so it feathers out into the sky)
                    den = den * (1.0 - 0.7 * sw) * (1.0 - 0.65 * smoothstep(cl.hc - 0.5 * cl.rt, cl.hc + 1.2 * cl.rt, p.y - C.y));
                    if (soft > 0.0 && den > 0.002) {
                        let mt = gnoise3((p + cam) * (1.0 / 14.0) - pl_wind() * (a * 0.09) + vec3<f32>(0.0, -0.05 * a, 0.0));
                        den = den * mix(1.0, saturate(0.2 + 1.6 * mt), soft);
                    }
                    if (den > 0.002) {
                        if (nl == 0 || (tr > 0.3 && nl % 3 == 0)) {
                            let fp = p + L * 6.0;
                            lc_face = pl_col_sdf(&cl, fp, pl_col_base2(&cl, fp).x, false).x - sd.x;
                            let s1 = saturate((8.0 - pl_col_base(&cl, p + L * 14.0)) / 26.0);
                            let s2 = saturate((8.0 - pl_col_base(&cl, p + L * 40.0)) / 36.0);
                            lc_bulk = exp(-(s1 * 10.0 + s2 * 18.0) * 0.3);
                            sky_occ = saturate((10.0 - pl_col_base(&cl, p + vec3<f32>(0.0, 50.0, 0.0))) / 50.0);
                        }
                        nl = nl + 1;
                        let lam = mix(saturate(0.25 + lc_face / 6.0), 0.65, soft);
                        let tsun = mix(lc_bulk, 0.7, soft) * lam;
                        let hy = saturate((p.y - C.y) / max(cl.hc + cl.rt, 1.0));
                        let deep = saturate(-d0 / 50.0);
                        let ao = mix((0.55 + 0.45 * sd.y) * (1.0 - 0.6 * deep) * (1.0 - 0.6 * sky_occ), 0.75, soft);
                        let mv = 0.9 + 0.2 * (sd.w - 0.5) + 0.25 * (sd.y - 0.5);
                        var alb = mix(vec3<f32>(0.4, 0.36, 0.31), sootc, smoothstep(0.05, 0.5, hy)) * mv;
                        alb = alb * (1.0 - 0.3 * sw);
                        let skyg = mix(mix(skyl, vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.45), fogl, 0.15) * (1.0 - 0.35 * warm);
                        var c = alb * ((skyg * (0.75 * ao * (0.35 + 0.65 * hy)) + vec3<f32>(0.3, 0.26, 0.2) * day * (1.0 - 0.6 * warm) * ao) + sunc * vec3<f32>(0.95, 0.85, 0.72) * (1.05 * tsun * ph));
                        // (lit from below by the rod's light and the burst: white-gold, then a golden glow that stays
                        // while the rod shines)
                        let low = exp(-max(p.y - C.y, 0.0) / (10.0 + 8.0 * a));
                        let en = (heat * 6.0 + glow * 0.6 + 0.25 * I_post) * low * night * (0.4 + 0.6 * (1.0 - sd.y));
                        let tcol = mix(vec3<f32>(2.4, 1.6, 0.7), vec3<f32>(3.4, 3.2, 3.0), heat);
                        c = c * (1.0 - saturate(en * 0.6)) + tcol * en * 0.5;
                        let al = 1.0 - exp(-den * 0.32 * st);
                        acc = acc + tr * al * c;
                        tmid = tmid + tr * al * t;
                        wmid = wmid + tr * al;
                        tr = tr * (1.0 - al);
                    }
                    t = t + select(st, max(0.55 * sd.x, (0.12 * st + 0.25) * min(1.0 + 0.06 * f32(i), 2.5)), sd.x > 0.0);
                }
                if (tr < 0.999) {
                    let dist = tmid / max(wmid, 1.0e-4);
                    if (tr < 0.5) {
                        col_t = dist;
                    }
                    let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, (1.0 - exp(-dist / 4000.0)) * 0.75);
                    if (stage == 0u) {
                        col = mix(col, ccol, (1.0 - tr) * k * fade);
                    } else {
                        pl_over(&hc, ccol, (1.0 - tr) * k * fade);
                    }
                }
            }
        }
        // ---- the jet: molten rock and debris shot straight up its path, tall and narrow, white-gold cooling to red, then
        // falling back --------------------------------------------------------------------------------------------------
        if (a > 0.0 && a < 2.0 * RD_JV / RD_JG) {
            let H = RD_JV * min(a, RD_JV / RD_JG) - 0.5 * RD_JG * min(a, RD_JV / RD_JG) * min(a, RD_JV / RD_JG) - 0.5 * RD_JG * pow(max(a - RD_JV / RD_JG, 0.0), 2.0);
            let Rb = 3.0 + a * 6.2 + 7.0 * max(a - RD_JV / RD_JG, 0.0) + 4.0;
            // (the ray against the upright cylinder it stands in)
            let o = -Rax.xz;
            let aa = max(dot(rd.xz, rd.xz), 1.0e-8);
            let bb = dot(rd.xz, o);
            let cc = dot(o, o) - Rb * Rb;
            let disc = bb * bb - aa * cc;
            if (disc > 0.0 && H > 0.0) {
                var t0 = (-bb - sqrt(disc)) / aa;
                var t1 = (-bb + sqrt(disc)) / aa;
                let ylo = Rax.y - 4.0;
                let yhi = Rax.y + H + 4.0;
                if (abs(rd.y) > 1.0e-5) {
                    let ya = ylo / rd.y;
                    let yb = yhi / rd.y;
                    t0 = max(t0, min(ya, yb));
                    t1 = min(t1, max(ya, yb));
                }
                t0 = max(t0, 0.0);
                t1 = min(t1, min(scene_len, col_t + 20.0));
                if (t1 > t0) {
                    var tr = 1.0;
                    var acc = vec3<f32>(0.0);
                    let n = 20;
                    let dt = (t1 - t0) / f32(n);
                    for (var i = 0; i < n; i = i + 1) {
                        let p = rd * (t0 + (f32(i) + j) * dt) - Rax;
                        if (p.y > H + 2.0) {
                            continue;
                        }
                        let jd = rd_jet(p, a, p + vec3<f32>(f32(seed % 61u) * 3.0, 0.0, 0.0));
                        if (jd.x <= 0.002) {
                            continue;
                        }
                        let al = 1.0 - exp(-jd.x * dt * 1.3);
                        let lit = sunc * (0.35 + 0.4 * saturate(p.y / 60.0)) + amb * 0.7;
                        let c = vec3<f32>(0.3, 0.27, 0.24) * lit + rd_heat(jd.y) * 1.3;
                        acc = acc + tr * al * c;
                        tr = tr * (1.0 - al);
                        if (tr < 0.03) {
                            break;
                        }
                    }
                    if (stage == 0u) {
                        col = col * (1.0 - (1.0 - tr) * k * fade) + acc * k * fade;
                    } else {
                        let kf = k * fade;
                        hc = vec4<f32>(hc.rgb * (1.0 - kf + kf * tr) + acc * kf, hc.a * (1.0 - kf + kf * tr));
                    }
                }
            }
        }
        // ---- the dust: a ring of it racing out over the ground, low and short-lived --------------------------------
        if (a > 0.0 && a < 22.0) {
            let rf = PL_V * a;
            var ylo = min(C.y, me.y) - 6.0;
            var yhi = max(C.y, me.y) + 60.0;
            if (pl_w(PL_HF) > 1.0) {
                ylo = min(ylo, C.y + pl_w(PL_HF + 2u) - 6.0);
                yhi = max(yhi, C.y + pl_w(PL_HF + 3u) + 60.0);
            }
            var loc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            if (!sky) {
                let sq = rel - C;
                let off = sq.y - pl_land(sq.xz, pl_gref(length(sq.xz), me, C, dme)).x;
                let stp = 2.0 * max(pl_w(PL_HF + 1u), 260.0) / 95.0;
                loc = vec4<f32>(sq.xz, clamp(off, -30.0, 2.5 + 0.1 * max(off - 2.5, 0.0)), stp * stp * 0.6);
            }
            var t0 = 0.0;
            var t1 = min(min(scene_len, col_t), 3200.0);
            if (abs(rd.y) > 1.0e-5) {
                let ya = ylo / rd.y;
                let yb = yhi / rd.y;
                t0 = max(t0, min(ya, yb));
                t1 = min(t1, max(ya, yb));
            } else if (ylo > 0.0 || yhi < 0.0) {
                t1 = -1.0;
            }
            let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
            let bb = -dot(rd.xz, C.xz);
            let cc = dot(C.xz, C.xz);
            let Ro = rf + 20.0;
            let Ri = max(rf - 110.0, 0.0);
            let dout = bb * bb - a2 * (cc - Ro * Ro);
            let din = bb * bb - a2 * (cc - Ri * Ri);
            if (t1 > t0 && dout > 0.0) {
                let oa = (-bb - sqrt(dout)) / a2;
                let ob = (-bb + sqrt(dout)) / a2;
                var seg = array<vec2<f32>, 3>(vec2<f32>(oa, ob), vec2<f32>(0.0, -1.0), vec2<f32>(0.0, -1.0));
                var ns = array<i32, 3>(14, 0, 0);
                if (din > 0.0 && Ri > 0.0) {
                    let ia = (-bb - sqrt(din)) / a2;
                    let ib = (-bb + sqrt(din)) / a2;
                    seg[0] = vec2<f32>(oa, ia);
                    seg[1] = vec2<f32>(ib, ob);
                    seg[2] = vec2<f32>(ia, ib);
                    ns = array<i32, 3>(10, 8, 4);
                }
                let mid_t = clamp(-bb / a2, t0, t1);
                let pm = rd * mid_t - C;
                let side = saturate(abs(dot(normalize(rd.xz), pm.xz / max(length(pm.xz), 1.0))) * 1.6);
                var tr = 1.0;
                var acc = vec3<f32>(0.0);
                let jd = ign(in.position.xy + vec2<f32>(0.0, fract(time * 5.0) * 53.0));
                var order = array<i32, 3>(0, 2, 1);
                for (var si = 0; si < 3; si = si + 1) {
                    let k2 = order[si];
                    let sa = max(seg[k2].x, t0);
                    let sb = min(seg[k2].y, t1);
                    let n = ns[k2];
                    if (n == 0 || sb <= sa || tr < 0.02) {
                        continue;
                    }
                    for (var i = 0; i < n; i = i + 1) {
                        let u0 = (f32(i) + jd) / f32(n);
                        let u1 = (f32(i) + jd + 1.0) / f32(n);
                        let t = sa + (sb - sa) * u0 * u0;
                        let dt = (sb - sa) * (u1 * u1 - u0 * u0);
                        let p = rd * t;
                        let dh = pl_dust(p, C, a, me, dme, side, loc);
                        let den = dh.x * smoothstep(2.0, 30.0, t) * 0.75 * (1.0 - smoothstep(12.0, 22.0, a));
                        if (den <= 0.001) {
                            continue;
                        }
                        let al = 1.0 - exp(-den * dt * 0.3);
                        let h = dh.y;
                        let wq = p + cam;
                        let bl = gnoise3(wq * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a + 0.5, 0.0));
                        let lo = (0.45 + 0.55 * saturate(h / 8.0)) * (0.55 + 0.7 * bl);
                        let dc = vec3<f32>(0.58, 0.53, 0.44) * (sunc * 0.75 * lo + amb * 0.6);
                        acc = acc + tr * al * dc;
                        tr = tr * (1.0 - al);
                        if (tr < 0.02) {
                            break;
                        }
                    }
                }
                if (stage == 0u) {
                    col = mix(col, col * tr + acc, k * fade);
                } else {
                    let kf = k * fade;
                    hc = vec4<f32>(hc.rgb * (1.0 - kf + kf * tr) + acc * kf, hc.a * (1.0 - kf + kf * tr));
                }
            }
        }
        // ---- the god rays: shafts of its light streaming out of it as it comes, broken by whatever stands between;
        // fanning out of the strike as it hits; rising softly out of the crater from the rod while it stands ----------
        var gr = vec3<f32>(0.0);
        let Iray = select(0.0, I_fall * 0.07, falling) + select(0.0, 0.8 * burst + 0.12 * I_post, a > 0.0);
        if (Iray > 0.004) {
            let Sp = project_rel(Ssrc);
            gr = gr + RD_WGOLD * rd_srays(uv, Sp, rd_depth_of(Ssrc), time, j) * Iray * night;
        }
        gr = gr * k * fade * (1.0 - 0.5 * day * (1.0 - u) * select(1.0, 0.0, a > 0.0));
        if (stage == 0u) {
            col = col + gr;
        } else {
            hc = vec4<f32>(hc.rgb + gr, hc.a);
        }
    }

    // ---- the column of light down its path, from the sky to the target, and the ionised line it lays in it: bright and
    // white-gold just behind it, then each bit of it, as it ages, widening and dimming, its glow fading over seconds and
    // the last of it over half a minute: the oldest, at the top, first. Nothing in it steps or jumps: all of it goes by
    // how long since the rod passed there, on and on through the strike, and the soft pillar round it calms into a quiet
    // column over the crater ---------------------------------------------------------------------------------------------
    if (stage != 1u && have) {
        let appear = smoothstep(PL_SEEN - 0.6, PL_SEEN + 0.6, time);
        let sg = pl_ray_seg(rd, Rax, Rax + vec3<f32>(0.0, 7000.0, 0.0), 0.0, 1.0);
        if (appear > 0.0 && sg.y < scene_len + 2.0 && sg.x < 120.0 + sg.y * px_a * 4.0) {
            let y = 7000.0 * sg.z;
            let sn = max(length(cross(rd, vec3<f32>(0.0, 1.0, 0.0))), 0.15);
            // (its nose, down at the ground from the moment it strikes; what is above it was laid as it passed)
            let ny = rd_nose_y(min(time, PL_HIT));
            let above = smoothstep(ny - 2.0, ny + 6.0, y);
            let age = max(time - rd_time_at(y), 0.0);
            let glowL = 1.4 * exp(-age / 0.7) + 0.5 * exp(-age / 5.0) + 0.12 * exp(-age / 20.0);
            // (widening as it ages, its light spread over the width: dimmer as it widens)
            let wl0 = 0.45 + 0.12 * age;
            let wl = max(wl0, sg.y * px_a * 0.7);
            let core = exp(-pow(sg.x / wl, 2.0)) * (0.45 / wl) * glowL * above;
            // (the path below it, faint, brightening as it nears)
            let path = (1.0 - above) * 0.06 * u * exp(-pow(sg.x / max(0.6, sg.y * px_a * 0.7), 2.0)) * min(0.6 / max(0.6, sg.y * px_a * 0.7), 1.0);
            // (the soft pillar round it: widening a little up into the sky and with the trail's age, thinning out high
            // up; as bright where it lies ahead of the rod as behind it by the time it strikes)
            let Rc = 7.0 + 0.004 * y + 1.6 * sqrt(age) * above;
            let lvl = select(0.25 + 0.75 * u * u, 0.55 * burst + 0.45 * I_post, a > 0.0);
            let soft = exp(-pow(sg.x / Rc, 2.0)) * 0.35 * sqrt(7.0 * Rc) / sn / (1.0 + y / 2500.0) * lvl * (above + (1.0 - above) * (0.5 + 0.5 * u));
            // (not over the rod where it stands: the column rises from its top)
            let inrod = select(0.0, (1.0 - smoothstep(RD_R, RD_R + 2.0, sg.x)) * (1.0 - smoothstep(rd_top_end(), rd_top_end() + 1.5, y)), a > 0.0);
            col = col + (RD_WGOLD * 2.2 * (core + path) + RD_GOLD * soft * 0.1) * k * fade * night * appear * (1.0 - inrod);
        }
    }

    // ---- its glow and its glare: a halo round it, the bow of white-gold air round its nose, and the starburst, the
    // streak and the ghosts of the lens; once it stands, softer, from its tip ------------------------------------------
    if (stage != 1u && have && time > PL_SEEN - 0.1) {
        var Ih = 0.0;
        var segA = N;
        var segB = N + vec3<f32>(0.0, RD_L, 0.0);
        if (falling) {
            Ih = I_fall;
        } else if (a > 0.0) {
            Ih = I_post;
            segA = Rax + vec3<f32>(0.0, rd_top_end() - RD_L * 0.5, 0.0);
            segB = Rax + vec3<f32>(0.0, rd_top_end() + 1.0, 0.0);
        }
        let sg = pl_ray_seg(rd, segA, segB, 0.0, 1.0);
        if (Ih > 0.0 && sg.y < scene_len + 1.0) {
            // (round it, not over it: from its surface out)
            let w = max(RD_R * 1.2, sg.y * px_a * 2.0);
            let e = max(sg.x - 0.9 * RD_R, 0.0);
            let halo = (exp(-e / w) * 0.5 + 0.12 / (1.0 + pow(e / (5.0 * w), 2.0))) * Ih * smoothstep(0.6 * RD_R, RD_R, sg.x);
            col = col + RD_WGOLD * halo * (1.0 - 0.6 * sg.z * select(1.0, 0.0, falling)) * k * night;
        }
        // (the bow of glowing air round its nose, opening back up it, in its last second the shock cone too)
        if (falling) {
            let sgb = pl_ray_seg(rd, N, N + vec3<f32>(0.0, 160.0, 0.0), 0.0, 1.0);
            if (sgb.y < scene_len) {
                let s = sgb.z * 160.0;
                let rc = RD_R + 1.0 + 0.21 * s;
                let w = max(0.8 + 0.03 * s, sgb.y * px_a * 1.5);
                let e = exp(-pow((sgb.x - rc) / w, 2.0)) * exp(-s / (12.0 + 60.0 * smoothstep(PL_HIT - 1.0, PL_HIT, time))) * min((0.8 + 0.03 * s) / w, 1.0);
                col = col + RD_WGOLD * e * (0.2 + 0.5 * smoothstep(PL_HIT - 1.0, PL_HIT, time)) * I_fall * 0.25 * k;
            }
        }
        // (the glare, where its light is in sight)
        // (as it comes near, its shape is what the eye is on: the glare let down as it grows on the screen)
        let big = RD_L / max(length(N), 1.0) / px_a;
        let Ig = select(0.0, I_fall * 0.9 / (1.0 + pow(big / 60.0, 2.0)), falling) + select(0.0, 6.0 * burst * burst + 0.25 * I_post, a > 0.0);
        if (Ig > 0.003) {
            let Sw = select(Ssrc, Cb + vec3<f32>(0.0, 3.0, 0.0), a > 0.0 && burst > 0.4);
            let sv = rd_seen(Sw);
            if (sv > 0.0) {
                let sz = select(0.13, 0.1, a > 0.0) * (0.6 + 0.4 * sqrt(min(Ig, 4.0)));
                col = col + rd_glare(uv, project_rel(Sw), Ig * sv, sz, time) * k * fade * mix(0.7, 1.0, night - 1.0);
            }
        }
    }

    // ---- the rod: dark metal, nose down, its nose blazing white-gold and the light running up it, a golden rim of light
    // round it, a glint where the sun catches it; driven into the land as it strikes -----------------------------------
    // (once it stands, its blocks are in the world: drawn till they are surely in (the crater dug out round it by some
    // 0.7 s, then lined from the rod out, the rod's own blocks first, in by some 1.0 s: rod.rs's Wave), then let go
    // over a second)
    if (stage != 1u && have && time > PL_SEEN - 0.1 && a < RD_LET_GO + 1.0) {
        let h = rd_rod_hit(rd, N, px_a, scene_len + 1.0);
        if (h.cov > 0.0) {
            let n = rd_rod_normal(h.q);
            let v = -rd;
            let ndv = saturate(dot(n, v));
            let fres = 0.05 + 0.95 * pow(1.0 - ndv, 5.0);
            let rf = reflect(rd, n);
            let env = mix(vec3<f32>(0.08, 0.09, 0.07) * (0.3 + 0.7 * day), skyl * 1.15, smoothstep(-0.25, 0.35, rf.y));
            let spec = pow(saturate(dot(rf, L)), 90.0) * 18.0 * sunc;
            let bk = rd_band(h.q.y);
            let band = select(0.0, 1.0, bk == 1);
            let carved = select(0.0, 1.0, bk == 2);
            // (forged dark metal, a faint grain of hammered plates on it; gold bands; carved bands a little lighter)
            let grain = 0.85 + 0.3 * vnoise(vec2<f32>(atan2(h.q.z, h.q.x) * 6.0, h.q.y * 0.5));
            let base = mix(mix(vec3<f32>(0.075, 0.07, 0.08) * grain, vec3<f32>(0.16, 0.15, 0.16), carved), vec3<f32>(0.75, 0.55, 0.22), band);
            var c = base * (amb * 0.6 + sunc * max(dot(n, L), 0.0) * 0.7) + mix(vec3<f32>(0.45, 0.45, 0.48), vec3<f32>(1.0, 0.8, 0.4), band) * (env * (0.25 + 0.75 * fres) + spec);
            // (its light: the nose white-gold, running up it, a rim of gold round its outline)
            let glow = select(I_fall, 3.0 * burst + I_post, a > 0.0);
            // (its nose white-hot, the heat running a little way up it, gold to dull red)
            let nose = exp(-h.q.y / 4.0) * 2.0 + exp(-h.q.y / 18.0) * 0.18;
            c = c + mix(vec3<f32>(1.2, 0.45, 0.12), vec3<f32>(1.3, 1.25, 1.15), saturate(exp(-h.q.y / 5.0))) * nose * min(glow, 2.0);
            c = c + RD_GOLD * pow(1.0 - ndv, 2.5) * 0.5 * min(glow, 2.0);
            c = mix(c, haze_c, (1.0 - exp(-h.t / 4000.0)) * 0.6);
            col = mix(col, c, h.cov * k * (1.0 - smoothstep(RD_LET_GO, RD_LET_GO + 1.0, a)));
        }
    }
    // ---- the flash: blinding, white-blue going gold, the radiance seen through anything for a moment ----------------
    if (stage != 1u && a > 0.0) {
        let Pf = Cb + vec3<f32>(0.0, 3.0, 0.0);
        let df = length(Pf);
        let cth = dot(rd, Pf / df);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let fl = (7.0 * exp(-a / 0.08) + 1.2 * exp(-a / 0.5) + 0.06 * exp(-a / 3.0)) * fade;
        let fc = mix(RD_GOLD * 2.6, vec3<f32>(3.0, 3.15, 3.5), exp(-a / 0.2));
        let tp = max(4.0 / df, px_a * 1.2);
        col = col + fc * fl * (0.6 * exp(-pow(th / tp, 2.0)) + 0.05 / (1.0 + pow(th / 0.04, 2.0)) + 0.012 * exp(-th / 0.5)) * k;
        col = col + RD_WGOLD * 0.5 * exp(-a / 0.2) * k * fade;
    }

    // ---- the debris: chunks of rock thrown up out of the crater, many of them molten, glowing and cooling as they
    // fly; the big ones trailing smoke ----------------------------------------------------------------------------------
    if (stage == 1u) {
        var near = 0.0;
        var near_hi = 0.0;
        if (a > 0.0 && a < 28.0 && pl_w(8u) > 0.5) {
            var low = min(C.y, me.y) - 4.0;
            if (pl_w(PL_HF) > 1.0) {
                low = min(low, C.y + pl_w(PL_HF + 2u) - 4.0);
            }
            let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
            let wpx = 1.0 / fpx;
            let eka = exp(-0.06 * a);
            let pxy = (floor(in.position.xy) * 2.0 + 1.0);
            for (var i = 0; i < PL_DEBRIS; i = i + 1) {
                let ch = pl_chunk(i, a, eka, C);
                if (ch.live <= 0.0 || ch.p.y < low) {
                    continue;
                }
                let dist = length(ch.p);
                let off = length(ch.p - rd * dot(ch.p, rd));
                if (dist < 1.0 || off > ch.s * 4.5 + length(ch.v) * 0.8 + 1.5 + 9.0 * dist * wpx) {
                    continue;
                }
                let s0 = project_rel(ch.p);
                if (s0.z < 0.0) {
                    continue;
                }
                let rad = max(ch.s * fpx / dist, 0.55);
                let reach = select(rad * 1.4 + length(ch.v) * 0.03 * fpx / dist + 2.0, rad * 3.0 + length(ch.v) * 0.6 * fpx / dist + 4.0, smoothstep(0.45, 0.8, ch.s) > 0.0);
                if (length(pxy - s0.xy * frame.resolution.xy) > reach + 3.0) {
                    continue;
                }
                if (pl_chunk_up(ch, C, me, dme) > 0.0) {
                    near = select(near, f32(i + 1), near == 0.0);
                    near_hi = f32(i + 1);
                }
            }
        }
        return PlOut(hc, vec4<f32>(min(scene_len, 6.0e4), min(col_t, 6.0e4), near, near_hi));
    }
    if ((stage == 0u || up_e.y > 0.0) && a > 0.0 && a < 28.0 && pl_w(8u) > 0.5) {
        let i_lo = select(0, i32(up_e.y + 0.5) - 1, stage == 2u);
        let i_hi = select(PL_DEBRIS, i32(up_e.z + 0.5), stage == 2u);
        let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
        let pxy = in.position.xy;
        let lim = min(scene_len, col_t);
        var cov = 0.0;
        var smk = 0.0;
        var hot = vec3<f32>(0.0);
        var low = min(C.y, me.y) - 4.0;
        if (pl_w(PL_HF) > 1.0) {
            low = min(low, C.y + pl_w(PL_HF + 2u) - 4.0);
        }
        let wpx = 1.0 / fpx;
        let eka = exp(-0.06 * a);
        for (var i = i_lo; i < i_hi; i = i + 1) {
            var ch = pl_chunk(i, a, eka, C);
            if (ch.live <= 0.0 || ch.p.y < low) {
                continue;
            }
            let dist = length(ch.p);
            if (dist > lim || dist < 1.0) {
                continue;
            }
            let off = length(ch.p - rd * dot(ch.p, rd));
            let reach_w = ch.s * 4.5 + length(ch.v) * 0.8 + 1.5 + 6.0 * dist * wpx;
            if (off > reach_w) {
                continue;
            }
            ch.live = pl_chunk_up(ch, C, me, dme);
            if (ch.live <= 0.0) {
                continue;
            }
            let s0 = project_rel(ch.p);
            if (s0.z < 0.0) {
                continue;
            }
            let q0 = s0.xy * frame.resolution.xy;
            let rad = max(ch.s * fpx / dist, 0.55);
            let bigc = smoothstep(0.45, 0.8, ch.s);
            let reach = select(rad * 1.4 + length(ch.v) * 0.03 * fpx / dist + 2.0, rad * 3.0 + length(ch.v) * 0.6 * fpx / dist + 4.0, bigc > 0.0);
            if (length(pxy - q0) > reach) {
                continue;
            }
            let s1 = project_rel(ch.p - ch.v * 0.03);
            let q1 = s1.xy * frame.resolution.xy;
            let ab = q1 - q0;
            let w = saturate(dot(pxy - q0, ab) / max(dot(ab, ab), 1.0e-4));
            let e = length(pxy - (q0 + ab * w));
            let spin = a * pl_w(PL_DB + PL_DW * u32(i) + 8u);
            let th = atan2(pxy.y - q0.y, pxy.x - q0.x);
            let lump = 1.0 + 0.28 * sin(th * 3.0 + f32(i) + spin) + 0.12 * sin(th * 5.0 - spin * 1.3);
            let c = saturate(rad * lump + 0.5 - e) * ch.live * saturate(rad / max(length(ab) * 0.5, rad));
            // (two in five of them molten: glowing, cooling as they fly, a streak of light behind them)
            if (mh(u32(i), seed, 0x5a1u) < 0.4) {
                let T = 0.62 * exp(-a / (2.5 + 3.0 * mh(u32(i), seed, 0x5a2u)));
                hot = max(hot, rd_heat(T) * 1.6 * c);
            } else {
                cov = max(cov, c);
            }
            if (bigc > 0.0) {
                let s2 = project_rel(ch.p - ch.v * 0.6 + vec3<f32>(0.0, 1.2, 0.0));
                let q2 = s2.xy * frame.resolution.xy;
                let tb = q2 - q0;
                let uu = saturate(dot(pxy - q0, tb) / max(dot(tb, tb), 1.0e-4));
                let wd = rad * (0.6 + 1.6 * uu) + 0.5;
                let et = length(pxy - (q0 + tb * uu));
                smk = max(smk, saturate(1.0 - et / wd) * (1.0 - uu) * 0.35 * bigc * ch.live * step(0.5, s2.z));
            }
        }
        let dirt = vec3<f32>(0.06, 0.055, 0.05) * (amb * 1.5 + sunc * 0.35);
        let smoke = vec3<f32>(0.28, 0.29, 0.31) * (amb * 0.8 + sunc * 0.25);
        col = mix(col, smoke, smk * k * fade);
        col = mix(col, dirt, cov * k * fade);
        col = col + hot * k * fade;
    }

    // ---- the dust at the eye: as the front washes over the camera, the picture greyed and flattened by the dust in the
    // air, clearing as it settles, and muck thrown on the lens -------------------------------------------------------
    if (a > 0.0 && a < 40.0) {
        let rc = length(C.xz);
        let tau = a - rc / PL_V;                               // since the front reached the eye
        if (tau > -0.1 && rc > 100.0) {
            let land = pl_land(-C.xz, pl_gref(rc, me, C, dme));
            let hc = -C.y - land.x;                            // the eye over the ground
            let E = smoothstep(-0.08, 0.05, tau) * (0.6 * exp(-tau / 0.8) + 0.4 * exp(-tau / 3.5))
                * smoothstep(60.0, 10.0, hc) * smoothstep(6000.0, 2500.0, rc) * smoothstep(100.0, 200.0, rc)
                * (1.0 - 0.55 * land.y) * fade * k * 0.7;
            if (E > 0.002) {
                let dust_c = vec3<f32>(0.5, 0.46, 0.4) * (sunc * 0.55 + amb * 0.8);
                let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
                col = mix(col, mix(vec3<f32>(lum), dust_c, 0.5), 0.22 * E);
                col = col * mix(vec3<f32>(1.0), vec3<f32>(1.03, 0.99, 0.93), E);
                let pxy = pl_px;
                let res = frame.resolution.xy;
                let film = gnoise3(vec3<f32>(pxy / (0.15 * res.y), 3.1)) * 0.8 + gnoise3(vec3<f32>(pxy / (0.07 * res.y), 7.7)) * 0.2;
                col = mix(col, dust_c, 0.12 * E * smoothstep(0.35, 0.95, film));
            }
            // (muck thrown on the lens as the front passes, far out of focus: soft grey drops high on the screen)
            let vis = smoothstep(60.0, 10.0, hc) * smoothstep(6000.0, 2500.0, rc) * smoothstep(120.0, 260.0, rc) * (1.0 - 0.5 * land.y) * k * 0.7;
            if (vis > 0.0 && tau > 0.2) {
                let pxy = pl_px;
                let res = frame.resolution.xy;
                var keep = 1.0;
                var shine = 0.0;
                for (var i = 0u; i < 14u; i = i + 1u) {
                    let t0 = 0.25 + 1.4 * mh(i, seed, 0x3d0u);
                    let age = tau - t0;
                    if (age <= 0.0) {
                        continue;
                    }
                    let c = vec2<f32>(0.03 + 0.94 * mh(i, seed, 0x3d1u), 0.02 + 0.4 * pow(mh(i, seed, 0x3d2u), 1.3)) * res;
                    let sz = mh(i, seed, 0x3d3u);
                    let r = (0.011 + 0.026 * pow(sz, 0.8)) * res.y;
                    let d0 = pxy - c;
                    if (dot(d0, d0) > 16.0 * r * r) {
                        continue;
                    }
                    let life = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(6.0, 16.0, age + 4.0 * mh(i, seed, 0x3d4u)));
                    for (var j = 0u; j < 4u; j = j + 1u) {
                        let hj = mh(i * 7u + j, seed, 0x3e0u);
                        if (j > 0u && hj > 0.3) {
                            continue;
                        }
                        let k2 = i * 7u + j;
                        let rj = select(r * (0.22 + 0.3 * mh(k2, seed, 0x3e1u)), r, j == 0u);
                        let ang = TAU * mh(k2, seed, 0x3e2u);
                        let cj = select(c + vec2<f32>(cos(ang), sin(ang)) * r * (1.4 + 0.9 * mh(k2, seed, 0x3e3u)), c, j == 0u);
                        let dj = pxy - cj;
                        let rot = TAU * mh(k2, seed, 0x3e4u);
                        let cr = cos(rot);
                        let sr = sin(rot);
                        let stretch = 1.0 + mix(0.4, 0.06, smoothstep(0.012, 0.03, rj / res.y)) * 2.0 * mh(k2, seed, 0x3e5u);
                        let e = vec2<f32>((dj.x * cr + dj.y * sr) / stretch, -dj.x * sr + dj.y * cr);
                        let th = atan2(e.y, e.x);
                        let ph = TAU * mh(k2, seed, 0x3e6u);
                        let q = length(e) / rj * (1.0 + 0.05 * sin(3.0 * th + ph) + 0.035 * sin(5.0 * th - 2.0 * ph));
                        if (q >= 1.4) {
                            continue;
                        }
                        let body = 1.0 - smoothstep(0.3, 1.38, q);
                        let ring = body * mix(0.9, 1.15, smoothstep(0.1, 0.8, q));
                        let mott = 0.94 + 0.12 * gnoise3(vec3<f32>(e / (0.8 * rj), f32(k2 % 97u)));
                        let op = (0.14 + 0.34 * pow(mh(k2, seed, 0x3e7u), 0.7)) * select(0.85, 1.0, j == 0u);
                        keep = keep * (1.0 - ring * mott * op * life);
                        shine = shine + body * smoothstep(0.3, -0.9, dj.y / rj) * op * life;
                    }
                }
                let muck = vec3<f32>(0.42, 0.38, 0.33) * (sunc * 0.45 + amb * 0.9);
                col = mix(col, col * keep + muck * (1.0 - keep) * 0.7, vis * fade) + muck * 0.4 * min(shine, 1.0) * vis * fade;
            }
        }
    }

    // ---- the impact frames: as it strikes the action held for a fifth of a second (rd_clock), stark compositions cut
    // hard against each other over it, then the release smeared out from the point and a long glow (rd_impact;
    // `/orbital impactframes off` leaves them out)
    let a_if = now() - PL_HIT;
    if (stage != 1u && rd_if_on() && a_if > -0.035 && a_if < RD_IF_END) {
        col = rd_impact(col, uv, a_if, Cb, seed);
    }
    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    if (capture() > 2.5) {
        let sp = floor(pl_px);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return PlOut(vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0), vec4<f32>(0.0));
    }
    return PlOut(vec4<f32>(srgb, 1.0), vec4<f32>(0.0));
}


// ---- the impact frames ----------------------------------------------------------------------------------------------
// As it strikes the action holds: a hit-stop, the pass's own clock (rd_clock) stopped on the moment of contact for a
// fifth of a second or so, then let go a little way into the burst and catching up over a third of a second.
// Over the hold, a few stark compositions cut hard against each other, two or three frames each at 60 a second, the
// camera kicked on every cut (pl_jolt: a tight punch-in on the point, then a shake a frame); then the release, the
// picture smeared out from the point and split in colour for a moment, and a long glow fading. Timed by the strike's
// clock. Three looks (RD_IF_STYLE; tools/preview.py's `--set rdif=N` builds the pass with another):
//   0, the black flash: red and black, black lightning cracking out of the point in a crimson glow: the scene a pale
//      negative, a tight red-on-black close-up, the negative cracked anew, the held picture drained, a last red hit;
//   1, Kanada: black silhouettes and thick, wobbling black lines converging on the point on white; a tight close-up
//      in negative, its lines gold; a gold and umber frame; the first again, shaken; gold and umber again, closer;
//   2, cinematic: a white-out with the rod burned black into it; the frozen picture bleached while a shockwave ring,
//      split in colour, tears out across the frame from the point and the camera pushes in; the release smeared.
// Photosensitivity: at most two dark dips and the white-outs in it, no more than three large swings of brightness in
// any second, its red kept to lines on black.
const RD_IF_STYLE: i32 = 1;
const RD_IF_CATCH: f32 = 0.35;     // the clock catching up after the hold, over this long,
const RD_IF_JUMP: f32 = 0.08;      // from this far into the burst (its first white-out cut: the release is the frames')
const RD_IF_END: f32 = 1.6;        // the frames and the glow after them done this long after it strikes
const RD_IF_ROD: vec3<f32> = vec3<f32>(0.05, 0.045, 0.05);
fn rd_if_on() -> bool {
    return ((u32(frame.mod_params[3].w + 0.5) >> 1u) & 1u) == 0u;
}
// The look picked in the game (params[15] / 4: 1 + RD_IF_STYLE's numbering; 0, none sent, RD_IF_STYLE's own).
fn rd_if_style() -> i32 {
    let s = i32((u32(frame.mod_params[3].w + 0.5) >> 2u) & 3u);
    return select(s - 1, RD_IF_STYLE, s == 0);
}
// How long the action holds: thirteen frames at 60 a second, twelve, fourteen (each cut ends half a frame early, so
// that a frame drawn on the beat falls in the cut that starts there).
fn rd_if_hold() -> f32 {
    return (select(select(14.0, 12.0, rd_if_style() == 1), 13.0, rd_if_style() == 0) - 0.5) / 60.0;
}
// The pass's clock: now(), but held on the moment of contact through the impact frames, then catching up.
fn rd_clock() -> f32 {
    let t = now();
    let a = t - PL_HIT;
    if (!rd_if_on() || a <= 0.0) {
        return t;
    }
    let F = rd_if_hold();
    if (a < F) {
        return PL_HIT - 0.0005;
    }
    if (a < F + RD_IF_CATCH) {
        return PL_HIT + RD_IF_JUMP + (a - F) * (F + RD_IF_CATCH - RD_IF_JUMP) / RD_IF_CATCH;
    }
    return t;
}
// The cut at `a` (seconds since it struck): its composition (-1: the release), the punch-in (how far the picture is
// zoomed on the point), the shake (screen heights, a new way each frame) and which set of lines and bolts.
fn rd_if_cut(a: f32) -> vec4<f32> {
    let F = rd_if_hold();
    if (a >= F) {
        // (snapping back out, still shaking, dying fast)
        let s = a - F;
        return vec4<f32>(-1.0, 1.0 + 0.12 * exp(-s / 0.05), 0.014 * exp(-s / 0.09), 9.0);
    }
    let f = a * 60.0 + 0.5;                                    // (frames since it struck, to the nearest)
    if (rd_if_style() == 0) {
        if (f < 3.0) { return vec4<f32>(0.0, 1.0, 0.012, 1.0); }
        if (f < 6.0) { return vec4<f32>(1.0, 3.0, 0.004, 2.0); }
        if (f < 8.0) { return vec4<f32>(0.0, 1.35, 0.016, 3.0); }
        if (f < 11.0) { return vec4<f32>(2.0, 1.12, 0.007, 3.0); }
        return vec4<f32>(1.0, 1.9, 0.01, 4.0);
    }
    if (rd_if_style() == 1) {
        if (f < 2.0) { return vec4<f32>(0.0, 1.06, 0.01, 1.0); }
        if (f < 5.0) { return vec4<f32>(1.0, 3.0, 0.004, 2.0); }
        if (f < 7.0) { return vec4<f32>(2.0, 1.6, 0.012, 3.0); }
        if (f < 10.0) { return vec4<f32>(0.0, 1.25, 0.02, 4.0); }
        return vec4<f32>(2.0, 1.9, 0.01, 5.0);
    }
    if (f < 3.0) { return vec4<f32>(0.0, 1.03, 0.006, 1.0); }
    return vec4<f32>(1.0, 1.04 + 0.1 * (a - 0.05) / (F - 0.05), 0.0015, 2.0);
}
// The impact point on the screen (uv).
fn rd_if_point(Cb: vec3<f32>) -> vec2<f32> {
    let p = project_rel(Cb + vec3<f32>(0.0, 2.0, 0.0));
    // (behind the eye: from below the middle of the screen, as a burst from off it)
    return select(vec2<f32>(0.5, 1.2), p.xy, p.z > 0.0);
}
// What the scene is at uv to the silhouette: bright or far 1, near and dark 0.
fn rd_if_tone(uv: vec2<f32>) -> f32 {
    let d = depth_at(uv);
    if (is_sky(d)) {
        return 1.0;
    }
    let len = length(world_offset(uv, d));
    let c = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    let lum = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return 0.55 * lum / (lum + 0.12) + 0.75 * smoothstep(250.0, 1400.0, len);
}
// The scene's silhouette: 1 the sky and what is bright, 0 the land and what stands on it close by (four looks a couple
// of pixels apart: the leaves' speckle smoothed into clean shapes).
fn rd_if_mask(uv: vec2<f32>) -> f32 {
    let o = 2.0 * frame.resolution.zw;
    let v = 0.25 * (rd_if_tone(uv + vec2<f32>(o.x, o.y)) + rd_if_tone(uv + vec2<f32>(-o.x, o.y)) + rd_if_tone(uv + vec2<f32>(o.x, -o.y)) + rd_if_tone(uv - o));
    return smoothstep(0.5, 0.6, v);
}
// The burst at the point: a small core flattened along the ground, its edge broken finely (qj: off the point in the
// picture's own screen heights, zoomed with it).
fn rd_if_core(qj: vec2<f32>, size: f32) -> f32 {
    let th = atan2(qj.y, qj.x);
    let c = size * (1.0 + 0.18 * sin(th * 23.0 + 1.3) * sin(th * 37.0 + 0.4));
    return 1.0 - smoothstep(c * 0.7, c, length(qj * vec2<f32>(0.55, 1.6)));
}
// A smooth glow round the point, flattened along the ground as the core is.
fn rd_if_halo(qj: vec2<f32>, size: f32) -> f32 {
    let d = length(qj * vec2<f32>(0.55, 1.6));
    return exp(-pow(d / size, 2.0) * 1.5);
}
// Thick impact lines converging on the point (q: off it in screen heights): `n` wedges round it, a third of them left
// out, each its own weight, thick at the screen's edge and tapering to a point well short of the middle, the whole set
// bent back and forth along its length (wobbling: anew each set `b`). 1 on a line.
fn rd_if_focus(q: vec2<f32>, b: u32, seed: u32, n: f32, wmax: f32) -> f32 {
    let r = max(length(q), 1.0e-4);
    let th = atan2(q.y, q.x) / TAU + 0.5;
    let fb = f32(b);
    let wob = (0.08 * sin(r * 6.0 + fb * 2.3 + th * 9.0) + 0.035 * sin(r * 17.0 - fb * 4.1)) * smoothstep(0.0, 0.25, r);
    let u = th * n + wob;
    let id = floor(u);
    let k = u32(i32(id) + 1000) + 977u * b;
    let h1 = mh(k, seed, 0x4c2u);
    let h2 = mh(k, seed, 0x4c3u);
    let h3 = mh(k, seed, 0x4c4u);
    if (h2 < 0.3) {
        return 0.0;
    }
    let r0 = 0.1 + 0.3 * h3 * h3;
    let w = wmax * (0.3 + 0.7 * h1) * smoothstep(r0, r0 + 0.45 + 0.4 * h1, r);
    let f = abs(fract(u) - 0.5);
    let px = (1.0 / frame.resolution.y) / r * n / TAU;
    return (1.0 - smoothstep(w * 0.5 - px, w * 0.5 + px, f)) * step(r0, r);
}
// Piecewise-linear noise, -1 to 1: lightning's sharp kinks.
fn rd_if_pln(x: f32, seed: u32, k: u32) -> f32 {
    let i = floor(x);
    let h0 = mh(u32(i32(i) + 65536), seed, k);
    let h1 = mh(u32(i32(i) + 65537), seed, k);
    return mix(h0, h1, x - i) * 2.0 - 1.0;
}
// A bolt's path: how far it has wandered off its line `s` along it.
fn rd_if_bpath(s: f32, seed: u32, k: u32) -> f32 {
    return (0.075 * rd_if_pln(s * 9.0, seed, k) + 0.028 * rd_if_pln(s * 27.0, seed, k + 1u)) * smoothstep(0.0, 0.08, s);
}
// One bolt from `o` at angle `ang`, `len` long, `w0` wide at its root: (how far across from its path, its half width
// there, how far along it it is, 0 to 1); far off if out of its length.
fn rd_if_bolt1(q: vec2<f32>, o: vec2<f32>, ang: f32, len: f32, w0: f32, seed: u32, k: u32) -> vec3<f32> {
    let d = vec2<f32>(cos(ang), sin(ang));
    let p = q - o;
    let s = dot(p, d);
    if (s < -0.01 || s > len) {
        return vec3<f32>(1.0e3, 0.0, 1.0);
    }
    let t = d.x * p.y - d.y * p.x;
    let along = saturate(s / len);
    return vec3<f32>(abs(t - rd_if_bpath(s, seed, k)), w0 * pow(1.0 - along, 0.7), along);
}
// The black flash's lightning round the point (q in screen heights): eight bolts cracking out of it, each with a branch,
// a new set each `b`. x: on a bolt (its black core), y: its glow, z: on its thin hot middle.
fn rd_if_bolts(q: vec2<f32>, b: u32, seed: u32) -> vec3<f32> {
    let px = 1.0 / frame.resolution.y;
    var core = 0.0;
    var glow = 0.0;
    var hot = 0.0;
    for (var i = 0u; i < 8u; i = i + 1u) {
        let k = 0x5000u + (b * 16u + i) * 8u;
        let ang = TAU * (f32(i) + 0.8 * mh(i, seed, k)) / 8.0;
        let len = 0.4 + 0.95 * mh(i, seed, k + 1u);
        let w0 = 0.007 + 0.013 * mh(i, seed, k + 2u);
        let sb = len * (0.2 + 0.4 * mh(i, seed, k + 4u));
        let d = vec2<f32>(cos(ang), sin(ang));
        let o2 = d * sb + vec2<f32>(-d.y, d.x) * rd_if_bpath(sb, seed, k + 3u);
        let ang2 = ang + select(-1.0, 1.0, mh(i, seed, k + 5u) > 0.5) * (0.35 + 0.5 * mh(i, seed, k + 6u));
        let w2 = w0 * 0.6 * pow(1.0 - sb / len, 0.7);
        for (var j = 0u; j < 2u; j = j + 1u) {
            let bt = select(rd_if_bolt1(q, vec2<f32>(0.0), ang, len, w0, seed, k + 3u),
                            rd_if_bolt1(q, o2, ang2, (len - sb) * 0.6, w2, seed, k + 7u), j == 1u);
            if (bt.x > 0.2) {
                continue;
            }
            core = max(core, 1.0 - smoothstep(bt.y - px, bt.y + px, bt.x));
            hot = max(hot, 1.0 - smoothstep(bt.y * 0.3 - px, bt.y * 0.3 + px, bt.x));
            glow = max(glow, exp(-max(bt.x - bt.y, 0.0) / 0.022) * (1.0 - bt.z * bt.z));
        }
    }
    return vec3<f32>(core, glow, hot);
}
// The rod in the impact frames, held on the moment of contact (`ar`: how far into its strike it is drawn, seconds): 1
// where it stands in the way of this pixel's ray, above the land.
fn rd_if_rod(uv: vec2<f32>, ar: f32) -> f32 {
    let cam = frame.camera_position.xyz;
    let anc = anchor_xz();
    let N = vec3<f32>(floor(anc.x) + 0.5, block_y() + 1.0 + rd_nose_y(PL_HIT + max(ar, 0.0)), floor(anc.y) + 0.5) - cam;
    let rd = normalize(world_offset(uv, 0.5));
    let sg = pl_ray_seg(rd, N, N + vec3<f32>(0.0, RD_L, 0.0), 0.0, 1.0);
    let d = depth_at(uv);
    // (none of it under the land: what has gone in is out of sight)
    let gyr = block_y() + 1.0 - cam.y + pl_g0();
    if ((!is_sky(d) && length(world_offset(uv, d)) < sg.y - RD_R) || N.y + RD_L * sg.z < gyr) {
        return 0.0;
    }
    let w = sg.y * frame.view_params.w / frame.resolution.y;
    return 1.0 - smoothstep(RD_R - w, RD_R + w, sg.x);
}
// The rod's outline in the impact frames: a band a few pixels wide just round it.
fn rd_if_rim(uv: vec2<f32>) -> f32 {
    let cam = frame.camera_position.xyz;
    let anc = anchor_xz();
    let N = vec3<f32>(floor(anc.x) + 0.5, block_y() + 1.0 + rd_nose_y(PL_HIT), floor(anc.y) + 0.5) - cam;
    let rd = normalize(world_offset(uv, 0.5));
    let sg = pl_ray_seg(rd, N, N + vec3<f32>(0.0, RD_L + 6.0, 0.0), 0.0, 1.0);
    let gyr = block_y() + 1.0 - cam.y + pl_g0();
    if (N.y + (RD_L + 6.0) * sg.z < gyr + 1.0) {
        return 0.0;
    }
    let w = sg.y * frame.view_params.w / frame.resolution.y;
    let e = sg.x - RD_R;
    return smoothstep(-w, 0.0, e) * (1.0 - smoothstep(3.0 * w, 4.0 * w, e));
}
fn rd_if_scene(uv: vec2<f32>) -> vec3<f32> {
    return srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}
// The picture smeared out from the point P (zoom blur, `amt` of the way in) and split in colour (`ca`), the scene and
// the rod (drawn `ar` seconds into its strike) blurred and laid over what the pass drew there in place of their sharp
// selves, so the pass's own light stays.
fn rd_if_blur(col: vec3<f32>, uv: vec2<f32>, P: vec2<f32>, amt: f32, ca: f32, ar: f32) -> vec3<f32> {
    let jit = fract(52.9829189 * fract(dot(pl_px, vec2<f32>(0.06711056, 0.00583715))));
    var acc = vec3<f32>(0.0);
    for (var k = 0; k < 8; k = k + 1) {
        let f = 1.0 - amt * (f32(k) + jit) / 8.0;
        let o = (uv - P) * f;
        let c = vec3<f32>(rd_if_scene(P + o * (1.0 + ca)).r, rd_if_scene(P + o).g, rd_if_scene(P + o * (1.0 - ca)).b);
        acc = acc + mix(c, RD_IF_ROD, rd_if_rod(P + o, ar));
    }
    let sharp = mix(rd_if_scene(uv), RD_IF_ROD, rd_if_rod(uv, ar));
    return max(col + acc / 8.0 - sharp, vec3<f32>(0.0));
}
fn rd_impact(col: vec3<f32>, uv: vec2<f32>, a: f32, Cb: vec3<f32>, seed: u32) -> vec3<f32> {
    let asp = frame.resolution.x / frame.resolution.y;
    let P = rd_if_point(Cb);
    let cut = rd_if_cut(max(a, 0.0));
    let qj = (uv - P) * vec2<f32>(asp, 1.0);
    let q = qj * max(cut.y, 1.0 + 4.0 * cut.z);                                          // on the screen, in screen heights
    let r = length(q);
    let lw = vec3<f32>(0.2126, 0.7152, 0.0722);
    if (a < 0.0) {
        // (the breath in: the last two frames before it the picture drained and darkened from its edges in)
        let e = smoothstep(-0.035, 0.0, a);
        return mix(col, vec3<f32>(dot(col, lw)) * 0.5, e * 0.7 * smoothstep(0.05, 0.7, r));
    }
    let F = rd_if_hold();
    if (a >= F) {
        // ---- the release: smeared out from the point and split in colour, fading fast; then the long glow
        let s = a - F;
        var c = col;
        let bl = exp(-s / 0.11);
        if (bl > 0.1) {
            c = rd_if_blur(c, uv, P, 0.35 * bl, 0.06 * bl, rd_clock() - PL_HIT);
        }
        let tint = select(select(vec3<f32>(1.0, 0.86, 0.68), vec3<f32>(1.0, 0.74, 0.38), rd_if_style() == 1), vec3<f32>(1.0, 0.22, 0.16), rd_if_style() == 0);
        let tau = select(0.35, 0.6, rd_if_style() == 2);
        let g = exp(-s / tau) * smoothstep(RD_IF_END, RD_IF_END - 0.4, a);
        return c + tint * g * (0.03 + 0.7 * exp(-r / 0.18));
    }
    let kind = i32(cut.x + 0.5);
    let b = u32(cut.w);
    let rod = rd_if_rod(uv, 0.0);
    let rim = rd_if_rim(uv) * (1.0 - rod);
    if (rd_if_style() == 0) {
        // ---- the black flash
        let bo = rd_if_bolts(q, b, seed);
        if (kind == 2) {
            // (the held picture drained to bone and blood, the bolts' last black in it)
            let l = dot(col, lw);
            var c = mix(vec3<f32>(0.1, 0.0, 0.015), vec3<f32>(0.95, 0.92, 0.9), smoothstep(0.04, 0.75, l));
            c = mix(c, vec3<f32>(0.6, 0.02, 0.03), saturate(bo.y) * 0.6);
            return c * (1.0 - 0.9 * bo.x);
        }
        let m = max(rd_if_mask(uv) * (1.0 - rod), 0.0);
        let core = rd_if_core(qj, 0.02);
        if (kind == 0) {
            // (a pale negative: bone where it was bright, black where near; crimson round the bolts, their cores black,
            // the rod black with a crimson edge, the core at the point black in a red ring)
            var c = mix(vec3<f32>(0.02, 0.0, 0.006), vec3<f32>(0.88, 0.85, 0.82), m);
            c = mix(c, vec3<f32>(0.8, 0.02, 0.04), saturate(bo.y + rim + 0.9 * rd_if_halo(qj, 0.045)) * 0.9);
            return c * (1.0 - bo.x) * (1.0 - core) * (1.0 - rod);
        }
        // (close: red on black, the sky only a dark blood, the bolts red-hot round thin white cores, the rod black edged
        // in red, the point a black hole in a red-hot ring)
        var c = vec3<f32>(0.012, 0.0, 0.003) + vec3<f32>(0.035, 0.0, 0.005) * m;
        c = c + vec3<f32>(1.0, 0.05, 0.04) * (bo.y * 0.9 + rim * 1.4 + 1.6 * rd_if_halo(qj, 0.05));
        c = mix(c, vec3<f32>(1.6, 0.25, 0.15), bo.x);
        c = mix(c, vec3<f32>(1.4, 1.2, 1.1), bo.z);
        return c * (1.0 - core) * (1.0 - rod * (1.0 - bo.x));
    }
    if (rd_if_style() == 1) {
        // ---- Kanada
        let l = rd_if_focus(q, b, seed, 40.0, select(0.8, 0.65, kind == 1)) * (1.0 - rod) * (1.0 - rim);
        let core = rd_if_core(qj, 0.022);
        let m = max(max(rd_if_mask(uv) * (1.0 - rod), rim), core);
        if (kind == 0) {
            // (black silhouettes on white, the lines black on the white and white over the black)
            return vec3<f32>(abs(m - l));
        }
        if (kind == 1) {
            // (the negative, close: the sky black, the land and the rod pale, the lines gold over all)
            let base = mix(vec3<f32>(1.0, 0.96, 0.9), vec3<f32>(0.015, 0.01, 0.008), max(m, rim) * (1.0 - core));
            return mix(base, vec3<f32>(1.0, 0.7, 0.2) * 1.3, l);
        }
        // (gold and umber: the sky gold, the land and the rod dark umber, the lines the other of the two)
        let gold = vec3<f32>(1.0, 0.64, 0.14);
        let umb = vec3<f32>(0.07, 0.025, 0.008);
        return mix(umb, gold, abs(m - l));
    }
    // ---- cinematic
    if (kind == 0) {
        // (the white-out: the land a pale ghost, the rod burned black into it)
        let m = rd_if_mask(uv);
        let ray = rd_if_focus(q, 7u, seed, 56.0, 0.5);
        var c = mix(vec3<f32>(0.62, 0.55, 0.48), vec3<f32>(1.25, 1.2, 1.1), m) * (1.0 - 0.25 * ray * (1.0 - m * 0.6));
        c = c + vec3<f32>(1.5, 1.3, 1.0) * (rd_if_core(qj, 0.05) + 0.8 * rd_if_halo(qj, 0.12));
        return mix(c, vec3<f32>(0.01), rod);
    }
    // (held: the frozen picture bleached and hard, darkened to its edges, a shockwave ring tearing out across it from the
    // point, pushing the picture out under it, split in colour, the picture it has passed lit)
    let s = a - 0.05;
    let rr = 0.03 + s * 7.5;
    let e = r - rr;
    let dir = q / max(r, 1.0e-4);
    let duv = dir * vec2<f32>(1.0 / asp, 1.0) / max(cut.y, 1.0 + 4.0 * cut.z);
    let bump = exp(-pow(e / 0.05, 2.0));
    var c = rd_if_blur(col, uv, P, 0.05 + 0.25 * s, 0.006, 0.0);
    if (bump > 0.01) {
        let w = 0.035 * bump;
        let rc = vec3<f32>(rd_if_scene(uv - duv * w * 1.6).r, rd_if_scene(uv - duv * w).g, rd_if_scene(uv - duv * w * 0.4).b);
        c = max(c + rc - rd_if_scene(uv), vec3<f32>(0.0));
    }
    let l = dot(c, lw);
    c = smoothstep(vec3<f32>(0.04), vec3<f32>(0.8), mix(vec3<f32>(l), c, 0.3));
    let passed = smoothstep(0.02, -0.04, e);
    c = c * mix(vec3<f32>(0.74, 0.77, 0.86), vec3<f32>(0.86, 0.85, 0.84), passed) * (1.0 - 0.45 * smoothstep(0.4, 1.1, r));
    c = c + vec3<f32>(1.0, 0.25, 0.1) * exp(-pow((e + 0.012) / 0.006, 2.0)) * 0.9
          + vec3<f32>(1.0, 0.95, 0.85) * exp(-pow(e / 0.005, 2.0)) * 1.2
          + vec3<f32>(0.15, 0.35, 1.0) * exp(-pow((e - 0.012) / 0.006, 2.0)) * 0.9;
    return c + vec3<f32>(1.5, 1.35, 1.1) * rd_if_core(qj, 0.035);
}

// ---- the jolt on the picture: the game's camera shake (rod.rs's rd_jolt) tops out at a few degrees, so as the
// shockwave reaches the player the picture itself is knocked about too: a hard, sharp hit, ringing out fast, then a
// shudder dying away over five seconds or so; hardest within a couple of hundred blocks. Shifted and turned a little
// and zoomed in just enough that no edge shows. And on the impact frames' cuts the picture punched in hard on the
// impact point and kicked a new way each frame (rd_if_cut). The lens's own marks stay put (pl_px). ---------------------------------------------------------
var<private> pl_px: vec2<f32>;
fn pl_jolt(in: StageIn) -> StageIn {
    pl_px = in.position.xy;
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    var o = in;
    let ai = now() - PL_HIT;
    if (rd_if_on() && ai > 0.0 && ai < RD_IF_END) {
        // (the impact frames' camera: punched in on the point on each cut, kicked a new way each frame, snapping back
        // out on the release)
        let cut = rd_if_cut(ai);
        let C = vec3<f32>(anchor_xz().x, block_y() + 1.0 + pl_g0(), anchor_xz().y) - frame.camera_position.xyz;
        let P = clamp(rd_if_point(C), vec2<f32>(0.2), vec2<f32>(0.8));
        let fi = u32(floor(ai * 60.0)) + 300u;
        let sd = u32(seed_v());
        let sh = (vec2<f32>(mh(fi, sd, 0x4f1u), mh(fi, sd, 0x4f2u)) - 0.5) * 2.0 * cut.z;
        let z = max(cut.y, 1.0 + 4.0 * cut.z);
        o.uv = clamp(P + (in.uv - P) / z + sh * vec2<f32>(1.0 / asp, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
        o.position = vec4<f32>(o.uv * res, in.position.zw);
    }
    let tgt = vec3<f32>(anchor_xz().x, block_y() + 1.0 + PL_BURST, anchor_xz().y);
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z);
    let dist = length(me - tgt);
    let s = now() - PL_HIT - dist / PL_V;                  // since the front reached the player
    if (s <= 0.0 || s > 7.0 || intensity_v() <= 0.0) {
        return o;
    }
    let g = clamp(1.5 / (1.0 + dist / 350.0), 0.2, 1.0);
    // (the hit: a slam, then swinging hard and fast, three or four times, dying in half a second)
    let hit = 0.034 * g * exp(-s / 0.22) * smoothstep(0.0, 0.015, s);
    let ring = vec2<f32>(
        0.65 * sin(s * 53.0 + 0.6) + 0.35 * sin(s * 89.0 + 2.1),
        0.65 * cos(s * 47.0 + 1.3) + 0.35 * sin(s * 77.0 + 0.4)
    );
    // (the shudder: the ground still heaving under the player, fading over seconds)
    let shud = 0.005 * g * exp(-s / 1.8) * smoothstep(0.08, 0.4, s);
    let sh = vec2<f32>(
        0.55 * sin(s * 17.0 + 0.3) + 0.3 * sin(s * 29.0 + 1.9) + 0.15 * sin(s * 53.0),
        0.55 * cos(s * 15.0 + 2.2) + 0.3 * sin(s * 31.0 + 0.7) + 0.15 * cos(s * 59.0)
    );
    let off = ring * hit + sh * shud;
    let roll = 0.018 * g * exp(-s / 0.3) * sin(s * 41.0 + 0.9) + 0.0025 * g * exp(-s / 1.8) * sin(s * 11.0);
    let zoom = 1.0 + 2.2 * (hit + shud) + 1.1 * abs(roll) * asp;
    var q = (o.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom;
    q = vec2<f32>(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll)) + off;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}
@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    let in = pl_jolt(in0);
    return rod(in, 0u, vec4<f32>(0.0), vec3<f32>(1.0e9, 1.0, 0.0)).c;
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): on a game with mod passes' half-size stage (docs/mods.md of the
// Horizon fork, release orbital-mod-api-7), the smoke is drawn at half the width and height by fs_half and laid over
// the full-size picture by fs_join; a game without it compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct PlHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> PlHalf {
    pl_px = in.position.xy;
    let o = rod(in, 1u, vec4<f32>(0.0), vec3<f32>(1.0e9, 1.0, 0.0));
    return PlHalf(o.c, o.e);
}

// The half-size stage's smoke at this pixel (whose ray goes `len` blocks): the four nearest of its pixels, each weighed
// by how near it is (bilinearly) and by how near the depth it was marched to is to this pixel's, so that across an edge
// against a block or the sky only the ones on this pixel's side count (a joint bilateral upsample); if none is, the
// nearest in depth round it. In .x of the second the column's distance of the one that counts most, in .y and .z the
// first and the last of the debris near any of the four (one more than their numbers; 0: none).
fn pl_up(pos: vec2<f32>, len: f32) -> PlOut {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var best_w = -1.0;
    var best_t = 1.0e9;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var near_t = 1.0e9;
    var debris = 1.0e4;
    var debris_hi = 0.0;
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        let dz = abs(e.x - lp) / max(lp, 1.0);
        if (e.z > 0.5) {
            debris = min(debris, e.z);
            debris_hi = max(debris_hi, e.w);
        }
        let w = bw * exp(-dz * 24.0);
        acc = acc + c * w;
        sw = sw + w;
        if (w > best_w) {
            best_w = w;
            best_t = e.y;
        }
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
            near_t = e.y;
        }
    }
    debris = select(0.0, debris, debris_hi > 0.5);
    if (sw < 1.0e-3) {
        // (none of the four on this pixel's side, as for a speck of sky through leaves: the nearest in depth of the four
        // by four round it)
        for (var k = 0; k < 16; k = k + 1) {
            let q = clamp(i0 + vec2<i32>((k & 3) - 1, (k >> 2u) - 1), vec2<i32>(0), hs - vec2<i32>(1));
            let e = textureLoad(half_extra, q, 0);
            let dz = abs(e.x - lp) / max(lp, 1.0);
            if (dz < near_dz) {
                near_dz = dz;
                near_c = textureLoad(half_picture, q, 0);
                near_t = e.y;
            }
        }
        return PlOut(near_c, vec4<f32>(near_t, debris, debris_hi, 0.0));
    }
    return PlOut(acc / sw, vec4<f32>(best_t, debris, debris_hi, 0.0));
}

@fragment
fn fs_join(in0: StageIn) -> @location(0) vec4<f32> {
    // (jolted as fs_main is: the half-size picture, drawn steady, read where the jolted pixel looks)
    let in = pl_jolt(in0);
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let u = pl_up(in.position.xy, len);
    return rod(in, 2u, u.c, vec3<f32>(select(u.e.x, 1.0e9, u.e.x >= 6.0e4), u.e.y, u.e.z)).c;
}
// [end half stage]
