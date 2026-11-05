// The Fold's world warp (the fork's render.set-warp): reality folded like paper, the mandala its crease pattern. Every
// terrain and entity vertex comes through `world_warp`, and every pixel of the terrain through `world_fragment` (after the
// `[fragments]` line) with where it really is, so all of it is anchored to the world and none to the screen. The land is a
// thin sheet: what is under it never moves far and is never drawn (see FRAGMENTS, "the sheet").
//   FW_RIPPLE  rings running out of the target, each bigger than the last
//   FW_SCORE   they sharpen into hairline creases racing over the land: the mandala (fw_crease)
//   FW_TEAR    the creases split on the void, painted on the land itself so nothing under it shows
//   FW_FOLD    the land is pinched up at the target and closes ring by ring (fw_chain), its top outwards, a hinge at each
//              ring; radial pleats take up the circumference; the horizon rolls up and over (fw_roll)
//   FW_WRAP0   the roll's ring comes in to the target and its tube down to the sphere's size, as the bud lies down onto its
//              floor and the land comes back to its own size: FW_SEAL shut, the player inside, the real land on the walls
//   FW_CRUSH   the sphere's top folds down to the target in six stages (fw_stage), each smaller and slower
//   FW_BEAT    the tip touches the target. Stillness
//   FW_REL     it all runs backwards (fw_tau), slowly at first: the sphere opens and the bud stands again, every ring up; then
//              ring by ring, outermost first, each falls and bangs down (fw_hit), the last, FW_SLAM4, letting the crater show
// The player stands on an island punched out of the sheet (FW_ISLE), left where it is, the sheet sliding by under it, and
// from the time the world closes they can't leave it: however far they really go the sphere goes with them (fw_stay).
// strike/fold.rs and fold.wgsl share the beats: keep them in step (`the_warp_keeps_the_beats`).
const FW_RIPPLE: f32 = 6.6;
const FW_SCORE: f32 = 12.0;
const FW_TEAR: f32 = 16.0;
const FW_FOLD: f32 = 19.0;
const FW_SEAL: f32 = 35.0;
const FW_CRUSH: f32 = 35.0;
const FW_BEAT: f32 = 40.0;
const FW_REL: f32 = 40.5;
const FW_FLAT: f32 = 44.1;         // strike/fold.rs's FD_SLAM[0]: the first ring lands, all else still up
const FW_SLAM4: f32 = 48.7;        // the last of the slams (strike/fold.rs's FD_SLAM)
const FW_END: f32 = 56.7;
const FW_FADE: f32 = 49.1;         // the comedown begins
const FW_TAU: f32 = 6.2831853;
const FW_PI: f32 = 3.14159265;
const FW_LEN: f32 = 480.0;         // the sheet's length, the last ring (strike/fold.rs's FD_RINGS[4])
const FW_SINK: f32 = 16.0;         // how far the sheet sinks from the island
const FW_ISLE: f32 = 26.0;         // the player's island's radius
const FW_LAND_R: f32 = 300.0;      // from FD_LAND on the crater is in the land within this: nothing is cut under it

// ---- what can be taken out: 0 turns each off -----------------------------------------------------------------------
const FW_IRID: f32 = 1.0;          // the iridescence's strength: 1 is about 36 degrees of hue and a quarter more saturation at its peak
const FW_FRACTAL: f32 = 1.0;       // block faces showing smaller copies of themselves
const FW_SPONGE: f32 = 1.0;        // blocks carved into sponges
const FW_PLEATS: f32 = 1.0;        // the radial pleats
const FW_UNDER: f32 = 1.0;         // the sheet's underside painted as rock
const FW_LAY0: f32 = 28.4;         // the bud lies down onto the sphere's floor between these
const FW_LAY1: f32 = 34.5;
const FW_WRAP0: f32 = 27.0;        // the roll's ring comes in to the target, its tube to the sphere's size, from here to FW_SEAL
const FW_SINK_END: f32 = 0.3;      // how much of FW_SINK is left once the sheet lies on the sphere
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
// How far along the sheet's curve ring i ends up lying: the bearing of its plate, radians from the top pole. The last two
// go past upright, so what has closed is a bud whose foot tucks in under it.
fn fw_phi(i: i32) -> f32 {
    switch i {
        case 0: { return 0.14; }
        case 1: { return 0.48; }
        case 2: { return 0.92; }
        case 3: { return 1.52; }
        default: { return 2.52; }
    }
}
// As the world closes the bud lies down, its outer plate first, so what is left of it never spreads over the player...
fn fw_lie(i: i32, tau: f32) -> f32 {
    let t0 = FW_LAY0 + 0.9 * f32(4 - i);
    return 1.0 - fw_ss(t0, t0 + 2.6, tau);
}
// ...and the sheet comes back to its own size, so that the land on the sphere's walls is the real land round the player,
// all of it, its trees and its hills, not a map of what is past the horizon. 0 as it closed, 1 its own size.
fn fw_lay(tau: f32) -> f32 {
    return fw_ss(FW_LAY0 + 1.8, FW_LAY1 - 0.8, tau);
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
// When ring i lands, outermost first (strike/fold.rs's FD_SLAM).
fn fw_hit(i: i32) -> f32 {
    switch i {
        case 4: { return 44.1; }
        case 3: { return 45.2; }
        case 2: { return 46.3; }
        case 1: { return 47.4; }
        default: { return FW_SLAM4; }
    }
}
const FW_FALL: f32 = 0.8;          // how long each ring takes to fall: slowly away, and all its weight in the last of it
// How closed ring i is (0 flat, 1 shut) at bearing a, on the fold's clock `tau`: a petal's middle leads its edges. From
// FW_REL, `t` the strike's clock, it stays shut till it is its turn to fall, and falling, faster and faster, it stops dead.
fn fw_p(i: i32, a: f32, tau: f32, t: f32) -> f32 {
    if (t >= FW_REL) {
        let u = clamp((t - fw_hit(i) + FW_FALL) / FW_FALL, 0.0, 1.0);
        return 1.0 - u * u * u;
    }
    let t0 = FW_FOLD + 2.1 * f32(i) + 0.7 * fw_petal(a, i);
    return fw_ss(0.0, 3.6, tau - t0);
}
// The shock of ring i's landing: a single heave running out over the land past it, gone in a second.
fn fw_shock(r: f32, t: f32) -> f32 {
    var y = 0.0;
    for (var i = 1; i < 5; i += 1) {
        let age = t - fw_hit(i);
        if (age > 0.0 && age < 1.0) {
            let x = (r - fw_ring(i) - 330.0 * age) / (12.0 + 34.0 * age);
            y += 5.0 * exp(-x * x - 2.6 * age) * fw_ss(0.0, 0.05, age) * fw_ss(fw_ring(i) - 30.0, fw_ring(i), r);
        }
    }
    return y;
}
// The fold's clock: the strike's up to FW_REL, then back to FW_BACK by FW_FLAT, gathering slowly, and there it stays.
const FW_BACK: f32 = 20.0;
fn fw_tau(t: f32) -> f32 {
    if (t < FW_BEAT) {
        return t;
    }
    if (t < FW_REL) {
        return FW_BEAT;
    }
    let u = clamp((t - FW_REL) / (FW_FLAT - FW_REL), 0.0, 1.0);
    // (gathering, then steady as the sphere opens, then the far land falling away)
    return FW_BEAT - (FW_BEAT - FW_BACK) * u * u * (3.11 + u * (-5.05 + u * 2.94));
}
// ---- the chain ----------------------------------------------------------------------------------------------------------
// The sheet's cross-section at bearing a: from the top pole (the target), plate after rigid plate, each a ring, hinged at
// its edge, the last lying on the ground. A point r along it: (R out from the axis, Y up, the plate's angle).
// A plate shrinks to `kappa` as it closes, so what has closed is a dome no wider than the globe, inside the player's distance
// whatever it is, and what hasn't lies flat and slides in to the dome's foot.
fn fw_chain(r: f32, a: f32, t: f32, kappa: f32, rt: f32) -> vec3<f32> {
    var prev = 0.0;
    var R = 0.0;
    var Y = 0.0;
    var total = 0.0;
    var here = 0.0;
    for (var i = 0; i < 5; i += 1) {
        let rho = fw_rho(i, a);
        let p = fw_p(i, a, t, rt);
        let ph = fw_phi(i) * p * fw_lie(i, t);
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
        // (the far land: lying flat, slid in by what the rings have taken up)
        R += r - prev;
        here = 0.0;
    }
    // (the top a point: the scallops' lengths make its height depend on the bearing)
    let plain = fw_top(t, kappa, rt);
    return vec3<f32>(R, Y + mix(plain, total, fw_ss(0.0, fw_ring(0), r)), here);
}
// How high the chain's top stands, whatever the bearing.
fn fw_top(t: f32, kappa: f32, rt: f32) -> f32 {
    var prev = 0.0;
    var total = 0.0;
    for (var i = 0; i < 5; i += 1) {
        let rho = fw_ring(i);
        let p = fw_p(i, 0.2618, t, rt);
        total += (rho - prev) * mix(1.0, kappa, p) * sin(fw_phi(i) * p * fw_lie(i, t));
        prev = rho;
    }
    return total;
}
// Where the chain's foot has come to: how far out the far land starts, at the plates' mean bearing.
fn fw_foot(t: f32, kappa: f32, rt: f32) -> f32 {
    var prev = 0.0;
    var total = 0.0;
    for (var i = 0; i < 5; i += 1) {
        let rho = fw_ring(i);
        let p = fw_p(i, 0.2618, t, rt);
        total += (rho - prev) * mix(1.0, kappa, p) * cos(fw_phi(i) * p * fw_lie(i, t));
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
// How big it ends: the player well inside, whatever their distance and however high they stood over the target.
fn fw_radius(d: f32, y: f32) -> f32 {
    return max(max(d * 1.3, 170.0), y * 1.15);
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
const FW_TIER_L: f32 = 0.72;       // each cone this much shorter than the last
const FW_TIER_R: f32 = 0.62;       // and this much narrower
// How far on stage k is: quick out of the fold, slow into its place.
fn fw_stage(k: i32, tau: f32) -> f32 {
    let e = clamp((tau - fw_start(k)) / (fw_start(k + 1) - fw_start(k)), 0.0, 1.0);
    return 1.0 - pow(1.0 - e, 1.7);
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
// ---- the roll -----------------------------------------------------------------------------------------------------------
// Past `r0` the sheet rolls up and in over a tube of radius `rc`, up to `fm` round it. As the world closes r0 comes in to
// the target and the tube's radius to the sphere's: a tube whose ring has come down to nothing is a sphere, so it is one
// sheet and one motion from the horizon's first curl to the sphere shut over the player. `w` eases it from the roll's own
// spacing to the stereographic map's, conformal, so that on the sphere the land is only scaled, never stretched.
// The player's feet, and the land under them, are left where they are, level: the whole of it is turned about them.
struct FwBend { tau: f32, d: f32, e: vec2<f32>, edge: f32, top: f32, r0: f32, rc: f32, fm: f32, w: f32, shut: f32, S: f32, drop: f32 }
fn fw_curl(tau: f32) -> f32 {
    return fw_ss(FW_FOLD + 1.0, 29.0, tau);
}
fn fw_bend(tau: f32, rt: f32, mq: vec3<f32>, e: vec2<f32>, edge: f32, kappa: f32, top: f32) -> FwBend {
    let d = length(mq.xz);
    let curl = fw_curl(tau);
    let w = fw_ss(FW_WRAP0, FW_SEAL, tau);
    let S = fw_radius(d, mq.y);
    let r0 = (max(fw_foot(tau, kappa, rt), d) + 170.0) * (1.0 - fw_ss(FW_WRAP0, FW_SEAL - 0.5, tau));
    // (a player under the target's height has the sphere's floor let down under them)
    let drop = min(mq.y - 4.0, 0.0) * w;
    return FwBend(tau, d, e, edge, top, r0, mix(mix(3000.0, 700.0, curl), S, w), mix(curl * 3.2, FW_PI, w), w, fw_ss(FW_SEAL - 2.0, FW_SEAL - 0.5, tau), S, drop);
}
// A point R along the sheet, y over it, on the roll: (out from the axis, up, how far round).
fn fw_roll(R: f32, y: f32, grow: f32, g: FwBend) -> vec3<f32> {
    let u = R - g.r0;
    if (u <= 0.0 || g.fm < 0.001) {
        return vec3<f32>(R, y, 0.0);
    }
    let e = u / (g.rc * g.fm);
    let x = e * 1.5707963;
    let ex = exp(-e);
    var f = g.fm * mix(1.0 - ex, 0.63662 * atan(x), g.w);
    f += (g.fm - f) * grow;
    let yy = y * mix(ex, 1.0 / (1.0 + x * x), g.w);
    let s = sin(f);
    let c = cos(f);
    return vec3<f32>(g.r0 + (g.rc - yy) * s, g.rc * (1.0 - c) + yy * c, f);
}
// Where the sheet goes: (R, a, y) along it from the target, y over it. The result is from the target, x and z as the world's.
fn fw_place(R: f32, r: f32, a: f32, y: f32, g: FwBend) -> vec3<f32> {
    let ca = cos(a);
    let sa = sin(a);
    let on = fw_roll(R, y, g.shut * fw_ss(0.85 * g.edge, g.edge, r), g);
    var X = on.x;
    var Y = on.y;
    // ---- the top comes down ----------------------------------------------------------------------------------------------
    let psi = FW_PI - on.z;
    if (g.tau > FW_CRUSH && psi < FW_CAP) {
        let S = g.S;
        let ax = 2.0 * S - g.top;
        let z0 = S * (1.0 - cos(FW_CAP));
        let v = psi / FW_CAP;
        let p = fw_dent(v, vec2<f32>(X, 2.0 * S - Y), g.tau, z0, ax);
        // (the land's own heights lie down, on the walls of the tiers: only those at the very edge stay)
        let w = fw_ss(0.86, 1.0, v);
        X = mix(p.x, X, w);
        Y = mix(2.0 * S - p.y, Y, w);
    }
    return fw_turn(X * ca, Y, X * sa, fw_roll(g.d, 0.0, 0.0, g), g);
}
// Turned about the feet, `at` on the roll, to bring them to the bottom.
fn fw_turn(x3: f32, Y: f32, z3: f32, at: vec3<f32>, g: FwBend) -> vec3<f32> {
    let c = cos(at.z);
    let s = sin(at.z);
    let du = x3 * g.e.x + z3 * g.e.y - at.x;
    let dv = -x3 * g.e.y + z3 * g.e.x;
    let dy = Y - at.y;
    let u2 = g.d + du * c + dy * s;
    return vec3<f32>(u2 * g.e.x - dv * g.e.y, -du * s + dy * c + g.drop, u2 * g.e.y + dv * g.e.x);
}
// When the mandala's middle goes back into the sheet.
fn fw_join(tau: f32) -> f32 {
    return fw_ss(31.0, 33.5, tau);
}
// A bubble round the eye: what the warp has moved stays this far off, sliding round it.
// (`keep` how far, blocks)
fn fw_clear(moved: vec3<f32>, from_: vec3<f32>, keep: f32) -> vec3<f32> {
    let d = length(moved);
    let rad = keep * fw_ss(3.0, 24.0, length(moved - from_));
    if (d >= rad || d < 0.001) {
        return moved;
    }
    return moved * (rad / d);
}

// ---- the sphere goes with them --------------------------------------------------------------------------------------------
// The player can't get away: how far they have come since they fired (me) is taken off what is drawn, all but what fw_reach
// leaves them, which never gets to the wall however far they go: they can wander about in it, and it is too big to leave.
// lib.rs keeps them near enough for the land to stay loaded, and slows their flight while it is shut (FD_STAY).
fn fw_held(tau: f32) -> f32 {
    return fw_ss(FW_WRAP0, 30.0, tau);
}
fn fw_reach(from_: vec3<f32>, S: f32, down: f32) -> vec3<f32> {
    let L = 0.55 * S;
    // (down it can go only as far as the floor)
    let v = vec3<f32>(from_.x, from_.y * select(1.0, L / down, from_.y < 0.0), from_.z);
    let n = length(v);
    if (n < 0.001) {
        return from_;
    }
    let q = v * (L * tanh(n / L) / n);
    return vec3<f32>(q.x, q.y * select(1.0, down / L, from_.y < 0.0), q.z);
}
fn fw_stay(c: FwClock, tau: f32) -> vec3<f32> {
    let g = fw_held(tau);
    if (g <= 0.0) {
        return vec3<f32>(0.0);
    }
    let mq = c.me - c.tgt;
    let from_ = -c.me;
    let down = max(mq.y - min(mq.y - 4.0, 0.0) - 2.0, 6.0);
    return (from_ - fw_reach(from_, fw_radius(length(mq.xz), mq.y), down)) * g;
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
    let S = fw_radius(dist, mq.y);
    let top = -FW_SINK * FW_SINK_END;
    let ax = 2.0 * S - top;
    let z1 = 2.0 * S * (1.0 - cos(FW_CAP));
    let pz = fw_point(k, tau, z1, ax);
    let qz = fw_point(k - 1, tau, z1, ax);
    let scale = S * sin(FW_CAP) * pow(FW_TIER_R, f32(k - 1));
    let w = r / FW_DISC;
    // (the first as wide as the top that folded in, its rim that top's edge, so it covers all of it; the rest with their rims
    // a little over the last one's point)
    var rim = qz - 0.3 * (pz - qz);
    if (k == 1) {
        rim = mix(qz, 0.5 * z1, g);
    }
    let bell = pow(min(w, 1.3), 1.5);
    let height = clamp(Q.y, -6.0, 60.0) * scale / FW_DISC;
    let b = (scale * w + height * 0.8) * g;
    let z = mix(pz, rim, bell) - height * 0.6 * g;
    let turn = a + f32(k) * FW_PI / 12.0;
    let bend = fw_bend(FW_BEAT, c.t, mq, e, 1.0e6, 1.0, top);
    out.pos = fw_turn(b * cos(turn), 2.0 * S - z, b * sin(turn), fw_roll(dist, 0.0, 0.0, bend), bend) + c.tgt + fw_stay(c, tau);
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
    let tau = fw_tau(t);
    let stay = fw_stay(c, tau);
    if (length(Q.xz - mq.xz) < FW_ISLE) {
        out.pos = c.tgt + Q + vec3<f32>(0.0, rip, 0.0) + stay;
        return out;
    }
    // ---- how far on: the sheet's own heights keep to its surface as it goes up ---------------------------------------------
    // (down from the sphere, and the sheet comes back up under the island as its own ring lands)
    let dist = length(mq.xz);
    var own = 4;
    for (var i = 3; i >= 0; i -= 1) {
        if (dist < fw_ring(i)) {
            own = i;
        }
    }
    let seat = select(fw_ss(FW_FOLD, FW_FOLD + 2.5, tau), 1.0 - fw_ss(fw_hit(own) - FW_FALL, fw_hit(own), t), t >= FW_REL);
    // (the hole the island left, closed while the island still covers it: it would be a window on the void)
    let fill = seat;
    let dm = length(Q.xz - mq.xz);
    if (fill > 0.0 && dm < FW_ISLE + 60.0) {
        let to = mix(dm, (dm - FW_ISLE) * (FW_ISLE + 60.0) / 60.0, fill);
        Q = vec3<f32>(mq.x + (Q.x - mq.x) * to / dm, Q.y, mq.z + (Q.z - mq.z) * to / dm);
        r = length(Q.xz);
        a = atan2(Q.z, Q.x);
    }
    let folded = fw_ss(FW_FOLD - 0.5, FW_FOLD + 6.0, tau) * (1.0 - fw_ss(FW_REL + 1.5, FW_SLAM4 - 0.8, t));
    // (what is under the sheet doesn't swing out on a lever: pressed up to its cut, then the heights pressed in)
    let cuts = fw_ss(FW_FOLD - 0.5, FW_FOLD, tau) * (1.0 - fw_ss(FW_SLAM4 - 0.3, FW_SLAM4, t));
    var h = Q.y + rip;
    if (t > FW_FLAT && t < FW_SLAM4) {
        h += fw_shock(r, t);
    }
    h = max(h, mix(-4000.0, c.cut, cuts));
    let soft = select(26.0 * (1.0 - exp(h / 26.0)) * -1.0, 110.0 * (1.0 - exp(-h / 110.0)), h > 0.0);
    h = mix(h, soft, folded);
    if (tau < FW_FOLD - 0.01 || t >= FW_SLAM4) {
        out.pos = c.tgt + vec3<f32>(Q.x, h, Q.z);
        return out;
    }
    // ---- the chain: the plates, hinged at the rings, as the far land slides in ---------------------------------------------
    let rb = clamp(dist * 0.56, 60.0, 150.0);
    let kappa = mix(rb / 153.0, 1.0, fw_lay(tau));
    let ch = fw_chain(r, a, tau, kappa, t);
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
    R += hh * sn;
    Y += hh * cs;
    // (the sheet sunk from under the island, a dish it stands in: nothing comes up through it)
    let sink = FW_SINK * seat * mix(1.0, FW_SINK_END, fw_lay(tau));
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
    let top = fw_top(tau, kappa, t) - sink;
    var P = fw_place(R, r, a, y, fw_bend(tau, t, mq, e, edge, kappa, top));
    // (the mandala's middle, cut out and left where it is till the bud has come back down to it)
    if (r < FW_ISLE) {
        P = mix(Q + vec3<f32>(0.0, rip, 0.0), P, fw_join(tau));
    }
    let bubble = 46.0 - 16.0 * fw_lay(tau);
    out.pos = fw_clear(P + c.tgt + stay, pos, bubble * (1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 1.0, t)));
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
            // (from inside the sphere, a pit in the land is a dark pit, no window on the void)
            if (f.front && fw_held(tau) > 0.5) {
                return Painted(vec4<f32>(0.03, 0.027, 0.03, 1.0), 0.0);
            }
            return drop_;
        }
    }
    // ---- the island's edge: a clean cut, the faces across it would be stretched to the land's new place ------------------
    let dm = length(Q.xz - (c.me.xz - c.tgt.xz));
    let isle = abs(dm - FW_ISLE);
    let gone = fw_ss(FW_FOLD - 0.4, FW_FOLD + 0.2, tau) * (1.0 - fw_ss(FW_SLAM4 - 0.1, FW_SLAM4 + 0.2, t));
    if (gone > 0.5 && isle < 1.7) {
        return drop_;
    }
    // (and the mandala's middle's)
    let mid = abs(r - FW_ISLE);
    if (gone * (1.0 - fw_join(tau)) > 0.5 && mid < 1.7) {
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
    let lifting = fw_p(ring, a, tau, t);
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
        let px = max(0.05, dist * 0.00095);
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
    // ---- past the real land the sphere goes off into its own dusk: the far land's coarse tiles are no use this close --------
    let dusk = fw_ss(600.0, 1500.0, r) * fw_ss(30.5, 33.5, tau) * 0.88;
    col = mix(col, vec3<f32>(0.035, 0.04, 0.1), dusk);
    // ---- the mandala's middle, a line of light where it was cut --------------------------------------------------------------
    {
        let px = max(0.05, dist * 0.00095);
        let line = (1.0 - fw_ss(1.7, 2.2 + px * 2.0, mid)) * fw_ss(FW_SCORE, FW_TEAR, t) * fade * (1.0 - fw_join(tau));
        col = mix(col, vec3<f32>(1.0, 0.95, 0.9) * 1.4, line);
    }
    return Painted(vec4<f32>(col, alpha), fog);
}
