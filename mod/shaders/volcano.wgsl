// Orbital Laser's post pass for the Supervolcano (laser 14). Like the Nuke's, the mod builds it from shaders/strike.wgsl
// up to its fs_main less the other lasers' own functions, followed by this file, and sets it for this strike only.
// Validate with tools/check-shader.sh.

// ---- laser 14: the supervolcano -----------------------------------------------------------------------------------
// A hairline beam, then nothing for ten seconds but the tremor. The land cracks in a ring, steam rising off it; the ring
// opens, a ring of vents 560 across feeds a dark jet that climbs into rough convective cauliflower, overshooting at its
// top (`vc_col`); lava bombs arc off it, smoke behind them (`vc_bombs`); its umbrella spreads flat across the whole sky,
// a ripple running out through it, lightning in rings (`vc_umb`, `vc_flash`); the sky goes dark at noon (`vc_dim`, the
// land and the sky darkened, what glows left glowing, the game's clock and weather never touched). The column loses its
// buoyancy and falls back on itself (`VC_COLLAPSE`), feeding a wall of ash that rolls out over the land in lobes and
// clefts (`vc_flow`), new clouds rising off its top. It engulfs the player: near black, embers. Then a world dimmed
// under falling ash, ending on a blood-red sun as the ash thins, all of it gone by VC_LEN (`vc_gone`).
// strike/volcano.rs keeps its VC_* in step with these, and gives the table: the bombs, the land's height.
const VC_LEN: f32 = 88.0;
const VC_HIT: f32 = 2.0;           // the beam hits and cuts out
const VC_CRACK: f32 = 6.0;         // the ring cracks through
const VC_ERUPT: f32 = 18.0;        // the eruption
const VC_LIGHT: f32 = 26.0;        // the plume's lightning
const VC_DARK: f32 = 36.0;         // the umbrella out over the land
const VC_COLLAPSE: f32 = 50.0;     // the column falls back, the flows set off from the ring
const VC_LIFT: f32 = 66.0;         // the flows lift into new clouds
const VC_RED: f32 = 80.0;          // the ash thinning round a red sun
const VC_RING: f32 = 280.0;        // the ring of vents' radius
const VC_HU: f32 = 1500.0;         // the umbrella's middle over the land
const VC_V: f32 = 343.0;           // the pressure ring's speed (the sound's)
const VC_DM: f32 = 150.0;          // the most the lumps stand out of a smooth body
const VC_BOMB: u32 = 16u;          // the table: the bombs from here, VC_BW words each
const VC_BW: u32 = 8u;
const VC_G: f32 = 28.0;
const VC_HF: u32 = 1024u;          // the land's height (volcano.rs's vc_hf_pack)

fn vc_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
// The land at q (level, from the vent): its height over the vent's ground, smoothly between the heightfield's cells.
fn vc_land(q: vec2<f32>) -> f32 {
    let nf = vc_w(VC_HF);
    if (nf < 2.0) {
        return 0.0;
    }
    let n = u32(nf + 0.5);
    if (arrayLength(&mod_data) < VC_HF + 8u + n * n) {
        return 0.0;
    }
    let R = vc_w(VC_HF + 1u);
    let step = 2.0 * R / (nf - 1.0);
    let fc = clamp((q + R) / step, vec2<f32>(0.0), vec2<f32>(nf - 1.001));
    let i0 = vec2<u32>(floor(fc));
    let t = fc - floor(fc);
    let base = VC_HF + 8u + i0.y * n + i0.x;
    let h = vec4<f32>(f32(mod_data[base] & 0xffffu), f32(mod_data[base + 1u] & 0xffffu), f32(mod_data[base + n] & 0xffffu), f32(mod_data[base + n + 1u] & 0xffffu));
    return mix(mix(h.x, h.y, t.x), mix(h.z, h.w, t.x), t.y) / 8.0 - 512.0;
}

// ---- the story's state at this moment, worked out once a pixel ---------------------------------------------------
struct VcS {
    t: f32,
    a: f32,      // since the eruption
    c: f32,      // since the collapse (under 0 before it)
    H: f32,      // the column's head over the land
    Hb: f32,     // the top of what is still standing of it, as it falls back
    Rt: f32,     // its radius at its head
    up: f32,     // how far its lumps have risen (and fallen back)
    Ru: f32,     // the umbrella's radius
    rf: f32,     // the wall of ash's radius
    rfm: f32,    // and past it nothing
    ftop: f32,   // nothing of the flows stands over this
    cov: f32,    // how much of the light the umbrella stops
    thin: f32,   // 0 to 1: the ash thinning away at the end
    px: f32,     // the angle a pixel spans
    fine: f32,   // (spare)
}
var<private> vs: VcS;
var<private> vc_px: vec2<f32>;

fn vc_front(c: f32) -> f32 {
    return VC_RING + 25.0 * c + 490.0 * (1.0 - exp(-c / 14.0));
}
fn vc_rr(hy: f32) -> f32 {
    return VC_RING - 155.0 * smoothstep(0.0, 190.0, hy);
}
fn vc_ww(hy: f32) -> f32 {
    return 76.0 + 0.52 * min(hy, 190.0) + 0.13 * clamp(hy - 190.0, 0.0, 330.0) + 0.24 * max(hy - 520.0, 0.0);
}
fn vc_set_state(time: f32) {
    var s: VcS;
    s.t = time;
    s.a = time - VC_ERUPT;
    s.c = time - VC_COLLAPSE;
    let a = max(s.a, 0.0);
    s.H = 1900.0 * (1.0 - exp(-(a + 0.15) / 8.5)) + 3.0 * min(a, 30.0);
    s.Rt = vc_rr(s.H) + vc_ww(s.H);
    s.Hb = s.H - 0.5 * 26.0 * max(s.c, 0.0) * max(s.c, 0.0) - 8.0 * max(s.c, 0.0);
    // (rising, then slowing, stopping as its buoyancy goes and falling back, faster and faster)
    let ca = min(a, 32.0);
    s.up = 34.0 * ca + 240.0 * (1.0 - exp(-ca / 3.0)) - 2.2 * max(s.c, 0.0) * max(s.c, 0.0) - 20.0 * max(s.c, 0.0);
    // (a gravity current: quick as the head first spreads, slowing as it thins; out past the horizon by the collapse)
    let u = max(time - 23.0, 0.0);
    s.Ru = 520.0 * smoothstep(0.0, 3.0, u) + 260.0 * pow(u, 1.28) * 0.5;
    s.rf = vc_front(max(s.c, 0.0));
    s.rfm = s.rf + 230.0;
    s.ftop = 340.0 + 1250.0 * smoothstep(VC_LIFT - 4.0, VC_RED - 2.0, time);
    s.thin = smoothstep(VC_RED - 4.0, VC_LEN - 0.6, time);
    s.cov = smoothstep(0.0, 8.0, u) * (1.0 - s.thin);
    s.px = frame.view_params.w / frame.resolution.y;
    vs = s;
}

// ---- the shapes: each one's smooth body, as a distance ----------------------------------------------------------
// The column: a ring of vents at the land, drawn in and merging as they rise into one flaring body, a dome over its
// head, bulging while it climbs. `ang` the bearing round the vent.
fn vc_col(q: vec3<f32>, rho: f32, ang: f32) -> f32 {
    let t = vs.t;
    if (t < VC_CRACK) {
        return 1.0e5;
    }
    // (its foot on the land round the ring, not at the vent's height: the ring may lie over hills and valleys)
    var hy = q.y;
    if (hy < 700.0) {
        hy = hy - vc_land(q.xz) * (1.0 - smoothstep(120.0, 700.0, hy));
    }
    // (steam first, thin jets along the crack)
    let st = saturate((t - VC_CRACK) / (VC_ERUPT - VC_CRACK));
    let on = smoothstep(0.0, 0.7, vs.a);
    let Hs = 12.0 + 50.0 * st;
    let H = max(vs.H, Hs);
    let Rr = vc_rr(hy);
    var W = mix(2.0 + 7.0 * st, vc_ww(hy), on);
    // (the jets, each its own, closing up as they rise: at the land the ring's a row of them)
    let jets = smoothstep(0.0, 34.0, hy) * (1.0 - smoothstep(60.0, 240.0, hy));
    if (jets > 0.0) {
        let sc = 0.5 + 0.5 * cos(13.0 * ang + 2.0 * sin(3.0 * ang + 0.7) + hy * 0.004);
        W = W * mix(1.0, 0.72 + 0.5 * sc * sc, jets);
    }
    // (the head bulging out of it while it climbs)
    let Rt = vs.Rt;
    let hd = (hy - (H - 0.75 * Rt)) / (0.6 * Rt);
    W = W + 0.17 * Rt * exp(-hd * hd) * smoothstep(350.0, 900.0, H);
    if (vs.c > 0.0) {
        // (what falls back spreads out at the foot)
        W = W + 150.0 * (1.0 - exp(-vs.c / 3.0)) * exp(-max(hy, 0.0) / 280.0);
    }
    let dA = abs(rho - Rr) - W;
    let dome = 0.55 * Rt * smoothstep(300.0, 900.0, H) * min(rho * rho / (Rt * Rt), 1.6);
    var top = hy - (min(H, vs.Hb + 60.0) - dome);
    if (vs.c > 0.0) {
        // (the top of what is left, rounded)
        top = max(top, hy - vs.Hb);
    }
    return vc_smax(dA, top, 34.0) * 0.82;
}
fn vc_smax(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * k * 0.25;
}
fn vc_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
// The ripple running out through the umbrella (Hunga Tonga's gravity waves): trains of waves leaving the head as it
// bobs, their height over the sheet.
fn vc_ripple(r: f32) -> f32 {
    let f = vs.t - 25.0;
    if (f <= 0.0) {
        return 0.0;
    }
    let R = 290.0 * f;                                       // the first wave's front
    let ph = (R - r) / 210.0;
    return 26.0 * sin(ph * TAU) * smoothstep(-0.2, 1.0, ph) * exp(-max(ph, 0.0) / 4.5) * smoothstep(300.0, 900.0, r);
}
// The umbrella: a flat sheet, thick over the head, thinning out to a rounded nose (a gravity current's).
fn vc_umb(q: vec3<f32>, r: f32) -> f32 {
    if (vs.Ru < 10.0) {
        return 1.0e5;
    }
    let hy = q.y;
    let e = saturate((vs.Ru - r) / 520.0);
    let prof = sqrt(e * (2.0 - e));
    let core = exp(-r * r / (1100.0 * 1100.0));
    // (a head of thicker cloud running along its nose, as a gravity current has)
    let nose = exp(-pow((vs.Ru - r - 330.0) / 300.0, 2.0));
    let th = (120.0 + 200.0 * core + 70.0 * nose) * prof;
    let hm = VC_HU + 2.2 * vc_ripple(r) + 30.0 * (1.0 - prof);
    let bot = hm - 0.9 * th - 210.0 * exp(-r * r / (700.0 * 700.0));
    let tp = hm + 0.9 * th + 120.0 * core;
    return max(max(hy - tp, bot - hy) * 0.8, (r - vs.Ru) * 0.8);
}
// The wall of ash and what it leaves: over the land (`land`), behind its front; .x the distance, .y how far behind the
// front (0 at it). Its front runs on in lobes along the land's lows, parted by clefts.
fn vc_n1(x: f32, per: u32, k: u32) -> f32 {
    let i = floor(x);
    let f = x - i;
    let u = f * f * (3.0 - 2.0 * f);
    let n = u32(i32(i)) % per;
    let a = f32(pcg(n ^ k) & 0xffffu) / 65535.0;
    let b = f32(pcg(((n + 1u) % per) ^ k) & 0xffffu) / 65535.0;
    return mix(a, b, u);
}
fn vc_lobes(ang: f32, rho: f32) -> f32 {
    // (long fingers running out from the ring, parted by narrow clefts: noise round the circle, wandering as it goes out)
    let u = (ang + 3.1415927 + 0.00022 * rho + 0.2 * sin(rho * 0.0031)) / TAU + 1.0;
    let n = 0.6 * vc_n1(u * 9.0, 9u, 0x71u) + 0.28 * vc_n1(u * 23.0, 23u, 0x72u) + 0.12 * vc_n1(u * 61.0, 61u, 0x73u);
    let cl = vc_n1(u * 17.0, 17u, 0x74u);
    return n - 0.5 - 0.3 * (1.0 - smoothstep(0.0, 0.16, abs(cl - 0.5)));
}
fn vc_flow(q: vec3<f32>, rho: f32, ang: f32, land: f32) -> vec2<f32> {
    let c = vs.c;
    if (c <= 0.0) {
        return vec2<f32>(1.0e5, -1.0e5);
    }
    let lob = vc_lobes(ang, rho);
    // (its lobes grow from nothing as it leaves the ring; high land holds it back)
    let e = vs.rf - rho - min(4.0 * (vs.rf - VC_RING) + 30.0, 520.0) * lob - 2.6 * max(land, 0.0);
    let h = q.y - land;
    let ep = max(e, 0.0);
    // (a steep nose, then a body thickening behind it)
    let nose = 225.0 * (1.0 - exp(-ep / 80.0)) * smoothstep(0.0, 2.0, c);
    var top = nose + 0.10 * min(ep, 700.0);
    // (the new clouds rising off it, once it has slowed and lost its load)
    let lift = smoothstep(VC_LIFT - 8.0, VC_RED, vs.t);
    let bot = smoothstep(280.0, 640.0, e) * (70.0 + 9.0 * max(vs.t - 50.0, 0.0)) * (0.8 + 0.5 * lob);
    if (lift > 0.0) {
        let tw = gnoise2(vec2<f32>(ang * 3.3, rho / 600.0));
        top = top + 980.0 * lift * smoothstep(120.0, 620.0, ep) * smoothstep(0.34, 0.74, tw + 0.5 * lob);
    }
    let d = max(max(h - top, bot - h) * 0.75, -e * 0.85);
    return vec2<f32>(d, e);
}

// What a stage of the march knows of a point: the distances, and how far along the ray nothing can stand.
struct VcB {
    d: f32,
    dc: f32,
    du: f32,
    df: f32,
    e: f32,
    land: f32,
    rho: f32,
    ang: f32,
}
fn vc_base(q: vec3<f32>) -> VcB {
    var b: VcB;
    let rho = length(q.xz);
    b.rho = rho;
    if (q.y < 480.0 || vs.c > 0.0) {
        b.ang = atan2(q.z, q.x);
    }
    b.dc = vc_col(q, rho, b.ang);
    b.du = vc_umb(q, rho);
    b.df = 1.0e5;
    b.e = -1.0e5;
    b.land = 0.0;
    if (vs.c > 0.0 && q.y < vs.ftop + VC_DM && rho < vs.rfm + VC_DM) {
        b.land = vc_land(q.xz);
        let f = vc_flow(q, rho, b.ang, b.land);
        b.df = f.x;
        b.e = f.y;
    }
    b.d = vc_smin(vc_smin(b.dc, b.du, 120.0), b.df, 60.0);
    return b;
}
// The base alone, for the light's looks along the way to the sun.
fn vc_dist(q: vec3<f32>) -> f32 {
    return vc_base(q).d;
}
// How far the ray may go from here with none of the smooth bodies nearer than the lumps can reach: the umbrella's sheet
// and the flows' layer are flat, so a ray at a low angle is carried straight to them, not crept up on.
fn vc_skip(q: vec3<f32>, rd: vec3<f32>, b: ptr<function, VcB>) -> f32 {
    let dm = VC_DM + 10.0;
    var s = (*b).dc - dm;
    // (the umbrella's layer)
    if (vs.Ru > 10.0) {
        let lo = VC_HU - 500.0 - dm;
        let hi = VC_HU + 480.0 + dm;
        var su = 1.0e6;
        if (q.y < lo) {
            su = select(1.0e6, (lo - q.y) / rd.y, rd.y > 1.0e-4);
        } else if (q.y > hi) {
            su = select(1.0e6, (q.y - hi) / -rd.y, rd.y < -1.0e-4);
        } else {
            su = (*b).du - dm;
        }
        s = min(s, su);
    }
    if (vs.c > 0.0) {
        let hi = vs.ftop + dm;
        var sf = 1.0e6;
        if (q.y > hi) {
            sf = select(1.0e6, (q.y - hi) / -rd.y, rd.y < -1.0e-4);
        } else {
            sf = max((*b).rho - vs.rfm - dm, (*b).df - dm);
        }
        s = min(s, sf);
    }
    return s;
}

// ---- the lumps: domes over a jittered lattice (as the Nuke's pl_dome), the lattice wrapped round `wrap` cells in x ----
fn vc_dome(p: vec3<f32>, wrap: i32) -> f32 {
    let b = floor(p - 0.5);
    var hmax = 0.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let o = vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let cell = b + o;
        var ic = vec3<i32>(cell);
        if (wrap > 0) {
            ic.x = ((ic.x % wrap) + wrap) % wrap;
        }
        let q = bitcast<vec3<u32>>(ic);
        let h = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x51u)));
        let jit = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) * (0.7 / 1023.0) + 0.15;
        let sz = 0.7 + 0.55 * f32(pcg(h) & 1023u) / 1023.0;
        let e = cell + jit - p;
        hmax = max(hmax, sz * sqrt(saturate(1.0 - dot(e, e) * 1.7 / (sz * sz))));
    }
    return hmax;
}
const VC_R1: mat3x3<f32> = mat3x3<f32>(-0.0014, 0.9977, -0.0674, -0.2224, -0.0660, -0.9727, -0.9750, 0.0136, 0.2220);
const VC_R2: mat3x3<f32> = mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971);
const VC_R3: mat3x3<f32> = mat3x3<f32>(-0.9891, -0.1223, 0.0816, 0.0968, -0.9594, -0.2651, 0.1107, -0.2543, 0.9608);

// The lumps on the column: rough convective cauliflower carried up it (falling back after the collapse), lumps on lumps.
// Low down the same lumps are drawn out up the jet and rush faster, as a flow narrowing must (`f` the height they are
// looked up at, stretching them). `d1` how far off the body is: the small lumps only looked up close to the surface.
// .x how far they stand out, .y how far up a dome, .z how soft its edge, .w the fray.
fn vc_softplus(x: f32, k: f32) -> f32 {
    return k * log(1.0 + exp(clamp(x / k, -20.0, 20.0)));
}
fn vc_lump_col(q: vec3<f32>, d1: f32, foot: f32, fine: bool) -> vec4<f32> {
    let hy = q.y;
    let f = 0.45 * hy + 0.55 * vc_softplus(hy - 300.0, 80.0);
    let qc = vec3<f32>(q.x, f - vs.up, q.z);
    let w = gnoise3(VC_R2 * qc * (1.0 / 330.0));
    let wq = qc + 80.0 * vec3<f32>(w - 0.5);
    // (held down low over the land, where the ring's wall is thinner than the lumps are deep: lumps cut as deep as that
    // leave it a thin skin the land shows through)
    let gain = (0.42 + 0.58 * smoothstep(60.0, 420.0, hy)) * (1.0 + 0.4 * smoothstep(500.0, 1400.0, hy));
    let b1 = vc_dome(VC_R1 * (wq * (1.0 / 240.0) + vec3<f32>(3.1, 0.0, 7.7)), 0);
    var v = (120.0 * (b1 - 0.52) + 50.0 * (w - 0.5)) * gain;
    var top = b1;
    var fray = 0.5;
    let rest = d1 - v;
    if (rest < 90.0) {
        let b2 = vc_dome(VC_R2 * (wq * (1.0 / 94.0) + vec3<f32>(0.0, 1.3, 5.1)), 0);
        v = v + 62.0 * (b2 - 0.52);
        top = b1 * (0.4 + 0.6 * b2);
        if (fine && rest < 46.0 && foot < 26.0) {
            let b3 = vc_dome(VC_R3 * (wq * (1.0 / 37.0) + vec3<f32>(1.7, 0.0, -2.1)), 0);
            v = v + 34.0 * (b3 - 0.52);
            top = top * (0.65 + 0.35 * b3);
            if (rest < 26.0 && foot < 10.0) {
                let b4 = vc_dome(VC_R1 * (wq * (1.0 / 15.0) + vec3<f32>(-4.7, 2.0, 0.3)), 0);
                v = v + 14.0 * (b4 - 0.52);
                fray = b4;
            }
        }
    }
    // (the steam before it all: no more than wisps)
    let on = smoothstep(0.0, 0.5, vs.a);
    return vec4<f32>(v * mix(0.13, 1.0, on), top, mix(8.0, 4.0, on), fray);
}
// On the umbrella: carried out with it (its big lumps spread as it spreads), settling smoother away from its head and
// its nose, its underside hanging in pouches.
fn vc_lump_umb(q: vec3<f32>, r: f32, d1: f32, foot: f32, fine: bool) -> vec4<f32> {
    let sc = pow(1300.0 / max(vs.Ru, 1300.0), 0.65);
    let qu0 = vec3<f32>(q.x * sc, q.y * 0.9, q.z * sc);
    let w = gnoise3(VC_R1 * qu0 * (1.0 / 520.0));
    let w2 = gnoise3(VC_R3 * qu0 * (1.0 / 170.0) + vec3<f32>(4.0));
    let qu = qu0 + vec3<f32>(260.0 * (w - 0.5) + 90.0 * (w2 - 0.5), 120.0 * (w2 - 0.5), 260.0 * (0.5 - w2) + 90.0 * (w - 0.5));
    let core = exp(-r * r / (1600.0 * 1600.0));
    let nose = exp(-max(vs.Ru - r, 0.0) / 620.0);
    let under = 1.0 - smoothstep(VC_HU - 180.0, VC_HU, q.y);
    let b1 = vc_dome(VC_R2 * (qu * (1.0 / 330.0) + vec3<f32>(1.3, 4.2, 0.2)), 0);
    var v = (34.0 + 76.0 * core + 90.0 * nose + 30.0 * under) * (b1 - 0.5) + (26.0 + 50.0 * core) * (w - 0.5) + 30.0 * (w2 - 0.5);
    var top = b1;
    let rest = d1 - v;
    if (rest < 70.0) {
        let b2 = vc_dome(VC_R3 * (qu * (1.0 / 120.0) + vec3<f32>(6.3, 0.2, 2.2)), 0);
        v = v + (30.0 + 30.0 * core + 30.0 * nose + 16.0 * under) * (b2 - 0.5);
        top = b1 * (0.5 + 0.5 * b2);
        if (fine && rest < 34.0 && foot < 36.0) {
            let b3 = vc_dome(VC_R1 * (qu * (1.0 / 44.0) + vec3<f32>(-3.3, 1.7, 8.1)), 0);
            v = v + 14.0 * (b3 - 0.5);
            top = top * (0.7 + 0.3 * b3);
        }
    }
    return vec4<f32>(v, top, 7.0, 0.5);
}
// On the wall of ash: looked up round the vent (bearing, distance out, height), the lattice wrapped round the circle, so
// the lumps travel out with the flow without smearing; they swell as it fans out.
fn vc_lump_flow(q: vec3<f32>, rho: f32, ang: f32, land: f32, d1: f32, foot: f32, fine: bool) -> vec4<f32> {
    let u = ang / TAU;
    let h = q.y - land;
    let qo = rho - 0.8 * (vs.rf - VC_RING);
    let rise = 14.0 * vs.c;
    let b1 = vc_dome(vec3<f32>(u * 28.0, qo / 125.0, (h - rise) / 105.0), 28);
    var v = 86.0 * (b1 - 0.5);
    var top = b1;
    var fray = 0.5;
    let rest = d1 - v;
    if (rest < 70.0) {
        let b2 = vc_dome(vec3<f32>(u * 71.0 + 3.1, qo / 50.0, (h - rise) / 44.0 + 4.7), 71);
        v = v + 36.0 * (b2 - 0.5);
        top = b1 * (0.5 + 0.5 * b2);
    }
    if (fine && rest < 34.0 && foot < 16.0) {
        let b3 = vc_dome(vec3<f32>(u * 173.0 - 1.9, qo / 20.0, (h - rise) / 18.0 + 2.3), 173);
        v = v + 15.0 * (b3 - 0.5);
        top = top * (0.7 + 0.3 * b3);
        if (foot < 5.0) {
            fray = gnoise3(vec3<f32>(u * 420.0, qo / 8.0, (h - rise) / 8.0));
            v = v + 7.0 * (fray - 0.5);
        }
    }
    return vec4<f32>(v, top, 5.0, fray);
}
// The surface at q: the smooth bodies (b) bulged out by the lumps of whichever is nearest, faded across where they meet.
// .x the distance, .y how far up a dome, .z how soft its edge, .w the fray.
fn vc_sdf(q: vec3<f32>, b: ptr<function, VcB>, foot: f32, fine: bool) -> vec4<f32> {
    let dc = (*b).dc;
    let du = (*b).du;
    let df = (*b).df;
    // (how much of each: by which is nearest, a band wide)
    let wc = saturate(1.0 + (min(du, df) - dc) / 70.0);
    let wu = saturate(1.0 + (min(dc, df) - du) / 70.0);
    let wf = saturate(1.0 + (min(dc, du) - df) / 70.0);
    var sum = 0.0;
    var l = vec4<f32>(0.0);
    if (wc > 0.0) {
        l = l + vc_lump_col(q, (*b).d, foot, fine) * wc;
        sum = sum + wc;
    }
    if (wu > 0.0) {
        l = l + vc_lump_umb(q, (*b).rho, (*b).d, foot, fine) * wu;
        sum = sum + wu;
    }
    if (wf > 0.0) {
        l = l + vc_lump_flow(q, (*b).rho, (*b).ang, (*b).land, (*b).d, foot, fine) * wf;
        sum = sum + wf;
    }
    l = l / max(sum, 1.0e-3);
    // (the lumps' height capped smoothly, so nothing stands out past what the march allows)
    let bp = max(l.x, 0.0);
    let bump = l.x - bp + bp / sqrt(sqrt(1.0 + pow(bp / VC_DM, 4.0)));
    return vec4<f32>((*b).d - bump, l.y, l.z, l.w);
}

// ---- the light ----------------------------------------------------------------------------------------------------
// How much of the sun's light gets past the umbrella to q: where the way to the sun crosses its sheet.
fn vc_sun_t(q: vec3<f32>, L: vec3<f32>) -> f32 {
    if (vs.cov <= 0.0 || L.y < 0.01) {
        return 1.0;
    }
    let up = VC_HU - 120.0 - q.y;
    if (up < 0.0) {
        return 1.0;
    }
    let h = q.xz + L.xz * (up / L.y);
    let r = length(h);
    return 1.0 - vs.cov * (1.0 - smoothstep(vs.Ru - 700.0, vs.Ru - 100.0, r)) * smoothstep(0.0, 160.0, up);
}
// How much of the sky's light does: the share of the sky the sheet leaves open over q.
fn vc_sky_t(q: vec3<f32>) -> f32 {
    if (vs.cov <= 0.0) {
        return 1.0;
    }
    let d = max(VC_HU - q.y, 60.0);
    let r = length(q.xz);
    let l = max(vs.Ru - r, 0.0);
    return 1.0 - vs.cov * (1.0 - d / sqrt(d * d + l * l)) * 0.97;
}
// The picture's darkening over land or sky at q (level with it, `far` for sky): noon gone dark, what glows left glowing.
fn vc_dim(c: vec3<f32>, q: vec3<f32>, L: vec3<f32>, sun_up: f32) -> vec3<f32> {
    let st = mix(1.0, vc_sun_t(q, L), sun_up);
    let sk = vc_sky_t(q);
    let lit = (0.72 * st + 0.28) * (0.05 + 0.95 * pow(sk, 1.3));
    // (bright and saturated: fire, lava, torches; or simply bright, a lamp)
    let mx = max(c.r, max(c.g, c.b));
    let sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 1.0e-3);
    let glow = smoothstep(0.45, 0.95, mx) * (0.06 + 0.94 * sat);
    let k = mix(lit, 1.0, glow);
    // (and what light is left, browned by the ash in the air)
    let g = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return mix(c, vec3<f32>(g) * vec3<f32>(1.12, 0.92, 0.74), 0.9 * vs.cov * (1.0 - glow)) * k;
}

// ---- the lightning: a slot a tenth of a second or so, a few alive at once ---------------------------------------
struct VcFlash {
    p: vec3<f32>,      // where, from the vent
    k: f32,            // how bright now
    ring: f32,         // 1 in the umbrella's rings, 0 in the plume
    id: f32,
}
fn vc_flash(i: i32, seed: u32) -> VcFlash {
    var o: VcFlash;
    let t = vs.t;
    let dt = 0.13;
    let sl = floor(t / dt) - f32(i);
    let slot = u32(max(sl, 0.0));
    o.id = sl;
    let t0 = sl * dt;
    let age = t - t0;
    let h = mh(slot, seed, 0x901u);
    let on = smoothstep(VC_LIGHT - 2.0, VC_LIGHT + 8.0, t0) * (1.0 - smoothstep(VC_COLLAPSE + 10.0, VC_RED, t0));
    if (h > 0.62 * on + 0.03 * step(VC_LIGHT, t0) * on) {
        return o;
    }
    let th = TAU * mh(slot, seed, 0x902u);
    let ring = mh(slot, seed, 0x903u) < smoothstep(VC_DARK - 4.0, VC_DARK + 4.0, t0);
    if (ring) {
        // (out through the sheet in rings, running out with the ripple)
        let n = floor(mh(slot, seed, 0x904u) * 3.0);
        let R = (0.3 + 0.28 * n) * min(vs.Ru, 5200.0);
        o.p = vec3<f32>(cos(th) * R, VC_HU - 90.0, sin(th) * R);
        o.ring = 1.0;
    } else {
        let hy = 380.0 + 1100.0 * mh(slot, seed, 0x905u);
        let R = (vc_rr(hy) + vc_ww(hy)) * (0.75 + 0.2 * mh(slot, seed, 0x906u));
        o.p = vec3<f32>(cos(th) * R, min(hy, max(vs.Hb, 60.0)), sin(th) * R);
    }
    // (a stroke or two, dying fast)
    let dur = 0.12 + 0.2 * mh(slot, seed, 0x907u);
    let strk = exp(-age / (0.45 * dur)) + 0.6 * exp(-max(age - 0.08, 0.0) / (0.3 * dur)) * step(0.08, age);
    o.k = strk * (0.5 + 0.8 * mh(slot, seed, 0x908u)) * step(age, 0.65);
    return o;
}

// ---- the lava bombs: on ballistic arcs off the ring (volcano.rs's vc_bombs, each down where it meets the land) --------
struct VcBomb {
    p0: vec3<f32>,
    v: vec3<f32>,
    t0: f32,
    tl: f32,
}
fn vc_bomb(i: u32) -> VcBomb {
    let b = VC_BOMB + VC_BW * i;
    var o: VcBomb;
    o.t0 = vc_w(b);
    o.p0 = vec3<f32>(vc_w(b + 1u), vc_w(b + 2u), vc_w(b + 3u));
    o.v = vec3<f32>(vc_w(b + 4u), vc_w(b + 5u), vc_w(b + 6u));
    o.tl = vc_w(b + 7u);
    return o;
}
fn vc_bomb_at(b: VcBomb, t: f32) -> vec3<f32> {
    let s = t - b.t0;
    return b.p0 + b.v * s - vec3<f32>(0.0, 0.5 * VC_G * s * s, 0.0);
}
// Their smoke (half size): .rgb what it adds (premultiplied), .a what it leaves; `tm` how far off the nearest is.
fn vc_bombs_smoke(C: vec3<f32>, rd: vec3<f32>, tmax: f32, amb: vec3<f32>, tm: ptr<function, f32>) -> vec4<f32> {
    let n = u32(vc_w(1u));
    let time = vs.t;
    var c = vec3<f32>(0.0);
    var tr = 1.0;
    if (time < VC_ERUPT + 1.0 || time > VC_COLLAPSE + 12.0) {
        return vec4<f32>(c, tr);
    }
    for (var i = 0u; i < n; i = i + 1u) {
        let b = vc_bomb(i);
        if (b.t0 >= time) {
            break;
        }
        if (time > b.tl + 11.0) {
            continue;
        }
        let te = min(time, b.tl);
        let ts = max(b.t0, te - 7.0);
        let a = vc_bomb_at(b, ts) + C;
        let e = vc_bomb_at(b, te) + C;
        let T = te - ts;
        let sag = 0.125 * VC_G * T * T;
        let g = pl_ray_seg(rd, a, e, 0.0, 1.0);
        let wmax = 2.0 + 1.9 * sqrt(time - ts);
        if (g.x > sag + 2.0 * wmax + g.y * vs.px * 2.0) {
            continue;
        }
        var pa = a;
        for (var k = 1; k <= 6; k = k + 1) {
            let tk = ts + T * f32(k) / 6.0;
            let pb = vc_bomb_at(b, tk) + C;
            let sg = pl_ray_seg(rd, pa, pb, 0.0, 1.0);
            let tm0 = tk - T * (1.0 - sg.z) / 6.0;
            let age = time - tm0;
            let w0 = 1.6 + 1.7 * sqrt(age);
            let w = max(w0, sg.y * vs.px);
            if (sg.x < 2.0 * w && sg.y < tmax) {
                let lump = 0.55 + 0.9 * gnoise3(vec3<f32>(sg.z + f32(k), f32(i) * 1.7, age * 0.2) * vec3<f32>(3.0, 1.0, 1.0));
                let al = saturate(exp(-sg.x * sg.x / (w * w)) * (w0 / w) * exp(-age / 3.2) * 0.85 * lump) * smoothstep(40.0, 320.0, sg.y);
                let hot = exp(-age / 0.35);
                let sc = vec3<f32>(0.1, 0.09, 0.082) * (dot(amb, vec3<f32>(0.33)) + 0.2) + vec3<f32>(1.4, 0.4, 0.06) * hot;
                c = c + tr * al * sc;
                tr = tr * (1.0 - al);
                if (al > 0.04) {
                    *tm = min(*tm, sg.y);
                }
            }
            pa = pb;
        }
        // (its dust where it comes down)
        if (time > b.tl) {
            let age = time - b.tl;
            let P = vc_bomb_at(b, b.tl) + C;
            let R = 5.0 + 14.0 * (1.0 - exp(-age / 1.2));
            let tc = dot(P, rd);
            let dd = length(P - rd * tc);
            if (dd < R && tc < tmax + R) {
                let al = (1.0 - smoothstep(0.3 * R, R, dd)) * 0.75 * exp(-age / 3.5) * smoothstep(20.0, 120.0, tc);
                c = c + tr * al * vec3<f32>(0.12, 0.105, 0.095) * (dot(amb, vec3<f32>(0.33)) + 0.3);
                tr = tr * (1.0 - al);
            }
        }
    }
    return vec4<f32>(c, tr);
}
// Their glowing heads (sharp, at full size): what they add at this pixel.
fn vc_bombs_heads(C: vec3<f32>, rd: vec3<f32>, tmax: f32) -> vec3<f32> {
    let n = u32(vc_w(1u));
    let time = vs.t;
    var c = vec3<f32>(0.0);
    if (time < VC_ERUPT + 1.0 || time > VC_COLLAPSE + 2.0) {
        return c;
    }
    let focal = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
    for (var i = 0u; i < n; i = i + 1u) {
        let b = vc_bomb(i);
        if (b.t0 >= time) {
            break;
        }
        if (time > b.tl + 0.5) {
            continue;
        }
        let te = min(time, b.tl);
        let p = vc_bomb_at(b, te) + C;
        let t = dot(p, rd);
        if (t < 0.0 || t > tmax + 8.0) {
            continue;
        }
        let s = vc_bomb_at(b, te - 0.05) + C;
        let sg = pl_ray_seg(rd, s, p, 0.0, 1.0);
        let ppx = sg.x * focal / max(t, 1.0);
        let sz = (1.0 + 1.6 * mh(i, 3u, 0x31u)) * focal / max(t, 1.0);
        let rpx = clamp(sz, 0.9, 7.0);
        if (ppx > 14.0 * rpx + 4.0) {
            continue;
        }
        let cool = saturate((time - b.t0) / 12.0);
        let hc = mix(vec3<f32>(3.2, 1.6, 0.4), vec3<f32>(2.0, 0.46, 0.08), cool);
        let core = saturate(rpx + 0.6 - ppx) * min(sz / rpx, 1.0) + 0.0;
        let glow = 0.08 / (1.0 + pow(ppx / (rpx * 3.0), 2.0));
        var land = 1.0;
        if (time > b.tl) {
            land = 2.0 * (1.0 - (time - b.tl) / 0.5);
        }
        c = c + hc * (core * 1.6 + glow) * land;
    }
    return c;
}

// ---- the bolts themselves: what of a flash is seen as lightning, sharp, at full size ------------------------------
fn vc_bolts(C: vec3<f32>, seed: u32, cloud_t: f32, pxy: vec2<f32>) -> f32 {
    var sum = 0.0;
    let res = frame.resolution.xy;
    for (var i = 0; i < 3; i = i + 1) {
        let f = vc_flash(i, seed);
        if (f.k < 0.03) {
            continue;
        }
        let sid = u32(f.id);
        let th = TAU * mh(sid, seed, 0x911u);
        // (in the plume out of its side, down and across; in the sheet running along it, forking)
        var dv = vec3<f32>(cos(th) * 260.0, -180.0 - 240.0 * mh(sid, seed, 0x912u), sin(th) * 260.0);
        if (f.ring > 0.5) {
            dv = vec3<f32>(cos(th) * 620.0, -40.0 - 50.0 * mh(sid, seed, 0x912u), sin(th) * 620.0);
        }
        let a = project_rel(f.p + C);
        let b = project_rel(f.p + dv + C);
        if (a.z < 0.0 || b.z < 0.0) {
            continue;
        }
        let pa = a.xy * res;
        let pb = b.xy * res;
        let ab = pb - pa;
        // (a chain of short strokes, kinked hard where they join, not one smooth wander; a branch off its middle)
        let span = length(ab);
        let nrm = vec2<f32>(-ab.y, ab.x) / max(span, 1.0);
        if (dot(pxy - (pa + pb) * 0.5, pxy - (pa + pb) * 0.5) < span * span) {
            var p0 = pa;
            for (var j = 1u; j <= 5u; j = j + 1u) {
                let u = f32(j) / 5.0;
                let kink = select((mh(sid + j, seed, 0x915u) - 0.5) * 0.34 * span, 0.0, j == 5u);
                let p1 = pa + ab * u + nrm * kink;
                let sg = bolt_line(pxy, p0, p1, f32((sid + j) % 89u), f32(sid % 13u), 1.25);
                sum = sum + (sg.x * 2.2 + sg.y * 0.25) * f.k * (1.0 - 0.5 * u);
                if (j == 2u) {
                    let pd = p1 + (ab * 0.34 + nrm * span * (mh(sid, seed, 0x914u) - 0.5) * 0.9);
                    let s2 = bolt_line(pxy, p1, pd, f32(sid % 97u) + 3.0, f32(sid % 17u), 0.8);
                    sum = sum + (s2.x * 1.2 + s2.y * 0.12) * f.k * 0.7;
                }
                p0 = p1;
            }
        }
    }
    return sum;
}

// ---- what hangs in the air round the eye: flakes of ash coming down, embers driven past (as the Hurricane's rain: strung
// along lines the way they move, the lines' feet on a grid across it, layers out from the eye on coarser grids) --------
fn vc_specks(rd: vec3<f32>, cq: vec3<f32>, vel: vec3<f32>, near: f32, time: f32, thin: f32, wpx0: f32) -> f32 {
    let spd = length(vel);
    let w = vel / max(spd, 1.0e-3);
    let e1 = normalize(cross(w, select(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 0.0), abs(w.x) < 0.9)));
    let e2 = cross(w, e1);
    let c2 = vec2<f32>(dot(cq, e1), dot(cq, e2));
    let r2 = vec2<f32>(dot(rd, e1), dot(rd, e2));
    let rr = dot(r2, r2);
    let rw = dot(rd, w);
    let aw0 = dot(cq, w);
    let focal = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
    var sum = 0.0;
    for (var k = 0; k < 3; k = k + 1) {
        let fk = f32(k);
        let cell = 1.1 * pow(2.2, fk);
        let ta = 2.0 * pow(2.2, fk);
        let tb = min(ta * 2.2, near);
        if (ta >= tb) {
            break;
        }
        let pa = c2 + r2 * ta;
        let pb = c2 + r2 * tb;
        var last = vec2<f32>(1.0e9);
        for (var n = 0; n < 4; n = n + 1) {
            let g = floor(mix(pa, pb, (f32(n) + 0.5) / 4.0) / cell);
            if (all(g == last)) {
                continue;
            }
            last = g;
            let hb = pcg(bitcast<u32>(i32(g.x)) * 0x9E3779B1u ^ pcg(bitcast<u32>(i32(g.y)) * 0x85EBCA6Bu ^ u32(k) * 0x27D4EB2Fu));
            if (f32(hb & 0xFFFFu) / 65535.0 > thin) {
                continue;
            }
            let hc = pcg(hb);
            let p = (g + vec2<f32>(0.15) + 0.7 * vec2<f32>(f32(hc & 0xFFFFu), f32(hc >> 16u)) / 65535.0) * cell;
            let ts = clamp(select(0.5 * (ta + tb), dot(p - c2, r2) / rr, rr > 1.0e-6), ta, tb);
            let d = length(c2 + r2 * ts - p);
            let px = d * focal / ts;
            let wpx = wpx0 / (1.0 + 0.4 * fk);
            if (px > 3.0 * wpx) {
                continue;
            }
            let hd = pcg(hc ^ 0x51u);
            let period = cell * (2.5 + 3.5 * f32(hd & 255u) / 255.0);
            let len = cell * 0.09;
            let x0 = (aw0 + rw * ts - spd * time) / period + f32(hd >> 24u) / 255.0;
            let fx = fract(x0) / (len / period);
            let on = step(fx, 1.0) * (0.15 + 0.85 * fx * fx);
            sum = sum + on * exp(-px * px / (wpx * wpx)) * (0.3 + 0.9 * f32(hc & 255u) / 255.0);
        }
    }
    return sum;
}

// ---- the march ----------------------------------------------------------------------------------------------------
struct VcMarch {
    c: vec3<f32>,      // premultiplied colour
    tr: f32,           // transmittance
    t: f32,            // how far off, where it is most of it (1e9: none)
}
struct VcLight {
    L: vec3<f32>,
    sunc: vec3<f32>,
    skyl: vec3<f32>,
    amb: vec3<f32>,
    haze: vec3<f32>,
    day: f32,
    warm: f32,
    sun_up: f32,
    seed: u32,
    night: f32,
}
fn vc_march(C: vec3<f32>, rd: vec3<f32>, tmax: f32, j: f32, l: VcLight) -> VcMarch {
    var o: VcMarch;
    o.c = vec3<f32>(0.0);
    o.tr = 1.0;
    o.t = 1.0e9;
    let t_end = min(tmax, 32000.0);
    let time = vs.t;
    if (time < VC_ERUPT + 0.9) {
        return o;
    }
    var t = 0.0;
    var nl = 0;
    var tsun = 1.0;
    var ao = 1.0;
    var rim = 0.0;
    var wmid = 0.0;
    var tmid = 0.0;
    let gl0 = vc_flash(0, l.seed);
    let gl1 = vc_flash(1, l.seed);
    let gl2 = vc_flash(2, l.seed);
    let ph = 0.75 + (0.45 + 1.3 * l.warm) * pow(saturate(dot(rd, l.L)), 5.0);
    for (var i = 0; i < 96; i = i + 1) {
        if (t > t_end || o.tr < 0.03) {
            break;
        }
        let p = rd * t;
        let q = p - C;
        var b = vc_base(q);
        let foot = t * vs.px * 2.0;
        if (b.d > VC_DM + 12.0) {
            let s = vc_skip(q, rd, &b);
            if (s > 20.0) {
                t = t + s * 0.97;
                // (going away from everything: nothing more on this ray)
                if (s > 1.0e5) {
                    break;
                }
                continue;
            }
            t = t + max((b.d - VC_DM) * 0.6, 8.0);
            continue;
        }
        let st = max(4.0, t * 0.005) * (0.75 + 0.5 * j) * (1.0 + 3.0 * vs.thin);
        // (going out to the thin end of it)
        var thin = 1.0;
        if (vs.thin > 0.0) {
            // (each place at its own time, a second or two either way)
            let g = gnoise3((q + vec3<f32>(0.0, 0.0, time * 6.0)) * (1.0 / 900.0));
            thin = exp(-0.75 * max(time - (VC_RED - 2.8) + 4.0 * (g - 0.5), 0.0));
            thin = thin * (1.0 - smoothstep(VC_LEN - 2.0, VC_LEN - 0.6, time));
        }
        var den = 0.0;
        var sd = vec4<f32>(b.d, 0.5, 8.0, 0.5);
        if (b.d < -VC_DM - 6.0) {
            den = 1.0;
        } else {
            sd = vc_sdf(q, &b, foot, true);
            let edge = sd.z + foot * 1.6 + 160.0 * vs.thin;
            den = saturate(-sd.x / edge);
        }
        // (the flows' body thinning behind the front, and the air under what has lifted clear)
        var ext = 0.42;
        if (b.df < 40.0) {
            ext = mix(0.42, 0.05, smoothstep(160.0, 520.0, b.e));
        }
        // (the steam: thin and white, before the eruption)
        let steam = (1.0 - smoothstep(0.0, 0.35, vs.a)) * step(b.dc, min(b.df, b.du));
        if (steam > 0.0) {
            ext = mix(ext, 0.016, steam);
        }
        den = den * thin;
        if (den > 1.0e-4) {
            if (nl == 0) {
                // (the light: its lump's face, then the bulk of the cloud on the way to the sun; and the sky's, shut out
                // from under it)
                // (in the sheet's shadow what light there is comes in low from the open sky round its edge: that side of
                // each lump is the lit one)
                let st0 = vc_sun_t(q, l.L);
                let Lr = normalize(vec3<f32>(q.x, -0.4 * b.rho, q.z));
                let Lf = select(l.L, Lr, st0 < 0.4);
                let fq = q + Lf * 16.0;
                var fb = vc_base(fq);
                let face = vc_sdf(fq, &fb, 40.0, false).x - sd.x;
                let fc = saturate(0.36 + face / 34.0);
                let s2 = saturate((14.0 - vc_dist(q + l.L * 110.0)) / 80.0);
                let s3 = saturate((10.0 - vc_dist(q + l.L * 330.0)) / 180.0);
                let bulk = exp(-(s2 * 4.6 + s3 * 5.0));
                tsun = fc * bulk * st0 * (1.0 - saturate(-b.d / 60.0)) * (1.0 - 0.5 * l.warm);
                rim = select(0.0, fc * fc, st0 < 0.4) * (1.0 - saturate(-b.d / 60.0));
                let occ = saturate((10.0 - vc_dist(q + vec3<f32>(0.0, 150.0, 0.0))) / 130.0);
                let deep = saturate(-b.d / 110.0);
                let wu0 = saturate(1.0 + (min(b.dc, b.df) - b.du) / 70.0);
                ao = mix(0.4 + 0.6 * sd.y * sd.y, 0.7 + 0.3 * sd.y, wu0) * (1.0 - 0.75 * occ) * (1.0 - 0.6 * deep);
            }
            nl = nl + 1;
            // ---- its colour: charcoal and umber, a little paler on the umbrella's top and on the flows' ash ---------
            let hy = q.y;
            let wc = saturate(1.0 + (min(b.du, b.df) - b.dc) / 70.0);
            let wf = saturate(1.0 + (min(b.dc, b.du) - b.df) / 70.0);
            let wu = saturate(1.0 + (min(b.dc, b.df) - b.du) / 70.0);
            let mott = gnoise3(q * (1.0 / 410.0) + vec3<f32>(3.0, -0.2 * vs.up / 410.0, 1.0));
            var alb = mix(vec3<f32>(0.05, 0.046, 0.044), vec3<f32>(0.165, 0.145, 0.13), smoothstep(0.3, 0.72, mott));
            alb = mix(alb, alb * 0.5, (1.0 - smoothstep(100.0, 480.0, hy)) * wc);
            // (the sheet's sunlit top pale, as ash spread thin; its underside as dark as the column)
            alb = mix(alb, mix(vec3<f32>(0.1, 0.09, 0.083), vec3<f32>(0.31, 0.285, 0.26), smoothstep(VC_HU - 40.0, VC_HU + 160.0, hy)) * (0.75 + 0.5 * mott), wu);
            alb = mix(alb, vec3<f32>(0.1, 0.09, 0.083) * (0.8 + 0.4 * mott), wf);
            alb = mix(alb, vec3<f32>(0.75, 0.74, 0.72), steam);
            let sk = vc_sky_t(q);
            let sk_l = dot(l.skyl, vec3<f32>(0.2126, 0.7152, 0.0722));
            // (the sky's light, and under the sheet the brown light that gets in round its edge)
            let skyg = mix(mix(l.skyl, vec3<f32>(sk_l), 0.75), vec3<f32>(sk_l) * vec3<f32>(1.0, 0.72, 0.52), vs.cov);
            var c = alb * (skyg * (0.1 + 0.6 * ao) * (0.05 + 0.95 * sk) + l.sunc * (1.25 * tsun * ph) + vec3<f32>(0.9, 0.55, 0.32) * sk_l * rim * vs.cov * 1.3 * (1.0 - saturate(-b.d / 30.0)) * saturate(0.25 + 1.2 * b.rho / vs.Ru));
            // ---- fire: the vents' glow on all that hangs over them, the falling mass and the flows' dull red low down --
            // (over the land under it: the ring may lie well above or below the vent's own ground)
            let hyl = hy - select(0.0, vc_land(q.xz), hy < 600.0);
            let dr = length(vec2<f32>(b.rho - VC_RING, hyl));
            let flick = 0.72 + 0.28 * sin(b.ang * 5.0 + time * 1.7) * sin(b.ang * 11.0 - time * 2.3);
            let vent = smoothstep(0.0, 0.5, vs.a) * (1.0 - smoothstep(VC_COLLAPSE, VC_COLLAPSE + 2.5, time));
            let crease = (1.0 - sd.y) * (1.0 - sd.y);
            // (from under: what hangs over the ring lit from below, dying out within a hundred or two blocks)
            let under = exp(-dr / 34.0) * 0.8 + 0.012 * exp(-dr / 105.0);
            var fire = vec3<f32>(1.0, 0.22, 0.035) * under * flick * vent * (0.3 + 0.7 * crease);
            // (the jet's foot itself: white-hot in its creases, right down at the land)
            let hot = exp(-max(hyl, 0.0) / 24.0) * wc * (1.0 - steam) * vent;
            fire = fire + mix(vec3<f32>(1.2, 0.22, 0.025), vec3<f32>(2.6, 1.2, 0.26), exp(-max(hyl, 0.0) / 8.0)) * hot * crease * 1.7;
            if (b.e > -60.0) {
                // (the flows, close behind the front and low down: the hot base of the cloud showing in its creases)
                let h = hy - b.land;
                let ember = exp(-max(h, 0.0) / 18.0) * (1.0 - smoothstep(380.0, 1000.0, b.rho)) * exp(-max(b.e, 0.0) / 130.0) * smoothstep(40.0, 200.0, t);
                fire = fire + vec3<f32>(1.0, 0.2, 0.03) * ember * crease * 1.1 * wf;
            }
            // (the sheet's underside: the fire's dull red on it round the column, its pouches catching it)
            if (wu > 0.0 && hy < VC_HU) {
                let gl = exp(-b.rho / 1000.0) * (0.35 + 0.65 * sd.y * sd.y) * (1.0 - smoothstep(VC_COLLAPSE + 2.0, VC_LIFT, time));
                fire = fire + vec3<f32>(0.34, 0.075, 0.016) * gl * smoothstep(0.0, 4.0, vs.a) * wu;
            }
            c = c + fire;
            // (as it thins, the light through it red)
            if (vs.thin > 0.0) {
                c = mix(c, vec3<f32>(0.3, 0.1, 0.05) * l.sun_up + c * 0.5, vs.thin);
            }
            // (the lightning in it)
            var lg = 0.0;
            if (gl0.k > 0.0) {
                let v = q - gl0.p;
                lg = lg + gl0.k / (1.0 + dot(v, v) / (150.0 * 150.0));
            }
            if (gl1.k > 0.0) {
                let v = q - gl1.p;
                lg = lg + gl1.k / (1.0 + dot(v, v) / (150.0 * 150.0));
            }
            if (gl2.k > 0.0) {
                let v = q - gl2.p;
                lg = lg + gl2.k / (1.0 + dot(v, v) / (150.0 * 150.0));
            }
            c = c + (alb + 0.02) * vec3<f32>(0.75, 0.72, 1.0) * lg * 2.2;
            let al = 1.0 - exp(-den * ext * st);
            o.c = o.c + o.tr * al * c;
            tmid = tmid + o.tr * al * t;
            wmid = wmid + o.tr * al;
            o.tr = o.tr * (1.0 - al);
        }
        t = t + select(st, max(0.65 * sd.x, st * (0.5 + 0.03 * f32(i))), sd.x > 0.0);
    }
    if (o.tr < 0.999) {
        let dist = tmid / max(wmid, 1.0e-4);
        if (o.tr < 0.6) {
            o.t = dist;
        }
        // (the air's haze over it)
        let ap = 1.0 - exp(-dist / 9000.0);
        o.c = mix(o.c, l.haze * (1.0 - o.tr), ap * 0.7);
    }
    return o;
}

// ---- the jolt on the picture (as the Nuke's pl_jolt): the tremor building, the eruption's front, the wall arriving -
fn vc_jolt(in: StageIn) -> StageIn {
    vc_px = in.position.xy;
    let t = now();
    let tgt = vec3<f32>(anchor_xz().x, block_y() + 1.0, anchor_xz().y);
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z);
    let dist = length(me - tgt);
    let g = clamp(1.7 / (1.0 + dist / 700.0), 0.2, 1.0);
    // (the tremor, building from the hit, faster and harder up to the eruption)
    let tr = smoothstep(VC_HIT, VC_ERUPT, t) * (1.0 - smoothstep(VC_ERUPT + 2.0, VC_ERUPT + 7.0, t + dist / VC_V));
    var amp = 0.0024 * g * tr * tr;
    let s = t - VC_ERUPT - dist / VC_V;
    if (s > 0.0 && s < 8.0) {
        amp = amp + 0.012 * g * exp(-s / 0.5) + 0.004 * g * exp(-s / 2.8);
    }
    if (amp <= 1.0e-5 || intensity_v() <= 0.0) {
        return in;
    }
    let sh = vec2<f32>(
        0.55 * sin(t * 37.0 + 0.3) + 0.3 * sin(t * 59.0 + 1.9) + 0.15 * sin(t * 83.0),
        0.55 * cos(t * 33.0 + 2.2) + 0.3 * sin(t * 61.0 + 0.7) + 0.15 * cos(t * 79.0)
    );
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    let zoom = 1.0 + 2.2 * amp;
    let q = (in.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom + sh * amp;
    var o = in;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}

// What a stage of the pass gives: the picture (the whole pass and the join), or the half-size stage's (premultiplied
// colour and transmittance) and beside it how far its ray went and the cloud's distance (`fs_half`).
struct VcOut {
    c: vec4<f32>,
    e: vec4<f32>,
}
// The pass, in one of three stages: 0 the whole of it (fs_main); 1 the half-size stage (the cloud, over a two by two of
// the picture's pixels, marched to alternately the nearest and the farthest of their depths); 2 the join (the rest,
// sharp, at full size, `up` the half-size stage's colour and transmittance, `up_t` its cloud's distance).
fn volcano(in: StageIn, stage: u32, up: vec4<f32>, up_t: f32) -> VcOut {
    var uv = in.uv;
    let time = now();
    vc_set_state(time);
    vm_set(time);
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let anc = anchor_xz();
    let C = vec3<f32>(anc.x, block_y() + 1.0, anc.y) - cam;
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));

    var d = 0.0;
    if (stage == 1u) {
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
    var sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    var scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    var hc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let fade = 1.0 - smoothstep(VC_LEN - 1.0, VC_LEN, time);

    // (the light, matched to the scene's)
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
    let sunc = mix(vec3<f32>(1.35, 1.24, 1.06), mix(vec3<f32>(1.5, 0.68, 0.3), vec3<f32>(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun.y)), warm) * sun_up + vec3<f32>(0.07, 0.09, 0.14) * moon;
    let sky_e = vc_sky_t(-C);
    let haze_c = mix(mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day), vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))) * vec3<f32>(0.5, 0.3, 0.18) * day, vs.cov * (1.0 - sky_e)) * (0.1 + 0.9 * sky_e);
    var l: VcLight;
    l.L = L;
    l.sunc = sunc;
    l.skyl = max(skyl, vec3<f32>(0.03, 0.035, 0.05));
    l.haze = haze_c;
    l.day = day;
    l.warm = warm;
    l.sun_up = sun_up;
    l.seed = seed;
    // ---- the mount, drawn over the land until the burst (volcano_mount.wgsl) ---------------------------------------
    let vmh = vm_surface(C, rd, scene_len, col, stage, l, uv, sky);
    col = vmh.c;
    if (vmh.t >= 0.0) {
        scene_len = vmh.t;
        sky = false;
    }

    // ---- the land and the sky, under it ---------------------------------------------------------------------------
    if (stage != 1u && !sky) {
        let qg = rel - C;
        col = vc_dim(col, qg, L, sun_up);
        // (the cracks, the ring's glow on the land)
        let rg = length(qg.xz);
        let vent = smoothstep(VC_CRACK, VC_ERUPT, time);
        if (time > VC_ERUPT + 0.9 && abs(qg.y) < 200.0) {
            let dr = abs(rg - VC_RING);
            let ang = atan2(qg.z, qg.x);
            let wob = 14.0 * sin(ang * 7.0 + 1.0) + 9.0 * sin(ang * 19.0 + 3.0) + 6.0 * sin(ang * 43.0 + 0.5);
            let cr = abs(rg + wob - VC_RING);
            let w = 0.6 + 5.0 * vent * vent + 6.0 * smoothstep(VC_ERUPT, VC_ERUPT + 2.0, time);
            let line = 1.0 - smoothstep(w * 0.4, w * 1.4, cr);
            let glow2 = exp(-cr / (10.0 + 40.0 * vent));
            let lava = vec3<f32>(3.0, 0.8, 0.12);
            col = col + lava * line * 2.2 * (1.0 - smoothstep(VC_COLLAPSE, VC_COLLAPSE + 3.0, time)) * k;
            col = col + scene * vec3<f32>(1.5, 0.4, 0.08) * glow2 * vent * (1.0 - smoothstep(VC_COLLAPSE, VC_LIFT, time)) * k;
            let lit = smoothstep(VC_ERUPT, VC_ERUPT + 1.0, time) * (1.0 - 0.7 * smoothstep(VC_COLLAPSE, VC_LIFT, time));
            col = col + scene * vec3<f32>(1.5, 0.42, 0.1) * (0.5 * exp(-dr / 170.0)) * lit * k;
        }
    }
    if (stage != 1u && sky) {
        // (what sky is left, in along the horizon under the sheet: dirty with ash, dimmed)
        let cv = (vs.cov * 0.3 + 0.7 * smoothstep(0.0, 8.0, time - 23.0)) * smoothstep(VC_DARK - 6.0, VC_DARK + 8.0, time) * (1.0 - smoothstep(77.5, VC_LEN - 0.2, time));
        let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
        // (its light dirty and red low down, gone by a few degrees up under the sheet's edge)
        let e = saturate(rd.y * 5.0);
        col = mix(col, vec3<f32>(lum) * mix(vec3<f32>(0.62, 0.27, 0.11), vec3<f32>(0.22, 0.075, 0.04), e), cv);
    }
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    }
    // ---- the cloud ------------------------------------------------------------------------------------------------
    var cloud_t = up_t;
    if (stage != 2u) {
        let j = mix(ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0)), 0.5, smoothstep(0.0, 0.1, vs.thin));
        let m = vc_march(C, rd, scene_len, j, l);
        cloud_t = m.t;
        // (the bombs' smoke, in front of the cloud or behind it)
        var tb = 1.0e9;
        let sm = vc_bombs_smoke(C, rd, min(scene_len, 9000.0), l.skyl * vc_sky_t(-C), &tb);
        var ac = m.c + sm.rgb * m.tr;
        if (tb < cloud_t) {
            ac = sm.rgb + m.c * sm.a;
        }
        let at0 = m.tr * sm.a;
        cloud_t = min(cloud_t, tb);
        // (the mount's steam and dust, in front of it all)
        let va = vm_air(C, rd, min(scene_len, 9000.0), j, l);
        ac = va.rgb + ac * va.a;
        let at = at0 * va.a;
        if (stage == 0u) {
            col = col * at + ac;
        } else {
            hc = vec4<f32>(ac, at);
        }
    }
    if (stage == 1u) {
        return VcOut(hc, vec4<f32>(min(scene_len, 6.0e4), min(cloud_t, 1.0e6), 0.0, 0.0));
    }
    // ---- the needle beam: a hairline down out of the sky, a spark where it touches --------------------------------
    if (time < VC_HIT + 0.3) {
        let cut = 1.0 - smoothstep(VC_HIT, VC_HIT + 0.06, time);
        let g = vc_land(vec2<f32>(0.0));
        let a = C + vec3<f32>(0.0, g, 0.0);
        let sg = pl_ray_seg(rd, a, a + vec3<f32>(0.0, 30000.0, 0.0), 0.0, 1.0);
        let w = max(sg.y * vs.px * 1.1, 0.05);
        if (sg.y < scene_len + 4.0) {
            let line = exp(-pow(sg.x / w, 2.0)) * smoothstep(0.0, 0.5, time) * cut;
            col = col + vec3<f32>(2.4, 1.3, 0.8) * line * 1.8 * k;
        }
    }
    // ---- the eruption: a hard ring of light round the land, the pressure ring out from it at the speed of sound ------
    let tr_here = select(1.0, up.a, stage == 2u);
    if (vs.a > -0.02 && vs.a < 7.0) {
        let Rs = VC_V * vs.a + VC_RING;
        let P = C + vec3<f32>(0.0, 8.0, 0.0);
        let bq = dot(rd, P);
        let disc = bq * bq - (dot(P, P) - Rs * Rs);
        if (disc > 0.0 && vs.a > 0.0) {
            let sq = sqrt(disc);
            var th = bq - sq;
            if (th < 0.0) {
                th = bq + sq;
            }
            let hp = rd * th;
            if (th > 0.0 && th < scene_len + 4.0 && hp.y > C.y - 4.0) {
                let edge = exp(-sq / (0.05 * Rs + 8.0));
                let sf = 1.0 - smoothstep(3.0, 7.0, vs.a);
                let pb = project_rel(P);
                var dirs = uv - pb.xy;
                if (pb.z < 0.0) {
                    dirs = -dirs;
                }
                let off = normalize(dirs + vec2<f32>(1.0e-5)) * (0.009 * edge + 0.002 * exp(-sq / (0.25 * Rs))) * sf;
                let sc = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv - off, 0.0).rgb);
                col = col + (sc - scene) * saturate(edge * 4.0 + 0.5) * sf * tr_here;
                col = col + vec3<f32>(1.0, 0.86, 0.72) * 0.16 * edge * exp(-vs.a / 1.4) * sf * tr_here;
            }
        }
        // (the flash: a blaze along the horizon where the ring opens, out over the land)
        let P2 = C + vec3<f32>(0.0, 60.0, 0.0);
        let tP = dot(P2, rd);
        let hp2 = rd * max(tP, 0.0) - C;
        let dr2 = length(vec2<f32>(length(hp2.xz) - VC_RING, hp2.y - 30.0));
        let fl = 5.0 * exp(-max(vs.a, 0.0) / 0.12) + 0.9 * exp(-max(vs.a, 0.0) / 1.1);
        col = col + vec3<f32>(3.0, 1.2, 0.3) * fl * (0.07 / (1.0 + pow(dr2 / 120.0, 2.0)) + 0.01) * smoothstep(-0.02, 0.02, vs.a) * k;
    }
    // ---- the air once the wall has gone over: thick with ash, the light gone brown, a red glow low towards the vent ---
    let eq = -C;
    var eye_e = -1.0e5;
    if (vs.c > 0.0) {
        let re = length(eq.xz);
        let fe = vc_flow(eq, re, atan2(eq.z, eq.x), vc_land(eq.xz));
        eye_e = fe.y;
        let over = max(eq.y - vc_land(eq.xz), 0.0);
        if (eye_e > 0.0 && over < 400.0) {
            let V = 16.0 * exp(eye_e / 165.0) * (1.0 + 30.0 * smoothstep(VC_RED - 5.0, VC_LEN - 2.0, time));
            let L = min(min(scene_len, cloud_t), 6000.0);
            let toV = normalize(C + vec3<f32>(0.0, 40.0, 0.0));
            let vg = pow(saturate(dot(rd, toV)), 6.0) * (1.0 - smoothstep(VC_LIFT, VC_RED, time));
            let fogc = (vec3<f32>(0.03, 0.021, 0.016) * (0.3 + day) + vec3<f32>(0.24, 0.05, 0.012) * vg * saturate(eye_e / 500.0));
            col = mix(col, fogc, (1.0 - exp(-L / V)) * smoothstep(0.0, 30.0, eye_e));
        }
    }
    // ---- flakes of ash coming down, embers driven past ---------------------------------------------------------------
    if (time > VC_COLLAPSE && eye_e > -700.0) {
        let wall = smoothstep(-40.0, 40.0, eye_e);
        let dirv = normalize(vec3<f32>(eq.x, 0.0, eq.z) + vec3<f32>(1.0e-3));
        if (wall > 0.0) {
            let eb = vc_specks(rd, cam * 0.0 + vec3<f32>(0.0, -time * 3.0, 0.0), dirv * 22.0 + vec3<f32>(0.0, 6.0, 0.0), min(scene_len, 40.0), time, 0.32, 1.3);
            let ek = wall * (1.0 - smoothstep(VC_LIFT - 2.0, VC_LIFT + 4.0, time));
            col = col + vec3<f32>(2.4, 0.7, 0.12) * eb * ek * k;
        }
        let ash = wall * (1.0 - smoothstep(VC_RED + 2.0, VC_LEN - 0.5, time)) * smoothstep(VC_COLLAPSE, VC_COLLAPSE + 8.0, time);
        if (ash > 0.0) {
            let af = vc_specks(rd, cam, vec3<f32>(1.6, -4.5, 0.9), min(scene_len, 60.0), time, 0.42, 1.0);
            col = mix(col, vec3<f32>(0.28, 0.25, 0.23) * (0.2 + 0.8 * day), saturate(af) * ash * 0.8);
        }
    }
    // ---- the bombs' heads, the bolts ----------------------------------------------------------------------------------
    if (time > VC_ERUPT + 1.0 && time < VC_COLLAPSE + 2.0) {
        col = col + vc_bombs_heads(C, rd, min(scene_len, cloud_t + 40.0)) * k;
    }
    if (time > VC_LIGHT - 2.0 && time < VC_RED) {
        let bl = vc_bolts(C, seed, cloud_t, vc_px);
        if (bl > 0.0) {
            col = col + vec3<f32>(0.82, 0.8, 1.0) * bl * 1.6 * k * (1.0 - 0.8 * smoothstep(VC_HU - 200.0, VC_HU + 100.0, -C.y));
        }
    }
    // ---- the blood-red sun, as the ash thins ------------------------------------------------------------------------
    if (sky && time > VC_RED - 8.0 && sun.y > -0.03) {
        let cth = saturate(dot(rd, sun));
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let show = smoothstep(VC_RED - 7.0, VC_RED, time) * (1.0 - smoothstep(VC_LEN - 3.0, VC_LEN - 0.3, time));
        let vis = 1.0 - exp(-7.0 * (tr_here + 0.05));
        let disc = 1.0 - smoothstep(0.052, 0.058, th);
        col = col + (vec3<f32>(1.15, 0.07, 0.02) * disc + vec3<f32>(0.42, 0.05, 0.02) * exp(-th / 0.22) + vec3<f32>(0.12, 0.03, 0.012) * exp(-th / 0.8)) * show * vis * sun_up;
    }
    col = vm_over(col, C, rd, scene_len, l);
    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    let out = mix(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb, srgb, fade);
    if (capture() > 2.5) {
        let sp = floor(vc_px);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = out.g * 0.5 + (out.r + out.b) * 0.25;
        let ycc_co = out.r - out.b;
        let ycc_cg = out.g - (out.r + out.b) * 0.5;
        return VcOut(vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0), vec4<f32>(0.0));
    }
    return VcOut(vec4<f32>(out, 1.0), vec4<f32>(0.0));
}
fn pl_ray_seg(rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>, lo: f32, hi: f32) -> vec3<f32> {
    let ab = b - a;
    let ab2 = max(dot(ab, ab), 1.0e-6);
    let bv = dot(rd, ab);
    let den = max(ab2 - bv * bv, 1.0e-6);
    let u = clamp((dot(rd, a) * bv - dot(a, ab)) / den, lo, hi);
    let c = a + ab * u;
    let t = dot(c, rd);
    return vec3<f32>(length(c - rd * t), t, u);
}

@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    let in = vc_jolt(in0);
    return volcano(in, 0u, vec4<f32>(0.0, 0.0, 0.0, 1.0), 1.0e9).c;
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): the cloud drawn at half the width and height by fs_half and laid
// over the full-size picture by fs_join; a game without the stage compiles these too and draws fs_main alone.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct VcHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> VcHalf {
    vc_px = in.position.xy;
    let o = volcano(in, 1u, vec4<f32>(0.0), 1.0e9);
    return VcHalf(o.c, o.e);
}
// The half-size stage's cloud at this pixel (whose ray goes `len` blocks): a joint bilateral upsample against the depth
// (as the Nuke's pl_up).
fn vc_up(pos: vec2<f32>, len: f32) -> VcOut {
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
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        let dz = abs(e.x - lp) / max(lp, 1.0);
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
        return VcOut(near_c, vec4<f32>(near_t, 0.0, 0.0, 0.0));
    }
    return VcOut(acc / sw, vec4<f32>(best_t, 0.0, 0.0, 0.0));
}
@fragment
fn fs_join(in0: StageIn) -> @location(0) vec4<f32> {
    let in = vc_jolt(in0);
    let d = depth_at(in.uv);
    let len0 = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let anc = anchor_xz();
    let len = vm_join_len(in.position.xy, len0, vec3<f32>(anc.x, block_y() + 1.0, anc.y) - frame.camera_position.xyz, normalize(world_offset(in.uv, 0.5)));
    let u = vc_up(in.position.xy, len);
    return volcano(in, 2u, u.c, u.e.x).c;
}
// [end half stage]
