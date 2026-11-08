// Orbital Laser's post pass for the Supervolcano (laser 14), built as the Nuke's: strike.wgsl up to its fs_main, then
// this file and volcano_mount.wgsl. Validate with tools/check-shader.sh.

// ---- laser 14: the supervolcano ----
// A satellite's beam melting a hole (`vc_opening`), the tremor, the mount rising round it, then one soft volume: a density falling off through a surface
// bulged by lumps on lumps (`vc_sdf`, sphere-traced only over empty air), lit by looks towards the light. The blast
// (`vc_col`), the shock (`vc_shells`, `vc_dust`), rock (`vc_spray`); fire in the trunk (`vc_heat`); bombs on ropes of
// smoke (`vc_bombs_smoke`); the umbrella over the sky, lightning in it (`vc_umb`, `vc_flash`, `vc_bolts`); noon gone dark
// (`vc_dim`). The column falls back (`VC_COLLAPSE`) into a wall of ash (`vc_flow`) that engulfs the player and lifts into
// a ceiling; then a dim world and a blood-red sun as the ash thins, gone by VC_LEN.
// strike/volcano.rs keeps its VC_* in step with these, and gives the table: the bombs, the land's height.
const VC_LEN: f32 = 88.0;
const VC_HIT: f32 = 2.0;           // the satellite's beam fires (the opening: vc_opening)
const VC_CRACK: f32 = 6.0;         // the ring cracks through
const VC_ERUPT: f32 = 18.0;        // the eruption
const VC_LIGHT: f32 = 26.0;        // the plume's lightning
const VC_DARK: f32 = 36.0;         // the umbrella out over the land
const VC_COLLAPSE: f32 = 50.0;     // the column falls back, the flows set off from the ring
const VC_LIFT: f32 = 66.0;         // the flows lift into new clouds
const VC_RED: f32 = 80.0;          // the ash thinning round a red sun
const VC_RING: f32 = 280.0;        // the ring of vents' radius
const VC_SPREAD: f32 = 28.0;       // the head reaches the ceiling and starts to spread
const VC_P: f32 = 6.0;             // how long the lumps are carried before they are let go
const VC_HU: f32 = 1500.0;         // the umbrella's middle over the land
const VC_V: f32 = 343.0;           // the pressure ring's speed (the sound's)
const VC_DM: f32 = 190.0;          // the most the lumps stand out of a smooth body
const VC_DUST: f32 = 8.0;          // the dust the shock lifts has settled
const VC_ST: f32 = 1.35;           // the march's stride
const VC_ST_AIR: f32 = 2.5;        // and through the air the wall has emptied
const VC_HOLD: f32 = 0.3;          // the big lumps kept for this share of the way off the surface
const VC_BOMB: u32 = 16u;          // the table: the bombs from here, VC_BW words each
const VC_BW: u32 = 8u;
const VC_G: f32 = 28.0;
const VC_HF: u32 = 1024u;          // the land's height (volcano.rs's vc_hf_pack)

// gnoise3 with one hash a corner.
fn vc_gc(hx: u32, hy: u32, hz: u32, f: vec3<f32>) -> f32 {
    let h = pcg(hx ^ hy ^ hz);
    let g = vec3<f32>(f32(h >> 21u), f32((h >> 10u) & 2047u), f32(h & 1023u)) * vec3<f32>(2.0 / 2047.0, 2.0 / 2047.0, 2.0 / 1023.0) - 1.0;
    return dot(g, f);
}
fn vc_gn3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = p - i;
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let c = bitcast<vec3<u32>>(vec3<i32>(i));
    let x0 = c.x * 73856093u;
    let x1 = x0 + 73856093u;
    let y0 = c.y * 19349663u;
    let y1 = y0 + 19349663u;
    let z0 = c.z * 83492791u;
    let z1 = z0 + 83492791u;
    let e = vec3<f32>(1.0, 0.0, 0.0);
    let n000 = vc_gc(x0, y0, z0, f);
    let n100 = vc_gc(x1, y0, z0, f - e.xyy);
    let n010 = vc_gc(x0, y1, z0, f - e.yxy);
    let n110 = vc_gc(x1, y1, z0, f - e.xxy);
    let n001 = vc_gc(x0, y0, z1, f - e.yyx);
    let n101 = vc_gc(x1, y0, z1, f - e.xyx);
    let n011 = vc_gc(x0, y1, z1, f - e.yxx);
    let n111 = vc_gc(x1, y1, z1, f - e.xxx);
    let a = mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y);
    let b = mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y);
    return mix(a, b, u.z) * 0.75 + 0.5;
}
fn vc_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
// The land at q (level, from the vent): its height over the vent's ground, smoothly between the heightfield's cells.
var<private> vc_hf_n: f32;
var<private> vc_hf_r: f32;
fn vc_land_set() {
    vc_hf_n = vc_w(VC_HF);
    vc_hf_r = vc_w(VC_HF + 1u);
    let n = u32(vc_hf_n + 0.5);
    if (vc_hf_n < 2.0 || arrayLength(&mod_data) < VC_HF + 8u + n * n) {
        vc_hf_n = 0.0;
    }
}
fn vc_land(q: vec2<f32>) -> f32 {
    let nf = vc_hf_n;
    if (nf < 2.0) {
        return 0.0;
    }
    let n = u32(nf + 0.5);
    let R = vc_hf_r;
    let step = 2.0 * R / (nf - 1.0);
    let fc = clamp((q + R) / step, vec2<f32>(0.0), vec2<f32>(nf - 1.001));
    let i0 = vec2<u32>(floor(fc));
    let t = fc - floor(fc);
    let base = VC_HF + 8u + i0.y * n + i0.x;
    let h = vec4<f32>(f32(mod_data[base] & 0xffffu), f32(mod_data[base + 1u] & 0xffffu), f32(mod_data[base + n] & 0xffffu), f32(mod_data[base + n + 1u] & 0xffffu));
    return mix(mix(h.x, h.y, t.x), mix(h.z, h.w, t.x), t.y) / 8.0 - 512.0;
}

// ---- the story's state at this moment, worked out once a pixel ----
struct VcS {
    t: f32,
    a: f32,      // since the eruption
    c: f32,      // since the collapse (under 0 before it)
    H: f32,      // the column's head over the land
    Hb: f32,     // the top of what is still standing of it, as it falls back
    Rt: f32,     // its radius at its head
    Rb: f32,     // the blast's radius over the land (the column's foot, later)
    Hd: f32,     // and its height
    dRb: f32,    // how fast the blast is spreading
    Ru: f32,     // the umbrella's radius
    dRu: f32,    // how fast it is spreading
    hu: f32,     // its middle: spreading out of the head under its top, rising to VC_HU
    rf: f32,     // the wall of ash's radius
    rfm: f32,    // and past it nothing
    dRf: f32,    // how fast it comes on
    ftop: f32,   // nothing of the flows stands over this
    cov: f32,    // how much of the light the umbrella stops
    thin: f32,   // 0 to 1: the ash thinning away at the end
    px: f32,     // the angle a pixel spans
    fine: f32,   // the march's pixel, in the picture's (2 at half size)
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
    // (the blast: out fast and low, wider than it is tall, drawing in a little as the column takes it over)
    s.Rb = (300.0 + 400.0 * (1.0 - exp(-a / 2.8))) * (1.0 - 0.1 * smoothstep(10.0, 28.0, a));
    s.dRb = 143.0 * exp(-a / 2.8);
    s.Hd = 130.0 + 270.0 * (1.0 - exp(-a / 3.0));
    // (the column breaking up out of its middle a few seconds on)
    s.H = s.Hd + 1560.0 * (1.0 - exp(-max(a - 4.0, 0.0) / 7.5));
    s.Rt = 470.0 + 0.2 * min(s.H, 1500.0);
    s.Hb = s.H - 0.5 * 26.0 * max(s.c, 0.0) * max(s.c, 0.0) - 8.0 * max(s.c, 0.0);
    // (a gravity current: quick as the head first spreads, slowing as it thins; out past the horizon by the collapse)
    let u = max(time - VC_SPREAD, 0.0);
    s.Ru = 620.0 * smoothstep(0.0, 3.0, u) + 130.0 * pow(u, 1.28);
    s.dRu = 166.0 * pow(max(u, 0.01), 0.28);
    s.hu = VC_HU - 420.0 * (1.0 - smoothstep(VC_SPREAD - 1.0, VC_SPREAD + 7.0, time));
    s.rf = vc_front(max(s.c, 0.0));
    s.dRf = 25.0 + 35.0 * exp(-max(s.c, 0.0) / 14.0);
    s.rfm = s.rf + 230.0;
    s.ftop = 340.0 + 760.0 * smoothstep(VC_LIFT - 4.0, VC_RED - 2.0, time);
    s.thin = pow(smoothstep(VC_RED, VC_LEN - 0.6, time), 1.3);
    s.cov = smoothstep(2.0, 16.0, u) * (1.0 - s.thin);
    s.px = frame.view_params.w / frame.resolution.y;
    s.fine = 1.0;
    vs = s;
    vc_land_set();
}

// ---- the shapes: each one's smooth body, as a distance ----
fn vc_smax(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * k * 0.25;
}
fn vc_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
// The steam before the eruption: thin jets along the ring's crack. (The mount's hook.)
fn vc_steam(hy: f32, rho: f32, ang: f32) -> f32 {
    let st = saturate((vs.t - VC_CRACK) / (VC_ERUPT - VC_CRACK));
    let Hs = 12.0 + 50.0 * st;
    var W = 2.0 + 7.0 * st;
    let jets = smoothstep(0.0, 34.0, hy) * (1.0 - smoothstep(60.0, 240.0, hy));
    if (jets > 0.0) {
        let sc = 0.5 + 0.5 * cos(13.0 * ang + 2.0 * sin(3.0 * ang + 0.7) + hy * 0.004);
        W = W * mix(1.0, 0.72 + 0.5 * sc * sc, jets);
    }
    return vc_smax(abs(rho - VC_RING) - W, hy - Hs, 34.0) * 0.82;
}
// The eruption's body, solid: the blast, an ellipsoid over the land far wider than it is tall, and out of its middle a
// trunk half its width, flaring into the head that feeds the umbrella. After the collapse the trunk falls back on
// itself and the blast's foot sinks into the flows.
fn vc_col(q: vec3<f32>, rho: f32, ang: f32, land: f32) -> f32 {
    if (vs.t < VC_CRACK) {
        return 1.0e5;
    }
    // (its foot on the land, not at the vent's height: the land may lie well above or below it)
    var hy = q.y;
    if (hy < 700.0) {
        hy = hy - land * (1.0 - smoothstep(120.0, 700.0, hy));
    }
    if (vs.a < 0.0) {
        return vc_steam(hy, rho, ang);
    }
    let c = max(vs.c, 0.0);
    // (no lathe turned this: pushed out unevenly round its foot, its trunk lobed and twisting as it climbs)
    // (bursting out harder one way than another)
    let br = 0.12 * sin(2.0 * ang + 1.0) + 0.09 * sin(5.0 * ang + 0.4) + 0.05 * sin(11.0 * ang + 2.1);
    let Rb = vs.Rb * (1.0 + br);
    let tall = 0.34 * sin(3.0 * ang + 2.0) + 0.24 * sin(7.0 * ang + 0.6) + 0.16 * sin(13.0 * ang + 4.0);
    let Hd = vs.Hd * (1.0 - 0.96 * smoothstep(3.0, 15.0, c)) * (1.0 + tall * (1.0 - smoothstep(6.0, 16.0, vs.a)));
    let e = vec2<f32>(rho / Rb, hy / Hd);
    let k0 = length(e);
    let k1 = max(length(vec2<f32>(rho / (Rb * Rb), hy / (Hd * Hd))), 1.0e-5);
    // (bounded at its rim: squashed flat, the estimate is the height over all the land, and lumps stood dark puffs on it)
    var d = max(k0 * (k0 - 1.0) / k1, (rho - Rb) * 0.8);
    // (its foot running on ahead of it: the base surge, gone as the column falls)
    if (c < 9.0) {
        let sr = 1.22 * Rb;
        let sh = 0.36 * vs.Hd;
        let es = vec2<f32>(rho / sr, hy / sh);
        let s0 = length(es);
        let s1 = max(length(vec2<f32>(rho / (sr * sr), hy / (sh * sh))), 1.0e-5);
        d = vc_smin(d, max(s0 * (s0 - 1.0) / s1, (rho - sr) * 0.8) + 300.0 * smoothstep(2.0, 9.0, c), 130.0);
    }
    let H = vs.H;
    if (H > vs.Hd + 15.0 && vs.Hb > 0.0) {
        // (bellied at the head while it climbs, flaring into the umbrella once there, thinning as it falls)
        let lobe = 0.17 * sin(3.0 * ang + hy * 0.0016 + 1.0) + 0.11 * sin(5.0 * ang - hy * 0.0021 + 2.2);
        let Rs0 = (540.0 + 200.0 * smoothstep(820.0, 1500.0, hy) * smoothstep(1000.0, 1500.0, H)) * (1.0 + lobe);
        let hd = (hy - (H - 0.72 * vs.Rt)) / (0.62 * vs.Rt);
        // (born narrow out of the blast's top, widening as it climbs: never a wide skirt at once)
        let gw = 0.3 + 0.7 * smoothstep(4.0, 10.0, vs.a);
        let Rs = (Rs0 + 0.2 * vs.Rt * exp(-hd * hd) * (1.0 - smoothstep(1200.0, 1600.0, H))) * (1.0 - 0.3 * smoothstep(0.0, 11.0, c)) * gw;
        let Rd = vs.Rt * gw;
        let dome = 0.5 * Rd * min(rho * rho / (Rd * Rd), 1.6);
        var top = hy - (min(H, vs.Hb + 60.0) - dome);
        if (c > 0.0) {
            // (the top of what is left, rounded)
            top = vc_smax(top, hy - vs.Hb, 60.0);
        }
        d = vc_smin(d, vc_smax((rho - Rs) * 0.85, top, 90.0), 260.0);
    }
    return d;
}
// The ripple running out through the umbrella (Hunga Tonga's gravity waves): trains of waves leaving the head as it
// bobs, their height over the sheet.
fn vc_ripple(r: f32) -> f32 {
    let f = vs.t - VC_SPREAD - 2.0;
    if (f <= 0.0) {
        return 0.0;
    }
    let R = 290.0 * f;                                       // the first wave's front
    let ph = (R - r) / 210.0;
    return 26.0 * sin(ph * TAU) * smoothstep(-0.2, 1.0, ph) * exp(-max(ph, 0.0) / 4.5) * smoothstep(300.0, 900.0, r);
}
// The umbrella: a sheet with real bulk, thick over the head, thinning out to a rounded rolling head at its nose (a
// gravity current's).
fn vc_umb(q: vec3<f32>, r0: f32) -> f32 {
    if (vs.Ru < 10.0) {
        return 1.0e5;
    }
    let hy = q.y;
    // (never a clean disc: pushed out unevenly round its edge, more so as it grows)
    let cs = q.x / max(r0, 1.0);
    let sn = q.z / max(r0, 1.0);
    let r = r0 * (1.0 + 0.11 * (4.0 * cs * cs * cs - 3.0 * cs) + 0.075 * (2.0 * sn * cs) + 0.05 * (1.0 - 2.0 * sn * sn) * cs);
    let e = saturate((vs.Ru - r) / 520.0);
    let prof = sqrt(e * (2.0 - e));
    let core = exp(-r * r / (1200.0 * 1200.0));
    let nose = exp(-pow((vs.Ru - r - 300.0) / 280.0, 2.0));
    // (thin while young: it spreads out of the head, under its top, not over it)
    let g = saturate(vs.Ru / 1300.0);
    let th = (210.0 + 240.0 * core + 120.0 * nose) * prof * g;
    let hm = vs.hu + 30.0 * (1.0 - prof);
    let bot = hm - 0.9 * th - 230.0 * exp(-r * r / (800.0 * 800.0)) * g;
    let tp = hm + 2.2 * vc_ripple(r) + 0.9 * th + 140.0 * core * g;
    return vc_smax(vc_smax(hy - tp, bot - hy, 60.0) * 0.8, (r - vs.Ru) * 0.8, 120.0);
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
    // (a steep rounded head, then a body thickening behind it)
    let nose = 235.0 * (1.0 - exp(-ep / 75.0)) * smoothstep(0.0, 2.0, c);
    var top = nose + 0.10 * min(ep, 700.0);
    // (the new clouds rising off it, once it has slowed and lost its load)
    let lift = smoothstep(VC_LIFT - 8.0, VC_RED, vs.t);
    if (lift > 0.0) {
        let tw = gnoise2(vec2<f32>(ang * 3.3, rho / 600.0));
        top = top + 560.0 * lift * smoothstep(120.0, 620.0, ep) * smoothstep(0.34, 0.74, tw + 0.5 * lob);
    }
    let d = vc_smax((h - top) * 0.75, -e * 0.85, 70.0);
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
    b.ang = atan2(q.z, q.x);
    let fl = vs.c > 0.0 && q.y < vs.ftop + VC_DM && rho < vs.rfm + VC_DM;
    b.land = 0.0;
    if (fl || q.y < 700.0) {
        b.land = vc_land(q.xz);
    }
    b.dc = vc_col(q, rho, b.ang, b.land);
    b.du = vc_umb(q, rho);
    b.df = 1.0e5;
    b.e = -1.0e5;
    if (fl) {
        let f = vc_flow(q, rho, b.ang, b.land);
        b.df = f.x;
        b.e = f.y;
    } else {
        // (the rest of the march reads it only under the flows)
        b.land = 0.0;
    }
    b.d = vc_smin(vc_smin(b.dc, b.du, 120.0), b.df, 60.0);
    return b;
}
// The base alone, for the light's looks along the way to the sun.
fn vc_dist(q: vec3<f32>) -> f32 {
    return vc_base(q).d;
}
// How far the ray may go with no smooth body nearer than the lumps reach: the sheet and the flows' layer are flat, so a
// low ray is carried straight to them, not crept up on.
fn vc_skip(q: vec3<f32>, rd: vec3<f32>, b: ptr<function, VcB>) -> f32 {
    let dm = VC_DM + 10.0;
    var s = (*b).dc - dm;
    // (the umbrella's layer)
    if (vs.Ru > 10.0) {
        let lo = vs.hu - 720.0 - dm;
        let hi = vs.hu + 680.0 + dm;
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

// ---- the lumps: domes over a jittered lattice (as the Nuke's pl_dome) ----
fn vc_dome(p: vec3<f32>) -> f32 {
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
const VC_R1: mat3x3<f32> = mat3x3<f32>(-0.0014, 0.9977, -0.0674, -0.2224, -0.0660, -0.9727, -0.9750, 0.0136, 0.2220);
const VC_R2: mat3x3<f32> = mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971);
const VC_R3: mat3x3<f32> = mat3x3<f32>(-0.9891, -0.1223, 0.0816, 0.0968, -0.9594, -0.2651, 0.1107, -0.2543, 0.9608);

// What carries the lumps at q: .xyz blocks a second, .w the rate all of it swells out from the axis (the blast and sheet
// spreading, as a stretch, which can't fold over as a speed would). Carried a while and let go (`vc_lump`): only ever the
// flow here and now, so nothing winds up into streaks.
fn vc_vel(q: vec3<f32>, rho: f32, wc: f32, wu: f32, wf: f32) -> vec4<f32> {
    let hy = q.y;
    let r = max(rho, 1.0);
    var vr = 0.0;
    var vy = 0.0;
    var gr = 0.0;
    if (wc > 0.0) {
        // (up the trunk, slowing under the head, which spreads over its own top; the blast's top its head till the trunk
        // climbs out, let go slowly, or every lump jumps)
        var uy = 10.0 + 66.0 * (1.0 - smoothstep(900.0, 1750.0, hy));
        let hh = max(saturate((hy - (vs.H - 460.0)) / 460.0), saturate((hy - (vs.Hd - 460.0)) / 460.0) * (1.0 - smoothstep(4.0, 14.0, vs.a)));
        var ur = 52.0 * hh * smoothstep(0.0, 0.8 * vs.Rt, r);
        // (and the blast rolling round a ring inside its edge: up its inside, out over its top, down its front, in under
        // it; carried out as it spreads)
        let uv = vec2<f32>(r - 0.72 * vs.Rb, hy - 0.5 * vs.Hd);
        let rr = 0.9 * vs.Hd;
        let wr = exp(-dot(uv, uv) / (rr * rr));
        ur = mix(ur, 0.13 * uv.y, wr);
        uy = mix(uy, -0.13 * uv.x, wr);
        if (vs.c > 0.0) {
            // (once it has lost its buoyancy all of it comes down, faster and faster, spreading at its foot)
            let fall = smoothstep(0.0, 3.0, vs.c);
            uy = mix(uy, -30.0 - 16.0 * vs.c, fall * smoothstep(0.0, 200.0, hy));
            ur = ur + 40.0 * fall * (1.0 - smoothstep(0.0, 300.0, hy));
        }
        vr = vr + wc * ur;
        vy = vy + wc * uy;
        gr = gr + wc * min(vs.dRb / vs.Rb, 0.075) * (1.0 - smoothstep(0.8 * vs.Hd, 1.4 * vs.Hd, hy));
    }
    if (wu > 0.0) {
        gr = gr + wu * min(vs.dRu / max(vs.Ru, 300.0), 0.075);
    }
    if (wf > 0.0) {
        // (the wall's head rolling forward over itself)
        vr = vr + wf * vs.dRf;
        vy = vy + wf * 14.0;
    }
    return vec4<f32>(q.x / r * vr, vy, q.z / r * vr, gr);
}
// The small lumps at q: each size faded in by how near the surface is (`rest`, less the big lumps) and its size in pixels:
// a size that simply starts draws a contour. Uses vc_lump's vc_lw, vc_lsy. .x how far out, .y of a dome, .z the fray.
var<private> vc_lw: vec4<f32>;
var<private> vc_cq: vec4<f32>;
var<private> vc_cb: vec4<f32>;
var<private> vc_cw: vec4<f32>;
var<private> vc_cy: f32;
var<private> vc_cs: f32;
var<private> vc_lsy: vec2<f32>;
fn vc_fine(q: vec3<f32>, rest: f32, foot: f32) -> vec3<f32> {
    var o = vec3<f32>(0.0, 1.0, 0.5);
    let g3 = saturate((120.0 - rest) / 40.0) * saturate((28.0 - foot) / 12.0);
    if (g3 <= 0.0) {
        return o;
    }
    let gain = vc_lw.w;
    let qf = vec3<f32>(q.x, q.y * vc_lsy.x, q.z) - vec3<f32>(0.0, 16.0 * vs.t * vc_lsy.y, 0.0) + vc_lw.xyz * 0.5;
    // (smooth noise from here down, not domes: a dome's sharp crease this small reads as cracked mud)
    let n3 = vc_gn3(VC_R3 * (qf * (1.0 / 44.0) + vec3<f32>(1.7, 0.0, -2.1)));
    let bl3 = sqrt((2.0 * n3 - 1.0) * (2.0 * n3 - 1.0) + 0.012);
    o.x = g3 * (6.0 + 26.0 * gain) * (0.9 * (n3 - 0.5) + 1.1 * (bl3 - 0.3));
    let g4 = saturate((90.0 - rest) / 30.0) * saturate((11.0 - foot) / 5.0);
    if (g4 > 0.0) {
        let n4 = vc_gn3(VC_R1 * (qf * (1.0 / 19.0) + vec3<f32>(-4.7, 2.0, 0.3)));
        let bl4 = sqrt((2.0 * n4 - 1.0) * (2.0 * n4 - 1.0) + 0.012);
        o.x = o.x + g4 * 22.0 * (bl4 - 0.3);
        let g5 = saturate((70.0 - rest) / 25.0) * saturate((4.5 - foot) / 2.0);
        if (g5 > 0.0) {
            let n5 = vc_gn3(VC_R2 * (qf * (1.0 / 7.0)) + vec3<f32>(0.3, 0.0, 0.25 * vs.t));
            o.x = o.x + g5 * 9.0 * (n5 - 0.5);
            o.z = mix(0.5, n5, g5);
        }
    }
    return o;
}
// The lumps on the bodies, lumps on lumps: rough cauliflower, its big lumps carried by the flow two sets at a time, half a
// turn apart, each fading in as the other goes (the Nuke's roll), the small ones drifting over them. `d1` how far off the
// body is (small lumps only close to it). `fine` false: the light's look.
// .x how far it stands out, .y how far up a dome (1 a crown, 0 a crease), .z unused, .w the fray.
fn vc_lump(q: vec3<f32>, b: ptr<function, VcB>, d1: f32, foot: f32, fine: bool) -> vec4<f32> {
    let dc = (*b).dc;
    let du = (*b).du;
    let df = (*b).df;
    let wc0 = saturate(1.0 + (min(du, df) - dc) / 70.0);
    let wu0 = saturate(1.0 + (min(dc, df) - du) / 70.0);
    let wf0 = saturate(1.0 + (min(dc, du) - df) / 70.0);
    let sum = max(wc0 + wu0 + wf0, 1.0e-3);
    let wc = wc0 / sum;
    let wu = wu0 / sum;
    let wf = wf0 / sum;
    // (the big lumps looked up again only every few blocks along the ray: they change slowly and cost the most)
    let dq = q - vc_cq.xyz;
    let hold = 4.0 + 0.6 * foot + VC_HOLD * vc_cs;
    var out_ = 0.0;
    var top = 0.0;
    var warp = vc_cw.xyz;
    var gain = vc_cw.w;
    var sy = vc_cy;
    if (fine && dot(dq, dq) < hold * hold) {
        out_ = vc_cb.x;
        top = vc_cb.y;
    } else {
    let rho = (*b).rho;
    let v = vc_vel(q, rho, wc, wu, wf);
    // (the sheet's lumps broad and flat, pouches under it, roughest at its nose; the wall's hug its face, not run ahead)
    gain = (wc + 0.62 * wf * smoothstep(-110.0, 10.0, (*b).e)) * mix(0.13, 1.0, smoothstep(0.0, 0.5, vs.a));
    sy = 1.0 + 0.28 * wf;
    if (wu > 0.0) {
        let nose = exp(-max(vs.Ru - rho, 0.0) / 520.0);
        let under = 1.0 - smoothstep(VC_HU - 260.0, VC_HU - 40.0, q.y);
        let core = exp(-rho * rho / (1800.0 * 1800.0));
        gain = gain + wu * (0.3 + 0.4 * core + 0.55 * nose + 0.85 * under);
        sy = sy + wu * mix(0.8, 0.25, under);
    }
    let q0 = vec3<f32>(q.x, q.y * sy, q.z);
    // (the lattice folded by two sizes of noise, so no cell shows)
    let w = vc_gn3(VC_R2 * q0 * (1.0 / 470.0));
    var w2 = 0.5;
    if (fine) {
        w2 = vc_gn3(VC_R3 * q0 * (1.0 / 180.0) + vec3<f32>(4.0, 0.0, 0.06 * vs.t));
    }
    warp = vec3<f32>(w - 0.5, w2 - 0.5, w2 - w) * 170.0;
    let ph = fract(vs.t / VC_P);
    let wA = 1.0 - abs(2.0 * ph - 1.0);
    let kd = select(1, 0, wA >= 0.5);
    var b1 = 0.0;
    var b2 = 0.0;
    var ws = 0.0;
    for (var k = select(kd, 0, fine); k < select(kd + 1, 2, fine); k = k + 1) {
        let wk = select(1.0 - wA, wA, k == 0);
        let tk = fract(ph + 0.5 * f32(k)) * VC_P;
        let cy = floor(vs.t / VC_P + 0.5 * f32(k));
        let st = 1.0 - exp(-v.w * tk);
        let qk = q0 - vec3<f32>(v.x * tk + q.x * st, v.y * sy * tk, v.z * tk + q.z * st) + warp;
        let o = vec3<f32>(3.1 + 7.3 * cy, 2.9 * f32(k), 7.7 - 4.1 * cy);
        b1 = b1 + wk * vc_dome(VC_R1 * (qk * (1.0 / 310.0) + o));
        if (fine) {
            b2 = b2 + wk * vc_dome(VC_R2 * (qk * (1.0 / 122.0) + o * 1.7));
        }
        ws = ws + wk;
    }
    b1 = b1 / max(ws, 1.0e-3);
    b2 = select(0.62, b2 / max(ws, 1.0e-3), fine);
    if (fine) {
        // (two half sets added are evener than one: their spread put back)
        let sp = 1.0 / sqrt(wA * wA + (1.0 - wA) * (1.0 - wA));
        b1 = 0.62 + (b1 - 0.62) * sp;
        b2 = 0.62 + (b2 - 0.62) * sp;
    }
    out_ = gain * (165.0 * (b1 - 0.56) + 74.0 * (b2 - 0.56) + 70.0 * (w - 0.5));
    if (wu > 0.0 && out_ < 0.0) {
        out_ = out_ * (1.0 - 0.72 * wu);
    }
    top = saturate(0.1 + 0.9 * b1 * (0.45 + 0.55 * b2));
    if (fine) {
        vc_cq = vec4<f32>(q, 1.0);
        vc_cb = vec4<f32>(out_, top, 0.0, 0.0);
        vc_cw = vec4<f32>(warp, gain);
        vc_cy = sy;
    }
    }
    var fray = 0.5;
    vc_lw = vec4<f32>(warp, gain);
    vc_lsy = vec2<f32>(sy, wc);
    if (fine) {
        let f = vc_fine(q, d1 - out_, foot);
        out_ = out_ + f.x;
        top = top * f.y;
        fray = f.z;
    }
    return vec4<f32>(out_, top, 0.0, fray);
}
// The surface at q: the smooth bodies (b) bulged out by the lumps. .x the distance, .y how far up a dome, .w the fray.
fn vc_sdf(q: vec3<f32>, b: ptr<function, VcB>, foot: f32, fine: bool) -> vec4<f32> {
    let l = vc_lump(q, b, (*b).d, foot, fine);
    // (the lumps' height capped smoothly, so nothing stands out past what the march allows)
    let bp = max(l.x, 0.0);
    let bump = l.x - bp + bp / sqrt(sqrt(1.0 + pow(bp / VC_DM, 4.0)));
    let d = (*b).d - bump;
    if (fine) {
        vc_cs = min(abs(d), 120.0);
    }
    return vec4<f32>(d, l.y, l.z, l.w);
}

// ---- the light ----
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

// ---- the lightning, as the Hurricane's hu_flashes: a slot of 0.13 s, a few alive at once. When, where and how strong
// (0x901 to 0x906, 0x908) vc_sound.rs's `flashes` copies for its thunder: keep them in step. Another hash says what: a
// third bolts to the land (most where the player sees them), a third channels out of the cloud, the rest in it (a third
// of those faint); strokes as the Hurricane's: a cloud's flickers over 0.3 s, a bolt's leader, return stroke, re-strokes.
const VC_BOLTS_AHEAD: f32 = 0.5;
const VC_BOLTS_ASIDE: f32 = 0.13;
const VC_CHANNELS: f32 = 0.76;     // (and up to here of the same hash, a channel out of the cloud)
const VC_LEAD: f32 = 0.075;
const VC_FL_END: f32 = 0.39;       // (three slots' worth: a flash is gone by the time its slot is dropped)
// (ten times the Hurricane's bolts: thicker, kinkier, a wider pool on the land)
const VC_BEAM_R: f32 = 13.0;
const VC_CHAN_W: f32 = 4.0;
const VC_KINK_LEN: f32 = 260.0;
const VC_THRU: f32 = 0.55;         // (how much of a channel shows through the ash under the cloud's face: its core the square of it, a blur of light)
const VC_FOOT_R2: f32 = 6000.0;
struct VcFlash {
    p: vec3<f32>,      // where, from the vent
    k: f32,            // how bright now, on the cloud round it
    ring: f32,         // 1 in the umbrella's rings, 0 in the plume
    id: f32,
    a: f32,            // seconds since it began
    n: u32,            // its strokes' hash
    kind: u32,         // 0 in the cloud alone, 1 a bolt to the land, 2 a channel out of the cloud
}
struct VcFlashes {
    f: array<VcFlash, 3>,
}
// The strokes of a flash in the cloud (the Supercell's sc_stroke, as hu_stroke): 1 at a stroke's peak.
fn vc_strokes(a: f32, n: u32) -> f32 {
    let count = 1u + n % 4u;
    var s = 0.0;
    var ts = 0.0;
    for (var k = 0u; k <= count; k = k + 1u) {
        let h = f32(pcg(n * 13u + k) & 1023u) / 1023.0;
        ts = ts + select(0.04 + 0.09 * h, 0.0, k == 0u);
        s = s + select(0.5 + 0.4 * h, 1.0, k == 0u) * exp(-max(a - ts, 0.0) / 0.04) * step(ts, a);
    }
    return (s + 0.08 * exp(-a / 0.25)) * (1.0 - smoothstep(0.3, VC_FL_END, a));
}
// A bolt's timing (hu_beam_k, hu_lead_k): a jagged leader flickering ~75 ms, new every two frames; the return stroke, drawn
// up off the land from 0.17 s, gone by 0.27; then a re-stroke or two, a frame or two each.
fn vc_flick(a: f32, n: u32, k: u32) -> f32 {
    return f32(pcg(n * 31u + k * 7u + u32(max(a, 0.0) * 30.0)) & 1023u) / 1023.0;
}
fn vc_beam_k(a: f32, n: u32) -> f32 {
    return smoothstep(0.05, VC_LEAD, a) * (1.0 - smoothstep(0.19, 0.27, a)) * (0.88 + 0.12 * vc_flick(a, n, 1u));
}
fn vc_lead_k(a: f32, n: u32) -> f32 {
    if (a < VC_LEAD) {
        return 0.55 + 0.45 * vc_flick(a, n, 2u);
    }
    let r0 = 0.28 + 0.03 * f32(n & 7u) / 7.0;
    let r1 = 0.335 + 0.03 * f32((n >> 3u) & 7u) / 7.0;
    return 0.8 * (step(r0, a) * step(a, r0 + 0.034) + 0.7 * step(r1, a) * step(a, r1 + 0.018));
}
fn vc_bolt_stroke(a: f32, n: u32) -> f32 {
    return (max(vc_beam_k(a, n), 0.6 * vc_lead_k(a, n)) + 0.12 * exp(-a / 0.15)) * (1.0 - smoothstep(0.34, VC_FL_END, a));
}
// (where the player is, off the vent)
fn vc_me() -> vec2<f32> {
    return vec2<f32>(frame.mod_params[3].x - anchor_xz().x, frame.mod_params[3].z - anchor_xz().y);
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
    // (bolts where the player can see them, ahead of the column, not behind it; fewer in the rest of the sky)
    let me = vc_me();
    let way = normalize(-me + vec2<f32>(1.0e-3, 0.0));
    let ahead = dot(normalize(o.p.xz - me), way);
    let hidden = smoothstep(0.35, 0.8, dot(o.p.xz, way) / max(length(o.p.xz), 1.0)) * (1.0 - smoothstep(700.0, 1100.0, abs(o.p.x * way.y - o.p.z * way.x)));
    let what = mh(slot, seed, 0x921u);
    let bolt = what < mix(VC_BOLTS_ASIDE, VC_BOLTS_AHEAD, smoothstep(0.45, 0.75, ahead) * (1.0 - hidden));
    o.kind = select(select(0u, 2u, what < VC_CHANNELS), 1u, bolt);
    o.a = age;
    o.n = u32(mh(slot, seed, 0x907u) * 65535.0);
    let br = select(vc_strokes(age, o.n), vc_bolt_stroke(age, o.n), bolt);
    let faint = select(1.0, 0.3, !bolt && mh(slot, seed, 0x922u) < 0.34);
    // (a bolt lights the cloud round its root less than a flash in the cloud does)
    o.k = br * select(1.0, 0.6, bolt) * faint * (0.5 + 0.8 * mh(slot, seed, 0x908u));
    return o;
}
fn vc_flashes(seed: u32) -> VcFlashes {
    var o: VcFlashes;
    o.f[0] = vc_flash(0, seed);
    o.f[1] = vc_flash(1, seed);
    o.f[2] = vc_flash(2, seed);
    return o;
}

// ---- the lava bombs: on ballistic arcs off the ring (volcano.rs's vc_bombs, each down where it meets the land) ----
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
// The trail where the bomb passed at time `s`, by now: the arc itself wandering smoothly as the smoke drifts and rises.
fn vc_rope_at(b: VcBomb, ph: f32, s: f32) -> vec3<f32> {
    let age = max(vs.t - s, 0.0);
    let g = 1.0 - exp(-age / 2.6);
    let w = vec3<f32>(sin(s * 1.1 + ph) + 0.5 * sin(s * 2.7 + ph * 1.7), 0.6 * sin(s * 1.7 + ph * 2.3), cos(s * 1.3 + ph * 0.7) + 0.5 * sin(s * 3.1 + ph));
    return vc_bomb_at(b, s) + w * (9.0 * g) + vec3<f32>(0.0, 1.5 * age, 0.0);
}
// A stretch of smoke as a soft billowing tube: `X` where the ray passes it (fixed in the world, so the billows stay
// where they were laid), `ax` the axis nearest it, `w` its radius, `age` its seconds. .x its cover, .y how much of the
// sun's light its face takes.
fn vc_tube(X: vec3<f32>, ax: vec3<f32>, rd: vec3<f32>, L: vec3<f32>, w: f32, age: f32, sz: f32) -> vec2<f32> {
    let r = X - ax;
    let n1 = vc_gn3(X * (1.0 / sz) + vec3<f32>(0.0, -0.08 * vs.t, 0.06 * vs.t));
    let n2 = vc_gn3(VC_R1 * X * (3.0 / sz) + vec3<f32>(0.16 * vs.t, 3.0, 0.0));
    let x = length(r) / w;
    let xe = x + 0.85 * (0.26 - abs(2.0 * n1 - 1.0)) + 0.38 * (n2 - 0.5);
    let cov = 1.0 - smoothstep(0.35, 1.0, xe);
    // (its face: round the axis towards the eye, its billows tipping it)
    let n = normalize(r / w + -rd * sqrt(max(1.0 - x * x, 0.05)) + 0.8 * vec3<f32>(n1 - 0.5, n2 - 0.5, n1 - n2));
    return vec2<f32>(cov, saturate(0.5 + 0.5 * dot(n, L)));
}
// Smoke `al` of colour `sc` at `t` laid under the cloud: hidden as much as the cloud in front hides it (vc_ctr, from where
// the march's light fell past 0.9, 0.6, 0.3, 0.1: vc_tk), hiding the part of the cloud behind it (vc_cm).
var<private> vc_tk: vec4<f32>;
var<private> vc_tx: vec2<f32>;
var<private> vc_cm: f32;
fn vc_ctr(t: f32) -> f32 {
    let k = vc_tk;
    var r = mix(1.0, 0.9, saturate((t - k.x) / 24.0 + 1.0));
    r = mix(r, 0.6, saturate((t - k.x) / max(k.y - k.x, 1.0)));
    r = mix(r, 0.3, saturate((t - k.y) / max(k.z - k.y, 1.0)));
    r = mix(r, 0.1, saturate((t - k.z) / max(k.w - k.z, 1.0)));
    r = mix(r, 0.0, saturate((t - k.w) / 16.0));
    return max(1.0 - (1.0 - saturate((r - 0.051) / 0.949)) * vc_tx.x, vc_tx.y);
}
fn vc_lay(c: ptr<function, vec3<f32>>, tr: ptr<function, f32>, tm: ptr<function, f32>, al: f32, sc: vec3<f32>, t: f32) {
    let v = vc_ctr(t);
    *c = *c + *tr * al * v * sc;
    *tr = *tr * (1.0 - al);
    vc_cm = vc_cm * (1.0 - al * saturate((v - vc_tx.y) / max(1.0 - vc_tx.y, 1.0e-3)));
    if (v > 0.5) {
        *tm = min(*tm, t);
    }
}
// Their smoke (half size): .rgb what it adds (premultiplied), .a what it leaves; `tm` how far off the nearest is.
fn vc_bombs_smoke(C: vec3<f32>, rd: vec3<f32>, tmax: f32, l: VcLight, amb0: vec3<f32>, tm: ptr<function, f32>) -> vec4<f32> {
    let n = u32(vc_w(1u));
    let time = vs.t;
    var c = vec3<f32>(0.0);
    var tr = 1.0;
    if (time < VC_ERUPT + 1.0 || time > VC_COLLAPSE + 14.0) {
        return vec4<f32>(c, tr);
    }
    let brown = vec3<f32>(0.13, 0.095, 0.07);
    let amb = mix(amb0, vec3<f32>(dot(amb0, vec3<f32>(0.2126, 0.7152, 0.0722))) * vec3<f32>(1.3, 0.8, 0.5), vs.cov);
    for (var i = 0u; i < n; i = i + 1u) {
        let b = vc_bomb(i);
        if (b.t0 >= time) {
            break;
        }
        let late = time - b.tl;
        if (late > 16.0) {
            continue;
        }
        let ph = f32(i) * 2.399;
        let size = 0.7 + 0.6 * mh(i, 7u, 0x35u);
        let te = min(time, b.tl);
        let ts = max(b.t0 + 0.2, te - 10.0);
        let T = te - ts;
        if (T > 0.0) {
            let a = vc_bomb_at(b, ts) + C;
            let e = vc_bomb_at(b, te) + C;
            let sag = 0.125 * VC_G * T * T;
            let g = pl_ray_seg(rd, a, e, 0.0, 1.0);
            let wmax = 34.0 * size;
            // (near the arc at all: then along it for where the ray passes nearest, by steps and then by Gauss-Newton, so
            // the rope is one smooth curve however it is seen)
            if (g.x < sag + wmax + 14.0 + g.y * vs.px * 3.0) {
                var sb = ts;
                var db = 1.0e12;
                for (var k = 0; k <= 8; k = k + 1) {
                    let s = ts + T * f32(k) / 8.0;
                    let pk = vc_rope_at(b, ph, s) + C;
                    let tk = max(dot(pk, rd), 0.0);
                    let dk = pk - rd * tk;
                    let d2 = dot(dk, dk);
                    if (d2 < db) {
                        db = d2;
                        sb = s;
                    }
                }
                for (var k = 0; k < 3; k = k + 1) {
                    let pk = vc_rope_at(b, ph, sb) + C;
                    let dp = b.v - vec3<f32>(0.0, VC_G * (sb - b.t0), 0.0);
                    let pp = pk - rd * dot(pk, rd);
                    let dd = dp - rd * dot(dp, rd);
                    sb = clamp(sb - dot(pp, dd) / max(dot(dd, dd), 1.0), ts, te);
                }
                let P = vc_rope_at(b, ph, sb) + C;
                let tc = dot(P, rd);
                let age = time - sb;
                // (thick from the first, swelling with age, thinning; brown smoke, hot at its head)
                let w = size * (5.0 + 6.2 * sqrt(age));
                let wv = max(w, tc * vs.px * 1.5);
                if (tc > 2.0 && tc < tmax + wv && length(P - rd * tc) < 1.9 * wv) {
                    let q = rd * tc - C;
                    let f = vc_tube(q, P - C, rd, l.L, wv, age, 26.0 * size);
                    // (a rope passing close to the eye thinned away: it would only be a smear across the picture)
                    let al = smoothstep(30.0, 240.0, tc) * saturate((tmax - tc + wv) / wv) * f.x * saturate(0.9 * exp(-age / 5.5) * (w / wv)) * (1.0 - smoothstep(te - ts - 0.5, te - ts, age) * smoothstep(9.0, 10.0, age)) * smoothstep(0.0, 0.5, age + 0.2);
                    if (al > 0.003) {
                        let hot = exp(-age / 0.22) * f.x;
                        let sun = l.sunc * vc_sun_t(q, l.L) * f.y * f.y * 1.1;
                        let sc = brown * (amb * (0.5 + 0.6 * f.y) + sun) + vec3<f32>(1.3, 0.34, 0.05) * hot * hot * hot;
                        vc_lay(&c, &tr, tm, al, sc, tc);
                    }
                }
            }
        }
        // (the black plume it throws up where it comes down, fed for a moment, then rising away and thinning)
        if (late > 0.0) {
            let P = vc_bomb_at(b, b.tl) + C;
            let Hp = size * 150.0 * (1.0 - exp(-late / 2.6));
            let sg = pl_ray_seg(rd, P, P + vec3<f32>(0.0, Hp, 0.0), 0.0, 1.0);
            let w = size * (5.0 + 15.0 * sqrt(late)) * (0.45 + 0.75 * sg.z);
            let wv = max(w, sg.y * vs.px * 1.5);
            if (sg.y > 2.0 && sg.x < 1.9 * wv && sg.y < tmax + 2.0 * wv) {
                let q = rd * sg.y - C;
                let ax = P + vec3<f32>(0.0, Hp * sg.z, 0.0) - C;
                let f = vc_tube(q, ax, rd, l.L, wv, late, 34.0 * size);
                let al = saturate((tmax - sg.y + 2.0 * wv) / (2.0 * wv)) * f.x * saturate(1.1 * exp(-late / 5.0) * (w / wv)) * (1.0 - 0.5 * sg.z * (1.0 - exp(-late / 2.0)));
                if (al > 0.003) {
                    let sun = l.sunc * vc_sun_t(q, l.L) * f.y * f.y * 0.5;
                    let sc = vec3<f32>(0.036, 0.032, 0.03) * (amb * (0.4 + 0.6 * f.y) + sun) + vec3<f32>(0.9, 0.2, 0.03) * exp(-late / 0.35) * (1.0 - sg.z);
                    vc_lay(&c, &tr, tm, al, sc, sg.y);
                }
            }
        }
    }
    return vec4<f32>(c, tr);
}
// Their glowing heads (sharp, at full size): what they add at this pixel. Behind the cloud (`ct`, `ca` what it leaves) a
// soft glow through it, dimmer the deeper.
fn vc_bombs_heads(C: vec3<f32>, rd: vec3<f32>, tmax: f32, ct: f32, ca: f32) -> vec3<f32> {
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
        let s = vc_bomb_at(b, te - 0.02) + C;
        let sg = pl_ray_seg(rd, s, p, 0.0, 1.0);
        let ppx = sg.x * focal / max(t, 1.0);
        let sz = (1.0 + 1.6 * mh(i, 3u, 0x31u)) * focal / max(t, 1.0);
        let rpx = clamp(sz, 0.9, 3.2);
        let occ = smoothstep(ct + 10.0, ct + 50.0, t) * (1.0 - ca);
        let hr = max(4.0 * rpx, 22.0 * focal / max(t, 1.0));
        if (ppx > select(14.0 * rpx + 4.0, 5.0 * hr, occ > 0.0)) {
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
        c = c + hc * ((core * 1.6 + glow) * (1.0 - occ) + occ * 0.1 * exp(-max(t - ct, 0.0) / 150.0) / (1.0 + pow(ppx / hr, 2.0))) * land;
    }
    return c;
}

// ---- the spray of rock thrown out of the blast: chunks flung radially out of the fireball, dark against it, hot where they
// show against the sky (sharp, at full size). .rgb what it adds, .a what it leaves of what is behind.
fn vc_spray(C: vec3<f32>, rd: vec3<f32>, tmax: f32, seed: u32) -> vec4<f32> {
    var c = vec3<f32>(0.0);
    var tr = 1.0;
    let focal = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
    for (var i = 0u; i < 56u; i = i + 1u) {
        let t0 = 0.8 + 6.5 * mh(i, seed, 0x941u);
        let s = vs.a - t0;
        if (s <= 0.0 || s > 13.0) {
            continue;
        }
        let th = TAU * mh(i, seed, 0x942u);
        let el = 0.12 + 1.15 * mh(i, seed, 0x943u);
        let dir = vec3<f32>(cos(th) * cos(el), sin(el), sin(th) * cos(el));
        let v = dir * (150.0 + 210.0 * mh(i, seed, 0x944u));
        let p0 = dir * vec3<f32>(320.0, 160.0, 320.0);
        // (slowing in the air, so it comes down, and not somewhere past the edge of the world)
        let e = exp(-s / 4.0);
        let p = p0 + v * 4.0 * (1.0 - e) - vec3<f32>(0.0, 0.5 * VC_G * s * s, 0.0);
        if (p.y < 0.0) {
            continue;
        }
        let vn = v * e - vec3<f32>(0.0, VC_G * s, 0.0);
        let a = p + C;
        let b = a - vn * 0.05;
        let sg = pl_ray_seg(rd, a, b, 0.0, 1.0);
        if (sg.y <= 1.0 || sg.y > tmax + 30.0) {
            continue;
        }
        let px = sg.x * focal / sg.y;
        let rpx = clamp((2.0 + 3.0 * mh(i, seed, 0x945u)) * focal / sg.y, 0.8, 6.0);
        if (px > 3.0 * rpx) {
            continue;
        }
        let core = saturate(1.0 - px / rpx);
        let hot = exp(-s / 3.0);
        c = c + tr * core * (vec3<f32>(0.03, 0.022, 0.018) + vec3<f32>(1.5, 0.42, 0.06) * hot * hot * (1.0 - sg.z * 0.8));
        tr = tr * (1.0 - core);
    }
    return vec4<f32>(c, tr);
}

// ---- the bolts themselves: what of a flash is seen as lightning, sharp, at full size ----
// Where a flash's channel runs: from f.p along this, in blocks. A bolt out of the column's flank or down out of the sheet
// to the land; in the plume out of its side, down and across; in the sheet running along under it, forking.
fn vc_flash_way(f: VcFlash, seed: u32) -> vec3<f32> {
    let sid = u32(f.id);
    let th = TAU * mh(sid, seed, 0x911u);
    let h = mh(sid, seed, 0x912u);
    let out = atan2(f.p.z, f.p.x) + 1.1 * (mh(sid, seed, 0x913u) - 0.5);
    if (f.kind == 1u) {
        var foot = f.p.xz + vec2<f32>(cos(th), sin(th)) * (120.0 + 320.0 * h);
        if (f.ring < 0.5) {
            // (clear of the blast's foot and of what the flows have covered)
            foot = vec2<f32>(cos(out), sin(out)) * max(max(vs.Rb, vs.rf), length(f.p.xz)) * (1.45 + 0.6 * h);
        }
        // (a bolt near the player comes down between them and the cloud: past the column it would never be seen)
        let me = vc_me();
        if (length(f.p.xz - me) < 1500.0) {
            let w = normalize(-me + vec2<f32>(1.0e-3, 0.0));
            let across = vec2<f32>(-w.y, w.x);
            foot = me + w * clamp(dot(f.p.xz - me, w) - 60.0 - 140.0 * h, 190.0, 560.0) + across * (0.8 * dot(f.p.xz - me, across) + 300.0 * (mh(sid, seed, 0x914u) - 0.5));
        }
        return vec3<f32>(foot.x, vc_land(foot), foot.y) - f.p;
    }
    if (f.ring > 0.5) {
        return vec3<f32>(cos(th) * 720.0, -40.0 - 50.0 * h, sin(th) * 720.0);
    }
    return vec3<f32>(cos(out) * 320.0, -200.0 - 280.0 * h, sin(out) * 320.0);
}
// A channel on the picture (hu_lin, hu_kink, hu_channel: the Supercell's), kinked at every scale, sharp bends, never smooth.
fn vc_lin(x: f32, s: f32) -> f32 {
    let i = floor(x);
    return mix(fh21(vec2<f32>(i, s)), fh21(vec2<f32>(i + 1.0, s)), x - i) * 2.0 - 1.0;
}
// (.x all of it, .y its large scales alone)
fn vc_kink(u: f32, s: f32, fq: f32) -> vec2<f32> {
    let v = u * fq;
    let big = 0.11 * vc_lin(v * 4.0, s) + 0.05 * vc_lin(v * 11.0, s + 1.7);
    return vec2<f32>(big + 0.024 * vc_lin(v * 29.0, s + 3.1) + 0.011 * vc_lin(v * 70.0, s + 5.3), big) / sqrt(fq);
}
fn vc_channel(px: vec2<f32>, sa: vec2<f32>, sb: vec2<f32>, s: f32, w: f32, pin: bool, fq: f32, jag: f32) -> vec3<f32> {
    let ab = sb - sa;
    let L = max(length(ab), 1.0);
    let dir = ab / L;
    let nrm = vec2<f32>(-dir.y, dir.x);
    let ap = px - sa;
    let u = clamp(dot(ap, dir) / L, 0.0, 1.0);
    let env = select(1.0, sqrt(max(1.0 - u, 0.0)) * 1.15, pin) * smoothstep(0.0, 0.04, u);
    let k0 = vc_kink(u, s, fq) * env * jag;
    let k1 = vc_kink(u + 0.002, s, fq).x * env * jag;
    let slope = (k1 - k0.x) / 0.002;
    let along = dot(ap, dir) - u * L;
    let off = (dot(ap, nrm) - k0.x * L) / sqrt(1.0 + slope * slope);
    let d = length(vec2<f32>(off, along));
    // (the bloom round its large scales only: the fine kinks, a row of pixels each, would comb it into stripes)
    let dg = length(vec2<f32>(dot(ap, nrm) - k0.y * L, along));
    let g = 1.0 / (1.0 + pow(dg / (w * 9.0), 2.0));
    return vec3<f32>(exp(-pow(d / w, 2.0)), g * g, u);
}
// How much is seen of what is `dm` off along the ray: hidden by the land (`near`) and the cloud (`ct` its distance, `ca`
// what shows through it), but a little through the ash just under the cloud's face.
fn vc_seen(dm: f32, near: f32, ct: f32, ca: f32) -> f32 {
    if (near < dm - 3.0) {
        return 0.0;
    }
    if (dm <= ct) {
        return 1.0;
    }
    return max(ca, VC_THRU * (1.0 - smoothstep(100.0, 900.0, dm - ct)));
}
// (a and b, camera-relative, brought in front of the eye: a bolt overhead has its root behind it)
fn vc_clip_w(p: vec3<f32>) -> f32 {
    return (frame.projection * (frame.view * vec4<f32>(p, 1.0))).w;
}
fn vc_near_end(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    let wa = vc_clip_w(a);
    let wb = vc_clip_w(b);
    if (wa >= 1.0 || wb <= wa) {
        return a;
    }
    return mix(a, b, (1.0 - wa) / (wb - wa));
}
// A jagged channel from a to b (camera-relative) on the picture, three forks off it (hu_bolt): x its core, y its bloom.
fn vc_bolt(px: vec2<f32>, a: vec3<f32>, b: vec3<f32>, seed: f32, near: f32, ct: f32, ca: f32) -> vec2<f32> {
    let pa = project_rel(a);
    let pb = project_rel(b);
    if (pa.z < 0.0 || pb.z < 0.0) {
        return vec2<f32>(0.0);
    }
    let res = frame.resolution.xy;
    let sa = pa.xy * res;
    let sb = pb.xy * res;
    let ab = sb - sa;
    let L = max(length(ab), 1.0);
    let la = length(a);
    let lb = length(b);
    let focal = res.y / (2.0 * tan(frame.view_params.w * 0.5));
    let w = clamp(VC_CHAN_W * focal / (0.5 * (la + lb)), 1.2, 4.0);
    let u0 = saturate(dot(px - sa, ab) / (L * L));
    if (length(px - (sa + ab * u0)) > 0.5 * L + 40.0 * w) {
        return vec2<f32>(0.0);
    }
    // (kinked for its length in blocks: this cloud's bolts run ten times the Hurricane's, so its scales are larger too)
    let fq = max(length(a - b) / VC_KINK_LEN, 1.0);
    var core = 0.0;
    var glow = 0.0;
    if (length(px - (sa + ab * u0)) < 0.2 * L + 40.0 * w) {
        let m = vc_channel(px, sa, sb, seed, w, true, fq, 1.35);
        let seen = vc_seen(mix(la, lb, m.z), near, ct, ca);
        core = m.x * seen * seen;
        glow = m.y * seen;
    }
    let dir = ab / L;
    let nrm = vec2<f32>(-dir.y, dir.x);
    for (var k = 0; k < 3; k = k + 1) {
        let fk = f32(k);
        let u = 0.15 + 0.55 * fract(seed * 0.618 + fk * 0.377);
        let root = sa + ab * u + nrm * vc_kink(u, seed, fq).x * sqrt(1.0 - u) * 1.15 * 1.35 * L;
        let side = select(-1.0, 1.0, fract(seed * 0.71 + fk * 0.53) > 0.5);
        let bdir = normalize(dir + nrm * side * (0.55 + 0.6 * fract(seed * 1.3 + fk * 0.7)));
        let lf = L * (0.16 + 0.26 * fract(seed * 0.9 + fk * 0.77));
        let end = root + bdir * lf;
        // (only near it: no fork's work over the whole of the bolt's box)
        let uf = saturate(dot(px - root, bdir) / lf);
        if (length(px - root - bdir * uf) > 0.22 * lf + 40.0 * w * 0.6) {
            continue;
        }
        let f = vc_channel(px, root, end, seed + 7.0 + fk * 3.3, w * 0.6, false, fq, 1.6);
        let fs = vc_seen(mix(la, lb, u), near, ct, ca) * pow(1.0 - f.z, 1.6);
        core = core + f.x * fs * fs;
        glow = glow + f.y * fs * 0.7;
    }
    return vec2<f32>(core, glow);
}
// The return stroke's column from a to b (camera-relative) on the picture (hu_beam): a thick soft rod of light, straight
// but for a gentle wave, drawn up off the land from `ue` (1: down to b, 0: none), its foot a point: x its core, y its halo.
fn vc_beam(px: vec2<f32>, a: vec3<f32>, b: vec3<f32>, seed: f32, ue: f32, near: f32, ct: f32, ca: f32) -> vec2<f32> {
    let pa = project_rel(a);
    let pb = project_rel(b);
    if (pa.z < 0.0 || pb.z < 0.0 || ue <= 0.01) {
        return vec2<f32>(0.0);
    }
    let res = frame.resolution.xy;
    let sa = pa.xy * res;
    let sb = pb.xy * res;
    let ab = sb - sa;
    let L = max(length(ab), 1.0);
    let dir = ab / L;
    let nrm = vec2<f32>(-dir.y, dir.x);
    let la = length(a);
    let lb = length(b);
    let focal = res.y / (2.0 * tan(frame.view_params.w * 0.5));
    let ap = px - sa;
    let u = clamp(dot(ap, dir) / L, 0.0, 1.0);
    let dm = mix(la, lb, u);
    let wc = max(VC_BEAM_R * focal / max(dm, 1.0), 1.4);
    let off0 = dot(ap, nrm);
    if (abs(off0) > 0.12 * L + 14.0 * wc) {
        return vec2<f32>(0.0);
    }
    // (a gentle wave, the large scales of the leader's kinks only)
    let wave = (0.03 * vc_lin(u * 3.0, seed) + 0.015 * vc_lin(u * 8.0, seed + 1.7)) * L * smoothstep(0.0, 0.05, u);
    let along = dot(ap, dir) - u * L;
    let d = length(vec2<f32>(off0 - wave, along));
    // (drawn up: thinning to a point at its foot)
    let taper = sqrt(saturate((ue - u) / 0.18)) * smoothstep(0.0, 0.03, u);
    let r = wc * taper;
    let seen = vc_seen(dm, near, ct, ca) * step(u, ue);
    let core = exp(-pow(d / max(r * 0.7, 0.6), 2.0)) * step(0.001, taper);
    let halo = 1.0 / (1.0 + pow(d / max(r * 2.2, 1.0), 2.0)) * taper;
    return vec2<f32>(core * seen, halo * halo) * seen;
}
// The bolts of the flashes under way, on the picture (hu_bolts): `near` how far the land is.
fn vc_bolts(fl: VcFlashes, C: vec3<f32>, seed: u32, near: f32, ct: f32, ca: f32, pxy: vec2<f32>) -> vec3<f32> {
    var c = vec3<f32>(0.0);
    for (var i = 0; i < 3; i = i + 1) {
        let f = fl.f[i];
        if (f.kind == 0u) {
            continue;
        }
        let dv = vc_flash_way(f, seed);
        var root = f.p;
        if (f.kind == 2u && f.ring > 0.5) {
            // (along under the sheet, out of the cloud: its underside as vc_umb has it)
            let r = length(f.p.xz);
            root.y = VC_HU - 0.9 * (210.0 + 240.0 * exp(-r * r / 1.44e6)) - 230.0 * exp(-r * r / 6.4e5) - 30.0;
        }
        let a = f.a;
        let n = f.n;
        let s0 = f32(pcg(u32(f.id) ^ seed) & 1023u) * 0.37;
        var tip = C + root + dv;
        var lk = vc_lead_k(a, n);
        var shape = f32(u32(a * 30.0));
        if (f.kind == 2u) {
            // (a channel alone: one shape from the leader's on, it stands while a return stroke would)
            lk = max(lk, vc_beam_k(a, n));
            shape = select(0.0, shape, a < VC_LEAD || a > 0.27);
        } else if (a > VC_LEAD && (n & 16u) != 0u) {
            // (a re-stroke now and then across the cloud instead, out of the root sideways)
            let side = normalize(vec3<f32>(-root.z, 0.0, root.x)) * select(-1.0, 1.0, (n & 32u) != 0u);
            tip = C + root + side * (340.0 + 260.0 * f32((n >> 6u) & 7u) / 7.0) - vec3<f32>(0.0, 120.0, 0.0);
        }
        let top = vc_near_end(C + root, tip);
        if (lk > 0.0) {
            let m = vc_bolt(pxy, top, tip, s0 + shape * 5.3, near, ct, ca);
            c = c + (vec3<f32>(1.0, 0.98, 1.0) * m.x * 2.4 + vec3<f32>(0.62, 0.6, 1.0) * m.y * 0.6) * lk;
        }
        if (f.kind == 1u) {
            // (the return stroke's column)
            let bk = vc_beam_k(a, n);
            if (bk > 0.0) {
                let ue = 1.0 - smoothstep(0.17, 0.27, a);
                let m = vc_beam(pxy, top, C + root + dv, s0, ue, near, ct, ca);
                c = c + (vec3<f32>(1.0, 0.98, 1.0) * m.x * 3.0 + vec3<f32>(0.66, 0.64, 1.0) * m.y * 1.1) * bk;
            }
        }
    }
    return c;
}
// A bolt's column lighting the land round its foot (`q` off the vent: hu_flash_at).
fn vc_flash_land(fl: VcFlashes, q: vec3<f32>, seed: u32) -> f32 {
    var e = 0.0;
    for (var i = 0; i < 3; i = i + 1) {
        let f = fl.f[i];
        if (f.kind == 1u) {
            let k = vc_beam_k(f.a, f.n) + 0.4 * vc_lead_k(f.a, f.n);
            let d = q - f.p - vc_flash_way(f, seed);
            e = e + 2.4 * k / (1.0 + dot(d, d) / VC_FOOT_R2);
        }
    }
    return e;
}

// ---- what hangs in the air round the eye: flakes of ash coming down, embers driven past (as the Hurricane's rain: strung
// along lines the way they move, the lines' feet on a grid across it, layers out from the eye on coarser grids) ----
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

// ---- the march ----
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
// Fire by temperature (0 to 1): a dull red, orange, yellow-white, as a flame's light.
fn vc_fire_c(T: f32) -> vec3<f32> {
    let a = mix(vec3<f32>(0.0), vec3<f32>(0.5, 0.05, 0.008), saturate(T * 3.2));
    let b = mix(a, vec3<f32>(1.25, 0.3, 0.035), saturate(T * 3.0 - 0.8));
    return mix(b, vec3<f32>(3.0, 1.75, 0.5), saturate(T * 2.2 - 1.05));
}
// How hot the smoke is at q, 0 to 1 (`top` how far up a dome it is): pockets of fire flaring and dying where a broad
// noise lets them, in the creases more than on the crowns; all of the blast at first, then (`old`) only low down near the
// vents as it cools into grey-brown ash. .y the broad glow round them, what the smoke nearby is lit by.
fn vc_heat(q: vec3<f32>, hy: f32, top: f32) -> vec2<f32> {
    let a = vs.a;
    if (a <= 0.0 || vs.c > 14.0) {
        return vec2<f32>(0.0);
    }
    // (how high it burns: nearly all the blast, then sinking to the column's foot, in to the vents)
    let old = smoothstep(10.0, 24.0, a);
    let hf = mix(0.62 * vs.Hd, 0.5 * min(vs.H, 1500.0), smoothstep(5.0, 15.0, a)) * mix(1.0, 0.2, old);
    var zone = (1.0 - smoothstep(0.45 * hf, 1.2 * hf, hy)) * (1.0 - smoothstep(4.0, 14.0, vs.c));
    if (a > 10.0) {
        zone = zone * (1.0 - smoothstep(10.0, 16.0, a) * smoothstep(VC_RING, VC_RING + 380.0, length(q.xz)));
    }
    if (zone <= 0.0) {
        return vec2<f32>(0.0);
    }
    let qf = q - vec3<f32>(0.0, 44.0 * vs.t, 0.0);
    let n1 = vc_gn3(VC_R1 * qf * (1.0 / 230.0) + vec3<f32>(0.0, 0.0, 0.14 * vs.t));
    let n2 = vc_gn3(VC_R2 * qf * (1.0 / 84.0) + vec3<f32>(1.7, 0.21 * vs.t, 0.0));
    let gate = vc_gn3(vec3<f32>(q.x, 0.5 * q.y, q.z) * (1.0 / 560.0) + vec3<f32>(0.0, -0.05 * vs.t, 0.19 * vs.t));
    let n = 0.6 * n1 + 0.4 * n2 + 0.42 * (gate - 0.5);
    let cool = smoothstep(1.5, 11.0, a);
    let thr = mix(0.5, 0.565, cool);
    let T = smoothstep(thr, thr + 0.1, n) * zone;
    // (tongues of flame in it, drawn up, soot between them: never a flat fill)
    let n3 = vc_gn3(VC_R3 * (q * vec3<f32>(1.0 / 26.0, 1.0 / 58.0, 1.0 / 26.0) - vec3<f32>(0.0, 2.0 * vs.t, 0.0)));
    let tongues = saturate(0.2 + 2.1 * (0.7 * n3 + 0.3 * n2) - 0.45);
    // (a crown's skin cools first: the fire shows between the lumps; less so while the blast is young)
    let cr = 1.0 - top;
    let skin = mix(mix(0.3 + 1.1 * cr * cr, 0.2 + 1.3 * cr * cr, cool), 1.5 * cr * cr, old);
    let hot = (0.8 - 0.16 * cool) * (0.5 + 0.75 * n1);
    let far = 1.0 - 0.7 * smoothstep(14.0, 28.0, a);
    return vec2<f32>(1.2 * pow(saturate(T * skin) * hot * tongues, 1.35 + 0.7 * old), mix(0.5, 1.0, cool) * smoothstep(0.46, 0.74, 0.7 * n1 + 0.5 * (gate - 0.2)) * zone * mix(1.0, zone, cool) * far * (0.45 + 0.9 * tongues));
}
// The air's colour along a ray: the sky's, gone dirty and red low down as the sheet closes over.
fn vc_band(rd: vec3<f32>) -> vec3<f32> {
    let e = saturate(rd.y * 3.2);
    return mix(vec3<f32>(0.46, 0.195, 0.08), vec3<f32>(0.16, 0.056, 0.03), smoothstep(0.0, 1.0, e));
}
fn vc_haze(rd: vec3<f32>, l: VcLight) -> vec3<f32> {
    let lum = dot(l.skyl, vec3<f32>(0.2126, 0.7152, 0.0722));
    return mix(l.haze, vec3<f32>(lum) * vc_band(rd), smoothstep(0.1, 0.7, vs.cov));
}
fn vc_march(C: vec3<f32>, rd: vec3<f32>, tmax: f32, j: f32, l: VcLight, fls: VcFlashes) -> VcMarch {
    var o: VcMarch;
    o.c = vec3<f32>(0.0);
    o.tr = 1.0;
    o.t = 1.0e9;
    vc_tk = vec4<f32>(1.0e9);
    vc_tx = vec2<f32>(1.0);
    vc_cm = 1.0;
    let t_end = min(tmax, 32000.0);
    let time = vs.t;
    if (time < VC_ERUPT + 0.9) {
        return o;
    }
    var t = 0.0;
    var tsun = 1.0;
    var ao = 1.0;
    var rim = 0.0;
    var below = 0.0;
    var inband = false;
    var face = 1.0;
    vc_cq = vec4<f32>(1.0e7);
    vc_cs = 0.0;
    var hs = pcg(u32(vc_px.x) ^ (u32(vc_px.y) << 13u) ^ (u32(fract(time * 7.0) * 1024.0) << 3u));
    var wmid = 0.0;
    var tmid = 0.0;
    // (the brightest flash lights the cloud: one, so the march keeps little in hand)
    var gl = fls.f[0];
    if (fls.f[1].k > gl.k) {
        gl = fls.f[1];
    }
    if (fls.f[2].k > gl.k) {
        gl = fls.f[2];
    }
    let gw = vc_flash_way(gl, l.seed);
    let gw2 = max(dot(gw, gw), 1.0);
    let ph = 0.75 + (0.45 + 1.3 * l.warm) * pow(saturate(dot(rd, l.L)), 5.0);
    // (two runs of one loop, the look at the light between them: a GPU's group pays for a branch at any step any of its
    // pixels takes it, and lasts as long as its slowest. Out here it looks once)
    var i = 0;
    var lq = vec3<f32>(0.0);
    var lb: VcB;
    var lsd = vec4<f32>(0.0);
    var lfoot = 0.0;
    for (var leg = 0; leg < 2; leg = leg + 1) {
    var look = false;
    for (; i < 132; i = i + 1) {
        if (t > t_end || o.tr < 0.05) {
            break;
        }
        let p = rd * t;
        let q = p - C;
        var b = vc_base(q);
        let foot = t * vs.px * vs.fine;
        if (b.d > VC_DM + 12.0) {
            let s = vc_skip(q, rd, &b);
            inband = false;
            if (s > 20.0) {
                t = t + s * 0.97;
                // (going away from everything: nothing more on this ray)
                if (s > 1.0e5) {
                    break;
                }
                continue;
            }
            t = t + max((b.d - VC_DM) * 0.6, 8.0);
            inband = false;
            continue;
        }
        // (every stride jittered by white noise, the first into the band too: a stride that lands alike from pixel to pixel
        // slices the smoke into contours, and a pattern of jitter shows as a halftone over thin smoke)
        hs = pcg(hs + u32(i));
        let jt = f32(hs & 0xffffu) / 65535.0;
        if (!inband) {
            inband = true;
            t = t + jt * max(4.0, t * 0.0034);
            continue;
        }
        let st = VC_ST * max(4.0, t * 0.0034) * (0.7 + 0.6 * jt) * (1.0 + 3.0 * vs.thin);
        // (still well off the surface: one set of the big lumps is enough to step by)
        if (b.d > 50.0) {
            let sc = vc_sdf(q, &b, foot, false).x;
            if (sc > 80.0) {
                t = t + 0.5 * (sc - 50.0);
                continue;
            }
        }
        let steam = (1.0 - smoothstep(-0.6, 0.0, vs.a)) * step(b.dc, min(b.df, b.du));
        // (the wall of ash torn into rolling banks behind its head, rolling past as it comes on, thinning to nothing a few
        // seconds behind the front, all but the clouds lifting off it)
        var ext = 0.15;
        var wb = 0.0;
        var torn = 1.0;
        if (b.df < 40.0) {
            let dir = q.xz / max(b.rho, 1.0);
            let hb = q.y - b.land;
            let qb = vec3<f32>(q.x - dir.x * vs.rf * 1.6, hb * 1.25 - 26.0 * time, q.z - dir.y * vs.rf * 1.6);
            let bank = 0.62 * vc_gn3(qb * (1.0 / 150.0) + vec3<f32>(0.0, 0.0, 0.11 * time)) + 0.38 * vc_gn3(VC_R2 * qb * (1.0 / 58.0));
            // (its head solid to the land; torn into banks, lifted off it, only behind)
            wb = smoothstep(40.0, 200.0, b.e);
            // (the ash lifting clear: the air under it empties, the land shows, a rolling ceiling over it)
            let lf = smoothstep(VC_LIFT - 8.0, VC_LIFT + 6.0, time) * smoothstep(150.0, 520.0, b.e);
            let base = lf * (250.0 + 340.0 * (bank - 0.5));
            let lifted = lf * smoothstep(180.0, 420.0, hb);
            let th = mix(mix(0.36, 0.56, smoothstep(40.0, 560.0, b.e)), 0.36, lifted);
            torn = smoothstep(base - 40.0, base + 110.0, hb + 150.0 * (1.0 - wb)) * mix(1.0, smoothstep(th - 0.08, th + 0.2, bank), wb);
            ext = mix(0.15, 0.05, wb);
            // (the air the wall has emptied)
            if (torn <= 0.0) {
                t = t + max(st * VC_ST_AIR, 14.0);
                continue;
            }
        }
        var den = 0.0;
        var sd = vec4<f32>(b.d, 0.5, 8.0, 0.5);
        if (b.d < -VC_DM - 8.0) {
            den = 1.0;
        } else {
            sd = vc_sdf(q, &b, foot, true);
            // (the smoke's edge crisp over a crown, loose and wispy in the creases; frayed where it is thin)
            let edge = mix(36.0, 9.0, saturate(sd.y * 1.25)) + foot * 1.6 + 160.0 * vs.thin;
            let ramp = saturate(-sd.x / edge);
            den = ramp * mix(saturate(0.22 + 1.5 * sd.w), 1.0, ramp);
        }
        den = den * torn;
        if (steam > 0.0) {
            ext = mix(ext, 0.016, steam);
        }
        if (den > 1.0e-4) {
            let hy = q.y;
            let hyl = hy - select(0.0, vc_land(q.xz), hy < 600.0);
            if (leg == 0) {
                look = true;
                lq = q;
                lb = b;
                lsd = sd;
                lfoot = foot;
                break;
            }
            // ---- its colour: charcoal and umber, pale steam over the blast, paler on the umbrella's top and the flows ---
            let wc = saturate(1.0 + (min(b.du, b.df) - b.dc) / 70.0);
            let wf = saturate(1.0 + (min(b.dc, b.du) - b.df) / 70.0);
            // (the sheet takes on its own colours as it spreads, out of the column's)
            let wu = saturate(1.0 + (min(b.dc, b.df) - b.du) / 70.0) * smoothstep(VC_SPREAD + 1.0, VC_SPREAD + 6.0, time);
            let mott = vc_gn3(q * (1.0 / 380.0) + vec3<f32>(3.0, -0.03 * time, 1.0));
            var alb = mix(vec3<f32>(0.075, 0.066, 0.06), vec3<f32>(0.2, 0.172, 0.15), smoothstep(0.3, 0.72, mott));
            // (a head of steam and pale ash riding the top of what is rising, going dark as it climbs and mixes)
            let crown = smoothstep(0.55 * vs.H - 40.0, 0.92 * vs.H, hy) * (1.0 - smoothstep(9.0, 23.0, vs.a)) * smoothstep(0.34, 0.6, mott + 0.3 * sd.y);
            alb = mix(alb, vec3<f32>(0.5, 0.48, 0.46), crown * step(0.0, vs.a));
            // (the sheet's sunlit top pale, as ash spread thin; its underside as dark as the column)
            alb = mix(alb, mix(vec3<f32>(0.115, 0.1, 0.09), vec3<f32>(0.25, 0.225, 0.2), smoothstep(VC_HU - 40.0, VC_HU + 180.0, hy)) * (0.8 + 0.4 * mott), wu);
            alb = mix(alb, vec3<f32>(0.115, 0.1, 0.092) * (0.72 + 0.56 * mott), wf);
            alb = mix(alb, vec3<f32>(0.75, 0.74, 0.72), steam);
            alb = alb * mix(1.0, 0.42, wc * (1.0 - smoothstep(0.35 * vs.H, 0.8 * vs.H, hy)) * (1.0 - crown));
            let sk = vc_sky_t(q);
            let sk_l = dot(l.skyl, vec3<f32>(0.2126, 0.7152, 0.0722));
            // (the sky's light, and under the sheet the brown light that gets in round its edge)
            let skyg = mix(mix(l.skyl, vec3<f32>(sk_l), 0.7), vec3<f32>(sk_l) * vec3<f32>(1.0, 0.72, 0.52), vs.cov);
            var c = alb * (skyg * (0.06 + 0.66 * ao) * (0.03 + 0.97 * sk * sk) + (l.sunc * (1.5 * tsun * ph) + vec3<f32>(0.9, 0.55, 0.32) * sk_l * rim * vs.cov * 0.8 * saturate(0.25 + 1.2 * b.rho / vs.Ru)) * face * mix(0.78, 1.12, sd.y));
            // ---- fire: pockets low in it, the smoke round them lit by them and from below ----
            let on = smoothstep(0.0, 0.4, vs.a);
            let ht = vc_heat(q, hyl, sd.y);
            var fire = vec3<f32>(0.0);
            if (ht.x > 0.0) {
                fire = vc_fire_c(ht.x) * on;
                // (fire under the skin outshines what falls on it)
                c = c * (1.0 - saturate(ht.x * 2.5));
            }
            // (the light of the fire on the smoke round it)
            let ash = min(alb, vec3<f32>(0.13));
            let cr = 1.0 - sd.y;
            c = c * (1.0 - 0.62 * ht.y * on);
            fire = fire + ash * vec3<f32>(2.5, 0.95, 0.15) * ht.y * (0.3 + 0.7 * cr) * on;
            // (from under: the land burning below what hangs over it)
            let fb = (1.0 - smoothstep(VC_COLLAPSE, VC_COLLAPSE + 6.0, time)) * on;
            fire = fire + ash * vec3<f32>(1.5, 0.42, 0.07) * below * below * (0.3 + 0.7 * cr) * exp(-max(hyl, 0.0) / 300.0) * fb;
            // (the vents' glow on the column's foot, fading with height)
            if (vs.a > 10.0 && time < VC_LIFT) {
                fire = fire + ash * vec3<f32>(4.0, 1.0, 0.16) * exp(-max(hyl, 0.0) / 130.0) * (1.0 - smoothstep(VC_RING, VC_RING + 520.0, b.rho)) * smoothstep(10.0, 18.0, vs.a) * (1.0 - smoothstep(VC_COLLAPSE, VC_LIFT, time)) * (0.4 + 0.6 * cr);
            }
            if (b.e > -60.0) {
                // (the flows, close behind the front and low down: the hot base of the cloud showing in its creases; inside the
                // wall, the banks lit red from under by what they have laid down)
                let h = hy - b.land;
                fire = fire + ash * vec3<f32>(1.5, 0.36, 0.09) * wb * (0.03 + exp(-max(h, 0.0) / 70.0)) * (1.0 - smoothstep(VC_LIFT, VC_RED, time));
                let crease = (1.0 - sd.y) * (1.0 - sd.y);
                let ember = exp(-max(h, 0.0) / 26.0) * (1.0 - smoothstep(380.0, 1400.0, b.rho)) * exp(-max(b.e, 0.0) / 170.0) * smoothstep(40.0, 200.0, t);
                fire = fire + vec3<f32>(1.0, 0.2, 0.03) * ember * crease * 1.6 * wf;
            }
            // (the sheet's underside: the fire's dull red on it round the column, its pouches catching it)
            if (wu > 0.0 && hy < VC_HU) {
                let gl = exp(-b.rho / 1100.0) * (0.15 + 0.85 * sd.y * sd.y) * (1.0 - smoothstep(VC_COLLAPSE + 2.0, VC_LIFT, time));
                fire = fire + vec3<f32>(0.2, 0.045, 0.01) * gl * smoothstep(0.0, 6.0, vs.a) * wu;
            }
            c = c + fire;
            // (the lightning in it: along its channel, lighting the cloud a long way round)
            var lg = 0.0;
            if (gl.k > 0.02) {
                let dd = q - gl.p - gw * saturate(dot(q - gl.p, gw) / gw2);
                lg = gl.k / (1.0 + dot(dd, dd) / (340.0 * 340.0));
            }
            c = c + (min(alb, vec3<f32>(0.2)) * 3.4 + 0.012) * vec3<f32>(0.72, 0.72, 1.0) * lg * 2.4;
            let al = 1.0 - exp(-den * ext * st);
            o.c = o.c + o.tr * al * c;
            tmid = tmid + o.tr * al * t;
            wmid = wmid + o.tr * al;
            o.tr = o.tr * (1.0 - al);
            vc_tk = min(vc_tk, select(vec4<f32>(1.0e9), vec4<f32>(t), vec4<f32>(o.tr) < vec4<f32>(0.9, 0.6, 0.3, 0.1)));
        }
        t = t + select(st, max(0.65 * sd.x, st * (0.5 + 0.03 * f32(i))), sd.x > 0.0);
    }
    if (!look) {
        break;
    }
    {
        let q = lq;
        var b = lb;
        let sd = lsd;
        let foot = lfoot;
        let hy = q.y;
        let hyl = hy - select(0.0, vc_land(q.xz), hy < 600.0);
            // (the light: looks on the way to the sun through the lumps, close and further, then through the bulk of the
            // cloud; in the sheet's shadow what light there is comes in low from the open sky round its edge)
            let st0 = vc_sun_t(q, l.L);
            let Lr = normalize(vec3<f32>(q.x, -0.4 * b.rho, q.z));
            let Lf = normalize(mix(Lr, l.L, smoothstep(0.15, 0.75, st0)));
            let f1q = q + Lf * 24.0;
            var fb1 = vc_base(f1q);
            let f1 = vc_sdf(f1q, &fb1, 40.0, false).x;
            let f2q = q + Lf * 78.0;
            var fb2 = vc_base(f2q);
            let f2 = vc_sdf(f2q, &fb2, 40.0, false).x;
            let o1 = saturate(0.5 - f1 / 40.0);
            let o2 = saturate(0.5 - f2 / 74.0);
            // (the sheet's underside, in its own shadow, needs no looks at the bulk: most of what fills the sky)
            let under = b.du < min(b.dc, b.df) && hy < VC_HU && st0 < 0.3;
            var s3 = 0.0;
            var s4 = 0.0;
            if (!under) {
                s3 = saturate((10.0 - vc_dist(q + Lf * 240.0)) / 120.0);
                s4 = saturate((10.0 - vc_dist(q + Lf * 560.0)) / 260.0);
            }
            let tau = 1.35 * o1 + 1.9 * o2 + 2.2 * s3 + 2.6 * s4;
            let lit = exp(-tau);
            // (and close to, the small lumps' own faces: which side of each looks at the light)
            face = 1.0;
            if (foot < 24.0) {
                let rs = sd.x + 40.0;
                face = 0.7 + 0.62 * saturate(0.5 - (vc_fine(q + Lf * 11.0, rs, foot).x - vc_fine(q, rs, foot).x) / 40.0);
            }
            tsun = lit * st0 * (1.0 - 0.5 * l.warm);
            rim = lit * (1.0 - smoothstep(0.15, 0.75, st0));
            // (the sky's light shut out from under what hangs over it and deep in it)
            let occ = select(saturate((10.0 - vc_dist(q + vec3<f32>(0.0, 190.0, 0.0))) / 150.0), 1.0, under);
            let deep = saturate(-sd.x / 90.0);
            ao = (0.4 + 0.6 * sd.y * sd.y) * (1.0 - 0.72 * occ) * (1.0 - 0.6 * deep);
            // (and open below it? the fire over the land lights what looks down on it)
            below = 0.0;
            if (hyl < 700.0 && time < VC_COLLAPSE + 6.0) {
                let dq = q - vec3<f32>(0.0, 46.0, 0.0);
                var db = vc_base(dq);
                below = saturate((vc_sdf(dq, &db, 40.0, false).x - vc_sdf(q, &b, 40.0, false).x + 6.0) / 64.0);
            }
    }
    }
    // (out of steps under the sheet, rising to it: it is met, so far off it is the haze. Else bands where steps ran out)
    let qe = rd * t - C;
    if (vs.Ru > 10.0 && i >= 132 && o.tr > 0.05 && rd.y > 0.0 && qe.y < VC_HU - 190.0) {
        let th = t + (VC_HU - 190.0 - qe.y) / rd.y;
        let k = o.tr * (1.0 - smoothstep(0.75 * vs.Ru, vs.Ru, length((rd * th - C).xz))) * (1.0 - smoothstep(0.7 * t_end, t_end, th));
        o.c = o.c + k * vc_haze(rd, l) * 0.75;
        tmid = tmid + k * th;
        wmid = wmid + k;
        o.tr = o.tr - k;
    }
    // (what the march left of the land behind it, once it stopped for being nearly opaque, is nothing)
    o.tr = saturate((o.tr - 0.051) / 0.949);
    // (thinning at the end: all of it lets the light through, more here and there, red as it goes; thinned in the
    // density, a cloud this deep would stay opaque, then clear along a hard edge)
    if (vs.thin > 0.0 && o.tr < 0.999) {
        let g = 0.6 * vc_gn3(rd * 2.3 + vec3<f32>(0.0, 0.0, time * 0.03)) + 0.4 * vc_gn3(VC_R1 * rd * 6.1 + vec3<f32>(time * 0.05));
        let x = 1.0 - smoothstep(0.0, 1.0, vs.thin * 1.2 + 0.55 * (g - 0.5) - 0.1);
        o.c = mix(o.c, vec3<f32>(0.1, 0.04, 0.026) * (1.0 - o.tr) * (0.2 + 0.8 * l.sun_up), 0.75 * vs.thin) * x;
        o.tr = 1.0 - (1.0 - o.tr) * x;
        vc_tx.x = x;
    }
    vc_tx.y = o.tr;
    if (o.tr < 0.999) {
        let dist = tmid / max(wmid, 1.0e-4);
        if (o.tr < 0.6) {
            o.t = dist;
        }
        // (the air's haze over it)
        let ap = 1.0 - exp(-max(dist - 1600.0, 0.0) / mix(9000.0, 1900.0, vs.cov));
        o.c = mix(o.c, vc_haze(rd, l) * (1.0 - o.tr), ap * mix(0.8, 1.0, vs.cov));
    }
    return o;
}

// The dust the shock lifts off the land: a thin low haze behind the pressure ring, three looks where the ray crosses it.
fn vc_dust(C: vec3<f32>, rd: vec3<f32>, tend: f32, col0: vec3<f32>, l: VcLight) -> vec3<f32> {
    let a = vs.a;
    let Rs = VC_RING + VC_V * a;
    let w = 46.0 + 0.2 * (Rs - VC_RING);
    let h = (18.0 + 14.0 * a) * (1.0 - smoothstep(VC_DUST - 4.0, VC_DUST, a));
    let o = -C.xz;
    let d = rd.xz;
    let aa = max(dot(d, d), 1.0e-6);
    let bq = dot(o, d) / aa;
    let oo = dot(o, o);
    let disc = bq * bq - (oo - Rs * Rs) / aa;
    if (disc <= 0.0) {
        return col0;
    }
    // (the air over the land the ray is in, and the ring's stretch of it, the near one if the ray is low enough there)
    let ry = select(1.0e-4, rd.y, abs(rd.y) > 1.0e-4);
    let y0 = -C.y;
    let t_a = (-14.0 - y0) / ry;
    let t_b = (h + 26.0 - y0) / ry;
    let lo = max(min(t_a, t_b), 0.0);
    let hi = min(max(t_a, t_b), tend);
    let sq = sqrt(disc);
    let Ri = max(Rs - 2.6 * w, 1.0);
    let di = bq * bq - (oo - Ri * Ri) / aa;
    let si = sqrt(max(di, 0.0));
    var ta = max(lo, -bq - sq);
    var tb = min(hi, select(-bq + sq, -bq - si, di > 0.0));
    if (tb <= ta && di > 0.0) {
        ta = max(lo, -bq + si);
        tb = min(hi, -bq + sq);
    }
    if (tb <= ta) {
        return col0;
    }
    let jt = f32(pcg(u32(vc_px.x) ^ (u32(vc_px.y) << 13u)) & 1023u) / 1023.0;
    let ds = (tb - ta) / 3.0;
    let lum = dot(l.skyl, vec3<f32>(0.2126, 0.7152, 0.0722));
    let tan_ = vec3<f32>(0.62, 0.55, 0.46) * (0.62 * lum + 0.5 * dot(l.sunc, vec3<f32>(0.33)));
    var col = col0;
    for (var i = 0; i < 3; i = i + 1) {
        let p = rd * (ta + (f32(i) + jt) * ds) - C;
        let v = (p.y - vc_land(p.xz)) / h;
        let u = (Rs - length(p.xz)) / w;
        let n = vc_gn3(vec3<f32>(p.x, p.y * 2.0 - 40.0 * a, p.z) * (1.0 / 95.0));
        let n2 = vc_gn3(VC_R1 * p * (1.0 / 340.0));
        let den = exp(-u * 1.1) * smoothstep(0.0, 0.2, u) * step(-0.2, v) * (1.0 - smoothstep(0.25, 1.0, v + 0.5 * (n - 0.5))) * smoothstep(0.34, 0.68, 0.5 * n + 0.5 * n2);
        col = mix(col, tan_, (1.0 - exp(-den * ds * 0.0055)) * (1.0 - smoothstep(4.0, VC_DUST, a) * 0.6) * smoothstep(60.0, 420.0, length(p + C)));
    }
    return col;
}
// The shock seen for a moment: a torn veil of condensation at the pressure ring's speed, two fainter behind, its amount
// from where the ray passes closest, so no line runs round it.
fn vc_shells(C: vec3<f32>, rd: vec3<f32>, tend: f32, col0: vec3<f32>, l: VcLight) -> vec3<f32> {
    var col = col0;
    let sy = 1.16;
    let o = vec3<f32>(-C.x, -C.y * sy, -C.z);
    let d = vec3<f32>(rd.x, rd.y * sy, rd.z);
    let aa = dot(d, d);
    let tca = -dot(o, d) / aa;
    let pc = o + d * tca;
    let b2 = dot(pc, pc);
    let b = sqrt(b2);
    let lum = dot(l.skyl, vec3<f32>(0.2126, 0.7152, 0.0722));
    let veil = vec3<f32>(0.9, 0.89, 0.87) * (0.55 * lum + 0.55 * dot(l.sunc, vec3<f32>(0.33)));
    for (var k = 0; k < 3; k = k + 1) {
        let born = 0.25 + 0.8 * f32(k);
        let s = vs.a - born;
        if (s <= 0.0 || s > 5.5) {
            continue;
        }
        let R = VC_RING + VC_V * s;
        let w = 12.0 + 0.03 * R;
        let in2 = R * R - b2;
        let hc = sqrt(max(in2, 0.0) / aa);
        var th = tca - hc;
        if (th <= 0.0) {
            th = tca + hc;
        }
        if (th <= 0.0 || th > tend) {
            continue;
        }
        let p = o + d * th;
        let dir = p / max(length(p), 1.0);
        let n = vc_gn3(dir * 5.0 + vec3<f32>(0.0, 0.14 * s, 1.7 * f32(k)));
        let n2 = vc_gn3(VC_R1 * dir * 15.0 + vec3<f32>(0.0, 0.0, 0.3 * s));
        let x = (b - R * (1.0 + 0.05 * (n - 0.5))) / w;
        let past = exp(-pow(max(x, 0.0), 2.0));
        let along = sqrt(R / (2.0 * w)) / sqrt(1.0 + max(-x, 0.0));
        let patch_ = smoothstep(0.4, 0.76, 0.68 * n + 0.32 * n2);
        let life = smoothstep(0.1, 0.7, s) * (1.0 - smoothstep(1.8, 5.5, s)) * (1.0 - 0.34 * f32(k));
        let al = saturate(0.075 * along * past * patch_ * life * smoothstep(0.03, 0.3, dir.y));
        col = mix(col, veil, al);
    }
    return col;
}

// ---- the opening: a small orbital laser over the vent, its targeting beam, the beam, the hole it melts ----
// The satellite hangs in orbit, 7,000 up and 1,600 beyond the vent from where the player fired (table words 2 and 3: the
// way to them), some 70 degrees up their sky, high over the vent, drifting along its orbit; drawn bigger the further off it is
// seen (`vc_sat_k`), so it reads as a machine from wherever they are. It aims a thin opaque red beam (VC_AIM), its spot
// wandering onto the vent and locking (VC_LOCK); its emitter charges and fires (VC_HIT): a white-hot beam that melts a
// clean round hole (VC_HR) down through the crust, cut at VC_OFF; the hole glows on, its rim cooling to crust, steam off
// it, and the mount rises round it (its land spread by vm_rest) until the eruption comes out of it.
const VC_AIM: f32 = 0.6;
const VC_LOCK: f32 = 1.5;
const VC_OFF: f32 = 4.6;
const VC_HR: f32 = 14.0;
const VC_SAT_END: f32 = 9.5;
fn vc_sat() -> vec3<f32> {
    var d = vec2<f32>(vc_w(2u), vc_w(3u));
    if (dot(d, d) < 0.5) {
        d = normalize(vc_me() + vec2<f32>(1.0e-3, 0.0));
    }
    let s = -1600.0 * d + vec2<f32>(-d.y, d.x) * 16.0 * (vs.t - 3.0);
    return vec3<f32>(s.x, 7000.0, s.y);
}
// How much bigger than itself it is drawn, seen from `P` off: as big as it would look from 2,400 (from 1,900 at the most).
fn vc_sat_k(P: vec3<f32>) -> f32 {
    return clamp(length(P) / 2400.0, 1.0, 4.0);
}
// Where the targeting spot is (level, from the vent): wandering in to the vent and still from VC_LOCK.
fn vc_spot() -> vec2<f32> {
    let w = pow(1.0 - smoothstep(VC_AIM, VC_LOCK, vs.t), 1.5);
    let t = vs.t;
    return vec2<f32>(sin(t * 3.1 + 0.4) + 0.6 * sin(t * 7.3), cos(t * 2.7 + 1.3) + 0.5 * sin(t * 6.1 + 2.0)) * 26.0 * w;
}
// The hole's radius now, in the land's own (rest) frame, and how hot it is (1 while the beam is on, the rim cooling after).
fn vc_hole_r() -> f32 {
    return VC_HR * pow(smoothstep(VC_HIT, VC_HIT + 1.6, vs.t), 0.6);
}
// A box `h` (half sizes) round the origin of a frame, the ray o + d s in it: .x where it is met (under 0: missed), .yzw
// the face's normal.
fn vc_box(o: vec3<f32>, d: vec3<f32>, h: vec3<f32>) -> vec4<f32> {
    let iv = 1.0 / select(d, vec3<f32>(1.0e-6), abs(d) < vec3<f32>(1.0e-6));
    let t0 = (-h - o) * iv;
    let t1 = (h - o) * iv;
    let tn = min(t0, t1);
    let tf = max(t0, t1);
    let a = max(max(tn.x, tn.y), tn.z);
    if (a > min(min(tf.x, tf.y), tf.z) || a < 0.0) {
        return vec4<f32>(-1.0);
    }
    return vec4<f32>(a, -sign(d) * step(tn.yzx, tn) * step(tn.zxy, tn));
}
// The land, under its light: the targeting spot and its reticle, the hole (its far wall seen down it, white-hot deep in
// it), its molten rim cooling to crust, the land round it scorched and lit by it. `q` where the ray meets the land, `o`
// the eye (both from the vent).
fn vc_open_land(c0: vec3<f32>, q: vec3<f32>, rd: vec3<f32>, o: vec3<f32>) -> vec3<f32> {
    let t = vs.t;
    var c = c0;
    if (t < VC_AIM || t > VC_ERUPT + 0.5 || abs(q.y) > 600.0) {
        return c;
    }
    if (t < VC_HIT) {
        let e = length(q.xz - vc_spot());
        let on = smoothstep(VC_AIM + 0.1, VC_AIM + 0.2, t);
        if (e > 13.0) {
            return c + c0 * vec3<f32>(1.0, 0.1, 0.05) * 1.2 * on / (1.0 + e * e / 30.0);
        }
        let lk = smoothstep(VC_LOCK - 0.1, VC_LOCK + 0.15, t);
        let ring = mix(11.0, 5.5, lk);
        let ang = atan2(q.z, q.x) + t * mix(1.5, 0.0, lk);
        let ticks = step(0.7, fract(ang * 4.0 / TAU + 0.35)) * (1.0 - lk) + lk;
        let blink = mix(1.0, 0.6 + 0.4 * step(0.5, fract(t * 7.0)), lk);
        let red = vec3<f32>(1.6, 0.08, 0.04);
        c = mix(c, red, (1.0 - smoothstep(1.4, 2.2, e)) * on);
        c = mix(c, red, (1.0 - smoothstep(0.35, 0.8, abs(e - ring))) * ticks * on * blink);
        c = c + c0 * vec3<f32>(1.0, 0.1, 0.05) * 1.2 * on / (1.0 + e * e / 30.0);
        return c;
    }
    // (in the land's own frame: the mount spreads it as it grows)
    var rq = q.xz;
    if (vm.on) {
        rq = vm_rest(rq);
    }
    let r = length(rq);
    let R = vc_hole_r();
    let fire = smoothstep(VC_HIT, VC_HIT + 0.05, t) * (1.0 - smoothstep(VC_OFF, VC_OFF + 0.1, t));
    let cool = smoothstep(VC_OFF, VC_OFF + 5.0, t);
    let wake = smoothstep(VC_CRACK, VC_ERUPT, t);
    // (the light of it on the land round it: the beam's, then the hole's)
    let lr = max(r - R, 0.0);
    c = c + c0 * vec3<f32>(2.2, 0.75, 0.2) * (fire * 1.1 / (1.0 + lr * lr / 900.0) + (0.5 - 0.35 * cool + wake) / (1.0 + lr * lr / (R * R * 1.5 + 1.0)));
    // (scorched round it)
    c = c * (1.0 - 0.8 * (1.0 - smoothstep(R, 2.6 * R + 6.0, r)) * smoothstep(VC_HIT, VC_HIT + 1.5, t));
    if (r > 1.5 * R + 5.0) {
        return c;
    }
    if (r < R) {
        // (down it: the far wall where the ray leaves the hole's round, how far under the rim; the floor past its depth)
        let Rw = R * length(q.xz) / max(r, 1.0e-3);
        let b = dot(o.xz, rd.xz);
        let a2 = max(dot(rd.xz, rd.xz), 1.0e-6);
        let s2 = (-b + sqrt(max(b * b - a2 * (dot(o.xz, o.xz) - Rw * Rw), 0.0))) / a2;
        let dep = max(q.y - (o.y + rd.y * s2), 0.0);
        let D = 6.0 + 150.0 * smoothstep(VC_HIT, VC_OFF, t);
        let wx = o.xz + rd.xz * s2;
        let n = vc_gn3(vec3<f32>(atan2(wx.y, wx.x) * 5.0, min(dep, D) * 0.06 - t * 0.5, 2.0));
        // (orange at the lip, white-hot down it; the lip going dark as it cools, the depths staying hot)
        var T = (0.32 + 0.9 * saturate(dep / (14.0 + 40.0 * cool)) - 0.3 * cool * (1.0 - smoothstep(0.0, 6.0, dep))) * (0.85 + 0.35 * n);
        T = mix(T, 1.35, step(D, dep));
        T = T * (1.0 - 0.15 * cool) + 0.25 * wake + 0.25 * fire;
        c = vc_fire_c(T) + vec3<f32>(5.0, 4.2, 3.0) * saturate(T - 1.05) * 1.5;
    } else {
        // (the lip: molten, then a crust with the glow in its cracks)
        let lip = 1.0 - smoothstep(R, 1.5 * R + 3.0, r + 1.5 * vc_gn3(vec3<f32>(rq * 0.3, 7.0)));
        let n = vc_gn3(vec3<f32>(rq * 0.35, t * 0.2));
        let vein = 1.0 - smoothstep(0.0, 0.08, abs(n - 0.5));
        let T = lip * mix(0.95, 0.55 * vein + 0.12, cool) * (0.75 + 0.3 * n);
        c = mix(c, vec3<f32>(0.04, 0.035, 0.03), lip * smoothstep(VC_HIT + 0.5, VC_OFF + 2.0, t));
        c = c + vc_fire_c(T + 0.3 * wake * lip);
    }
    return c;
}
// The rest, over the picture (sharp, full size): the steam off the hole, the satellite, its beams, their light.
fn vc_opening(c0: vec3<f32>, C: vec3<f32>, rd: vec3<f32>, len: f32, tr: f32, uv: vec2<f32>, l: VcLight, sky: bool) -> vec3<f32> {
    let t = vs.t;
    var c = c0;
    if (t > VC_ERUPT + 1.0) {
        return c;
    }
    let k = intensity_v();
    let res = frame.resolution.xy;
    let fire = smoothstep(VC_HIT, VC_HIT + 0.05, t) * (1.0 - smoothstep(VC_OFF, VC_OFF + 0.08, t));
    // ---- the steam off the hole: rising, leaning off with the wind, lit red from under ----
    let age = t - VC_HIT - 0.2;
    let H = min(30.0 + 60.0 * age, 620.0);
    // (near it at all, the mount's height under it counted at its most)
    let s0 = pl_ray_seg(rd, C, C + vec3<f32>(0.3 * H, H + vm.H * 1.5, 0.1 * H), 0.0, 1.0);
    if (age > 0.0 && s0.x < 30.0 + 0.7 * (H + vm.H) + s0.y * vs.px * 3.0) {
        let top = select(0.0, vm_height(vec2<f32>(0.0)), vm.on);
        let base = C + vec3<f32>(0.0, top, 0.0);
        let sg = pl_ray_seg(rd, base, base + vec3<f32>(0.3 * H, H, 0.1 * H), 0.0, 1.0);
        let h = H * sg.z;
        let w = max(12.0 + 0.32 * h, sg.y * vs.px * 1.5);
        if (sg.x < 1.9 * w && sg.y < len + w) {
            let q = rd * sg.y - C;
            let f = vc_tube(q, base - C + vec3<f32>(0.3, 1.0, 0.1) * h, rd, l.L, w, age, 40.0);
            let a = f.x * 0.75 * smoothstep(0.0, 1.0, age) * (1.0 - smoothstep(0.55, 1.0, sg.z)) * saturate((len - sg.y + w) / w) * (1.0 - smoothstep(VC_ERUPT - 0.5, VC_ERUPT + 0.6, t));
            let glow = vec3<f32>(1.6, 0.45, 0.1) * exp(-h / 40.0) * (0.8 * fire + 0.3 + 0.5 * smoothstep(VC_CRACK, VC_ERUPT, t));
            let sc = mix(vec3<f32>(0.8, 0.79, 0.78), vec3<f32>(0.3, 0.28, 0.26), smoothstep(0.1, 0.8, sg.z)) * (l.skyl * 0.5 + l.sunc * f.y * 0.7) + glow;
            c = mix(c, sc, a * tr);
        }
    }
    if (t > VC_SAT_END) {
        return c;
    }
    // ---- the satellite ----
    let S = vc_sat();
    let ax = normalize(-S);
    let su = normalize(cross(ax, vec3<f32>(0.0, 1.0, 0.0)));
    let sv = cross(su, ax);
    let P = S + C;
    let sk = vc_sat_k(P);
    let E = P + ax * 55.0 * sk;
    let show = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(VC_SAT_END - 2.0, VC_SAT_END, t));
    let charge = smoothstep(VC_LOCK + 0.1, VC_HIT, t) * (1.0 - smoothstep(VC_HIT, VC_HIT + 0.1, t));
    let tp = dot(P, rd);
    if (tp > 0.0 && length(P - rd * tp) < 180.0 * sk && tp < len) {
        let tu = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)));
        let tv = cross(tu, rd);
        // (the panels turning slowly on their arms, a glint off them as they catch the sun)
        let th = 0.5 + 0.08 * t;
        let cs = cos(th);
        let sn = sin(th);
        var acc = vec3<f32>(0.0);
        var cov = 0.0;
        for (var i = 0; i < 4; i = i + 1) {
            let off = (vec2<f32>(f32(i & 1), f32(i >> 1u)) - 0.5) * 0.5;
            let r = normalize(rd + (tu * off.x + tv * off.y) * vs.px);
            let o = vec3<f32>(dot(-P, su), dot(-P, sv), dot(-P, ax)) / sk;
            let d = vec3<f32>(dot(r, su), dot(r, sv), dot(r, ax));
            var best = vec4<f32>(1.0e9, 0.0, 0.0, 0.0);
            var m = -1;
            var lp = vec3<f32>(0.0);
            let hb = vc_box(o, d, vec3<f32>(15.0, 15.0, 33.0));
            if (hb.x > 0.0) {
                best = hb;
                m = 0;
            }
            let he = vc_box(o - vec3<f32>(0.0, 0.0, 43.0), d, vec3<f32>(9.0, 9.0, 11.0));
            if (he.x > 0.0 && he.x < best.x) {
                best = he;
                m = 2;
            }
            let ht = vc_box(o, d, vec3<f32>(24.0, 1.7, 1.7));
            if (ht.x > 0.0 && ht.x < best.x) {
                best = ht;
                m = 0;
            }
            // (the panels, in their own frame, turned about the arms)
            let rot = mat3x3<f32>(1.0, 0.0, 0.0, 0.0, cs, -sn, 0.0, sn, cs);
            for (var s = -1.0; s < 2.0; s = s + 2.0) {
                let hp = vc_box(rot * (o - vec3<f32>(81.0 * s, 0.0, 0.0)), rot * d, vec3<f32>(58.0, 20.0, 1.1));
                if (hp.x > 0.0 && hp.x < best.x) {
                    best = vec4<f32>(hp.x, transpose(rot) * hp.yzw);
                    m = 1;
                    lp = rot * (o + d * hp.x - vec3<f32>(81.0 * s, 0.0, 0.0));
                }
            }
            if (m >= 0) {
                let n = su * best.y + sv * best.z + ax * best.w;
                let lo = o + d * best.x;
                var alb = vec3<f32>(0.62, 0.46, 0.2) * (0.7 + 0.6 * hash31(floor(lo * 0.4)));
                var sp = 1.2;
                var glow = vec3<f32>(0.0);
                if (m == 1) {
                    let g = step(0.9, fract(lp.x / 5.0)) + step(0.88, fract(lp.y / 7.0));
                    alb = mix(vec3<f32>(0.02, 0.035, 0.09), vec3<f32>(0.3), saturate(g));
                    sp = 9.0;
                } else if (m == 2) {
                    alb = vec3<f32>(0.08, 0.08, 0.09);
                    if (best.w > 0.5) {
                        glow = mix(vec3<f32>(1.5, 0.05, 0.03) * smoothstep(VC_AIM - 0.2, VC_AIM, t), vec3<f32>(8.0, 6.0, 4.0), max(charge, fire)) * (1.0 - smoothstep(VC_OFF, VC_OFF + 0.6, t));
                    }
                }
                let lit = l.skyl * 0.3 + l.sunc * max(dot(n, l.L), 0.0) + l.sunc * sp * pow(max(dot(reflect(r, n), l.L), 0.0), 40.0);
                acc = acc + alb * lit + glow;
                cov = cov + 0.25;
            }
        }
        c = mix(c, acc / max(cov * 4.0, 1.0e-3), cov * show);
    }
    // (its lights, the glint as it comes into view, the emitter charging and firing)
    let pe = project_rel(E);
    if (pe.z > 0.0) {
        let dd = (uv - pe.xy) * res;
        let r2 = dot(dd, dd);
        for (var s = -1.0; s < 2.0; s = s + 2.0) {
            let pn = project_rel(P + su * 139.0 * sk * s);
            let dn = dot((uv - pn.xy) * res, (uv - pn.xy) * res);
            let bl = step(0.75, fract(t * 1.1 + 0.5 * s));
            c = c + select(vec3<f32>(0.1, 2.0, 0.3), vec3<f32>(2.0, 0.1, 0.05), s < 0.0) * bl * show / (1.0 + dn / 1.5);
        }
        let gl = exp(-pow((t - 0.45) / 0.14, 2.0));
        let star = 1.0 / (1.0 + r2 / 3.0) + 0.3 * (exp(-abs(dd.x) / 1.0) + exp(-abs(dd.y) / 1.0)) * exp(-sqrt(r2) / 22.0);
        c = c + vec3<f32>(2.0, 1.9, 1.7) * gl * star * show;
        let em = charge * 1.2 + fire * (1.6 + 0.4 * sin(t * 47.0));
        let flare = 1.0 / (1.0 + r2 / (5.0 + 18.0 * fire)) + 0.04 / (1.0 + r2 / 700.0) + 0.25 * exp(-abs(dd.y) / 1.5) * exp(-abs(dd.x) / (25.0 + 35.0 * fire));
        c = c + vec3<f32>(3.0, 2.1, 1.3) * em * flare * k;
    }
    // ---- the targeting beam: thin, solid, red, lit as the thing it is ----
    let sp = vc_spot();
    let G = C + vec3<f32>(sp.x, vc_land(sp), sp.y);
    if (t > VC_AIM && t < VC_HIT) {
        let B = mix(E, G, smoothstep(VC_AIM, VC_AIM + 0.18, t));
        let sg = pl_ray_seg(rd, E, B, 0.0, 1.0);
        let pw = sg.y * vs.px;
        let wv = max(1.1, 0.55 * pw);
        if (sg.y < len + 2.0 && sg.x < wv + pw) {
            let side = normalize(rd * sg.y - mix(E, B, sg.z) + vec3<f32>(1.0e-4));
            let shade = 0.25 + 0.9 * max(dot(side, l.L), 0.0) * l.sun_up + 0.35;
            let cv = saturate((wv - sg.x) / pw + 0.5) * max(1.1 / wv, 0.9);
            c = mix(c, vec3<f32>(0.85, 0.035, 0.02) * shade, cv * tr);
        }
    }
    // ---- the beam: a white-hot core in an orange sheath, coming down from the emitter in an instant, pulsing ----
    if (fire > 0.0) {
        let head = smoothstep(VC_HIT, VC_HIT + 0.1, t);
        let sg = pl_ray_seg(rd, E, mix(E, C, head), 0.0, 1.0);
        let pw = sg.y * vs.px;
        if (sg.y < len + 1.0) {
            let f = 0.8 + 0.35 * sin(t * 31.0 - sg.z * 40.0) * sin(t * 13.0 + sg.z * 17.0);
            let r0 = 2.8 * (1.0 + 0.5 * exp(-(t - VC_HIT) * 4.0));
            let rc = max(r0, 0.45 * pw);
            let core = exp(-pow(sg.x / rc, 2.0)) * min(r0 / rc, 1.0);
            let sheath = exp(-pow(sg.x / (rc * 2.6), 2.0)) * min(r0 / rc, 1.0);
            let halo = 1.0 / (1.0 + pow(sg.x / 30.0, 2.0));
            c = c + (vec3<f32>(6.0, 4.9, 3.4) * core + vec3<f32>(3.0, 0.85, 0.13) * sheath * f + vec3<f32>(0.8, 0.22, 0.04) * halo * 0.15) * fire * k;
        }
    }
    // ---- the hit's light: a bloom round where it melts in, seen over what stands in front of it ----
    let ph = project_rel(C);
    if (ph.z > 0.0 && t > VC_HIT && t < VC_OFF + 6.0) {
        let dd = (uv - ph.xy) * vec2<f32>(res.x / res.y, 1.0);
        let r2 = dot(dd, dd);
        let hot = fire * (1.0 + 0.2 * sin(t * 29.0)) + 0.06 * (1.0 - smoothstep(VC_OFF, VC_OFF + 6.0, t));
        c = c + vec3<f32>(2.2, 0.9, 0.3) * hot * (0.5 / (1.0 + r2 * 3000.0) + 0.07 / (1.0 + r2 * 160.0) + 0.35 * exp(-abs(dd.y) * 300.0) * exp(-abs(dd.x) * 10.0) * fire) * k;
    }
    return c;
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
    let tr = smoothstep(VC_HIT, VC_ERUPT - 1.0, t) * (1.0 - smoothstep(VC_ERUPT - 1.05, VC_ERUPT - 0.75, t));
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
    vs.fine = select(1.0, 2.0, stage == 1u);
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
    // ---- the mount, drawn over the land until the burst (volcano_mount.wgsl) ----
    let vmh = vm_surface(C, rd, scene_len, col, stage, l, uv, sky);
    col = vmh.c;
    if (vmh.t >= 0.0) {
        scene_len = vmh.t;
        sky = false;
    }

    // ---- the land and the sky, under it ----
    let fl = vc_flashes(seed);
    if (stage != 1u && !sky) {
        let qg = select(rel, rd * scene_len, vmh.t >= 0.0) - C;
        col = vc_dim(col, qg, L, sun_up);
        // (a bolt's foot lighting the land round it)
        col = col * (1.0 + 1.6 * vc_flash_land(fl, qg, seed));
        // (the targeting spot, the hole the beam melts)
        col = vc_open_land(col, qg, rd, -C);
        // (the cracks, the ring's glow on the land)
        let rg = length(qg.xz);
        let vent = smoothstep(VC_CRACK, VC_ERUPT, time);
        if (time > VC_ERUPT + 0.9 && abs(qg.y) < 200.0 && vmh.t < 0.0) {
            let dr = abs(rg - VC_RING);
            let ang = atan2(qg.z, qg.x);
            let wob = 14.0 * sin(ang * 7.0 + 1.0) + 9.0 * sin(ang * 19.0 + 3.0) + 6.0 * sin(ang * 43.0 + 0.5);
            let cr = abs(rg + wob - VC_RING);
            let w = 0.6 + 5.0 * vent * vent + 6.0 * smoothstep(VC_ERUPT, VC_ERUPT + 2.0, time);
            let line = 1.0 - smoothstep(w * 0.4, w * 1.4, cr);
            let glow2 = exp(-cr / (10.0 + 40.0 * vent));
            let lava = vec3<f32>(3.0, 0.8, 0.12);
            col = col + lava * line * 2.2 * (1.0 - smoothstep(VC_ERUPT + 1.0, VC_ERUPT + 5.0, time)) * k;
            col = col + scene * vec3<f32>(1.5, 0.4, 0.08) * glow2 * vent * (1.0 - smoothstep(VC_COLLAPSE, VC_LIFT, time)) * k;
            let lit = smoothstep(VC_ERUPT, VC_ERUPT + 1.0, time) * (1.0 - 0.7 * smoothstep(VC_COLLAPSE, VC_LIFT, time));
            col = col + scene * vec3<f32>(1.5, 0.42, 0.1) * (0.9 * exp(-max(rg - vs.Rb, 0.0) / 240.0)) * lit * k;
        }
    }
    if (stage != 1u && !sky && vs.cov > 0.0) {
        let lum = dot(l.skyl, vec3<f32>(0.2126, 0.7152, 0.0722));
        col = mix(col, vec3<f32>(lum) * vc_band(vec3<f32>(0.0)), (1.0 - exp(-max(scene_len - 250.0, 0.0) / 1500.0)) * smoothstep(0.1, 0.7, vs.cov));
    }
    if (stage != 1u && sky) {
        // (what sky is left, in along the horizon under the sheet: dirty with ash, dimmed)
        let cv = (vs.cov * 0.3 + 0.7 * smoothstep(0.0, 8.0, time - 23.0)) * smoothstep(VC_DARK - 6.0, VC_DARK + 8.0, time) * (1.0 - smoothstep(85.0, VC_LEN - 0.2, time));
        let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
        // (its light dirty and red low down, gone by a few degrees up under the sheet's edge)
        col = mix(col, vec3<f32>(lum) * vc_band(rd), cv);
    }
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    }
    // ---- the cloud ----
    var cloud_t = up_t;
    var tr_here = select(1.0, up.a, stage == 2u);
    if (stage != 2u) {
        let j = 0.5;
        let m = vc_march(C, rd, scene_len, j, l, fl);
        cloud_t = m.t;
        // (the bombs' smoke, in front of the cloud or behind it)
        var tb = 1.0e9;
        let sb = vc_bombs_smoke(C, rd, min(scene_len, 9000.0), l, l.skyl * vc_sky_t(-C), &tb);
        let st = vm_trails(C, rd, min(scene_len, 9000.0), l, &tb);
        let sm = vec4<f32>(st.rgb + sb.rgb * st.a, sb.a * st.a);
        var ac = sm.rgb + m.c * vc_cm;
        let at0 = m.tr * sm.a;
        cloud_t = min(cloud_t, tb);
        // (the mount's steam and dust, in front of it all)
        let va = vm_air(C, rd, min(scene_len, 9000.0), j, l);
        ac = va.rgb + ac * va.a;
        let at = at0 * va.a;
        tr_here = at;
        if (stage == 0u) {
            col = col * at + ac;
        } else {
            hc = vec4<f32>(ac, at);
        }
    }
    if (stage == 1u) {
        return VcOut(hc, vec4<f32>(min(scene_len, 6.0e4), min(cloud_t, 1.0e6), vm_chunk_near(C, rd, scene_len), vmh.id));
    }
    // ---- the opening: the satellite, its beams, the steam off the hole ----
    col = vc_opening(col, C, rd, scene_len, tr_here, uv, l, sky);
    // ---- the eruption: a hard ring of light round the land, the pressure ring out from it at the speed of sound ----
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
                let soft = 1.0 - exp(-sq / (0.012 * Rs + 3.0));
                let off = normalize(dirs + vec2<f32>(1.0e-5)) * (0.009 * edge + 0.002 * exp(-sq / (0.25 * Rs))) * sf * soft;
                let sc = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv - off, 0.0).rgb);
                col = col + (sc - scene) * saturate(edge * 4.0 + 0.5) * sf * tr_here * soft;
                col = col + vec3<f32>(1.0, 0.86, 0.72) * 0.1 * edge * exp(-vs.a / 1.4) * sf * tr_here * soft;
            }
        }
        // (the flash: a blaze along the horizon where the ring opens, out over the land)
        let P2 = C + vec3<f32>(0.0, 60.0, 0.0);
        let tP = dot(P2, rd);
        let hp2 = rd * max(tP, 0.0) - C;
        var dr2 = length(vec2<f32>(length(hp2.xz) - VC_RING, hp2.y - 30.0));
        // (or how far over the ring where it crosses it: a blaze all along it, its core hidden by the land)
        var dc = select(1.0e5, dr2, tP < scene_len + 60.0);
        let a2 = dot(rd.xz, rd.xz);
        let b2 = dot(rd.xz, C.xz);
        let e2 = b2 * b2 - a2 * (dot(C.xz, C.xz) - VC_RING * VC_RING);
        if (e2 > 0.0) {
            let tx = (b2 + vec2<f32>(-1.0, 1.0) * sqrt(e2)) / a2;
            let vy = abs(rd.y * tx - C.y - 30.0) + select(vec2<f32>(0.0), vec2<f32>(1.0e5), tx < vec2<f32>(0.0));
            dr2 = min(vy.x, vy.y);
            let vc = vy + select(vec2<f32>(0.0), vec2<f32>(1.0e5), tx > vec2<f32>(scene_len + 60.0));
            dc = min(vc.x, vc.y);
        }
        let fl = 5.0 * exp(-max(vs.a, 0.0) / 0.12) + 0.9 * exp(-max(vs.a, 0.0) / 1.1);
        col = col + vec3<f32>(3.0, 1.2, 0.3) * fl * (0.07 / (1.0 + pow(dc / 40.0, 2.0)) + 0.025 / (1.0 + pow(dr2 / 220.0, 2.0)) + 0.008) * smoothstep(-0.02, 0.02, vs.a) * k * tr_here;
    }
    // ---- the shock's pale shells, out over the fireball ----
    if (vs.a > 0.0 && vs.a < VC_DUST) {
        col = vc_dust(C, rd, min(scene_len, cloud_t), col, l);
    }
    if (vs.a > 0.25 && vs.a < 7.8) {
        col = vc_shells(C, rd, min(scene_len, cloud_t), col, l) ;
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
            // (engulfed: how long since the front went over, by how fast it came. Six or seven seconds of it, then it thins)
            let tau = eye_e / vs.dRf;
            let thick = smoothstep(0.0, 0.9, tau) * (1.0 - smoothstep(4.0, 8.5, tau)) * (1.0 - smoothstep(180.0, 400.0, over));
            // (how far one can see, thinning on after it has gone by, to nothing as the ash goes)
            let clear = smoothstep(8.0, 16.0, tau);
            let V = mix(mix(3000.0, 26000.0, clear), 170.0, thick) / max(1.0 - vs.thin, 1.0e-2);
            let Lh = 1800.0;
            let Lf = min(select(Lh + (6000.0 - Lh) * smoothstep(0.0, 0.15, rd.y), min(scene_len, Lh), !sky), 6000.0);
            // (only as far as the cloud, as much as it hides what is behind: a hard outline in the fog otherwise)
            let L = mix(min(Lf, cloud_t), Lf, saturate(tr_here));
            let toV = normalize(C + vec3<f32>(0.0, 40.0, 0.0));
            let vg = pow(saturate(dot(rd, toV)), 4.0) * (1.0 - smoothstep(VC_LIFT, VC_RED, time));
            // (the murk lit from under it, red down low; towards the vent the glow of all that is still burning)
            let low = 1.0 - smoothstep(-0.05, 0.5, rd.y);
            let fogc = vec3<f32>(0.032, 0.019, 0.014) * (0.3 + day) + vec3<f32>(0.1, 0.023, 0.006) * low * thick + vec3<f32>(0.2, 0.05, 0.01) * vg * thick;
            col = mix(col, fogc, (1.0 - exp(-L / V)) * smoothstep(0.0, 30.0, eye_e));
        }
    }
    // ---- flakes of ash coming down, embers driven past ----
    if (time > VC_COLLAPSE && eye_e > -700.0) {
        let wall = smoothstep(-40.0, 40.0, eye_e);
        let dirv = normalize(vec3<f32>(eq.x, 0.0, eq.z) + vec3<f32>(1.0e-3));
        if (wall > 0.0) {
            let eb = vc_specks(rd, cam * 0.0 + vec3<f32>(0.0, -time * 3.0, 0.0), dirv * 34.0 + vec3<f32>(0.0, 7.0, 0.0), min(scene_len, 40.0), time, 0.42, 1.5);
            let ek = wall * (1.0 - smoothstep(6.0, 11.0, max(eye_e, 0.0) / vs.dRf));
            col = col + vec3<f32>(2.4, 0.7, 0.12) * eb * ek * k;
        }
        let ash = wall * (1.0 - smoothstep(VC_RED + 2.0, VC_LEN - 0.5, time)) * smoothstep(VC_COLLAPSE, VC_COLLAPSE + 8.0, time);
        if (ash > 0.0) {
            let af = vc_specks(rd, cam, vec3<f32>(1.6, -4.5, 0.9), min(scene_len, 60.0), time, 0.42, 1.0);
            col = mix(col, vec3<f32>(0.28, 0.25, 0.23) * (0.2 + 0.8 * day), saturate(af) * ash * 0.8);
        }
    }
    // ---- the spray of rock, the bombs' heads, the bolts ----
    if (vs.a > 0.8 && vs.a < 21.0) {
        let sp = vc_spray(C, rd, min(scene_len, cloud_t + 60.0), seed);
        col = col * sp.a + sp.rgb * k;
    }
    if (time > VC_ERUPT + 1.0 && time < VC_COLLAPSE + 2.0) {
        col = col + vc_bombs_heads(C, rd, scene_len, cloud_t, tr_here) * k;
    }
    if (time > VC_LIGHT - 2.0 && time < VC_RED) {
        let kb = k * (1.0 - 0.8 * smoothstep(VC_HU - 200.0, VC_HU + 100.0, -C.y));
        col = col + vc_bolts(fl, C, seed, scene_len, cloud_t, tr_here, vc_px) * kb;
    }
    // ---- the blood-red sun, as the ash thins ----
    if (sky && time > VC_RED - 8.0 && sun.y > -0.03) {
        let cth = saturate(dot(rd, sun));
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let show = smoothstep(VC_RED - 7.0, VC_RED, time) * (1.0 - smoothstep(VC_LEN - 3.0, VC_LEN - 0.3, time));
        let vis = max(1.0 - exp(-7.0 * (tr_here + 0.05)), 0.9);
        let disc = 1.0 - smoothstep(0.052, 0.058, th);
        col = col + (vec3<f32>(1.15, 0.07, 0.02) * disc + vec3<f32>(0.42, 0.05, 0.02) * exp(-th / 0.22) + vec3<f32>(0.12, 0.03, 0.012) * exp(-th / 0.8)) * show * vis * sun_up;
    }
    col = vm_over(col, C, rd, scene_len, cloud_t, tr_here, l);
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
