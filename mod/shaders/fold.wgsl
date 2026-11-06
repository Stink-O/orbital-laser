// Orbital Laser's post pass for the Fold (laser 14). The mod builds it from shaders/strike.wgsl up to its fs_main less the
// other lasers' own functions, followed by this file, and sets it for a fold strike only. Validate with
// tools/check-shader.sh.

// ---- laser 14: the fold -------------------------------------------------------------------------------------------
// The world's bending, its creases, its tears and its colours aren't here: the land's own vertices and pixels go through
// shaders/fold_warp.wgsl. This pass draws what is not the world: the droplet (its fall, its stop, its meld), the void and
// its stars where the land has left, the point, the one flash, and the dust of the slams.
// strike/fold.rs plans the sounds and the land: keep the FD_* in step with its and fold_warp.wgsl's.
const FD_STOP: f32 = 3.4;          // the droplet stops dead
const FD_HANG: f32 = 4.5;          // it has hung still; it is let go
const FD_TOUCH: f32 = 6.0;         // it touches the land
const FD_MELD: f32 = 6.2;          // the land has closed over its tip: it has gone in
const FD_FOLD: f32 = 19.0;
const FD_SEAL: f32 = 35.0;
const FD_CRUSH: f32 = 35.0;
const FD_BEAT: f32 = 40.0;         // the tip touches the target
const FD_REL: f32 = 40.5;          // it all runs backwards
const FD_SLAM0: f32 = 44.1;         // the first ring lands
const FD_SLAM4: f32 = 48.7;        // the last slam
const FD_FALL: f32 = 3000.0;       // how high it starts over the target

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
        case 4: { return 44.1; }
        case 3: { return 45.2; }
        case 2: { return 46.3; }
        case 1: { return 47.4; }
        default: { return 48.7; }
    }
}

// ---- the droplet: a classic teardrop of liquid metal, round end down, its tip straight up, the same shape from the top of
// the sky to the ground. It falls hard, braking all the way (FD_B) but still doing FD_V when it stops dead in one frame; what
// was moving with it isn't stopped: the fire and the wake go on past it and down (fd_slip), hit the land and throw out a low
// ring of dust (fd_dust), and it shakes like a jelly for a second (fd_drop), hangs, and is let go: it falls to the land from rest.
// Its height over the land is d.h, to its centre; its bottom is d.R under that, its tip FD_TIP * d.R over it.
const FD_V: f32 = 280.0;           // how fast it is going as it stops, blocks a second
const FD_B: f32 = 177.16;          // its braking: (FD_FALL - FD_V * FD_STOP) / FD_STOP^2
const FD_SLIP: f32 = 0.3;          // how soon what moved with it loses its speed, seconds
const FD_TIP: f32 = 1.72;          // the tip, in radii over the centre
const FD_PIV: f32 = -0.3;          // the point it squashes about, in radii over the centre: low, the tip does the moving
struct FdDrop { R: f32, stop_h: f32, h: f32, sx: f32, sy: f32, piv: f32, rip: f32, ph: f32, sway: vec2<f32>, pool: f32, pw: f32 }
struct FdLight { L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>, haze: vec3<f32> }
struct FdMist { c: vec3<f32>, tau: f32, glow: vec3<f32> }
// How far over where it stops it is, `tau` seconds before it does, and when it was at that height.
fn fd_fall(tau: f32) -> f32 { return tau * (FD_V + FD_B * tau); }
fn fd_fall_inv(H: f32) -> f32 { return (sqrt(FD_V * FD_V + 4.0 * FD_B * max(H, 0.0)) - FD_V) / (2.0 * FD_B); }
// How far the air that was moving with it has gone on, `after` seconds after the stop.
fn fd_slip(after: f32) -> f32 { return FD_V * FD_SLIP * (1.0 - exp(-after / FD_SLIP)); }
fn fd_erf(x: f32) -> f32 {
    let y = clamp(x, -4.0, 4.0);
    return tanh(1.1284 * y + 0.1009 * y * y * y);
}
// How high its foot hangs over the target, and how high it is `a` from the touch: from rest, under gravity, straight on through
// the land, the FD_DROP s fall ending on FD_TOUCH at every size. It stops 70 blocks up at R 8.5, and goes into the land at
// fd_vc: 82 blocks a second at R 8.5, its gravity 54.7. fold_warp.wgsl's fw_high and fw_over the same.
const FD_DROP: f32 = 1.5;          // FD_TOUCH - FD_HANG
fn fd_high(R: f32) -> f32 {
    return 5.0 * R + 19.0;
}
fn fd_over(a: f32, R: f32) -> f32 {
    let u = (a + FD_DROP) / FD_DROP;
    return fd_high(R) * (1.0 - u * u);
}
fn fd_vc(R: f32) -> f32 { return 2.0 * fd_high(R) / FD_DROP; }
// From FD_TOUCH: height of its centre over the target, and the ripple on its side (d.rip, d.ph). Nothing changes for it at
// the land: the same speed, the same gravity, straight through, like a stone into water. The land's depth hides it.
fn fd_meld(t: f32, R: f32) -> vec3<f32> {
    let a = t - FD_TOUCH;
    // (waves run up it from the neck, as they do up a drop going into water, and are gone before it is)
    return vec3<f32>(R + fd_over(a, R), 0.05 * (1.0 - exp(-a * 18.0)) * exp(-a * 3.2), a * 30.0);
}
const FD_FOOT: f32 = 0.25;
const FD_MEET: f32 = -0.08;        // when it and the land's finger meet, seconds from FD_TOUCH: fold_warp.wgsl's FW_MEET
// The metal at its foot, where it and the land become one: how high over the target, and how wide. It starts thin and widens
// fast, as a neck does (with the root of the time), keeps just over the land's swell (fold_warp.wgsl's fw_neck), and goes
// under it as the last of the drop does. fw_land's height of the land at the middle.
fn fd_sink(a: f32) -> f32 {
    return 1.0 - fd_ss(0.95, 1.95, a);
}
fn fd_wide(a: f32, R: f32) -> f32 {
    let u = clamp((a + 0.5) / 1.1, 0.0, 1.0);
    let v = 1.0 - u * u * sqrt(u);
    return 0.4725 * R * (1.0 - v * v) * fd_sink(a);
}
fn fd_land(a: f32, R: f32) -> f32 {
    let full = 1.35 * R;
    // (how high the drop's foot is as they meet)
    let meet = fd_over(FD_MEET, R);
    if (a < FD_MEET) {
        let u = clamp((a + 0.5) / (FD_MEET + 0.5), 0.0, 1.0);
        let u3 = u * u * u;
        return fd_wide(a, R) + (meet - fd_wide(FD_MEET, R)) * u3 * u3;
    }
    let s = a - FD_MEET;
    let rise = 1.0 - (1.0 - meet / full) * exp(-s / 0.16);
    return full * ((rise + 0.2 * fd_ss(0.0, 0.45, s) * exp(-1.4 * s) * sin(6.2 * s - 1.35)) * fd_sink(a) - 0.08 * fd_ss(1.7, 2.15, a) * (1.0 - fd_ss(2.15, 2.9, a)));
}
// (`h`: the drop's centre over the target)
fn fd_foot(a: f32, h: f32, R: f32) -> vec2<f32> {
    if (a < FD_MEET || a > 0.4) {
        return vec2<f32>(0.0, 1.0);
    }
    // (the drop's width at the top of the land's skirt, which is where the neck is)
    let land = fd_land(a, R);
    let y = clamp((land - h) / R, -1.0, FD_TIP);
    let rho = R * sqrt(max(fd_prof(y).x, 0.0));
    // (its height from FD_FOOT under the target, so its edge goes into the land rather than lying on it; drawn down at the end)
    let top = land + 0.02 * R * fd_ss(0.0, 0.2, a) + FD_FOOT * R - (land + 0.4 * R) * fd_ss(0.12, 0.26, a);
    return vec2<f32>(max(top, 0.0), rho + 0.12 * R);
}
// `side`: across the view, what its tip sways along.
fn fd_drop(t: f32, dist: f32, side: vec2<f32>) -> FdDrop {
    let R = clamp(dist * 0.05, 5.0, 15.0);
    let stop_h = R + fd_high(R);
    var h = stop_h;
    var sx = 1.0;
    var sy = 1.0;
    var piv = FD_PIV;
    var rip = 0.0;
    var ph = 0.0;
    var sway = vec2<f32>(0.0);
    var foot = vec2<f32>(0.0, 1.0);
    if (t < FD_STOP) {
        h = stop_h + fd_fall(FD_STOP - t);
    } else if (t < FD_TOUCH) {
        // (its centre stops, its surface doesn't: from no change at all in the first frame, one heavy settle and a smaller one
        // back, 2.2 Hz, its volume kept, all gone in half a second; a little ripple up it to the tip, and the tip left swaying a
        // little; then perfectly still, a good half second before it is let go)
        let a = t - FD_STOP;
        let e = exp(-a * 5.5) * (1.0 - fd_ss(0.25, 0.5, a));
        sy = 1.0 - 0.055 * e * sin(a * 14.0);
        sx = 1.0 / sqrt(sy);
        rip = 0.015 * e * (1.0 - exp(-a * 30.0));
        ph = a * 24.0;
        sway = side * 0.035 * e * sin(a * 10.0);
        if (t > FD_HANG) {
            // (let go: from rest where it stopped, under gravity, reaching the land on FD_TOUCH whatever its size: fd_vc)
            h = R + fd_over(t - FD_TOUCH, R);
            foot = fd_foot(t - FD_TOUCH, h, R);
        }
    } else {
        let m = fd_meld(t, R);
        h = m.x;
        rip = m.y;
        ph = m.z;
        foot = fd_foot(t - FD_TOUCH, h, R);
    }
    return FdDrop(R, stop_h, h, max(sx, 0.001), sy, piv, rip, ph, sway, foot.x, foot.y);
}
// The teardrop's side: its radius squared at height y (radii over the centre, -1 its bottom, FD_TIP its tip), and how fast
// that changes with y. Fitted to the user's picture: within 1.2% of its radius all the way up.
fn fd_prof(y: f32) -> vec2<f32> {
    let a = y + 1.0;
    let b = FD_TIP - y;
    let rb = sqrt(b);
    let q = 0.25773 + y * (0.09111 + y * (-0.07338 + y * (-0.05797 + y * 0.03297)));
    let dq = 0.09111 + y * (-0.14676 + y * (-0.17391 + y * 0.13188));
    let b2 = b * b * rb;
    return vec2<f32>(a * b2 * q, b2 * q - 2.5 * a * b * rb * q + a * b2 * dq);
}
// About the distance to its surface, in blocks, from p (from its centre); never much over, up to twice under far off.
fn fd_bead(pIn: vec3<f32>, d: FdDrop) -> f32 {
    var p = pIn / d.R;
    let sc = min(min(d.sx, d.sy), 1.0);
    p.y = (p.y - d.piv) / d.sy + d.piv;
    p = vec3<f32>(p.x / d.sx, p.y, p.z / d.sx);
    let u = clamp((p.y + 1.0) / (FD_TIP + 1.0), 0.0, 1.0);
    let o = p.xz - d.sway * u * u;
    let rr = dot(o, o);
    var e: f32;
    if (p.y >= FD_TIP) {
        e = sqrt(rr + (p.y - FD_TIP) * (p.y - FD_TIP));
    } else if (p.y <= -1.0) {
        e = sqrt(rr + (p.y + 1.0) * (p.y + 1.0));
    } else {
        let f = fd_prof(p.y);
        let m = 1.0 + d.rip * sin(d.ph - p.y * 5.0) * fd_ss(-0.9, -0.3, p.y);
        e = (rr - f.x * m * m) / sqrt(4.0 * rr + f.y * f.y * m * m * m * m + 1.0e-4);
    }
    return e * d.R * sc;
}
// Its normal at p on its surface, worked out, not differenced: the differences depend on how far from the surface the march
// stopped, and showed as contours in the chrome.
fn fd_bead_n(pIn: vec3<f32>, d: FdDrop) -> vec3<f32> {
    var p = pIn / d.R;
    p.y = (p.y - d.piv) / d.sy + d.piv;
    p = vec3<f32>(p.x / d.sx, clamp(p.y, -1.0, FD_TIP), p.z / d.sx);
    let u = (p.y + 1.0) / (FD_TIP + 1.0);
    let o = p.xz - d.sway * u * u;
    let f = fd_prof(p.y);
    let w = fd_ss(-0.9, -0.3, p.y);
    let a = d.ph - p.y * 5.0;
    let m = 1.0 + d.rip * sin(a) * w;
    let dm = -5.0 * d.rip * cos(a) * w;
    let gy = -2.0 * dot(o, d.sway) * 2.0 * u / (FD_TIP + 1.0) - (f.y * m * m + 2.0 * f.x * m * dm);
    return normalize(vec3<f32>(2.0 * o.x / d.sx, gy / d.sy, 2.0 * o.y / d.sx) + vec3<f32>(0.0, -1.0e-5, 0.0));
}
// The drop and the foot of metal it melts into, one surface: a smooth union, so the neck flows.
fn fd_foot_at(pIn: vec3<f32>, d: FdDrop) -> vec4<f32> {
    let q = pIn + vec3<f32>(0.0, d.h + FD_FOOT * d.R, 0.0);
    let s = vec3<f32>(q.x / d.pw, q.y / d.pool, q.z / d.pw);
    let l = max(length(s), 0.001);
    let g = vec3<f32>(s.x / d.pw, s.y / d.pool, s.z / d.pw);
    return vec4<f32>(g / max(length(g), 0.0001), (l - 1.0) * min(d.pool, d.pw));
}
fn fd_blend(a: f32, b: f32, k: f32) -> f32 {
    return clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
}
fn fd_sdf(pIn: vec3<f32>, d: FdDrop) -> f32 {
    let a = fd_bead(pIn, d);
    if (d.pool <= 0.0) {
        return a;
    }
    let b = fd_foot_at(pIn, d).w;
    let k = 0.22 * d.R;
    let h = fd_blend(a, b, k);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn fd_normal(pIn: vec3<f32>, d: FdDrop) -> vec3<f32> {
    let n = fd_bead_n(pIn, d);
    if (d.pool <= 0.0) {
        return n;
    }
    let f = fd_foot_at(pIn, d);
    return normalize(mix(f.xyz, n, fd_blend(fd_bead(pIn, d), f.w, 0.22 * d.R)));
}
// ---- the two glows: one soft ring round where they meet, from first touch; then, the drop gone in, one soft glow over the whole
// landing, and no flash in either ------------------------------------------------------------------------------------------
const FD_GLOW: vec3<f32> = vec3<f32>(0.86, 0.93, 1.1);
// How the land's sides differ: fold_warp.wgsl's fw_side, with its seed.
fn fd_side(ang: f32, a: f32) -> vec2<f32> {
    let s = seed_v() * 2.399;
    return vec2<f32>(
        0.52 * sin(ang + s) + 0.34 * sin(2.0 * ang + s * 1.7 - 0.9 * a) + 0.22 * sin(3.0 * ang - s * 2.3 + 1.4 * a),
        0.5 * sin(ang - s * 1.3 + 2.1) + 0.36 * sin(2.0 * ang + s * 0.7 + 1.1 * a) + 0.2 * sin(5.0 * ang + s * 3.1 - 1.3 * a));
}
fn fd_glow(colIn: vec3<f32>, t: f32, v: vec3<f32>, G: vec3<f32>, P: vec3<f32>, lit: f32, far: f32, d: FdDrop) -> vec3<f32> {
    let a = t - FD_TOUCH;
    if (a < FD_MEET - 0.25 || a > 3.0) {
        return colIn;
    }
    var col = colIn;
    let R = d.R;
    // (the ray's nearest to the place, and whether the land is in front of it)
    let H = G + vec3<f32>(0.0, 0.4 * R, 0.0);
    let hd = dot(H, v);
    let miss = length(H - v * hd);
    let seen = select(0.35, 1.0, far > hd - 3.0 * R);
    let rr = length(P.xz);
    // ---- the join: the land itself lit where it meets the drop, its blocks kept, and hot right at the line ---------------------
    // (a first warmth as the gap closes, all of it the moment they touch, a little over at first, and going as the drop does)
    let snap = fd_ss(FD_MEET, FD_MEET + 0.1, a);
    let g1 = (0.22 * fd_ss(FD_MEET - 0.25, FD_MEET, a) + snap * (0.78 + 0.5 * exp(-max(a - FD_MEET, 0.0) / 0.16))) * (1.0 - fd_ss(0.35, 0.85, a));
    if (g1 > 0.0) {
        let neck = select(0.15 * R, max(d.pw - 0.12 * R, 0.15 * R), d.pool > 0.0);
        if (lit > 0.0) {
            // (uneven round it, the way the land's skirt is)
            let L = fd_side(atan2(P.z, P.x) + rr / (3.2 * R), a);
            let edge = neck * (1.0 + 0.12 * L.x);
            let x = max(rr - edge, 0.0);
            let e = exp(-x / ((0.55 + 0.22 * L.y) * R)) * exp(-max(P.y - fd_land(a, R), 0.0) / (0.8 * R));
            let hot = exp(-abs(rr - edge) / (0.14 * R));
            col = col + (col * 1.2 * e + (col * 1.1 + FD_GLOW * 0.1) * hot * e) * g1 * lit;
        }
        col = col + FD_GLOW * 0.09 * g1 * seen * exp(-miss * miss / (2.0 * R * R));
    }
    // ---- all of it -----------------------------------------------------------------------------------------------------------
    // (what it took in, coming up through the land as it closes and going out through the land's heaving)
    let g2 = fd_ss(0.25, 0.75, a) * (1.0 - fd_ss(0.75, 3.0, a));
    if (g2 > 0.0) {
        let wide = R * (3.0 + 1.0 * fd_ss(0.3, 3.0, a));
        if (lit > 0.0) {
            let x = rr / wide;
            col = col + (col * 1.0 + FD_GLOW * 0.03) * exp(-x * x) * exp(-max(abs(P.y) - 6.0, 0.0) / (1.2 * R)) * g2 * lit;
        }
        col = col + FD_GLOW * 0.05 * g2 * seen * exp(-miss * miss / (wide * wide * 0.9));
    }
    return col;
}
// The light on smoke and dust: the Payload's.
fn fd_light() -> FdLight {
    let sun = normalize(frame.sun.xyz);
    let day = smoothstep(-0.2, 0.1, sun.y);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    let skyl = srgb_to_linear(frame.sky_color.rgb);
    let amb = mix(vec3<f32>(0.03, 0.035, 0.05), skyl * 0.85 + vec3<f32>(0.04), day);
    let sunc = mix(vec3<f32>(1.35, 1.24, 1.06), mix(vec3<f32>(1.5, 0.68, 0.3), vec3<f32>(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun.y)), warm) * sun_up + vec3<f32>(0.07, 0.09, 0.14) * moon;
    return FdLight(L, sunc, amb, mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day));
}
// The wake: the Payload's trail on the droplet's straight fall, one piece: a cord of lumpy smoke hung in the sky where it came
// down, its lumps fixed where they were laid, tight off the tip and swelling with age, pale high up and dark low down, with the
// flame in its first fifth of a second. After the stop the last of it keeps falling, past the droplet and into the land.
fn fd_trail(v: vec3<f32>, C: vec3<f32>, d: FdDrop, t: f32, px: f32, li: FdLight, far: f32) -> FdMist {
    var m = FdMist(vec3<f32>(0.0), 0.0, vec3<f32>(0.0));
    let a2 = max(dot(v.xz, v.xz), 1.0e-4);
    let sc = dot(C.xz, v.xz) / a2;
    if (sc <= 0.0 || sc > far) {
        return m;
    }
    let after = max(t - FD_STOP, 0.0);
    let ycl = v.y * sc - C.y;                    // how far over the droplet's centre the ray passes the fall's line
    let gy = ycl + d.h;                          // over the land
    if (gy < -1.0) {
        return m;
    }
    let tipy = FD_TIP * d.R;
    let yw = ycl + d.h - d.stop_h;
    // (the last of the wake carried on down, less of it the higher up)
    let laid = yw + fd_slip(after) * exp(-max(yw, 0.0) / 170.0) - tipy;
    let head = d.h - d.stop_h;
    let on = fd_ss(head - 0.1 * d.R, head + 0.9 * d.R, laid);
    if (on <= 0.0) {
        return m;
    }
    let te = FD_STOP - fd_fall_inv(laid);
    let age = max(t - te, 0.0);
    let dive = fd_ss(1.0, 3.0, te);
    let smk = fd_ss(1800.0, 500.0, laid);
    // (it wanders as it ages, the wind having it)
    let wa = min(age, 9.0);
    let bend = vec2<f32>(sin(laid * 0.0071 + 1.3) + 0.5 * sin(laid * 0.019), cos(laid * 0.0053) + 0.5 * sin(laid * 0.023 + 2.0)) * wa * 1.5;
    let off = v.xz * sc - (C.xz + bend);
    let hx = length(off);
    // (tight off the tip; where the air it has dragged down meets the land it spreads)
    let flare = 10.0 * fd_ss(26.0, 0.0, gy) * fd_ss(0.0, 0.1, after);
    let rad = mix(0.3 * d.R, 0.72 * d.R + 1.5, 1.0 - exp(-age / 0.14)) + 4.2 * sqrt(age) + flare;
    if (hx >= rad * 3.4) {
        return m;
    }
    let sn = max(sqrt(a2), 0.08);
    let sw = 2.2 * rad + 3.0;
    // (its lumps twisted round it, the wind of the fall winding the rope the fire is wound round the droplet with)
    let tw = laid * 0.045 + seed_v();
    let ct = cos(tw);
    let st = sin(tw);
    let across = vec3<f32>(ct * off.x - st * off.y, 0.0, st * off.x + ct * off.y) / sw + vec3<f32>(seed_v() * 0.31, seed_v() * 0.17, 0.0);
    let lv = log2(sw / 8.0);
    let lk = floor(lv);
    let lf = lv - lk;
    let sA = 8.0 * exp2(lk);
    let lp = vec3<f32>(0.0, laid, 0.0);
    let qa = lp / sA + across + vec3<f32>(lk * 17.3, lk * 5.1, 0.0);
    let qb = lp / (2.0 * sA) + across + vec3<f32>((lk + 1.0) * 17.3, (lk + 1.0) * 5.1, 0.0);
    let lsp = 1.0 / sqrt(lf * lf + (1.0 - lf) * (1.0 - lf));
    let qs = 1.0 / sw;
    let along = sc * px / sn * qs;
    let thru = 2.0 * sqrt(max(2.1 * rad * rad - hx * hx, 0.0)) * abs(v.y) / sn * qs + 1.0e-3;
    let w1 = min(saturate(2.0 * sqrt(1.0 / thru)), saturate(2.0 - 10.0 * along));
    let w2 = min(saturate(2.0 * sqrt(0.385 / thru)), saturate(2.0 - 10.0 * along * 2.6));
    let w3 = min(saturate(2.0 * sqrt(0.164 / thru)), saturate(2.0 - 10.0 * along * 6.1));
    var n1 = 0.5;
    var n2 = 0.5;
    var n3 = 0.5;
    if (w1 > 0.0) {
        let o = vec3<f32>(0.0, 0.0, 0.06 * age);
        n1 = 0.5 + (mix(gnoise3(qa + o), gnoise3(qb + o), lf) - 0.5) * lsp;
    }
    if (w2 > 0.0) {
        let o = vec3<f32>(4.0, 0.08 * age, 1.0);
        n2 = 0.5 + (mix(gnoise3(qa * 2.6 + o), gnoise3(qb * 2.6 + o), lf) - 0.5) * lsp;
    }
    if (w3 > 0.0) {
        let o = vec3<f32>(1.0, 7.0, 0.15 * age);
        n3 = 0.5 + (mix(gnoise3(qa * 6.1 + o), gnoise3(qb * 6.1 + o), lf) - 0.5) * lsp;
    }
    let puff = 0.5 + 0.72 * w1 * (n1 - 0.5) + 0.42 * w2 * (n2 - 0.5) + 0.16 * w3 * (n3 - 0.5);
    let rw = rad * (0.45 + puff);
    let rr = hx / rw;
    let prof = exp(-rr * rr * 1.4) * fd_ss(2.3, 1.5, rr);
    let gin = 1.0 / max(sn, 0.5);
    let thr = mix(0.32, 0.12, smk) + 0.38 * fd_ss(1.5, 18.0, age);
    let mm = (puff - thr) * 3.2 + 0.3 * exp(-age / 0.8);
    let sl = 3.2 * 0.14 * sqrt(0.384 * (1.0 - w1 * w1) + 0.09 * (1.0 - w2 * w2) + 0.0064 * (1.0 - w3 * w3)) + 1.0e-3;
    // (a soft max(mm, 0): past 30 its exp would run out, and it is mm)
    let mz = mm / sl;
    let dens = saturate(select(sl * log(1.0 + exp(max(mz, -30.0))), mm, mz > 30.0));
    let sig = (0.26 * exp(-age / 2.6) + 0.25 * exp(-age / 0.7) * dive) * mix(0.35, 1.0, smk);
    // (its foot lifting off the land as it thins, the droplet left in the clear)
    let foot = 42.0 * pow(max(after - 0.7, 0.0), 2.0);
    let life = (1.0 - fd_ss(9.0, 14.0, t)) * fd_ss(0.1, 0.9, t) * fd_ss(foot - 1.0, foot + 50.0, gy + 40.0 * step(after, 0.7));
    let dtau = sig * prof * dens * 1.6 * rad * gin * on * life;
    let nrm = normalize(vec3<f32>(off.x, 0.0, off.y) - v * (0.6 * rad) + vec3<f32>(0.0, 1.0e-4, 0.0));
    let ln = 0.5 + w1 * (n1 - 0.5);
    let lit = (0.35 + 0.65 * saturate(dot(nrm, li.L) * 0.5 + 0.5)) * (0.6 + 0.8 * ln * ln);
    var alb = mix(vec3<f32>(0.5, 0.5, 0.52), vec3<f32>(0.17, 0.145, 0.125), smk);
    alb = mix(alb, alb * 1.35 + vec3<f32>(0.03), fd_ss(4.0, 20.0, age));
    var c = alb * (li.sunc * lit * 0.85 + li.amb * (0.6 + 0.4 * ln));
    // (just behind it the smoke is lit by its own flame)
    c = c + vec3<f32>(1.5, 0.55, 0.14) * exp(-age / 0.16) * dive * (0.4 + 0.6 * ln);
    c = mix(c, li.haze, (1.0 - exp(-sc / 3000.0)) * 0.75);
    m.c = c;
    m.tau = dtau;
    // (the flame: its root white-yellow off the tip, orange back along it, in tongues, not a beam)
    let fw = rad * (0.8 - 0.35 * saturate(age / 0.3));
    let fprof = exp(-pow(hx / max(fw, 0.5), 2.0) * 1.6);
    let fl = exp(-age / 0.1) * dive * on;
    m.glow = mix(vec3<f32>(1.5, 0.42, 0.06), vec3<f32>(2.2, 1.1, 0.3), exp(-age / 0.04)) * fl * fprof * fd_ss(0.34, 0.6, puff + 0.1 * sin(t * 40.0 + laid * 0.2));
    // (high up, the hot streak of air it leaves, white, cooling within a second)
    let fh = (1.0 - dive) * exp(-age / 0.45) * life;
    m.glow = max(m.glow, vec3<f32>(2.4, 2.3, 2.1) * fh * min(fprof * rad * 0.3, 1.2));
    return m;
}
// The fire on the droplet: a skin of flame wrapped round the teardrop itself, thin and white on the round end it is falling on,
// streaming up its sides in ribbons that wind round it, drawn in to the tip where it goes dark and turns into the wake. Marched
// through, up to `s_end`. At the stop the droplet is left behind: the skin goes on down in its shape, swelling, and is gone.
fn fd_sheath(colIn: vec3<f32>, v: vec3<f32>, C: vec3<f32>, d: FdDrop, t: f32, s_end: f32, jit: f32) -> vec3<f32> {
    let after = max(t - FD_STOP, 0.0);
    let hi = fd_ss(FD_STOP - 2.8, FD_STOP - 0.3, t);
    let on = hi * exp(-after / 0.09);
    if (on < 0.01) {
        return colIn;
    }
    let grow = 1.0 + after * 2.5;
    let Cg = C - vec3<f32>(0.0, min(fd_slip(after), max(d.h - d.R, 0.0)), 0.0);
    let bc = Cg + vec3<f32>(0.0, 0.36 * d.R * grow, 0.0);
    let br = 1.8 * d.R * grow;
    let cd = dot(bc, v);
    let b2 = dot(bc, bc) - cd * cd;
    if (cd < 0.0 || b2 > br * br) {
        return colIn;
    }
    let hc = sqrt(br * br - b2);
    let s0 = max(cd - hc, 0.05);
    let s1 = min(cd + hc, s_end);
    if (s1 <= s0) {
        return colIn;
    }
    const N = 24;
    let ds = (s1 - s0) / f32(N);
    var T = 1.0;
    var E = vec3<f32>(0.0);
    let dn = ds / (d.R * grow);
    for (var i = 0; i < N; i += 1) {
        let q = (v * (s0 + (f32(i) + jit) * ds) - Cg) / (d.R * grow);
        // (how far off its side, across: the same either side of the tip, as a true distance isn't cheaply)
        let ro = length(q.xz);
        var e: f32;
        if (q.y >= FD_TIP) {
            e = length(vec2<f32>(ro, q.y - FD_TIP));
        } else if (q.y <= -1.0) {
            e = length(vec2<f32>(ro, q.y + 1.0));
        } else {
            e = ro - sqrt(max(fd_prof(q.y).x, 0.0));
        }
        let hgt = saturate((q.y + 1.0) / (FD_TIP + 1.0));
        let th = mix(0.1, 0.34, hgt) * (1.0 - fd_ss(0.8, 1.0, hgt) * 0.5) * (1.0 + after * 16.0);
        if (e > th * 2.4 || e < -0.06) {
            continue;
        }
        // (ribbons running up it and winding half way round on the way; seamless round it)
        let az = atan2(q.z, q.x) + hgt * 3.8 + seed_v();
        let ca = cos(az);
        let sa = sin(az);
        let fl = q.y * 0.55 - t * 6.0;
        let n = gnoise3(vec3<f32>(ca * 1.2, sa * 1.2, fl)) * 0.72 + gnoise3(vec3<f32>(ca * 3.0, sa * 3.0, fl * 2.0 + 3.0)) * 0.28;
        let tt = th * (0.5 + 1.1 * n);
        let sh = exp(-pow(max(e, 0.0) / tt, 2.0));
        let nose = exp(-hgt * 7.0);
        let rib = mix(fd_ss(0.46, 0.6, n), 1.0, nose * 0.3);
        let dens = sh * rib * on;
        let x = saturate(hgt * 1.1 + max(e, 0.0) / tt * 0.25);
        var c = mix(vec3<f32>(2.1, 1.25, 0.5), vec3<f32>(1.8, 0.55, 0.08), fd_ss(0.05, 0.4, x));
        c = mix(c, vec3<f32>(0.5, 0.07, 0.01), fd_ss(0.45, 0.9, x));
        E = E + c * T * dens * dn * 2.2 / (1.0 + after * 26.0);
        // (dark round the tip: the flame burning out into smoke, wrapped in to its point)
        let sm = dens * fd_ss(0.42, 0.85, hgt) * dn * 5.0;
        E = E + vec3<f32>(0.09, 0.075, 0.07) * T * sm;
        T = T * exp(-sm - dens * dn * 0.8);
    }
    return colIn * T + E;
}
// The dust: the air that came down with it hits the land and goes by, a faint breath of it close round the target, low, and gone
// in a second or so: enough to see the air arrive, the land clear through it. Marched, up to `s_end`.
fn fd_dust(colIn: vec3<f32>, v: vec3<f32>, G: vec3<f32>, a: f32, s_end: f32, land: vec4<f32>, li: FdLight, jit: f32) -> vec3<f32> {
    if (a <= 0.0 || a > 1.6) {
        return colIn;
    }
    let rf = 6.0 + 44.0 * (1.0 - exp(-a / 0.55));
    let w = 5.0 + 4.0 * a;
    let top = 4.0 + 3.0 * (1.0 - exp(-a / 0.45)) + 0.4 * a;
    let fade = (1.0 - fd_ss(0.3, 1.6, a)) * fd_ss(0.0, 0.08, a);
    let ylo = min(G.y + land.y, G.y) - 2.0;
    let yhi = max(G.y + land.y, G.y) + top * 2.0;
    // (the ray in the slab of air it fills, and in the disc out to the front)
    var s0 = 0.05;
    var s1 = s_end;
    if (abs(v.y) > 1.0e-5) {
        let ya = ylo / v.y;
        let yb = yhi / v.y;
        s0 = max(s0, min(ya, yb));
        s1 = min(s1, max(ya, yb));
    }
    let a2 = max(dot(v.xz, v.xz), 1.0e-6);
    let bb = -dot(v.xz, G.xz);
    let Ro = rf * 1.14 + w * 2.0;
    let dout = bb * bb - a2 * (dot(G.xz, G.xz) - Ro * Ro);
    if (dout <= 0.0) {
        return colIn;
    }
    let qd = sqrt(dout);
    s0 = max(s0, (-bb - qd) / a2);
    s1 = min(s1, (-bb + qd) / a2);
    if (s1 <= s0) {
        return colIn;
    }
    const N = 14;
    let ds = (s1 - s0) / f32(N);
    var T = 1.0;
    var C = vec3<f32>(0.0);
    let alb = vec3<f32>(0.34, 0.29, 0.23);
    for (var i = 0; i < N; i += 1) {
        let p = v * (s0 + (f32(i) + jit) * ds) - G;
        // (its height over the land: the land under this pixel's own end, near it)
        let dl = p.xz - land.zw;
        let gh = clamp(land.x, -14.0, 14.0) * exp(-dot(dl, dl) / 900.0);
        let y = p.y - gh;
        if (y < -1.5) {
            continue;
        }
        let r = length(p.xz);
        let ang = atan2(p.z, p.x);
        let wob = vnoise(vec2<f32>(cos(ang) * 2.4 + 5.0, sin(ang) * 2.4 + a * 0.2));
        let rl = rf * (0.9 + 0.2 * wob);
        let x = (r - rl) / w;
        if (x > 2.2) {
            continue;
        }
        // (carried out with the front, and rising)
        let n = fbm3(vec3<f32>(p.x, p.y * 1.5 - a * 9.0, p.z) * 0.075 - vec3<f32>(p.x, 0.0, p.z) / max(r, 1.0) * (rf * 0.075));
        let ht = top * (0.5 + 1.0 * n);
        let roll = exp(-x * x * 1.2) * exp(-pow(max(y, 0.0) / ht, 2.0));
        let haze = 0.025 * fd_ss(0.2, -1.2, x) * exp(-max(y, 0.0) / (top * 0.5));
        let dens = max(fd_ss(0.36, 0.62, n + 0.2 * exp(-x * x)) * roll, haze) * fade;
        if (dens < 0.003) {
            continue;
        }
        let dt = dens * ds * 0.035;
        let lit = 0.55 + 0.45 * saturate(y / ht) + 0.35 * saturate(dot(normalize(vec3<f32>(p.x / max(r, 1.0), 0.6, p.z / max(r, 1.0))), li.L));
        C = C + alb * (li.sunc * lit * 0.75 + li.amb * 0.9) * T * (1.0 - exp(-dt));
        T = T * exp(-dt);
    }
    return colIn * T + C;
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
// The droplet over the picture (`col` so far, `far` how far the scene is along this ray); `land` the land this pixel's ray ends
// on: its height over the target (x, kept near), where it is (zw), for the dust.
fn fd_droplet(colIn: vec3<f32>, t: f32, v: vec3<f32>, G: vec3<f32>, C: vec3<f32>, d: FdDrop, far: f32, uv: vec2<f32>, aspect: f32, land: vec4<f32>, li: FdLight, jit: f32) -> vec3<f32> {
    var col = colIn;
    let px = frame.view_params.w / frame.resolution.y;
    let q = project_rel(C);
    let after = max(t - FD_STOP, 0.0);
    let hi = fd_ss(FD_STOP - 2.6, FD_STOP - 0.2, t);
    // ---- the wake, hung in the sky -----------------------------------------------------------------------------------------
    if (t < 14.0) {
        let m = fd_trail(v, C, d, t, px, li, far);
        if (m.tau > 0.0) {
            col = mix(col, m.c, 1.0 - exp(-m.tau));
        }
        col = col + m.glow;
    }
    // ---- the glint: from far up a star, for as long as it is smaller than a few pixels ------------------------------------
    if (q.z > 0.0 && t < FD_STOP) {
        let dp = (uv - q.xy) * vec2<f32>(aspect, 1.0);
        let dd = length(dp);
        let ang = d.R / max(length(C), 1.0);
        let small = 1.0 - fd_ss(0.002, 0.012, ang);
        let tw = 0.85 + 0.15 * sin(t * 37.0);
        let star = exp(-dd / 0.0024) * 2.4 + exp(-abs(dp.y) / 0.0016) * exp(-abs(dp.x) / 0.05) * 1.1 + exp(-abs(dp.x) / 0.0016) * exp(-abs(dp.y) / 0.03) * 0.7;
        col = col + vec3<f32>(1.0, 0.96, 0.9) * star * small * tw;
    }
    // ---- a steady soft halo round it while it hangs, so it can be found on a small screen, and no flicker in it ------------
    if (q.z > 0.0 && t >= FD_STOP && t < FD_MELD) {
        let dh = length((uv - q.xy) * vec2<f32>(aspect, 1.0));
        col = col + vec3<f32>(0.9, 0.95, 1.05) * exp(-dh / 0.016) * 0.2 * fd_ss(FD_STOP + 0.1, FD_STOP + 0.8, t) * (1.0 - fd_ss(FD_TOUCH - 0.2, FD_MELD, t));
    }
    // ---- the metal --------------------------------------------------------------------------------------------------------
    var s_end = far;
    let bc = C + vec3<f32>(0.0, 0.36 * d.R, 0.0);
    let bcd = dot(bc, v);
    // (with the foot of metal in it, a sphere taking that in too)
    let bR = select(1.75 * d.R * max(d.sx, 1.0), max(1.75 * d.R, length(bc - G) + 1.2 * d.pw + d.R), d.pool > 0.0);
    if (length(bc - v * bcd) < bR && bcd > 0.0) {
        var s = max(bcd - bR, 0.05);
        var best = 1.0e9;
        var sb = s;
        var hit = false;
        for (var i = 0; i < 56; i += 1) {
            let e = fd_sdf(v * s - C, d);
            let rel = e / (px * s);
            if (rel < best) {
                best = rel;
                sb = s;
            }
            if (rel < 0.1) {
                hit = true;
                sb = s + e + fd_sdf(v * (s + e) - C, d);
                break;
            }
            s += max(e, 0.15 * px * s);
            if (s > bcd + bR) {
                break;
            }
        }
        // (the edge smoothed over a pixel: a post pass has no other)
        let cov = saturate(1.0 - best);
        if (cov > 0.0 && sb < far + 0.4) {
            let p = v * sb - C;
            let n = fd_normal(p, d);
            let r = reflect(v, n);
            var c = fd_env(r, normalize(frame.sun.xyz));
            // (the real land in it: where the reflection meets the ground, read off the picture, the picture's edge if it is off it,
            // so its underside shows the land's own colours and not a grey)
            if (r.y < 0.15) {
                let up = max(-r.y, 0.03);
                let ro = project_rel(v * sb + r * clamp((dot(v * sb, vec3<f32>(0.0, 1.0, 0.0)) - G.y) / up, 8.0, 400.0));
                // (what lies behind the eye: the land nearest it, the picture's foot)
                let px_ = select(vec2<f32>(0.5, 0.92), clamp(ro.xy, vec2<f32>(0.02, 0.45), vec2<f32>(0.98, 0.98)), ro.z > 0.0);
                c = mix(c, fd_sample(px_) * 1.05, 0.85 * fd_ss(0.15, -0.05, r.y));
            }
            let fres = pow(1.0 - max(dot(-v, n), 0.0), 4.0);
            var mc = c * vec3<f32>(0.9, 0.93, 0.98) * (0.86 + 0.5 * fres);
            // (the sheath's heat on it as it falls, out of it within a second of the stop)
            mc = mc + vec3<f32>(1.5, 0.55, 0.12) * fd_ss(-0.45, -1.0, n.y) * hi * exp(-after / 0.3);
            col = mix(col, mc, cov);
            if (hit) {
                s_end = min(s_end, sb);
            }
        }
    }
    // ---- the fire round it, and the dust the air raises -----------------------------------------------------------------
    col = fd_sheath(col, v, C, d, t, s_end, jit);
    // (the dust over it thinned: it stays the thing to look at)
    let dusty = fd_dust(col, v, G, after - (d.stop_h - d.R) / FD_V, s_end, land, li, jit);
    return mix(dusty, col, select(0.0, 0.7, s_end < far));
}

// ---- the slam's dust: what it drove out of the ground ------------------------------------------------------------------------
// A wall of dust and ash thrown out of the crater on the frame it appears, running out over the land and slowing, and the
// crater's air full of what fell into it, thinning as it rises. `a`: seconds since the slam.
const FDB_LEN: f32 = 9.0;
const FDB_RIM: f32 = 270.0;
const FDB_OUT: f32 = 280.0;
const FDB_HIGH: f32 = 160.0;
const FDB_STEPS: i32 = 14;
fn fdb_front(a: f32) -> f32 { return FDB_RIM + FDB_OUT * (1.0 - exp(-a * 0.85)); }
fn fdb_high(a: f32) -> f32 { return 22.0 + FDB_HIGH * (1.0 - exp(-a * 1.0)); }
/// How thick the dust is at `p` (from the target).
fn fdb_density(p: vec3<f32>, a: f32) -> f32 {
    let r = length(p.xz);
    let h = fdb_high(a);
    let width = 34.0 + 34.0 * a;
    let x = (r - fdb_front(a)) / width;
    // (the wall leans out, its foot ahead of its top)
    let lean = (r - fdb_front(a) + 0.5 * max(p.y, 0.0)) / width;
    let wall = 0.55 * fd_ss(0.0, 0.5, a) * exp(-min(x * x, lean * lean)) * fd_ss(h * (0.75 + 0.25 * fd_ss(0.0, 200.0, r)), h * 0.2, p.y);
    // (the crater's air: from the floor up over the rim, whatever is above it thin)
    // (only once the panels have fallen: it is what they drive up, and while they fall they are the picture)
    let air = 0.16 * fd_ss(3.6, 5.6, a) * fd_ss(350.0, 170.0, r) * fd_ss(h * 0.9, -30.0, p.y) * (1.0 - fd_ss(3.0, FDB_LEN - 0.5, a));
    let d = (wall + air) * pow(1.0 - a / FDB_LEN, 1.6);
    if (d < 0.01) { return 0.0; }
    let q = p * 0.021 + vec3<f32>(0.0, -a * 0.35, 0.0) + normalize(vec3<f32>(p.x, 0.0, p.z) + vec3<f32>(0.01)) * a * -0.3;
    let n = 0.6 * vnoise3(q) + 0.28 * vnoise3(q * 2.3) + 0.12 * vnoise3(q * 5.1);
    return d * fd_ss(0.3, 0.72, n);
}
/// The picture behind `col` seen through the dust, along `v` from `ro` (from the target), up to `far`.
fn fd_blast(colIn: vec3<f32>, ro: vec3<f32>, v: vec3<f32>, far: f32, a: f32, jit: f32) -> vec3<f32> {
    let reach = fdb_front(a) + 90.0 + 30.0 * a;
    let top = fdb_high(a) * 1.15;
    // (only the slab of air it can be in, and the circle round the target)
    let b = dot(ro.xz, v.xz);
    let aa = max(dot(v.xz, v.xz), 1.0e-5);
    let c = dot(ro.xz, ro.xz) - reach * reach;
    let disc = b * b - aa * c;
    if (disc <= 0.0) { return colIn; }
    let sq = sqrt(disc);
    var s0 = max((-b - sq) / aa, 0.0);
    var s1 = min((-b + sq) / aa, far);
    let lo = -110.0;
    if (abs(v.y) > 1.0e-4) {
        let ya = (lo - ro.y) / v.y;
        let yb = (top - ro.y) / v.y;
        s0 = max(s0, min(ya, yb));
        s1 = min(s1, max(ya, yb));
    } else if (ro.y < lo || ro.y > top) {
        return colIn;
    }
    if (s1 <= s0) { return colIn; }
    let sun = normalize(frame.sun.xyz);
    let day = fd_ss(-0.12, 0.25, sun.y);
    let step = (s1 - s0) / f32(FDB_STEPS);
    var seen = 1.0;
    var light = vec3<f32>(0.0);
    for (var i = 0; i < FDB_STEPS; i += 1) {
        let p = ro + v * (s0 + (f32(i) + jit) * step);
        let d = fdb_density(p, a);
        if (d <= 0.0) { continue; }
        // (lit from above and towards the sun; dark ash at its foot, paler dust as it rises)
        let up = fd_ss(-20.0, fdb_high(a), p.y);
        let lit = fdb_density(p + sun * 14.0, a);
        let c = mix(vec3<f32>(0.1, 0.09, 0.085), vec3<f32>(0.5, 0.45, 0.39), up) * (0.35 + 0.65 * exp(-lit * 2.4)) * (0.16 + 0.84 * day);
        let t = 1.0 - exp(-d * step * 0.065);
        light += c * t * seen;
        seen *= 1.0 - t;
        if (seen < 0.02) { break; }
    }
    return colIn * seen + light;
}

// The fold's clock: fold_warp.wgsl's fw_tau.
fn fd_tau(t: f32) -> f32 {
    if (t < FD_BEAT) { return t; }
    if (t < FD_REL) { return FD_BEAT; }
    let u = clamp((t - FD_REL) / (FD_SLAM0 - FD_REL), 0.0, 1.0);
    return FD_BEAT - (FD_BEAT - 20.0) * u * u * (3.11 + u * (-5.05 + u * 2.94));
}
// Where the branch's tip ends: fold_warp.wgsl's fw_seat and fw_turned with the sphere shut, the same (`the_warp_keeps_the_beats`).
fn fd_radius(d: f32, y: f32) -> f32 {
    return max(max(d * 1.3, 170.0), y * 1.15);
}
fn fd_rim(d: f32) -> f32 {
    return max(620.0, d + 480.0);
}
const FD_PI: f32 = 3.14159265;
const FD_TUBE_W: f32 = 0.5933;     // fold_warp.wgsl's: the tube as it holds
const FD_TUBE_R0: f32 = 0.352;
const FD_LEN: f32 = 480.0;
fn fd_seat(d: f32, mh: f32) -> vec3<f32> {
    let S = fd_radius(d, mh);
    let rim = fd_rim(d);
    let r0 = (max(FD_LEN, d) + 170.0) * FD_TUBE_R0;
    let rc = mix(700.0, S, FD_TUBE_W);
    let fm = mix(3.2, FD_PI, FD_TUBE_W);
    let u = d - r0;
    if (u <= 0.0) {
        return vec3<f32>(d, mh, 0.0);
    }
    let e = u / (rc * fm);
    let x = e * 1.5707963;
    let ex = exp(-e);
    let f = min(fm * mix(1.0 - ex, 0.63662 * atan(x), FD_TUBE_W), 3.3);
    let lip = 34.0 * FD_TUBE_W * pow(fd_ss(rim * 0.8, rim, d), 2.0);
    let yy = mh * mix(ex, 1.0 / (1.0 + x * x), FD_TUBE_W) - lip;
    let s = sin(f);
    let c = cos(f);
    return vec3<f32>(r0 + (rc - yy) * s, rc * (1.0 - c) + yy * c, f);
}
fn fd_turned(du: f32, dy: f32, at: vec3<f32>, d: f32, mh: f32) -> vec2<f32> {
    let c = cos(at.z);
    let s = sin(at.z);
    return vec2<f32>(d + du * c + dy * s, -du * s + dy * c + mh);
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
    let gq = (tgt - cam) - camera_rest();
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let off = world_offset(uv, select(d0, 0.5, sky0));
    let v = normalize(off);
    let far = select(length(off), 1.0e7, sky0);

    // ---- where the branch's tip has gone at the touch: on the far side of the sphere's floor, the frame the sphere is in going
    // with the player. The eye never moves in that frame: it is where it stood as they fired, whatever they have done since -------
    let mh = me.y - tgt.y;
    let te = (me.xz - tgt.xz) / max(dist, 0.001);
    let at = fd_seat(dist, mh);
    let tip = fd_turned(-at.x, -at.y, at, dist, mh);
    let pt = project_rel(tgt - me + vec3<f32>(te.x * tip.x, tip.y - 1.62, te.y * tip.x));

    var col = fd_sample(uv);

    // ---- the void: the sky going out as the land closes, and under the land where it has left ------------------------------
    if (sky0 && t > FD_FOLD - 0.5) {
        let tau = fd_tau(t);
        let dark = fd_ss(FD_FOLD + 3.0, 30.0, tau);
        let under = fd_ss(0.03, -0.015, v.y) * fd_ss(FD_FOLD, FD_FOLD + 1.2, t) * (1.0 - fd_ss(FD_SLAM4, FD_SLAM4 + 0.2, t));
        col = mix(col, fd_stars(v), max(dark, under));
        // ---- land that isn't there. Far land not loaded leaves gaps in what the sheet carries, which would show the void: the stars belong to the
        // tears and the hole in the roof. A gap the land closes round takes the land's colours round it, but for the hole: a ray that comes near
        // the axis, on which the hole's mouth lies however far down it has come ------------------------------------------------------------
        if (t < FD_SLAM4) {
            var near = vec3<f32>(0.0);
            var found = 0.0;
            let step = res.y / 1440.0;
            for (var i = 0; i < 8; i += 1) {
                let ang = f32(i) * 0.7853982 + 0.3;
                let dir = vec2<f32>(cos(ang), sin(ang)) * step / res;
                for (var j = 0; j < 3; j += 1) {
                    let uv2 = uv + dir * (22.0 + 44.0 * f32(j * (j + 1)));
                    if (!is_sky(depth_at(uv2))) {
                        near += fd_sample(uv2);
                        found += 1.0;
                        break;
                    }
                }
            }
            // (the axis, turned as the land is: how near this ray comes to it. Filled, a hole under the rays' reach grew an averaged star)
            let ax0 = tgt - me + vec3<f32>(te.x * tip.x, tip.y - 1.62, te.y * tip.x);
            let u1 = fd_turned(-at.x, 1000.0 - at.y, at, dist, mh);
            let ax = normalize(vec3<f32>(te.x * (u1.x - tip.x), u1.y - tip.y, te.y * (u1.x - tip.x)));
            let cr = cross(v, ax);
            let miss = abs(dot(ax0, cr)) / max(length(cr), 0.001);
            let hole = fd_ss(27.0, 29.0, tau) * fd_ss(1100.0, 800.0, miss);
            if (found > 5.5) {
                col = mix(col, near / found, fd_ss(5.5, 7.5, found) * (1.0 - hole));
            }
        }
    }

    // ---- the droplet -------------------------------------------------------------------------------------------------------
    if (t < 10.0) {
        let side = normalize(vec2<f32>(-gq.z, gq.x) + vec2<f32>(0.0, 1.0e-4));
        let d = fd_drop(t, dist, side);
        let li = fd_light();
        let jit = ign(in.position.xy);
        var land = vec4<f32>(0.0);
        if (!sky0) {
            let P = off - gq;
            land = vec4<f32>(clamp(P.y, -40.0, 40.0), 0.0, P.xz);
            // (its shadow on the land, closing up as it comes down)
            let sr = d.R * (1.6 + 0.06 * d.h);
            let shadow = exp(-dot(P.xz, P.xz) / (sr * sr)) * 0.62 * exp(-abs(P.y) / 12.0) * fd_ss(420.0, 60.0, d.h) * (1.0 - fd_ss(FD_TOUCH, FD_MELD, t));
            col = col * (1.0 - shadow);
            // (the fire's light on the land under it, coming up as it does, and going out with the air that hits the land)
            let lr = d.h * 0.8 + 6.0;
            let fl = fd_ss(FD_STOP - 0.7, FD_STOP, t) * exp(-max(t - FD_STOP, 0.0) / 0.16) / (1.0 + dot(P.xz, P.xz) / (lr * lr));
            col = col + col * vec3<f32>(2.6, 1.15, 0.4) * fl * (14.0 / (lr + 20.0)) * exp(-max(abs(P.y) - 6.0, 0.0) / 16.0);
        }
        let C = gq + vec3<f32>(0.0, d.h, 0.0);
        // (what the land has reached up inside the drop is taken into it, not seen through it)
        // (until the land has closed over it: a pixel of land in it melts from drop to land as that happens, and has little of the
        // join's light, or the drop's own pixels burn white)
        let swallowed = t >= FD_TOUCH + FD_MEET && t < FD_MELD && !sky0 && fd_bead(off - C, d) < 0.0;
        let under = col;
        col = fd_droplet(under, t, v, gq, C, d, far, uv, aspect, land, li, jit);
        var lit = select(0.0, 1.0, !sky0);
        if (swallowed) {
            let closing = fd_ss(FD_MELD - 0.16, FD_MELD, t);
            col = mix(fd_droplet(under, t, v, gq, C, d, 1.0e7, uv, aspect, land, li, jit), col, closing);
            lit = mix(0.12, 1.0, closing * closing * closing);
        }
        col = fd_glow(col, t, v, gq, off - gq, lit, far, d);
    }

    // ---- the touch: a tiny light at the point the moment the tip reaches it, there for the stillness, gone as it runs back -----
    let dd = length((uv - pt.xy) * vec2<f32>(aspect, 1.0));
    if (t >= FD_BEAT && t < FD_REL + 0.25 && pt.z > 0.0) {
        let on = fd_ss(FD_BEAT, FD_BEAT + 0.04, t) * (1.0 - fd_ss(FD_REL - 0.02, FD_REL + 0.25, t));
        let g = 0.0022;
        col = col + vec3<f32>(1.0, 0.97, 0.92) * (exp(-dd / g) * 2.6 + exp(-dd / (g * 6.0)) * 0.3) * on;
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
    // ---- the dust the last slam drove out of the ground -------------------------------------------------------------------
    let fdb_a = t - FD_SLAM4;
    if (fdb_a > 0.0 && fdb_a < FDB_LEN) {
        col = fd_blast(col, -gq, v, far, fdb_a, hash21(uv * res));
    }
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}
