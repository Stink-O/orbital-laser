// Orbital Laser's post pass for the Earthquake (laser 21). The mod builds it from shaders/strike.wgsl up to its fs_main
// less the other lasers' own functions, then shaders/earthquake_plates.wgsl (the plates, shared with the world warp),
// then this file, and sets it for an earthquake strike only. Validate with tools/check-shader.sh.
//
// The land itself moves through the world warp (shaders/earthquake_warp.wgsl): the game's own blocks, trees and water;
// the faults are cut open in real blocks (strike/eq_land.rs). This pass draws what is laid over the picture: a short hard
// jolt of the picture at the blow, the first heave, each lurch and the climax (the hardest; the game's shake tops out at
// a few degrees), shaped as the Payload's and the Nuke's (their passes' pl_jolt), and nothing between them.
//
// The file is laid out to be split later: the shared head (`[eq shared]`: the table, the view of the pixel), then the
// stages (`[eq stages]`: fs_main, and at QUALITY FAST fs_half and fs_join), each built only from what it draws. The dust
// in the air (shaders/earthquake_dust.wgsl) is joined in at the `[eq stages]` line: fs_half marches it at QUALITY FAST,
// fs_main at FULL, and fs_join lays the half-size stage over the picture.

// ==== [eq shared] =====================================================================================================
// The table (mod_data from word 0, strike/earthquake.rs's eq_table): word 0 EQ_MAGIC once it is in; 1-2 the main fault's
// direction as integers about 256 long (fx, fz); 3 the reach; 4 the pace; 5-6 slip and heave, hundredths; 7 whether
// the plates rest displaced (1) or ease back (0); 8 the plate the player rides (-1 none); 9-11 where the player stood
// as it fired; 12 the jolts' strength there (the knob `jolt` and the distance); 13 how many jolts follow; 14-15 the
// fault coordinates' origin (u0, v0); 16 where the main crack ends along the fault (u, blocks); at 17 the jolts, two
// words each: when it reaches the player, strike seconds, and how hard (0 to 1).
const EQ_MAGIC: f32 = 5151.0;
const EQ_T_EV: u32 = 17u;
const EQ_EV_MAX: u32 = 16u;

fn eq_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn eq_ready() -> bool {
    return abs(eq_w(0u) - EQ_MAGIC) < 0.5;
}
fn eq_cfg() -> EqCfg {
    let fi = vec2<i32>(i32(round(eq_w(1u))), i32(round(eq_w(2u))));
    var c: EqCfg;
    c.seed = u32(max(seed_v(), 0.0) + 0.5);
    c.reach = eq_w(3u);
    c.pace = eq_w(4u);
    c.fdir = vec2<f32>(fi) / max(length(vec2<f32>(fi)), 1.0);
    c.fi = fi;
    c.slip_q = i32(round(eq_w(5u)));
    c.heave_q = i32(round(eq_w(6u)));
    c.rest = eq_w(7u) > 0.5;
    c.rider = i32(round(eq_w(8u)));
    c.rider_k = 1.0;
    c.prev = -1;
    c.prev_k = 0.0;
    c.shift = vec2<f32>(round(eq_w(14u)), round(eq_w(15u)));
    return c;
}
// The strike's clock.
fn eq_clock() -> f32 {
    return now();
}
// The target block's corner (the land one over it), camera-relative.
fn eq_origin() -> vec3<f32> {
    let anc = anchor_xz();
    return vec3<f32>(anc.x - 0.5, block_y() + 1.0, anc.y - 0.5) - frame.camera_position.xyz;
}

// What the parts read about the pixel.
struct EqView {
    t: f32,
    rel: vec3<f32>,           // the scene point under the pixel, camera-relative
    sky: bool,
    O: vec3<f32>,             // the target block's corner, camera-relative
    day: f32,
}
// ==== [end eq shared] =================================================================================================

// ==== [eq stages] =====================================================================================================
// The knob (`/orbital tune`: dust), read once a pixel by eq_view: a tune_knob call at each place a value is used slows
// the whole pass several times over.
var<private> eq_tune: f32 = 1.0;
fn eq_k_dust() -> f32 { return eq_tune; }

// The view of the pixel, at full size (stage 0, 2) or for the half-size stage's two by two (stage 1: alternately the
// nearest and the farthest of their depths).
fn eq_view(in: StageIn, stage: u32) -> EqView {
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
    eq_tune = tune_knob(0u, 1.0);
    var v: EqView;
    v.t = eq_clock();
    v.sky = is_sky(d);
    v.rel = world_offset(uv, select(d, 0.5, v.sky));
    v.O = eq_origin();
    v.day = saturate(frame.sun.y * 2.5 + 0.35);
    return v;
}
// Nothing to draw: the table is not in yet, or the strike is over.
fn eq_idle() -> bool {
    return !eq_ready() || intensity_v() <= 0.0;
}
// The jolt on the picture: each beat in the table as it reaches the player, a hard hit swinging fast and dying in under
// a second, then a short shudder (longer and heavier the bigger the beat: the climax's some two seconds); shifted only,
// never turned, and zoomed in just enough that no edge shows. Nothing between the beats.
fn eq_jolt(in: StageIn) -> StageIn {
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    var o = in;
    let t = eq_clock();
    if (!eq_ready() || t <= 0.0 || t >= EQ_LEN) {
        return o;
    }
    let g0 = eq_w(12u);
    if (g0 <= 0.0) {
        return o;
    }
    var off = vec2<f32>(0.0);
    var hitz = 0.0;
    let n = min(u32(eq_w(13u) + 0.5), EQ_EV_MAX);
    for (var i = 0u; i < n; i = i + 1u) {
        let s = t - eq_w(EQ_T_EV + 2u * i);
        if (s > 0.0 && s < 4.0) {
            let k = eq_w(EQ_T_EV + 2u * i + 1u);
            let g = g0 * k;
            let fi = f32(i);
            // (the hit: a slam, then swinging hard and fast three or four times)
            let hit = 0.03 * g * exp(-s / (0.2 + 0.1 * k)) * smoothstep(0.0, 0.02, s);
            let ring = vec2<f32>(0.65 * sin(s * 47.0 + 0.6 + fi) + 0.35 * sin(s * 83.0 + 2.1 * fi), 0.65 * cos(s * 41.0 + 1.3 * fi) + 0.35 * sin(s * 71.0 + 0.4));
            // (the shudder: heavier and slower, the ground still heaving, gone in a second or two)
            let shud = 0.0065 * g * exp(-s / (0.35 + 0.6 * k)) * smoothstep(0.08, 0.35, s);
            let sh = vec2<f32>(0.55 * sin(s * 17.0 + 0.3 * fi) + 0.3 * sin(s * 29.0 + 1.9) + 0.15 * sin(s * 53.0), 0.55 * cos(s * 15.0 + 2.2 + fi) + 0.3 * sin(s * 31.0 + 0.7) + 0.15 * cos(s * 59.0));
            off = off + ring * hit + sh * shud;
            hitz = hitz + hit + shud;
        }
    }
    if (hitz <= 1.0e-5) {
        return o;
    }
    let zoom = 1.0 + 2.2 * hitz;
    let q = (o.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom + off;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}
fn eq_out(in: StageIn, col: vec3<f32>) -> vec4<f32> {
    return vec4<f32>(linear_to_srgb(max(col, vec3<f32>(0.0))), 1.0);
}
@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    let in = eq_jolt(in0);
    if (eq_idle()) {
        return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);
    }
    let v = eq_view(in, 0u);
    let col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb);
    // (the dust in the air at full size: shaders/earthquake_dust.wgsl)
    let dust = eqd_march(v, normalize(v.rel), select(length(v.rel), 1.0e9, v.sky), ign(in.position.xy));
    return eq_out(in, eqd_over(col, dust));
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): on a game with mod passes' half-size stage, the soft part (the
// dust) is drawn at half the width and height by fs_half and laid over the full-size picture by fs_join; a game
// without it compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct EqHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> EqHalf {
    if (eq_idle()) {
        return EqHalf(vec4<f32>(0.0, 0.0, 0.0, 1.0), vec4<f32>(1.0e9, 0.0, 0.0, 0.0));
    }
    // (the dust in the air at half size, marched to alternately the nearest and the farthest depth of its two by two:
    // shaders/earthquake_dust.wgsl); beside it how far its ray went, for the join
    let v = eq_view(in, 1u);
    let len = select(length(v.rel), 1.0e9, v.sky);
    // (each of a two by two of its pixels marches a quarter of a stride on from the last: the join lays every pixel of
    // the picture over a whole two by two of them, so the four phases are one ray sampled four times as finely and no
    // grain is left to show)
    let hq = vec2<i32>(floor(in.position.xy));
    let phase = f32(((hq.x & 1) * 2) ^ ((hq.y & 1) * 3));
    // (and each two by two starts its own way into the stride, so what the four still miss is a soft grain, not bands)
    let dust = eqd_march(v, normalize(v.rel), len, (phase + ign(vec2<f32>(hq >> vec2<u32>(1u)))) * 0.25);
    return EqHalf(dust, vec4<f32>(min(len, 6.0e4), 0.0, 0.0, 0.0));
}
// The half-size stage at this pixel (whose ray goes `len` blocks): the nine of its pixels round it, each weighed by how
// much of a box two of them wide round this pixel it covers (always a whole two by two: the march's four phases in
// equal shares, so they never show as a stipple) and by how near the depth it was marched to is to this pixel's, so
// across the edge of a cliff or against the sky only those on this pixel's side count; if none is, the nearest in
// depth of them.
fn eq_up(pos: vec2<f32>, len: f32) -> vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h + 0.5));
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    for (var k = 0; k < 9; k = k + 1) {
        let o = vec2<i32>(k % 3, k / 3) - vec2<i32>(1);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let dq = h - vec2<f32>(i0);
        let bw = select(0.5 + f32(o.x) * dq.x, 1.0, o.x == 0) * select(0.5 + f32(o.y) * dq.y, 1.0, o.y == 0);
        let dz = abs(e.x - lp) / max(lp, 1.0);
        let w = bw * exp(-dz * 24.0);
        acc = acc + c * w;
        sw = sw + w;
        if (dz < near_dz) {
            near_dz = dz;
            near_c = c;
        }
    }
    if (sw < 1.0e-3) {
        return near_c;
    }
    return acc / sw;
}
@fragment
fn fs_join(in0: StageIn) -> @location(0) vec4<f32> {
    let in = eq_jolt(in0);
    if (eq_idle()) {
        return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);
    }
    let col = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0).rgb);
    let d = depth_at(in.uv);
    let dust = eq_up(in.position.xy, select(length(world_offset(in.uv, d)), 1.0e9, is_sky(d)));
    return eq_out(in, eqd_over(col, dust));
}
// [end half stage]
// ==== [end eq stages] =================================================================================================
