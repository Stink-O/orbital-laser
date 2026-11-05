// Orbital Laser's post pass for the Fold (laser 14). The mod builds it from shaders/strike.wgsl up to its fs_main less the
// other lasers' own functions, followed by this file, and sets it for a fold strike only. Validate with
// tools/check-shader.sh.

// ---- laser 14: the fold -------------------------------------------------------------------------------------------
// The world's bending, its creases, its tears and its colours aren't here: the land's own vertices and pixels go through
// shaders/fold_warp.wgsl. This pass draws what is not the world: the droplet (its fall, its stop, its meld), the void and
// its stars where the land has left, the point, the one flash, and the dust of the slams.
// strike/fold.rs plans the sounds and the land: keep the FD_* in step with its and fold_warp.wgsl's.
const FD_STOP: f32 = 3.4;          // the droplet stops dead
const FD_HANG: f32 = 3.9;          // it has hung still; it lowers
const FD_TOUCH: f32 = 6.0;         // it touches the land
const FD_MELD: f32 = 7.2;          // it has gone in
const FD_FOLD: f32 = 19.0;
const FD_SEAL: f32 = 31.0;
const FD_CRUSH: f32 = 35.0;
const FD_BEAT: f32 = 37.5;
const FD_REL: f32 = 38.7;          // the bloom
const FD_SLAM0: f32 = 39.8;
const FD_SLAM4: f32 = 43.1;
const FD_FALL: f32 = 3000.0;       // how high it starts over the target
const FD_LIFT: f32 = 46.0;         // FW_LIFT

fn fd_ss(a: f32, b: f32, x: f32) -> f32 { return smoothstep(a, b, x); }
fn fd_sample(uv: vec2<f32>) -> vec3<f32> {
    return srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}
// The void (fw_stars in fold_warp.wgsl: the same sky through a tear and round the world).
fn fd_stars(dir: vec3<f32>) -> vec3<f32> {
    let c = floor(dir * 300.0);
    let q = fract((c.xy + c.z * 37.7) * vec2<f32>(0.1031, 0.1137));
    let d = dot(q, q.yx + 33.33);
    let h = fract((q.x + d) * (q.y + d));
    let s = select(0.0, (h - 0.99) / 0.01, h > 0.99);
    let glow = 0.5 + 0.5 * sin(dir.x * 4.0 + dir.y * 3.0 + dir.z * 5.0);
    return mix(vec3<f32>(0.006, 0.005, 0.016), vec3<f32>(0.03, 0.012, 0.05), glow * glow) + vec3<f32>(0.8, 0.82, 1.0) * s * s;
}
fn fd_ring(i: i32) -> f32 {
    switch i {
        case 0: { return 44.0; }
        case 1: { return 104.0; }
        case 2: { return 176.0; }
        case 3: { return 290.0; }
        default: { return 480.0; }
    }
}
fn fd_slam(i: i32) -> f32 {
    switch i {
        case 4: { return 39.8; }
        case 3: { return 40.6; }
        case 2: { return 41.4; }
        case 1: { return 42.2; }
        default: { return 43.1; }
    }
}

// ---- the droplet: a bead of liquid metal with twelve fine creases round its lower half, the mandala in small --------------
struct FdDrop { R: f32, stop_h: f32, h: f32, sx: f32, sy: f32, tail: f32 }
fn fd_drop(t: f32, dist: f32) -> FdDrop {
    let R = clamp(dist * 0.05, 5.0, 15.0);
    let stop_h = R * 1.3 + 7.0;
    var h = stop_h;
    var sx = 1.0;
    var sy = 1.0;
    var tail = 0.0;
    if (t < FD_STOP) {
        let u = 1.0 - t / FD_STOP;
        h = stop_h + FD_FALL * pow(u, 2.6);
        tail = 1.0;
        sy = 1.25;
        sx = 0.9;
    } else if (t < FD_HANG) {
        h = stop_h;
    } else if (t < FD_TOUCH) {
        let u = (t - FD_HANG) / (FD_TOUCH - FD_HANG);
        h = mix(stop_h, R * 0.92, u * u * (3.0 - 2.0 * u));
    } else {
        // (melding: settling into a thin mirror on the land, spreading a little, then sunk in)
        let u = clamp((t - FD_TOUCH) / (FD_MELD - FD_TOUCH), 0.0, 1.0);
        let e = u * u * (3.0 - 2.0 * u);
        sy = mix(1.0, 0.03, e);
        sx = mix(1.0, 2.1, e * (2.0 - e)) * (1.0 - fd_ss(0.72, 1.0, u));
        h = R * 0.92 * sy;
    }
    return FdDrop(R, stop_h, h, max(sx, 0.001), sy, tail);
}
fn fd_sdf(p: vec3<f32>, d: FdDrop) -> f32 {
    let q = vec3<f32>(p.x / d.sx, p.y / d.sy, p.z / d.sx);
    let a = atan2(q.z, q.x);
    let l = length(q);
    let u = q.y / max(l, 0.001);
    // (the creases: cut into its lower half, fading out at the equator and the pole; the tail drawn up as it falls)
    let lower = fd_ss(0.1, -0.35, u) * fd_ss(-1.0, -0.8, u);
    let cr = pow(abs(cos(a * 6.0)), 26.0);
    let tail = d.tail * fd_ss(0.1, 1.0, u) * 0.75;
    return (l - d.R * (1.0 + tail - 0.05 * cr * lower)) * min(d.sx, d.sy);
}
fn fd_normal(p: vec3<f32>, d: FdDrop) -> vec3<f32> {
    let e = 0.02 * d.R;
    let k = vec2<f32>(1.0, -1.0);
    return normalize(k.xyy * fd_sdf(p + k.xyy * e, d) + k.yyx * fd_sdf(p + k.yyx * e, d) + k.yxy * fd_sdf(p + k.yxy * e, d) + k.xxx * fd_sdf(p + k.xxx * e, d));
}
// What a chrome surface sees: the sky, a hard dark line at the horizon, the land, the sun as a hard bright point.
fn fd_env(dir: vec3<f32>, sun: vec3<f32>) -> vec3<f32> {
    let y = dir.y;
    let sky = mix(vec3<f32>(0.95, 1.0, 1.12), vec3<f32>(0.1, 0.2, 0.46), pow(clamp(y, 0.0, 1.0), 0.55));
    let ground = mix(vec3<f32>(0.2, 0.17, 0.13), vec3<f32>(0.035, 0.035, 0.04), pow(clamp(-y, 0.0, 1.0), 0.4));
    var c = select(ground, sky, y > 0.0);
    c = c * (1.0 - 0.95 * exp(-y * y * 2600.0));
    let s = max(dot(dir, sun), 0.0);
    return c + vec3<f32>(9.0, 8.6, 8.0) * pow(s, 1400.0) + vec3<f32>(0.5, 0.48, 0.44) * pow(s, 40.0);
}
// The droplet over the picture (`col` so far, `far` how far the scene is along this ray).
fn fd_droplet(colIn: vec3<f32>, t: f32, v: vec3<f32>, C: vec3<f32>, d: FdDrop, far: f32, uv: vec2<f32>, aspect: f32) -> vec3<f32> {
    var col = colIn;
    let cd = dot(C, v);
    let miss = length(C - v * cd);
    let q = project_rel(C);
    let hi = fd_ss(FD_STOP - 2.6, FD_STOP - 0.2, t);
    // ---- the fire and the trail ----------------------------------------------------------------------------------------
    if (t < FD_STOP + 2.6) {
        // (the ray's nearest point to the fall's line, straight up through the droplet)
        let u = vec3<f32>(0.0, 1.0, 0.0);
        let b = dot(v, u);
        let den = max(1.0 - b * b, 0.001);
        let s = max((cd - dot(C, u) * b) / den, 0.0);
        let y = (dot(v * s, u) - C.y);
        let dr = length(v * s - (C + u * y));
        if (s < far) {
            let w0 = d.R * (1.0 + 0.4 * hi);
            let after = max(t - FD_STOP, 0.0);
            // (the trail's fire goes on when the droplet stops: it comes down past it and is gone in half a second)
            let drop_y = y + after * 520.0;
            let len = (180.0 + 420.0 * hi);
            let along = clamp(drop_y / len, 0.0, 1.0);
            let on = fd_ss(0.0, 0.03, drop_y / len + 0.02) * (1.0 - fd_ss(0.05, 0.55, after));
            let wf = w0 * (0.9 + 2.6 * along);
            // (split round the droplet once it has stopped)
            let hollow = select(1.0, fd_ss(d.R * 0.9, d.R * 1.4, dr), after > 0.0 && abs(y) < d.R * 2.5);
            let turb = 0.55 + 0.9 * vnoise(vec2<f32>(y * 0.05 + t * 34.0, atan2((v * s - C).z, (v * s - C).x) * 2.0));
            let fire = exp(-pow(dr / wf, 2.0)) * on * turb * hollow * (1.0 - along) * hi;
            let hot = mix(vec3<f32>(1.5, 1.15, 0.85), mix(vec3<f32>(1.3, 0.42, 0.07), vec3<f32>(0.28, 0.035, 0.01), along), fd_ss(0.0, 0.22, along));
            // (smoke: a dark rope above it, left hanging in the sky, thinning)
            let age = max(t - (FD_STOP * (1.0 - pow(max(y, 0.0) / FD_FALL, 1.0 / 2.6))), 0.0);
            let sw = d.R * 1.1 + 4.0 * age + 2.0 * sqrt(max(y, 0.0)) * 0.1;
            let sn = 0.6 + 0.8 * vnoise(vec2<f32>(y * 0.018, atan2((v * s - C).z, (v * s - C).x) * 1.5 + 3.0));
            let smoke = exp(-pow(dr / sw, 2.0)) * fd_ss(0.0, 26.0, y) * sn * 0.75 * d.tail * fd_ss(0.1, 1.2, t) + exp(-pow(dr / sw, 2.0)) * fd_ss(0.0, 26.0, y) * sn * 0.75 * (1.0 - d.tail) * (1.0 - fd_ss(0.0, 2.4, after));
            col = mix(col, vec3<f32>(0.1, 0.095, 0.1), clamp(smoke, 0.0, 0.85));
            col = col + hot * fire;
        }
    }
    // ---- the glint: from far up a star, for as long as it is smaller than a few pixels ------------------------------------
    if (q.z > 0.0 && t < FD_MELD) {
        let dd = length((uv - q.xy) * vec2<f32>(aspect, 1.0));
        let dp = (uv - q.xy) * vec2<f32>(aspect, 1.0);
        let ang = d.R / max(length(C), 1.0);
        let small = 1.0 - fd_ss(0.002, 0.012, ang);
        let tw = 0.85 + 0.15 * sin(t * 37.0);
        let star = exp(-dd / 0.0024) * 2.4 + exp(-abs(dp.y) / 0.0016) * exp(-abs(dp.x) / 0.05) * 1.1 + exp(-abs(dp.x) / 0.0016) * exp(-abs(dp.y) / 0.03) * 0.7;
        let fall = select(0.0, 1.0, t < FD_STOP);
        // (and one hard star off its top at the stop, gone in the same half second)
        let stopped = select(0.0, exp(-(t - FD_STOP) * 5.0), t >= FD_STOP);
        col = col + vec3<f32>(1.0, 0.96, 0.9) * star * (small * tw * fall + stopped * 0.8);
    }
    // ---- a steady soft halo round it while it hangs, so it can be found on a small screen, and no flicker in it ------------
    if (q.z > 0.0 && t >= FD_STOP && t < FD_TOUCH + 0.6) {
        let dh = length((uv - q.xy) * vec2<f32>(aspect, 1.0));
        col = col + vec3<f32>(0.9, 0.95, 1.05) * exp(-dh / 0.016) * 0.28 * (1.0 - fd_ss(FD_TOUCH - 0.2, FD_TOUCH + 0.6, t));
    }
    // ---- the metal --------------------------------------------------------------------------------------------------------
    if (miss < d.R * 2.6 * max(d.sx, 1.0) && cd > 0.0) {
        var s = max(cd - d.R * 2.8 * max(d.sx, 1.0), 0.05);
        var hit = false;
        for (var i = 0; i < 40; i += 1) {
            let e = fd_sdf(v * s - C, d);
            if (e < 0.004 * d.R) {
                hit = true;
                break;
            }
            s += e * 0.8;
            if (s > cd + d.R * 3.2 * max(d.sx, 1.0)) {
                break;
            }
        }
        if (hit && s < far + 0.4) {
            let p = v * s - C;
            let n = fd_normal(p, d);
            let r = reflect(v, n);
            var c = fd_env(r, normalize(frame.sun.xyz));
            // (the real land in it, where the reflection can be read off the picture)
            let ro = project_rel(v * s + r * 90.0);
            if (ro.z > 0.0 && ro.x > 0.0 && ro.x < 1.0 && ro.y > 0.0 && ro.y < 1.0 && r.y < 0.15) {
                c = mix(c, fd_sample(ro.xy) * 1.1, 0.6);
            }
            let fres = pow(1.0 - max(dot(-v, n), 0.0), 4.0);
            col = c * vec3<f32>(0.9, 0.93, 0.98) * (0.86 + 0.5 * fres);
            // (the sheath's heat on it as it falls)
            col = col + vec3<f32>(3.4, 1.3, 0.35) * fd_ss(0.0, -1.0, n.y) * hi * d.tail;
        }
    }
    return col;
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let t = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let res = frame.resolution.xy;
    let aspect = res.x / res.y;
    let me = frame.mod_params[3].xyz;
    let dist = length(me.xz - tgt.xz);
    let rb = clamp(dist * 0.56, 60.0, 150.0);
    let gq = (tgt - cam) - camera_rest();
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let off = world_offset(uv, select(d0, 0.5, sky0));
    let v = normalize(off);
    let far = select(length(off), 1.0e7, sky0);

    // ---- the bloom's jolt: the picture pulled about the point, its colours pulled apart -------------------------------------
    let pt = project_rel(gq + vec3<f32>(0.0, rb + FD_LIFT, 0.0));
    let centre = select(vec2<f32>(0.5), pt.xy, pt.z > 0.0);
    let blast = fd_ss(FD_REL - 0.02, FD_REL + 0.03, t) * (1.0 - fd_ss(FD_REL + 0.1, FD_REL + 0.9, t));
    var col: vec3<f32>;
    if (blast > 0.002) {
        let d = uv - centre;
        let j = blast * 0.07;
        col = vec3<f32>(fd_sample(centre + d * (1.0 - j * 1.3)).r, fd_sample(centre + d * (1.0 - j)).g, fd_sample(centre + d * (1.0 - j * 0.7)).b);
    } else {
        col = fd_sample(uv);
    }

    // ---- the void: the sky going out as the land closes, and under the land where it has left ------------------------------
    if (sky0 && t > FD_FOLD - 0.5) {
        let dark = fd_ss(FD_FOLD + 3.0, FD_SEAL - 1.0, t) * (1.0 - fd_ss(FD_REL + 0.6, FD_SLAM4 + 0.4, t));
        let under = fd_ss(0.03, -0.015, v.y) * fd_ss(FD_FOLD, FD_FOLD + 1.2, t) * (1.0 - fd_ss(FD_SLAM0 - 0.2, FD_SLAM4 + 0.2, t));
        col = mix(col, fd_stars(v), max(dark, under));
    }

    // ---- the droplet -------------------------------------------------------------------------------------------------------
    if (t < FD_MELD + 2.8) {
        let d = fd_drop(t, dist);
        // (its shadow on the land, closing up as it comes down)
        if (!sky0 && t >= FD_STOP && t < FD_MELD) {
            let P = off - gq;
            let sr = d.R * (1.6 + 0.06 * d.h);
            let shadow = exp(-dot(P.xz, P.xz) / (sr * sr)) * 0.62 * exp(-abs(P.y) / 12.0) * (1.0 - fd_ss(FD_TOUCH + 0.3, FD_MELD, t));
            col = col * (1.0 - shadow);
        }
        let C = gq + vec3<f32>(0.0, d.h, 0.0);
        col = fd_droplet(col, t, v, C, d, far, uv, aspect);
    }

    // ---- the point, in the dark, drawing in and holding -----------------------------------------------------------------
    let dd = length((uv - pt.xy) * vec2<f32>(aspect, 1.0));
    if (t > FD_BEAT - 0.5 && t < FD_REL + 0.15 && pt.z > 0.0) {
        let on = fd_ss(FD_BEAT - 0.5, FD_BEAT, t);
        let g = 0.0028;
        col = col + vec3<f32>(0.94, 0.9, 1.0) * (exp(-dd / g) * 2.6 + exp(-dd / (g * 7.0)) * 0.35) * on;
    }

    // ---- the bloom: the one flash, out of the point, gone in half a second --------------------------------------------------
    let since = t - FD_REL;
    if (since > -0.02 && since < 1.2) {
        let flash = exp(-max(since, 0.0) * 6.0);
        col = mix(col, vec3<f32>(1.0, 0.97, 1.02) * 1.4, flash * exp(-dd * 1.5 / (0.3 + 3.2 * max(since, 0.0))));
    }

    // ---- the slams: a ring of dust running out from each ring as it lands ---------------------------------------------------
    if (!sky0 && t > FD_SLAM0 && t < FD_SLAM4 + 3.0) {
        let P = off + (cam + camera_rest() - tgt);
        let dpix = length(P.xz);
        for (var i = 0; i < 5; i += 1) {
            let age = t - fd_slam(i);
            if (age > 0.0 && age < 3.0) {
                let front = fd_ring(i) * 0.9 + 140.0 * pow(age, 0.6);
                let w = 16.0 + 26.0 * age;
                let x = (dpix - front) / w;
                let n = fd_ss(0.42, 0.8, fbm(P.xz * 0.035 + vec2<f32>(age * 0.5, -age * 0.3)));
                let a = exp(-x * x) * pow(1.0 - age / 3.0, 2.0) * n * 0.55;
                col = mix(col, vec3<f32>(0.2, 0.18, 0.16), clamp(a, 0.0, 0.7));
            }
        }
    }
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}
