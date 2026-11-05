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
const VM_SW: usize = 22;
const VM_FOUNT: usize = VM_BASE + 2200;
pub(super) const VM_FOUNTS: usize = 44;
const VM_BOULD: usize = VM_BASE + 2800;
pub(super) const VM_BOULDS: usize = 40;
const VM_BW: usize = 16;
const VM_PLATE: usize = VM_BASE + 3500;
const VM_PW: usize = 16;
pub(super) const VM_PLATES: usize = 164;
/// The plates thrown at the burst: those of the rings on the dome (the others lie out on the land).
const VM_FLY: usize = 95;
/// The columns' words: the land and the field (what the march reads), the colours, the rest (what the shading reads).
const VM_W0: usize = VM_BASE + 8192;
const VM_W1: usize = VM_W0 + VM_COLS;
const VM_W2: usize = VM_W1 + VM_COLS;
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
fn read_col(stack: &[u16], base: i32, below: i32, mats: &[(u8, Class)], tints: (u32, u32), gy: i32) -> Option<Col> {
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
        shards.extend(f.iter().map(|v| (*v as f32).to_bits()));
    }
    vec![(VM_SHARD, shards), (VM_FOUNT, vm_founts(w, &foot)), (VM_BOULD, vm_boulders(w, &foot)), (VM_PLATE, vm_plates(w, p))]
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
    done: usize,
}
impl PlateSums {
    fn new(w: &Work) -> Self {
        let n = w.geo.plates.len();
        PlateSums { sum: vec![(0.0, 0.0, 0.0, 0.0); n], rad: vec![0.0; n], off: vec![0.0; n], done: 0 }
    }
    /// The next `n` columns of the two rounds; whether that was the last of them.
    fn rows(&mut self, w: &Work, n: usize, land: &dyn Fn(f64, f64) -> f64) -> bool {
        let end = (self.done + n).min(2 * VM_COLS);
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
                self.rad[c] = self.rad[c].max((x - cx).powi(2) + (z - cz).powi(2));
                let g = &w.geo.plates[c];
                let pc = g.s + g.gx * (cx - g.x) + g.gz * (cz - g.z);
                let top = w.cols[j].map_or(l, |k| f64::from(k.top - i32::from(k.canopy))) + cell.p * VM_H;
                let plane = l + VM_H * (pc + g.gx * (x - cx) + g.gz * (z - cz));
                self.off[c] = self.off[c].max((top - plane).abs());
            }
        }
        self.done = end;
        end == 2 * VM_COLS
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
pub(super) fn vm_plan(p: &mut Plan, seed: u32, hf: Rc<RefCell<Hf>>, facing: f64) {
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
        q.later(0.7, move |q| vm_land_step(q, w, hf, r, 0, 0, 0.7, 0));
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
fn vm_land_step(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, r: Rc<Round>, part: usize, start: usize, at: f32, round: u32) {
    if part >= r.tags.len() {
        vm_send(q, &w, &hf, at);
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
                    vm_land_step(q, w, hf, r, 0, 0, t + 0.1, round + 1);
                });
            }
        }
        return;
    }
    let next = |q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, r: Rc<Round>, part: usize, start: usize| {
        q.later(at + 0.05, move |q| vm_land_step(q, w, hf, r, part, start, at + 0.05, round));
    };
    let Some(a) = crate::columns::get(r.tags[part]) else {
        if at < 5.2 {
            next(q, w, hf, r, part, start);
        } else {
            vm_send(q, &w, &hf, at);
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
        next(q, w, hf, r, part + 1, 0);
    } else {
        next(q, w, hf, r, part, end);
    }
}

/// The land as it stands given to the pass, over a few ticks.
fn vm_send(q: &mut Plan, w: &Shared, hf: &Rc<RefCell<Hf>>, at: f32) {
    if w.borrow().next_cell < VM_COLS {
        return;
    }
    let (w, hf) = (w.clone(), hf.clone());
    q.later(at + 0.05, move |q| {
        let p = Rc::new(RefCell::new(Pack::new(&w.borrow())));
        q.later(at + 0.1, move |q| {
            p.borrow_mut().soften(&w.borrow());
            vm_send_rows(q, w, hf, p, at + 0.15);
        });
    });
}
fn vm_send_rows(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, p: Rc<RefCell<Pack>>, at: f32) {
    q.later(at, move |q| {
        let last = {
            let (wb, h) = (w.borrow(), hf.borrow());
            p.borrow_mut().rows(&wb, PACK_COLS, &|x, z| h.at(x, z))
        };
        if !last {
            vm_send_rows(q, w, hf, p, at + 0.05);
            return;
        }
        let Ok(p) = Rc::try_unwrap(p) else { return };
        for (index, words) in p.into_inner().finish() {
            q.ev.push((at, Act::Words { index: index as u32, words }));
        }
        let sums = PlateSums::new(&w.borrow());
        vm_send_tables(q, w, hf, sums, at + 0.05);
    });
}
/// The tables that stand on the land, once the plates are summed.
fn vm_send_tables(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, mut sums: PlateSums, at: f32) {
    q.later(at, move |q| {
        let last = {
            let (wb, h) = (w.borrow(), hf.borrow());
            sums.rows(&wb, PACK_COLS, &|x, z| h.at(x, z))
        };
        if !last {
            vm_send_tables(q, w, hf, sums, at + 0.05);
            return;
        }
        let (wb, h) = (w.borrow(), hf.borrow());
        for (index, words) in vm_tables(&wb, &sums, &|x, z| h.at(x, z)) {
            q.ev.push((at, Act::Words { index: index as u32, words }));
        }
    });
}

#[cfg(test)]
pub(super) mod table {
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
            return Col { top: g.round() as i32, canopy: 0, c0: c565([52.0, 96.0, 190.0]), c1: c565([120.0, 110.0, 96.0]), kind: 2 };
        }
        let n = f64::from(hash(x as i32, z as i32));
        if let Some(t) = tree(x as f32, z as f32) {
            return Col { top: (g + f64::from(t)).round() as i32, canopy: t as u8, c0: c565([52.0 + 18.0 * n, 92.0 + 24.0 * n, 58.0 + 12.0 * n]), c1: c565([134.0, 96.0, 67.0]), kind: 1 };
        }
        Col { top: g.round() as i32, canopy: 0, c0: c565([108.0 + 18.0 * n, 168.0 + 22.0 * n, 118.0 + 12.0 * n]), c1: c565([134.0, 96.0, 67.0]), kind: 0 }
    }
    /// The whole table at once (the tests' and the preview's: the game's goes in stages).
    pub(in crate::strike) fn all(seed: u32, col: &dyn Fn(f64, f64) -> Option<Col>) -> Vec<(usize, Vec<u32>)> {
        let mut w = Work::new(seed, PI / 2.0);
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
        o.extend(vm_tables(&w, &sums, &|_, _| 0.0));
        o
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
    fn the_table_fits_the_pass_data() {
        assert!(VM_W2 + VM_COLS <= 262_144);
        assert!(VM_TILE + VM_TN * VM_TN * 2 <= VM_SHARD);
        assert!(VM_SHARD + VM_SHARDS * VM_SW <= VM_FOUNT);
        assert!(VM_FOUNT + VM_FOUNTS * 8 <= VM_BOULD);
        assert!(VM_BOULD + VM_BOULDS * VM_BW <= VM_PLATE);
        assert_eq!(VM_FLY, Geo::new(37, 0.0).rings[..5].iter().map(|g| g.n).sum::<usize>());
        assert!(VM_PLATE + VM_PLATES * VM_PW <= VM_W0);
    }
}
