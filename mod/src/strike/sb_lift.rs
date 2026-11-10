//! The Sky Breaks' opening: everything before the hand punches through the sky (SB_LEAD + 0.25 = 9 s). A disc of the
//! land round the target (LF_R across, its edge ragged) cracks round its rim and tears free: its real blocks are taken
//! out of the world (`world.edit-blocks`, a real hole left, deepest in its middle) and the pass draws them as an island
//! (shaders/skybreak.wgsl's `[lift]`), block for block in their real colours and textures, as read (`world.read-columns`,
//! the Hurricane's way: hurricane.rs's bk_words), the trees on it whole. It hangs a moment, rising slowly, turning a
//! little, dirt and pebbles falling off its underside (the first of them real falling blocks), a ring of dust rolling out
//! from where it tore out and bits of the rim lifting after it to circle it; then it speeds up, brakes under the sky and
//! sinks into it (LF_TOUCH to LF_IN), the sky closing over it. The sky rings like a pane struck (two or three tight
//! stiff rings, dead by LF_PRESS), a small star crack left where it went in, glinting. Then something presses on the
//! sky from behind: it bows down over the target, whitening with the strain, the dark of a hand on it as through frosted
//! glass, which lifts off and comes down again as a fist: the first crack (skybreak.rs's SB_CRACK).
//!
//! The pass's words from SB_LF (keep the LF_* in step with skybreak.wgsl's):
//! - `SB_LF` .. `+ 32`, the header: [state (0 none yet, 1 the land as read, 2 made up: the land never answered), its
//!   kinds, whether its blocks were taken out of the world (1) or are still there (terrain off: 0), its height (bottom to
//!   top), the grid's corner x y z (from the target's ground point), the pivot's place at rest x y z (the same), the
//!   cells it fills (i0 j0 k0, i1 j1 k1: from, to past), its top over the pivot, its reach from the pivot, how many bits
//!   fall off it, how many circle it, the blocks of it that fall as real falling blocks (the pass leaves those out)].
//! - `LF_RIM` (32 words): the disc's radius round the target, every 360/32 degrees from +x towards +z.
//! - `LF_PATH` (LF_NP samples of LF_PW, every LF_DT from 0): the pivot's place (x y z) and the island's turn (a
//!   quaternion x y z w) then.
//! - `LF_BITS` (LF_NB of LF_BW): what falls off its underside: when, where it comes off (x y z) and how fast (x y z),
//!   its kind, its size, its tumble (an axis's bearing, how fast).
//! - `LF_ORB` (LF_NO of LF_OW): the bits of the rim that lift after it and circle it: when they lift, where from (its
//!   bearing round the rim and its ground), the circle's radius and its height over the pivot, how fast round, its kind,
//!   its size.
//! - `LF_PAL` (LF_NK of LF_KW): its block kinds, each hurricane.rs's bk_words (its faces' colours and textures), the top
//!   bit of word 1 set for a plant drawn as crossed planes (its texture in word 2, how it runs in word 4).
//! - `LF_GRID` (LF_N by LF_N by LF_NY cells, a byte each, four to a word): its blocks, a kind + 1 (0 air); cell (i, j, k)
//!   is byte `(j * LF_N + k) * LF_N + i` (i along x, k along z, j up), the block at (bx - LF_H + i, y0 + j, bz - LF_H + k).
use super::hu_blocks::HU_BLOCKS;
use super::hurricane::{bk_words, hu_block};
use super::nuke::{Kind, kind};
use super::skybreak::TAU;
use super::*;
use crate::sdk::atlas;

/// The words' place (past the rest of the Sky Breaks' table and whatever else it grows: skybreak.rs's SB_WORDS is
/// 5416).
pub(super) const SB_LF: usize = 12288;
pub(super) const LF_RIM: usize = SB_LF + 32;
pub(super) const LF_NRIM: usize = 32;
pub(super) const LF_PATH: usize = SB_LF + 64;
pub(super) const LF_NP: usize = 200;
pub(super) const LF_PW: usize = 8;
pub(super) const LF_DT: f64 = 1.0 / 30.0;
pub(super) const LF_BITS: usize = LF_PATH + LF_NP * LF_PW;
pub(super) const LF_NB: usize = 48;
pub(super) const LF_BW: usize = 12;
pub(super) const LF_ORB: usize = LF_BITS + LF_NB * LF_BW;
pub(super) const LF_NO: usize = 16;
pub(super) const LF_OW: usize = 8;
pub(super) const LF_PAL: usize = LF_ORB + LF_NO * LF_OW;
pub(super) const LF_NK: usize = 48;
pub(super) const LF_KW: usize = 12;
pub(super) const LF_GRID: usize = LF_PAL + LF_NK * LF_KW;
pub(super) const LF_N: usize = 24;
pub(super) const LF_H: i32 = 12;
pub(super) const LF_NY: usize = 48;
pub(super) const LF_WORDS: usize = LF_GRID + LF_N * LF_N * LF_NY / 4;

/// The disc's radius (its edge wanders from about 0.85 to 1.15 of it round it).
pub(super) const LF_R: f64 = 7.0;
/// How deep it is torn out in its middle and at its edge (its underside tapers between, ragged).
const LF_DEEP: f64 = 14.0;
const LF_SHALLOW: f64 = 3.0;
/// The leaves of the trees on it out to this far past its edge go with it.
const LF_CANOPY: f64 = 3.5;
/// The blocks read under each column's top: a tree on it and its land under.
const LF_BELOW: u32 = 48;

// ---- the timeline (skybreak.wgsl's LF_*: keep in step) ---------------------------------------------------------------
/// The land is read as it fires; its ground cracks round the rim from LF_RING; its blocks are taken out at LF_CUT
/// (the pass draws them from when they are read, where they are, so the real ones win until then); it tears free at
/// LF_TEAR.
pub(super) const LF_RING: f32 = 0.08;
pub(super) const LF_CUT: f32 = 0.55;
pub(super) const LF_TEAR: f32 = 0.6;
/// It rises slowly until about LF_CLIMB, then speeds up; its top meets the sky at LF_TOUCH and its bottom is through by
/// LF_IN, when the sky has closed over it.
pub(super) const LF_CLIMB: f32 = 2.0;
pub(super) const LF_TOUCH: f32 = 4.2;
pub(super) const LF_IN: f32 = 5.15;
/// The star crack where it went in snaps out; the sky rings from LF_RIPPLE, still by LF_PRESS.
pub(super) const LF_STAR: f32 = 5.3;
pub(super) const LF_RIPPLE: f32 = 5.4;
/// Pressure from behind (sb_hand.rs's `punch` moves the hand): a hand comes down out of the dark from 6.3 s, lies flat
/// on the sky and leans on it from LF_PRESS, has rolled up onto its knuckles by 7.9, is drawn back (the sky's last heave
/// at LF_CURL) and thrown at LF_PUNCH, through at the first crack (skybreak.rs's SB_CRACK, 9 s).
pub(super) const LF_PRESS: f32 = 7.0;
pub(super) const LF_CURL: f32 = 8.35;
pub(super) const LF_PUNCH: f32 = 8.75;
/// The bits that fall off it as real falling blocks: the first few, while it is low.
const LF_REAL: usize = 10;

/// The disc's radius at bearing `a` (from +x towards +z): its ragged edge.
pub(super) fn lf_rim(seed: u32, a: f64) -> f64 {
    let u = (a / TAU).rem_euclid(1.0) * LF_NRIM as f64;
    let i = u.floor() as usize;
    let f = u - u.floor();
    let r = |k: usize| rim_at(seed, k % LF_NRIM);
    let s = f * f * (3.0 - 2.0 * f);
    r(i) + (r(i + 1) - r(i)) * s
}
fn rim_at(seed: u32, k: usize) -> f64 {
    // (a few big lobes and some small bites: never round)
    let a = TAU * k as f64 / LF_NRIM as f64;
    let ph = TAU * mh(1, seed, 0x1f1);
    let lobes = 0.12 * (2.0 * a + ph).sin() + 0.08 * (3.0 * a + 2.0 * ph).sin() + 0.05 * (5.0 * a + 3.0 * ph).sin();
    LF_R * (1.0 + lobes + 0.2 * (mh(k as u32, seed, 0x1f2) - 0.5))
}
/// How deep under its ground column (dx, dz) (from the target's column) is taken: deepest in the middle, a ragged taper
/// to its edge; none outside it.
fn depth_at(seed: u32, dx: i32, dz: i32) -> Option<i32> {
    let (x, z) = (f64::from(dx), f64::from(dz));
    let r = x.hypot(z);
    let edge = lf_rim(seed, z.atan2(x)) + 1.4 * (mh(((dx & 0xffff) | (dz << 16)) as u32, seed, 0x1f3) - 0.5);
    if r > edge {
        return None;
    }
    let u = (r / edge).min(1.0);
    let jag = 2.2 * (mh(((dx & 0xffff) | (dz << 16)) as u32, seed, 0x1f4) - 0.5) + 1.6 * (super::vnoise(x, z, 3.5, seed ^ 0x1f5) - 0.5);
    Some((LF_SHALLOW + (LF_DEEP - LF_SHALLOW) * (1.0 - u * u).max(0.0).powf(0.8) + jag * (0.3 + 0.7 * u)).round().max(2.0) as i32)
}

/// The island as read: its cells, its kinds (HU_BLOCKS's, with their tints), where it is.
#[derive(Default)]
pub(super) struct Island {
    pub grid: Vec<u8>,
    pub kinds: Vec<(u16, u32, u32)>,
    /// The world's y of the grid's bottom row.
    pub y0: i32,
    /// The world blocks taken out (x, z, from, to): a run up a column each.
    pub runs: Vec<(i32, i32, i32, i32)>,
    /// The cells it fills (i0, j0, k0, i1, j1, k1: from, to past).
    pub bounds: [usize; 6],
    pub real: bool,
}
impl Island {
    fn new() -> Island {
        Island { grid: vec![0; LF_N * LF_N * LF_NY], ..Default::default() }
    }
    fn at(i: usize, j: usize, k: usize) -> usize {
        (j * LF_N + k) * LF_N + i
    }
    pub fn cell(&self, i: usize, j: usize, k: usize) -> u8 {
        self.grid[Self::at(i, j, k)]
    }
    /// Kind `b` (HU_BLOCKS's) as tinted by `grass` and `foliage` (quantised as the Hurricane's are), its number + 1 for
    /// the grid; the last once the table's room is taken.
    fn kind_of(&mut self, b: u16, grass: u32, foliage: u32) -> u8 {
        crate::meter::spend(120);
        let q = |c: u32| c & 0xF0F0F0;
        let (g, f) = match HU_BLOCKS[b as usize].tint {
            1 => (q(grass), 0),
            2 => (0, q(foliage)),
            _ => (0, 0),
        };
        if let Some(i) = self.kinds.iter().position(|e| *e == (b, g, f)) {
            return i as u8 + 1;
        }
        if self.kinds.len() >= LF_NK {
            return LF_NK as u8;
        }
        self.kinds.push((b, g, f));
        self.kinds.len() as u8
    }
    /// What it fills, worked out from its cells.
    fn bound(&mut self) {
        let mut b = [usize::MAX, usize::MAX, usize::MAX, 0, 0, 0];
        crate::meter::spend(4 * self.grid.len() as u64);
        for j in 0..LF_NY {
            for k in 0..LF_N {
                for i in 0..LF_N {
                    if self.grid[Self::at(i, j, k)] != 0 {
                        b = [b[0].min(i), b[1].min(j), b[2].min(k), b[3].max(i + 1), b[4].max(j + 1), b[5].max(k + 1)];
                    }
                }
            }
        }
        self.bounds = if b[0] == usize::MAX { [0; 6] } else { b };
    }
    /// The middle of its cells (from the target's ground point at height `gy`), and its top and bottom over and under it.
    pub fn pivot(&self, gy: i32) -> ([f64; 3], f64, f64) {
        let (mut s, mut n) = ([0.0f64; 3], 0.0f64);
        let (mut lo, mut hi) = (f64::MAX, f64::MIN);
        crate::meter::spend(3 * self.grid.len() as u64);
        for j in self.bounds[1]..self.bounds[4] {
            for k in self.bounds[2]..self.bounds[5] {
                for i in self.bounds[0]..self.bounds[3] {
                    if self.grid[Self::at(i, j, k)] != 0 {
                        let c = self.rel(i, j, k, gy);
                        for q in 0..3 {
                            s[q] += c[q];
                        }
                        n += 1.0;
                        lo = lo.min(c[1] - 0.5);
                        hi = hi.max(c[1] + 0.5);
                    }
                }
            }
        }
        if n == 0.0 {
            return ([0.0, -4.0, 0.0], 1.0, 1.0);
        }
        let p = [s[0] / n, s[1] / n, s[2] / n];
        (p, hi - p[1], p[1] - lo)
    }
    /// Cell (i, j, k)'s middle, from the target's ground point (its block's corner at x - 0.5, z - 0.5).
    pub fn rel(&self, i: usize, j: usize, k: usize, gy: i32) -> [f64; 3] {
        [i as f64 - f64::from(LF_H), f64::from(self.y0 + j as i32 - gy) + 0.5, k as f64 - f64::from(LF_H)]
    }
}

/// The island from the land as read (`a`, the columns asked in `cols` order), round the target's block (bx, by, bz).
pub(super) fn island_from(a: &crate::columns::Answer, bx: i32, by: i32, bz: i32, seed: u32) -> Option<Island> {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    crate::meter::spend(3_000 * a.palette.len() as u64 + 400 * a.columns.len() as u64);
    let known: Vec<Option<u16>> = a.palette.iter().map(|n| hu_block(n)).collect();
    let bedrock = |p: usize| a.palette[p].contains("bedrock");
    // (each column: its ground (the highest ground block not far over the target's: never a roof), its blocks)
    struct C {
        dx: i32,
        dz: i32,
        base: i32,
        g: i32,
        i: usize,
    }
    let mut cols: Vec<C> = Vec::new();
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else { continue };
        let base = surface - a.below;
        crate::meter::spend(20 * blocks.len() as u64);
        let g = (0..blocks.len()).rev().find(|&j| base + j as i32 <= by + 10 && kinds.get(blocks[j] as usize).is_some_and(|k| k.0 == Kind::Ground));
        if let Some(g) = g {
            cols.push(C { dx: x - bx, dz: z - bz, base, g: base + g as i32, i });
        }
    }
    // (the middle's tints: the island's grass and leaves as the biome there tints them)
    let mid = cols.iter().min_by_key(|c| c.dx * c.dx + c.dz * c.dz)?;
    let (grass, foliage) = a.tints(mid.i);
    let mut isl = Island::new();
    // (the bottom row: the lowest block it takes)
    let low = cols.iter().filter_map(|c| depth_at(seed, c.dx, c.dz).map(|d| c.g - d + 1)).min()?;
    isl.y0 = low;
    let put = |isl: &mut Island, dx: i32, dz: i32, y: i32, p: usize| -> bool {
        let (i, k, j) = (dx + LF_H, dz + LF_H, y - isl.y0);
        if !(0..LF_N as i32).contains(&i) || !(0..LF_N as i32).contains(&k) || !(0..LF_NY as i32).contains(&j) {
            return false;
        }
        let b = known[p].or_else(|| hu_block("minecraft:dirt")).unwrap_or(0);
        let v = isl.kind_of(b, grass, foliage);
        isl.grid[Island::at(i as usize, j as usize, k as usize)] = v;
        true
    };
    // (the disc: everything from its bottom up to the top of what stands on it, but water and lava (left to pour in))
    let mut trees: Vec<(i32, i32, i32)> = Vec::new();
    for c in &cols {
        let Some(d) = depth_at(seed, c.dx, c.dz) else { continue };
        let Some((surface, blocks)) = a.column(c.i) else { continue };
        let _ = surface;
        let from = c.g - d + 1;
        let mut run: Option<(i32, i32)> = None;
        for j in 0..blocks.len() {
            let y = c.base + j as i32;
            if y < from {
                continue;
            }
            let p = blocks[j] as usize;
            let k = kinds.get(p).map_or(Kind::Air, |k| k.0);
            if bedrock(p) {
                run = None;
                continue;
            }
            if k == Kind::Air || k == Kind::Fluid {
                if let Some((y0, y1)) = run.take() {
                    isl.runs.push((c.dx + bx, c.dz + bz, y0, y1));
                }
                continue;
            }
            if !put(&mut isl, c.dx, c.dz, y, p) {
                // (past the grid: left in the world, and the run so far ended under it)
                if let Some((y0, y1)) = run.take() {
                    isl.runs.push((c.dx + bx, c.dz + bz, y0, y1));
                }
                continue;
            }
            if (k == Kind::Log || k == Kind::Leaves) && y > c.g {
                trees.push((c.dx, y, c.dz));
            }
            run = Some(run.map_or((y, y), |(y0, _)| (y0, y)));
        }
        if let Some((y0, y1)) = run {
            isl.runs.push((c.dx + bx, c.dz + bz, y0, y1));
        }
    }
    // (the leaves of the trees on it reaching out past its edge: those within a few blocks of its own, out to
    // LF_CANOPY past it, go with it; a tree standing off it keeps its own)
    if !trees.is_empty() {
        let seen: std::collections::HashSet<(i32, i32, i32)> = trees.iter().copied().collect();
        for c in &cols {
            if depth_at(seed, c.dx, c.dz).is_some() {
                continue;
            }
            let (x, z) = (f64::from(c.dx), f64::from(c.dz));
            if x.hypot(z) > lf_rim(seed, z.atan2(x)) + LF_CANOPY {
                continue;
            }
            let Some((_, blocks)) = a.column(c.i) else { continue };
            for j in 0..blocks.len() {
                let y = c.base + j as i32;
                let p = blocks[j] as usize;
                if y <= c.g + 1 || kinds.get(p).map_or(true, |k| k.0 != Kind::Leaves) {
                    continue;
                }
                crate::meter::spend(400);
                let near = seen.iter().any(|&(tx, ty, tz)| (tx - c.dx).abs() + (ty - y).abs() + (tz - c.dz).abs() <= 3);
                if near && put(&mut isl, c.dx, c.dz, y, p) {
                    isl.runs.push((c.dx + bx, c.dz + bz, y, y));
                }
            }
        }
    }
    isl.bound();
    if isl.bounds[3] == 0 {
        return None;
    }
    isl.real = true;
    Some(isl)
}

/// An island made up where the land never answered (or in the tests): grass on dirt on stone, a few flowers.
pub(super) fn island_made_up(seed: u32, gy: i32) -> Island {
    let mut isl = Island::new();
    isl.y0 = gy - LF_DEEP as i32 - 3;
    let names = ["minecraft:grass_block", "minecraft:dirt", "minecraft:stone", "minecraft:short_grass", "minecraft:dandelion", "minecraft:poppy", "minecraft:gravel"];
    let ids: Vec<u16> = names.iter().map(|n| hu_block(n).unwrap_or(0)).collect();
    for dz in -LF_H..LF_H {
        for dx in -LF_H..LF_H {
            let Some(d) = depth_at(seed, dx, dz) else { continue };
            let h = mh(((dx & 0xffff) | (dz << 16)) as u32, seed, 0x1f6);
            for y in gy - d..gy {
                let b = if y == gy - 1 { 0 } else if y >= gy - 4 { 1 } else if h > 0.85 && y < gy - 6 { 6 } else { 2 };
                let v = isl.kind_of(ids[b], 0, 0);
                let (i, j, k) = ((dx + LF_H) as usize, (y - isl.y0) as usize, (dz + LF_H) as usize);
                isl.grid[Island::at(i, j, k)] = v;
            }
            if h < 0.22 {
                let b = if h < 0.04 { 4 } else if h < 0.07 { 5 } else { 3 };
                let v = isl.kind_of(ids[b], 0, 0);
                isl.grid[Island::at((dx + LF_H) as usize, (gy - isl.y0) as usize, (dz + LF_H) as usize)] = v;
            }
        }
    }
    isl.bound();
    isl
}

// ---- its way up ------------------------------------------------------------------------------------------------------
/// Monotone cubic through `k` (time, value), at `t` (Fritsch-Carlson: it never overshoots a key).
fn mono(k: &[(f64, f64)], t: f64) -> f64 {
    let n = k.len();
    if t <= k[0].0 {
        return k[0].1;
    }
    if t >= k[n - 1].0 {
        return k[n - 1].1;
    }
    let i = (0..n - 1).find(|&i| t < k[i + 1].0).unwrap_or(n - 2);
    let d = |i: usize| (k[i + 1].1 - k[i].1) / (k[i + 1].0 - k[i].0);
    let m = |i: usize| -> f64 {
        if i == 0 {
            return d(0);
        }
        if i == n - 1 {
            return d(n - 2);
        }
        // (the harmonic mean of the slopes either side: flat where they differ in sign)
        let (a, b) = (d(i - 1), d(i));
        if a * b <= 0.0 { 0.0 } else { 2.0 * a * b / (a + b) }
    };
    let h = k[i + 1].0 - k[i].0;
    let s = (t - k[i].0) / h;
    let (s2, s3) = (s * s, s * s * s);
    (2.0 * s3 - 3.0 * s2 + 1.0) * k[i].1 + (s3 - 2.0 * s2 + s) * h * m(i) + (-2.0 * s3 + 3.0 * s2) * k[i + 1].1 + (s3 - s2) * h * m(i + 1)
}
fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
fn qmul(a: [f64; 4], b: [f64; 4]) -> [f64; 4] {
    [
        a[3] * b[0] + b[3] * a[0] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] + b[3] * a[1] + a[2] * b[0] - a[0] * b[2],
        a[3] * b[2] + b[3] * a[2] + a[0] * b[1] - a[1] * b[0],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    ]
}
fn qaxis(ax: [f64; 3], ang: f64) -> [f64; 4] {
    let s = (0.5 * ang).sin();
    [ax[0] * s, ax[1] * s, ax[2] * s, (0.5 * ang).cos()]
}
pub(super) fn qrot(q: [f64; 4], v: [f64; 3]) -> [f64; 3] {
    let t = [2.0 * (q[1] * v[2] - q[2] * v[1]), 2.0 * (q[2] * v[0] - q[0] * v[2]), 2.0 * (q[0] * v[1] - q[1] * v[0])];
    [
        v[0] + q[3] * t[0] + q[1] * t[2] - q[2] * t[1],
        v[1] + q[3] * t[1] + q[2] * t[0] - q[0] * t[2],
        v[2] + q[3] * t[2] + q[0] * t[1] - q[1] * t[0],
    ]
}

/// The island's way: its pivot (from the target's ground point) and its turn at `t`, for one at rest at `piv` whose top
/// is `top` over it and bottom `bot` under it. Its speed up is worked out as three smooth parts (`speed`): a lurch as
/// it tears free and a slow rise out of its hole, a climb (fast, then braking hard and smoothly under the sky), and its
/// sinking into the sky, scaled so that its top meets the sky at LF_TOUCH and its bottom is through by LF_IN; its
/// height is their sum to then (`ys`, every LF_STEP).
#[derive(Clone)]
pub(super) struct Way {
    pub piv: [f64; 3],
    pub top: f64,
    pub bot: f64,
    pub seed: u32,
    climb: f64,
    sink: f64,
    ys: Vec<f64>,
    yaw: Vec<f64>,
}
const LF_STEP: f64 = 1.0 / 200.0;
const LF_WAY_END: f64 = 7.0;
fn hang_v(t: f64) -> f64 {
    let tear = f64::from(LF_TEAR);
    let lurch = 14.0 * smooth(tear, tear + 0.05, t) * if t > tear + 0.06 { (-(t - tear - 0.06) / 0.12).exp() } else { 1.0 };
    lurch + (5.0 * smooth(tear + 0.02, 0.9, t) + 14.0 * smooth(1.0, 2.2, t)) * (1.0 - smooth(2.8, 3.8, t))
}
fn climb_v(t: f64) -> f64 {
    let u = (t - f64::from(LF_CLIMB)) / f64::from(LF_TOUCH - LF_CLIMB);
    if u <= 0.0 || u >= 1.0 { 0.0 } else { u.powf(2.4) * (1.0 - u).powf(1.7) }
}
fn sink_v(t: f64) -> f64 {
    smooth(4.0, 4.25, t) * (1.0 - smooth(4.55, 6.3, t))
}
fn integral(f: impl Fn(f64) -> f64, a: f64, b: f64) -> f64 {
    let n: u32 = 400;
    let h = (b - a) / f64::from(n);
    crate::meter::spend(u64::from(n) * 60);
    (0..n).map(|i| f(a + (f64::from(i) + 0.5) * h)).sum::<f64>() * h
}
impl Way {
    pub fn new(piv: [f64; 3], top: f64, bot: f64, seed: u32) -> Way {
        let (tear, touch, inn) = (f64::from(LF_TEAR), f64::from(LF_TOUCH), f64::from(LF_IN));
        let y = super::skybreak::SB_H - top - piv[1];
        let sink = (top + bot + 1.0) / integral(sink_v, touch, inn);
        let climb = (y - integral(hang_v, tear, touch) - sink * integral(sink_v, 4.0, touch)) / integral(climb_v, f64::from(LF_CLIMB), touch);
        let n = (LF_WAY_END / LF_STEP) as usize + 1;
        crate::meter::spend(n as u64 * 400);
        let mut ys = vec![0.0; n];
        let mut yaw = vec![0.0; n];
        // (its spin round the upright: 0.4 rad/s as it hangs, 0.9 by the top of its climb, gone as it goes in)
        let spin = |u: f64| (0.4 * smooth(0.7, 2.0, u) + 0.5 * smooth(2.4, 3.8, u) - 0.9 * smooth(4.2, 5.4, u)).max(0.0);
        let speed = |t: f64| hang_v(t) + climb * climb_v(t) + sink * sink_v(t);
        for i in 1..n {
            let t = (i as f64 - 0.5) * LF_STEP;
            let (v, w) = if t < tear { (0.0, 0.0) } else { (speed(t), spin(t)) };
            ys[i] = ys[i - 1] + v * LF_STEP;
            yaw[i] = yaw[i - 1] + w * LF_STEP;
        }
        Way { piv, top, bot, seed, climb, sink, ys, yaw }
    }
    fn table(v: &[f64], t: f64) -> f64 {
        let x = (t / LF_STEP).clamp(0.0, (v.len() - 1) as f64);
        let i = (x.floor() as usize).min(v.len() - 2);
        v[i] + (v[i + 1] - v[i]) * (x - i as f64)
    }
    /// How fast it climbs at `t`, blocks a second.
    pub fn speed(&self, t: f64) -> f64 {
        if t < f64::from(LF_TEAR) { 0.0 } else { hang_v(t) + self.climb * climb_v(t) + self.sink * sink_v(t) }
    }
    /// How far up the pivot is at `t`.
    pub fn rise(&self, t: f64) -> f64 {
        Self::table(&self.ys, t)
    }
    /// Its pivot at `t`.
    pub fn at(&self, t: f64) -> [f64; 3] {
        let s = self.seed;
        // (it drifts a little as it hangs, and comes in over the target as it climbs: it goes into the sky there)
        let a0 = TAU * mh(2, s, 0x1f7);
        let hang = smooth(f64::from(LF_TEAR), 1.4, t) * (1.0 - smooth(2.2, 3.4, t));
        let wx = hang * 1.1 * (a0 + 0.9 * t).cos();
        let wz = hang * 1.1 * (a0 + 0.9 * t).sin();
        let home = 1.0 - smooth(2.0, 3.6, t);
        [self.piv[0] * home + wx, self.piv[1] + self.rise(t), self.piv[2] * home + wz]
    }
    /// Its turn at `t` (x, y, z, w): a lurch as it tears free, then a slow tumble that grows as it climbs, its spin
    /// round the upright quickening, and straightening a little as the sky takes it.
    pub fn turn(&self, t: f64) -> [f64; 4] {
        let s = self.seed;
        let lurch = 0.06 * smooth(f64::from(LF_TEAR), 0.75, t) * (1.0 - 0.6 * smooth(0.75, 1.2, t));
        let hang = 0.1 * smooth(0.8, 2.0, t) + 0.05 * (TAU * (t - 0.8) / 2.6).sin() * smooth(0.8, 1.4, t);
        let climb = 0.2 * smooth(2.0, 3.8, t);
        let ease = 1.0 - 0.6 * smooth(f64::from(LF_TOUCH), f64::from(LF_IN) + 0.3, t);
        let tilt = (lurch + hang + climb) * ease;
        let bear = TAU * mh(3, s, 0x1f8) + 0.5 * smooth(0.8, 5.0, t) * (t - 0.8);
        let axis = [bear.cos(), 0.0, bear.sin()];
        let spin_dir = if mh(4, s, 0x1f9) < 0.5 { -1.0 } else { 1.0 };
        let yaw = Self::table(&self.yaw, t);
        qmul(qaxis(axis, tilt), qaxis([0.0, 1.0, 0.0], spin_dir * yaw))
    }
    /// Where a point of it at rest (from the target's ground point) is at `t`.
    pub fn place(&self, p: [f64; 3], t: f64) -> [f64; 3] {
        let c = self.at(t);
        let r = qrot(self.turn(t), [p[0] - self.piv[0], p[1] - self.piv[1], p[2] - self.piv[2]]);
        [c[0] + r[0], c[1] + r[1], c[2] + r[2]]
    }
}

// ---- the table -------------------------------------------------------------------------------------------------------
/// The rim's words, for the pass from as it fires (the ground cracks round it before the island's blocks are read).
pub(super) fn rim_words(seed: u32) -> Vec<u32> {
    (0..LF_NRIM).map(|k| (rim_at(seed, k) as f32).to_bits()).collect()
}
/// A bit that falls off the island: when, where at rest, its kind (the grid's number), its size, its fling.
#[derive(Clone, Copy, Debug)]
pub(super) struct Bit {
    pub t: f32,
    pub p: [f64; 3],
    pub kind: u8,
    pub size: f64,
    pub fling: f64,
    pub speed: f64,
}
impl Bit {
    /// Where it comes off the island (from the target's ground point) and how fast it is going then: lagging the
    /// island's climb a little, flung out.
    pub fn off(&self, way: &Way) -> ([f64; 3], [f64; 3]) {
        let t = f64::from(self.t);
        let p = way.place(self.p, t);
        let (a, b) = (way.place(self.p, t - 0.02), way.place(self.p, t + 0.02));
        let k = 0.7;
        let v = [(b[0] - a[0]) / 0.04 * k + self.fling.cos() * self.speed, (b[1] - a[1]) / 0.04 * k, (b[2] - a[2]) / 0.04 * k + self.fling.sin() * self.speed];
        (p, v)
    }
}
/// What falls off it: from its rim as it tears free, then from its underside as it rises.
pub(super) fn bits(isl: &Island, gy: i32, seed: u32) -> Vec<Bit> {
    let b = isl.bounds;
    // (each column's lowest block, and the rim's: the outermost columns)
    let mut under: Vec<([f64; 3], u8, f64)> = Vec::new();
    crate::meter::spend(30 * (LF_N * LF_N * LF_NY) as u64);
    for k in b[2]..b[5] {
        for i in b[0]..b[3] {
            if let Some(j) = (b[1]..b[4]).find(|&j| isl.cell(i, j, k) != 0) {
                let c = isl.rel(i, j, k, gy);
                under.push(([c[0], c[1] - 0.5, c[2]], isl.cell(i, j, k), c[0].hypot(c[2])));
            }
        }
    }
    if under.is_empty() {
        return Vec::new();
    }
    let mut rng = Rng::new(u64::from(seed) ^ 0x1f_b175);
    let mut rim: Vec<&([f64; 3], u8, f64)> = under.iter().filter(|u| u.2 > LF_R * 0.7).collect();
    if rim.is_empty() {
        rim = under.iter().collect();
    }
    let mut out = Vec::with_capacity(LF_NB);
    for n in 0..LF_NB {
        // (the first of them break off its rim as it tears; the rest drop from under it, fewer as it goes)
        let tear = n < 14;
        let t = if tear { LF_TEAR + 0.02 + 0.5 * (n as f32 / 14.0) + 0.06 * rng.next() as f32 } else { LF_TEAR + 0.6 + 3.0 * ((n - 14) as f64 / (LF_NB - 14) as f64).powf(1.3) as f32 + 0.08 * rng.next() as f32 };
        let src = if tear { rim[(rng.next() * rim.len() as f64) as usize % rim.len()] } else { &under[(rng.next() * under.len() as f64) as usize % under.len()] };
        let p = if tear { [src.0[0], src.0[1] + 0.5 + 2.0 * rng.next(), src.0[2]] } else { src.0 };
        let size = if n < LF_REAL || rng.next() < 0.2 { 1.0 } else { 0.3 + 0.4 * rng.next() };
        let fling = src.0[2].atan2(src.0[0]) + 0.8 * (rng.next() - 0.5);
        out.push(Bit { t, p, kind: src.1, size, fling, speed: 0.6 + 2.2 * rng.next() });
    }
    out
}
/// A bit of the rim that lifts after it and circles it.
#[derive(Clone, Copy, Debug)]
pub(super) struct Orbiter {
    pub t: f32,
    pub bear: f64,
    pub ground: f64,
    pub r: f64,
    pub h: f64,
    pub w: f64,
    pub kind: u8,
    pub size: f64,
}
fn orbiters(isl: &Island, seed: u32, ground: &dyn Fn(f64) -> f64) -> Vec<Orbiter> {
    let mut rng = Rng::new(u64::from(seed) ^ 0x1f_0b17);
    // (its ground kinds: what lay at its top, what under)
    let mut ks: Vec<u8> = Vec::new();
    for (n, k) in isl.kinds.iter().enumerate() {
        if matches!(HU_BLOCKS[k.0 as usize].class, 2) {
            ks.push(n as u8 + 1);
        }
    }
    if ks.is_empty() {
        ks.push(1);
    }
    let dir = if mh(4, seed, 0x1f9) < 0.5 { -1.0 } else { 1.0 };
    (0..LF_NO)
        .map(|n| {
            let bear = TAU * (n as f64 + 0.6 * rng.next()) / LF_NO as f64;
            Orbiter {
                t: LF_TEAR + 0.08 + 1.1 * rng.next() as f32,
                bear,
                ground: ground(bear),
                r: lf_rim(seed, bear) + 2.5 + 6.0 * rng.next(),
                h: -5.0 + 8.0 * rng.next(),
                w: dir * (0.55 + 0.6 * rng.next()),
                kind: ks[(rng.next() * ks.len() as f64) as usize % ks.len()],
                size: 0.3 + 0.55 * rng.next().powf(1.5),
            }
        })
        .collect()
}

/// The pass's words for the island (from SB_LF; the rim's included).
pub(super) fn lf_words(isl: &Island, way: &Way, bits: &[Bit], orb: &[Orbiter], gy: i32, seed: u32, cut: bool, real: usize) -> Vec<u32> {
    let mut w = vec![0u32; LF_WORDS - SB_LF];
    let f = |v: f64| (v as f32).to_bits();
    let o = |i: usize| i - SB_LF;
    let b = isl.bounds;
    w[0] = f(if isl.real { 1.0 } else { 2.0 });
    w[1] = f(isl.kinds.len() as f64);
    w[2] = f(if cut { 1.0 } else { 0.0 });
    w[3] = f(way.top + way.bot);
    let g0 = [-f64::from(LF_H) - 0.5, f64::from(isl.y0 - gy), -f64::from(LF_H) - 0.5];
    for q in 0..3 {
        w[4 + q] = f(g0[q]);
        w[7 + q] = f(way.piv[q]);
    }
    for q in 0..6 {
        w[10 + q] = f(b[q] as f64);
    }
    w[16] = f(way.top);
    // (its reach: the farthest of its cells' corners from the pivot)
    let mut reach: f64 = 0.0;
    for &(ci, cj, ck) in &[(b[0], b[1], b[2]), (b[3], b[4], b[5]), (b[0], b[4], b[5]), (b[3], b[1], b[2]), (b[0], b[1], b[5]), (b[3], b[4], b[2]), (b[0], b[4], b[2]), (b[3], b[1], b[5])] {
        let p = [g0[0] + ci as f64, g0[1] + cj as f64, g0[2] + ck as f64];
        reach = reach.max(((p[0] - way.piv[0]).powi(2) + (p[1] - way.piv[1]).powi(2) + (p[2] - way.piv[2]).powi(2)).sqrt());
    }
    w[17] = f(reach);
    w[18] = f(bits.len() as f64);
    w[19] = f(orb.len() as f64);
    w[20] = f(real as f64);
    w[21] = f(way.bot);
    for k in 0..LF_NRIM {
        w[o(LF_RIM) + k] = f(rim_at(seed, k));
    }
    crate::meter::spend(LF_NP as u64 * 6_000);
    for n in 0..LF_NP {
        let t = n as f64 * LF_DT;
        let c = way.at(t);
        let q = way.turn(t);
        let at = o(LF_PATH) + n * LF_PW;
        for k in 0..3 {
            w[at + k] = f(c[k]);
        }
        for k in 0..4 {
            w[at + 3 + k] = f(q[k]);
        }
    }
    for (n, bt) in bits.iter().enumerate().take(LF_NB) {
        let at = o(LF_BITS) + n * LF_BW;
        let (p, v) = bt.off(way);
        w[at] = f(f64::from(bt.t));
        for k in 0..3 {
            w[at + 1 + k] = f(p[k]);
            w[at + 4 + k] = f(v[k]);
        }
        w[at + 7] = f(f64::from(bt.kind));
        w[at + 8] = f(bt.size);
        w[at + 9] = f(bt.fling * 1.7 + 0.4);
        w[at + 10] = f(2.0 + 3.0 * bt.speed);
    }
    for (n, ob) in orb.iter().enumerate().take(LF_NO) {
        let at = o(LF_ORB) + n * LF_OW;
        let v = [f64::from(ob.t), ob.bear, ob.ground, ob.r, ob.h, ob.w, f64::from(ob.kind), ob.size];
        for k in 0..LF_OW {
            w[at + k] = f(v[k]);
        }
    }
    crate::meter::spend(isl.kinds.len() as u64 * 60_000);
    for (n, &(bk, grass, foliage)) in isl.kinds.iter().enumerate() {
        let at = o(LF_PAL) + n * LF_KW;
        let mut k = bk_words(bk, grass, foliage);
        if let Some(c) = cross_of(bk, grass, foliage) {
            k[1] |= 1 << 31;
            k[2] = c;
            k[3] = 0;
            // (across the plane: u along it, v down it)
            k[4] = 1 | 2 << 2 | 2 << 4 | 1 << 6 | 1 << 8;
        }
        w[at..at + LF_KW].copy_from_slice(&k[..LF_KW]);
    }
    crate::meter::spend(isl.grid.len() as u64 * 2);
    for (n, c) in isl.grid.iter().enumerate() {
        w[o(LF_GRID) + n / 4] |= u32::from(*c) << (8 * (n % 4));
    }
    w
}
/// A plant drawn as two crossed planes (flowers, grass, ferns, saplings): its texture's word (hurricane.rs's face_words'
/// first), tinted as the game tints it; none for a block drawn as a cube.
fn cross_of(b: u16, grass: u32, foliage: u32) -> Option<u32> {
    let k = &HU_BLOCKS[b as usize];
    if k.class != 5 {
        return None;
    }
    crate::meter::spend(40_000);
    let faces = atlas::block_sprites(&[k.name.to_string()]).pop().flatten();
    let c565 = |c: u32| ((c >> 19) & 31) << 11 | ((c >> 10) & 63) << 5 | ((c >> 3) & 31);
    let tint = match k.tint {
        1 => c565(if grass == 0 { 0x91BD59 } else { grass }),
        2 => c565(if foliage == 0 { 0x77AB2F } else { foliage }),
        _ => 0xFFFF,
    };
    let Some(f) = faces else {
        // (no textures known: its colour, as a plant)
        return Some(0);
    };
    // (the game leaves its crossed planes out of its sides, and names its texture as its particle's; the tests' stand-in
    // has them on its sides)
    if f.cube && f.particle.is_none() && f.sides.iter().all(|s| s.is_empty()) {
        return Some(0);
    }
    let sp = f.particle.or_else(|| f.sides.iter().flatten().next().map(|x| x.sprite))?;
    if sp.array != 0 || sp.layer >= 1 << 13 {
        return Some(0);
    }
    Some(1 | 1 << 1 | sp.layer << 2 | tint << 16)
}

// ---- the plan --------------------------------------------------------------------------------------------------------
/// The columns read for it: the disc and its canopy's reach round it.
pub(super) fn lf_columns(bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let r = LF_R * 1.25 + LF_CANOPY + 1.0;
    let n = r.ceil() as i32;
    let mut out = Vec::new();
    for dz in -n..=n {
        for dx in -n..=n {
            if f64::from(dx).hypot(f64::from(dz)) <= r && (-LF_H..LF_H).contains(&dx) && (-LF_H..LF_H).contains(&dz) {
                out.push((bx + dx, bz + dz));
            }
        }
    }
    out
}

/// The lift's part of the plan (from skybreak_plan): the land read as it fires, the island's table once it is, its
/// blocks taken out at LF_CUT, what falls off it, the dust, the jolts. `me`: the player, from the target's ground point.
pub(super) fn sb_lift_plan(p: &mut Plan, seed: u32, terrain: bool, me: [f64; 3]) {
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let gy = by + 1;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    // (the rim for the ground's cracks, at once; the land under the disc, asked as it fires)
    p.ev.push((0.05, Act::Words { index: LF_RIM as u32, words: rim_words(seed) }));
    let tag = crate::columns::new_tag();
    p.ev.push((0.0, Act::Read { tag, columns: lf_columns(bx, bz), below: LF_BELOW, above: 0 }));
    // (its chunks, within LF_H of the target's column, are held while it is read and cut with the rest of the strike's
    // (skybreak.rs's `sb_load_rows`, a site LF_H + 2 round the target): the panes' and the hand's take the same chunks in, and
    // a forceload removed here would let theirs go)
    fn wait(q: &mut Plan, tag: u32, seed: u32, terrain: bool, me: [f64; 3], at: f32) {
        let now = at.max(clock());
        let (bx, by, bz) = (q.bx, q.by, q.bz);
        let got = crate::columns::get(tag);
        // (until just before the cut it waits for the land; after, it makes one up, and leaves the land alone)
        if got.is_none() && now < LF_CUT - 0.1 {
            let t = now + 0.05;
            q.later(t, move |q| wait(q, tag, seed, terrain, me, t));
            return;
        }
        crate::columns::forget(tag);
        let isl = got.and_then(|a| island_from(&a, bx, by, bz, seed));
        let made_up = isl.is_none();
        let isl = isl.unwrap_or_else(|| island_made_up(seed, by + 1));
        let cut = terrain && !made_up && now <= LF_CUT + 0.3;
        lift_out(q, &isl, seed, cut, me, now);
        let what = if made_up { "made up (the land never answered)" } else if cut { "taken out of the land" } else { "drawn, the land left alone" };
        crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("skybreak: the island, {} blocks of {} kinds, {what}", isl.grid.iter().filter(|c| **c != 0).count(), isl.kinds.len()));
    }
    p.later(0.1, move |q| wait(q, tag, seed, terrain, me, 0.1));

    // ---- the jolts (the sounds are strike/sb_sounds.rs's) ----
    let dist = (me[0] * me[0] + me[1] * me[1] + me[2] * me[2]).sqrt();
    let near = (1.4 / (1.0 + dist / 45.0)).clamp(0.0, 1.0) as f32;
    // (the ground trembling as it cracks round the rim, for anyone near; the wrench as it tears free)
    for n in 0..6 {
        p.shake(LF_RING + 0.08 * n as f32, (0.12 + 0.05 * n as f32) * near, 0.12);
    }
    p.shake(LF_TEAR, 0.55 * near + 0.05, 0.4);
    // (the star crack snapping where it went in: high up, a small hard tick; then the sky straining)
    p.shake(LF_STAR, 0.12, 0.2);
    for (t, s) in [(7.55, 0.08), (7.95, 0.1), (8.3, 0.1), (8.8, 0.14), (8.9, 0.18)] {
        p.shake(t, s, 0.25);
    }
    // (real dust where the rim cracks and as it tears, for anyone close)
    let y = f64::from(gy);
    for n in 0..4 {
        p.at(LF_RING + 0.12 * n as f32, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {cx:.1} {:.1} {cz:.1} {r:.1} 0.2 {r:.1} 0.05 40 force"#, y + 0.2, r = LF_R * 0.8));
    }
    p.at(LF_TEAR, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {cx:.1} {:.1} {cz:.1} {r:.1} 1.0 {r:.1} 0.3 300 force"#, y + 0.5, r = LF_R));
    p.at(LF_TEAR + 0.05, format!("particle minecraft:poof {cx:.1} {:.1} {cz:.1} {r:.1} 0.4 {r:.1} 0.08 80 force", y + 0.4, r = LF_R + 1.0));
}

/// The island in: its words, its blocks out of the world, what falls off it for real, the dust under it.
fn lift_out(q: &mut Plan, isl: &Island, seed: u32, cut: bool, _me: [f64; 3], now: f32) {
    let (bx, by, bz) = (q.bx, q.by, q.bz);
    let gy = by + 1;
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let _ = (bx, bz);
    let (piv, top, bot) = isl.pivot(gy);
    let way = Way::new(piv, top, bot, seed);
    let bits = bits(isl, gy, seed);
    // (the rim's ground round it, from its own top there: where the orbiters lift from)
    let ground = |a: f64| -> f64 {
        let r = lf_rim(seed, a) - 1.5;
        let (i, k) = (((r * a.cos()).round() as i32 + LF_H) as usize, ((r * a.sin()).round() as i32 + LF_H) as usize);
        if i >= LF_N || k >= LF_N {
            return 0.0;
        }
        (0..LF_NY).rev().find(|&j| {
            let c = isl.cell(i, j, k);
            c != 0 && isl.kinds.get(c as usize - 1).is_some_and(|k| HU_BLOCKS[k.0 as usize].class == 2)
        }).map_or(0.0, |j| isl.rel(i, j, k, gy)[1] + 0.5)
    };
    let orb = orbiters(isl, seed, &ground);
    let real = if cut { LF_REAL.min(bits.len()) } else { 0 };
    let words = lf_words(isl, &way, &bits, &orb, gy, seed, cut, real);
    q.ev.push((now, Act::Words { index: SB_LF as u32, words }));
    if !cut {
        return;
    }
    // (its blocks out at LF_CUT, a run up each column; the pass has drawn it there since it was read)
    let mut b = Blocks::default();
    for &(x, z, y0, y1) in &isl.runs {
        b.run(x, z, y0, y1, "minecraft:air");
    }
    b.runs.shrink_to_fit();
    q.ev.push((LF_CUT, Act::Blocks(Box::new(b))));
    // (the first bits off it fall as real blocks, where the pass would have drawn them)
    for (n, bt) in bits.iter().enumerate().take(real) {
        let k = isl.kinds.get(bt.kind as usize - 1).map_or(0, |k| k.0);
        let name = HU_BLOCKS[k as usize].name;
        let class = HU_BLOCKS[k as usize].class;
        if class != 2 {
            continue;
        }
        let (pos, v) = bt.off(&way);
        let (vx, vy, vz) = (v[0] / 20.0, v[1] / 20.0, v[2] / 20.0);
        let keep = if n % 2 == 0 { "" } else { ",CancelDrop:1b" };
        q.ev.push((
            bt.t,
            Act::Cmd(format!(
                "summon minecraft:falling_block {:.2} {:.2} {:.2} {{BlockState:{{Name:\"{name}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}",
                cx + pos[0],
                f64::from(gy) + pos[1] - 0.5,
                cz + pos[2]
            )),
        ));
    }
    // (dust and grit falling from under it as it hangs, for anyone close)
    let mut t = LF_TEAR + 0.15;
    while t < 2.4 {
        let c = way.at(f64::from(t));
        let yb = f64::from(gy) + c[1] - bot - 1.0;
        q.at(t, format!(r#"particle minecraft:falling_dust{{block_state:"minecraft:dirt"}} {:.1} {yb:.1} {:.1} 3.5 0.6 3.5 0 30 force"#, cx + c[0], cz + c[2]));
        t += 0.15;
    }
}

/// For tools/preview (skybreak.rs's sb_write_table): the island's words over the preview's land (the tests' land:
/// grass on dirt on stone, an oak by the middle; `LF_TREE=0` none), from SB_LF in `w`; with `SB_HOLE=path`, the hole
/// it leaves for the preview's scene (`x z y` a column: its ground's new height).
#[cfg(test)]
pub(super) fn lf_preview(w: &mut Vec<u32>, seed: u32, terrain: bool) {
    let tree = std::env::var("LF_TREE").map_or(true, |v| v != "0");
    crate::columns::clear();
    let tag = crate::columns::new_tag();
    crate::columns::test_answer(tag, &lf_columns(0, 0), LF_BELOW, 0, &|x, z| {
        tests::lf_column(x, z, LF_BELOW, tree)
    });
    let a = crate::columns::get(tag).unwrap();
    let isl = island_from(&a, 0, 64, 0, seed).unwrap();
    let (piv, top, bot) = isl.pivot(65);
    let way = Way::new(piv, top, bot, seed);
    let bt = bits(&isl, 65, seed);
    let ground = |_: f64| 0.0;
    let orb = orbiters(&isl, seed, &ground);
    let words = lf_words(&isl, &way, &bt, &orb, 65, seed, terrain, if terrain { LF_REAL } else { 0 });
    w.resize(SB_LF, 0);
    w.extend(words);
    if let Ok(path) = std::env::var("SB_HOLE") {
        let mut bottom: std::collections::BTreeMap<(i32, i32), i32> = Default::default();
        for &(x, z, y0, _) in &isl.runs {
            if y0 <= 64 {
                let e = bottom.entry((x, z)).or_insert(y0);
                *e = (*e).min(y0);
            }
        }
        let text: String = bottom.iter().map(|((x, z), y)| format!("{x} {z} {y}\n")).collect();
        std::fs::write(path, text).unwrap();
    }
    eprintln!("island: {} blocks, {} kinds, pivot {:.1} {:.1} {:.1}, top {top:.1} bottom {bot:.1}", isl.grid.iter().filter(|c| **c != 0).count(), isl.kinds.len(), piv[0], piv[1], piv[2]);
}

#[cfg(test)]
mod tests {
    use super::*;
    /// A column of the tests' land: grass on dirt on stone at 64, tall grass and flowers here and there, and an oak by
    /// the middle (its trunk at 2, 1).
    pub(crate) fn lf_column(x: i32, z: i32, below: u32, tree: bool) -> Option<(i32, Vec<&'static str>)> {
        let g = 64;
        let h = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, 9, 3);
        let (tx, tz) = if tree { (2, 1) } else { (900, 900) };
        let (ddx, ddz) = ((x - tx).abs(), (z - tz).abs());
        let block = |y: i32| -> &'static str {
            if y <= g - 5 {
                "minecraft:stone"
            } else if y < g {
                "minecraft:dirt"
            } else if y == g {
                "minecraft:grass_block"
            } else if ddx == 0 && ddz == 0 && y <= g + 5 {
                "minecraft:oak_log"
            } else if (g + 4..=g + 5).contains(&y) && ddx <= 2 && ddz <= 2 && ddx + ddz < 4 {
                "minecraft:oak_leaves"
            } else if (g + 6..=g + 7).contains(&y) && ddx <= 1 && ddz <= 1 && ddx + ddz < 2 + i32::from(y == g + 6) {
                "minecraft:oak_leaves"
            } else if y == g + 1 && h < 0.3 {
                if h < 0.05 { "minecraft:dandelion" } else if h < 0.08 { "minecraft:poppy" } else { "minecraft:short_grass" }
            } else {
                "minecraft:air"
            }
        };
        let top = (g..=g + 8).rev().find(|&y| block(y) != "minecraft:air").unwrap_or(g) + 1;
        Some((top, (top - below as i32..top).map(block).collect()))
    }
    fn read(bx: i32, bz: i32) -> std::rc::Rc<crate::columns::Answer> {
        crate::columns::clear();
        let tag = crate::columns::new_tag();
        crate::columns::test_answer(tag, &lf_columns(bx, bz), LF_BELOW, 0, &|x, z| lf_column(x - bx, z - bz, LF_BELOW, true));
        crate::columns::get(tag).unwrap()
    }

    #[test]
    fn the_island_is_the_land_it_took() {
        let a = read(0, 0);
        let isl = island_from(&a, 0, 64, 0, 37).expect("an island");
        // (every block taken out is drawn in its cell, and nothing is drawn that wasn't taken)
        let mut taken = 0;
        for &(x, z, y0, y1) in &isl.runs {
            for y in y0..=y1 {
                let (i, j, k) = ((x + LF_H) as usize, (y - isl.y0) as usize, (z + LF_H) as usize);
                assert!(isl.cell(i, j, k) != 0, "{x} {y} {z} taken but not drawn");
                taken += 1;
            }
        }
        let drawn = isl.grid.iter().filter(|c| **c != 0).count();
        assert_eq!(taken, drawn);
        assert!(drawn > 800 && drawn < 4000, "{drawn} blocks");
        // (grass on top, stone underneath, the tree with it, the edge ragged)
        let names: Vec<&str> = isl.kinds.iter().map(|k| HU_BLOCKS[k.0 as usize].name).collect();
        for n in ["minecraft:grass_block", "minecraft:dirt", "minecraft:stone", "minecraft:oak_log", "minecraft:oak_leaves"] {
            assert!(names.contains(&n), "{n} missing: {names:?}");
        }
        let cols: std::collections::HashSet<(i32, i32)> = isl.runs.iter().filter(|r| r.2 < 64).map(|r| (r.0, r.1)).collect();
        let rmax = cols.iter().map(|&(x, z)| f64::from(x).hypot(f64::from(z))).fold(0.0, f64::max);
        let rmin = (0..64).map(|k| {
            let a = TAU * k as f64 / 64.0;
            (1..12).map(f64::from).find(|&r| !cols.contains(&((r * a.cos()).round() as i32, (r * a.sin()).round() as i32))).unwrap_or(12.0)
        }).fold(99.0, f64::min);
        assert!(rmax < LF_R * 1.35 + 0.5 && rmin > LF_R * 0.6, "its edge from {rmin} to {rmax}");
        // (deepest in its middle)
        let bottom = |x: i32, z: i32| isl.runs.iter().filter(|r| r.0 == x && r.1 == z).map(|r| r.2).min().unwrap();
        assert!(bottom(0, 0) <= 64 - 10 && bottom(5, 0).max(bottom(0, 5)) >= 64 - 9, "{} {} {}", bottom(0, 0), bottom(5, 0), bottom(0, 5));
    }

    #[test]
    fn its_way_up_meets_the_sky_on_time() {
        let a = read(0, 0);
        let isl = island_from(&a, 0, 64, 0, 37).unwrap();
        let (piv, top, bot) = isl.pivot(65);
        let way = Way::new(piv, top, bot, 37);
        let sky = super::super::skybreak::SB_H;
        let top_at = |t: f64| way.at(t)[1] + top;
        assert!((way.at(0.3)[1] - piv[1]).abs() < 1e-9, "still until it tears");
        assert!((top_at(f64::from(LF_TOUCH)) - sky).abs() < 0.5, "its top meets the sky at {}", top_at(f64::from(LF_TOUCH)));
        assert!(way.at(f64::from(LF_IN))[1] - bot > sky, "its bottom is through by LF_IN");
        assert!(way.rise(1.5) < 10.0 && way.rise(2.0) < 20.0, "it hangs low a while: {} {}", way.rise(1.5), way.rise(2.0));
        // (up all the way, never jerking: its speed changes smoothly)
        let mut prev = 0.0;
        let mut v_prev = 0.0;
        for n in 1..=200 {
            let t = 0.6 + n as f64 * 0.03;
            let y = way.rise(t);
            assert!(y >= prev - 1e-9, "down at {t}");
            let v = (y - prev) / 0.03;
            if n > 2 {
                assert!((v - v_prev).abs() < 60.0, "a jerk at {t}: {v_prev} to {v}");
            }
            prev = y;
            v_prev = v;
        }
        // (and over the target as it goes in)
        let c = way.at(f64::from(LF_TOUCH));
        assert!(c[0].hypot(c[2]) < 0.5, "{c:?}");
    }

    #[test]
    fn the_lift_plans_light() {
        crate::ground::set_test(Some(|_, _| Some(65)));
        crate::columns::clear();
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let mut ev = crate::strike::plan(&crate::lasers::SKYBREAK, &target, true, "minecraft:overworld", 37.0, [0.5, 70.0, 300.0], 0);
        // (play the plan out in time order as the game would, the land answered at once, to 2 s)
        let mut cut = None;
        let mut words = None;
        let mut summons = 0;
        loop {
            ev.sort_by(|a, b| b.0.total_cmp(&a.0));
            let Some((t, a)) = ev.pop() else { break };
            if t > 2.0 {
                break;
            }
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| lf_column(x, z, below + above, true)),
                Act::Later(job) | Act::Soon(job) => {
                    crate::meter::reset();
                    let more = job();
                    assert!(crate::meter::spent() < 20_000_000, "a stage of {} at {t}", crate::meter::spent());
                    ev.extend(more);
                }
                Act::Blocks(b) if t < 1.0 => cut = Some((t, b.runs.len())),
                Act::Words { index, words: w } if index as usize == SB_LF => words = Some((t, w)),
                Act::Cmd(c) if c.contains("falling_block") => summons += 1,
                _ => {}
            }
        }
        let (tw, w) = words.expect("the island's words");
        assert!(tw < LF_CUT - 0.05, "its words at {tw}");
        assert_eq!(w.len(), LF_WORDS - SB_LF);
        assert_eq!(f32::from_bits(w[0]), 1.0);
        assert_eq!(f32::from_bits(w[2]), 1.0);
        let (tc, runs) = cut.expect("its blocks taken out");
        assert!((tc - LF_CUT).abs() < 1e-6 && runs > 100, "{tc} {runs}");
        assert!(summons >= 5, "{summons} falling blocks");
    }
}
