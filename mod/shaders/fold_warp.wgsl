// The Fold's world warp (the fork's render.set-warp): the world's real geometry, the far terrain's tiles too, bent. Every
// terrain and entity vertex comes through `world_warp`, from the camera, and leaves where it is drawn. All of it is a
// function of where the vertex is in the world about the target and of the strike's clock, never of the screen.
//   0-2 s      the hook: the ground bucks at the target, a wave races out over the land
//   2-29 s     the wave covers all in view; behind it the land rolls into curling rings, twists, and the horizon curls up
//              and over; copies of the land near the target come up out of it and open round it like petals
//   29-36 s    all of it drawn in to one mass of land at the target, which falls in to a point: the beat in the dark
//   37 s       the blast: the world flung back out of the point from the middle out, straight again, the crater in it
// strike/fold.rs and fold.wgsl share the FD_* beats.
const FW_CONV: f32 = 29.0;       // all of it starts in
const FW_BEAT: f32 = 36.0;       // the mass a point
const FW_REL: f32 = 37.0;        // the blast
const FW_REL_V: f32 = 1500.0;    // how fast the world comes back, blocks a second
const FW_TAU: f32 = 6.2831853;
const FW_COPIES: f32 = 6.0;
const FW_DISC: f32 = 130.0;      // how far the copies' land reaches from the target (lib.rs asks for these sections)

fn fw_ss(a: f32, b: f32, x: f32) -> f32 {
    let t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
fn fw_rot(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}
// How far the front has come, blocks from the target: under the player `d` away at about 2 s, whatever the range, so that
// they watch it come, then racing out past all in view by about 16 s.
fn fw_front(t: f32, d: f32) -> f32 {
    return max(d, 90.0) * 0.42 * t + 16.0 * t * t;
}
// The wave at the front and the ripples it leaves: (lift, lean out), for a point r from the target. The crest is highest
// near the target and dies away outwards, and at any distance it stays big enough to see from there.
fn fw_ripple(t: f32, r: f32, d: f32) -> vec2<f32> {
    let x = r - fw_front(t, d);
    let w = 17.0 + 0.04 * r;
    let amp = (38.0 * exp(-r / 300.0) + 9.0 + 0.012 * r) * (1.0 - fw_ss(13.0, 22.0, t)) * fw_ss(0.0, 0.25, t);
    let head = exp(-x * x / (2.0 * w * w));
    // (what it leaves behind it: rings dying away)
    let tail = select(0.0, exp(x / (240.0 + 0.5 * r)), x < 0.0);
    let k = 1.7 / w;
    let lift = amp * (head * 1.25 + 0.6 * tail * sin(x * k * 0.75));
    let lean = amp * 0.55 * (head * sin(x * k));
    return vec2<f32>(lift, lean);
}
// The land from the target in its bent place: rings of it rolling over towards the target, `b` how bent, with a building's
// height kept along the land's own normal so that it leans and turns over with it.
fn fw_rings(sIn: f32, h: f32, a: f32, b: f32, t: f32) -> vec2<f32> {
    let s = max(sIn, 0.0);
    // (rings that widen with the distance, the same shape at every scale)
    let wid = 96.0 + 0.3 * s;
    let k = FW_TAU / wid;
    let ph = FW_TAU * log(1.0 + 0.3 * s / 96.0) / 0.3 + t * 1.1;
    let petals = 0.62 + 0.38 * cos(a * 6.0 + sin(s * 0.012) * 1.6);
    let am = (0.72 + 0.6 * exp(-s / 210.0)) * b * petals / k;
    let c = cos(ph);
    let sn = sin(ph);
    // (a trochoid, the crest thrown in towards the target: past 1 / k it loops over itself)
    let R = s + am * (sn - 0.7 * (1.0 - c));
    let Y = am * (1.0 - c);
    let tan = vec2<f32>(1.0 + am * k * (c - 0.7 * sn), am * k * sn);
    let n = vec2<f32>(-tan.y, tan.x) / max(length(tan), 0.08);
    return vec2<f32>(R, Y) + n * h;
}
// The land past `r0` curling up and over about a tube of radius `rc`, its top inwards: the horizon rising all round, up
// over the sky, all the world to the end of the far terrain gathered on the tube by `fmax` (radians).
fn fw_tube(R: f32, Y: f32, r0: f32, rc: f32, fmax: f32) -> vec2<f32> {
    let u = R - r0;
    if (u <= 0.0 || fmax < 0.001) {
        return vec2<f32>(R, Y);
    }
    let f = fmax * (1.0 - exp(-u / (rc * fmax)));
    let c = cos(f);
    let s = sin(f);
    return vec2<f32>(r0 + rc * s - Y * s, rc * (1.0 - c) + Y * c);
}
// A point of the land (r from the target at bearing a, `h` over it) on the ball the world ends in: the pole over the target,
// the far land gathering round the bottom. `axis` turns that pole, for the copies.
fn fw_ball(a: f32, r: f32, h: f32, rb: f32, axis: vec2<f32>) -> vec3<f32> {
    let th = 3.09 * (1.0 - exp(-r / 340.0));
    let rr = rb + clamp(h, -16.0, 90.0) * 0.55 * min(rb / 90.0, 1.0);
    var p = rr * vec3<f32>(sin(th) * cos(a), cos(th), sin(th) * sin(a));
    let yz = fw_rot(p.yz, axis.x);
    p = vec3<f32>(p.x, yz.x, yz.y);
    let xy = fw_rot(p.xy, axis.y);
    return vec3<f32>(xy.x, xy.y, p.z);
}

// A bubble round the eye: what the warp has moved stays this far off, sliding round it, until all of it goes in to the mass.
fn fw_clear(moved: vec3<f32>, from_: vec3<f32>, keep: f32) -> vec3<f32> {
    let d = length(moved);
    let rad = 46.0 * keep * fw_ss(3.0, 24.0, length(moved - from_));
    if (d >= rad || d < 0.001) {
        return moved;
    }
    return moved * (rad / d);
}

fn world_warp(pos: vec3<f32>, copy: u32) -> Warped {
    let w = globals.warp;
    let t = w[0].w + w[4].w * 0.05;
    // the target and the player as they fired, from the camera
    let tgt = (w[0].xyz - w[4].xyz) - w[5].xyz;
    let me = (w[3].xyz - w[4].xyz) - w[5].xyz;
    let seed = w[2].x;
    var Q = pos - tgt;
    let Q0y = Q.y;
    let r = length(Q.xz);
    let a = atan2(Q.z, Q.x);

    var out = Warped(pos, vec3<f32>(1.0));
    // (the mod builds this ahead of the first strike, for a frame, with no parameters: nothing to do)
    if (w[2].y < 0.5) {
        return out;
    }
    // (the rock under the land is out of it: everything under y 40 is pressed up to it and left out, or its depth would be
    // thrown about by every fold and the bedrock show. The far terrain's columns run down to the bottom of the world.)
    let floor_y = 40.0 - (w[4].y + w[5].y) - tgt.y;
    // ---- what the world comes back from: the mass at the target, how drawn in this vertex is --------------------------
    let dist = length(me.xz - tgt.xz);
    let since0 = t - FW_REL;
    let pressed = 1.0 - fw_ss(0.0, 1.3, since0);
    let rock = pressed * fw_ss(0.0, 0.1, t);
    let under = Q.y < floor_y;
    Q.y = mix(Q.y, max(Q.y, floor_y + 0.02 * (Q.y - floor_y)), rock);
    // (flung back: the near land first, all of it home within a second and a quarter, overshooting a touch)
    let since = t - FW_REL;
    let rel_r = since * FW_REL_V + 0.5 * since * since * 500.0;
    let u_back = clamp(since / (0.28 + 0.95 * (1.0 - exp(-r / 1500.0))), 0.0, 1.0);
    let back = select(0.0, 1.0 - pow(1.0 - u_back, 3.0), since >= 0.0);
    // (the far land starts in first and arrives with the near)
    let delay = 3.2 * exp(-r / 900.0);
    var cv = fw_ss(FW_CONV + delay, 34.8, t);
    cv = cv * cv * (1.0 - back);
    // the ball's radius, falling in to the point at the beat
    let rb = mix(150.0, 104.0, fw_ss(FW_CONV, 35.0, t)) * (1.0 - 0.985 * fw_ss(35.35, FW_BEAT - 0.1, t)) + 2.0 * fw_ss(FW_REL - 0.4, FW_REL, t);
    let spin = 0.3 * (t - FW_CONV) + 2.4 * fw_ss(32.0, FW_BEAT, t) * fw_ss(32.0, FW_BEAT, t) * (t - 32.0);
    let ballc = vec3<f32>(0.0, 16.0 + 90.0 * (1.0 - fw_ss(35.0, FW_BEAT, t)), 0.0);

    if (copy > 0u) {
        // ---- the copies: the land near the target again, each opening out round it like a petal, its top towards the
        // middle, the land's edge run out to nothing so that it ends in a clean disc ------------------------------------
        let k = f32(copy) - 1.0;
        let n = FW_COPIES;
        let up = fw_ss(6.0 + k * 1.7, 12.0 + k * 1.7, t);
        if (up < 0.001 || t >= FW_REL + 0.5) {
            out.pos = tgt + vec3<f32>(0.0, -4000.0, 0.0);
            out.tint = vec3<f32>(-1.0);
            return out;
        }
        // (each its own turn of the land, a saucer of it, rising out of the middle to a ring of islands round the target,
        // short of the player whatever the range)
        let crown = clamp(dist * 0.46, 60.0, 240.0);
        let scale = 0.5 * up;
        let turn = (k + 1.0) * FW_TAU / n + seed + 0.09 * t;
        let v = fw_rot(Q.xz, turn) * scale;
        let saucer = r * r * 0.0021 * scale;
        var L = vec3<f32>(v.x, Q.y * scale + saucer, v.y);
        // (tilted in towards the target, the ring turning slowly)
        let bearing = k * FW_TAU / n + seed * 0.37 + 0.11 * (t - 6.0);
        let u = vec2<f32>(cos(bearing), sin(bearing));
        let g = vec2<f32>(-u.y, u.x);
        let along = dot(L.xz, u);
        let across = dot(L.xz, g);
        let tilt = 0.5 + 0.22 * sin(t * 0.3 + k * 1.9);
        let cs = cos(tilt);
        let sn = sin(tilt);
        let out_ = crown * up + along * cs - L.y * sn;
        let high = along * sn + L.y * cs + up * (64.0 + 60.0 * fract(k * 0.382) + 9.0 * sin(t * 0.5 + k * 2.1));
        var P = vec3<f32>(u.x * out_ + g.x * across, high, u.y * out_ + g.y * across);
        // ---- in to the mass
        let cc = fw_ss(FW_CONV + 0.4 * k, 33.5 + 0.2 * k, t) * (1.0 - fw_ss(FW_REL - 0.05, FW_REL + 0.6, t));
        if (cc > 0.0) {
            let axis = vec2<f32>(1.1 + k * 1.3 + seed, 0.7 * k + spin);
            let B = fw_ball(a + spin, r, Q.y, rb * (0.82 + 0.1 * k), axis);
            P = mix(P, B + ballc, cc * cc);
        }
        out.pos = fw_clear(P + tgt, pos, 1.0 - cc);
        // (the disc's edge and all under its crust left out, in place: moved away they would drag their faces after them)
        out.tint = select(vec3<f32>(0.92 + 0.08 * k / n), vec3<f32>(-1.0), r > FW_DISC || Q0y < -26.0);
        return out;
    }

    if (t <= 0.0 || t > 46.0) {
        return out;
    }

    // ---- the wave -------------------------------------------------------------------------------------------------------
    let rip = fw_ripple(t, r, dist);
    let live = 1.0 - back;
    // (the ground bucking at the target: the first second's hook)
    let buck = 78.0 * exp(-r * r / (2.0 * 70.0 * 70.0)) * fw_ss(0.0, 0.2, t) * (1.0 - fw_ss(0.8, 3.0, t)) * cos((t - 0.2) * 4.2);
    let front = fw_front(t, dist);
    // how bent the land is here: nearest the target first, the reach growing behind the front
    let reach = 40.0 + 90.0 * max(t - 1.2, 0.0) + 16.0 * max(t - 6.0, 0.0) * max(t - 6.0, 0.0);
    let eye_r = clamp(dist * 0.8, 50.0, 200.0);
    let eye = fw_ss(eye_r * 0.3, eye_r, length(vec3<f32>(pos.x, pos.y * 0.5, pos.z)));
    let b0 = 1.0 - fw_ss(reach * 0.45, reach, r);
    let bend = b0 * fw_ss(0.6, 6.0, t) * live * (1.0 - fw_ss(front * 0.8, front, r)) * (0.12 + 0.88 * exp(-r / 800.0));
    var rr = r + rip.y * live;
    var yy = Q.y + (rip.x + buck) * live;
    // the rings
    let ring = fw_rings(rr, yy, a, bend * eye, t);
    rr = ring.x;
    yy = ring.y;
    // the twist, more the nearer, and the higher up (towers turn into corkscrews)
    let near = exp(-r / 300.0);
    let th = bend * eye * ((1.5 * near + 0.3) * sin(t * 0.18 + seed) + Q.y * 0.014 * near);
    // the horizon up and over: the tube starts beyond the player whatever the range
    let curl = fw_ss(1.5, 17.0, t) * live;
    let r0 = max(dist + 170.0, 420.0);
    let rc = mix(2600.0, 620.0, curl);
    let up = fw_tube(rr, yy, r0, rc, curl * 3.5);
    rr = up.x;
    yy = up.y;
    let aa = a + th;
    var P = vec3<f32>(rr * cos(aa), yy, rr * sin(aa));
    // (the world right round the eye is left straight while they stand on it)
    let keep = 1.0 - eye;
    P = mix(P, vec3<f32>(Q.x, Q.y + rip.x * 0.2 * live, Q.z), keep * (1.0 - cv));

    // ---- in to the mass -------------------------------------------------------------------------------------------------
    if (cv > 0.0) {
        let axis = vec2<f32>(0.0, spin * 0.3);
        let B = fw_ball(a + spin, r, Q.y, rb, axis);
        P = mix(P, B + ballc, cv);
    }
    // ---- flung back, and what is left ringing ---------------------------------------------------------------------------
    if (t >= FW_REL) {
        let x = r - rel_r;
        let fade = 1.0 - fw_ss(FW_REL + 1.5, 45.0, t);
        P.y = P.y + (18.0 * exp(-r / 700.0) + 4.0) * fade * back * sin(x * 0.045) * exp(x / 340.0);
    }
    out.pos = fw_clear(P + tgt, pos, (1.0 - cv) * (1.0 - back));
    // ---- the crest lit: the wave's own line over the land ---------------------------------------------------------------
    let x = r - front;
    let seam = exp(-x * x / (2.0 * (20.0 + 0.04 * r) * (20.0 + 0.04 * r))) * (1.0 - fw_ss(14.0, 22.0, t));
    out.tint = select(vec3<f32>(1.0 + 0.28 * seam, 1.0 + 0.2 * seam, 1.0 + 0.45 * seam), vec3<f32>(-1.0), under && rock > 0.5);
    return out;
}
