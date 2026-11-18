// Orbital Laser's post pass for the Six Stars (laser 22). The mod builds it from shaders/strike.wgsl up to its fs_main
// (the helpers) less the other lasers' own functions, followed by this file, and sets it for a Six Stars strike only.
// Validate with tools/check-shader.sh.

// ---- laser 22: the six stars ----------------------------------------------------------------------------------------
// A wanted level climbs: six stars light one by one at the top right of the screen, each on a heavy beat, and the whole
// sky turns to a hazy golden-hour sunset with them, the sun swelling a step with each star, the land shimmering in the
// heat. The sixth peels out of its slot,
// gains thickness, turns over and goes out into the sky at the same size on the screen, so only the land it passes
// behind says how big it is; it hangs high over the target, then falls, a star of cracked white blocks, white-hot
// through its cracks, its edges burning violet to magenta to orange, shedding burning blocks, smoke behind it. It
// strikes: a dirty fireball and a column of black and brown smoke boiling up (the Payload's column, larger), the dust of
// the front racing out over the land, earth thrown; its five points break off and plough out over the land, each
// cutting a burning trench. strike/sixstars.rs samples the path, the billows and the pieces it sheds into the table
// (ss_table, render.set-data): keep the PL_* and SS_* in step.
const PL_SEEN: f32 = 11.8;         // its trail from as it starts to fall (SS_DROP),
const PL_TURN: f32 = 13.5;         // flame behind it from about here,
const PL_HIT: f32 = 17.0;          // and it strikes
const PL_LEN: f32 = 58.0;          // the strike's length (lasers.rs): everything fades out over its last PL_FADE
const PL_FADE: f32 = 7.0;
const PL_SOFT0: f32 = 14.0;        // the column keeps its crisp billows this long after the strike, then loses them
const PL_SOFT1: f32 = 24.0;
const SS_SMOKE_GONE: f32 = 33.0;   // and is gone this long after it strikes (its last wisps under a hundredth: not marched)        // by this, a soft, drifting, widening haze thinning away
const PL_V: f32 = 343.0;           // the shockwave's front, blocks a second
const PL_P: u32 = 24u;             // the table: the path's samples from PL_P, three words each,
const PL_PF: u32 = 416u;           // the billows from PL_PF, PL_PW words each
const PL_PW: u32 = 8u;
const PL_HF: u32 = 2048u;          // the land's heightfield (sixstars.rs's ss_hf_*): its size, then heights, shelter
const PL_FR: u32 = 560u;           // the burning blocks it sheds (sixstars.rs's ss_fragments), PL_FW words each
const PL_FW: u32 = 12u;
const PL_NPUFF: i32 = 18;
const PL_DEBRIS: i32 = 120;
const PL_DB: u32 = 12288u;         // the debris (sixstars.rs's ss_debris_words), PL_DW words each
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

// ---- the column: billows rising out of the strike, each a ball grown and lifted over time -----------------------
struct PlCol {
    n: i32,
    lo: vec3<f32>,
    hi: vec3<f32>,
    grow: f32,
    a: f32,
    C: vec3<f32>,
    // (the billows where they are this frame: worked out once a pixel, not at every step)
    // (packed as half floats, from C: it keeps the march's registers free; half a block is lost at most)
    q: array<vec2<u32>, 18>,
    // (the stem: a trunk from the ground to the stem's highest billow (s1, radius s1.w), s0.w its radius at the foot,
    // so it stands as one ragged mass and not a stack of balls)
    s0: vec4<f32>,
    s1: vec4<f32>,
    // (and the low, wide skirt it stands in, sunk in the crater and merging with the dust: its middle and radius
    // across, 13 high)
    sk: vec4<f32>,
    // (the five trenches' smoke, part of the same body so it is the same smoke: each a tapering roll from by the column
    // (its foot `ln.x` out, radius `lr.x`, its axis `lr.z` up) out to just behind its point (`ln.y` out, `lr.y`, `lr.w`
    // up); none when lr.x is 0)
    ln: vec2<f32>,
    lr: vec4<f32>,
    // (each roll's ground at its foot, its middle and its end (from the target's): it follows the land, hugging it)
    lh: array<vec4<f32>, 5>,
}
// Billow i at `a` seconds after the strike: its middle and radius (w; 0 before it is launched).
fn pl_puff(i: i32, a: f32, C: vec3<f32>, grow: f32) -> vec4<f32> {
    let b = PL_PF + PL_PW * u32(i);
    let s = a - pl_w(b);
    if (s <= 0.0) {
        return vec4<f32>(C, 0.0);
    }
    let H = pl_w(5u) * (1.0 + 0.006 * a);
    let tau = pl_w(b + 1u);
    let rise = 1.0 - exp(-s / tau);
    // (swollen fast as it bursts out, then swelling slowly on)
    let r = pl_w(b + 3u) * (0.22 + 0.78 * (1.0 - exp(-s / (0.45 * tau)))) * grow;
    let h = 5.0 + pl_w(b + 2u) * H * rise;
    // (its foot planted over the crater: the low billows drawn in on the axis, off it more the higher they climb;
    // the wind leans the column over from the ground up, its foot staying put and its head carried furthest)
    let foot = saturate((h - 5.0) / (0.45 * H));
    let spread = (0.35 + 0.65 * rise) * (0.15 + 0.85 * foot * foot);
    let c = C + vec3<f32>(pl_w(b + 4u) * spread, h, pl_w(b + 5u) * spread) + pl_wind() * (a * pow(saturate(h / H), 1.6));
    return vec4<f32>(c, r);
}
fn pl_column(a: f32, C: vec3<f32>) -> PlCol {
    var o: PlCol;
    o.n = 0;
    o.lo = C;
    o.hi = C;
    o.a = a;
    o.C = C;
    o.s1 = vec4<f32>(C, 0.0);
    o.grow = 1.0 + 0.012 * max(a - 6.0, 0.0) + 0.006 * max(a - PL_SOFT0, 0.0);
    for (var i = 0; i < PL_NPUFF; i = i + 1) {
        var q = pl_puff(i, a, C, o.grow);
        // (the stem's billows smaller: its trunk carries it, they only bulge it; the lowest sunk into the crater, so
        // none of them sits on the ground as a ball)
        q.w = q.w * select(1.0, 0.8, i < 5);
        q.y = q.y - 12.0 * (1.0 - smoothstep(10.0, 70.0, q.y - C.y));
        o.q[i] = vec2<u32>(pack2x16float(q.xy - C.xy), pack2x16float(vec2<f32>(q.z - C.z, q.w)));
        if (q.w <= 0.0) {
            continue;
        }
        o.lo = min(o.lo, q.xyz - vec3<f32>(q.w));
        o.hi = max(o.hi, q.xyz + vec3<f32>(q.w));
        o.n = o.n + 1;
        if (i < 5 && q.y >= o.s1.y) {
            o.s1 = q;
        }
    }
    // (the stem's trunk: wide at its dusty foot, narrowing a little to its top billow)
    // (its foot under the crater's floor (some 9 deep): it rises out of the ground, its bottom never seen)
    o.s0 = vec4<f32>(C + vec3<f32>(0.0, -12.0, 0.0), min(o.s1.w * 1.25, 16.0 + 55.0 * saturate(a / 1.2)));
    o.s1.w = o.s1.w * 0.75;
    o.sk = vec4<f32>(C + vec3<f32>(0.0, -5.0, 0.0), (20.0 + 60.0 * saturate(a / 1.5)) * (1.0 + 0.01 * max(a - 2.0, 0.0)));
    if (o.n > 0) {
        o.lo = min(o.lo, min(o.s0.xyz - vec3<f32>(o.s0.w), o.sk.xyz - vec3<f32>(o.sk.w, 22.0, o.sk.w)));
        o.hi = max(o.hi, o.sk.xyz + vec3<f32>(o.sk.w, 22.0, o.sk.w));
    }
    // (the trenches' smoke: laid as each point ploughs out, a roll rising and swelling behind it, thinning away)
    o.lr = vec4<f32>(0.0);
    if (ss_have() && a > 0.05 && a < SS_LEG_GONE) {
        let reach = ss_tip(a) - 6.0;
        let foot = SS_LEG_R0;
        let age0 = a - ss_plough_t(foot);
        let age1 = max(a - ss_plough_t(reach), 0.0);
        let l0 = smoothstep(0.0, 0.35, age0) * exp(-max(age0 - 5.0, 0.0) / 4.0);
        let l1 = smoothstep(0.0, 0.25, age1) * exp(-max(age1 - 5.0, 0.0) / 4.0);
        let r0 = (10.0 + 16.0 * (1.0 - exp(-age0 / 6.0))) * l0;
        let r1 = (5.0 + 12.0 * (1.0 - exp(-age1 / 6.0))) * max(l1, 0.35 * l0);
        o.ln = vec2<f32>(foot, max(reach, foot + 1.0));
        // (its axis low, the lower part of the roll in the ground: it hugs the land rather than hanging over it)
        o.lr = vec4<f32>(r0, r1, 0.4 * r0 + 4.0 * (1.0 - exp(-age0 / 5.0)) - 3.0, 0.35 * r1 - 2.0);
        let yaw = pl_w(9u);
        let mid = 0.5 * (o.ln.x + o.ln.y);
        for (var k = 0; k < 5; k = k + 1) {
            let an = yaw + TAU * f32(k) / 5.0;
            let dr = vec2<f32>(cos(an), sin(an));
            o.lh[k] = vec4<f32>(pl_land(dr * o.ln.x, 0.0).x, pl_land(dr * mid, 0.0).x, pl_land(dr * o.ln.y, 0.0).x, 0.0);
        }
        if (r0 > 0.5) {
            var glo = 0.0;
            var ghi = 0.0;
            for (var k = 0; k < 5; k = k + 1) {
                glo = min(glo, min(o.lh[k].x, min(o.lh[k].y, o.lh[k].z)));
                ghi = max(ghi, max(o.lh[k].x, max(o.lh[k].y, o.lh[k].z)));
            }
            let e = o.ln.y + o.lr.x;
            o.lo = min(o.lo, C + vec3<f32>(-e, glo - 10.0, -e));
            o.hi = max(o.hi, C + vec3<f32>(e, ghi + o.lr.z + 2.0 * o.lr.x, e));
            o.n = max(o.n, 1);
        }
    }
    // (room for the billows' lumps)
    o.lo = o.lo - vec3<f32>(34.0);
    o.hi = o.hi + vec3<f32>(34.0);
    return o;
}
fn pl_col_base(col: ptr<function, PlCol>, p: vec3<f32>) -> f32 {
    var d = 1.0e6;
    let pc = p - (*col).C;
    for (var i = 0; i < PL_NPUFF; i = i + 1) {
        let qp = (*col).q[i];
        let qa = unpack2x16float(qp.x);
        let qb = unpack2x16float(qp.y);
        let q = vec4<f32>(qa, qb);
        if (q.w > 0.0) {
            // (the low ones squat and wide, spreading over the ground)
            let low = 1.0 - smoothstep(0.0, 60.0, q.y);
            let e = (pc - q.xyz) * vec3<f32>(1.0 - 0.25 * low, 1.0 + 0.6 * low, 1.0 - 0.25 * low);
            d = smin(d, (length(e) - q.w) / (1.0 + 0.6 * low), 18.0);
        }
    }
    let sk = (*col).sk;
    if ((*col).n > 0) {
        let r = vec3<f32>(sk.w, 22.0, sk.w);
        let e = (p - sk.xyz) / r;
        let k0 = length(e);
        d = smin(d, k0 * (k0 - 1.0) / max(length(e / r), 1.0e-4), 16.0);
    }
    let lr = (*col).lr;
    if (lr.x > 0.5) {
        let yaw = pl_w(9u);
        for (var k = 0; k < 5; k = k + 1) {
            let an = yaw + TAU * f32(k) / 5.0;
            let dir = vec3<f32>(cos(an), 0.0, sin(an));
            // (in two runs, foot to middle and middle to end, each on the land under it)
            let gh = (*col).lh[k];
            let lm = 0.5 * ((*col).ln.x + (*col).ln.y);
            let A = dir * (*col).ln.x + vec3<f32>(0.0, gh.x + lr.z, 0.0);
            let M = dir * lm + vec3<f32>(0.0, gh.y + 0.5 * (lr.z + lr.w), 0.0);
            let B = dir * (*col).ln.y + vec3<f32>(0.0, gh.z + lr.w, 0.0);
            let rm = 0.5 * (lr.x + lr.y);
            let am = M - A;
            let u1 = saturate(dot(pc - A, am) / max(dot(am, am), 1.0));
            d = smin(d, length(pc - A - am * u1) - mix(lr.x, rm, u1), 14.0);
            let mb = B - M;
            let u2 = saturate(dot(pc - M, mb) / max(dot(mb, mb), 1.0));
            d = smin(d, length(pc - M - mb * u2) - mix(rm, lr.y, u2), 14.0);
        }
    }
    let s0 = (*col).s0;
    let s1 = (*col).s1;
    if (s1.w > 0.0) {
        let ab = s1.xyz - s0.xyz;
        let u = saturate(dot(p - s0.xyz, ab) / max(dot(ab, ab), 1.0));
        d = smin(d, length(p - s0.xyz - ab * u) - mix(s0.w, s1.w, u), 14.0);
    }
    return d;
}
// Cauliflower lumps: domes over a jittered lattice (a feature point in each of the eight cells round p, well jittered),
// each its own size (big ones standing proud of small ones), rounded on top and meeting in creases: about 1 on a big
// dome's crown, 0 in a crease. Called on a rotated domain (pl_rot), a different turn for each size, so no lattice lines up
// with the world's axes or with another's.
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
// The three turns of the lumps' domains, one a size.
fn pl_rot(k: i32, p: vec3<f32>) -> vec3<f32> {
    if (k == 0) {
        return mat3x3<f32>(-0.0014, 0.9977, -0.0674, -0.2224, -0.0660, -0.9727, -0.9750, 0.0136, 0.2220) * p;
    }
    if (k == 1) {
        return mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971) * p;
    }
    return mat3x3<f32>(-0.9891, -0.1223, 0.0816, 0.0968, -0.9594, -0.2651, 0.1107, -0.2543, 0.9608) * p;
}
// The column's surface at p, as the clips' smoke is: one mass, not a pile of balls. The billows' union warped and
// bulged out in lumps on lumps on lumps (big domes, middling ones on them, small ones on those, and a fine turbulent
// fray at the very edge), the lumps smaller down the thinner stem. In .y how far up a dome it lies (0 deep in a crease,
// 1 on a crown), in .z how soft its edge is there (crisp in places, a loose wispy fringe in others: the density's ramp,
// blocks), in .w the fine fray (0 to 1) the fringe is torn by.
fn pl_col_sdf(col: ptr<function, PlCol>, p: vec3<f32>, d0: f32, fine: bool) -> vec4<f32> {
    let a = (*col).a;
    let q = (p - (*col).C) * vec3<f32>(1.0, 1.0 / (*col).grow, 1.0) - vec3<f32>(0.0, 2.2 * a + 10.0 * min(a, 1.5), 0.0) - pl_wind() * (a * 0.4);
    // (the billows' balls melted together and pushed about, so no one of them shows round)
    let w = gnoise3(pl_rot(1, q * (1.0 / 55.0)));
    let w2 = gnoise3(pl_rot(2, q * (1.0 / 23.0) + vec3<f32>(9.2, -0.12 * a, 4.4)));
    let b1 = pl_dome(pl_rot(0, q * (1.0 / 36.0) + vec3<f32>(3.1, 0.0, 7.7) + 0.3 * vec3<f32>(w2 - 0.5)));
    let hy = p.y - (*col).C.y;
    // (the stem's lumps smaller: it is thinner)
    let lump = 0.7 + 0.3 * smoothstep(15.0, 110.0, hy);
    // (as it settles its billows melt away: the lumps sink back into a rounded mass, its edge a broad loose fringe)
    let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
    let crisp = 1.0 - 0.8 * soft;
    let b2 = pl_dome(pl_rot(1, q * (1.0 / 14.0) + vec3<f32>(0.0, -0.3 * a, 1.3)));
    // (up the stem the big lumps give way to middling ones: it is too thin for two of them across)
    let up = smoothstep(25.0, 130.0, hy);
    var d = d0 - (26.0 * (b1 - 0.45) * crisp * (0.3 + 0.7 * up) + (6.0 + 6.0 * (1.0 - up)) * (b2 - 0.45) * (1.0 - 0.7 * soft) + (18.0 + 8.0 * soft) * (w - 0.5) + 8.0 * (w2 - 0.5)) * lump;
    // (crisp-edged mostly, its lumps outlined sharp against the sky, torn into fine wisps only in places; the stem's
    // foot loosest: the dust it stands in)
    let ew = smoothstep(0.6, 0.82, w2);
    let edge = mix(0.8, 3.5, ew) + 6.0 * (1.0 - smoothstep(0.0, 60.0, hy));
    var fray = 0.5;
    if (fine && d < 12.0 && soft < 0.99) {
        // (small cauliflower lumps on the middling ones, then the turbulent fray right at the edge)
        let b3 = pl_dome(pl_rot(2, q * (1.0 / 5.5) + vec3<f32>(1.7, -0.5 * a, -2.1)));
        d = d - 2.4 * (b3 - 0.45) * (1.0 - soft) * lump;
        fray = gnoise3(pl_rot(0, q * (1.0 / 1.8)) + vec3<f32>(5.0, 1.0, -0.8 * a));
        d = d - 2.4 * (fray - 0.5) * (1.0 - soft) * (0.25 + 0.75 * ew);
    }
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

// How much of the sun's light reaches land point `o` (camera-relative) through the column: its billows' smooth body
// marched towards the sun in ten steps, soft-edged. 1 in full sun.
fn pl_shadow(o: vec3<f32>, L: vec3<f32>, a: f32, C: vec3<f32>, j: f32) -> f32 {
    // (first, whether the sun's ray passes near the column at all: the stick from its foot to its top)
    let cgrow = 1.0 + 0.012 * max(a - 6.0, 0.0) + 0.006 * max(a - PL_SOFT0, 0.0);
    let ctop = C + vec3<f32>(0.0, 5.0 + 1.08 * pl_w(5u) * (1.0 + 0.006 * a) * cgrow, 0.0) + pl_wind() * a;
    let sg = pl_ray_seg(L, C - vec3<f32>(0.0, 30.0, 0.0) - o, ctop - o, 0.0, 1.0);
    if (sg.x > 230.0 * cgrow + 60.0) {
        return 1.0;
    }
    var cs = pl_column(a, C);
    if (cs.n == 0) {
        return 1.0;
    }
    let tb = pl_box(L, cs.lo - o, cs.hi - o);
    if (tb.y <= tb.x) {
        return 1.0;
    }
    let n = 10;
    let dt = (tb.y - tb.x) / f32(n);
    var tau = 0.0;
    for (var i = 0; i < n; i = i + 1) {
        tau = tau + saturate(0.35 - pl_col_base(&cs, o + L * (tb.x + (f32(i) + j) * dt)) / 30.0);
    }
    let thin = 1.0 - 0.85 * smoothstep(PL_SOFT0, PL_SOFT1 + 10.0, a);
    return exp(-tau * dt * 0.03 * thin * smoothstep(0.3, 1.5, a));
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
    // (the four corners read one by one, not written into a vector at a run-time index in a loop: FXC, DirectX 12's
    // compiler, can't do that without unrolling the loops round it, and fails on the dust's and the cloud's)
    let b = PL_HF + 8u + i0.y * n + i0.x;
    let c = vec4<u32>(mod_data[b], mod_data[b + 1u], mod_data[b + n], mod_data[b + n + 1u]);
    let hv = vec4<f32>(c & vec4<u32>(0xffffu)) / 8.0 - 512.0;
    let sv = vec4<f32>((c >> vec4<u32>(16u)) & vec4<u32>(0xffu)) / 255.0;
    // (past its edge, the edge's ground carried on: not `gref`, which rises to wherever the player stood, up a tower
    // or in the air)
    let g = mix(mix(hv.x, hv.y, t.x), mix(hv.z, hv.w, t.x), t.y);
    let sh = mix(mix(sv.x, sv.y, t.x), mix(sv.z, sv.w, t.x), t.y);
    let e = smoothstep(-step, 3.0 * step, max(abs(q.x), abs(q.y)) - R);
    return vec2<f32>(g, sh * (1.0 - e));
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
    if (h > 70.0 || h < -4.0) {
        return vec2<f32>(0.0, h);
    }
    // (the front billows: pushed on and held back by the turbulence it churns, more so higher up)
    let rf = PL_V * a;
    let n1 = gnoise3(w * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a, 0.0));
    let n2 = gnoise3(w * (1.0 / 3.5) + vec3<f32>(5.0, -2.0 * a, 1.0));
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
    let hw = (7.0 + 0.009 * r) * rise * (0.35 + 1.2 * n1) * (0.6 + 0.8 * n3) + 1.5 * min(since, 6.0);
    let up = smoothstep(hw, hw * 0.35, h) * smoothstep(-4.0, 0.0, h);
    let lead = smoothstep(-3.0, 1.5, s);
    let wall = 1.6 * exp(-s / (9.0 + 0.015 * r)) * (0.75 + 0.25 * side) * (1.0 - 0.6 * sh);
    let haze = (0.009 * exp(-since / 2.5) + 0.0025 * exp(-since / 6.0)) * (0.5 + n2);
    // (none round the column's foot: the blast cleared it, and it would tint the smoke)
    let mid = smoothstep(70.0, 230.0, r);
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

// ---- the Six Stars: the stars, the sky, the falling star -------------------------------------------------------------
const SS_HUD: f32 = 0.3;           // the row of empty stars fades in at the top right
const SS_STAR1: f32 = 1.2;         // and each lights (strike/sixstars.rs's SS_STARS: evenly spaced)
const SS_STAR2: f32 = 2.35;
const SS_STAR3: f32 = 3.5;
const SS_STAR4: f32 = 4.65;
const SS_STAR5: f32 = 5.8;
const SS_STAR6: f32 = 6.95;
const SS_GATHER: f32 = 7.72;       // the sixth sinks into its slot, the others dimming, the sky drawn in towards it,
const SS_PEEL: f32 = 8.2;          // snaps out of it to the top of its jolt (SS_JOLT), held there (the hit-stop),
const SS_JOLT: f32 = 0.1;
const SS_GO: f32 = 8.36;           // let go, smeared along its way for a few frames, kicked up and to the side out of the
                                   // row, and, still the screen's flat star, swoops across the picture to where it will hang,
const SS_CONV: f32 = 10.35;        // turning into the star in the world there (the same picture), its thickness growing
const SS_REAL: f32 = 0.95;         // in over this,
const SS_STATION: f32 = 11.2;      // hangs high over the target,
const SS_DROP: f32 = 11.8;         // falls, and strikes at PL_HIT
const SS_PLOUGH: f32 = 2.4;        // its points plough out this long after it strikes, slowing (SS_PLOUGH_K)
const SS_PLOUGH_K: f32 = 0.8;
const SS_IN_K: f32 = 0.42;         // the star's inner corners, of its points' radius
const SS_TRAIL: f32 = 2.2;         // its smoke trail, as wide again as the Payload's this many times
const SS_TRAIL_GONE: f32 = 5.0;    // and thinned away this long after it strikes (sig: its smoke thins over six seconds)
const SS_MAGIC: f32 = 6006.0;
const SS_CELLS: f32 = 12.0;        // the star is built of blocks: this many a side from its middle to a tip

fn ss_have() -> bool {
    return abs(pl_w(15u) - SS_MAGIC) < 0.5;
}
fn ss_star_t(i: i32) -> f32 {
    return SS_STAR1 + (SS_STAR2 - SS_STAR1) * f32(i);
}
// params[15]'s flags (lib.rs's flags_of): 1 the smoke's shadow off, 2 the flashes softened (`/orbital impactframes off`).
fn ss_soft() -> bool {
    return (u32(frame.mod_params[3].w + 0.01) & 2u) != 0u;
}
// The sunset's sun: low over the land, off to one side of the target as the player looked.
fn ss_sun() -> vec3<f32> {
    let a = pl_w(14u);
    let el = 0.165;
    return vec3<f32>(cos(a) * cos(el), sin(el), sin(a) * cos(el));
}
// How far the stars have climbed at t: 0 to 6, each step eased in over most of a second as its star lights.
fn ss_level(t: f32) -> f32 {
    var l = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        l = l + smoothstep(ss_star_t(i) - 0.05, ss_star_t(i) + 0.9, t);
    }
    return l;
}
// The sunset's hold on the world at t (`l` the stars' level, there): rising with the stars, let go over the last seconds.
fn ss_hold(t: f32, l: f32) -> f32 {
    return pow(saturate(l / 6.0), 0.8) * (1.0 - smoothstep(PL_LEN - 7.0, PL_LEN - 0.5, t));
}
// The pulse on each beat (a star lighting, the sixth peeling out): how hard the sun flares, 0 to about 1.
fn ss_beat(t: f32) -> f32 {
    var b = 0.0;
    for (var i = 0; i < 7; i = i + 1) {
        let t0 = select(ss_star_t(i), SS_PEEL, i == 6);
        let s = t - t0;
        if (s > -0.05) {
            let k = 0.55 + 0.09 * f32(i);
            if (ss_soft()) {
                b = b + 0.35 * k * smoothstep(-0.05, 0.4, s) * exp(-max(s - 0.4, 0.0) / 1.2);
            } else {
                b = b + k * smoothstep(-0.05, 0.03, s) * exp(-max(s, 0.0) / 0.45);
            }
        }
    }
    return b;
}
// The sun's angular radius: small at first, swelling a step with each star (and flaring on each beat).
fn ss_sun_r(t: f32) -> f32 {
    let l = ss_level(t);
    return 0.03 + 0.011 * l + 0.008 * ss_beat(t);
}

// The hazy golden-hour sky along rd: deep violet and dusty lavender overhead, hot pink and coral lower, peach and
// orange at the horizon, warmer and brighter round the sun (no sun itself: ss_sky_sun).
fn ss_sunset(rd: vec3<f32>) -> vec3<f32> {
    let S = ss_sun();
    let e = rd.y;
    let h = max(e, 0.0);
    var c = mix(vec3<f32>(1.25, 0.62, 0.30), vec3<f32>(1.08, 0.46, 0.38), smoothstep(0.0, 0.07, h));
    c = mix(c, vec3<f32>(0.88, 0.33, 0.52), smoothstep(0.05, 0.19, h));
    c = mix(c, vec3<f32>(0.52, 0.40, 0.72), smoothstep(0.16, 0.40, h));
    c = mix(c, vec3<f32>(0.19, 0.12, 0.38), smoothstep(0.36, 0.98, h));
    let fl = normalize(vec3<f32>(rd.x, 0.0, rd.z) + vec3<f32>(1.0e-5, 0.0, 0.0));
    let cs = max(dot(fl, normalize(vec3<f32>(S.x, 0.0, S.z))), 0.0);
    c = c + vec3<f32>(1.1, 0.5, 0.18) * pow(cs, 6.0) * exp(-h * 5.0) * 0.8;
    if (e < 0.0) {
        c = mix(c, vec3<f32>(0.55, 0.34, 0.44), smoothstep(0.0, -0.3, e));
    }
    return c;
}
// A deck of streaky cloud high over the land, lit from under by the low sun: gold near it, pink and violet away from
// it, its tops in shade.
fn ss_clouds(rd: vec3<f32>, t: f32) -> vec4<f32> {
    if (rd.y < 0.015) {
        return vec4<f32>(0.0);
    }
    let S = ss_sun();
    let tp = (1050.0 - frame.camera_position.y) / rd.y;
    if (tp <= 0.0) {
        return vec4<f32>(0.0);
    }
    let base = (frame.camera_position.xz - floor(frame.camera_position.xz / 20000.0) * 20000.0) + rd.xz * tp + vec2<f32>(t * 6.0, t * 2.0);
    // (streaks, long one way)
    let ca = 0.6;
    let q = vec2<f32>(base.x * cos(ca) - base.y * sin(ca), base.x * sin(ca) + base.y * cos(ca));
    let wq = q / vec2<f32>(2600.0, 1100.0);
    let warp = vec2<f32>(gnoise2(wq * 1.7 + vec2<f32>(3.1, 0.4)), gnoise2(wq * 1.7 + vec2<f32>(-1.2, 5.5))) - 0.5;
    let n = gfbm2(wq + warp * 0.8) * 0.75 + gnoise2(q / vec2<f32>(500.0, 300.0) + warp * 2.0) * 0.25;
    let den = smoothstep(0.47, 0.72, n) * smoothstep(0.015, 0.12, rd.y) * exp(-tp / 26000.0);
    if (den <= 0.001) {
        return vec4<f32>(0.0);
    }
    let cs = pow(max(dot(rd, S), 0.0), 3.0);
    let under = mix(vec3<f32>(1.05, 0.42, 0.62), vec3<f32>(1.5, 0.82, 0.42), cs);
    let shade = mix(vec3<f32>(0.42, 0.26, 0.55), under, smoothstep(0.5, 0.8, n));
    return vec4<f32>(shade, den * 0.85);
}
// The sun itself and its glow along rd (over the sky, where the land does not hide it).
fn ss_sky_sun(rd: vec3<f32>, t: f32) -> vec3<f32> {
    let S = ss_sun();
    let th = acos(clamp(dot(rd, S), -1.0, 1.0));
    let r = ss_sun_r(t);
    // (its lower edge sunk in the haze over the horizon)
    let sunk = smoothstep(-0.015, 0.05, rd.y);
    let disc = smoothstep(r, r * 0.93, th) * mix(0.55, 1.0, sunk);
    let beat = ss_beat(t);
    let glow = exp(-th / (0.11 + 0.6 * r)) * (0.45 + 0.35 * beat) + 0.18 * exp(-th / 0.45);
    return vec3<f32>(2.6, 1.75, 0.95) * disc * (1.0 + 0.4 * beat) + vec3<f32>(1.4, 0.6, 0.3) * glow;
}
// The world graded to the golden hour: lit warm peach, its shadows violet, the far land fading into the pink haze.
fn ss_grade(c: vec3<f32>, dist: f32, rd: vec3<f32>, s: f32) -> vec3<f32> {
    let l = luminance(c);
    let tone = mix(vec3<f32>(0.56, 0.42, 0.88), vec3<f32>(1.16, 0.9, 0.68), smoothstep(0.015, 0.33, l));
    let night = smoothstep(0.0, -0.25, frame.sun.y);
    // (the greens pulled warm: lit as by a low orange sun, not the day's white)
    let warmed = mix(c, vec3<f32>(l) * vec3<f32>(1.35, 0.95, 0.72), 0.25);
    var g = warmed * tone * (1.08 + 1.4 * night) + vec3<f32>(0.012, 0.008, 0.022);
    let hz = ss_sunset(normalize(vec3<f32>(rd.x, 0.03, rd.z)));
    let level = 1.0 - smoothstep(0.08, 0.45, -rd.y);
    g = mix(g, hz * 0.8, (1.0 - exp(-dist / 2600.0)) * 0.55 * level);
    return mix(c, g, s);
}

// ---- the star as a shape: five points, its tips at 1 (iq's sdStar5) ---------------------------------------------------
fn ss_star2(p0: vec2<f32>) -> f32 {
    let k1 = vec2<f32>(0.809016994375, -0.587785252292);
    let k2 = vec2<f32>(-k1.x, k1.y);
    var p = vec2<f32>(abs(p0.x), p0.y);
    p = p - 2.0 * max(dot(k1, p), 0.0) * k1;
    p = p - 2.0 * max(dot(k2, p), 0.0) * k2;
    p = vec2<f32>(abs(p.x), p.y - 1.0);
    let ba = SS_IN_K * vec2<f32>(-k1.y, k1.x) - vec2<f32>(0.0, 1.0);
    let h = clamp(dot(p, ba) / dot(ba, ba), 0.0, 1.0);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// ---- the stars on the screen: six, top right, as a wanted level's ----------------------------------------------------
// Lit from the right, the leftmost last (it is the one that leaves). Each its own: an empty slot (dark, outlined) until it lights; lit, white with a thin dark outline, its fill growing out
// of its middle with a little overshoot and a flash of light round it. Built of the same steps as the star that leaves
// (SS_CELLS from its middle to a tip), so the one that peels out is the same picture. Premultiplied colour and coverage.
fn ss_hud_geom() -> vec4<f32> {
    let res = frame.resolution.xy;
    let rh = 0.03 * res.y;
    // (its size, the gap between, the row's height, the rightmost's middle)
    return vec4<f32>(rh, 2.45 * rh, 0.078 * res.y, res.x - 0.055 * res.y - rh);
}
// The lit white of a star's face at p (its points' tips at 1): the screen's, and the star in the world's while it is
// still the screen's picture.
fn ss_white(p: vec2<f32>) -> vec3<f32> {
    return vec3<f32>(1.0, 0.97, 0.95) * (0.94 + 0.06 * (1.0 - length(p)));
}
// One star of the row, `q` the pixel from its middle in its own frame (screen pixels, y down) and `rh` its points'
// radius in pixels: `lit` (0 an empty slot) from ti, its outline and shadow `ol` of the row's, a halo `hal` round it.
fn ss_hud_star(q: vec2<f32>, rh: f32, lit: f32, ti: f32, t: f32, ol: f32, hal: f32) -> vec4<f32> {
    let cell = rh / SS_CELLS;
    // (the steps of its edge)
    let qc = (floor(q / cell) + 0.5) * cell;
    let p = vec2<f32>(qc.x, -qc.y) / rh;
    let d = ss_star2(p);
    // (lit from its middle out, overshooting a little)
    let s = saturate((t - ti) / 0.22);
    let grow = s * (1.0 + 0.6 * (1.0 - s)) * 1.15;
    let fill = select(0.0, 1.0, d < 0.0 && length(p) < grow * 1.2) * lit;
    // (a thin dark outline round it, a step wide, and a soft shadow)
    let edge = select(0.0, 1.0, d >= 0.0 && d < 1.15 / SS_CELLS);
    let pd = ss_star2(p + vec2<f32>(-1.5, 1.5) / SS_CELLS);
    let shadow = select(0.0, 0.35, pd < 0.0 && d >= 0.0);
    var a = max(max(edge * 0.92, shadow) * ol, select(0.0, 0.5, d < 0.0));
    var rgb = vec3<f32>(0.035, 0.028, 0.05) * a;
    if (d < 0.0) {
        // (empty: dark and see-through; lit: white, a breath of warmth from the sunset round it)
        rgb = mix(vec3<f32>(0.035, 0.03, 0.05) * 0.5, ss_white(p), fill);
        a = mix(0.5, 1.0, fill);
    }
    let halo = hal * exp(-max(ss_star2(vec2<f32>(q.x, -q.y) / rh), 0.0) * 4.0) * select(1.0, 0.0, d < 0.0);
    rgb = rgb + vec3<f32>(1.0, 0.9, 0.95) * halo;
    a = max(a, min(halo, 1.0));
    return vec4<f32>(rgb, a);
}
// The wind-up before the leftmost leaves (SS_GATHER to SS_PEEL), 0 to 1: slow to start and gathering pace into the
// release, so it builds; held at 1 from the release on (what follows it eases out of its own accord).
fn ss_wind(t: f32) -> f32 {
    let x = saturate((t - SS_GATHER) / (SS_PEEL - SS_GATHER));
    return x * x * (1.6 - 0.6 * x);
}
// The leftmost sinking into its slot as it winds up (xy its middle's offset in its radii, z its scale), and so the
// pose the star that leaves starts its jolt from.
fn ss_gather(t: f32) -> vec3<f32> {
    let g = ss_wind(t);
    return vec3<f32>(0.0, 0.07 * g, 1.0 - 0.15 * g);
}
// The row's recoil as the leftmost snaps out (`x` seconds since the release reached this star): kicked away and
// springing back with one small undershoot, a fraction of its radius; never a bounce.
fn ss_recoil(x: f32) -> f32 {
    if (x <= 0.0) {
        return 0.0;
    }
    return exp(-x / 0.07) * sin(x * 19.6);
}
// How the stars blink as the level is lost (after the strike, before they go): 1 lit, 0 its empty slot. Fast blinks
// with soft edges, a touch quicker as it goes, the last one staying off: the stars left blank, and only then the empty
// row fades away (SS_BLINK1 to SS_HUD_GONE). With the flashes softened a slow, gentle breath, easing out to blank.
const SS_BLINK0: f32 = 19.5;
// (the eighth blink's off: the phase reaching 7.3, about 2.8 s in)
const SS_BLINK_LAST: f32 = 7.3;
const SS_BLINK1: f32 = 22.7;
const SS_HUD_GONE: f32 = 23.6;
fn ss_blink(t: f32) -> f32 {
    if (t < SS_BLINK0) {
        return 1.0;
    }
    let u = t - SS_BLINK0;
    if (ss_soft()) {
        // (one breath every 1.3 s, down to a little under half and back, easing in; then out to blank)
        let breath = 1.0 - 0.55 * smoothstep(0.0, 0.6, u) * (0.5 - 0.5 * cos(TAU * u / 1.3));
        return breath * (1.0 - smoothstep(SS_BLINK1 - 1.0, SS_BLINK1 - 0.2, t));
    }
    // (a phase that runs at 2.3 a second picking up to 2.9, each cycle off for its middle 45%, its edges ramps of
    // some 40 ms; seven blinks, and the eighth stays off)
    let ph = u * 2.3 + 0.11 * u * u;
    let fw = 0.04 * (2.3 + 0.22 * u);
    if (ph >= SS_BLINK_LAST) {
        return 1.0 - smoothstep(SS_BLINK_LAST - fw, SS_BLINK_LAST + fw, ph);
    }
    let f = fract(ph);
    let off = smoothstep(0.3 - fw, 0.3 + fw, f) * (1.0 - smoothstep(0.75 - fw, 0.75 + fw, f));
    return 1.0 - off;
}
fn ss_hud(px: vec2<f32>, t: f32) -> vec4<f32> {
    let g = ss_hud_geom();
    let rh = g.x;
    let fade = smoothstep(SS_HUD, SS_HUD + 0.5, t) * (1.0 - smoothstep(SS_BLINK1, SS_HUD_GONE, t));
    if (fade <= 0.0 || px.y > g.z + 2.8 * rh || px.x < g.w - 5.0 * g.y - 2.5 * rh) {
        return vec4<f32>(0.0);
    }
    let wind = ss_wind(t);
    let tau = t - SS_PEEL;
    let blink = ss_blink(t);
    var out = vec4<f32>(0.0);
    for (var i = 0; i < 6; i = i + 1) {
        var c = vec2<f32>(g.w - f32(5 - i) * g.y, g.z);
        // (the others: dimmed a little as the leftmost winds up, and as it snaps out kicked down and away from it, the
        // nearest first and hardest, the release running along the row; their light coming back with the kick)
        var dim = 1.0;
        if (i > 0 && t > SS_GATHER && tau < 0.8) {
            let x = tau - 0.022 * f32(i - 1);
            let rc = ss_recoil(x) * rh * (0.5 - 0.06 * f32(i - 1));
            c = c + vec2<f32>(0.3, 1.0) * rc;
            dim = 1.0 - 0.3 * select(wind, exp(-max(x, 0.0) / 0.09), x > 0.0);
        }
        var q = px - c;
        if (length(q) > 2.4 * rh) {
            continue;
        }
        // (lit from the right: the rightmost first, the leftmost, the outermost, last)
        let ti = ss_star_t(5 - i);
        var lit = smoothstep(ti, ti + 0.02, t);
        // (the last, the leftmost, leaves its slot: it flies from then (ss_fly), its slot left empty)
        let gone = i == 0 && t >= SS_PEEL;
        var hal = 0.0;
        if (gone) {
            lit = 0.0;
        } else if (i == 0) {
            // (sinking into its slot, and its glow gathering)
            let gt = ss_gather(t);
            q = (q - gt.xy * rh) / gt.z;
            hal = 0.35 * wind * select(1.0, 0.5, ss_soft());
        }
        lit = lit * blink;
        // (a flash of light round it as it lights; a faint glow while lit)
        let fl = select(exp(-max(t - ti, 0.0) / 0.45) * smoothstep(ti - 0.02, ti + 0.04, t) * select(1.0, 0.35, ss_soft()), 0.0, gone);
        var st = ss_hud_star(q, rh, lit, ti, t, 1.0, fl * 0.9 + 0.12 * lit + hal);
        st = vec4<f32>(st.rgb * dim, st.a);
        out = vec4<f32>(out.rgb * (1.0 - st.a) + st.rgb, out.a + st.a * (1.0 - out.a));
    }
    return out * fade;
}

// ---- the star leaving the screen: still the screen's flat star, out of its slot and across the picture to where it
// will hang, growing to the size it will be there; there it turns into the star in the world (ss_frame) ------------
struct SsCam {
    fwd: vec3<f32>,
    right: vec3<f32>,
    up: vec3<f32>,
    fpx: f32,
}
fn ss_cam() -> SsCam {
    var c: SsCam;
    c.fwd = -normalize((frame.inverse_view * vec4<f32>(0.0, 0.0, 1.0, 0.0)).xyz);
    c.right = normalize((frame.inverse_view * vec4<f32>(1.0, 0.0, 0.0, 0.0)).xyz);
    c.up = normalize((frame.inverse_view * vec4<f32>(0.0, 1.0, 0.0, 0.0)).xyz);
    // (pixels to a unit off the view's axis at a unit's depth)
    c.fpx = 0.5 * frame.resolution.y / tan(0.5 * frame.view_params.w);
    return c;
}
// Where it turns into the star in the world: where it will hang, S (camera-relative), as the camera sees it, or, while
// that is off the picture, on the picture's edge towards it at the same depth (and S behind the camera or far off to
// its side, as if a point as far off towards it); P that point, tg its pixel and rt the star's radius there in pixels.
struct SsDock {
    P: vec3<f32>,
    tg: vec2<f32>,
    rt: f32,
}
fn ss_dock(S: vec3<f32>, cam: SsCam) -> SsDock {
    var o: SsDock;
    let res = frame.resolution.xy;
    let dS = max(length(S), 1.0);
    var v = S / dS;
    let c = dot(v, cam.fwd);
    if (c < 0.3) {
        v = normalize(v + cam.fwd * (0.3 - c) * 1.5);
    }
    let D = max(dot(v * dS, cam.fwd), 1.0);
    o.rt = clamp(pl_w(10u) * cam.fpx / D, 0.5 * ss_hud_geom().x, 0.4 * res.y);
    let m = vec2<f32>(1.15 * o.rt);
    o.tg = clamp(project_rel(v * dS).xy * res, m, res - m);
    let dir = ss_cam_dir(o.tg / res);
    o.P = dir * D / max(dot(dir, cam.fwd), 0.05);
    return o;
}
// The flying star's middle on the screen (pixels), its points' radius and how far it has come (0 to 1) at t, from the
// slot c0 (radius rh) to tg (radius rt). At SS_PEEL it snaps from where it sank in its slot (ss_gather) to the top of
// its jolt, out of the slot and swollen, in SS_JOLT, and is held there to SS_GO (the hit-stop); let go, it is kicked up
// and to the side out of the row (the kick spent over a few tenths of a second), and, under that, swoops across the
// picture, picking up and then easing a long way into where it will hang, growing as it goes.
fn ss_fly_at(t: f32, c0: vec2<f32>, rh: f32, tg: vec2<f32>, rt: f32) -> vec4<f32> {
    let res = frame.resolution.xy;
    let g0 = ss_gather(SS_PEEL);
    let a0 = c0 + g0.xy * rh;
    let side = select(1.0, -1.0, tg.x < c0.x);
    let kick = vec2<f32>(side * 2.0, -0.75) * rh;
    // (the jolt: up out of the slot and a little its way, swelling past its size; then held)
    let jt = saturate((t - SS_PEEL) / SS_JOLT);
    // (fast out of the slot but never in one frame: some six frames, easing to its top)
    let je = 1.0 - pow(1.0 - jt, 2.2);
    let jo = vec2<f32>(side * 0.3, -0.62) * rh;
    let tau = max(t - SS_GO, 0.0);
    // (the kick eased in over its first frames: it picks up speed, it does not jump)
    let fj = min((1.0 - exp(-tau / 0.08)) / (1.0 - exp(-0.5 / 0.08)), 1.0) * smoothstep(0.0, 0.06, tau);
    let ut = saturate((t - SS_GO) / (SS_CONV - SS_GO));
    let w = 1.0 - pow(1.0 - ut, 1.4);
    let et = w * w * (3.0 - 2.0 * w);
    let h = a0 + kick;
    let dv = tg - h;
    var n = vec2<f32>(-dv.y, dv.x) / max(length(dv), 1.0);
    if (dot(n, 0.5 * res - 0.5 * (h + tg)) < 0.0) {
        n = -n;
    }
    let c = a0 + mix(jo * je, kick, fj) + dv * et + n * min(0.18 * length(dv), 0.18 * res.y) * sin(3.14159265 * et);
    // (its size: from its sunk size to past its own at the top of the jolt, settling to a little over it as it goes)
    let rj = rh * mix(mix(g0.z, 1.34, je), 1.3, fj);
    return vec4<f32>(c, exp(mix(log(rj), log(rt), pow(et, 1.15))), et);
}
struct SsFly {
    c: vec2<f32>,
    r: f32,
    e: f32,
    roll: f32,
    dir: vec2<f32>,
    sk: f32,
    sm: f32,
    ol: f32,
    hal: f32,
    O: vec3<f32>,
    R: f32,
}
fn ss_fly(t: f32, C: vec3<f32>) -> SsFly {
    var f: SsFly;
    let g = ss_hud_geom();
    let res = frame.resolution.xy;
    let c0 = vec2<f32>(g.w - 5.0 * g.y, g.z);
    let cam = ss_cam();
    let dk = ss_dock(pl_head(SS_STATION) + C, cam);
    let D = max(dot(dk.P, cam.fwd), 1.0);
    let tg = dk.tg;
    let rt = dk.rt;
    let a = ss_fly_at(t, c0, g.x, tg, rt);
    let b = ss_fly_at(t - 1.0 / 90.0, c0, g.x, tg, rt);
    f.c = a.xy;
    f.r = a.z;
    f.e = a.w;
    let vel = (a.xy - b.xy) * 90.0;
    let sp = length(vel);
    f.dir = select(vec2<f32>(0.0, -1.0), vel / max(sp, 1.0e-3), sp > 1.0);
    let tau = t - SS_GO;
    // (the smear as it is let go: drawn out along its way over two or three frames, its front where the star is, then
    // snapping back to its shape with a breath of squash; after that stretched hardly at all, by its speed)
    f.sm = 1.1 * smoothstep(0.0, 0.03, tau) * (1.0 - smoothstep(0.05, 0.1, tau));
    // (and drawn out a little as it jolts up out of the slot, so it is seen to travel there)
    let jt = saturate((t - SS_PEEL) / SS_JOLT);
    f.sm = max(f.sm, 0.55 * sin(3.14159265 * pow(jt, 0.7)) * step(t, SS_GO));
    f.sk = 1.0 + f.sm - 0.07 * ss_bump(tau - 0.04, 0.035) + min(sp / max(f.r, 1.0) * 0.004, 0.05);
    // (one turn, flicked as it is let go and slowing all the way to upright as it arrives)
    let ur = saturate(tau / (SS_CONV - SS_GO));
    let side = select(1.0, -1.0, tg.x < c0.x);
    f.roll = side * TAU * pow(1.0 - ur, 3.0);
    // (the row's outline shed as it leaves; white-hot through the hit-stop and fading as it goes, its slot's faint glow
    // fading as it goes)
    f.ol = (1.0 - smoothstep(SS_GO, SS_GO + 0.4, t)) * (1.0 - 0.8 * f.sm / 1.25);
    let hot = select(1.0, 0.35, ss_soft()) * select(1.0, 0.75, ss_soft() && t < SS_GO);
    f.hal = mix(0.35 * select(1.0, 0.5, ss_soft()), 0.9 * hot, saturate((t - SS_PEEL) / SS_JOLT)) * exp(-max(tau, 0.0) / 0.3)
        + 0.12 * (1.0 - f.e);
    // (as a star in the world, flat and facing the camera, it would be: for its glow)
    f.O = ss_cam_dir(f.c / res) * D / max(dot(ss_cam_dir(f.c / res), cam.fwd), 0.05);
    f.R = f.r * D / cam.fpx;
    return f;
}
// The flying star at pixel px (premultiplied colour and coverage).
fn ss_fly_draw(px: vec2<f32>, t: f32, f: SsFly) -> vec4<f32> {
    // (smeared: drawn out behind it, its front kept where it is)
    var q = px - f.c + f.dir * f.r * f.sm;
    if (length(q) > 2.6 * f.r * f.sk) {
        return vec4<f32>(0.0);
    }
    // (undo its stretch and its turn: into its own frame)
    let pr = vec2<f32>(-f.dir.y, f.dir.x);
    q = f.dir * dot(q, f.dir) / f.sk + pr * dot(q, pr) * sqrt(f.sk);
    let cr = cos(f.roll);
    let sr = sin(f.roll);
    q = vec2<f32>(cr * q.x + sr * q.y, -sr * q.x + cr * q.y);
    return ss_hud_star(q, f.r, 1.0, -100.0, t, f.ol, f.hal);
}
// The picture bent round the slot the star leaves: xy the pixels to move where this pixel looks, z how the lens
// shades what it bends (its thick middle a little brighter, its sides a little darker, -1 to 1), w how far out across
// it (-0.43 its inner side to 0.43 its outer: a breath of colour split across it, and light caught on its outer side). As it winds up the picture round the slot is drawn in towards it; as it snaps out (SS_PEEL) a
// ring of refraction bulges out of the slot, star-shaped at first and rounding as it grows, a thick lens magnifying
// what is behind it, thinning away as it spreads. Only near the slot, only then.
fn ss_bend(px: vec2<f32>, t: f32) -> vec4<f32> {
    if (t < SS_GATHER || t > SS_PEEL + 1.0 || !ss_have()) {
        return vec4<f32>(0.0);
    }
    let g = ss_hud_geom();
    let rh = g.x;
    let c0 = vec2<f32>(g.w - 5.0 * g.y, g.z);
    let q = px - c0;
    let l = length(q);
    let tau = t - SS_PEEL;
    let soft = select(1.0, 0.55, ss_soft());
    var o = vec4<f32>(0.0);
    // (drawn in: what is near the slot looked at from further out, so it shrinks towards it)
    let pin = 0.17 * ss_wind(t) * select(1.0, exp(-tau / 0.03), tau > 0.0) * soft;
    if (pin > 0.0 && l < 7.0 * rh) {
        o = vec4<f32>(q * pin * exp(-pow(l / (2.6 * rh), 2.0)), 0.0, 0.0);
    }
    if (tau > 0.0) {
        let r = rh * (0.9 + 11.0 * (1.0 - exp(-tau / 0.24)));
        let w = 0.45 * rh + 0.14 * (r - rh);
        if (l < r + 3.0 * w) {
            let qs = vec2<f32>(q.x, -q.y) / r;
            let x = mix(ss_star2(qs) * r, l - r, smoothstep(0.0, 0.3, tau)) / w;
            let amp = w * 0.65 * exp(-tau / 0.45) * smoothstep(0.0, 0.02, tau) * (1.0 - smoothstep(0.5, 1.0, tau)) * soft;
            let dir = q / max(l, 1.0);
            let ex = exp(-x * x);
            o = vec4<f32>(o.xy - dir * amp * x * ex, (amp / w) * (1.0 - 2.0 * x * x) * ex, (amp / w) * x * ex);
        }
    }
    return o;
}

// ---- the star in the world ----------------------------------------------------------------------------------------------
// Where it is and how it lies at t (camera-relative): its middle O, its axes (ey towards its first point, ez out of its
// face), its points' radius R and thickness T (blocks), how hot (0 the screen's flat white star, 1 burning) and how
// cracked; show 0 when it is not drawn.
struct SsFrame {
    O: vec3<f32>,
    ex: vec3<f32>,
    ey: vec3<f32>,
    ez: vec3<f32>,
    R: f32,
    T: f32,
    zk: f32,
    glint: f32,
    heat: f32,
    crack: f32,
    plain: f32,
    show: f32,
}
fn ss_ease(x: f32) -> f32 {
    let u = saturate(x);
    return u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
}
fn ss_cam_dir(uvp: vec2<f32>) -> vec3<f32> {
    return normalize(world_offset(uvp, 0.5));
}
fn ss_face(ez: vec3<f32>, up: vec3<f32>) -> SsFrame {
    var f: SsFrame;
    f.ez = ez;
    f.ey = normalize(up - dot(up, ez) * ez + vec3<f32>(0.0, 1.0e-5, 0.0));
    f.ex = cross(f.ey, f.ez);
    return f;
}
// A swell from rest to 1 at tau0 and back, smooth all the way (zero at and before 0).
fn ss_bump(tau: f32, tau0: f32) -> f32 {
    let x = max(tau, 0.0) / tau0;
    return x * x * exp(2.0 * (1.0 - x));
}
fn ss_frame(t: f32, C: vec3<f32>, me: vec3<f32>) -> SsFrame {
    var f: SsFrame;
    f.show = 0.0;
    if (t < SS_CONV || t >= PL_HIT) {
        return f;
    }
    let Rw = pl_w(10u);
    let Tw = pl_w(11u);
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let S = pl_head(SS_STATION) + C;
    // (where it hangs, facing where the player stood)
    let f0 = ss_face(normalize(me - S), up);
    let tau = t - SS_CONV;
    var O = pl_head(t) + C;
    var Rf = Rw;
    var fb = f0;
    if (t < SS_STATION) {
        // (it turns real where the flat star stopped, flat to the camera there (ss_fly: the same picture), and comes
        // round to face the player over the moment before it hangs, settling a little under its weight)
        let cam = ss_cam();
        let w = ss_ease(tau / (SS_STATION - SS_CONV));
        let sk = sin(3.14159265 * saturate(tau / (SS_STATION - SS_CONV)));
        let dk = ss_dock(S, cam);
        O = mix(dk.P, S, w) - up * 4.0 * sk * sk;
        Rf = mix(dk.rt * max(dot(dk.P, cam.fwd), 1.0) / cam.fpx, Rw, w);
        fb = ss_face(normalize(mix(-cam.fwd, f0.ez, w)), normalize(mix(cam.up, f0.ey, w)));
    }
    var ex = fb.ex;
    var ey = fb.ey;
    var ez = fb.ez;
    // (as it turns real, a slow swing of its face towards the sun and its top back, out of step, showing its thickness,
    // dying away into the hang)
    let gone = 1.0 - smoothstep(12.6, 13.6, t);
    let sgn = select(-1.0, 1.0, dot(ss_sun(), f0.ex) > 0.0);
    let sw = sgn * 0.42 * ss_bump(tau, 0.55) * gone;
    let tb = -0.15 * ss_bump(tau - 0.12, 0.7) * gone;
    ez = rot_axis(ez, ey, sw);
    ex = rot_axis(ex, ey, sw);
    ey = rot_axis(ey, ex, tb);
    ez = rot_axis(ez, ex, tb);
    // (then, as it falls, it tips its face the short way over to lie level, face down when the player is under it, so
    // they see its face all the way, turning a fifth of a turn in its own plane as it comes so that it lands with its
    // first point away from them (strike/sixstars.rs's yaw: tipped over, its first point would face them, and its
    // points are a fifth of a turn apart); first lifting its face a little as it is drawn up (SS_STATION to SS_DROP),
    // rocking a little as it comes down flat)
    let face_up = f0.ez.y > 0.0;
    let goal = select(-up, up, face_up);
    let h = normalize(cross(f0.ez, goal) + vec3<f32>(1.0e-5, 0.0, 0.0));
    let ang = acos(clamp(dot(f0.ez, goal), -1.0, 1.0));
    let ut = saturate((t - (SS_DROP - 0.1)) / (16.4 - (SS_DROP - 0.1)));
    let wt = 1.0 - pow(1.0 - ut, 1.2);
    let tip = ss_ease(wt);
    let psi = sgn * select(0.2 * TAU / 2.0, 0.2 * TAU, face_up) * ss_ease(saturate((t - SS_DROP) / (16.5 - SS_DROP)));
    ex = rot_axis(ex, ez, psi);
    ey = rot_axis(ey, ez, psi);
    let dip = smoothstep(SS_STATION, SS_DROP, t) * (1.0 - smoothstep(SS_DROP, SS_DROP + 0.9, t));
    let phi = ang * tip - 0.08 * dip;
    ex = rot_axis(ex, h, phi);
    ey = rot_axis(ey, h, phi);
    ez = rot_axis(ez, h, phi);
    let env = smoothstep(12.6, 13.8, t) * (1.0 - smoothstep(15.8, 16.75, t));
    let ra = 0.12 * (vnoise(vec2<f32>(t * 0.8, 1.3)) - 0.5) * env;
    let k2 = normalize(cross(up, h) + vec3<f32>(0.0, 0.0, 1.0e-5));
    let rb = 0.12 * (vnoise(vec2<f32>(t * 0.65, 7.9)) - 0.5) * env;
    ex = rot_axis(rot_axis(ex, h, ra), k2, rb);
    ey = rot_axis(rot_axis(ey, h, ra), k2, rb);
    ez = rot_axis(rot_axis(ez, h, ra), k2, rb);
    f.O = O;
    f.ex = ex;
    f.ey = ey;
    f.ez = ez;
    f.R = Rf;
    f.T = Tw * Rf / Rw;
    f.zk = max(ss_ease(tau / SS_REAL), 0.01);
    f.plain = 1.0 - smoothstep(0.05, 1.25, tau);
    f.glint = saturate((tau - 0.3) / 0.6);
    let hot = smoothstep(SS_CONV + 0.1, SS_STATION, t);
    f.heat = select(mix(0.55, 1.0, smoothstep(SS_STATION, SS_DROP + 2.0, t)), 0.55 * hot, t < SS_STATION);
    f.crack = select(mix(0.2, 1.0, smoothstep(SS_DROP, PL_HIT, t)), 0.2 * hot, t < SS_DROP);
    f.show = 1.0;
    return f;
}
// How far out the points' tips are tau seconds after it strikes, from R to the crater's tips (strike/sixstars.rs's
// ss_tip).
fn ss_tip(tau: f32) -> f32 {
    let k = (1.0 - exp(-clamp(tau, 0.0, SS_PLOUGH) / SS_PLOUGH_K)) / (1.0 - exp(-SS_PLOUGH / SS_PLOUGH_K));
    return pl_w(10u) + (pl_w(12u) - pl_w(10u)) * k;
}
// When the tips reach r (seconds after it strikes).
fn ss_plough_t(r: f32) -> f32 {
    let R = pl_w(10u);
    if (r <= R) {
        return 0.0;
    }
    let f = min((r - R) / max(pl_w(12u) - R, 1.0), 1.0);
    return -SS_PLOUGH_K * log(max(1.0 - f * (1.0 - exp(-SS_PLOUGH / SS_PLOUGH_K)), 1.0e-4));
}
// Point k, ploughing out over the land tau seconds after it strikes: lying level on the land, nose down a little,
// sinking as it goes, crumbling once it stops.
fn ss_piece(k: i32, tau: f32, C: vec3<f32>) -> SsFrame {
    var f: SsFrame;
    let R = pl_w(10u);
    let a = pl_w(9u) + TAU * f32(k) / 5.0;
    let dir = vec3<f32>(cos(a), 0.0, sin(a));
    let off = ss_tip(tau) - R;
    let mid = dir * (off + 0.7 * R);
    let g = pl_land(mid.xz, 0.0).x;
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let ex = cross(dir, up);
    let tilt = -0.09;
    f.ey = dir * cos(tilt) - up * sin(tilt);
    f.ez = up * cos(tilt) + dir * sin(tilt);
    f.ex = ex;
    f.R = R;
    f.T = pl_w(11u);
    f.zk = 1.0;
    let bury = smoothstep(0.0, SS_PLOUGH, tau);
    f.O = C + dir * off + vec3<f32>(0.0, g + f.T * (0.35 - 0.45 * bury), 0.0);
    f.heat = mix(1.0, 0.45, smoothstep(0.0, SS_PLOUGH + 1.5, tau));
    f.crack = 1.0;
    f.plain = 0.0;
    f.show = 1.0 - smoothstep(SS_PLOUGH + 0.6, SS_PLOUGH + 2.2, tau);
    return f;
}

struct SsHit {
    t: f32,
    n: vec3<f32>,
    cell: vec3<f32>,
    hit: bool,
}
// Whether cell c (cells from its middle; SS_CELLS to a tip) is a block of it: inside the star, as thick as it is there
// (thickest in the middle, stepping down to its edges: `hz` half its thickness, in cells), within point `mask` only
// (-1 all of it), not crumbled away.
fn ss_occ(c: vec3<f32>, hz: f32, mask: i32, crumble: f32) -> bool {
    let p = (c.xy + 0.5) / SS_CELLS;
    let d = ss_star2(p);
    if (d > 0.0) {
        return false;
    }
    let ht = max(hz * clamp(0.32 + (-d) / 0.3, 0.32, 1.0), 0.5);
    if (abs(c.z + 0.5) > ht) {
        return false;
    }
    if (mask >= 0) {
        let an = atan2(p.x, p.y);
        if (abs(an) > 0.6283 || length(p) < SS_IN_K * 0.9) {
            return false;
        }
    }
    if (crumble > 0.0) {
        let hh = fh31(c + vec3<f32>(f32(mask) * 37.0, 3.0, 11.0));
        if (hh < crumble * (0.6 + 0.6 * saturate(length(p)))) {
            return false;
        }
    }
    return true;
}
// The ray (ro, rd: in cells, rd scaled so its parameter is the world's distance) through the star's blocks within the
// box lo..hi: the first block it meets.
fn ss_dda(ro: vec3<f32>, rd: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>, hz: f32, mask: i32, crumble: f32, tmax: f32) -> SsHit {
    var o: SsHit;
    o.hit = false;
    let inv = 1.0 / select(rd, vec3<f32>(1.0e-7), abs(rd) < vec3<f32>(1.0e-7));
    let ta = (lo - ro) * inv;
    let tb = (hi - ro) * inv;
    let t0v = min(ta, tb);
    let t1v = max(ta, tb);
    let t0 = max(max(t0v.x, t0v.y), max(t0v.z, 0.0));
    let t1 = min(min(t1v.x, t1v.y), min(t1v.z, tmax));
    if (t1 <= t0) {
        return o;
    }
    var axis = 0;
    if (t0v.y >= t0v.x && t0v.y >= t0v.z) {
        axis = 1;
    } else if (t0v.z >= t0v.x && t0v.z >= t0v.y) {
        axis = 2;
    }
    let p0 = ro + rd * (t0 + 1.0e-4);
    var cell = floor(p0);
    let st = sign(rd);
    let tdel = abs(inv);
    var tm = (cell + max(st, vec3<f32>(0.0)) - ro) * inv;
    var t = t0;
    for (var i = 0; i < 80; i = i + 1) {
        if (t > t1) {
            break;
        }
        if (ss_occ(cell, hz, mask, crumble)) {
            o.hit = true;
            o.t = t;
            o.cell = cell;
            var n = vec3<f32>(0.0);
            if (axis == 0) {
                n.x = -st.x;
            } else if (axis == 1) {
                n.y = -st.y;
            } else {
                n.z = -st.z;
            }
            o.n = n;
            return o;
        }
        if (tm.x < tm.y && tm.x < tm.z) {
            t = tm.x;
            tm.x = tm.x + tdel.x;
            cell.x = cell.x + st.x;
            axis = 0;
        } else if (tm.y < tm.z) {
            t = tm.y;
            tm.y = tm.y + tdel.y;
            cell.y = cell.y + st.y;
            axis = 1;
        } else {
            t = tm.z;
            tm.z = tm.z + tdel.z;
            cell.z = cell.z + st.z;
            axis = 2;
        }
    }
    return o;
}
// The star (or piece `mask`) of frame f along rd, nearer than tmax: its colour (x: how much it covers) and distance.
fn ss_draw(f: SsFrame, rd: vec3<f32>, tmax: f32, mask: i32, crumble: f32, t: f32, Ls: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>) -> vec4<f32> {
    let cs = f.R / SS_CELLS;
    // (its blocks squashed flat through its thickness by zk: none at all as it turns from the screen's star, growing in)
    let csv = vec3<f32>(cs, cs, cs * max(f.zk, 0.01));
    let ro = vec3<f32>(dot(f.ex, -f.O), dot(f.ey, -f.O), dot(f.ez, -f.O)) / csv;
    let rdl = vec3<f32>(dot(f.ex, rd), dot(f.ey, rd), dot(f.ez, rd)) / csv;
    let hz = max(0.5 * f.T / cs, 0.5);
    let zc = ceil(hz);
    var lo = vec3<f32>(-SS_CELLS, -SS_CELLS, -zc);
    var hi = vec3<f32>(SS_CELLS, SS_CELLS, zc);
    if (mask >= 0) {
        lo = vec3<f32>(-0.42 * SS_CELLS, 0.33 * SS_CELLS, -zc);
        hi = vec3<f32>(0.42 * SS_CELLS, SS_CELLS, zc);
    }
    let h = ss_dda(ro, rdl, lo, hi, hz, mask, crumble, tmax);
    if (!h.hit) {
        return vec4<f32>(0.0, 0.0, 0.0, -1.0);
    }
    let pc = ro + rdl * h.t;
    let p2 = pc.xy / SS_CELLS;
    let d = ss_star2(p2);
    let nw = f.ex * h.n.x + f.ey * h.n.y + f.ez * h.n.z;
    let side = 1.0 - abs(h.n.z);
    // (each block's own face: its edges a little darker, its own shade of white)
    var fu = fract(pc.xy);
    if (abs(h.n.x) > 0.5) {
        fu = fract(pc.yz);
    } else if (abs(h.n.y) > 0.5) {
        fu = fract(pc.xz);
    }
    let fe = min(min(fu.x, 1.0 - fu.x), min(fu.y, 1.0 - fu.y));
    let line = 1.0 - smoothstep(0.0, 0.08, fe);
    let hs = fh31(h.cell + vec3<f32>(5.0, 9.0, 1.0));
    let base = vec3<f32>(0.93, 0.9, 0.96) * (0.86 + 0.14 * hs);
    // (the screen's star: its face white, its sides dark, its outline)
    let hud = ss_white((h.cell.xy + 0.5) / SS_CELLS) * mix(vec3<f32>(1.0), vec3<f32>(0.66, 0.6, 0.78), side);
    // (in the world: lit by the low sun, warm on what faces it and violet in its shade, its sides darker)
    let lam = 0.35 + 0.65 * max(dot(nw, Ls), 0.0);
    var lit = base * (sunc * lam * 0.8 + vec3<f32>(dot(amb, vec3<f32>(0.333))) * 1.2) * (1.0 - 0.35 * line);
    lit = lit * mix(vec3<f32>(1.0), vec3<f32>(0.72, 0.62, 0.9), side);
    var c = mix(lit, hud, f.plain);
    // (as it turns real, a sheen of the low sun's light sliding once across its face, a block at a time)
    if (f.glint > 0.0 && f.glint < 1.0) {
        let pq = (h.cell.xy + 0.5) / SS_CELLS;
        let sb = (dot(pq, vec2<f32>(0.62, 0.78)) - mix(-1.45, 1.45, ss_ease(f.glint))) / 0.2;
        c = c + vec3<f32>(1.0, 0.86, 0.7) * 0.75 * exp(-sb * sb) * (1.0 - 0.7 * side);
    }
    // (white-hot through its cracks, widening as it falls)
    var cq = p2 * 4.2 + vec2<f32>(pl_w(9u), 1.3);
    if (side > 0.5) {
        cq = cq + vec2<f32>(pc.z * 0.35, 0.0);
    }
    let cr = abs(vnoise(cq) - 0.5) + 0.35 * abs(vnoise(cq * 2.3 + 4.0) - 0.5) * 0.4;
    let w = (0.008 + 0.05 * f.crack) * smoothstep(0.0, 0.15, f.crack + f.heat * 0.2);
    let inc = smoothstep(w, w * 0.35, cr) * step(0.01, f.crack);
    let hot = mix(vec3<f32>(5.0, 1.6, 0.35), vec3<f32>(7.0, 6.0, 4.4), smoothstep(w * 0.7, 0.0, cr));
    c = mix(c, hot, inc);
    // (its edges burning: violet at the very edge, magenta, then orange in from it)
    let eb = exp(d / 0.065);
    var burn = mix(vec3<f32>(2.6, 0.85, 0.22), vec3<f32>(2.3, 0.32, 1.4), smoothstep(0.25, 0.7, eb));
    burn = mix(burn, vec3<f32>(0.95, 0.3, 2.4), smoothstep(0.72, 1.0, eb));
    let flick = 0.7 + 0.3 * vnoise(p2 * 9.0 + vec2<f32>(t * 3.1, -t * 2.3));
    c = c + burn * eb * f.heat * f.heat * flick * 1.3;
    // (heating through as it falls: white-hot from inside, its faces glowing)
    c = c + vec3<f32>(1.0, 0.82, 0.62) * f.heat * f.heat * 0.45 * (1.0 - 0.4 * side);
    return vec4<f32>(c, h.t);
}
// The glow round the star as it burns (hidden behind the land nearer than it).
fn ss_glow(f: SsFrame, rd: vec3<f32>, scene_len: f32, t: f32) -> vec3<f32> {
    let tO = dot(rd, f.O);
    if (tO <= 0.0) {
        return vec3<f32>(0.0);
    }
    let dp = length(rd * tO - f.O);
    let k = exp(-pow(dp / (1.25 * f.R), 2.0)) * 0.45 + 0.22 / (1.0 + pow(dp / (0.9 * f.R), 2.0));
    let seen = smoothstep(tO - 1.4 * f.R, tO - 0.3 * f.R, scene_len);
    let hue = mix(vec3<f32>(1.9, 0.45, 1.25), vec3<f32>(2.3, 0.95, 0.3), 0.5 + 0.5 * sin(t * 1.3));
    return hue * k * (0.12 + f.heat * f.heat) * seen * 0.55;
}

// ---- the smoke along the trenches: each point's wake, laid as it ploughs out (part of the column's body: pl_column) --
const SS_LEG_R0: f32 = 40.0;       // from this far out (the column stands in the middle)
const SS_LEG_GONE: f32 = 30.0;     // and gone this long after it strikes

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
// where that stage drew them; `up_e`: the column's distance, and whether a piece of debris may be near this pixel).
fn sixstars(in: StageIn, stage: u32, up: vec4<f32>, up_e: vec2<f32>) -> PlOut {
    let up_t = up_e.x;
    var uv = in.uv;
    let time = now();
    // (the picture bent round the star's slot as it leaves: everything behind the screen's stars drawn as from there)
    var bend = vec4<f32>(0.0);
    if (stage != 1u) {
        bend = ss_bend(in.position.xy, time);
        uv = clamp(uv + bend.xy * frame.resolution.zw, 0.5 * frame.resolution.zw, vec2<f32>(1.0) - 0.5 * frame.resolution.zw);
    }
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let px_a = frame.view_params.w / frame.resolution.y;      // (the angle a pixel spans)
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;              // the strike's point, on the target's ground
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z) - cam;
    let dme = length((me - C).xz);
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    // (the light: the sun's, warm orange-red as it nears the horizon and fading out as it sets; under the horizon the
    // moon's, faint and cold, from the other side of the sky)
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    var warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    var L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));

    var d = 0.0;
    if (stage == 1u) {
        // (the two by two of the picture's pixels this one stands for: its middle, and alternately the nearest and the
        // farthest of their depths, so that at an edge both sides are marched and the join finds the one it matches)
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
        // (through depth_at at each pixel's middle, not textureLoad: OpenGL can't load from a depth texture)
        let d0 = depth_at((vec2<f32>(q) + 0.5) * frame.resolution.zw);
        let d1 = depth_at((vec2<f32>(f32(q1.x), f32(q.y)) + 0.5) * frame.resolution.zw);
        let d2 = depth_at((vec2<f32>(f32(q.x), f32(q1.y)) + 0.5) * frame.resolution.zw);
        let d3 = depth_at((vec2<f32>(q1) + 0.5) * frame.resolution.zw);
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
    var amb = mix(vec3<f32>(0.03, 0.035, 0.05), skyl * 0.85 + vec3<f32>(0.04), day);
    var sunc = mix(vec3<f32>(1.35, 1.24, 1.06), mix(vec3<f32>(1.5, 0.68, 0.3), vec3<f32>(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun.y)), warm) * sun_up + vec3<f32>(0.07, 0.09, 0.14) * moon;
    // (the haze along the horizon, reddened by a low sun: the light the sky gives from round about)
    let fogl = srgb_to_linear(frame.fog_color.rgb);
    var haze_c = mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day);
    // (the golden hour: the low sun's light, the lavender sky's, the peach haze, as the stars climb)
    let ss_l = ss_level(time);
    let ss_s = select(0.0, ss_hold(time, ss_l), ss_have());
    let Ls = ss_sun();
    L = normalize(mix(L, Ls, ss_s));
    warm = mix(warm, 0.9, ss_s);
    sunc = mix(sunc, vec3<f32>(1.55, 0.92, 0.55), ss_s);
    skyl = mix(skyl, vec3<f32>(0.52, 0.42, 0.7), ss_s);
    amb = mix(amb, vec3<f32>(0.3, 0.22, 0.42), ss_s);
    haze_c = mix(haze_c, vec3<f32>(0.95, 0.55, 0.5), ss_s);

    // ---- the sky and the world turned to the golden hour (the sky replaced whole, the land graded) ------------------
    if (stage != 1u && ss_have()) {
        let sp = ss_s;
        if (sp > 0.0) {
            if (sky) {
                var skyc = ss_sunset(rd);
                let cl = ss_clouds(rd, time);
                skyc = mix(skyc, cl.rgb, cl.a);
                skyc = skyc + ss_sky_sun(rd, time) * (1.0 - 0.85 * cl.a);
                col = mix(col, skyc, sp);
            } else {
                // (the land far off shimmering in the heat, more with each star)
                {
                    let amp = (ss_l / 6.0) * 0.0024 * smoothstep(40.0, 300.0, scene_len) * sp;
                    if (amp > 0.0) {
                        let off = vec2<f32>(gnoise3(vec3<f32>(in.position.xy / 22.0, time * 1.7)) - 0.5, gnoise3(vec3<f32>(in.position.xy / 31.0 + 9.0, time * 1.3)) - 0.5) * amp;
                        col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv + off, 0.0).rgb);
                    }
                }
                col = ss_grade(col, scene_len, rd, sp);
            }
        }
    }
    // ---- the trenches burning behind the points as they plough out, the crater's floor glowing, cooling ----------
    if (stage != 1u && !sky && have && ss_have() && a > 0.0 && a < 26.0) {
        let q = rel - C;
        let rr = length(q.xz);
        let tipR = pl_w(12u);
        if (rr < tipR * 1.05) {
            let gl = pl_land(q.xz, 0.0).x;
            if (q.y < gl + 3.0) {
                let rel_a = (atan2(q.z, q.x) - pl_w(9u)) - floor((atan2(q.z, q.x) - pl_w(9u)) / TAU) * TAU;
                let kk = round(rel_a / (TAU / 5.0));
                let dd = abs(rel_a - kk * TAU / 5.0);
                let p1 = vec2<f32>(tipR, 0.0);
                let p2 = pl_w(13u) * vec2<f32>(cos(0.6283), sin(0.6283));
                let e = p2 - p1;
                let edge = p1.x * e.y / max(cos(dd) * e.y - sin(dd) * e.x, 1.0e-4);
                let u = rr / edge;
                let tp = ss_plough_t(rr);
                if (u < 1.0 && a > tp) {
                    let s2 = a - tp;
                    let g = (exp(-s2 / 3.5) * 0.85 + 0.3 * exp(-s2 / 14.0)) * smoothstep(0.0, 0.08, s2);
                    let n = vnoise(q.xz / 5.0 + vec2<f32>(a * 0.7, 0.0));
                    let core = pow(saturate(1.0 - u), 0.5);
                    let lava = mix(vec3<f32>(2.2, 0.5, 0.08), vec3<f32>(3.0, 1.3, 0.3), n);
                    col = col + lava * g * (0.3 + 0.7 * n) * core * 1.6 * k;
                }
            }
        }
    }

    // ---- the flash of the strike lighting the land and the sky round it ---------------------------------------------
    var flash = 0.0;
    if (stage != 1u && a > 0.0 && a < 3.0) {
        flash = select(exp(-a / 0.16) + 0.25 * exp(-a / 0.9), 0.45 * exp(-a / 0.5) + 0.25 * exp(-a / 0.9), ss_soft());
        let Pf = C + vec3<f32>(0.0, 25.0, 0.0);
        let df = length(Pf);
        let cth = dot(rd, Pf / df);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let fire_c = vec3<f32>(3.2, 1.55, 0.5);
        // (the glow in the air round it, seen through anything: it lights the haze)
        col = col + fire_c * flash * (0.12 / (1.0 + pow(th / 0.035, 2.0)) + 0.025 * exp(-th / 0.4)) * k;
        // (and the land near it lit orange)
        if (!sky) {
            let dl = length(rel - Pf);
            col = col + scene * fire_c * flash * 2.0 / (1.0 + pow(dl / 110.0, 2.0)) * k;
        }
    }

    // ---- the column's shadow on the land: the sun's light through its own billows, marched from the land towards the
    // sun, so it falls where the column really is (under it at noon, long across the land at a low sun); soft --------
    if (stage != 1u && !sky && have && a > 0.3 && a < SS_SMOKE_GONE && L.y > 0.02 && (u32(frame.mod_params[3].w + 0.01) & 1u) == 0u) {
        let T = pl_shadow(rel, L, a, C, ign(in.position.xy));
        col = col * (1.0 - 0.7 * (1.0 - T) * sun_up * k * fade);
    }

    // ---- the trail: a cord of lumpy smoke hung along its path, pale and thin high up, dark grey-brown and dense along
    // the dive, lit orange by the flame just behind the head; as it ages it swells, pales, breaks into beads and puffs,
    // frays and thins away over twenty seconds or so, drifting with the wind ------------------------------------------
    // (the join: the half-size stage's smoke over the picture, where the trail's would go)
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    }
    if (stage != 2u && have && time > PL_SEEN && time < PL_HIT + SS_TRAIL_GONE) {
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
                let rg = 0.65 * length(pg - pa) + 3.4 * SS_TRAIL * (7.0 + 5.5 * sqrt(ag)) + 4.0;
                let tg = max(dot(cg, rd), 0.0);
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
            let dive = smoothstep(PL_TURN - 2.2, PL_TURN + 0.4, te);
            // (smoke rather than vapour: from a second or two after it shows, as in the third clip, where the whole
            // hook it draws is the same grey-brown smoke)
            let smk = smoothstep(PL_SEEN + 1.0, PL_SEEN + 4.0, te);
            // (its core's radius: thin and tight where it is laid, swelling with age; the outer fray to twice that)
            let rad = SS_TRAIL * mix(3.0 + 3.0 * sqrt(age), mix(6.0 + 5.0 * sqrt(age), 7.0 + 5.5 * sqrt(age), dive), smk);
            if (h.x < rad * 3.4) {
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
                let thr = mix(0.32, 0.12, smk) + 0.38 * smoothstep(1.5, 18.0, age);
                let m = (puff - thr) * 3.2 + 0.3 * exp(-age / 0.8);
                let sl = 3.2 * 0.14 * sqrt(0.384 * (1.0 - w1 * w1) + 0.09 * (1.0 - w2 * w2) + 0.0064 * (1.0 - w3 * w3)) + 1.0e-3;
                let dens = saturate(sl * log(1.0 + exp(clamp(m / sl, -30.0, 30.0))));
                // (dense where it is laid, thinning over the next twenty seconds; the vapour fainter)
                let sig = (0.26 * exp(-age / 6.0) + 0.25 * exp(-age / 0.7) * dive) * mix(0.35, 1.0, smk) * fade * (1.0 - smoothstep(PL_HIT + SS_TRAIL_GONE - 4.0, PL_HIT + SS_TRAIL_GONE, time));
                let dtau = sig * prof * dens * 1.6 * rad * gin;
                // (lit on its sunward side and on its lumps' tops, darker in its creases)
                let axis = pa_ + ab * sz;
                let nrm = normalize(cp - axis - rd * (0.6 * rad) + vec3<f32>(0.0, 1.0e-4, 0.0));
                let ln = 0.5 + w1 * (n1 - 0.5);
                let lit = (0.35 + 0.65 * saturate(dot(nrm, L) * 0.5 + 0.5)) * (0.6 + 0.8 * ln * ln);
                // (grey-brown smoke, paler as it spreads thin; the vapour high up a pale grey)
                var alb = mix(vec3<f32>(0.5, 0.5, 0.52), vec3<f32>(0.17, 0.145, 0.125), smk);
                alb = mix(alb, alb * 1.35 + vec3<f32>(0.03), smoothstep(4.0, 20.0, age));
                var c = alb * (sunc * lit * 0.85 + amb * (0.6 + 0.4 * ln));
                // (just behind the head it is lit by the flame: orange, dying back within a second)
                c = c + vec3<f32>(1.9, 0.75, 0.22) * exp(-age / 0.12) * dive * step(time, PL_HIT + 0.3) * (0.4 + 0.6 * ln);
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
                let fh = (1.0 - dive) * exp(-age / 0.45) * step(time, PL_HIT);
                glow = max(glow, vec3<f32>(2.4, 2.3, 2.1) * fh * min(chord * 0.6, 1.2));
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
    if (have && time > PL_HIT - 7.0 && time < PL_HIT + 7.0) {
        let nf = min(i32(pl_w(7u) + 0.5), 32);
        var ftau = 0.0;
        var ftc = vec3<f32>(0.0);
        var fglow = vec3<f32>(0.0);
        for (var f = 0; f < nf; f = f + 1) {
            let b = PL_FR + PL_FW * u32(f);
            let t0 = pl_w(b);
            let s = time - t0;
            if (s <= 0.0) {
                continue;
            }
            let life = pl_w(b + 1u);
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
                            var c = vec3<f32>(0.19, 0.16, 0.14) * (sunc * 0.75 + amb * 0.8);
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

    // (how far off the column stands along this ray, where it is mostly opaque: the dust and debris behind it hidden)
    var col_t = select(1.0e9, up_t, stage == 2u);
    // ---- the column: raymarched, self-shadowed towards the sun, dark at its core, fire in it as it bursts ----------
    // (first a cheap bound round all it could be, a fat stick from under the crater to over its top, leaning with the
    // wind: most of the picture is well clear of it, and need not work out where its eighteen billows are)
    let cgrow = 1.0 + 0.012 * max(a - 6.0, 0.0) + 0.006 * max(a - PL_SOFT0, 0.0);
    let ctop = C + vec3<f32>(0.0, 5.0 + 1.08 * pl_w(5u) * (1.0 + 0.006 * a) * cgrow, 0.0) + pl_wind() * a;
    let cbound = pl_ray_seg(rd, C - vec3<f32>(0.0, 30.0, 0.0), ctop, 0.0, 1.0);
    if (stage != 2u && have && a > 0.0 && a < SS_SMOKE_GONE && cbound.x < 230.0 * cgrow + 80.0) {
        var cl = pl_column(a, C);
        if (cl.n > 0) {
            let tb = pl_box(rd, cl.lo, cl.hi);
            let t1 = min(tb.y, scene_len);
            if (t1 > tb.x) {
                var t = tb.x;
                var tr = 1.0;
                var acc = vec3<f32>(0.0);
                let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
                let H = pl_w(5u);
                // (looking towards a low sun, its edges and thin parts shine: the light through them)
                let ph = 0.8 + (0.5 + 1.6 * warm) * pow(saturate(dot(rd, L)), 5.0);
                // (how far it has settled: its billows going soft, its stem lifting off the ground and thinning
                // first, the whole thinning to nothing over the half-minute after)
                let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
                let lift = H * 0.4 * smoothstep(PL_SOFT0, PL_SOFT1 + 4.0, a) - 30.0;
                let thin = exp(-max(a - PL_SOFT0 - 4.0, 0.0) / 3.5);
                var tmid = 0.0;
                var wmid = 0.0;
                var nl = 0;
                var lc_face = 0.0;
                var lc_bulk = 1.0;
                for (var i = 0; i < 80; i = i + 1) {
                    if (t > t1 || tr < 0.03) {
                        break;
                    }
                    let p = rd * t;
                    let d0 = pl_col_base(&cl, p);
                    if (d0 > 40.0) {
                        // (empty air: leap on, short of where a lump could reach)
                        t = t + d0 - 34.0;
                        continue;
                    }
                    let st = max(5.5, t * 0.011) * (0.75 + 0.5 * j) * (1.0 + 1.5 * soft);
                    let sd = pl_col_sdf(&cl, p, d0, true);
                    // (a soft-edged volume, crisp in places and wispy in others, its fringe torn by the fine fray;
                    // later a broad soft fringe, the stem going first and the rest thinning away as a haze)
                    let ramp = saturate(-sd.x / (sd.z + 26.0 * soft));
                    var den = ramp * mix(saturate(0.15 + 1.7 * sd.w), 1.0, ramp * ramp) * thin;
                    den = den * smoothstep(lift - 25.0, lift + 35.0, p.y - C.y);
                    if (soft > 0.0 && den > 0.002) {
                        // (and mottled, the haze uneven in wisps and clots)
                        let mt = gnoise3((p + cam) * (1.0 / 11.0) - pl_wind() * (a * 0.09) + vec3<f32>(0.0, -0.05 * a, 0.0));
                        den = den * mix(1.0, saturate(0.2 + 1.6 * mt), soft);
                    }
                    if (den > 0.002) {
                        // (the sun: the lumps' own faces (a look a few blocks towards it, at the big and middling
                        // lumps), gently, and the column's bulk between it and the sun (three looks further on): sunlit
                        // tops and edges, the side and underside away from it in deep shadow)
                        // (looked for afresh while what lies behind still shows through much, and kept once it hardly
                        // does: deep in it they cost as much and show little)
                        // (as it thins, looked for every fourth step: the haze shows little of it, and its every step lit was most of its cost)
                        if ((tr > 0.25 && nl % select(1, 4, soft > 0.25) == 0) || nl == 0) {
                            let fp = p + L * 5.0;
                            lc_face = pl_col_sdf(&cl, fp, pl_col_base(&cl, fp), false).x - sd.x;
                            // (the bulk's shadow: three looks further on, each soft, a broad ramp through the bulk's
                            // edge, so the shadow of a smooth body inside it never draws a hard straight terminator)
                            let s1 = saturate((8.0 - pl_col_base(&cl, p + L * 11.0)) / 22.0);
                            let s2 = saturate((8.0 - pl_col_base(&cl, p + L * 30.0)) / 30.0);
                            let s3 = saturate((6.0 - pl_col_base(&cl, p + L * 62.0)) / 40.0);
                            lc_bulk = exp(-(s1 * 10.0 + s2 * 18.0 + s3 * 22.0) * 0.3);
                        }
                        nl = nl + 1;
                        let lam = mix(saturate(0.2 + lc_face / 5.0), 0.65, soft);
                        let tsun = mix(lc_bulk, 0.7, soft) * lam;
                        let hy = saturate((p.y - C.y) / max(H, 1.0));
                        // (smoke and dust, tan-grey, lit by the scene: warm where the sun is on it, greyed by the sky on
                        // its shadowed side, darker down its stem and deep in it (no dark rims round each lump: only
                        // the creases a little shaded); browner and dustier at its foot, a little greyer up top, and
                        // uneven through it; once it settles, evenly lit)
                        let deep = saturate(-d0 / 45.0);
                        let ao = mix((0.65 + 0.35 * sd.y) * (1.0 - 0.55 * deep), 0.75, soft);
                        let mv = 0.9 + 0.2 * (sd.w - 0.5) + 0.25 * (sd.y - 0.5);
                        let alb = mix(vec3<f32>(0.15, 0.105, 0.075), vec3<f32>(0.05, 0.046, 0.046), smoothstep(0.04, 0.4, hy)) * mv;
                        let skyg = mix(mix(skyl, vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.45), fogl, 0.15) * (1.0 - 0.35 * warm);
                        var c = alb * (skyg * (0.48 * ao * (0.3 + 0.7 * hy)) + vec3<f32>(0.2, 0.17, 0.13) * day * (1.0 - 0.6 * warm) * ao + sunc * vec3<f32>(0.95, 0.85, 0.72) * (1.05 * tsun * ph));
                        // (fire in it as it bursts: low down, dying fast)
                        let core = exp(min(d0, 0.0) / 26.0);
                        let fire = (exp(-a / 0.35) + 0.4 * exp(-a / 1.3)) * exp(-max(p.y - C.y, 0.0) / (18.0 + 32.0 * min(a, 3.0))) * core * core;
                        c = c * (1.0 - saturate(fire * 2.0)) + mix(vec3<f32>(2.4, 0.62, 0.12), vec3<f32>(3.4, 1.45, 0.3), sd.y) * saturate(fire * 1.6);
                        let ext = den * 0.4 * st;
                        let al = 1.0 - exp(-ext);
                        acc = acc + tr * al * c;
                        tmid = tmid + tr * al * t;
                        wmid = wmid + tr * al;
                        tr = tr * (1.0 - al);
                    }
                    // (outside it, closing in on its edge in short steps, so its fine edge is not lost between them
                    // as grain; through it, the long ones)
                    t = t + select(st, max(0.55 * sd.x, (0.12 * st + 0.25) * min(1.0 + 0.06 * f32(i), 2.5)), sd.x > 0.0);
                }
                if (tr < 0.999) {
                    // (the air between: farther, paler)
                    let dist = tmid / max(wmid, 1.0e-4);
                    if (tr < 0.5) {
                        col_t = dist;
                    }
                    let ap = 1.0 - exp(-dist / 2600.0);
                    let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, ap * 0.8);
                    if (stage == 0u) {
                        col = mix(col, ccol, (1.0 - tr) * k * fade);
                    } else {
                        pl_over(&hc, ccol, (1.0 - tr) * k * fade);
                    }
                }
            }
        }
    }

    // ---- the star: out of the screen into the sky, hanging, falling; once it strikes, its five points ploughing out --
    if (stage != 1u && ss_have() && time >= SS_CONV && time < PL_HIT + SS_PLOUGH + 2.4) {
        var best = vec4<f32>(0.0, 0.0, 0.0, -1.0);
        var glow = vec3<f32>(0.0);
        if (time < PL_HIT) {
            let f = ss_frame(time, C, me);
            if (f.show > 0.0) {
                let tO = dot(rd, f.O);
                let dp = length(rd * tO - f.O);
                if (tO > 0.0 && dp < 1.6 * f.R) {
                    best = ss_draw(f, rd, scene_len, -1, 0.0, time, Ls, sunc, amb);
                }
                glow = ss_glow(f, rd, scene_len, time) * smoothstep(SS_CONV, SS_CONV + 0.12, time);
            }
        } else {
            let tau = time - PL_HIT;
            for (var pk = 0; pk < 5; pk = pk + 1) {
                let f = ss_piece(pk, tau, C);
                if (f.show <= 0.0) {
                    continue;
                }
                let cen = f.O + f.ey * (0.68 * f.R);
                let tO = dot(rd, cen);
                if (tO <= 0.0 || length(rd * tO - cen) > 0.62 * f.R + f.T) {
                    continue;
                }
                let h = ss_draw(f, rd, scene_len, pk, 1.0 - f.show, time, Ls, sunc, amb);
                if (h.w > 0.0 && (best.w < 0.0 || h.w < best.w)) {
                    best = h;
                }
            }
        }
        if (best.w > 0.0) {
            // (behind the column where it is thick: only what of it shows through)
            let vis = select(1.0, 0.04, best.w > col_t);
            col = mix(col, best.rgb, vis * k * fade);
        }
        col = col + glow * k;
    }

    // ---- the dust: marched along the view ray where it crosses the shell behind the front, more sparsely inside ------
    if (stage != 2u && a > 0.0 && a < 16.0) {
        let rf = PL_V * a;
        // (the slab the dust stays in: over the land's lowest and highest ground, where the heightfield is in)
        var ylo = min(C.y, me.y) - 6.0;
        var yhi = max(C.y, me.y) + 45.0;
        if (pl_w(PL_HF) > 1.0) {
            ylo = min(ylo, C.y + pl_w(PL_HF + 2u) - 6.0);
            yhi = max(yhi, C.y + pl_w(PL_HF + 3u) + 45.0);
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
        var t1 = min(min(scene_len, col_t), 1600.0);
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
        let Ro = rf + 12.0;
        let Ri = max(rf - 60.0, 0.0);
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
                    let dc = vec3<f32>(0.62, 0.55, 0.34) * (sunc * 0.75 * lo + amb * 0.6);
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
        if (a > 0.0 && a < 16.0 && pl_w(8u) > 0.5) {
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
                    near = 1.0;
                    break;
                }
            }
        }
        // (how far its ray went, and the column's distance, for the join to match its pixels against and hide what lies
        // behind the column; both kept within a half float)
        return PlOut(hc, vec4<f32>(min(scene_len, 6.0e4), min(col_t, 6.0e4), near, 0.0));
    }
    if ((stage == 0u || up_e.y > 0.0) && a > 0.0 && a < 16.0 && pl_w(8u) > 0.5) {
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
        for (var i = 0; i < PL_DEBRIS; i = i + 1) {
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
        let dirt = vec3<f32>(0.035, 0.03, 0.026) * (amb * 1.5 + sunc * 0.3);
        let smoke = vec3<f32>(0.28, 0.29, 0.31) * (amb * 0.8 + sunc * 0.25);
        col = mix(col, smoke, smk * k * fade);
        col = mix(col, dirt, cov * k * fade);
    }

    // ---- the dust at the eye: as the front washes over the camera, the picture greyed and flattened by the dust in the
    // air, clearing as it settles, and muck thrown on the lens -------------------------------------------------------
    if (a > 0.0 && a < 30.0) {
        let rc = length(C.xz);
        let tau = a - rc / PL_V;                               // since the front reached the eye
        if (tau > -0.1 && rc > 50.0) {
            let land = pl_land(-C.xz, pl_gref(rc, me, C, dme));
            let hc = -C.y - land.x;                            // the eye over the ground
            let E = smoothstep(-0.08, 0.05, tau) * (0.6 * exp(-tau / 0.8) + 0.4 * exp(-tau / 3.5))
                * smoothstep(40.0, 8.0, hc) * smoothstep(2600.0, 900.0, rc) * smoothstep(50.0, 110.0, rc)
                * (1.0 - 0.55 * land.y) * fade * k;
            if (E > 0.002) {
                let dust_c = vec3<f32>(0.5, 0.46, 0.4) * (sunc * 0.55 + amb * 0.8);
                // (the air thick with it: contrast lost, greyed and a little warmed)
                let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
                col = mix(col, mix(vec3<f32>(lum), dust_c, 0.5), 0.22 * E);
                col = col * mix(vec3<f32>(1.0), vec3<f32>(1.03, 0.99, 0.93), E);
                // (a faint film of it on the lens, in soft blotches, fixed to the screen)
                let pxy = in.position.xy;
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
            let vis = smoothstep(40.0, 8.0, hc) * smoothstep(2600.0, 900.0, rc) * smoothstep(60.0, 140.0, rc) * (1.0 - 0.5 * land.y) * k;
            if (vis > 0.0 && tau > 0.2) {
                let pxy = in.position.xy;
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
                col = col * mix(1.0, keep, vis * fade)
                    + vec3<f32>(0.42, 0.38, 0.33) * (sunc * 0.45 + amb * 0.9) * 0.4 * min(shine, 1.0) * vis * fade;
            }
        }
    }

    // ---- the sun's flare on the lens (a long streak across the picture, flaring on each beat) and the stars ---------
    if (ss_have() && ss_s > 0.0) {
        let sp = project_rel(Ls * 5000.0);
        if (sp.z > 0.0 && all(sp.xy > vec2<f32>(-0.2)) && all(sp.xy < vec2<f32>(1.2))) {
            let seen = select(0.0, 1.0, is_sky(depth_at(clamp(sp.xy, vec2<f32>(0.001), vec2<f32>(0.999)))));
            let res = frame.resolution.xy;
            let dpx = (uv - sp.xy) * res;
            let beat = ss_beat(time);
            let amt = ss_s * seen * (0.22 + 0.85 * beat) * (1.0 + ss_l / 6.0);
            let streak = exp(-abs(dpx.y) / (0.005 * res.y)) * exp(-abs(dpx.x) / (0.45 * res.x));
            let glare = exp(-length(dpx) / (0.09 * res.y));
            col = col + (vec3<f32>(1.3, 0.62, 0.58) * streak * 0.55 + vec3<f32>(1.4, 0.8, 0.5) * glare * 0.25) * amt;
        }
    }
    // (the lens rippling out of the slot: its glassy shading, a breath of colour split across it, the light on its
    // edge; then the screen's stars, bent by it too)
    if (bend.z != 0.0) {
        let ow = bend.w * select(1.0, 0.5, ss_soft());
        col = col * (1.0 + 0.14 * bend.z) * (vec3<f32>(1.0) + vec3<f32>(0.18, 0.02, -0.2) * ow)
            + vec3<f32>(1.0, 0.92, 0.88) * 0.13 * smoothstep(0.25, 0.42, ow);
    }
    let hud = ss_hud(in.position.xy + 0.7 * bend.xy, time);
    col = col * (1.0 - hud.a) + hud.rgb;
    // (the star leaving its slot, still the screen's, until it has turned into the star in the world)
    if (ss_have() && time >= SS_PEEL && time < SS_CONV + 0.12) {
        let fy = ss_fly(time, C);
        let x = 1.0 - smoothstep(SS_CONV, SS_CONV + 0.12, time);
        let st = ss_fly_draw(in.position.xy, time, fy) * x;
        col = col * (1.0 - st.a) + st.rgb;
        var gf: SsFrame;
        gf.O = fy.O;
        gf.R = fy.R;
        col = col + ss_glow(gf, rd, 1.0e9, time) * fy.e * x * k;
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

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return sixstars(in, 0u, vec4<f32>(0.0), vec2<f32>(1.0e9, 1.0)).c;
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
    let o = sixstars(in, 1u, vec4<f32>(0.0), vec2<f32>(1.0e9, 1.0));
    return PlHalf(o.c, o.e);
}

// The half-size stage's smoke at this pixel (whose ray goes `len` blocks): the four nearest of its pixels, each weighed
// by how near it is (bilinearly) and by how near the depth it was marched to is to this pixel's, so that across an edge
// against a block or the sky only the ones on this pixel's side count (a joint bilateral upsample); if none is, the
// nearest in depth round it. In .x of the second the column's distance of the one that counts most, in .y whether any of the
// four has debris near it.
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
    var debris = 0.0;
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        let dz = abs(e.x - lp) / max(lp, 1.0);
        debris = max(debris, e.z);
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
        return PlOut(near_c, vec4<f32>(near_t, debris, 0.0, 0.0));
    }
    return PlOut(acc / sw, vec4<f32>(best_t, debris, 0.0, 0.0));
}

@fragment
fn fs_join(in: StageIn) -> @location(0) vec4<f32> {
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let u = pl_up(in.position.xy, len);
    return sixstars(in, 2u, u.c, vec2<f32>(select(u.e.x, 1.0e9, u.e.x >= 6.0e4), u.e.y)).c;
}
// [end half stage]
