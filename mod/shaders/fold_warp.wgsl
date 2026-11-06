// The Fold's world warp (the fork's render.set-warp): reality folded like paper, the mandala its crease pattern. Every
// terrain and entity vertex comes through `world_warp`, and every pixel of the terrain through `world_fragment` (after the
// `[fragments]` line) with where it really is, so all of it is anchored to the world and none to the screen. The land is a
// thin sheet: what is under it never moves far and is never drawn (see FRAGMENTS, "the sheet").
//   FW_RIPPLE  rings running out of the target, each bigger than the last
//   FW_SCORE   they sharpen into creases racing over the land, one kind of line: the crease pattern (cp_lines)
//   FW_TEAR    by now every crease and ring is drawn, and the sheet is folding along them
//   FW_FOLD    the land swells up round the target ring by ring, one smooth sheet, nothing over anything: every point of it
//              goes to one place (cp_sheet), the horizon rolling up and over behind it (fw_roll)
//   FW_WRAP0   the roll's ring comes in to the target and its tube down, as the swell lies down onto its floor and the land comes back to
//              its own size; by FW_HOLD it has stopped closing (fw_tb), a tube: the player on its floor, the whole of the land round them to
//              the far land's end, the hole in the roof that end, one round line
//   FW_CRUSH   the rim draws in and down: the land's outer band sags from the tube, one sheet, a stalactite of land lowering
//              to the target (fw_place), its mouth closing as it comes, on a timing of its own (fw_gather, fw_tip), with a sway and a strain on it (fw_flex)
//              (from about 36.8 fold.wgsl turns it to the droplet's metal from the tip up, over this same surface: fd_stal, fd_stalactite)
//   FW_BEAT    the drop hanging from its tip (fold.wgsl's fd_hang) touches the target, the strain still building
//   FW_REL     it goes back, not as it came: the reach holds, straining, lets go and is back up (fw_gather, fw_tip); the tube gives, catches itself and lets go (fw_tau),
//              and the bud stands again, every ring up; then
//              ring by ring, outermost first, each falls and bangs down (fw_hit), the last, FW_SLAM4, breaking the land along its creases:
//              the crater swaps in held up at the land's level and falls in, kite by kite (fw_sunk)
// The land under the player is one piece of the sheet: it takes less and less of the sheet's motion the nearer it is to them
// (fw_share), so they stand level on land that bends away from them, no edge to it, till the land is back at its own size and it
// is all the sheet; and from the time the world closes they can't leave it: the tube and its hole are one rigid frame that goes
// with them, whatever they do (fw_stay).
// strike/fold.rs and fold.wgsl share the beats: keep them in step (`the_warp_keeps_the_beats`).
// [post pass too] (mod/build.rs puts what is between these marks before fold.wgsl, which works out the stalactite's surface from the same code)
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
const FW_SINK: f32 = 16.0;         // how far the sheet sinks from under the player
const FW_FEET: f32 = 15.0;         // how far from the player the land is all their own, no part of the sheet's motion
const FW_EYE: f32 = 1.62;          // their eye over their feet
const FW_LAND_R: f32 = 480.0;      // from FD_LAND on the crater is in the land within this: nothing is cut under it
const FW_BOWL: f32 = 66.0;         // how deep the crater's bowl is (strike/fold_land.rs's FD_BOWL)
const FW_SUNK: f32 = 5.6;          // the crater has fallen in by this long after the last slam
const FW_CAVE: f32 = 18.0;         // half the panels' fall's acceleration, blocks a second squared: a little more than what the player falls with

// ---- what can be taken out: 0 turns each off -----------------------------------------------------------------------
const FW_IRID: f32 = 1.0;          // the iridescence's strength: 1 is about 36 degrees of hue and a quarter more saturation at its peak
const FW_FRACTAL: f32 = 1.0;       // block faces showing smaller copies of themselves
const FW_PLEATS: f32 = 1.0;        // the radial pleats
const FW_UNDER: f32 = 1.0;         // the sheet's underside painted as rock
const FW_LAY0: f32 = 27.6;         // the bud lies down onto the sphere's floor between these
const FW_LAY1: f32 = 32.6;
const FW_FLAT0: f32 = 34.5;        // from here on the sheet lies on the sphere with nothing left standing on it
const FW_WRAP0: f32 = 27.0;        // the roll's ring comes in to the target, its tube to the sphere's size, from here to FW_SEAL
const FW_SINK_END: f32 = 0.0;      // how much of FW_SINK is left once the sheet lies on the sphere
const FW_HOLD: f32 = 31.5;         // the fold's clock where the tube stops closing (fw_tb)
const FW_EASE: f32 = 1.5;          // how long it takes to stop
const FW_TUBE_W: f32 = 0.5933;     // fw_bend's w, and how much of the r0 of fw_bend is left, as it holds
const FW_TUBE_R0: f32 = 0.352;
const FW_RIM0: f32 = 0.3;          // the band of land that goes down to the target: from this much of the way to the land's end, to its end
const FW_TURNS: f32 = 0.18;        // how far round it leans on the way
const FW_SHOULDER: f32 = 0.3;      // how far the curve keeps to the tube's own way as it leaves it, of its radius there
const FW_WAIST: f32 = 0.095;       // the curve's third point: how far out of the axis, of that radius...
const FW_RIDGE: f32 = 0.2;         // how far its land stands out of the curve, of its radius
const FW_KNEE: f32 = 200.0;        // ...and how high, blocks: low and near the axis, it comes in and hangs: a long thin taper, a reach, not a bag
const FW_TIP: f32 = 14.0;          // how high over the target's land the band stops: what touches it is the drop hanging from it (fold.wgsl's fd_hang)
const FW_END_K: f32 = 0.97;        // how much of the far land's reach is drawn: its own end goes in steps, a chunk at a time, and this one is a circle
const FW_MOUTH: f32 = 2.8;         // how far round the tube the land's end comes, radians, wherever the far land ends
fn fw_ss(a: f32, b: f32, x: f32) -> f32 {
    let t = clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
// [end post pass too]
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
// Ring i's plate's bearing, radians from the top pole: as it closes, never past upright, so what rises stands over the land
// and nothing over anything; running back, `rt` past FW_REL, the bud stands right up, its last all but upright: past that its land folds back over itself.
fn fw_phi(i: i32, rt: f32) -> f32 {
    if (rt >= FW_REL) {
        switch i {
            case 0: { return 0.14; }
            case 1: { return 0.48; }
            case 2: { return 0.92; }
            case 3: { return 1.3; }
            default: { return 1.5; }
        }
    }
    switch i {
        case 0: { return 0.1; }
        case 1: { return 0.38; }
        case 2: { return 0.78; }
        case 3: { return 1.12; }
        default: { return 0.7; }
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
    return fw_ss(28.8, FW_LAY1, tau);
}
// Something uneven at bearing a, -1 to 1, its own for each i: round the circle once, so no seam, and no symmetry to it.
fn fw_wob(a: f32, i: i32) -> f32 {
    let k = f32(i);
    return (sin(a * 2.0 + 1.3 * k + 0.4) + 0.7 * sin(a * 5.0 - 2.1 * k + 1.1) + 0.45 * sin(a * 11.0 + 0.7 * k) + 0.3 * sin(a * 17.0 - 1.9 * k)) / 2.45;
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
// How closed ring i is (0 flat, 1 shut) on the fold's clock `tau`, `lead` how long it is behind the rest at this bearing. From
// FW_REL, `t` the strike's clock, it stays shut till it is its turn to fall, and falling, faster and faster, it stops dead.
fn fw_p(i: i32, lead: f32, tau: f32, t: f32) -> f32 {
    if (t >= FW_REL) {
        let u = clamp((t - fw_hit(i) + FW_FALL) / FW_FALL, 0.0, 1.0);
        return 1.0 - u * u * u;
    }
    return fw_ss(0.0, 3.6, tau - FW_FOLD - 2.1 * f32(i) - lead);
}
fn fw_lead(a: f32, i: i32) -> f32 {
    return 0.35 + 0.22 * (sin(a * 2.0 + 1.7 * f32(i)) + 0.6 * sin(a * 5.0 - 2.3 * f32(i)));
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
// ---- the crease pattern: origami, one pattern at a time, the same everywhere it is used (tools/foldview/pattern.py makes its tables, here and in strike/fold.rs).
// Twelve straight creases 30 degrees apart, out of the target, mountain and valley in turn, and five rings of straight chords round them, mountain and
// valley in turn from ring to ring: a pleated sheet, which is what a closing umbrella is. Across each panel of it, by the wheel's FOLD switch (`/orbital foldpattern`, cp_mode):
//   0 UMBRELLA    nothing: the panels are flat
//   1 WATERBOMB   an X, its middle off the panel, up and down in turn
//   2 DIAGONAL    one diagonal, turn about, so that they run in diamonds, a fold along each (the nodes at their ends stand off the others, CP_DIA)
// Nothing else is drawn and nothing else folds: every line on the land is a real kink of the sheet and every kink is on a line. What isn't regular is the time each line
// takes and how far each runs: the mountains on past the last ring, the valleys stopping short of it.
// It folds as paper does: the pattern's nodes go somewhere (cp_bear), and every point of the land goes where the nodes of its panel put it (cp_sheet). A panel
// between two creases and two chords is flat: its chords are parallel, whatever the nodes do. Each node fires as its crease reaches it. Nodes keep to their
// bearing, so a wedge never leaves its sector of the circle and no two wedges can meet; along a bearing the sheet is one line going one way: nothing over anything.
const CP_K: f32 = 0.75;            // the big creases' fold: a panel's slope, per radian of cp_rise
const CP_N: i32 = 12;              // the creases (the tables are CP_N * 5 long)
const CP_V: f32 = 0.12;            // WATERBOMB: a panel's middle off it, of its width
const CP_DIA: f32 = 0.05;          // DIAGONAL: how far up or down a node stands, of its radius, in turn
const CP_PRE: f32 = 0.62;          // how far the folds go before the land lifts: all of it by FW_FOLD + 5
const CP_REST: f32 = 0.5;          // how much of them is left in the sphere's walls
fn cp_dir(k: i32) -> vec2<f32> {
    switch k {
        case 0: { return vec2<f32>(1.000000, 0.000000); }
        case 1: { return vec2<f32>(0.866025, 0.500000); }
        case 2: { return vec2<f32>(0.500000, 0.866025); }
        case 3: { return vec2<f32>(0.000000, 1.000000); }
        case 4: { return vec2<f32>(-0.500000, 0.866025); }
        case 5: { return vec2<f32>(-0.866025, 0.500000); }
        case 6: { return vec2<f32>(-1.000000, 0.000000); }
        case 7: { return vec2<f32>(-0.866025, -0.500000); }
        case 8: { return vec2<f32>(-0.500000, -0.866025); }
        case 9: { return vec2<f32>(-0.000000, -1.000000); }
        case 10: { return vec2<f32>(0.500000, -0.866025); }
        default: { return vec2<f32>(0.866025, -0.500000); }
    }
}
// How high a big crease is, a block out: its neighbours' angles apart, up then down, so a zigzag of one slope closes on itself.
fn cp_rise(k: i32) -> f32 {
    switch k {
        case 0: { return 0.261799; }
        case 1: { return -0.261799; }
        case 2: { return 0.261799; }
        case 3: { return -0.261799; }
        case 4: { return 0.261799; }
        case 5: { return -0.261799; }
        case 6: { return 0.261799; }
        case 7: { return -0.261799; }
        case 8: { return 0.261799; }
        case 9: { return -0.261799; }
        case 10: { return 0.261799; }
        default: { return -0.261799; }
    }
}
// How far out it reaches, to its point.
fn cp_end(k: i32) -> f32 {
    switch k {
        case 0: { return 623.4; }
        case 1: { return 316.1; }
        case 2: { return 580.8; }
        case 3: { return 367.4; }
        case 4: { return 644.7; }
        case 5: { return 299.0; }
        case 6: { return 602.1; }
        case 7: { return 346.0; }
        case 8: { return 564.8; }
        case 9: { return 328.9; }
        case 10: { return 634.0; }
        default: { return 384.5; }
    }
}
// The pattern's tables (pattern.py), k * 5 + i for ring i on crease k: one over how far out each ring meets it, and that far out; when the scoring comes to that
// node (fw_score's inverse from cp_born), when the chord from there to crease k + 1 sets off, and when its two chords come to it. Private and constant, as every vertex wants them.
var<private> CP_INV: array<f32, 60> = array<f32, 60>(0.022727, 0.010339, 0.005310, 0.004272, 0.001877, 0.022727, 0.008986, 0.006109, 0.003357, 0.002341, 0.022727, 0.010339, 0.005310, 0.004272, 0.001877, 0.022727, 0.008986, 0.006109, 0.003357, 0.002341, 0.022727, 0.010339, 0.005310, 0.004272, 0.001877, 0.022727, 0.008986, 0.006109, 0.003357, 0.002341, 0.022727, 0.010339, 0.005310, 0.004272, 0.001877, 0.022727, 0.008986, 0.006109, 0.003357, 0.002341, 0.022727, 0.010339, 0.005310, 0.004272, 0.001877, 0.022727, 0.008986, 0.006109, 0.003357, 0.002341, 0.022727, 0.010339, 0.005310, 0.004272, 0.001877, 0.022727, 0.008986, 0.006109, 0.003357, 0.002341);
var<private> CP_Q: array<f32, 60> = array<f32, 60>(44.00, 96.72, 188.32, 234.08, 532.80, 44.00, 111.28, 163.68, 297.92, 427.20, 44.00, 96.72, 188.32, 234.08, 532.80, 44.00, 111.28, 163.68, 297.92, 427.20, 44.00, 96.72, 188.32, 234.08, 532.80, 44.00, 111.28, 163.68, 297.92, 427.20, 44.00, 96.72, 188.32, 234.08, 532.80, 44.00, 111.28, 163.68, 297.92, 427.20, 44.00, 96.72, 188.32, 234.08, 532.80, 44.00, 111.28, 163.68, 297.92, 427.20, 44.00, 96.72, 188.32, 234.08, 532.80, 44.00, 111.28, 163.68, 297.92, 427.20);
// (and how far up or down each node stands, of its radius)
var<private> CP_Z: array<f32, 60> = array<f32, 60>(-0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850, -0.0850, 0.0850, -0.0850, 0.0850, -0.0850);
var<private> CP_AT: array<f32, 60> = array<f32, 60>(12.83, 13.35, 13.99, 14.24, 15.43, 13.45, 14.09, 14.46, 15.17, 15.69, 13.07, 13.59, 14.23, 14.48, 15.67, 13.78, 14.42, 14.79, 15.50, 16.02, 13.21, 13.73, 14.37, 14.62, 15.81, 13.61, 14.25, 14.62, 15.33, 15.85, 12.93, 13.45, 14.09, 14.34, 15.53, 13.91, 14.55, 14.92, 15.63, 16.15, 13.33, 13.85, 14.49, 14.74, 15.93, 13.68, 14.32, 14.69, 15.40, 15.92, 13.01, 13.53, 14.17, 14.42, 15.61, 13.51, 14.15, 14.52, 15.23, 15.75);
var<private> CP_CORD: array<f32, 60> = array<f32, 60>(13.80, 14.27, 14.70, 15.02, 16.41, 13.97, 14.02, 14.55, 14.89, 16.59, 13.94, 13.99, 15.04, 15.14, 16.60, 13.62, 14.21, 15.13, 15.28, 16.30, 13.85, 14.45, 15.14, 15.50, 16.38, 13.75, 14.50, 15.21, 15.24, 16.37, 13.32, 14.13, 15.05, 14.73, 16.38, 13.51, 14.24, 15.26, 15.03, 16.72, 14.01, 14.45, 15.30, 15.38, 16.57, 14.14, 14.04, 14.82, 15.13, 16.30, 13.79, 13.90, 14.91, 15.15, 16.47, 13.71, 14.19, 15.18, 15.34, 16.54);
var<private> CP_CH: array<f32, 60> = array<f32, 60>(13.78, 14.05, 14.32, 14.75, 16.46, 14.16, 13.99, 14.78, 15.04, 16.71, 13.71, 14.00, 15.30, 15.23, 16.50, 13.52, 14.42, 14.96, 15.32, 16.10, 14.18, 14.49, 15.32, 15.69, 16.65, 13.32, 14.50, 15.10, 14.79, 16.10, 13.31, 13.76, 15.01, 14.68, 16.66, 13.71, 14.71, 15.50, 15.39, 16.78, 14.31, 14.18, 15.10, 15.37, 16.37, 13.98, 13.90, 14.54, 14.90, 16.22, 13.60, 13.90, 15.27, 15.40, 16.72, 13.82, 14.49, 15.09, 15.28, 16.36);
// When it sets off.
fn cp_born(k: i32) -> f32 {
    switch k {
        case 0: { return 12.10; }
        case 1: { return 12.72; }
        case 2: { return 12.34; }
        case 3: { return 13.05; }
        case 4: { return 12.48; }
        case 5: { return 12.88; }
        case 6: { return 12.20; }
        case 7: { return 13.18; }
        case 8: { return 12.60; }
        case 9: { return 12.95; }
        case 10: { return 12.28; }
        default: { return 12.78; }
    }
}
fn cp_x(a: vec2<f32>, b: vec2<f32>) -> f32 {
    return a.x * b.y - a.y * b.x;
}
// The wedge bearing a lies in: big creases k and k1, the unit vector at a as u e0 + v e1, and x[i] one over how far out ring i's
// chord is at a.
struct CpW { k: i32, k1: i32, e0: vec2<f32>, e1: vec2<f32>, u: f32, v: f32, ct: f32, st: f32 }
fn cp_wedge(a: f32, q: vec2<f32>, r: f32) -> CpW {
    let turn = fract(globals.warp[2].x * 0.618034) * FW_TAU;
    let ct = cos(turn);
    let st = sin(turn);
    let x = fract((a - turn) / FW_TAU) * f32(CP_N);
    let k = min(i32(x), CP_N - 1);
    let k1 = (k + 1) % CP_N;
    let e0 = cp_dir(k);
    let e1 = cp_dir(k1);
    let qr = q / max(r, 0.001);
    let d = vec2<f32>(qr.x * ct + qr.y * st, qr.y * ct - qr.x * st);
    let det = cp_x(e0, e1);
    return CpW(k, k1, e0, e1, cp_x(d, e1) / det, cp_x(e0, d) / det, ct, st);
}
// Where ring i meets big crease k.
fn cp_node(k: i32, i: i32) -> f32 {
    return CP_Q[k * 5 + i];
}
// One over how far out ring i's chord is at this bearing.
fn cp_ix(w: CpW, i: i32) -> f32 {
    return w.u * CP_INV[w.k * 5 + i] + w.v * CP_INV[w.k1 * 5 + i];
}
// Ring i's edge in this wedge, at its bearing: the straight chord from node to node.
fn cp_rho(w: CpW, i: i32) -> f32 {
    return 1.0 / cp_ix(w, i);
}
// Which facet of the wedge r is in, 0 to 4; 5 past the last ring.
fn cp_cell(w: CpW, r: f32) -> i32 {
    for (var i = 0; i < 5; i += 1) {
        if (r * cp_ix(w, i) < 1.0) {
            return i;
        }
    }
    return 5;
}
// Which pattern this strike folds on: (strike/fold.rs's fd_lie) under params[10]'s whole number, 1024ths of one, one more than 100 pattern + 6 k + cell.
fn cp_code() -> i32 {
    let x = globals.warp[2].z;
    return i32(round((ceil(x) - x) * 1024.0)) - 1;
}
fn cp_mode() -> i32 {
    return clamp(cp_code() / 100, 0, 2);
}
// A panel of the pattern: the wedge's cell i, its corners round it, a and b on crease k, c and d on crease k1 (a and d the target in
// cell 0), and v where its four triangles meet, its point m of the way across and along (flat across unless its pattern folds there; a line there only then); sp which of its corners
// a line of the pattern's own goes to: every other from 0 (DIAGONAL) or 1, -1 none, 2 all four.
struct CpKite { a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>, v: vec2<f32>, m: vec3<f32>, up: f32, bq: vec4<f32>, sp: i32 }
fn cp_kite(w: CpW, i: i32) -> CpKite {
    let in0 = select(0.0, cp_node(w.k, max(i - 1, 0)), i > 0);
    let in1 = select(0.0, cp_node(w.k1, max(i - 1, 0)), i > 0);
    let q0 = cp_node(w.k, i);
    let q1 = cp_node(w.k1, i);
    let a = in0 * w.e0;
    let b = q0 * w.e0;
    let d = in1 * w.e1;
    let c = q1 * w.e1;
    let odd = ((w.k + i) & 1) == 1;
    let mode = cp_mode();
    var m = vec3<f32>(0.5);
    var sp = -1;
    if (mode == 1) {
        sp = 2;
    } else if (mode == 2) {
        m = select(vec3<f32>(0.0, 1.0, 0.5), vec3<f32>(1.0, 0.0, 0.5), odd);
        sp = select(0, 1, odd);
    }
    return CpKite(a, b, c, d, mix(mix(a, b, m.x), mix(d, c, m.y), m.z), m, select(-1.0, 1.0, odd), vec4<f32>(q0, q1, in0, in1), sp);
}
// Which of the kite's four facets p is in, between its corners j and j + 1 and the apex: its weights there, how far it is from the
// nearest of the facet's three lines, blocks.
struct CpTri { j: i32, lv: f32, lx: f32, ly: f32, e: f32 }
fn cp_tri(kt: CpKite, p: vec2<f32>, exact: bool) -> CpTri {
    var c = array<vec2<f32>, 4>(kt.a, kt.b, kt.c, kt.d);
    let q = p - kt.v;
    var s0 = cp_x(c[0] - kt.v, q);
    let first = s0;
    var j = 3;
    for (var n = 0; n < 3; n += 1) {
        let s1 = cp_x(c[n + 1] - kt.v, q);
        if (s0 >= 0.0 && s1 <= 0.0) {
            j = n;
            break;
        }
        s0 = s1;
    }
    let x = c[j] - kt.v;
    let y = c[(j + 1) & 3] - kt.v;
    let dd = max(cp_x(x, y), 0.001);
    let lx = max(cp_x(q, y) / dd, 0.0);
    let ly = max(cp_x(x, q) / dd, 0.0);
    let lv = max(1.0 - lx - ly, 0.0);
    // (how far off the chord it is, or its pattern's own lines; near enough, lying on the sphere: a groove)
    var e = lv * (kt.bq.x - kt.bq.z);
    if (exact) {
        e = lv * dd / max(length(y - x), 0.001);
        if (kt.sp == 2 || kt.sp == ((j + 1) & 1)) {
            e = min(e, lx * dd / max(length(y), 0.001));
        }
        if (kt.sp == 2 || kt.sp == (j & 1)) {
            e = min(e, ly * dd / max(length(x), 0.001));
        }
    }
    return CpTri(j, lv, lx, ly, e);
}
// Where the land is against a line through a to b: (signed blocks off it, how far along it, 0 to 1, its length).
fn cp_seg(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec3<f32> {
    let e = b - a;
    let l = max(length(e), 0.001);
    let n = e / l;
    return vec3<f32>(cp_x(n, p - a), dot(p - a, n) / l, l);
}
// A crease is a straight line in the world, not one draped over the hills, and a facet is flat: so as the front comes the land's relief
// is pressed out towards one level, CP_FLAT of it everywhere, and along any crease it runs in a groove, CP_GROOVE deep at most, that stays in the sphere's walls. `e` how far the nearest fine line is. What is
// left of its height here: (over the land, along the creases). The level is the land's own, how low it lies round the target (params[10],
// strike/fold.rs's fd_level, from the target), brought to the target's height at the target. Only what stands over it is pressed: pressed
// from under, a column's rock would stand up through the lower land beside it.
fn cp_level(r: f32) -> f32 {
    return ceil(globals.warp[2].z) * min(r / 170.0, 1.0);
}
fn cp_squash(y: f32, level: f32, pr: f32) -> f32 {
    return level + max(y - level, 0.0) * pr + min(y - level, 0.0);
}
const CP_FLAT: f32 = 0.35;
// The groove a crease runs down, what cp_press's second number leaves: only so deep. Taken from all the land's height over the level it was a trench as
// deep as the hills, a wall of stretched columns either side of every line.
const CP_GROOVE: f32 = 5.0;
fn cp_groove(y: f32, level: f32, gv: f32) -> f32 {
    return y - min((1.0 - gv) * max(y - level, 0.0), CP_GROOVE);
}
fn cp_press(r: f32, w: CpW, t: f32, e: f32) -> vec2<f32> {
    let p = (w.u * w.e0 + w.v * w.e1) * r;
    var bl = 0.0;
    for (var j = 0; j < 2; j += 1) {
        let k = select(w.k, w.k1, j == 1);
        let e = select(w.e0, w.e1, j == 1);
        let q = dot(p, e);
        let end = cp_end(k);
        let g = min(fw_score(t - cp_born(k) + FW_SCORE), end);
        let wide = 17.0 + 0.03 * q;
        let d = abs(cp_x(e, p));
        if (q > 0.0 && d < wide && q < g) {
            bl = max(bl, fw_ss(0.0, 60.0, g - q) * fw_ss(0.0, 34.0, q) * fw_ss(end, end * 0.72, q) * (1.0 - fw_ss(0.22 * wide, wide, d)));
        }
    }
    // (the chords and the spokes too, narrower, as they fire: a groove through a forest, the line down the middle of it)
    let fine = fw_ss(FW_SCORE + 2.0, FW_SCORE + 5.0, t) * (1.0 - fw_ss(1.0, 9.0, e));
    return vec2<f32>(1.0 - CP_FLAT * fw_ss(FW_SCORE + 0.3, FW_TEAR + 1.5, t) * fw_ss(0.0, 150.0, fw_score(t) - r) * fw_ss(FW_LEN * 1.25, FW_LEN, r), 1.0 - 0.9 * max(bl, fine));
}
// When the chord of wedge k at ring i is scored.
fn cp_chord(k: i32, i: i32) -> f32 {
    return CP_CH[k * 5 + i];
}
// How far the scoring has raced by t.
fn fw_score(t: f32) -> f32 {
    let u = max(t - FW_SCORE, 0.0);
    return 40.0 * u + 26.0 * u * u + 3.0 * u * u * u;
}
// ---- the chain ----------------------------------------------------------------------------------------------------------
// The sheet's cross-section at bearing a: from the top pole (the target), plate after rigid plate, each a ring, hinged at
// its edge, the last lying on the ground. A point r along it: (R out from the axis, Y up, the plate's angle).
// A plate shrinks to `kappa` as it closes, so what has closed is a dome no wider than the globe, inside the player's distance
// whatever it is, and what hasn't lies flat and slides in to the dome's foot.
// How much of the folds the sheet has on the fold's clock: going up they deepen as it lifts, and all but go as it comes back to its
// own size on the sphere; running back they stand again, and each ring's own go with it as it falls.
fn cp_amount(tau: f32, rt: f32) -> f32 {
    return select(mix(CP_PRE, 1.0, fw_ss(FW_FOLD, FW_FOLD + 5.0, tau)), 1.0, rt >= FW_REL) * mix(1.0, CP_REST, fw_lay(tau));
}
// The player's own kite is left alone, so that nothing rises under them: (its crease, its cell), from where they stood as it fired (fd_pin in
// strike/fold.rs): under params[10]'s whole number, with the pattern (cp_code).
fn cp_pin() -> vec2<i32> {
    let code = cp_code() % 100;
    return vec2<i32>(code / 6, code % 6);
}
// Is ring i's node on big crease k one of the pinned kite's?
fn cp_pinned(k: i32, i: i32, pin: vec2<i32>) -> bool {
    return (k == pin.x || k == (pin.x + 1) % CP_N) && (i == pin.y || i == pin.y - 1);
}
// The sheet's rings, what a vertex needs of the chain: the way plate i goes, per block of its length (an arc's chord over its length doesn't depend
// on the length), how far a plate has shrunk to, the sine and cosine of its angle at its outer edge, how closed it is; and where the chain at
// the rings' mean radii ends: (how far out its foot has come, how high its top stands).
struct CpR { D: array<vec2<f32>, 5>, kk: array<f32, 5>, sn: array<f32, 5>, cs: array<f32, 5>, ps: array<f32, 6>, foot: vec2<f32> }
fn cp_rings(tau: f32, t: f32, kappa: f32) -> CpR {
    var g: CpR;
    var ph: array<f32, 6>;
    let soft = fw_soft(tau, t);
    for (var i = 0; i < 5; i += 1) {
        g.ps[i] = fw_p(i, 0.35, tau, t);
        ph[i] = fw_phi(i, t) * g.ps[i] * fw_lie(i, tau);
    }
    ph[5] = 0.0;
    g.ps[5] = 0.0;
    var last = 0.0;
    var prev = 0.0;
    for (var i = 0; i < 5; i += 1) {
        let a0 = mix(ph[i], 0.5 * (last + ph[i]), soft);
        let a1 = mix(ph[i], 0.5 * (ph[i] + ph[i + 1]), soft);
        g.D[i] = fw_arc(a0, a1, 1.0, 1.0);
        g.kk[i] = mix(1.0, kappa, g.ps[i]);
        g.sn[i] = sin(a1);
        g.cs[i] = cos(a1);
        let rho = fw_ring(i);
        g.foot += g.D[i] * (rho - prev) * g.kk[i];
        prev = rho;
        last = ph[i];
    }
    return g;
}
// How far node (k, i) stands off the sheet, of how far out it is: each fires as its crease comes to it, and as its chords do; the last ring lies on
// the land past it.
fn cp_lift(k: i32, i: i32, t: f32, pin: vec2<i32>) -> f32 {
    if (i >= 4 || cp_pinned(k, i, pin)) {
        return 0.0;
    }
    var ring = CP_Z[k * 5 + i];
    // (the diagonals' fold: the nodes at their ends one way, the others the other)
    if (cp_mode() == 2) {
        ring += select(-CP_DIA, CP_DIA, ((k + i) & 1) == 1);
    }
    var big = CP_K * cp_rise(k);
    if (t < 19.0) {
        big *= fw_ss(0.0, 1.5, t - CP_AT[k * 5 + i]);
        ring *= fw_ss(0.0, 1.4, t - CP_CORD[k * 5 + i]);
    }
    return big + ring;
}
// Where the sheet goes: the point of the pattern at (r, its wedge w), its cell i and facet tr in the kite kt, with the land's height hh over it, from the
// target, turned by the pattern's turn to the world; n the facet's way up. `top` the sheet's top, over the target. `g` none when it lies flat.
struct CpS { pos: vec3<f32>, n: vec3<f32> }
fn cp_sheet(w: CpW, i: i32, kt: CpKite, tr: CpTri, r: f32, hh: f32, tau: f32, t: f32, top: f32, pin: vec2<i32>, g: CpR, lifts: bool) -> CpS {
    let amount = cp_amount(tau, t);
    let m = min(i, 4);
    let in_ = i - 1;
    // ---- the nodes it needs: out along crease k and crease k1, one sum, then up from the foot -----------------------------------------
    var oa = vec2<f32>(0.0);
    var ob = vec2<f32>(0.0);
    var oc = vec2<f32>(0.0);
    var od = vec2<f32>(0.0);
    var sn0 = 0.0;
    var cs0 = 1.0;
    var sn1 = 0.0;
    var cs1 = 1.0;
    let ik = w.k * 5;
    let ik1 = w.k1 * 5;
    if (lifts) {
        var c0 = vec2<f32>(0.0);
        var c1 = vec2<f32>(0.0);
        var p0 = 0.0;
        var p1 = 0.0;
        for (var j = 0; j < 5; j += 1) {
            let q0 = CP_Q[ik + j];
            let q1 = CP_Q[ik1 + j];
            c0 += g.D[j] * (q0 - p0) * g.kk[j];
            c1 += g.D[j] * (q1 - p1) * g.kk[j];
            p0 = q0;
            p1 = q1;
            if (j == in_) {
                oa = c0;
                od = c1;
            }
            if (j == m) {
                ob = c0;
                oc = c1;
            }
        }
        oa = vec2<f32>(oa.x, c0.y - oa.y);
        ob = vec2<f32>(ob.x, c0.y - ob.y);
        oc = vec2<f32>(oc.x, c1.y - oc.y);
        od = vec2<f32>(od.x, c1.y - od.y);
        sn1 = g.sn[m];
        cs1 = g.cs[m];
        if (i > 0) {
            sn0 = g.sn[in_];
            cs0 = g.cs[in_];
        }
    } else {
        ob = vec2<f32>(CP_Q[ik + m], 0.0);
        oc = vec2<f32>(CP_Q[ik1 + m], 0.0);
        if (i > 0) {
            oa = vec2<f32>(CP_Q[ik + in_], 0.0);
            od = vec2<f32>(CP_Q[ik1 + in_], 0.0);
        }
    }
    // (running back each node lies down with the ring outside it)
    let fall = select(1.0, g.ps[min(m + 1, 5)], t >= FW_REL && lifts);
    let zb = ob.x * cp_lift(w.k, m, t, pin) * amount * fall;
    let zc = oc.x * cp_lift(w.k1, m, t, pin) * amount * fall;
    let B2 = ob + vec2<f32>(sn1, cs1) * zb;
    let C2 = oc + vec2<f32>(sn1, cs1) * zc;
    let B = vec3<f32>(B2.x * w.e0.x, B2.y, B2.x * w.e0.y);
    let C = vec3<f32>(C2.x * w.e1.x, C2.y, C2.x * w.e1.y);
    var S = vec3<f32>(0.0);
    var n = vec3<f32>(0.0, 1.0, 0.0);
    var under = n;
    if (i < 5) {
        var A = vec3<f32>(0.0, top, 0.0);
        var D = A;
        if (i > 0) {
            let fall0 = select(1.0, g.ps[i], t >= FW_REL && lifts);
            let A2 = oa + vec2<f32>(sn0, cs0) * (oa.x * cp_lift(w.k, in_, t, pin) * amount * fall0);
            let D2 = od + vec2<f32>(sn0, cs0) * (od.x * cp_lift(w.k1, in_, t, pin) * amount * fall0);
            A = vec3<f32>(A2.x * w.e0.x, A2.y, A2.x * w.e0.y);
            D = vec3<f32>(D2.x * w.e1.x, D2.y, D2.x * w.e1.y);
        }
        var V = mix(mix(A, B, kt.m.x), mix(D, C, kt.m.y), kt.m.z);
        if (cp_mode() == 1 && (w.k != pin.x || i != pin.y)) {
            let up = cross(C - A, B - D);
            let nv = up / max(length(up), 0.001);
            let f = fw_ss(0.0, 1.3, t - CP_CH[w.k * 5 + i] - 0.6) * select(1.0, g.ps[i], t >= FW_REL && lifts);
            V += nv * kt.up * CP_V * min(length(C - B), 0.7 * (kt.bq.x - kt.bq.z + kt.bq.y - kt.bq.w)) * f * amount;
        }
        var c = array<vec3<f32>, 4>(A, B, C, D);
        let X = c[tr.j];
        let Y = c[(tr.j + 1) & 3];
        S = V * tr.lv + X * tr.lx + Y * tr.ly;
        let up = cross(Y - V, X - V);
        // (a facet's own winding, never turned to face the sky: a plate past upright has its land on what is now its underside, and turned over here
        // that land stands out through the back of the sheet, inside out)
        n = up / max(length(up), 0.001);
        // (what stands on the sheet and what lies under it go one way off it, the same way on both sides of a crease: along each facet's own normal
        // the heights fan apart over a ridge and cross in a valley)
        let dd = w.u * w.e0 + w.v * w.e1;
        let in_out = clamp((r - select(0.0, cp_rho(w, in_), i > 0)) / max(cp_rho(w, m) - select(0.0, cp_rho(w, in_), i > 0), 0.001), 0.0, 1.0);
        let a2 = mix(vec2<f32>(sn0, cs0), vec2<f32>(sn1, cs1), in_out);
        under = vec3<f32>(a2.x * dd.x, a2.y, a2.x * dd.y);
    } else {
        // (the far land: lying flat, slid in by what the rings have taken up. Squeezed round the foot of what has closed it would go to
        // streaks, so as it closes it is drawn in near the foot by as much across as round, and only further out comes back to its size)
        let d = w.u * w.e0 + w.v * w.e1;
        let rho = cp_rho(w, 4);
        let w0 = w.u * rho * CP_INV[ik + 4];
        let on = mix(C, B, clamp(w0, 0.0, 1.0));
        let x = r - rho;
        let s0 = clamp(length(on.xz) / rho, 0.0, 1.0);
        let more = mix(x, x * s0 + (1.0 - s0) * (x - 600.0 * (1.0 - exp(-x / 600.0))), fw_soft(tau, t));
        S = vec3<f32>(on.x + d.x * more, on.y, on.z + d.y * more);
    }
    let P = S + under * hh;
    return CpS(vec3<f32>(P.x * w.ct - P.z * w.st, P.y, P.x * w.st + P.z * w.ct), vec3<f32>(n.x * w.ct - n.z * w.st, n.y, n.x * w.st + n.z * w.ct));
}
// All that is left of it lying on the sphere, every vertex of the walls: the facet's height over the sheet, and its way up (x, z).
fn cp_lying(w: CpW, i: i32, kt: CpKite, tr: CpTri, t: f32, pin: vec2<i32>) -> vec3<f32> {
    let ik = w.k * 5;
    let ik1 = w.k1 * 5;
    let zb = kt.bq.x * cp_lift(w.k, i, t, pin);
    let zc = kt.bq.y * cp_lift(w.k1, i, t, pin);
    var za = 0.0;
    var zd = 0.0;
    if (i > 0) {
        za = kt.bq.z * cp_lift(w.k, i - 1, t, pin);
        zd = kt.bq.w * cp_lift(w.k1, i - 1, t, pin);
    }
    var zv = mix(mix(za, zb, kt.m.x), mix(zd, zc, kt.m.y), kt.m.z);
    if (cp_mode() == 1 && (w.k != pin.x || i != pin.y)) {
        zv += kt.up * CP_V * min(length(kt.c - kt.b), 0.7 * (kt.bq.x - kt.bq.z + kt.bq.y - kt.bq.w));
    }
    var z = array<f32, 4>(za, zb, zc, zd);
    var c = array<vec2<f32>, 4>(kt.a, kt.b, kt.c, kt.d);
    let zx = z[tr.j];
    let zy = z[(tr.j + 1) & 3];
    let x = c[tr.j];
    let y = c[(tr.j + 1) & 3];
    // (the plane through the three: its slope)
    let e1 = x - kt.v;
    let e2 = y - kt.v;
    let dd = max(cp_x(e1, e2), 0.001);
    let g = vec2<f32>((zx - zv) * e2.y - (zy - zv) * e1.y, (zy - zv) * e1.x - (zx - zv) * e2.x) / dd * CP_REST;
    let n = vec2<f32>(-g.x * w.ct + g.y * w.st, -g.x * w.st - g.y * w.ct);
    return vec3<f32>(CP_REST * (zv * tr.lv + zx * tr.lx + zy * tr.ly), n);
}
// How far the rigid plates have gone to one curved sheet: all of it going up; rigid only as the rings fall back.
fn fw_soft(t: f32, rt: f32) -> f32 {
    return select(1.0, fw_ss(25.5, 27.5, t), rt >= FW_REL);
}
// Along an arc of length L, its angle a0 to a1, the first x of it: (across, down).
fn fw_arc(a0: f32, a1: f32, L: f32, x: f32) -> vec2<f32> {
    let c = (a1 - a0) / max(L, 0.001);
    if (abs(a1 - a0) < 0.002) {
        return vec2<f32>(cos(a0), sin(a0)) * x;
    }
    let e = a0 + c * x;
    return vec2<f32>(sin(e) - sin(a0), cos(a0) - cos(e)) / c;
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
// The land at the droplet's foot: drawn to it, as a blob of a lava lamp or ferrofluid is drawn to a magnet. Nothing shows at
// first; as the gap closes the land gathers under the drop in a low swell, then a finger flicks up the last blocks (the pull
// grows with how near it is) and catches the drop's foot on FW_MEET. The drop doesn't notice: it falls straight on through, and
// the land is snatched up its side in a tight skirt with a hollow flank and closes over its tip at about 6.15. What it took in
// leaves the land heaving, as water goes on after a stone: the finger, a little past where it will rest, thickens to a mound,
// sags, comes up once more and falls, a shallow dimple after it, as the rings start. The reply starts at the drop and travels
// out from it, so the land further off moves later, and no two sides keep time: each has its own moment and reach.
// fold.wgsl's fd_land in step (`the_warp_keeps_the_beats`).
const FW_MEET: f32 = -0.08;        // when it touches, seconds from FW_TOUCH: fold.wgsl's FD_MEET
const FW_DROP: f32 = 1.5;          // how long it falls, let go: FD_TOUCH - FD_HANG
// How high the drop's foot hangs over the target, and how high it is `a` from the touch: from rest, under gravity, straight on
// through the land. fold.wgsl's the same.
fn fw_high(R: f32) -> f32 {
    return 5.0 * R + 19.0;
}
fn fw_over(a: f32, R: f32) -> f32 {
    let u = (a + FW_DROP) / FW_DROP;
    return fw_high(R) * (1.0 - u * u);
}
// How the sides differ, each about -1 to 1: long lobes that drift apart, the first of them one whole side leading. `ang` turned
// with the distance, so they wind out from the drop as they go; fold.wgsl's fd_side the same.
fn fw_side(ang: f32, a: f32) -> vec2<f32> {
    let s = globals.warp[2].x * 2.399;
    return vec2<f32>(
        0.52 * sin(ang + s) + 0.34 * sin(2.0 * ang + s * 1.7 - 0.9 * a) + 0.22 * sin(3.0 * ang - s * 2.3 + 1.4 * a),
        0.5 * sin(ang - s * 1.3 + 2.1) + 0.36 * sin(2.0 * ang + s * 0.7 + 1.1 * a) + 0.2 * sin(5.0 * ang + s * 3.1 - 1.3 * a));
}
// How much of the land's height is left as it falls, from about a second after the touch.
fn fw_sink(a: f32) -> f32 {
    return 1.0 - fw_ss(0.95, 1.95, a);
}
// The wide swell round the finger, blocks: gathering long before the finger does, and slower. Part of fw_land.
fn fw_wide(a: f32, R: f32) -> f32 {
    let u = clamp((a + 0.5) / 1.1, 0.0, 1.0);
    let v = 1.0 - u * u * sqrt(u);
    return 0.4725 * R * (1.0 - v * v) * fw_sink(a);
}
// All of it at the middle, blocks.
fn fw_land(a: f32, R: f32) -> f32 {
    let full = 1.35 * R;
    // (how high the drop's foot is as they meet)
    let meet = fw_over(FW_MEET, R);
    if (a < FW_MEET) {
        let u = clamp((a + 0.5) / (FW_MEET + 0.5), 0.0, 1.0);
        let u3 = u * u * u;
        return fw_wide(a, R) + (meet - fw_wide(FW_MEET, R)) * u3 * u3;
    }
    let s = a - FW_MEET;
    let rise = 1.0 - (1.0 - meet / full) * exp(-s / 0.16);
    return full * ((rise + 0.2 * fw_ss(0.0, 0.45, s) * exp(-1.4 * s) * sin(6.2 * s - 1.35)) * fw_sink(a) - 0.08 * fw_ss(1.7, 2.15, a) * (1.0 - fw_ss(2.15, 2.9, a)));
}
fn fw_neck(r: f32, ang: f32, t: f32, R: f32) -> f32 {
    let a = t - FW_TOUCH;
    if (a <= -0.5 || a >= 4.2 || r > R * 9.0) {
        return 0.0;
    }
    // (none on the axis: the finger stands under the drop)
    let k = fw_ss(0.0, R, r);
    let L = fw_side(ang + r / (3.2 * R), a);
    let as_ = a - 0.07 * L.y * k;
    let reach = 1.0 + 0.09 * L.x * k;
    // (how wide the drop is at the top of the land, this side: fold.wgsl's fd_prof and fd_meld: it falls on at the same pace,
    // from the top of its fall to right through the land; the land hasn't reached it, nothing)
    let h = R + fw_over(a, R);
    let y = clamp((fw_land(as_, R) * reach - h) / R, -1.0, 1.72);
    let b = 1.72 - y;
    let q = 0.25773 + y * (0.09111 + y * (-0.07338 + y * (-0.05797 + y * 0.03297)));
    // (softly from nothing: no side's neck opens with a hard edge beside one not yet touching)
    let z = y + 1.0;
    let touch = R * sqrt(max((0.5 * (z + sqrt(z * z + 0.0036))) * b * b * sqrt(b) * q, 0.0));
    // (past the drop's waist what it leaves is land, not air: the column keeps its width as the taper goes down through it, a lip
    // round the tip, and slumps in from there)
    let rho = max(touch, R * mix(1.0, 0.55, fw_ss(0.0, 1.0, y)) * fw_ss(-0.2, 0.0, y) * (1.0 - 0.6 * fw_ss(0.3, 0.9, a)));
    let d = max(r - rho, 0.0);
    // (its point rounded, and wider, as what is left of the finger slumps into a mound)
    let round_ = 1.0 + 0.4 * R * fw_ss(0.2, 0.7, a);
    let x = sqrt(d * d + round_ * round_) - round_;
    // (news of it reaches further out later, sooner on the leading sides, and only so late: a wave, not a clock)
    let at = as_ - (0.95 + 0.42 * L.x) * (1.0 - exp(-d / (5.2 * R)));
    let wide = fw_wide(at, R);
    let w = R * mix(0.16, 0.42, fw_ss(-0.1, 0.15, at)) * (1.0 + 1.1 * fw_ss(0.25, 0.9, at));
    return ((fw_land(at, R) - wide) * exp(-x / w) * reach + wide * (1.0 + 0.45 * L.y * k) * exp(-x / (3.0 * R))) * (1.0 - fw_ss(6.0 * R, 9.0 * R, r));
}
// How hard the land is being drawn in, 1 at rest at its strongest, `a` from the touch: hardly at all until they meet, then a
// sudden tug past its mark, back, and let go with a little recoil.
fn fw_draw(a: f32) -> f32 {
    if (a < FW_MEET) {
        let u = clamp((a + 0.5) / (FW_MEET + 0.5), 0.0, 1.0);
        return 0.09 * u * u * u * u;
    }
    let s = a - FW_MEET;
    let tug = 1.0 - 0.91 * exp(-s / 0.2) + 0.22 * fw_ss(0.0, 0.5, s) * exp(-1.3 * s) * sin(6.0 * s - 1.5);
    return tug * (1.0 - fw_ss(1.35, 2.3, a)) - 0.1 * fw_ss(1.9, 2.3, a) * (1.0 - fw_ss(2.3, 3.0, a));
}
// How far the land here is drawn in towards the drop, blocks: what stands higher goes further, so trees and walls lean to it,
// and never right on to it.
fn fw_pull(r: f32, ang: f32, y: f32, t: f32, R: f32) -> f32 {
    let a = t - FW_TOUCH;
    if (a <= -0.5 || a >= 4.3 || r > R * 14.0) {
        return 0.0;
    }
    let L = fw_side(ang + r / (3.2 * R), a);
    let at = a - (1.05 + 0.4 * L.x) * (1.0 - exp(-r / (6.5 * R))) - 0.06 * L.y;
    let lean = 1.0 + 2.4 * (1.0 - exp(-max(y, 0.0) / (2.0 * R)));
    let p = 1.12 * R * fw_draw(at) * (1.0 + 0.3 * L.y) * lean * (1.0 - exp(-r / (1.2 * R))) * exp(-r / (2.6 * R));
    let s = 0.8 * r + 0.01;
    return s * (1.0 - exp(-p / s));
}
// [post pass too]
// ---- the sphere ------------------------------------------------------------------------------------------------------
// How big it ends: the player well inside, whatever their distance and however high they stood over the target.
fn fw_radius(d: f32, y: f32) -> f32 {
    return max(max(d * 1.3, 170.0), y * 1.15);
}
// The fold's clock: the strike's up to FW_BEAT, then back to FW_BACK by FW_FLAT. Not the fold played backwards: it stays shut through the touch and while the band goes back up
// (fw_gather, fw_tip); the tube gives all at once and catches itself, hangs there, and then lets go for good, the far land falling away as it did.
const FW_BACK: f32 = 20.0;
fn fw_tau(t: f32) -> f32 {
    if (t < FW_BEAT) {
        return t;
    }
    if (t < FW_REL) {
        return FW_BEAT;
    }
    if (t < 42.2) {
        return fw_h(vec3<f32>(FW_REL, FW_BEAT, 0.0), vec3<f32>(42.2, 34.6, -3.0), t);
    }
    if (t < 42.55) {
        return fw_h(vec3<f32>(42.2, 34.6, -3.0), vec3<f32>(42.55, 32.0, -8.5), t);
    }
    if (t < 42.88) {
        return fw_h(vec3<f32>(42.55, 32.0, -8.5), vec3<f32>(42.88, 31.1, -1.0), t);
    }
    if (t < 43.3) {
        return fw_h(vec3<f32>(42.88, 31.1, -1.0), vec3<f32>(43.3, 28.37, -6.7), t);
    }
    let u = clamp((t - FW_REL) / (FW_FLAT - FW_REL), 0.0, 1.0);
    return FW_BEAT - (FW_BEAT - FW_BACK) * u * u * (3.11 + u * (-5.05 + u * 2.94));
}
// ...and it doesn't go all round at once: as the tube gives, each side of it is a little ahead of or behind the rest.
fn fw_uneven(a: f32, t: f32) -> f32 {
    return 0.9 * fw_ss(42.15, 42.6, t) * (1.0 - fw_ss(43.0, 43.45, t)) * (sin(a * 2.0 + 0.8) + 0.6 * sin(a * 3.0 - 1.2));
}
// ---- the reach: nothing here goes by the fold's clock, the rim's way down and back has a timing of its own, keyed by hand -------------------------------------------
// One piece of a track: from (time, value, slope) a to b.
fn fw_h(a: vec3<f32>, b: vec3<f32>, t: f32) -> f32 {
    let w = b.x - a.x;
    let u = clamp((t - a.x) / w, 0.0, 1.0);
    let u2 = u * u;
    let u3 = u2 * u;
    return a.y * (2.0 * u3 - 3.0 * u2 + 1.0) + b.y * (3.0 * u2 - 2.0 * u3) + w * (a.z * (u3 - 2.0 * u2 + u) + b.z * (u3 - u2));
}
// How far the band has come off the tube on to its curve: the hole breathes out a little, the rim's weight starts to tell, and it goes all at once, its mouth shut well before
// the tip has got anywhere. On the way back it lets go late and opens fast, past where it started, and settles.
fn fw_gather(t: f32) -> f32 {
    if (t < 34.5 || t > 42.9) { return 0.0; }
    if (t < 34.95) { return fw_h(vec3<f32>(34.5, 0.0, 0.0), vec3<f32>(34.95, -0.03, 0.0), t); }
    if (t < 35.4) { return fw_h(vec3<f32>(34.95, -0.03, 0.0), vec3<f32>(35.4, 0.12, 0.62), t); }
    if (t < 35.95) { return fw_h(vec3<f32>(35.4, 0.12, 0.62), vec3<f32>(35.95, 0.8, 1.3), t); }
    if (t < 36.3) { return fw_h(vec3<f32>(35.95, 0.8, 1.3), vec3<f32>(36.3, 1.0, 0.0), t); }
    if (t < 41.45) { return 1.0; }
    if (t < 41.95) { return fw_h(vec3<f32>(41.45, 1.0, 0.0), vec3<f32>(41.95, 0.42, -2.2), t); }
    if (t < 42.25) { return fw_h(vec3<f32>(41.95, 0.42, -2.2), vec3<f32>(42.25, -0.05, -0.3), t); }
    return fw_h(vec3<f32>(42.25, -0.05, -0.3), vec3<f32>(42.9, 0.0, 0.0), t);
}
// How high the band's end is over the target's land once it has come off the tube (FW_TIP at the touch, and the drop under it does the rest). A long heavy fall out of the
// gathered bulge; a catch, where the land takes the weight and the tip gives back; a second, shorter, slower pull; then it thins and creeps, slower and slower, right into the touch.
// Back: held a moment past the touch, strained, then it goes all at once, far faster than it came.
fn fw_tip(t: f32) -> f32 {
    if (t < 35.8) { return FW_TIP0; }
    if (t < 36.3) { return fw_h(vec3<f32>(35.8, FW_TIP0, 0.0), vec3<f32>(36.3, 325.0, -300.0), t); }
    if (t < 36.72) { return fw_h(vec3<f32>(36.3, 325.0, -300.0), vec3<f32>(36.72, 196.0, -210.0), t); }
    if (t < 37.02) { return fw_h(vec3<f32>(36.72, 196.0, -210.0), vec3<f32>(37.02, 158.0, 0.0), t); }
    if (t < 37.2) { return fw_h(vec3<f32>(37.02, 158.0, 0.0), vec3<f32>(37.2, 163.0, 0.0), t); }
    if (t < 37.62) { return fw_h(vec3<f32>(37.2, 163.0, 0.0), vec3<f32>(37.62, 104.0, -170.0), t); }
    if (t < 38.2) { return fw_h(vec3<f32>(37.62, 104.0, -170.0), vec3<f32>(38.2, 50.0, -46.0), t); }
    if (t < 39.15) { return fw_h(vec3<f32>(38.2, 50.0, -46.0), vec3<f32>(39.15, 25.0, -14.0), t); }
    if (t < FW_BEAT) { return fw_h(vec3<f32>(39.15, 25.0, -14.0), vec3<f32>(FW_BEAT, FW_TIP, -7.0), t); }
    if (t < 40.95) { return FW_TIP; }
    if (t < 41.3) { return fw_h(vec3<f32>(40.95, FW_TIP, 0.0), vec3<f32>(41.3, 64.0, 300.0), t); }
    return fw_h(vec3<f32>(41.3, 64.0, 300.0), vec3<f32>(41.85, FW_TIP0, 100.0), t);
}
const FW_TIP0: f32 = 400.0;        // where the end of the gathered bulge hangs before it lets go
// How the band's length moves as it hangs, off the curve and all of it a matter of height, so what looks for a pixel on the curve can take it straight off (fold.wgsl's
// fd_stal). A slow sway that lags from the rim to the tip, and the strain: slow uneven pulses running down it from about 38 s, strongest near the tip, the rim all but
// still, and still growing at the touch. Out: (across, across, out from the axis), blocks.
fn fw_flex(Y: f32, top: f32, t: f32) -> vec3<f32> {
    if (t < 35.3 || t > 42.6) {
        return vec3<f32>(0.0);
    }
    let s = clamp((top - Y) / (top - FW_TIP), 0.0, 1.0);
    // (the tip is held once it is near: what is over it still moves)
    let pin = mix(1.0, fw_ss(2.0, 90.0, Y), fw_ss(38.6, 39.9, t) * (1.0 - fw_ss(41.0, 41.3, t)));
    let back = t - 1.25 * s;
    let sway = fw_ss(35.5, 36.6, t) * (1.0 - fw_ss(41.8, 42.5, t)) * 15.0 * s * sqrt(s) * pin;
    let sx = sin(1.13 * back + 0.9 + 0.8 * sin(0.61 * back)) + 0.55 * sin(2.37 * back + 2.1 + 0.9 * sin(1.03 * back));
    let sz = sin(0.97 * back + 4.1 + 0.7 * sin(0.73 * back + 1.0)) + 0.5 * sin(2.11 * back + 0.4);
    // ---- the strain ---------------------------------------------------------------------------------------------------------
    let e = fw_ss(37.9, 40.9, t) * (1.0 - fw_ss(41.0, 41.5, t));
    if (e <= 0.0) {
        return vec3<f32>(sway * sx, sway * sz, 0.0);
    }
    let w = fw_ss(0.1, 0.8, s) * fw_ss(0.0, 12.0, Y);
    // (down the length, at about 90 blocks a second, the beat uneven)
    let ph = 6.6 * t + 2.3 * sin(1.7 * t + 0.6) + 1.4 * sin(4.1 * t) - 0.07 * (top - Y);
    let beat = sin(ph) + 0.55 * sin(1.73 * ph + 1.1 + t);
    let out_ = 1.5 * e * w * beat;
    let q = 11.0 * t + 2.0 * sin(3.1 * t) - 0.05 * (top - Y);
    let side = 1.0 * e * w * pin;
    return vec3<f32>(sway * sx + side * sin(q), sway * sz + side * sin(1.37 * q + 2.0), out_);
}
// ---- the roll -----------------------------------------------------------------------------------------------------------
// Past `r0` the sheet rolls up and in over a tube of radius `rc`, up to `fm` round it. As the world closes r0 comes in to
// the target and the tube's radius to the sphere's: a tube whose ring has come down to nothing is a sphere, so it is one
// sheet and one motion from the horizon's first curl to the tube. `w` eases it from the roll's own spacing towards the stereographic
// map's, conformal, so that the land is only scaled, hardly stretched.
// The player's feet, and the land under them, are left where they are, level: the whole of it is turned about them.
struct FwBend { tau: f32, t: f32, d: f32, e: vec2<f32>, edge: f32, top: f32, r0: f32, rc: f32, fm: f32, w: f32, fit: f32, draw: f32, tip: f32, pin: f32, rim: f32 }
// The clock the tube closes by: `tau` to FW_HOLD - FW_EASE, then easing to a stop at FW_HOLD, and the same way back.
fn fw_tb(tau: f32) -> f32 {
    let s = FW_HOLD - FW_EASE;
    return select(tau, FW_HOLD - FW_EASE * exp((s - tau) / FW_EASE), tau > s);
}
const FW_TAIL0: f32 = 0.7;         // the land past the roll's end lies on along its tangent till fm is this, and is drawn in by FW_TAIL1
const FW_TAIL1: f32 = 1.5;
fn fw_curl(tau: f32) -> f32 {
    return fw_ss(FW_FOLD + 1.0, 29.0, tau);
}
fn fw_bend(tau: f32, t: f32, foot: f32, mq: vec3<f32>, e: vec2<f32>, edge: f32, top: f32) -> FwBend {
    let d = length(mq.xz);
    let curl = fw_curl(tau);
    let tb = fw_tb(tau);
    let w = fw_ss(FW_WRAP0, FW_SEAL, tb);
    let S = fw_radius(d, mq.y);
    let r0 = (max(foot, d) + 170.0) * (1.0 - fw_ss(FW_WRAP0, FW_SEAL - 0.5, tb));
    let rc = mix(mix(3000.0, 700.0, curl), S, w);
    let fm = mix(curl * 3.2, FW_PI, w);
    // (where the far land ends is the player's setting: wherever that is, the land's end comes as far round the tube)
    let en = max(edge - r0, 1.0) / (rc * max(fm, 0.001));
    let fe = fm * mix(1.0 - exp(-en), 0.63662 * atan(en * 1.5707963), w);
    let fit = max(FW_MOUTH - fe, 0.0) * fw_ss(FW_WRAP0, FW_HOLD, tb);
    return FwBend(tau, t, d, e, edge, top, r0, rc, fm, w, fit, fw_gather(t), fw_tip(t), mq.y, fw_rim(d));
}
// A point R along the sheet, y over it, on the roll: (out from the axis, up, how far round).
fn fw_roll(R: f32, y: f32, g: FwBend) -> vec3<f32> {
    let u = R - g.r0;
    if (u <= 0.0 || g.fm < 0.001) {
        return vec3<f32>(R, y, 0.0);
    }
    let e = u / (g.rc * g.fm);
    let x = e * 1.5707963;
    let ex = exp(-e);
    var f = g.fm * mix(1.0 - ex, 0.63662 * atan(x), g.w);
    f = min(f + g.fit * fw_ss(0.2 * g.edge, g.edge, R), 3.3);
    let lip = 34.0 * g.w * pow(fw_ss(g.rim * 0.8, g.rim, R), 2.0);
    // (the roll is only rc * fm long, and fm starts from nothing: what is past that lies on along the tangent, or all the land out to the horizon would land on one
    // circle the moment it starts; drawn in as the roll grows long enough to take it)
    let tail = 1.0 - fw_ss(FW_TAIL0, FW_TAIL1, g.fm);
    let rem = max(u - g.rc * f, 0.0) * tail;
    let yy = y * mix(mix(ex, 1.0 / (1.0 + x * x), g.w), 1.0, tail) - lip;
    let s = sin(f);
    let c = cos(f);
    return vec3<f32>(g.r0 + (g.rc - yy) * s + rem * c, g.rc * (1.0 - c) + yy * c + rem * s, f);
}
// How far along the funnel's curve the land goes, for how far it is through the band's scale (0 to 1): the curve's steps of length over width, so that a step
// along it is as much squeezed as a step round it, all the way down: the land grows smaller towards the tip as it does on the tube's map, no streaks. Its width
// is floored 40 blocks from the tip, or the tip would take all the land there is. (tools/foldview/mocks.py's spend(), from one typical curve; the shape hardly moves it.)
var<private> FW_SPEND: array<f32, 17> = array<f32, 17>(0.0000, 0.1879, 0.3074, 0.3933, 0.4645, 0.5270, 0.5838, 0.6361, 0.6851, 0.7311, 0.7746, 0.8157, 0.8543, 0.8903, 0.9235, 0.9591, 1.0000);
fn fw_spend(q: f32) -> f32 {
    let x = clamp(q, 0.0, 1.0) * 16.0;
    let i = min(i32(x), 15);
    return mix(FW_SPEND[i], FW_SPEND[i + 1], x - f32(i));
}
// Where the sheet goes: R along it from the target at the bearing (ca, sa), y over it. The result is from the target, x and z as the world's.
// The land's outer band, R1 on to its end, is what comes down to the target: `draw` eases it from the tube to one curve that leaves the tube on the tube's own
// tangent at R1, so there is no join to it, broad for most of the way and rounding off at the target: a stalactite of land lowering, the land's end its mouth.
// Each bearing goes one way along the one curve, so nothing can cross anything.
struct FwWay { P0: vec2<f32>, P1: vec2<f32>, P2: vec2<f32>, P3: vec2<f32>, R1: f32, k: f32 }
fn fw_way(g: FwBend) -> FwWay {
    let R1 = FW_RIM0 * g.edge;
    let a = fw_roll(R1, 0.0, g);
    let P0 = a.xy;
    // (long and thin the further it has come: short, what is in it is in a fat bulge)
    let e = clamp((P0.y - g.tip) / (P0.y - FW_TIP), 0.2, 1.0);
    // (held at the touch it draws itself thin with the strain, and when it lets go that goes at once)
    let thin = 1.0 - 0.14 * fw_ss(39.8, 40.95, g.t) * (1.0 - fw_ss(40.95, 41.12, g.t));
    let P2 = vec2<f32>(min(FW_WAIST * P0.x, 0.35 * max(g.d, 60.0)) * thin / sqrt(e), P0.y - (P0.y - FW_KNEE) * e);
    return FwWay(P0, P0 + vec2<f32>(cos(a.z), sin(a.z)) * P0.x * FW_SHOULDER, P2, vec2<f32>(0.0, g.tip), R1, log(g.edge / R1));
}
// The curve at v, 0 to 1 down the band.
fn fw_curve(v: f32, f: FwWay) -> vec2<f32> {
    let m = 1.0 - v;
    return f.P0 * (m * m * m) + f.P1 * (3.0 * m * m * v) + f.P2 * (3.0 * m * v * v) + f.P3 * (v * v * v);
}
// How far out of the curve the land stands at bearing a, of the curve's own radius there, v down the band.
fn fw_ridge(a: f32, v: f32) -> f32 {
    let w = fw_ss(0.2, 0.42, v) * (1.0 - fw_ss(0.78, 0.92, v));
    if (w <= 0.0) {
        return 0.0;
    }
    return w * FW_RIDGE * (0.5 * sin(3.0 * a + 1.0 + 2.0 * v) + 0.32 * sin(5.0 * a - 2.0 + 3.0 * v) + 0.26 * sin(8.0 * a + 0.5 - 4.0 * v) + 0.18 * sin(13.0 * a + 2.1 + 5.0 * v));
}
fn fw_place(R: f32, ca0: f32, sa0: f32, y: f32, g: FwBend) -> vec3<f32> {
    var on = fw_roll(R, y, g);
    var ca = ca0;
    var sa = sa0;
    var sway = vec3<f32>(0.0);
    if (g.draw != 0.0 && R > FW_RIM0 * g.edge) {
        let f = fw_way(g);
        let v = fw_spend(log(R / f.R1) / f.k);
        on = vec3<f32>(mix(on.xy, fw_curve(v, f), g.draw), on.z);
        // (a mountain's shoulders and gullies, running down it: no pipe)
        on.x *= 1.0 + fw_ridge(atan2(sa0, ca0), v) * max(g.draw, 0.0);
        let tw = FW_TURNS * FW_TAU * v * g.draw;
        let ct = cos(tw);
        let st = sin(tw);
        ca = ca0 * ct - sa0 * st;
        sa = ca0 * st + sa0 * ct;
        sway = fw_flex(on.y, f.P0.y, g.t);
        on.x = max(on.x + sway.z, 0.0);
    }
    let p = vec3<f32>(on.x * ca + sway.x, on.y, on.x * sa + sway.y);
    return fw_turn(p.x, p.y, p.z, fw_roll(g.d, g.pin, g), g);
}
// Where the lip of the land near the target's own columns ends.
fn fw_rim(d: f32) -> f32 {
    return max(620.0, d + 480.0);
}
// The player's place on the held tube: fw_roll at that place, as the rim's tip has it. With fw_turned, what puts the rim's tip on the target:
// fold.wgsl's fd_seat and fd_turned light the target with the same (`the_warp_keeps_the_beats`).
fn fw_seat(d: f32, mh: f32) -> vec3<f32> {
    let S = fw_radius(d, mh);
    let rim = fw_rim(d);
    let r0 = (max(FW_LEN, d) + 170.0) * FW_TUBE_R0;
    let rc = mix(700.0, S, FW_TUBE_W);
    let fm = mix(3.2, FW_PI, FW_TUBE_W);
    let u = d - r0;
    if (u <= 0.0) {
        return vec3<f32>(d, mh, 0.0);
    }
    let e = u / (rc * fm);
    let x = e * 1.5707963;
    let ex = exp(-e);
    let f = min(fm * mix(1.0 - ex, 0.63662 * atan(x), FW_TUBE_W), 3.3);
    let lip = 34.0 * FW_TUBE_W * pow(fw_ss(rim * 0.8, rim, d), 2.0);
    let yy = mh * mix(ex, 1.0 / (1.0 + x * x), FW_TUBE_W) - lip;
    let s = sin(f);
    let c = cos(f);
    return vec3<f32>(r0 + (rc - yy) * s, rc * (1.0 - c) + yy * c, f);
}
// `du` along the land from the player's place and `dy` off it, turned to bring that place to their feet: (out from the axis, up).
fn fw_turned(du: f32, dy: f32, at: vec3<f32>, d: f32, mh: f32) -> vec2<f32> {
    let c = cos(at.z);
    let s = sin(at.z);
    return vec2<f32>(d + du * c + dy * s, -du * s + dy * c + mh);
}
// Turned about the feet, `at` on the roll, to bring them to the bottom.
fn fw_turn(x3: f32, Y: f32, z3: f32, at: vec3<f32>, g: FwBend) -> vec3<f32> {
    let dv = -x3 * g.e.y + z3 * g.e.x;
    let q = fw_turned(x3 * g.e.x + z3 * g.e.y - at.x, Y - at.y, at, g.d, g.pin);
    return vec3<f32>(q.x * g.e.x - dv * g.e.y, q.y, q.x * g.e.y + dv * g.e.x);
}
// [end post pass too]
// How much of the sheet's motion the land `off` from the player takes, 0 at their feet to 1: nothing under them, more and more
// away from them, and over twice as far behind them as towards the target: the sheet slides towards the target as it closes,
// and the land behind them has that much further to catch it. `e` the way from the target to them, `d` how far. `slid` 1 as the sheet slides
// furthest: behind them the ramp stretches out with it, or more of the slide than its width folds the land back over itself in a crescent behind them.
const FW_SLID: f32 = 2.0;
fn fw_share(off: vec2<f32>, e: vec2<f32>, d: f32, slid: f32) -> f32 {
    let dm = length(off);
    return fw_ss(FW_FEET, clamp(0.95 * d, 90.0, 190.0) * (1.0 + fw_ss(-0.2, 0.6, dot(off, e) / max(dm, 0.001)) * (1.0 + FW_SLID * slid)), dm);
}
// When the land under the player has all gone back to the sheet: the sheet is at its own size again by then and their own ring
// (`own`) has lain down (fw_lie), so it is the land that was there and nothing comes up through them.
fn fw_join(tau: f32, own: i32) -> f32 {
    let end = max(33.0, FW_LAY0 + 0.9 * f32(4 - own) + 2.6);
    return fw_ss(end - 1.0, end, tau);
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
// The player can't get away: however far they have come from where they stood (me) is taken off all of it, the land, the hole
// and the branch alike, so that from inside it is one rigid frame and they see the same whatever they do. Nothing shows of how far
// they really go: lib.rs keeps them near enough for the land to stay loaded, and slows their flight while it is shut (FD_STAY).
fn fw_held(tau: f32) -> f32 {
    return fw_ss(FW_WRAP0, 30.0, tau);
}
fn fw_stay(c: FwClock, tau: f32) -> vec3<f32> {
    return (vec3<f32>(0.0, -FW_EYE, 0.0) - c.me) * fw_held(tau);
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

// How much light a facet of the sheet has: its own way up against the sun's, so that it reads as a panel turned in the light, whatever
// the land's own lighting has made of it. (The sun low or down still lights it from where it would be.)
fn cp_shade(n: vec3<f32>, tau: f32) -> f32 {
    let L = normalize(vec3<f32>(globals.sun.x, abs(globals.sun.y) + 0.45, globals.sun.z));
    return clamp(1.0 + mix(1.5, 2.6, fw_lay(tau)) * (dot(n, L) - L.y), 0.42, 1.55);
}
// ---- the damage: the crater earned. Each bang leaves its ring sunk a little, panel by panel, along the creases, and the land burnt (fw_hurt): by the last bang the land on
// the hold already lies where the crater is going to be, as dark as it, broken along the same lines, and the swap is the last blow of it. All of it goes by the pattern's nodes,
// so each panel is flat, its bends on the creases. How far ring n's nodes have gone of their way down, n = -1 the target: most as the ring outside them lands, the rest as their own does.
fn fw_step(hit: f32, t: f32) -> f32 {
    return fw_ss(hit - 0.04, hit + 0.12, t);
}
fn fw_gone(n: i32, t: f32) -> f32 {
    let own = fw_step(fw_hit(max(n, 0)), t);
    return select(0.55 * fw_step(fw_hit(n + 1), t) + 0.45 * own, own, n < 0);
}
// How far down node (k, n) ends up: the rim not at all.
fn fw_sag_node(k: i32, n: i32) -> f32 {
    var d = 20.0;
    if (n >= 3) {
        return 0.0;
    }
    if (n >= 0) {
        d = select(select(8.0, 13.0, n == 1), 18.0, n == 0) * (0.75 + 0.5 * fw_hash(vec2<f32>(f32(k) * 5.0 + 2.0, f32(n) * 9.0 + 4.0)));
    }
    return d;
}
// How far the land at this point of panel kt has sunk by t.
fn fw_sag(w: CpW, i: i32, kt: CpKite, tr: CpTri, t: f32) -> f32 {
    if (i > 3) {
        return 0.0;
    }
    let in_ = fw_gone(i - 1, t);
    let out_ = fw_gone(i, t);
    var z = array<f32, 4>(in_ * fw_sag_node(w.k, select(-1, i - 1, i > 0)), out_ * fw_sag_node(w.k, i), out_ * fw_sag_node(w.k1, i), in_ * fw_sag_node(w.k1, select(-1, i - 1, i > 0)));
    // (the waterbomb's points go on standing out of what has sunk)
    let zv = mix(mix(z[0], z[1], kt.m.x), mix(z[3], z[2], kt.m.y), kt.m.z) + select(0.0, kt.up * 5.0 * out_, kt.sp == 2);
    return zv * tr.lv + z[tr.j] * tr.lx + z[(tr.j + 1) & 3] * tr.ly;
}
// When panel (w, i) lets go of the land's level, after the last slam: from the middle out.
fn fw_late(w: CpW, i: i32) -> f32 {
    return 0.2 + 0.62 * f32(i) + 0.5 * fw_hash(vec2<f32>(f32(w.k) * 13.0 + 3.0, f32(i) * 7.0 + 1.0));
}
// The crater goes in held up where the land had sunk to: the last slam breaks the land along its creases, and each panel of the pattern lets go on
// its own time, from the middle out, the one under the player first, and falls to where it really lies (strike/fold_land.rs's `bowl`:
// keep them in step). What it is still held up by.
fn fw_sunk(Q: vec3<f32>, r: f32, a: f32, t: f32, mq: vec3<f32>) -> f32 {
    let w = cp_wedge(a, Q.xz, r);
    let u = r * cp_ix(w, 3);
    if (u >= 1.0) {
        return 0.0;
    }
    let i = cp_cell(w, r);
    let mr = length(mq.xz);
    let mw = cp_wedge(atan2(mq.z, mq.x), mq.xz, mr);
    let late = select(fw_late(w, i), 0.0, w.k == mw.k && i == cp_cell(mw, mr));
    let s = max(t - FW_SLAM4 - late, 0.0);
    let kt = cp_kite(w, i);
    let sag = fw_sag(w, i, kt, cp_tri(kt, (w.u * w.e0 + w.v * w.e1) * r, false), t) * fw_ss(FW_FEET, FW_FEET + 40.0, length(Q.xz - mq.xz));
    return max(FW_BOWL * pow(1.0 - u * u * u, 0.75) - sag - FW_CAVE * s * s, 0.0);
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
    let r = length(Q.xz);
    let a = atan2(Q.z, Q.x);
    if (copy > 0u) {
        out.pos = c.tgt + vec3<f32>(0.0, -4000.0, 0.0);
        out.tint = vec3<f32>(-1.0);
        return out;
    }
    if (t >= FW_SLAM4 + 0.01 && t < FW_SLAM4 + FW_SUNK) {
        Q.y += fw_sunk(Q, r, a, t, c.me - c.tgt);
    } else if (t > FW_FLAT && t < FW_SLAM4 + 0.01 && r < 310.0) {
        // (each ring sunk a little as it lands)
        let w = cp_wedge(a, Q.xz, r);
        let i = cp_cell(w, r);
        if (i < 4) {
            let kt = cp_kite(w, i);
            Q.y -= fw_sag(w, i, kt, cp_tri(kt, (w.u * w.e0 + w.v * w.e1) * r, false), t) * fw_ss(FW_FEET, FW_FEET + 40.0, length(Q.xz - (c.me - c.tgt).xz));
        }
    }
    // (the player rides it: what is under them is taken off everything, as though they rose and fell with the land)
    let dropR = clamp(length(c.me.xz - c.tgt.xz) * 0.05, 5.0, 15.0);
    let rip = fw_ripple(r, t) - fw_ripple(length(c.tgt.xz), t) + fw_neck(r, a, t, dropR);
    if (t < FW_TOUCH + 4.3) {
        let pull = fw_pull(r, a, Q.y, t, dropR) / max(r, 0.01);
        Q = vec3<f32>(Q.x * (1.0 - pull), Q.y, Q.z * (1.0 - pull));
    }
    // ---- the land under the player: how much of the sheet's motion it takes ------------------------------------------------
    let mq = c.me - c.tgt;
    let tau = fw_tau(t);
    let stay = fw_stay(c, tau);
    let dist = length(mq.xz);
    let e = select(vec2<f32>(1.0, 0.0), mq.xz / max(dist, 0.001), dist > 0.5);
    var rest = Q + vec3<f32>(0.0, rip, 0.0);
    // (the land pressed along the creases, all but what is underfoot, whether or not it has gone to the sheet yet)
    // (on the sphere only what the pattern covers: the far land has nothing to work out)
    let crease = t > FW_SCORE && t < FW_SLAM4 && (tau < FW_FLAT0 || r < FW_LEN * 1.25);
    var w: CpW;
    var kt: CpKite;
    var tr: CpTri;
    var cell = 5;
    if (crease) {
        w = cp_wedge(a, Q.xz, r);
        cell = cp_cell(w, r);
        if (cell < 5) {
            kt = cp_kite(w, cell);
            tr = cp_tri(kt, (w.u * w.e0 + w.v * w.e1) * r, tau < FW_FLAT0);
        }
    }
    var pr = 1.0;
    var gv = 1.0;
    if (crease && r < FW_LEN * 1.25 && (tau < FW_FLAT0 || cell < 5)) {
        // (on the sphere only the creases' grooves are left)
        let pp = select(cp_press(r, w, t, select(1000.0, tr.e, cell < 5)), vec2<f32>(1.0, 1.0 - 0.9 * (1.0 - fw_ss(1.0, 9.0, tr.e))), tau >= FW_FLAT0);
        // (going back the land is pressed again as the sphere opens, and each ring lets its relief go as it lands)
        var back = 1.0;
        if (t >= FW_REL) {
            let lands = fw_hit(min(cell, 4));
            back = 1.0 - fw_ss(lands - 0.15, lands + 0.1, t);
        }
        let them = back * fw_ss(FW_FEET, FW_FEET + 40.0, length(Q.xz - mix(-c.tgt.xz, mq.xz, fw_held(tau))));
        pr = mix(1.0, pp.x, them * (1.0 - fw_lay(tau)));
        gv = mix(1.0, pp.y, them);
        rest.y = cp_groove(cp_squash(rest.y, cp_level(r), pr), cp_level(r), gv);
    }
    var own = 4;
    for (var i = 3; i >= 0; i -= 1) {
        if (dist < fw_ring(i)) {
            own = i;
        }
    }
    // (under them as they are till the sphere has hold of them, then under where it has them)
    let join = fw_join(tau, own);
    let share = mix(fw_share(Q.xz - mix(-c.tgt.xz, mq.xz, fw_held(tau)), e, dist, select(0.0, fw_ss(24.0, 27.5, tau), t < FW_REL)), 1.0, join);
    if (share <= 0.0) {
        out.pos = c.tgt + rest + stay;
        return out;
    }
    // ---- how far on: the sheet's own heights keep to its surface as it goes up ---------------------------------------------
    // (down from the sphere, and the sheet comes back up under them as their own ring lands)
    let seat = select(fw_ss(FW_FOLD, FW_FOLD + 2.5, tau), 1.0 - fw_ss(fw_hit(own) - FW_FALL, fw_hit(own), t), t >= FW_REL);
    let folded = fw_ss(FW_FOLD - 0.5, FW_FOLD + 6.0, tau) * (1.0 - fw_ss(FW_REL + 1.5, FW_SLAM4 - 0.8, t)) * (1.0 - fw_lay(tau));
    // (what is under the sheet doesn't swing out on a lever: squeezed up to its cut, in order, so that an old crater or a deep
    // pit is still a pit with a floor and walls; then the heights pressed in)
    let cuts = fw_ss(FW_FOLD - 0.5, FW_FOLD, tau) * (1.0 - fw_ss(FW_SLAM4 - 0.3, FW_SLAM4, t));
    var h = Q.y + rip;
    if (t > FW_FLAT && t < FW_SLAM4) {
        h += fw_shock(r, t);
    }
    if (crease) {
        h = cp_groove(cp_squash(h, cp_level(r), pr), cp_level(r), gv);
    }
    if (h < c.cut) {
        h = mix(h, c.cut + 0.15 * (h - c.cut), cuts);
    }
    var soft = select(26.0 * (1.0 - exp(h / 26.0)) * -1.0, 110.0 * (1.0 - exp(-h / 110.0)), h > 0.0);
    // (its relief is pressed out already: left as it is, or what lies under it would be pressed on to it too)
    if (crease) {
        soft = mix(soft, h, fw_ss(FW_LEN * 1.25, FW_LEN, r));
    }
    h = mix(h, soft, folded);
    let pin = cp_pin();
    if (tau < FW_FOLD - 0.01 || t >= FW_SLAM4) {
        var P = vec3<f32>(Q.x, h, Q.z);
        // (flat on the land still: only the folds)
        if (crease && cell < 5) {
            var g: CpR;
            let s = cp_sheet(w, cell, kt, tr, r, h, tau, t, 0.0, pin, g, false);
            P = s.pos;
            out.tint = vec3<f32>(mix(1.0, cp_shade(s.n, tau), share));
        }
        out.pos = c.tgt + mix(rest, P, share);
        return out;
    }
    // ---- the chain: the plates, hinged at the rings, as the far land slides in ---------------------------------------------
    let rb = clamp(dist * 0.56, 60.0, 150.0);
    // (running back the plates stay their own size: drawn in as they stand again, the land under the player's ramp slid further than the ramp is wide)
    let kappa = mix(rb / 153.0, 1.0, select(fw_lay(tau), 1.0, t >= FW_REL));
    // (once it lies on the sphere there is no chain to work out: this is most of the vertices' work, every one of them)
    let lying = tau >= FW_FLAT0;
    var g: CpR;
    if (!lying) {
        g = cp_rings(tau, t, kappa);
    }
    // (lying flat the foot is the sheet's own length)
    let span = select(g.foot, vec2<f32>(FW_LEN, 0.0), lying);
    var s = CpS(vec3<f32>(r * cos(a), h, r * sin(a)), vec3<f32>(0.0, 1.0, 0.0));
    if (lying) {
        if (crease && cell < 5) {
            let l = cp_lying(w, cell, kt, tr, t, pin);
            s.pos.y += l.x;
            s.n = normalize(vec3<f32>(l.y, 1.0, l.z));
            out.tint = vec3<f32>(mix(1.0, cp_shade(s.n, tau), share));
        }
    } else if (crease) {
        s = cp_sheet(w, cell, kt, tr, r, h, tau, t, span.y, pin, g, true);
        out.tint = vec3<f32>(mix(1.0, cp_shade(s.n, tau), share));
    }
    let R = length(s.pos.xz);
    let ca = s.pos.x / max(R, 0.001);
    let sa = s.pos.z / max(R, 0.001);
    // (the sheet sunk from under them, a dish they stand in: nothing comes up through it)
    let sink = FW_SINK * seat * mix(1.0, FW_SINK_END, fw_lay(tau));
    var y = s.pos.y - sink;
    let along = s.pos.xz - e * dist;
    let far_ = length(along);
    let dish = mq.y - 8.0 + max(far_ - 34.0, 0.0) * 0.5;
    if (y > dish && tau > FW_FOLD) {
        y = mix(dish + (y - dish) * mix(1.0, fw_ss(26.0, 116.0, far_), seat), y, join);
    }
    // ---- the sheet on the sphere -----------------------------------------------------------------------------------------
    let reach = clamp(min(globals.fog.y, globals.fog.w), 480.0, 20000.0);
    let edge = max(FW_END_K * reach - dist, 300.0);
    let P = mix(rest, fw_place(R, ca, sa, y, fw_bend(tau + fw_uneven(a, t), t, span.x, mq, e, edge, span.y - sink)), share);
    let bubble = 46.0 - 16.0 * fw_lay(tau);
    out.pos = fw_clear(P + c.tgt + stay, pos + stay, bubble * (1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 1.0, t)));
    return out;
}
// [fragments]
// ---- the creases, as the land's pixels see them ----------------------------------------------------------------------------
// big: blocks to the edge of the nearest crease. hot: how much of the pixel is a crease's bright core, glow its light round it.
struct CpHit { big: f32, hot: f32, glow: f32 }
// How much of a pixel `px` wide a line of half width hw, d off it, covers.
fn cp_cover(d: f32, hw: f32, px: f32) -> f32 {
    return min(hw / px, 1.0) * (1.0 - fw_ss(max(hw - 0.5 * px, 0.0), hw + px, d));
}
// A line's half width s along it, as much of it as has grown by g, to a point at its end.
fn cp_taper(s: f32, g: f32) -> f32 {
    if (s < 0.0 || s >= g) {
        return 0.0;
    }
    return pow(1.0 - s / g, 0.7);
}
const CP_HW: f32 = 0.5;            // a crease's half width at its widest, blocks: one line, one width, every one of them
const CP_LEAD: f32 = 3.0;          // how far its light reaches, blocks
fn cp_line(h: ptr<function, CpHit>, d: f32, fade: f32, px: f32) {
    let hw = CP_HW * fade;
    (*h).big = min((*h).big, d - hw);
    (*h).hot = max((*h).hot, cp_cover(d, hw, px));
    (*h).glow = max((*h).glow, exp(-max(d - hw, 0.0) / CP_LEAD) * fade);
}
// One kind of line: the creases, each as far as it has run, the chords from the crease that got there first. `near`: none close by the player (their own land
// isn't pressed, and a bright line over its trees is a dotted road).
fn cp_lines(r: f32, w: CpW, i: i32, t: f32, px: f32, near: f32) -> CpHit {
    var h = CpHit(1000.0, 0.0, 0.0);
    let p = (w.u * w.e0 + w.v * w.e1) * r;
    for (var j = 0; j < 2; j += 1) {
        let k = select(w.k, w.k1, j == 1);
        let e = select(w.e0, w.e1, j == 1);
        let q = dot(p, e);
        let end = cp_end(k);
        let g = min(fw_score(t - cp_born(k) + FW_SCORE), end);
        if (g > 0.0 && q > 0.0 && q < g) {
            cp_line(&h, abs(cp_x(e, p)), near * fw_ss(1.0, 42.0, q) * cp_taper(q / end, g / end), px);
        }
    }
    for (var n = max(i - 1, 0); n <= min(i, 4); n += 1) {
        let g = fw_ss(0.0, 1.0, (t - cp_chord(w.k, n)) / 1.5);
        if (g > 0.0) {
            let n0 = cp_node(w.k, n);
            let n1 = cp_node(w.k1, n);
            // (from the crease that got to it first)
            let first = CP_AT[w.k * 5 + n] < CP_AT[w.k1 * 5 + n];
            let sg = cp_seg(p, select(n1 * w.e1, n0 * w.e0, first), select(n0 * w.e0, n1 * w.e1, first));
            cp_line(&h, abs(sg.x), near * cp_taper(sg.y, g), px);
        }
    }
    // (the pattern's own lines across the panel, a moment after its chord)
    if (i < 5) {
        let kt = cp_kite(w, i);
        let g = fw_ss(0.0, 1.0, (t - cp_chord(w.k, i) - 0.6) / 1.3);
        if (kt.sp >= 0 && g > 0.0) {
            var cn = array<vec2<f32>, 4>(kt.a, kt.b, kt.c, kt.d);
            for (var j = 0; j < 4; j += 1) {
                if (kt.sp == 2 || (j & 1) == kt.sp) {
                    let s = cp_seg(p, cn[j], kt.v);
                    cp_line(&h, abs(s.x), near * cp_taper(s.y, g), px);
                }
            }
        }
    }
    return h;
}
// ---- the damage on the land's pixels: burnt, cracked ---------------------------------------------------------------------
// soot: how far it has gone to the crater's char. crack: how much of the pixel is a crack's dark. ember: how hot it glows.
struct FwHurt { soot: f32, crack: f32, ember: f32 }
const FW_BURN: f32 = 396.0;        // how far out the bangs burn (strike/fold_land.rs's FD_CHAR)
fn fw_hurt(r: f32, w: CpW, i: i32, d: f32, t: f32, px: f32) -> FwHurt {
    var o = FwHurt(0.0, 0.0, 0.0);
    // ---- the wound: from the touch, out along the creases, each crease its own time, the stain soaking out from them into the panels ------
    let u = t - FW_BEAT;
    let k = select(w.k, w.k1, w.v > w.u);
    let v = max(u - 0.3 * (cp_born(k) - FW_SCORE), 0.0);
    let got = (12.0 + 20.0 * v) * v - r;
    if (got > 0.0) {
        let wide = 2.5 + 40.0 * fw_ss(1.0, 8.7, u);
        o.soot = (1.0 - fw_ss(0.2 * wide, wide, d)) * fw_ss(0.0, 50.0, got) * 0.75;
        o.ember = (1.0 - fw_ss(0.15, 0.7 + px, d)) * exp(-got / 45.0) * fw_ss(FW_LEN, FW_LEN - 40.0, r);
        o.crack = (1.0 - fw_ss(0.4, 1.2 + px, d)) * fw_ss(0.0, 30.0, got) * 0.6;
    }
    // ---- the bangs: each burns its ring, and goes on burning what has landed; cracks run in along the creases from where it landed ----
    let c = min(i, 4);
    let a = t - fw_hit(c);
    let inner = c < 4;
    var burn = 0.46 * fw_step(fw_hit(c), t);
    for (var n = 0; n < c; n += 1) {
        burn += 0.46 / f32(c) * fw_step(fw_hit(n), t);
    }
    // (past the crater the burn goes off to the char's own edge, by the rays)
    if (!inner) {
        burn *= 0.8 * fw_ss(FW_BURN, 300.0, r + 26.0 * sin(atan2(w.v, w.u) * 5.0 + f32(w.k) * 2.1));
    }
    o.soot = max(o.soot, burn);
    if (a > 0.0) {
        let out_ = 1.0 / cp_ix(w, c);
        let run = fw_ss(0.0, 34.0, a * 480.0 - (out_ - r));
        o.crack = max(o.crack, (1.0 - fw_ss(0.5, 1.4 + px, d - 0.5 * fw_ss(0.0, 0.5, a))) * run);
        o.ember = max(o.ember, (1.0 - fw_ss(0.05, 0.6 + px, d)) * run * (0.3 + 0.7 * exp(-a * 1.8)));
    }
    return o;
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
    let ang = atan2(Q.z, Q.x);
    let s2 = slope + (fw_neck(r + e, ang, t, R) - fw_neck(r0, ang, t, R)) / (r + e - r0);
    let Ns = normalize(vec3<f32>(-s2 * D.x, 1.0, -s2 * D.y));
    let nv = max(dot(N, -V), 0.0);
    let turned = nv - max(-V.y, 0.0);
    var col = colIn * (1.0 + FW_SHEEN * 0.9 * day * (dot(Ns, L) - L.y));
    // (a face turned from the eye shows the bright sky low down, one turned to it the deep sky overhead)
    col = mix(col, globals.sky_color.rgb * 1.15, clamp(-turned * 1.3, 0.0, 0.34) * FW_SHEEN * up);
    col = col * (1.0 - clamp(turned * 1.2, 0.0, 0.3) * FW_SHEEN);
    // ---- the droplet's metal spreading from the contact, thin as a film, then taken into the land ----------------------------
    let rf = 1.3 * R + 30.0 * (1.0 - exp(-a / 1.1)) + 2.5 * sin(ang * 5.0 + 1.0) + 1.5 * sin(ang * 11.0 - 2.0);
    // (thick at the foot, thin on past it, gone by the first rebound)
    let foot = exp(-max(r - R * 0.9, 0.0) / (R * 0.9));
    let film = fw_ss(rf, rf - 6.0, r) * fw_ss(0.0, 0.2, a) * (1.0 - fw_ss(6.8, 8.2, t)) * (0.06 + 0.24 * foot) * up;
    if (film > 0.002) {
        let m = reflect(V, N);
        let env = mix(vec3<f32>(0.42, 0.44, 0.48), globals.sky_color.rgb * 1.1, fw_ss(-0.02, 0.5, m.y));
        let glint = pow(max(dot(m, L), 0.0), 120.0) * 3.0 * day;
        col = mix(col, env * (1.0 + 0.3 * pow(1.0 - nv, 3.0)) + vec3<f32>(glint), film);
    }
    return col;
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
    let mq = c.me - c.tgt;
    // ---- the far land's end: a clean circle round the player, the hole's edge ---------------------------------------------------
    let reach = clamp(min(globals.fog.y, globals.fog.w), 480.0, 20000.0);
    if (tau > FW_FOLD && length(Q.xz - mq.xz) > FW_END_K * reach) {
        return drop_;
    }
    // ---- the sheet: nothing under the land is drawn ------------------------------------------------------------------------
    let opened = t > FW_SEAL - 0.5 && r < FW_LAND_R;
    if (t > FW_FOLD - 0.5 && t < FW_SLAM4) {
        // (the backs of the caves' walls, of sealed rooms and of what the far tiles stand on are left out)
        let dim = f.light.x < 5.0;
        if ((dim || (Q.y < c.cut && !opened)) && !f.front) {
            return drop_;
        }
        // (what the sky doesn't reach is dark, no window on the void, and a deep crater open to the sky
        // goes on being a crater)
        if (dim && plain.a > 0.5) {
            let pit = fw_ss(FW_FOLD - 0.5, FW_FOLD + 0.5, t);
            return Painted(vec4<f32>(mix(plain.rgb, vec3<f32>(0.03, 0.027, 0.03), pit), 1.0), 1.0 - pit);
        }
    }
    // ---- what of the land's underside shows ----------------------------------------------------------------------------------
    let gone = fw_ss(FW_FOLD - 0.4, FW_FOLD + 0.2, tau) * (1.0 - fw_ss(FW_SLAM4 - 0.1, FW_SLAM4 + 0.2, t));
    // ---- the crease pattern, its parts in time ---------------------------------------------------------------------------
    let front = fw_score(t);
    let healed = fw_ss(25.5, 28.0, tau);
    // (past the land they are healed, and the pattern's dear: not worked out when there is nothing to show)
    var dc = vec2<f32>(1000.0);
    var hit = CpHit(1000.0, 0.0, 0.0);
    if (plain.a < 0.5 && f.layer < 32768u) {
        // (the leaves' holes: nothing of them is drawn)
        return Painted(plain, 1.0);
    }
    let wedge = cp_wedge(a, Q.xz, r);
    let cell = cp_cell(wedge, r);
    if (front > 0.0 && r < FW_LEN * 1.2) {
        hit = cp_lines(r, wedge, cell, t, max(0.05, dist * 0.00095), fw_ss(FW_FEET + 25.0, FW_FEET + 70.0, length(f.home.xz - c.me.xz)));
        dc = vec2<f32>(hit.big);
    }
    let scored = fw_ss(0.0, 26.0, front - r);
    let fade = 1.0 - fw_ss(FW_FADE, FW_END - 1.5, t);
    // (the block's own texture, tiled smaller and smaller as the land goes)
    var tex = plain;
    let dnear = min(dc.x, dc.y);
    let ring = min(cell, 4);
    let lifting = fw_p(ring, fw_lead(a, ring), tau, t);
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
    // (the land's top faces only, by the face's real normal: plants and leaves have backs too)
    let real_n = cross(dpdx(f.home), dpdy(f.home));
    // (the rim's way down: a far tile is long enough to span the funnel's winding and shows its back, a black shard: only the land's top is drawn there)
    if (tau > 34.4 && real_n.y > 0.5 * length(real_n) && r > FW_RIM0 * max(FW_END_K * reach - length(mq.xz), 300.0)) {
        return drop_;
    }
    // (which side of a top face is seen, by which way round the land's own (x, z) lies on the screen: water is wound the other way, and a
    // far tile's water is opaque)
    if (FW_UNDER > 0.0 && real_n.y > 0.9 * length(real_n) && shown > 0.0 && plain.a > 0.99) {
        let n = fw_hash(floor(Q.xz * 0.5) + floor(Q.y * 0.5));
        let rock = mix(vec3<f32>(0.1, 0.085, 0.08), vec3<f32>(0.24, 0.19, 0.16), n) * (0.6 + 0.4 * fw_ss(40.0, 0.0, Q.y + 30.0));
        col = mix(col, rock, 0.92 * shown);
    }
    // ---- the water's look ------------------------------------------------------------------------------------------------
    if (t > FW_TOUCH + FW_MEET - 0.3 && t < FW_TEAR) {
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
    // ---- the creases ------------------------------------------------------------------------------------------------------
    if (r < FW_LEN * 1.2) {
        // (the lines low on the sphere's walls and as the rings stand and fall; gone as a ring lands, as its land gets its relief back)
        let on = fade * mix(1.0, 0.4, healed) * (1.0 - 0.45 * fw_ss(FW_REL + 1.5, FW_FLAT - 0.8, t)) * (1.0 - fw_ss(fw_hit(ring) - 0.2, fw_hit(ring) + 0.05, t));
        let tone = 0.5 + 0.5 * sin(r * 0.012 - t * 0.2);
        let line = mix(vec3<f32>(1.0, 0.93, 0.82), vec3<f32>(0.86, 0.8, 1.0), tone) * 1.3;
        col = col + line * 0.22 * on * hit.glow;
        // (the line lies on what faces up: a wall that stands on it would be a white slab, a tree's crown a dotted road)
        let core = on * hit.hot * fw_ss(0.5, 0.85, abs(real_n.y) / max(length(real_n), 1.0e-6));
        col = mix(col, line, clamp(core, 0.0, 1.0));
        fog = 1.0 - clamp(core + 0.5 * on * hit.glow, 0.0, 1.0);
    }
    // ---- the damage: from the touch on the land is hurt along its creases, and each bang makes it worse; what is left of it fades off the crater as its panels fall ---
    if (t > FW_BEAT && r < FW_LEN * 1.2 && fade > 0.0) {
        var hurt = fw_hurt(r, wedge, cell, hit.big, t, max(0.05, dist * 0.00095));
        // (the crater comes up out of the soot as it falls; what lay past it clears at once)
        let s = t - FW_SLAM4;
        if (s > 0.0) {
            let go = select(1.0 - fw_ss(0.0, 1.0, s), 1.0 - fw_ss(0.0, 2.0, s - fw_late(wedge, ring)), cell < 4);
            hurt = FwHurt(hurt.soot * go, hurt.crack * go, hurt.ember * go);
        }
        let g = dot(col, vec3<f32>(0.3, 0.5, 0.2));
        let burnt = vec3<f32>(0.075, 0.066, 0.07) + vec3<f32>(0.33, 0.3, 0.3) * g;
        col = mix(col, burnt, clamp(hurt.soot, 0.0, 1.0));
        col = col * (1.0 - 0.92 * clamp(hurt.crack, 0.0, 1.0));
        // (on what faces up, as the lines are)
        let hot = clamp(hurt.ember, 0.0, 1.0) * fw_ss(0.5, 0.85, abs(real_n.y) / max(length(real_n), 1.0e-6));
        // (dull where it has cooled, white-hot only just after a bang; never one flat orange along a crack)
        let along = 0.62 + 0.38 * sin(r * 0.13 + f32(wedge.k) * 2.4 + t * 1.3) * sin(r * 0.041 - f32(wedge.k));
        col = col + mix(vec3<f32>(0.55, 0.1, 0.03), vec3<f32>(1.15, 0.5, 0.14), hot * hot) * hot * along;
        fog = fog * (1.0 - hot);
    }
    // ---- the land overhead goes off in a thin haze: it has to read as land, right up to the torn edge of the hole -----------------
    let awayp = length(Q.xz - mq.xz);
    let dusk = 0.5 * fw_ss(430.0, 900.0, awayp) * fw_ss(30.5, 33.5, tau);
    col = mix(col, vec3<f32>(0.035, 0.05, 0.11), dusk);
    // (the game's fog goes by how far off a thing is drawn, no use on walls: all of it the sphere's own dusk)
    return Painted(vec4<f32>(col, alpha), fog * (1.0 - fw_ss(30.0, 33.0, tau)));
}
