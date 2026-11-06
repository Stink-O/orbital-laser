// The Fold's world warp (the fork's render.set-warp): reality folded like paper, the mandala its crease pattern. Every
// terrain and entity vertex comes through `world_warp`, and every pixel of the terrain through `world_fragment` (after the
// `[fragments]` line) with where it really is, so all of it is anchored to the world and none to the screen. The land is a
// thin sheet: what is under it never moves far and is never drawn (see FRAGMENTS, "the sheet").
//   FW_RIPPLE  rings running out of the target, each bigger than the last
//   FW_SCORE   they sharpen into hairline creases racing over the land: the crease pattern (cp_lines)
//   FW_TEAR    the creases split on the void, painted on the land itself so nothing under it shows
//   FW_FOLD    the land swells up round the target ring by ring, one smooth sheet, nothing over anything: every point of it
//              goes to one place (fw_chain), the horizon rolling up and over behind it (fw_roll)
//   FW_WRAP0   the roll's ring comes in to the target and its tube down to the sphere's size, as the swell lies down onto its
//              floor and the land comes back to its own size: FW_SEAL all but shut, the player inside, the real land on the
//              walls, and a hole left in the roof (FW_HOLE): the land stops at a rim that curls away round it
//   FW_CRUSH   a branch of that same sheet flows down off the rim to the target (fw_spout), in six stages (fw_stage), each
//              smaller and slower
//   FW_BEAT    its tip touches the target. Stillness
//   FW_REL     it all runs backwards (fw_tau), slowly at first: the sphere opens and the bud stands again, every ring up; then
//              ring by ring, outermost first, each falls and bangs down (fw_hit), the last, FW_SLAM4, letting the crater show
// The land under the player is one piece of the sheet: it takes less and less of the sheet's motion the nearer it is to them
// (fw_share), so they stand level on land that bends away from them, no edge to it, till the land is back at its own size and it
// is all the sheet; and from the time the world closes they can't leave it: the sphere, its hole and the branch are one rigid
// frame that goes with them, whatever they do (fw_stay).
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
const FW_SINK: f32 = 16.0;         // how far the sheet sinks from under the player
const FW_FEET: f32 = 15.0;         // how far from the player the land is all their own, no part of the sheet's motion
const FW_EYE: f32 = 1.62;          // their eye over their feet
const FW_LAND_R: f32 = 300.0;      // from FD_LAND on the crater is in the land within this: nothing is cut under it

// ---- what can be taken out: 0 turns each off -----------------------------------------------------------------------
const FW_IRID: f32 = 1.0;          // the iridescence's strength: 1 is about 36 degrees of hue and a quarter more saturation at its peak
const FW_FRACTAL: f32 = 1.0;       // block faces showing smaller copies of themselves
const FW_SPONGE: f32 = 1.0;        // blocks carved into sponges
const FW_PLEATS: f32 = 1.0;        // the radial pleats
const FW_UNDER: f32 = 1.0;         // the sheet's underside painted as rock
const FW_LAY0: f32 = 27.6;         // the bud lies down onto the sphere's floor between these
const FW_LAY1: f32 = 32.6;
const FW_FLAT0: f32 = 34.5;        // from here on the sheet lies on the sphere with nothing left standing on it
const FW_WRAP0: f32 = 27.0;        // the roll's ring comes in to the target, its tube to the sphere's size, from here to FW_SEAL
const FW_SINK_END: f32 = 0.0;      // how much of FW_SINK is left once the sheet lies on the sphere
const FW_HOLE: f32 = 0.6;          // the hole in the roof: radians, round the point across from the target
const FW_DISC: f32 = 130.0;        // how far the branch's land reaches from the target (lib.rs asks for these sections)
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
// Ring i's plate's bearing, radians from the top pole: as it closes, never past upright, so what rises stands over the land
// and nothing over anything; running back, `rt` past FW_REL, the bud stands right up, its last two past upright.
fn fw_phi(i: i32, rt: f32) -> f32 {
    if (rt >= FW_REL) {
        switch i {
            case 0: { return 0.14; }
            case 1: { return 0.48; }
            case 2: { return 0.92; }
            case 3: { return 1.52; }
            default: { return 2.52; }
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
// ---- the crease pattern: origami. Straight lines, nothing wandering: eight big creases out of the target at bearings that fold flat
// (Kawasaki: every other angle round it adds up to 180 degrees), two of them one straight line through it; then, ring by ring, chords
// between them from node to node (cp_rho, straight, so the bends lie on the lines); then in each facet a vein off a big crease, and
// branches off the vein. The sheet zigzags from one big crease to the next, flat facets between them, each big crease a mountain or a
// valley in turn: cp_rise, a height a block out along each. Each kite between two big creases and two chords folds about an apex
// of its own, four straight spokes out to its corners.
// It folds as paper does: the pattern's nodes go somewhere (cp_bear), and every point of the land goes where the three nodes of its
// facet put it (cp_sheet), so that a facet is a flat panel and every bend lies on a drawn line, whatever the nodes do. Each node
// fires as its crease reaches it, big creases first. Nodes keep to their bearing, so a wedge never leaves its sector of the circle
// and no two wedges can meet; along a bearing the sheet is one line going one way: nothing over anything.
const CP_K: f32 = 0.5;             // the big creases' fold: a panel's slope, per radian of cp_rise
const CP_R: f32 = 0.085;           // the chords': each ring's node this much of its radius up, then down, turn about
const CP_V: f32 = 0.16;            // a kite's apex off its panel, of the kite's width
const CP_PRE: f32 = 0.62;          // how far the folds go before the land lifts: all of it by FW_FOLD + 5
const CP_REST: f32 = 0.5;          // how much of them is left in the sphere's walls
fn cp_dir(k: i32) -> vec2<f32> {
    switch k {
        case 0: { return vec2<f32>(1.000000, 0.000000); }
        case 1: { return vec2<f32>(0.788011, 0.615661); }
        case 2: { return vec2<f32>(-0.325568, 0.945519); }
        case 3: { return vec2<f32>(-0.573576, 0.819152); }
        case 4: { return vec2<f32>(-1.000000, 0.000000); }
        case 5: { return vec2<f32>(-0.121869, -0.992546); }
        case 6: { return vec2<f32>(0.325568, -0.945519); }
        default: { return vec2<f32>(0.882948, -0.469472); }
    }
}
// How high a big crease is, a block out: its neighbours' angles apart, up then down, so a zigzag of one slope closes on itself.
fn cp_rise(k: i32) -> f32 {
    switch k {
        case 0: { return 0.131; }
        case 1: { return 0.794; }
        case 2: { return -0.445; }
        case 3: { return -0.166; }
        case 4: { return -1.126; }
        case 5: { return 0.323; }
        case 6: { return -0.131; }
        default: { return 0.620; }
    }
}
// How far out it reaches, to its point.
fn cp_end(k: i32) -> f32 {
    switch k {
        case 0: { return 560.0; }
        case 1: { return 430.0; }
        case 2: { return 545.0; }
        case 3: { return 385.0; }
        case 4: { return 570.0; }
        case 5: { return 450.0; }
        case 6: { return 520.0; }
        default: { return 400.0; }
    }
}
// The pattern's tables, k * 5 + i for ring i on big crease k: one over how far out each ring meets it, and that far out (in and out by turns
// from one crease to the next and from one ring to the next, so the chords run in zigzags, facets like kites, none the same as another: ring
// i's fw_ring, up to 24% either way); when the scoring comes to that node (fw_score's inverse from cp_born) and when its chords do (cp_chord's,
// either side); and four numbers of the kite at wedge k, ring i. Private and constant, as every vertex wants them.
var<private> CP_INV: array<f32, 40> = array<f32, 40>(0.019573, 0.011678, 0.004623, 0.004120, 0.001782, 0.027736, 0.008565, 0.006843, 0.002906, 0.002638, 0.020483, 0.011177, 0.005123, 0.004379, 0.001742, 0.025310, 0.007770, 0.007426, 0.002897, 0.002555, 0.020316, 0.010662, 0.004848, 0.003851, 0.001855, 0.026149, 0.008739, 0.006787, 0.002974, 0.002662, 0.019413, 0.011845, 0.004865, 0.004264, 0.001793, 0.026306, 0.007756, 0.007470, 0.002833, 0.002597);
var<private> CP_Q: array<f32, 40> = array<f32, 40>(51.09, 85.63, 216.31, 242.72, 561.17, 36.05, 116.75, 146.13, 344.12, 379.08, 48.82, 89.47, 195.20, 228.36, 574.05, 39.51, 128.70, 134.66, 345.18, 391.39, 49.22, 93.79, 206.27, 259.67, 539.08, 38.24, 114.43, 147.34, 336.25, 375.66, 51.51, 84.42, 205.55, 234.52, 557.72, 38.01, 128.93, 133.87, 352.98, 385.06);
var<private> CP_AT: array<f32, 40> = array<f32, 40>(13.28, 13.63, 14.52, 14.65, 15.89, 12.97, 13.75, 13.96, 14.99, 15.13, 13.21, 13.62, 14.36, 14.54, 15.89, 12.78, 13.61, 13.65, 14.76, 14.95, 13.94, 14.38, 15.14, 15.42, 16.50, 13.26, 13.99, 14.23, 15.22, 15.38, 14.09, 14.42, 15.26, 15.41, 16.68, 13.23, 14.08, 14.12, 15.27, 15.39);
var<private> CP_CORD: array<f32, 40> = array<f32, 40>(16.64, 16.15, 15.77, 15.40, 14.85, 16.48, 16.09, 15.98, 15.31, 15.09, 16.47, 16.33, 15.47, 14.94, 14.75, 16.79, 16.47, 15.50, 15.03, 14.87, 16.57, 16.59, 15.62, 15.42, 14.92, 16.59, 16.45, 15.72, 15.27, 14.69, 16.62, 16.01, 16.09, 14.84, 14.68, 16.45, 16.07, 15.75, 14.99, 14.55);
var<private> CP_H: array<vec4<f32>, 40> = array<vec4<f32>, 40>(vec4<f32>(0.7871, 0.9337, 0.4569, 0.8698), vec4<f32>(0.9882, 0.5722, 0.8110, 0.8550), vec4<f32>(0.7124, 0.6829, 0.2213, 0.8636), vec4<f32>(0.2846, 0.2659, 0.6005, 0.6233), vec4<f32>(0.7048, 0.3936, 0.5385, 0.2343), vec4<f32>(0.3773, 0.5747, 0.2596, 0.5330), vec4<f32>(0.3728, 0.7326, 0.0184, 0.0967), vec4<f32>(0.4612, 0.3595, 0.9426, 0.7963), vec4<f32>(0.3427, 0.4555, 0.3885, 0.2805), vec4<f32>(0.0175, 0.3002, 0.8398, 0.2267), vec4<f32>(0.5535, 0.7705, 0.9446, 0.9883), vec4<f32>(0.0424, 0.4468, 0.9917, 0.1300), vec4<f32>(0.7927, 0.9143, 0.0683, 0.7475), vec4<f32>(0.3587, 0.1730, 0.7005, 0.2073), vec4<f32>(0.7404, 0.9254, 0.1749, 0.5496), vec4<f32>(0.7635, 0.3448, 0.5099, 0.9395), vec4<f32>(0.8343, 0.7834, 0.5945, 0.9038), vec4<f32>(0.4735, 0.9375, 0.2453, 0.8242), vec4<f32>(0.2007, 0.8072, 0.8073, 0.2075), vec4<f32>(0.0159, 0.0875, 0.6499, 0.1123), vec4<f32>(0.8494, 0.7886, 0.8655, 0.7468), vec4<f32>(0.2928, 0.3381, 0.6910, 0.8977), vec4<f32>(0.8845, 0.6046, 0.3449, 0.5112), vec4<f32>(0.5142, 0.5882, 0.1705, 0.5199), vec4<f32>(0.1819, 0.1683, 0.0917, 0.4446), vec4<f32>(0.7576, 0.4723, 0.1035, 0.9860), vec4<f32>(0.5429, 0.3322, 0.5535, 0.2036), vec4<f32>(0.8287, 0.2220, 0.8490, 0.7318), vec4<f32>(0.5654, 0.1419, 0.0577, 0.8631), vec4<f32>(0.7528, 0.5611, 0.5672, 0.5777), vec4<f32>(0.7531, 0.8493, 0.2238, 0.1454), vec4<f32>(0.7905, 0.0630, 0.1820, 0.1580), vec4<f32>(0.3193, 0.2357, 0.7576, 0.1544), vec4<f32>(0.1764, 0.3675, 0.4691, 0.5609), vec4<f32>(0.3620, 0.8975, 0.0766, 0.9193), vec4<f32>(0.3345, 0.0958, 0.8281, 0.6725), vec4<f32>(0.3229, 0.0119, 0.7974, 0.9960), vec4<f32>(0.3926, 0.8933, 0.8448, 0.5192), vec4<f32>(0.7454, 0.7400, 0.2095, 0.2472), vec4<f32>(0.3814, 0.1526, 0.2195, 0.6228));
// When it sets off.
fn cp_born(k: i32) -> f32 {
    switch k {
        case 0: { return 12.47; }
        case 1: { return 12.34; }
        case 2: { return 12.43; }
        case 3: { return 12.11; }
        case 4: { return 13.15; }
        case 5: { return 12.6; }
        case 6: { return 13.27; }
        default: { return 12.58; }
    }
}
fn cp_x(a: vec2<f32>, b: vec2<f32>) -> f32 {
    return a.x * b.y - a.y * b.x;
}
// The wedge bearing a lies in: big creases k and k1, the unit vector at a as u e0 + v e1, and x[i] one over how far out ring i's
// chord is at a.
struct CpW { k: i32, k1: i32, e0: vec2<f32>, e1: vec2<f32>, u: f32, v: f32, turn: f32 }
fn cp_wedge(a: f32) -> CpW {
    let turn = fract(globals.warp[2].x * 0.618034) * FW_TAU;
    let x = fract((a - turn) / FW_TAU) * 360.0;
    var k = 7;
    if (x < 125.0) {
        k = select(select(2, 1, x < 109.0), 0, x < 38.0);
    } else if (x < 263.0) {
        k = select(4, 3, x < 180.0);
    } else if (x < 332.0) {
        k = select(6, 5, x < 289.0);
    }
    let k1 = (k + 1) % 8;
    let e0 = cp_dir(k);
    let e1 = cp_dir(k1);
    let at = x * 0.017453293;
    let d = vec2<f32>(cos(at), sin(at));
    let det = cp_x(e0, e1);
    return CpW(k, k1, e0, e1, cp_x(d, e1) / det, cp_x(e0, d) / det, turn);
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
// A kite of the pattern: the wedge's cell i, its corners round it, a and b on crease k, c and d on crease k1 (a and d the target in
// cell 0), and v its apex: what its lines and its folds are made of.
struct CpKite { a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>, v: vec2<f32>, m: vec3<f32>, h: vec4<f32>, id: vec2<f32> }
fn cp_kite(w: CpW, i: i32) -> CpKite {
    let id = vec2<f32>(f32(w.k) * 13.0 + 3.0, f32(i) * 7.0 + 1.0);
    let h = CP_H[w.k * 5 + i];
    let in0 = select(0.0, cp_node(w.k, max(i - 1, 0)), i > 0);
    let in1 = select(0.0, cp_node(w.k1, max(i - 1, 0)), i > 0);
    let a = in0 * w.e0;
    let b = cp_node(w.k, i) * w.e0;
    let d = in1 * w.e1;
    let c = cp_node(w.k1, i) * w.e1;
    // (off its middle, each its own way: the kites no two alike)
    let m = vec3<f32>(0.3 + 0.45 * h.x, 0.3 + 0.45 * h.y, 0.32 + 0.36 * h.z);
    return CpKite(a, b, c, d, mix(mix(a, b, m.x), mix(d, c, m.y), m.z), m, h, id);
}
// Which of the kite's four facets p is in, between its corners j and j + 1 and the apex: its weights there, how far it is from the
// nearest of the facet's three lines, blocks.
struct CpTri { j: i32, lv: f32, lx: f32, ly: f32, e: f32 }
fn cp_tri(kt: CpKite, p: vec2<f32>) -> CpTri {
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
    let e = min(min(lx * dd / max(length(y), 0.001), ly * dd / max(length(x), 0.001)), lv * dd / max(length(y - x), 0.001));
    return CpTri(j, lv, lx, ly, e);
}
// One line of the kite: a spoke, from corner a to its apex, or a branch off one.
struct CpLine { a: vec2<f32>, b: vec2<f32>, id: vec2<f32>, h: vec4<f32> }
// Where the land is against a line through a to b: (signed blocks off it, how far along it, 0 to 1, its length).
fn cp_seg(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec3<f32> {
    let e = b - a;
    let l = max(length(e), 0.001);
    let n = e / l;
    return vec3<f32>(cp_x(n, p - a), dot(p - a, n) / l, l);
}
// A crease is a straight line in the world, not one draped over the hills, and a facet is flat: so as the front comes the land's relief
// is pressed out towards one level, CP_FLAT of it everywhere and nearly all of it along any crease, and that last stays in the sphere's walls, a groove the line runs down. `e` how far the nearest fine line is. What is
// left of its height here: (over the land, along the creases). The level is the land's own, how low it lies round the target (params[10],
// strike/fold.rs's fd_level, from the target), brought to the target's height at the target. Only what stands over it is pressed: pressed
// from under, a column's rock would stand up through the lower land beside it.
fn cp_level(r: f32) -> f32 {
    return globals.warp[2].z * min(r / 170.0, 1.0);
}
fn cp_squash(y: f32, level: f32, pr: f32) -> f32 {
    return level + max(y - level, 0.0) * pr + min(y - level, 0.0);
}
const CP_FLAT: f32 = 0.68;
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
    return FW_SCORE + 2.2 + 0.5 * f32(4 - i) + 1.1 * fw_hash(vec2<f32>(f32(k) * 7.0 + 1.0, f32(i) * 13.0 + 8.0));
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
// The player's own kite is left alone, so that nothing rises under them: (its crease, its cell).
fn cp_pin(mq: vec3<f32>) -> vec2<i32> {
    let w = cp_wedge(atan2(mq.z, mq.x));
    return vec2<i32>(w.k, cp_cell(w, length(mq.xz)));
}
// Is ring i's node on big crease k one of the pinned kite's?
fn cp_pinned(k: i32, i: i32, pin: vec2<i32>) -> bool {
    return (k == pin.x || k == (pin.x + 1) % 8) && (i == pin.y || i == pin.y - 1);
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
    var ring = select(-CP_R, CP_R, (i & 1) == 1);
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
        // (the apex: on the kite's own surface, then off it, as the spokes fire and till its ring falls)
        var V = mix(mix(A, B, kt.m.x), mix(D, C, kt.m.y), kt.m.z);
        if (w.k != pin.x || i != pin.y) {
            let up = cross(C - A, B - D);
            let nv = up * select(1.0, -1.0, up.y < 0.0) / max(length(up), 0.001);
            let f = fw_ss(0.0, 1.3, t - (FW_SCORE + 3.2 + 1.3 * kt.h.y)) * select(1.0, g.ps[i], t >= FW_REL && lifts);
            V += nv * select(-CP_V, CP_V, kt.h.x > 0.5) * length(C - B) * f * amount;
        }
        var c = array<vec3<f32>, 4>(A, B, C, D);
        let X = c[tr.j];
        let Y = c[(tr.j + 1) & 3];
        S = V * tr.lv + X * tr.lx + Y * tr.ly;
        let up = cross(Y - V, X - V);
        n = up * select(1.0, -1.0, up.y < 0.0) / max(length(up), 0.001);
        // (what lies under the land goes straight down from the sheet, one way on both sides of a crease: leaning with its facet it would come
        // out through a steep ridge)
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
    let level = cp_level(r);
    let P = S + n * max(hh - level, 0.0) + under * min(hh, level);
    let q = fw_rot(P.xz, w.turn);
    let m2 = fw_rot(n.xz, w.turn);
    return CpS(vec3<f32>(q.x, P.y, q.y), vec3<f32>(m2.x, n.y, m2.y));
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
// ---- the sphere ------------------------------------------------------------------------------------------------------
// How big it ends: the player well inside, whatever their distance and however high they stood over the target.
fn fw_radius(d: f32, y: f32) -> f32 {
    return max(max(d * 1.3, 170.0), y * 1.15);
}
// The fold down from the roof: a branch of land comes over the hole's rim and down to the target, in six stages, each shorter
// and slower than the last, thinner at each. The far land past the rim is no use for it: its tiles are too big and too few to
// be bent that tightly, and go to blades and streaks. So it is the real land round the target, its blocks and trees, drawn five
// more times (`copy`), each time a length of one tube: a disc of land rolled up conformally, its middle at the length's end,
// its edge joined to the end of the one before, a node at each join. It goes along one curve (fw_path), one length after
// another, one radius at any point along it: nothing can cross anything.
fn fw_start(k: i32) -> f32 {
    switch k {
        case 0: { return 35.0; }
        case 1: { return 35.5; }
        case 2: { return 36.1; }
        case 3: { return 36.8; }
        case 4: { return 37.5; }
        case 5: { return 38.2; }
        default: { return FW_HANG; }
    }
}
const FW_TIER_L: f32 = 0.74;       // each stage of the branch this much shorter than the last
// How far on stage k is: quick out of the fold, slow into its place.
fn fw_stage(k: i32, tau: f32) -> f32 {
    let e = clamp((tau - fw_start(k)) / (fw_start(k + 1) - fw_start(k)), 0.0, 1.0);
    return 1.0 - pow(1.0 - e, 2.0);
}
// Where stage k ends along the branch's path, 0 to 1.
fn fw_knot(k: i32) -> f32 {
    return (1.0 - pow(FW_TIER_L, f32(k + 1))) / (1.0 - pow(FW_TIER_L, 6.0));
}
// The stages are done by FW_HANG with the tip FW_SHORT blocks short; it all but stops there, and creeps, and waits, and then in
// the last 0.3 s up to FW_BEAT it closes the rest of it. Nothing of the branch ever goes past this.
const FW_HANG: f32 = 39.0;
const FW_SHORT: f32 = 13.0;
// How many blocks short of the target its tip is, once the stages are done.
fn fw_gap(tau: f32) -> f32 {
    return FW_SHORT - 6.0 * fw_ss(FW_HANG - 0.1, FW_BEAT - 0.3, tau) - 7.0 * pow(clamp((tau - FW_BEAT + 0.3) / 0.3, 0.0, 1.0), 2.0);
}
// How far along its path the very tip has reached by `tau`, 0 to 1: 1 is the target. (4.245 S: the path's blocks to one of x at its end)
fn fw_reached(tau: f32, S: f32) -> f32 {
    var x = 0.0;
    var len = (1.0 - FW_TIER_L) / (1.0 - pow(FW_TIER_L, 6.0));
    for (var k = 0; k < 6; k += 1) {
        x += len * fw_stage(k, tau);
        len *= FW_TIER_L;
    }
    let L = 4.245 * S;
    return (1.0 - FW_SHORT / L) * x + (FW_SHORT - fw_gap(tau)) / L;
}
// How much of the path the rounded end takes up, behind the tip: finer as it arrives.
fn fw_cap(reach: f32) -> f32 {
    return mix(0.02, 0.004, fw_ss(0.95, 1.0, reach));
}
// Its thickness x along, blocks: down a step at each stage's end, a node there, to nothing at the tip.
fn fw_girth(x: f32, S: f32) -> f32 {
    var q = 0.0;
    var node = 0.0;
    for (var k = 1; k < 5; k += 1) {
        let at = fw_knot(k);
        q += fw_ss(at - 0.014, at + 0.014, x);
        let n = (x - at) / 0.016;
        node += exp(-n * n);
    }
    return 0.26 * S * pow(0.84, q) * (1.0 + 0.12 * node) * pow(max(1.0 - x, 0.0), 0.6);
}
// Its middle line x along, in the plane through the axis (out from the axis, up): over the rim and down to the target.
struct FwPath { c: vec2<f32>, n: vec2<f32> }
fn fw_path(x: f32, S: f32, top: f32) -> FwPath {
    // (starting behind the wall, under the rim, so it hooks over the rim's edge, clear of it, as a root does over a stone)
    let p0 = vec2<f32>(1.02 * S, 1.76 * S);
    let p1 = vec2<f32>(0.24 * S, 2.76 * S);
    let p2 = vec2<f32>(0.12 * S, 1.41 * S);
    let p3 = vec2<f32>(0.0, top);
    let m = 1.0 - x;
    let C = p0 * (m * m * m) + p1 * (3.0 * m * m * x) + p2 * (3.0 * m * x * x) + p3 * (x * x * x);
    var T = (p1 - p0) * (m * m) + (p2 - p1) * (2.0 * m * x) + (p3 - p2) * (x * x);
    T = T / max(length(T), 0.001);
    return FwPath(C, vec2<f32>(-T.y, T.x));
}
const FW_THROAT: f32 = 22.0;       // what of a copy's disc rounds off its length's end
// Length k (1 to 5) of the branch: the land of a copy to where it goes.
fn fw_length(k: i32, Q: vec3<f32>, r: f32, a: f32, c: FwClock) -> Warped {
    var out = Warped(c.tgt + vec3<f32>(0.0, -4000.0, 0.0), vec3<f32>(-1.0));
    let tau = fw_tau(c.t);
    let mq = c.me - c.tgt;
    let dist = length(mq.xz);
    let S = fw_radius(dist, mq.y);
    let reach = fw_reached(tau, S);
    let cap = fw_cap(reach);
    let from_ = select(fw_knot(k - 1), 0.0, k == 1);
    // (the length's end, its rounded end past that: the tip itself is `reach`, no further)
    let end = min(max(reach - cap, from_ + 0.0001), fw_knot(k));
    if (reach <= select(from_ + cap, 0.0, k == 1) || r > FW_DISC) {
        return out;
    }
    let e = select(vec2<f32>(1.0, 0.0), mq.xz / max(dist, 0.001), dist > 0.5);
    // (along it by the log of r, as a disc rolled to a tube without stretching goes; inside the throat it rounds off)
    var x = end;
    var rho = 0.0;
    let endr = fw_girth(end, S);
    if (r > FW_THROAT) {
        x = from_ + (end - from_) * log(FW_DISC / r) / log(FW_DISC / FW_THROAT);
        rho = fw_girth(x, S);
    } else {
        let u = r / FW_THROAT;
        rho = endr * u;
        x = min(end + cap * (1.0 - u * u), reach);
    }
    // (the land's own heights, as big as the land is at this place on the tube)
    rho += clamp(Q.y, -6.0, 40.0) * clamp(rho / max(r, FW_THROAT), 0.08, 1.2) * 0.8;
    let P = fw_path(x, S, 0.0);
    // (turning a little as it goes, each length its own way round)
    let phi = -a + f32(k) * 1.9 + x * 2.2;
    let at = atan2(-e.y, -e.x);
    let ca = cos(at);
    let sa = sin(at);
    let c2 = P.c + P.n * (rho * cos(phi));
    let side = rho * sin(phi);
    let bend = fw_bend(FW_BEAT, 0.0, mq, e, 1.0e6, 0.0);
    out.pos = fw_turn(c2.x * ca - side * sa, c2.y, c2.x * sa + side * ca, fw_seat(dist, mq.y), bend) + c.tgt + fw_stay(c, tau);
    out.tint = vec3<f32>(1.0);
    return out;
}
// ---- the roll -----------------------------------------------------------------------------------------------------------
// Past `r0` the sheet rolls up and in over a tube of radius `rc`, up to `fm` round it. As the world closes r0 comes in to
// the target and the tube's radius to the sphere's: a tube whose ring has come down to nothing is a sphere, so it is one
// sheet and one motion from the horizon's first curl to the sphere shut over the player. `w` eases it from the roll's own
// spacing to the stereographic map's, conformal, so that on the sphere the land is only scaled, never stretched.
// The player's feet, and the land under them, are left where they are, level: the whole of it is turned about them.
struct FwBend { tau: f32, d: f32, e: vec2<f32>, edge: f32, top: f32, r0: f32, rc: f32, fm: f32, w: f32, shut: f32, S: f32, pin: f32, rim: f32 }
fn fw_curl(tau: f32) -> f32 {
    return fw_ss(FW_FOLD + 1.0, 29.0, tau);
}
fn fw_bend(tau: f32, foot: f32, mq: vec3<f32>, e: vec2<f32>, edge: f32, top: f32) -> FwBend {
    let d = length(mq.xz);
    let curl = fw_curl(tau);
    let w = fw_ss(FW_WRAP0, FW_SEAL, tau);
    let S = fw_radius(d, mq.y);
    let r0 = (max(foot, d) + 170.0) * (1.0 - fw_ss(FW_WRAP0, FW_SEAL - 0.5, tau));
    return FwBend(tau, d, e, edge, top, r0, mix(mix(3000.0, 700.0, curl), S, w), mix(curl * 3.2, FW_PI, w), w, fw_ss(FW_SEAL - 2.0, FW_SEAL - 0.5, tau), S, mq.y, fw_rim(d));
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
    // (the land brought on to the rim, however far off the real land's edge would have put it, and no further: round its
    // rim it curls away, outwards, so that it ends in a lip and not an edge)
    let th = FW_PI - FW_HOLE;
    let lim = 2.0 * atan(g.rim / (2.0 * g.S));
    f = min(f + g.w * g.shut * (th - lim) * fw_ss(0.45 * g.rim, g.rim, R), mix(3.3, th, g.w * g.shut));
    let lip = 34.0 * g.w * pow(fw_ss(g.rim * 0.8, g.rim, R), 2.0);
    let yy = y * mix(ex, 1.0 / (1.0 + x * x), g.w) - lip;
    let s = sin(f);
    let c = cos(f);
    return vec3<f32>(g.r0 + (g.rc - yy) * s, g.rc * (1.0 - c) + yy * c, f);
}
// Where the sheet goes: R along it from the target at the bearing (ca, sa), y over it. The result is from the target, x and z as the world's.
fn fw_place(R: f32, ca: f32, sa: f32, y: f32, g: FwBend) -> vec3<f32> {
    let on = fw_roll(R, y, g);
    let p = vec3<f32>(on.x * ca, on.y, on.x * sa);
    return fw_turn(p.x, p.y, p.z, fw_roll(g.d, g.pin, g), g);
}
// The land's own end, on the walls, at bearing a: a wandering line round the hole.
fn fw_edge(a: f32, rim: f32) -> f32 {
    return rim * (0.93 + 0.06 * fw_wob(a, 11));
}
// How far out from the target the walls' land goes: the real land's end, near enough.
fn fw_rim(d: f32) -> f32 {
    return max(620.0, d + 480.0);
}
// The player's place on the shut sphere: fw_roll at that place with the world closed, as the branch and its tip have it. With
// fw_turned, what puts the branch's tip on the target: fold.wgsl's fd_seat and fd_turned light the target with the same
// (`the_warp_keeps_the_beats`).
fn fw_seat(d: f32, mh: f32) -> vec3<f32> {
    let S = fw_radius(d, mh);
    let rim = fw_rim(d);
    let x = d / (2.0 * S);
    let th = FW_PI - FW_HOLE;
    let lim = 2.0 * atan(rim / (2.0 * S));
    let f = min(2.0 * atan(x) + (th - lim) * fw_ss(0.45 * rim, rim, d), th);
    let lip = 34.0 * pow(fw_ss(rim * 0.8, rim, d), 2.0);
    let yy = mh / (1.0 + x * x) - lip;
    let s = sin(f);
    let c = cos(f);
    return vec3<f32>((S - yy) * s, S * (1.0 - c) + yy * c, f);
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
// How much of the sheet's motion the land `off` from the player takes, 0 at their feet to 1: nothing under them, more and more
// away from them, and over twice as far behind them as towards the target: the sheet slides towards the target as it closes,
// and the land behind them has that much further to catch it. `e` the way from the target to them, `d` how far.
fn fw_share(off: vec2<f32>, e: vec2<f32>, d: f32) -> f32 {
    let dm = length(off);
    return fw_ss(FW_FEET, clamp(0.95 * d, 90.0, 190.0) * (1.0 + fw_ss(-0.2, 0.6, dot(off, e) / max(dm, 0.001))), dm);
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
        return fw_length(i32(copy), Q, r, a, c);
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
    let crease = t > FW_SCORE && t < FW_SLAM4;
    var w: CpW;
    var kt: CpKite;
    var tr: CpTri;
    var cell = 5;
    if (crease) {
        w = cp_wedge(a);
        cell = cp_cell(w, r);
        if (cell < 5) {
            kt = cp_kite(w, cell);
            tr = cp_tri(kt, (w.u * w.e0 + w.v * w.e1) * r);
        }
    }
    var pr = 1.0;
    if (crease && r < FW_LEN * 1.25) {
        let pp = cp_press(r, w, t, select(1000.0, tr.e, cell < 5));
        // (going back the land is pressed again as the sphere opens, and each ring lets its relief go as it lands)
        var back = 1.0;
        if (t >= FW_REL) {
            let lands = fw_hit(min(cell, 4));
            back = 1.0 - fw_ss(lands - 0.15, lands + 0.1, t);
        }
        let them = back * fw_ss(FW_FEET, FW_FEET + 40.0, length(Q.xz - mix(-c.tgt.xz, mq.xz, fw_held(tau))));
        pr = mix(1.0, pp.x, them * (1.0 - fw_lay(tau))) * mix(1.0, pp.y, them);
        rest.y = cp_squash(rest.y, cp_level(r), pr);
    }
    var own = 4;
    for (var i = 3; i >= 0; i -= 1) {
        if (dist < fw_ring(i)) {
            own = i;
        }
    }
    // (under them as they are till the sphere has hold of them, then under where it has them)
    let join = fw_join(tau, own);
    let share = mix(fw_share(Q.xz - mix(-c.tgt.xz, mq.xz, fw_held(tau)), e, dist), 1.0, join);
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
        h = cp_squash(h, cp_level(r), pr);
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
    let pin = cp_pin(mq);
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
    let kappa = mix(rb / 153.0, 1.0, fw_lay(tau));
    // (once it lies on the sphere there is no chain to work out: this is most of the vertices' work, every one of them)
    let lying = tau >= FW_FLAT0;
    var g: CpR;
    if (!lying) {
        g = cp_rings(tau, t, kappa);
    }
    let span = g.foot;
    var s = CpS(vec3<f32>(r * cos(a), h, r * sin(a)), vec3<f32>(0.0, 1.0, 0.0));
    if (crease && (cell < 5 || !lying)) {
        s = cp_sheet(w, cell, kt, tr, r, h, tau, t, span.y, pin, g, !lying);
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
    let reach = clamp(min(globals.fog.y, globals.fog.w), 480.0, 6000.0);
    let edge = max(reach - dist, 300.0);
    let P = mix(rest, fw_place(R, ca, sa, y, fw_bend(tau, span.x, mq, e, edge, span.y - sink)), share);
    let bubble = 46.0 - 16.0 * fw_lay(tau);
    out.pos = fw_clear(P + c.tgt + stay, pos + stay, bubble * (1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 1.0, t)));
    return out;
}
// [fragments]
// ---- the creases, as the land's pixels see them ----------------------------------------------------------------------------
// big: blocks to the edge of the nearest big crease or chord. hot: how much of the pixel is such a crease's bright core, glow its
// light round it. ink: how much is a fine crease's dark line. tear: blocks to the void's edge, under 0 in it.
struct CpHit { big: f32, hot: f32, glow: f32, ink: f32, tear: f32 }
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
fn cp_lines(r: f32, a: f32, t: f32, px: f32, near: f32, shut: f32) -> CpHit {
    var h = CpHit(1000.0, 0.0, 0.0, 0.0, 1000.0);
    let w = cp_wedge(a);
    let p = (w.u * w.e0 + w.v * w.e1) * r;
    let i = cp_cell(w, r);
    // ---- the two big creases either side -----------------------------------------------------------------------------------
    for (var j = 0; j < 2; j += 1) {
        let k = select(w.k, w.k1, j == 1);
        let e = select(w.e0, w.e1, j == 1);
        let q = dot(p, e);
        let sd = cp_x(e, p);
        let d = abs(sd);
        let end = cp_end(k);
        let g = min(fw_score(t - cp_born(k) + FW_SCORE), end);
        if (g > 0.0 && q > 0.0 && q < g) {
            let hw = 0.8 * fw_ss(1.0, 42.0, q) * cp_taper(q / end, g / end);
            h.big = min(h.big, d - hw);
            h.hot = max(h.hot, cp_cover(d, hw, px));
            h.glow = max(h.glow, exp(-max(d - hw, 0.0) / 3.5) * fw_ss(0.0, 30.0, q) * cp_taper(q / end, g / end));
        }
        // (where it really tears: round some of the nodes, a long thin diamond along it, its edges straight, wider on one side)
        if (d < 26.0 && q > 0.0) {
            for (var n = max(i - 1, 0); n <= min(i, 4); n += 1) {
                let hn = fw_hash(vec2<f32>(f32(k) * 11.0 + 5.0, f32(n) * 6.0 + 3.0));
                if (hn < 0.42) {
                    let q0 = cp_node(k, n);
                    let hm = fract(hn * 17.3);
                    let x0 = q0 * (0.84 - 0.08 * hm);
                    let x1 = q0 * (1.14 + 0.14 * hm);
                    let xm = mix(x0, x1, 0.38 + 0.25 * fract(hn * 41.0));
                    let tri = max(select((x1 - q) / (x1 - xm), (q - x0) / (xm - x0), q < xm), 0.0);
                    let at = FW_TEAR + 3.0 * hm;
                    let opens = fw_ss(at, at + 2.6, t) * (1.0 - fw_ss(FW_FADE + 1.0, FW_END - 2.0, t)) * (1.0 - shut);
                    if (tri * opens > 0.0) {
                        h.tear = min(h.tear, d - select(0.7, 1.0, sd > 0.0) * (2.2 + 0.0085 * q0) * tri * opens);
                    }
                }
            }
        }
    }
    // ---- the chords, node to node ---------------------------------------------------------------------------------------------
    for (var n = max(i - 1, 0); n <= min(i, 4); n += 1) {
        let n0 = cp_node(w.k, n);
        let n1 = cp_node(w.k1, n);
        // (from the crease it stands further out on)
        let P0 = select(n1 * w.e1, n0 * w.e0, n0 > n1);
        let P1 = select(n0 * w.e0, n1 * w.e1, n0 > n1);
        let g = fw_ss(0.0, 1.0, (t - cp_chord(w.k, n)) / 1.5);
        if (g > 0.0) {
            let sg = cp_seg(p, P0, P1);
            let d = abs(sg.x);
            let hw = 0.5 * cp_taper(sg.y, g);
            h.big = min(h.big, d - hw);
            // (none close by the player: their own land isn't pressed, and a thin bright line over its trees is a dotted road)
            h.hot = max(h.hot, 0.6 * near * cp_cover(d, hw, px));
            h.glow = max(h.glow, 0.3 * near * exp(-max(d - hw, 0.0) / 2.0) * cp_taper(sg.y, g));
        }
    }
    // ---- the fine ones: the kite's spokes, from its corners to its apex, a branch off a spoke, a branch off that; each only as far as it
    // has grown, thinner and later than the one it comes off, and each inside its facet, so they never cross ----------------------
    if (i < 5 && shut < 1.0) {
        let kt = cp_kite(w, i);
        let tr = cp_tri(kt, p);
        var cn = array<vec2<f32>, 4>(kt.a, kt.b, kt.c, kt.d);
        let born0 = FW_SCORE + 3.2 + 1.3 * kt.h.y;
        if (t >= born0) {
            let g = fw_ss(0.0, 1.0, (t - born0) / 1.3);
            for (var j = 0; j < 2; j += 1) {
                let s = cp_seg(p, cn[(tr.j + j) & 3], kt.v);
                h.ink = max(h.ink, cp_cover(abs(s.x), 0.46 * cp_taper(s.y, g), px));
            }
            let at = (tr.j + 1) & 3;
            var c = CpLine(cn[tr.j], kt.v, kt.id + vec2<f32>(f32(tr.j) * 3.0, 0.0), kt.h);
            var born = born0 + 0.9 + 0.7 * kt.h.z;
            var w0 = 0.3;
            for (var lev = 0; lev < 2; lev += 1) {
                if (t < born) {
                    break;
                }
                let sg = cp_seg(p, c.a, c.b);
                let side = select(-1.0, 1.0, sg.x > 0.0);
                // (the branch off it, on this facet's side)
                let id = c.id * 1.31 + vec2<f32>(side * 3.1 + f32(lev) * 5.0, side * 1.7 + 9.0);
                let hb = vec4<f32>(fw_hash(id), fw_hash(id + 19.0), fw_hash(id.yx * 1.3 + 3.0), fw_hash(id * 2.1 + 31.0));
                let e = (c.b - c.a) / sg.z;
                let nb = vec2<f32>(-e.y, e.x) * side;
                let from_ = c.a + (c.b - c.a) * (0.2 + 0.55 * hb.x);
                let dir = normalize(e * (0.3 + 0.75 * hb.y) + nb * (0.6 + 0.4 * hb.z));
                c = CpLine(from_, from_ + dir * sg.z * (0.34 + 0.3 * hb.w), id, hb);
                let sb = cp_seg(p, c.a, c.b);
                let gb = fw_ss(0.0, 1.0, (t - born) / 1.3);
                h.ink = max(h.ink, cp_cover(abs(sb.x), w0 * cp_taper(sb.y, gb), px));
                born += 0.9 + 0.7 * hb.x;
                w0 *= 0.65;
            }
        }
    }
    return h;
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
    // ---- the branch: a disc of land round the target, rolled to a length of a tube --------------------------------------------
    if (f.copy > 0u) {
        if (r > FW_DISC || !f.front || plain.a < 0.5) {
            return drop_;
        }
        var col = plain.rgb;
        // (the water isn't copied: what lies under it stands for it)
        if (f.light.x < 6.0) {
            col = vec3<f32>(0.1, 0.2, 0.46);
        }
        // (a dark line at each join, deep in the throat of the length before; and in the dusk where it comes over the rim)
        col = col * mix(0.45, 1.0, fw_ss(FW_DISC, FW_DISC - 16.0, r)) * mix(0.5, 1.0, fw_ss(FW_THROAT, FW_THROAT + 18.0, r));
        if (f.copy == 1u) {
            col = mix(vec3<f32>(0.02, 0.024, 0.06), col, fw_ss(110.0, 52.0, r));
        }
        return Painted(vec4<f32>(col, 1.0), 0.0);
    }
    // ---- the hole in the roof: the walls' land ends in a wandering line --------------------------------------------------------
    let mq = c.me - c.tgt;
    let dmq = length(mq.xz);
    let lands = fw_edge(a, fw_rim(dmq));
    if (r > lands + (1.0 - fw_ss(31.0, 34.5, tau)) * 8000.0) {
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
        // (what the sky doesn't reach is dark, no window on the void: that is the cracks' alone, and a deep crater open to the sky
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
    var hit = CpHit(1000.0, 0.0, 0.0, 0.0, 1000.0);
    if (front > 0.0 && r < FW_LEN * 1.2) {
        hit = cp_lines(r, a, t, max(0.05, dist * 0.00095), fw_ss(FW_FEET + 25.0, FW_FEET + 70.0, length(f.home.xz - c.me.xz)), healed);
        dc = vec2<f32>(hit.big);
    }
    let scored = fw_ss(0.0, 26.0, front - r);
    let fade = 1.0 - fw_ss(FW_FADE, FW_END - 1.5, t);
    // (the block's own texture, tiled smaller and smaller as the land goes)
    var tex = plain;
    let dnear = min(dc.x, dc.y);
    let ring = min(cp_cell(cp_wedge(a), r), 4);
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
    // ---- the sponge: as a petal goes, blocks by the creases eaten away to the void ---------------------------------------
    if (FW_SPONGE > 0.0 && dist < 260.0 && lifting > 0.02) {
        // (only by a tear: the void nowhere else)
        // (and only going up: a ring coming down lands whole)
        let sp = fw_ss(0.02, 0.45, lifting) * (1.0 - fw_ss(0.88, 1.0, lifting)) * (1.0 - fw_ss(6.0, 26.0, hit.tear)) * (1.0 - healed) * select(1.0, 0.0, t >= FW_REL);
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
    // ---- the creases ------------------------------------------------------------------------------------------------------
    if (r < FW_LEN * 1.2) {
        if (hit.tear < 0.0) {
            return Painted(vec4<f32>(fw_stars(normalize(f.at)), 1.0), 0.0);
        }
        let px = max(0.05, dist * 0.00095);
        // (the lines low on the sphere's walls and as the rings stand and fall; gone as a ring lands, as its land gets its relief back)
        let on = fade * mix(1.0, 0.4, healed) * (1.0 - 0.45 * fw_ss(FW_REL + 1.5, FW_FLAT - 0.8, t)) * (1.0 - fw_ss(fw_hit(ring) - 0.2, fw_hit(ring) + 0.05, t));
        // (only a tear has a hot edge, and a thin one; scorch behind it)
        let ember = on * (1.0 - fw_ss(0.0, 0.3 + px * 1.5, hit.tear));
        col = col * (1.0 - 0.7 * on * (1.0 - fw_ss(0.2, 2.2, hit.tear)));
        col = col * (1.0 - 0.85 * on * hit.ink);
        let tone = 0.5 + 0.5 * sin(r * 0.012 - t * 0.2);
        let line = mix(vec3<f32>(1.0, 0.93, 0.82), vec3<f32>(0.86, 0.8, 1.0), tone) * 1.5;
        col = col + line * 0.3 * on * hit.glow;
        col = mix(col, vec3<f32>(1.0, 0.5, 0.2), clamp(ember, 0.0, 1.0));
        col = mix(col, line, clamp(on * hit.hot, 0.0, 1.0));
        fog = 1.0 - clamp(on * hit.hot + ember + 0.5 * on * hit.glow, 0.0, 1.0);
    }
    // ---- past the real land the sphere goes off into its own dusk: the far land's coarse tiles are no use this close, and the
    // darker it gets towards the hole the less there is to see of how it ends ----------------------------------------------------
    let awayp = length(Q.xz - mq.xz);
    let dusk = max(fw_ss(430.0, 640.0, awayp), fw_ss(0.5 * lands, 0.97 * lands, r)) * fw_ss(30.5, 33.5, tau);
    col = mix(col, vec3<f32>(0.02, 0.024, 0.06), dusk * 0.96);
    // (the game's fog goes by how far off a thing is drawn, no use on walls: all of it the sphere's own dusk)
    return Painted(vec4<f32>(col, alpha), fog * (1.0 - fw_ss(30.0, 33.0, tau)));
}
