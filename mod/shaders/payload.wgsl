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
const PL_TURN: f32 = 11.0;         // turns into its dive,
const PL_HIT: f32 = 13.6;          // and strikes
const PL_LEN: f32 = 44.0;          // the strike's length (lasers.rs): everything fades out over its last PL_FADE
const PL_FADE: f32 = 7.0;
const PL_V: f32 = 343.0;           // the shockwave's front, blocks a second (with the blast's sound: payload.rs)
const PL_P: u32 = 16u;             // the table: the path's samples from PL_P, three words each,
const PL_PF: u32 = 400u;           // the billows from PL_PF, PL_PW words each (launch, rise, height share, radius, x, z)
const PL_PW: u32 = 8u;
const PL_NPUFF: i32 = 18;
const PL_DEBRIS: i32 = 90;

fn pl_w(i: u32) -> f32 {
    if (i >= arrayLength(&mod_data)) {
        return 0.0;
    }
    return bitcast<f32>(mod_data[i]);
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
fn pl_col_base(col: PlCol, p: vec3<f32>) -> f32 {
    var d = 1.0e6;
    for (var i = 0; i < PL_NPUFF; i = i + 1) {
        let q = pl_puff(i, col.a, col.C, col.grow);
        if (q.w > 0.0) {
            d = smin(d, length(p - q.xyz) - q.w, 11.0);
        }
    }
    return d;
}
fn pl_col_dens(col: PlCol, p: vec3<f32>, C: vec3<f32>, a: f32, d0: f32, fine: bool) -> f32 {
    let q = (p - C) * vec3<f32>(1.0, 1.0 / col.grow, 1.0) - vec3<f32>(0.0, 1.5 * a, 0.0) - pl_wind() * (a * 0.4);
    // (billows: lumps on lumps, rounded and bulging out)
    let n1 = gnoise3(q * (1.0 / 34.0) + vec3<f32>(3.1, 0.0, 7.7));
    var d = d0 - 30.0 * (n1 - 0.42);
    if (fine) {
        let n2 = gnoise3(q * (1.0 / 12.0) + vec3<f32>(0.0, -0.6 * a, 1.3));
        d = d - 11.0 * (n2 - 0.45);
    }
    return saturate(-d / 5.0);
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
fn pl_dust(p: vec3<f32>, C: vec3<f32>, a: f32, me: vec3<f32>, dme: f32) -> f32 {
    let q = p - C;
    let r = length(q.xz);
    let ang = atan2(q.z, q.x);
    // (the front wanders a little round the ring)
    let rf = PL_V * a * (1.0 + 0.012 * sin(ang * 7.0 + 1.3) + 0.008 * sin(ang * 13.0)) - 3.0;
    if (r > rf + 4.0 || r < 8.0) {
        return 0.0;
    }
    // (its ground: the target's, rising or falling to the player's as it goes out to them)
    let gref = mix(0.0, me.y - C.y, smoothstep(0.0, max(dme, 1.0), r));
    let h = q.y - gref;
    let since = max(rf - r, 0.0) / PL_V;           // seconds since the front passed here
    let w = 5.0 + 0.04 * r;
    let lead = smoothstep(rf + 4.0, rf - 3.0, r);
    let wall = exp(-pow((rf - r) / w, 2.0)) * 2.4 + exp(-(rf - r) / (3.0 * w)) * 0.6;
    let hang = (0.5 * exp(-since / 4.0) + 0.14 * exp(-since / 25.0)) / (1.0 + r / 120.0);
    let far = 1.0 / (1.0 + r / 260.0);
    let top = mix(15.0, 8.0, saturate(r / 600.0)) * 1.5 + 3.5 * since;
    if (h > top * 3.0 || (wall + hang) * lead * far < 0.01) {
        return 0.0;
    }
    let drift = pl_wind() * a + vec3<f32>(q.x, 0.0, q.z) * (0.72 / max(r, 1.0)) * since;
    let n1 = gnoise3((q - drift) * vec3<f32>(1.0 / 16.0, 1.0 / 10.0, 1.0 / 16.0) + vec3<f32>(0.0, -0.25 * a, 0.0));
    let hd = top * (0.4 + 0.9 * n1);
    let up = exp(-max(h, 0.0) / hd) * smoothstep(-6.0, 0.0, h);
    var den = (wall + hang) * lead * up * far;
    if (den < 0.004) {
        return 0.0;
    }
    let n2 = gnoise3((q - drift) * (1.0 / 5.0) + vec3<f32>(5.0, 0.0, 1.0));
    den = den * saturate(1.6 * n1 - 0.3) * (0.65 + 0.7 * n2);
    return den;
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
    let el = 0.25 + 1.0 * mh(fi, seed, 0x302u);
    let big = mh(fi, seed, 0x303u);
    let sp = mix(28.0, 92.0, pow(mh(fi, seed, 0x304u), 0.7)) * (1.0 - 0.3 * big);
    let t0 = 0.03 + 0.25 * mh(fi, seed, 0x305u);
    let tau = a - t0;
    o.s = mix(0.12, 1.5, big * big * big);
    o.live = 0.0;
    if (tau <= 0.0) {
        return o;
    }
    let v0 = vec3<f32>(cos(ang) * cos(el), sin(el), sin(ang) * cos(el)) * sp;
    // (a little drag: they slow, and fall less than straight)
    let k = 0.06;
    let e = (1.0 - exp(-k * tau)) / k;
    let g = 9.8;
    o.p = C + vec3<f32>(0.0, 3.0, 0.0) + vec3<f32>(v0.x, 0.0, v0.z) * e + vec3<f32>(0.0, v0.y * e - g * (tau - e) / k, 0.0);
    o.v = vec3<f32>(v0.x, 0.0, v0.z) * exp(-k * tau) + vec3<f32>(0.0, (v0.y + g / k) * exp(-k * tau) - g / k, 0.0);
    let r = length((o.p - C).xz);
    let gref = C.y + mix(0.0, me.y - C.y, smoothstep(0.0, max(dme, 1.0), r));
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
            let dive = smoothstep(PL_TURN - 0.3, PL_TURN + 0.9, te);
            let rad = mix(1.1 + 1.7 * sqrt(age), 3.0 + 2.6 * sqrt(age), dive);
            if (h.x < rad && h.y < scene_len + rad) {
                let chord = 2.0 * sqrt(max(rad * rad - h.x * h.x, 0.0));
                let cp = rd * h.y;
                let nq = gnoise3((cp + cam) / (2.5 * rad + 2.0) + vec3<f32>(f32(seed % 97u), 0.0, 0.0));
                let nq2 = gnoise3((cp + cam) / (0.9 * rad + 1.0) + vec3<f32>(0.0, 3.0, f32(seed % 89u)));
                let shape = saturate(1.7 * nq - 0.3) * (0.55 + 0.9 * nq2 * (1.0 - dive * 0.5)) * saturate(1.0 - pow(h.x / rad, 2.0) * 0.85);
                let pale = 0.3 * exp(-age / 14.0) / (1.0 + 0.25 * age);
                let dark = 0.55 * exp(-age / 45.0);
                let sig = mix(pale, dark, dive) * shape * fade;
                let occl = saturate((scene_len - h.y) / rad + 0.5);
                let dtau = sig * chord * occl;
                // (lit on its sunward side)
                let axis = pa + (pb - pa) * h.z;
                let nrm = normalize(cp - axis + vec3<f32>(0.0, 1.0e-4, 0.0));
                let lit = 0.45 + 0.55 * saturate(dot(nrm, L) * 0.5 + 0.5);
                let alb = mix(vec3<f32>(0.62, 0.62, 0.64), vec3<f32>(0.075, 0.072, 0.07), dive);
                let c = alb * (sunc * lit * 0.85 + amb * 0.9);
                tc = tc + c * dtau;
                tw = tw + dtau;
                tau = tau + dtau;
                // (the flame tail just behind the head, in the dive)
                let fl = dive * exp(-age / 0.09) * step(time, PL_HIT + 0.05);
                glow = max(glow, vec3<f32>(3.5, 1.5, 0.35) * fl * min(chord * 0.35, 1.6) * occl);
            }
            pa = pb;
        }
        if (tw > 0.0) {
            let al = 1.0 - exp(-tau);
            col = mix(col, tc / tw, al * k);
        }
        col = col + glow * k;
    }

    // ---- the column: raymarched, self-shadowed towards the sun, dark at its core, fire in it as it bursts ----------
    if (have && a > 0.0) {
        let cl = pl_column(a, C);
        if (cl.n > 0) {
            let tb = pl_box(rd, cl.lo, cl.hi);
            let t1 = min(tb.y, scene_len);
            if (t1 > tb.x) {
                var t = tb.x;
                var tr = 1.0;
                var acc = vec3<f32>(0.0);
                let j = ign(in.position.xy + vec2<f32>(fract(time * 7.0) * 37.0, 0.0));
                let H = pl_w(5u);
                let ph = 0.75 + 0.55 * pow(saturate(dot(rd, L)), 5.0);
                var tmid = 0.0;
                var wmid = 0.0;
                for (var i = 0; i < 44; i = i + 1) {
                    if (t > t1 || tr < 0.04) {
                        break;
                    }
                    let p = rd * t;
                    let d0 = pl_col_base(cl, p);
                    if (d0 > 30.0) {
                        // (empty air: leap on, short of where a lump could reach)
                        t = t + d0 - 26.0;
                        continue;
                    }
                    let st = max(4.5, t * 0.011) * (0.75 + 0.5 * j);
                    let den = pl_col_dens(cl, p, C, a, d0, true);
                    if (den > 0.002) {
                        // (the sun through the column: two looks towards it)
                        let p1 = p + L * 12.0;
                        let p2 = p + L * 34.0;
                        let s1 = saturate((4.0 - pl_col_base(cl, p1)) / 16.0);
                        let s2 = saturate(-pl_col_base(cl, p2) / 14.0);
                        let tsun = exp(-(s1 * 12.0 + s2 * 28.0) * 0.22);
                        let hy = (p.y - C.y) / max(H, 1.0);
                        // (the core and the foot darker, soot-grey; the tops lighter, a little blue)
                        let core = exp(min(d0, 0.0) / 26.0);
                        let alb = mix(vec3<f32>(0.12, 0.115, 0.11), vec3<f32>(0.34, 0.36, 0.41), saturate(hy * 1.3 + 0.1));
                        let skyw = (0.3 + 0.7 * saturate(hy + 0.2)) * (0.2 + 0.8 * core) * (0.45 + 0.55 * saturate(p1.y - p.y + 0.5));
                        var c = alb * (sunc * tsun * ph * 1.5 + amb * skyw * 0.6 + vec3<f32>(0.05, 0.045, 0.04) * day);
                        // (fire in it as it bursts: low down, dying fast)
                        let fire = exp(-a / 0.55) * exp(-max(p.y - C.y, 0.0) / (14.0 + 30.0 * a)) * (0.6 + 0.4 * core);
                        c = c + vec3<f32>(5.0, 2.0, 0.45) * fire * (1.0 - core * 0.3);
                        let ext = den * 0.2 * st;
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
        let dive = smoothstep(PL_TURN, PL_TURN + 1.0, time);
        let show = smoothstep(PL_SEEN - 0.2, PL_SEEN + 1.2, time);
        let flick = 0.85 + 0.15 * sin(time * 37.0) * sin(time * 23.0 + 1.0);
        let size = mix(1.6, 5.5, dive);
        let thc = max(size / dh, px_a * 0.9);
        let hot = mix(vec3<f32>(1.0, 0.96, 0.9), vec3<f32>(1.0, 0.55, 0.16), dive);
        let core = exp(-pow(th / thc, 2.0)) * mix(14.0, 9.0, dive);
        let bloom = 0.9 / (1.0 + pow(th / (thc * 4.0 + 0.004), 2.0)) + 0.18 * exp(-th / 0.05);
        // (a faint horizontal streak, the lens's)
        let sv = rd - hn * cth;
        let up = normalize(cross(cross(hn, vec3<f32>(0.0, 1.0, 0.0)), hn) + vec3<f32>(0.0, 1.0e-5, 0.0));
        let streak = exp(-abs(dot(sv, up)) / (px_a * 1.5)) * exp(-th / 0.12) * 0.25;
        col = col + hot * (core + bloom + streak) * show * vis * flick * k;
    }

    // ---- the dust: marched along the view ray, low over the land ------------------------------------------------
    if (a > 0.0 && a < 32.0) {
        let rf = PL_V * a;
        let ylo = min(C.y, me.y) - 8.0;
        let yhi = max(C.y, me.y) + 60.0;
        var t0 = 0.0;
        var t1 = min(scene_len, 1400.0);
        if (abs(rd.y) > 1.0e-5) {
            let ya = ylo / rd.y;
            let yb = yhi / rd.y;
            t0 = max(t0, min(ya, yb));
            t1 = min(t1, max(ya, yb));
        } else if (ylo > 0.0 || yhi < 0.0) {
            t1 = -1.0;
        }
        // (and only out to the front)
        let a2 = max(dot(rd.xz, rd.xz), 1.0e-8);
        let bb = -dot(rd.xz, C.xz);
        let R = rf + 6.0;
        let disc = bb * bb - a2 * (dot(C.xz, C.xz) - R * R);
        if (disc > 0.0) {
            t0 = max(t0, (-bb - sqrt(disc)) / a2);
            t1 = min(t1, (-bb + sqrt(disc)) / a2);
        } else {
            t1 = -1.0;
        }
        if (t1 > t0) {
            let N = 18;
            var tr = 1.0;
            var acc = vec3<f32>(0.0);
            let j = ign(in.position.xy + vec2<f32>(0.0, fract(time * 5.0) * 53.0));
            for (var i = 0; i < N; i = i + 1) {
                let u0 = (f32(i) + j) / f32(N);
                let u1 = (f32(i) + 1.0 + j) / f32(N);
                let t = t0 + (t1 - t0) * u0 * u0;
                let dt = (t1 - t0) * (u1 * u1 - u0 * u0);
                let p = rd * t;
                let den = pl_dust(p, C, a, me, dme);
                if (den <= 0.0) {
                    continue;
                }
                let al = 1.0 - exp(-den * dt * 0.06);
                let q = p - C;
                let r = length(q.xz);
                let h = q.y - mix(0.0, me.y - C.y, smoothstep(0.0, max(dme, 1.0), r));
                let lo = 0.55 + 0.45 * saturate(h / 10.0);
                let dc = vec3<f32>(0.6, 0.47, 0.3) * (sunc * 0.8 * lo + amb * 0.9);
                acc = acc + tr * al * dc;
                tr = tr * (1.0 - al);
                if (tr < 0.02) {
                    break;
                }
            }
            col = mix(col, col * tr + acc, k * fade);
        }
    }

    // ---- the debris: chunks and specks of earth, flying and falling ------------------------------------------------
    if (a > 0.0 && a < 16.0) {
        let fpx = frame.resolution.y / (2.0 * tan(frame.view_params.w * 0.5));
        let pxy = in.position.xy;
        var cov = 0.0;
        for (var i = 0; i < PL_DEBRIS; i = i + 1) {
            let ch = pl_chunk(i, a, seed, C, me, dme);
            if (ch.live <= 0.0) {
                continue;
            }
            let dist = length(ch.p);
            if (dist > scene_len || dist < 1.0) {
                continue;
            }
            let s0 = project_rel(ch.p);
            if (s0.z < 0.0) {
                continue;
            }
            let q0 = s0.xy * frame.resolution.xy;
            let rad0 = max(ch.s * fpx / dist, 0.55);
            if (length(pxy - q0) > rad0 * 1.4 + length(ch.v) * 0.03 * fpx / dist + 2.0) {
                continue;
            }
            let s1 = project_rel(ch.p - ch.v * 0.03);
            let q1 = s1.xy * frame.resolution.xy;
            let rad = max(ch.s * fpx / dist, 0.55);
            // (a capsule along its blur)
            let ab = q1 - q0;
            let w = saturate(dot(pxy - q0, ab) / max(dot(ab, ab), 1.0e-4));
            let e = length(pxy - (q0 + ab * w));
            let lump = 1.0 + 0.3 * sin(atan2(pxy.y - q0.y, pxy.x - q0.x) * 3.0 + f32(i));
            let c = saturate(rad * lump + 0.5 - e) * ch.live * saturate(rad / max(length(ab) * 0.5, rad));
            cov = max(cov, c);
        }
        let dirt = vec3<f32>(0.05, 0.042, 0.035) * (amb * 1.5 + sunc * 0.35);
        col = mix(col, dirt, cov * k * fade);
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
