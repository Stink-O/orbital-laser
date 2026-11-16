// [lean pass] (mod/src/passbuild.rs: the game's pass goes in without its comment and blank lines)
// Orbital Laser's post pass for the Convergence (laser 20). The mod builds it from shaders/strike.wgsl up to its
// fs_main less the other lasers' own functions, followed by this file, and sets it for a convergence strike only.
// Validate with tools/check-shader.sh.
//
// The Nether breaks out of the ground, the Aether out of the sky: the land cracks open and fire and ash rush out of it,
// a rift tears open in the sky over it; a fountain of fire and a stub of light draw back, then two columns race at each
// other and strike in the air (a shell out from the point they meet), shove each other up and down (each surge a
// ring), the meeting point tightens and drops, and one huge burst ends it. The land itself (cracks, basalt, the two
// halves, the crater, the islands left in the sky) is real blocks: strike/convergence.rs.
//
// The pass is in four files (mod/build.rs joins them: this one up to `[cv stages]`, the three sides, the rest of this):
//   this file                the clock and the geometry (`[cv shared]`, mirrored by strike/convergence.rs's CV_*: keep
//                            both in step) and the stage functions (`[cv stages]`: fs_main, and at QUALITY FAST fs_half
//                            and fs_join), the jolt on the picture;
//   convergence_sky.wgsl     the sky side: the rift and what shows through it, the gold column, the light spilling out;
//   convergence_ground.wgsl  the ground side, the clash and the burst: the red column, the smoke, the meeting point,
//                            the impact's shell and the rings, the burst and its cloud, the lens;
//   convergence_cracks.wgsl  the cracks: their depth and glow, the fire and ash rushing out of them.
// Each side is reached only through its two functions: `cv_sky_soft` / `cv_sky_sharp`, `cv_ground_soft` /
// `cv_ground_sharp` (which call `cv_cracks_soft` / `cv_cracks_sharp`). The soft ones are drawn in the half-size stage
// at QUALITY FAST (premultiplied colour and transmittance), the sharp ones at full size over the picture, with
// CvView's `veil` saying how much shows through the ground side's smoke.

// ==== [cv shared] =====================================================================================================
// The beats, strike seconds (strike/convergence.rs: CV_OMEN ... CV_END).
const CV_OMEN: f32 = 0.0;          // the ground trembles, cracks glow, a seam of light opens high over the target
const CV_BREAK: f32 = 5.0;         // both break in
const CV_RED0: f32 = 6.0;          // a fountain of fire starts out of the ground (to CV_RED_STUB high)
const CV_GOLD0: f32 = 7.5;         // a stub of light starts down out of the rift (CV_GOLD_STUB long)
const CV_CROUCH: f32 = 12.33;      // both gather their light, a moment before they fire
const CV_FIRE: f32 = 12.45;        // both fire: the two columns race at each other
const CV_MEET: f32 = 13.0;         // they strike each other in the air: the impact, then the clash
const CV_DRAW: f32 = 23.0;         // the meeting point tightens and drops
const CV_HIT: f32 = 26.0;          // THE BLAST
const CV_CLOSE: f32 = 31.0;        // the aftermath: the rift closing, gone by CV_END
const CV_END: f32 = 40.0;
const CV_LEN: f32 = 60.0;          // the strike's length (lasers.rs): everything fades out over its last CV_FADE
const CV_FADE: f32 = 8.0;
// The clash's surges (CV_SURGES, CV_SURGE_SIGN: up for the Nether, down for the Aether; each its own reach and attack:
// cv_surge_amp, cv_surge_atk, as CV_SURGE_AMP and CV_SURGE_ATK), and the speed their knocks and sounds are timed at.
const CV_RING_V: f32 = 160.0;
// Heights over the target's ground: where the columns meet, the rift's plane and its size, the burst.
const CV_MEET_Y: f32 = 130.0;
const CV_RIFT_Y: f32 = 260.0;
const CV_RIFT_R: f32 = 80.0;
const CV_BURST: f32 = 14.0;
// The two columns' core radius, blocks: both sides draw theirs to it, racing and standing alike.
const CV_BEAM_R: f32 = 9.0;
// Before they fire: how high the fire's fountain stands and how far the light hangs under the rift (the LOWs
// the same: neither draws back). The impact's shell in the air, blocks a second (its jolt keys off it).
const CV_RED_STUB: f32 = 30.0;
const CV_RED_LOW: f32 = 30.0;
const CV_GOLD_STUB: f32 = 36.0;
const CV_GOLD_LOW: f32 = 36.0;
const CV_IMPACT_V: f32 = 240.0;
const CV_V: f32 = 343.0;          // the blast's front, blocks a second (the knockback and the blast's sound key off it)
// The table (mod_data from word 0, cv_table in strike/convergence.rs): word 0 CV_MAGIC once it is in, 1 the seam's
// bearing (radians; the Nether half the bearings within PI past it), 2 the seed.
const CV_MAGIC: f32 = 7171.0;

fn cv_surge(i: i32) -> f32 {
    var s = array<f32, 6>(14.4, 16.2, 17.6, 19.4, 20.9, 22.2);
    return s[clamp(i, 0, 5)];
}
fn cv_surge_sign(i: i32) -> f32 {
    return select(-1.0, 1.0, (i & 1) == 0);
}
// How far surge i shoves the meeting point (blocks) and how heavily (seconds: it is nine tenths of the way four times
// this after it starts): a struggle, no two alike.
fn cv_surge_amp(i: i32) -> f32 {
    var a = array<f32, 6>(22.0, 34.0, 18.0, 40.0, 28.0, 26.0);
    return a[clamp(i, 0, 5)];
}
fn cv_surge_atk(i: i32) -> f32 {
    var a = array<f32, 6>(0.16, 0.12, 0.28, 0.11, 0.22, 0.14);
    return a[clamp(i, 0, 5)];
}
// How far one of the Nether's surges has driven the meeting point u seconds after it starts, as a share of its reach:
// a weight pushed, from rest to rest, with no overshoot, and none of the ground given back (`atk`: it is nine tenths
// of the way four times this after it starts).
fn cv_shove(u: f32, atk: f32) -> f32 {
    if (u <= 0.0) {
        return 0.0;
    }
    let x = u / atk;
    return 1.0 - (1.0 + x) * exp(-x);
}
// How fast that shove is moving the meeting point u seconds after it starts, as a share of its greatest speed (which
// it has `atk` after it starts): 0 at the start, 1, then dying away.
fn cv_push(u: f32, atk: f32) -> f32 {
    if (u <= 0.0) {
        return 0.0;
    }
    let x = u / atk;
    return 2.7182818 * x * exp(-x);
}
// Which way the clash is being shoved at t and how hard (up for the Nether, down for the Aether; about -1..1): each
// surge's own speed, so it rises and falls with the meeting point's movement, never ahead of it.
fn cv_kick(t: f32) -> f32 {
    var f = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        f = f + cv_surge_sign(i) * cv_surge_amp(i) / 40.0 * cv_push(t - cv_surge(i), cv_surge_atk(i));
    }
    return f * step(CV_MEET, t);
}
// The meeting point never quite rests: it drifts a little on three slow swings that never line up (blocks; none at
// the impact, all of it 1.6 s after), and the gold column's weight drives it down a little as they strike.
fn cv_wander(t: f32) -> f32 {
    let e = smoothstep(CV_MEET + 0.2, CV_MEET + 1.6, t);
    return e * (2.0 * sin(0.9 * t + 1.3) + 1.2 * sin(2.3 * t + 4.1) + 0.6 * sin(5.1 * t + 0.7));
}
fn cv_recoil(t: f32) -> f32 {
    let u = t - CV_MEET;
    if (u <= 0.0) {
        return 0.0;
    }
    let x = u / 0.09;
    return -9.0 * (1.0 - (1.0 + x) * exp(-x)) * exp(-u / 0.9);
}
fn cv_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
// Whether the table is in (the first tick after the strike fires), and the seam's bearing.
fn cv_ready() -> bool {
    return abs(cv_w(0u) - CV_MAGIC) < 0.5;
}
fn cv_seam() -> f32 {
    return cv_w(1u);
}
// The strike's clock.
fn cv_clock() -> f32 {
    return now();
}
// 0 before t0, 1 after t1, eased between.
fn cv_beat(t: f32, t0: f32, t1: f32) -> f32 {
    return smoothstep(t0, t1, t);
}
// The target's ground, camera-relative.
fn cv_ground() -> vec3<f32> {
    let anc = anchor_xz();
    return vec3<f32>(anc.x, block_y() + 1.0, anc.y) - frame.camera_position.xyz;
}
// Where the player stood as it fired, camera-relative.
fn cv_me() -> vec3<f32> {
    return vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z) - frame.camera_position.xyz;
}
// The meeting point's height over the target's ground at t (strike/convergence.rs's cv_meet_y, step for step).
fn cv_clash_y(t: f32) -> f32 {
    // (one way only through the clash: each of the Nether's surges drives it up toward the rift and keeps what it
    // takes; the Aether's hold it where it is; then the Aether drives it all the way down: cv_meet_y)
    var y = CV_MEET_Y + cv_wander(t) + cv_recoil(t);
    for (var i = 0; i < 6; i = i + 2) {
        y = y + 0.75 * cv_surge_amp(i) * cv_shove(t - cv_surge(i), 2.5 * cv_surge_atk(i));
    }
    return y;
}
fn cv_meet_y(t: f32) -> f32 {
    if (t < CV_DRAW) {
        return cv_clash_y(t);
    }
    if (t < CV_HIT) {
        let u = (t - CV_DRAW) / (CV_HIT - CV_DRAW);
        // (driven down faster and faster, fastest as it strikes the ground: no easing into it)
        let y0 = cv_clash_y(CV_DRAW);
        return y0 + (CV_BURST - y0) * u * u * u;
    }
    return CV_BURST;
}
// How far a column has come from where it stood before it fired (`from`) to the meeting point, at t: it stands
// `stub` out from `t0` (eased), holds `low` (the same: it never draws back) to CV_FIRE, then races (cv_snap: at speed
// at once, gathering more all the way) and strikes at CV_MEET. Returns its reach from its root, blocks; `full` the
// whole way to the meeting point.
// The race, 0-1 over 0-1: CV_SNAP of its mean speed from the first instant, the rest gathered on the way.
const CV_SNAP: f32 = 0.6;
fn cv_snap(u: f32) -> f32 {
    return CV_SNAP * u + (1.0 - CV_SNAP) * pow(u, 2.4);
}
fn cv_reach(t: f32, t0: f32, stub: f32, low: f32, full: f32) -> f32 {
    if (t >= CV_FIRE) {
        let u = clamp((t - CV_FIRE) / (CV_MEET - CV_FIRE), 0.0, 1.0);
        return low + (full - low) * cv_snap(u);
    }
    if (t >= CV_CROUCH) {
        let u = (t - CV_CROUCH) / (CV_FIRE - CV_CROUCH);
        return stub + (low - stub) * u * u * (3.0 - 2.0 * u);
    }
    let u = clamp((t - t0) / (CV_CROUCH - t0), 0.0, 1.0);
    return stub * (1.0 - pow(1.0 - u, 3.0));
}
// The race itself, 0 at CV_FIRE to 1 at CV_MEET (as cv_reach's), and seconds since the impact (negative before).
fn cv_launch(t: f32) -> f32 {
    return cv_snap(clamp((t - CV_FIRE) / (CV_MEET - CV_FIRE), 0.0, 1.0));
}
fn cv_since_meet(t: f32) -> f32 {
    return t - CV_MEET;
}
// The red column's top and the gold column's foot over the target's ground (cv_red_top, cv_gold_foot).
fn cv_red_top(t: f32) -> f32 {
    if (t >= CV_MEET) {
        return cv_meet_y(t);
    }
    return cv_reach(t, CV_RED0, CV_RED_STUB, CV_RED_LOW, CV_MEET_Y);
}
fn cv_gold_foot(t: f32) -> f32 {
    if (t >= CV_MEET) {
        return cv_meet_y(t);
    }
    return CV_RIFT_Y - cv_reach(t, CV_GOLD0, CV_GOLD_STUB, CV_GOLD_LOW, CV_RIFT_Y - CV_MEET_Y);
}
// The rift's half-length (along the seam) and half-width at t: a hairline seam over the omen, torn open over the
// break, held through the clash and the blast, closing over the aftermath.
fn cv_rift_size(t: f32) -> vec2<f32> {
    let open = cv_beat(t, CV_BREAK, CV_MEET);
    let close = 1.0 - cv_beat(t, CV_CLOSE, CV_END);
    let len = CV_RIFT_R * (0.85 * cv_beat(t, CV_OMEN + 0.3, CV_BREAK) + 0.15 * open) * close;
    let wid = (0.6 + 1.4 * cv_beat(t, CV_OMEN + 0.3, CV_BREAK) + (0.75 * CV_RIFT_R - 2.0) * open * open) * close;
    return vec2<f32>(len, wid);
}
// How hard the clash flares at t (each surge as hard as it is moving the meeting point), 0 before CV_MEET.
fn cv_flare(t: f32) -> f32 {
    var f = 0.0;
    for (var i = 0; i < 6; i = i + 1) {
        f = f + cv_surge_amp(i) / 28.0 * cv_push(t - cv_surge(i), cv_surge_atk(i));
    }
    return f * step(CV_MEET, t);
}
// Since the blast, seconds (negative before).
fn cv_since_hit(t: f32) -> f32 {
    return t - CV_HIT;
}

// What both sides read about the pixel.
struct CvView {
    t: f32,
    rd: vec3<f32>,            // the ray's direction (unit, world axes)
    C: vec3<f32>,             // the target's ground, camera-relative
    rel: vec3<f32>,           // the scene point under the pixel, camera-relative
    len: f32,                 // how far the ray goes before the world (1e9 for the sky)
    sky: bool,
    fade: f32,                // everything fading out over the strike's last seconds
    day: f32,
    veil: f32,                // how much shows through the ground side's smoke and fire along this ray (1 clear, 0
                              // hidden): set for the sharp parts only (1 in the soft ones)
}
// The distance from the ray to point P (camera-relative) and how far along the ray its nearest point lies.
fn cv_pt(rd: vec3<f32>, P: vec3<f32>) -> vec2<f32> {
    let t = max(dot(P, rd), 0.0);
    return vec2<f32>(length(P - rd * t), t);
}
// The distance from the ray to the vertical segment over (C.x, C.z) from height ya to yb (camera-relative), and how far
// along the ray its nearest point lies.
fn cv_vseg(rd: vec3<f32>, C: vec3<f32>, ya: f32, yb: f32) -> vec2<f32> {
    let h = rd.xz;
    let hh = max(dot(h, h), 1.0e-6);
    let th = max(dot(C.xz, h) / hh, 0.0);
    let y = clamp(rd.y * th, min(ya, yb), max(ya, yb));
    return cv_pt(rd, vec3<f32>(C.x, y, C.z));
}
// What a glow behind the world shows: none past the world's depth (soft over a few blocks).
fn cv_vis(v: CvView, t: f32) -> f32 {
    return select(1.0 - smoothstep(v.len - 4.0, v.len + 4.0, t), 1.0, v.sky);
}
// ==== [end cv shared] =================================================================================================

// (the sky side, the ground side and the cracks are their own files: the pass is this file up to `[cv stages]`, then
// those three, then the rest of this file: mod/build.rs)

// ==== [cv stages] =====================================================================================================
// The pixel's screen uv, for the lens (set by the stage).
var<private> v_uv: vec2<f32>;
// The four tuning knobs (`/orbital tune`: glow, burst, flash, haze), read once a pixel by cv_view: a tune_knob call at
// each place a value is used slows the whole pass several times over.
var<private> cv_tune: vec4<f32> = vec4<f32>(1.0);
fn cv_k_glow() -> f32 { return cv_tune.x; }
fn cv_k_burst() -> f32 { return cv_tune.y; }
fn cv_k_flash() -> f32 { return cv_tune.z; }
fn cv_k_haze() -> f32 { return cv_tune.w; }
// (a fifth: dusk, how far the day goes out)
var<private> cv_tune_dusk: f32 = 1.0;

// The view of the pixel, at full size (stage 0, 2) or for the half-size stage's two by two (stage 1: alternately the
// nearest and the farthest of their depths, as the Rod's).
fn cv_view(in: StageIn, stage: u32) -> CvView {
    var uv = in.uv;
    var d = 0.0;
    if (stage == 1u) {
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
        let d0 = depth_at((vec2<f32>(q) + 0.5) * frame.resolution.zw);
        let d1 = depth_at((vec2<f32>(f32(q1.x), f32(q.y)) + 0.5) * frame.resolution.zw);
        let d2 = depth_at((vec2<f32>(f32(q.x), f32(q1.y)) + 0.5) * frame.resolution.zw);
        let d3 = depth_at((vec2<f32>(q1) + 0.5) * frame.resolution.zw);
        let hq = vec2<i32>(floor(in.position.xy));
        d = select(min(min(d0, d1), min(d2, d3)), max(max(d0, d1), max(d2, d3)), ((hq.x + hq.y) & 1) == 0);
        uv = (vec2<f32>(q) + 1.0) * frame.resolution.zw;
    } else {
        d = depth_at(uv);
    }
    v_uv = uv;
    cv_tune = vec4<f32>(tune_knob(0u, 1.0), tune_knob(1u, 1.0), tune_knob(2u, 1.0), tune_knob(3u, 1.0));
    cv_tune_dusk = tune_knob(4u, 1.0);
    var v: CvView;
    v.t = cv_clock();
    v.sky = is_sky(d);
    v.rel = world_offset(uv, select(d, 0.5, v.sky));
    v.len = select(1.0e9, length(v.rel), !v.sky);
    v.rd = normalize(world_offset(uv, 0.5));
    v.C = cv_ground();
    v.fade = 1.0 - smoothstep(CV_LEN - CV_FADE, CV_LEN, v.t);
    v.day = saturate(frame.sun.y * 2.5 + 0.35);
    v.veil = 1.0;
    return v;
}
// The ground side's transmittance along this pixel's ray (CvView's `veil`): set by cv_soft, or by cv_up from the
// half-size stage.
var<private> cv_gveil: f32 = 1.0;
// Both sides' soft parts together (premultiplied colour and transmittance over what is behind).
fn cv_soft(v: CvView) -> vec4<f32> {
    let s = cv_sky_soft(v);
    let g = cv_ground_soft(v);
    cv_gveil = g.a;
    return vec4<f32>(s.rgb * g.a + g.rgb, s.a * g.a);
}
// Nothing to draw: the table is not in yet, or the strike is over.
fn cv_idle() -> bool {
    return !cv_ready() || intensity_v() <= 0.0;
}
// How far the day has gone out at t (0 daylight, 1 its darkest): it dims as the worlds stir, goes as both break in,
// stays out through the clash and the blast, and comes back over the aftermath.
fn cv_dusk(t: f32) -> f32 {
    let gone = 0.3 * cv_beat(t, 0.4, CV_BREAK) + 0.7 * cv_beat(t, CV_BREAK, CV_CROUCH);
    return gone * (1.0 - cv_beat(t, CV_CLOSE - 2.0, CV_END));
}
// The world under the two of them: the daylight goes out and the sky takes sides along the seam, the Nether's half a
// dark red, the Aether's a deep blue, so that the fire and the light stand out against it (the land keeps its own
// colours, dimmed, with a little of its side's). `col` the game's picture (linear), before anything is laid over it.
fn cv_grade(v: CvView, col: vec3<f32>) -> vec3<f32> {
    let k = saturate(cv_dusk(v.t) * v.fade * v.day * cv_tune_dusk);
    if (k <= 0.0) {
        return col;
    }
    // (where the pixel lies over the land: the land itself, or for the sky a ceiling 420 blocks over the target's
    // ground, so the line between the halves runs through the rift and away to the horizon both ways)
    var far = v.len;
    if (v.sky) {
        far = min((v.C.y + 420.0) / max(v.rd.y, 0.03), 5000.0);
    }
    let q = (v.rd * far - v.C).xz;
    let sn = cv_seam();
    let across = dot(q, vec2<f32>(-sin(sn), cos(sn)));
    // (the line torn, not ruled: it wanders with the bearing round the target and the distance out; the bearing's
    // share let go toward the axis over the target, where every bearing meets and it would draw a star)
    let ql = length(q);
    let wob = 0.5 * sin(atan2(q.y, q.x) * 7.0 + 1.7) * smoothstep(0.0, 0.2 * far + 40.0, ql) + 0.5 * sin(ql * 0.011 + 0.6);
    let side = smoothstep(-1.0, 1.0, (across + wob * 0.04 * far) / (10.0 + 0.05 * far));
    let tint = mix(vec3<f32>(0.26, 0.38, 0.85), vec3<f32>(0.70, 0.17, 0.10), side);
    let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let w = select(0.25 + 0.3 * smoothstep(60.0, 500.0, v.len), 1.0, v.sky);
    var c = mix(col, vec3<f32>(lum) * tint * 1.6, w * k) * mix(1.0, select(0.45, 0.30, v.sky), k);
    if (v.sky) {
        // (the two skies are not flat colour: over the Nether's half dark ash rolls slowly under a glow from below;
        // over the Aether's pale light hangs in soft drifting bands; the line between them burns)
        let p = q * 0.0035;
        // (toward the horizon the ceiling is cut off at `far` = 5000 and every pixel of a column would read the same
        // point of it: the detail thins out to its mean before that, into haze. All of it comes in with the dusk,
        // `k`, as the tint does: nothing is there at once)
        let hz = smoothstep(4500.0, 2200.0, far);
        let ash = mix(0.5, 0.65 * fvnoise(p + vec2<f32>(0.021, 0.013) * v.t) + 0.35 * fvnoise(p * 2.7 - vec2<f32>(0.017, 0.031) * v.t), hz);
        let roll = mix(0.5, smoothstep(0.38, 0.72, ash), hz);
        let low = 1.0 - smoothstep(0.0, 0.45, v.rd.y);
        let nether = c * mix(1.0, mix(1.25, 0.45, roll), k) + vec3<f32>(0.55, 0.12, 0.03) * (0.10 + 0.22 * low) * (1.0 - roll) * k;
        let band = hz * smoothstep(0.45, 0.8, fvnoise(p * vec2<f32>(0.6, 1.9) + vec2<f32>(-0.012, 0.02) * v.t + vec2<f32>(31.7, 7.3)));
        let aether = c * mix(1.0, 0.9 + 0.25 * band, k) + vec3<f32>(0.55, 0.62, 0.75) * 0.10 * band * k;
        let edge = 1.0 - abs(side * 2.0 - 1.0);
        c = mix(aether, nether, side) + vec3<f32>(1.0, 0.8, 0.6) * 0.30 * edge * edge * k * (0.6 + 0.4 * ash);
    }
    return c;
}
// The picture at this pixel with the soft parts laid over it (`soft`: premultiplied colour and transmittance), then
// the sharp parts. Each stage function calls only what it needs: the half-size stage carries none of the sharp path
// and the join none of the soft marches (a stage built with both in it is slow in both).
fn cv_finish(in: StageIn, v: CvView, soft: vec4<f32>) -> vec4<f32> {
    var col = cv_grade(v, srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb));
    col = col * soft.a + soft.rgb;
    var w = v;
    w.veil = cv_gveil;
    col = cv_sky_sharp(w, col);
    col = cv_ground_sharp(w, col);
    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0);
    }
    return vec4<f32>(srgb, 1.0);
}

// The jolt on the picture: the game's camera shake tops out at a few degrees, so the picture itself is knocked about
// too, a little at each surge as its ring reaches the player, hard as the blast's front does (the Rod's).
fn cv_jolt(in: StageIn) -> StageIn {
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    var o = in;
    let t = cv_clock();
    let me = cv_me();
    let dist = length(me - (cv_ground() + vec3<f32>(0.0, CV_BURST, 0.0)));
    let s = t - CV_HIT - dist / CV_V;
    var off = vec2<f32>(0.0);
    var roll = 0.0;
    var hitz = 0.0;
    if (s > 0.0 && s < 7.0 && intensity_v() > 0.0) {
        let g = clamp(1.5 / (1.0 + dist / 350.0), 0.2, 1.0);
        let hit = 0.034 * g * exp(-s / 0.22) * smoothstep(0.0, 0.015, s);
        let ring = vec2<f32>(0.65 * sin(s * 53.0 + 0.6) + 0.35 * sin(s * 89.0 + 2.1), 0.65 * cos(s * 47.0 + 1.3) + 0.35 * sin(s * 77.0 + 0.4));
        let shud = 0.005 * g * exp(-s / 1.8) * smoothstep(0.08, 0.4, s);
        let sh = vec2<f32>(0.55 * sin(s * 17.0 + 0.3) + 0.3 * sin(s * 29.0 + 1.9), 0.55 * cos(s * 15.0 + 2.2) + 0.3 * sin(s * 31.0 + 0.7));
        off = ring * hit + sh * shud;
        roll = 0.018 * g * exp(-s / 0.3) * sin(s * 41.0 + 0.9) + 0.0025 * g * exp(-s / 1.8) * sin(s * 11.0);
        hitz = hit + shud;
    }
    // (the impact's shell reaching the player: a knock, harder than a surge's)
    let dm = length(me - (cv_ground() + vec3<f32>(0.0, CV_MEET_Y, 0.0)));
    let ui = t - CV_MEET - min(dm / CV_IMPACT_V, 4.0);
    if (ui > 0.0 && ui < 1.5 && intensity_v() > 0.0) {
        let g = clamp(1.8 / (1.0 + dm / 300.0), 0.2, 0.9);
        let k = 0.022 * g * exp(-ui / 0.2) * smoothstep(0.0, 0.015, ui);
        off = off + vec2<f32>(0.6 * sin(ui * 51.0 + 0.7) + 0.4 * sin(ui * 83.0), 0.6 * cos(ui * 43.0 + 1.9) + 0.4 * sin(ui * 71.0 + 1.1)) * k;
        roll = roll + 0.009 * g * exp(-ui / 0.25) * sin(ui * 37.0 + 0.4);
        hitz = hitz + k;
    }
    // (each surge's shell reaching the player from where the meeting point was then: a small knock)
    for (var i = 0; i < 6; i = i + 1) {
        let ds = length(me - (cv_ground() + vec3<f32>(0.0, cv_meet_y(cv_surge(i)), 0.0)));
        let u = t - cv_surge(i) - min(ds / CV_RING_V, 4.0);
        if (u > 0.0 && u < 1.2) {
            let g = clamp(1.6 / (1.0 + ds / 250.0), 0.15, 0.7);
            let k = 0.012 * g * exp(-u / 0.18) * smoothstep(0.0, 0.02, u);
            off = off + vec2<f32>(sin(u * 47.0 + f32(i)), cos(u * 41.0 + 2.0 * f32(i))) * k;
            hitz = hitz + k;
        }
    }
    if (hitz <= 0.0) {
        return o;
    }
    let zoom = 1.0 + 2.2 * hitz + 1.1 * abs(roll) * asp;
    var q = (o.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom;
    q = vec2<f32>(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll)) + off;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}
@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    let in = cv_jolt(in0);
    let v = cv_view(in, 0u);
    if (cv_idle()) {
        return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);
    }
    return cv_finish(in, v, cv_soft(v));
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): on a game with mod passes' half-size stage, the soft parts (the
// glows, the rift's window) are drawn at half the width and height by fs_half and laid over the full-size picture by
// fs_join; a game without it compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct CvHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> CvHalf {
    let v = cv_view(in, 1u);
    let e = vec4<f32>(min(v.len, 6.0e4), 1.0, 0.0, 0.0);
    if (cv_idle()) {
        return CvHalf(vec4<f32>(0.0, 0.0, 0.0, 1.0), e);
    }
    let s = cv_soft(v);
    return CvHalf(s, vec4<f32>(e.x, cv_gveil, 0.0, 0.0));
}
// The half-size stage at this pixel (whose ray goes `len` blocks): the four nearest of its pixels, weighed bilinearly
// and by how near the depth each was drawn at is to this pixel's (a joint bilateral upsample); if none is near, the
// nearest in depth of the four.
fn cv_up(pos: vec2<f32>, len: f32) -> vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var veil = 0.0;
    var near_veil = 1.0;
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
        let dz = abs(e.x - lp) / max(lp, 1.0);
        let w = bw * exp(-dz * 24.0);
        acc = acc + c * w;
        veil = veil + e.y * w;
        sw = sw + w;
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
            near_veil = e.y;
        }
    }
    if (sw < 1.0e-3) {
        cv_gveil = near_veil;
        return near_c;
    }
    cv_gveil = veil / sw;
    return acc / sw;
}
@fragment
fn fs_join(in0: StageIn) -> @location(0) vec4<f32> {
    let in = cv_jolt(in0);
    let v = cv_view(in, 2u);
    if (cv_idle()) {
        return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);
    }
    return cv_finish(in, v, cv_up(in.position.xy, v.len));
}
// [end half stage]
// ==== [end cv stages] =================================================================================================
