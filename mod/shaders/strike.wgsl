// Orbital Laser's post pass (capability `render`): one full-screen pass over the
// world, drawn after any shader pack. Everything is anchored in the world by
// rebuilding each pixel's position from the depth buffer and the camera
// matrices, or by tracing the view ray against shapes placed in the world
// (planes, cylinders, a volume). Nothing is painted flat on the screen except
// the lens: bloom, a streak, the flash.
//
// The mod hands it sixteen numbers each frame, `frame.mod_params`:
//   [0] target x, y, z (the point hit), strike clock in seconds
//   [1] hit block centre x, z, the wings' facing (radians), laser
//   [2] seed, intensity, capture mode (0 off, 3 video capture), hit block y
//
// Lasers:
//   0 Plasma   a raging plasma beam, forked lightning, a churning fireball, a smoke plume
//   1 Godly    the clouds part, a calm pillar of light comes down, halo rings and wings stand
//              in the sky, six pillars of light land round a golden sigil, a dome of light
//   2 Black hole  a singularity over the target bends the light round it; an accretion disk, a jet
//              out of both poles, the land dragged in, and it evaporates in a flash (`singularity`)
//   3 Meteor storm  meteors pound the land round the target, then one the size of a hill lands on it: a
//              fireball, a shockwave, ejecta across the sky and a sky gone brown with dust (`meteor_storm`)

fn target_x() -> f32 { return frame.mod_params[0].x; }
fn target_y() -> f32 { return frame.mod_params[0].y; }
fn target_z() -> f32 { return frame.mod_params[0].z; }
fn anchor_x() -> f32 { return frame.mod_params[1].x; }
fn anchor_z() -> f32 { return frame.mod_params[1].y; }
fn wing_a() -> f32 { return frame.mod_params[1].z; }
fn laser() -> f32 { return frame.mod_params[1].w; }
fn seed_v() -> f32 { return frame.mod_params[2].x; }
fn intensity_v() -> f32 { return max(frame.mod_params[2].y, 0.05); }
fn capture() -> f32 { return frame.mod_params[2].z; }
fn block_y() -> f32 { return frame.mod_params[2].w; }

const TAU: f32 = 6.2831853;
const T_FIRE: f32 = 4.0;
const PILLAR_R: f32 = 40.0;       // keep in step with strike.py: GODLY_PILLAR_R, GODLY_PILLAR_A0
const PILLAR_A0: f32 = 0.5235988;
const SIGIL_R1: f32 = 31.0;       // the inner etched ring (godly bowl_r + 3)

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash31(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    let o = vec2<f32>(17.3, 9.1);
    let q1 = p * 2.03 + o;
    let q2 = q1 * 2.03 + o;
    let q3 = q2 * 2.03 + o;
    let q4 = q3 * 2.03 + o;
    return 0.5 * vnoise(p) + 0.25 * vnoise(q1) + 0.125 * vnoise(q2) + 0.0625 * vnoise(q3) + 0.03125 * vnoise(q4);
}

fn vnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(hash31(i), hash31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(hash31(i + vec3<f32>(0.0, 1.0, 0.0)), hash31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(hash31(i + vec3<f32>(0.0, 0.0, 1.0)), hash31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(hash31(i + vec3<f32>(0.0, 1.0, 1.0)), hash31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

fn fbm3(p: vec3<f32>) -> f32 {
    let q = p * 2.07 + vec3<f32>(5.1, 1.3, 7.7);
    let r = q * 2.11 + vec3<f32>(2.9, 8.3, 4.1);
    return 0.55 * vnoise3(p) + 0.3 * vnoise3(q) + 0.15 * vnoise3(r);
}

// Cheaper noise for the heavy passes (the black hole, the meteor storm): an integer hash (PCG) instead of sin.
fn pcg(x: u32) -> u32 {
    let s = x * 747796405u + 2891336453u;
    let w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}
fn fh21(p: vec2<f32>) -> f32 {
    let q = bitcast<vec2<u32>>(vec2<i32>(floor(p)));
    return f32(pcg(q.x ^ pcg(q.y))) * (1.0 / 4294967295.0);
}
fn fh31(p: vec3<f32>) -> f32 {
    let q = bitcast<vec3<u32>>(vec3<i32>(floor(p)));
    return f32(pcg(q.x ^ pcg(q.y ^ pcg(q.z)))) * (1.0 / 4294967295.0);
}
fn fvnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(fh21(i), fh21(i + vec2<f32>(1.0, 0.0)), u.x), mix(fh21(i + vec2<f32>(0.0, 1.0)), fh21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn ffbm(p: vec2<f32>) -> f32 {
    return 0.55 * fvnoise(p) + 0.3 * fvnoise(p * 2.03 + vec2<f32>(17.3, 9.1)) + 0.15 * fvnoise(p * 4.1 + vec2<f32>(3.1, 5.7));
}
fn fvnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(fh31(i), fh31(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(fh31(i + vec3<f32>(0.0, 1.0, 0.0)), fh31(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(fh31(i + vec3<f32>(0.0, 0.0, 1.0)), fh31(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(fh31(i + vec3<f32>(0.0, 1.0, 1.0)), fh31(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}
fn ffbm3(p: vec3<f32>) -> f32 {
    return 0.62 * fvnoise3(p) + 0.38 * fvnoise3(p * 2.07 + vec3<f32>(5.1, 1.3, 7.7));
}

fn lava_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.02, 0.0, 0.0), vec3<f32>(0.7, 0.05, 0.0), smoothstep(0.0, 0.3, h));
    c = mix(c, vec3<f32>(1.0, 0.38, 0.02), smoothstep(0.25, 0.55, h));
    c = mix(c, vec3<f32>(1.0, 0.85, 0.35), smoothstep(0.5, 0.8, h));
    c = mix(c, vec3<f32>(1.0, 1.0, 1.0), smoothstep(0.8, 1.0, h));
    return c;
}

fn gold_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.12, 0.05, 0.0), vec3<f32>(0.85, 0.45, 0.05), smoothstep(0.0, 0.3, h));
    c = mix(c, vec3<f32>(1.0, 0.82, 0.3), smoothstep(0.25, 0.6, h));
    c = mix(c, vec3<f32>(1.0, 0.98, 0.9), smoothstep(0.6, 1.0, h));
    return c;
}

// The plasma fireball's colour by temperature: smoke, a violet-blue body, cyan, then white.
fn plasma_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.0), vec3<f32>(0.35, 0.08, 0.6), smoothstep(0.05, 0.3, h));
    c = mix(c, vec3<f32>(0.3, 0.6, 2.2), smoothstep(0.25, 0.55, h));
    c = mix(c, vec3<f32>(1.2, 2.0, 3.0), smoothstep(0.5, 0.8, h));
    c = mix(c, vec3<f32>(4.0, 4.0, 4.2), smoothstep(0.8, 1.0, h));
    return c;
}

// 1 when `theme` is i, else 0 (the option arrives as a float).
fn th_is(i: f32) -> f32 {
    return 1.0 - step(0.5, abs(laser() - i));
}

fn pick2(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return a * th_is(0.0) + b * th_is(1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

fn target_pos() -> vec3<f32> {
    var v = vec3<f32>(0.0);
    v.x = target_x();
    v.y = target_y();
    v.z = target_z();
    return v;
}

fn anchor_xz() -> vec2<f32> {
    var v = vec2<f32>(0.0);
    v.x = anchor_x();
    v.y = anchor_z();
    return v;
}

fn wing_dirs() -> vec4<f32> {
    // xy: the wings' facing (towards the shooter), zw: the span direction, both in the xz plane
    let a = wing_a();
    let c = cos(a);
    let s = sin(a);
    return vec4<f32>(c, s, -s, c);
}

// The strike's clock, kept by the mod (it starts at 0 when the designator fires).
fn now() -> f32 {
    return frame.mod_params[0].w;
}

fn phase_time() -> f32 {
    return now();
}

// Screen uv of a camera-relative world point; z < 0 when behind the camera.
fn project_rel(p: vec3<f32>) -> vec3<f32> {
    let clip = frame.projection * (frame.view * vec4<f32>(p, 1.0));
    let ndc = clip.xy / max(abs(clip.w), 1e-4);
    return vec3<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, select(-1.0, 1.0, clip.w > 0.0));
}

fn bolt_disp(len: f32, u: f32, seed: f32, tq: f32) -> f32 {
    let amp = len * 0.2;
    let n1 = (vnoise(vec2<f32>(u * 4.0 + seed, tq)) - 0.5) * 2.0;
    let n2 = (vnoise(vec2<f32>(u * 13.0 + seed * 3.1, tq * 1.7)) - 0.5) * 2.0;
    let n3 = (vnoise(vec2<f32>(u * 41.0 + seed * 5.3, tq * 2.3)) - 0.5) * 2.0;
    return (n1 * amp + n2 * amp * 0.38 + n3 * amp * 0.12) * smoothstep(0.0, 0.1, u);
}

// x: hot core, y: soft glow, z: position along the bolt (0 at its root)
fn bolt_line(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, seed: f32, tq: f32, wid: f32) -> vec3<f32> {
    let ab = b - a;
    let len = max(length(ab), 1.0e-4);
    let dir = ab / len;
    let nrm = vec2<f32>(-dir.y, dir.x);
    let ap = p - a;
    let u = clamp(dot(ap, dir) / len, 0.0, 1.0);
    let off = dot(ap, nrm) - bolt_disp(len, u, seed, tq);
    let along = dot(ap, dir) - u * len;
    let d = length(vec2<f32>(off, along));
    let w = wid * (1.0 - 0.75 * u);
    let core = exp(-pow(d / w, 2.0));
    let g = 1.0 / (1.0 + pow(d / (w * 3.0), 2.0));
    return vec3<f32>(core, g * g, u);
}

// Soft capsule between two points of a plane (world units): x = hot core, y = glow. Thinner towards the far end.
fn seg_soft(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, w: f32) -> vec2<f32> {
    let ab = b - a;
    let l2 = max(dot(ab, ab), 1.0e-8);
    let u = clamp(dot(p - a, ab) / l2, 0.0, 1.0);
    let d = length(p - (a + ab * u));
    let ww = w * (1.0 - 0.65 * u);
    return vec2<f32>(exp(-pow(d / ww, 2.0)), 1.0 / (1.0 + pow(d / (ww * 4.0), 2.0)));
}

// Distance-based edge of one equilateral triangle (circumradius R) at polar (r, ang); its edges face ang = 0, 120, 240 degrees.
fn tri_line(r: f32, ang: f32, R: f32, w: f32) -> f32 {
    let sector = TAU / 3.0;
    let a = ang - floor(ang / sector + 0.5) * sector;
    let d = r * cos(a) - R * 0.5;
    return exp(-pow(d / w, 2.0)) * (1.0 - smoothstep(R * 0.98, R * 1.04, r));
}

// Distance from the view ray to a vertical axis at xz `c` (camera-relative): x = ray distance at closest approach,
// y = distance from the axis there, z = height of that point. x < 0 when the axis is behind.
fn axis_hit(c: vec2<f32>, v2: vec2<f32>, vv: f32, cam_y: f32, rdy: f32) -> vec3<f32> {
    var t = length(c);
    var d = length(c);
    if (vv > 1.0e-5) {
        t = dot(c, v2) / vv;
        d = length(c - v2 * t);
    }
    return vec3<f32>(t, d, cam_y + rdy * t);
}

// ---- laser 2: the black hole ----------------------------------------------------------------
// A singularity hangs over the target. Light is bent round it by marching each view ray that passes near it through
// the hole's gravity (the photon orbit equation, r'' = -1.5 h^2 r / |r|^5, in horizon radii): rays that fall in are
// black, rays that cross the disk pick up its light, and the rest resample the scene (or the starry sky) in the
// direction they leave in. Its jet is a vertical column like the other lasers' beams.

const HOLE_H: f32 = 28.0;         // keep in step with strike.rs: HOLE_H, BH_END
const BH_END: f32 = 10.0;
const BH_RS: f32 = 3.6;           // the horizon's radius, in blocks
const DISK_IN: f32 = 2.6;         // the accretion disk, in horizon radii
const DISK_OUT: f32 = 9.0;
const LENS_R: f32 = 12.0;         // how far out light is bent, in horizon radii

// A dark sky of stars and violet haze, looking along `d`.
fn bh_sky(d: vec3<f32>, seed: f32) -> vec3<f32> {
    let q = d * 140.0;
    let f = fract(q) - 0.5;
    let h = fh31(floor(q) + vec3<f32>(seed));
    let star = step(0.975, h) * exp(-dot(f, f) * 40.0) * (0.5 + 4.0 * fract(h * 37.0));
    let tint = mix(vec3<f32>(0.7, 0.8, 1.25), vec3<f32>(1.25, 0.9, 0.7), fract(h * 91.0));
    let neb = ffbm3(d * 2.6 + vec3<f32>(seed * 0.01));
    let neb2 = ffbm3(d * 6.0 - vec3<f32>(2.0, 0.0, 1.0));
    let haze = vec3<f32>(0.10, 0.02, 0.17) * smoothstep(0.4, 0.85, neb) + vec3<f32>(0.02, 0.04, 0.13) * smoothstep(0.5, 0.9, neb2);
    return tint * star + haze;
}

// The disk's colour by temperature: dull red at the rim, orange, white, then blue-white at the inner edge.
fn disk_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.0), vec3<f32>(0.7, 0.07, 0.02), smoothstep(0.0, 0.25, h));
    c = mix(c, vec3<f32>(2.4, 0.75, 0.12), smoothstep(0.2, 0.5, h));
    c = mix(c, vec3<f32>(3.4, 2.5, 1.35), smoothstep(0.45, 0.75, h));
    c = mix(c, vec3<f32>(3.2, 3.6, 5.0), smoothstep(0.75, 1.0, h));
    return c;
}

// The scene at `uvs`, dimmed, its sky turned to the black hole's starry dark (seen along `dir`).
fn bh_scene(uvs: vec2<f32>, dir: vec3<f32>, seed: f32, sky_env: f32, dim: f32) -> vec3<f32> {
    let c = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uvs, 0.0).rgb) * dim;
    if (is_sky(depth_at(uvs))) {
        return mix(c, bh_sky(dir, seed), sky_env * 0.94);
    }
    return c;
}

// ---- the black hole's debris: blocks torn out of the ground, spiralling in, eaten or flung ----
// strike.rs tears the same blocks out of the ground at the same moments (debris_*): keep the formulas in step.
const DEBRIS: i32 = 160;

fn debris_angle(fi: f32, seed: f32) -> f32 { return fract(fi * 0.381966 + seed * 0.1137) * TAU; }
fn debris_r0(fi: f32, seed: f32) -> f32 { return 35.0 + 15.0 * fract(fi * 0.618034 + seed * 0.1234); }
fn debris_t(fi: f32) -> f32 { return 0.4 + 6.0 * fi / f32(DEBRIS) + 0.3 * fract(fi * 0.7548777); }
fn debris_big(fi: f32, seed: f32) -> bool { return fract(fi * 0.2763932 + seed * 0.0517) > 0.78; }

fn rot_axis(v: vec3<f32>, a: vec3<f32>, ang: f32) -> vec3<f32> {
    let c = cos(ang);
    let s = sin(ang);
    return v * c + cross(a, v) * s + a * dot(a, v) * (1.0 - c);
}

// One piece of debris: where it is (camera-relative), its radial direction from the hole, how stretched it is,
// how hot, how present (0: not there).
struct Piece {
    c: vec3<f32>,
    u: vec3<f32>,
    k: f32,
    glow: f32,
    alive: f32,
}

fn debris_piece(i: i32, ft: f32, seed: f32, cam: vec3<f32>, tgt: vec3<f32>, H: vec3<f32>, n: vec3<f32>, rs: f32) -> Piece {
    var pc: Piece;
    pc.alive = 0.0;
    pc.k = 1.0;
    pc.glow = 0.0;
    pc.u = vec3<f32>(0.0, 1.0, 0.0);
    pc.c = vec3<f32>(0.0);
    let fi = f32(i);
    let t_rip = debris_t(fi);
    let s = min(ft, BH_END) - t_rip;
    if (s <= 0.0) {
        return pc;
    }
    let a0 = debris_angle(fi, seed);
    let R0 = debris_r0(fi, seed);
    let big = debris_big(fi, seed);
    let h1 = fh21(vec2<f32>(fi, seed + 5.0));
    let h2 = fh21(vec2<f32>(fi, seed + 9.0));
    let T_in = 2.6 + 1.4 * h2;
    let flung = h1 < 0.28;
    let u_f = 0.5 + 0.2 * h2;
    let ub = s / T_in;
    let u = min(ub, select(1.0, u_f, flung));
    // the disk's plane, with world x and z laid onto it so the orbit starts where the block was torn out
    let E1 = normalize(vec3<f32>(1.0, 0.0, 0.0) - n * n.x);
    let E2 = normalize(vec3<f32>(0.0, 0.0, 1.0) - n * n.z - E1 * dot(vec3<f32>(0.0, 0.0, 1.0), E1));
    let rsn = max(rs, 0.6);
    let r = mix(rsn * 0.95, R0, pow(1.0 - u, 0.75));
    let th = a0 - (3.0 + 3.0 * h1) * u * u;                    // the same way round as the disk turns
    let lift = smoothstep(0.0, 0.45, u);
    // torn out of the ground where strike.rs removes it (block-aligned), then up into the disk's plane
    let src = floor(tgt.xz + vec2<f32>(cos(a0), sin(a0)) * R0) + select(vec2<f32>(0.5), vec2<f32>(0.0), big);
    let gy = block_y() + select(0.5, 0.0, big);           // the hit block's layer, which the blast levels the ground to
    let ground = vec3<f32>(src.x, gy, src.y) - cam;
    let ground_r = vec3<f32>(tgt.x - cam.x, gy - cam.y, tgt.z - cam.z) + vec3<f32>(cos(th), 0.0, sin(th)) * r;
    let gp = mix(ground, ground_r, smoothstep(0.0, 0.15, u));
    let dp = H + (E1 * cos(th) + E2 * sin(th)) * r;
    var c = mix(gp, dp, lift) + vec3<f32>(0.0, sin(lift * 3.14159) * 7.0, 0.0);
    var alive = smoothstep(0.0, 0.05, s);
    var stretch = 1.0 + min(9.0, pow(2.2 * rsn / r, 3.0));
    if (flung && ub > u_f) {
        // slingshot round the hole and away
        let dt = (ub - u_f) * T_in;
        let tdir = E1 * sin(th) - E2 * cos(th);
        c = c + (tdir * 65.0 + n * 16.0) * dt;
        alive = alive * (1.0 - smoothstep(2.5, 4.0, dt));
        stretch = 1.0;
    } else if (!flung) {
        // eaten: gone once it reaches the horizon
        alive = alive * (1.0 - step(1.0, ub));
    }
    if (ft > BH_END) {
        // what was still circling when it evaporated is thrown outwards
        let ef = ft - BH_END;
        c = c + normalize(c - H) * ef * 70.0;
        alive = alive * (1.0 - smoothstep(1.0, 2.5, ef));
        stretch = 1.0;
    }
    pc.c = c;
    pc.u = normalize(c - H + vec3<f32>(1.0e-4));
    pc.k = stretch;
    pc.glow = select(smoothstep(rsn * 4.0, rsn * 1.2, r), 0.0, flung && ub > u_f) * f32(ft <= BH_END);
    pc.alive = alive;
    return pc;
}

// A block's face colour (sRGB) at face pixel `px`: grass, dirt, stone, deepslate, log or leaves.
fn debris_tex(kind: i32, px: vec2<f32>, top: bool, side_y: f32, seed: f32) -> vec3<f32> {
    let nz = fh21(px + vec2<f32>(seed * 3.1, f32(kind) * 17.0));
    let nz2 = fh21(px * 1.7 + vec2<f32>(5.0, seed));
    switch kind {
        case 0: {
            if (top || side_y > 0.8) {
                return vec3<f32>(0.33, 0.55, 0.2) * (0.75 + 0.45 * nz);
            }
            return vec3<f32>(0.52, 0.36, 0.24) * (0.75 + 0.45 * nz);
        }
        case 1: { return vec3<f32>(0.52, 0.36, 0.24) * (0.75 + 0.45 * nz); }
        case 2: { return vec3<f32>(0.5, 0.5, 0.5) * (0.78 + 0.35 * nz) * (0.9 + 0.1 * nz2); }
        case 3: { return vec3<f32>(0.27, 0.27, 0.3) * (0.75 + 0.4 * nz); }
        case 4: {
            if (top) {
                let ring = fract(length(px - vec2<f32>(7.5)) * 0.35);
                return mix(vec3<f32>(0.68, 0.55, 0.34), vec3<f32>(0.5, 0.38, 0.22), step(0.5, ring)) * (0.9 + 0.2 * nz);
            }
            return vec3<f32>(0.4, 0.31, 0.19) * (0.7 + 0.5 * hash21(vec2<f32>(px.x, seed))) * (0.9 + 0.2 * nz);
        }
        default: {
            return vec3<f32>(0.2, 0.42, 0.13) * (0.5 + 0.8 * nz) * (0.6 + 0.4 * step(0.25, nz2));
        }
    }
}

fn singularity(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();

    // ---- timeline -------------------------------------------------------------
    let charging = select(0.0, saturate(time / T_FIRE), time < T_FIRE);
    let fire_t = time - T_FIRE;
    let fired = fire_t > 0.0;
    let ft = max(fire_t, 0.0);
    let left = saturate((BH_END - ft) / 1.6);                  // 1 until its last 1.6 s, then down to 0
    let life = select(0.0, smoothstep(0.0, 0.07, ft) * pow(left, 0.4), fired);
    // the horizon: nothing until the fire, then it is suddenly there, a touch too big for an instant before it settles;
    // at the end it shrinks and is gone
    let ring_in = 0.12 * exp(-ft * 6.0);
    let rs = BH_RS * life * (1.0 + ring_in + 0.03 * sin(time * 5.0));
    let rs_l = rs;
    let disk_env = smoothstep(0.0, 0.12, ft) * pow(left, 0.5) * f32(fired);
    let hot = 1.0 + 1.6 * (1.0 - left) + 2.2 * exp(-ft * 2.0);  // white-hot as it ignites, hotter again as it shrinks
    let jet_env = smoothstep(0.3, 0.9, ft) * (1.0 - smoothstep(BH_END - 1.2, BH_END - 0.3, ft)) * f32(fired);
    let ef = ft - BH_END;                                       // the evaporation's own clock
    let evap = select(0.0, exp(-ef * 2.6), ef > 0.0);
    let sky_env = smoothstep(0.5, 3.8, time) * (1.0 - smoothstep(BH_END + 2.0, BH_END + 10.0, ft));
    let open_ = select(0.0, exp(-fire_t * 7.0), fired);        // the instant it opens
    let implode = saturate((time - 2.7) / 1.3) * (1.0 - f32(fired));
    let pull_env = max(charging * charging, life) * (1.0 - smoothstep(BH_END, BH_END + 3.0, ft));
    // the last half second before it opens: the whole picture is sucked in towards one point
    let pinch = smoothstep(T_FIRE - 0.5, T_FIRE, time) * (1.0 - f32(fired));

    // ---- where it hangs, and how its disk lies (tipped towards whoever fired) ----
    let H = crel + vec3<f32>(0.0, HOLE_H, 0.0);
    let wd = wing_dirs();
    let n = normalize(vec3<f32>(0.0, 1.0, 0.0) + 0.32 * vec3<f32>(wd.x, 0.0, wd.y));
    let e1 = vec3<f32>(wd.z, 0.0, wd.w);
    let e2 = cross(n, e1);
    let pH = project_rel(H);
    let pt = project_rel(crel);

    // ---- camera shake and the imploding ring's refraction ----------------------
    let near_scale = 1.0 / (1.0 + length(H) / 30.0);
    let shake_amt = (open_ * 4.0 + jet_env * 0.5 + life * 0.25 + evap * 4.0 + implode * implode * 0.8) * k * 0.012 * near_scale;
    let shake = (vec2<f32>(vnoise(vec2<f32>(time * 37.0, 1.0)), vnoise(vec2<f32>(time * 41.0, 7.0))) - 0.5) * 2.0 * shake_amt;
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    let r0 = length(p0.xz - tgt.xz);
    let ri = 75.0 * pow(1.0 - implode, 1.6);
    let rw = ft * 58.0;                                         // the shockwave when it opens
    let ring_mask = select(0.0, exp(-pow((r0 - ri) / 3.0, 2.0)) * implode, !sky0) + select(0.0, exp(-pow((r0 - rw) / 3.5, 2.0)) * exp(-ft * 0.6), fired && !sky0);
    var rdir = uv - pt.xy;
    rdir = rdir / max(length(rdir), 1e-4);
    // the moment it opens a ripple of bent space tears out across the screen from it
    let sdv = (uv - pH.xy) * vec2<f32>(aspect, 1.0);
    let sdist = length(sdv);
    let gw = exp(-pow((sdist - ft * 2.4) / 0.07, 2.0)) * exp(-ft * 1.6) * f32(fired) * step(0.0, pH.z);
    let gw_dir = (uv - pH.xy) / max(sdist, 1e-4);
    let suck = (pH.xy - uv) * pinch * pinch * 0.32 * k * step(0.0, pH.z);
    let uv2 = clamp(uv + shake - rdir * ring_mask * 0.06 * k * pt.z + suck + gw_dir * gw * 0.045 * k, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene, darkened: light itself is being pulled away ----------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let P = cam + rel;
    let v2 = rd.xz;
    let vv = dot(v2, v2);
    let dim = clamp(1.0 - (0.5 * charging * charging + 0.55 * sky_env * f32(fired) + 0.2 * life + 0.5 * pinch) * k, 0.08, 1.0);
    let ca = (open_ * 0.02 + evap * 0.015 + ring_mask * 0.006 + gw * 0.03 + pinch * pinch * 0.012) * k;
    let ca_dir = (uv2 - pH.xy) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b)) * dim;
    if (sky) {
        col = mix(col, bh_sky(rd, seed), sky_env * 0.94);
    }
    var add = vec3<f32>(0.0);
    var swallowed = false;

    // ---- the lens: march the ray through the hole's gravity --------------------
    if (rs_l > 0.02) {
        let infl = LENS_R * rs_l;
        let tc = dot(H, rd);
        let b = length(H - rd * tc);
        let t0 = max(tc - infl, 0.0);
        if (b < infl && tc + infl > 0.0 && scene_len > t0) {
            var pp = (rd * t0 - H) / rs_l;                     // the ray, relative to the hole, in horizon radii
            var v = rd;
            var travel = t0;
            let hv = cross(pp, v);
            let h2 = dot(hv, hv);
            var trans = 1.0;
            var acc = vec3<f32>(0.0);
            var captured = false;
            var hit = false;
            var rmin = 1.0e9;
            for (var i = 0; i < 96; i = i + 1) {
                let r = length(pp);
                rmin = min(rmin, r);
                if (r < 1.0) {
                    captured = true;
                    break;
                }
                if (r > LENS_R + 0.5 && dot(pp, v) > 0.0) {
                    break;
                }
                let dt = clamp((r - 0.9) * 0.16, 0.03, 1.5);
                let prev = pp;
                let r2 = r * r;
                v = normalize(v - 1.5 * h2 * pp / (r2 * r2 * r) * dt);
                pp = pp + v * dt;
                travel = travel + dt * rs_l;
                if (!sky && travel > scene_len) {
                    hit = true;
                    break;
                }
                // crossing the disk's plane: its light, seen through whatever bending got the ray here
                let s0 = dot(prev, n);
                let s1 = dot(pp, n);
                if (disk_env > 0.001 && s0 * s1 < 0.0) {
                    let x = mix(prev, pp, s0 / (s0 - s1));
                    let dr = length(x);
                    if (dr > DISK_IN * 0.9 && dr < DISK_OUT) {
                        let dx = vec2<f32>(dot(x, e1), dot(x, e2));
                        // inner rings turn faster than outer ones (Kepler), so the gas shears into streaks
                        let rot = -time * 5.5 / pow(dr, 1.5);
                        let q = vec2<f32>(dx.x * cos(rot) - dx.y * sin(rot), dx.x * sin(rot) + dx.y * cos(rot));
                        let nz = fbm(q * 0.9 + vec2<f32>(seed, 3.0));
                        let bands = 0.55 + 0.45 * sin(dr * 7.0 + nz * 7.0);
                        let dens = saturate(bands * (0.35 + 1.1 * nz));
                        let edge = smoothstep(DISK_IN * 0.9, DISK_IN * 1.15, dr) * (1.0 - smoothstep(DISK_OUT * 0.55, DISK_OUT, dr));
                        // the side turning towards you is brighter and bluer (relativistic beaming)
                        let tdir = normalize(cross(n, x));
                        let beta = 0.62 * sqrt(DISK_IN / dr);
                        let g = sqrt(1.0 - beta * beta) / (1.0 - beta * dot(tdir, -v));
                        let temp = pow(DISK_IN / dr, 0.85) * (0.7 + 0.4 * nz) * g * 0.95 * hot;
                        let a_d = saturate(dens * edge * 1.1) * disk_env;
                        acc = acc + trans * a_d * disk_ramp(temp) * min(g * g * g, 4.0) * 1.6;
                        trans = trans * (1.0 - a_d * 0.92);
                    }
                }
                if (trans < 0.02) {
                    break;
                }
            }
            // how much the bending counts: all of it near the hole, none at the edge, so it meets the unbent world
            let w = 1.0 - smoothstep(LENS_R * 0.35, LENS_R * 0.95, rmin);
            var bent = vec3<f32>(0.0);
            if (!captured) {
                let dir_b = normalize(mix(rd, v, w));
                var far = H + pp * rs_l + v * 4000.0;
                if (hit) {
                    far = H + pp * rs_l;
                }
                let pr = project_rel(far);
                let uvb = mix(uv2, pr.xy, w);
                let on = pr.z > 0.0 && all(uvb > vec2<f32>(0.001)) && all(uvb < vec2<f32>(0.999));
                if (on || w < 0.01) {
                    bent = bh_scene(clamp(uvb, vec2<f32>(0.001), vec2<f32>(0.999)), dir_b, seed, sky_env, dim);
                } else if (dir_b.y > -0.03) {
                    bent = bh_sky(dir_b, seed) * sky_env + vec3<f32>(0.03, 0.025, 0.04) * (1.0 - sky_env);
                } else {
                    bent = vec3<f32>(0.02, 0.016, 0.022) * dim;
                }
            }
            col = bent * trans + acc * k;
            swallowed = captured;
            // the photon ring: light that went round the hole before getting out
            add = add + vec3<f32>(2.6, 1.7, 1.0) * exp(-pow((rmin - 1.52) / 0.05, 2.0)) * disk_env * select(1.0, 0.0, captured) * 1.4 * k;
        }
    }

    // ---- ground: the spiral it draws in while it charges, the land being dragged in, the disk's light ----
    if (!sky) {
        let dxg = P.xz - tgt.xz;
        let r = length(dxg);
        let ang = atan2(dxg.y, dxg.x);
        let dy = P.y - tgt.y;
        let near_y = 1.0 / (1.0 + dy * dy / 40.0);
        let lr = log(max(r, 0.5));
        // four spiral arms winding in (the same spiral strike.rs drags the land into), the outer ring closing in
        let conv = mix(48.0, 4.0, 1.0 - pow(1.0 - charging, 2.5));
        let arms = pow(0.5 + 0.5 * cos(4.0 * (ang - lr * 2.6) + time * (2.0 + 6.0 * charging)), 6.0);
        var ret = arms * (1.0 - smoothstep(conv - 6.0, conv, r)) * smoothstep(1.0, 4.0, r) * 0.6;
        ret = ret + exp(-pow((r - conv) / 0.4, 2.0)) * 1.4;
        ret = ret + exp(-pow((r - 3.0) / 0.25, 2.0)) * charging;
        add = add + vec3<f32>(0.75, 0.25, 1.4) * ret * charging * near_y * 1.8 * k;
        // the imploding ring, then the shockwave running out when it opens: a dark trough behind a bright edge
        add = add + vec3<f32>(0.9, 0.5, 1.6) * exp(-pow((r - ri) / 1.4, 2.0)) * implode * near_y * 4.0 * k;
        let wave = exp(-pow((r - rw) / 2.6, 2.0)) * exp(-ft * 0.5) * f32(fired) * near_y;
        add = add + vec3<f32>(1.1, 0.7, 1.8) * wave * 5.0 * k;
        col = col * (1.0 - exp(-pow((r - rw + 5.0) / 4.0, 2.0)) * exp(-ft * 0.5) * f32(fired) * near_y * 0.6);
        // streaks flowing in across the ground towards the crater
        let sa = ang - lr * 1.2;
        let flow = fbm(vec2<f32>(cos(sa), sin(sa)) * 9.0 + vec2<f32>(lr * 2.0 + time * 0.9, seed));
        let streak = smoothstep(0.55, 0.8, flow) * smoothstep(6.0, 14.0, r) * (1.0 - smoothstep(40.0, 85.0, r));
        add = add + vec3<f32>(0.5, 0.15, 0.9) * streak * life * near_y * 0.6 * k;
        // lit from above by the disk (warm) and the jet (violet)
        let lh = (cam + H) - P;
        let ld2 = dot(lh, lh);
        let light = vec3<f32>(1.8, 0.85, 0.4) * disk_env * hot * 700.0 / (ld2 + 300.0) + vec3<f32>(0.8, 0.4, 1.6) * jet_env * 30.0 / (r * r + 30.0);
        col = col + col * light * k / max(dim, 0.2);
        // the bore under the jet
        if (fired && r < 14.0) {
            let bore = (1.0 - smoothstep(3.0, 8.5, r)) * smoothstep(-2.0, 0.0, dy + 1.5) * (1.0 - smoothstep(0.0, 8.0, dy));
            let nz = fbm(dxg * 0.8 + vec2<f32>(time * 0.3, P.y * 0.5));
            col = col * (1.0 - bore * jet_env * 0.85);
            add = add + mix(vec3<f32>(0.5, 0.1, 1.2), vec3<f32>(1.6, 1.2, 2.2), nz) * bore * jet_env * 1.6 * k;
        }
    }

    // ---- the jet: a column of light pouring out of the hole, down into the ground and up to the sky ----
    let bh = axis_hit(crel.xz, v2, vv, cam.y, rd.y);
    if (bh.x > 0.0 && (jet_env > 0.001 || charging > 0.001)) {
        let dist = bh.y;
        let y_p = bh.z;
        let off = v2 * bh.x - crel.xz;
        let ang_b = atan2(off.y, off.x);
        let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, bh.x), !sky);
        let hy = tgt.y + HOLE_H;
        let away = abs(y_p - hy);
        // the designator's thread while it charges: violet, from the sky down to the target
        let des = exp(-pow(dist / 0.07, 2.0)) * charging * smoothstep(tgt.y - 1.0, tgt.y + 0.5, y_p);
        add = add + vec3<f32>(0.8, 0.2, 1.4) * des * vis * 2.5 * (0.7 + 0.3 * sin(time * 30.0));
        if (jet_env > 0.001) {
            // it shoots out of both poles: the down jet stops at the ground, the up jet runs on into the sky
            let reach_up = (ft - 0.3) * 260.0;
            let reach_dn = (ft - 0.3) * 120.0;
            let up_ = step(hy, y_p) * (1.0 - smoothstep(reach_up - 20.0, reach_up, away)) * exp(-away / 500.0);
            let dn_ = step(y_p, hy) * smoothstep(tgt.y - 1.5, tgt.y + 0.5, y_p) * (1.0 - smoothstep(reach_dn - 2.0, reach_dn, away));
            let from_h = smoothstep(rs * 1.1, rs * 2.2, away);
            let rj = (0.55 + 0.035 * away) * (1.0 + 0.15 * sin(time * 17.0 + away * 0.2)) * k;
            let core = exp(-pow(dist / (rj * 0.5), 2.0));
            let sheath = exp(-pow(dist / (rj * 1.8), 2.0));
            let halo = 1.0 / (1.0 + pow(dist / (rj * 6.0), 2.0));
            // knots of plasma racing away from the hole along the jet, wound round by two strands
            let knot = pow(0.5 + 0.5 * sin((away - time * 60.0) * 0.25), 8.0);
            let strand = pow(0.5 + 0.5 * sin(ang_b * 2.0 + away * 0.45 - time * 14.0), 10.0) * exp(-pow((dist - rj * 1.3) / (rj * 0.5), 2.0));
            let n2 = fbm(vec2<f32>(ang_b * 2.0, away * 0.08 - time * 8.0));
            var jb = core * vec3<f32>(6.0, 5.5, 9.0) + sheath * vec3<f32>(1.2, 0.5, 2.8) * (0.6 + 0.8 * n2) * (1.0 + 2.0 * knot);
            jb = jb + halo * vec3<f32>(0.5, 0.2, 1.0) * 0.35 + vec3<f32>(1.4, 1.0, 2.6) * strand;
            add = add + jb * (up_ + dn_) * from_h * jet_env * mix(0.25, 1.0, vis);
        }
    }

    // ---- the debris: blocks torn out of the ground, tumbling round the hole ------
    if (fired) {
        let tch = dot(H, rd);
        var best = scene_len;
        var dcol = vec3<f32>(0.0);
        var found = false;
        for (var i = 0; i < DEBRIS; i = i + 1) {
            let pc = debris_piece(i, ft, seed, cam, tgt, H, n, rs);
            if (pc.alive < 0.01) {
                continue;
            }
            let fi = f32(i);
            let big = debris_big(fi, seed);
            let hs = select(0.5, 1.0, big);
            // quick reject: the ray misses the piece's bounding sphere
            let tq = dot(pc.c, rd);
            let reach = hs * 1.8 * pc.k;
            if (tq < 0.0 || length(pc.c - rd * tq) > reach || tq - reach > best) {
                continue;
            }
            // into the piece's own space: undo the stretch towards the hole, then its tumble
            let ax = normalize(vec3<f32>(fh21(vec2<f32>(fi, 1.0)), fh21(vec2<f32>(fi, 2.0)), fh21(vec2<f32>(fi, 3.0))) - 0.5 + 1.0e-3);
            let spin = (ft - debris_t(fi)) * (1.5 + 3.0 * fh21(vec2<f32>(fi, 4.0))) * (1.0 + 2.0 * pc.glow);
            let sk = sqrt(pc.k);
            let ro = -pc.c;
            let ro_s = (ro - pc.u * dot(pc.u, ro)) * sk + pc.u * dot(pc.u, ro) / pc.k;
            let rd_s = (rd - pc.u * dot(pc.u, rd)) * sk + pc.u * dot(pc.u, rd) / pc.k;
            let ro_l = rot_axis(ro_s, ax, -spin) / hs;
            let rd_l = rot_axis(rd_s, ax, -spin) / hs;
            let inv = 1.0 / select(rd_l, vec3<f32>(1.0e-6), abs(rd_l) < vec3<f32>(1.0e-6));
            let ta = (vec3<f32>(-1.0) - ro_l) * inv;
            let tb = (vec3<f32>(1.0) - ro_l) * inv;
            let tlo = min(ta, tb);
            let thi = max(ta, tb);
            let tn = max(max(tlo.x, tlo.y), tlo.z);
            let tf = min(min(thi.x, thi.y), thi.z);
            if (tf < max(tn, 0.0) || tn > best || tn < 0.0) {
                continue;
            }
            if (swallowed && tn > tch) {
                continue;
            }
            best = tn;
            found = true;
            let lp = ro_l + rd_l * tn;
            let al = abs(lp);
            var nl = vec3<f32>(0.0, sign(lp.y), 0.0);
            var fuv = lp.xz;
            if (al.x >= al.y && al.x >= al.z) {
                nl = vec3<f32>(sign(lp.x), 0.0, 0.0);
                fuv = lp.zy;
            } else if (al.z >= al.y) {
                nl = vec3<f32>(0.0, 0.0, sign(lp.z));
                fuv = lp.xy;
            }
            let px = floor((fuv * 0.5 + 0.5) * 16.0 * hs * 2.0);
            let kind = min(i32(fh21(vec2<f32>(fi, seed + 13.0)) * 6.0), 5);
            let albedo = srgb_to_linear(debris_tex(kind, px, nl.y > 0.5, lp.y, seed + fi));
            let nw = normalize(rot_axis(nl, ax, spin));
            let sunl = 0.3 + 0.7 * max(dot(nw, normalize(vec3<f32>(0.3, 1.0, 0.2))), 0.0);
            let rl = length(pc.c - H) / max(rs, 0.6);
            let diskl = vec3<f32>(2.2, 1.0, 0.45) * max(dot(nw, -pc.u), 0.0) * disk_env * 6.0 / (1.0 + rl * 0.5);
            var cc = albedo * (sunl * dim + diskl);
            // tidal heating, then the redshift swallowing it as it reaches the horizon
            cc = cc + vec3<f32>(2.6, 0.7, 0.15) * pc.glow * pc.glow * 1.5 + vec3<f32>(0.6, 0.2, 1.0) * pc.glow * 0.3;
            cc = cc * smoothstep(1.0, 1.9, rl) * pc.alive;
            dcol = cc;
        }
        if (found) {
            col = dcol;
            add = add * 0.15;
        }
    }

    // ---- it evaporates: a blinding flash and a shell of light running out from where it was ----
    if (ef > 0.0 && ef < 8.0) {
        let tcs = dot(H, rd);
        let bs = length(H - rd * max(tcs, 0.0));
        let re = ef * 75.0;
        let shell = exp(-pow((bs - re) / (1.5 + re * 0.06), 2.0)) * exp(-ef * 0.7) * select(0.0, 1.0, tcs > 0.0 || length(H) < re);
        add = add + vec3<f32>(1.6, 1.2, 2.4) * shell * 2.5 * k;
        add = add + vec3<f32>(2.2, 2.0, 2.6) * evap * evap * 2.5 * k;
        add = add + vec3<f32>(1.2, 0.9, 1.8) * exp(-bs * 0.08) * evap * 3.0 * k;
    }

    // ---- the lens: the disk's bloom, a violet streak through the jet's foot ------
    if (pH.z > 0.0) {
        let dd = (uv - pH.xy) * vec2<f32>(aspect, 1.0);
        // the pinprick everything is being sucked into, just before it opens, and the burst of the opening
        add = add + vec3<f32>(2.0, 1.6, 3.0) * pinch * pinch * pinch * (1.0 / (1.0 + dot(dd, dd) * 9000.0) * 6.0 + 1.0 / (1.0 + dot(dd, dd) * 400.0) * 0.6) * k;
        add = add + vec3<f32>(1.6, 1.2, 2.4) * exp(-pow((sdist - ft * 2.4) / 0.02, 2.0)) * exp(-ft * 2.2) * f32(fired) * 0.8 * k;
        let bloom = 1.0 / (1.0 + dot(dd, dd) * 60.0);
        add = add + vec3<f32>(1.2, 0.6, 0.35) * bloom * disk_env * hot * 0.22 * k;
        let streak = exp(-abs(dd.y) * 240.0) * exp(-abs(dd.x) * 2.6);
        add = add + vec3<f32>(1.2, 0.5, 2.6) * streak * (disk_env * 0.6 + evap * 2.0) * k;
    }

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.25 + 0.45 * pull_env) * k)
        + vec3<f32>(0.25, 0.05, 0.5) * smoothstep(0.35, 1.0, vg) * pull_env * 0.06 * k;
    outc = aces(outc * 0.9);
    var srgb = linear_to_srgb(outc);
    // the instant it opens the picture goes negative
    srgb = mix(srgb, vec3<f32>(1.0) - srgb, saturate(open_ * 1.2 * k));
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    return vec4<f32>(srgb, 1.0);
}

// Gradient noise (smooth, without the square grid value noise shows), from a cheap integer hash, for the meteor
// storm's fire and smoke. Each octave is turned so their grids never line up.
fn pcg3d(v0: vec3<u32>) -> vec3<u32> {
    var v = v0 * 1664525u + 1013904223u;
    v.x = v.x + v.y * v.z;
    v.y = v.y + v.z * v.x;
    v.z = v.z + v.x * v.y;
    v = v ^ (v >> vec3<u32>(16u));
    v.x = v.x + v.y * v.z;
    v.y = v.y + v.z * v.x;
    v.z = v.z + v.x * v.y;
    return v;
}
fn grad3(i: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(pcg3d(bitcast<vec3<u32>>(vec3<i32>(i)))) * (2.0 / 4294967295.0) - 1.0;
}
fn gnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = p - i;
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let n000 = dot(grad3(i), f);
    let n100 = dot(grad3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0));
    let n010 = dot(grad3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0));
    let n110 = dot(grad3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0));
    let n001 = dot(grad3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0));
    let n101 = dot(grad3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0));
    let n011 = dot(grad3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0));
    let n111 = dot(grad3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0));
    let x0 = mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y);
    let x1 = mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y);
    return mix(x0, x1, u.z) * 0.75 + 0.5;
}
fn gfbm3(p: vec3<f32>, octaves: i32) -> f32 {
    let m = mat3x3<f32>(0.00, 0.80, 0.60, -0.80, 0.36, -0.48, -0.60, -0.48, 0.64);
    var q = p;
    var a = 0.5;
    var s = 0.0;
    var w = 0.0;
    for (var o = 0; o < octaves; o = o + 1) {
        s = s + a * gnoise3(q);
        w = w + a;
        q = m * q * 2.03 + vec3<f32>(1.7, 9.2, 5.3);
        a = a * 0.5;
    }
    return s / w;
}
fn grad2(i: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(pcg3d(bitcast<vec3<u32>>(vec3<i32>(vec2<i32>(i), 7))).xy) * (2.0 / 4294967295.0) - 1.0;
}
fn gnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = p - i;
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = dot(grad2(i), f);
    let b = dot(grad2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0));
    let c = dot(grad2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0));
    let d = dot(grad2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.9 + 0.5;
}
fn gfbm2(p: vec2<f32>) -> f32 {
    let m = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
    let q1 = m * p * 2.03 + vec2<f32>(1.7, 9.2);
    let q2 = m * q1 * 2.01 + vec2<f32>(5.3, 2.8);
    return (0.5 * gnoise2(p) + 0.25 * gnoise2(q1) + 0.125 * gnoise2(q2)) / 0.875;
}
// A dither that changes from pixel to pixel without clumping, to hide the steps of a march.
fn ign(px: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(px, vec2<f32>(0.06711056, 0.00583715))));
}

// ---- laser 3: the meteor storm ------------------------------------------------------------------
// Seventy-two meteors come in from one direction and land over the land round the target, then one the size of a
// hill comes down on the target itself. Each meteor is a glowing head and a trail on its path, hidden by the terrain
// in front of it (so it disappears into the ground where it really hits), a fireball and a ring on the ground where it
// lands. strike.rs digs the craters at the same places and moments (met_*): keep the formulas in step.

const MET_N: i32 = 72;             // keep in step with strike.rs: MET_N, MET_SPAN, BIG_T
const MET_SPAN: f32 = 120.0;
const BIG_T: f32 = 13.5;           // the big one lands this long after the fire, on the target
const BIG_R: f32 = 16.0;           // its radius, in blocks
const MET_V: f32 = 150.0;          // how fast the small ones are going when they land, blocks a second
const MET_A: f32 = 45.0;           // how hard the air slows them (they come in four times faster)
const MET_ENTRY: f32 = 5.0;        // seconds from the top of their path to the ground
const BIG_V: f32 = 260.0;
const MET_END: f32 = 34.0;         // when everything has faded (the strike runs 38 s)

// A meteor's own random numbers (`k` picks which): an integer hash, so strike.rs gets exactly the same ones.
fn mh(i: u32, seed: u32, k: u32) -> f32 { return f32(pcg(i ^ pcg(seed ^ pcg(k)))) * (1.0 / 4294967296.0); }
// Where a meteor lands (x, z off the target) and when (seconds after the fire). A third of them come down together,
// the fragments of one that broke up, close to one another and within a second or so of each other; the rest
// anywhere, at any time.
fn met_where(fi: f32, seed: f32) -> vec3<f32> {
    let i = u32(fi);
    let s = u32(seed);
    if (mh(i, s, 5u) < 0.33) {
        let c = 100u + min(u32(mh(i, s, 6u) * 6.0), 5u);
        let ca = mh(c, s, 1u) * TAU;
        let cr = 24.0 + (MET_SPAN - 30.0) * sqrt(mh(c, s, 2u));
        let oa = mh(i, s, 7u) * TAU;
        let orr = 3.0 + 11.0 * mh(i, s, 8u);
        let pos = vec2<f32>(cos(ca), sin(ca)) * cr + vec2<f32>(cos(oa), sin(oa)) * orr;
        return vec3<f32>(pos, 3.0 + 8.5 * mh(c, s, 3u) + 1.4 * mh(i, s, 9u));
    }
    let a = mh(i, s, 1u) * TAU;
    let r = 14.0 + (MET_SPAN - 14.0) * sqrt(mh(i, s, 2u));
    return vec3<f32>(cos(a) * r, sin(a) * r, 2.5 + 9.5 * mh(i, s, 3u));
}
fn met_t(fi: f32, seed: f32) -> f32 { return met_where(fi, seed).z; }
// How far up its path a meteor is `tau` seconds before it lands, and when (seconds before landing) it passed `l`.
fn met_path(tau: f32) -> f32 { return MET_V * tau + MET_A * tau * tau; }
fn met_when(l: f32) -> f32 { return (sqrt(MET_V * MET_V + 4.0 * MET_A * l) - MET_V) / (2.0 * MET_A); }
fn met_off(fi: f32, seed: f32) -> vec2<f32> { return met_where(fi, seed).xy; }
fn met_class(fi: f32, seed: f32) -> i32 {
    let h = mh(u32(fi), u32(seed), 4u);
    return select(select(2, 1, h < 0.87), 0, h < 0.6);
}
// Where a meteor comes from (pointing back up its path): all from one part of the sky, a little scattered.
fn met_dir(fi: f32, seed: f32, elev: f32, spread: f32) -> vec3<f32> {
    let phi = fract(seed * 0.0911) * TAU + (fh21(vec2<f32>(fi, 31.0)) - 0.5) * 0.45 * spread;
    let e = elev + (fh21(vec2<f32>(fi, 37.0)) - 0.5) * 0.3 * spread;
    return vec3<f32>(cos(e) * cos(phi), sin(e), cos(e) * sin(phi));
}

// The closest approach of the view ray (from the eye, along `rd`) to the segment ab (camera-relative):
// x = the distance between them, y = how far along the ray, z = where along ab (0 at a).
fn ray_seg(rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    let ab = b - a;
    let l2 = max(dot(ab, ab), 1.0e-6);
    let rab = dot(rd, ab);
    let den = l2 - rab * rab;
    var s = clamp(select(0.0, (rab * dot(rd, a) - dot(a, ab)) / den, den > 1.0e-6), 0.0, 1.0);
    let t = max(dot(rd, a + ab * s), 0.0);
    s = clamp(dot(rd * t - a, ab) / l2, 0.0, 1.0);
    return vec3<f32>(length(rd * t - (a + ab * s)), t, s);
}

fn meteor_storm(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();

    // ---- timeline -------------------------------------------------------------
    let charging = select(0.0, saturate(time / T_FIRE), time < T_FIRE);
    let fire_t = time - T_FIRE;
    let fired = fire_t > 0.0;
    let ft = max(fire_t, 0.0);
    let dtb = ft - BIG_T;                                       // the big one's clock: 0 at its impact
    let hit_b = dtb > 0.0;
    let end_env = 1.0 - smoothstep(MET_END - 6.0, MET_END, ft);
    let storm_env = smoothstep(0.0, 1.5, time) * (1.0 - smoothstep(BIG_T + 2.0, BIG_T + 6.0, ft));
    let approach = smoothstep(BIG_T - 6.0, BIG_T, ft) * (1.0 - f32(hit_b));
    let flash = select(0.0, exp(-dtb * 2.2), hit_b);
    let dust_env = smoothstep(BIG_T + 0.5, BIG_T + 7.0, ft) * end_env;

    // ---- the big one's path ---------------------------------------------------
    let ub = met_dir(-1.0, seed, 0.42, 0.0);
    let big_head = crel + ub * BIG_V * max(BIG_T - ft, 0.0);
    let pB = project_rel(big_head);
    let pt = project_rel(crel);

    // ---- camera shake and the shockwave's refraction ----------------------------
    let near_scale = 1.0 / (1.0 + length(crel) / 60.0);
    let shake_amt = (storm_env * 0.15 * f32(fired) + approach * approach * 1.5 + flash * 7.0 + select(0.0, exp(-dtb * 0.35), hit_b) * 1.6) * k * 0.012 * max(near_scale, 0.35);
    let shake = (vec2<f32>(vnoise(vec2<f32>(time * 37.0, 1.0)), vnoise(vec2<f32>(time * 41.0, 7.0))) - 0.5) * 2.0 * shake_amt;
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    let r0 = length(p0.xz - tgt.xz);
    let rsb = max(dtb, 0.0) * 95.0;                             // the big shockwave's radius
    let shock_mask = select(0.0, exp(-pow((r0 - rsb) / 5.0, 2.0)) * exp(-max(dtb, 0.0) * 0.3), hit_b && !sky0);
    var sdir = uv - pt.xy;
    sdir = sdir / max(length(sdir), 1e-4);
    var haze = vec2<f32>(0.0);
    if (fired && !sky0) {
        // each small impact's air blast: a ripple of heat haze running out along the ground
        for (var i = 0; i < MET_N; i = i + 1) {
            let fi = f32(i);
            let dtm = fire_t - met_t(fi, seed);
            if (dtm < 0.0 || dtm > 1.1) {
                continue;
            }
            let fc = f32(met_class(fi, seed));
            let off = met_off(fi, seed);
            let gi = length(p0.xz - (tgt.xz + off));
            let m = exp(-pow((gi - dtm * (55.0 + 25.0 * fc)) / (1.5 + fc), 2.0)) * exp(-dtm * 3.5) * (0.5 + 0.5 * fc)
                * (1.0 - smoothstep(20.0, 40.0, abs(p0.y - tgt.y)));
            if (m > 0.002) {
                let pi = project_rel(vec3<f32>(tgt.x + off.x, tgt.y, tgt.z + off.y) - cam);
                let dir = uv - pi.xy;
                haze = haze + dir / max(length(dir), 1.0e-4) * m * 0.012 * pi.z;
            }
        }
    }
    let uv2 = clamp(uv + shake + sdir * shock_mask * 0.05 * k * pt.z + haze * k, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene ------------------------------------------------------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let P = cam + rel;
    let ca = (flash * 0.02 + shock_mask * 0.01) * k;
    let ca_dir = (uv2 - vec2<f32>(0.5)) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b));
    // the light goes the colour of a dusk on fire, then brown under the dust
    let dim = clamp(1.0 - (0.35 * charging * charging + 0.3 * storm_env + 0.45 * dust_env) * k, 0.2, 1.0);
    col = col * dim * mix(vec3<f32>(1.0), vec3<f32>(1.15, 0.8, 0.6), saturate(storm_env + dust_env) * k);
    // lit up by the big one as it comes in
    col = col * (1.0 + vec3<f32>(1.4, 0.75, 0.3) * approach * approach * 1.6 * k);
    if (sky) {
        let grad = pow(1.0 - uv2.y, 1.5);
        let dusk = vec3<f32>(0.32, 0.1, 0.05) + vec3<f32>(0.55, 0.22, 0.08) * grad;
        col = mix(col, dusk, saturate(storm_env * 0.65 + charging * 0.3) * k);
        let dusty = vec3<f32>(0.16, 0.07, 0.035) + vec3<f32>(0.25, 0.09, 0.03) * grad * (0.6 + 0.6 * gfbm2(rd.xz / max(rd.y, 0.05) * 1.5 + vec2<f32>(time * 0.05, 0.0)));
        col = mix(col, dusty, dust_env * 0.88 * k);
        // the sky round the big one burns as it comes in
        let tow = max(dot(rd, normalize(big_head)), 0.0);
        col = col + vec3<f32>(1.6, 0.75, 0.25) * pow(tow, 12.0) * approach * 1.6 * k;
    }
    var add = vec3<f32>(0.0);

    // ---- on the ground: the impact zone while it charges, the craters' glow, the shockwaves ----
    if (!sky) {
        let dxg = P.xz - tgt.xz;
        let r = length(dxg);
        let ang = atan2(dxg.y, dxg.x);
        let dy = P.y - tgt.y;
        // on the ground, or down in the crater: nothing up in the clouds
        let on_ground = 1.0 - smoothstep(28.0, 45.0, dy);
        let near_y = on_ground / (1.0 + dy * dy / 200.0);
        // the zone: a dashed ring where the storm will fall, closing in on ground zero
        let zone_env = max(charging, storm_env * 0.35 * (1.0 - f32(hit_b))) * end_env;
        if (zone_env > 0.001) {
            let dash = step(0.5, fract(ang / TAU * 48.0 + time * 0.08));
            var z = exp(-pow((r - MET_SPAN) / 0.8, 2.0)) * dash * 1.2;
            let conv = mix(MET_SPAN, 10.0, 1.0 - pow(1.0 - charging, 2.0));
            z = z + exp(-pow((r - conv) / 0.6, 2.0)) * charging;
            z = z + (exp(-pow((r - 6.0) / 0.3, 2.0)) + exp(-pow((r - 2.5) / 0.25, 2.0))) * (0.6 + 0.4 * sin(time * 8.0));
            let cross_ = (1.0 - smoothstep(0.15, 0.35, min(abs(dxg.x), abs(dxg.y)))) * (1.0 - smoothstep(9.0, 10.0, r));
            z = z + cross_ * 0.7;
            add = add + vec3<f32>(1.6, 0.25, 0.1) * z * zone_env * near_y * 2.0 * k;
        }
        // the big one: its crater glowing, its shockwave racing out with a wall of dust behind it
        if (hit_b) {
            let edge = exp(-pow((r - rsb) / 4.0, 2.0)) * exp(-dtb * 0.28) * near_y;
            add = add + vec3<f32>(2.2, 1.3, 0.6) * edge * 5.0 * k;
            let behind = smoothstep(rsb + 2.0, rsb - 40.0, r) * exp(-dtb * 0.12) * on_ground;
            col = mix(col, vec3<f32>(0.2, 0.12, 0.07) * (0.6 + 0.8 * gfbm2(dxg * 0.03 + vec2<f32>(time * 0.3, 0.0))), behind * 0.55 * k);
            let n = gfbm2(dxg * 0.12 + vec2<f32>(time * 0.1, -time * 0.07));
            let heat = (1.0 - r / 75.0) * 0.9 + (n - 0.5) * 0.8 + saturate((tgt.y - P.y) / 30.0) * 0.6 - dtb * 0.02;
            let mask = (1.0 - smoothstep(55.0, 80.0, r)) * smoothstep(0.0, 1.5, dtb) * end_env * on_ground;
            add = add + lava_ramp(heat) * mask * 3.0 * k;
        }
    }

    // ---- the storm -------------------------------------------------------------
    // Each meteor comes in from the top of the atmosphere, about 1,900 blocks up its path, faint until the air gets
    // thick enough to set it burning, slowing as it comes down. Behind it a streak of fire cools to a trail of smoke
    // that stays where it passed, billowing out and thinning.
    let v2 = rd.xz;
    let vv = dot(v2, v2);
    for (var i = 0; i < MET_N; i = i + 1) {
        let fi = f32(i);
        let dtm = fire_t - met_t(fi, seed);                     // 0 at its impact
        if (dtm < -MET_ENTRY || dtm > 9.0) {
            continue;
        }
        let cls = met_class(fi, seed);
        let fc = f32(cls);
        let off = met_off(fi, seed);
        let I = vec3<f32>(tgt.x + off.x, tgt.y, tgt.z + off.y) - cam;
        let u = met_dir(fi, seed, 0.62, 1.0);
        let rr = 0.6 + 0.5 * fc + 0.3 * fc * fc;               // the rock: 0.6, 1.4, 2.8 blocks
        let tau = -dtm;                                         // seconds until it lands
        let Lh = met_path(max(tau, 0.0));
        let L0 = met_path(MET_ENTRY);
        let headp = I + u * Lh;
        let q = ray_seg(rd, headp, I + u * L0);
        let l = mix(Lh, L0, q.z);
        let age = max(met_when(l) - tau, 0.0);                  // seconds since it passed there
        let burn = smoothstep(1700.0, 1050.0, l);               // only burning once the air is thick enough
        let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.5, scene_len + 0.5, q.y), !sky);
        let flick = 0.7 + 0.6 * fvnoise(vec2<f32>(time * 13.0, fi * 7.0));
        let sw = rr * 1.4 + age * (1.6 + 1.2 * fc);
        let swp = max(sw, q.y * 0.0015);
        if (vis > 0.001 && q.x < swp * 3.0) {
            // the smoke it leaves, widening and thinning out (its billows only worked out where there is smoke to see)
            let s_env = exp(-pow(q.x / swp, 2.0)) * (sw / swp) * burn * smoothstep(0.08, 0.6, age)
                * exp(-age / (3.5 + 2.0 * fc)) * (0.55 + 0.2 * fc);
            if (s_env > 0.006) {
                let sn = gfbm2(vec2<f32>(l * 0.06, age * 0.7 + fi * 3.1));
                col = mix(col, vec3<f32>(0.32, 0.29, 0.27) * dim * (0.55 + 0.7 * sn), saturate(s_env * (0.3 + 0.6 * sn)) * vis);
            }
            // the fire: white-hot at the head, then orange, then a glowing streak cooling behind it
            let fw0 = rr * (1.0 + age * 5.0);
            let fw = max(fw0, q.y * 0.0012);
            let fire = exp(-pow(q.x / fw, 2.0)) * (fw0 / fw) * exp(-age * 3.2);
            let fcol = mix(vec3<f32>(3.4, 3.0, 2.2), vec3<f32>(2.6, 0.75, 0.12), smoothstep(0.0, 0.3, age));
            add = add + fcol * fire * burn * flick * (0.8 + 0.4 * fc) * vis * k;
            // bits breaking off and burning out behind it
            let sp = fh21(vec2<f32>(floor(l * 0.5), floor(age * 14.0) + fi * 17.0));
            let side = (fract(sp * 53.0) - 0.5) * (rr * 2.0 + age * 6.0);
            let spark = step(0.9, sp) * exp(-pow((q.x - abs(side)) / max(rr * 0.5, q.y * 0.001), 2.0)) * exp(-age * 2.5) * smoothstep(0.02, 0.15, age);
            add = add + vec3<f32>(3.0, 1.4, 0.35) * spark * burn * vis * k;
        }
        if (tau > -0.05) {
            // the head: a glow seen from far off, and close up the rock itself, its leading face molten
            let th = dot(headp, rd);
            if (th > 0.0) {
                let dh = length(headp - rd * th);
                let visg = select(1.0, 1.0 - smoothstep(scene_len - 1.0, scene_len + 1.0, th), !sky);
                let glow = 1.0 / (1.0 + pow(dh / (rr * 2.5 + th * 0.002), 2.0));
                add = add + vec3<f32>(2.2, 1.3, 0.55) * glow * (0.08 + 0.9 * burn) * flick * 0.55 * visg * k;
                let hq = rr * rr - dh * dh;
                if (hq > 0.0) {
                    let t0 = th - sqrt(hq);
                    if (t0 > 0.0 && t0 < scene_len) {
                        let nrm = normalize(rd * t0 - headp);
                        let n3 = gfbm3(nrm * 2.5 + vec3<f32>(time * 0.6, fi, time * 0.4), 2);
                        // lumpy: let the noise eat into its edge
                        if (dot(nrm, -rd) > 0.45 * n3 - 0.05) {
                            let front = saturate(dot(nrm, -u) * 0.5 + 0.5);
                            let rock = vec3<f32>(0.08, 0.07, 0.06) * (0.5 + 0.9 * n3) * dim;
                            col = rock + lava_ramp(0.3 + 0.7 * front) * pow(front, 3.0) * 2.4 * burn;
                        }
                    }
                }
            }
        }
        if (dtm >= 0.0) {
            // it lands: a fireball, a plume of dust and rock, glowing chunks thrown out, a ring along the ground
            let fr = 3.0 + 2.5 * fc + 0.5 * fc * fc;            // 3, 6, 10: about the crater strike.rs digs
            let Rf = fr * (1.0 - exp(-dtm * 5.0)) + 0.5;
            let C = I + vec3<f32>(0.0, Rf * 0.4, 0.0);
            let tcp = dot(C, rd);
            if (tcp > 0.0) {
                let dc = length(C - rd * tcp);
                let visf = select(1.0, smoothstep(tcp - Rf * 1.2, tcp - Rf * 0.2, scene_len), !sky);
                let fire = exp(-pow(dc / Rf, 2.0)) * exp(-dtm * 1.8);
                add = add + lava_ramp(0.45 + fire * 0.6) * fire * (2.8 + fc) * visf * k;
                add = add + vec3<f32>(1.5, 0.7, 0.3) / (1.0 + pow(dc / (Rf * 3.0), 2.0)) * exp(-dtm * 4.0) * 0.5 * (1.0 + fc) * visf * k;
            }
            let ah = axis_hit(I.xz, v2, vv, cam.y, rd.y);
            let Hp = fr * 3.0 * (1.0 - exp(-dtm * 1.1));
            let Rp = fr * 0.6 + dtm * 0.9;
            if (ah.x > 0.0 && ah.y < Rp * 3.0 && ah.z - tgt.y > -2.0 && ah.z - tgt.y < Hp + 2.0) {
                let yrel = ah.z - tgt.y;
                let pn = gfbm2(vec2<f32>(yrel * 0.22 - dtm * 1.2, fi + ah.y * 0.3));
                let dens = exp(-pow(ah.y / Rp, 2.0)) * smoothstep(Hp, Hp * 0.5, yrel) * smoothstep(-1.0, 0.5, yrel)
                    * exp(-dtm / 5.0) * smoothstep(0.0, 0.3, dtm) * (0.4 + 0.7 * pn);
                let visp = select(1.0, 1.0 - smoothstep(scene_len - 0.5, scene_len + 0.5, ah.x), !sky);
                col = mix(col, vec3<f32>(0.26, 0.2, 0.15) * dim * (0.6 + 0.6 * pn), saturate(dens * 0.85) * visp);
            }
            if (cls > 0 && dtm < 2.6) {
                for (var j = 0; j < 5; j = j + 1) {
                    let fj = f32(j);
                    let az = fh21(vec2<f32>(fi * 7.0 + fj, seed)) * TAU;
                    let hj = fh21(vec2<f32>(fj, fi * 3.0 + seed));
                    let vh = (8.0 + 10.0 * hj) * (0.8 + 0.6 * fc);
                    let vy = (11.0 + 9.0 * hj) * (0.9 + 0.4 * fc);
                    let t1 = max(dtm - 0.12, 0.0);
                    let pa = I + vec3<f32>(cos(az) * vh * dtm, vy * dtm - 12.5 * dtm * dtm, sin(az) * vh * dtm);
                    let pb = I + vec3<f32>(cos(az) * vh * t1, vy * t1 - 12.5 * t1 * t1, sin(az) * vh * t1);
                    if (pa.y < I.y - 2.0) {
                        continue;
                    }
                    let qj = ray_seg(rd, pa, pb);
                    let visj = select(1.0, 1.0 - smoothstep(scene_len - 0.4, scene_len + 0.4, qj.y), !sky);
                    let w = max(0.35 * (1.0 + qj.z), qj.y * 0.0012);
                    add = add + vec3<f32>(2.6, 1.0, 0.25) * exp(-pow(qj.x / w, 2.0)) * (0.35 / w) * exp(-dtm * 0.6) * visj * k;
                }
            }
            let dxi = P.xz - (tgt.xz + off);
            let gr = length(dxi);
            let Rd = fr * 4.5 * (1.0 - exp(-dtm * 2.0));
            if (!sky && dtm < 1.0) {
                // a brief flash where the air blast leads
                let gw = 1.0 - smoothstep(20.0, 40.0, abs(P.y - tgt.y));
                let edge = exp(-pow((gr - dtm * (55.0 + 25.0 * fc)) / (0.4 + 0.3 * fc), 2.0)) * exp(-dtm * 9.0);
                add = add + vec3<f32>(1.5, 1.1, 0.7) * edge * (0.4 + 0.4 * fc) * gw * k;
            }
            if (!sky && gr < max(Rd + fr * 2.0, fr * 3.0)) {
                let gw = 1.0 - smoothstep(20.0, 40.0, abs(P.y - tgt.y));
                // the blast throws up a skirt of dust that rolls out along the ground, thickest at its front, and settles
                let inside = smoothstep(Rd + 1.0, Rd - fr * 0.8, gr);
                let front = exp(-pow((gr - Rd * 0.92) / (0.6 + fr * 0.35), 2.0));
                let dn = gfbm2(dxi * 0.35 + vec2<f32>(dtm * 0.8, fi * 2.3));
                let grain = fh21(floor(P.xz * 4.0) + vec2<f32>(fi, 3.0));
                let skirt = (inside * 0.35 + front * 0.9) * (0.45 + 0.8 * dn) * exp(-dtm / (2.5 + fc)) * smoothstep(0.0, 0.15, dtm);
                let lit = lava_ramp(0.5) * 0.3 * exp(-dtm * 1.5) * (1.0 - smoothstep(0.0, fr * 2.0, gr));
                let dust_col = mix(vec3<f32>(0.24, 0.18, 0.13), vec3<f32>(0.42, 0.3, 0.2), dn) * dim * (0.8 + 0.4 * grain) + lit;
                col = mix(col, dust_col, saturate(skirt * (0.6 + 0.2 * fc)) * gw * k);
                // the crater glowing as it cools, and embers scattered round it flickering out
                let glow = (1.0 - smoothstep(fr * 0.3, fr * 1.1, gr)) * exp(-dtm * 0.3);
                let n = gfbm2(dxi * 0.9 + vec2<f32>(time * 0.3, fi));
                add = add + lava_ramp(0.35 + 0.5 * glow + 0.3 * n) * glow * gw * 1.8 * k;
                let eh = fh21(floor(P.xz * 2.0) + vec2<f32>(fi * 13.0, 7.0));
                let spark = step(0.93, eh) * (1.0 - smoothstep(fr, fr * 2.8, gr)) * exp(-dtm * (0.4 + 2.0 * fract(eh * 37.0)))
                    * (0.55 + 0.45 * sin(time * 18.0 + eh * 60.0));
                add = add + vec3<f32>(2.4, 0.9, 0.2) * spark * gw * k;
            }
        }
    }

    // ---- the big one coming in: a rock the size of a hill, burning, its trail left across the sky ----
    if (fired && ft > 4.0 && dtb < 12.0) {
        let heat = smoothstep(4.0, BIG_T - 2.0, ft) * (1.0 - smoothstep(0.0, 0.1, dtb));
        let Lb = BIG_V * max(BIG_T - ft, 0.0);
        let Lb0 = BIG_V * (BIG_T - 4.0);
        let q = ray_seg(rd, big_head, crel + ub * Lb0);
        let l = mix(Lb, Lb0, q.z);
        let age = (l - Lb) / BIG_V + max(dtb, 0.0);            // seconds since it passed there
        let burn = smoothstep(Lb0, Lb0 * 0.7, l);
        let vis = select(1.0, 1.0 - smoothstep(scene_len - 2.0, scene_len + 2.0, q.y), !sky);
        // smoke, billowing out into a wall across the sky
        let sw = BIG_R * 1.3 + age * 7.0;
        let swp = max(sw, q.y * 0.0015);
        let sn = gfbm2(vec2<f32>(l * 0.02 - age * 0.3, q.x / swp * 2.0 + seed));
        let sa = exp(-pow(q.x / swp, 2.0)) * (sw / swp) * burn * smoothstep(0.1, 0.8, age) * exp(-age / 14.0) * (0.35 + 0.65 * sn);
        col = mix(col, vec3<f32>(0.3, 0.26, 0.23) * dim * (0.5 + 0.8 * sn), saturate(sa * 0.9) * vis);
        // fire round the rock and streaming back off it
        let fw0 = BIG_R * (1.0 + age * 2.5);
        let fw = max(fw0, q.y * 0.0015);
        let core = exp(-pow(q.x / (fw * 0.7), 2.0)) * (fw0 / fw) * exp(-age * 1.4);
        let hot = mix(vec3<f32>(4.0, 3.4, 2.2), vec3<f32>(3.0, 0.9, 0.15), smoothstep(0.0, 0.8, age));
        add = add + hot * core * vis * (0.3 + 0.9 * heat) * (1.0 - f32(hit_b)) * k;
        if (!hit_b) {
            // the rock itself, its leading face white-hot
            let oc = -big_head;
            let bq = dot(oc, rd);
            let cq = dot(oc, oc) - BIG_R * BIG_R;
            let hq = bq * bq - cq;
            if (hq > 0.0) {
                let t0 = -bq - sqrt(hq);
                if (t0 > 0.0 && t0 < scene_len) {
                    let nrm = normalize(rd * t0 - big_head);
                    let front = saturate(dot(nrm, -ub));
                    let cracks = smoothstep(0.55, 0.75, gfbm3(nrm * 5.0 + vec3<f32>(seed), 3));
                    let rock = vec3<f32>(0.06, 0.05, 0.045) * (0.5 + gfbm3(nrm * 9.0, 2));
                    col = rock + lava_ramp(0.4 + 0.6 * front + 0.3 * cracks) * (pow(front, 2.0) * 3.0 + cracks * 1.2) * (0.3 + heat);
                }
            }
            // the glare round it, seen from far off as a star getting brighter
            let th = dot(big_head, rd);
            if (th > 0.0) {
                let dh = length(big_head - rd * th);
                let glare = 1.0 / (1.0 + pow(dh / (BIG_R * 2.5 + th * 0.004), 2.0));
                add = add + vec3<f32>(2.2, 1.4, 0.7) * glare * (0.35 + 1.2 * heat) * select(1.0, 0.3, !sky && scene_len < th) * k;
            }
        }
    }

    // ---- the big one lands: a fireball the size of a mountain, bursting out unevenly, rising into smoke ----
    if (hit_b && dtb < 24.0) {
        let Rv = 115.0 * (1.0 - exp(-dtb * 0.55));
        let top_s = 30.0 + dtb * 16.0;
        let capr = 25.0 + dtb * 3.0;
        let Rb = max(Rv * 1.35, top_s + capr) + 4.0;
        let oc = cam - tgt;
        let bq = dot(oc, rd);
        let cq = dot(oc, oc) - Rb * Rb;
        let hq = bq * bq - cq;
        if (hq > 0.0) {
            let sq = sqrt(hq);
            let ta = max(-bq - sq, 0.0);
            let tb = min(-bq + sq, scene_len);
            if (tb > ta) {
                let steps = 16;
                let dt = (tb - ta) / f32(steps);
                var trans = 1.0;
                var acc = vec3<f32>(0.0);
                let fade = 1.0 - smoothstep(16.0, 24.0, dtb);
                let jit = ign(in.position.xy);
                let grow = smoothstep(1.0, 4.0, dtb);
                for (var i = 0; i < steps; i = i + 1) {
                    let ts = ta + (f32(i) + jit) * dt;
                    let lp = oc + rd * ts;
                    let rl = length(lp);
                    let rr = length(lp.xz);
                    let stem = (1.0 - rr / (22.0 + max(lp.y, 0.0) * 0.12)) * 1.3 * (1.0 - smoothstep(top_s - 8.0, top_s, lp.y));
                    let capq = length(vec2<f32>(rr / max(capr * 1.6, 1.0), (lp.y - top_s) / max(capr * 0.6, 1.0)));
                    var coarse = max(stem, (1.0 - capq) * 1.6) * grow;
                    if (rl < Rv * 1.6 + 2.0) {
                        // its edge pushed out and pulled in by direction, so it bursts out in lobes, furthest downrange
                        let dirn = lp / max(rl, 1.0e-3);
                        let lobe = gnoise3(dirn * 2.4 + vec3<f32>(seed * 0.37, 3.1, seed * 0.11));
                        let Re = Rv * (0.6 + 0.75 * lobe + 0.25 * saturate(dot(dirn, -ub)));
                        coarse = max(coarse, (1.0 - rl / max(Re, 1.0)) * 1.5 - 0.2);
                    }
                    if (coarse < -1.25 || lp.y < -8.0) {
                        continue;                                    // too far outside for the billows to reach
                    }
                    let nz = gfbm3(lp * 0.03 + vec3<f32>(0.0, -dtb * 0.45, seed), select(2, 3, ts < 200.0));
                    let body = coarse + (nz - 0.5) * 2.6;
                    let dens = saturate(body * 1.2) * smoothstep(-8.0, 4.0, lp.y) * fade;
                    if (dens < 0.002) {
                        continue;
                    }
                    let temp = saturate(body * 0.6 + 0.42 - dtb * 0.045 - max(lp.y, 0.0) / 260.0);
                    let emit = lava_ramp(temp) * 3.0 * (0.3 + 0.7 * exp(-dtb * 0.12));
                    // smoke, lit from underneath by the fire in it
                    let smoke = vec3<f32>(0.11, 0.085, 0.07) * (0.45 + nz) + lava_ramp(temp * 0.8) * 0.12;
                    let a = (1.0 - exp(-dens * dt * 0.07)) * 0.88;
                    acc = acc + trans * a * (emit + smoke);
                    trans = trans * (1.0 - a);
                    if (trans < 0.05) {
                        break;
                    }
                }
                col = col * trans + acc * k;
            }
        }
        // ejecta flung out every way at once: some skimming low and far, some thrown almost straight up, most along a
        // few rays and downrange of where it came in, glowing as they arc and fall back
        let down = normalize(vec2<f32>(-ub.x, -ub.z) + vec2<f32>(1.0e-4));
        for (var j = 0; j < 64; j = j + 1) {
            let fj = f32(j);
            let h1 = fh21(vec2<f32>(fj, seed + 51.0));
            let h2 = fh21(vec2<f32>(fj, seed + 57.0));
            let h3 = fh21(vec2<f32>(fj, seed + 61.0));
            let h4 = fh21(vec2<f32>(fj, seed + 67.0));
            let tau = dtb - 0.1 - 1.4 * h3 * h3;
            if (tau <= 0.0 || tau > 16.0) {
                continue;
            }
            // which ray it rides (or none), how steep, how fast
            let ray_a = floor(h1 * 7.0) * TAU / 7.0 + seed * 0.3;
            let along_ray = h4 < 0.6;
            let az0 = select(h1 * TAU, ray_a + (h2 - 0.5) * 0.18, along_ray);
            let dvec = normalize(mix(vec2<f32>(cos(az0), sin(az0)), down, 0.35 * h2) + vec2<f32>(1.0e-4));
            let elev = mix(0.15, 1.35, pow(h3, 0.7));
            let speed = (55.0 + 95.0 * h4 * h4) * (0.7 + 0.6 * h2);
            let vh = cos(elev) * speed;
            let vy = sin(elev) * speed;
            let p0 = crel + vec3<f32>(dvec.x, 0.0, dvec.y) * (18.0 + 18.0 * h2);
            let ph = p0 + vec3<f32>(dvec.x * vh * tau, vy * tau - 15.0 * tau * tau, dvec.y * vh * tau);
            let t1 = max(tau - 0.22, 0.0);
            let pt1 = p0 + vec3<f32>(dvec.x * vh * t1, vy * t1 - 15.0 * t1 * t1, dvec.y * vh * t1);
            if (ph.y + cam.y < tgt.y - 6.0) {
                continue;
            }
            let sz = 0.8 + 2.2 * h1 * h4;
            let q = ray_seg(rd, ph, pt1);
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.5, scene_len + 0.5, q.y), !sky);
            let w = max(sz * (1.0 + q.z), q.y * 0.0012);
            let core = exp(-pow(q.x / w, 2.0)) * (sz / w);
            let cool = exp(-tau * 0.2);
            add = add + mix(vec3<f32>(1.6, 0.25, 0.05), vec3<f32>(3.0, 1.6, 0.6), cool) * core * (1.0 - q.z * 0.6) * vis * (0.5 + cool) * k;
        }
    }

    // ---- the lens: the big one's bloom as it comes in, the whiteout when it lands ----
    if (pB.z > 0.0 && approach > 0.001) {
        let dd = (uv - pB.xy) * vec2<f32>(aspect, 1.0);
        add = add + vec3<f32>(1.6, 0.9, 0.4) * approach * approach / (1.0 + dot(dd, dd) * 25.0) * 1.2 * k;
        let streak = exp(-abs(dd.y) * 220.0) * exp(-abs(dd.x) * 2.0);
        add = add + vec3<f32>(2.0, 1.0, 0.4) * streak * approach * k;
    }
    add = add + vec3<f32>(6.0, 5.4, 4.6) * flash * flash * k;
    add = add + vec3<f32>(1.5, 0.8, 0.4) * select(0.0, exp(-dtb * 0.6), hit_b) * 0.4 * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.35 * max(storm_env, dust_env)) * k)
        + vec3<f32>(0.4, 0.1, 0.02) * smoothstep(0.35, 1.0, vg) * max(storm_env, dust_env) * 0.08 * k;
    outc = aces(outc * 0.9);
    let srgb = linear_to_srgb(outc);
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    return vec4<f32>(srgb, 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    if (th_is(2.0) > 0.5) {
        return singularity(in);
    }
    if (th_is(3.0) > 0.5) {
        return meteor_storm(in);
    }
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let tt = phase_time();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let anc = anchor_xz();
    let crel = tgt - cam;
    let dist_t = length(crel);
    let T0 = th_is(0.0);
    let T1 = th_is(1.0);
    let seed = seed_v();

    // ---- timeline -------------------------------------------------------------
    let charging = select(0.0, saturate(tt / T_FIRE), tt < T_FIRE);
    let fire_t = tt - T_FIRE;
    let fired = fire_t > 0.0;
    // godly's light starts coming down a little before it lands; plasma's beam is there in an instant
    let fire_b = fire_t + 0.6 * T1;
    let beam_env = smoothstep(0.0, 0.1, fire_b) * (1.0 - smoothstep(9.0, 11.0, fire_t));
    let crater_env = smoothstep(0.0, 0.8, fire_t) * (1.0 - smoothstep(10.0, 20.0, fire_t));
    let flash = select(0.0, exp(-fire_t * 9.0), fired);
    let reticle_env = max(charging, select(0.0, exp(-fire_t * 2.5), fired));
    let after = 1.0 - smoothstep(13.0, 21.0, fire_t) * f32(fired);
    let k = intensity_v();
    let pal = hash21(vec2<f32>(seed, 3.7));
    let sr1 = hash21(vec2<f32>(seed, 11.3));
    let sr2 = hash21(vec2<f32>(seed, 23.9));
    let surge = pow(vnoise(vec2<f32>(time * 1.9, seed * 13.0)), 2.5) * 2.2 * T0;
    let stutter = 1.0 - 0.4 * step(0.8, vnoise(vec2<f32>(time * 9.0, seed * 5.0))) * T0;
    let wobble = (vec2<f32>(vnoise(vec2<f32>(time * 2.3, seed)), vnoise(vec2<f32>(time * 2.1, seed * 2.0))) - 0.5) * 1.6 * surge;

    // ---- palette ----------------------------------------------------------------
    let tint_pal = mix(vec3<f32>(0.25, 1.1, 3.8), vec3<f32>(3.4, 0.5, 2.6), step(0.34, pal));
    let tint_p = mix(tint_pal, vec3<f32>(0.5, 3.2, 0.9), step(0.67, pal));
    let tint_beam = pick2(tint_p, vec3<f32>(3.4, 2.6, 1.0));
    let tint_alt = pick2(tint_p.zxy, vec3<f32>(3.0, 2.8, 1.8));
    let ring_col = pick2(vec3<f32>(1.0, 0.75, 0.45), vec3<f32>(1.6, 1.3, 0.7));
    let tint_l = mix(mix(vec3<f32>(0.4, 0.45, 1.8), vec3<f32>(1.8, 0.4, 1.2), step(0.34, pal)), vec3<f32>(0.3, 1.8, 0.5), step(0.67, pal));
    let gold = vec3<f32>(1.6, 1.2, 0.55);
    let white = vec3<f32>(1.6, 1.55, 1.3);

    // ---- target on screen -----------------------------------------------------
    let pt = project_rel(crel);
    let uvT = pt.xy;

    // ---- camera shake and shockwave refraction (resample position) ------------
    let near_scale = 1.0 / (1.0 + dist_t / 28.0);
    let shake_amt = (beam_env * 0.8 * T0 + flash * mix(5.0, 2.5, T1) + (1.0 - smoothstep(0.0, 3.0, fire_t)) * f32(fired) * 1.6) * k * 0.012 * near_scale;
    let shake = (vec2<f32>(vnoise(vec2<f32>(time * 37.0, 1.0)), vnoise(vec2<f32>(time * 41.0, 7.0))) - 0.5) * 2.0 * shake_amt;

    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    let r0 = length(p0.xz - tgt.xz);
    let rs = fire_t * 62.0;
    let shock_fade = select(0.0, exp(-fire_t * 0.55), fired);
    let shock_mask = select(0.0, exp(-pow((r0 - rs) / 3.5, 2.0)), fired && !sky0) * shock_fade;
    var shock_dir = uv - uvT;
    shock_dir = shock_dir / max(length(shock_dir), 1e-4);
    var uv2 = uv + shake + shock_dir * shock_mask * 0.08 * k * pt.z;
    // heat haze over the beam and the crater (plasma)
    let haze = (beam_env + crater_env * 0.6) * k * exp(-length((uv - uvT) * vec2<f32>(aspect, 1.0)) * 4.0) * pt.z * T0;
    uv2 = uv2 + vec2<f32>(sin(uv.y * 90.0 + time * 14.0), cos(uv.x * 70.0 - time * 11.0)) * 0.0025 * haze;
    uv2 = clamp(uv2, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- scene colour with chromatic aberration -------------------------------
    let ca = (flash * 0.012 + shock_mask * 0.008) * k;
    let ca_dir = (uv2 - vec2<f32>(0.5)) * ca;
    let sr = textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r;
    let sg = textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g;
    let sb = textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b;
    var col = srgb_to_linear(vec3<f32>(sr, sg, sb));

    // ---- world position at the shifted pixel ----------------------------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let P = cam + rel;
    let v2 = rd.xz;
    let vv = dot(v2, v2);

    // ---- grading: the world dims so the light reads ------------------------------
    let dim = 1.0 - (0.45 * charging * charging + 0.4 * beam_env + 0.2 * crater_env) * k * mix(1.0, 0.75, T1);
    col = col * clamp(dim, 0.2, 1.0);
    if (sky) {
        let st = beam_env * k;
        let grad = pow(1.0 - uv2.y, 2.0);
        if (T0 > 0.5) {
            col = mix(col, vec3<f32>(0.04, 0.0, 0.1) + vec3<f32>(0.25, 0.0, 0.35) * grad, st * 0.7);
            col = col + vec3<f32>(0.5, 0.02, 0.02) * charging * charging * k * 0.35 * (1.0 - uv2.y);
        } else {
            // the clouds part: an overcast rolls in over the whole sky and tears open above the target
            let cover_env = smoothstep(0.0, 2.5, tt) * after;
            if (rd.y > 0.015 && cover_env > 0.001) {
                let H = tgt.y + 150.0;
                let th = (H - cam.y) / rd.y;
                let hit = cam + rd * max(th, 0.0);
                let q = hit.xz - anc;
                let rq = length(q);
                let aq = atan2(q.y, q.x);
                let Ra = 58.0 * smoothstep(0.6, 4.2, tt);
                // the cloud deck swirls round the opening, slower further out
                let swirl = aq + 9.0 / (1.0 + rq * 0.04) * (0.2 + 0.05 * time);
                let qs = vec2<f32>(cos(swirl), sin(swirl)) * rq;
                let cl = fbm(qs * 0.012 + vec2<f32>(time * 0.03, seed));
                let cl2 = fbm(qs * 0.035 - vec2<f32>(time * 0.05, 0.0));
                let dens = smoothstep(0.32, 0.7, cl * 0.8 + cl2 * 0.35) * smoothstep(Ra * 0.85, Ra * 1.25, rq);
                let horizon = smoothstep(0.015, 0.14, rd.y);
                let lit = exp(-max(rq - Ra, 0.0) / 70.0);
                let deck = mix(vec3<f32>(0.10, 0.09, 0.09), vec3<f32>(1.25, 0.85, 0.42), lit) * (0.55 + 0.6 * cl2);
                let cover = (0.55 + 0.45 * dens) * cover_env * horizon;
                col = mix(col, deck, cover);
                // the opening itself: a well of light, with rays cut through the torn edge
                let open_ = (1.0 - smoothstep(Ra * 0.55, Ra * 1.05, rq)) * cover_env * horizon;
                let rays = pow(fbm(vec2<f32>(aq * 7.0, time * 0.25)), 2.0) * exp(-max(rq - Ra * 0.8, 0.0) / 45.0) * (1.0 - dens);
                col = col + (vec3<f32>(2.6, 2.2, 1.5) * open_ + vec3<f32>(1.4, 1.0, 0.45) * rays * cover_env * horizon) * k;
            } else {
                col = mix(col, vec3<f32>(0.16, 0.08, 0.03) + vec3<f32>(0.6, 0.32, 0.1) * grad, 0.6 * cover_env);
            }
        }
    }

    var add = vec3<f32>(0.0);

    // ---- ground effects -------------------------------------------------------
    if (!sky) {
        let dxg = P.xz - tgt.xz;
        let r = length(dxg);
        let ang = atan2(dxg.y, dxg.x);
        let dy = P.y - tgt.y;
        let near_y = 1.0 / (1.0 + dy * dy / 40.0);
        let rc_lo = pick2(vec3<f32>(1.0, 0.05, 0.03), vec3<f32>(1.0, 0.75, 0.2));
        let rc_hi = pick2(vec3<f32>(1.0, 0.9, 0.8), vec3<f32>(1.0, 1.0, 0.9));
        let rc = mix(rc_lo, rc_hi, charging * charging);

        // plasma: the targeting reticle
        if (T0 > 0.5 && reticle_env > 0.001) {
            var ret = 0.0;
            let conv = mix(30.0, 5.0, 1.0 - pow(1.0 - charging, 3.0));
            ret = ret + exp(-pow((r - conv) / 0.35, 2.0)) * 1.3;
            let spin1 = step(0.5, fract(ang / TAU * 24.0 + time * 0.35));
            ret = ret + exp(-pow((r - 9.0) / 0.22, 2.0)) * spin1;
            let spin2 = step(0.35, fract(ang / TAU * 12.0 - time * 0.6));
            ret = ret + exp(-pow((r - 14.0) / 0.2, 2.0)) * spin2 * 0.9;
            ret = ret + exp(-pow((r - 3.0) / 0.2, 2.0));
            let spokes = (1.0 - smoothstep(0.0, 0.06, abs(fract(ang / TAU * 8.0 + time * 0.12) - 0.5) * r * 0.05));
            ret = ret + spokes * (1.0 - smoothstep(conv - 2.0, conv, r)) * smoothstep(1.0, 2.0, r) * 0.45;
            let scan = exp(-pow((r - fract(time * 0.7) * 30.0) / 0.5, 2.0)) * 0.7;
            ret = ret + scan * select(0.0, 1.0, charging > 0.0);
            add = add + rc * ret * reticle_env * near_y * 2.2 * k;
        }
        // godly: the sigil, laid out exactly where strike.py etches it in gold and stands the pillars
        if (T1 > 0.5) {
            let sg_env = max(reticle_env, crater_env) * after;
            if (sg_env > 0.001) {
                let qa = P.xz - anc;
                let ra = length(qa);
                let aa = atan2(qa.y, qa.x);
                let draw = smoothstep(0.0, 3.6, tt);                       // the lines burn in while it charges
                let sweep = step(fract((aa - PILLAR_A0) / TAU + 1.0), draw);
                var sig = (exp(-pow((ra - SIGIL_R1) / 0.45, 2.0)) + exp(-pow((ra - PILLAR_R) / 0.45, 2.0))) * sweep;
                // the hexagram: triangles through alternate pillars
                let hexa = tri_line(ra, aa - PILLAR_A0 - 1.0471976, PILLAR_R, 0.45) + tri_line(ra, aa - PILLAR_A0, PILLAR_R, 0.45);
                sig = sig + hexa * smoothstep(1.2, 3.8, tt);
                // a ring of runes between the circles, turning slowly
                let rune_a = aa - time * 0.05;
                let rf = fract(rune_a / TAU * 48.0);
                let rune = step(0.4, hash21(vec2<f32>(floor(rune_a / TAU * 48.0), 3.0))) * step(0.2, rf) * step(rf, 0.8);
                sig = sig + rune * step(34.0, ra) * (1.0 - step(37.0, ra)) * 0.8 * sweep;
                let pulse = 0.75 + 0.25 * sin(time * 2.0 - ra * 0.15);
                add = add + rc * sig * sg_env * near_y * 2.6 * pulse * k;
            }
        }

        // the crater: a glowing bowl round the axis, hotter the deeper the surface
        if (fired) {
            let Rc = 1.2 + 7.5 * (1.0 - exp(-fire_t * 0.45));
            let reach = Rc * 1.8;
            if (r < reach * 1.4) {
                let deep = saturate((tgt.y - P.y) / 14.0);
                let n = fbm(dxg * 0.85 + vec2<f32>(time * 0.12, -time * 0.09) + vec2<f32>(P.y * 0.6));
                var heat = (1.0 - r / reach) * 0.9 + (n - 0.5) * 0.9 + deep * 0.7;
                let crust = smoothstep(0.35, 0.65, fbm(dxg * 1.7 + vec2<f32>(3.7, P.y * 0.8)));
                heat = heat - crust * 0.25;
                let mask = (1.0 - smoothstep(reach * 0.7, reach * 1.4, r)) * exp(-max(dy, 0.0) / 4.0);
                add = add + (lava_ramp(heat) * T0 + gold_ramp(heat) * T1) * mask * crater_env * 4.5 * k;
                let bore = (1.0 - smoothstep(Rc * 0.15, Rc * 0.65, r)) * smoothstep(-2.0, 0.0, dy + 1.5) * (1.0 - smoothstep(0.0, 8.0, dy));
                col = col * (1.0 - bore * crater_env * 0.92);
                add = add + pick2(vec3<f32>(1.0, 0.8, 0.5), vec3<f32>(1.0, 0.95, 0.7)) * bore * bore * crater_env * 2.2 * k;
            }
            // godly: golden cracks run out across the ground
            if (T1 > 0.5) {
                let reach_c = 3.0 + fire_t * 6.5;
                if (r < reach_c) {
                    let wob = fbm(vec2<f32>(ang * 3.0 + r * 0.12, r * 0.18 + seed));
                    let cang = fract(ang / TAU * 11.0 + (wob - 0.5) * 1.3);
                    let cdist = 0.5 - abs(cang - 0.5);
                    let thr = 0.16 * 11.0 / (TAU * max(r, 1.5));
                    let crack = (1.0 - smoothstep(thr * 0.4, thr, cdist)) * (1.0 - smoothstep(reach_c * 0.55, reach_c, r)) * smoothstep(1.5, 4.0, r);
                    add = add + vec3<f32>(1.3, 1.0, 0.45) * crack * crater_env * near_y * 3.0 * k;
                }
            }
            // secondary shocks as the beam surges
            for (var q = 0; q < 4; q = q + 1) {
                let fq = f32(q);
                let tq0 = 1.3 + fq * 2.2 + 1.5 * hash21(vec2<f32>(seed, fq + 41.0));
                let dtq = fire_t - tq0;
                let rq = max(dtq, 0.0) * (24.0 + 20.0 * hash21(vec2<f32>(seed, fq + 7.0)));
                let ringq = exp(-pow((r - rq) / 1.2, 2.0)) * exp(-max(dtq, 0.0) * 0.8) * step(0.0, dtq);
                add = add + ring_col * 0.9 * ringq * near_y * 2.5 * k;
            }
            // the shockwave: a bright leading edge (a twelve-petal lotus for godly) with a wall of dust behind it
            let rs_eff = rs * (1.0 + 0.07 * T1 * sin(12.0 * ang + time * 0.6));
            let edge = exp(-pow((r - rs_eff) / 2.8, 2.0)) * shock_fade * near_y;
            add = add + ring_col * edge * 7.0 * k;
            col = col * (1.0 - exp(-pow((r - rs_eff + 4.0) / 3.0, 2.0)) * shock_fade * near_y * 0.5 * T0);
            let rs_in = rs * 0.62 * (1.0 + 0.07 * sin(12.0 * ang + 3.1416 - time * 0.6));
            add = add + ring_col * exp(-pow((r - rs_in) / 1.2, 2.0)) * shock_fade * near_y * 3.0 * k * T1;
        }
    }

    // ---- the beam -------------------------------------------------------------
    let bh = axis_hit(crel.xz + wobble, v2, vv, cam.y, rd.y);
    let t_ray = bh.x;
    let dist = bh.y;
    let y_p = bh.z;
    if (t_ray > 0.0) {
        let c2 = crel.xz + wobble;
        let off = v2 * t_ray - c2;
        let ang_b = atan2(off.y, off.x);
        let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, t_ray), !sky);
        let vis_mix = mix(0.22, 1.0, vis);
        let head = tgt.y + 800.0 * pow(1.0 - saturate(fire_b / mix(0.16, 0.6, T1)), 2.0);
        let above = smoothstep(tgt.y - 1.5, tgt.y + 0.5, y_p) * select(1.0, smoothstep(head - 3.0, head + 3.0, y_p), fire_b > 0.0);
        let n = fbm(vec2<f32>(ang_b * 2.5, y_p * 0.07 - time * 9.0));
        let n2 = fbm(vec2<f32>(ang_b * 2.2 + 11.0 + time * 0.8, y_p * 0.11 - time * 9.0));

        // the designator's thin beam while charging: red for plasma, a golden thread for godly
        let des = exp(-pow(dist / 0.07, 2.0)) * charging * (1.0 - step(0.0, fire_b)) * smoothstep(tgt.y - 1.0, tgt.y + 0.5, y_p);
        add = add + pick2(vec3<f32>(1.0, 0.08, 0.04), vec3<f32>(1.0, 0.8, 0.3)) * des * vis * 2.5 * (0.7 + 0.3 * sin(time * 40.0 * T0));

        if (beam_env > 0.001) {
            let hgt = max(y_p - tgt.y, 0.0);
            if (T0 > 0.5) {
                let plume = 1.0 + 3.2 * exp(-hgt / 9.0);
                let rcb = (0.9 + 1.1 * exp(-fire_t * 1.3) + 0.2 * sin(time * 23.0) + 0.7 * surge) * (0.85 + 0.45 * n) * k * plume;
                let lat = dist * sign(dot(off, vec2<f32>(-c2.y, c2.x)) + 1.0e-5);
                let core = exp(-pow(dist / (rcb * 0.5), 2.0));
                let sheath = exp(-pow(dist / (rcb * 2.0), 2.0));
                let halo = 1.0 / (1.0 + pow(dist / (rcb * 6.0), 2.0));
                let pk = fbm(vec2<f32>(y_p * 0.06 - time * 7.0 + seed, ang_b * 0.9 + time * 0.7));
                let pulse = pow(smoothstep(0.38, 0.82, pk), 2.0) * (0.7 + 1.1 * surge);
                let plasma = tint_beam * (0.55 + 0.9 * n2) * (1.0 + 3.0 * pulse);
                var b = (core * vec3<f32>(8.0, 8.0, 9.0) * (0.85 + 0.5 * surge) + sheath * plasma + halo * tint_alt * 0.3) * above * stutter;
                // twisting energy strands round the beam
                let spin = (6.0 + 10.0 * sr1) * select(-1.0, 1.0, sr2 > 0.5);
                let strand = pow(0.5 + 0.5 * sin(ang_b * 3.0 + y_p * 0.35 - time * spin), 10.0)
                    + pow(0.5 + 0.5 * sin(ang_b * 2.0 - y_p * 0.5 + time * 9.0), 10.0);
                let band = exp(-pow((dist - rcb * 1.5) / (rcb * 0.45), 2.0));
                b = b + tint_alt * 0.8 * strand * band * above;
                add = add + b * beam_env * vis_mix;
                // sparks in beam space: lateral offset x height
                let cell = vec2<f32>(lat * 1.4, y_p * 0.9 - time * 14.0);
                let id = floor(cell);
                let f = fract(cell) - 0.5;
                let spark = step(0.92, hash21(id)) * exp(-dot(f, f) * 26.0) * (1.0 - smoothstep(rcb * 1.2, rcb * 9.0, abs(lat)));
                add = add + vec3<f32>(1.0, 0.75, 0.4) * spark * 3.5 * beam_env * above * vis_mix * k;
            } else {
                // godly: a calm, wide pillar of light; rings of brightness slide down it, motes drift up inside
                let rcg = (2.2 + 1.6 * exp(-max(fire_t, 0.0) * 1.5)) * k;
                let core = exp(-pow(dist / (rcg * 0.55), 2.0));
                let sheath = exp(-pow(dist / (rcg * 2.2), 2.0));
                let halo = 1.0 / (1.0 + pow(dist / (rcg * 7.0), 2.0));
                let stream = 0.75 + 0.5 * fbm(vec2<f32>(ang_b * 3.0, y_p * 0.05 + time * 2.5));
                let slide = fract((y_p - tgt.y + time * 26.0) / 24.0);
                let rings = exp(-pow((slide - 0.5) / 0.03, 2.0)) * exp(-pow((dist - rcg * 1.3) / (rcg * 0.9), 2.0));
                var b = core * vec3<f32>(9.0, 8.2, 6.2) + sheath * vec3<f32>(3.0, 2.3, 1.0) * stream + halo * vec3<f32>(1.4, 1.1, 0.6) * 0.25;
                b = b + vec3<f32>(3.2, 2.6, 1.3) * rings * 1.5;
                add = add + b * above * beam_env * vis_mix;
                let lat = dist * sign(dot(off, vec2<f32>(-c2.y, c2.x)) + 1.0e-5);
                let cell = vec2<f32>(lat * 0.9, y_p * 0.5 - time * 3.0);
                let id = floor(cell);
                let f = fract(cell) - 0.5;
                let mote = step(0.9, hash21(id)) * exp(-dot(f, f) * 30.0) * (1.0 - smoothstep(rcg * 0.8, rcg * 3.0, abs(lat)));
                add = add + vec3<f32>(1.6, 1.4, 0.9) * mote * 1.6 * beam_env * above * vis_mix * k;
            }
        }
        // plasma: a lingering column of embers once the beam has gone
        let ember = crater_env * (1.0 - beam_env) * exp(-pow(dist / 4.0, 2.0)) * smoothstep(tgt.y, tgt.y + 3.0, y_p) * exp(-(y_p - tgt.y) / 30.0) * T0;
        let ecell = floor(vec2<f32>(ang_b * 3.0, y_p * 0.7 - time * 5.0));
        add = add + vec3<f32>(1.0, 0.4, 0.08) * step(0.82, hash21(ecell)) * ember * vis * 0.35 * k;
    }

    // ---- the smoke plume (plasma) / a rising veil of light (godly) ---------------
    let smoke_env = smoothstep(1.2, 4.5, fire_t) * (1.0 - smoothstep(15.0, 26.0, fire_t)) * f32(fired);
    if (smoke_env > 0.001) {
        let sh = axis_hit(crel.xz, v2, vv, cam.y, rd.y);       // the plume stands on the fixed axis: no sway
        let t_s = sh.x;
        let dist_s = sh.y;
        let y_s = sh.z;
        let off_s = v2 * t_s - crel.xz;
        let vis_s = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, t_s), !sky);
        let h = max(y_s - tgt.y, 0.0);
        let top = (fire_t - 1.0) * 11.0;
        let crown = smoothstep(top - 30.0, top - 4.0, h) * (1.0 - smoothstep(top - 6.0, top + 4.0, h));
        let R = 3.5 + 0.2 * h + 13.0 * crown;
        let lat_s = dist_s * sign(dot(off_s, vec2<f32>(-crel.z, crel.x)) + 1.0e-5);
        let turb = fbm(vec2<f32>(lat_s * 0.16 + 3.0, h * 0.16 - time * 0.5 + seed));
        let turb2 = fbm(vec2<f32>(lat_s * 0.34 - 4.0, h * 0.34 - time * 0.9));
        let dens = exp(-pow(dist_s / (R * (0.75 + 0.5 * turb)), 2.0)) * (0.35 + 0.9 * turb2)
            * (1.0 - smoothstep(top - 5.0, top + 3.0, h)) * smoothstep(-1.0, 3.0, y_s - tgt.y);
        let a_s = smoothstep(0.16, 0.7, dens * 1.7) * mix(0.96, 0.35, T1) * smoke_env * vis_s * select(0.0, 1.0, t_s > 0.0);
        let under = exp(-h / 9.0) * crater_env * (0.4 + 0.9 * turb);
        let rim = pow(saturate(1.0 - dist_s / (R * 1.1)), 0.6);
        let sm_lo = pick2(vec3<f32>(0.025, 0.024, 0.027), vec3<f32>(1.0, 0.9, 0.7));
        let sm_hi = pick2(vec3<f32>(0.44, 0.42, 0.43), vec3<f32>(1.6, 1.45, 1.1));
        let under_col = pick2(vec3<f32>(1.0, 0.33, 0.05), vec3<f32>(1.4, 1.0, 0.4));
        let smoke_col = mix(sm_lo, sm_hi, saturate(0.1 + 0.8 * turb2 * (0.35 + h / 80.0)) * (1.0 - 0.5 * rim)) + under_col * under * 1.5;
        col = mix(col, smoke_col, a_s);
    }

    // ---- the impact: a volume in the world, traced along the view ray -------------
    // plasma: a churning fireball that cools to smoke as it climbs into a mushroom; godly: a dome of light.
    if (fired && fire_t < 9.0) {
        let Rv = mix(36.0, 46.0, T1) * (1.0 - exp(-fire_t * 1.6));
        let top_s = (14.0 + fire_t * 13.0) * T0;                   // the plasma stem's crown, rising
        let capr = (9.0 + fire_t * 2.6) * T0;
        let Rb = max(Rv, top_s + capr) + 2.0;
        let oc = cam - tgt;
        let bq = dot(oc, rd);
        let cq = dot(oc, oc) - Rb * Rb;
        let hq = bq * bq - cq;
        if (hq > 0.0) {
            let sq = sqrt(hq);
            let ta = max(-bq - sq, 0.0);
            let tb = min(-bq + sq, scene_len);
            if (tb > ta) {
                let steps = 26;
                let dt = (tb - ta) / f32(steps);
                var trans = 1.0;
                var acc = vec3<f32>(0.0);
                let fade = exp(-fire_t * 0.55);
                for (var i = 0; i < steps; i = i + 1) {
                    let ts = ta + (f32(i) + hash21(uv * 913.0 + f32(i))) * dt;
                    let lp = oc + rd * ts;                         // relative to the impact point
                    let rl = length(lp);
                    let nz = fbm3(lp * 0.07 + vec3<f32>(0.0, -fire_t * 1.6, seed));
                    let up = smoothstep(-2.0, 1.0, lp.y);
                    if (T0 > 0.5) {
                        // the fireball: billows carved out of noise, hottest at the heart, cooling as it climbs;
                        // a stem and a mushroom cap rise out of it in the first seconds
                        let s = rl / max(Rv, 0.5);
                        let rr = length(lp.xz);
                        var body = (1.0 - s) * 1.5 + (nz - 0.5) * 2.4 - 0.2;
                        let stem = (1.0 - rr / (3.5 + max(lp.y, 0.0) * 0.08)) * 1.3 * (1.0 - smoothstep(top_s - 4.0, top_s, lp.y));
                        let capq = length(vec2<f32>(rr / max(capr, 1.0), (lp.y - top_s) / max(capr * 0.5, 1.0)));
                        body = max(body, (max(stem, (1.0 - capq) * 1.6) + (nz - 0.5) * 2.0) * smoothstep(0.4, 1.6, fire_t));
                        let dens = saturate(body) * smoothstep(-6.0, 2.0, lp.y) * (1.0 - smoothstep(5.0, 9.0, fire_t));
                        let temp = saturate(body * 0.7 + 0.2 - fire_t * 0.12 - max(lp.y, 0.0) / 90.0);
                        let emit = plasma_ramp(temp) * 2.4;
                        let smoke = vec3<f32>(0.12, 0.11, 0.12) * (0.4 + nz);
                        let a = 1.0 - exp(-dens * dt * 0.15);
                        acc = acc + trans * a * (emit + smoke);
                        trans = trans * (1.0 - a);
                    } else {
                        // the dome: only a thin shell of light, so it reads as a bright rim where you look across it
                        let shell = exp(-pow((rl - Rv) / (1.5 + Rv * 0.04), 2.0)) * (0.5 + 0.9 * nz) * up;
                        acc = acc + trans * gold_ramp(0.6 + 0.4 * nz) * shell * exp(-fire_t * 0.9) * dt * 0.05;
                    }
                    if (trans < 0.02) {
                        break;
                    }
                }
                col = col * trans + acc * k;
            }
        }
        // the first instant: the whole sky goes white
        add = add + (ring_col * 0.4 + vec3<f32>(1.2)) * exp(-fire_t * 7.0) * mix(1.6, 0.9, T1) * k;
    }

    // ---- lightning (plasma): forked bolts between points round the beam axis ------
    if (T0 > 0.5 && beam_env > 0.001 && pt.z > 0.0) {
        let pa = vec2<f32>(uv.x * aspect, uv.y);
        var lit = vec3<f32>(0.0);
        for (var i = 0; i < 6; i = i + 1) {
            let fi = f32(i);
            let slot = floor(time * (9.0 + 8.0 * sr1) + fi * 3.7);
            let h1 = hash21(vec2<f32>(slot, fi * 5.3));
            let h2 = hash21(vec2<f32>(fi * 9.1, slot + 4.0));
            let h3 = hash21(vec2<f32>(slot * 1.3, fi + 8.0));
            let h4 = hash21(vec2<f32>(slot + 7.0, fi * 2.2));
            if (h3 < 0.22 + 0.35 * sr2) {
                continue;
            }
            let ang = h2 * TAU;
            let reach = (9.0 + 17.0 * h4) * (0.8 + 0.7 * sr1);
            let a3 = vec3<f32>(tgt.x - cam.x, tgt.y + 3.0 + h1 * 55.0 - cam.y, tgt.z - cam.z);
            let b3 = a3 + vec3<f32>(cos(ang) * reach, (h4 - 0.65) * 12.0, sin(ang) * reach);
            let sa = project_rel(a3);
            let sbp = project_rel(b3);
            if (sa.z < 0.0 || sbp.z < 0.0) {
                continue;
            }
            let a2 = vec2<f32>(sa.x * aspect, sa.y);
            let b2 = vec2<f32>(sbp.x * aspect, sbp.y);
            let wid = 0.0026 * k;
            let m = bolt_line(pa, a2, b2, slot + fi * 11.0, slot, wid);
            var v = m;
            let ab = b2 - a2;
            let len = length(ab);
            let dir = ab / max(len, 1.0e-4);
            let nrm = vec2<f32>(-dir.y, dir.x);
            for (var j = 0; j < 2; j = j + 1) {
                let fj = f32(j);
                let u0 = 0.3 + 0.32 * fj + 0.08 * h1;
                let root = a2 + dir * (u0 * len) + nrm * bolt_disp(len, u0, slot + fi * 11.0, slot);
                let sgn = select(-1.0, 1.0, fract(h2 * 7.0 + fj) > 0.5);
                let c = cos(0.7 * sgn);
                let sn = sin(0.7 * sgn);
                let bd = vec2<f32>(dir.x * c - dir.y * sn, dir.x * sn + dir.y * c);
                let fork = bolt_line(pa, root, root + bd * (len * (0.45 - 0.1 * fj)), slot + fi * 11.0 + 5.0 + fj, slot, wid * 0.7);
                v = max(v, fork * 0.8);
            }
            // hidden behind terrain that is nearer than the bolt
            let bolt_d = mix(length(a3), length(b3), m.z);
            let vis_b = select(1.0, smoothstep(bolt_d - 2.0, bolt_d + 0.5, scene_len), !sky);
            let flick = 0.65 + 0.35 * hash21(vec2<f32>(floor(time * 60.0), fi));
            lit = lit + (vec3<f32>(0.85, 0.95, 1.0) * v.x * 7.0 + tint_l * v.y * 0.9) * vis_b * flick * (0.7 + 0.6 * surge);
        }
        add = add + lit * beam_env;
    }

    // ---- godly: halo rings, wings, pillars of light and ribbons, all standing in the world ----
    if (T1 > 0.5) {
        var holy = vec3<f32>(0.0);

        // three halo rings, horizontal circles stacked up the beam, turning in opposite directions
        for (var i = 0; i < 3; i = i + 1) {
            let fi = f32(i);
            let hh = tgt.y + 24.0 + 24.0 * fi + 3.0 * fi * fi;
            let rw = 10.0 + 7.0 * fi;
            let env_h = smoothstep(0.6 + 0.8 * fi, 1.8 + 0.8 * fi, tt) * after;
            if (env_h > 0.001 && abs(rd.y) > 1.0e-4) {
                let th = (hh - cam.y) / rd.y;
                if (th > 0.0 && th < scene_len) {
                    let q = cam.xz + rd.xz * th - tgt.xz;
                    let rr = length(q);
                    let dirn = select(-1.0, 1.0, (i & 1) == 0);
                    let an = atan2(q.y, q.x) + time * 0.12 * dirn;
                    // bands keep at least about a pixel wide far away (and dim to match) so they don't shimmer
                    let wpx = max(th * 0.0018, 0.0001);
                    let w = max(0.3, wpx);
                    let wn = 0.3 / w;
                    var ringv = exp(-pow((rr - rw) / w, 2.0)) * (0.55 + 0.45 * step(0.5, fract(an / TAU * 36.0)));
                    ringv = ringv + exp(-pow((rr - rw + 1.3) / (w * 0.7), 2.0)) * 0.8;
                    let runes = step(0.45, hash21(vec2<f32>(floor(an / TAU * 40.0), fi))) * step(0.15, fract(an / TAU * 40.0));
                    ringv = ringv + runes * (1.0 - smoothstep(0.45, 0.5 + w, abs(rr - rw - 1.6))) * 0.7;
                    let glowr = exp(-pow((rr - rw) / 2.8, 2.0)) * 0.08;
                    holy = holy + gold * (ringv * wn + glowr) * env_h * 1.6;
                }
            }
        }

        // a pair of vast feathered wings, fixed in the world on a plane facing whoever fired
        let wing_env = smoothstep(0.2, 2.6, fire_t) * (1.0 - smoothstep(12.0, 20.0, fire_t)) * f32(fired);
        if (wing_env > 0.001) {
            let wd = wing_dirs();
            let nrm = vec3<f32>(wd.x, 0.0, wd.y);
            let span = vec3<f32>(wd.z, 0.0, wd.w);
            let root = crel + vec3<f32>(0.0, 36.0, 0.0);
            let den = dot(rd, nrm);
            if (abs(den) > 1.0e-3) {
                let th = dot(root, nrm) / den;
                if (th > 0.0 && th < scene_len) {
                    let lp = rd * th - root;
                    let w2 = vec2<f32>(dot(lp, span), lp.y);
                    if (abs(w2.x) < 70.0 && w2.y > -40.0 && w2.y < 40.0) {
                        // a wing: an arm sweeping out from the shoulder to the wrist, a row of long flight feathers
                        // hanging from it (pointing down near the body, swinging outwards towards the tip), a row of
                        // short coverts over their roots, and a fan of primaries off the wrist
                        let sp = 0.35 + 0.65 * smoothstep(0.2, 2.8, fire_t);
                        let ww = max(0.7, th * 0.002);
                        let wn = 0.7 / ww;
                        let sgn = select(-1.0, 1.0, w2.x > 0.0);
                        let q = vec2<f32>(w2.x * sgn, w2.y);                 // fold the left wing onto the right
                        let flap = 0.06 * sin(time * 1.1);
                        let elbow = vec2<f32>(17.0, 11.0 + 4.0 * flap) * sp;
                        let wrist = vec2<f32>(36.0, 17.0 + 8.0 * flap) * sp;
                        var wing = vec2<f32>(0.0);
                        let arm1 = seg_soft(q, vec2<f32>(0.0), elbow, ww * 1.3);
                        let arm2 = seg_soft(q, elbow, wrist, ww * 1.1);
                        wing = wing + (arm1 + arm2) * 0.8;
                        for (var i = 0; i < 14; i = i + 1) {
                            let u = (f32(i) + 0.5) / 14.0;
                            let base = (1.0 - u) * (1.0 - u) * vec2<f32>(0.0) + 2.0 * u * (1.0 - u) * elbow + u * u * wrist;
                            let fa = mix(-1.75, -0.55, pow(u, 1.3)) + 0.04 * sin(time * 1.3 + u * 9.0);
                            let fd = vec2<f32>(cos(fa), sin(fa));
                            let fl = mix(11.0, 30.0, pow(u, 0.8)) * sp;
                            wing = wing + seg_soft(q, base, base + fd * fl, ww);
                            wing = wing + seg_soft(q, base + vec2<f32>(0.0, 0.8), base + fd * fl * 0.42, ww * 1.15) * 0.7;
                        }
                        for (var i = 0; i < 5; i = i + 1) {
                            let fi = f32(i) / 4.0;
                            let fa = mix(-0.5, 0.35, fi);
                            let fl = mix(30.0, 17.0, fi) * sp;
                            wing = wing + seg_soft(q, wrist, wrist + vec2<f32>(cos(fa), sin(fa)) * fl, ww);
                        }
                        holy = holy + (white * min(wing.x, 1.4) * wn * 0.75 + gold * min(wing.y, 2.0) * 0.06) * wing_env;
                    }
                }
            }
        }

        // six pillars of light come down round the beam, onto the quartz pillars strike.py stands there
        for (var i = 0; i < 6; i = i + 1) {
            let fi = f32(i);
            let pa_ = PILLAR_A0 + fi * TAU / 6.0;
            let pc = floor(anc + vec2<f32>(cos(pa_), sin(pa_)) * PILLAR_R) + vec2<f32>(0.5);
            let ph = axis_hit(pc - cam.xz, v2, vv, cam.y, rd.y);
            if (ph.x > 0.0) {
                let envp = smoothstep(0.25 * fi + 0.1, 0.25 * fi + 0.5, fire_t) * (1.0 - smoothstep(9.0, 12.0, fire_t)) * f32(fired);
                let visp = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, ph.x), !sky);
                let landed = smoothstep(tgt.y - 3.0, tgt.y - 1.0, ph.z);
                let dropping = smoothstep(-2.0, 2.0, ph.z - (tgt.y + 300.0 * pow(1.0 - saturate((fire_t - 0.25 * fi - 0.1) / 0.35), 2.0)));
                let prof = exp(-pow(ph.y / 0.55, 2.0)) * 3.0 + exp(-pow(ph.y / 2.0, 2.0)) * 0.6;
                holy = holy + vec3<f32>(1.5, 1.35, 0.9) * prof * envp * visp * landed * dropping;
            }
        }

        // two golden ribbons spiral up round the beam
        let hx_env = smoothstep(0.5, 2.5, fire_t) * (1.0 - smoothstep(10.0, 13.0, fire_t)) * f32(fired);
        if (hx_env > 0.001 && pt.z > 0.0) {
            let pa = vec2<f32>(uv.x * aspect, uv.y);
            for (var rb = 0; rb < 2; rb = rb + 1) {
                let ph0 = f32(rb) * 3.14159;
                var prev = project_rel(crel + vec3<f32>(cos(ph0 + time * 1.6) * 5.0, 0.5, sin(ph0 + time * 1.6) * 5.0));
                for (var j = 1; j < 30; j = j + 1) {
                    let hgt = f32(j) * 3.0;
                    let a = ph0 + hgt * 0.22 + time * 1.6;
                    let rad = 5.0 + hgt * 0.06;
                    let p3 = crel + vec3<f32>(cos(a) * rad, hgt, sin(a) * rad);
                    let cur = project_rel(p3);
                    if (prev.z > 0.0 && cur.z > 0.0) {
                        let sgm = seg_soft(pa, vec2<f32>(prev.x * aspect, prev.y), vec2<f32>(cur.x * aspect, cur.y), 0.0028 * 40.0 / max(length(p3), 10.0));
                        let vis_r = select(1.0, step(length(p3) - 1.0, scene_len), !sky);
                        let fade = 1.0 - f32(j) / 30.0;
                        holy = holy + (vec3<f32>(1.7, 1.3, 0.5) * sgm.x + vec3<f32>(1.2, 0.8, 0.3) * sgm.y * 0.3) * hx_env * (0.4 + 0.6 * fade) * vis_r;
                    }
                    prev = cur;
                }
            }
        }
        add = add + holy * k;
    }

    // ---- the lens: bloom round the light, plasma's anamorphic streak, the flash ----
    if (pt.z > 0.0) {
        let dd = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let bloom = 1.0 / (1.0 + dot(dd, dd) * 220.0);
        add = add + pick2(vec3<f32>(1.0, 0.7, 0.5), vec3<f32>(1.0, 0.9, 0.6)) * bloom * (beam_env * 0.6 + flash * 0.8) * k * mix(1.0, 0.45, T1);
        let streak = exp(-abs(dd.y) * 260.0) * exp(-abs(dd.x) * 3.2);
        add = add + vec3<f32>(0.3, 0.8, 2.6) * streak * beam_env * 0.9 * k * T0;
    }
    add = add + pick2(vec3<f32>(0.9, 0.95, 1.0), vec3<f32>(1.0, 0.95, 0.75)) * flash * flash * 0.9 * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    let tint = pick2(vec3<f32>(1.0, 0.45, 0.35), vec3<f32>(1.0, 0.8, 0.3)) * charging * 0.12
        + pick2(vec3<f32>(0.5, 0.2, 1.0), vec3<f32>(1.0, 0.85, 0.4)) * beam_env * 0.07;
    outc = outc * (1.0 - smoothstep(0.35, 1.0, vg) * (0.15 + 0.35 * (charging + beam_env) * 0.5) * k * mix(1.0, 0.4, T1)) + tint * smoothstep(0.3, 1.0, vg) * k;
    outc = aces(outc * 0.9);
    let srgb = linear_to_srgb(outc);
    if (capture() > 2.5) {
        // video capture: luma in red, alternating chroma in green (a screenshot loses the blue channel)
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    return vec4<f32>(srgb, 1.0);
}
