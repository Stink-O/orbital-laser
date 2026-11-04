// Orbital Laser's post pass for the Fold (laser 14). The mod builds it from shaders/strike.wgsl up to its fs_main less the
// other lasers' own functions, followed by this file, and sets it for a fold strike only. Validate with
// tools/check-shader.sh.

// ---- laser 14: the fold -------------------------------------------------------------------------------------------
// The world bends outwards from the target. Everything here is a function of the world's position about the target and of
// the clock, never of the screen: a front grows out of the target (a swell racing over the land, buckling it), and behind
// it the world is displaced: twisted and sheared about the target, the land beyond a line through it curling up and over,
// its blocks repeated and turned in cells (houses and trees multiplying through each other), all of it dragged in towards
// the target in the last seconds into one mass. The picture is the game's own: each pixel's ray is marched through the
// displaced space (`fd_src` takes a point of it to where it is in the real world) against the real picture's depth, and
// takes the real picture's colour where it lands, so it is always blocks and textures.
//   0-2 s      the hook: the ground bucks at the target and a ripple races out over the land
//   2-30 s     the front grows over everything in view; behind it the land bends, folds and repeats, more and more
//   30-36 s    all of it drawn in to the target; the beat of near silence in the dark
//   37 s       the one blast: the real world snaps back from the middle out, the mandala crater in it
//   39-50 s    comedown
// strike/fold.rs plans the sounds and the land: keep the FD_* in step with its.
const FD_FOLD0: f32 = 12.0;        // the land beyond the target's line begins to curl over
const FD_CONV0: f32 = 29.0;        // all of it drawn in
const FD_BEAT: f32 = 36.0;         // the beat of near silence
const FD_REL: f32 = 37.0;          // the release
const FD_SETTLE: f32 = 39.0;
const FD_END: f32 = 50.0;
const FD_WAVE_V: f32 = 520.0;      // how fast the release's wave goes out, blocks a second
const FD_MARCH: i32 = 30;

fn fd_ss(a: f32, b: f32, x: f32) -> f32 { return smoothstep(a, b, x); }
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
fn fd_rot(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ---- the front and the bending, all of the world's position and the time ---------------------------------------------
// How far the front has grown (blocks from the target): fast, then faster, until it covers all in view.
fn fd_front(t: f32) -> f32 {
    return 34.0 * t + 8.0 * t * t;
}
// What the strike is doing at clock t (all smooth).
struct FdEnv {
    grow: f32,      // how far the bending has come
    curl: f32,      // the land curling up and over
    rep: f32,       // the world repeating in cells
    conv: f32,      // drawn in
    beat: f32,      // the dark
    drain: f32,     // the comedown's drained colours
}
fn fd_env(t: f32) -> FdEnv {
    var e: FdEnv;
    e.grow = fd_ss(0.8, 18.0, t);
    e.curl = fd_ss(FD_FOLD0, 27.0, t);
    e.rep = fd_ss(8.0, 24.0, t);
    e.conv = fd_ss(FD_CONV0, FD_BEAT, t);
    e.beat = fd_ss(FD_BEAT - 0.2, FD_REL - 0.15, t);
    e.drain = fd_ss(FD_REL + 0.6, FD_SETTLE + 1.5, t) * (1.0 - fd_ss(FD_SETTLE + 3.0, FD_END - 0.5, t));
    return e;
}
// The release's wave: 1 where the real world is back (r from the target).
fn fd_restored(t: f32, r: f32) -> f32 {
    let rf = (t - FD_REL) * FD_WAVE_V - 60.0;
    return 1.0 - fd_ss(rf - 40.0, rf + 6.0, r);
}
// The swell at the front, and how much of the world the front has bent (both for the point's distance r).
fn fd_swell(t: f32, r: f32) -> f32 {
    let x = r - fd_front(t);
    let w = 20.0 + 0.4 * t;
    let amp = (9.0 + 4.0 * sin(t * 0.7)) * exp(-r / 330.0) * (1.0 - fd_ss(14.0, 26.0, t));
    // (a swell: a crest and a trough behind it, the crest the highest)
    let env = exp(-x * x / (2.0 * w * w));
    return amp * env * sin(x * 0.12 + 1.2) * 1.4;
}
// The point `Q` (of the bent world, from the target) in the real world (from the target).
fn fd_src(Qin: vec3<f32>, t: f32, e: FdEnv, f: vec2<f32>, home: vec2<f32>, seed: f32, camq: vec3<f32>) -> vec3<f32> {
    var Q = Qin;
    let r = length(Q.xz);
    // (the world right round the eye is left straight, so they are never inside the bending)
    let live = (1.0 - fd_restored(t, r)) * fd_ss(22.0, 110.0, length(Qin - camq));
    if (t < 0.02 || live < 0.001) {
        return Q;
    }
    let behind = 1.0 - fd_ss(fd_front(t) - 110.0, fd_front(t), r);
    let near = exp(-r / (120.0 + 4.0 * t));
    let d = e.grow * behind * live * (0.3 + 0.7 * near);
    // the ripple (the land raised where it passes; the ground buckling at the target in the first seconds)
    Q.y = Q.y - fd_swell(t, r) * live - 11.0 * exp(-r / 26.0) * (1.0 - fd_ss(0.2, 2.6, t)) * fd_ss(0.0, 0.25, t) * live;
    // twisted and sheared about the target: more the nearer, and the higher up, the more
    var th = d * (2.4 * near + 0.5) * sin(t * 0.21 + seed);
    th = th + Q.y * 0.01 * d * (1.0 + sin(t * 0.33));
    Q = vec3<f32>(fd_rot(Q.xz, th), Q.y).xzy;
    // the land beyond a line through the target curling up and over (a cylinder about an axis along it, fixed in the world)
    let g = vec2<f32>(f.y, -f.x);
    let u = dot(Q.xz, f);
    if (u > 0.0 && e.curl > 0.001) {
        let l = dot(Q.xz, g);
        let R = mix(900.0, 62.0, pow(e.curl * live, 0.8));
        let v = Q.y - R;
        let rho = max(length(vec2<f32>(u, v)), 0.5);
        let alpha = atan2(u, -v);
        let s2 = R * alpha;
        let h = R - rho;
        Q = vec3<f32>(f * s2 + g * l, h).xzy;
        Q.y = h;
    }
    // the world in cells, each a turned copy of the one the player stood in, sliding through its neighbours
    let rep = e.rep * live * behind;
    if (rep > 0.001) {
        let C = 72.0;
        let cell = round(Q.xz / C);
        let local = Q.xz - cell * C;
        let k = floor(hash21(cell + vec2<f32>(seed, 3.0)) * 4.0);
        let turned = fd_rot(local, k * 1.5708) + home;
        let lift = (hash21(cell * 1.7 + 9.0) - 0.5) * 26.0 * rep * rep;
        let m = fd_ss(0.0, 1.0, rep);
        Q = vec3<f32>(mix(Q.xz, turned, m), Q.y + lift).xzy;
    }
    // all of it drawn in, round and round, into the one mass at the target
    let cv = e.conv * live;
    if (cv > 0.001) {
        let rr = length(Q.xz);
        let pull = 1.0 + 6.0 * cv * cv * exp(-rr / 130.0) + 4.0 * e.beat;
        let spin = (3.0 * cv * cv + 3.0 * e.beat) * exp(-rr / 90.0);
        Q = vec3<f32>(fd_rot(Q.xz * pull, spin), Q.y * (1.0 - 0.35 * cv) - 14.0 * cv * exp(-rr / 80.0)).xzy;
    }
    return Q;
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

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let t = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let e = fd_env(t);
    let res = frame.resolution.xy;
    let aspect = res.x / res.y;
    let fw = fd_fwd();
    let seed = seed_v();

    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let dir0 = normalize(world_offset(uv, 0.5));
    let rel0 = select(dir0 * 400.0, world_offset(uv, d0), !sky0);
    let P0 = cam + rel0;
    let dpix = length(P0.xz - tgt.xz);

    // the world's fixed directions: the line the land curls over runs across where the player stood as it fired, and the
    // cell they stood in is the one that repeats
    var me = frame.mod_params[3].yzw;
    if (length(me) < 1.0) {
        me = cam;
    }
    let fl = tgt.xz - me.xz;
    let f = select(vec2<f32>(0.0, 1.0), normalize(fl), length(fl) > 1.0e-3);
    let C = 72.0;
    let home = round((me.xz - tgt.xz) / C) * C;

    var col = fd_sample(uv);
    var hit = !sky0;
    var srel = rel0;
    var tau_hit = select(1.0e9, length(rel0), !sky0);
    var amount = 0.0;
    let live_on = t > 0.02 && t < FD_REL + 3.4;
    if (live_on) {
        // the ray through the bent space
        var tau = 1.5;
        var prev = 0.0;
        var found = false;
        var last = vec3<f32>(0.0);
        for (var i = 0; i < FD_MARCH; i = i + 1) {
            let srcp = fd_src(dir0 * tau + cam - tgt, t, e, f, home, seed, cam - tgt) + tgt - cam;
            if (fd_behind(srcp, fw)) {
                var lo = prev;
                var hi = tau;
                for (var j = 0; j < 5; j = j + 1) {
                    let mid = 0.5 * (lo + hi);
                    if (fd_behind(fd_src(dir0 * mid + cam - tgt, t, e, f, home, seed, cam - tgt) + tgt - cam, fw)) {
                        hi = mid;
                    } else {
                        lo = mid;
                    }
                }
                srel = fd_src(dir0 * hi + cam - tgt, t, e, f, home, seed, cam - tgt) + tgt - cam;
                tau_hit = hi;
                found = true;
                break;
            }
            prev = tau;
            tau = tau * 1.13 + 0.7;
        }
        hit = found;
        if (found) {
            let q = project_rel(srel);
            col = fd_sample(q.xy);
            amount = clamp(length(srel - (dir0 * tau_hit)) / 40.0, 0.0, 1.0);
        } else {
            // (nothing of the real world where this ray goes: the sky)
            col = srgb_to_linear(frame.sky_color.rgb);
            srel = dir0 * 600.0;
        }
    }
    let ground_p = cam + srel;
    let Pb = cam + dir0 * min(tau_hit, 600.0) - tgt;   // where it is in the bent world, from the target
    let rb = length(Pb.xz);
    let live = 1.0 - fd_restored(t, rb);

    // ---- colour: the world's own, turned the more it is bent ---------------------------------------------------------
    if (hit) {
        let k = clamp(amount * 1.2 + e.grow * 0.25, 0.0, 1.0) * live;
        col = fd_hue(col, k * (0.6 * sin(t * 0.4 + rb * 0.02) + 0.5 * sin(ground_p.y * 0.06 + t * 0.2)));
        let l = luminance(col);
        col = mix(vec3<f32>(l), col, 1.0 + 0.5 * k);
        col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(1.0 + 0.35 * k));
    }
    // the front: a bright seam on the land where the swell crests (in the world, so it stays put as they look round)
    {
        let x = rb - fd_front(t);
        let seam = exp(-x * x / 90.0) * (1.0 - fd_ss(12.0, 30.0, t)) * fd_ss(0.0, 0.3, t);
        col = col + fd_pal(rb * 0.01 - t * 0.2) * seam * 0.35 * select(0.0, 1.0, hit);
    }

    // ---- the mass: dark, and heavier, as it is drawn in ----------------------------------------------------------------
    let dm = length((Pb - vec3<f32>(0.0, 0.0, 0.0)).xz);
    col = col * (1.0 - 0.3 * e.conv * live * exp(-dm / 260.0)) * (1.0 - 0.9 * e.beat * live);
    if (!hit) {
        col = col * (1.0 - 0.8 * e.conv * live);
    }
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
        let rf = since * FD_WAVE_V - 60.0;
        let ring = exp(-pow((dpix - (rf + 50.0)) / 34.0, 2.0));
        let wave_env = fd_ss(-0.05, 0.5, since) * (1.0 - fd_ss(1.4, 3.2, since));
        let rc = fd_pal(dpix * 0.012 - since * 0.8);
        col = col + rc * ring * wave_env * 1.6;
        let restored = fd_restored(t, dpix);
        let after = restored * (1.0 - fd_ss(0.4, 2.4, since - dpix / FD_WAVE_V));
        let l = luminance(col);
        col = mix(vec3<f32>(l), col, 1.0 + 0.7 * after) * (1.0 + 0.12 * after);
    }

    // ---- the comedown: colours drained, coming back --------------------------------------------------------------------------
    if (e.drain > 0.001) {
        let l = luminance(col);
        col = mix(col, vec3<f32>(l) * vec3<f32>(0.95, 0.97, 1.05), e.drain * 0.6);
    }
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}
