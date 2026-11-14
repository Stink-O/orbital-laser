//! The World Eater's land: what it does to the world, as real blocks, from the path (strike/we_path.rs)
//! as strike/worldeater.rs plays it out (an arch at a time: a hunt's arches are planned as it goes).
//!
//! - **Sites**: the land round each knot (a disc `SITE_R` across) and along each tunnelled stretch (a corridor), read
//!   from the world (`world.read-columns`, payload.rs's reader: each column's ground, what stands on it) a few seconds
//!   before it is needed, taken in a part a stage. What the worm does to a site is kept in it (each column's ground and
//!   top as it leaves them), so a knot it bites and later breaches again works on the land as the bite left it.
//! - **A hole** at each knot: open to bedrock (`dig`, from the middle out as the head goes through), its walls dressed
//!   darkening downward (stone and tuff, then deepslate, cobbled deepslate and sculk, then blackstone at the bottom), the
//!   water and lava in them sealed (tuff, magma). A bite's rim then caves to a funnel (`funnel`). A breach throws a rim
//!   of earth out to `rim` and fells the trees out to `fell` lying pointing away (`heap`, `felled`), with real falling
//!   blocks and whole trees thrown out of it (`thrown`); a bite fells the trees close round it. What is left hanging
//!   (leaves of a tree whose trunk went, plants whose ground went) goes (`tidy_rows`). Sculk creeps out from each hole
//!   (`sculk`).
//! - **A trench** where it tunnelled from one knot to the next: after its tail has gone in, the land between sinks
//!   ring by ring from the first hole to the second (`trench_floors`, `trench_rings`): ~50 wide, ~25 deep, uneven, a
//!   rubble floor, following each column's own ground; lakes and rivers are left (and the ground next to them, as a
//!   dam), lava under its floor sealed, trees on it laid on its floor along it.
//! - **The furrow** behind the wormsign's mound (`furrow`): a low ridge of turned earth along its track, laid just
//!   behind the mound as it passes.
//!
//! Every edit goes in through `world.edit-blocks`, split by the tick it is due (`Blocks::split_by`), so each hole and
//! each trench goes in as a wave and no tick takes much of it (worldeater.rs's `we_land_profile` prints the busiest).
use super::payload::{self, Column, LEAVES, LOG_X, LOG_Y, LOG_Z, PL_ABOVE, PL_BELOW};
use super::{Act, Blocks, Col, Plan, Rng, mh, surf, tidy, vnoise};
use crate::ground::FxMap;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;

/// `hypot` through `sqrt`: one WebAssembly instruction where libm's hypot is hundreds (the land's loops take one a
/// column). The World Eater's land files use it for every length.
pub(super) trait Hyp {
    fn hyp(self, other: f64) -> f64;
}
impl Hyp for f64 {
    #[inline]
    fn hyp(self, other: f64) -> f64 {
        (self * self + other * other).sqrt()
    }
}

/// A column `heap` looks at with `Hole::at` (nearly every column of the site: an atan2, the wobble's sines and the
/// cell; ~1,100 WebAssembly instructions, by mod_soak's trace). Uncounted, the meter saw a fifth of a breach's rim, the
/// pump ran the rim's parts and the sculk after them in one tick beside the per-tick tables, and that tick took over
/// half its fuel (mod_soak, the game's log); counted, the pump (PUMP_FILL) leaves the rest for the next tick. (The
/// rim's parts are smaller for it: worldeater.rs's `breach_land` and `bite_land`.)
const AT_COST: u64 = 1_100;
/// The land read round each knot (radius), and how many columns a query and a take-in stage carry.
pub(super) const SITE_R: f64 = 124.0;
const PER_READ: usize = 3300;
/// A trench: half its width, its depth (both wander).
pub(super) const TR_W: f64 = 25.0;
pub(super) const TR_D: f64 = 25.0;

/// What has happened to a column.
const DUG: u8 = 1;
const HEAPED: u8 = 2;
const FELLED: u8 = 4;
const FELL_NOW: u8 = 8;
const LAID: u8 = 16;
/// Everything over its ground swept off by us.
const CLEARED: u8 = 32;
const TRENCH: u8 = 64;

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct Cell {
    pub c: Column,
    pub g: i32,
    pub top: i32,
    pub flag: u8,
}

/// A stretch of land as read, and what the worm has made of it.
#[derive(Default)]
pub(super) struct Site {
    /// Each column of its square's index into `cells` (u32::MAX: not one of its columns): a dense grid, not a hash map
    /// (some fifty thousand columns a site; a hash map's inserts cost a stage's fuel).
    x0: i32,
    z0: i32,
    w: i32,
    h: i32,
    grid: Vec<u32>,
    pub cols: Vec<(i32, i32)>,
    pub cells: Vec<Cell>,
    missing: Vec<(i32, i32)>,
}
pub(super) type Shared = Rc<RefCell<Site>>;
impl Site {
    pub fn new(cols: Vec<(i32, i32)>) -> Site {
        let (mut x0, mut z0, mut x1, mut z1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for &(x, z) in &cols {
            (x0, z0, x1, z1) = (x0.min(x), z0.min(z), x1.max(x), z1.max(z));
        }
        if cols.is_empty() {
            return Site::default();
        }
        let (w, h) = (x1 - x0 + 1, z1 - z0 + 1);
        crate::meter::spend(60 * cols.len() as u64 + 4 * (w * h) as u64);
        let mut grid = vec![u32::MAX; (w * h) as usize];
        for (i, &(x, z)) in cols.iter().enumerate() {
            grid[((z - z0) * w + (x - x0)) as usize] = i as u32;
        }
        let cells = vec![Cell::default(); cols.len()];
        Site { x0, z0, w, h, grid, cols, cells, missing: Vec::new() }
    }
    fn idx(&self, x: i32, z: i32) -> Option<usize> {
        let (i, k) = (x - self.x0, z - self.z0);
        if i < 0 || k < 0 || i >= self.w || k >= self.h {
            return None;
        }
        let v = self.grid[(k * self.w + i) as usize];
        (v != u32::MAX).then_some(v as usize)
    }
    /// The column's cell, if it was read.
    fn known(&self, x: i32, z: i32) -> Option<usize> {
        self.idx(x, z).filter(|&i| self.cells[i].c.known)
    }
    fn wet_near(&self, x: i32, z: i32) -> bool {
        [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|(dx, dz)| self.known(x + dx, z + dz).is_some_and(|i| self.cells[i].c.fluid))
    }
    /// Nothing over its ground and nothing laid on it.
    fn open(&self, i: usize) -> bool {
        let c = &self.cells[i];
        c.top == c.g && c.flag & (LAID | DUG) == 0 && !c.c.fluid
    }
    /// The cells of rows z0..=z1 (a site made row by row, as `disc` makes it): their index range.
    pub fn rows(&self, z0: i32, z1: i32) -> (usize, usize) {
        (self.cols.partition_point(|c| c.1 < z0), self.cols.partition_point(|c| c.1 <= z1))
    }
    pub fn known_count(&self) -> usize {
        self.cells.iter().filter(|c| c.c.known).count()
    }
    fn put(&mut self, x: i32, z: i32, c: Column) {
        if let Some(i) = self.idx(x, z) {
            self.cells[i] = Cell { c, g: c.g, top: c.top.max(c.g), flag: 0 };
        }
    }
}

/// The columns within `r` of (cx, cz), row by row.
pub(super) fn disc(cx: f64, cz: f64, r: f64) -> Vec<(i32, i32)> {
    let mut out = Vec::new();
    let (z0, z1) = ((cz - r).floor() as i32, (cz + r).ceil() as i32);
    for z in z0..=z1 {
        let dz = f64::from(z) + 0.5 - cz;
        if dz.abs() > r {
            continue;
        }
        let half = (r * r - dz * dz).sqrt();
        for x in ((cx - half) - 0.5).ceil() as i32..=((cx + half) - 0.5).floor() as i32 {
            out.push((x, z));
        }
    }
    crate::meter::spend(30 * out.len() as u64);
    out
}

/// The columns within `w` of the segment a..b (world, level), less those `skip` says: row by row, each row's stretch
/// worked out (the capsule round the segment is convex: one stretch a row), no column outside it looked at.
pub(super) fn corridor(a: [f64; 2], b: [f64; 2], w: f64, skip: impl Fn(i32, i32) -> bool) -> Vec<(i32, i32)> {
    corridor_part(a, b, w, skip, 0, 1)
}
/// The rows of part `p` of `n` of `corridor`'s (in order: the parts one after another are the whole).
pub(super) fn corridor_part(a: [f64; 2], b: [f64; 2], w: f64, skip: impl Fn(i32, i32) -> bool, p: usize, n: usize) -> Vec<(i32, i32)> {
    let (dx, dz) = (b[0] - a[0], b[1] - a[1]);
    let l2 = dx * dx + dz * dz;
    let mut out = Vec::new();
    let (z0, z1) = ((a[1].min(b[1]) - w).floor() as i32, (a[1].max(b[1]) + w).ceil() as i32);
    let rows = (z1 - z0 + 1) as usize;
    let (r0, r1) = (rows * p / n, rows * (p + 1) / n);
    for z in z0 + r0 as i32..z0 + r1 as i32 {
        let pz = f64::from(z) + 0.5;
        let (mut lo, mut hi) = (f64::MAX, f64::MIN);
        // (the discs round either end)
        for c in [a, b] {
            let e = pz - c[1];
            if e.abs() <= w {
                let h = (w * w - e * e).sqrt();
                lo = lo.min(c[0] - h);
                hi = hi.max(c[0] + h);
            }
        }
        // (the band between: 0 <= along <= l2 and |across| <= w l, each linear in x along the row)
        if l2 > 1e-9 {
            let l = l2.sqrt();
            let (mut blo, mut bhi) = (f64::MIN, f64::MAX);
            let mut clip = |k: f64, c: f64, lo_v: f64, hi_v: f64| {
                // lo_v <= k x + c <= hi_v
                if k.abs() < 1e-12 {
                    if c < lo_v || c > hi_v {
                        (blo, bhi) = (1.0, 0.0);
                    }
                } else {
                    let (p, q) = ((lo_v - c) / k, (hi_v - c) / k);
                    blo = blo.max(p.min(q));
                    bhi = bhi.min(p.max(q));
                }
            };
            clip(dx, (pz - a[1]) * dz - a[0] * dx, 0.0, l2);
            clip(-dz, (pz - a[1]) * dx + a[0] * dz, -w * l, w * l);
            if blo <= bhi {
                lo = lo.min(blo);
                hi = hi.max(bhi);
            }
        }
        if lo > hi {
            continue;
        }
        for x in (lo - 0.5).ceil() as i32..=(hi - 0.5).floor() as i32 {
            if !skip(x, z) {
                out.push((x, z));
            }
        }
    }
    crate::meter::spend(300 * out.len() as u64 + 400 * (r1 - r0) as u64);
    out
}

/// As `read`, the site made at `at` of the columns `cols` gives (the plan's own call stays light: making a site of
/// tens of thousands of columns is a stage's work).
pub(super) fn read_new(p: &mut Plan, at: f32, site: &Shared, until: f32, cols: impl FnOnce() -> Vec<(i32, i32)> + 'static) {
    let s2 = site.clone();
    p.later(at, move |q| {
        *s2.borrow_mut() = Site::new(cols());
        read(q, at + 0.05, &s2, until);
    });
}

/// Read `site`'s columns from `at` (a query each PER_READ, asked together), taken in a part a stage as they are
/// answered; the ones not loaded yet asked once more. Nothing is taken in after `until`.
pub(super) fn read(p: &mut Plan, at: f32, site: &Shared, until: f32) {
    let site = site.clone();
    p.later(at, move |q| {
        let parts: Vec<Vec<(i32, i32)>> = site.borrow().cols.chunks(PER_READ).map(<[(i32, i32)]>::to_vec).collect();
        let tags: Vec<u32> = parts.iter().map(|_| crate::columns::new_tag()).collect();
        for (cols, &tag) in parts.into_iter().zip(&tags) {
            q.ev.push((at, Act::Read { tag, columns: cols, below: PL_BELOW, above: PL_ABOVE }));
        }
        let t = at + 0.1;
        q.later(t, move |q| take_step(q, site, Rc::new(tags), 0, t, until, 0));
    });
}
fn take_step(q: &mut Plan, site: Shared, tags: Rc<Vec<u32>>, part: usize, at_t: f32, until: f32, retry: u32) {
    crate::trace("we take_step begins");
    if part >= tags.len() {
        let missing = std::mem::take(&mut site.borrow_mut().missing);
        if !missing.is_empty() && retry < 1 && at_t + 1.0 < until {
            let t = at_t + 0.8;
            q.later(t, move |q| {
                let tags: Vec<u32> = missing
                    .chunks(PER_READ)
                    .map(|c| {
                        let tag = crate::columns::new_tag();
                        q.ev.push((t, Act::Read { tag, columns: c.to_vec(), below: PL_BELOW, above: PL_ABOVE }));
                        tag
                    })
                    .collect();
                q.later(t + 0.15, move |q| take_step(q, site, Rc::new(tags), 0, t + 0.15, until, retry + 1));
            });
        }
        return;
    }
    let Some(a) = crate::columns::take(tags[part]) else {
        if at_t < until {
            q.later(at_t + 0.1, move |q| take_step(q, site, tags, part, at_t + 0.1, until, retry));
        } else {
            crate::columns::forget(tags[part]);
        }
        return;
    };
    {
        // (each column's blocks looked through from its top down to its ground: `meter`; some 4,500 instructions a
        // column in the game's WebAssembly, by mod_soak)
        crate::meter::spend(4_500 * a.columns.len() as u64);
        let mut s = site.borrow_mut();
        let mut got = Vec::new();
        let mut missing = Vec::new();
        payload::take_in_each(&a, |x, z, c| got.push((x, z, c)), |x, z| missing.push((x, z)));
        for (x, z, c) in got {
            s.put(x, z, c);
        }
        s.missing.extend(missing);
    }
    q.later(at_t + 0.05, move |q| take_step(q, site, tags, part + 1, at_t + 0.05, until, retry));
}

// ---- a hole --------------------------------------------------------------------------------------------------------
/// A hole at a knot: its middle (world), its ground (the knot's ground block), its radius (wandering), its funnel's
/// outer radius (a bite's; the radius itself for none), how far its rim of thrown earth and its felled trees reach.
#[derive(Clone, Copy, Debug)]
pub(super) struct Hole {
    pub cx: f64,
    pub cz: f64,
    pub g: i32,
    pub r: f64,
    pub rf: f64,
    pub rim: f64,
    pub fell: f64,
    pub seed: u32,
    pub ph: [f64; 4],
}
impl Hole {
    pub fn new(cx: f64, cz: f64, g: i32, r: f64, rf: f64, seed: u32) -> Hole {
        let ph = [0, 1, 2, 3].map(|k| TAU * mh(k, seed, 0x401));
        Hole { cx, cz, g, r, rf, rim: 112.0, fell: 120.0, seed, ph }
    }
    fn wob(&self, a: f64) -> f64 {
        1.0 + 0.08 * (3.0 * a + self.ph[0]).sin() + 0.05 * (5.0 * a + self.ph[1]).sin() + 0.03 * (11.0 * a + self.ph[2]).sin()
    }
    /// Column (x, z): how far from the middle, its bearing, the hole's edge on that bearing.
    pub fn at(&self, x: i32, z: i32) -> (f64, f64, f64) {
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let a = dz.atan2(dx);
        (dx.hyp(dz), a, self.r * self.wob(a))
    }
    /// The funnel's outer edge on bearing `a` (the edge itself for none).
    fn fedge(&self, a: f64) -> f64 {
        let e = self.r * self.wob(a);
        if self.rf <= self.r { e } else { e + (self.rf - self.r) * (1.0 + 0.18 * (4.0 * a + self.ph[3]).sin()) }
    }
    /// Whether column (x, z) is within `r` of its middle (no trigonometry: for the loops over a whole site).
    pub fn near(&self, x: i32, z: i32, r: f64) -> bool {
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        dx * dx + dz * dz <= r * r
    }
    /// The farthest its funnel (or its wall) reaches on any bearing.
    pub fn reach_max(&self) -> f64 {
        (self.r * 1.17 + 3.0).max(self.r * 1.17 + (self.rf - self.r).max(0.0) * 1.18)
    }
    /// Whether column (x, z) is in the hole, its funnel or its dressed wall (`pad` further out).
    pub fn holds(&self, x: i32, z: i32, pad: f64) -> bool {
        // (most columns asked are far from it: no trigonometry for them)
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let (far, sure) = (self.reach_max() + pad, self.r * 0.83);
        let d2 = dx * dx + dz * dz;
        if d2 > far * far {
            return false;
        }
        if d2 < sure * sure {
            return true;
        }
        let (r, a, e) = self.at(x, z);
        r < self.fedge(a).max(e + 3.0) + pad
    }
}

/// The hole's wall, darkening downward: what replaces the natural stone at height `y` (the bottom `floor`, the ground
/// `g`), none where it is left.
fn wall_block(x: i32, y: i32, z: i32, g: i32, floor: i32, seed: u32) -> Option<&'static str> {
    let n = vnoise(f64::from(x) * 0.9 + f64::from(y) * 0.6, f64::from(z) * 0.9 - f64::from(y) * 0.3, 3.5, seed ^ 0x5a);
    let f = f64::from(y - floor) / f64::from((g - floor).max(1));
    if f > 0.75 {
        (n < 0.28).then_some("minecraft:tuff")
    } else if f > 0.5 {
        if n < 0.3 {
            Some("minecraft:tuff")
        } else if n < 0.5 {
            Some("minecraft:deepslate")
        } else {
            None
        }
    } else if f > 0.25 {
        Some(if n < 0.22 { "minecraft:sculk" } else if n < 0.45 { "minecraft:cobbled_deepslate" } else if n < 0.62 { "minecraft:tuff" } else { "minecraft:deepslate" })
    } else {
        Some(if n < 0.35 { "minecraft:blackstone" } else if n < 0.5 { "minecraft:sculk" } else if n < 0.62 { "minecraft:basalt" } else { "minecraft:deepslate" })
    }
}
/// The loose rock and earth that lands on a floor (a funnel's slope, a trench's, the bottom of a hole), deeper darker.
fn rubble(x: i32, y: i32, z: i32, deep: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) * 1.3 + f64::from(y) * 0.7, f64::from(z) * 1.3, 2.5, seed ^ 0x61);
    let m = mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917) ^ y.wrapping_mul(1_181)) as u32, seed, 0x62);
    if m < 0.05 + 0.1 * deep {
        return "minecraft:sculk";
    }
    if deep > 0.5 {
        if n < 0.3 {
            "minecraft:cobbled_deepslate"
        } else if n < 0.5 {
            "minecraft:tuff"
        } else if n < 0.7 {
            "minecraft:gravel"
        } else {
            "minecraft:deepslate"
        }
    } else if n < 0.25 {
        "minecraft:coarse_dirt"
    } else if n < 0.45 {
        "minecraft:gravel"
    } else if n < 0.65 {
        "minecraft:cobblestone"
    } else if n < 0.8 {
        "minecraft:tuff"
    } else {
        "minecraft:rooted_dirt"
    }
}

/// `out`'s runs sorted into the ticks they go in at, each chunk's on one tick (the earliest `when` of its columns): the
/// game sends a chunk an edit changes whole, so a wave that changes each chunk once costs the frame least.
fn by_chunk(out: &Blocks, when: impl Fn(i32, i32) -> f32) -> Vec<(f32, Blocks)> {
    let mut m: FxMap<(i32, i32), f32> = FxMap::default();
    crate::meter::spend(150 * out.runs.len() as u64);
    for r in &out.runs {
        let t = when(r.x, r.z);
        m.entry((r.x >> 4, r.z >> 4)).and_modify(|v| *v = v.min(t)).or_insert(t);
    }
    out.split_by(|x, z| m.get(&(x >> 4, z >> 4)).copied().unwrap_or(0.0))
}
/// As `by_chunk`, `when` asked once a chunk, at its middle (for times that are only a matter of where).
fn by_chunk_at(out: &Blocks, when: impl Fn(i32, i32) -> f32) -> Vec<(f32, Blocks)> {
    let mut m: FxMap<(i32, i32), f32> = FxMap::default();
    crate::meter::spend(60 * out.runs.len() as u64);
    for r in &out.runs {
        m.entry((r.x >> 4, r.z >> 4)).or_insert_with(|| {
            crate::meter::spend(1_500);
            when((r.x >> 4) * 16 + 8, (r.z >> 4) * 16 + 8)
        });
    }
    out.split_by(|x, z| m.get(&(x >> 4, z >> 4)).copied().unwrap_or(0.0))
}

fn smooth(x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}

/// Dig the hole over cells i0..i1 of its site: open to bedrock (from the bottom `floor` up), from the middle out from
/// `t0` (all under the body, WE_R across, at once) to `t1` at its edge; its wall dressed and sealed just after.
#[allow(clippy::too_many_arguments)]
pub(super) fn dig(q: &mut Plan, site: &mut Site, h: &Hole, floor: i32, t0: f32, t1: f32, i0: usize, i1: usize, count: Option<(&Rc<std::cell::Cell<u32>>, &Rc<std::cell::Cell<u32>>)>) {
    crate::trace("we dig begins");
    // (the hole itself, and the seal of water in its wall, urgent: the body comes through it whatever the frame time;
    // the wall's dressing after it)
    let mut hole = Blocks { urgent: true, ..Default::default() };
    let mut out = Blocks::default();
    let mut when: FxMap<(i32, i32), f32> = FxMap::default();
    crate::meter::spend(60 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    for i in i0..i1.min(site.cells.len()) {
        let (x, z) = site.cols[i];
        if !h.near(x, z, h.r * 1.17 + 3.0) {
            continue;
        }
        let cell = site.cells[i];
        let (r, _, e) = h.at(x, z);
        if r >= e + 3.0 {
            continue;
        }
        crate::meter::spend(800);
        // (an unread column: its ground taken as the knot's, its top well over it)
        let (g, top) = if cell.c.known { (cell.g, cell.top) } else { (h.g, h.g + 30) };
        if r < e {
            // the hole: everything gone down to the bottom, its floor a scatter of rubble and sculk over the bedrock
            let wtop = if cell.c.known && cell.c.fluid { cell.c.wtop } else { g };
            hole.run(x, z, floor + 1, top.max(g).max(wtop) + 1, "minecraft:air");
            hole.run(x, z, floor, floor, rubble(x, floor, z, 1.0, h.seed));
            hole.put(x, z, floor - 1, floor - 1, "minecraft:magma_block", Some("minecraft:lava"), false);
            hole.put(x, z, floor - 1, floor - 1, "minecraft:tuff", Some("minecraft:water"), false);
            site.cells[i].g = floor;
            site.cells[i].top = floor;
            site.cells[i].flag |= DUG | CLEARED;
            // (as many columns a tick from the middle out: those under the body first, hidden by it)
            let w = t0 + (t1 - t0) * ((r / e).clamp(0.0, 1.0).powi(2) as f32);
            when.insert((x, z), w);
        } else {
            // its wall: the stone dressed darker downward in runs of ten, the water and lava in it sealed
            let mut y = floor;
            while y <= g - 4 {
                let y1 = (y + 9).min(g - 4);
                if let Some(b) = wall_block(x, y, z, g, floor, h.seed) {
                    out.put(x, z, y, y1, b, Some("#minecraft:base_stone_overworld"), false);
                }
                y = y1 + 1;
            }
            // (the water in it sealed right up to its surface: a hole cut in a lake or the sea has a wall of tuff round
            // it, not water standing; the lava only low down, where lava lies)
            let wet = cell.c.known && cell.c.fluid && !cell.c.lava;
            if wet {
                hole.put(x, z, floor, cell.c.wtop.max(g), "minecraft:tuff", Some("minecraft:water"), false);
            } else {
                out.put(x, z, floor, g, "minecraft:tuff", Some("minecraft:water"), false);
            }
            out.put(x, z, floor, g.min(16), "minecraft:magma_block", Some("minecraft:lava"), false);
            // (round the wall over half a second once its stretch is open)
            let (_, a, _) = h.at(x, z);
            // (a wet wall sealed as the hole begins, before any of it opens beside it)
            when.insert((x, z), if wet { t0 } else { t1 + 0.1 + 0.5 * ((a + PI) / TAU) as f32 });
        }
    }
    for o in [&hole, &out] {
        for (t, mut b) in by_chunk(o, |x, z| when.get(&(x, z)).copied().unwrap_or(t1)) {
            // (the hole's own edits counted as they are made and as they go in: `hole_log`)
            if let (true, Some((made, sent))) = (b.urgent, count) {
                made.set(made.get() + 1);
                b.sent = Some(sent.clone());
            }
            q.ev.push((t, Act::Blocks(Box::new(b))));
        }
    }
}

/// How far outside a funnel the lake it cuts into is dammed.
const DAM: f64 = 2.5;

/// A bite's rim caving in to a funnel over cells i0..i1: the ground between its edge and the funnel's outer edge
/// slumped into a slope down to 24 under it at the edge, rubble on it, from the inside out over `t0`..`t1`.
pub(super) fn funnel(q: &mut Plan, site: &mut Site, h: &Hole, t0: f32, t1: f32, i0: usize, i1: usize) {
    crate::trace("we funnel begins");
    let mut out = Blocks::default();
    let mut when: FxMap<(i32, i32), f32> = FxMap::default();
    crate::meter::spend(60 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    for i in i0..i1.min(site.cells.len()) {
        let (x, z) = site.cols[i];
        let cell = site.cells[i];
        if !cell.c.known || cell.flag & DUG != 0 || cell.c.lava || !h.near(x, z, h.reach_max() + DAM) {
            continue;
        }
        let (r, a, e) = h.at(x, z);
        let fe = h.fedge(a);
        // (water in a lake the funnel cuts into: drained inside it, dammed in tuff up to the lake's top just outside it;
        // edit-blocks doesn't set water flowing, so water left standing by the slope would stand there as walls and
        // pillars)
        let wet = cell.c.fluid;
        let wtop = cell.c.wtop.max(cell.g);
        if r < e || r >= fe + DAM || (r >= fe && !wet) {
            continue;
        }
        crate::meter::spend(700);
        if r >= fe {
            out.put(x, z, cell.g - 2, wtop, "minecraft:tuff", Some("minecraft:water"), false);
            when.insert((x, z), t0 + 0.05);
            continue;
        }
        let u = (fe - r) / (fe - e);
        let d = (24.0 * u.powf(1.4) + 2.0 * (vnoise(f64::from(x), f64::from(z), 4.0, h.seed ^ 0x77) - 0.5)).round() as i32;
        if d < 1 {
            if wet {
                out.put(x, z, cell.g + 1, wtop + 1, "minecraft:air", Some("minecraft:water"), false);
                when.insert((x, z), t0 + (t1 - t0) * (1.0 - u as f32));
            }
            continue;
        }
        let ng = cell.g - d;
        out.run(x, z, ng + 1, cell.top.max(wtop) + 2, "minecraft:air");
        out.run(x, z, ng - 1, ng, rubble(x, ng, z, 0.6 * u, h.seed));
        out.put(x, z, ng - 4, ng - 2, "minecraft:magma_block", Some("minecraft:lava"), false);
        site.cells[i].g = ng;
        site.cells[i].top = ng;
        site.cells[i].flag |= DUG | CLEARED;
        when.insert((x, z), t0 + (t1 - t0) * (1.0 - u as f32));
    }
    for (t, b) in by_chunk(&out, |x, z| when.get(&(x, z)).copied().unwrap_or(t1)) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// Round a hole over cells i0..i1, from `t0`: a breach's rim of thrown earth (up to `rim_h` high at its edge, none at
/// `h.rim`) heaped, everything standing out to `fell` swept off (the trees marked to lie felled), never into another
/// hole (`other`). The sweep goes out as the eruption's blast does, the heap lands after it.
#[allow(clippy::too_many_arguments)]
pub(super) fn heap(q: &mut Plan, site: &mut Site, h: &Hole, rim_h: f64, fell: f64, t0: f32, i0: usize, i1: usize, other: &dyn Fn(i32, i32) -> bool) {
    crate::trace("we heap begins");
    let mut out = Blocks { clear_of_player: true, ..Default::default() };
    let mut when: FxMap<(i32, i32), f32> = FxMap::default();
    crate::meter::spend(60 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    let reach = h.rim.max(fell);
    for i in i0..i1.min(site.cells.len()) {
        let (x, z) = site.cols[i];
        let cell = site.cells[i];
        if !cell.c.known || cell.c.lava || cell.c.fluid || cell.flag & DUG != 0 {
            continue;
        }
        crate::meter::spend(AT_COST);
        let (r, a, e) = h.at(x, z);
        let inner = h.fedge(a).max(e + 3.0);
        if r < inner || r >= reach || other(x, z) {
            continue;
        }
        crate::meter::spend(1_200);
        let u = (r - inner) / (h.rim - inner).max(1.0);
        let mut g = cell.g;
        if rim_h > 0.0 && u < 1.0 && !site.wet_near(x, z) {
            let n = vnoise(f64::from(x), f64::from(z), 5.0, h.seed ^ 0x33);
            let hh = (rim_h * (1.0 - u).powf(2.2) + 1.2 * (n - 0.5) * (1.0 - u)).round() as i32;
            if hh > 0 {
                // (its body one earth, its top another: two runs a column)
                if hh > 1 {
                    out.run(x, z, g + 1, g + hh - 1, payload::ejecta(x, g + 1, z, h.seed));
                }
                out.run(x, z, g + hh, g + hh, payload::ejecta(x, g + hh, z, h.seed));
                g += hh;
                site.cells[i].flag |= HEAPED;
            }
        }
        let mut top = cell.top.max(g);
        if r < fell && top > g {
            // (a felled tree's stump of one or two left, unless earth was heaped over it)
            let keep = if cell.c.trunk >= 3 && g == cell.g { g + 1 + (mh((x * 31 + z * 17) as u32, h.seed, 0x81) * 2.0) as i32 } else { g };
            if top > keep {
                out.run(x, z, keep + 1, top, "minecraft:air");
            }
            top = keep;
            site.cells[i].flag |= CLEARED;
            if cell.c.trunk >= 3 && cell.flag & FELLED == 0 {
                site.cells[i].flag |= FELLED | FELL_NOW;
            }
        }
        site.cells[i].g = g;
        site.cells[i].top = top.max(g);
        // (swept as the blast reaches it; the earth lands a little after)
        let tw = t0 + ((r - inner) / 150.0) as f32;
        when.insert((x, z), if g > cell.g { tw + 0.5 + ((r - inner) / 120.0) as f32 } else { tw });
    }
    for (t, b) in by_chunk(&out, |x, z| when.get(&(x, z)).copied().unwrap_or(t0)) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// The trees swept off round a hole (over cells i0..i1), lying on the land pointing away from it, their crowns
/// crushed round their ends, each down once the sweep has passed where it lies.
pub(super) fn felled(q: &mut Plan, site: &mut Site, h: &Hole, t0: f32, i0: usize, i1: usize) {
    crate::trace("we felled begins");
    let mut out = Blocks { clear_of_player: true, ..Default::default() };
    crate::meter::spend(15 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    for i in i0..i1.min(site.cells.len()) {
        if site.cells[i].flag & FELL_NOW == 0 {
            continue;
        }
        site.cells[i].flag &= !FELL_NOW;
        crate::meter::spend(2_500);
        let (x, z) = site.cols[i];
        let c = site.cells[i].c;
        let (_, a, _) = h.at(x, z);
        let (dx, dz) = (a.cos(), a.sin());
        let (sx, sz, log) = if dx.abs() > dz.abs() { (dx.signum() as i32, 0, LOG_X[c.wood as usize]) } else { (0, dz.signum() as i32, LOG_Z[c.wood as usize]) };
        let want = (i32::from(c.trunk) - 1).clamp(2, 3 + (mh((x * 7 + z * 13) as u32, h.seed, 0x82) * 4.0) as i32);
        let mut gy = site.cells[i].g;
        let mut last = None;
        for k in 1..=want {
            let (lx, lz) = (x + sx * k, z + sz * k);
            let Some(j) = site.known(lx, lz) else { break };
            if !site.open(j) || (site.cells[j].g - gy).abs() > 1 || site.wet_near(lx, lz) {
                break;
            }
            let g2 = site.cells[j].g;
            out.run(lx, lz, g2 + 1, g2 + 1, log);
            site.cells[j].top = g2 + 1;
            site.cells[j].flag |= LAID;
            gy = g2;
            last = Some((lx, lz));
        }
        if let (Some((lx, lz)), true) = (last, c.leaves != 255) {
            for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx)] {
                let (fx, fz) = (lx + ox, lz + oz);
                let Some(j) = site.known(fx, fz) else { continue };
                if site.open(j) && (site.cells[j].g - gy).abs() <= 1 && !site.wet_near(fx, fz) {
                    let g2 = site.cells[j].g;
                    out.run(fx, fz, g2 + 1, g2 + 1, LEAVES[c.leaves as usize]);
                    site.cells[j].top = g2 + 1;
                    site.cells[j].flag |= LAID;
                }
            }
        }
    }
    for (t, b) in by_chunk_at(&out, |x, z| t0 + 0.4 + (h.at(x, z).0 / 150.0) as f32) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// What a hole's work left hanging round rows z0..=z1 of its site's square, `reach` round its middle (leaves of a tree
/// whose trunk went, plants whose ground went), at `t`, once it is in.
pub(super) fn tidy_rows(q: &mut Plan, site: &Site, h: &Hole, reach: f64, z0: i32, z1: i32, t: f32) {
    crate::trace("we tidy_rows begins");
    let rr = reach.ceil() as i32 + 2;
    let ix = h.cx.floor() as i32;
    let col = |x: i32, z: i32| -> Col {
        match site.idx(x, z) {
            Some(i) if site.cells[i].flag & (CLEARED | DUG) != 0 && !site.cells[i].c.fluid => Col::Cleared,
            _ => Col::Kept,
        }
    };
    let b = tidy(ix - rr, z0, ix + rr, z1, 32, -1, col);
    // (from the middle out over a second: each of its runs looks some thirty blocks up a column)
    for (t, b) in by_chunk_at(&b, |x, z| t + (h.at(x, z).0 / reach.max(1.0)) as f32) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// The blocks a breach throws out of its hole (real falling blocks, some landing as blocks, the rest breaking up where
/// they land, none dropping an item) and trees torn apart (a few logs and leaves, each block on its own way, breaking
/// up where they land), from `t0`: `n` blocks, `trees` trees.
pub(super) fn thrown(q: &mut Plan, site: &Site, h: &Hole, t0: f32, n: usize, trees: usize) {
    crate::trace("we thrown begins");
    let mut rng = Rng::new(u64::from(h.seed) ^ 0x7e57_0001);
    let mut made = 0;
    for _ in 0..n * 3 {
        if made >= n {
            break;
        }
        let r = h.r * 0.95 * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = (h.cx + a.cos() * r, h.cz + a.sin() * r);
        let (c, g) = match site.idx(x.floor() as i32, z.floor() as i32) {
            Some(i) if site.cells[i].c.known => (site.cells[i].c, site.cells[i].c.g),
            _ => (Column { ground: 2, ..Default::default() }, h.g),
        };
        if c.fluid {
            continue;
        }
        let deep = rng.next();
        let blk = match (c.ground, deep) {
            (1, d) if d < 0.35 => "minecraft:grass_block",
            (1 | 2, d) if d < 0.55 => "minecraft:dirt",
            (_, d) if d < 0.68 => "minecraft:coarse_dirt",
            (_, d) if d < 0.8 => "minecraft:stone",
            (_, d) if d < 0.88 => "minecraft:deepslate",
            (_, d) if d < 0.95 => "minecraft:tuff",
            _ => "minecraft:sculk",
        };
        // (most thrown out a hundred or so, a share far, out to ~250)
        let far = rng.next() < 0.18;
        let hs = if far { 4.5 + 2.5 * rng.next() } else { 0.6 + 3.0 * rng.next().powf(1.3) };
        let vy = if far { 2.4 + 1.0 * rng.next() } else { 1.0 + 1.8 * rng.next() };
        let ang = a + rng.uniform(-0.35, 0.35);
        let y = f64::from(g) + 2.0 + 4.0 * rng.next();
        let t = t0 + 0.05 + 0.7 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((
            t,
            Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{:.3}d,{vy:.3}d,{:.3}d]}}", ang.cos() * hs, ang.sin() * hs)),
        ));
        made += 1;
    }
    // (whole trees: those that stood over the hole, trunk and crown thrown as one)
    let near = disc(h.cx, h.cz, h.r * 1.3 + 6.0);
    crate::meter::spend(150 * near.len() as u64);
    let mut stood: Vec<usize> = near
        .into_iter()
        .filter_map(|(x, z)| site.known(x, z))
        .filter(|&i| {
            let c = &site.cells[i].c;
            c.trunk >= 4 && {
                let (r, _, e) = h.at(site.cols[i].0, site.cols[i].1);
                r < e + 6.0
            }
        })
        .collect();
    // (spread round the hole, not all from one side)
    stood.sort_by_key(|&i| (mh(i as u32, h.seed, 0x7a) * 1e6) as u64);
    for &i in stood.iter().take(trees) {
        let (x, z) = site.cols[i];
        let c = site.cells[i].c;
        let (_, a, _) = h.at(x, z);
        let hs = 1.6 + 1.6 * rng.next();
        let vy = 1.6 + 0.8 * rng.next();
        let (vx, vz) = (a.cos() * hs, a.sin() * hs);
        let t = t0 + 0.15 + 0.4 * rng.next() as f32;
        let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        let base = f64::from(c.g) + 3.0;
        let n = i32::from(c.trunk).min(7);
        // (torn apart as it goes: a few logs and a clump or two of its leaves, each block on its own way and time, never
        // the crown thrown whole: a flat crown flying in one piece reads as a slab hanging in the air)
        let mut put = |dx: f64, dy: f64, dz: f64, blk: &str, rng: &mut Rng| {
            let (jx, jy, jz) = (rng.uniform(-0.45, 0.45), rng.uniform(-0.35, 0.35), rng.uniform(-0.45, 0.45));
            let tt = t + 0.12 * rng.next() as f32;
            q.ev.push((tt, Act::Cmd(format!("summon minecraft:falling_block {:.2} {:.2} {:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b,CancelDrop:1b,Motion:[{:.3}d,{:.3}d,{:.3}d]}}", fx + dx, base + dy, fz + dz, vx + jx, vy + jy, vz + jz))));
        };
        for k in 0..n.min(3) {
            put(0.0, f64::from(k), 0.0, LOG_Y[c.wood as usize], &mut rng);
        }
        if c.leaves != 255 {
            let leaf = LEAVES[c.leaves as usize];
            let top = f64::from(n);
            for (dx, dy, dz) in [(0.0, 0.0, 0.0), (1.0, -1.0, 0.0)] {
                put(dx, top + dy, dz, leaf, &mut rng);
            }
        }
    }
}

/// Sculk creeping out from a hole over cells i0..i1 (onto its rim and the ground round it, patchier further out, veins
/// past the patches), from `t0` over `secs`.
#[allow(clippy::too_many_arguments)]
pub(super) fn sculk(q: &mut Plan, site: &mut Site, h: &Hole, t0: f32, secs: f32, i0: usize, i1: usize) {
    crate::trace("we sculk begins");
    let mut out = Blocks { clear_of_player: true, ..Default::default() };
    let mut when: FxMap<(i32, i32), f32> = FxMap::default();
    const REACH: f64 = 42.0;
    crate::meter::spend(60 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    for i in i0..i1.min(site.cells.len()) {
        let (x, z) = site.cols[i];
        let cell = site.cells[i];
        if !cell.c.known || cell.c.fluid || cell.flag & (LAID | DUG) != 0 || cell.top != cell.g || !h.near(x, z, h.reach_max() + REACH) {
            continue;
        }
        let (r, a, e) = h.at(x, z);
        let inner = h.fedge(a).max(e + 3.0);
        let u = (r - inner) / REACH;
        if !(0.0..1.0).contains(&u) {
            continue;
        }
        crate::meter::spend(500);
        let n = vnoise(f64::from(x), f64::from(z), 4.0, h.seed ^ 0x5c);
        let p = 0.75 * (1.0 - u).powf(1.5);
        if n < p {
            out.run(x, z, cell.g, cell.g, "minecraft:sculk");
        } else if n < p + 0.1 {
            out.put(x, z, cell.g + 1, cell.g + 1, "minecraft:sculk_vein[down=true]", Some("minecraft:air"), false);
        } else {
            continue;
        }
        when.insert((x, z), t0 + secs * smooth(u + 0.15 * (n - 0.5)) as f32);
    }
    for (t, b) in by_chunk(&out, |x, z| when.get(&(x, z)).copied().unwrap_or(t0)) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

// ---- a trench ------------------------------------------------------------------------------------------------------
/// A tunnelled stretch: from and to (world, level), the seed, when its rings sink from the first to the last.
#[derive(Clone, Copy, Debug)]
pub(super) struct Trench {
    pub a: [f64; 2],
    pub b: [f64; 2],
    pub seed: u32,
    pub t0: f32,
    pub t1: f32,
    pub rings: u32,
}
impl Trench {
    pub fn len(&self) -> f64 {
        (self.b[0] - self.a[0]).hyp(self.b[1] - self.a[1])
    }
    /// Column (x, z): how far along (0 to len), how far across (signed).
    pub fn at(&self, x: i32, z: i32) -> (f64, f64) {
        let l = self.len().max(1e-6);
        let (dx, dz) = ((self.b[0] - self.a[0]) / l, (self.b[1] - self.a[1]) / l);
        let (px, pz) = (f64::from(x) + 0.5 - self.a[0], f64::from(z) + 0.5 - self.a[1]);
        (px * dx + pz * dz, -px * dz + pz * dx)
    }
    fn half(&self, u: f64, x: i32, z: i32) -> f64 {
        TR_W * (1.0 + 0.12 * (u / 23.0 + f64::from(self.seed % 97)).sin() + 0.16 * (vnoise(f64::from(x), f64::from(z), 14.0, self.seed ^ 0x21) - 0.5))
    }
    /// The ring a place `u` along is in, and when it sinks.
    pub fn ring(&self, u: f64) -> (u32, f32) {
        let k = ((u / self.len().max(1.0)) * f64::from(self.rings)).floor().clamp(0.0, f64::from(self.rings - 1)) as u32;
        (k, self.t0 + (self.t1 - self.t0) * k as f32 / (self.rings - 1).max(1) as f32)
    }
    /// Ring `k`'s middle (world, level).
    pub fn ring_mid(&self, k: u32) -> [f64; 2] {
        let f = (f64::from(k) + 0.5) / f64::from(self.rings);
        [self.a[0] + (self.b[0] - self.a[0]) * f, self.a[1] + (self.b[1] - self.a[1]) * f]
    }
}

/// How deep the trench goes at column (x, z), none outside it.
fn trench_depth(tr: &Trench, x: i32, z: i32) -> Option<i32> {
    let (u, o) = tr.at(x, z);
    let w = tr.half(u, x, z);
    if o.abs() >= w {
        return None;
    }
    let n = vnoise(f64::from(x), f64::from(z), 9.0, tr.seed ^ 0x23);
    let d = TR_D * (1.0 - (o / w).powi(2)).powf(0.7) * (0.8 + 0.4 * n) + 1.5 * (mh((x * 7 + z * 3) as u32, tr.seed, 0x24) - 0.5);
    let d = d.round() as i32;
    (d >= 1).then_some(d)
}

/// The trench's floor over cells i0..i1 of its corridor (worked out ahead: the ring edits and the laid trees read it).
pub(super) fn trench_floors(site: &mut Site, tr: &Trench, i0: usize, i1: usize, other: &dyn Fn(i32, i32) -> bool) {
    crate::trace("we trench_floors begins");
    crate::meter::spend(900 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    for i in i0..i1.min(site.cells.len()) {
        let (x, z) = site.cols[i];
        let cell = site.cells[i];
        if !cell.c.known || cell.c.fluid || cell.c.lava || site.wet_near(x, z) {
            continue;
        }
        if let Some(d) = trench_depth(tr, x, z) {
            if other(x, z) {
                continue;
            }
            site.cells[i].g = cell.g - d;
            site.cells[i].flag |= TRENCH;
        }
    }
}

/// The trench's ring edits over cells i0..i1: each column sunk to its floor as its ring goes (everything over it gone,
/// its floor rubble, the lava under it sealed), the trees that stood on it laid on its floor along it.
pub(super) fn trench_rings(q: &mut Plan, site: &mut Site, tr: &Trench, i0: usize, i1: usize) {
    crate::trace("we trench_rings begins");
    let mut out = Blocks { clear_of_player: true, ..Default::default() };
    crate::meter::spend(900 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    let l = tr.len().max(1.0);
    let (dx, dz) = ((tr.b[0] - tr.a[0]) / l, (tr.b[1] - tr.a[1]) / l);
    for i in i0..i1.min(site.cells.len()) {
        let cell = site.cells[i];
        if cell.flag & TRENCH == 0 {
            continue;
        }
        let (x, z) = site.cols[i];
        let f = cell.g;
        let deep = f64::from(cell.c.g - f) / TR_D;
        out.run(x, z, f + 1, cell.top.max(cell.c.g) + 4, "minecraft:air");
        out.run(x, z, f - 1, f, rubble(x, f, z, deep, tr.seed));
        out.put(x, z, f - 4, f - 2, "minecraft:stone", Some("minecraft:lava"), false);
        site.cells[i].top = f;
        // (a tree that stood here, laid along the trench on its floor)
        if cell.c.trunk >= 3 && cell.flag & FELLED == 0 {
            site.cells[i].flag |= FELLED;
            let s = if mh((x * 5 + z * 11) as u32, tr.seed, 0x25) < 0.5 { 1 } else { -1 };
            let (sx, sz, log) = if dx.abs() > dz.abs() { ((dx.signum() as i32) * s, 0, LOG_X[cell.c.wood as usize]) } else { (0, (dz.signum() as i32) * s, LOG_Z[cell.c.wood as usize]) };
            for k in 1..=i32::from(cell.c.trunk).min(5) {
                let (lx, lz) = (x + sx * k, z + sz * k);
                let Some(j) = site.idx(lx, lz) else { break };
                let cj = site.cells[j];
                if cj.flag & TRENCH == 0 || cj.flag & LAID != 0 || (cj.g - f).abs() > 2 {
                    break;
                }
                out.run(lx, lz, cj.g + 1, cj.g + 1, log);
                site.cells[j].flag |= LAID;
                site.cells[j].top = cj.g + 1;
            }
        }
    }
    // (a laid log lies in its own column's ring: in after that column's air, both being one edit)
    for (t, b) in out.split_by(|x, z| tr.ring(tr.at(x, z).0).1) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

// ---- the wormsign: the land heaving over the head ----------------------------------------------------------------
/// Half the strip the land heaves in over the head as it runs under (22 wide); how far from the player the crest throws
/// its most (`BUCK_NEAR`), thins to a few (`BUCK_SEEN`), and is only hinted at, a block every other tick (`BUCK_HINT`).
pub(super) const BUCK_W: f64 = 11.0;
pub(super) const BUCK_NEAR: f64 = 150.0;
pub(super) const BUCK_SEEN: f64 = 450.0;
pub(super) const BUCK_HINT: f64 = 700.0;
/// Where the strip ends short of its breach's middle: inside the hole's edge (a breach is 40 across its middle, give or
/// take 16%), so the scar runs into the rim and the dig takes the rest; the crest at its most violent over the last
/// `BUCK_RAGE` before it.
pub(super) const BUCK_END: f64 = 28.0;
const BUCK_RAGE: f64 = 60.0;
/// The most blocks the crest throws a tick (near the player, by the rim).
pub(super) const BUCK_MOST: usize = 24;
/// What the strip is left as, and what it throws.
const BUCK_GROUND: [&str; 6] = ["minecraft:coarse_dirt", "minecraft:rooted_dirt", "minecraft:gravel", "minecraft:coarse_dirt", "minecraft:dirt", "minecraft:coarse_dirt"];
const BUCK_THROWN: [&str; 6] = ["minecraft:coarse_dirt", "minecraft:rooted_dirt", "minecraft:dirt", "minecraft:gravel", "minecraft:cobblestone", "minecraft:grass_block"];

/// A run under the land: its line (world, level: where it starts, W0 or the last dive, to its breach), when the head is
/// how far along it (a tick apart, from the run's first tick to its breach: `along`), the seed.
pub(super) struct Buck<'a> {
    pub a: [f64; 2],
    pub b: [f64; 2],
    pub along: &'a [(f32, f64)],
    pub seed: u32,
}
impl Buck<'_> {
    fn len(&self) -> f64 {
        (self.b[0] - self.a[0]).hyp(self.b[1] - self.a[1])
    }
    fn way(&self) -> ([f64; 2], [f64; 2]) {
        let l = self.len().max(1e-6);
        let d = [(self.b[0] - self.a[0]) / l, (self.b[1] - self.a[1]) / l];
        (d, [-d[1], d[0]])
    }
    /// When the head passes under `u` along the line (none: it never gets there before the breach).
    fn t_at(&self, u: f64) -> Option<f32> {
        let i = self.along.partition_point(|x| x.1 < u);
        self.along.get(i).map(|x| x.0)
    }
}

/// How many blocks the crest throws a block of its way, `d` from the player and `left` short of its strip's end.
pub(super) fn buck_density(d: f64, left: f64) -> f64 {
    let n = if d <= BUCK_NEAR {
        3.0
    } else if d <= BUCK_SEEN {
        3.0 - 2.4 * (d - BUCK_NEAR) / (BUCK_SEEN - BUCK_NEAR)
    } else if d <= BUCK_HINT {
        0.25
    } else {
        0.0
    };
    // (at its most violent as it runs into the breach's rim, wherever that is in sight: the eruption's to be watched)
    let rage = (1.0 - left / BUCK_RAGE).clamp(0.0, 1.0);
    let n = if rage > 0.0 && d <= BUCK_HINT { n.max(3.0) } else { n };
    n * (1.0 + 1.2 * rage)
}

/// The crest of earth bursting up just over the head as it passes, ticks `j0..j1` of its run (`along`'s): blocks thrown
/// 3 to 8 up and out to the sides from a few blocks behind the head's place to a few ahead, as many as the player can
/// see (`buck_density`, at most BUCK_MOST a tick), falling back over the strip (some landing as blocks, the rest breaking up), up to the rim.
pub(super) fn buck_throw(q: &mut Plan, bk: &Buck, me: [f64; 3], j0: usize, j1: usize) {
    let (d, n) = bk.way();
    let stop = bk.len() - BUCK_END;
    let mut rng = Rng::new(u64::from(bk.seed) ^ 0xb0c4 ^ ((j0 as u64) << 20));
    let (mut acc, mut prev) = (0.0f64, j0.checked_sub(1).and_then(|p| bk.along.get(p)).map(|x| x.1));
    for &(t, u) in &bk.along[j0.min(bk.along.len())..j1.min(bk.along.len())] {
        let du = (u - prev.unwrap_or(u)).max(0.0);
        prev = Some(u);
        if !(0.0..stop).contains(&u) {
            continue;
        }
        let (hx, hz) = (bk.a[0] + d[0] * u, bk.a[1] + d[1] * u);
        // (lumpy along the line: the crest swells and slackens)
        let swell = 0.65 + 0.7 * vnoise(u / 14.0, 0.0, 1.0, bk.seed ^ 0xb1);
        // (as many a block of the way the head came this tick)
        acc += buck_density((hx - me[0]).hyp(hz - me[2]), stop - u) * swell * du;
        let k = (acc.floor() as usize).min(BUCK_MOST);
        acc -= acc.floor();
        crate::meter::spend(2_500 * k as u64);
        for _ in 0..k {
            // (most over the line, fewer out at the strip's edges)
            let o = BUCK_W * 0.95 * (rng.uniform(-1.0, 1.0) + rng.uniform(-1.0, 1.0)) * 0.5;
            let j = rng.uniform(-3.0, 6.0);
            let (x, z) = (bk.a[0] + d[0] * (u + j) + n[0] * o, bk.a[1] + d[1] * (u + j) + n[1] * o);
            let blk = *rng.pick(&BUCK_THROWN);
            // (3 to 8 up: a block's rise is v*v/0.08 or so)
            let vy = rng.uniform(0.5, 0.8);
            let side = (o / BUCK_W) * rng.uniform(0.08, 0.2);
            let fwd = rng.uniform(-0.02, 0.1);
            let (mx, mz) = (n[0] * side + d[0] * fwd, n[1] * side + d[1] * fwd);
            let keep = if rng.next() < 0.3 { "" } else { ",CancelDrop:1b" };
            q.at(
                t + 0.05 * rng.next() as f32,
                surf(x.floor() as i32, z.floor() as i32, &format!("summon minecraft:falling_block ~0.5 ~0.2 ~0.5 {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{mx:.3}d,{vy:.3}d,{mz:.3}d]}}")),
            );
        }
    }
}

/// The scar the strip is left as, along `u0..u1` of the line: turned earth (coarse dirt, rooted dirt, dirt, gravel)
/// over most of its middle, patchier towards its edges (a noise, not a band), the odd top block gone a step down and
/// the odd clod a step up, the grass and flowers on it gone; each where the head has just passed. Surface-relative runs
/// (grass and dirt only turned, plants only cleared): no land read needed.
pub(super) fn buck_ground(q: &mut Plan, bk: &Buck, u0: f64, u1: f64) {
    let (d, n) = bk.way();
    let stop = bk.len() - BUCK_END;
    let mut out = Blocks::default();
    let mut seen: std::collections::HashSet<(i32, i32)> = std::collections::HashSet::new();
    let mut u = u0.max(0.0);
    while u < u1.min(stop) {
        // (the strip's edges wander)
        let wob = 1.0 + 0.18 * (vnoise(u / 11.0, 3.0, 1.0, bk.seed ^ 0xb6) - 0.5);
        let half = BUCK_W * wob;
        let mut o = -half;
        while o <= half {
            let (x, z) = ((bk.a[0] + d[0] * u + n[0] * o).floor() as i32, (bk.a[1] + d[1] * u + n[1] * o).floor() as i32);
            let edge = (o.abs() / half).min(1.0);
            o += 0.8;
            if !seen.insert((x, z)) {
                continue;
            }
            crate::meter::spend(900);
            let m = vnoise(f64::from(x), f64::from(z), 3.0, bk.seed ^ 0xb2);
            let h = mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, bk.seed, 0xb3);
            // (turned over the middle; at the edges only where the noise says)
            if m < 0.12 + 0.75 * edge * edge {
                continue;
            }
            let centre = 1.0 - edge;
            let blk = BUCK_GROUND[((m * 97.0) as usize + (h * 13.0) as usize) % BUCK_GROUND.len()];
            if h < 0.07 * centre {
                // (a step down: the top block gone, what was under it turned)
                out.put(x, z, -1, -1, "minecraft:air", Some("minecraft:grass_block"), true);
                out.put(x, z, -2, -2, blk, Some("minecraft:dirt"), true);
            } else {
                out.put(x, z, -1, -1, blk, Some("minecraft:grass_block"), true);
                if h > 1.0 - 0.06 * centre {
                    // (a clod a step up, where grass grew on it)
                    out.put(x, z, 0, 0, BUCK_GROUND[(h * 61.0) as usize % BUCK_GROUND.len()], Some("minecraft:short_grass"), true);
                }
            }
            out.put(x, z, 0, 1, "minecraft:air", Some("#minecraft:replaceable"), true);
        }
        u += 0.8;
    }
    for (t, b) in by_chunk(&out, |x, z| {
        let along = (f64::from(x) + 0.5 - bk.a[0]) * d[0] + (f64::from(z) + 0.5 - bk.a[1]) * d[1];
        bk.t_at(along).unwrap_or(0.0) + 0.2
    }) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// The trees in or beside the strip over cells i0..i1 of its site (read along it): every one in it toppled as the head
/// passes (about half of those just beside it), lying on the land away from the line (their crowns crushed at their ends).
pub(super) fn buck_trees(q: &mut Plan, site: &mut Site, bk: &Buck, i0: usize, i1: usize) {
    let (d, n) = bk.way();
    let mut out = Blocks { clear_of_player: true, ..Default::default() };
    let mut when: FxMap<(i32, i32), f32> = FxMap::default();
    crate::meter::spend(30 * (i1.min(site.cells.len()).saturating_sub(i0)) as u64);
    for i in i0..i1.min(site.cells.len()) {
        let c = site.cells[i];
        if !c.c.known || c.c.trunk < 3 || c.flag & FELLED != 0 {
            continue;
        }
        let (x, z) = site.cols[i];
        let (px, pz) = (f64::from(x) + 0.5 - bk.a[0], f64::from(z) + 0.5 - bk.a[1]);
        let (u, o) = (px * d[0] + pz * d[1], px * n[0] + pz * n[1]);
        // (every tree in the strip, and about half of those just beside it)
        if o.abs() > BUCK_W + 2.0 || u > bk.len() - BUCK_END {
            continue;
        }
        let Some(t) = bk.t_at(u) else { continue };
        crate::meter::spend(4_000);
        site.cells[i].flag |= FELLED;
        // (the tree gone from where it stood, its crown with it)
        out.run(x, z, c.g + 1, c.top.max(c.g + 1), "minecraft:air");
        for (ox, oz) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1), (2, 0), (-2, 0), (0, 2), (0, -2)] {
            out.put(x + ox, z + oz, c.g + 2, c.g + 14, "minecraft:air", Some(LEAF_NAMES_ALL), false);
            when.entry((x + ox, z + oz)).or_insert(t + 0.4);
        }
        when.insert((x, z), t + 0.4);
        // (lying away from the line: along x or z, whichever is nearer that way)
        let away = if o >= 0.0 { n } else { [-n[0], -n[1]] };
        let (sx, sz, log) = if away[0].abs() > away[1].abs() { (away[0].signum() as i32, 0, LOG_X[c.c.wood as usize]) } else { (0, away[1].signum() as i32, LOG_Z[c.c.wood as usize]) };
        let mut gy = c.g;
        let mut last = None;
        for k in 1..=i32::from(c.c.trunk).min(6) {
            let (lx, lz) = (x + sx * k, z + sz * k);
            let Some(j) = site.known(lx, lz) else { break };
            if !site.open(j) || (site.cells[j].g - gy).abs() > 1 {
                break;
            }
            let g2 = site.cells[j].g;
            out.run(lx, lz, g2 + 1, g2 + 1, log);
            site.cells[j].top = g2 + 1;
            site.cells[j].flag |= LAID;
            when.insert((lx, lz), t + 0.9);
            gy = g2;
            last = Some((lx, lz));
        }
        if let (Some((lx, lz)), true) = (last, c.c.leaves != 255) {
            for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx)] {
                let (fx, fz) = (lx + ox, lz + oz);
                let Some(j) = site.known(fx, fz) else { continue };
                if site.open(j) && (site.cells[j].g - gy).abs() <= 1 {
                    let g2 = site.cells[j].g;
                    out.run(fx, fz, g2 + 1, g2 + 1, LEAVES[c.c.leaves as usize]);
                    site.cells[j].top = g2 + 1;
                    site.cells[j].flag |= LAID;
                    when.insert((fx, fz), t + 0.9);
                }
            }
        }
    }
    for (t, b) in out.split_by(|x, z| when.get(&(x, z)).copied().unwrap_or(f32::MAX.min(1.0e4))) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}
/// Leaves of any wood (a tag).
const LEAF_NAMES_ALL: &str = "#minecraft:leaves";

#[cfg(test)]
pub(super) mod tests {
    use super::*;

    /// A wood on rolling land (its ground about 64), oaks now and then, a pond round (300, 300).
    pub fn ground_h(x: i32, z: i32) -> i32 {
        (64.0 + 3.0 * (f64::from(x) * 0.05).sin() * (f64::from(z) * 0.04).cos()).round() as i32
    }
    pub fn tree(x: i32, z: i32) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 0.985
    }
    pub fn pond(x: i32, z: i32) -> bool {
        (f64::from(x) - 300.0).hyp(f64::from(z) - 300.0) < 12.0
    }
    pub fn column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let g = ground_h(x, z);
        let wet = pond(x, z);
        let t = tree(x, z) && !wet;
        let block = |y: i32| -> &'static str {
            if y < g - 3 {
                "minecraft:stone"
            } else if y < g {
                "minecraft:dirt"
            } else if y == g {
                if wet { "minecraft:sand" } else { "minecraft:grass_block" }
            } else if wet && y <= g + 2 {
                "minecraft:water"
            } else if t && y <= g + 6 {
                "minecraft:oak_log"
            } else if t && y <= g + 8 && y >= g + 4 {
                "minecraft:oak_leaves"
            } else {
                "minecraft:air"
            }
        };
        let top = if t { g + 9 } else if wet { g + 3 } else { g + 1 };
        Some((top, (top - below as i32..top + above as i32).map(block).collect()))
    }

    fn site_of(cols: Vec<(i32, i32)>) -> Site {
        let mut s = Site::new(cols.clone());
        let tag = crate::columns::new_tag();
        crate::columns::test_answer(tag, &cols, PL_BELOW, PL_ABOVE, &|x, z| column(x, z, PL_BELOW, PL_ABOVE));
        let a = crate::columns::take(tag).unwrap();
        payload::take_in_each(&a, |x, z, c| s.put(x, z, c), |_, _| {});
        s
    }
    fn plan() -> Plan {
        Plan { laser: &crate::lasers::WORLD_EATER, ev: Vec::new(), rng: Rng::new(1), bx: 0, by: 64, bz: 0 }
    }
    fn fills(p: &Plan) -> Vec<String> {
        p.ev.iter().filter_map(|(_, a)| if let Act::Blocks(b) = a { Some(b.as_fills()) } else { None }).flatten().collect()
    }

    #[test]
    fn we_hole_goes_to_bedrock_with_a_dressed_wall_and_a_funnel() {
        let h = Hole::new(0.5, 0.5, 64, 45.0, 60.0, 9);
        let mut s = site_of(disc(0.5, 0.5, SITE_R));
        let mut p = plan();
        let n = s.cells.len();
        dig(&mut p, &mut s, &h, -59, 19.0, 19.9, 0, n, None);
        funnel(&mut p, &mut s, &h, 21.0, 24.0, 0, n);
        let f = fills(&p);
        assert!(f.iter().any(|f| f.starts_with("fill 0 -58 0 0 ") && f.contains("air")));
        let dug = s.cells.iter().filter(|c| c.g == -59).count() as f64;
        let want = PI * 45.0 * 45.0;
        assert!(dug > 0.8 * want && dug < 1.25 * want, "{dug}");
        assert!(f.iter().any(|f| f.contains("replace #minecraft:base_stone_overworld") && f.contains("blackstone")));
        assert!(f.iter().any(|f| f.contains("minecraft:tuff replace minecraft:water")));
        let slope: Vec<i32> = s.cells.iter().filter(|c| c.flag & DUG != 0 && c.g > -59).map(|c| c.c.g - c.g).collect();
        assert!(slope.iter().max().copied().unwrap_or(0) >= 20 && slope.iter().min().copied().unwrap_or(99) <= 3, "{slope:?}");
        let times: Vec<f32> = p.ev.iter().map(|e| e.0).collect();
        assert!(times.iter().cloned().fold(f32::MAX, f32::min) >= 19.0 && times.iter().cloned().fold(0.0, f32::max) <= 24.1);
    }

    #[test]
    fn we_bite_in_a_lake_leaves_no_water_standing_by_it() {
        // (a bite 30 across with its funnel to 50, its edge cutting through the pond round (300, 300))
        let h = Hole::new(270.5, 300.5, 64, 30.0, 50.0, 4);
        let mut s = site_of(disc(270.5, 300.5, SITE_R));
        let mut p = plan();
        let n = s.cells.len();
        dig(&mut p, &mut s, &h, -59, 19.0, 19.9, 0, n, None);
        funnel(&mut p, &mut s, &h, 21.0, 24.0, 0, n);
        // (every column of the pond within the funnel's reach and a dam's width past it: drained, dug or dammed)
        let mut touched: std::collections::HashSet<(i32, i32)> = Default::default();
        for (_, a) in &p.ev {
            if let Act::Blocks(b) = a {
                for r in &b.runs {
                    touched.insert((r.x, r.z));
                }
            }
        }
        let mut wet = 0;
        for x in 285..=315 {
            for z in 285..=315 {
                let (r, a, _) = h.at(x, z);
                if pond(x, z) && r < h.fedge(a) + DAM - 0.5 {
                    wet += 1;
                    assert!(touched.contains(&(x, z)), "the pond's water left standing at {x} {z} ({r:.1} out)");
                }
            }
        }
        assert!(wet > 20, "{wet}");
        let f = fills(&p);
        assert!(f.iter().any(|f| f.contains("minecraft:tuff replace minecraft:water")), "the lake dammed");
    }

    #[test]
    fn we_breach_heaps_its_rim_and_fells_the_trees_pointing_away() {
        let h = Hole::new(0.5, 0.5, 64, 40.0, 40.0, 3);
        let mut s = site_of(disc(0.5, 0.5, SITE_R));
        let mut p = plan();
        let n = s.cells.len();
        dig(&mut p, &mut s, &h, -59, 9.0, 9.6, 0, n, None);
        heap(&mut p, &mut s, &h, 6.0, 120.0, 9.1, 0, n, &|_, _| false);
        felled(&mut p, &mut s, &h, 9.1, 0, n);
        thrown(&mut p, &s, &h, 9.0, 100, 5);
        let f = fills(&p);
        let logs = f.iter().filter(|f| f.contains("_log[axis=")).count();
        assert!(logs > 20, "{logs}");
        // (each felled log lies pointing away from the hole: along x where it is more east or west of it than north or south)
        let along = f.iter()
            .filter(|f| f.contains("_log[axis="))
            .filter(|l| {
                let w: Vec<f64> = l.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap()).collect();
                l.contains("axis=x") == (w[0].abs() > w[2].abs())
            })
            .count();
        assert!(along * 10 >= logs * 9, "{along} of {logs} logs pointing away");
        let heaped = s.cells.iter().filter(|c| c.flag & HEAPED != 0).count();
        assert!(heaped > 5000, "{heaped}");
        let high = s.cells.iter().map(|c| c.g - c.c.g).max().unwrap();
        assert!((4..=8).contains(&high), "{high}");
        let summons = p.ev.iter().filter(|(_, a)| matches!(a, Act::Cmd(c) if c.starts_with("summon minecraft:falling_block"))).count();
        assert!(summons >= 100, "{summons}");
    }

    #[test]
    fn we_trench_sinks_ring_by_ring_and_leaves_the_pond() {
        let tr = Trench { a: [200.0, 200.0], b: [420.0, 400.0], seed: 4, t0: 31.0, t1: 39.0, rings: 12 };
        let mut s = site_of(corridor([200.0, 200.0], [420.0, 400.0], TR_W * 1.35, |_, _| false));
        let n = s.cells.len();
        trench_floors(&mut s, &tr, 0, n, &|_, _| false);
        let mut p = plan();
        trench_rings(&mut p, &mut s, &tr, 0, n);
        let deepest = s.cells.iter().filter(|c| c.flag & TRENCH != 0).map(|c| c.c.g - c.g).max().unwrap();
        assert!((20..=33).contains(&deepest), "{deepest}");
        assert!(s.cells.iter().all(|c| !(c.c.fluid && c.flag & TRENCH != 0)), "the pond dug");
        let mut times: Vec<f32> = p.ev.iter().map(|e| e.0).collect();
        times.dedup();
        assert!(times.len() >= 10 && times[0] >= 31.0 && *times.last().unwrap() <= 39.01, "{times:?}");
        let first = p.ev.iter().find(|e| e.0 == times[0]).unwrap();
        if let Act::Blocks(b) = &first.1 {
            assert!(b.runs.iter().all(|r| tr.at(r.x, r.z).0 < tr.len() / 6.0));
        }
    }
}

#[cfg(test)]
mod bench {
    use super::*;
    /// `cargo test --release --lib we_corridor_bench -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn we_corridor_bench() {
        let holes = [Hole::new(0.5, 0.5, 64, 45.0, 60.0, 1), Hole::new(212.5, 212.5, 64, 45.0, 60.0, 2)];
        let t = std::time::Instant::now();
        let cols = corridor([0.5, 0.5], [212.5, 212.5], TR_W * 1.35, |x, z| holes.iter().any(|h| h.holds(x, z, 0.0)));
        let a = t.elapsed();
        let t = std::time::Instant::now();
        let n = cols.len();
        let site = Site::new(cols);
        let b = t.elapsed();
        eprintln!("corridor {n} columns: {:?}; site {:?} ({} cells)", a, b, site.cells.len());
    }
}
