// The World Eater's path (laser 19), as mod/src/strike/we_path.rs has it (contract v2): the first of the pass's files
// (after strike.wgsl up to its fs_main: worldeater_path.wgsl, worldeater_body.wgsl, worldeater.wgsl). Read the notes at
// the top of we_path.rs: the path is a chain of arches, each with two holes of its own (it breaches at A_i = from, dives
// at D_i = to); underground runs join them (from W0 into A_0, the first approach; from D_i into A_i+1: down, a quarter
// turn, level at depth, a quarter turn, up); after the last D straight down. It is read from the table in mod_data that
// strike/worldeater.rs gives (render.set-data). Every position here is from the strike's origin (the target's ground
// point: the block's middle, one up) unless it says "from the camera".
//
//   we_begin()          call it first, once a pixel: the origin from the camera (we_o) and the wormsign's way (we_sdir)
//   we_point(s)         the centreline s blocks along (s = 0 where it comes out at A_0), from the origin
//   we_pt(s)            the same and its unit tangent (the way the head goes)
//   we_at(s)            the centreline's point from the camera
//   we_head(t)          the head's s at strike time t; we_head_v(t) its speed; a body point b blocks behind the head is
//                       at we_point(we_head(t) - b), the tail at b = WE_LEN
//   we_time_at(s)       when the head is at s
//   we_mound(t)         where the head is while underground: the land over it, the mound's height, the dome over the
//                       breach to come (WeMnd)
//   we_n(), we_arch_*(i) the arches: from, to, apex, len, s0, t_out, t_in, hold; we_run_*(i) the run into arch i: where
//                       it starts, its level y, its length, whether it dives, its s; we_s_end() where the last goes in
//   we_sign(t), we_dome(t), we_dir_rule(me, seed): v1's wormsign from the constants alone (as the world warp has them)
// Keep in step with we_path.rs (its tests pin the numbers; tools/preview.py worldeater --set wedebug=1 draws Rust's
// samples over these and says in its top left corner whether they agree: green they do, red they don't).

// [warp too] (mod/build.rs puts what is between these marks before worldeater_warp.wgsl, the world warp)
// [generated constants] (mod/build.rs from mod/src/strike/we_path.rs's we_wgsl_consts: change them there; `cargo test we_wgsl_in_step` checks this copy, WE_REGEN=1 rewrites it)
const WE_R: f32 = 34.0;
const WE_LEN: f32 = 1836.0;
const WE_SPAN: f32 = 260.0;
const WE_APEX: f32 = 250.0;
const WE_SIGN: f32 = 420.0;
const WE_SIGN_T0: f32 = 0.0;
const WE_V_SIGN: f32 = 30.0;
const WE_SIGN_T: f32 = 8.5;
const WE_MOUND_R: f32 = 25.0;
const WE_MOUND_H: f32 = 9.0;
const WE_DOME_T0: f32 = 7.5;
const WE_DOME_LEAD: f32 = 1.5;
const WE_DOME_R: f32 = 45.0;
const WE_DOME_H: f32 = 10.0;
const WE_BREACH: f32 = 9.0;
const WE_BELLOW0: f32 = 12.5;
const WE_BELLOW1: f32 = 14.5;
const WE_BITE: f32 = 19.0;
const WE_TAIL_OUT: f32 = 27.0;
const WE_TAIL_IN: f32 = 31.0;
const WE_SINK0: f32 = 31.0;
const WE_SINK1: f32 = 40.0;
const WE_LEN_S: f32 = 46.0;
const WE_RUN_TURN: f32 = 67.6;
const WE_RUN_DEPTH: f32 = 80.0;
const WE_RUN_MIN: f32 = 160.0;
const WE_RUN_MAX: f32 = 600.0;
const WE_LOOP_D: f32 = 40.0;
const WE_LOOP_R: f32 = 50.0;
const WE_LOOP_ALPHA: f32 = 1.0471975511965976;
const WE_LOOP_LEN: f32 = 446.51914291880917;
const WE_ARCS_MAX: u32 = 6u;
const WE_T_COUNT: u32 = 0u;
const WE_T_MAGIC: u32 = 1u;
const WE_T_SIGN: u32 = 2u;
const WE_T_LEN: u32 = 4u;
const WE_T_T0: u32 = 5u;
const WE_T_V0: u32 = 6u;
const WE_A0: u32 = 16u;
const WE_AW: u32 = 48u;
const WE_R_FROM: u32 = 0u;
const WE_R_TO: u32 = 3u;
const WE_R_APEX: u32 = 6u;
const WE_R_LEN: u32 = 7u;
const WE_R_S: u32 = 8u;
const WE_R_RUN: u32 = 9u;
const WE_R_LOOP: u32 = 9u;
const WE_R_TOUT: u32 = 11u;
const WE_R_VOUT: u32 = 12u;
const WE_R_TIN: u32 = 13u;
const WE_R_VIN: u32 = 14u;
const WE_R_H0: u32 = 15u;
const WE_R_H1: u32 = 16u;
const WE_R_HC: u32 = 17u;
const WE_R_HV: u32 = 18u;
const WE_R_TH: u32 = 19u;
const WE_TN: u32 = 16u;
const WE_R_RUN_LEN: u32 = 36u;
const WE_R_RUN_DIVE: u32 = 37u;
const WE_R_RUN_LAND: u32 = 38u;
const WE_R_RUN_Y: u32 = 39u;
const WE_R_RUN_T: u32 = 40u;
const WE_R_RUN_V: u32 = 41u;
const WE_PATH_END: u32 = 512u;
const WE_BODY_T: u32 = 512u;
const WE_FX_T: u32 = 2048u;
const WE_LAND_T: u32 = 8192u;
const WE_DBG_T: u32 = 16384u;
const WE_EYE_T: u32 = 8704u;
// [end generated constants]
fn we_ss(a: f32, b: f32, x: f32) -> f32 {
    let t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
// The line's way from where the player is from the origin and the seed (we_path.rs's we_dir_rule): across the way they
// look at the target, to their right for an odd seed, their left for an even one.
fn we_dir_rule(me: vec3<f32>, seed: f32) -> vec2<f32> {
    let v0 = -me.xz;
    let l = length(v0);
    let v = select(vec2<f32>(0.0, -1.0), v0 / max(l, 1.0e-6), l > 1.0);
    let side = select(-1.0, 1.0, (u32(seed + 0.5) & 1u) == 1u);
    return vec2<f32>(-v.y, v.x) * side;
}
// The wormsign at t: x how far its mound has come from W0 towards P0 (0 to WE_SIGN), y how high it is.
fn we_sign(t: f32) -> vec2<f32> {
    let u = clamp(t / WE_SIGN_T, 0.0, 1.0);
    let g = 1.0 - pow(1.0 - u, 1.7);
    return vec2<f32>(WE_SIGN * g * g * (3.0 - 2.0 * g), WE_MOUND_H * we_ss(0.0, 1.6, t) * (1.0 - we_ss(7.6, 8.6, t)));
}
// How high the land over P0 is domed at t (none from the breach on).
fn we_dome(t: f32) -> f32 {
    return select(WE_DOME_H * we_ss(WE_DOME_T0, WE_BREACH, t), 0.0, t >= WE_BREACH);
}
// [end warp too]

// ---- the table ---------------------------------------------------------------------------------------------------
fn we_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn we_n() -> u32 {
    return min(u32(max(we_w(WE_T_COUNT), 0.0) + 0.5), WE_ARCS_MAX);
}
// Word k of arch i's record.
fn we_aw(i: u32, k: u32) -> f32 {
    return we_w(WE_A0 + i * WE_AW + k);
}
fn we_arch_from(i: u32) -> vec3<f32> {
    return vec3<f32>(we_aw(i, WE_R_FROM), we_aw(i, WE_R_FROM + 1u), we_aw(i, WE_R_FROM + 2u));
}
fn we_arch_to(i: u32) -> vec3<f32> {
    return vec3<f32>(we_aw(i, WE_R_TO), we_aw(i, WE_R_TO + 1u), we_aw(i, WE_R_TO + 2u));
}
fn we_arch_apex(i: u32) -> f32 { return we_aw(i, WE_R_APEX); }
fn we_arch_len(i: u32) -> f32 { return we_aw(i, WE_R_LEN); }
fn we_arch_s0(i: u32) -> f32 { return we_aw(i, WE_R_S); }
fn we_arch_t_out(i: u32) -> f32 { return we_aw(i, WE_R_TOUT); }
fn we_arch_t_in(i: u32) -> f32 { return we_aw(i, WE_R_TIN); }
// The hold (x h0, y h1, z its middle in blocks into the arch, w its speed); x < 0 for none.
fn we_arch_hold(i: u32) -> vec4<f32> {
    return vec4<f32>(we_aw(i, WE_R_H0), we_aw(i, WE_R_H1), we_aw(i, WE_R_HC), we_aw(i, WE_R_HV));
}
// Where the last arch goes in.
fn we_s_end() -> f32 {
    let n = we_n();
    if (n == 0u) {
        return 0.0;
    }
    return we_arch_s0(n - 1u) + we_arch_len(n - 1u);
}

// ---- DETAIL: how much the pass may spend (the QUALITY switch and the screen) ------------------------------------
// The mod's tier in frame.mod_params[3].w (params[15], lib.rs's `we_tier`): 2 FULL, 1 FAST, 0 PERFORMANCE.
fn we_tier() -> u32 {
    return u32(clamp(frame.mod_params[3].w + 0.5, 0.0, 2.0));
}
// The factor the pass scales its work by (step counts, piece counts, dust density, block detail), in (0, 1]: FULL 1 at any
// size; FAST 1 up to 1080 lines and less on a taller picture (1080 / height: 0.75 at 1440, 0.6 at 2160 and over);
// PERFORMANCE half of FAST's. 1 is the look as it was before DETAIL.
fn we_detail() -> f32 {
    let t = we_tier();
    if (t >= 2u) {
        return 1.0;
    }
    let s = clamp(1080.0 / max(frame.resolution.y, 1.0), 0.6, 1.0);
    return select(0.5 * s, s, t == 1u);
}

// The origin from the camera, and the wormsign's way: we_begin.
var<private> we_o: vec3<f32>;
var<private> we_sdir: vec2<f32>;
fn we_begin() {
    let cam = frame.camera_position.xyz;
    we_o = (vec3<f32>(frame.mod_params[1].x, frame.mod_params[2].w + 1.0, frame.mod_params[1].y) - cam) - frame.camera_rest.xyz;
    if (we_w(WE_T_MAGIC) > 0.5) {
        we_sdir = vec2<f32>(we_w(WE_T_SIGN), we_w(WE_T_SIGN + 1u));
    } else {
        // (no table yet, the first tick: as the warp works it out)
        let me = (frame.mod_params[3].xyz - cam) - frame.camera_rest.xyz - we_o;
        we_sdir = we_dir_rule(me, frame.mod_params[2].x);
    }
}

// ---- the centreline ------------------------------------------------------------------------------------------------
struct WePt {
    p: vec3<f32>,
    t: vec3<f32>,
}
fn we_herm(p0: f32, m0: f32, p1: f32, m1: f32, u: f32) -> f32 {
    let u2 = u * u;
    let u3 = u2 * u;
    return (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1;
}
// sp blocks into arch i.
fn we_arch_at(i: u32, sp: f32) -> WePt {
    let f = we_arch_from(i);
    let to = we_arch_to(i);
    let dd = to.xz - f.xz;
    let w = max(length(dd), 1.0e-4);
    let d = dd / w;
    let ax = 0.5 * w;
    let by = we_arch_apex(i);
    let h = we_arch_len(i) / f32(WE_TN);
    let x = clamp(sp / h, 0.0, f32(WE_TN));
    let k = min(u32(x), WE_TN - 1u);
    let t0 = we_aw(i, WE_R_TH + k);
    let t1 = we_aw(i, WE_R_TH + k + 1u);
    let m0 = h / max(length(vec2<f32>(ax * sin(t0), by * cos(t0))), 1.0e-6);
    let m1 = h / max(length(vec2<f32>(ax * sin(t1), by * cos(t1))), 1.0e-6);
    let th = we_herm(t0, m0, t1, m1, x - f32(k));
    let s = sin(th);
    let c = cos(th);
    let along = ax * (1.0 - c);
    let p = vec3<f32>(f.x + d.x * along, f.y + (to.y - f.y) * 0.5 * (1.0 - c) + by * s, f.z + d.y * along);
    let tg = normalize(vec3<f32>(d.x * ax * s, (to.y - f.y) * 0.5 * s + by * c, d.y * ax * s));
    return WePt(p, tg);
}
// The run into arch i: where it starts (x, the land's height there, z), its level centre's y, its length, whether it
// starts with a dive (all but arch 0's), and `s` where it starts.
fn we_run_from(i: u32) -> vec3<f32> {
    return vec3<f32>(we_aw(i, WE_R_RUN), we_aw(i, WE_R_RUN_LAND), we_aw(i, WE_R_RUN + 1u));
}
fn we_run_y(i: u32) -> f32 { return we_aw(i, WE_R_RUN_Y); }
fn we_run_len(i: u32) -> f32 { return we_aw(i, WE_R_RUN_LEN); }
fn we_run_dive(i: u32) -> bool { return we_aw(i, WE_R_RUN_DIVE) > 0.5; }
fn we_run_s(i: u32) -> f32 { return we_arch_s0(i) - we_run_len(i); }
// u blocks into the run into arch i (before it, for the first approach, level straight back): down, a quarter turn,
// level, a quarter turn up, up (we_path.rs's run_at).
fn we_run_at(i: u32, u0: f32) -> WePt {
    let rt = WE_RUN_TURN;
    let q = 1.5707963 * rt;
    let st = we_run_from(i);
    let a = we_arch_from(i);
    let dd = a.xz - st.xz;
    let hd = max(length(dd), 1.0e-4);
    let e = dd / hd;
    let y = we_run_y(i);
    var u = u0;
    var x0 = 0.0;
    if (we_run_dive(i)) {
        let v1 = st.y - (y + rt);
        if (u < v1) {
            return WePt(vec3<f32>(st.x, st.y - u, st.z), vec3<f32>(0.0, -1.0, 0.0));
        }
        u = u - v1;
        if (u < q) {
            let s = sin(u / rt);
            let c = cos(u / rt);
            let x = rt - rt * c;
            return WePt(vec3<f32>(st.x + e.x * x, y + rt - rt * s, st.z + e.y * x), vec3<f32>(e.x * s, -c, e.y * s));
        }
        u = u - q;
        x0 = rt;
    }
    let lv = hd - rt - x0;
    if (u < lv) {
        let x = x0 + u;
        return WePt(vec3<f32>(st.x + e.x * x, y, st.z + e.y * x), vec3<f32>(e.x, 0.0, e.y));
    }
    u = u - lv;
    if (u < q) {
        let s = sin(u / rt);
        let c = cos(u / rt);
        let x = hd - rt + rt * s;
        return WePt(vec3<f32>(st.x + e.x * x, y + rt - rt * c, st.z + e.y * x), vec3<f32>(e.x * c, s, e.y * c));
    }
    u = u - q;
    return WePt(vec3<f32>(a.x, y + rt + u, a.z), vec3<f32>(0.0, 1.0, 0.0));
}
// v1's loop under a shared knot: no longer part of the path (kept so the body's v1 code still compiles; don't use it).
fn we_loop_at(k: vec3<f32>, e: vec2<f32>, u: f32) -> WePt {
    let d0 = WE_LOOP_D;
    let r = WE_LOOP_R;
    let al = WE_LOOP_ALPHA;
    let l1 = r * al;
    let l2 = r * (3.14159265 + 2.0 * al);
    var q = vec4<f32>(0.0, d0 - u, 0.0, -1.0);
    if (u >= d0 + 2.0 * l1 + l2) {
        q = vec4<f32>(0.0, u - (d0 + 2.0 * l1 + l2), 0.0, 1.0);
    } else if (u >= d0 + l1 + l2) {
        let f = al - (u - d0 - l1 - l2) / r;
        q = vec4<f32>(-r + r * cos(f), -r * sin(f), sin(f), cos(f));
    } else if (u >= d0 + l1) {
        let b = al - (u - d0 - l1) / r;
        q = vec4<f32>(r * cos(b), -2.0 * r * sin(al) + r * sin(b), sin(b), -cos(b));
    } else if (u >= d0) {
        let f = (u - d0) / r;
        q = vec4<f32>(r - r * cos(f), -r * sin(f), sin(f), -cos(f));
    }
    let n = vec3<f32>(k.x, k.y - d0, k.z);
    return WePt(n + vec3<f32>(e.x * q.x, q.y, e.y * q.x), normalize(vec3<f32>(e.x * q.z, q.w, e.y * q.z)));
}
fn we_pt(s: f32) -> WePt {
    let n = we_n();
    if (n == 0u) {
        return WePt(vec3<f32>(0.0, s, 0.0), vec3<f32>(0.0, 1.0, 0.0));
    }
    for (var i = 0u; i < n; i = i + 1u) {
        let s0 = we_arch_s0(i);
        if (s < s0) {
            return we_run_at(i, s - (s0 - we_run_len(i)));
        }
        if (s <= s0 + we_arch_len(i)) {
            return we_arch_at(i, s - s0);
        }
    }
    let k = we_arch_to(n - 1u);
    return WePt(vec3<f32>(k.x, k.y - (s - we_s_end()), k.z), vec3<f32>(0.0, -1.0, 0.0));
}
fn we_point(s: f32) -> vec3<f32> {
    return we_pt(s).p;
}
fn we_tangent(s: f32) -> vec3<f32> {
    return we_pt(s).t;
}
// From the camera (after we_begin).
fn we_at(s: f32) -> vec3<f32> {
    return we_o + we_pt(s).p;
}

// ---- the caught eye (we_path.rs's WeEye: the land's words at WE_EYE_T) ----------------------------------------------
// s along the centreline at t: the cubic through the knots (time, s, ds/dt), held at the ends.
fn we_eye_s(t: f32) -> f32 {
    let n = u32(clamp(we_w(WE_EYE_T + 2u), 0.0, 64.0));
    if (n == 0u) {
        return 0.0;
    }
    let b = WE_EYE_T + 24u;
    if (t <= we_w(b)) {
        return we_w(b + 1u);
    }
    for (var i = 1u; i < n; i = i + 1u) {
        let t1 = we_w(b + 3u * i);
        if (t < t1) {
            let t0 = we_w(b + 3u * i - 3u);
            let dt = max(t1 - t0, 1.0e-6);
            return we_herm(we_w(b + 3u * i - 2u), we_w(b + 3u * i - 1u) * dt, we_w(b + 3u * i + 1u), we_w(b + 3u * i + 2u) * dt, (t - t0) / dt);
        }
    }
    return we_w(b + 3u * n - 2u);
}
// The caught eye at t (from the origin): xyz its place, from where they stood onto the centreline; w 1 from the jaws'
// shut to the let-go, else 0.
// Word i..i+3 of the eye's.
fn we_eye_v3(i: u32) -> vec3<f32> {
    return vec3<f32>(we_w(WE_EYE_T + i), we_w(WE_EYE_T + i + 1u), we_w(WE_EYE_T + i + 2u));
}
// Its flight out of the mouth at t (its start at word 8, 0: none, to the let-go): the cubic between the two places and
// velocities; xyz the place, w 1 while flying (0 before it).
fn we_eye_fly(t: f32, dv: bool) -> vec4<f32> {
    let t0 = we_w(WE_EYE_T + 8u);
    if (t0 <= 0.0 || t < t0) {
        return vec4<f32>(0.0);
    }
    let d = max(we_w(WE_EYE_T + 1u) - t0, 1.0e-3);
    let u = clamp((t - t0) / d, 0.0, 1.0);
    let u2 = u * u;
    let u3 = u2 * u;
    var h = vec4<f32>(2.0 * u3 - 3.0 * u2 + 1.0, (u3 - 2.0 * u2 + u) * d, -2.0 * u3 + 3.0 * u2, (u3 - u2) * d);
    if (dv) {
        h = vec4<f32>((6.0 * u2 - 6.0 * u) / d, 3.0 * u2 - 4.0 * u + 1.0, (6.0 * u - 6.0 * u2) / d, 3.0 * u2 - 2.0 * u);
    }
    return vec4<f32>(h.x * we_eye_v3(9u) + h.y * we_eye_v3(12u) + h.z * we_eye_v3(15u) + h.w * we_eye_v3(18u), 1.0);
}
fn we_eye(t: f32) -> vec4<f32> {
    let t0 = we_w(WE_EYE_T);
    if (t0 <= 0.0) {
        return vec4<f32>(0.0);
    }
    let f = we_eye_fly(t, false);
    if (f.w > 0.5) {
        return vec4<f32>(f.xyz, select(0.0, 1.0, t <= we_w(WE_EYE_T + 1u)));
    }
    let st = vec3<f32>(we_w(WE_EYE_T + 5u), we_w(WE_EYE_T + 6u), we_w(WE_EYE_T + 7u));
    let u = clamp((t - t0 - we_w(WE_EYE_T + 3u)) / max(we_w(WE_EYE_T + 4u), 1.0e-3), 0.0, 1.0);
    let m = u * u * u * (u * (6.0 * u - 15.0) + 10.0);
    return vec4<f32>(mix(st, we_point(we_eye_s(t)), m), select(0.0, 1.0, t >= t0 && t <= we_w(WE_EYE_T + 1u)));
}
// The way the eye travels at t: the centreline's, towards the head.
fn we_eye_dir(t: f32) -> vec3<f32> {
    let f = we_eye_fly(t, true);
    if (f.w > 0.5) {
        return normalize(f.xyz);
    }
    return we_tangent(we_eye_s(t));
}

// ---- the head's schedule -------------------------------------------------------------------------------------------
// Knot j of arch i (0 it comes out, 1 and 2 its hold's ends, 3 it goes in): x the time, y the head's s, z its speed;
// x < 0 for a hold it hasn't.
fn we_knot(i: u32, j: u32) -> vec3<f32> {
    let s0 = we_arch_s0(i);
    if (j == 0u) {
        return vec3<f32>(we_aw(i, WE_R_TOUT), s0, we_aw(i, WE_R_VOUT));
    }
    if (j == 3u) {
        return vec3<f32>(we_aw(i, WE_R_TIN), s0 + we_arch_len(i), we_aw(i, WE_R_VIN));
    }
    let h = we_arch_hold(i);
    if (h.x < 0.0) {
        return vec3<f32>(-1.0, 0.0, 0.0);
    }
    let half = 0.5 * h.w * (h.y - h.x);
    return select(vec3<f32>(h.y, s0 + h.z + half, h.w), vec3<f32>(h.x, s0 + h.z - half, h.w), j == 1u);
}
// The head's s (x) and speed (y) at strike time t: from the head's knot at W0 (the run into arch 0's start) on, through
// each arch's out, hold and in knots (we_path.rs's head).
fn we_head_sv(t: f32) -> vec2<f32> {
    let n = we_n();
    if (n == 0u) {
        return vec2<f32>(-1.0e4, 0.0);
    }
    var a = vec3<f32>(we_aw(0u, WE_R_RUN_T), we_run_s(0u), we_aw(0u, WE_R_RUN_V));
    if (t <= a.x) {
        return vec2<f32>(a.y + a.z * (t - a.x), a.z);
    }
    for (var i = 0u; i < n; i = i + 1u) {
        for (var j = 0u; j < 4u; j = j + 1u) {
            let b = we_knot(i, j);
            if (b.x < 0.0) {
                continue;
            }
            if (t <= b.x) {
                let dt = b.x - a.x;
                let u = clamp((t - a.x) / dt, 0.0, 1.0);
                let u2 = u * u;
                let s = we_herm(a.y, a.z * dt, b.y, b.z * dt, u);
                let v = ((6.0 * u2 - 6.0 * u) * a.y + (3.0 * u2 - 4.0 * u + 1.0) * a.z * dt + (-6.0 * u2 + 6.0 * u) * b.y + (3.0 * u2 - 2.0 * u) * b.z * dt) / dt;
                return vec2<f32>(s, v);
            }
            a = b;
        }
    }
    return vec2<f32>(a.y + a.z * (t - a.x), a.z);
}
fn we_head(t: f32) -> f32 {
    return we_head_sv(t).x;
}
fn we_head_v(t: f32) -> f32 {
    return we_head_sv(t).y;
}
// When the head is at s (a bisection: a few dozen we_head calls; not for every step of a march).
fn we_time_at(s: f32) -> f32 {
    var lo = -200.0;
    var hi = 400.0;
    for (var k = 0; k < 28; k = k + 1) {
        let m = 0.5 * (lo + hi);
        if (we_head(m) < s) {
            lo = m;
        } else {
            hi = m;
        }
    }
    return 0.5 * (lo + hi);
}

// ---- the head underground ------------------------------------------------------------------------------------------
// Where the head is while underground (we_path.rs's mound): at, the land over it (from the origin); h the mound's
// height there; dome the dome's height over the breach to come, at dome_at; arch the run it is in (-1: none, it is over
// the land or gone down for good).
struct WeMnd {
    at: vec3<f32>,
    h: f32,
    dome: f32,
    dome_at: vec3<f32>,
    arch: i32,
}
fn we_mound(t: f32) -> WeMnd {
    var out = WeMnd(vec3<f32>(0.0), 0.0, 0.0, vec3<f32>(0.0), -1);
    let s = we_head(t);
    let n = we_n();
    for (var i = 0u; i < n; i = i + 1u) {
        let s0 = we_arch_s0(i);
        if (s > s0 + we_arch_len(i)) {
            continue;
        }
        if (s >= s0 || (i > 0u && s < we_run_s(i))) {
            return out;
        }
        let p = we_run_at(i, s - we_run_s(i)).p;
        let st = we_run_from(i);
        let a = we_arch_from(i);
        let ex = a.xz - st.xz;
        let f = clamp(dot(p.xz - st.xz, ex) / max(dot(ex, ex), 1.0e-9), 0.0, 1.0);
        let rt = we_aw(i, WE_R_RUN_T);
        let t_out = we_arch_t_out(i);
        let rise = select(we_ss(rt, rt + 1.6, t), we_ss(rt + 0.5, rt + 2.1, t), we_run_dive(i));
        out.at = vec3<f32>(p.x, mix(st.y, a.y, f), p.z);
        out.h = WE_MOUND_H * rise * (1.0 - we_ss(t_out - 1.4, t_out - 0.4, t));
        out.dome = WE_DOME_H * we_ss(t_out - WE_DOME_LEAD, t_out, t);
        out.dome_at = a;
        out.arch = i32(i);
        return out;
    }
    return out;
}
