// v5 BOIL-UP: the Nuke's cloud as it was at 6cb04f9 2026-10-30 22:22 Nuke: the boil's churn calmed by fourteen seconds and looked up only where it shows
// Written by tools/nuke_cloud.py extract (don't edit by hand); spliced into nuke.wgsl by mod/src/lib.rs's
// nuke_cloud_pass for /orbital nukecloud 5.
// [cloud fns]
const v5_PL_DM: f32 = 70.0;           // the most the cloud's lumps stand out of its smooth body (pl_col_sdf), which the
// ---- the mushroom cloud: a fireball rising into a toroidal cap on a stem, a ring round the stem, a base surge -----
struct v5_PlCol {
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
fn v5_pl_column(a: f32, C: vec3<f32>) -> v5_PlCol {
    var o: v5_PlCol;
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
fn v5_pl_lean(col: ptr<function, v5_PlCol>, hy: f32) -> vec3<f32> {
    return pl_wind() * ((*col).a * pow(saturate(hy / max((*col).hc, 1.0)), 1.5));
}
// The cloud's smooth body at p (camera-relative): the cap (the roll round its core circle, a dome over it), the stem,
// the base surge; and in .y how much of the ring is there instead (the ring kept apart: it is white).
fn v5_pl_col_base2(col: ptr<function, v5_PlCol>, p: vec3<f32>) -> vec2<f32> {
    let C = (*col).C;
    let hy0 = p.y - C.y;
    let q = p - C - v5_pl_lean(col, hy0);
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
    // (the ring round the stem: a thin flat collar)
    var dr = 1.0e6;
    let rg = (*col).ring;
    if (rg.z > 0.01) {
        let e = vec2<f32>((rho - rg.y) / 34.0, (hy - rg.x) / 13.0);
        dr = (length(e) - 1.0) * 13.0;
    }
    return vec2<f32>(d, dr);
}
fn v5_pl_col_base(col: ptr<function, v5_PlCol>, p: vec3<f32>) -> f32 {
    let b = v5_pl_col_base2(col, p);
    return min(b.x, b.y);
}
// Cauliflower lumps: domes over a jittered lattice (a feature point in each of the eight cells round p, well jittered),
// each its own size, rounded on top and meeting in creases: about 1 on a big dome's crown, 0 in a crease.
fn v5_pl_dome(p: vec3<f32>) -> f32 {
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
fn v5_pl_rot(k: i32, p: vec3<f32>) -> vec3<f32> {
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
fn v5_pl_nz(qm: vec3<f32>) -> vec4<f32> {
    let S = 2.2;
    let w = gnoise3(v5_pl_rot(1, qm * (1.0 / (55.0 * S))));
    let w2 = gnoise3(v5_pl_rot(2, qm * (1.0 / (23.0 * S)) + vec3<f32>(9.2, 0.0, 4.4)));
    let b1 = v5_pl_dome(v5_pl_rot(0, qm * (1.0 / (36.0 * S)) + vec3<f32>(3.1, 0.0, 7.7) + 0.3 * vec3<f32>(w2 - 0.5)));
    let b2 = v5_pl_dome(v5_pl_rot(1, qm * (1.0 / (14.0 * S)) + vec3<f32>(0.0, 0.0, 1.3)));
    return vec4<f32>(w, w2, b1, b2);
}
// And its small lumps and its fray.
fn v5_pl_nz_fine(qm: vec3<f32>) -> vec2<f32> {
    let S = 2.2;
    return vec2<f32>(v5_pl_dome(v5_pl_rot(2, qm * (1.0 / (5.5 * S)) + vec3<f32>(1.7, 0.0, -2.1))), gnoise3(v5_pl_rot(0, qm * (1.0 / (1.8 * S))) + vec3<f32>(5.0, 1.0, 0.0)));
}
// The cloud's surface at p: its smooth body bulged out in lumps on lumps (as the Payload's column). The lumps are its
// material's, looked up where that material started, so they move with it and none ever comes from nowhere: up the
// stem with the rising air; in the cap, carried up with it, swelling as it swells, and round its roll (up the inside,
// out over the top, down the outside, back in under it). .x the distance, .y how far up a dome it lies, .z how soft
// its edge is, .w the fine fray.
fn v5_pl_col_sdf(col: ptr<function, v5_PlCol>, p: vec3<f32>, d0: f32, fine: bool) -> vec4<f32> {
    let a = (*col).a;
    let C = (*col).C;
    let q = p - C - v5_pl_lean(col, p.y - C.y);
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
    let wc0 = smoothstep(hc - 1.5 * rt, hc - 0.6 * rt, q.y);
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
    var nf = vec2<f32>(0.5);
    let need_fine = fine && smoothstep(PL_SOFT0, PL_SOFT1, a) < 0.99;
    if (wc > 0.98) {
        nz = v5_pl_nz(qc);
        if (need_fine && d0 < 50.0) {
            nf = v5_pl_nz_fine(qc);
        }
    } else if (wc < 0.02) {
        nz = v5_pl_nz(qs);
        if (need_fine && d0 < 50.0) {
            nf = v5_pl_nz_fine(qs);
        }
    } else {
        // (the spread two fadings together lose put back)
        let ls = 1.0 / sqrt(wc * wc + (1.0 - wc) * (1.0 - wc));
        nz = vec4<f32>(0.5, 0.5, 0.62, 0.62) + (mix(v5_pl_nz(qs), v5_pl_nz(qc), wc) - vec4<f32>(0.5, 0.5, 0.62, 0.62)) * ls;
        if (need_fine && d0 < 50.0) {
            nf = vec2<f32>(0.62, 0.5) + (mix(v5_pl_nz_fine(qs), v5_pl_nz_fine(qc), wc) - vec2<f32>(0.62, 0.5)) * ls;
        }
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
        let b3 = nf.x;
        d = d - 4.0 * (b3 - 0.45) * (1.0 - soft) * lump;
        fray = nf.y;
        d = d - 3.5 * (fray - 0.5) * (1.0 - soft) * (0.25 + 0.75 * ew);
    }
    // (the lumps' height capped smoothly at PL_DM, so that nothing stands out past the bounds the march allows)
    let bump = max(d0 - d, 0.0);
    d = d0 - bump / sqrt(sqrt(1.0 + pow(bump / v5_PL_DM, 4.0))) + max(d - d0, 0.0);
    return vec4<f32>(d, b1 * (0.45 + 0.55 * b2), edge, fray);
}
// A ray against a box, camera-relative: the entry and exit distances.
fn v5_pl_box(rd: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>) -> vec2<f32> {
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
fn v5_pl_cap_shade(o: vec3<f32>, L: vec3<f32>, a: f32, C: vec3<f32>, hc: f32, R: f32) -> f32 {
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
fn v5_pl_shadow(o: vec3<f32>, L: vec3<f32>, a: f32, C: vec3<f32>, j: f32) -> f32 {
    var cs = v5_pl_column(a, C);
    let tb = v5_pl_box(L, cs.lo - o, cs.hi - o);
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
        let d = v5_pl_col_base2(&cs, o + L * (tb.x + (f32(i) + j) * dt)).x;
        tau = tau + saturate(0.35 - d / 45.0);
    }
    // (thinning as the cloud does, late on)
    let thin = 1.0 - 0.8 * smoothstep(PL_SOFT0, PL_LEN, a);
    return exp(-tau * dt * 0.022 * thin * smoothstep(0.3, 2.0, a));
}

// [cloud]
    // ---- the mushroom cloud: raymarched, self-shadowed towards the sun, glowing from inside --------------------------
    // (the fireball's heat: white-hot for a moment, orange for seconds, a dull red glow dying over tens of seconds)
    let heat = exp(-a / 0.9);
    let glow = 1.0 * exp(-a / 3.5) + 0.26 * exp(-a / 11.0);
    if (stage != 2u && have && a > 0.0) {
        var cl = v5_pl_column(a, C);
        // (first a cheap bound: a fat stick from under the land up to the cap's core circle, leaning with the wind, as
        // wide as the cap's rim and its lumps; its rounded top holds the dome. Its top at the core's height, not over
        // the cap: from a point higher up the rim's lumps lie further off than the rim's radius, and were cut off)
        let ctop = C + vec3<f32>(0.0, cl.hc, 0.0) + pl_wind() * a;
        let cbound = pl_ray_seg(rd, C - vec3<f32>(0.0, 20.0, 0.0), ctop, 0.0, 1.0);
        let crad = max(cl.Rt + cl.rt, max(cl.surge.x + cl.surge.y, 0.8 * cl.rt + 0.15 * cl.rt)) + v5_PL_DM + 30.0 + 0.2 * length(pl_wind()) * a;
        let tb = v5_pl_box(rd, cl.lo, cl.hi);
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
            let sootc = mix(vec3<f32>(0.2, 0.16, 0.13), vec3<f32>(0.6, 0.54, 0.48), smoothstep(2.0, 22.0, a));
            for (var i = 0; i < 128; i = i + 1) {
                if (t > t1 || tr < 0.03) {
                    break;
                }
                let p = rd * t;
                let b2 = v5_pl_col_base2(&cl, p);
                let d0 = b2.x;
                let dr = b2.y;
                let db = min(d0, dr);
                // (far from it, a long step: the body's distance is up to 1.6 times too long under the cap's roll)
                if (db > v5_PL_DM + 14.0) {
                    t = t + (db - v5_PL_DM - 4.0) * 0.52;
                    continue;
                }
                let st = max(5.0, t * 0.009) * (0.75 + 0.5 * j);
                var den = 0.0;
                var ringw = 0.0;
                var sd = vec4<f32>(d0, 0.5, 4.0, 0.5);
                // (deep inside, past where any lump could reach, it is smoke whatever the lumps: none looked up)
                if (d0 < -v5_PL_DM - 6.0) {
                    sd = vec4<f32>(d0, 0.45, 4.0, 0.5);
                    den = thin;
                } else if (d0 < v5_PL_DM + 4.0) {
                    sd = v5_pl_col_sdf(&cl, p, d0, true);
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
                    if (tr > 0.25 || nl == 0) {
                        let fp = p + L * 9.0;
                        lc_face = v5_pl_col_sdf(&cl, fp, v5_pl_col_base2(&cl, fp).x, false).x - sd.x;
                        let s1 = saturate((10.0 - v5_pl_col_base(&cl, p + L * 20.0)) / 34.0);
                        let s2 = saturate((10.0 - v5_pl_col_base(&cl, p + L * 55.0)) / 46.0);
                        let s3 = saturate((8.0 - v5_pl_col_base(&cl, p + L * 120.0)) / 60.0);
                        lc_bulk = exp(-(s1 * 10.0 + s2 * 18.0 + s3 * 22.0) * 0.42);
                        // (the sky's light shut out from under the cap and deep in it: what lies under more of it
                        // darker, its tops lit)
                        sky_occ = saturate((12.0 - v5_pl_col_base(&cl, p + vec3<f32>(0.0, 80.0, 0.0))) / 70.0);
                    }
                    nl = nl + 1;
                    let lam = mix(saturate(0.2 + lc_face / 8.0), 0.65, soft);
                    // (the ring, out from under the cap's edge, catches more of the sun than the stem in its shadow)
                    // (under the cap, the stem, the surge and the ring in its shadow)
                    let capsh = v5_pl_cap_shade(p, L, a, C, cl.hc - 0.3 * cl.rt, cl.Rt + cl.rt);
                    let tsun = max(mix(lc_bulk, 0.7, soft) * lam * capsh, 0.45 * ringw * capsh);
                    let hy = saturate((p.y - C.y) / max(cl.hc + cl.rt, 1.0));
                    let deep = saturate(-d0 / 70.0);
                    let ao = mix((0.55 + 0.45 * sd.y) * (1.0 - 0.6 * deep) * (1.0 - 0.6 * sky_occ), 0.75, soft);
                    let mv = 0.9 + 0.2 * (sd.w - 0.5) + 0.25 * (sd.y - 0.5);
                    // (dusty brown low down, sooty grey-brown up in the cap, a little pink-tan as it ages)
                    var alb = mix(vec3<f32>(0.43, 0.38, 0.32), sootc, smoothstep(0.08, 0.45, hy)) * mv;
                    alb = mix(alb, vec3<f32>(0.85, 0.86, 0.88), ringw);
                    // (the surge's dust darker and browner than the cloud: earth, not smoke)
                    alb = alb * (1.0 - 0.3 * sw);
                    let skyg = mix(mix(skyl, vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.45), fogl, 0.15) * (1.0 - 0.35 * warm);
                    var c = alb * ((skyg * (0.48 * ao * (0.3 + 0.7 * hy)) + vec3<f32>(0.2, 0.17, 0.13) * day * (1.0 - 0.6 * warm) * ao) * mix(0.5, 1.0, capsh) + sunc * vec3<f32>(0.95, 0.85, 0.72) * (1.05 * tsun * ph));
                    // (lit from inside: the fireball's heat in the cap's core and its underside, white-hot at first,
                    // orange, then a dull red fading over tens of seconds; the stem's top lit by it from above)
                    let capw = smoothstep(cl.hc - 1.8 * cl.rt, cl.hc - 0.6 * cl.rt, p.y - C.y);
                    // (the fireball's heat: the whole ball at first, then gathered in the ring's core as it rolls up)
                    let qg = p - C - v5_pl_lean(&cl, p.y - C.y);
                    let gv = vec2<f32>(length(qg.xz) - cl.Rt, (qg.y - cl.hc) * 1.2);
                    let ringc = exp(-dot(gv, gv) / pow(0.55 * cl.rt, 2.0));
                    let core = mix(1.0 - exp(min(d0, 0.0) / (0.22 * cl.rt + 6.0)), ringc, smoothstep(2.0, 9.0, a));
                    let under = 1.0 - smoothstep(cl.hc - 0.6 * cl.rt, cl.hc + 0.5 * cl.rt, p.y - C.y);
                    let surf = 2.2 * exp(-a / 2.0) + 0.9 * exp(-a / 5.0);
                    let e = (heat * 7.0 + surf + glow * (0.06 + 3.2 * core * core * (exp(-a / 6.0) + 0.12)) * (0.3 + 1.4 * under)) * capw * (1.0 - ringw) * (0.12 + 2.0 * (1.0 - sd.y) * (1.0 - sd.y));
                    let tcol = mix(mix(vec3<f32>(0.9, 0.13, 0.03), vec3<f32>(3.0, 1.25, 0.32), saturate(glow * 1.3 + 0.15 * core)), vec3<f32>(3.4, 3.0, 2.4), heat);
                    // (and the land's glow, under it, on the stem and the surge, at first)
                    let lowlit = (1.0 - capw) * (heat * 2.0 + 0.6 * glow) * exp(-max(p.y - C.y, 0.0) / 90.0) * 0.4;
                    // (at night its own glow is most of what lights it, and shows for longer)
                    let en = e * (1.0 + 1.6 * (1.0 - day));
                    c = c * (1.0 - saturate(en * 0.5)) + tcol * (en * 0.6 + lowlit);
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
                let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, ap * 0.75);
                if (stage == 0u) {
                    col = mix(col, ccol, (1.0 - tr) * k * fade);
                } else {
                    pl_over(&hc, ccol, (1.0 - tr) * k * fade);
                }
            }
        }
    }
