//! The Supervolcano's mount: the land swelling into a dome some 600 across and 150 high (VC_SWELL to VC_HUSH), then
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
pub(super) const VM_HALF: i32 = 360;
pub(super) const VM_STEP: i32 = 3;
pub(super) const VM_GW: usize = 241;
const VM_COLS: usize = VM_GW * VM_GW;
/// The tiles the march skips by: VM_TC cells a side, each three words (the land's highest, P's highest, the spires'
/// tallest), a tile's words taking in the tiles round it (the land slides under the march's feet).
const VM_TC: usize = 16;
const VM_TN: usize = 15;
const VM_TILE: usize = VM_BASE + 16;
/// The spires, four words each (when, how tall, x, z); the fountains and the boulders, eight each; the plates, twelve.
const VM_SPIRE: usize = VM_BASE + 700;
pub(super) const VM_SPIRES: usize = 14;
const VM_FOUNT: usize = VM_BASE + 1024;
pub(super) const VM_FOUNTS: usize = 64;
const VM_BOULD: usize = VM_BASE + 1536;
pub(super) const VM_BOULDS: usize = 40;
const VM_PLATE: usize = VM_BASE + 2048;
const VM_PW: usize = 12;
pub(super) const VM_PLATES: usize = 128;
/// The columns' words: the land and the field (what the march reads), the colours, the rest (what the shading reads).
const VM_W0: usize = VM_BASE + 4096;
const VM_W1: usize = VM_W0 + VM_COLS;
const VM_W2: usize = VM_W1 + VM_COLS;
/// The dome's radius, on average.
const VM_RAD: f64 = 300.0;
/// The beats (BEATS.md).
const VC_SWELL: f64 = 7.0;
const VC_HUSH: f64 = 17.0;
/// How much of each column's stack is read, the columns worked out a tick, rows to a query.
const READ_BELOW: u32 = 16;
const READ_ABOVE: u32 = 1;
const PER_STAGE: usize = 3_600;
const READ_ROWS: usize = 40;

/// A smooth bump of noise, 0 to 1.
fn vn(x: f64, z: f64, s: u32) -> f64 {
    let (i, k) = (x.floor(), z.floor());
    let (u, v) = (x - i, z - k);
    let (u, v) = (u * u * (3.0 - 2.0 * u), v * v * (3.0 - 2.0 * v));
    let h = |a: f64, b: f64| mh((a as i32 as u32).wrapping_mul(0x9E37_79B1).wrapping_add(b as i32 as u32), s, 0x6d);
    let (a, b, c, d) = (h(i, k), h(i + 1.0, k), h(i, k + 1.0), h(i + 1.0, k + 1.0));
    (a * (1.0 - u) + b * u) * (1.0 - v) + (c * (1.0 - u) + d * u) * v
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
#[derive(Clone, Copy)]
pub(super) struct Spire {
    pub t0: f64,
    pub h: f64,
    pub x: f64,
    pub z: f64,
    pub rad: f64,
}
/// The dome and how it breaks, for a seed: worked out as the strike starts.
pub(super) struct Geo {
    seed: u32,
    ph: [f64; 4],
    rings: Vec<Ring>,
    plates: Vec<Plate>,
    pub spires: Vec<Spire>,
}
/// A column of the field.
#[derive(Clone, Copy, Default)]
pub(super) struct Cell {
    pub p: f64,
    pub d: f64,
    pub plate: u8,
    pub phase: u8,
}
impl Geo {
    pub fn new(seed: u32) -> Self {
        let ph = [TAU * mh(1, seed, 0x700), TAU * mh(2, seed, 0x700), TAU * mh(3, seed, 0x700), TAU * mh(4, seed, 0x700)];
        let mut g = Geo { seed, ph, rings: Vec::new(), plates: Vec::new(), spires: Vec::new() };
        // (wedges in rings: long down the slope, a star of them round the top, on out past the dome's foot over the land,
        // where only the cracks show)
        let mut first = 0;
        for &(r0, r1, n) in &[(0.0, 66.0, 7usize), (66.0, 140.0, 11), (140.0, 225.0, 16), (225.0, 310.0, 20), (310.0, 400.0, 26), (400.0, 540.0, 31)] {
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
                let e = 12.0;
                let gx = (g.dome(x + e, z) - g.dome(x - e, z)) / (2.0 * e);
                let gz = (g.dome(x, z + e) - g.dome(x, z - e)) / (2.0 * e);
                // (each plate its own way: a lift, a tilt; near the top more, a few much more: blocks heaved up on edge
                // and blocks dropped)
                let big = (mh(k, seed, 0x703) - 0.5) * 2.0;
                let heave = if mh(k, seed, 0x704) < 0.14 { 0.09 * (0.3 + s) } else { 0.0 };
                let tilt = 0.0005 + 0.0010 * s;
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
        g.spires = (0..VM_SPIRES)
            .map(|i| {
                let k = i as u32;
                let u = (i as f64 + 0.5 * mh(k, seed, 0x710)) / VM_SPIRES as f64;
                let a = TAU * (0.618_034 * i as f64 + 0.2 * mh(k, seed, 0x711));
                // (the first the highest up, on down the flanks as it goes on, late ones anywhere)
                let r = 40.0 + 210.0 * (0.25 + 0.75 * mh(k, seed, 0x712)).powf(0.8);
                Spire {
                    t0: 10.4 + 6.0 * u.powf(0.8),
                    h: 26.0 + 46.0 * mh(k, seed, 0x713).powf(1.4) * (1.0 - 0.4 * r / 250.0),
                    x: r * a.cos(),
                    z: r * a.sin(),
                    rad: 9.0 + 11.0 * mh(k, seed, 0x714),
                }
            })
            .collect();
        g
    }
    /// The dome at (x, z) from the vent: its share of the height, 0 past its foot, about 1 at the top. Never a circle,
    /// never a bowl: lobed round its foot, ridged over its back.
    pub fn dome(&self, x: f64, z: f64) -> f64 {
        let a = z.atan2(x);
        let [p0, p1, p2, _] = self.ph;
        let rad = VM_RAD * (1.0 + 0.1 * (2.0 * a + p0).sin() + 0.075 * (3.0 * a + p1).sin() + 0.04 * (5.0 * a + p2).sin());
        let u = x.hypot(z) / rad;
        if u >= 1.0 {
            return 0.0;
        }
        let b = (1.0 - u * u).powi(2);
        let s = self.seed;
        let ridges = vn(x / 170.0 + 3.3, z / 170.0, s) - 0.5;
        let fine = vn(x / 66.0, z / 66.0 + 7.1, s ^ 7) - 0.5;
        b * (1.0 + 0.42 * ridges + 0.17 * fine)
    }
    /// The field at column (x, z) from the vent.
    pub fn cell(&self, x: f64, z: f64) -> Cell {
        let s = self.seed;
        // (the edges wander: long bends, jagged close to)
        let (wx, wz) = (
            x + 22.0 * (vn(x / 96.0, z / 96.0, s ^ 11) - 0.5) + 5.5 * (vn(x / 25.0, z / 25.0, s ^ 12) - 0.5) + 1.6 * (vn(x / 8.0, z / 8.0, s ^ 15) - 0.5),
            z + 22.0 * (vn(x / 96.0 + 5.0, z / 96.0, s ^ 13) - 0.5) + 5.5 * (vn(x / 25.0, z / 25.0 + 3.0, s ^ 14) - 0.5) + 1.6 * (vn(x / 8.0, z / 8.0 + 1.0, s ^ 16) - 0.5),
        );
        let r = wx.hypot(wz).max(1.0);
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
                let d = (0.56 * dr).hypot(dt);
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
        if s0 > 0.0 {
            let (cx, cz) = ((x / 34.0).floor(), (z / 34.0).floor());
            let (mut dn, mut v) = (1.0e18f64, 0.0);
            for b in -1..=1 {
                for c in -1..=1 {
                    let (ci, ck) = (cx + f64::from(b), cz + f64::from(c));
                    let id = (ci as i32 as u32).wrapping_mul(0x9E37_79B1).wrapping_add(ck as i32 as u32);
                    let (px, pz) = ((ci + mh(id, s, 0x720)) * 34.0, (ck + mh(id, s, 0x721)) * 34.0);
                    let d = (x - px).hypot(z - pz);
                    if d < dn {
                        dn = d;
                        v = mh(id, s, 0x722) - 0.5;
                    }
                }
            }
            p += v * 0.022 * on * (0.4 + s0);
        }
        Cell { p, d: 0.5 * (d2 - d1), plate: best as u8, phase: k.phase }
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
    /// How much each column's height is of a spire: spire + 1, and its share (0 to 1).
    sp: Vec<(u8, u8)>,
}
impl Work {
    fn new(seed: u32) -> Self {
        Work { geo: Rc::new(Geo::new(seed)), cells: vec![Cell::default(); VM_COLS], next_cell: 0, cols: vec![None; VM_COLS], known: 0, sp: vec![(0, 0); VM_COLS] }
    }
    /// The next `n` columns of the field; whether that was the last of them.
    fn field(&mut self, n: usize) -> bool {
        let end = (self.next_cell + n).min(VM_COLS);
        crate::meter::spend(2_400 * (end - self.next_cell) as u64);
        for j in self.next_cell..end {
            let (x, z) = col_xz(j);
            self.cells[j] = self.geo.cell(x, z);
        }
        self.next_cell = end;
        if end == VM_COLS {
            self.spires();
            return true;
        }
        false
    }
    fn spires(&mut self) {
        let geo = self.geo.clone();
        for (id, s) in geo.spires.iter().enumerate() {
            let k = id as u32;
            let n = (s.rad * 1.4 / f64::from(VM_STEP)).ceil() as i32 + 1;
            let (ci, ck) = (((s.x + f64::from(VM_HALF)) / f64::from(VM_STEP)).round() as i32, ((s.z + f64::from(VM_HALF)) / f64::from(VM_STEP)).round() as i32);
            // (not a cone: a few columns of rock thrust up together, each a slab with straight sides and a broken, tilted top)
            struct Shard {
                x: f64,
                z: f64,
                tall: f64,
                rad: f64,
                face: [(f64, f64); 5],
                tx: f64,
                tz: f64,
            }
            let shards: Vec<Shard> = (0..4u32)
                .map(|b| {
                    let m = |c: u32| mh(k * 7 + b, geo.seed, c);
                    let a = TAU * m(0x730);
                    let o = if b == 0 { 0.0 } else { s.rad * (0.45 + 0.5 * m(0x731)) };
                    let rot = TAU * m(0x734);
                    let face = [0.0, 1.0, 2.0, 3.0, 4.0].map(|i: f64| {
                        let t = rot + i * TAU / 5.0 + 0.4 * (mh(k * 13 + b + i as u32, geo.seed, 0x735) - 0.5);
                        (t.cos(), t.sin())
                    });
                    let lean = TAU * m(0x736);
                    Shard {
                        x: s.x + o * a.cos(),
                        z: s.z + o * a.sin(),
                        tall: if b == 0 { 1.0 } else { 0.45 + 0.45 * m(0x732) },
                        rad: s.rad * if b == 0 { 0.62 } else { 0.32 + 0.3 * m(0x733) },
                        face,
                        tx: 0.05 * lean.cos(),
                        tz: 0.05 * lean.sin(),
                    }
                })
                .collect();
            for dk in -n..=n {
                for di in -n..=n {
                    let (i, c) = (ci + di, ck + dk);
                    if i < 0 || c < 0 || i >= VM_GW as i32 || c >= VM_GW as i32 {
                        continue;
                    }
                    let j = c as usize * VM_GW + i as usize;
                    let (x, z) = col_xz(j);
                    let mut h = 0.0f64;
                    for b in &shards {
                        let (dx, dz) = (x - b.x, z - b.z);
                        // (a polygon's distance from its middle, its sides straight)
                        let u = b.face.iter().fold(0.0f64, |m, f| m.max((dx * f.0 + dz * f.1) / b.rad));
                        if u < 1.0 {
                            let top = b.tall + b.tx * dx + b.tz * dz;
                            h = h.max(top * (1.0 - u.powi(6)).max(0.0).sqrt().min(1.0));
                        }
                    }
                    if h > 0.004 {
                        let v = (h.min(1.0) * 255.0).round() as u8;
                        if v > self.sp[j].1 {
                            self.sp[j] = (id as u8 + 1, v);
                        }
                    }
                }
            }
        }
    }
}
/// Column j's place, from the vent.
fn col_xz(j: usize) -> (f64, f64) {
    let (i, k) = ((j % VM_GW) as i32, (j / VM_GW) as i32);
    (f64::from(i * VM_STEP - VM_HALF), f64::from(k * VM_STEP - VM_HALF))
}

/// The pass's words. `land` gives a column not read (the land's rough height, from the vent's ground, or none).
pub(super) fn vm_words(w: &Work, land: &dyn Fn(f64, f64) -> f64) -> Vec<(usize, Vec<u32>)> {
    crate::meter::spend(300 * VM_COLS as u64);
    // (what wasn't read takes the colours of the nearest that was)
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
    // (trees are no shape at three blocks a column: a wood is a low, soft roof over the ground)
    let mut can = vec![0f32; VM_COLS];
    for k in 2..VM_GW - 2 {
        for i in 2..VM_GW - 2 {
            let mut sum = 0u32;
            for b in k - 2..=k + 2 {
                for a in i - 2..=i + 2 {
                    sum += w.cols[b * VM_GW + a].map_or(0, |c| u32::from(c.canopy));
                }
            }
            can[k * VM_GW + i] = sum as f32 / 25.0;
        }
    }
    let mut w0 = Vec::with_capacity(VM_COLS);
    let mut w2 = Vec::with_capacity(VM_COLS);
    let mut w1 = Vec::with_capacity(VM_COLS);
    let mut tiles = vec![[f32::MIN, f32::MIN, 0.0f32]; VM_TN * VM_TN];
    let (mut lo, mut hi) = (f32::MAX, f32::MIN);
    for j in 0..VM_COLS {
        let (x, z) = col_xz(j);
        let cell = w.cells[j];
        let (top, canopy) = w.cols[j].map_or_else(|| (land(x, z), 0), |c| (f64::from(c.top - i32::from(c.canopy)) + 0.7 * f64::from(can[j]), c.canopy));
        let h = ((top + 512.0) * 2.0).round().clamp(0.0, 2047.0) as u32;
        let p = (((cell.p + 0.25) / 1.6) * 2047.0).round().clamp(0.0, 2047.0) as u32;
        let d = (cell.d * 4.0).round().clamp(0.0, 127.0) as u32;
        let (sid, sv) = w.sp[j];
        w0.push(h | p << 11 | d << 22 | u32::from(cell.phase & 3) << 29 | u32::from(sid > 0) << 31);
        w1.push(if c0[j] != 0 { c0[j] | c1[j] << 16 } else { c565([95.0, 135.0, 60.0]) | c565([134.0, 96.0, 67.0]) << 16 });
        w2.push(u32::from(cell.plate) | u32::from(sid) << 8 | u32::from(sv) << 16 | u32::from(kk[j] & 7) << 24 | u32::from(canopy.min(31)) << 27);
        // (a tile's words take in the columns of the tiles round it)
        let (i, k) = (j % VM_GW, j / VM_GW);
        let (ti, tk) = ((i / VM_TC).min(VM_TN - 1), (k / VM_TC).min(VM_TN - 1));
        let (tl, pl) = (top as f32, cell.p as f32);
        let sh = if sid > 0 { w.geo.spires[sid as usize - 1].h as f32 } else { 0.0 };
        lo = lo.min(tl);
        hi = hi.max(tl);
        for b in ti.saturating_sub(1)..(ti + 2).min(VM_TN) {
            for c in tk.saturating_sub(1)..(tk + 2).min(VM_TN) {
                let t = &mut tiles[c * VM_TN + b];
                t[0] = t[0].max(tl);
                t[1] = t[1].max(pl);
                t[2] = t[2].max(sh);
            }
        }
    }
    let tw: Vec<u32> = tiles.iter().flat_map(|t| t.iter().map(|v| v.to_bits())).collect();
    let spires: Vec<u32> = w.geo.spires.iter().flat_map(|s| [s.t0, s.h, s.x, s.z].map(|v| (v as f32).to_bits())).collect();
    let head = vec![1f32.to_bits(), lo.to_bits(), hi.to_bits()];
    vec![(VM_BASE, head), (VM_TILE, tw), (VM_SPIRE, spires), (VM_W0, w0), (VM_W1, w1), (VM_W2, w2)]
}

/// The columns of rows `a..b` of the square.
fn read_part(bx: i32, bz: i32, a: usize, b: usize) -> Vec<(i32, i32)> {
    (a..b.min(VM_GW)).flat_map(|k| (0..VM_GW).map(move |i| (bx + i as i32 * VM_STEP - VM_HALF, bz + k as i32 * VM_STEP - VM_HALF))).collect()
}

type Shared = Rc<RefCell<Work>>;

/// The mount's part of the plan: the field worked out as it starts, the land read, whatever the terrain setting, since
/// the mount is only drawn.
pub(super) fn vm_plan(p: &mut Plan, seed: u32, hf: Rc<RefCell<Hf>>) {
    let w: Shared = Rc::new(RefCell::new(Work::new(seed)));
    {
        let w = w.clone();
        p.later(0.1, move |q| vm_field_step(q, w, 0.1));
    }
    let parts = VM_GW.div_ceil(READ_ROWS);
    let tags: Rc<Vec<u32>> = Rc::new((0..parts).map(|_| crate::columns::new_tag()).collect());
    for part in 0..parts {
        let tags = tags.clone();
        let t = 0.6 + 0.05 * part as f32;
        p.later(t, move |q| {
            let columns = read_part(q.bx, q.bz, part * READ_ROWS, (part + 1) * READ_ROWS);
            q.ev.push((t, Act::Read { tag: tags[part], columns, below: READ_BELOW, above: READ_ABOVE }));
        });
    }
    p.later(1.0, move |q| vm_land_step(q, w, hf, tags, 0, 0, 1.0, 0));
}

fn vm_field_step(q: &mut Plan, w: Shared, at: f32) {
    if !w.borrow_mut().field(PER_STAGE) {
        q.later(at + 0.05, move |q| vm_field_step(q, w, at + 0.05));
    }
}

/// The land's answers worked through, a part at a time, waiting for each; columns not loaded yet asked again until 5.4 s;
/// the pass given what there is after each round and in any case by 5.6 s.
#[allow(clippy::too_many_arguments)]
fn vm_land_step(q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, tags: Rc<Vec<u32>>, part: usize, start: usize, at: f32, round: u32) {
    let next = |q: &mut Plan, w: Shared, hf: Rc<RefCell<Hf>>, tags: Rc<Vec<u32>>, part: usize, start: usize| {
        q.later(at + 0.05, move |q| vm_land_step(q, w, hf, tags, part, start, at + 0.05, round));
    };
    if part >= tags.len() {
        vm_send(q, &w, &hf, at);
        let (bx, bz) = (q.bx, q.bz);
        if round < 6 && at < 5.0 {
            let missing: Vec<(i32, i32)> = {
                let wb = w.borrow();
                (0..VM_COLS).filter(|&j| wb.cols[j].is_none()).map(|j| (bx + ((j % VM_GW) as i32) * VM_STEP - VM_HALF, bz + ((j / VM_GW) as i32) * VM_STEP - VM_HALF)).collect()
            };
            crate::meter::spend(30 * VM_COLS as u64);
            if !missing.is_empty() {
                let tag = crate::columns::new_tag();
                let t = at + 0.7;
                q.later(t, move |q| {
                    q.ev.push((t, Act::Read { tag, columns: missing, below: READ_BELOW, above: READ_ABOVE }));
                    vm_land_step(q, w, hf, Rc::new(vec![tag]), 0, 0, t + 0.1, round + 1);
                });
            }
        }
        return;
    }
    let Some(a) = crate::columns::get(tags[part]) else {
        if at < 5.6 {
            next(q, w, hf, tags, part, start);
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
        crate::columns::take(tags[part]);
        next(q, w, hf, tags, part + 1, 0);
    } else {
        next(q, w, hf, tags, part, end);
    }
}

fn vm_send(q: &mut Plan, w: &Shared, hf: &Rc<RefCell<Hf>>, at: f32) {
    let wb = w.borrow();
    if wb.next_cell < VM_COLS {
        return;
    }
    let h = hf.borrow();
    for (index, words) in vm_words(&wb, &|x, z| h.at(x, z)) {
        q.ev.push((at, Act::Words { index: index as u32, words }));
    }
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
            return Col { top: (g + f64::from(t)).round() as i32, canopy: t as u8, c0: c565([32.0 + 18.0 * n, 62.0 + 24.0 * n, 26.0 + 12.0 * n]), c1: c565([134.0, 96.0, 67.0]), kind: 1 };
        }
        Col { top: g.round() as i32, canopy: 0, c0: c565([62.0 + 18.0 * n, 118.0 + 28.0 * n, 44.0 + 12.0 * n]), c1: c565([134.0, 96.0, 67.0]), kind: 0 }
    }
    /// The whole table at once (the tests' and the preview's: the game's goes in stages).
    pub(in crate::strike) fn all(seed: u32, col: &dyn Fn(f64, f64) -> Option<Col>) -> Vec<(usize, Vec<u32>)> {
        let mut w = Work::new(seed);
        while !w.field(PER_STAGE) {}
        for j in 0..VM_COLS {
            let (x, z) = col_xz(j);
            w.cols[j] = col(x, z);
        }
        vm_words(&w, &|_, _| 0.0)
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
    fn the_dome_is_about_600_wide_and_its_plates_cover_it() {
        let g = Geo::new(37);
        let top = (0..2000).map(|i| { let a = i as f64 * 0.77; let r = i as f64 * 0.06; g.dome(r * a.cos(), r * a.sin()) }).fold(0.0, f64::max);
        assert!((0.8..1.35).contains(&top), "{top}");
        for k in 0..4 {
            let a = k as f64 * 1.3;
            assert!(g.dome(180.0 * a.cos(), 180.0 * a.sin()) > 0.1);
            assert_eq!(g.dome(350.0 * a.cos(), 350.0 * a.sin()), 0.0);
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
        assert!(VM_TILE + VM_TN * VM_TN * 3 <= VM_SPIRE);
        assert!(VM_SPIRE + VM_SPIRES * 4 <= VM_FOUNT);
        assert!(VM_FOUNT + VM_FOUNTS * 8 <= VM_BOULD);
        assert!(VM_BOULD + VM_BOULDS * 8 <= VM_PLATE);
        assert!(VM_PLATE + VM_PLATES * VM_PW <= VM_W0);
    }
}
