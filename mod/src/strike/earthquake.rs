//! The Earthquake's plan: no beam. The land splits along a main fault and one side is thrust up into a cliff
//! (`EqPlates`, the Rust mirror of shaders/earthquake_plates.wgsl).
//!
//! The beats (strike seconds; the shaders keep the same in their `EQ_*`): 0 a deep blow underfoot; EQ_CRACK (0.8) the
//! crack: the main fault cut open for real from the target both ways and on toward the player, then the side cracks
//! branching off and racing out round the plates, every cut reached by EQ_CRACK_BY (5.5; strike/eq_land.rs cuts them,
//! `fault_at` says where and when); the land still until it breaks; EQ_WARP_START (5.6) the world warp on; EQ_HEAVE (6)
//! the first heave: 35% of every plate's offset in about a second, the player lifted (on the up side) or thrown; lurches
//! at 8.5, 11 and 13.5 (12, 10, 6%), each plate its own timing; 14 to 18.5 the build, every plate shuddering harder;
//! EQ_CLIMAX (18.5) the last 37% in one thrust; EQ_STILL (21) every plate exactly on its final place; EQ_REST (31) the
//! drawn land and the real swapped on one frame; the aftermath to the end (50).
//!
//! How the land moves: the world warp (shaders/earthquake_warp.wgsl) moves the game's own vertices with their plate.
//! With `rest` (terrain on, once the real land is moved: `EQ_REAL_LAND`) each plate ends exactly on its whole-block
//! offset, where its real blocks will be by then; without, two more lurches set every plate back home by EQ_BACK_END.
//! The land's work (the cut, the read, the moved land written behind the hold, swapped in at rest) is
//! strike/eq_land.rs's.
//!
//! A player on a moving plate walks it while the picture shows it moved (eq_ride.rs: the camera drawn from the plate's
//! `drawn` displacement, handed over onto it before the land at rest goes in); the one standing on the up side inside
//! the zone as it fires (`rider`) feels the heaves as theirs, anyone else is knocked by them (KNOCKBACK). The warp reads its params
//! (`eq_params`), the post pass its table (`eq_table`); both are worked out here from the same `EqPlates`.
// (the land's interface (`fault_at`, `zone`, the cut's heights) and the shaders' mirrors are used by strike/eq_land.rs and
// the tests)
#![cfg_attr(not(test), allow(dead_code))]
use super::{Act, Plan, Rng, Target, sound_from};
use crate::lasers::Laser;

#[path = "eq_sounds.rs"]
mod eq_sounds;
use eq_sounds::eq_sounds;
pub use eq_sounds::{eq_slab_cues, eq_tree_cues};
/// Water pouring into the canyon, heard: asked for by the land once it has found water it sets flowing.
pub(super) fn eq_pour(p: &mut Plan, pl: &EqPlates) {
    eq_sounds::eq_pour(p, pl);
}

// ---- the beats (shaders/earthquake_plates.wgsl's EQ_*: keep both in step, `eq_wgsl_in_step`) -------------------------
/// The faults are cut open from EQ_CRACK, the cut racing out from the target at EQ_CRACK_V blocks a second (faster when
/// the zone is too big to be cut through in time), every cut reached by EQ_CRACK_BY.
pub(crate) const EQ_CRACK: f32 = 0.8;
pub(crate) const EQ_CRACK_V: f32 = 110.0;
pub(crate) const EQ_CRACK_BY: f32 = 5.5;
pub const EQ_WARP_START: f32 = 5.6;
pub(crate) const EQ_HEAVE: f32 = 6.0;
pub(crate) const EQ_CLIMAX: f32 = 18.5;
/// Every plate exactly on its final place from here (and still: no shudder, no rock), the drawn land standing until
/// the swap at EQ_REST.
pub(crate) const EQ_STILL: f32 = 21.0;
/// The real land is in under the drawn land by here and the two are swapped (strike/eq_land.rs).
pub(crate) const EQ_REST: f32 = 31.0;
pub const EQ_WARP_END: f32 = 31.0;
/// The terrain left alone: every plate back home and the warp off by here.
pub const EQ_BACK_END: f32 = 43.0;
// ---- the plates --------------------------------------------------------------------------------------------------------
/// How many plates there are at most (a plate's number is under this): seven bands of three segments.
pub const EQ_PLATES: usize = 21;
pub(super) const EQ_CAP: f32 = 0.45;
const EQ_SEG: f32 = 0.75;
const EQ_ROCK: f32 = 0.026;
const EQ_SHUD: f32 = 0.14;
pub(crate) const EQ_OFF_SCALE: f32 = 1.0;
const EQ_UP_E1: f32 = 0.2125;
const EQ_UP_E2: f32 = 0.4625;
const EQ_UP_E3: f32 = 0.73125;
const EQ_DN_E1: f32 = 0.225;
const EQ_DN_E2: f32 = 0.6;
/// The plates' rise (the up side's four bands from the fault out, then the down side's three), how far each moves away
/// from the fault and along it (blocks, before the knobs; the end segments half).
const EQ_RISE: [i32; 7] = [54, 38, 22, 8, -38, -14, -5];
const EQ_AWAY: [i32; 7] = [10, 7, 4, 1, 9, 6, 3];
const EQ_ALONG: i32 = 6;
/// The lurches: when each starts (before each plate's own spread), its share of the offset, how long it takes: the
/// first heave, three lurches, the climax; the last two only with the terrain left alone (back home).
const EQ_BASE: [f32; 7] = [6.0, 8.5, 11.0, 13.5, 18.5, 33.5, 38.4];
const EQ_SHARE: [f32; 7] = [0.35, 0.12, 0.1, 0.06, 0.37, -0.6, -0.4];
const EQ_LONG: [f32; 7] = [1.2, 1.2, 1.1, 0.9, 1.4, 3.6, 3.6];
/// The climax's number among the lurches, and the first lurch back home's.
pub(crate) const EQ_K_CLIMAX: usize = 4;
pub(crate) const EQ_K_HOME: usize = 5;
const EQ_UNITS: [u32; 12] = [1, 2, 4, 5, 8, 10, 11, 13, 16, 17, 19, 20];
// ---- the build before the climax: every plate shuddering harder, on its own phase (blocks) ---------------------------
const EQ_BUILD_T: f32 = 14.0;
const EQ_BUILD_SHUD: f32 = 0.06;
// ---- the player ----------------------------------------------------------------------------------------------------------
/// Where the main fault passes the player: inside the zone, across the band they ride (times the reach: the middle of
/// the cliff's band); outside it, this many blocks to their side. The crack runs on this far past them.
const EQ_RIDE_V: f32 = 0.10625;
const EQ_PASS: f32 = 30.0;
const EQ_PAST: f32 = 60.0;
/// The pass's table: its first word once it is in (shaders/earthquake.wgsl's EQ_MAGIC), where the jolts start and how
/// many there are at most.
pub(crate) const EQ_MAGIC: f32 = 5151.0;
const EQ_T_EV: usize = 17;
const EQ_EV_MAX: usize = 16;
/// Whether the real land is moved to where the plates come to rest (terrain on: strike/eq_land.rs). Off, terrain on
/// plays as terrain off and the plates ease back home.
pub const EQ_REAL_LAND: bool = true;
/// The knockback at the first heave, two of the lurches and the climax (times): mostly up (the ground heaving), a
/// little out; none for a player riding their plate (a push while carried would throw them as it lets go).
const EQ_KNOCK_OUT: f32 = 0.32;
const EQ_KNOCK_UP: f32 = 0.5;

/// The knobs as a strike takes them (`/orbital tune`, next strike).
#[derive(Clone, Copy, Debug)]
pub(crate) struct EqTune {
    pub reach: f32,
    pub slip: f32,
    pub heave: f32,
    pub pace: f32,
    pub knock: f32,
    pub jolt: f32,
}
impl EqTune {
    pub fn now() -> Self {
        let g = |k: &str| crate::tune::get("earthquake", k);
        EqTune { reach: g("reach"), slip: g("slip"), heave: g("heave"), pace: g("pace"), knock: g("knock"), jolt: g("jolt") }
    }
}

// ---- hashing (shaders/earthquake_plates.wgsl's, operation for operation) -----------------------------------------------
pub(crate) fn eq_hash(x: u32) -> u32 {
    let mut h = x;
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb_352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846c_a68b);
    h ^= h >> 16;
    h
}
pub(crate) fn eq_h(seed: u32, a: u32, b: u32) -> u32 {
    eq_hash(eq_hash(seed.wrapping_mul(0x9e37_79b1).wrapping_add(a)) ^ b.wrapping_mul(0x85eb_ca77).wrapping_add(0x1656_67b1))
}
fn eq_u(h: u32) -> f32 {
    (h >> 8) as f32 / 16_777_216.0
}
fn eq_lat(seed: u32, i: [i32; 2], k: u32) -> f32 {
    eq_u(eq_hash((i[0] as u32).wrapping_mul(0x8da6_b343) ^ (i[1] as u32).wrapping_mul(0xd816_3841) ^ seed.wrapping_mul(0x9e37_79b1).wrapping_add(k.wrapping_mul(0x85eb_ca77))))
}
fn mix(a: f32, b: f32, t: f32) -> f32 {
    a * (1.0 - t) + b * t
}
pub(crate) fn eq_vn(seed: u32, p: [f32; 2], k: u32) -> f32 {
    let fl = [p[0].floor(), p[1].floor()];
    let i = [fl[0] as i32, fl[1] as i32];
    let f = [p[0] - fl[0], p[1] - fl[1]];
    let u = [f[0] * f[0] * (3.0 - 2.0 * f[0]), f[1] * f[1] * (3.0 - 2.0 * f[1])];
    let a = eq_lat(seed, i, k);
    let b = eq_lat(seed, [i[0] + 1, i[1]], k);
    let c = eq_lat(seed, [i[0], i[1] + 1], k);
    let d = eq_lat(seed, [i[0] + 1, i[1] + 1], k);
    mix(mix(a, b, u[0]), mix(c, d, u[0]), u[1])
}
/// a / b rounded to the nearest, halves away from zero (b > 0).
fn eq_rdiv(a: i32, b: i32) -> i32 {
    if a >= 0 { (a + b / 2) / b } else { -((-a + b / 2) / b) }
}
/// One lurch's share of its weight `u` of the way through it (the shaders' eq_ease): a hard start (its speed peaks about
/// a sixth of the way through, from none: no velocity jump), an overshoot of about 8% halfway that settles from above,
/// at rest by the end with no velocity jump.
pub(crate) fn eq_ease(u: f32) -> f32 {
    if u <= 0.0 {
        return 0.0;
    }
    if u >= 1.0 {
        return 1.0;
    }
    let a = 1.0 - u;
    let a2 = a * a;
    1.0 + a2 * a2 * (-1.0 - 4.0 * u + 17.0 * u * u)
}
/// The very last lurch home: no overshoot (the shaders' eq_ease_last).
fn eq_ease_last(u: f32) -> f32 {
    let x = u.clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}
fn eq_ease_k(k: usize, u: f32) -> f32 {
    if k == EQ_K_HOME + 1 { eq_ease_last(u) } else { eq_ease(u) }
}
fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}
/// The build before the climax, 0 to 1 (the shaders' eq_build): growing from EQ_BUILD_T to the climax, gone over the
/// climax's thrust, nothing from EQ_STILL.
pub(crate) fn eq_build(t: f32) -> f32 {
    let g = smoothstep(EQ_BUILD_T, EQ_CLIMAX, t);
    g * g * (1.0 - smoothstep(EQ_CLIMAX + 0.2, EQ_STILL - 0.6, t))
}

/// The faults' cut: within EQ_CUT_HALF of a boundary between two plates (or of the rim where the plate inside moves, or
/// of the main crack past the zone toward the player), down to these heights (the main fault's, the others').
pub(crate) const EQ_CUT_HALF: f32 = 2.2;
pub(crate) const EQ_CUT_MAIN_Y: i32 = -60;
/// The main fault's cut is a trench in the zone: this wide each side of its line at the target, narrowing to
/// EQ_CUT_HALF where it leaves the zone (`main_half`). A lake of lava lies in it (`lake`, `lake_at`).
pub(crate) const EQ_WIDE: f32 = 10.0;
/// The lake's surface is the lava block this far under the land's level at the target once the low side has dropped.
const EQ_LAKE_UNDER: i32 = 30;
/// The lake's lava is crusted over where `crust` is this or more, and magma from EQ_CRUST_RIM under it.
pub(crate) const EQ_CRUST: f32 = 0.6;
pub(crate) const EQ_CRUST_RIM: f32 = 0.04;
pub(crate) const EQ_CUT_Y: i32 = -20;
/// A column of a fault's cut: whether it is the main fault's, the height its cut goes down to, and the strike second
/// the crack reaches it.
#[derive(Clone, Copy, Debug)]
pub struct EqFault {
    pub main: bool,
    pub floor: i32,
    pub at: f32,
    /// The main crack past the zone toward the player (nothing moves beside it: a crack only).
    pub crack: bool,
}

/// One lurch of a plate: when it starts, its share of the plate's offset, how long it takes.
#[derive(Clone, Copy, Debug)]
pub struct EqLurch {
    pub t: f32,
    pub w: f32,
    pub d: f32,
    /// The way it rocks the plate (+-1).
    pub s: f32,
}

/// Which boundary is nearest a point (the shaders' EqWhere.kind).
const K_MAIN: i32 = 0;
const K_BAND: i32 = 1;
const K_SEG: i32 = 2;
const K_RIM: i32 = 3;
/// A point's cell: its plate (none: fixed land), how far it is in fault coordinates from the nearest boundary, which
/// boundary that is.
#[derive(Clone, Copy, Debug)]
struct Cell {
    plate: Option<usize>,
    edge: f32,
    kind: i32,
}

/// The plates of one strike: the Rust mirror of shaders/earthquake_plates.wgsl's `EqCfg` and its functions. Points are
/// level, in blocks from the target block's corner (x, z); a column (x, z) of the world is `column`'s.
#[derive(Clone, Copy, Debug)]
pub struct EqPlates {
    pub seed: u32,
    pub reach: f32,
    pub pace: f32,
    pub fdir: [f32; 2],
    pub fi: [i32; 2],
    pub slip_q: i32,
    pub heave_q: i32,
    /// The plates come to rest displaced (the real land moved there); else they ease back.
    pub rest: bool,
    /// No plate is pinned any more (the player rides theirs): always -1.
    pub pinned: i32,
    /// The target block (x, y, z): the plates' origin is its corner (x, z), the land at y + 1.
    pub block: [i32; 3],
    /// The fault coordinates' origin (u0, v0), whole blocks: the zone moved along the fault and across it so the player
    /// stands well inside a plate or well outside the zone.
    pub shift: [i32; 2],
    /// The plate the player rides up on, or -1.
    pub ride: i32,
    /// Where the main crack ends toward the player, u in fault coordinates (it starts at the rim on the other side).
    pub crack_end: f32,
    /// Where the player stood as it fired, in fault coordinates.
    pub me_uv: [f32; 2],
}

impl EqPlates {
    /// The plates of a strike at `target` fired by a player at `me`, the strike's seed `seed` (1-997), the knobs `k`.
    /// The main fault runs through the target and heads for the player, passing them on their side (the side that
    /// rises): across the cliff's band when they are inside the zone (they ride it up), EQ_PASS to their side outside
    /// it; within 45 blocks it runs across their view. The zone is moved along it (`shift`) until they stand at least
    /// 10 blocks from any boundary (12 outside).
    pub fn new(target: &Target, me: [f64; 3], seed: u32, rest: bool, k: &EqTune) -> Self {
        let [bx, _, bz] = target.block;
        let (mx, mz) = ((me[0] - f64::from(bx)) as f32, (me[2] - f64::from(bz)) as f32);
        let (px, pz) = (f64::from(mx) - 0.5, f64::from(mz) - 0.5);
        let d = px.hypot(pz);
        let reach = k.reach.round();
        let base = EqPlates {
            seed,
            reach,
            pace: (k.pace * 100.0).round() / 100.0,
            fdir: [1.0, 0.0],
            fi: [256, 0],
            slip_q: (k.slip * 100.0).round() as i32,
            heave_q: (k.heave * 100.0).round() as i32,
            rest,
            pinned: -1,
            block: target.block,
            shift: [0, 0],
            ride: -1,
            crack_end: 0.0,
            me_uv: [0.0, 0.0],
        };
        let inside_first = d < f64::from((EQ_CAP + 0.93) * reach) - 20.0;
        let mut fallback = None;
        for ride in if inside_first { [true, false] } else { [false, true] } {
            let pass = if ride { EQ_RIDE_V * reach } else { EQ_PASS };
            let a = if d >= 45.0 {
                pz.atan2(px) - (f64::from(pass) / d).min(0.95).asin()
            } else {
                // (across the view, within 25 degrees)
                let look = if d > 0.5 { (-pz).atan2(-px) } else { 0.0 };
                look + std::f64::consts::FRAC_PI_2 + (f64::from(eq_u(eq_h(seed, 7, 0))) - 0.5) * 2.0 * 25f64.to_radians()
            };
            let mut fi = [(256.0 * a.cos()).round() as i32, (256.0 * a.sin()).round() as i32];
            // (the player on the up side: v > 0)
            if (-(fi[1] as f64) * px + fi[0] as f64 * pz) < 0.0 {
                fi = [-fi[0], -fi[1]];
            }
            let fl = ((fi[0] * fi[0] + fi[1] * fi[1]) as f32).sqrt().max(1.0);
            let cfg = EqPlates { fi, fdir: [fi[0] as f32 / fl, fi[1] as f32 / fl], ..base };
            let w = cfg.uv(cfg.bent([mx, mz]));
            let v0 = (w[1] - pass).round() as i32;
            let shifts = [0, 8, -8, 16, -16, 24, -24, 32, -32, 40, -40, 48, -48];
            // (riding: the middle segment if it can be, the end ones else)
            let picks = if ride { 2 } else { 1 };
            for pick in 0..picks {
                for &u0 in &shifts {
                    let mut c = cfg;
                    c.shift = [u0, v0];
                    let cell = c.cell_at([mx, mz]);
                    let e = c.true_edge([mx, mz], cell);
                    let ok = match cell.plate {
                        Some(i) => ride && i / 3 == 0 && (pick == 1 || i % 3 == 1) && e >= 10.0,
                        None => !ride && e >= 12.0,
                    };
                    if ok {
                        if ride {
                            c.ride = cell.plate.map_or(-1, |i| i as i32);
                        }
                        return c.finish([mx, mz]);
                    }
                    if fallback.is_none() && u0 == 0 && !ride {
                        fallback = Some(c);
                    }
                }
            }
        }
        // (nowhere well clear: as if far, the zone where it is)
        fallback.unwrap_or(base).finish([mx, mz])
    }
    fn finish(mut self, me: [f32; 2]) -> Self {
        self.me_uv = self.uv(self.bent(me));
        let uz = (EQ_CAP + 1.07) * self.reach;
        self.crack_end = (self.me_uv[0] + EQ_PAST).max(uz);
        self
    }
    /// A point pushed about by smooth noise (the shaders' eq_bent).
    fn bent(&self, p: [f32; 2]) -> [f32; 2] {
        let a = [p[0] * (1.0 / 90.0), p[1] * (1.0 / 90.0)];
        let b = [p[0] * (1.0 / 22.0), p[1] * (1.0 / 22.0)];
        let n1 = [eq_vn(self.seed, a, 1) - 0.5, eq_vn(self.seed, a, 2) - 0.5];
        let n2 = [eq_vn(self.seed, b, 3) - 0.5, eq_vn(self.seed, b, 4) - 0.5];
        [p[0] + n1[0] * 14.0 + n2[0] * 4.0, p[1] + n1[1] * 14.0 + n2[1] * 4.0]
    }
    /// The world point (x, z) of fault coordinates (u, v), the land's bend left out (some blocks).
    pub(crate) fn world_of(&self, w: [f32; 2]) -> [f64; 2] {
        let (a, b) = (w[0] + self.shift[0] as f32, w[1] + self.shift[1] as f32);
        [
            f64::from(self.block[0]) + f64::from(a * self.fdir[0] - b * self.fdir[1]),
            f64::from(self.block[2]) + f64::from(a * self.fdir[1] + b * self.fdir[0]),
        ]
    }
    /// A bent point in fault coordinates (the shaders' eq_uv).
    fn uv(&self, q: [f32; 2]) -> [f32; 2] {
        [q[0] * self.fdir[0] + q[1] * self.fdir[1] - self.shift[0] as f32, -q[0] * self.fdir[1] + q[1] * self.fdir[0] - self.shift[1] as f32]
    }
    fn rim(&self, q: [f32; 2]) -> f32 {
        self.reach * (0.93 + 0.14 * eq_vn(self.seed, [q[0] * (1.0 / 90.0), q[1] * (1.0 / 90.0)], 5))
    }
    /// The cell of fault point w, the rim there `rim` (the shaders' eq_cell).
    fn cell(&self, w: [f32; 2], rim: f32) -> Cell {
        let r = self.reach;
        let cap = (w[0].abs() - EQ_CAP * r).max(0.0).hypot(w[1]);
        if cap >= rim {
            return Cell { plate: None, edge: cap - rim, kind: K_RIM };
        }
        let (band, lo, hi);
        if w[1] >= 0.0 {
            let a = w[1];
            (band, lo, hi) = if a < EQ_UP_E1 * r {
                (0, a, EQ_UP_E1 * r - a)
            } else if a < EQ_UP_E2 * r {
                (1, a - EQ_UP_E1 * r, EQ_UP_E2 * r - a)
            } else if a < EQ_UP_E3 * r {
                (2, a - EQ_UP_E2 * r, EQ_UP_E3 * r - a)
            } else {
                (3, a - EQ_UP_E3 * r, 1.0e9)
            };
        } else {
            let a = -w[1];
            (band, lo, hi) = if a < EQ_DN_E1 * r {
                (4, a, EQ_DN_E1 * r - a)
            } else if a < EQ_DN_E2 * r {
                (5, a - EQ_DN_E1 * r, EQ_DN_E2 * r - a)
            } else {
                (6, a - EQ_DN_E2 * r, 1.0e9)
            };
        }
        let s = EQ_SEG * r;
        let (seg, ds) = if w[0] < -s {
            (0, -s - w[0])
        } else if w[0] > s {
            (2, w[0] - s)
        } else {
            (1, (w[0] + s).min(s - w[0]))
        };
        let mut e = lo;
        let mut kind = if band == 0 || band == 4 { K_MAIN } else { K_BAND };
        if hi < e {
            e = hi;
            kind = K_BAND;
        }
        if ds < e {
            e = ds;
            kind = K_SEG;
        }
        if rim - cap < e {
            e = rim - cap;
            kind = K_RIM;
        }
        Cell { plate: Some(band * 3 + seg), edge: e, kind }
    }
    fn cell_at(&self, p: [f32; 2]) -> Cell {
        let q = self.bent(p);
        self.cell(self.uv(q), self.rim(q))
    }
    /// The distances in fault coordinates from fault point w (the rim there `rim`) to each edge of plate `plate`'s cell
    /// (its band's two edges, its segment's, the rim; for fixed land the rim alone), positive inside it: each a smooth
    /// function of where it is, so its slope across the land can be taken by a small step.
    fn edges(&self, w: [f32; 2], rim: f32, plate: Option<usize>) -> [f32; 4] {
        let r = self.reach;
        let cap = (w[0].abs() - EQ_CAP * r).max(0.0).hypot(w[1]);
        let Some(i) = plate else { return [cap - rim, 1.0e9, 1.0e9, 1.0e9] };
        let (band, seg) = (i / 3, i % 3);
        let up = [0.0, EQ_UP_E1, EQ_UP_E2, EQ_UP_E3, 1.0e6];
        let dn = [0.0, EQ_DN_E1, EQ_DN_E2, 1.0e6];
        let (a, lo, hi) = if band < 4 { (w[1], up[band], up[band + 1]) } else { (-w[1], dn[band - 4], dn[band - 3]) };
        let s = EQ_SEG * r;
        let ds = match seg {
            0 => -s - w[0],
            2 => w[0] - s,
            _ => (w[0] + s).min(s - w[0]),
        };
        [a - lo * r, hi * r - a, ds, rim - cap]
    }
    /// The true distance in blocks from p to the nearest boundary of its cell `c`: each edge's distance in fault
    /// coordinates over how fast it changes across the land (the bending stretches and squeezes them by up to about a
    /// half), the nearest of them.
    fn true_edge(&self, p: [f32; 2], c: Cell) -> f32 {
        const H: f32 = 0.3;
        let at = |p: [f32; 2]| {
            let q = self.bent(p);
            self.edges(self.uv(q), self.rim(q), c.plate)
        };
        let (e0, ex, ez) = (at(p), at([p[0] + H, p[1]]), at([p[0], p[1] + H]));
        (0..4).filter(|&k| e0[k] < 1.0e5).map(|k| e0[k] / ((ex[k] - e0[k]) / H).hypot((ez[k] - e0[k]) / H).clamp(0.25, 4.0)).fold(f32::MAX, f32::min)
    }
    /// The true distance in blocks from p to the main fault's line (v = 0), and v there.
    fn main_dist(&self, p: [f32; 2]) -> (f32, f32) {
        const H: f32 = 0.3;
        let v = |p: [f32; 2]| self.uv(self.bent(p))[1];
        let v0 = v(p);
        let g = ((v([p[0] + H, p[1]]) - v0) / H).hypot((v([p[0], p[1] + H]) - v0) / H).clamp(0.25, 4.0);
        (v0.abs() / g, v0)
    }
    /// Which plate the level point (x, z) from the target block's corner lies on, and how far it is from the nearest
    /// boundary (another plate's, or the rim), in blocks (true to within a few percent near it; within half past 24
    /// blocks of fault coordinates): none past the rim (fixed land).
    pub fn where_at(&self, x: f32, z: f32) -> (Option<usize>, f32) {
        let c = self.cell_at([x, z]);
        let e = if c.edge < 24.0 { self.true_edge([x, z], c) } else { c.edge };
        (c.plate, e)
    }
    /// How far the level point (x, z) from the target block's corner lies outside every fault's cut, blocks (under 0:
    /// in one): from its cell's nearest boundary less EQ_CUT_HALF, and from the main fault's trench.
    pub fn cut_clear(&self, x: f32, z: f32) -> f32 {
        let e = self.where_at(x, z).1 - EQ_CUT_HALF;
        let w = self.uv(self.bent([x, z]));
        if !self.rest || w[0].abs() > self.lake_end() {
            return e;
        }
        e.min(self.main_dist([x, z]).0 - self.main_half(w[0]))
    }
    /// Which plate the level point (x, z) from the target block's corner lies on (none: fixed land).
    pub fn plate_of(&self, x: f32, z: f32) -> Option<usize> {
        self.cell_at([x, z]).plate
    }
    /// Which plate the world's column (x, z) lies on (by its middle): what the land's work asks of each column.
    pub fn column(&self, x: i32, z: i32) -> Option<usize> {
        self.plate_of((x - self.block[0]) as f32 + 0.5, (z - self.block[2]) as f32 + 0.5)
    }
    /// How fast the cracks run, blocks a second: EQ_CRACK_V, or faster when the zone is too big to be cut by
    /// EQ_CRACK_BY.
    fn crack_v(&self) -> f32 {
        EQ_CRACK_V.max(self.side_v())
    }
    /// How fast the side cracks run: just fast enough to reach the zone's farthest edge by EQ_CRACK_BY (the cut keeps
    /// pace with them; at the main crack's speed the land's cut fell behind the far band edges).
    fn side_v(&self) -> f32 {
        2.6 * self.reach / (EQ_CRACK_BY - 0.3 - EQ_CRACK)
    }
    /// When the crack reaches fault point w on a boundary of kind `kind`: the main fault from the target both ways; a
    /// segment's edge from where it leaves the main fault; a band's edge (and the rim) from where it leaves a segment's;
    /// the main crack past the zone faster, so its far end is reached in time too.
    fn arrive(&self, w: [f32; 2], kind: i32) -> f32 {
        let v = self.crack_v();
        let s = EQ_SEG * self.reach;
        let uz = (EQ_CAP + 1.07) * self.reach;
        let path = match kind {
            K_MAIN => {
                let u = w[0].abs();
                if u > uz {
                    let tz = EQ_CRACK + uz / v;
                    let v2 = v.max((self.crack_end - uz) / (EQ_CRACK_BY - 0.3 - tz));
                    return (tz + (u - uz) / v2).min(EQ_CRACK_BY - 0.3);
                }
                return EQ_CRACK + u / v;
            }
            K_SEG => s + w[1].abs(),
            _ => s + w[1].abs() + (w[0].abs() - s).abs(),
        };
        EQ_CRACK + path / self.side_v()
    }
    /// How far each side of the main fault's line its cut reaches at fault coordinate u: EQ_WIDE at the target, less
    /// toward the zone's ends, EQ_CUT_HALF from where the lake ends (`lake_end`) on.
    pub fn main_half(&self, u: f32) -> f32 {
        if !self.rest {
            return EQ_CUT_HALF;
        }
        let k = (u.abs() / self.lake_end()).min(1.0);
        EQ_CUT_HALF + (EQ_WIDE - EQ_CUT_HALF) * (1.0 - k * k).max(0.0)
    }
    /// How far along the main fault each way from the target the lake reaches (fault coordinates): short of the rim,
    /// whose cut is not as deep.
    fn lake_end(&self) -> f32 {
        (EQ_CAP + 0.6) * self.reach
    }
    /// The y of the lake's lava (its top block; one more of lava under it, a floor under that): EQ_LAKE_UNDER under the
    /// target's land once the low side beside the fault has come to rest, and high enough that the cut's floor, risen
    /// with the plate that rises most, still lies under it (the cliff's wall has real faces down to that floor: what
    /// rises out of the lava is the wall, never the trench's floor). None with the terrain left alone.
    pub fn lake(&self) -> Option<i32> {
        if !self.rest {
            return None;
        }
        let low = (0..EQ_PLATES).map(|i| self.offset(i)[1]).min().unwrap_or(0);
        let high = (0..EQ_PLATES).map(|i| self.offset(i)[1]).max().unwrap_or(0);
        Some((self.block[1] + low - EQ_LAKE_UNDER).max(EQ_CUT_MAIN_Y + high + 5))
    }
    /// How crusted the lake's lava is over the world's column (x, z), 0 to about 1.2: a raft of dark crust where it is
    /// EQ_CRUST or more, a rim of magma just under that (shaders/earthquake_warp.wgsl's `eq_crust`, by the column's
    /// middle from the target block's corner: the warp draws the same rafts while the land moves).
    pub fn crust(&self, x: i32, z: i32) -> f32 {
        let p = [(x - self.block[0]) as f32 + 0.5, (z - self.block[2]) as f32 + 0.5];
        eq_vn(self.seed, [p[0] * (1.0 / 11.0), p[1] * (1.0 / 11.0)], 61) + 0.35 * (eq_vn(self.seed, [p[0] * 0.25, p[1] * 0.25], 62) - 0.5)
    }
    /// What a cut column (x, z) of the world holds of the lake: 2 lava (the main fault's cut inside the lake's reach),
    /// 1 a sill of rock as high as the lava and one more (the main cut for 8 past the lake's ends, and any other
    /// fault's cut where it opens into the lake: nothing flows out), 0 neither.
    pub fn lake_at(&self, x: i32, z: i32, main: bool) -> u8 {
        if !self.rest {
            return 0;
        }
        let p = [(x - self.block[0]) as f32 + 0.5, (z - self.block[2]) as f32 + 0.5];
        let w = self.uv(self.bent(p));
        let (u, end) = (w[0].abs(), self.lake_end());
        if main {
            return if u <= end { 2 } else if u <= end + 8.0 { 1 } else { 0 };
        }
        if u <= end + 8.0 && self.main_dist(p).0 < self.main_half(w[0]) + 3.5 { 1 } else { 0 }
    }
    /// A column of a fault's cut, if (x, z) of the world is one: within `EQ_CUT_HALF` of a boundary between two plates,
    /// of the rim where the plate inside moves, or of the main crack past the zone toward the player (to `crack_end`).
    /// They are cut open for real before anything moves, so every plate has its own faces and no face outside the cut has
    /// its vertices on two plates (`eq_no_face_outside_a_cut_spans_two_plates`).
    pub fn fault_at(&self, x: i32, z: i32) -> Option<EqFault> {
        let p = [(x - self.block[0]) as f32 + 0.5, (z - self.block[2]) as f32 + 0.5];
        let q = self.bent(p);
        let w = self.uv(q);
        let rim = self.rim(q);
        let c = self.cell(w, rim);
        // (the bending scales distances by at most about 1.6: past this the column is well clear)
        let near = EQ_CUT_HALF * 1.8;
        let make = |main: bool, kind: i32| Some(EqFault { main, floor: if main { EQ_CUT_MAIN_Y } else { EQ_CUT_Y }, at: self.arrive(w, kind), crack: false });
        // (the main fault's trench, wherever its cell's nearest boundary is)
        // (the bending scales distances by between about 0.6 and 1.6: well inside it by that, no need to measure)
        if self.rest && w[1].abs() < EQ_WIDE * 1.8 && w[0].abs() <= self.lake_end() && c.plate.is_some() {
            let hw = self.main_half(w[0]);
            if w[1].abs() < 0.55 * hw || self.main_dist(p).0 < hw {
                return make(true, K_MAIN);
            }
        }
        if let Some(i) = c.plate {
            if c.edge > near || self.true_edge(p, c) >= EQ_CUT_HALF {
                return None;
            }
            if c.kind == K_RIM && self.offset(i) == [0; 3] {
                return None;
            }
            return make(c.kind == K_MAIN, c.kind);
        }
        // past the rim: its cut where the plate inside moves, and the main crack on toward the player
        if c.edge < near && self.true_edge(p, c) < EQ_CUT_HALF {
            let inside = self.cell(w, 1.0e9).plate;
            if inside.is_some_and(|j| self.offset(j) != [0; 3]) {
                return make(false, K_RIM);
            }
        }
        if w[0] > 0.0 && w[0] <= self.crack_end && w[1].abs() < near && self.main_dist(p).0 < EQ_CUT_HALF {
            return make(true, K_MAIN).map(|f| EqFault { crack: true, ..f });
        }
        None
    }
    /// The chunks (world chunk x, z) the main crack past the zone may cut, each with about when the crack first nears
    /// it, in that order: the crack's line from inside the nearest the rim comes to its end, wide enough for the bending.
    pub fn crack_chunks(&self) -> Vec<(i32, i32, f32)> {
        let mut v = Vec::new();
        let mut u = ((EQ_CAP + 0.93) * self.reach - 24.0).max(0.0);
        while u <= self.crack_end + 18.0 {
            let at = self.arrive([u, 0.0], K_MAIN);
            let mut s = -18.0f32;
            while s <= 18.0 {
                let (a, b) = (u + self.shift[0] as f32, s + self.shift[1] as f32);
                let x = self.block[0] as f32 + a * self.fdir[0] - b * self.fdir[1];
                let z = self.block[2] as f32 + a * self.fdir[1] + b * self.fdir[0];
                v.push(((x.floor() as i32) >> 4, (z.floor() as i32) >> 4, at));
                s += 3.0;
            }
            u += 3.0;
        }
        v.sort_by(|a, b| (a.0, a.1).cmp(&(b.0, b.1)).then(a.2.total_cmp(&b.2)));
        v.dedup_by(|a, b| (a.0, a.1) == (b.0, b.1));
        v.sort_by(|a, b| a.2.total_cmp(&b.2));
        v
    }
    /// The soonest the crack can reach a fault's column within `pad` (in fault coordinates) of the level point (x, z)
    /// from the target block's corner: every crack's path to a column is at least its |u|, and off the main fault at
    /// least |u| + |v| (`arrive`).
    pub fn crack_soonest(&self, x: f32, z: f32, pad: f32) -> f32 {
        let w = self.uv(self.bent([x, z]));
        let (u, v) = (w[0].abs(), w[1].abs());
        let uz = (EQ_CAP + 1.07) * self.reach;
        let side = EQ_CRACK + (u + v - 2.0 * pad).clamp(0.0, uz) / self.side_v();
        if v > pad + EQ_WIDE * 1.8 {
            return side;
        }
        side.min(EQ_CRACK + (u - pad).clamp(0.0, uz) / self.crack_v())
    }
    /// What the world's column (x, z) is to the main fault's trench where the lake lies: (its fault coordinate u, how far
    /// inside the trench's edge it is in blocks (under 0: outside), whether it is on the low side). None past the lake.
    pub fn trench_probe(&self, x: i32, z: i32) -> Option<(f32, f32, bool)> {
        if !self.rest {
            return None;
        }
        let p = [(x - self.block[0]) as f32 + 0.5, (z - self.block[2]) as f32 + 0.5];
        let w = self.uv(self.bent(p));
        if w[0].abs() > self.lake_end() {
            return None;
        }
        let (d, v) = self.main_dist(p);
        Some((w[0], self.main_half(w[0]) - d, v < 0.0))
    }
    /// The world's column at fault point (u, v) were the land not bent (it is, by up to about 12 blocks): a first guess.
    pub fn unbent(&self, u: f32, v: f32) -> [i32; 2] {
        let (a, b) = (u + self.shift[0] as f32, v + self.shift[1] as f32);
        [self.block[0] + (a * self.fdir[0] - b * self.fdir[1]).floor() as i32, self.block[2] + (a * self.fdir[1] + b * self.fdir[0]).floor() as i32]
    }
    /// The fault's direction (unit, world x and z), and how far along it each way the lake reaches.
    pub fn fault(&self) -> ([f32; 2], f32) {
        (self.fdir, self.lake_end())
    }
    /// Whether the level point p from the target block's corner is surely further than `pad` from the main fault's
    /// trench, told without the bending (which moves a point by up to about 12 blocks): most of the land is.
    fn off_trench(&self, p: [f32; 2], pad: f32) -> bool {
        let w = self.uv(p);
        w[1].abs() > EQ_WIDE * 1.8 + pad + 14.0 || w[0].abs() > self.lake_end() + pad + 14.0
    }
    /// When the crack reaches the level point (x, z) from the target block's corner, if everything within `half` blocks
    /// of it is the main fault's trench with the lake in it (none: some of it may not be).
    pub fn trench_inside(&self, x: f32, z: f32, half: f32) -> Option<f32> {
        if !self.rest || self.off_trench([x, z], half) {
            return None;
        }
        let p = [x, z];
        let w = self.uv(self.bent(p));
        // (the bending scales distances by at most about 1.6)
        if w[0].abs() + 1.6 * half > self.lake_end() || w[1].abs() > EQ_WIDE * 1.8 {
            return None;
        }
        // (the trench narrows by under a tenth of a block a block along it; the distance from the fault's line is true
        // to within a few percent, and a column's own may differ from the block's middle's by that)
        let hw = self.main_half(w[0]);
        (self.main_dist(p).0 + half + 0.3 < hw - 0.1 * half - 0.15 * hw).then(|| self.arrive(w, K_MAIN))
    }
    /// Whether the level point (x, z) from the target block's corner may lie within `pad` (in fault coordinates) of a
    /// column of the main fault's trench (`main_half`), or within `half` blocks of one: false means none is that near.
    pub fn trench_near(&self, x: f32, z: f32, pad: f32, half: f32) -> bool {
        if !self.rest || self.off_trench([x, z], pad + half) {
            return false;
        }
        let w = self.uv(self.bent([x, z]));
        if w[0].abs() > self.lake_end() + pad || w[1].abs() >= EQ_WIDE * 1.8 + pad {
            return false;
        }
        // (by its true distance from the fault's line: within `half` blocks of the trench's edge at the widest it can
        // be there)
        self.main_dist([x, z]).0 - half - 0.5 < self.main_half(w[0]) + 0.1 * half
    }
    /// Whether the level point (x, z) from the target block's corner may lie within `pad` (in fault coordinates) of a
    /// column of the main crack past the zone (`fault_at`'s `crack`): false means none is that near.
    pub fn crack_near(&self, x: f32, z: f32, pad: f32) -> bool {
        let w = self.uv(self.bent([x, z]));
        w[0] > -pad && w[0] <= self.crack_end + pad && w[1].abs() < EQ_CUT_HALF * 1.8 + pad
    }
    /// The plate the player rides up on, if they stood on one that rises as it fired.
    pub fn rider(&self) -> Option<usize> {
        (self.ride >= 0).then_some(self.ride as usize)
    }
    /// The middle (world x, z) and the radius of everything that moves or is cut, the main crack past the zone toward
    /// the player aside (it is a crack only: `crack_line`).
    pub fn zone(&self) -> ([f64; 2], f64) {
        let (u0, v0) = (self.shift[0] as f32, self.shift[1] as f32);
        let mid = [u0 * self.fdir[0] - v0 * self.fdir[1], u0 * self.fdir[1] + v0 * self.fdir[0]];
        let off = (EQ_AWAY[0].max(EQ_AWAY[4]).pow(2) + EQ_ALONG.pow(2)) as f32;
        let r = (EQ_CAP + 1.07) * self.reach + 14.0 + off.sqrt() * self.slip_q as f32 / 100.0 + 2.0;
        ([f64::from(self.block[0]) + 0.5 + f64::from(mid[0]), f64::from(self.block[2]) + 0.5 + f64::from(mid[1])], f64::from(r))
    }
    /// The main crack past the zone toward the player: (world x, z) where it leaves the zone, (world x, z) where it ends,
    /// as a straight line (its columns wander from it by up to about 12 blocks with the bending; `fault_at` says which).
    #[allow(dead_code)]
    pub fn crack_line(&self) -> ([f64; 2], [f64; 2]) {
        let at = |u: f32| {
            let (u, v) = (u + self.shift[0] as f32, self.shift[1] as f32);
            [f64::from(self.block[0]) + f64::from(u * self.fdir[0] - v * self.fdir[1]), f64::from(self.block[2]) + f64::from(u * self.fdir[1] + v * self.fdir[0])]
        };
        (at((EQ_CAP + 0.93) * self.reach), at(self.crack_end))
    }
    /// Plate i's offset at rest, whole blocks (x, y, z) (the shaders' eq_offset).
    pub fn offset(&self, i: usize) -> [i32; 3] {
        if i >= EQ_PLATES {
            return [0; 3];
        }
        let b = i / 3;
        let up = b < 4;
        let mut rise = EQ_RISE[b];
        let mut away = EQ_AWAY[b];
        let mut along = if up { EQ_ALONG } else { -EQ_ALONG };
        if i % 3 != 1 {
            rise = eq_rdiv(rise, 2);
            away = eq_rdiv(away, 2);
            along /= 2;
        }
        let h = eq_h(self.seed, 100 + i as u32, 7);
        rise += if rise.abs() >= 20 { (h % 5) as i32 - 2 } else { (h % 3) as i32 - 1 };
        let aw = if up { away } else { -away } * self.slip_q;
        let al = along * self.slip_q;
        let x = eq_rdiv(al * self.fi[0] - aw * self.fi[1], 25600);
        let z = eq_rdiv(al * self.fi[1] + aw * self.fi[0], 25600);
        [x, eq_rdiv(rise * self.heave_q, 100), z]
    }
    /// How many lurches each plate has (the last two, back home, only with the terrain left alone).
    pub fn lurch_n(&self) -> usize {
        if self.rest { EQ_K_HOME } else { EQ_BASE.len() }
    }
    /// Plate i's lurch k (0 the first heave, 1-3 the plates working, EQ_K_CLIMAX the climax, EQ_K_HOME and on back
    /// home); past the plate's last lurch one that moves nothing.
    pub fn lurch(&self, i: usize, k: usize) -> EqLurch {
        if k >= EQ_BASE.len() {
            return EqLurch { t: EQ_REST, w: 0.0, d: 1.0, s: 1.0 };
        }
        let (iu, ku) = (i as u32, k as u32);
        let hk = eq_h(self.seed, 20, ku);
        let a = EQ_UNITS[(hk % 12) as usize];
        let rank = ((iu * a + (hk >> 8) % 21) % 21) as f32 - 10.0;
        let hp = eq_h(self.seed, 22 + iu, ku);
        let mut t = EQ_BASE[k];
        let mut d = EQ_LONG[k];
        if k == 0 || k == EQ_K_CLIMAX {
            t = t + rank * 0.012;
        } else {
            t = t + rank * 0.037 + (eq_u(hp) - 0.5) * 0.04;
            d = d * (0.9 + 0.2 * (hp & 255) as f32 / 255.0);
        }
        let end = if k >= EQ_K_HOME { EQ_BACK_END } else { EQ_STILL };
        d = (d * self.pace).min(end - 0.05 - t);
        EqLurch { t, w: EQ_SHARE[k], d, s: if hp & 256 == 0 { 1.0 } else { -1.0 } }
    }
    /// Plate i's share of its offset at t: 0 before its first lurch; from EQ_STILL exactly 1 (and from EQ_BACK_END
    /// exactly 0 when it eases back home).
    pub fn share(&self, i: usize, t: f32) -> f32 {
        if t >= EQ_BACK_END && !self.rest {
            return 0.0;
        }
        if t >= EQ_STILL {
            return 1.0 + (EQ_K_HOME..self.lurch_n()).map(|k| {
                let l = self.lurch(i, k);
                l.w * eq_ease_k(k, (t - l.t) / l.d)
            }).sum::<f32>();
        }
        (0..EQ_K_HOME).map(|k| {
            let l = self.lurch(i, k);
            l.w * eq_ease_k(k, (t - l.t) / l.d)
        }).sum()
    }
    /// How hard plate i is slipping at t, 0 to 1 (its shudder, the dust and the rubble to come): its lurches, and the
    /// build's shudder before the climax.
    #[allow(dead_code)]
    pub fn slipping(&self, i: usize, t: f32) -> f32 {
        if (t >= EQ_STILL && t < EQ_BASE[EQ_K_HOME] - 0.5) || (self.rest && t >= EQ_STILL) || t >= EQ_BACK_END || t <= EQ_HEAVE - 0.5 {
            return 0.0;
        }
        let mut s = eq_build(t) * 0.5;
        for k in 0..self.lurch_n() {
            let l = self.lurch(i, k);
            let u = (t - l.t) / l.d;
            if u > 0.0 && u < 1.0 {
                let b = (std::f32::consts::PI * u).sin();
                s += b * b * (l.w.abs() / 0.15).min(1.0);
            }
        }
        s.min(1.0)
    }
    /// Where plate i's points are drawn at t, from where they are, without its rock and shudder (what the plan needs:
    /// the rigid part); from EQ_REST exactly the whole-block offset (or none from EQ_BACK_END).
    pub fn disp(&self, i: usize, t: f32) -> [f32; 3] {
        if i >= EQ_PLATES {
            return [0.0; 3];
        }
        let o = self.offset(i);
        let k = if self.rest { 1.0 } else { EQ_OFF_SCALE } * self.share(i, t);
        [o[0] as f32 * k, o[1] as f32 * k, o[2] as f32 * k]
    }
    /// How hard plate i slips at t as the shaders' eq_motion has it (its y): the lurches under way, nothing at rest.
    fn slip_drawn(&self, i: usize, t: f32) -> f32 {
        if (self.rest && t >= EQ_STILL) || t >= EQ_BACK_END || t < EQ_HEAVE - 0.5 {
            return 0.0;
        }
        let ks = if t >= EQ_STILL { EQ_K_HOME..self.lurch_n() } else { 0..EQ_K_HOME };
        let mut slip = 0.0;
        for k in ks {
            let l = self.lurch(i, k);
            let u = (t - l.t) / l.d;
            if u > 0.0 && u < 1.0 {
                let b = (std::f32::consts::PI * u).sin();
                slip += b * b * (l.w.abs() / 0.15).min(1.0);
            }
        }
        slip.min(1.0)
    }
    /// Where the world warp draws plate i's points at t while it is kept rigid (the plate the player stands on: no rock),
    /// from where they are: `disp` and its shudder (the shaders' eq_disp).
    pub fn drawn(&self, i: usize, t: f32) -> [f32; 3] {
        let mut d = self.disp(i, t);
        if i >= EQ_PLATES {
            return d;
        }
        let sh = EQ_SHUD * self.slip_drawn(i, t) + EQ_BUILD_SHUD * eq_build(t);
        if sh > 0.0 {
            let ph = std::f32::consts::TAU * eq_u(eq_h(self.seed, 95 + i as u32, 0));
            d[0] += sh * (t * 45.0 + ph).sin();
            d[1] += sh * 0.6 * (t * 57.0 + 2.0 * ph).sin();
            d[2] += sh * (t * 51.0 + 3.0 * ph).sin();
        }
        d
    }
    /// Every lurch of every plate: (when it starts, the plate, how many blocks it moves the plate as drawn).
    pub fn lurches(&self) -> Vec<(f32, usize, f32)> {
        let mut out = Vec::new();
        for i in 0..EQ_PLATES {
            let o = self.offset(i);
            let len = ((o[0] * o[0] + o[1] * o[1] + o[2] * o[2]) as f32).sqrt() * if self.rest { 1.0 } else { EQ_OFF_SCALE };
            for k in 0..self.lurch_n() {
                let l = self.lurch(i, k);
                out.push((l.t, i, l.w.abs() * len));
            }
        }
        out.sort_by(|a, b| a.0.total_cmp(&b.0));
        out
    }
    /// The plate whose lurches the player feels as theirs: the one they ride, else the cliff's middle.
    fn near(&self) -> usize {
        self.rider().unwrap_or(1)
    }
    /// The world warp's params (shaders/earthquake_warp.wgsl's header): (index, value) over the strike's own.
    pub fn warp_params(&self) -> [(usize, f32); 8] {
        let fp = ((self.fi[0] + 512) * 1024 + (self.fi[1] + 512)) as f32;
        let sh = ((self.shift[0] + 512) * 1024 + (self.shift[1] + 512)) as f32;
        [
            (0, fp),
            (2, self.reach),
            (6, self.pace),
            (10, (self.slip_q * 1000 + self.heave_q) as f32),
            (12, sh),
            (13, eq_rigid_param(self.rider(), 1.0)),
            (14, 0.0),
            // (the lake's lava block's y + 1024; 0: none)
            (7, self.lake().map_or(0.0, |l| (l + 1024) as f32)),
        ]
    }
}

/// The warp's params 13 and 14: a plate kept from rocking (the one the player stands on, and the one they left while
/// the view eases off it), as its number + 1 and how far it is kept rigid (0 to 1) in half the fraction: the warp's
/// `c.rider`, `c.rider_k`, `c.prev`, `c.prev_k`.
pub fn eq_rigid_param(plate: Option<usize>, k: f32) -> f32 {
    plate.map_or(0.0, |i| (i + 1) as f32 + 0.5 * k.clamp(0.0, 1.0))
}

/// The plates of a strike, with the knobs as they are now: `plan`, lib.rs (the warp's params) and the ride all take
/// them so.
pub fn eq_plates(target: &Target, me: [f64; 3], seed: f32, terrain: bool) -> EqPlates {
    EqPlates::new(target, me, seed as u32, terrain && EQ_REAL_LAND, &EqTune::now())
}
/// The params the world warp reads, set over the strike's own as it fires (lib.rs).
pub fn eq_params(target: &Target, me: [f64; 3], seed: f32, terrain: bool) -> [(usize, f32); 8] {
    eq_plates(target, me, seed, terrain).warp_params()
}

/// The jolts the player feels: (strike second it reaches them, how hard 0-1), in time order: the blow underfoot (small),
/// the first heave, each lurch by its share, the climax the hardest; back home with the terrain left alone. Nothing
/// between them: no running tremor.
fn eq_jolts(pl: &EqPlates, me: [f64; 3]) -> Vec<(f32, f32)> {
    let late = (eq_jolt_dist(pl, me) / 1700.0) as f32;
    let n = pl.near();
    let mut out = vec![(0.05 + late, 0.3)];
    let size = [0.85, 0.45, 0.4, 0.3, 1.0, 0.35, 0.25];
    for k in 0..pl.lurch_n() {
        out.push((pl.lurch(n, k).t + 0.05 + late, size[k]));
    }
    out.truncate(EQ_EV_MAX);
    out.sort_by(|a, b| a.0.total_cmp(&b.0));
    out
}
/// How far the player is from the nearest moving plate (0 standing on one), blocks: what the jolts fall off by.
fn eq_jolt_dist(pl: &EqPlates, me: [f64; 3]) -> f64 {
    let (x, z) = ((me[0] - f64::from(pl.block[0])) as f32, (me[2] - f64::from(pl.block[2])) as f32);
    match pl.where_at(x, z) {
        (Some(_), _) => 0.0,
        (None, e) => f64::from(e),
    }
}
/// How hard the jolts are where the player stands, 0 to 1: all of it on a plate and close by, falling off with the
/// distance to the nearest moving plate; half for a rider (the ride moves their view already); times the knob `jolt`.
fn eq_jolt_gain(pl: &EqPlates, me: [f64; 3], jolt: f32) -> f32 {
    let d = eq_jolt_dist(pl, me);
    let g = (1.6 / (1.0 + d / 250.0)).min(1.0) as f32;
    g * if pl.rider().is_some() { 0.5 } else { 1.0 } * jolt
}
/// One jolt of the game's camera at `t`, `fo` as hard, `s` the jolt's size (the climax 1): shaped as the Payload's and
/// the Nuke's (payload::pl_jolt, nuke::nk_jolt), short: a hard hit, sharp kicks every other tick ringing out over half
/// a second, a quick shudder fading over about one more (the climax's over about two and a half).
fn eq_jolt(p: &mut Plan, t: f32, fo: f32, s: f32) {
    let f = fo * (0.35 + 0.65 * s);
    if f <= 1.0e-4 {
        return;
    }
    p.shake(t, f, 0.6 + 0.6 * s);
    p.shake(t + 0.05, 0.45 * f, 1.2 + 1.8 * s);
    let kicks = 3 + (4.0 * s).round() as usize;
    for n in 0..kicks {
        p.shake(t + 0.1 * (n + 1) as f32, (1.0 - 0.08 * n as f32) * f, 0.14);
    }
    let long = 1.0 + 1.5 * s;
    let shud = (long / 0.12).round() as usize;
    for n in 0..shud {
        let u = n as f32 / shud as f32;
        p.shake(t + 0.1 * (kicks + 1) as f32 + 0.12 * n as f32, (0.55 * (1.0 - u).powf(1.3) + 0.06) * f, 0.1);
    }
}

/// The post pass's table (shaders/earthquake.wgsl's `[eq shared]` head says the layout).
pub(crate) fn eq_table(pl: &EqPlates, me: [f64; 3], jolt: f32) -> Vec<u32> {
    let jolts = eq_jolts(pl, me);
    let g = eq_jolt_gain(pl, me, jolt);
    let mut w: Vec<f32> = vec![
        EQ_MAGIC,
        pl.fi[0] as f32,
        pl.fi[1] as f32,
        pl.reach,
        pl.pace,
        pl.slip_q as f32,
        pl.heave_q as f32,
        if pl.rest { 1.0 } else { 0.0 },
        pl.ride as f32,
        me[0] as f32,
        me[1] as f32,
        me[2] as f32,
        g,
        jolts.len() as f32,
        pl.shift[0] as f32,
        pl.shift[1] as f32,
        pl.crack_end,
    ];
    debug_assert_eq!(w.len(), EQ_T_EV);
    for (t, s) in &jolts {
        w.push(*t);
        w.push(*s);
    }
    // (the dust's words: strike/eq_fx.rs)
    super::eq_fx::eq_fx_extend(&mut w, pl);
    w.iter().map(|v| v.to_bits()).collect()
}

/// The land's work (terrain on): the faults cut open as the crack races out, each column's real blocks read once
/// (`world.read-columns`) and written once where its plate comes to rest (`world.edit-blocks`), chunk by chunk behind
/// `render.hold-world` (strike/eq_land.rs). Nothing when the plates ease back home.
fn eq_land(p: &mut Plan, pl: &EqPlates, me: [f64; 3]) {
    super::eq_land::eq_land(p, pl, me);
}

/// The circle the hold on the terrain is kept to (lib.rs's `frame`, from the strike's params: the target block's middle
/// 4-5, the fault's direction 0, the zone's shift 12, the reach 2, the slip in 10): every chunk the land's work edits
/// under the hold has its middle in it (the zone's circle and a chunk's half diagonal).
pub fn eq_hold_within(params: &[f32]) -> (f64, f64, f64) {
    let reach = params[2];
    let slip = (params[10].max(0.0) as u32 / 1000) as f32 / 100.0;
    let fp = params[0].max(0.0) as u32;
    let fi = [(fp / 1024) as i32 - 512, (fp % 1024) as i32 - 512];
    let fl = ((fi[0] * fi[0] + fi[1] * fi[1]) as f32).sqrt().max(1.0);
    let sh = params[12].max(0.0) as u32;
    let (u0, v0) = (((sh / 1024) as i32 - 512) as f32, ((sh % 1024) as i32 - 512) as f32);
    let f = [fi[0] as f32 / fl, fi[1] as f32 / fl];
    let mid = [u0 * f[0] - v0 * f[1], u0 * f[1] + v0 * f[0]];
    let off = ((EQ_AWAY[0].max(EQ_AWAY[4]).pow(2) + EQ_ALONG.pow(2)) as f32).sqrt();
    let r = (EQ_CAP + 1.07) * reach + 14.0 + off * slip + 2.0 + 7.0 + 12.0;
    (f64::from(params[4] + mid[0]), f64::from(params[5] + mid[1]), f64::from(r))
}

pub(super) fn earthquake_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let k = EqTune::now();
    let pl = EqPlates::new(target, me, shader_seed as u32, terrain && EQ_REAL_LAND, &k);
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let ground = [f64::from(bx) + 0.5, f64::from(by) + 1.0, f64::from(bz) + 0.5];
    let (_, dist) = sound_from(ground, me);
    // (through the ground: much sooner than through the air)
    let late = (dist / 1700.0) as f32;
    // the pass's table, on the tick after it fires
    let table = eq_table(&pl, me, k.jolt);
    p.ev.push((0.05, Act::Table(table)));
    // (the land's own heights under the dust, asked of the world now: strike/eq_ground.rs)
    super::eq_ground::eq_ground(&mut p, &pl);

    eq_sounds(&mut p, &pl, dist, late);

    // ---- the shaking: a short hard jolt at the blow, the first heave, each lurch and the climax (the hardest); nothing
    // between them (the pass knocks the picture about on top: shaders/earthquake.wgsl's eq_jolt)
    let fo = eq_jolt_gain(&pl, me, k.jolt);
    if fo > 0.0 {
        for (t, s) in eq_jolts(&pl, me) {
            eq_jolt(&mut p, t, fo, s);
        }
    }
    // ---- the knocks (KNOCKBACK): the first heave, two lurches, the climax; none for a player riding their plate ---------
    if pl.rider().is_none() {
        let reach = pl.reach * 2.5;
        let n = pl.near();
        for (kk, x) in [(0usize, 1.0f32), (1, 0.45), (2, 0.5), (EQ_K_CLIMAX, 1.15)] {
            let t = pl.lurch(n, kk).t + 0.08 + late;
            p.ev.push((t, Act::Shove { from: ground, out: EQ_KNOCK_OUT * x * k.knock, up: EQ_KNOCK_UP * x * k.knock, reach }));
        }
    }
    if terrain {
        eq_land(&mut p, &pl, me);
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    fn tune0() -> EqTune {
        EqTune { reach: 160.0, slip: 1.0, heave: 1.0, pace: 1.0, knock: 1.0, jolt: 1.0 }
    }
    fn target() -> Target {
        Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] }
    }
    fn plates(seed: u32, rest: bool, me: [f64; 3]) -> EqPlates {
        EqPlates::new(&target(), me, seed, rest, &tune0())
    }
    /// The player at `d` blocks from the target, bearing `deg`.
    fn me_at(d: f64, deg: f64) -> [f64; 3] {
        let a = deg.to_radians();
        [10.5 + d * a.cos(), 66.0, -2.5 + d * a.sin()]
    }

    /// The constants and the hashes the shaders share with the plan, as here.
    #[test]
    fn eq_wgsl_in_step() {
        let src = include_str!("../../shaders/earthquake_plates.wgsl");
        let val = |name: &str| -> f32 {
            let line = src.lines().find(|l| l.starts_with(&format!("const {name}: f32 = "))).unwrap_or_else(|| panic!("{name} in the plates"));
            line.split('=').nth(1).unwrap().split(';').next().unwrap().trim().parse().unwrap()
        };
        for (name, v) in [
            ("EQ_LEN", crate::lasers::EARTHQUAKE.length),
            ("EQ_CRACK", EQ_CRACK),
            ("EQ_CRACK_V", EQ_CRACK_V),
            ("EQ_CRACK_BY", EQ_CRACK_BY),
            ("EQ_WARP_START", EQ_WARP_START),
            ("EQ_HEAVE", EQ_HEAVE),
            ("EQ_CLIMAX", EQ_CLIMAX),
            ("EQ_STILL", EQ_STILL),
            ("EQ_REST", EQ_REST),
            ("EQ_WARP_END", EQ_WARP_END),
            ("EQ_BACK_END", EQ_BACK_END),
            ("EQ_CAP", EQ_CAP),
            ("EQ_SEG", EQ_SEG),
            ("EQ_ROCK", EQ_ROCK),
            ("EQ_SHUD", EQ_SHUD),
            ("EQ_OFF_SCALE", EQ_OFF_SCALE),
            ("EQ_UP_E1", EQ_UP_E1),
            ("EQ_UP_E2", EQ_UP_E2),
            ("EQ_UP_E3", EQ_UP_E3),
            ("EQ_DN_E1", EQ_DN_E1),
            ("EQ_DN_E2", EQ_DN_E2),
            ("EQ_BUILD_T", EQ_BUILD_T),
            ("EQ_BUILD_SHUD", EQ_BUILD_SHUD),
        ] {
            assert!((val(name) - v).abs() < 1e-6, "{name}: the shaders have {}, the plan {v}", val(name));
        }
        assert!(src.contains(&format!("const EQ_PLATES: i32 = {EQ_PLATES};")));
        assert!(src.contains(&format!("const EQ_K_CLIMAX: i32 = {EQ_K_CLIMAX};")) && src.contains(&format!("const EQ_K_HOME: i32 = {EQ_K_HOME};")));
        assert!(!src.contains("eq_wave") && !src.contains("EQ_WAVE"), "the ground waves are gone");
        let list = |a: &[f32]| a.iter().map(|b| format!("{b:?}")).collect::<Vec<_>>().join(", ");
        for (name, a) in [("base", &EQ_BASE), ("share", &EQ_SHARE), ("long", &EQ_LONG)] {
            assert!(src.contains(&format!("var {name} = array<f32, 7>({});", list(a))), "the lurches' {name}: {}", list(a));
        }
        let dust = include_str!("../../shaders/earthquake_dust.wgsl");
        assert!(dust.contains(&format!("var b = array<f32, 7>({});", list(&EQ_BASE))) && dust.contains(&format!("var s = array<f32, 7>({});", list(&EQ_SHARE))), "the dust's lurches");
        assert!(dust.contains("x.rest_one = (c.rest && v.t >= EQ_STILL) || v.t >= EQ_BACK_END;"));
        let ints = |a: &[i32]| a.iter().map(|b| b.to_string()).collect::<Vec<_>>().join(", ");
        assert!(src.contains(&format!("var rises = array<i32, 7>({});", ints(&EQ_RISE))));
        assert!(src.contains(&format!("var aways = array<i32, 7>({});", ints(&EQ_AWAY))));
        assert!(src.contains(&format!("var along = select(-{EQ_ALONG}, {EQ_ALONG}, up);")));
        let units = EQ_UNITS.iter().map(|u| format!("{u}u")).collect::<Vec<_>>().join(", ");
        assert!(src.contains(&format!("var units = array<u32, 12>({units});")));
        // (the hashes' constants and the integer arithmetic, word for word)
        for s in [
            "h * 0x7feb352du", "h * 0x846ca68bu", "^ (seed * 0x9e3779b1u + k * 0x85ebca77u)", "seed * 0x9e3779b1u + a", "b * 0x85ebca77u + 0x165667b1u", "0x8da6b343u", "0xd8163841u",
            "f32(h >> 8u) / 16777216.0", "let h = eq_h(c.seed, 100u + u32(i), 7u);", "rise = rise + select(i32(h % 3u) - 1, i32(h % 5u) - 2, abs(rise) >= 20);",
            "rise = eq_rdiv(rise, 2);", "away = eq_rdiv(away, 2);", "along = along / 2;",
            "let x = eq_rdiv(al * c.fi.x - aw * c.fi.y, 25600);", "let z = eq_rdiv(al * c.fi.y + aw * c.fi.x, 25600);", "eq_rdiv(rise * c.heave_q, 100)",
            "let hk = eq_h(c.seed, 20u, ku);", "let a = units[hk % 12u];", "f32((u32(i) * a + (hk >> 8u) % 21u) % 21u) - 10.0", "t = t + rank * 0.012;",
            "let hp = eq_h(c.seed, 22u + u32(i), ku);", "t = t + rank * 0.037 + (eq_u(hp) - 0.5) * 0.04;", "d = d * (0.9 + 0.2 * f32(hp & 255u) / 255.0);",
            "select(-1.0, 1.0, (hp & 256u) == 0u)",
            "let ph = 6.2831853 * eq_u(eq_h(c.seed, 95u + u32(i), 0u));", "d = d + sh * vec3<f32>(sin(t * 45.0 + ph), 0.6 * sin(t * 57.0 + 2.0 * ph), sin(t * 51.0 + 3.0 * ph));",
            "let sh = EQ_SHUD * m.y + EQ_BUILD_SHUD * eq_build(t);", "slip = slip + m;", "let m = b * b * min(abs(l.w) / 0.15, 1.0);",
            "if ((c.rest && t >= EQ_STILL) || t >= EQ_BACK_END || t < EQ_HEAVE - 0.5) {",
            "let rigid = min(select(0.0, c.rider_k, i == c.rider) + select(0.0, c.prev_k, i == c.prev), 1.0);",
            "d = min(d * c.pace, end - 0.05 - t);", "1.0 + a2 * a2 * (-1.0 - 4.0 * u + 17.0 * u * u)", "if (k == 0 || k == EQ_K_CLIMAX) {", "let end = select(EQ_STILL, EQ_BACK_END, k >= EQ_K_HOME);",
            "return g * g * (1.0 - smoothstep(EQ_CLIMAX + 0.2, EQ_STILL - 0.6, t));", "let g = smoothstep(EQ_BUILD_T, EQ_CLIMAX, t);", "x * x * x * (x * (6.0 * x - 15.0) + 10.0)",
            "c.reach * (0.93 + 0.14 * eq_vn(c.seed, q * (1.0 / 90.0), 5u))", "p + n1 * 14.0 + n2 * 4.0", "let a = p * (1.0 / 90.0);", "let b = p * (1.0 / 22.0);",
            "return vec2<f32>(dot(q, c.fdir), dot(q, vec2<f32>(-c.fdir.y, c.fdir.x))) - c.shift;",
            "let cap = length(vec2<f32>(max(abs(w.x) - EQ_CAP * r, 0.0), w.y));", "return EqWhere(band * 3 + seg, e, kind);",
        ] {
            assert!(src.contains(s), "the plates' shader lacks `{s}`");
        }
        // (the hash itself: a known value, so a change on either side shows)
        assert_eq!((eq_hash(1), eq_hash(12345)), (0x6889_90c0, 0x912e_fcf7));
        // the pass's table and the warp's params
        let pass = include_str!("../../shaders/earthquake.wgsl");
        assert!(pass.contains(&format!("const EQ_MAGIC: f32 = {EQ_MAGIC:.1};")) && pass.contains(&format!("const EQ_T_EV: u32 = {EQ_T_EV}u;")) && pass.contains(&format!("const EQ_EV_MAX: u32 = {EQ_EV_MAX}u;")));
        for s in ["c.rider = i32(round(eq_w(8u)));", "c.rider_k = 1.0;", "c.prev = -1;", "c.shift = vec2<f32>(round(eq_w(14u)), round(eq_w(15u)));"] {
            assert!(pass.contains(s), "the pass lacks `{s}`");
        }
        let warp = include_str!("../../shaders/earthquake_warp.wgsl");
        assert!(!warp.contains("wave") && !pass.contains("tremor") && !pass.contains("roll"), "no waves, no tremor, no roll");
        for s in [
            "i32(fp / 1024u) - 512, i32(fp % 1024u) - 512", "c.reach = w[0].z", "c.pace = w[1].z", "c.slip_q = i32(kn / 1000u)", "c.heave_q = i32(kn % 1000u)",
            "c.rider = i32(floor(w[3].y + 0.001)) - 1", "c.rider_k = clamp(fract(w[3].y + 0.001) * 2.0, 0.0, 1.0)",
            "c.prev = i32(floor(w[3].z + 0.001)) - 1", "c.prev_k = clamp(fract(w[3].z + 0.001) * 2.0, 0.0, 1.0)", "c.seed = u32(max(w[2].x, 0.0) + 0.5)", "kn = u32(max(w[2].z, 0.0) + 0.5)", "fp = u32(max(w[0].x, 0.0) + 0.5)",
            "sh = u32(max(w[3].x, 0.0) + 0.5)", "c.shift = vec2<f32>(f32(i32(sh / 1024u) - 512), f32(i32(sh % 1024u) - 512))",
        ] {
            assert!(warp.contains(s), "the warp lacks `{s}`");
        }
        let me = me_at(120.0, 70.0);
        let pl = plates(37, true, me);
        let wp = pl.warp_params();
        let fp = wp[0].1 as u32;
        assert_eq!([(fp / 1024) as i32 - 512, (fp % 1024) as i32 - 512], pl.fi);
        let sh = wp[4].1 as u32;
        assert_eq!([(sh / 1024) as i32 - 512, (sh % 1024) as i32 - 512], pl.shift);
        assert!(wp.iter().all(|w| w.0 != 1), "params[1] (the old wave knob) unused");
        assert_eq!(wp[3].1 as i32, pl.slip_q * 1000 + pl.heave_q);
        assert_eq!(wp[5].1 as i32 - 1, pl.ride);
    }

    /// Every share starts at nothing, stands exactly on 1 from EQ_STILL (back to exactly 0 by EQ_BACK_END when the land
    /// eases home), and its velocity never jumps (no linear ramps, no dead stops).
    #[test]
    fn eq_shares_start_at_none_rest_exactly_and_never_jump() {
        for seed in [1u32, 37, 500, 997] {
            for rest in [true, false] {
                for pace in [0.6f32, 1.0, 1.6] {
                    let pl = EqPlates::new(&target(), me_at(150.0, 0.0), seed, rest, &EqTune { pace, ..tune0() });
                    for i in 0..EQ_PLATES {
                        let first = (0..pl.lurch_n()).map(|k| pl.lurch(i, k).t).fold(f32::MAX, f32::min);
                        assert!(first > EQ_HEAVE - 0.2 && first > EQ_WARP_START + 0.2);
                        assert_eq!(pl.share(i, first - 1e-3), 0.0);
                        assert_eq!(pl.share(i, 0.0), 0.0);
                        // (exactly on its place from EQ_STILL; with the land eased back home, until the first lurch home)
                        let home = if rest { 60.0 } else { pl.lurch(i, EQ_K_HOME).t };
                        for t in [EQ_STILL, EQ_STILL + 0.01, 25.0, EQ_REST, home - 1e-3] {
                            if t < home {
                                assert_eq!(pl.share(i, t), 1.0, "{seed} {i} at {t}");
                            }
                        }
                        let end = if rest { EQ_REST } else { EQ_BACK_END };
                        assert_eq!(pl.share(i, end), if rest { 1.0 } else { 0.0 });
                        assert_eq!(pl.share(i, end + 7.0), if rest { 1.0 } else { 0.0 });
                        // (every lurch up done before EQ_STILL, every lurch home before EQ_BACK_END)
                        for k in 0..pl.lurch_n() {
                            let l = pl.lurch(i, k);
                            assert!(l.t + l.d < if k < EQ_K_HOME { EQ_STILL } else { EQ_BACK_END }, "{seed} {i} {k}: {l:?}");
                        }
                        assert!((pl.share(i, EQ_STILL - 1e-3) - 1.0).abs() < 1e-5);
                        if !rest {
                            assert!(pl.share(i, EQ_BACK_END - 1e-3).abs() < 1e-5);
                        }
                        // (sampled at 1 ms: the velocity never jumps)
                        let dt = 1e-3f64;
                        let s = |t: f64| f64::from(pl.share(i, t as f32));
                        let mut t = EQ_HEAVE as f64 - 0.5;
                        let mut v0 = (s(t + dt) - s(t)) / dt;
                        let mut peak = 0.0f64;
                        while t < end as f64 + 0.5 {
                            let v = (s(t + 2.0 * dt) - s(t + dt)) / dt;
                            assert!((v - v0).abs() < 0.06, "seed {seed} plate {i} pace {pace} at {t:.3}: {v0} to {v}");
                            peak = peak.max(v.abs());
                            v0 = v;
                            t += dt;
                        }
                        assert!(peak > 0.2, "it moves at all");
                    }
                }
            }
        }
    }

    /// One lurch: from nothing with no jump in its speed, its speed peaking within its first fifth (a hard start), an
    /// overshoot of about 8% that settles, at rest at its end with no jump.
    #[test]
    fn eq_a_lurch_starts_hard_overshoots_and_settles() {
        let n = 100_000;
        let (mut vmax, mut at_v, mut top, mut at_top) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
        let mut prev = 0.0f64;
        for j in 1..=n {
            let u = j as f64 / n as f64;
            let y = f64::from(eq_ease(u as f32));
            let v = (y - prev) * n as f64;
            if v > vmax {
                (vmax, at_v) = (v, u);
            }
            if y > top {
                (top, at_top) = (y, u);
            }
            // (rising all the way to its overshoot)
            if u < at_top.max(0.3) && u < 0.45 {
                assert!(y >= prev - 1e-6, "dips at {u}");
            }
            prev = y;
        }
        eprintln!("eq_ease: speed peaks at {at_v:.3} ({vmax:.2} of the mean), overshoot {:.3} at {at_top:.3}", top - 1.0);
        assert!(at_v <= 0.2, "the speed peaks at {at_v}");
        assert!((top - 1.0 - 0.08).abs() < 0.015, "overshoot {}", top - 1.0);
        let d = 1e-4f32;
        assert!(eq_ease(d) / d < 0.01 && (1.0 - eq_ease(1.0 - d)).abs() / d < 0.01, "no speed at either end");
        assert_eq!((eq_ease(0.0), eq_ease(1.0)), (0.0, 1.0));
    }

    /// The lurches as the timeline has them: the heave at EQ_HEAVE with 35%, three lurches (12, 10, 6%) each plate on its
    /// own time within 0.4 s, the climax at EQ_CLIMAX the biggest, the heave and the climax within 0.12 s on every plate;
    /// the shares adding to 1; the build's shudder only between, none from EQ_STILL; never two plates at the same time.
    #[test]
    fn eq_the_lurches_keep_the_timeline() {
        assert!((EQ_SHARE[..EQ_K_HOME].iter().sum::<f32>() - 1.0).abs() < 1e-6);
        assert!((EQ_SHARE[EQ_K_HOME..].iter().sum::<f32>() + 1.0).abs() < 1e-6);
        assert_eq!(EQ_BASE[0], EQ_HEAVE);
        assert_eq!(EQ_BASE[EQ_K_CLIMAX], EQ_CLIMAX);
        assert!(EQ_SHARE[EQ_K_CLIMAX] > EQ_SHARE[0] && (1..EQ_K_CLIMAX).all(|k| EQ_SHARE[k] < EQ_SHARE[0] && EQ_SHARE[k] < EQ_SHARE[k - 1]));
        for seed in [1u32, 37, 222, 500, 997] {
            for rest in [true, false] {
                let pl = plates(seed, rest, me_at(150.0, 0.0));
                assert_eq!(pl.lurch_n(), if rest { 5 } else { 7 });
                for k in 0..pl.lurch_n() {
                    let ts: Vec<f32> = (0..EQ_PLATES).map(|i| pl.lurch(i, k).t).collect();
                    let spread = if k == 0 || k == EQ_K_CLIMAX { 0.1201 } else { 0.4001 };
                    assert!(ts.iter().all(|t| (t - EQ_BASE[k]).abs() <= spread), "{seed} lurch {k}: {ts:?}");
                    let mut s = ts.clone();
                    s.sort_by(f32::total_cmp);
                    // (the heave's and the climax's order a permutation: never two plates at once; the others' spread by a
                    // hash too, so two may now and then land together)
                    if k == 0 || k == EQ_K_CLIMAX {
                        assert!(s.windows(2).all(|w| w[1] - w[0] > 1e-4), "{seed} lurch {k}: two plates at once");
                    }
                    assert!(s.windows(3).all(|w| w[2] - w[0] > 1e-4), "{seed} lurch {k}: three plates at once");
                }
                for i in 0..EQ_PLATES {
                    for k in 1..pl.lurch_n() {
                        assert!(pl.lurch(i, k).t > pl.lurch(i, k - 1).t, "{seed} {i}: in order");
                    }
                    // (a little past 1 in the climax's overshoot, 1 from EQ_STILL)
                    let over = (0..200).map(|j| pl.share(i, EQ_CLIMAX + j as f32 * 0.01)).fold(0.0f32, f32::max);
                    assert!(over > 1.02 && over < 1.06, "{seed} {i}: the climax overshoots to {over}");
                    assert_eq!(pl.slipping(i, EQ_STILL + 0.5), 0.0);
                    assert_eq!(pl.slipping(i, EQ_HEAVE - 0.6), 0.0);
                }
            }
        }
        assert_eq!(eq_build(EQ_BUILD_T), 0.0);
        assert_eq!(eq_build(EQ_STILL), 0.0);
        assert!(eq_build(EQ_CLIMAX) > 0.95 && eq_build(16.0) > 0.0 && eq_build(16.0) < eq_build(18.0));
        // (the clip from the fire to the climax under 20 s)
        assert!(EQ_CLIMAX + 1.4 < 20.0);
    }

    /// The offsets: whole blocks, the up side in giant steps up to the cliff at the fault, the canyon dropping beside it,
    /// the two sides apart and sliding opposite ways, the end segments about half; and the knobs scale them.
    #[test]
    fn eq_offsets_are_whole_and_the_cliff_is_at_the_fault() {
        for seed in 1..=997u32 {
            let pl = plates(seed, true, me_at(300.0, 40.0));
            for i in 0..EQ_PLATES {
                let o = pl.offset(i);
                assert_eq!(pl.disp(i, EQ_REST), [o[0] as f32, o[1] as f32, o[2] as f32]);
                let (b, s) = (i / 3, i % 3);
                let up = b < 4;
                let along = o[0] as f32 * pl.fdir[0] + o[2] as f32 * pl.fdir[1];
                let away = -o[0] as f32 * pl.fdir[1] + o[2] as f32 * pl.fdir[0];
                assert!(if up { along > 2.0 && away > 0.0 } else { along < -2.0 && away < 0.0 }, "{seed} {i}: {o:?}");
                assert!(o[1] != 0 && (o[1] > 0) == up, "{seed} {i}: {o:?}");
                if s == 1 {
                    let end = pl.offset(i - 1)[1];
                    assert!(o[1].abs() > end.abs() || o[1].abs() < 6, "{seed} {i}: the middle {o:?}, the end {end}");
                }
            }
            for s in 0..3 {
                let r: Vec<i32> = (0..7).map(|b| pl.offset(b * 3 + s)[1]).collect();
                // (the cliff at the fault: the up side's steps fall away from it, the canyon is the deepest of the down side)
                assert!(r[0] > r[1] && r[1] > r[2] && r[2] > r[3] && r[3] > 0, "{seed} seg {s}: {r:?}");
                assert!(r[4] < r[5] && r[5] < r[6] && r[6] < 0, "{seed} seg {s}: {r:?}");
                if s == 1 {
                    assert!(r[0] >= 52 && r[0] <= 56 && r[4] <= -36 && r[4] >= -40, "{seed}: {r:?}");
                }
            }
            let big = EqPlates::new(&target(), me_at(300.0, 40.0), seed, true, &EqTune { slip: 2.0, heave: 2.0, ..tune0() });
            assert!((0..EQ_PLATES).all(|i| { let o = big.offset(i); o[0].abs() <= 24 && o[2].abs() <= 24 && o[1].abs() <= 112 }));
            let flat = EqPlates::new(&target(), me_at(300.0, 40.0), seed, true, &EqTune { heave: 0.0, ..tune0() });
            assert!((0..EQ_PLATES).all(|i| flat.offset(i)[1] == 0));
        }
    }

    /// Two plates either side of a boundary never close on each other by more than the cut is wide, so a plate's walls
    /// never pass through its neighbour's.
    #[test]
    fn eq_neighbours_never_close_past_the_cut() {
        for seed in [1u32, 37, 222, 500, 997] {
            let pl = plates(seed, true, me_at(300.0, 40.0));
            let n = [-pl.fdir[1], pl.fdir[0]];
            let o = |i: usize| { let o = pl.offset(i); [o[0] as f32, o[2] as f32] };
            let close = |a: usize, b: usize, axis: [f32; 2]| {
                let (oa, ob) = (o(a), o(b));
                // (a lies on the low side of b along axis: closing is a moving up into b)
                (oa[0] - ob[0]) * axis[0] + (oa[1] - ob[1]) * axis[1]
            };
            // (by design at most 3 blocks; each plate's offset is whole blocks of the world, not of the fault's way, which
            // can add up to a block and a half between two: never past touching)
            let most = 2.0 * EQ_CUT_HALF + 0.1;
            for s in 0..3 {
                for (a, b) in [(0, 1), (1, 2), (2, 3)] {
                    assert!(close(a * 3 + s, b * 3 + s, n) <= most, "{seed}: bands {a}-{b} seg {s}");
                }
                for (a, b) in [(4, 5), (5, 6)] {
                    assert!(close(b * 3 + s, a * 3 + s, n) <= most, "{seed}: bands {a}-{b} seg {s}");
                }
                assert!(close(12 + s, s, n) <= most, "{seed}: the main fault, seg {s}");
            }
            for b in 0..7 {
                assert!(close(b * 3, b * 3 + 1, pl.fdir) <= most && close(b * 3 + 1, b * 3 + 2, pl.fdir) <= most, "{seed}: band {b}'s segments");
            }
            // (the outermost bands against the fixed land past the rim)
            for s in 0..3 {
                let (u, d) = (o(9 + s), o(18 + s));
                assert!(u[0] * n[0] + u[1] * n[1] <= most && -(d[0] * n[0] + d[1] * n[1]) <= most);
            }
        }
    }

    /// The player inside the zone on its up side rides the cliff's band (middle segment when it can be), well clear of
    /// its edges; far off, they are on no plate and the main crack passes them by about EQ_PASS, on past them, never
    /// under their feet.
    #[test]
    fn eq_the_rider_rises_and_the_crack_passes_the_far_player() {
        for seed in [1u32, 37, 222, 500, 997] {
            for deg in [0.0, 70.0, 135.0, 250.0] {
                for d in [5.0, 30.0, 60.0, 120.0, 180.0] {
                    let me = me_at(d, deg);
                    let pl = plates(seed, true, me);
                    let i = pl.rider().unwrap_or_else(|| panic!("{seed} {deg} {d}: no rider"));
                    assert!(i / 3 == 0 && pl.offset(i)[1] > 20, "{seed} {deg} {d}: plate {i}");
                    let (mx, mz) = ((me[0] - 10.0) as f32, (me[2] + 3.0) as f32);
                    let (on, e) = pl.where_at(mx, mz);
                    assert!(on == Some(i) && e >= 10.0, "{seed} {deg} {d}: on {on:?} {e}");
                    assert!((pl.me_uv[1] - EQ_RIDE_V * pl.reach).abs() < 0.6, "{seed} {deg} {d}: {:?}", pl.me_uv);
                    if d >= 60.0 && d <= 120.0 {
                        assert!(i == 1, "{seed} {deg} {d}: rides plate {i}");
                    }
                    let (x, z) = (me[0].floor() as i32, me[2].floor() as i32);
                    assert!(pl.fault_at(x, z).is_none());
                }
                for d in [200.0, 215.0, 230.0, 245.0] {
                    // (round the zone's end: riding well inside, or well outside on no plate)
                    let me = me_at(d, deg);
                    let pl = plates(seed, true, me);
                    let (on, e) = pl.where_at((me[0] - 10.0) as f32, (me[2] + 3.0) as f32);
                    assert!(e >= 10.0 && (on.is_none() == pl.rider().is_none()), "{seed} {deg} {d}: {on:?} {e}");
                }
                for d in [300.0, 600.0, 1000.0] {
                    let me = me_at(d, deg);
                    let pl = plates(seed, true, me);
                    assert!(pl.rider().is_none() && pl.plate_of((me[0] - 10.0) as f32, (me[2] + 3.0) as f32).is_none());
                    assert!((pl.me_uv[1] - EQ_PASS).abs() < 0.6 && pl.crack_end >= pl.me_uv[0] + EQ_PAST - 1.0, "{seed} {deg} {d}: {:?}", pl.me_uv);
                    // (the crack cut beside them and past them; nothing under their feet)
                    let (x, z) = (me[0].floor() as i32, me[2].floor() as i32);
                    assert!(pl.fault_at(x, z).is_none());
                    let at = |u: f32, v: f32| {
                        let (u, v) = (u + pl.shift[0] as f32, v + pl.shift[1] as f32);
                        ((10.0 + u * pl.fdir[0] - v * pl.fdir[1]) as i32, (-3.0 + u * pl.fdir[1] + v * pl.fdir[0]) as i32)
                    };
                    let cut = |u: f32| (-6..=6).any(|dv| { let (x, z) = at(u, dv as f32 * 2.0); pl.fault_at(x, z).is_some_and(|f| f.main) });
                    // (the line here is unbent: the crack wanders from it by up to about 10 blocks either way)
                    assert!(cut(pl.me_uv[0]) && cut(pl.me_uv[0] + EQ_PAST - 12.0), "{seed} {deg} {d}");
                    assert!(!cut(pl.me_uv[0] + EQ_PAST + 12.0), "{seed} {deg} {d}: past its end");
                }
            }
        }
    }

    /// The no-stretch guarantee: every column of the zone that `fault_at` does not cut has its four corners and its
    /// middle on one plate (or on plates that never move), so no face outside a cut has its vertices on two plates.
    /// Prints the margin: how much nearer than EQ_CUT_HALF to a boundary any column with corners on two plates lies.
    #[test]
    fn eq_no_face_outside_a_cut_spans_two_plates() {
        let mut worst = 0.0f32;
        let mut cuts = 0usize;
        for (seed, me) in [(1u32, me_at(120.0, 0.0)), (37, me_at(600.0, 70.0)), (222, me_at(30.0, 135.0)), (500, me_at(200.0, 250.0)), (997, me_at(1000.0, 300.0)), (613, me_at(90.0, 200.0))] {
            for rest in [true, false] {
                let pl = plates(seed, rest, me);
                let (mid, r) = pl.zone();
                let (cx, cz) = (mid[0].floor() as i32, mid[1].floor() as i32);
                let ri = r.ceil() as i32 + 4;
                let still = |p: Option<usize>| p.is_none_or(|i| pl.offset(i) == [0; 3]);
                for z in cz - ri..=cz + ri {
                    for x in cx - ri..=cx + ri {
                        let (lx, lz) = ((x - pl.block[0]) as f32, (z - pl.block[2]) as f32);
                        let ps = [pl.plate_of(lx + 0.5, lz + 0.5), pl.plate_of(lx, lz), pl.plate_of(lx + 1.0, lz), pl.plate_of(lx, lz + 1.0), pl.plate_of(lx + 1.0, lz + 1.0)];
                        let one = ps.iter().all(|p| *p == ps[0] || (still(*p) && still(ps[0])));
                        if one {
                            continue;
                        }
                        let e = pl.where_at(lx + 0.5, lz + 0.5).1;
                        worst = worst.max(e);
                        let f = pl.fault_at(x, z);
                        assert!(f.is_some(), "seed {seed} rest {rest}: column {x} {z} spans plates {ps:?} uncut, {e:.2} from the boundary");
                        let f = f.unwrap();
                        assert!(f.at >= EQ_CRACK && f.at <= EQ_CRACK_BY, "seed {seed}: cut at {}", f.at);
                        cuts += 1;
                    }
                }
            }
        }
        eprintln!("columns spanning two plates: {cuts}, all cut; the farthest of them {worst:.2} from a boundary: margin {:.2} of EQ_CUT_HALF {EQ_CUT_HALF}", EQ_CUT_HALF - worst);
        assert!(EQ_CUT_HALF - worst >= 0.8);
    }

    /// Every cut is reached by EQ_CRACK_BY, the main fault first and out from the target, a side crack never before the
    /// crack it leaves; every column of the main fault's cut goes down to its floor.
    #[test]
    fn eq_the_cracks_race_out_in_order() {
        for (seed, me) in [(7u32, me_at(200.0, 30.0)), (37, me_at(1000.0, 200.0)), (500, me_at(40.0, 90.0))] {
            for reach in [100.0, 160.0, 220.0] {
                let pl = EqPlates::new(&target(), me, seed, true, &EqTune { reach, ..tune0() });
                let (mid, r) = pl.zone();
                let (mut first_side, mut main_n, mut n) = (f32::MAX, 0, 0);
                for z in ((mid[1] - r) as i32..(mid[1] + r) as i32).step_by(2) {
                    for x in ((mid[0] - r) as i32..(mid[0] + r) as i32).step_by(2) {
                        if let Some(f) = pl.fault_at(x, z) {
                            n += 1;
                            assert!(f.at >= EQ_CRACK && f.at <= EQ_CRACK_BY, "{seed} {reach}: {f:?}");
                            if f.main {
                                main_n += 1;
                                assert_eq!(f.floor, EQ_CUT_MAIN_Y);
                            } else {
                                assert_eq!(f.floor, EQ_CUT_Y);
                                first_side = first_side.min(f.at);
                            }
                        }
                    }
                }
                assert!(n > 500 && main_n > 100, "{seed} {reach}: {n} cut, {main_n} main");
                // (the side cracks leave the main one where it reaches the segments' edges)
                assert!(first_side >= EQ_CRACK + EQ_SEG * pl.reach / pl.crack_v() - 0.1, "{seed} {reach}: a side crack at {first_side}");
                // (the far end of the main crack, past the player, in time too)
                assert!(pl.arrive([pl.crack_end, 0.0], K_MAIN) <= EQ_CRACK_BY);
            }
        }
    }

    #[test]
    fn eq_the_plan_is_in_time_order_and_jolts_only_on_the_beats() {
        let json = include_str!("../../../orbital-sounds/assets/orbital/sounds.json");
        for terrain in [false, true] {
            for me in [me_at(40.0, 90.0), me_at(250.0, 90.0), me_at(900.0, 90.0)] {
                let ev = plan(&crate::lasers::EARTHQUAKE, &target(), terrain, "minecraft:overworld", 37.0, me, 0);
                assert!(ev.windows(2).all(|w| w[0].0 <= w[1].0), "in time order");
                assert!(ev.iter().all(|e| e.0 < crate::lasers::EARTHQUAKE.length));
                // (terrain off: nothing touches the world, no commands, no edits, no reads)
                if !terrain {
                    assert!(!ev.iter().any(|e| matches!(e.1, Act::Cmd(_) | Act::Blocks(_) | Act::Read { .. } | Act::Spare(_))));
                }
                let sounds: Vec<String> = ev.iter().filter_map(|(_, a)| if let Act::Sound { event, .. } | Act::SoundFrom { event, .. } = a { Some(event.clone()) } else { None }).collect();
                for s in ["bed", "blow", "heaveblow", "climaxblow", "climax", "settle"] {
                    assert!(sounds.iter().any(|e| e.starts_with(&format!("orbital:earthquake.{s}_")) || e.starts_with(&format!("orbital:earthquake.syn_{s}_"))), "{s}");
                }
                for e in &sounds {
                    let key = e.strip_prefix("orbital:").unwrap();
                    let at = json.find(&format!("\"{key}\"")).unwrap_or_else(|| panic!("{e} in sounds.json"));
                    let name = json[at..].split("\"name\": \"").nth(1).and_then(|r| r.split('"').next()).unwrap();
                    assert!(name.starts_with("orbital:earthquake/"), "{e}: {name}");
                    let file = format!("../orbital-sounds/assets/orbital/sounds/{}.ogg", name.trim_start_matches("orbital:"));
                    assert!(std::path::Path::new(&file).exists(), "{file}");
                }
                // (the knocks for a player not riding: the first heave, two lurches, the climax; none for a rider)
                let rider = plates(37, terrain, me).rider().is_some();
                assert_eq!(ev.iter().filter(|e| matches!(e.1, Act::Shove { .. })).count(), if rider { 0 } else { 4 }, "{me:?}");
                assert!(ev.iter().any(|e| matches!(e.1, Act::Table(_))));
                // (the climax the hardest shake; shakes only in the jolts' wake, none before the blow's or between the beats:
                // no running tremor)
                let shakes: Vec<(f32, f32, f32)> = ev.iter().filter_map(|(t, a)| if let Act::Shake { strength, seconds } = a { Some((*t, *strength, *seconds)) } else { None }).collect();
                let top = shakes.iter().fold((0.0f32, 0.0f32), |m, s| if s.1 > m.1 { (s.0, s.1) } else { m });
                assert!(shakes.iter().filter(|s| (s.0 - EQ_CLIMAX).abs() < 0.6).any(|s| s.1 >= top.1 - 1e-6), "{me:?}: the hardest at {top:?}");
                let pl = plates(37, terrain, me);
                let beats = eq_jolts(&pl, me);
                for s in &shakes {
                    let after = beats.iter().filter(|b| b.0 <= s.0 + 1e-4).map(|b| s.0 - b.0).fold(f32::MAX, f32::min);
                    assert!(after < 3.6 && s.2 <= 3.01, "{me:?}: a shake at {} ({} s) {after} s after a beat", s.0, s.2);
                }
            }
        }
        // (the knob `jolt` at 0: no jolt at all; a rider half)
        let me = me_at(250.0, 90.0);
        assert_eq!(eq_jolt_gain(&plates(37, true, me), me, 0.0), 0.0);
        let mut q = Plan { laser: &crate::lasers::EARTHQUAKE, ev: Vec::new(), rng: Rng::new(1), bx: 0, by: 0, bz: 0 };
        eq_jolt(&mut q, 6.0, 0.0, 1.0);
        assert!(q.ev.is_empty());
        let rider = me_at(100.0, 90.0);
        assert!(plates(37, true, rider).rider().is_some());
        assert!((eq_jolt_gain(&plates(37, true, rider), rider, 1.0) - 0.5).abs() < 1e-6);
        // (the table: the magic, the jolts in time order, the blow, the heave, the lurches, the climax the hardest)
        let pl = plates(37, false, me);
        let w: Vec<f32> = eq_table(&pl, me, 1.0).iter().map(|b| f32::from_bits(*b)).collect();
        assert_eq!(w[0], EQ_MAGIC);
        let n = w[13] as usize;
        assert!(n == 1 + pl.lurch_n() && n <= EQ_EV_MAX && w.len() >= EQ_T_EV + 2 * n);
        assert!((0..n - 1).all(|i| w[EQ_T_EV + 2 * i] <= w[EQ_T_EV + 2 * i + 2]));
        assert!((0..n).any(|i| w[EQ_T_EV + 2 * i + 1] == 1.0 && (w[EQ_T_EV + 2 * i] - EQ_CLIMAX).abs() < 0.3));
        assert_eq!((w[14] as i32, w[15] as i32), (pl.shift[0], pl.shift[1]));
    }

    /// The hold's circle holds every chunk the land edits: every moving or cut column of the zone within it, less a chunk.
    #[test]
    fn eq_hold_covers_the_zone() {
        for (seed, me) in [(7u32, me_at(200.0, 30.0)), (37, me_at(120.0, 200.0))] {
            let pl = plates(seed, true, me);
            let mut params = [0.0f32; 16];
            for (i, v) in pl.warp_params() {
                params[i] = v;
            }
            params[4] = pl.block[0] as f32 + 0.5;
            params[5] = pl.block[2] as f32 + 0.5;
            let (hx, hz, hr) = eq_hold_within(&params);
            let (mid, r) = pl.zone();
            assert!(hr >= r + 12.0 && (hx - mid[0]).hypot(hz - mid[1]) < 1.0, "{hx} {hz} {hr} against {mid:?} {r}");
            for z in ((mid[1] - r - 20.0) as i32..(mid[1] + r + 20.0) as i32).step_by(3) {
                for x in ((mid[0] - r - 20.0) as i32..(mid[0] + r + 20.0) as i32).step_by(3) {
                    if pl.column(x, z).is_some() {
                        assert!((f64::from(x) + 0.5 - mid[0]).hypot(f64::from(z) + 0.5 - mid[1]) < r, "{x} {z} past the zone's circle");
                    }
                }
            }
        }
    }

    /// `CB_SEED=37 CB_OUT=FILE PL_ME=x,y,z [PL_HILLS=H] cargo test --release eq_write_table -- --ignored`: the pass's
    /// table for tools/preview.py (the target at 0.5 65 0.5), with the land's heights on its hills.
    #[test]
    #[ignore]
    fn eq_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or("0,65,250".into(), |v| v).split(',').map(|v| v.parse().unwrap()).collect();
        let me = [me[0], me[1], me[2]];
        let t = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let pl = EqPlates::new(&t, me, seed as u32, false, &tune0());
        let mut w = eq_table(&pl, me, 1.0);
        // (the land's shape, as tools/preview draws it: PL_HILLS=H its hills (main.rs's hills_h), level otherwise)
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        if hills != 0.0 {
            let f = |x: f64, z: f64| (hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin())) as f32;
            let h = super::super::eq_ground::eq_ground_words(&pl, f);
            w.resize(super::super::eq_ground::EQ_H + h.len(), 0);
            w[super::super::eq_ground::EQ_H..].copy_from_slice(&h);
        }
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}
