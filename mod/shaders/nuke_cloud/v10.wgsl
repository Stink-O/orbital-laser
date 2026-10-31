// v10 V3 PLUS: v3 FOLDING's cloud (12c9f80: its shapes, lumps and motion unchanged) with today's look: the burning
// ball a saturated self-lit orange, sooty in its creases in broken patches, going out to a dark brown by eight or nine
// seconds (6987c27, 00c7c2b); the cap a lighter grey-brown, its tops sunlit, from fifteen seconds (87eca29); the cap's
// shadow on its stem, the ring and the base surge (9ea7c55). Made by hand from v3.wgsl (tools/nuke_cloud.py extract
// leaves it be); spliced into nuke.wgsl by mod/build.rs (src/passbuild.rs nuke_cloud_pass) for /orbital nukecloud 10.
// [cloud fns]
const v10_PL_DM: f32 = 70.0;           // the most the cloud's lumps stand out of its smooth body (pl_col_sdf), which the
// ---- the mushroom cloud: a fireball rising into a toroidal cap on a stem, a ring round the stem, a base surge -----
struct v10_PlCol {
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
}
fn v10_pl_column(a: f32, C: vec3<f32>) -> v10_PlCol {
    var o: v10_PlCol;
    o.a = a;
    o.C = C + pl_wind() * (0.0 * a);
    // (the fireball: swelling to sixty in half a second, then slowly on; rising, slowly at first, then climbing to
    // over four hundred as its rise slows; its roll opening out into the cap's ring)
    o.rt = 56.0 * (1.0 - exp(-a / 0.45)) + 26.0 * (1.0 - exp(-a / 14.0)) + 0.15 * a;
    o.hc = PL_BURST + 385.0 * (1.0 - exp(-a / 15.0)) * smoothstep(0.0, 2.5, a + 0.5);
    o.Rt = 80.0 * (1.0 - exp(-a / 6.0)) + 70.0 * (1.0 - exp(-a / 28.0)) + 0.3 * a;
    // (the stem pulled up out of the land under it, from a couple of seconds on)
    o.st = min(o.hc - 0.15 * o.rt, max(a - 1.0, 0.0) * 55.0);
    o.sr = vec3<f32>(34.0 + 30.0 * saturate(a / 6.0), 20.0 + 8.0 * saturate(a / 20.0), 26.0 + 0.3 * o.Rt);
    // (the condensation ring: a thin white collar round the stem, from 4 s, gone by 30)
    o.ring = vec3<f32>(0.42 * o.hc + 10.0, o.sr.y * 2.0 + 30.0 + 0.6 * a, smoothstep(4.0, 9.0, a) * (1.0 - smoothstep(16.0, 30.0, a)));
    // (the base surge: dust rolling out over the ground round the stem's foot)
    o.surge = vec3<f32>(30.0 + 160.0 * (1.0 - exp(-a / 12.0)), 24.0 + 0.1 * a, 8.0 + 9.0 * saturate(a / 12.0));
    let top = o.hc + 1.4 * o.rt;
    let w = max(o.Rt + o.rt * 1.6, o.surge.x + o.surge.y) + 90.0;
    let lean = pl_wind() * a;
    o.lo = C + vec3<f32>(-w + min(lean.x, 0.0), -20.0 - pl_foot_low(a, o.rt), -w + min(lean.z, 0.0));
    o.hi = C + vec3<f32>(w + max(lean.x, 0.0), top + 90.0, w + max(lean.z, 0.0));
    return o;
}
// The cloud's lean with the wind at p (its head carried furthest, its foot staying put).
fn v10_pl_lean(col: ptr<function, v10_PlCol>, hy: f32) -> vec3<f32> {
    return pl_wind() * ((*col).a * pow(saturate(hy / max((*col).hc, 1.0)), 1.5));
}
// The cloud's smooth body at p (camera-relative): the cap (the roll round its core circle, a dome over it), the stem,
// the base surge; and in .y how much of the ring is there instead (the ring kept apart: it is white).
fn v10_pl_col_base2(col: ptr<function, v10_PlCol>, p: vec3<f32>) -> vec2<f32> {
    let C = (*col).C;
    let hy0 = p.y - C.y;
    let q = p - C - v10_pl_lean(col, hy0);
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
    // (the fireball's foot: for its first seconds spread over the ground it burst just over, a flattened dome on the
    // land (pl_foot), not a ball floating over it)
    d = smin(d, pl_foot((*col).a, rt, rho, hy), 0.3 * rt + 4.0);
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
        let settle = 22.0 * smoothstep(18.0, 70.0, (*col).a) + 40.0 * (1.0 - smoothstep(0.2, 2.5, (*col).a));
        d = smin(d, ds + 14.0 * smoothstep(0.0, 0.6, inner.x) + settle, 22.0);
        // (and a low sheet of dust inside the roll, from it in to the stem's foot: a skirt, not a tyre)
        let sheet = max(rho - sg.x, abs(hy - 0.2 * sg.z) - 0.32 * sg.z);
        d = smin(d, sheet + 11.0 + settle, 18.0);
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
fn v10_pl_col_base(col: ptr<function, v10_PlCol>, p: vec3<f32>) -> f32 {
    let b = v10_pl_col_base2(col, p);
    return min(b.x, b.y);
}
// Cauliflower lumps: domes over a jittered lattice (a feature point in each of the eight cells round p, well jittered),
// each its own size, rounded on top and meeting in creases: about 1 on a big dome's crown, 0 in a crease.
fn v10_pl_dome(p: vec3<f32>) -> f32 {
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
fn v10_pl_rot(k: i32, p: vec3<f32>) -> vec3<f32> {
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
fn v10_pl_col_sdf(col: ptr<function, v10_PlCol>, p: vec3<f32>, d0: f32, fine: bool) -> vec4<f32> {
    let a = (*col).a;
    let C = (*col).C;
    var q = p - C - v10_pl_lean(col, p.y - C.y);
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
    let om = 0.25 * (1.0 - exp(-a / 2.0)) * exp(-a / 12.0) + 0.04;
    let ph = fract(a / PL_CHURN);
    let wA = 1.0 - abs(2.0 * ph - 1.0);
    // (and the stem's boiling up it: its lumps carried up, the same way all down it to the land, so they move without
    // stretching; let go of over most of the cap's height, under its roll, where the roll's own churn takes over)
    q.y = q.y - 3.5 * min(a, 18.0) * (1.0 - exp(-wq * wq)) * (1.0 - smoothstep((*col).hc - 1.7 * (*col).rt, (*col).hc - 0.5 * (*col).rt, q.y));
    let S = 2.2;
    let w = gnoise3(v10_pl_rot(1, q * (1.0 / (55.0 * S))));
    let w2 = gnoise3(v10_pl_rot(2, q * (1.0 / (23.0 * S)) + vec3<f32>(9.2, -0.05 * a, 4.4)));
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
        b1 = b1 + select(1.0 - wA, wA, k == 0) * v10_pl_dome(v10_pl_rot(0, qk * (1.0 / (36.0 * S)) + vec3<f32>(3.1 + 7.3 * cyc, 0.0, 7.7 - 4.1 * cyc + 2.9 * f32(k)) + 0.3 * vec3<f32>(w2 - 0.5)));
    }
    // (two half sets added are evener than one: their spread put back)
    b1 = select(b1 / max(wsum, 1.0e-3), 0.62 + (b1 - 0.62) / sqrt(wA * wA + (1.0 - wA) * (1.0 - wA)), fine);
    let hy = p.y - C.y;
    let lump = 1.6 * (0.6 + 0.4 * smoothstep(20.0, 160.0, hy));
    let soft = smoothstep(PL_SOFT0, PL_SOFT1, a);
    let crisp = 1.0 - 0.8 * soft;
    let b2 = v10_pl_dome(v10_pl_rot(1, q * (1.0 / (14.0 * S)) + vec3<f32>(0.0, -0.15 * a, 1.3)));
    let up = smoothstep(40.0, 200.0, hy);
    // (the crown over the middle smoother than the roll: its big swells let down, so it stays one rounded dome)
    let crown = (1.0 - smoothstep(0.3 * (*col).Rt, (*col).Rt + 0.3 * (*col).rt, rho)) * smoothstep((*col).hc, (*col).hc + 0.5 * (*col).rt, hy);
    var d = d0 - (26.0 * (b1 - 0.45) * crisp * (0.4 + 0.6 * up) * (1.0 - 0.2 * crown) + 9.0 * (b2 - 0.45) * (1.0 - 0.7 * soft) + (18.0 + 8.0 * soft) * (w - 0.5) * (1.0 - 0.35 * crown) + 8.0 * (w2 - 0.5)) * lump;
    let ew = smoothstep(0.6, 0.82, w2);
    let edge = mix(1.5, 6.0, ew) + 10.0 * (1.0 - smoothstep(0.0, 60.0, hy));
    var fray = 0.5;
    if (fine && d < 20.0 && soft < 0.99) {
        let b3 = v10_pl_dome(v10_pl_rot(2, q * (1.0 / (5.5 * S)) + vec3<f32>(1.7, -0.25 * a, -2.1)));
        d = d - 4.0 * (b3 - 0.45) * (1.0 - soft) * lump;
        fray = gnoise3(v10_pl_rot(0, q * (1.0 / (1.8 * S))) + vec3<f32>(5.0, 1.0, -0.4 * a));
        d = d - 3.5 * (fray - 0.5) * (1.0 - soft) * (0.25 + 0.75 * ew);
    }
    // (the lumps' height capped smoothly at PL_DM, so that nothing stands out past the bounds the march allows)
    let bump = max(d0 - d, 0.0);
    d = d0 - bump / sqrt(sqrt(1.0 + pow(bump / v10_PL_DM, 4.0))) + max(d - d0, 0.0);
    return vec4<f32>(d, b1 * (0.45 + 0.55 * b2), edge, fray);
}
// A ray against a box, camera-relative: the entry and exit distances.
fn v10_pl_box(rd: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>) -> vec2<f32> {
    let inv = 1.0 / select(rd, vec3<f32>(1.0e-6), abs(rd) < vec3<f32>(1.0e-6));
    let ta = lo * inv;
    let tb = hi * inv;
    let tmin = min(ta, tb);
    let tmax = max(ta, tb);
    return vec2<f32>(max(max(tmin.x, tmin.y), max(tmin.z, 0.0)), min(min(tmax.x, tmax.y), tmax.z));
}

// How much of the sun's light reaches land point `o` (camera-relative) through the cloud: its smooth body marched
// towards the sun in a dozen steps, soft-edged (a little of its lumps' reach counted in). 1 in full sun.
fn v10_pl_shadow(o: vec3<f32>, L: vec3<f32>, a: f32, C: vec3<f32>, j: f32) -> f32 {
    var cs = v10_pl_column(a, C);
    let tb = v10_pl_box(L, cs.lo - o, cs.hi - o);
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
        let d = v10_pl_col_base2(&cs, o + L * (tb.x + (f32(i) + j) * dt)).x;
        tau = tau + saturate(0.35 - d / 45.0);
    }
    // (thinning as the cloud does, late on)
    let thin = 1.0 - 0.8 * smoothstep(PL_SOFT0, PL_LEN, a);
    return exp(-tau * dt * 0.022 * thin * smoothstep(0.3, 2.0, a));
}

// [cloud]
    // ---- the mushroom cloud: raymarched, self-shadowed towards the sun, glowing from inside --------------------------
    // (the fireball's heat: white-hot for a moment, orange for seconds, a dull red glow dying over tens of seconds)
    let heat = exp(-a / 0.6);
    // (as filmed (Plumbbob Fizeau): a blazing orange ball for some five seconds, then going out fast; by eight or nine
    // seconds a dark sooty roll with a little red deep in it)
    let glow = 1.0 * (1.0 - smoothstep(4.5, 9.0, a)) + 0.12 * exp(-a / 10.0);
    if (stage != 2u && have && a > 0.0) {
        var cl = v10_pl_column(a, C);
        // (first a cheap bound: a fat stick from under the land up to the cap's core circle, leaning with the wind, as
        // wide as the cap's rim and its lumps; its rounded top holds the dome. Its top at the core's height, not over
        // the cap: from a point higher up the rim's lumps lie further off than the rim's radius, and were cut off)
        let ctop = C + vec3<f32>(0.0, cl.hc, 0.0) + pl_wind() * a;
        let cbound = pl_ray_seg(rd, C - vec3<f32>(0.0, 20.0, 0.0), ctop, 0.0, 1.0);
        let crad = max(cl.Rt + cl.rt, max(cl.surge.x + cl.surge.y, 0.8 * cl.rt + 0.15 * cl.rt)) + v10_PL_DM + 30.0 + 0.2 * length(pl_wind()) * a;
        let tb = v10_pl_box(rd, cl.lo, cl.hi);
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
            // (dark brown as the fire goes out, by eight or nine seconds; lifting to Fizeau's grey-brown by twenty, paler on)
            let sootc = mix(mix(vec3<f32>(0.2, 0.14, 0.1), vec3<f32>(0.44, 0.37, 0.31), smoothstep(9.0, 20.0, a)), vec3<f32>(0.56, 0.51, 0.46), smoothstep(20.0, 45.0, a));
            for (var i = 0; i < 128; i = i + 1) {
                if (t > t1 || tr < 0.03) {
                    break;
                }
                let p = rd * t;
                let b2 = v10_pl_col_base2(&cl, p);
                let d0 = b2.x;
                let dr = b2.y;
                let db = min(d0, dr);
                // (far from it, a long step: the body's distance is up to 1.6 times too long under the cap's roll)
                if (db > v10_PL_DM + 14.0) {
                    t = t + (db - v10_PL_DM - 4.0) * 0.52;
                    continue;
                }
                let st = max(5.0, t * 0.009) * (0.75 + 0.5 * j);
                var den = 0.0;
                var ringw = 0.0;
                var sd = vec4<f32>(d0, 0.5, 4.0, 0.5);
                // (deep inside, past where any lump could reach, it is smoke whatever the lumps: none looked up)
                if (d0 < -v10_PL_DM - 6.0) {
                    sd = vec4<f32>(d0, 0.45, 4.0, 0.5);
                    den = thin;
                } else if (d0 < v10_PL_DM + 4.0) {
                    sd = v10_pl_col_sdf(&cl, p, d0, true);
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
                        let qs = p - C - v10_pl_lean(&cl, p.y - C.y);
                        em_k = smoothstep(0.42, 0.68, gnoise3(qs * (1.0 / 48.0) + vec3<f32>(2.3, -0.03 * a, 5.1)));
                    }
                    if (tr > 0.25 || nl == 0) {
                        let fp = p + L * 9.0;
                        lc_face = v10_pl_col_sdf(&cl, fp, v10_pl_col_base2(&cl, fp).x, false).x - sd.x;
                        let s1 = saturate((10.0 - v10_pl_col_base(&cl, p + L * 20.0)) / 34.0);
                        let s2 = saturate((10.0 - v10_pl_col_base(&cl, p + L * 55.0)) / 46.0);
                        let s3 = saturate((8.0 - v10_pl_col_base(&cl, p + L * 120.0)) / 60.0);
                        lc_bulk = exp(-(s1 * 10.0 + s2 * 18.0 + s3 * 22.0) * 0.3);
                        // (the sky's light shut out from under the cap and deep in it: what lies under more of it
                        // darker, its tops lit)
                        sky_occ = saturate((12.0 - v10_pl_col_base(&cl, p + vec3<f32>(0.0, 80.0, 0.0))) / 70.0);
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
                    let qg = p - C - v10_pl_lean(&cl, p.y - C.y);
                    let gv = vec2<f32>(length(qg.xz) - cl.Rt, (qg.y - cl.hc) * 1.2);
                    let ringc = exp(-dot(gv, gv) / pow(0.55 * cl.rt, 2.0));
                    let core = mix(1.0 - exp(min(d0, 0.0) / (0.22 * cl.rt + 6.0)), ringc, smoothstep(2.0, 9.0, a));
                    let under = 1.0 - smoothstep(cl.hc - 0.6 * cl.rt, cl.hc + 0.5 * cl.rt, p.y - C.y);
                    let surf = 1.5 * (1.0 - smoothstep(4.5, 8.5, a)) + 0.6 * exp(-a / 1.2);
                    // (from its first second, the glow on its lumps' crowns, their creases sooty)
                    let e = (heat * 5.0 + surf + glow * (0.06 + 3.2 * core * core * (exp(-a / 6.0) + 0.12)) * (0.3 + 1.4 * under)) * capw * (1.0 - ringw) * mix(0.1 + 2.3 * (1.0 - sd.y) * (1.0 - sd.y), (0.05 + 0.75 * smoothstep(0.2, 1.0, em_y)) * (1.0 - 0.6 * kb), smoothstep(0.3, 1.3, a));
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
                t = t + select(st, max(0.55 * min(sd.x, dr), (0.12 * st + 0.25) * min(1.0 + 0.06 * f32(i), 2.5)), min(sd.x, dr) > 0.0);
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
