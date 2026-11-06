//! The Supervolcano's mount: the land swelling into a dome some 800 across and 300 high (more at its crest) (VC_SWELL to VC_HUSH), then
//! bursting (VC_ERUPT). Nothing of it is real: the pass draws it (shaders/volcano_mount.wgsl) over the real land, on the
//! land's own heights and colours, and the white-out at the burst hides it going, so it needs no blocks, leaves none and
//! shows with the terrain off too.
//!
//! The height the pass draws is `land(x) + H(t) * P(x)`, less a crack's cut: `H` the dome's height now, one number; `P`
//! a number a column worked out here once, so the pass marches it reading one word a corner. The dome is broken into
//! plates (`Geo`: wedges in rings, long down the slope, with a star of them round the top): each column's `P` is its
//! plate's tangent plane to the dome, tilted and lifted a little its own way, so the steps between the plates grow as
//! the dome does, from nothing, and the slopes break by themselves. `D` is how far the column is from its plate's edge:
//! the cracks, which the pass opens and lights.
//!
//! What the pass reads (render.set-data, keep in step with volcano_mount.wgsl's VM_*): everything from VM_BASE, none of it
//! the table's or the land's (volcano.rs). The columns run from the vent's less VM_HALF, every VM_STEP, x then z.
use super::sh_land::{self, Class, MATS};
use super::vc_lodge::{self, Lodge, Rock, RockCol, Slab, VL_BASE, VL_MAP};
use super::volcano::Hf;
use super::*;
use std::cell::RefCell;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
pub(super) const VM_BASE: usize = 65_536;
/// The square of columns: VM_GW a side, VM_STEP blocks apart, VM_HALF either side of the vent.
pub(super) const VM_HALF: i32 = 480;
pub(super) const VM_STEP: i32 = 4;
pub(super) const VM_GW: usize = 241;
const VM_COLS: usize = VM_GW * VM_GW;
/// The tiles the march skips by: VM_TC cells a side, each two words (the land's highest, P's highest), a tile's words
/// taking in the tiles round it (the land slides under the march's feet).
const VM_TC: usize = 16;
const VM_TN: usize = 15;
const VM_TILE: usize = VM_BASE + 16;
/// The shards (VM_SW words each, in order of when they punch up), the fountains and the boulders (eight each), the plates.
const VM_SHARD: usize = VM_BASE + 512;
pub(super) const VM_SHARDS: usize = 56;
const VM_SW: usize = 26;
const VM_FOUNT: usize = VM_BASE + 2200;
pub(super) const VM_FOUNTS: usize = 44;
const VM_BOULD: usize = VM_BASE + 2800;
pub(super) const VM_BOULDS: usize = 40;
const VM_BW: usize = 16;
pub(super) const VM_PLATE: usize = VM_BASE + 3500;
pub(super) const VM_PW: usize = 16;
pub(super) const VM_PLATES: usize = 164;
/// The plates thrown at the burst: those of the rings on the dome (the others lie out on the land).
pub(super) const VM_FLY: usize = 95;
/// Their flight past the white-out, four words each (`vm_flights`).
pub(super) const VM_FLT: usize = VM_BASE + 6200;
/// The slab each is in its own frame, four words each (`vm_slabs`).
const VM_SLAB: usize = VM_BASE + 6600;
/// The columns' words: the land and the field (what the march reads), the colours, the rest (what the shading reads).
pub(super) const VM_W0: usize = VM_BASE + 8192;
const VM_W1: usize = VM_W0 + VM_COLS;
pub(super) const VM_W2: usize = VM_W1 + VM_COLS;
/// The dome's radius, on average.
const VM_RAD: f64 = 400.0;
/// How high it gets (the pass's vm_hgt, before the last heave).
const VM_H: f64 = 380.0;
/// The beats (BEATS.md).
const VC_SWELL: f64 = 7.0;
const VC_HUSH: f64 = 17.0;
/// How much of each column's stack is read, the columns worked out a tick, rows to a query.
const READ_BELOW: u32 = 12;
const READ_ABOVE: u32 = 1;
const PER_STAGE: usize = 2_400;
const PACK_COLS: usize = 8_000;
const READ_COLS: usize = 8_000;

/// The random numbers a column of the field draws on: a table made once (the columns are many, and a hash each is too
/// dear in fuel: 58,000 columns must go in a few ticks).
const VM_TAB: usize = 1 << 12;
fn vm_tab(seed: u32) -> Vec<f32> {
    (0..VM_TAB as u32).map(|i| mh(i, seed, 0x6d) as f32).collect()
}
#[derive(Clone, Copy, Default)]
struct Plate {
    x: f64,
    z: f64,
    /// The dome at its seed, and its slope there, its own tilt and lift in.
    s: f64,
    gx: f64,
    gz: f64,
    phase: u8,
}
struct Ring {
    r0: f64,
    r1: f64,
    n: usize,
    first: usize,
}
/// A column of rock thrust up through the land: a tapered prism with five straight sides, leaning, its top broken.
#[derive(Clone, Copy)]
pub(super) struct Shard {
    pub t0: f64,
    pub h: f64,
    pub x: f64,
    pub z: f64,
    pub rad: f64,
    pub lean: (f64, f64),
    pub tilt: (f64, f64),
    pub face: [(f64, f64); 5],
}
/// A burst of lava from a crack: where (on what land, at what share of the dome), when, for how long, how high.
#[derive(Clone, Copy, Default)]
struct Fount {
    x: f64,
    z: f64,
    land: f64,
    p: f64,
    t0: f64,
    dur: f64,
    h: f64,
    seed: f64,
}
/// The dome and how it breaks, for a seed: worked out as the strike starts, its long way across the player's look
/// (`facing`, the player's bearing from the vent), so from where they stand it fills as much of the horizon as it can.
pub(super) struct Geo {
    seed: u32,
    facing: f64,
    tab: Vec<f32>,
    /// The dome's radius by bearing.
    radii: Vec<f64>,
    rings: Vec<Ring>,
    plates: Vec<Plate>,
    pub shards: Vec<Shard>,
}
/// A column of the field.
#[derive(Clone, Copy, Default)]
pub(super) struct Cell {
    pub p: f64,
    pub d: f64,
    pub plate: u8,
    pub phase: u8,
    /// How far from the smaller breaks inside the plate.
    pub d2: f64,
}
impl Geo {
    pub fn new(seed: u32, facing: f64) -> Self {
        let ph = [TAU * mh(1, seed, 0x700), TAU * mh(2, seed, 0x700), TAU * mh(3, seed, 0x700), TAU * mh(4, seed, 0x700)];
        let [_, p1, p2, _] = ph;
        let radii = (0..=512)
            .map(|i| {
                let a = -PI + TAU * f64::from(i) / 512.0;
                VM_RAD * (1.0 - 0.16 * (2.0 * (a - facing)).cos() + 0.05 * (3.0 * a + p1).sin() + 0.03 * (5.0 * a + p2).sin())
            })
            .collect();
        let mut g = Geo { seed, facing, tab: vm_tab(seed), radii, rings: Vec::new(), plates: Vec::new(), shards: Vec::new() };
        // (wedges in rings: long down the slope, a star of them round the top, on out past the dome's foot over the land,
        // where only the cracks show)
        let mut first = 0;
        for &(r0, r1, n) in &[(0.0, 80.0, 8usize), (80.0, 167.0, 13), (167.0, 260.0, 19), (260.0, 353.0, 25), (353.0, 453.0, 30), (453.0, 573.0, 34), (573.0, 720.0, 35)] {
            g.rings.push(Ring { r0, r1, n, first });
            first += n;
        }
        for j in 0..g.rings.len() {
            let (r0, r1, n) = (g.rings[j].r0, g.rings[j].r1, g.rings[j].n);
            for i in 0..n {
                let k = g.plates.len() as u32;
                let a = TAU * (i as f64 + 0.25 + 0.5 * mh(k, seed, 0x701)) / n as f64 + 0.37 * j as f64;
                let r = r0 + (r1 - r0) * (0.3 + 0.4 * mh(k, seed, 0x702));
                let (x, z) = (r * a.cos(), r * a.sin());
                let s = g.dome(x, z);
                let e = 16.0;
                let gx = (g.dome(x + e, z) - g.dome(x - e, z)) / (2.0 * e);
                let gz = (g.dome(x, z + e) - g.dome(x, z - e)) / (2.0 * e);
                // (each plate its own way: a lift, a tilt; near the top more, a few much more: blocks heaved up on edge
                // and blocks dropped)
                let big = (mh(k, seed, 0x703) - 0.5) * 2.0;
                let heave = if mh(k, seed, 0x704) < 0.14 { 0.09 * (0.3 + s) } else { 0.0 };
                let tilt = 0.0003 + 0.0006 * s;
                let ta = TAU * mh(k, seed, 0x705);
                g.plates.push(Plate {
                    x,
                    z,
                    s: s + big * (0.012 + 0.05 * s) + heave,
                    gx: gx + tilt * ta.cos() * mh(k, seed, 0x706),
                    gz: gz + tilt * ta.sin() * mh(k, seed, 0x706),
                    phase: (mh(k, seed, 0x707) * 4.0) as u8,
                });
            }
        }
        // (in clumps, one tall one and a few by it: the first high up, on down the flanks as it goes on)
        let clumps = VM_SHARDS / 4;
        let mut shards = Vec::with_capacity(VM_SHARDS);
        for c in 0..clumps {
            let k = c as u32;
            let u = (c as f64 + 0.6 * mh(k, seed, 0x710)) / clumps as f64;
            let a = TAU * (0.618_034 * c as f64 + 0.2 * mh(k, seed, 0x711));
            let r = 100.0 + 250.0 * (0.2 + 0.8 * mh(k, seed, 0x712)).powf(0.8);
            let t0 = 11.4 + 5.0 * u.powf(0.8);
            let tall = (65.0 + 105.0 * mh(k, seed, 0x713).powf(1.3)) * (1.0 - 0.35 * r / 330.0);
            let rad = 18.0 + 18.0 * mh(k, seed, 0x714);
            // (they lean out from the middle of the clump, thrust apart)
            for b in 0..4u32 {
                let m = |q: u32| mh(k * 7 + b, seed, q);
                let oa = TAU * m(0x730);
                let o = if b == 0 { 0.0 } else { rad * (0.9 + 1.0 * m(0x731)) };
                let rot = TAU * m(0x734);
                let face = [0.0, 1.0, 2.0, 3.0, 4.0].map(|i: f64| {
                    let t = rot + i * TAU / 5.0 + 0.5 * (mh(k * 13 + b + i as u32, seed, 0x735) - 0.5);
                    (t.cos(), t.sin())
                });
                let (lx, lz) = (oa.cos(), oa.sin());
                let le = if b == 0 { 0.06 * m(0x736) } else { 0.1 + 0.22 * m(0x736) };
                let ta = TAU * m(0x737);
                shards.push(Shard {
                    t0: t0 + 0.5 * m(0x738) * f64::from(u32::from(b > 0)),
                    h: tall * if b == 0 { 1.0 } else { 0.42 + 0.46 * m(0x732) },
                    x: r * a.cos() + o * oa.cos(),
                    z: r * a.sin() + o * oa.sin(),
                    rad: rad * if b == 0 { 1.0 } else { 0.5 + 0.4 * m(0x733) },
                    lean: (le * lx, le * lz),
                    tilt: (0.5 * ta.cos(), 0.5 * ta.sin()),
                    face,
                });
            }
        }
        shards.sort_by(|a, b| a.t0.total_cmp(&b.t0));
        g.shards = shards;
        g
    }
    /// A smooth bump of noise, 0 to 1 (layer `s` of it).
    #[inline]
    fn vn(&self, x: f64, z: f64, s: u32) -> f64 {
        let (i, k) = (x.floor(), z.floor());
        let (u, v) = (x - i, z - k);
        let (u, v) = (u * u * (3.0 - 2.0 * u), v * v * (3.0 - 2.0 * v));
        let (ci, ck) = (i as i32 as u32, k as i32 as u32);
        let h = |a: u32, b: u32| f64::from(self.tab[(a.wrapping_mul(61).wrapping_add(b.wrapping_mul(1021)).wrapping_add(s.wrapping_mul(379)) as usize) & (VM_TAB - 1)]);
        let (a, b, c, d) = (h(ci, ck), h(ci + 1, ck), h(ci, ck + 1), h(ci + 1, ck + 1));
        (a * (1.0 - u) + b * u) * (1.0 - v) + (c * (1.0 - u) + d * u) * v
    }
    /// The dome at (x, z) from the vent: its share of the height, 0 past its foot, about 1 at the top. Never a circle,
    /// never a bowl: lobed round its foot, ridged over its back.
    pub fn dome(&self, x: f64, z: f64) -> f64 {
        let r2 = x * x + z * z;
        if r2 > 570.0 * 570.0 {
            return 0.0;
        }
        let rad = self.radii[(((z.atan2(x) + PI) / TAU * 512.0) as usize).min(512)];
        let u2 = r2 / (rad * rad);
        if u2 >= 1.0 {
            return 0.0;
        }
        // (a wide swell, its shoulders full, with a steeper heart heaved up through it)
        let v2 = u2 / 0.16;
        let b = 0.94 * (1.0 - u2) * (1.0 - 0.55 * u2) + if v2 < 1.0 { 0.16 * (1.0 - v2) * (1.0 - v2) } else { 0.0 };
        let ridges = self.vn(x / 227.0 + 3.3, z / 227.0, 1) - 0.5;
        let fine = self.vn(x / 88.0, z / 88.0 + 7.1, 2) - 0.5;
        b * (1.0 + 0.42 * ridges + 0.17 * fine)
    }
    /// The field at column (x, z) from the vent.
    pub fn cell(&self, x: f64, z: f64) -> Cell {
        // (the edges wander: long bends, jagged close to)
        let (wx, wz) = (
            x + 29.0 * (self.vn(x / 128.0, z / 128.0, 11) - 0.5) + 7.5 * (self.vn(x / 33.0, z / 33.0, 12) - 0.5) + 2.2 * (self.vn(x / 11.0, z / 11.0, 15) - 0.5),
            z + 29.0 * (self.vn(x / 128.0 + 5.0, z / 128.0, 13) - 0.5) + 7.5 * (self.vn(x / 33.0, z / 33.0 + 3.0, 14) - 0.5) + 2.2 * (self.vn(x / 11.0, z / 11.0 + 1.0, 16) - 0.5),
        );
        let r = (wx * wx + wz * wz).sqrt().max(1.0);
        let (ux, uz) = (wx / r, wz / r);
        let a = wz.atan2(wx);
        let j = self.rings.iter().position(|g| r < g.r1).unwrap_or(self.rings.len() - 1);
        let (mut d1, mut d2, mut best) = (1.0e18f64, 1.0e18f64, 0usize);
        for g in &self.rings[j.saturating_sub(1)..(j + 2).min(self.rings.len())] {
            let w = (((a / TAU).rem_euclid(1.0)) * g.n as f64).floor() as i64;
            // (the rings turn a little against each other: three or four of its wedges either side are enough)
            let n = g.n as i64;
            for o in -3..=3 {
                let i = g.first + (w + o).rem_euclid(n) as usize;
                let p = &self.plates[i];
                let (dx, dz) = (wx - p.x, wz - p.z);
                let dr = dx * ux + dz * uz;
                let dt = dz * ux - dx * uz;
                // (long down the slope)
                let d = (0.3136 * dr * dr + dt * dt).sqrt();
                if d < d1 {
                    d2 = d1;
                    d1 = d;
                    best = i;
                } else if d < d2 {
                    d2 = d;
                }
            }
        }
        let k = &self.plates[best];
        let s0 = self.dome(x, z);
        let plane = k.s + k.gx * (x - k.x) + k.gz * (z - k.z);
        // (the plates die out into the dome's own skirt, which dies out into the land)
        let on = smooth(0.012, 0.16, s0);
        let mut p = s0 + (plane - s0) * on;
        // (and each plate is broken again, smaller and less)
        let mut d_in = 31.0;
        if s0 > 0.0 {
            let (cx, cz) = ((x / 46.0).floor(), (z / 46.0).floor());
            let (mut dn, mut dn2, mut v) = (1.0e18f64, 1.0e18f64, 0.0);
            for b in -1..=1 {
                for c in -1..=1 {
                    let (ci, ck) = (cx + f64::from(b), cz + f64::from(c));
                    let id = ((ci as i32 as u32).wrapping_mul(53).wrapping_add((ck as i32 as u32).wrapping_mul(907)) as usize) & (VM_TAB - 4);
                    let (px, pz) = ((ci + f64::from(self.tab[id])) * 46.0, (ck + f64::from(self.tab[id + 1])) * 46.0);
                    let d = ((x - px) * (x - px) + (z - pz) * (z - pz)).sqrt();
                    if d < dn {
                        dn2 = dn;
                        dn = d;
                        v = f64::from(self.tab[id + 2]) - 0.5;
                    } else if d < dn2 {
                        dn2 = d;
                    }
                }
            }
            p += v * 0.03 * on * (0.4 + s0);
            d_in = 0.5 * (dn2 - dn);
        }
        Cell { p, d: 0.5 * (d2 - d1), plate: best as u8, phase: k.phase, d2: d_in }
    }
}
fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

/// What a column of the land comes to.
#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub(super) struct Col {
    /// What stands highest on it and how much of that is a tree, from the vent's ground.
    pub top: i32,
    pub canopy: u8,
    /// Its top's colour and the ground's under it, 5-6-5.
    pub c0: u32,
    pub c1: u32,
    /// 0 ground, 1 a tree, 2 water, 3 snow, 4 sand or bare stone.
    pub kind: u8,
    /// What the ground itself is (`MATS`), under what stands on it.
    pub m: u8,
}
fn c565(c: [f64; 3]) -> u32 {
    let (r, g, b) = ((c[0].clamp(0.0, 255.0)) as u32, (c[1].clamp(0.0, 255.0)) as u32, (c[2].clamp(0.0, 255.0)) as u32);
    ((r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)).max(1)
}
fn tinted(m: u8, grass: u32, foliage: u32) -> [f64; 3] {
    let (top, _, _, k) = MATS[m as usize];
    let c = [f64::from(top[0]), f64::from(top[1]), f64::from(top[2])];
    let t = match k >> 3 {
        1 if grass != 0 => grass,
        1 => 0x91BD59,
        2 if foliage != 0 => foliage,
        2 => 0x77AB2F,
        _ => return c,
    };
    [c[0] * f64::from((t >> 16) & 255) / 255.0, c[1] * f64::from((t >> 8) & 255) / 255.0, c[2] * f64::from(t & 255) / 255.0]
}
/// What a column's stack read comes to; none where it holds nothing but air.
pub(super) fn read_col(stack: &[u16], base: i32, below: i32, mats: &[(u8, Class)], tints: (u32, u32), gy: i32) -> Option<Col> {
    let y0 = base - below;
    let (mut top, mut surface) = (None, None);
    let mut ground = None;
    for i in (0..stack.len()).rev() {
        let (m, class) = mats.get(stack[i] as usize).copied().unwrap_or((0, Class::Ground));
        if class == Class::Air {
            continue;
        }
        if top.is_none() {
            top = Some(y0 + i as i32 + 1);
            surface = Some((m, class));
        }
        if class == Class::Ground {
            ground = Some((y0 + i as i32 + 1, m, i));
            break;
        }
    }
    let (top, (m, class)) = (top?, surface?);
    let mut c = Col { top: top - gy, ..Col::default() };
    let (grass, foliage) = tints;
    let col = tinted(m, grass, foliage);
    c.c0 = c565(if class == Class::Leaves { [col[0] * 0.82, col[1] * 0.82, col[2] * 0.82] } else { col });
    c.kind = match class {
        Class::Leaves | Class::Log => 1,
        Class::Water => 2,
        Class::Snow => 3,
        _ if matches!(m, 12..=23 | 44..=52) => 4,
        _ => 0,
    };
    if m == 10 {
        c.kind = 3;
    }
    // (the ground under it, and what lies under that: what shows when the land breaks)
    c.m = ground.map_or(m, |g| g.1);
    let under = match ground {
        Some((y, _, i)) => {
            c.canopy = (top - y).clamp(0, 31) as u8;
            let u = if i >= 1 { stack[i - 1] } else { stack[i] };
            mats.get(u as usize).copied().unwrap_or((2, Class::Ground)).0
        }
        None => 2,
    };
    c.c1 = c565(tinted(under.max(2), 0, 0));
    Some(c)
}

/// The mount's work, as it goes.
pub(super) struct Work {
    geo: Rc<Geo>,
    cells: Vec<Cell>,
    next_cell: usize,
    cols: Vec<Option<Col>>,
    known: usize,
}
impl Work {
    fn new(seed: u32, facing: f64) -> Self {
        Work { geo: Rc::new(Geo::new(seed, facing)), cells: vec![Cell::default(); VM_COLS], next_cell: 0, cols: vec![None; VM_COLS], known: 0 }
    }
    /// The next `n` columns of the field; whether that was the last of them.
    fn field(&mut self, n: usize) -> bool {
        let end = (self.next_cell + n).min(VM_COLS);
        crate::meter::spend(3_000 * (end - self.next_cell) as u64);
        for j in self.next_cell..end {
            let (x, z) = col_xz(j);
            self.cells[j] = self.geo.cell(x, z);
        }
        self.next_cell = end;
        end == VM_COLS
    }
}
/// Column j's place, from the vent.
fn col_xz(j: usize) -> (f64, f64) {
    let (i, k) = ((j % VM_GW) as i32, (j / VM_GW) as i32);
    (f64::from(i * VM_STEP - VM_HALF), f64::from(k * VM_STEP - VM_HALF))
}

/// The pass's columns as they are packed: in stages (58,000 columns' worth is some 40 million instructions).
pub(super) struct Pack {
    c0: Vec<u32>,
    c1: Vec<u32>,
    kk: Vec<u8>,
    blur: Vec<f32>,
    w0: Vec<u32>,
    w1: Vec<u32>,
    w2: Vec<u32>,
    tiles: Vec<[f32; 2]>,
    lo: f32,
    hi: f32,
    facing: f32,
    done: usize,
}
impl Pack {
    /// Begun: what wasn't read takes the colours of the nearest that was.
    fn new(w: &Work) -> Self {
        crate::meter::spend(180 * VM_COLS as u64);
        let mut c0 = vec![0u32; VM_COLS];
        let mut c1 = vec![0u32; VM_COLS];
        let mut kk = vec![0u8; VM_COLS];
        for j in 0..VM_COLS {
            if let Some(c) = w.cols[j] {
                c0[j] = c.c0;
                c1[j] = c.c1;
                kk[j] = c.kind;
            }
        }
        if w.known < VM_COLS {
            let spread = |c0: &mut Vec<u32>, c1: &mut Vec<u32>, kk: &mut Vec<u8>, j: usize, from: usize| {
                if c0[j] == 0 && c0[from] != 0 {
                    c0[j] = c0[from];
                    c1[j] = c1[from];
                    kk[j] = kk[from];
                }
            };
            for j in 0..VM_COLS {
                if j % VM_GW > 0 {
                    spread(&mut c0, &mut c1, &mut kk, j, j - 1);
                }
                if j >= VM_GW {
                    spread(&mut c0, &mut c1, &mut kk, j, j - VM_GW);
                }
            }
            for j in (0..VM_COLS).rev() {
                if j % VM_GW + 1 < VM_GW {
                    spread(&mut c0, &mut c1, &mut kk, j, j + 1);
                }
                if j + VM_GW < VM_COLS {
                    spread(&mut c0, &mut c1, &mut kk, j, j + VM_GW);
                }
            }
        }
        Pack {
            c0,
            c1,
            kk,
            blur: Vec::new(),
            w0: Vec::with_capacity(VM_COLS),
            w1: Vec::with_capacity(VM_COLS),
            w2: Vec::with_capacity(VM_COLS),
            tiles: vec![[f32::MIN, f32::MIN]; VM_TN * VM_TN],
            lo: f32::MAX,
            hi: f32::MIN,
            facing: w.geo.facing as f32,
            done: 0,
        }
    }
    /// (trees are no shape at three blocks a column: a wood is a low, soft roof over the ground)
    fn soften(&mut self, w: &Work) {
        crate::meter::spend(120 * VM_COLS as u64);
        let mut can: Vec<u16> = (0..VM_COLS).map(|j| w.cols[j].map_or(0, |c| u16::from(c.canopy))).collect();
        let mut run: Vec<u16> = vec![0; VM_GW + 1];
        for k in 0..VM_GW {
            let row = &mut can[k * VM_GW..(k + 1) * VM_GW];
            for i in 0..VM_GW {
                run[i + 1] = run[i] + row[i];
            }
            for (i, v) in row.iter_mut().enumerate() {
                *v = run[(i + 3).min(VM_GW)] - run[i.saturating_sub(2)];
            }
        }
        self.blur = vec![0f32; VM_COLS];
        for j in 0..VM_COLS {
            let up = if j >= VM_GW { can[j - VM_GW] } else { can[j] };
            let down = if j + VM_GW < VM_COLS { can[j + VM_GW] } else { can[j] };
            self.blur[j] = (f32::from(up) + f32::from(can[j]) + f32::from(down)) / 15.0;
        }
    }
    /// The next `n` columns (`land` gives one not read); whether that was the last of them.
    fn rows(&mut self, w: &Work, n: usize, land: &dyn Fn(f64, f64) -> f64) -> bool {
        let end = (self.done + n).min(VM_COLS);
        crate::meter::spend(600 * (end - self.done) as u64);
        for j in self.done..end {
            let (x, z) = col_xz(j);
            let cell = w.cells[j];
            let (top, canopy) = w.cols[j].map_or_else(|| (land(x, z), 0), |c| (f64::from(c.top - i32::from(c.canopy)) + 0.7 * f64::from(self.blur[j]), c.canopy));
            let h = ((top + 512.0) * 2.0).round().clamp(0.0, 2047.0) as u32;
            let p = (((cell.p + 0.25) / 1.6) * 2047.0).round().clamp(0.0, 2047.0) as u32;
            let d = (cell.d * 4.0).round().clamp(0.0, 127.0) as u32;
            self.w0.push(h | p << 11 | d << 22 | u32::from(cell.phase & 3) << 29);
            self.w1.push(if self.c0[j] != 0 { self.c0[j] | self.c1[j] << 16 } else { c565([95.0, 135.0, 60.0]) | c565([134.0, 96.0, 67.0]) << 16 });
            let d2 = (cell.d2 * 8.0).round().clamp(0.0, 255.0) as u32;
            self.w2.push(u32::from(cell.plate) | d2 << 8 | u32::from(self.kk[j] & 7) << 24 | u32::from(canopy.min(31)) << 27);
            let (i, k) = (j % VM_GW, j / VM_GW);
            let (ti, tk) = ((i / VM_TC).min(VM_TN - 1), (k / VM_TC).min(VM_TN - 1));
            let (tl, pl) = (top as f32, cell.p as f32);
            self.lo = self.lo.min(tl);
            self.hi = self.hi.max(tl);
            let t = &mut self.tiles[tk * VM_TN + ti];
            t[0] = t[0].max(tl);
            t[1] = t[1].max(pl);
        }
        self.done = end;
        end == VM_COLS
    }
    /// The whole of it, for the pass (a tile's words take in the tiles round it).
    fn finish(self) -> Vec<(usize, Vec<u32>)> {
        let own = self.tiles.clone();
        let mut tiles = self.tiles;
        for tk in 0..VM_TN {
            for ti in 0..VM_TN {
                for c in tk.saturating_sub(1)..(tk + 2).min(VM_TN) {
                    for b in ti.saturating_sub(1)..(ti + 2).min(VM_TN) {
                        let o = own[c * VM_TN + b];
                        let t = &mut tiles[tk * VM_TN + ti];
                        t[0] = t[0].max(o[0]);
                        t[1] = t[1].max(o[1]);
                    }
                }
            }
        }
        let tw: Vec<u32> = tiles.iter().flat_map(|t| t.iter().map(|v| v.to_bits())).collect();
        let head = vec![1f32.to_bits(), self.lo.to_bits(), self.hi.to_bits(), self.facing.cos().to_bits(), self.facing.sin().to_bits()];
        vec![(VM_BASE, head), (VM_TILE, tw), (VM_W0, self.w0), (VM_W1, self.w1), (VM_W2, self.w2)]
    }
}
/// How far a shard reaches from the middle it tumbles about (`mid` in the pass's vm_shards): its corners, where each two
/// sides meet its top and its foot. The ball the pass looks in has to hold all of it, or its edge cuts the shard.
fn shard_fit(s: &Shard, fx: f64, fz: f64, down: f64) -> f64 {
    let taper = 0.62 * s.rad / s.h;
    let mid = (0.5 * s.lean.0 * s.h, 0.25 * s.h, 0.5 * s.lean.1 * s.h);
    let mut far = 0.0f64;
    for i in 0..5 {
        let (a, b) = (s.face[i], s.face[(i + 1) % 5]);
        // (where the two sides meet, a unit in from each of them)
        let det = a.0 * b.1 - a.1 * b.0;
        let (vx, vz) = ((b.1 - a.1) / det, (a.0 - b.0) / det);
        let tl = s.tilt.0 * vx + s.tilt.1 * vz;
        let fl = fx * vx + fz * vz;
        for y in [(s.h - s.rad * tl) / (1.0 - taper * tl), (-down - s.rad * fl) / (1.0 - taper * fl)] {
            let r = s.rad - taper * y;
            let (dx, dy, dz) = (vx * r + s.lean.0 * y - mid.0, y - mid.1, vz * r + s.lean.1 * y - mid.2);
            far = far.max((dx * dx + dy * dy + dz * dz).sqrt());
        }
    }
    far + 1.0
}
/// The pass's tables that stand on the land: the shards, the fountains, the boulders, the plates (`p`, worked out).
fn vm_tables(w: &Work, p: &PlateSums, land: &dyn Fn(f64, f64) -> f64) -> Vec<(usize, Vec<u32>)> {
    crate::meter::spend(500_000);
    // (each shard stands on the land and the lift at its foot)
    let mut shards = Vec::with_capacity(VM_SHARDS * VM_SW);
    let foot = |x: f64, z: f64| {
        let j = col_index(x, z);
        (w.cols[j].map_or_else(|| land(x, z), |c| f64::from(c.top - i32::from(c.canopy))), w.cells[j].p)
    };
    for s in &w.geo.shards {
        let (l, p) = foot(s.x, s.z);
        let mut f = vec![s.x, s.z, l, p, s.t0, s.h, s.rad, s.lean.0, s.lean.1, s.tilt.0, s.tilt.1, 0.62 * s.rad / s.h];
        for c in s.face {
            f.push(c.0);
            f.push(c.1);
        }
        // (its foot: broken off under the land's slope there, so it hardly shows before it flies; no steeper than its
        // flare allows, or a short wide shard's sides run on far past the rock it is)
        let e = 24.0;
        let at = |x: f64, z: f64| {
            let (l, p) = foot(x, z);
            l + p * VM_H
        };
        let (mut sx, mut sz) = ((at(s.x + e, s.z) - at(s.x - e, s.z)) / (2.0 * e), (at(s.x, s.z + e) - at(s.x, s.z - e)) / (2.0 * e));
        let k = 1.0f64.min(0.25 * s.h / (0.62 * s.rad)) / sx.hypot(sz).max(1.0e-3);
        sx *= k.min(1.0);
        sz *= k.min(1.0);
        let down = 0.37 * s.h + 0.3 * s.rad;
        f.extend([-sx, -sz, down, shard_fit(s, -sx, -sz, down)]);
        shards.extend(f.iter().map(|v| (*v as f32).to_bits()));
    }
    let plates = vm_plates(w, p);
    let flights = vm_flights(&plates, w.geo.seed, land);
    vec![(VM_SHARD, shards), (VM_FOUNT, vm_founts(w, &foot)), (VM_BOULD, vm_boulders(w, &foot)), (VM_PLATE, plates), (VM_FLT, flights), (VM_SLAB, vm_slabs(w, p))]
}

/// The bursts of lava: on the cracks, few and high up at first, more and all over as it goes on, none past the hush.
fn vm_founts(w: &Work, foot: &dyn Fn(f64, f64) -> (f64, f64)) -> Vec<u32> {
    let s = w.geo.seed;
    let mut out = Vec::with_capacity(VM_FOUNTS * 8);
    let mut list: Vec<Fount> = (0..VM_FOUNTS as u32)
        .map(|k| {
            let u = (f64::from(k) + 0.7 * mh(k, s, 0x740)) / VM_FOUNTS as f64;
            let t0 = 10.4 + 6.4 * u.powf(0.7);
            let a0 = TAU * mh(k, s, 0x741);
            let r = 40.0 + 300.0 * mh(k, s, 0x742).powf(0.9) * (0.45 + 0.55 * u);
            // (along the ring to the crack nearest)
            let mut best = (1.0e9, r * a0.cos(), r * a0.sin());
            for b in -16..=16 {
                let a = a0 + f64::from(b) * 5.0 / r;
                let (x, z) = (r * a.cos(), r * a.sin());
                let j = col_index(x, z);
                if w.cells[j].d < best.0 {
                    best = (w.cells[j].d, x, z);
                }
            }
            let (land, p) = foot(best.1, best.2);
            let dur = 1.2 + 1.8 * mh(k, s, 0x743);
            Fount { x: best.1, z: best.2, land, p, t0, dur: dur.min((17.15 - t0).max(0.25)), h: 70.0 + 150.0 * mh(k, s, 0x744).powi(2) + 60.0 * u, seed: f64::from(k) * 1.37 }
        })
        .collect();
    list.sort_by(|a, b| a.t0.total_cmp(&b.t0));
    for f in list {
        out.extend([f.x, f.z, f.land, f.p, f.t0, f.dur, f.h, f.seed].map(|v| (v as f32).to_bits()));
    }
    out
}
/// The boulders breaking off and rolling down: each down a line from the middle: its bearing, where it starts, when and
/// how hard it goes, how big, and the land and the dome at five places on the way.
fn vm_boulders(w: &Work, foot: &dyn Fn(f64, f64) -> (f64, f64)) -> Vec<u32> {
    let s = w.geo.seed;
    let mut out = Vec::with_capacity(VM_BOULDS * VM_BW);
    for k in 0..VM_BOULDS as u32 {
        let a = TAU * mh(k, s, 0x750);
        let r0 = 90.0 + 200.0 * mh(k, s, 0x751);
        let r1 = (r0 + 260.0).min(350.0);
        let t0 = 10.5 + 6.0 * mh(k, s, 0x752);
        let acc = 13.0 + 18.0 * mh(k, s, 0x753);
        let size = 6.0 + 11.0 * mh(k, s, 0x754).powi(2);
        let mut f = vec![a.cos(), a.sin(), r0, r1, t0, acc, size, f64::from(k)];
        for i in 0..4 {
            let r = r0 + (r1 - r0) * f64::from(i) / 3.0;
            let (l, p) = foot(r * a.cos(), r * a.sin());
            f.push(l);
            f.push(p);
        }
        out.extend(f.iter().map(|v| (*v as f32).to_bits()));
    }
    out
}
/// What the plates' words need of every column, in stages (two rounds of all of them, some 28 million instructions at
/// once: the tick that was over half its fuel, each time the land's read came in): each plate's columns summed, then how
/// far they reach and how far their land stands off its plane.
struct PlateSums {
    sum: Vec<(f64, f64, f64, f64)>,
    rad: Vec<f64>,
    off: Vec<f64>,
    /// What the plane through its land's tops needs: xx, xz, zz, xy, zy, each column's from the plate's middle.
    fit: Vec<[f64; 5]>,
    /// How far under and over that plane they lie, at the height it all stood at the burst.
    span: Vec<(f64, f64)>,
    /// All its columns' height over its middle's at the burst: how far off the height it flies at its rock is.
    lift: Vec<f64>,
    done: usize,
}
impl PlateSums {
    fn new(w: &Work) -> Self {
        let n = w.geo.plates.len();
        PlateSums { sum: vec![(0.0, 0.0, 0.0, 0.0); n], rad: vec![0.0; n], off: vec![0.0; n], fit: vec![[0.0; 5]; n], span: vec![(f64::MAX, f64::MIN); n], lift: vec![0.0; n], done: 0 }
    }
    /// The plane that fits plate c's tops, from its middle: (dy/dx, dy/dz).
    fn plane(&self, c: usize) -> (f64, f64) {
        let [xx, xz, zz, xy, zy] = self.fit[c];
        let det = xx * zz - xz * xz;
        if det.abs() < 1.0 {
            return (0.0, 0.0);
        }
        ((xy * zz - zy * xz) / det, (zy * xx - xy * xz) / det)
    }
    /// The next `n` columns of the three rounds; whether that was the last of them.
    fn rows(&mut self, w: &Work, n: usize, land: &dyn Fn(f64, f64) -> f64) -> bool {
        let end = (self.done + n).min(3 * VM_COLS);
        crate::meter::spend(500 * (end - self.done) as u64);
        let centre = |t: (f64, f64, f64, f64)| if t.3 > 0.0 { (t.0 / t.3, t.1 / t.3, t.2 / t.3) } else { (0.0, 0.0, 0.0) };
        for i in self.done..end {
            let j = i % VM_COLS;
            let cell = &w.cells[j];
            let c = cell.plate as usize;
            let (x, z) = col_xz(j);
            if i < VM_COLS {
                let t = &mut self.sum[c];
                t.0 += x;
                t.1 += z;
                t.2 += w.cols[j].map_or_else(|| land(x, z), |c| f64::from(c.top - i32::from(c.canopy)));
                t.3 += 1.0;
                continue;
            }
            let t = self.sum[c];
            if t.3 > 0.0 {
                let (cx, cz, l) = centre(t);
                let (dx, dz) = (x - cx, z - cz);
                // (the land's top as the pass has it, at the height the dome had when it burst)
                let dy = w.cols[j].map_or_else(|| land(x, z), |k| f64::from(k.top - i32::from(k.canopy))) + cell.p * vm_burst_h() - l;
                if i < 2 * VM_COLS {
                    self.rad[c] = self.rad[c].max(dx * dx + dz * dz);
                    let g = &w.geo.plates[c];
                    let pc = g.s + g.gx * (cx - g.x) + g.gz * (cz - g.z);
                    let top = w.cols[j].map_or(l, |k| f64::from(k.top - i32::from(k.canopy))) + cell.p * VM_H;
                    let plane = l + VM_H * (pc + g.gx * dx + g.gz * dz);
                    self.off[c] = self.off[c].max((top - plane).abs());
                    let f = &mut self.fit[c];
                    for (v, a) in f.iter_mut().zip([dx * dx, dx * dz, dz * dz, dx * dy, dz * dy]) {
                        *v += a;
                    }
                } else {
                    let (a, b) = self.plane(c);
                    let u = dy - a * dx - b * dz;
                    // (a wood stands a little over its ground: the pack's soft roof)
                    let wood = 0.7 * w.cols[j].map_or(0.0, |k| f64::from(k.canopy));
                    let s = &mut self.span[c];
                    *s = (s.0.min(u), s.1.max(u + wood));
                    self.lift[c] += dy;
                }
            }
        }
        self.done = end;
        end == 3 * VM_COLS
    }
}
/// The plates as thrown at the burst: from the top first, up and out, each turning its own way.
fn vm_plates(w: &Work, p: &PlateSums) -> Vec<u32> {
    let s = w.geo.seed;
    let n = w.geo.plates.len();
    let centre = |t: (f64, f64, f64, f64)| if t.3 > 0.0 { (t.0 / t.3, t.1 / t.3, t.2 / t.3) } else { (0.0, 0.0, 0.0) };
    let mut out = Vec::with_capacity(VM_PW * n);
    for k in 0..n {
        let rad = p.rad[k].sqrt();
        let t = p.sum[k];
        let m = k as u32;
        let (cx, cz, l) = centre(t);
        let g = &w.geo.plates[k];
        let pc = g.s + g.gx * (cx - g.x) + g.gz * (cz - g.z);
        let r = cx.hypot(cz).max(1.0);
        let (ux, uz) = (cx / r, cz / r);
        // (the sheet: thrown out far more than up, those near the top up hardest; it goes in a fifth of a second)
        let tr = 18.03 + r / 1300.0 + 0.03 * mh(m, s, 0x760);
        let up = (170.0 + 330.0 * (1.0 - r / 430.0).clamp(0.0, 1.0)) * (0.7 + 0.6 * mh(m, s, 0x761));
        let out_v = (80.0 + 200.0 * (PI * (r / 440.0).min(1.0)).sin()) * (0.75 + 0.5 * mh(m, s, 0x762));
        let aa = TAU * mh(m, s, 0x763);
        let f = [cx, cz, l, pc, g.gx, g.gz, rad, 14.0 + 22.0 * mh(m, s, 0x764), if k < VM_FLY { tr } else { 1.0e6 }, ux * out_v, up, uz * out_v, aa.cos(), aa.sin(), (0.2 + 0.55 * mh(m, s, 0x765)) * if mh(m, s, 0x766) < 0.5 { 1.0 } else { -1.0 }, p.off[k] + 4.0];
        out.extend(f.iter().map(|v| (*v as f32).to_bits()));
    }
    out
}
/// How the plates come down, the pass's `vm_flown`: from when the air takes them (VM_BRK) each its drag's time `tau`, the
/// gravity that brings it to the land at the moment chosen for it, and that moment: the biggest last and highest.
fn vm_flights(t: &[u32], s: u32, land: &dyn Fn(f64, f64) -> f64) -> Vec<u32> {
    const VM_BRK: f64 = 18.7;
    const VM_G: f64 = 34.0;
    const VM_TH: f64 = 2.5;
    const H: f64 = 400.0; // the dome's height at the burst
    let word = |k: usize, i: usize| f64::from(f32::from_bits(t[k * VM_PW + i]));
    let big = (0..VM_FLY).map(|k| word(k, 6)).fold(1.0, f64::max);
    let mut out = Vec::with_capacity(4 * VM_FLY);
    for k in 0..VM_FLY {
        let q = (word(k, 6) / big).powi(2);
        let a = VM_BRK - word(k, 8);
        let (vx, vy, vz) = (word(k, 9), word(k, 10) - VM_G * a, word(k, 11));
        let y = word(k, 2) + word(k, 3) * H + word(k, 10) * a - 0.5 * VM_G * a * a;
        let hit = 28.0 + 6.0 * q + 1.5 * mh(k as u32, s, 0x767);
        let tau = 1.0 + 6.0 * q;
        let sec = hit - VM_BRK;
        let e = tau * (1.0 - (-sec / tau).exp());
        let eh = VM_TH * (1.0 - (-sec / VM_TH).exp());
        let (x, z) = (word(k, 0) + vx * (a + eh), word(k, 1) + vz * (a + eh));
        let g = (y + vy * e - land(x, z)) / (tau * (sec - e));
        // (the sphere it fits in, round its middle: tilted it reaches further than across the land it covers)
        let fit = word(k, 6) * (1.0 + (H * word(k, 4)).powi(2) + (H * word(k, 5)).powi(2)).sqrt() + word(k, 15) + word(k, 7);
        out.extend([tau, g, hit, fit].iter().map(|v| (*v as f32).to_bits()));
    }
    out
}
/// The slab each thrown plate is, in its own frame: the plane through its land's tops (its slope in x and in z) and how
/// far under and over that plane the tops lie, from the height its middle flies at. (The plate's word 3 and its tilt are
/// the plane it was made from, which is a long way off the land where the dome dies out: the slab the pass looks in has
/// to be the land's own, or the looks go on air, the plate is cut, or both.)
fn vm_slabs(w: &Work, p: &PlateSums) -> Vec<u32> {
    let mut out = Vec::with_capacity(4 * VM_FLY);
    for k in 0..VM_FLY {
        let t = p.sum[k];
        let (cx, cz) = if t.3 > 0.0 { (t.0 / t.3, t.1 / t.3) } else { (0.0, 0.0) };
        let g = &w.geo.plates[k];
        let y0 = vm_burst_h() * (g.s + g.gx * (cx - g.x) + g.gz * (cz - g.z));
        let (a, b) = p.plane(k);
        // (between columns the pass's top goes straight, and a broken edge reaches a column and a bit past its own)
        let m = 3.0 + 8.0 * a.hypot(b);
        let (lo, hi) = p.span[k];
        out.extend([a, b, lo - y0 - m, hi - y0 + m].iter().map(|v| (*v as f32).to_bits()));
    }
    out
}
/// The dome's height from the burst on: the pass's vm_hgt, its plates' phase 0, once it has stopped (keep in step).
pub(super) fn vm_burst_h() -> f64 {
    let s: f64 = VC_HUSH - VC_SWELL;
    let a = TAU * (0.42 * s + 0.03 * s * s);
    let da = TAU * (0.42 + 0.06 * s);
    let u = ((s - 0.8 * a.sin() / da) / 10.0).clamp(0.0, 1.0);
    VM_H * (0.62 * u + 0.08 * u * u + 0.3 * u.powi(4)) * 0.988 * 1.09
}
/// The column nearest (x, z) from the vent.
fn col_index(x: f64, z: f64) -> usize {
    let (i, k) = (((x + f64::from(VM_HALF)) / f64::from(VM_STEP)).round() as i32, ((z + f64::from(VM_HALF)) / f64::from(VM_STEP)).round() as i32);
    (k.clamp(0, VM_GW as i32 - 1) as usize) * VM_GW + i.clamp(0, VM_GW as i32 - 1) as usize
}

type Shared = Rc<RefCell<Work>>;

/// A round of the land's read: its queries, two in flight at a time, each asked as an earlier one comes in (the answers
/// of many at once would be too much for a tick to take in).
struct Round {
    tags: Vec<u32>,
    cols: Vec<Vec<(i32, i32)>>,
}
impl Round {
    fn new(cols: Vec<(i32, i32)>) -> Rc<Self> {
        let cols: Vec<Vec<(i32, i32)>> = cols.chunks(READ_COLS).map(<[_]>::to_vec).collect();
        Rc::new(Round { tags: cols.iter().map(|_| crate::columns::new_tag()).collect(), cols })
    }
    fn ask(&self, q: &mut Plan, part: usize, at: f32) {
        if let (Some(&tag), Some(c)) = (self.tags.get(part), self.cols.get(part)) {
            q.ev.push((at, Act::Read { tag, columns: c.clone(), below: READ_BELOW, above: READ_ABOVE }));
        }
    }
}

/// The mount's part of the plan: the field worked out as it starts, the land read, whatever the terrain setting, since
/// the mount is only drawn.
pub(super) fn vm_plan(p: &mut Plan, seed: u32, hf: Rc<RefCell<Hf>>, facing: f64, lodge: vc_lodge::Shared) {
    let w: Shared = Rc::new(RefCell::new(Work::new(seed, facing)));
    {
        let w = w.clone();
        p.later(0.1, move |q| vm_field_step(q, w, 0.1));
    }
    p.later(0.6, move |q| {
        let all: Vec<(i32, i32)> = (0..VM_COLS)
            .map(|j| (q.bx + ((j % VM_GW) as i32) * VM_STEP - VM_HALF, q.bz + ((j / VM_GW) as i32) * VM_STEP - VM_HALF))
            .collect();
        let r = Round::new(all);
        r.ask(q, 0, 0.6);
        r.ask(q, 1, 0.6);
        q.later(0.7, move |q| vm_land_step(q, w, hf, r, lodge, 0, 0, 0.7, 0));
    });
}

fn vm_field_step(q: &mut Plan, w: Shared, at: f32) {
    if !w.borrow_mut().field(PER_STAGE) {
        q.later(at + 0.05, move |q| vm_field_step(q, w, at + 0.05));
    }
}

/// The land's answers worked through, a part at a time, waiting for each; columns not loaded yet asked again until 5 s;
/// the pass given what there is after each round and in any case by 5.6 s.
#[allow(clippy::too_many_arguments)]
fn vm_land_step(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, r: Rc<Round>, lodge: vc_lodge::Shared, part: usize, start: usize, at: f32, round: u32) {
    if part >= r.tags.len() {
        vm_send(q, &w, &hf, &lodge, at);
        let (bx, bz) = (q.bx, q.bz);
        if round < 3 && at < 4.6 {
            let missing: Vec<(i32, i32)> = {
                let wb = w.borrow();
                (0..VM_COLS).filter(|&j| wb.cols[j].is_none()).map(|j| (bx + ((j % VM_GW) as i32) * VM_STEP - VM_HALF, bz + ((j / VM_GW) as i32) * VM_STEP - VM_HALF)).collect()
            };
            crate::meter::spend(30 * VM_COLS as u64);
            if !missing.is_empty() {
                let t = at + 0.5;
                q.later(t, move |q| {
                    let r = Round::new(missing);
                    r.ask(q, 0, t);
                    r.ask(q, 1, t);
                    vm_land_step(q, w, hf, r, lodge, 0, 0, t + 0.1, round + 1);
                });
            }
        }
        return;
    }
    let next = |q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, r: Rc<Round>, lodge: vc_lodge::Shared, part: usize, start: usize| {
        q.later(at + 0.05, move |q| vm_land_step(q, w, hf, r, lodge, part, start, at + 0.05, round));
    };
    let Some(a) = crate::columns::get(r.tags[part]) else {
        if at < 5.2 {
            next(q, w, hf, r, lodge, part, start);
        } else {
            vm_send(q, &w, &hf, &lodge, at);
        }
        return;
    };
    let mats: Vec<(u8, Class)> = a.palette.iter().map(|n| sh_land::material(n)).collect();
    let end = (start + PER_STAGE).min(a.columns.len());
    crate::meter::spend(500 * (end - start) as u64);
    {
        let mut wb = w.borrow_mut();
        let (bx, bz, gy) = (q.bx, q.bz, q.by + 1);
        for i in start..end {
            let Some((base, stack)) = a.column(i) else { continue };
            let (x, z) = a.columns[i];
            let (ci, ck) = (x - bx + VM_HALF, z - bz + VM_HALF);
            if let Some(c) = read_col(stack, base, a.below, &mats, a.tints(i), gy) {
                let j = (ck / VM_STEP) as usize * VM_GW + (ci / VM_STEP) as usize;
                wb.cols[j] = Some(c);
                wb.known += 1;
            }
        }
    }
    if end >= a.columns.len() {
        crate::columns::take(r.tags[part]);
        r.ask(q, part + 2, at);
        next(q, w, hf, r, lodge, part + 1, 0);
    } else {
        next(q, w, hf, r, lodge, part, end);
    }
}

/// The land as it stands given to the pass, over a few ticks.
fn vm_send(q: &mut Plan, w: &Shared, hf: &Rc<RefCell<Hf>>, lodge: &vc_lodge::Shared, at: f32) {
    if w.borrow().next_cell < VM_COLS {
        return;
    }
    let (w, hf, lodge) = (w.clone(), hf.clone(), lodge.clone());
    q.later(at + 0.05, move |q| {
        let p = Rc::new(RefCell::new(Pack::new(&w.borrow())));
        q.later(at + 0.1, move |q| {
            p.borrow_mut().soften(&w.borrow());
            vm_send_rows(q, w, hf, p, lodge, at + 0.15);
        });
    });
}
fn vm_send_rows(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, p: Rc<RefCell<Pack>>, lodge: vc_lodge::Shared, at: f32) {
    q.later(at, move |q| {
        let last = {
            let (wb, h) = (w.borrow(), hf.borrow());
            p.borrow_mut().rows(&wb, PACK_COLS, &|x, z| h.at(x, z))
        };
        if !last {
            vm_send_rows(q, w, hf, p, lodge, at + 0.05);
            return;
        }
        let Ok(p) = Rc::try_unwrap(p) else { return };
        let mut words = None;
        for (index, w) in p.into_inner().finish() {
            match (index, &mut words) {
                (VM_W0, _) => words = Some((w.clone(), Vec::new())),
                (VM_W2, Some(k)) => k.1 = w.clone(),
                _ => {}
            }
            q.ev.push((at, Act::Words { index: index as u32, words: w }));
        }
        let sums = PlateSums::new(&w.borrow());
        vm_send_tables(q, w, hf, sums, lodge, Rc::new(words.unwrap_or_default()), at + 0.05);
    });
}
/// The tables that stand on the land, once the plates are summed.
fn vm_send_tables(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, mut sums: PlateSums, lodge: vc_lodge::Shared, words: Rc<(Vec<u32>, Vec<u32>)>, at: f32) {
    q.later(at, move |q| {
        let last = {
            let (wb, h) = (w.borrow(), hf.borrow());
            sums.rows(&wb, PACK_COLS, &|x, z| h.at(x, z))
        };
        if !last {
            vm_send_tables(q, w, hf, sums, lodge, words, at + 0.05);
            return;
        }
        let tables = {
            let (wb, h) = (w.borrow(), hf.borrow());
            vm_tables(&wb, &sums, &|x, z| h.at(x, z))
        };
        let plates = tables.iter().find(|t| t.0 == VM_PLATE).map_or_else(Vec::new, |t| t.1.clone());
        let flights = tables.iter().find(|t| t.0 == VM_FLT).map_or_else(Vec::new, |t| t.1.clone());
        for (index, words) in tables {
            q.ev.push((at, Act::Words { index: index as u32, words }));
        }
        let picks = vl_pick(&w.borrow(), &sums, &lodge.borrow().sites);
        let make = Make { w, hf, sums, words, lodge, plates, flights, picks, slabs: Vec::new() };
        vl_make(q, make, at + 0.05);
    });
}

// ---- the plates that come down as real land: strike/vc_lodge.rs ---------------------------------------------------------
/// Which plates (`VM_FLY`), with their sites: the biggest that are whole, none whose middle flies far off the rock it
/// carries, nor a thin sliver. The biggest near the player. (plate, site, when it hits, how thick.)
fn vl_pick(w: &Work, p: &PlateSums, sites: &[vc_lodge::Site]) -> Vec<(usize, vc_lodge::Site, f64, f64)> {
    crate::meter::spend(100_000);
    let seed = w.geo.seed;
    let mut c: Vec<(f64, usize, f64)> = Vec::new();
    let fits = |k: usize, fill0: f64, off0: f64| {
        let n = p.sum[k].3;
        if n < 200.0 {
            return None;
        }
        let area = n * f64::from(VM_STEP * VM_STEP);
        let rad = p.rad[k].sqrt();
        let fill = area / (PI * rad * rad);
        let off = (p.lift[k] / n - vm_burst_h() * (w.geo.plates[k].s + w.geo.plates[k].gx * (p.sum[k].0 / n - w.geo.plates[k].x) + w.geo.plates[k].gz * (p.sum[k].1 / n - w.geo.plates[k].z))).abs();
        let span = p.span[k].1 - p.span[k].0;
        (fill >= fill0 && off <= off0 && rad < 128.0 && span < 90.0).then_some(area)
    };
    for (fill, off) in [(0.33, 45.0), (0.26, 90.0), (0.0, 1.0e6)] {
        c.clear();
        for k in 0..VM_FLY {
            if let Some(a) = fits(k, fill, off) {
                c.push((a, k, p.sum[k].1.atan2(p.sum[k].0)));
            }
        }
        if c.len() >= sites.len() {
            break;
        }
    }
    c.sort_by(|a, b| b.0.total_cmp(&a.0));
    c.truncate(sites.len());
    // (the times: the smallest first; the biggest last, in about the same second as what is thrown does)
    let mut order: Vec<(f64, usize)> = c.iter().map(|e| (e.0, e.1)).collect();
    order.sort_by(|a, b| a.0.total_cmp(&b.0));
    let hit = |k: usize| {
        let r = order.iter().position(|e| e.1 == k).unwrap_or(0) as f64;
        29.2 + 0.74 * r + 0.34 * mh(k as u32, seed, 0x76a)
    };
    let mut left = c;
    let mut out = Vec::with_capacity(sites.len());
    for (j, s) in sites.iter().enumerate() {
        // (of the biggest left, for the near ones, the one that lay nearest that way already)
        let a = s.z.atan2(s.x);
        let span = if s.near { (sites.len() / 2 - j.min(sites.len() / 2 - 1)).min(left.len()) } else { left.len() };
        let Some(i) = (0..span).min_by(|&p, &q| {
            let off = |i: usize| ((left[i].2 - a).rem_euclid(TAU) - PI).abs();
            off(q).total_cmp(&off(p))
        }) else {
            break;
        };
        let e = left.remove(i);
        out.push((e.1, *s, hit(e.1), 30.0 + 10.0 * mh(e.1 as u32, seed, 0x76b)));
    }
    out
}
/// What's being worked out of those plates, a stage each.
struct Make {
    w: Shared,
    hf: Rc<RefCell<Hf>>,
    sums: PlateSums,
    words: Rc<(Vec<u32>, Vec<u32>)>,
    lodge: vc_lodge::Shared,
    plates: Vec<u32>,
    flights: Vec<u32>,
    picks: Vec<(usize, vc_lodge::Site, f64, f64)>,
    slabs: Vec<Slab>,
}
/// Plate `n` of the picks as a rock, a slab and its flight (the words of the plate and its flight changed).
fn vl_one(n: usize, m: &mut Make) -> Slab {
    let (k, site, hit, th) = m.picks[n];
    let word = |t: &[u32], i: usize| f64::from(f32::from_bits(t[k * VM_PW + i]));
    let (cx, cz, l, pc) = (word(&m.plates, 0), word(&m.plates, 1), word(&m.plates, 2), word(&m.plates, 3));
    let hb = vm_burst_h();
    let wb = m.w.borrow();
    let (w0, w2) = (&m.words.0, &m.words.1);
    let mut cols = Vec::new();
    crate::meter::spend(40 * VM_COLS as u64);
    if !w0.is_empty() && !w2.is_empty() {
        for j in 0..VM_COLS {
            if (w2[j] & 255) as usize == k {
                let a = w0[j];
                let land = f64::from(a & 0x7ff) * 0.5 - 512.0;
                let p = f64::from((a >> 11) & 0x7ff) * (1.6 / 2047.0) - 0.25;
                let (kk, d2) = (((w2[j] >> 24) & 7) as u8, ((w2[j] >> 8) & 255) as f32 / 8.0);
                let m = wb.cols[j].map_or(1, |c| c.m);
                cols.push(RockCol { i: (j % VM_GW) as i32, k: (j / VM_GW) as i32, top: (land + p * hb) as f32, m, kind: kk, d2 });
                crate::meter::spend(60);
            }
        }
    }
    let big = (0..VM_FLY).map(|q| f64::from(f32::from_bits(m.plates[q * VM_PW + 6]))).fold(1.0, f64::max);
    let q = (word(&m.plates, 6) / big).powi(2);
    let rock = Rock {
        id: k,
        rest: [cx, l + pc * hb, cz],
        v: [word(&m.plates, 9), word(&m.plates, 10), word(&m.plates, 11)],
        tr: word(&m.plates, 8),
        tau: 1.0 + 6.0 * q,
        axis: (word(&m.plates, 12), word(&m.plates, 13)),
        spin: word(&m.plates, 14),
        th,
        plane: m.sums.plane(k),
        cols,
    };
    let mut s = Slab::new(&rock, site, hit, n, wb.geo.seed, 0.0);
    drop(wb);
    let gs = m.hf.borrow().at(site.x, site.z);
    let v = s.fly(gs);
    // (its own words: how thick, the way it goes; its flight's)
    for (i, x) in [(7, th), (9, v[0]), (11, v[2])] {
        m.plates[k * VM_PW + i] = (x as f32).to_bits();
    }
    let e = k * 4;
    let fit = word(&m.plates, 6) * (1.0 + (400.0 * word(&m.plates, 4)).powi(2) + (400.0 * word(&m.plates, 5)).powi(2)).sqrt() + word(&m.plates, 15) + th;
    for (i, x) in [rock.tau, s.g, hit, fit].iter().enumerate() {
        m.flights[e + i] = (*x as f32).to_bits();
    }
    s
}
fn vl_make(q: &mut Plan, mut m: Make, at: f32) {
    q.later(at, move |q| {
        let n = m.slabs.len();
        if n < m.picks.len() {
            let mut s = vl_one(n, &mut m);
            let w2 = m.words.1.clone();
            let id = s.rock_id;
            let (i0, k0) = s.grid_cells();
            s.set_bits(&|i, k| w2.get((k0 + k) * VM_GW + i0 + i).is_some_and(|w| (*w & 255) as usize == id));
            m.slabs.push(s);
            vl_make(q, m, at + 0.05);
            return;
        }
        let Make { lodge, plates, flights, slabs, .. } = m;
        for s in &slabs {
            let k = s.rock_id;
            q.ev.push((at, Act::Words { index: (VM_PLATE + k * VM_PW) as u32, words: plates[k * VM_PW..(k + 1) * VM_PW].to_vec() }));
            q.ev.push((at, Act::Words { index: (VM_FLT + k * 4) as u32, words: flights[k * 4..(k + 1) * 4].to_vec() }));
        }
        let mut l = lodge.borrow_mut();
        l.set_slabs(slabs);
        let (map, words) = l.words();
        q.ev.push((at, Act::Data { index: VM_BASE as u32 + 5, value: 1.0 }));
        q.ev.push((at, Act::Words { index: VL_MAP as u32, words: map }));
        q.ev.push((at, Act::Words { index: VL_BASE as u32, words }));
    });
}

#[cfg(test)]
pub(in crate::strike) mod table {
    use super::*;
    /// The preview's land for the table (`flat=1 trees=1` of tools/preview, read every VM_STEP), a river across it and a
    /// patch of bare ground, so its slopes can be seen carrying them.
    fn hash(x: i32, z: i32) -> f32 {
        let mut h = (x as u32).wrapping_mul(374761393) ^ (z as u32).wrapping_mul(668265263);
        h = (h ^ (h >> 13)).wrapping_mul(1274126177);
        ((h ^ (h >> 16)) & 0xFFFF) as f32 / 65535.0
    }
    fn tree(x: f32, z: f32) -> Option<f32> {
        let (bx, bz) = (x.floor() as i32, z.floor() as i32);
        let (cx, cz) = (bx.div_euclid(7), bz.div_euclid(7));
        if hash(cx, cz + 911) < 0.62 {
            return None;
        }
        let ox = cx * 7 + 1 + (hash(cx + 5, cz) * 4.0) as i32;
        let oz = cz * 7 + 1 + (hash(cx, cz + 5) * 4.0) as i32;
        let rr = 2 + (hash(cx + 9, cz + 3) * 1.6) as i32;
        let (dx, dz) = ((bx - ox).abs(), (bz - oz).abs());
        if dx.max(dz) > rr || dx + dz > rr + 1 {
            return None;
        }
        Some(7.0 + (hash(cx + 2, cz + 7) * 6.0).floor() - (dx + dz) as f32 * 0.5)
    }
    pub(in crate::strike) fn preview_col(x: f64, z: f64, hills: f64) -> Col {
        let (gx, gz) = (x + 0.5, z + 0.5);
        let g = hills * (0.5 * (gx * 0.045 + 0.7).sin() * (gz * 0.038).cos() + 0.5 * (gx * 0.013 - gz * 0.017).sin());
        let river = (z + 60.0 + 70.0 * (x * 0.006).sin() + 18.0 * (x * 0.021).sin()).abs();
        if river < 8.0 {
            return Col { top: g.round() as i32, canopy: 0, c0: c565([52.0, 96.0, 190.0]), c1: c565([120.0, 110.0, 96.0]), kind: 2, m: 25 };
        }
        let n = f64::from(hash(x as i32, z as i32));
        if let Some(t) = tree(x as f32, z as f32) {
            return Col { top: (g + f64::from(t)).round() as i32, canopy: t as u8, c0: c565([52.0 + 18.0 * n, 92.0 + 24.0 * n, 58.0 + 12.0 * n]), c1: c565([134.0, 96.0, 67.0]), kind: 1, m: 1 };
        }
        Col { top: g.round() as i32, canopy: 0, c0: c565([108.0 + 18.0 * n, 168.0 + 22.0 * n, 118.0 + 12.0 * n]), c1: c565([134.0, 96.0, 67.0]), kind: 0, m: 1 }
    }
    /// The whole table at once (the tests' and the preview's: the game's goes in stages).
    pub(in crate::strike) fn all(seed: u32, col: &dyn Fn(f64, f64) -> Option<Col>) -> Vec<(usize, Vec<u32>)> {
        all_lodged(seed, [0.0, 5.0, 1000.0], &|_, _| 0.0, col).0
    }
    /// The same with the plates that come down: `me` the player, `land` the ground's height from the vent.
    pub(in crate::strike) fn all_lodged(seed: u32, me: [f64; 3], land: &dyn Fn(f64, f64) -> f64, col: &dyn Fn(f64, f64) -> Option<Col>) -> (Vec<(usize, Vec<u32>)>, vc_lodge::Shared) {
        let facing = me[2].atan2(me[0]);
        let mut w = Work::new(seed, facing);
        while !w.field(PER_STAGE) {}
        for j in 0..VM_COLS {
            let (x, z) = col_xz(j);
            w.cols[j] = col(x, z);
        }
        let mut p = Pack::new(&w);
        p.soften(&w);
        while !p.rows(&w, PACK_COLS, &|_, _| 0.0) {}
        let mut o = p.finish();
        let mut sums = PlateSums::new(&w);
        while !sums.rows(&w, PACK_COLS, &|_, _| 0.0) {}
        let t = vm_tables(&w, &sums, &|_, _| 0.0);
        let plates = t.iter().find(|e| e.0 == VM_PLATE).unwrap().1.clone();
        let flights = t.iter().find(|e| e.0 == VM_FLT).unwrap().1.clone();
        o.extend(t);
        let words = (o.iter().find(|e| e.0 == VM_W0).unwrap().1.clone(), o.iter().find(|e| e.0 == VM_W2).unwrap().1.clone());
        let lodge: vc_lodge::Shared = Rc::new(RefCell::new(Lodge::new(vc_lodge::vl_sites(seed, me), seed, true, me, [0.5, 65.0, 0.5])));
        let picks = vl_pick(&w, &sums, &lodge.borrow().sites);
        let mut hf = Hf::default();
        let cells = (super::super::volcano::VC_HN * super::super::volcano::VC_HN) as usize;
        let reach = 1500.0;
        let n = super::super::volcano::VC_HN;
        hf.set(&(0..cells).map(|c| { let st = 2.0 * reach / (n - 1) as f64; Some(land(st * (c % n) as f64 - reach, st * (c / n) as f64 - reach)) }).collect::<Vec<_>>(), reach);
        let mut m = Make { w: Rc::new(RefCell::new(w)), hf: Rc::new(RefCell::new(hf)), sums, words: Rc::new(words), lodge: lodge.clone(), plates, flights, picks, slabs: Vec::new() };
        for n in 0..m.picks.len() {
            let mut s = vl_one(n, &mut m);
            let w2 = m.words.1.clone();
            let id = s.rock_id;
            let (i0, k0) = s.grid_cells();
            s.set_bits(&|i, k| w2.get((k0 + k) * VM_GW + i0 + i).is_some_and(|w| (*w & 255) as usize == id));
            m.slabs.push(s);
        }
        for e in &mut o {
            if e.0 == VM_PLATE {
                e.1 = m.plates.clone();
            }
            if e.0 == VM_FLT {
                e.1 = m.flights.clone();
            }
        }
        let mut l = lodge.borrow_mut();
        l.set_slabs(m.slabs);
        let (map, words) = l.words();
        o.push((VM_BASE + 5, vec![1f32.to_bits()]));
        o.push((VL_MAP, map));
        o.push((VL_BASE, words));
        drop(l);
        (o, lodge)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read(names: &[&str], x: u8) -> Vec<(u8, Class)> {
        let _ = x;
        names.iter().map(|n| sh_land::material(n)).collect()
    }
    #[test]
    fn a_stack_comes_to_its_top_and_its_ground() {
        let mats = read(&["minecraft:air", "minecraft:stone", "minecraft:dirt", "minecraft:grass_block", "minecraft:oak_leaves", "minecraft:oak_log", "minecraft:water", "minecraft:short_grass"], 0);
        // (a tree: stone, dirt, grass, a log, leaves over it, air: its top two over the grass)
        let stack = [1, 1, 1, 2, 3, 5, 5, 4, 0];
        let c = read_col(&stack, 108, 8, &mats, (0x91BD59, 0x77AB2F), 100).unwrap();
        assert_eq!((c.top, c.canopy, c.kind), (8, 3, 1));
        // (a lake too deep to see the bottom of: its surface)
        let c = read_col(&[6, 6, 6, 6, 0], 70, 4, &mats, (0, 0), 64).unwrap();
        assert_eq!((c.top, c.kind), (6, 2));
        // (grass plants are no height)
        let c = read_col(&[1, 3, 7, 0], 66, 3, &mats, (0, 0), 65).unwrap();
        assert_eq!((c.top, c.canopy, c.kind), (0, 0, 0));
        assert!(read_col(&[0, 0, 0], 66, 2, &mats, (0, 0), 64).is_none());
    }
    #[test]
    fn the_dome_is_about_800_wide_and_its_plates_cover_it() {
        let g = Geo::new(37, 0.0);
        let top = (0..2000).map(|i| { let a = i as f64 * 0.77; let r = i as f64 * 0.08; g.dome(r * a.cos(), r * a.sin()) }).fold(0.0, f64::max);
        assert!((0.8..1.35).contains(&top), "{top}");
        for k in 0..4 {
            let a = k as f64 * 1.3;
            assert!(g.dome(240.0 * a.cos(), 240.0 * a.sin()) > 0.1);
            assert_eq!(g.dome(490.0 * a.cos(), 490.0 * a.sin()), 0.0);
        }
        assert!(g.plates.len() <= VM_PLATES);
        let mut seen = vec![false; g.plates.len()];
        let (mut pmin, mut pmax) = (f64::MAX, f64::MIN);
        for j in (0..VM_COLS).step_by(7) {
            let (x, z) = col_xz(j);
            let c = g.cell(x, z);
            seen[c.plate as usize] = true;
            pmin = pmin.min(c.p);
            pmax = pmax.max(c.p);
        }
        assert!(pmin > -0.25 && pmax < 1.35, "{pmin} {pmax}");
        assert!(seen.iter().filter(|s| **s).count() > g.plates.len() / 2);
    }
    #[test]
    fn land_never_read_still_comes_out_whole() {
        // (nothing loaded: a flat grey-green land at the survey's height, no holes in the words)
        let t = table::all(37, &|_, _| None);
        let w0 = &t.iter().find(|w| w.0 == VM_W0).unwrap().1;
        let w1 = &t.iter().find(|w| w.0 == VM_W1).unwrap().1;
        assert_eq!(w0.len(), VM_COLS);
        assert!(w1.iter().all(|c| *c != 0));
        // (half of it read: the rest takes its colours)
        let t = table::all(37, &|x, z| (x < 0.0).then(|| table::preview_col(x, z, 0.0)));
        let w1 = &t.iter().find(|w| w.0 == VM_W1).unwrap().1;
        assert!(w1.iter().all(|c| *c != 0));
    }
    #[test]
    fn what_is_thrown_comes_down_and_some_of_it_passes_the_player() {
        let all = table::all(37, &|x, z| Some(table::preview_col(x, z, 0.0)));
        let plates = &all.iter().find(|t| t.0 == VM_PLATE).unwrap().1;
        let fl = &all.iter().find(|t| t.0 == VM_FLT).unwrap().1;
        assert_eq!(fl.len(), 4 * VM_FLY);
        let w = |t: &[u32], i: usize| f64::from(f32::from_bits(t[i]));
        let mut far = 0;
        for k in 0..VM_FLY {
            let (tau, g, hit) = (w(fl, 4 * k), w(fl, 4 * k + 1), w(fl, 4 * k + 2));
            assert!(tau >= 1.0 && (5.0..240.0).contains(&g), "plate {k}: tau {tau}, g {g}");
            assert!((28.0..36.7).contains(&hit), "plate {k} hits at {hit}");
            let b = k * VM_PW;
            let a = 18.7 - w(plates, b + 8);
            let eh = 2.5 * (1.0 - (-(hit - 18.7) / 2.5f64).exp());
            let (x, z) = (w(plates, b) + w(plates, b + 9) * (a + eh), w(plates, b + 1) + w(plates, b + 11) * (a + eh));
            assert!(w(fl, 4 * k + 3) >= w(plates, b + 6));
            if x.hypot(z) > 900.0 {
                far += 1;
            }
        }
        assert!(far >= 8, "only {far} plates come down past 900 blocks");
    }
    // ---- a thrown plate's and shard's shape: the pass's vm_plates and vm_shards on the CPU --------------------------------
    struct Tb<'a> {
        w0: &'a [u32],
        w2: &'a [u32],
        pl: &'a [u32],
        fl: &'a [u32],
        sl: &'a [u32],
        hb: f32,
    }
    fn tb(all: &[(usize, Vec<u32>)]) -> Tb<'_> {
        let get = |k: usize| all.iter().find(|t| t.0 == k).unwrap().1.as_slice();
        Tb { w0: get(VM_W0), w2: get(VM_W2), pl: get(VM_PLATE), fl: get(VM_FLT), sl: get(VM_SLAB), hb: vm_burst_h() as f32 }
    }
    fn w(t: &[u32], i: usize) -> f32 {
        f32::from_bits(t[i])
    }
    fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    }
    fn at(o: [f32; 3], d: [f32; 3], t: f32) -> [f32; 3] {
        [o[0] + d[0] * t, o[1] + d[1] * t, o[2] + d[2] * t]
    }
    /// What the pass has of plate i: its middle and height, its slab (the plane's slopes, its top and underside over and
    /// under the plate's middle), its thickness.
    struct Pl {
        i: usize,
        cxz: [f32; 2],
        y0: f32,
        sl: [f32; 2],
        th: f32,
        lt: f32,
        hi: f32,
    }
    fn pl(t: &Tb, i: usize) -> Pl {
        let (b, sb) = (i * VM_PW, i * 4);
        let th = w(t.pl, b + 7);
        let (lt, hi) = (w(t.sl, sb + 2) - th, w(t.sl, sb + 3));
        Pl { i, cxz: [w(t.pl, b), w(t.pl, b + 1)], y0: w(t.pl, b + 2) + w(t.pl, b + 3) * t.hb, sl: [w(t.sl, sb), w(t.sl, sb + 1)], th, lt, hi }
    }
    fn top(t: &Tb, q: &Pl, xz: [f32; 2]) -> Option<f32> {
        let (hf, st) = (VM_HALF as f32, VM_STEP as f32);
        let g = [((xz[0] + hf) / st).clamp(0.0, 239.999), ((xz[1] + hf) / st).clamp(0.0, 239.999)];
        let c = [g[0].floor(), g[1].floor()];
        let f = [g[0] - c[0], g[1] - c[1]];
        let b = c[1] as usize * VM_GW + c[0] as usize;
        let m = [(1.0 - f[0]) * (1.0 - f[1]), f[0] * (1.0 - f[1]), (1.0 - f[0]) * f[1], f[0] * f[1]];
        let (mut k, mut v) = (0.0, 0.0);
        for (j, o) in [b, b + 1, b + VM_GW, b + VM_GW + 1].into_iter().enumerate() {
            if t.w2[o] & 255 == q.i as u32 {
                let a = t.w0[o];
                k += m[j];
                v += m[j] * ((a & 0x7ff) as f32 * 0.5 - 512.0 + (((a >> 11) & 0x7ff) as f32 * (1.6 / 2047.0) - 0.25) * t.hb);
            }
        }
        (k >= 1.0e-4).then(|| v / k)
    }
    fn in_plate(t: &Tb, q: &Pl, lp: [f32; 3]) -> bool {
        let xz = [lp[0] + q.cxz[0], lp[2] + q.cxz[1]];
        let hf = VM_HALF as f32;
        if xz[0].abs() > hf - 3.0 || xz[1].abs() > hf - 3.0 {
            return false;
        }
        let jit = [(xz[1] * 0.43 + xz[0] * 0.11).sin() * 0.8, (xz[0] * 0.47 - xz[1] * 0.13).sin() * 0.8];
        let gc = [((xz[0] + hf) / VM_STEP as f32 + 0.5 + jit[0]).clamp(0.0, 240.0) as usize, ((xz[1] + hf) / VM_STEP as f32 + 0.5 + jit[1]).clamp(0.0, 240.0) as usize];
        if t.w2[gc[1] * VM_GW + gc[0]] & 255 != q.i as u32 {
            return false;
        }
        let y = lp[1] + q.y0;
        top(t, q, xz).is_some_and(|tp| y <= tp && y >= tp - q.th)
    }
    /// The pass's look along a ray in the plate's own frame (`ld` unit, `px` the pixel's angle, `dense` over 0: a look
    /// every `dense` blocks of the same stretch): how far, or under 0.
    fn march(t: &Tb, q: &Pl, lo: [f32; 3], ld: [f32; 3], fine: f32, px: f32, dense: f32) -> f32 {
        let rad = w(t.fl, q.i * 4 + 3);
        let tc = -dot(lo, ld);
        let dd = dot(lo, lo) - tc * tc;
        if dd > rad * rad * 1.1 || tc + rad < 0.0 {
            return -1.0;
        }
        let n = [-q.sl[0], 1.0, -q.sl[1]];
        let dn = dot(n, ld);
        if dn.abs() < 1.0e-5 {
            return -1.0;
        }
        let (t0, t1) = ((q.hi - dot(n, lo)) / dn, (q.lt - dot(n, lo)) / dn);
        let ch = (rad * rad * 1.1 - dd).max(0.0).sqrt();
        let ta = t0.min(t1).max(tc - ch).max(0.0);
        let tb = t0.max(t1).min(tc + ch);
        if ta >= tb {
            return -1.0;
        }
        let looks = if dense > 0.0 { 2 + ((tb - ta) / dense) as i32 } else { 2 + ((tb - ta) / (2.5 * fine).max(ta * px)).min(if fine < 1.5 { 60.0 } else { 44.0 }) as i32 };
        let dtl = (tb - ta) / looks as f32;
        for k in 0..looks {
            let s = ta + dtl * (k as f32 + 0.1);
            if in_plate(t, q, at(lo, ld, s)) {
                return s;
            }
        }
        -1.0
    }
    /// What is truly there along the ray: the plate's columns, however far from its slab.
    fn truth(t: &Tb, q: &Pl, lo: [f32; 3], ld: [f32; 3], reach: f32, step: f32) -> bool {
        let tc = -dot(lo, ld);
        let mut s = (tc - reach).max(0.0);
        while s < tc + reach {
            if in_plate(t, q, at(lo, ld, s)) {
                return true;
            }
            s += step;
        }
        false
    }
    fn hash01(k: u32) -> f32 {
        let mut h = k.wrapping_mul(2_654_435_761);
        h ^= h >> 15;
        h = h.wrapping_mul(2_246_822_519);
        h ^= h >> 13;
        (h & 0xffffff) as f32 / 16_777_216.0
    }
    fn nz(a: [f32; 3]) -> [f32; 3] {
        let l = dot(a, a).sqrt();
        [a[0] / l, a[1] / l, a[2] / l]
    }
    fn dir(k: u32) -> [f32; 3] {
        let (a, y) = (hash01(k + 1) * 6.283, hash01(k + 101) * 1.98 - 0.99);
        let q = (1.0 - y * y).sqrt();
        [q * a.cos(), y, q * a.sin()]
    }
    /// Plate q's outline from direction `d`, `gs` blocks a ray: what is there, what a look at all of the slab finds, and
    /// the pass's looks at full and half size.
    fn outline(t: &Tb, q: &Pl, d: [f32; 3], gs: f32, px: f32) -> (Vec<bool>, Vec<bool>, Vec<bool>, Vec<bool>, usize) {
        let fit = w(t.fl, q.i * 4 + 3) * 1.1;
        let up = if d[1].abs() > 0.9 { [1.0, 0.0, 0.0] } else { [0.0, 1.0, 0.0] };
        let cr = |a: [f32; 3], b: [f32; 3]| [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
        let u = nz(cr(up, d));
        let v = cr(d, u);
        let n = (2.0 * fit / gs) as i32 + 1;
        let mut o = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
        for y in 0..n {
            for x in 0..n {
                let (sx, sy) = (-fit + gs * x as f32, -fit + gs * y as f32);
                // (a far eye: near enough parallel rays, as far as a plate goes)
                let lo = [d[0] * -900.0 + u[0] * sx + v[0] * sy, d[1] * -900.0 + u[1] * sx + v[1] * sy, d[2] * -900.0 + u[2] * sx + v[2] * sy];
                o.0.push(truth(t, q, lo, d, fit * 1.05, 1.0));
                o.1.push(march(t, q, lo, d, 1.0, px, 0.5) >= 0.0);
                o.2.push(march(t, q, lo, d, 1.0, px, 0.0) >= 0.0);
                o.3.push(march(t, q, lo, d, 2.0, px, 0.0) >= 0.0);
            }
        }
        (o.0, o.1, o.2, o.3, n as usize)
    }
    /// Each plate from all round: at worst, how much of it its slab cuts away, and how much of what's left the pass's
    /// looks miss by more than a ray's width (7 blocks) from what they found, at full and half size: a plate seen one way
    /// can't lose what it shows another. `VM_REPORT=1` prints every plate's.
    fn plate_shapes(hills: f64, seed: u32) -> (f32, f32, f32) {
        let all = table::all(seed, &|x, z| Some(table::preview_col(x, z, hills)));
        let t = tb(&all);
        let px = 70f32.to_radians() / 1080.0;
        let (mut wc, mut wf, mut wh) = (0.0f32, 0.0f32, 0.0f32);
        let report = std::env::var("VM_REPORT").is_ok();
        let lost = |ev: &[bool], m: &[bool], n: usize| {
            (0..ev.len()).filter(|&j| ev[j] && !(0..9).any(|o: usize| {
                let (x, y) = ((j % n + (o % 3)).wrapping_sub(1), (j / n + o / 3).wrapping_sub(1));
                x < n && y < n && m[y * n + x]
            })).count()
        };
        // (every fourth, in a test run: a look at all of them takes a minute)
        for i in (0..VM_FLY).step_by(if report { 1 } else { 4 }) {
            let q = pl(&t, i);
            let (mut there, mut cut, mut found, mut lf, mut lh) = (0, 0, 0, 0, 0);
            for k in 0..8u32 {
                let (tv, ev, mf, mh, n) = outline(&t, &q, dir(k), 7.0, px);
                there += tv.iter().filter(|b| **b).count();
                cut += (0..tv.len()).filter(|&j| tv[j] && !ev[j]).count();
                found += ev.iter().filter(|b| **b).count();
                lf += lost(&ev, &mf, n);
                lh += lost(&ev, &mh, n);
            }
            let (c, f, h) = (cut as f32 / there.max(1) as f32, lf as f32 / found.max(1) as f32, lh as f32 / found.max(1) as f32);
            if report {
                println!("{i:3} th {:4.0} slab {:6.0} {:6.0} | there {there:6} cut {:5.1}% | looks lose {:5.2}% half {:5.2}%", q.th, q.lt, q.hi, 100.0 * c, 100.0 * f, 100.0 * h);
            }
            (wc, wf, wh) = (wc.max(c), wf.max(f), wh.max(h));
        }
        (wc, wf, wh)
    }
    #[test]
    fn a_thrown_plate_keeps_its_shape_from_every_side() {
        for hills in [0.0, 60.0] {
            let (cut, full, half) = plate_shapes(hills, 37);
            assert!(cut < 0.01, "a plate's slab cuts {:.1}% of it", cut * 100.0);
            assert!(full < 0.005 && half < 0.01, "a plate's looks lose {:.1}% of it, {:.1}% at half size", full * 100.0, half * 100.0);
        }
    }
    #[test]
    fn a_plate_has_no_fin_along_its_edges() {
        let all = table::all(37, &|x, z| Some(table::preview_col(x, z, 30.0)));
        let t = tb(&all);
        for i in 0..VM_FLY {
            let q = pl(&t, i);
            // (every block of its columns, against the slab the pass looks in)
            let (mut c, mut n) = (0, 0);
            for gz in 0..960 {
                for gx in 0..960 {
                    let lp = [gx as f32 - 480.0 - q.cxz[0], 0.0, gz as f32 - 480.0 - q.cxz[1]];
                    let xz = [gx as f32 - 480.0, gz as f32 - 480.0];
                    let Some(tp) = top(&t, &q, xz) else { continue };
                    if !in_plate(&t, &q, [lp[0], tp - q.y0, lp[2]]) {
                        continue;
                    }
                    n += 1;
                    let u = tp - q.y0 - q.sl[0] * lp[0] - q.sl[1] * lp[2];
                    c += usize::from(u > q.hi || u < q.lt + q.th);
                }
            }
            assert!(n > 0 && c == 0, "plate {i}: {c} columns of {n} stand out of its slab");
        }
    }
    /// The pass's look at shard `b` in its own frame, its sides, top and foot and nothing else: how far in and out.
    fn shard_hit(s: &[u32], b: usize, ro: [f32; 3], dv: [f32; 3]) -> Option<(f32, f32)> {
        let (taper, rad) = (w(s, b + 11), w(s, b + 6));
        let (mut tn, mut tf) = (f32::MIN, f32::MAX);
        let mut plane = |n: [f32; 3], d: f32| {
            let den = dot(n, dv);
            let tt = (d - dot(n, ro)) / den;
            if den < 0.0 {
                tn = tn.max(tt);
            } else {
                tf = tf.min(tt);
            }
        };
        for f in 0..5 {
            plane([w(s, b + 12 + 2 * f), taper, w(s, b + 13 + 2 * f)], rad);
        }
        plane([w(s, b + 9), 1.0, w(s, b + 10)], w(s, b + 5));
        // (the foot's the other way up)
        plane([-w(s, b + 22), -1.0, -w(s, b + 23)], w(s, b + 24));
        (tn < tf).then_some((tn, tf))
    }
    #[test]
    fn a_shard_ends_and_fits_its_ball() {
        let all = table::all(37, &|x, z| Some(table::preview_col(x, z, 30.0)));
        let s = &all.iter().find(|t| t.0 == VM_SHARD).unwrap().1;
        assert_eq!(s.len(), VM_SHARDS * VM_SW);
        for i in 0..VM_SHARDS {
            let b = i * VM_SW;
            let (h, rb) = (w(s, b + 5), w(s, b + 25));
            let lean = [w(s, b + 7), w(s, b + 8)];
            let mid = [lean[0] * h * 0.5, h * 0.25, lean[1] * h * 0.5];
            let mut far = 0.0f32;
            // (the frame's rays are sheared by its lean: a straight line still, so the ends of its stretch in it are the solid's)
            for k in 0..40_000u32 {
                let d = dir(k);
                let (a, r) = (dir(k + 90_000), rb * 1.3 * hash01(k + 200_000).sqrt());
                let o = [mid[0] + a[0] * r - d[0] * 900.0, mid[1] + a[1] * r - d[1] * 900.0, mid[2] + a[2] * r - d[2] * 900.0];
                let shear = |p: [f32; 3]| [p[0] - lean[0] * p[1], p[1], p[2] - lean[1] * p[1]];
                let (ro, dv) = (shear(o), shear(d));
                if let Some((tn, tf)) = shard_hit(s, b, ro, dv) {
                    assert!(tf < 2_000.0, "shard {i} has no end: a ray goes on through it to {tf}");
                    for t in [tn, tf] {
                        let p = at(o, d, t);
                        far = far.max((p[0] - mid[0]).hypot(p[1] - mid[1]).hypot(p[2] - mid[2]));
                    }
                }
            }
            assert!(far > 0.0 && far <= rb, "shard {i}: {far} from its middle, its ball {rb}");
        }
    }
    /// A plate's outlines from all round for looking at: VM_PL=4,88 VM_OUT=dir (VM_HILLS=H) writes dir/p4.pgm..., a column
    /// a side, rows: what is there; white what the looks find, pale what they miss, grey what the slab cuts.
    #[test]
    #[ignore]
    fn vm_plate_sheet() {
        let hills: f64 = std::env::var("VM_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let all = table::all(37, &|x, z| Some(table::preview_col(x, z, hills)));
        let t = tb(&all);
        let px = 70f32.to_radians() / 1080.0;
        let out = std::env::var("VM_OUT").unwrap();
        for ps in std::env::var("VM_PL").unwrap().split(',') {
            let i: usize = ps.parse().unwrap();
            let q = pl(&t, i);
            let gs = (w(t.fl, i * 4 + 3) * 2.2 / 120.0).max(1.0);
            let mut rows: [Vec<(Vec<u8>, usize)>; 3] = [vec![], vec![], vec![]];
            for d in [[0.0, 1.0, 0.01], [0.0, -1.0, 0.01], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.7, 0.3, 0.65], [-0.6, -0.5, 0.62]] {
                let (tv, ev, mf, mh, n) = outline(&t, &q, nz(d), gs, px);
                rows[0].push((tv.iter().map(|b| if *b { 255u8 } else { 0 }).collect(), n));
                rows[1].push(((0..tv.len()).map(|j| if !ev[j] { if tv[j] { 90u8 } else { 0 } } else if mf[j] { 255 } else { 170 }).collect(), n));
                rows[2].push(((0..tv.len()).map(|j| if !ev[j] { 0u8 } else if mh[j] { 255 } else { 170 }).collect(), n));
            }
            let (n, wd) = (rows[0][0].1, rows[0].iter().map(|r| r.1 + 2).sum::<usize>());
            let mut sheet: Vec<Vec<u8>> = vec![];
            for r in &rows {
                for y in 0..n {
                    let mut line = vec![];
                    for (v, n) in r {
                        line.extend_from_slice(&v[y * n..(y + 1) * n]);
                        line.extend_from_slice(&[40, 40]);
                    }
                    sheet.push(line);
                }
                sheet.push(vec![40; wd]);
            }
            let mut f = format!("P5\n{} {}\n255\n", wd, sheet.len()).into_bytes();
            f.extend(sheet.into_iter().flatten());
            std::fs::write(format!("{out}/p{i}.pgm"), f).unwrap();
        }
    }
    #[test]
    fn the_table_fits_the_pass_data() {
        assert!(VM_W2 + VM_COLS <= 262_144);
        assert!(VM_TILE + VM_TN * VM_TN * 2 <= VM_SHARD);
        assert!(VM_SHARD + VM_SHARDS * VM_SW <= VM_FOUNT);
        assert!(VM_FOUNT + VM_FOUNTS * 8 <= VM_BOULD);
        assert!(VM_BOULD + VM_BOULDS * VM_BW <= VM_PLATE);
        assert_eq!(VM_FLY, Geo::new(37, 0.0).rings[..5].iter().map(|g| g.n).sum::<usize>());
        assert!(VM_PLATE + VM_PLATES * VM_PW <= VM_FLT);
        assert!(VM_FLT + 4 * VM_FLY <= VM_SLAB);
        assert!(VM_SLAB + 4 * VM_FLY <= VL_MAP && VL_MAP + VM_FLY <= VL_BASE && VL_BASE + vc_lodge::VL_N * vc_lodge::VL_W <= VM_W0);
    }
}
