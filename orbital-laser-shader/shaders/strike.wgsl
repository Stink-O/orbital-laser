// Orbital laser strike. One composite pass; everything is anchored in the world by
// rebuilding each pixel's position from the depth buffer and the camera matrices.
//
// Themes (the `theme` option, set per strike by strike.py):
//   0 Plasma   the original: blue/magenta/green plasma, forked lightning, dark smoke
//   1 Inferno  a column of fire: ember storm, glowing ground cracks, black-red smoke
//   2 Void     a dark beam that tears a black hole: gravity lens, spiral arms, stars, desaturation
//   3 Godly    halo rings, giant feathered wings, pillars of light, a golden sigil, rising souls

override target_x: f32 = 0.0;
override target_y: f32 = 64.0;
override target_z: f32 = 0.0;
override loop_period: f32 = 24.0;
override intensity: f32 = 1.0;
override freeze_time: f32 = -1.0;
override swz: f32 = 0.0;
override seed: f32 = 0.0;
override theme: f32 = 0.0;
const looping: bool = false;

const TAU: f32 = 6.2831853;
const T_FIRE: f32 = 4.0;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
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

fn lava_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.02, 0.0, 0.0), vec3<f32>(0.7, 0.05, 0.0), smoothstep(0.0, 0.3, h));
    c = mix(c, vec3<f32>(1.0, 0.38, 0.02), smoothstep(0.25, 0.55, h));
    c = mix(c, vec3<f32>(1.0, 0.85, 0.35), smoothstep(0.5, 0.8, h));
    c = mix(c, vec3<f32>(1.0, 1.0, 1.0), smoothstep(0.8, 1.0, h));
    return c;
}

fn void_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.0, 0.0, 0.02), vec3<f32>(0.25, 0.03, 0.55), smoothstep(0.0, 0.35, h));
    c = mix(c, vec3<f32>(0.75, 0.25, 1.0), smoothstep(0.3, 0.65, h));
    c = mix(c, vec3<f32>(1.0, 0.9, 1.0), smoothstep(0.7, 1.0, h));
    return c;
}

fn gold_ramp(x: f32) -> vec3<f32> {
    let h = saturate(x);
    var c = mix(vec3<f32>(0.12, 0.05, 0.0), vec3<f32>(0.85, 0.45, 0.05), smoothstep(0.0, 0.3, h));
    c = mix(c, vec3<f32>(1.0, 0.82, 0.3), smoothstep(0.25, 0.6, h));
    c = mix(c, vec3<f32>(1.0, 0.98, 0.9), smoothstep(0.6, 1.0, h));
    return c;
}

// 1 when `theme` is i, else 0 (the option arrives as a float).
fn th_is(i: f32) -> f32 {
    return 1.0 - step(0.5, abs(theme - i));
}

fn pick4(a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a * th_is(0.0) + b * th_is(1.0) + c * th_is(2.0) + d * th_is(3.0);
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

// Soft capsule-ish line between two screen points: x = hot core, y = glow. Thinner towards the far end.
fn seg_soft(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, w: f32) -> vec2<f32> {
    let ab = b - a;
    let l2 = max(dot(ab, ab), 1.0e-8);
    let u = clamp(dot(p - a, ab) / l2, 0.0, 1.0);
    let d = length(p - (a + ab * u));
    let ww = w * (1.0 - 0.65 * u);
    return vec2<f32>(exp(-pow(d / ww, 2.0)), 1.0 / (1.0 + pow(d / (ww * 4.0), 2.0)));
}

// Drifting motes on a scrolling grid (embers, souls): brightness 0..1.
fn motes(uv: vec2<f32>, aspect: f32, time: f32, scale: f32, speed: f32, dens: f32, size: f32, sway: f32) -> f32 {
    let p = vec2<f32>(uv.x * aspect * scale, uv.y * scale + time * speed);
    let cell = floor(p);
    let h = hash21(cell);
    let h2 = hash21(cell + vec2<f32>(7.3, 1.9));
    let h3 = hash21(cell + vec2<f32>(2.1, 5.7));
    let c = vec2<f32>(0.5 + (h2 - 0.5) * 0.6 + sway * sin(time * 1.7 + h * 6.28), 0.5 + (h3 - 0.5) * 0.6);
    let f = fract(p) - c;
    return step(1.0 - dens, h) * exp(-dot(f, f) / (size * size)) * (0.65 + 0.35 * sin(time * 8.0 + h * 40.0));
}

fn stars(rd: vec3<f32>, time: f32) -> f32 {
    let s = vec2<f32>(atan2(rd.z, rd.x) * 30.0, asin(clamp(rd.y, -1.0, 1.0)) * 30.0);
    let c = floor(s);
    let f = fract(s) - 0.5;
    let h = hash21(c);
    return step(0.962, h) * exp(-dot(f, f) * 55.0) * (0.55 + 0.45 * sin(time * 3.0 + h * 50.0));
}

// Distance-based edge of one equilateral triangle (circumradius R) at polar (r, ang).
fn tri_line(r: f32, ang: f32, R: f32, w: f32) -> f32 {
    let sector = TAU / 3.0;
    let a = ang - floor(ang / sector + 0.5) * sector;
    let d = r * cos(a) - R * 0.5;
    return exp(-pow(d / w, 2.0)) * (1.0 - smoothstep(R * 0.98, R * 1.04, r));
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x * frame.resolution.w * 0.0 + frame.resolution.x / frame.resolution.y;
    let time = now();
    let tt = phase_time();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let dist_t = length(crel);

    // ---- timeline -------------------------------------------------------------
    let charging = select(0.0, saturate(tt / T_FIRE), tt < T_FIRE);
    let fire_t = tt - T_FIRE;
    let fired = fire_t > 0.0;
    let beam_env = smoothstep(0.0, 0.1, fire_t) * (1.0 - smoothstep(9.0, 11.0, fire_t));
    let crater_env = smoothstep(0.0, 0.8, fire_t) * (1.0 - smoothstep(10.0, 20.0, fire_t));
    let flash = select(0.0, exp(-fire_t * 9.0), fired);
    let reticle_env = max(charging, select(0.0, exp(-fire_t * 2.5), fired));
    let k = intensity;
    let pal = hash21(vec2<f32>(seed, 3.7));
    let sr1 = hash21(vec2<f32>(seed, 11.3));
    let sr2 = hash21(vec2<f32>(seed, 23.9));
    let surge = pow(vnoise(vec2<f32>(time * 1.9, seed * 13.0)), 2.5) * 2.2;
    let stutter = 1.0 - 0.4 * step(0.8, vnoise(vec2<f32>(time * 9.0, seed * 5.0)));
    let wobble = (vec2<f32>(vnoise(vec2<f32>(time * 2.3, seed)), vnoise(vec2<f32>(time * 2.1, seed * 2.0))) - 0.5) * 1.6 * surge;

    // ---- theme: which masks are on, and the palette every layer draws from -------
    let T0 = th_is(0.0);
    let T1 = th_is(1.0);
    let T2 = th_is(2.0);
    let T3 = th_is(3.0);
    let tint_pal = mix(vec3<f32>(0.25, 1.1, 3.8), vec3<f32>(3.4, 0.5, 2.6), step(0.34, pal));
    let tint_p = mix(tint_pal, vec3<f32>(0.5, 3.2, 0.9), step(0.67, pal));
    let tint_beam = pick4(tint_p, vec3<f32>(3.6, 1.0, 0.12), vec3<f32>(1.1, 0.25, 3.4), vec3<f32>(3.4, 2.6, 1.0));
    let tint_alt = pick4(tint_p.zxy, vec3<f32>(3.4, 1.7, 0.3), vec3<f32>(1.8, 0.9, 3.5), vec3<f32>(3.0, 2.8, 1.8));
    let ring_col = pick4(vec3<f32>(1.0, 0.75, 0.45), vec3<f32>(1.0, 0.42, 0.1), vec3<f32>(0.7, 0.3, 1.6), vec3<f32>(1.6, 1.3, 0.7));
    let tint_l_p = mix(mix(vec3<f32>(0.4, 0.45, 1.8), vec3<f32>(1.8, 0.4, 1.2), step(0.34, pal)), vec3<f32>(0.3, 1.8, 0.5), step(0.67, pal));
    let tint_l = pick4(tint_l_p, vec3<f32>(1.9, 0.7, 0.15), vec3<f32>(1.3, 0.35, 2.4), vec3<f32>(2.0, 1.7, 0.7));
    let bolt_core = pick4(vec3<f32>(0.85, 0.95, 1.0), vec3<f32>(1.0, 0.85, 0.6), vec3<f32>(0.9, 0.8, 1.0), vec3<f32>(1.0, 0.96, 0.8));
    let streak_col = pick4(vec3<f32>(0.3, 0.8, 2.6), vec3<f32>(2.6, 0.9, 0.2), vec3<f32>(1.2, 0.4, 2.8), vec3<f32>(2.8, 2.1, 0.8));
    let bloom_col = pick4(vec3<f32>(1.0, 0.7, 0.5), vec3<f32>(1.0, 0.55, 0.25), vec3<f32>(0.8, 0.5, 1.0), vec3<f32>(1.0, 0.9, 0.6));
    let ray_col = pick4(vec3<f32>(0.9, 0.6, 1.8), vec3<f32>(1.8, 0.7, 0.2), vec3<f32>(0.8, 0.4, 1.8), vec3<f32>(1.8, 1.4, 0.6));
    let flash_col = pick4(vec3<f32>(0.9, 0.95, 1.0), vec3<f32>(1.0, 0.8, 0.55), vec3<f32>(0.85, 0.75, 1.0), vec3<f32>(1.0, 0.95, 0.75));

    // ---- target on screen -----------------------------------------------------
    let pt = project_rel(crel);
    let uvT = pt.xy;

    // ---- camera shake and shockwave refraction (resample position) ------------
    let near_scale = 1.0 / (1.0 + dist_t / 28.0);
    let shake_amt = (beam_env * 0.8 + flash * 1.4 + (1.0 - smoothstep(0.0, 6.0, fire_t)) * f32(fired) * 0.5) * k * 0.012 * near_scale;
    let shake = (vec2<f32>(vnoise(vec2<f32>(time * 37.0, 1.0)), vnoise(vec2<f32>(time * 41.0, 7.0))) - 0.5) * 2.0 * shake_amt;

    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    let r0 = length(p0.xz - tgt.xz);
    let rs = fire_t * 40.0;
    let shock_fade = select(0.0, exp(-fire_t * 0.55), fired);
    let shock_mask = select(0.0, exp(-pow((r0 - rs) / 3.5, 2.0)), fired && !sky0) * shock_fade;
    var shock_dir = uv - uvT;
    shock_dir = shock_dir / max(length(shock_dir), 1e-4);
    var uv2 = uv + shake + shock_dir * shock_mask * 0.05 * k * pt.z;
    // heat haze around the beam / crater
    let haze = (beam_env + crater_env * 0.6) * k * exp(-length((uv - uvT) * vec2<f32>(aspect, 1.0)) * 4.0) * pt.z;
    uv2 = uv2 + vec2<f32>(sin(uv.y * 90.0 + time * 14.0), cos(uv.x * 70.0 - time * 11.0)) * 0.0025 * haze;
    // void: the picture is pulled in towards the hole
    let to_t = uvT - uv;
    uv2 = uv2 + to_t * exp(-length(to_t * vec2<f32>(aspect, 1.0)) * 2.2) * 0.2 * T2 * (beam_env + 0.25 * charging + 0.4 * crater_env) * k * pt.z;
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

    // ---- global grading: dim the world so the light reads -----------------------
    let dim = 1.0 - (0.45 * charging * charging + 0.4 * beam_env + 0.2 * crater_env) * k * mix(1.0, 0.3, T3);
    col = col * clamp(dim, 0.2, 1.0);
    // void: the world drains of colour
    col = mix(col, vec3<f32>(luminance(col)), saturate(0.65 * T2 * (charging * 0.5 + beam_env + 0.5 * crater_env) * k));
    if (sky) {
        let st = beam_env * k;
        let grad = pow(1.0 - uv2.y, 2.0);
        let sky_beam = pick4(vec3<f32>(0.04, 0.0, 0.1) + vec3<f32>(0.25, 0.0, 0.35) * grad,
                          vec3<f32>(0.22, 0.03, 0.0) + vec3<f32>(0.75, 0.2, 0.02) * grad,
                          vec3<f32>(0.0, 0.0, 0.015) + vec3<f32>(0.18, 0.04, 0.3) * grad,
                          vec3<f32>(0.9, 0.62, 0.3) + vec3<f32>(0.6, 0.45, 0.25) * grad);
        col = mix(col, sky_beam, st * mix(0.7, 0.8, T3));
        let charge_tint = pick4(vec3<f32>(0.5, 0.02, 0.02), vec3<f32>(0.55, 0.12, 0.0), vec3<f32>(0.2, 0.0, 0.4), vec3<f32>(0.6, 0.45, 0.15));
        col = col + charge_tint * charging * charging * k * 0.35 * (1.0 - uv2.y);
        col = col + vec3<f32>(0.8, 0.85, 1.0) * stars(rd, time) * T2 * (beam_env + 0.3 * charging + 0.5 * crater_env) * 2.2 * k;
    }

    var add = vec3<f32>(0.0);

    // ---- ground effects -------------------------------------------------------
    if (!sky) {
        let dxg = P.xz - tgt.xz;
        let r = length(dxg);
        let ang = atan2(dxg.y, dxg.x);
        let dy = P.y - tgt.y;
        let near_y = 1.0 / (1.0 + dy * dy / 40.0);

        // targeting reticle; the godly theme draws a golden sigil instead
        if (reticle_env > 0.001 || (T3 > 0.5 && crater_env > 0.001)) {
            let heat = charging;
            let rc_lo = pick4(vec3<f32>(1.0, 0.05, 0.03), vec3<f32>(1.0, 0.2, 0.0), vec3<f32>(0.5, 0.1, 1.0), vec3<f32>(1.0, 0.75, 0.2));
            let rc_hi = pick4(vec3<f32>(1.0, 0.9, 0.8), vec3<f32>(1.0, 0.8, 0.4), vec3<f32>(0.9, 0.8, 1.0), vec3<f32>(1.0, 1.0, 0.9));
            let rc = mix(rc_lo, rc_hi, heat * heat);
            if (T3 < 0.5) {
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
            } else {
                // the sigil: concentric rings, a rotating hexagram, a ring of runes, and petals at the centre
                let sg_env = max(reticle_env, crater_env * 0.8);
                let gr = mix(0.4, 1.0, smoothstep(0.0, 3.2, tt));
                let ra = ang + time * 0.12;
                var sig = exp(-pow((r - 6.0 * gr) / 0.18, 2.0)) + exp(-pow((r - 9.0 * gr) / 0.14, 2.0)) * 0.8;
                sig = sig + exp(-pow((r - 14.0 * gr) / 0.2, 2.0)) + exp(-pow((r - 20.0 * gr) / 0.16, 2.0)) * 0.9;
                sig = sig + exp(-pow((r - 24.0 * gr) / 0.3, 2.0));
                sig = sig + tri_line(r, ra, 20.0 * gr, 0.2) + tri_line(r, ra + 1.0471976, 20.0 * gr, 0.2);
                let rune_a = ang - time * 0.08;
                let rf = fract(rune_a / TAU * 40.0);
                let rune = step(0.45, hash21(vec2<f32>(floor(rune_a / TAU * 40.0), 3.0))) * step(0.25, rf) * step(rf, 0.75);
                sig = sig + rune * step(21.5 * gr, r) * (1.0 - step(23.2 * gr, r)) * 0.9;
                sig = sig + (1.0 - smoothstep(0.0, 0.09, abs(fract(ang / TAU * 12.0 - time * 0.05) - 0.5) * r * 0.08)) * (1.0 - smoothstep(5.0 * gr, 6.0 * gr, r)) * 0.6;
                add = add + rc * sig * sg_env * near_y * 2.4 * k;
            }
        }

        // molten crater: glow cylinder around the axis, hotter the deeper the surface
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
                add = add + (lava_ramp(heat) * (T0 + T1) + void_ramp(heat) * T2 + gold_ramp(heat) * T3) * mask * crater_env * 4.5 * k;
                // fake bore on flat ground: the floor falls away into white heat
                let bore = (1.0 - smoothstep(Rc * 0.15, Rc * 0.65, r)) * smoothstep(-2.0, 0.0, dy + 1.5) * (1.0 - smoothstep(0.0, 8.0, dy));
                col = col * (1.0 - bore * crater_env * 0.92);
                let bore_col = pick4(vec3<f32>(1.0, 0.8, 0.5), vec3<f32>(1.0, 0.55, 0.2), vec3<f32>(0.8, 0.5, 1.0), vec3<f32>(1.0, 0.95, 0.7));
                add = add + bore_col * bore * bore * crater_env * 2.2 * k;
            }
            // glowing cracks spreading across the ground (every theme but plasma)
            if (T0 < 0.5) {
                let reach_c = 3.0 + fire_t * 6.5;
                if (r < reach_c) {
                    let wob = fbm(vec2<f32>(ang * 3.0 + r * 0.12, r * 0.18 + seed));
                    let ca = fract(ang / TAU * 11.0 + (wob - 0.5) * 1.3);
                    let cdist = 0.5 - abs(ca - 0.5);
                    let thr = 0.16 * 11.0 / (TAU * max(r, 1.5));
                    let crack = (1.0 - smoothstep(thr * 0.4, thr, cdist)) * (1.0 - smoothstep(reach_c * 0.55, reach_c, r)) * smoothstep(1.5, 4.0, r);
                    let cc = pick4(vec3<f32>(0.0), vec3<f32>(1.0, 0.4, 0.05), vec3<f32>(0.7, 0.25, 1.4), vec3<f32>(1.3, 1.0, 0.45));
                    add = add + cc * crack * crater_env * near_y * 3.0 * k;
                }
            }
            // void: a black hole on the ground, with an accretion ring and spiral arms
            if (T2 > 0.5) {
                let Rv = 2.0 + 9.0 * smoothstep(0.0, 4.0, fire_t);
                let disk = (1.0 - smoothstep(Rv * 0.75, Rv, r)) * near_y;
                col = col * (1.0 - disk * crater_env * 0.97);
                let acc = exp(-pow((r - Rv) / 0.7, 2.0)) * near_y;
                let arm = pow(0.5 + 0.5 * sin(ang * 3.0 - 2.6 * log(max(r, 0.5)) + time * 2.5), 3.0) * step(Rv, r) * exp(-(r - Rv) / (Rv * 1.6)) * near_y;
                add = add + vec3<f32>(1.6, 0.6, 3.0) * (acc * 2.4 + arm * 0.9) * crater_env * k;
            }
            // random secondary shocks as the beam surges
            for (var q = 0; q < 4; q = q + 1) {
                let fq = f32(q);
                let tq0 = 1.3 + fq * 2.2 + 1.5 * hash21(vec2<f32>(seed, fq + 41.0));
                let dtq = fire_t - tq0;
                let rq = max(dtq, 0.0) * (24.0 + 20.0 * hash21(vec2<f32>(seed, fq + 7.0)));
                let ringq = exp(-pow((r - rq) / 1.2, 2.0)) * exp(-max(dtq, 0.0) * 0.8) * step(0.0, dtq);
                add = add + ring_col * 0.9 * ringq * near_y * 2.5 * k;
            }
            // shockwave ring: bright leading edge (a twelve-petal lotus for the godly theme)
            let rs_eff = rs * (1.0 + 0.07 * T3 * sin(12.0 * ang + time * 0.6));
            let edge = exp(-pow((r - rs_eff) / 1.7, 2.0)) * shock_fade * near_y;
            add = add + ring_col * edge * 4.5 * k;
            let rs_in = rs * 0.62 * (1.0 + 0.07 * sin(12.0 * ang + 3.1416 - time * 0.6));
            add = add + ring_col * exp(-pow((r - rs_in) / 1.2, 2.0)) * shock_fade * near_y * 3.0 * k * T3;
        }
    }

    // ---- the beam -------------------------------------------------------------
    let c2 = crel.xz + wobble;
    let v2 = rd.xz;
    let vv = dot(v2, v2);
    var t_ray = dist_t;
    var dist = length(c2);
    if (vv > 1.0e-5) {
        t_ray = dot(c2, v2) / vv;
        dist = length(c2 - v2 * t_ray);
    }
    if (t_ray > 0.0) {
        let y_p = cam.y + rd.y * t_ray;
        let off = v2 * t_ray - c2;
        let ang_b = atan2(off.y, off.x);
        let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, t_ray), !sky);
        let vis_mix = mix(0.22, 1.0, vis);
        let head = tgt.y + 800.0 * pow(1.0 - saturate(fire_t / 0.16), 2.0);
        let above = smoothstep(tgt.y - 1.5, tgt.y + 0.5, y_p) * select(1.0, smoothstep(head - 3.0, head + 3.0, y_p), fired);
        let n = fbm(vec2<f32>(ang_b * 2.5, y_p * 0.07 - time * 9.0));
        let n2 = fbm(vec2<f32>(ang_b * 2.2 + 11.0 + time * 0.8, y_p * 0.11 - time * 9.0));

        // thin red designator beam while charging
        let des = exp(-pow(dist / 0.07, 2.0)) * charging * (1.0 - f32(fired)) * smoothstep(tgt.y - 1.0, tgt.y + 0.5, y_p);
        add = add + pick4(vec3<f32>(1.0, 0.08, 0.04), vec3<f32>(1.0, 0.3, 0.02), vec3<f32>(0.5, 0.1, 1.0), vec3<f32>(1.0, 0.8, 0.3)) * des * vis * 2.5 * (0.7 + 0.3 * sin(time * 40.0));

        if (beam_env > 0.001) {
            let hgt = max(y_p - tgt.y, 0.0);
            let plume = 1.0 + 3.2 * exp(-hgt / 9.0);
            let rc = (0.9 + 1.1 * exp(-fire_t * 1.3) + 0.2 * sin(time * 23.0) + 0.7 * surge) * (0.85 + 0.45 * n) * k * plume;
            let lat = dist * sign(dot(off, vec2<f32>(-c2.y, c2.x)) + 1.0e-5);
            let core = exp(-pow(dist / (rc * 0.5), 2.0));
            let sheath = exp(-pow(dist / (rc * 2.0), 2.0));
            let halo = 1.0 / (1.0 + pow(dist / (rc * 6.0), 2.0));
            let pk = fbm(vec2<f32>(y_p * 0.06 - time * 7.0 + seed, ang_b * 0.9 + time * 0.7));
            let pulse = pow(smoothstep(0.38, 0.82, pk), 2.0) * (0.7 + 1.1 * surge);
            let plasma = tint_beam * (0.55 + 0.9 * n2) * (1.0 + 3.0 * pulse);
            let core_col = pick4(vec3<f32>(8.0, 8.0, 9.0), vec3<f32>(9.0, 6.0, 2.5), vec3<f32>(0.0), vec3<f32>(9.0, 8.0, 6.0));
            var b = (core * core_col * (0.85 + 0.5 * surge) + sheath * plasma + halo * tint_alt * 0.3) * above * stutter;
            // void: a dark core with a bright violet rim; the beam eats the light behind it
            let rim_v = exp(-pow((dist - rc * 0.55) / (rc * 0.2), 2.0)) * T2;
            b = b + vec3<f32>(3.5, 1.4, 8.0) * rim_v * above * stutter;
            col = col * (1.0 - core * T2 * above * beam_env * vis * 0.97);

            // twisting energy strands around the beam
            let spin = (6.0 + 10.0 * sr1) * select(-1.0, 1.0, sr2 > 0.5);
            let strand = pow(0.5 + 0.5 * sin(ang_b * 3.0 + y_p * 0.35 - time * spin), 10.0)
                + pow(0.5 + 0.5 * sin(ang_b * 2.0 - y_p * 0.5 + time * 9.0), 10.0);
            let band = exp(-pow((dist - rc * 1.5) / (rc * 0.45), 2.0));
            b = b + tint_alt * 0.8 * strand * band * above;

            add = add + b * beam_env * vis_mix;

            // sparks in beam space: lateral offset x height
            let cell = vec2<f32>(lat * 1.4, y_p * 0.9 - time * 14.0);
            let id = floor(cell);
            let f = fract(cell) - 0.5;
            let hsh = hash21(id);
            let spark = step(0.92, hsh) * exp(-dot(f, f) * 26.0) * (1.0 - smoothstep(rc * 1.2, rc * 9.0, abs(lat)));
            add = add + pick4(vec3<f32>(1.0, 0.75, 0.4), vec3<f32>(1.0, 0.6, 0.15), vec3<f32>(0.8, 0.5, 1.0), vec3<f32>(1.0, 0.95, 0.7)) * spark * 3.5 * beam_env * above * vis_mix * k;
        }
        // lingering column of embers after the beam shuts off
        let ember = crater_env * (1.0 - beam_env) * exp(-pow(dist / 4.0, 2.0)) * smoothstep(tgt.y, tgt.y + 3.0, y_p) * exp(-(y_p - tgt.y) / 30.0);
        let ecell = floor(vec2<f32>(ang_b * 3.0, y_p * 0.7 - time * 5.0));
        add = add + vec3<f32>(1.0, 0.4, 0.08) * step(0.82, hash21(ecell)) * ember * vis * 0.35 * k;

        // lit smoke plume: a dark column that billows out at its crown, glowing orange from the crater below
        let smoke_env = smoothstep(1.2, 4.5, fire_t) * (1.0 - smoothstep(15.0, 26.0, fire_t)) * f32(fired);
        if (smoke_env > 0.001) {
            // the plume stands on the fixed target axis: none of the beam's sway or surges
            let c2s = crel.xz;
            var t_s = dist_t;
            var dist_s = length(c2s);
            if (vv > 1.0e-5) {
                t_s = dot(c2s, v2) / vv;
                dist_s = length(c2s - v2 * t_s);
            }
            let y_s = cam.y + rd.y * t_s;
            let off_s = v2 * t_s - c2s;
            let vis_s = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, t_s), !sky);
            let h = max(y_s - tgt.y, 0.0);
            let top = (fire_t - 1.0) * 11.0;
            let crown = smoothstep(top - 30.0, top - 4.0, h) * (1.0 - smoothstep(top - 6.0, top + 4.0, h));
            let R = 3.5 + 0.2 * h + 13.0 * crown;
            let lat_s = dist_s * sign(dot(off_s, vec2<f32>(-c2s.y, c2s.x)) + 1.0e-5);
            let turb = fbm(vec2<f32>(lat_s * 0.16 + 3.0, h * 0.16 - time * 0.5 + seed));
            let turb2 = fbm(vec2<f32>(lat_s * 0.34 - 4.0, h * 0.34 - time * 0.9));
            let dens = exp(-pow(dist_s / (R * (0.75 + 0.5 * turb)), 2.0)) * (0.35 + 0.9 * turb2)
                * (1.0 - smoothstep(top - 5.0, top + 3.0, h)) * smoothstep(-1.0, 3.0, y_s - tgt.y);
            let a_s = smoothstep(0.16, 0.7, dens * 1.7) * 0.96 * smoke_env * vis_s * (select(0.0, 1.0, t_s > 0.0));
            let under = exp(-h / 9.0) * crater_env * (0.4 + 0.9 * turb);
            let rim = pow(saturate(1.0 - dist_s / (R * 1.1)), 0.6);
            let sm_lo = pick4(vec3<f32>(0.025, 0.024, 0.027), vec3<f32>(0.02, 0.008, 0.006), vec3<f32>(0.03, 0.015, 0.05), vec3<f32>(1.0, 0.9, 0.7));
            let sm_hi = pick4(vec3<f32>(0.44, 0.42, 0.43), vec3<f32>(0.28, 0.12, 0.06), vec3<f32>(0.22, 0.12, 0.35), vec3<f32>(1.6, 1.45, 1.1));
            let under_col = pick4(vec3<f32>(1.0, 0.33, 0.05), vec3<f32>(1.0, 0.3, 0.03), vec3<f32>(0.7, 0.25, 1.6), vec3<f32>(1.4, 1.0, 0.4));
            let smoke_col = mix(sm_lo, sm_hi, saturate(0.1 + 0.8 * turb2 * (0.35 + h / 80.0)) * (1.0 - 0.5 * rim)) + under_col * under * 1.5;
            col = mix(col, smoke_col, a_s);
        }
    }

    // ---- lightning: forked screen-space bolts rooted on the beam axis ----------
    if (beam_env > 0.001 && pt.z > 0.0) {
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
            let sb = project_rel(b3);
            if (sa.z < 0.0 || sb.z < 0.0) {
                continue;
            }
            let a2 = vec2<f32>(sa.x * aspect, sa.y);
            let b2 = vec2<f32>(sb.x * aspect, sb.y);
            let wid = 0.0026 * k;
            let m = bolt_line(pa, a2, b2, slot + fi * 11.0, slot, wid);
            var v = m;
            // two forks leaving the main bolt
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
            // hide bolts behind terrain
            let dA = length(a3);
            let dB = length(b3);
            let bolt_d = mix(dA, dB, m.z);
            let vis_b = select(1.0, 1.0 - smoothstep(bolt_d - 1.0, bolt_d + 2.0, scene_len) * 0.0 - (1.0 - smoothstep(bolt_d - 2.0, bolt_d + 0.5, scene_len)), !sky);
            let flick = 0.65 + 0.35 * hash21(vec2<f32>(floor(time * 60.0), fi));
            lit = lit + (bolt_core * v.x * 7.0 + tint_l * v.y * 0.9) * vis_b * flick * (0.7 + 0.6 * surge);
        }
        add = add + lit * beam_env;
    }

    // ---- inferno: a storm of embers and a wash of heat ---------------------------
    if (T1 > 0.5 && pt.z > 0.0) {
        let dd = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let near_t = exp(-length(dd) * 1.3);
        let env = (beam_env + 0.6 * crater_env + 0.2 * charging) * k;
        var em = motes(uv, aspect, time, 22.0, 2.4, 0.16, 0.2, 0.25) + motes(uv + vec2<f32>(0.31, 0.17), aspect, time, 38.0, 3.4, 0.14, 0.17, 0.3) * 0.8;
        em = em + motes(uv + vec2<f32>(0.7, 0.4), aspect, time, 12.0, 1.5, 0.12, 0.25, 0.2) * 1.2;
        add = add + vec3<f32>(1.0, 0.55, 0.14) * em * near_t * env * 2.4;
        add = add + vec3<f32>(0.5, 0.12, 0.0) * exp(-abs(uv.y - uvT.y) * 7.0) * exp(-abs(uv.x - uvT.x) * aspect * 1.4) * crater_env * 0.8 * k;
    }

    // ---- void: everything streaks inward ---------------------------------------
    if (T2 > 0.5 && pt.z > 0.0) {
        let dd = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let l = length(dd);
        let a_s = atan2(dd.y, dd.x);
        let wl = pow(fbm(vec2<f32>(a_s * 26.0, floor(time * 6.0) * 0.37 + seed)), 4.0) * 3.0;
        let infall = smoothstep(0.0, 0.6, l) * exp(-l * 2.4);
        add = add + vec3<f32>(0.7, 0.35, 1.6) * wl * infall * (beam_env + 0.3 * crater_env) * k;
    }

    // ---- godly: halo rings, wings, pillars, pulses, souls and rays --------------
    if (T3 > 0.5 && pt.z > 0.0) {
        let pa = vec2<f32>(uv.x * aspect, uv.y);
        let rightw = frame.inverse_view[0].xyz;
        let upw = frame.inverse_view[1].xyz;
        var holy = vec3<f32>(0.0);
        let gold = vec3<f32>(1.6, 1.2, 0.55);
        let white = vec3<f32>(1.6, 1.55, 1.3);
        let after = 1.0 - smoothstep(13.0, 21.0, fire_t) * f32(fired);

        // three halo rings stacked up the beam, turning in opposite directions
        for (var i = 0; i < 3; i = i + 1) {
            let fi = f32(i);
            let hh = 18.0 + 26.0 * fi + 2.0 * fi * fi;
            let rw = 14.0 + 11.0 * fi + 3.0 * fi * fi;
            let a3 = crel + vec3<f32>(0.0, hh, 0.0);
            let sa = project_rel(a3);
            if (sa.z < 0.0) {
                continue;
            }
            let sb = project_rel(a3 + rightw * rw);
            let rr = length((sb.xy - sa.xy) * vec2<f32>(aspect, 1.0));
            let dd = pa - vec2<f32>(sa.x * aspect, sa.y);
            let rad = length(dd);
            let an = atan2(dd.y, dd.x);
            let env_h = smoothstep(0.6 + 0.8 * fi, 1.8 + 0.8 * fi, tt) * after;
            let dirn = select(-1.0, 1.0, (i & 1) == 0);
            let w = 0.0035 + 0.0007 * fi;
            var ringv = exp(-pow((rad - rr) / w, 2.0)) * (0.5 + 0.5 * step(0.5, fract(an / TAU * 36.0 + time * 0.08 * dirn)));
            ringv = ringv + exp(-pow((rad - rr * 0.88) / (w * 0.7), 2.0));
            ringv = ringv + exp(-pow((rad - rr * 1.06) / (w * 0.6), 2.0)) * step(0.4, hash21(vec2<f32>(floor(an / TAU * 28.0 - time * 0.2 * dirn), fi)));
            ringv = ringv + step(0.92, fract(an / TAU * 72.0)) * step(rr * 0.88, rad) * step(rad, rr) * 0.6;
            let glowr = exp(-pow((rad - rr) / (w * 6.0), 2.0)) * 0.18;
            let vis_h = select(1.0, step(length(a3), scene_len), !sky);
            holy = holy + gold * (ringv + glowr) * env_h * vis_h;
        }

        // a pair of vast feathered wings unfolding from the beam
        let wing_env = smoothstep(0.2, 2.6, fire_t) * (1.0 - smoothstep(12.0, 20.0, fire_t)) * f32(fired);
        if (wing_env > 0.001) {
            let root3 = crel + vec3<f32>(0.0, 38.0, 0.0);
            let sr = project_rel(root3);
            if (sr.z > 0.0) {
                let r2 = vec2<f32>(sr.x * aspect, sr.y);
                let spread = smoothstep(0.2, 2.8, fire_t);
                for (var sd = 0; sd < 2; sd = sd + 1) {
                    let sgn = select(-1.0, 1.0, sd == 0);
                    for (var i = 0; i < 12; i = i + 1) {
                        let fi = f32(i) / 11.0;
                        let th = mix(-0.9, 0.95, fi) * (0.25 + 0.75 * spread) + 0.06 * sin(time * 1.5 + fi * 5.0);
                        let len_w = mix(60.0, 24.0, fi) * (0.92 + 0.08 * sin(fi * 13.0)) * (0.3 + 0.7 * spread);
                        let dirw = rightw * (sgn * cos(th)) + upw * sin(th);
                        let eb = project_rel(root3 + dirw * len_w);
                        if (eb.z < 0.0) {
                            continue;
                        }
                        let e2 = vec2<f32>(eb.x * aspect, eb.y);
                        let sgm = seg_soft(pa, r2, e2, 0.0042);
                        holy = holy + (white * sgm.x * 1.2 + gold * sgm.y * 0.35) * wing_env;
                        let eb2 = project_rel(root3 + (dirw + upw * 0.07) * len_w * 0.55 + upw * 1.6);
                        if (eb2.z > 0.0) {
                            let sg2 = seg_soft(pa, r2, vec2<f32>(eb2.x * aspect, eb2.y), 0.0034);
                            holy = holy + (white * sg2.x * 0.7 + gold * sg2.y * 0.25) * wing_env;
                        }
                    }
                }
            }
        }

        // eight pillars of light around the beam, striking one after another
        if (vv > 1.0e-5) {
            for (var i = 0; i < 8; i = i + 1) {
                let fi = f32(i);
                let pang = fi * TAU / 8.0 + time * 0.05;
                let cpil = crel.xz + vec2<f32>(cos(pang), sin(pang)) * 12.0;
                let tp = dot(cpil, v2) / vv;
                if (tp > 0.0) {
                    let dp = length(cpil - v2 * tp);
                    let yp = cam.y + rd.y * tp;
                    let envp = smoothstep(0.25 * fi + 0.2, 0.25 * fi + 0.7, fire_t) * (1.0 - smoothstep(9.0, 12.0, fire_t)) * f32(fired);
                    let visp = select(1.0, 1.0 - smoothstep(scene_len - 0.6, scene_len + 0.6, tp), !sky);
                    let abp = smoothstep(tgt.y - 1.0, tgt.y + 1.0, yp);
                    let prof = exp(-pow(dp / 0.45, 2.0)) * 3.0 + exp(-pow(dp / 1.8, 2.0)) * 0.7;
                    holy = holy + vec3<f32>(1.5, 1.35, 0.9) * prof * envp * visp * abp;
                }
            }
        }

        // divine pulses ripple out from the impact, souls drift up, golden rays fan out
        let dd = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let l = length(dd);
        for (var i = 0; i < 3; i = i + 1) {
            let ph = fract((time - T_FIRE) / 1.9 + f32(i) / 3.0);
            holy = holy + vec3<f32>(1.6, 1.3, 0.7) * exp(-pow((l - ph * 1.1) / 0.012, 2.0)) * (1.0 - ph) * (1.0 - ph) * 0.9 * step(0.0, fire_t) * beam_env;
        }
        let souls = motes(uv, aspect, time, 9.0, 0.45, 0.2, 0.28, 0.35) + motes(uv + vec2<f32>(0.4, 0.2), aspect, time, 15.0, 0.7, 0.18, 0.22, 0.4) * 0.8;
        holy = holy + vec3<f32>(1.5, 1.2, 0.6) * souls * exp(-l * 0.9) * (beam_env + crater_env * 0.8 + 0.15 * charging);
        let a_s = atan2(dd.y, dd.x);
        let gray = pow(fbm(vec2<f32>(a_s * 5.0 + 3.0, time * 0.4)), 3.0) * 2.4;
        holy = holy + vec3<f32>(1.8, 1.4, 0.7) * gray * exp(-l * 3.0) * (beam_env * 0.7 + flash * 1.2);
        add = add + holy * k;
    }

    // ---- lens streak and flash at the target ---------------------------------
    if (pt.z > 0.0) {
        let dd = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let streak = exp(-abs(dd.y) * 260.0) * exp(-abs(dd.x) * 3.2);
        let bloom = 1.0 / (1.0 + dot(dd, dd) * 220.0);
        add = add + streak_col * streak * beam_env * 0.9 * k;
        add = add + bloom_col * bloom * (beam_env * 0.6 + flash * 0.8) * k;
    }
    if (pt.z > 0.0) {
        let dd2 = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let ang_s = atan2(dd2.y, dd2.x);
        let ray = pow(fbm(vec2<f32>(ang_s * 7.0 + 3.0, time * 0.7)), 3.0) * 2.0;
        add = add + ray_col * ray * exp(-length(dd2) * 6.0) * (beam_env * 0.5 + flash * 1.2) * k;
    }
    add = add + flash_col * (flash * flash * 0.9 + T3 * 0.5 * exp(-fire_t * 2.5) * f32(fired)) * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    let tint_lo = pick4(vec3<f32>(1.0, 0.45, 0.35), vec3<f32>(1.0, 0.3, 0.1), vec3<f32>(0.4, 0.1, 0.8), vec3<f32>(1.0, 0.8, 0.3));
    let tint_hi = pick4(vec3<f32>(0.5, 0.2, 1.0), vec3<f32>(1.0, 0.35, 0.05), vec3<f32>(0.35, 0.1, 0.8), vec3<f32>(1.0, 0.85, 0.4));
    let tint = tint_lo * charging * 0.12 + tint_hi * beam_env * 0.07;
    outc = outc * (1.0 - smoothstep(0.35, 1.0, vg) * (0.15 + 0.35 * (charging + beam_env) * 0.5) * k * mix(1.0, 0.4, T3)) + tint * smoothstep(0.3, 1.0, vg) * k;
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
