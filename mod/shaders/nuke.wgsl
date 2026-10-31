// Orbital Laser's post pass for the Nuke (laser 10): the Payload's (payload.wgsl) grown into a nuclear bomb. Like it,
// the mod builds it from shaders/strike.wgsl up to its fs_main less the other lasers' own functions, followed by this
// file, and sets it for a nuke strike only. Validate with tools/check-shader.sh.

// ---- laser 10: the nuke -------------------------------------------------------------------------------------------
// No beam. The bomb comes in from orbit, a white-hot streak across the sky with a thick trail, sheds its heat, arcs
// over into a steep dive (a finned casing, spinning up, glinting), faster and faster, a vapour collar round it; it bursts
// PL_BURST over the land: a blinding white flash whites out the picture and lights the land and the sky; a fireball
// swells white-orange, rises and darkens into a mushroom cloud hundreds of blocks tall (a fat, churning toroidal cap
// with a ragged underside, glowing orange inside for tens of seconds, a stem pulled up out of the land, a condensation
// ring round the stem, a ground-hugging base surge); the shockwave races out as a shell of distortion over the land,
// raising a wall of dust; debris flies and rains down far round it.
// strike/nuke.rs samples the path into the table (nk_table, render.set-data): keep the PL_* in step with its NK_*.
const PL_SEEN: f32 = 0.8;          // the bomb shows, coming in from orbit white-hot,
const PL_COOL: f32 = 6.0;          // sheds its heat and arcs over into its fall,
const PL_DIVE: f32 = 8.0;          // dives faster and faster, its nose heating again,
const PL_HIT: f32 = 11.0;          // and bursts,
const PL_BURST: f32 = 45.0;        // this high over the target's ground
const PL_LEN: f32 = 90.0;          // the strike's length (lasers.rs): everything fades out over its last PL_FADE
const PL_FADE: f32 = 10.0;
const PL_SOFT0: f32 = 48.0;        // the cloud keeps its crisp billows this long after the burst, then loses them
const PL_SOFT1: f32 = 72.0;        // by this, a soft, drifting haze thinning away (gone by PL_LEN)
const PL_CHURN: f32 = 7.0;        // the roll's lumps carried this long before they are let go (pl_col_sdf)
const PL_DM: f32 = 55.0;           // the most the cloud's lumps stand out of its smooth body (pl_col_sdf), which the
                                   // march's bounds and gates all allow for
const PL_V: f32 = 343.0;           // the shockwave's front, blocks a second (with the blast's sound: nuke.rs)
const PL_P: u32 = 16u;             // the table: the path's samples from PL_P, three words each,
const PL_PF: u32 = 400u;
const PL_PW: u32 = 8u;
const PL_HF: u32 = 1024u;          // the land's heightfield (nuke.rs's nk_hf_words): its size, then heights, shelter
const PL_FR: u32 = 560u;           // the pieces it sheds coming in (none for the nuke)
const PL_FW: u32 = 12u;
const PL_DEBRIS: i32 = 160;
const PL_DB: u32 = 10496u;         // the debris (nuke.rs's nk_debris_words), PL_DW words each
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

// ---- the bomb's shape (the fall's): a casing, its fins, the vapour round it in the dive ------------------------------------------------
const NK_BS: f32 = 1.3;            // the casing's scale: about 16 long and 3.4 across
// A cone from radius r1 at y 0 to r2 at y h, its ends rounded (iq's round cone).
fn nk_rcone(p: vec3<f32>, r1: f32, r2: f32, h: f32) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let b = (r1 - r2) / h;
    let a = sqrt(1.0 - b * b);
    let k = dot(q, vec2<f32>(-b, a));
    if (k < 0.0) {
        return length(q) - r1;
    }
    if (k > a * h) {
        return length(q - vec2<f32>(0.0, h)) - r2;
    }
    return dot(q, vec2<f32>(a, b)) - r1;
}
// The bomb at p (its own frame: y along it, nose first, from its middle): the distance, and what is there (0 the body,
// 1 the fins and tail, 2 the nose, 3 the vapour collar). `spin`: how far it has turned; `vc`: how much of the collar
// there is (none at 0).
fn nk_bomb(p0: vec3<f32>, spin: f32, vc: f32) -> vec2<f32> {
    let p = p0 / NK_BS;
    var d = nk_rcone(p - vec3<f32>(0.0, -4.2, 0.0), 1.3, 1.3, 7.4);
    d = min(d, nk_rcone(p - vec3<f32>(0.0, -6.0, 0.0), 0.75, 1.3, 1.8));
    var m = 0.0;
    let dn = nk_rcone(p - vec3<f32>(0.0, 3.2, 0.0), 1.3, 0.28, 2.9);
    if (dn < d) {
        m = 2.0;
        d = dn;
    }
    // (four fins, turned with it, swept back)
    let cs = cos(spin);
    let sn = sin(spin);
    var f = abs(vec2<f32>(p.x * cs - p.z * sn, p.x * sn + p.z * cs));
    if (f.y > f.x) {
        f = f.yx;
    }
    let df = max(max(f.y - 0.09, f.x - 2.9), max(-6.5 - p.y, p.y + 3.4 + 0.6 * (f.x - 1.0)));
    if (df < d) {
        m = 1.0;
        d = df;
    }
    d = d * NK_BS;
    if (vc > 0.0) {
        // (the vapour collar of its dive near the speed of sound: a thin cone of cloud opening back from its shoulders,
        // growing as it gathers speed)
        let yc = 2.4 * NK_BS - p0.y;
        let rc = length(p0.xz);
        let ln = 9.0 * vc;
        let dcn = abs(dot(vec2<f32>(rc, yc), vec2<f32>(0.82, -0.57))) - 0.25;
        let dv = max(dcn, max(-yc, yc - ln));
        if (dv < d) {
            m = 3.0;
            d = dv;
        }
    }
    return vec2<f32>(d, m);
}

// ---- the mushroom cloud: a fireball rising into a toroidal cap on a stem, a ring round the stem, a base surge -----
struct PlCol {
    a: f32,
    C: vec3<f32>,
    // (the cap: its core circle's height over the ground and radius, the roll's radius about it; the stem's top height
    // and its radius at the foot, in the middle and at the top; the ring round the stem: its height, radius and how
    // much of it shows; the base surge: its radius and its roll's width and height)
    hc: f32,
    Rt: f32,
    rt: f32,
    st: f32,
    sr: vec3<f32>,
    ring: vec3<f32>,
    surge: vec3<f32>,
    lo: vec3<f32>,
    hi: vec3<f32>,
    // (the boil's billows (pl_billows): their middles from C and radii, packed as half floats; bm which of them a ray
    // passes near enough to look up, none unless set)
    bq: array<vec2<u32>, 16>,
    bm: u32,
    // (how deep in the crease between two billows the last point looked up lies: 1 right in it)
    kb: f32,
}
fn pl_column(a: f32, C: vec3<f32>) -> PlCol {
    var o: PlCol;
    o.bm = 0u;
    o.kb = 0.0;
    o.a = a;
    o.C = C + pl_wind() * (0.0 * a);
    // (the fireball: swelling to sixty in half a second, then slowly on; punching up fast, boiling, its stem close behind,
    // to some 250 by four seconds and over four hundred as its rise slows; its roll opening out into the cap's ring)
    o.rt = 56.0 * (1.0 - exp(-a / 0.45)) + 26.0 * (1.0 - exp(-a / 14.0)) + 0.15 * a;
    o.hc = PL_BURST + 385.0 * (1.0 - exp(-a / 7.0)) * smoothstep(0.0, 1.5, a + 0.3);
    o.Rt = 80.0 * (1.0 - exp(-a / 6.0)) + 70.0 * (1.0 - exp(-a / 28.0)) + 0.3 * a;
    // (the stem pulled up out of the land under it, from a couple of seconds on)
    o.st = min(o.hc - 0.15 * o.rt, max(a - 0.6, 0.0) * 95.0);
    o.sr = vec3<f32>(34.0 + 30.0 * saturate(a / 6.0), 20.0 + 8.0 * saturate(a / 20.0), 26.0 + 0.3 * o.Rt);
    // (the condensation ring: a thin white collar round the stem, from 4 s, gone by 30)
    o.ring = vec3<f32>(0.42 * o.hc + 10.0, o.sr.y * 2.0 + 30.0 + 0.6 * a, smoothstep(4.0, 9.0, a) * (1.0 - smoothstep(16.0, 30.0, a)));
    // (the base surge: dust rolling out over the ground round the stem's foot)
    o.surge = vec3<f32>(30.0 + 95.0 * (1.0 - exp(-a / 10.0)), 20.0 + 0.1 * a, 7.0 + 7.0 * saturate(a / 12.0));
    let top = o.hc + 1.4 * o.rt;
    let w = max(o.Rt + o.rt * 1.6, o.surge.x + o.surge.y) + 90.0;
    let lean = pl_wind() * a;
    o.lo = C + vec3<f32>(-w + min(lean.x, 0.0), -20.0, -w + min(lean.z, 0.0));
    o.hi = C + vec3<f32>(w + max(lean.x, 0.0), top + 90.0, w + max(lean.z, 0.0));
    return o;
}
// The cloud's lean with the wind at p (its head carried furthest, its foot staying put).
fn pl_lean(col: ptr<function, PlCol>, hy: f32) -> vec3<f32> {
    return pl_wind() * ((*col).a * pow(saturate(hy / max((*col).hc, 1.0)), 1.5));
}
const PL_NB: u32 = 16u;            // the boil's billows: the first PL_NBC in the fireball and the cap, the rest up the stem
const PL_NBC: u32 = 12u;
// A billow's uniform random k (0 to 1) for billow i in its life n.
fn pl_bh(i: u32, n: i32, k: u32) -> f32 {
    return f32(pcg(pcg(i * 0x9e37u + bitcast<u32>(n) * 0x85ebu + 0x2c1u) + k * 0x68e3u) & 0xffffu) / 65535.0;
}
// The boil (Plumbbob Fizeau's first fifteen seconds): billows welling up inside the fireball, swelling out through its
// surface as they ride round its roll (up its inside, out over its top, down its outside), each a lobe standing out of
// the one beside it, then sinking back into it as the next wells up; up the stem, billows of dust and smoke climbing
// into the cap. Each is born at nothing deep in the body and dies back into it, so none pops in or out. Their middles
// from C (leaning with the wind) and radii, worked out once a ray, packed into the column's bq.
fn pl_billows(col: ptr<function, PlCol>) {
    let a = (*col).a;
    let Rt = (*col).Rt;
    let rt = (*col).rt;
    let hc = (*col).hc;
    let envc = smoothstep(0.02, 0.5, a) * (1.0 - smoothstep(11.0, 24.0, a));
    let envs = smoothstep(0.8, 2.5, a) * (1.0 - smoothstep(10.0, 22.0, a));
    for (var i = 0u; i < PL_NB; i = i + 1u) {
        var c = vec3<f32>(0.0);
        var r = 0.0;
        if (i < PL_NBC) {
            // (its life: some three to four seconds, slower as the cloud calms, each a different phase)
            let lf = 2.6 + 1.6 * pl_bh(i, -1, 0u);
            let s = (a + 0.6 * a * a / (a + 12.0)) / lf + pl_bh(i, -1, 1u) * 0.999;
            let n = i32(floor(s));
            let u = fract(s);
            // (round the axis at its own bearing, drifting; round the roll from low inside out over the top)
            let ph = 6.2832 * pl_bh(i, n, 2u) + 0.25 * (pl_bh(i, n, 3u) - 0.5) * a;
            let th0 = 0.8 + 2.3 * pl_bh(i, n, 4u);
            let th = th0 - u * (1.3 + 1.0 * pl_bh(i, n, 5u));
            let R = rt * (0.25 + 0.7 * smoothstep(0.0, 0.6, u));
            let sn = sin(th);
            let rho = Rt + R * cos(th);
            let y = hc + R * sn * select(0.6, 0.95, sn > 0.0) + 0.3 * rt * max(sn, 0.0);
            c = vec3<f32>(cos(ph) * rho, y, sin(ph) * rho);
            r = rt * (0.4 + 0.25 * pl_bh(i, n, 6u)) * pow(sin(3.1416 * u), 0.6) * envc;
        } else {
            // (up the stem: from its foot to its top, and into the cap)
            let lf = 1.8 + 0.9 * pl_bh(i, -1, 0u);
            let s = a / lf + pl_bh(i, -1, 1u) * 0.999;
            let n = i32(floor(s));
            let u = fract(s);
            let y = (0.1 + 0.95 * u) * (*col).st;
            let ph = 6.2832 * pl_bh(i, n, 2u);
            let sr = (*col).sr;
            let rs = mix(mix(sr.x, sr.y, smoothstep(0.0, 0.3, u)), sr.z, smoothstep(0.65, 1.0, u));
            c = vec3<f32>(cos(ph), 0.0, sin(ph)) * (0.45 * rs) + vec3<f32>(0.0, y, 0.0);
            r = rs * (0.7 + 0.25 * pl_bh(i, n, 3u)) * pow(sin(3.1416 * u), 0.5) * envs * step(1.0, (*col).st);
        }
        c = c + pl_lean(col, c.y);
        (*col).bq[i] = vec2<u32>(pack2x16float(c.xy), pack2x16float(vec2<f32>(c.z, r)));
    }
}
// Which billows a ray from the camera along rd may come near enough to be looked up (within `m` of their surfaces).
fn pl_bmask(col: ptr<function, PlCol>, rd: vec3<f32>, m: f32) -> u32 {
    var bm = 0u;
    for (var i = 0u; i < PL_NB; i = i + 1u) {
        let qa = unpack2x16float((*col).bq[i].x);
        let qb = unpack2x16float((*col).bq[i].y);
        if (qb.y > 0.5) {
            let c = (*col).C + vec3<f32>(qa, qb.x);
            let tc = max(dot(c, rd), 0.0);
            if (length(c - rd * tc) < qb.y + m) {
                bm = bm | (1u << i);
            }
        }
    }
    return bm;
}
// The billows the ray looks up, melted into the cloud's body d at p (from C, leaning).
fn pl_bunion(col: ptr<function, PlCol>, pc: vec3<f32>, d0: f32) -> f32 {
    var d = d0;
    var kb = 0.0;
    var m = (*col).bm;
    loop {
        if (m == 0u) {
            break;
        }
        let i = firstTrailingBit(m);
        m = m & (m - 1u);
        let qa = unpack2x16float((*col).bq[i].x);
        let qb = unpack2x16float((*col).bq[i].y);
        let db = length(pc - vec3<f32>(qa, qb.x)) - qb.y;
        let k = 0.2 * qb.y + 4.0;
        let h = saturate(0.5 + 0.5 * (db - d) / k);
        kb = max(kb, 4.0 * h * (1.0 - h));
        d = mix(db, d, h) - k * h * (1.0 - h);
    }
    (*col).kb = kb;
    return d;
}
// The cloud's smooth body at p (camera-relative): the cap (the roll round its core circle, a dome over it), the stem,
// the base surge; and in .y how much of the ring is there instead (the ring kept apart: it is white).
fn pl_col_base2(col: ptr<function, PlCol>, p: vec3<f32>) -> vec2<f32> {
    let C = (*col).C;
    let hy0 = p.y - C.y;
    let q = p - C - pl_lean(col, hy0);
    let hy = q.y;
    let rho = length(q.xz);
    let Rt = (*col).Rt;
    let rt = (*col).rt;
    let hc = (*col).hc;
    // (the cap: a fat roll, its underside a little flattened, a dome over its middle. As the ring forms its outer edge
    // curls down and under, hanging lower than its inner edge, where the air is drawn in and up)
    let fold = smoothstep(3.0, 14.0, (*col).a);
    let lo_k = mix(1.6, mix(1.9, 1.12, smoothstep(-0.4 * rt, 0.6 * rt, rho - Rt)), fold);
    let tq = vec2<f32>(rho - Rt, (hy - hc) * select(1.6, lo_k, hy < hc));
    var d = length(tq) - rt;
    // (the dome over it higher than the roll's top, so the cap is one rounded crown, not two lobes with a dip between)
    // (an ellipsoid's distance near enough true all round it, not squeezed sideways: squeezed, the dome's smoke
    // thickened too slowly into it and its middle was a thin haze the glow showed through)
    let er = vec3<f32>(Rt + 0.8 * rt, 1.0 * rt, Rt + 0.8 * rt);
    let eq = vec3<f32>(q.x, hy - hc - 0.3 * rt, q.z);
    let ek0 = length(eq / er);
    var dome = ek0 * (ek0 - 1.0) / max(length(eq / (er * er)), 1.0e-6);
    // (its underside drawn up into a hollow as the ring forms, the stem rising into it: from a ball with a flat bottom
    // to a cap over an open ring, by degrees)
    dome = max(dome, hc - mix(0.9, 0.12, fold) * rt - hy);
    d = smin(d, dome, 0.35 * rt);
    // (the stem: from under the land up into the cap, wide at its dusty foot, narrow in the middle, flaring into the cap)
    if ((*col).st > 0.0) {
        let u = saturate(hy / max((*col).st, 1.0));
        let sr = (*col).sr;
        let rs = mix(mix(sr.x, sr.y, smoothstep(0.0, 0.3, u)), sr.z, smoothstep(0.65, 1.0, u)) * (0.92 + 0.16 * sin(hy * 0.045 + 1.3));
        let ds = max(rho - rs, max(hy - (*col).st, -hy - 20.0));
        d = smin(d, ds, 26.0);
    }
    // (the base surge: a low roll of dust round the foot, out where the land is)
    let sg = (*col).surge;
    if ((*col).a > 0.2) {
        let e = vec2<f32>((rho - sg.x) / sg.y, (hy - 0.3 * sg.z) / sg.z);
        let inner = vec2<f32>(max(sg.x - rho, 0.0) / (sg.x * 0.9), 0.0);
        let k0 = length(e);
        let ds = (k0 - 1.0) * min(sg.y, sg.z);
        // (a roll, not a disc: thin inside it, thinning away as the dust settles)
        // (and rising out of the ground as the blast reaches it, not there all at once)
        let settle = 30.0 * smoothstep(14.0, 50.0, (*col).a) + 40.0 * (1.0 - smoothstep(0.2, 2.5, (*col).a));
        d = smin(d, ds + 14.0 * smoothstep(0.0, 0.6, inner.x) + settle, 22.0);
        // (and a low sheet of dust inside the roll, from it in to the stem's foot: a skirt, not a tyre)
        let sheet = max(rho - sg.x, abs(hy - 0.2 * sg.z) - 0.32 * sg.z);
        d = smin(d, sheet + 11.0 + settle, 18.0);
    }
    // (the boil's billows, those the ray looks up)
    (*col).kb = 0.0;
    if ((*col).bm != 0u) {
        d = pl_bunion(col, p - C, d);
    }
    // (the ring round the stem: a thin flat collar)
    var dr = 1.0e6;
    let rg = (*col).ring;
    if (rg.z > 0.01) {
        let e = vec2<f32>((rho - rg.y) / 34.0, (hy - rg.x) / 13.0);
        dr = (length(e) - 1.0) * 13.0;
    }
    return vec2<f32>(d, dr);
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
        // (one hash a cell, three words: its jitter, and its size)
        let h = pcg3d(q + vec3<u32>(0u, 0u, 0x51u));
        let jit = vec3<f32>(h >> vec3<u32>(22u)) * (0.7 / 1023.0) + 0.15;
        let sz = 0.7 + 0.55 * f32((h.x >> 12u) & 1023u) / 1023.0;
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
// The cloud's lumps at material point qm: the big swell, the bend of the big lumps, the big lumps and the middling ones.
fn pl_nz(qm: vec3<f32>) -> vec4<f32> {
    let S = 2.2;
    let w = gnoise3(pl_rot(1, qm * (1.0 / (55.0 * S))));
    let w2 = gnoise3(pl_rot(2, qm * (1.0 / (23.0 * S)) + vec3<f32>(9.2, 0.0, 4.4)));
    let b1 = pl_dome(pl_rot(0, qm * (1.0 / (36.0 * S)) + vec3<f32>(3.1, 0.0, 7.7) + 0.3 * vec3<f32>(w2 - 0.5)));
    let b2 = pl_dome(pl_rot(1, qm * (1.0 / (14.0 * S)) + vec3<f32>(0.0, 0.0, 1.3)));
    return vec4<f32>(w, w2, b1, b2);
}
// And its small lumps and its fray.
fn pl_nz_fine(qm: vec3<f32>) -> vec2<f32> {
    let S = 2.2;
    return vec2<f32>(pl_dome(pl_rot(2, qm * (1.0 / (5.5 * S)) + vec3<f32>(1.7, 0.0, -2.1))), gnoise3(pl_rot(0, qm * (1.0 / (1.8 * S))) + vec3<f32>(5.0, 1.0, 0.0)));
}
// The cloud's surface at p: its smooth body bulged out in lumps on lumps (as the Payload's column). The lumps are its
// material's, looked up where that material started, so they move with it and none ever comes from nowhere: up the
// stem with the rising air; in the cap, carried up with it, swelling as it swells, and round its roll (up the inside,
// out over the top, down the outside, back in under it). .x the distance, .y how far up a dome it lies, .z how soft
// its edge is, .w the fine fray.
fn pl_col_sdf(col: ptr<function, PlCol>, p: vec3<f32>, d0: f32, fine: bool) -> vec4<f32> {
    let a = (*col).a;
    let C = (*col).C;
    let q = p - C - pl_lean(col, p.y - C.y);
    let Rt = (*col).Rt;
    let rt = (*col).rt;
    let hc = (*col).hc;
    let rho = max(length(q.xz), 1.0e-3);
    let dir = q.xz / rho;
    // (the cap's own frame: about its core, scaled with it, turned round its roll by how far it has churned, most
    // through the roll and none on the axis, where the two sides would part in a seam)
    let uv = vec2<f32>(rho - Rt, q.y - hc);
    let wq = dot(uv, uv) / pow(1.9 * rt, 2.0);
    let wr = exp(-wq) * smoothstep(0.0, 0.8 * Rt + 10.0, rho);
    let ang = 1.25 * (1.0 - exp(-a / 6.0)) * wr;
    let cs = cos(ang);
    let sn = sin(ang);
    let uvr = vec2<f32>(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);
    let sc = 150.0 / (Rt + rt);
    var qc = vec3<f32>(dir.x * (Rt + uvr.x) * sc, uvr.y * sc + 400.0, dir.y * (Rt + uvr.x) * sc);
    // (the stem's: rising with the air drawn up it, the same all the way down to the land)
    var qs = q - vec3<f32>(0.0, 6.0 * a, 0.0);
    // (the boil: for its first seconds the fireball's lumps are flung about by a churning flow of its own, racing up
    // through it, tumbling over each other; it calms over the next ten seconds into the slow roll. The lumps are pushed
    // about, not made: the same ones, carried)
    let bo = exp(-a / 4.0) * smoothstep(0.0, 0.5, a);
    let wc0 = smoothstep(hc - 1.45 * rt, hc - 1.1 * rt, q.y);
    if (bo > 0.03 && wc0 > 0.02) {
        let wq0 = qc * (1.0 / 30.0) + vec3<f32>(0.0, -1.1 * a, 0.0);
        let wv = vec3<f32>(gnoise3(wq0), gnoise3(wq0 + vec3<f32>(5.2, 1.7, 1.3)), gnoise3(wq0 + vec3<f32>(2.1, 3.9, 8.4))) - vec3<f32>(0.5);
        qc = qc + wv * (70.0 * bo);
    }
    if (bo > 0.03 && wc0 < 0.98) {
        let ws0 = qs * (1.0 / 24.0) + vec3<f32>(0.0, -1.6 * a, 0.0);
        let ws = vec3<f32>(gnoise3(ws0), gnoise3(ws0 + vec3<f32>(5.2, 1.7, 1.3)), gnoise3(ws0 + vec3<f32>(2.1, 3.9, 8.4))) - vec3<f32>(0.5);
        qs = qs + ws * (45.0 * bo);
    }
    // (the one over the other through the neck under the cap: the two looked up and their lumps faded across)
    let wc = wc0;
    var nz = vec4<f32>(0.0);
    // (the spread two fadings together lose put back)
    let ls = 1.0 / sqrt(wc * wc + (1.0 - wc) * (1.0 - wc));
    if (wc > 0.98) {
        nz = pl_nz(qc);
    } else if (wc < 0.02) {
        nz = pl_nz(qs);
    } else {
        nz = vec4<f32>(0.5, 0.5, 0.62, 0.62) + (mix(pl_nz(qs), pl_nz(qc), wc) - vec4<f32>(0.5, 0.5, 0.62, 0.62)) * ls;
    }
    let w = nz.x;
    let w2 = nz.y;
    let b1 = nz.z;
    let b2 = nz.w;
    let hy = p.y - C.y;
    let lump = 1.6 * (0.6 + 0.4 * smoothstep(20.0, 160.0, hy));
    let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
    let crisp = 1.0 - 0.8 * soft;
    let up = smoothstep(40.0, 200.0, hy);
    // (the crown over the middle smoother than the roll: its big swells let down, so it stays one rounded dome)
    let crown = (1.0 - smoothstep(0.3 * (*col).Rt, (*col).Rt + 0.3 * (*col).rt, rho)) * smoothstep((*col).hc, (*col).hc + 0.5 * (*col).rt, hy);
    var d = d0 - (26.0 * (b1 - 0.45) * crisp * (0.4 + 0.6 * up) * (1.0 - 0.2 * crown) + 9.0 * (b2 - 0.45) * (1.0 - 0.7 * soft) + (18.0 + 8.0 * soft) * (w - 0.5) * (1.0 - 0.35 * crown) + 8.0 * (w2 - 0.5)) * lump;
    let ew = smoothstep(0.6, 0.82, w2);
    let edge = mix(1.5, 6.0, ew) + 10.0 * (1.0 - smoothstep(0.0, 60.0, hy));
    var fray = 0.5;
    if (fine && d < 20.0 && soft < 0.99) {
        // (looked up only near the surface the bigger lumps make)
        var nf = vec2<f32>(0.5);
        if (wc > 0.98) {
            nf = pl_nz_fine(qc);
        } else if (wc < 0.02) {
            nf = pl_nz_fine(qs);
        } else {
            nf = vec2<f32>(0.62, 0.5) + (mix(pl_nz_fine(qs), pl_nz_fine(qc), wc) - vec2<f32>(0.62, 0.5)) * ls;
        }
        let b3 = nf.x;
        d = d - 4.0 * (b3 - 0.45) * (1.0 - soft) * lump;
        fray = nf.y;
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
    if (sg.x > max(cs.Rt + cs.rt, cs.surge.x + cs.surge.y) + 40.0) {
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
    let hw = (9.0 + 0.012 * r) * rise * (0.35 + 1.2 * n1) * (0.6 + 0.8 * n3) + 1.5 * min(since, 6.0);
    let up = smoothstep(hw, hw * 0.35, h) * smoothstep(-4.0, 0.0, h);
    let lead = smoothstep(-3.0, 1.5, s);
    let wall = 1.6 * exp(-s / (18.0 + 0.02 * r)) * (0.75 + 0.25 * side) * (1.0 - 0.6 * sh);
    let haze = (0.009 * exp(-since / 2.5) + 0.0025 * exp(-since / 6.0)) * (0.5 + n2);
    // (none round the column's foot: the blast cleared it, and it would tint the smoke)
    let mid = smoothstep(80.0, 230.0, r);
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
fn nuke(in: StageIn, stage: u32, up: vec4<f32>, up_e: vec3<f32>) -> PlOut {
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
    let Pb = C + vec3<f32>(0.0, PL_BURST, 0.0);
    if (stage != 1u && a > 0.0 && a < 9.0) {
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
            if (th > 0.0 && th < scene_len + 4.0 && hp.y > C.y - 4.0) {
                // (grazing: the shell seen edge-on, a band some tens of blocks thick along its outline)
                let edge = exp(-sq / (0.045 * Rs + 8.0));
                let sf = (1.0 - smoothstep(4.0, 9.0, a)) * k;
                let pb = project_rel(Pb);
                var dirs = uv - pb.xy;
                if (pb.z < 0.0) {
                    dirs = -dirs;
                }
                let off = normalize(dirs + vec2<f32>(1.0e-5)) * (0.012 * edge + 0.003 * exp(-sq / (0.25 * Rs))) * sf;
                let sc = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv - off, 0.0).rgb);
                col = mix(col, sc, saturate(edge * 4.0 + 0.5) * sf);
                col = col + vec3<f32>(0.9, 0.93, 1.0) * (0.22 * edge + 0.03 * exp(-sq / (0.3 * Rs))) * exp(-a / 1.6) * sf * (0.3 + 0.7 * day);
            }
        }
    }

    // ---- the flash: the burst lighting the land and the sky, white then orange, the sky staying brighter a while ----
    // (the light it gives: blinding for a moment, strong for seconds, a glow under the cloud for tens of seconds)
    let fl = select(0.0, 9.0 * exp(-a / 0.25) + 1.6 * exp(-a / 2.5) + 0.35 * exp(-a / 16.0), a > 0.0) * fade;
    if (stage != 1u && a > 0.0) {
        let Pf = C + vec3<f32>(0.0, PL_BURST + 80.0 * saturate(a / 15.0), 0.0);
        let df = length(Pf);
        let cth = dot(rd, Pf / df);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let fire_c = mix(vec3<f32>(3.0, 1.35, 0.42), vec3<f32>(3.2, 3.0, 2.8), exp(-a / 0.6));
        // (the glow in the air round it, seen through anything: it lights the haze)
        col = col + fire_c * fl * (0.05 / (1.0 + pow(th / 0.08, 2.0)) + 0.012 * exp(-th / 0.7)) * k;
        if (sky) {
            // (the sky itself brighter, warm, for a while)
            col = col + vec3<f32>(1.0, 0.78, 0.52) * (0.3 * exp(-a / 2.0) + 0.08 * exp(-a / 20.0)) * (0.35 + 0.65 * (1.0 - day)) * k * fade;
        } else {
            // (and the land lit by it, far out)
            let dl = length(rel - Pf);
            col = col + scene * fire_c * fl * 0.9 / (1.0 + pow(dl / 320.0, 2.0)) * k;
        }
    }

    // ---- the cloud's shadow on the land: the sun's light through the cloud's own body, marched from the land towards
    // the sun, so it falls where the cloud really is: under it at noon, long and far across the land at a low sun, the
    // stem's band, the base surge's skirt; soft, and the sky still lights what lies in it -------------------------------
    if (stage != 1u && !sky && have && a > 0.3 && L.y > 0.02 && frame.mod_params[3].w < 0.5) {
        let T = pl_shadow(rel, L, a, C, ign(in.position.xy));
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
            // (the nuke's: laid white-hot in the re-entry, a thick lumpy trail of ablated smoke and the ionised air
            // glowing behind it; once it has shed its heat a pale vapour trail, thickening as it dives faster)
            let heat = 1.0 - smoothstep(PL_COOL - 0.6, PL_COOL + 1.0, te);
            let gone = 0.0;
            let dv = smoothstep(PL_DIVE - 1.0, PL_HIT, te);
            let dive = 0.0;
            // (smoke rather than vapour: from a second or two after it shows, as in the third clip, where the whole
            // hook it draws is the same grey-brown smoke)
            let smk = 0.0;
            // (its core's radius: thin and tight where it is laid, swelling with age; the outer fray to twice that)
            // (never thinner than a pixel, its density spread over the width it is drawn at)
            let rad0 = mix(1.2 + 3.0 * dv, 5.5, heat) + mix(1.5 + 1.5 * dv, 4.5, heat) * sqrt(age);
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
                let sig = mix(0.45 + 0.35 * dv, 0.8, heat) * exp(-age / mix(9.0, 16.0, heat)) * exp(-max(time - PL_HIT, 0.0) / 2.5) * fade * thin * (1.0 - gone);
                let dtau = sig * prof * dens * 1.6 * rad * gin;
                // (lit on its sunward side and on its lumps' tops, darker in its creases)
                let axis = pa_ + ab * sz;
                let nrm = normalize(cp - axis - rd * (0.6 * rad) + vec3<f32>(0.0, 1.0e-4, 0.0));
                let ln = 0.5 + w1 * (n1 - 0.5);
                let lit = (0.35 + 0.65 * saturate(dot(nrm, L) * 0.5 + 0.5)) * (0.6 + 0.8 * ln * ln);
                // (grey-brown smoke, paler as it spreads thin; the vapour high up a pale grey)
                var alb = mix(mix(mix(vec3<f32>(0.5, 0.5, 0.52), vec3<f32>(0.72, 0.72, 0.74), dv), vec3<f32>(0.74, 0.71, 0.66), heat), vec3<f32>(0.17, 0.145, 0.125), smk);
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
                let fh = max(heat, 0.1 * dv * dv) * exp(-age / mix(0.45, 0.25, dv)) * step(time, PL_HIT);
                let gr = rad * 0.5;
                let gch = sqrt(max(1.0 - gx * gx / (gr * gr), 0.0));
                let gcol = mix(mix(vec3<f32>(1.3, 0.35, 0.3), vec3<f32>(2.6, 0.95, 0.3), exp(-age / 0.4)), vec3<f32>(3.4, 3.0, 2.3), exp(-age / 0.1));
                glow = max(glow, gcol * fh * gch * 1.4);
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
    // ---- the mushroom cloud: raymarched, self-shadowed towards the sun, glowing from inside --------------------------
    // (the fireball's heat: white-hot for a moment, orange for seconds, a dull red glow dying over tens of seconds)
    let heat = exp(-a / 0.9);
    // (as filmed (Plumbbob Fizeau): a blazing orange ball for some five seconds, then going out fast; by eight or nine
    // seconds a dark sooty roll with a little red deep in it)
    let glow = 1.0 * (1.0 - smoothstep(4.5, 9.0, a)) + 0.12 * exp(-a / 10.0);
    if (stage != 2u && have && a > 0.0) {
        var cl = pl_column(a, C);
        // (first a cheap bound: a fat stick from under the land up to the cap's core circle, leaning with the wind, as
        // wide as the cap's rim and its lumps; its rounded top holds the dome. Its top at the core's height, not over
        // the cap: from a point higher up the rim's lumps lie further off than the rim's radius, and were cut off)
        let ctop = C + vec3<f32>(0.0, cl.hc, 0.0) + pl_wind() * a;
        let cbound = pl_ray_seg(rd, C - vec3<f32>(0.0, 20.0, 0.0), ctop, 0.0, 1.0);
        let crad = max(cl.Rt + 1.35 * cl.rt, max(cl.surge.x + cl.surge.y, 0.8 * cl.rt + 0.15 * cl.rt)) + PL_DM + 30.0 + 0.2 * length(pl_wind()) * a;
        let tb = pl_box(rd, cl.lo, cl.hi);
        let t1 = min(tb.y, scene_len);
        if (cbound.x < crad && t1 > tb.x) {
            pl_billows(&cl);
            let bmask = pl_bmask(&cl, rd, PL_DM + 20.0);
            cl.bm = bmask;
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
            // (dark brown as the fire goes out, by eight or nine seconds; lifting to Fizeau's grey-brown by twenty, paler on)
            let sootc = mix(mix(vec3<f32>(0.2, 0.14, 0.1), vec3<f32>(0.38, 0.32, 0.27), smoothstep(9.0, 20.0, a)), vec3<f32>(0.5, 0.46, 0.42), smoothstep(20.0, 45.0, a));
            for (var i = 0; i < 128; i = i + 1) {
                if (t > t1 || tr < 0.03) {
                    break;
                }
                let p = rd * t;
                let b2 = pl_col_base2(&cl, p);
                // (the crease between two billows broken up by the lumps over it: sooty in their own creases, not a ring)
                let kb0 = cl.kb;
                let d0 = b2.x;
                let dr = b2.y;
                let db = min(d0, dr);
                // (far from it, a long step: the body's distance is up to 1.6 times too long under the cap's roll)
                if (db > PL_DM + 14.0) {
                    t = t + (db - PL_DM - 4.0) * 0.52;
                    continue;
                }
                let st = max(5.0, t * 0.009) * (0.75 + 0.5 * j);
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
                    if (nl == 0 || (tr > 0.5 && nl < 3)) {
                        let fp = p + L * 9.0;
                        lc_face = pl_col_sdf(&cl, fp, pl_col_base2(&cl, fp).x, false).x - sd.x;
                        // (the light through the bulk: the smooth body's, without the billows)
                        cl.bm = 0u;
                        let s1 = saturate((10.0 - pl_col_base(&cl, p + L * 20.0)) / 34.0);
                        let s2 = saturate((10.0 - pl_col_base(&cl, p + L * 55.0)) / 46.0);
                        let s3 = saturate((8.0 - pl_col_base(&cl, p + L * 120.0)) / 60.0);
                        lc_bulk = exp(-(s1 * 10.0 + s2 * 18.0 + s3 * 22.0) * 0.3);
                        // (the sky's light shut out from under the cap and deep in it: what lies under more of it
                        // darker, its tops lit)
                        sky_occ = saturate((12.0 - pl_col_base(&cl, p + vec3<f32>(0.0, 80.0, 0.0))) / 70.0);
                        cl.bm = bmask;
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
                    let kb = kb0 * saturate(1.5 - 1.6 * sd.y);
                    let mv = (0.9 + 0.2 * (sd.w - 0.5) + 0.25 * (sd.y - 0.5)) * (1.0 - 0.35 * kb);
                    // (dusty brown low down, sooty grey-brown up in the cap, a little pink-tan as it ages)
                    var alb = mix(vec3<f32>(0.43, 0.38, 0.32), sootc, smoothstep(0.08, 0.45, hy)) * mv;
                    alb = mix(alb, vec3<f32>(0.85, 0.86, 0.88), ringw);
                    // (the surge's dust darker and browner than the cloud: earth, not smoke)
                    alb = alb * (1.0 - 0.3 * sw);
                    let skyg = mix(mix(skyl, vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.45), fogl, 0.15) * (1.0 - 0.35 * warm);
                    // (lifted as the fire goes out: the smoke's light scattered about inside it, so its shadowed side is grey-brown,
                    // not charcoal; while it burns, its own glow is most of its light)
                    let lift = smoothstep(5.0, 10.0, a);
                    var c = alb * ((skyg * (mix(0.48, 0.75, lift) * ao * (0.35 + 0.65 * hy)) + mix(vec3<f32>(0.2, 0.17, 0.13), vec3<f32>(0.3, 0.26, 0.2), lift) * day * (1.0 - 0.6 * warm) * ao) * mix(0.55, 1.0, capsh) + sunc * vec3<f32>(0.95, 0.85, 0.72) * (1.05 * tsun * ph));
                    // (lit from inside: the fireball's heat in the cap's core and its underside, white-hot at first,
                    // orange, then a dull red fading over tens of seconds; the stem's top lit by it from above)
                    let capw = smoothstep(cl.hc - 1.8 * cl.rt, cl.hc - 0.6 * cl.rt, p.y - C.y);
                    // (the fireball's heat: the whole ball at first, then gathered in the ring's core as it rolls up)
                    let qg = p - C - pl_lean(&cl, p.y - C.y);
                    let gv = vec2<f32>(length(qg.xz) - cl.Rt, (qg.y - cl.hc) * 1.2);
                    let ringc = exp(-dot(gv, gv) / pow(0.55 * cl.rt, 2.0));
                    let core = mix(1.0 - exp(min(d0, 0.0) / (0.22 * cl.rt + 6.0)), ringc, smoothstep(2.0, 9.0, a));
                    let under = 1.0 - smoothstep(cl.hc - 0.6 * cl.rt, cl.hc + 0.5 * cl.rt, p.y - C.y);
                    let surf = 1.5 * (1.0 - smoothstep(4.5, 8.5, a)) + 0.6 * exp(-a / 1.2);
                    let e = (heat * 7.0 + surf + glow * (0.06 + 3.2 * core * core * (exp(-a / 6.0) + 0.12)) * (0.3 + 1.4 * under)) * capw * (1.0 - ringw) * mix(0.1 + 2.3 * (1.0 - sd.y) * (1.0 - sd.y), (0.05 + 0.75 * smoothstep(0.2, 1.0, sd.y)) * (1.0 - 0.8 * kb), smoothstep(1.0, 3.0, a));
                    let tcol = mix(mix(vec3<f32>(0.9, 0.13, 0.03), vec3<f32>(2.8, 0.95, 0.16), saturate(glow * 1.3 + 0.15 * core)), vec3<f32>(3.4, 3.0, 2.4), heat);
                    // (and the land's glow, under it, on the stem and the surge, at first)
                    let lowlit = (1.0 - capw) * (heat * 2.0 + 0.6 * glow) * exp(-max(p.y - C.y, 0.0) / 90.0) * 0.4;
                    // (at night its own glow is most of what lights it, and shows for longer)
                    let en = e * (1.0 + 1.6 * (1.0 - day));
                    // (while it burns, the light on its sooty skin small beside its own: dark in its creases, not pale)
                    c = c * (1.0 - 0.6 * capw * (1.0 - smoothstep(4.0, 8.0, a))) * (1.0 - saturate(en * 1.2)) + tcol * (en * 0.6 + lowlit);
                    let ext = den * 0.32 * st;
                    let al = 1.0 - exp(-ext);
                    acc = acc + tr * al * c;
                    tmid = tmid + tr * al * t;
                    wmid = wmid + tr * al;
                    tr = tr * (1.0 - al);
                }
                // (well clear of it, a longer step: the lumps' slopes are steepest only close in)
                let dm = min(sd.x, dr);
                t = t + select(st, max(dm * mix(0.55, 0.8, smoothstep(8.0, 40.0, dm)), (0.12 * st + 0.25) * min(1.0 + 0.06 * f32(i), 2.5)), dm > 0.0);
            }
            if (tr < 0.999) {
                let dist = tmid / max(wmid, 1.0e-4);
                if (tr < 0.5) {
                    col_t = dist;
                }
                let ap = 1.0 - exp(-dist / 4000.0);
                // (the air's haze over it: thin over the burning ball, whose own light outshines it)
                let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, ap * 0.75 * mix(0.25, 1.0, smoothstep(5.0, 9.0, a)));
                if (stage == 0u) {
                    col = mix(col, ccol, (1.0 - tr) * k * fade);
                } else {
                    pl_over(&hc, ccol, (1.0 - tr) * k * fade);
                }
            }
        }
    }

    // ---- the bomb: a white-hot streak coming in from orbit, its plasma sheath and ionised wake; its heat shed, the
    // casing (an ogive nose, a long body, four fins at its tail, spinning faster as it dives, the sun glinting off it),
    // diving faster and faster, a collar of vapour round it, its nose glowing again; a pinprick of light the instant
    // before it bursts --------------------------------------------------------------------------------------------
    if (stage != 1u && have && time > PL_SEEN - 0.1 && time < PL_HIT + 0.03) {
        let tb = min(time, PL_HIT);
        let H0 = pl_head(tb);
        let Hp = H0 + C;
        let dh = length(Hp);
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
        let show = smoothstep(PL_SEEN - 0.1, PL_SEEN + 0.35, time) * vis * k;
        // (its way, nose first; how hot it still is; how hard it is diving: its nose heating again, the vapour round it)
        let vd = normalize(H0 - pl_head(tb - 0.06) + vec3<f32>(0.0, -1.0e-4, 0.0));
        let heat = 1.0 - smoothstep(PL_COOL - 0.6, PL_COOL + 1.0, time);
        let dive = smoothstep(PL_DIVE, PL_HIT, time);
        let vc = smoothstep(PL_HIT - 2.2, PL_HIT - 0.3, time);
        // (the frame it is drawn in: y along it, nose first, coning a little, less as it gathers speed)
        let sw = vec2<f32>(sin(time * 1.7), cos(time * 1.3)) * mix(0.04, 0.012, dive);
        let e1 = normalize(cross(vd, select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(vd.y) > 0.9)));
        let e2 = cross(vd, e1);
        let ay = normalize(vd + e1 * sw.x + e2 * sw.y);
        let ax = normalize(cross(ay, e2));
        let az = cross(ax, ay);
        // (its fins spin it up as it dives: the glints come faster and faster)
        let sd8 = max(time - PL_COOL, 0.0);
        let spin = time * 2.3 + 0.32 * sd8 * sd8;
        // (marched in the frame, within a sphere round it)
        let reach = 13.0;
        let cen = Hp;
        let bq = dot(rd, cen);
        let disc = bq * bq - dot(cen, cen) + reach * reach;
        if (disc > 0.0 && show > 0.0) {
            let sq = sqrt(disc);
            var tt = max(bq - sq, 0.0);
            let t1 = min(bq + sq, scene_len);
            var best = 1.0e9;
            var bt = tt;
            var bm = 0.0;
            for (var i = 0; i < 56; i = i + 1) {
                if (tt > t1) {
                    break;
                }
                let pw = tt * px_a;
                let w = rd * tt - Hp;
                let r = nk_bomb(vec3<f32>(dot(w, ax), dot(w, ay), dot(w, az)), spin, vc);
                let rr = r.x / pw;
                if (rr < best) {
                    best = rr;
                    bt = tt;
                    bm = r.y;
                }
                if (r.x < 0.02 * pw) {
                    break;
                }
                tt = tt + max(r.x, 0.35 * pw);
            }
            var cov = saturate(0.6 - best) / 0.6;
            let pw = bt * px_a;
            if (cov > 0.0) {
                let w = rd * bt - Hp;
                let q = vec3<f32>(dot(w, ax), dot(w, ay), dot(w, az));
                let ep = max(0.05, 0.4 * pw);
                let ex = vec2<f32>(1.0, -1.0);
                let nl = normalize(ex.xyy * nk_bomb(q + ex.xyy * ep, spin, vc).x + ex.yyx * nk_bomb(q + ex.yyx * ep, spin, vc).x + ex.yxy * nk_bomb(q + ex.yxy * ep, spin, vc).x + ex.xxx * nk_bomb(q + ex.xxx * ep, spin, vc).x);
                var n = normalize(ax * nl.x + ay * nl.y + az * nl.z);
                var alb = vec3<f32>(0.4, 0.41, 0.42);
                var spec = 1.0;
                if (bm < 0.5) {
                    // (the body: a dull grey casing, a dark band round it, faint seams)
                    let yb = q.y / NK_BS;
                    alb = select(alb, vec3<f32>(0.07), abs(yb - 0.9) < 0.3);
                    alb = alb * (0.9 + 0.1 * step(0.06, abs(fract(yb / 2.2) - 0.5)));
                } else if (bm < 1.5) {
                    alb = vec3<f32>(0.12, 0.12, 0.13);
                } else if (bm < 2.5) {
                    alb = vec3<f32>(0.09, 0.085, 0.08);
                } else {
                    // (the vapour: a thin white veil, flickering, thinning to its trailing edge)
                    let fade_v = 1.0 - saturate((2.4 * NK_BS - q.y) / (9.0 * vc + 0.01));
                    alb = vec3<f32>(0.95, 0.96, 1.0);
                    spec = 0.0;
                    cov = cov * vc * 0.35 * fade_v * (0.75 + 0.25 * sin(time * 53.0 + q.y * 3.0));
                    if (dot(n, rd) > 0.0) {
                        n = -n;
                    }
                }
                let ndl = dot(n, L);
                // (the canopy lets the sun through: lit from behind as well)
                let dif = select(max(ndl, 0.0), 0.5 + 0.5 * abs(ndl), bm > 2.5);
                var c = alb * (sunc * dif * 0.95 + amb * (0.55 + 0.45 * n.y));
                c = c + sunc * spec * (pow(max(dot(reflect(rd, n), L), 0.0), 90.0) * 5.0 + pow(max(dot(reflect(rd, n), L), 0.0), 8.0) * 0.15);
                // (still hot from the re-entry: the nose glowing red, the body dull red behind it, cooling)
                // (and heating again in the dive: the nose dull red, then orange, its edges brightest)
                let warmb = max(smoothstep(PL_COOL + 2.2, PL_COOL - 0.4, time), 0.8 * dive * dive);
                let wn = select(0.35 * saturate((q.y / NK_BS + 3.0) / 6.0), 1.0, bm > 1.5 && bm < 2.5) * select(1.0, 0.0, bm > 2.5);
                c = c + mix(vec3<f32>(1.6, 0.28, 0.06), vec3<f32>(3.0, 1.6, 0.6), max(heat, 0.6 * dive * dive)) * warmb * warmb * wn;
                c = mix(c, haze_c, (1.0 - exp(-bt / 3000.0)) * 0.75);
                col = mix(col, c, cov * show);
            }
        }
        // (from far off, a speck at least: the casing never thinner than a pixel against the sky)
        let thc = max(4.0 / dh, px_a * 0.9);
        let far = smoothstep(1.2, 0.35, 16.0 / dh / px_a / 6.0) * (1.0 - heat);
        col = mix(col, vec3<f32>(0.05, 0.05, 0.055) + sunc * 0.05, exp(-pow(th / thc, 2.0)) * far * 0.85 * show);
        // (the re-entry: a white-hot point, its plasma sheath drawn out behind it in a teardrop, bloom, a lens streak)
        if (heat > 0.001) {
            let fl = 0.86 + 0.14 * sin(time * 41.0) * sin(time * 27.0 + 1.0);
            let tc0 = max(3.0 / dh, px_a * 0.9);
            let core = exp(-pow(th / tc0, 2.0)) * 16.0;
            let bloom = 1.1 / (1.0 + pow(th / (tc0 * 4.0 + 0.004), 2.0)) + 0.22 * exp(-th / 0.05);
            let lw = 16.0 + 100.0 * heat;
            let s = ray_seg(rd, Hp, Hp - vd * lw);
            let ww = mix(1.6, 6.0, sqrt(s.z));
            let wpx = max(ww, s.y * px_a * 0.8);
            let sheath = exp(-pow(s.x / wpx, 2.0)) * pow(1.0 - s.z, 1.6) * (ww / wpx) * 5.0;
            let sv = rd - hn * cth;
            let upv = normalize(cross(cross(hn, vec3<f32>(0.0, 1.0, 0.0)), hn) + vec3<f32>(0.0, 1.0e-5, 0.0));
            let streak = exp(-abs(dot(sv, upv)) / (px_a * 1.2)) * exp(-th / 0.035) * 0.3;
            let hot = vec3<f32>(1.0, 0.95, 0.88) * (core + bloom + streak) + mix(vec3<f32>(1.0, 0.9, 0.75), vec3<f32>(1.0, 0.42, 0.16), sqrt(s.z)) * sheath;
            col = col + hot * heat * fl * show;
        }
        // (the dive's heat: a small orange glow at its nose and a short hot wake, growing to the burst)
        if (dive > 0.001) {
            let s = ray_seg(rd, Hp + vd * 9.0, Hp - vd * (4.0 + 22.0 * dive));
            let ww = mix(0.8, 2.2, s.z);
            let wpx = max(ww, s.y * px_a * 0.8);
            let wake = exp(-pow(s.x / wpx, 2.0)) * pow(1.0 - s.z, 2.0) * (ww / wpx);
            let tc1 = max(2.0 / dh, px_a * 0.9);
            let nose = exp(-pow(th / tc1, 2.0)) * 1.2 + 0.15 / (1.0 + pow(th / (tc1 * 4.0 + 0.002), 2.0));
            col = col + vec3<f32>(2.4, 0.95, 0.3) * (nose + wake * 0.8) * dive * dive * show;
        }
        // (the sun glinting off its turning fins, now and then, from any distance)
        let gph = pow(0.5 + 0.5 * sin(spin * 2.0 + 0.7), 30.0) + 0.5 * pow(0.5 + 0.5 * sin(spin * 2.0 + 2.6), 40.0);
        let gtc = max(2.0 / dh, px_a * 1.0);
        let glint = (exp(-pow(th / (gtc * 0.6), 2.0)) * 2.5 + 0.1 / (1.0 + pow(th / (gtc * 3.0), 2.0))) * gph * sun_up;
        // (and at night a strobe on its tail, so it can be followed down, blinking faster as it nears)
        let blink = step(fract(time * 1.1 + 0.25 * sd8 * sd8), 0.14) * (1.0 - day) * 0.8;
        let red = exp(-pow(th / max(px_a * 1.2, 0.8 / dh), 2.0)) * 2.0 + 0.2 / (1.0 + pow(th / (px_a * 5.0), 2.0));
        col = col + (sunc * glint * (1.0 + dive) + vec3<f32>(2.4, 0.12, 0.05) * red * blink) * (1.0 - heat) * show;
        // (the instant before: a pinprick of white at it, swelling)
        let pin = pow(saturate((time - (PL_HIT - 0.22)) / 0.22), 3.0);
        if (pin > 0.0) {
            let pc = max(2.0 / dh, px_a * 0.9);
            col = col + vec3<f32>(1.0, 0.98, 0.95) * (exp(-pow(th / pc, 2.0)) * 30.0 + 2.5 / (1.0 + pow(th / (0.012 * pin + 0.002), 2.0))) * pin * show;
        }
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
            let dcl = pl_column(max(a, 0.01), C);
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
        if (a > 0.0 && a < 24.0 && pl_w(8u) > 0.5) {
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
    if ((stage == 0u || up_e.y > 0.0) && a > 0.0 && a < 24.0 && pl_w(8u) > 0.5) {
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
        let dirt = vec3<f32>(0.035, 0.03, 0.026) * (amb * 1.5 + sunc * 0.3);
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
                let pxy = in.position.xy;
                let res = frame.resolution.xy;
                let film = gnoise3(vec3<f32>(pxy / (0.13 * res.y), 3.1)) * 0.65 + gnoise3(vec3<f32>(pxy / (0.034 * res.y), 7.7)) * 0.35;
                col = mix(col, dust_c, 0.12 * E * smoothstep(0.45, 0.8, film));
            }
            // (muck thrown on the lens as the front passes, out of focus, as the second clip shows it: drops near round
            // but each its own, a few elongated, 2 to 7% of the picture's height across, a ring darker than their middle,
            // soft over their outer quarter, mottled; some faint, some strong (letting through 55 to 90% of the light),
            // grey; often with a smaller drop or two beside them; nearly all high on the screen; landing over the second
            // after the front, staying a long while)
            let vis = smoothstep(60.0, 10.0, hc) * smoothstep(6000.0, 2500.0, rc) * smoothstep(120.0, 260.0, rc) * (1.0 - 0.5 * land.y) * k;
            if (vis > 0.0 && tau > 0.2) {
                let pxy = in.position.xy;
                let res = frame.resolution.xy;
                var keep = 1.0;
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
                    if (dot(d0, d0) > 9.0 * r * r) {
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
                        if (q >= 1.08) {
                            continue;
                        }
                        let ring = mix(0.58, 1.0, smoothstep(0.05, 0.7, q)) * (1.0 - smoothstep(0.78, 1.06, q));
                        let mott = 0.88 + 0.24 * gnoise3(vec3<f32>(e / (0.35 * rj), f32(k2 % 97u)));
                        let op = (0.14 + 0.34 * pow(mh(k2, seed, 0x3e7u), 0.7)) * select(0.85, 1.0, j == 0u);
                        keep = keep * (1.0 - ring * mott * op * life);
                    }
                }
                // (muck, not shade: the drops scatter the light as well as stopping it, a dusty grey-brown veil)
                let muck = vec3<f32>(0.42, 0.38, 0.33) * (sunc * 0.45 + amb * 0.9);
                col = mix(col, col * keep + muck * (1.0 - keep) * 0.7, vis * fade);
            }
        }
    }

    // ---- the white-out: for a moment the whole picture is the flash, then it lets go, overexposed for a second ----
    if (stage != 1u && a > -0.02 && a < 4.0) {
        // (as filmed: the whole frame a pinkish white, then washed orange for a second or so, then the exposure drops
        // dark for a moment before the sky comes back)
        let wo = saturate(1.4 * exp(-max(a, 0.0) / 0.22)) * smoothstep(-0.02, 0.02, a);
        col = col * (1.0 + 0.4 * exp(-max(a, 0.0) / 0.6));
        let ow = smoothstep(0.08, 0.35, a) * (1.0 - smoothstep(1.1, 2.1, a));
        col = mix(col, col * vec3<f32>(1.5, 0.8, 0.35) + vec3<f32>(0.38, 0.14, 0.02), ow * k);
        col = col * (1.0 - 0.32 * exp(-pow((a - 2.5) / 0.55, 2.0)) * k);
        col = mix(col, vec3<f32>(1.4, 1.24, 1.32), wo * k);
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
    return nuke(in, 0u, vec4<f32>(0.0), vec3<f32>(1.0e9, 1.0, 0.0)).c;
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
    let o = nuke(in, 1u, vec4<f32>(0.0), vec3<f32>(1.0e9, 1.0, 0.0));
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
fn fs_join(in: StageIn) -> @location(0) vec4<f32> {
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let u = pl_up(in.position.xy, len);
    return nuke(in, 2u, u.c, vec3<f32>(select(u.e.x, 1.0e9, u.e.x >= 6.0e4), u.e.y, u.e.z)).c;
}
// [end half stage]
