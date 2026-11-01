// Orbital Laser's post pass for the Supercell (laser 12). Like the Payload's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, project_rel, bolt_line, mh, ign) less the other lasers' own functions,
// followed by this file, and sets it for a supercell strike only. Validate with tools/check-shader.sh.

// ---- laser 12: the supercell --------------------------------------------------------------------------------------
// No beam. The sky darkens; a storm cloud boils up over the target and spreads: a broad, low, dark deck, a slowly
// turning wall cloud hanging under its middle with ragged scud round it, a tower climbing out of it into an anvil that
// spreads downwind. Rain falls out of it in grey veils. Then the storm: lightning strikes all over the land under it,
// faster and faster, each bolt a branching channel from the cloud's base to the ground, re-striking a few times, the
// cloud lit from inside round its root and the land round its foot lit bright; flickers inside the cloud between. A few
// thin funnels come down out of the wall cloud, touch, wander over the land in a swirl of dust and lift back up (the
// vortex section). Then one colossal strike on the target: a thick knot of bolts, a blinding flash, a shockwave over the
// land and a jolt. Then the storm dies away.
// strike/storm.rs hands the bolts, the funnels' tracks and the flickers to the pass in its table (sc_table,
// render.set-data): keep the SC_* and VX_* in step.
const SC_FORMED: f32 = 9.0;        // the cloud is formed,
const SC_STORM0: f32 = 9.5;        // the bolts strike from here
const SC_STORM1: f32 = 42.0;       // to here,
const SC_FINALE: f32 = 45.0;       // the colossal strike,
const SC_CLEAR: f32 = 50.0;        // the storm dying away from here,
const SC_LEN: f32 = 64.0;          // and gone by the strike's end (lasers.rs's length)
const SC_B: u32 = 16u;             // the table: the bolts from SC_B, SC_BW words each (t, x, z off the middle, ground)
const SC_BW: u32 = 4u;
const SC_F: u32 = 400u;            // the funnels from SC_F, VX_W words each (vortex.rs's vx_words)
const VX_W: u32 = 148u;
const VX_DT: f32 = 0.5;
const VX_DOWN: f32 = 2.5;
const SC_K: u32 = 1024u;           // the flickers in the cloud from SC_K (t, x, z)
// The cloud's heights over the target's ground: the deck's base, the wall cloud's (lower, under its middle), the
// deck's top, the tower's, and the anvil's underside and top.
const SC_BASE: f32 = 80.0;
const SC_WALL: f32 = 46.0;
const SC_TOP: f32 = 150.0;
const SC_TOWER: f32 = 315.0;
const SC_ANV0: f32 = 270.0;
const SC_ANV1: f32 = 335.0;

fn sc_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn sc_have() -> bool {
    return arrayLength(&mod_data) > SC_K;
}

// ---- helpers (as payload.wgsl's) ------------------------------------------------------------------------------------
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}
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
// Cauliflower lumps (payload.wgsl's pl_dome): about 1 on a dome's crown, 0 in a crease.
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
    return mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971) * p;
}
fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// ---- the storm's life ---------------------------------------------------------------------------------------------
// How far it has formed (0 to 1 over the build-up), and how much of it is left as it dies away.
fn sc_form(t: f32) -> f32 {
    return smoothstep(0.0, SC_FORMED, t);
}
fn sc_fade(t: f32) -> f32 {
    return 1.0 - smoothstep(SC_CLEAR, SC_LEN - 1.0, t);
}
// How far out the deck reaches, and the anvil.
fn sc_deck_r(t: f32) -> f32 {
    return 70.0 + 230.0 * smoothstep(0.3, SC_FORMED + 2.0, t);
}
fn sc_anvil_r(t: f32) -> f32 {
    return -40.0 + 340.0 * smoothstep(5.0, SC_FORMED + 9.0, t);
}
// How heavily it rains (0 to 1).
fn sc_rain(t: f32) -> f32 {
    return smoothstep(5.0, 11.0, t) * (1.0 - smoothstep(SC_CLEAR - 1.0, SC_CLEAR + 3.0, t));
}
// The deck's base over the ground at r out (the wall cloud hangs lower under its middle).
fn sc_base(r: f32) -> f32 {
    return mix(SC_BASE, SC_WALL, 1.0 - smoothstep(28.0, 70.0, r));
}

// ---- the cloud ------------------------------------------------------------------------------------------------------
// The cloud's smooth body at q (off the target's ground): positive inside, about one per dozen blocks in.
fn sc_shape(q: vec3<f32>, t: f32) -> f32 {
    let r = length(q.xz);
    let form = sc_form(t);
    let base = sc_base(r) + 14.0 * (1.0 - form);
    // (it builds up from a dark, flat layer: its top climbing, the tower last)
    let tower = 1.0 - smoothstep(80.0, 175.0, r);
    let full = mix(SC_TOP, SC_TOWER, tower * smoothstep(1.5, 8.5, t));
    let top = base + (full - base) * (0.3 + 0.7 * smoothstep(0.0, 6.0, t));
    let deck = min(min(q.y - base, top - q.y) / 14.0, (sc_deck_r(t) - r) / 45.0);
    // (the anvil: flat, spreading downwind of the tower, thinning out at its edge, its underside sagging to its middle)
    let qa = q.xz - vec2<f32>(80.0 * form, 10.0 * form);
    let ra = length(qa * vec2<f32>(0.8, 1.0));
    let ar = sc_anvil_r(t);
    let sag = 18.0 * (1.0 - smoothstep(0.0, ar, ra));
    let anv = min(min(q.y - (SC_ANV0 + 12.0 * smoothstep(0.3, 1.0, ra / ar) - sag), SC_ANV1 - 14.0 * smoothstep(0.4, 1.0, ra / ar) - q.y) / 12.0, (ar - ra) / 60.0) - 3.0 * (1.0 - smoothstep(5.0, 8.0, t));
    // (and as it dies away it is eaten away from its edges in, thinning to nothing, not just fading)
    return max(deck, anv) - 1.8 * (1.0 - smoothstep(0.0, 4.0, t)) - 9.0 * pow(1.0 - sc_fade(t), 1.3);
}
// The cloud's density at q (0 to 1), its lumps turning with the storm (faster in close, where the wall cloud turns),
// boiling up the tower; and in .y how far up its lumps lie (0 in a crease, 1 on a crown).
fn sc_den(q: vec3<f32>, t: f32, fine: bool) -> vec2<f32> {
    let sh = sc_shape(q, t);
    if (sh < -2.6) {
        return vec2<f32>(0.0, 0.0);
    }
    let r = length(q.xz);
    let low = 1.0 - smoothstep(SC_TOP, SC_ANV0, q.y);
    let ang = 0.12 * t * 60.0 / (60.0 + r) * low;
    let qr = vec3<f32>(rot2(q.xz, -ang), q.y).xzy;
    let boil = vec3<f32>(0.0, -0.9 * t, 0.0);
    let n1 = gnoise3(pl_rot(0, qr * (1.0 / 75.0)) + boil * (1.0 / 75.0));
    let n2 = gnoise3(pl_rot(1, qr * (1.0 / 27.0)) + vec3<f32>(3.1, -0.03 * t, 7.7));
    var d = sh + (n1 - 0.5) * 2.6 + (n2 - 0.5) * 1.2;
    var crown = 0.5;
    // (the tower's and the anvil's edges in cauliflower lumps, boiling)
    let tw = (1.0 - smoothstep(80.0, 180.0, r)) * smoothstep(SC_TOP - 20.0, SC_TOP + 20.0, q.y);
    if (fine && d > -1.2 && d < 1.0) {
        if (tw > 0.01) {
            crown = pl_dome(pl_rot(0, (qr + boil * 1.3) * (1.0 / 24.0)));
            d = d + (crown - 0.45) * 1.8 * tw;
        }
        let n3 = gnoise3(qr * (1.0 / 8.0) + vec3<f32>(0.0, -0.12 * t, 0.0));
        d = d + (n3 - 0.5) * 0.7;
    }
    // (ragged scud under the base round the wall cloud: wisps hanging lower, turning faster)
    let base = sc_base(r);
    let scud = (1.0 - smoothstep(30.0, 110.0, r)) * smoothstep(base - 26.0, base - 4.0, q.y) * (1.0 - smoothstep(base - 4.0, base + 4.0, q.y));
    if (scud > 0.01) {
        let qs = vec3<f32>(rot2(q.xz, -0.3 * t * 50.0 / (50.0 + r)), q.y).xzy;
        let ns = gnoise3(qs * (1.0 / 14.0) + vec3<f32>(5.0, 0.0, 1.0));
        d = max(d, (ns - 0.62) * 6.0 * scud * sc_form(t));
    }
    return vec2<f32>(saturate(d * 0.9) * sc_fade(t), crown);
}

// A flash lighting the cloud (camera-relative point, how bright).
struct ScFlash {
    p: array<vec4<f32>, 3>,
}

// ---- the bolts ------------------------------------------------------------------------------------------------------
// How bright bolt (or the finale) is `a` seconds after it strikes: its leader, then a return stroke and one or two
// more, as vanilla's re-strike, the channel glowing faintly between.
fn sc_stroke(a: f32, n: u32) -> f32 {
    if (a < 0.0 || a > 0.9) {
        return 0.0;
    }
    var s = exp(-a / 0.05) * step(0.0, a);
    if (n >= 1u) {
        s = s + 0.8 * exp(-max(a - 0.13, 0.0) / 0.04) * step(0.13, a);
    }
    if (n >= 2u) {
        s = s + 0.6 * exp(-max(a - 0.3, 0.0) / 0.05) * step(0.3, a);
    }
    return s + 0.12 * exp(-a / 0.3);
}
// Bolt i: its foot (off the middle, on the ground) and when.
fn sc_bolt(i: u32) -> vec4<f32> {
    let o = SC_B + SC_BW * i;
    return vec4<f32>(sc_w(o + 1u), sc_w(o + 3u), sc_w(o + 2u), sc_w(o));
}
// Where a bolt's channel leaves the cloud over its foot f (off the middle): a little off to one side.
fn sc_root(f: vec3<f32>, i: u32, seed: u32) -> vec3<f32> {
    let a = TAU * mh(i, seed, 0x51u);
    let r = length(f.xz);
    return vec3<f32>(f.x + 22.0 * cos(a) * mh(i, seed, 0x52u), sc_base(r) + 4.0, f.z + 22.0 * sin(a) * mh(i, seed, 0x52u));
}
// A bolt from root a to foot b (camera-relative), drawn on the picture: its jagged channel and a few forks, hidden by
// what stands in front of it. x: the hot core, y: the glow.
fn sc_draw_bolt(px: vec2<f32>, a: vec3<f32>, b: vec3<f32>, seed: f32, wmul: f32, grow: f32, scene_len: f32) -> vec2<f32> {
    let pa = project_rel(a);
    let pb = project_rel(b);
    if (pa.z < 0.0 || pb.z < 0.0) {
        return vec2<f32>(0.0);
    }
    let res = frame.resolution.xy;
    let sa = pa.xy * res;
    let sb = pb.xy * res;
    let L = length(sb - sa);
    let dist = length(0.5 * (a + b));
    let focal = res.y / (2.0 * tan(frame.view_params.w * 0.5));
    let w = clamp(0.55 * focal / dist, 0.9, 7.0) * wmul;
    // (far from it on the picture: nothing to draw)
    let ab = sb - sa;
    let u0 = saturate(dot(px - sa, ab) / max(dot(ab, ab), 1.0));
    if (length(px - (sa + ab * u0)) > 0.32 * L + 30.0 * w) {
        return vec2<f32>(0.0);
    }
    var core = 0.0;
    var glow = 0.0;
    let m = bolt_line(px, sa, sb, seed, seed * 0.37, w);
    let bd = mix(length(a), length(b), m.z);
    let seen = select(0.0, 1.0, scene_len > bd - 3.0) * step(m.z, grow);
    core = core + m.x * seen;
    glow = glow + m.y * seen;
    let dir = ab / max(L, 1.0);
    let nrm = vec2<f32>(-dir.y, dir.x);
    for (var j = 0; j < 3; j = j + 1) {
        let fj = f32(j);
        let u = 0.18 + 0.22 * fj + 0.08 * fract(seed * 0.618 + fj * 0.37);
        if (u > grow) {
            continue;
        }
        let root = sa + ab * u + nrm * bolt_disp(L, u, seed, seed * 0.37);
        let side = select(-1.0, 1.0, fract(seed * 0.71 + fj * 0.53) > 0.5);
        let bdir = normalize(dir + nrm * side * (0.7 + 0.5 * fract(seed * 1.3 + fj)));
        let len = L * (0.18 + 0.14 * fract(seed * 0.9 + fj * 0.77));
        let f = bolt_line(px, root, root + bdir * len, seed + 5.0 + fj * 3.0, seed, w * 0.6);
        let fd = mix(length(a), length(b), u + f.z * 0.3);
        let fs = select(0.0, 1.0, scene_len > fd - 3.0) * step(u + f.z * (1.0 - u), grow + 0.05);
        core = core + f.x * fs * (1.0 - 0.6 * f.z);
        glow = glow + f.y * fs * 0.6;
    }
    return vec2<f32>(core, glow);
}

// ---- the vortex: a funnel let down out of the cloud (vortex.rs) --------------------------------------------------
// A thin rotating funnel: a tapered vortex from its foot on the land up to the wall cloud's base, curving a little, its
// surface wound in spiral bands that climb as it turns, a swirl of dust and debris round its foot while it touches.
// It comes down out of the cloud as a lowering cone, and lifts by roping out from the ground up. A full tornado scales
// it: vx_radius with the funnel's touch radius (and the cloud's base), the debris cloud's radius and height with it.
struct VxFunnel {
    foot: vec3<f32>,       // camera-relative
    top: vec3<f32>,
    low: f32,              // the share of it from the ground up not (yet, or any more) drawn
    touch: f32,            // how much it is on the land
    r: f32,                // its touch radius
    spin: f32,
}
fn vx_at(k: u32, t: f32, C: vec3<f32>) -> VxFunnel {
    var f: VxFunnel;
    let o = SC_F + VX_W * k;
    let t0 = sc_w(o);
    let t1 = sc_w(o + 1u);
    let n = max(i32(sc_w(o + 2u) + 0.5), 1);
    let u = clamp((t - t0) / VX_DT, 0.0, f32(n - 1));
    let i = min(i32(floor(u)), max(n - 2, 0));
    let fr = u - f32(i);
    let a = o + 4u + 3u * u32(i);
    let b = o + 4u + 3u * u32(min(i + 1, n - 1));
    let pa = vec3<f32>(sc_w(a), sc_w(a + 2u), sc_w(a + 1u));
    let pb = vec3<f32>(sc_w(b), sc_w(b + 2u), sc_w(b + 1u));
    let p = mix(pa, pb, fr);
    f.foot = C + p;
    // (its top in the wall cloud's base, lagging in towards the middle)
    f.top = C + vec3<f32>(p.x * 0.6 + 8.0 * sin(t * 0.21 + f32(k)), sc_base(length(p.xz) * 0.6) + 6.0, p.z * 0.6 + 8.0 * cos(t * 0.17 + f32(k)));
    let down = smoothstep(t0, t0 + VX_DOWN, t);
    let up = smoothstep(t1 - VX_DOWN, t1, t);
    f.low = max(1.0 - down, up);
    f.touch = smoothstep(t0 + 0.8 * VX_DOWN, t0 + VX_DOWN, t) * (1.0 - smoothstep(t1 - VX_DOWN, t1 - 0.8 * VX_DOWN, t));
    f.r = sc_w(o + 3u);
    f.spin = f32(k) * 2.1;
    if (t < t0 || t > t1) {
        f.low = 1.0;
    }
    return f;
}
// The funnel's radius at s of its way up (0 its foot, 1 its top), from its thin foot to the wide cone it hangs from.
fn vx_radius(f: VxFunnel, s: f32) -> f32 {
    return mix(1.1 + 0.35 * f.r, 11.0, pow(s, 2.4));
}
// The funnel's axis at s of its way up: curving off the straight line a little, swaying.
fn vx_axis(f: VxFunnel, s: f32, t: f32) -> vec3<f32> {
    let bend = vec3<f32>(sin(t * 0.37 + f.spin), 0.0, cos(t * 0.29 + f.spin)) * 7.0 * sin(3.14159 * s);
    return mix(f.foot, f.top, s) + bend;
}
// The funnel's density at camera-relative p (x), and its dust's (y).
fn vx_den(f: VxFunnel, p: vec3<f32>, t: f32) -> vec2<f32> {
    let H = max(f.top.y - f.foot.y, 10.0);
    let s = saturate((p.y - f.foot.y) / H);
    let ax = vx_axis(f, s, t);
    let e = (p - ax).xz;
    let d = length(e);
    let th = atan2(e.y, e.x);
    // (spiral bands winding up it, climbing as it turns; the funnel's edge shredded by them)
    let spin = t * 7.0 + f.spin;
    let bands = 0.5 + 0.5 * sin(3.0 * th - spin + p.y * 0.35);
    let n = gnoise3(vec3<f32>(cos(th) * 1.5, sin(th) * 1.5, p.y * 0.12 - t * 1.8) + vec3<f32>(f.spin));
    let rs = vx_radius(f, s) * (0.85 + 0.35 * n);
    let vis = smoothstep(f.low - 0.04, f.low + 0.04, s) * step(p.y, f.top.y + 4.0);
    var fun = smoothstep(rs, rs * 0.45, d) * (0.55 + 0.45 * bands) * vis;
    // (the cone it hangs from, merging into the cloud's base)
    fun = max(fun, smoothstep(0.75, 1.0, s) * smoothstep(rs * 1.3, rs * 0.5, d) * 0.35 * vis);
    // (the dust and debris whirled round its foot while it touches: a squat, ragged, turning cloud)
    var dust = 0.0;
    let hy = p.y - f.foot.y;
    if (f.touch > 0.01 && hy < 16.0) {
        let rd0 = (4.5 + 2.2 * f.r) * (0.75 + 0.5 * gnoise3(vec3<f32>(cos(th - t * 3.0) * 2.0, sin(th - t * 3.0) * 2.0, hy * 0.2 + f.spin)));
        let dd = length((p - f.foot).xz);
        dust = smoothstep(rd0, rd0 * 0.35, dd) * smoothstep(16.0, 1.0, hy) * smoothstep(-1.0, 1.0, hy) * f.touch;
        dust = dust * (0.5 + 0.5 * sin(2.0 * th - t * 9.0 + hy * 0.5 + f.spin));
    }
    return vec2<f32>(fun, dust);
}

// What the volumetric part has gathered: colour (premultiplied), transmittance, and its distance.
struct ScVol {
    c: vec4<f32>,
    t: f32,
}
fn sc_over(h: ptr<function, vec4<f32>>, c: vec3<f32>, x: f32) {
    *h = vec4<f32>((*h).rgb * (1.0 - x) + c * x, (*h).a * (1.0 - x));
}

// How the flashes light a point of the cloud.
fn sc_flash_at(fl: ScFlash, p: vec3<f32>) -> f32 {
    var e = 0.0;
    for (var j = 0; j < 3; j = j + 1) {
        let f = fl.p[j];
        if (f.w > 0.001) {
            let d = p - f.xyz;
            e = e + f.w / (1.0 + dot(d, d) * (1.0 / 3200.0));
        }
    }
    return e;
}

// The cloud, the rain and the funnels along the ray rd (camera-relative), as far as `scene_len`.
fn sc_volume(rd: vec3<f32>, scene_len: f32, C: vec3<f32>, time: f32, j: f32, fl: ScFlash, L: vec3<f32>, amb: vec3<f32>, sunc: vec3<f32>, fine: bool) -> ScVol {
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var tmid = 0.0;
    var wmid = 0.0;
    let fc = vec3<f32>(0.75, 0.8, 1.15);
    let form = sc_form(time);
    let fade = sc_fade(time);
    // ---- the cloud: marched between its lowest base and the anvil's top, inside its widest reach -------------------
    let reach = max(sc_deck_r(time), sc_anvil_r(time) + 110.0) + 40.0;
    let ylo = C.y + SC_WALL - 30.0;
    let yhi = C.y + SC_ANV1 + 15.0;
    var t0 = 0.0;
    var t1 = scene_len;
    if (abs(rd.y) > 1.0e-5) {
        let ta = (ylo - 0.0) / rd.y;
        let tb = (yhi - 0.0) / rd.y;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    } else if (0.0 < ylo || 0.0 > yhi) {
        t1 = -1.0;
    }
    // (and the cylinder of its reach)
    let oc = -C.xz;
    let dxz = rd.xz;
    let qa = dot(dxz, dxz);
    let qb = dot(oc, dxz);
    let qc = dot(oc, oc) - reach * reach;
    let disc = qb * qb - qa * qc;
    if (disc <= 0.0 || qa < 1.0e-8) {
        if (qc > 0.0) {
            t1 = -1.0;
        }
    } else {
        let sq = sqrt(disc);
        t0 = max(t0, (-qb - sq) / qa);
        t1 = min(t1, (-qb + sq) / qa);
    }
    if (t1 > t0 && form * fade > 0.001) {
        let n = select(36, 56, fine);
        let span = t1 - t0;
        // (short steps in the cloud, at most 96 of them: a long ray through it is only seen through so far)
        let dt0 = clamp(span / f32(n), 2.5, 7.0);
        var dt = dt0;
        var t = t0 + dt * j;
        let ph = 0.75 + 0.6 * pow(saturate(dot(rd, L)), 6.0);
        for (var i = 0; i < 96; i = i + 1) {
            if (t > t1 || acc.a < 0.03) {
                break;
            }
            let p = rd * t;
            let q = p - C;
            let sh = sc_shape(q, time);
            if (sh < -3.0) {
                // (empty air: leap on, short of where the lumps could reach)
                t = t + max(dt, (-sh - 2.6) * 11.0);
                continue;
            }
            // (thinned round the eye: from inside it, or flying through its scud, the storm round about still shows)
            let dn = sc_den(q, time, fine) * vec2<f32>(smoothstep(12.0, 70.0, t), 1.0);
            if (dn.x > 0.003) {
                let r = length(q.xz);
                let base = sc_base(r);
                let tower = 1.0 - smoothstep(80.0, 175.0, r);
                let top = mix(SC_TOP, SC_TOWER, tower);
                let h01 = saturate((q.y - base) / max(top - base, 1.0));
                // (lit from above: deep in it, and its underside, dark; a look towards the sun for its own lumps)
                var sun_t = exp(-min(max(top - q.y, 0.0), 110.0) * 0.022);
                if (fine) {
                    let q2 = q + L * 16.0;
                    sun_t = sun_t * exp(-saturate(sc_shape(q2, time) + 0.5) * 1.4);
                }
                let anvil = smoothstep(SC_ANV0 - 30.0, SC_ANV0 + 10.0, q.y);
                sun_t = max(sun_t, anvil * 0.7);
                // (storm-grey, its base green-black, the tower's tops pale)
                let alb = mix(mix(vec3<f32>(0.1, 0.14, 0.11), vec3<f32>(0.3, 0.33, 0.31), smoothstep(0.0, 0.35, h01)), vec3<f32>(0.6, 0.61, 0.63), smoothstep(0.35, 1.0, h01)) * (0.85 + 0.3 * dn.y);
                let e = sc_flash_at(fl, p);
                let ambg = mix(amb, vec3<f32>(dot(amb, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.65);
                let c = alb * (ambg * (0.45 + 0.55 * h01) * (2.0 - fade) + sunc * mix(0.6, sun_t, fade) * 0.85 * ph) + fc * e * (0.5 + 0.5 * alb);
                let ext = dn.x * 0.07 * dt * (0.35 + 0.65 * fade);
                let al = 1.0 - exp(-ext);
                sc_over(&acc, c, al);
                tmid = tmid + acc.a * al * t;
                wmid = wmid + acc.a * al;
            }
            dt = dt0 * (0.8 + 0.4 * fract(j + f32(i) * 0.618)) * select(1.0, 2.0, dn.x < 0.003 && sh < -1.0);
            t = t + dt;
        }
    }
    // ---- the rain: grey veils falling out of the base, streaked, heaviest under the forward part of the storm ----
    let rk = sc_rain(time) * fade;
    if (rk > 0.001) {
        let rr = sc_deck_r(time) * 0.78;
        let yb = C.y + SC_BASE;
        var r0 = 0.0;
        var r1 = scene_len;
        if (abs(rd.y) > 1.0e-5) {
            let ta = (C.y - 4.0) / rd.y;
            let tb = yb / rd.y;
            r0 = max(r0, min(ta, tb));
            r1 = min(r1, max(ta, tb));
        }
        let qc2 = dot(oc, oc) - rr * rr;
        let disc2 = qb * qb - qa * qc2;
        if (disc2 > 0.0 && qa > 1.0e-8) {
            let sq = sqrt(disc2);
            r0 = max(r0, (-qb - sq) / qa);
            r1 = min(r1, (-qb + sq) / qa);
        } else if (qc2 > 0.0) {
            r1 = -1.0;
        }
        r1 = min(r1, r0 + 700.0);
        if (r1 > r0) {
            let nr = 10;
            let dtr = (r1 - r0) / f32(nr);
            var tr = 1.0;
            var cr = vec3<f32>(0.0);
            for (var i = 0; i < nr; i = i + 1) {
                let t = r0 + (f32(i) + j) * dtr;
                let p = rd * t;
                let q = p - C;
                let r = length(q.xz);
                // (the shafts: streaks hanging from the base, swept by the wind, the wall cloud's middle drier)
                let sx = q.xz + vec2<f32>(0.25 * q.y, 0.0);
                let shaft = gnoise3(vec3<f32>(sx * (1.0 / 22.0), time * 0.08)) * 0.7 + gnoise3(vec3<f32>(sx * (1.0 / 6.0), q.y * 0.02 + time * 0.6)) * 0.3;
                var den = rk * smoothstep(0.42, 0.7, shaft) * (1.0 - smoothstep(rr * 0.6, rr, r)) * smoothstep(18.0, 50.0, length(q.xz - vec2<f32>(-20.0, 0.0)));
                den = den * smoothstep(-4.0, 6.0, q.y) * (1.0 - smoothstep(sc_base(r) - 10.0, sc_base(r), q.y));
                if (den > 0.001) {
                    let e = sc_flash_at(fl, p);
                    let c = vec3<f32>(0.36, 0.39, 0.42) * (amb * 0.8 + sunc * 0.15) + fc * e * 0.35;
                    let al = 1.0 - exp(-den * 0.012 * dtr);
                    cr = cr + tr * al * c;
                    tr = tr * (1.0 - al);
                }
            }
            // (the rain is under the cloud: in front of what the cloud gathered, for an eye under it)
            acc = vec4<f32>(cr + tr * acc.rgb, tr * acc.a);
            if (tr < 0.98 && wmid < 1.0e-3) {
                tmid = 0.5 * (r0 + r1);
                wmid = 1.0;
            }
        }
    }
    // ---- the funnels ---------------------------------------------------------------------------------------------------
    if (sc_have()) {
        let nf = u32(sc_w(2u) + 0.5);
        for (var k = 0u; k < min(nf, 4u); k = k + 1u) {
            let f = vx_at(k, time, C);
            if (f.low >= 0.999) {
                continue;
            }
            let sg = pl_ray_seg(rd, f.foot, f.top, 0.0, 1.0);
            if (sg.x > 22.0 + 6.0 * f.r || sg.y - 40.0 > scene_len) {
                continue;
            }
            let ft0 = max(sg.y - 40.0, 0.0);
            let ft1 = min(sg.y + 40.0, scene_len);
            let nn = select(18, 28, fine);
            let fdt = (ft1 - ft0) / f32(nn);
            var fa = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            var ftm = 0.0;
            for (var i = 0; i < nn; i = i + 1) {
                let t = ft0 + (f32(i) + j) * fdt;
                let p = rd * t;
                // (only under the cloud's base: inside it the cloud hides it, and its cone merges into the base)
                let qb = p - C;
                let dd = vx_den(f, p, time) * smoothstep(sc_base(length(qb.xz)) - 1.0, sc_base(length(qb.xz)) - 18.0, qb.y);
                let den = dd.x + dd.y;
                if (den > 0.002) {
                    let e = sc_flash_at(fl, p);
                    let s01 = saturate((p.y - f.foot.y) / max(f.top.y - f.foot.y, 1.0));
                    let fcol = mix(vec3<f32>(0.13, 0.15, 0.15), vec3<f32>(0.24, 0.26, 0.27), s01) * (1.0 - 0.45 * smoothstep(0.6, 1.0, s01));
                    let dcol = vec3<f32>(0.34, 0.28, 0.21);
                    let alb = (fcol * dd.x + dcol * dd.y) / den;
                    let c = alb * (amb * 1.1 + sunc * 0.12) + fc * e * 0.5 * alb;
                    let al = 1.0 - exp(-den * 0.55 * fdt);
                    sc_over(&fa, c, al);
                    ftm = ftm + t * al;
                    if (fa.a < 0.03) {
                        break;
                    }
                }
            }
            if (fa.a < 0.999) {
                // (under the cloud: in front of what the cloud gathered, unless the eye looks down through it)
                let ftd = ftm / max(1.0 - fa.a, 1.0e-3);
                let mid = tmid / max(wmid, 1.0e-4);
                if (wmid < 1.0e-3 || ftd < mid) {
                    acc = vec4<f32>(fa.rgb + fa.a * acc.rgb, fa.a * acc.a);
                } else {
                    acc = vec4<f32>(acc.rgb + acc.a * fa.rgb, fa.a * acc.a);
                }
                tmid = tmid + ftd * (1.0 - fa.a) * 4.0;
                wmid = wmid + (1.0 - fa.a) * 4.0;
            }
        }
    }
    var o: ScVol;
    o.c = acc;
    o.t = select(1.0e9, tmid / max(wmid, 1.0e-4), wmid > 1.0e-4);
    return o;
}

struct PlOut {
    c: vec4<f32>,
    e: vec4<f32>,
}

// The pass, in one of three stages: 0 the whole of it at full size (fs_main); 1 the half-size stage (fs_half: the
// cloud, the rain and the funnels, over a two by two of the picture's pixels), as premultiplied colour and
// transmittance; 2 the join (fs_join: the rest, sharp, at full size, with the half-size stage's `up` laid over).
fn supercell(in: StageIn, stage: u32, up: vec4<f32>) -> PlOut {
    var uv = in.uv;
    let time = now();
    let k = intensity_v();
    let seed = u32(seed_v());
    let anc = anchor_xz();
    let cam = frame.camera_position.xyz;
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;
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
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let form = sc_form(time) * sc_fade(time);
    let have = sc_have();

    // (the light, matched to the scene's: its sky, the sun's or the moon's)
    var skyl = srgb_to_linear(frame.sky_color.rgb);
    let amb0 = mix(vec3<f32>(0.02, 0.025, 0.035), skyl * 0.55 + vec3<f32>(0.03), day);
    let amb = amb0 * mix(1.0, 0.55, form);
    let sunc = (mix(vec3<f32>(1.25, 1.18, 1.05), vec3<f32>(1.4, 0.62, 0.3), warm) * sun_up + vec3<f32>(0.05, 0.07, 0.11) * moon) * mix(1.0, 0.6, form);

    // ---- the flashes: the bolts striking now and the flickers in the cloud, the three brightest kept for the cloud ---
    var fl: ScFlash;
    fl.p[0] = vec4<f32>(0.0);
    fl.p[1] = vec4<f32>(0.0);
    fl.p[2] = vec4<f32>(0.0);
    // (and the brightest bolt's own light on the land)
    var gflash = vec3<f32>(0.0);
    var sky_flash = 0.0;
    let tf = time - SC_FINALE;
    if (have) {
        let nb = u32(sc_w(0u) + 0.5);
        for (var i = 0u; i < min(nb, 96u); i = i + 1u) {
            let b = sc_bolt(i);
            let a = time - b.w;
            if (a < 0.0 || a > 0.9) {
                continue;
            }
            let I = sc_stroke(a, pcg(i ^ seed) % 3u);
            let root = C + sc_root(b.xyz, i, seed);
            let foot = C + b.xyz;
            let fp = vec4<f32>(root + vec3<f32>(0.0, 20.0, 0.0), I * 2.5);
            // (kept if brighter than the dimmest held)
            var lo = 0;
            if (fl.p[1].w < fl.p[lo].w) { lo = 1; }
            if (fl.p[2].w < fl.p[lo].w) { lo = 2; }
            if (fp.w > fl.p[lo].w) { fl.p[lo] = fp; }
            if (stage != 1u && !sky) {
                let dl = length(rel - foot);
                gflash = gflash + vec3<f32>(0.8, 0.85, 1.1) * I * 5.0 / (1.0 + dl * dl / 300.0);
            }
            sky_flash = sky_flash + I * 0.5 / (1.0 + length(foot) / 300.0);
        }
        let nk = u32(sc_w(3u) + 0.5);
        for (var i = 0u; i < min(nk, 64u); i = i + 1u) {
            let o = SC_K + 3u * i;
            let a = time - sc_w(o);
            if (a < 0.0 || a > 0.7) {
                continue;
            }
            // (a flicker: two or three quick pulses)
            let I = (exp(-a / 0.06) + 0.7 * exp(-max(a - 0.14, 0.0) / 0.05) * step(0.14, a) + 0.5 * exp(-max(a - 0.33, 0.0) / 0.06) * step(0.33, a)) * 1.6;
            let p = C + vec3<f32>(sc_w(o + 1u), SC_BASE + 40.0 + 60.0 * mh(i, seed, 0x61u), sc_w(o + 2u));
            let fp = vec4<f32>(p, I);
            var lo = 0;
            if (fl.p[1].w < fl.p[lo].w) { lo = 1; }
            if (fl.p[2].w < fl.p[lo].w) { lo = 2; }
            if (fp.w > fl.p[lo].w) { fl.p[lo] = fp; }
            sky_flash = sky_flash + I * 0.12 / (1.0 + length(p) / 300.0);
        }
    }
    // (the finale's: a knot of bolts on the target, blinding, lighting the cloud over it hard)
    var fin = 0.0;
    if (tf > 0.0 && tf < 1.6) {
        fin = exp(-tf / 0.09) + 0.8 * exp(-max(tf - 0.12, 0.0) / 0.07) * step(0.12, tf) + 0.7 * exp(-max(tf - 0.3, 0.0) / 0.08) * step(0.3, tf) + 0.5 * exp(-max(tf - 0.55, 0.0) / 0.1) * step(0.55, tf) + 0.15 * exp(-tf / 0.6);
        fl.p[0] = vec4<f32>(C + vec3<f32>(0.0, SC_WALL + 14.0, 0.0), fin * 2.2);
        if (stage != 1u && !sky) {
            let dl = length(rel - C);
            gflash = gflash + vec3<f32>(0.85, 0.88, 1.1) * fin * 14.0 / (1.0 + dl * dl / 900.0);
        }
        sky_flash = sky_flash + fin * 0.6 / (1.0 + length(C) / 400.0);
    }

    // ---- the land in the storm's gloom: darker and a little green under the cloud, and lit by the bolts --------------
    if (stage != 1u) {
        if (!sky) {
            let rr = length((rel - C).xz);
            let cover = form * (1.0 - smoothstep(sc_deck_r(time) * 0.75, sc_deck_r(time) * 1.05, rr));
            col = col * (1.0 - 0.3 * form - 0.42 * cover) * mix(vec3<f32>(1.0), vec3<f32>(0.9, 1.0, 0.94), cover);
            col = col + scene * gflash * k;
            // (the finale's shockwave: a ring of light and dust racing out over the land)
            if (tf > 0.0 && tf < 2.5) {
                let ring = exp(-pow((rr - 140.0 * tf) / 4.5, 2.0)) * exp(-tf / 0.9);
                col = col + (scene * 1.8 + vec3<f32>(0.18, 0.16, 0.13)) * ring * k;
            }
        } else {
            let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
            col = mix(col, vec3<f32>(lum) * vec3<f32>(0.92, 1.0, 0.95), 0.6 * form) * (1.0 - 0.62 * form);
        }
        // (everything flickering brighter with the flashes, the sky most)
        col = col + (scene * 0.5 + amb0 * 0.4 + vec3<f32>(0.01)) * vec3<f32>(0.8, 0.85, 1.1) * min(sky_flash, 2.5) * select(0.5, 1.0, sky) * k;
    }

    // ---- the cloud, the rain and the funnels -------------------------------------------------------------------------
    var vol_t = 1.0e9;
    var vol_a = 1.0;
    if (stage == 2u) {
        col = col * up.a + up.rgb;
        vol_a = up.a;
    } else if (time < SC_LEN) {
        let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
        let v = sc_volume(rd, scene_len, C, time, j, fl, L, amb, sunc, true);
        vol_t = v.t;
        vol_a = v.c.a;
        if (stage == 0u) {
            let kk = k;
            col = col * mix(1.0, v.c.a, kk) + v.c.rgb * kk;
        } else {
            let srgb_h = v.c;
            return PlOut(vec4<f32>(srgb_h.rgb * k, mix(1.0, srgb_h.a, k)), vec4<f32>(min(scene_len, 6.0e4), select(1.0e9, v.t, v.t < 1.0e8), 0.0, 0.0));
        }
    }

    // ---- the bolts, over it all (hidden by the cloud only for an eye above it) ----------------------------------------
    let cam_above = smoothstep(C.y + SC_TOP - 20.0, C.y + SC_TOP + 20.0, 0.0);
    let behind = mix(1.0, vol_a, cam_above);
    if (have) {
        let px = in.position.xy;
        let nb = u32(sc_w(0u) + 0.5);
        var core = 0.0;
        var glow = 0.0;
        for (var i = 0u; i < min(nb, 96u); i = i + 1u) {
            let b = sc_bolt(i);
            let a = time - b.w;
            if (a < 0.0 || a > 0.9) {
                continue;
            }
            let I = sc_stroke(a, pcg(i ^ seed) % 3u);
            let root = C + sc_root(b.xyz, i, seed);
            let foot = C + b.xyz;
            let m = sc_draw_bolt(px, root, foot, f32(pcg(i * 7u + seed) % 1000u) * 0.13 + 3.0, 1.0, saturate(a / 0.04), scene_len);
            core = core + m.x * I;
            glow = glow + m.y * I;
        }
        if (fin > 0.0) {
            for (var i = 0u; i < 5u; i = i + 1u) {
                let a = TAU * f32(i) / 5.0 + f32(seed % 7u);
                let foot = C + vec3<f32>(cos(a) * 2.0, 0.0, sin(a) * 2.0);
                // (one thick channel straight down, four thinner ones from further round the wall cloud joining it)
                let rr = select(34.0, 0.0, i == 0u);
                let root = C + vec3<f32>(cos(a) * rr, SC_WALL + 6.0, sin(a) * rr);
                let m = sc_draw_bolt(px, root, foot, f32(i) * 17.3 + f32(seed % 13u), select(1.3, 4.0, i == 0u), saturate(tf / 0.03), scene_len);
                core = core + m.x * fin;
                glow = glow + m.y * fin;
            }
        }
        col = col + (vec3<f32>(2.2, 2.3, 3.0) * min(core, 3.0) * 2.2 + vec3<f32>(0.45, 0.42, 1.0) * glow * 1.3) * behind * k;
    }
    // (the finale: the picture whited out for an instant, fading as the eye recovers, less from far off)
    if (tf > 0.0 && tf < 1.5) {
        let near = 1.0 / (1.0 + length(C) / 350.0);
        let wo = (0.6 * exp(-tf / 0.07) + 0.12 * exp(-tf / 0.5)) * near * k;
        col = mix(col, vec3<f32>(1.3, 1.32, 1.45), saturate(wo));
    }

    // (the rain close by is the game's own: the world's weather rains while the storm lasts, strike/storm.rs)

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

// ---- the finale's jolt: the picture slammed and shaken as its crack reaches the player (as nuke.wgsl's pl_jolt) ----
fn sc_jolt(in: StageIn) -> StageIn {
    let C = vec3<f32>(anchor_xz().x, block_y() + 1.0, anchor_xz().y);
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z);
    let dist = length(me - C);
    let s = now() - SC_FINALE - dist / 343.0;
    if (s <= 0.0 || s > 4.0 || intensity_v() <= 0.0) {
        return in;
    }
    let g = clamp(1.5 / (1.0 + dist / 200.0), 0.15, 1.0);
    let hit = 0.022 * g * exp(-s / 0.25) * smoothstep(0.0, 0.02, s);
    let ring = vec2<f32>(0.65 * sin(s * 47.0 + 0.6) + 0.35 * sin(s * 83.0 + 2.1), 0.65 * cos(s * 41.0 + 1.3) + 0.35 * sin(s * 71.0 + 0.4));
    let shud = 0.004 * g * exp(-s / 1.2) * smoothstep(0.05, 0.3, s);
    let sh = vec2<f32>(sin(s * 17.0 + 0.3), cos(s * 15.0 + 2.2));
    let off = ring * hit + sh * shud;
    let roll = 0.012 * g * exp(-s / 0.35) * sin(s * 37.0 + 0.9);
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    let zoom = 1.0 + 2.2 * (hit + shud) + 1.1 * abs(roll) * asp;
    var q = (in.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom;
    q = vec2<f32>(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll)) + off;
    var o = in;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}

@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    return supercell(sc_jolt(in0), 0u, vec4<f32>(0.0)).c;
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): the cloud, the rain and the funnels drawn at half the width and
// height by fs_half and laid over the full-size picture by fs_join (as payload.wgsl's); a game without the stages
// compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct PlHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> PlHalf {
    let o = supercell(in, 1u, vec4<f32>(0.0));
    return PlHalf(o.c, o.e);
}
// The half-size stage's at this pixel (whose ray goes `len` blocks): the four nearest, each weighed by how near it is
// and by how near the depth it was marched to is to this pixel's (a joint bilateral upsample, as payload.wgsl's pl_up).
fn sc_up(pos: vec2<f32>, len: f32) -> vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
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
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
        }
    }
    if (sw < 1.0e-3) {
        return near_c;
    }
    return acc / sw;
}
@fragment
fn fs_join(in0: StageIn) -> @location(0) vec4<f32> {
    let in = sc_jolt(in0);
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    return supercell(in, 2u, sc_up(in.position.xy, len)).c;
}
// [end half stage]
