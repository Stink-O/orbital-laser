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
const FW_CAP: f32 = 0.7;           // how much of the sphere's top folds down: radians round the point

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
// The ripples: five rings out of the target, each bigger than the last.
fn fw_ripple(r: f32, t: f32) -> f32 {
    var y = 0.0;
    for (var k = 0; k < 5; k += 1) {
        let f = f32(k);
        let t0 = FW_RIPPLE + 1.05 * f;
        if (t < t0) {
            break;
        }
        let front = (58.0 + 14.0 * f) * (t - t0) * (1.0 + 0.09 * (t - t0));
        let w = 13.0 + 7.0 * f + 0.05 * front;
        let x = (r - front) / w;
        y += (1.3 + 2.2 * f) * exp(-x * x) * cos(x * 2.4) / (1.0 + r / 340.0);
    }
    return y * (1.0 - fw_ss(FW_SCORE - 0.4, FW_TEAR, t));
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
    var k = fw_lobe(t, FW_FLAT, 42.0, -0.0012) + fw_lobe(t, 42.0, 42.8, 0.0007) + fw_lobe(t, 42.8, 43.7, -0.0004);
    if (t > 43.7) {
        // (up slowly, down all at once)
        let u = (t - 43.7) / (FW_SLAM4 - 43.7);
        let up = fw_ss(0.0, 0.62, u);
        let down = clamp((u - 0.62) / 0.38, 0.0, 1.0);
        k = 0.0006 * up * (1.0 - down * down * down);
    }
    return k;
}
// How far round from the target a point `rho` along the sheet lies on the sphere of curvature k: the stereographic map,
// conformal, so the land is only scaled, never stretched. The land's edge is drawn in to the point as the sphere shuts.
fn fw_theta(rho: f32, k: f32, w: f32) -> f32 {
    let th = 2.0 * atan(rho * k * 0.5);
    return th + (FW_PI - th) * w;
}
// The fold down from the sphere's top: six stages, each half the last, each a tier of twelve points opening out of the
// one before. `v` is how far from the top the land was (1 at the fold's edge, 0 the top itself), `ax` is the sphere's
// axis's length from the top to the target (where the tip ends); gives (out from the axis, down from the top).
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
const FW_TIER_V: f32 = 0.58;       // each tier takes this much less of the land
const FW_TIER_R: f32 = 0.52;       // and is this much narrower, and FW_TIER_L this much shorter
const FW_TIER_L: f32 = 0.56;
// Where tier k's top is, down from the top, of `ax`, and how wide.
fn fw_tier_z(k: i32, z0: f32, ax: f32) -> f32 {
    let q = (1.0 - pow(FW_TIER_L, f32(k))) / (1.0 - pow(FW_TIER_L, 6.0));
    return z0 + (ax - z0) * q;
}
fn fw_tier_b(k: i32, b0: f32) -> f32 {
    return select(b0 * pow(FW_TIER_R, f32(k)), 0.0, k >= 6);
}
// A tier, w 0 at its top, 1 where the next begins: in like a cone, out to a skirt, then a fold back under to the next.
fn fw_tier(w: f32, a: f32, k: i32, z0: f32, ax: f32, b0: f32) -> vec2<f32> {
    let za = fw_tier_z(k, z0, ax);
    let zb = fw_tier_z(k + 1, z0, ax);
    let ra = fw_tier_b(k, b0);
    let rb = fw_tier_b(k + 1, b0);
    let L = zb - za;
    var z = za;
    var b = ra;
    if (w < 0.5) {
        let u = w / 0.5;
        z = za + L * 0.72 * u;
        b = mix(ra, mix(ra, rb, 0.86), u);
    } else if (w < 0.72) {
        let u = (w - 0.5) / 0.22;
        z = za + L * mix(0.72, 1.12, u);
        b = mix(mix(ra, rb, 0.86), mix(ra, rb, 0.2), u);
    } else {
        let u = (w - 0.72) / 0.28;
        z = za + L * mix(1.12, 1.0, u);
        b = mix(mix(ra, rb, 0.2), rb, u);
    }
    // (twelve points, sharpest on the skirt, each tier turned half a point on the last)
    let skirt = fw_ss(0.3, 0.72, w) * (1.0 - fw_ss(0.72, 1.0, w));
    let edge = fw_ss(0.0, 0.25, w) * (1.0 - fw_ss(0.8, 1.0, w));
    b *= 1.0 + (0.5 - fw_petal(a, k)) * (0.1 * edge + 0.5 * skirt);
    return vec2<f32>(b, z);
}
// What's left below tier k's top: a round nose (out, down).
fn fw_nose(v: f32, k: i32, z0: f32, ax: f32, b0: f32) -> vec2<f32> {
    let ra = fw_tier_b(k, b0);
    let u = v / pow(FW_TIER_V, f32(k));
    return vec2<f32>(ra * u, fw_tier_z(k, z0, ax) + 0.3 * ra * (1.0 - u * u));
}
fn fw_tiers(v: f32, a: f32, tau: f32, sphere: vec2<f32>, z0: f32, ax: f32, b0: f32) -> vec2<f32> {
    var s = 0;
    while (s < 6 && tau >= fw_start(s + 1)) {
        s += 1;
    }
    let vk = pow(FW_TIER_V, f32(s));
    // (a part already out)
    if (s >= 6 || v >= vk) {
        let j = i32(floor(log(max(v, 1.0e-5)) / log(FW_TIER_V)));
        let jj = clamp(j, 0, 5);
        let hi = pow(FW_TIER_V, f32(jj));
        let lo = select(hi * FW_TIER_V, 0.0, jj == 5);
        return fw_tier((hi - v) / (hi - lo), a, jj, z0, ax, b0);
    }
    // (the one going, out of the rest: what was the sphere's top, then the nose)
    let e = fw_ss(0.0, 1.0, (tau - fw_start(s)) / (fw_start(s + 1) - fw_start(s)));
    // (quick out of the fold, slow into its place)
    let g = 1.0 - pow(1.0 - e, 2.2);
    var before = sphere;
    if (s > 0) {
        before = fw_nose(v, s, z0, ax, b0);
    }
    let vn = vk * FW_TIER_V;
    var after: vec2<f32>;
    if (s == 5) {
        after = fw_tier((vk - v) / vk, a, s, z0, ax, b0);
    } else if (v >= vn) {
        after = fw_tier((vk - v) / (vk - vn), a, s, z0, ax, b0);
    } else {
        after = fw_nose(v, s + 1, z0, ax, b0);
    }
    return mix(before, after, g);
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
        let b0 = S * sin(FW_CAP);
        let v = psi / FW_CAP;
        let p = fw_tiers(v, a, g.tau, vec2<f32>(X, 2.0 * S - Y), z0, ax, b0);
        // (the land's own heights lie down, on the walls of the tiers: only those at the very edge stay)
        let w = fw_ss(0.86, 1.0, v);
        X = mix(p.x, X, w);
        Y = mix(2.0 * S - p.y, Y, w);
    }
    // ---- turned about the sphere's middle to bring the player's feet to the bottom --------------------------------------
    let thd = fw_theta(g.d, k, 0.0);
    let c = cos(thd);
    let s = sin(thd);
    let up = s / k;
    let yp = 2.0 * pow(sin(thd * 0.5), 2.0) / k;
    let x3 = X * ca;
    let z3 = X * sa;
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
    return globals.warp[2].y > 0.5 && t > FW_RIPPLE - 0.2 && t < FW_END;
}

fn world_warp(pos: vec3<f32>, copy: u32) -> Warped {
    var out = Warped(pos, vec3<f32>(1.0));
    let c = fw_clock();
    let t = c.t;
    // (the mod builds this ahead of the first strike, for a frame, with no parameters: nothing to do)
    if (!fw_live(t)) {
        return out;
    }
    let Q = pos - c.tgt;
    let r = length(Q.xz);
    let a = atan2(Q.z, Q.x);
    let rip = fw_ripple(r, t);
    // ---- the island: left where it is ------------------------------------------------------------------------------------
    let mq = c.me - c.tgt;
    if (length(Q.xz - mq.xz) < FW_ISLE) {
        out.pos = pos + vec3<f32>(0.0, rip, 0.0);
        return out;
    }
    // ---- how far on: the sheet's own heights keep to its surface as it goes up ---------------------------------------------
    let tau = fw_tau(t);
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
        let hairline = scored * fade * hair * (1.0 - 0.8 * opens);
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
