// Orbital Laser's post pass (capability `render`): one full-screen pass over the
// world, drawn after any shader pack. Everything is anchored in the world by
// rebuilding each pixel's position from the depth buffer and the camera
// matrices, or by tracing the view ray against shapes placed in the world
// (planes, cylinders, a volume). Nothing is painted flat on the screen except
// the lens: bloom, a streak, the flash.
//
// The mod hands it sixteen numbers each frame, `frame.mod_params`:
//   [0] target x, y, z (the point hit), strike clock in seconds
//   [1] hit block centre x, z, the wings' facing (radians: towards the player, the mothership points away), laser
//   [2] seed, intensity, capture mode (0 off, 3 video capture), hit block y
//   [3] the mothership's approach (0 towards the player, 1 from behind them, 2 from their left, 3 from their right,
//       4 from overhead), and how it arrives (0 snap, 1 unfold, 2 warp); unused by the others
//
// Lasers:
//   0 Plasma   a raging plasma beam, forked lightning, a churning fireball, a smoke plume
//   1 Godly    the clouds part, a calm pillar of light comes down, halo rings and wings stand
//              in the sky, six pillars of light land round a golden sigil, a dome of light
//   2 Black hole  a singularity over the target bends the light round it; an accretion disk, a jet
//              out of both poles, the land dragged in, and it evaporates in a flash (`singularity`)
//   3 Meteor storm  meteors pound the land round the target, then one the size of a hill lands on it: a
//              fireball, a shockwave, ejecta across the sky and a sky gone brown with dust (`meteor_storm`)
//   4 Mothership  a slab of dark metal a kilometre long drops out of hyperspace over the target and stops dead, its
//              shadow on the land; its emitters' green beams meet under it, and one beam comes down and sweeps away,
//              cutting a molten trench; then it is gone (`mothership`)
//   5 Downfall  its own pass (shaders/downfall.wgsl, after everything here up to fs_main): the mothership brought down
//              by a meteor, its black hole engine rupturing (`downfall`). [3].z there is how far downrange its stern
//              comes to rest. Kept out of this pass so its size costs the other lasers nothing.

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
fn approach() -> i32 { return i32(frame.mod_params[3].x + 0.5); }
// The ship lasers' own light, in the colour picked for them (frame.mod_params[3].w: 0 green, the Mothership's own, 1 red,
// 2 amber, 3 blue, 4 violet, 5 white): their green lights taken through a matrix (each column what that channel turns
// into). Green leaves them exactly as they are.
fn ship_tint(c: vec3<f32>) -> vec3<f32> {
    let i = i32(frame.mod_params[3].w + 0.5);
    if (i <= 0) {
        return c;
    }
    var m = mat3x3<f32>(0.25, 0.25, 0.25, 0.62, 0.65, 0.68, 0.1, 0.1, 0.1);
    switch i {
        case 1: { m = mat3x3<f32>(0.2, 0.35, 0.0, 1.0, 0.1, 0.03, 0.0, 0.0, 0.2); }
        case 2: { m = mat3x3<f32>(0.2, 0.3, 0.0, 1.0, 0.55, 0.05, 0.0, 0.0, 0.15); }
        case 3: { m = mat3x3<f32>(0.1, 0.1, 0.2, 0.12, 0.45, 1.0, 0.0, 0.1, 0.3); }
        case 4: { m = mat3x3<f32>(0.2, 0.2, 0.1, 0.7, 0.12, 1.0, 0.0, 0.0, 0.3); }
        default: {}
    }
    return m * c;
}
fn arrival_style() -> i32 { return i32(frame.mod_params[3].y + 0.5); }

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

// ---- falling into a black hole (the Black Hole's and the Downfall's debris, and the Downfall's wreck) ----
// How far out a piece is `u` (0 to 1) of the way through its fall from `r0`: from rest, slowly at first, then faster and
// faster, through the horizon and into the middle by u = 1 (r0 (1 - u²)^(2/3), close to a free fall's).
fn bh_fall(r0: f32, u: f32) -> f32 {
    return r0 * pow(max(1.0 - u * u, 0.0), 0.6667);
}
// How many times as long a piece `l0` long is drawn out at `u` through its fall from `r0` (its near end at `r`, bh_fall):
// its far end falls the same way from further out, so later (`lag` times as long: the free fall's time goes as r^1.5),
// and the gap between them grows faster and faster as they near the hole; at most 6 times.
fn bh_tide(r0: f32, l0: f32, r: f32, u: f32, lag: f32) -> f32 {
    return clamp((bh_fall(r0 + l0, u / lag) - r) / l0, 1.0, 6.0);
}
// No less than bh_tide, without its pow (the far end's fall to first order): for culling.
fn bh_tide_max(r0: f32, l0: f32, r: f32, u: f32, lag: f32) -> f32 {
    let rt = (r0 + l0) / r0 * r * (1.0 + 1.3333 * u * u * (1.0 - 1.0 / lag) / max(1.0 - u * u, 1.0e-4));
    return select(clamp((rt - r) / l0, 1.0, 6.0), 6.0, u > 0.97);
}
// The light from something `r` from the hole: redder and dimmer nearer the horizon (climbing out of the hole's pull),
// none from the horizon in.
fn bh_redshift(r: f32, rs: f32) -> vec3<f32> {
    let z = sqrt(saturate(1.0 - rs / max(r, 1.0e-3)));
    return vec3<f32>(pow(z, 0.7), pow(z, 1.6), pow(z, 2.6));
}
// A ray from the camera (`rd`) against a piece falling in: a box of half-size `hs`, turned `ang` about `ax`, drawn out
// `k` times along `u` (out from the hole) and thinned across about its middle `c` (camera-relative); none of it from the
// horizon (`rs` round `H`) in. How far (x, -1: missed), and where on it in its own space (yzw, the box -1 to 1).
fn bh_chunk(c: vec3<f32>, rd: vec3<f32>, u: vec3<f32>, k: f32, hs: f32, ax: vec3<f32>, ang: f32, H: vec3<f32>, rs: f32) -> vec4<f32> {
    let sk = sqrt(k);
    let ro = -c;
    let ro_s = (ro - u * dot(u, ro)) * sk + u * dot(u, ro) / k;
    let rd_s = (rd - u * dot(u, rd)) * sk + u * dot(u, rd) / k;
    let ro_l = rot_axis(ro_s, ax, -ang) / hs;
    let rd_l = rot_axis(rd_s, ax, -ang) / hs;
    let inv = 1.0 / select(rd_l, vec3<f32>(1.0e-6), abs(rd_l) < vec3<f32>(1.0e-6));
    let ta = (vec3<f32>(-1.0) - ro_l) * inv;
    let tb = (vec3<f32>(1.0) - ro_l) * inv;
    let tlo = min(ta, tb);
    let thi = max(ta, tb);
    let tn = max(max(tlo.x, tlo.y), tlo.z);
    let tf = min(min(thi.x, thi.y), thi.z);
    // (where the ray meets it inside the horizon, what is behind is in the hole's shadow)
    if (tf < tn || tn < 0.0 || length(rd * tn - H) < rs) {
        return vec4<f32>(-1.0);
    }
    return vec4<f32>(tn, ro_l + rd_l * tn);
}
// The world normal of the face of a bh_chunk box at `lp` (its own space).
fn bh_chunk_n(lp: vec3<f32>, u: vec3<f32>, k: f32, ax: vec3<f32>, ang: f32) -> vec3<f32> {
    let al = abs(lp);
    var nl = vec3<f32>(0.0, sign(lp.y), 0.0);
    if (al.x >= al.y && al.x >= al.z) {
        nl = vec3<f32>(sign(lp.x), 0.0, 0.0);
    } else if (al.z >= al.y) {
        nl = vec3<f32>(0.0, 0.0, sign(lp.z));
    }
    // (the stretch is symmetric, so normals go back through it as it is)
    let ns = rot_axis(nl, ax, ang);
    return normalize((ns - u * dot(u, ns)) * sqrt(k) + u * dot(u, ns) / k);
}

// One piece of debris: where its near end is (camera-relative), its radial direction from the hole, how stretched it
// is (or below 0: drawn out by the tides, worked out by bh_tide from `tide` (r0, l0, u, lag) and `r` only once the ray is
// known to pass near it), how hot, how present (0: not there).
struct Piece {
    c: vec3<f32>,
    u: vec3<f32>,
    k: f32,
    glow: f32,
    alive: f32,
    tide: vec4<f32>,
    r: f32,
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
    let l0 = select(1.0, 2.0, big);
    let lag = (R0 + l0) / R0 * sqrt((R0 + l0) / R0);
    let u = min(ub, select(lag, u_f, flung));
    // the disk's plane, with world x and z laid onto it so the orbit starts where the block was torn out
    let E1 = normalize(vec3<f32>(1.0, 0.0, 0.0) - n * n.x);
    let E2 = normalize(vec3<f32>(0.0, 0.0, 1.0) - n * n.z - E1 * dot(vec3<f32>(0.0, 0.0, 1.0), E1));
    let rsn = max(rs, 0.6);
    // its near end falls from rest, faster and faster, through the horizon to the middle; its far end, a block or two
    // further out, falls in a little after it (the free fall's time goes as r^1.5): so the tides draw it out along the
    // way in, more and more as it nears the hole
    let r = bh_fall(R0, u);
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
    var stretch = select(1.0, -bh_tide_max(R0, l0, r, u, lag), !flung || ub < u_f);
    if (flung && ub > u_f) {
        // slingshot round the hole and away
        let dt = (ub - u_f) * T_in;
        let tdir = E1 * sin(th) - E2 * cos(th);
        c = c + (tdir * 65.0 + n * 16.0) * dt;
        alive = alive * (1.0 - smoothstep(2.5, 4.0, dt));
        stretch = 1.0;
    } else if (!flung) {
        // eaten: gone once its far end too is through the horizon
        alive = alive * (1.0 - step(lag, ub));
    }
    if (ft > BH_END) {
        // what was still circling when it evaporated is thrown outwards
        let ef = ft - BH_END;
        c = c + normalize(c - H) * ef * 70.0;
        alive = alive * (1.0 - smoothstep(1.0, 2.5, ef));
        stretch = 1.0;
    }
    pc.u = normalize(c - H + vec3<f32>(1.0e-4));
    pc.c = c;
    pc.k = stretch;
    pc.tide = vec4<f32>(R0, l0, u, lag);
    pc.r = r;
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

// What a view ray brings back past a black hole at `H` (camera-relative) of horizon radius `rs_l`: it is marched through
// the hole's gravity (the photon orbit equation, in horizon radii), picking up the disk's light (`acc`, seen through
// `trans` of it) where it crosses the disk's plane (normal `n`, `e1` `e2` in it), and either falls in (`captured`), ends
// on the scene (`hit`), or leaves along `v` from `p` (camera-relative) and resamples the scene that way (`bent`; `w`
// how much the bending counts). `on`: whether the ray came near enough to be bent at all.
struct BhLens {
    on: bool,
    captured: bool,
    hit: bool,
    bent: vec3<f32>,
    trans: f32,
    acc: vec3<f32>,
    rmin: f32,
    p: vec3<f32>,
    v: vec3<f32>,
    w: f32,
}
fn bh_lens(H: vec3<f32>, rs_l: f32, rd: vec3<f32>, uv2: vec2<f32>, scene_len: f32, sky: bool, n: vec3<f32>, e1: vec3<f32>,
           e2: vec3<f32>, disk_env: f32, hot: f32, seed: f32, time: f32, sky_env: f32, dim: f32) -> BhLens {
    var L: BhLens;
    L.on = false;
    L.captured = false;
    L.hit = false;
    L.bent = vec3<f32>(0.0);
    L.trans = 1.0;
    L.acc = vec3<f32>(0.0);
    L.rmin = 1.0e9;
    L.p = vec3<f32>(0.0);
    L.v = rd;
    L.w = 0.0;
    let infl = LENS_R * rs_l;
    let tc = dot(H, rd);
    let b = length(H - rd * tc);
    let t0 = max(tc - infl, 0.0);
    if (b < infl && tc + infl > 0.0 && scene_len > t0) {
        L.on = true;
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
        L.captured = captured;
        L.hit = hit;
        L.bent = bent;
        L.trans = trans;
        L.acc = acc;
        L.rmin = rmin;
        L.p = H + pp * rs_l;
        L.v = v;
        L.w = w;
    }
    return L;
}

// [lasers pass only]
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

    // ---- the imploding ring's refraction (the camera's shake is the game's, scheduled in strike.rs) ----
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
    let uv2 = clamp(uv - rdir * ring_mask * 0.06 * k * pt.z + suck + gw_dir * gw * 0.045 * k, vec2<f32>(0.002), vec2<f32>(0.998));

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
        let L = bh_lens(H, rs_l, rd, uv2, scene_len, sky, n, e1, e2, disk_env, hot, seed, time, sky_env, dim);
        if (L.on) {
            col = L.bent * L.trans + L.acc * k;
            swallowed = L.captured;
            // the photon ring: light that went round the hole before getting out
            add = add + vec3<f32>(2.6, 1.7, 1.0) * exp(-pow((L.rmin - 1.52) / 0.05, 2.0)) * disk_env * select(1.0, 0.0, L.captured) * 1.4 * k;
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
            // quick reject: the ray misses the piece's bounding sphere, however far it is drawn out
            let far_ = abs(pc.k) * hs;
            let mid = pc.c + pc.u * far_;
            let tq = dot(mid, rd);
            let reach = hs * 1.8 + far_;
            if (tq < 0.0 || length(mid - rd * tq) > reach || tq - reach > best) {
                continue;
            }
            let k = select(pc.k, bh_tide(pc.tide.x, pc.tide.y, pc.r, pc.tide.z, pc.tide.w), pc.k < 0.0);
            let cen = pc.c + pc.u * (pc.tide.y * 0.5 * k);       // (its middle: its near end is where it has fallen to)
            if (k > 1.5) {
                // (and, drawn out, the ray misses the sliver it has become)
                let qs = ray_seg(rd, pc.c, pc.c + pc.u * (pc.tide.y * k));
                if (qs.x > hs * 1.8) {
                    continue;
                }
            }
            // into the piece's own space: undo the stretch towards the hole, then its tumble
            let ax = normalize(vec3<f32>(fh21(vec2<f32>(fi, 1.0)), fh21(vec2<f32>(fi, 2.0)), fh21(vec2<f32>(fi, 3.0))) - 0.5 + 1.0e-3);
            let spin = (ft - debris_t(fi)) * (1.5 + 3.0 * fh21(vec2<f32>(fi, 4.0))) * (1.0 + 2.0 * pc.glow);
            let bx = bh_chunk(cen, rd, pc.u, k, hs, ax, spin, H, rs);
            if (bx.x < 0.0 || bx.x > best || (swallowed && bx.x > tch)) {
                continue;
            }
            best = bx.x;
            found = true;
            let lp = bx.yzw;
            let al = abs(lp);
            var fuv = lp.xz;
            var top = lp.y > 0.0;
            if (al.x >= al.y && al.x >= al.z) {
                fuv = lp.zy;
                top = false;
            } else if (al.z >= al.y) {
                fuv = lp.xy;
                top = false;
            }
            let nw = bh_chunk_n(lp, pc.u, k, ax, spin);
            let px = floor((fuv * 0.5 + 0.5) * 16.0 * hs * 2.0);
            let kind = min(i32(fh21(vec2<f32>(fi, seed + 13.0)) * 6.0), 5);
            let albedo = srgb_to_linear(debris_tex(kind, px, top, lp.y, seed + fi));
            let sunl = 0.3 + 0.7 * max(dot(nw, normalize(vec3<f32>(0.3, 1.0, 0.2))), 0.0);
            let rp = length(rd * bx.x - H);
            let rl = rp / max(rs, 0.6);
            let diskl = vec3<f32>(2.2, 1.0, 0.45) * max(dot(nw, -pc.u), 0.0) * disk_env * 6.0 / (1.0 + rl * 0.5);
            var cc = albedo * (sunl * dim + diskl);
            // tidal heating, then the redshift taking it as it goes through the horizon
            cc = cc + vec3<f32>(2.6, 0.7, 0.15) * pc.glow * pc.glow * 1.5 + vec3<f32>(0.6, 0.2, 1.0) * pc.glow * 0.3;
            cc = cc * bh_redshift(rp, rs) * pc.alive;
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
// [end lasers pass only]

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

// [lasers pass only]
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

    // ---- the shockwave's refraction (the camera's shake is the game's, scheduled in strike.rs) ----
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
    let uv2 = clamp(uv + sdir * shock_mask * 0.05 * k * pt.z + haze * k, vec2<f32>(0.002), vec2<f32>(0.998));

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
// [end lasers pass only]

// ---- laser 4: the mothership --------------------------------------------------------------------------------------
// A ship a kilometre long, a slab of dark metal with a blunted, tapering bow, drops out of hyperspace over the target:
// it bursts out of a point and unfolds to its full size as it rushes in along its heading from far off (the approach
// the player picked), and stops dead high overhead in about a quarter of a second, smeared by real motion blur. It
// leaves the way it points, stretching out as it goes. It is never marched: each view ray is met analytically with the hull's three stepped
// tiers (flat floors at fixed heights, each bounded by a rectangular outline in the ship's own plan, with the walls
// between them found by bisecting the outline), and the plating, seams and lights are worked out only where the ray
// lands. Its shadow is the same outline seen along the sun. strike.rs cuts the trench where the beam is on the ground
// (ms_sweep): keep the formulas in step.

const MS_H: f32 = 420.0;           // its belly over the target; keep in step with strike.rs: MS_*, TRENCH_L
const MS_ARRIVE: f32 = 3.0;        // it drops out of hyperspace
const MS_SNAP: f32 = 0.167;        // the snap: stopped this long after, four film frames
const MS_IN: f32 = 0.28;           // the unfold: stopped, at its full size, this long after
const MS_WARP: f32 = 0.45;         // the warp: out of its streak this long after
const MS_BEAM: f32 = 8.0;          // the beam leaves the ship
const MS_HIT: f32 = 8.2;           // and lands on the target
const MS_SWEEP0: f32 = 10.0;       // it sweeps away from the player
const MS_SWEEP1: f32 = 19.0;
const MS_CUT: f32 = 20.0;          // the beam cuts off
const MS_LEAVE: f32 = 23.0;        // it goes
const MS_OUT: f32 = 0.3;           // and is gone this long after
const MS_END: f32 = 32.0;          // the trench has cooled (the strike runs 34 s)
const MS_FAR: f32 = 24000.0;       // how far off along its heading it comes from, and goes to
const MS_COAST: f32 = 14.0;        // what it coasts on after the stop, dying away long before the beam fires
const MS_SHUTTER: f32 = 0.0417;    // the motion blur's shutter: a film frame, 1/24 s (the snap's is half of it, 180°)
const TRENCH_L: f32 = 100.0;
const MS_HL: f32 = 560.0;          // its half-length and half-width, and how far its stern's corners are cut off
const MS_HW: f32 = 250.0;
const MS_CHAMFER: f32 = 50.0;
const MS_TAPER: f32 = 220.0;       // its bow tapers over this length, to a blunt tip this wide either side
const MS_TIP: f32 = 70.0;
const MS_EM_X: f32 = 70.0;         // the eye (where the beam comes from), along the hull from its middle towards the bow
const MS_EYE_R: f32 = 46.0;
const MS_EYE_UP: f32 = 18.0;       // how far the eye is set up into the belly
const MS_FOCUS: f32 = 70.0;        // the emitters' beams meet this far under the belly
const MS_TIER_B: f32 = 28.0;       // the tiers' floors, over the belly (the keel's): middle, outer, and its top
const MS_TIER_C: f32 = 56.0;
const MS_TOP: f32 = 150.0;
const MS_HANGAR: vec4<f32> = vec4<f32>(-290.0, 0.0, 90.0, 100.0);   // the hangar bay: middle (x, z), half-length, half-width
const MS_HANGAR_UP: f32 = 115.0;   // its ceiling, over the belly
const CLOUD_Y: f32 = 192.0;        // the vanilla cloud layer

// How far along the trench the beam is at `t`, 0 to 1, and when it is `u` of the way (strike.rs's ms_sweep, ms_when).
fn ms_sweep(t: f32) -> f32 {
    let s = saturate((t - MS_SWEEP0) / (MS_SWEEP1 - MS_SWEEP0));
    return s * s * (3.0 - 2.0 * s);
}
fn ms_when(u: f32) -> f32 {
    return MS_SWEEP0 + (MS_SWEEP1 - MS_SWEEP0) * (0.5 - sin(asin(1.0 - 2.0 * saturate(u)) / 3.0));
}
// The way the beam sweeps: from the target away from the player (strike.rs's ms_axis). The ship points the other way.
fn ms_axis() -> vec2<f32> {
    let a = wing_a();
    return -vec2<f32>(cos(a), sin(a));
}

// Where the ship is: where its middle stops (xz), its heading and across it, its belly's height, how far along its
// heading it is from there, and how it is scaled along (sx, round `px`), across (sz) and up (sy, from its belly).
struct MsFrame {
    c: vec2<f32>,
    ax: vec2<f32>,
    sd: vec2<f32>,
    y0: f32,
    shift: f32,
    sx: f32,
    sz: f32,
    sy: f32,
    px: f32,
}

// How long after it drops in it has stopped, for each way of arriving (0 snap, 1 unfold, 2 warp).
fn ms_stop(style: i32) -> f32 {
    return select(select(MS_WARP, MS_IN, style == 1), MS_SNAP, style == 0);
}

// The ship at `t`, coming in on approach `mode` (4: dropping from overhead, the rest along its heading) in `style`:
//   0 snap: solid from the first frame, a hard rigid slide in from far off, slowing so hard it is all but there after
//     a frame or two, then the last few blocks coasted to a standstill;
//   1 unfold: it bursts out of a point, unfolding to its full size as it rushes in;
//   2 warp: it is there at once, but smeared out kilometres back along its path, and pulls in out of the streak.
// On the way out it accelerates away the way it points (straight up from overhead), its bow leading and its stern
// lagging, so it stretches out as it goes.
fn ms_frame(base: MsFrame, t: f32, mode: i32, style: i32) -> MsFrame {
    var f = base;
    let up = mode == 4;
    let td = t - MS_LEAVE;
    if (td > 0.0) {
        let u = td / MS_OUT;
        let lead = MS_FAR * u * u * u;
        let lag = MS_FAR * pow(u, 4.5);
        if (up) {
            f.y0 = f.y0 + lag;
            f.sy = 1.0 + (lead - lag) / MS_TOP;
        } else {
            f.shift = lag;
            f.px = -MS_HL;
            f.sx = 1.0 + (lead - lag) / (2.0 * MS_HL);
        }
        return f;
    }
    let ta = max(t - MS_ARRIVE, 0.0);
    var far = MS_COAST * exp(-ta / 1.3);
    if (style == 2) {
        // smeared out behind its bow (above its belly, from overhead), narrower the more it is stretched
        let s = 1.0 + 70.0 * exp(-ta * 13.0);
        if (up) {
            f.sy = s;
        } else {
            f.sx = s;
            f.px = MS_HL;
            f.sz = 1.0 / (1.0 + (s - 1.0) * 0.3);
        }
    } else if (style == 1) {
        let u = saturate(ta / MS_IN);
        far = far + MS_FAR * pow(1.0 - u, 4.0);
        let s = max(1.0 - pow(1.0 - u, 2.2), 0.002);
        f.sx = s;
        f.sz = s;
        f.sy = s;
    } else {
        far = far + MS_FAR * pow(1.0 - saturate(ta / MS_SNAP), 5.0);
    }
    if (up) {
        f.y0 = f.y0 + far;
    } else {
        f.shift = -far;
    }
    return f;
}
fn ms_here(t: f32) -> bool {
    return t >= MS_ARRIVE && t < MS_LEAVE + MS_OUT;
}

// A world xz into the ship's plan: x along it (the bow at +560, the stern at -560), y across, in blocks; and back.
fn ms_local(f: MsFrame, p: vec2<f32>) -> vec2<f32> {
    let r = p - f.c;
    return vec2<f32>((dot(r, f.ax) - f.shift - f.px) / f.sx + f.px, dot(r, f.sd) / f.sz);
}
fn ms_world(f: MsFrame, q: vec2<f32>) -> vec2<f32> {
    return f.c + f.ax * (f.shift + f.px + (q.x - f.px) * f.sx) + f.sd * (q.y * f.sz);
}

// The sponsons stepping out of its sides: how far out at `x`.
fn ms_sponson(x: f32) -> f32 {
    return 32.0 * (step(abs(x + 150.0), 70.0) + step(abs(x - 130.0), 70.0));
}
// The hull's half-width at `x` along it: the full width (and the sponsons), narrowing over the bow to its blunt tip.
fn ms_half_w(x: f32) -> f32 {
    return min(MS_HW + ms_sponson(x), MS_HW - (MS_HW - MS_TIP) * (x - (MS_HL - MS_TAPER)) / MS_TAPER);
}

// The hull's outline, a long slab with sponsons stepping out of its sides, its stern's corners cut off and its bow
// tapering to a blunt tip, eroded by `inset` blocks: below 0 inside, roughly the distance to its edge.
fn ms_outline(q: vec2<f32>, inset: f32) -> f32 {
    let a = abs(q);
    var d = max(a.x - MS_HL + inset, a.y - MS_HW - ms_sponson(q.x) + inset);
    d = max(d, (a.x + a.y - (MS_HL + MS_HW - MS_CHAMFER) + inset * 1.4142) * 0.7071);
    let slope = (MS_HW - MS_TIP) / MS_TAPER;
    return max(d, (a.y + slope * (q.x - (MS_HL - MS_TAPER)) - MS_HW) / sqrt(1.0 + slope * slope) + inset);
}
// The hangar bay's outline (below 0 inside).
fn ms_hangar(q: vec2<f32>) -> f32 {
    return max(abs(q.x - MS_HANGAR.x) - MS_HANGAR.z, abs(q.y - MS_HANGAR.y) - MS_HANGAR.w);
}

// Tier `k`'s outline (each inside the next, so a ray from below meets them in order):
//   0 the keel: a ridge down the middle the whole length, widening at the stern into the engine block, broken by the
//     hangar bay;
//   1 the middle deck: two long trenches let into it either side of the keel, recessed bays in its long sides, the
//     hangar's mouth;
//   2 the outer hull, its long sides stepped in and out in long blocks.
fn ms_tier(q: vec2<f32>, k: i32) -> f32 {
    if (k == 0) {
        let ridge = max(abs(q.y) - 70.0, ms_outline(q, 30.0));
        let engines = max(max(abs(q.y) - 170.0, q.x + 430.0), ms_outline(q, 42.0));
        return max(min(ridge, engines), -ms_hangar(q));
    }
    if (k == 1) {
        var d = ms_outline(q, 40.0);
        let cell = floor(q.x / 140.0);
        let bay = max(abs(q.x - (cell + 0.5) * 140.0) - 36.0, MS_HW - 74.0 - abs(q.y));
        d = max(d, select(-1.0e9, -bay, fh21(vec2<f32>(cell, sign(q.y) * 3.0 + 11.0)) > 0.35));
        let trench = max(abs(abs(q.y) - 119.0) - 7.0, abs(q.x + 60.0) - 360.0);
        return max(max(d, -trench), -ms_hangar(q));
    }
    let step_in = step(0.5, fh21(vec2<f32>(floor(q.x / 100.0), sign(q.y) + 3.0))) * step(abs(q.x), MS_HL - 60.0);
    return ms_outline(q, 0.0) + 8.0 * step_in;
}
fn ms_eye(q: vec2<f32>) -> f32 {
    return length(q - vec2<f32>(MS_EM_X, 0.0)) - MS_EYE_R;
}
fn ms_tier_h(k: i32) -> f32 {
    return select(select(MS_TOP, MS_TIER_C, k == 2), select(MS_TIER_B, 0.0, k == 0), k < 2);
}

// Where a view ray meets the hull: how far, where in its plan, how high over the belly, and what it hit: 0, 1, 2 a
// tier's floor, 3 a tier's wall, 4 the eye's ceiling, 5 the eye's wall, 6 the hangar's ceiling, 7 its wall; -1 nothing.
struct MsHit {
    t: f32,
    q: vec2<f32>,
    h: f32,
    kind: i32,
}

// Up a recess from its mouth at `t_lo`: its ceiling (`up` over the belly), or its wall on the way (found by bisecting
// `which`'s outline: 0 the eye, 1 the hangar).
fn ms_recess(f: MsFrame, cam: vec3<f32>, rd: vec3<f32>, t_lo: f32, up: f32, which: i32) -> MsHit {
    var hit: MsHit;
    let t_c = (f.y0 + up * f.sy - cam.y) / rd.y;
    let q_c = ms_local(f, cam.xz + rd.xz * t_c);
    if (select(ms_hangar(q_c), ms_eye(q_c), which == 0) < 0.0) {
        hit.t = t_c;
        hit.q = q_c;
        hit.h = up;
        hit.kind = select(6, 4, which == 0);
        return hit;
    }
    var a = t_lo;
    var b = t_c;
    for (var i = 0; i < 5; i = i + 1) {
        let m = 0.5 * (a + b);
        let qm = ms_local(f, cam.xz + rd.xz * m);
        if (select(ms_hangar(qm), ms_eye(qm), which == 0) < 0.0) {
            a = m;
        } else {
            b = m;
        }
    }
    hit.t = b;
    hit.q = ms_local(f, cam.xz + rd.xz * b);
    hit.h = (cam.y + rd.y * b - f.y0) / f.sy;
    hit.kind = select(7, 5, which == 0);
    return hit;
}

// Met from underneath only: the footprints grow tier by tier going up, so the first thing the ray meets is a floor it
// is inside at the floor's height, or the wall it crosses before the next floor, or one of the two recesses (the eye
// in the keel, the hangar in the middle deck). A dozen outline tests at most.
fn ms_trace(f: MsFrame, cam: vec3<f32>, rd: vec3<f32>) -> MsHit {
    var hit: MsHit;
    hit.t = 1.0e9;
    hit.q = vec2<f32>(0.0);
    hit.h = 0.0;
    hit.kind = -1;
    if (rd.y < 1.0e-3 || cam.y > f.y0) {
        return hit;
    }
    // quick reject: the ray passes the hull's whole height clear of it
    let pa = cam.xz + rd.xz * ((f.y0 - cam.y) / rd.y);
    let pb = cam.xz + rd.xz * ((f.y0 + MS_TOP * f.sy - cam.y) / rd.y);
    let ab = pb - pa;
    let mid = ms_world(f, vec2<f32>(0.0));
    let u = saturate(dot(mid - pa, ab) / max(dot(ab, ab), 1.0e-4));
    if (length(pa + ab * u - mid) > 640.0 * max(f.sx, f.sz)) {
        return hit;
    }
    for (var k = 0; k < 3; k = k + 1) {
        let t_lo = (f.y0 + ms_tier_h(k) * f.sy - cam.y) / rd.y;
        let t_hi = (f.y0 + ms_tier_h(k + 1) * f.sy - cam.y) / rd.y;
        let q_lo = ms_local(f, cam.xz + rd.xz * t_lo);
        if (k == 1 && ms_hangar(q_lo) < 0.0 && ms_outline(q_lo, 40.0) < 0.0) {
            return ms_recess(f, cam, rd, t_lo, MS_HANGAR_UP, 1);
        }
        if (ms_tier(q_lo, k) < 0.0) {
            if (k == 0 && ms_eye(q_lo) < 0.0) {
                return ms_recess(f, cam, rd, t_lo, MS_EYE_UP, 0);
            }
            hit.t = t_lo;
            hit.q = q_lo;
            hit.h = ms_tier_h(k);
            hit.kind = k;
            return hit;
        }
        let q_hi = ms_local(f, cam.xz + rd.xz * t_hi);
        if (ms_tier(q_hi, k) < 0.0) {
            var a = t_lo;
            var b = t_hi;
            for (var i = 0; i < 5; i = i + 1) {
                let m = 0.5 * (a + b);
                if (ms_tier(ms_local(f, cam.xz + rd.xz * m), k) < 0.0) {
                    b = m;
                } else {
                    a = m;
                }
            }
            hit.t = b;
            hit.q = ms_local(f, cam.xz + rd.xz * b);
            hit.h = (cam.y + rd.y * b - f.y0) / f.sy;
            hit.kind = 3;
            return hit;
        }
    }
    return hit;
}

// The plating at `q` (blocks) seen with a footprint of `fp` blocks a pixel: x = how much of the pixel a seam between
// plates covers (thin seams fade out into an average far off rather than shimmer), y = the plate's own random number,
// zw = the plate's size.
fn ms_plates(q: vec2<f32>, fp: f32) -> vec4<f32> {
    let h0 = fh21(floor(q / 48.0) + vec2<f32>(17.0, 3.0));
    let size = vec2<f32>(select(48.0, 24.0, h0 > 0.45), select(48.0, 24.0, h0 > 0.75));
    let c = floor(q / size);
    let fr = q - c * size;
    let e = min(min(fr.x, size.x - fr.x), min(fr.y, size.y - fr.y));
    let w = 0.45;
    let seam = (1.0 - smoothstep(w * 0.5, w + fp, e)) * min(1.0, 2.0 * w / max(fp, 1.0e-3));
    return vec4<f32>(seam, fh21(c * vec2<f32>(1.0, 1.7) + size * 0.37), size);
}

// A thin glowing line at distance `d` (blocks) from it, `w` wide, kept about a pixel wide (and dimmed to match) far off.
fn ms_line(d: f32, w: f32, fp: f32) -> f32 {
    let ww = max(w, fp);
    return exp(-pow(d / ww, 2.0)) * (w / ww);
}

// What the metal mirrors, looking along `r`: the land below (darker straight down, where the ship's own shadow lies),
// the bright haze at the horizon, the sun's glare off the land and the haze under it, and the sky. The sky's colour
// is taken mostly grey, so the metal reads as metal, not as blue.
fn ms_env(r: vec3<f32>, haze: vec3<f32>, sun: vec3<f32>, day: f32) -> vec3<f32> {
    let grey = mix(haze, vec3<f32>(luminance(haze)), 0.65);
    let ground = vec3<f32>(0.16, 0.17, 0.13) * (0.08 + 0.92 * day) * mix(0.35, 1.0, smoothstep(-0.75, -0.3, r.y));
    let e = mix(ground, grey * 1.1, smoothstep(-0.28, 0.0, r.y));
    let glare = vec3<f32>(1.0, 0.88, 0.7) * pow(max(dot(r, normalize(vec3<f32>(sun.x, -abs(sun.y), sun.z))), 0.0), 24.0) * 1.1 * day;
    return mix(e, grey * 0.9, smoothstep(0.0, 0.5, r.y)) + glare;
}

// The hull's colour where the ray hit it: dark metal mirroring the land and the sky (Fresnel: brighter the more
// glancing the look), each plate a little differently tilted, toned and rough, grimed along its seams; green seams,
// windows and lights. `lit` how lit up its seams are, `core` the gathering light under the eye, `beam` the beam,
// `focus` where they meet (camera-relative), `boost` how much its lights flare (while it is a blur), `wake` seconds
// since it stopped (its seams and windows come on in a cascade a beat after; its running lights are on all along),
// `eng` how bright its engines are.
fn ms_hull(h: MsHit, f: MsFrame, rd: vec3<f32>, time: f32, lit: f32, chase_on: f32, core: f32, beam: f32, focus: vec3<f32>,
           haze: vec3<f32>, day: f32, sun: vec3<f32>, boost: f32, wake: f32, eng: f32) -> vec3<f32> {
    let q = h.q;
    let pix = 2.0 / (frame.projection[1][1] * frame.resolution.y);
    let wall = h.kind == 3 || h.kind == 5 || h.kind == 7;
    let fp = h.t * pix / select(max(rd.y, 0.12), 0.6, wall);
    let X = rd * h.t;
    let green = vec3<f32>(0.12, 1.5, 0.3);
    // the cascade: from the stern to the bow in a quarter of a second, each light at its own moment in it
    let on_at = 0.35 + 0.25 * (q.x + MS_HL) / (2.0 * MS_HL) + 0.06 * fh21(floor(q / 23.0) + vec2<f32>(77.0, 1.0));
    let on = smoothstep(on_at, on_at + 0.05, wake);
    // a wave of light running along the seams towards the bow while it charges
    let chase = pow(0.5 + 0.5 * sin(q.x * 0.025 - time * 7.0), 6.0) * chase_on;
    let glow = (0.25 + 0.9 * lit + 1.6 * chase) * boost * on;
    var tone = 1.0;                       // how bright the metal is (plates, grime, recesses)
    var rough = 0.35;
    var nl = vec3<f32>(0.0, -1.0, 0.0);   // the surface's normal in the ship's frame (x along, y up, z across)
    var emit = vec3<f32>(0.0);
    if (h.kind <= 2) {
        // the decks: plates, their seams, fine machinery between, some plates set back into the hull
        let pl = ms_plates(q, fp);
        // each plate its own tilt and roughness
        let hv = vec3<f32>(pcg3d(bitcast<vec3<u32>>(vec3<i32>(vec2<i32>(floor(q / pl.zw)), 9)))) * (1.0 / 4294967295.0);
        nl = normalize(vec3<f32>((hv.x - 0.5) * 0.45, -1.0, (hv.y - 0.5) * 0.45));
        rough = 0.15 + 0.6 * hv.z;
        tone = (0.55 + 0.7 * pl.y) * mix(1.0, 0.25, pl.x) * select(select(1.1, 1.0, h.kind == 1), 0.85, h.kind == 0);
        // whole sections of it a shade lighter or darker, weathered
        tone = tone * (0.65 + 0.7 * gnoise2(q * 0.006 + vec2<f32>(3.1, 7.7)));
        let g = fh21(floor(q / 6.0) + vec2<f32>(pl.y * 91.0, 5.0));
        tone = tone * mix(1.0, 0.65 + 0.7 * g * g, saturate(2.0 - fp / 3.0));
        // grime: dark streaks trailing back from the seams, along the way it flies
        let seam_d = 12.0 - abs(fract(q.y / 24.0) - 0.5) * 24.0;
        let streak = smoothstep(0.45, 0.75, gnoise2(vec2<f32>(q.x * 0.015, q.y * 0.45)));
        tone = tone * (1.0 - 0.45 * exp(-seam_d / 2.5) * streak * saturate(2.0 - fp / 2.0));
        if (pl.y > 0.82) {
            // a plate set 4 blocks up: past its edge you see the side of the recess, inside it a darker grid
            let rdl = vec2<f32>(dot(rd.xz, f.ax), dot(rd.xz, f.sd));
            let qd = q + rdl * (4.0 / max(rd.y, 0.2));
            if (any(floor(qd / pl.zw) != floor(q / pl.zw))) {
                tone = tone * 0.3;
            } else {
                let gd = abs(fract(qd / 3.0) - 0.5) * 3.0;
                tone = tone * mix(0.45, 0.7, saturate(min(gd.x, gd.y) / max(fp, 0.4)));
                rough = 0.8;
            }
        } else if (pl.y > 0.6 && pl.y < 0.7) {
            // conduits running along the hull
            tone = tone * mix(1.0, 0.75 + 0.5 * smoothstep(0.15, 0.35, abs(fract(q.y / 2.5) - 0.5)), saturate(1.5 - fp));
        } else if (pl.y < 0.12) {
            // a row of intakes: dark slots across the plate
            let slot = step(abs(fract(q.x / 4.0) - 0.5), 0.3) * step(abs(fract(q.y / pl.w) - 0.5), 0.3);
            tone = tone * mix(1.0, 1.0 - 0.85 * slot, saturate(2.0 - fp / 1.5));
        }
        if (h.kind == 1 && abs(q.y) > 70.0) {
            // armour: the plating stepping up from the keel in overlapping layers, each lip catching the light and
            // throwing a shadow on the layer above it
            let lz = (abs(q.y) - 70.0) / 34.0;
            let fl = fract(lz);
            tone = tone * (0.85 + 0.3 * fh21(vec2<f32>(floor(lz), 61.0)));
            tone = tone * (1.0 - 0.5 * exp(-fl * 34.0 / 2.5)) + 0.9 * exp(-(1.0 - fl) * 34.0 / max(1.0, fp));
        }
        if (h.kind == 2) {
            // fields of radiator fins hanging across the hull: you see the side of each that faces you
            let fc = floor(q / vec2<f32>(80.0, 60.0));
            if (fh21(fc + vec2<f32>(13.0, 29.0)) > 0.62 && abs(q.x) < MS_HL - 120.0) {
                let rdl = dot(rd.xz, f.ax);
                let fin = smoothstep(0.3, 0.7, fract(q.x / 3.0 + 0.2 * sign(rdl)));
                tone = tone * mix(0.8, 0.45 + 0.7 * fin, saturate(1.6 - fp / 1.5));
                rough = 0.5;
            }
        }
        if (q.x > MS_HL - MS_TAPER - 30.0 && h.kind > 0) {
            // sensor arrays on the bow: domes, each mirroring the sky round it, a light blinking on some
            let sc = floor(q / 16.0);
            let sh = fh21(sc + vec2<f32>(5.0, 83.0));
            let dv = q - (sc + 0.5) * 16.0;
            let dd = length(dv);
            if (sh > 0.45 && dd < 5.0) {
                nl = normalize(vec3<f32>(dv.x / 5.0, -sqrt(max(1.0 - dd * dd / 25.0, 0.05)), dv.y / 5.0));
                tone = 1.3;
                rough = 0.1;
                emit = emit + vec3<f32>(0.4, 2.6, 0.5) * ms_line(dd, 0.6, fp) * step(0.75, sh) * step(0.6, fract(time * 0.7 + sh * 9.0));
            } else if (sh > 0.3 && dd < 6.0) {
                tone = tone * (0.4 + 0.6 * smoothstep(0.5, 1.0, abs(fract(dd / 2.0) - 0.5) * 2.0));
            }
        }
        if (h.h >= MS_TOP) {
            // (the roof, seen from above: the downfall's ship as it rolls)
            nl.y = -nl.y;
        }
        // the decks' edges bevelled, catching the light from round the side
        let edge = -ms_tier(q, h.kind);
        let bevel = (1.0 - smoothstep(0.0, 2.5 + fp, edge)) * select(1.0, 0.0, h.kind == 0 && ms_eye(q) < 2.0);
        tone = tone + 1.2 * bevel;
        rough = mix(rough, 0.1, bevel);
        // glowing seams: along the foot of the deck above, down both sides of the keel, ribs across
        var s = ms_line(abs(fract(q.x / 120.0 + 0.5) - 0.5) * 120.0, 0.5, fp) * 0.35 * step(0.4, fh21(vec2<f32>(floor(q.x / 120.0 + 0.5), floor(q.y / 70.0) + 40.0)));
        if (h.kind == 0) {
            s = s + ms_line(abs(abs(q.y) - 20.0), 0.5, fp) * 0.6;
        } else {
            s = s + ms_line(ms_tier(q, h.kind - 1) - 1.4, 0.6, fp) * 1.3;
        }
        emit = emit + green * s * glow;
        if (h.kind > 0) {
            // windows: rows of tiny lights in districts, lit and dark, like a city seen at night from far above
            let row = floor(q.y / 6.0);
            let district = fh21(vec2<f32>(row, floor(q.x / 90.0)) + vec2<f32>(3.0, 17.0));
            let wx = floor(q.x / 2.0);
            let wh = fh21(vec2<f32>(wx, row) + vec2<f32>(41.0, 5.0));
            if (district > 0.64 && wh > 0.72) {
                let d = length(q - vec2<f32>(wx * 2.0 + 1.0, row * 6.0 + 3.0));
                let flick = 0.6 + 0.4 * step(0.2, fract(wh * 13.0 + floor(time * 0.5) * 0.37));
                emit = emit + vec3<f32>(0.55, 1.5, 0.6) * ms_line(d, 0.45, fp) * flick * boost * on * 0.6;
            }
        }
        if (h.kind == 2) {
            // running lights down both long sides: deep green to port, bright to starboard, a white strobe; on all along
            let cx = floor(q.x / 40.0);
            let lx = cx * 40.0 + 20.0;
            let d = length(q - vec2<f32>(lx, sign(q.y) * (ms_half_w(lx) - 14.0)));
            let blink = step(0.82, fract(time * 0.9 - cx * 0.11));
            let rc = select(vec3<f32>(0.4, 2.6, 0.5), vec3<f32>(0.08, 1.1, 0.18), q.y > 0.0);
            emit = emit + mix(rc, vec3<f32>(3.5, 4.0, 3.5), blink) * ms_line(d, 1.3, fp) * (0.6 + 1.4 * blink) * boost;
        }
    } else if (h.kind == 4) {
        // the eye's ceiling: six emitters round the aperture the beam comes from
        let e = q - vec2<f32>(MS_EM_X, 0.0);
        let re = length(e);
        let ae = atan2(e.y, e.x);
        let sa = TAU / 6.0;
        let ke = floor(ae / sa + 0.5);
        let de = length(e - vec2<f32>(cos(ke * sa), sin(ke * sa)) * 30.0);
        let ribs = smoothstep(0.2, 0.6, abs(fract(ae / sa * 4.0) - 0.5) * 2.0);
        tone = 0.45 + 0.4 * ribs;
        rough = 0.5;
        let hot = mix(vec3<f32>(0.15, 1.8, 0.35), vec3<f32>(3.5, 5.0, 3.6), core);
        emit = emit + hot * ((1.0 - smoothstep(5.0, 5.0 + fp, de)) * (0.3 * on + 7.0 * core + 6.0 * beam) + exp(-de / 6.0) * (0.2 * on + 2.5 * core));
        emit = emit + vec3<f32>(4.5, 6.0, 4.5) * (1.0 - smoothstep(9.0, 9.0 + fp, re)) * (0.2 * on + 10.0 * core + 10.0 * beam);
        emit = emit + green * (ms_line(re - 18.0, 0.6, fp) + ms_line(re - 42.0, 0.8, fp)) * glow;
    } else if (h.kind == 6) {
        // the hangar's ceiling: a lit interior, rows of light strips, the dark shapes of craft docked under them
        let hq = q - MS_HANGAR.xy;
        let strip = ms_line(abs(fract(hq.y / 16.0 + 0.5) - 0.5) * 16.0, 1.2, fp);
        let docked = max(abs(fract(hq.x / 30.0) - 0.5) * 30.0 - 9.0, abs(fract(hq.y / 16.0) - 0.5) * 16.0 - 4.0);
        tone = 0.35 * (0.8 + 0.4 * fh21(floor(hq / 30.0)));
        rough = 0.7;
        let inner = vec3<f32>(0.8, 1.6, 0.9) * (0.25 + 1.2 * strip) * on;
        emit = emit + inner * select(1.0, 0.1, docked < 0.0);
    } else {
        // walls: their normal from the outline, decks every 5 blocks, rows of lit windows along them, ribs every 30;
        // the engines' bells on the walls facing aft
        var n2 = vec2<f32>(0.0);
        if (h.kind == 3) {
            let k = select(0, select(1, 2, h.h > MS_TIER_C), h.h > MS_TIER_B);
            n2 = vec2<f32>(ms_tier(q + vec2<f32>(1.0, 0.0), k) - ms_tier(q - vec2<f32>(1.0, 0.0), k),
                           ms_tier(q + vec2<f32>(0.0, 1.0), k) - ms_tier(q - vec2<f32>(0.0, 1.0), k));
        } else if (h.kind == 5) {
            n2 = vec2<f32>(MS_EM_X, 0.0) - q;
        } else {
            let hq = q - MS_HANGAR.xy;
            n2 = select(vec2<f32>(0.0, -sign(hq.y)), vec2<f32>(-sign(hq.x), 0.0), abs(hq.x) - MS_HANGAR.z > abs(hq.y) - MS_HANGAR.w);
        }
        n2 = n2 / max(length(n2), 1.0e-4);
        nl = vec3<f32>(n2.x, 0.0, n2.y);
        let u = select(dot(q, vec2<f32>(-n2.y, n2.x)), atan2(q.y, q.x - MS_EM_X) * MS_EYE_R, h.kind == 5);
        let deck = abs(fract(h.h / 5.0) - 0.5) * 5.0;
        let deck_l = mix(mix(0.45, 1.0, saturate((deck - 0.3) / max(fp * 0.5, 0.2))), 0.93, smoothstep(0.7, 2.2, fp));
        tone = 0.8 * deck_l * (0.75 + 0.4 * fh21(vec2<f32>(floor(u / 30.0), 9.0)));
        rough = 0.3 + 0.4 * fh21(vec2<f32>(floor(u / 30.0), 19.0));
        let wc = vec2<f32>(floor(u / 3.5), floor(h.h / 5.0));
        let wh = fh21(wc + vec2<f32>(3.0, 51.0));
        let win = step(select(0.88, 0.55, h.kind == 7), wh) * step(1.2, deck) * step(abs(fract(u / 3.5) - 0.5), 0.3);
        emit = emit + vec3<f32>(0.45, 1.5, 0.5) * win * saturate(1.6 - fp / 2.5) * boost * on * select(1.0, 2.0, h.kind == 7);
        emit = emit + green * ms_line(MS_TOP - h.h, 0.8, fp) * glow * select(0.0, 1.0, h.kind == 3);
        if (h.kind == 3 && n2.x > 0.8 && q.x > MS_HL - 4.0) {
            // the bow's blunt end: heavy ribs up it, a prow light along its middle
            let rib = abs(fract(q.y / 14.0) - 0.5) * 14.0;
            tone = tone * mix(1.0, 0.5 + 0.6 * smoothstep(1.0, 3.0, rib), saturate(2.0 - fp / 2.0));
            emit = emit + green * ms_line(abs(h.h - 75.0), 1.2, fp) * (0.4 + glow) * 1.5;
        }
        if (h.kind == 3 && n2.x < -0.8) {
            // the engines: big bells across the stern above, a row of smaller ones in the engine block below
            let big = h.h > MS_TIER_C;
            let pitch = select(50.0, 90.0, big);
            let r = select(14.0, 34.0, big);
            let zc = (floor(q.y / pitch) + 0.5) * pitch;
            let vc = select(14.0, 103.0, big);
            let d = length(vec2<f32>(q.y - zc, h.h - vc));
            if (abs(zc) < select(160.0, 200.0, big) && d < r * 1.3) {
                tone = tone * mix(1.0, 0.25, step(d, r));
                let bell = ms_line(d - r, 1.5, fp) * 1.5 + (1.0 - smoothstep(r * 0.2, r, d)) * 1.2;
                emit = emit + mix(vec3<f32>(0.2, 1.8, 0.4), vec3<f32>(3.0, 5.0, 3.2), saturate(eng - 1.0)) * bell * eng;
            }
        }
    }
    // the metal: it mirrors the land and the sky, sharply where a plate is smooth, blurred where it is rough, more
    // and more the more glancing the look; in sunlight its walls catch a hot glint of the sun
    let n = normalize(vec3<f32>(f.ax.x, 0.0, f.ax.y) * nl.x + vec3<f32>(0.0, nl.y, 0.0) + vec3<f32>(f.sd.x, 0.0, f.sd.y) * nl.z);
    let r = reflect(rd, n);
    let cosv = max(dot(-rd, n), 0.0);
    let fres = 0.45 + 0.55 * pow(1.0 - cosv, 5.0);
    let env = mix(ms_env(r, haze, sun, day), (mix(haze, vec3<f32>(luminance(haze)), 0.65) * 0.6 + vec3<f32>(0.08, 0.085, 0.07) * day) * 0.6, rough * 0.8);
    let sun_c = vec3<f32>(1.0, 0.92, 0.8) * 2.5 * day * step(0.0, sun.y);
    let glint = sun_c * pow(max(dot(r, sun), 0.0), mix(300.0, 20.0, rough)) * (1.0 - rough) * max(dot(n, sun), 0.0) * 4.0;
    let metal = vec3<f32>(0.42, 0.43, 0.44) * tone;
    var c = metal * (env * fres + glint) + metal * 0.04 * (haze + vec3<f32>(0.1) * day) * max(dot(n, sun), 0.0);
    // and the green light gathering under the eye, and the beam's
    let lf = X - focus;
    c = c + metal * ship_tint(vec3<f32>(0.4, 2.0, 0.6)) * (core * 0.8 + beam * 1.6) * 4000.0 / (dot(lf, lf) + 2500.0) * 0.3;
    // the air between: a light veil of the sky's blue, and its lights dimmed, which is what makes it look so far away
    let hz = 1.0 - exp(-h.t / 3000.0);
    return mix(c, haze * 0.6, hz * 0.35) + ship_tint(emit) * exp(-h.t / 3000.0);
}

// The air reacting to the mothership as it comes (the clouds stirring before it), as it stops (a pressure ripple
// running out through the cloud layer, `tr` seconds after) and just after (a shimmer of heat round its edges): seen only
// as the world bending, so it comes back as the offset of the picture at `uv`.
fn ms_air(uv: vec2<f32>, cam: vec3<f32>, p0: vec3<f32>, sky0: bool, stir: f32, tr: f32, wake: f32, base: MsFrame, f: MsFrame,
          time: f32, seed: f32, k: f32) -> vec2<f32> {
    var off = vec2<f32>(0.0);
    if (stir > 0.001 && !sky0 && abs(p0.y - CLOUD_Y - 2.0) < 6.0) {
        // before it comes the clouds start to stir, as if the air is being pushed aside
        let sw = vec2<f32>(gnoise2(p0.xz * 0.012 + vec2<f32>(time * 0.35, seed)), gnoise2(p0.xz * 0.012 + vec2<f32>(7.0, time * 0.3))) - 0.5;
        off = off + sw * 0.014 * stir * stir * k;
    }
    // the air reacting to it: a pressure ripple running out through the cloud layer and the air below it as it stops
    // (and again as it goes), seen only as the world bending, and a shimmer of heat round its edges for a second
    let rd0 = normalize(world_offset(uv, 0.5));
    if (tr > 0.0 && tr < 6.0 && abs(rd0.y) > 1.0e-3) {
        let t_cl = (CLOUD_Y - cam.y) / rd0.y;
        if (t_cl > 0.0 && (sky0 || t_cl < length(p0 - cam) + 40.0)) {
            let rr = length(cam.xz + rd0.xz * t_cl - base.c);
            let ripple = exp(-pow((rr - tr * 650.0) / (40.0 + tr * 15.0), 2.0)) * exp(-tr * 0.8);
            let pr = project_rel(vec3<f32>(base.c.x, CLOUD_Y, base.c.y) - cam);
            let rdir = uv - pr.xy;
            off = off + rdir / max(length(rdir), 1.0e-4) * ripple * 0.012 * pr.z * k;
        }
    }
    if (wake > 0.0 && wake < 1.2 && rd0.y > 1.0e-3 && cam.y < base.y0) {
        let qe = ms_local(f, cam.xz + rd0.xz * ((base.y0 + 20.0 - cam.y) / rd0.y));
        let m = exp(-pow(ms_tier(qe, 2) / 18.0, 2.0)) * (1.0 - wake / 1.2);
        if (m > 0.01) {
            let hw = vec2<f32>(gnoise2(uv * vec2<f32>(120.0, 60.0) + vec2<f32>(0.0, time * 6.0)), gnoise2(uv * vec2<f32>(120.0, 60.0) + vec2<f32>(17.0, time * 5.0))) - 0.5;
            off = off + hw * 0.006 * m * k;
        }
    }
    return off;
}

// The mothership's arrival in light: the point it unfolds out of, the warp streak it pulls out of, its exhaust
// streaming out behind it while it moves fast.
fn ms_arrival_fx(f: MsFrame, base: MsFrame, cam: vec3<f32>, rd: vec3<f32>, sky: bool, scene_len: f32, ta: f32, mode: i32, style: i32,
                 blurring: bool, present: bool, k: f32) -> vec3<f32> {
    var add = vec3<f32>(0.0);
    // the unfold: the point it bursts out of, a tiny bright star far off where it is coming from, swelling into it
    if (style == 1 && ta >= 0.0 && ta < MS_IN) {
        let pc = vec3<f32>(ms_world(f, vec2<f32>(0.0)).x, f.y0 + 40.0 * f.sy, ms_world(f, vec2<f32>(0.0)).y) - cam;
        let tp = dot(pc, rd);
        if (tp > 0.0 && (sky || tp < scene_len)) {
            let ang = length(pc - rd * tp) / tp;
            let born = pow(1.0 - f.sx, 1.5);
            add = add + (vec3<f32>(4.0, 6.0, 4.0) * exp(-pow(ang / 0.0025, 2.0)) + vec3<f32>(0.4, 1.6, 0.5) * exp(-ang / 0.012) * 0.5) * born * k;
        }
    }
    if (style == 2 && ta > -0.3 && ta < 0.06) {
        // the warp: the streak it comes in on, racing in along its path from far off and snapping into it
        let up = mode == 4;
        let head = MS_HL - 30000.0 * pow(saturate(-ta / 0.3), 2.0);
        let a2 = ms_world(base, vec2<f32>(select(head, 0.0, up), 0.0));
        let b2 = ms_world(base, vec2<f32>(select(head - 30000.0, 0.0, up), 0.0));
        let ya = base.y0 + select(30.0, MS_TOP - head + MS_HL, up);
        let q = ray_seg(rd, vec3<f32>(a2.x, ya, a2.y) - cam, vec3<f32>(b2.x, ya + select(0.0, 30000.0, up), b2.y) - cam);
        let w = max(3.0, q.y * 0.0015);
        let vis = select(1.0, 0.0, !sky && q.y > scene_len);
        add = add + vec3<f32>(1.2, 2.6, 1.5) * exp(-pow(q.x / w, 2.0)) * (3.0 / w) * 2.0 * smoothstep(-0.3, -0.1, ta) * (1.0 - smoothstep(0.0, 0.06, ta)) * vis * k;
    }
    if (blurring && present) {
        // its engines' exhaust streaming out behind it while it moves
        for (var j = 0; j < 5; j = j + 1) {
            let zc = (f32(j) - 2.0) * 90.0;
            let e0 = ms_world(f, vec2<f32>(-MS_HL, zc));
            let e1 = ms_world(f, vec2<f32>(-MS_HL - 260.0, zc));
            let q = ray_seg(rd, vec3<f32>(e0.x, f.y0 + 103.0 * f.sy, e0.y) - cam, vec3<f32>(e1.x, f.y0 + 103.0 * f.sy, e1.y) - cam);
            let w = max(16.0 + 30.0 * q.z, q.y * 0.0015);
            let vis = select(1.0, 0.0, !sky && q.y > scene_len);
            add = add + vec3<f32>(0.4, 2.2, 0.6) * exp(-pow(q.x / w, 2.0)) * (16.0 / w) * (1.0 - q.z) * 0.8 * vis * k;
        }
    }
    return ship_tint(add);
}

// The mothership's charge: its emitters' beams converging under the eye on `focus` (camera-relative), and the blinding
// point of light gathering there. `ship_t`: how far off the hull is along the view (the beams pass behind it).
fn ms_charge_fx(f: MsFrame, cam: vec3<f32>, rdb: vec3<f32>, focus: vec3<f32>, sky: bool, scene_len: f32, ship_t: f32, conv_env: f32,
                core_env: f32, present: bool, time: f32, k: f32) -> vec3<f32> {
    var add = vec3<f32>(0.0);
    // ---- the charge: the emitters' beams converging under the eye, a blinding point of light gathering there ----
    if (conv_env > 0.001 && present) {
        let rad = 30.0;
        for (var i = 0; i < 6; i = i + 1) {
            let a = f32(i) * TAU / 6.0;
            let ew = ms_world(f, vec2<f32>(MS_EM_X + cos(a) * rad, sin(a) * rad));
            let e3 = vec3<f32>(ew.x, f.y0 + MS_EYE_UP, ew.y) - cam;
            let q = ray_seg(rdb, e3, focus);
            let w = max(1.2 + 0.8 * core_env, q.y * 0.0012);
            let vis = select(1.0, 0.0, (!sky && q.y > scene_len) || q.y > ship_t + 1.0);
            let flick = 0.8 + 0.2 * sin(time * 40.0 + f32(i) * 2.1);
            add = add + (vec3<f32>(2.6, 4.8, 2.6) * exp(-pow(q.x / (w * 0.5), 2.0)) + vec3<f32>(0.15, 1.4, 0.3) * exp(-pow(q.x / (w * 2.5), 2.0)))
                * (1.2 / w) * conv_env * flick * vis * k;
        }
    }
    if (core_env > 0.001) {
        let tc = dot(focus, rdb);
        if (tc > 0.0) {
            let dc = length(focus - rdb * tc);
            let R = (1.0 + 3.5 * core_env) * (1.0 + 0.08 * sin(time * 33.0));
            let vis = select(1.0, 0.2, (!sky && tc > scene_len) || tc > ship_t + 2.0);
            add = add + (vec3<f32>(5.0, 6.0, 5.0) * exp(-pow(dc / R, 2.0)) + vec3<f32>(0.6, 2.6, 0.8) * exp(-dc / R) * 0.9 + vec3<f32>(0.12, 0.7, 0.2) * exp(-dc / (R * 5.0)) * 0.4) * core_env * vis * k;
        }
    }
    return ship_tint(add);
}

// [lasers pass only]
fn mothership(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();

    // ---- timeline -------------------------------------------------------------
    let ta = time - MS_ARRIVE;                                  // its own clock: 0 the instant it drops in
    let td = time - MS_LEAVE;                                   // 0 the instant it goes
    let present = ms_here(time);
    let here = f32(present);
    let stir = smoothstep(0.0, MS_ARRIVE, time) * f32(ta < 0.0);
    let charge = saturate((time - T_FIRE) / (MS_BEAM - T_FIRE));
    let lit = charge * (1.0 - smoothstep(MS_CUT, MS_LEAVE - 1.6, time)) + smoothstep(MS_LEAVE - 1.6, MS_LEAVE, time);
    let chase_on = charge * (1.0 - smoothstep(MS_BEAM, MS_HIT + 1.0, time));
    let conv_env = smoothstep(T_FIRE + 1.2, MS_BEAM - 0.3, time) * (1.0 - smoothstep(MS_CUT, MS_CUT + 0.4, time));
    let core_env = smoothstep(T_FIRE + 2.0, MS_BEAM, time) * (1.0 - smoothstep(MS_CUT, MS_CUT + 0.6, time));
    let beam_env = smoothstep(MS_BEAM, MS_BEAM + 0.04, time) * (1.0 - smoothstep(MS_CUT, MS_CUT + 0.3, time));
    let hit_t = time - MS_HIT;
    let landed = hit_t > 0.0;
    let flash = select(0.0, exp(-hit_t * 8.0), landed);
    let end_env = 1.0 - smoothstep(MS_END - 6.0, MS_END, time);
    let u_sw = ms_sweep(time);

    // ---- where the ship is: its eye over the target once it has stopped, pointing the way it came in ----
    // (the beam always sweeps away from the player, whichever way the ship came from)
    let ax = ms_axis();                                         // the way the beam sweeps
    let mode = approach();
    let right = vec2<f32>(-ax.y, ax.x);                         // the player's right, facing the target
    var base: MsFrame;
    base.ax = select(select(select(-ax, right, mode == 2), -right, mode == 3), ax, mode == 1);
    base.c = tgt.xz - base.ax * MS_EM_X;
    base.sd = vec2<f32>(-base.ax.y, base.ax.x);
    base.y0 = tgt.y + MS_H;
    base.shift = 0.0;
    base.sx = 1.0;
    base.sz = 1.0;
    base.sy = 1.0;
    base.px = 0.0;
    let style = arrival_style();
    let f = ms_frame(base, time, mode, style);
    let stop = ms_stop(style);
    let wake = ta - stop;                                       // since it stopped
    // the light on the land drops as its shadow lands, over a third of a second
    let land = smoothstep(stop, stop + 0.3, ta) * f32(td < MS_OUT);
    // a blur while it is moving fast: on its way in, and on its way out
    let arriving = ta >= 0.0 && ta < stop + MS_SHUTTER;
    let blurring = arriving || (td > 0.0 && td < MS_OUT + MS_SHUTTER);
    // its engines: low while it hangs there, blazing while it moves, gathering before it goes
    let eng = 0.35 + 2.6 * f32(blurring) + 1.5 * smoothstep(MS_LEAVE - 1.6, MS_LEAVE, time);
    let focus = vec3<f32>(tgt.x, base.y0 - MS_FOCUS, tgt.z) - cam;
    let gxz = tgt.xz + ax * TRENCH_L * u_sw;                    // where the beam is on the ground
    let G = vec3<f32>(gxz.x, tgt.y, gxz.y) - cam;

    // ---- the light and the sky ------------------------------------------------
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let haze = srgb_to_linear(saturate(frame.sky_color.rgb)) * 0.95 + vec3<f32>(0.01, 0.015, 0.03);

    // ---- the clouds stirring, the air rippling, heat haze (the camera's shake is the game's, scheduled in strike.rs) ----
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    let tr = select(ta - stop, td - MS_OUT * 0.5, td > 0.0);
    var off = ms_air(uv, cam, p0, sky0, stir, tr, wake, base, f, time, seed, k);
    let pF = project_rel(focus);
    let pG = project_rel(G);
    if (beam_env > 0.001 && pG.z > 0.0) {
        // the air boiling round the beam, and over where it touches down
        var m = exp(-length((uv - pG.xy) * vec2<f32>(aspect, 1.0)) / 0.05) * 1.5;
        if (pF.z > 0.0) {
            let a2 = pF.xy * vec2<f32>(aspect, 1.0);
            let ab2 = pG.xy * vec2<f32>(aspect, 1.0) - a2;
            let u2 = saturate(dot(uv * vec2<f32>(aspect, 1.0) - a2, ab2) / max(dot(ab2, ab2), 1.0e-6));
            let sdist = length(uv * vec2<f32>(aspect, 1.0) - a2 - ab2 * u2);
            m = m + exp(-pow(sdist / (0.012 + 0.02 * u2), 2.0));
        }
        if (m > 0.01) {
            let hw = vec2<f32>(gnoise2(uv * vec2<f32>(140.0, 50.0) + vec2<f32>(0.0, -time * 9.0)), gnoise2(uv * vec2<f32>(140.0, 50.0) + vec2<f32>(31.0, -time * 8.0))) - 0.5;
            off = off + hw * 0.004 * m * beam_env * k;
        }
    }
    let uv2 = clamp(uv + off, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene ------------------------------------------------------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let rdb = normalize(world_offset(uv, 0.5));                // not bent by the heat
    let P = cam + rel;
    let cloud = !sky && abs(P.y - CLOUD_Y - 2.0) < 6.0;
    let ca = flash * 0.02 * k;
    let ca_dir = (uv2 - vec2<f32>(0.5)) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b));
    // the light goes flat and grey as the sky darkens before it, and under it (it covers half the sky)
    let dim = clamp(1.0 - (0.12 * stir + 0.14 * land + 0.22 * charge * charge * (1.0 - f32(landed)) + 0.1 * beam_env) * k, 0.3, 1.0);
    col = col * dim;

    // ---- its shadow: the outline seen along the sun ----------------------------
    if (!sky && present && P.y < f.y0) {
        // (a low sun would throw it miles off: kept high, so it falls round the target)
        let ls = select(vec3<f32>(0.0, 1.0, 0.0), normalize(vec3<f32>(sun.x, max(sun.y, 0.6), sun.z)), sun.y > 0.0);
        let Q = P.xz + ls.xz * (f.y0 + MS_TIER_C * 0.5 - P.y) / ls.y;
        let pen = 4.0 + (f.y0 - P.y) * 0.012;
        let sh = 1.0 - smoothstep(-pen, pen, ms_tier(ms_local(f, Q), 2));
        col = col * (1.0 - sh * (0.6 * day + 0.15) * land * k);
    }
    var add = vec3<f32>(0.0);

    // ---- on the ground: the glow and dust under it, the beam's light, the crater and the trench molten ----
    if (!sky) {
        let rel2 = P.xz - tgt.xz;
        let r = length(rel2);
        let dy = P.y - tgt.y;
        // on the ground, or down in the crater and the trench: nothing up in the clouds
        let on_ground = 1.0 - smoothstep(25.0, 40.0, dy);
        let green = ship_tint(vec3<f32>(0.3, 1.8, 0.45));
        if (charge > 0.0 && hit_t < 0.5) {
            // charging: the ground under the eye lit, a ring closing in on the target, dust lifting off it
            let fade = 1.0 - smoothstep(0.0, 0.5, hit_t);
            let conv = mix(60.0, 5.0, pow(charge, 1.5));
            let g = exp(-r / 14.0) * charge * charge * 1.4 + exp(-pow((r - conv) / 1.2, 2.0)) * charge * 1.6;
            add = add + green * g * on_ground * fade * k;
            if (r < 50.0) {
                let dn = gfbm2(rel2 * 0.08 + vec2<f32>(time * 0.4, -time * 0.3));
                let dust = saturate(dn * 1.5 - 0.45) * charge * (1.0 - smoothstep(10.0, 45.0, r)) * on_ground * fade;
                col = mix(col, vec3<f32>(0.3, 0.26, 0.2) * dim, dust * 0.4 * k);
            }
        }
        // lit by the gathering light under the eye, and hard by the beam where it touches down
        let gr = length(P.xz - gxz);
        col = col + col * green * core_env * 0.6 / (1.0 + r * r / 40000.0) * on_ground * k;
        col = col + col * vec3<f32>(1.4, 2.0, 1.3) * beam_env * 1500.0 / (gr * gr + dy * dy + 150.0) * on_ground * k;
        if (beam_env > 0.001 && gr < 32.0) {
            // the splash where it touches down: white-hot, molten rock thrown out in streaks
            let ang = atan2(P.z - gxz.y, P.x - gxz.x);
            let st = gfbm2(vec2<f32>(ang * 3.0, gr * 0.15 - time * 3.0) + vec2<f32>(seed));
            let splash = exp(-gr / 4.0) * 1.5 + smoothstep(0.55, 0.85, st) * exp(-gr / 12.0);
            add = add + lava_ramp(0.55 + 0.5 * exp(-gr / 6.0)) * splash * beam_env * on_ground * 3.0 * k;
        }
        // the crater and the trench, molten where the beam has been, cooling over seconds; hottest deepest
        let along = dot(rel2, ax);
        let across = dot(rel2, vec2<f32>(-ax.y, ax.x));        // across the trench (not the ship: it may point any way)
        if (landed && along > -30.0 && along < TRENCH_L + 12.0 && abs(across) < 30.0) {
            let deep = saturate(-dy / 16.0);
            var heat = 0.0;
            let m_cr = 1.0 - smoothstep(14.0, 26.0, r);
            if (m_cr > 0.0) {
                heat = max(heat, (exp(-hit_t / 7.0) * 0.9 * (1.0 - 0.5 * r / 26.0) + deep * 0.5 * exp(-hit_t / 20.0)) * m_cr);
            }
            let swept = TRENCH_L * u_sw;
            if (along > 0.0 && along < swept + 3.0) {
                let age = max(time - ms_when(along / TRENCH_L), 0.0);
                let m_tr = (1.0 - smoothstep(5.0, 9.0, abs(across))) * (1.0 - smoothstep(swept, swept + 3.0, along));
                heat = max(heat, (exp(-age / 6.0) * 0.95 + deep * 0.5 * exp(-age / 18.0)) * m_tr);
            }
            if (heat > 0.01) {
                // all of it molten while it is fresh; as it cools a crust closes over it and only the cracks glow
                let n = gfbm2(rel2 * 0.16 + vec2<f32>(P.y * 0.3, seed));
                let veins = exp(-pow((n - 0.5) / 0.07, 2.0));
                let molten = mix(veins * 0.9, 1.0, heat * heat);
                let hh = heat * molten * (0.8 + 0.4 * gnoise2(rel2 * 0.9 + vec2<f32>(time * 0.2, P.y)));
                add = add + lava_ramp(hh) * smoothstep(0.03, 0.25, heat * molten) * on_ground * end_env * 2.4 * k;
                col = col * (1.0 - 0.6 * smoothstep(0.0, 0.3, heat) * (1.0 - molten) * on_ground);
            }
        }
    }

    // ---- the ship ---------------------------------------------------------------
    var ship_t = 1.0e9;
    if (present || blurring) {
        // while it moves fast it is averaged over the shutter, the moments jittered from pixel to pixel so the copies
        // melt into one smear, its lights drawn out into streaks; otherwise once. The snap is shot like film: its
        // arrival steps at 24 frames a second, each exposed for half a frame (a 180° shutter), so it never looks like
        // smooth animation
        let n = select(1, 12, blurring);
        let jit = select(0.0, ign(in.position.xy), blurring);
        let film = arriving && style == 0;
        let t_film = MS_ARRIVE + floor(ta / MS_SHUTTER) * MS_SHUTTER;
        var acc = vec3<f32>(0.0);
        var cover = 0.0;
        for (var i = 0; i < n; i = i + 1) {
            let fr = (f32(i) + jit) / f32(n);
            let ts = select(time - select(0.0, MS_SHUTTER * fr, blurring), t_film + MS_SHUTTER * 0.5 * fr, film);
            if (!ms_here(ts)) {
                continue;
            }
            let fi = ms_frame(base, ts, mode, style);
            let hit = ms_trace(fi, cam, rd);
            if (hit.kind < 0) {
                continue;
            }
            // behind the terrain it is hidden; behind a cloud it shows faintly through; far off it is lost in the air
            // behind a cloud: from under the cloud layer it shows faintly through it; from over it (where the clouds
            // are thin) it is solid, under the cloud's tint, the land never showing through it
            let over = cloud && cam.y > CLOUD_Y + 8.0;
            let vis = select(select(0.0, 0.3, cloud), 1.0, sky || hit.t < scene_len || over) * (1.0 - smoothstep(4000.0, 20000.0, hit.t));
            if (vis > 0.0) {
                var hc = ms_hull(hit, fi, rd, ts, lit, chase_on, core_env, beam_env, focus, haze, day, sun, select(1.0, 3.0, blurring), ts - MS_ARRIVE - stop, eng);
                if (over && hit.t > scene_len) {
                    hc = mix(hc, vec3<f32>(luminance(col)), 0.3);
                }
                var a = vis;
                if (style == 2 && ts < MS_LEAVE) {
                    // still pulling out of its streak: hardly there, its lights smeared out along it, brightest down its
                    // middle and towards the bow
                    let w = saturate((max(fi.sx, fi.sy) - 1.0) / 8.0);
                    let az = abs(hit.q.y) / max(ms_half_w(hit.q.x), 1.0);
                    let smear = (exp(-pow(az / 0.05, 2.0)) * 2.0 + pow(0.5 + 0.5 * cos(az * 40.0), 12.0) * 0.6 + 0.15)
                        * (0.4 + 0.6 * saturate((hit.q.x + MS_HL) / (2.0 * MS_HL)));
                    a = vis * (1.0 - 0.9 * w);
                    hc = hc * (1.0 - 0.9 * w) + ship_tint(vec3<f32>(1.2, 2.6, 1.5)) * smear * w;
                }
                acc = acc + hc * vis;
                cover = cover + a;
                ship_t = min(ship_t, hit.t);
            }
        }
        let a = cover / f32(n);
        col = col * (1.0 - a) + acc / f32(n);
        add = add * (1.0 - a);
        // (a smear of it, while it moves fast, hides what is behind it only where it covers most of the shutter)
        ship_t = select(1.0e9, ship_t, a > 0.5);
    }
    // everything drawn after the hull is hidden where the hull is in front of it: its distance is the scene's depth
    let scene_lh = min(scene_len, ship_t);
    let sky_h = sky && ship_t > 1.0e8;
    add = add + ms_arrival_fx(f, base, cam, rd, sky_h, scene_lh, ta, mode, style, blurring, present, k);
    if (wake > 1.0 && td < 0.0) {
        // small craft out round it once it has settled, tiny against it, each with its own lights
        for (var j = 0; j < 6; j = j + 1) {
            let fj = f32(j);
            let rad = 180.0 + 240.0 * fract(fj * 0.618034);
            let spd = (0.05 + 0.07 * fract(fj * 0.754878)) * select(-1.0, 1.0, j % 2 == 0);
            let ang = fj * 1.7 + (wake - 1.0) * spd;
            let lift = smoothstep(1.0, 4.0, wake);
            let pc2 = base.c + base.ax * cos(ang) * rad + base.sd * sin(ang) * rad * 0.5;
            let pc = vec3<f32>(pc2.x, base.y0 - 20.0 - (25.0 + 40.0 * fract(fj * 0.381966)) * lift, pc2.y) - cam;
            let tp = dot(pc, rd);
            if (tp > 0.0 && (sky_h || tp < scene_lh)) {
                let dpx = length(pc - rd * tp);
                let fpc = tp * 0.0012;
                col = mix(col, vec3<f32>(0.03, 0.03, 0.035), (1.0 - smoothstep(2.5, 2.5 + fpc, dpx)) * lift);
                let blink = step(0.7, fract(time * 1.3 + fj * 0.37));
                add = add + mix(vec3<f32>(0.4, 2.4, 0.6), vec3<f32>(3.0), blink) * ms_line(dpx, 0.6, fpc) * 2.0 * lift * k;
            }
        }
    }
    if (td > 0.0 && td < MS_OUT + 0.6) {
        // a faint streak where it went, gone in a moment (straight up for one that came from overhead)
        let up = mode == 4;
        let a2 = ms_world(base, vec2<f32>(select(MS_HL + 40.0, 0.0, up), 0.0));
        let b2 = ms_world(base, vec2<f32>(select(MS_FAR + MS_HL, 0.0, up), 0.0));
        let q = ray_seg(rd, vec3<f32>(a2.x, base.y0 + select(30.0, MS_TOP + 40.0, up), a2.y) - cam,
                        vec3<f32>(b2.x, base.y0 + select(30.0, MS_FAR, up), b2.y) - cam);
        let w = max(2.0, q.y * 0.0012);
        let vis = select(1.0, 0.0, !sky_h && q.y > scene_lh);
        add = add + vec3<f32>(0.5, 1.6, 0.6) * exp(-pow(q.x / w, 2.0)) * (2.0 / w) * 0.6 * smoothstep(0.08, 0.2, td) * exp(-max(td - MS_OUT, 0.0) * 5.0) * vis * k;
    }

    // ---- steam and smoke boiling up off the trench as it cools -------------------
    if (landed && end_env > 0.001) {
        let s0 = crel + vec3<f32>(0.0, 9.0, 0.0);
        let s1 = G + vec3<f32>(0.0, 9.0, 0.0);
        let q = ray_seg(rd, s0, s1);
        let along = q.z * TRENCH_L * u_sw;
        let age = max(time - select(MS_HIT, ms_when(along / TRENCH_L), u_sw > 0.0), 0.0);
        let W = 6.0 + 1.6 * age;
        if (q.x < W * 2.5) {
            let vis = select(1.0, 1.0 - smoothstep(scene_lh - 1.0, scene_lh + 1.0, q.y), !sky_h);
            let yq = cam.y + rd.y * q.y - tgt.y;
            let sn = gfbm2(vec2<f32>(along * 0.07 - time * 0.1, yq * 0.09 - time * 0.55 + seed));
            let dens = exp(-pow(q.x / W, 2.0)) * smoothstep(0.3, 2.0, age) * exp(-age / 12.0) * (0.25 + 1.1 * sn) * smoothstep(-2.0, 3.0, yq) * end_env;
            // dark smoke while it is fresh, lit orange from underneath, then pale steam
            let under = exp(-max(yq, 0.0) / 8.0) * exp(-age / 6.0);
            let pale = smoothstep(1.0, 8.0, age);
            let steam = mix(vec3<f32>(0.1, 0.09, 0.085), vec3<f32>(0.7, 0.7, 0.72), pale) * dim * (0.35 + 0.65 * day) * (0.65 + 0.5 * sn) + lava_ramp(0.5) * under * 0.5;
            col = mix(col, steam, saturate(dens * 0.85) * vis);
        }
    }

    add = add + ms_charge_fx(f, cam, rdb, focus, sky, scene_len, ship_t, conv_env, core_env, present, time, k);
    // the guide: a pencil-thin thread from the focus to the target in the last seconds before it fires
    if (charge > 0.6 && time < MS_HIT) {
        let q = ray_seg(rd, focus, crel);
        let w = max(0.12, q.y * 0.0008);
        let vis = select(1.0, 0.0, !sky_h && q.y > scene_lh + 0.5);
        add = add + vec3<f32>(0.7, 3.0, 0.9) * exp(-pow(q.x / w, 2.0)) * (0.12 / w) * smoothstep(0.6, 0.9, charge) * (0.7 + 0.3 * sin(time * 50.0)) * vis * k;
    }

    // ---- the beam: down from the focus to the ground, white-hot inside its sheaths ----
    if (beam_env > 0.001) {
        let gb = G - vec3<f32>(0.0, 18.0, 0.0);
        let q = ray_seg(rdb, focus, gb);
        let lenb = length(gb - focus);
        let along = q.z * lenb;
        let hgt = focus.y + cam.y + (gb.y - focus.y) * q.z - tgt.y;
        // it leaves the focus and is on the ground in a fifth of a second
        let head = saturate((time - MS_BEAM) / (MS_HIT - MS_BEAM));
        var rc = (1.9 + 0.3 * sin(time * 29.0) + 0.25 * sin(time * 47.0 + 1.0)) * (1.0 + 1.2 * exp(-max(hit_t, 0.0) * 2.5));
        rc = rc * (1.0 + 1.6 * exp(-max(hgt, 0.0) / 7.0)) * mix(0.45, 1.0, smoothstep(0.0, 0.25, q.z)) * k;
        let w = max(rc, q.y * 0.0012);
        let e = rc / w;
        let dd = q.x;
        if (dd < w * 40.0 && q.z <= head + 0.01) {
            let vis = select(1.0, 1.0 - smoothstep(scene_lh - 0.8, scene_lh + 0.8, q.y), !sky_h);
            let vis_mix = mix(0.1, 1.0, vis);
            let bdir = (gb - focus) / max(lenb, 1.0e-3);
            let e1 = normalize(cross(bdir, vec3<f32>(1.0, 0.0, 0.0)));
            let e2 = cross(bdir, e1);
            let ofs = rdb * q.y - (focus + (gb - focus) * q.z);
            let ang = atan2(dot(ofs, e2), dot(ofs, e1));
            let n1 = gnoise2(vec2<f32>(ang * 1.6, along * 0.05 - time * 16.0));
            let n2 = gnoise2(vec2<f32>(ang * 2.3 + 7.0, along * 0.11 - time * 23.0));
            // surges of brightness racing down it, and strands of plasma winding round it
            let pulse = pow(0.5 + 0.5 * sin(along * 0.04 - time * 55.0), 6.0);
            let strand = pow(0.5 + 0.5 * sin(ang * 3.0 + along * 0.12 - time * 20.0), 12.0) * exp(-pow((dd - w * 2.2) / (w * 0.6), 2.0));
            let core = exp(-pow(dd / (w * 0.55), 2.0));
            let inner = exp(-pow(dd / (w * 1.5), 2.0)) * (0.6 + 0.8 * n1);
            let outer = exp(-pow(dd / (w * 3.8), 2.0)) * (0.4 + 0.9 * n2);
            let halo = exp(-dd / (rc * 5.0));
            var b = (core * vec3<f32>(9.0, 10.0, 9.0) * (1.0 + 0.6 * pulse) + inner * vec3<f32>(0.35, 1.8, 0.5) * (1.0 + 1.2 * pulse)
                + outer * vec3<f32>(0.04, 0.45, 0.1) + strand * vec3<f32>(0.6, 2.8, 0.8) * 0.8) * e;
            // the head of it, blazing, on its way down
            b = b + vec3<f32>(8.0, 9.5, 8.0) * exp(-pow((q.z - head) * lenb / 6.0, 2.0)) * core * (1.0 - step(1.0, head));
            // behind the ground only its glow shows
            add = add + ship_tint(b * vis + halo * vec3<f32>(0.03, 0.18, 0.05) * vis_mix) * beam_env * k;
        }
        // the fireball where it touches down, boiling
        if (landed) {
            let cf = G + vec3<f32>(0.0, 3.5, 0.0);
            let tcp = dot(cf, rd);
            let Rf = (8.0 + 6.0 * exp(-hit_t * 2.0)) * (0.9 + 0.1 * sin(time * 13.0));
            if (tcp > 0.0) {
                let dc = length(cf - rd * tcp);
                if (dc < Rf * 4.0) {
                    let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
                    let hy = cross(hx, rd);
                    let on = rd * tcp - cf;
                    let ang = atan2(dot(on, hy), dot(on, hx));
                    let nz = gfbm2(vec2<f32>(ang * 1.3 + seed, dc / Rf * 2.0 - time * 2.5));
                    let fire = exp(-pow(dc / (Rf * (0.75 + 0.5 * nz)), 2.0));
                    let visf = select(1.0, smoothstep(tcp - Rf * 1.3, tcp - Rf * 0.2, scene_lh), !sky_h);
                    add = add + (lava_ramp(0.55 + 0.5 * fire) * fire * 3.5 + ship_tint(vec3<f32>(0.5, 2.0, 0.6)) * fire * fire * 1.5) * visf * beam_env * k;
                    add = add + vec3<f32>(1.6, 1.0, 0.6) * exp(-dc / Rf) * 0.25 * beam_env * visf * k;
                }
            }
        }
    }

    // ---- sparks and molten rock thrown out of the cut, and chunks of rock (dark) ----
    // (only for rays passing near where they can be: within reach of the stretch of trench cut in the last two seconds)
    let sp_a = tgt.xz + ax * TRENCH_L * ms_sweep(time - 2.0);
    let sp_q = ray_seg(rd, vec3<f32>(sp_a.x, tgt.y + 8.0, sp_a.y) - cam, G + vec3<f32>(0.0, 8.0, 0.0));
    if (landed && time < MS_CUT + 2.0 && sp_q.x < 50.0) {
        for (var j = 0; j < 24; j = j + 1) {
            // each one thrown again and again, from wherever the beam is then, a new way each time
            let fj = f32(j);
            let life = 1.1 + 0.9 * fract(fj * 0.618034);
            let ph = fract(fj * 0.754878) * life;
            let gen = floor((time + ph) / life);
            let tb = gen * life - ph;                               // when this one was thrown
            let a = time - tb;
            if (tb < MS_HIT || tb > MS_CUT) {
                continue;
            }
            let src = tgt.xz + ax * TRENCH_L * ms_sweep(tb);
            let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), u32(gen), u32(seed)))) * (1.0 / 4294967295.0);
            let h1 = hv.x;
            let h2 = hv.y;
            let h3 = hv.z;
            let az = h1 * TAU;
            let vh = 6.0 + 16.0 * h2;
            let vy = 12.0 + 18.0 * h3;
            let s3 = vec3<f32>(src.x, tgt.y + 1.0, src.y) - cam;
            let pa = s3 + vec3<f32>(cos(az) * vh * a, vy * a - 16.0 * a * a, sin(az) * vh * a);
            let a1 = max(a - 0.06, 0.0);
            let pb = s3 + vec3<f32>(cos(az) * vh * a1, vy * a1 - 16.0 * a1 * a1, sin(az) * vh * a1);
            if (pa.y + cam.y < tgt.y - 4.0) {
                continue;
            }
            let qj = ray_seg(rd, pa, pb);
            let vis = select(1.0, 1.0 - smoothstep(scene_lh - 0.4, scene_lh + 0.4, qj.y), !sky_h);
            if (j % 3 == 0) {
                let w = 0.25 + 0.3 * h2;
                col = mix(col, vec3<f32>(0.05, 0.04, 0.035) * dim, exp(-pow(qj.x / max(w, qj.y * 0.0012), 4.0)) * (w / max(w, qj.y * 0.0012)) * vis);
            } else {
                let w = max(0.25, qj.y * 0.0012);
                add = add + mix(vec3<f32>(4.0, 3.2, 2.2), vec3<f32>(2.6, 0.7, 0.12), saturate(a / life)) * exp(-pow(qj.x / w, 2.0)) * (0.25 / w) * (1.0 - a / life) * vis * k;
            }
        }
    }

    // ---- the lens: bloom round the focus and the beam's foot, a streak through it ----
    if (pF.z > 0.0 && core_env > 0.001) {
        let dd = (uv - pF.xy) * vec2<f32>(aspect, 1.0);
        add = add + ship_tint(vec3<f32>(0.6, 1.9, 0.7)) * core_env / (1.0 + dot(dd, dd) * 600.0) * 0.4 * k;
    }
    if (pG.z > 0.0 && beam_env > 0.001) {
        let dd = (uv - pG.xy) * vec2<f32>(aspect, 1.0);
        add = add + ship_tint(vec3<f32>(1.1, 1.8, 1.1)) * beam_env / (1.0 + dot(dd, dd) * 400.0) * 0.5 * k;
        // a short anamorphic streak through the beam's foot
        add = add + ship_tint(vec3<f32>(0.4, 2.3, 0.6)) * exp(-abs(dd.y) * 260.0) * exp(-abs(dd.x) * 6.0) * beam_env * 0.4 * k;
    }
    add = add + vec3<f32>(2.4, 2.9, 2.4) * flash * flash * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.25 * here + 0.2 * beam_env) * k);
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
// [end lasers pass only]

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    if (th_is(2.0) > 0.5) {
        return singularity(in);
    }
    if (th_is(3.0) > 0.5) {
        return meteor_storm(in);
    }
    if (th_is(4.0) > 0.5) {
        return mothership(in);
    }
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let tt = phase_time();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let anc = anchor_xz();
    let crel = tgt - cam;
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

    // ---- shockwave refraction (resample position; the camera's shake is the game's, scheduled in strike.rs) ----

    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    let r0 = length(p0.xz - tgt.xz);
    let rs = fire_t * 62.0;
    let shock_fade = select(0.0, exp(-fire_t * 0.55), fired);
    let shock_mask = select(0.0, exp(-pow((r0 - rs) / 3.5, 2.0)), fired && !sky0) * shock_fade;
    var shock_dir = uv - uvT;
    shock_dir = shock_dir / max(length(shock_dir), 1e-4);
    var uv2 = uv + shock_dir * shock_mask * 0.08 * k * pt.z;
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
