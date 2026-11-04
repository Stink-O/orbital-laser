// Orbital Laser's post pass for the Fold (laser 14). The mod builds it from shaders/strike.wgsl up to its fs_main less the
// other lasers' own functions, followed by this file, and sets it for a fold strike only. Validate with
// tools/check-shader.sh.

// ---- laser 14: the fold -------------------------------------------------------------------------------------------
// A strike that attacks how the world looks. Nothing in it is a flash or a blast; it is slow, and all of it is the view.
//   onset (0-8 s)         colours breathe, block edges shimmer and crawl.
//   come-up (8-20 s)      the sky splits into slowly turning mirrored wedges centred on the target; fractal patterns ripple
//                         over the land, anchored to the terrain by its depth; giant glowing mushrooms grow in a ring round it.
//   the fold (20-32 s)    the horizon curls up and the land rolls in on itself (the world bent about a cylinder, every pixel
//                         marched through the bent space against the world's own depth), mirrored copies of the world
//                         repeating round the target, hills and trees tiling up into the sky.
//   convergence (32-37 s) everything spirals into one point at the target and the world goes dark but for it.
//   release (37 s)        it snaps back, outwards from the point, with one wave of colour; the real crater is there.
//   comedown (39-50 s)    colours drain and return, the last patterns fizzle, the echoes die away.
// With `render.set-history` the pass reads its own last picture (binding 17) for the echoes: everything that moves leaves
// a trail whose hue drifts. No pixel changes faster than a slow colour shift, except the one wave at the release.
// strike/fold.rs plans the sounds and the land: keep the FD_* in step with its.
@group(0) @binding(17) var history_picture: texture_2d<f32>;

const FD_COMEUP: f32 = 8.0;
const FD_FOLD0: f32 = 20.0;        // the curl begins, fullest by FD_FOLD1
const FD_FOLD1: f32 = 30.0;
const FD_CONV0: f32 = 32.0;        // the spiral in
const FD_BEAT: f32 = 36.0;         // the beat of near silence
const FD_REL: f32 = 37.0;          // the release
const FD_SETTLE: f32 = 39.0;
const FD_END: f32 = 50.0;
const FD_GIANT_R: f32 = 82.0;      // the giant mushrooms' ring (fold.rs's FD_GIANT_R)
const FD_GIANTS: i32 = 12;
const FD_WAVE_V: f32 = 520.0;      // how fast the release's wave goes out, blocks a second
const FD_MARCH: i32 = 26;

fn fd_ss(a: f32, b: f32, x: f32) -> f32 { return smoothstep(a, b, x); }

// What the strike is doing at clock t (all smooth).
struct FdEnv {
    breathe: f32,   // the colours breathing and the edges shimmering
    kal_s: f32,     // the sky's mirrored wedges
    kal_g: f32,     // the world mirrored round the target
    frac: f32,      // fractals over the land
    mush: f32,      // (clock for the mushrooms)
    curl: f32,      // the horizon curling up
    conv: f32,      // the spiral in
    beat: f32,      // the collapse to one point
    trail: f32,     // the echoes
    drain: f32,     // the comedown's drained colours
}
fn fd_env(t: f32) -> FdEnv {
    var e: FdEnv;
    let after = 1.0 - fd_ss(FD_SETTLE + 1.0, FD_END - 1.0, t);
    e.breathe = (0.22 * fd_ss(0.3, 7.0, t) + 0.78 * fd_ss(7.0, 16.0, t)) * select(1.0, after, t > FD_REL);
    e.kal_s = fd_ss(8.0, 15.0, t);
    e.kal_g = fd_ss(19.0, 27.0, t);
    e.frac = fd_ss(10.0, 18.0, t);
    e.mush = t;
    e.curl = fd_ss(FD_FOLD0, FD_FOLD1, t);
    e.conv = fd_ss(FD_CONV0, FD_BEAT, t);
    e.beat = fd_ss(FD_BEAT - 0.2, FD_REL - 0.15, t);
    e.trail = fd_ss(11.0, 18.0, t) * (1.0 - fd_ss(FD_SETTLE + 1.0, FD_END - 1.0, t));
    e.drain = fd_ss(FD_REL + 0.6, FD_SETTLE + 1.5, t) * (1.0 - fd_ss(FD_SETTLE + 3.0, FD_END - 0.5, t));
    return e;
}

fn fd_hue(c: vec3<f32>, a: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735);
    let s = sin(a);
    let co = cos(a);
    return c * co + cross(k, c) * s + k * dot(k, c) * (1.0 - co);
}
fn fd_pal(x: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (vec3<f32>(x) + vec3<f32>(0.0, 0.33, 0.67)));
}
fn fd_mirror(u: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(1.0) - abs(fract(u * 0.5) * 2.0 - vec2<f32>(1.0));
}
fn fd_fwd() -> vec3<f32> {
    return -frame.inverse_view[2].xyz;
}
fn fd_sample(uv: vec2<f32>) -> vec3<f32> {
    return srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, fd_mirror(uv), 0.0).rgb);
}

// ---- directions about the target ---------------------------------------------------------------------------------
struct FdBasis {
    ax: vec3<f32>,
    ux: vec3<f32>,
    vx: vec3<f32>,
}
fn fd_basis(ax: vec3<f32>) -> FdBasis {
    var ux = cross(ax, vec3<f32>(0.0, 1.0, 0.0));
    if (length(ux) < 1.0e-3) {
        ux = vec3<f32>(1.0, 0.0, 0.0);
    }
    ux = normalize(ux);
    // (psi 0 to the right of the target, pi/2 up, -pi/2 down)
    return FdBasis(ax, ux, cross(ux, ax));
}
fn fd_polar(d: vec3<f32>, b: FdBasis) -> vec2<f32> {
    return vec2<f32>(acos(clamp(dot(d, b.ax), -1.0, 1.0)), atan2(dot(d, b.vx), dot(d, b.ux)));
}
fn fd_from_polar(p: vec2<f32>, b: FdBasis) -> vec3<f32> {
    return b.ax * cos(p.x) + (b.ux * cos(p.y) + b.vx * sin(p.y)) * sin(p.x);
}
// psi turned into one of n mirrored wedges (turning with `rot`), its source the half-wedge round `centre`; `w` how far
// (0 not at all), the short way round.
fn fd_fold_psi(psi: f32, n: f32, rot: f32, centre: f32, w: f32) -> f32 {
    let seg = TAU / n;
    let a = psi + rot;
    let k = a - seg * floor(a / seg);
    let m = abs(k - seg * 0.5);
    let src = centre + m - seg * 0.25;
    var delta = src - psi;
    delta = delta - TAU * round(delta / TAU);
    return psi + w * delta;
}

// ---- the world bent about a cylinder ------------------------------------------------------------------------------
// Camera-relative, in world axes. The land ahead (along `f`, the view's heading) curls up round an axis across the view
// (`r`) R above the ground: a point at distance s along it and h over it is at angle s / R round, R - h from the axis. `inv`
// takes a point of the bent world to where it is in the real one.
struct FdBend {
    f: vec3<f32>,
    r: vec3<f32>,
    yg: f32,
    R: f32,
}
fn fd_bend(curl: f32, t: f32, tgt: vec3<f32>) -> FdBend {
    let fw = fd_fwd();
    var fh = vec3<f32>(fw.x, 0.0, fw.z);
    fh = select(vec3<f32>(1.0, 0.0, 0.0), normalize(fh), length(fh) > 1.0e-3);
    // (turns a little, slowly: the roll)
    let turn = curl * 0.35 * sin(t * 0.17);
    let c = cos(turn);
    let s = sin(turn);
    let f = vec3<f32>(fh.x * c - fh.z * s, 0.0, fh.x * s + fh.z * c);
    let yg = clamp(tgt.y - frame.camera_position.y, -70.0, -1.6);
    let k = pow(curl, 1.6) / 92.0 * (1.0 + 0.14 * sin(t * 0.55));
    let R = max(1.0 / (1.2e-4 + k), -yg * 1.5 + 22.0);
    return FdBend(f, vec3<f32>(f.z, 0.0, -f.x), yg, R);
}
fn fd_bend_inv(p: vec3<f32>, b: FdBend) -> vec3<f32> {
    let u = dot(p, b.f);
    let l = dot(p, b.r);
    let v = p.y - (b.yg + b.R);
    let rho = max(length(vec2<f32>(u, v)), 0.5);
    let alpha = atan2(u, -v);
    return b.f * (b.R * alpha) + b.r * l + vec3<f32>(0.0, b.yg + (b.R - rho), 0.0);
}
fn fd_bend_fwd(p: vec3<f32>, b: FdBend) -> vec3<f32> {
    let s = dot(p, b.f);
    let l = dot(p, b.r);
    let h = p.y - b.yg;
    let a = s / b.R;
    let rho = b.R - h;
    return b.f * (rho * sin(a)) + b.r * l + vec3<f32>(0.0, b.yg + b.R - rho * cos(a), 0.0);
}

// Whether the real world's point `pr` (camera-relative) is at or behind what the picture shows there.
fn fd_behind(pr: vec3<f32>, fw: vec3<f32>) -> bool {
    let zv = dot(pr, fw);
    if (zv < 0.1) {
        return false;
    }
    let q = project_rel(pr);
    let dp = depth_at(fd_mirror(q.xy));
    let zs = select(1.0e6, linear_depth(dp), !is_sky(dp));
    return zv >= zs;
}
// The ray `d` through the bent world: the first point of the real world it meets (camera-relative; w the distance along
// the bent ray, -1 for none), marched in steps that grow with the distance, then refined.
fn fd_march(d: vec3<f32>, b: FdBend) -> vec4<f32> {
    let fw = fd_fwd();
    var tau = 1.5;
    var prev = 0.0;
    for (var i = 0; i < FD_MARCH; i = i + 1) {
        if (fd_behind(fd_bend_inv(d * tau, b), fw)) {
            var lo = prev;
            var hi = tau;
            for (var j = 0; j < 5; j = j + 1) {
                let mid = 0.5 * (lo + hi);
                if (fd_behind(fd_bend_inv(d * mid, b), fw)) {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }
            return vec4<f32>(fd_bend_inv(d * hi, b), hi);
        }
        prev = tau;
        tau = tau * 1.14 + 0.8;
    }
    return vec4<f32>(0.0, 0.0, 0.0, -1.0);
}

// ---- the mushrooms -------------------------------------------------------------------------------------------------
fn fd_giant_pos(k: i32, tgt: vec3<f32>) -> vec3<f32> {
    let a = (f32(k) + 0.5) * TAU / f32(FD_GIANTS);
    return vec3<f32>(tgt.x + FD_GIANT_R * cos(a), tgt.y, tgt.z + FD_GIANT_R * sin(a));
}
fn fd_giant_size(k: i32, t: f32) -> f32 {
    let g = fd_ss(9.0 + 0.4 * f32(k), 17.0 + 0.4 * f32(k), t);
    let sway = 1.0 + 0.05 * sin(t * 1.1 + f32(k) * 1.7);
    return g * sway * (1.0 - fd_ss(34.0, 36.2, t));
}
// The ray from the origin (direction d) against a mushroom standing at `c` (its foot), scale `s`: x the distance (-1
// for none), y 0 stem, 1 cap's top, 2 its underside, zw the local direction for its spots.
fn fd_mush_hit(d: vec3<f32>, c: vec3<f32>, s: f32, k: i32) -> vec4<f32> {
    let hk = hash21(vec2<f32>(f32(k), 3.1));
    let H = (26.0 + 8.0 * hk) * s;
    let Rc = (17.0 + 5.0 * fract(hk * 7.3)) * s;
    let Rs = 2.8 * s;
    var best = vec4<f32>(-1.0, 0.0, 0.0, 0.0);
    // the stem: a cylinder
    let o = -c;
    let a = dot(d.xz, d.xz);
    let bq = dot(o.xz, d.xz);
    let cq = dot(o.xz, o.xz) - Rs * Rs;
    let disc = bq * bq - a * cq;
    if (disc > 0.0 && a > 1.0e-6) {
        let th = (-bq - sqrt(disc)) / a;
        let yy = o.y + d.y * th;
        if (th > 0.0 && yy > 0.0 && yy < H) {
            best = vec4<f32>(th, 0.0, yy / H, atan2(o.z + d.z * th, o.x + d.x * th));
        }
    }
    // the cap: the upper part of an ellipsoid on top of it
    let e = vec3<f32>(Rc, 0.62 * Rc, Rc);
    let oc = (o - vec3<f32>(0.0, H, 0.0)) / e;
    let dc = d / e;
    let a2 = dot(dc, dc);
    let b2 = dot(oc, dc);
    let c2 = dot(oc, oc) - 1.0;
    let d2 = b2 * b2 - a2 * c2;
    if (d2 > 0.0) {
        let sq = sqrt(d2);
        let t0 = (-b2 - sq) / a2;
        let t1 = (-b2 + sq) / a2;
        for (var j = 0; j < 2; j = j + 1) {
            let tc = select(t1, t0, j == 0);
            let p = oc + dc * tc;
            if (tc > 0.0 && p.y > -0.18 && (best.x < 0.0 || tc < best.x)) {
                best = vec4<f32>(tc, select(2.0, 1.0, j == 0), p.x, p.z);
            }
        }
    }
    return best;
}

// ---- looks ---------------------------------------------------------------------------------------------------------
// A kaliset fractal in the world's own coordinates (so it sits on the land and on its walls), a value 0 to 1.
fn fd_fractal(p: vec3<f32>, t: f32) -> f32 {
    var z = p * 0.034 + vec3<f32>(0.2 * sin(t * 0.07), 0.0, 0.2 * cos(t * 0.09));
    var acc = 0.0;
    let c = vec3<f32>(0.78 + 0.04 * sin(t * 0.11), 0.69, 0.82 + 0.03 * cos(t * 0.13));
    for (var i = 0; i < 6; i = i + 1) {
        z = abs(z) / max(dot(z, z), 0.08) - c;
        acc = acc + exp(-4.0 * abs(length(z) - 0.9));
    }
    return clamp(acc * 0.5, 0.0, 1.0);
}
// The sky as a kaleidoscope: wedges turning slowly, marbled, rings spreading from the target.
fn fd_sky_pattern(d: vec3<f32>, b: FdBasis, t: f32, n: f32) -> vec3<f32> {
    let pp = fd_polar(d, b);
    let psi = fd_fold_psi(pp.y, n, t * 0.045, 0.0, 1.0);
    let q = vec2<f32>(pp.x * 2.6, psi * 2.2);
    let w1 = gfbm2(q * 1.4 + vec2<f32>(t * 0.05, 3.1));
    let w2 = gfbm2(q * 2.2 - vec2<f32>(5.3, t * 0.04) + w1 * 1.6);
    let rings = 0.5 + 0.5 * sin(pp.x * 24.0 - t * 0.5 + w2 * 3.0);
    let v = w2 * 0.8 + pp.x * 0.35 + t * 0.012;
    var c = fd_pal(v) * (0.1 + 0.9 * rings * rings) * 0.95;
    c = c + fd_pal(v + 0.5) * exp(-pp.x * 3.0) * 0.5;
    return c;
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let t = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let e = fd_env(t);
    let res = frame.resolution.xy;
    let aspect = res.x / res.y;

    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let dir0 = normalize(world_offset(uv, 0.5));
    let rel0 = select(dir0 * 400.0, world_offset(uv, d0), !sky0);
    let P0 = cam + rel0;
    let dpix = length(P0.xz - tgt.xz);

    // the release: the wave from the target outwards, inside it the world is as it was
    let rf = (t - FD_REL) * FD_WAVE_V - 60.0;
    let restored = 1.0 - fd_ss(rf - 40.0, rf + 6.0, dpix);
    let live = 1.0 - restored;

    var col = vec3<f32>(0.0);
    var ground_p = P0;                 // where in the real world this pixel's colour comes from
    var hit = !sky0;
    var tau_hit = 1.0e9;
    var d2 = dir0;
    var uvs = uv;
    var void_k = 0.0;

    let ax = normalize(tgt - cam);
    let B = fd_basis(ax);
    let kal_g = e.kal_g * live;
    let curl = e.curl * live;
    let conv = e.conv * live;
    let beat = e.beat * live;
    let warped = (kal_g + curl + conv) > 0.002;

    if (!warped) {
        // (nothing bends yet, or any more: the picture as it is, its sky wedged in the come-up)
        col = fd_sample(uv);
        tau_hit = select(1.0e9, length(rel0), !sky0);
    } else {
        // the spiral in: the direction's angle from the target stretched and twisted
        var pp = fd_polar(dir0, B);
        let pull = 1.0 + 16.0 * pow(conv, 2.5) + 90.0 * pow(beat, 2.0);
        let swirl = (5.0 * conv * conv + 4.0 * beat) / (0.2 + pp.x * 3.0);
        pp = vec2<f32>(pp.x * pull, pp.y + swirl);
        if (pp.x >= 3.1) {
            void_k = 1.0;
        }
        // mirrored copies round the target (the wedge's source is the ground on the player's side of it)
        pp.y = fd_fold_psi(pp.y, 12.0, t * 0.035, -1.5708, kal_g * fd_ss(0.0, 0.12, pp.x));
        d2 = fd_from_polar(vec2<f32>(min(pp.x, 3.1), pp.y), B);
        // the world bent, marched
        let bnd = fd_bend(curl, t, tgt);
        let m = fd_march(d2, bnd);
        if (m.w > 0.0) {
            let q = project_rel(m.xyz);
            uvs = q.xy;
            col = fd_sample(uvs);
            ground_p = cam + m.xyz;
            tau_hit = m.w;
            hit = true;
        } else {
            hit = false;
            tau_hit = 1.0e9;
            col = vec3<f32>(0.0);
            ground_p = cam + d2 * 500.0;
        }
    }

    // ---- the sky: wedges, marbled, ringed ---------------------------------------------------------------------------
    let is_skyish = !hit;
    if (is_skyish) {
        let skyc = select(srgb_to_linear(frame.sky_color.rgb), col, !warped);
        let pat = fd_sky_pattern(d2, B, t, 8.0);
        let k = max(e.kal_s * live, kal_g);
        // (the sky as it was, mirrored in the same wedges: its sun and clouds turned into a kaleidoscope)
        let pp = fd_polar(d2, B);
        let psi = fd_fold_psi(pp.y, 8.0, t * 0.045, 1.5708, 1.0);
        let ds = fd_from_polar(vec2<f32>(pp.x, psi), B);
        let qs = project_rel(ds * 100.0);
        let mir = select(skyc, fd_sample(qs.xy), qs.z > 0.0);
        let wl = smoothstep(0.0, 0.05, abs(fd_fold_psi(pp.y, 8.0, t * 0.045, 0.0, 1.0) - pp.y + 3.0) * 0.0 + 0.1);
        col = mix(skyc, mix(mir, pat, 0.85) * 0.95, k);
        ground_p = cam + d2 * 600.0;
    }

    // ---- breathing colours, shimmering edges --------------------------------------------------------------------------
    let rr = length(ground_p.xz - tgt.xz);
    let b = e.breathe * live;
    // (the edges: where the picture's colour or depth jumps, found in the real picture round where this came from)
    let px = frame.resolution.zw * 1.6;
    let c1 = fd_sample(uvs + vec2<f32>(px.x, 0.0));
    let c2 = fd_sample(uvs - vec2<f32>(px.x, 0.0));
    let c3 = fd_sample(uvs + vec2<f32>(0.0, px.y));
    let c4 = fd_sample(uvs - vec2<f32>(0.0, px.y));
    let edge = clamp((abs(luminance(c1) - luminance(c2)) + abs(luminance(c3) - luminance(c4))) * 3.2, 0.0, 1.0);
    let crawl = 0.5 + 0.5 * sin(dot(ground_p, vec3<f32>(1.7, 2.3, 1.1)) * 0.9 - t * 2.2 + edge * 6.0);
    if (!is_skyish) {
        col = fd_hue(col, b * (0.55 * sin(t * 0.8 + rr * 0.025) + 0.25 * sin(t * 0.37 + ground_p.y * 0.05)));
        let l = luminance(col);
        col = mix(vec3<f32>(l), col, 1.0 + b * (0.3 + 0.2 * sin(t * 0.6 + rr * 0.04)));
        col = col * (1.0 + 0.05 * b * sin(t * 0.9));
        col = col + fd_pal(t * 0.03 + rr * 0.01 + edge) * edge * crawl * b * 0.7;
    }

    // ---- the fractals over the land, anchored to it ------------------------------------------------------------------
    if (!is_skyish && e.frac > 0.001) {
        let f = fd_fractal(ground_p, t);
        let rip = 0.5 + 0.5 * sin(rr * 0.17 - t * 1.15);
        let reach = exp(-rr / 220.0) * 0.8 + 0.2;
        let s = e.frac * live * reach * (0.35 + 0.65 * rip);
        let tint = fd_pal(f * 1.6 + rr * 0.004 - t * 0.04);
        col = mix(col, col * (0.35 + 1.5 * tint), clamp(s * 0.5, 0.0, 0.6)) + tint * f * s * 0.12;
    }

    // ---- the mushrooms: a ring of giants round the target, glowing -----------------------------------------------------
    if (t > 9.0 && t < 36.5) {
        let bnd = fd_bend(curl, t, tgt);
        var best_t = 1.0e9;
        var mush_col = vec3<f32>(0.0);
        var spill = vec3<f32>(0.0);
        for (var k = 0; k < FD_GIANTS; k = k + 1) {
            let s = fd_giant_size(k, t);
            if (s < 0.01) {
                continue;
            }
            let base = fd_giant_pos(k, tgt) - cam;
            let hk = hash21(vec2<f32>(f32(k), 3.1));
            let hue = fract(hk * 3.7 + 0.12 * sin(t * 0.2 + f32(k)));
            // where it stands in the bent world
            let c = select(base, fd_bend_fwd(base, bnd), curl > 0.002);
            let sc = s * (1.0 - 0.0 * live);
            // (the light it throws on the land round its foot, in the real world)
            let gp = ground_p - fd_giant_pos(k, tgt);
            let gd = length(gp.xz);
            let pulse = 0.75 + 0.25 * sin(t * 1.3 + f32(k) * 2.1);
            if (!is_skyish) {
                spill = spill + fd_pal(hue) * exp(-gd / (14.0 * s + 1.0)) * pulse * s * 0.9 * exp(-max(gp.y, 0.0) * 0.05);
            }
            let cm = c + vec3<f32>(0.0, 18.0 * s, 0.0);
            if (dot(cm, d2) < -40.0 * s || length(cm - d2 * dot(cm, d2)) > 34.0 * s + 6.0) {
                continue;
            }
            let h = fd_mush_hit(d2, c, sc, k);
            if (h.x > 0.0 && h.x < best_t) {
                best_t = h.x;
                var m = vec3<f32>(0.0);
                if (h.y < 0.5) {
                    // the stem: pale, glowing, ringed
                    let ring = 0.5 + 0.5 * sin(h.z * 40.0 + t);
                    m = mix(vec3<f32>(0.9, 0.8, 0.95), fd_pal(hue + 0.3), 0.4) * (0.45 + 0.35 * ring) * pulse;
                } else if (h.y < 1.5) {
                    // the cap: glowing, spotted, bright at its rim
                    let sp = vnoise(vec2<f32>(h.z * 7.0, h.w * 7.0) + f32(k) * 3.0);
                    let spots = smoothstep(0.62, 0.7, sp);
                    let rim = pow(clamp(length(vec2<f32>(h.z, h.w)), 0.0, 1.0), 3.0);
                    m = fd_pal(hue) * (0.6 + 0.9 * rim) * pulse + vec3<f32>(0.9, 0.95, 1.0) * spots * 0.7;
                } else {
                    m = fd_pal(hue + 0.15) * 0.45 * pulse + vec3<f32>(0.2) * (0.5 + 0.5 * sin(atan2(h.w, h.z) * 30.0));
                }
                mush_col = m;
            }
        }
        col = col + spill * e.frac * live * 0.8;
        if (best_t < tau_hit) {
            let fade = exp(-best_t / 600.0);
            col = mix(col, mush_col * 1.3, fade * live * 0.97);
        }
    }

    // ---- the collapse: dark but for one point ---------------------------------------------------------------------------
    if (void_k > 0.5) {
        let q = fd_polar(dir0, B);
        let sp = gfbm2(vec2<f32>(q.x * 3.0 - t * 0.25, (q.y + 5.0 * conv * conv) * 1.6));
        col = fd_pal(sp + t * 0.02) * 0.05 * (1.0 - beat) * (0.4 + sp);
    }
    col = col * (1.0 - 0.94 * beat * (0.6 + 0.4 * fd_ss(0.0, 0.5, dot(dir0, ax) * 8.0 - 7.0 + 1.0 - beat)));
    // (the point: where the target is, a small pale star in the dark, drawing in and holding)
    if (t > FD_CONV0 && t < FD_REL + 0.2) {
        let q = project_rel(tgt - cam);
        let dd = length((uv - q.xy) * vec2<f32>(aspect, 1.0));
        let grow = 0.004 + 0.02 * (1.0 - e.conv) + 0.003 * sin(t * 2.0);
        let star = exp(-dd / grow) * 0.9 + exp(-dd / (grow * 5.0)) * 0.25;
        col = col + vec3<f32>(0.9, 0.85, 1.0) * star * e.conv * select(0.0, 1.0, q.z > 0.0);
    }

    // ---- the release: one wave of colour out of the point ----------------------------------------------------------------
    let since = t - FD_REL;
    if (since > -0.05 && since < 3.2) {
        let ring = exp(-pow((dpix - (rf + 50.0)) / 34.0, 2.0));
        let wave_env = fd_ss(-0.05, 0.5, since) * (1.0 - fd_ss(1.4, 3.2, since));
        let rc = fd_pal(dpix * 0.012 - since * 0.8);
        col = col + rc * ring * wave_env * 1.6;
        // (and the world under it for a moment brighter and more saturated, fading as it settles)
        let after = restored * (1.0 - fd_ss(0.4, 2.4, since - dpix / FD_WAVE_V));
        let l = luminance(col);
        col = mix(vec3<f32>(l), col, 1.0 + 0.7 * after) * (1.0 + 0.12 * after);
    }

    // ---- the comedown: colours drained, coming back --------------------------------------------------------------------------
    if (e.drain > 0.001) {
        let l = luminance(col);
        col = mix(col, vec3<f32>(l) * vec3<f32>(0.95, 0.97, 1.05), e.drain * 0.78);
    }

    // ---- echoes: the pass's last picture, followed to where this came from, its hue drifting ---------------------------------
    var out_col = col;
    if (frame.previous_camera_position.w > 0.5 && e.trail > 0.001) {
        var uvp = uv;
        if (!is_skyish) {
            let dq = ground_p - frame.previous_camera_position.xyz;
            let pc = frame.previous_projection * (frame.previous_view * vec4<f32>(dq, 1.0));
            if (pc.w > 0.05) {
                uvp = vec2<f32>(pc.x / pc.w * 0.5 + 0.5, 0.5 - pc.y / pc.w * 0.5);
            }
        }
        let h = srgb_to_linear(textureSampleLevel(history_picture, linear_sampler, fd_mirror(uvp), 0.0).rgb);
        let echo = fd_hue(h, 0.025) * 0.965;
        // (in the dark of the collapse the echoes are let go quickly)
        let k = e.trail * 0.9 * (1.0 - 0.8 * beat) * (1.0 - 0.9 * restored * fd_ss(0.0, 0.8, since - dpix / FD_WAVE_V));
        out_col = mix(col, max(col, echo), k);
    }
    return vec4<f32>(linear_to_srgb(max(out_col, vec3<f32>(0.0))), 1.0);
}
