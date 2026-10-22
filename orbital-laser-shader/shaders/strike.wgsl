// Orbital laser strike. One composite pass; everything is anchored in the world by
// rebuilding each pixel's position from the depth buffer and the camera matrices.

override target_x: f32 = 0.0;
override target_y: f32 = 64.0;
override target_z: f32 = 0.0;
override loop_period: f32 = 24.0;
override intensity: f32 = 1.0;
override freeze_time: f32 = -1.0;
override swz: f32 = 0.0;
override seed: f32 = 0.0;
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
    let dim = 1.0 - (0.45 * charging * charging + 0.4 * beam_env + 0.2 * crater_env) * k;
    col = col * clamp(dim, 0.2, 1.0);
    if (sky) {
        let void_t = beam_env * k;
        col = mix(col, vec3<f32>(0.04, 0.0, 0.1) + vec3<f32>(0.25, 0.0, 0.35) * pow(1.0 - uv2.y, 2.0), void_t * 0.7);
        col = col + vec3<f32>(0.5, 0.02, 0.02) * charging * charging * k * 0.35 * (1.0 - uv2.y);
    }

    var add = vec3<f32>(0.0);

    // ---- ground effects -------------------------------------------------------
    if (!sky) {
        let dxg = P.xz - tgt.xz;
        let r = length(dxg);
        let ang = atan2(dxg.y, dxg.x);
        let dy = P.y - tgt.y;
        let near_y = 1.0 / (1.0 + dy * dy / 40.0);

        // targeting reticle
        if (reticle_env > 0.001) {
            let heat = charging;
            let rc = mix(vec3<f32>(1.0, 0.05, 0.03), vec3<f32>(1.0, 0.9, 0.8), heat * heat);
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
                add = add + lava_ramp(heat) * mask * crater_env * 4.5 * k;
                // fake bore on flat ground: the floor falls away into white heat
                let bore = (1.0 - smoothstep(Rc * 0.15, Rc * 0.65, r)) * smoothstep(-2.0, 0.0, dy + 1.5) * (1.0 - smoothstep(0.0, 8.0, dy));
                col = col * (1.0 - bore * crater_env * 0.92);
                add = add + vec3<f32>(1.0, 0.8, 0.5) * bore * bore * crater_env * 2.2 * k;
            }
            // random secondary shocks as the beam surges
            for (var q = 0; q < 4; q = q + 1) {
                let fq = f32(q);
                let tq0 = 1.3 + fq * 2.2 + 1.5 * hash21(vec2<f32>(seed, fq + 41.0));
                let dtq = fire_t - tq0;
                let rq = max(dtq, 0.0) * (24.0 + 20.0 * hash21(vec2<f32>(seed, fq + 7.0)));
                let ringq = exp(-pow((r - rq) / 1.2, 2.0)) * exp(-max(dtq, 0.0) * 0.8) * step(0.0, dtq);
                add = add + vec3<f32>(1.0, 0.6, 0.3) * ringq * near_y * 2.5 * k;
            }
            // shockwave ring: bright leading edge
            let edge = exp(-pow((r - rs) / 1.7, 2.0)) * shock_fade * near_y;
            add = add + vec3<f32>(1.0, 0.75, 0.45) * edge * 4.5 * k;
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
        add = add + vec3<f32>(1.0, 0.08, 0.04) * des * vis * 2.5 * (0.7 + 0.3 * sin(time * 40.0));

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
            let tint_a = mix(vec3<f32>(0.25, 1.1, 3.8), vec3<f32>(3.4, 0.5, 2.6), step(0.34, pal));
            let tint = mix(tint_a, vec3<f32>(0.5, 3.2, 0.9), step(0.67, pal));
            let plasma = tint * (0.55 + 0.9 * n2) * (1.0 + 3.0 * pulse);
            var b = (core * vec3<f32>(8.0, 8.0, 9.0) * (0.85 + 0.5 * surge) + sheath * plasma + halo * tint.zxy * 0.3) * above * stutter;

            // twisting energy strands around the beam
            let spin = (6.0 + 10.0 * sr1) * select(-1.0, 1.0, sr2 > 0.5);
            let strand = pow(0.5 + 0.5 * sin(ang_b * 3.0 + y_p * 0.35 - time * spin), 10.0)
                + pow(0.5 + 0.5 * sin(ang_b * 2.0 - y_p * 0.5 + time * 9.0), 10.0);
            let band = exp(-pow((dist - rc * 1.5) / (rc * 0.45), 2.0));
            b = b + tint.zxy * 0.8 * strand * band * above;

            add = add + b * beam_env * vis_mix;

            // sparks in beam space: lateral offset x height
            let cell = vec2<f32>(lat * 1.4, y_p * 0.9 - time * 14.0);
            let id = floor(cell);
            let f = fract(cell) - 0.5;
            let hsh = hash21(id);
            let spark = step(0.92, hsh) * exp(-dot(f, f) * 26.0) * (1.0 - smoothstep(rc * 1.2, rc * 9.0, abs(lat)));
            add = add + vec3<f32>(1.0, 0.75, 0.4) * spark * 3.5 * beam_env * above * vis_mix * k;
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
            let smoke_col = mix(vec3<f32>(0.025, 0.024, 0.027), vec3<f32>(0.44, 0.42, 0.43), saturate(0.1 + 0.8 * turb2 * (0.35 + h / 80.0)) * (1.0 - 0.5 * rim))
                + vec3<f32>(1.0, 0.33, 0.05) * under * 1.5;
            col = mix(col, smoke_col, a_s);
        }
    }

    // ---- lightning: forked screen-space bolts rooted on the beam axis ----------
    if (beam_env > 0.001 && pt.z > 0.0) {
        let pa = vec2<f32>(uv.x * aspect, uv.y);
        var lit = vec3<f32>(0.0);
        let tint_l = mix(mix(vec3<f32>(0.4, 0.45, 1.8), vec3<f32>(1.8, 0.4, 1.2), step(0.34, pal)), vec3<f32>(0.3, 1.8, 0.5), step(0.67, pal));
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
            lit = lit + (vec3<f32>(0.85, 0.95, 1.0) * v.x * 7.0 + tint_l * v.y * 0.9) * vis_b * flick * (0.7 + 0.6 * surge);
        }
        add = add + lit * beam_env;
    }

    // ---- lens streak and flash at the target ---------------------------------
    if (pt.z > 0.0) {
        let dd = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let streak = exp(-abs(dd.y) * 260.0) * exp(-abs(dd.x) * 3.2);
        let bloom = 1.0 / (1.0 + dot(dd, dd) * 220.0);
        add = add + vec3<f32>(0.3, 0.8, 2.6) * streak * beam_env * 0.9 * k;
        add = add + vec3<f32>(1.0, 0.7, 0.5) * bloom * (beam_env * 0.6 + flash * 0.8) * k;
    }
    if (pt.z > 0.0) {
        let dd2 = (uv - uvT) * vec2<f32>(aspect, 1.0);
        let ang_s = atan2(dd2.y, dd2.x);
        let ray = pow(fbm(vec2<f32>(ang_s * 7.0 + 3.0, time * 0.7)), 3.0) * 2.0;
        add = add + vec3<f32>(0.9, 0.6, 1.8) * ray * exp(-length(dd2) * 6.0) * (beam_env * 0.5 + flash * 1.2) * k;
    }
    add = add + vec3<f32>(0.9, 0.95, 1.0) * flash * flash * 0.9 * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    let tint = vec3<f32>(1.0, 0.45, 0.35) * charging * 0.12 + vec3<f32>(0.5, 0.2, 1.0) * beam_env * 0.07;
    outc = outc * (1.0 - smoothstep(0.35, 1.0, vg) * (0.15 + 0.35 * (charging + beam_env) * 0.5) * k) + tint * smoothstep(0.3, 1.0, vg) * k;
    outc = aces(outc * 0.9);
    if (swz > 1.5) {
        return vec4<f32>(vec3<f32>(tt / loop_period), 1.0);
    }
    let srgb = linear_to_srgb(outc);
    let pick = vec3<f32>(srgb.b);
    let odd = step(0.5, fract(frame.time.x * 2.3));
    return vec4<f32>(mix(srgb, pick, step(0.5, swz) * odd), 1.0);
}
