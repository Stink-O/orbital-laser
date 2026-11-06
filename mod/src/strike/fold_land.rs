//! The Fold's land: the scar. The crease pattern smashed into the ground as it slammed back: a wound whose outline is the
//! pattern's fourth ring (FD_INV, fold_warp.wgsl's cp_ix: about 600 across, its corners out to 350), every kite of the pattern a
//! panel of its own, the mandala laid out on them so its wedges run along the big creases and its bands along the chords, broken
//! into tilted plates, split by straight fissures along the creases, burnt in patches, round a shaft down to bedrock, a ragged
//! rim, the land past it flattened, blackened and rayed. The warp holds it up at the land's level as it swaps in and lets it
//! fall, kite by kite (fold_warp.wgsl's fw_sunk, the same `bowl`).
//!
//! All of it goes in behind the game's hold on the terrain (`render.hold-world`, FD_HIDDEN): the land on screen stays as it
//! was while one wave goes from the middle out, FD_LAND0 to FD_LAND1, and the whole crater takes its place on the one frame
//! the hold lets go, FD_REVEAL, as the last slam lands. Every chunk is edited once, on one tick (`fd_tick`): its cut, its
//! rubble, heaps, fires and felled trees together. A second edit of a chunk is a second resend, nine light jobs and its
//! sections meshed again, so nothing but falling blocks and fires changes the land after the reveal. It is read at the
//! fire, worked out a little ahead of when it is due, in one chain of stages (`fd_work`).
//!
//! What makes the look, each one apart (see the constants of the same name; each can be taken out alone):
//!   `mandala`        the unbroken pattern (mirrored): terraces and tiles, what everything else breaks; `laid` lays it on the kites
//!   `kite_drop`      each kite of the crease pattern its own panel: a drop and a tilt, so the creases stand as scarps
//!   FD_SHATTER       the plates: `plate`, each with its own drop, tilt and slide, the pattern going with it
//!   FD_CRACKS        the cracks between the plates
//!   FD_BURN          the pattern burnt off the plates (`burn`), whole plates of it gone
//!   FD_FISSURES      the six fissures along the mountain creases, nearly straight, with forks, running out past the rim (`fissure`)
//!   FD_RING_CRACKS   broken lengths of the chords (`ring_crack`)
//!   FD_SHAFT, FD_FUNNEL   the void wound at the middle: a shaft to bedrock and the funnel it fell into (0: none)
//!   FD_HEAP          the rim's heap of thrown earth (0: none)
//!   FD_CHARRED       the blackened land (`charred`), FD_RAYS the rays in it, one a wedge (`Shape::ray`)
//!   FD_FELLED        the trees felled pointing away (`fd_fell`)
//!   FD_RUBBLE_N, FD_HEAPS   the rubble strewn (`fd_rubble`), the heaps of it on the crater's floor
//!   FD_THROWN        the falling blocks thrown as each ring lands (`fd_thrown`)
//!   FD_EMBERS        the fires left burning (`fd_embers`)
//!   FD_SMOKE         the smoke rising after it
use super::fold::{FD_BEAT, FD_FOLD, FD_HIDDEN, FD_LEN, FD_N as FD_CREASES, FD_RELEASE, FD_REVEAL, FD_RINGS, FD_SEAL, FD_TEAR, FdWedge, fd_wedge};
use super::rod::{Column, Due, LEAF_NAMES, LEAVES, LOG_X, LOG_Y, LOG_Z, Land, Sector, Used, ring_columns, take_in_grid};
use super::{Act, Blocks, Col, Plan, Rng, TIDY_BORDER, bedrock_top, mh, tidy, vnoise};
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;

// ---- the switches ------------------------------------------------------------------------------------------------
/// The plates tilted, dropped and slid (false: the pattern one piece, on its terraces).
const FD_SHATTER: bool = true;
/// The cracks between the plates.
const FD_CRACKS: bool = true;
/// The pattern burnt off in patches, some of the plates' whole.
const FD_BURN: bool = true;
/// The fissures along the mountain creases.
const FD_FISSURES: bool = true;
/// The broken arcs of the crease rings.
const FD_RING_CRACKS: bool = true;
/// The land past the rim blackened, and the rays in it (false: blackened evenly).
const FD_CHARRED: bool = true;
const FD_RAYS: bool = true;
/// The trees felled lying pointing away (false: swept off with the rest).
const FD_FELLED: bool = true;
/// Rubble tries, heaps on the floor, falling blocks thrown, fires left burning (0: none of it).
const FD_RUBBLE_N: usize = 8000;
const FD_RUBBLE_JOBS: u32 = 14;
const FD_HEAPS: usize = 260;
const FD_HEAP_JOBS: u32 = 16;
const FD_THROWN: [usize; 4] = [120, 180, 240, 160];
/// The blocks that peel off the land along the creases and fall upward into the fold, a batch as each stage of it opens
/// (`fd_peel`); all 0 takes them out. They are real falling blocks with no gravity, gone at the crush.
const FD_PEEL: [usize; 4] = [100, 140, 160, 120];
/// How wide round the player the land is left alone until the last slam: they stand on it through the fold (FW_ISLE + 4).
const FD_ISLE: f64 = 30.0;
const FD_EMBERS: usize = 3200;
const FD_EMBER_JOBS: u32 = 12;
/// Plumes of smoke over the crater after it (0: none).
const FD_SMOKE: usize = 20;

// ---- the sizes ---------------------------------------------------------------------------------------------------
/// The crater's radius, about: its edge is the pattern's fourth ring, 230 to 350 out, its long corners on every other crease (`Shape::edge`).
pub(super) const FD_R: f64 = 300.0;
/// The pattern's own radius (in `mandala`'s units), and how far out it reaches, of the way to the crater's edge: past it the
/// crater's walls are bare burnt rock.
const FD_PR: f64 = 64.0;
const FD_REACH: f64 = 0.92;
/// How deep the bowl is under the land's level (fold_warp.wgsl's FW_BOWL) and how much the pattern's terraces add (per unit of its `dig`).
pub(super) const FD_BOWL: f64 = 66.0;
const FD_TERR: f64 = 1.5;
/// The shaft's radius (it wanders); the funnel its mouth has fallen into, how deep and how far out.
pub(super) const FD_SHAFT: f64 = 22.0;
const FD_FUNNEL: f64 = 34.0;
const FD_FUNNEL_R: f64 = 56.0;
/// The most a hollow is filled up under the floor.
const FD_FILL: i32 = 30;
/// The rim's heap, its reach in crater radii, how high.
const FD_RIM: f64 = 1.14;
const FD_HEAP: f64 = 28.0;
/// The land flattened, the band past it of stripped crowns and knocked trees, blackened, rubble strewn.
const FD_FLAT: f64 = 340.0;
const FD_BAND: f64 = 26.0;
/// Past this only rays of char: nothing is taken away, so nothing is left hanging.
const FD_BLOWN: f64 = FD_FLAT * 1.09 + FD_BAND;
const FD_CHAR: f64 = 396.0;
const FD_RUBBLE: f64 = 404.0;
/// How much of the land is read, in how many rings (each asked of the world on its own).
const FD_READ: i32 = 410;
const FD_GW: i32 = 2 * FD_READ + 1;
const FD_BELOW: u32 = 36;
const FD_ABOVE: u32 = 1;
const FD_PARTS: i32 = 96;
/// Mobs and items killed this far from the target.
const FD_KILL: i32 = 360;
/// The plates: how many in a ring round the target. They grow with the radius (log-polar cells: a plate about a sixth of
/// `r + FD_PLATE0` across), `1 / FD_STRETCH` longer than wide: wedges.
const FD_PLATES: u32 = 34;
const FD_STRETCH: f64 = 0.68;
const FD_PLATE0: f64 = 40.0;
/// The mandala's twelve folds.
const FD_N: f64 = 12.0;

/// The land's wave: from when to when, behind the hold. It ends this long before the reveal: a chunk's resend, its light
/// and its meshes take the game some tenths of a second, and a chunk not ready by the reveal shows late.
pub(super) const FD_LAND0: f32 = FD_HIDDEN.start + 0.2;
pub(super) const FD_LAND1: f32 = FD_REVEAL - 1.6;
/// The chunks the player's island stands on go in just before the reveal, so they swap in with the rest and the ground goes
/// from under them with the slam.
const FD_ISLE_AT: f32 = FD_REVEAL - 0.5;
/// What a column counts for in the wave's pace, past its blocks (`fd_cost`): what its chunk costs the frame, its resend,
/// light and meshes, whatever is changed in it. It keeps the chunks a second even: they are what the frames feel.
const FD_PER_CHUNK: f64 = 30.0;
/// How long before its edits are due a part of the wave is worked out (the plan holds what is waiting: the wave's whole
/// edits are too much to carry for half a minute).
const FD_AHEAD: f32 = 30.0;
/// The most runs of edits worked out and not due yet: they wait in the mod's memory, 64 MiB with the land's square in it, and hold the wave back past this.
const FD_HELD: usize = 860_000;
/// Strike seconds past which a column still not loaded is left out (logged): the forceload is given back at FD_LEN - 1.
const FD_LAND_BY: f32 = FD_LEN - 4.0;
/// How long, once the crater's land is in, it waits for more of the rest to come.
const FD_PATIENCE: f32 = 4.0;

// ---- the blocks --------------------------------------------------------------------------------------------------
/// Every block a column's cut names (`Cut` keeps their places here: there are ~370,000 cuts): the rainbow in concrete,
/// the same in glazed terracotta, the burnt rock.
const PAL: [&str; 38] = [
    "minecraft:red_concrete",
    "minecraft:orange_concrete",
    "minecraft:yellow_concrete",
    "minecraft:lime_concrete",
    "minecraft:green_concrete",
    "minecraft:cyan_concrete",
    "minecraft:light_blue_concrete",
    "minecraft:blue_concrete",
    "minecraft:purple_concrete",
    "minecraft:magenta_concrete",
    "minecraft:pink_concrete",
    "minecraft:white_concrete",
    "minecraft:red_glazed_terracotta",
    "minecraft:orange_glazed_terracotta",
    "minecraft:yellow_glazed_terracotta",
    "minecraft:lime_glazed_terracotta",
    "minecraft:green_glazed_terracotta",
    "minecraft:cyan_glazed_terracotta",
    "minecraft:light_blue_glazed_terracotta",
    "minecraft:blue_glazed_terracotta",
    "minecraft:purple_glazed_terracotta",
    "minecraft:magenta_glazed_terracotta",
    "minecraft:pink_glazed_terracotta",
    "minecraft:white_glazed_terracotta",
    // (24 on: burnt rock, the first BURNT of them the ground's patches)
    "minecraft:black_concrete",
    "minecraft:blackstone",
    "minecraft:coal_block",
    "minecraft:polished_blackstone",
    "minecraft:smooth_basalt",
    "minecraft:basalt",
    "minecraft:cobbled_deepslate",
    "minecraft:deepslate",
    "minecraft:tuff",
    "minecraft:gray_concrete",
    // (34 on: what glows)
    "minecraft:magma_block",
    "minecraft:crying_obsidian",
    "minecraft:obsidian",
    "minecraft:netherrack",
];
const BURNT: u8 = 24;
const BURNT_N: u8 = 10;
const MAGMA: u8 = 34;
const CRYING: u8 = 35;
const OBSIDIAN: u8 = 36;
const NETHERRACK: u8 = 37;
const AIR: &str = "minecraft:air";

fn conc(i: i32) -> u8 {
    i.rem_euclid(12) as u8
}
fn glazed(i: i32) -> u8 {
    12 + i.rem_euclid(12) as u8
}
/// A hash of column (x, z), 0 to 1.
fn cell(x: i32, z: i32, seed: u32, k: u32) -> f64 {
    mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, seed, k)
}
fn sstep(a: f64, b: f64, x: f64) -> f64 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

// ---- the mandala: the pattern before it broke ----------------------------------------------------------------------
/// A column of the pattern: how far the terrace is dug (or stands up, negative), its top and what is under it (`PAL`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Tile {
    pub dig: i32,
    pub top: u8,
    pub under: u8,
}

/// The wedge coordinate of angle `a` in a `n`-fold pattern: 0 on a wedge's middle line, 1 on its edge (a mirror
/// axis), the same either side of both: what makes the pattern a kaleidoscope's.
fn wedge(a: f64, n: f64) -> f64 {
    let w = TAU / n;
    ((a.rem_euclid(w) - w / 2.0).abs() / (w / 2.0)).clamp(0.0, 1.0)
}

/// The unbroken pattern at (`dx`, `dz`), in its own units (FD_PR across its radius; continuous: the tests ask at any
/// point). None past it. `seed` picks which rainbow phase it starts at.
pub(super) fn mandala(dx: f64, dz: f64, seed: u32) -> Option<Tile> {
    let r = dx.hypot(dz);
    if r >= FD_PR {
        return None;
    }
    let a = dz.atan2(dx);
    let w = wedge(a, FD_N);
    let phase = (seed % 12) as i32;
    // (the rainbow turns with the radius: every ring its own hue, every motif the hue five along)
    let hue = |r: f64| phase + (r / FD_PR * 11.0).floor() as i32;
    let t = |dig: i32, top: u8, under: u8| Some(Tile { dig, top, under });
    if r < 7.0 {
        // the eye (the shaft has taken most of it)
        return t(22, glazed(hue(r) + (w * 3.0) as i32 + 6), conc(hue(r)));
    }
    if r < 17.0 {
        // twelve petals, leaf-shaped, each a terrace higher than the field between them, and a line round every one
        let u = (r - 7.0) / 10.0;
        let pw = 0.06 + 0.94 * (u * PI).sin().powf(0.6);
        let arc = (w - pw) * r * (PI / FD_N);
        if arc.abs() < 0.55 {
            return t(17, glazed(hue(r) + 3), conc(hue(r) + 6));
        }
        return if w < pw { t(18, glazed(hue(r) + 5 + (u * 3.0) as i32), conc(hue(r) + 2)) } else { t(15, conc(hue(r)), conc(hue(r) + 4)) };
    }
    if r < 27.0 {
        // twenty-four diamonds on a field, a core in each
        let w24 = wedge(a, FD_N * 2.0);
        let arc = w24 * r * (PI / (FD_N * 2.0));
        let v = (r - 22.0).abs() / 5.0 + arc / 4.0;
        if v < 0.4 {
            return t(11, glazed(hue(r) + 8), conc(hue(r) + 2));
        }
        if v < 1.0 {
            return t(12, glazed(hue(r) + 4), conc(hue(r) + 7));
        }
        return t(14, conc(hue(r) + (r > 22.0) as i32), conc(hue(r) + 5));
    }
    if r < 39.0 {
        // scallops: the ring's edge bulging out at every wedge's edge, a line along it
        let re = 33.0 + 4.0 * (a * FD_N).cos();
        if (r - re).abs() < 0.9 {
            return t(10, glazed(hue(r) + 9), conc(hue(r) + 3));
        }
        return if r < re { t(11, glazed(hue(r) + 2 + (w * 2.0) as i32), conc(hue(r) + 5)) } else { t(9, conc(hue(r) + 6), conc(hue(r))) };
    }
    if r < 51.0 {
        // spokes, thirty-six of them, every other one a step down, the rainbow running across each wedge
        let w36 = wedge(a, FD_N * 3.0);
        let k = (w * 5.99) as i32;
        if w36 < 0.5 {
            return t(7, glazed(hue(r) + k * 2), conc(hue(r) + k));
        }
        return t(5, conc(hue(r) + k * 2 + 1), conc(hue(r) + k + 4));
    }
    // a sunburst: twelve long spikes and twelve short between them, standing up out of a step down
    let u = (r - 51.0) / (FD_PR - 51.0);
    if w < 1.0 - u {
        return t(-3, glazed(hue(r) + 7), conc(hue(r) + 1));
    }
    if w > 0.75 + 0.2 * u && u < 0.55 {
        return t(-1, glazed(hue(r) + 2), conc(hue(r) + 8));
    }
    t(3, conc(hue(r) + 3), conc(hue(r) + 9))
}

// ---- the crater's shape ------------------------------------------------------------------------------------------
#[derive(Clone, Copy)]
pub(super) struct Shape {
    cx: f64,
    cz: f64,
    ph: [f64; 4],
    seed: u32,
    /// How the crease pattern is turned, degrees (fold.rs's fd_turn).
    turn: f64,
    /// The height the crater is cut down from (`Job::Level`), and where bedrock begins.
    level: i32,
    bot: i32,
    /// Where the player stood (x, z): their island.
    me: [f64; 2],
    /// Which crease pattern (fold.rs's FD_PATTERNS): what parts each panel breaks into (`facet`).
    pattern: usize,
}
impl Shape {
    /// The pattern at bearing `a`.
    fn wedge(&self, a: f64) -> FdWedge {
        crate::meter::spend(300);
        fd_wedge(a, self.turn)
    }
    /// The crater's edge along bearing `a`: the pattern's fourth ring, chord by straight chord (each plate bites its own piece out of it, `fd_cut`).
    fn edge(&self, w: &FdWedge) -> f64 {
        1.0 / w.ix(3)
    }
    fn flat(&self, a: f64) -> f64 {
        FD_FLAT * (1.0 + 0.05 * (2.0 * a + self.ph[2]).sin() + 0.04 * (7.0 * a + self.ph[0]).sin())
    }
    /// How strongly bearing `a` lies in one of the blackened rays (0 to 1): one along each wedge's middle, between the
    /// fissures, each its own width and strength, with thinner streaks among them.
    fn ray(&self, a: f64) -> f64 {
        if !FD_RAYS {
            return 0.0;
        }
        let w = self.wedge(a);
        let i = w.k as u32;
        let f = w.v / (w.u + w.v).max(1e-6);
        let st = (mh(i, self.seed, 0xc1) * 0.55 + 0.45) * (PI * f).sin().powf(3.0 + 5.0 * mh(i, self.seed, 0xc2));
        let q = 30.0 / PI;
        let fine = ((vnoise(a.cos() * q, a.sin() * q, 1.0, self.seed ^ 0x73) - 0.5) / 0.3).clamp(0.0, 1.0);
        st.max(0.6 * fine)
    }
}
/// Which part of panel `i` of wedge `w` the point `r` out on its bearing is in, by the pattern's own lines across it (fold_warp.wgsl's cp_kite, cp_tri): UMBRELLA one part,
/// WATERBOMB four round its middle, DIAGONAL the two sides of its diagonal.
fn facet(pattern: usize, w: &FdWedge, i: usize, r: f64) -> u32 {
    if pattern == 0 {
        return 0;
    }
    // (in the two creases' own axes: a skew frame keeps which side of a line a point is on)
    let p = (w.u * r, w.v * r);
    let (b, c) = ((FdWedge::node(w.k, i), 0.0), (0.0, FdWedge::node(w.k1, i)));
    let (a, d) = if i == 0 { ((0.0, 0.0), (0.0, 0.0)) } else { ((FdWedge::node(w.k, i - 1), 0.0), (0.0, FdWedge::node(w.k1, i - 1))) };
    let side = |o: (f64, f64), e: (f64, f64)| (e.0 - o.0) * (p.1 - o.1) - (e.1 - o.1) * (p.0 - o.0) > 0.0;
    if pattern == 2 {
        let (o, e) = if (w.k + i) % 2 == 1 { (b, d) } else { (a, c) };
        return u32::from(side(o, e));
    }
    // (round its middle, spoke by spoke, as cp_tri)
    let v = (0.25 * (a.0 + b.0 + c.0 + d.0), 0.25 * (a.1 + b.1 + c.1 + d.1));
    let round = [a, b, c, d];
    (0..4).find(|j| side(v, round[*j]) && !side(v, round[(*j + 1) % 4])).map_or(0, |j| j as u32)
}
/// The floor's own panel: a panel of the crease pattern, a drop and a tilt of its own, so that the creases stand as scarps. `r` out along
/// bearing wedge `w`, in the wedge's cell `i`, its inner and outer chords `r0`, `r1` there.
fn kite_drop(seed: u32, w: &FdWedge, i: usize, r: f64, r0: f64, r1: f64, part: u32) -> f64 {
    let id = (w.k * 5 + i) as u32 * 4 + part;
    let h = |k: u32| mh(id, seed, k);
    let e = (r - 0.5 * (r0 + r1)) / (r1 - r0).max(1.0) * 2.0;
    // (each dips in towards the middle, or now and then out, its outer edge a scarp over the next)
    let tip = if h(0xf1) < 0.2 { -5.0 } else { 3.0 + 9.0 * h(0xf2) };
    -3.0 - 15.0 * h(0xf3) + tip * e
}
/// How deep the bowl is at u (crater radii out): a broad, flattish floor, steep near the edge.
fn bowl(u: f64) -> f64 {
    if u >= 1.0 {
        return 0.0;
    }
    FD_BOWL * (1.0 - u.powi(3)).powf(0.75)
}

/// The plate a point lies on: a cell of a jittered log-polar grid (so they grow with the radius, and close up round the
/// circle), its hash, where its middle is, and how far the point is from the plate's edge, in blocks.
#[derive(Clone, Copy)]
struct Plate {
    id: u32,
    /// Its middle: radius and bearing.
    sr: f64,
    sa: f64,
    gap: f64,
}
fn plate(seed: u32, r: f64, a: f64) -> Plate {
    crate::meter::spend(1_400);
    let n = f64::from(FD_PLATES);
    let k = n / TAU;
    let (p, q) = (a.rem_euclid(TAU) * k, (r + FD_PLATE0).ln() * k * FD_STRETCH);
    let (ip, iq) = (p.floor(), q.floor());
    // (the nearest two sites of the nine round it)
    let (mut d1, mut d2) = (f64::MAX, f64::MAX);
    let (mut s1, mut s2) = ((0.0, 0.0, 0u32), (0.0, 0.0, 0u32));
    for j in -1..=1 {
        for i in -1..=1 {
            let (ci, cj) = (ip + f64::from(i), iq + f64::from(j));
            let id = (ci.rem_euclid(n) as u32) * 4099 + cj as i32 as u32;
            let (sp, sq) = (ci + 0.12 + 0.76 * mh(id, seed, 0xa1), cj + 0.12 + 0.76 * mh(id, seed, 0xa2));
            let d = (p - sp).powi(2) + (q - sq).powi(2);
            if d < d1 {
                (d2, s2) = (d1, s1);
                (d1, s1) = (d, (sp, sq, id));
            } else if d < d2 {
                (d2, s2) = (d, (sp, sq, id));
            }
        }
    }
    // (the distance to the line halfway between the two, in cells; a cell is about (r + FD_PLATE0) / k blocks wide)
    let sep = ((s1.0 - s2.0).powi(2) + (s1.1 - s2.1).powi(2)).sqrt().max(1e-6);
    let gap = (d2 - d1) / (2.0 * sep) * (r + FD_PLATE0) / k;
    Plate { id: s1.2, sr: ((s1.1 / (k * FD_STRETCH)).exp() - FD_PLATE0).max(0.0), sa: s1.0 / k, gap }
}

/// A plate's fate.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Fate {
    /// It kept its pattern (burnt round its edges).
    Held,
    /// Its pattern mostly burnt off.
    Burnt,
    /// Gone: fallen in, no pattern left on it.
    Gone,
}
/// What became of plate `id`, whose middle is `u` crater radii out: the further out the worse, and ever more of the middle
/// survives than of the edge, so the pattern stays readable.
fn fate(id: u32, seed: u32, u: f64) -> Fate {
    if !FD_SHATTER && !FD_BURN {
        return Fate::Held;
    }
    let h = mh(id, seed, 0xa3);
    let gone = 0.05 + 0.12 * u * u;
    if h < gone {
        Fate::Gone
    } else if h < gone + 0.07 + 0.1 * u {
        Fate::Burnt
    } else {
        Fate::Held
    }
}
/// How far plate `id` is shifted at (dx, dz) (up or down, in blocks), whose middle is at `sa`, `sr`, `su` crater radii out:
/// dropped a little, and tilted, mostly sloping in towards the crater's middle, so each outer edge stands up (fault blocks);
/// now and then heaved up hard on one side, a fang of the pattern standing out of the floor.
fn shift(id: u32, seed: u32, dx: f64, dz: f64, sa: f64, sr: f64, su: f64, gone: bool) -> f64 {
    if !FD_SHATTER {
        return 0.0;
    }
    let h = |k: u32| mh(id, seed, k);
    let drop = -9.0 * h(0xa4).powi(2) - if gone { 9.0 + 6.0 * h(0xa5) } else { 0.0 };
    let heaved = h(0xa6) < 0.13;
    let slope = if heaved { 0.32 + 0.34 * h(0xa7) } else { 0.06 + 0.2 * h(0xa7) };
    let dir = sa + (h(0xa8) - 0.5) * if heaved { 3.0 } else { 1.4 };
    let (ox, oz) = (sr * sa.cos(), sr * sa.sin());
    let run = (dx - ox) * dir.cos() + (dz - oz) * dir.sin();
    (drop + slope * run + if heaved { 4.0 } else { 0.0 }).clamp(-30.0, 26.0) * (0.45 + 0.55 * sstep(0.0, 0.4, su))
}

/// A fissure at (r, a), if any: how near its middle (1) or edge (0), and the fissure's length. The six run along the mountain
/// creases, all but straight, out to where the last ring meets each, as far as the land read; each forks once, the branch leaning
/// off it.
fn fissure(s: &Shape, r: f64, a: f64, w: &FdWedge) -> Option<(f64, f64)> {
    if !FD_FISSURES || r > FD_RUBBLE {
        return None;
    }
    crate::meter::spend(600);
    // (every other crease, the mountains: one of the wedge's two)
    let k = if w.k % 2 == 0 { w.k } else { w.k1 };
    let b = a - FdWedge::bearing(k, s.turn);
    let off = (r * b.sin(), b.cos() > 0.0);
    if !off.1 {
        return None;
    }
    let i = k as u32;
    let h = |n: u32| mh(i, s.seed, 0xb0 + n);
    let len = (FdWedge::reach(k) * (0.8 + 0.2 * h(0))).min(FD_RUBBLE - 8.0);
    if r > len {
        return None;
    }
    let wander = (2.6 * (r / 37.0 + TAU * h(1)).sin() + 1.5 * (r / 13.0 + TAU * h(2)).sin() + 1.0 * (r / 5.1 + TAU * h(3)).sin()) * (r / 60.0).min(1.0);
    let off = off.0 - wander;
    let width = |l: f64, r0: f64| 1.0 + 7.0 * (1.0 - (r - r0) / (l - r0)).max(0.0).powf(0.7);
    let wd = width(len, 0.0);
    let main = (off.abs() < wd).then(|| (1.0 - off.abs() / wd, len));
    let fr = 90.0 + 130.0 * h(4);
    let branch = if r > fr {
        let l2 = fr + (len - fr) * (0.45 + 0.5 * h(5));
        let side = if h(6) < 0.5 { -1.0 } else { 1.0 };
        let o2 = off - side * (r - fr) * (0.2 + 0.12 * h(7));
        let w2 = 0.75 * width(l2, fr);
        (r < l2 && o2.abs() < w2).then(|| (1.0 - o2.abs() / w2, l2))
    } else {
        None
    };
    match (main, branch) {
        (Some(m), Some(b)) => Some(if m.0 > b.0 { m } else { b }),
        (m, b) => m.or(b),
    }
}
/// A broken length of a chord of the pattern at (r, a), if any: how near its middle.
fn ring_crack(s: &Shape, r: f64, a: f64, w: &FdWedge) -> Option<f64> {
    if !FD_RING_CRACKS {
        return None;
    }
    for k in 0..3 {
        let off = r - 1.0 / w.ix(k) - 1.2 * (9.0 * a + s.ph[k]).sin();
        let wd = 1.5 + 0.7 * k as f64;
        if off.abs() < wd && vnoise(a.cos() * 4.0 + 9.0, a.sin() * 4.0 + 9.0, 1.0, s.seed ^ 0xb9 ^ k as u32) > 0.36 {
            return Some(1.0 - off.abs() / wd);
        }
    }
    None
}

/// What the strike makes of a column.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
enum Zone {
    /// Not worked out yet (`cut_of`).
    #[default]
    Unset,
    /// Past the flattened land, as it stood (its grass blackened, its crowns stripped).
    Keep,
    /// Flattened: everything standing swept off.
    Flat,
    /// The rim's heap.
    Rim,
    /// The crater's floor, the pattern on it.
    Floor,
    /// A crack or fissure, or the crater's floor where no pattern is left.
    Crack,
    /// The shaft, down to bedrock.
    Shaft,
}
/// What a column is cut to: its new ground's top block's height, its top two blocks (`PAL`).
#[derive(Clone, Copy, Debug, Default)]
struct Cut {
    zone: Zone,
    top: i16,
    a: u8,
    b: u8,
}

/// A patch of burnt rock (its place in `PAL`): broad patches of one or another, flecks in them.
fn burnt(x: i32, z: i32, seed: u32) -> u8 {
    let n = vnoise(f64::from(x), f64::from(z), 9.0, seed ^ 0x51);
    let f = cell(x, z, seed, 0x54);
    if f < 0.02 {
        return MAGMA;
    }
    if f < 0.1 {
        return BURNT + (f * 700.0) as u8 % BURNT_N;
    }
    // (blacker the more of it there is: the lighter rock only the patches' tops)
    let v = (n * 1.9 - 0.45).clamp(0.0, 0.999);
    BURNT + (v * v * f64::from(BURNT_N)) as u8
}

/// The column's cut: where the whole of the look is decided. Costs about a plate's lookup and a fissure's.
fn fd_cut(s: &Shape, c: &Column, x: i32, z: i32) -> Cut {
    crate::meter::spend(900);
    let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
    let r = dx.hypot(dz);
    let a = dz.atan2(dx);
    let g = c.g;
    let w = s.wedge(a);
    let edge = s.edge(&w);
    let far = r > edge * 1.12 * FD_RIM;
    // (past any plate's reach, the land)
    let fis = fissure(s, r, a, &w);
    if far {
        return match fis {
            Some((f, len)) if !c.fluid => out_crack(s, x, z, g, r, f, len),
            _ if r < s.flat(a) => Cut { zone: Zone::Flat, top: g as i16, a: 0, b: 0 },
            _ if knocked(c, s, x, z, r, a) => Cut { zone: Zone::Flat, top: g as i16, a: 0, b: 0 },
            _ => Cut { zone: Zone::Keep, top: g as i16, a: 0, b: 0 },
        };
    }
    let p = plate(s.seed, r, a);
    let h = |k: u32| mh(p.id, s.seed, k);
    // (each plate bites its own piece out of the edge: the rim broken, not a smooth curve)
    let rc = edge * (0.965 + 0.07 * h(0xa9)) * (0.985 + 0.03 * vnoise(f64::from(x), f64::from(z), 11.0, s.seed ^ 0x31));
    let u = r / rc;
    let lv = f64::from(s.level);
    if u >= 1.0 {
        // ---- the rim: the land heaped up in hunks, a plate's worth each, broken by the fissures ----------------------------
        if let Some((f, len)) = fis
            && !c.fluid
        {
            return out_crack(s, x, z, g, r, f, len);
        }
        if u < FD_RIM && !c.fluid {
            let e = (u - 1.0) / (FD_RIM - 1.0);
            let hunk = h(0xaa);
            let n = vnoise(f64::from(x), f64::from(z), 7.0, s.seed ^ 0x35);
            let hh = FD_HEAP * (1.0 - e).powf(1.3) * (0.15 + 1.25 * hunk * hunk) * (0.55 + 0.9 * n);
            return Cut { zone: Zone::Rim, top: (g + hh.round() as i32) as i16, a: 0, b: 0 };
        }
        return Cut { zone: Zone::Flat, top: g as i16, a: 0, b: 0 };
    }
    // ---- the shaft ---------------------------------------------------------------------------------------------------
    let su = (p.sr / edge).min(1.0);
    let wound = FD_SHAFT * (1.0 + 0.22 * (3.0 * a + s.ph[1]).sin() + 0.14 * (7.0 * a + s.ph[2]).sin()) * (0.88 + 0.3 * h(0xab));
    if r < wound {
        return Cut { zone: Zone::Shaft, top: s.bot as i16, a: BURNT, b: BURNT };
    }
    // ---- the floor: a plate of the pattern, where it fell --------------------------------------------------------------
    let dest = fate(p.id, s.seed, su);
    let sl = if FD_SHATTER { 1.0 + 6.0 * su } else { 0.0 };
    let (sx, sz) = ((h(0xac) - 0.5) * 2.0 * sl, (h(0xad) - 0.5) * 2.0 * sl);
    // (the kite it lies on, and how far through the rings, 0 to 1 at the crater's edge)
    let i = (0..3).find(|i| r * w.ix(*i) < 1.0).unwrap_or(3);
    let r0 = if i == 0 { 0.0 } else { 1.0 / w.ix(i - 1) };
    let r1 = 1.0 / w.ix(i);
    let through = (i as f64 + ((r - r0) / (r1 - r0)).clamp(0.0, 1.0)) / 4.0;
    // (the pattern laid on the kites, wedge edge on big crease, band on chord, slid with the plate)
    let slid = 1.0 + (sx * a.cos() + sz * a.sin()) / r1.max(1.0);
    let pa = (w.v / (w.u + w.v).max(1e-6) + sz / r.max(20.0)) * TAU / FD_N;
    let pr = through * slid * FD_PR / FD_REACH;
    let tile = mandala(pr * pa.cos(), pr * pa.sin(), s.seed);
    let dig = tile.map_or(0, |t| t.dig);
    // (each plate one level of the bowl, so its edges stand proud; the level eased into the land's own heights by the rim)
    let bow = if FD_SHATTER { bowl(su).min(bowl(u * 0.92)) } else { bowl(u) };
    let t = sstep(0.0, 0.24, 1.0 - u);
    let base = f64::from(g) + (lv - f64::from(g)) * t;
    let tilt = shift(p.id, s.seed, dx, dz, p.sa, p.sr, su, dest == Fate::Gone) + kite_drop(s.seed, &w, i, r, r0, r1, facet(s.pattern, &w, i, r)) * t;
    let funnel = FD_FUNNEL * (1.0 - ((r - wound) / FD_FUNNEL_R).clamp(0.0, 1.0)).powi(2);
    let top = base - bow - FD_TERR * f64::from(dig) - funnel + tilt;
    // (never heaped higher than a little over the land round it; hollows filled)
    let mut top = (top.round() as i32).min(g.max(s.level) + 18).min(g + FD_FILL);
    let mut crack = None;
    if FD_CRACKS {
        let w = (0.7 + 1.5 * vnoise(f64::from(x), f64::from(z), 23.0, s.seed ^ 0x37)) * (0.7 + 0.6 * su);
        if p.gap < w {
            crack = Some(1.0 - p.gap / w);
            top -= (4.0 + 9.0 * (1.0 - p.gap / w) + 7.0 * h(0xae)) as i32;
        }
    }
    let fs = fis.map(|f| f.0).or_else(|| ring_crack(s, r, a, &w));
    if let Some(f) = fs {
        top -= (10.0 + 26.0 * f) as i32;
    }
    let top = top.max(s.bot + 1) as i16;
    if crack.is_some() || fs.is_some() {
        let v = crack.unwrap_or(0.0).max(fs.unwrap_or(0.0));
        let f = cell(x, z, s.seed, 0x55);
        let a = if v > 0.7 && f < 0.1 { MAGMA } else if v > 0.7 && f < 0.13 { CRYING } else { BURNT + (f * 3.99) as u8 };
        return Cut { zone: Zone::Crack, top, a, b: BURNT };
    }
    // ---- the pattern burnt off it ---------------------------------------------------------------------------------------
    let Some(tile) = tile else {
        return Cut { zone: Zone::Crack, top, a: burnt(x, z, s.seed), b: BURNT };
    };
    let edge_burn = 1.0 - (p.gap / 7.0).min(1.0);
    let (burn, keep) = if !FD_BURN {
        (0.0, 1.0)
    } else {
        // (burnt along its edges, and in swathes that run across the plates)
        let sw = sstep(0.64, 0.78, vnoise(dx, dz, 38.0, s.seed ^ 0x3a));
        let lean = 0.03 + 0.14 * su * su + 0.55 * sstep(0.74, 0.98, f64::max(su, u));
        match dest {
            Fate::Held => (lean + 0.26 * edge_burn * edge_burn + 0.6 * sw, 1.0),
            Fate::Burnt => (0.62 + 0.3 * edge_burn + 0.4 * sw, 1.0),
            Fate::Gone => (1.2, 0.0),
        }
    };
    let v = 0.72 * vnoise(f64::from(x), f64::from(z), 6.0, s.seed ^ 0x38) + 0.28 * cell(x, z, s.seed, 0x56);
    // (about half way through the noise's range at burn 0.5)
    if keep == 0.0 || v < 0.08 + 0.72 * burn {
        return Cut { zone: Zone::Crack, top, a: burnt(x, z, s.seed), b: BURNT };
    }
    Cut { zone: Zone::Floor, top, a: tile.top, b: tile.under }
}
/// A fissure past the crater's edge, cut down into the land: shallower and thinner as it runs out.
fn out_crack(s: &Shape, x: i32, z: i32, g: i32, r: f64, f: f64, len: f64) -> Cut {
    let d = 5.0 + 26.0 * f.sqrt() * (1.0 - r / len).max(0.0).sqrt();
    let v = cell(x, z, s.seed, 0x57);
    let a = if f > 0.7 && v < 0.1 { MAGMA } else if f > 0.7 && v < 0.13 { CRYING } else { BURNT + (v * 3.99) as u8 };
    Cut { zone: Zone::Crack, top: (g - d as i32).max(s.bot + 1) as i16, a, b: BURNT }
}

/// How hard it still hits column (x, z) in the band past the flattened land: 1 at its inner edge, to 0 at its outer.
fn band(s: &Shape, r: f64, a: f64) -> Option<f64> {
    let e = r - s.flat(a);
    (0.0..FD_BAND).contains(&e).then(|| 1.0 - e / FD_BAND)
}
/// A tree in the band knocked flat (more of them near the flattened land).
fn knocked(c: &Column, s: &Shape, x: i32, z: i32, r: f64, a: f64) -> bool {
    FD_FELLED && c.trunk >= 3 && !c.fluid && band(s, r, a).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x91) < 0.75 * p.powf(1.1))
}

/// The land past the rim blackened: all over by the rim, thinning out, in rays out to FD_CHAR and past. None where the
/// ground shows through.
fn charred(s: &Shape, x: i32, z: i32, r: f64, a: f64) -> Option<&'static str> {
    if !FD_CHARRED {
        return None;
    }
    let ray = s.ray(a);
    let n = vnoise(f64::from(x), f64::from(z), 8.0, s.seed ^ 0x71);
    let f = cell(x, z, s.seed, 0x74);
    let inner = FD_R * FD_RIM * 1.02;
    let reach = inner + 34.0 + (FD_CHAR * 1.06 - inner - 34.0) * ray;
    let k = (1.0 - ((r - inner) / (reach - inner)).clamp(0.0, 1.0)).powf(0.7);
    if 0.65 * n + 0.35 * f > 0.1 + 0.95 * k {
        return None;
    }
    Some(if f < 0.018 && r < FD_CHAR {
        "minecraft:magma_block"
    } else if k > 0.55 {
        PAL[usize::from(burnt(x, z, s.seed))]
    } else if n > 0.62 {
        "minecraft:coarse_dirt"
    } else if n > 0.4 {
        "minecraft:blackstone"
    } else if n > 0.3 {
        "minecraft:black_concrete"
    } else {
        "minecraft:podzol"
    })
}
/// The rim's heap, thrown earth turned over: dark rock on top, now and then a shard of the pattern; `k`: how far up it.
fn ejecta(x: i32, y: i32, z: i32, k: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) * 1.3 + f64::from(y) * 0.71, f64::from(z) * 1.3, 4.0, seed ^ 0x61);
    let f = mh((x.wrapping_mul(73_856_093) ^ y.wrapping_mul(19_349_663) ^ z.wrapping_mul(83_492_791)) as u32, seed, 0x62);
    if f < 0.035 {
        return PAL[12 + (f * 340.0) as usize % 12];
    }
    let k = k + 0.3 * (n - 0.5);
    if k > 0.55 {
        if n > 0.62 { "minecraft:basalt" } else if n > 0.42 { "minecraft:blackstone" } else if n > 0.3 { "minecraft:black_concrete" } else { "minecraft:cobbled_deepslate" }
    } else if n > 0.6 {
        "minecraft:blackstone"
    } else if n > 0.42 {
        "minecraft:coarse_dirt"
    } else if n > 0.28 {
        "minecraft:rooted_dirt"
    } else {
        "minecraft:podzol"
    }
}

// ---- the wave: from the middle out, under the fold ----------------------------------------------------------------------
/// The rings (FD_RING wide in the crater, twice that past it) are worked out in parts of about FD_ITEM columns.
const FD_RING: f64 = 4.0;
const FD_ITEM: f64 = 250.0;
/// What is expected to change in a column at radius r (blocks), for the wave's pace: what is dug and its lining, the
/// chunk sent again.
fn fd_cost(r: f64) -> f64 {
    let u = r / FD_R;
    FD_PER_CHUNK
        + if r < FD_SHAFT {
            120.0
        } else if u < 1.0 {
            let e = (1.0 - (r - FD_SHAFT) / FD_FUNNEL_R).max(0.0);
            bowl(u) + FD_TERR * 9.0 + FD_FUNNEL * e * e + 8.0
        } else if u < FD_RIM {
            12.0
        } else {
            6.0
        }
}
/// When the wave reaches radius r: paced to the changes, FD_LAND0 at the middle to FD_LAND1 at the end of the land read.
#[derive(Clone)]
struct Wave(Rc<Vec<f32>>);
impl Wave {
    fn new() -> Self {
        let n = FD_READ as usize + 40;
        let mut v = vec![0.0f64; n + 1];
        let mut work = 0.0;
        for (r, o) in v.iter_mut().enumerate() {
            *o = work;
            work += TAU * (r as f64 + 0.5) * fd_cost(r as f64 + 0.5);
        }
        Wave(Rc::new(v.iter().map(|w| FD_LAND0 + (FD_LAND1 - FD_LAND0) * (*w / work) as f32).collect()))
    }
    fn at(&self, r: f64) -> f32 {
        self.0[(r.max(0.0) as usize).min(self.0.len() - 1)]
    }
    /// When it has swept the whole of the chunk column holding (x, z), its furthest column's ring part included.
    fn chunk(&self, cx: f64, cz: f64, x: i32, z: i32) -> f32 {
        let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
        let d = (mx - cx).hypot(mz - cz);
        // (a chunk's neighbours at the same distance a tick or two apart: round the middle eight of them, each the whole
        // depth of the crater, would all land on one)
        self.at(d + 11.4 + 3.0 * FD_RING) + 0.2 * mh(((x >> 4) * 8191 + (z >> 4)) as u32, 7, 0xd5) as f32
    }
    /// When a part of a ring goes in.
    fn when(&self, sec: &Sector) -> f32 {
        let (t0, t1) = (self.at(sec.r0), self.at(sec.r1));
        t0 + (t1 - t0) * sec.frac as f32
    }
}
/// When everything that goes in chunk (x, z) does: the one tick, whatever it is (each chunk is sent and meshed once, and
/// the player's island goes last, with the chunks it stands on).
fn fd_tick(s: &Shape, wave: &Wave, x: i32, z: i32) -> f32 {
    let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
    if (mx - s.me[0]).hypot(mz - s.me[1]) < FD_ISLE + 11.4 {
        return FD_ISLE_AT;
    }
    wave.chunk(s.cx, s.cz, x, z).min(FD_LAND1 + 0.2)
}
/// The rings from r0 to r1, each split by angle into parts of about `item` columns and no more than `arc` blocks along
/// (their seams turned from ring to ring).
fn sectors(r0: f64, r1: f64, w: f64, item: f64, arc: f64) -> Vec<Sector> {
    let mut out = Vec::new();
    let mut r = r0;
    let mut k = 0;
    while r < r1 {
        let w = if r >= FD_R { 2.0 * w } else { w };
        let e = if r + 1.5 * w >= r1 { r1 } else { r + w };
        let n = (PI * (e * e - r * r) / item).ceil().max((TAU * e / arc).ceil()).max(1.0);
        let turn = TAU * (f64::from(k) * 0.618_034).fract();
        for j in 0..n as usize {
            out.push(Sector { r0: r, r1: e, a0: turn + TAU * j as f64 / n, da: if n <= 1.0 { TAU } else { TAU / n }, frac: j as f64 / n });
        }
        r = e;
        k += 1;
    }
    out
}

fn idx(bx: i32, bz: i32, x: i32, z: i32) -> Option<usize> {
    let (i, k) = (x - bx + FD_READ, z - bz + FD_READ);
    ((0..FD_GW).contains(&i) && (0..FD_GW).contains(&k)).then_some((k * FD_GW + i) as usize)
}
fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    crate::meter::spend(30);
    land.cols.get(idx(bx, bz, x, z)?).filter(|c| c.known)
}
const FD_CUT_COST: u64 = 13_500;
/// Column (x, z)'s cut, worked out once and kept (each column's neighbours ask for it, and the rubble and fires after).
fn cut_of(cuts: &mut [Cut], land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32) -> Option<Cut> {
    let i = idx(bx, bz, x, z)?;
    if cuts[i].zone != Zone::Unset {
        return Some(cuts[i]);
    }
    let c = land.cols.get(i).filter(|c| c.known)?;
    // (what a cut really costs: the meter's marks inside it are a part of that, and work that finds its neighbours' cuts not
    // worked out yet pays for them)
    let v = fd_cut(s, c, x, z);
    // (past the rim a cut is a fissure's question and little else)
    crate::meter::spend(if matches!(v.zone, Zone::Flat | Zone::Keep) { FD_CUT_COST / 4 } else { FD_CUT_COST });
    cuts[i] = v;
    Some(v)
}
/// The lowest of a column's four neighbours' new tops, where they are lower than `top`: how far down its wall is bared.
fn bared(cuts: &mut [Cut], land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32, top: i32) -> i32 {
    let mut lo = top;
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        if let Some(n) = cut_of(cuts, land, s, bx, bz, x + dx, z + dz) {
            lo = lo.min(i32::from(n.top));
        }
    }
    lo
}
/// A wall bared by what was cut: y0..=y1 of column (x, z) laid in dark rock, in bands (so few runs), the odd seam glowing.
/// (Solid, whatever was there: no lava or water comes through a face the crater bares.)
fn wall(b: &mut Blocks, x: i32, z: i32, y0: i32, y1: i32, seed: u32) {
    let mut y = y0;
    while y <= y1 {
        // (bands 2 to 5 high, in step along the wall, near enough)
        let band = (y + (cell(x >> 3, z >> 3, seed, 0x41) * 4.0) as i32).div_euclid(4);
        let f = mh(band as u32 ^ ((x >> 3) as u32).wrapping_mul(9_973) ^ ((z >> 3) as u32).wrapping_mul(7_919), seed, 0x42);
        let m = if f < 0.05 {
            MAGMA
        } else if f < 0.08 {
            OBSIDIAN
        } else if f < 0.1 {
            CRYING
        } else {
            BURNT + ((f - 0.1) / 0.9 * 7.0) as u8
        };
        let e = (y + 3).min(y1);
        b.run(x, z, y, e, PAL[usize::from(m)]);
        y = e + 1;
    }
}

/// One column's edits: into `air` what is cleared (no player's column is spared that), into `b` what is laid. `cleared`:
/// whether nothing is left standing on it.
fn fd_col(b: &mut Blocks, air: &mut Blocks, land: &Land, cuts: &mut [Cut], s: &Shape, bx: i32, bz: i32, x: i32, z: i32, cleared: Option<&mut bool>) {
    crate::meter::spend(600);
    let Some(c) = at(land, bx, bz, x, z).copied() else { return };
    let Some(cut) = cut_of(cuts, land, s, bx, bz, x, z) else { return };
    let top = i32::from(cut.top);
    if let Some(k) = cleared {
        *k = cut.zone != Zone::Keep && !(c.fluid && matches!(cut.zone, Zone::Flat | Zone::Rim));
    }
    match cut.zone {
        Zone::Shaft | Zone::Floor | Zone::Crack => {
            // everything over it gone (water like any other block: what is left of it flows in), its face laid, the walls
            // it bares to its neighbours lined; a hollow under it filled
            let high = c.top.max(c.g);
            if high > top {
                air.run(x, z, top + 1, high, AIR);
            }
            let lo = bared(cuts, land, s, bx, bz, x, z, top).min(c.g.min(top + 1) - 1);
            if cut.zone == Zone::Shaft {
                b.run(x, z, top, top, "minecraft:blackstone");
                return;
            }
            if lo <= top - 3 {
                wall(b, x, z, lo, top - 3, s.seed);
            }
            if lo <= top - 1 {
                b.run(x, z, (top - 2).max(lo), top - 1, PAL[usize::from(cut.b)]);
            }
            b.run(x, z, top, top, PAL[usize::from(cut.a)]);
        }
        Zone::Rim if !c.fluid => {
            // the heap, what stood there swept off, the wall of the crater under it lined
            let lo = bared(cuts, land, s, bx, bz, x, z, c.g);
            if lo < c.g {
                wall(b, x, z, lo, c.g - 1, s.seed);
            }
            let hk = f64::from((top - c.g).max(1));
            for y in c.g + i32::from(top == c.g)..=top {
                b.run(x, z, y, y, ejecta(x, y, z, f64::from(y - c.g) / hk, s.seed));
            }
            if top == c.g {
                b.run(x, z, c.g, c.g, ejecta(x, c.g, z, 0.3, s.seed));
            }
            if c.top > top {
                air.run(x, z, top + 1, c.top, AIR);
            }
        }
        Zone::Flat | Zone::Keep if !c.fluid => {
            let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            let (r, a) = (dx.hypot(dz), dz.atan2(dx));
            let lo = bared(cuts, land, s, bx, bz, x, z, c.g);
            if lo < c.g {
                wall(b, x, z, lo, c.g - 1, s.seed);
            }
            if cut.zone == Zone::Flat {
                // flattened: everything standing on the land swept off (a felled tree's stump left), the land blackened
                let stump = if FD_FELLED && c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, s.seed, 0x81) * 2.0) as i32 } else { 0 };
                if c.top > c.g + stump {
                    air.run(x, z, c.g + 1 + stump, c.top, AIR);
                }
                if let Some(m) = charred(s, x, z, r, a) {
                    b.run(x, z, c.g, c.g, m);
                }
            } else {
                if c.ground != 0
                    && let Some(m) = charred(s, x, z, r, a)
                {
                    b.run(x, z, c.g, c.g, m);
                }
                // in the band past it: the crowns stripped, in patches, wholly near it and their tops further out
                if c.leaves != 255
                    && let Some(p) = band(s, r, a)
                    && vnoise(f64::from(x), f64::from(z), 5.0, s.seed ^ 0x93) < 0.25 + 0.75 * p
                {
                    let keep = (f64::from(c.top - c.g) * (1.0 - (0.35 + 0.8 * p).min(1.0))).floor() as i32;
                    b.put(x, z, c.g + 1 + keep, c.top, AIR, Some(LEAF_NAMES[c.leaves as usize]), false);
                }
            }
        }
        _ => {}
    }
}

/// One part of a ring: its edits, what they leave hanging tidied, the trees standing in it felled. How much more than its
/// estimate it cost (1 for land of the usual height: tall forest and mountains are dearer).
fn fd_part(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, cuts: &mut [Cut], made: &mut [u8], late: &mut Due, wave: &Wave, sec: &Sector) -> (f64, usize) {
    let (bx, bz) = (q.bx, q.bz);
    let (cells, [x0, z0, x1, z1]) = sec.cells(s.cx, s.cz);
    // (what is laid keeps clear of the player; what is cleared does not, or they would be left on a pillar)
    let (mut b, mut air) = (Blocks { clear_of_player: true, ..Default::default() }, Blocks::default());
    let gw = (x1 - x0 + 1) as usize;
    let mut grid = vec![false; gw * (z1 - z0 + 1) as usize];
    for &(x, z) in &cells {
        fd_col(&mut b, &mut air, land, cuts, s, bx, bz, x, z, grid.get_mut((z - z0) as usize * gw + (x - x0) as usize));
    }
    let runs = b.runs.len() + air.runs.len();
    let when = |x: i32, z: i32| fd_tick(s, wave, x, z);
    for (tc, e) in air.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(e))));
    }
    for (tc, e) in b.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(e))));
    }
    // (what is left hanging round what changed: leaves of a tree whose trunk went, plants whose ground went; none well
    // within the flattened land, where every column is cleared through, but by water or a column not read)
    let inner = sec.r1 + f64::from(TIDY_BORDER) + 1.0 < 0.86 * FD_FLAT;
    let past = sec.r0 > FD_BLOWN + f64::from(TIDY_BORDER) + 1.0;
    let need = !past && (!inner || grid.iter().zip(0..).any(|(&k, i)| !k && sec.holds(f64::from(x0 + i % gw as i32) + 0.5 - s.cx, f64::from(z0 + i / gw as i32) + 0.5 - s.cz)) || {
        let e = TIDY_BORDER;
        (z0 - e..=z1 + e).any(|z| (x0 - e..=x1 + e).any(|x| at(land, bx, bz, x, z).is_none_or(|c| c.fluid)))
    });
    for &(x, z) in &cells {
        if let Some(i) = idx(bx, bz, x, z) {
            made[i] = if grid[(z - z0) as usize * gw + (x - x0) as usize] { 1 } else { 2 };
        }
    }
    let mut tb = if !need {
        Blocks::default()
    } else {
        tidy(x0, z0, x1, z1, 40, -1, |x, z| {
            let Some(ix) = idx(bx, bz, x, z) else { return Col::Kept };
            if made[ix] == 0 {
                let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
                let cleared = match at(land, bx, bz, x, z) {
                    Some(c) if c.fluid => false,
                    Some(_) if dx * dx + dz * dz < (0.86 * FD_FLAT).powi(2) => true,
                    Some(c) if dx * dx + dz * dz > (1.14 * FD_FLAT).powi(2) && c.trunk < 3 => false,
                    Some(c) => {
                        let (r, a) = (dx.hypot(dz), dz.atan2(dx));
                        r < s.flat(a) || knocked(c, s, x, z, r, a)
                    }
                    None => false,
                };
                // (3, 4: what the wave will make of it, not reached yet)
                made[ix] = if cleared { 3 } else { 4 };
            }
            if made[ix] == 1 || made[ix] == 3 { Col::Cleared } else { Col::Kept }
        })
    };
    tb.runs.retain_mut(|r| {
        let Some(ix) = idx(bx, bz, r.x, r.z) else { return false };
        if made[ix] > 2 {
            return false;
        }
        if r.surface.is_none() || r.y != 2 {
            return true;
        }
        match at(land, bx, bz, r.x, r.z) {
            Some(c) if c.trunk == 0 && !c.fluid => {
                let h = c.top - c.g - 2;
                r.height = r.height.min(h.max(0) as u32);
                h > 0
            }
            _ => true,
        }
    });
    for (tc, e) in tb.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(e))));
    }
    if FD_FELLED {
        fd_fell(late, land, s, used, wave, bx, bz, &cells);
    }
    let tall: i32 = cells.iter().filter_map(|&(x, z)| at(land, bx, bz, x, z)).filter(|c| !c.fluid).map(|c| (c.top - c.g).max(0)).sum();
    (1.0 + f64::from(tall) / cells.len().max(1) as f64 / 35.0, runs)
}

/// The trees standing on `cells` felled, lying on the land pointing away (crowns crushed round their ends, stripped off
/// nearer in), each log and leaf in `due` on its own chunk's tick.
fn fd_fell(due: &mut Due, land: &Land, s: &Shape, used: &mut Used, wave: &Wave, bx: i32, bz: i32, cells: &[(i32, i32)]) {
    let rim = FD_R * FD_RIM * 1.1;
    // (a column a log may lie on: past the rim's reach, dry, its ground near the last one's)
    let lie = |x: i32, z: i32, gy: i32| -> Option<i32> {
        let c = at(land, bx, bz, x, z)?;
        let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
        let (r, a) = (dx.hypot(dz), dz.atan2(dx));
        if c.fluid || r < rim || (c.g - gy).abs() > 1 || fissure(s, r, a, &s.wedge(a)).is_some() {
            return None;
        }
        // (past the flattened land: only on open ground)
        if r > s.flat(a) - 1.0 && (band(s, r, a).is_none() || c.trunk > 0 || c.top > c.g + 1) {
            return None;
        }
        Some(c.g)
    };
    for &(x, z) in cells {
        crate::meter::spend(40);
        let Some(c) = at(land, bx, bz, x, z) else { continue };
        if c.trunk < 3 || c.fluid {
            continue;
        }
        let (ox, oz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
        let (r, a) = (ox.hypot(oz), oz.atan2(ox));
        if r < rim || (r > s.flat(a) - 1.0 && !knocked(c, s, x, z, r, a)) {
            continue;
        }
        let (dx, dz) = (a.cos(), a.sin());
        let (sx, sz, log) = if dx.abs() > dz.abs() { (dx.signum() as i32, 0, LOG_X[c.wood as usize]) } else { (0, dz.signum() as i32, LOG_Z[c.wood as usize]) };
        let h = |kk: u32| cell(x, z, s.seed, kk);
        let want = (i32::from(c.trunk) - 1).clamp(2, 4 + (h(1) * 4.0) as i32);
        let mut last = None;
        let mut gy = c.g;
        let mut put: Vec<(i32, i32, i32, &'static str)> = Vec::new();
        for n in 1..=want {
            let (lx, lz) = (x + sx * n, z + sz * n);
            if used.contains(&(lx, lz)) {
                break;
            }
            let Some(g2) = lie(lx, lz, gy) else { break };
            put.push((lx, lz, g2 + 1, log));
            used.insert((lx, lz));
            gy = g2;
            last = Some((lx, lz));
        }
        // (the crown crushed round its end, out where the blast has not stripped it)
        if let (Some((lx, lz)), true) = (last, r > FD_FLAT * 0.9 && c.leaves != 255) {
            let leaves = LEAVES[c.leaves as usize];
            for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx), (sx - sz, sz - sx)] {
                let (fx, fz) = (lx + ox, lz + oz);
                if used.contains(&(fx, fz)) {
                    continue;
                }
                if let Some(g2) = lie(fx, fz, gy) {
                    put.push((fx, fz, g2 + 1, leaves));
                    used.insert((fx, fz));
                }
            }
        }
        if put.is_empty() {
            continue;
        }
        for (px, pz, y, m) in put {
            due.get(fd_tick(s, wave, px, pz)).run(px, pz, y, y, m);
        }
    }
}

/// What rubble is made of: the burnt ground, shards of the pattern, the land's soil.
fn rubble_block(rng: &mut Rng, seed: u32, r: f64) -> &'static str {
    let k = rng.next();
    if k < 0.2 {
        // (a shard of the pattern; more of them nearer in)
        return PAL[if rng.next() < 0.7 { 12 } else { 0 } + (seed as usize + (r / 30.0) as usize + rng.int(0, 5) as usize) % 12];
    }
    *rng.pick(&["minecraft:blackstone", "minecraft:basalt", "minecraft:cobbled_deepslate", "minecraft:tuff", "minecraft:coarse_dirt", "minecraft:cobblestone", "minecraft:stone", "minecraft:coal_block", "minecraft:deepslate"])
}

/// The rubble: chunks of the ground and the pattern, strewn on the crater's floor and out past the rim along the rays, on
/// their chunks' ticks.
fn fd_rubble(due: &mut Due, bx: i32, bz: i32, land: &Land, s: &Shape, wave: &Wave, cuts: &mut [Cut], used: &mut Used, part: u32) {
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7e57 ^ (u64::from(part) << 24));
    let lands = |x: i32, z: i32| fd_tick(s, wave, x, z);
    let n = FD_RUBBLE_N / FD_RUBBLE_JOBS as usize;
    crate::meter::spend(4_000 * n as u64);
    for _ in 0..n {
        let r = FD_SHAFT * 1.5 + (FD_RUBBLE - FD_SHAFT * 1.5) * rng.next().powf(1.25);
        let a = rng.uniform(0.0, TAU);
        // (past the rim only along the rays, the longest out to FD_RUBBLE)
        if r > FD_R * FD_RIM {
            let ray = s.ray(a);
            if r > FD_R * FD_RIM + 30.0 + (FD_RUBBLE - FD_R * FD_RIM - 30.0) * ray || rng.next() > 0.12 + 0.88 * ray {
                continue;
            }
        }
        let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
        let Some(c) = at(land, bx, bz, x, z).copied() else { continue };
        let Some(cut) = cut_of(cuts, land, s, bx, bz, x, z) else { continue };
        if used.contains(&(x, z)) || (c.fluid && !matches!(cut.zone, Zone::Floor | Zone::Crack)) || cut.zone == Zone::Shaft {
            continue;
        }
        if cut.zone == Zone::Keep && (c.top > c.g + 1 || c.trunk > 0) {
            continue;
        }
        let y = i32::from(cut.top) + 1;
        let m = rubble_block(&mut rng, s.seed, r);
        let t = lands(x, z);
        due.get(t).run(x, z, y, y, m);
        used.insert((x, z));
        // (now and then a bigger chunk: two or three side by side, and a second block on it)
        if rng.next() < 0.3 {
            let (x2, z2) = (x + rng.int(-1, 1), z + rng.int(-1, 1));
            if !used.contains(&(x2, z2))
                && let Some(c2) = cut_of(cuts, land, s, bx, bz, x2, z2)
                && i32::from(c2.top) + 1 == y
            {
                due.get(lands(x2, z2)).run(x2, z2, y, y, m);
                used.insert((x2, z2));
            }
            if rng.next() < 0.5 {
                due.get(t).run(x, z, y + 1, y + 1, m);
            }
        }
    }
}

/// Heaps of rubble on the crater's floor, some of them (a job `FD_HEAPS` / FD_HEAP_JOBS of them).
fn fd_heaps(due: &mut Due, bx: i32, bz: i32, land: &Land, s: &Shape, wave: &Wave, cuts: &mut [Cut], part: u32) {
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x4ea9 ^ (u64::from(part) << 24));
    for _ in 0..FD_HEAPS / FD_HEAP_JOBS as usize {
        let r = FD_SHAFT * 2.0 + (FD_R * 0.98 - FD_SHAFT * 2.0) * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
        let rad = rng.int(3, 8);
        let tall = 0.6 + 0.5 * rng.next();
        let m = rubble_block(&mut rng, s.seed, r);
        let m2 = rubble_block(&mut rng, s.seed, r);
        crate::meter::spend(400 * ((2 * rad + 1) * (2 * rad + 1)) as u64);
        for dz in -rad..=rad {
            for dx in -rad..=rad {
                let d = f64::from(dx * dx + dz * dz).sqrt() + 1.4 * vnoise(f64::from(x + dx), f64::from(z + dz), 3.0, s.seed ^ 0x65);
                if d >= f64::from(rad) {
                    continue;
                }
                let Some(c) = cut_of(cuts, land, s, bx, bz, x + dx, z + dz) else { continue };
                if !matches!(c.zone, Zone::Floor | Zone::Crack) {
                    continue;
                }
                let h = (tall * (f64::from(rad) - d)).ceil() as i32;
                let y = i32::from(c.top);
                let b = due.get(fd_tick(s, wave, x + dx, z + dz));
                b.run(x + dx, z + dz, y + 1, y + h, if (dx + 2 * dz + h).rem_euclid(3) == 0 { m2 } else { m });
            }
        }
    }
}

/// Real blocks thrown by the slam (band `k` of the four, from the middle, the shock reaching each a little after the one
/// inside it): out of its plates, outward and up, at all speeds, some landing as blocks, the rest breaking up where they
/// land (CancelDrop).
fn fd_thrown(q: &mut Plan, land: &Land, s: &Shape, cuts: &mut [Cut], k: usize) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410 ^ ((k as u64) << 20));
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let (r0, r1) = [(FD_SHAFT * 1.6, FD_RINGS[0]), (FD_RINGS[0], FD_RINGS[1]), (FD_RINGS[1], FD_R * 0.95), (FD_R * 0.95, FD_R * FD_RIM)][k];
    let t0 = FD_REVEAL + 0.08 * k as f32;
    let want = FD_THROWN[k];
    let mut n = 0;
    crate::meter::spend(want as u64 * 2 * 3_000);
    for _ in 0..want * 2 {
        if n >= want {
            break;
        }
        let r = r0 + (r1 - r0) * rng.next();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = (s.cx + a.cos() * r, s.cz + a.sin() * r);
        let (ix, iz) = (x.floor() as i32, z.floor() as i32);
        let Some(c) = at(land, bx, bz, ix, iz).copied() else { continue };
        let Some(cut) = cut_of(cuts, land, s, bx, bz, ix, iz) else { continue };
        if c.fluid || cut.zone == Zone::Shaft {
            continue;
        }
        let d = rng.next();
        let blk = if d < 0.08 && wood.is_some() {
            LOG_Y[wood.unwrap_or(0)]
        } else if cut.zone == Zone::Floor && d < 0.7 {
            PAL[usize::from(cut.a)]
        } else {
            rubble_block(&mut rng, s.seed, r)
        };
        // (a lob that lands by the rim to a hard throw that comes down a hundred blocks off; blocks a tick)
        let h = 0.35 + 1.5 * rng.next().powf(1.3);
        let vy = 1.4 + 2.3 * rng.next();
        let (vx, vz) = (a.cos() * h, a.sin() * h);
        let y = f64::from(cut.top) + 1.6 + 2.0 * rng.next();
        let t = t0 + 0.05 + 0.75 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

/// When each batch of `fd_peel` starts.
const PEEL_AT: [f32; 4] = [FD_TEAR + 0.4, FD_FOLD, FD_FOLD + 4.0, FD_FOLD + 8.0];
/// The land's own blocks peeling off along the creases and falling upward: each from a crease of the pattern, of what the
/// land is there, drifting up towards the fold.
fn fd_peel(q: &mut Plan, land: &Land, s: &Shape, k: usize) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x9ee1 ^ ((k as u64) << 20));
    let want = FD_PEEL[k];
    let reach = [FD_RINGS[1], FD_RINGS[2], FD_RINGS[3], FD_RINGS[3]][k];
    crate::meter::spend(want as u64 * 2 * 3_000);
    let mut n = 0;
    for _ in 0..want * 2 {
        if n >= want {
            break;
        }
        // (on a radial crease, or a ring's edge)
        let on_ring = rng.next() < 0.4;
        let (r, a) = if on_ring {
            let (i, a) = ((rng.next() * (k + 2).min(4) as f64) as usize, rng.uniform(0.0, TAU));
            (1.0 / s.wedge(a).ix(i), a)
        } else {
            ((0.15 + 0.85 * rng.next()) * reach, FdWedge::bearing((rng.next() * FD_CREASES as f64) as usize % FD_CREASES, s.turn) + rng.uniform(-0.006, 0.006))
        };
        let (x, z) = (s.cx + a.cos() * r, s.cz + a.sin() * r);
        let Some(c) = at(land, bx, bz, x.floor() as i32, z.floor() as i32).copied() else { continue };
        if c.fluid {
            continue;
        }
        let d = rng.next();
        let blk = if c.trunk > 0 && d < 0.5 {
            LOG_Y[usize::from(c.wood)]
        } else if c.leaves != 255 && d < 0.8 {
            LEAVES[usize::from(c.leaves)]
        } else {
            match c.ground {
                1 if d < 0.92 => "minecraft:grass_block",
                1 | 2 => "minecraft:dirt",
                _ => "minecraft:stone",
            }
        };
        let (vy, h) = (0.12 + 0.3 * rng.next(), 0.04 + 0.1 * rng.next());
        let (vx, vz) = (-a.cos() * h, -a.sin() * h);
        let y = f64::from(c.top) + 1.2;
        let t = PEEL_AT[k] + 3.5 * rng.next() as f32;
        // (a falling block gives up at 600 ticks, and `kill` doesn't reach them: each is old enough to go at the crush's end)
        let age = 600 - ((FD_BEAT - t) * 20.0) as i32;
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:{age},DropItem:0b,CancelDrop:1b,NoGravity:1b,Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

/// Fires left burning in clumps over the wound: on the burnt plates and the blackened land round it, a block of netherrack
/// under each so it keeps burning, on their chunks' ticks.
fn fd_embers(due: &mut Due, bx: i32, bz: i32, land: &Land, s: &Shape, wave: &Wave, cuts: &mut [Cut], used: &mut Used, part: u32) {
    let mut rng = Rng::new(u64::from(s.seed) ^ 0xe3b3 ^ (u64::from(part) << 24));
    let n = FD_EMBERS / FD_EMBER_JOBS as usize;
    crate::meter::spend(n as u64 * 3_000);
    for _ in 0..n {
        let r = FD_SHAFT * 2.0 + (FD_FLAT * 0.98 - FD_SHAFT * 2.0) * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
        // (in clumps)
        if vnoise(f64::from(x), f64::from(z), 22.0, s.seed ^ 0xe1) < 0.56 || used.contains(&(x, z)) {
            continue;
        }
        let Some(c) = at(land, bx, bz, x, z).copied() else { continue };
        let Some(cut) = cut_of(cuts, land, s, bx, bz, x, z) else { continue };
        if c.fluid || !matches!(cut.zone, Zone::Crack | Zone::Flat | Zone::Rim) || cut.a == MAGMA {
            continue;
        }
        let y = i32::from(cut.top);
        let b = due.get(fd_tick(s, wave, x, z));
        b.run(x, z, y, y, PAL[usize::from(NETHERRACK)]);
        b.put(x, z, y + 1, y + 1, "minecraft:fire", Some(AIR), false);
        used.insert((x, z));
    }
}

// ---- the land's work: one stage a tick, in order --------------------------------------------------------------------
/// All the land's work is one chain of stages, a tick each: the land read (its rings asked from the middle out and taken in
/// as they are answered), the crater's level from it, then the parts of the wave ring by ring, each worked out FD_AHEAD
/// before it is due. Each stage does about FD_BUDGET columns' worth (well under a tick's fuel).
const FD_BUDGET: f64 = 870.0;
/// What an answer of the land's read is reckoned to cost past what `take_in_grid` counts.
const FD_ANSWER: u64 = 7_000_000;
/// About what a unit of that work costs in instructions.
const FD_UNIT: f64 = 8_000.0;
/// Columns of the land's square made ready a stage.
const FD_GROW: usize = 100_000;
/// While the wave's edits are going in a stage starts no job past this.
const FD_WAVE_SOFT: u64 = 12_500_000;
/// Reads of the land asked and not taken in yet, at most.
const FD_IN_FLIGHT: usize = 8;
enum Job {
    /// The level the crater is cut down from.
    Level,
    Thrown(usize),
    Peel(usize),
    Rubble(u32),
    Heaps(u32),
    Embers(u32),
    Part(Sector),
    /// What was gathered for the chunks' ticks past their cuts, handed to the plan after all of them.
    Late,
}
struct Work {
    land: Land,
    s: Shape,
    wave: Wave,
    used: Used,
    /// The felled trees, the rubble, the heaps and the fires, by tick: on a chunk's tick they must follow its cut (a column's
    /// clearing would take what lay on it), so they wait here for the last of its parts.
    late: Due,
    cuts: Vec<Cut>,
    /// What was made of each column, for the tidying (0 not yet known, 1 cleared through, 2 left).
    made: Vec<u8>,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    /// The ring of unloaded columns asked again (one at a time, the rings in turn): its tag, ring, columns and when.
    retry: Option<(u32, usize, Vec<(i32, i32)>, f32)>,
    rnext: usize,
    rat: f32,
    /// Columns not loaded at the last stage, and when last some came.
    left: usize,
    came: f32,
    level: bool,
    /// The parts worked out and not due yet: when, how many runs; and all their runs.
    held: std::collections::VecDeque<(f32, usize)>,
    held_runs: usize,
    jobs: std::collections::VecDeque<Job>,
}
fn read_reach(part: i32) -> f64 {
    f64::from(FD_READ) * (f64::from(part + 1) / f64::from(FD_PARTS)).sqrt()
}
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let q0 = if part == 0 { -1.0 } else { read_reach(part - 1).powi(2) };
    ring_columns(bx, bz, q0, read_reach(part).min(f64::from(FD_READ)))
}
impl Work {
    fn new(s: Shape) -> Self {
        let mut jobs = std::collections::VecDeque::new();
        jobs.push_back(Job::Level);
        // (these wait for their time beside the wave, not behind it)
        for k in 0..4 {
            if FD_THROWN[k] > 0 {
                jobs.push_back(Job::Thrown(k));
            }
        }
        for k in 0..4 {
            if FD_PEEL[k] > 0 {
                jobs.push_back(Job::Peel(k));
            }
        }
        // (the rubble, the heaps and the fires once the crater's cuts are worked out, so they cost only their own work; all
        // gathered in `late`, and handed over behind the wave's parts: `flush`)
        let mut gathered = false;
        for sec in sectors(0.0, f64::from(FD_READ) + 1.0, FD_RING, FD_ITEM, 150.0) {
            if !gathered && sec.r0 >= FD_R * 0.86 {
                if FD_RUBBLE_N > 0 {
                    jobs.extend((0..FD_RUBBLE_JOBS).map(Job::Rubble));
                }
                if FD_HEAPS > 0 {
                    jobs.extend((0..FD_HEAP_JOBS).map(Job::Heaps));
                }
                if FD_EMBERS > 0 {
                    jobs.extend((0..FD_EMBER_JOBS).map(Job::Embers));
                }
                gathered = true;
            }
            jobs.push_back(Job::Part(sec));
        }
        jobs.push_back(Job::Late);
        let n = (FD_GW * FD_GW) as usize;
        Work {
            land: Land { cols: Vec::with_capacity(n), missing: vec![Vec::new(); FD_PARTS as usize], woods: [0; 9], done: false },
            s,
            wave: Wave::new(),
            used: Default::default(),
            late: Due(Default::default()),
            cuts: Vec::with_capacity(n),
            made: Vec::with_capacity(n),
            tags: (0..FD_PARTS).map(|_| crate::columns::new_tag()).collect(),
            asked: 0,
            taken: 0,
            retry: None,
            rnext: 0,
            rat: 0.0,
            left: usize::MAX,
            came: 0.0,
            level: false,
            held: Default::default(),
            held_runs: 0,
            jobs,
        }
    }
    /// The land's square filled in, a piece a stage: all at once, it is some milliseconds. Whether it is done.
    fn grown(&mut self) -> bool {
        let n = (FD_GW * FD_GW) as usize;
        if self.made.len() == n {
            return true;
        }
        crate::meter::spend(4_000_000);
        let step = |len: usize| (len + FD_GROW).min(n);
        if self.land.cols.len() < n {
            self.land.cols.resize(step(self.land.cols.len()), Column::default());
        } else if self.cuts.len() < n {
            self.cuts.resize(step(self.cuts.len()), Cut::default());
        } else {
            self.made.resize(n, 0);
        }
        false
    }
    /// How far out the land is in (every column within it read): out to the rings taken in, short of the first ring
    /// with columns the world had not loaded. A few dozen steps however much is missing.
    fn ready(&self) -> f64 {
        if self.land.done {
            return f64::INFINITY;
        }
        crate::meter::spend(400);
        let r = if self.taken == 0 { 0.0 } else { read_reach(self.taken as i32 - 1) };
        let mut first = self.land.missing.iter().position(|m| !m.is_empty()).unwrap_or(usize::MAX);
        if let Some((_, part, _, _)) = &self.retry {
            first = first.min(*part);
        }
        if first == usize::MAX {
            return r;
        }
        let inner = if first == 0 { 0.0 } else { read_reach(first as i32 - 1) };
        r.min(inner - 1.0)
    }
    fn unloaded(&self) -> usize {
        self.land.missing.iter().map(Vec::len).sum::<usize>() + self.retry.as_ref().map_or(0, |r| r.2.len())
    }
    /// Whether job `j` can be done now; and whether the jobs after it must wait for it (the wave's parts go in order).
    fn can(&self, j: &Job, now: f32) -> (bool, bool) {
        match j {
            // (from what has loaded by then if the crater's land still has not all)
            Job::Level => (self.ready() >= FD_R * 1.2 || now >= FD_LAND0 - 1.0, true),
            Job::Thrown(_) => (self.level && self.land.done && now + FD_AHEAD >= FD_REVEAL, false),
            Job::Peel(k) => (self.land.done && now + 2.0 >= PEEL_AT[*k], false),
            Job::Rubble(_) | Job::Heaps(_) | Job::Embers(_) => (self.level && self.land.done, false),
            Job::Late => (self.level && self.land.done, true),
            Job::Part(sec) => (self.level && now + FD_AHEAD >= self.wave.when(sec) && self.ready() >= sec.r1 + 12.0 && self.held_runs < FD_HELD, true),
        }
    }
    fn cost(j: &Job) -> f64 {
        match j {
            Job::Level => 150.0,
            Job::Thrown(_) | Job::Peel(_) => 500.0,
            Job::Rubble(_) | Job::Heaps(_) => FD_BUDGET * 0.5,
            Job::Embers(_) => FD_BUDGET * 0.5,
            Job::Late => 100.0,
            Job::Part(s) => {
                let a = s.da.min(TAU) / 2.0 * (s.r1 * s.r1 - s.r0 * s.r0);
                let k = if s.r0 < FD_R * FD_RIM {
                    0.75
                } else if s.r1 + 4.0 < 0.86 * FD_FLAT {
                    0.45
                } else if s.r0 > FD_BLOWN {
                    0.3
                } else {
                    0.55
                };
                a * k
            }
        }
    }
    /// What is gathered for the ticks before `tick` handed to the plan (they come after what the stages before gave).
    fn flush(&mut self, q: &mut Plan, tick: i32) {
        let rest = self.late.0.split_off(&tick);
        let mut ready = Due(std::mem::replace(&mut self.late.0, rest));
        for e in ready.0.values_mut() {
            e.clear_of_player = true;
        }
        ready.push(q);
    }
    /// The crater's level: the median ground under it, so a hill at the target does not leave it perched, nor a dell
    /// sink it.
    fn find_level(&mut self, bx: i32, bz: i32) {
        let mut hs = Vec::with_capacity(400);
        for i in 0..400u32 {
            let (a, r) = (mh(i, self.s.seed, 0xd1) * TAU, FD_R * mh(i, self.s.seed, 0xd2).sqrt());
            let (x, z) = ((self.s.cx + a.cos() * r).floor() as i32, (self.s.cz + a.sin() * r).floor() as i32);
            if let Some(c) = at(&self.land, bx, bz, x, z) {
                hs.push(if c.fluid { c.wtop } else { c.g });
            }
        }
        hs.sort_unstable();
        if let Some(m) = hs.get(hs.len() / 2) {
            self.s.level = *m;
        }
        self.level = true;
    }
}

/// One stage of the land's work.
fn fd_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = 'stage: {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        if !wk.grown() {
            break 'stage true;
        }
        let (bx, bz) = (q.bx, q.bz);
        let mut spent = 0.0;
        // the reads: the land's rings two a stage from the middle out, no more than FD_IN_FLIGHT not taken in yet: an answer
        // waits in the mod's own memory, and it has 64 MiB
        if wk.asked < wk.tags.len() && wk.asked < wk.taken + FD_IN_FLIGHT {
            for _ in 0..2.min(wk.tags.len() - wk.asked) {
                let part = wk.asked;
                q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: FD_BELOW, above: FD_ABOVE }));
                wk.asked += 1;
                spent += 75.0;
            }
        }
        // their answers taken in as they come (up to four a stage)
        for _ in 0..4 {
            // (real land's answers cost a good deal more than the meter's two million: as many a stage as fit)
            if wk.taken < wk.asked
                && crate::meter::room(FD_ANSWER)
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                take_in_grid(&mut wk.land, &a, bx, bz, wk.taken, FD_READ, true);
                crate::meter::spend(FD_ANSWER);
                wk.taken += 1;
                spent += 300.0;
            }
        }
        if wk.taken == wk.tags.len() && !wk.land.done {
            // (the columns the world had not loaded yet, as at a target far off, its chunks only forceloaded as the strike
            // began: asked again a ring at a time, and the land's work waits for them, given up on late)
            if let Some((tag, part, _, since)) = &wk.retry {
                let (tag, part, since) = (*tag, *part, *since);
                if let Some(a) = crate::columns::take(tag) {
                    take_in_grid(&mut wk.land, &a, bx, bz, part, FD_READ, true);
                    wk.retry = None;
                    spent += 300.0;
                } else if now > since + 3.0
                    && let Some((_, part, cols, _)) = wk.retry.take()
                {
                    wk.land.missing[part] = cols;
                }
            }
            let left = wk.unloaded();
            if left < wk.left && wk.left != usize::MAX {
                wk.came = now;
            }
            wk.left = left;
            // (the crater's land in and nothing more coming for a while, as land that will not load past the edge of
            // what the world has: the rest left out, not the whole of the land held back for it)
            let stalled = now - wk.came > FD_PATIENCE && now > FD_SEAL;
            if left == 0 {
                wk.land.done = true;
            } else if now > FD_LAND_BY || stalled {
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("fold: {left} columns of the land never loaded; the terrain left out there"));
                wk.land.done = true;
            } else if wk.retry.is_none() && now >= wk.rat {
                let n = wk.land.missing.len();
                if let Some(part) = (0..n).map(|j| (wk.rnext + j) % n).find(|&j| !wk.land.missing[j].is_empty()) {
                    let cols = std::mem::take(&mut wk.land.missing[part]);
                    crate::meter::spend(40 * cols.len() as u64);
                    let tag = crate::columns::new_tag();
                    q.ev.push((now, Act::Read { tag, columns: cols.clone(), below: FD_BELOW, above: FD_ABOVE }));
                    wk.retry = Some((tag, part, cols, now));
                    wk.rnext = part + 1;
                    wk.rat = now + 0.1;
                    spent += 150.0;
                }
            }
        }
        crate::trace("fd land taken");
        // (no job on a stage that took answers in: the two together went over half a tick's fuel)
        if wk.taken < wk.tags.len() && spent >= 300.0 {
            break 'stage true;
        }
        while wk.held.front().is_some_and(|h| h.0 <= now) {
            wk.held_runs -= wk.held.pop_front().map_or(0, |h| h.1);
        }
        // the jobs: the first that can be done (never past one of the wave's parts that cannot yet: they go in order)
        loop {
            // (the wave's edits come after the stage in the same tick, up to meter::EDITS, and the meter reads a little under the real thing)
            if now >= FD_HIDDEN.start && crate::meter::spent() >= FD_WAVE_SOFT {
                break;
            }
            let mut pick = None;
            for (i, j) in wk.jobs.iter().enumerate() {
                crate::meter::spend(300);
                let (can, blocks) = wk.can(j, now);
                if can {
                    pick = Some(i);
                    break;
                }
                if blocks {
                    break;
                }
            }
            let Some(i) = pick else { break };
            let c = Work::cost(&wk.jobs[i]);
            // (a job waits for the next tick unless it fits in this one: what else the tick did and a whole job on top of
            // it went over half a tick's fuel, now and then, on real land)
            if (spent > 0.0 && spent + c > FD_BUDGET) || !crate::meter::room(((c * FD_UNIT) as u64).min(10_000_000)) {
                break;
            }
            spent += c;
            crate::meter::spend((c * FD_UNIT) as u64);
            let job = wk.jobs.remove(i).unwrap_or(Job::Level);
            let wave = wk.wave.clone();
            let s = wk.s;
            match job {
                Job::Level => {
                    wk.find_level(bx, bz);
                }
                Job::Thrown(k) => fd_thrown(q, &wk.land, &s, &mut wk.cuts, k),
                Job::Peel(k) => fd_peel(q, &wk.land, &s, k),
                Job::Rubble(k) => fd_rubble(&mut wk.late, bx, bz, &wk.land, &s, &wave, &mut wk.cuts, &mut wk.used, k),
                Job::Heaps(k) => fd_heaps(&mut wk.late, bx, bz, &wk.land, &s, &wave, &mut wk.cuts, k),
                Job::Embers(k) => fd_embers(&mut wk.late, bx, bz, &wk.land, &s, &wave, &mut wk.cuts, &mut wk.used, k),
                Job::Late => {
                    wk.flush(q, i32::MAX);
                    #[cfg(target_arch = "wasm32")]
                    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("fold: the land worked out at {now:.1} s, the mod's memory {} MiB of 64", core::arch::wasm32::memory_size(0) / 16));
                }
                Job::Part(sec) => {
                    let (k, runs) = fd_part(q, &wk.land, &s, &mut wk.used, &mut wk.cuts, &mut wk.made, &mut wk.late, &wave, &sec);
                    spent += c * (k - 1.0);
                    wk.held.push_back((wave.at(sec.r1), runs));
                    wk.held_runs += runs;
                    // (a chunk's tick is when the wave has passed all of it: every part of those due by here is done)
                    wk.flush(q, (wave.at(sec.r0) / 0.05).floor() as i32);
                }
            }
            crate::trace("fd job");
        }
        !wk.jobs.is_empty()
    };
    if more && now < FD_LEN - 1.0 {
        q.later(now + 0.05, move |q| fd_work(q, w, now + 0.05));
    }
}

/// The chunks of the land read, a row of chunks a rectangle: worked out by the row, on the fire tick (some forty rows;
/// `pk_load_rows` goes through every column, hundreds of thousands, too much for the fire).
fn load_rows(cx: f64, cz: f64) -> Vec<[i32; 4]> {
    let rr = f64::from(FD_READ) + 4.0;
    let (z0, z1) = (((cz - rr).floor() as i32) >> 4, ((cz + rr).floor() as i32) >> 4);
    (z0..=z1)
        .filter_map(|c| {
            // (the row's edge nearest the middle: as wide as any of it gets)
            let (zl, zh) = (f64::from(c * 16), f64::from(c * 16 + 16));
            let d = if cz < zl { zl - cz } else if cz > zh { cz - zh } else { 0.0 };
            (d <= rr).then(|| {
                let w = (rr * rr - d * d).sqrt();
                [((cx - w).floor() as i32 >> 4) * 16, c * 16, ((cx + w).floor() as i32 >> 4) * 16 + 15, c * 16 + 15]
            })
        })
        .collect()
}

/// The land's plan, from fold_plan when the terrain is on: kept loaded from the fire, read, and the chain of stages that
/// does the rest; mobs and items killed as the bloom goes; smoke after it.
pub(super) fn land_plan(p: &mut Plan, seed: u32, turn: f64, dimension: &str, me: [f64; 3], pattern: usize) {
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let load = load_rows(cx, cz);
    for [x0, z0, x1, z1] in &load {
        p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
    }
    for [x0, z0, x1, z1] in &load {
        p.ev.push((FD_LEN - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    }
    // (the ground goes from under them with the slam, up to a crater's depth: the fall takes nothing from them)
    p.at(FD_ISLE_AT - 0.1, format!("execute positioned {cx:.1} {} {cz:.1} run effect give @a[distance=..{FD_KILL}] minecraft:resistance 8 4 true", by + 1));
    // (as the hold starts too: what stands on the land would fall into a crater that can't be seen yet)
    for t in [FD_HIDDEN.start, FD_RELEASE, FD_REVEAL, FD_REVEAL + 2.0] {
        p.at(t, format!("execute positioned {cx:.1} {} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{FD_KILL}]", by + 1));
    }
    for i in 0..FD_SMOKE as u32 {
        let (a, r) = (mh(i, seed, 0xe5) * TAU, FD_R * 1.15 * mh(i, seed, 0xe6).sqrt());
        let (x, z) = (cx + a.cos() * r, cz + a.sin() * r);
        let t = FD_REVEAL + 0.5 + (FD_LEN - FD_REVEAL - 2.0) * i as f32 / FD_SMOKE as f32;
        p.at(t, format!("particle minecraft:campfire_signal_smoke {x:.1} {:.1} {z:.1} 18 2 18 0.03 80 force", by - 12));
    }
    let shape = Shape { cx, cz, ph: [TAU * mh(1, seed, 0xc0), TAU * mh(2, seed, 0xc0), TAU * mh(3, seed, 0xc0), TAU * mh(4, seed, 0xc0)], seed, turn, level: by + 1, me: [me[0], me[2]], pattern, bot: bedrock_top(dimension) };
    // (its state made on a stage of its own, not as it fires: the land's square of columns is some megabytes)
    p.later(0.15, move |q| {
        crate::meter::spend(9_000_000);
        let work = Rc::new(RefCell::new(Work::new(shape)));
        q.later(0.2, move |q| fd_work(q, work, 0.2));
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::sim::{self, Played};
    use crate::strike::{Target, plan};
    use std::collections::{BTreeMap, HashMap, HashSet};

    /// Blocks peel off along the creases and fall upward as the land opens: no gravity, all before the crush, and they are
    /// old enough to be gone as it is crushed.
    #[test]
    fn blocks_peel_off_along_the_creases() {
        let p = played(1);
        let peel: Vec<&(f32, String)> = p.cmds.iter().filter(|(_, c)| c.contains("NoGravity:1b")).collect();
        assert!(peel.len() > 150, "{} blocks peeled", peel.len());
        assert!(peel.iter().all(|(t, _)| *t >= FD_TEAR && *t < FD_SEAL), "peeled out of its time");
    }

    fn the_laser() -> &'static crate::lasers::Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "fold").expect("the fold")
    }
    fn target() -> Target {
        Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] }
    }
    const ME: [f64; 3] = [0.5, 66.0, 400.5];

    // ---- the test's worlds --------------------------------------------------------------------------------------------
    thread_local! {
        /// 0 flat open land with a few trees; 1 hills with a village and woods (VillageNuke's kind of land); 2 mountains (60
        /// high, steep); 3 a jungle (every column a tall tree); 4 deep ocean; 5 lakes and land; 6 the hills only half
        /// loaded (nothing east of x 150); 7 the hills, the strip x >= 70 loaded only 8 s in (`LOADED`).
        static LAND: std::cell::Cell<u8> = const { std::cell::Cell::new(0) };
        static ASKED: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
    }
    fn tree(x: i32, z: i32, p: f64) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 1.0 - p
    }
    fn hills(x: i32, z: i32) -> i32 {
        let (x, z) = (f64::from(x), f64::from(z));
        (70.0 + 12.0 * (x * 0.021).sin() + 9.0 * (z * 0.033 + 1.0).cos() + 4.0 * ((x + z) * 0.07).sin()) as i32
    }
    fn house(x: i32, z: i32) -> bool {
        // (a house every 40 blocks: 7 by 7, on the land)
        let (i, k) = (x.div_euclid(40), z.div_euclid(40));
        (x - i * 40) < 7 && (z - k * 40) < 7 && mh((i * 31 + k * 17) as u32, 3, 1) < 0.4
    }
    fn world(land: u8, x: i32, z: i32) -> (i32, Box<dyn Fn(i32) -> &'static str>) {
        match land {
            0 => {
                let t = tree(x, z, 0.004);
                (if t { 73 } else { 64 }, Box::new(move |y| if y < 60 { "minecraft:stone" } else if y < 64 { "minecraft:dirt" } else if y == 64 { "minecraft:grass_block" } else if t && y <= 70 { "minecraft:oak_log" } else if t && y <= 73 { "minecraft:oak_leaves" } else { "minecraft:air" }))
            }
            1 | 6 | 7 => {
                let g = hills(x, z);
                let (h, t) = (house(x, z), tree(x, z, 0.02));
                let top = if h { g + 6 } else if t { g + 9 } else { g };
                (top, Box::new(move |y| {
                    if y < g - 3 {
                        "minecraft:stone"
                    } else if y < g {
                        "minecraft:dirt"
                    } else if y == g {
                        "minecraft:grass_block"
                    } else if h && y <= g + 6 {
                        "minecraft:oak_planks"
                    } else if t && y <= g + 6 {
                        "minecraft:oak_log"
                    } else if t && y <= g + 9 {
                        "minecraft:oak_leaves"
                    } else {
                        "minecraft:air"
                    }
                }))
            }
            2 => {
                let g = (100.0 + 60.0 * (f64::from(x) * 0.02).sin() * (f64::from(z) * 0.025).cos()).round() as i32;
                (g, Box::new(move |y| if y < g { "minecraft:stone" } else if y == g { "minecraft:snow_block" } else { "minecraft:air" }))
            }
            3 => {
                let g = 70;
                let h = 20 + ((x * 7 + z * 13).rem_euclid(14));
                (g + h + 3, Box::new(move |y| if y < g { "minecraft:dirt" } else if y == g { "minecraft:grass_block" } else if y <= g + h && (x + z) % 2 == 0 { "minecraft:jungle_log" } else { "minecraft:jungle_leaves" }))
            }
            4 => (62, Box::new(|y| if y < 20 { "minecraft:stone" } else if y <= 62 { "minecraft:water" } else { "minecraft:air" })),
            _ => {
                let wet = (f64::from(x) * 0.031).sin() * (f64::from(z) * 0.027).cos() > 0.3;
                if wet {
                    (62, Box::new(|y| if y < 52 { "minecraft:sand" } else if y <= 62 { "minecraft:water" } else { "minecraft:air" }))
                } else {
                    (66, Box::new(|y| if y < 66 { "minecraft:dirt" } else if y == 66 { "minecraft:grass_block" } else { "minecraft:air" }))
                }
            }
        }
    }
    fn column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let land = LAND.with(|l| l.get());
        if land == 6 && x > 150 {
            return None;
        }
        if land == 7 {
            // (each ask a tick or so; the strip comes after 200 asks)
            ASKED.with(|a| a.set(a.get() + 1));
            if x >= 70 && ASKED.with(|a| a.get()) < 300_000 {
                return None;
            }
        }
        let (top, f) = world(land, x, z);
        let (below, above) = (below as i32, above as i32);
        Some((top, (top - below..top + above).map(|y| f(y)).collect()))
    }
    thread_local! {
        /// The crease pattern the tests play on.
        static PATTERN: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    }
    fn played_at(land: u8, len: f32) -> Played {
        LAND.with(|l| l.set(land));
        ASKED.with(|a| a.set(0));
        let ev = plan(the_laser(), &target(), true, "minecraft:overworld", 37.0, ME, PATTERN.with(std::cell::Cell::get));
        sim::play(ev, len, &column)
    }
    fn played(land: u8) -> Played {
        played_at(land, FD_LEN)
    }

    // ---- the world after it --------------------------------------------------------------------------------------------
    /// The runs that went into each column, in order: y0, y1, block, what it was limited to; so what a column ended up as
    /// can be asked block by block.
    #[derive(Default)]
    struct After {
        cols: HashMap<(i32, i32), Vec<(i32, i32, &'static str, Option<&'static str>)>>,
    }
    impl After {
        fn new(p: &Played) -> Self {
            let mut cols: HashMap<(i32, i32), Vec<_>> = Default::default();
            for (_, _, b) in &p.edits {
                for r in &b.runs {
                    // (the tidying's, counted from the ground as it stands: only what hung there)
                    if r.surface.is_some() {
                        continue;
                    }
                    let only = r.only.map(|f| b.filters[f as usize]);
                    cols.entry((r.x, r.z)).or_default().push((r.y, r.y + r.height as i32 - 1, b.palette[r.block as usize], only));
                }
            }
            After { cols }
        }
        fn block(&self, land: u8, x: i32, y: i32, z: i32) -> &'static str {
            let (top, f) = world(land, x, z);
            let mut b = if y > top { "minecraft:air" } else if y < top - 80 { "minecraft:stone" } else { f(y) };
            for &(y0, y1, m, only) in self.cols.get(&(x, z)).map_or(&[][..], |v| v) {
                if y >= y0 && y <= y1 && only.is_none_or(|o| o == b || (o.ends_with("_leaves") && b.ends_with("_leaves"))) {
                    b = m;
                }
            }
            b
        }
        /// The column's highest block.
        fn top(&self, land: u8, x: i32, z: i32) -> i32 {
            let (t0, _) = world(land, x, z);
            let hi = self.cols.get(&(x, z)).map_or(t0, |v| v.iter().map(|r| r.1).max().unwrap_or(t0)).max(t0);
            let mut y = hi;
            while y > -64 {
                let b = self.block(land, x, y, z);
                if b != "minecraft:air" && b != "minecraft:fire" {
                    return y;
                }
                y -= 1;
            }
            y
        }
    }

    // ---- the pattern --------------------------------------------------------------------------------------------------
    /// The mandala under the damage is a kaleidoscope: turning it a twelfth of a turn, or mirroring it across a wedge's
    /// edge, gives the same column (every dig, every block), wherever it is asked.
    #[test]
    fn the_mandala_is_twelvefold_and_mirrored() {
        for i in 0..4000u32 {
            let r = 1.0 + 62.0 * mh(i, 5, 1);
            let a = mh(i, 5, 2) * TAU;
            let k = mandala(r * a.cos(), r * a.sin(), 3);
            for turn in [1.0, 5.0, 11.0] {
                let b = a + turn * TAU / FD_N;
                assert_eq!(k, mandala(r * b.cos(), r * b.sin(), 3), "turned {turn} at r {r:.2}, angle {a:.3}");
            }
            let m = -a; // (the mirror across the x axis, an edge)
            assert_eq!(k, mandala(r * m.cos(), r * m.sin(), 3), "mirrored at r {r:.2}, angle {a:.3}");
        }
    }
    /// The rings are terraced and colourful.
    #[test]
    fn the_mandala_is_terraced_and_colourful() {
        let mut hues = HashSet::new();
        let mut depths = HashSet::new();
        for i in -64..64 {
            for j in -64..64 {
                if let Some(t) = mandala(f64::from(i) + 0.5, f64::from(j) + 0.5, 3) {
                    assert!((-3..=22).contains(&t.dig), "{}", t.dig);
                    depths.insert(t.dig);
                    hues.insert(t.top);
                }
            }
        }
        assert!(hues.len() >= 16, "{} blocks on top", hues.len());
        assert!(depths.len() >= 10, "{depths:?}");
    }

    // ---- the crater ---------------------------------------------------------------------------------------------------
    /// How far a column's top lies under the land's level at each ring, and where the crater's edge is along each bearing.
    fn sizes(a: &After, land: u8, gy: i32) -> (BTreeMap<i32, (f64, i32)>, Vec<f64>) {
        let mut rings: BTreeMap<i32, (i64, i64, i32)> = Default::default();
        for x in (-400..400).step_by(3) {
            for z in (-400..400).step_by(3) {
                let r = f64::from(x).hypot(f64::from(z));
                if r < 400.0 {
                    let d = gy - a.top(land, x, z);
                    let e = rings.entry((r / 20.0) as i32).or_default();
                    e.0 += i64::from(d);
                    e.1 += 1;
                    e.2 = e.2.max(d);
                }
            }
        }
        let mut edges = Vec::new();
        for k in 0..72 {
            let t = f64::from(k) * TAU / 72.0;
            // (from outside in, the first column cut well under the land)
            let mut r = 400.0;
            while r > 0.0 {
                let (x, z) = ((r * t.cos()).floor() as i32, (r * t.sin()).floor() as i32);
                if gy - a.top(land, x, z) > 6 && a.cols.get(&(x, z)).is_some() {
                    break;
                }
                r -= 1.0;
            }
            edges.push(r);
        }
        (rings.into_iter().map(|(k, v)| (k * 20, (v.0 as f64 / v.1 as f64, v.2))).collect(), edges)
    }
    /// It is big and deep: about 600 across, deeper than the Nuke's, its outline the pattern's fourth ring, the shaft to bedrock, the
    /// pattern still there on the floor.
    #[test]
    fn the_crater_is_big_deep_and_ragged() {
        let p = played(0);
        let a = After::new(&p);
        let (rings, edges) = sizes(&a, 0, 64);
        for (r, v) in &rings {
            eprintln!("r {r:4}: mean depth {:6.1} deepest {}", v.0, v.1);
        }
        let mean = edges.iter().sum::<f64>() / edges.len() as f64;
        let (lo, hi) = (edges.iter().copied().fold(f64::MAX, f64::min), edges.iter().copied().fold(0.0, f64::max));
        eprintln!("edge {lo:.0} .. {hi:.0}, mean {mean:.0}");
        // (the most: a fissure running out)
        assert!(mean > 260.0 && mean < 330.0 && lo > 200.0 && hi < 400.0, "{mean} {lo} {hi}");
        let sd = (edges.iter().map(|e| (e - mean).powi(2)).sum::<f64>() / edges.len() as f64).sqrt();
        assert!(sd > 20.0, "its edge is too smooth: {sd:.1}");
        assert!(rings[&100].0 > 50.0, "{:?}", rings[&100]);
        assert!(rings[&200].0 > 35.0, "{:?}", rings[&200]);
        // the shaft: down to bedrock, open
        for y in [-50, -20, 20, 40] {
            assert_eq!(a.block(0, 3, y, 3), "minecraft:air", "y {y}");
        }
        // the pattern left on the floor: all round it, a good part of each wedge
        let mut wedges = [(0u32, 0u32); 12];
        let mut tops: HashSet<&str> = HashSet::new();
        for x in (-260..260).step_by(2) {
            for z in (-260..260).step_by(2) {
                let r = f64::from(x).hypot(f64::from(z));
                if r > 50.0 && r < 220.0 {
                    let w = (f64::from(z).atan2(f64::from(x)).rem_euclid(TAU) / (TAU / 12.0)) as usize;
                    wedges[w.min(11)].0 += 1;
                    let b = a.block(0, x, a.top(0, x, z), z);
                    if b.contains("glazed") || (b.contains("concrete") && !b.contains("black") && !b.contains("gray")) {
                        wedges[w.min(11)].1 += 1;
                        tops.insert(b);
                    }
                }
            }
        }
        eprintln!("the pattern kept: {:?}", wedges.iter().map(|w| 100 * w.1 / w.0.max(1)).collect::<Vec<_>>());
        assert!(wedges.iter().all(|w| w.1 * 100 > w.0 * 8 && w.1 * 100 < w.0 * 85), "{wedges:?}");
        assert!(wedges.iter().map(|w| w.1).sum::<u32>() * 100 > wedges.iter().map(|w| w.0).sum::<u32>() * 25, "{wedges:?}");
        assert!(tops.len() >= 12, "{tops:?}");
    }
    /// Nothing of the old land stands inside it, on hills with a village, on mountains or in a jungle: every column inside
    /// the crater is cut well under the land's own top and everything over it goes, however tall.
    #[test]
    fn no_old_land_is_left_standing() {
        for land in [1u8, 2, 3] {
            let p = played(land);
            let a = After::new(&p);
            let mut hills = Vec::new();
            for i in 0..400u32 {
                let (t, r) = (mh(i, 8, 1) * TAU, 200.0 * mh(i, 8, 2).sqrt());
                let (x, z) = ((r * t.cos()) as i32, (r * t.sin()) as i32);
                hills.push(world(land, x, z).0);
            }
            hills.sort();
            let mut high = 0;
            let (mut wood, mut planks) = (0, 0);
            for x in -125..125 {
                for z in -125..125 {
                    if f64::from(x).hypot(f64::from(z)) < 125.0 {
                        let t = a.top(land, x, z);
                        high = high.max(t);
                        let b = a.block(land, x, t, z);
                        wood += i32::from(b.ends_with("_log") || b.ends_with("_leaves"));
                        planks += i32::from(b.ends_with("_planks"));
                        assert!(a.cols.contains_key(&(x, z)), "land {land}: column {x} {z} never cut");
                    }
                }
            }
            eprintln!("land {land}: the highest column within 125: {high}, the land's median about {}", hills[200]);
            assert_eq!((wood, planks), (0, 0), "land {land}");
            assert!(high < hills[200] + 28, "land {land}: {high} over {}", hills[200]);
        }
    }
    /// Land loaded late is waited for: nothing of it left standing.
    #[test]
    fn land_loaded_late_is_cut_too() {
        let p = played(7);
        let a = After::new(&p);
        let mut miss = 0;
        for x in 70..125 {
            for z in -70..70 {
                if f64::from(x).hypot(f64::from(z)) < 125.0 && !a.cols.contains_key(&(x, z)) {
                    miss += 1;
                }
            }
        }
        assert_eq!(miss, 0);
    }
    /// The water and lava it cuts into: the wall is solid rock wherever the crater bares it.
    #[test]
    fn its_walls_are_laid_solid() {
        let p = played(1);
        let a = After::new(&p);
        let mut bare = 0;
        for x in (-150..150).step_by(5) {
            for z in (-150..150).step_by(5) {
                let t = a.top(1, x, z);
                for (dx, dz) in [(1, 0), (0, 1)] {
                    let n = a.top(1, x + dx, z + dz);
                    let (hi, lo, cx, cz) = if t > n { (t, n, x, z) } else { (n, t, x + dx, z + dz) };
                    // (the wall of the higher column, down to the lower's top)
                    for y in lo + 1..hi {
                        let b = a.block(1, cx, y, cz);
                        if b == "minecraft:air" || b == "minecraft:water" {
                            bare += 1;
                        }
                    }
                }
            }
        }
        assert_eq!(bare, 0);
    }

    // ---- when it goes in ----------------------------------------------------------------------------------------------
    /// The land goes in from the middle out, only once the world is folded, all but the rubble by the last slam, each
    /// chunk's edits on one tick; the forceload is on from the fire and off at the end; the falling blocks fly at the
    /// slams; mobs die at the release, falling blocks spared.
    #[test]
    fn the_land_goes_in_under_the_fold() {
        let p = played(0);
        assert!(p.edits.len() > 300);
        let first = p.edits.iter().map(|e| e.1).fold(f32::MAX, f32::min);
        assert!(first >= FD_HIDDEN.start && first < FD_LAND0 + 0.5, "first {first}");
        // (the wave's own, not the rubble and the fires)
        let main: Vec<_> = p.edits.iter().filter(|e| !e.2.clear_of_player).collect();
        // (all of it behind the hold, the wave done in time for its last chunks' meshes to be ready)
        let all = p.edits.iter().map(|e| e.1).fold(0.0, f32::max);
        assert!(all < FD_HIDDEN.end, "the last edit at {all}");
        let wave_end = p.edits.iter().filter(|e| e.1 < FD_ISLE_AT - 0.01).map(|e| e.1).fold(0.0, f32::max);
        assert!(wave_end <= FD_LAND1 + 0.25, "the wave's last at {wave_end}");
        let late = p.edits.iter().map(|e| e.0 - e.1).fold(0.0, f32::max);
        assert!(late < 0.2, "{late} s late");
        // (the middle first)
        let at = |r: f64| main.iter().filter(|e| e.2.runs.iter().any(|u| (f64::from(u.x).hypot(f64::from(u.z)) - r).abs() < 4.0)).map(|e| e.1).fold(f32::MAX, f32::min);
        assert!(at(20.0) < at(100.0) && at(100.0) < at(170.0) && at(170.0) < at(280.0));
        // (each chunk edited on one tick, its rubble, fires and felled trees with its cut: a second is a second resend, nine
        // light jobs and its meshes again)
        let mut chunks: HashMap<(i32, i32), HashSet<i32>> = Default::default();
        for (t, _, b) in &p.edits {
            for r in &b.runs {
                chunks.entry((r.x >> 4, r.z >> 4)).or_default().insert((t / 0.05).round() as i32);
            }
        }
        let most = chunks.values().map(HashSet::len).max().unwrap_or(0);
        assert_eq!(most, 1, "a chunk edited on {most} ticks");
        // (what the game's frames feel: never many chunks a second)
        let mut per: BTreeMap<i32, usize> = Default::default();
        for t in chunks.values().flatten() {
            *per.entry(t / 20).or_default() += 1;
        }
        let busiest = per.values().max().unwrap_or(&0);
        eprintln!("busiest second: {busiest} chunks");
        assert!(*busiest < 320, "{busiest} chunks in a second");
        assert!(p.cmds.first().is_some_and(|c| c.1.starts_with("forceload add")), "{:?}", p.cmds.first());
        assert!(p.cmds.iter().any(|c| c.1.starts_with("forceload remove") && c.0 >= FD_LEN - 1.1));
        let thrown: Vec<f32> = p.cmds.iter().filter(|c| c.1.contains("falling_block ") && !c.1.contains("NoGravity")).filter(|c| c.1.starts_with("summon")).map(|c| c.0).collect();
        assert!(thrown.len() > 150, "{} thrown", thrown.len());
        // (thrown out of the crater by the slam that made it)
        assert!(thrown.iter().all(|t| *t >= FD_REVEAL && *t <= FD_REVEAL + 1.2), "{thrown:?}");
        let kills: Vec<&(f32, String)> = p.cmds.iter().filter(|c| c.1.contains("kill @e")).collect();
        assert!(!kills.is_empty() && kills[0].0 >= FD_HIDDEN.start - 0.1 && kills.iter().all(|c| c.1.contains("type=!minecraft:falling_block")));
    }

    // ---- the fuel -------------------------------------------------------------------------------------------------------
    /// (timed: `cargo test --release fold_no_stage -- --ignored --nocapture`, on its own)
    #[test]
    #[ignore]
    fn fold_no_stage_too_heavy_anywhere() {
        fold_anywhere(true);
    }
    /// Wherever it strikes, the land's edits go in on time.
    #[test]
    fn fold_land_goes_in_on_time_anywhere() {
        fold_anywhere(false);
    }
    fn fold_anywhere(timed: bool) {
        if timed && cfg!(debug_assertions) {
            return;
        }
        // (the land's work is the same on all three patterns but for the panels' drops: each on the two lands that find the most of it)
        for (land, pattern) in [(0u8, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (0, 1), (0, 2), (3, 1), (3, 2)] {
            PATTERN.with(|p| p.set(pattern));
            let mut best: Vec<f64> = Vec::new();
            let mut late_all = 0.0f32;
            for _ in 0..if timed { 3 } else { 1 } {
                let p = played(land);
                let late = p.edits.iter().map(|e| e.0 - e.1).fold(0.0f32, f32::max);
                late_all = late_all.max(late);
                let ms: Vec<f64> = p.stages.iter().map(|s| s.2).collect();
                best = if best.len() != ms.len() { ms } else { best.iter().zip(&ms).map(|(a, b)| a.min(*b)).collect() };
            }
            let worst = best.iter().copied().fold(0.0, f64::max);
            eprintln!("LAND {land} pattern {pattern}: {} stages, edits {late_all:.2} s late at most, heaviest {worst:.2} ms", best.len());
            assert!(!timed || worst < 1.3, "land {land}: a stage took {worst:.2} ms");
            // (the jungle's many runs meet FD_HELD: it goes in up to some 4 s late, its outer land past the reveal. Known, not fixed: round 3)
            assert!(land == 6 || late_all < if land == 3 { 5.5 } else { 0.4 }, "land {land}: an edit {late_all:.2} s late");
        }
        LAND.with(|l| l.set(0));
        PATTERN.with(|p| p.set(0));
    }
    /// The three patterns' panels: an umbrella's whole, a waterbomb's in four, a diagonal's in two, each part inside its own panel.
    #[test]
    fn the_panels_break_along_their_pattern() {
        for (pattern, parts) in [(0usize, 1usize), (1, 4), (2, 2)] {
            let mut seen = std::collections::HashSet::new();
            for n in 0..1440 {
                let w = fd_wedge(f64::from(n).to_radians() / 4.0 + 0.001, 0.0);
                for r in (116..250).step_by(3) {
                    let r = f64::from(r);
                    let i = (0..4).find(|i| r * w.ix(*i) < 1.0).unwrap_or(3);
                    seen.insert((w.k, i, facet(pattern, &w, i, r)));
                }
            }
            let most = (0..12).flat_map(|k| (0..4).map(move |i| (k, i))).map(|(k, i)| seen.iter().filter(|s| s.0 == k && s.1 == i).count()).max();
            assert_eq!(most, Some(parts), "pattern {pattern}");
        }
    }
    /// `cargo test --release fd_wave_profile -- --ignored --nocapture`: the land's edits as the mod plays them out: how far
    /// out they reach a second at a time, how many blocks, chunks; $FD_LAND the land.
    #[test]
    #[ignore]
    fn fd_wave_profile() {
        let land = std::env::var("FD_LAND").ok().and_then(|v| v.parse().ok()).unwrap_or(1);
        let p = played(land);
        let mut bins: BTreeMap<i32, (u64, u64, usize, f64, f64, HashSet<(i32, i32)>)> = Default::default();
        let mut tick_blocks: BTreeMap<i32, u64> = Default::default();
        let mut tick_chunks: BTreeMap<i32, HashSet<(i32, i32)>> = Default::default();
        let (mut all, mut solid) = (0u64, 0u64);
        for (t, _, b) in &p.edits {
            let e = bins.entry((t / 0.5) as i32).or_insert((0, 0, 0, f64::MAX, 0.0, HashSet::new()));
            for u in &b.runs {
                let r = f64::from(u.x).hypot(f64::from(u.z));
                let h = u64::from(u.height);
                all += h;
                e.0 += h;
                if b.palette[u.block as usize] != AIR {
                    e.1 += h;
                    solid += h;
                }
                e.2 += 1;
                e.3 = e.3.min(r);
                e.4 = e.4.max(r);
                e.5.insert((u.x >> 4, u.z >> 4));
                *tick_blocks.entry((t / 0.05).round() as i32).or_default() += h;
                tick_chunks.entry((t / 0.05).round() as i32).or_default().insert((u.x >> 4, u.z >> 4));
            }
        }
        for (k, v) in &bins {
            println!("{:6.2} s: {:8} blocks, {:8} laid, {:7} runs, r {:4.0}..{:4.0}, {:4} chunks", *k as f32 * 0.5, v.0, v.1, v.2, v.3, v.4, v.5.len());
        }
        let heavy = p.stages.iter().map(|s| s.2).fold(0.0f64, f64::max);
        let late = p.edits.iter().map(|e| e.0 - e.1).fold(0.0f32, f32::max);
        let runs: usize = p.edits.iter().map(|e| e.2.runs.len()).sum();
        let last_wave = p.edits.iter().map(|e| e.1).fold(0.0f32, f32::max);
        println!("{all} blocks ({solid} laid), {runs} runs, {} edits, {} stages, heaviest {heavy:.2} ms, edits {late:.2} s late at most, the last due at {last_wave:.2}", p.edits.len(), p.stages.len());
        let top = tick_blocks.iter().max_by_key(|e| *e.1).map_or(0.0, |e| *e.0 as f32 * 0.05);
        let tc = tick_chunks.iter().max_by_key(|e| e.1.len()).map_or(0.0, |e| *e.0 as f32 * 0.05);
        println!("busiest ticks at {top:.2} and {tc:.2}");
        println!("busiest tick {} blocks, {} chunks", tick_blocks.values().max().unwrap_or(&0), tick_chunks.values().map(HashSet::len).max().unwrap_or(0));
        let mut st: Vec<_> = p.stages.iter().map(|s| (s.2, s.0, s.1)).collect();
        st.sort_by(|a, b| b.0.total_cmp(&a.0));
        println!("heaviest stages (ms, due, ran): {:?}", &st[..12.min(st.len())]);
        let band = |t0: f32, t1: f32| { let v: Vec<f64> = p.stages.iter().filter(|s| s.0 >= t0 && s.0 < t1).map(|s| s.2).collect(); (v.len(), v.iter().sum::<f64>() / v.len().max(1) as f64) };
        for t in (0..50).step_by(5) { println!("stages due {t}..: {:?}", band(t as f32, t as f32 + 5.0)); }
        println!("{} commands, {} of them summons", p.cmds.len(), p.cmds.iter().filter(|c| c.1.starts_with("summon")).count());
    }

    // ---- the look -------------------------------------------------------------------------------------------------------
    fn rgb(name: &str) -> Option<[f32; 3]> {
        let n = name.split('[').next()?.strip_prefix("minecraft:")?;
        let hue = |c: &str| -> [f32; 3] {
            match c {
                "red" => [0.69, 0.18, 0.15],
                "orange" => [0.85, 0.4, 0.07],
                "yellow" => [0.94, 0.72, 0.1],
                "lime" => [0.44, 0.7, 0.1],
                "green" => [0.29, 0.4, 0.14],
                "cyan" => [0.08, 0.52, 0.55],
                "light_blue" => [0.2, 0.55, 0.78],
                "blue" => [0.18, 0.2, 0.62],
                "purple" => [0.4, 0.14, 0.62],
                "magenta" => [0.7, 0.2, 0.65],
                "pink" => [0.9, 0.5, 0.65],
                "black" => [0.05, 0.05, 0.07],
                "gray" => [0.21, 0.23, 0.25],
                _ => [0.9, 0.9, 0.9],
            }
        };
        Some(if let Some(c) = n.strip_suffix("_glazed_terracotta") {
            let h = hue(c);
            [h[0] * 0.95 + 0.04, h[1] * 0.95 + 0.04, h[2] * 0.95 + 0.04]
        } else if let Some(c) = n.strip_suffix("_concrete") {
            hue(c)
        } else if n.ends_with("_log") {
            [0.33, 0.25, 0.15]
        } else if n.ends_with("_leaves") {
            [0.2, 0.36, 0.14]
        } else if n.ends_with("_planks") {
            [0.6, 0.46, 0.28]
        } else {
            match n {
                "air" => return None,
                "fire" => [1.5, 0.7, 0.15],
                "water" => [0.15, 0.3, 0.7],
                "grass_block" => [0.33, 0.5, 0.22],
                "snow_block" => [0.92, 0.95, 0.97],
                "sand" => [0.84, 0.78, 0.6],
                "dirt" | "rooted_dirt" => [0.4, 0.28, 0.18],
                "coarse_dirt" => [0.33, 0.24, 0.16],
                "podzol" => [0.3, 0.2, 0.1],
                "stone" => [0.45, 0.45, 0.45],
                "cobblestone" => [0.42, 0.42, 0.42],
                "blackstone" | "polished_blackstone" => [0.13, 0.11, 0.14],
                "basalt" | "smooth_basalt" => [0.24, 0.24, 0.26],
                "cobbled_deepslate" => [0.26, 0.26, 0.27],
                "deepslate" => [0.3, 0.3, 0.32],
                "tuff" => [0.4, 0.41, 0.36],
                "coal_block" => [0.08, 0.08, 0.08],
                "magma_block" => [1.1, 0.4, 0.08],
                "crying_obsidian" => [0.5, 0.15, 0.85],
                "obsidian" => [0.06, 0.04, 0.1],
                "netherrack" => [0.45, 0.16, 0.14],
                _ => [0.6, 0.0, 0.6],
            }
        })
    }
    /// The land as voxels for the preview (tools/preview.py's `vox=2` views), written to $FL_OUT: a line `x y z r g b` a
    /// block, every block a column shows. $FL_LAND: the land (0 flat, 1 hills and a village, 2 mountains), $FL_SEED.
    #[test]
    #[ignore]
    fn fl_dump_land() {
        let out = std::env::var("FL_OUT").unwrap_or("../dist/preview/fold_land.txt".into());
        let land: u8 = std::env::var("FL_LAND").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
        let seed: f32 = std::env::var("FL_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(37.0);
        LAND.with(|l| l.set(land));
        let ev = plan(the_laser(), &target(), true, "minecraft:overworld", seed, ME, 0);
        let p = sim::play(ev, FD_LEN, &column);
        let a = After::new(&p);
        let n = FD_READ + 30;
        let w = (2 * n + 1) as usize;
        let tops: Vec<i32> = (-n..=n).flat_map(|z| (-n..=n).map(move |x| (x, z))).map(|(x, z)| a.top(land, x, z)).collect();
        let t = |x: i32, z: i32| -> i32 {
            if x.abs() > n || z.abs() > n { i32::MIN } else { tops[(z + n) as usize * w + (x + n) as usize] }
        };
        let mut s = String::new();
        let mut count = 0;
        for z in -n..=n {
            for x in -n..=n {
                let top = t(x, z);
                let lo = [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().map(|d| t(x + d.0, z + d.1)).filter(|v| *v != i32::MIN).min().unwrap_or(top).min(top - 1).max(top - 90);
                for y in lo..=top {
                    if let Some(c) = rgb(a.block(land, x, y, z)) {
                        s.push_str(&format!("{x} {y} {z} {:.2} {:.2} {:.2}\n", c[0], c[1], c[2]));
                        count += 1;
                    }
                }
                // (what lies or burns on it)
                let b = a.block(land, x, top + 1, z);
                if b == "minecraft:fire" {
                    s.push_str(&format!("{x} {} {z} 1.5 0.7 0.15\n", top + 1));
                }
            }
        }
        std::fs::create_dir_all(std::path::Path::new(&out).parent().unwrap()).unwrap();
        std::fs::write(&out, s).unwrap();
        eprintln!("{count} voxels -> {out}");
    }
}
