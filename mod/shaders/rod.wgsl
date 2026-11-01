// Orbital Laser's post pass for the Rod from God (laser 11): the Nuke's (nuke.wgsl) turned kinetic. Like it, the mod
// builds it from shaders/strike.wgsl up to its fs_main less the other lasers' own functions, followed by this file, and
// sets it for a rod strike only. Validate with tools/check-shader.sh.

// ---- laser 11: the rod from god -----------------------------------------------------------------------------------
// No beam, no explosive. A tungsten rod comes down from orbit: a thin, blinding white-hot streak tearing straight down
// out of the sky, faster and faster, a long thin straight ionised trail behind it and a faint shock-cone shimmer round it;
// it strikes: impact frames (a few stark, stylised frames for a split second: white, the scene thresholded into black
// and white silhouettes with jagged impact lines bursting from the point, its negative), a small sharp white flash, a
// hemispherical shockwave bending the light, a fountain of rock thrown up in a cone round a tall column of pulverised
// earth that rises, falls back and spreads, a ground-hugging ring of dust racing out; debris raining down round it.
// strike/rod.rs samples the path into the table (rd_table, render.set-data): keep the PL_* in step with its RD_*.
const PL_SEEN: f32 = 1.0;          // the rod shows, high in the sky,
const PL_HIT: f32 = 7.0;           // and strikes,
const PL_BURST: f32 = 0.0;         // on the ground under the target (pl_g0)
const PL_LEN: f32 = 60.0;          // the strike's length (lasers.rs): everything fades out over its last PL_FADE
const PL_FADE: f32 = 8.0;
const PL_SOFT0: f32 = 20.0;        // the column keeps its crisp lumps this long after the impact, then loses them
const PL_SOFT1: f32 = 38.0;        // by this, a soft, drifting haze thinning away (gone by PL_LEN)
const PL_CHURN: f32 = 7.0;         // the head's lumps carried this long before they are let go (pl_col_sdf)
const PL_V: f32 = 343.0;           // the shockwave's front, blocks a second (with the blast's sound: rod.rs)
const PL_P: u32 = 16u;             // the table: the path's samples from PL_P, three words each,
const PL_PF: u32 = 400u;
const PL_PW: u32 = 8u;
const PL_HF: u32 = 1024u;          // the land's heightfield (rod.rs's rd_hf_words): its size, then heights, shelter
const PL_FR: u32 = 560u;           // (no pieces shed)
const PL_FW: u32 = 12u;
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
// How far a bit of the trail (sample i) has drifted `age` seconds after it was laid: carried by the wind, rising a
// little, wandering.
fn pl_trail_drift(i: i32, age: f32, seed: u32) -> vec3<f32> {
    let fi = f32(i);
    let wob = vec3<f32>(sin(fi * 0.21 + f32(seed % 61u)), 0.4 * sin(fi * 0.13 + 2.0), cos(fi * 0.17 + f32(seed % 37u)));
    return pl_wind() * age + vec3<f32>(0.0, 0.35 * age, 0.0) + wob * (0.35 * age);
}
// Where a bit of the trail laid at time te has drifted to by time t.
fn pl_trail_at(i: i32, te: f32, t: f32, seed: u32) -> vec3<f32> {
    return pl_sample(i) + pl_trail_drift(i, max(t - te, 0.0), seed);
}
// Where a shed piece is `s` seconds after it let go at p0 with velocity v0: slowed by the air (drag k a second),
// falling (under gravity with that drag).
fn pl_frag(p0: vec3<f32>, v0: vec3<f32>, k: f32, s: f32) -> vec3<f32> {
    let e = (1.0 - exp(-k * s)) / k;
    return p0 + v0 * e - vec3<f32>(0.0, 20.0 * (s - e) / k, 0.0);
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
// Point j of the trail at strike time t: laid at its sample's time, drifted since; the one past the last laid is the
// head's.
fn pl_trail_pt(j: i32, last: i32, thead: f32, t: f32, seed: u32) -> vec3<f32> {
    if (j > last) {
        return pl_head(thead);
    }
    return pl_trail_at(max(j, 0), pl_w(1u) + pl_w(2u) * f32(max(j, 0)), t, seed);
}
// Where along the ray (from, to) it is on the side of the plane through p that n faces.
fn pl_half(rd: vec3<f32>, p: vec3<f32>, n: vec3<f32>) -> vec2<f32> {
    let r = dot(rd, n);
    let c = dot(p, n);
    if (abs(r) < 1.0e-6) {
        return select(vec2<f32>(1.0, 0.0), vec2<f32>(-1.0e9, 1.0e9), c <= 0.0);
    }
    let tc = c / r;
    return select(vec2<f32>(-1.0e9, tc), vec2<f32>(tc, 1.0e9), r > 0.0);
}
fn pl_erf(x: f32) -> f32 {
    let y = clamp(x, -4.0, 4.0);
    return tanh(1.1284 * y + 0.1009 * y * y * y);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// How much of the sun's light the cap lets through to a point `o` under it (camera-relative): the sun's ray from it
// crossing the cap's level, through its broad soft disc. For the stem, the surge and the dust, which the full march
// (pl_shadow) would cost too much for at every step.
fn pl_cap_shade(o: vec3<f32>, L: vec3<f32>, a: f32, C: vec3<f32>, hc: f32, R: f32) -> f32 {
    let capy = C.y + hc;
    if (L.y < 0.02 || o.y > capy) {
        return 1.0;
    }
    let s = (capy - o.y) / L.y;
    let r = length((o + L * s - C - pl_wind() * a).xz);
    let thin = 1.0 - 0.8 * smoothstep(PL_SOFT0, PL_LEN, a);
    return 1.0 - 0.8 * (1.0 - smoothstep(0.55 * R, 1.1 * R, r)) * smoothstep(2.0, 6.0, a) * thin;
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
// How strongly the fireball's foot is there at `a` seconds after the burst: from the first frames, letting go of the
// ground over its third and fourth seconds as the ball lifts away on its stem.
fn pl_foot_k(a: f32) -> f32 {
    return 1.0 - smoothstep(1.2, 3.8, a);
}
// The fireball's foot at (rho, hy) from the burst's ground (`rt` the ball's radius): a broad dome hugging the land, a
// third wider than the ball and half as high, so the fire spreads along the ground under it; below the ground a ball
// (hidden by the land, there so the foot meets every slope round it). Its distance, sunk away as it lets go.
fn pl_foot(a: f32, rt: f32, rho: f32, hy: f32) -> f32 {
    let s = pl_foot_k(a);
    let rf = 1.3 * rt + 6.0;
    let hf = select(0.55 * rt + 4.0, rf, hy < 0.0) * (0.35 + 0.65 * s);
    let e = vec2<f32>(rho / rf, hy / hf);
    return (length(e) - 1.0) * min(rf, hf) + (1.0 - s) * (0.6 * rt + 40.0);
}
// How far under the burst's ground the foot reaches (the cloud's box).
fn pl_foot_low(a: f32, rt: f32) -> f32 {
    return select(0.0, 1.3 * rt + 6.0, pl_foot_k(a) > 0.0);
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

const PL_DM: f32 = 40.0;           // the most the column's lumps stand out of its smooth body (pl_col_sdf), which the
                                   // march's bounds, gates and long steps allow for
const PL_S: f32 = 1.3;             // the lumps' scale (the Nuke's 2.2: a narrower body, finer, grittier lumps)
// ---- the column of dust: pulverised earth thrown up out of the crater, a tall rising column flaring into a ragged
// head, falling back and spreading over the land round its foot ---------------------------------------------------
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
    // (thrown up fast: most of its height in under three seconds, about 280 at its highest by eight or so; then falling
    // back, its head sinking and swelling as the dust spreads and settles)
    let rise = 1.0 - exp(-a / 1.3);
    let fall = smoothstep(5.0, 30.0, a);
    o.st = 290.0 * rise * (1.0 - 0.55 * fall) + 6.0;
    // (its foot as wide as the crater it came out of, flaring up the column into a ragged top no wider than the
    // column, not a cap; spreading as it falls back)
    o.sr = vec3<f32>(44.0 + 8.0 * saturate(a / 3.0) + 2.2 * a, 30.0 + 8.0 * saturate(a / 6.0) + 2.4 * a, 40.0 + 14.0 * saturate(a / 5.0) + 1.8 * a);
    o.rt = (0.85 * o.sr.z) * (0.4 + 0.6 * rise) * (1.0 - 0.5 * fall);
    o.hc = max(o.st - 0.5 * o.rt, 0.6 * o.rt);
    o.Rt = 0.0;
    o.ring = vec3<f32>(0.0);
    // (the base surge: what falls back, rolling out over the ground round its foot, spreading and settling)
    o.surge = vec3<f32>(40.0 + 170.0 * (1.0 - exp(-a / 10.0)), 22.0 + 0.4 * a, 7.0 + 10.0 * saturate(a / 12.0));
    let top = o.st + 0.6 * o.rt;
    let w = max(max(o.sr.z, o.rt * 1.3), o.surge.x + o.surge.y) + 60.0;
    let lean = pl_wind() * a;
    o.lo = C + vec3<f32>(-w + min(lean.x, 0.0), -24.0, -w + min(lean.z, 0.0));
    o.hi = C + vec3<f32>(w + max(lean.x, 0.0), top + 60.0, w + max(lean.z, 0.0));
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
    let eq = vec3<f32>(q.x, (hy - hc) * 1.35, q.z);
    let ek0 = length(eq / rt);
    var d = (ek0 - 1.0) * rt * 0.85;
    // (the column: from under the crater's floor up into the head, flaring)
    let u = saturate(hy / max((*col).st, 1.0));
    let sr = (*col).sr;
    let rs = mix(mix(sr.x, sr.y, smoothstep(0.0, 0.25, u)), sr.z, smoothstep(0.35, 1.0, u)) * (0.9 + 0.2 * sin(hy * 0.05 + 1.3));
    let ds = max(rho - rs, max(hy - hc, -hy - 24.0));
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
    let edge = mix(1.5, 6.0, ew) + 10.0 * (1.0 - smoothstep(0.0, 60.0, hy));
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

// How much of the sun's light reaches land point `o` (camera-relative) through the cloud: its smooth body marched
// towards the sun in a dozen steps, soft-edged (a little of its lumps' reach counted in). 1 in full sun.
fn pl_shadow(o: vec3<f32>, L: vec3<f32>, a: f32, C: vec3<f32>, j: f32) -> f32 {
    var cs = pl_column(a, C);
    let tb = pl_box(L, cs.lo - o, cs.hi - o);
    if (tb.y <= tb.x) {
        return 1.0;
    }
    // (first, whether the sun's ray passes near the cloud at all: the stick from its foot to its cap's core)
    let ctop = C + vec3<f32>(0.0, cs.hc, 0.0) + pl_wind() * a;
    let sg = pl_ray_seg(L, C - o, ctop - o, 0.0, 1.0);
    if (sg.x > max(max(cs.sr.z, cs.rt), cs.surge.x + cs.surge.y) + 40.0) {
        return 1.0;
    }
    let n = 14;
    let dt = (tb.y - tb.x) / f32(n);
    var tau = 0.0;
    for (var i = 0; i < n; i = i + 1) {
        let d = pl_col_base2(&cs, o + L * (tb.x + (f32(i) + j) * dt)).x;
        tau = tau + saturate(0.35 - d / 45.0);
    }
    // (thinning as the cloud does, late on)
    let thin = 1.0 - 0.8 * smoothstep(PL_SOFT0, PL_LEN, a);
    return exp(-tau * dt * 0.022 * thin * smoothstep(0.3, 2.0, a));
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
// The pass, in one of three stages: 0 the whole of it at full size (fs_main); 1 the half-size stage (fs_half: the
// smoke, the trail, the dust and the pieces' smoke, over a two by two of the picture's pixels, marched to alternately
// the nearest and the farthest of their depths), returned as premultiplied colour and transmittance; 2 the join
// (fs_join: the rest, sharp, at full size, with the half-size stage's `up` (colour, transmittance) laid over the picture
// where that stage drew them; `up_e`: the column's distance, and the first and last of the debris that may be near
// this pixel, each one more than its number (0: none)).
fn rod(in: StageIn, stage: u32, up: vec4<f32>, up_e: vec3<f32>) -> PlOut {
    let up_t = up_e.x;
    var uv = in.uv;
    let time = now();
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let px_a = frame.view_params.w / frame.resolution.y;      // (the angle a pixel spans)
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;              // the strike's point, on the target's ground
    let Cb = C + vec3<f32>(0.0, pl_g0(), 0.0);              // the ground under the burst (the cloud's foot)
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
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    // (the half-size stage's own: what it has gathered, over what lies behind)
    var hc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    // (leaves and grass whipped as the blast's front goes through them: what is green near it shaken on the screen)
    if (stage != 1u && !sky && time > PL_HIT && time < PL_HIT + 6.0) {
        let rfr = PL_V * (time - PL_HIT);
        let rs = length((rel - (vec3<f32>(anchor_xz().x, block_y() + 1.0, anchor_xz().y) - cam)).xz);
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
    let fade = 1.0 - smoothstep(PL_LEN - PL_FADE, PL_LEN, time);
    let a = time - PL_HIT;                                    // seconds since it struck
    let have = pl_n() > 1;

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
    // (the haze along the horizon, reddened by a low sun: the light the sky gives from round about)
    let fogl = srgb_to_linear(frame.fog_color.rgb);
    let haze_c = mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day);

    // ---- the shockwave: a shell racing out from the burst at the speed of sound, bending the light where the eye looks
    // along it (its edge on the picture), a faint white sheen of condensation on it for the first seconds ------------
    let Pb = Cb + vec3<f32>(0.0, PL_BURST, 0.0);
    if (stage != 1u && a > 0.0 && a < 5.0) {
        let Rs = PL_V * a;
        let bq = dot(rd, Pb);
        let cq = dot(Pb, Pb) - Rs * Rs;
        let disc = bq * bq - cq;
        if (disc > 0.0) {
            let sq = sqrt(disc);
            // (where the ray meets the shell, in front of the scene, over the land: the near side, else the far)
            var th = bq - sq;
            if (th < 0.0) {
                th = bq + sq;
            }
            let hp = rd * th;
            if (th > 0.0 && th < scene_len + 4.0 && hp.y > Cb.y - 4.0) {
                // (grazing: the shell seen edge-on, a band some tens of blocks thick along its outline)
                // (the rod's: tighter and sharper than the Nuke's, and gone sooner)
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
                col = col + vec3<f32>(0.9, 0.93, 1.0) * (0.3 * edge + 0.04 * exp(-sq / (0.3 * Rs))) * exp(-a / 0.8) * sf * (0.3 + 0.7 * day);
            }
        }
    }

    // ---- the shock cone round the rod: a faint shimmer, the air bent along a thin cone opening back from its tip --------
    if (stage != 1u && have && time > PL_SEEN && time < PL_HIT) {
        let H0 = pl_head(time);
        let Hp = H0 + C;
        let vd = normalize(H0 - pl_head(time - 0.03) + vec3<f32>(0.0, -1.0e-4, 0.0));
        let Lc = 160.0;
        let sg = ray_seg(rd, Hp, Hp - vd * Lc);
        if (sg.y < scene_len) {
            let rc = 1.5 + 0.2 * sg.z * Lc;
            let w = max(1.2 + 0.03 * sg.z * Lc, sg.y * px_a * 1.5);
            let e = exp(-pow((sg.x - rc) / w, 2.0)) * (1.0 - sg.z) * smoothstep(PL_SEEN, PL_SEEN + 0.5, time);
            if (e > 0.01) {
                let pa = project_rel(Hp);
                let pb = project_rel(Hp - vd * Lc);
                let ax = normalize(pb.xy - pa.xy + vec2<f32>(1.0e-6));
                let nrm = vec2<f32>(-ax.y, ax.x);
                let sd = select(-1.0, 1.0, dot(uv - pa.xy, nrm) > 0.0);
                let off = nrm * sd * 0.004 * e * k;
                let sc = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv - off, 0.0).rgb);
                col = mix(col, sc, saturate(e * 3.0));
                col = col + vec3<f32>(0.85, 0.9, 1.0) * 0.05 * e * k * (0.3 + 0.7 * day);
            }
        }
    }

    // ---- the flash: small and sharp, white, lighting the land round it for a moment ---------------------------------
    let fl = select(0.0, 7.0 * exp(-a / 0.05) + 0.5 * exp(-a / 0.35) + 0.03 * exp(-a / 4.0), a > 0.0) * fade;
    if (stage != 1u && a > 0.0) {
        let Pf = Cb + vec3<f32>(0.0, 3.0, 0.0);
        let df = length(Pf);
        let cth = dot(rd, Pf / df);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let fire_c = mix(vec3<f32>(2.6, 1.5, 0.7), vec3<f32>(3.1, 3.15, 3.4), exp(-a / 0.15));
        // (the point of light itself, tight, and its glow in the air, seen through anything)
        let tp = max(4.0 / df, px_a * 1.2);
        col = col + fire_c * fl * (0.6 * exp(-pow(th / tp, 2.0)) + 0.03 / (1.0 + pow(th / 0.03, 2.0)) + 0.006 * exp(-th / 0.4)) * k;
        if (sky) {
            col = col + vec3<f32>(0.9, 0.92, 1.0) * 0.1 * exp(-a / 0.3) * (0.35 + 0.65 * (1.0 - day)) * k * fade;
        } else {
            let dl = length(rel - Pf);
            col = col + scene * fire_c * fl * 0.9 / (1.0 + pow(dl / 140.0, 2.0)) * k;
            // (and the ground round the point glowing hot for a moment)
            let rg = length((rel - Cb).xz);
            let hot = (2.5 * exp(-a / 0.4) + 0.4 * exp(-a / 2.0)) * (1.0 - smoothstep(10.0, 45.0, rg)) * (1.0 - smoothstep(10.0, 40.0, abs(rel.y - Cb.y)));
            col = col + scene * vec3<f32>(3.0, 1.2, 0.4) * hot * k * fade;
        }
    }

    // ---- the cloud's shadow on the land: the sun's light through the cloud's own body, marched from the land towards
    // the sun, so it falls where the cloud really is: under it at noon, long and far across the land at a low sun, the
    // stem's band, the base surge's skirt; soft, and the sky still lights what lies in it -------------------------------
    if (stage != 1u && !sky && have && a > 0.3 && L.y > 0.02 && fract(frame.mod_params[3].w * 0.5) < 0.25) {
        let T = pl_shadow(rel, L, a, Cb, ign(in.position.xy));
        col = col * (1.0 - 0.72 * (1.0 - T) * sun_up * k * fade);
    }

    // ---- the trail: a cord of lumpy smoke hung along its path, pale and thin high up, dark grey-brown and dense along
    // the dive, lit orange by the flame just behind the head; as it ages it swells, pales, breaks into beads and puffs,
    // frays and thins away over twenty seconds or so, drifting with the wind ------------------------------------------
    // (the join: the half-size stage's smoke over the picture, where the trail's would go)
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    }
    if (stage != 2u && have && time > PL_SEEN) {
        let n = pl_n();
        let t0 = pl_w(1u);
        let dt = pl_w(2u);
        let thead = min(time, PL_HIT);
        let last = min(i32(floor((thead - t0) / dt)), n - 1);
        var tau = 0.0;
        var tc = vec3<f32>(0.0);
        var glow = vec3<f32>(0.0);
        let sd = vec3<f32>(f32(seed % 97u) * 3.1, f32(seed % 89u) * 1.7, 0.0);
        // (the trail's points, the head's the one past the last laid)
        var pa = pl_trail_pt(0, last, thead, time, seed) + C;
        var pv = pa;                      // the point before pa (pa itself before the first)
        var have_pv = true;
        var pc = pa;                      // the point after pa, when it is known already
        var have_pc = false;
        for (var i = 0; i <= last; i = i + 1) {
            // (eight pieces at a time looked at as one ball round them first: most rays pass well clear of it)
            if (i % 8 == 0 && i + 8 <= last) {
                let pg = pl_trail_pt(i + 8, last, thead, time, seed) + C;
                let cg = 0.5 * (pa + pg);
                let ag = max(time - (t0 + dt * f32(i)), 0.0);
                let tg = max(dot(cg, rd), 0.0);
                let rg = 0.65 * length(pg - pa) + 3.4 * (6.0 + 4.8 * sqrt(ag) + tg * px_a) + 4.0;
                if (length(cg - rd * tg) > rg || tg - rg > scene_len) {
                    pa = pg;
                    have_pv = false;
                    have_pc = false;
                    i = i + 7;
                    continue;
                }
            }
            if (!have_pv) {
                pv = pl_trail_pt(i - 1, last, thead, time, seed) + C;
            }
            var pb = pc;
            if (!have_pc) {
                pb = pl_trail_pt(i + 1, last, thead, time, seed) + C;
            }
            var pn = pb + (pb - pa);
            if (i < last) {
                pn = pl_trail_pt(i + 2, last, thead, time, seed) + C;
            }
            pc = pn;
            have_pc = true;
            let pa_ = pa;
            let pv_ = pv;
            pv = pa;
            have_pv = true;
            pa = pb;
            // (each piece is the smoke between two planes across the trail, through its two ends and halfway round
            // the bend at each, so that the pieces fit together with no seam, gap or overlap at any angle it is seen
            // from; the ray's way through each is counted, not one point on it. The whole's first end capped a little
            // past its first point, its last carried on past the head.)
            let ab = pb - pa_;
            let len_ab = max(length(ab), 1.0e-4);
            let da = ab / len_ab;
            let te_a = t0 + dt * f32(i);
            let age_a = max(time - te_a, 0.0);
            var na = da;
            var oa = pa_;
            if (i == 0) {
                oa = pa_ - da * (2.0 + 2.0 * sqrt(age_a));
            } else {
                na = normalize(da + normalize(pa_ - pv_ + vec3<f32>(0.0, 1.0e-5, 0.0)));
            }
            var nb = da;
            var ob = pb;
            if (i < last) {
                nb = normalize(da + normalize(pn - pb + vec3<f32>(0.0, 1.0e-5, 0.0)));
            } else {
                // (on into the ground, where it struck: not cut off square across it over the ground)
                ob = pb + da * (12.0 + 8.0 * sqrt(max(time - thead, 0.0))) * step(PL_HIT, time);
            }
            let ia = pl_half(rd, oa, na);
            let ib = pl_half(rd, ob, -nb);
            let t1 = max(max(ia.x, ib.x), 0.0);
            let t2 = min(min(ia.y, ib.y), scene_len);
            if (t2 <= t1) {
                continue;
            }
            let h = pl_ray_seg(rd, pa_, pb, -1.0e4, 1.0e4);
            let tn = clamp(h.y, t1, t2);
            let sz = clamp(dot(rd * tn - pa_, da) / len_ab, 0.0, 1.0);
            // (the lumps looked up on the sheet through the trail's axis that faces the eye: how far along this piece
            // the ray's way through it lies, and how far across the ray passes. Not where the ray meets the piece's
            // end, which a ray seen glancing along it would smear into streaks.)
            let cp = pa_ + ab * sz + (rd * h.y - (pa_ + ab * h.z));
            let te = clamp(te_a + dt * sz, t0, thead);
            let age = max(time - te, 0.0);
            // (the rod's: a long thin straight line of ionised air glowing behind it, white-blue cooling to a faint violet
            // within a second, and a thin pale vapour trail left hanging, swelling a little and drifting)
            let heat = 0.0;
            let gone = 0.0;
            let dv = smoothstep(PL_SEEN, PL_HIT, te);
            let dive = 0.0;
            // (smoke rather than vapour: from a second or two after it shows, as in the third clip, where the whole
            // hook it draws is the same grey-brown smoke)
            let smk = 0.0;
            // (its core's radius: thin and tight where it is laid, swelling with age; the outer fray to twice that)
            // (never thinner than a pixel, its density spread over the width it is drawn at)
            let rad0 = 0.9 + 0.6 * dv + 1.1 * sqrt(age);
            let rad = max(rad0, tn * px_a * 0.9);
            let thin = rad0 / rad;
            if (h.x < rad * 3.4 && gone < 1.0) {
                // (the smoke's own lumps, carried with it as it drifts and rises, churning slowly: looked up where the
                // smoke was laid (fixed, so they never slide along it) and across it in its own width (so they swell
                // with it, about its axis). Their size along it cannot follow the width without sliding, so they are
                // looked up at the two fixed sizes either side of it, a doubling apart, and faded from one to the
                // next as it swells.)
                let sw = 2.2 * rad + 3.0;
                let la = pa_ - pl_trail_drift(i, age_a, seed);
                var lb = pb;
                if (i < last) {
                    lb = pb - pl_trail_drift(i + 1, max(time - (te_a + dt), 0.0), seed);
                }
                let laid = mix(la, lb, sz) - C;
                let across = (cp - (pa_ + ab * sz)) / sw + sd;
                let lv = log2(sw / 8.0);
                let lk = floor(lv);
                let lf = lv - lk;
                let sA = 8.0 * exp2(lk);
                let qa = laid / sA + across + vec3<f32>(lk * 17.3, lk * 5.1, 0.0);
                let qb = laid / (2.0 * sA) + across + vec3<f32>((lk + 1.0) * 17.3, (lk + 1.0) * 5.1, 0.0);
                // (two lookups faded together are evener than one: their spread put back)
                let lsp = 1.0 / sqrt(lf * lf + (1.0 - lf) * (1.0 - lf));
                // (the lumps are looked up once, where the ray passes nearest its axis: they are painted on a sheet
                // through it, facing the eye. Where the trail runs away from the eye that sheet is squeezed along the
                // trail and its lumps drawn out across it into streaks; but there the ray goes a long way through the
                // smoke along it and would see many lumps one behind another, evened out. So each size of lump lets go
                // towards its mean as the stretch of trail the ray passes through (or a pixel spans) grows past it.)
                let sn = max(length(cross(rd, da)), 0.08);
                let qs = 1.0 / (2.2 * rad + 3.0);
                let along = tn * px_a / sn * qs;
                let thru = 2.0 * sqrt(max(2.1 * rad * rad - h.x * h.x, 0.0)) * abs(dot(rd, da)) / sn * qs + 1.0e-3;
                let w1 = min(saturate(2.0 * sqrt(1.0 / thru)), saturate(2.0 - 10.0 * along));
                let w2 = min(saturate(2.0 * sqrt(0.385 / thru)), saturate(2.0 - 10.0 * along * 2.6));
                let w3 = min(saturate(2.0 * sqrt(0.164 / thru)), saturate(2.0 - 10.0 * along * 6.1));
                // (each looked up only where it shows)
                var n1 = 0.5;
                var n2 = 0.5;
                var n3 = 0.5;
                if (w1 > 0.0) {
                    let o = vec3<f32>(0.0, 0.0, 0.06 * age);
                    n1 = 0.5 + (mix(gnoise3(qa + o), gnoise3(qb + o), lf) - 0.5) * lsp;
                }
                if (w2 > 0.0) {
                    let o = vec3<f32>(4.0, 0.08 * age, 1.0);
                    n2 = 0.5 + (mix(gnoise3(qa * 2.6 + o), gnoise3(qb * 2.6 + o), lf) - 0.5) * lsp;
                }
                if (w3 > 0.0) {
                    let o = vec3<f32>(1.0, 7.0, 0.15 * age);
                    n3 = 0.5 + (mix(gnoise3(qa * 6.1 + o), gnoise3(qb * 6.1 + o), lf) - 0.5) * lsp;
                }
                let puff = 0.5 + 0.62 * w1 * (n1 - 0.5) + 0.3 * w2 * (n2 - 0.5) + 0.08 * w3 * (n3 - 0.5);
                // (a soft profile across it, its edge pushed in and out by the lumps: ragged, no rim)
                let rw = rad * (0.45 + 1.0 * puff);
                let rr = h.x / rw;
                // (and let go to nothing before the edge it is looked for within, not cut off there: the let-go
                // itself pushed in and out by the lumps, or where the smoke is dense its edge would be the let-go's,
                // smooth and straight)
                let prof = exp(-rr * rr * 1.4) * smoothstep(2.3, 1.5, rr);
                // (how much of the profile along the ray lies in this piece, and how much longer the ray's way through
                // it is than straight across)
                let ka = 1.183 * sn / rw;
                let gin = 0.5 * (pl_erf((t2 - h.y) * ka) - pl_erf((t1 - h.y) * ka)) / max(sn, 0.5);
                // (broken into beads and puffs as it ages, the gaps opening; the vapour high up breaks sooner. Where
                // the lumps are evened out, what they would have let through on the whole: the gaps' and the beads'
                // mean, not the mean lump's, which the gaps would swallow)
                let thr = mix(0.32, 0.12, smk) - 0.1 * heat + 0.38 * smoothstep(1.5, 18.0, age);
                let m = (puff - thr) * 3.2 + 0.3 * exp(-age / 0.8);
                let sl = 3.2 * 0.14 * sqrt(0.384 * (1.0 - w1 * w1) + 0.09 * (1.0 - w2 * w2) + 0.0064 * (1.0 - w3 * w3)) + 1.0e-3;
                let dens = saturate(sl * log(1.0 + exp(clamp(m / sl, -30.0, 30.0))));
                // (dense where it is laid, thinning over the next twenty seconds; the vapour fainter)
                let sig = 0.4 * exp(-age / 14.0) * exp(-max(time - PL_HIT, 0.0) / 10.0) * fade * thin * (1.0 - gone);
                let dtau = sig * prof * dens * 1.6 * rad * gin;
                // (lit on its sunward side and on its lumps' tops, darker in its creases)
                let axis = pa_ + ab * sz;
                let nrm = normalize(cp - axis - rd * (0.6 * rad) + vec3<f32>(0.0, 1.0e-4, 0.0));
                let ln = 0.5 + w1 * (n1 - 0.5);
                let lit = (0.35 + 0.65 * saturate(dot(nrm, L) * 0.5 + 0.5)) * (0.6 + 0.8 * ln * ln);
                // (grey-brown smoke, paler as it spreads thin; the vapour high up a pale grey)
                var alb = mix(vec3<f32>(0.74, 0.75, 0.78), vec3<f32>(0.17, 0.145, 0.125), smk);
                alb = mix(alb, alb * 1.35 + vec3<f32>(0.03), smoothstep(4.0, 20.0, age));
                var c = alb * (sunc * lit * 0.85 + amb * (0.6 + 0.4 * ln));
                // (just behind the head it is lit by the flame: orange, dying back within a second)
                c = c + vec3<f32>(1.9, 0.75, 0.22) * exp(-age / 0.12) * dive * step(time, PL_HIT + 0.3) * (0.4 + 0.6 * ln);
                // (in the re-entry, lit from within by the glowing air just behind the head)
                c = c + vec3<f32>(2.2, 0.9, 0.35) * exp(-age / 0.35) * heat * (0.5 + 0.5 * ln);
                // (farther, the air between greys it to the sky)
                c = mix(c, haze_c, (1.0 - exp(-tn / 3000.0)) * 0.75);
                tc = tc + c * dtau;
                tau = tau + dtau;
                // (the flame tail just behind the head, in the dive)
                // (how far off its axis the ray passes within this piece: where it is nearest, or at the piece's end
                // it leaves by, so the glow runs on smoothly from piece to piece)
                let gx = length(rd * tn - axis);
                let chord = 2.0 * sqrt(max(rad * rad - gx * gx, 0.0));
                let fl = dive * exp(-age / 0.13) * step(time, PL_HIT + 0.05);
                // (soft-edged, a teardrop narrowing back from the head, white-yellow at its root, orange back along it)
                let fw = rad * (0.75 - 0.35 * saturate(age / 0.3));
                let fprof = exp(-pow(gx / max(fw, 0.5), 2.0) * 1.6) * min(fw * 0.5, 1.0);
                glow = max(glow, mix(vec3<f32>(3.2, 1.0, 0.18), vec3<f32>(4.0, 2.6, 1.0), exp(-age / 0.06)) * fl * 1.6 * fprof);
                // (high up, the hot streak of air it leaves glowing behind it, white, cooling within a second)
                // (the re-entry's: the ionised air it leaves glowing behind it, white-yellow cooling through orange to a
                // dull pink within a second, a core narrower than the smoke)
                // (the rod's ionised line: from the head back, white-blue, cooling to a faint violet within a second;
                // never thinner than a pixel, so it reads from any distance)
                let fh = (exp(-age / 0.35) + 0.25 * exp(-age / 1.4)) * (1.0 - smoothstep(PL_HIT, PL_HIT + 0.6, time));
                let gr = max(0.9 + 0.5 * dv, tn * px_a * 0.8);
                let gch = exp(-gx * gx / (gr * gr) * 1.5) * min((0.9 + 0.5 * dv) / gr, 1.0);
                let gcol = mix(mix(vec3<f32>(0.55, 0.35, 0.9), vec3<f32>(1.6, 1.5, 2.6), exp(-age / 0.3)), vec3<f32>(3.4, 3.4, 3.6), exp(-age / 0.08));
                glow = max(glow, gcol * fh * gch * 1.6);
            }
        }
        if (tau > 0.0) {
            let al = 1.0 - exp(-tau);
            if (stage == 0u) {
                col = mix(col, tc / tau, al * k);
            } else {
                pl_over(&hc, tc / tau, al * k);
            }
        }
        if (stage == 0u) {
            col = col + glow * k;
        } else {
            hc = vec4<f32>(hc.rgb + glow * k, hc.a);
        }
    }

    // ---- the pieces it sheds coming in: glowing chunks flung off to the side, falling away behind it, burning out
    // over a second or three, each trailing its own thin smoke; in the last seconds a spray of sparks off the fireball --
    if (have && time > PL_SEEN && time < PL_HIT + 7.0) {
        let nf = min(i32(pl_w(7u) + 0.5), 32);
        var ftau = 0.0;
        var ftc = vec3<f32>(0.0);
        var fglow = vec3<f32>(0.0);
        for (var f = 0; f < nf; f = f + 1) {
            let b = PL_FR + PL_FW * u32(f);
            let t0 = pl_w(b);
            let s = time - t0;
            let life = pl_w(b + 1u);
            // (gone, glow and smoke, three and a half seconds after it burns out: nothing more looked up for it)
            if (s <= 0.0 || s > life + 3.6) {
                continue;
            }
            let size = pl_w(b + 2u);
            let spark = pl_w(b + 3u) > 0.5;
            let kd = max(pl_w(b + 4u), 0.05);
            let p0 = vec3<f32>(pl_w(b + 5u), pl_w(b + 6u), pl_w(b + 7u)) + C;
            let v0 = vec3<f32>(pl_w(b + 8u), pl_w(b + 9u), pl_w(b + 10u));
            if (stage != 1u && s < life) {
                // (the glowing piece, smeared over the last few hundredths of a second it moved: a short streak)
                let pa = pl_frag(p0, v0, kd, s);
                let pb = pl_frag(p0, v0, kd, max(s - select(0.03, 0.05, spark), 0.0));
                let h = ray_seg(rd, pa, pb);
                // (in the join, hidden behind the column, which the half-size stage drew)
                if (h.y < select(scene_len + 2.0, min(scene_len + 2.0, up_t), stage == 2u)) {
                    let w = max(size, h.y * px_a * 0.8);
                    let e = min(size / w, 1.0);
                    let u = s / life;
                    let hot = select(mix(vec3<f32>(4.0, 2.3, 1.0), vec3<f32>(2.6, 0.75, 0.12), u), vec3<f32>(4.0, 3.2, 1.8), spark);
                    let fl = 0.75 + 0.25 * sin(time * 41.0 + f32(f) * 2.3);
                    fglow = fglow + hot * (exp(-pow(h.x / w, 2.0)) * 3.0 + 0.25 * exp(-h.x / (w * 4.0))) * e * e * (1.0 - u * u) * fl;
                }
            }
            if (stage != 2u && !spark) {
                // (its smoke: laid where it was while it burned, swelling and thinning after)
                let s_hi = min(s, life);
                let s_lo = max(s - 3.5, 0.0);
                let qe = pl_frag(p0, v0, kd, s_hi);
                let qs = pl_frag(p0, v0, kd, s_lo);
                let cq = 0.5 * (qs + qe);
                let rq = 0.75 * length(qe - qs) + 2.0 * size * (0.6 + 1.1 * sqrt(s - s_lo)) + 3.0;
                let tq = max(dot(cq, rd), 0.0);
                if (s_hi > s_lo && length(cq - rd * tq) < rq && tq - rq < scene_len) {
                    var qa = qs;
                    for (var j = 1; j <= 8; j = j + 1) {
                        let sj = s_lo + (s_hi - s_lo) * f32(j) / 8.0;
                        let qb = pl_frag(p0, v0, kd, sj);
                        let h = ray_seg(rd, qa, qb);
                        let age = s - (sj - (s_hi - s_lo) / 8.0 * (1.0 - h.z));
                        let rad = size * (0.6 + 1.1 * sqrt(age));
                        if (h.x < rad * 2.0 && h.y < scene_len + rad && (h.z < 0.9999 || j == 8)) {
                            let cp = rd * h.y;
                            // (from the target, not the world's origin: see the trail's lumps)
                            let nb = gnoise3((cp - C) / (2.5 * rad + 1.0) + vec3<f32>(f32(f) * 7.1, 0.0, 0.1 * age));
                            let prof = exp(-pow(h.x / (rad * (0.5 + nb)), 2.0) * 1.4);
                            let dens = saturate((nb - 0.18 - 0.25 * smoothstep(0.5, 3.5, age)) * 3.0);
                            let dtau = 0.5 * exp(-age / 1.8) * prof * dens * 1.6 * rad * fade;
                            var c = vec3<f32>(0.45, 0.43, 0.4) * (sunc * 0.75 + amb * 0.8);
                            c = c + vec3<f32>(1.6, 0.6, 0.15) * exp(-age / 0.1) * step(s, life);
                            c = mix(c, haze_c, (1.0 - exp(-h.y / 3000.0)) * 0.75);
                            ftc = ftc + c * dtau;
                            ftau = ftau + dtau;
                        }
                        qa = qb;
                    }
                }
            }
        }
        if (ftau > 0.0) {
            if (stage == 0u) {
                col = mix(col, ftc / ftau, (1.0 - exp(-ftau)) * k);
            } else {
                pl_over(&hc, ftc / ftau, (1.0 - exp(-ftau)) * k);
            }
        }
        col = col + fglow * k * fade;
    }

    // (how far off the cloud stands along this ray, where it is mostly opaque: the dust and debris behind it hidden)
    var col_t = select(1.0e9, up_t, stage == 2u);
    // (the cloud stands on the ground under the burst, Cb: its C)
    {
    let C = Cb;
    // ---- the column of dust: raymarched, self-shadowed towards the sun, its foot glowing for a moment -----------------
    // (the rock the impact melted and threw up glowing white-hot for a moment at the column's foot, orange for a second)
    let heat = exp(-a / 0.25);
    let glow = exp(-a / 0.6);
    if (stage != 2u && have && a > 0.0) {
        var cl = pl_column(a, C);
        // (first a cheap bound: a fat stick from under the land up to the cap's core circle, leaning with the wind, as
        // wide as the cap's rim and its lumps; its rounded top holds the dome. Its top at the core's height, not over
        // the cap: from a point higher up the rim's lumps lie further off than the rim's radius, and were cut off)
        let ctop = C + vec3<f32>(0.0, cl.hc, 0.0) + pl_wind() * a;
        let cbound = pl_ray_seg(rd, C - vec3<f32>(0.0, 20.0, 0.0), ctop, 0.0, 1.0);
        let crad = max(max(cl.sr.z, cl.rt), cl.surge.x + cl.surge.y) + PL_DM + 30.0 + 0.2 * length(pl_wind()) * a;
        let tb = pl_box(rd, cl.lo, cl.hi);
        let t1 = min(tb.y, scene_len);
        if (cbound.x < crad && t1 > tb.x) {
            var t = tb.x;
            var tr = 1.0;
            var acc = vec3<f32>(0.0);
            let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
            let ph = 0.8 + (0.5 + 1.6 * warm) * pow(saturate(dot(rd, L)), 5.0);
            let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
            let thin = exp(-max(a - PL_SOFT0 - 12.0, 0.0) / 7.0);
            var tmid = 0.0;
            var wmid = 0.0;
            var nl = 0;
            var lc_face = 0.0;
            var lc_bulk = 1.0;
            var sky_occ = 0.0;
            // (how far up a lump where the ray first meets the smoke: its glow and its soot are the surface's, not each
            // step's deeper in, whose lumps cut in slices would show as rings)
            var em_y = 0.5;
            var em_k = 0.0;
            // (pulverised earth and rock: grey-brown, paler and greyer up the column where the fine dust is, paler as it
            // spreads)
            let sootc = mix(vec3<f32>(0.48, 0.45, 0.41), vec3<f32>(0.58, 0.56, 0.52), smoothstep(10.0, 40.0, a));
            for (var i = 0; i < 96; i = i + 1) {
                if (t > t1 || tr < 0.04) {
                    break;
                }
                let p = rd * t;
                let b2 = pl_col_base2(&cl, p);
                let d0 = b2.x;
                let dr = b2.y;
                let db = min(d0, dr);
                // (far from it, a long step: the body's distance is up to 1.6 times too long under the cap's roll)
                if (db > PL_DM + 14.0) {
                    t = t + (db - PL_DM - 4.0) * 0.52;
                    continue;
                }
                let st = max(7.5, t * 0.012) * (0.75 + 0.5 * j);
                var den = 0.0;
                var ringw = 0.0;
                var sd = vec4<f32>(d0, 0.5, 4.0, 0.5);
                // (deep inside, past where any lump could reach, it is smoke whatever the lumps: none looked up)
                if (d0 < -PL_DM - 6.0) {
                    sd = vec4<f32>(d0, 0.45, 4.0, 0.5);
                    den = thin;
                } else if (d0 < PL_DM + 4.0) {
                    sd = pl_col_sdf(&cl, p, d0, true);
                    let ramp = saturate(-sd.x / (sd.z + 40.0 * soft));
                    den = ramp * mix(saturate(0.15 + 1.7 * sd.w), 1.0, ramp * ramp) * thin;
                }
                // (the ring: thin and white, its edge soft)
                if (dr < 12.0) {
                    // (wispy: torn into strands and gaps by two sizes of noise, soft through its whole depth)
                    let rn = gnoise3((p + cam) * (1.0 / 7.0) + vec3<f32>(0.0, 0.0, 0.15 * a));
                    let rb = gnoise3((p + cam) * vec3<f32>(1.0 / 40.0, 1.0 / 14.0, 1.0 / 40.0) + vec3<f32>(3.0, 0.0, 0.05 * a));
                    let rd0 = saturate((-dr + 12.0 * (rn - 0.5)) / 14.0) * smoothstep(0.3, 0.7, rb) * cl.ring.z * 0.12;
                    ringw = rd0 / max(rd0 + den, 1.0e-4);
                    den = den + rd0;
                }
                // (the base surge's dust thinner than the cloud's smoke: the land shows through it in places)
                let sw = (1.0 - smoothstep(25.0, 70.0, p.y - C.y)) * smoothstep(0.8 * cl.sr.x, 1.6 * cl.sr.x, length((p - C).xz));
                den = den * (1.0 - 0.7 * sw);
                if (soft > 0.0 && den > 0.002) {
                    let mt = gnoise3((p + cam) * (1.0 / 20.0) - pl_wind() * (a * 0.09) + vec3<f32>(0.0, -0.05 * a, 0.0));
                    den = den * mix(1.0, saturate(0.2 + 1.6 * mt), soft);
                }
                if (den > 0.002) {
                    if (nl == 0) {
                        em_y = sd.y;
                        // (soot in broken patches over the creases between its lumps, carried with the cloud: not rings)
                        let qs = p - C - pl_lean(&cl, p.y - C.y);
                        em_k = smoothstep(0.42, 0.68, gnoise3(qs * (1.0 / 48.0) + vec3<f32>(2.3, -0.03 * a, 5.1)));
                    }
                    if (nl == 0 || (tr > 0.3 && nl % 3 == 0)) {
                        let fp = p + L * 9.0;
                        lc_face = pl_col_sdf(&cl, fp, pl_col_base2(&cl, fp).x, false).x - sd.x;
                        let s1 = saturate((10.0 - pl_col_base(&cl, p + L * 20.0)) / 34.0);
                        let s2 = saturate((10.0 - pl_col_base(&cl, p + L * 55.0)) / 46.0);
                        let s3 = saturate((8.0 - pl_col_base(&cl, p + L * 120.0)) / 60.0);
                        lc_bulk = exp(-(s1 * 10.0 + s2 * 18.0 + s3 * 22.0) * 0.3);
                        // (the sky's light shut out from under the cap and deep in it: what lies under more of it
                        // darker, its tops lit)
                        sky_occ = saturate((12.0 - pl_col_base(&cl, p + vec3<f32>(0.0, 80.0, 0.0))) / 70.0);
                    }
                    nl = nl + 1;
                    let lam = mix(saturate(0.25 + lc_face / 7.0), 0.65, soft);
                    // (the ring, out from under the cap's edge, catches more of the sun than the stem in its shadow)
                    // (under the cap, the stem, the surge and the ring in its shadow)
                    let capsh = pl_cap_shade(p, L, a, C, cl.hc - 0.3 * cl.rt, cl.Rt + cl.rt);
                    let tsun = max(mix(lc_bulk, 0.7, soft) * lam * capsh, 0.45 * ringw * capsh);
                    let hy = saturate((p.y - C.y) / max(cl.hc + cl.rt, 1.0));
                    let deep = saturate(-d0 / 70.0);
                    let ao = mix((0.55 + 0.45 * sd.y) * (1.0 - 0.6 * deep) * (1.0 - 0.6 * sky_occ), 0.75, soft);
                    let kb = em_k * saturate(1.5 - 1.6 * em_y);
                    let mv = (0.9 + 0.2 * (sd.w - 0.5) + 0.25 * (sd.y - 0.5)) * (1.0 - 0.35 * kb);
                    // (earthy brown low down, its pulverised rock grey-brown up the column)
                    var alb = mix(vec3<f32>(0.37, 0.33, 0.28), sootc, smoothstep(0.05, 0.5, hy)) * mv;
                    alb = mix(alb, vec3<f32>(0.85, 0.86, 0.88), ringw);
                    // (the surge's dust darker and browner than the cloud: earth, not smoke)
                    alb = alb * (1.0 - 0.3 * sw);
                    let skyg = mix(mix(skyl, vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.45), fogl, 0.15) * (1.0 - 0.35 * warm);
                    // (lifted as the fire goes out: the smoke's light scattered about inside it, so its shadowed side is grey-brown,
                    // not charcoal; while it burns, its own glow is most of its light)
                    let lift = 1.0;
                    var c = alb * ((skyg * (mix(0.48, 0.75, lift) * ao * (0.35 + 0.65 * hy)) + mix(vec3<f32>(0.2, 0.17, 0.13), vec3<f32>(0.3, 0.26, 0.2), lift) * day * (1.0 - 0.6 * warm) * ao) * mix(0.55, 1.0, capsh) + sunc * vec3<f32>(0.95, 0.85, 0.72) * (1.05 * tsun * ph));
                    // (its foot lit from inside for a moment by the rock the impact melted: white-hot, then orange, gone
                    // within a couple of seconds; at night it shows a little longer)
                    let low = exp(-max(p.y - C.y, 0.0) / (12.0 + 10.0 * a));
                    let en = (heat * 6.0 + glow * 0.5) * low * (1.0 + 0.8 * (1.0 - day)) * (0.4 + 0.6 * (1.0 - sd.y));
                    let tcol = mix(vec3<f32>(2.6, 0.9, 0.25), vec3<f32>(3.4, 3.2, 3.0), heat);
                    c = c * (1.0 - saturate(en * 0.8)) + tcol * en * 0.6;
                    let ext = den * 0.32 * st;
                    let al = 1.0 - exp(-ext);
                    acc = acc + tr * al * c;
                    tmid = tmid + tr * al * t;
                    wmid = wmid + tr * al;
                    tr = tr * (1.0 - al);
                }
                t = t + select(st, max(0.55 * min(sd.x, dr), (0.12 * st + 0.25) * min(1.0 + 0.06 * f32(i), 2.5)), min(sd.x, dr) > 0.0);
            }
            if (tr < 0.999) {
                let dist = tmid / max(wmid, 1.0e-4);
                if (tr < 0.5) {
                    col_t = dist;
                }
                let ap = 1.0 - exp(-dist / 4000.0);
                // (the air's haze over it: thin over the burning ball, whose own light outshines it)
                let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, ap * 0.75);
                if (stage == 0u) {
                    col = mix(col, ccol, (1.0 - tr) * k * fade);
                } else {
                    pl_over(&hc, ccol, (1.0 - tr) * k * fade);
                }
            }
        }
    }
    }
    // ---- the rod: a blinding white-hot point tearing straight down, its plasma sheath drawn out thin behind it, bloom,
    // a lens streak; brighter as it nears ------------------------------------------------------------------------------
    if (stage != 1u && have && time > PL_SEEN - 0.1 && time < PL_HIT + 0.02) {
        let tb = min(time, PL_HIT);
        let H0 = pl_head(tb);
        let Hp = H0 + C;
        let dh = max(length(Hp), 1.0);
        let hn = Hp / dh;
        let cth = dot(rd, hn);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let hp = project_rel(Hp);
        var vis = 1.0;
        if (hp.z > 0.0 && all(hp.xy > vec2<f32>(0.0)) && all(hp.xy < vec2<f32>(1.0))) {
            let dd = depth_at(hp.xy);
            if (!is_sky(dd) && length(world_offset(hp.xy, dd)) < dh - 3.0) {
                vis = 0.0;
            }
        } else if (cth < 0.0) {
            vis = 0.0;
        }
        let show = smoothstep(PL_SEEN - 0.1, PL_SEEN + 0.3, time) * vis * k;
        let vd = normalize(H0 - pl_head(tb - 0.03) + vec3<f32>(0.0, -1.0e-4, 0.0));
        let near = smoothstep(PL_HIT - 1.5, PL_HIT, time);
        let fl = 0.9 + 0.1 * sin(time * 53.0) * sin(time * 31.0 + 1.0);
        let tc0 = max(2.5 / dh, px_a * 0.9);
        let core = exp(-pow(th / tc0, 2.0)) * 20.0;
        let bloom = 1.3 / (1.0 + pow(th / (tc0 * 4.0 + 0.003), 2.0)) + 0.25 * exp(-th / 0.04);
        let lw = 50.0 + 40.0 * near;
        let sg = ray_seg(rd, Hp, Hp - vd * lw);
        let ww = mix(0.9, 3.0, sqrt(sg.z));
        let wpx = max(ww, sg.y * px_a * 0.8);
        let sheath = exp(-pow(sg.x / wpx, 2.0)) * pow(1.0 - sg.z, 1.4) * (ww / wpx) * 5.0;
        let sv = rd - hn * cth;
        let upv = normalize(cross(cross(hn, vec3<f32>(0.0, 1.0, 0.0)), hn) + vec3<f32>(0.0, 1.0e-5, 0.0));
        let streak = exp(-abs(dot(sv, upv)) / (px_a * 1.2)) * exp(-th / 0.05) * 0.35;
        let hot = vec3<f32>(1.0, 0.97, 0.95) * (core + bloom + streak) + mix(vec3<f32>(1.0, 0.95, 0.9), vec3<f32>(0.7, 0.6, 1.1), sqrt(sg.z)) * sheath;
        col = col + hot * fl * show * (1.0 + 0.8 * near);
    }

    // ---- the dust: marched along the view ray where it crosses the shell behind the front, more sparsely inside ------
    if (stage != 2u && a > 0.0 && a < 45.0) {
        let rf = PL_V * a;
        // (the slab the dust stays in: over the land's lowest and highest ground, where the heightfield is in)
        var ylo = min(C.y, me.y) - 6.0;
        var yhi = max(C.y, me.y) + 90.0;
        if (pl_w(PL_HF) > 1.0) {
            ylo = min(ylo, C.y + pl_w(PL_HF + 2u) - 6.0);
            yhi = max(yhi, C.y + pl_w(PL_HF + 3u) + 90.0);
        }
        // (where this pixel's ray meets the land, its own height: the dust right there sits on it, in a hollow
        // smaller than the heightfield's cells or on a rise; a treetop or a wall counts only a little)
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
        // (the ray across the discs out to the front and out to where the wall thins: the shell between)
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
            var ns = array<i32, 3>(16, 0, 0);
            if (din > 0.0 && Ri > 0.0) {
                let ia = (-bb - sqrt(din)) / a2;
                let ib = (-bb + sqrt(din)) / a2;
                seg[0] = vec2<f32>(oa, ia);
                seg[1] = vec2<f32>(ib, ob);
                seg[2] = vec2<f32>(ia, ib);
                ns = array<i32, 3>(12, 10, 6);
            }
            // (how square the ray crosses the ring: along it, at the ring's sides from far off, it would pile up)
            let mid_t = clamp(-bb / a2, t0, t1);
            let pm = rd * mid_t - C;
            let side = saturate(abs(dot(normalize(rd.xz), pm.xz / max(length(pm.xz), 1.0))) * 1.6);
            var tr = 1.0;
            var acc = vec3<f32>(0.0);
            let j = ign(in.position.xy + vec2<f32>(0.0, fract(time * 5.0) * 53.0));
            // (the cap over it, for its shadow on the dust)
            let dcl = pl_column(max(a, 0.01), Cb);
            // (the near crossing, the haze inside, then the far crossing: in the order the ray meets them)
            var order = array<i32, 3>(0, 2, 1);
            for (var si = 0; si < 3; si = si + 1) {
                let k2 = order[si];
                let sa = max(seg[k2].x, t0);
                let sb = min(seg[k2].y, t1);
                let n = ns[k2];
                if (n == 0 || sb <= sa || tr < 0.02) {
                    continue;
                }
                // (closer together near the eye)
                for (var i = 0; i < n; i = i + 1) {
                    let u0 = (f32(i) + j) / f32(n);
                    let u1 = (f32(i) + j + 1.0) / f32(n);
                    let t = sa + (sb - sa) * u0 * u0;
                    let dt = (sb - sa) * (u1 * u1 - u0 * u0);
                    let p = rd * t;
                    let dh = pl_dust(p, C, a, me, dme, side, loc);
                    // (thin right round the eye: the front passing over it would otherwise fill the whole picture with
                    // dust, the sky too; the lens and the air at the eye show it there instead)
                    let den = dh.x * smoothstep(2.0, 30.0, t);
                    if (den <= 0.001) {
                        continue;
                    }
                    let al = 1.0 - exp(-den * dt * 0.3);
                    let h = dh.y;
                    // (its billows lit on top, darker under them and low down)
                    let wq = p + cam;
                    let bl = gnoise3(wq * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a + 0.5, 0.0));
                    let lo = (0.45 + 0.55 * saturate(h / 8.0)) * (0.55 + 0.7 * bl);
                    let dc = vec3<f32>(0.56, 0.49, 0.37) * (sunc * 0.75 * lo * pl_cap_shade(p, L, a, C, dcl.hc - 0.3 * dcl.rt, dcl.Rt + dcl.rt) + amb * 0.6);
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

    // ---- the debris: dark chunks and specks of earth, tumbling as they fly and fall, the big ones trailing smoke ----
    if (stage == 1u) {
        // (whether a piece of the debris still in the air passes near here, a few pixels wider than the join looks for
        // them: the join looks only near those that are; most of the picture has none near it)
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
            // (the middle of the two by two this pixel stands for, in the picture's pixels)
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
                // (as the join looks for it on the screen, three pixels wider)
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
                    // (the first and the last near it: the join looks through those only)
                    near = select(near, f32(i + 1), near == 0.0);
                    near_hi = f32(i + 1);
                }
            }
        }
        // (how far its ray went, and the column's distance, for the join to match its pixels against and hide what lies
        // behind the column; both kept within a half float)
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
        // (below the lowest of the land, a chunk is down: no need to look for the land under it)
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
            // (first a cheap look at how far off this pixel's ray it is, in the world: most are well clear)
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
            // (the smoke a big one trails: a fading wisp along where it flew the last half second)
            let reach = select(rad * 1.4 + length(ch.v) * 0.03 * fpx / dist + 2.0, rad * 3.0 + length(ch.v) * 0.6 * fpx / dist + 4.0, bigc > 0.0);
            if (length(pxy - q0) > reach) {
                continue;
            }
            let s1 = project_rel(ch.p - ch.v * 0.03);
            let q1 = s1.xy * frame.resolution.xy;
            // (a tumbling lump: a capsule along its blur, its outline turning)
            let ab = q1 - q0;
            let w = saturate(dot(pxy - q0, ab) / max(dot(ab, ab), 1.0e-4));
            let e = length(pxy - (q0 + ab * w));
            let spin = a * pl_w(PL_DB + PL_DW * u32(i) + 8u);
            let th = atan2(pxy.y - q0.y, pxy.x - q0.x);
            let lump = 1.0 + 0.28 * sin(th * 3.0 + f32(i) + spin) + 0.12 * sin(th * 5.0 - spin * 1.3);
            let c = saturate(rad * lump + 0.5 - e) * ch.live * saturate(rad / max(length(ab) * 0.5, rad));
            cov = max(cov, c);
            if (bigc > 0.0) {
                let s2 = project_rel(ch.p - ch.v * 0.6 + vec3<f32>(0.0, 1.2, 0.0));
                let q2 = s2.xy * frame.resolution.xy;
                let tb = q2 - q0;
                let u = saturate(dot(pxy - q0, tb) / max(dot(tb, tb), 1.0e-4));
                let wd = rad * (0.6 + 1.6 * u) + 0.5;
                let et = length(pxy - (q0 + tb * u));
                smk = max(smk, saturate(1.0 - et / wd) * (1.0 - u) * 0.45 * bigc * ch.live * step(0.5, s2.z));
            }
        }
        let dirt = vec3<f32>(0.06, 0.055, 0.05) * (amb * 1.5 + sunc * 0.35);
        let smoke = vec3<f32>(0.28, 0.29, 0.31) * (amb * 0.8 + sunc * 0.25);
        col = mix(col, smoke, smk * k * fade);
        col = mix(col, dirt, cov * k * fade);
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
                * (1.0 - 0.55 * land.y) * fade * k;
            if (E > 0.002) {
                let dust_c = vec3<f32>(0.5, 0.46, 0.4) * (sunc * 0.55 + amb * 0.8);
                // (the air thick with it: contrast lost, greyed and a little warmed)
                let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
                col = mix(col, mix(vec3<f32>(lum), dust_c, 0.5), 0.22 * E);
                col = col * mix(vec3<f32>(1.0), vec3<f32>(1.03, 0.99, 0.93), E);
                // (a faint film of it on the lens, in soft blotches, fixed to the screen)
                let pxy = pl_px;
                let res = frame.resolution.xy;
                // (as out of focus as the drops: broad, soft-edged, no fine grain)
                let film = gnoise3(vec3<f32>(pxy / (0.15 * res.y), 3.1)) * 0.8 + gnoise3(vec3<f32>(pxy / (0.07 * res.y), 7.7)) * 0.2;
                col = mix(col, dust_c, 0.12 * E * smoothstep(0.35, 0.95, film));
            }
            // (muck thrown on the lens as the front passes, far out of focus, as the second clip shows it: drops near
            // round but each its own, a few drawn out into soft streaks, 2 to 7% of the picture's height across, blurred
            // discs a touch denser towards the rim, feathered over their outer half with no outline, faintly mottled and
            // faintly lit on the side the light comes from; some faint, some strong (letting through 55 to 90% of the light),
            // grey; often with a smaller drop or two beside them; nearly all high on the screen; landing over the second
            // after the front, staying a long while)
            let vis = smoothstep(60.0, 10.0, hc) * smoothstep(6000.0, 2500.0, rc) * smoothstep(120.0, 260.0, rc) * (1.0 - 0.5 * land.y) * k;
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
                    // (the drop and up to three smaller ones round it, each its own size, stretch, turn and strength)
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
                        // (stretched along its own turn: the big ones hardly, the small ones up to twice as long)
                        let rot = TAU * mh(k2, seed, 0x3e4u);
                        let cr = cos(rot);
                        let sr = sin(rot);
                        let stretch = 1.0 + mix(0.4, 0.06, smoothstep(0.012, 0.03, rj / res.y)) * 2.0 * mh(k2, seed, 0x3e5u);
                        let e = vec2<f32>((dj.x * cr + dj.y * sr) / stretch, -dj.x * sr + dj.y * cr);
                        let th = atan2(e.y, e.x);
                        let ph = TAU * mh(k2, seed, 0x3e6u);
                        // (an edge a little uneven)
                        let q = length(e) / rj * (1.0 + 0.05 * sin(3.0 * th + ph) + 0.035 * sin(5.0 * th - 2.0 * ph));
                        if (q >= 1.4) {
                            continue;
                        }
                        // (a defocused disc: feathered from under half its radius out past its edge, a little denser
                        // towards the rim, its mottling blurred to a faint unevenness)
                        let body = 1.0 - smoothstep(0.3, 1.38, q);
                        let ring = body * mix(0.9, 1.15, smoothstep(0.1, 0.8, q));
                        let mott = 0.94 + 0.12 * gnoise3(vec3<f32>(e / (0.8 * rj), f32(k2 % 97u)));
                        let op = (0.14 + 0.34 * pow(mh(k2, seed, 0x3e7u), 0.7)) * select(0.85, 1.0, j == 0u);
                        keep = keep * (1.0 - ring * mott * op * life);
                        // (and the light caught in it, faintly, on its upper side)
                        shine = shine + body * smoothstep(0.3, -0.9, dj.y / rj) * op * life;
                    }
                }
                // (muck, not shade: the drops scatter the light as well as stopping it, a dusty grey-brown veil)
                let muck = vec3<f32>(0.42, 0.38, 0.33) * (sunc * 0.45 + amb * 0.9);
                col = mix(col, col * keep + muck * (1.0 - keep) * 0.7, vis * fade) + muck * 0.4 * min(shine, 1.0) * vis * fade;
            }
        }
    }

    // ---- the impact frames: for a split second as it strikes, a few stark stylised frames (white; the scene in black
    // and white silhouettes with jagged impact lines bursting from the point; its negative, the lines red; black and
    // white again, split in colour), then the picture as it was (rd_impact; `/orbital impactframes off` leaves them out)
    if (stage != 1u && a > -0.004 && a < RD_IF_END && frame.mod_params[3].w < 1.5) {
        col = rd_impact(col, uv, a, Cb, seed);
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
// The anime technique: for a split second as it strikes, the picture cuts to a few stark frames, timed by the strike's
// clock (so they hold at any frame rate), each beat two or three frames at 60 a second. RD_IF: when each beat ends.
const RD_IF0: f32 = 0.034;         // 0: pure white, the impact point a tiny black core (and the picture punched in)
const RD_IF1: f32 = 0.084;         // 1: black silhouettes on white, black impact lines bursting from the point
const RD_IF2: f32 = 0.134;         // 2: the negative: white silhouettes on black, the lines red
const RD_IF_END: f32 = 0.168;      // 3: black on white again, split in colour; then the picture
// The impact point on the screen (uv), and the picture's aspect.
fn rd_if_point(Cb: vec3<f32>) -> vec2<f32> {
    let p = project_rel(Cb + vec3<f32>(0.0, 2.0, 0.0));
    // (behind the eye: from the middle of the screen's edge nearest it, as a burst from off the screen)
    return select(vec2<f32>(0.5, 1.2) + (vec2<f32>(0.5) - p.xy) * 0.0, p.xy, p.z > 0.0);
}
// The scene's silhouette at uv: 1 where it is bright or far (the sky, the distance, what is lit), 0 where it is near
// and dark (the land and what stands on it close by); the impact's own burst white round the point.
fn rd_if_mask(uv: vec2<f32>, P: vec2<f32>, asp: f32, a: f32) -> f32 {
    let d = depth_at(uv);
    var v = 1.0;
    if (!is_sky(d)) {
        let len = length(world_offset(uv, d));
        let c = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
        let lum = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
        v = 0.55 * lum / (lum + 0.12) + 0.75 * smoothstep(250.0, 1400.0, len);
    }
    let q = (uv - P) * vec2<f32>(asp, 1.0);
    let r = length(q);
    // (the burst: a ragged white star round the point, growing beat by beat)
    let th = atan2(q.y, q.x);
    let star = 0.05 + 0.04 * a / RD_IF_END + 0.025 * sin(th * 7.0 + 1.3) * sin(th * 11.0 + 0.4);
    v = v + 1.5 * (1.0 - smoothstep(star * 0.8, star, r));
    let px = 1.5 / frame.resolution.y;
    return smoothstep(0.55 - px * 40.0, 0.55 + px * 40.0, v);
}
// The impact lines at uv for beat `b`: thin, jagged wedges bursting out from the point, each its own width and start,
// a new set each beat. 1 on a line.
fn rd_if_lines(uv: vec2<f32>, P: vec2<f32>, asp: f32, b: u32, seed: u32) -> f32 {
    let q = (uv - P) * vec2<f32>(asp, 1.0);
    let r = max(length(q), 1.0e-4);
    let n = 84.0;
    let th = atan2(q.y, q.x) / TAU + 0.5;
    // (jagged: each line bent back and forth along its length)
    let u0 = th * n;
    let id0 = floor(u0);
    let hj = mh(u32(id0) + 977u * b, seed, 0x4c1u);
    let z1 = abs(fract(r * (5.0 + 4.0 * hj) + hj * 7.0) - 0.5) * 2.0 - 0.5;
    let z2 = abs(fract(r * 17.0 + hj * 3.0) - 0.5) * 2.0 - 0.5;
    let jag = 0.22 * z1 + 0.07 * z2;
    let u = u0 + jag * smoothstep(0.0, 0.2, r);
    let id = floor(u);
    let k = u32(i32(id) + 1000) + 977u * b;
    let h1 = mh(k, seed, 0x4c2u);
    let h2 = mh(k, seed, 0x4c3u);
    let h3 = mh(k, seed, 0x4c4u);
    if (h2 < 0.3) {
        return 0.0;
    }
    // (starting a way out from the point, thin there and widening outward, past the screen's edge)
    let r0 = 0.07 + 0.32 * h3 * h3;
    let w = (0.04 + 0.3 * h1 * h1 * h1) * smoothstep(r0, r0 + 0.3, r);
    let f = abs(fract(u) - 0.5);
    // (a pixel's width across the line, for a clean edge)
    let px = (1.0 / frame.resolution.y) / r * n / TAU;
    return (1.0 - smoothstep(w * 0.5 - px, w * 0.5 + px, f)) * step(r0, r);
}
fn rd_impact(col: vec3<f32>, uv0: vec2<f32>, a: f32, Cb: vec3<f32>, seed: u32) -> vec3<f32> {
    let asp = frame.resolution.x / frame.resolution.y;
    let P = rd_if_point(Cb);
    let uv = uv0;
    let q = (uv - P) * vec2<f32>(asp, 1.0);
    let r = length(q);
    if (a < RD_IF0) {
        // (pure white, the point a tiny black core)
        let core = 1.0 - smoothstep(0.008, 0.011, r);
        return vec3<f32>(1.0 - core);
    }
    if (a < RD_IF1) {
        let m = rd_if_mask(uv, P, asp, a);
        let l = rd_if_lines(uv, P, asp, 1u, seed);
        let v = abs(m - l);
        return vec3<f32>(v);
    }
    if (a < RD_IF2) {
        // (the negative: what was white black, the land white, the lines a hot red)
        let m = rd_if_mask(uv, P, asp, a);
        let l = rd_if_lines(uv, P, asp, 2u, seed);
        let base = vec3<f32>(1.0 - m) * vec3<f32>(1.0, 0.93, 0.9);
        return mix(base, vec3<f32>(1.0, 0.07, 0.04), l);
    }
    // (black on white again, its lines anew, the picture split in colour out from the point)
    let ca = normalize(q + vec2<f32>(1.0e-5)) * vec2<f32>(1.0 / asp, 1.0) * 0.007;
    let mr = rd_if_mask(uv + ca, P, asp, a);
    let mg = rd_if_mask(uv, P, asp, a);
    let mb = rd_if_mask(uv - ca, P, asp, a);
    let l = rd_if_lines(uv, P, asp, 3u, seed);
    return vec3<f32>(abs(mr - l), abs(mg - l), abs(mb - l));
}

// ---- the jolt on the picture: the game's camera shake (rod.rs's rd_jolt) tops out at a few degrees, so as the
// shockwave reaches the player the picture itself is knocked about too: a hard, sharp hit, ringing out fast, then a
// shudder dying away over five seconds or so; hardest within a couple of hundred blocks. Shifted and turned a little
// and zoomed in just enough that no edge shows. And on the impact frames' first beats the picture punched in hard on
// the impact point. The lens's own marks stay put (pl_px). ---------------------------------------------------------
var<private> pl_px: vec2<f32>;
fn pl_jolt(in: StageIn) -> StageIn {
    pl_px = in.position.xy;
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    var o = in;
    let ai = now() - PL_HIT;
    if (ai > 0.0 && ai < RD_IF_END && frame.mod_params[3].w < 1.5 && intensity_v() > 0.0) {
        // (the punch: in by a sixth at once, easing back over the beats)
        let C = vec3<f32>(anchor_xz().x, block_y() + 1.0, anchor_xz().y) - frame.camera_position.xyz;
        let P = clamp(rd_if_point(C), vec2<f32>(0.2), vec2<f32>(0.8));
        let z = 1.0 + 0.16 * exp(-ai / 0.06);
        o.uv = P + (in.uv - P) / z;
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
