// The Convergence's pass, the cracks: the land round the target splitting open (the cracks' glow, the trenches they
// open into and what shows down in them, the fire and the ash rushing out of them, the embers off them). Appended after
// shaders/convergence_ground.wgsl and before convergence.wgsl's `[cv stages]` (mod/build.rs); reads `[cv shared]`,
// `v_uv` and the ground side's helpers (cvg_fire, cvg_draw, cvg_over, cvg_px and its colours). Reached only through
// cv_cracks_soft (called by cv_ground_soft: half size at QUALITY FAST) and cv_cracks_sharp (by cv_ground_sharp).
// ==== [cv cracks] =====================================================================================================
// The soft part is the fire and the ash: a volume along each crack, marched only inside a slab round the crack's own
// curved line (the ray's crossing with it found by two corrections, the slab's span from the crack's local bearing),
// the cracks taken nearest first. The sharp part is analytic: the light the fire throws on the land, the trench each
// crack opens into (traced block by block when the land is left alone: the real fissures' width and depth), the
// magma at the cracks before they open, and the embers carried up with the ash.

// The cracks (strike/convergence.rs's CV_CRACKS, CV_CRACK_R) and where cv_table puts them in mod_data: bearings from
// CVG_CRACK_W, reaches 7 on, the count at 14.
const CVG_CRACKS: i32 = 7;
const CVG_CRACK_R: f32 = 50.0;
const CVG_CRACK_W: u32 = 16u;
// A fissure's columns: those whose middle lies within CVK_HALF of a crack's line (cv_pre_part's `dc < 0.75`).
const CVK_HALF: f32 = 0.75;
// The fire's slab: how far either side of a crack's line it is marched, and from how deep to how high.
const CVK_SLAB: f32 = 6.0;
const CVK_Y0: f32 = -8.0;
const CVK_Y1: f32 = 44.0;
// The jets' height cap, blocks.
const CVK_HMAX: f32 = 34.0;
// Fire colours (linear): smoky red at the edges and tips, orange, yellow, the hot core.
const CVK_F0: vec3<f32> = vec3<f32>(0.32, 0.035, 0.012);
const CVK_F1: vec3<f32> = vec3<f32>(1.0, 0.2, 0.025);
const CVK_F2: vec3<f32> = vec3<f32>(1.0, 0.5, 0.1);
const CVK_F3: vec3<f32> = vec3<f32>(1.0, 0.7, 0.3);

// ---- the cracks (as strike/convergence.rs's cv_crack) -----------------------------------------------------------------
// Crack k's bearing at the target and its reach (from the table; hashed stand-ins until it is in).
fn cvg_crack(k: i32) -> vec2<f32> {
    if (abs(cv_w(CVG_CRACK_W + 14u) - 7.0) < 0.5) {
        return vec2<f32>(cv_w(CVG_CRACK_W + u32(k)), cv_w(CVG_CRACK_W + 7u + u32(k)));
    }
    let s = cv_w(2u);
    return vec2<f32>(TAU * (f32(k) + 0.6 * fh21(vec2<f32>(f32(k) * 7.0 + 1.0, s))) / 7.0, CVG_CRACK_R * (0.65 + 0.35 * fh21(vec2<f32>(f32(k) * 7.0 + 3.0, s))));
}
// Crack k's bearing `r` out from the target (they wander as they run out).
fn cvg_crack_phi(k: i32, base: f32, r: f32) -> f32 {
    let fk = f32(k);
    return base + 0.16 * sin(r * 0.09 + fk * 1.7) + 0.06 * sin(r * 0.31 + fk);
}
// How far the horizontal offset d (from the target) is off the nearest crack, blocks; and how far along it (0..1).
fn cvg_crack_d(d: vec2<f32>) -> vec2<f32> {
    let r = length(d);
    let a = atan2(d.y, d.x);
    var best = 1.0e9;
    var along = 1.0;
    for (var k = 0; k < CVG_CRACKS; k = k + 1) {
        let cr = cvg_crack(k);
        let phi = cvg_crack_phi(k, cr.x, r);
        let dd = abs(fract((a - phi) / TAU + 0.5) - 0.5) * TAU * r;
        let e = select(dd + (r - cr.y) * 3.0, dd, r <= cr.y);
        if (e < best) {
            best = e;
            along = r / CVG_CRACK_R;
        }
    }
    return vec2<f32>(best, along);
}
// The signed distance across crack k (bearing `base`) of the horizontal offset d at r = |d| out, blocks.
fn cvk_across(k: i32, base: f32, d: vec2<f32>, r: f32) -> f32 {
    let a = atan2(d.y, d.x);
    return (fract((a - cvg_crack_phi(k, base, r)) / TAU + 0.5) - 0.5) * TAU * r;
}
// The crack nearest the horizontal offset d: (signed distance across it, its index, its bearing, its reach).
fn cvk_nearest(d: vec2<f32>) -> vec4<f32> {
    let r = length(d);
    let a = atan2(d.y, d.x);
    var best = 1.0e9;
    var out = vec4<f32>(1.0e9, 0.0, 0.0, 0.0);
    for (var k = 0; k < CVG_CRACKS; k = k + 1) {
        let cr = cvg_crack(k);
        let x = (fract((a - cvg_crack_phi(k, cr.x, r)) / TAU + 0.5) - 0.5) * TAU * r;
        let e = abs(x) + max(r - cr.y, 0.0) * 3.0;
        if (e < best) {
            best = e;
            out = vec4<f32>(x, f32(k), cr.x, cr.y);
        }
    }
    return out;
}
// When the crack opens into a fissure at r out (cv_pre_part's t1).
fn cvk_t1(r: f32) -> f32 {
    return CV_BREAK + 0.3 + 4.0 * r / CVG_CRACK_R;
}
// How deep the fissure is under the land's top at r out (cv_pre_part's `deep`, plus the block it opens from).
fn cvk_depth(r: f32) -> f32 {
    return 3.0 + floor(4.0 * saturate(1.0 - r / CVG_CRACK_R));
}
// Whether the column whose middle is at offset cc (from the target) is one of crack k's fissure columns.
fn cvk_in(k: i32, base: f32, reach: f32, cc: vec2<f32>) -> bool {
    let r = length(cc);
    if (r > reach || r >= CVG_CRACK_R) {
        return false;
    }
    return abs(cvk_across(k, base, cc, r)) < CVK_HALF;
}
// Whether the land was really cut (terrain damage on: params[15]'s quarter, as the Fold's); otherwise the pass digs
// the trenches itself.
fn cvk_terrain() -> bool {
    return fract(frame.mod_params[3].w) > 0.125;
}

// ---- the fracture (the omen) ------------------------------------------------------------------------------------------
// Each crack runs out from the target in CVK_NS jumps: a hold (the tip stuck, straining), then a slip (the tip running
// out at 30..80 blocks a second, slowing into the stop). Crack k starts at CVK_RUN0 + 0..0.9 s and reaches its end at
// CVK_RUN1 + 0..0.45 s; the holds take what the slips leave of that. Drawn on the land under the pixel (its position
// from the depth), so it follows slopes; no block changes until the break.
const CVK_NS: i32 = 7;
const CVK_RUN0: f32 = 0.35;
const CVK_RUN1: f32 = 4.2;
// Side cracks: a slot every CVK_BR blocks along a crack, about half of them used.
const CVK_BR: f32 = 4.5;
// Whether the gap snaps to whole columns (true) or runs across the blocks (false).
const CVK_SNAP: bool = false;
// A hash of crack k's i-th draw (`salt` picks which), with the strike's seed.
fn cvk_h(k: i32, i: i32, salt: f32) -> f32 {
    return fh21(vec2<f32>(f32(k) * 13.0 + f32(i) * 1.618 + 0.5, salt * 7.31 + fract(cv_w(2u) * 0.0137) * 977.0));
}
// The crack's line jagged at the block's scale: how far its middle sits off the smooth line r out, blocks.
fn cvk_jag(k: i32, r: f32) -> f32 {
    let fk = f32(k);
    return 1.1 * (fvnoise(vec2<f32>(r * 0.42, fk * 7.3)) - 0.5) + 0.5 * (fvnoise(vec2<f32>(r * 1.6, fk * 3.1 + 9.0)) - 0.5) * smoothstep(1.0, 5.0, r);
}
// Crack k's run (reach `reach`) at r out and at t: (when the tip passed r, where the tip is, how long it has been stuck
// there: < 0 while it has not started or once it has reached its end).
fn cvk_front(k: i32, reach: f32, r: f32, t: f32) -> vec3<f32> {
    let t0 = CVK_RUN0 + 0.9 * cvk_h(k, 0, 1.0);
    let span = CVK_RUN1 + 0.45 * cvk_h(k, 0, 2.0) - t0;
    var sl = 0.0;
    for (var i = 0; i < CVK_NS; i = i + 1) {
        sl = sl + 0.35 + cvk_h(k, i, 3.0);
    }
    let ls = reach / sl;
    var sd = 0.0;
    var sh = 0.0;
    for (var i = 0; i < CVK_NS; i = i + 1) {
        sd = sd + (0.35 + cvk_h(k, i, 3.0)) * ls / (30.0 + 50.0 * cvk_h(k, i, 4.0));
        sh = sh + 0.2 + cvk_h(k, i, 5.0) * select(1.0, 0.3, i == 0);
    }
    let hs = max(span - sd, 0.0) / sh;
    var at = t0;
    var ar = 0.0;
    var T = -1.0;
    var tip = 0.0;
    var held = -1.0;
    for (var i = 0; i < CVK_NS; i = i + 1) {
        let h = (0.2 + cvk_h(k, i, 5.0) * select(1.0, 0.3, i == 0)) * hs;
        let l = (0.35 + cvk_h(k, i, 3.0)) * ls;
        let d = l / (30.0 + 50.0 * cvk_h(k, i, 4.0));
        if (t >= at && t < at + h) {
            tip = ar;
            held = t - at;
        }
        at = at + h;
        if (T < 0.0 && r < ar + l) {
            T = at + d * (1.0 - pow(1.0 - saturate((r - ar) / l), 1.0 / 1.6));
        }
        if (t >= at && t < at + d) {
            tip = ar + l * (1.0 - pow(1.0 - (t - at) / d, 1.6));
            held = 0.0;
        }
        at = at + d;
        ar = ar + l;
    }
    if (T < 0.0) {
        T = at;
    }
    if (t >= at) {
        tip = reach;
    }
    return vec3<f32>(T, tip, held);
}
// The heat of the opened ground (0..1): hot where it has just opened and near the target, cooling behind, the strain
// before the eruption pushing it up, the light under it pulsing slowly along the crack.
fn cvk_heat(k: i32, r: f32, age: f32, sr: f32, t: f32) -> f32 {
    let pl = 0.8 + 0.35 * (fvnoise(vec2<f32>(r * 0.06 - t * 0.45, f32(k) * 3.0 + t * 0.12)) - 0.5);
    return saturate((0.3 + 0.55 * exp(-max(age, 0.0) / 0.9) + 0.25 * exp(-r / 14.0) + 0.45 * sr) * pl);
}
// The open gap at the pixel: `xr` across from its middle (blocks), `w` wide, `D` deep, its across direction `n`;
// `heat` its heat, `fresh` how newly it opened, `up` whether the face is a top. Seen down into: the far wall traced
// for where the ray meets it (dark rock near the lip, lit ever brighter from the glow below), or the molten floor.
fn cvk_gap(v: CvView, xr: f32, w: f32, D: f32, n: vec2<f32>, heat: f32, fresh: f32, up: bool, f: vec2<f32>) -> vec3<f32> {
    let ra = dot(v.rd.xz, n);
    let dn = max(-v.rd.y, 0.02);
    let sg = select(-1.0, 1.0, ra >= 0.0);
    let s = (sg * 0.5 * w - xr) / max(abs(ra), 1.0e-3) * sg;
    var h = s * dn;
    if (!up) {
        h = D * (0.45 + 0.4 * cvk_tex(f, 3.0));
    }
    let hc = cvk_ramp(0.35 + 0.6 * heat);
    if (h >= D) {
        // (the floor: molten, its texels brighter and darker)
        return hc * (1.3 + 0.8 * cvk_tex(f, 7.0)) * (0.7 + 0.5 * heat);
    }
    let fa = length(f - anchor_xz());
    let tx = 0.7 + 0.6 * cvk_tex(vec2<f32>(fa, h), 2.0);
    let rock = vec3<f32>(0.05, 0.04, 0.035) * tx * (0.25 + 0.6 * v.day * exp(-h / 0.6));
    // (lit from the floor: brightest just over it and dark half way up; the lip's edge catching the light from below;
    // the rock glowing where it has only just split; hot air shimmering in the gap)
    let below = exp(-(D - h) / (0.18 * D + 0.25));
    let lip = 0.45 * exp(-h / 0.12);
    return rock + hc * ((1.5 * below + lip + 0.5 * fresh * exp(-(D - h) / 0.7)) * tx + 0.06);
}
// The fracture on the land at the pixel (P target-relative, r out, nearest crack k with bearing `base` and reach
// `reach`, `xs` across its smooth line): the main gap, its side cracks, its lips lit from below, the hairline straining
// ahead of a stuck tip. `land` the land's colour so far, `scene` as the world drew it. Returns (colour, how much of the
// pixel is gap).
fn cvk_fracture(v: CvView, land: vec3<f32>, scene: vec3<f32>, P: vec3<f32>, r: f32, k: i32, base: f32, reach: f32, xs: f32, sr: f32) -> vec4<f32> {
    let t = v.t;
    let anc = anchor_xz();
    var q = P.xz;
    var xq = xs;
    if (CVK_SNAP) {
        q = floor(P.xz + anc) + 0.5 - anc;
        xq = cvk_across(k, base, q, length(q));
    }
    let rq = length(q);
    let rc = min(rq, reach);
    let fr = cvk_front(k, reach, rc, t);
    let age = t - fr.x;
    let px = max(cvg_px(v.len), 0.02);
    let f = P.xz + anc;
    var out = land;
    var cover = 0.0;
    // (the main gap: widening as it opens, widest near the target, its edges rough at the texel's scale; wider again as
    // the land gives way at the break)
    let xj = xq - cvk_jag(k, rc);
    let open = 1.0 - exp(-max(age, 0.0) / 0.4);
    let wm = mix(1.2, 0.35, saturate(rc / reach)) * (0.75 + 0.5 * fvnoise(vec2<f32>(rc * 0.3, f32(k) * 5.0)));
    let w = wm * open * (1.0 + 0.45 * cv_beat(t, CV_BREAK - 0.5, CV_BREAK + 0.5)) * (1.0 - smoothstep(reach - 3.0, reach + 0.3, rq));
    let rough = 0.14 * (cvk_tex(f, 11.0) - 0.5);
    let heat = cvk_heat(k, rc, age, sr, t);
    let n = vec2<f32>(-P.z, P.x) / max(r, 1.0e-3);
    let up = cvk_up(v) > 0.7;
    var gx = 0.5 * w + rough - abs(xj);
    if (CVK_SNAP) {
        gx = select(-1.0, 1.0, abs(xj) < max(0.5 * w, 0.0) && w > 0.25);
    }
    if (age > 0.0 && w > 0.0) {
        let c = saturate(gx / px + 0.5) * saturate(w / px * 1.5 + 0.2);
        if (c > 0.0) {
            let D = 1.0 + 2.5 * w;
            let fresh = exp(-age / 0.6);
            let g = cvk_gap(v, xj - sign(xj) * max(rough, 0.0), max(w, 0.05), D, n, heat, fresh, up, f);
            out = mix(out, g, c);
            cover = c;
        }
        // (the lips lit from below: the light out of the gap on the land just beside it)
        let e = max(abs(xj) - 0.5 * w, 0.0);
        out = out + (scene * 2.2 + vec3<f32>(0.04, 0.01, 0.0)) * cvk_ramp(0.3 + 0.6 * heat) * exp(-e / 0.35) * (1.0 - cover) * open;
    }
    // (the hairline straining out ahead of a stuck tip)
    if (fr.z > 0.0 && rq > fr.y && rq < reach) {
        let a = rq - fr.y;
        let ln = smoothstep(0.0, 0.5, fr.z) * exp(-a / (0.8 + 2.5 * fr.z)) * exp(-abs(xj) / max(0.06, px * 0.5)) * min(0.12 / px, 1.0);
        out = out + cvk_ramp(0.55) * ln * 1.6;
    }
    // (the side cracks: run off the main one as its tip passes, on a little, then die)
    let j0 = floor(rq / CVK_BR);
    for (var jj = 0; jj < 3; jj = jj + 1) {
        let j = i32(j0) - jj;
        let hb = cvk_h(k, 20 + j, 6.0);
        if (j < 0 || hb > 0.6) {
            continue;
        }
        let rj = (f32(j) + 0.2 + 0.6 * cvk_h(k, 20 + j, 7.0)) * CVK_BR;
        if (rj < 3.0 || rj > reach - 2.0) {
            continue;
        }
        let u = rq - rj;
        if (u < 0.0) {
            continue;
        }
        let side = select(-1.0, 1.0, cvk_h(k, 20 + j, 8.0) > 0.5);
        let ang = 0.45 + 0.55 * cvk_h(k, 20 + j, 9.0);
        let ca = cos(ang);
        let Lb = (2.5 + 7.5 * cvk_h(k, 20 + j, 10.0)) * (1.0 - 0.45 * rj / reach);
        let s = u / ca;
        if (s > Lb) {
            continue;
        }
        let ab = t - cvk_front(k, reach, rj, t).x - 0.04 - 0.2 * cvk_h(k, 20 + j, 11.0);
        if (ab <= 0.0) {
            continue;
        }
        // (running out fast and slowing, as the main one's slips)
        let Ln = Lb * (1.0 - exp(-ab / 0.22));
        if (s > Ln) {
            continue;
        }
        let xb = cvk_jag(k, rj) + side * (u * tan(ang) + 0.03 * u * u) + 0.35 * (fvnoise(vec2<f32>(s * 1.3, f32(j) * 3.7 + f32(k))) - 0.5);
        let wb = (0.12 + 0.4 * wm) * (1.0 - s / Lb) * (1.0 - exp(-ab / 0.35));
        let d = abs(xq - xb) * ca;
        let cb = saturate((0.5 * wb + rough * 0.5 - d) / px + 0.5) * min(wb / px * 1.5 + 0.15, 1.0);
        let hb2 = cvk_heat(k, rj + s, ab - s * 0.08, sr, t) * (1.0 - 0.6 * s / Lb);
        if (cb > 0.0) {
            let g = cvk_gap(v, 0.0, max(wb, 0.05), 1.0 + 3.0 * wb, n, hb2, exp(-ab / 0.6), false, f);
            out = mix(out, g, cb * (1.0 - cover));
            cover = max(cover, cb);
        }
        out = out + scene * 1.6 * cvk_ramp(0.3 + 0.5 * hb2) * exp(-max(d - 0.5 * wb, 0.0) / 0.3) * (1.0 - cover) * (1.0 - exp(-ab / 0.3));
    }
    return vec4<f32>(out, cover);
}
// The dust and grit kicked up where a slip stops: a puff at the end of each jump, thrown up fast, spreading and
// settling over two seconds, bigger for a longer jump and near the target, lit from the crack under it. Each puff a
// gaussian blob integrated along the ray in closed form, clipped at the world's depth.
fn cvk_dust(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let t = v.t;
    if (t < CVK_RUN0 || t > CV_BREAK + 2.5) {
        return col;
    }
    let cy = cvg_cyl(v.rd, v.C, CVG_CRACK_R + 6.0, -4.0, 16.0, v.len + 4.0);
    if (cy.x >= cy.y) {
        return col;
    }
    let sun = max(frame.sun.y, 0.0);
    var tau = 0.0;
    var lit = vec3<f32>(0.0);
    for (var k = 0; k < CVG_CRACKS; k = k + 1) {
        let cr = cvg_crack(k);
        let reach = cr.y;
        let t0 = CVK_RUN0 + 0.9 * cvk_h(k, 0, 1.0);
        if (t < t0) {
            continue;
        }
        let span = CVK_RUN1 + 0.45 * cvk_h(k, 0, 2.0) - t0;
        var sl = 0.0;
        var sd = 0.0;
        var sh = 0.0;
        for (var i = 0; i < CVK_NS; i = i + 1) {
            let l = 0.35 + cvk_h(k, i, 3.0);
            sl = sl + l;
            sd = sd + l / (30.0 + 50.0 * cvk_h(k, i, 4.0));
            sh = sh + 0.2 + cvk_h(k, i, 5.0) * select(1.0, 0.3, i == 0);
        }
        let ls = reach / sl;
        let hs = max(span - sd * ls, 0.0) / sh;
        var at = t0;
        var ar = 0.0;
        for (var i = 0; i < CVK_NS; i = i + 1) {
            let l = (0.35 + cvk_h(k, i, 3.0)) * ls;
            at = at + (0.2 + cvk_h(k, i, 5.0) * select(1.0, 0.3, i == 0)) * hs + l / (30.0 + 50.0 * cvk_h(k, i, 4.0));
            ar = ar + l;
            let a = t - at;
            if (a < 0.0) {
                break;
            }
            if (a > 2.4) {
                continue;
            }
            let rr = min(ar, reach);
            let ph = cvg_crack_phi(k, cr.x, rr);
            let hj = cvk_h(k, i, 12.0);
            // (thrown up fast to a block or two, spreading, sinking back a little as it thins)
            let up = (1.0 - exp(-a / 0.18)) * (1.2 + 1.4 * hj) - 0.35 * a;
            let sgm = 0.9 + 2.6 * (1.0 - exp(-a / 0.7)) + 0.03 * l;
            let Q = v.C + vec3<f32>(cos(ph) * rr, cvk_lift(k, rr) + 0.4 + max(up, 0.2), sin(ph) * rr);
            // (squashed: twice as wide as it is high)
            let sc = vec3<f32>(1.0, 2.0, 1.0);
            let d = v.rd * sc;
            let qq = Q * sc;
            let dd = dot(d, d);
            let s = dot(d, qq) / dd;
            let m = max(dot(qq, qq) - s * s * dd, 0.0);
            let e = m / (sgm * sgm);
            if (e > 9.0) {
                continue;
            }
            let A = (1.0 - exp(-a / 0.05)) * exp(-a / 0.75) * (0.18 + 0.02 * l) * (1.0 + exp(-rr / 10.0));
            let clip = smoothstep(-sgm, sgm * 0.5, v.len - s) * smoothstep(0.0, 1.0, s);
            // (grit: the blob broken up at the texel's scale round where the ray passes it)
            let pw = v.rd * s - Q;
            let gr = 0.55 + 0.9 * fvnoise(vec2<f32>(pw.x + pw.y * 0.7, pw.z - pw.y * 0.6) * 2.3 + vec2<f32>(f32(k) * 9.0 + f32(i) * 3.3, a * 1.7));
            let dtau = A * exp(-e) * sgm * 1.7725 / sqrt(dd) * clip * gr;
            tau = tau + dtau;
            lit = lit + dtau * cvk_ramp(0.5) * 0.25 * exp(-max(up, 0.0) / 1.2) * exp(-a / 0.8);
        }
    }
    if (tau <= 1.0e-4) {
        return col;
    }
    let al = (1.0 - exp(-tau)) * v.veil;
    let dc = vec3<f32>(0.3, 0.26, 0.2) * (0.3 + 0.7 * sun * v.day) + lit / tau;
    return mix(col, dc, al);
}

// ---- the jets ---------------------------------------------------------------------------------------------------------
// The fire as the columns fire: a breath lower in the moment before, flaring as they go.
fn cvk_crouch(t: f32) -> f32 {
    let dip = cv_beat(t, CV_CROUCH, CV_FIRE) * (1.0 - cv_beat(t, CV_FIRE, CV_FIRE + 0.12));
    let u = max(t - CV_FIRE, 0.0);
    return 1.0 - 0.2 * dip + 1.1 * smoothstep(0.0, 0.07, u) * exp(-u / 0.5);
}
// How high crack k's fire stands r out at t: nothing until the stretch opens, then a vent under pressure (a fast burst,
// an overshoot, a settle) to a roar that varies along the crack, gusts running out along it, each crack its own, all
// with the fire's strength over the strike (cvg_fire: harder at each surge and over the draw, gone in the blast).
fn cvk_jet(k: i32, r: f32, reach: f32, t: f32, fire: f32) -> f32 {
    let fk = f32(k);
    // (the opening's front ragged, not a wall)
    let u = t - cvk_t1(r) + 0.35 * (fvnoise(vec2<f32>(r * 0.45, fk * 9.1)) - 0.5);
    if (u <= 0.0 || fire <= 0.01) {
        return 0.0;
    }
    let hk = fh21(vec2<f32>(fk, 7.0));
    let roar = 3.0 + 12.0 * pow(fvnoise(vec2<f32>(r * 0.13 + fk * 5.3, t * (0.7 + 0.4 * hk))), 1.6);
    let gust = 21.0 * pow(fvnoise(vec2<f32>(r * 0.075 - t * (1.3 + 1.1 * hk), fk * 3.7 + t * 0.21)), 2.2);
    // (each stretch vents on its own, a little after the crack under it opens: a ragged run of bursts, not a front)
    let uv = max(u - 0.8 * fvnoise(vec2<f32>(r * 0.2, fk * 3.3 + 1.0)), 0.0);
    let q = uv / (0.3 + 0.15 * hk);
    let vent = (16.0 + 10.0 * hk) * q * exp(1.0 - q) + 8.0 * exp(-uv / 2.4) * (1.0 - exp(-uv / 0.1));
    var H = roar * smoothstep(0.0, 0.7, u) + gust * smoothstep(0.3, 1.6, u) + vent;
    // (until the fire breaks out the cracks only lick low: what stands tall over the vent first is the eruption)
    H = H * mix(0.22, 1.0, cv_beat(t, CV_RED0, CV_RED0 + 0.25));
    // (the eruption: hissing a little harder near the target as the strain builds, low, so no tall sheet with its ash
    // stands over the vent ahead of the fire; then a gout running out along every crack from the target as it breaks out)
    H = H * (1.0 + 1.6 * cvk_erupt_wave(r, t)) + 3.0 * cvg_strain(t) * exp(-r / 18.0) * (0.6 + 0.8 * fvnoise(vec2<f32>(t * 5.0 + fk * 3.1, r * 0.3)));
    H = H * (0.5 + 0.5 * min(fire, 2.2)) * saturate(fire * 2.0) * cvk_crouch(t);
    H = H * (1.0 - 0.45 * saturate(r / reach)) * (1.0 - smoothstep(reach - 6.0, reach + 0.5, r)) * smoothstep(0.5, 5.0, r);
    return CVK_HMAX * (1.0 - exp(-H / CVK_HMAX));
}
// The eruption's wave out along the cracks r out at t: arriving from the target at 55 blocks a second as the fire breaks
// out (CV_RED0), a hard attack dying over most of a second.
fn cvk_erupt_wave(r: f32, t: f32) -> f32 {
    let u = t - CV_RED0 - r / 55.0;
    if (u <= 0.0) {
        return 0.0;
    }
    return smoothstep(0.0, 0.08, u) * exp(-u / 0.8);
}
// The strain before the eruption r out: strongest over the target.
fn cvk_strain(r: f32, t: f32) -> f32 {
    return cvg_strain(t) * exp(-r / 22.0);
}
// The fire's colour at temperature T (0..1): smoky red, orange, yellow, the core; its own light with it.
fn cvk_ramp(T: f32) -> vec3<f32> {
    let c = mix(mix(CVK_F0, CVK_F1, smoothstep(0.1, 0.4, T)), mix(CVK_F2, CVK_F3, smoothstep(0.75, 1.0, T)), smoothstep(0.4, 0.75, T));
    return c * (0.2 + 1.15 * T * T);
}

// ---- the soft part: the fire and the ash ------------------------------------------------------------------------------
// Value noise in 3D on a one-round hash (a third of fvnoise3's), and two octaves of it.
fn cvk_h3(i: vec3<f32>) -> f32 {
    let q = bitcast<vec3<u32>>(vec3<i32>(i));
    return f32(pcg(q.x * 73856093u ^ q.y * 19349663u ^ q.z * 83492791u)) * (1.0 / 4294967295.0);
}
fn cvk_n3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(cvk_h3(i), cvk_h3(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(cvk_h3(i + vec3<f32>(0.0, 1.0, 0.0)), cvk_h3(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(cvk_h3(i + vec3<f32>(0.0, 0.0, 1.0)), cvk_h3(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(cvk_h3(i + vec3<f32>(0.0, 1.0, 1.0)), cvk_h3(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}
fn cvk_fbm3(p: vec3<f32>) -> f32 {
    return 0.62 * cvk_n3(p) + 0.38 * cvk_n3(p * 2.07 + vec3<f32>(5.1, 1.3, 7.7));
}
// The land's height over the target's ground along the cracks (strike/convergence.rs's CV_CRH: 1.0 once they are in,
// then CVK_HN words a crack, evenly out to CVG_CRACK_R), so the fire stands on the land where it slopes: crack k's
// at r out, and the lowest and the highest along it.
const CVK_HW: u32 = 145u;
const CVK_HN: i32 = 6;
fn cvk_lift_in() -> bool {
    return abs(cv_w(CVK_HW) - 1.0) < 0.5;
}
fn cvk_lift(k: i32, r: f32) -> f32 {
    if (!cvk_lift_in()) {
        return 0.0;
    }
    let f = clamp(r / CVG_CRACK_R, 0.0, 1.0) * f32(CVK_HN - 1);
    let i = min(i32(f), CVK_HN - 2);
    let b = CVK_HW + 1u + u32(k * CVK_HN + i);
    return mix(cv_w(b), cv_w(b + 1u), f - f32(i));
}
fn cvk_lift_range(k: i32) -> vec2<f32> {
    if (!cvk_lift_in()) {
        return vec2<f32>(0.0);
    }
    var lo = 0.0;
    var hi = 0.0;
    for (var i = 0; i < CVK_HN; i = i + 1) {
        let h = cv_w(CVK_HW + 1u + u32(k * CVK_HN + i));
        lo = min(lo, h);
        hi = max(hi, h);
    }
    return vec2<f32>(lo, hi);
}
// The fire and the ash of crack k at p (target-relative, its height over the land there): (the fire's density, the
// ash's, the fire's temperature).
fn cvk_dens(k: i32, base: f32, reach: f32, p: vec3<f32>, r: f32, x: f32, t: f32, fire: f32) -> vec3<f32> {
    if (r > reach + 1.0) {
        return vec3<f32>(0.0);
    }
    let H = cvk_jet(k, r, reach, t, fire);
    if (H <= 0.3) {
        return vec3<f32>(0.0);
    }
    let y = p.y;
    let fk = f32(k) * 17.0;
    let yp = max(y, 0.0);
    // (licking: the tongues sway across as they climb, more the higher they go)
    let xs = x + (0.35 + 0.05 * yp) * sin(y * 0.33 - t * 4.3 + r * 0.45 + fk) + 0.25 * sin(y * 0.9 - t * 7.1 + r * 1.3);
    let w = min(0.6 + 0.07 * yp, 1.9);
    let ax = abs(xs) / w;
    let win = 1.0 - smoothstep(CVK_SLAB - 2.0, CVK_SLAB - 0.3, abs(x));
    var fd = 0.0;
    var T = 0.0;
    let hf = y / H;
    if (ax < 2.6 && hf < 1.3) {
        let n = cvk_fbm3(vec3<f32>(xs * 0.7, y * 0.22 - t * 2.4, r * 0.45 + fk));
        let body = exp(-ax * ax * 0.6) * (1.15 - hf);
        // (thin where it leaves the fissure, so the glowing trench shows under it; flame proper a little above)
        fd = saturate((body + (n - 0.5) * 2.4) * 1.6 - 0.45) * (1.0 - smoothstep(1.9, 2.6, ax)) * mix(0.5, 1.0, smoothstep(0.0, 3.0, y)) * smoothstep(CVK_Y0, CVK_Y0 + 2.0, y) * win;
        T = saturate(exp(-ax * ax) * (1.15 - hf) + (n - 0.5) * 0.7 + 0.15 * saturate(-y));
    }
    var ad = 0.0;
    let wa = min(0.9 + 0.1 * yp, 2.2);
    let aa = abs(x) / wa;
    if (aa < 2.2 && y > H * 0.25 && y < 40.0) {
        let m = cvk_n3(vec3<f32>(x * 0.28, y * 0.1 - t * 0.95, r * 0.21 + fk));
        let u = t - cvk_t1(r);
        // (the ash thrown up as a crack opens: before the fire breaks out only a thin wisp of it, so no dark column
        // stands over the vent ahead of the eruption; it thickens behind the gout)
        let puff = (0.55 + 1.2 * exp(-u / 1.6)) * saturate(H / 8.0) * mix(0.12, 1.0, cv_beat(t, CV_RED0 + 0.15, CV_RED0 + 1.0));
        ad = saturate((m - 0.32) * 2.2) * exp(-aa * aa) * smoothstep(H * 0.25, H * 0.85, y) * (1.0 - smoothstep(24.0, 40.0, y)) * win * puff;
    }
    return vec3<f32>(fd, ad, T);
}
// The span of the ray (from O, target-relative, along rd) through crack k's slab, clipped to [0, lim] and its heights:
// (from, to, where it crosses the crack's line, how fast it crosses it: blocks across a block along); from >= to when
// it misses. `lift`: the land's lowest and highest along the crack over the target's ground.
fn cvk_span(k: i32, base: f32, reach: f32, O: vec3<f32>, rd: vec3<f32>, lim: f32, lift: vec2<f32>) -> vec4<f32> {
    let dir = vec2<f32>(cos(base), sin(base));
    let np = vec2<f32>(-dir.y, dir.x);
    var dn = dot(rd.xz, np);
    if (abs(dn) < 1.0e-4) {
        dn = select(-1.0e-4, 1.0e-4, dn >= 0.0);
    }
    let on = dot(O.xz, np);
    var tc = -on / dn;
    for (var i = 0; i < 2; i = i + 1) {
        let rr = clamp(dot((O + rd * tc).xz, dir), 0.0, reach);
        tc = (rr * sin(cvg_crack_phi(k, base, rr) - base) - on) / dn;
    }
    let rr = dot((O + rd * tc).xz, dir);
    // (the crack's own bearing there, its wander included: how fast the ray crosses it)
    let rc = clamp(rr, 0.0, reach);
    let fk = f32(k);
    let ph = cvg_crack_phi(k, base, rc);
    let dph = 0.0144 * cos(rc * 0.09 + fk * 1.7) + 0.0186 * cos(rc * 0.31 + fk);
    let tg = normalize(vec2<f32>(cos(ph), sin(ph)) + rc * dph * vec2<f32>(-sin(ph), cos(ph)));
    let s = abs(tg.x * rd.z - tg.y * rd.x);
    // (only where the ray is within the crack's reach of the target, at the slab's heights; a ray that crosses the
    // crack clearly only round its crossing, one that runs along it (where the crack's bends can bring it back) the
    // whole way, stepping over what lies off the crack at the fastest the ray could close on it)
    let cy = cvg_cyl(rd, -O, reach + 1.5, CVK_Y0 + lift.x, CVK_Y1 + lift.y, lim);
    if (s > 0.4) {
        let hs = CVK_SLAB * 1.3 / s;
        return vec4<f32>(max(tc - hs, cy.x), min(tc + hs, cy.y), tc, s);
    }
    return vec4<f32>(cy.x, cy.y, clamp(tc, cy.x, cy.y), length(rd.xz) * 1.7 + 0.02);
}
// The fire and the ash along the cracks, nearest crack first: premultiplied colour and transmittance.
fn cvk_fire(v: CvView) -> vec4<f32> {
    let t = v.t;
    let fire = cvg_fire(t);
    if (t < CV_BREAK + 0.3 || fire <= 0.01) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let O = -v.C;
    var sa: array<f32, 7>;
    var sb: array<f32, 7>;
    var key: array<f32, 7>;
    var bases: array<f32, 7>;
    var reaches: array<f32, 7>;
    var rates: array<f32, 7>;
    var hit = false;
    for (var k = 0; k < CVG_CRACKS; k = k + 1) {
        let cr = cvg_crack(k);
        bases[k] = cr.x;
        reaches[k] = cr.y;
        let s = cvk_span(k, cr.x, cr.y, O, v.rd, v.len, cvk_lift_range(k));
        sa[k] = s.x;
        sb[k] = s.y;
        rates[k] = s.w;
        key[k] = select(1.0e9, s.z, s.x < s.y);
        hit = hit || s.x < s.y;
    }
    if (!hit) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let sun = max(frame.sun.y, 0.0);
    let ash_k = cv_k_haze();
    let ashc = vec3<f32>(0.034, 0.03, 0.028) * (0.35 + 0.9 * sun * v.day) + vec3<f32>(0.004);
    let j = ign(floor(v_uv * frame.resolution.xy * 0.5) + vec2<f32>(fract(t * 7.0) * 41.0, 13.0));
    var out = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    for (var n = 0; n < CVG_CRACKS; n = n + 1) {
        // (the nearest crack not yet drawn)
        var kb = -1;
        var best = 1.0e8;
        for (var k = 0; k < CVG_CRACKS; k = k + 1) {
            if (key[k] < best) {
                best = key[k];
                kb = k;
            }
        }
        if (kb < 0 || out.a < 0.02) {
            break;
        }
        key[kb] = 1.0e9;
        // (stepping over what lies well off the crack's line in one go, at the rate the ray closes on it; through the
        // fire and the ash in steps of a block or so, longer far off)
        let b = sb[kb];
        let base = bases[kb];
        let reach = reaches[kb];
        let rate = rates[kb];
        // (at least a twelfth of the span a step, so a ray running along the crack still reaches its end)
        let dmin = max(1.1, (b - sa[kb]) / 16.0);
        var tt = sa[kb] + j * max(dmin, 0.015 * sa[kb]);
        let N = 16 + i32(frame.resolution.x < 0.0);
        for (var i = 0; i < N; i = i + 1) {
            if (tt >= b) {
                break;
            }
            let p0 = O + v.rd * tt;
            let r = length(p0.xz);
            // (over the land there, not over the target's ground)
            let p = vec3<f32>(p0.x, p0.y - cvk_lift(kb, r), p0.z);
            let x = cvk_across(kb, base, p.xz, r);
            let dt = max(dmin, 0.015 * tt);
            if (abs(x) > 5.0) {
                tt = tt + clamp((abs(x) - 4.5) / rate, dt, 25.0);
                continue;
            }
            tt = tt + dt;
            // (thinning out round the eye: a camera in the fire sees it go by, not a wall)
            let d = cvk_dens(kb, base, reach, p, r, x, t, fire) * smoothstep(2.0, 9.0, tt - dt);
            let sf = d.x * 1.5;
            let sa2 = d.y * 0.45 * ash_k;
            let sg = sf + sa2;
            if (sg <= 1.0e-3) {
                continue;
            }
            let al = 1.0 - exp(-sg * dt);
            // (the ash lit from under by the fire below it)
            let under = CVK_F1 * 0.35 * exp(-max(p.y, 0.0) / 9.0) * min(fire, 1.5);
            let ce = (cvk_ramp(d.z) * sf + (ashc + under) * sa2) / sg;
            out = vec4<f32>(out.rgb + out.a * ce * al, out.a * (1.0 - al));
            if (out.a < 0.02) {
                break;
            }
        }
    }
    return out;
}
// The soft part: premultiplied colour and transmittance over what is behind.
fn cv_cracks_soft(v: CvView) -> vec4<f32> {
    return cvk_fire(v);
}

// ---- the sharp part: the trenches, the glow, the embers ---------------------------------------------------------------
// A block face's texture: one of its 16 by 16 texels at face coordinates f (blocks), hashed.
fn cvk_tex(f: vec2<f32>, s: f32) -> f32 {
    return fh21(floor(f * 16.0) + vec2<f32>(s * 131.0, s * 71.0));
}
// Magma's top at face coordinates f, glowing `g` (0..1), pulsing slowly.
fn cvk_magma(f: vec2<f32>, g: f32, t: f32) -> vec3<f32> {
    let q = floor(f * 16.0) / 16.0;
    let n = fvnoise(q * 3.1 + vec2<f32>(t * 0.15, 0.0)) * 0.65 + fvnoise(q * 7.3 - vec2<f32>(0.0, t * 0.2)) * 0.35;
    let vein = smoothstep(0.5, 0.68, n);
    let tx = 0.8 + 0.4 * cvk_tex(f, 5.0);
    return (vec3<f32>(0.2, 0.035, 0.012) * tx + vec3<f32>(1.25, 0.42, 0.06) * vein * g) * (0.5 + 0.5 * g);
}
// The trench crack k has opened under the land's top at the pixel (the ray's hit P, target-relative), traced column by
// column down the fissure (its columns as cv_pre_part cuts them, each `od` of its depth): the face it reaches, lit by
// the fire at the bottom, with the fire filling the trench. Returns the colour.
fn cvk_trench(v: CvView, k: i32, base: f32, reach: f32, P: vec3<f32>, od: f32, glow: f32) -> vec3<f32> {
    let rd = v.rd;
    let anc = anchor_xz();
    let w0 = P.xz + anc;
    var cell = floor(w0);
    let sx = select(-1.0, 1.0, rd.x >= 0.0);
    let sz = select(-1.0, 1.0, rd.z >= 0.0);
    let ix = 1.0 / max(abs(rd.x), 1.0e-5);
    let iz = 1.0 / max(abs(rd.z), 1.0e-5);
    var tmx = (cell.x + max(sx, 0.0) - w0.x) * sx * ix;
    var tmz = (cell.y + max(sz, 0.0) - w0.y) * sz * iz;
    let down = max(-rd.y, 1.0e-4);
    var D = cvk_depth(length(cell + 0.5 - anc)) * od;
    var tau = 0.0;
    var kind = 0;
    var axis = 0;
    for (var i = 0; i < 14; i = i + 1) {
        let tf = D / down;
        let tn = min(tmx, tmz);
        if (tf <= tn) {
            tau = tf;
            kind = 1;
            break;
        }
        tau = tn;
        if (tmx < tmz) {
            cell.x = cell.x + sx;
            tmx = tmx + ix;
            axis = 0;
        } else {
            cell.y = cell.y + sz;
            tmz = tmz + iz;
            axis = 1;
        }
        let cc = cell + 0.5 - anc;
        let Dn = cvk_depth(length(cc)) * od;
        if (!cvk_in(k, base, reach, cc) || tau * down > Dn) {
            kind = 2;
            break;
        }
        D = Dn;
    }
    let h = tau * down;
    let H = P + rd * tau;
    let wy = H.y + v.C.y + frame.camera_position.y;
    var col = vec3<f32>(0.0);
    if (kind == 1) {
        col = cvk_magma(H.xz + anc, glow, v.t);
    } else {
        // (a wall: earth under the top, stone below, lit from the bottom and a little by the sky at the lip)
        let f = select(vec2<f32>(H.x + anc.x, wy), vec2<f32>(H.z + anc.y, wy), axis == 0);
        let tx = 0.75 + 0.5 * cvk_tex(f, f32(axis));
        let alb = mix(vec3<f32>(0.2, 0.13, 0.08), vec3<f32>(0.2, 0.19, 0.19), smoothstep(1.0, 1.6, h)) * tx;
        let hot = exp(-max(D - h, 0.0) / 2.2);
        let Ld = (CVK_F1 * 0.6 + CVK_F2 * 2.6 * hot) * glow + vec3<f32>(0.5, 0.56, 0.68) * v.day * exp(-h / 0.7) * 0.35;
        // (the rock glowing hot near the bottom, brightest in its texels' cracks)
        col = alb * Ld + CVK_F1 * exp(-max(D - h, 0.0) / 1.2) * (0.35 + 0.6 * step(0.92, tx - 0.25)) * glow;
    }
    // (the fire filling the trench: its light along the ray's way down)
    let fill = (1.0 - exp(-tau * 0.45)) * saturate(glow) * 0.6;
    return mix(col, cvk_ramp(0.55 + 0.35 * saturate(h / max(D, 1.0))), fill);
}
// How much the land's face at the pixel faces up (its normal from the depths of the pixels beside it).
fn cvk_up(v: CvView) -> f32 {
    let px = frame.resolution.zw;
    let ua = v_uv + vec2<f32>(px.x, 0.0);
    let ub = v_uv + vec2<f32>(0.0, px.y);
    let a = world_offset(ua, depth_at(ua)) - v.rel;
    let b = world_offset(ub, depth_at(ub)) - v.rel;
    let n = cross(a, b);
    return abs(n.y) / max(length(n), 1.0e-6);
}
// The land round the cracks: the fracture running out over the omen (cvk_fracture), the light out of it on the land
// (flickering with the jets once they burn), the trenches the fissures open into at the break (dug by the pass when the
// land was left alone; when it was cut, the light down in the real ones, and the drawn gap giving way to them).
// Changes only what the land shows, through the soft parts' veil.
fn cvk_land(v: CvView, col: vec3<f32>, fire: f32) -> vec3<f32> {
    let t = v.t;
    let P = v.rel - v.C;
    let r = length(P.xz);
    if (r > CVG_CRACK_R + 20.0) {
        return col;
    }
    let nc = cvk_nearest(P.xz);
    let x = abs(nc.x);
    if (x > 30.0) {
        return col;
    }
    let k = i32(nc.y + 0.5);
    let base = nc.z;
    let reach = nc.w;
    let rc = min(r, reach);
    let fr = cvk_front(k, reach, rc, t);
    let age = t - fr.x;
    // (the light comes out only behind the tip)
    let g = smoothstep(0.0, 0.5, age);
    if (g <= 0.0 && fr.z <= 0.0) {
        return col;
    }
    let H = cvk_jet(k, rc, reach, t, fire);
    let sr = cvk_strain(r, t);
    let heat = cvk_heat(k, rc, age, sr, t);
    let I = g * (0.45 + 0.5 * heat + 0.25 * min(fire, 2.0)) * (1.0 + 0.03 * H) * (1.0 - smoothstep(reach, reach + 8.0, r)) * (1.0 + 1.8 * sr + 1.2 * cvk_erupt_wave(r, t));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, v_uv, 0.0).rgb);
    // (the light: a band hugging the crack, a wide warm wash, less on what stands high over it)
    let lift = 1.0 / (1.0 + max(P.y - cvk_lift(k, rc), 0.0) / (5.0 + 0.5 * H));
    let L = (mix(CVK_F1, CVK_F2, max(sr, 0.4 * heat)) * exp(-x / (1.6 * (1.0 + 1.2 * sr))) + mix(CVK_F1, CVK_F2, 0.3) * exp(-x / 9.0) * 0.3) * I * lift;
    var land = scene * (1.0 + L);
    let dug = cvk_terrain() && t > cvk_t1(rc);
    // (not on what stands over the land: trees, walls; known once the land's heights along the cracks are in)
    let oy = P.y - cvk_lift(k, rc);
    let onland = !cvk_lift_in() || (oy > -4.0 && oy < 3.5);
    if (x < 12.0 && r < reach + 3.0 && onland) {
        // (in the real fissures once they are cut: the drawn gap gone over a second as the fire stands in them)
        var keep = 1.0;
        if (cvk_terrain()) {
            keep = 1.0 - cv_beat(t, cvk_t1(rc), cvk_t1(rc) + 1.2) * (1.0 - smoothstep(1.0, 2.5, x));
        }
        if (keep > 0.0) {
            let fx = cvk_fracture(v, land, scene, P, r, k, base, reach, nc.x, sr);
            land = mix(land, fx.rgb, keep);
        }
    }
    if (!cvk_terrain() && x < 1.6 && r < reach + 1.0) {
        let anc = anchor_xz();
        let cc = floor(P.xz + anc) + 0.5 - anc;
        if (cvk_in(k, base, reach, cc)) {
            let u = t - cvk_t1(length(cc));
            if (u > 0.0 && cvk_up(v) > 0.9) {
                // (the fissure opening under the drawn gap: the floor dropping away)
                let q = saturate(u / 0.3);
                let od = 1.0 - (1.0 - q) * (1.0 - q) * (1.0 - q);
                let tr = cvk_trench(v, k, base, reach, P, max(od, 0.05), I);
                land = mix(land, tr, smoothstep(0.0, 0.12, u));
            }
        }
    }
    if (dug && x < 2.5) {
        // (down in the real fissures: the walls lit from the magma at their foot)
        let deep = saturate(cvk_lift(k, rc) - P.y - 0.5);
        land = land + scene * CVK_F2 * deep * 2.0 * I * exp(-x / 1.2) + CVK_F1 * exp(-x / 1.0) * (0.05 + 0.4 * deep) * I;
    }
    return col + (land - scene) * v.veil;
}
// Embers carried up with the ash: on a few planes facing the camera through the target, rising at different speeds
// with the air's own sway (one coherent field, so they drift together and apart), each row of them set off on its own
// so they never stack into lines, streaked by their speed, sized and timed each its own, only over the cracks that
// have opened, cooling as they climb; drawn into the meeting point over the draw.
fn cvk_embers(v: CvView, col: vec3<f32>, fire: f32) -> vec3<f32> {
    let t = v.t;
    if (t < CV_BREAK + 0.3 || fire <= 0.02) {
        return col;
    }
    var c = col;
    let draw = cvg_draw(t);
    let O = mix(v.C, v.C + vec3<f32>(0.0, cv_meet_y(t), 0.0), draw);
    let sc = 1.0 - 0.7 * draw;
    let nh = normalize(O.xz + vec2<f32>(1.0e-3, 0.0));
    let n = vec3<f32>(nh.x, 0.0, nh.y);
    let dn = dot(v.rd, n);
    if (dn < 0.08) {
        return c;
    }
    let right = vec3<f32>(-nh.y, 0.0, nh.x);
    let see = mix(v.veil, 1.0, 0.5);
    for (var i = 0; i < 3; i = i + 1) {
        let fi = f32(i);
        let Q = O + n * (fi - 1.0) * 20.0 * sc;
        let th = dot(Q, n) / dn;
        if (th <= 0.5 || th > v.len) {
            continue;
        }
        let Pw = v.rd * th - O;
        let y = (Pw.y + (O.y - v.C.y)) / sc;
        var g = vec2<f32>(dot(Pw, right), Pw.y) / sc;
        if (abs(g.x) > 70.0 || y < -2.0 || y > 75.0) {
            continue;
        }
        // (the air's sway, then the field scrolled up at this plane's speed; each row offset on its own)
        g = g + (vec2<f32>(fvnoise(g * 0.06 + vec2<f32>(t * 0.35, fi * 7.0)), fvnoise(g * 0.06 + vec2<f32>(fi * 3.0, t * 0.3 + 5.0))) - 0.5) * 9.0;
        let cell = 2.4 + 0.5 * fi;
        let rise = 9.0 + 4.5 * fi;
        let gy = g.y - rise * t;
        let row = floor(gy / cell);
        let gx = g.x + fh21(vec2<f32>(row, 31.0 + fi)) * cell;
        let id = vec2<f32>(floor(gx / cell), row);
        let h = fh21(id + vec2<f32>(fi * 17.0, 3.0));
        if (h > 0.4) {
            continue;
        }
        let h2 = fh21(id + vec2<f32>(fi * 5.0 + 9.0, 29.0));
        let h3 = fract(h2 * 13.7);
        let ce = (id + 0.15 + 0.7 * vec2<f32>(h2, h3)) * cell;
        let dd = vec2<f32>(gx, gy) - ce;
        let rw = 0.09 + 0.12 * h3;
        let px = max(rw, cvg_px(th) * 0.9);
        let st = 1.0 + rise * 0.025 / px;
        let d2 = (dd.x * dd.x + dd.y * dd.y / (st * st)) * sc * sc;
        let s = exp(-d2 / (px * px)) * (rw / px);
        if (s < 0.004) {
            continue;
        }
        // (only over cracks that have opened, spreading as they climb)
        let src = (v.rd * th - v.C).xz;
        let cd = cvg_crack_d(src);
        let rs = length(src);
        let open = cv_beat(t, cvk_t1(rs), cvk_t1(rs) + 0.8);
        let keep = exp(-cd.x / (1.5 + 0.35 * max(y, 0.0))) * open * smoothstep(-2.0, 1.5, y) * exp(-max(y, 0.0) / (20.0 + 25.0 * h2)) * (1.0 - smoothstep(55.0, 75.0, y)) * (1.0 - smoothstep(55.0, 70.0, abs(g.x)));
        let fl = 0.6 + 0.4 * sin(t * (10.0 + 9.0 * h2) + h3 * 40.0);
        let hot = exp(-max(y, 0.0) / 14.0);
        c = c + mix(CVK_F1, CVK_F3, hot * (0.5 + 0.5 * h3)) * s * keep * fl * (2.5 + 1.5 * min(fire, 2.0) + 4.0 * draw + 5.0 * cvg_burst(t - CV_RED0)) * see;
    }
    return c;
}
// The sharp part, over the picture.
fn cv_cracks_sharp(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let fire = cvg_fire(v.t);
    if (fire <= 0.0 && v.t > CV_BREAK) {
        return col;
    }
    var c = col;
    if (!v.sky) {
        c = cvk_land(v, c, fire);
    }
    c = cvk_dust(v, c);
    return cvk_embers(v, c, fire);
}
// ==== [end cv cracks] =================================================================================================
