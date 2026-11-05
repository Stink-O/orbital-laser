// The Fold's world warp (the fork's render.set-warp): reality folded like paper, the mandala its crease pattern. Every
// terrain and entity vertex comes through `world_warp`, and every pixel of the terrain through `world_fragment` (after the
// `[fragments]` line) with where it really is, so all of it is anchored to the world and none to the screen. The land is a
// thin sheet: what is under it never moves far and is never drawn (see FRAGMENTS, "the sheet").
//   FW_RIPPLE  rings running out of the target, each bigger than the last
//   FW_SCORE   they sharpen into hairline creases racing over the land: the mandala (fw_crease)
//   FW_TEAR    the creases split on the void, painted on the land itself so nothing under it shows
//   FW_FOLD    the land is pinched up at the target and closes ring by ring (fw_chain), its top outwards, a hinge at each
//              ring, the far land curling up and in; radial pleats take up the circumference
//   FW_SEAL    the bud: a globe of real land. FW_CRUSH it crushes to a point at FW_BEAT
//   FW_REL     the bloom; FW_SLAM0.. the rings slam down, outermost first
// The player stands on an island punched out of the sheet (FW_ISLE), left where it is.
// strike/fold.rs and fold.wgsl share the beats: keep them in step (`the_warp_keeps_the_beats`).
const FW_RIPPLE: f32 = 6.6;
const FW_SCORE: f32 = 12.0;
const FW_TEAR: f32 = 16.0;
const FW_FOLD: f32 = 19.0;
const FW_SEAL: f32 = 31.0;
const FW_CRUSH: f32 = 35.0;
const FW_BEAT: f32 = 37.5;
const FW_REL: f32 = 38.7;
const FW_SLAM4: f32 = 43.1;        // the last of the slams (strike/fold.rs's FD_SLAM)
const FW_END: f32 = 53.0;
const FW_FADE: f32 = 44.0;         // the comedown begins
const FW_TAU: f32 = 6.2831853;
const FW_PI: f32 = 3.14159265;
const FW_LEN: f32 = 480.0;         // the sheet's length, the last ring (strike/fold.rs's FD_RINGS[4])
const FW_LIFT: f32 = 46.0;         // how far the bud hangs over the ground
const FW_SINK: f32 = 16.0;         // how far the sheet sinks from the island
const FW_ISLE: f32 = 26.0;         // the player's island's radius
const FW_LAND_R: f32 = 300.0;      // from FD_LAND on the crater is in the land within this: nothing is cut under it

// ---- what can be taken out: 0 turns each off -----------------------------------------------------------------------
const FW_IRID: f32 = 1.0;          // the iridescence's strength: 1 is about 36 degrees of hue and a quarter more saturation at its peak
const FW_FRACTAL: f32 = 1.0;       // block faces showing smaller copies of themselves
const FW_SPONGE: f32 = 1.0;        // blocks carved into sponges
const FW_CARDS: f32 = 1.0;         // the land's copies dealt along the creases
const FW_PLEATS: f32 = 1.0;        // the radial pleats
const FW_UNDER: f32 = 1.0;         // the sheet's underside painted as rock
const FW_COPIES: f32 = 6.0;
const FW_DISC: f32 = 130.0;        // how far the copies' land reaches from the target (lib.rs asks for these sections)

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
// How far along the sheet's curve ring i ends up lying: the bearing of its plate on the globe, radians from the top pole.
fn fw_phi(i: i32) -> f32 {
    switch i {
        case 0: { return 0.14; }
        case 1: { return 0.48; }
        case 2: { return 0.92; }
        case 3: { return 1.52; }
        default: { return 2.52; }
    }
}
// When ring i slams (FD_SLAM, outermost first).
fn fw_slam(i: i32) -> f32 {
    switch i {
        case 4: { return 39.8; }
        case 3: { return 40.6; }
        case 2: { return 41.4; }
        case 1: { return 42.2; }
        default: { return FW_SLAM4; }
    }
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
// How closed ring i is (0 flat, 1 shut) at bearing a: a petal's middle leads its edges.
fn fw_p(i: i32, a: f32, t: f32) -> f32 {
    if (t >= FW_REL) {
        // (falling, faster and faster, to its slam; a little kick back up)
        let hit = fw_slam(i);
        let u = clamp((t - (hit - 0.8)) / 0.8, 0.0, 1.0);
        let fall = 1.0 - u * u * u;
        let after = max(t - hit, 0.0);
        return fall + 0.035 * exp(-after * 5.0) * abs(sin(after * 9.0)) * step(hit, t);
    }
    let t0 = FW_FOLD + 2.1 * f32(i) + 0.7 * fw_petal(a, i);
    return fw_ss(0.0, 3.6, t - t0);
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
        let ph = fw_phi(i) * p;
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
    return vec3<f32>(R, Y + total, here);
}
// ---- the water: the land takes the droplet the way still water takes a drop -------------------------------------------
// Each pulse of the centre (the droplet going in, then the land's own rebounds) lets go one group of rings, worked out as
// deep water's ring waves (the Cauchy-Poisson problem; refs in the team's notes): at distance r, time s after the pulse, the
// wave here is the one whose group has come this far, k = g s^2 / (4 r^2), so the first rings out are long and fast, the
// ones behind them short and slow, the crests run forward through their group at twice its speed, and a calm grows in the
// middle as the short waves leave. r is softened by FW_CORE so the middle itself falls and rebounds, one formula all the way
// in. Physically a group thins out as r^-3; FW_RB and FW_RP put back enough of that to carry it to the player.
const FW_TOUCH: f32 = 6.0;         // the droplet touches: fold.wgsl's FD_TOUCH
const FW_G: f32 = 480.0;           // the land's gravity, blocks/s^2: higher, every ring faster; a wave's period is 2 pi / sqrt(g k)
const FW_SRC: f32 = 22.0;          // how wide a pulse is, blocks: the shortest ring it makes is about 2.2 of these
const FW_CORE: f32 = 22.0;         // the softened middle
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
    let y = -1.2 * fw_group(r2, t - 6.3) + 2.4 * fw_group(r2, t - 7.6) - 4.2 * fw_group(r2, t - 8.9)
        + 6.4 * fw_group(r2, t - 10.2) - 8.4 * fw_group(r2, t - 11.5);
    return y * (1.0 - fw_ss(FW_SCORE - 0.4, FW_TEAR, t));
}
// The droplet's height a little after it touches (fold.wgsl's fd_meld, in step) and the land at its foot: as water does, the
// land reaches up to meet the drop in a small lip, which runs out as the neck widens and closes in over the drop's top.
fn fw_sink(a: f32, R: f32) -> f32 {
    return R - a * (2.5 + a * ((2.72 * R + 1.0 - 3.75) / 2.25));
}
fn fw_neck(r: f32, t: f32, R: f32) -> f32 {
    let a = t - FW_TOUCH;
    if (a <= 0.0 || a > 1.8 || r > R * 3.0) {
        return 0.0;
    }
    // (the drop's width where it meets the land: fold.wgsl's fd_prof)
    let y = clamp(-fw_sink(a, R) / R, -1.0, 1.72);
    let b = 1.72 - y;
    let q = 0.25773 + y * (0.09111 + y * (-0.07338 + y * (-0.05797 + y * 0.03297)));
    let rho = R * sqrt(max((y + 1.0) * b * b * sqrt(b) * q, 0.0));
    let w = 1.6 + 0.18 * R;
    let e = max(r - rho, 0.0) / w;
    return (0.9 + 0.12 * R) * fw_ss(0.0, 0.22, a) * (1.0 - fw_ss(1.15, 1.75, a)) * exp(-e * e);
}
// The land past `r0` curling up and in over a tube of radius `rc`.
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
// A point of the land on the globe: the target at the top, the far land gathered at the bottom.
fn fw_ball(a: f32, r: f32, h: f32, rb: f32) -> vec3<f32> {
    var th = FW_PI * 0.94 * r / FW_LEN;
    if (r > FW_LEN) {
        th = FW_PI * (0.94 + 0.055 * (1.0 - exp(-(r - FW_LEN) / 700.0)));
    }
    let rr = rb + h * min(rb / 150.0, 1.0);
    return vec3<f32>(rr * sin(th) * cos(a), rr * cos(th), rr * sin(th) * sin(a));
}
// A bubble round the eye: what the warp has moved stays this far off, sliding round it.
fn fw_clear(moved: vec3<f32>, from_: vec3<f32>, keep: f32) -> vec3<f32> {
    let d = length(moved);
    let rad = 46.0 * keep * fw_ss(3.0, 24.0, length(moved - from_));
    if (d >= rad || d < 0.001) {
        return moved;
    }
    return moved * (rad / d);
}
// ---- the cards: the land near the target dealt along the creases -----------------------------------------------------
// Copy k (0 up): which piece of land it is, from the target, and the bearing of the crease it is dealt along.
fn fw_card_at(k: f32, seed: f32) -> vec2<f32> {
    let group = floor(k / 3.0);
    let b = (group * 2.0 + 1.0) * FW_PI / 6.0 * 2.0 + floor(seed * 7.0) * FW_PI / 6.0;
    return vec2<f32>(cos(b), sin(b)) * 74.0;
}
// How far copy k is dealt: 0 not yet, 1 out.
fn fw_card_up(k: f32, t: f32) -> f32 {
    return fw_ss(0.0, 2.2, t - (FW_TEAR + 0.6 + 0.8 * (k % 3.0) + 1.3 * floor(k / 3.0)));
}
fn fw_card(Q: vec3<f32>, k: f32, seed: f32, up: f32) -> vec3<f32> {
    let c = fw_card_at(k, seed);
    let j = k % 3.0 + 1.0;
    let dir = normalize(c);
    // (fanned from its own edge, each further round, and slid out along the crease)
    let L = Q.xz - c;
    let side = vec2<f32>(-dir.y, dir.x);
    let v = fw_rot(L + side * 26.0, 0.42 * j * up) - side * 26.0;
    let along = c + dir * up * (14.0 + 52.0 * j) + side * up * 12.0 * j;
    return vec3<f32>(along.x + v.x, Q.y + up * (9.0 + 12.0 * j), along.y + v.y);
}

struct FwClock { t: f32, tgt: vec3<f32>, me: vec3<f32>, seed: f32, cut: f32 }
fn fw_clock() -> FwClock {
    let w = globals.warp;
    let tgt = (w[0].xyz - w[4].xyz) - w[5].xyz;
    let me = (w[3].xyz - w[4].xyz) - w[5].xyz;
    return FwClock(w[0].w + w[4].w * 0.05, tgt, me, w[2].x, min(50.0 - w[0].y, -20.0));
}
fn fw_live(t: f32) -> bool {
    return globals.warp[2].y > 0.5 && t > FW_TOUCH - 0.2 && t < FW_END;
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
    if (copy > 0u) {
        let k = f32(copy) - 1.0;
        let up = fw_card_up(k, t);
        if (FW_CARDS < 0.5 || up < 0.002 || t > FW_BEAT) {
            out.pos = c.tgt + vec3<f32>(0.0, -4000.0, 0.0);
            out.tint = vec3<f32>(-1.0);
            return out;
        }
        Q = fw_card(Q, k, c.seed, up);
    }
    let r = length(Q.xz);
    let a = atan2(Q.z, Q.x);
    // (the player rides it: what is under them is taken off everything, as though they rose and fell with the land)
    let rip = fw_ripple(r, t) - fw_ripple(length(c.tgt.xz), t) + fw_neck(r, t, clamp(length(c.me.xz - c.tgt.xz) * 0.05, 5.0, 15.0));
    // ---- the island: left where it is ------------------------------------------------------------------------------------
    let dm = length(Q.xz - c.me.xz);
    if (dm < FW_ISLE && copy == 0u) {
        out.pos = pos + vec3<f32>(0.0, rip, 0.0);
        return out;
    }
    // ---- how far on: the sheet's own heights keep to its surface as it goes up ---------------------------------------------
    let opening = fw_ss(FW_REL, FW_SLAM4 + 0.4, t);
    let folded = fw_ss(FW_FOLD - 0.5, FW_FOLD + 6.0, t) * (1.0 - opening);
    // (what is under the sheet doesn't swing out on a lever: pressed up to its cut, then the heights pressed in)
    let cuts = fw_ss(FW_FOLD - 0.5, FW_FOLD, t) * (1.0 - fw_ss(FW_REL, FW_REL + 0.3, t));
    var h = Q.y + rip;
    h = max(h, mix(-4000.0, c.cut, cuts));
    let soft = select(26.0 * (1.0 - exp(h / 26.0)) * -1.0, 110.0 * (1.0 - exp(-h / 110.0)), h > 0.0);
    h = mix(h, soft, folded);
    if (t < FW_FOLD - 0.01) {
        out.pos = c.tgt + vec3<f32>(Q.x, h, Q.z);
        return out;
    }
    // ---- the chain: the plates, hinged at the rings ------------------------------------------------------------------------
    let dist = length(c.me.xz - c.tgt.xz);
    let rb = clamp(dist * 0.56, 60.0, 150.0);
    let ch = fw_chain(r, a, t, rb / 153.0);
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
        hh += FW_PLEATS * (0.5 - tri) * 1.3 * w * sqrt(max(1.0 - squeeze * squeeze, 0.0));
    }
    R += hh * sn;
    Y += hh * cs;
    // ---- the far land, curling up and in; all of it into the globe ------------------------------------------------------
    let curl = fw_ss(FW_FOLD + 1.0, FW_SEAL - 2.0, t) * (1.0 - fw_ss(FW_REL, FW_REL + 1.2, t));
    if (r > FW_LEN) {
        let tube = fw_tube(R, Y, max(R - (r - FW_LEN), dist) + 170.0, mix(3000.0, 700.0, curl), curl * 3.2);
        R = tube.x;
        Y = tube.y;
    }
    let C = vec3<f32>(0.0, rb + FW_LIFT, 0.0);
    // (the sheet sunk a little from under the island, which stands proud as the land slides in beneath it, then hung up)
    let sink = FW_SINK * fw_ss(FW_FOLD, FW_FOLD + 2.5, t) * (1.0 - fw_ss(39.5, FW_SLAM4 - 0.1, t));
    var P = vec3<f32>(R * cos(a), Y - sink + (FW_LIFT + sink) * fw_ss(FW_FOLD + 8.0, FW_SEAL, t) * (1.0 - fw_ss(FW_REL, 39.8, t)), R * sin(a));
    let near = fw_ss(FW_LEN * 0.9, FW_LEN * 1.5, r);
    let cv0 = fw_ss(mix(FW_SEAL - 3.0, FW_SEAL - 7.0, near), FW_SEAL + 0.6, t);
    let cv = cv0 * (1.0 - fw_ss(FW_REL + 0.05, FW_REL + 0.85, t));
    if (cv > 0.0) {
        let u = fw_ss(FW_CRUSH, FW_BEAT, t);
        // (turning slowly, then wound up as it is crushed; none past the point, where it can't be seen to stop)
        let spin = select(0.0, 0.05 * max(t - FW_SEAL, 0.0) + 2.6 * u * u * u, t < FW_REL);
        let B = fw_ball(a + spin, r, h, rb) + C;
        P = mix(P, B, cv * cv * (3.0 - 2.0 * cv));
    }
    // ---- crushed to the point; burst back ----------------------------------------------------------------------------------
    let v = (t - FW_REL) / 0.7;
    var sc = 1.0 - 0.994 * pow(fw_ss(FW_CRUSH, FW_BEAT - 0.05, t), 1.6);
    if (t >= FW_REL) {
        let u = clamp(v, 0.0, 1.0);
        sc = 0.006 + 0.994 * (1.0 - pow(1.0 - u, 3.0)) * (1.0 + 0.12 * sin(u * FW_PI));
    }
    if (sc < 0.9999) {
        P = C + (P - C) * sc;
    }
    let keep = 1.0 - fw_ss(FW_CRUSH, FW_CRUSH + 0.8, t) * (1.0 - fw_ss(FW_REL + 0.3, FW_REL + 0.8, t));
    out.pos = fw_clear(P + c.tgt, pos, keep * (1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 1.0, t)));
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
fn fw_wet(colIn: vec3<f32>, Q: vec3<f32>, r: f32, t: f32, at: vec3<f32>, R: f32) -> vec3<f32> {
    let a = t - FW_TOUCH;
    let e = 1.5;
    let slope = (fw_ripple(r + e, t) - fw_ripple(max(r - e, 0.0), t)) / (2.0 * e);
    let D = Q.xz / max(r, 0.5);
    let N = normalize(vec3<f32>(-slope * D.x, 1.0, -slope * D.y));
    let V = at / max(length(at), 0.01);
    let L = globals.sun.xyz;
    let day = fw_ss(-0.1, 0.2, L.y);
    let sky = mix(globals.fog_color.rgb, globals.sky_color.rgb, 0.5);
    // (the sun's light across the slope, then the sky's in it, more the flatter it is seen: both only what the wave changes)
    let nv = max(dot(N, -V), 0.0);
    let nv0 = max(-V.y, 0.0);
    let fres = pow(1.0 - nv, 5.0) - pow(1.0 - nv0, 5.0);
    var col = colIn * (1.0 + FW_SHEEN * 1.6 * day * (dot(N, L) - L.y));
    col = col + sky * clamp(fres, -0.25, 0.5) * 0.9 * FW_SHEEN;
    // ---- the droplet's metal spreading from the contact, thin as a film, then taken into the land ----------------------------
    let ang = atan2(Q.z, Q.x);
    let rf = R + 40.0 * (1.0 - exp(-a / 1.5)) + 2.5 * sin(ang * 5.0 + 1.0) + 1.5 * sin(ang * 11.0 - 2.0);
    let film = fw_ss(rf, rf - 9.0, r) * fw_ss(0.0, 0.25, a) * (1.0 - fw_ss(8.4, 11.0, t));
    if (film > 0.002) {
        let m = reflect(V, N);
        let env = mix(globals.fog_color.rgb, globals.sky_color.rgb, fw_ss(0.0, 0.55, m.y));
        let glint = pow(max(dot(m, L), 0.0), 90.0) * 2.0 * day;
        let metal = env * vec3<f32>(0.92, 0.95, 1.0) + vec3<f32>(glint);
        col = mix(col, metal, film * (0.5 + 0.45 * pow(1.0 - nv, 3.0)));
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
    // ---- the cards: each its own rectangle of land ---------------------------------------------------------------------
    var card = 0.0;
    if (f.copy > 0u) {
        let k = f32(f.copy) - 1.0;
        let L = Q.xz - fw_card_at(k, c.seed);
        if (max(abs(L.x), abs(L.y)) > 24.0 || Q.y < -10.0 || f.light.x < 6.0) {
            return drop_;
        }
        card = fw_ss(0.0, 0.9, 24.0 - max(abs(L.x), abs(L.y)));
    }
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
    let dm = length(Q.xz - c.me.xz);
    let isle = abs(dm - FW_ISLE);
    let gone = fw_ss(FW_FOLD - 0.4, FW_FOLD + 0.2, t) * (1.0 - fw_ss(FW_SLAM4 - 0.1, FW_SLAM4 + 0.2, t));
    if (gone > 0.5 && isle < 1.7 && f.copy == 0u) {
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
    let lifting = fw_p(ring, a, t);
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
        col = fw_wet(col, Q, r, t, f.at, clamp(length(c.me.xz - c.tgt.xz) * 0.05, 5.0, 15.0));
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
        let opens = fw_ss(FW_TEAR, FW_FOLD + 1.0, t) * (1.0 - fw_ss(FW_FADE + 1.0, FW_END - 2.0, t));
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
    if (f.copy == 0u) {
        let px = max(0.05, dist * 0.00095);
        let line = (1.0 - fw_ss(1.7, 2.2 + px * 2.0, isle)) * fw_ss(FW_SCORE, FW_TEAR, t) * fade;
        col = mix(col, vec3<f32>(1.0, 0.95, 0.9) * 1.4, line);
    }
    if (f.copy > 0u) {
        // (a card's edge, bright as its land was cut)
        col = mix(vec3<f32>(1.0, 0.55, 0.2), col, card);
    }
    return Painted(vec4<f32>(col, alpha), fog);
}
