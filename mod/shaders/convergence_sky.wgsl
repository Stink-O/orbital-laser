// The Convergence's pass, its sky side: the rift and what shows through it, the Aether's column, the light spilling out.
// Appended after shaders/convergence.wgsl's `[cv shared]` block and before its `[cv stages]` (mod/build.rs); reads only
// what that block gives. Reached only through cv_sky_soft and cv_sky_sharp.
// ==== [cv sky] ========================================================================================================
// The sky side.
// - The rift: a torn hole in the plane CV_RIFT_Y over the target, its long axis along the seam, CVS_LIP thick (its torn
//   wall seen between its lower and upper edges). Over the omen a hairline running out along the seam, then straining
//   (its light and crackle building); from the break drawn steadily apart (cvs_part), whole a little before they fire;
//   closing over the aftermath (cv_rift_size). Through it the Aether: a brighter, bluer day sky, three layers of blocky
//   clouds with thickness, and eleven floating islands (traced boxes in three tiers, 40 to 420 blocks over the
//   hole, so they slide against each other as the eye moves), textured with the game's blocks when the table carries
//   their sprites (words CVS_TEX..): mint grass, pale stone (calcite, diorite), sand under them, mint and golden leaf
//   crowns; lit by the Aether's own sun, hazed by distance.
// - What spills out: a thick hollow cone of luminous mist falling from the rim (marched, curtains of light streaming
//   down it), shafts of light slanting down to the land as the hole parts, pale motes on three shells round the column.
// - The column, only under the rift's plane and never wider than its hole: one body, CV_BEAM_R across, whether it
//   hangs out of the hole as a stub (its end flickering), races down (longer each moment, a brighter leading end, its
//   light streaming faster and dragged out behind) or stands pressing down on the meeting point. A white heart in a
//   pale gold-white body with filaments streaming down it, a sheath with turning streaks, a halo cooling to sky blue.
// - In the clash (CvsFight) it is a jet under pressure: its axis a fixed straight line under the rift, its width
//   CV_BEAM_R with a few percent of slow drift. What changes is its flow, heat and light, all from the shared clock's
//   smooth signals: its light streams down faster as the meeting point is driven down and stalls as it is driven up
//   (the stream's phase carries the meeting point's own travel), it burns brighter as it drives and dims as it is
//   driven back, the light piling bright at its foot; a front of brighter light runs down it as each of its shoves
//   starts; its skin roils harder the harder the clash is pressed; its light is thrown on the rift's rim and veils.
//   Over the draw it burns and streams with the speed it drives the meeting point down.
// - The sharp parts are faded by the ground side's smoke in front of them (CvView's veil), leaving a broad glow.
// - Its light on the land: pale gold near the column, sky blue further out, on the Aether's half (the seam's other
//   side), strongest over the draw.
const CVS_SKY_HI: vec3<f32> = vec3<f32>(0.16, 0.50, 1.15);
const CVS_SKY_LO: vec3<f32> = vec3<f32>(0.70, 0.92, 1.12);
const CVS_SUN: vec3<f32> = vec3<f32>(0.42, 0.82, 0.38);
const CVS_MINT: vec3<f32> = vec3<f32>(0.66, 0.97, 0.80);
const CVS_LEAF_MINT: vec3<f32> = vec3<f32>(0.50, 0.86, 0.62);
const CVS_LEAF_GOLD: vec3<f32> = vec3<f32>(1.0, 0.76, 0.22);
// The light the column, its glow and the rift's rim are drawn in (linear): a pale gold-white body, a soft pale gold
// glow, a pearl-white heart, and the clear sky blue of the light's shade.
const CVS_BODY: vec3<f32> = vec3<f32>(1.0, 0.86, 0.60);
const CVS_DEEP: vec3<f32> = vec3<f32>(1.0, 0.80, 0.52);
const CVS_HOT: vec3<f32> = vec3<f32>(1.0, 0.98, 0.95);
const CVS_SHADE: vec3<f32> = vec3<f32>(0.42, 0.60, 1.0);
// The light it throws (spill, shafts, threads, motes, the land): pale gold, a little warmer than the body.
const CVS_GLOW: vec3<f32> = vec3<f32>(1.0, 0.84, 0.58);
// Tuning (the likeliest numbers to change): the window's brightness, the spill's thickness, the land's light.
const CVS_WINDOW_EXPOSURE: f32 = 1.0;
const CVS_SPILL: f32 = 1.0;
const CVS_LAND_LIGHT: f32 = 0.75;
// The tear's thickness: how far over the rift's plane its upper edge lies, blocks.
const CVS_LIP: f32 = 10.0;
// The table's block sprites (strike/convergence.rs's cv_table): word CVS_TEX 1.0 once filled, then the layers (sprite
// array 0) of the top faces of grass_block, calcite, sand, oak_leaves, diorite. Without them the blocks are drawn as
// look-alikes.
const CVS_TEX: u32 = 48u;
const CVS_ISLANDS: i32 = 11;
// The islands the land grows in the sky (real blocks; strike/convergence.rs's cv_islands): word CVS_ISL their count,
// then five words each: dx, dz from the target, the top's height over the target's ground, the radius, when it starts.
const CVS_ISL: u32 = 64u;

@group(0) @binding(8) var block_sprites: texture_2d_array<f32>;
@group(0) @binding(9) var block_sampler: sampler;

// The seam's axis (x along it, y across it, in the world's xz).
fn cvs_axis() -> vec2<f32> {
    let s = cv_seam();
    return vec2<f32>(cos(s), sin(s));
}
// One pixel's angle, radians (the world's picture's).
fn cvs_pxa() -> f32 {
    return 2.0 / (frame.projection[1][1] * frame.resolution.y);
}
// Where the ray meets the rift's plane, from the target (x along the seam, y across it), and how far along the ray
// (1e9: it never does). From below or above alike. cvs_rift_q_at: the same for a plane `dy` over it.
fn cvs_rift_q(v: CvView) -> vec3<f32> {
    return cvs_rift_q_at(v, 0.0);
}
fn cvs_rift_q_at(v: CvView, dy: f32) -> vec3<f32> {
    let h = v.C.y + CV_RIFT_Y + dy;
    let tr = h / select(v.rd.y, 1.0e-6, abs(v.rd.y) < 1.0e-6);
    if (tr <= 0.0) {
        return vec3<f32>(1.0e9, 1.0e9, 1.0e9);
    }
    let p = v.rd * tr - v.C;
    let ax = cvs_axis();
    return vec3<f32>(dot(p.xz, ax), dot(p.xz, vec2<f32>(-ax.y, ax.x)), tr);
}
// The rift drawing in before the columns fire (0-1; let go the moment they fire).
fn cvs_gather(t: f32) -> f32 {
    return smoothstep(CV_CROUCH, CV_FIRE, t) * (1.0 - smoothstep(CV_FIRE, CV_FIRE + 0.05, t));
}
// The flare as they fire: a hit, ringing down.
fn cvs_kick(t: f32) -> f32 {
    let u = t - CV_FIRE;
    return select(0.0, exp(-u / 0.3) * smoothstep(0.0, 0.03, u), u > 0.0);
}
// The impact's recoil reaching back up the gold column to the rift (MEET_Y to RIFT_Y at CVS_RECOIL_V): a hit there too.
const CVS_RECOIL_V: f32 = 480.0;
fn cvs_recoil(t: f32) -> f32 {
    let u = t - CV_MEET - (CV_RIFT_Y - CV_MEET_Y) / CVS_RECOIL_V;
    return select(0.0, exp(-u / 0.35) * smoothstep(0.0, 0.04, u), u > 0.0);
}
// 0 before e0, 1 after e1, eased in and out with no jerk at either end (smootherstep).
fn cvs_ease(t: f32, e0: f32, e1: f32) -> f32 {
    let x = saturate((t - e0) / (e1 - e0));
    return x * x * x * (x * (6.0 * x - 15.0) + 10.0);
}
// ---- the tear ------------------------------------------------------------------------------------------------------
// The rift is not a shape that grows: the sky's own stuff gives way. Every point of the rift's plane has a fixed
// resistance (cvs_resist, blocks, in world space); a front (cvs_tear: a lens along the seam, its half-length and
// half-width, and the strength the sky still has) moves through it, and a point is open while its distance outside the
// front plus its resistance plus that strength is under 0 (cvs_tear_at's `e`). So the hole starts as pockets along the
// hairline where the sky is weakest, they run together into a ragged tear, the tear eats outward faster along the seam,
// tongues and strands of sky hold out where the resistance is high and burn through as the front passes them; every
// bay, tongue and strand is fixed in the world and only uncovered, never scaled.
// The hairline's half-length, the front's half-length and half-width once whole, the strength the sky has as it
// starts to give, and how far over the rift's plane the column's source lies in the Aether, blocks.
const CVS_HAIR: f32 = 68.0;
const CVS_FA: f32 = 70.0;
const CVS_FB: f32 = 49.0;
const CVS_GIVE: f32 = 36.0;
const CVS_SRC: f32 = 520.0;
// The hairline's half-length over the omen: running out along the seam and holding.
fn cvs_hair_len(t: f32) -> f32 {
    return CVS_HAIR * cvs_ease(t, CV_OMEN + 0.3, CV_BREAK - 1.0);
}
// The resistance field's offset for this strike.
fn cvs_o() -> vec2<f32> {
    return vec2<f32>(fract(seed_v() * 0.0731) * 211.0, 5.1);
}
// The sky's resistance at q (the rift's plane, x along the seam, y across it, blocks from the target): x all of it, y
// without its finest octave (for the light round the hole). Large bays and tongues, a warped middle octave, sparse thin
// strands crossing the seam (they hang across the tear after the sky round them has gone), a fine ragged octave; the
// hairline weak in places along its length and the middle weaker.
fn cvs_resist(q: vec2<f32>) -> vec2<f32> {
    let o = cvs_o();
    let wp = vec2<f32>(fvnoise(q * 0.05 + o + vec2<f32>(7.7)), fvnoise(q * 0.05 + o + vec2<f32>(1.3))) - vec2<f32>(0.5);
    let qw = q + 12.0 * wp;
    let big = 14.0 * (fvnoise(q / 30.0 + o) - 0.5);
    let r = 1.0 - abs(2.0 * fvnoise(qw * vec2<f32>(1.0 / 9.0, 1.0 / 17.0) + o * 1.7 + vec2<f32>(3.3)) - 1.0);
    let r2 = r * r;
    let r4 = r2 * r2;
    let shred = 16.0 * r4 * r4 * smoothstep(0.4, 0.7, fvnoise(q / 26.0 + o + vec2<f32>(9.1)));
    let mid = 8.0 * (fvnoise(qw / 11.0 + o * 1.3) - 0.5);
    let fine = 4.0 * (fvnoise(q * 0.25 + o * 2.3) - 0.5);
    let hv = fvnoise(vec2<f32>(q.x / 11.0, 0.5) + o.yx);
    let hair = -(8.0 + 6.0 * hv) * exp(-(q.y / 3.0) * (q.y / 3.0)) * smoothstep(CVS_HAIR + 4.0, CVS_HAIR - 8.0, abs(q.x));
    let cen = -4.0 * exp(-dot(q, q) / 784.0);
    // (where it gives first, at the break: three places along the hairline, each a split drawn out along it, deeper
    // than anything else in the field, so the first one gives right on the break and the others just after it)
    var wl = 0.0;
    for (var i = 0; i < 3; i = i + 1) {
        let px = select(select(-47.0, 31.0, i == 1), -12.0, i == 0);
        let ux = (q.x - px) / 14.0;
        let uy = q.y / 5.0;
        wl = wl + (CVS_GIVE - 1.5 - 1.5 * f32(i)) * exp(-ux * ux - uy * uy);
    }
    let m = saturate(wl / 30.0);
    let sm = (big + shred - 1.0 + hair + cen) * (1.0 - m) + mid - wl;
    return vec2<f32>(sm + fine * (1.0 - 0.7 * m), sm);
}
// The front at t: x its half-length, y its half-width (blocks), z the strength the sky still has (blocks of
// resistance). Before the break nothing gives; from it the strength goes (fast at first, so the first pockets give
// right on the break) while the lens widens, heavily, eased into its whole size by the crouch; held from the impact on
// as cv_rift_size holds it, and over the aftermath shrinking with it while the sky's strength comes back, so the last
// pockets close up.
fn cvs_tear(t: f32) -> vec3<f32> {
    if (t >= CV_MEET) {
        let s = cv_rift_size(t);
        let shut = 1.3 * CVS_GIVE * cv_beat(t, CV_CLOSE + 1.0, CV_END);
        return vec3<f32>(max(s.x * CVS_FA / CV_RIFT_R, 0.3), max(s.y * CVS_FB / (0.75 * CV_RIFT_R), 0.3), shut);
    }
    let L = CVS_HAIR + (CVS_FA - CVS_HAIR) * cvs_ease(t, CV_BREAK + 0.5, CV_CROUCH);
    let W = 0.3 + (CVS_FB - 0.3) * (0.12 * cvs_ease(t, CV_BREAK, CV_BREAK + 2.0) + 0.88 * cvs_ease(t, CV_BREAK + 0.8, CV_CROUCH));
    let x = saturate((t - CV_BREAK) / 2.2);
    return vec3<f32>(L, W, CVS_GIVE * (1.0 - x) * (1.0 - x));
}
// How far q lies outside the front's lens (half-length L, half-width W), blocks (negative inside): the nearer of the
// distance across (right for a thin lens) and the ellipse's gradient estimate (right for a round one).
fn cvs_dbase(q: vec2<f32>, L: f32, W: f32) -> f32 {
    let x = abs(q.x);
    let y = abs(q.y);
    var dv = length(vec2<f32>(max(x - L, 0.0), y));
    if (x < L) {
        dv = y - W * sqrt(max(1.0 - (x / L) * (x / L), 0.0));
    }
    let g = length(vec2<f32>(x / L, y / W));
    let gr = length(vec2<f32>(x / (L * L), y / (W * W))) / max(g, 1.0e-4);
    let dg = (g - 1.0) / max(gr, 1.0e-6);
    return select(min(dv, dg), max(dv, dg), dv < 0.0);
}
// The sky at q for the front T: x how far it is from giving (blocks; under 0 open), y the same without the finest
// octave. Far outside the front the resistance is let go smoothly (it can open nothing there).
fn cvs_e(q: vec2<f32>, T: vec3<f32>) -> vec2<f32> {
    let d = cvs_dbase(q, T.x, T.y) + T.z;
    let w = 1.0 - smoothstep(25.0, 40.0, d - T.z);
    if (w <= 0.0) {
        return vec2<f32>(d + 6.0, d + 6.0);
    }
    let n = cvs_resist(q);
    return vec2<f32>(d + n.x * w + 6.0 * (1.0 - w), d + n.y * w + 6.0 * (1.0 - w));
}
// How far the rift has opened (0 whole sky, 1 the hole whole): its strength gone and its width reached.
fn cvs_part(t: f32) -> f32 {
    if (t < CV_BREAK) {
        return 0.0;
    }
    if (t >= CV_MEET) {
        return 1.0;
    }
    let T = cvs_tear(t);
    return 0.35 * (1.0 - T.z / CVS_GIVE) + 0.65 * (T.y - 0.3) / (CVS_FB - 0.3);
}
// The seam straining before it gives (0-1): its light building over the last seconds of the omen, then easing down to a
// share of it as the hole opens and the light pours out instead.
fn cvs_strain(t: f32) -> f32 {
    return cvs_ease(t, CV_BREAK - 1.8, CV_BREAK) * (1.0 - 0.7 * cvs_ease(t, CV_BREAK + 0.5, CV_BREAK + 4.0));
}
// The rift's extent (half-length, half-width) for what is laid round it (the light cone, the shafts, the glows): the
// hairline over the omen, the front after.
fn cvs_size(t: f32) -> vec2<f32> {
    if (t < CV_BREAK) {
        return vec2<f32>(cvs_hair_len(t), 0.3);
    }
    return cvs_tear(t).xy;
}
// A shoulder on brightness: linear to 0.6, then each channel easing to 1, so the brightest light goes to a clean white
// rather than clipping to a hue.
fn cvs_shoulder(c: vec3<f32>) -> vec3<f32> {
    let k = max(c - vec3<f32>(0.6), vec3<f32>(0.0));
    return min(c, vec3<f32>(0.6)) + 0.4 * (vec3<f32>(1.0) - exp(-k / 0.4));
}
// The gold column's head's speed down, blocks a second (cv_reach's race differentiated).
fn cvs_head_v(t: f32) -> f32 {
    let u = clamp((t - CV_FIRE) / (CV_MEET - CV_FIRE), 0.0, 1.0);
    return (CV_RIFT_Y - CV_MEET_Y - CV_GOLD_LOW) * (CV_SNAP + (1.0 - CV_SNAP) * 2.4 * pow(u, 1.4)) / (CV_MEET - CV_FIRE);
}
// The speed the column's look takes from: the head's while it races, falling away over a moment once it strikes (no
// step at the impact).
fn cvs_speed(t: f32) -> f32 {
    if (t < CV_GOLD0) {
        return max((cvs_colfoot(t - 0.02) - cvs_colfoot(t + 0.02)) / 0.04, 0.0);
    }
    if (t < CV_MEET) {
        return cvs_head_v(t);
    }
    return max(cvs_head_v(CV_MEET) * exp(-(t - CV_MEET) / 0.12), cvs_f.vd);
}
// The light gathering in the column over the crouch, carried through the moment it fires and let go as it races
// (continuous at CV_FIRE).
fn cvs_charge(t: f32) -> f32 {
    if (t < CV_FIRE) {
        return smoothstep(CV_CROUCH, CV_FIRE, t);
    }
    return exp(-(t - CV_FIRE) / 0.35);
}
// ∫ smoothstep(a, b, s) ds from far before a to t.
fn cvs_ramp_int(t: f32, a: f32, b: f32) -> f32 {
    if (t <= a) {
        return 0.0;
    }
    if (t >= b) {
        return t - b + 0.5 * (b - a);
    }
    let x = (t - a) / (b - a);
    return (b - a) * (x * x * x - 0.5 * x * x * x * x);
}

// ---- the clash as the gold side feels it ----------------------------------------------------------------------------
// Its state at t, worked out once a pixel (cv_sky_soft and cv_sky_sharp set cvs_f first), from the shared clock's
// smooth signals only: cv_kick (signed, up for the Nether), cv_flare and the meeting point's travel.
struct CvsFight {
    on: f32,       // the clash under way (0..1)
    dn: f32,       // how hard it is driving the meeting point down (0..~1)
    up: f32,       // how hard it is being driven back up (0..~1)
    tb: f32,       // how turbulent its skin is (0..1)
    drive: f32,    // its stream's phase carried on by the meeting point's travel down (back as it is driven up)
    ph: f32,       // the phase of the light streaming down it (cvs_stream)
    vd: f32,       // how fast it is driving the meeting point down over the draw, blocks a second
}
var<private> cvs_f: CvsFight;
// How far the stream's phase moves per block the meeting point travels (the stream rushes as it is driven down,
// nearly stalls as it is driven up at the hardest shoves' speed), and how fast the front of each of its own shoves
// runs down it from the rift, blocks a second.
const CVS_DRIVE_K: f32 = 0.045;
const CVS_FRONT_V: f32 = 700.0;
fn cvs_fight(t: f32) -> CvsFight {
    var f = CvsFight(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    if (t >= CV_MEET) {
        f.on = smoothstep(CV_MEET, CV_MEET + 0.6, t) * (1.0 - cv_beat(t, CV_HIT - 0.3, CV_HIT));
        // (eased in from 0: the clock's push starts with a slope, the light gathers from none)
        let k = cv_kick(t);
        let dn = max(-k, 0.0);
        let up = max(k, 0.0);
        let fl = cv_flare(t);
        f.dn = 1.3 * dn * dn / (dn + 0.3) * f.on;
        f.up = 1.3 * up * up / (up + 0.3) * f.on;
        f.tb = saturate(0.35 * f.on + 0.6 * fl * fl / (fl + 0.3) * f.on);
        let ym = cv_meet_y(t);
        f.drive = CVS_DRIVE_K * (CV_MEET_Y - ym);
        // (the draw: from CV_DRAW it drives the meeting point all the way down, gathering speed; its weight is its
        // speed, so it burns and streams harder the faster the point goes down, to the blast)
        if (t > CV_DRAW) {
            f.vd = max((ym - cv_meet_y(t + 0.04)) / 0.04, 0.0);
            let w = saturate(f.vd / 90.0) * (1.0 - cv_beat(t, CV_HIT - 0.3, CV_HIT));
            f.dn = max(f.dn, 1.15 * w);
            f.tb = max(f.tb, 0.5 + 0.5 * w);
        }
    }
    f.ph = cvs_stream(t, f.drive);
    return f;
}
// Extra light along the column at height y (over the target's ground; its foot at `foot`): a front running down it
// from the rift as each of its own shoves starts (bright ahead, dragged out behind, given into its foot as it gets
// there), and the impact's recoil running up it from the meeting point.
fn cvs_front(t: f32, y: f32, foot: f32) -> f32 {
    var l = 0.0;
    let ui = t - CV_MEET;
    if (ui > 0.0 && ui < 1.0) {
        let yr = CV_MEET_Y + CVS_RECOIL_V * ui;
        l = l + 1.1 * exp(-pow((y - yr) / 12.0, 2.0)) * exp(-ui / 0.8) * smoothstep(CV_RIFT_Y + 90.0, CV_RIFT_Y + 20.0, yr);
    }
    let n = 3 + i32(frame.resolution.x < 0.0);
    for (var j = 0; j < n; j = j + 1) {
        let i = 2 * j + 1;
        let u = t - cv_surge(i);
        if (u < 0.0 || u > 1.0) {
            continue;
        }
        let a = cv_surge_amp(i) / 40.0;
        let ys = CV_RIFT_Y + 120.0 - CVS_FRONT_V * u;
        let dy = y - ys;
        let shape = select(exp(-dy / (30.0 + 60.0 * u)), exp(-(dy / 9.0) * (dy / 9.0)), dy < 0.0);
        l = l + 1.2 * a * shape * smoothstep(0.0, 0.07, u) * smoothstep(foot - 8.0, foot + 25.0, ys);
    }
    return l;
}
// The column's core radius at s blocks over its foot and height y: CV_BEAM_R whether it hangs, races or stands, a few
// percent of slow drift in the clash; never wider than the hole near the plane; over it narrowing into its source far
// up in the Aether.
fn cvs_beam_r_at(t: f32, s: f32, sz: vec2<f32>, y: f32) -> f32 {
    let drift = 1.0 + 0.05 * cvs_f.on * (fvnoise(vec2<f32>(s * 0.015 - t * 0.3, t * 0.2 + 4.0)) - 0.5);
    let h = max(y - CV_RIFT_Y, 0.0);
    let lim = 0.55 * sz.y + 0.3 + 40.0 * smoothstep(0.0, 60.0, h);
    return min(CV_BEAM_R * drift * (1.0 - 0.6 * smoothstep(0.0, CVS_SRC, h)), lim);
}
// The column's brightness at s blocks over its foot, L long, at height y (its front there adding `lb`): one level
// whether it hangs, races or stands, the light gathered over the crouch carried into the launch; a brighter leading end
// with light dragged out behind it as it races; in the clash brighter as it drives, dimmer as it is driven back with
// the light piling at its foot, and slow blotches of heat carried down on its stream.
// The clash's push as the column carries it, s blocks over its foot (x driving down, y driven back): its own shove
// comes down it from the rift (seen higher up before it lands on the meeting point), a blow from the fire runs up it
// from the meeting point; the draw's weight is the whole column's. Never the whole column at once.
const CVS_PULSE_V: f32 = 300.0;
fn cvs_fight_at(t: f32, s: f32) -> vec2<f32> {
    let F = cvs_f;
    if (F.on <= 0.0) {
        return vec2<f32>(F.dn, F.up);
    }
    let d = max(s, 0.0) / CVS_PULSE_V;
    let kd = max(-cv_kick(t + d), 0.0);
    let ku = max(cv_kick(t - d), 0.0);
    let w = saturate(F.vd / 90.0) * (1.0 - cv_beat(t, CV_HIT - 0.3, CV_HIT));
    return vec2<f32>(max(1.3 * kd * kd / (kd + 0.3) * F.on, 1.15 * w), 1.3 * ku * ku / (ku + 0.3) * F.on);
}
fn cvs_beam_i(t: f32, s: f32, L: f32, lb: f32, R: f32, y: f32) -> f32 {
    let F = cvs_f;
    let fa = cvs_fight_at(t, s);
    let vs = cvs_speed(t);
    let lead = 1.4 * saturate(vs / 600.0) * exp(-max(s, 0.0) / (1.4 * R + 0.075 * vs));
    let pile = exp(-max(s, 0.0) / 22.0);
    let fight = 1.0 + 0.55 * fa.x + fa.y * (0.9 * pile - 0.3) + 0.25 * fa.x * pile;
    let heat = 1.0 + F.on * 0.32 * (fvnoise(vec2<f32>(y * 0.018 + F.ph * 0.5, t * 0.3 + 2.0)) - 0.5);
    return (1.0 + 0.5 * cvs_charge(t)) * (fight + lb + lead) * heat;
}
// The gold column's foot as drawn: cv_gold_foot, the stub's tip flickering while it hangs (still by the time it fires).
fn cvs_foot(t: f32) -> f32 {
    let alive = 1.0 - smoothstep(CV_CROUCH, CV_FIRE, t);
    return cv_gold_foot(t) - 3.0 * (fvnoise(vec2<f32>(t * 1.7, 5.3)) - 0.5) * alive * cv_beat(t, CV_GOLD0, CV_GOLD0 + 1.5);
}
// The ray against the gold column's axis (over the target, heights ya..yb over its ground), under the rift's plane and
// over it alike (what is over it is seen only through the hole: cvs_seen_at). x the distance, y how far along the ray,
// z the height of the axis's nearest point.
fn cvs_axis_d(v: CvView, ya: f32, yb: f32) -> vec3<f32> {
    let h = v.rd.xz;
    let hh = max(dot(h, h), 1.0e-6);
    let th = max(dot(v.C.xz, h) / hh, 0.0);
    var y = clamp(v.rd.y * th - v.C.y, ya, yb);
    var P = vec3<f32>(v.C.x, v.C.y + y, v.C.z);
    var tr = max(dot(P, v.rd), 0.0);
    y = clamp(v.rd.y * tr - v.C.y, ya, yb);
    P = vec3<f32>(v.C.x, v.C.y + y, v.C.z);
    tr = max(dot(P, v.rd), 0.0);
    return vec3<f32>(length(v.rd * tr - P), tr, y);
}
// How much of a sharp part shows through the ground side's smoke: the smoke lies low, so only rays climbing to the
// part pass through it first; seen from above, the part is in front of it.
fn cvs_veiled(v: CvView) -> f32 {
    return mix(1.0, v.veil, smoothstep(-0.05, 0.05, v.rd.y));
}

// The tear seen along the ray where it crosses a plane `dy` over the rift's: e how far the sky there is from giving
// (blocks, under 0 open), es without the finest octave, pf one pixel's width there (blocks; `px` pixels), z the ray's
// distance to the plane (1e9: it never crosses it), q the point, v how fast the front moves there (blocks a second,
// either way).
struct CvsTearAt {
    e: f32,
    es: f32,
    pf: f32,
    z: f32,
    q: vec2<f32>,
    v: f32,
}
fn cvs_tear_at(v: CvView, dy: f32, px: f32) -> CvsTearAt {
    let q = cvs_rift_q_at(v, dy);
    if (q.z > 1.0e8) {
        return CvsTearAt(1.0e9, 1.0e9, 1.0, 1.0e9, vec2<f32>(0.0), 0.0);
    }
    let T = cvs_tear(v.t);
    let T0 = cvs_tear(v.t - 0.2);
    let e = cvs_e(q.xy, T);
    let sp = (cvs_dbase(q.xy, T0.x, T0.y) + T0.z - cvs_dbase(q.xy, T.x, T.y) - T.z) / 0.2;
    let pf = q.z * cvs_pxa() * px / max(abs(v.rd.y), 0.05);
    return CvsTearAt(e.x, e.y, pf, q.z, q.xy, sp);
}
// What of the things over the rift's plane this pixel's ray sees through the hole (0-1): set by cv_sky_soft and
// cv_sky_sharp before the column is drawn.
var<private> cvs_vh: f32 = 0.0;
// The column's strength over the plane, inside the Aether, for what it lights there (set by cv_sky_soft).
var<private> cvs_upl: f32 = 0.0;

// ---- the Aether through the hole --------------------------------------------------------------------------------
// The Aether's sky in direction rd: always day, brighter and bluer than the world's, white toward its own horizon, a
// warm glow round its sun.
fn cvs_aether_sky(rd: vec3<f32>) -> vec3<f32> {
    let up = saturate(rd.y);
    var c = mix(CVS_SKY_LO, CVS_SKY_HI, pow(up, 0.7));
    let s = max(dot(rd, normalize(CVS_SUN)), 0.0);
    c = c + vec3<f32>(1.0, 0.9, 0.6) * (0.25 * pow(s, 6.0) + 0.9 * pow(s, 200.0));
    return c * CVS_WINDOW_EXPOSURE;
}
// Island i: x, z its middle from the target (world axes), y how far over the rift's plane its top is, w its radius.
// Three tiers: near (over the hole), middle and far (out where the eye looks through from any side, ~0.9 of their
// height out).
fn cvs_island(i: i32) -> vec4<f32> {
    let fi = f32(i);
    var h = 0.0;
    var R = 0.0;
    var out = 0.0;
    if (i < 3) {
        h = 42.0 + 14.0 * fi;
        R = 12.0 + 8.0 * fract(fi * 0.618 + 0.3);
        out = 18.0 + 30.0 * fract(fi * 0.618);
    } else if (i < 7) {
        h = 120.0 + 25.0 * (fi - 3.0);
        R = 22.0 + 10.0 * fract(fi * 0.618);
        out = h * (0.55 + 0.5 * fract(fi * 0.381));
    } else {
        h = 280.0 + 45.0 * (fi - 7.0);
        R = 40.0 + 18.0 * fract(fi * 0.618);
        out = h * (0.5 + 0.55 * fract(fi * 0.381 + 0.2));
    }
    // (none on the column's axis: it runs up through them into its source)
    out = max(out, R + 30.0);
    let a = fi * 2.39996 + seed_v() * 0.61;
    return vec4<f32>(cos(a) * out, h, sin(a) * out, R);
}
// Layer k of island i (radius R, depth D): x, y its offset from the island's middle, z its thickness, w how far under
// the island's top its own top is (0 the grass slab, 3 thick; 1-3 the body, narrowing, each a third of D).
fn cvs_layer(i: i32, k: i32, R: f32, D: f32) -> vec4<f32> {
    let jit = vec2<f32>(fract(f32(i) * 0.731) - 0.5, fract(f32(i) * 0.413) - 0.5);
    let fk = f32(k);
    let off = floor(jit * R * 0.14 * fk);
    if (k == 0) {
        return vec4<f32>(0.0, 0.0, 3.0, 0.0);
    }
    let a = 3.0 + floor(D * 0.34 * (fk - 1.0));
    let b = 3.0 + floor(D * 0.34 * fk);
    return vec4<f32>(off, b - a, a);
}
// One box (middle c, half size b, camera-relative) against the ray: where it goes in and out (in > out: a miss).
fn cvs_box(ird: vec3<f32>, c: vec3<f32>, b: vec3<f32>) -> vec2<f32> {
    let t1 = (c - b) * ird;
    let t2 = (c + b) * ird;
    let lo = min(t1, t2);
    let hi = max(t1, t2);
    return vec2<f32>(max(max(lo.x, lo.y), lo.z), min(min(hi.x, hi.y), hi.z));
}
// A traced island's hit: how far, the box it hit (middle and half size), which part (0 the grass slab, 1-3 the
// hanging body, 4 a crown), which island (-1: none).
struct CvsHit {
    t: f32,
    c: vec3<f32>,
    b: vec3<f32>,
    part: i32,
    isl: i32,
}
// The islands against the ray: each a grass slab, three narrowing layers hanging under it (each two crossed boxes, so
// its outline steps like a round island's) and one crown overhanging its edge; whole blocks, on the block grid.
fn cvs_trace(v: CvView, tmin: f32) -> CvsHit {
    var best = CvsHit(1.0e9, vec3<f32>(0.0), vec3<f32>(1.0), 0, -1);
    let ird = 1.0 / select(v.rd, sign(v.rd) * 1.0e-6 + vec3<f32>(1.0e-7), abs(v.rd) < vec3<f32>(1.0e-6));
    let base = v.C + vec3<f32>(0.0, CV_RIFT_Y, 0.0);
    for (var i = 0; i < CVS_ISLANDS; i = i + 1) {
        let I = cvs_island(i);
        let R = floor(I.w);
        let D = floor(0.9 * R);
        let top = base.y + floor(I.y + 1.5 * sin(v.t * 0.25 + f32(i) * 1.7));
        // (on the block grid the textures are laid on: whole blocks from the target)
        let mid = vec3<f32>(v.C.x + floor(I.x), 0.0, v.C.z + floor(I.z));
        // (its bounds, crown included)
        let bb = cvs_box(ird, vec3<f32>(mid.x, top - 0.5 * D, mid.z), vec3<f32>(R + 5.0, 0.5 * D + 9.0, R + 5.0));
        if (bb.x > bb.y || bb.y < tmin || bb.x > best.t) {
            continue;
        }
        for (var k = 0; k < 4; k = k + 1) {
            let lay = cvs_layer(i, k, R, D);
            let cc = vec3<f32>(mid.x + lay.x, top - lay.w - 0.5 * lay.z, mid.z + lay.y);
            let hy = 0.5 * lay.z;
            let r = floor(R * select(0.86 - 0.22 * f32(k), 1.0, k == 0));
            for (var m = 0; m < 2; m = m + 1) {
                let hb = select(vec3<f32>(floor(0.62 * r), hy, r), vec3<f32>(r, hy, floor(0.62 * r)), m == 0);
                let h = cvs_box(ird, cc, hb);
                if (h.x <= h.y && h.x > tmin && h.x < best.t) {
                    best = CvsHit(h.x, cc, hb, k, i);
                }
            }
        }
        // (a crown at the edge: mint or golden leaves)
        let ca = f32(i) * 1.3 + 0.4;
        let cc = vec3<f32>(mid.x + floor(cos(ca) * (R - 2.0)), top + 4.5, mid.z + floor(sin(ca) * (R - 2.0)));
        let h = cvs_box(ird, cc, vec3<f32>(3.0, 2.5, 3.0));
        if (h.x <= h.y && h.x > tmin && h.x < best.t) {
            best = CvsHit(h.x, cc, vec3<f32>(3.0, 2.5, 3.0), 4, i);
        }
    }
    return best;
}
// A block's texture: sprite `k` of the table (0 grass top, 1 calcite, 2 sand, 3 oak leaves, 4 diorite) at uv, at
// mip level lod, linear, with its alpha; a look-alike (its average and a 16 by 16 grain) when the table carries none.
fn cvs_tex(k: u32, uv: vec2<f32>, cell: vec3<f32>, lod: f32) -> vec4<f32> {
    if (abs(cv_w(CVS_TEX) - 1.0) < 1.0e-3) {
        let layer = i32(bitcast<u32>(cv_w(CVS_TEX + 1u + k)));
        let lv = clamp(lod, 0.0, f32(textureNumLevels(block_sprites) - 1));
        let s = textureSampleLevel(block_sprites, block_sampler, fract(uv), layer, lv);
        return vec4<f32>(srgb_to_linear(s.rgb), s.a);
    }
    var avg = vec3<f32>(0.62, 0.62, 0.62);
    if (k == 1u) {
        avg = vec3<f32>(0.86, 0.87, 0.84);
    } else if (k == 2u) {
        avg = vec3<f32>(0.86, 0.80, 0.60);
    } else if (k == 3u) {
        avg = vec3<f32>(0.55, 0.55, 0.55);
    } else if (k == 4u) {
        avg = vec3<f32>(0.74, 0.74, 0.75);
    }
    let g = fh31(vec3<f32>(floor(fract(uv) * 16.0), cell.x * 7.0 + cell.y * 13.0 + cell.z));
    let grain = select(0.10, 0.22, k == 4u || k == 3u);
    return vec4<f32>(srgb_to_linear(avg * (1.0 - grain + 2.0 * grain * g)), select(1.0, step(0.25, g), k == 3u));
}
// The colour of the island's block face hit (camera-relative), lit by the Aether's sun, hazed by distance past the
// hole at tplane.
fn cvs_island_col(v: CvView, h: CvsHit, tplane: f32) -> vec3<f32> {
    let P = v.rd * h.t;
    let lp = (P - h.c) / h.b;
    let a = abs(lp);
    var n = vec3<f32>(0.0, sign(lp.y), 0.0);
    if (a.x >= a.y && a.x >= a.z) {
        n = vec3<f32>(sign(lp.x), 0.0, 0.0);
    } else if (a.z >= a.y) {
        n = vec3<f32>(0.0, 0.0, sign(lp.z));
    }
    let L = P - v.C - n * 0.01;
    let cell = floor(L);
    let uvw = fract(L);
    var uv = vec2<f32>(uvw.x, uvw.z);
    if (abs(n.x) > 0.5) {
        uv = vec2<f32>(uvw.z, 1.0 - uvw.y);
    } else if (abs(n.z) > 0.5) {
        uv = vec2<f32>(uvw.x, 1.0 - uvw.y);
    }
    // (a texel's footprint: the half-size stage's pixels are two across)
    let lod = log2(max(h.t * cvs_pxa() * 2.0 * 16.0 / max(abs(dot(n, v.rd)), 0.25), 1.0));
    let hb = fh31(cell + vec3<f32>(f32(h.isl) * 31.0));
    var alb = vec3<f32>(0.0);
    var glow = 0.0;
    let top_band = h.part == 0 && abs(n.y) < 0.5 && (h.c.y + h.b.y - P.y) < 1.0 && uv.y < 0.3;
    if (h.part == 4) {
        // (leaves: the cut-out's holes show the crown's shaded inside)
        let lt = cvs_tex(3u, uv, cell, lod);
        let tint = select(CVS_LEAF_MINT, CVS_LEAF_GOLD, (h.isl & 1) == 1);
        alb = lt.rgb * tint * select(0.45, 1.0, lt.a > 0.5);
    } else if ((h.part == 0 && n.y > 0.5) || top_band) {
        // (the Aether's pale mint grass, on the top and as a band down the slab's sides)
        alb = cvs_tex(0u, select(uv, uvw.xz, n.y > 0.5), cell, lod).rgb * CVS_MINT;
    } else {
        // (pale stone, with sand the more toward the bottom, and the odd block of glowing yellow)
        let deep = f32(h.part) / 3.0;
        let quick = hb > 1.0 - (0.18 + 0.5 * deep) || (n.y < -0.5 && h.part == 3 && hb > 0.25);
        let k = select(select(1u, 4u, hb < 0.3), 2u, quick);
        alb = cvs_tex(k, uv, cell, lod).rgb;
        if (k != 2u && fh31(cell * 1.7 + vec3<f32>(5.0)) < 0.03) {
            glow = select(0.0, 1.0, fh21(floor(uv * 16.0) + cell.xz * 3.0) > 0.72);
        }
    }
    // (lit: the Aether's sun, the game's face shading, a bright bounce from the cloud sea below)
    let face = select(select(0.8, 0.6, abs(n.x) > 0.5), select(0.5, 1.0, n.y > 0.5), abs(n.y) > 0.5);
    let sun = max(dot(n, normalize(CVS_SUN)), 0.0);
    let amb = vec3<f32>(0.55, 0.68, 0.85) * face + vec3<f32>(0.32, 0.33, 0.35) * select(0.0, 1.0, n.y < -0.5);
    // (contact shade: under an overhang, darker toward the layer hanging below it; on a side, toward the overhang over it)
    var ao = 1.0;
    let I = cvs_island(h.isl);
    let R = floor(I.w);
    let D = floor(0.9 * R);
    let mid = vec2<f32>(v.C.x + floor(I.x), v.C.z + floor(I.z));
    if (n.y < -0.5 && h.part < 3) {
        let nl = cvs_layer(h.isl, h.part + 1, R, D);
        let r = floor(R * (0.86 - 0.22 * f32(h.part + 1)));
        let d2 = abs(P.xz - (mid + nl.xy));
        let da = max(d2 - vec2<f32>(floor(0.62 * r), r), vec2<f32>(0.0));
        let db = max(d2 - vec2<f32>(r, floor(0.62 * r)), vec2<f32>(0.0));
        let d = min(length(da), length(db));
        ao = 1.0 - 0.5 * exp(-d / 3.0);
    } else if (abs(n.y) < 0.5 && h.part > 0) {
        ao = 1.0 - 0.35 * exp(-(h.c.y + h.b.y - P.y) / 2.0);
    }
    var c = alb * (amb + vec3<f32>(1.0, 0.94, 0.82) * sun * 0.75) * ao + vec3<f32>(1.0, 0.85, 0.35) * glow * 1.4;
    // (the column's light on its near sides: it stands among them; their shade away from it)
    let tc = v.C.xz - P.xz;
    let dc = max(length(tc), 1.0);
    let lc = max(dot(n, vec3<f32>(tc.x / dc, 0.0, tc.y / dc)), 0.0);
    c = c + alb * CVS_GLOW * (lc * 1.8 + 0.15) * cvs_upl / (1.0 + (dc / 55.0) * (dc / 55.0));
    c = c * CVS_WINDOW_EXPOSURE;
    let far = 1.0 - exp(-max(h.t - tplane, 0.0) / 650.0);
    return mix(c, cvs_aether_sky(v.rd), far * 0.85);
}
// A cloud layer's height over the rift's plane (0 cold white just over the hole, 1 blue, 2 golden high up).
fn cvs_cloud_h(k: i32) -> f32 {
    return select(select(330.0, 175.0, k == 1), 55.0, k == 0);
}
// The clouds in the Aether: layers of blocky cloud with thickness (boxes 12 across, CVS_CLOUD_T deep), each drifting
// its own way; at the ray's crossing of layer k's underside, its colour and how much cloud (0-1). Seen from under: a
// box's underside in its own cool shade, or, where the ray goes in through a box's side, that side lit by the Aether's
// sun by the way it faces.
fn cvs_skycloud(v: CvView, k: i32, tk: f32) -> vec4<f32> {
    let fk = f32(k);
    let T = select(9.0, 5.0, k == 0);
    let drift = vec2<f32>(v.t * (1.2 + 0.5 * fk), v.t * (0.4 - 0.3 * fk)) + vec2<f32>(fk * 300.0);
    let tk2 = tk + T / max(v.rd.y, 1.0e-3);
    let cb = floor(((v.rd * tk - v.C).xz + drift) / 12.0);
    let ct = floor(((v.rd * tk2 - v.C).xz + drift) / 12.0);
    let th = select(0.6, 0.74, k == 0);
    let off = vec2<f32>(fk * 17.0, seed_v());
    let mb = fvnoise(cb * 0.33 + off) >= th;
    let mt = fvnoise(ct * 0.33 + off) >= th;
    let tint = select(select(vec3<f32>(1.0, 0.93, 0.80), vec3<f32>(0.78, 0.88, 1.05), k == 1), vec3<f32>(1.0, 1.0, 1.02), k == 0);
    var c = vec3<f32>(0.0);
    if (mb) {
        c = mix(tint, CVS_SHADE, 0.25) * (0.58 + 0.08 * fh21(cb));
    } else if (mt) {
        let dc = abs(ct - cb);
        let n = select(vec3<f32>(0.0, 0.0, -sign(v.rd.z)), vec3<f32>(-sign(v.rd.x), 0.0, 0.0), dc.x > 0.5);
        c = tint * (0.74 + 0.36 * max(dot(n, normalize(CVS_SUN)), 0.0));
    }
    // (a clearing round the column's axis, its edges lit by it)
    let rr = length((v.rd * tk - v.C).xz);
    let clear = smoothstep(22.0 + 0.04 * cvs_cloud_h(k), 36.0 + 0.04 * cvs_cloud_h(k), rr);
    c = c + CVS_GLOW * 0.6 * exp(-rr / 45.0) * cvs_upl;
    let m = select(0.0, 1.0, mb || mt) * clear;
    return vec4<f32>(c * CVS_WINDOW_EXPOSURE, m * select(0.88, 0.7, k == 0));
}
// What shows through the hole along the ray (it crosses the plane at tplane): the sky, the clouds and the islands,
// back to front.
fn cvs_aether(v: CvView, tplane: f32) -> vec3<f32> {
    let hit = cvs_trace(v, tplane);
    let sky = cvs_aether_sky(v.rd);
    var c = sky;
    var done = hit.isl < 0;
    for (var k = 2; k >= 0; k = k - 1) {
        let tk = (v.C.y + CV_RIFT_Y + cvs_cloud_h(k)) / max(v.rd.y, 1.0e-3);
        if (!done && hit.t > tk) {
            c = cvs_island_col(v, hit, tplane);
            done = true;
        }
        let a = cvs_skycloud(v, k, tk);
        let haze = exp(-max(tk - tplane, 0.0) / 900.0);
        c = mix(c, mix(sky, a.rgb, haze), a.a);
    }
    if (!done) {
        c = cvs_island_col(v, hit, tplane);
    }
    return c;
}

// ---- what spills out ---------------------------------------------------------------------------------------------
// How much the rift is open and pouring (0-1, a little over as they fire): easing in as it parts, drawn in over the
// crouch and thrown out as they fire, thinning after the blast as it closes.
fn cvs_pour(t: f32) -> f32 {
    // (it pours as the hole parts: none through the hairline, most of it once the hole is a third open)
    let g = select(cvs_part(t), 1.0, t >= CV_MEET) / 0.3;
    let rise = 1.0 - exp(-g * g);
    return rise * (1.0 - 0.3 * cvs_gather(t) + 0.5 * cvs_kick(t)) * (1.0 - 0.55 * cv_beat(t, CV_HIT, CV_HIT + 3.0)) * (1.0 - cv_beat(t, CV_CLOSE, CV_END));
}
// How far the veils have fallen under the rift's plane at t: they start slowly, pour fast, slow as they reach their
// length, and lurch further down as the columns fire.
fn cvs_fall(t: f32) -> f32 {
    let a = max(t - CV_BREAK, 0.0);
    let u = max(t - CV_FIRE, 0.0) / 0.35;
    return 40.0 + 130.0 * (1.0 - exp(-a / 3.2)) * (1.0 - exp(-a * 2.0)) + 18.0 * (1.0 - exp(-u));
}
// The phase of what pours down the veils (their streaks): an uneven speed, faster once the columns fire.
fn cvs_pour_ph(t: f32) -> f32 {
    return t + 1.6 * fvnoise(vec2<f32>(t * 0.3, 1.7)) + 1.5 * max(t - CV_FIRE, 0.0);
}
// The phase of the light streaming down the gold column: slow while the stub hangs, speeding up as it fires (no step),
// rushing with the head as it races, then a fast stream whose speed wanders, carried on by `drive` (cvs_fight: faster
// while the meeting point is driven down, slower while it is driven up).
fn cvs_stream(t: f32, drive: f32) -> f32 {
    let race = CV_RIFT_Y - CV_GOLD_LOW - cv_gold_foot(clamp(t, CV_FIRE, CV_MEET));
    return 0.8 * t + 3.2 * cvs_ramp_int(t, CV_FIRE - 0.1, CV_FIRE + 0.4) + 0.016 * race + 1.5 * fvnoise(vec2<f32>(t * 0.8, 8.1)) + drive;
}
// The light falling from the rim: a thick hollow cone of luminous mist under the hole (its section the rift's ellipse,
// widening by `spread` over its fall), marched through in CVS_FALL_N steps between the rift's plane, the depth it has
// fallen to and the cone's widest section; curtains of light streaming down it at two scales, the finer turning with
// the depth into its wall; lit from the rim and the column within, falling into a clear blue shade on its outside and
// below. Premultiplied colour and transmittance.
const CVS_FALL_N: u32 = 8u;
fn cvs_curtain(v: CvView, spread: f32) -> vec4<f32> {
    let sz = cvs_size(v.t);
    let A = max(sz.x * 0.95, 1.0);
    let B = max(sz.y * 0.95, 1.0);
    let fall = cvs_fall(v.t);
    let ax = cvs_axis();
    let ac = vec2<f32>(-ax.y, ax.x);
    // (the camera from the target, in the seam's axes, scaled by the widest section)
    let o = -v.C;
    let Aw = A + spread;
    let Bw = B + spread;
    let ox = dot(o.xz, ax) / Aw;
    let oz = dot(o.xz, ac) / Bw;
    let dx = dot(v.rd.xz, ax) / Aw;
    let dz = dot(v.rd.xz, ac) / Bw;
    let qa = dx * dx + dz * dz;
    let qb = 2.0 * (ox * dx + oz * dz);
    let qc = ox * ox + oz * oz - 1.0;
    let disc = qb * qb - 4.0 * qa * qc;
    if (disc <= 0.0 || qa < 1.0e-12) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let sq = sqrt(disc);
    var t0 = max((-qb - sq) / (2.0 * qa), 0.0);
    var t1 = (-qb + sq) / (2.0 * qa);
    // (the slab it falls through)
    let ya = CV_RIFT_Y - fall - o.y;
    let yb = CV_RIFT_Y - o.y;
    if (abs(v.rd.y) > 1.0e-5) {
        let s0 = ya / v.rd.y;
        let s1 = yb / v.rd.y;
        t0 = max(t0, min(s0, s1));
        t1 = min(t1, max(s0, s1));
    } else if (ya > 0.0 || yb < 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    t1 = min(t1, select(v.len + 4.0, 1.0e7, v.sky));
    if (t1 <= t0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let n = CVS_FALL_N + u32(frame.resolution.x < 0.0);
    let dt = (t1 - t0) / f32(n);
    // (a fixed offset a pixel, so the steps do not band: a hash, not a gradient pattern; the half-size stage draws every
    // second pixel, and a gradient noise taken at that stride is a regular lattice of stripes, read as a cross-hatch)
    let px = floor(v_uv * frame.resolution.xy);
    let jit = fh21(px + vec2<f32>(17.0, 59.0));
    let ph = cvs_pour_ph(v.t);
    let rot = v.t * 0.025;
    let T = cvs_tear(v.t);
    let o2 = cvs_o();
    var add = vec3<f32>(0.0);
    var keep = 1.0;
    for (var i = 0u; i < n; i = i + 1u) {
        let tt = t0 + (f32(i) + jit) * dt;
        let P = o + v.rd * tt;
        let u = (CV_RIFT_Y - P.y) / fall;
        let X = dot(P.xz, ax) / (A + spread * u);
        let Z = dot(P.xz, ac) / (B + spread * u);
        let r = length(vec2<f32>(X, Z));
        // (a thick wall round the cone's side, a little light filling it within)
        let shell = exp(-((r - 0.88) / 0.26) * ((r - 0.88) / 0.26)) + 0.12 * (1.0 - smoothstep(0.4, 1.1, r));
        if (shell < 0.02) {
            continue;
        }
        // (light only under where the sky is open: the front and its large bays, at the point the mist fell from)
        let qp = vec2<f32>(X * A, Z * B);
        let opn = smoothstep(6.0, -6.0, cvs_dbase(qp, T.x, T.y) + T.z + 14.0 * (fvnoise(qp / 30.0 + o2) - 0.5));
        let ang = atan2(Z, X) + rot;
        let n1 = fvnoise(vec2<f32>(ang * 7.0, P.y * 0.03 + ph * 0.9));
        let n2 = fvnoise(vec2<f32>(ang * 19.0 + r * 5.0, P.y * 0.075 + ph * 1.7 + r * 1.3));
        let dens = smoothstep(0.38, 0.85, 0.6 * n1 + 0.4 * n2) * shell * pow(saturate(1.0 - u), 1.2) * smoothstep(0.0, 0.08, u) * (0.2 + 0.8 * opn);
        // (lit from the rim above and the column within)
        let lit = exp(-1.7 * u) * (0.45 + 0.55 * (1.0 - smoothstep(0.5, 1.2, r)));
        let col = mix(CVS_SHADE * 0.22, mix(CVS_GLOW, CVS_HOT, 0.45) * 1.15, lit) * (0.75 + 0.25 * v.day);
        let a = saturate(dens * dt * 0.02 * CVS_SPILL);
        add = add + col * a * keep;
        keep = keep * (1.0 - a);
    }
    return vec4<f32>(add, keep);
}
// Shafts of gold light slanting down from the rift to the land: each a beam of radius w, its brightness the length of
// ray inside it.
fn cvs_shafts(v: CvView, I: f32) -> vec3<f32> {
    let sz = cvs_size(v.t);
    let ax = cvs_axis();
    let ac = vec2<f32>(-ax.y, ax.x);
    var add = vec3<f32>(0.0);
    for (var i = 0; i < 7; i = i + 1) {
        let fi = f32(i);
        let a = fi * 0.8976 + 0.3 + seed_v() * 0.2;
        let ca = vec2<f32>(cos(a), sin(a));
        let top2 = (ax * ca.x * sz.x + ac * ca.y * sz.y) * 0.55;
        let reach = 70.0 + 70.0 * fract(fi * 0.618 + 0.2);
        let foot2 = (ax * ca.x + ac * ca.y) * reach;
        let S = v.C + vec3<f32>(top2.x, CV_RIFT_Y - 4.0, top2.y);
        let E = v.C + vec3<f32>(foot2.x, 0.0, foot2.y);
        let u = normalize(E - S);
        let L = length(E - S);
        // (the nearest points of the ray and the beam's line)
        let b = dot(v.rd, u);
        let dd = dot(v.rd, S);
        let e = dot(u, S);
        let den = max(1.0 - b * b, 1.0e-4);
        let tr = (dd - b * e) / den;
        let sb = clamp((b * dd - e) / den, 0.0, L);
        let d = length(v.rd * tr - (S + u * sb));
        let w = 7.0 + 9.0 * sb / L;
        // (soft at the beam's side rather than cut at it)
        let chord = 2.0 * sqrt(max(w * w - d * d, 0.0)) / sqrt(den) * (1.0 - smoothstep(0.6 * w, w, d) * 0.5);
        // (each its own slow flicker, and each its own moment to come on)
        let flick = 0.55 + 0.45 * fvnoise(vec2<f32>(v.t * (0.3 + 0.1 * fract(fi * 0.37)), fi * 3.1));
        // (each let down as the hole parts wide enough for it, one after another, eased)
        let pt = cvs_part(v.t);
        let k0 = 0.12 + 0.07 * fract(fi * 0.618 + 0.4) + 0.06 * fi;
        let on = smoothstep(k0, k0 + 0.35, pt);
        // (light streaming down it: slow brighter pulses running from the rift to the land)
        let pulse = 0.7 + 0.6 * fvnoise(vec2<f32>(sb * 0.035 - v.t * (0.9 + 0.2 * fract(fi * 0.37)), fi * 5.3));
        let along = smoothstep(0.0, 0.08, sb / L) * (1.0 - 0.7 * sb / L) * pulse;
        add = add + CVS_GLOW * min(chord, 60.0) * 0.0055 * flick * on * along * cv_vis(v, max(tr, 0.0));
    }
    return add * I;
}
// The gold column's sheath: a cylinder of radius R round the column from y0 (over the target's ground) up through the
// rift's plane into the Aether (over it only as seen through the hole); its glow the length of ray inside it, with turning streaks streaming down it at the phase
// `ph`, drawn out along it by the speed `vs`.
fn cvs_sheath(v: CvView, y0: f32, R: f32, ph: f32, vs: f32) -> vec3<f32> {
    let h = v.rd.xz;
    let hh = max(dot(h, h), 1.0e-6);
    let cxz = v.C.xz;
    let b = dot(cxz, h) / hh;
    let disc = b * b - (dot(cxz, cxz) - R * R) / hh;
    if (disc <= 0.0) {
        return vec3<f32>(0.0);
    }
    let sq = sqrt(disc);
    var add = vec3<f32>(0.0);
    let ya = v.C.y + y0;
    let yb = v.C.y + CV_RIFT_Y + 160.0;
    for (var j = 0; j < 2; j = j + 1) {
        let tt = b + select(sq, -sq, j == 0);
        if (tt <= 0.0) {
            continue;
        }
        let y = v.rd.y * tt;
        if (y < ya || y > yb) {
            continue;
        }
        let p = v.rd.xz * tt - cxz;
        let ang = atan2(p.y, p.x);
        let yy = (y - v.C.y) / (1.0 + vs / 900.0);
        let s = fvnoise(vec2<f32>(ang * 2.0 + v.t * 0.35, yy * 0.025 + ph));
        let s2 = fvnoise(vec2<f32>(ang * 5.0 - v.t * 0.2, yy * 0.06 + ph * 1.9));
        let streak = smoothstep(0.45, 0.95, 0.6 * s + 0.4 * s2);
        let ends = smoothstep(ya, ya + 10.0, y) * smoothstep(yb, yb - 80.0, y) * cvs_seen_at(y - v.C.y);
        add = add + CVS_BODY * streak * ends * cv_vis(v, tt);
    }
    // (the length of ray inside it: a soft body, densest seen through its middle)
    let chord = min(sq * sqrt(hh), R) / R;
    let ymid = v.rd.y * b;
    let inr = smoothstep(ya, ya + 8.0, ymid) * smoothstep(yb, yb - 80.0, ymid) * cvs_seen_at(ymid - v.C.y);
    return add * 0.6 + CVS_DEEP * chord * chord * 0.26 * inr * cv_vis(v, b);
}
// The real islands growing out of the rift's light after the blast (the table's start times): a thread of light let down from the rift to each as it forms and a
// soft glow round it, from just before it starts to a few seconds after its underside is whole.
fn cvs_threads(v: CvView) -> vec3<f32> {
    var add = vec3<f32>(0.0);
    let n = min(u32(max(cv_w(CVS_ISL), 0.0)), 16u);
    for (var k = 0u; k < n; k = k + 1u) {
        let o = CVS_ISL + 1u + 5u * k;
        let t0 = cv_w(o + 4u);
        let a = v.t - t0;
        if (a < -0.8 || a > 10.0) {
            continue;
        }
        let env = smoothstep(-0.8, 0.2, a) * (1.0 - smoothstep(5.5, 10.0, a)) * (1.0 - cv_beat(v.t, CV_CLOSE + 2.0, CV_END));
        let P = v.C + vec3<f32>(cv_w(o), 0.0, cv_w(o + 1u));
        let top = cv_w(o + 2u);
        let R = cv_w(o + 3u);
        let s = cv_vseg(v.rd, P, top + 1.0, CV_RIFT_Y);
        // (a broad soft ray of light, narrow where it leaves the rift and spreading to the island's width as it comes
        // down, brightest over the island, fading toward the rift; never thinner than several pixels)
        let y = v.rd.y * s.y - P.y;
        let dn = smoothstep(CV_RIFT_Y, top, y);
        let up = (0.25 + 0.75 * dn) * smoothstep(CV_RIFT_Y + 0.5, CV_RIFT_Y - 10.0, y);
        let w = max(R * (0.25 + 0.55 * dn), s.y * cvs_pxa() * 6.0);
        let th = CVS_GLOW * exp(-s.x * s.x / (w * w)) * 0.16 * up * cv_vis(v, s.y);
        // (the glow round the island as it forms)
        let g = cv_pt(v.rd, P + vec3<f32>(0.0, top - 0.3 * R, 0.0));
        add = add + (th + CVS_GLOW * exp(-g.x * g.x / (R * R * 1.6)) * 0.22 * cv_vis(v, g.y - R)) * env;
    }
    return add;
}
// The rift's light in the clash (a factor on its rim, its spill, its veils, its shafts): brighter as the column
// drives, dimmer as it is driven back, with the clash's own smooth rise and fall.
fn cvs_rift_lit(t: f32) -> f32 {
    let F = cvs_f;
    return max(1.0 + 0.9 * min(F.dn, 0.6) - 0.35 * F.up, 0.3);
}
// The gold column's strength at t: coming down after CV_GOLD0, held to the blast, swallowed by it.
fn cvs_col_i(t: f32) -> f32 {
    return cv_beat(t, CV_GOLD0 - 0.3, CV_GOLD0 + 0.6) * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 0.3));
}
// Its strength over the rift's plane, in the Aether: lit at its source as the hole first gives, coming down to the hole
// (cvs_colfoot), held to the blast, then drawn back up into its source.
fn cvs_up_i(t: f32) -> f32 {
    return cv_beat(t, CV_GOLD0 - 1.9, CV_GOLD0 - 1.3) * (1.0 - cv_beat(t, CV_HIT + 1.4, CV_HIT + 2.4));
}
// Its strength at height y (over the target's ground): the Aether's share over the plane, the column's under it.
fn cvs_ci_at(t: f32, y: f32) -> f32 {
    return mix(cvs_col_i(t), cvs_up_i(t), smoothstep(CV_RIFT_Y - 3.0, CV_RIFT_Y + 3.0, y));
}
// The column's lower end at t, the whole of it: its light coming down from its source through the Aether to the hole
// before it hangs out of it (from CV_GOLD0, cvs_foot), and after the blast drawn back up into its source.
fn cvs_colfoot(t: f32) -> f32 {
    if (t < CV_GOLD0) {
        return CV_RIFT_Y + CVS_SRC * (1.0 - cvs_ease(t, CV_GOLD0 - 1.7, CV_GOLD0));
    }
    return mix(cvs_foot(t), CV_RIFT_Y + CVS_SRC, cvs_ease(t, CV_HIT + 0.1, CV_HIT + 2.4));
}
// How much of a point of the column at height y shows: under the plane all of it, over it what the ray sees through
// the hole (cvs_vh).
fn cvs_seen_at(y: f32) -> f32 {
    return mix(1.0, cvs_vh, smoothstep(CV_RIFT_Y - 1.0, CV_RIFT_Y + 2.0, y));
}
// Its far end in the Aether: fading into the light of its source.
fn cvs_top_at(y: f32) -> f32 {
    return smoothstep(CV_RIFT_Y + CVS_SRC, CV_RIFT_Y + CVS_SRC - 220.0, y);
}

// The soft part (half size at QUALITY FAST): the Aether through the hole, the glow round it, the veils, the shafts,
// the column's sheath and halo.
fn cv_sky_soft(v: CvView) -> vec4<f32> {
    var add = vec3<f32>(0.0);
    var keep = 1.0;
    let t = v.t;
    cvs_f = cvs_fight(t);
    let rl = cvs_rift_lit(t);
    let pour = cvs_pour(t);
    let gat = cvs_gather(t);
    let kick = cvs_kick(t);
    let rc = cvs_recoil(t);
    cvs_vh = 0.0;
    cvs_upl = cvs_up_i(t) * cv_k_glow();
    let L0 = cvs_tear_at(v, 0.0, 2.0);
    if (L0.z < 1.0e8) {
        let seen = cv_vis(v, L0.z);
        // (the Aether, only from under the hole)
        if (v.rd.y > 0.0 && L0.e < L0.pf) {
            let inside = smoothstep(L0.pf, -L0.pf, L0.e) * seen;
            if (inside > 0.0) {
                // (the tear has thickness: past its lower edge the ray must pass its upper one, CVS_LIP over it and
                // set back a little, to see the Aether; between them it sees the torn wall, lit pale gold-white near
                // the lower edge where the light pours over it, in a clear blue shade deeper in)
                let U = cvs_tear_at(v, CVS_LIP, 2.0);
                let thru = smoothstep(U.pf, -U.pf, U.e + 1.5);
                let wl = exp(min(L0.e, 0.0) / 4.0);
                // (light running down the wall in streaks, fixed in the wall)
                let wn = fvnoise(vec2<f32>(L0.q.x * 0.35 + L0.q.y * 0.2, L0.q.y * 0.35 - t * 0.8));
                let wall = mix(CVS_SHADE * 0.16, mix(CVS_GLOW, CVS_HOT, 0.5) * 0.75, wl) * (0.55 + 0.45 * wn);
                var ae = vec3<f32>(0.0);
                if (thru > 0.0) {
                    ae = cvs_aether(v, L0.z) * mix(0.62, 1.0, smoothstep(0.0, -6.0, U.e));
                }
                add = add + mix(wall * (0.5 + 0.4 * cvs_pour(t) + 0.6 * cvs_strain(t)), ae, thru) * inside;
                keep = keep * (1.0 - inside);
                cvs_vh = inside * thru;
            }
        }
        // (light spilling round the hole, on the plane's both sides, from where it is open: blocks out from the
        // edge, never a shape scaled with the hole; drawn in tight over the crouch, thrown wide as they fire and as
        // the impact's recoil reaches it)
        let out = max(L0.es, 0.0) * (1.0 + 1.5 * gat);
        let g = (exp(-out / 22.0) * 0.6 + exp(-out / 80.0) * 0.25) * smoothstep(-2.0, 2.0, L0.e) * seen * (0.3 + 0.7 * cvs_part(t)) * cv_beat(t, CV_OMEN + 0.3, CV_BREAK);
        add = add + CVS_GLOW * g * (0.1 + 0.25 * pour + 0.12 * cvs_strain(t)) * (1.0 - 0.5 * gat + 0.9 * kick + 0.7 * rc) * rl * (1.0 - cv_beat(t, CV_CLOSE, CV_END));
    }
    // the veils pouring over the rim
    if (pour > 0.01) {
        let hz = cv_k_haze();
        let v1 = cvs_curtain(v, 55.0 + 35.0 * cv_beat(t, CV_MEET, CV_HIT));
        let vl = mix(1.0, rl, 0.5);
        let a1 = vec4<f32>(v1.rgb * pour * hz * vl, 1.0 - saturate((1.0 - v1.a) * pour * hz));
        add = add * a1.a + a1.rgb;
        keep = keep * a1.a;
        let si = hz * pour * (0.6 + 0.6 * cv_beat(t, CV_MEET, CV_HIT)) * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 2.0) * 0.8);
        add = add + cvs_shafts(v, si * (1.0 - 0.6 * gat + 0.7 * kick + 0.5 * rc) * mix(1.0, rl, 0.6));
    }
    // the threads of light down to the islands growing in the sky
    if (t > CV_HIT + 1.0 && t < CV_END) {
        add = add + cvs_threads(v) * cv_k_glow();
    }
    // the gold column, from the rift (never over it, never wider than its hole) down to its foot: sheath and halo, the
    // same body whether it hangs under the rift, races down or stands in the clash (cvs_beam_r, cvs_beam_i), a soft
    // glow round its leading end as it races
    let ci0 = max(cvs_col_i(t), cvs_up_i(t)) * cv_k_glow();
    if (ci0 > 0.0) {
        let F = cvs_f;
        let foot = cvs_colfoot(t);
        let sz = cvs_size(t);
        let vs = cvs_speed(t);
        let L = max(CV_RIFT_Y - foot, 1.0);
        let Rs = min(1.8 * CV_BEAM_R, 0.8 * sz.y + 0.5);
        let gain = (1.0 + 0.5 * cvs_charge(t)) * (1.0 + 0.45 * F.dn - 0.2 * F.up) * (1.0 + 0.4 * rc);
        add = add + cvs_sheath(v, foot, Rs, F.ph, vs) * cvs_col_i(t) * cv_k_glow() * gain;
        let yb = CV_RIFT_Y + CVS_SRC;
        let a = cvs_axis_d(v, foot, yb);
        let ci = cvs_ci_at(t, a.z) * cv_k_glow() * cvs_seen_at(a.z) * cvs_top_at(a.z);
        if (ci > 0.0) {
            let s = a.z - foot;
            // (the fronts only near the axis: far out only the halo's tail reaches)
            var lb = 0.0;
            if (a.x < 40.0) {
                lb = cvs_front(t, a.z, foot);
            }
            let R = cvs_beam_r_at(t, s, sz, a.z);
            let I = cvs_beam_i(t, s, L, lb, R, a.z);
            let w = min(1.5 * R, 0.8 * sz.y + 1.0 + 60.0 * smoothstep(CV_RIFT_Y, CV_RIFT_Y + 60.0, a.z));
            // (a pale gold glow round it, its long tail cooling to a clear sky blue; it runs on up through the hole
            // into the Aether, no end on the plane)
            let tl = 0.07 * w / (a.x + w);
            // (in the clash its foot thins out over the last stretch above the meeting point, where the front's blades
            // carry it on: no rounded end)
            let ff = mix(1.0, smoothstep(-4.0, 20.0, s), 0.7 * F.on);
            let body = (tl + 0.18 * exp(-a.x * a.x / (4.0 * w * w))) * ff;
            add = add + mix(CVS_DEEP, CVS_SHADE, saturate(0.4 * tl / max(body, 1.0e-4))) * body * ci * I * cv_vis(v, a.y);
            // (its leading end as it comes down or races: a glow round it, the brighter the faster)
            let lg = saturate(vs / 600.0) * exp(-max(s, 0.0) / (2.0 * R + 0.05 * vs));
            add = add + CVS_HOT * lg * 0.3 * exp(-a.x * a.x / (9.0 * R * R)) * ci * cv_vis(v, a.y);
            // (a little body to it: it hides some of the bright sky behind, so its gold reads against it)
            let dens = 0.5 * exp(-a.x * a.x / (0.8 * w * w)) * min(ci, 1.0) * cv_vis(v, a.y);
            add = add * (1.0 - dens);
            keep = keep * (1.0 - dens);
        }
        // (its source, far up in the Aether: a blaze the column narrows into, seen only through the hole)
        let si = cvs_up_i(t) * cv_k_glow() * cvs_vh;
        if (si > 0.0) {
            let g = cv_pt(v.rd, v.C + vec3<f32>(0.0, yb, 0.0));
            let r = g.x / 22.0;
            add = add + (CVS_HOT * exp(-r * r * 0.6) * 1.2 + CVS_GLOW * 0.35 / (1.0 + r)) * si * (1.0 + 0.5 * cvs_charge(t));
        }
    }
    return vec4<f32>(add * v.fade, mix(1.0, keep, v.fade));
}

// ---- the sharp part ------------------------------------------------------------------------------------------------
// Gold motes on three shells round the column (one per cell of 7 by 7 blocks of each, the odd cell lit), drifting
// down and turning; brightest after the blast.
fn cvs_motes(v: CvView, I: f32) -> vec3<f32> {
    var add = vec3<f32>(0.0);
    let h = v.rd.xz;
    let hh = max(dot(h, h), 1.0e-6);
    let cxz = v.C.xz;
    let b = dot(cxz, h) / hh;
    let cc = dot(cxz, cxz);
    let pxa = cvs_pxa();
    for (var k = 0; k < 3; k = k + 1) {
        let R = select(select(125.0, 75.0, k == 1), 38.0, k == 0);
        let disc = b * b - (cc - R * R) / hh;
        if (disc <= 0.0) {
            continue;
        }
        let sq = sqrt(disc);
        for (var j = 0; j < 2; j = j + 1) {
            let tt = b + select(sq, -sq, j == 0);
            if (tt <= 0.0) {
                continue;
            }
            let y = v.rd.y * tt - v.C.y;
            if (y < 5.0 || y > CV_RIFT_Y) {
                continue;
            }
            let p = v.rd.xz * tt - cxz;
            let arc = (atan2(p.y, p.x) + v.t * (0.02 + 0.01 * f32(k))) * R;
            let q = vec2<f32>(arc, y + v.t * (4.0 + 1.5 * f32(k)));
            let cell = floor(q / 7.0);
            let hsh = fh21(cell + vec2<f32>(f32(k) * 91.0, 3.0));
            if (hsh < 0.72) {
                continue;
            }
            let at = (cell + 0.2 + 0.6 * vec2<f32>(fract(hsh * 13.7), fract(hsh * 71.3))) * 7.0;
            let d = length(q - at);
            let rr = max(0.22, tt * pxa * 1.3);
            let tw = 0.6 + 0.4 * sin(v.t * 3.0 + hsh * 40.0);
            // (fading in under the rift and out near the ground, never cut at the shell's ends)
            let ends = smoothstep(5.0, 15.0, y) * smoothstep(CV_RIFT_Y, CV_RIFT_Y - 15.0, y);
            add = add + mix(CVS_HOT, CVS_GLOW, hsh) * exp(-d * d / (rr * rr)) * tw * ends * (0.14 / rr + 0.32) * cv_vis(v, tt);
        }
    }
    return add * I;
}
// Flakes torn off the burning edge: one in four of the 3 by 3 block cells of four planes near the rift's (two over it,
// lifting into the Aether's light; two under it, falling), each torn off where it lies as the front passes it and
// shown on the plane its age has carried it to, so it rises or falls in steps that cross-fade; small bright shards,
// cooling as they go and burning out.
fn cvs_flakes(v: CvView, t: f32) -> vec3<f32> {
    var add = vec3<f32>(0.0);
    let T = cvs_tear(t);
    let T0 = cvs_tear(t - 0.2);
    let n = 4 + i32(frame.resolution.x < 0.0);
    for (var k = 0; k < n; k = k + 1) {
        let dy = select(select(-13.0, -5.0, k == 2), select(11.0, 4.0, k == 0), k < 2);
        let Q = cvs_rift_q_at(v, dy);
        if (Q.z > 1.0e8) {
            continue;
        }
        let cell = floor(Q.xy / 3.0);
        let h = fh21(cell + vec2<f32>(f32(k) * 57.0 + 3.0, 11.0));
        if (h < 0.74) {
            continue;
        }
        let p0 = (cell + vec2<f32>(0.2) + 0.6 * vec2<f32>(fract(h * 13.7), fract(h * 71.3))) * 3.0;
        let d0 = cvs_dbase(p0, T.x, T.y) + T.z;
        if (d0 > 22.0 || d0 < -30.0) {
            continue;
        }
        // (its age: how far the front has gone past it, blocks; 0 as it is torn off)
        let age = -cvs_e(p0, T).x / 7.0;
        let ph = select(0.0, 0.5, k == 1 || k == 3);
        let on = smoothstep(ph - 0.15, ph + 0.05, age) * (1.0 - smoothstep(ph + 0.35, ph + 0.55, age));
        if (on <= 0.0) {
            continue;
        }
        let sp = abs(cvs_dbase(p0, T0.x, T0.y) + T0.z - d0) / 0.2;
        let hot = saturate(sp / 5.0);
        // (a shard: long one way, its own turn)
        let an = h * 40.0;
        let dq = Q.xy - p0;
        let r = vec2<f32>(dot(dq, vec2<f32>(cos(an), sin(an))), dot(dq, vec2<f32>(-sin(an), cos(an))));
        let pf = Q.z * cvs_pxa() / max(abs(v.rd.y), 0.05);
        let sz = vec2<f32>(max(1.7, pf), max(0.7, pf));
        let f = exp(-dot(r / sz, r / sz) * 2.0) * min(1.0, 1.4 / pf);
        let cool = saturate(age);
        add = add + mix(CVS_HOT, select(CVS_SHADE * 0.6, CVS_GLOW, k < 2), cool) * f * on * hot * (1.3 - 0.8 * cool) * cv_vis(v, Q.z);
    }
    return add;
}
// The sharp part (full size): the Aether's light on the land, the hole's torn, bright edge, the gold column's core,
// the motes. Each faded by the ground side's smoke in front of it (cvs_veiled), and where the smoke hides the rift
// or the column, only a broad glow of them through it.
fn cv_sky_sharp(v: CvView, col: vec3<f32>) -> vec3<f32> {
    var c = col;
    let t = v.t;
    cvs_f = cvs_fight(t);
    let vf = cvs_veiled(v);
    let hid = 1.0 - vf;
    let gat = cvs_gather(t);
    let kick = cvs_kick(t);
    let rc = cvs_recoil(t);
    // the Aether's light on the land under it: pale gold near the column, sky blue further out, on its own half (the
    // land's share of the pixel only: none on the smoke in front of it)
    if (!v.sky) {
        let P = v.rel - v.C;
        let ax = cvs_axis();
        let r = length(P.xz);
        let aside = smoothstep(-12.0, 12.0, -(ax.x * P.z - ax.y * P.x));
        let grow = 0.35 * cv_beat(t, CV_BREAK, CV_MEET) + 0.65 * cv_beat(t, CV_MEET, CV_HIT - 0.3);
        let lit = grow * (1.0 - 0.8 * cv_beat(t, CV_HIT, CV_HIT + 2.0)) * (1.0 - cv_beat(t, CV_CLOSE, CV_END)) * v.fade * v.veil;
        if (lit > 0.0) {
            let near = 1.0 / (1.0 + (r / 70.0) * (r / 70.0));
            let wide = 1.0 / (1.0 + (r / 220.0) * (r / 220.0));
            let tint = vec3<f32>(1.0, 0.86, 0.64) * near * (0.3 + 0.7 * aside) + vec3<f32>(0.45, 0.62, 1.0) * wide * (0.25 + 0.5 * aside) * 0.6;
            c = c * (1.0 + tint * lit * CVS_LAND_LIGHT * 2.0) + CVS_GLOW * near * aside * lit * 0.03;
        }
    }
    let open = cv_beat(t, CV_OMEN + 0.3, CV_OMEN + 1.5) * (1.0 - cv_beat(t, CV_END - 2.0, CV_END));
    let st = cvs_strain(t);
    let rimg = (1.0 - 0.45 * gat + 1.6 * kick + 1.2 * rc + 1.4 * st) * cvs_rift_lit(t);
    // the torn edge: the sky's stuff burning where it is being eaten (bright, wide and hot where the front is moving
    // at that moment, cooled to a steady glow where it has stopped), a white seam on the edge, a pale gold band on the
    // sky's side with embers in it, and the sky scorched dark beyond it; all at a fixed size in blocks. Dimmed over the
    // crouch, flaring as they fire; in the clash flaring as it pours, guttering as it takes a blow
    let L0 = cvs_tear_at(v, 0.0, 1.0);
    if (vf > 0.003 && L0.z < 1.0e8 && L0.e < 30.0 && L0.e > -20.0) {
        let e = L0.e;
        let heat = saturate(abs(L0.v) / 5.0) * cvs_part(t + 0.6);
        let crawl = 0.7 + 0.6 * fvnoise(L0.q * 0.22 + vec2<f32>(t * 0.35, -t * 0.25));
        let w = max(0.55 + 0.9 * heat, 1.2 * L0.pf);
        let ei = select(e, e * 2.5, e < 0.0);
        let core = exp(-(ei / w) * (ei / w));
        let band = exp(-max(e, 0.0) / (2.0 + 5.0 * heat)) * smoothstep(-1.5 * w, 0.0, e);
        // (embers: one cell in a few of a block and a half, each its own flicker, in the band)
        let cell = floor(L0.q / 1.6);
        let hc = fh21(cell + vec2<f32>(17.0, 3.0));
        let fl = fvnoise(vec2<f32>(hc * 53.0, t * (2.0 + 2.0 * hc)));
        let emb = step(0.74, hc) * smoothstep(0.35, 0.9, fl) * exp(-max(e, 0.0) / (2.5 + 3.0 * heat)) * smoothstep(-0.4, 0.6, e) * min(1.0, 1.6 / L0.pf);
        // (scorched: the sky's stuff charred dark just outside the burning edge, once there is a hole to burn from)
        let ch = smoothstep(0.5, 3.0, e) * exp(-max(e - 3.0, 0.0) / 9.0) * saturate(cvs_part(t) * 4.0);
        let lit = open * cv_vis(v, L0.z) * vf * v.fade;
        let I = lit * rimg * crawl;
        let add = (CVS_HOT * core * (0.9 + 1.4 * heat) + CVS_BODY * band * (0.25 + 0.65 * heat) + mix(CVS_GLOW, CVS_HOT, fl) * emb * (0.6 + 1.2 * heat)) * I;
        c = c * (1.0 - 0.55 * ch * lit) + CVS_SHADE * 0.02 * ch * lit;
        c = mix(c + add, cvs_shoulder(c + add), saturate(band * 2.0));
        // (flakes of it torn off the edge as it is eaten: some lifting into the Aether's light, some falling and
        // burning out)
        if (heat > 0.02 && e > -12.0 && e < 6.0) {
            c = c + cvs_flakes(v, t) * lit;
        }
    }
    // the hairline over the omen: a crack in the sky, straining (brighter and crackling harder) before it gives, a
    // thin line of it left where the tear does not reach, dimming once the hole is whole
    let hw = open * (1.0 - 0.9 * cvs_ease(t, CV_BREAK + 3.0, CV_MEET)) * vf * v.fade;
    if (hw > 0.003 && L0.z < 1.0e8) {
        let hl = cvs_hair_len(t);
        let dh = length(vec2<f32>(max(abs(L0.q.x) - hl, 0.0), L0.q.y));
        if (dh < 40.0) {
            // (a crack, not a bar: thinning and dimming toward its ends)
            let tp = sqrt(saturate(1.0 - (L0.q.x / max(hl, 1.0)) * (L0.q.x / max(hl, 1.0))));
            let wh = max((0.25 + 0.6 * st) * (0.3 + 0.7 * tp), 1.2 * L0.pf);
            let ck = 0.6 + 0.6 * fvnoise(vec2<f32>(L0.q.x * 0.45, t * 3.0)) * (0.5 + st);
            let cs = 0.8 + 0.4 * fvnoise(vec2<f32>(L0.q.x * 0.06, t * 0.7));
            let add = (CVS_HOT * exp(-(dh / wh) * (dh / wh)) * 1.4 * ck + CVS_BODY * exp(-dh / (2.0 + 5.0 * st)) * 0.35 * cs) * (0.45 + 1.1 * st) * (0.25 + 0.75 * tp) * smoothstep(-L0.pf, L0.pf, L0.e) * cv_vis(v, L0.z) * hw;
            c = mix(c + add, cvs_shoulder(c + add), saturate(exp(-dh / 3.0)));
        }
    }
    // the seam straining: light pressing through it, a soft glow drawn out along it that builds before it parts and
    // eases down to a share of itself as the hole opens and the spill takes over (no rays, nothing thrown out)
    if (st > 0.003 && vf > 0.003) {
        let q = cvs_rift_q(v);
        if (q.z < 1.0e8) {
            let sz = cvs_size(t);
            let e = vec2<f32>(q.x / (sz.x + 30.0), q.y / (sz.y + 9.0));
            let r2 = dot(e, e);
            let gl = exp(-r2 * 2.5) * 0.45 + exp(-sqrt(r2) * 2.4) * 0.16;
            let add = (CVS_GLOW * gl + CVS_HOT * exp(-r2 * 9.0) * 0.35) * st * open * cv_vis(v, q.z) * vf * v.fade;
            c = mix(c + add, cvs_shoulder(c + add), saturate(gl * 2.0));
        }
    }
    // (behind the smoke, the rift only as a broad glow lighting it from within)
    if (hid > 0.003) {
        let q = cvs_rift_q(v);
        if (q.z < 1.0e8) {
            let sz = cvs_size(t);
            let e = vec2<f32>(q.x / (sz.x + 50.0), q.y / (sz.y + 50.0));
            let gl = exp(-dot(e, e) * 2.0) * saturate(sz.x / 40.0) * (0.35 + 0.4 * cvs_pour(t)) * rimg;
            c = c + CVS_GLOW * gl * hid * 0.45 * open * v.fade;
        }
    }
    // the gold column's core: never over the rift's plane, CV_BEAM_R across whether it hangs, races or stands, a
    // white-gold heart in a gold body, its filaments streaming down it (drawn out and faster as it races, a brighter
    // leading end with light dragged behind it); in the clash its axis and width held, its stream, heat, fronts and skin's
    // turbulence following the clash (cvs_f, cvs_front, cvs_beam_*)
    let ci0 = max(cvs_col_i(t), cvs_up_i(t)) * cv_k_glow();
    if (ci0 > 0.0) {
        let foot = cvs_colfoot(t);
        let a = cvs_axis_d(v, foot, CV_RIFT_Y + CVS_SRC);
        // (what of it over the plane this ray sees through the hole: worked out only where that is asked)
        cvs_vh = 0.0;
        if (a.z > CV_RIFT_Y - 1.0 && L0.z < 1.0e8 && v.rd.y > 0.0 && L0.e < L0.pf && a.x < 50.0 + a.y * cvs_pxa() * 3.0) {
            let U = cvs_tear_at(v, CVS_LIP, 1.0);
            cvs_vh = smoothstep(L0.pf, -L0.pf, L0.e) * smoothstep(U.pf, -U.pf, U.e + 1.5);
        }
        let ci = cvs_ci_at(t, a.z) * cv_k_glow();
        // (only near the axis: the core and its glow behind the smoke lie within this)
        if (a.x < 50.0 + a.y * cvs_pxa() * 3.0) {
            let F = cvs_f;
            let sz = cvs_size(t);
            let L = max(CV_RIFT_Y - foot, 1.0);
            let lb = cvs_front(t, a.z, foot);
            let s = a.z - foot;
            let R = cvs_beam_r_at(t, s, sz, a.z);
            let Rp = max(R, a.y * cvs_pxa() * 1.5);
            let q = a.x / Rp;
            // (its filaments: across it by where the ray passes it sideways, along it streaming down)
            let side = normalize(vec3<f32>(-v.rd.z, 0.0, v.rd.x) + vec3<f32>(1.0e-5, 0.0, 0.0));
            let P = vec3<f32>(v.C.x, v.C.y + a.z, v.C.z);
            let lat = dot(v.rd * a.y - P, side) / Rp;
            let vs = cvs_speed(t);
            let ph = F.ph;
            let yy = a.z / (1.0 + vs / 700.0);
            let n1 = fvnoise(vec2<f32>(lat * 1.7 + 3.1, yy * 0.04 + ph * 1.2));
            let n2 = fvnoise(vec2<f32>(lat * 4.3 + 8.7, yy * 0.11 + ph * 2.3));
            // (the harder the clash is pressed, the more its fine filaments break up the skin)
            let wf = 0.38 + 0.22 * F.tb;
            let tex = 0.62 + 0.62 * smoothstep(0.3 - 0.06 * F.tb, 0.88, (1.0 - wf) * n1 + wf * n2);
            // (no end on the plane: it runs on up through the hole into its source, seen over the plane only through
            // the hole)
            // (in the clash its foot frays: torn off at uneven heights across it over the last twenty-odd blocks above
            // the meeting point, a fixed length, so it ends in blades, not a cap, and the fire's tongues show between
            // them; the blades' pattern streams down with the light itself. While the Nether drives, the light's end
            // breaks up, read at the time what is there passed the meeting point (its length the same))
            let nfr = fvnoise(vec2<f32>(lat * 2.2 + 5.0, s * 0.07 + ph * 1.5));
            let nbr = fvnoise(vec2<f32>(lat * 5.1 + 1.7, s * 0.16 + ph * 2.6));
            let kb = max(cv_kick(t - max(s, 0.0) / 150.0), 0.0) * F.on;
            let fry = mix(1.0, smoothstep(0.0, 24.0, s + 26.0 * (nfr - 0.5)) * (1.0 - min(kb, 1.0) * 0.85 * smoothstep(0.55, 0.3, nbr) * exp(-max(s, 0.0) / 40.0)), F.on);
            let top = cvs_top_at(a.z) * cvs_seen_at(a.z) * fry;
            let I = ci * cvs_beam_i(t, s, L, lb, R, a.z) * cv_vis(v, a.y) * v.fade * top;
            // (a white heart, a pale gold-white body, a soft luminous sheath round it, its edge cooling to sky blue)
            let body = exp(-q * q * q * q);
            let heart = exp(-q * q * 5.0);
            let sheath = exp(-q * q * 0.35);
            let core = CVS_BODY * body * (0.75 + 0.55 * tex) * 1.3 + CVS_HOT * heart * (0.55 + 0.45 * tex) * 1.5 + CVS_DEEP * sheath * 0.22 + CVS_SHADE * max(sheath - body, 0.0) * 0.1;
            // (its body hides what is behind it, so it reads as a solid beam over the sky and the smoke, not a haze)
            let op = 0.85 * body * min(ci, 1.0) * cv_vis(v, a.y) * v.fade * top * vf;
            c = c * (1.0 - op) + core * I * vf;
            // (behind the smoke, a broad glow of it)
            c = c + CVS_BODY * 0.3 * exp(-a.x / (2.3 * R)) * I * hid;
            // (the brightest of it eased off to a clean white)
            c = mix(c, cvs_shoulder(c), saturate(2.0 * sheath * min(ci, 1.0)));
        }
    }
    // the motes: a few over the clash, the last fall after the blast
    let mi = 0.35 * cv_beat(t, CV_BREAK, CV_MEET) + 0.65 * cv_beat(t, CV_HIT, CV_HIT + 2.0) * (1.0 - cv_beat(t, CV_END - 3.0, CV_END + 4.0));
    if (mi > 0.0 && vf > 0.003) {
        c = c + cvs_motes(v, mi * v.fade * vf);
    }
    return c;
}
// ==== [end cv sky] ====================================================================================================
