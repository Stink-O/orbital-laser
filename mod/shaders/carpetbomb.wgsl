// Orbital Laser's post pass for the Carpet Bomb (laser 18). Like the Payload's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, project_rel, ray_seg, mh, ign) less the other lasers' own functions,
// followed by this file, and sets it for a carpet bomb strike only. Validate with tools/check-shader.sh.

// ---- laser 18: the carpet bomb --------------------------------------------------------------------------------------
// No beam. A bomber high over the land, unseen but for its contrail, two thin white lines drawing across the sky towards
// the player; out of the haze under it a stick of bombs, dark streaks dropping steeply one after another, and where each
// strikes, a flash, a low, wide fireball hugging the ground that rolls over into dark smoke, a ring of dust racing out
// over the land; blast after blast walking up the line, the rings overlapping, the dust rolling and merging into one
// wall along it, earth thrown up and raining down; the last the biggest, close in front of the player, its dust washing
// over them and muck on the lens. At most three blasts' smoke is drawn whole at once: each older one sinks into the
// line's dust as the next ones come.
// strike/carpet.rs lays the stick out in the table (cp_table, render.set-data): keep the CP_* in step.
const CP_LEN: f32 = 37.5;          // the strike's length (lasers.rs): everything fades out over its last CP_FADE
const CP_FADE: f32 = 7.0;
const CP_V: f32 = 343.0;           // a blast's front, blocks a second (with its sound: carpet.rs)
const CP_B: u32 = 16u;             // the bombs from CP_B, CP_BW words each (when, x, z, ground, size, along, hash)
const CP_BW: u32 = 8u;
const CP_HF: u32 = 1024u;          // the land's heightfield (payload.rs's pl_hf_pack): its size, then heights
const CP_DB: u32 = 10496u;         // the debris (carpet.rs's cp_debris_words), CP_DW words a piece, CP_DPB a bomb
const CP_DW: u32 = 10u;
const CP_DPB: i32 = 24;
const CP_NMAX: i32 = 14;
const CP_HB: f32 = 632.0;            // the bomber's height over the land (the bombs leave its belly)

fn cp_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn cp_n() -> i32 {
    return min(i32(cp_w(0u) + 0.5), CP_NMAX);
}
fn cp_dir() -> vec2<f32> {
    return vec2<f32>(cp_w(1u), cp_w(2u));
}
fn cp_wind() -> vec3<f32> {
    return vec3<f32>(cp_w(3u), 0.0, cp_w(4u));
}
// Bomb b: where it strikes (from the target's ground point) and when.
fn cp_bomb(b: i32) -> vec4<f32> {
    let o = CP_B + CP_BW * u32(b);
    return vec4<f32>(cp_w(o + 1u), cp_w(o + 3u), cp_w(o + 2u), cp_w(o));
}
fn cp_size(b: i32) -> f32 {
    return max(cp_w(CP_B + CP_BW * u32(b) + 4u), 0.5);
}
// The bomber's flight (carpet.rs's CpGeo): its speed (word 10), when it is half way through letting the stick go (11),
// how long that takes (12), where it is along the line then (13), when it comes out of the haze (14). How far along the
// line's way it is at strike time t (it flies the line, on past the player).
fn cp_plane_along(t: f32) -> f32 {
    return cp_w(13u) + cp_w(10u) * (t - cp_w(11u));
}
// When bomb b leaves its belly: the stick let go one after another over the ripple, the first first.
fn cp_release(b: i32) -> f32 {
    return cp_w(11u) + cp_w(12u) * (f32(b) / max(f32(cp_n() - 1), 1.0) - 0.5);
}
// Where bomb b is at strike time t (from the target's ground point), between leaving the bomber and striking: carried
// on with it at first, falling faster and faster, steeper as it comes down.
fn cp_fall(b: i32, t: f32) -> vec3<f32> {
    let imp = cp_bomb(b);
    let r0 = cp_release(b);
    let dir = cp_dir();
    let rel = vec3<f32>(cp_w(8u), CP_HB - 3.0, cp_w(9u)) + vec3<f32>(dir.x, 0.0, dir.y) * cp_plane_along(r0);
    let u = saturate((t - r0) / max(imp.w - r0, 0.1));
    let fwd = 1.0 - (1.0 - u) * (1.0 - u);
    return vec3<f32>(mix(rel.x, imp.x, fwd), mix(rel.y, imp.y, u * u), mix(rel.z, imp.z, fwd));
}
// An ellipsoid's distance (radii r) at e = its offset, as the Payload's skirt has it: a close bound, not the smallest
// radius's, which reads far too near beside a flat one and lets the lumps swell it out over everything near.
fn cp_ellipsoid(e: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(e / r);
    let k1 = length(e / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1.0e-4);
}
fn cp_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// Cauliflower lumps (payload.wgsl's pl_dome): domes over a jittered lattice, each its own size.
fn cp_dome(p: vec3<f32>) -> f32 {
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
fn cp_rot(k: i32, p: vec3<f32>) -> vec3<f32> {
    if (k == 0) {
        return mat3x3<f32>(-0.0014, 0.9977, -0.0674, -0.2224, -0.0660, -0.9727, -0.9750, 0.0136, 0.2220) * p;
    }
    if (k == 1) {
        return mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971) * p;
    }
    return mat3x3<f32>(-0.9891, -0.1223, 0.0816, 0.0968, -0.9594, -0.2651, 0.1107, -0.2543, 0.9608) * p;
}

// ---- the land: the heightfield round the line (the dust and the rings hug it) ----------------------------------------
fn cp_land(q: vec2<f32>) -> f32 {
    let nf = cp_w(CP_HF);
    if (nf < 2.0) {
        return 0.0;
    }
    let n = u32(nf + 0.5);
    if (arrayLength(&mod_data) < CP_HF + 8u + n * n) {
        return 0.0;
    }
    let R = cp_w(CP_HF + 1u);
    let step = 2.0 * R / (nf - 1.0);
    let fc = clamp((q + R) / step, vec2<f32>(0.0), vec2<f32>(nf - 1.001));
    let i0 = vec2<u32>(floor(fc));
    let t = fc - floor(fc);
    let b = CP_HF + 8u + i0.y * n + i0.x;
    let c = vec4<u32>(mod_data[b], mod_data[b + 1u], mod_data[b + n], mod_data[b + n + 1u]);
    let hv = vec4<f32>(c & vec4<u32>(0xffffu)) / 8.0 - 512.0;
    return mix(mix(hv.x, hv.y, t.x), mix(hv.z, hv.w, t.x), t.y);
}

// ---- a blast's smoke: a low, wide fireball hugging the ground, rolling over into dark smoke and sinking into dust --------
// Its size at age a (size s): its reach across, its height, how far its billows have lifted.
// (how wide the last's fireball may grow: short of where the player stood, so it never swallows them)
var<private> cp_cap: f32 = 1.0e9;
fn cp_body_dim(a: f32, s: f32) -> vec3<f32> {
    if (s > 1.4) {
        // (the last: two to three times the others' across. Its dome's reach (short of where the player stood), its
        // height (bursting up fast, then climbing slowly on, as the Payload's), how far its plume leans downwind)
        let Rb = min(38.0 * s * (0.2 + 0.8 * (1.0 - exp(-a / 0.35))) * (1.0 + 0.012 * a), cp_cap);
        let Hb = s * (30.0 + 26.0 * (1.0 - exp(-a / 1.0)) + 1.6 * min(a, 24.0));
        return vec3<f32>(Rb, Hb, s * (3.0 + 2.6 * min(a, 24.0)));
    }
    let R = 26.0 * s * (0.25 + 0.75 * (1.0 - exp(-a / 0.3))) * (1.0 + 0.02 * a);
    let H = s * (11.0 + 16.0 * (1.0 - exp(-a / 0.7)) + 0.35 * min(a, 25.0));
    return vec3<f32>(R, H, s * (3.0 * min(a, 2.0) + 0.15 * a));
}
// The smooth body of blast B (its middle on the ground, camera-relative, and its age in .w; its size and its weight in
// S.xy) at p: a squat dome, wider than tall, with a few billows on it and a low skirt spreading over the ground.
// The last blast's smoke (its own shape, moving as the Payload's column does): billows launched out of it, each eased up
// and swelled over time, fast at first and slowing; a broad, squat, boiling dome over a wide dust skirt, its upper
// billows sheared off downwind into a leaning plume, its foot staying put.
fn cp_final_d(p: vec3<f32>, B: vec4<f32>, S: vec2<f32>, hsh: u32) -> f32 {
    let a = B.w;
    let s = S.x;
    let dm = cp_body_dim(a, s);
    let R = dm.x;
    let H = dm.y;
    var wd = cp_wind();
    wd = select(vec3<f32>(1.0, 0.0, 0.0), wd / max(length(wd), 1.0e-4), length(wd) > 0.05);
    let q = p - B.xyz;
    let grow = 1.0 + 0.01 * max(a - 4.0, 0.0);
    // (the skirt: wide and low, the dust it threw out rolling over the land)
    let sh = 7.0 * s + 0.08 * H;
    var d = cp_ellipsoid(q - wd * (0.15 * dm.z), vec3<f32>(R * 1.3, sh, R * 1.3));
    // (the dome: broad and squat)
    d = cp_smin(d, cp_ellipsoid(q - vec3<f32>(0.0, 0.1 * H, 0.0), vec3<f32>(R * 0.95, 0.5 * H, R * 0.95)), 10.0 * s);
    for (var i = 0u; i < 14u; i = i + 1u) {
        let h0 = mh(i, hsh, 0x81u);
        let dome = i < 8u;
        let sg = a - select(0.1 + 0.5 * h0, 0.02 + 0.2 * h0, dome);
        if (sg <= 0.0) {
            continue;
        }
        let tau = 0.55 + 0.75 * mh(i, hsh, 0x82u);
        let rise = 1.0 - exp(-sg / tau);
        let h2 = mh(i, hsh, 0x83u);
        let hf = select(0.55 + 0.45 * (f32(i - 8u) / 5.0) + 0.08 * h2, 0.12 + 0.42 * h2, dome);
        let off = R * select(0.22 * mh(i, hsh, 0x84u), 0.25 + 0.6 * mh(i, hsh, 0x84u), dome);
        let rad = R * select(0.3 + 0.12 * mh(i, hsh, 0x85u), 0.33 + 0.14 * mh(i, hsh, 0x85u), dome);
        let hgt = hf * H * rise;
        let ang = TAU * mh(i, hsh, 0x86u);
        let spread = 0.35 + 0.65 * rise;
        // (sheared off downwind the higher it climbs, its foot staying put)
        let c = vec3<f32>(cos(ang) * off * spread, hgt, sin(ang) * off * spread) + wd * (dm.z * pow(saturate(hgt / H), 1.5));
        let r = rad * (0.25 + 0.75 * (1.0 - exp(-sg / (0.45 * tau)))) * grow * select(0.85, 1.0, dome);
        d = cp_smin(d, length(q - c) - r, 12.0 * s);
    }
    return d + (1.0 - S.y) * 0.6 * R;
}
fn cp_body_d(p: vec3<f32>, B: vec4<f32>, S: vec2<f32>, hsh: u32) -> f32 {
    if (S.y <= 0.0) {
        return 1.0e6;
    }
    if (S.x > 1.4) {
        return cp_final_d(p, B, S, hsh);
    }
    let dm = cp_body_dim(B.w, S.x);
    let q = p - B.xyz - cp_wind() * (0.4 * B.w);
    // (the dome: its middle a little over the ground, its foot sunk into the crater)
    var d = cp_ellipsoid(q - vec3<f32>(0.0, 0.3 * dm.y, 0.0), vec3<f32>(dm.x * 0.8, dm.y, dm.x * 0.8));
    // (the skirt: wide and low)
    let sk = dm.x * select(1.25, 1.05, S.x > 1.4);
    d = cp_smin(d, cp_ellipsoid(q, vec3<f32>(sk, 0.35 * dm.y + 2.0, sk)), 6.0 * S.x);
    // (four billows rolling up off its top and sides as it lifts)
    for (var k = 0u; k < 4u; k = k + 1u) {
        let ang = TAU * mh(k, hsh, 0x61u);
        let rr = dm.x * (0.25 + 0.4 * mh(k, hsh, 0x62u));
        let hy = dm.y * (0.45 + 0.4 * mh(k, hsh, 0x63u)) + dm.z * (0.5 + 0.5 * mh(k, hsh, 0x64u));
        let rad = dm.x * (0.32 + 0.12 * mh(k, hsh, 0x65u));
        let c = vec3<f32>(cos(ang) * rr, hy, sin(ang) * rr);
        d = cp_smin(d, length(q - c) - rad, 8.0 * S.x);
    }
    // (sinking into the line's dust as it is let go: lower and thinner)
    return d + (1.0 - S.y) * 0.6 * dm.x;
}
// The bodies' union (up to three), and which is nearest.
fn cp_bodies(p: vec3<f32>, B0: vec4<f32>, S0: vec2<f32>, h0: u32, B1: vec4<f32>, S1: vec2<f32>, h1: u32, B2: vec4<f32>, S2: vec2<f32>, h2: u32) -> vec2<f32> {
    let d0 = cp_body_d(p, B0, S0, h0);
    let d1 = cp_body_d(p, B1, S1, h1);
    let d2 = cp_body_d(p, B2, S2, h2);
    var w = 0.0;
    var m = d0;
    if (d1 < m) {
        m = d1;
        w = 1.0;
    }
    if (d2 < m) {
        m = d2;
        w = 2.0;
    }
    return vec2<f32>(cp_smin(cp_smin(d0, d1, 10.0), d2, 10.0), w);
}
// Its surface's lumps at p (camera-relative; `a` the nearest's age): lumps on lumps, a fine fray at the edge. In .y how
// far up a dome it lies, in .z the fray.
fn cp_lumps(p: vec3<f32>, d0: f32, a: f32, fine: bool, sc: f32) -> vec3<f32> {
    // (carried up with the rising mass and along with the wind, as the Payload's: its lumps churn as it climbs; the
    // last's faster up front, then slowly)
    let up = select(1.6 * min(a, 6.0) + 0.3 * a, 2.2 * a + 10.0 * min(a, 1.5), sc > 1.5);
    let q = (p + frame.camera_position.xyz - vec3<f32>(0.0, up, 0.0) - cp_wind() * (0.5 * a)) / sc;
    let w = gnoise3(cp_rot(1, q * (1.0 / 26.0)));
    let w2 = gnoise3(cp_rot(2, q * (1.0 / 11.0) + vec3<f32>(9.2, -0.1 * a, 4.4)));
    let b1 = cp_dome(cp_rot(0, q * (1.0 / 15.0) + 0.3 * vec3<f32>(w2 - 0.5)));
    let b2 = cp_dome(cp_rot(1, q * (1.0 / 6.5) + vec3<f32>(0.0, -0.3 * a, 1.3)));
    // (as it settles, the last's billows melt away into a softer mass)
    let crisp = 1.0 - 0.7 * smoothstep(14.0, 26.0, a) * step(1.5, sc);
    var d = d0 - (10.0 * (b1 - 0.45) * crisp + 4.0 * (b2 - 0.45) * crisp + 8.0 * (w - 0.5) + 4.0 * (w2 - 0.5)) * sc;
    var fray = 0.5;
    if (fine && d < 6.0) {
        let b3 = cp_dome(cp_rot(2, q * (1.0 / 2.6) + vec3<f32>(1.7, -0.5 * a, -2.1)));
        d = d - 1.4 * (b3 - 0.45) * sc;
        fray = gnoise3(cp_rot(0, q * (1.0 / 1.2)) + vec3<f32>(5.0, 1.0, -0.8 * a));
        d = d - 1.2 * (fray - 0.5) * sc;
    }
    return vec3<f32>(d, b1 * (0.45 + 0.55 * b2), fray);
}

// ---- the line's dust: each blast's ring of dust rolling out and stalling, all of them merging into one wall --------------
// At p (camera-relative; q from the target's ground point, h its height over the land): its density and how high over
// the land it may stand there.
fn cp_dust(q: vec3<f32>, h: f32, time: f32, n: i32) -> vec2<f32> {
    var dsum = 0.0;
    var hmax = 0.0;
    for (var b = 0; b < n; b = b + 1) {
        let bm = cp_bomb(b);
        let a = time - bm.w;
        if (a <= 0.0) {
            continue;
        }
        let s = cp_size(b);
        // (the last's kept short of where the player stood, as its fireball is: its front (cp_front) goes over them)
        let Rd = min(s * (52.0 * (1.0 - exp(-a / 1.0)) + 1.0 * min(a, 15.0)), select(1.0e9, cp_cap * 1.35, b == n - 1));
        let r = length(q.xz - bm.xz);
        if (r > Rd + 22.0) {
            continue;
        }
        let ww = 6.0 + 0.12 * Rd;
        let rim = exp(-pow((r - Rd) / ww, 2.0)) * (0.25 + 0.75 * exp(-a / 4.0));
        let inside = smoothstep(Rd + 3.0, Rd - 14.0, r) * (0.3 + 0.7 * exp(-a / 7.0));
        let db = 0.9 * rim + 0.4 * inside;
        dsum = dsum + db;
        hmax = max(hmax, s * (9.0 + 20.0 * (1.0 - exp(-a / 1.4)) + 0.6 * min(a, 22.0)) * (0.8 + 0.4 * rim) * saturate(db * 2.5));
    }
    if (dsum <= 0.003) {
        return vec2<f32>(0.0, 0.0);
    }
    return vec2<f32>(dsum, hmax);
}

// ---- a blast's shockwave front, as the Payload's (payload.wgsl's pl_dust): a dense wall of dust a few blocks high
// just behind a crisp, billowing front racing out at the speed of sound, thinning behind it into haze that rises and
// hangs, all over the land's own ground. `amp` how much of it (the last's 1, the small ones' less), `hs` how high,
// `quick` how fast it settles (the small ones' quicker), `inner` the clear middle (its smoke is there). Its density and
// its height over the land at p.
fn cp_front(p: vec3<f32>, C: vec3<f32>, Cf: vec3<f32>, a: f32, amp: f32, hs: f32, quick: f32, inner: f32) -> vec2<f32> {
    let q = p - Cf;
    let r = length(q.xz);
    let w = p + frame.camera_position.xyz;
    let qg = p - C;
    let h = qg.y - cp_land(qg.xz);
    if (h > 70.0 * hs || h < -4.0) {
        return vec2<f32>(0.0, h);
    }
    let rf = CP_V * a;
    let n1 = gnoise3(w * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a, 0.0));
    let n2 = gnoise3(w * (1.0 / 3.5) + vec3<f32>(5.0, -2.0 * a, 1.0));
    let sf = rf - r + (n1 - 0.5) * 14.0 + (n2 - 0.5) * 5.0 - 0.25 * max(h, 0.0);
    if (sf < -3.0) {
        return vec2<f32>(0.0, h);
    }
    let since = max(sf, 0.0) / CP_V;
    let n3 = gnoise3(w * (1.0 / 38.0) + vec3<f32>(0.0, -0.3 * a, 9.0));
    let rise = 1.0 + 0.8 * smoothstep(0.0, 25.0, sf) - 0.7 * smoothstep(30.0, 140.0, sf);
    let hw = ((4.5 + 0.006 * r) * rise * (0.35 + 1.2 * n1) * (0.6 + 0.8 * n3) + 1.5 * min(since, 6.0)) * hs;
    let up = smoothstep(hw, hw * 0.35, h) * smoothstep(-4.0, 0.0, h);
    let lead = smoothstep(-3.0, 1.5, sf);
    let wall = 1.6 * exp(-sf / (9.0 + 0.015 * r));
    let haze = (0.009 * exp(-since * quick / 2.5) + 0.0025 * exp(-since * quick / 6.0)) * (0.5 + n2);
    let mid = smoothstep(inner, inner * 3.0, r);
    let low = 0.22 * exp(-since * quick / 3.0) * smoothstep(0.0, 30.0, sf) * exp(-max(h, 0.0) / (2.5 + 2.0 * n1)) * smoothstep(0.35, 0.7, n3);
    return vec2<f32>(((wall * saturate(1.5 * n1 + 0.25 * n2) * (0.35 + 1.3 * n3) + haze) * up + low) * lead * mid * amp, h);
}
// That front marched along the ray where it crosses the shell behind it, more sparsely inside (payload.wgsl's way): its
// colour gathered (premultiplied) and what still shows through.
fn cp_front_march(rd: vec3<f32>, C: vec3<f32>, Cf: vec3<f32>, a: f32, amp: f32, hs: f32, quick: f32, inner: f32, t0: f32, t1: f32, j: f32, dcol: vec3<f32>, amb: vec3<f32>) -> vec4<f32> {
    let rf = CP_V * a;
    let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
    let bb = -dot(rd.xz, Cf.xz);
    let cc = dot(Cf.xz, Cf.xz);
    let Ro = rf + 12.0;
    let Ri = max(rf - 60.0, 0.0);
    let dout = bb * bb - a2 * (cc - Ro * Ro);
    let din = bb * bb - a2 * (cc - Ri * Ri);
    var tr = 1.0;
    var acc = vec3<f32>(0.0);
    if (t1 <= t0 || dout <= 0.0) {
        return vec4<f32>(acc, tr);
    }
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
        ns = array<i32, 3>(10, 8, 5);
    }
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
            let u0 = (f32(i) + j) / f32(n);
            let u1 = (f32(i) + j + 1.0) / f32(n);
            let t = sa + (sb - sa) * u0 * u0;
            let dt = (sb - sa) * (u1 * u1 - u0 * u0);
            let p = rd * t;
            let dh = cp_front(p, C, Cf, a, amp, hs, quick, inner);
            // (thin right round the eye: the front passing over it would fill the picture; the lens shows it instead)
            let den = dh.x * smoothstep(2.0, 30.0, t);
            if (den <= 0.001) {
                continue;
            }
            let al = 1.0 - exp(-den * dt * 0.3);
            let wq = p + frame.camera_position.xyz;
            let bl = gnoise3(wq * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a + 0.5, 0.0));
            let lo = (0.45 + 0.55 * saturate(dh.y / 8.0)) * (0.55 + 0.7 * bl);
            acc = acc + tr * al * (dcol * lo + amb * 0.6 * vec3<f32>(0.62, 0.55, 0.34));
            tr = tr * (1.0 - al);
            if (tr < 0.02) {
                break;
            }
        }
    }
    return vec4<f32>(acc, tr);
}

// ---- the debris: chunks and specks of earth thrown out of each crater, falling back round it --------------------------
struct CpChunk {
    p: vec3<f32>,
    v: vec3<f32>,
    s: f32,
    live: f32,
}
fn cp_chunk(i: i32, a: f32, C: vec3<f32>) -> CpChunk {
    var o: CpChunk;
    let b = CP_DB + CP_DW * u32(i);
    let tau = a - cp_w(b + 5u);
    o.s = cp_w(b + 6u);
    o.live = 0.0;
    if (tau <= 0.0) {
        return o;
    }
    let dir = vec3<f32>(cp_w(b), 0.0, cp_w(b + 1u));
    let vh = cp_w(b + 3u);
    let vy = cp_w(b + 4u);
    let k = 0.06;
    let ek = exp(-k * a) * cp_w(b + 7u);
    let e = (1.0 - ek) / k;
    let g = 9.8;
    o.p = C + dir * (cp_w(b + 2u) + vh * e) + vec3<f32>(0.0, 1.5 + vy * e - g * (tau - e) / k, 0.0);
    o.v = dir * (vh * ek) + vec3<f32>(0.0, (vy + g / k) * ek - g / k, 0.0);
    o.live = 1.0;
    return o;
}

// ---- the fires: flames left burning in and round each crater, spot fires out on the flattened land -----------------
// How strongly the fires of bomb b burn at its age a (0 to 1): catching over half a second, burning down over a while.
fn cp_burn(a: f32, big: bool) -> f32 {
    let life = select(13.0, 22.0, big);
    return smoothstep(0.15, 0.8, a) * (1.0 - smoothstep(life * 0.4, life, a));
}
// ---- the light inside the smoke: each blast's glow blooming through it as it goes off, fading out over about a second.
// The two that count at this moment (the two latest blasts'), camera-relative, their strength in .w, their reach in `r`.
struct CpLit {
    l0: vec4<f32>,
    l1: vec4<f32>,
    r: vec2<f32>,
}
fn cp_lights(C: vec3<f32>, time: f32, latest: i32, lastb: i32) -> CpLit {
    var o: CpLit;
    o.l0 = vec4<f32>(0.0);
    o.l1 = vec4<f32>(0.0);
    o.r = vec2<f32>(1.0);
    if (latest < 0) {
        return o;
    }
    for (var j = 0; j < 2; j = j + 1) {
        let b = latest - j;
        if (b < 0) {
            continue;
        }
        let bm = cp_bomb(b);
        let a = time - bm.w;
        let s = cp_size(b);
        let big = b == lastb;
        let dm = cp_body_dim(max(a, 0.05), s);
        let g = (2.0 * exp(-a / 0.15) + 0.8 * exp(-a / 0.45)) * s * select(1.0, 1.4, big) * step(0.0, a);
        let l = vec4<f32>(C + bm.xyz + vec3<f32>(0.0, 0.35 * dm.y, 0.0), g);
        if (j == 0) {
            o.l0 = l;
            o.r.x = dm.x * 0.6;
        } else {
            o.l1 = l;
            o.r.y = dm.x * 0.6;
        }
    }
    return o;
}
// The light those two give smoke or dust at p.
fn cp_lit_at(lt: CpLit, p: vec3<f32>) -> vec3<f32> {
    let d0 = p - lt.l0.xyz;
    let d1 = p - lt.l1.xyz;
    let g = lt.l0.w / (1.0 + dot(d0, d0) / (lt.r.x * lt.r.x)) + lt.l1.w / (1.0 + dot(d1, d1) / (lt.r.y * lt.r.y));
    return vec3<f32>(2.6, 1.1, 0.3) * g;
}

// A field of flames in a vertical cylinder (its middle `c` on its ground, camera-relative; radius rr, flames up to hh,
// its floor sunk `sink` in the middle as a crater's is): their light along the ray up to `lim`, in six looks. Patches of
// fire (some ground bare), each torn into tongues licking up, flickering, hottest low, red at their tips.
fn cp_flames(rd: vec3<f32>, c: vec3<f32>, rr: f32, hh: f32, sink: f32, lim: f32, j: f32, time: f32, key: f32, I: f32) -> vec3<f32> {
    let a2 = dot(rd.xz, rd.xz);
    if (a2 < 1.0e-8 || I <= 0.0) {
        return vec3<f32>(0.0);
    }
    let bb = -dot(rd.xz, c.xz);
    let disc = bb * bb - a2 * (dot(c.xz, c.xz) - rr * rr);
    if (disc <= 0.0) {
        return vec3<f32>(0.0);
    }
    let sq = sqrt(disc);
    var t0 = max((-bb - sq) / a2, 0.0);
    var t1 = min((-bb + sq) / a2, lim);
    if (abs(rd.y) > 1.0e-5) {
        let ya = (c.y - sink - 1.0) / rd.y;
        let yb = (c.y + hh) / rd.y;
        t0 = max(t0, min(ya, yb));
        t1 = min(t1, max(ya, yb));
    }
    if (t1 <= t0) {
        return vec3<f32>(0.0);
    }
    let dt = (t1 - t0) / 6.0;
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 6; i = i + 1) {
        let p = rd * (t0 + (f32(i) + j) * dt);
        let q = p - c;
        let r = length(q.xz) / rr;
        let h = q.y + sink * saturate(1.0 - r * r);
        if (h < -0.5 || r > 1.0) {
            continue;
        }
        let w = p + frame.camera_position.xyz;
        let pch = smoothstep(0.38, 0.68, gnoise3(vec3<f32>(w.xz / 5.0, key)));
        if (pch <= 0.0) {
            continue;
        }
        let fl = gnoise3(vec3<f32>(w.x / 1.6, w.y / 2.6 - time * 3.2, w.z / 1.6) + key);
        let top = hh * (0.35 + 0.65 * pch) * (0.4 + 0.6 * I);
        let u = max(h, 0.0) / max(top, 0.3);
        // (the fine tongues looked up only where the flame could show at all)
        if (fl * 1.21 + 0.99 - 0.5 - u * 1.15 <= 0.0) {
            continue;
        }
        let fl2 = gnoise3(vec3<f32>(w.x / 0.7, w.y / 1.1 - time * 5.5, w.z / 0.7) - key);
        let den = saturate((0.55 * fl + 0.45 * fl2) * 2.2 - 0.5 - u * 1.15) * pch * smoothstep(1.0, 0.8, r);
        if (den > 0.0) {
            let hot = mix(vec3<f32>(2.4, 1.15, 0.3), vec3<f32>(1.3, 0.24, 0.04), saturate(u * 1.2));
            acc = acc + hot * den * min(dt, 3.0);
        }
    }
    return acc * I * 0.35;
}

struct CpOut {
    c: vec4<f32>,
    e: vec4<f32>,
}
fn cp_over(h: ptr<function, vec4<f32>>, c: vec3<f32>, x: f32) {
    *h = vec4<f32>((*h).rgb * (1.0 - x) + c * x, (*h).a * (1.0 - x));
}
// Ray (from the eye along rd) against a sphere at c of radius r: where it enters and leaves (none: x > y).
fn cp_sphere(rd: vec3<f32>, c: vec3<f32>, r: f32) -> vec2<f32> {
    let b = dot(rd, c);
    let h = b * b - dot(c, c) + r * r;
    if (h < 0.0) {
        return vec2<f32>(1.0, -1.0);
    }
    let s = sqrt(h);
    return vec2<f32>(max(b - s, 0.0), b + s);
}

// The pass, in one of three stages, as the Payload's: 0 the whole of it at full size (fs_main); 1 the half-size stage
// (fs_half: the blasts' smoke and the line's dust), returned as premultiplied colour and transmittance; 2 the join
// (fs_join: the rest, sharp, at full size, the half-size stage's `up` laid over the picture; `up_t` the smoke's distance).
fn carpetbomb(in: StageIn, stage: u32, up: vec4<f32>, up_t: f32) -> CpOut {
    var uv = in.uv;
    let time = now();
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let px_a = frame.view_params.w / frame.resolution.y;
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z) - cam;
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    let n = cp_n();
    let have = n > 0;
    if (have) {
        let lbm = cp_bomb(n - 1);
        cp_cap = 0.45 * length((me - (C + lbm.xyz)).xz);
    }

    var d = 0.0;
    if (stage == 1u) {
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
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
    var hc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let fade = 1.0 - smoothstep(CP_LEN - CP_FADE, CP_LEN, time);

    // (the latest bomb down, and the last's index)
    var latest = -1;
    for (var b = 0; b < n; b = b + 1) {
        if (cp_bomb(b).w < time) {
            latest = b;
        }
    }
    let lastb = n - 1;

    // (leaves and grass whipped as each front goes through them)
    if (stage != 1u && !sky && have && latest >= 0) {
        let green = scene.g > scene.r * 1.1 && scene.g > scene.b * 1.05;
        if (green) {
            var gust = 0.0;
            for (var b = max(latest - 3, 0); b <= latest; b = b + 1) {
                let bm = cp_bomb(b);
                let a = time - bm.w;
                if (a > 0.0 && a < 4.0) {
                    let rs = length((rel - (C + bm.xyz)).xz);
                    let e = CP_V * a - rs;
                    gust = max(gust, (exp(-pow(e / 12.0, 2.0)) + 0.4 * exp(-max(e, 0.0) / 40.0) * step(0.0, e)) * cp_size(b) * exp(-rs / 160.0));
                }
            }
            if (gust > 0.03) {
                let fpx0 = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
                let amp = min(0.45 * fpx0 / max(scene_len, 1.0), 7.0) * min(gust, 1.4);
                let ph = dot(floor(in.position.xy / 6.0), vec2<f32>(0.37, 0.71));
                let off = vec2<f32>(sin(time * 29.0 + ph * 5.0), cos(time * 23.0 + ph * 3.0)) * amp;
                let s2 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv + off * frame.resolution.zw, 0.0).rgb);
                if (s2.g > s2.r * 1.1 && s2.g > s2.b * 1.05) {
                    col = s2;
                }
            }
        }
    }

    // (the light, matched to the scene's, as the Payload's)
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
    let fire_c = vec3<f32>(3.2, 1.55, 0.5);

    // ---- each blast's flash lighting the land and the air round it, and its crater glowing a while after ---------------
    if (stage != 1u && have && latest >= 0) {
        for (var b = max(latest - 9, 0); b <= latest; b = b + 1) {
            let bm = cp_bomb(b);
            let a = time - bm.w;
            if (a <= 0.0 || a > 16.0) {
                continue;
            }
            let s = cp_size(b);
            let big = b == lastb;
            let flash = (exp(-a / 0.12) + 0.3 * exp(-a / 0.7)) * s * select(1.0, 2.2, big);
            let Pf = C + bm.xyz + vec3<f32>(0.0, select(4.0, 12.0, big) * s, 0.0);
            let df = length(Pf);
            let cth = dot(rd, Pf / df);
            let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
            col = col + fire_c * flash * (0.1 / (1.0 + pow(th / 0.03, 2.0)) + 0.02 * exp(-th / 0.35)) * k;
            if (!sky) {
                let dl = length(rel - Pf);
                col = col + scene * fire_c * flash * 2.0 / (1.0 + pow(dl / (select(32.0, 70.0, big) * s), 2.0)) * k;
                // (the last's condensation flash: the land whitened in a broad band just behind its front as it races out)
                if (big && a < 1.6) {
                    let rs = length((rel - (C + bm.xyz)).xz);
                    let e = CP_V * a - rs;
                    let bandw = smoothstep(-3.0, 4.0, e) * exp(-max(e, 0.0) / 45.0) * exp(-a / 0.55) * smoothstep(20.0, 60.0, rs);
                    col = mix(col, vec3<f32>(0.95, 0.96, 1.0) * (sunc * 0.75 + amb * 0.8), saturate(0.5 * bandw) * k);
                }
                // (the crater's floor glowing in cracks and seams, white-orange to a dull red, cooling over ten seconds)
                let rc = length((rel - (C + bm.xyz)).xz);
                // (the crater as carpet.rs digs it: 12.5 across a size (the last's 21), 8 deep (10.6))
                let crr = select(12.5, 21.0, big) * s;
                let cdp = select(8.0, 10.6, big) * s;
                if (rc < crr * 1.1 && abs(rel.y - (C.y + bm.y) + 0.5 * cdp) < 0.5 * cdp + 3.0) {
                    let w = rel + cam;
                    let cr = smoothstep(0.56, 0.8, gnoise3(vec3<f32>(w.xz / 1.7, f32(b) * 3.1))) + 0.35 * smoothstep(0.45, 0.75, gnoise3(vec3<f32>(w.xz / 4.0, 3.0 + f32(b))));
                    let cool = exp(-a / 3.5);
                    let tc = mix(vec3<f32>(0.8, 0.1, 0.02), vec3<f32>(3.0, 1.35, 0.3), cool);
                    col = col + tc * cr * smoothstep(crr, crr * 0.35, rc) * (0.12 + 0.88 * cool) * smoothstep(0.0, 0.3, a) * exp(-a / 9.0) * k;
                }
            }
        }
    }
    // ---- the last blast's cloud's shadow on the land (a cheap one: the sun's ray from the land past its dome) ---------
    if (stage != 1u && !sky && have && latest == lastb && L.y > 0.05 && frame.mod_params[3].w < 0.5) {
        let bm = cp_bomb(lastb);
        let a = time - bm.w;
        let dm = cp_body_dim(a, cp_size(lastb));
        let mid = C + bm.xyz + vec3<f32>(0.0, 0.5 * dm.y, 0.0) + cp_wind() * (0.4 * a) - rel;
        let along = max(dot(mid, L), 0.0);
        let off = length(mid - L * along);
        let thin = 1.0 - smoothstep(16.0, 30.0, a);
        let sh = smoothstep(dm.x * 1.1, dm.x * 0.45, off) * smoothstep(0.2, 1.0, a) * thin;
        col = col * (1.0 - 0.55 * sh * sun_up * k * fade);
    }

    // ---- the contrail: two thin white lines high over the land along the stick's way, laid as the bomber goes over,
    // spreading, breaking up and thinning over half a minute; the bombs come out of the haze under its head ------------
    if (stage != 1u && have) {
        let dir2 = cp_dir();
        let vb = max(cp_w(10u), 1.0);
        let shead = cp_plane_along(time);
        // (laid only where it has flown since it came out of the haze)
        let sfrom = max(shead - 2600.0, cp_plane_along(cp_w(14u)));
        let dir = vec3<f32>(dir2.x, 0.0, dir2.y);
        let side = vec3<f32>(-dir2.y, 0.0, dir2.x);
        var ctau = 0.0;
        var cc = vec3<f32>(0.0);
        for (var e = 0; e < 4; e = e + 1) {
            // (from its four engine pods, under its wings)
            let eo = select(select(9.0, 16.0, e == 3), select(-16.0, -9.0, e == 1), e < 2);
            let o = C + vec3<f32>(cp_w(8u), CP_HB + 1.0, cp_w(9u)) + side * eo;
            let pa = o + dir * sfrom;
            let pb = o + dir * max(shead - 14.0 - 0.25 * vb, sfrom + 1.0);
            let h = ray_seg(rd, pa, pb);
            if (h.y > scene_len) {
                continue;
            }
            // (its age where the ray passes it: laid at the head, older back along it)
            let span = max(shead - 14.0 - 0.25 * vb - sfrom, 1.0);
            let age = (1.0 - h.z) * span / vb + 0.25;
            let wdt = 0.9 + 0.9 * sqrt(age) + h.y * px_a * 0.6;
            let sl = shead - (1.0 - h.z) * span;
            let nb = gnoise3(vec3<f32>(sl / 24.0, f32(e) * 7.0, age * 0.02));
            let brk = saturate((nb - 0.08 - 0.35 * smoothstep(8.0, 40.0, age)) * 2.5);
            let dens = exp(-pow(h.x / wdt, 2.0)) * min((0.9 + 0.9 * sqrt(age)) / wdt, 1.0) * brk * exp(-age / 28.0) * smoothstep(0.0, 1.0, age);
            ctau = ctau + dens * 0.35;
            cc = cc + dens * 0.35 * (vec3<f32>(0.92, 0.93, 0.95) * (sunc * 0.8 + amb * 0.9));
        }
        if (ctau > 0.0) {
            let al = (1.0 - exp(-ctau)) * k * fade;
            col = mix(col, mix(cc / ctau, haze_c, 0.35), al);
        }
        // ---- the bomber: a swept-wing heavy bomber's dark shape high over the land, flying the line, coming out of the
        // haze before the first bomb and on steadily after the last, fading off; seen from below, against the sky ----
        if (rd.y > 1.0e-3 && C.y + CP_HB > 0.0) {
            let tp = (C.y + CP_HB) / rd.y;
            if (tp < scene_len) {
                let hp = rd * tp - (C + vec3<f32>(cp_w(8u), CP_HB, cp_w(9u)) + dir * shead);
                let al = dot(hp.xz, dir2);
                let ax = abs(dot(hp.xz, vec2<f32>(-dir2.y, dir2.x)));
                // (its outline as a B-52's, 48 long and 56 across: fuselage, wings swept back to thin tips, the
                // tailplane, four engine pods under the wings)
                let fus = max(abs(al + 2.0) - 24.0, ax - 1.8 * (1.0 - 0.5 * smoothstep(14.0, 26.0, abs(al + 2.0))));
                let wing = max(abs(al - (4.0 - 0.62 * ax)) - mix(9.0, 2.6, saturate(ax / 28.0)), ax - 28.0);
                let tail = max(abs(al - (-22.0 - 0.55 * ax)) - mix(3.2, 1.2, saturate(ax / 9.0)), ax - 9.0);
                let pod1 = length(vec2<f32>(al - (6.0 - 0.62 * 9.0), ax - 9.0) / vec2<f32>(3.2, 0.9)) - 1.0;
                let pod2 = length(vec2<f32>(al - (6.0 - 0.62 * 16.0), ax - 16.0) / vec2<f32>(3.2, 0.9)) - 1.0;
                let sd = min(min(fus, wing), min(tail, min(pod1, pod2) * 0.9));
                let fpx = max(tp * px_a, 0.05);
                let cov = saturate(0.5 - sd / fpx);
                if (cov > 0.0) {
                    // (out of the haze as it comes, into it as it goes: never popping in or out)
                    let showb = smoothstep(cp_w(14u), cp_w(14u) + 2.0, time) * (1.0 - smoothstep(cp_bomb(lastb).w - 1.0, cp_bomb(lastb).w + 2.5, time));
                    // (dark from below, a glint of the sun off it, greyed by the air between)
                    let glint = pow(saturate(dot(reflect(rd, vec3<f32>(0.0, -1.0, 0.0)), L)), 30.0) * 2.0;
                    var bc = vec3<f32>(0.07, 0.075, 0.085) * (amb * 1.3 + sunc * 0.15) + sunc * glint * 0.4;
                    bc = mix(bc, haze_c, saturate((1.0 - exp(-tp / 1500.0)) * 0.85 + 0.04));
                    col = mix(col, bc, cov * showb * k * fade);
                }
            }
        }
    }

    // ---- the blasts' smoke: the three latest's bodies raymarched together, self-shadowed towards the sun, fire in each
    // as it bursts; older ones let go into the line's dust as the next ones come ------------------------------------------
    if (stage == 2u) {
        col = col * up.a + up.rgb;
    }
    var col_t = select(1.0e9, up_t, stage == 2u);
    var lit: CpLit;
    if (stage != 2u) {
        lit = cp_lights(C, time, latest, lastb);
    }
    // (how much of what lies behind the smoke and the dust still shows through: the fires behind them veiled by it)
    var veil = select(1.0, up.a, stage == 2u);
    if (stage != 2u && have && latest >= 0) {
        // (the three latest, their middles camera-relative, ages and sizes; each let go before the third after it lands)
        var B0 = vec4<f32>(0.0);
        var B1 = vec4<f32>(0.0);
        var B2 = vec4<f32>(0.0);
        var S0 = vec2<f32>(1.0, 0.0);
        var S1 = vec2<f32>(1.0, 0.0);
        var S2 = vec2<f32>(1.0, 0.0);
        var h0 = 0u;
        var h1 = 0u;
        var h2 = 0u;
        var lo = vec2<f32>(1.0e9, -1.0);
        for (var j = 0; j < 3; j = j + 1) {
            let b = latest - j;
            if (b < 0) {
                continue;
            }
            let bm = cp_bomb(b);
            let a = time - bm.w;
            let s = cp_size(b);
            var w = 1.0;
            if (b + 3 < n) {
                let until = cp_bomb(b + 3).w - bm.w;
                w = 1.0 - smoothstep(until - 1.6, until - 0.05, a);
            }
            // (the last one's lingers, thinning away)
            w = w * (1.0 - select(smoothstep(15.0, 28.0, a), smoothstep(24.0, 34.0, a), b == lastb));
            if (w <= 0.0) {
                continue;
            }
            let Bv = vec4<f32>(C + bm.xyz, a);
            let Sv = vec2<f32>(s, w);
            let hv = u32(cp_w(CP_B + CP_BW * u32(b) + 6u)) + seed * 7u;
            let dm = cp_body_dim(a, s);
            var iv = cp_sphere(rd, Bv.xyz + cp_wind() * (0.4 * a) + vec3<f32>(0.0, 0.4 * dm.y, 0.0), max(dm.x * 1.45, dm.y * 1.2 + dm.z) + 16.0);
            if (b == lastb) {
                let wl = cp_wind();
                let wdir = select(vec3<f32>(1.0, 0.0, 0.0), wl / max(length(wl), 1.0e-4), length(wl) > 0.05);
                iv = cp_sphere(rd, Bv.xyz + vec3<f32>(0.0, 0.45 * dm.y, 0.0) + wdir * (0.5 * dm.z), max(dm.x * 1.6, 0.65 * dm.y) + 0.6 * dm.z + 30.0);
            }
            if (iv.y > iv.x) {
                lo = vec2<f32>(min(lo.x, iv.x), max(lo.y, iv.y));
            }
            if (j == 0) {
                B0 = Bv;
                S0 = Sv;
                h0 = hv;
            } else if (j == 1) {
                B1 = Bv;
                S1 = Sv;
                h1 = hv;
            } else {
                B2 = Bv;
                S2 = Sv;
                h2 = hv;
            }
        }
        let t1 = min(lo.y, scene_len);
        if (t1 > lo.x) {
            var t = lo.x;
            var tr = 1.0;
            var acc = vec3<f32>(0.0);
            let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
            let ph = 0.8 + (0.5 + 1.6 * warm) * pow(saturate(dot(rd, L)), 5.0);
            var tmid = 0.0;
            var wmid = 0.0;
            var lc = 1.0;
            var nl = 0;
            for (var i = 0; i < 64; i = i + 1) {
                if (t > t1 || tr < 0.04) {
                    break;
                }
                let p = rd * t;
                let bd = cp_bodies(p, B0, S0, h0, B1, S1, h1, B2, S2, h2);
                if (bd.x > 32.0) {
                    t = t + bd.x - 27.0;
                    continue;
                }
                var Bn = B0;
                var Sn = S0;
                if (bd.y > 1.5) {
                    Bn = B2;
                    Sn = S2;
                } else if (bd.y > 0.5) {
                    Bn = B1;
                    Sn = S1;
                }
                let a = Bn.w;
                let lsc = select(1.0, 1.9, Sn.x > 1.4);
                let st = max(1.6 * lsc, t * 0.006) * (0.75 + 0.5 * j);
                let sd = cp_lumps(p, bd.x, a, true, lsc);
                let fsoft = select(0.0, smoothstep(14.0, 26.0, a), Sn.x > 1.4);
                let ramp = saturate(-sd.x / (1.2 + 3.0 * smoothstep(1.0, 6.0, a) + 14.0 * fsoft));
                var den = ramp * mix(saturate(0.2 + 1.6 * sd.z), 1.0, ramp * ramp) * Sn.y;
                if (den > 0.002) {
                    // (the sun through the rest of the bodies: two looks towards it, looked for afresh while what lies
                    // behind still shows through, then kept)
                    if (tr > 0.3 || nl == 0) {
                        let s1 = saturate((5.0 - cp_bodies(p + L * 7.0, B0, S0, h0, B1, S1, h1, B2, S2, h2).x) / 14.0);
                        let s2 = saturate((4.0 - cp_bodies(p + L * 20.0, B0, S0, h0, B1, S1, h1, B2, S2, h2).x) / 20.0);
                        lc = exp(-(s1 * 9.0 + s2 * 14.0) * 0.3);
                    }
                    nl = nl + 1;
                    let hy = saturate((p.y - Bn.y) / max(cp_body_dim(a, Sn.x).y * 1.3, 1.0));
                    // (dark smoke from the charge, browned and greyed by the dust it carries up, paler as it ages and
                    // as it settles into the dust; creases a little shaded)
                    let ao = 0.6 + 0.4 * sd.y;
                    let young = exp(-a / 3.0);
                    let alb = mix(vec3<f32>(0.45, 0.4, 0.33), vec3<f32>(0.16, 0.14, 0.125), young * (0.5 + 0.5 * hy)) * (0.9 + 0.2 * (sd.z - 0.5));
                    let skyg = mix(mix(skyl, vec3<f32>(dot(skyl, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.45), fogl, 0.15) * (1.0 - 0.35 * warm);
                    var c = alb * (skyg * (0.5 * ao * (0.4 + 0.6 * hy)) + vec3<f32>(0.2, 0.17, 0.13) * day * ao * (1.0 - 0.6 * warm) + sunc * vec3<f32>(0.95, 0.85, 0.72) * (1.05 * lc * saturate(0.25 + 0.75 * sd.y) * ph));
                    // (fire in it as it bursts, low and deep, dying fast; its underside lit by the crater's glow)
                    let core = exp(min(bd.x, 0.0) / (6.0 * Sn.x));
                    let fire = exp(-a / 0.2) * exp(-max(p.y - Bn.y, 0.0) / (6.0 * Sn.x + 14.0 * a)) * core;
                    c = c * (1.0 - saturate(fire * 2.0)) + vec3<f32>(3.4, 1.3, 0.25) * (0.55 + 0.6 * sd.y) * saturate(fire * 1.7);
                    c = c + vec3<f32>(1.2, 0.4, 0.08) * exp(-a / 0.35) * exp(-max(p.y - Bn.y, 0.0) / (4.0 * Sn.x)) * 0.4;
                    // (its base lit from under by the fires burning in the crater, steadily)
                    // (lit from inside by the blasts' glow as they go off: more in its thin fringe than deep in it)
                    c = c + cp_lit_at(lit, p) * (0.35 + 0.65 * (1.0 - sd.y)) * 0.35;
                    let fb = cp_burn(a, Sn.x > 1.4);
                    c = c + vec3<f32>(1.5, 0.55, 0.12) * fb * exp(-max(p.y - Bn.y, 0.0) / (2.5 * Sn.x)) * (0.3 + 0.4 * (1.0 - sd.y)) * 0.1;
                    let ext = den * 0.55 * st;
                    let al = 1.0 - exp(-ext);
                    acc = acc + tr * al * c;
                    tmid = tmid + tr * al * t;
                    wmid = wmid + tr * al;
                    tr = tr * (1.0 - al);
                }
                t = t + select(st, max(0.55 * sd.x, 0.35 * st), sd.x > 0.0);
            }
            if (tr < 0.999) {
                let dist = tmid / max(wmid, 1.0e-4);
                if (tr < 0.5) {
                    col_t = dist;
                }
                let ap = 1.0 - exp(-dist / 2600.0);
                let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, ap * 0.8);
                veil = veil * (1.0 - (1.0 - tr) * k * fade);
                if (stage == 0u) {
                    col = mix(col, ccol, (1.0 - tr) * k * fade);
                } else {
                    cp_over(&hc, ccol, (1.0 - tr) * k * fade);
                }
            }
        }
    }

    // ---- the line's dust: marched along the ray through the box round the line, over the land ---------------------------
    if (stage != 2u && have && latest >= 0) {
        let dir2 = cp_dir();
        let side2 = vec2<f32>(-dir2.y, dir2.x);
        // (the box round the line, in its own frame: along it from beyond the first to past the last, across it)
        let a0 = cp_w(6u) - 120.0;
        let a1 = cp_w(7u) + 175.0;
        let wide = 175.0;
        let o2 = -C.xz;
        let ra = vec2<f32>(dot(rd.xz, dir2), dot(rd.xz, side2));
        let oa = vec2<f32>(dot(o2, dir2), dot(o2, side2));
        let inv = 1.0 / select(ra, vec2<f32>(1.0e-6), abs(ra) < vec2<f32>(1.0e-6));
        let ta = (vec2<f32>(a0, -wide) - oa) * inv;
        let tb = (vec2<f32>(a1, wide) - oa) * inv;
        var t0 = max(max(min(ta.x, tb.x), min(ta.y, tb.y)), 0.0);
        var t1 = min(min(max(ta.x, tb.x), max(ta.y, tb.y)), min(min(scene_len, col_t), 1800.0));
        // (and the slab over the land's lowest and highest)
        var ylo = min(C.y, me.y) - 6.0;
        var yhi = max(C.y, me.y) + 40.0;
        if (cp_w(CP_HF) > 1.0) {
            ylo = min(ylo, C.y + cp_w(CP_HF + 2u) - 6.0);
            yhi = max(yhi, C.y + cp_w(CP_HF + 3u) + 40.0);
        }
        if (abs(rd.y) > 1.0e-5) {
            let ya = ylo / rd.y;
            let yb = yhi / rd.y;
            t0 = max(t0, min(ya, yb));
            t1 = min(t1, max(ya, yb));
        } else if (ylo > 0.0 || yhi < 0.0) {
            t1 = -1.0;
        }
        if (t1 > t0) {
            let ns = 22;
            var tr = 1.0;
            var acc = vec3<f32>(0.0);
            let j = ign(in.position.xy + vec2<f32>(0.0, fract(time * 5.0) * 53.0));
            for (var i = 0; i < ns; i = i + 1) {
                let u0 = (f32(i) + j) / f32(ns);
                let u1 = (f32(i) + j + 1.0) / f32(ns);
                let t = t0 + (t1 - t0) * u0 * u0;
                let dt = (t1 - t0) * (u1 * u1 - u0 * u0);
                let p = rd * t;
                let q = p - C;
                let h = q.y - cp_land(q.xz);
                if (h > 60.0 || h < -4.0) {
                    continue;
                }
                let dd = cp_dust(q, h, time, n);
                if (dd.x <= 0.0) {
                    continue;
                }
                let w = p + cam;
                let n1 = gnoise3(w * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -0.9 * time, 0.0));
                let n3 = gnoise3(w * (1.0 / 34.0) + vec3<f32>(0.0, -0.25 * time, 9.0));
                let hw = dd.y * (0.45 + 1.1 * n1) * (0.6 + 0.8 * n3);
                let upw = smoothstep(hw, hw * 0.3, h) * smoothstep(-4.0, 0.0, h);
                var den = dd.x * saturate(1.5 * n1 + 0.15) * (0.35 + 1.3 * n3) * upw;
                // (thin right round the eye: the lens and the air at the eye show it there instead)
                den = den * smoothstep(4.0, 45.0, t) * 0.16;
                if (den <= 0.0005) {
                    continue;
                }
                let al = 1.0 - exp(-den * dt);
                let lo = (0.45 + 0.55 * saturate(h / 8.0)) * (0.55 + 0.7 * n1);
                var dc = vec3<f32>(0.6, 0.53, 0.42) * (sunc * 0.7 * lo + amb * 0.6);
                dc = dc + cp_lit_at(lit, p) * 0.3;
                dc = mix(dc, haze_c, (1.0 - exp(-t / 2600.0)) * 0.7);
                acc = acc + tr * al * dc;
                tr = tr * (1.0 - al);
                if (tr < 0.02) {
                    break;
                }
            }
            let kf = k * fade;
            veil = veil * (1.0 - kf + kf * tr);
            if (stage == 0u) {
                col = mix(col, col * tr + acc, kf);
            } else {
                hc = vec4<f32>(hc.rgb * (1.0 - kf + kf * tr) + acc * kf, hc.a * (1.0 - kf + kf * tr));
            }
        }
    }
    // ---- the shockwave fronts: the last's as the Payload's, racing out at the speed of sound over the land and on
    // past the player; the small ones' smaller and quicker, rippling out in turn (the two latest at most) -------------
    if (stage != 2u && have && latest >= 0) {
        var ylo = min(C.y, me.y) - 6.0;
        var yhi = max(C.y, me.y) + 45.0;
        if (cp_w(CP_HF) > 1.0) {
            ylo = min(ylo, C.y + cp_w(CP_HF + 2u) - 6.0);
            yhi = max(yhi, C.y + cp_w(CP_HF + 3u) + 45.0);
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
        let jf = ign(in.position.xy + vec2<f32>(0.0, fract(time * 5.0) * 53.0));
        let dcol = vec3<f32>(0.62, 0.55, 0.34) * sunc * 0.75;
        for (var j = 0; j < 3; j = j + 1) {
            let b = select(latest - j, lastb, j == 2);
            if (b < 0 || (j < 2 && b == lastb) || (j == 2 && latest != lastb)) {
                continue;
            }
            let bm = cp_bomb(b);
            let a = time - bm.w;
            let big = b == lastb;
            if (a <= 0.0 || a > select(1.2, 32.0, big)) {
                continue;
            }
            let s = cp_size(b);
            let amp = select(0.55 * (1.0 - smoothstep(0.55, 1.15, a)), 1.0, big);
            let fr = cp_front_march(rd, C, C + bm.xyz, a, amp, select(0.55 * s, 1.0, big), select(3.0, 1.0, big), select(12.0 * s, 32.0, big), t0, t1, jf, dcol, amb);
            if (fr.w < 0.999) {
                let kf = k * fade;
                veil = veil * (1.0 - kf + kf * fr.w);
                if (stage == 0u) {
                    col = mix(col, col * fr.w + fr.rgb, kf);
                } else {
                    hc = vec4<f32>(hc.rgb * (1.0 - kf + kf * fr.w) + fr.rgb * kf, hc.a * (1.0 - kf + kf * fr.w));
                }
            }
        }
    }
    if (stage == 1u) {
        return CpOut(hc, vec4<f32>(min(scene_len, 6.0e4), min(col_t, 6.0e4), 0.0, 0.0));
    }
    let lim = min(scene_len, col_t);

    // ---- the fires: in and round each crater, and spot fires out on the flattened land (brush and felled trees burning),
    // embers rising off them and drifting, and the sparks thrown as each bomb goes off --------------------------------
    if (have && latest >= 0) {
        let jf = ign(in.position.xy + vec2<f32>(fract(time * 3.0) * 71.0, 13.0));
        var glow = vec3<f32>(0.0);
        for (var b = 0; b <= latest; b = b + 1) {
            let bm = cp_bomb(b);
            let a = time - bm.w;
            let big = b == lastb;
            let I = cp_burn(a, big);
            let s = cp_size(b);
            let Cb = C + bm.xyz;
            // (a cheap look first: nothing of this one's fires near the ray)
            let mc = Cb + vec3<f32>(0.0, 4.0, 0.0);
            let tm = max(dot(mc, rd), 0.0);
            let reach = select(45.0, 80.0, big) * s + 8.0;
            if (length(mc - rd * tm) > reach + 6.0 || tm - reach > lim) {
                continue;
            }
            if (I > 0.0) {
                let fr = select(13.75, 23.0, big) * s;
                glow = glow + cp_flames(rd, Cb, fr, select(6.0 + 4.0 * s, 10.0 + 4.0 * s, big), select(8.0, 10.6, big) * s, lim, jf, time, f32(b) * 7.3, I);
                // (spot fires out where the blast swept: brush and the trees it felled)
                for (var f = 0u; f < 4u; f = f + 1u) {
                    let hk = u32(b) * 8u + f;
                    let ang = TAU * mh(hk, seed, 0x701u);
                    let rr = select(35.0, 71.0, big) * s * (0.4 + 0.65 * mh(hk, seed, 0x702u));
                    let off = vec2<f32>(cos(ang), sin(ang)) * rr;
                    let gq = bm.xz + off;
                    let sc = C + vec3<f32>(gq.x, cp_land(gq), gq.y);
                    let start = rr / CP_V + 0.4 + 1.2 * mh(hk, seed, 0x703u);
                    let life = 6.0 + 10.0 * mh(hk, seed, 0x704u);
                    let Is = smoothstep(start, start + 0.8, a) * (1.0 - smoothstep(life * 0.5, life, a));
                    glow = glow + cp_flames(rd, sc, 1.6 + 1.6 * mh(hk, seed, 0x705u), 2.5 + 4.0 * mh(hk, seed, 0x706u), 0.0, lim, jf, time, f32(hk) * 3.7, Is);
                }
                // (embers lifting off the fires on the heat, drifting with the wind, winking out)
                for (var e = 0u; e < 14u; e = e + 1u) {
                    let hk = u32(b) * 32u + e;
                    let per = 2.4 + 1.8 * mh(hk, seed, 0x711u);
                    let ea = fract((a + per * mh(hk, seed, 0x712u)) / per) * per;
                    let ang = TAU * mh(hk, seed, 0x713u);
                    let r0 = select(11.0, 19.0, big) * s * sqrt(mh(hk, seed, 0x714u));
                    let ph = TAU * mh(hk, seed, 0x715u);
                    let pe = Cb + vec3<f32>(cos(ang) * r0, 0.5 + ea * (2.5 + 3.0 * mh(hk, seed, 0x716u)) + 0.6 * ea * ea, sin(ang) * r0)
                        + cp_wind() * (0.8 * ea) + vec3<f32>(sin(ea * 2.1 + ph), 0.0, cos(ea * 1.7 + ph)) * 1.4 * ea;
                    let te = dot(pe, rd);
                    if (te < 1.0 || te > lim) {
                        continue;
                    }
                    let we = max(0.1, te * px_a * 0.7);
                    let oe = length(pe - rd * te);
                    if (oe > we * 3.0) {
                        continue;
                    }
                    let fl = 0.6 + 0.4 * sin(time * 23.0 + ph * 5.0);
                    glow = glow + vec3<f32>(3.6, 1.5, 0.35) * exp(-pow(oe / we, 2.0)) * min(0.1 / we, 1.0) * (1.0 - ea / per) * (1.0 - ea / per) * fl * I * 2.0;
                }
            }
            // (the sparks thrown as it goes off: bright streaks flung out and up, gone in under a second)
            if (a > 0.0 && a < 0.8) {
                for (var e = 0u; e < 20u; e = e + 1u) {
                    let hk = u32(b) * 64u + e;
                    let ang = TAU * mh(hk, seed, 0x721u);
                    let el = 0.25 + 1.1 * mh(hk, seed, 0x722u);
                    let sp = (50.0 + 70.0 * mh(hk, seed, 0x723u)) * sqrt(s);
                    let v = vec3<f32>(cos(ang) * cos(el), sin(el), sin(ang) * cos(el)) * sp;
                    let kk = 2.2;
                    let pa = Cb + vec3<f32>(0.0, 1.5, 0.0) + v * (1.0 - exp(-kk * a)) / kk - vec3<f32>(0.0, 9.0 * a * a, 0.0);
                    let a1 = max(a - 0.03, 0.0);
                    let pb = Cb + vec3<f32>(0.0, 1.5, 0.0) + v * (1.0 - exp(-kk * a1)) / kk - vec3<f32>(0.0, 9.0 * a1 * a1, 0.0);
                    let hs = ray_seg(rd, pa, pb);
                    if (hs.y > lim) {
                        continue;
                    }
                    let ws = max(0.12, hs.y * px_a * 0.6);
                    let lifeu = 1.0 - a / (0.4 + 0.4 * mh(hk, seed, 0x724u));
                    glow = glow + vec3<f32>(4.0, 2.8, 1.2) * exp(-pow(hs.x / ws, 2.0)) * min(0.12 / ws, 1.0) * saturate(lifeu) * saturate(lifeu) * 2.5;
                }
            }
        }
        col = col + glow * k * fade * (0.2 + 0.8 * veil);
    }

    // ---- the bombs: dark streaks coming down steeply, one after another, a faint thin trail of torn air behind each ----
    if (have) {
        let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
        var cov = 0.0;
        var vap = 0.0;
        for (var b = 0; b < n; b = b + 1) {
            let bm = cp_bomb(b);
            let since = time - cp_release(b);
            if (since <= 0.0 || time >= bm.w) {
                continue;
            }
            let s = cp_size(b);
            let pa = C + cp_fall(b, time);
            let pb = C + cp_fall(b, time - 0.035);
            let h = ray_seg(rd, pa, pb);
            if (h.y > lim + 2.0) {
                continue;
            }
            // (dropping out of its belly)
            let show = smoothstep(0.0, 0.15, since);
            let w = max(0.55 * s, h.y * px_a * 0.7);
            cov = max(cov, exp(-pow(h.x / w, 2.0)) * min(0.55 * s / w, 1.0) * show);
            // (the torn air behind it: a faint pale line along its last half second, thinning)
            let qa = C + cp_fall(b, max(time - 0.5, cp_release(b)));
            let hv = ray_seg(rd, pb, qa);
            if (hv.y < lim) {
                let wv = max(0.5 + 1.2 * hv.z, hv.y * px_a * 0.7);
                vap = max(vap, exp(-pow(hv.x / wv, 2.0)) * min((0.5 + 1.2 * hv.z) / wv, 1.0) * (1.0 - hv.z) * 0.22 * show);
            }
        }
        let bc = vec3<f32>(0.035, 0.034, 0.036) * (amb * 1.2 + sunc * 0.25);
        col = mix(col, vec3<f32>(0.85, 0.86, 0.88) * (sunc * 0.6 + amb * 0.8), vap * k);
        col = mix(col, bc, cov * k);
    }

    // ---- the rings: each blast's shock front racing out over the land, kicking up a thin low wall of dust --------------
    if (have && latest >= 0) {
        for (var b = max(latest - 3, 0); b <= latest; b = b + 1) {
            let bm = cp_bomb(b);
            let a = time - bm.w;
            let big = b == lastb;
            if (a <= 0.02 || a > select(1.6, 2.6, big)) {
                continue;
            }
            let s = cp_size(b) * select(1.0, 2.0, big);
            let rf = CP_V * a;
            let c2 = (C + bm.xyz).xz;
            let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
            let bb = -dot(rd.xz, c2);
            let disc = bb * bb - a2 * (dot(c2, c2) - rf * rf);
            if (disc <= 0.0) {
                continue;
            }
            let sq = sqrt(disc);
            for (var e = 0; e < 2; e = e + 1) {
                let t = (-bb + select(-sq, sq, e == 1)) / a2;
                if (t < 1.0 || t > lim) {
                    continue;
                }
                let p = rd * t;
                let q = p - C;
                let hg = q.y - cp_land(q.xz);
                let hr = s * (2.0 + 0.012 * rf);
                if (hg < -1.5 || hg > hr * 1.6) {
                    continue;
                }
                let radial = normalize(p.xz - c2);
                let gl = max(abs(dot(normalize(rd.xz), radial)), 0.22);
                let ang = atan2(radial.y, radial.x);
                let nb = gnoise3(vec3<f32>(cos(ang) * rf / 9.0, sin(ang) * rf / 9.0, a * 3.0 + f32(b)));
                let al = 0.3 * s * exp(-a / 0.5) * exp(-rf / (260.0 * s)) * smoothstep(hr * 1.6, hr * 0.2, hg) * smoothstep(-1.5, 0.0, hg) * saturate(nb * 1.6 - 0.2) / gl;
                let rc = vec3<f32>(0.62, 0.56, 0.45) * (sunc * 0.75 + amb * 0.7);
                col = mix(col, rc, saturate(al) * k * fade);
            }
        }
    }

    // ---- the debris: dark chunks and specks of earth, tumbling as they fly and fall back round each crater --------------
    if (have && latest >= 0) {
        let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
        let pxy = in.position.xy;
        var cov = 0.0;
        var hot = 0.0;
        var smk = 0.0;
        let wpx = 1.0 / fpx;
        for (var b = max(latest - 6, 0); b <= latest; b = b + 1) {
            let bm = cp_bomb(b);
            let a = time - bm.w;
            if (a <= 0.0 || a > 9.0) {
                continue;
            }
            let Cb = C + bm.xyz;
            // (none of its pieces near this pixel's ray: they fly at most some 140 blocks out and 90 up)
            let mc = Cb + vec3<f32>(0.0, 35.0, 0.0);
            let tm = max(dot(mc, rd), 0.0);
            let rch = select(150.0, 260.0, b == lastb) * cp_size(b);
            if (length(mc - rd * tm) > rch || tm - rch > lim) {
                continue;
            }
            let low = C.y + min(cp_w(CP_HF + 2u), bm.y) - 3.0;
            let cnt = select(CP_DPB, 3 * CP_DPB, b == lastb);
            for (var i = 0; i < cnt; i = i + 1) {
                var ch = cp_chunk(b * CP_DPB + i, a, Cb);
                if (ch.live <= 0.0 || ch.p.y < low) {
                    continue;
                }
                let dist = length(ch.p);
                if (dist > lim || dist < 1.0) {
                    continue;
                }
                let burning = mh(u32(b * CP_DPB + i), seed, 0x9a0u) < select(0.33, 0.6, b == lastb) && a < select(5.0, 8.0, b == lastb);
                let off = length(ch.p - rd * dot(ch.p, rd));
                if (off > ch.s * 4.0 + length(ch.v) * select(0.05, 0.5, burning) + 1.5 + 6.0 * dist * wpx) {
                    continue;
                }
                // (down once it reaches the land under it)
                let gq = ch.p - C;
                ch.live = smoothstep(cp_land(gq.xz) - 1.0, cp_land(gq.xz) + 1.5, gq.y);
                if (ch.live <= 0.0) {
                    continue;
                }
                let s0 = project_rel(ch.p);
                if (s0.z < 0.0) {
                    continue;
                }
                let q0 = s0.xy * frame.resolution.xy;
                let rad = max(ch.s * fpx / dist, 0.55);
                let s1 = project_rel(ch.p - ch.v * 0.03);
                let q1 = s1.xy * frame.resolution.xy;
                let ab = q1 - q0;
                // (a third of the pieces burning: glowing, trailing smoke)
                if (burning) {
                    let s2 = project_rel(ch.p - ch.v * 0.45 + vec3<f32>(0.0, 0.8, 0.0));
                    let q2 = s2.xy * frame.resolution.xy;
                    let tb = q2 - q0;
                    let uu = saturate(dot(pxy - q0, tb) / max(dot(tb, tb), 1.0e-4));
                    let wd = rad * (0.7 + 2.2 * uu) + 0.6;
                    let et = length(pxy - (q0 + tb * uu));
                    smk = max(smk, saturate(1.0 - et / wd) * (1.0 - uu) * 0.5 * ch.live * step(0.5, s2.z) * saturate(1.0 - a / select(5.0, 8.0, b == lastb)));
                }
                if (length(pxy - q0) > rad * 1.5 + length(ab) + 2.0) {
                    continue;
                }
                let w = saturate(dot(pxy - q0, ab) / max(dot(ab, ab), 1.0e-4));
                let e = length(pxy - (q0 + ab * w));
                let spin = a * cp_w(CP_DB + CP_DW * u32(b * CP_DPB + i) + 8u);
                let th = atan2(pxy.y - q0.y, pxy.x - q0.x);
                let lump = 1.0 + 0.28 * sin(th * 3.0 + f32(i) + spin) + 0.12 * sin(th * 5.0 - spin * 1.3);
                let cv = saturate(rad * lump + 0.5 - e) * ch.live * saturate(rad / max(length(ab) * 0.5, rad));
                cov = max(cov, cv);
                if (burning) {
                    hot = max(hot, cv * exp(-a / 2.5) * (0.75 + 0.25 * sin(time * 31.0 + f32(i))));
                }
            }
        }
        let dirt = vec3<f32>(0.035, 0.03, 0.026) * (amb * 1.5 + sunc * 0.3);
        let smoke = vec3<f32>(0.2, 0.19, 0.19) * (amb * 0.8 + sunc * 0.3);
        col = mix(col, smoke, smk * k * fade);
        col = mix(col, dirt, cov * k * fade);
        col = col + vec3<f32>(3.2, 1.2, 0.22) * hot * k * fade;
    }

    // ---- the last blast's dust at the eye: the picture greyed and flattened as it rolls over, muck on the lens --------
    if (have && latest == lastb) {
        let bm = cp_bomb(lastb);
        let a = time - bm.w;
        let s = cp_size(lastb);
        let Cf = C + bm.xyz;
        let rc = length(Cf.xz);
        let Rd = min(s * (52.0 * (1.0 - exp(-a / 1.0)) + 1.0 * min(a, 15.0)), cp_cap * 1.35);
        let hc0 = -Cf.y - cp_land(-C.xz);
        // (as the Payload's: from the moment its front reaches the eye, the air thick with it, clearing as it settles)
        let tfr = a - rc / CP_V;
        let E = max(smoothstep(-0.08, 0.05, tfr) * (0.6 * exp(-tfr / 0.8) + 0.4 * exp(-tfr / 3.5)) * smoothstep(2600.0, 900.0, rc),
                    0.6 * smoothstep(rc - 30.0, rc + 4.0, Rd) * (1.0 - smoothstep(9.0, 20.0, a)))
            * smoothstep(40.0, 8.0, hc0) * fade * k;
        if (E > 0.002) {
            let dust_c = vec3<f32>(0.5, 0.46, 0.4) * (sunc * 0.55 + amb * 0.8);
            let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
            col = mix(col, mix(vec3<f32>(lum), dust_c, 0.5), 0.26 * E);
            col = col * mix(vec3<f32>(1.0), vec3<f32>(1.03, 0.99, 0.93), E);
            let pxy = in.position.xy;
            let res = frame.resolution.xy;
            let film = gnoise3(vec3<f32>(pxy / (0.15 * res.y), 3.1)) * 0.8 + gnoise3(vec3<f32>(pxy / (0.07 * res.y), 7.7)) * 0.2;
            col = mix(col, dust_c, 0.12 * E * smoothstep(0.35, 0.95, film));
        }
        // (muck thrown on the lens as the front passes, far out of focus: the Payload's drops)
        let tau = a - rc / CP_V;
        // (only where its dust comes: close in front of it)
        let vis = smoothstep(40.0, 8.0, hc0) * smoothstep(2600.0, 900.0, rc) * smoothstep(40.0, 90.0, rc) * k;
        if (vis > 0.0 && tau > 0.2) {
            let pxy = in.position.xy;
            let res = frame.resolution.xy;
            var keep = 1.0;
            var shine = 0.0;
            for (var i = 0u; i < 12u; i = i + 1u) {
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
                for (var jj = 0u; jj < 4u; jj = jj + 1u) {
                    let hj = mh(i * 7u + jj, seed, 0x3e0u);
                    if (jj > 0u && hj > 0.3) {
                        continue;
                    }
                    let k2 = i * 7u + jj;
                    let rj = select(r * (0.22 + 0.3 * mh(k2, seed, 0x3e1u)), r, jj == 0u);
                    let ang = TAU * mh(k2, seed, 0x3e2u);
                    let cj = select(c + vec2<f32>(cos(ang), sin(ang)) * r * (1.4 + 0.9 * mh(k2, seed, 0x3e3u)), c, jj == 0u);
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
                    let op = (0.14 + 0.34 * pow(mh(k2, seed, 0x3e7u), 0.7)) * select(0.85, 1.0, jj == 0u);
                    keep = keep * (1.0 - ring * mott * op * life);
                    shine = shine + body * smoothstep(0.3, -0.9, dj.y / rj) * op * life;
                }
            }
            col = col * mix(1.0, keep, vis * fade)
                + vec3<f32>(0.42, 0.38, 0.33) * (sunc * 0.45 + amb * 0.9) * 0.4 * min(shine, 1.0) * vis * fade;
        }
    }

    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return CpOut(vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0), vec4<f32>(0.0));
    }
    return CpOut(vec4<f32>(srgb, 1.0), vec4<f32>(0.0));
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return carpetbomb(in, 0u, vec4<f32>(0.0), 1.0e9).c;
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): the blasts' smoke and the line's dust drawn at half the width
// and height by fs_half and laid over the full-size picture by fs_join, as the Payload's; a game without the stage
// compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct CpHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> CpHalf {
    let o = carpetbomb(in, 1u, vec4<f32>(0.0), 1.0e9);
    return CpHalf(o.c, o.e);
}

// The half-size stage at this pixel (whose ray goes `len` blocks): the four nearest of its pixels, each weighed by how
// near it is and by how near the depth it was marched to is to this pixel's (a joint bilateral upsample; payload.wgsl's
// pl_up). In .x of the second the smoke's distance of the one that counts most.
fn cp_up(pos: vec2<f32>, len: f32) -> CpOut {
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
        return CpOut(near_c, vec4<f32>(near_t, 0.0, 0.0, 0.0));
    }
    return CpOut(acc / sw, vec4<f32>(best_t, 0.0, 0.0, 0.0));
}

@fragment
fn fs_join(in: StageIn) -> @location(0) vec4<f32> {
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let u = cp_up(in.position.xy, len);
    return carpetbomb(in, 2u, u.c, select(u.e.x, 1.0e9, u.e.x >= 6.0e4)).c;
}
// [end half stage]
