// Orbital Laser's post pass for the Fold (laser 14). The mod builds it from shaders/strike.wgsl up to its fs_main less the
// other lasers' own functions, followed by this file, and sets it for a fold strike only. Validate with
// tools/check-shader.sh.

// ---- laser 14: the fold -------------------------------------------------------------------------------------------
// The world's bending, its creases, its tears and its colours aren't here: the land's own vertices and pixels go through
// shaders/fold_warp.wgsl. This pass draws what is not the world: the droplet (its fall, its stop, its meld), the void and
// its stars where the land has left, the point, the one flash, and the dust of the slams.
// strike/fold.rs plans the sounds and the land: keep the FD_* in step with its and fold_warp.wgsl's.
const FD_STOP: f32 = 3.4;          // the middle of its brake
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
const FD_FALL: f32 = 3600.0;       // how high it starts over the target

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
// the sky to the ground. It falls hard, braking all the way (FD_B), then OVERRUN's long smooth brake (fd_brake_t) takes the rest; what
// was moving with it isn't stopped: the fire and the wake go on past it and down (fd_slip), hit the land and throw out a low
// ring of dust (fd_dust), and it shakes like a jelly for a second (fd_drop), hangs, and is let go: it falls to the land from rest.
// Its height over the land is d.h, to its centre; its bottom is d.R under that, its tip FD_TIP * d.R over it.
const FD_V: f32 = 280.0;           // how fast it is going as it stops, blocks a second
const FD_LEAD: f32 = 4.0;          // the clock starts this far before 0: its fall takes FD_LEAD + FD_STOP, time to look up (lib.rs's Strike::wait, fold.rs's FD_LEAD)
const FD_B: f32 = 27.88;           // its braking: (FD_FALL - FD_V * T) / T^2, T being FD_LEAD + FD_STOP
const FD_SLIP: f32 = 0.3;          // how soon what moved with it loses its speed, seconds
const FD_BRAKE: f32 = 0.5;         // OVERRUN's stop: it starts braking this long before FD_STOP and comes to rest about as long after it (fd_brake_t), the force rising and falling smoothly
const FD_OVER: f32 = 1.6;          // OVERRUN: how soon the air it brakes out of loses its speed, seconds
const FD_TIP: f32 = 1.72;          // the tip, in radii over the centre
const FD_PIV: f32 = -0.3;          // the point it squashes about, in radii over the centre: low, the tip does the moving
struct FdDrop { R: f32, stop_h: f32, h: f32, sx: f32, sy: f32, piv: f32, rip: f32, ph: f32, sway: vec2<f32>, pool: f32, pw: f32 }
// It comes down an arc, not a plumb line: seen from under a straight fall its whole trail lies end on, a dot. High up it is off to the player's side, so the trail is seen
// side on across the sky, and it comes round to plumb over the target by the time it stops. How far to the side it is, H over where it stops.
const FD_ARC: f32 = 820.0;
fn fd_arc(H: f32) -> f32 {
    let u = max(H, 0.0) / FD_FALL;
    return FD_ARC * u * u;
}
struct FdLight { L: vec3<f32>, sunc: vec3<f32>, amb: vec3<f32>, haze: vec3<f32> }
struct FdMist { c: vec3<f32>, tau: f32, glow: vec3<f32>, fire: vec4<f32> }
// How far over where it stops it is, `tau` seconds before it does, and when it was at that height.
fn fd_fall(tau: f32) -> f32 { return tau * (FD_V + FD_B * tau); }
fn fd_fall_inv(H: f32) -> f32 { return (sqrt(FD_V * FD_V + 4.0 * FD_B * max(H, 0.0)) - FD_V) / (2.0 * FD_B); }
// How far the air that was moving with it has gone on, `after` seconds after the stop.
fn fd_slip(after: f32) -> f32 {
    if (fd_stop() == 4) {
        // (OVERRUN: `after` is from the brake's start, and the air goes on at the speed it was doing as the drop slows away from it)
        return (FD_V + 2.0 * FD_B * FD_BRAKE) * after / (1.0 + after / FD_OVER);
    }
    return FD_V * FD_SLIP * (1.0 - exp(-after / FD_SLIP));
}
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
// How long OVERRUN's brake takes: from the speed it has at FD_STOP - FD_BRAKE down to nothing over what is left of its fall. The speed goes by a smoothstep, so the force on it rises from nothing,
// peaks half way and dies away to nothing: no jolt at either end. Everything after the stop goes by this clock too: `fd_since`.
fn fd_brake_t() -> f32 {
    return 2.0 * fd_fall(FD_BRAKE) / (FD_V + 2.0 * FD_B * FD_BRAKE);
}
// Seconds since what was moving with it started to leave it: the stop for the rest, the brake's start for OVERRUN.
fn fd_since(t: f32) -> f32 { return max(t - select(FD_STOP, FD_STOP - FD_BRAKE, fd_stop() == 4), 0.0); }
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
    // (OVERRUN: a hard, quick, smooth brake, no dead stop)
    let brake_t = select(0.0, fd_brake_t(), fd_stop() == 4);
    let at_rest = FD_STOP - FD_BRAKE + brake_t;
    if (brake_t > 0.0 && t >= FD_STOP - FD_BRAKE && t < at_rest) {
        // (the integral of 1 - smoothstep(u); and it squashes with the force on it, its foot held back, and the settle below takes it from there)
        let u = (t - (FD_STOP - FD_BRAKE)) / brake_t;
        h = stop_h + fd_fall(FD_BRAKE) * (1.0 - 2.0 * (u - u * u * u + 0.5 * u * u * u * u));
        sy = 1.0 - 0.06 * 4.0 * u * (1.0 - u);
        sx = 1.0 / sqrt(sy);
        piv = -1.0;
    } else if (t < FD_STOP) {
        h = stop_h + fd_fall(FD_STOP - t);
    } else if (t < FD_TOUCH) {
        // (its centre stops, its surface doesn't: from no change at all in the first frame, one heavy settle and a smaller one
        // back, 2.2 Hz, its volume kept, all gone in half a second; a little ripple up it to the tip, and the tip left swaying a
        // little; then perfectly still, a good half second before it is let go)
        let a = t - max(FD_STOP, select(FD_STOP, at_rest, brake_t > 0.0));
        let e = exp(-a * 5.5) * (1.0 - fd_ss(0.25, 0.5, a));
        // (OVERRUN: the brake has taken all that up, so only the faintest settle is left)
        let wob = select(1.0, 0.15, fd_stop() == 4);
        sy = 1.0 - 0.055 * wob * e * sin(a * 14.0);
        sx = 1.0 / sqrt(sy);
        rip = 0.015 * wob * e * (1.0 - exp(-a * 30.0));
        ph = a * 24.0;
        sway = side * 0.035 * wob * e * sin(a * 10.0);
        if (fd_stop() == 3) {
            // (SQUASH: it takes it all itself, its foot held and the rest coming down on it, and rocks back slowly, heavy)
            let sq = fd_ss(0.0, 0.12, a) * exp(-a * 1.9) * cos(7.85 * (a - 0.12)) * (1.0 - fd_ss(0.85, 1.05, a));
            sy = 1.0 - 0.5 * sq;
            sx = 1.0 / sqrt(sy);
            piv = -1.0;
            rip = 0.03 * exp(-a * 3.0) * (1.0 - exp(-a * 30.0));
            ph = a * 16.0;
            sway = vec2<f32>(0.0);
        }
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
fn fd_trail(v: vec3<f32>, C: vec3<f32>, d: FdDrop, way: vec2<f32>, t: f32, px: f32, li: FdLight, far: f32) -> FdMist {
    var m = FdMist(vec3<f32>(0.0), 0.0, vec3<f32>(0.0), vec4<f32>(0.0));
    let a2 = max(dot(v.xz, v.xz), 1.0e-4);
    // (where the ray passes nearest the arc: the arc is the plumb line's height's way off to the side, and a couple of steps find it)
    let head0 = d.h - d.stop_h;
    let S = C - vec3<f32>(way.x * fd_arc(head0), head0, way.y * fd_arc(head0));
    var nearest = S.xz;
    var sc = dot(nearest, v.xz) / a2;
    for (var i = 0; i < 3; i += 1) {
        nearest = S.xz + way * fd_arc(v.y * sc - S.y);
        sc = dot(nearest, v.xz) / a2;
    }
    if (sc <= 0.0 || sc > far) {
        return m;
    }
    let after = fd_since(t);
    let ycl = v.y * sc - C.y;                    // how far over the droplet's centre the ray passes the fall's line
    let gy = ycl + d.h;                          // over the land
    if (gy < -1.0) {
        return m;
    }
    let tipy = FD_TIP * d.R;
    let yw = ycl + d.h - d.stop_h;
    // (the last of the wake carried on down, less of it the higher up)
    let mode = fd_stop();
    let k = fd_stopk(mode);
    let laid = yw + k.x * fd_slip(after) * exp(-max(yw, 0.0) / select(170.0, 900.0, mode == 4)) - tipy;
    let head = d.h - d.stop_h;
    let on = fd_ss(head - 0.1 * d.R, head + 0.9 * d.R, laid);
    if (on <= 0.0) {
        return m;
    }
    let te = FD_STOP - fd_fall_inv(laid);
    let age = max(t - te, 0.0);
    let dive = fd_ss(-2.5, 1.5, te);
    let smk = fd_ss(2500.0, 1100.0, laid);
    // (it wanders as it ages, the wind having it)
    let wa = min(age, 18.0);
    let bend = vec2<f32>(sin(laid * 0.0071 + 1.3) + 0.5 * sin(laid * 0.019), cos(laid * 0.0053) + 0.5 * sin(laid * 0.023 + 2.0)) * wa * (1.5 + 0.18 * wa);
    let off = v.xz * sc - (nearest + bend);
    let hx = length(off);
    // (tight off the tip; where the air it has dragged down meets the land it spreads)
    let flare = 10.0 * fd_ss(26.0, 0.0, gy) * fd_ss(0.0, 0.1, after);
    // (and never thinner than a pixel or two: from far off it is a line drawn across the sky, not nothing)
    let rad = max(mix(0.3 * d.R, 0.72 * d.R + 1.5, 1.0 - exp(-age / 0.14)) + 3.4 * sqrt(age) + 1.1 * max(t - FD_STOP, 0.0) + flare + select(0.0, 11.0 * (1.0 - exp(-after / 0.3)) * exp(-max(yw, 0.0) / 50.0), mode == 5), 1.5 * px * sc);
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
    // (it doesn't go anywhere: it comes apart where it hangs, the thin between its lumps opening until only wisps are left, and those go. Its old high end first)
    let thr = mix(0.32, 0.12, smk) + 0.38 * fd_ss(1.5, 18.0, age) + 0.5 * fd_ss(2.0, 14.0, t - FD_STOP);
    let mm = (puff - thr) * 3.2 + 0.3 * exp(-age / 0.8);
    let sl = 3.2 * 0.14 * sqrt(0.384 * (1.0 - w1 * w1) + 0.09 * (1.0 - w2 * w2) + 0.0064 * (1.0 - w3 * w3)) + 1.0e-3;
    // (a soft max(mm, 0): past 30 its exp would run out, and it is mm)
    let mz = mm / sl;
    let dens = saturate(select(sl * log(1.0 + exp(max(mz, -30.0))), mm, mz > 30.0));
    // (dense where it is laid and thinning slowly; right behind the flame nearly solid, the fire going out into dark smoke)
    let sig = (0.3 * exp(-age / 4.5) + 0.5 * exp(-age / 0.6) * dive) * mix(0.6, 1.15, smk);
    let life = (1.0 - fd_ss(13.0, 18.5, t)) * fd_ss(0.1 - FD_LEAD, 0.9 - FD_LEAD, t);
    var dtau = sig * prof * dens * 1.6 * rad * gin * on * life;
    let nrm = normalize(vec3<f32>(off.x, 0.0, off.y) - v * (0.6 * rad) + vec3<f32>(0.0, 1.0e-4, 0.0));
    let ln = 0.5 + w1 * (n1 - 0.5);
    let lit = (0.35 + 0.65 * saturate(dot(nrm, li.L) * 0.5 + 0.5)) * (0.6 + 0.8 * ln * ln);
    // (white vapour high up, soot-dark low down, paling as it spreads thin)
    var alb = mix(vec3<f32>(0.74, 0.74, 0.76), vec3<f32>(0.115, 0.1, 0.09), smk);
    alb = mix(alb, alb * 1.35 + vec3<f32>(0.03), fd_ss(3.0, 16.0, age));
    var c = alb * (li.sunc * lit * 0.85 + li.amb * (0.6 + 0.4 * ln));
    // (just behind the fire the smoke is lit by it, dying back at once)
    c = c + vec3<f32>(1.2, 0.42, 0.09) * exp(-age / 0.1) * dive * (0.4 + 0.6 * ln);
    c = mix(c, li.haze, (1.0 - exp(-sc / 3000.0)) * 0.5);
    m.c = c;
    m.tau = dtau;
    // (the fire, a body and not a light: burning back off the tip, how long by how fast it goes; white at its root, yellow, orange, dull red at its end, torn to tongues there.
    // It hides what is behind it, or over a bright sky it would only wash out)
    let spd = FD_V + 2.0 * FD_B * max(FD_STOP - te, 0.0);
    let db = max(laid - head, 0.0);
    let u = db / (34.0 + 0.055 * spd);
    let fw = max(d.R * (0.74 - 0.42 * saturate(u)), 1.4 * px * sc);
    let tore = u + 1.3 * (n2 - 0.5) * saturate(u * 2.0) + 0.5 * sin(t * 31.0 + laid * 0.17) * saturate(u * 1.4) * 0.3;
    let ee = hx / fw * (1.0 + 0.9 * (n1 - 0.5) * saturate(u * 3.0));
    let body = fd_ss(1.15, 0.45, ee) * fd_ss(1.25, 0.7, tore) * dive * on * exp(-after / k.y);
    if (body > 0.0) {
        let heat = saturate(1.0 - 0.8 * tore - 0.45 * ee);
        var fc = mix(vec3<f32>(0.62, 0.09, 0.015), vec3<f32>(1.0, 0.36, 0.05), fd_ss(0.05, 0.4, heat));
        fc = mix(fc, vec3<f32>(1.0, 0.72, 0.2), fd_ss(0.4, 0.68, heat));
        fc = mix(fc, vec3<f32>(1.0, 0.97, 0.82), fd_ss(0.68, 0.92, heat));
        m.fire = vec4<f32>(fc, body);
    }
    // (high up, the hot streak of air it leaves, white, cooling within a second)
    let fh = (1.0 - dive) * exp(-age / 0.45) * life;
    let fprof = exp(-pow(hx / max(rad * 0.6, 0.5), 2.0) * 1.6);
    m.glow = vec3<f32>(2.0, 1.9, 1.75) * fh * min(fprof * rad * 0.3, 1.0);
    return m;
}
// The fire on the droplet: a skin of flame wrapped round the teardrop itself, thin and white on the round end it is falling on,
// streaming up its sides in ribbons that wind round it, drawn in to the tip where it goes dark and turns into the wake. Marched
// through, up to `s_end`. At the stop the droplet is left behind: the skin goes on down in its shape, swelling, and is gone.
fn fd_sheath(colIn: vec3<f32>, v: vec3<f32>, C: vec3<f32>, d: FdDrop, t: f32, s_end: f32, jit: f32) -> vec3<f32> {
    let after = fd_since(t);
    let hi = fd_ss(FD_STOP - 5.5, FD_STOP - 0.3, t);
    let k = fd_stopk(fd_stop());
    let on = hi * exp(-after / k.z);
    if (on < 0.01) {
        return colIn;
    }
    // (OVERRUN: it holds its shape and burns out as the speed goes, sliding off past the drop: swelling as it does, over a whole second, it was a big glass dome)
    let over = select(1.0, 0.16, fd_stop() == 4);
    let grow = 1.0 + after * 2.5 * over;
    // (OVERRUN: it only goes on past the drop by what the drop has fallen behind it)
    let past = k.x * fd_slip(after) - select(0.0, d.stop_h + fd_fall(FD_BRAKE) - d.h, fd_stop() == 4 && t >= FD_STOP - FD_BRAKE);
    let Cg = C - vec3<f32>(0.0, min(max(past, 0.0), max(d.h - d.R, 0.0)), 0.0);
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
        let th = mix(0.1, 0.34, hgt) * (1.0 - fd_ss(0.8, 1.0, hgt) * 0.5) * (1.0 + after * 16.0 * over);
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
        var c = mix(vec3<f32>(1.0, 0.95, 0.72), vec3<f32>(1.0, 0.5, 0.08), fd_ss(0.05, 0.4, x));
        c = mix(c, vec3<f32>(0.6, 0.09, 0.015), fd_ss(0.45, 0.9, x));
        // (it hides what is behind it: fire over a bright sky, added to it, only goes pink)
        let fa = 1.0 - exp(-dens * dn * 4.0 / (1.0 + after * 26.0 * over));
        E = E + c * T * fa;
        T = T * (1.0 - fa);
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
// Beads of burning metal shed off it in the last of its fall, each dropping back behind it with a short bright tail, as the Payload sheds its pieces.
fn fd_sparks(colIn: vec3<f32>, v: vec3<f32>, S: vec3<f32>, way: vec2<f32>, t: f32, px: f32) -> vec3<f32> {
    var col = colIn;
    for (var i = 0; i < 6; i += 1) {
        let k = f32(i);
        let ti = 0.6 + 0.27 * k + 0.09 * sin(k * 12.9 + seed_v());
        let a = t - ti;
        if (a <= 0.0 || a > 1.3) {
            continue;
        }
        let tau = FD_STOP - ti;
        let H0 = fd_fall(tau);
        let sp = FD_V + 2.0 * FD_B * tau;
        let b = S + vec3<f32>(way.x * fd_arc(H0), H0, way.y * fd_arc(H0));
        let ang = k * 2.4 + seed_v() * 3.0;
        let dir = vec3<f32>(cos(ang), 0.0, sin(ang)) * (24.0 + 26.0 * fract(k * 0.37 + seed_v()));
        let a0 = max(a - 0.045, 0.0);
        let A = b - vec3<f32>(0.0, sp * (1.0 - exp(-2.0 * a)) / 2.0, 0.0) + dir * (1.0 - exp(-2.5 * a));
        let B = b - vec3<f32>(0.0, sp * (1.0 - exp(-2.0 * a0)) / 2.0, 0.0) + dir * (1.0 - exp(-2.5 * a0));
        let h = ray_seg(v, A, B);
        let w = max(0.8, 1.1 * px * h.y);
        let c = exp(-h.x * h.x / (w * w)) * (1.0 - h.z * 0.8) * (1.0 - fd_ss(0.7, 1.3, a));
        col = mix(col, mix(vec3<f32>(1.0, 0.92, 0.6), vec3<f32>(1.0, 0.4, 0.06), h.z), saturate(c * 1.5));
    }
    return col;
}
// ---- how it stops: `/orbital foldstop N`, for trying them. What each keeps the same: it stops at FD_STOP, it is let go at FD_HANG and it touches on FD_TOUCH.
//   0 THE WAKE   as it was: the fire and the wake go on past it and hit the land
//   1 AIR POND   the air takes it as water takes a drop: rings run out across a plane at its foot, seen by what they bend behind them, and the fire and the smoke flatten on it
//   2 SHOCK      all that speed goes into the air at once: a white bubble of condensation and the ring of its shock front leave it and run out, bending the sky as they go
//   3 SQUASH     it takes the stop itself: flattens hard, comes back tall, and rocks slowly to rest, heavy
//   4 OVERRUN    the one the game uses. It brakes over about a second (FD_BRAKE), the force rising and falling smoothly, and the fire and the wake overrun it: they pour on past and round it, and it is left standing in the stream
//   5 MUSHROOM   the column behind it has nowhere to go: it stacks up over it and rolls out in one thick smoke ring
//   6 STUTTER    time catches: the fire and the smoke hang frozen for a beat with the world drained, the drop's echoes running on under it, and everything lets go
fn fd_stop() -> i32 { return clamp(i32(frame.mod_params[3].w + 0.5), 0, 6); }
// (how much of the wake goes on past it, how long the fire lasts, and how long the fire's skin)
fn fd_stopk(mode: i32) -> vec3<f32> {
    switch mode {
        case 1: { return vec3<f32>(0.0, 0.03, 0.04); }
        case 2: { return vec3<f32>(0.6, 0.04, 0.05); }
        case 3: { return vec3<f32>(0.35, 0.04, 0.035); }
        case 4: { return vec3<f32>(1.0, 0.6, 0.3); }
        case 5: { return vec3<f32>(0.0, 0.04, 0.05); }
        default: { return vec3<f32>(1.0, 0.05, 0.09); }
    }
}
// The clock the fire and the smoke go by: the strike's, but STUTTER's hangs at the stop for FD_HOLD, then catches up.
const FD_HOLD: f32 = 0.3;
fn fd_stopclock(t: f32, mode: i32) -> f32 {
    if (mode != 6 || t < FD_STOP) {
        return t;
    }
    if (t < FD_STOP + FD_HOLD) {
        return FD_STOP;
    }
    return t - FD_HOLD * (1.0 - fd_ss(FD_STOP + 0.8, FD_STOP + 1.8, t));
}
// Where the ray meets the level of the drop's foot: (how far along the ray, x and z from the drop), the second -1 if it doesn't.
fn fd_plane(v: vec3<f32>, y: f32, far: f32) -> f32 {
    if (abs(v.y) < 1.0e-4) {
        return -1.0;
    }
    let s = y / v.y;
    return select(-1.0, s, s > 0.0 && s < far);
}
// AIR POND's rings at r: (their height's slope, how much of it there is here). Groups running out, the crests quicker than the group, as on water.
fn fd_pond(r: f32, a: f32) -> vec2<f32> {
    var sl = 0.0;
    var on = 0.0;
    for (var i = 0; i < 3; i += 1) {
        let b = a - f32(i) * 0.2;
        if (b <= 0.0) {
            continue;
        }
        let g = 150.0 * b + 6.0;
        let w = 15.0 + 36.0 * b;
        let x = (r - g) / w;
        let e = exp(-x * x) * exp(-b * 1.5);
        sl += e * sin((r - 2.0 * g) * 0.42 / (1.0 + 0.5 * b)) * (1.0 - f32(i) * 0.25);
        on = max(on, e);
    }
    return vec2<f32>(sl, on);
}
// The picture behind what is in the air, bent by what the stop did to it.
fn fd_bent(colIn: vec3<f32>, v: vec3<f32>, C: vec3<f32>, d: FdDrop, a: f32, far: f32, uv: vec2<f32>, aspect: f32, mode: i32) -> vec3<f32> {
    var col = colIn;
    if (mode == 1 && a < 2.4) {
        let y = C.y - (d.h - d.stop_h) - d.R;
        let s = fd_plane(v, y, far);
        if (s > 30.0) {
            let P = v * s;
            let q = P.xz - C.xz;
            let r = length(q);
            let w = fd_pond(r, a);
            if (w.y > 0.003) {
                let dir = q / max(r, 0.1);
                let p0 = project_rel(P);
                let p1 = project_rel(P + vec3<f32>(dir.x, 0.0, dir.y) * 24.0);
                let fade = fd_ss(0.0, 0.05, a) * (1.0 - fd_ss(1.6, 2.4, a));
                if (p0.z > 0.0 && p1.z > 0.0) {
                    let bend = (p1.xy - p0.xy) * w.x * 1.1;
                    let lb = length(bend);
                    col = fd_sample(clamp(uv + bend * min(1.0, 0.03 / max(lb, 1.0e-5)) * fade * fd_ss(30.0, 90.0, s), vec2<f32>(0.002), vec2<f32>(0.998)));
                }
                // (its crests catching the sky's light, as a skin on the air)
                let lift = max(w.x, 0.0);
                col = col + vec3<f32>(0.62, 0.68, 0.76) * pow(lift, 2.0) * 0.5 * fade + vec3<f32>(0.5, 0.56, 0.66) * w.y * 0.05 * fade;
            }
        }
    }
    if (mode == 2 && a < 1.6) {
        let Rs = 12.0 + 330.0 * a * (1.0 - 0.22 * a);
        let c0 = dot(C, v);
        let b = length(C - v * c0);
        let wd = 5.0 + 26.0 * a;
        let x = (b - Rs) / wd;
        if (abs(x) < 3.0 && c0 > 0.0) {
            let q = project_rel(C);
            let dr = (uv - q.xy) * vec2<f32>(aspect, 1.0);
            let dir = dr / max(length(dr), 1.0e-4);
            let k = x * exp(-x * x) * exp(-a * 1.8) * fd_ss(0.0, 0.04, a) * 0.03 * (1.0 - fd_ss(1.0, 1.6, a));
            col = fd_sample(clamp(uv + dir * k / vec2<f32>(aspect, 1.0), vec2<f32>(0.002), vec2<f32>(0.998)));
        }
    }
    return col;
}
// What the stop leaves in the air, in front of what is behind it, up to `s_end`.
fn fd_after(colIn: vec3<f32>, v: vec3<f32>, C: vec3<f32>, d: FdDrop, t: f32, a: f32, s_end: f32, li: FdLight, jit: f32, mode: i32) -> vec3<f32> {
    var col = colIn;
    if (a <= 0.0) {
        return col;
    }
    if (mode == 1 && a < 3.0) {
        // (the fire and the smoke stopped by the skin of the air and running out flat along it)
        let s = fd_plane(v, C.y - (d.h - d.stop_h) - d.R, s_end);
        if (s > 0.0) {
            let P = v * s;
            let q = P.xz - C.xz;
            let r = length(q);
            let Rd = 7.0 + 62.0 * (1.0 - exp(-a / 0.5));
            let ang = atan2(q.y, q.x);
            let wob = 0.84 + 0.32 * vnoise(vec2<f32>(cos(ang) * 2.2 + 3.0, sin(ang) * 2.2 + a * 0.25));
            let x = r / (Rd * wob);
            if (x < 1.5) {
                let n = fbm3(vec3<f32>(q.x * 0.05, a * 0.5, q.y * 0.05) + vec3<f32>(0.0, 0.0, seed_v()));
                let rim = fd_ss(1.0, 0.72, x + (n - 0.5) * 0.9) * fd_ss(0.0, 0.1, a);
                let hole = fd_ss(0.9 * d.R, 1.5 * d.R, r);
                let thin = (1.0 - fd_ss(0.7, 3.0, a)) * fd_ss(0.28, 0.6, n);
                let alpha = saturate(0.8 * rim * hole * thin);
                let lit = 0.5 + 0.5 * saturate(li.L.y + n - 0.3);
                var c = vec3<f32>(0.13, 0.115, 0.105) * (li.sunc * lit * 0.85 + li.amb);
                let burn = exp(-a / 0.2) * fd_ss(0.5, 1.0, x + n * 0.5);
                c = mix(c, vec3<f32>(1.0, 0.5, 0.1), saturate(burn * 1.3));
                col = mix(col, c, alpha);
            }
        }
    }
    if (mode == 2 && a < 1.5) {
        // (the bubble: cloud for a moment, where the air was let go; its skin brighter, seen edge on)
        let Rs = 12.0 + 330.0 * a * (1.0 - 0.22 * a);
        let c0 = dot(C, v);
        let b = length(C - v * c0);
        if (c0 > 0.0) {
            let bub = fd_ss(0.0, 0.03, a) * exp(-a / 0.16);
            let u = saturate(b / Rs);
            let n = vnoise(vec2<f32>(atan2(v.z, v.x) * 30.0, v.y * 60.0) + vec2<f32>(a * 2.0));
            col = mix(col, vec3<f32>(0.92, 0.94, 0.98), saturate(bub * (0.2 + 0.7 * u * u * u * u) * (0.6 + 0.8 * n)) * fd_ss(1.03, 0.97, b / Rs));
        }
        // (and the ring round it, where the shock runs flat out through the drop's own level)
        let s = fd_plane(v, C.y, s_end);
        if (s > 0.0) {
            let q = (v * s).xz - C.xz;
            let r = length(q);
            let w = 3.0 + 16.0 * a;
            let x = (r - Rs) / w;
            if (abs(x) < 3.0) {
                let n = fbm3(vec3<f32>(q.x * 0.035, a * 0.8, q.y * 0.035));
                let al = exp(-x * x) * (0.3 + 1.0 * n) * exp(-a * 2.1) * fd_ss(0.0, 0.05, a);
                col = mix(col, vec3<f32>(0.9, 0.92, 0.96), saturate(al));
            }
        }
    }
    if (mode == 5 && a < 3.2) {
        // (the ring: what piled up over it rolls out and over, the thick of it going round its own core)
        let Rt = 5.0 + 46.0 * (1.0 - exp(-a / 0.6));
        let rt = 6.0 + 12.0 * (1.0 - exp(-a / 0.6));
        let Ct = C + vec3<f32>(0.0, FD_TIP * d.R + 7.0 + 26.0 * (1.0 - exp(-a / 0.5)), 0.0);
        let Bo = Rt + rt * 1.9;
        let c0 = dot(Ct, v);
        let h = dot(Ct, Ct) - c0 * c0;
        if (h < Bo * Bo) {
            let sq = sqrt(Bo * Bo - h);
            let s0 = max(c0 - sq, 0.05);
            let s1 = min(c0 + sq, s_end);
            if (s1 > s0) {
                const N = 16;
                let ds = (s1 - s0) / f32(N);
                var T = 1.0;
                var L = vec3<f32>(0.0);
                let fade = fd_ss(0.0, 0.12, a) * (1.0 - fd_ss(0.9, 2.6, a));
                for (var i = 0; i < N; i += 1) {
                    let p = v * (s0 + (f32(i) + jit) * ds) - Ct;
                    let ro = length(p.xz);
                    let qx = ro - Rt;
                    let e = length(vec2<f32>(qx, p.y * 1.15));
                    if (e > rt * 1.5) {
                        continue;
                    }
                    let phi = atan2(p.y, qx);
                    let n = gnoise3(vec3<f32>(p.x * 0.1, p.z * 0.1, phi * 0.9 - a * 2.8)) * 0.65 + gnoise3(vec3<f32>(p.x * 0.27, p.z * 0.27, phi * 2.0 - a * 3.6 + 2.0)) * 0.35;
                    let dn = fd_ss(rt * (0.9 + 0.7 * n), rt * (0.1 + 0.5 * n), e) * fade;
                    if (dn < 0.01) {
                        continue;
                    }
                    let up = saturate(p.y / rt * 0.5 + 0.5);
                    var c = vec3<f32>(0.1, 0.09, 0.082) * (li.sunc * (0.3 + 0.7 * up * saturate(li.L.y + 0.4)) + li.amb * 0.8);
                    // (the fire still in its heart, going out)
                    c = c + vec3<f32>(1.3, 0.42, 0.07) * exp(-a / 0.28) * fd_ss(0.7, 0.1, e / rt);
                    let fa = 1.0 - exp(-dn * ds * 0.2);
                    L = L + c * T * fa;
                    T = T * (1.0 - fa);
                }
                col = col * T + L;
            }
        }
    }
    if (mode == 6 && a < 0.5) {
        // (the drop's echoes, running on where it would have gone, thinning out: hollow, the rim of it only)
        for (var i = 1; i < 6; i += 1) {
            let g = C - vec3<f32>(0.0, FD_V * 0.2 * a * f32(i) + f32(i) * 1.5 * d.R * fd_ss(0.0, 0.05, a), 0.0);
            let c0 = dot(g, v);
            let b = length(g - v * c0);
            let x = (b - d.R) / (0.09 * d.R);
            let al = exp(-x * x) * 0.8 * exp(-f32(i) * 0.4) * (1.0 - fd_ss(0.25, 0.5, a));
            col = mix(col, vec3<f32>(0.86, 0.92, 1.04), saturate(al));
        }
    }
    return col;
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
fn fd_droplet(colIn: vec3<f32>, t: f32, v: vec3<f32>, G: vec3<f32>, C: vec3<f32>, d: FdDrop, way: vec2<f32>, far: f32, uv: vec2<f32>, aspect: f32, land: vec4<f32>, li: FdLight, jit: f32) -> vec3<f32> {
    var col = colIn;
    let px = frame.view_params.w / frame.resolution.y;
    let q = project_rel(C);
    let after = fd_since(t);
    let hi = fd_ss(FD_STOP - 5.5, FD_STOP - 0.2, t);
    let mode = fd_stop();
    let tx = fd_stopclock(t, mode);
    if (after > 0.0) {
        col = fd_bent(col, v, C, d, after, far, uv, aspect, mode);
    }
    // ---- the wake, hung in the sky -----------------------------------------------------------------------------------------
    var wake = FdMist(vec3<f32>(0.0), 0.0, vec3<f32>(0.0), vec4<f32>(0.0));
    if (t < 18.5) {
        let m = fd_trail(v, C, d, way, tx, px, li, far);
        wake = m;
        if (m.tau > 0.0) {
            col = mix(col, m.c, 1.0 - exp(-m.tau));
        }
        col = mix(col, m.fire.rgb, m.fire.a) + m.glow;
    }
    if (t > 0.6 && t < 3.4) {
        let head0 = d.h - d.stop_h;
        col = fd_sparks(col, v, C - vec3<f32>(way.x * fd_arc(head0), head0, way.y * fd_arc(head0)), way, t, px);
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
            // (its belly white hot, red up its sides, cooling to chrome from the top down within a second or so of the stop)
            let hot = fd_ss(0.25, -0.75, n.y) * hi * exp(-after / 0.4);
            mc = mix(mc, mix(vec3<f32>(0.85, 0.2, 0.03), vec3<f32>(1.0, 0.86, 0.6), fd_ss(-0.2, -0.85, n.y) * exp(-after / 0.15)), saturate(hot * 1.15));
            col = mix(col, mc, cov);
            // (the stream going by in front of it, thin, its lumps showing, and clearing off it as the stream dies: it stays the thing to look at)
            if (mode == 4 && wake.tau > 0.0) {
                col = mix(col, wake.c, cov * (1.0 - exp(-wake.tau)) * 0.55 * fd_ss(0.2, 0.7, after) * (1.0 - fd_ss(1.5, 3.2, after)));
            }
            if (hit) {
                s_end = min(s_end, sb);
            }
        }
    }
    // ---- the fire round it, and the dust the air raises -----------------------------------------------------------------
    col = fd_sheath(col, v, C, d, tx, s_end, jit);
    col = fd_after(col, v, C, d, t, after, s_end, li, jit, mode);
    // (the dust over it thinned: it stays the thing to look at)
    // (POND and MUSHROOM keep the air off the land; STUTTER's arrives late)
    let air = select(after - select((d.stop_h - d.R) / FD_V, 1.2, mode == 4) - select(0.0, FD_HOLD, mode == 6), -1.0, mode == 1 || mode == 5);
    let dusty = fd_dust(col, v, G, air, s_end, land, li, jit);
    var out_ = mix(dusty, col, select(0.0, 0.7, s_end < far));
    // (STUTTER: the world drained for the beat it hangs, and let go at once)
    if (mode == 6 && after > 0.0 && after < FD_HOLD + 0.1) {
        let g = dot(out_, vec3<f32>(0.3, 0.55, 0.15));
        out_ = mix(out_, vec3<f32>(g) * vec3<f32>(0.86, 0.9, 1.0), 0.42 * fd_ss(0.0, 0.03, after) * (1.0 - fd_ss(FD_HOLD, FD_HOLD + 0.1, after)));
    }
    return out_;
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

// ---- the metal's frame --------------------------------------------------------------------------------------------------
// fw_turn undone: from where fw_place leaves a point, or a way, to the tube's own frame: the target at the origin, its axis up; and back, for a way.
fn fd_unturn(P: vec3<f32>, g: FwBend, at: vec3<f32>, point: bool) -> vec3<f32> {
    let ct = cos(at.z);
    let st = sin(at.z);
    let w = select(0.0, 1.0, point);
    let al = dot(P.xz, g.e) - g.d * w;
    let dv = -P.x * g.e.y + P.z * g.e.x;
    let dy0 = P.y - g.pin * w;
    let along = al * ct - dy0 * st + at.x * w;
    let Y = al * st + dy0 * ct + at.y * w;
    return vec3<f32>(along * g.e.x - dv * g.e.y, Y, along * g.e.y + dv * g.e.x);
}
fn fd_returned(n: vec3<f32>, g: FwBend, at: vec3<f32>) -> vec3<f32> {
    let ct = cos(at.z);
    let st = sin(at.z);
    let al = dot(n.xz, g.e);
    let dv = -n.x * g.e.y + n.z * g.e.x;
    let qx = al * ct + n.y * st;
    let qy = -al * st + n.y * ct;
    return vec3<f32>(qx * g.e.x - dv * g.e.y, qy, qx * g.e.y + dv * g.e.x);
}
// What the metal sees past the picture's edge. The picture hasn't what is behind the eye, and a mirror this big shows everything it reflects, so not a map of the land: what makes
// chrome chrome. Dark, the land's own dim greens and blues far off in it, and long soft ribbons of the sky's light lying along it, which the metal's curves draw out and bend.
fn fd_round(r: vec3<f32>) -> vec3<f32> {
    let w = r.y * 5.0 + 0.7 * sin(r.x * 2.7 + 1.0 * sin(r.z * 3.1)) + 0.55 * sin(r.z * 3.3 - 0.8 * sin(r.x * 2.2 + 1.0));
    let n = 0.6 * sin(r.x * 3.1 + 1.3 * sin(r.z * 3.7 + 0.7) + r.y) + 0.5 * sin(r.z * 4.3 - 1.1 * sin(r.x * 2.9 - 1.0) - 1.4 * r.y);
    let k = fw_ss(-0.4, 0.9, n);
    let hue = 0.5 + 0.5 * sin(r.x * 2.3 - r.z * 1.7 + 1.1 * sin(r.y * 5.0));
    let land = mix(vec3<f32>(0.03, 0.05, 0.03), vec3<f32>(0.02, 0.035, 0.075), hue);
    var c = mix(land * 0.3, land * 1.5 + vec3<f32>(0.035, 0.04, 0.05), k);
    let a = 0.5 + 0.5 * cos(w * 2.0);
    c = c + vec3<f32>(0.62, 0.66, 0.74) * pow(a, 26.0) * (0.3 + 0.7 * k);
    c = c + vec3<f32>(0.1, 0.11, 0.13) * pow(0.5 + 0.5 * cos(w * 2.0 + 1.9), 3.0);
    return c;
}
// The droplet's own metal, for a surface at `S` from the eye (along `v`) with normal `n`: fd_env's sky, its hard dark line, the sun, and under it the land off the picture.
// `near` how much of the real land it mirrors: what is under it at the tip, where there is land on the picture to mirror.
fn fd_chrome(v: vec3<f32>, S: vec3<f32>, n: vec3<f32>, G: vec3<f32>, near: f32) -> vec3<f32> {
    let r = reflect(v, n);
    // (its horizon drawn down: seen from under it, most of a thing hung up looks down, and the droplet's bright half would be lost)
    let e = normalize(vec3<f32>(r.x, (r.y + FD_LIFT) * 1.7, r.z));
    var c = fd_env(e, normalize(frame.sun.xyz));
    c = c * (1.0 - 0.9 * exp(-e.y * e.y * 24000.0));
    if (e.y < 0.03) {
        let up = max(-r.y, 0.03);
        let ro = project_rel(S + r * clamp((S.y - G.y) / up, 8.0, 400.0));
        let edge = fd_ss(0.0, 0.05, min(min(ro.x, 1.0 - ro.x), min(ro.y, 1.0 - ro.y)));
        let there = select(0.0, edge, ro.z > 0.0 && r.y < 0.0) * near;
        var l = fd_round(r);
        if (there > 0.0) {
            l = mix(l, fd_sample(ro.xy), there);
        }
        c = mix(c, l * 1.05, 0.9 * fd_ss(0.012, -0.012, e.y));
    }
    let fres = pow(1.0 - max(dot(-v, n), 0.0), 4.0);
    // (the droplet is small: this much of a thing at night has to go down with the sky)
    let day = 0.14 + 0.86 * fd_ss(-0.2, 0.1, frame.sun.y);
    return c * vec3<f32>(0.9, 0.93, 0.98) * (0.86 + 0.5 * fres) * day;
}
const FD_LIFT: f32 = 0.26;
// ---- the boil ---------------------------------------------------------------------------------------------------------------
// The hole in the roof closes, and what closes it is metal, slowly, heavy. The land's end melts: thick tongues of the droplet's metal crawl in from the rim for seconds, from one side first, the
// stars narrowing between them, and as they near each other their fronts and the pockets left between them seethe (fb_seethe), more and more; they bridge pair by pair (FB_JOIN on) and the last
// pockets close off to one side. The surface they make heaves and rolls and settles, with no streaming in it (fb_heave); the flow (fb_flow) grows out of that by the metal drawing itself to the drip:
// what is on it is carried along a real field, currents, eddies and all, so that the streaks are its lumps pulled out. A dimple, a bulge hanging out of it, a bead on a neck, a pinch, and one drop
// falls the length of the tube under gravity to the target on FD_BEAT. Out over the land past the rim there is no edge to it (fb_creep). All in the tube's own frame (fd_unturn), wherever the player has gone.
const FB_MELT: f32 = 32.5;         // the land's end starts to melt
const FB_JOIN: f32 = 35.8;         // the tongues start to bridge
const FB_SEAL: f32 = 36.85;        // the last of the stars has gone
const FB_RUN: f32 = 37.2;         // the flow begins to grow out of the settling surface
const FB_FLOWN: f32 = 38.7;        // by here it is flowing in full
const FB_PIN: f32 = 38.35;          // the pinch: the drop is let go
const FB_UP: f32 = 4.0;            // the surface over the land's end, so what is left of the land goes in front of it
const FB_FIT: f32 = 1.2;           // past the hole's rim it goes on, behind the land
const FB_LONG: f32 = 78.0;         // how far the bead hangs under the surface as it lets go
const FB_V0: f32 = 34.0;           // how fast it is going as it does
const FB_THICK: f32 = 24.0;        // the metal's thickness, blocks
const FB_EDGE: f32 = 19.0;         // how soon it reaches that from its edge
// The tongues' own clock: their shapes were keyed on one that ran from 34.5, and it goes by slowly here: ~3.3 s for its first second, then the join, drawn out.
fn fb_tm(t: f32) -> f32 {
    let a = (t - FB_MELT) / 3.3;
    if (a < 1.0) {
        return 34.5 + a;
    }
    return 35.5 + (t - (FB_MELT + 3.3)) * 0.42 / (FB_SEAL - (FB_MELT + 3.3));
}
fn fb_source(g: FwBend) -> vec2<f32> {
    // (off to one side of the player, so that it starts where they can see it start)
    return vec2<f32>(-0.32 * g.e.x - 0.947 * g.e.y, 0.947 * g.e.x - 0.32 * g.e.y);
}
// How late a bearing is, 0 on the side it starts, 1 across from it.
fn fb_late(dir: vec2<f32>, S: vec2<f32>) -> f32 {
    return 0.5 - 0.5 * dot(dir, S);
}
// The metal on the hole: `d` how far `q` is outside it, blocks (under 0 inside), and its slope. The rim growing in, and FB_TONGUES thick tongues from it to a place off to the far side, each its
// own width and time, the first from the side at `S`, one soft union whose softness jumps as they join. What is between them is the stars.
const FB_TONGUES: i32 = 9;
struct FbMetal { d: f32, g: vec2<f32> }
fn fb_metal(qIn: vec2<f32>, t: f32, S: vec2<f32>, rd: f32) -> FbMetal {
    // (no straight lines: the whole of it is bent a little, slowly)
    let q = qIn + 30.0 * vec2<f32>(sin(qIn.y * 0.0093 + 0.25 * t + 1.0) + 0.4 * sin(qIn.y * 0.031 - 0.17 * t), sin(qIn.x * 0.0107 - 0.21 * t + 2.0) + 0.4 * sin(qIn.x * 0.027 + 0.2 * t));
    let r = max(length(q), 0.01);
    let dirq = q / r;
    let tm = fb_tm(t);
    let jn = fw_ss(FB_JOIN, FB_JOIN + 0.5, t);
    let k = 13.0 + 11.0 * jn;
    // ---- the rim, growing in, unevenly ------------------------------------------------------------------------------------------
    let late = fb_late(dirq, S);
    let g0 = fw_ss(34.5 + 0.32 * late, 35.8 + 0.5 * late, tm);
    let th = atan2(q.y, q.x);
    let ringR = rd * (1.03 - 0.24 * g0 * (1.0 + 0.45 * sin(th * 2.0 + 1.0 + 0.9 * sin(th * 3.0)) + 0.3 * sin(th * 5.0 - 0.6)));
    let d0 = ringR - r;
    var sum = exp(clamp(-d0 / k, -40.0, 40.0));
    var gs = -dirq * sum;
    // ---- the tongues ----------------------------------------------------------------------------------------------------------
    let seal = -S * rd * 0.3;
    for (var i = 0; i < FB_TONGUES; i += 1) {
        let fi = f32(i);
        let h = hash21(vec2<f32>(fi, 41.0));
        let h2 = fract(h * 27.1);
        let an = (fi + 0.7 * h) * 6.2831853 / f32(FB_TONGUES);
        let A = vec2<f32>(cos(an), sin(an));
        let lt = fb_late(A, S);
        let u = clamp((tm - (34.6 + 0.85 * lt + 0.2 * h2)) / (0.95 + 0.55 * h), 0.0, 1.0);
        if (u <= 0.0) {
            continue;
        }
        // (slow to get going, heavy, and it doesn't quite stop; it comes on in surges, a lobe rolling over the front)
        let p0 = u * u * (3.0 - 2.0 * u);
        let p = p0 + 0.42 * p0 * (1.0 - p0) * sin(u * 11.0 + h * 6.28) * 0.5;
        let B = A * rd * 1.06;
        let T = mix(B, seal, 0.08 + 0.92 * p);
        let ba = T - B;
        let qa = q - B;
        let s = clamp(dot(qa, ba) / max(dot(ba, ba), 1.0), 0.0, 1.0);
        let e = qa - ba * s;
        let el = max(length(e), 0.01);
        // (thick: a blunt head on it, wider than what is behind it, a heavy thing that has to push)
        let head = exp(-pow((1.0 - s) * length(ba) / 70.0, 2.0));
        let wd = (30.0 + 40.0 * h2) * (0.55 + 0.45 * p) * (1.0 + 0.55 * (1.0 - s)) * (1.0 + 0.2 * jn + 0.06 * fw_ss(FB_JOIN + 0.2, FB_SEAL, t)) + 16.0 * head * (0.4 + 0.6 * p);
        let di = el - wd;
        let w = exp(clamp(-di / k, -40.0, 40.0));
        sum += w;
        gs += w * e / el;
    }
    // (what's left of the stars closes on its own, by FB_SEAL)
    let fill = 70.0 * fw_ss(FB_SEAL - 0.3, FB_SEAL + 0.02, t);
    return FbMetal(-k * log(max(sum, 1.0e-30)) - fill, gs / max(sum, 1.0e-30));
}
// The big slow bubbles: each swells where it is and bursts, a ring running off it. Their slope.
const FB_BUBBLES: i32 = 6;
fn fb_bubbles(q: vec2<f32>, t: f32, S: vec2<f32>, rd: f32) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    if (t < 36.3 || t > 40.2) {
        return g;
    }
    let P = array<vec2<f32>, 6>(vec2<f32>(0.62, 0.7), vec2<f32>(0.5, 2.6), vec2<f32>(0.78, 4.1), vec2<f32>(0.45, 5.3), vec2<f32>(0.7, 1.7), vec2<f32>(0.58, 3.5));
    let W = array<vec3<f32>, 6>(vec3<f32>(36.4, 1.25, 46.0), vec3<f32>(36.72, 1.3, 62.0), vec3<f32>(36.95, 1.0, 38.0), vec3<f32>(37.3, 1.3, 54.0), vec3<f32>(37.55, 1.1, 42.0), vec3<f32>(37.8, 1.2, 34.0));
    let turn = atan2(S.y, S.x);
    for (var i = 0; i < FB_BUBBLES; i += 1) {
        let w = W[i];
        let a = t - (w.x + w.y);
        if (t < w.x || a > 1.5) {
            continue;
        }
        let bear = P[i].y + turn;
        let c = vec2<f32>(cos(bear), sin(bear)) * P[i].x * rd * (1.0 - 0.14 * clamp((t - w.x) / 2.0, 0.0, 1.0));
        let e = q - c;
        let el = max(length(e), 0.01);
        let dir = e / el;
        if (a < 0.0) {
            // (a heavy dome, its top slowly coming down towards the eye)
            let x = (t - w.x) / w.y;
            let R = w.z * (0.45 + 0.55 * sqrt(x));
            let u = el / R;
            if (u < 1.0) {
                let A = 0.3 * R * x * x * (3.0 - 2.0 * x);
                let f = 1.0 - u * u;
                g -= dir * 6.0 * A * u * f * f / R;
            }
        } else {
            // (it has burst: its skirt falls back and runs out as a ring, thick, gone in a second)
            let front = w.z * (1.0 + 1.1 * (1.0 - exp(-a / 0.34)));
            let wd = 10.0 + 0.3 * w.z;
            let x2 = (el - front) / wd;
            let A = 0.17 * w.z * exp(-a / 0.5);
            g -= dir * 2.0 * A * x2 * exp(-x2 * x2) / wd;
        }
    }
    return g;
}
// ---- the seethe: bubbles of every size in the metal at the fronts and round the pockets of stars, building as they close. Three loose scatters, big slow ones and small quick ones, each on its own
// rotated grid so nothing lines up; a cycle of each cell swells a dome where it likes and bursts it. Most cycles of most cells have nothing in them, so there is never a pattern of them. `amt`, how
// much seethe here, thins them out. Out: height, slope.
fn fb_seethe(q: vec2<f32>, t: f32, amt: f32, edge: f32) -> vec3<f32> {
    var o = vec3<f32>(0.0);
    let CELL = array<f32, 3>(205.0, 92.0, 50.0);
    let PER = array<f32, 3>(2.3, 1.35, 0.8);
    let RAD = array<f32, 3>(82.0, 38.0, 20.0);
    let SL = array<f32, 3>(1.0, 0.6, 0.3);
    let EDGE_K = array<f32, 3>(1.0e4, 110.0, 40.0);
    let ROT = array<vec2<f32>, 3>(vec2<f32>(0.8, 0.6), vec2<f32>(0.28, -0.96), vec2<f32>(-0.6, 0.8));
    for (var k = 0; k < 3; k += 1) {
        // (the small ones only right at the front: further in, only the big)
        let keep = fw_ss(EDGE_K[k], 0.6 * EDGE_K[k], edge);
        if (keep <= 0.0) {
            continue;
        }
        let u = vec2<f32>(q.x * ROT[k].x - q.y * ROT[k].y, q.x * ROT[k].y + q.y * ROT[k].x) / CELL[k] + vec2<f32>(f32(k) * 3.7, 11.0);
        let c0 = floor(u - 0.5);
        for (var j = 0; j < 4; j += 1) {
            let c = c0 + vec2<f32>(f32(j & 1), f32(j >> 1));
            let ph = hash21(c + f32(k) * 19.0);
            let cl = (t + ph * 40.0) / PER[k];
            let cy = floor(cl);
            let h = hash21(c * 1.7 + vec2<f32>(cy * 0.37 + f32(k) * 5.0, cy * 0.61));
            if (h > amt) {
                continue;
            }
            let h2 = fract(h * 91.7 + ph);
            let h3 = fract(h2 * 47.3);
            let life = fract(cl);
            let sz = RAD[k] * (0.5 + 0.5 * h2 * h2);
            let wt = fw_ss(0.0, 0.16, amt - h) * keep;
            let e0 = (u - (c + vec2<f32>(0.5) + (vec2<f32>(h2, h3) - 0.5) * max(0.5 - 1.5 * sz / CELL[k], 0.14))) * CELL[k];
            // (none of them round: each squashed its own way, and leaning)
            let an = h3 * 6.2831853;
            let ca = cos(an);
            let sa = sin(an);
            let sq = 1.0 + 0.9 * fract(h3 * 13.1);
            let e1 = vec2<f32>(ca * e0.x + sa * e0.y, (-sa * e0.x + ca * e0.y) * sq);
            let el = max(length(e1), 0.01);
            let d1 = vec2<f32>(ca * e1.x - sa * e1.y * sq, sa * e1.x + ca * e1.y * sq) / el;
            let dir = vec2<f32>(d1.x * ROT[k].x + d1.y * ROT[k].y, -d1.x * ROT[k].y + d1.y * ROT[k].x);
            let x = life / 0.74;
            if (x < 1.0) {
                let R = sz * (0.45 + 0.55 * sqrt(x));
                let w = el / R;
                if (w < 1.0) {
                    // (no flat top on it: a soft hump, with nothing in the middle to make it an eye)
                    let A = 0.3 * R * x * x * (3.0 - 2.0 * x);
                    let f = 1.0 - w * w;
                    // (the small ones are the edge's: they lift it and hardly mark the surface, which is where they would be eyes)
                    o = o + wt * vec3<f32>(A * f * f * f, -dir * 6.0 * A * w * f * f / R * SL[k]);
                }
            } else if (k == 0) {
                // (it goes down fast, not at once)
                {
                    let a0 = (life - 0.74) * PER[k];
                    let w = el / sz;
                    if (w < 1.0) {
                        let A = 0.3 * sz * exp(-a0 / (0.05 * PER[k]));
                        let f = 1.0 - w * w;
                        o = o + wt * vec3<f32>(A * f * f * f, -dir * 6.0 * A * w * f * f / sz * SL[k]);
                    }
                }
                // (a big one leaves a ring, thick, gone soon)
                let a = (life - 0.74) * PER[k];
                let front = sz * (1.0 + 0.4 * (1.0 - exp(-a / (0.14 * PER[k]))));
                let wd = 0.35 * sz + 2.0;
                let x2 = (el - front) / wd;
                let A = 0.13 * sz * exp(-a / (0.1 * PER[k]));
                let f = exp(-x2 * x2);
                // (where the metal is thin it bursts right through: stars for a moment)
                let gone = exp(-(el * el) / (sz * sz * 0.5)) * exp(-a / (0.13 * PER[k]));
                o = o + wt * vec3<f32>(A * f - 0.55 * sz * gone, -dir * 2.0 * A * x2 * f / wd);
            } else {
                let a = (life - 0.74) * PER[k];
                let w = el / sz;
                if (w < 1.0) {
                    let A = 0.3 * sz * exp(-a / (0.05 * PER[k]));
                    let f = 1.0 - w * w;
                    o = o + wt * vec3<f32>(A * f * f * f, -dir * 6.0 * A * w * f * f / sz * SL[k]);
                }
                o.x = o.x - wt * 0.6 * sz * exp(-(el * el) / (sz * sz * 0.5)) * exp(-a / (0.13 * PER[k]));
            }
        }
    }
    return o;
}
// The integral of fw_ss(a, b, t) over t: how far a thing has gone whose speed comes up smoothly.
fn fb_ramp(a: f32, b: f32, t: f32) -> f32 {
    let u = clamp((t - a) / (b - a), 0.0, 1.0);
    return (b - a) * u * u * u * (1.0 - 0.5 * u) + max(t - b, 0.0);
}
// How far the metal has been drawn, in blocks at the speed of the field below: nothing until the surface has settled, then it comes up slowly.
const FB_DRAW: f32 = 30.0;         // blocks a second, as it runs in full, where the field is 1
fn fb_drawn(t: f32) -> f32 {
    return FB_DRAW * fb_ramp(FB_RUN, FB_FLOWN, t);
}
// How far the metal was carried in as the tongues crawled.
fn fb_crawled(t: f32) -> f32 {
    return 110.0 * (fb_ramp(33.0, 34.2, t) - fb_ramp(35.6, 36.9, t));
}
// The field the metal is drawn along: to the drip, and over that plane waves of current, each part turning and part closing or spreading, so that there are eddies, and places currents meet and
// fold and places they part. x is how far it has been drawn: the field moves on as it goes, slowly. Out: velocity, and its gradient: (dv.x/dx, dv.x/dy, dv.y/dx, dv.y/dy).
struct FbField { v: vec2<f32>, dv: vec4<f32> }
fn fb_field(q: vec2<f32>, x: f32) -> FbField {
    let r = max(length(q), 1.0);
    let rh = q / r;
    let e = exp(-r / 170.0);
    let gate = fw_ss(3.0, 30.0, r);
    let S = (0.5 + 1.0 * e) * gate;
    let dS = -1.0 / 170.0 * e * gate;
    var v = -rh * S;
    // (-S rh: along rh its gradient is -dS, across it -S / r)
    let a = -dS;
    let b = -S / r;
    var dv = vec4<f32>(a * rh.x * rh.x + b * rh.y * rh.y, (a - b) * rh.x * rh.y, (a - b) * rh.x * rh.y, a * rh.y * rh.y + b * rh.x * rh.x);
    let K = array<vec2<f32>, 4>(vec2<f32>(0.0143, 0.0041), vec2<f32>(-0.0086, 0.0207), vec2<f32>(0.0238, -0.0167), vec2<f32>(-0.0301, -0.0223));
    let Pp = array<f32, 4>(0.7, 2.9, 4.6, 1.3);
    let Om = array<f32, 4>(0.0031, -0.0043, 0.0058, -0.0071);
    let Sp = array<f32, 4>(0.82, 0.7, 0.56, 0.4);
    let Tw = array<vec2<f32>, 4>(vec2<f32>(0.94, 0.3), vec2<f32>(-0.88, 0.45), vec2<f32>(0.75, -0.6), vec2<f32>(0.97, 0.2));
    for (var i = 0; i < 4; i += 1) {
        let k = K[i];
        let ph = dot(k, q) + Pp[i] + Om[i] * x;
        let c = cos(ph);
        let s = sin(ph);
        let kl = length(k);
        let kh = k / kl;
        // (Tw.x of it across the wave, turning; Tw.y along it, closing and spreading)
        let d = (vec2<f32>(-kh.y, kh.x) * Tw[i].x + kh * Tw[i].y) * Sp[i];
        v = v + d * c;
        dv = dv - vec4<f32>(d.x * k.x, d.x * k.y, d.y * k.x, d.y * k.y) * s;
    }
    return FbField(v, dv);
}
// The heave: what the surface does after it has joined, before anything runs: long swells rocking on the spot and rolling across it, slowly dying down, some of it never gone. Slope.
fn fb_heave(q: vec2<f32>, t: f32) -> vec2<f32> {
    let on = fw_ss(FB_JOIN, FB_JOIN + 0.7, t);
    if (on <= 0.0) {
        return vec2<f32>(0.0);
    }
    let dec = 0.32 + 0.68 * exp(-max(t - 36.9, 0.0) / 0.9);
    var g = vec2<f32>(0.0);
    // (rocking)
    let K = array<vec2<f32>, 3>(vec2<f32>(0.0121, 0.0072), vec2<f32>(-0.0083, 0.0144), vec2<f32>(0.0176, -0.0101));
    let W = array<vec3<f32>, 3>(vec3<f32>(1.5, 1.1, 9.0), vec3<f32>(1.1, 3.7, 11.0), vec3<f32>(1.9, 0.4, 6.0));
    for (var i = 0; i < 3; i += 1) {
        let w = W[i];
        g = g + K[i] * w.z * cos(dot(K[i], q) + 0.8 * sin(0.9 * t + w.y)) * sin(w.x * t + w.y);
    }
    // (rolling: long fronts coming through, curved, each from its own side and at its own speed)
    let C = array<vec2<f32>, 4>(vec2<f32>(-900.0, 300.0), vec2<f32>(700.0, 800.0), vec2<f32>(300.0, -1000.0), vec2<f32>(-500.0, -800.0));
    let T = array<vec3<f32>, 4>(vec3<f32>(36.1, 76.0, 9.0), vec3<f32>(36.9, 58.0, 7.5), vec3<f32>(37.7, 92.0, 6.0), vec3<f32>(38.6, 68.0, 7.0));
    for (var i = 0; i < 4; i += 1) {
        let w = T[i];
        let e = q - C[i];
        let el = length(e);
        let x = (el - (length(C[i]) - 420.0) - w.y * (t - w.x)) / 60.0;
        if (abs(x) < 3.0) {
            g = g + e / el * (-2.0 * x / 60.0) * exp(-x * x) * w.z * 3.0;
        }
    }
    return g * on * dec;
}
// The metal's own forms: broad rolling ones and, drawn out, narrow ones, plane waves at angles that never line up, each sliding over the metal at its own rate. Their slope, in the coordinates they are carried in.
fn fb_lumps(a: vec2<f32>, t: f32) -> vec2<f32> {
    let K = array<vec3<f32>, 5>(vec3<f32>(0.0191, 0.0072, 0.115), vec3<f32>(-0.0103, 0.0247, 0.1), vec3<f32>(0.0086, -0.0129, 0.11), vec3<f32>(-0.0313, -0.0141, 0.085), vec3<f32>(0.0292, 0.0303, 0.06));
    let W = array<vec2<f32>, 5>(vec2<f32>(0.24, 0.6), vec2<f32>(-0.37, 2.4), vec2<f32>(0.15, 4.4), vec2<f32>(0.5, 1.1), vec2<f32>(-0.64, 5.6));
    var g = vec2<f32>(0.0);
    for (var i = 0; i < 5; i += 1) {
        let k = K[i];
        let ph = k.x * a.x + k.y * a.y + W[i].y + W[i].x * t + 1.7 * sin(0.0083 * a.y - 0.0061 * a.x + W[i].y) + 1.2 * sin(0.0057 * a.x + 0.0121 * a.y + 2.1 * W[i].y);
        g = g + normalize(k.xy) * k.z * cos(ph);
    }
    return g;
}
fn fb_fine(a: vec2<f32>, t: f32) -> vec2<f32> {
    let K = array<vec3<f32>, 4>(vec3<f32>(0.0637, 0.0411, 0.1), vec3<f32>(-0.0352, 0.0837, 0.09), vec3<f32>(0.0953, -0.0524, 0.075), vec3<f32>(-0.0721, -0.1046, 0.06));
    let W = array<vec2<f32>, 4>(vec2<f32>(0.9, 3.1), vec2<f32>(-1.3, 0.7), vec2<f32>(1.7, 5.2), vec2<f32>(-2.1, 1.9));
    var g = vec2<f32>(0.0);
    for (var i = 0; i < 4; i += 1) {
        let k = K[i];
        g = g + normalize(k.xy) * k.z * cos(k.x * a.x + k.y * a.y + W[i].y + W[i].x * t);
    }
    return g;
}
// The metal's surface: (height, its slope along x, z), blocks. `ps`, how big a pixel is there.
const FB_STEPS: i32 = 5;
fn fb_flow(q: vec2<f32>, t: f32, ps: f32) -> vec3<f32> {
    let r = max(length(q), 1.0);
    let rh = q / r;
    // ---- where what is here came from ----
    let X = fb_drawn(t);
    var p = q;
    var J = vec4<f32>(1.0, 0.0, 0.0, 1.0);
    if (X > 0.5) {
        let dx = X / f32(FB_STEPS);
        for (var i = 0; i < FB_STEPS; i += 1) {
            let f = fb_field(p, X * (1.0 - (f32(i) + 0.5) / f32(FB_STEPS)));
            p = p - f.v * dx;
            let m = vec4<f32>(1.0, 0.0, 0.0, 1.0) - f.dv * dx;
            J = vec4<f32>(m.x * J.x + m.y * J.z, m.x * J.y + m.y * J.w, m.z * J.x + m.w * J.z, m.z * J.y + m.w * J.w);
        }
    }
    // (and as the tongues crawled, in from the rim. Near enough no shear in that, for what it adds)
    let cr = fb_crawled(t);
    let out = cr / (length(p) + 240.0);
    // (the broad forms are thick, and go at something over half the speed of what's on them)
    let d = p - q;
    let pa = (q + 0.55 * d) * (1.0 + out);
    let Ja = vec4<f32>(1.0, 0.0, 0.0, 1.0) + 0.55 * (J - vec4<f32>(1.0, 0.0, 0.0, 1.0));
    let ga = fb_lumps(pa, t);
    // (how hard it has been squeezed: what is squeezed thin goes under, or it crowds to a hair)
    let cc = dot(Ja, Ja);
    // (the drip: as the bead comes the middle goes smooth, a long clean funnel with nothing on it, so that the eye goes there and the bead can be seen)
    let well = fw_ss(FB_PIN - 1.3, FB_PIN - 0.5, t) * (1.0 - fw_ss(FB_PIN + 0.9, FB_PIN + 2.0, t));
    let calm = 1.0 - well * (1.0 - fw_ss(45.0, 190.0, r));
    var g = vec2<f32>(Ja.x * ga.x + Ja.z * ga.y, Ja.y * ga.x + Ja.w * ga.y) * 2.3 * calm / (1.0 + 0.1 * max(cc - 2.0, 0.0));
    // ---- the narrow forms, which the flow draws out to the streaks ----
    let c2 = dot(J, J);
    let on = (0.3 + 1.1 * fw_ss(6.0, 70.0, X)) * fw_ss(4.0, 30.0, r) * calm / (1.0 + 0.05 * max(c2 - 2.0, 0.0) + 0.04 * c2 * ps * ps);
    if (on > 0.01) {
        let gb = fb_fine(p * (1.0 + out), t);
        g = g + vec2<f32>(J.x * gb.x + J.z * gb.y, J.y * gb.x + J.w * gb.y) * on;
    }
    g = g + fb_heave(q, t) * calm + rh * well * 0.7 * (r / 85.0) * exp(0.5 - 0.5 * r * r / (85.0 * 85.0));
    // (rings running out of the middle from the pinch)
    let xp = t - FB_PIN;
    if (xp > 0.0 && xp < 1.6) {
        let ph = r * 0.16 - xp * 16.0;
        let a_ = 2.2 * exp(-xp / 0.5) * fw_ss(0.0, 0.05, xp) * fw_ss(r * 0.16 - 16.0 * xp - 0.5, r * 0.16 - 16.0 * xp + 1.5, 0.0);
        g = g + rh * a_ * 0.16 * cos(ph) * exp(-r / 150.0);
    }
    return vec3<f32>(0.0, g);
}
// How far out the hole has opened again as the metal lets go: all at once, from the middle, the plate and the metal drawing back to the rim.
fn fb_opened(t: f32, rd: f32) -> f32 {
    if (t <= FW_LETGO) {
        return -1.0;
    }
    return 1.12 * rd * (1.0 - exp(-(t - FW_LETGO) / 0.15));
}
// The shape hanging under the surface, from FB_RUN on: a dimple out of which a bulge hangs (a over the surface, wide w, its ring of dimple d), the bead on its neck. L how far
// the bead's centre is under the surface, R its radius, n the neck's radius, and top how far up the neck goes: past the pinch, what is left of it going back up.
struct FbPool { a: f32, w: f32, d: f32, L: f32, R: f32, n: f32, top: f32 }
fn fb_R(dist: f32) -> f32 {
    return clamp(dist * 0.085, 9.0, 22.0);
}
fn fb_pool(t: f32, Rd: f32) -> FbPool {
    let x = t - FB_PIN;
    // (the bead's hang: slowly out of the bulge, heavier and heavier, the last of it drawn long by its own weight)
    let long = clamp((x + 0.63) / 0.63, 0.0, 1.0);
    let L = FB_LONG * (0.17 * fw_ss(-1.15, -0.63, x) + 0.83 * long * long * long) + 1.4 * sin(t * 8.3) * fw_ss(-0.9, -0.57, x) * (1.0 - long);
    let R = Rd * (0.3 + 0.7 * fw_ss(-1.2, -0.35, x));
    if (x < 0.0) {
        let swell = fw_ss(-1.5, -0.75, x);
        return FbPool(30.0 * swell, 40.0 - 8.0 * swell, 6.0 * fw_ss(-1.6, -1.05, x), L, R, mix(0.62 * R, 0.1 * R, fw_ss(-0.75, 0.0, x)), 0.0);
    }
    // (let go: the bulge goes back up with a bounce or two and the dimple fills)
    let e = exp(-x / 0.62);
    let b = cos(x * 7.6) * e;
    return FbPool(max(30.0 * b, 0.0) + 2.2 * sin(x * 7.6 + 1.0) * e, 32.0, 6.0 * e, 0.0, 0.0, 0.12 * R * (1.0 + 2.2 * fw_ss(0.0, 0.16, x)), FB_LONG * 0.72 * exp(-x / 0.075));
}
// The drop as it hangs, its tip in the neck: fd_bead's own teardrop.
fn fb_drop_at(p0: vec2<f32>, R: f32, wob: f32) -> FdDrop {
    return FdDrop(R, 0.0, 0.0, 1.0 / sqrt(wob), wob, FD_PIV, 0.0, 0.0, p0, 0.0, 1.0);
}
// How far under the surface the drop's centre is, `x` seconds past the pinch: constant gravity, to touch the land at FD_BEAT.
fn fb_fall(x: f32, y0: f32, R: f32) -> f32 {
    let T = FD_BEAT - FB_PIN;
    let g = 2.0 * (y0 - FB_LONG - R - FB_V0 * T) / (T * T);
    return FB_LONG + FB_V0 * x + 0.5 * g * x * x;
}
fn fb_wobble(x: f32) -> f32 {
    return 1.0 + (0.2 * cos(x * 13.5) + 0.05 * cos(x * 21.0 + 1.0)) * exp(-x / 0.8);
}
fn fb_sdf(p: vec3<f32>, y0: f32, P: FbPool, d: FdDrop) -> f32 {
    let y = p.y - y0;
    let rho = length(p.xz);
    let u = rho / P.w;
    let den = 1.0 + u * u;
    let yc = -P.a / den + P.d * exp(-u * u * 0.18);
    let sl = 2.0 * P.a * u / (den * den * P.w);
    var s = (yc - y) / sqrt(1.0 + sl * sl) * 0.85;
    if (P.R > 0.0 && P.L > 0.0) {
        let b = fd_bead(p - vec3<f32>(0.0, y0 - P.L, 0.0), d);
        let ny = clamp(y, -P.L + 0.6 * P.R, -0.3 * P.a);
        let wide = P.n * (1.0 + 2.0 * fw_ss(-P.L * 0.5, -0.1 * P.a, ny));
        let neck = length(vec2<f32>(rho, y - ny)) - wide;
        s = fd_smin(s, fd_smin(b, neck, 0.5 * P.R), 2.5 + 0.34 * P.a);
    } else if (P.top > 0.5) {
        // (the neck's stump, pulled back up into the bulge)
        let ny = clamp(y, -P.top, 0.0);
        s = fd_smin(s, length(vec2<f32>(rho, y - ny)) - P.n, 4.0);
    }
    return s;
}
fn fb_normal(p: vec3<f32>, y0: f32, P: FbPool, d: FdDrop) -> vec3<f32> {
    let e = 0.25;
    let a = fb_sdf(p + vec3<f32>(e, -e, -e), y0, P, d);
    let b = fb_sdf(p + vec3<f32>(-e, -e, e), y0, P, d);
    let c = fb_sdf(p + vec3<f32>(-e, e, -e), y0, P, d);
    let f = fb_sdf(p + vec3<f32>(e, e, e), y0, P, d);
    return normalize(vec3<f32>(a - b - c + f, -a - b + c + f, -a + b - c + f));
}
fn fd_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
// The metal's look: the droplet's chrome, the picture of the tube under it (fd_round), and a hard light off the rim of the world to catch the beads on.
fn fb_chrome(v: vec3<f32>, S: vec3<f32>, n: vec3<f32>, gq: vec3<f32>, seen: f32) -> vec3<f32> {
    var c = fd_chrome(v, S, n, gq, 0.0);
    let r = reflect(v, n);
    // (over it is the metal's own roof, not the sky)
    c = mix(c, fd_round(vec3<f32>(r.x, r.z * 0.42, r.y)) * 1.6 + vec3<f32>(0.05, 0.055, 0.06), fd_ss(-0.1, 0.2, r.y));
    // (the world in it. What a mirror overhead really shows is the floor behind the eye, which isn't on the picture: this bends its rays out to the walls round the hole, which are, and the
    // metal takes the land's own colours, bent by every lump in it)
    let side = vec3<f32>(r.x * 3.2, 0.3 + 0.5 * abs(r.y), r.z * 3.2) + 0.65 * v;
    let ro = project_rel(normalize(side) * 600.0);
    var there = seen * select(0.0, fd_ss(0.0, 0.14, min(min(ro.x, 1.0 - ro.x), min(ro.y, 1.0 - ro.y))), ro.z > 0.0);
    // (the land only: the picture still has the day's sky in the hole)
    if (there > 0.0 && is_sky(depth_at(ro.xy))) {
        there = 0.0;
    }
    if (there > 0.0) {
        let l = fd_sample(ro.xy);
        c = mix(c, l * (0.32 + 1.5 * luminance(l)) * 1.15 + c * 0.25, 0.85 * there);
    }
    let k1 = max(dot(r, normalize(vec3<f32>(0.5, -0.62, 0.3))), 0.0);
    let k2 = max(dot(r, normalize(vec3<f32>(-0.7, -0.5, -0.45))), 0.0);
    let day = 0.14 + 0.86 * fd_ss(-0.2, 0.1, frame.sun.y);
    c = c + (vec3<f32>(1.0, 0.98, 0.95) * (0.95 * pow(k1, 150.0) + 0.1 * pow(k1, 6.0)) + vec3<f32>(0.75, 0.85, 1.05) * (0.75 * pow(k2, 110.0) + 0.08 * pow(k2, 5.0))) * day;
    return c;
}
// ---- no edge to it: the metal doesn't stop at the land's end but creeps out over the land round it, in runs, thinning to a wet shine and ending in smears, the land's dark places
// (water, valleys, shadow) taking it first, so its own colours and grain show through as it goes. `q` a place on the land, `rho` how far out, the rim `rd`. Out: how far inside the metal, inside the wet.
fn fb_creep(q: vec2<f32>, rho: f32, rd: f32, t: f32, S: vec2<f32>) -> vec2<f32> {
    let th = atan2(q.y, q.x);
    let fa = 0.5 + 0.5 * sin(th * 3.0 + 1.0 + 0.8 * sin(th * 2.0 + 0.5));
    let fb = 0.5 + 0.5 * sin(th * 7.0 - 0.7 + 1.1 * sin(th * 3.0));
    let fc = 0.5 + 0.5 * sin(th * 17.0 + 2.0 + 1.3 * sin(th * 5.0));
    let runs = 0.22 + 0.6 * fa * fa + 0.5 * fb * fb * fb + 0.35 * fc * fc * fc * fc;
    let when_ = FB_MELT + 1.3 * fb_late(q / rho, S);
    let n1 = fbm(q * 0.021) - 0.5;
    let n2 = fbm(q * 0.083 + 9.0) - 0.5;
    let back = 1.0 - fw_ss(FW_LETGO + 0.12, FW_LETGO + 0.6, t);
    let out_ = rho - rd;
    let g = fw_ss(when_, when_ + 3.4, t);
    let f = 150.0 * runs * g * back - out_ + (70.0 * n1 + 34.0 * n2) * fw_ss(0.0, 0.3, g) - 40.0 * (1.0 - back) + 90.0 * fw_ss(0.05, 0.6, g) * back * (1.0 - fw_ss(0.0, 90.0, out_));
    let wet = (150.0 * runs * g + 40.0 * fw_ss(0.0, 0.3, g)) * (1.0 - fw_ss(FW_LETGO + 0.5, FW_LETGO + 1.0, t)) - out_ + 60.0 * n1;
    return vec2<f32>(f, wet);
}
fn fb_on_land(colIn: vec3<f32>, v: vec3<f32>, q: vec2<f32>, rho: f32, far: f32, rd: f32, t: f32, S: vec2<f32>, gq: vec3<f32>, g: FwBend, at: vec3<f32>) -> vec3<f32> {
    var col = colIn;
    let px = frame.view_params.w / frame.resolution.y;
    let c = fb_creep(q, rho, rd, t, S);
    if (c.y < -40.0 && c.x < -90.0) {
        return col;
    }
    let lum = luminance(col);
    let rh = q / rho;
    // ---- the wet: a shine on the land ahead of it ----------------------------------------------------------------------------
    let fl = fb_flow(q, t, px * far);
    let f = c.x + 64.0 * (0.22 - lum);
    let w = fw_ss(-40.0, 6.0, c.y + 40.0 * (0.22 - lum));
    if (w > 0.0) {
        let n = normalize(fd_returned(normalize(vec3<f32>(-fl.y * 0.6, -1.0, -fl.z * 0.6)), g, at));
        col = col * (1.0 - 0.4 * w) + fb_chrome(v, v * far, n, gq, 1.0) * 0.2 * w;
    }
    // ---- the metal, thinning to nothing: it ends in smears and thin runs. Long thin ones along the way it is going, and it keeps to the low ground (lum) ------
    let run = fbm(rh * 30.0 + vec2<f32>(rho * 0.0045, -rho * 0.0031)) - 0.5;
    let run2 = fbm(rh * 83.0 + vec2<f32>(-rho * 0.006, rho * 0.0042)) - 0.5;
    let smear = fbm(q * 0.047 + rh * 3.0 + 5.0) - 0.5;
    let f2 = f + (170.0 * run + 70.0 * run2 + 60.0 * smear) * (1.0 - fw_ss(30.0, 130.0, f)) - 16.0;
    let a = fw_ss(0.0, 26.0, f2);
    let thick = fw_ss(14.0, 90.0, f);
    let gr = fl.yz * (2.2 - 1.4 * thick) + rh * 0.6 * (1.0 - thick) * sin(f * 0.17 + 0.03 * (q.x - q.y));
    if (a > 0.0) {
        let n = normalize(fd_returned(normalize(vec3<f32>(-gr.x, -1.0, -gr.y)), g, at));
        let ch = fb_chrome(v, v * far, n, gq, 1.0);
        // (thin, it is a film on the land: the land's own colours in it)
        col = mix(col, mix(col * 0.75 + ch * (0.22 + 1.1 * col), ch, thick), a);
    }
    return col;
}
fn fb_boil(colIn: vec3<f32>, v: vec3<f32>, far: f32, t: f32, mq: vec3<f32>, gq: vec3<f32>, g: FwBend, at: vec3<f32>) -> vec3<f32> {
    var col = colIn;
    let o = fd_unturn(mq + vec3<f32>(0.0, FW_EYE, 0.0), g, at, true);
    let d = fd_unturn(v, g, at, false);
    let rim = fw_roll(g.edge, 0.0, g).xy;
    let rd = rim.x;
    let y0 = rim.y + FB_UP;
    let px = frame.view_params.w / frame.resolution.y;
    let Rd = fb_R(g.d);
    let S0 = fb_source(g);
    // ---- what has crept out on to the land ---------------------------------------------------------------------------------------
    if (far < 1.0e6) {
        let P = o + d * far;
        let rho = length(P.xz);
        if (rho > 0.7 * rd && rho < rd + 300.0 && P.y > y0 - 320.0) {
            col = fb_on_land(col, v, P.xz, rho, far, rd, t, S0, gq, g, at);
        }
    }
    // ---- the plate and the metal on it ---------------------------------------------------------------------------------------
    if (d.y > 0.05) {
        let s = (y0 - o.y) / d.y;
        let q = o.xz + d.xz * s;
        let r = length(q);
        if (s > 0.0 && s < far + 8.0 && r < rd * FB_FIT) {
            let S = S0;
            let ps = px * s;
            let th = atan2(q.y, q.x);
            // (not vnoise: its cells don't quite meet on some drivers, which on an edge this clean shows as square cuts)
            let wn0p = q * 0.0135 + vec2<f32>(4.0, 1.0);
            let wn0 = 0.3 * sin(wn0p.x + 1.4 * sin(wn0p.y * 0.9 + 1.0)) + 0.2 * sin(wn0p.y * 1.7 - 1.2 * sin(wn0p.x * 1.3 + 2.0));
            // (thick, so its edge wanders in lobes, with no fray to it)
            let wp = q * 0.041 + vec2<f32>(0.35 * t + 0.5 * fb_ramp(34.5, 36.0, t), -0.27 * t);
            let wn1 = 0.3 * sin(wp.x + 1.6 * sin(wp.y * 1.3)) + 0.2 * sin(wp.y * 1.9 - 1.3 * sin(wp.x * 1.5 + 1.0));
            let mt = fb_metal(q, t, S, rd);
            // (its edge wanders, a skin of it thin at the very edge)
            let wr = fw_ss(34.2, 35.8, t) * (1.0 - fw_ss(FB_SEAL, FB_SEAL + 0.3, t));
            var edge = -mt.d + 44.0 * wn0 + (24.0 + 30.0 * wr) * wn1;
            // (and it doesn't start as a ring: it comes up over the land's end from one side, round to the other)
            let la = fb_late(q / max(r, 1.0), S);
            edge = edge - 80.0 * (1.0 - fw_ss(FB_MELT + 1.1 * la, FB_MELT + 1.1 + 1.5 * la, t));
            var soft = max(ps, 3.0);
            // (the seethe: at the fronts and round the pockets, in a band that widens as they close. It lifts the edge itself)
            var se = vec3<f32>(0.0);
            let bu = fw_ss(33.4, 35.2, t) * (1.0 - fw_ss(FB_SEAL - 0.05, 37.5, t));
            let wide = 130.0 + 190.0 * fw_ss(34.8, 36.1, t);
            // (and it comes in knots, not evenly)
            let knot = fw_ss(-0.35, 0.75, sin(q.x * 0.0127 + 0.2 * t + 2.0 * sin(q.y * 0.0091)) + 0.7 * sin(q.y * 0.0173 - 0.15 * t + 1.0));
            let am = bu * fw_ss(-90.0, -20.0, edge) * (1.0 - fw_ss(0.5 * wide, wide, edge)) * (0.5 + 0.5 * knot);
            if (am > 0.002) {
                se = fb_seethe(q, t, am * (0.55 + 0.75 * fw_ss(34.5, 35.9, t)), edge);
                edge = edge + 2.0 * se.x * fw_ss(150.0, 40.0, edge);
            }
            if (t > FW_LETGO) {
                // (it tears: a ragged edge that wanders, runs and grain in it, thin metal first)
                let open = fb_opened(t, rd) * (1.0 + 0.055 * sin(th * 2.0 + 1.0 + 1.3 * sin(th * 3.0 - t * 2.0)) + 0.03 * sin(th * 5.0 - 0.7 + 0.9 * sin(th * 2.0 + t)));
                let rag = fbm(q * 0.031 + vec2<f32>(t * 0.6, 2.0)) - 0.5;
                let grain = fbm(q * 0.16 + 7.0) - 0.5;
                edge = min(edge, r - open + 110.0 * wn0 + 90.0 * rag + 34.0 * grain);
                soft = max(ps, 7.0);
            }
            let cov = saturate(edge / soft + 0.5);
            if (cov > 0.0) {
                let fl = fb_flow(q, t, ps);
                let m = max(edge, 0.0);
                let ex = exp(-m / FB_EDGE);
                let gr = mt.g * (-FB_THICK / FB_EDGE * ex) + fl.yz * (1.0 - 0.75 * ex) * 0.8 + fb_bubbles(q, t, S, rd) + se.yz;
                let n = normalize(fd_returned(normalize(vec3<f32>(-gr.x, -1.0, -gr.y)), g, at));
                // (the lip is too steep to see the land in: it would only be its grain)
                col = mix(col, fb_chrome(v, v * s, n, gq, 1.0 - ex), cov);
            }
        }
    }
    // ---- the bulge, the bead and its neck ----------------------------------------------------------------------------------
    if (t > FB_PIN - 1.6 && t < FB_PIN + 2.6 && d.y > 0.05) {
        let P = fb_pool(t, Rd);
        let D = fb_drop_at(vec2<f32>(0.0), P.R, mix(1.0, fb_wobble(0.0), fw_ss(FB_PIN - 0.46, FB_PIN, t)));
        let bot = -(max(P.L, P.top) + 1.5 * P.R + 4.0);
        let a = (y0 + bot - o.y) / d.y;
        let b = (y0 + 3.0 - o.y) / d.y;
        let bound = max(3.0 * P.w, 2.6 * P.R);
        let s0 = o.xz + d.xz * a;
        let s1 = o.xz + d.xz * b;
        let sd = s1 - s0;
        let cl = s0 + sd * clamp(-dot(s0, sd) / max(dot(sd, sd), 1.0e-4), 0.0, 1.0);
        if (dot(cl, cl) < bound * bound && a > 0.0) {
            var s = a;
            var best = 1.0e9;
            var sb = s;
            var hit = false;
            for (var i = 0; i < 44; i += 1) {
                let e = fb_sdf(o + d * s, y0, P, D);
                let rel = e / (px * s);
                if (rel < best) {
                    best = rel;
                    sb = s;
                }
                if (rel < 0.15) {
                    hit = true;
                    sb = s + e;
                    break;
                }
                s += max(e, 0.15 * px * s);
                if (s > b) {
                    break;
                }
            }
            let cov = saturate(1.0 - best);
            if (cov > 0.0 && sb < far) {
                let q = o + d * sb;
                let n0 = fb_normal(q, y0, P, D);
                let fl = fb_flow(q.xz, t, px * sb);
                let keep = fw_ss(-12.0, -2.0, q.y - y0);
                let n = normalize(fd_returned(normalize(n0 - vec3<f32>(fl.y, 0.0, fl.z) * 0.8 * keep), g, at));
                // (only what really hangs: the rest is the surface's, drawn above)
                col = mix(col, fb_chrome(v, v * sb, n, gq, 1.0), cov * fw_ss(-0.4, -3.5, q.y - y0));
            }
        }
    }
    // ---- the drop, let go ---------------------------------------------------------------------------------------------------
    if (t >= FB_PIN && t < FD_BEAT + 0.16) {
        let x = t - FB_PIN;
        let w = fb_wobble(x);
        // (its tip swaying a little, and a little off the plumb line on the way, on it as it lands)
        let D = fb_drop_at(vec2<f32>(sin(x * 4.3 + 0.4), cos(x * 3.1)) * 0.04 * exp(-x / 1.1), Rd, w);
        let cy = y0 - fb_fall(x, y0, Rd);
        let off_ = clamp(FD_BEAT - t, 0.0, 1.0);
        let c = vec3<f32>(1.6 * sin(x * 1.9 + 0.5) * off_, cy, 1.1 * sin(x * 1.4 + 2.1) * off_);
        let bc = c + vec3<f32>(0.0, 0.36 * Rd, 0.0) - o;
        let rb = 1.9 * Rd * max(w, 1.0 / sqrt(w));
        let bcd = dot(bc, d);
        let miss = length(bc - d * bcd);
        // (a bright point the eye can stay on, as long as it is small, and a little soft light round it all the way down)
        if (bcd > 0.0) {
            let ang = miss / bcd;
            let close = fw_ss(0.05, 0.012, Rd / bcd);
            col = col + vec3<f32>(0.92, 0.96, 1.05) * (exp(-ang / (0.0016 + 0.25 * Rd / bcd * (1.0 - close))) * 0.5 * (0.35 + 0.65 * close) + exp(-ang / 0.014) * 0.07);
        }
        if (miss < rb && bcd > 0.0) {
            var s = max(bcd - rb, 0.05);
            var best = 1.0e9;
            var sb = s;
            for (var i = 0; i < 40; i += 1) {
                let e = fd_bead(o + d * s - c, D);
                let rel = e / (px * s);
                if (rel < best) {
                    best = rel;
                    sb = s;
                }
                if (rel < 0.1) {
                    sb = s + e + fd_bead(o + d * (s + e) - c, D);
                    break;
                }
                s += max(e, 0.15 * px * s);
                if (s > bcd + rb) {
                    break;
                }
            }
            let cov = saturate(1.0 - best);
            if (cov > 0.0 && sb < far + 0.4) {
                let n = normalize(fd_returned(fd_bead_n(o + d * sb - c, D), g, at));
                col = mix(col, fb_chrome(v, v * sb, n, gq, 1.0), cov);
            }
        }
    }
    return col;
}
// ---- the hit: on the land, where it lands. A little crown of the metal thrown up and out and falling back, a ring of it running out over the land, a splash that soaks in.
const FB_SPLASH: i32 = 14;
fn fb_hit(colIn: vec3<f32>, v: vec3<f32>, far: f32, off: vec3<f32>, sky0: bool, t: f32, mq: vec3<f32>, gq: vec3<f32>, g: FwBend, at: vec3<f32>) -> vec3<f32> {
    var col = colIn;
    let a = t - FD_BEAT;
    let Rd = fb_R(g.d);
    let o = fd_unturn(mq + vec3<f32>(0.0, FW_EYE, 0.0), g, at, true);
    let d = fd_unturn(v, g, at, false);
    // ---- before it: its shadow on the land, closing up as it comes down, as the first droplet's did ------------------------------------
    if (a < 0.0) {
        if (!sky0) {
            let P = o + d * far;
            let hh = -a * (140.0 + 200.0 * -a);
            let sr = Rd * (1.5 + 0.05 * hh);
            col = col * (1.0 - exp(-dot(P.xz, P.xz) / (sr * sr)) * 0.6 * exp(-abs(P.y) / 12.0) * fd_ss(420.0, 30.0, hh));
        }
        return col;
    }
    // ---- on the land ------------------------------------------------------------------------------------------------------
    if (!sky0) {
        let P = o + d * far;
        let r = length(P.xz);
        if (abs(P.y) < 26.0 && r < 90.0) {
            let front = Rd * 0.6 + 46.0 * (1.0 - exp(-a / 0.2));
            let x = (r - front) / (1.0 + 2.4 * a);
            let fade = exp(-a / 0.3);
            col = col + vec3<f32>(0.85, 0.92, 1.05) * exp(-x * x) * fade * 0.75 * saturate(a / 0.02);
            // (the splash: chrome on the land, thrown out with the ring, soaking in by the time the metal lets go)
            let wet = Rd * (0.4 + 1.5 * (1.0 - exp(-a / 0.09))) * (1.0 + 0.12 * sin(atan2(P.z, P.x) * 5.0 + 1.0) + 0.08 * sin(atan2(P.z, P.x) * 11.0));
            let dry = wet * fw_ss(0.5, 1.0, a);
            let edge = min(wet - r, r - dry);
            let cov = saturate(edge / (0.0016 * far) + 0.5);
            if (cov > 0.0) {
                let nr = 0.5 * fw_ss(0.0, 2.0, edge) * 0.0 + 0.8 * fw_ss(2.5, 0.0, min(edge, 2.5)) * sign(wet - r - (r - dry));
                let rh = P.xz / max(r, 0.01);
                let n = normalize(fd_returned(normalize(vec3<f32>(rh.x * nr + 0.25 * sin(r * 1.6 - a * 26.0) * exp(-a / 0.25) * rh.x, 1.0, rh.y * nr + 0.25 * sin(r * 1.6 - a * 26.0) * exp(-a / 0.25) * rh.y)), g, at));
                col = mix(col, fd_chrome(v, v * far, n, gq, 0.8), cov);
            }
        }
    }
    // ---- the crown --------------------------------------------------------------------------------------------------------
    if (a < 0.95) {
        let px = frame.view_params.w / frame.resolution.y;
        let bc = -o;
        let bcd = dot(bc, d);
        if (length(bc - d * bcd) < 90.0 && bcd > 0.0) {
            for (var i = 0; i < FB_SPLASH; i += 1) {
                let h = hash21(vec2<f32>(f32(i), 3.0));
                let h2 = fract(h * 19.3);
                let an = (f32(i) + 0.8 * h) * 6.2831853 / f32(FB_SPLASH);
                let vo = 16.0 + 26.0 * h2;
                let vu = 30.0 + 34.0 * fract(h * 7.1);
                let life = a - 0.03 * h;
                if (life <= 0.0) {
                    continue;
                }
                let y = vu * life - 62.0 * life * life;
                if (y < -1.0) {
                    continue;
                }
                let c = vec3<f32>(cos(an) * (Rd * 0.5 + vo * life), y, sin(an) * (Rd * 0.5 + vo * life));
                let rb = (0.35 + 0.5 * h) * 0.2 * Rd * (1.0 - 0.3 * life);
                let oc = c - o;
                let b = dot(oc, d);
                let miss = length(oc - d * b);
                let cov = saturate((rb - miss) / (px * b) + 0.5);
                if (cov > 0.0 && b - rb < far + 1.0) {
                    let z = sqrt(max(rb * rb - miss * miss, 0.0));
                    let n = normalize(fd_returned(normalize(d * (b - z) - oc), g, at));
                    col = mix(col, fd_chrome(v, v * (b - z), n, gq, 0.8), cov);
                }
            }
        }
    }
    return col;
}
fn fd_tau(t: f32) -> f32 {
    return fw_tau(t);
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
        // (to the player's side: the same side whatever they do)
        let way = vec2<f32>(-te.y, te.x);
        let H = fd_arc(d.h - d.stop_h);
        let C = gq + vec3<f32>(way.x * H, d.h, way.y * H);
        // (what the land has reached up inside the drop is taken into it, not seen through it)
        // (until the land has closed over it: a pixel of land in it melts from drop to land as that happens, and has little of the
        // join's light, or the drop's own pixels burn white)
        let swallowed = t >= FD_TOUCH + FD_MEET && t < FD_MELD && !sky0 && fd_bead(off - C, d) < 0.0;
        let under = col;
        col = fd_droplet(under, t, v, gq, C, d, way, far, uv, aspect, land, li, jit);
        var lit = select(0.0, 1.0, !sky0);
        if (swallowed) {
            let closing = fd_ss(FD_MELD - 0.16, FD_MELD, t);
            col = mix(fd_droplet(under, t, v, gq, C, d, way, 1.0e7, uv, aspect, land, li, jit), col, closing);
            lit = mix(0.12, 1.0, closing * closing * closing);
        }
        col = fd_glow(col, t, v, gq, off - gq, lit, far, d);
    }

    // ---- the boil, and what falls from it ---------------------------------------------------------------------------------------
    if (t > FB_MELT && t < FW_LETGO + 1.0) {
        let tau = fd_tau(t);
        let mq = me - tgt;
        let e2 = select(vec2<f32>(1.0, 0.0), mq.xz / max(dist, 0.001), dist > 0.5);
        let g = fw_bend(tau, t, FW_LEN, mq, e2, max(FW_END_K * clamp(frame.view_params.z, 480.0, 20000.0) - dist, 300.0), 0.0);
        let at_ = fw_roll(g.d, g.pin, g);
        col = fb_boil(col, v, far, t, mq, gq, g, at_);
        if (t > 39.2) {
            col = fb_hit(col, v, far, off, sky0, t, mq, gq, g, at_);
        }
    }
    // ---- the touch: a tiny light at the point the moment the tip reaches it, there while it holds, gone as it lets go -----
    let dd = length((uv - pt.xy) * vec2<f32>(aspect, 1.0));
    if (t >= FD_BEAT && t < FD_REL + 0.6 && pt.z > 0.0) {
        let on = fd_ss(FD_BEAT, FD_BEAT + 0.04, t) * (1.0 - fd_ss(FD_REL + 0.42, FD_REL + 0.6, t));
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
