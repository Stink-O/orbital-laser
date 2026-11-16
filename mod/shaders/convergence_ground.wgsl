// The Convergence's pass, its ground side, the clash and the burst: the Nether breaking out of the land (the fissures'
// fire, glow, smoke, embers and haze, the red column), the knot where the two columns meet (its arcs, its rings, the
// land lit red from below and gold from above), the draw-in and its held breath, the blast (the sundering: a sheet of
// light standing on the seam, the Nether's surge of fire and ash out over its half and the Aether's of light and mist
// over the other, sparks thrown, the impact frames, the flash, the lens) and its aftermath (an ash pall sinking over the
// Nether's half, mist lifting into the rift over the Aether's, a curtain of light on the seam, the crater's glow dying). Appended after
// shaders/convergence_sky.wgsl and before convergence.wgsl's `[cv stages]` (mod/build.rs); reads only what
// `[cv shared]` gives (and `v_uv` from the stages). Reached only through cv_ground_soft and cv_ground_sharp.
// ==== [cv ground] =====================================================================================================
// The soft parts (cv_ground_soft, half size at QUALITY FAST) are the volumes, each marched only inside its own bound:
// the fissure smoke, the red column, the knot, the sundering's surges, pall and mist; and the fire sheets along the cracks. The
// sharp parts (cv_ground_sharp, full size) are analytic: light on the land (the cracks, the columns, the rings, the
// fronts, the sheet, the crater), the sheet of light on the seam, the shock shells in the air,
// the arcs, sparks and ash (one cell of a hashed grid on a few planes facing the camera: no lists), the haze, the
// impact frames, the flash and the lens.

// Colours (linear).
const CVG_WHITE: vec3<f32> = vec3<f32>(1.0, 0.95, 0.86);
const CVG_CORE: vec3<f32> = vec3<f32>(1.0, 0.8, 0.5);
const CVG_FLAME: vec3<f32> = vec3<f32>(1.0, 0.38, 0.06);
const CVG_EMBER: vec3<f32> = vec3<f32>(1.0, 0.2, 0.03);
const CVG_BLOOD: vec3<f32> = vec3<f32>(0.5, 0.03, 0.015);
const CVG_ASH: vec3<f32> = vec3<f32>(0.3, 0.28, 0.27);
const CVG_GOLD: vec3<f32> = vec3<f32>(1.0, 0.88, 0.66);
// The Aether's light: pearl white, and the clear sky blue of its shade.
const CVG_PEARL: vec3<f32> = vec3<f32>(0.97, 0.96, 0.93);
const CVG_SKYB: vec3<f32> = vec3<f32>(0.55, 0.72, 1.0);
// The crater's radius (strike/convergence.rs's CV_CRATER_R, as built; its `crater` knob is not seen here).
const CVG_CRATER_R: f32 = 84.0;

// The live knobs (`/orbital tune`, read once a pixel by the shared block's cv_view; 1 = as built): 0 `glow` the red column's and the knot's brightness,
// 1 `burst` the sundering's surges' size, 2 `flash` the flash's strength, 3 `haze` the smoke's and the haze's amount.
fn cvg_k_glow() -> f32 {
    return cv_k_glow();
}
fn cvg_k_burst() -> f32 {
    return cv_k_burst();
}
fn cvg_k_flash() -> f32 {
    return cv_k_flash();
}
fn cvg_k_smoke() -> f32 {
    return cv_k_haze();
}
fn cvg_k_haze() -> f32 {
    return cv_k_haze();
}

// ---- small helpers ---------------------------------------------------------------------------------------------------
// Premultiplied colour and transmittance: f in front of b.
fn cvg_over(f: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(f.rgb + f.a * b.rgb, f.a * b.a);
}
// Which side the horizontal offset d (from the target) lies on: 1 the Nether, 0 the Aether, soft over `w` blocks
// across the seam (strike/convergence.rs's cv_side).
fn cvg_side(d: vec2<f32>, w: f32) -> f32 {
    let s = cv_seam();
    return smoothstep(-w, w, dot(d, vec2<f32>(-sin(s), cos(s))));
}
// A pixel's size in blocks at distance `t` along its ray.
fn cvg_px(t: f32) -> f32 {
    return t * frame.view_params.w * frame.resolution.w;
}
// The ray's span inside the vertical cylinder of radius R round C (camera-relative) between heights y0 and y1 over
// C.y, clipped to [0, lim]; x >= y when it misses.
fn cvg_cyl(rd: vec3<f32>, C: vec3<f32>, R: f32, y0: f32, y1: f32, lim: f32) -> vec2<f32> {
    let h = rd.xz;
    let a = max(dot(h, h), 1.0e-6);
    let b = dot(C.xz, h);
    let c = dot(C.xz, C.xz) - R * R;
    let disc = b * b - a * c;
    if (disc <= 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    let sq = sqrt(disc);
    var tn = (b - sq) / a;
    var tf = (b + sq) / a;
    if (abs(rd.y) > 1.0e-5) {
        let ta = (C.y + y0) / rd.y;
        let tb = (C.y + y1) / rd.y;
        tn = max(tn, min(ta, tb));
        tf = min(tf, max(ta, tb));
    } else if (C.y + y0 > 0.0 || C.y + y1 < 0.0) {
        return vec2<f32>(1.0, 0.0);
    }
    return vec2<f32>(max(tn, 0.0), min(tf, lim));
}
// The red column's presence at t (0 until the fire bursts out of the ground, blown out in the burst's first instant):
// the body itself comes in by travel (cvg_gout's jet climbing out of the ground), so this only switches on its light.
fn cvg_col_on(t: f32) -> f32 {
    return cv_beat(t, CV_RED0 - 0.03, CV_RED0 + 0.12) * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 0.25)) * (1.0 - 0.75 * cvg_collapse(t));
}
// The eruption. The strain before it, 0..1 over the last second and a half before CV_RED0, gathering hardest at the
// end (the ground over the target glowing and swelling with light through the cracks), let go over half a second as
// the fire breaks out.
fn cvg_strain(t: f32) -> f32 {
    let u = saturate((t - (CV_RED0 - 1.5)) / 1.5);
    return pow(u, 2.2) * (1.0 - smoothstep(CV_RED0, CV_RED0 + 0.6, t));
}
// The burst's light, `a` seconds after the fire breaks out: a hard attack, dying over a second.
fn cvg_burst(a: f32) -> f32 {
    if (a <= 0.0) {
        return 0.0;
    }
    return smoothstep(0.0, 0.1, a) * exp(-a / 0.9);
}
// The first gout, `a` seconds after the fire breaks out (CV_RED0): (the jet's head, climbing fast and slowing as it
// spends itself; the top of what still burns, falling back to the fountain's as the gout burns out from the top down;
// the head of dark smoke it throws up, still rising slowly; that head's radius). Each eased, none turning back on
// itself but the fire's top, which sinks as the fire above it goes to smoke.
fn cvg_gout(a: f32) -> vec4<f32> {
    let aa = max(a, 0.0);
    let hj = 96.0 * (1.0 - exp(-aa / 0.34));
    let hf = mix(hj, cv_red_top(CV_RED0 + aa), smoothstep(0.45, 2.4, aa));
    let rh = 12.0 + 12.0 * (1.0 - exp(-aa / 0.7)) + 4.0 * aa;
    let hs = hj + 5.0 * aa + 0.45 * rh;
    return vec4<f32>(hj, hf, hs, rh);
}
// The gout's life: on from the burst, gone by 7 s after it.
fn cvg_gout_on(t: f32) -> bool {
    return t > CV_RED0 - 1.6 && t < CV_RED0 + 7.0;
}
// The draw-in, 0..1 over CV_DRAW..CV_HIT, eased in (everything tightening hardest at the end).
fn cvg_draw(t: f32) -> f32 {
    let u = saturate((t - CV_DRAW) / (CV_HIT - CV_DRAW));
    return u * u;
}
// The draw-in as the ground side moves with it: tightening hardest at the end.
fn cvg_pull(t: f32) -> f32 {
    let u = saturate((t - CV_DRAW) / (CV_HIT - CV_DRAW));
    return pow(u, 2.3);
}
// The clash through the fight: on just after the impact, off over the held breath.
fn cvg_clash(t: f32) -> f32 {
    return smoothstep(CV_MEET, CV_MEET + 0.5, t) * (1.0 - smoothstep(CV_HIT - 0.6, CV_HIT - 0.1, t));
}
// The clash's force at t, worked out once a pixel (t is the same at every pixel; the other calls read it back):
//   x: the shared cv_kick as it is (positive while the Nether shoves up, negative while the Aether shoves down);
//   y: how hard they press (the shoves' speed, and the meeting point's own drift between them), 0 at the impact;
//   z: the meeting point's speed, blocks a second (up for the Nether), faded in after the impact and out over the draw;
//   w: which side is winning, about -1..1 (positive the Nether): the shove under way, which way the meeting point is
//      moving and a slow grinding wander, so it is never still; centred over the draw.
var<private> cvg_f_t: f32 = -1.0;
var<private> cvg_f_v: vec4<f32> = vec4<f32>(0.0);
fn cvg_force(t: f32) -> vec4<f32> {
    if (t == cvg_f_t) {
        return cvg_f_v;
    }
    cvg_f_t = t;
    if (t <= CV_MEET) {
        cvg_f_v = vec4<f32>(0.0);
        return cvg_f_v;
    }
    let kick = cv_kick(t);
    let cl = cvg_clash(t);
    let held = 1.0 - saturate(cvg_pull(t));
    let vel = (cv_meet_y(t + 0.02) - cv_meet_y(t - 0.02)) / 0.04 * cl * held;
    let press = abs(kick) + 0.3 * tanh(abs(vel) / 25.0);
    let g = fvnoise(vec2<f32>(t * 1.7, 6.3)) - 0.5;
    let win = clamp(kick + 0.35 * tanh(vel / 15.0) + 0.3 * g * cl, -1.0, 1.0) * held;
    cvg_f_v = vec4<f32>(kick, press, vel, win);
    return cvg_f_v;
}
// How fast the Aether is driving the meeting point down to the land from CV_DRAW, as a share of about 90 blocks a
// second (0 outside the drive), worked out once a pixel.
var<private> cvg_d_t: f32 = -1.0;
var<private> cvg_d_v: f32 = 0.0;
fn cvg_descent(t: f32) -> f32 {
    if (t == cvg_d_t) {
        return cvg_d_v;
    }
    cvg_d_t = t;
    cvg_d_v = 0.0;
    if (t > CV_DRAW && t < CV_HIT) {
        cvg_d_v = clamp((cv_meet_y(t - 0.02) - cv_meet_y(t + 0.02)) / 0.04 / 90.0, 0.0, 1.3);
    }
    return cvg_d_v;
}
// Which way the clash is being shoved at t and how hard: the shared cv_kick.
fn cvg_kick(t: f32) -> f32 {
    return cvg_force(t).x;
}
// The integral of the shoves' speed (cv_push) from their starts to t, each scaled by `up` for the Nether's and `down`
// for the Aether's and by its reach: what a flow or a spin gains from them, so its speed rises and falls with the
// meeting point's, never in a step.
fn cvg_pushed(t: f32, up: f32, down: f32) -> f32 {
    var f = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        let u = t - cv_surge(i);
        if (u > 0.0) {
            let a = cv_surge_atk(i);
            let x = u / a;
            f = f + select(down, up, cv_surge_sign(i) > 0.0) * cv_surge_amp(i) / 40.0 * 2.7182818 * a * (1.0 - (1.0 + x) * exp(-x));
        }
    }
    return f;
}
// The race's speed as a share of its last (at speed from CV_FIRE, gathering to 1 at CV_MEET, as cv_launch's slope), dying away
// over a few tenths after the impact: what the leading end's heat keys off.
fn cvg_red_spd(t: f32) -> f32 {
    if (t <= CV_FIRE) {
        return 0.0;
    }
    if (t < CV_MEET) {
        return (CV_SNAP + (1.0 - CV_SNAP) * 2.4 * pow((t - CV_FIRE) / (CV_MEET - CV_FIRE), 1.4)) / (CV_SNAP + (1.0 - CV_SNAP) * 2.4);
    }
    return exp(-(t - CV_MEET) / 0.14);
}
// How far the fire has flowed up the column by t, blocks: its speed wanders (a slow noise, never stalling), rushes as the
// columns race (easing back to its own pace over a quarter of a second after the impact, no jump in speed), and in the
// fight rises and falls with the meeting point's movement: rushing on as the Nether drives it up, all but stalling as
// the Aether drives it down (cvg_pushed), carried a little with its drift between the shoves.
fn cvg_flow(t: f32) -> f32 {
    var f = 34.0 * t + 20.0 * fvnoise(vec2<f32>(t * 0.9, 3.7)) + 45.0 * cv_launch(t);
    if (t > CV_MEET) {
        f = f + 49.0 * (1.0 - exp(-(t - CV_MEET) / 0.25)) + cvg_pushed(t, 100.0, -22.0) + 0.3 * cv_wander(t);
    }
    if (t > CV_DRAW) {
        // (driven back down the column into the land as the meeting point comes down: its fire streams downward)
        f = f - 0.9 * (cv_clash_y(CV_DRAW) - cv_meet_y(min(t, CV_HIT)));
    }
    return f;
}
// The fire's strength over the strike: the cracks glowing in the omen, the fissures roaring from the break, harder
// at each surge and over the draw, gone in the burst.
fn cvg_fire(t: f32) -> f32 {
    return (0.25 * cv_beat(t, CV_OMEN + 0.8, CV_BREAK) + 0.75 * cv_beat(t, CV_BREAK, CV_BREAK + 2.5) + 0.4 * cv_flare(t) + 0.8 * cvg_draw(t)) * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 0.3)) * (1.0 - 0.6 * cvg_collapse(t));
}

// ---- the soft parts ------------------------------------------------------------------------------------------------
// The dark smoke rolling up off the fissures: a plume round the target, widening as it climbs, rolling (its noise
// warped by a slower one, climbing), lit by the sun on top and red from the fire under it; split at depth `tc` (the
// red column's axis) into what lies in front of it (returned) and what lies behind (`cvg_back`).
var<private> cvg_back: vec4<f32>;
fn cvg_smoke(v: CvView, tc: f32) -> vec4<f32> {
    cvg_back = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let t = v.t;
    // (before the fire breaks out only a thin wisp off the open cracks, so nothing dark stands over the vent ahead of
    // the eruption; the body of it comes up behind the gout, its top climbing from the land, thrown higher by it)
    let rise = 0.12 * cv_beat(t, CV_BREAK + 0.3, CV_RED0) + 0.88 * cv_beat(t, CV_RED0 + 0.3, CV_RED0 + 2.2);
    let on = rise * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 0.6)) * cvg_k_smoke();
    if (on <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let draw = saturate(cvg_pull(t));
    let blow = cv_beat(t, CV_HIT, CV_HIT + 0.6);
    let top = min(4.0 + 13.0 * (t - CV_BREAK) + 34.0 * smoothstep(CV_RED0, CV_RED0 + 2.2, t), 105.0);
    let bst = cvg_burst(t - CV_RED0);
    let Rb = 104.0 * (1.0 + 2.0 * blow);
    let span = cvg_cyl(v.rd, v.C, Rb, 0.0, top, v.len);
    if (span.x >= span.y) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let N = 8;
    let dt = (span.y - span.x) / f32(N);
    let j = ign(floor(v_uv * frame.resolution.xy * 0.5) + vec2<f32>(fract(t * 7.0) * 41.0, 0.0));
    var front = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var back = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let sun = max(frame.sun.y, 0.0);
    let fire = cvg_fire(t);
    // (the meeting point's light on the smoke's top: the winner's colour, as strong as what is fed into it)
    let fc = cvg_force(t);
    let km = vec3<f32>(0.0, cv_meet_y(t), 0.0);
    let kl = mix(CVG_GOLD, CVG_FLAME, 0.5 + 0.5 * fc.w) * (0.25 + 0.75 * min(1.2 * max(cvg_feed(t).x - 0.6, 0.0), 1.5)) * cvg_clash(t) * cvg_k_glow() * 0.25;
    // (the red column inside it: its light on the smoke round it, the sleeve it burns clear about itself, and the smoke
    // in front of it thinned along the rays that pass near it, so it shows through)
    let con = cvg_col_on(t);
    let ctop = cv_red_top(t);
    let Rc = 2.0 * CV_BEAM_R;
    let dax = cv_vseg(v.rd, v.C, 0.0, ctop).x;
    let thin = 1.0 - 0.6 * con * (1.0 - smoothstep(0.9 * Rc, 2.6 * Rc, dax));
    let cl_c = mix(CVG_EMBER, CVG_FLAME, 0.55) * 1.5 * con * cvg_k_glow();
    for (var i = 0; i < N; i = i + 1) {
        let tt = span.x + (f32(i) + j) * dt;
        let P = v.rd * tt - v.C;
        let y = P.y;
        // (leaning off with the wind as it climbs, pulled in over the draw, blown out in the burst)
        var q = P.xz - vec2<f32>(0.22, 0.1) * y * (1.0 - draw);
        // (blown out low down while the Aether drives the column back into the ground: cvg_punch, from cvg_column)
        let pk = cvg_punch * exp(-max(y, 0.0) / 30.0);
        q = q / ((1.0 - 0.45 * draw + 2.0 * blow) * (1.0 + 0.3 * pk));
        let r = length(q);
        let Rp = 16.0 + 0.5 * y;
        let w = fvnoise3(vec3<f32>(q.x, y - t * 4.0, q.y) * 0.022);
        let n = ffbm3(vec3<f32>(q.x * 0.05 + w * 1.6, y * 0.045 - t * 0.28, q.y * 0.05 - w * 1.2));
        // (thinning to nothing well inside the cylinder it is marched in, whatever the lean and the noise do)
        let bound = 1.0 - smoothstep(0.62 * Rb, 0.94 * Rb, length(P.xz));
        let rc = length(P.xz);
        let sleeve = 1.0 - con * (1.0 - smoothstep(0.7 * Rc, 1.5 * Rc, rc));
        let dens = saturate((1.0 - r / Rp) * 1.1 + (n - 0.52) * 2.4) * smoothstep(1.0, 10.0, y) * (1.0 - smoothstep(top - 30.0, top - 2.0, y)) * on * bound * (1.0 - 0.55 * pk * exp(-r / 26.0)) * sleeve * select(1.0, thin, tt < tc);
        if (dens <= 0.002) {
            continue;
        }
        let a = 1.0 - exp(-dens * 0.055 * dt);
        let lit = (0.06 + 0.5 * sun * saturate(0.3 + y / 90.0 + (n - 0.5))) * v.day + 0.015;
        let under = CVG_EMBER * (exp(-y / 16.0) * 2.2 + exp(-r / 12.0) * 0.8) * (0.4 + fire) + CVG_FLAME * 2.5 * bst * exp(-r / 30.0);
        let dk = P - km;
        let inner = exp(-max(rc - Rc, 0.0) / 11.0) * (1.0 - smoothstep(ctop - 4.0, ctop + 12.0, y)) * (0.55 + 0.9 * (n - 0.3));
        let ce = vec3<f32>(0.05, 0.022, 0.017) * lit * 3.0 + under * 0.35 + kl / (1.0 + dot(dk, dk) / 1600.0) + cl_c * max(inner, 0.0);
        if (tt < tc) {
            front = vec4<f32>(front.rgb + front.a * ce * a, front.a * (1.0 - a));
        } else {
            back = vec4<f32>(back.rgb + back.a * ce * a, back.a * (1.0 - a));
        }
    }
    cvg_back = back;
    return front;
}
// The red column, the Nether's fire, one column from the eruption to the blast: a swelling of light over the vent as
// the strain builds (cvg_strain), then a gout torn out of the ground (cvg_gout: a jet climbing fast and slowing, burning
// out from the top down, throwing up a head of dark smoke that rolls as it climbs, lit red from under); before the
// columns fire a fountain
// standing out of the fissure (surging, its top licking and falling back, billowing wider as it climbs and cooling to
// dark red and soot at its top), gathering into the column's own shape as it draws back over the crouch; then the same
// column racing up, its body, width (a core of CV_BEAM_R), colour and texture as it stands, only longer each moment,
// its leading end hotter and its fire streaming faster with the speed; then standing from the fissure to the meeting
// point: molten orange-yellow in its core through orange and deep red to soot at its torn skin, dark structure through
// it, fire flowing up it at a speed that wanders. In the fight its axis is a straight line up from the target and its
// width its own (a slow drift of a few percent): the struggle shows in its fire, streaming up fast and burning hotter
// while the Nether drives the meeting point up, all but stalling and piling up hot under the meeting point while the
// Aether drives it down, its skin the more turbulent the harder they press; thinner and hotter over the draw, its fire
// streaming downward and piling up hot down its length as the Aether drives the meeting point into the land. Lit from
// inside (each sample's light is its own colour, so thick fire saturates to that colour, never past it: never white).
// Premultiplied colour and transmittance; `cvg_col_t` the depth of its axis along the ray, `cvg_punch` how hard it is
// being driven back into the ground (the smoke blown out low).
const CVG_SOOT: vec3<f32> = vec3<f32>(0.022, 0.013, 0.012);
const CVG_DEEP: vec3<f32> = vec3<f32>(0.32, 0.025, 0.008);
const CVG_ORANGE: vec3<f32> = vec3<f32>(1.05, 0.24, 0.03);
const CVG_MOLTEN: vec3<f32> = vec3<f32>(1.85, 0.6, 0.11);
const CVG_HOTCORE: vec3<f32> = vec3<f32>(2.6, 1.45, 0.55);
// q (four values a step of `x` apart) read at x, linearly, held past its ends.
fn cvg_q4(q: vec4<f32>, x: f32) -> f32 {
    let u = clamp(x, 0.0, 3.0);
    return dot(q, max(vec4<f32>(0.0), vec4<f32>(1.0) - abs(vec4<f32>(u) - vec4<f32>(0.0, 1.0, 2.0, 3.0))));
}
var<private> cvg_col_t: f32;
var<private> cvg_punch: f32 = 0.0;
fn cvg_column(v: CvView) -> vec4<f32> {
    let t = v.t;
    let on = cvg_col_on(t);
    let top = max(cv_red_top(t), 1.0);
    let ax = cv_vseg(v.rd, v.C, 0.0, top);
    cvg_col_t = ax.y;
    cvg_punch = 0.0;
    // (the eruption: the strain before it, the gout and its head of smoke after it)
    let ea = t - CV_RED0;
    let stn = cvg_strain(t);
    var go = vec4<f32>(0.0);
    var glife = 0.0;
    var hlife = 0.0;
    if (cvg_gout_on(t) && ea > 0.0) {
        go = cvg_gout(ea);
        glife = 1.0 - smoothstep(1.4, 3.8, ea);
        hlife = smoothstep(0.0, 0.25, ea) * (1.0 - smoothstep(2.2, 5.5, ea));
    }
    if (on <= 0.0 && stn <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let pull = cvg_pull(t);
    let cl = cvg_clash(t);
    // (the Nether driving the meeting point up, and the Aether driving it down: the shared kick's two halves; and the
    // Aether driving it all the way down from CV_DRAW, the smoke blown out low as the meeting point nears the land)
    let fc = cvg_force(t);
    let driven = max(-fc.x, 0.0) * cl;
    let dsc = cvg_descent(t);
    cvg_punch = max(driven, dsc * (1.0 - smoothstep(25.0, 100.0, top)));
    // (the fountain, gathering into the column's shape over the crouch; the race's speed for its leading end)
    let fount = 1.0 - cv_beat(t, CV_CROUCH, CV_FIRE);
    let spd = cvg_red_spd(t);
    let gather = cv_beat(t, CV_CROUCH, CV_FIRE) * (1.0 - cv_beat(t, CV_FIRE, CV_FIRE + 0.25));
    // (the fountain's top surging: a wandering noise, so its gouts come at uneven times)
    let topv = top * (1.0 + fount * 0.3 * (fvnoise(vec2<f32>(t * 1.5, 8.1)) - 0.42));
    let drift = 1.0 + 0.04 * (fvnoise(vec2<f32>(t * 0.35, 5.1)) - 0.5) * cl;
    let R0 = 2.0 * CV_BEAM_R * drift * (1.0 - 0.5 * pull);
    let Rb = max(R0 * 3.2 + 6.0, (go.w / 0.85 + 8.0) / 0.72 * step(0.0, hlife - 1.0e-4));
    let span = cvg_cyl(v.rd, v.C, Rb, -2.0, max(topv + R0 * mix(1.0, 2.4, fount), (go.z + 1.15 * go.w) * step(0.0, glife + hlife - 1.0e-4)), v.len);
    if (span.x >= span.y) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let N = 14 + i32(frame.resolution.x < 0.0);
    let dt = (span.y - span.x) / f32(N);
    let j = ign(floor(v_uv * frame.resolution.xy * 0.5) + vec2<f32>(0.0, fract(t * 5.0) * 29.0));
    let flow = cvg_flow(t);
    let spin = t * 1.6;
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let bst = cvg_burst(ea);
    let bright0 = (0.85 + 0.45 * pull + 0.25 * gather + 0.35 * dsc + 0.5 * bst) * on * cvg_k_glow();
    // (the fight as it travels along the column: one of the Nether's shoves climbs it from the vent as fresh fire at
    // about 260 blocks a second, reaching the top as the shove lands (read ahead by the climb's time); one of the
    // Aether's runs down it from the top as fire piled back, at about 170 (read behind))
    var kup = vec4<f32>(0.0);
    var kdn = vec4<f32>(0.0);
    if (cl > 0.0) {
        kup = vec4<f32>(cv_kick(t), cv_kick(t + 0.2), cv_kick(t + 0.4), cv_kick(t + 0.6));
        kdn = vec4<f32>(kup.x, cv_kick(t - 0.12), cv_kick(t - 0.24), cv_kick(t - 0.36));
    }
    let soot = CVG_SOOT * (0.35 + 0.65 * v.day);
    let lead_l = 10.0 + 30.0 * spd;
    // (the column's own body only under the jet's head while the gout climbs, so it comes up with it)
    let cin = select(1.0, 0.0, ea <= 0.0);
    let th_r = 2.4 * (1.0 - exp(-max(ea, 0.0) / 1.1));
    let rcs = vec2<f32>(cos(th_r), sin(th_r));
    for (var i = 0; i < N; i = i + 1) {
        let tt = span.x + (f32(i) + j) * dt;
        let P = v.rd * tt - v.C;
        let y = P.y;
        let h = saturate(y / topv);
        let rp = length(P.xz);
        // (the bound's own fade: nothing reaches the cylinder it is marched in)
        let bound = 1.0 - smoothstep(0.72 * Rb, 0.95 * Rb, rp);
        if (bound <= 0.0) {
            continue;
        }
        let dtop = max(topv - y, 0.0);
        let drv = max(cvg_q4(kup, dtop / 52.0), 0.0) * cl;
        let dvn = max(-cvg_q4(kdn, dtop / 20.4), 0.0) * cl;
        let turb = 0.9 + 0.6 * min(drv + dvn, 1.5) + 0.5 * dsc;
        let bright = bright0 + (0.35 * drv - 0.1 * dvn) * on * cvg_k_glow();
        let yy = y - flow;
        let tw = y * 0.05 - spin;
        let cs = vec2<f32>(cos(tw), sin(tw));
        let q = vec2<f32>(P.x * cs.x - P.z * cs.y, P.x * cs.y + P.z * cs.x) / R0;
        let n = ffbm3(vec3<f32>(q.x * 1.7, yy * 0.05, q.y * 1.7));
        let n2 = fvnoise3(vec3<f32>(q.x * 4.6 + n * 1.5, yy * 0.17, q.y * 4.6));
        // (the shape: a wide foot; the fountain billowing out toward its top; its leading end a little wider)
        let lead = spd * exp(-max(topv - y, 0.0) / lead_l);
        let foot = 1.0 + 0.7 * exp(-max(y, 0.0) / 7.0);
        let bill = mix(1.0, 0.75 + 0.5 * h, fount);
        let R = R0 * foot * bill * (1.0 + 0.12 * lead);
        let rr = rp / R;
        // (its end ragged: licks above the fountain's top, a cleaner end while it races; in the clash thinned out
        // over a longer, torn stretch under the meeting point, where the front's tongues carry it on)
        let ke = cl * (1.0 - fount);
        let lick = (n - 0.5) * R0 * mix(mix(0.6, 2.2, fount), 1.2, ke);
        let endf = 1.0 - smoothstep(topv - R0 * mix(0.5, 0.9, ke), topv + R0 * mix(mix(0.3, 1.0, fount), 0.1, ke), y + lick);
        // (a solid core, its skin torn)
        let solid = smoothstep(0.62, 0.3, rr);
        var dens = saturate((1.0 - rr) * 1.8 + (n - 0.5) * mix(2.1, 0.8, solid) + (n2 - 0.5) * turb * mix(1.0, 0.35, solid) + 1.2 * solid) * endf * smoothstep(-2.0, 1.5, y) * bound * cin;
        if (ea < 1.0) {
            dens = dens * smoothstep(go.x + 2.0, go.x - 6.0, y);
        }
        // (how hot: hottest in the core, cooling to its skin and up the fountain, dark veins of soot torn through it;
        // hotter at its leading end, hotter where a shove of its own is climbing it, piling up hot over a fixed stretch
        // under the meeting point where one of the Aether's is running down it, and as the Aether drives it into the
        // ground; its skin torn where either is passing)
        let vein = smoothstep(0.42, 0.26, n2) * smoothstep(0.45, 0.8, rr);
        let pile = (dvn + 0.9 * dsc) * exp(-dtop / 24.0);
        var heat = saturate(1.55 - rr * 1.3 + (n - 0.5) * 1.0 + (n2 - 0.5) * 0.4 - 0.45 * h * fount + 0.3 * gather + 0.18 * pull + 0.15 * drv - 0.08 * dvn + 0.45 * lead + 0.4 * pile - 0.65 * vein);
        // (the strain before the eruption: a swelling of light over the vent, no body, brighter the nearer it gives)
        if (stn > 0.0) {
            let sw = stn * exp(-pow(rp / (6.0 + 8.0 * stn), 2.0) - pow(max(y, 0.0) / (3.0 + 12.0 * stn), 2.0)) * (0.6 + 0.8 * n2) * bound;
            acc = vec4<f32>(acc.rgb + acc.a * mix(CVG_ORANGE, CVG_MOLTEN, stn) * sw * 0.08 * min(dt, 8.0), acc.a);
        }
        // (the gout: a jet torn out of the ground, widening as it climbs and as it ages, burning out from the top down;
        // over it the head of dark smoke it throws up, rolling about its own ring as it climbs, lit red from under)
        var under = 0.0;
        if (glife + hlife > 0.0) {
            let rs = R0 * (0.75 + 0.6 * saturate(y / max(go.x, 1.0))) * (1.0 + 0.3 * ea);
            let ls = (n - 0.5) * R0 * 1.4;
            let gs = saturate((1.0 - rp / rs) * 1.7 + (n - 0.5) * 1.6 + (n2 - 0.5) * 0.8) * smoothstep(go.x + 3.0, go.x - 8.0, y + ls) * glife * smoothstep(-2.0, 1.0, y);
            var gh = 0.0;
            var gd = gs;
            let yc = go.z - 0.55 * go.w;
            let cy = y - yc;
            if (hlife > 0.0 && abs(cy) < 1.4 * go.w && rp < 1.35 * go.w) {
                let cx = rp - 0.5 * go.w;
                let rx = cx * rcs.x + cy * rcs.y;
                let ry = -cx * rcs.y + cy * rcs.x;
                let dir = P.xz / max(rp, 1.0e-3);
                let Q = vec3<f32>(dir.x * (rx + 0.5 * go.w), ry - ea * 4.0, dir.y * (rx + 0.5 * go.w));
                let nh = ffbm3(Q * 0.075 + vec3<f32>(3.1, 0.0, 1.7));
                let hd = length(vec2<f32>(rp * 0.85, cy * 1.05)) / go.w;
                let dh = saturate((1.0 - hd) * 2.2 + (nh - 0.5) * 2.6) * hlife * mix(1.0, 0.3, smoothstep(1.2, 4.5, ea)) * bound;
                // (fire in its heart for its first instants, then smoke)
                let hh = 0.95 * exp(-ea / 0.45) * saturate(1.3 - hd + (nh - 0.5));
                gh = select(gh, hh, dh > gd);
                gd = max(gd, dh);
            }
            // (the stem burns below the fire's top and goes to smoke over it)
            let sh = saturate(1.45 - rp / rs * 1.1 + (n - 0.5) * 0.9) * smoothstep(go.y + 6.0, go.y - 10.0, y) * (0.6 + 0.4 * exp(-ea / 1.2));
            gh = select(gh, sh, gs >= gd);
            under = gd * (0.3 + 1.6 * bst) * exp(-max(y - go.y, 0.0) / 24.0) * (1.0 - smoothstep(0.3, 0.6, gh));
            heat = (heat * dens + gh * gd) / max(dens + gd, 1.0e-4);
            dens = max(dens, gd);
        }
        if (dens <= 0.002) {
            continue;
        }
        var ce = mix(soot, CVG_DEEP, smoothstep(0.08, 0.3, heat));
        ce = mix(ce, CVG_ORANGE, smoothstep(0.3, 0.58, heat));
        ce = mix(ce, CVG_MOLTEN, smoothstep(0.62, 0.9, heat));
        // (the molten core: white-orange down its middle, the column's own heart, not its skin)
        ce = mix(ce, CVG_HOTCORE, smoothstep(0.9, 1.0, heat) * smoothstep(0.42, 0.15, rr) * (1.0 - 0.6 * fount * h));
        ce = ce * mix(1.0, bright, smoothstep(0.1, 0.4, heat)) + CVG_EMBER * under * 0.5 * cvg_k_glow();
        // (soot is thick and dark; the fire thinner, so its depth shows)
        let a = 1.0 - exp(-dens * mix(0.55, 0.36, heat) * dt);
        acc = vec4<f32>(acc.rgb + acc.a * ce * a, acc.a * (1.0 - a));
    }
    return acc;
}
// The meeting point: two jets driven into each other head on, with no shape of their own. Stuff streams up the fire
// and down the light into the contact, is turned aside there and thrown outward across the axis, and flies on by
// itself: it slows, thins, tears into shreds and burns out with age. Every size is fixed (the spray's reach is where
// what was thrown has died out); what changes with the fight is how much is fed in (cvg_feed), and that is read at
// retarded time: what is r blocks out left the contact cvg_ej_age(r) seconds ago, so a surge leaves the contact as a
// denser, brighter band racing out through the spray while its outline stays where it is. Over the spray's bearings
// gusts come and go on their own clock (slow noise in bearing and emission time), and now and then a jet breaks out
// at a hashed bearing and time. All the spray's textures are functions of bearing and emission time, so each patch
// keeps its heading and is seen leaving, travelling and dying.
// The ejecta's flight: r(a) = CVG_EJ_REACH (1 - e^(-a / CVG_EJ_TAU)), 100 blocks a second as it leaves, slowing
// (still some 30 as it burns out round 60 blocks); the breakout jets' own, faster and further (still 55 as they die
// round 80); the slab's bound; pulses along the columns' ends, blocks a second.
const CVG_EJ_REACH: f32 = 80.0;
const CVG_EJ_TAU: f32 = 0.8;
const CVG_JET_REACH: f32 = 130.0;
const CVG_JET_TAU: f32 = 0.9;
const CVG_SPRAY_RB: f32 = 88.0;
const CVG_COL_V: f32 = 150.0;
// How far the fire's tongues reach up into the light and the light's blades down into the fire, blocks.
const CVG_TONGUE: f32 = 20.0;
const CVG_BLADE: f32 = 24.0;
fn cvg_ej_age(r: f32) -> f32 {
    return -CVG_EJ_TAU * log(1.0 - min(r / CVG_EJ_REACH, 0.985));
}
// What is fed into the contact at time tr: (how much: about 0.6 at rest in the fight, up to ~1.5 on a surge, more as
// the light drives down, ~2.4 in the impact's burst; who is driving it, about -1..1, positive the Nether). The
// shared clock's shoves, the drive down, a slow unevenness and the impact's burst; 0 before the impact and gone over
// the held breath.
fn cvg_feed(tr: f32) -> vec2<f32> {
    let s = tr - CV_MEET;
    if (s <= 0.0) {
        return vec2<f32>(0.0);
    }
    var p = 0.0;
    var k = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        let u = tr - cv_surge(i);
        if (u > 0.0 && u < 2.5) {
            let q = cv_surge_amp(i) / 40.0 * cv_push(u, cv_surge_atk(i));
            p = p + q;
            k = k + cv_surge_sign(i) * q;
        }
    }
    let on = smoothstep(0.0, 0.3, s) * (1.0 - smoothstep(CV_HIT - 0.45, CV_HIT - 0.05, tr));
    let ud = saturate((tr - CV_DRAW) / (CV_HIT - CV_DRAW));
    let dr = ud * ud;
    let wan = 0.1 * sin(1.37 * tr + 0.4) + 0.07 * sin(2.83 * tr + 2.1);
    let f = on * (0.62 + wan + 0.6 * min(p, 1.2) + 0.55 * dr) + 1.7 * exp(-s / 0.28) * smoothstep(0.0, 0.015, s);
    return vec2<f32>(f, clamp(k - 0.9 * dr, -1.0, 1.0) * on);
}
// The contact's scale (blocks), fixed: in at the impact, tightening a little over the draw, gone in the held breath.
// The arcs and the sharp glow key off it.
fn cvg_knot_r(t: f32) -> f32 {
    let s = cv_since_meet(t);
    if (s <= 0.0) {
        return 0.5;
    }
    return max(17.0 * (1.0 - 0.3 * cvg_pull(t)) * (1.0 - exp(-s / 0.05)) * (1.0 - 0.94 * cvg_collapse(t)), 0.5);
}
// Who is winning at the contact now (positive the Nether), the drive down counted for the Aether.
fn cvg_wk(t: f32) -> f32 {
    return clamp(cvg_force(t).w - 0.9 * cvg_descent(t), -1.0, 1.0);
}
// Colours of the front: the light's pale gold and the fire's red.
const CVG_KGOLD: vec3<f32> = vec3<f32>(1.0, 0.9, 0.72);
const CVG_KFIRE: vec3<f32> = vec3<f32>(1.05, 0.19, 0.02);
// The columns' ends through each other near the axis: the fire's tongues up into the light and the light's blades
// down into the fire, their patterns streaming toward the contact at their own columns' speeds; each end brighter
// while its side drives and broken up while it is beaten, both read at the time what is there passed the contact.
fn cvg_overlap(v: CvView, M: vec3<f32>, Ro: f32, fnow: f32, pull: f32) -> vec4<f32> {
    let t = v.t;
    let Lu = CVG_TONGUE;
    let Ld = CVG_BLADE;
    let span = cvg_cyl(v.rd, M, 1.6 * Ro, -(Ld + 16.0), Lu + 16.0, v.len);
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (span.x >= span.y) {
        return acc;
    }
    let N = 7 + i32(frame.resolution.x < 0.0);
    let dt = (span.y - span.x) / f32(N);
    let j = ign(floor(v_uv * frame.resolution.xy * 0.5) + vec2<f32>(fract(t * 3.0) * 17.0, 5.0));
    let flf = 0.08 * cvg_flow(t);
    let fll = 2.4 * t + cvg_pushed(t, -0.6, 2.0) + 3.0 * pull;
    for (var i = 0; i < N; i = i + 1) {
        let tt = span.x + (f32(i) + j) * dt;
        let p = v.rd * tt - M;
        let r = length(p.xz);
        let rr = r / Ro;
        if (rr > 1.3) {
            continue;
        }
        // (two scales of the fire's own turbulence streaming up at different speeds, so it evolves rather than slides;
        // the light's blades long along the axis, narrow across it, streaming down)
        let nA = fvnoise3(vec3<f32>(p.x * 0.1, p.y * 0.06 - flf, p.z * 0.1));
        let nB = fvnoise3(vec3<f32>(p.x * 0.21 + 5.3, p.y * 0.13 - 1.7 * flf, p.z * 0.21 + 7.1));
        let nf = 0.62 * nA + 0.38 * nB;
        let n2 = fvnoise3(vec3<f32>(p.x * 0.22, p.y * 0.035 + fll, p.z * 0.22));
        // (the fight as it was when what is here passed the contact)
        let fe = cvg_feed(t - abs(p.y) / CVG_COL_V);
        let lf = max(-fe.y, 0.0);
        let ll = max(fe.y, 0.0);
        let topF = Lu * (1.9 * nf - 0.45);
        var fF = smoothstep(topF + 2.0, topF - 5.0, p.y) * smoothstep(-(Ld + 16.0), -6.0, p.y) * smoothstep(1.25, 0.45 + 0.25 * nf, rr);
        fF = fF * saturate(1.0 - lf * 1.6 * smoothstep(0.55, 0.3, nf) - 0.3 * lf);
        let botL = -Ld * (1.9 * n2 - 0.45);
        var fL = smoothstep(botL - 2.0, botL + 5.0, p.y) * smoothstep(Lu + 16.0, 5.0, p.y) * smoothstep(1.1, 0.3 + 0.3 * n2, rr);
        fL = fL * saturate(1.0 - ll * 1.6 * smoothstep(0.55, 0.3, n2) - 0.3 * ll);
        let dens = fF * 1.9 + fL * 1.4;
        if (dens <= 0.003) {
            continue;
        }
        // (the fire: red and orange, deep red and soot in its folds; the light pearl and pale gold, sky blue at its
        // edge; where both are thick, hot: molten orange into pale gold, never white, the hotter the more is fed)
        let fr = mix(CVG_DEEP * 0.6, mix(CVG_KFIRE, CVG_MOLTEN * 0.75, smoothstep(0.55, 0.8, nf)), smoothstep(0.32, 0.55, nf)) * (1.0 + 0.5 * ll);
        let lt = mix(CVG_SKYB * 0.5, mix(CVG_KGOLD * 0.85, CVG_PEARL * 0.95, smoothstep(0.6, 0.85, n2)), smoothstep(0.2, 0.5, n2)) * 0.8 * (1.0 + 0.5 * lf);
        var ce = (fr * fF * 1.9 + lt * fL * 1.4) / dens;
        let hot = saturate(fF * fL * 2.2) * (0.45 + 0.3 * fe.x + 0.5 * pull);
        ce = (ce + mix(CVG_MOLTEN * 0.6, CVG_KGOLD * 0.8, 0.5 + 0.4 * (n2 - nf)) * hot) * (0.7 + 0.35 * fe.x);
        let a = 1.0 - exp(-dens * 0.13 * dt);
        acc = vec4<f32>(acc.rgb + acc.a * ce * a, acc.a * (1.0 - a));
    }
    return acc;
}
// The spray thrown out across the axis from the contact: two torn layers, the light's over the contact's plane and
// the fire's under it, the fire's shreds lifting and the light's sinking as they age so they cross and mix out
// toward the edge; each torn in streaks by bearing and emission time, breaking into shreds as it ages; gusts and
// breakout jets over its bearings. Sampled through the slab it lies in; what lies beyond depth `tc` along the ray (the
// axis) goes to `cvg_spray_back`, so the columns' ends can be laid between the two.
var<private> cvg_spray_back: vec4<f32>;
// A gaussian layer of width w, its middle y below the point, averaged over the heights y - hy .. y + hy.
fn cvg_layer(y: f32, hy: f32, w: f32) -> f32 {
    let k = 1.2 / w;
    return 0.886 * w * (tanh(k * (y + hy)) - tanh(k * (y - hy))) / (2.0 * hy);
}
fn cvg_spray_soft(v: CvView, M: vec3<f32>, Ro: f32, tc: f32) -> vec4<f32> {
    let t = v.t;
    let H = 20.0;
    let span = cvg_cyl(v.rd, M, CVG_SPRAY_RB, -H, H, v.len);
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var bk = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    cvg_spray_back = bk;
    if (span.x >= span.y) {
        return acc;
    }
    let N = 7 + i32(frame.resolution.x < 0.0);
    let dt = (span.y - span.x) / f32(N);
    let j = ign(floor(v_uv * frame.resolution.xy * 0.5) + vec2<f32>(5.0, fract(t * 3.0) * 23.0));
    // (half the height a step spans: each step takes the layers' whole share of its stretch of the ray, so a thin
    // layer crossed steeply is never stepped over)
    let hy = max(0.5 * dt * abs(v.rd.y), 1.0e-3);
    for (var i = 0; i < N; i = i + 1) {
        let tt = span.x + (f32(i) + j) * dt;
        let p = v.rd * tt - M;
        let r = length(p.xz);
        let d = p.xz / max(r, 1.0e-3);
        // (when what is here left the contact, and what was fed then)
        let a = cvg_ej_age(r);
        let tr = t - a;
        let fd = cvg_feed(tr);
        // (a breakout jet: in a slot of 1.2 s of emission time, now and then one bearing throws a narrow jet for a
        // fraction of a second, faster and further than the rest, still flying as it burns out)
        let aj = -CVG_JET_TAU * log(1.0 - min(r / CVG_JET_REACH, 0.985));
        let trj = t - aj;
        let sl = floor(trj / 1.2);
        var jet = 0.0;
        let hj = fh21(vec2<f32>(sl, 41.0));
        if (hj < 0.65) {
            let t0 = (sl + 0.1 + 0.5 * fh21(vec2<f32>(sl, 43.0))) * 1.2;
            let du = 0.22 + 0.3 * fh21(vec2<f32>(sl, 47.0));
            let ang = TAU * fh21(vec2<f32>(sl, 53.0));
            let wj = smoothstep(t0, t0 + 0.05, trj) * (1.0 - smoothstep(t0 + du - 0.08, t0 + du, trj));
            jet = wj * exp(-(1.0 - dot(d, vec2<f32>(cos(ang), sin(ang)))) / 0.0035) * (1.0 - smoothstep(0.45, 0.85, aj)) * min(cvg_feed(trj).x, 1.0);
        }
        if (fd.x <= 0.002 && jet <= 0.002) {
            continue;
        }
        // (a slow turbulence over the bearings in emission time (the circle of bearings drifting through a field, so
        // its pattern changes without turning): it ripples the sheet and bends its streaks, carried out with them)
        let wn = fvnoise(d * 2.3 + vec2<f32>(tr * 1.1 + 7.0, -tr * 0.9));
        let th = 1.8 + 0.1 * r;
        let dy = p.y - (wn - 0.5) * th * 1.3;
        let wa = 0.9 * (wn - 0.5);
        let dw = d * cos(wa) + vec2<f32>(-d.y, d.x) * sin(wa);
        // (gusts: a slower pattern of the same kind, so for a second or so one sector throws far more than the
        // others, then another)
        let g = fvnoise(d * 0.75 + vec2<f32>(tr * 0.6 + 11.0, tr * 0.45));
        let gust = 0.2 + 2.1 * smoothstep(0.3, 0.85, g);
        // (fine threads by bearing, the fire's and the light's interleaved (one field: the fire where it is high, the
        // light where it is low), torn across into shreds by a coarser field that thins them as they age)
        let thr = fvnoise3(vec3<f32>(dw * 22.0, tr * 1.6));
        let tear = fvnoise3(vec3<f32>(dw * 4.5 + vec2<f32>(31.0, 7.0), tr * 3.2));
        let brk = 0.3 + 0.25 * smoothstep(0.2, 1.15, a);
        let tr_k = saturate((tear - brk) * 2.6);
        let stF = smoothstep(0.42, 0.75, thr);
        let stL = smoothstep(0.58, 0.25, thr);
        let lift = 4.0 * a * a;
        let w = 0.75 * th;
        let yF = dy + 0.45 * th - lift;
        let yL = dy - 0.45 * th + lift;
        let oF = cvg_layer(yF, hy, w);
        let oL = cvg_layer(yL, hy, w);
        let oJ = cvg_layer(dy, hy, w);
        let amt = 2.4 * (0.55 + 0.45 * min(fd.x, 1.8)) * gust * tr_k * (1.0 - smoothstep(0.65, 1.2, a)) * smoothstep(0.3 * Ro, 1.1 * Ro, r);
        let dF = amt * oF * stF * (1.0 + 0.6 * max(fd.y, 0.0) - 0.3 * max(-fd.y, 0.0));
        let dL = amt * oL * stL * (1.0 + 0.6 * max(-fd.y, 0.0) - 0.3 * max(fd.y, 0.0));
        let dJ = jet * oJ * (0.4 + 0.8 * tear) * 1.6;
        let dens = dF + dL + dJ;
        if (dens <= 0.003) {
            continue;
        }
        // (the fire's shreds red to molten, the light's pale gold to pearl; the hottest by the contact; as bright as
        // what was fed when they left)
        let hc = 1.0 + 0.3 * exp(-r / (0.7 * Ro));
        let cF = mix(CVG_KFIRE, CVG_MOLTEN * 0.8, tear) * hc * 1.3;
        let cL = mix(CVG_KGOLD, CVG_PEARL, tear) * hc * 1.15;
        let cJ = select(cL, cF, fh21(vec2<f32>(sl, 59.0)) < 0.5) * 1.3;
        // (luminous and thin: it glows more than it hides; cooling as it ages)
        let ce = (cF * dF + cL * dL + cJ * dJ) / dens * (0.35 + 0.65 * fd.x + 0.5 * jet) * (0.5 + 0.5 * exp(-a / 0.8));
        let em = 1.0 - exp(-dens * 0.3 * dt);
        let al = 1.0 - exp(-dens * 0.1 * dt);
        if (tt < tc) {
            acc = vec4<f32>(acc.rgb + acc.a * ce * em, acc.a * (1.0 - al));
        } else {
            bk = vec4<f32>(bk.rgb + bk.a * ce * em, bk.a * (1.0 - al));
        }
    }
    cvg_spray_back = bk;
    return acc;
}
fn cvg_knot(v: CvView) -> vec4<f32> {
    let t = v.t;
    let s = cv_since_meet(t);
    let on = smoothstep(0.0, 0.04, s) * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 0.12));
    if (on <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let pull = cvg_pull(t);
    let M = v.C + vec3<f32>(0.0, cv_meet_y(t), 0.0);
    let Ro = 1.45 * CV_BEAM_R * (1.0 - 0.25 * pull);
    let fnow = cvg_feed(t).x;
    let bright = (0.9 + 0.7 * pull) * on * cvg_k_glow();
    let o = cvg_overlap(v, M, Ro, fnow, pull);
    // (the spray split at the axis: its near side over the columns' ends, its far side under them)
    let f = cvg_spray_soft(v, M, Ro, cv_pt(v.rd, M).y);
    let b = cvg_spray_back;
    let out = cvg_over(f, cvg_over(o, b));
    return vec4<f32>(out.rgb * bright, out.a);
}
// ---- the sundering: the blast as the two realms tearing apart along the seam --------------------------------------
// The seam's bearing as a unit vector along it (x, z) and the unit normal pointing into the Nether's half (cvg_side's).
fn cvg_seam_dir() -> vec2<f32> {
    let s = cv_seam();
    return vec2<f32>(cos(s), sin(s));
}
fn cvg_seam_n() -> vec2<f32> {
    let s = cv_seam();
    return vec2<f32>(-sin(s), cos(s));
}
// The last instant before the blast, 0..1 over its last third of a second: everything drawn to the point, dimming
// (the held breath). 0 from the blast on.
fn cvg_collapse(t: f32) -> f32 {
    if (t >= CV_HIT) {
        return 0.0;
    }
    let u = saturate((t - (CV_HIT - 0.34)) / 0.33);
    return u * u * (3.0 - 2.0 * u);
}
// The surges' front over the land `a` seconds after the blast, blocks from the target: out at CV_V (the land's wave,
// the knockback and the sound keep to it) to 230, then slowing to a stop short of 300.
fn cvg_front(a: f32) -> f32 {
    let x = CV_V * max(a, 0.0);
    if (x < 230.0) {
        return x;
    }
    return 230.0 + 70.0 * (1.0 - exp(-(x - 230.0) / 70.0));
}
// A rise with an overshoot that settles: 0 at a = 0, past 1, back to 1.
fn cvg_spring(a: f32, tau: f32, w: f32) -> f32 {
    if (a <= 0.0) {
        return 0.0;
    }
    return 1.0 - exp(-a / tau) * cos(w * a);
}
// The sheet of light on the seam `a` seconds after the blast: (its half-length along the seam, its top, its strength,
// its thickness). It tears up to the rift in an instant and races out both ways along the seam to CVG_SHEET_L, burns
// at full strength for about a second and a half (an overshoot on the hit), then tears into curtains (cvg_tear) that
// dim, shorten and go as the rift closes.
const CVG_SHEET_L: f32 = 250.0;
fn cvg_tear(a: f32) -> f32 {
    return smoothstep(1.4, 5.2, a);
}
fn cvg_sheet(a: f32) -> vec4<f32> {
    if (a <= 0.0) {
        return vec4<f32>(0.0);
    }
    let t = CV_HIT + a;
    let race = 1.0 - exp(-a / 0.14);
    let curt = cvg_tear(a);
    let close = 1.0 - cv_beat(t, CV_CLOSE, CV_END);
    let L = mix(CVG_SHEET_L * race, cv_rift_size(t).x * 1.6 + 30.0 * close, curt * curt);
    let top = CV_RIFT_Y * (1.0 - exp(-a / 0.06));
    let I = smoothstep(0.0, 0.02, a) * (1.0 + 0.8 * exp(-a / 0.15)) * (1.0 - 0.12 * smoothstep(0.2, 1.4, a)) * mix(1.0, 0.16, curt) * (1.0 - 0.5 * smoothstep(5.0, 9.0, a)) * close;
    let w = 3.0 + 7.0 * smoothstep(0.0, 0.3, a) * (1.0 - curt);
    return vec4<f32>(L, top, I, w);
}
// How much of the sheet's light reaches P (target-relative): falling off away from the seam's plane, within its length
// and height.
fn cvg_sheet_light(P: vec3<f32>, sh: vec4<f32>) -> f32 {
    if (sh.z <= 0.0) {
        return 0.0;
    }
    let sd = abs(dot(P.xz, cvg_seam_n()));
    let u = abs(dot(P.xz, cvg_seam_dir())) / max(sh.x, 1.0);
    return sh.z * (1.0 - smoothstep(0.75, 1.3, u)) * (1.0 - smoothstep(0.8 * sh.y, sh.y + 30.0, P.y)) / (1.0 + pow(sd / (30.0 + 0.15 * length(P.xz)), 2.0));
}
// The two halves thrown apart, and what stays in the air. On the Nether's half a wall of black ash and fire 60-100
// high rolling out over the land at the front's speed (cvg_front), rolled about its own head and lit orange from
// inside, leaving a burning pall in banks that sinks and thins over 8-12 seconds. On the Aether's half a wall of
// white-gold light and dense pale mist as big, glowing, leaving a luminous mist that lifts into columns drawn up toward
// the rift. Each a half-ring out from the target, meeting the other only at the seam (no cloud over the seam itself),
// lit by the sheet. Marched in one bounded cylinder, its steps packed close to the eye (near masses pass the camera;
// far off the masses are big), each its own colour and absorption: honest transmittance.
fn cvg_sunder(v: CvView) -> vec4<f32> {
    let a = cv_since_hit(v.t);
    if (a <= 0.0 || a > 26.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let kb = cvg_k_burst();
    let Rf = cvg_front(a);
    let Rb = min(Rf + 50.0, 320.0);
    // (the mist's columns reaching up to the rift: the bound tall only while they do)
    let up = smoothstep(0.8, 3.0, a) * (1.0 - smoothstep(15.0, 20.0, a));
    let Hb = max(mix(135.0 * kb, CV_RIFT_Y + 12.0, up), (kb * min(25.0 + 15.0 * max(a - 1.2, 0.0), 165.0) + 10.0) * step(1.2, a) * step(a, 25.0));
    let span = cvg_cyl(v.rd, v.C, Rb, -3.0, Hb, v.len);
    if (span.x >= span.y) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let Ls = span.y - span.x;
    // (steps: long through empty air, shorter where the medium is, each short enough to add about half an optical
    // depth at most, so a dense face is never drawn in terraces at the steps' spacing; a long step that lands deep in a
    // dense mass backs up and comes in again short. No offset from pixel to pixel: any pattern in it, fine or smooth,
    // prints at half size. The count is read at run time, so the loop stays a loop)
    let N = 62 + i32(frame.resolution.x < 0.0);
    let dB = clamp(Ls / 20.0, 5.0, 30.0);
    // (inside a part's envelope the steps are never longer than this, however thin it is there)
    let dIn = clamp(Ls / 54.0, 3.5, 7.5);
    let Nn = cvg_seam_n();
    let sh = cvg_sheet(a);
    let t = v.t;
    // (each part's life: the walls, the pall, the mist, the smoke rising off the crater)
    let wall_n = 1.0 - smoothstep(3.0, 8.5, a);
    let wall_a = 1.0 - smoothstep(2.5, 7.5, a);
    let pall = smoothstep(0.1, 1.0, a) * (1.0 - smoothstep(9.0, 24.0, a));
    let mist = smoothstep(0.15, 1.2, a) * (1.0 - smoothstep(10.0, 21.0, a));
    let plume = smoothstep(1.2, 4.0, a) * (1.0 - smoothstep(15.0, 25.0, a));
    // (the Nether's wall: up hard, overshooting, slumping as it slows; the Aether's: quicker, and still climbing)
    let Hn = max(88.0 * kb * cvg_spring(a, 0.22, 3.6) * (1.0 - 0.3 * smoothstep(1.0, 7.0, a)), 1.0);
    let Ha = max(78.0 * kb * cvg_spring(a, 0.16, 5.5) + 9.0 * a, 1.0);
    // (the pall's top sinking; it thins as it does)
    let Hp = kb * mix(80.0, 34.0, smoothstep(1.0, 14.0, a));
    let thin = mix(1.0, 0.45, smoothstep(2.5, 14.0, a));
    let ys = CV_RIFT_Y * smoothstep(0.6, 4.5, a);
    let close = 1.0 - cv_beat(t, CV_CLOSE, CV_END);
    let conv = smoothstep(2.0, 12.0, a);
    let hot = exp(-a / 2.2);
    let warm = exp(-a / 5.0);
    let young = exp(-a / 1.4);
    let sun = normalize(frame.sun.xyz);
    let sunh = max(sun.y, 0.0);
    // (the daylight on it goes as the world's does: the masses dark against the dusk, lit from inside)
    let dim = mix(1.0, 0.4, cv_dusk(t));
    let wind = vec2<f32>(3.2, 1.3) * a;
    let rp = min(0.97 * Rf, 290.0);
    // (the smoke off the crater: a column climbing over its Nether half, clear of the seam, widening as it climbs and
    // leaning away from the seam)
    let Hc = kb * min(25.0 + 15.0 * max(a - 1.2, 0.0), 165.0);
    let Cc = Nn * 0.74 * CVG_CRATER_R;
    // (where the ray crosses the sheet's plane: what lies past it inside its outline is hidden by it as much as it
    // burns, so the transmittance handed to the sharp parts is what stands in front of it)
    let an = dot(v.rd.xz, Nn);
    var tcs = 1.0e9;
    if (abs(an) > 1.0e-4) {
        let tc = dot(v.C.xz, Nn) / an;
        if (tc > 0.0) {
            tcs = tc;
        }
    }
    let Pc = v.rd * min(tcs, 1.0e5) - v.C;
    let uc = abs(dot(Pc.xz, cvg_seam_dir())) / max(sh.x, 1.0);
    let past = min(sh.z * 1.2, 0.92) * (1.0 - 0.6 * cvg_tear(a)) * (1.0 - smoothstep(0.7, 1.0, uc)) * (1.0 - smoothstep(0.5 * sh.y, 0.9 * sh.y, Pc.y)) * step(0.0, Pc.y);
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var tt = span.x + 0.5 * dB;
    var cap = dB;
    var last = dB;
    var backs = 0;
    for (var i = 0; i < N; i = i + 1) {
        if (acc.a < 0.02 || tt >= span.y) {
            break;
        }
        let P = v.rd * tt - v.C;
        let y = P.y;
        let r = length(P.xz);
        let sd = dot(P.xz, Nn);
        let side = smoothstep(-10.0, 10.0, sd);
        let bound = 1.0 - smoothstep(Rb - 50.0, Rb - 6.0, r);
        // (each part's envelope first, no noise: most steps end here)
        let xn = r - 0.96 * Rf;
        // (the wall riding the front, trailing off behind it into the pall)
        let en_s = wall_n * smoothstep(12.0, -10.0, xn) * exp(min(xn, 0.0) / (25.0 + 15.0 * min(a, 2.0))) * (1.0 - smoothstep(Hn * 0.75, Hn * 1.35 + 6.0, y));
        // (the pall: out to the front, clear over the seam itself, the clear gap widening as it climbs so the two
        // halves lean away from the sheet)
        let clr = smoothstep(4.0, 34.0, abs(sd) - 0.45 * max(y, 0.0));
        let en_p = pall * (1.0 - smoothstep(rp - 30.0, rp + 6.0, r)) * (1.0 - smoothstep(Hp * 0.4, Hp, y)) * mix(1.0, 0.6, saturate(r / max(rp, 1.0))) * clr;
        // (the crater's smoke column)
        let pq = P.xz - Cc - Nn * 0.17 * max(y, 0.0) * smoothstep(30.0, 140.0, y);
        let rc0 = 0.5 * CVG_CRATER_R * (1.0 + 0.25 * saturate(y / max(Hc, 1.0)) + 0.35 * exp(-max(y, 0.0) / 14.0));
        let pr = length(pq) / rc0;
        let en_c = plume * (1.0 - smoothstep(0.8, 1.15, pr)) * (1.0 - smoothstep(Hc * 0.45, Hc + 12.0, y)) * smoothstep(-6.0, 4.0, y);
        let en_n = side * max(max(en_s, en_p), en_c);
        let xa = r - Rf;
        let en_as = wall_a * smoothstep(12.0, -10.0, xa) * exp(min(xa, 0.0) / (25.0 + 15.0 * min(a, 2.0))) * (1.0 - smoothstep(Ha * 0.75, Ha * 1.35 + 8.0, y));
        // (the mist: a low layer thinning as it lifts, and its columns in a cone narrowing toward the rift)
        let hy = saturate(y / CV_RIFT_Y);
        let rc = mix(min(Rf, 240.0), CV_RIFT_R * mix(0.95, 0.35, conv) * close + 14.0, pow(hy, 0.6));
        let low = (1.0 - smoothstep(22.0, 48.0, y)) * (1.0 - smoothstep(3.5, 12.0, a));
        let strm = smoothstep(4.0, 24.0, y) * (1.0 - smoothstep(ys - 60.0, ys, y)) * (1.0 - smoothstep(CV_RIFT_Y - 25.0, CV_RIFT_Y + 4.0, y));
        let en_am = mist * (1.0 - smoothstep(rc - 40.0, rc, r)) * max(low, strm) * clr;
        let en_a = (1.0 - side) * max(en_as, en_am);
        if ((en_n + en_a) * bound <= 0.003) {
            last = max(min(dB, cap), (span.y - tt) / f32(N - i));
            tt = tt + last;
            cap = min(cap * 1.7, dB);
            continue;
        }
        let dir = P.xz / max(r, 1.0);
        // (the Nether's stuff carried out with the front and rolled about its head: the foot thrown out ahead, the top
        // falling back; the pall drifting downwind and churning; the crater's smoke climbing)
        let cx = xn + 0.35 * Hn;
        let cy = y - 0.42 * Hn;
        // (the roll turns about a radian and a half at most: past that its shear winds the noise into rings)
        let th = 1.6 * (1.0 - exp(-1.2 * a)) * exp(-(cx * cx + cy * cy) / (Hn * Hn * 1.4));
        let cs = vec2<f32>(cos(th), sin(th));
        let rx = cx * cs.x + cy * cs.y;
        let ry = -cx * cs.y + cy * cs.x;
        let Qf = vec3<f32>(P.x - dir.x * (0.8 * Rf + rx - cx) - wind.x * pall, y + (ry - cy) + 0.9 * a, P.z - dir.y * (0.8 * Rf + rx - cx) - wind.y * pall);
        let wc = smoothstep(0.0, 0.25, en_c);
        let Qn = mix(Qf, vec3<f32>(P.x - 1.5 * a, y - 7.0 * a, P.z + 40.0), wc);
        // (the Aether's carried out and lifting; its columns leaning in toward the rift as they climb)
        let pin = 1.0 + 1.3 * conv * smoothstep(30.0, CV_RIFT_Y, y);
        let Qa = vec3<f32>(P.x * pin - dir.x * 0.9 * Rf, y - 18.0 * a, P.z * pin - dir.y * 0.9 * Rf);
        let Q = mix(Qa, Qn, side);
        let fq = mix(0.034, mix(0.03, 0.038, wc), side);
        // (billows: a large rolling shape whose edges are bitten into round lumps by a finer one, the lumps turning
        // over as they go; a sample a little above says whether this point lies under a mass: its underside is dark)
        let p1 = Q * fq + vec3<f32>(0.0, -mix(0.1, 0.05, side) * a, 0.0);
        let o1 = fvnoise3(p1);
        // (each finer octave fades to its mean where the steps are too long to follow it, so none aliases into bands)
        let ds = min(last, dIn);
        let lod1 = saturate(2.2 - ds * fq * 2.07 * 2.2);
        let n1 = 0.62 * o1 + 0.38 * mix(0.5, fvnoise3(p1 * 2.07 + vec3<f32>(5.1, 1.3, 7.7)), lod1);
        let lod = saturate(2.2 - ds * fq * 3.1 * 2.2);
        let n2 = mix(0.5, fvnoise3(Q * (fq * 3.1) + vec3<f32>(n1 * 1.7, -mix(0.45, 0.2, side) * a, 0.6 * n1)), lod);
        let o1u = fvnoise3(p1 + vec3<f32>(0.2, 0.42, -0.1));
        let n = 0.7 * n1 + 0.3 * n2;
        let bite = 0.3 * (1.0 - n2);
        // (big masses with clear air between: nearer and farther banks, never one even murk; each bank lumpy, carrying
        // the smaller billows)
        let braw = fvnoise3(Q * 0.012 + vec3<f32>(0.0, -0.03 * a, 0.02 * a));
        let bank = smoothstep(0.45, 0.66, braw + 0.25 * (n1 - 0.5));
        // the Nether's: the wall thick, its top in billows; the pall in lumpy banks; the crater's column dense
        var dn = en_s * side * saturate((n1 - 0.15 - 0.34 * saturate(y / Hn) - bite) * 3.0 + 0.3 * exp(-max(y, 0.0) / 14.0));
        dn = max(dn, en_p * side * (0.02 + 0.98 * bank) * saturate((n1 - 0.21 - bite) * 3.0) * 0.55 * thin);
        // (its outline bitten by the billows, so it rises as lumps, never as a smooth tube)
        dn = max(dn, en_c * side * saturate((n1 + 0.62 - 0.85 * pr - 0.45 * saturate(y / max(Hc, 1.0)) - bite) * 3.0) * 0.75);
        // the Aether's: the wall dense with soft edges; the low mist in rags; the columns long strands twisting as
        // they are drawn up, clear air between them
        var da = en_as * saturate((n1 - 0.26 - 0.25 * saturate(y / Ha) - 0.6 * bite) * 2.4);
        if (en_am * (1.0 - side) > 0.0) {
            // (the twist slow with height: far from the axis a quick one shears the strands into level bands)
            let tw = 0.0042 * y * (0.4 + conv) + 0.05 * a;
            let cw = vec2<f32>(cos(tw), sin(tw));
            let qx = Qa.x * cw.x - Qa.z * cw.y;
            let qz = Qa.x * cw.y + Qa.z * cw.x;
            let sn = fvnoise3(vec3<f32>(qx * 0.026, Qa.y * 0.011 - 0.1 * a, qz * 0.026) + vec3<f32>(n1 * 1.4, 0.0, n2 * 0.9));
            let st = smoothstep(0.42, 0.85, sn) * (0.55 + 0.45 * n2) * strm + low * (0.1 + 0.9 * bank) * saturate((n1 - 0.36 - 0.6 * bite) * 2.6);
            da = max(da, en_am * st * 0.6);
        }
        // (nothing right at the eye walls the view: it thins over the first steps, so what passes the camera is wisps)
        let near = smoothstep(0.5, 9.0, tt);
        let sig = (dn * 0.32 + da * 0.085 * (1.0 - side)) * bound * near * (1.0 - past * smoothstep(tcs - 6.0, tcs + 6.0, tt));
        // (this step's length: about half an optical depth, never under a block and a half (more far off), never over
        // the long step; a long step that came down deep in a mass goes back and comes in short)
        // (and never so short that the steps left could not reach the far end: a ray never stops short)
        let want = max(clamp(0.55 / max(sig, 1.0e-4), max(1.5, 0.006 * tt), min(dIn, cap)), (span.y - tt) / f32(N - i));
        if (backs < 3 && i > 0 && last > 1.8 * want && sig * last > 0.6) {
            backs = backs + 1;
            tt = tt - last + want;
            last = want;
            cap = want;
            continue;
        }
        let dt = want;
        last = dt;
        tt = tt + dt;
        cap = min(cap * 1.7, dB);
        // (fire showing in the gaps between the billows low in the wall: light with no ash in front of it)
        let gf = en_s * side * hot * exp(-max(y, 0.0) / (0.35 * Hn + 5.0)) * (1.0 - saturate(dn * 2.5)) * smoothstep(0.4, 0.75, n2) * smoothstep(6.0, 40.0, tt) * bound;
        acc = vec4<f32>(acc.rgb + acc.a * mix(CVG_ORANGE, CVG_MOLTEN, smoothstep(0.6, 0.9, n2)) * gf * 0.03 * min(dt, 12.0), acc.a);
        if (sig <= 0.0004) {
            continue;
        }
        // (light: the sun on the tops of the masses, the sky, the sheet near the seam brightest on the thin edges)
        let under_m = saturate((o1u - o1) * 6.0 + 0.25);
        let lit = (0.2 + 0.85 * sunh * saturate(0.25 + y / mix(Ha * 1.3 + 40.0, Hn * 1.3 + 20.0, side) + (n1 - 0.5) * 1.3)) * v.day * dim * (1.0 - mix(0.4, 0.75, side) * under_m) + 0.02;
        let sl = cvg_sheet_light(P, sh) * (1.25 - 0.6 * n) * (1.0 - 0.65 * under_m * side);
        // the Nether's: black ash lit from inside: fire in its body while it is hot, brightest low; embers glowing deep
        // in the pall and the crater's column, red from below, dying out slowly
        let heat = hot * smoothstep(0.42, 0.85, n2) * exp(-max(y, 0.0) / (0.45 * Hn + 6.0)) * smoothstep(-60.0, 0.0, xn) * smoothstep(6.0, 40.0, tt) * en_s + 0.5 * warm * smoothstep(0.55, 0.9, n2) * exp(-max(y, 0.0) / 18.0) * max(en_p, en_c);
        let ash = vec3<f32>(0.04, 0.02, 0.015) * (0.6 + 0.7 * n1);
        let fire = mix(CVG_DEEP, mix(CVG_ORANGE, CVG_MOLTEN, smoothstep(0.5, 1.0, heat)), smoothstep(0.05, 0.4, heat));
        let deep = saturate((1.0 - under_m) * 0.6 + 0.4 * n2);
        let pocket = 0.06 + 0.94 * smoothstep(0.55, 0.8, n);
        let inner = mix(CVG_BLOOD, CVG_ORANGE, deep * deep * pocket) * pocket * (0.3 * warm * exp(-max(y, 0.0) / (0.25 * max(Hn, Hp) + 8.0)) * max(en_s, en_p) + 0.7 * exp(-max(y, 0.0) / 45.0) * en_c * exp(-max(a - 3.0, 0.0) / 14.0) * (0.35 + 0.65 * deep));
        let under = CVG_EMBER * (0.2 * hot * exp(-max(y, 0.0) / (0.25 * Hn + 6.0)) * smoothstep(6.0, 40.0, tt) + 0.07 * warm * exp(-max(y, 0.0) / 12.0));
        let cn = ash * lit + fire * heat * 3.0 + inner * smoothstep(4.0, 30.0, tt) + under + (ash * 3.0 + CVG_EMBER * 0.07) * sl;
        // the Aether's: pearl and pale gold, lit from within while it is young (white-hot only in its first instant),
        // the mist glowing, brighter near the rift; its shaded undersides clear sky blue
        let gold = mix(vec3<f32>(1.0, 0.86, 0.62), CVG_PEARL, n2);
        let cool = vec3<f32>(0.42, 0.58, 0.95);
        let gc = mix(gold, CVG_WHITE, 0.85 * exp(-a / 0.35));
        let glow = 0.05 + 0.8 * young * smoothstep(0.4, 0.8, n) * smoothstep(4.0, 30.0, tt) + 0.5 * mist * (0.4 + 0.6 * n2) + 0.6 * smoothstep(110.0, CV_RIFT_Y, y) * close * mist;
        let ca = mix(gc, cool, 0.6 * under_m) * lit * 0.4 + gc * glow * (1.0 - 0.45 * under_m) + mix(CVG_GOLD, CVG_WHITE, 0.3) * sl * 0.5;
        let ce = mix(ca, cn, side);
        let al = 1.0 - exp(-sig * dt);
        acc = vec4<f32>(acc.rgb + acc.a * al * ce, acc.a * (1.0 - al));
    }
    return acc;
}
// The soft part (half size at QUALITY FAST): the smoke (in front of the column and behind it), the red column and a
// halo round it (it reads from far off), the fire along the cracks, the knot; from the blast the sundering.
fn cv_ground_soft(v: CvView) -> vec4<f32> {
    let t = v.t;
    var out = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if (t < CV_HIT + 0.7) {
        let col = cvg_column(v);
        let sm = cvg_smoke(v, cvg_col_t);
        let fl = cv_cracks_soft(v);
        let on = cvg_col_on(t);
        var halo = vec3<f32>(0.0);
        if (on > 0.0) {
            let s = cv_vseg(v.rd, v.C, 0.0, cv_red_top(t));
            let w = 18.0 + 0.02 * s.y;
            // (for far eyes only: up close the body itself reads)
            halo = mix(CVG_EMBER, CVG_FLAME, 0.45) * 0.6 * w / (s.x + w) * on * (1.0 + 0.6 * max(cvg_kick(t), 0.0) + 1.5 * cvg_pull(t)) * cv_vis(v, s.y) * cvg_k_glow() * smoothstep(90.0, 330.0, s.y);
        }
        out = cvg_over(sm, cvg_over(col, cvg_over(vec4<f32>(halo, 1.0), cvg_back)));
        out = cvg_over(fl, out);
        out = cvg_over(cvg_knot(v), out);
    }
    if (t > CV_HIT) {
        out = cvg_over(cvg_sunder(v), out);
    }
    return vec4<f32>(out.rgb * v.fade, mix(1.0, out.a, v.fade));
}

// ---- the sharp parts -----------------------------------------------------------------------------------------------
// One cell of sparks on a vertical plane facing the camera through O (camera-relative), `off` blocks along the view:
// the sparks' rest frame is the plane's coordinates less `shift`'s, divided by `scale` (a cloud expanding or
// tightening), each column of cells climbing at about `rise` blocks a second; a cell of `cell` blocks holds a spark
// with probability `fill`, `rw` blocks across (never under a pixel). Returns (its glow, its own hash 0..1, 0, the
// ray's distance to the plane).
fn cvg_sparks(v: CvView, O: vec3<f32>, off: f32, shift: vec3<f32>, scale: f32, rise: f32, cell: f32, fill: f32, rw: f32, seed: f32) -> vec4<f32> {
    let nh = normalize(O.xz + vec2<f32>(1.0e-3, 0.0));
    let n = vec3<f32>(nh.x, 0.0, nh.y);
    let dn = dot(v.rd, n);
    if (dn < 0.08) {
        return vec4<f32>(0.0);
    }
    let Q = O + n * off;
    let th = dot(Q, n) / dn;
    if (th <= 0.5 || th > v.len) {
        return vec4<f32>(0.0);
    }
    let P = v.rd * th - shift;
    let right = vec3<f32>(-nh.y, 0.0, nh.x);
    var g = vec2<f32>(dot(P, right), P.y) / scale;
    let colid = floor(g.x / cell);
    let sp = 0.55 + 0.9 * fh21(vec2<f32>(colid, seed));
    g.y = g.y - rise * sp * v.t / scale + sin(v.t * 1.3 * sp + colid) * cell * 0.07;
    let id = floor(g / cell);
    let h = fh21(id + vec2<f32>(seed * 17.0, seed));
    if (h > fill) {
        return vec4<f32>(0.0);
    }
    let h2 = fh21(id + vec2<f32>(seed * 3.0 + 9.0, 31.0));
    let c = (id + 0.2 + 0.6 * vec2<f32>(h2, fract(h2 * 13.7))) * cell;
    let d = length(g - c) * scale;
    let r = max(rw, cvg_px(th) * 0.9);
    return vec4<f32>(exp(-d * d / (r * r)) * (rw / r), h / max(fill, 1.0e-3), 0.0, th);
}
// Embers and ash: rising off the fissures from the break, drawn into the knot over the draw, thrown out with the blast,
// falling as ash and dying embers over the Nether's half in the aftermath.
fn cvg_embers(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let t = v.t;
    var c = col;
    let a = cv_since_hit(t);
    if (a > 0.0 && a < 7.0) {
        // (thrown: a cloud of sparks blown out from the burst, falling)
        let B = v.C + vec3<f32>(0.0, CV_BURST - 4.0 * a * a, 0.0);
        let sc = 1.0 + 26.0 * (1.0 - exp(-a / 0.8));
        for (var i = 0; i < 3; i = i + 1) {
            let fi = f32(i);
            let s = cvg_sparks(v, B, (fi - 1.0) * 9.0 * sc, B, sc, 0.0, 2.6, 0.22, 0.3, 11.0 + fi);
            if (s.x > 0.004) {
                let rr = length(v.rd * s.w - B) / sc;
                let keep = 1.0 - smoothstep(9.0, 12.0, rr);
                let side = cvg_side((v.rd * s.w - v.C).xz, 30.0);
                let tint = mix(mix(CVG_GOLD, CVG_WHITE, 0.4), mix(CVG_EMBER, CVG_CORE, s.y), side);
                c = c + tint * s.x * keep * 6.0 * exp(-a / 2.2) * smoothstep(0.08, 0.3, a) * (1.0 - smoothstep(4.5, 7.0, a));
            }
        }
    }
    let ea = t - CV_RED0;
    if (ea > 0.0 && ea < 4.5) {
        // (the eruption's: embers and burning ash thrown up with the gout, spreading, slowing, falling back and dying)
        let B = v.C + vec3<f32>(0.0, 8.0 + 62.0 * (1.0 - exp(-ea / 0.45)) - 4.5 * ea * ea, 0.0);
        let sc = 1.0 + 16.0 * (1.0 - exp(-ea / 0.6));
        for (var i = 0; i < 3; i = i + 1) {
            let fi = f32(i);
            let s = cvg_sparks(v, B, (fi - 1.0) * 5.0 * sc, B, sc, 0.0, 2.2, 0.3, 0.28, 61.0 + fi);
            if (s.x > 0.004) {
                let rr = length(v.rd * s.w - B) / sc;
                let keep = 1.0 - smoothstep(3.5, 5.5, rr);
                let cool = smoothstep(0.3, 2.5, ea + 0.8 * s.y);
                let tint = mix(mix(CVG_CORE, CVG_FLAME, cool), CVG_EMBER * 0.35, step(0.7, s.y) * cool);
                c = c + tint * s.x * keep * 7.0 * exp(-ea / 1.6) * smoothstep(0.0, 0.08, ea) * (1.0 - smoothstep(3.2, 4.5, ea)) * v.veil;
            }
        }
    }
    let sm = cv_since_meet(t);
    if (sm > 0.0 && sm < 4.0) {
        // (the impact's sparks: both colours flung out from the meeting point, slowing, falling, dying)
        let B = v.C + vec3<f32>(0.0, CV_MEET_Y - 5.0 * sm * sm, 0.0);
        let sc = 1.0 + 30.0 * (1.0 - exp(-sm / 0.45));
        for (var i = 0; i < 3; i = i + 1) {
            let fi = f32(i);
            let s = cvg_sparks(v, B, (fi - 1.0) * 7.0 * sc, B, sc, 0.0, 2.2, 0.26, 0.25, 41.0 + fi);
            if (s.x > 0.004) {
                let rr = length(v.rd * s.w - B) / sc;
                let keep = 1.0 - smoothstep(6.0, 9.0, rr);
                let tint = select(mix(CVG_GOLD, CVG_WHITE, 0.35), mix(CVG_EMBER, CVG_CORE, fract(s.y * 7.0)), s.y < 0.5);
                c = c + tint * s.x * keep * 7.0 * exp(-sm / 1.1) * smoothstep(0.0, 0.06, sm) * (1.0 - smoothstep(2.6, 4.0, sm)) * v.veil;
            }
        }
    }
    if (a > 1.5) {
        // (falling: ash and the odd dying ember over the Nether's half)
        let on = cv_beat(a, 1.5, 5.0) * (1.0 - cv_beat(a, 12.0, 22.0));
        if (on > 0.0) {
            for (var i = 0; i < 2; i = i + 1) {
                let fi = f32(i);
                let s = cvg_sparks(v, v.C, (fi - 0.5) * 70.0, v.C, 1.0, -3.5 - 2.0 * fi, 4.5, 0.4, 0.28, 21.0 + fi);
                if (s.x > 0.004) {
                    let P = v.rd * s.w - v.C;
                    let r = length(P.xz);
                    let keep = (1.0 - smoothstep(110.0, 170.0, r)) * smoothstep(0.0, 4.0, P.y) * (1.0 - smoothstep(120.0, 170.0, P.y)) * cvg_side(P.xz, 25.0);
                    let glowing = step(0.85, s.y);
                    let ash = CVG_ASH * (0.25 + 0.75 * v.day) * (0.5 + 0.5 * s.y);
                    c = mix(c, ash, saturate(s.x * keep * on * (1.0 - glowing)) * 0.9) + CVG_EMBER * s.x * keep * on * glowing * 2.5;
                }
            }
        }
    }
    if (a > 0.8) {
        // (rising: motes of light over the Aether's half, lifting with the mist toward the rift)
        let on = cv_beat(a, 0.8, 3.0) * (1.0 - cv_beat(a, 9.0, 15.0));
        if (on > 0.0) {
            for (var i = 0; i < 2; i = i + 1) {
                let fi = f32(i);
                let s = cvg_sparks(v, v.C, (fi - 0.5) * 60.0, v.C, 1.0, 7.0 + 4.0 * fi, 8.0, 0.035, 0.3, 51.0 + fi);
                if (s.x > 0.004) {
                    let P = v.rd * s.w - v.C;
                    let r = length(P.xz);
                    let keep = (1.0 - smoothstep(120.0, 180.0, r)) * smoothstep(2.0, 10.0, P.y) * (1.0 - smoothstep(190.0, 250.0, P.y)) * (1.0 - cvg_side(P.xz, 25.0));
                    c = c + mix(CVG_GOLD, CVG_WHITE, 0.5 * s.y) * s.x * keep * on * 1.4;
                }
            }
        }
    }
    return c;
}
// The shells out from the meeting point: 0 the impact's (at CV_IMPACT_V from where the columns struck), 1-6 each
// surge's (smaller, slower, from where the meeting point was as its shove peaked). (seconds since it, its middle's height,
// its radius, its strength; strength 0 when it is not out)
fn cvg_shell(i: i32, t: f32) -> vec4<f32> {
    if (i == 0) {
        let s = cv_since_meet(t);
        if (s <= 0.0 || s > 1.6) {
            return vec4<f32>(0.0);
        }
        let I = smoothstep(0.0, 0.025, s) * exp(-s / 0.55) * (1.0 - smoothstep(0.85, 1.55, s));
        return vec4<f32>(s, CV_MEET_Y, CV_IMPACT_V * s, I);
    }
    // (let go as the shove is moving the meeting point fastest, from where it is then; as strong as its reach)
    let k = i - 1;
    let t0 = cv_surge(k) + cv_surge_atk(k);
    let u = t - t0;
    if (u <= 0.0 || u > 1.3 || t > CV_HIT) {
        return vec4<f32>(0.0);
    }
    let I = 0.42 * cv_surge_amp(k) / 32.0 * smoothstep(0.0, 0.05, u) * exp(-u / 0.45) * (1.0 - smoothstep(0.7, 1.25, u));
    // (fast out of the point, slowing as it spreads; the big shoves' further)
    let R = (CV_RING_V * 0.55 * (1.0 - exp(-u / 0.55)) * 1.6 + 30.0 * u) * (1.0 + 0.4 * smoothstep(24.0, 38.0, cv_surge_amp(k)));
    return vec4<f32>(u, cv_meet_y(t0), R, I);
}
fn cvg_shell_tint(i: i32) -> vec3<f32> {
    if (i == 0) {
        return mix(CVG_WHITE, CVG_CORE, 0.3);
    }
    return select(mix(CVG_GOLD, CVG_WHITE, 0.3), mix(CVG_FLAME, CVG_CORE, 0.4), cv_surge_sign(i - 1) > 0.0);
}
// One shell in the air: a soft sphere of radius R and thickness w round M (camera-relative). The ray's path through it
// (1 face on, more toward its limb, a soft fall past it: no edge), each of its two crossings shown only in front of the
// world and fading near the eye; the picture behind its limb bent outward; patchy, tinted by the half each crossing
// lies over. A ring in the level plane through M rides with it (`ring` its strength).
fn cvg_shock(v: CvView, col: vec3<f32>, M: vec3<f32>, R: f32, w: f32, I: f32, tint: vec3<f32>, ring: f32, seed: f32) -> vec3<f32> {
    var c = col;
    let p = cv_pt(v.rd, M);
    if (p.x < R + 2.5 * w) {
        let x = p.x;
        let lim = R / sqrt(max(R * R - x * x, 0.0) + 0.9 * w * R) * exp(-pow(max(x - R, 0.0) / w, 2.0));
        let hh = sqrt(max(R * R - x * x, 0.0));
        let tn = p.y - hh;
        let tf = p.y + hh;
        let vn = cv_vis(v, tn) * smoothstep(2.0, 18.0, tn);
        let vf = cv_vis(v, tf) * smoothstep(2.0, 18.0, tf);
        let dn = normalize(v.rd * max(tn, 0.0) - M + vec3<f32>(0.0, 1.0e-3, 0.0));
        let pz = 0.45 + 0.9 * fvnoise(dn.xz * 6.0 + vec2<f32>(dn.y * 4.0 + seed, seed * 1.7));
        let side = cvg_side((v.rd * max(tn, 0.0) - v.C).xz, 25.0);
        let tc = mix(tint, tint * mix(vec3<f32>(1.0, 0.9, 0.7), vec3<f32>(1.0, 0.55, 0.3), side), 0.5);
        let k = I * min(lim, 6.0) * pz * 0.5 * (vn + vf) * v.veil;
        c = c + tc * k * 0.24 + c * k * 0.14;
        // (the bending at its limb: the picture there pushed outward from the middle)
        let bend = I * smoothstep(0.55, 1.0, x / R) * exp(-pow(max(x - R, 0.0) / w, 2.0)) * vn;
        if (bend > 0.01) {
            let pm = project_rel(M);
            let asp = frame.resolution.x / frame.resolution.y;
            let dir = normalize((v_uv - pm.xy) * vec2<f32>(asp, 1.0) + vec2<f32>(1.0e-5, 0.0));
            let o = dir * bend * 0.02 / vec2<f32>(asp, 1.0);
            let s0 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, v_uv, 0.0).rgb);
            let s1 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, v_uv - o, 0.0).rgb);
            c = c + (s1 - s0);
        }
    }
    if (ring > 0.0 && abs(v.rd.y) > 1.0e-4) {
        let tp = M.y / v.rd.y;
        if (tp > 0.0) {
            let Q = v.rd * tp - M;
            let rq = length(Q.xz);
            let wr = 1.5 * w + 2.0;
            let x = rq - R * 1.03;
            if (abs(x) < 3.0 * wr) {
                let torn = 0.35 + 0.9 * fvnoise(vec2<f32>(atan2(Q.z, Q.x) * 9.0 + seed, R * 0.02));
                let k = exp(-x * x / (wr * wr)) * torn * ring * I * cv_vis(v, tp) * smoothstep(2.0, 18.0, tp) * v.veil;
                c = c + tint * k * 0.5 + c * k * 0.2;
            }
        }
    }
    return c;
}
// A shock disc flaring out sideways from the meeting point on a big shove (`big` 0..1), flying out with its shell
// (`sh`, cvg_shell's) at about half its radius and fading with it: a thick torn rim (a ring of rolling air with a
// round section, thicker than a block or two) round a thinner sheet that thickens toward it, in the level plane
// through M (camera-relative). The ray is sampled at four depths across the slab it lies in, so the rim has a near
// and a far side, a top and an underside: lit on the side facing the meeting point and on the side its own column
// comes from (the Aether's from above, the Nether's from below), its shade a darker, cooler tone of its colour.
fn cvg_disc(v: CvView, col: vec3<f32>, M: vec3<f32>, sh: vec4<f32>, big: f32, tint: vec3<f32>, up: f32, seed: f32) -> vec3<f32> {
    if (big <= 0.0 || abs(v.rd.y) < 1.0e-4) {
        return col;
    }
    let tp = M.y / v.rd.y;
    if (tp <= 0.0) {
        return col;
    }
    let R = 12.0 + 0.5 * sh.z;
    // (the rim's section: a few blocks, growing as it flies out; never under two pixels)
    let rt = max(2.2 + 0.035 * R, cvg_px(tp) * 2.0);
    let Q0 = v.rd * tp - M;
    if (length(Q0.xz) > R * 1.12 + 3.0 * rt / max(abs(v.rd.y), 0.15)) {
        return col;
    }
    // (four samples along the ray across the slab |y| < 1.6 rt)
    let ds = min(1.6 * rt / abs(v.rd.y), 3.0 * rt) * 0.5;
    var e = 0.0;
    var lit = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        let tk = tp + (f32(i) - 1.5) * ds;
        let Q = v.rd * tk - M;
        let rq = length(Q.xz);
        let ang = atan2(Q.z, Q.x);
        let nz = fvnoise(vec2<f32>(ang * 7.0 + seed, rq * 0.06 - sh.x * 5.0));
        let Re = R * (1.0 + 0.08 * (fvnoise(vec2<f32>(ang * 5.0 + seed, sh.x * 2.0)) - 0.5));
        let rti = rt * (0.7 + 0.6 * nz);
        let d = vec2<f32>(rq - Re, Q.y);
        let dr = length(d);
        let rim = exp(-dr * dr / (rti * rti));
        // (the sheet inside the rim, thickening toward it)
        let sth = rti * 0.45 * pow(saturate(rq / Re), 2.0);
        let fill = exp(-Q.y * Q.y / max(sth * sth, 0.05)) * smoothstep(8.0, 14.0, rq) * (1.0 - smoothstep(-rti, 0.2 * rti, rq - Re)) * (0.25 + 0.7 * nz) * 0.45;
        // (its light: the rim's section facing in toward the meeting point and toward its own column, lit; away, shade)
        let nrm = d / max(dr, 1.0e-3);
        let l = saturate(0.5 - 0.45 * nrm.x + 0.45 * up * nrm.y);
        e = e + rim + fill;
        lit = lit + (rim * (0.35 + 0.9 * l) + fill * (0.5 + 0.5 * nz));
    }
    let k = sh.w * big * cv_vis(v, tp) * smoothstep(2.0, 18.0, tp) * v.veil * min(2.0 * ds / max(rt, 1.0e-3), 2.5) * 0.25;
    let sh_c = tint * mix(vec3<f32>(0.75, 0.3, 0.2), vec3<f32>(0.55, 0.68, 1.0), step(0.0, up));
    let cc = mix(sh_c * 0.45, mix(tint, CVG_WHITE, 0.2), saturate(lit / max(e, 1.0e-3)));
    return col + cc * min(e, 4.0) * k * 1.6 - col * min(e * k * 0.25, 0.35);
}
// The meeting point's sharp parts: the red column's leading end as it races (a glow of its own molten core, as wide as
// its core, as hot as the speed: the column itself is the body behind it), the hard flash as they strike, the shells and
// the ring out from it, each surge's own shell, and the knot's white core through the clash.
fn cvg_meet(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let t = v.t;
    var c = col;
    let spd = cvg_red_spd(t);
    if (spd > 0.003) {
        let top = cv_red_top(t);
        let H = v.C + vec3<f32>(0.0, top - 2.0, 0.0);
        let p = cv_pt(v.rd, H);
        let w = max(CV_BEAM_R * (0.8 + 0.3 * spd), cvg_px(p.y) * 1.5);
        let g = exp(-p.x * p.x / (w * w)) + 0.15 * w / (p.x + w);
        c = c + mix(CVG_MOLTEN, CVG_WHITE, 0.3) * g * 2.2 * spd * cv_vis(v, p.y) * v.veil * cvg_k_glow();
    }
    let s = cv_since_meet(t);
    let M0 = v.C + vec3<f32>(0.0, CV_MEET_Y, 0.0);
    if (s > 0.0 && s < 2.0) {
        // (the flash: a hard white instant as they strike in clear air, letting go fast)
        let p = cv_pt(v.rd, M0);
        let I = (14.0 * exp(-s / 0.05) + 0.7 * exp(-s / 0.22)) * cvg_k_flash();
        let w = 5.0 + 16.0 * (1.0 - exp(-max(s, 0.0) / 0.1));
        let g = exp(-p.x * p.x / (w * w)) + 0.12 * w / (p.x + w);
        c = c + CVG_WHITE * g * I * cv_vis(v, p.y);
        if (s > 0.0) {
            c = mix(c, CVG_WHITE * 1.4, saturate(0.45 * exp(-s / 0.035) * cvg_k_flash()));
        }
    }
    // (the shells: the impact's (with its ring, and a fainter one following), then the surges')
    for (var i = 0; i < 7; i = i + 1) {
        let sh = cvg_shell(i, t);
        if (sh.w <= 0.0) {
            continue;
        }
        let M = v.C + vec3<f32>(0.0, sh.y, 0.0);
        let w = select(3.0 + 6.0 * sh.x, 4.0 + 10.0 * sh.x, i == 0);
        c = cvg_shock(v, c, M, sh.z, w, sh.w, cvg_shell_tint(i), select(0.45, 1.0, i == 0), f32(i) * 3.7);
        if (i > 0) {
            c = cvg_disc(v, c, M, sh, smoothstep(24.0, 38.0, cv_surge_amp(i - 1)), cvg_shell_tint(i), -cv_surge_sign(i - 1), f32(i) * 2.3);
        }
        if (i == 0 && sh.x > 0.05) {
            c = cvg_shock(v, c, M, sh.z * 0.72, w * 1.4, sh.w * 0.45 * smoothstep(0.05, 0.2, sh.x), mix(CVG_GOLD, CVG_FLAME, 0.5), 0.0, 9.1);
        }
    }
    if (s > 0.0 && t < CV_HIT + 0.1) {
        // (where they press hardest: a flat glow in the front's plane, wide across the axis and thin along it (a
        // streak from the side, a torn disc from under), its edge uneven, pale gold into molten orange)
        let M = v.C + vec3<f32>(0.0, cv_meet_y(t), 0.0);
        let p = cv_pt(v.rd, M);
        let pull = cvg_pull(t);
        let Rk = cvg_knot_r(t);
        let X = v.rd * p.y - M;
        let dh = length(X.xz);
        let dd = X.xz / max(dh, 1.0e-3);
        let px = cvg_px(p.y) * 1.5;
        // (its edge uneven by bearing, the pattern changing on its own clock, never turning)
        let wr = max(0.75 * Rk * (0.6 + 0.8 * fvnoise3(vec3<f32>(dd * 2.2, t * 0.5 + 1.3))), px);
        let wv = max(0.1 * Rk, px);
        let dv = X.y;
        let g = exp(-(dh / wr) * (dh / wr) - (dv / wv) * (dv / wv));
        if (g > 1.0e-3) {
            // (as bright as what was fed when the light there left the contact: the middle at once, its edge after)
            let fe = cvg_feed(t - cvg_ej_age(dh)).x;
            c = c + mix(CVG_MOLTEN * 0.6, CVG_KGOLD, 0.5 - 0.35 * cvg_wk(t)) * g * (0.18 + 0.2 * fe + 2.0 * pull) * cv_vis(v, p.y) * v.veil * cvg_k_glow();
        }
    }
    return c;
}
// The light on the land and a glow that hugs it: the cracks' glow (and down in them), the red column's light from
// below on the Nether's side and the gold from the knot on the Aether's, meeting across the seam; the surges' rings
// running out over it; the blast's two fronts; the fireball's light; the crater glowing red and dying.
fn cvg_land(v: CvView, col: vec3<f32>) -> vec3<f32> {
    if (v.sky) {
        return col;
    }
    let t = v.t;
    let a = cv_since_hit(t);
    let P = v.rel - v.C;
    let r = length(P.xz);
    var L = vec3<f32>(0.0);
    var E = vec3<f32>(0.0);
    var shade = 0.0;
    let side = cvg_side(P.xz, 6.0);
    let on = cvg_col_on(t);
    let ea = t - CV_RED0;
    let stn = cvg_strain(t);
    if (stn > 0.0) {
        // (the strain before the eruption: the land round the target glowing from under, flickering as it builds)
        let fl = 0.75 + 0.5 * fvnoise(vec2<f32>(t * 6.0, 2.3));
        L = L + mix(CVG_EMBER, CVG_FLAME, stn) * stn * fl * (1.6 / (1.0 + pow(length(vec2<f32>(r, max(P.y, 0.0) * 1.5)) / 20.0, 2.0)) + 0.25 / (1.0 + pow(r / 60.0, 2.0))) * cvg_k_glow();
    }
    if (on > 0.0) {
        // (lit from the whole height of the fire: the gout's while it burns, so the trees round it go red from above)
        var top = cv_red_top(t);
        if (ea > 0.0 && ea < 7.0) {
            top = max(top, cvg_gout(ea).y);
        }
        let dy = max(P.y - top, 0.0) + max(-P.y, 0.0);
        let dl = length(vec2<f32>(r, dy));
        let bst = cvg_burst(ea);
        let ir = (1.0 + 0.6 * max(cvg_kick(t), 0.0) + 2.0 * cvg_pull(t) + 1.2 * cvg_descent(t) + 2.2 * bst) * on * cvg_k_glow();
        L = L + CVG_FLAME * ir * (1.8 / (1.0 + pow(dl / 46.0, 2.0)) + 0.3 / (1.0 + pow(dl / (130.0 + 90.0 * bst), 2.0))) * mix(0.55, 1.0, side);
    }
    let sm = cv_since_meet(t);
    let kon = smoothstep(0.0, 0.03, sm) * (1.0 - cv_beat(t, CV_HIT, CV_HIT + 0.2));
    if (kon > 0.0) {
        let dm = length(P - vec3<f32>(0.0, cv_meet_y(t), 0.0));
        let ig = (1.0 + min(1.2 * max(cvg_feed(t).x - 0.6, 0.0), 1.5) + 4.0 * cvg_pull(t) + 5.0 * exp(-sm / 0.12)) * kon * cvg_k_glow() * (1.0 - 0.85 * cvg_collapse(t));
        let g = ig / (1.0 + pow(dm / (130.0 * (1.0 - 0.4 * cvg_pull(t))), 2.0));
        L = L + mix(CVG_GOLD * 0.9, CVG_FLAME * 1.3, side) * g;
        // (where the two lights meet on the land, a seam of white)
        let sd = abs(dot(P.xz, vec2<f32>(-sin(cv_seam()), cos(cv_seam()))));
        E = E + CVG_WHITE * exp(-sd / 1.8) * g * 0.12 * (1.0 - smoothstep(60.0, 140.0, r));
    }
    // (the shells from the meeting point passing over the land: a soft band of their light where each meets it)
    for (var i = 0; i < 7; i = i + 1) {
        let sh = cvg_shell(i, t);
        if (sh.w <= 0.0 || sh.z <= sh.y) {
            continue;
        }
        let x = r - sqrt(sh.z * sh.z - sh.y * sh.y);
        let wd = 6.0 + 0.06 * sh.z;
        L = L + cvg_shell_tint(i) * exp(-x * x / (wd * wd)) * sh.w * 0.9 * smoothstep(sh.y, sh.y + 25.0, sh.z);
    }
    if (a > 0.0) {
        // (the two fronts, each on its own half: white-gold light on the Aether's, fire on the Nether's, a little behind)
        let Rf = cvg_front(a);
        let fd = (1.0 - smoothstep(1.5, 4.5, a)) * (0.35 + 0.65 * exp(-a / 0.8)) * 300.0 / (300.0 + Rf);
        let x1 = r - Rf;
        let x2 = r - 0.96 * Rf;
        L = L + mix(CVG_GOLD, CVG_WHITE, 0.15) * (exp(-x1 * x1 / 70.0) * 4.0 + exp(min(x1, 0.0) / 40.0) * step(x1, 0.0) * 0.5) * fd * (1.0 - side);
        L = L + CVG_FLAME * (exp(-x2 * x2 / 110.0) * 4.5 + exp(min(x2, 0.0) / 60.0) * step(x2, 0.0) * 0.8) * fd * side;
        // (under the pall the land glows with embers a while, and lies in its shadow; under the Aether's mist it is
        // lit white-gold)
        L = L + CVG_EMBER * 0.4 * smoothstep(0.5, 2.0, a) * exp(-a / 6.0) * (1.0 - smoothstep(Rf - 40.0, Rf, r)) * side;
        let rp = min(0.97 * Rf, 290.0);
        let under = 1.0 - smoothstep(rp - 30.0, rp + 6.0, r);
        // (the shadow falls in patches under the pall's banks, drifting with them)
        let wd = vec2<f32>(3.2, 1.3) * a * smoothstep(0.1, 1.0, a);
        let bk = smoothstep(0.38, 0.68, fvnoise3(vec3<f32>(P.x - wd.x, 30.0 + 0.9 * a, P.z - wd.y) * 0.012 + vec3<f32>(0.0, -0.03 * a, 0.02 * a)));
        shade = 0.62 * side * under * (0.3 + 0.7 * bk) * smoothstep(0.1, 0.8, a) * (1.0 - smoothstep(7.0, 20.0, a)) * smoothstep(4.0, 34.0, abs(dot(P.xz, cvg_seam_n())));
        L = L + mix(CVG_GOLD, CVG_WHITE, 0.15) * 0.9 * (1.0 - side) * under * smoothstep(0.1, 0.6, a) * (0.4 + 0.6 * exp(-a / 2.0)) * (1.0 - smoothstep(5.0, 14.0, a));
        // (the sheet's light: a white line burnt along the seam, its glare spread over the land each side)
        let sh = cvg_sheet(a);
        if (sh.z > 0.0) {
            let sd = abs(dot(P.xz, cvg_seam_n()));
            let ua = abs(dot(P.xz, cvg_seam_dir())) / max(sh.x, 1.0);
            let ea = sh.z * (1.0 - smoothstep(0.75, 1.05, ua)) * cvg_k_flash();
            let st = mix(mix(CVG_WHITE, CVG_GOLD, 0.35), mix(vec3<f32>(0.9, 0.9, 0.92), vec3<f32>(1.0, 0.3, 0.06), side), smoothstep(0.1, 0.5, a));
            L = L + CVG_WHITE * ea * 2.2 * exp(-sd / 4.0) + st * ea * (1.0 * exp(-sd / 10.0) + 1.3 / (1.0 + pow(sd / 45.0, 2.0)));
            E = E + CVG_WHITE * ea * exp(-sd / 2.5) * 0.6;
        }
        let cg = (1.0 - smoothstep(0.45 * CVG_CRATER_R, 1.05 * CVG_CRATER_R, r)) * smoothstep(0.5, 2.0, a) * exp(-a / mix(6.0, 14.0, side));
        L = L + CVG_EMBER * cg * mix(0.6, 2.0, side) * smoothstep(-1.0, -8.0, P.y);
        E = E + CVG_EMBER * cg * mix(0.02, 0.25, side) * smoothstep(-2.0, -14.0, P.y);
    }
    // (a bright light lifts the land toward its own colour, never far past it)
    let cs = col * (1.0 - shade);
    return cs + cs * L / (1.0 + 0.3 * max(L.r, max(L.g, L.b))) + E;
}
// The arcs thrown off the knot: a few heavy bolts out of its rim, each with a branch, struck anew a couple of times a
// second, flung out sideways as the two jets meet; more of them and longer the harder they press and over the draw,
// torn toward the losing column. Gold off its upper half, red-orange off its lower, each with a wide glow of its colour
// (its light on the smoke and air it crosses). A bolt the force no longer calls for fades out within its own life,
// never cut.
fn cvg_arcs(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let t = v.t;
    let on = smoothstep(CV_MEET, CV_MEET + 0.08, t) * (1.0 - cv_beat(t, CV_HIT - 0.05, CV_HIT));
    if (on <= 0.0) {
        return col;
    }
    let M = v.C + vec3<f32>(0.0, cv_meet_y(t), 0.0);
    let pm = project_rel(M);
    if (pm.z < 0.0) {
        return col;
    }
    var c = col;
    let dM = length(M);
    let asp = frame.resolution.x / frame.resolution.y;
    let toscr = 1.0 / (dM * 2.0 * tan(frame.view_params.w * 0.5));
    let q = (v_uv - pm.xy) * vec2<f32>(asp, 1.0);
    let fl = saturate((cvg_feed(t).x - 0.6) / 0.8);
    let draw = cvg_pull(t);
    let rk = 0.85 * cvg_knot_r(t) * toscr;
    let reach = 46.0 * (1.0 - 0.4 * draw) * toscr;
    if (length(q) > rk + 1.6 * reach) {
        return col;
    }
    let vis = cv_vis(v, dM);
    // (the column's line on the screen, the level way across it, and the way to the loser's column: up while the
    // Nether wins, down while the Aether does)
    let pu = project_rel(M + vec3<f32>(0.0, 12.0, 0.0));
    let du = (pu.xy - pm.xy) * vec2<f32>(asp, 1.0);
    let upn = du / max(length(du), 1.0e-6);
    let across = vec2<f32>(-upn.y, upn.x);
    let thr = 0.3 + 0.5 * fl + 0.4 * draw;
    let wid = max(1.5 * toscr, 1.6 * frame.resolution.w);
    for (var i = 0; i < 3; i = i + 1) {
        let fi = f32(i);
        let rate = 1.7 + 1.3 * fh21(vec2<f32>(fi, 0.7));
        let ph = t * rate + fi * 0.37 + 0.6 * fvnoise(vec2<f32>(t * 1.1, fi * 5.0));
        let ep = floor(ph);
        let fr = fract(ph);
        let want = saturate((thr - fh21(vec2<f32>(ep, fi * 3.1))) / 0.15);
        if (want <= 0.0) {
            continue;
        }
        let ang = fh21(vec2<f32>(ep, fi * 5.7 + 1.0)) * TAU;
        let d0 = normalize(across * cos(ang) + upn * (0.45 * sin(ang)));
        let len = reach * (0.55 + 0.45 * fh21(vec2<f32>(ep, fi + 9.0)));
        let a0 = d0 * rk;
        let sd = ep * 1.7 + fi;
        let tq = t * 1.2;
        let bl = bolt_line(q, a0, a0 + d0 * len, sd, tq, wid);
        // (its branch, forking off part way along at a slant)
        let u0 = 0.35 + 0.3 * fh21(vec2<f32>(ep, fi + 2.0));
        let nr = vec2<f32>(-d0.y, d0.x);
        let bp = a0 + d0 * len * u0 + nr * bolt_disp(len, u0, sd, tq);
        let sg = select(-1.0, 1.0, fh21(vec2<f32>(ep, fi + 4.0)) < 0.5);
        let d1 = normalize(d0 + nr * sg * 0.8);
        let br = bolt_line(q, bp, bp + d1 * len * (1.0 - u0) * 0.75, sd + 3.3, tq, wid * 0.7);
        let core = max(bl.x, br.x * 0.8);
        let glow = max(bl.y, br.y * 0.7);
        let halo = 1.0 / (1.0 + pow(length(q - (a0 + d0 * len * 0.4)) / (len * 0.45 + 1.0e-5), 2.0));
        let life = smoothstep(0.0, 0.05, fr) * pow(1.0 - fr, 1.3) * want;
        let tint = select(CVG_FLAME, CVG_GOLD, dot(d0, upn) + 0.3 * fh21(vec2<f32>(ep, fi * 2.3 + 4.0)) - 0.15 > 0.0);
        c = c + (mix(tint, CVG_WHITE, 0.4) * core * 2.4 + tint * glow * 1.4 + tint * halo * 0.1) * life * on * vis * v.veil * (1.0 - bl.z * 0.4) * (0.8 + 0.3 * fl);
    }
    return c;
}
// The heat haze over the fissures: the picture behind a sheet through the target (facing the camera) shimmering.
fn cvg_haze(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let t = v.t;
    let k = (cvg_fire(t) + 1.2 * cvg_strain(t)) * cvg_k_haze();
    if (k <= 0.02) {
        return col;
    }
    let nh = normalize(v.C.xz + vec2<f32>(1.0e-3, 0.0));
    let dn = dot(v.rd.xz, nh);
    if (dn < 0.1) {
        return col;
    }
    let th = dot(v.C.xz, nh) / dn;
    if (th <= 1.0 || th > v.len - 1.0) {
        return col;
    }
    let P = v.rd * th - v.C;
    let u = dot(P.xz, vec2<f32>(-nh.y, nh.x));
    let m = (1.0 - smoothstep(25.0, 55.0, abs(u))) * smoothstep(-2.0, 4.0, P.y) * (1.0 - smoothstep(20.0, 70.0, P.y)) * (1.0 - smoothstep(v.len - 16.0, v.len - 1.0, th));
    if (m <= 0.0) {
        return col;
    }
    let n = vec2<f32>(fvnoise(vec2<f32>(u * 0.35, P.y * 0.3 - t * 7.0)), fvnoise(vec2<f32>(u * 0.35 + 9.0, P.y * 0.3 - t * 6.0))) - 0.5;
    let o = n * 0.45 / (th * tan(frame.view_params.w * 0.5) * 2.0) * m * k;
    let s0 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, v_uv, 0.0).rgb);
    let s1 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, v_uv + o * vec2<f32>(frame.resolution.y / frame.resolution.x, 1.0), 0.0).rgb);
    return col + (s1 - s0);
}
// The sheet of light on the seam (cvg_sheet), at full size: a slab of light standing on the seam's line through the
// target, the ray's path through it (soft across its thickness, so seen edge-on it is a blinding line, seen face-on a
// solid burning wall), white-hot at its foot and its core over the target, its outline torn into strands at its top
// and ends, its racing ends gold and fire; as it tears (cvg_tear) holes open up it until only curtains are left. Round
// it the air glows: a halo about its outline where the ray crosses its plane, and a glow about its core that reads
// from every bearing. Under the ground side's smoke only as much as shows through it.
// One folded layer of the sheet at (along the seam, height), `a` seconds after the blast, layer `k`, torn by `curt`:
// (its brightness, its slow warp 0..1). The layer is a ribbon whose place along the seam bends with height and time
// (large slow bends carrying smaller quicker ones), so its folds lean, wander and are of many widths; it is bright where
// it folds (two scales of ridges), brighter in knots, and dark where it parts, the gaps opening and closing as they
// drift and widening as it tears.
fn cvg_fold(along: f32, y: f32, a: f32, k: f32, curt: f32) -> vec2<f32> {
    let w1 = fvnoise(vec2<f32>(along * 0.007, y * 0.0055 - a * 0.08));
    let w2 = fvnoise(vec2<f32>(along * 0.022 + k * 1.3, y * 0.014 - a * 0.2));
    let x = along + 80.0 * (w1 - 0.5) + 20.0 * (w2 - 0.5) + 9.0 * k;
    let f1 = fvnoise(vec2<f32>(x * 0.026 + k * 5.1, y * 0.006 - a * 0.06));
    let f2 = fvnoise(vec2<f32>(x * 0.085 + k * 2.3, y * 0.012 - a * 0.15));
    let r1 = 1.0 - abs(2.0 * f1 - 1.0);
    let r2 = 1.0 - abs(2.0 * f2 - 1.0);
    let r2s = r2 * r2;
    let fold = smoothstep(0.25, 1.0, r1) * (0.75 + 0.5 * f2) + r2s * r2s * r2s * 0.35;
    let g = fvnoise(vec2<f32>(along * 0.012 + k * 9.0 + a * 0.06, y * 0.009 - a * 0.18)) + 0.25 * (f2 - 0.5);
    let gap = smoothstep(0.3 + 0.25 * curt, 0.6 + 0.2 * curt, g);
    let knot = smoothstep(0.7, 0.95, fvnoise(vec2<f32>(x * 0.045 + k * 4.0, y * 0.02 - a * 0.35)));
    return vec2<f32>(fold * (0.06 + 0.94 * gap) * (1.0 + 1.2 * knot * gap), w1);
}
fn cvg_sheet_sharp(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let a = cv_since_hit(v.t);
    if (a <= 0.0 || v.t > CV_END + 0.5) {
        return col;
    }
    let sh = cvg_sheet(a);
    if (sh.z <= 0.001 || sh.x < 1.0) {
        return col;
    }
    let S = cvg_seam_dir();
    let Nn = cvg_seam_n();
    let fk = cvg_k_flash();
    let curt = cvg_tear(a);
    var c = col;
    // (the glow in the air round it: about the core over the target from any bearing, and about its outline where the
    // ray crosses its plane)
    let sc = cv_vseg(v.rd, v.C, 0.0, sh.y * 0.75);
    let gw = 26.0 + 0.04 * sc.y;
    var halo = sh.z * (0.32 * gw / (sc.x + gw) * (0.35 + 0.65 * smoothstep(0.0, 1.0, 1.0 - curt))) * mix(0.35, 1.0, cv_vis(v, sc.y));
    let an = dot(v.rd.xz, Nn);
    let bn = dot(v.C.xz, Nn);
    if (abs(an) > 0.02) {
        let tc = bn / an;
        if (tc > 0.0) {
            let Pc = v.rd * tc - v.C;
            let dl = max(abs(dot(Pc.xz, S)) - sh.x * 0.85, 0.0);
            let dy = max(Pc.y - sh.y * 0.8, 0.0) + max(-Pc.y, 0.0) * 3.0;
            let dout = length(vec2<f32>(dl, dy));
            halo = halo + sh.z * (0.22 * exp(-dout / 22.0) + 0.045 / (1.0 + pow(dout / 80.0, 2.0))) * (0.25 + 0.75 * smoothstep(0.0, 12.0, dout)) * mix(0.4, 1.0, cv_vis(v, tc)) * mix(1.0, 0.4, curt);
        }
    }
    // (its glow takes the colour of the half the pixel looks out over: fire one side of it, gold the other)
    var far = v.rel - v.C;
    if (v.sky) {
        far = v.rd * 1.0e5 - v.C;
    }
    let ns = smoothstep(-0.15, 0.15, dot(normalize(far.xz + vec2<f32>(1.0e-3, 0.0)), Nn));
    let ht = mix(mix(CVG_WHITE, CVG_GOLD, 0.35), mix(vec3<f32>(0.86, 0.9, 0.98), vec3<f32>(1.0, 0.27, 0.05), ns), smoothstep(0.08, 0.5, a));
    c = c + ht * halo * fk * (0.3 + 0.7 * v.veil);
    // (the span of the ray inside the slab |across| < W, along its length and under its top)
    let W = 4.0 * sh.w;
    var t0 = 0.0;
    var t1 = 6000.0;
    if (abs(an) > 1.0e-5) {
        let ta = (bn - W) / an;
        let tb = (bn + W) / an;
        t0 = max(min(ta, tb), 0.0);
        t1 = min(max(ta, tb), t1);
    } else if (abs(bn) >= W) {
        return c;
    }
    let as_ = dot(v.rd.xz, S);
    let bs = dot(v.C.xz, S);
    let Lx = sh.x * 1.1;
    if (abs(as_) > 1.0e-5) {
        let ta = (bs - Lx) / as_;
        let tb = (bs + Lx) / as_;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    } else if (abs(bs) >= Lx) {
        return c;
    }
    if (abs(v.rd.y) > 1.0e-5) {
        let ta = (v.C.y - 2.0) / v.rd.y;
        let tb = (v.C.y + sh.y * 1.05) / v.rd.y;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    }
    t1 = min(t1, v.len + 3.0);
    if (t0 >= t1) {
        return c;
    }
    let tm = 0.5 * (t0 + t1);
    let P = v.rd * tm - v.C;
    let along = dot(P.xz, S);
    let across = dot(P.xz, Nn);
    let y = P.y;
    let u = abs(along) / sh.x;
    // (three folded layers at different depths across the slab, each seen where the ray crosses it: nearer folds in
    // front of farther ones, sliding past each other as the eye moves)
    var fl = vec3<f32>(0.0);
    var fw = 0.5;
    // (the layers' colours across the slab: gold on the Aether's face, white-gold in the middle, fire on the Nether's)
    var lc0 = vec3<f32>(1.0, 0.88, 0.66);
    var lc2 = vec3<f32>(1.0, 0.2, 0.03);
    for (var k = 0; k < 3; k = k + 1) {
        let fk_ = f32(k);
        var tk = tm;
        if (abs(an) > 1.0e-4) {
            tk = clamp((bn + (fk_ - 1.0) * 0.55 * W) / an, t0, t1);
        }
        let Pk = v.rd * tk - v.C;
        let f = cvg_fold(dot(Pk.xz, S), Pk.y, a, fk_, curt);
        fl[k] = f.x;
        if (k == 1) {
            fw = f.y;
        }
    }
    // (front to back: the nearest layer hides a little of those behind it; the far ones fainter and more gold)
    var lay = vec3<f32>(fl.x, fl.y, fl.z);
    if (bn < 0.0) {
        lay = vec3<f32>(fl.z, fl.y, fl.x);
        let sw = lc0;
        lc0 = lc2;
        lc2 = sw;
    }
    let w1 = (1.0 - 0.35 * min(lay.x, 1.0)) * 0.8 * lay.y;
    let w2 = (1.0 - 0.35 * min(lay.x, 1.0)) * (1.0 - 0.3 * min(lay.y, 1.0)) * 0.6 * lay.z;
    let F = lay.x + w1 + w2;
    let ltint0 = (lc0 * lay.x + vec3<f32>(1.0, 0.8, 0.6) * w1 + lc2 * w2) / max(F, 1.0e-3);
    // (light and shade across its folds: the crests their colour, the troughs between them the face's shade, sky blue
    // on the Aether's face and deep red on the Nether's, so it reads as folded, not as a flat wall of colour)
    let shc = select(vec3<f32>(0.75, 0.32, 0.22), vec3<f32>(0.6, 0.74, 1.05), bn >= 0.0);
    let ltint = ltint0 * mix(shc, vec3<f32>(1.0), smoothstep(0.15, 0.85, lay.x + 0.5 * w1));
    let n = fw;
    let n2 = fvnoise(vec2<f32>(along * 0.08 + 7.0 + 30.0 * (fw - 0.5) * 0.08, y * 0.03 - a * 1.3));
    // (its outline: tallest over the target, lower toward its ends, its edges torn and flickering)
    let topx = sh.y * (0.3 + 0.7 * sqrt(max(1.0 - u * u, 0.0))) * (0.9 + 0.2 * n);
    let env = (1.0 - smoothstep(0.72, 1.0, u + 0.18 * (n2 - 0.5))) * (1.0 - smoothstep(0.6 * topx, topx, y)) * smoothstep(-2.0, 1.5, y);
    if (env <= 0.0) {
        return c;
    }
    // (a solid body while it burns, the folds burning through it; at its top and ends and as it tears only the folds,
    // parting until only curtains are left)
    let edge = saturate(smoothstep(0.5, 0.95, u) + smoothstep(0.5, 0.95, y / max(topx, 1.0)));
    let strands = 0.08 + 0.85 * F;
    let solid = mix(0.16 + 0.75 * F, strands, edge);
    let body = mix(solid, F * 0.95, curt);
    let foot = exp(-max(y, 0.0) / 45.0);
    let coreu = exp(-u * u * 4.0);
    let hotb = (0.28 + 1.9 * foot + 1.4 * coreu * (0.4 + 0.6 * foot)) * (0.45 + 1.1 * n);
    let ends = exp(-pow((u - 0.93) / 0.07, 2.0)) * (1.0 - smoothstep(0.3, 0.9, a));
    let tint = mix(CVG_GOLD * 1.2, CVG_FLAME * 1.3, smoothstep(0.4, 0.6, n2));
    // (white only in its core low over the target and in its first instant; elsewhere its layers' colours)
    let wcore = saturate(1.5 * foot * coreu * (1.0 - 0.5 * curt) + exp(-a / 0.3));
    let wc = mix(ltint, CVG_WHITE, wcore);
    let e = (wc * hotb * body + tint * (edge * 0.8 + ends * 2.5) * strands) * env * sh.z * fk;
    // (soft across its thickness: the path through it face on, a soft line edge on)
    let g = exp(-across * across / (sh.w * sh.w)) + 0.12 * exp(-abs(across) / (1.5 * sh.w));
    let path = min((t1 - t0) / (2.0 * W), 1.4) * g;
    let k = path * cv_vis(v, t0) * v.veil * smoothstep(8.0, 70.0, tm);
    // (it hides what is behind it as much as it burns)
    let hide = saturate(min(k, 1.0) * (0.35 + 0.65 * min(body, 1.0)) * env * min(sh.z, 1.0) * 0.85);
    // (its colours held below white where it is not the core: a bright fold is a brighter gold or fire, not white)
    var ek = e * k;
    let em = max(ek.r, max(ek.g, ek.b));
    ek = mix(ek * (1.25 / max(em, 1.25)), ek, wcore);
    return c * (1.0 - hide) + ek + c * e * k * 0.15;
}
// Impact frames as the blast strikes (off with `/orbital impactframes off`: params[15]'s bit 2, as the Rod's): three
// stark frames, a fifth of a second in all, the picture cut in two along the seam: the world black on white with the
// seam's line white-hot; then black on the two sides' colours (the Nether's ember, the Aether's gold-white); then the
// world drawn in its side's colour on black. A white line on the seam through all three; then the flash.
fn cvg_if_on() -> bool {
    return ((u32(frame.mod_params[3].w + 0.5) >> 1u) & 1u) == 0u;
}
fn cvg_impact(v: CvView, col: vec3<f32>, a: f32) -> vec3<f32> {
    var far = v.rel - v.C;
    if (v.sky) {
        far = v.rd * 1.0e5 - v.C;
    }
    let nether = dot(far.xz, cvg_seam_n()) > 0.0;
    // (the sheet itself as it tears out: where the ray crosses the seam's plane inside its outline, before the world)
    var line = 0.0;
    let sh = cvg_sheet(max(a, 0.01));
    let an = dot(v.rd.xz, cvg_seam_n());
    if (abs(an) > 1.0e-4) {
        let tc = dot(v.C.xz, cvg_seam_n()) / an;
        if (tc > 0.0 && tc < v.len) {
            let P = v.rd * tc - v.C;
            let u = abs(dot(P.xz, cvg_seam_dir())) / max(sh.x, 1.0);
            let topx = sh.y * (0.3 + 0.7 * sqrt(max(1.0 - u * u, 0.0)));
            line = (1.0 - smoothstep(0.9, 1.0, u)) * (1.0 - smoothstep(0.9 * topx, topx, P.y)) * step(0.0, P.y);
        }
    }
    let fig = select(1.0, 0.0, v.sky);
    let f = floor(a / 0.066);
    if (f < 1.0) {
        return mix(vec3<f32>(1.0), vec3<f32>(0.0), fig * (1.0 - line)) * 3.0;
    }
    let sc = select(mix(CVG_GOLD, CVG_WHITE, 0.45) * 2.6, CVG_EMBER * 2.4, nether);
    if (f < 2.0) {
        return mix(sc, vec3<f32>(0.0), fig) + CVG_WHITE * line * 3.0;
    }
    return mix(vec3<f32>(0.0), sc, fig) + CVG_WHITE * line * 3.0;
}
// The sharp part (full size): the haze, the light on the land, the sparks, the arcs, the shells, the knot's core, the
// held breath before the blast, the sheet, the impact frames, the flash and the lens.
fn cv_ground_sharp(v: CvView, col: vec3<f32>) -> vec3<f32> {
    var c = col;
    let t = v.t;
    let a = cv_since_hit(t);
    c = cvg_haze(v, c);
    c = cvg_land(v, c);
    c = cv_cracks_sharp(v, c);
    c = cvg_embers(v, c);
    c = cvg_arcs(v, c);
    c = cvg_meet(v, c);
    let M = v.C + vec3<f32>(0.0, cv_meet_y(t), 0.0);
    let cl = cvg_collapse(t);
    if (cl > 0.0) {
        // (the held breath: everything but the point it has all drawn into going dark)
        let pm = project_rel(M);
        let dq = length((v_uv - pm.xy) * vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0));
        c = c * (1.0 - 0.6 * cl * smoothstep(0.015, 0.35, dq));
    }
    if (a > 0.0 && a < 4.0) {
        // (the eye stopped down by the sheet: the world dims round it for a moment, the Nether's half most)
        var far = v.rel - v.C;
        if (v.sky) {
            far = v.rd * 1.0e5 - v.C;
        }
        let ns = smoothstep(-0.1, 0.1, dot(normalize(far.xz + vec2<f32>(1.0e-3, 0.0)), cvg_seam_n()));
        c = c * (1.0 - mix(0.22, 0.42, ns) * smoothstep(0.12, 0.3, a) * exp(-max(a - 0.3, 0.0) / 1.1) * cvg_k_flash());
    }
    c = cvg_sheet_sharp(v, c);
    if (a > 0.0 && a < 3.0) {
        if (a < 0.2 && cvg_if_on()) {
            c = cvg_impact(v, c, a);
        } else {
            // (a short white-out that resolves into the sheet: after the impact frames, or at once without them)
            let a0 = select(0.1, 0.2, cvg_if_on());
            let fl = saturate(cvg_k_flash() * (0.92 * exp(-max(a - a0, 0.0) / 0.035) + 0.04 * exp(-a / 0.3)));
            c = mix(c, mix(CVG_WHITE, CVG_CORE, saturate(a * 2.0)) * 3.0, fl);
        }
    }
    // the lens: a bloom and an anamorphic streak through the knot or the sheet's core, red on the one side and gold on
    // the other
    var src = M;
    var I = 0.0;
    var Is = 0.0;
    var sl = 2.2;
    let sm = cv_since_meet(t);
    if (sm > 0.0 && t <= CV_HIT) {
        // (a burst as they strike, then a low glow through the clash; dimmed in the held breath. The streak only for the
        // instant of the impact and each big shove's peak, short and fading)
        let hit = 3.0 * exp(-sm / 0.18) * smoothstep(0.0, 0.02, sm);
        I = ((0.12 + 0.12 * min(1.2 * max(cvg_feed(t).x - 0.6, 0.0), 1.5) + 1.2 * cvg_pull(t)) * smoothstep(0.0, 0.5, sm) + hit) * (1.0 - 0.8 * cl);
        var pk = 0.0;
        for (var i = 0; i < 6; i = i + 1) {
            let u = t - cv_surge(i) - cv_surge_atk(i);
            pk = pk + smoothstep(24.0, 38.0, cv_surge_amp(i)) * smoothstep(-0.08, 0.0, u) * exp(-max(u, 0.0) / 0.16);
        }
        Is = (3.0 * exp(-sm / 0.12) * smoothstep(0.0, 0.02, sm) + 1.4 * pk) * (1.0 - 0.8 * cl);
        sl = 5.0;
    } else if (a > 0.0 && a < 8.0) {
        src = v.C + vec3<f32>(0.0, 30.0, 0.0);
        I = (1.2 * exp(-a / 0.5) + 0.8 * cvg_sheet(a).z + 0.3 * exp(-a / 4.0)) * (1.0 - smoothstep(6.0, 8.0, a)) * v.veil;
        Is = I;
    }
    if (I + Is > 0.0 && !(a > 0.0 && a < 0.2 && cvg_if_on())) {
        let pr = project_rel(src);
        if (pr.z > 0.0) {
            let asp = frame.resolution.x / frame.resolution.y;
            let d = (v_uv - pr.xy) * vec2<f32>(asp, 1.0);
            let bloom = exp(-length(d) * 9.0);
            let streak = exp(-abs(d.y) * 180.0) * exp(-abs(d.x) * sl);
            let tint = mix(CVG_GOLD, CVG_FLAME, smoothstep(-0.3, 0.3, d.x));
            c = c + mix(CVG_WHITE, tint, 0.5) * bloom * 0.7 * I + mix(CVG_WHITE, tint, 0.3) * streak * 0.6 * Is;
        }
    }
    return c;
}
// ==== [end cv ground] =================================================================================================
