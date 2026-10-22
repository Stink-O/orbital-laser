// Orbital laser strike. One composite pass; everything is anchored in the world by
// rebuilding each pixel's position from the depth buffer and the camera matrices, or by
// tracing the view ray against shapes placed in the world (planes, cylinders, a volume).
// Nothing is painted flat on the screen except the lens: bloom, a streak, the flash.
//
// Lasers (the `theme` option, set per strike by strike.py):
//   0 Plasma   a raging plasma beam, forked lightning, a churning fireball, a smoke plume
//   1 Godly    the clouds part, a calm pillar of light comes down, halo rings and wings stand
//              in the sky, six pillars of light land round a golden sigil, a dome of light

override target_x: f32 = 0.0;
override target_y: f32 = 64.0;
override target_z: f32 = 0.0;
override anchor_x: f32 = 0.5;     // centre of the hit block: the world sigil and pillars are laid out round it
override anchor_z: f32 = 0.5;
override wing_a: f32 = 0.0;       // godly: the wings face along this angle in the xz plane (towards whoever fired)
override loop_period: f32 = 24.0;
override intensity: f32 = 1.0;
override freeze_time: f32 = -1.0;
override swz: f32 = 0.0;
override seed: f32 = 0.0;
override theme: f32 = 0.0;
const looping: bool = false;

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
    return 1.0 - step(0.5, abs(theme - i));
}

fn pick2(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return a * th_is(0.0) + b * th_is(1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

fn target_pos() -> vec3<f32> {
    var v = vec3<f32>(0.0);
    v.x = target_x;
    v.y = target_y;
    v.z = target_z;
    return v;
}

fn anchor_xz() -> vec2<f32> {
    var v = vec2<f32>(0.0);
    v.x = anchor_x;
    v.y = anchor_z;
    return v;
}

fn wing_dirs() -> vec4<f32> {
    // xy: the wings' facing (towards the shooter), zw: the span direction, both in the xz plane
    let c = cos(wing_a);
    let s = sin(wing_a);
    return vec4<f32>(c, s, -s, c);
}

fn now() -> f32 {
    let t0 = frame.time.x;
    return t0 + step(0.0, freeze_time) * (freeze_time - t0);
}

fn phase_time() -> f32 {
    let t = now();
    if (looping) {
        return t - floor(t / loop_period) * loop_period;
    }
    return t;
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

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
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
    let k = intensity;
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
    if (swz > 1.5 && swz < 2.5) {
        return vec4<f32>(vec3<f32>(tt / loop_period), 1.0);
    }
    let srgb = linear_to_srgb(outc);
    if (swz > 2.5) {
        // video capture: luma in red, alternating chroma in green (a screenshot loses the blue channel)
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    let pick = vec3<f32>(srgb.b);
    let odd = step(0.5, fract(frame.time.x * 2.3));
    return vec4<f32>(mix(srgb, pick, step(0.5, swz) * odd), 1.0);
}
