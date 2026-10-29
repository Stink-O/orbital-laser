// Orbital Laser's post pass for the Payload (laser 9). Like the Sinkhole's, the mod builds it from shaders/strike.wgsl
// up to its fs_main (the helpers: the noise, project_rel, ray_seg, mh, ign) less the other lasers' own functions,
// followed by this file, and sets it for a payload strike only. Validate with tools/check-shader.sh.

// ---- laser 9: the payload -----------------------------------------------------------------------------------------
// No beam. A few seconds of calm; then a small, fiercely bright point high in the sky drifts and sinks on a lazy,
// looping path, a thin pale ribbon of smoke curling behind it and hanging in the air; it turns and dives, faster and
// faster, a fireball now, its trail a dark column hung in the shape of its path; it strikes: a flash and a burst of
// fire, and a huge column of smoke boils up out of it, lumpy, dark at its core and sunlit on its tops, climbing and
// leaning with the wind for many seconds; the shockwave races out over the land as a low wall of tan dust, washes over
// the player and hangs as haze; dark chunks of earth fly and rain down far round it.
// strike/payload.rs samples the path and the column's billows into the table (pl_table, render.set-data): keep the
// PL_* in step.
const PL_SEEN: f32 = 3.0;          // the object shows,
const PL_TURN: f32 = 10.6;         // starts its fast final descent, a fireball by then,
const PL_HIT: f32 = 13.6;          // and strikes
const PL_LEN: f32 = 44.0;          // the strike's length (lasers.rs): everything fades out over its last PL_FADE
const PL_FADE: f32 = 7.0;
const PL_V: f32 = 343.0;           // the shockwave's front, blocks a second (with the blast's sound: payload.rs)
const PL_P: u32 = 16u;             // the table: the path's samples from PL_P, three words each,
const PL_PF: u32 = 400u;           // the billows from PL_PF, PL_PW words each (launch, rise, height share, radius, x, z)
const PL_PW: u32 = 8u;
const PL_HF: u32 = 1024u;          // the land's heightfield (payload.rs's pl_hf_words): its size, then heights, shelter
const PL_NPUFF: i32 = 18;
const PL_DEBRIS: i32 = 120;

fn pl_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
}
fn pl_u(i: u32) -> u32 {
    if (i >= arrayLength(&mod_data)) {
        return 0u;
    }
    return mod_data[i];
}
fn pl_n() -> i32 {
    return i32(pl_w(0u) + 0.5);
}
fn pl_sample(i: i32) -> vec3<f32> {
    let b = PL_P + 3u * u32(clamp(i, 0, pl_n() - 1));
    return vec3<f32>(pl_w(b), pl_w(b + 1u), pl_w(b + 2u));
}
// Where the object is at strike time t (from the target's ground): the samples, smoothly between (Catmull-Rom).
fn pl_head(t: f32) -> vec3<f32> {
    let u = (t - pl_w(1u)) / max(pl_w(2u), 1.0e-3);
    let i = i32(floor(u));
    let f = u - floor(u);
    let p0 = pl_sample(i - 1);
    let p1 = pl_sample(i);
    let p2 = pl_sample(i + 1);
    let p3 = pl_sample(i + 2);
    let f2 = f * f;
    let f3 = f2 * f;
    return 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f3);
}
fn pl_wind() -> vec3<f32> {
    return vec3<f32>(pl_w(3u), 0.0, pl_w(4u));
}
// Where a bit of the trail laid at time te has drifted to by time t: carried by the wind, rising a little, wandering.
fn pl_trail_at(i: i32, te: f32, t: f32, seed: u32) -> vec3<f32> {
    let age = max(t - te, 0.0);
    let fi = f32(i);
    let wob = vec3<f32>(sin(fi * 0.21 + f32(seed % 61u)), 0.4 * sin(fi * 0.13 + 2.0), cos(fi * 0.17 + f32(seed % 37u)));
    return pl_sample(i) + pl_wind() * age + vec3<f32>(0.0, 0.35 * age, 0.0) + wob * (0.35 * age);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ---- the column: billows rising out of the strike, each a ball grown and lifted over time -----------------------
struct PlCol {
    n: i32,
    lo: vec3<f32>,
    hi: vec3<f32>,
    grow: f32,
    a: f32,
    C: vec3<f32>,
    // (the billows where they are this frame: worked out once a pixel, not at every step)
    q: array<vec4<f32>, 18>,
}
// Billow i at `a` seconds after the strike: its middle and radius (w; 0 before it is launched).
fn pl_puff(i: i32, a: f32, C: vec3<f32>, grow: f32) -> vec4<f32> {
    let b = PL_PF + PL_PW * u32(i);
    let s = a - pl_w(b);
    if (s <= 0.0) {
        return vec4<f32>(C, 0.0);
    }
    let H = pl_w(5u) * (1.0 + 0.006 * a);
    let tau = pl_w(b + 1u);
    let rise = 1.0 - exp(-s / tau);
    // (swollen fast as it bursts out, then swelling slowly on)
    let r = pl_w(b + 3u) * (0.22 + 0.78 * (1.0 - exp(-s / (0.45 * tau)))) * grow;
    let h = 5.0 + pl_w(b + 2u) * H * rise;
    let spread = 0.35 + 0.65 * rise;
    let c = C + vec3<f32>(pl_w(b + 4u) * spread, h, pl_w(b + 5u) * spread) + pl_wind() * (a * (0.15 + 0.85 * h / H));
    return vec4<f32>(c, r);
}
fn pl_column(a: f32, C: vec3<f32>) -> PlCol {
    var o: PlCol;
    o.n = 0;
    o.lo = C;
    o.hi = C;
    o.a = a;
    o.C = C;
    o.grow = 1.0 + 0.012 * max(a - 6.0, 0.0);
    for (var i = 0; i < PL_NPUFF; i = i + 1) {
        let q = pl_puff(i, a, C, o.grow);
        o.q[i] = q;
        if (q.w <= 0.0) {
            continue;
        }
        o.lo = min(o.lo, q.xyz - vec3<f32>(q.w));
        o.hi = max(o.hi, q.xyz + vec3<f32>(q.w));
        o.n = o.n + 1;
    }
    // (room for the billows' lumps)
    o.lo = o.lo - vec3<f32>(24.0);
    o.hi = o.hi + vec3<f32>(24.0);
    return o;
}
fn pl_col_base(col: ptr<function, PlCol>, p: vec3<f32>) -> f32 {
    var d = 1.0e6;
    for (var i = 0; i < PL_NPUFF; i = i + 1) {
        let q = (*col).q[i];
        if (q.w > 0.0) {
            d = smin(d, length(p - q.xyz) - q.w, 11.0);
        }
    }
    return d;
}
// Cauliflower lumps: domes over a jittered lattice (the nearest of the eight cells round p, a feature point in each),
// rounded on top and meeting in creases: 1 on a dome's crown, 0 in a crease.
fn pl_dome(p: vec3<f32>) -> f32 {
    let b = floor(p - 0.5);
    var f1 = 9.0;
    for (var c = 0u; c < 8u; c = c + 1u) {
        let o = vec3<f32>(f32(c & 1u), f32((c >> 1u) & 1u), f32(c >> 2u));
        let cell = b + o;
        let q = bitcast<vec3<u32>>(vec3<i32>(cell));
        let h = pcg(q.x ^ pcg(q.y ^ pcg(q.z + 0x51u)));
        let jit = vec3<f32>(f32(h & 1023u), f32((h >> 10u) & 1023u), f32((h >> 20u) & 1023u)) * (0.5 / 1023.0) + 0.25;
        let e = cell + jit - p;
        f1 = min(f1, dot(e, e));
    }
    return sqrt(saturate(1.0 - f1 * 1.7));
}
// The column's surface at p: the billows' union bulged out in lumps on lumps (big domes, smaller domes on them), with
// how far up a dome it lies (0 deep in a crease, 1 on a crown) in .y.
fn pl_col_sdf(col: ptr<function, PlCol>, p: vec3<f32>, d0: f32, fine: bool) -> vec2<f32> {
    let a = (*col).a;
    let q = (p - (*col).C) * vec3<f32>(1.0, 1.0 / (*col).grow, 1.0) - vec3<f32>(0.0, 2.2 * a + 10.0 * min(a, 1.5), 0.0) - pl_wind() * (a * 0.4);
    let b1 = pl_dome(q * (1.0 / 34.0) + vec3<f32>(3.1, 0.0, 7.7));
    // (the small lumps only where it is looked at, not where the light is looked for)
    var b2 = 0.6;
    if (fine) {
        b2 = pl_dome(q * (1.0 / 12.0) + vec3<f32>(0.0, -0.3 * a, 1.3));
    }
    // (the stem's lumps smaller: it is thinner)
    let lump = 0.55 + 0.45 * smoothstep(20.0, 110.0, p.y - (*col).C.y);
    let w = gnoise3(q * (1.0 / 60.0));
    var d = d0 - (28.0 * (b1 - 0.45) + 4.5 * (b2 - 0.45) + 16.0 * (w - 0.5)) * lump;
    if (fine && d < 3.0) {
        let b3 = gnoise3(q * (1.0 / 4.0) + vec3<f32>(5.0, 1.0, -0.8 * a));
        d = d - 1.5 * (b3 - 0.5);
    }
    return vec2<f32>(d, b1 * (0.4 + 0.6 * b2));
}
// A ray against a box, camera-relative: the entry and exit distances.
fn pl_box(rd: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>) -> vec2<f32> {
    let inv = 1.0 / select(rd, vec3<f32>(1.0e-6), abs(rd) < vec3<f32>(1.0e-6));
    let ta = lo * inv;
    let tb = hi * inv;
    let tmin = min(ta, tb);
    let tmax = max(ta, tb);
    return vec2<f32>(max(max(tmin.x, tmin.y), max(tmin.z, 0.0)), min(min(tmax.x, tmax.y), tmax.z));
}

// ---- the dust of the shockwave: a low wall racing out over the land, rising and hanging behind it ---------------
// The ground at r out where the heightfield does not reach (or before it is in): the target's, rising or falling to
// the player's as it goes out to them.
fn pl_gref(r: f32, me: vec3<f32>, C: vec3<f32>, dme: f32) -> f32 {
    return mix(0.0, me.y - C.y, smoothstep(0.0, max(dme, 1.0), r));
}
// The land at q (level, from the target): its ground (from the target's) and how sheltered it is from the blast by the
// land between (0 to 1), from the heightfield, smoothly between its cells; `gref` past its edge.
fn pl_land(q: vec2<f32>, gref: f32) -> vec2<f32> {
    let nf = pl_w(PL_HF);
    if (nf < 2.0) {
        return vec2<f32>(gref, 0.0);
    }
    let n = u32(nf + 0.5);
    if (arrayLength(&mod_data) < PL_HF + 8u + n * n) {
        return vec2<f32>(gref, 0.0);
    }
    let R = pl_w(PL_HF + 1u);
    let step = 2.0 * R / (nf - 1.0);
    let fc = clamp((q + R) / step, vec2<f32>(0.0), vec2<f32>(nf - 1.001));
    let i0 = vec2<u32>(floor(fc));
    let t = fc - floor(fc);
    var hv = vec4<f32>(0.0);
    var sv = vec4<f32>(0.0);
    for (var j = 0u; j < 4u; j = j + 1u) {
        let c = mod_data[PL_HF + 8u + (i0.y + (j >> 1u)) * n + i0.x + (j & 1u)];
        hv[j] = f32(c & 0xffffu) / 8.0 - 512.0;
        sv[j] = f32((c >> 16u) & 0xffu) / 255.0;
    }
    let g = mix(mix(hv.x, hv.y, t.x), mix(hv.z, hv.w, t.x), t.y);
    let sh = mix(mix(sv.x, sv.y, t.x), mix(sv.z, sv.w, t.x), t.y);
    let e = smoothstep(-step, 3.0 * step, max(abs(q.x), abs(q.y)) - R);
    return vec2<f32>(mix(g, gref, e), sh * (1.0 - e));
}
// The dust at p (camera-relative), `side`: how square the ray crosses the ring there (0 along it): a dense, opaque wall
// a few blocks high just behind a crisp, billowing front, thinning behind it into haze that rises and hangs. All of it
// over the land's own ground (the heightfield, and close to where this pixel's ray meets the land, that point's own
// height: `loc`, its xz from the target, how far it stands off the heightfield there, and the reach of that squared),
// climbing the rises, filling the hollows, thinner and later in the lee of a ridge. Its density, and its height over
// the ground.
fn pl_dust(p: vec3<f32>, C: vec3<f32>, a: f32, me: vec3<f32>, dme: f32, side: f32, loc: vec4<f32>) -> vec2<f32> {
    let q = p - C;
    let r = length(q.xz);
    let w = p + frame.camera_position.xyz;
    let land = pl_land(q.xz, pl_gref(r, me, C, dme));
    let dl = q.xz - loc.xy;
    let h = q.y - land.x - loc.z * exp(-dot(dl, dl) / loc.w);
    let sh = land.y;
    if (h > 70.0 || h < -4.0) {
        return vec2<f32>(0.0, h);
    }
    // (the front billows: pushed on and held back by the turbulence it churns, more so higher up)
    let rf = PL_V * a;
    let n1 = gnoise3(w * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a, 0.0));
    let n2 = gnoise3(w * (1.0 / 3.5) + vec3<f32>(5.0, -2.0 * a, 1.0));
    // (held back in the lee of a ridge, more so the deeper it lies under it)
    let s = rf - r + (n1 - 0.5) * 14.0 + (n2 - 0.5) * 5.0 - 0.25 * max(h, 0.0) - 22.0 * sh;
    if (s < -3.0) {
        return vec2<f32>(0.0, h);
    }
    let since = max(s, 0.0) / PL_V;
    // (the wall: a person's height and more, higher as it goes and behind its front; its top ragged)
    let n3 = gnoise3(w * (1.0 / 38.0) + vec3<f32>(0.0, -0.3 * a, 9.0));
    // (tallest a little behind the front, settling lower behind it)
    let rise = 1.0 + 1.2 * smoothstep(0.0, 25.0, s) - 0.9 * smoothstep(30.0, 140.0, s);
    let hw = (5.0 + 0.012 * r) * rise * (0.35 + 1.2 * n1) * (0.6 + 0.8 * n3) + 1.5 * min(since, 6.0);
    let up = smoothstep(hw, hw * 0.35, h) * smoothstep(-4.0, 0.0, h);
    let lead = smoothstep(-3.0, 1.5, s);
    let wall = 1.6 * exp(-s / (9.0 + 0.015 * r)) * (0.75 + 0.25 * side) * (1.0 - 0.6 * sh);
    let haze = (0.009 * exp(-since / 2.5) + 0.0025 * exp(-since / 6.0)) * (0.5 + n2);
    // (none round the column's foot: the blast cleared it, and it would tint the smoke)
    let mid = smoothstep(45.0, 160.0, r);
    // (and what it leaves low over the land for a few seconds, in drifting patches)
    let low = 0.22 * (1.0 - 0.45 * sh) * exp(-since / 3.0) * smoothstep(0.0, 30.0, s) * exp(-max(h, 0.0) / (2.5 + 2.0 * n1)) * smoothstep(0.35, 0.7, n3);
    return vec2<f32>(((wall * saturate(1.5 * n1 + 0.25 * n2) * (0.35 + 1.3 * n3) + haze * (1.0 - 0.4 * sh)) * up + low) * lead * mid, h);
}
// ---- the debris: chunks and specks of earth thrown out, falling back far round it ---------------------------------
struct PlChunk {
    p: vec3<f32>,
    v: vec3<f32>,
    s: f32,
    live: f32,
}
fn pl_chunk(i: i32, a: f32, seed: u32, C: vec3<f32>, me: vec3<f32>, dme: f32) -> PlChunk {
    var o: PlChunk;
    let fi = u32(i);
    let ang = mh(fi, seed, 0x301u) * TAU;
    let big = mh(fi, seed, 0x303u);
    // (torn up all over the blast's middle, each as the blast reaches it, not all from one point: most thrown
    // a few hundred blocks, a third far, some of those coming down round the player)
    let r0 = 6.0 + 40.0 * sqrt(mh(fi, seed, 0x306u));
    let far = mh(fi, seed, 0x307u) < 0.35;
    let el = select(0.35 + 0.85 * mh(fi, seed, 0x302u), 0.45 + 0.4 * mh(fi, seed, 0x302u), far);
    let sp = select(mix(30.0, 80.0, pow(mh(fi, seed, 0x304u), 0.7)), mix(90.0, 135.0, mh(fi, seed, 0x304u)), far) * (1.0 - 0.25 * big);
    let t0 = r0 / PL_V + 0.12 * mh(fi, seed, 0x305u);
    let tau = a - t0;
    o.s = mix(0.12, 1.1, big * big * big);
    o.live = 0.0;
    if (tau <= 0.0) {
        return o;
    }
    let dir = vec3<f32>(cos(ang), 0.0, sin(ang));
    let v0 = vec3<f32>(dir.x * cos(el), sin(el), dir.z * cos(el)) * sp;
    // (a little drag: they slow, and fall less than straight)
    let k = 0.06;
    let e = (1.0 - exp(-k * tau)) / k;
    let g = 9.8;
    o.p = C + dir * r0 + vec3<f32>(0.0, 2.0, 0.0) + vec3<f32>(v0.x, 0.0, v0.z) * e + vec3<f32>(0.0, v0.y * e - g * (tau - e) / k, 0.0);
    o.v = vec3<f32>(v0.x, 0.0, v0.z) * exp(-k * tau) + vec3<f32>(0.0, (v0.y + g / k) * exp(-k * tau) - g / k, 0.0);
    let r = length((o.p - C).xz);
    // (the land under it looked up only when it is down near the highest of it: it is checked for every chunk, every pixel)
    var gref = C.y + pl_gref(r, me, C, dme);
    if (o.p.y < max(gref, C.y + pl_w(PL_HF + 3u)) + 3.0) {
        gref = C.y + pl_land((o.p - C).xz, gref - C.y).x;
    }
    o.live = smoothstep(gref - 1.0, gref + 2.0, o.p.y);
    return o;
}

fn payload(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let time = now();
    let cam = frame.camera_position.xyz;
    let k = intensity_v();
    let seed = u32(seed_v());
    let px_a = frame.view_params.w / frame.resolution.y;      // (the angle a pixel spans)
    let anc = anchor_xz();
    let gy = block_y() + 1.0;
    let C = vec3<f32>(anc.x, gy, anc.y) - cam;              // the strike's point, on the target's ground
    let me = vec3<f32>(frame.mod_params[3].x, frame.mod_params[3].y, frame.mod_params[3].z) - cam;
    let dme = length((me - C).xz);
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let L = normalize(select(vec3<f32>(0.3, 1.0, 0.2), sun, sun.y > 0.05));

    let d = depth_at(uv);
    let sky = is_sky(d);
    let rel = world_offset(uv, select(d, 0.5, sky));
    let scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv, 0.5));
    let scene = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
    var col = scene;
    // (leaves and grass whipped as the blast's front goes through them: what is green near it shaken on the screen)
    if (!sky && time > PL_HIT && time < PL_HIT + 6.0) {
        let rfr = PL_V * (time - PL_HIT);
        let rs = length((rel - (vec3<f32>(anchor_xz().x, block_y() + 1.0, anchor_xz().y) - cam)).xz);
        let e = rfr - rs;
        let gust = exp(-pow(e / 14.0, 2.0)) + 0.4 * exp(-max(e, 0.0) / 50.0) * step(0.0, e);
        let green = scene.g > scene.r * 1.1 && scene.g > scene.b * 1.05;
        if (gust > 0.03 && green) {
            let fpx0 = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
            let amp = min(0.45 * fpx0 / max(scene_len, 1.0), 7.0) * gust;
            let ph = dot(floor(in.position.xy / 6.0), vec2<f32>(0.37, 0.71));
            let off = vec2<f32>(sin(time * 29.0 + ph * 5.0), cos(time * 23.0 + ph * 3.0)) * amp;
            let s2 = srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, uv + off * frame.resolution.zw, 0.0).rgb);
            if (s2.g > s2.r * 1.1 && s2.g > s2.b * 1.05) {
                col = s2;
            }
        }
    }
    let fade = 1.0 - smoothstep(PL_LEN - PL_FADE, PL_LEN, time);
    let a = time - PL_HIT;                                    // seconds since it struck
    let have = pl_n() > 1;

    // (the light, matched to the scene's: its sky from the top of the picture where it is sky, and the sun's)
    var skyl = srgb_to_linear(frame.sky_color.rgb);
    var nsk = 1.0;
    for (var s = 0; s < 3; s = s + 1) {
        let su = vec2<f32>(0.2 + 0.3 * f32(s), 0.04);
        if (is_sky(depth_at(su))) {
            skyl = skyl + srgb_to_linear(textureSampleLevel(scene_color, linear_sampler, su, 0.0).rgb);
            nsk = nsk + 1.0;
        }
    }
    skyl = skyl / nsk;
    let amb = mix(vec3<f32>(0.03, 0.035, 0.05), skyl * 0.85 + vec3<f32>(0.04), day);
    let sunc = vec3<f32>(1.35, 1.24, 1.06) * day;
    let haze_c = mix(vec3<f32>(0.02, 0.025, 0.04), skyl * 1.05, day);

    // ---- the flash of the strike lighting the land and the sky round it ---------------------------------------------
    var flash = 0.0;
    if (a > 0.0 && a < 3.0) {
        flash = exp(-a / 0.16) + 0.25 * exp(-a / 0.9);
        let Pf = C + vec3<f32>(0.0, 10.0, 0.0);
        let df = length(Pf);
        let cth = dot(rd, Pf / df);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        let fire_c = vec3<f32>(3.2, 1.55, 0.5);
        // (the glow in the air round it, seen through anything: it lights the haze)
        col = col + fire_c * flash * (0.12 / (1.0 + pow(th / 0.035, 2.0)) + 0.025 * exp(-th / 0.4)) * k;
        // (and the land near it lit orange)
        if (!sky) {
            let dl = length(rel - Pf);
            col = col + scene * fire_c * flash * 2.0 / (1.0 + pow(dl / 45.0, 2.0)) * k;
        }
    }

    // ---- the trail: a thin pale ribbon over the drift, dense dark smoke along the dive, hung in the sky -------------
    if (have && time > PL_SEEN) {
        let n = pl_n();
        let t0 = pl_w(1u);
        let dt = pl_w(2u);
        let thead = min(time, PL_HIT);
        let last = min(i32(floor((thead - t0) / dt)), n - 1);
        var tau = 0.0;
        var tc = vec3<f32>(0.0);
        var tw = 0.0;
        var glow = vec3<f32>(0.0);
        var pa = pl_trail_at(0, t0, time, seed) + C;
        for (var i = 0; i <= last; i = i + 1) {
            let te_b = t0 + dt * f32(i + 1);
            var pb: vec3<f32>;
            if (i == last) {
                pb = pl_head(thead) + C;
            } else {
                pb = pl_trail_at(i + 1, te_b, time, seed) + C;
            }
            let h = ray_seg(rd, pa, pb);
            let te = min(t0 + dt * (f32(i) + h.z), thead);
            let age = max(time - te, 0.0);
            // (pale vapour high up, where it is still coming in; dense dark smoke where it came down burning)
            let dive = smoothstep(PL_TURN - 1.6, PL_TURN + 0.6, te);
            let rad = mix(4.0 + 3.5 * sqrt(age), 6.0 + 4.5 * sqrt(age), dive);
            if (h.x < rad && h.y < scene_len + rad) {
                let chord = 2.0 * sqrt(max(rad * rad - h.x * h.x, 0.0));
                let cp = rd * h.y;
                let nq = gnoise3((cp + cam) / (2.5 * rad + 2.0) + vec3<f32>(f32(seed % 97u), 0.0, 0.0));
                let nq2 = gnoise3((cp + cam) / (0.9 * rad + 1.0) + vec3<f32>(0.0, 3.0, f32(seed % 89u)));
                let shape = mix(saturate(1.7 * nq - 0.3), 0.6 + 0.4 * nq, dive) * (0.55 + 0.9 * nq2 * (1.0 - dive * 0.5)) * saturate(1.0 - pow(h.x / rad, 2.0) * 0.85);
                // (both hang in the sky in the shape of the arc for many seconds, drifting and thinning)
                let pale = 0.3 * exp(-age / 20.0) / (1.0 + 0.1 * age);
                let dark = 0.55 * exp(-max(age - 3.0, 0.0) / 9.0) / (1.0 + 0.04 * max(age - 3.0, 0.0));
                let sig = mix(pale, dark, dive) * shape * fade;
                let occl = saturate((scene_len - h.y) / rad + 0.5);
                let dtau = sig * chord * occl;
                // (lit on its sunward side)
                let axis = pa + (pb - pa) * h.z;
                let nrm = normalize(cp - axis + vec3<f32>(0.0, 1.0e-4, 0.0));
                let lit = 0.45 + 0.55 * saturate(dot(nrm, L) * 0.5 + 0.5);
                let alb = mix(vec3<f32>(0.46, 0.47, 0.5), vec3<f32>(0.075, 0.072, 0.07), dive);
                let c = alb * (sunc * lit * 0.85 + amb * 0.9);
                tc = tc + c * dtau;
                tw = tw + dtau;
                tau = tau + dtau;
                // (the flame tail just behind the head, in the dive)
                let fl = dive * exp(-age / 0.13) * step(time, PL_HIT + 0.05);
                glow = max(glow, mix(vec3<f32>(3.2, 1.0, 0.18), vec3<f32>(4.0, 2.6, 1.0), exp(-age / 0.06)) * fl * min(chord * 0.35, 1.6) * occl);
                // (high up, the hot streak of air it leaves glowing behind it, white, cooling within a second)
                let fh = (1.0 - dive) * exp(-age / 0.45) * step(time, PL_HIT);
                glow = max(glow, vec3<f32>(2.4, 2.3, 2.1) * fh * min(chord * 0.6, 1.2) * occl);
            }
            pa = pb;
        }
        if (tw > 0.0) {
            let al = 1.0 - exp(-tau);
            col = mix(col, tc / tw, al * k);
        }
        col = col + glow * k;
    }

    // (how far off the column stands along this ray, where it is mostly opaque: the dust and debris behind it hidden)
    var col_t = 1.0e9;
    // ---- the column: raymarched, self-shadowed towards the sun, dark at its core, fire in it as it bursts ----------
    if (have && a > 0.0) {
        var cl = pl_column(a, C);
        if (cl.n > 0) {
            let tb = pl_box(rd, cl.lo, cl.hi);
            let t1 = min(tb.y, scene_len);
            if (t1 > tb.x) {
                var t = tb.x;
                var tr = 1.0;
                var acc = vec3<f32>(0.0);
                let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
                let H = pl_w(5u);
                let ph = 0.8 + 0.5 * pow(saturate(dot(rd, L)), 5.0);
                var tmid = 0.0;
                var wmid = 0.0;
                for (var i = 0; i < 56; i = i + 1) {
                    if (t > t1 || tr < 0.03) {
                        break;
                    }
                    let p = rd * t;
                    let d0 = pl_col_base(&cl, p);
                    if (d0 > 34.0) {
                        // (empty air: leap on, short of where a lump could reach)
                        t = t + d0 - 30.0;
                        continue;
                    }
                    let st = max(3.5, t * 0.008) * (0.75 + 0.5 * j);
                    let sd = pl_col_sdf(&cl, p, d0, true);
                    let den = saturate(-sd.x / 1.2);
                    if (den > 0.002) {
                        // (the sun: the billow's own face (a look a few blocks towards it), and the column's bulk
                        // between it and the sun (two looks further on))
                        let face = pl_col_sdf(&cl, p + L * 4.0, pl_col_base(&cl, p + L * 4.0), false).x;
                        let lam = saturate(0.35 + (face - sd.x) / 6.0);
                        let s1 = saturate((4.0 - pl_col_base(&cl, p + L * 14.0)) / 14.0);
                        let s2 = saturate(-pl_col_base(&cl, p + L * 40.0) / 14.0);
                        let tsun = exp(-(s1 * 12.0 + s2 * 28.0) * 0.25) * lam;
                        let hy = saturate((p.y - C.y) / max(H, 1.0));
                        // (dark slate, blue-grey from the sky on its shadowed side, darker down its stem and in its
                        // creases; its tops a little paler where the sun catches them)
                        let ao = 0.35 + 0.65 * sd.y;
                        let alb = vec3<f32>(0.3, 0.31, 0.34);
                        var c = alb * (skyl * (0.7 * ao * (0.5 + 0.5 * hy)) + sunc * vec3<f32>(0.27, 0.29, 0.31) * (tsun * ph) + vec3<f32>(0.01) * day);
                        // (fire in it as it bursts: low down, dying fast)
                        let core = exp(min(d0, 0.0) / 26.0);
                        let fire = exp(-a / 0.25) * exp(-max(p.y - C.y, 0.0) / (16.0 + 40.0 * a)) * core;
                        c = c * (1.0 - saturate(fire * 2.0)) + vec3<f32>(3.6, 1.25, 0.18) * (0.6 + 0.6 * sd.y) * saturate(fire * 1.6);
                        let ext = den * 0.4 * st;
                        let al = 1.0 - exp(-ext);
                        acc = acc + tr * al * c;
                        tmid = tmid + tr * al * t;
                        wmid = wmid + tr * al;
                        tr = tr * (1.0 - al);
                    }
                    t = t + st;
                }
                if (tr < 0.999) {
                    // (the air between: farther, paler)
                    let dist = tmid / max(wmid, 1.0e-4);
                    if (tr < 0.5) {
                        col_t = dist;
                    }
                    let ap = 1.0 - exp(-dist / 2600.0);
                    let ccol = mix(acc / max(1.0 - tr, 1.0e-4), haze_c, ap * 0.8);
                    col = mix(col, ccol, (1.0 - tr) * k * fade);
                }
            }
        }
    }

    // ---- the object: a white-hot point, bloom round it; a fireball in the dive ------------------------------------
    if (have && time > PL_SEEN - 0.2 && time < PL_HIT + 0.04) {
        let Hp = pl_head(time) + C;
        let dh = length(Hp);
        let hn = Hp / dh;
        let cth = dot(rd, hn);
        let th = sqrt(max(2.0 * (1.0 - cth), 0.0));
        // (hidden behind anything nearer: the picture's depth where it is)
        let hp = project_rel(Hp);
        var vis = 1.0;
        if (hp.z > 0.0 && all(hp.xy > vec2<f32>(0.0)) && all(hp.xy < vec2<f32>(1.0))) {
            let dd = depth_at(hp.xy);
            if (!is_sky(dd) && length(world_offset(hp.xy, dd)) < dh - 3.0) {
                vis = 0.0;
            }
        } else if (cth < 0.0) {
            vis = 0.0;
        }
        // (white-hot high up, heating into a fireball as it comes down into the thick air)
        let dive = smoothstep(PL_TURN - 1.5, PL_TURN + 0.8, time);
        let show = smoothstep(PL_SEEN - 0.2, PL_SEEN + 1.2, time);
        let flick = 0.85 + 0.15 * sin(time * 37.0) * sin(time * 23.0 + 1.0);
        let size = mix(1.6, 8.0, dive);
        let thc = max(size / dh, px_a * 0.9);
        let hot = mix(vec3<f32>(1.0, 0.96, 0.9), vec3<f32>(1.0, 0.62, 0.2), dive);
        let core = exp(-pow(th / thc, 2.0)) * mix(14.0, 9.0, dive);
        // (a soft bloom round the white-hot point; in the dive a flame, its glare much less)
        let bloom = (0.9 / (1.0 + pow(th / (thc * 4.0 + 0.004), 2.0)) + 0.18 * exp(-th / 0.05)) * mix(1.0, 0.3, dive);
        // (a faint horizontal streak, the lens's)
        let sv = rd - hn * cth;
        let up = normalize(cross(cross(hn, vec3<f32>(0.0, 1.0, 0.0)), hn) + vec3<f32>(0.0, 1.0e-5, 0.0));
        let streak = exp(-abs(dot(sv, up)) / (px_a * 1.5)) * exp(-th / 0.12) * 0.25 * (1.0 - dive);
        col = col + hot * (core + bloom + streak) * show * vis * flick * k;
    }

    // ---- the dust: marched along the view ray where it crosses the shell behind the front, more sparsely inside ------
    if (a > 0.0 && a < 32.0) {
        let rf = PL_V * a;
        // (the slab the dust stays in: over the land's lowest and highest ground, where the heightfield is in)
        var ylo = min(C.y, me.y) - 6.0;
        var yhi = max(C.y, me.y) + 45.0;
        if (pl_w(PL_HF) > 1.0) {
            ylo = min(ylo, C.y + pl_w(PL_HF + 2u) - 6.0);
            yhi = max(yhi, C.y + pl_w(PL_HF + 3u) + 45.0);
        }
        // (where this pixel's ray meets the land, its own height: the dust right there sits on it, in a hollow
        // smaller than the heightfield's cells or on a rise; a treetop or a wall counts only a little)
        var loc = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        if (!sky) {
            let sq = rel - C;
            let off = sq.y - pl_land(sq.xz, pl_gref(length(sq.xz), me, C, dme)).x;
            let stp = 2.0 * max(pl_w(PL_HF + 1u), 260.0) / 95.0;
            loc = vec4<f32>(sq.xz, clamp(off, -30.0, 2.5 + 0.1 * max(off - 2.5, 0.0)), stp * stp * 0.6);
        }
        var t0 = 0.0;
        var t1 = min(min(scene_len, col_t), 1600.0);
        if (abs(rd.y) > 1.0e-5) {
            let ya = ylo / rd.y;
            let yb = yhi / rd.y;
            t0 = max(t0, min(ya, yb));
            t1 = min(t1, max(ya, yb));
        } else if (ylo > 0.0 || yhi < 0.0) {
            t1 = -1.0;
        }
        // (the ray across the discs out to the front and out to where the wall thins: the shell between)
        let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
        let bb = -dot(rd.xz, C.xz);
        let cc = dot(C.xz, C.xz);
        let Ro = rf + 12.0;
        let Ri = max(rf - 60.0, 0.0);
        let dout = bb * bb - a2 * (cc - Ro * Ro);
        let din = bb * bb - a2 * (cc - Ri * Ri);
        if (t1 > t0 && dout > 0.0) {
            let oa = (-bb - sqrt(dout)) / a2;
            let ob = (-bb + sqrt(dout)) / a2;
            var seg = array<vec2<f32>, 3>(vec2<f32>(oa, ob), vec2<f32>(0.0, -1.0), vec2<f32>(0.0, -1.0));
            var ns = array<i32, 3>(20, 0, 0);
            if (din > 0.0 && Ri > 0.0) {
                let ia = (-bb - sqrt(din)) / a2;
                let ib = (-bb + sqrt(din)) / a2;
                seg[0] = vec2<f32>(oa, ia);
                seg[1] = vec2<f32>(ib, ob);
                seg[2] = vec2<f32>(ia, ib);
                ns = array<i32, 3>(14, 12, 10);
            }
            // (how square the ray crosses the ring: along it, at the ring's sides from far off, it would pile up)
            let mid_t = clamp(-bb / a2, t0, t1);
            let pm = rd * mid_t - C;
            let side = saturate(abs(dot(normalize(rd.xz), pm.xz / max(length(pm.xz), 1.0))) * 1.6);
            var tr = 1.0;
            var acc = vec3<f32>(0.0);
            let j = ign(in.position.xy + vec2<f32>(0.0, fract(time * 5.0) * 53.0));
            // (the near crossing, the haze inside, then the far crossing: in the order the ray meets them)
            var order = array<i32, 3>(0, 2, 1);
            for (var si = 0; si < 3; si = si + 1) {
                let k2 = order[si];
                let sa = max(seg[k2].x, t0);
                let sb = min(seg[k2].y, t1);
                let n = ns[k2];
                if (n == 0 || sb <= sa || tr < 0.02) {
                    continue;
                }
                // (closer together near the eye)
                for (var i = 0; i < n; i = i + 1) {
                    let u0 = (f32(i) + j) / f32(n);
                    let u1 = (f32(i) + j + 1.0) / f32(n);
                    let t = sa + (sb - sa) * u0 * u0;
                    let dt = (sb - sa) * (u1 * u1 - u0 * u0);
                    let p = rd * t;
                    let dh = pl_dust(p, C, a, me, dme, side, loc);
                    let den = dh.x;
                    if (den <= 0.001) {
                        continue;
                    }
                    let al = 1.0 - exp(-den * dt * 0.3);
                    let h = dh.y;
                    // (its billows lit on top, darker under them and low down)
                    let wq = p + cam;
                    let bl = gnoise3(wq * vec3<f32>(1.0 / 9.0, 1.0 / 6.0, 1.0 / 9.0) + vec3<f32>(0.0, -1.2 * a + 0.5, 0.0));
                    let lo = (0.45 + 0.55 * saturate(h / 8.0)) * (0.55 + 0.7 * bl);
                    let dc = vec3<f32>(0.62, 0.55, 0.34) * (sunc * 0.75 * lo + amb * 0.6);
                    acc = acc + tr * al * dc;
                    tr = tr * (1.0 - al);
                    if (tr < 0.02) {
                        break;
                    }
                }
            }
            col = mix(col, col * tr + acc, k * fade);
        }
    }

    // ---- the debris: dark chunks and specks of earth, tumbling as they fly and fall, the big ones trailing smoke ----
    if (a > 0.0 && a < 16.0) {
        let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
        let pxy = in.position.xy;
        let lim = min(scene_len, col_t);
        var cov = 0.0;
        var smk = 0.0;
        for (var i = 0; i < PL_DEBRIS; i = i + 1) {
            let ch = pl_chunk(i, a, seed, C, me, dme);
            if (ch.live <= 0.0) {
                continue;
            }
            let dist = length(ch.p);
            if (dist > lim || dist < 1.0) {
                continue;
            }
            let s0 = project_rel(ch.p);
            if (s0.z < 0.0) {
                continue;
            }
            let q0 = s0.xy * frame.resolution.xy;
            let rad = max(ch.s * fpx / dist, 0.55);
            let bigc = smoothstep(0.45, 0.8, ch.s);
            // (the smoke a big one trails: a fading wisp along where it flew the last half second)
            let reach = select(rad * 1.4 + length(ch.v) * 0.03 * fpx / dist + 2.0, rad * 3.0 + length(ch.v) * 0.6 * fpx / dist + 4.0, bigc > 0.0);
            if (length(pxy - q0) > reach) {
                continue;
            }
            let s1 = project_rel(ch.p - ch.v * 0.03);
            let q1 = s1.xy * frame.resolution.xy;
            // (a tumbling lump: a capsule along its blur, its outline turning)
            let ab = q1 - q0;
            let w = saturate(dot(pxy - q0, ab) / max(dot(ab, ab), 1.0e-4));
            let e = length(pxy - (q0 + ab * w));
            let spin = a * (3.0 + 6.0 * mh(u32(i), seed, 0x308u));
            let th = atan2(pxy.y - q0.y, pxy.x - q0.x);
            let lump = 1.0 + 0.28 * sin(th * 3.0 + f32(i) + spin) + 0.12 * sin(th * 5.0 - spin * 1.3);
            let c = saturate(rad * lump + 0.5 - e) * ch.live * saturate(rad / max(length(ab) * 0.5, rad));
            cov = max(cov, c);
            if (bigc > 0.0) {
                let s2 = project_rel(ch.p - ch.v * 0.6 + vec3<f32>(0.0, 1.2, 0.0));
                let q2 = s2.xy * frame.resolution.xy;
                let tb = q2 - q0;
                let u = saturate(dot(pxy - q0, tb) / max(dot(tb, tb), 1.0e-4));
                let wd = rad * (0.6 + 1.6 * u) + 0.5;
                let et = length(pxy - (q0 + tb * u));
                smk = max(smk, saturate(1.0 - et / wd) * (1.0 - u) * 0.45 * bigc * ch.live * step(0.5, s2.z));
            }
        }
        let dirt = vec3<f32>(0.035, 0.03, 0.026) * (amb * 1.5 + sunc * 0.3);
        let smoke = vec3<f32>(0.28, 0.29, 0.31) * (amb * 0.8 + sunc * 0.25);
        col = mix(col, smoke, smk * k * fade);
        col = mix(col, dirt, cov * k * fade);
    }

    // ---- the dust at the eye: as the front washes over the camera, grit thrown at the lens and streaking past, the
    // picture flattened and warmed by the dust in the air, clearing as it settles ------------------------------------
    if (a > 0.0 && a < 20.0) {
        let rc = length(C.xz);
        let tau = a - rc / PL_V;                               // since the front reached the eye
        if (tau > -0.1 && rc > 50.0) {
            let land = pl_land(-C.xz, pl_gref(rc, me, C, dme));
            let hc = -C.y - land.x;                            // the eye over the ground
            let E = smoothstep(-0.08, 0.05, tau) * (0.6 * exp(-tau / 0.8) + 0.4 * exp(-tau / 3.5))
                * smoothstep(40.0, 8.0, hc) * smoothstep(2600.0, 900.0, rc) * smoothstep(50.0, 110.0, rc)
                * (1.0 - 0.55 * land.y) * fade * k;
            if (E > 0.002) {
                let dust_c = vec3<f32>(0.6, 0.5, 0.35) * (sunc * 0.6 + amb * 0.75);
                // (the air thick with it: contrast lost, warmed)
                let lum = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
                col = mix(col, mix(vec3<f32>(lum), dust_c, 0.55), 0.25 * E);
                col = col * mix(vec3<f32>(1.0), vec3<f32>(1.06, 0.98, 0.84), E);
                // (a film of it on the lens, in soft blotches, fixed to the screen)
                let pxy = in.position.xy;
                let sres = frame.resolution.y / 1080.0;
                let film = gnoise3(vec3<f32>(pxy / (140.0 * sres), 3.1)) * 0.65 + gnoise3(vec3<f32>(pxy / (37.0 * sres), 7.7)) * 0.35;
                col = mix(col, dust_c * 1.15, 0.2 * E * smoothstep(0.42, 0.8, film));
                // (specks streaking past: grains blown from the blast's side past the eye, out from where they come
                // from on the screen, or in towards where they go when that is behind)
                let tow = normalize(vec3<f32>(C.x, 0.0, C.z) + vec3<f32>(1.0e-3, 0.0, 0.0));
                let pin = project_rel(tow * 1000.0);
                let pout = project_rel(-tow * 1000.0);
                let fwd_in = pin.z > 0.0;
                let F = select(pout.xy, pin.xy, fwd_in) * frame.resolution.xy;
                let dv = pxy - F;
                let dl = max(length(dv), 1.0);
                let th = atan2(dv.y, dv.x);
                let lr = log(dl);
                var sp = 0.0;
                for (var l = 0; l < 2; l = l + 1) {
                    let fl = f32(l);
                    let nth = 260.0 - 90.0 * fl;
                    let cs = 0.16 + 0.1 * fl;
                    // (on the move: outward from where they come from, inward to where they go)
                    let flow = (1.6 + 0.9 * fl) * a * select(-1.0, 1.0, fwd_in);
                    let uth = (th / TAU + 0.5) * nth;
                    let ur = (lr - flow) / cs;
                    let ci = floor(uth);
                    let cr = floor(ur);
                    let hsh = mh(u32(i32(ci) + 4096), u32(i32(cr) + 4096), 0x3c1u + u32(l));
                    if (hsh < 0.018 - 0.006 * fl) {
                        let ct = (ci + 0.2 + 0.6 * mh(u32(i32(ci) + 4096), u32(i32(cr) + 4096), 0x3c5u)) / nth;
                        let cl = (cr + 0.5) * cs;
                        let across = abs((th / TAU + 0.5) - ct) * TAU * dl;
                        let along = abs((lr - flow) - cl) * dl;
                        let wid = (0.8 + 1.4 * fl) * sres;
                        let lng = (4.0 + 10.0 * hsh / 0.018) * sres * (1.0 + 2.0 * exp(-tau / 0.6));
                        sp = max(sp, smoothstep(wid + 0.8, 0.0, across) * smoothstep(lng, lng * 0.3, along) * (0.6 + 0.4 * fl));
                    }
                }
                sp = sp * smoothstep(30.0 * sres, 160.0 * sres, dl);
                let grain = dust_c * mix(1.1, 0.55, smoothstep(0.2, 0.6, lum));
                // (the grains thrown past in the front's first second or so, a few stragglers after)
                col = mix(col, grain, sp * 0.55 * min(E * 1.6, 1.0) * (0.25 + 0.75 * exp(-max(tau, 0.0) / 0.7)));
            }
        }
    }

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

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return payload(in);
}
