// Orbital Laser's post pass for the Supercell (laser 12). Like the Payload's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, project_rel, bolt_line, mh, ign) less the other lasers' own functions,
// followed by this file, and sets it for a supercell strike only. Validate with tools/check-shader.sh.

// ---- laser 12: the supercell --------------------------------------------------------------------------------------
// No beam. The sky darkens; a storm cloud boils up over the target and spreads: a broad, low, dark deck, a slowly
// turning wall cloud hanging under its middle with ragged scud round it, a tower climbing out of it into an anvil that
// spreads downwind. Rain falls out of it in streaked grey curtains (the world's weather is left alone). Then the storm: lightning strikes all over the land under it,
// faster and faster, each bolt a branching channel from the cloud's base to the ground, re-striking a few times, the
// cloud lit from inside round its root and the land round its foot lit bright; flickers inside the cloud between. A few
// thin funnels come down out of the wall cloud, touch, wander over the land in a swirl of dust and lift back up (the
// vortex section). Then the finale: a rapid run of bolts snapping down closer and closer onto the target, in time with
// its sound's cracks, some arcing in out of the ring round the wall cloud; a hush, the light gone out but for the
// leader racing down; then one colossal strike on the target, a single blinding channel, the ring of bolts round the
// wall cloud snapping into it in the same instant, held, a shockwave over the land and a jolt. Then the storm dies away.
// strike/storm.rs hands the bolts, the funnels' tracks and the flickers to the pass in its table (sc_table,
// render.set-data): keep the SC_* and VX_* in step.
const SC_FORMED: f32 = 6.5;        // the cloud is formed,
const SC_STORM0: f32 = 4.0;        // the flurry's lone small bolts strike from here,
const SC_WAVES: f32 = 15.0;        // more and more at once from here,
const SC_CONV: f32 = 24.0;         // drawn in onto the target from here
const SC_STORM1: f32 = 27.85;      // to here, then the finale's run-in (storm.rs's FIN_RUN)
const SC_FINALE: f32 = 29.0;       // collapsing into the colossal strike,
const SC_CLEAR: f32 = 32.5;        // the storm dying away from here,
const SC_LEN: f32 = 42.0;          // and gone by the strike's end (lasers.rs's length)
const SC_B: u32 = 16u;             // the table: the bolts from SC_B, SC_BW words each (t, x, z off the middle, ground),
const SC_BW: u32 = 4u;             // in the order they strike
const SC_NB: u32 = 140u;           // (room for this many)
const SC_F: u32 = 576u;            // the funnels from SC_F, VX_W words each (vortex.rs's vx_words)
const VX_W: u32 = 148u;
const VX_DT: f32 = 0.5;
const VX_DOWN: f32 = 3.5;
const SC_K: u32 = 1024u;           // the flickers in the cloud from SC_K (t, x, z)
const SC_I: u32 = 1192u;           // for each whole second, the first bolt still seen then (a u32)
const SC_NI: u32 = 64u;
// The cloud's heights over the target's ground: the deck's base, the wall cloud's (lower, under its middle), the
// deck's top, the tower's, and the anvil's underside and top.
const SC_BASE: f32 = 80.0;
const SC_WALL: f32 = 46.0;
const SC_TOP: f32 = 150.0;
const SC_TOWER: f32 = 315.0;
const SC_ANV0: f32 = 270.0;
const SC_ANV1: f32 = 335.0;

fn sc_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn sc_have() -> bool {
    return arrayLength(&mod_data) > SC_K;
}

// ---- helpers (as payload.wgsl's) ------------------------------------------------------------------------------------
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn pl_ray_seg(rd: vec3<f32>, a: vec3<f32>, b: vec3<f32>, lo: f32, hi: f32) -> vec3<f32> {
    let ab = b - a;
    let l2 = max(dot(ab, ab), 1.0e-6);
    let rab = dot(rd, ab);
    let den = l2 - rab * rab;
    var s = clamp(select(0.0, (rab * dot(rd, a) - dot(a, ab)) / den, den > 1.0e-6), lo, hi);
    let t = max(dot(rd, a + ab * s), 0.0);
    s = clamp(dot(rd * t - a, ab) / l2, lo, hi);
    return vec3<f32>(length(rd * t - (a + ab * s)), t, s);
}
// Cauliflower lumps (payload.wgsl's pl_dome): about 1 on a dome's crown, 0 in a crease.
fn pl_dome(p: vec3<f32>) -> f32 {
    let b = floor(p - 0.5);
    var hmax = 0.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let o = vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let cell = b + o;
        let q = bitcast<vec3<u32>>(vec3<i32>(cell));
        let h = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x51u)));
        let jit = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) * (0.7 / 1023.0) + 0.15;
        let sz = 0.7 + 0.55 * f32(pcg(h) & 1023u) / 1023.0;
        let e = cell + jit - p;
        hmax = max(hmax, sz * sqrt(saturate(1.0 - dot(e, e) * 1.7 / (sz * sz))));
    }
    return hmax;
}
fn pl_rot(k: i32, p: vec3<f32>) -> vec3<f32> {
    if (k == 0) {
        return mat3x3<f32>(-0.0014, 0.9977, -0.0674, -0.2224, -0.0660, -0.9727, -0.9750, 0.0136, 0.2220) * p;
    }
    return mat3x3<f32>(-0.6616, 0.1124, 0.7414, -0.4826, -0.8205, -0.3063, 0.5739, -0.5605, 0.5971) * p;
}
fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// ---- the storm's life ---------------------------------------------------------------------------------------------
// How far it has formed (0 to 1 over the build-up), and how much of it is left as it dies away.
fn sc_form(t: f32) -> f32 {
    return smoothstep(0.0, SC_FORMED, t);
}
fn sc_fade(t: f32) -> f32 {
    return 1.0 - smoothstep(SC_CLEAR, SC_LEN - 1.0, t);
}
// How far out the deck reaches, and the anvil.
fn sc_deck_r(t: f32) -> f32 {
    return 70.0 + 230.0 * smoothstep(0.2, SC_FORMED + 1.5, t);
}
fn sc_anvil_r(t: f32) -> f32 {
    return -40.0 + 340.0 * smoothstep(3.5, SC_FORMED + 6.5, t);
}
// How heavily it rains (0 to 1).
fn sc_rain(t: f32) -> f32 {
    return smoothstep(3.5, 8.0, t) * (1.0 - smoothstep(SC_CLEAR - 1.0, SC_CLEAR + 3.0, t));
}
// The deck's base over the ground at r out (the wall cloud hangs lower under its middle).
fn sc_base(r: f32) -> f32 {
    return mix(SC_BASE, SC_WALL, 1.0 - smoothstep(28.0, 70.0, r));
}

// ---- the cloud ------------------------------------------------------------------------------------------------------
// The cloud's smooth body at q (off the target's ground): positive inside, about one per dozen blocks in.
fn sc_shape(q: vec3<f32>, t: f32) -> f32 {
    let r = length(q.xz);
    let form = sc_form(t);
    let base = sc_base(r) + 14.0 * (1.0 - form);
    // (it builds up from a dark, flat layer: its top climbing, the tower last)
    let tower = 1.0 - smoothstep(80.0, 175.0, r);
    let full = mix(SC_TOP, SC_TOWER, tower * smoothstep(1.0, 6.2, t));
    let top = base + (full - base) * (0.3 + 0.7 * smoothstep(0.0, 4.4, t));
    let deck = min(min(q.y - base, top - q.y) / 14.0, (sc_deck_r(t) - r) / 45.0);
    // (the anvil: flat, spreading downwind of the tower, thinning out at its edge, its underside sagging to its middle)
    let qa = q.xz - vec2<f32>(80.0 * form, 10.0 * form);
    let ra = length(qa * vec2<f32>(0.8, 1.0));
    let ar = sc_anvil_r(t);
    let sag = 18.0 * (1.0 - smoothstep(0.0, ar, ra));
    let anv = min(min(q.y - (SC_ANV0 + 12.0 * smoothstep(0.3, 1.0, ra / ar) - sag), SC_ANV1 - 14.0 * smoothstep(0.4, 1.0, ra / ar) - q.y) / 12.0, (ar - ra) / 60.0) - 3.0 * (1.0 - smoothstep(3.5, 5.8, t));
    // (and as it dies away it is eaten away from its edges in, thinning to nothing, not just fading)
    return max(deck, anv) - 1.8 * (1.0 - smoothstep(0.0, 3.0, t)) - 9.0 * pow(1.0 - sc_fade(t), 1.3);
}
// The cloud's density at q (0 to 1), its lumps turning with the storm (faster in close, where the wall cloud turns),
// boiling up the tower; and in .y how far up its lumps lie (0 in a crease, 1 on a crown).
fn sc_den(q: vec3<f32>, t: f32, fine: bool) -> vec2<f32> {
    let sh = sc_shape(q, t);
    if (sh < -2.6) {
        return vec2<f32>(0.0, 0.0);
    }
    let r = length(q.xz);
    let low = 1.0 - smoothstep(SC_TOP, SC_ANV0, q.y);
    let ang = 0.12 * t * 60.0 / (60.0 + r) * low;
    let qr = vec3<f32>(rot2(q.xz, -ang), q.y).xzy;
    let boil = vec3<f32>(0.0, -0.9 * t, 0.0);
    let n1 = gnoise3(pl_rot(0, qr * (1.0 / 75.0)) + boil * (1.0 / 75.0));
    let n2 = gnoise3(pl_rot(1, qr * (1.0 / 27.0)) + vec3<f32>(3.1, -0.03 * t, 7.7));
    var d = sh + (n1 - 0.5) * 2.6 + (n2 - 0.5) * 1.2;
    var crown = 0.5;
    // (the tower's and the anvil's edges in cauliflower lumps, boiling)
    let tw = (1.0 - smoothstep(80.0, 180.0, r)) * smoothstep(SC_TOP - 20.0, SC_TOP + 20.0, q.y);
    if (fine && d > -1.2 && d < 1.0) {
        if (tw > 0.01) {
            crown = pl_dome(pl_rot(0, (qr + boil * 1.3) * (1.0 / 24.0)));
            d = d + (crown - 0.45) * 1.8 * tw;
        }
        let n3 = gnoise3(qr * (1.0 / 8.0) + vec3<f32>(0.0, -0.12 * t, 0.0));
        d = d + (n3 - 0.5) * 0.7;
    }
    // (ragged scud under the base round the wall cloud: wisps hanging lower, turning faster)
    let base = sc_base(r);
    let scud = (1.0 - smoothstep(30.0, 110.0, r)) * smoothstep(base - 26.0, base - 4.0, q.y) * (1.0 - smoothstep(base - 4.0, base + 4.0, q.y));
    if (scud > 0.01) {
        let qs = vec3<f32>(rot2(q.xz, -0.3 * t * 50.0 / (50.0 + r)), q.y).xzy;
        let ns = gnoise3(qs * (1.0 / 14.0) + vec3<f32>(5.0, 0.0, 1.0));
        d = max(d, (ns - 0.62) * 6.0 * scud * sc_form(t));
    }
    return vec2<f32>(saturate(d * 0.9) * sc_fade(t), crown);
}

// A flash lighting the cloud (camera-relative point, how bright).
struct ScFlash {
    p: array<vec4<f32>, 3>,
}

// ---- the bolts ------------------------------------------------------------------------------------------------------
// As lightning is: a faint stepped leader, a dim branching tree, creeping down from the cloud in a few frames
// (SC_LEAD); then the return stroke lighting the whole channel at once at full brightness; then two to four re-strokes
// flickering down the same channel over a few tenths of a second, each lasting several frames at 60 fps; a brief
// afterglow. The channel is tortuous: kinked every few blocks at every scale (piecewise-linear noise, so it bends
// sharply, never smoothly), forking downward in branches that taper and fade; a thin white-violet core in a wide bloom.
const SC_LEAD: f32 = 0.09;
// The return stroke and re-strokes of bolt `n` (its hash) `a` seconds after the return stroke: 1 at a stroke's peak.
fn sc_stroke(a: f32, n: u32) -> f32 {
    if (a < 0.0 || a > 1.0) {
        return 0.0;
    }
    let count = 2u + n % 3u;
    var s = 0.0;
    var ts = 0.0;
    for (var k = 0u; k <= count; k = k + 1u) {
        let h = f32(pcg(n * 13u + k) & 1023u) / 1023.0;
        let dk = select(0.05 + 0.1 * h, 0.0, k == 0u);
        ts = ts + dk;
        s = s + select(0.55 + 0.35 * h, 1.0, k == 0u) * exp(-max(a - ts, 0.0) / 0.045) * step(ts, a);
    }
    // (the channel glowing on faintly between the strokes, and after)
    return s + 0.1 * exp(-a / 0.35);
}
// The finale's run-in (storm.rs's FIN_RUN): the bolts struck after SC_STORM1, each on a crack of the finale's sound's
// run-in. Lightning as the eye sees it: no leader to see, the channel there at once at full brightness, gone in a few
// frames, a brief afterglow (a quarter of them re-striking once); and all of it out in the hush before the crack
// (`sc_hushcut`).
fn sc_snap(a: f32, n: u32) -> f32 {
    if (a < 0.0 || a > 0.5) {
        return 0.0;
    }
    let re = select(0.0, 0.5, (n & 3u) == 0u) * exp(-max(a - 0.055, 0.0) / 0.025) * step(0.055, a);
    return exp(-a / 0.03) + re + 0.12 * exp(-a / 0.1);
}
fn sc_is_run(t: f32) -> bool {
    return t > SC_STORM1;
}
// The hush before the crack (SC_SUCK, storm.rs's FIN_SUCK, in the strike's time): 1 in it, the light held back.
fn sc_hush(t: f32) -> f32 {
    let tf = t - SC_FINALE;
    return select(0.0, smoothstep(-SC_SUCK, -SC_SUCK + 0.03, tf), tf < 0.0);
}
// How much of the run-in's bolts is still seen at `t`: none from the hush on.
fn sc_hushcut(t: f32) -> f32 {
    return 1.0 - smoothstep(SC_FINALE - SC_SUCK, SC_FINALE - SC_SUCK + 0.03, t);
}
// Whether run-in bolt i arcs in out of the ring round the wall cloud (its root out in the ring, its channel running in
// under the cloud's base before it drops onto its foot), and if so its root and the bend where it turns down.
fn sc_arc(i: u32, seed: u32) -> bool {
    return mh(i, seed, 0x7au) < 0.4;
}
fn sc_arc_root(f: vec3<f32>, i: u32, seed: u32) -> vec3<f32> {
    let a = atan2(f.z, f.x) + 0.8 * (mh(i, seed, 0x7bu) - 0.5);
    let rr = 50.0 + 35.0 * mh(i, seed, 0x7cu);
    return vec3<f32>(cos(a) * rr, sc_base(rr) + 2.0, sin(a) * rr);
}
fn sc_arc_bend(f: vec3<f32>, root: vec3<f32>, i: u32, seed: u32) -> vec3<f32> {
    let k = 0.3 + 0.2 * mh(i, seed, 0x7du);
    return vec3<f32>(mix(f.x, root.x, k), mix(f.y, root.y, 0.7 + 0.15 * mh(i, seed, 0x7eu)), mix(f.z, root.z, k));
}
// The leader: how far down the cloud's branching tree has crept by `a` seconds after the return stroke (negative a).
fn sc_leader(a: f32) -> f32 {
    return saturate((a + SC_LEAD) / SC_LEAD);
}
// Bolt i: its foot (off the middle, on the ground) and when its return stroke is.
fn sc_bolt(i: u32) -> vec4<f32> {
    let o = SC_B + SC_BW * i;
    return vec4<f32>(sc_w(o + 1u), sc_w(o + 3u), sc_w(o + 2u), sc_w(o));
}
// The first bolt that can still be seen at `t` (the table's per-second index: the bolts are in the order they strike,
// so the pass looks only from it on, while they are due, never at the whole storm's).
fn sc_first(t: f32) -> u32 {
    let s = u32(clamp(floor(t), 0.0, f32(SC_NI - 1u)));
    if (SC_I + s >= arrayLength(&mod_data)) {
        return 0u;
    }
    return mod_data[SC_I + s];
}
// How big a bolt struck at `t` is: the flurry's small and thin, full size once the waves come, a little more as they
// draw in.
fn sc_size(t: f32) -> f32 {
    return mix(0.45, 1.0, smoothstep(SC_STORM0, SC_WAVES, t)) * (1.0 + 0.2 * smoothstep(SC_CONV, SC_FINALE, t));
}
// How far the bolts are drawn in at `t` (0 to 1): their roots to the wall cloud's middle, their feet onto the target.
fn sc_conv(t: f32) -> f32 {
    return smoothstep(SC_CONV, SC_FINALE, t);
}
// Whether bolt i is a positive bolt: a rarer, brighter one out of the anvil, from high and far off.
fn sc_positive(i: u32, seed: u32) -> bool {
    return mh(i, seed, 0x5au) < 0.08;
}
// Where a bolt's channel leaves the cloud over its foot f (off the middle): out of the base a little off to one side,
// or for a positive bolt out of the anvil's underside, high and further out.
// As the bolts draw in (`sc_conv` of when it struck, `t`) its root slides in under the wall cloud's middle, so the last
// waves spray down out of one knot of the cloud onto the land round the target.
fn sc_root(f: vec3<f32>, i: u32, seed: u32, t: f32) -> vec3<f32> {
    let a = TAU * mh(i, seed, 0x51u);
    let r = length(f.xz);
    var root = vec3<f32>(f.x + 22.0 * cos(a) * mh(i, seed, 0x52u), sc_base(r) + 4.0, f.z + 22.0 * sin(a) * mh(i, seed, 0x52u));
    if (sc_positive(i, seed)) {
        let out = f.xz / max(r, 1.0);
        root = vec3<f32>(f.x + out.x * 45.0, SC_ANV0 - 8.0, f.z + out.y * 45.0);
    }
    let knot = vec3<f32>(9.0 * cos(a), SC_WALL + 8.0, 9.0 * sin(a));
    return mix(root, knot, 0.9 * pow(sc_conv(t), 1.2));
}
// Piecewise-linear noise in [-1, 1]: sharp kinks, no smooth curves.
fn sc_lin(x: f32, s: f32) -> f32 {
    let i = floor(x);
    let f = x - i;
    return mix(fh21(vec2<f32>(i, s)), fh21(vec2<f32>(i + 1.0, s)), f) * 2.0 - 1.0;
}
// The channel's sideways kink at u of its way (0 its root, 1 its end), in its lengths: four scales of kinks, the
// finest every couple of blocks on a bolt of a hundred.
// (`fq`: how many times longer than a hundred blocks it is: a long bolt kinks as often along its length)
fn sc_kink(u: f32, s: f32, fq: f32) -> f32 {
    let v = u * fq;
    return (0.11 * sc_lin(v * 4.0, s) + 0.05 * sc_lin(v * 11.0, s + 1.7) + 0.024 * sc_lin(v * 29.0, s + 3.1) + 0.011 * sc_lin(v * 70.0, s + 5.3)) / sqrt(fq);
}
// One kinked channel on the picture from sa to sb (pixels), `w` its core's half-width there: x its core, y its bloom,
// z how far along it the nearest point is. The kink is pinned at the end (`pin`: the foot on the ground).
fn sc_channel(px: vec2<f32>, sa: vec2<f32>, sb: vec2<f32>, s: f32, w: f32, pin: bool, fq: f32) -> vec3<f32> {
    let ab = sb - sa;
    let L = max(length(ab), 1.0);
    let dir = ab / L;
    let nrm = vec2<f32>(-dir.y, dir.x);
    let ap = px - sa;
    let u = clamp(dot(ap, dir) / L, 0.0, 1.0);
    let env = select(1.0, sqrt(max(1.0 - u, 0.0)) * 1.15, pin) * smoothstep(0.0, 0.04, u);
    let k0 = sc_kink(u, s, fq) * env;
    let k1 = sc_kink(u + 0.002, s, fq) * env;
    let slope = (k1 - k0) / 0.002;
    let off = (dot(ap, nrm) - k0 * L) / sqrt(1.0 + slope * slope);
    let along = dot(ap, dir) - u * L;
    let d = length(vec2<f32>(off, along));
    let core = exp(-pow(d / w, 2.0));
    let g = 1.0 / (1.0 + pow(d / (w * 9.0), 2.0));
    return vec3<f32>(core, g * g, u);
}
// A bolt from root a to foot b (camera-relative), drawn on the picture: its channel and five forks (each kinked, branching
// down and out, tapering and fading), hidden by what stands in front of it. `lead`: how far down the leader has crept
// (1: the whole channel). x: the hot core, y: the bloom.
fn sc_draw_bolt(px: vec2<f32>, a: vec3<f32>, b: vec3<f32>, seed: f32, wmul: f32, lead: f32, scene_len: f32) -> vec2<f32> {
    let pa = project_rel(a);
    let pb = project_rel(b);
    if (pa.z < 0.0 || pb.z < 0.0) {
        return vec2<f32>(0.0);
    }
    let res = frame.resolution.xy;
    let sa = pa.xy * res;
    let sb = pb.xy * res;
    let ab = sb - sa;
    let L = max(length(ab), 1.0);
    let dist = length(0.5 * (a + b));
    let focal = res.y / (2.0 * tan(frame.view_params.w * 0.5));
    let w = clamp(0.35 * focal / dist, 0.7, 4.0) * wmul;
    // (far from it on the picture: nothing to draw)
    let u0 = saturate(dot(px - sa, ab) / (L * L));
    if (length(px - (sa + ab * u0)) > 0.45 * L + 40.0 * w) {
        return vec2<f32>(0.0);
    }
    let la = length(a);
    let lb = length(b);
    let fq = max(length(a - b) / 100.0, 1.0);
    let m = sc_channel(px, sa, sb, seed, w, true, fq);
    let seen = select(0.0, 1.0, scene_len > mix(la, lb, m.z) - 3.0) * smoothstep(lead + 0.01, lead - 0.01, m.z);
    var core = m.x * seen;
    var glow = m.y * seen;
    let dir = ab / L;
    let nrm = vec2<f32>(-dir.y, dir.x);
    for (var j = 0; j < 5; j = j + 1) {
        let fj = f32(j);
        let hu = fract(seed * 0.618 + fj * 0.377);
        let u = 0.1 + 0.62 * fract(hu + fj * 0.21);
        if (u > lead) {
            continue;
        }
        let root = sa + ab * u + nrm * sc_kink(u, seed, fq) * sqrt(1.0 - u) * 1.15 * L;
        let side = select(-1.0, 1.0, fract(seed * 0.71 + fj * 0.53) > 0.5);
        let bdir = normalize(dir + nrm * side * (0.55 + 0.6 * fract(seed * 1.3 + fj * 0.7)));
        let len = L * (0.12 + 0.22 * fract(seed * 0.9 + fj * 0.77)) * (1.0 - 0.5 * u);
        let f = sc_channel(px, root, root + bdir * len, seed + 7.0 + fj * 3.3, w * 0.55, false, fq);
        // (it creeps out as the leader passes it, and fades and thins along its length)
        let grown = smoothstep(f.z - 0.02, f.z + 0.02, (lead - u) * 3.0);
        let fade = pow(1.0 - f.z, 1.6);
        let fs = select(0.0, 1.0, scene_len > mix(la, lb, u + f.z * 0.25) - 3.0) * grown * fade;
        core = core + f.x * fs;
        glow = glow + f.y * fs * 0.7;
    }
    return vec2<f32>(core, glow);
}

// ---- the vortex: a funnel let down out of the cloud (vortex.rs) --------------------------------------------------
// A condensation funnel hanging from the wall cloud: wide where it leaves the cloud's base, tapering smoothly to a
// narrow cone or rope at the ground, leaning a little the way it travels and bending in a slow sinuous curve; its edge
// fairly sharp, wound with striations that spiral round it and up it as it turns, fastest near the ground. At its foot,
// once it nears the land, a squat debris cloud whirls up, wider than the funnel and dust-coloured, with pieces flung
// round it and out. It forms by lowering out of the cloud (the debris kicking up before it touches), matures, then
// ropes out (thinning to a twisted, sinuous rope) and lifts back up as it dies. Lit as the storm is: darker on its side
// away from the light, silhouetted against what is brighter behind it.
// A full tornado scales it: VX_RT (the cone's width at the cloud) and the foot's width with the funnel's touch radius
// (vortex.rs's `touch_r`), the debris cloud with it, the march's bound (vx_bound) with both.
const VX_ROPE: f32 = 4.0;          // it ropes out over this long before it is gone, lifting off over the last 1.6 (vortex.rs's VX_LIFT)
const VX_RT: f32 = 11.0;           // the cone's radius where it leaves the cloud's base
struct VxFunnel {
    foot: vec3<f32>,       // camera-relative, on the land (vortex.rs smooths the land under it)
    top: vec3<f32>,
    vel: vec2<f32>,        // its foot's way over the land, blocks a second
    low: f32,              // the share of it from the ground up not (yet, or any more) drawn
    touch: f32,            // how much it is on the land
    debris: f32,           // how much dust is whirled up round its foot
    rope: f32,             // how far it has roped out (0 mature, 1 a thin rope)
    r: f32,                // its touch radius
    spin: f32,
}
fn vx_at(k: u32, t: f32, C: vec3<f32>) -> VxFunnel {
    var f: VxFunnel;
    let o = SC_F + VX_W * k;
    let t0 = sc_w(o);
    let t1 = sc_w(o + 1u);
    let n = max(i32(sc_w(o + 2u) + 0.5), 1);
    let u = clamp((t - t0) / VX_DT, 0.0, f32(n - 1));
    let i = min(i32(floor(u)), max(n - 2, 0));
    let fr = u - f32(i);
    let a = o + 4u + 3u * u32(i);
    let b = o + 4u + 3u * u32(min(i + 1, n - 1));
    let pa = vec3<f32>(sc_w(a), sc_w(a + 2u), sc_w(a + 1u));
    let pb = vec3<f32>(sc_w(b), sc_w(b + 2u), sc_w(b + 1u));
    let p = mix(pa, pb, fr);
    f.foot = C + p;
    f.vel = (pb.xz - pa.xz) / VX_DT;
    // (its top in the wall cloud's base, drawn in towards the middle and ahead of its foot: it leans the way it goes)
    let top_xz = p.xz * 0.85 + f.vel * 1.2;
    f.top = C + vec3<f32>(top_xz.x, sc_base(length(top_xz)) + 3.0, top_xz.y);
    let down = smoothstep(t0, t0 + VX_DOWN, t);
    let lift = smoothstep(t1 - 1.6, t1, t);
    f.low = max(1.0 - down, lift);
    f.touch = smoothstep(t0 + 0.8 * VX_DOWN, t0 + VX_DOWN, t) * (1.0 - smoothstep(t1 - 1.8, t1 - 1.2, t));
    f.debris = smoothstep(t0 + 0.45 * VX_DOWN, t0 + VX_DOWN, t) * (1.0 - smoothstep(t1 - 2.0, t1 - 0.6, t));
    f.rope = smoothstep(t1 - VX_ROPE, t1 - 1.2, t);
    f.r = sc_w(o + 3u);
    f.spin = f32(k) * 2.1;
    if (t < t0 || t > t1) {
        f.low = 1.0;
        f.debris = 0.0;
    }
    return f;
}
// The funnel's radius at s of its way up (0 its foot, 1 the cloud's base): a narrow foot, flaring into the wide cone it
// hangs from; thinned to a rope as it dies.
fn vx_radius(f: VxFunnel, s: f32) -> f32 {
    let foot = (1.0 + 0.4 * f.r) * mix(1.0, 0.55, f.rope);
    let cone = mix(VX_RT, VX_RT * 0.35, f.rope);
    // (and as it lowers, its tip a narrowing point)
    let tip = smoothstep(f.low - 0.02, f.low + 0.3, s);
    return mix(foot, cone, pow(s, mix(3.5, 5.0, f.rope))) * mix(0.25, 1.0, tip);
}
// The funnel's axis at s of its way up: from its foot to its top, bending in a slow S that writhes as it turns, more
// as it ropes out.
fn vx_axis(f: VxFunnel, s: f32, t: f32) -> vec3<f32> {
    let along = mix(f.foot, f.top, s);
    let side = normalize(vec3<f32>(-(f.top - f.foot).z, 0.0, (f.top - f.foot).x) + vec3<f32>(1.0e-3, 0.0, 0.0));
    let amp = mix(3.0, 10.0, f.rope) * sin(3.14159 * s) * (1.0 - 0.7 * f.low);
    let w1 = sin(s * 5.0 - t * 0.9 + f.spin) * amp;
    let w2 = cos(s * 3.0 - t * 0.6 + f.spin * 1.3) * amp * 0.6;
    return along + side * w1 + vec3<f32>(side.z, 0.0, -side.x) * w2;
}
// How far round the funnel reaches from its axis (the march's bound): the cone, the debris cloud.
fn vx_bound(f: VxFunnel) -> f32 {
    return VX_RT + 14.0 + 3.0 * f.r;
}
// The funnel at camera-relative p: x its density, y its dust's, z how far it lies out on the funnel's surface (0 at the
// axis, 1 at its edge: the shading's side), w the striation there.
fn vx_den(f: VxFunnel, p: vec3<f32>, t: f32) -> vec4<f32> {
    let H = max(f.top.y - f.foot.y, 10.0);
    let s = saturate((p.y - f.foot.y) / H);
    let ax = vx_axis(f, s, t);
    let e = (p - ax).xz;
    let d = length(e);
    let th = atan2(e.y, e.x);
    // (it turns, fastest near the ground; its striations spiral round it and climb as it turns)
    let w = mix(9.0, 2.5, s);
    let thr = th - w * t - f.spin;
    let stri = 0.5 + 0.5 * sin(6.0 * thr + p.y * 0.55);
    let n = gnoise3(vec3<f32>(cos(thr) * 2.0, sin(thr) * 2.0, p.y * 0.09 - t * 1.4) + vec3<f32>(f.spin));
    let rs = vx_radius(f, s) * (0.9 + 0.12 * stri + 0.18 * (n - 0.5));
    let vis = smoothstep(f.low - 0.03, f.low + 0.03, s);
    let fun = smoothstep(rs, rs * 0.8, d) * (0.75 + 0.25 * stri) * vis;
    // (the debris cloud whirled round its foot: squat, ragged, dust-coloured, turning fast, wider than the funnel)
    var dust = 0.0;
    let hy = p.y - f.foot.y;
    if (f.debris > 0.01 && hy < 26.0) {
        let dd = length((p - f.foot).xz);
        let thd = atan2((p - f.foot).z, (p - f.foot).x) - 7.0 * t - f.spin;
        let rd0 = (5.0 + 2.6 * f.r) * (0.8 + 0.45 * gnoise3(vec3<f32>(cos(thd) * 1.8, sin(thd) * 1.8, hy * 0.12 - t * 0.6 + f.spin)));
        let top = 7.0 + 14.0 * smoothstep(rd0, 0.0, dd);
        dust = smoothstep(rd0, rd0 * 0.45, dd) * smoothstep(top, top * 0.3, hy) * smoothstep(-1.5, 1.0, hy) * f.debris;
        dust = dust * (0.55 + 0.45 * sin(3.0 * thd + hy * 0.4)) * 1.7;
    }
    return vec4<f32>(fun, dust, saturate(d / max(rs, 0.5)), stri);
}
// The pieces flung round a funnel's foot (a few dozen, each a tumbling dark speck orbiting and climbing, some thrown
// out), on the picture: how much of this pixel they cover.
fn vx_pieces(px: vec2<f32>, f: VxFunnel, t: f32, scene_len: f32) -> f32 {
    if (f.debris < 0.02) {
        return 0.0;
    }
    let res = frame.resolution.xy;
    let focal = res.y / (2.0 * tan(frame.view_params.w * 0.5));
    var cover = 0.0;
    for (var i = 0u; i < 16u; i = i + 1u) {
        let h = vec3<f32>(f32(pcg(i * 3u + 1u) & 1023u), f32(pcg(i * 3u + 2u) & 1023u), f32(pcg(i * 3u + 3u) & 1023u)) / 1023.0;
        let life = fract(t * (0.25 + 0.2 * h.x) + h.y);
        let r = (4.0 + 2.5 * f.r) * (0.7 + 0.6 * h.z) + 10.0 * life * life * step(0.7, h.x);
        let a = TAU * h.x + t * (5.0 - 2.5 * h.z) + f.spin;
        let y = 1.0 + 26.0 * life * (0.4 + 0.6 * h.y) - 30.0 * max(life - 0.75, 0.0);
        let q = f.foot + vec3<f32>(cos(a) * r, y, sin(a) * r);
        let pq = project_rel(q);
        if (pq.z < 0.0) {
            continue;
        }
        let dq = length(q);
        let sz = max(0.28 * focal / dq * (0.4 + 0.8 * h.z), 0.5);
        let dpx = length(px - pq.xy * res);
        cover = max(cover, smoothstep(sz + 0.7, sz - 0.3, dpx) * select(0.0, 1.0, scene_len > dq) * f.debris * smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.9, 1.0, life)));
    }
    return cover;
}

// What the volumetric part has gathered: colour (premultiplied), transmittance, and its distance.
// Rain in the world: drops falling along lines in the way they fall (`vel`, blocks a second: down, and blown), the
// lines' feet on a grid across that way, a jittered line a cell, the drops strung along each its own (length, speed,
// spacing, brightness, whether it is there: a hash a cell). Five layers out from the camera (`cq`, off the middle),
// each a coarser grid than the last: near drops big, fast and few, far ones fine and many. Only the cells the ray
// crosses in each layer are tried, so no direction is special: looking along the rain (straight up or down) the drops
// come end on, as dots, never converging on a point; nothing repeats on the picture. Hidden past `near`.
fn sc_rain_lines(rd: vec3<f32>, cq: vec3<f32>, vel: vec3<f32>, near: f32, time: f32) -> f32 {
    let spd = length(vel);
    let w = vel / max(spd, 1.0e-3);
    let e1 = normalize(cross(w, select(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 0.0), abs(w.x) < 0.9)));
    let e2 = cross(w, e1);
    let c2 = vec2<f32>(dot(cq, e1), dot(cq, e2));
    let r2 = vec2<f32>(dot(rd, e1), dot(rd, e2));
    let rr = dot(r2, r2);
    let rw = dot(rd, w);
    let aw0 = dot(cq, w);
    let focal = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
    var sum = 0.0;
    for (var k = 0; k < 5; k = k + 1) {
        let fk = f32(k);
        let cell = 0.45 * pow(1.9, fk);
        let ta = 1.3 * pow(1.9, fk);
        let tb = min(ta * 1.9, near);
        if (ta >= tb) {
            break;
        }
        let pa = c2 + r2 * ta;
        let pb = c2 + r2 * tb;
        var last = vec2<f32>(1.0e9);
        for (var n = 0; n < 6; n = n + 1) {
            let g = floor(mix(pa, pb, (f32(n) + 0.5) / 6.0) / cell);
            if (all(g == last)) {
                continue;
            }
            last = g;
            let hb = pcg(bitcast<u32>(i32(g.x)) * 0x9E3779B1u ^ pcg(bitcast<u32>(i32(g.y)) * 0x85EBCA6Bu ^ u32(k) * 0x27D4EB2Fu));
            // (in gusty sheets: the rain thicker and thinner in broad patches that drift past with the wind)
            let gust = vnoise(g * cell * (1.0 / 38.0) + vec2<f32>(0.0, time * 0.9 * spd / 38.0));
            if (f32(hb & 0xFFFFu) / 65535.0 > (0.4 + 0.12 * fk) * (0.25 + 1.5 * gust * gust)) {
                continue;
            }
            let hc = pcg(hb);
            var p = (g + vec2<f32>(0.15, 0.15) + 0.7 * vec2<f32>(f32(hc & 0xFFFFu), f32(hc >> 16u)) / 65535.0) * cell;
            // (where the ray passes nearest the line, and how near)
            var ts = clamp(select(0.5 * (ta + tb), dot(p - c2, r2) / rr, rr > 1.0e-6), ta, tb);
            // (each line a little off the wind's way: tilted its own way across it)
            let tilt = (vec2<f32>(f32((hc >> 3u) & 255u), f32((hc >> 11u) & 255u)) / 255.0 - 0.5) * 0.14;
            p = p + tilt * (aw0 + rw * ts);
            ts = clamp(select(0.5 * (ta + tb), dot(p - c2, r2) / rr, rr > 1.0e-6), ta, tb);
            let d = length(c2 + r2 * ts - p);
            let px = d * focal / ts;
            let wpx = 0.55 + 1.1 / (1.0 + fk);
            if (px > 3.0 * wpx) {
                continue;
            }
            // (the drops along it: is there one where the ray passes, over the stretch of the line the ray is that near)
            let hd = pcg(hc ^ 0x51u);
            let period = cell * (1.6 + 2.4 * f32(hd & 255u) / 255.0);
            let hl = f32((hd >> 8u) & 255u) / 255.0;
            let len = (cell * (0.15 + 0.9 * hl * hl) + spd * 0.008) / (1.0 + 0.3 * fk);
            let half_t = min(wpx * ts / focal / max(sqrt(rr), 1.0e-3), 0.5 * (tb - ta));
            let x0 = (aw0 + rw * (ts - half_t) - spd * (0.9 + 0.2 * f32((hd >> 16u) & 255u) / 255.0) * time) / period + f32(hd >> 24u) / 255.0;
            let x1 = x0 + 2.0 * abs(rw) * half_t / period;
            let lf = len / period;
            // (its head bright, its tail fading behind it)
            let fx = fract(x0);
            let on = select(step(fx, lf) * (0.25 + 0.75 * smoothstep(0.0, lf, fx)), 0.7, floor(x1) != floor(x0) || x1 - x0 >= 1.0);
            let hb2 = f32(hc & 255u) / 255.0;
            sum = sum + on * exp(-px * px / (wpx * wpx)) * (0.6 - 0.07 * fk) * (0.3 + 1.2 * hb2 * hb2);
        }
    }
    return sum;
}

struct ScVol {
    c: vec4<f32>,
    t: f32,
}
fn sc_over(h: ptr<function, vec4<f32>>, c: vec3<f32>, x: f32) {
    *h = vec4<f32>((*h).rgb * (1.0 - x) + c * x, (*h).a * (1.0 - x));
}

// How the flashes light a point of the cloud.
fn sc_flash_at(fl: ScFlash, p: vec3<f32>) -> f32 {
    var e = 0.0;
    for (var j = 0; j < 3; j = j + 1) {
        let f = fl.p[j];
        if (f.w > 0.001) {
            let d = p - f.xyz;
            e = e + f.w / (1.0 + dot(d, d) * (1.0 / 3200.0));
        }
    }
    return e;
}

// The cloud, the rain and the funnels along the ray rd (camera-relative), as far as `scene_len`.
fn sc_volume(rd: vec3<f32>, scene_len: f32, C: vec3<f32>, time: f32, j: f32, fl: ScFlash, L: vec3<f32>, amb: vec3<f32>, sunc: vec3<f32>, fine: bool) -> ScVol {
    var acc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var tmid = 0.0;
    var wmid = 0.0;
    let fc = vec3<f32>(0.75, 0.8, 1.15);
    let form = sc_form(time);
    let fade = sc_fade(time);
    // ---- the cloud: marched between its lowest base and the anvil's top, inside its widest reach -------------------
    let reach = max(sc_deck_r(time), sc_anvil_r(time) + 110.0) + 40.0;
    let ylo = C.y + SC_WALL - 30.0;
    let yhi = C.y + SC_ANV1 + 15.0;
    var t0 = 0.0;
    var t1 = scene_len;
    if (abs(rd.y) > 1.0e-5) {
        let ta = (ylo - 0.0) / rd.y;
        let tb = (yhi - 0.0) / rd.y;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    } else if (0.0 < ylo || 0.0 > yhi) {
        t1 = -1.0;
    }
    // (and the cylinder of its reach)
    let oc = -C.xz;
    let dxz = rd.xz;
    let qa = dot(dxz, dxz);
    let qb = dot(oc, dxz);
    let qc = dot(oc, oc) - reach * reach;
    let disc = qb * qb - qa * qc;
    if (disc <= 0.0 || qa < 1.0e-8) {
        if (qc > 0.0) {
            t1 = -1.0;
        }
    } else {
        let sq = sqrt(disc);
        t0 = max(t0, (-qb - sq) / qa);
        t1 = min(t1, (-qb + sq) / qa);
    }
    if (t1 > t0 && form * fade > 0.001) {
        let n = select(36, 56, fine);
        let span = t1 - t0;
        // (short steps in the cloud, at most 96 of them: a long ray through it is only seen through so far)
        let dt0 = clamp(span / f32(n), 2.5, 7.0);
        var dt = dt0;
        var t = t0 + dt * j;
        let ph = 0.75 + 0.6 * pow(saturate(dot(rd, L)), 6.0);
        for (var i = 0; i < 96; i = i + 1) {
            if (t > t1 || acc.a < 0.03) {
                break;
            }
            let p = rd * t;
            let q = p - C;
            let sh = sc_shape(q, time);
            if (sh < -3.0) {
                // (empty air: leap on, short of where the lumps could reach)
                t = t + max(dt, (-sh - 2.6) * 11.0);
                continue;
            }
            // (thinned round the eye: from inside it, or flying through its scud, the storm round about still shows)
            let dn = sc_den(q, time, fine) * vec2<f32>(smoothstep(12.0, 70.0, t), 1.0);
            if (dn.x > 0.003) {
                let r = length(q.xz);
                let base = sc_base(r);
                let tower = 1.0 - smoothstep(80.0, 175.0, r);
                let top = mix(SC_TOP, SC_TOWER, tower);
                let h01 = saturate((q.y - base) / max(top - base, 1.0));
                // (lit from above: deep in it, and its underside, dark; a look towards the sun for its own lumps)
                var sun_t = exp(-min(max(top - q.y, 0.0), 110.0) * 0.022);
                if (fine) {
                    let q2 = q + L * 16.0;
                    sun_t = sun_t * exp(-saturate(sc_shape(q2, time) + 0.5) * 1.4);
                }
                let anvil = smoothstep(SC_ANV0 - 30.0, SC_ANV0 + 10.0, q.y);
                sun_t = max(sun_t, anvil * 0.7);
                // (storm-grey, its base green-black, the tower's tops pale)
                let alb = mix(mix(vec3<f32>(0.1, 0.14, 0.11), vec3<f32>(0.3, 0.33, 0.31), smoothstep(0.0, 0.35, h01)), vec3<f32>(0.6, 0.61, 0.63), smoothstep(0.35, 1.0, h01)) * (0.85 + 0.3 * dn.y);
                let e = sc_flash_at(fl, p);
                let ambg = mix(amb, vec3<f32>(dot(amb, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.65);
                let c = alb * (ambg * (0.45 + 0.55 * h01) * (2.0 - fade) + sunc * mix(0.6, sun_t, fade) * 0.85 * ph) + fc * e * (0.5 + 0.5 * alb);
                let ext = dn.x * 0.07 * dt * (0.35 + 0.65 * fade);
                let al = 1.0 - exp(-ext);
                sc_over(&acc, c, al);
                tmid = tmid + acc.a * al * t;
                wmid = wmid + acc.a * al;
            }
            dt = dt0 * (0.8 + 0.4 * fract(j + f32(i) * 0.618)) * select(1.0, 2.0, dn.x < 0.003 && sh < -1.0);
            t = t + dt;
        }
    }
    // ---- the rain: grey veils falling out of the base, streaked, heaviest under the forward part of the storm ----
    let rk = sc_rain(time) * fade;
    if (rk > 0.001) {
        let rr = sc_deck_r(time) * 0.78;
        let yb = C.y + SC_BASE;
        var r0 = 0.0;
        var r1 = scene_len;
        if (abs(rd.y) > 1.0e-5) {
            let ta = (C.y - 4.0) / rd.y;
            let tb = yb / rd.y;
            r0 = max(r0, min(ta, tb));
            r1 = min(r1, max(ta, tb));
        }
        let qc2 = dot(oc, oc) - rr * rr;
        let disc2 = qb * qb - qa * qc2;
        if (disc2 > 0.0 && qa > 1.0e-8) {
            let sq = sqrt(disc2);
            r0 = max(r0, (-qb - sq) / qa);
            r1 = min(r1, (-qb + sq) / qa);
        } else if (qc2 > 0.0) {
            r1 = -1.0;
        }
        r1 = min(r1, r0 + 700.0);
        if (r1 > r0) {
            let nr = 10;
            let dtr = (r1 - r0) / f32(nr);
            var tr = 1.0;
            var cr = vec3<f32>(0.0);
            for (var i = 0; i < nr; i = i + 1) {
                let t = r0 + (f32(i) + j) * dtr;
                let p = rd * t;
                let q = p - C;
                let r = length(q.xz);
                // (the curtains: broad shafts hanging from the base, leaning and drifting with the wind, streaked by the rain
                // falling through them: its streaks drawn down fast; the wall cloud's middle drier)
                let sx = q.xz + vec2<f32>(0.3 * q.y + 3.0 * time, 0.0);
                let curtain = gnoise3(vec3<f32>(sx * (1.0 / 26.0), time * 0.06));
                let fall = gnoise3(vec3<f32>(sx.x * (1.0 / 3.0), (q.y + 32.0 * time) * (1.0 / 22.0), sx.y * (1.0 / 3.0)));
                // (streaked in long vertical bands that read as rain from far off)
                let bands = gnoise3(vec3<f32>(sx.x * (1.0 / 7.0), (q.y + 20.0 * time) * (1.0 / 90.0), sx.y * (1.0 / 7.0)));
                var den = rk * smoothstep(0.46, 0.64, curtain) * smoothstep(0.38, 0.62, bands) * (0.55 + 0.9 * smoothstep(0.45, 0.75, fall)) * (1.0 - smoothstep(rr * 0.6, rr, r)) * smoothstep(18.0, 50.0, length(q.xz - vec2<f32>(-20.0, 0.0)));
                den = den * smoothstep(-4.0, 6.0, q.y) * (1.0 - smoothstep(sc_base(r) - 10.0, sc_base(r), q.y));
                // (none close round the eye: the curtains are seen across the land, never a wall in front of the view)
                den = den * smoothstep(40.0, 140.0, t);
                if (den > 0.001) {
                    let e = sc_flash_at(fl, p);
                    let c = vec3<f32>(0.36, 0.39, 0.42) * (amb * 0.8 + sunc * 0.15) + fc * e * 0.35;
                    let al = 1.0 - exp(-den * 0.05 * dtr);
                    cr = cr + tr * al * c;
                    tr = tr * (1.0 - al);
                }
            }
            // (the rain is under the cloud: in front of what the cloud gathered, for an eye under it; never so thick that
            // the storm behind it, its bolts and its funnels, does not show through: at most 45% of it hidden)
            let keep = max(tr, 0.55);
            cr = cr * (1.0 - keep) / max(1.0 - tr, 1.0e-4);
            acc = vec4<f32>(cr + keep * acc.rgb, keep * acc.a);
            if (tr < 0.98 && wmid < 1.0e-3) {
                tmid = 0.5 * (r0 + r1);
                wmid = 1.0;
            }
        }
    }
    // ---- the funnels ---------------------------------------------------------------------------------------------------
    if (sc_have()) {
        let nf = u32(sc_w(2u) + 0.5);
        for (var k = 0u; k < min(nf, 4u); k = k + 1u) {
            let f = vx_at(k, time, C);
            if (f.low >= 0.999) {
                continue;
            }
            let bnd = vx_bound(f);
            let sg = pl_ray_seg(rd, f.foot, f.top, 0.0, 1.0);
            if (sg.x > bnd || sg.y - bnd > scene_len) {
                continue;
            }
            // (marched only across it: its width where the ray passes nearest, and the dust's round its foot)
            let half = vx_radius(f, sg.z) * 1.3 + 4.0 + select(0.0, 6.0 + 3.0 * f.r, sg.z < 0.4);
            let ft0 = max(sg.y - half, 0.0);
            let ft1 = min(sg.y + half, scene_len);
            let nn = select(18, 26, fine);
            let fdt = (ft1 - ft0) / f32(nn);
            var fa = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            var ftm = 0.0;
            for (var i = 0; i < nn; i = i + 1) {
                let t = ft0 + (f32(i) + j) * fdt;
                let p = rd * t;
                // (only under the cloud's base: inside it the cloud hides it, and its cone merges into the base)
                let qb = p - C;
                let v4 = vx_den(f, p, time);
                // (inside the cloud the cloud hides it: where the cloud's smooth body begins, it is gone)
                let dd = v4.xy * smoothstep(0.4, -0.6, sc_shape(qb, time)) * smoothstep(sc_base(length(qb.xz)) + 1.0, sc_base(length(qb.xz)) - 6.0, qb.y);
                let den = dd.x + dd.y;
                if (den > 0.002) {
                    let e = sc_flash_at(fl, p);
                    let s01 = saturate((p.y - f.foot.y) / max(f.top.y - f.foot.y, 1.0));
                    // (lit as the storm is: the side towards the light and the sky paler, the far side and the cone
                    // under the cloud darker, the striations' grooves a little darker)
                    let ax = vx_axis(f, s01, time);
                    let nrm = normalize(vec3<f32>((p - ax).x, 0.0, (p - ax).z) + vec3<f32>(0.0, 1.0e-3, 0.0));
                    let lit = 0.55 + 0.45 * dot(nrm, normalize(vec3<f32>(L.x, 0.0, L.z) + vec3<f32>(1.0e-3, 0.0, 0.0)));
                    let rim = smoothstep(0.55, 1.0, v4.z);
                    let fcol = mix(vec3<f32>(0.16, 0.18, 0.18), vec3<f32>(0.27, 0.29, 0.3), s01 * 0.5 + 0.5 * rim) * (0.8 + 0.25 * v4.w) * (1.0 - 0.4 * smoothstep(0.7, 1.0, s01));
                    let dcol = vec3<f32>(0.36, 0.3, 0.22);
                    let alb = (fcol * dd.x + dcol * dd.y) / den;
                    let c = alb * (amb * (0.75 + 0.6 * lit) + sunc * 0.15 * lit) + fc * e * 0.5 * alb;
                    let al = 1.0 - exp(-den * 0.9 * fdt);
                    sc_over(&fa, c, al);
                    ftm = ftm + t * al;
                    if (fa.a < 0.03) {
                        break;
                    }
                }
            }
            if (fa.a < 0.999) {
                // (under the cloud: in front of what the cloud gathered, unless the eye looks down through it)
                let ftd = ftm / max(1.0 - fa.a, 1.0e-3);
                let mid = tmid / max(wmid, 1.0e-4);
                if (wmid < 1.0e-3 || ftd < mid) {
                    acc = vec4<f32>(fa.rgb + fa.a * acc.rgb, fa.a * acc.a);
                } else {
                    acc = vec4<f32>(acc.rgb + acc.a * fa.rgb, fa.a * acc.a);
                }
                tmid = tmid + ftd * (1.0 - fa.a) * 4.0;
                wmid = wmid + (1.0 - fa.a) * 4.0;
            }
        }
    }
    var o: ScVol;
    o.c = acc;
    o.t = select(1.0e9, tmid / max(wmid, 1.0e-4), wmid > 1.0e-4);
    return o;
}

struct PlOut {
    c: vec4<f32>,
    e: vec4<f32>,
}

// The pass, in one of three stages: 0 the whole of it at full size (fs_main); 1 the half-size stage (fs_half: the
// cloud, the rain and the funnels, over a two by two of the picture's pixels), as premultiplied colour and
// transmittance; 2 the join (fs_join: the rest, sharp, at full size, with the half-size stage's `up` laid over).
fn supercell(in: StageIn, stage: u32, up: vec4<f32>) -> PlOut {
    var uv = in.uv;
    let time = now();
    let k = intensity_v();
    let seed = u32(seed_v());
    let anc = anchor_xz();
    let cam = frame.camera_position.xyz;
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let sun_up = smoothstep(-0.12, 0.06, sun.y);
    let warm = (1.0 - smoothstep(0.02, 0.4, sun.y)) * smoothstep(-0.2, -0.02, sun.y);
    let moon = smoothstep(-0.02, -0.2, sun.y);
    let L = normalize(select(-sun, sun, sun.y > -0.04) + vec3<f32>(0.0, 0.03, 0.0));
    var d = 0.0;
    if (stage == 1u) {
        let full = vec2<i32>(frame.resolution.xy);
        let q = vec2<i32>(floor(in.position.xy)) * 2;
        let q1 = min(q + vec2<i32>(1), full - vec2<i32>(1));
        let d0 = textureLoad(scene_depth, q, 0);
        let d1 = textureLoad(scene_depth, vec2<i32>(q1.x, q.y), 0);
        let d2 = textureLoad(scene_depth, vec2<i32>(q.x, q1.y), 0);
        let d3 = textureLoad(scene_depth, q1, 0);
        let hq = vec2<i32>(floor(in.position.xy));
        d = select(min(min(d0, d1), min(d2, d3)), max(max(d0, d1), max(d2, d3)), ((hq.x + hq.y) & 1) == 0);
        uv = (vec2<f32>(q) + 1.0) * frame.resolution.zw;
    } else {
        d = depth_at(uv);
    }
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    let form = sc_form(time) * sc_fade(time);
    let have = sc_have();

    // (the light, matched to the scene's: its sky, the sun's or the moon's)
    var skyl = srgb_to_linear(frame.sky_color.rgb);
    let amb0 = mix(vec3<f32>(0.02, 0.025, 0.035), skyl * 0.55 + vec3<f32>(0.03), day);
    let amb = amb0 * mix(1.0, 0.55, form);
    let sunc = (mix(vec3<f32>(1.25, 1.18, 1.05), vec3<f32>(1.4, 0.62, 0.3), warm) * sun_up + vec3<f32>(0.05, 0.07, 0.11) * moon) * mix(1.0, 0.6, form);

    // ---- the flashes: the bolts striking now and the flickers in the cloud, the three brightest kept for the cloud ---
    var fl: ScFlash;
    fl.p[0] = vec4<f32>(0.0);
    fl.p[1] = vec4<f32>(0.0);
    fl.p[2] = vec4<f32>(0.0);
    // (and the brightest bolt's own light on the land)
    var gflash = vec3<f32>(0.0);
    var sky_flash = 0.0;
    let tf = time - SC_FINALE;
    if (have) {
        let nb = min(u32(sc_w(0u) + 0.5), SC_NB);
        for (var i = sc_first(time); i < nb; i = i + 1u) {
            let b = sc_bolt(i);
            let a = time - b.w;
            if (a < 0.0) {
                break;
            }
            if (a > 1.0) {
                continue;
            }
            let run = sc_is_run(b.w);
            var I = sc_stroke(a, pcg(i ^ seed)) * select(1.0, 1.6, sc_positive(i, seed)) * sc_size(b.w);
            var root = C + sc_root(b.xyz, i, seed, b.w);
            if (run) {
                I = sc_snap(a, pcg(i ^ seed)) * sc_hushcut(time) * sc_size(b.w) * 1.1;
                if (sc_arc(i, seed)) {
                    root = C + sc_arc_root(b.xyz, i, seed);
                }
            }
            let foot = C + b.xyz;
            let fp = vec4<f32>(root + vec3<f32>(0.0, 20.0, 0.0), I * 2.5);
            // (kept if brighter than the dimmest held)
            var lo = 0;
            if (fl.p[1].w < fl.p[lo].w) { lo = 1; }
            if (fl.p[2].w < fl.p[lo].w) { lo = 2; }
            if (fp.w > fl.p[lo].w) { fl.p[lo] = fp; }
            if (stage != 1u && !sky) {
                let dl = length(rel - foot);
                gflash = gflash + vec3<f32>(0.8, 0.85, 1.1) * I * 5.0 / (1.0 + dl * dl / 300.0);
            }
            sky_flash = sky_flash + I * 0.5 / (1.0 + length(foot) / 300.0);
        }
        let nk = u32(sc_w(3u) + 0.5);
        for (var i = 0u; i < min(nk, 64u); i = i + 1u) {
            let o = SC_K + 3u * i;
            let a = time - sc_w(o);
            if (a < 0.0 || a > 0.7) {
                continue;
            }
            // (a flicker: two or three quick pulses)
            let I = (exp(-a / 0.06) + 0.7 * exp(-max(a - 0.14, 0.0) / 0.05) * step(0.14, a) + 0.5 * exp(-max(a - 0.33, 0.0) / 0.06) * step(0.33, a)) * 1.6 * (1.0 - sc_hush(time));
            let p = C + vec3<f32>(sc_w(o + 1u), SC_BASE + 40.0 + 60.0 * mh(i, seed, 0x61u), sc_w(o + 2u));
            let fp = vec4<f32>(p, I);
            var lo = 0;
            if (fl.p[1].w < fl.p[lo].w) { lo = 1; }
            if (fl.p[2].w < fl.p[lo].w) { lo = 2; }
            if (fp.w > fl.p[lo].w) { fl.p[lo] = fp; }
            sky_flash = sky_flash + I * 0.12 / (1.0 + length(p) / 300.0);
        }
    }
    // (the finale's: a knot of bolts on the target, blinding, lighting the cloud over it hard)
    var fin = 0.0;
    if (tf > 0.0 && tf < 3.0) {
        // (held: the channel burning on for two seconds, re-struck again and again)
        fin = 0.4 * (1.0 - smoothstep(1.6, 2.4, tf)) * (0.75 + 0.25 * sin(tf * 41.0));
        for (var n = 0; n < 7; n = n + 1) {
            let ts = array<f32, 7>(0.0, 0.12, 0.3, 0.52, 0.8, 1.12, 1.5)[n];
            fin = fin + (1.0 - 0.09 * f32(n)) * exp(-max(tf - ts, 0.0) / 0.08) * step(ts, tf);
        }
        fl.p[0] = vec4<f32>(C + vec3<f32>(0.0, SC_WALL + 14.0, 0.0), fin * 2.2);
        if (stage != 1u && !sky) {
            let dl = length(rel - C);
            gflash = gflash + vec3<f32>(0.85, 0.88, 1.1) * fin * 18.0 / (1.0 + dl * dl / 2500.0);
        }
        sky_flash = sky_flash + fin * 0.6 / (1.0 + length(C) / 400.0);
    }

    // ---- the land in the storm's gloom: darker and a little green under the cloud, and lit by the bolts --------------
    if (stage != 1u) {
        if (!sky) {
            let rr = length((rel - C).xz);
            let cover = form * (1.0 - smoothstep(sc_deck_r(time) * 0.75, sc_deck_r(time) * 1.05, rr));
            // (and wet where the rain falls: darker, a little cooler)
            let wet = sc_rain(time) * sc_fade(time) * (1.0 - smoothstep(sc_deck_r(time) * 0.55, sc_deck_r(time) * 0.8, rr));
            // (the storm's shadow reaching on past its deck, under the anvil and the murk round it: the land round a
            // player watching from a few hundred blocks off dims too, not just what lies under the cloud)
            let shade = form * (1.0 - smoothstep(sc_deck_r(time), sc_deck_r(time) * 1.9, rr));
            col = col * (1.0 - 0.3 * form - 0.42 * cover) * (1.0 - 0.3 * shade * (1.0 - cover)) * mix(vec3<f32>(1.0), vec3<f32>(0.9, 1.0, 0.94), max(cover, 0.6 * shade)) * mix(vec3<f32>(1.0), vec3<f32>(0.84, 0.86, 0.9), wet);
            col = col + scene * gflash * k;
            // (the finale's shockwave: a bright ring racing out over the land at 140 blocks a second, as its edits go,
            // a wall of dust and smoke rising behind it, settling into a haze)
            if (tf > 0.0 && tf < 5.0) {
                let front = 140.0 * tf;
                let e = rr - front;
                let ring = exp(-pow(e / 6.0, 2.0)) * exp(-tf / 1.6);
                let behind = smoothstep(4.0, -30.0, e) * exp(-tf / 2.2) * smoothstep(0.0, 25.0, rr);
                col = col + (scene * 2.2 + vec3<f32>(0.25, 0.22, 0.18)) * ring * k;
                col = mix(col, vec3<f32>(0.2, 0.18, 0.16) * (amb0 * 2.0 + vec3<f32>(0.08)), 0.45 * behind * k);
                // (the crater glowing where the strike fused it, cooling)
                col = col + vec3<f32>(2.6, 0.9, 0.25) * exp(-max(rr - 6.0, 0.0) / 9.0) * exp(-tf / 1.8) * k;
            }
        } else {
            let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
            col = mix(col, vec3<f32>(lum) * vec3<f32>(0.92, 1.0, 0.95), 0.6 * form) * (1.0 - 0.62 * form);
        }
        // (everything flickering brighter with the flashes, the sky most)
        col = col + (scene * 0.5 + amb0 * 0.4 + vec3<f32>(0.01)) * vec3<f32>(0.8, 0.85, 1.1) * min(sky_flash, 2.5) * select(0.5, 1.0, sky) * k;
    }

    // ---- the cloud, the rain and the funnels -------------------------------------------------------------------------
    var vol_t = 1.0e9;
    var vol_a = 1.0;
    if (stage == 2u) {
        col = col * up.a + up.rgb;
        vol_a = up.a;
    } else if (time < SC_LEN) {
        let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
        let v = sc_volume(rd, scene_len, C, time, j, fl, L, amb, sunc, true);
        vol_t = v.t;
        vol_a = v.c.a;
        if (stage == 0u) {
            let kk = k;
            col = col * mix(1.0, v.c.a, kk) + v.c.rgb * kk;
        } else {
            let srgb_h = v.c;
            return PlOut(vec4<f32>(srgb_h.rgb * k, mix(1.0, srgb_h.a, k)), vec4<f32>(min(scene_len, 6.0e4), select(1.0e9, v.t, v.t < 1.0e8), 0.0, 0.0));
        }
    }

    // ---- the bolts, over it all (hidden by the cloud only for an eye above it) ----------------------------------------
    let cam_above = smoothstep(C.y + SC_TOP - 20.0, C.y + SC_TOP + 20.0, 0.0);
    let behind = mix(1.0, vol_a, cam_above);
    // (the hush before the crack: the light held back, the land and the cloud a breath darker)
    let hush = sc_hush(time);
    col = col * (1.0 - 0.32 * hush * k);
    // (the pieces flung round the funnels' feet: dark specks against the dust and the sky)
    if (have) {
        let nf = u32(sc_w(2u) + 0.5);
        for (var kf = 0u; kf < min(nf, 4u); kf = kf + 1u) {
            let f = vx_at(kf, time, C);
            if (f.debris < 0.02) {
                continue;
            }
            let sg = pl_ray_seg(rd, f.foot, f.foot + vec3<f32>(0.0, 30.0, 0.0), 0.0, 1.0);
            if (sg.x < 14.0 + 3.0 * f.r) {
                let cv = vx_pieces(in.position.xy, f, time, scene_len);
                col = mix(col, vec3<f32>(0.07, 0.06, 0.05) * (amb0 + vec3<f32>(0.05)), cv * k);
            }
        }
    }
    if (have) {
        let px = in.position.xy;
        let nb = min(u32(sc_w(0u) + 0.5), SC_NB);
        var core = 0.0;
        var glow = 0.0;
        for (var i = sc_first(time); i < nb; i = i + 1u) {
            let b = sc_bolt(i);
            let a = time - b.w;
            if (a < -SC_LEAD) {
                break;
            }
            if (a > 1.0) {
                continue;
            }
            let pos = sc_positive(i, seed);
            let root = C + sc_root(b.xyz, i, seed, b.w);
            let foot = C + b.xyz;
            let sd = f32(pcg(i * 7u + seed) % 1000u) * 0.13 + 3.0;
            let sz = sc_size(b.w);
            if (sc_is_run(b.w)) {
                // (the run-in's: there at once, no leader; an arcing one in two legs, in under the cloud's base from the
                // ring and then down)
                let I = sc_snap(a, pcg(i ^ seed)) * sc_hushcut(time) * 1.3;
                if (I < 0.004) {
                    continue;
                }
                if (sc_arc(i, seed)) {
                    let ra = C + sc_arc_root(b.xyz, i, seed);
                    let bend = C + sc_arc_bend(b.xyz, ra - C, i, seed);
                    let m0 = sc_draw_bolt(px, ra, bend, sd + 1.9, 0.9 * sz, 1.0, scene_len);
                    let m1 = sc_draw_bolt(px, bend, foot, sd, 1.15 * sz, 1.0, scene_len);
                    core = core + (m0.x + m1.x) * I;
                    glow = glow + (m0.y + m1.y) * I;
                } else {
                    let m = sc_draw_bolt(px, root, foot, sd, 1.15 * sz, 1.0, scene_len);
                    core = core + m.x * I;
                    glow = glow + m.y * I;
                }
                continue;
            }
            if (a < 0.0) {
                // (the stepped leader: a dim branching tree creeping down)
                let m = sc_draw_bolt(px, root, foot, sd, 0.6 * sz, sc_leader(a), scene_len);
                core = core + m.x * 0.12;
                glow = glow + m.y * 0.1;
                continue;
            }
            let I = sc_stroke(a, pcg(i ^ seed)) * select(1.0, 1.5, pos) * mix(0.6, 1.0, sz);
            let m = sc_draw_bolt(px, root, foot, sd, select(1.0, 1.6, pos) * sz, 1.0, scene_len);
            core = core + m.x * I;
            glow = glow + m.y * I;
        }
        // (spider lightning: some of the flickers crawl along the cloud's base in branching channels)
        let nk = u32(sc_w(3u) + 0.5);
        for (var i = 0u; i < min(nk, 64u); i = i + 1u) {
            if (mh(i, seed, 0x62u) > 0.5) {
                continue;
            }
            let o = SC_K + 3u * i;
            let a = time - sc_w(o);
            if (a < 0.0 || a > 0.5) {
                continue;
            }
            let p0 = vec3<f32>(sc_w(o + 1u), 0.0, sc_w(o + 2u));
            let ang = TAU * mh(i, seed, 0x63u);
            let len = 60.0 + 80.0 * mh(i, seed, 0x64u);
            let p1 = p0 + vec3<f32>(cos(ang) * len, 0.0, sin(ang) * len);
            let ra = C + vec3<f32>(p0.x, sc_base(length(p0.xz)) - 2.0, p0.z);
            let rb = C + vec3<f32>(p1.x, sc_base(length(p1.xz)) - 2.0, p1.z);
            let I = (exp(-a / 0.07) + 0.6 * exp(-max(a - 0.15, 0.0) / 0.06) * step(0.15, a)) * 0.6 * (1.0 - hush);
            let m = sc_draw_bolt(px, ra, rb, f32(i) * 3.7 + 11.0, 0.7, saturate(a / 0.12), scene_len);
            core = core + m.x * I;
            glow = glow + m.y * I;
        }
        // (in the hush, the one channel's leader racing down out of the wall cloud onto the target, faint, its tearing
        // what is heard then; the return stroke lights the same path)
        let main_root = C + vec3<f32>(0.0, SC_WALL + 6.0, 0.0);
        let main_sd = f32(seed % 13u);
        if (tf > -SC_SUCK && tf < 0.0) {
            let lead = pow(saturate((tf + SC_SUCK) / SC_SUCK), 1.5);
            let m = sc_draw_bolt(px, main_root, C, main_sd, 1.2, lead, scene_len);
            core = core + m.x * 0.14;
            glow = glow + m.y * 0.08;
        }
        if (fin > 0.0) {
            // (the one channel, blinding, held and re-struck)
            let m = sc_draw_bolt(px, main_root, C, main_sd, 6.5, 1.0, scene_len);
            core = core + m.x * fin;
            glow = glow + m.y * fin;
            // (and in the same instant the ring of bolts round the wall cloud snapping into it, from all round, each
            // striking its channel part way down; gone in a few frames, into it, as the whiteout clears)
            let sp = exp(-tf / 0.08) * step(tf, 0.4);
            if (sp > 0.01) {
                for (var i = 0u; i < 9u; i = i + 1u) {
                    let a = TAU * (f32(i) + 0.4 * mh(i, seed, 0x71u)) / 9.0 + f32(seed % 7u);
                    let rr = 50.0 + 35.0 * mh(i, seed, 0x72u);
                    let root = C + vec3<f32>(cos(a) * rr, sc_base(rr) + 2.0, sin(a) * rr);
                    let hit = C + vec3<f32>(0.0, 12.0 + 28.0 * mh(i, seed, 0x73u), 0.0);
                    let m = sc_draw_bolt(px, root, hit, f32(i) * 23.1 + 5.0 + f32(seed % 11u), 2.2, 1.0, scene_len);
                    core = core + m.x * sp * 1.6;
                    glow = glow + m.y * sp * 1.4;
                }
            }
        }
        col = col + (vec3<f32>(2.4, 2.4, 3.2) * min(core, 3.0) * 2.4 + vec3<f32>(0.42, 0.4, 1.0) * glow * 1.2) * behind * k;
    }
    // (the finale: the picture whited out for an instant, fading as the eye recovers, less from far off)
    if (tf > 0.0 && tf < 1.5) {
        let near = 1.0 / (1.0 + length(C) / 350.0);
        let wo = (0.65 * exp(-tf / 0.08) + 0.2 * exp(-tf / 0.6)) * near * k;
        col = mix(col, vec3<f32>(1.3, 1.32, 1.45), saturate(wo));
    }

    // ---- the rain close by, for an eye under the storm: drops in the world round the camera (`sc_rain_lines`, as the
    // Hurricane's: the same at any pitch, looking straight up or down), slanted a little by the wind, more of them
    // out at the edges of the picture than across its middle, hidden by what stands in front, only under the base
    let rk = sc_rain(time) * sc_fade(time);
    if (rk > 0.01 && stage != 1u) {
        let res = frame.resolution.xy;
        let edge = mix(0.3, 1.0, smoothstep(0.12, 0.48, length((uv - 0.5) * vec2<f32>(res.x / res.y, 1.0))));
        let cq = -C;
        let under = (1.0 - smoothstep(sc_deck_r(time) * 0.6, sc_deck_r(time) * 0.8, length(cq.xz))) * (1.0 - smoothstep(sc_base(length(cq.xz)) - 20.0, sc_base(length(cq.xz)), cq.y));
        let streak = sc_rain_lines(rd, cq, vec3<f32>(2.2, -16.0, 0.8), scene_len, time) * under * 0.8;
        col = col + vec3<f32>(0.62, 0.66, 0.72) * streak * rk * edge * (amb0 * 0.7 + vec3<f32>(0.02) + vec3<f32>(0.7) * min(sky_flash, 2.0)) * k;
    }

    let srgb = linear_to_srgb(max(col, vec3<f32>(0.0)));
    if (capture() > 2.5) {
        let sp = floor(in.position.xy);
        let chk = fract((sp.x + sp.y) * 0.5);
        let ycc_y = srgb.g * 0.5 + (srgb.r + srgb.b) * 0.25;
        let ycc_co = srgb.r - srgb.b;
        let ycc_cg = srgb.g - (srgb.r + srgb.b) * 0.5;
        return PlOut(vec4<f32>(ycc_y, select(ycc_cg, ycc_co, chk < 0.25) * 0.5 + 0.5, 0.0, 1.0), vec4<f32>(0.0));
    }
    return PlOut(vec4<f32>(srgb, 1.0), vec4<f32>(0.0));
}

// ---- the finale's jolt: the picture slammed and shaken as its crack reaches the player, as hard as the Rod's (rod.wgsl's
// pl_jolt): a slam swinging hard three or four times in half a second, a shudder fading over a couple of seconds ----
// How long before its crack reaches the player the finale's hush falls (storm.rs's FIN_SUCK: the beds cut, the run-in
// fallen away, only the leader's tearing rising into it; the pass holds its light back then, `sc_hush`).
const SC_SUCK: f32 = 0.16;
// Seconds since the finale's crack reached the player (negative before), and how much of it reaches them.
fn sc_heard() -> vec2<f32> {
    let C = vec3<f32>(anchor_xz().x, block_y() + 1.0, anchor_xz().y);
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z);
    let dist = length(me - C);
    return vec2<f32>(now() - SC_FINALE - 0.05 - dist / 343.0, clamp(1.5 / (1.0 + dist / 350.0), 0.2, 1.0));
}
fn sc_jolt(in: StageIn) -> StageIn {
    let h = sc_heard();
    let s = h.x;
    if (s <= 0.0 || s > 6.0 || intensity_v() <= 0.0) {
        return in;
    }
    let g = h.y;
    let hit = 0.034 * g * exp(-s / 0.22) * smoothstep(0.0, 0.015, s);
    let ring = vec2<f32>(0.65 * sin(s * 53.0 + 0.6) + 0.35 * sin(s * 89.0 + 2.1), 0.65 * cos(s * 47.0 + 1.3) + 0.35 * sin(s * 77.0 + 0.4));
    let shud = 0.005 * g * exp(-s / 1.8) * smoothstep(0.08, 0.4, s);
    let sh = vec2<f32>(0.55 * sin(s * 17.0 + 0.3) + 0.3 * sin(s * 29.0 + 1.9) + 0.15 * sin(s * 53.0),
                       0.55 * cos(s * 15.0 + 2.2) + 0.3 * sin(s * 31.0 + 0.7) + 0.15 * cos(s * 59.0));
    let off = ring * hit + sh * shud;
    let roll = 0.018 * g * exp(-s / 0.3) * sin(s * 41.0 + 0.9) + 0.0025 * g * exp(-s / 1.8) * sin(s * 11.0);
    let res = frame.resolution.xy;
    let asp = res.x / res.y;
    let zoom = 1.0 + 2.2 * (hit + shud) + 1.1 * abs(roll) * asp;
    var q = (in.uv - 0.5) * vec2<f32>(asp, 1.0) / zoom;
    q = vec2<f32>(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll)) + off;
    var o = in;
    o.uv = clamp(q / vec2<f32>(asp, 1.0) + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    o.position = vec4<f32>(o.uv * res, in.position.zw);
    return o;
}
// The pressure of it on the picture, with the sound: in the hush before the crack the picture drawn in (the edges
// darkening, the colour draining a little), then as it hits a hard punch of light, the air shoved (a pale flash
// that blows out the picture's middle tones, gone in a third of a second) and a dusty haze settling after.
fn sc_press(c: vec3<f32>, uv: vec2<f32>) -> vec3<f32> {
    let h = sc_heard();
    let s = h.x;
    if (s < -SC_SUCK - 0.05 || s > 3.0 || intensity_v() <= 0.0) {
        return c;
    }
    let g = h.y;
    let res = frame.resolution.xy;
    let r = length((uv - 0.5) * vec2<f32>(res.x / res.y, 1.0));
    var o = c;
    // (the hush: drawn in)
    let suck = smoothstep(-SC_SUCK - 0.05, -0.02, s) * (1.0 - smoothstep(0.0, 0.03, s));
    let lum = dot(o, vec3<f32>(0.2126, 0.7152, 0.0722));
    o = mix(o, vec3<f32>(lum), 0.35 * suck * g) * (1.0 - 0.55 * suck * g * smoothstep(0.25, 0.85, r));
    // (the punch: the picture blown out pale, the middle first)
    let punch = g * smoothstep(0.0, 0.012, s) * exp(-max(s, 0.0) / 0.09);
    o = o + (vec3<f32>(0.95, 0.97, 1.05) - o * 0.3) * punch * (1.0 - 0.45 * smoothstep(0.1, 0.9, r));
    // (the dust it shoves along after: a warm grey haze settling over two seconds)
    let haze = g * smoothstep(0.03, 0.25, s) * exp(-max(s - 0.25, 0.0) / 1.2);
    o = mix(o, vec3<f32>(0.42, 0.4, 0.37) * (0.6 + 0.4 * lum), 0.22 * haze);
    return max(o, vec3<f32>(0.0));
}

@fragment
fn fs_main(in0: StageIn) -> @location(0) vec4<f32> {
    let o = supercell(sc_jolt(in0), 0u, vec4<f32>(0.0)).c;
    return vec4<f32>(sc_press(o.rgb, in0.uv), o.a);
}

// [half stage]
// QUALITY FAST (mod/src/lib.rs keeps this only then): the cloud, the rain and the funnels drawn at half the width and
// height by fs_half and laid over the full-size picture by fs_join (as payload.wgsl's); a game without the stages
// compiles these too and draws fs_main alone, at full size.
@group(0) @binding(6) var half_picture: texture_2d<f32>;
@group(0) @binding(7) var half_extra: texture_2d<f32>;

struct PlHalf {
    @location(0) c: vec4<f32>,
    @location(1) e: vec4<f32>,
}
@fragment
fn fs_half(in: StageIn) -> PlHalf {
    let o = supercell(in, 1u, vec4<f32>(0.0));
    return PlHalf(o.c, o.e);
}
// The half-size stage's at this pixel (whose ray goes `len` blocks): the four nearest, each weighed by how near it is
// and by how near the depth it was marched to is to this pixel's (a joint bilateral upsample, as payload.wgsl's pl_up).
fn sc_up(pos: vec2<f32>, len: f32) -> vec4<f32> {
    let hs = vec2<i32>(textureDimensions(half_picture));
    let h = floor(pos) * 0.5 - 0.25;
    let i0 = vec2<i32>(floor(h));
    let f = h - floor(h);
    let lp = min(len, 6.0e4);
    var acc = vec4<f32>(0.0);
    var sw = 0.0;
    var near_dz = 1.0e9;
    var near_c = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(k & 1, k >> 1u);
        let q = clamp(i0 + o, vec2<i32>(0), hs - vec2<i32>(1));
        let c = textureLoad(half_picture, q, 0);
        let e = textureLoad(half_extra, q, 0);
        let bw = select(1.0 - f.x, f.x, o.x == 1) * select(1.0 - f.y, f.y, o.y == 1);
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
    let in = sc_jolt(in0);
    let d = depth_at(in.uv);
    let len = select(1.0e9, length(world_offset(in.uv, d)), !is_sky(d));
    let o = supercell(in, 2u, sc_up(in.position.xy, len)).c;
    return vec4<f32>(sc_press(o.rgb, in0.uv), o.a);
}
// [end half stage]
