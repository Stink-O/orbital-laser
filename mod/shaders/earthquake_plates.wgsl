// The Earthquake's plates: the one definition of them, plain functions and constants with no bindings. mod/build.rs puts
// this file before the world warp (shaders/earthquake_warp.wgsl) and before the post pass's own (shaders/earthquake.wgsl);
// strike/earthquake.rs's `EqPlates` mirrors it step for step (`eq_wgsl_in_step` holds the constants and the hashes to it).
//
// The land splits along a main fault and one side is thrust up into a cliff. In fault coordinates (u along the main
// fault, v across it, the up side v > 0; the level point pushed about by smooth noise first, `eq_bent`, then turned onto
// the fault and moved by the strike's (u0, v0)), the zone is a stadium EQ_CAP * reach long each side of its straight
// part and about `reach` round (a ragged rim, `eq_rim`). It is cut in bands parallel to the fault (four on the up side,
// three on the down side, `EQ_UP_EDGE`, `EQ_DN_EDGE`) and each band in three segments along it (the middle one out to
// EQ_SEG * reach each side): plate i is band i / 3 and segment i % 3, found in O(1) (`eq_cell`).
// Each plate has a whole-block offset (`eq_offset`, integer arithmetic only, so the plan and the shaders agree to the
// block): the up side in giant steps rising to the cliff at the fault, the canyon floor dropping on the other side, each
// side moving away from the fault (less each band out) and along it (the two sides opposite ways), the end segments half.
// Its share of that at t is the sum of its lurches (`eq_lurch`): the first heave at EQ_HEAVE, three as the plates work,
// the climax at EQ_CLIMAX; each with a hard start and an overshoot of about 8% that settles (`eq_ease`). Before the
// climax every plate shudders harder (`eq_build`). From EQ_STILL the displacement is exactly the whole-block offset
// (`rest`: the real land is moved there by EQ_REST); with the terrain left alone two more lurches set every plate back
// home by EQ_BACK_END.
// Everything that must agree exactly (offsets, lurch times and shares) comes from the strike's seed through u32 hashing
// (`eq_hash`), never from fract(sin()).

// ---- the beats, strike seconds (strike/earthquake.rs: EQ_*) ----------------------------------------------------------
const EQ_LEN: f32 = 50.0;          // the strike's length (lasers.rs)
const EQ_CRACK: f32 = 0.8;         // the main fault's crack starts racing out from the target
const EQ_CRACK_V: f32 = 110.0;     // blocks a second (faster when the zone is too big to be cut through by EQ_CRACK_BY)
const EQ_CRACK_BY: f32 = 5.5;      // every cut reached by now
const EQ_WARP_START: f32 = 5.6;    // the world warp on (nothing moves before the first heave)
const EQ_HEAVE: f32 = 6.0;         // the first heave: 35% of every plate's offset in about a second
const EQ_CLIMAX: f32 = 18.5;       // THE CLIMAX: the last 37% of the rise in one thrust
const EQ_STILL: f32 = 21.0;        // every plate exactly on its final place, still
const EQ_REST: f32 = 31.0;         // the real land in under the drawn land: the two swapped
const EQ_WARP_END: f32 = 31.0;     // the world warp off (the real land swapped in under it)
const EQ_BACK_END: f32 = 43.0;     // the terrain left alone: every plate back home, the warp off
// ---- the plates ------------------------------------------------------------------------------------------------------
const EQ_PLATES: i32 = 21;         // seven bands of three segments
const EQ_CAP: f32 = 0.45;          // the stadium's straight part, each side of the target, times the reach
const EQ_SEG: f32 = 0.75;          // the middle segment's half length, times the reach
const EQ_ROCK: f32 = 0.026;        // a slipping plate's rock: up to 1.5 degrees of vertical shear about its middle
const EQ_SHUD: f32 = 0.14;         // and its shudder, blocks
const EQ_OFF_SCALE: f32 = 1.0;     // the terrain left alone: the plates drawn at this share of their offsets
const EQ_K_CLIMAX: i32 = 4;        // the climax's number among the lurches
const EQ_K_HOME: i32 = 5;          // the first lurch back home's (the terrain left alone)
// ---- the build before the climax -------------------------------------------------------------------------------------
const EQ_BUILD_T: f32 = 14.0;      // every plate shuddering from here, harder and harder to the climax
const EQ_BUILD_SHUD: f32 = 0.06;   // blocks, at its hardest

const EQ_PI: f32 = 3.14159265;

// What the plates are made from: the warp builds it from its params, the post pass from its table.
struct EqCfg {
    seed: u32,
    reach: f32,
    pace: f32,
    fdir: vec2<f32>,        // the main fault's direction (unit), +u
    fi: vec2<i32>,          // the same as integers about 256 long (the offsets are worked out from these)
    slip_q: i32,            // the knobs `slip` and `heave`, hundredths
    heave_q: i32,
    rest: bool,             // the plates come to rest displaced (the real land is moved); else they ease back
    rider: i32,             // the plate the player stands on (kept from rocking by rider_k, 0 to 1), or -1
    rider_k: f32,
    prev: i32,              // the plate they stood on before (kept from rocking by prev_k while the view eases off it)
    prev_k: f32,
    shift: vec2<f32>,       // (u0, v0): the fault coordinates' origin from the target block's corner, whole blocks
}

// ---- hashing (u32, the same in strike/earthquake.rs) -------------------------------------------------------------------
fn eq_hash(x: u32) -> u32 {
    var h = x;
    h = h ^ (h >> 16u);
    h = h * 0x7feb352du;
    h = h ^ (h >> 15u);
    h = h * 0x846ca68bu;
    h = h ^ (h >> 16u);
    return h;
}
fn eq_h(seed: u32, a: u32, b: u32) -> u32 {
    return eq_hash(eq_hash(seed * 0x9e3779b1u + a) ^ (b * 0x85ebca77u + 0x165667b1u));
}
// 0 to 1 (exact in f32: 24 bits).
fn eq_u(h: u32) -> f32 {
    return f32(h >> 8u) / 16777216.0;
}
// Value noise, 0 to 1, smooth; `k` picks an independent field (one hash a lattice point: the warp runs it per vertex).
fn eq_lat(seed: u32, i: vec2<i32>, k: u32) -> f32 {
    return eq_u(eq_hash((bitcast<u32>(i.x) * 0x8da6b343u) ^ (bitcast<u32>(i.y) * 0xd8163841u) ^ (seed * 0x9e3779b1u + k * 0x85ebca77u)));
}
fn eq_vn(seed: u32, p: vec2<f32>, k: u32) -> f32 {
    let fl = floor(p);
    let i = vec2<i32>(fl);
    let f = p - fl;
    let u = f * f * (3.0 - 2.0 * f);
    let a = eq_lat(seed, i, k);
    let b = eq_lat(seed, i + vec2<i32>(1, 0), k);
    let c = eq_lat(seed, i + vec2<i32>(0, 1), k);
    let d = eq_lat(seed, i + vec2<i32>(1, 1), k);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ---- where the plates are -----------------------------------------------------------------------------------------------
// A level point (blocks from the target block's corner, x and z) pushed about by smooth noise: up to 7 blocks at a
// 90-block scale and 2 at 22, so the faults run as natural traces, not ruler lines (its slope stays under about a half,
// so a distance in fault coordinates is a true one to within that before strike/earthquake.rs corrects it).
fn eq_bent(c: EqCfg, p: vec2<f32>) -> vec2<f32> {
    let a = p * (1.0 / 90.0);
    let b = p * (1.0 / 22.0);
    let n1 = vec2<f32>(eq_vn(c.seed, a, 1u), eq_vn(c.seed, a, 2u)) - 0.5;
    let n2 = vec2<f32>(eq_vn(c.seed, b, 3u), eq_vn(c.seed, b, 4u)) - 0.5;
    return p + n1 * 14.0 + n2 * 4.0;
}
// A bent point in fault coordinates: (u along the fault, v across it, the up side positive).
fn eq_uv(c: EqCfg, q: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(dot(q, c.fdir), dot(q, vec2<f32>(-c.fdir.y, c.fdir.x))) - c.shift;
}
// The zone's ragged rim at bent point q: its radius round the stadium's straight part there.
fn eq_rim(c: EqCfg, q: vec2<f32>) -> f32 {
    return c.reach * (0.93 + 0.14 * eq_vn(c.seed, q * (1.0 / 90.0), 5u));
}
// The bands' edges across the fault, times the reach: the up side's (from the fault out; the last band runs to the rim)
// and the down side's.
const EQ_UP_E1: f32 = 0.2125;
const EQ_UP_E2: f32 = 0.4625;
const EQ_UP_E3: f32 = 0.73125;
const EQ_DN_E1: f32 = 0.225;
const EQ_DN_E2: f32 = 0.6;
struct EqWhere {
    plate: i32,             // 0 to EQ_PLATES - 1, or -1: fixed land
    edge: f32,              // in fault coordinates, to the nearest boundary: another plate's, or the rim
    kind: i32,              // which that is: 0 the main fault, 1 a band's edge, 2 a segment's, 3 the rim
}
// The cell of fault point w, the rim there `rim`.
fn eq_cell(c: EqCfg, w: vec2<f32>, rim: f32) -> EqWhere {
    let r = c.reach;
    let cap = length(vec2<f32>(max(abs(w.x) - EQ_CAP * r, 0.0), w.y));
    if (cap >= rim) {
        return EqWhere(-1, cap - rim, 3);
    }
    var band = 0;
    var lo = 0.0;
    var hi = 1.0e9;
    if (w.y >= 0.0) {
        let a = w.y;
        if (a < EQ_UP_E1 * r) {
            band = 0;
            lo = a;
            hi = EQ_UP_E1 * r - a;
        } else if (a < EQ_UP_E2 * r) {
            band = 1;
            lo = a - EQ_UP_E1 * r;
            hi = EQ_UP_E2 * r - a;
        } else if (a < EQ_UP_E3 * r) {
            band = 2;
            lo = a - EQ_UP_E2 * r;
            hi = EQ_UP_E3 * r - a;
        } else {
            band = 3;
            lo = a - EQ_UP_E3 * r;
        }
    } else {
        let a = -w.y;
        if (a < EQ_DN_E1 * r) {
            band = 4;
            lo = a;
            hi = EQ_DN_E1 * r - a;
        } else if (a < EQ_DN_E2 * r) {
            band = 5;
            lo = a - EQ_DN_E1 * r;
            hi = EQ_DN_E2 * r - a;
        } else {
            band = 6;
            lo = a - EQ_DN_E2 * r;
        }
    }
    let s = EQ_SEG * r;
    var seg = 1;
    var ds = min(w.x + s, s - w.x);
    if (w.x < -s) {
        seg = 0;
        ds = -s - w.x;
    } else if (w.x > s) {
        seg = 2;
        ds = w.x - s;
    }
    var e = lo;
    var kind = select(1, 0, band == 0 || band == 4);
    if (hi < e) {
        e = hi;
        kind = 1;
    }
    if (ds < e) {
        e = ds;
        kind = 2;
    }
    if (rim - cap < e) {
        e = rim - cap;
        kind = 3;
    }
    return EqWhere(band * 3 + seg, e, kind);
}
// Which plate the level point p (blocks from the target block's corner) lies on, and how far (in fault coordinates)
// it is from the nearest boundary.
fn eq_where(c: EqCfg, p: vec2<f32>) -> EqWhere {
    let q = eq_bent(c, p);
    return eq_cell(c, eq_uv(c, q), eq_rim(c, q));
}
fn eq_plate(c: EqCfg, p: vec2<f32>) -> i32 {
    return eq_where(c, p).plate;
}
// Plate i's middle in fault coordinates (what it rocks about).
fn eq_mid(c: EqCfg, i: i32) -> vec2<f32> {
    let r = c.reach;
    var vm = array<f32, 7>(0.5 * EQ_UP_E1, 0.5 * (EQ_UP_E1 + EQ_UP_E2), 0.5 * (EQ_UP_E2 + EQ_UP_E3), 0.5 * (EQ_UP_E3 + 1.0), -0.5 * EQ_DN_E1, -0.5 * (EQ_DN_E1 + EQ_DN_E2), -0.5 * (EQ_DN_E2 + 1.0));
    let s = i % 3;
    let um = select(0.0, select(-1.0, 1.0, s == 2) * 0.5 * (EQ_SEG + EQ_CAP + 1.0), s != 1);
    return vec2<f32>(um, vm[i / 3]) * r;
}

// ---- how each plate moves -----------------------------------------------------------------------------------------------
// a / b rounded to the nearest, halves away from zero (b > 0); i32 division truncates in WGSL as in Rust.
fn eq_rdiv(a: i32, b: i32) -> i32 {
    if (a >= 0) {
        return (a + b / 2) / b;
    }
    return -((-a + b / 2) / b);
}
// Plate i's offset at rest, whole blocks. Its rise (the up side's bands from the fault out 54, 38, 22, 8; the down
// side's -38, -14, -5; a block or two of jitter) times `heave`; away from the fault (10, 7, 4, 1 and 9, 6, 3) and along
// it (6, the two sides opposite ways) times `slip`; the end segments half of each. Fixed land: none.
fn eq_offset(c: EqCfg, i: i32) -> vec3<i32> {
    if (i < 0 || i >= EQ_PLATES) {
        return vec3<i32>(0);
    }
    var rises = array<i32, 7>(54, 38, 22, 8, -38, -14, -5);
    var aways = array<i32, 7>(10, 7, 4, 1, 9, 6, 3);
    let b = i / 3;
    let up = b < 4;
    var rise = rises[b];
    var away = aways[b];
    var along = select(-6, 6, up);
    if (i % 3 != 1) {
        rise = eq_rdiv(rise, 2);
        away = eq_rdiv(away, 2);
        along = along / 2;
    }
    let h = eq_h(c.seed, 100u + u32(i), 7u);
    rise = rise + select(i32(h % 3u) - 1, i32(h % 5u) - 2, abs(rise) >= 20);
    let aw = select(-away, away, up) * c.slip_q;
    let al = along * c.slip_q;
    let x = eq_rdiv(al * c.fi.x - aw * c.fi.y, 25600);
    let z = eq_rdiv(al * c.fi.y + aw * c.fi.x, 25600);
    return vec3<i32>(x, eq_rdiv(rise * c.heave_q, 100), z);
}
struct EqLurch {
    t: f32,                 // when it starts, strike seconds
    w: f32,                 // its share of the plate's offset (the last two negative when the plates ease back)
    d: f32,                 // how long it takes, seconds
    s: f32,                 // the way it rocks the plate (+-1)
}
// How many lurches a plate has: the first heave, three as the plates work, the climax; and with the terrain left alone
// two more back home.
fn eq_lurches(c: EqCfg) -> i32 {
    return select(7, EQ_K_HOME, c.rest);
}
// Plate i's lurch k (0 the first heave, 1-3 the plates working, EQ_K_CLIMAX the climax, EQ_K_HOME on back home with the
// terrain left alone).
fn eq_lurch(c: EqCfg, i: i32, k: i32) -> EqLurch {
    var base = array<f32, 7>(6.0, 8.5, 11.0, 13.5, 18.5, 33.5, 38.4);
    var share = array<f32, 7>(0.35, 0.12, 0.1, 0.06, 0.37, -0.6, -0.4);
    var long = array<f32, 7>(1.2, 1.2, 1.1, 0.9, 1.4, 3.6, 3.6);
    let ku = u32(k);
    // (the plates' order in each lurch a permutation of the 21: never two at once)
    var units = array<u32, 12>(1u, 2u, 4u, 5u, 8u, 10u, 11u, 13u, 16u, 17u, 19u, 20u);
    let hk = eq_h(c.seed, 20u, ku);
    let a = units[hk % 12u];
    let rank = f32((u32(i) * a + (hk >> 8u) % 21u) % 21u) - 10.0;
    // (one hash a plate and lurch for the rest: the warp works this out for every vertex)
    let hp = eq_h(c.seed, 22u + u32(i), ku);
    var t = base[k];
    var d = long[k];
    if (k == 0 || k == EQ_K_CLIMAX) {
        t = t + rank * 0.012;
    } else {
        t = t + rank * 0.037 + (eq_u(hp) - 0.5) * 0.04;
        d = d * (0.9 + 0.2 * f32(hp & 255u) / 255.0);
    }
    let end = select(EQ_STILL, EQ_BACK_END, k >= EQ_K_HOME);
    d = min(d * c.pace, end - 0.05 - t);
    return EqLurch(t, share[k], d, select(-1.0, 1.0, (hp & 256u) == 0u));
}
// One lurch's share of its weight u of the way through it: 0 at 0, 1 from 1, a hard start (its speed peaking about a
// sixth of the way through, from none), an overshoot of about 8% halfway that settles from above, no velocity jump at
// either end. The very last lurch home has none: it settles the land back exactly where it was.
fn eq_ease(u: f32) -> f32 {
    if (u <= 0.0) {
        return 0.0;
    }
    if (u >= 1.0) {
        return 1.0;
    }
    let a = 1.0 - u;
    let a2 = a * a;
    return 1.0 + a2 * a2 * (-1.0 - 4.0 * u + 17.0 * u * u);
}
fn eq_ease_last(u: f32) -> f32 {
    let x = clamp(u, 0.0, 1.0);
    return x * x * x * (x * (6.0 * x - 15.0) + 10.0);
}
fn eq_ease_k(k: i32, u: f32) -> f32 {
    if (k == EQ_K_HOME + 1) {
        return eq_ease_last(u);
    }
    return eq_ease(u);
}
// Plate i's share of its offset at t (0 before its first lurch; from EQ_STILL exactly 1, with the terrain left alone
// until its lurches home, and exactly 0 from EQ_BACK_END).
fn eq_share(c: EqCfg, i: i32, t: f32) -> f32 {
    if (!c.rest && t >= EQ_BACK_END) {
        return 0.0;
    }
    var s = 0.0;
    var k0 = 0;
    var k1 = EQ_K_HOME;
    if (t >= EQ_STILL) {
        s = 1.0;
        k0 = EQ_K_HOME;
        k1 = eq_lurches(c);
    }
    for (var k = k0; k < k1; k = k + 1) {
        let l = eq_lurch(c, i, k);
        s = s + l.w * eq_ease_k(k, (t - l.t) / l.d);
    }
    return s;
}
// The build before the climax, 0 to 1: growing from EQ_BUILD_T to the climax, gone over the climax's thrust, nothing
// from EQ_STILL.
fn eq_build(t: f32) -> f32 {
    let g = smoothstep(EQ_BUILD_T, EQ_CLIMAX, t);
    return g * g * (1.0 - smoothstep(EQ_CLIMAX + 0.2, EQ_STILL - 0.6, t));
}
// Plate i's motion at t in one walk over its lurches: x its share of its offset (eq_share), y how hard it slips (0 to
// 1: its shudder, the dust and the rubble to come), z its rock (radians of vertical shear about its middle). Still from
// EQ_STILL until any lurch home.
fn eq_motion(c: EqCfg, i: i32, t: f32) -> vec3<f32> {
    if ((c.rest && t >= EQ_STILL) || t >= EQ_BACK_END || t < EQ_HEAVE - 0.5) {
        return vec3<f32>(eq_share(c, i, t), 0.0, 0.0);
    }
    var s = 0.0;
    var slip = 0.0;
    var a = 0.0;
    var k0 = 0;
    var k1 = EQ_K_HOME;
    if (t >= EQ_STILL) {
        s = 1.0;
        k0 = EQ_K_HOME;
        k1 = eq_lurches(c);
    }
    for (var k = k0; k < k1; k = k + 1) {
        let l = eq_lurch(c, i, k);
        let u = (t - l.t) / l.d;
        s = s + l.w * eq_ease_k(k, u);
        if (u > 0.0 && u < 1.0) {
            let b = sin(EQ_PI * u);
            let m = b * b * min(abs(l.w) / 0.15, 1.0);
            slip = slip + m;
            a = a + l.s * m;
        }
    }
    let rigid = min(select(0.0, c.rider_k, i == c.rider) + select(0.0, c.prev_k, i == c.prev), 1.0);
    let rock = EQ_ROCK * clamp(a, -1.0, 1.0) * (1.0 - rigid);
    return vec3<f32>(s, min(slip, 1.0), rock);
}
// The way plate i rocks about (unit, in fault coordinates).
fn eq_rock_dir(c: EqCfg, i: i32) -> vec2<f32> {
    let a = 6.2831853 * eq_u(eq_h(c.seed, 90u + u32(i), 0u));
    return vec2<f32>(cos(a), sin(a));
}
// Where a point of plate i, at fault point w, is drawn at t, from where it is: its plate's share of its offset, its rock
// about its middle and its shudder (while it slips, and the build's before the climax, each plate on its own phase).
// From EQ_STILL exactly the whole-block offset (or none from EQ_BACK_END).
fn eq_disp(c: EqCfg, i: i32, t: f32, w: vec2<f32>) -> vec3<f32> {
    if (i < 0 || i >= EQ_PLATES) {
        return vec3<f32>(0.0);
    }
    let off = vec3<f32>(eq_offset(c, i));
    let m = eq_motion(c, i, t);
    let scale = select(EQ_OFF_SCALE, 1.0, c.rest);
    var d = off * (scale * m.x);
    let sh = EQ_SHUD * m.y + EQ_BUILD_SHUD * eq_build(t);
    if (sh > 0.0) {
        let ph = 6.2831853 * eq_u(eq_h(c.seed, 95u + u32(i), 0u));
        d = d + sh * vec3<f32>(sin(t * 45.0 + ph), 0.6 * sin(t * 57.0 + 2.0 * ph), sin(t * 51.0 + 3.0 * ph));
        d.y = d.y + m.z * dot(w - eq_mid(c, i), eq_rock_dir(c, i));
    }
    return d;
}
