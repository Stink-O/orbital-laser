// Orbital Laser's post pass for the Fold (laser 14). The mod builds it from shaders/strike.wgsl up to its fs_main less the
// other lasers' own functions, followed by this file, and sets it for a fold strike only. Validate with
// tools/check-shader.sh.

// ---- laser 14: the fold -------------------------------------------------------------------------------------------
// The bending itself isn't here: the world's real vertices go through shaders/fold_warp.wgsl (the fork's render.set-warp),
// far terrain and all, so what this pass gets is already the bent world. It only adds what is over the picture: the
// jolt of the first second and of the blast (the picture pulled about the target), the sky going out as the world is
// drawn in, the point in the dark, the blast's flash and ring, and the comedown's drained colours.
// strike/fold.rs plans the sounds and the land: keep the FD_* in step with its and fold_warp.wgsl's.
const FD_CONV0: f32 = 29.0;        // all of it drawn in
const FD_BEAT: f32 = 36.0;         // the beat of near silence
const FD_REL: f32 = 37.0;          // the release
const FD_SETTLE: f32 = 39.0;
const FD_END: f32 = 50.0;
const FD_WAVE_V: f32 = 1500.0;     // how fast the world comes back, blocks a second (FW_REL_V)

fn fd_ss(a: f32, b: f32, x: f32) -> f32 { return smoothstep(a, b, x); }
fn fd_pal(x: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (vec3<f32>(x) + vec3<f32>(0.0, 0.33, 0.67)));
}
fn fd_sample(uv: vec2<f32>) -> vec3<f32> {
    return srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let t = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let res = frame.resolution.xy;
    let aspect = res.x / res.y;
    let q = project_rel(tgt - cam);
    let centre = select(vec2<f32>(0.5), q.xy, q.z > 0.0);
    let dd = length((uv - q.xy) * vec2<f32>(aspect, 1.0));

    // ---- the jolts: the picture pulled in and out about the target, its colours pulled apart --------------------------
    let hook = fd_ss(0.0, 0.08, t) * (1.0 - fd_ss(0.15, 0.9, t));
    let blast = fd_ss(FD_REL - 0.02, FD_REL + 0.03, t) * (1.0 - fd_ss(FD_REL + 0.1, FD_REL + 1.0, t));
    let jolt = hook * 0.05 + blast * 0.09;
    var col: vec3<f32>;
    if (jolt > 0.0005) {
        let d = uv - centre;
        col = vec3<f32>(fd_sample(centre + d * (1.0 - jolt * 1.3)).r, fd_sample(centre + d * (1.0 - jolt)).g, fd_sample(centre + d * (1.0 - jolt * 0.7)).b);
    } else {
        col = fd_sample(uv);
    }

    // ---- the sky goes out as the world is drawn in; with nothing left, only the dark and its stars ---------------------
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let dark = fd_ss(FD_CONV0, 34.5, t) * (1.0 - fd_ss(FD_REL, FD_REL + 0.9, t));
    if (sky0 && dark > 0.0) {
        let dir = normalize(world_offset(uv, 0.5));
        let c = floor(dir * 170.0);
        let h = hash21(c.xy + c.z * 3.7);
        let star = select(0.0, (h - 0.993) / 0.007, h > 0.993);
        let space = vec3<f32>(0.012, 0.01, 0.022) + vec3<f32>(0.75, 0.78, 0.95) * star * star;
        col = mix(col, space, dark);
    }
    // (the sky's own bruise round the mass as it closes)
    if (sky0) {
        col = col * (1.0 + fd_ss(FD_CONV0 - 4.0, FD_CONV0, t) * (1.0 - dark) * vec3<f32>(-0.2, -0.3, -0.05));
    }

    // ---- the point: where the target is, a small pale star in the dark, drawing in and holding --------------------------
    if (t > FD_BEAT - 0.5 && t < FD_REL + 0.2 && q.z > 0.0) {
        let grow = 0.003 + 0.0012 * sin(t * 11.0);
        let on = fd_ss(FD_BEAT - 0.5, FD_BEAT, t);
        let star = exp(-dd / grow) * 2.2 + exp(-dd / (grow * 7.0)) * 0.4;
        col = col + vec3<f32>(0.92, 0.88, 1.0) * star * on;
    }

    // ---- the blast: the flash out of the point, one ring of colour racing out over the land -----------------------------
    let since = t - FD_REL;
    if (since > -0.02 && since < 3.6) {
        let flash = exp(-max(since, 0.0) * 7.0);
        col = mix(col, vec3<f32>(1.0, 0.98, 1.05) * 1.3, flash * exp(-dd * 1.6 / (0.25 + 3.0 * max(since, 0.0))));
        if (!sky0) {
            let P = cam + world_offset(uv, d0);
            let dpix = length(P.xz - tgt.xz);
            let rf = since * FD_WAVE_V + 0.5 * since * since * 500.0;
            let w = 26.0 + 0.05 * rf;
            let ring = exp(-pow((dpix - rf) / w, 2.0));
            col = col + fd_pal(dpix * 0.004 - since * 0.8) * ring * (1.0 - fd_ss(0.8, 2.4, since)) * 0.3;
        }
    }

    // ---- the comedown: colours drained, coming back ----------------------------------------------------------------------
    let drain = fd_ss(FD_REL + 0.6, FD_SETTLE + 1.5, t) * (1.0 - fd_ss(FD_SETTLE + 3.0, FD_END - 0.5, t));
    if (drain > 0.001) {
        let l = luminance(col);
        col = mix(col, vec3<f32>(l) * vec3<f32>(0.95, 0.97, 1.05), drain * 0.5);
    }
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}
