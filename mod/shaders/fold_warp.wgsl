// The Fold's world warp (the fork's render.set-warp): reality folded like paper, the mandala its crease pattern. Every
// terrain and entity vertex comes through `world_warp`, and every pixel of the terrain through `world_fragment` (after the
// `[fragments]` line) with where it really is, so all of it is anchored to the world and none to the screen. The land is a
// thin sheet: what is under it never moves far and is never drawn (see FRAGMENTS, "the sheet").
//   FW_RIPPLE  rings running out of the target, each bigger than the last
//   FW_SCORE   they sharpen into hairline creases racing over the land: the mandala (fw_crease)
//   FW_TEAR    the creases split on the void, painted on the land itself so nothing under it shows
//   FW_FOLD    the land is pinched up at the target and closes ring by ring (fw_chain), its top outwards, a hinge at each
//              ring; radial pleats take up the circumference; the mandala's land shrinks to a pearl on the floor
//   the far land closes round the player (fw_place): the sheet is bent conformally onto the inside of a sphere, so nothing
//              stretches, with the player's feet at its bottom and all the land out to the horizon gathered at the point
//              across from the target. FW_SEAL it has shut: the player is inside, the world on the walls all round
//   FW_CRUSH   that point, the sphere's top, folds down to the target in six stages (fw_tiers), each half the last
//   FW_BEAT    the tip touches the target. Stillness
//   FW_REL     all of it runs backwards, very fast (fw_tau), flat at FW_FLAT, and past it: the sheet flaps (fw_flap), each
//              swing less, the last a fall, FW_SLAM4, which lets the crater show
// The player stands on an island punched out of the sheet (FW_ISLE), left where it is, the sheet sliding by under it.
// strike/fold.rs and fold.wgsl share the beats: keep them in step (`the_warp_keeps_the_beats`).
const FW_RIPPLE: f32 = 6.6;
const FW_SCORE: f32 = 12.0;
const FW_TEAR: f32 = 16.0;
const FW_FOLD: f32 = 19.0;
const FW_SEAL: f32 = 35.0;
const FW_CRUSH: f32 = 35.0;
const FW_BEAT: f32 = 40.0;
const FW_REL: f32 = 40.3;
const FW_FLAT: f32 = 41.1;         // strike/fold.rs's FD_FLAT, FD_SLAM[0]
const FW_SLAM4: f32 = 45.0;        // the last of the slams (strike/fold.rs's FD_SLAM)
const FW_END: f32 = 53.0;
const FW_FADE: f32 = 45.4;         // the comedown begins
const FW_TAU: f32 = 6.2831853;
const FW_PI: f32 = 3.14159265;
const FW_LEN: f32 = 480.0;         // the sheet's length, the last ring (strike/fold.rs's FD_RINGS[4])
const FW_SINK: f32 = 20.0;         // how far the sheet sinks from the island
const FW_ISLE: f32 = 26.0;         // the player's island's radius
const FW_LAND_R: f32 = 300.0;      // from FD_LAND on the crater is in the land within this: nothing is cut under it

// ---- what can be taken out: 0 turns each off -----------------------------------------------------------------------
const FW_IRID: f32 = 1.0;          // the iridescence's strength: 1 is about 36 degrees of hue and a quarter more saturation at its peak
const FW_FRACTAL: f32 = 1.0;       // block faces showing smaller copies of themselves
const FW_SPONGE: f32 = 1.0;        // blocks carved into sponges
const FW_PLEATS: f32 = 1.0;        // the radial pleats
const FW_UNDER: f32 = 1.0;         // the sheet's underside painted as rock
const FW_LAY0: f32 = 27.0;         // the mound lies back, the world drawn in, between these
const FW_LAY1: f32 = 33.0;
const FW_PEARL: f32 = 0.533;      // what the rings' scale comes to as they lie back, of what it was
const FW_CAP: f32 = 0.95;
const FW_SPIKE: f32 = 0.2;         // how much of the cap is the spike down the cones
const FW_DISC: f32 = 130.0;        // how far the cones' land reaches from the target (lib.rs asks for these sections)          // how much of the sphere's top folds down: radians round the point

fn fw_ss(a: f32, b: f32, x: f32) -> f32 {
    let t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
fn fw_rot(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}
fn fw_hash(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(0.1031, 0.1137));
    let d = dot(q, q.yx + 33.33);
    return fract((q.x + d) * (q.y + d));
}
fn fw_ring(i: i32) -> f32 {
    switch i {
        case 0: { return 44.0; }
        case 1: { return 104.0; }
        case 2: { return 176.0; }
        case 3: { return 290.0; }
        default: { return FW_LEN; }
    }
}
// How far along the sheet's curve ring i ends up lying: the bearing of its plate, radians, at `tau`: steep as it goes up,
// laying back to a broad mound with the target on top as the world closes round it.
fn fw_phi(i: i32, tau: f32) -> f32 {
    var a = 0.14;
    var b = 0.08;
    switch i {
        case 0: { }
        case 1: { a = 0.48; b = 0.26; }
        case 2: { a = 0.92; b = 0.5; }
        case 3: { a = 1.52; b = 0.84; }
        default: { a = 1.9; b = 0.7; }
    }
    return mix(a, b, fw_ss(FW_LAY0, FW_LAY1, tau));
}
// The twelve petals: 0 on a petal's middle line, 1 on its edge, each ring's turned half a petal on the last's.
fn fw_petal(a: f32, i: i32) -> f32 {
    let x = a * 6.0 / FW_PI + 0.5 * f32(i & 1);
    return abs(fract(x) - 0.5) * 2.0;
}
// Ring i's outer edge at bearing a: scalloped into twelve pointed tips.
fn fw_rho(i: i32, a: f32) -> f32 {
    let ring = fw_ring(i);
    return ring + 0.16 * ring * (0.5 - fw_petal(a, i));
}
// How closed ring i is (0 flat, 1 shut) at bearing a, on the fold's clock `tau`: a petal's middle leads its edges.
fn fw_p(i: i32, a: f32, tau: f32) -> f32 {
    let t0 = FW_FOLD + 2.1 * f32(i) + 0.7 * fw_petal(a, i);
    return fw_ss(0.0, 3.6, tau - t0);
}
// The fold's clock: the strike's up to FW_REL, then back to FW_FOLD by FW_FLAT, faster and faster, and there it stays.
fn fw_tau(t: f32) -> f32 {
    if (t < FW_BEAT) {
        return t;
    }
    if (t < FW_REL) {
        return FW_BEAT;
    }
    let u = clamp((t - FW_REL) / (FW_FLAT - FW_REL), 0.0, 1.0);
    return FW_BEAT - (FW_BEAT - FW_FOLD + 0.6) * pow(u, 1.7);
}
// ---- the chain ----------------------------------------------------------------------------------------------------------
// The sheet's cross-section at bearing a: from the top pole (the target), plate after rigid plate, each a ring, hinged at
// its edge, the last lying on the ground. A point r along it: (R out from the axis, Y up, the plate's angle).
// A plate shrinks to `kappa` as it closes, so what has closed is a dome no wider than the globe, inside the player's distance
// whatever it is, and what hasn't lies flat and slides in to the dome's foot.
fn fw_chain(r: f32, a: f32, t: f32, kappa: f32) -> vec3<f32> {
    var prev = 0.0;
    var R = 0.0;
    var Y = 0.0;
    var total = 0.0;
    var here = 0.0;
    for (var i = 0; i < 5; i += 1) {
        let rho = fw_rho(i, a);
        let p = fw_p(i, a, t);
        let ph = fw_phi(i, t) * p;
        let c = cos(ph);
        let s = sin(ph);
        let k = mix(1.0, kappa, p);
        let len = (rho - prev) * k;
        total += len * s;
        if (r > prev) {
            let seg = (min(r, rho) - prev) * k;
            R += seg * c;
            Y -= seg * s;
            here = ph;
        }
        prev = rho;
    }
    if (r > prev) {
        // (the far land: lying flat, slid in by what the rings have taken up; then, as the world closes, all of it scaled to
        // the mound's foot: squeezed round the foot by the slide alone it would go to streaks, and only a scale keeps its
        // shapes. Its heights go with it, world_warp)
        let foot = max(R, 1.0);
        R = mix(foot + r - prev, foot * r / prev, fw_ss(FW_LAY0 - 2.0, FW_LAY1 - 2.0, t));
        here = 0.0;
    }
    // (the top a point: the scallops' lengths make its height depend on the bearing)
    let plain = fw_top(t, kappa);
    return vec3<f32>(R, Y + mix(plain, total, fw_ss(0.0, fw_ring(0), r)), here);
}
// How high the chain's top stands, whatever the bearing.
fn fw_top(t: f32, kappa: f32) -> f32 {
    var prev = 0.0;
    var total = 0.0;
    for (var i = 0; i < 5; i += 1) {
        let rho = fw_ring(i);
        let p = fw_p(i, 0.2618, t);
        total += (rho - prev) * mix(1.0, kappa, p) * sin(fw_phi(i, t) * p);
        prev = rho;
    }
    return total;
}
// ---- the water: the land takes the droplet the way still water takes a drop -------------------------------------------
// Each pulse of the centre (the droplet going in, then the land's own rebounds) lets go one group of rings, worked out as
// deep water's ring waves (the Cauchy-Poisson problem; refs in the team's notes): at distance r, time s after the pulse, the
// wave here is the one whose group has come this far, k = g s^2 / (4 r^2), so the first rings out are long and fast, the
// ones behind them short and slow, the crests run forward through their group at twice its speed, and a calm grows in the
// middle as the short waves leave. r is softened by FW_CORE so the middle itself falls and rebounds, one formula all the way
// in. Physically a group thins out as r^-3; FW_RB and FW_RP put back enough of that to carry it to the player.
const FW_TOUCH: f32 = 6.0;         // the droplet touches: fold.wgsl's FD_TOUCH
const FW_G: f32 = 400.0;           // the land's gravity, blocks/s^2: higher, every ring faster; a wave's period is 2 pi / sqrt(g k)
const FW_SRC: f32 = 17.0;          // how wide a pulse is, blocks: the shortest ring it makes is about 2.2 of these
const FW_CORE: f32 = 20.0;         // the softened middle
const FW_RB: f32 = 60.0;
const FW_RP: f32 = 1.5;
fn fw_group(r2: f32, s: f32) -> f32 {
    if (s <= 0.0) {
        return 0.0;
    }
    let q2 = r2 + FW_CORE * FW_CORE;
    let q = sqrt(q2);
    let u = FW_G * s * s * 0.25;
    let x = u / q2 * FW_SRC * 0.5;
    if (x > 3.0) {
        return 0.0;
    }
    let b = 1.0 + q / FW_RB;
    return 0.706 * FW_SRC * FW_SRC * u / (q2 * q) * exp(-x * x) * b * sqrt(b) * cos(u / q);
}
// The land's height here at t, blocks: five groups, each stronger than the last and of the other sign.
fn fw_ripple(r: f32, t: f32) -> f32 {
    if (t < FW_TOUCH || t > FW_TEAR) {
        return 0.0;
    }
    let r2 = r * r;
    let y = -1.2 * fw_group(r2, t - 7.5) + 2.6 * fw_group(r2, t - 8.6) - 4.6 * fw_group(r2, t - 9.6)
        + 7.2 * fw_group(r2, t - 10.6) - 9.5 * fw_group(r2, t - 11.5);
    return y * (1.0 - fw_ss(FW_SCORE - 0.4, FW_TEAR, t));
}
// The land at the droplet's foot: drawn to it. A finger of land reaches up for the drop as it falls, meets it a tenth of a second
// before it would have reached the ground, climbs its side in a tight skirt with a hollow flank, not a hill's round one, and
// closes over its top as the last of it goes under at 7.5, then falls back. fold.wgsl's fd_land and fd_meld in step.
fn fw_land(a: f32, R: f32) -> f32 {
    return 1.35 * R * fw_ss(-0.5, 0.55, a) * (1.0 - 0.69 * fw_ss(0.95, 1.5, a) - 0.31 * fw_ss(1.5, 2.4, a));
}
fn fw_neck(r: f32, t: f32, R: f32) -> f32 {
    let a = t - FW_TOUCH;
    if (a <= -0.5 || a >= 2.4 || r > R * 9.0) {
        return 0.0;
    }
    let H = fw_land(a, R);
    // (how wide the drop is at the top of the land: fold.wgsl's fd_prof and fd_meld)
    let vc = 2.0 * (1.6 * R + 6.0) / 1.1;
    var h = R + 1.6 * R + 6.0;
    if (a > 0.0) {
        h = R - vc * 0.25 * (1.0 - exp(-a / 0.25)) - a * a * (2.22 * R + 1.0 - vc * 0.25) / 2.25;
    }
    let y = clamp((H - h) / R, -1.0, 1.72);
    let b = 1.72 - y;
    let q = 0.25773 + y * (0.09111 + y * (-0.07338 + y * (-0.05797 + y * 0.03297)));
    let rho = R * sqrt(max((y + 1.0) * b * b * sqrt(b) * q, 0.0));
    let d = max(r - rho, 0.0);
    let x = sqrt(d * d + 1.0) - 1.0;
    return H * (0.65 * exp(-x / (0.42 * R)) + 0.35 * exp(-x / (3.0 * R))) * (1.0 - fw_ss(6.0 * R, 9.0 * R, r));
}
// How far the land here is drawn in towards the drop, blocks: what stands higher goes further, so trees and walls lean to it.
fn fw_pull(r: f32, y: f32, t: f32, R: f32) -> f32 {
    let a = t - FW_TOUCH;
    if (a <= -0.3 || a >= 2.3 || r > R * 14.0) {
        return 0.0;
    }
    let P = 1.0 * R * fw_ss(-0.3, 0.6, a) * (1.0 - fw_ss(1.35, 2.3, a));
    let lean = 1.0 + clamp(y, 0.0, 26.0) / (1.2 * R);
    return min(P * lean * (1.0 - exp(-r / (1.2 * R))) * exp(-r / (2.6 * R)), 0.85 * r);
}
// ---- the sphere ------------------------------------------------------------------------------------------------------
// How big it ends: the player well inside, whatever their distance.
fn fw_radius(d: f32) -> f32 {
    return max(d * 1.3, 170.0);
}
// How bent the sheet is at `tau` (1 / the sphere's radius): nothing, the horizon coming up, shut.
fn fw_curve(tau: f32, d: f32) -> f32 {
    let g = fw_ss(20.5, FW_SEAL, tau);
    return pow(g, 1.3) / fw_radius(d);
}
// The sheet's last swings after FW_FLAT: its bend, plus curling up, minus down; each lobe less than the last, and the
// last heaved up to fall all at once on FW_SLAM4.
fn fw_lobe(t: f32, a: f32, b: f32, amp: f32) -> f32 {
    if (t <= a || t >= b) {
        return 0.0;
    }
    return amp * sin(FW_PI * (t - a) / (b - a));
}
fn fw_flap(t: f32) -> f32 {
    if (t <= FW_FLAT || t >= FW_SLAM4) {
        return 0.0;
    }
    var k = fw_lobe(t, FW_FLAT, 42.0, -0.0009) + fw_lobe(t, 42.0, 42.8, 0.0005) + fw_lobe(t, 42.8, 43.7, -0.0003);
    if (t > 43.7) {
        // (up slowly, down all at once)
        let u = (t - 43.7) / (FW_SLAM4 - 43.7);
        let up = fw_ss(0.0, 0.62, u);
        let down = clamp((u - 0.62) / 0.38, 0.0, 1.0);
        k = 0.00028 * up * (1.0 - down * down * down);
    }
    return k;
}
// How far round from the target a point `rho` along the sheet lies on the sphere of curvature k: the stereographic map,
// conformal, so the land is only scaled, never stretched. The land's edge is drawn in to the point as the sphere shuts.
fn fw_theta(rho: f32, k: f32, w: f32) -> f32 {
    let th = 2.0 * atan(rho * k * 0.5);
    return th + (FW_PI - th) * w;
}
// The fold down from the sphere's top: six stages, each slower than the last. In the first the top is pushed in on itself
// (mirrored in the plane of its edge, as a dent in a ball: nothing stretches). In each of the others a copy of the real land
// round the target, the same land each time, smaller and smaller, opens as a cone out of the point of the one before, and
// the last cone's point is on the target. A thin spike of the sheet runs down inside them, so the tip gets there even
// where the copies' land isn't loaded.
fn fw_start(k: i32) -> f32 {
    switch k {
        case 0: { return 35.0; }
        case 1: { return 35.6; }
        case 2: { return 36.3; }
        case 3: { return 37.1; }
        case 4: { return 38.0; }
        case 5: { return 39.0; }
        default: { return FW_BEAT; }
    }
}
const FW_TIER_L: f32 = 0.56;       // each cone this much shorter than the last
const FW_TIER_R: f32 = 0.54;       // and this much narrower
// How far on stage k is: quick out of the fold, slow into its place.
fn fw_stage(k: i32, tau: f32) -> f32 {
    let e = clamp((tau - fw_start(k)) / (fw_start(k + 1) - fw_start(k)), 0.0, 1.0);
    return 1.0 - pow(1.0 - e, 2.4);
}
// How far down from the sphere's top cone k's point is by `tau` (0 is the dent's bottom's depth, z1).
fn fw_point(k: i32, tau: f32, z1: f32, ax: f32) -> f32 {
    let unit = (ax - z1) * (1.0 - FW_TIER_L) / (1.0 - pow(FW_TIER_L, 5.0));
    var z = z1;
    var len = unit;
    for (var j = 1; j <= k; j += 1) {
        z += len * fw_stage(j, tau);
        len *= FW_TIER_L;
    }
    return z;
}
// The sheet's cap: (out from the axis, down from the top). `v` 1 at the cap's edge, 0 the very top.
fn fw_dent(v: f32, sphere: vec2<f32>, tau: f32, z0: f32, ax: f32) -> vec2<f32> {
    let g = fw_stage(0, tau);
    let z1 = 2.0 * z0;
    let p = vec2<f32>(sphere.x, mix(sphere.y, 2.0 * z0 - sphere.y, g));
    // (the middle of it drawn out to the spike, the tip where the last cone's point is)
    let vv = min(v / FW_SPIKE, 1.0);
    let spike = vec2<f32>(4.0 * vv, mix(fw_point(5, tau, z1, ax), z1 * 0.97, vv));
    return mix(p, spike, g * fw_ss(FW_SPIKE * 1.5, FW_SPIKE * 0.7, v));
}
// Where the sheet goes: (R, a, y) along it from the target, y over it, bent to curvature k with the point `d` along it,
// the player's feet, left where it is, level. The result is from the target, x and z as the world's.
struct FwBend { k: f32, shut: f32, tau: f32, d: f32, e: vec2<f32>, edge: f32, top: f32 }
fn fw_place(R: f32, r: f32, a: f32, y: f32, g: FwBend) -> vec3<f32> {
    let k = g.k;
    let ca = cos(a);
    let sa = sin(a);
    if (abs(k) < 1.0e-6) {
        return vec3<f32>(R * ca, y, R * sa);
    }
    let th = fw_theta(R, k, g.shut * fw_ss(0.42 * g.edge, g.edge, r));
    let f = pow(cos(th * 0.5), 2.0);
    var X = sin(th) * (1.0 / k - y * f);
    var Y = 2.0 * pow(sin(th * 0.5), 2.0) / k + y * f * cos(th);
    // ---- the top comes down ----------------------------------------------------------------------------------------------
    let psi = FW_PI - th;
    if (g.tau > FW_CRUSH && k > 0.0 && psi < FW_CAP) {
        let S = 1.0 / k;
        let ax = 2.0 * S - g.top;
        let z0 = S * (1.0 - cos(FW_CAP));
        let v = psi / FW_CAP;
        let p = fw_dent(v, vec2<f32>(X, 2.0 * S - Y), g.tau, z0, ax);
        // (the land's own heights lie down, on the walls of the tiers: only those at the very edge stay)
        let w = fw_ss(0.86, 1.0, v);
        X = mix(p.x, X, w);
        Y = mix(2.0 * S - p.y, Y, w);
    }
    return fw_turn(X * ca, Y, X * sa, g);
}
// Turned about the sphere's middle to bring the player's feet to the bottom.
fn fw_turn(x3: f32, Y: f32, z3: f32, g: FwBend) -> vec3<f32> {
    let k = g.k;
    let thd = fw_theta(g.d, k, 0.0);
    let c = cos(thd);
    let s = sin(thd);
    let up = s / k;
    let yp = 2.0 * pow(sin(thd * 0.5), 2.0) / k;
    let du = x3 * g.e.x + z3 * g.e.y - up;
    let dv = -x3 * g.e.y + z3 * g.e.x;
    let dy = Y - yp;
    let u2 = g.d + du * c + dy * s;
    return vec3<f32>(u2 * g.e.x - dv * g.e.y, -du * s + dy * c, u2 * g.e.y + dv * g.e.x);
}
// A bubble round the eye: what the warp has moved stays this far off, sliding round it.
fn fw_clear(moved: vec3<f32>, from_: vec3<f32>, keep: f32) -> vec3<f32> {
    let d = length(moved);
    let rad = 30.0 * keep * fw_ss(3.0, 24.0, length(moved - from_));
    if (d >= rad || d < 0.001) {
        return moved;
    }
    return moved * (rad / d);
}

struct FwClock { t: f32, tgt: vec3<f32>, me: vec3<f32>, seed: f32, cut: f32 }
fn fw_clock() -> FwClock {
    let w = globals.warp;
    let tgt = (w[0].xyz - w[4].xyz) - w[5].xyz;
    let me = (w[3].xyz - w[4].xyz) - w[5].xyz;
    return FwClock(w[0].w + w[4].w * 0.05, tgt, me, w[2].x, min(50.0 - w[0].y, -20.0));
}
fn fw_live(t: f32) -> bool {
    return globals.warp[2].y > 0.5 && t > FW_TOUCH - 0.5 && t < FW_END;
}

// Cone k (1 to 5): a copy of the land round the target, its middle at the point, its edge the rim.
fn fw_cone(k: i32, pos: vec3<f32>, Q: vec3<f32>, r: f32, a: f32, c: FwClock) -> Warped {
    var out = Warped(c.tgt + vec3<f32>(0.0, -4000.0, 0.0), vec3<f32>(-1.0));
    let tau = fw_tau(c.t);
    let g = fw_stage(k, tau);
    if (tau <= fw_start(k) || g < 0.002) {
        return out;
    }
    let mq = c.me - c.tgt;
    let dist = length(mq.xz);
    let e = select(vec2<f32>(1.0, 0.0), mq.xz / max(dist, 0.001), dist > 0.5);
    let S = fw_radius(dist);
    let rb = clamp(dist * 0.56, 60.0, 150.0);
    let kappa = rb / 153.0 * FW_PEARL;
    let top = fw_top(FW_BEAT, kappa) - FW_SINK;
    let ax = 2.0 * S - top;
    let z1 = 2.0 * S * (1.0 - cos(FW_CAP));
    let pz = fw_point(k, tau, z1, ax);
    let qz = fw_point(k - 1, tau, z1, ax);
    let scale = 0.42 * S * pow(FW_TIER_R, f32(k - 1));
    let w = r / FW_DISC;
    // (the rim a little over the last cone's point)
    let rim = qz - 0.3 * (pz - qz);
    let bell = pow(min(w, 1.3), 1.5);
    let height = clamp(Q.y, -6.0, 60.0) * scale / FW_DISC;
    let b = (scale * w + height * 0.8) * g;
    let z = mix(pz, rim, bell) - height * 0.6 * g;
    let turn = a + f32(k) * FW_PI / 12.0;
    let bend = FwBend(1.0 / S, 1.0, tau, dist, e, 1.0e6, top);
    out.pos = fw_turn(b * cos(turn), 2.0 * S - z, b * sin(turn), bend) + c.tgt;
    out.tint = vec3<f32>(1.0);
    return out;
}
fn world_warp(pos: vec3<f32>, copy: u32) -> Warped {
    var out = Warped(pos, vec3<f32>(1.0));
    let c = fw_clock();
    let t = c.t;
    // (the mod builds this ahead of the first strike, for a frame, with no parameters: nothing to do)
    if (!fw_live(t)) {
        if (copy > 0u) {
            out.pos = c.tgt + vec3<f32>(0.0, -4000.0, 0.0);
            out.tint = vec3<f32>(-1.0);
        }
        return out;
    }
    var Q = pos - c.tgt;
    var r = length(Q.xz);
    var a = atan2(Q.z, Q.x);
    if (copy > 0u) {
        return fw_cone(i32(copy), pos, Q, r, a, c);
    }
    // (the player rides it: what is under them is taken off everything, as though they rose and fell with the land)
    let dropR = clamp(length(c.me.xz - c.tgt.xz) * 0.05, 5.0, 15.0);
    let rip = fw_ripple(r, t) - fw_ripple(length(c.tgt.xz), t) + fw_neck(r, t, dropR);
    if (t < FW_TOUCH + 2.3) {
        let pull = fw_pull(r, Q.y, t, dropR) / max(r, 0.01);
        Q = vec3<f32>(Q.x * (1.0 - pull), Q.y, Q.z * (1.0 - pull));
    }
    // ---- the island: left where it is ------------------------------------------------------------------------------------
    let mq = c.me - c.tgt;
    if (length(Q.xz - mq.xz) < FW_ISLE) {
        out.pos = c.tgt + Q + vec3<f32>(0.0, rip, 0.0);
        return out;
    }
    // ---- how far on: the sheet's own heights keep to its surface as it goes up ---------------------------------------------
    let tau = fw_tau(t);
    // (the hole the island left, closed while the island still covers it: it would be a window on the void)
    let fill = fw_ss(FW_FOLD, FW_FOLD + 2.5, tau);
    let dm = length(Q.xz - mq.xz);
    if (fill > 0.0 && dm < FW_ISLE + 60.0) {
        let to = mix(dm, (dm - FW_ISLE) * (FW_ISLE + 60.0) / 60.0, fill);
        Q = vec3<f32>(mq.x + (Q.x - mq.x) * to / dm, Q.y, mq.z + (Q.z - mq.z) * to / dm);
        r = length(Q.xz);
        a = atan2(Q.z, Q.x);
    }
    let opening = fw_ss(FW_REL, FW_FLAT, t);
    let folded = fw_ss(FW_FOLD - 0.5, FW_FOLD + 6.0, tau);
    // (what is under the sheet doesn't swing out on a lever: pressed up to its cut, then the heights pressed in)
    let cuts = fw_ss(FW_FOLD - 0.5, FW_FOLD, tau) * (1.0 - fw_ss(FW_FLAT - 0.3, FW_FLAT, t));
    var h = Q.y + rip;
    h = max(h, mix(-4000.0, c.cut, cuts));
    let soft = select(26.0 * (1.0 - exp(h / 26.0)) * -1.0, 110.0 * (1.0 - exp(-h / 110.0)), h > 0.0);
    h = mix(h, soft, folded);
    let flap = fw_flap(t);
    if (tau < FW_FOLD - 0.01 && flap == 0.0) {
        out.pos = c.tgt + vec3<f32>(Q.x, h, Q.z);
        return out;
    }
    // ---- the chain: the plates, hinged at the rings, shrinking to a pearl as the far land slides in --------------------------
    let dist = length(mq.xz);
    let rb = clamp(dist * 0.56, 60.0, 150.0);
    let kappa = rb / 153.0 * mix(1.0, FW_PEARL, fw_ss(FW_LAY0, FW_LAY1, tau));
    let ch = fw_chain(r, a, tau, kappa);
    var R = ch.x;
    var Y = ch.y;
    let sn = sin(ch.z);
    let cs = cos(ch.z);
    // (the pleats: what the circle has lost, folded in radially like a fan)
    var hh = h;
    if (FW_PLEATS > 0.0 && r > 44.0) {
        let i = select(select(select(4, 3, r < fw_ring(3)), 2, r < fw_ring(2)), 1, r < fw_ring(1));
        let tri = fw_petal(a, i);
        let squeeze = clamp(R / max(r, 1.0), 0.0, 1.0);
        let w = min(r * FW_PI / 12.0, 34.0);
        hh += FW_PLEATS * (0.5 - tri) * 1.3 * w * sqrt(max(1.0 - squeeze * squeeze, 0.0)) * fw_ss(FW_LEN * 1.15, FW_LEN * 0.95, r);
    }
    // (the land's heights scale with the land)
    let small = clamp(abs(R) / max(r, 1.0), 0.0, 1.0);
    let lay = fw_ss(FW_LAY0, FW_LAY1, tau);
    hh *= mix(mix(1.0, kappa, lay), mix(1.0, small, lay), fw_ss(FW_LEN, FW_LEN * 1.2, r));
    R += hh * sn;
    Y += hh * cs;
    // (the sheet sunk from under the island, a dish it stands in: nothing comes up through it)
    let sink = FW_SINK * fw_ss(FW_FOLD, FW_FOLD + 2.5, tau);
    let e = select(vec2<f32>(1.0, 0.0), mq.xz / max(dist, 0.001), dist > 0.5);
    var y = Y - sink;
    let along = vec2<f32>(R * cos(a), R * sin(a)) - e * dist;
    let far_ = length(along);
    let dish = mq.y - 8.0 + max(far_ - FW_ISLE - 8.0, 0.0) * 0.5;
    if (y > dish && tau > FW_FOLD) {
        y = dish + (y - dish) * fw_ss(FW_ISLE, FW_ISLE + 90.0, far_);
    }
    // ---- the sheet on the sphere -----------------------------------------------------------------------------------------
    let reach = clamp(min(globals.fog.y, globals.fog.w), 480.0, 6000.0);
    let edge = max(reach - dist, 300.0);
    let k = fw_curve(tau, dist) + flap;
    let shut = fw_ss(28.5, FW_SEAL - 0.5, tau);
    let top = fw_top(tau, kappa) - sink;
    let P = fw_place(R, r, a, y, FwBend(k, shut, tau, dist, e, edge, top));
    out.pos = fw_clear(P + c.tgt, pos, 1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 1.0, t));
    return out;
}
// [fragments]
// ---- the mandala ----------------------------------------------------------------------------------------------------
// How far (r, a) is from the nearest crease, blocks: x a ring's scalloped edge or a petal's edge, y a petal's middle line.
fn fw_crease(r: f32, a: f32) -> vec2<f32> {
    var ring = 1000.0;
    var inside = 4;
    for (var i = 4; i >= 0; i -= 1) {
        let rho = fw_rho(i, a);
        ring = min(ring, abs(r - rho));
        if (r < rho) {
            inside = i;
        }
    }
    let past = max(r - fw_rho(4, a), 0.0);
    let tri = fw_petal(a, inside);
    let arc = FW_PI / 12.0 * r;
    let edge = (1.0 - tri) * arc;
    let mid = select(1000.0, tri * arc, inside > 0);
    return vec2<f32>(min(ring, edge + past * 4.0), mid + past * 4.0);
}
// How far the scoring has raced by t.
fn fw_score(t: f32) -> f32 {
    let u = max(t - FW_SCORE, 0.0);
    return 40.0 * u + 26.0 * u * u + 3.0 * u * u * u;
}
// ---- the void ---------------------------------------------------------------------------------------------------------
fn fw_stars(dir: vec3<f32>) -> vec3<f32> {
    let c = floor(dir * 300.0);
    let h = fw_hash(c.xy + c.z * 37.7);
    let s = select(0.0, (h - 0.99) / 0.01, h > 0.99);
    let glow = 0.5 + 0.5 * sin(dir.x * 4.0 + dir.y * 3.0 + dir.z * 5.0);
    return mix(vec3<f32>(0.006, 0.005, 0.016), vec3<f32>(0.03, 0.012, 0.05), glow * glow) + vec3<f32>(0.8, 0.82, 1.0) * s * s;
}
// ---- the iridescence: oil on water, hue turned about the grey axis, luminance kept -------------------------------------
fn fw_hue(col: vec3<f32>, ang: f32, sat: f32) -> vec3<f32> {
    let l = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let c = cos(ang);
    let s = sin(ang);
    let k = vec3<f32>(0.57735);
    let v = col - vec3<f32>(dot(col, k)) * k;
    let turned = v * c + cross(k, v) * s;
    let out_ = turned * sat + vec3<f32>(dot(col, k)) * k;
    // (its own luminance back, so nothing is lifted to pastel)
    let l2 = dot(out_, vec3<f32>(0.299, 0.587, 0.114));
    return clamp(out_ + vec3<f32>(l - l2), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn fw_iridesce(col: vec3<f32>, Q: vec3<f32>, r: f32, t: f32, w: f32) -> vec3<f32> {
    if (w < 0.004) {
        return col;
    }
    // (slow broad bands, bent by their own second bands, as on a film of oil; a tenth of a turn or so every few seconds)
    let q = Q.xz + vec2<f32>(sin(Q.z * 0.013 + t * 0.09), cos(Q.x * 0.011 - t * 0.07)) * 26.0;
    let bands = sin(q.x * 0.019 + q.y * 0.012 + Q.y * 0.03 + t * 0.22) + 0.6 * sin(r * 0.031 - t * 0.31);
    let ang = 0.63 * FW_IRID * w * bands / 1.6;
    return fw_hue(col, ang, 1.0 + 0.26 * FW_IRID * w);
}
// ---- the water's look: small waves are seen by their slope, what they reflect, long before their height shows ------------
const FW_SHEEN: f32 = 1.0;
fn fw_wet(colIn: vec3<f32>, Q: vec3<f32>, r: f32, t: f32, at: vec3<f32>, R: f32, up: f32) -> vec3<f32> {
    let a = t - FW_TOUCH;
    let e = 1.5;
    let r0 = max(r - e, 0.0);
    var slope = (fw_ripple(r + e, t) - fw_ripple(r0, t)) / (r + e - r0);
    // (the first fine ripples, too small for the land's vertices: only their light, running out ahead of the metal)
    let lead = R + 58.0 * (1.0 - exp(-a / 1.5));
    let fine = fw_ss(lead, lead - 12.0, r) * fw_ss(0.0, 0.4, a) * (1.0 - fw_ss(7.4, 9.6, t));
    slope += 0.11 * fine * up * sin(r * 0.8 - a * 9.0) * exp(-r / 80.0);
    let D = Q.xz / max(r, 0.5);
    let N = normalize(vec3<f32>(-slope * D.x, 1.0, -slope * D.y));
    let V = at / max(length(at), 0.01);
    let L = globals.sun.xyz;
    let day = fw_ss(-0.1, 0.2, L.y);
    // (the sun's light across the rings and the swell at its foot; the sky's only in the rings: the swell is too steep, it would wash the blocks out)
    let s2 = slope + (fw_neck(r + e, t, R) - fw_neck(r0, t, R)) / (r + e - r0);
    let Ns = normalize(vec3<f32>(-s2 * D.x, 1.0, -s2 * D.y));
    let nv = max(dot(N, -V), 0.0);
    let turned = nv - max(-V.y, 0.0);
    var col = colIn * (1.0 + FW_SHEEN * 0.9 * day * (dot(Ns, L) - L.y));
    // (a face turned from the eye shows the bright sky low down, one turned to it the deep sky overhead)
    col = mix(col, globals.sky_color.rgb * 1.15, clamp(-turned * 1.3, 0.0, 0.34) * FW_SHEEN * up);
    col = col * (1.0 - clamp(turned * 1.2, 0.0, 0.3) * FW_SHEEN);
    // ---- the droplet's metal spreading from the contact, thin as a film, then taken into the land ----------------------------
    let ang = atan2(Q.z, Q.x);
    let rf = 1.3 * R + 30.0 * (1.0 - exp(-a / 1.1)) + 2.5 * sin(ang * 5.0 + 1.0) + 1.5 * sin(ang * 11.0 - 2.0);
    // (thick at the foot, thin on past it, gone by the first rebound)
    let foot = exp(-max(r - R * 0.9, 0.0) / (R * 0.9));
    let film = fw_ss(rf, rf - 6.0, r) * fw_ss(0.0, 0.2, a) * (1.0 - fw_ss(7.0, 9.0, t)) * (0.06 + 0.32 * foot) * up;
    if (film > 0.002) {
        let m = reflect(V, N);
        let env = mix(vec3<f32>(0.42, 0.44, 0.48), globals.sky_color.rgb * 1.1, fw_ss(-0.02, 0.5, m.y));
        let glint = pow(max(dot(m, L), 0.0), 120.0) * 3.0 * day;
        col = mix(col, env * (1.0 + 0.3 * pow(1.0 - nv, 3.0)) + vec3<f32>(glint), film);
    }
    return col;
}
// ---- the sponge: is a point of a unit block a hole? (a Menger sponge, three levels) --------------------------------------
fn fw_hole(p: vec3<f32>) -> bool {
    var q = fract(p);
    for (var i = 0; i < 3; i += 1) {
        q = q * 3.0;
        let c = floor(q);
        let m = vec3<f32>(step(1.0, c.x) * step(c.x, 1.5), step(1.0, c.y) * step(c.y, 1.5), step(1.0, c.z) * step(c.z, 1.5));
        if (m.x + m.y + m.z >= 2.0) {
            return true;
        }
        q = fract(q);
    }
    return false;
}

fn world_fragment(f: Fragment) -> Painted {
    let c = fw_clock();
    let t = c.t;
    let drop_ = Painted(vec4<f32>(0.0, 0.0, 0.0, -1.0), 1.0);
    if (f.cut > 0.0) {
        return drop_;
    }
    let plain = sprite(f.uv, f.layer) * f.color;
    if (!fw_live(t)) {
        // (no strike clock yet, the warp built ahead of the first strike; or past it)
        return Painted(plain, 1.0);
    }
    let Q = f.home - c.tgt;
    let dist = length(f.at);
    let tau = fw_tau(t);
    let r = length(Q.xz);
    let a = atan2(Q.z, Q.x);
    // ---- the cones: a scalloped disc of the land, its top only ---------------------------------------------------------
    if (f.copy > 0u) {
        let edge = FW_DISC * (0.86 + 0.14 * (1.0 - fw_petal(a + f32(f.copy) * FW_PI / 12.0, 0)));
        if (r > edge || Q.y < -8.0 || f.light.x < 6.0 || plain.a < 0.5) {
            return drop_;
        }
        let px = max(0.05, max(length(dpdx(f.home)), length(dpdy(f.home))));
        let rimline = 1.0 - fw_ss(0.5, 1.0 + px * 1.6, edge - r);
        // (dark in the throat, where the next cone comes out of it: the steps read)
        let shade = mix(0.42, 1.0, fw_ss(0.0, 0.62, r / edge));
        return Painted(vec4<f32>(mix(plain.rgb * shade, vec3<f32>(1.0, 0.72, 0.42), rimline), 1.0), 1.0 - rimline);
    }
    // ---- the sheet: nothing under the land is drawn ------------------------------------------------------------------------
    let opened = t > FW_SEAL - 0.5 && r < FW_LAND_R;
    if (t > FW_FOLD - 0.5 && t < FW_SLAM4) {
        // (the caves' walls, sealed rooms, and what the far tiles stand on)
        if (f.light.x < 5.0 || (Q.y < c.cut && !opened)) {
            return drop_;
        }
    }
    // ---- the island's edge: a clean cut, the faces across it would be stretched to the land's new place ------------------
    let dm = length(Q.xz - (c.me.xz - c.tgt.xz));
    let isle = abs(dm - FW_ISLE);
    let gone = fw_ss(FW_FOLD - 0.4, FW_FOLD + 0.2, tau) * (1.0 - fw_ss(FW_FLAT - 0.1, FW_FLAT + 0.2, t));
    if (gone > 0.5 && isle < 1.7) {
        return drop_;
    }
    // ---- the crease pattern, its parts in time ---------------------------------------------------------------------------
    let dc = fw_crease(r, a);
    let front = fw_score(t);
    let scored = fw_ss(0.0, 26.0, front - r);
    let fade = 1.0 - fw_ss(FW_FADE, FW_END - 1.5, t);
    // (the block's own texture, tiled smaller and smaller as the land goes)
    var tex = plain;
    let dnear = min(dc.x, dc.y);
    var ring = 4;
    if (r < fw_rho(0, a)) { ring = 0; } else if (r < fw_rho(1, a)) { ring = 1; } else if (r < fw_rho(2, a)) { ring = 2; } else if (r < fw_rho(3, a)) { ring = 3; }
    let lifting = fw_p(ring, a, tau);
    let zone = scored * fade * (1.0 - fw_ss(5.0, 24.0, dnear - 6.0 * fw_ss(0.0, 1.0, lifting)));
    if (FW_FRACTAL > 0.0 && zone > 0.01 && dist < 460.0 && r < FW_LEN) {
        let z = 3.0 * zone * (0.4 + 0.6 * fw_ss(FW_TEAR, FW_FOLD + 8.0, t));
        let k = floor(z);
        let u0 = f.uv * pow(2.0, k);
        let u1 = u0 * 2.0;
        let a0 = sprite(u0, f.layer) * f.color;
        let a1 = sprite(u1, f.layer) * f.color;
        let m = z - k;
        tex = mix(a0, a1, m * m * (3.0 - 2.0 * m));
        tex = vec4<f32>(tex.rgb, max(plain.a, 0.0));
        // (a fine dark line round each small copy, so they read as blocks in the block)
        let g = abs(fract(u0) - 0.5);
        let cell = 1.0 - fw_ss(0.46, 0.5, max(g.x, g.y)) * 0.28 * min(k, 1.0);
        tex = vec4<f32>(tex.rgb * cell, tex.a);
    }
    if (tex.a < 0.5 && f.layer < 32768u && plain.a < 0.5) {
        return Painted(tex, 1.0);
    }
    var col = tex.rgb;
    // (water is drawn over what lies under it: over the void it would go dark, so it is made solid as the land leaves)
    var alpha = tex.a;
    if (alpha < 0.98) {
        alpha = mix(alpha, 0.97, fw_ss(FW_TEAR, FW_FOLD, t) * (1.0 - fw_ss(FW_SLAM4 - 0.2, FW_SLAM4 + 0.6, t)));
    }
    var fog = 1.0;
    // ---- the underside: rock, not the land's top seen from under it --------------------------------------------------------
    let shown = gone * (1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 0.3, t));
    // (the back of the land's top faces only, by the face's real normal: plants and leaves have backs too)
    let real_n = cross(dpdx(f.home), dpdy(f.home));
    if (FW_UNDER > 0.0 && !f.front && shown > 0.0 && plain.a > 0.99 && abs(real_n.y) > 0.9 * length(real_n)) {
        let n = fw_hash(floor(Q.xz * 0.5) + floor(Q.y * 0.5));
        let rock = mix(vec3<f32>(0.1, 0.085, 0.08), vec3<f32>(0.24, 0.19, 0.16), n) * (0.6 + 0.4 * fw_ss(40.0, 0.0, Q.y + 30.0));
        col = mix(col, rock, 0.92 * shown);
    }
    // ---- the water's look ------------------------------------------------------------------------------------------------
    if (t > FW_TOUCH && t < FW_TEAR) {
        // (top faces: the water's skin; a wall or a trunk takes none of the metal)
        let up = fw_ss(0.5, 0.9, abs(real_n.y) / max(length(real_n), 1.0e-5));
        col = fw_wet(col, Q, r, t, f.at, clamp(length(c.me.xz - c.tgt.xz) * 0.05, 5.0, 15.0), up);
    }
    // ---- the iridescence: anchored to the land, spread with the wave, strongest on the creases and the petals -------------
    if (FW_IRID > 0.0) {
        let wave = fw_ss(0.0, 120.0, 60.0 * max(t - FW_RIPPLE, 0.0) + front - r);
        let farther = 0.35 + 0.65 * exp(-r / 520.0);
        let on = 0.7 + 0.3 * (1.0 - fw_ss(4.0, 40.0, dnear)) * scored + 0.3 * lifting;
        col = fw_iridesce(col, Q, r, t, clamp(on, 0.0, 1.0) * wave * farther * fade);
    }
    // ---- the sponge: as a petal goes, blocks by the creases eaten away to the void ---------------------------------------
    if (FW_SPONGE > 0.0 && dist < 260.0 && lifting > 0.02) {
        let sp = fw_ss(0.02, 0.45, lifting) * (1.0 - fw_ss(0.88, 1.0, lifting)) * (1.0 - fw_ss(6.0, 26.0, dnear));
        // (block by block, by the blocks' own grid; past a little way off a sponge three blocks wide, or it couldn't be seen)
        let w = globals.warp;
        let size = select(1.0, 3.0, dist > 70.0);
        let ph = (f.home + fract(w[4].xyz) + w[5].xyz) / size;
        if (fw_hash(floor(ph.xz) + floor(ph.y) * 7.0) < sp * 1.4) {
            let v = normalize(f.at);
            var depth = -1.0;
            for (var i = 0; i < 12; i += 1) {
                let s = f32(i) * 0.1;
                if (!fw_hole(ph + v * s)) {
                    depth = s;
                    break;
                }
            }
            if (depth < 0.0) {
                return Painted(vec4<f32>(fw_stars(v), 1.0), 0.0);
            }
            col = col * (1.0 - min(depth * 1.1, 0.85));
        }
    }
    // ---- the creases ---------------------------------------------------------------------------------------------------
    if (scored > 0.001 && r < FW_LEN * 1.2) {
        // (a pixel in the land's own blocks, however small the warp has made it)
        let px = max(0.05, max(length(dpdx(f.home)), length(dpdy(f.home))));
        let d = min(dc.x, dc.y + 1.2);
        let hair = 1.0 - fw_ss(0.05 + px, 0.1 + px * 2.2, d);
        // (the tear: wider the more it has opened, broken up block by block)
        let jag = 0.45 + 1.1 * fw_hash(floor(Q.xz / 3.0));
        // (and sealed by the time the world has closed: no void from inside)
        let opens = fw_ss(FW_TEAR, FW_FOLD + 1.0, t) * (1.0 - fw_ss(FW_FADE + 1.0, FW_END - 2.0, t)) * (1.0 - fw_ss(29.0, 33.0, tau));
        let tw = opens * jag * (1.6 + 0.009 * r + 2.2 * (1.0 - fw_ss(0.0, 3.0, dc.x)));
        let void_ = dc.x < tw;
        if (void_) {
            return Painted(vec4<f32>(fw_stars(normalize(f.at)), 1.0), 0.0);
        }
        // (the seam's hot edge, then only a scorch as it seals)
        let tone = 0.5 + 0.5 * sin(r * 0.012 - t * 0.2);
        let line = mix(vec3<f32>(1.0, 0.93, 0.82), vec3<f32>(0.86, 0.8, 1.0), tone) * 1.5;
        let hairline = scored * fade * hair * (1.0 - 0.8 * opens) * (1.0 - 0.85 * fw_ss(29.0, 33.0, tau));
        // (an ember's edge on the tear: thin and low, scorch behind it)
        let e = max(dc.x - tw, 0.0);
        let ember = opens * fade * (1.0 - fw_ss(0.0, 0.5 + px * 1.5, e));
        let scorch = opens * (1.0 - fw_ss(0.3, 2.6, e));
        col = col * (1.0 - 0.75 * scorch);
        col = mix(col, vec3<f32>(1.0, 0.4, 0.12), clamp(ember, 0.0, 1.0));
        col = mix(col, line, clamp(hairline, 0.0, 1.0));
        fog = 1.0 - clamp(hairline + ember, 0.0, 1.0);
    }
    // ---- the island's rim, a line of light where it was cut -----------------------------------------------------------
    {
        let px = max(0.05, dist * 0.00095);
        let line = (1.0 - fw_ss(1.7, 2.2 + px * 2.0, isle)) * fw_ss(FW_SCORE, FW_TEAR, t) * fade;
        col = mix(col, vec3<f32>(1.0, 0.95, 0.9) * 1.4, line);
    }
    return Painted(vec4<f32>(col, alpha), fog);
}
