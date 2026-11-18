// The Earthquake's pass, the dust: what the breaking land throws into the air. Joined into shaders/earthquake.wgsl at its
// `[eq stages]` line (mod/build.rs, tools/check-shader.sh, tools/preview.py), so it reads `[eq shared]` and the plates
// (shaders/earthquake_plates.wgsl). Drawn by fs_half at QUALITY FAST (half size) and by fs_main at QUALITY FULL, through
// the one march `eqd_march`, called once in each.
//
// Its sources, all from the plates' own times (every one thinning away, none ending in a frame):
//   the crack's breath (from EQ_CRACK to a few seconds past the first heave): grit jetting out of the cut just behind the crack's front as it races out (the plates'
//     crack time, `eqd_arrive`, mirrors strike/earthquake.rs's `arrive`), tallest on the main fault, then hanging and
//     thinning;
//   each lurch (EQ_HEAVE to EQ_STILL): along the boundaries of the plates that slip, dust boiling up from the foot of the moving wall
//     (the lower side's ground) to about a third of the wall's height, the canyon side wider, a thin skin rolling off
//     the higher side's lip; never over its top;
//   the climax (EQ_CLIMAX): a low front rolling out from the main fault over both sides to about 220 blocks, hugging each
//     plate's ground as drawn, thinning as it goes;
//   after (from just past the climax to the end): a haze over the canyon and the cliff's foot drifting off and settling.
// Cost: the ray is clipped to a box round the zone in fault coordinates and to a band of heights by the time; the march
// has a fixed run-time count of steps, a share of them placed in a window round the ray's crossing of the main fault's
// plane (its curtain is thin and the heaviest); a sample works out its plate and its nearest boundary in O(1) through
// the plates' own lookup (`eq_cell`) and its neighbour's by one more; the plates' lurches are read from the table
// (strike/eq_fx.rs: no hashing of lurches per sample), only the two lurches round the moment; the light is worked out
// outside the loop and only mixed in it.
// ==== [eq dust] =======================================================================================================
// The table's dust words (strike/eq_fx.rs: EQ_FX, EQ_FX_STRIDE): a block a plate, its offset (x, y, z), its lurch count,
// then each lurch's start and length.
const EQD_FX: u32 = 64u;
const EQD_STRIDE: u32 = 20u;
const EQD_STEPS: u32 = 16u;          // samples a ray, all told
const EQD_MAIN_STEPS: u32 = 7u;      // of them in the window round the main fault
const EQD_SIGMA: f32 = 0.32;         // extinction a block at density 1
// (the preview only: the land under the dust left where it lies, for a renderer with no world warp: tools/preview.py)
const EQD_STILL_LAND: bool = false;
const EQD_ALB: vec3<f32> = vec3<f32>(0.5, 0.42, 0.32);   // the dust's own colour (soil and stone, linear)
// The land's own heights (strike/eq_ground.rs: EQ_H, EQ_HU, EQ_HV, EQ_HALF_V): from word EQD_H 1 once they are in, u's
// two ends along the fault, the lowest and the highest, then after EQD_HEAD words EQD_HU x EQD_HV heights over the
// target's level, a row a v (EQD_HALF_V to each side of the fault).
const EQD_H: u32 = 512u;
const EQD_HEAD: u32 = 8u;
const EQD_HU: u32 = 64u;
const EQD_HV: u32 = 56u;
const EQD_HALF_V: f32 = 250.0;

struct EqdCtx {
    c: EqCfg,
    t: f32,
    k1: i32,            // the latest lurch begun (or about to), -1 none
    cum: f32,           // the plates' share from the lurches before the two round the moment
    rest_one: bool,     // every plate exactly on its offset (or exactly home)
    hon: bool,          // the land's heights are in
    hu: vec2<f32>,      // their grid's two ends along the fault
    hy: vec2<f32>,      // the lowest and the highest of them
    wind: vec2<f32>,
    cv: f32,            // the cracks' speed, blocks a second
    cend: f32,          // where the main crack ends toward the player (u)
    amt: f32,           // the knob `dust`
}
struct EqdPl {
    dy: f32,            // how far its ground has gone up (or down) at t
    lift: f32,          // how far its ground is drawn up (or down): dy (the preview's still land: none)
    slid: vec2<f32>,    // how far it is drawn across the land (x, z)
    act: f32,           // the dust its lurches have thrown, still in the air (0 to ~1.6)
    grow: f32,          // how far that dust has boiled up (0 to 1)
}

// The lurches' base times and shares (earthquake_plates.wgsl's eq_lurch, the same arrays).
fn eqd_base(k: i32) -> f32 {
    var b = array<f32, 7>(6.0, 8.5, 11.0, 13.5, 18.5, 33.5, 38.4);
    return b[clamp(k, 0, 6)];
}
fn eqd_share_k(k: i32) -> f32 {
    var s = array<f32, 7>(0.35, 0.12, 0.1, 0.06, 0.37, -0.6, -0.4);
    return s[clamp(k, 0, 6)];
}
// How much dust lurch k throws, by its share (the climax most, the first heave a little less).
fn eqd_kick(k: i32) -> f32 {
    var m = array<f32, 7>(1.45, 0.8, 0.7, 0.45, 1.7, 0.55, 0.4);
    return m[clamp(k, 0, 6)];
}

// What the march needs about the moment and the pixel, once.
fn eqd_ctx(v: EqView) -> EqdCtx {
    var x: EqdCtx;
    let c = eq_cfg();
    x.c = c;
    x.t = v.t;
    let n = eq_lurches(c);
    var k1 = -1;
    for (var k = 0; k < n; k = k + 1) {
        if (eqd_base(k) - 0.7 <= v.t) {
            k1 = k;
        }
    }
    x.k1 = k1;
    var cum = 0.0;
    for (var k = 0; k < k1 - 1; k = k + 1) {
        cum = cum + eqd_share_k(k);
    }
    x.cum = cum;
    x.rest_one = (c.rest && v.t >= EQ_STILL) || v.t >= EQ_BACK_END;
    let a = 6.2831853 * eq_u(eq_h(c.seed, 300u, 1u));
    x.wind = vec2<f32>(cos(a), sin(a)) * 2.2;
    x.cv = max(EQ_CRACK_V, 2.6 * c.reach / (EQ_CRACK_BY - 0.3 - EQ_CRACK));
    x.cend = eq_w(16u);
    x.amt = eq_k_dust();
    // (the land's own heights, once the world has answered: until then level)
    x.hon = eq_w(EQD_H) > 0.5;
    x.hu = vec2<f32>(eq_w(EQD_H + 1u), eq_w(EQD_H + 2u));
    x.hy = select(vec2<f32>(0.0), vec2<f32>(eq_w(EQD_H + 3u), eq_w(EQD_H + 4u)), x.hon);
    return x;
}
// The land's own height over the target's level at p (target-relative x, z, where the land lay before it moved): the
// grid between its four points; level until it is in.
fn eqd_land(x: EqdCtx, p: vec2<f32>) -> f32 {
    if (!x.hon) {
        return 0.0;
    }
    let u = dot(p, x.c.fdir) - x.c.shift.x;
    let v = dot(p, vec2<f32>(-x.c.fdir.y, x.c.fdir.x)) - x.c.shift.y;
    let g = vec2<f32>(saturate((u - x.hu.x) / max(x.hu.y - x.hu.x, 1.0)) * f32(EQD_HU - 1u), saturate((v + EQD_HALF_V) / (2.0 * EQD_HALF_V)) * f32(EQD_HV - 1u));
    let i = min(vec2<u32>(g), vec2<u32>(EQD_HU - 2u, EQD_HV - 2u));
    let f = g - vec2<f32>(i);
    let b = EQD_H + EQD_HEAD + i.y * EQD_HU + i.x;
    return mix(mix(eq_w(b), eq_w(b + 1u), f.x), mix(eq_w(b + EQD_HU), eq_w(b + EQD_HU + 1u), f.x), f.y);
}
// Plate i at the moment: its ground's rise, the dust its two lurches round the moment have thrown, how far it has boiled up.
fn eqd_pl(x: EqdCtx, i: i32) -> EqdPl {
    var o: EqdPl;
    o.dy = 0.0;
    o.lift = 0.0;
    o.slid = vec2<f32>(0.0);
    o.act = 0.0;
    o.grow = 0.0;
    if (i < 0 || i >= EQ_PLATES) {
        return o;
    }
    let b = EQD_FX + u32(i) * EQD_STRIDE;
    let oy = eq_w(b + 1u);
    let t = x.t;
    var share = x.cum;
    var gw = 0.0;
    for (var j = 0; j < 2; j = j + 1) {
        let k = x.k1 - 1 + j;
        if (k >= 0) {
            let lt = eq_w(b + 4u + 2u * u32(k));
            let ld = max(eq_w(b + 5u + 2u * u32(k)), 0.1);
            let s = t - lt;
            share = share + eqd_share_k(k) * eq_ease_k(k, s / ld);
            if (s > 0.0) {
                let tau = select(3.0, 5.5, k == EQ_K_CLIMAX);
                let a = eqd_kick(k) * smoothstep(0.0, 0.25 * ld + 0.1, s) * exp(-max(s - 0.6 * ld, 0.0) / tau);
                o.act = o.act + a;
                gw = gw + a * (1.0 - exp(-s / 0.9));
            }
        }
    }
    if (x.rest_one) {
        share = select(0.0, 1.0, x.c.rest);
    }
    o.dy = oy * share;
    o.lift = select(o.dy, 0.0, EQD_STILL_LAND);
    o.slid = select(vec2<f32>(eq_w(b), eq_w(b + 2u)) * share, vec2<f32>(0.0), EQD_STILL_LAND);
    o.grow = gw / max(o.act, 1.0e-4);
    return o;
}
// When the crack reaches fault point w on a boundary of kind `kind` (strike/earthquake.rs's `arrive`).
fn eqd_arrive(x: EqdCtx, w: vec2<f32>, kind: i32) -> f32 {
    let v = x.cv;
    let R = x.c.reach;
    let s = EQ_SEG * R;
    let uz = (EQ_CAP + 1.07) * R;
    var path = 0.0;
    if (kind == 0) {
        let u = abs(w.x);
        if (u > uz) {
            let tz = EQ_CRACK + uz / v;
            let v2 = max(v, (x.cend - uz) / (EQ_CRACK_BY - 0.3 - tz));
            return min(tz + (u - uz) / v2, EQ_CRACK_BY - 0.3);
        }
        path = u;
    } else if (kind == 2) {
        path = s + abs(w.y);
    } else {
        path = s + abs(w.y) + abs(abs(w.x) - s);
    }
    return EQ_CRACK + path / v;
}
// The band (0-3 the up side from the fault out, 4-6 the down side) and the segment (0-2 along) of fault point w, as
// eq_cell finds them, the rim aside.
fn eqd_band(w: vec2<f32>, R: f32) -> i32 {
    let a = abs(w.y);
    if (w.y >= 0.0) {
        return select(select(select(3, 2, a < EQ_UP_E3 * R), 1, a < EQ_UP_E2 * R), 0, a < EQ_UP_E1 * R);
    }
    return select(select(6, 5, a < EQ_DN_E2 * R), 4, a < EQ_DN_E1 * R);
}
fn eqd_seg(w: vec2<f32>, R: f32) -> i32 {
    let s = EQ_SEG * R;
    return select(select(1, 2, w.x > s), 0, w.x < -s);
}
// The plate across the nearest boundary from fault point w (its cell `cl`), -1 fixed land: worked out from the bands'
// and segments' order, with no second lookup.
fn eqd_nb(R: f32, w: vec2<f32>, cl: EqWhere) -> i32 {
    let band = eqd_band(w, R);
    let seg = eqd_seg(w, R);
    if (cl.plate < 0) {
        // (past the rim: the plate inside it)
        return band * 3 + seg;
    }
    if (cl.kind == 0) {
        return select(seg, 12 + seg, band == 0);
    }
    if (cl.kind == 1) {
        var lo = array<f32, 7>(0.0, EQ_UP_E1, EQ_UP_E2, EQ_UP_E3, 0.0, EQ_DN_E1, EQ_DN_E2);
        var hi = array<f32, 7>(EQ_UP_E1, EQ_UP_E2, EQ_UP_E3, 1.0e6, EQ_DN_E1, EQ_DN_E2, 1.0e6);
        let a = abs(w.y) / R;
        let first = band == 0 || band == 4;
        let last = band == 3 || band == 6;
        let out = !last && (first || hi[band] - a < a - lo[band]);
        return (band + select(-1, 1, out)) * 3 + seg;
    }
    if (cl.kind == 2) {
        let ns = select(select(2, 0, w.x < 0.0), 1, seg != 1);
        return band * 3 + ns;
    }
    return -1;
}

// The dust at P (target-relative): its density, how lit it is (0 shade to 1 the sun's full face) and how high P stands
// over its ground.
fn eqd_density(x: EqdCtx, P: vec3<f32>) -> vec3<f32> {
    let c = x.c;
    let t = x.t;
    let q = eq_bent(c, P.xz);
    let w = eq_uv(c, q);
    let rim = eq_rim(c, q);
    let cl = eq_cell(c, w, rim);
    let R = c.reach;
    let main_ext = cl.plate < 0 && w.x > 0.0 && w.x < x.cend && abs(w.y) < 14.0;
    let kind = select(cl.kind, 0, main_ext);
    let e = select(cl.edge, abs(w.y), main_ext);
    let is_main = kind == 0;
    let own = eqd_pl(x, cl.plate);
    // (the ground here: the land's own height where this point lay before its plate moved, and the plate's rise)
    let hb = eqd_land(x, P.xz - own.slid);
    let ground = own.lift + hb;
    var dens = 0.0;
    var lit = 0.0;
    var wsum = 0.0;
    // (the dust's own big lumps, drifting with the wind and rising: where each cloud's top and its front stand wanders
    // with them, so a top is heads of cloud and never a level sheet)
    let dr = P - vec3<f32>(x.wind.x, 0.0, x.wind.y) * t;
    let n1 = fvnoise3(dr * vec3<f32>(1.0 / 10.0, 1.0 / 7.0, 1.0 / 10.0) + vec3<f32>(0.0, -0.32 * t, 0.0));
    let bil = n1 - 0.5;
    // ---- the boundary's dust: the crack's breath and the lurches' -------------------------------------------------
    if (e < 34.0) {
        let nb = select(eqd_nb(R, w, cl), -1, main_ext);
        let other = eqd_pl(x, nb);
        // (no dust where neither side moves: the rim of a plate that stays)
        let moves = cl.plate >= 0 || nb >= 0 || main_ext;
        let side_nb = 0.5 * exp(-e / 4.0);
        // (the boils along the boundary: where it jets hardest, each its own column)
        let along = select(w.y, w.x, kind == 0 || kind == 1);
        let boil = fvnoise(vec2<f32>(along * (1.0 / 16.0), 0.35 * t + f32(kind) * 7.3));
        // the crack's breath
        let at = eqd_arrive(x, w, kind);
        let a = t - at;
        if (moves && a > 0.0 && t < EQ_HEAVE + 3.0) {
            let hmax = select(select(8.0, 5.0, kind == 3), 14.0, is_main) * (0.55 + 0.9 * boil);
            let hb_ = hmax * (0.3 + 0.7 * (1.0 - exp(-a / 0.55)));
            let wb = min(2.6 + 1.5 * sqrt(a) + 0.25 * max(P.y - ground, 0.0), 10.0);
            let h = P.y - ground;
            let amt = (3.2 * exp(-a / 0.45) + 1.1 * exp(-a / 3.2)) * (1.0 - smoothstep(EQ_HEAVE - 0.5, EQ_HEAVE + 3.0, t)) * smoothstep(0.0, 0.08, a);
            let prof = exp(-(e * e) / (wb * wb)) * smoothstep(hb_, 0.25 * hb_, h) * smoothstep(-8.0, -1.0, h);
            let d = amt * prof * select(0.7, 1.0, is_main);
            dens = dens + d;
            lit = lit + d * saturate(h / max(hb_, 1.0));
            wsum = wsum + d;
        }
        // the lurches' dust: from the foot of the moving wall, the lower side wider (the canyon), a skin off the lip
        let act = mix(own.act, other.act, side_nb);
        if (act > 0.003 && moves) {
            let cliff = abs(own.dy - other.dy);
            let g_lo = min(own.lift, other.lift) + hb;
            let g_hi = max(own.lift, other.lift) + hb;
            let grow = mix(own.grow, other.grow, side_nb);
            let hl = (3.0 + cliff * 0.34) * (0.35 + 0.65 * grow) * (0.55 + 0.75 * boil);
            let low_side = own.dy <= other.dy;
            let wl = select(3.0 + 0.04 * cliff, 6.0 + 0.2 * cliff + 3.0 * grow, low_side) * select(0.8, 1.0, is_main);
            let h = P.y - g_lo;
            let prof = exp(-(e * e) / (wl * wl)) * smoothstep(hl, 0.3 * hl, h - 1.1 * bil * hl) * smoothstep(-6.0, 0.0, h);
            // (the lip: a thin skin over the higher side's edge, rolling off it)
            let hl2 = P.y - g_hi;
            let lip = select(0.0, 0.45, !low_side) * exp(-e / 6.0) * smoothstep(4.0 + 3.0 * grow, 0.5, hl2) * smoothstep(-1.0, 0.5, hl2) * min(cliff / 10.0, 1.0);
            let k = act * min(0.35 + cliff / 30.0, 1.1) * select(0.6, 1.0, is_main) * (0.5 + boil);
            let d = k * (prof + lip);
            dens = dens + d;
            lit = lit + d * (0.35 + 0.65 * saturate((P.y - g_lo) / max(cliff, 6.0)));
            wsum = wsum + d;
        }
    }
    // ---- the climax's front, rolling out over the land from the main fault ---------------------------------------------
    let sc = t - EQ_CLIMAX;
    if (sc > 0.0 && sc < 14.0) {
        let dm = abs(w.y);
        let rf = 232.0 * (1.0 - exp(-sc / 1.6));
        let xb = rf - dm + 22.0 * bil;
        let ends = 1.0 - smoothstep((EQ_CAP + 0.8) * R, (EQ_CAP + 1.12) * R, abs(w.x) - select(0.0, max(x.cend - (EQ_CAP + 1.0) * R, 0.0), w.x > 0.0));
        if (xb > -4.0 && ends > 0.0) {
            let h = P.y - ground;
            let hf = (9.0 + 4.0 * smoothstep(0.0, 40.0, xb)) * (1.0 - 0.35 * smoothstep(80.0, 220.0, dm));
            let wall = exp(-max(xb, 0.0) / 22.0) * smoothstep(-4.0, 1.5, xb) + 0.18 * exp(-max(xb, 0.0) / 80.0);
            let fade = (1.0 - 0.7 * smoothstep(60.0, 200.0, dm)) * (1.0 - smoothstep(205.0, 240.0, dm)) * exp(-max(sc - 3.5, 0.0) / 3.0);
            let d = 0.9 * wall * fade * ends * smoothstep(hf, 0.2 * hf, h - 1.3 * bil * hf) * smoothstep(-3.0, 0.0, h);
            dens = dens + d;
            lit = lit + d * saturate(0.3 + h / hf);
            wsum = wsum + d;
        }
    }
    // ---- after: a haze over the canyon and the cliff's foot -----------------------------------------------------------
    if (t > EQ_CLIMAX + 1.5 && cl.plate >= 0) {
        let canyon = smoothstep(-0.32 * R, -0.12 * R, w.y) * (1.0 - smoothstep(-2.0, 6.0, w.y));
        if (canyon > 0.0) {
            let h = P.y - ground;
            let ht = 18.0 * (1.0 - 0.4 * smoothstep(EQ_CLIMAX + 5.5, EQ_LEN - 2.0, t));
            let life = smoothstep(EQ_CLIMAX + 1.5, EQ_CLIMAX + 5.5, t) * (1.0 - smoothstep(EQ_CLIMAX + 9.5, EQ_LEN, t));
            let d = 0.09 * canyon * life * smoothstep(ht, 0.0, h - 0.8 * bil * ht) * smoothstep(-4.0, 0.0, h) * (1.0 - smoothstep(0.85 * R, 1.05 * R, abs(w.x)));
            dens = dens + d;
            lit = lit + d * 0.45;
            wsum = wsum + d;
        }
    }
    if (dens <= 1.0e-4) {
        return vec3<f32>(0.0);
    }
    // ---- its grain: lumps that boil up, drift with the wind and fold in ---------------------------------------------
    let n2 = fvnoise3(dr * (1.0 / 3.1) + vec3<f32>(4.1, -0.7 * t, 1.7));
    let n = 0.68 * n1 + 0.32 * n2;
    let dd = dens * saturate(0.15 + (n - 0.5) * 2.6 + 0.35 * min(dens, 1.0));
    return vec3<f32>(dd * x.amt, lit / max(wsum, 1.0e-4) * (0.75 + 0.5 * n1), P.y - ground);
}

// The ray (camera-relative direction `rd`, ending at `tmax`) through the dust: premultiplied colour and transmittance.
// `j`: where in its stride each sample of this pixel's ray lies (0 to 1).
fn eqd_march(v: EqView, rd: vec3<f32>, tmax: f32, j: f32) -> vec4<f32> {
    let t = v.t;
    if (t < EQ_CRACK || t >= EQ_LEN || eq_k_dust() <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    var x = eqd_ctx(v);
    let c = x.c;
    let R = c.reach;
    // (the box round everything that throws dust, in the unbent fault's frame: the bending moves it by at most ~10)
    let o3 = -v.O;
    let perp = vec2<f32>(-c.fdir.y, c.fdir.x);
    let ou = dot(o3.xz, c.fdir) - c.shift.x;
    let ov = dot(o3.xz, perp) - c.shift.y;
    let du = dot(rd.xz, c.fdir);
    let dv = dot(rd.xz, perp);
    let pre = t < EQ_HEAVE - 0.7;
    let U0 = (EQ_CAP + 1.07) * R + 24.0;
    let U1 = max(U0, x.cend + 24.0);
    let V = select(1.07 * R + 20.0, 250.0, t > EQ_CLIMAX);
    // (over and under the land's own heights)
    let y0 = select(-56.0, -26.0, pre) + x.hy.x;
    let y1 = select(74.0, 24.0, pre) + x.hy.y;
    let lo = vec3<f32>(-U0, y0, -V);
    let hi = vec3<f32>(U1, y1, V);
    let ro = vec3<f32>(ou, o3.y, ov);
    let rv = vec3<f32>(du, rd.y, dv);
    let inv = 1.0 / select(rv, vec3<f32>(1.0e-6), abs(rv) < vec3<f32>(1.0e-6));
    let ta = (lo - ro) * inv;
    let tb = (hi - ro) * inv;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    var t0 = max(max(max(tn.x, tn.y), tn.z), 0.0);
    var t1 = min(min(min(tf.x, tf.y), tf.z), tmax);
    if (t1 <= t0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // (on land with relief the box is tall: the stretch of the ray that runs within the dust's reach of the land's own
    // height under it, by a few probes, so the samples are not spent on air far over a valley or rock deep under a hill)
    if (x.hon && x.hy.y - x.hy.x > 12.0) {
        let dp = (t1 - t0) * 0.125;
        let slack = 0.5 * abs(rd.y) * dp + 14.0;
        var a = t1;
        var b = t0;
        for (var k = 0; k < 8; k = k + 1) {
            let ts = t0 + (f32(k) + 0.5) * dp;
            let P = rd * ts - v.O;
            let h = P.y - eqd_land(x, P.xz);
            if (h < select(74.0, 24.0, pre) + slack && h > select(-56.0, -26.0, pre) - slack) {
                a = min(a, ts - 0.5 * dp);
                b = max(b, ts + 0.5 * dp);
            }
        }
        if (b <= a) {
            return vec4<f32>(0.0, 0.0, 0.0, 1.0);
        }
        t0 = a;
        t1 = b;
    }
    // (the window round the main fault's crossing)
    let W = select(30.0, 16.0, pre);
    var m0 = t0;
    var m1 = t0;
    var nm = 0u;
    if (abs(dv) > 1.0e-4) {
        let tm = -ov / dv;
        let hw = W / abs(dv);
        let a = max(tm - hw, t0);
        let b = min(tm + hw, t1);
        if (b > a && (b - a) < 0.7 * (t1 - t0)) {
            m0 = a;
            m1 = b;
            nm = EQD_MAIN_STEPS;
        }
    }
    // (the count read at run time: the loop stays a loop)
    // (fewer where the dust is thin and low: the breath before the heave's dust and the haze after the climax's front)
    let thin = t < EQ_HEAVE - 1.5 || t > EQ_CLIMAX + 9.0;
    let total = select(EQD_STEPS, EQD_STEPS - 5u, thin) + u32(frame.resolution.x < 0.0);
    let rest_n = total - nm;
    let la = m0 - t0;
    let lb = t1 - m1;
    let na = u32(round(f32(rest_n) * la / max(la + lb, 1.0e-3)));
    let nb = rest_n - na;
    // (the light, outside the loop: the sun's colour by its height, the sky's)
    let sy = frame.sun.y;
    let sunc = mix(vec3<f32>(1.0, 0.5, 0.25), vec3<f32>(1.0, 0.95, 0.86), smoothstep(0.0, 0.45, sy)) * 1.35 * smoothstep(-0.06, 0.12, sy);
    // (the sky's light, and the land's own bounced up into it)
    let amb = srgb_to_linear(frame.sky_color.rgb) * 0.3 + vec3<f32>(0.11, 0.09, 0.065) * (0.3 + 0.7 * smoothstep(-0.05, 0.3, sy));
    let sxz = normalize(frame.sun.xz + vec2<f32>(1.0e-4, 0.0));
    let face = 0.5 + 0.5 * dot(-rd.xz, sxz) * length(rd.xz);
    var col = vec3<f32>(0.0);
    var tr = 1.0;
    var tw = 0.0;
    var tsum = 0.0;
    for (var i = 0u; i < total; i = i + 1u) {
        var s0 = t0;
        var len = la;
        var k = i;
        var cnt = na;
        if (i >= na && i < na + nm) {
            s0 = m0;
            len = m1 - m0;
            k = i - na;
            cnt = nm;
        } else if (i >= na + nm) {
            s0 = m1;
            len = lb;
            k = i - na - nm;
            cnt = nb;
        }
        let dt = len / f32(max(cnt, 1u));
        let ts = s0 + (f32(k) + j) * dt;
        let P = rd * ts - v.O;
        let d = eqd_density(x, P);
        if (d.x > 1.0e-4) {
            let a = 1.0 - exp(-d.x * EQD_SIGMA * dt);
            // (darker down in the canyon, under the land)
            let deep = smoothstep(-40.0, 2.0, d.z);
            // (and lit from under by the lava that lies in it, the more the deeper)
            let glow = vec3<f32>(1.0, 0.42, 0.1) * 0.6 * (1.0 - deep) * (1.0 - deep);
            let lc = EQD_ALB * (amb * (0.55 + 0.45 * deep) + sunc * d.y * deep * (0.55 + 0.45 * face) + glow);
            col = col + tr * a * lc;
            tw = tw + tr * a;
            tsum = tsum + tr * a * ts;
            tr = tr * (1.0 - a);
            if (tr < 0.02) {
                break;
            }
        }
    }
    // (the game's fog over it, by how far off it mostly is)
    let dist = tsum / max(tw, 1.0e-4);
    let rdist = max(frame.view_params.z, 64.0);
    let fog = smoothstep(0.55 * rdist, 1.05 * rdist, dist);
    col = mix(col, srgb_to_linear(frame.fog_color.rgb) * (1.0 - tr), fog);
    return vec4<f32>(col, tr);
}
// The dust over the scene's colour (linear): what the march gave laid over it.
fn eqd_over(scene: vec3<f32>, d: vec4<f32>) -> vec3<f32> {
    return scene * d.w + d.rgb;
}
// ==== [end eq dust] ===================================================================================================
