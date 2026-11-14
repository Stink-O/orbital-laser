// The World Eater's body, after worldeater_path.wgsl. For worldeater.wgsl, after we_begin()
// (keep these and WeHit's first six fields; fields are only added at the end). Positions are from the camera.
//   we_body_hit(ro, rd, tmax, t) -> WeHit         the worm on the ray ro + rd d, d < tmax (WE_MISS: none)
//   we_body_colour(hit, rd, sun, t) -> vec3       its colour there, linear, lit
//   we_body_shade(p, sun, t) -> f32               the sun at p past the worm (1 lit, 0 in its shadow)
//   we_body_sd(p, t) -> f32                       signed distance to the worm's outside (a smooth tube and head)
//   we_eye_hit_at(eo, rd, tmax, t, es) -> WeHit   the eye's ray from eo; es: caught, the eye's s (we_eye_s(t)), else
//                                                 -1e9; caught: we_eye_hit_at(we_o + we_eye(t).xyz, rd, tmax, t,
//                                                 we_eye_s(t)); deep in the body only the throat round the eye
//   we_throat_miss() -> vec4                      caught, a ray that met nothing: rgb, a (1e9: out of the mouth)
//   we_throat_glow(s, t) -> vec3                  the light the throat's walls give off at path position s (linear)
//   we_throat_far(t) -> vec3                      the deep glow far down the throat, towards the head (we_eye_dir)

const WE_MISS: f32 = 1.0e9;

// ---- the knobs --------------------------------------------------------------------------------------------------
const WB_L: f32 = 17.0;
const WB_HEAD: f32 = 58.0;
const WB_HINGE: f32 = 40.0;
const WB_RT: f32 = 17.0;
const WB_RC: f32 = 27.5;
const WB_RB: f32 = 37.5;
const WB_NP: f32 = 12.0;
const WB_NECK: f32 = 240.0;
const WB_LOOK_MAX: f32 = 0.9;
const WB_PET_L: f32 = 46.0;
const WB_PET_R: f32 = 29.0;
const WB_PHI_SHUT: f32 = -0.52;
const WB_PHI_OPEN: f32 = 0.95;
const WB_PHI_GAPE: f32 = 1.32;
const WB_STRIP_B: f32 = 210.0;
const WB_LOD: f32 = 400.0;
const WB_SWAY: f32 = 4.5;
const WB_HEAVE: f32 = 2.5;
const WB_PERI: f32 = 2.0;
const WB_TEAL: vec3<f32> = vec3<f32>(0.10, 0.75, 0.80);
const WB_SOUL: vec3<f32> = vec3<f32>(0.25, 0.85, 1.6);

const WB_M_PLATE: u32 = 0u;   // the armour plates (stone)
const WB_M_JOINT: u32 = 1u;   // the joints between rings (tuff, deepslate)
const WB_M_SCULK: u32 = 2u;   // sculk in the seams and veins (glows teal)
const WB_M_TOOTH: u32 = 3u;   // teeth (bone, calcite, dripstone)
const WB_M_GUM: u32 = 4u;     // the mouth's rim
const WB_M_PETAL: u32 = 5u;   // a jaw petal's outside
const WB_M_PETAL_IN: u32 = 6u; // a jaw petal's inside (lit by the throat)
const WB_M_THROAT: u32 = 7u;  // the throat's wall (inside the body)
const WB_M_LAND: u32 = 8u;    // the land on its back (grass, dirt, oak)

const WB_B_TILES: u32 = 0u;
const WB_B_COBBLED: u32 = 1u;
const WB_B_PBLACK: u32 = 2u;
const WB_B_DBRICKS: u32 = 3u;
const WB_B_PBBRICKS: u32 = 4u;
const WB_B_CRACKED: u32 = 5u;
const WB_B_TUFF: u32 = 6u;
const WB_B_SCULK: u32 = 7u;
const WB_B_DEEPSLATE: u32 = 8u;
const WB_B_BONE: u32 = 9u;
const WB_B_CALCITE: u32 = 10u;
const WB_B_DRIP: u32 = 11u;
const WB_B_GRASS: u32 = 13u;
const WB_B_DIRT: u32 = 14u;
const WB_B_LEAVES: u32 = 15u;
const WB_B_LOG: u32 = 16u;
const WB_B_BLACK: u32 = 17u;
const WB_B_BASALT: u32 = 18u;
const WB_B_CHISEL: u32 = 19u;
const WB_B_PDEEP: u32 = 20u;
const WB_NB: u32 = 22u;
const WB_BK0: u32 = 4u;
const WB_BKW: u32 = 12u;

@group(0) @binding(8) var block_sprites: texture_2d_array<f32>;
@group(0) @binding(9) var block_sampler: sampler;

struct WeHit {
    d: f32,
    p: vec3<f32>,
    n: vec3<f32>,
    mat: u32,
    glow: f32,
    b: f32,
    blk: u32,
    face: u32,
    uv: vec2<f32>,
    ao: f32,
    sh: f32,
    mouth: f32,
    tone: f32,
    ns: vec3<f32>,
    inside: f32,
}

fn wb_miss() -> WeHit {
    return WeHit(WE_MISS, vec3<f32>(0.0), vec3<f32>(0.0, 1.0, 0.0), 0u, 0.0, 0.0, 0u, 2u, vec2<f32>(0.0), 1.0, 1.0, 0.0, 1.0, vec3<f32>(0.0, 1.0, 0.0), 0.0);
}

// ---- small things -------------------------------------------------------------------------------------------------
fn wb_hu(a: u32, b: u32, c: u32) -> u32 {
    return pcg(a ^ pcg(b ^ pcg(c + 0x9E3779B9u)));
}
fn wb_h(a: u32, b: u32, c: u32) -> f32 {
    return f32(wb_hu(a, b, c) >> 8u) * (1.0 / 16777216.0);
}
fn wb_hc(c: vec3<f32>, k: u32) -> f32 {
    let i = vec3<u32>(vec3<i32>(floor(c)) + vec3<i32>(8192));
    return wb_h(i.x ^ (k * 0x632BE5ABu), i.y + (i.z << 14u), k);
}
fn wb_rot(v: vec3<f32>, a: vec3<f32>, ang: f32) -> vec3<f32> {
    let c = cos(ang);
    let s = sin(ang);
    return v * c + cross(a, v) * s + a * dot(a, v) * (1.0 - c);
}

// ---- the path, as the body needs it: frames with a side that doesn't twist, curvature, life -----------------------
struct WbFr {
    p: vec3<f32>,
    x: vec3<f32>,
    y: vec3<f32>,
    z: vec3<f32>,
    k: vec3<f32>,
}

var<private> wb_ready: f32 = -1.0e9;
var<private> wb_ok: bool = false;
var<private> wb_n: u32 = 0u;
var<private> wb_sh: f32 = 0.0;
var<private> wb_s0: array<f32, 6>;
var<private> wb_s1: array<f32, 6>;
var<private> wb_pl: array<vec3<f32>, 6>;
var<private> wb_af: array<vec3<f32>, 6>;
var<private> wb_at: array<vec3<f32>, 6>;
var<private> wb_ad: array<vec4<f32>, 6>;
var<private> wb_open: f32 = 0.0;
var<private> wb_gape: f32 = 0.0;
var<private> wb_alpha: f32 = 0.0;
var<private> wb_axis: vec3<f32> = vec3<f32>(0.0, 1.0, 0.0);
var<private> wb_pivot: vec3<f32>;
var<private> wb_ho: vec3<f32>;
var<private> wb_hx: vec3<f32>;
var<private> wb_hy: vec3<f32>;
var<private> wb_hz: vec3<f32>;
var<private> wb_phi: array<f32, 6>;
var<private> wb_psi: vec3<f32>;
var<private> wb_glow: f32 = 0.0;
var<private> wb_strip_t: vec2<f32> = vec2<f32>(9.6, 14.0);
var<private> wb_t: f32 = 0.0;
// (0 at run time, unknown to the compiler: added to fixed loop counts so the driver doesn't unroll them)
var<private> wb_z: i32 = 0;
var<private> wb_zu: u32 = 0u;

fn wb_plane(i: u32) -> vec3<f32> {
    let dd = we_arch_to(i).xz - we_arch_from(i).xz;
    let d = dd / max(length(dd), 1.0e-4);
    return vec3<f32>(-d.y, 0.0, d.x);
}
fn wb_slerp_h(a: vec3<f32>, b: vec3<f32>, u: f32) -> vec3<f32> {
    let ang = atan2(a.z * b.x - a.x * b.z, dot(a, b));
    return wb_rot(a, vec3<f32>(0.0, 1.0, 0.0), ang * u);
}
fn wb_frame_of(p: vec3<f32>, x: vec3<f32>, z0: vec3<f32>, k: vec3<f32>) -> WbFr {
    let z = normalize(z0 - x * dot(z0, x));
    return WbFr(p, x, cross(z, x), z, k);
}
fn wb_fr(s: f32) -> WbFr {
    let n = wb_n;
    if (n == 0u) {
        return wb_frame_of(vec3<f32>(0.0, s, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0));
    }
    var ri = n;
    for (var i = 0u; i < n; i = i + 1u) {
        let s0 = wb_s0[i];
        let s1 = wb_s1[i];
        if (s < s0) {
            ri = i;
            break;
        }
        if (s <= s1) {
            let f = wb_af[i];
            let to = wb_at[i];
            let ad = wb_ad[i];
            let d = ad.xy;
            let ax = ad.z;
            let by = ad.w;
            let h = (s1 - s0) / f32(WE_TN);
            let xq = clamp((s - s0) / h, 0.0, f32(WE_TN));
            let k = min(u32(xq), WE_TN - 1u);
            let t0 = we_aw(i, WE_R_TH + k);
            let t1 = we_aw(i, WE_R_TH + k + 1u);
            let m0 = h / max(length(vec2<f32>(ax * sin(t0), by * cos(t0))), 1.0e-6);
            let m1 = h / max(length(vec2<f32>(ax * sin(t1), by * cos(t1))), 1.0e-6);
            let th = we_herm(t0, m0, t1, m1, xq - f32(k));
            let sn = sin(th);
            let cs = cos(th);
            let sh = to.y - f.y;
            let along = ax * (1.0 - cs);
            let p = vec3<f32>(f.x + d.x * along, f.y + sh * 0.5 * (1.0 - cs) + by * sn, f.z + d.y * along);
            let pt = vec3<f32>(d.x * ax * sn, sh * 0.5 * sn + by * cs, d.y * ax * sn);
            let ptt = vec3<f32>(d.x * ax * cs, sh * 0.5 * cs - by * sn, d.y * ax * cs);
            let l2 = max(dot(pt, pt), 1.0e-6);
            let tg = pt * inverseSqrt(l2);
            let kv = (ptt - tg * dot(ptt, tg)) / l2;
            return wb_frame_of(p, tg, wb_pl[i], kv);
        }
    }
    var side = wb_pl[n - 1u];
    if (ri == n) {
        let d = wb_at[n - 1u];
        return wb_frame_safe(vec3<f32>(d.x, d.y - (s - wb_s1[n - 1u]), d.z), vec3<f32>(0.0, -1.0, 0.0), side);
    }
    let rs = we_run_s(ri);
    let prev = select(wb_sign_plane(), wb_pl[max(ri, 1u) - 1u], ri > 0u);
    let len = wb_s0[ri] - rs;
    side = wb_slerp_h(prev, wb_pl[ri], we_ss(rs + min(50.0, 0.3 * len), wb_s0[ri] - min(50.0, 0.3 * len), s));
    if (s < rs) {
        let st = we_run_from(0u);
        let e = normalize(wb_af[0].xz - st.xz + vec2<f32>(1.0e-4, 0.0));
        let d = rs - s;
        return wb_frame_safe(vec3<f32>(st.x - e.x * d, we_run_y(0u), st.z - e.y * d), vec3<f32>(e.x, 0.0, e.y), side);
    }
    let q = we_run_at(ri, s - rs);
    return wb_frame_safe(q.p, q.t, side);
}
fn wb_sign_plane() -> vec3<f32> {
    return vec3<f32>(-we_sdir.y, 0.0, we_sdir.x);
}
fn wb_frame_safe(p: vec3<f32>, x: vec3<f32>, z0: vec3<f32>) -> WbFr {
    var z = z0;
    if (abs(dot(z0, x)) > 0.95) {
        z = normalize(cross(x, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
    }
    return wb_frame_of(p, x, z, vec3<f32>(0.0));
}

fn wb_sway(s: f32) -> vec2<f32> {
    var env = 0.0;
    var flick = 0.0;
    let b = wb_sh - s;
    let tail = wb_sh - WE_LEN;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        let s0 = wb_s0[i];
        let s1 = wb_s1[i];
        if (s >= s0 && s <= s1) {
            env = we_ss(8.0, 110.0, min(s - s0, s1 - s));
            let u = tail - s0;
            if (u > -6.0 && u < 600.0) {
                let m = clamp((b - (WE_LEN - 150.0)) / 150.0, 0.0, 1.0);
                let a = 10.0 * exp(-u / 120.0) * we_ss(-6.0, 20.0, u);
                flick = a * m * m * sin(m * 4.2 - u / 15.0) * we_ss(0.0, 30.0, s - s0);
            }
        }
    }
    let t = wb_t;
    let a1 = b * TAU / 320.0 - 1.7 * t + 1.3;
    let a2 = b * TAU / 130.0 + 2.3 * t;
    let a3 = b * TAU / 240.0 - 1.3 * t + 0.4;
    wb_sway_d = -env * vec2<f32>(WB_SWAY * cos(a1) * TAU / 320.0 + 1.4 * cos(a2) * TAU / 130.0, WB_HEAVE * cos(a3) * TAU / 240.0);
    let z = env * (WB_SWAY * sin(a1) + 1.4 * sin(a2)) + flick;
    let y = env * WB_HEAVE * sin(a3);
    return vec2<f32>(z, y);
}
var<private> wb_sway_d: vec2<f32>;

fn wb_bendw(b: f32) -> f32 {
    return we_ss(WB_NECK, WB_HINGE, b);
}

fn wb_frame(s: f32) -> WbFr {
    let f = wb_fr(s);
    let sw = wb_sway(s);
    let dw = wb_sway_d;
    var p = f.p + f.z * sw.x + f.y * sw.y;
    var x = normalize(f.x + f.z * dw.x + f.y * dw.y);
    var z = normalize(f.z - x * dot(f.z, x));
    var y = cross(z, x);
    var k = f.k;
    let b = wb_sh - s;
    if (wb_alpha > 1.0e-4 && b < WB_NECK) {
        let ang = wb_alpha * wb_bendw(b);
        p = wb_pivot + wb_rot(p - wb_pivot, wb_axis, ang);
        x = wb_rot(x, wb_axis, ang);
        y = wb_rot(y, wb_axis, ang);
        z = wb_rot(z, wb_axis, ang);
        k = wb_rot(k, wb_axis, ang);
        let da = wb_alpha * (wb_bendw(b - 1.0) - wb_bendw(b + 1.0)) * 0.5;
        k = k + cross(wb_axis, x) * da;
    }
    return WbFr(p, x, y, z, k);
}

fn wb_ring_b(k: i32) -> f32 {
    let b0 = WB_HEAD + (f32(k) + 0.5) * WB_L;
    return b0 + WB_PERI * sin(TAU * b0 / 110.0 - 2.6 * wb_t);
}
fn wb_taper(b: f32) -> f32 {
    return mix(0.22, 1.0, pow(we_ss(0.0, 150.0, WE_LEN - b), 0.7));
}
fn wb_strip(b: f32) -> f32 {
    if (b > WB_STRIP_B) {
        return 0.0;
    }
    return (1.0 - we_ss(wb_strip_t.x, wb_strip_t.y, wb_t)) * we_ss(WB_STRIP_B, 130.0, b);
}

fn wb_setup_core(t: f32) {
    if (t == wb_ready) {
        return;
    }
    wb_ready = t;
    wb_setup_lite(t);
    if (!wb_ok) {
        return;
    }
    for (var i = 0u; i < wb_n; i = i + 1u) {
        wb_s0[i] = we_arch_s0(i);
        wb_s1[i] = wb_s0[i] + we_arch_len(i);
        wb_pl[i] = wb_plane(i);
        let f = we_arch_from(i);
        let to = we_arch_to(i);
        let dd = to.xz - f.xz;
        let w = max(length(dd), 1.0e-4);
        wb_af[i] = f;
        wb_at[i] = to;
        wb_ad[i] = vec4<f32>(dd / w, 0.5 * w, we_arch_apex(i));
    }
}
// The part of the setup without the arches' tables (the caught eye's throat needs no more).
var<private> wb_ready_l: f32 = -1.0e9;
fn wb_setup_lite(t: f32) {
    if (t == wb_ready_l) {
        return;
    }
    wb_ready_l = t;
    wb_t = t;
    wb_z = select(0, 1, frame.time.x < -1.0);
    wb_zu = u32(wb_z);
    wb_n = we_n();
    wb_ok = wb_n > 0u;
    if (!wb_ok) {
        return;
    }
    wb_sh = we_head(t);
    var op = 0.0;
    var gp = 0.0;
    var lk = 0.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        let h = we_arch_hold(i);
        if (h.x >= 0.0) {
            op = max(op, we_ss(h.x - 0.35, h.x + 0.55, t) * (1.0 - we_ss(h.y - 0.25, h.y + 0.7, t)));
            lk = max(lk, we_ss(h.x - 0.7, h.x + 0.9, t) * (1.0 - we_ss(h.y - 0.2, h.y + 1.1, t)));
            let ti = we_arch_t_in(i);
            gp = max(gp, we_ss(ti - 1.15, ti - 0.3, t) * (1.0 - we_ss(ti + 0.05, ti + 0.6, t)));
        }
    }
    let spit = we_w(WE_BODY_T + 2u);
    if (spit > 0.0) {
        gp = max(gp, we_ss(spit - 0.7, spit - 0.15, t) * (1.0 - we_ss(spit + 0.9, spit + 1.7, t)));
    }
    wb_open = op;
    wb_gape = gp;
    wb_strip_t = vec2<f32>(we_arch_t_out(0u) + 0.6, max(14.0, we_arch_t_out(0u) + 3.0));
    wb_psi = vec3<f32>(0.14 * t, -0.19 * t + 0.3, 0.25 * t + 0.1);
    wb_glow = 0.25 + 1.2 * max(op, gp) + 0.35 * op * (0.5 + 0.5 * sin(TAU * 2.3 * t));
    wb_alpha = 0.0;
}
var<private> wb_ready_h: f32 = -1.0e9;
fn wb_setup(t: f32) {
    wb_setup_core(t);
    if (!wb_ok || t == wb_ready_h) {
        return;
    }
    wb_ready_h = t;
    let op = wb_open;
    let gp = wb_gape;
    var lk = 0.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        let h = we_arch_hold(i);
        if (h.x >= 0.0) {
            lk = max(lk, we_ss(h.x - 0.7, h.x + 0.9, t) * (1.0 - we_ss(h.y - 0.2, h.y + 1.1, t)));
        }
    }
    wb_alpha = 0.0;
    var hf = wb_frame(wb_sh - WB_HINGE);
    if (lk > 1.0e-3) {
        let sp = wb_sh - WB_NECK;
        let pv = wb_fr(sp);
        let sv = wb_sway(sp);
        wb_pivot = pv.p + pv.z * sv.x + pv.y * sv.y;
        let hp = hf.p;
        let g = normalize(-we_o - hp);
        let c = clamp(dot(hf.x, g), -1.0, 1.0);
        let ax = cross(hf.x, g);
        if (length(ax) > 1.0e-4) {
            wb_axis = normalize(ax);
            var inland = 0.0;
            for (var i = 0u; i < wb_n; i = i + 1u) {
                if (sp >= wb_s0[i] && sp <= wb_s1[i]) {
                    inland = we_ss(0.0, 60.0, min(sp - wb_s0[i], wb_s1[i] - sp));
                }
            }
            wb_alpha = min(acos(c), WB_LOOK_MAX) * lk * inland * we_ss(60.0, 160.0, length(we_o + hp));
        }
    }
    if (wb_alpha > 1.0e-4) {
        let ang = wb_alpha * wb_bendw(WB_HINGE);
        hf.p = wb_pivot + wb_rot(hf.p - wb_pivot, wb_axis, ang);
        hf.x = wb_rot(hf.x, wb_axis, ang);
        hf.y = wb_rot(hf.y, wb_axis, ang);
        hf.z = wb_rot(hf.z, wb_axis, ang);
    }
    let sk = 0.012 * op;
    let a1 = sk * sin(29.0 * t) + 0.6 * sk * sin(47.0 * t + 1.3);
    let a2 = sk * sin(33.0 * t + 1.0) + 0.6 * sk * sin(41.0 * t + 0.2);
    let hx = normalize(hf.x + hf.y * a1 + hf.z * a2);
    let hz = normalize(hf.z - hx * dot(hf.z, hx));
    wb_hx = hx;
    wb_hz = hz;
    wb_hy = cross(hz, hx);
    wb_ho = we_o + hf.p;
    let phi = mix(mix(WB_PHI_SHUT, WB_PHI_OPEN, op), WB_PHI_GAPE, gp);
    for (var j = 0; j < 6 + wb_z; j = j + 1) {
        let fj = f32(j);
        let var_j = (0.08 * sin(fj * 2.1 + 1.0)) * max(op, gp);
        let shake = 0.035 * op * (sin(37.0 * t + 1.7 * fj) + 0.6 * sin(23.0 * t + fj * 0.9));
        wb_phi[j] = phi + var_j + shake;
    }
}

var<private> wb_lho: vec3<f32>;
var<private> wb_lhx: vec3<f32>;
fn wb_head_lite() {
    if (wb_ready_h == wb_t) {
        wb_lho = wb_ho;
        wb_lhx = wb_hx;
        return;
    }
    wb_lho = vec3<f32>(1.0e7);
    wb_lhx = vec3<f32>(0.0, 1.0, 0.0);
    let s = wb_sh - WB_HINGE;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        if (s >= wb_s0[i] && s <= wb_s1[i]) {
            let h = (wb_s1[i] - wb_s0[i]) / f32(WE_TN);
            let x = (s - wb_s0[i]) / h;
            let j = min(u32(x), WE_TN - 1u);
            let pa = wb_cpt(i, j);
            let pb = wb_cpt(i, j + 1u);
            wb_lho = mix(pa, pb, x - f32(j));
            wb_lhx = normalize(pb - pa);
        }
    }
}

// ---- the grids and what is in them ---------------------------------------------------------------------------------
struct WbCtx {
    kind: u32,
    id: i32,
    o: vec3<f32>,
    x: vec3<f32>,
    y: vec3<f32>,
    z: vec3<f32>,
    k: vec2<f32>,
    a: vec4<f32>,
    lo: vec3<f32>,
    hi: vec3<f32>,
}
var<private> wb_c: WbCtx;
var<private> wb_shadow: bool = false;

fn wb_blk(m: u32, b: u32) -> u32 {
    return 1u | (b << 1u) | (m << 8u);
}

fn wb_rib(b: f32) -> f32 {
    return select(0.0, 1.0, fract(b / 6.0) < 0.34);
}

fn wb_plate_stone(ph: f32, hc: f32) -> u32 {
    if (ph < 0.26) {
        return select(WB_B_TILES, WB_B_CRACKED, hc < 0.08);
    }
    if (ph < 0.5) {
        return select(WB_B_COBBLED, WB_B_DEEPSLATE, hc < 0.1);
    }
    if (ph < 0.6) {
        return select(WB_B_PBLACK, WB_B_BLACK, hc < 0.06);
    }
    if (ph < 0.8) {
        return WB_B_DBRICKS;
    }
    if (ph < 0.95) {
        return WB_B_PDEEP;
    }
    return WB_B_DEEPSLATE;
}

fn wb_atan2(y: f32, x: f32) -> f32 {
    let ax = abs(x);
    let ay = abs(y);
    let a = min(ax, ay) / max(max(ax, ay), 1.0e-20);
    let s = a * a;
    var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
    r = select(r, 1.5707963 - r, ay > ax);
    r = select(r, 3.1415927 - r, x < 0.0);
    return select(r, -r, y < 0.0);
}

fn wb_ring_occ(c: vec3<f32>) -> u32 {
    let tau = wb_c.a.y;
    let yz = c.yz;
    let rr = length(yz);
    let rho = rr / tau;
    let f = clamp(1.0 - dot(wb_c.k, yz), 0.4, 1.9);
    let xf = c.x / f;
    let half = WB_L * 0.5;
    let strip = wb_c.a.z;
    if (abs(xf) > half + 7.0 && !(strip > 0.0 && xf > -half - 3.5 && xf < half + 1.0)) {
        return 0u;
    }
    let bc = wb_c.a.x;
    let bcell = bc - xf;
    if (bcell > WE_LEN - 1.0 - 0.25 * rr) {
        return 0u;
    }
    if (wb_shadow && xf > half && xf < half + 3.5 && rho > WB_RC + 1.0 && rho < 35.0) {
        return 1u;
    }
    let rin = WB_RT - 1.5 * wb_rib(bcell);
    if (rho < rin || (rho > 36.6 && strip <= 0.0)) {
        return 0u;
    }
    let kh = u32(wb_c.id + 4096);
    // (the core reaches well into the next ring's: on a bend no sky between rings, only the dark seam)
    if (rho <= WB_RC && abs(xf) <= half + 7.0) {
        let hc = wb_hc(c, kh);
        if (rho < rin + 1.0) {
            let groove = 1.0 - wb_rib(bcell);
            if (groove > 0.5 && hc < 0.45) {
                return wb_blk(WB_M_SCULK, WB_B_SCULK);
            }
            return wb_blk(WB_M_THROAT, select(select(WB_B_DEEPSLATE, WB_B_BLACK, hc < 0.35), WB_B_PDEEP, hc > 0.8));
        }
        // (past the ring's own length, the core seen only through a bend's opened seam: dark, a thin glow at most)
        if (abs(xf) > half + 2.5) {
            return wb_blk(WB_M_JOINT, select(WB_B_BLACK, WB_B_DEEPSLATE, hc < 0.5));
        }
        let seam = we_ss(half - 3.0, half + 2.0, abs(xf));
        if (hc < 0.15 + 0.2 * seam) {
            return wb_blk(WB_M_SCULK, WB_B_SCULK);
        }
        return wb_blk(WB_M_JOINT, select(WB_B_TUFF, WB_B_DEEPSLATE, hc < 0.55 + 0.25 * seam));
    }
    let th = wb_atan2(yz.y, yz.x);
    let sect = TAU / WB_NP;
    let thp = th + wb_c.a.w + 4.0 * TAU;
    let jf = floor(thp / sect);
    let u = thp / sect - jf - 0.5;
    let j = u32(jf) % 12u;
    let arc = u * sect * rho;
    let hw = 0.5 * sect * rho - 0.85;
    let ph = wb_h(kh, j, 1u);
    let along = clamp((half - xf) / (WB_L + 2.5), 0.0, 1.0);
    let rflat = 30.8 + 4.6 * along + (ph - 0.5) * 1.8;
    let edge = min(abs(arc) / max(hw, 1.0), 1.0);
    let rtop = rflat - 2.6 * edge * edge * edge - 1.4 * (1.0 - we_ss(0.0, 0.14, along));
    let inplate = xf >= -half - 3.0 && xf <= half - 0.5;
    if (inplate && rho >= WB_RC - 0.5) {
        if (abs(arc) <= hw && rho <= rtop) {
            let hc = wb_hc(c, kh);
            let streak = wb_h(kh, j * 64u + u32(floor((xf + 40.0) / 2.5)), select(3u, 4u, arc > 0.0));
            if ((hw - abs(arc) < 1.7 && streak < 0.3) || hc < 0.004) {
                return wb_blk(WB_M_SCULK, WB_B_SCULK);
            }
            let worn = select(0u, 0x10000u, rho > rtop - 1.2 && (hw - abs(arc) < 1.4 || along > 0.9 || along < 0.1));
            if (along > 0.86 && wb_h(kh, j, 5u) < 0.55) {
                return wb_blk(WB_M_PLATE, WB_B_PBBRICKS) | worn;
            }
            return wb_blk(WB_M_PLATE, wb_plate_stone(wb_h(kh, j, 2u), hc)) | worn;
        }
        if (abs(arc) > hw && rho <= WB_RC + 1.6) {
            return wb_blk(WB_M_SCULK, WB_B_SCULK);
        }
    }
    if (strip > 0.0) {
        let ath = abs(th);
        if (ath < 1.1 && xf > -half - 3.0 && xf < half + 0.5) {
            let dep = 1.0 + 3.2 * (1.0 - (ath / 1.1) * (ath / 1.1)) * (0.6 + 0.4 * wb_h(kh, u32(floor(xf + 20.0)), 9u));
            let base = select(rtop, WB_RC + 1.6, abs(arc) > hw);
            if (rho > base && rho <= rflat + dep) {
                let hc = wb_hc(c, kh);
                let clump = wb_hc(floor(c / 3.0), kh + 17u);
                let keep = strip * 1.4 - 0.45 * ath - 0.1 * (rho - rflat);
                if (0.75 * clump + 0.25 * hc < keep) {
                    return wb_blk(WB_M_LAND, select(WB_B_DIRT, WB_B_GRASS, rho > rflat + dep - 1.0));
                }
                return 0u;
            }
        }
        for (var tr = 0u; tr < 2u + wb_zu; tr = tr + 1u) {
            if (c.y < 29.0 || abs(c.z) > 16.0) {
                break;
            }
            if (wb_h(kh, 7u, tr) < 0.6 && wb_h(kh, 8u, tr) < strip * 1.5 - 0.45) {
                let xt = floor(-half + 2.0 + wb_h(kh, 10u, tr) * (WB_L - 4.0)) + 0.5;
                let zt = floor((wb_h(kh, 11u, tr) - 0.5) * 26.0) + 0.5;
                let al = clamp((half - xt) / (WB_L + 2.5), 0.0, 1.0);
                let rs = 30.8 + 4.6 * al + 2.6;
                let yb = floor(sqrt(max(rs * rs - zt * zt, 0.0))) + 0.5;
                let dy = c.y - yb;
                let dx = abs(c.x - xt);
                let dz = abs(c.z - zt);
                if (dx < 0.1 && dz < 0.1 && dy > -1.5 && dy < 5.0) {
                    return wb_blk(WB_M_LAND, WB_B_LOG);
                }
                if (dy > 2.5 && dy < 4.5 && dx < 2.1 && dz < 2.1 && !(dx > 1.9 && dz > 1.9 && wb_hc(c, kh + 3u) < 0.6)) {
                    return wb_blk(WB_M_LAND, WB_B_LEAVES);
                }
                if (dy > 4.5 && dy < 6.5 && dx < 1.1 && dz < 1.1 && !(dx > 0.9 && dz > 0.9 && dy > 5.5)) {
                    return wb_blk(WB_M_LAND, WB_B_LEAVES);
                }
            }
        }
    }
    return 0u;
}

fn wb_head_occ(c: vec3<f32>) -> u32 {
    let x = c.x;
    let rho = length(c.yz);
    let hc = wb_hc(c, 777u);
    if (x > -1.5 - 1.5 * wb_hc(floor(c / 2.0), 778u) && x < 2.6 && rho > 23.0 && rho < 29.0 + 1.6 * wb_hc(floor(c / 2.0), 779u)) {
        return wb_blk(WB_M_GUM, select(select(WB_B_BLACK, WB_B_PBLACK, hc < 0.35), select(WB_B_DEEPSLATE, WB_B_SCULK, rho < 26.0), hc > 0.62));
    }
    if (x < -17.0 || x > 0.0) {
        return 0u;
    }
    if (rho < WB_RC) {
        let rw = mix(WB_RT, 24.0, we_ss(-15.0, -1.0, x)) - 1.2 * wb_rib(-x + 40.0);
        if (rho >= rw) {
            if (rho < rw + 1.0 && wb_rib(-x + 40.0) < 0.5 && hc < 0.4) {
                return wb_blk(WB_M_SCULK, WB_B_SCULK);
            }
            return wb_blk(WB_M_THROAT, select(WB_B_DEEPSLATE, WB_B_BLACK, hc < 0.4));
        }
        return 0u;
    }
    return 0xFFFFFFFFu;
}

fn wb_petal_occ(c: vec3<f32>) -> u32 {
    let u = c.x;
    let w = c.y;
    let v = c.z;
    if (u < 0.0 || u > WB_PET_L) {
        return 0u;
    }
    let un = u / WB_PET_L;
    let hw = 14.5 + 5.0 * sin(3.14159 * min(un * 1.25, 1.0)) - 6.0 * we_ss(0.7, 1.0, un);
    let vn = v / hw;
    if (abs(vn) > 1.0 || u > WB_PET_L - 9.0 * vn * vn) {
        return 0u;
    }
    let phi = wb_c.a.x;
    let rr = WB_PET_R + u * sin(phi) + w * cos(phi);
    if (rr <= 0.5 || abs(v) > 0.5774 * rr + 0.35) {
        return 0u;
    }
    let rc = max(WB_PET_R - 0.5 * u, 7.0);
    let w0 = -v * v / (2.0 * rc);
    let band = fract(u / 9.0);
    let spine = abs(v) < 1.6 && u < WB_PET_L - 5.0;
    let th = 6.0 - 2.4 * un + 1.6 * (1.0 - vn * vn) + select(0.0, 1.5, spine) + select(0.0, 1.0, band > 0.55);
    if (w < w0 - 0.5 || w > w0 + th) {
        return 0u;
    }
    let pid = u32(wb_c.id);
    let hc = wb_hc(c, 900u + pid);
    if (w < w0 + 1.0) {
        if ((abs(v) < 1.6 && hc < 0.6) || (abs(fract(u / 7.0 + v * 0.05) - 0.5) < 0.08 && hc < 0.7) || hc < 0.05) {
            return wb_blk(WB_M_SCULK, WB_B_SCULK);
        }
        return wb_blk(WB_M_PETAL_IN, select(WB_B_PDEEP, WB_B_DEEPSLATE, hc < 0.4));
    }
    if (hw - abs(v) < 1.3 || u > WB_PET_L - 9.0 * vn * vn - 1.3) {
        return wb_blk(WB_M_PETAL, WB_B_PBBRICKS) | 0x10000u;
    }
    if (spine) {
        return wb_blk(WB_M_PETAL, select(WB_B_BASALT, WB_B_CHISEL, hc < 0.25));
    }
    let bh = wb_h(pid, u32(floor(u / 9.0)), select(21u, 22u, v > 0.0));
    if (hc < 0.03) {
        return wb_blk(WB_M_SCULK, WB_B_SCULK);
    }
    return wb_blk(WB_M_PETAL, wb_plate_stone(bh, hc));
}

fn wb_tooth_occ(c: vec3<f32>) -> u32 {
    let m = wb_c.id;
    var x0 = 0.5;
    var r0 = 26.0;
    var nt = 24.0;
    var len = 11.0;
    var beta = 0.75;
    if (m == 1) {
        x0 = -6.0;
        r0 = 22.5;
        nt = 20.0;
        len = 9.0;
        beta = 0.45;
    } else if (m == 2) {
        x0 = -11.5;
        r0 = 19.0;
        nt = 16.0;
        len = 8.0;
        beta = 0.25;
    }
    let rho = length(c.yz);
    let th = atan2(c.z, c.y);
    let sect = TAU / nt;
    let jf = round(th / sect + 0.5 * f32(m & 1));
    let thj = (jf - 0.5 * f32(m & 1)) * sect;
    var dth = th - thj;
    dth = dth - TAU * round(dth / TAU);
    let q = vec2<f32>(c.x - x0, rho - r0);
    let a = q.x * sin(beta) - q.y * cos(beta);
    let p = q.x * cos(beta) + q.y * sin(beta);
    let tq = rho * dth;
    let tid = u32(i32(jf) + 64) + u32(m) * 128u;
    let ln = len * (0.8 + 0.35 * wb_h(tid, 3u, 7u));
    if (a < -1.5 || a > ln) {
        return 0u;
    }
    let hs = 1.75 * (1.0 - a / ln) + 0.3;
    if (abs(p) > hs || abs(tq) > hs) {
        return 0u;
    }
    let f = a / ln;
    if (f < 0.22) {
        return wb_blk(WB_M_TOOTH, WB_B_DRIP);
    }
    return wb_blk(WB_M_TOOTH, select(WB_B_BONE, WB_B_CALCITE, f > 0.68));
}

fn wb_occ(c: vec3<f32>) -> u32 {
    var q = c;
    var collar = false;
    if (wb_c.kind == 2u) {
        return wb_petal_occ(c);
    }
    if (wb_c.kind == 3u) {
        return wb_tooth_occ(c);
    }
    if (wb_c.kind == 1u) {
        let h = wb_head_occ(c);
        if (h != 0xFFFFFFFFu) {
            return h;
        }
        collar = true;
        q = vec3<f32>(c.x + 8.5, c.y, c.z);
    }
    let sa = wb_c.a;
    let sid = wb_c.id;
    let sk = wb_c.k;
    if (collar) {
        wb_c.a = vec4<f32>(WB_HINGE + 8.5, 1.07, 0.0, 0.2);
        wb_c.id = 3000;
        wb_c.k = vec2<f32>(0.0);
    }
    let v = wb_ring_occ(q);
    if (collar) {
        wb_c.a = sa;
        wb_c.id = sid;
        wb_c.k = sk;
    }
    return v;
}

// ---- tracing a grid, block by block ----------------------------------------------------------------------------------
struct WbV {
    t: f32,
    n: vec3<f32>,
    c: vec3<f32>,
    v: u32,
}
fn wb_dda(o: vec3<f32>, d: vec3<f32>, t0in: f32, t1in: f32, maxn: i32, ring: bool) -> WbV {
    let dd = select(d, vec3<f32>(1.0e-7), abs(d) < vec3<f32>(1.0e-7));
    let inv = 1.0 / dd;
    let ta = (wb_c.lo - o) * inv;
    let tb = (wb_c.hi - o) * inv;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    let tb0 = max(max(tn.x, tn.y), tn.z);
    let t0 = max(tb0, t0in);
    let t1 = min(min(min(tf.x, tf.y), tf.z), t1in);
    var out = WbV(WE_MISS, vec3<f32>(0.0), vec3<f32>(0.0), 0u);
    if (t0 >= t1) {
        return out;
    }
    let st = sign(dd);
    var nrm = vec3<f32>(0.0);
    let ad = abs(dd);
    var ax = select(select(2, 1, ad.y >= ad.z), 0, ad.x >= ad.y && ad.x >= ad.z);
    if (tb0 >= t0in) {
        ax = select(select(2, 1, tn.y >= tn.z), 0, tn.x >= tn.y && tn.x >= tn.z);
    }
    if (ax == 0) {
        nrm.x = -st.x;
    } else if (ax == 1) {
        nrm.y = -st.y;
    } else {
        nrm.z = -st.z;
    }
    let p0 = o + d * (t0 + 1.0e-3);
    var cell = clamp(floor(p0), wb_c.lo, wb_c.hi - vec3<f32>(1.0));
    let tdel = abs(inv);
    var tside = (cell + max(st, vec3<f32>(0.0)) - o) * inv;
    var t = t0;
    var leaving = tb0 < t0in + 1.0e-4 && t0in < 0.5;
    for (var i = 0; i < maxn + wb_z; i = i + 1) {
        if (wb_shadow && wb_c.kind == 0u && dot(cell.yz + 0.5, cell.yz + 0.5) > 1369.0 && dot(cell.yz + 0.5, dd.yz) > 0.0) {
            break;
        }
        var v = 0u;
        if (ring) {
            v = wb_ring_occ(cell + 0.5);
        } else {
            v = wb_occ(cell + 0.5);
        }
        if (v != 0u && !leaving) {
            out = WbV(t, nrm, cell, v);
            return out;
        }
        leaving = leaving && v != 0u;
        if (tside.x < tside.y && tside.x < tside.z) {
            t = tside.x;
            cell.x = cell.x + st.x;
            tside.x = tside.x + tdel.x;
            nrm = vec3<f32>(-st.x, 0.0, 0.0);
        } else if (tside.y < tside.z) {
            t = tside.y;
            cell.y = cell.y + st.y;
            tside.y = tside.y + tdel.y;
            nrm = vec3<f32>(0.0, -st.y, 0.0);
        } else {
            t = tside.z;
            cell.z = cell.z + st.z;
            tside.z = tside.z + tdel.z;
            nrm = vec3<f32>(0.0, 0.0, -st.z);
        }
        if (t > t1) {
            break;
        }
    }
    return out;
}

var<private> wb_bt: f32 = 1.0e9;
var<private> wb_bv: WbV;
var<private> wb_bc: WbCtx;

fn wb_trace(ro: vec3<f32>, rd: vec3<f32>, t0: f32, t1: f32, maxn: i32, ring: bool) {
    let q = ro - wb_c.o;
    let o = vec3<f32>(dot(q, wb_c.x), dot(q, wb_c.y), dot(q, wb_c.z));
    let d = vec3<f32>(dot(rd, wb_c.x), dot(rd, wb_c.y), dot(rd, wb_c.z));
    let h = wb_dda(o, d, t0, min(t1, wb_bt), maxn, ring);
    if (h.v != 0u && h.t < wb_bt) {
        wb_bt = h.t;
        wb_bv = h;
        wb_bc = wb_c;
    }
}

fn wb_cone(o: vec3<f32>, d: vec3<f32>, A: f32, B: f32, x0: f32, x1: f32, t_lo: f32) -> f32 {
    let r0 = A + B * o.x;
    let a2 = d.y * d.y + d.z * d.z - B * B * d.x * d.x;
    let b2 = o.y * d.y + o.z * d.z - B * d.x * r0;
    let c2 = o.y * o.y + o.z * o.z - r0 * r0;
    let disc = b2 * b2 - a2 * c2;
    if (disc < 0.0 || abs(a2) < 1.0e-9) {
        return 1.0e9;
    }
    let sq = sqrt(disc);
    let ta = (-b2 - sq) / a2;
    let tb = (-b2 + sq) / a2;
    var best = 1.0e9;
    for (var k = 0; k < 2 + wb_z; k = k + 1) {
        let tt = select(tb, ta, k == 0);
        let x = o.x + d.x * tt;
        if (tt > t_lo && tt < best && x >= x0 && x <= x1 && A + B * x > 0.0) {
            best = tt;
        }
    }
    return best;
}
fn wb_ring_coarse(ro: vec3<f32>, rd: vec3<f32>) {
    let q = ro - wb_c.o;
    let o = vec3<f32>(dot(q, wb_c.x), dot(q, wb_c.y), dot(q, wb_c.z));
    let d = vec3<f32>(dot(rd, wb_c.x), dot(rd, wb_c.y), dot(rd, wb_c.z));
    let tau = wb_c.a.y;
    let half = WB_L * 0.5;
    let kc = 4.6 / (WB_L + 2.5);
    let A = (30.8 + kc * half) * tau;
    let B = -kc * tau;
    // (as long along as the ring's blocks reach on a bend (its box): on the outside of the neck's bend no gaps between
    // rings)
    let xm = max(wb_c.hi.x, half + 5.0);
    let t1 = wb_cone(o, d, A, B, -half - 3.0 - (xm - half - 5.0), xm - 5.5, 0.0);
    let t2 = wb_cone(o, d, WB_RC * tau, 0.0, -xm, xm, 0.0);
    let t = min(t1, t2);
    if (t >= wb_bt) {
        return;
    }
    let pl = o + d * t;
    let rho = max(length(pl.yz), 1.0e-3);
    var nl = vec3<f32>(0.0, pl.y / rho, pl.z / rho);
    if (t1 <= t2) {
        nl = normalize(vec3<f32>(-B, pl.y / rho, pl.z / rho));
    }
    let sect = TAU / WB_NP;
    let thp = wb_atan2(pl.z, pl.y) + wb_c.a.w + 4.0 * TAU;
    let kh = u32(wb_c.id + 4096);
    let jp = u32(floor(thp / sect)) % 12u;
    var v = wb_blk(WB_M_PLATE, wb_plate_stone(wb_h(kh, jp, 2u), 0.5));
    if (t2 < t1) {
        v = wb_blk(WB_M_JOINT, WB_B_DEEPSLATE);
    }
    let ua = abs(fract(thp / sect) - 0.5) * sect * rho / tau;
    if (t1 <= t2 && ua > 0.5 * sect * rho / tau - 1.6) {
        v = wb_blk(WB_M_SCULK, WB_B_SCULK);
    }
    if (v == 0u) {
        v = wb_blk(WB_M_PLATE, WB_B_TILES);
    }
    wb_bt = t;
    wb_bv = WbV(t, nl, floor(pl), v);
    wb_bc = wb_c;
    wb_bc.kind = 4u;
}

fn wb_ring_prep(ro: vec3<f32>, rd: vec3<f32>, k: i32) -> vec4<f32> {
    let bc = wb_ring_b(k);
    if (bc - WB_L * 0.5 - 6.0 > WE_LEN) {
        return vec4<f32>(0.0);
    }
    let fr = wb_frame(wb_sh - bc);
    let tau = wb_taper(bc);
    let strip = select(0.0, wb_strip(bc), wb_strip(bc) > 0.05);
    let kl = vec2<f32>(dot(fr.k, fr.y), dot(fr.k, fr.z));
    let rb = 36.6 * tau + select(0.0, 9.0, strip > 0.0);
    let fm = clamp(1.0 + length(kl) * rb, 1.0, 1.9);
    let xm = (WB_L * 0.5 + 7.0) * fm;
    let toff = select(0.0, 0.5, (k & 1) == 1) * (TAU / WB_NP) + (wb_h(u32(k + 4096), 0u, 6u) - 0.5) * 0.35 * (TAU / WB_NP);
    let up = select(0.0, 5.0, strip > 0.0);
    wb_c = WbCtx(0u, k, we_o + fr.p, fr.x, fr.y, fr.z, kl, vec4<f32>(bc, tau, strip, toff),
        vec3<f32>(-xm, -rb, -rb), vec3<f32>(xm, rb + up, rb));
    if (strip <= 0.0 && length(wb_c.o) - rb > WB_LOD + 60.0 * (wb_h(u32(k + 4096), 0u, 9u) - 0.5)) {
        wb_ring_coarse(ro, rd);
        return vec4<f32>(0.0);
    }
    let q = ro - wb_c.o;
    let oy = vec2<f32>(dot(q, fr.y), dot(q, fr.z));
    let dy = vec2<f32>(dot(rd, fr.y), dot(rd, fr.z));
    let rc = rb + up;
    let a = dot(dy, dy);
    let b = dot(oy, dy);
    let cc = dot(oy, oy) - rc * rc;
    let disc = b * b - a * cc;
    var tin = 0.0;
    let ri = (WB_RT - 1.6) * tau;
    let ci = dot(oy, oy) - ri * ri;
    if (ci < 0.0) {
        if (a < 1.0e-8) {
            return vec4<f32>(0.0);
        }
        tin = max((-b + sqrt(b * b - a * ci)) / a - 0.5, 0.0);
    }
    if (disc < 0.0 || a < 1.0e-8) {
        if (cc > 0.0) {
            return vec4<f32>(0.0);
        }
        return vec4<f32>(1.0, tin, 1.0e9, 80.0);
    }
    let sq = sqrt(disc);
    let t0 = (-b - sq) / a;
    let t1 = (-b + sq) / a;
    if (t1 < 0.0 || t0 > wb_bt) {
        return vec4<f32>(0.0);
    }
    return vec4<f32>(1.0, max(max(t0, 0.0), tin), t1, 44.0);
}

fn wb_cyl(o: vec3<f32>, rd: vec3<f32>, a: vec3<f32>, r: f32) -> vec2<f32> {
    let oy = o - a * dot(o, a);
    let dy = rd - a * dot(rd, a);
    let qa = dot(dy, dy);
    let qb = dot(oy, dy);
    let qc = dot(oy, oy) - r * r;
    let disc = qb * qb - qa * qc;
    if (qa < 1.0e-8) {
        return select(vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0e9), qc < 0.0);
    }
    if (disc < 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    let sq = sqrt(disc);
    return vec2<f32>(max((-qb - sq) / qa, 0.0), (-qb + sq) / qa);
}

fn wb_head_prep(ro: vec3<f32>, rd: vec3<f32>, q: i32) -> vec4<f32> {
    if (q == 0) {
        wb_c = WbCtx(1u, 0, wb_ho, wb_hx, wb_hy, wb_hz, vec2<f32>(0.0), vec4<f32>(0.0), vec3<f32>(-19.0, -40.0, -40.0), vec3<f32>(3.0, 40.0, 40.0));
        let cy = wb_cyl(ro - wb_ho, rd, wb_hx, 39.5);
        return vec4<f32>(select(0.0, 1.0, cy.x < cy.y), cy.x, cy.y, 80.0);
    }
    if (q <= 6) {
        let j = q - 1;
        let th = f32(j) * (TAU / 6.0);
        let rh = wb_hy * cos(th) + wb_hz * sin(th);
        let phi = wb_phi[j];
        let U = wb_hx * cos(phi) + rh * sin(phi);
        let W = -wb_hx * sin(phi) + rh * cos(phi);
        let pc = wb_ho + rh * WB_PET_R + U * (0.5 * WB_PET_L) - ro;
        let pb = dot(pc, rd);
        let pd = dot(pc, pc) - pb * pb;
        if (pd > 34.0 * 34.0 || pb + 34.0 < 0.0 || pb - 34.0 > wb_bt) {
            return vec4<f32>(0.0);
        }
        wb_c = WbCtx(2u, j, wb_ho + rh * WB_PET_R, U, W, cross(U, W), vec2<f32>(0.0), vec4<f32>(phi, 0.0, 0.0, 0.0), vec3<f32>(-1.0, -14.0, -20.5), vec3<f32>(WB_PET_L + 1.0, 11.0, 20.5));
        return vec4<f32>(1.0, 0.0, 1.0e9, 72.0);
    }
    if (max(wb_open, wb_gape) <= 0.01) {
        return vec4<f32>(0.0);
    }
    let m = q - 7;
    let ps = wb_psi[m];
    let x0 = select(select(0.5, -6.0, m == 1), -11.5, m == 2);
    let r0 = select(select(26.0, 22.5, m == 1), 19.0, m == 2);
    wb_c = WbCtx(3u, m, wb_ho, wb_hx, wb_hy * cos(ps) + wb_hz * sin(ps), -wb_hy * sin(ps) + wb_hz * cos(ps), vec2<f32>(0.0), vec4<f32>(0.0), vec3<f32>(x0 - 3.0, -r0 - 3.0, -r0 - 3.0), vec3<f32>(x0 + 12.0, r0 + 3.0, r0 + 3.0));
    return vec4<f32>(1.0, 0.0, 1.0e9, 72.0);
}

// ---- the broad phase: arches' boxes, chords' capsules ------------------------------------------------------------
fn wb_cap(ro: vec3<f32>, rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let ba = b - a;
    let u = clamp(dot(ro - a, ba) / max(dot(ba, ba), 1.0e-6), 0.0, 1.0);
    if (length(ro - a - ba * u) < r) {
        return 0.0;
    }
    return we_capsule(ro, rd, a, b, r);
}
fn wb_ray_seg(ro: vec3<f32>, rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> f32 {
    let ba = b - a;
    let oa = ro - a;
    let bb = dot(ba, ba);
    let bd = dot(ba, rd);
    let den = bb - bd * bd;
    var v = 0.0;
    if (den > 1.0e-6) {
        v = clamp((dot(oa, ba) - dot(oa, rd) * bd) / den, 0.0, 1.0);
    }
    var u = max(dot(a + ba * v - ro, rd), 0.0);
    v = clamp(dot(ro + rd * u - a, ba) / max(bb, 1.0e-6), 0.0, 1.0);
    u = max(dot(a + ba * v - ro, rd), 0.0);
    return length(ro + rd * u - a - ba * v);
}

fn wb_bent(s: f32, p: vec3<f32>) -> vec3<f32> {
    let b = wb_sh - s;
    if (wb_alpha > 1.0e-4 && b < WB_NECK) {
        return wb_pivot + wb_rot(p - wb_pivot, wb_axis, wb_alpha * wb_bendw(b));
    }
    return p;
}
fn wb_cpt(i: u32, j: u32) -> vec3<f32> {
    let f = wb_af[i];
    let to = wb_at[i];
    let ad = wb_ad[i];
    let th = we_aw(i, WE_R_TH + j);
    let sn = sin(th);
    let cs = cos(th);
    let along = ad.z * (1.0 - cs);
    let p = vec3<f32>(f.x + ad.x * along, f.y + (to.y - f.y) * 0.5 * (1.0 - cs) + ad.w * sn, f.z + ad.y * along);
    return we_o + wb_bent(wb_s0[i] + (wb_s1[i] - wb_s0[i]) * f32(j) / f32(WE_TN), p);
}
struct WbPc {
    a: vec3<f32>,
    b: vec3<f32>,
    sa: f32,
    sb: f32,
}
const WB_NPC: u32 = 22u;
fn wb_piece(i: u32, q: u32) -> WbPc {
    let h = (wb_s1[i] - wb_s0[i]) / f32(WE_TN);
    if (q < 16u) {
        return WbPc(wb_cpt(i, q), wb_cpt(i, q + 1u), wb_s0[i] + h * f32(q), wb_s0[i] + h * f32(q + 1u));
    }
    var sa = wb_s0[i] - 120.0 + 40.0 * f32(q - 16u);
    if (q >= 19u) {
        sa = wb_s1[i] + 40.0 * f32(q - 19u);
    }
    let sb = sa + 40.0;
    let pa = select(we_o + we_pt(sa).p, wb_cpt(i, 16u), q == 19u);
    let pb = select(we_o + we_pt(sb).p, wb_cpt(i, 0u), q == 18u);
    return WbPc(pa, pb, sa, sb);
}
fn wb_near_hole(ro: vec3<f32>, rd: vec3<f32>, i: u32, end: u32, tmax: f32) -> bool {
    let k = we_o + select(wb_af[i], wb_at[i], end == 1u);
    let e = wb_cap(ro, rd, k - vec3<f32>(0.0, 130.0, 0.0), k, 125.0);
    return e >= 0.0 && e < tmax;
}

var<private> wb_cand: array<vec4<f32>, 6>;
var<private> wb_cpa: array<vec4<f32>, 6>;
var<private> wb_cpb: array<vec4<f32>, 6>;
var<private> wb_ncand: u32 = 0u;
fn wb_add(e: f32, sa: f32, sb: f32, se: f32, pa: vec3<f32>, pb: vec3<f32>) {
    let lo = wb_sh - WE_LEN - 12.0;
    let hi = wb_sh - WB_HEAD + 14.0;
    let a = max(sa, lo);
    let b = min(sb, hi);
    if (b <= a) {
        return;
    }
    if (wb_ncand == 6u && e >= wb_cand[5].x) {
        return;
    }
    var k = i32(min(wb_ncand, 5u));
    while (k > 0 && wb_cand[k - 1].x > e) {
        wb_cand[k] = wb_cand[k - 1];
        wb_cpa[k] = wb_cpa[k - 1];
        wb_cpb[k] = wb_cpb[k - 1];
        k = k - 1;
    }
    wb_cand[k] = vec4<f32>(e, a, b, clamp(se, a, b));
    wb_cpa[k] = vec4<f32>(pa, sa);
    wb_cpb[k] = vec4<f32>(pb, sb);
    wb_ncand = min(wb_ncand + 1u, 6u);
}
fn wb_arch_box(ro: vec3<f32>, rd: vec3<f32>, i: u32, m: f32, tmax: f32) -> bool {
    let f = we_o + we_arch_from(i);
    let to = we_arch_to(i) - we_arch_from(i);
    let w = max(length(to.xz), 1.0e-4);
    let d3 = vec3<f32>(to.x / w, 0.0, to.z / w);
    let z = wb_pl[i];
    let q = ro - f;
    let o = vec3<f32>(dot(q, d3), q.y, dot(q, z));
    let dv = vec3<f32>(dot(rd, d3), rd.y, dot(rd, z));
    let lo = vec3<f32>(-m, min(0.0, to.y) - 100.0, -m);
    let hi = vec3<f32>(w + m, max(0.0, to.y) + we_arch_apex(i) + m, m);
    let dd = select(dv, vec3<f32>(1.0e-7), abs(dv) < vec3<f32>(1.0e-7));
    let ta = (lo - o) / dd;
    let tb = (hi - o) / dd;
    let tn = min(ta, tb);
    let tf = max(ta, tb);
    let t0 = max(max(tn.x, tn.y), max(tn.z, 0.0));
    let t1 = min(min(min(tf.x, tf.y), tf.z), tmax);
    // (the span along the arch from the box without the neck's bend margin: the chords off the neck need no more)
    let mx = vec3<f32>(m - min(m, 52.0), 0.0, m - min(m, 52.0));
    let ta2 = (lo + mx - o) / dd;
    let tb2 = (hi - mx - o) / dd;
    let u0 = max(max(min(ta2, tb2).x, min(ta2, tb2).y), max(min(ta2, tb2).z, 0.0));
    let u1 = min(min(min(max(ta2, tb2).x, max(ta2, tb2).y), max(ta2, tb2).z), tmax);
    wb_span = vec2<f32>(1.0, 0.0);
    if (u0 < u1) {
        let a0 = o.x + dv.x * u0;
        let a1 = o.x + dv.x * u1;
        wb_span = vec2<f32>(min(a0, a1) - min(m, 52.0), max(a0, a1) + min(m, 52.0));
    }
    return t0 < t1;
}
var<private> wb_span: vec2<f32>;
fn wb_chord_in(i: u32, j: u32) -> bool {
    // (while the neck bends, its chords moved off the arch's plane: always looked at; the rest as ever, so they never
    // crowd the neck's out of the candidates)
    let h = (wb_s1[i] - wb_s0[i]) / f32(WE_TN);
    if (wb_alpha > 1.0e-4 && wb_s0[i] + h * f32(j + 1u) > wb_sh - WB_NECK) {
        return true;
    }
    let ax = wb_ad[i].z;
    let a0 = ax * (1.0 - cos(we_aw(i, WE_R_TH + j)));
    let a1 = ax * (1.0 - cos(we_aw(i, WE_R_TH + j + 1u)));
    return max(a0, a1) >= wb_span.x && min(a0, a1) <= wb_span.y;
}

fn wb_gather(ro: vec3<f32>, rd: vec3<f32>, tmax: f32) {
    wb_ncand = 0u;
    if (wb_headonly || (wb_headfwd && dot(rd, wb_hx) > 0.0)) {
        return;
    }
    let rcap = WB_RB + 8.0;
    let m = rcap + 6.0 + select(0.0, 130.0, wb_alpha > 1.0e-4);
    let lo = wb_sh - WE_LEN - 12.0;
    let hi = wb_sh - WB_HEAD + 14.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        if (wb_s1[i] + 120.0 < lo || wb_s0[i] - 120.0 > hi || !wb_arch_box(ro, rd, i, m, tmax)) {
            continue;
        }
        let h = (wb_s1[i] - wb_s0[i]) / f32(WE_TN);
        var pa = vec3<f32>(0.0);
        var have = 99u;
        for (var q = 0u; q < 16u + wb_zu; q = q + 1u) {
            if (!wb_chord_in(i, q)) {
                continue;
            }
            if (have != q) {
                pa = wb_cpt(i, q);
            }
            let pb = wb_cpt(i, q + 1u);
            have = q + 1u;
            let sa = wb_s0[i] + h * f32(q);
            if (sa + h >= lo && sa <= hi) {
                let e = wb_cap(ro, rd, pa, pb, rcap);
                if (e >= 0.0 && e < tmax) {
                    let ba = pb - pa;
                    let u = clamp(dot(ro + rd * (e + 8.0) - pa, ba) / max(dot(ba, ba), 1.0e-6), 0.0, 1.0);
                    wb_add(e, sa, sa + h, sa + h * u, pa, pb);
                }
            }
            pa = pb;
        }
        for (var end = 0u; end < 2u + wb_zu; end = end + 1u) {
            let s_end = select(wb_s0[i] - 120.0, wb_s1[i], end == 1u);
            if (s_end + 120.0 < lo || s_end > hi || !wb_near_hole(ro, rd, i, end, tmax)) {
                continue;
            }
            for (var q = 16u + 3u * end; q < 19u + 3u * end; q = q + 1u) {
                let pc = wb_piece(i, q);
                if (pc.sb < lo || pc.sa > hi) {
                    continue;
                }
                let e = wb_cap(ro, rd, pc.a, pc.b, rcap);
                if (e >= 0.0 && e < tmax) {
                    let ba = pc.b - pc.a;
                    let u = clamp(dot(ro + rd * (e + 8.0) - pc.a, ba) / max(dot(ba, ba), 1.0e-6), 0.0, 1.0);
                    wb_add(e, pc.sa, pc.sb, mix(pc.sa, pc.sb, u), pc.a, pc.b);
                }
            }
        }
    }
}

fn we_body_hit(ro: vec3<f32>, rd: vec3<f32>, tmax: f32, t: f32) -> WeHit {
    wb_setup(t);
    if (!wb_ok) {
        return wb_miss();
    }
    wb_bt = min(tmax, WE_MISS);
    let t_in = wb_bt;
    wb_gather(ro, rd, wb_bt);
    let kmax = i32(floor((WE_LEN - WB_HEAD) / WB_L));
    let hr = 52.0 + 42.0 * max(wb_open, wb_gape);
    let hc = wb_ho + wb_hx * 8.0 - ro;
    let hb = dot(hc, rd);
    let hd = dot(hc, hc) - hb * hb;
    var pk0 = 1000000;
    var pk1 = -1000000;
    for (var c = 0u; c < wb_ncand; c = c + 1u) {
        let cd = wb_cand[c];
        if (cd.x > wb_bt) {
            break;
        }
        let k0 = max(i32(floor((wb_sh - cd.z - 16.0 - WB_HEAD) / WB_L - 0.5)), 0);
        let k1 = min(i32(ceil((wb_sh - cd.y + 16.0 - WB_HEAD) / WB_L - 0.5)), kmax);
        let kc = clamp(i32(floor((wb_sh - cd.w - WB_HEAD) / WB_L)), k0, k1);
        for (var jq = 0; jq <= 2 * (k1 - k0) + 1; jq = jq + 1) {
            let k = kc + select(-(jq / 2), (jq + 1) / 2, (jq & 1) == 1);
            if (k < k0 || k > k1 || (k >= pk0 && k <= pk1)) {
                continue;
            }
            if (!(wb_alpha > 1.0e-4 && wb_ring_b(k) < WB_NECK + 20.0)) {
                let pa = wb_cpa[c];
                let pb = wb_cpb[c];
                let sc = wb_sh - wb_ring_b(k);
                let cc = mix(pa.xyz, pb.xyz, (sc - pa.w) / max(pb.w - pa.w, 1.0e-3)) - ro;
                let cb = dot(cc, rd);
                let cr = select(54.0, 66.0, wb_ring_b(k) < WB_STRIP_B + 10.0);
                let cd2 = dot(cc, cc) - cb * cb;
                if (cd2 > cr * cr || cb + cr < 0.0 || cb - sqrt(cr * cr - cd2) > wb_bt) {
                    continue;
                }
            }
            let job = wb_ring_prep(ro, rd, k);
            if (job.x > 0.5 && job.y < job.z) {
                wb_trace(ro, rd, job.y, job.z, i32(job.w), true);
            }
        }
        if (k1 >= pk0 - 1 && k0 <= pk1 + 1) {
            pk0 = min(pk0, k0);
            pk1 = max(pk1, k1);
        } else {
            pk0 = k0;
            pk1 = k1;
        }
    }
    if (hd < hr * hr && hb + hr > 0.0 && hb - sqrt(hr * hr - hd) < wb_bt) {
        for (var hq = 0; hq < 10 + wb_z; hq = hq + 1) {
            let job = wb_head_prep(ro, rd, hq);
            if (job.x > 0.5 && job.y < job.z) {
                wb_trace(ro, rd, job.y, job.z, i32(job.w), false);
            }
        }
    }
    if (max(wb_open, wb_gape) > 0.02) {
        let oh = ro - wb_ho;
        let hx0 = dot(oh, wb_hx);
        let dx = dot(rd, wb_hx);
        if (hx0 > 0.0 && dx < -0.05) {
            let tp = -hx0 / dx;
            let q = oh + rd * tp;
            let rr = length(q - wb_hx * dot(q, wb_hx));
            let td = tp + 45.0 / -dx;
            if (rr < 22.0 && tp < wb_bt && td < t_in && (wb_bt >= t_in || wb_bt > td)) {
                let core = 1.0 - (rr / 22.0) * (rr / 22.0);
                return WeHit(td, ro + rd * td, wb_hx, WB_M_THROAT, wb_glow, 400.0, WB_B_DEEPSLATE, 2u, vec2<f32>(0.5), 1.0, 0.0, wb_glow, 0.45 + 0.75 * core * core, wb_hx, 0.0);
            }
        }
    }
    if (wb_bt >= t_in) {
        return wb_miss();
    }
    return wb_finish(ro, rd);
}

fn wb_finish(ro: vec3<f32>, rd: vec3<f32>) -> WeHit {
    wb_c = wb_bc;
    let coarse = wb_c.kind == 4u;
    if (coarse) {
        wb_c.kind = 0u;
    }
    let v = wb_bv;
    let q = ro - wb_c.o;
    let o = vec3<f32>(dot(q, wb_c.x), dot(q, wb_c.y), dot(q, wb_c.z));
    let d = vec3<f32>(dot(rd, wb_c.x), dot(rd, wb_c.y), dot(rd, wb_c.z));
    let pl = o + d * v.t;
    let nl = v.n;
    let n = wb_c.x * nl.x + wb_c.y * nl.y + wb_c.z * nl.z;
    let mat = (v.v >> 8u) & 255u;
    let blk = (v.v >> 1u) & 127u;
    let worn = (v.v & 0x10000u) != 0u;
    let fp = clamp(pl - v.c, vec3<f32>(0.0), vec3<f32>(1.0));
    let an = abs(nl);
    let fax = select(select(2, 1, an.y >= an.z), 0, an.x >= an.y && an.x >= an.z);
    let uv = select(select(fp.xy, fp.xz, fax == 1), fp.zy, fax == 0);
    let face = select(2u, select(1u, 0u, nl.y > 0.0), fax == 1);
    let dist = v.t;
    var nsl = nl;
    let rho_l = max(length(pl.yz), 1.0e-3);
    let radial = vec3<f32>(0.0, pl.y / rho_l, pl.z / rho_l);
    var inner = false;
    if (wb_c.kind == 0u) {
        inner = rho_l < (WB_RC - 3.0) * wb_c.a.y;
        nsl = select(normalize(radial + vec3<f32>(0.24, 0.0, 0.0)), -radial, inner);
    } else if (wb_c.kind == 1u) {
        nsl = select(radial, -radial, dot(nl, radial) < -0.3);
    }
    let ns = normalize(wb_c.x * nsl.x + wb_c.y * nsl.y + wb_c.z * nsl.z);
    var ao = 1.0;
    if (wb_c.kind == 0u && !inner) {
        let along = clamp((WB_L * 0.5 - pl.x) / (WB_L + 2.5), 0.0, 1.0);
        ao = mix(0.62, 1.0, we_ss(0.0, 0.32, along)) * select(1.0, 0.6, rho_l < (WB_RC + 0.6) * wb_c.a.y);
    }
    let sun = frame.sun.xyz;
    let L = normalize(select(-sun, sun, sun.y > -0.04));
    var sh = 1.0;
    if (dot(n, L) <= 0.0 && !coarse) {
        sh = 0.0;
    }
    if (wb_c.kind == 0u && !inner) {
        let Ll = vec3<f32>(dot(L, wb_c.x), dot(L, wb_c.y), dot(L, wb_c.z));
        let lr = dot(Ll.yz, radial.yz);
        let xe = WB_L * 0.5 - 3.0;
        let lip = 35.0 * wb_c.a.y;
        if (Ll.x > 0.05) {
            let rho_at = rho_l + lr * max(xe - pl.x, 0.0) / Ll.x;
            sh = sh * we_ss(lip - 2.5, lip + 1.5, rho_at);
        }
    }
    let pw = ro + rd * v.t;
    var b = 0.0;
    var mouth = 0.0;
    var glow = 0.0;
    let mo = wb_ho - wb_hx * 20.0;
    if (wb_c.kind == 0u) {
        b = wb_c.a.x - pl.x;
    } else if (wb_c.kind == 2u) {
        b = WB_HINGE - dot(pw - wb_ho, wb_hx);
    } else {
        b = WB_HINGE - pl.x;
    }
    if (wb_c.kind != 0u || inner) {
        let lv = mo - pw;
        let ld = length(lv);
        let fall = 1.0 / (1.0 + (ld / 24.0) * (ld / 24.0));
        mouth = wb_glow * fall * max(dot(n, lv / max(ld, 1.0e-3)), 0.0);
        if (inner) {
            mouth = mouth + wb_glow * 0.9 * we_ss(WB_HEAD, 220.0, b);
        }
    }
    var m2 = mat;
    if (inner && mat != WB_M_SCULK) {
        m2 = WB_M_THROAT;
    }
    if (mat == WB_M_SCULK) {
        glow = 1.0;
    } else if (m2 == WB_M_THROAT) {
        glow = mouth;
    }
    var tone = 0.9 + 0.2 * wb_hc(v.c, 31u + u32(wb_c.id + 64) * 7u + wb_c.kind);
    if (worn) {
        tone = tone * 1.38;
    }
    tone = tone * (0.84 + 0.32 * (0.5 + 0.5 * sin(b / 97.0 + 1.3) * sin(b / 41.0 + 0.7)));
    let oh = ro - wb_ho;
    let xh = dot(oh, wb_hx);
    let rh = length(oh - wb_hx * xh);
    let lit_in = max(wb_open, wb_gape);
    let behind = (1.0 - we_ss(-6.0, 6.0, xh) * lit_in) * (1.0 - we_ss(18.0, 28.0, rh));
    let deep = 1.0 - we_ss(24.0, 30.0, wb_eye_d);
    var inside = deep * (1.0 - we_ss(-6.0, 6.0, xh) * lit_in * select(0.0, 1.0, length(oh) < 95.0));
    if (wb_c.kind != 0u) {
        inside = max(behind, deep * we_ss(35.0, 45.0, length(oh)));
    }
    return WeHit(v.t, pw, n, m2, glow, b, blk, face, uv, ao, sh, mouth, tone, ns, inside);
}

// ---- the blocks' textures -----------------------------------------------------------------------------------------
fn wb_u(i: u32) -> u32 {
    let n = arrayLength(&mod_data);
    return select(0u, mod_data[min(i, n - 1u)], i < n);
}
fn wb_565(c: u32) -> vec3<f32> {
    return srgb_to_linear(vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0));
}
fn wb_tint(c: u32) -> vec3<f32> {
    if (c == 0xFFFFu) {
        return vec3<f32>(1.0);
    }
    return vec3<f32>(f32((c >> 11u) & 31u) / 31.0, f32((c >> 5u) & 63u) / 63.0, f32(c & 31u) / 31.0);
}
fn wb_face_st(m: u32, uv: vec2<f32>) -> vec2<f32> {
    let q = vec3<f32>(vec3<u32>(m, m >> 2u, m >> 4u) & vec3<u32>(3u)) - 1.0;
    let r = vec3<f32>(vec3<u32>(m >> 6u, m >> 8u, m >> 10u) & vec3<u32>(3u)) - 1.0;
    return fract(vec2<f32>(q.x + uv.x * q.z + uv.y * r.y, q.y + uv.x * r.x + uv.y * r.z) * 0.99999 + 0.000005);
}
fn wb_lod(t: f32) -> f32 {
    let px = 2.0 * tan(0.5 * frame.view_params.w) * frame.resolution.w;
    return log2(max(t * px * 16.0, 1.0e-4));
}
fn wb_tex(b: u32, face: u32, uv: vec2<f32>, lod: f32) -> vec4<f32> {
    if (wb_u(WE_BODY_T + 1u) != 0x3F800000u || b >= WB_NB) {
        return vec4<f32>(0.04, 0.04, 0.045, 1.0);
    }
    let o = WE_BODY_T + WB_BK0 + b * WB_BKW;
    let wa = wb_u(o);
    let wb2 = wb_u(o + 1u);
    let avg = wb_565(select(select(wa >> 16u, wb2 & 0xFFFFu, face == 1u), wa & 0xFFFFu, face == 0u));
    let f0 = wb_u(o + 2u + 3u * face);
    if ((f0 & 1u) == 0u || lod > 3.5) {
        return vec4<f32>(avg, 1.0);
    }
    let st = wb_face_st(wb_u(o + 4u + 3u * face), uv);
    let lv = clamp(lod, 0.0, f32(textureNumLevels(block_sprites) - 1));
    let c0 = textureSampleLevel(block_sprites, block_sampler, st, i32((f0 >> 2u) & 0x1FFFu), lv);
    var rgb = srgb_to_linear(c0.rgb * wb_tint(f0 >> 16u));
    if ((f0 & 2u) != 0u && c0.a < 0.5) {
        rgb = avg * 0.3;
    }
    let f1 = wb_u(o + 3u + 3u * face);
    if ((f1 & 1u) != 0u) {
        let c1 = textureSampleLevel(block_sprites, block_sampler, st, i32((f1 >> 2u) & 0x1FFFu), lv);
        rgb = mix(rgb, srgb_to_linear(c1.rgb * wb_tint(f1 >> 16u)), c1.a);
    }
    let la = max(dot(avg, vec3<f32>(0.3, 0.55, 0.15)), 1.0e-3);
    return vec4<f32>(rgb, mix(dot(rgb, vec3<f32>(0.3, 0.55, 0.15)) / la, 1.0, we_ss(1.5, 3.5, lod)));
}

// ---- light ----------------------------------------------------------------------------------------------------------
struct WbLt {
    L: vec3<f32>,
    sunc: vec3<f32>,
    amb: vec3<f32>,
    haze: vec3<f32>,
    day: f32,
}
// The scene's light, the Tsunami's (tsunami.wgsl's TsLight): the sun's way and colour from the frame (warm low, gone at
// night, the moon's dim blue then), the sky's ambient, a floor of night light.
fn wb_lights(sun: vec3<f32>) -> WbLt {
    let day = saturate(sun.y * 2.5 + 0.35);
    let up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    let skyl = srgb_to_linear(frame.sky_color.rgb);
    let sunc = mix(vec3<f32>(1.25, 1.18, 1.05), vec3<f32>(1.4, 0.62, 0.3), warm) * up + vec3<f32>(0.05, 0.07, 0.11) * (1.0 - up);
    let amb = mix(vec3<f32>(0.02, 0.025, 0.035), skyl * 0.6 + vec3<f32>(0.03), day);
    return WbLt(L, sunc, amb, srgb_to_linear(frame.fog_color.rgb), day);
}
// The game's fog on the land at d along a ray (its render-distance fog over the last tenth of the render distance,
// round the camera's column), and the Tsunami's thin haze of the distance.
fn wb_fog(c: vec3<f32>, d: f32, rd: vec3<f32>, fogl: vec3<f32>) -> vec3<f32> {
    let p = rd * d;
    let cyl = max(length(p.xz), abs(p.y));
    let r = frame.view_params.z;
    let f = saturate((cyl - 0.9 * r) / max(0.1 * r, 1.0)) * frame.fog_color.a;
    return mix(mix(c, fogl * 0.72, (1.0 - exp(-d * 0.00013)) * 0.75), fogl, f);
}

fn we_body_colour(hit: WeHit, rd: vec3<f32>, sun: vec3<f32>, t: f32) -> vec3<f32> {
    if (hit.inside > 0.999) {
        return wb_inside_colour(hit, rd, t);
    }
    let lt = wb_lights(sun);
    let lod = wb_lod(hit.d);
    let tx = wb_tex(hit.blk, hit.face, hit.uv, lod);
    let alb = tx.rgb * hit.tone;
    let n = normalize(mix(hit.n, hit.ns, 0.4 + 0.45 * we_ss(60.0, 400.0, hit.d)));
    let ndl = max(dot(n, lt.L), 0.0);
    // (lit as the land beside it is: the game's own shade on a block's faces (top full, bottom half, sides 0.8 and 0.6,
    // applied as the game does, to the gamma-encoded colour), the day's light over all of it (the moon's dim blue at
    // night), and the sun's way only as a modest lit and shade side on top)
    let fs = hit.n.x * hit.n.x * 0.6 + hit.n.z * hit.n.z * 0.8 + hit.n.y * hit.n.y * select(0.5, 1.0, hit.n.y > 0.0);
    let fsl = pow(fs, 2.2);
    let sunw = lt.sunc / max(dot(lt.sunc, vec3<f32>(0.2126, 0.7152, 0.0722)), 1.0e-3);
    let dayc = mix(vec3<f32>(0.05, 0.065, 0.1), mix(vec3<f32>(1.0), sunw, 0.25), lt.day);
    var c = alb * fsl * (dayc * (0.78 + 0.4 * ndl * hit.sh) * hit.ao + vec3<f32>(0.01));
    let hv = normalize(lt.L - rd);
    let spec = pow(max(dot(n, hv), 0.0), 40.0) * hit.sh * ndl;
    if (hit.blk == WB_B_PBLACK || hit.blk == WB_B_PDEEP || hit.blk == WB_B_PBBRICKS || hit.mat == WB_M_TOOTH) {
        c = c + lt.sunc * spec * 0.08;
    }
    if (hit.mat == WB_M_SCULK) {
        let pulse = 0.55 + 0.45 * sin(TAU * hit.b / 110.0 - 2.6 * t + 1.2);
        let spot = we_ss(1.25, 2.4, tx.w);
        c = c + alb * WB_TEAL * (1.2 + 3.5 * spot) * (0.35 + 0.65 * pulse) * (0.7 + 1.0 * (1.0 - lt.day));
    }
    if (hit.mouth > 0.0) {
        c = c + alb * WB_SOUL * hit.mouth * select(0.9, 0.45, hit.mat == WB_M_TOOTH);
    }
    if (hit.mat == WB_M_THROAT || (hit.mat == WB_M_SCULK && hit.mouth > 0.0)) {
        let deep = we_ss(WB_HINGE + 4.0, 120.0, hit.b);
        c = mix(c, WB_SOUL * wb_glow * 1.3 * min(hit.tone, 1.2), deep * 0.92);
    }
    let co = wb_fog(c, hit.d, rd, lt.haze);
    if (hit.inside > 0.001) {
        return mix(co, wb_inside_colour(hit, rd, t), hit.inside);
    }
    return co;
}

// ---- the worm's shadow on the world --------------------------------------------------------------------------------
fn we_body_shade(p: vec3<f32>, sun: vec3<f32>, t: f32) -> f32 {
    // (caught, the world outside isn't seen)
    if (wb_caught(t)) {
        return 1.0;
    }
    wb_setup_core(t);
    if (!wb_ok) {
        return 1.0;
    }
    wb_head_lite();
    let L = normalize(select(-sun, sun, sun.y > -0.04));
    var lit = 1.0;
    let r = 33.0;
    let lo = wb_sh - WE_LEN;
    let hi = wb_sh - 30.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        if (!wb_arch_box(p, L, i, WB_RB + 20.0 + select(0.0, 130.0, wb_alpha > 1.0e-4), 1.0e9)) {
            continue;
        }
        let h = (wb_s1[i] - wb_s0[i]) / f32(WE_TN);
        var pa = vec3<f32>(0.0);
        var have = 99u;
        for (var q = 0u; q < 16u + wb_zu; q = q + 1u) {
            if (!wb_chord_in(i, q)) {
                continue;
            }
            if (have != q) {
                pa = wb_cpt(i, q);
            }
            let pb = wb_cpt(i, q + 1u);
            have = q + 1u;
            let sa = wb_s0[i] + h * f32(q);
            let pc = WbPc(pa, pb, sa, sa + h);
            pa = pb;
            let a = max(pc.sa, lo);
            let bb = min(pc.sb, hi);
            if (bb > a) {
                let u0 = (a - pc.sa) / (pc.sb - pc.sa);
                let u1 = (bb - pc.sa) / (pc.sb - pc.sa);
                let dd = wb_ray_seg(p, L, mix(pc.a, pc.b, u0), mix(pc.a, pc.b, u1));
                let rr = r * wb_taper(wb_sh - a);
                lit = min(lit, we_ss(rr - 9.0, rr + 7.0, dd));
            }
        }
    }
    let hc = wb_lho + wb_lhx * 10.0;
    let dh = wb_ray_seg(p, L, hc - wb_lhx * 25.0, hc + wb_lhx * 10.0);
    let rh = 32.0 + 22.0 * max(wb_open, wb_gape);
    lit = min(lit, we_ss(rh - 9.0, rh + 8.0, dh));
    return lit;
}

// ---- inside -----------------------------------------------------------------------------------------------------------
fn wb_near_s(p: vec3<f32>) -> vec2<f32> {
    var bs = wb_sh;
    var bd = 1.0e9;
    var s = wb_sh - 20.0;
    for (var k = 0; k < 50 + wb_z; k = k + 1) {
        var sk = wb_sh - 20.0 - 40.0 * f32(k);
        if (k >= 47) {
            sk = s;
        }
        let q = we_pt(sk);
        let v = p - we_o - q.p;
        let d = length(v);
        if (k < 47) {
            if (d < bd) {
                bd = d;
                bs = sk;
            }
            if (k == 46) {
                s = bs;
            }
        } else {
            s = clamp(sk + clamp(dot(v, q.t), -40.0, 40.0), wb_sh - WE_LEN, wb_sh);
            bd = d;
        }
    }
    return vec2<f32>(s, bd);
}

// Whether the land's eye says a player is caught at t, in the body (from the jaws' shut to the eye passing the tip).
fn wb_caught(t: f32) -> bool {
    return we_w(WE_EYE_T) > 0.0 && t >= we_w(WE_EYE_T) && t < wb_tip_t();
}
// When the caught eye passes the snout's tip (the land's word 8; the let-go without it): from then on it is outside.
fn wb_tip_t() -> f32 {
    let tf = we_w(WE_EYE_T + 8u);
    return select(we_w(WE_EYE_T + 1u), tf, tf > 0.0);
}
fn we_body_sd(p: vec3<f32>, t: f32) -> f32 {
    // (caught: the camera, the carried player, is in the body from the shut to the let-go)
    if (wb_caught(t) && length(p) < 1.0) {
        return -1.0;
    }
    wb_setup_core(t);
    if (!wb_ok) {
        return 1.0e9;
    }
    wb_head_lite();
    var d = 1.0e9;
    let r = 33.0;
    let lo = wb_sh - WE_LEN;
    let hi = wb_sh - 30.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        for (var q = 0u; q < WB_NPC + wb_zu; q = q + 1u) {
            if (q >= 16u && length(p - we_o - select(wb_af[i], wb_at[i], q >= 19u)) > 260.0) {
                continue;
            }
            let pc = wb_piece(i, q);
            let a = max(pc.sa, lo);
            let bb = min(pc.sb, hi);
            if (bb > a) {
                let qa = mix(pc.a, pc.b, (a - pc.sa) / (pc.sb - pc.sa));
                let qb = mix(pc.a, pc.b, (bb - pc.sa) / (pc.sb - pc.sa));
                let ba = qb - qa;
                let u = clamp(dot(p - qa, ba) / max(dot(ba, ba), 1.0e-6), 0.0, 1.0);
                d = min(d, length(p - qa - ba * u) - r * wb_taper(wb_sh - mix(a, bb, u)));
            }
        }
    }
    let hc = wb_lho - wb_lhx * 18.0;
    let ba = wb_lhx * 40.0;
    let u = clamp(dot(p - hc, ba) / dot(ba, ba), 0.0, 1.0);
    d = min(d, length(p - hc - ba * u) - (34.0 - 18.0 * u * (1.0 - max(wb_open, wb_gape))));
    var near_run = d < 60.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        let a0 = we_o.xz + we_run_from(i).xz;
        let ab = we_o.xz + wb_af[i].xz - a0;
        let u = clamp(dot(p.xz - a0, ab) / max(dot(ab, ab), 1.0e-6), 0.0, 1.0);
        near_run = near_run || (length(p.xz - a0 - ab * u) < 110.0 && p.y < we_o.y + max(wb_af[i].y, we_run_from(i).y) + 10.0);
    }
    if (d > -6.0 && near_run) {
        var ns = vec2<f32>(we_eye_s(t), 0.0);
        if (we_eye(t).w > 0.5) {
            ns.y = length(p - we_o - we_pt(ns.x).p);
        } else {
            ns = wb_near_s(p);
        }
        d = min(d, ns.y - r * wb_taper(wb_sh - ns.x));
    }
    return d;
}

fn we_body_hit_coarse(ro: vec3<f32>, rd: vec3<f32>, tmax: f32, t: f32) -> f32 {
    wb_setup_core(t);
    if (!wb_ok) {
        return WE_MISS;
    }
    wb_head_lite();
    var best = min(tmax, WE_MISS);
    let lo = wb_sh - WE_LEN;
    let hi = wb_sh - 30.0;
    for (var i = 0u; i < wb_n; i = i + 1u) {
        if (wb_s1[i] + 120.0 < lo || wb_s0[i] - 120.0 > hi || !wb_arch_box(ro, rd, i, WE_R + 10.0 + select(0.0, 130.0, wb_alpha > 1.0e-4), best)) {
            continue;
        }
        let h = (wb_s1[i] - wb_s0[i]) / f32(WE_TN);
        var pa = vec3<f32>(0.0);
        var have = 99u;
        for (var q = 0u; q < 16u + wb_zu; q = q + 1u) {
            if (!wb_chord_in(i, q)) {
                continue;
            }
            if (have != q) {
                pa = wb_cpt(i, q);
            }
            let pb = wb_cpt(i, q + 1u);
            have = q + 1u;
            let sa = wb_s0[i] + h * f32(q);
            let a = max(sa, lo);
            let bb = min(sa + h, hi);
            if (bb > a) {
                let e = we_capsule(ro, rd, mix(pa, pb, (a - sa) / h), mix(pa, pb, (bb - sa) / h), WE_R * wb_taper(wb_sh - a));
                if (e > 0.0 && e < best) {
                    best = e;
                }
            }
            pa = pb;
        }
        for (var end = 0u; end < 2u + wb_zu; end = end + 1u) {
            if (!wb_near_hole(ro, rd, i, end, best)) {
                continue;
            }
            for (var q = 16u + 3u * end; q < 19u + 3u * end; q = q + 1u) {
                let pc = wb_piece(i, q);
                let a = max(pc.sa, lo);
                let bb = min(pc.sb, hi);
                if (bb > a) {
                    let e = we_capsule(ro, rd, mix(pc.a, pc.b, (a - pc.sa) / 40.0), mix(pc.a, pc.b, (bb - pc.sa) / 40.0), WE_R * wb_taper(wb_sh - a));
                    if (e > 0.0 && e < best) {
                        best = e;
                    }
                }
            }
        }
    }
    let hc = wb_lho - wb_lhx * 18.0;
    let e = we_capsule(ro, rd, hc, hc + wb_lhx * 40.0, 34.0 - 10.0 * (1.0 - max(wb_open, wb_gape)));
    if (e > 0.0 && e < best) {
        best = e;
    }
    return select(WE_MISS, best, best < min(tmax, WE_MISS));
}

// Whether the ray from the camera passes within the head's reach (its open petals and teeth included) before tmax:
// for a pass that gates the full hit on the coarse one, whose head is only the shut head's.
fn we_body_head_near(rd: vec3<f32>, tmax: f32, t: f32) -> bool {
    wb_setup_core(t);
    if (!wb_ok) {
        return false;
    }
    wb_head_lite();
    // (wb_head_lite's head is the unbent one's: 40 more for the head turned to look)
    let hr = 92.0 + 42.0 * max(wb_open, wb_gape);
    let hc = wb_lho + wb_lhx * 8.0;
    let hb = dot(hc, rd);
    let hd = dot(hc, hc) - hb * hb;
    return hd < hr * hr && hb + hr > 0.0 && hb - sqrt(hr * hr - hd) < tmax;
}

// The body on the ray eo + rd d (eo the eye, from the camera). es: caught, the eye's s along the path (on or near the
// centreline); < -1e8 not caught. Caught deep in the body: only the stretch of throat the eye is in (wb_tube_hit).
fn we_eye_hit_at(eo: vec3<f32>, rd: vec3<f32>, tmax: f32, t: f32, es: f32) -> WeHit {
    wb_eye_d = 1.0e9;
    wb_eye_o = eo;
    wb_tube = false;
    wb_trd = rd;
    var t0 = 0.0;
    // (the swallow's dark beat, the screen black (fx's beat, the land's words): nothing to trace)
    let ub = t - we_w(WE_EYE_T);
    if (es > -1.0e8 && we_w(WE_EYE_T) > 0.0 && ub > 0.35 && ub < we_w(WE_EYE_T + 3u)) {
        wb_tube = true;
        wb_tm = 600.0;
        return wb_miss();
    }
    if (es > -1.0e8 && !(we_w(WE_EYE_T) > 0.0 && t >= wb_tip_t())) {
        wb_setup_lite(t);
        wb_eb = wb_sh - es;
        if (wb_ok && wb_sh - es > WB_HEAD + 3.0 && es > wb_sh - WE_LEN + 40.0) {
            let h = wb_tube_hit(eo, rd, tmax, es);
            if (!wb_thead) {
                wb_tube = true;
                return h;
            }
            // (a ray into the head: the head's own blocks only (the teeth and the jaws), from where it leaves the tube)
            t0 = wb_thd;
            wb_headonly = t0 > 0.0;
        } else {
            // (by the head, caught: in it; looking out of it, only the head's blocks)
            wb_eye_d = 0.0;
            wb_headfwd = true;
        }
    }
    var h = we_body_hit(eo + rd * t0, rd, tmax - t0, t);
    wb_headonly = false;
    wb_headfwd = false;
    if (h.d < WE_MISS) {
        h.d = h.d + t0;
    }
    return h;
}
var<private> wb_eye_d: f32 = 1.0e9;
var<private> wb_eye_o: vec3<f32>;
var<private> wb_tube: bool;
var<private> wb_thead: bool;
var<private> wb_tm: f32;
var<private> wb_thd: f32;
var<private> wb_headonly: bool;
var<private> wb_headfwd: bool;
fn we_throat_miss() -> vec4<f32> {
    let fogc = WB_SOUL * (0.45 + 0.5 * wb_glow);
    if (wb_tube) {
        return vec4<f32>(WB_SOUL * (0.06 + 0.12 * wb_glow), wb_tm);
    }
    // (caught: the world only out through the open mouth (the ray through the hinge's plane within the opening), else
    // the throat's dark: never the sky through a gap in the walls)
    let o = max(wb_open, wb_gape);
    let dx = dot(wb_trd, wb_hx);
    let th = dot(wb_ho - wb_eye_o, wb_hx) / max(dx, 1.0e-4);
    let qh = wb_eye_o + wb_trd * th - wb_ho;
    let out = o > 0.05 && dx > 0.2 && length(qh - wb_hx * dot(qh, wb_hx)) < 20.0 + 40.0 * o;
    if (wb_eye_d < 27.0 && !out) {
        return vec4<f32>(WB_SOUL * (0.06 + 0.12 * wb_glow), 600.0);
    }
    if ((wb_eye_o - we_o).y < -6.0) {
        return vec4<f32>(WB_SOUL * (0.06 + 0.12 * wb_glow), 600.0);
    }
    return vec4<f32>(fogc, 1.0e9);
}

const WB_TNA: f32 = 108.0;
fn wb_tcell(c: vec2<f32>) -> f32 {
    let k = u32((i32(c.y) % 108 + 108) % 108);
    var h = floor(wb_h(u32(i32(c.x) + 100000), k, 71u) * 1.9) + 2.0 * wb_rib(c.x + 0.5);
    return select(h, 0.0, k % 9u == 0u);
}
fn wb_tpos(t: f32) -> vec4<f32> {
    let p = wb_eye_o + wb_trd * t - wb_tpa;
    let x = dot(p, wb_tax);
    let w = p - wb_tax * x;
    let f = clamp(x / wb_tl, 0.0, 1.0);
    let ph = atan2(dot(w, mix(wb_tfa.y, wb_tfb.y, f)), dot(w, mix(wb_tfa.z, wb_tfb.z, f)));
    let c = vec2<f32>(wb_sh - wb_tsa - wb_tdir * x, (ph / TAU + 0.5) * WB_TNA);
    return vec4<f32>(c, length(w), wb_tcell(floor(c)));
}
var<private> wb_trd: vec3<f32>;
var<private> wb_tpa: vec3<f32>;
var<private> wb_tax: vec3<f32>;
var<private> wb_tl: f32;
var<private> wb_tsa: f32;
var<private> wb_tdir: f32;
var<private> wb_tfa: WbFr;
var<private> wb_tfb: WbFr;
// The throat's radius b behind the snout's tip (the body's hollow); never less than the eye's distance off the axis.
fn wb_trad(b: f32) -> f32 {
    return max((WB_RT + 0.5) * wb_taper(b), wb_eye_d + 1.5);
}
// wb_fr's side at s from the path's words alone (no tables): the arch's plane, across a run turning from the last
// arch's to the next's.
fn wb_tfr(s: f32, tg: vec3<f32>) -> WbFr {
    var side = wb_plane(wb_n - 1u);
    for (var i = 0u; i < wb_n; i = i + 1u) {
        let s0 = we_arch_s0(i);
        if (s < s0) {
            let rs = we_run_s(i);
            let m = min(50.0, 0.3 * (s0 - rs));
            side = wb_slerp_h(select(wb_sign_plane(), wb_plane(max(i, 1u) - 1u), i > 0u), wb_plane(i), we_ss(rs + m, s0 - m, s));
            break;
        }
        if (s <= s0 + we_arch_len(i)) {
            side = wb_plane(i);
            break;
        }
    }
    return wb_frame_safe(vec3<f32>(0.0), tg, side);
}
// The caught eye's own hit: the tube round the centreline it is in, segment by segment (we_pt's chords, ends on a
// fixed grid of s, joined at planes square to the path), its wall's cells a height field; up to the collar's back.
fn wb_tube_hit(eo: vec3<f32>, rd: vec3<f32>, tmax: f32, es: f32) -> WeHit {
    let s_hi = wb_sh - WB_HEAD;
    wb_thead = false;
    wb_tm = 600.0;
    let s_lo = wb_sh - WE_LEN + 30.0;
    // (the segments' ends on a fixed grid of s (12 apart, 24 past 48 from the eye), so the walls stand still as the eye
    // moves)
    var sa = floor(es / 12.0) * 12.0;
    var qa = WePt(vec3<f32>(0.0), vec3<f32>(0.0, 1.0, 0.0));
    var dir = 1.0;
    var pa = vec3<f32>(0.0);
    var sb = sa;
    var tb = qa.t;
    var th = -1.0;
    var rw = WB_RT;
    var ax = qa.t;
    var len = 1.0;
    var tc = -1.0;
    var nst = vec3<f32>(0.0);
    for (var k = 0; k < 37 + wb_z; k = k + 1) {
        if (k > 0) {
            if ((dir > 0.0 && sa >= s_hi - 0.05) || sa <= s_lo) {
                wb_thead = dir > 0.0;
                break;
            }
            let g = select(24.0, 12.0, abs(sa - es) < 48.0);
            sb = min(select(ceil(sa / g - 1.0), floor(sa / g + 1.0), dir > 0.0) * g, s_hi);
        }
        let qb = we_pt(sb);
        let pb = we_o + qb.p;
        tb = qb.t;
        if (k == 0) {
            // (the first grid point: the way along, and how far off the axis the eye is; too far, the full trace)
            dir = select(-1.0, 1.0, dot(rd, qb.t) >= 0.0);
            let v = eo - pb;
            wb_eye_d = length(v - qb.t * dot(v, qb.t));
            if (wb_eye_d >= 20.0) {
                wb_thead = true;
                wb_thd = 0.0;
                return wb_miss();
            }
            pa = pb;
            qa = qb;
            continue;
        }
        len = max(length(pb - pa), 1.0e-3);
        ax = (pb - pa) / len;
        rw = wb_trad(wb_sh - 0.5 * (sa + sb));
        // (narrower than the last: the step's face where the ray came in)
        if (tc > 0.0) {
            let o = eo + rd * tc - pa;
            if (length(o - ax * dot(o, ax)) > rw) {
                th = tc;
                break;
            }
        }
        let te = wb_cyl(eo - pa, rd, ax, rw).y;
        let nb = qb.t * dir;
        let dn = dot(rd, nb);
        if (dn < 1.0e-5 || te < dot(pb - eo, nb) / dn) {
            th = te;
            break;
        }
        tc = dot(pb - eo, nb) / dn;
        nst = -nb;
        sa = sb;
        pa = pb;
        qa = qb;
    }
    if (wb_thead) {
        // (into the head: where the ray crosses the collar's back, for the head's own blocks from there)
        wb_thd = max(dot(pa - eo, qa.t) / max(dot(rd, qa.t), 1.0e-5), 0.0);
        return wb_miss();
    }
    if (th == tc && tc > 0.0) {
        let pm = eo + rd * th;
        return WeHit(th, pm, nst, WB_M_THROAT, wb_glow, wb_sh - sa, WB_B_TILES, 0u, fract(pm.xz + pm.y), 0.5, 1.0, 0.0,
            0.7, nst, 1.0);
    }
    if (th < 0.0 || th > min(tmax, 700.0)) {
        return wb_miss();
    }
    wb_trd = rd;
    wb_tpa = pa;
    wb_tax = ax;
    wb_tl = len;
    wb_tsa = sa;
    wb_tdir = dir;
    for (var e = 0; e < 2 + wb_z; e = e + 1) {
        let f = wb_tfr(select(sa, sb, e == 1), select(qa.t, tb, e == 1));
        if (e == 0) {
            wb_tfa = f;
        } else {
            wb_tfb = f;
        }
    }
    let ti = clamp(wb_cyl(eo - pa, rd, ax, rw - 3.2).y, 0.0, th);
    // (ten steps in from there to the wall, then halved four times: one path for both, so one copy of wb_tpos)
    var lo = ti;
    var hi = th;
    var q0 = vec4<f32>(0.0, 0.0, 0.0, -1.0);
    var q = q0;
    var found = false;
    for (var i = 1; i <= 14 + wb_z; i = i + 1) {
        let tt = select(mix(ti, th, f32(i) / 10.0), 0.5 * (lo + hi), found);
        let qt = wb_tpos(tt);
        if (qt.z > rw - qt.w || (!found && i == 10)) {
            hi = tt;
            q = qt;
            found = true;
        } else {
            lo = tt;
            q0 = qt;
        }
    }
    let pw = eo + rd * hi;
    let w = pw - pa - ax * dot(pw - pa, ax);
    let rn = w / max(length(w), 1.0e-4);
    var n = -rn;
    var face = 0u;
    var uv = fract(q.xy);
    let c0 = floor(q0.xy);
    let c1 = floor(q.xy);
    if (c0.x != c1.x && q0.w >= 0.0 && q0.w < q.w) {
        n = -sign(dot(rd, ax)) * ax;
        face = 2u;
        uv = vec2<f32>(fract(q.y), fract(q.z));
    } else if (c0.y != c1.y && q0.w >= 0.0 && q0.w < q.w) {
        let tg = cross(ax, rn);
        n = -sign(dot(rd, tg)) * tg;
        face = 2u;
        uv = vec2<f32>(fract(q.x), fract(q.z));
    }
    let k = u32((i32(c1.y) % 108 + 108) % 108);
    let hb = wb_h(u32(i32(c1.x) + 100000), k, 72u);
    var blk = select(select(WB_B_PBLACK, WB_B_DEEPSLATE, hb < 0.7), WB_B_TILES, hb < 0.42);
    var mat = WB_M_THROAT;
    if (k % 9u == 0u || hb > 0.9) {
        blk = WB_B_SCULK;
        mat = WB_M_SCULK;
    } else if (q.w >= 2.0) {
        blk = WB_B_DBRICKS;
    }
    return WeHit(hi, pw, n, mat, wb_glow, wb_sh - wb_tsa - dir * dot(pw - pa, ax), blk, face, uv,
        0.5 + 0.17 * q.w, 1.0, 0.0, 0.8 + 0.3 * hb, n, 1.0);
}

// The peristalsis at b behind the tip: bands of light running up the throat towards the head about once a second,
// brighter in the seconds after a swallow.
fn wb_band(b: f32, t: f32) -> f32 {
    let tc = we_w(WE_FX_T);
    let sw = 1.0 + 1.5 * select(0.0, exp((tc - t) / 2.5), tc > 0.0 && t > tc);
    return pow(0.5 + 0.5 * sin(TAU * (b / 46.0 + t * 1.1)), 6.0) * sw;
}
// For fx: the light the throat's walls give off at path position s and strike time t (linear; the sculk's glow and the
// peristalsis bands), to light what streams past the eye there; and the deep glow far down the throat ahead of the
// eye (towards the head, we_eye_dir(t)).
// (after we_eye_hit_at or we_throat_far this pixel: it uses their setup, so a call per block face brings in no more)
fn we_throat_glow(s: f32, t: f32) -> vec3<f32> {
    return WB_TEAL * (0.06 + 0.55 * wb_band(wb_sh - s, t));
}
fn we_throat_far(t: f32) -> vec3<f32> {
    wb_setup_lite(t);
    return WB_SOUL * (0.06 + 0.12 * wb_glow);
}
// The inside's light.
fn wb_inside_colour(h: WeHit, rd: vec3<f32>, t: f32) -> vec3<f32> {
    let tx = wb_tex(h.blk, h.face, h.uv, wb_lod(h.d));
    let alb = tx.rgb * h.tone;
    let band = wb_band(h.b, t);
    let fac = 0.4 + 0.6 * pow(max(dot(h.n, -rd), 0.0), 1.2);
    var col = alb * (WB_TEAL * (0.03 + 0.45 * band) * h.ao * fac + vec3<f32>(0.003, 0.004, 0.006));
    // (the head from inside: its teeth and gums in the mouth's soul light, and the day coming in as the jaws open)
    col = col + alb * WB_SOUL * (h.mouth * 0.6 + select(0.0, 0.05 + 0.15 * wb_glow, h.mat == WB_M_TOOTH));
    if (wb_ready_h == wb_t) {
        let dv = h.p - wb_ho;
        col = col + alb * vec3<f32>(0.7, 0.72, 0.75) * max(wb_open, wb_gape) / (1.0 + dot(dv, dv) / 900.0)
            * (0.3 + 0.7 * max(dot(h.n, wb_hx), 0.0));
    }
    if (h.mat == WB_M_SCULK) {
        let pulse = 0.5 + 0.5 * sin(TAU * h.b / 110.0 - 2.6 * t + 1.2);
        col = col + alb * WB_TEAL * (1.2 + 9.0 * we_ss(1.25, 2.4, tx.w)) * (0.25 + 0.6 * pulse + band);
    }
    let fogc = WB_SOUL * (0.06 + 0.12 * wb_glow) * select(0.3, 1.0, h.b < wb_eb);
    return mix(col, fogc, we_ss(30.0, 260.0, h.d));
}
var<private> wb_eb: f32 = 0.0;

fn we_capsule(ro: vec3<f32>, rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let ba = b - a;
    let oa = ro - a;
    let baba = dot(ba, ba);
    let bard = dot(ba, rd);
    let baoa = dot(ba, oa);
    let rdoa = dot(rd, oa);
    let oaoa = dot(oa, oa);
    let qa = baba - bard * bard;
    let qb = baba * rdoa - baoa * bard;
    let qc = baba * oaoa - baoa * baoa - r * r * baba;
    let h = qb * qb - qa * qc;
    if (h < 0.0) {
        return -1.0;
    }
    var y = -1.0;
    if (abs(qa) > 1.0e-6) {
        let t = (-qb - sqrt(h)) / qa;
        y = baoa + t * bard;
        if (y > 0.0 && y < baba) {
            return t;
        }
    } else {
        y = select(baba, 0.0, bard > 0.0);
    }
    let oc = select(ro - b, oa, y <= 0.0);
    let b2 = dot(rd, oc);
    let c2 = dot(oc, oc) - r * r;
    let h2 = b2 * b2 - c2;
    if (h2 > 0.0) {
        return -b2 - sqrt(h2);
    }
    return -1.0;
}
