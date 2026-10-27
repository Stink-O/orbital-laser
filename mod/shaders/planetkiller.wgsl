// Orbital Laser's post pass for the Planet Killer (laser 6). Like the Downfall's, the mod builds it from
// shaders/strike.wgsl up to its fs_main (the helpers: the noise, ray_seg, bolt_line, lava_ramp, project_rel, mh) less the
// other lasers' own functions, followed by this file, and sets it for a planet killer strike only, so its size costs the
// other lasers nothing. Validate with tools/check-shader.sh.

// ---- laser 6: the planet killer -----------------------------------------------------------------------------------
// Seven towers grind up out of the land far out round the horizon, one after another, dark against a sky going dark:
// each one's ground heaves and splits, light leaking up through it; the tower breaks the surface and struggles there,
// straining, catching, shuddering, leaning, then bursts up out of it in a surge of dust, a column of earth climbing with
// it. Each crown crackles and fires a bolt of lightning at a ring of light forming high over the target: it feels its
// way out in steps, branching, then runs the rest of the way and strikes the ring, lighting the land and the sky, and
// holds the jagged path it took, trembling, struck again now and then. The ring lights up from where each bolt strikes
// it, round to the next, until it is whole, a band of plasma with lightning crawling over it; it shudders, tightens and
// fills with light, and they fuse: a flash, a ring of light tearing out through the sky, the sky cracking and the clouds
// blown open. A bolt feels its way down to the target, streamers reaching up to meet it, and the beam pours down it.
// The land under it domes up, cracking with light, and bursts: a fireball, a column of ejecta, a shock running out
// through the land and a wall of dust, debris spiralling up round the beam, the crater molten and fissures running out
// from it pulsing with light. Then the bolts stutter out and the towers go dark and sink; the ring crushes in to a
// point, drops into the crater and bursts again, and a mushroom cloud climbs over the crater as the daylight comes back.
// strike.rs times the same strike, digs the same crater and opens the same fissures (pk_crack): keep the PK_* and pk_*
// in step.

const PK_N: i32 = 7;               // the towers
const PK_H: f32 = 300.0;           // the ring their beams feed, its middle this high over the target,
const PK_RING_R: f32 = 220.0;      // this wide, tightening to PK_RING_T as they fuse,
const PK_RING_T: f32 = 150.0;
const PK_RING_TILT: f32 = 0.22;    // its face tipped this far towards the player, so it reads from the ground,
const PK_RING_V: f32 = 2.6;        // and lit round from each beam at this many radians a second
const PK_SRC_R: f32 = 1100.0;      // how far out the towers stand
const PK_TOWER_H: f32 = 420.0;     // how tall they stand, and how wide at the foot
const PK_TOWER_R: f32 = 62.0;
const PK_BULGE: f32 = 0.7;         // the ground over a tower heaves and splits for this long,
const PK_STRUGGLE: f32 = 1.1;      // then it breaks the surface and struggles there (straining, catching, shuddering),
const PK_THRUST: f32 = 0.8;        // then bursts up out of it, risen this long after,
const PK_RAISE: f32 = 2.25;        // and settled, and fires, this long after it broke the surface:
const PK_IGN0: f32 = 3.05;         // the first (its ground starting to heave as the strike starts), the last by PK_IGN1
const PK_IGN1: f32 = 5.45;
const PK_CREEP: f32 = 1.0;         // its bolt feels its way out from its crown for this long, then runs the rest of the
const PK_SHOOT: f32 = 1.14;        // way, striking the ring this long after it fires
const PK_SHAKE: f32 = 6.9;         // the ring shudders and tightens from here
const PK_MERGE: f32 = 7.6;         // keep in step with strike.rs: PK_IGN*, PK_BULGE, PK_STRUGGLE, PK_THRUST, PK_RAISE, PK_SHOOT,
const PK_DROP: f32 = 8.4;          // PK_MERGE, PK_DROP, PK_HIT, PK_BURST, PK_CUT, PK_POP, the crater's and the cracks'
const PK_HIT: f32 = 8.5;           // a bolt feels its way down from the ring to the target, the beam pours down it and lands,
const PK_BURST: f32 = 9.0;         // the ground domes up, and bursts
const PK_CUT: f32 = 17.65;         // the towers cut out
const PK_DRAIN: f32 = 0.4;         // their bolts dying over this long, all gone before the ring falls
const PK_FALL: f32 = 18.15;        // it drops into the crater,
const PK_POP: f32 = 18.55;         // and bursts there
const PK_END: f32 = 28.15;         // the daylight is back (the strike runs 30.5 s)
const PK_BLAST: f32 = 340.0;       // the land flattened out to here, PK_ABOVE up
const PK_ABOVE: f32 = 24.0;
const PK_BOWL: f32 = 240.0;        // the crater (strike.rs's pk_depth0): PK_BOWL round, its walls dropping PK_WALL_D from
const PK_FLOOR: f32 = 145.0;       // its edge in to PK_FLOOR, its floor sagging PK_SAG more in to the open shaft, PK_SHAFT
const PK_WALL_D: f32 = 60.0;       // round, down to bedrock (PK_SHAFT_D under a target at sea level)
const PK_SAG: f32 = 20.0;
const PK_SHAFT: f32 = 40.0;
const PK_SHAFT_D: f32 = 123.0;
const PK_CORE: f32 = 64.0;         // dug from PK_DIG0 after the burst at PK_RATE blocks a second, from the middle out: the
const PK_DIG0: f32 = 2.0;          // core (with the land over it), then the land over the rest out to PK_LAND, then the rest
const PK_RATE: f32 = 1500000.0;    // (pk_dig_t)
const PK_LAND: f32 = 268.0;
const PK_CRACKS: i32 = 12;         // the fissures: from PK_RIM out, PK_SEG-block segments, opening at PK_CRACK_V blocks a
const PK_RIM: f32 = 236.0;         // second from PK_CRACK_T after the burst
const PK_SEG: f32 = 12.0;
const PK_CRACK_V: f32 = 90.0;
const PK_CRACK_T: f32 = 0.9;
// The beams' light: a searing white core in an electric blue, a deep cobalt glow round it.
const PK_WHITE: vec3<f32> = vec3<f32>(7.0, 8.0, 10.0);
const PK_HOT: vec3<f32> = vec3<f32>(0.9, 2.2, 6.0);
const PK_DEEP: vec3<f32> = vec3<f32>(0.08, 0.22, 1.8);
const PK_ARC: vec3<f32> = vec3<f32>(0.55, 0.75, 2.4);       // the glow round the bolts, bluer and more violet

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
    return vec2<f32>(a, 110.0 + 50.0 * mh(u32(i), s, 23u));
}
fn pk_crack_off(i: i32, j: i32, seed: f32) -> f32 {
    return select((mh(u32(i * 32 + j), u32(seed), 24u) - 0.5) * 0.12, 0.0, j == 0);
}

// How deep the crater is `r` out from its middle, smoothly (strike.rs's pk_depth0), and the ground dug out of it within
// `r` (pk_vol).
fn pk_depth0(r: f32) -> f32 {
    if (r < PK_SHAFT) {
        return PK_SHAFT_D;
    }
    if (r < PK_FLOOR) {
        return PK_WALL_D + PK_SAG * (PK_FLOOR - r) / (PK_FLOOR - PK_SHAFT);
    }
    let u = saturate((r - PK_FLOOR) / (PK_BOWL - PK_FLOOR));
    return PK_WALL_D * (1.0 - u * u);
}
fn pk_vol(r: f32) -> f32 {
    let w = PK_BOWL - PK_FLOOR;
    let rs = min(r, PK_SHAFT);
    var v = 3.14159265 * rs * rs * PK_SHAFT_D;
    if (r > PK_SHAFT) {
        let rf = min(r, PK_FLOOR);
        let k = PK_SAG / (PK_FLOOR - PK_SHAFT);
        v = v + TAU * ((PK_WALL_D + k * PK_FLOOR) * (rf * rf - PK_SHAFT * PK_SHAFT) * 0.5 - k * (rf * rf * rf - PK_SHAFT * PK_SHAFT * PK_SHAFT) / 3.0);
    }
    if (r > PK_FLOOR) {
        let u = min((r - PK_FLOOR) / w, 1.0);
        v = v + TAU * PK_WALL_D * w * (PK_FLOOR * (u - u * u * u / 3.0) + w * (u * u * 0.5 - u * u * u * u * 0.25));
    }
    return v;
}
// When the crater `r` out is dug (strike.rs's pk_dig_t): the core with the land over it, then, once the land over the rest
// is cleared, the rest, from the middle out.
fn pk_dig_t(r: f32) -> f32 {
    let rc = min(r, PK_CORE);
    let core = PK_BURST + PK_DIG0 + (3.14159265 * rc * rc * PK_ABOVE + pk_vol(rc)) / PK_RATE;
    if (r <= PK_CORE) {
        return core;
    }
    return core + 3.14159265 * (PK_LAND * PK_LAND - PK_CORE * PK_CORE) * PK_ABOVE / PK_RATE + (pk_vol(r) - pk_vol(PK_CORE)) / PK_RATE;
}

// How far the land at `rel2` (from the target, `r` out) has really been opened by `time`: the crater as strike.rs digs
// it, from the middle out (pk_dig_t), its edge wandering round it as pk_depth's does and a little ragged, soft. Nothing
// over the land not dug yet.
fn pk_open(rel2: vec2<f32>, r: f32, time: f32, seed: f32) -> f32 {
    let ang = atan2(rel2.y, rel2.x);
    let w = gnoise2(vec2<f32>(cos(ang), sin(ang)) * 4.4 + vec2<f32>(seed * 0.37, 11.0)) - 0.5;
    let rag = gnoise2(rel2 * 0.06 + vec2<f32>(seed, 3.0)) - 0.5;
    let edge = PK_BOWL * (1.0 + 0.14 * w) + 10.0 * rag;
    let inside = 1.0 - smoothstep(edge - 8.0, edge + 2.0, r);
    let front = time - pk_dig_t(max(r + 14.0 * rag, 0.0));
    return inside * smoothstep(0.0, 0.8, front);
}

// How far the blast's shock front has run out `t` after the land burst, and the second one `t` after the nexus burst:
// fast out, slowing as it spreads.
fn pk_shock_r(t: f32) -> f32 {
    return 90.0 + 820.0 * (1.0 - exp(-t * 0.55));
}
fn pk_pop_r(t: f32) -> f32 {
    return 30.0 + 540.0 * (1.0 - exp(-t * 0.6));
}
// How far a fissure's split has run out past PK_RIM `t` after the burst (strike.rs's pk_crack_time turned round): in
// jerks, four a second, each a lurch forward that eases to a stop, keeping to PK_CRACK_V on the whole.
fn pk_crack_front(t: f32) -> f32 {
    let q = max(t - PK_CRACK_T, 0.0) * 4.0;
    return (floor(q) + smoothstep(0.0, 0.35, fract(q))) / 4.0 * PK_CRACK_V;
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

// The colour of the beams' and the ring's light by how hot it is (0 to 1 and over): a deep blue haze, an electric
// blue, cyan, then white.
fn pk_heat(h: f32) -> vec3<f32> {
    var c = mix(vec3<f32>(0.02, 0.05, 0.45), vec3<f32>(0.12, 0.45, 3.0), smoothstep(0.0, 0.35, h));
    c = mix(c, vec3<f32>(0.7, 2.8, 5.2), smoothstep(0.3, 0.7, h));
    return mix(c, vec3<f32>(6.5, 7.8, 9.5), smoothstep(0.65, 1.0, h));
}

// A band of light round C (camera-relative) at radius R in the plane with normal n, `w` blocks wide (at least a pixel
// or so): met where the view ray crosses the plane, widened as the plane turns edge on so it never thins to nothing.
// x how bright, y how far along the ray, z where round it (radians, from e1 towards e2).
fn pk_band(rd: vec3<f32>, C: vec3<f32>, e1: vec3<f32>, e2: vec3<f32>, R: f32, w: f32) -> vec3<f32> {
    let n = cross(e1, e2);
    let dn = dot(rd, n);
    let tp = dot(C, n) / select(dn, 1.0e-4, abs(dn) < 1.0e-4);
    if (tp <= 0.0) {
        return vec3<f32>(0.0);
    }
    let X = rd * tp - C;
    let ww = max(w, tp * 0.0013) / max(abs(dn), 0.12);
    return vec3<f32>(exp(-pow((length(X) - R) / ww, 2.0)) * (w / max(w, tp * 0.0013)), tp, atan2(dot(X, e2), dot(X, e1)));
}

// A tower, in its own frame (y up from its bottom, PK_TOWER_H tall): a stepped hexagonal plinth splayed into the ground,
// three buttresses flying up off its corners, a shaft in six tiers narrowing up it with a heavy collar under each joint
// and ribs up its corners, a neck, a ring plate round it, and four claws curling up round the emitter at its crown under
// a spire. Its distance (a little under, so marching it never oversteps), and what it is made of there: 0 the hull,
// 1 a collar or a rib, 2 the crown, 3 a buttress, 5 the emitter.
const PK_T0: f32 = 64.0;            // the shaft, from the plinth's top
const PK_T1: f32 = 336.0;           // to the neck,
const PK_TIER: f32 = 45.333;        // in six tiers
const PK_TB: f32 = 136.0;           // and all of it (and the broken ground heaped round its foot) within this of its axis
const PK_CORE_Y: f32 = 397.0;       // where the emitter is

// A hexagon's distance, `a` from its middle to the middle of a side (its corners on +-x).
fn pk_hex(p: vec2<f32>, a: f32) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735027);
    var q = abs(p);
    q = q - 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
    q = q - vec2<f32>(clamp(q.x, -k.z * a, k.z * a), a);
    return length(q) * sign(q.y);
}
// p turned into the first of n sectors round the axis (the first centred `off` round from +x).
fn pk_fold(p: vec2<f32>, n: f32, off: f32) -> vec2<f32> {
    let s = TAU / n;
    let a = atan2(p.y, p.x) - off;
    let b = a - s * floor(a / s + 0.5);
    return vec2<f32>(cos(b), sin(b)) * length(p);
}
fn pk_cone(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, ra: f32, rb: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h) - mix(ra, rb, h);
}
// The shaft's half-width at height y, before its tiers.
fn pk_shaft_a(y: f32) -> f32 {
    let u = saturate((y - PK_T0) / (PK_T1 - PK_T0));
    return mix(46.0, 19.0, u * (0.55 + 0.45 * u));
}
// How far the tower being marched has risen, and how high the broken ground is heaped round its foot (0 to 1).
var<private> pk_lift_g: f32;
var<private> pk_heap_g: f32;
fn pk_tsdf(p: vec3<f32>) -> vec2<f32> {
    let y = p.y;
    // the plinth, in three steps, run down into the ground
    let pa = mix(76.0, 60.0, saturate(y / PK_T0)) - 7.0 * smoothstep(20.0, 22.0, y) - 6.0 * smoothstep(42.0, 44.0, y);
    var d = max(pk_hex(p.xz, pa) * 0.9, max(-60.0 - y, y - PK_T0));
    var m = 0.0;
    // the shaft, each tier narrowing up its height
    let ti = clamp(floor((y - PK_T0) / PK_TIER), 0.0, 5.0);
    let tt = (y - PK_T0) / PK_TIER - ti;
    let a = pk_shaft_a(y) * (1.04 - 0.08 * tt);
    // (every other tier turned a twelfth of the way round, so its corners stand over the faces under it)
    let tw = select(0.0, 0.5235988, ti - 2.0 * floor(ti * 0.5) > 0.5);
    let pr = vec2<f32>(cos(tw) * p.x + sin(tw) * p.z, -sin(tw) * p.x + cos(tw) * p.z);
    d = min(d, max(pk_hex(pr, a), max(PK_T0 - 2.0 - y, y - PK_T1)));
    // a collar under each joint
    let yj = PK_T0 + clamp(round((y - PK_T0) / PK_TIER), 1.0, 5.0) * PK_TIER;
    let dc = max(length(p.xz) - pk_shaft_a(yj) * 1.12 - 5.0, abs(y - yj + 1.0) - 3.5);
    if (dc < d) {
        d = dc;
        m = 1.0;
    }
    // ribs up its corners
    let q6 = pk_fold(pr, 6.0, 0.0);
    let dr = max(max(abs(q6.y) - 1.8, q6.x - a * 1.1547 - 3.5), max(PK_T0 - y, y - PK_T1 + 30.0));
    if (dr < d) {
        d = dr;
        m = 1.0;
    }
    // the three buttresses off the plinth's corners
    let q3 = pk_fold(p.xz, 3.0, 0.0);
    let df = max(max(abs(q3.y) - 4.5, (q3.x + 0.38 * y - 104.0) * 0.935), max(-60.0 - y, y - 236.0));
    if (df < d) {
        d = df;
        m = 3.0;
    }
    // the ground round its foot, broken and heaped up round it as it burst out (not risen with it)
    if (pk_heap_g > 0.0) {
        let rr = length(p.xz);
        let yg = y - PK_TOWER_H + pk_lift_g;
        let hh = pk_heap_g * (16.0 * exp(-pow((rr - 82.0) / 26.0, 2.0)) + 7.0 * exp(-pow((rr - 112.0) / 14.0, 2.0)))
            * (0.6 + 0.8 * gnoise2(p.xz * 0.09)) - 2.0;
        let dm = max((yg - hh) * 0.45, rr - PK_TB + 2.0);
        if (dm < d) {
            d = dm;
            m = 6.0;
        }
    }
    // the crown
    if (y > PK_T1 - 24.0) {
        let dn = max(pk_hex(p.xz, 14.0), max(PK_T1 - 4.0 - y, y - 360.0));
        let dh = max(abs(y - 352.0) - 2.2, abs(length(p.xz) - 31.0) - 9.0);
        let q4 = pk_fold(p.xz, 4.0, 0.7853982);
        let qc = vec3<f32>(q4.x, y, q4.y);
        let dk = min(pk_cone(qc, vec3<f32>(15.0, 346.0, 0.0), vec3<f32>(37.0, 380.0, 0.0), 6.0, 4.0),
            pk_cone(qc, vec3<f32>(37.0, 380.0, 0.0), vec3<f32>(13.0, 416.0, 0.0), 4.0, 1.2));
        let dsp = pk_cone(p, vec3<f32>(0.0, 352.0, 0.0), vec3<f32>(0.0, 420.0, 0.0), 5.0, 0.8);
        let dcr = min(min(dn, dh), min(dk, dsp));
        if (dcr < d) {
            d = dcr;
            m = 2.0;
        }
        let de = length(p - vec3<f32>(0.0, PK_CORE_Y, 0.0)) - 8.5;
        if (de < d) {
            d = de;
            m = 5.0;
        }
    }
    return vec2<f32>(d, m);
}
// A point (camera-relative) in the frame of the tower whose foot is at S (camera-relative, on the ground), risen `lift`
// out of the land, leaning by `lean` (sheared about the ground), turned `rot` about its axis.
fn pk_tlocal(X: vec3<f32>, S: vec3<f32>, lift: f32, lean: vec2<f32>, rot: f32) -> vec3<f32> {
    let rel = X - S;
    let xz = rel.xz - lean * rel.y;
    let c = cos(rot);
    let s = sin(rot);
    return vec3<f32>(c * xz.x - s * xz.y, rel.y + PK_TOWER_H - lift, s * xz.x + c * xz.y);
}
// The view ray against the tower (S, lift, lean, rot as pk_tlocal), up to `tmax`: x how far along it (under 0 if it
// misses), y what it is made of there. Marched from where the ray enters the upright cylinder round it.
fn pk_tower(S: vec3<f32>, lift: f32, lean: vec2<f32>, rot: f32, rd: vec3<f32>, tmax: f32) -> vec2<f32> {
    let o = -S.xz + lean * S.y;
    let v = rd.xz - lean * rd.y;
    let a = max(dot(v, v), 1.0e-8);
    let b = dot(o, v);
    let disc = b * b - a * (dot(o, o) - PK_TB * PK_TB);
    if (disc <= 0.0) {
        return vec2<f32>(-1.0);
    }
    var t0 = (-b - sqrt(disc)) / a;
    var t1 = (-b + sqrt(disc)) / a;
    // (from a little under its foot, the ground there not always level, to its tip)
    let ylo = S.y - 30.0;
    let yhi = S.y + lift + 2.0;
    if (abs(rd.y) > 1.0e-5) {
        t0 = max(t0, min(ylo / rd.y, yhi / rd.y));
        t1 = min(t1, max(ylo / rd.y, yhi / rd.y));
    }
    t0 = max(t0, 0.0);
    t1 = min(t1, tmax);
    if (t1 <= t0) {
        return vec2<f32>(-1.0);
    }
    var t = t0;
    for (var k = 0; k < 80; k = k + 1) {
        let h = pk_tsdf(pk_tlocal(rd * t, S, lift, lean, rot));
        if (h.x < max(0.05, t * 0.0009)) {
            return vec2<f32>(t, h.y);
        }
        t = t + h.x * 0.8;
        if (t > t1) {
            break;
        }
    }
    return vec2<f32>(-1.0);
}
// The tower's surface's normal at q (in its frame).
fn pk_tnormal(q: vec3<f32>, e: f32) -> vec3<f32> {
    let k = vec2<f32>(1.0, -1.0);
    return normalize(k.xyy * pk_tsdf(q + k.xyy * e).x + k.yyx * pk_tsdf(q + k.yyx * e).x + k.yxy * pk_tsdf(q + k.yxy * e).x
        + k.xxx * pk_tsdf(q + k.xxx * e).x);
}

fn pk_ease(a: f32, b: f32, x: f32) -> f32 {
    let y = 1.0 - saturate(x);
    return mix(a, b, 1.0 - y * y);
}
fn pk_jolt(s: f32, at: f32, k: f32) -> f32 {
    return select(0.0, exp(-(s - at) * k), s > at);
}
// A tower `s` seconds after it breaks the surface: x how far it has risen (of its height), y how hard it shudders
// (blocks). It punches through, strains against the ground barely moving, gives a little and catches, grinds on, gives
// again and catches, gathers itself, shaking harder and harder, then bursts up out of it, carried a little past its
// height, and settles.
fn pk_rise(s: f32) -> vec2<f32> {
    if (s <= 0.0) {
        return vec2<f32>(0.0);
    }
    var h = 0.162;
    if (s < 0.12) {
        h = pk_ease(0.0, 0.055, s / 0.12);
    } else if (s < 0.38) {
        h = mix(0.055, 0.066, (s - 0.12) / 0.26);
    } else if (s < 0.45) {
        h = pk_ease(0.066, 0.104, (s - 0.38) / 0.07);
    } else if (s < 0.52) {
        h = mix(0.104, 0.097, smoothstep(0.45, 0.52, s));
    } else if (s < 0.76) {
        h = mix(0.097, 0.118, (s - 0.52) / 0.24);
    } else if (s < 0.82) {
        h = pk_ease(0.118, 0.17, (s - 0.76) / 0.06);
    } else if (s < 0.9) {
        h = mix(0.17, 0.162, smoothstep(0.82, 0.9, s));
    } else if (s >= PK_STRUGGLE) {
        let x = (s - PK_STRUGGLE) / PK_THRUST;
        if (x < 1.0) {
            h = mix(0.162, 1.035, 1.0 - pow(1.0 - x, 2.4));
        } else {
            let y = saturate((x - 1.0) * PK_THRUST / (PK_RAISE - PK_STRUGGLE - PK_THRUST));
            h = mix(1.035, 1.0, y) + 0.008 * sin(y * 9.0) * (1.0 - y);
        }
    }
    let strain = smoothstep(0.88, PK_STRUGGLE, s) * f32(s < PK_STRUGGLE);
    let sh = 0.35 * f32(s < PK_STRUGGLE) + 2.2 * pk_jolt(s, 0.0, 8.0) + 1.4 * pk_jolt(s, 0.38, 10.0) + 1.6 * pk_jolt(s, 0.45, 9.0)
        + 1.8 * pk_jolt(s, 0.76, 10.0) + 1.5 * pk_jolt(s, 0.82, 9.0) + 1.6 * strain + 3.2 * pk_jolt(s, PK_STRUGGLE, 2.6);
    return vec2<f32>(h, sh);
}

// The leader of a bolt `et` seconds after it sets out: how far it has reached (of the way). It feels its way out in
// steps, slowly, stalling, for PK_CREEP, then suddenly runs the rest of the way.
fn pk_lead(et: f32, fi: f32) -> f32 {
    if (et <= 0.0) {
        return 0.0;
    }
    if (et < PK_CREEP) {
        let q = et / PK_CREEP;
        let w = q + 0.035 * sin(q * 11.0 + fi * 2.3);
        let st = (floor(w * 14.0) + smoothstep(0.0, 0.3, fract(w * 14.0))) / 14.0;
        return 0.36 * pow(saturate(st), 1.35);
    }
    let x = saturate((et - PK_CREEP) / (PK_SHOOT - PK_CREEP));
    return 0.36 + 0.64 * x * (0.7 + 0.3 * x);
}

// A bolt's jagged line: straight runs between random kinks, x of them along it; seeded by `so`.
fn pk_jg(x: f32, so: u32) -> f32 {
    let i = u32(i32(floor(x)) + 4096);
    return mix(f32(pcg(i ^ so)), f32(pcg((i + 1u) ^ so)), fract(x)) * (2.0 / 4294967296.0) - 1.0;
}

// A bolt of lightning from A to B (camera-relative), seeded by `s`, drawn out to `head` of the way along, `n` segments;
// `amp` how far it wanders off its line (of its length), `jit` how hard it crackles (its line trembling, a new tremble
// every frame of film, its shape kept), `rc` its channel's radius. Each kink is the same from frame to frame, so it keeps
// the path it took. x its core, y the glow round it, z how far along it the nearest point is.
fn pk_bolt(rd: vec3<f32>, A: vec3<f32>, B: vec3<f32>, head: f32, s: u32, n: i32, amp: f32, jit: f32, rc: f32, time: f32,
           scene_len: f32, sky: bool, cloud: bool) -> vec3<f32> {
    let AB = B - A;
    let L = max(length(AB), 1.0e-3);
    let D = AB / L;
    let qc = ray_seg(rd, A, A + AB * head);
    let wc = max(rc, qc.y * 0.0013);
    let margin = L * amp * 0.13 + wc * 30.0;
    if (head <= 0.0 || qc.x > margin) {
        return vec3<f32>(0.0);
    }
    let e1 = normalize(cross(D, select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(D.y) > 0.9)));
    let e2 = cross(D, e1);
    let s1 = pcg(s ^ 0x9e3779b9u);
    let s2 = pcg(s1);
    let s3 = pcg(s2);
    let s4 = pcg(s3);
    let s5 = pcg(s4);
    let s6 = pcg(s5);
    let s7 = pcg(s6);
    let s8 = pcg(s7);
    let sj = pcg(s ^ u32(i32(time * 24.0)));
    let fn_ = f32(n);
    // (in two passes: the line's broad bends first, four segments at a time, and only where the ray passes near one of
    // those its kinks; the broad bends kink on those four-segment knots, so the coarse line is exactly theirs)
    let nc = (n + 3) / 4;
    let fnc = f32(n) / 4.0;
    let fine = L * amp * 0.05;
    var cprev = A;
    var prev = A;
    var best = 1.0e9;
    var bt = 0.0;
    var bu = 0.0;
    for (var c = 1; c <= nc; c = c + 1) {
        let j0 = (c - 1) * 4;
        let j1 = min(c * 4, n);
        let cu0 = f32(j0) / fn_;
        if (cu0 >= head) {
            break;
        }
        let cu = f32(j1) / fn_;
        let cenv = sqrt(max(sin(cu * 3.14159265), 0.0));
        let co = vec2<f32>(pk_jg(cu * fnc * 0.5, s1), pk_jg(cu * fnc * 0.5, s2)) * 0.065 + vec2<f32>(pk_jg(cu * fnc, s3), pk_jg(cu * fnc, s4)) * 0.035;
        let CP = A + AB * cu + (e1 * co.x + e2 * co.y) * (L * amp * cenv);
        let cq = ray_seg(rd, cprev, CP);
        cprev = CP;
        if (cq.x > fine + max(rc, cq.y * 0.0013) * 40.0) {
            // (too far from it to matter: carry on from where its kinked line ends)
            if (cu > head) {
                break;
            }
            let x = cu * fn_;
            var o = co + vec2<f32>(pk_jg(x * 0.5, s5), pk_jg(x * 0.5, s6)) * 0.018 + vec2<f32>(pk_jg(x, s7), pk_jg(x, s8)) * 0.009;
            o = o + vec2<f32>(pk_jg(x, sj), pk_jg(x, sj ^ 0x55u)) * 0.0035 * jit;
            prev = A + AB * cu + (e1 * o.x + e2 * o.y) * (L * amp * cenv);
            continue;
        }
        for (var j = j0 + 1; j <= j1; j = j + 1) {
            let u0 = f32(j - 1) / fn_;
            if (u0 >= head) {
                break;
            }
            let u = f32(j) / fn_;
            let env = sqrt(max(sin(u * 3.14159265), 0.0));
            let x = u * fn_;
            var o = vec2<f32>(pk_jg(u * fnc * 0.5, s1), pk_jg(u * fnc * 0.5, s2)) * 0.065 + vec2<f32>(pk_jg(u * fnc, s3), pk_jg(u * fnc, s4)) * 0.035
                + vec2<f32>(pk_jg(x * 0.5, s5), pk_jg(x * 0.5, s6)) * 0.018 + vec2<f32>(pk_jg(x, s7), pk_jg(x, s8)) * 0.009;
            o = o + vec2<f32>(pk_jg(x, sj), pk_jg(x, sj ^ 0x55u)) * 0.0035 * jit;
            var P = A + AB * u + (e1 * o.x + e2 * o.y) * (L * amp * env);
            if (u > head) {
                P = mix(prev, P, (head - u0) * fn_);
            }
            let q = ray_seg(rd, prev, P);
            if (q.x < best) {
                best = q.x;
                bt = q.y;
                bu = mix(u0, min(u, head), q.z);
            }
            prev = P;
        }
    }
    if (best > 1.0e8) {
        return vec3<f32>(0.0);
    }
    let w = max(rc, bt * 0.0013);
    let en = rc / w;
    let occ = pk_occ(bt, scene_len, sky, cloud);
    let core = exp(-pow(best / (w * 0.6), 2.0)) * en;
    let glow = (exp(-best / (w * 3.5)) * 0.55 + exp(-best / (w * 14.0)) * 0.12) * en * (1.0 - smoothstep(0.4, 1.0, qc.x / margin));
    return vec3<f32>(core * occ, glow * occ, bu);
}

// The point `u` along a bolt's path (pk_bolt's, with no crackle): where a branch leaves it.
fn pk_bolt_at(A: vec3<f32>, B: vec3<f32>, u: f32, s: u32, n: i32, amp: f32) -> vec3<f32> {
    let AB = B - A;
    let L = max(length(AB), 1.0e-3);
    let D = AB / L;
    let e1 = normalize(cross(D, select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(D.y) > 0.9)));
    let e2 = cross(D, e1);
    let s1 = pcg(s ^ 0x9e3779b9u);
    let s2 = pcg(s1);
    let s3 = pcg(s2);
    let s4 = pcg(s3);
    let s5 = pcg(s4);
    let s6 = pcg(s5);
    let s7 = pcg(s6);
    let s8 = pcg(s7);
    let x = u * f32(n);
    let fnc = f32(n) / 4.0;
    let env = sqrt(max(sin(u * 3.14159265), 0.0));
    let o = vec2<f32>(pk_jg(u * fnc * 0.5, s1), pk_jg(u * fnc * 0.5, s2)) * 0.065 + vec2<f32>(pk_jg(u * fnc, s3), pk_jg(u * fnc, s4)) * 0.035
        + vec2<f32>(pk_jg(x * 0.5, s5), pk_jg(x * 0.5, s6)) * 0.018 + vec2<f32>(pk_jg(x, s7), pk_jg(x, s8)) * 0.009;
    return A + AB * u + (e1 * o.x + e2 * o.y) * (L * amp * env);
}

// How bright tower i's bolt is `et` after it set out: faint while it feels its way, a blinding stroke as it strikes the
// ring, then a held arc, flickering, struck again now and then, stuttering out when the towers cut out.
fn pk_bolt_light(et: f32, i: i32, seed: f32, time: f32) -> f32 {
    if (et <= 0.0) {
        return 0.0;
    }
    let tc = et - PK_SHOOT;
    if (tc < 0.0) {
        return 0.12 + 0.25 * smoothstep(PK_CREEP - 0.05, PK_SHOOT, et);
    }
    let s = u32(seed) + u32(i) * 977u;
    let fl = 0.72 + 0.28 * mh(u32(time * 30.0), s, 51u);
    let b = floor(time * 4.0);
    let rs = select(0.0, exp(-fract(time * 4.0) * 7.0) * 2.2, mh(u32(b), s, 52u) > 0.72 && tc > 0.6);
    let ct = time - PK_CUT - 0.08 * mh(u32(i), u32(seed), 34u);
    let end = select(1.0, step(0.45, mh(u32(time * 22.0), s, 53u)) * (1.0 + 1.5 * exp(-ct * 12.0)) * (1.0 - smoothstep(0.05, PK_DRAIN, ct)), ct > 0.0);
    return (fl + rs + 7.0 * exp(-tc * 9.0)) * end;
}

// The dust and earth tower i throws up, on the view ray up to `tmax`, its foot at F (camera-relative), `s` after it
// broke the surface: puffs of it vented round its foot each time it catches; then, as it bursts up, the bulk of the
// ground round it blown out in a surge rolling out over the land, a column of earth climbing with it and falling off it,
// and a cloud left hanging round its foot. Marched through in ten steps, lit by the day from above (its tops lit, its
// depths dark) and by `glow` near the tower. xyz the light it gives, w how much of what is behind shows through.
fn pk_dust(rd: vec3<f32>, F: vec3<f32>, s: f32, sb: f32, fi: f32, seed: f32, tmax: f32, px: vec2<f32>, amb: vec3<f32>,
           glow: vec3<f32>, time: f32) -> vec4<f32> {
    let tb = s - PK_STRUGGLE;                                   // since it burst up
    let up = tb > 0.0;
    // its foot's cloud: a little dust as the ground heaves, each catch venting more, then the bulk of it as it bursts
    let vent = 0.6 * (pk_jolt(s, 0.0, 2.0) + pk_jolt(s, 0.45, 2.5) + pk_jolt(s, 0.82, 2.5));
    let Rf = select(14.0 + 40.0 * sb + 50.0 * saturate(s / PK_STRUGGLE), 90.0 + 120.0 * (1.0 - exp(-tb * 0.5)), up);
    let Hf = select(10.0 + 14.0 * sb + 36.0 * saturate(s / PK_STRUGGLE), 80.0 + 90.0 * (1.0 - exp(-tb * 0.55)), up);
    let af = select(0.3 * sb + 0.45 * saturate(s * 2.0) + vent, 1.15 - 0.5 * smoothstep(2.0, 14.0, tb), up)
        * (1.0 - smoothstep(PK_CUT + 4.0, PK_END, time));
    // the surge rolling out, and the column of earth climbing with it
    let Rs = 60.0 + 340.0 * (1.0 - exp(-tb * 0.9));
    let aS = 26.0 + 75.0 * (1.0 - exp(-tb * 0.7));
    let as_ = select(0.0, exp(-tb / 3.5), up);
    let as2 = as_ * smoothstep(0.04, 0.12, as_);
    let Hc = 40.0 + 430.0 * (1.0 - exp(-tb * 1.4));
    let ac = select(0.0, 1.2 * exp(-max(tb - 0.8, 0.0) / 1.8), up);
    let ac2 = ac * smoothstep(0.04, 0.12, ac);
    let Rb = max(Rf * 1.05, max(select(0.0, Rs + aS * 1.4, as_ > 0.04), select(0.0, 120.0 + Hc * 0.3, ac > 0.04)));
    let Hb = max(Hf * 1.1, max(select(0.0, aS * 2.0, as_ > 0.04), select(0.0, Hc, ac > 0.04)));
    if (af + as_ + ac < 0.02) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // where the ray is inside its bounds: an upright cylinder round its foot
    let v = rd.xz;
    let a = max(dot(v, v), 1.0e-8);
    let b = -dot(v, F.xz);
    let c = dot(F.xz, F.xz) - Rb * Rb;
    let disc = b * b - a * c;
    if (disc <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    var t0 = (-b - sqrt(disc)) / a;
    var t1 = (-b + sqrt(disc)) / a;
    if (abs(rd.y) > 1.0e-5) {
        let ya = (F.y - 2.0) / rd.y;
        let yb = (F.y + Hb) / rd.y;
        t0 = max(t0, min(ya, yb));
        t1 = min(t1, max(ya, yb));
    }
    t0 = max(t0, 0.0);
    t1 = min(t1, tmax);
    if (t1 <= t0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let N = 9;
    let dt = (t1 - t0) / f32(N);
    var T = 1.0;
    var acc = vec3<f32>(0.0);
    let jit = ign(px);
    for (var k = 0; k < N; k = k + 1) {
        let q = rd * (t0 + (f32(k) + jit) * dt) - F;
        let r = length(q.xz);
        let y = max(q.y, 0.0);
        var d = af * smoothstep(1.0, 0.1, length(vec2<f32>(r / Rf, y / Hf)));
        if (up) {
            if (abs(r - Rs) < aS * 1.5 && as2 > 0.0) {
                let lump = 0.55 + 0.9 * gnoise2(vec2<f32>(atan2(q.z, q.x) * 5.0 + fi * 3.0, tb * 0.3));
                let aL = aS * lump;
                d = d + as2 * smoothstep(1.0, 0.1, length(vec2<f32>(r - Rs, y - aL * 0.55)) / aL) * smoothstep(Rs * 0.2, Rs * 0.75, r);
            }
            let Rc = 80.0 + 0.35 * y + 60.0 * (1.0 - exp(-tb * 1.2));
            d = d + ac2 * smoothstep(1.0, 0.2, r / Rc) * smoothstep(Hc, Hc * 0.5, y) * (0.6 + 0.4 * smoothstep(Hc * 0.25, 0.0, y));
        }
        // (none of it here, however the noise falls: no need to work it out)
        if (d < 0.135) {
            continue;
        }
        // (billowing: it churns and rolls out, climbing where it climbs; its edges eaten into billows, the noise only
        // taking away)
        let nq = q * 0.022 + vec3<f32>(fi * 17.0 + seed, -time * 0.3, fi * 5.0) - vec3<f32>(q.x, 0.0, q.z) * (0.005 / max(r, 1.0)) * time * 6.0;
        let n = gfbm3(nq, 2);
        d = smoothstep(0.0, 1.0, saturate((d * (0.4 + 2.2 * n) - 0.35) * 2.0));
        if (d > 0.002) {
            let al = 1.0 - exp(-d * 0.07 * dt);
            // (lit from above: its tops bright, its depths and underside dark; the tower's light on it close to it)
            let lit = amb * (0.3 + 1.0 * smoothstep(0.4, 0.8, n)) * (0.55 + 0.45 * saturate(y / max(Hf, 20.0)))
                + glow * exp(-r / 70.0);
            acc = acc + T * al * lit;
            T = T * (1.0 - al);
            if (T < 0.02) {
                break;
            }
        }
    }
    return vec4<f32>(acc, T);
}

// The mushroom of smoke over the crater `mt` after the nexus burst in it (C its foot, camera-relative), on the view ray
// up to `tmax`: a stem boiling up out of the crater into a cap that rolls over on itself as it climbs and spreads, glowing
// from under where the fire is still in it, cooling. Marched through in twelve steps. xyz the light it gives, w how much
// of what is behind shows through.
fn pk_mushroom(rd: vec3<f32>, C: vec3<f32>, mt: f32, seed: f32, tmax: f32, px: vec2<f32>, amb: vec3<f32>, time: f32) -> vec4<f32> {
    let hc = 90.0 + 640.0 * (1.0 - exp(-mt * 0.2));             // its cap's height,
    let rx = 90.0 + 340.0 * (1.0 - exp(-mt * 0.28));            // how wide,
    let ry = rx * 0.42;                                         // how deep
    let Rb = rx * 1.25;
    let Hb = hc + ry * 1.3;
    let v = rd.xz;
    let a = max(dot(v, v), 1.0e-8);
    let b = -dot(v, C.xz);
    let c = dot(C.xz, C.xz) - Rb * Rb;
    let disc = b * b - a * c;
    if (disc <= 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    var t0 = (-b - sqrt(disc)) / a;
    var t1 = (-b + sqrt(disc)) / a;
    if (abs(rd.y) > 1.0e-5) {
        let ya = (C.y - 2.0) / rd.y;
        let yb = (C.y + Hb) / rd.y;
        t0 = max(t0, min(ya, yb));
        t1 = min(t1, max(ya, yb));
    }
    t0 = max(t0, 0.0);
    t1 = min(t1, tmax);
    if (t1 <= t0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let N = 12;
    let dt = (t1 - t0) / f32(N);
    var T = 1.0;
    var acc = vec3<f32>(0.0);
    let jit = ign(px);
    let fresh = exp(-mt / 6.0);
    // (lightning flickering inside it now and then, as in a volcano's plume)
    let fb = floor(time * 9.0);
    let flick = step(0.8, fh21(vec2<f32>(fb, seed))) * exp(-mt / 8.0);
    let fq = vec3<f32>((fh21(vec2<f32>(fb, 3.0)) - 0.5) * rx, hc - ry * 0.3 + (fh21(vec2<f32>(fb, 5.0)) - 0.5) * ry, (fh21(vec2<f32>(fb, 7.0)) - 0.5) * rx);
    for (var k = 0; k < N; k = k + 1) {
        let q = rd * (t0 + (f32(k) + jit) * dt) - C;
        let r = length(q.xz);
        let y = q.y;
        // the cap: a ring rolling over on itself round a dome; the stem, wider at its foot and where it meets the cap
        let ring = length(vec2<f32>((r - rx * 0.55) / (rx * 0.5), (y - hc) / ry));
        let dome = length(vec2<f32>(r / (rx * 0.75), (y - hc - ry * 0.2) / (ry * 1.1)));
        var d = smoothstep(1.0, 0.25, min(ring, dome));
        let Rs = (36.0 + 4.5 * mt) * (1.0 + 0.7 * exp(-y / 25.0) + 0.8 * smoothstep(hc - ry * 2.5, hc - ry * 0.5, y));
        d = max(d, smoothstep(1.0, 0.3, r / Rs) * smoothstep(hc + ry * 0.2, hc - ry * 0.6, y) * 0.9);
        if (d < 0.13) {
            continue;
        }
        // (billowing: the cap rolling over, the stem climbing)
        let roll = vec3<f32>(q.x, 0.0, q.z) / max(r, 1.0);
        let nq = q * (0.9 / rx) + vec3<f32>(seed, -mt * 0.35, seed * 0.7) + roll * mt * 0.15;
        let n = gfbm3(nq * 3.0, 3);
        d = smoothstep(0.0, 1.0, saturate((d * (0.4 + 2.2 * n) - 0.35) * 2.0));
        if (d > 0.002) {
            let al = 1.0 - exp(-d * (2.4 / rx) * dt);
            // (lit from above, its depths dark; from under by the fire still in it, low in the stem and under the cap)
            let under = smoothstep(hc + ry * 0.3, hc - ry * 0.8, y) * smoothstep(0.35, 0.75, 1.0 - n);
            let glow = lava_ramp(0.35 + 0.35 * (1.0 - n)) * (exp(-max(y, 0.0) / 40.0) * 1.4 + under * 0.5) * fresh;
            let lit = amb * (0.3 + 1.0 * smoothstep(0.45, 0.85, n)) * (0.6 + 0.4 * saturate((y - hc + ry) / (2.0 * ry))) + glow
                + PK_ARC * flick * exp(-length(q - fq) / (rx * 0.35)) * 0.6;
            acc = acc + T * al * lit;
            T = T * (1.0 - al);
            if (T < 0.02) {
                break;
            }
        }
    }
    return vec4<f32>(acc, T);
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
    let charge = smoothstep(PK_IGN0 + PK_SHOOT, PK_MERGE, time) * f32(time < PK_FALL);
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

    // the ring's frame: its underside turned towards the player, and two directions across it (angles round it run from re1
    // towards re2)
    let tw = wing_dirs().xy;
    let rn = normalize(vec3<f32>(-tw.x * PK_RING_TILT, 1.0, -tw.y * PK_RING_TILT));
    let re1 = normalize(cross(rn, vec3<f32>(0.0, 0.0, 1.0)));
    let re2 = cross(rn, re1);
    // the towers, and how many beams are feeding the ring
    var em: array<vec4<f32>, 7>;
    var fa: array<f32, 7>;                                      // where round the ring each beam feeds it
    var fed = 0.0;
    var lock = 0.0;                                             // a jolt of light as each bolt strikes it
    var blt: array<f32, 7>;                                     // how bright each bolt is
    var strike_fl = 0.0;                                        // the flash of the bolts striking, all together
    for (var i = 0; i < PK_N; i = i + 1) {
        em[i] = pk_emitter(i, seed);
        blt[i] = pk_bolt_light(time - em[i].w, i, seed, time) * power;
        strike_fl = strike_fl + max(blt[i] - 1.0, 0.0);
        let fv = em[i].xyz - tgt;
        fa[i] = atan2(dot(fv, re2), dot(fv, re1));
        let lt = time - em[i].w - PK_SHOOT;
        fed = fed + smoothstep(-0.1, 0.2, lt);
        lock = lock + select(0.0, exp(-lt * 7.0), lt > 0.0 && time < PK_CUT);
    }
    // the ring: round the point over the target, tipped towards the player; it tightens as they fuse, holds while it
    // feeds the beam, and crushes in to a point as they drain, which falls into the crater
    let tight = smoothstep(PK_SHAKE, PK_MERGE, time);
    let crush = saturate((time - PK_CUT - 0.1) / (PK_FALL - PK_CUT - 0.1));
    let RR = mix(PK_RING_R, PK_RING_T, tight * tight) * (1.0 + 0.015 * sin(time * 9.0) * burn) * (1.0 - crush * crush);
    let fall = saturate((time - PK_FALL) / (PK_POP - PK_FALL));
    let NX0 = crel + vec3<f32>(0.0, PK_H, 0.0) + vec3<f32>(sin(time * 41.0), sin(time * 37.0 + 1.0), cos(time * 43.0)) * 2.5 * unstable;
    let NX = NX0 - vec3<f32>(0.0, (PK_H - 6.0) * fall * fall, 0.0);       // (falling, faster and faster)
    // its middle: nothing until they fuse; then the white-hot heart the beam is fired from, and at the end the ring
    // crushed into it
    let fuse = smoothstep(PK_MERGE - 0.4, PK_MERGE, time);
    let Rn = (fuse * (6.0 + 8.0 * select(0.0, exp(-merge_t * 3.0), merged)) * (1.0 - crush) + 14.0 * crush * crush + 2.0 * lock * fuse)
        * (0.94 + 0.06 * sin(time * 31.0) + 0.04 * sin(time * 53.0)) * f32(!popped);
    // how much of it is lit and how hard: the light it throws on the land and the clouds
    let glow_n = saturate(fed / 7.0) * (0.5 + 0.7 * charge + 0.6 * burn) * (1.0 - crush) * f32(!popped);
    // energy racing round it, faster and faster as it charges, and while it burns
    let spin = time * 1.5 + 9.0 * charge * charge * charge * max(time - PK_IGN0 - PK_SHOOT, 0.0) + 6.0 * burn * max(time - PK_DROP, 0.0);

    // ---- the light and the sky ------------------------------------------------
    let sun = frame.sun.xyz;
    let day = saturate(sun.y * 2.5 + 0.35);
    let pT = project_rel(crel);
    let pN = project_rel(NX);

    // ---- what bends the light: the ring, and the shock rings running out through the land -------------------------
    let d0 = depth_at(uv);
    let sky0 = is_sky(d0);
    let p0 = cam + world_offset(uv, select(d0, 0.5, sky0));
    var off = vec2<f32>(0.0);
    if (pN.z > 0.0 && glow_n > 0.01) {
        // what is seen through the ring bent towards its middle and turned with it, harder as it charges and as it
        // shudders; a shimmer of heat in it
        let r0d = normalize(world_offset(uv, 0.5));
        let dn0 = dot(r0d, rn);
        let tp0 = dot(NX0, rn) / select(dn0, 1.0e-4, abs(dn0) < 1.0e-4);
        if (tp0 > 0.0) {
            let in_ = saturate(1.0 - length(r0d * tp0 - NX0) / max(RR, 1.0));
            let dv = uv - pN.xy;
            let tw_ = in_ * in_ * (0.04 + 0.08 * charge + 0.1 * unstable) * glow_n;
            off = off - dv * in_ * in_ * (0.05 + 0.08 * charge + 0.1 * unstable) * glow_n + vec2<f32>(-dv.y, dv.x) * tw_
                + (vec2<f32>(gnoise2(uv * 90.0 + vec2<f32>(0.0, time * 3.0)), gnoise2(uv * 90.0 + vec2<f32>(17.0, time * 2.5))) - 0.5) * 0.004 * in_ * glow_n;
            off = off * k;
        }
    }
    if (pT.z > 0.0 && !sky0) {
        let r0 = length(p0.xz - tgt.xz);
        if (burst) {
            // the land rippling as the shock runs out through it, rings of it behind the front
            let rs = pk_shock_r(bt);
            let m = (exp(-pow((r0 - rs) / 7.0, 2.0)) + 0.5 * exp(-pow((r0 - rs * 0.8) / 5.0, 2.0)) * sin(r0 * 0.15 - bt * 20.0))
                * exp(-bt * 0.4);
            off = off + normalize(uv - pT.xy + vec2<f32>(1.0e-5)) * m * 0.03 * k;
        }
        if (popped) {
            let rs = pk_pop_r(mt);
            off = off + normalize(uv - pT.xy + vec2<f32>(1.0e-5)) * exp(-pow((r0 - rs) / 6.0, 2.0)) * exp(-mt * 0.6) * 0.02 * k;
        }
    }
    for (var i = 0; i < PK_N; i = i + 1) {
        // the land rippling out from each tower as it bursts up out of it
        let rt = time - (em[i].w - PK_RAISE + PK_STRUGGLE);
        if (rt > 0.0 && rt < 2.0 && !sky0) {
            let pb_ = project_rel(em[i].xyz - cam);
            let rr = length(p0.xz - em[i].xz);
            let rs = 260.0 * sqrt(rt);
            if (pb_.z > 0.0) {
                off = off + normalize(uv - pb_.xy + vec2<f32>(1.0e-5)) * exp(-pow((rr - rs) / 14.0, 2.0)) * exp(-rt * 1.8) * 0.012 * k;
            }
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
    var sky = is_sky(d);
    var solid = false;                                          // (a tower is what is seen here)
    let rel = world_offset(uv2, select(d, 0.5, sky));
    var scene_len = select(1.0e9, length(rel), !sky);
    let rd = normalize(world_offset(uv2, 0.5));
    let rdb = normalize(world_offset(uv, 0.5));                // not bent
    let P = cam + rel;
    var cloud = !sky && abs(P.y - CLOUD_Y - 2.0) < 6.0;
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
    // the clouds blown open from under the ring as they fuse, a rim of light running out round the hole
    if (cloud && merged) {
        let dcl = length(P.xz - (NX + cam).xz);
        let Rh = 1100.0 * (1.0 - exp(-merge_t * 0.9));
        col = mix(col, night * dark + vec3<f32>(0.2, 0.3, 0.5) * (1.0 - dark), smoothstep(Rh, Rh - 90.0, dcl) * 0.95 * k);
        col = col + PK_HOT * exp(-pow((dcl - Rh) / 45.0, 2.0)) * 0.5 * exp(-merge_t * 0.5) * k;
    }
    var add = vec3<f32>(0.0);

    // ---- the towers: the ground over each heaving and splitting, light leaking up through the cracks; the tower
    //      breaking the surface and struggling there, straining, catching, shuddering, leaning, puffs of dust venting
    //      round it; then bursting up out of it, the ground round it blown out in a surge of dust and a column of earth
    //      climbing with it, rock flung out; dark armoured metal, tiered, buttressed, power running up its seams, its
    //      crown's emitter crackling before it fires. Solid: the nearest of them (or of their heaving ground) is drawn
    //      over what is behind it, and hides it, and anything nearer (the land, the dust) hides it.
    var tS: array<vec4<f32>, 7>;                                // where each stands (shaking) and how far it has risen
    var tst: array<vec4<f32>, 7>;                               // s, its ground's heave, its power, its seams waking
    var near_t = scene_len;
    var near_col = vec3<f32>(0.0);
    var near_add = vec3<f32>(0.0);
    var near_a = 0.0;
    let hazec = srgb_to_linear(frame.fog_color.rgb) * (0.3 + 0.7 * day) * (1.0 - 0.8 * dark);
    let amb_t = mix(vec3<f32>(0.012, 0.018, 0.045), vec3<f32>(0.2, 0.24, 0.32), day) * (1.0 - 0.7 * dark);
    let sun_c = vec3<f32>(1.6, 1.5, 1.35) * day * (1.0 - 0.85 * dark);
    for (var i = 0; i < PK_N; i = i + 1) {
        let e = em[i];
        let fi = f32(i);
        let r0 = e.w - PK_RAISE;                                // when it breaks the surface
        let bt0 = time - (r0 - PK_BULGE);                       // since its ground began to heave
        tS[i] = vec4<f32>(e.xyz - cam, 0.0);
        tst[i] = vec4<f32>(-99.0, 0.0, 0.0, 0.0);
        if (bt0 <= 0.0) {
            continue;
        }
        let s = time - r0;
        let tb = s - PK_STRUGGLE;                               // since it burst up
        let rz = pk_rise(s);
        let S0 = e.xyz - cam;
        let ds = length(S0);
        let sdir = S0 / ds;
        let et = time - e.w;
        let c = 1.0 - dot(rd, sdir);
        let sb = smoothstep(0.0, PK_BULGE, bt0);
        // it shudders, the ground under it trembling as it heaves; it leans as it struggles, and straightens as it
        // bursts up; once it has cut out it sinks back, slowly at first
        let shk = rz.y + 0.5 * sb * f32(s < 0.0);
        let S = S0 + vec3<f32>(sin(time * 43.0 + fi * 1.3) + 0.5 * sin(time * 71.0 + fi), 0.0, sin(time * 37.0 + fi * 2.1) + 0.5 * sin(time * 67.0 + fi * 0.7)) * shk * 0.6;
        let la = mh(u32(i), u32(seed), 35u) * TAU;
        let lean = vec2<f32>(cos(la), sin(la)) * ((0.05 + 0.02 * mh(u32(i), u32(seed), 36u)) * (1.0 - smoothstep(PK_STRUGGLE, PK_STRUGGLE + 0.6, s)) + 0.004 * shk) * f32(s > 0.0);
        let sk = saturate((time - PK_CUT - 1.5) / 3.5);
        let lift = PK_TOWER_H * rz.x * (1.0 - sk * sk) + sin(time * 31.0) * shk * 0.3 * f32(s > 0.0);
        let lit = smoothstep(-0.5, 0.15, et) * power;
        let wake = smoothstep(0.0, 0.5, tb) * power;              // (its seams waking as it bursts up)
        let fire_ = select(0.0, exp(-(et - PK_SHOOT) * 2.2), et > PK_SHOOT);
        tS[i] = vec4<f32>(S, lift);
        tst[i] = vec4<f32>(s, sb, lit, wake);
        // (the horizon round it lit by its crown, a little, along the horizon more than above it)
        let low = exp(-abs(rd.y - sdir.y - 0.05) / 0.07);
        add = add + PK_ARC * (exp(-c / 0.004) * 0.6 + exp(-c / 0.02) * 0.08) * low * (0.5 * fire_ + 0.08 * lit) * select(0.15, 1.0, sky || scene_len > ds * 0.6) * k;
        // (only near it)
        if (ray_seg(rd, S0, S0 + vec3<f32>(0.0, PK_TOWER_H + 30.0, 0.0)).x > PK_TB * 1.5 + 60.0) {
            continue;
        }
        let haze = 1.0 - exp(-ds / 6000.0);
        // its ground heaving up before it breaks, split by cracks with light leaking up through them, then broken open
        // round it while it struggles, until it bursts out
        if (tb < 0.3) {
            let Rd = 150.0;
            let Cd = S0 + vec3<f32>(0.0, (34.0 * sb * sb + 8.0 * saturate(s / PK_STRUGGLE)) - Rd, 0.0);
            let tcd = dot(Cd, rd);
            let dc2 = dot(Cd, Cd) - tcd * tcd;
            if (tcd > 0.0 && dc2 < Rd * Rd) {
                let td = tcd - sqrt(Rd * Rd - dc2);
                let pd = rd * td - Cd;
                if (pd.y + Cd.y - S0.y > -0.5 && (sky || td < scene_len + 6.0) && td < near_t) {
                    let nd = pd / Rd;
                    let ang = atan2(nd.z, nd.x);
                    // (the land itself lifted, shaded by its slope; split by cracks no thinner than a pixel, the ground
                    // round them torn up dark, light leaking up out of them)
                    let pw = td * 0.0013 / 5.0;
                    let w1 = max(0.007, pw * 0.7);
                    let w2 = max(0.005, pw * 0.5);
                    let cn = abs(gnoise2(vec2<f32>(ang * 9.0, nd.y * 30.0) + vec2<f32>(fi * 5.0)) - 0.5);
                    let cn2 = abs(gnoise2(vec2<f32>(ang * 23.0, nd.y * 70.0) + vec2<f32>(fi * 3.0, 9.0)) - 0.5);
                    let open = sb * (1.0 - smoothstep(0.0, 0.3, tb));
                    let cracks = (exp(-cn / w1) * pow(0.007 / w1, 1.5) + 0.5 * exp(-cn2 / w2) * pow(0.005 / w2, 1.5) * saturate(s * 2.0)) * open;
                    let torn = (exp(-cn / (w1 * 6.0)) * 0.7 + smoothstep(0.985, 0.995, nd.y) * saturate(s * 3.0)) * open;
                    let slope = 0.55 + 0.6 * saturate(dot(nd, normalize(vec3<f32>(0.3, 1.0, 0.2))));
                    let land = vec3<f32>(0.12, 0.15, 0.08) * (0.25 + 0.75 * day) * (1.0 - 0.55 * dark) * slope;
                    let dome = mix(land, vec3<f32>(0.06, 0.048, 0.038) * (0.3 + 0.6 * day) * (1.0 - 0.5 * dark), saturate(torn));
                    near_t = td;
                    // (as hazy with distance as the land round it: it is the land)
                    near_col = mix(dome, col, saturate(td / 2500.0) * 0.85);
                    near_add = pk_heat(0.45 + 0.35 * saturate(cracks)) * cracks * (0.4 + 1.2 * saturate(s)) * k;
                    near_a = open;
                }
            }
        }
        if (lift > 1.0) {
            let rot = fi * 0.9 + mh(u32(i), u32(seed), 37u) * 1.0;
            pk_lift_g = lift;
            pk_heap_g = smoothstep(0.0, 0.4, tb) * (1.0 - smoothstep(PK_CUT + 2.0, PK_CUT + 6.0, time));
            let th = pk_tower(S, lift, lean, rot, rd, near_t);
            if (th.x > 0.0) {
                let X = rd * th.x;
                let q = pk_tlocal(X, S, lift, lean, rot);
                let nl = pk_tnormal(q, max(0.4, th.x * 0.0008));
                let cr = cos(rot);
                let sr = sin(rot);
                let n = normalize(vec3<f32>(cr * nl.x + sr * nl.z, nl.y, -sr * nl.x + cr * nl.z));
                let m = th.y;
                let yp = q.y;
                // (the panels of its hull: on each face of the six, plates in courses, each a little different, the
                // joints between them dark; their face-local place)
                let qf = pk_fold(q.xz, 6.0, 0.5235988);
                let course = floor(yp / 17.0);
                let pu = qf.y / 13.0 + 0.5 * (course - 2.0 * floor(course / 2.0));
                let groove = max(smoothstep(0.45, 0.49, abs(fract(pu) - 0.5)), smoothstep(0.46, 0.49, abs(fract(yp / 17.0) - 0.5))) * f32(m < 0.5 || m > 2.5);
                let plate = fh21(vec2<f32>(floor(pu) + floor(atan2(q.z, q.x) * 0.955) * 17.0, course + fi * 31.0));
                // (some plates inset, darker, a slit of light across them)
                let inset = step(0.8, plate) * f32(m < 0.5) * step(PK_T0, yp);
                var alb = vec3<f32>(0.042, 0.046, 0.056) * (0.7 + 0.6 * plate) * (1.0 - 0.6 * groove) * (1.0 - 0.5 * inset);
                if (m > 0.5 && m < 1.5) {
                    alb = vec3<f32>(0.065, 0.066, 0.072);                  // collars and ribs: heavier, brighter metal
                } else if (m > 1.5 && m < 2.5) {
                    alb = vec3<f32>(0.06, 0.062, 0.075);                   // the crown
                } else if (m > 2.5 && m < 3.5) {
                    alb = vec3<f32>(0.038, 0.04, 0.05) * (0.85 + 0.3 * plate); // the buttresses
                } else if (m > 5.5) {
                    alb = vec3<f32>(0.075, 0.062, 0.05) * (0.6 + 0.6 * gnoise2(q.xz * 0.3));   // the broken ground
                }
                // lit by the sky, the sun, the ring, the beam, and its own emitter; its hollows shadowed
                let ao = 0.3 + 0.7 * saturate(pk_tsdf(q + nl * 6.0).x / 6.0);
                let L = frame.sun.xyz;
                let Lr = normalize(NX - X);
                let Lb = normalize(crel - X);
                let qe = vec3<f32>(0.0, PK_CORE_Y, 0.0) - q;
                let de2 = dot(qe, qe);
                let emi = (0.3 * lit + 3.0 * fire_ + 0.1 * wake) * 900.0 / (900.0 + de2) * max(dot(nl, qe * inverseSqrt(de2)), 0.0);
                let ringc = pk_heat(0.55) * glow_n * 0.4 + vec3<f32>(0.5, 0.7, 1.2) * burn * 0.3;
                let diff = amb_t * (0.35 + 0.65 * n.y) + sun_c * max(dot(n, L), 0.0) + pk_heat(0.55) * glow_n * 0.22 * max(dot(n, Lr), 0.0)
                    + vec3<f32>(0.5, 0.7, 1.2) * burn * 0.3 * max(dot(n, Lb), 0.0) + PK_HOT * emi;
                let spec = sun_c * pow(max(dot(n, normalize(L - rd)), 0.0), 48.0) * 0.35 + ringc * pow(max(dot(n, normalize(Lr - rd)), 0.0), 24.0) * 0.6;
                let rim = pow(1.0 - max(dot(n, -rd), 0.0), 5.0) * select(1.0, 0.15, m > 5.5);
                var tc = alb * diff * ao * (0.6 + 0.4 * smoothstep(0.0, 200.0, yp)) + spec * ao * (1.0 - 0.6 * groove) + (amb_t * 1.5 + PK_DEEP * 0.12 * (0.2 + lit)) * rim * ao;
                // power: in the seams over the joints, up the middle of some of the hull's plates in runs, along the
                // buttresses' edges, round the ring plate, surging; the emitter blazing as it fires
                let yj = PK_T0 + clamp(round((yp - PK_T0) / PK_TIER), 1.0, 5.0) * PK_TIER;
                let surge = 0.3 + pow(0.5 + 0.5 * sin(yp * 0.03 - time * 10.0 + fi), 6.0) * 1.8;
                let run = step(0.55, fh21(vec2<f32>(floor(yp / 23.0) + floor(atan2(q.z, q.x) * 0.955) * 7.0, fi + seed)));
                var glow = 0.0;
                if (m < 0.5) {
                    glow = exp(-pow((yp - yj - 3.6) / 0.8, 2.0)) * 0.7 + exp(-pow(qf.y / 0.7, 2.0)) * run * step(PK_T0, yp) * 0.6
                        + inset * exp(-pow((fract(yp / 17.0) - 0.5) / 0.04, 2.0)) * 0.5;
                } else if (m > 2.5 && m < 3.5) {
                    let q3 = pk_fold(q.xz, 3.0, 0.0);
                    glow = exp(-pow((104.0 - 0.38 * yp - q3.x) / 1.2, 2.0)) * smoothstep(0.0, 20.0, yp) * 0.9;
                } else if (m > 1.5 && m < 2.5) {
                    glow = exp(-pow((length(q.xz) - 37.0) / 1.0, 2.0)) * smoothstep(356.0, 350.0, yp) * 1.2 + exp(-pow((length(q.xz) - 25.0) / 1.0, 2.0)) * smoothstep(356.0, 350.0, yp) * 0.6;
                }
                if (m > 5.5) {
                    let cn = abs(gnoise2(q.xz * 0.12 + vec2<f32>(fi * 7.0)) - 0.5);
                    glow = exp(-cn / 0.015) * 0.35 * (1.0 - smoothstep(0.0, 6.0, tb));
                }
                var em_ = PK_HOT * glow * surge * (0.12 * wake + lit) * 0.9;
                if (m > 4.5 && m < 5.5) {
                    em_ = PK_WHITE * (0.15 * wake + 0.8 * lit + 2.5 * fire_) + PK_HOT * (0.3 * wake + lit) * (0.6 + 0.4 * rim);
                    tc = vec3<f32>(0.02, 0.03, 0.06);
                }
                // (caked in earth where it came up through the ground as it struggled, the earth falling away in streaks
                // once it has burst up)
                let crust_top = PK_TOWER_H - 0.17 * PK_TOWER_H;
                let streak = gnoise2(vec2<f32>(atan2(q.z, q.x) * 11.0, yp * 0.012 + fi));
                let earth = saturate(smoothstep(crust_top - 30.0, crust_top + 10.0, yp) * select(1.0, saturate(1.0 - tb * 0.35 - (1.0 - streak) * 0.7), tb > 0.0)
                    + smoothstep(90.0, 0.0, yp) * 0.7) * 0.9 * f32(m < 5.5);
                tc = mix(tc, vec3<f32>(0.07, 0.056, 0.042) * (0.6 + 0.5 * streak) * (0.3 + 0.6 * day) * (1.0 - 0.4 * dark) * (0.5 + 0.5 * ao), earth);
                em_ = em_ * (1.0 - earth);
                near_t = th.x;
                near_col = mix(tc, hazec, haze);
                near_add = em_ * (1.0 - haze * 0.7) * k;
                near_a = 1.0;
            }
        }
    }
    if (near_a > 0.0) {
        col = mix(col, near_col, near_a);
        add = add * (1.0 - near_a) + near_add;
        scene_len = near_t;
        if (near_a > 0.5) {
            sky = false;
            cloud = false;
            solid = true;
        }
    }
    // what each throws up, and its crown, the furthest first, each cut by what is in front of it
    var order: array<i32, 7>;
    for (var i = 0; i < PK_N; i = i + 1) {
        order[i] = i;
    }
    for (var i = 0; i < PK_N; i = i + 1) {
        for (var j = i + 1; j < PK_N; j = j + 1) {
            if (dot(tS[order[j]].xyz, tS[order[j]].xyz) > dot(tS[order[i]].xyz, tS[order[i]].xyz)) {
                let o = order[i];
                order[i] = order[j];
                order[j] = o;
            }
        }
    }
    for (var oi = 0; oi < PK_N; oi = oi + 1) {
        let i = order[oi];
        let st = tst[i];
        let s = st.x;
        if (s < -PK_BULGE - 0.5) {
            continue;
        }
        let fi = f32(i);
        let S0 = em[i].xyz - cam;
        let S = tS[i].xyz;
        let lift = tS[i].w;
        let sb = st.y;
        let lit = st.z;
        let wake = st.w;
        let tb = s - PK_STRUGGLE;
        let et = time - em[i].w;
        let fire_ = select(0.0, exp(-(et - PK_SHOOT) * 2.2), et > PK_SHOOT);
        // (only near it: what it throws up climbs some 600 blocks and spreads 400 round it)
        if (ray_seg(rd, S0, S0 + vec3<f32>(0.0, 650.0, 0.0)).x > 480.0) {
            continue;
        }
        // the dust it throws up (cut by the land and by the towers)
        let amb = vec3<f32>(0.4, 0.36, 0.31) * (0.15 + 0.85 * day) * (1.0 - 0.6 * dark) + PK_DEEP * 0.03 * lit;
        let dg = PK_HOT * (0.05 * lit + 0.06 * wake * exp(-max(tb, 0.0))) + lava_ramp(0.4) * 0.05 * f32(s > 0.0) * exp(-max(s, 0.0) * 0.8);
        let du = pk_dust(rd, S0, s, sb, fi, seed, select(scene_len, 1.0e9, sky), in.position.xy, amb, dg, time);
        col = col * du.w + du.xyz * k + col * (1.0 - k) * (1.0 - du.w);
        add = add * mix(1.0, du.w, 0.85);
        // rock flung up and out as it bursts through, falling back (dark against the sky)
        if (tb > 0.0 && tb < 6.0 && ray_seg(rd, S0, S0 + vec3<f32>(0.0, 130.0 * tb, 0.0)).x < 100.0 * tb + 60.0) {
            for (var j = 0; j < 14; j = j + 1) {
                let hv = vec3<f32>(pcg3d(vec3<u32>(u32(j), u32(i), u32(seed)))) * (1.0 / 4294967295.0);
                let az = hv.x * TAU;
                let vh = 25.0 + 70.0 * hv.y;
                let vy = 45.0 + 85.0 * hv.z * hv.z;
                let s3 = S0 + vec3<f32>(cos(az) * 40.0, 6.0, sin(az) * 40.0);
                let a1 = max(tb - 0.05, 0.0);
                let pa = s3 + vec3<f32>(cos(az) * vh * tb, vy * tb - 16.0 * tb * tb, sin(az) * vh * tb);
                let pb = s3 + vec3<f32>(cos(az) * vh * a1, vy * a1 - 16.0 * a1 * a1, sin(az) * vh * a1);
                if (pa.y < S0.y - 2.0) {
                    continue;
                }
                let qj = ray_seg(rd, pa, pb);
                let wj = 2.0 + 4.5 * hv.y;
                let cov = smoothstep(1.0, 0.5, qj.x / max(wj, qj.y * 0.0013)) * (wj / max(wj, qj.y * 0.0013));
                let vj = select(1.0, 1.0 - smoothstep(scene_len - 1.0, scene_len + 1.0, qj.y), !sky);
                col = mix(col, vec3<f32>(0.035, 0.03, 0.026) * (0.4 + 0.6 * day), cov * vj);
                add = add * (1.0 - cov * vj * 0.8);
            }
        }
        // its emitter: blazing as it fires, and before it fires the charge crawling over its crown, crackling
        let tip = S + vec3<f32>(0.0, lift - PK_TOWER_H + PK_CORE_Y, 0.0);
        let ct = 1.0 - dot(rd, normalize(tip));
        add = add + (PK_WHITE * exp(-ct / 3.0e-6) * 0.6 + PK_HOT * exp(-ct / 6.0e-5) * 0.4) * (lit + 2.0 * fire_)
            * pk_occ(length(tip) - 12.0, scene_len, sky, cloud) * k;
        let corona = smoothstep(-0.7, -0.1, et) * (1.0 - smoothstep(PK_SHOOT, PK_SHOOT + 0.5, et)) * power;
        if (corona > 0.01) {
            for (var j = 0; j < 2; j = j + 1) {
                let sj = pcg(u32(seed) + u32(i) * 131u + u32(j) * 7u + u32(time * 16.0) * 1009u);
                let hv = vec3<f32>(pcg3d(vec3<u32>(sj, 3u, 5u))) * (1.0 / 4294967295.0);
                let a0 = tip + vec3<f32>(0.0, 6.0 * hv.x, 0.0);
                let dir = normalize(vec3<f32>(cos(hv.y * TAU), 0.6 * hv.z - 0.1, sin(hv.y * TAU)));
                let bo = pk_bolt(rd, a0, a0 + dir * (30.0 + 30.0 * hv.z), 1.0, sj, 6, 1.6, 0.0, 0.5, time, scene_len, sky, cloud);
                add = add + (PK_WHITE * bo.x * 0.8 + PK_HOT * bo.y) * corona * k;
            }
        }
    }

    // ---- on the land: lit by the ring and the beam, the shock rings, the crater and the fissures molten ----------
    let rel2 = P.xz - tgt.xz;
    let r = length(rel2);
    let dy = P.y - tgt.y;
    if (!sky && !solid) {
        let on_ground = 1.0 - smoothstep(25.0, 40.0, dy);
        // the ring lights the land under it, a ring of blue light on it, falling off from its nearest point
        let pr = P - cam - NX0;
        let pp = pr - rn * dot(pr, rn);
        let ql = pr - pp / max(length(pp), 1.0e-3) * RR;
        col = col + col * vec3<f32>(0.45, 0.6, 0.95) * glow_n * 50000.0 / (dot(ql, ql) + 60000.0) * k;
        // the bolts lighting the land under them, blinding as each strikes
        for (var i = 0; i < PK_N; i = i + 1) {
            if (blt[i] > 0.01) {
                let A = em[i].xyz - cam + vec3<f32>(0.0, PK_TOWER_H, 0.0);
                let F = NX0 + (re1 * cos(fa[i]) + re2 * sin(fa[i])) * RR;
                let ab = F - A;
                let pa = P - cam - A;
                let dl = length(pa - ab * saturate(dot(pa, ab) / dot(ab, ab)));
                col = col + col * vec3<f32>(0.8, 0.85, 1.1) * blt[i] * 0.2 / (1.0 + dl * dl / 90000.0) * k;
            }
        }
        // the beam hard on the land round its foot
        col = col + col * vec3<f32>(1.6, 2.2, 3.6) * burn * 22000.0 / (r * r + dy * dy + 7500.0) * k;
        if (charge > 0.0 && hit_t < 0.5) {
            // charging: the ground under the ring glowing with the charge gathering in it, flickering
            let fade = 1.0 - smoothstep(0.0, 0.5, hit_t);
            let fl = 0.6 + 0.4 * mh(u32(time * 24.0), u32(seed), 61u);
            add = add + PK_ARC * exp(-r / 24.0) * charge * charge * 0.5 * fl * on_ground * fade * k;
        }
        if (burst) {
            // the shock ring racing out over the land, kicking up dust as it goes
            let rs = pk_shock_r(bt);
            // (a flash along it at first; then only the dust it lifts, pale on its leading edge)
            add = add + (PK_HOT * 0.6 + vec3<f32>(1.2, 1.0, 0.8)) * exp(-pow((r - rs) / 4.0, 2.0)) * exp(-bt * 3.0) * on_ground * k;
            col = mix(col, vec3<f32>(0.3, 0.27, 0.24) * (0.3 + 0.7 * day) * (1.0 - 0.5 * dark), exp(-pow((r - rs + 8.0) / 14.0, 2.0)) * 0.45 * exp(-bt * 0.35) * on_ground * k);
            let behind = smoothstep(rs, rs - 30.0, r) * smoothstep(rs - 160.0, rs - 50.0, r) * exp(-bt * 0.3);
            col = mix(col, vec3<f32>(0.16, 0.13, 0.11) * (0.3 + 0.7 * day) * (1.0 - 0.6 * dark), behind * 0.55 * on_ground * k);
        }
        if (popped) {
            let rs = pk_pop_r(mt);
            add = add + PK_HOT * exp(-pow((r - rs) / 3.0, 2.0)) * exp(-mt * 3.0) * 0.8 * on_ground * k;
            col = mix(col, vec3<f32>(0.3, 0.27, 0.24) * (0.3 + 0.7 * day) * (1.0 - 0.5 * dark), exp(-pow((r - rs + 6.0) / 10.0, 2.0)) * 0.35 * exp(-mt * 0.5) * on_ground * k);
        }
        if (burst && r < PK_BOWL * 1.12) {
            // the crater glowing where it has just been dug (each part of it as it is opened, from the middle out,
            // cooling), hotter the deeper; the magma strewn over its floor (more of it in towards the shaft) and over the
            // bedrock at the foot of the shaft glowing on in patches (strike.rs strews it so: no lake, only rock); round
            // the foot of the beam everything white-hot
            let deep = max(-dy, 0.0);
            let dug = time - pk_dig_t(r);
            let open = pk_open(rel2, r, time, seed);
            let fresh = exp(-max(dug, 0.0) / 7.0) * smoothstep(1.0, 3.0, deep) * open;
            let core = saturate((deep - 30.0) / 60.0) * open;
            let pn = gnoise2(rel2 * 0.11 + vec2<f32>(seed, 0.0));
            let hotf = saturate(1.0 - (r - PK_SHAFT) / (PK_BOWL - PK_SHAFT));
            let th = 0.66 - 0.22 * hotf * hotf;
            let mpatch = smoothstep(th, th + 0.1, pn) * smoothstep(PK_WALL_D * 0.6, PK_WALL_D, deep) * open;
            let bottom = smoothstep(PK_SHAFT_D - 16.0, PK_SHAFT_D - 4.0, deep) * smoothstep(0.42, 0.56, pn) * open;
            let heat = max(max(fresh * 0.85, core * 0.6), max(mpatch * 0.8, bottom * 0.9)) * (1.0 - smoothstep(PK_BOWL * 0.98, PK_BOWL * 1.1, r))
                + burn * exp(-r / 35.0);
            let n = gfbm2(rel2 * 0.06 + vec2<f32>(P.y * 0.2 + time * 0.05, seed));
            let veins = exp(-pow((n - 0.5) / 0.07, 2.0));
            let molten = mix(veins * 0.9, 1.0, saturate(heat * heat + max(mpatch, bottom)));
            let hh = heat * molten * (0.8 + 0.4 * gnoise2(rel2 * 0.15 + vec2<f32>(time * 0.3, P.y)));
            add = add + lava_ramp(hh) * smoothstep(0.03, 0.25, heat * molten) * on_ground * after * 2.6 * k;
        }
        // the fissures running out from the rim, opening as the shock reaches them, light pulsing out along them
        // (in from the rim too, across the land not dug yet, up to the crater's real edge)
        let unopened = 1.0 - pk_open(rel2, r, time, seed);
        if (burst && r > PK_SHAFT && r < PK_RIM + 170.0 && unopened > 0.01) {
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
                let u = max(r - PK_RIM, 0.0);
                if (u > cr.y) {
                    continue;
                }
                let j = i32(floor(u / PK_SEG));
                let f = fract(u / PK_SEG);
                let a = cr.x + mix(pk_crack_off(i, j, seed), pk_crack_off(i, j + 1, seed), f);
                var da = ang - a;
                da = da - TAU * floor(da / TAU + 0.5);
                let lat = abs(da) * r;
                let hw = 1.0 + 4.5 * (1.0 - u / cr.y);
                let open = saturate((pk_crack_front(bt) - u) / 6.0);
                let c1 = ((1.0 - smoothstep(hw - 0.4, hw + 0.8, lat)) + exp(-lat / (hw * 2.5)) * 0.35) * open;
                if (c1 > crack) {
                    crack = c1;
                    pulse = pow(0.5 + 0.5 * sin(u * 0.1 - time * 5.0 + f32(i)), 4.0);
                }
            }
            crack = crack * unopened;
            if (crack > 0.01) {
                let hh = (0.55 + 0.35 * exp(-bt / 14.0) + 0.25 * pulse * power) * (0.85 + 0.3 * gnoise2(rel2 * 0.3 + vec2<f32>(time * 0.3, 0.0)));
                add = add + (lava_ramp(hh) + PK_HOT * pulse * 0.4 * power) * crack * on_ground * after * 2.2 * k;
            }
        }
    }
    // the clouds lit from above by the ring, from below by the beam
    if (cloud) {
        let pr = P - cam - NX0;
        let pp = pr - rn * dot(pr, rn);
        let dn = length(pr - pp / max(length(pp), 1.0e-3) * RR);
        add = add + pk_heat(0.4) * (glow_n * 0.45 * exp(-dn / 140.0) + burn * 0.12 * exp(-length(rel2) / 80.0)) * k;
        for (var i = 0; i < PK_N; i = i + 1) {
            if (blt[i] > 0.01) {
                let A = em[i].xyz - cam + vec3<f32>(0.0, PK_TOWER_H, 0.0);
                let F = NX0 + (re1 * cos(fa[i]) + re2 * sin(fa[i])) * RR;
                let ab = F - A;
                let pa = P - cam - A;
                let dl = length(pa - ab * saturate(dot(pa, ab) / dot(ab, ab)));
                add = add + vec3<f32>(0.5, 0.6, 1.2) * blt[i] * 0.35 / (1.0 + dl * dl / 40000.0) * k;
            }
        }
    }

    // ---- the land doming up under the beam, cracking with the light inside it, before it bursts --------------------
    if (hit_t > 0.0 && !burst) {
        let s = pow(saturate(hit_t / (PK_BURST - PK_HIT)), 2.2);
        let Rd = 40.0 + 140.0 * s;
        let Cd = crel - vec3<f32>(0.0, Rd * 0.62, 0.0);
        let tcd = dot(Cd, rd);
        let dc2 = dot(Cd, Cd) - tcd * tcd;
        // (not from under it: the player standing on it would be lifted with it)
        if (tcd > 0.0 && dc2 < Rd * Rd && dot(Cd, Cd) > Rd * Rd) {
            let td = tcd - sqrt(Rd * Rd - dc2);
            let pd = rd * td - Cd;
            if (pd.y + Cd.y - crel.y > -1.0 && (sky || td < scene_len + 4.0)) {
                let nd = pd / Rd;
                let ang = atan2(nd.z, nd.x);
                // (the land itself heaved up, shaded by its slope, split by cracks no thinner than a pixel, white-hot
                // light inside them, the ground torn dark along them)
                let pw = td * 0.0013 / max(Rd / 6.0, 1.0);
                let w1 = max(0.012, pw * 0.7);
                let w2 = max(0.008, pw * 0.5);
                let cn = abs(gnoise2(vec2<f32>(ang * 4.0, nd.y * 6.0) + vec2<f32>(seed)) - 0.5);
                let cn2 = abs(gnoise2(vec2<f32>(ang * 11.0, nd.y * 15.0) + vec2<f32>(seed + 7.0)) - 0.5);
                let cracks = (exp(-cn / w1) * pow(0.012 / w1, 1.5) + 0.6 * exp(-cn2 / w2) * pow(0.008 / w2, 1.5)) * smoothstep(0.1, 0.8, s);
                let torn = exp(-cn / (w1 * 5.0)) * smoothstep(0.0, 0.6, s);
                let top = exp(-(1.0 - nd.y) * 14.0);
                let slope = 0.5 + 0.7 * saturate(dot(nd, normalize(vec3<f32>(0.3, 1.0, 0.2))));
                let land = vec3<f32>(0.12, 0.15, 0.08) * (0.25 + 0.75 * day) * (1.0 - 0.55 * dark) * slope * (1.0 + 1.2 * max(nd.y, 0.0) * glow_n);
                col = mix(land, vec3<f32>(0.05, 0.04, 0.035) * (0.3 + 0.6 * day), saturate(torn));
                add = (mix(lava_ramp(0.55 + 0.4 * saturate(cracks)), PK_WHITE * 0.15, 0.3) * cracks * 2.5 + PK_HOT * top * 1.5 * s) * k;
                scene_len = min(scene_len, td);
            }
        }
    }

    // ---- the wall of dust thrown out round it, racing over the land and climbing ------------------------------------
    if (burst && bt < 18.0) {
        let Rw = 120.0 + 520.0 * (1.0 - exp(-bt * 0.3));
        let Hw = 30.0 + 170.0 * (1.0 - exp(-bt * 0.45));
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
            let lit = vec3<f32>(0.2, 0.18, 0.16) * (0.25 + 0.75 * day) * (1.0 - 0.6 * dark) + vec3<f32>(0.2, 0.28, 0.5) * burn * 0.6 * exp(-Rw / 500.0);
            col = mix(col, lit, saturate(dust * fade) * 0.85 * k);
            add = add * (1.0 - saturate(dust * fade) * 0.6);
        }
    }

    // ---- the column of ejecta thrown up round the beam as the land bursts, thinning out -------------------------
    if (burst && bt < 14.0) {
        let He = 60.0 + 460.0 * (1.0 - exp(-bt * 0.9));
        let Re = 45.0 + 70.0 * (1.0 - exp(-bt * 0.6));
        let q = ray_seg(rd, crel, crel + vec3<f32>(0.0, He, 0.0));
        if (q.x < Re * 1.6) {
            let X = rd * q.y - crel;
            let side = dot(X, normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0)));
            let n = gfbm2(vec2<f32>(side / Re * 1.5 + seed, X.y / Re * 0.6 - bt * 0.8));
            // a ragged shell, densest at its edge, its top boiling out
            let shell = exp(-pow((q.x - Re * 0.6) / (Re * 0.5), 2.0)) * (0.4 + 0.9 * n) * smoothstep(He, He * 0.7, X.y);
            let dens = saturate(shell * 1.1) * exp(-max(bt - 5.0, 0.0) / 3.0) * (1.0 - smoothstep(11.0, 14.0, bt)) * smoothstep(Re * 1.2, Re * 2.6, length(crel.xz));
            let vis = select(1.0, 1.0 - smoothstep(scene_len - 1.0, scene_len + 1.0, q.y), !sky);
            let lit = vec3<f32>(0.09, 0.075, 0.065) * (0.3 + 0.7 * day) * (1.0 - 0.5 * dark) + PK_HOT * 0.02 * burn * (0.5 + n)
                + lava_ramp(0.55) * exp(-max(X.y, 0.0) / 25.0) * 0.15;
            col = mix(col, lit, dens * 0.9 * vis * k);
            add = add * (1.0 - dens * 0.5 * vis);
        }
    }

    // ---- the mushroom of smoke climbing over the crater once the nexus has burst there, lit from under ------------
    if (popped) {
        let amb = vec3<f32>(0.2, 0.19, 0.19) * (0.2 + 0.8 * day) * (1.0 - 0.5 * dark);
        let mu = pk_mushroom(rd, crel, mt, seed, select(scene_len, 1.0e9, sky), in.position.xy, amb, time);
        let f = after * smoothstep(0.0, 0.8, mt) * k;
        col = mix(col, col * mu.w + mu.xyz, f);
        add = add * mix(1.0, mu.w, 0.85 * f);
    }

    // ---- the towers' bolts: each feeling its way out from its crown towards the ring in steps, branching, slowly, then
    //      running the rest of the way and striking it, a blinding stroke that lights the land and the sky; then held,
    //      the same jagged path, trembling, flickering, struck again now and then; where it meets the ring, a crackling
    //      knot of light ---------------------------------------------------------------------------------------------
    for (var i = 0; i < PK_N; i = i + 1) {
        let e = em[i];
        let et = time - e.w;
        let Lb = blt[i];
        if (et <= 0.0 || Lb < 0.002) {
            continue;
        }
        let fi = f32(i);
        let A = e.xyz - cam + vec3<f32>(0.0, PK_CORE_Y + 9.0, 0.0);
        let F = NX0 + (re1 * cos(fa[i]) + re2 * sin(fa[i])) * RR;
        let head = pk_lead(et, fi);
        let si = pcg(u32(seed) * 31u + u32(i) * 7919u);
        let tc = et - PK_SHOOT;
        let held = tc > 0.0;
        let rc = select(1.0, 2.0 + 2.5 * exp(-tc * 6.0), held) * k;
        let bo = pk_bolt(rdb, A, F, head, si, 32, 1.0, select(0.0, 1.0, held), rc, time, scene_len, sky, cloud);
        // (its glow held back in the blinding moment it strikes: the core blazes, the air round it does not fog over)
        let gl = min(Lb, 2.0) / max(Lb, 1.0e-3);
        var c = PK_WHITE * bo.x * 1.1 + PK_ARC * bo.y * gl;
        // (the leader's tip, brightest where it is feeling its way)
        if (!held) {
            let hp = pk_bolt_at(A, F, head, si, 32, 1.0);
            let th = max(dot(hp, rdb), 0.0);
            let dh = length(hp - rdb * th);
            let wh = max(2.0, th * 0.0013);
            c = c + (PK_WHITE * exp(-pow(dh / (wh * 1.2), 2.0)) * 1.5 + PK_ARC * exp(-dh / (wh * 6.0)) * 0.5) * (2.0 / wh) * pk_occ(th, scene_len, sky, cloud) * 3.0;
        }
        // its branches, put out as it feels its way; they flash with the stroke and die
        let br = select(1.0, 0.5 * exp(-tc * 7.0), held);
        if (br > 0.01) {
            for (var j = 0; j < 4; j = j + 1) {
                let sbj = pcg(si + u32(j) * 0x2545u);
                let hv = vec3<f32>(pcg3d(vec3<u32>(sbj, 9u, 1u))) * (1.0 / 4294967295.0);
                let ub = 0.04 + 0.27 * hv.x;
                let bh = saturate((min(head, 0.36) - ub) / (0.07 + 0.08 * hv.y));
                if (bh <= 0.0) {
                    continue;
                }
                let O = pk_bolt_at(A, F, ub, si, 32, 1.0);
                let D = normalize(F - A);
                let e1 = normalize(cross(D, vec3<f32>(0.0, 1.0, 0.0)));
                let e2 = cross(D, e1);
                let ba = hv.z * TAU;
                let dir = normalize(D + (e1 * cos(ba) + e2 * sin(ba)) * (0.5 + 0.5 * hv.y));
                let lb = length(F - A) * (0.06 + 0.1 * hv.y);
                let bb = pk_bolt(rdb, O, O + dir * lb, bh, sbj, 8, 1.5, 0.0, rc * 0.6, time, scene_len, sky, cloud);
                c = c + (PK_WHITE * bb.x * 0.7 + PK_ARC * bb.y * 0.8 * gl) * br * (1.0 - 0.6 * bb.z);
            }
        }
        // (the air round it lit)
        let qa = ray_seg(rdb, A, A + (F - A) * head);
        c = c + vec3<f32>(0.5, 0.55, 1.0) * exp(-qa.x / max(50.0, qa.y * 0.03)) * 0.025 * gl * pk_occ(qa.y, scene_len, sky, cloud);
        // where it meets the ring: a white-hot knot, arcs crackling out of it over the ring (blazing as it strikes, but
        // not swelling into a ball of light)
        var ck = vec3<f32>(0.0);
        if (held) {
            let tf = max(dot(F, rdb), 0.0);
            let df = length(F - rdb * tf);
            let wf = max(5.0, tf * 0.0016);
            let ocf = pk_occ(tf, scene_len, sky, cloud);
            let fan = df / max(tf, 1.0);
            ck = ((PK_WHITE * exp(-pow(df / (wf * 1.1), 2.0)) * 1.4 + PK_ARC * exp(-df / (wf * 3.0)) * 0.6) * (5.0 / wf)
                + PK_ARC * exp(-fan / 0.006) * 0.12 * select(0.0, 1.0, tf > 0.0)) * ocf;
            for (var j = 0; j < 3; j = j + 1) {
                let sj = pcg(si + u32(j) * 0x3d1u + u32(time * 20.0) * 0x9e37u);
                let hv = vec3<f32>(pcg3d(vec3<u32>(sj, 4u, 2u))) * (1.0 / 4294967295.0);
                let ta = fa[i] + (hv.x - 0.5) * 0.9;
                let dir = normalize((re1 * cos(ta) + re2 * sin(ta)) * RR + rn * (hv.y - 0.5) * 60.0 - (F - NX0));
                let ma = pk_bolt(rdb, F, F + dir * (40.0 + 70.0 * hv.z), 1.0, sj, 7, 1.4, 0.0, 0.8 * k, time, scene_len, sky, cloud);
                ck = ck + (PK_WHITE * ma.x * 0.8 + PK_ARC * ma.y * 0.8) * (1.0 - ma.z * 0.7);
            }
        }
        add = add + (c * Lb + ck * min(Lb, 2.5)) * k;
    }

    // ---- the ring: lit round from where each beam feeds it until it closes, a band of light with a white-hot outer
    //      edge, a lit inner edge and a turbulent body, runes turning on it, energy racing round; filling with light as
    //      they fuse; met where the view ray crosses its plane, so it is a clean ellipse from anywhere ----------------
    let ring_vis = saturate(fed * 2.0) * (1.0 - smoothstep(PK_FALL - 0.05, PK_FALL + 0.05, time)) * f32(!popped);
    let tcn = dot(NX, rd);
    let lum_n = Rn / 14.0;
    if (ring_vis > 0.0 && RR > 1.0) {
        let dn = dot(rd, rn);
        let tpl = dot(NX0, rn) / select(dn, 1.0e-4, abs(dn) < 1.0e-4);
        if (tpl > 0.0) {
            let X = rd * tpl - NX0;
            let rr = length(X);
            let th = atan2(dot(X, re2), dot(X, re1));
            // (a pixel, in the ring's plane: every line is at least that wide, so nothing shimmers)
            let fp = max(tpl * 0.0013, 0.3) / max(abs(dn), 0.1);
            let rho = rr - RR;
            // (its width uneven round it, churning)
            let W = (24.0 + 10.0 * charge) * (0.7 + 0.6 * gnoise2(vec2<f32>(th * 4.0 + spin * 0.5, seed)));
            if (rho > -W - 40.0 - fp * 4.0 && rho < 90.0 + fp * 4.0) {
                // how much of it is lit at this angle: each beam's arc running on round from where it feeds, gathering
                // speed, a white-hot head leading it; each feed point flaring as its beam strikes
                var lit = 0.0;
                var lit_soft = 0.0;                             // (the same, its ends soft: for the haze round it)
                var lead = 0.0;
                for (var i = 0; i < PK_N; i = i + 1) {
                    let dt = time - (em[i].w + PK_SHOOT - 0.03);
                    if (dt <= 0.0) {
                        continue;
                    }
                    let reach = PK_RING_V * dt * (1.0 + 0.6 * dt);
                    var d = th - fa[i];
                    d = d - TAU * floor(d / TAU);
                    lit = max(lit, smoothstep(reach + 0.03, reach - 0.03, d));
                    let ds = select(d, d - TAU, d > TAU - 0.4);
                    lit_soft = max(lit_soft, smoothstep(-0.35, 0.0, ds) * smoothstep(reach + 0.35, reach - 0.05, ds));
                    lead = max(lead, exp(-pow((d - reach) / 0.05, 2.0)) * (1.0 - smoothstep(TAU * 0.6, TAU, reach)));
                    lead = max(lead, exp(-pow(min(d, TAU - d) / 0.04, 2.0)) * (0.35 + 1.5 * exp(-dt * 4.0)) * power);
                }
                let lw = max(2.2, fp);
                let edge = exp(-pow(rho / lw, 2.0)) * (2.2 / lw);
                let iw = max(1.4, fp);
                let inner = exp(-pow((rho + W) / iw, 2.0)) * (1.4 / iw);
                let body = smoothstep(-W - fp, -W + fp, rho) * smoothstep(fp, -fp, rho);
                // a band of plasma churning round, threads of lightning crawling over it (in stretches, a new path every
                // frame of film or so), its outer edge white-hot and uneven
                let flowr = gnoise2(vec2<f32>(th * RR * 0.03 - spin * 4.0, rho * 0.08 + seed));
                var arcs = 0.0;
                let fw = max(0.9, fp);
                for (var f = 0; f < 3; f = f + 1) {
                    let sf = pcg(u32(seed) + u32(f) * 0x51u + u32(time * 14.0 + f32(f) * 0.33) * 0x9e37u);
                    let x = th * RR / 16.0;
                    let y = -W * 0.5 + W * 0.45 * (pk_jg(x, sf) * 0.7 + pk_jg(x * 3.1, sf ^ 0x77u) * 0.3);
                    let on = smoothstep(0.1, 0.3, pk_jg(x * 0.09, sf ^ 0x1234u) * 0.5 + 0.5 - 0.2);
                    arcs = arcs + exp(-pow((rho - y) / fw, 2.0)) * (0.9 / fw) * on;
                }
                let haze = exp(-max(rho, 0.0) / 45.0) * exp(-max(-rho - W, 0.0) / 30.0);
                let level = (0.55 + 0.6 * charge + 0.5 * burn + 0.5 * unstable * (0.5 + 0.5 * sin(time * 47.0))) * ring_vis;
                var c = pk_heat(1.0) * edge * (0.35 + 1.0 * flowr * flowr) + pk_heat(0.75) * inner * 0.25
                    + pk_heat(0.25 + 0.35 * flowr) * body * (0.2 + 0.4 * flowr * flowr)
                    + (PK_WHITE * 0.4 + PK_ARC) * arcs * (0.5 + 0.8 * charge + 0.5 * burn + 1.5 * lock);
                c = c * lit + pk_heat(0.1) * haze * 0.35 * lit_soft + PK_WHITE * lead * (edge * 0.4 + body * 0.25) * 2.0
                    + pk_heat(0.2) * (1.0 - lit) * edge * 0.08 * saturate(fed);
                add = add + c * level * pk_occ(tpl, scene_len, sky, cloud) * k;
            }
            // as they fuse it fills with light, swirling in to its middle
            let fill = fuse * (0.9 * select(1.0, exp(-merge_t * 1.2), merged) + 0.22 * burn) * (1.0 - crush);
            if (fill > 0.001 && rho < -W) {
                let sw = gfbm2(vec2<f32>(th * 2.0 + rr * 0.02 - time * 1.4, rr * 0.03 - time * 0.9));
                let dsc = fill * (0.3 + 0.7 * sw) * (0.35 + 0.65 * saturate(1.0 - rr / RR)) * smoothstep(-W, -W - 15.0, rho);
                add = add + pk_heat(0.25 + 0.45 * sw * fill) * dsc * 0.5 * ring_vis * pk_occ(tpl, scene_len, sky, cloud) * k;
            }
        }
    }
    // ---- its middle: the white-hot heart the beam is fired from, and the ring crushed into it, falling ----------
    if (Rn > 0.01 && tcn > 0.0) {
        let dcn = length(NX - rd * tcn);
        let occ = pk_occ(tcn - Rn, scene_len, sky, cloud);
        let wpx = max(Rn, tcn * 0.0016);
        let en = Rn / wpx;
        let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
        let hy = cross(hx, rd);
        let o = rd * tcn - NX;
        let ang = atan2(dot(o, hy), dot(o, hx));
        let surf = gfbm2(vec2<f32>(ang * 2.5 + seed, dcn / wpx * 1.5 - time * 3.0));
        // (a hard white core, a thin rim of blue fire round it, a little haze: a star, not a blur)
        let core = 1.0 - smoothstep(wpx * 0.9, wpx * 1.0, dcn * (0.94 + 0.12 * surf));
        let rim = exp(-pow((dcn - wpx) / (wpx * 0.12), 2.0));
        var star = pk_heat(1.0) * 0.9 * core + pk_heat(0.7) * rim * (0.6 + 0.5 * surf) * en
            + pk_heat(0.45) * exp(-max(dcn - wpx, 0.0) / (wpx * 0.35)) * (0.3 + 0.4 * surf) * en
            + pk_heat(0.1) * exp(-dcn / (wpx * 3.0)) * 0.5 * en;
        if (fall > 0.0) {
            // falling: its trail down the line of the beam
            let q = ray_seg(rd, NX, NX + vec3<f32>(0.0, 120.0 * fall, 0.0));
            let wq = max(2.0, q.y * 0.0013);
            star = star + pk_heat(0.6) * exp(-pow(q.x / wq, 2.0)) * (3.0 / wq) * (1.0 - q.z) * fall;
        }
        add = add + star * occ * k;
    }

    // ---- as they fuse: a ring of fire tearing out through the sky, and the sky cracking open from the nexus -------
    if (merged && merge_t < 6.0) {
        let tp = NX.y / select(rd.y, 1.0e-5, abs(rd.y) < 1.0e-5);
        if (tp > 0.0) {
            let pp = rd * tp;
            let rr = length(pp.xz - NX.xz);
            let ap = atan2(pp.z - NX.z, pp.x - NX.x);
            let R = 1400.0 * (1.0 - exp(-merge_t * 0.9));
            let th = 5.0 + 22.0 * merge_t;
            var ring = exp(-pow((rr - R) / th, 2.0)) * exp(-merge_t * 1.5) * saturate(0.2 + 1.1 * gfbm2(vec2<f32>(ap * 9.0, rr * 0.004 + seed)));
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
            ring = ring + exp(-pow(lat / wc, 2.0)) * smoothstep(reach, reach - 200.0, rr) * smoothstep(RR * 0.9, RR * 1.3, rr) * exp(-merge_t * 1.8) * 1.6;
            let wfar = max(1.0, tp * 0.002);
            // (not edge on, where it would only be a line across the sky)
            add = add + (PK_ARC * 0.7 + PK_WHITE * 0.12) * ring * min(1.0, 30.0 / wfar) * smoothstep(0.03, 0.12, abs(rd.y)) * pk_occ(tp, scene_len, sky, cloud) * k;
        }
    }

    // ---- once they have fused, a bolt feeling its way down from the ring's middle to the target, branching, and
    //      streamers reaching up off the land to meet it; the beam pours down the path it opens ----------------------
    let dl_t = time - (PK_MERGE + 0.15);
    if (dl_t > 0.0 && time < PK_DROP + 0.3) {
        let G = crel - vec3<f32>(0.0, 1.0, 0.0);
        let dl = dl_t * PK_SHOOT / (PK_DROP - PK_MERGE - 0.15);
        let hd = pk_lead(dl, 3.0);
        let si = pcg(u32(seed) * 13u + 77u);
        let lv = select(0.3 + 0.4 * smoothstep(PK_CREEP, PK_SHOOT, dl), 3.0 * exp(-(time - PK_DROP) * 9.0), time > PK_DROP);
        let bo = pk_bolt(rdb, NX, G, hd, si, 24, 0.7, 0.0, 1.6 * k, time, scene_len, sky, cloud);
        var c = PK_WHITE * bo.x + PK_ARC * bo.y;
        if (time < PK_DROP) {
            let hp = pk_bolt_at(NX, G, hd, si, 24, 0.7);
            let th = max(dot(hp, rdb), 0.0);
            let dh = length(hp - rdb * th);
            let wh = max(2.0, th * 0.0013);
            c = c + (PK_WHITE * exp(-pow(dh / (wh * 1.2), 2.0)) * 1.5 + PK_ARC * exp(-dh / (wh * 6.0)) * 0.5) * (2.0 / wh) * pk_occ(th, scene_len, sky, cloud) * 3.0;
        }
        for (var j = 0; j < 3; j = j + 1) {
            let sbj = pcg(si + u32(j) * 0x2545u);
            let hv = vec3<f32>(pcg3d(vec3<u32>(sbj, 9u, 1u))) * (1.0 / 4294967295.0);
            let ub = 0.05 + 0.28 * hv.x;
            let bh = saturate((min(hd, 0.36) - ub) / (0.07 + 0.08 * hv.y));
            if (bh > 0.0) {
                let O = pk_bolt_at(NX, G, ub, si, 24, 0.7);
                let ba = hv.z * TAU;
                let dir = normalize(vec3<f32>(cos(ba) * (0.6 + 0.6 * hv.y), -1.0, sin(ba) * (0.6 + 0.6 * hv.y)));
                let bb = pk_bolt(rdb, O, O + dir * (40.0 + 70.0 * hv.y), bh, sbj, 8, 1.5, 0.0, 1.0 * k, time, scene_len, sky, cloud);
                c = c + (PK_WHITE * bb.x * 0.7 + PK_ARC * bb.y * 0.8) * (1.0 - 0.6 * bb.z);
            }
        }
        // (the streamers: thin sparks reaching up off the land round the target, flickering, in the last moments)
        let st = smoothstep(PK_DROP - 0.4, PK_DROP - 0.1, time) * (1.0 - smoothstep(PK_DROP, PK_DROP + 0.1, time));
        if (st > 0.0) {
            for (var j = 0; j < 4; j = j + 1) {
                let sj = pcg(u32(seed) * 7u + u32(j) * 0x61u);
                let hv = vec3<f32>(pcg3d(vec3<u32>(sj, 2u, 8u))) * (1.0 / 4294967295.0);
                let a0 = hv.x * TAU;
                let O = crel + vec3<f32>(cos(a0), 0.0, sin(a0)) * (6.0 + 30.0 * hv.y);
                let fl = step(0.3, mh(u32(time * 30.0), sj, 3u));
                let bb = pk_bolt(rdb, O, O + vec3<f32>((hv.z - 0.5) * 20.0, 20.0 + 35.0 * hv.z, (hv.y - 0.5) * 20.0), st, sj, 8, 2.2, 1.0, 0.3 * k, time, scene_len, sky, cloud);
                c = c + (PK_WHITE * bb.x * 0.5 + PK_ARC * bb.y * 0.6) * fl * (1.0 - 0.6 * bb.z);
            }
        }
        add = add + c * lv * k;
    }

    // ---- the beam: down from the ring's middle onto the target, a white core inside a blue sheath, strands wound round it ----
    if (burn > 0.001) {
        let G = crel - vec3<f32>(0.0, 14.0, 0.0);
        let xh = saturate((time - PK_DROP) / (PK_HIT - PK_DROP));
        let xt = saturate((time - PK_CUT - PK_DRAIN * 0.5) / 0.4);
        let u_head = xh * xh;
        let u_top = xt * xt;
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
            let halo = (exp(-dd / (rc * 4.0)) + exp(-dd / max(q.y, 1.0) / 0.05) * 0.1) * (1.0 - smoothstep(w * 25.0, w * 40.0, dd));
            var strands = 0.0;
            let axis = A + (B - A) * q.z;
            // (lightning crawling over it: jagged arcs wound round it in stretches, a new one every frame of film or so)
            for (var s = 0; s < 4; s = s + 1) {
                let sk = pcg(u32(seed) * 3u + u32(s) * 0x9e1u + u32(time * 18.0 + f32(s) * 0.27) * 0x632bu);
                let hv = vec3<f32>(pcg3d(vec3<u32>(sk, 6u, 6u))) * (1.0 / 4294967295.0);
                let a0 = hv.x * lenb;
                let al = 50.0 + 130.0 * hv.y;
                let on = smoothstep(a0, a0 + 8.0, along) * smoothstep(a0 + al, a0 + al - 8.0, along);
                if (on <= 0.0) {
                    continue;
                }
                let ph = hv.z * TAU + along * 0.02 * select(-1.0, 1.0, hv.x > 0.5) + pk_jg(along / 9.0, sk) * 0.9;
                let hp = axis + (e1 * cos(ph) + e2 * sin(ph)) * rc * (1.35 + 0.45 * pk_jg(along / 6.0, sk ^ 0x5bu));
                let th = max(dot(hp, rdb), 0.0);
                let wh = max(rc * 0.1, th * 0.0012);
                strands = strands + exp(-pow(length(hp - rdb * th) / wh, 2.0)) * (rc * 0.1 / wh) * on * select(1.0, 1.0 - smoothstep(scene_len - 0.8, scene_len + 0.8, th), !sky);
            }
            var b = (PK_WHITE * core * (1.0 + 0.6 * pulse) + PK_HOT * inner * (0.28 + 0.6 * pulse) + PK_DEEP * outer * 0.4) * e;
            // the head of it, blazing, on its way down
            b = b + PK_WHITE * exp(-pow((q.z - 1.0) * (u_head - u_top) * lenb / 10.0, 2.0)) * core * 1.5 * (1.0 - step(1.0, u_head));
            // (its strands wind out of it below the ring, not round its heart)
            strands = strands * smoothstep(40.0, 110.0, along);
            add = add + (b * vis + halo * PK_DEEP * 0.12 * e * vis_mix + (PK_ARC * 0.8 + PK_WHITE * 0.45) * strands * 2.2) * burn * k;
        }
        // the fireball where the land burst, boiling; it settles round the foot of the beam
        if (burst) {
            let Rf = (70.0 + 130.0 * exp(-bt * 0.6) * (1.0 - exp(-bt * 6.0))) * (0.93 + 0.07 * sin(time * 13.0));
            let cf = crel + vec3<f32>(0.0, Rf * 0.25, 0.0);
            let tcp = dot(cf, rd);
            // (a dome, flattened against the land)
            let dc = length((rd * max(tcp, 0.0) - cf) * vec3<f32>(1.0, 1.7, 1.0));
            if (dc < Rf * 4.0 && tcp > 0.0) {
                let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
                let hy = cross(hx, rd);
                let on = rd * tcp - cf;
                let ang = atan2(dot(on, hy), dot(on, hx));
                let nz = gfbm2(vec2<f32>(ang * 1.3 + seed, dc / Rf * 2.0 - time * 2.5));
                let fire = exp(-pow(dc / (Rf * (0.75 + 0.5 * nz)), 2.0));
                // plasma, white-hot at its heart, the land burning orange under it, a crust of smoke round its edge
                let heat = fire * (0.4 + 0.6 * exp(-dc / (Rf * 0.3)));
                let low = exp(-max((rd * max(tcp, 0.0) - crel).y, 0.0) / 12.0);
                // (seen from inside it, only its heart: it does not fog the whole view)
                let visf = select(1.0, smoothstep(tcp - Rf * 1.3, tcp - Rf * 0.2, scene_len), !sky) * mix(smoothstep(0.0, 0.5, heat), 1.0, smoothstep(Rf * 0.8, Rf * 1.8, length(cf)));
                col = mix(col, vec3<f32>(0.04, 0.04, 0.05), smoothstep(0.05, 0.5, fire) * (1.0 - heat) * 0.6 * visf * burn * k);
                add = add + (PK_WHITE * 0.25 * heat * heat + PK_HOT * 0.45 * heat * (1.0 + 0.6 * nz) + PK_DEEP * fire * 0.3
                    + lava_ramp(0.45 + 0.5 * heat) * fire * low * 1.4) * visf * burn * k;
                add = add + vec3<f32>(1.2, 1.2, 1.6) * exp(-dc / Rf) * 0.12 * (1.0 - smoothstep(Rf * 2.5, Rf * 4.0, dc)) * smoothstep(Rf, Rf * 3.0, length(cf)) * burn * visf * k;
            }
        }
    }

    // ---- the nexus bursting in the crater: a ball of fire and plasma swelling out of it, the mushroom climbing out of it --
    if (popped && mt < 5.0) {
        let Rp = (45.0 + 135.0 * (1.0 - exp(-mt * 3.0))) * (0.95 + 0.05 * sin(time * 17.0));
        let cf = crel + vec3<f32>(0.0, Rp * 0.3 + 40.0 * mt, 0.0);
        let tcp = dot(cf, rd);
        let dc = length((rd * max(tcp, 0.0) - cf) * vec3<f32>(1.0, 1.3, 1.0));
        if (dc < Rp * 2.0) {
            let hx = normalize(cross(rd, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1.0e-4, 0.0, 0.0));
            let on = rd * tcp - cf;
            let nz = gfbm2(vec2<f32>(atan2(dot(on, cross(hx, rd)), dot(on, hx)) * 1.4 + seed, dc / Rp * 2.0 - time * 2.0));
            let fire = exp(-pow(dc / (Rp * (0.7 + 0.5 * nz)), 2.0)) * exp(-mt / 1.2) * (1.0 - smoothstep(3.5, 5.0, mt));
            let visf = select(1.0, smoothstep(tcp - Rp * 1.3, tcp - Rp * 0.2, scene_len), !sky) * select(0.0, 1.0, tcp > 0.0)
                * mix(smoothstep(0.3, 0.8, fire), 1.0, smoothstep(Rp * 0.8, Rp * 1.8, length(cf)));
            add = add + (lava_ramp(0.35 + 0.6 * fire) * fire * 2.4 + PK_HOT * fire * fire * 1.5 * exp(-mt * 2.0)) * visf * k
                * mix(0.35, 1.0, smoothstep(Rp * 0.8, Rp * 1.8, length(cf)));
        }
    }

    // ---- debris spiralling up round the beam, and molten rock thrown out of the crater, the crater still erupting ----
    let sp_q = ray_seg(rd, crel, crel + vec3<f32>(0.0, 300.0, 0.0));
    if (burst && sp_q.x < 340.0) {
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
                let rr = 30.0 + 50.0 * hv.x;
                let w0 = (1.2 + 1.5 * hv.y) * select(-1.0, 1.0, hv.z > 0.5);
                let vy = 35.0 + 50.0 * hv.z;
                let a1 = max(a - 0.08, 0.0);
                pa = crel + vec3<f32>(cos(hv.y * TAU + w0 * a) * rr, vy * a, sin(hv.y * TAU + w0 * a) * rr);
                pb = crel + vec3<f32>(cos(hv.y * TAU + w0 * a1) * rr, vy * a1, sin(hv.y * TAU + w0 * a1) * rr);
            } else {
                let az = hv.x * TAU;
                let vh = 25.0 + 60.0 * hv.y;
                let vy = 35.0 + 55.0 * hv.z;
                let s3 = crel + vec3<f32>(cos(az) * 20.0, 2.0, sin(az) * 20.0);
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
    if (burst && bt < 5.0) {
        let Rs = pk_shock_r(bt);
        let tcs = dot(crel, rd);
        let ps = rd * max(tcs, 0.0) - crel;
        let dcs = length(ps);
        let th = 8.0 + 25.0 * bt;
        let wpx = max(th, max(tcs, 1.0) * 0.002);
        // (a faint pale shell, as a shock front is seen by the haze it condenses, soft and broken)
        let brk = 0.5 + 0.8 * gnoise2(vec2<f32>(atan2(ps.z, ps.x) * 6.0, ps.y * 0.02 + seed));
        let limb = exp(-pow((dcs - Rs) / wpx, 2.0)) * (th / wpx) * smoothstep(-5.0, 10.0, ps.y) * brk;
        add = add + vec3<f32>(0.4, 0.43, 0.5) * limb * 0.35 * exp(-bt * 1.6) * pk_occ(tcs, scene_len, sky, cloud) * k;
    }

    // ---- the lens: bloom round the ring's heart and the beam's foot, a long streak through the heart --------------
    if (pN.z > 0.0 && Rn > 0.01) {
        let dd = (uv - pN.xy) * vec2<f32>(aspect, 1.0);
        let l = lum_n * (0.6 + 0.5 * charge + 0.6 * burn) + select(0.0, exp(-merge_t * 4.0) * 1.5, merged) + lock * 0.8;
        add = add + PK_HOT * l / (1.0 + dot(dd, dd) * 600.0) * 0.25 * k;
    }
    if (pT.z > 0.0 && (burn > 0.001 || (popped && mt < 2.0))) {
        let dd = (uv - pT.xy) * vec2<f32>(aspect, 1.0);
        let l = burn + select(0.0, exp(-mt * 2.0) * 2.0, popped);
        add = add + vec3<f32>(1.2, 1.6, 2.6) * l / (1.0 + dot(dd, dd) * 400.0) * 0.25 * k;
    }
    add = add + vec3<f32>(2.2, 2.5, 3.2) * flash * flash * k;
    // (the sky lit up as the bolts strike)
    add = add + vec3<f32>(0.6, 0.65, 1.0) * min(strike_fl, 8.0) * 0.006 * select(0.5, 1.0, sky) * k;

    // ---- combine --------------------------------------------------------------
    var outc = col + add;
    let vg = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
    outc = outc * (1.0 - smoothstep(0.3, 1.0, vg) * (0.2 + 0.3 * dark) * k);
    // (tone-mapped so the brightest light keeps its colour: the filmic curve on its brightness, half on each channel)
    let lum_o = max(luminance(outc * 0.9), 1.0e-5);
    let hue = outc * 0.9 * (aces(vec3<f32>(lum_o)).x / lum_o);
    outc = mix(aces(outc * 0.9), hue / max(1.0, max(hue.r, max(hue.g, hue.b))), 0.45);
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
