// Orbital Laser's post pass for the Tsunami (laser 14). Like the Hurricane's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, hash, pcg) less the other lasers' own functions, followed by this file, and
// sets it for a tsunami strike only. Validate with tools/check-shader.sh.

// ---- laser 14: the tsunami ----------------------------------------------------------------------------------------
// No beam. A wave of dark, debris-laden water 130 blocks high and nearly three kilometres wide rises on the horizon and
// crosses the land at about 100 blocks a second: everything in its way is swept up in its foam, it towers over the
// player and washes over them, then drains away leaving mud and wreckage.
// The whole wave is closed-form, a function of where (s, u: along its way and across it) and when, so nothing is kept
// from frame to frame and a strike started part way in lands where it should: the front reaches a point at `ts_arr`,
// the water there rises over `ts_rise`, holds, then drains. strike/tsunami.rs keeps the TS_* and these functions in
// step (the model: the arrival, the envelope, the profile) and hands the pass its table (render.set-data).
const TS_LEN: f32 = 42.0;       // the strike's length (lasers.rs)
const TS_T: f32 = 9.0;          // when the front crosses the target
const TS_V0: f32 = 100.0;       // its speed there, blocks a second, slowing past it
const TS_C: f32 = 1.07e-5;      // (time to s: s / V0 + C s^2)
const TS_SEA: f32 = 100.0;      // the level the wave rises from, under the target's ground
const TS_A: f32 = 230.0;        // how far over that it rises at full strength: 130 over the target's ground
const TS_FACE: f32 = 70.0;      // the face's width, blocks
const TS_HOLD: f32 = 7.5;       // seconds the water holds at its height, then
const TS_DRAIN: f32 = 10.0;     // drains away over
const TS_LEAN: f32 = 0.34;      // seconds the crest leans out over the face (its overhang, about 35 blocks)

fn ts_sq(x: f32) -> f32 { return x * x; }

struct TsG {
    m: vec2<f32>,      // the way it moves (towards the player), on the ground
    n: vec2<f32>,      // across it
    dp: f32,           // how far the player stood from the target as it fired
    send: f32,         // how far past the target it runs before it is spent
    sd: f32,           // the strike's seed
}
fn ts_geo() -> TsG {
    var g: TsG;
    let a = wing_a();
    g.m = vec2<f32>(cos(a), sin(a));
    g.n = vec2<f32>(-g.m.y, g.m.x);
    let me = vec2<f32>(frame.mod_params[3].x, frame.mod_params[3].z) - anchor_xz();
    g.dp = length(me);
    g.send = min(g.dp + 120.0, 720.0);
    g.sd = fract(seed_v() * 0.6180339) * 40.0;
    return g;
}
// How long the front takes to reach distance s past the target.
fn ts_tau(s: f32) -> f32 {
    let sp = max(s, 0.0);
    return s / TS_V0 + TS_C * sp * sp;
}
// The front's speed at s, blocks a second.
fn ts_vel(s: f32) -> f32 {
    return 1.0 / (1.0 / TS_V0 + 2.0 * TS_C * max(s, 0.0));
}
// Where the middle of the front is at `t` (the inverse of ts_tau).
fn ts_front(t: f32) -> f32 {
    let tt = t - TS_T;
    if (tt < 0.0) {
        return tt * TS_V0;
    }
    let b = 1.0 / TS_V0;
    return (-b + sqrt(b * b + 4.0 * TS_C * tt)) / (2.0 * TS_C);
}
// The front's lead or lag along its length (seconds): bowed back at its flanks, in lobes that run ahead along some
// stretches of it.
fn ts_lag(s: f32, u: f32, sd: f32) -> f32 {
    let c = 9.0e-7 * u * u;
    let l1 = (fvnoise(vec2<f32>(u * 0.0042 + sd, s * 0.0014)) - 0.5) * 1.0;
    let l2 = (fvnoise(vec2<f32>(u * 0.017 + 3.1 + sd, s * 0.004 + 9.0)) - 0.5) * 0.22;
    return c + l1 + l2;
}
fn ts_arr(s: f32, u: f32, sd: f32) -> f32 {
    return TS_T + ts_tau(s) + ts_lag(s, u, sd);
}
// How strong the wave is where (s, u): grown over the first thousand blocks (shoaling), weaker as it runs inland, spent
// at its end, weaker towards its flanks, its height lumpy along the front. 1 at full strength.
fn ts_env(s: f32, u: f32, g: TsG) -> f32 {
    let shoal = 0.57 + 0.43 * smoothstep(-1000.0, -400.0, s);
    let dec = 1.0 - 0.45 * smoothstep(0.0, g.send, s);
    let end = 1.0 - smoothstep(g.send - 80.0, g.send + 30.0, s);
    let lat = 1.0 - smoothstep(650.0, 1400.0, abs(u));
    let lump = 1.0 + 0.03 * (fvnoise(vec2<f32>(u * 0.012 + g.sd, s * 0.003)) - 0.5) * 2.0 + 0.035 * (fvnoise(vec2<f32>(u * 0.045, s * 0.01 + 4.0)) - 0.5) * 2.0 + 0.02 * (fvnoise(vec2<f32>(u * 0.2, s * 0.02 + 7.0)) - 0.5) * 2.0;
    return shoal * dec * end * lat * lump;
}
// The water's height over its sea (0 to 1) `tau` seconds after the front reached a point whose front is `s` out: up the
// face, held, drained.
fn ts_prof(tau: f32, s: f32) -> f32 {
    if (tau <= 0.0) {
        return 0.0;
    }
    let tr = TS_FACE / ts_vel(s);
    let rr = clamp(tau / tr, 0.0, 1.0);
    let rise = 1.0 - pow(1.0 - rr, 2.3);
    let x = clamp((tau - tr - TS_HOLD) / TS_DRAIN, 0.0, 1.0);
    let drain = 1.0 - x * x * (3.0 - 2.0 * x);
    return rise * drain;
}
// The water's surface function at a point (relative to the target's ground): negative inside the water, positive in the
// air above it, and a big number where there is none.
fn ts_f(pa: vec3<f32>, t: f32, g: TsG) -> f32 {
    let s = dot(pa.xz, g.m);
    let u = dot(pa.xz, g.n);
    let env = ts_env(s, u, g);
    if (env < 0.03) {
        return 1.0e4;
    }
    let a = TS_A * env;
    let yb = clamp((pa.y + TS_SEA) / a, 0.0, 1.0);
    let tau = t - ts_arr(s, u, g.sd) + TS_LEAN * yb * yb + 0.05 * (fvnoise(vec2<f32>(u * 0.06 + g.sd, pa.y * 0.045)) - 0.5);
    let p = ts_prof(tau, s);
    if (p <= 0.0) {
        return 1.0e4;
    }
    return pa.y - (a * p - TS_SEA);
}

struct TsHit {
    t: f32,
    hit: bool,
}
// The first place the ray (from `ro`, relative to the target's ground) is in the water, between t0 and t1: marched down
// the way to the front's reach, with steps of a seventh of the way to the surface, then bisected.
fn ts_march(ro: vec3<f32>, rd: vec3<f32>, t0: f32, t1: f32, time: f32, g: TsG, j: f32) -> TsHit {
    var h: TsHit;
    h.hit = false;
    h.t = t1;
    let s0 = dot(ro.xz, g.m);
    let rs = dot(rd.xz, g.m);
    // (the wave lies behind its front, a little ahead of it where a lobe runs on: a ray that starts ahead of that and
    // heads away from it never meets it)
    let sf = ts_front(time) + 240.0;
    var tin = t0;
    if (s0 > sf) {
        if (rs >= -1.0e-4) {
            return h;
        }
        tin = max(tin, (s0 - sf) / -rs);
    }
    let ytop = TS_A - TS_SEA + 30.0;
    if (ro.y > ytop) {
        if (rd.y >= -1.0e-4) {
            return h;
        }
        tin = max(tin, (ro.y - ytop) / -rd.y);
    }
    var t = tin + j * 2.0;
    var tp = tin;
    for (var i = 0; i < 80; i = i + 1) {
        if (t > t1) {
            break;
        }
        let f = ts_f(ro + rd * t, time, g);
        if (f < 0.0) {
            // (bisected between the last step and this one)
            var a = tp;
            var b = t;
            for (var k = 0; k < 7; k = k + 1) {
                let mid = 0.5 * (a + b);
                if (ts_f(ro + rd * mid, time, g) < 0.0) {
                    b = mid;
                } else {
                    a = mid;
                }
            }
            h.t = b;
            h.hit = true;
            return h;
        }
        tp = t;
        t = t + clamp(f * 0.14, 0.7 + t * 0.0012, 60.0);
    }
    return h;
}
fn ts_normal(p: vec3<f32>, t: f32, g: TsG) -> vec3<f32> {
    let e = 1.2;
    let dx = ts_f(p + vec3<f32>(e, 0.0, 0.0), t, g) - ts_f(p - vec3<f32>(e, 0.0, 0.0), t, g);
    let dy = ts_f(p + vec3<f32>(0.0, e, 0.0), t, g) - ts_f(p - vec3<f32>(0.0, e, 0.0), t, g);
    let dz = ts_f(p + vec3<f32>(0.0, 0.0, e), t, g) - ts_f(p - vec3<f32>(0.0, 0.0, e), t, g);
    return normalize(vec3<f32>(dx, dy, dz) + vec3<f32>(1.0e-5));
}

fn ts_vn3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(fh31(i), fh31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(fh31(i + vec3<f32>(0.0, 1.0, 0.0)), fh31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(fh31(i + vec3<f32>(0.0, 0.0, 1.0)), fh31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(fh31(i + vec3<f32>(0.0, 1.0, 1.0)), fh31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}
fn ts_fbm3(p: vec3<f32>, oct: i32) -> f32 {
    var a = 0.5;
    var q = p;
    var s = 0.0;
    var n = 0.0;
    for (var i = 0; i < oct; i = i + 1) {
        s = s + a * ts_vn3(q);
        n = n + a;
        a = a * 0.5;
        // (turned a little between octaves so no octave's grid lines up with the last's)
        q = vec3<f32>(q.x * 0.8 - q.z * 0.6, q.y, q.x * 0.6 + q.z * 0.8) * 2.07 + vec3<f32>(5.1, 1.3, 7.7);
    }
    return s / n;
}

// What the light is: matched to the scene's, as the Hurricane's.
struct TsLight {
    L: vec3<f32>,
    amb: vec3<f32>,
    sunc: vec3<f32>,
    skyl: vec3<f32>,
    fogl: vec3<f32>,
    day: f32,
}

// The wave's surface where the ray met it: its colour (linear), and how much of the picture it takes (a thin foot lets
// the ground show through).
fn ts_surface(p: vec3<f32>, rd: vec3<f32>, ht: f32, time: f32, g: TsG, li: TsLight) -> vec4<f32> {
    let nrm0 = ts_normal(p, time, g);
    let s = dot(p.xz, g.m);
    let u = dot(p.xz, g.n);
    let env = ts_env(s, u, g);
    let a = TS_A * env;
    let tau = time - ts_arr(s, u, g.sd);
    let w = tau * ts_vel(s);
    let ybar = clamp((p.y + TS_SEA) / a, 0.0, 1.0);
    let hg = max(p.y, 0.0);
    // (the detail shrinks to nothing with distance: a pixel is many blocks out there)
    let lod = clamp(2.8 - log2(max(ht, 1.0) * 0.004 + 1.0) * 1.2, 0.0, 3.0);
    let noct = i32(clamp(lod + 1.0, 1.0, 4.0));
    let tv = vec3<f32>(p.x * 0.0, 0.0, 0.0);
    let uc = u * 0.05;
    let turb = ts_fbm3(vec3<f32>(uc, (p.y + time * 9.0) * 0.045, w * 0.05), noct);
    let strk = ts_vn3(vec3<f32>(u * 0.13, p.y * 0.011 + time * 0.9, w * 0.02));
    let fine = ts_fbm3(vec3<f32>(u * 0.4, (p.y + time * 14.0) * 0.3, w * 0.4), 2);
    // how steep the face is here
    let steep = 1.0 - abs(nrm0.y);
    var nrm = nrm0;
    // (the face's ripples: its normal jostled by the turbulence)
    let jit = vec3<f32>(turb - 0.5, 0.3 * (fine - 0.5), ts_vn3(vec3<f32>(uc + 7.0, p.y * 0.05, w * 0.05 + 3.0)) - 0.5) * 0.55 * lod / 3.0;
    nrm = normalize(nrm + jit);
    // ---- foam: the crest, patches on the face, tongues running down from the crest, and a churning foot ----------------
    let ragged = ts_fbm3(vec3<f32>(uc * 2.0 + 3.0, p.y * 0.1 + time * 2.0, w * 0.1), noct);
    let crestF = smoothstep(0.87 - 0.06 * ragged, 0.97, ybar);
    let patchf = smoothstep(0.66, 0.84, turb + 0.14 * ybar);
    let tongue = smoothstep(0.66, 0.86, strk) * smoothstep(0.55, 0.93, ybar + 0.25 * (ragged - 0.5)) * (0.5 + 0.5 * turb);
    let foot = (1.0 - smoothstep(4.0, 30.0 + 18.0 * turb, hg)) * smoothstep(0.38, 0.62, turb);
    var foam = clamp(crestF * (0.45 + 0.8 * ragged) + 0.6 * patchf * (0.3 + 0.7 * ybar) + 0.85 * tongue + 0.85 * foot, 0.0, 1.0);
    foam = foam * (0.55 + 0.45 * smoothstep(0.2, 0.55, fine + 0.35 * foam));
    // ---- the water: dark, brown-green, murky; at the thin, sunlit crest a green glow --------------------------------
    let fresnel = 0.03 + 0.97 * pow(1.0 - saturate(dot(nrm, -rd)), 5.0);
    let refl = reflect(rd, nrm);
    let skyc = mix(li.fogl, li.skyl, smoothstep(0.0, 0.55, refl.y)) * (0.55 + 0.45 * li.day);
    let dif = saturate(dot(nrm, li.L));
    let mud = vec3<f32>(0.11, 0.085, 0.052);
    let green = vec3<f32>(0.05, 0.12, 0.085);
    let thin = smoothstep(0.72, 1.0, ybar) * (0.4 + 0.6 * turb);
    var body = mix(mud, green, 0.35 + 0.4 * thin) * (li.amb * 1.4 + li.sunc * dif * 0.55 + vec3<f32>(0.004));
    let tra = pow(saturate(dot(rd, li.L)), 3.0) * thin;
    body = body + vec3<f32>(0.06, 0.26, 0.17) * li.sunc * tra * 1.2;
    // (under the lip it overhangs: dark)
    body = body * (1.0 - 0.6 * smoothstep(0.05, -0.5, nrm0.y));
    let wet = mix(body, skyc * 0.75, fresnel * (1.0 - 0.7 * foam));
    let spec = pow(saturate(dot(refl, li.L)), 90.0) * li.sunc * 2.0 * (1.0 - foam);
    let foamc = vec3<f32>(0.8, 0.79, 0.74) * (mix(li.amb, vec3<f32>(luminance(li.amb)), 0.5) * 1.5 + li.sunc * (0.3 + 0.5 * dif)) * (0.8 + 0.3 * fine);
    var c = mix(wet, foamc, foam) + spec;
    // the thin water at the foot lets the ground through
    let alpha = 1.0;
    return vec4<f32>(c, alpha);
}

fn tsunami(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let time = now();
    let k = intensity_v();
    let cam = frame.camera_position.xyz;
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    // (off the camera without its f32 rounding: far from the origin the camera moves in 1/128 block steps)
    let C = (vec3<f32>(anc.x, gy, anc.y) - cam) - camera_rest();
    let d = depth_at(uv);
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let g = ts_geo();
    let ro = -C;

    let sun = frame.sun.xyz;
    var li: TsLight;
    li.day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    li.L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    li.skyl = srgb_to_linear(frame.sky_color.rgb);
    li.fogl = srgb_to_linear(frame.fog_color.rgb);
    li.amb = mix(vec3<f32>(0.02, 0.025, 0.035), li.skyl * 0.6 + vec3<f32>(0.03), li.day);
    li.sunc = mix(vec3<f32>(1.25, 1.18, 1.05), vec3<f32>(1.4, 0.62, 0.3), warm) * sun_up + vec3<f32>(0.05, 0.07, 0.11) * (1.0 - sun_up);

    let pj = vec2<u32>(floor(in.position.xy));
    let j = f32(pcg(pj.x * 0x9E3779B1u ^ pcg(pj.y * 0x85EBCA6Bu ^ u32(time * 60.0))) & 0xFFFFu) / 65536.0;

    let h = ts_march(ro, rd, 0.0, min(scene_len, 6000.0), time, g, j);
    if (h.hit) {
        let sf = ts_surface(ro + rd * h.t, rd, h.t, time, g, li);
        col = mix(col, sf.rgb, sf.a);
        // (the haze of the distance)
        let haze = 1.0 - exp(-h.t * 0.00032);
        col = mix(col, li.fogl * 0.95, haze * 0.8);
    }
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return tsunami(in);
}
