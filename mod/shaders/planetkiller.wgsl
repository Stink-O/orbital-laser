// Orbital Laser's post pass for the Planet Killer (laser 6). Like the Downfall's, the mod builds it from
// shaders/strike.wgsl up to its fs_main (the helpers: the noise, ray_seg, bolt_line, lava_ramp, project_rel, mh) less the
// other lasers' own functions, followed by this file, and sets it for a planet killer strike only, so its size costs the
// other lasers nothing. Validate with tools/check-shader.sh.

// ---- laser 6: the planet killer -----------------------------------------------------------------------------------
// Seven towers tear up out of the land far out round the horizon, one after another, dark against a sky going dark, the
// light running up their seams. Each fires a column of light straight up into the sky, then bends it over like a
// searchlight onto a point high over the target, the beams braided with strands of light and surges racing along them.
// Where they meet a star swells inside spinning rings, bending the light round it and drawing streaks of light in,
// until it shudders out of true and they fuse: a flash, a ring of fire tearing out through the sky, the sky cracking and
// the clouds blown open. One beam comes down. The land under it domes up, cracking with light, and bursts: a fireball, a
// column of ejecta, a shock ring rippling out through the land and a wall of dust, debris spiralling up round the beam,
// the crater molten and fissures running out from it pulsing with light. Then the towers go dark and sink, their beams
// draining into the star; it collapses, drops into the crater and bursts again, and a mushroom of glowing smoke climbs
// over the crater as the daylight comes back. strike.rs times the same strike, digs the same crater and opens the same
// fissures (pk_crack): keep the PK_* and pk_* in step.

const PK_N: i32 = 7;               // the towers
const PK_H: f32 = 300.0;           // the nexus, where their beams meet, this high over the target
const PK_SRC_R: f32 = 1500.0;      // how far out the towers stand
const PK_TOWER_H: f32 = 420.0;     // how tall they stand, and how wide at the foot
const PK_TOWER_R: f32 = 62.0;
const PK_RAISE: f32 = 0.45;        // a tower tears up out of the land over this long before it fires
const PK_IGN0: f32 = 0.51;         // the first fires (it starts to rise as the strike does), the last by PK_IGN1
const PK_IGN1: f32 = 1.71;
const PK_UP: f32 = 0.25;           // its column reaches PK_COL high this long after it fires,
const PK_COL: f32 = 1100.0;
const PK_BEND0: f32 = 0.45;        // and bends over onto the nexus from this long after it fires, over PK_BEND
const PK_BEND: f32 = 0.8;
const PK_SHAKE: f32 = 3.3;         // the nexus shudders out of true from here
const PK_MERGE: f32 = 4.0;         // keep in step with strike.rs: PK_IGN*, PK_RAISE, PK_MERGE, PK_HIT, PK_BURST, PK_CUT,
const PK_DROP: f32 = 4.1;          // PK_POP, PK_BOWL, PK_BOWL_D, PK_DIG*, the cracks'
const PK_HIT: f32 = 4.35;          // the one beam lands, the ground domes up,
const PK_BURST: f32 = 4.85;        // and bursts
const PK_CUT: f32 = 13.5;          // the towers cut out
const PK_DRAIN: f32 = 0.4;         // their beams drain up into the nexus over this long, all done before it falls
const PK_FALL: f32 = 14.0;         // it drops into the crater,
const PK_POP: f32 = 14.4;          // and bursts there
const PK_END: f32 = 24.0;          // the daylight is back (the strike runs 26 s)
const PK_BLAST: f32 = 170.0;       // the land flattened out to here
const PK_BOWL: f32 = 130.0;        // the crater's radius and depth (the laser's bowl_r, bowl_d), dug 3 blocks at a time
const PK_BOWL_D: f32 = 70.0;       // from PK_DIG0 after the burst, PK_DIG_K seconds a block down at the top (pk_dig_t)
const PK_DIG0: f32 = 2.9;
const PK_DIG_K: f32 = 0.21;
const PK_CRACKS: i32 = 12;         // the fissures: from PK_RIM out, PK_SEG-block segments, opening at PK_CRACK_V blocks a
const PK_RIM: f32 = 126.0;         // second from PK_CRACK_T after the burst
const PK_SEG: f32 = 12.0;
const PK_CRACK_V: f32 = 90.0;
const PK_CRACK_T: f32 = 0.9;
// The beams' light: a searing white core in an electric blue, a deep cobalt glow round it.
const PK_WHITE: vec3<f32> = vec3<f32>(7.0, 8.0, 10.0);
const PK_HOT: vec3<f32> = vec3<f32>(0.9, 2.2, 6.0);
const PK_DEEP: vec3<f32> = vec3<f32>(0.08, 0.22, 1.8);

// Tower i: where its foot stands (xyz) and when it fires (w). The first fires beyond the target as the player faces it,
// the rest alternately to its right and left, round towards the player; each a little off its place and its time.
fn pk_emitter(i: i32, seed: f32) -> vec4<f32> {
    let s = u32(seed);
    let side = select(-1.0, 1.0, i % 2 == 1);
    let a = wing_a() + 3.14159265 + side * f32((i + 1) / 2) * TAU / f32(PK_N) + (mh(u32(i), s, 31u) - 0.5) * 0.5;
    let r = PK_SRC_R * (0.8 + 0.4 * mh(u32(i), s, 32u));
    let t = PK_IGN0 + (PK_IGN1 - PK_IGN0) * f32(i) / f32(PK_N - 1) + (mh(u32(i), s, 33u) - 0.5) * 0.12;
    let tgt = target_pos();
    return vec4<f32>(tgt.x + cos(a) * r, tgt.y - 2.0, tgt.z + sin(a) * r, t);
}

// Fissure i: x its heading out from the target, y how long it runs past PK_RIM. Its line wanders off that heading by
// pk_crack_off at each PK_SEG.
fn pk_crack(i: i32, seed: f32) -> vec2<f32> {
    let s = u32(seed);
    let a = (f32(i) + 0.7 * mh(u32(i), s, 21u)) * TAU / f32(PK_CRACKS) + mh(99u, s, 22u) * TAU;
    return vec2<f32>(a, 120.0 + 70.0 * mh(u32(i), s, 23u));
}
fn pk_crack_off(i: i32, j: i32, seed: f32) -> f32 {
    return select((mh(u32(i * 32 + j), u32(seed), 24u) - 0.5) * 0.12, 0.0, j == 0);
}

// When the 3 blocks of the crater from `d` down are dug (strike.rs's pk_dig_t): the time to dig all of the bowl over
// them, its area falling off with depth as a paraboloid's does.
fn pk_dig_t(d: f32) -> f32 {
    let q = floor(d / 3.0) * 3.0;
    return PK_BURST + PK_DIG0 + PK_DIG_K * (q - q * q / (2.0 * (PK_BOWL_D + 0.5)));
}

// How much of a light `t` along the view ray shows: all of it in front of the scene or against the sky, some through a
// cloud, none behind the land.
fn pk_occ(t: f32, scene_len: f32, sky: bool, cloud: bool) -> f32 {
    return select(select(0.0, 0.5, cloud), 1.0, sky || t < scene_len);
}

// A ring of radius R round C (camera-relative) in the plane of e1 and e2: x how close the view ray passes to it, y how
// far along the ray, z where round it (radians). Where the ray crosses its plane, its nearest point is straight out from
// the middle; where the ray runs along the plane, from the ray's closest point to the middle.
fn pk_ring(rd: vec3<f32>, C: vec3<f32>, e1: vec3<f32>, e2: vec3<f32>, R: f32) -> vec3<f32> {
    let n = cross(e1, e2);
    var X = rd * max(dot(C, rd), 0.0) - C;
    let dn = dot(rd, n);
    if (abs(dn) > 0.08) {
        let tp = dot(C, n) / dn;
        if (tp > 0.0) {
            X = rd * tp - C;
        }
    }
    let a = atan2(dot(X, e2), dot(X, e1));
    let P = C + (e1 * cos(a) + e2 * sin(a)) * R;
    let tq = max(dot(P, rd), 0.0);
    return vec3<f32>(length(P - rd * tq), tq, a);
}

// A tower's radius `yp` blocks up from its bottom: a tapering shaft, a drum for its head, a spike for its tip.
fn pk_tower_r(yp: f32) -> f32 {
    if (yp < 0.0 || yp > PK_TOWER_H) {
        return 0.0;
    }
    let u = yp / PK_TOWER_H;
    if (u < 0.84) {
        return mix(PK_TOWER_R, 16.0, u / 0.84);
    }
    if (u < 0.93) {
        return 30.0;
    }
    return 12.0 * (1.0 - (u - 0.93) / 0.07);
}

// The view ray against a tower whose foot is at b (camera-relative), risen `lift` blocks out of the land: x how far
// along the ray (under 0 if it misses), y the angle round it, z how far up it from its bottom, w how square on it faces
// the eye (1 face on, 0 at its edge). Met as an upright cylinder of the radius at the height it is met at, twice over.
fn pk_tower(b: vec3<f32>, lift: f32, rd: vec3<f32>) -> vec4<f32> {
    let o = -b.xz;
    let v = rd.xz;
    let a = max(dot(v, v), 1.0e-8);
    let bb = dot(o, v);
    var t = -bb / a;
    var r = pk_tower_r(rd.y * t - b.y + PK_TOWER_H - lift);
    for (var k = 0; k < 2; k = k + 1) {
        let disc = bb * bb - a * (dot(o, o) - r * r);
        if (r <= 0.0 || disc < 0.0) {
            return vec4<f32>(-1.0);
        }
        t = (-bb - sqrt(disc)) / a;
        let rn = pk_tower_r(rd.y * t - b.y + PK_TOWER_H - lift);
        if (rn <= 0.0) {
            return vec4<f32>(-1.0);
        }
        r = rn;
    }
    let p = rd * t - b;
    if (t <= 0.0 || p.y < 0.0) {
        return vec4<f32>(-1.0);
    }
    let nrm = normalize(p.xz);
    return vec4<f32>(t, atan2(nrm.y, nrm.x), p.y + PK_TOWER_H - lift, saturate(dot(nrm, -normalize(v))));
}

// Where tower i's beam runs at `time` (camera-relative): a quadratic curve from its tip (a) through c to its end (b),
// drawn from u0 to u1 of the way along. It fires a column straight up, bends it over onto the nexus, and at the end
// drains from the tower end up into it.
struct PkCurve {
    a: vec3<f32>,
    c: vec3<f32>,
    b: vec3<f32>,
    u0: f32,
    u1: f32,
}
fn pk_curve(e: vec4<f32>, NX: vec3<f32>, cam: vec3<f32>, time: f32, i: i32, seed: f32) -> PkCurve {
    var cv: PkCurve;
    let et = time - e.w;
    cv.a = e.xyz - cam + vec3<f32>(0.0, PK_TOWER_H, 0.0);
    let bend = smoothstep(PK_BEND0, PK_BEND0 + PK_BEND, et);
    let up = cv.a + vec3<f32>(0.0, PK_COL, 0.0);
    let arc = mix(cv.a, NX, 0.35) + vec3<f32>(0.0, 420.0, 0.0);
    cv.b = mix(up, NX, bend * bend * (3.0 - 2.0 * bend));
    cv.c = mix(cv.a + vec3<f32>(0.0, PK_COL * 0.5, 0.0), arc, bend);
    cv.u1 = saturate(et / PK_UP);
    cv.u0 = saturate((time - PK_CUT - 0.1 * mh(u32(i), u32(seed), 34u)) / PK_DRAIN);
    return cv;
}
fn pk_bez(cv: PkCurve, s: f32) -> vec3<f32> {
    let m = 1.0 - s;
    return cv.a * (m * m) + cv.c * (2.0 * m * s) + cv.b * (s * s);
}

fn planet_killer(in: StageIn) -> vec4<f32> {
    let uv = in.uv;
    let aspect = frame.resolution.x / frame.resolution.y;
    let time = now();
    let cam = frame.camera_position.xyz;
    let tgt = target_pos();
    let crel = tgt - cam;
    let k = intensity_v();
    let seed = seed_v();

    // ---- timeline -------------------------------------------------------------
    // the daylight draining away as the towers rise, back once it is over
    let dark = smoothstep(0.0, 1.5, time) * (1.0 - smoothstep(PK_POP + 1.5, PK_END, time));
    let charge = smoothstep(PK_IGN0 + PK_BEND0 + PK_BEND, PK_MERGE, time) * f32(time < PK_FALL);
    let unstable = smoothstep(PK_SHAKE, PK_MERGE, time) * f32(time < PK_MERGE);
    let merge_t = time - PK_MERGE;
    let merged = merge_t > 0.0;
    let burn = smoothstep(PK_DROP, PK_DROP + 0.05, time) * (1.0 - smoothstep(PK_CUT + PK_DRAIN, PK_CUT + PK_DRAIN + 0.4, time));
    let hit_t = time - PK_HIT;
    let bt = time - PK_BURST;                                   // since the land burst
    let burst = bt > 0.0;
    let mt = time - PK_POP;                                     // since the nexus burst in the crater
    let popped = mt > 0.0;
    // (the screen flashes as the land bursts and as the nexus does, a little as they fuse)
    let flash = select(0.0, exp(-bt * 5.0), burst) + select(0.0, exp(-merge_t * 9.0) * 0.3, merged)
        + select(0.0, exp(-mt * 9.0) * 0.4, popped) + select(0.0, exp(-hit_t * 12.0) * 0.25, hit_t > 0.0);
    let after = 1.0 - smoothstep(PK_END - 0.5, PK_END + 2.0, time);
    // the towers' power: rising with them, full while they fire, gone once they cut out
    let power = 1.0 - smoothstep(PK_CUT, PK_CUT + 0.8, time);

    // the towers, and how many beams are feeding the nexus
    var em: array<vec4<f32>, 7>;
    var fed = 0.0;
    for (var i = 0; i < PK_N; i = i + 1) {
        em[i] = pk_emitter(i, seed);
        fed = fed + smoothstep(PK_BEND0 + PK_BEND * 0.7, PK_BEND0 + PK_BEND + 0.2, time - em[i].w);
    }
    // the nexus: a point when the first beam reaches it, swelling with each one after and with the charge, shuddering,
    // blazing as they fuse, steady while it feeds the beam, collapsing as they drain, then falling into the crater
    let collapse = 1.0 - 0.8 * smoothstep(PK_CUT + 0.2, PK_FALL, time);
    let fall = smoothstep(PK_FALL, PK_POP, time);
    let NX0 = crel + vec3<f32>(0.0, PK_H, 0.0) + vec3<f32>(sin(time * 41.0), sin(time * 37.0 + 1.0), cos(time * 43.0)) * 2.5 * unstable;
    let NX = NX0 - vec3<f32>(0.0, (PK_H - 6.0) * fall * fall, 0.0);
    let Rn = (1.5 + 1.1 * fed + 8.0 * charge * charge + 12.0 * select(0.0, exp(-merge_t * 2.5), merged))
        * (0.93 + 0.07 * sin(time * 31.0) + 0.04 * sin(time * 53.0) + 0.25 * unstable * sin(time * 67.0))
        * collapse * f32(fed > 0.0 && !popped);
    let glow_n = saturate(fed / 3.0) * (0.4 + 0.6 * charge + 0.6 * burn) * collapse * f32(!popped);
    let rings_on = saturate(fed / 2.0) * (1.0 - smoothstep(PK_CUT, PK_FALL, time));

    // ---- the light and the sky ------------------------------------------------
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let pT = project_rel(crel);
    let pN = project_rel(NX);

    // ---- what bends the light: the nexus's pull, and the shock rings running out through the land ----------------
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    var off = vec2<f32>(0.0);
    if (pN.z > 0.0 && glow_n > 0.01) {
        // the light round the nexus pulled in towards it, harder as it charges and as it shudders
        let side = normalize(cross(NX, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
        let rs = length((project_rel(NX + side * Rn * 3.0).xy - pN.xy) * vec2<f32>(aspect, 1.0));
        let dv = (uv - pN.xy) * vec2<f32>(aspect, 1.0);
        let dl = max(length(dv), 1.0e-5);
        let pull = rs * rs / max(dl, rs * 0.8) * (0.35 + 0.5 * charge + 0.8 * unstable) * exp(-dl / (rs * 6.0 + 1.0e-4));
        off = off - dv / dl * min(pull, 0.05) / vec2<f32>(aspect, 1.0) * glow_n * k;
    }
    if (pT.z > 0.0 && !sky0) {
        let r0 = length(p0.xz - tgt.xz);
        if (burst) {
            // the land rippling as the shock runs out through it, rings of it behind the front
            let rs = 60.0 + 220.0 * pow(bt, 0.8);
            let m = (exp(-pow((r0 - rs) / 7.0, 2.0)) + 0.5 * exp(-pow((r0 - rs * 0.8) / 5.0, 2.0)) * sin(r0 * 0.15 - bt * 20.0))
                * exp(-bt * 0.4);
            off = off + normalize(uv - pT.xy + vec2<f32>(1.0e-5)) * m * 0.03 * k;
        }
        if (popped) {
            let rs = 20.0 + 160.0 * pow(mt, 0.8);
            off = off + normalize(uv - pT.xy + vec2<f32>(1.0e-5)) * exp(-pow((r0 - rs) / 6.0, 2.0)) * exp(-mt * 0.6) * 0.02 * k;
        }
    }
    if (burn > 0.001 && pT.z > 0.0) {
        // the air boiling round the beam's foot
        let m = exp(-length((uv - pT.xy) * vec2<f32>(aspect, 1.0)) / 0.1);
        let hw = vec2<f32>(gnoise2(uv * vec2<f32>(120.0, 45.0) + vec2<f32>(0.0, -time * 8.0)), gnoise2(uv * vec2<f32>(120.0, 45.0) + vec2<f32>(31.0, -time * 7.0))) - 0.5;
        off = off + hw * 0.006 * m * burn * k;
    }
    let uv2 = clamp(uv + off, vec2<f32>(0.002), vec2<f32>(0.998));

    // ---- the scene ------------------------------------------------------------
    let d = depth_at(uv2);
    let sky = is_sky(d);
    let rel = world_offset(uv2, select(d, 0.5, sky));
    var scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let rdb = normalize(world_offset(uv, 0.5));                // not bent
    let P = cam + rel;
    let cloud = !sky && abs(P.y - CLOUD_Y - 2.0) < 6.0;
    let ca = flash * 0.015 * k;
    let ca_dir = (uv2 - vec2<f32>(0.5)) * ca;
    var col = srgb_to_linear(vec3<f32>(
        textureSampleLevel(scene_color, linear_sampler, uv2 + ca_dir, 0.0).r,
        textureSampleLevel(scene_color, linear_sampler, uv2, 0.0).g,
        textureSampleLevel(scene_color, linear_sampler, uv2 - ca_dir, 0.0).b));
    // the sky goes to a deep night blue, a band of light along the horizon while the towers fire; the land dark
    let night = vec3<f32>(0.004, 0.007, 0.022) + vec3<f32>(0.03, 0.05, 0.16) * exp(-abs(rd.y) / 0.06) * power * saturate(time - PK_IGN0);
    if (sky) {
        col = mix(col, night, 0.88 * dark * k);
    } else {
        col = col * (1.0 - 0.62 * dark * k);
    }
    // the clouds blown open from under the nexus as they fuse, a rim of light running out round the hole
    if (cloud && merged) {
        let dcl = length(P.xz - (NX + cam).xz);
        let Rh = 1100.0 * (1.0 - exp(-merge_t * 0.9));
        col = mix(col, night * dark + vec3<f32>(0.2, 0.3, 0.5) * (1.0 - dark), smoothstep(Rh, Rh - 90.0, dcl) * 0.95 * k);
        col = col + PK_HOT * exp(-pow((dcl - Rh) / 45.0, 2.0)) * 0.5 * exp(-merge_t * 0.5) * k;
    }
    var add = vec3<f32>(0.0);

    // ---- the towers: torn up out of the land, dark, power running up their seams, their crowns lit ----------------
    for (var i = 0; i < PK_N; i = i + 1) {
        let e = em[i];
        let rt = time - (e.w - PK_RAISE);
        if (rt <= 0.0) {
            continue;
        }
        let S = e.xyz - cam;
        let ds = length(S);
        let sdir = S / ds;
        let et = time - e.w;
        // it rises, eased to a stop; once it has cut out it sinks back
        let rise = smoothstep(0.0, PK_RAISE, rt);
        let sink = smoothstep(PK_CUT + 1.5, PK_CUT + 5.0, time);
        let lift = PK_TOWER_H * rise * rise * (3.0 - 2.0 * rise) * (1.0 - sink);
        let lit = smoothstep(-0.3, 0.1, et) * power;
        let burst_ = select(0.0, exp(-et * 2.2), et > 0.0);
        // (the horizon round it lit up, along the horizon more than above it: in the sky and on the far land)
        let c = 1.0 - dot(rd, sdir);
        let low = exp(-abs(rd.y - sdir.y - 0.05) / 0.07);
        add = add + PK_DEEP * exp(-c / 0.02) * low * (1.4 * burst_ + 0.35 * lit + 0.4 * (1.0 - rise) * f32(rise > 0.0))
            * select(0.15, 1.0, sky || scene_len > ds * 0.6) * k;
        if (lift < 1.0) {
            continue;
        }
        let th = pk_tower(S, lift, rd);
        if (th.x > 0.0 && (sky || th.x < scene_len)) {
            let yp = th.z;
            let u = yp / PK_TOWER_H;
            // dark metal, lit at its edge by the glow behind it; seams and bands of light, power surging up them
            let body = vec3<f32>(0.025, 0.03, 0.04) * (0.35 + 0.65 * day) * (1.0 - 0.4 * dark) + PK_DEEP * pow(1.0 - th.w, 3.0) * 0.25 * (0.3 + lit);
            let seam = exp(-pow(sin(th.y * 4.0) / 0.05, 2.0)) * smoothstep(0.84, 0.8, u);
            let band = exp(-pow((fract(yp / 38.0) - 0.5) / 0.04, 2.0));
            let surge = 0.35 + pow(0.5 + 0.5 * sin(yp * 0.035 - time * 12.0 + th.y), 6.0) * 1.6;
            let drum = smoothstep(0.83, 0.85, u) * smoothstep(0.94, 0.92, u) * (0.5 + 0.5 * pow(0.5 + 0.5 * sin(th.y * 6.0 + time * 4.0), 3.0));
            let haze = saturate(ds / 6000.0);
            let tc = body + PK_HOT * ((seam * 0.5 + band * 0.25) * surge * (0.2 + lit) + drum * (0.3 + 1.6 * lit + 2.0 * burst_));
            col = mix(tc, col, haze);
            add = add * haze;
            scene_len = min(scene_len, th.x);
        }
        // its crown: a ring of light round its head, turning, and the point of its tip blazing as it fires
        let hd = S + vec3<f32>(0.0, lift - PK_TOWER_H * 0.12, 0.0);
        let rg = pk_ring(rd, hd, vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), 75.0);
        let wr = max(2.5, rg.y * 0.0013);
        add = add + (PK_HOT * exp(-pow(rg.x / wr, 2.0)) * (2.5 / wr) * (0.4 + 0.6 * pow(0.5 + 0.5 * sin(rg.z * 5.0 + time * 3.0), 2.0)))
            * (0.15 + 0.85 * lit) * pk_occ(rg.y, scene_len + 5.0, sky, cloud) * k;
        let tip = S + vec3<f32>(0.0, lift, 0.0);
        let ct = 1.0 - dot(rd, normalize(tip));
        add = add + (PK_WHITE * exp(-ct / 3.0e-6) * 0.6 + PK_HOT * exp(-ct / 6.0e-5) * 0.4) * (lit + 2.0 * burst_)
            * pk_occ(length(tip) - 5.0, scene_len, sky, cloud) * k;
    }

    // ---- on the land: lit by the nexus and the beam, the shock rings, the crater and the fissures molten ----------
    let rel2 = P.xz - tgt.xz;
    let r = length(rel2);
    let dy = P.y - tgt.y;
    if (!sky) {
        let on_ground = 1.0 - smoothstep(25.0, 40.0, dy);
        // the nexus lights everything under it, like a second sun
        let ln = NX + cam - P;
        col = col + col * vec3<f32>(1.0, 1.7, 3.2) * glow_n * 90000.0 / (dot(ln, ln) + 60000.0) * k;
        // the beam hard on the land round its foot
        col = col + col * vec3<f32>(1.6, 2.2, 3.6) * burn * 9000.0 / (r * r + dy * dy + 3000.0) * k;
        if (charge > 0.0 && hit_t < 0.5) {
            // charging: a ring of light closing in on the target
            let fade = 1.0 - smoothstep(0.0, 0.5, hit_t);
            let conv = mix(160.0, 3.0, pow(charge, 1.4));
            add = add + PK_HOT * (exp(-pow((r - conv) / 2.0, 2.0)) * 0.9 + exp(-r / 12.0) * charge * charge * 0.6) * charge * on_ground * fade * k;
        }
        if (burst) {
            // the shock ring racing out over the land, kicking up dust as it goes
            let rs = 60.0 + 220.0 * pow(bt, 0.8);
            add = add + (PK_HOT * 0.6 + vec3<f32>(1.2, 1.0, 0.8)) * exp(-pow((r - rs) / 4.0, 2.0)) * exp(-bt * 0.5) * on_ground * k;
            let behind = smoothstep(rs, rs - 30.0, r) * smoothstep(rs - 160.0, rs - 50.0, r) * exp(-bt * 0.3);
            col = mix(col, vec3<f32>(0.16, 0.13, 0.11) * (0.3 + 0.7 * day) * (1.0 - 0.6 * dark), behind * 0.55 * on_ground * k);
        }
        if (popped) {
            let rs = 20.0 + 160.0 * pow(mt, 0.8);
            add = add + PK_HOT * exp(-pow((r - rs) / 3.0, 2.0)) * exp(-mt * 0.7) * 0.8 * on_ground * k;
        }
        if (burst && r < PK_BOWL + 10.0) {
            // the crater molten where it has been dug (each layer glowing as it is opened, cooling), hottest deepest, and
            // the lake of lava on its floor; round the foot of the beam everything white-hot
            let deep = max(-dy, 0.0);
            let dug = max(time - pk_dig_t(deep), 0.0);
            let fresh = exp(-dug / 8.0) * smoothstep(1.0, 3.0, deep);
            let core = saturate((deep - 25.0) / 40.0);
            let lake = smoothstep(PK_BOWL_D - 6.0, PK_BOWL_D - 3.0, deep);
            let heat = max(max(fresh * 0.85, core * 0.75), lake) * (1.0 - smoothstep(PK_BOWL - 4.0, PK_BOWL + 10.0, r))
                + burn * exp(-r / 22.0);
            let n = gfbm2(rel2 * 0.06 + vec2<f32>(P.y * 0.2 + time * 0.05, seed));
            let veins = exp(-pow((n - 0.5) / 0.07, 2.0));
            let molten = mix(veins * 0.9, 1.0, saturate(heat * heat + lake));
            let hh = heat * molten * (0.8 + 0.4 * gnoise2(rel2 * 0.15 + vec2<f32>(time * 0.3, P.y)));
            add = add + lava_ramp(hh) * smoothstep(0.03, 0.25, heat * molten) * on_ground * after * 2.6 * k;
        }
        // the fissures running out from the rim, opening as the shock reaches them, light pulsing out along them
        if (burst && r > PK_RIM - 2.0 && r < PK_RIM + 200.0) {
            let ang = atan2(rel2.y, rel2.x);
            var crack = 0.0;
            var pulse = 0.0;
            // (each fissure keeps to its own twelfth of the way round, give or take, so only the three nearest are looked at)
            let base = mh(99u, u32(seed), 22u) * TAU;
            let x = (ang - base) / (TAU / f32(PK_CRACKS));
            let i0 = i32(floor(x - floor(x / f32(PK_CRACKS)) * f32(PK_CRACKS)));
            for (var di = -1; di <= 1; di = di + 1) {
                let i = (i0 + di + PK_CRACKS) % PK_CRACKS;
                let cr = pk_crack(i, seed);
                let u = r - PK_RIM;
                if (u > cr.y) {
                    continue;
                }
                let j = i32(floor(max(u, 0.0) / PK_SEG));
                let f = fract(max(u, 0.0) / PK_SEG);
                let a = cr.x + mix(pk_crack_off(i, j, seed), pk_crack_off(i, j + 1, seed), f);
                var da = ang - a;
                da = da - TAU * floor(da / TAU + 0.5);
                let lat = abs(da) * r;
                let hw = 0.8 + 3.5 * (1.0 - u / cr.y);
                let open = saturate((bt - PK_CRACK_T - u / PK_CRACK_V) * 3.0);
                let c1 = ((1.0 - smoothstep(hw - 0.4, hw + 0.8, lat)) + exp(-lat / (hw * 2.5)) * 0.35) * open;
                if (c1 > crack) {
                    crack = c1;
                    pulse = pow(0.5 + 0.5 * sin(u * 0.1 - time * 5.0 + f32(i)), 4.0);
                }
            }
            if (crack > 0.01) {
                let hh = (0.55 + 0.35 * exp(-bt / 14.0) + 0.25 * pulse * power) * (0.85 + 0.3 * gnoise2(rel2 * 0.3 + vec2<f32>(time * 0.3, 0.0)));
                add = add + (lava_ramp(hh) + PK_HOT * pulse * 0.4 * power) * crack * on_ground * after * 2.2 * k;
            }
        }
    }
    // the clouds lit from above by the nexus, from below by the beam
    if (cloud) {
        let dn = length((P - cam - NX).xz);
        add = add + PK_HOT * (glow_n * 0.5 * exp(-dn / 160.0) + burn * 0.4 * exp(-length(rel2) / 80.0)) * k;
    }

    // ---- the land doming up under the beam, cracking with the light inside it, before it bursts --------------------
    if (hit_t > 0.0 && !burst) {
        let s = smoothstep(0.0, PK_BURST - PK_HIT, hit_t);
        let Rd = 30.0 + 140.0 * s;
        let Cd = crel - vec3<f32>(0.0, Rd * 0.62, 0.0);
        let tcd = dot(Cd, rd);
        let dc2 = dot(Cd, Cd) - tcd * tcd;
        if (tcd > 0.0 && dc2 < Rd * Rd) {
            let td = tcd - sqrt(Rd * Rd - dc2);
            let pd = rd * td - Cd;
            if (pd.y + Cd.y - crel.y > -1.0 && (sky || td < scene_len + 4.0)) {
                let nd = pd / Rd;
                let cn = abs(gnoise2(vec2<f32>(atan2(nd.z, nd.x) * 4.0, nd.y * 6.0) + vec2<f32>(seed)) - 0.5);
                let cn2 = abs(gnoise2(vec2<f32>(atan2(nd.z, nd.x) * 11.0, nd.y * 15.0) + vec2<f32>(seed + 7.0)) - 0.5);
                let cracks = (exp(-cn / 0.014) + 0.6 * exp(-cn2 / 0.01)) * smoothstep(0.1, 0.8, s);
                let top = exp(-(1.0 - nd.y) * 14.0);
                // (lit from above by the nexus and the beam, its sides in shadow)
                col = vec3<f32>(0.07, 0.06, 0.055) * (0.25 + 0.4 * day + 1.2 * max(nd.y, 0.0) * glow_n) * (1.0 - 0.4 * dark);
                add = (lava_ramp(0.5 + 0.45 * cracks) * cracks * 3.0 + PK_HOT * top * 2.0 * s) * k;
                scene_len = min(scene_len, td);
            }
        }
    }

    // ---- the wall of dust thrown out round it, racing over the land and climbing ------------------------------------
    if (burst && bt < 12.0) {
        let Rw = 70.0 + 300.0 * (1.0 - exp(-bt * 0.3));
        let Hw = 20.0 + 110.0 * (1.0 - exp(-bt * 0.45));
        let c2 = cam.xz - tgt.xz;
        let v2 = rd.xz;
        let a2 = dot(v2, v2);
        let b2 = dot(c2, v2);
        let disc = b2 * b2 - a2 * (dot(c2, c2) - Rw * Rw);
        if (a2 > 1.0e-6 && disc > 0.0) {
            let sq = sqrt(disc);
            var dust = 0.0;
            for (var s = 0; s < 2; s = s + 1) {
                let tw = (-b2 + select(-sq, sq, s == 1)) / a2;
                if (tw <= 0.0 || (!sky && tw > scene_len)) {
                    continue;
                }
                let pw = cam + rd * tw;
                let hy = pw.y - tgt.y;
                let aw = atan2(pw.z - tgt.z, pw.x - tgt.x);
                let n = gfbm2(vec2<f32>(aw * 7.0 + seed, hy * 0.03 - bt * 0.3));
                let top = Hw * (0.55 + 0.8 * n);
                dust = max(dust, smoothstep(top, top * 0.3, hy) * smoothstep(-6.0, 2.0, hy) * (0.5 + 0.6 * n));
            }
            let fade = exp(-bt / 4.0) * smoothstep(0.0, 0.3, bt);
            let lit = vec3<f32>(0.2, 0.18, 0.16) * (0.25 + 0.75 * day) * (1.0 - 0.6 * dark) + vec3<f32>(0.2, 0.28, 0.5) * burn * 0.6 * exp(-Rw / 300.0);
            col = mix(col, lit, saturate(dust * fade) * 0.85 * k);
            add = add * (1.0 - saturate(dust * fade) * 0.6);
        }
    }

    // ---- the column of ejecta thrown up round the beam as the land bursts, thinning out -------------------------
    if (burst && bt < 12.0) {
        let He = 40.0 + 300.0 * (1.0 - exp(-bt * 0.9));
        let Re = 30.0 + 40.0 * (1.0 - exp(-bt * 0.6));
        let q = ray_seg(rd, crel, crel + vec3<f32>(0.0, He, 0.0));
        if (q.x < Re * 1.6) {
            let X = rd * q.y - crel;
            let side = dot(X, normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0)));
            let n = gfbm2(vec2<f32>(side / Re * 1.5 + seed, X.y / Re * 0.6 - bt * 0.8));
            // a ragged shell, densest at its edge, its top boiling out
            let shell = exp(-pow((q.x - Re * 0.6) / (Re * 0.5), 2.0)) * (0.4 + 0.9 * n) * smoothstep(He, He * 0.7, X.y);
            let dens = saturate(shell * 1.1) * exp(-max(bt - 5.0, 0.0) / 3.0);
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 1.0, scene_len + 1.0, q.y), !sky);
            let lit = vec3<f32>(0.09, 0.075, 0.065) * (0.3 + 0.7 * day) * (1.0 - 0.5 * dark) + PK_HOT * 0.07 * burn
                + lava_ramp(0.55) * exp(-max(X.y, 0.0) / 25.0) * 0.15;
            col = mix(col, lit, dens * 0.9 * vis * k);
            add = add * (1.0 - dens * 0.5 * vis);
        }
    }

    // ---- the mushroom of smoke climbing over the crater once the nexus has burst there, lit from under ------------
    if (popped) {
        let hc = 70.0 + 480.0 * (1.0 - exp(-mt * 0.2));
        let rx = 60.0 + 240.0 * (1.0 - exp(-mt * 0.28));
        let ry = rx * 0.45;
        let Cc = crel + vec3<f32>(0.0, hc, 0.0);
        let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
        let hy = cross(hx, rd);
        var dens = 0.0;
        var glow = vec3<f32>(0.0);
        // its cap: where the ray passes a flattened ellipsoid (in the space where it is a sphere), its edge billowing
        let sc = vec3<f32>(1.0, rx / ry, 1.0);
        let rs3 = rd * sc;
        let cs3 = Cc * sc;
        let tq = dot(cs3, rs3) / dot(rs3, rs3);
        let m = length(cs3 - rs3 * tq) / rx;
        if (m < 1.3 && tq > 0.0 && (sky || tq - ry < scene_len)) {
            let o = rd * tq - Cc;
            let st = vec2<f32>(dot(o, hx), dot(o, hy)) / rx;
            let n = gfbm2(st * 2.0 + vec2<f32>(seed, -mt * 0.12)) * 0.78 + gfbm2(st * 4.0 + vec2<f32>(mt * 0.1, seed)) * 0.22;
            dens = smoothstep(1.05, 0.5, m + (n - 0.5) * 0.45) * (0.55 + 0.6 * n);
            // the underside lit by the crater, glowing as it boils up, cooling
            let under = smoothstep(0.1, -0.5, st.y);
            // (and lightning flickering inside it now and then, as in a volcano's plume)
            let flick = step(0.82, fh21(vec2<f32>(floor(time * 9.0), seed))) * exp(-pow(length(st - (vec2<f32>(fh21(vec2<f32>(floor(time * 9.0), 3.0)), fh21(vec2<f32>(floor(time * 9.0), 5.0))) - 0.5)) / 0.35, 2.0));
            glow = (lava_ramp(0.4 + 0.35 * n) * under * exp(-mt / 7.0) * 1.1 + PK_HOT * exp(-m * 3.0) * exp(-mt / 1.5) * 0.6 + PK_HOT * flick * 0.9) * dens;
        }
        // its stem, from the crater up into the cap
        let q = ray_seg(rd, crel, Cc - vec3<f32>(0.0, ry * 0.7, 0.0));
        let Rs = (22.0 + 6.0 * mt) * (1.0 + 0.4 * q.z);
        if (q.x < Rs * 1.8 && (sky || q.y < scene_len)) {
            let X = rd * q.y - crel;
            let side = dot(X, hx);
            let n = gfbm2(vec2<f32>(side / Rs * 1.3 + seed + 5.0, X.y / Rs * 0.5 - mt * 0.6));
            let ds_ = smoothstep(1.4, 0.1, q.x / Rs + (n - 0.5) * 0.7) * (0.45 + 0.6 * n) * smoothstep(1.0, 0.6, q.z);
            // (where it runs up into the cap, the cap's lit underside still shows)
            glow = max(glow, lava_ramp(0.45 + 0.3 * n) * exp(-max(X.y, 0.0) / 25.0) * exp(-mt / 6.0) * 1.2 * ds_);
            dens = max(dens, ds_);
        }
        dens = saturate(dens) * after;
        let smoke = vec3<f32>(0.075, 0.07, 0.072) * (0.3 + 0.7 * day) * (1.0 - 0.5 * dark);
        col = mix(col, smoke, dens * 0.93 * k);
        add = add * (1.0 - dens * 0.85) + glow * after * k;
    }

    // ---- the towers' beams: columns straight up, bending over onto the nexus, braided, surges racing along them ----
    for (var i = 0; i < PK_N; i = i + 1) {
        let e = em[i];
        let et = time - e.w;
        if (et <= 0.0) {
            continue;
        }
        let cv = pk_curve(e, NX0, cam, time, i, seed);
        if (cv.u0 >= 1.0) {
            continue;
        }
        // the curve as eight straight stretches: the nearest to the view ray
        var best = vec4<f32>(1.0e9, 0.0, 0.0, 0.0);              // its distance, along the ray, how far along the curve
        var pa = vec3<f32>(0.0);
        var pb = vec3<f32>(0.0);
        var prev = pk_bez(cv, cv.u0);
        for (var j = 1; j <= 8; j = j + 1) {
            let s = mix(cv.u0, cv.u1, f32(j) / 8.0);
            let cur = pk_bez(cv, s);
            let q = ray_seg(rdb, prev, cur);
            let w = max(3.0, q.y * 0.0013);
            if (q.x / w < best.x / max(3.0, best.y * 0.0013)) {
                best = vec4<f32>(q.x, q.y, mix(mix(cv.u0, cv.u1, f32(j - 1) / 8.0), s, q.z), 0.0);
                pa = prev;
                pb = cur;
            }
            prev = cur;
        }
        let rc = (3.0 + 1.0 * charge + 0.8 * burn + 3.0 * select(0.0, exp(-merge_t * 3.0), merged)) * k;
        let w = max(rc, best.y * 0.0013);
        if (best.x > w * 40.0) {
            continue;
        }
        let en = rc / w;
        let occ = pk_occ(best.y, scene_len, sky, cloud);
        let fi = f32(i);
        let len = length(cv.b - cv.a) * 1.3;
        let along = best.z * len;
        // a strand of light either side, wound round it; where along it a point of the ray is nearest
        let dir = normalize(pb - pa + vec3<f32>(1.0e-5));
        let e1 = normalize(cross(dir, select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(dir.y) > 0.9)));
        let e2 = cross(dir, e1);
        let axis = pk_bez(cv, best.z);
        var strands = 0.0;
        for (var s = 0; s < 2; s = s + 1) {
            let ph = along * 0.045 - time * 9.0 + f32(s) * 3.14159265 + fi;
            let hp = axis + (e1 * cos(ph) + e2 * sin(ph)) * (rc * 2.6 + 2.0);
            let th = max(dot(hp, rdb), 0.0);
            let dh = length(hp - rdb * th);
            let wh = max(rc * 0.35, th * 0.0012);
            strands = strands + exp(-pow(dh / wh, 2.0)) * (rc * 0.35 / wh) * pk_occ(th, scene_len, sky, cloud);
        }
        // (from far off, where the braid is too small to make out, only the beam)
        strands = strands * smoothstep(0.02, 0.05, (rc * 2.6 + 2.0) / max(best.y, 1.0));
        let pulse = pow(0.5 + 0.5 * sin(along * 0.012 - time * 26.0 + fi * 1.7), 10.0) * (0.4 + charge) + pow(0.5 + 0.5 * sin(along * 0.015 - time * 41.0 + fi), 14.0) * burn;
        let crackle = 0.75 + 0.5 * gnoise2(vec2<f32>(along * 0.05 - time * 30.0, fi * 7.0));
        let core = exp(-pow(best.x / (w * 0.5), 2.0));
        let sheath = exp(-pow(best.x / (w * 1.6), 2.0)) * crackle;
        let glow = exp(-best.x / (w * 6.0)) * (1.0 - smoothstep(w * 25.0, w * 40.0, best.x));
        // its head blazing as it climbs
        let head = exp(-pow((cv.u1 - best.z) * len / 15.0, 2.0)) * (1.0 - step(1.0, cv.u1));
        let b = PK_WHITE * core * (1.0 + 1.5 * pulse + 3.0 * head) + PK_HOT * sheath * (0.6 + 1.6 * pulse + 2.0 * head) + PK_DEEP * glow * 0.4;
        add = add + (b * en * occ + (PK_HOT * 0.6 + PK_WHITE * 0.1) * strands) * k;
    }

    // ---- the nexus: a star where they meet, rings spinning round it, streaks of light drawn in, arcs over it -------
    let tcn = dot(NX, rd);
    let lum_n = Rn / 14.0;
    if (rings_on > 0.01 && tcn > 0.0) {
        // three rings, each turning on its own tilted axis, faster as it charges, thrown out of true as it shudders
        let Rr = (10.0 + 10.0 * charge + 6.0 * burn) * collapse;
        for (var j = 0; j < 3; j = j + 1) {
            let fj = f32(j);
            let tilt = 0.5 + 0.55 * fj + unstable * 0.7 * sin(time * (23.0 + fj * 7.0));
            let spin = time * (0.6 + 0.5 * fj) * (1.0 + 2.5 * charge) + fj * 2.1;
            let nrm = vec3<f32>(sin(tilt) * cos(spin), cos(tilt), sin(tilt) * sin(spin));
            let e1 = normalize(cross(nrm, vec3<f32>(0.3, 0.1, 0.9)));
            let e2 = cross(nrm, e1);
            let rg = pk_ring(rd, NX, e1, e2, Rr * (1.7 + 0.55 * fj));
            let wr = max(0.9 + 0.3 * charge, rg.y * 0.0012);
            let seg = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(rg.z * 3.0 + time * (6.0 + 3.0 * fj)), 2.0);
            add = add + (PK_HOT + PK_WHITE * 0.15) * exp(-pow(rg.x / wr, 2.0)) * (1.2 / wr) * seg * rings_on * (1.0 + 2.0 * unstable)
                * pk_occ(rg.y, scene_len, sky, cloud) * k;
        }
    }
    if (Rn > 0.01 && tcn > 0.0) {
        let dcn = length(NX - rd * tcn);
        let occ = pk_occ(tcn - Rn, scene_len, sky, cloud);
        let wpx = max(Rn, tcn * 0.0016);
        let en = Rn / wpx;
        let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
        let hy = cross(hx, rd);
        let o = rd * tcn - NX;
        let p2 = vec2<f32>(dot(o, hx), dot(o, hy));
        let ang = atan2(p2.y, p2.x);
        let surf = gfbm2(vec2<f32>(ang * 2.5 + seed, dcn / wpx * 1.5 - time * 3.0));
        let wob = 1.0 + unstable * 0.35 * sin(ang * 5.0 + time * 40.0);
        var star = PK_WHITE * 1.2 * (1.0 - smoothstep(wpx * 0.85, wpx * 1.05, dcn * (0.9 + 0.2 * surf) / wob))
            + PK_HOT * exp(-max(dcn - wpx, 0.0) / (wpx * 0.6)) * (0.8 + 0.8 * surf) * en
            + PK_DEEP * exp(-dcn / (wpx * 4.0)) * 0.8 * en;
        if (dcn < wpx * 4.0 && time < PK_FALL) {
            // arcs of plasma leaping off it
            let tq = floor(time * 16.0);
            var arcs = 0.0;
            for (var j = 0; j < 5; j = j + 1) {
                let aj = fh21(vec2<f32>(f32(j) * 3.1, tq)) * TAU;
                let dj = vec2<f32>(cos(aj), sin(aj));
                let bl = bolt_line(p2, dj * wpx * 0.7, dj * wpx * (2.2 + 1.6 * fh21(vec2<f32>(f32(j), tq + 5.0))), seed + 50.0 + f32(j) * 3.0, tq, wpx * 0.06);
                arcs = arcs + (bl.x + bl.y * 0.3) * step(0.3 - 0.3 * unstable, fh21(vec2<f32>(f32(j) + 9.0, tq)));
            }
            star = star + (PK_WHITE * 0.5 + PK_HOT) * arcs * saturate(fed / 2.0) * (0.6 + charge + burn + 2.0 * unstable) * en;
        }
        if (fall > 0.0) {
            // falling: its trail down the line of the beam
            let q = ray_seg(rd, NX, NX + vec3<f32>(0.0, 120.0 * fall, 0.0));
            let wq = max(2.0, q.y * 0.0013);
            star = star + PK_HOT * exp(-pow(q.x / wq, 2.0)) * (3.0 / wq) * (1.0 - q.z) * fall;
        }
        add = add + star * occ * k;
    }
    if (charge > 0.01 && tcn > 0.0 && length(NX - rd * tcn) < 320.0 && time < PK_DROP) {
        // light drawn in from round it, spiralling in faster as it closes
        for (var j = 0; j < 16; j = j + 1) {
            let fj = f32(j);
            let per = 1.2 + 0.7 * fract(fj * 0.618034);
            let u = fract((time + fract(fj * 0.754878) * per) / per);
            let nr = normalize(vec3<f32>(fract(fj * 0.37) - 0.5, 0.6 + fract(fj * 0.71), fract(fj * 0.53) - 0.5));
            let e1 = normalize(cross(nr, vec3<f32>(0.0, 0.0, 1.0)));
            let e2 = cross(nr, e1);
            let rad = 280.0 * pow(1.0 - u, 1.6) + 3.0;
            let th = fj * 2.4 + u * 7.0;
            let u1 = max(u - 0.05, 0.0);
            let rad1 = 280.0 * pow(1.0 - u1, 1.6) + 3.0;
            let th1 = fj * 2.4 + u1 * 7.0;
            let pa = NX + (e1 * cos(th) + e2 * sin(th)) * rad;
            let pb = NX + (e1 * cos(th1) + e2 * sin(th1)) * rad1;
            let q = ray_seg(rd, pa, pb);
            let wq = max(0.8, q.y * 0.0012);
            add = add + (PK_HOT + PK_WHITE * 0.2 * u) * exp(-pow(q.x / wq, 2.0)) * (0.8 / wq) * u * u * charge * pk_occ(q.y, scene_len, sky, cloud) * k;
        }
    }

    // ---- as they fuse: a ring of fire tearing out through the sky, and the sky cracking open from the nexus -------
    if (merged && merge_t < 6.0) {
        let tp = NX.y / select(rd.y, 1.0e-5, abs(rd.y) < 1.0e-5);
        if (tp > 0.0) {
            let pp = rd * tp;
            let rr = length(pp.xz - NX.xz);
            let ap = atan2(pp.z - NX.z, pp.x - NX.x);
            let R = 1400.0 * (1.0 - exp(-merge_t * 0.9));
            let th = 6.0 + 50.0 * merge_t;
            var ring = (exp(-pow((rr - R) / th, 2.0)) + exp(-pow((rr - R * 0.82) / (th * 0.5), 2.0)) * 0.4) * exp(-merge_t * 0.9)
                * (0.7 + 0.6 * gnoise2(vec2<f32>(ap * 12.0, merge_t)));
            // the cracks: one jagged line out of each of fourteen sectors, running out ahead of the ring
            let sec = floor(ap / (TAU / 14.0));
            let ac = (sec + 0.5 + 0.5 * (fh21(vec2<f32>(sec, seed)) - 0.5)) * TAU / 14.0;
            // (jagged: straight runs between kinks, every 90 blocks and every 25)
            let k1 = rr / 90.0;
            let k2 = rr / 25.0;
            let kink = mix(fh21(vec2<f32>(sec * 7.0 + floor(k1), seed)), fh21(vec2<f32>(sec * 7.0 + floor(k1) + 1.0, seed)), fract(k1)) * 60.0
                + mix(fh21(vec2<f32>(sec * 5.0 + floor(k2), seed + 3.0)), fh21(vec2<f32>(sec * 5.0 + floor(k2) + 1.0, seed + 3.0)), fract(k2)) * 14.0 - 37.0;
            let lat = abs((ap - ac) * rr - kink * smoothstep(40.0, 200.0, rr));
            let wc = 1.5 + rr * 0.002;
            let reach = 1600.0 * (1.0 - exp(-merge_t * 2.5));
            ring = ring + exp(-pow(lat / wc, 2.0)) * smoothstep(reach, reach - 200.0, rr) * smoothstep(20.0, 60.0, rr) * exp(-merge_t * 1.8) * 1.6;
            let wfar = max(1.0, tp * 0.002);
            add = add + (PK_HOT + PK_WHITE * 0.15) * ring * min(1.0, 30.0 / wfar) * pk_occ(tp, scene_len, sky, cloud) * k;
        }
    }

    // the guide: a pencil-thin thread from the nexus to the target in the moments before it fires
    if (time > 2.6 && time < PK_DROP) {
        let q = ray_seg(rdb, NX, crel);
        let w = max(0.15, q.y * 0.001);
        add = add + PK_HOT * exp(-pow(q.x / w, 2.0)) * (0.2 / w) * smoothstep(2.6, 3.4, time) * (0.7 + 0.3 * sin(time * 60.0))
            * pk_occ(q.y, scene_len, sky, cloud) * k;
    }

    // ---- the beam: down from the nexus onto the target, a white core inside a blue sheath, strands wound round it ----
    if (burn > 0.001) {
        let G = crel - vec3<f32>(0.0, 14.0, 0.0);
        let u_head = saturate((time - PK_DROP) / (PK_HIT - PK_DROP));
        let u_top = saturate((time - PK_CUT - PK_DRAIN * 0.5) / 0.4);
        let A = NX + (G - NX) * u_top;
        let B = NX + (G - NX) * u_head;
        let q = ray_seg(rdb, A, B);
        let lenb = length(G - NX);
        let qz = mix(u_top, u_head, q.z);
        let along = qz * lenb;
        let hgt = NX.y + (G.y - NX.y) * qz - crel.y;
        var rc = (11.0 + 1.2 * sin(time * 23.0) + 0.9 * sin(time * 37.0 + 1.0)) * (1.0 + 0.6 * exp(-max(hit_t, 0.0) * 2.0));
        rc = rc * (1.0 + 0.5 * exp(-max(hgt, 0.0) / 12.0)) * k;
        let w = max(rc, q.y * 0.0013);
        let e = rc / w;
        let dd = q.x;
        if (dd < w * 40.0) {
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.8, scene_len + 0.8, q.y), !sky);
            let vis_mix = mix(0.15, 1.0, vis);
            let bdir = (G - NX) / max(lenb, 1.0e-3);
            let e1 = normalize(cross(bdir, vec3<f32>(1.0, 0.0, 0.0)));
            let e2 = cross(bdir, e1);
            let ofs = rdb * q.y - (A + (B - A) * q.z);
            let ang = atan2(dot(ofs, e2), dot(ofs, e1));
            let n1 = gnoise2(vec2<f32>(ang * 1.6, along * 0.04 - time * 18.0));
            let n2 = gnoise2(vec2<f32>(ang * 2.3 + 7.0, along * 0.09 - time * 25.0));
            // surges racing down it, three strands wound round it
            let pulse = pow(0.5 + 0.5 * sin(along * 0.03 - time * 60.0), 6.0);
            let core = exp(-pow(dd / (w * 0.42), 2.0));
            let inner = exp(-pow(dd / (w * 1.2), 2.0)) * (0.6 + 0.8 * n1);
            let outer = exp(-pow(dd / (w * 2.6), 2.0)) * (0.4 + 0.9 * n2);
            let halo = (exp(-dd / (rc * 4.0)) + exp(-dd / (rc * 14.0)) * 0.12) * (1.0 - smoothstep(w * 25.0, w * 40.0, dd));
            var strands = 0.0;
            let axis = A + (B - A) * q.z;
            for (var s = 0; s < 3; s = s + 1) {
                let ph = along * 0.03 + time * 7.0 + f32(s) * TAU / 3.0;
                let hp = axis + (e1 * cos(ph) + e2 * sin(ph)) * rc * 1.7;
                let th = max(dot(hp, rdb), 0.0);
                let wh = max(rc * 0.18, th * 0.0012);
                strands = strands + exp(-pow(length(hp - rdb * th) / wh, 2.0)) * (rc * 0.18 / wh) * select(1.0, 1.0 - smoothstep(scene_len - 0.8, scene_len + 0.8, th), !sky);
            }
            var b = (PK_WHITE * core * (1.0 + 0.6 * pulse) + PK_HOT * inner * (0.28 + 0.6 * pulse) + PK_DEEP * outer * 0.4) * e;
            // the head of it, blazing, on its way down
            b = b + PK_WHITE * exp(-pow((q.z - 1.0) * (u_head - u_top) * lenb / 10.0, 2.0)) * core * 1.5 * (1.0 - step(1.0, u_head));
            add = add + (b * vis + halo * PK_DEEP * 0.12 * e * vis_mix + (PK_HOT * 0.8 + PK_WHITE * 0.15) * strands * 1.5) * burn * k;
        }
        // the fireball where the land burst, boiling; it settles round the foot of the beam
        if (burst) {
            let Rf = (45.0 + 80.0 * exp(-bt * 0.6) * (1.0 - exp(-bt * 6.0))) * (0.93 + 0.07 * sin(time * 13.0));
            let cf = crel + vec3<f32>(0.0, Rf * 0.25, 0.0);
            let tcp = dot(cf, rd);
            // (a dome, flattened against the land)
            let dc = length((rd * max(tcp, 0.0) - cf) * vec3<f32>(1.0, 1.7, 1.0));
            if (dc < Rf * 4.0) {
                let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
                let hy = cross(hx, rd);
                let on = rd * tcp - cf;
                let ang = atan2(dot(on, hy), dot(on, hx));
                let nz = gfbm2(vec2<f32>(ang * 1.3 + seed, dc / Rf * 2.0 - time * 2.5));
                let fire = exp(-pow(dc / (Rf * (0.75 + 0.5 * nz)), 2.0));
                // plasma, white-hot at its heart, the land burning orange under it, a crust of smoke round its edge
                let heat = fire * (0.4 + 0.6 * exp(-dc / (Rf * 0.3)));
                let low = exp(-max((rd * max(tcp, 0.0) - crel).y, 0.0) / 12.0);
                let visf = select(1.0, smoothstep(tcp - Rf * 1.3, tcp - Rf * 0.2, scene_len), !sky);
                col = mix(col, vec3<f32>(0.04, 0.04, 0.05), smoothstep(0.05, 0.5, fire) * (1.0 - heat) * 0.6 * visf * burn * k);
                add = add + (PK_WHITE * 0.25 * heat * heat + PK_HOT * 0.45 * heat * (1.0 + 0.6 * nz) + PK_DEEP * fire * 0.3
                    + lava_ramp(0.45 + 0.5 * heat) * fire * low * 1.4) * visf * burn * k;
                add = add + vec3<f32>(1.2, 1.2, 1.6) * exp(-dc / Rf) * 0.12 * (1.0 - smoothstep(Rf * 2.5, Rf * 4.0, dc)) * burn * visf * k;
            }
        }
    }

    // ---- the nexus bursting in the crater: a ball of fire and plasma swelling out of it, the mushroom climbing out of it --
    if (popped && mt < 3.0) {
        let Rp = (30.0 + 90.0 * (1.0 - exp(-mt * 3.0))) * (0.95 + 0.05 * sin(time * 17.0));
        let cf = crel + vec3<f32>(0.0, Rp * 0.3 + 40.0 * mt, 0.0);
        let tcp = dot(cf, rd);
        let dc = length((rd * max(tcp, 0.0) - cf) * vec3<f32>(1.0, 1.3, 1.0));
        if (dc < Rp * 2.0) {
            let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
            let on = rd * tcp - cf;
            let nz = gfbm2(vec2<f32>(atan2(dot(on, cross(hx, rd)), dot(on, hx)) * 1.4 + seed, dc / Rp * 2.0 - time * 2.0));
            let fire = exp(-pow(dc / (Rp * (0.7 + 0.5 * nz)), 2.0)) * exp(-mt / 1.2);
            let visf = select(1.0, smoothstep(tcp - Rp * 1.3, tcp - Rp * 0.2, scene_len), !sky);
            add = add + (lava_ramp(0.35 + 0.6 * fire) * fire * 2.4 + PK_HOT * fire * fire * 1.5 * exp(-mt * 2.0)) * visf * k;
        }
    }

    // ---- debris spiralling up round the beam, and molten rock thrown out of the crater, the crater still erupting ----
    let sp_q = ray_seg(rd, crel, crel + vec3<f32>(0.0, 200.0, 0.0));
    if (burst && sp_q.x < 220.0) {
        for (var j = 0; j < 30; j = j + 1) {
            // each one thrown again and again, a new way each time
            let fj = f32(j);
            let life = 2.2 + 1.6 * fract(fj * 0.618034);
            let ph = fract(fj * 0.754878) * life;
            let gen = floor((time + ph) / life);
            let tb = gen * life - ph;                               // when this one was thrown
            let a = time - tb;
            let erupting = tb > PK_CUT && fract(fj * 0.31) > 0.6;   // (after the beam, a few: the crater still erupting)
            if (tb < PK_BURST || (tb > PK_CUT && !erupting) || tb > PK_END - 4.0) {
                continue;
            }
            let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), u32(gen), u32(seed)))) * (1.0 / 4294967295.0);
            var pa = vec3<f32>(0.0);
            var pb = vec3<f32>(0.0);
            if (j % 2 == 0 && tb < PK_CUT) {
                // round the beam: orbiting it and climbing
                let rr = 18.0 + 30.0 * hv.x;
                let w0 = (1.2 + 1.5 * hv.y) * select(-1.0, 1.0, hv.z > 0.5);
                let vy = 25.0 + 35.0 * hv.z;
                let a1 = max(a - 0.08, 0.0);
                pa = crel + vec3<f32>(cos(hv.y * TAU + w0 * a) * rr, vy * a, sin(hv.y * TAU + w0 * a) * rr);
                pb = crel + vec3<f32>(cos(hv.y * TAU + w0 * a1) * rr, vy * a1, sin(hv.y * TAU + w0 * a1) * rr);
            } else {
                let az = hv.x * TAU;
                let vh = 15.0 + 40.0 * hv.y;
                let vy = 25.0 + 40.0 * hv.z;
                let s3 = crel + vec3<f32>(cos(az) * 12.0, 2.0, sin(az) * 12.0);
                let a1 = max(a - 0.07, 0.0);
                pa = s3 + vec3<f32>(cos(az) * vh * a, vy * a - 16.0 * a * a, sin(az) * vh * a);
                pb = s3 + vec3<f32>(cos(az) * vh * a1, vy * a1 - 16.0 * a1 * a1, sin(az) * vh * a1);
                if (pa.y + cam.y < tgt.y - 20.0) {
                    continue;
                }
            }
            let qj = ray_seg(rd, pa, pb);
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 0.4, scene_len + 0.4, qj.y), !sky);
            if (j % 3 == 0) {
                // a chunk of the land, dark against the light
                let w = 0.8 + 1.2 * hv.y;
                col = mix(col, vec3<f32>(0.04, 0.035, 0.03), exp(-pow(qj.x / max(w, qj.y * 0.0012), 4.0)) * (w / max(w, qj.y * 0.0012)) * vis);
                add = add * (1.0 - exp(-pow(qj.x / max(w, qj.y * 0.0012), 4.0)) * vis * 0.8);
            } else {
                let w = max(0.4, qj.y * 0.0012);
                add = add + mix(vec3<f32>(4.0, 3.4, 2.6), vec3<f32>(2.6, 0.7, 0.12), saturate(a / life)) * exp(-pow(qj.x / w, 2.0)) * (0.4 / w) * (1.0 - a / life) * vis * k;
            }
        }
    }

    // ---- the shock dome: the blast front in the air, a shell bending the light, lit at its edge -----------------
    if (burst && bt < 3.0) {
        let Rs = 60.0 + 220.0 * pow(bt, 0.8);
        let tcs = dot(crel, rd);
        let ps = rd * max(tcs, 0.0) - crel;
        let dcs = length(ps);
        let th = 4.0 + 10.0 * bt;
        let wpx = max(th, max(tcs, 1.0) * 0.002);
        let limb = exp(-pow((dcs - Rs) / wpx, 2.0)) * (th / wpx) * smoothstep(-5.0, 10.0, ps.y);
        add = add + (PK_HOT * 0.25 + vec3<f32>(0.5, 0.55, 0.6)) * limb * exp(-bt * 1.3) * pk_occ(tcs, scene_len, sky, cloud) * k;
    }

    // ---- the lens: bloom round the nexus and the beam's foot, a long streak through the nexus --------------------
    if (pN.z > 0.0 && Rn > 0.01) {
        let dd = (uv - pN.xy) * vec2<f32>(aspect, 1.0);
        let l = lum_n * (0.6 + 0.5 * charge + 0.6 * burn) + select(0.0, exp(-merge_t * 3.0) * 3.0, merged);
        add = add + PK_HOT * l / (1.0 + dot(dd, dd) * 300.0) * 0.35 * k;
        add = add + PK_HOT * exp(-abs(dd.y) * 300.0) * exp(-abs(dd.x) * 1.6) * l * 0.5 * k;
    }
    if (pT.z > 0.0 && (burn > 0.001 || (popped && mt < 2.0))) {
        let dd = (uv - pT.xy) * vec2<f32>(aspect, 1.0);
        let l = burn + select(0.0, exp(-mt * 2.0) * 2.0, popped);
        add = add + vec3<f32>(1.2, 1.6, 2.6) * l / (1.0 + dot(dd, dd) * 400.0) * 0.25 * k;
        add = add + PK_HOT * exp(-abs(dd.y) * 260.0) * exp(-abs(dd.x) * 3.0) * l * 0.35 * k;
    }
    add = add + vec3<f32>(2.2, 2.5, 3.2) * flash * flash * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.3 * dark) * k);
    outc = aces(outc * 0.9);
    let srgb = linear_to_srgb(outc);
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
    return planet_killer(in);
}
