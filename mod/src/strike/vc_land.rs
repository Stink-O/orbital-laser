//! What the Supervolcano leaves: real blocks, terrain on only, going in behind the wall of ash from VC_COLLAPSE.
//!
//! The caldera (`Shape`: about 560 across, its edge scalloped and slumped, 90 deep): a lake of dark crust (`lake_edit`:
//! big irregular plates, broken further in places, thin veins of lava towards the ring's vents dimming to dark seams away
//! from them, a few open pools, lava a tenth of it), a few huge blocks of the land dropped whole and standing in it, their
//! beds still in them (`Drop`). Its walls (`relief`): a scarp, slumped blocks each dropped and turned back on its own, fans
//! of rubble at the foot, their faces in dark beds (`beds_edit`) carried down with what slumped. The rim (`Ctx::rim`):
//! slabs of the land broken and tilted up on the ring's own apron of ash, a crown of wedges where it burst hardest.
//!
//! Round it (`out_edit`) one deposit (ignimbrite) out to about 440: one tone with a fine grain, wet streaks along the
//! flows, ponded deep in the low ground, a skin on the ridges so the land's shape shows through. Water under it is filled
//! to a dark wet plain. Past its wandering edge the land fades through patches of dust (`dust_cover`), pumice floating
//! on the water, to the odd patch by VC_FAR, as far as the world has chunks loaded (`vc_far_chunk`, no read). The trees
//! grade (`fate`, `stand_edit`, `vc_fell`): charred trunks lying pointing away and burnt stumps, then bare black trunks,
//! then scorched trees with their crowns going brown, then the leaves only. Water and lava the walls cut into are
//! sealed. The chunks within VC_LOAD (about 4,000) are force-loaded from the moment it fires, so nothing stops at a
//! line: the edge of what's force-loaded has to lie where the land has all but faded out.
//!
//! The work goes a chunk at a time (`vc_chunk`), in order of when each is due: past the ring as the wall of ash goes over
//! it, inside the ring from the edge in as fast as the world takes the blocks (VC_RATE), so every chunk's edits go in on
//! one tick and the game redraws it once. Everything that shows as a face is worked out from a chunk's relief (`Rel`);
//! what lies round the caldera comes from a read (`read_columns`, a ring of parts). A run costs the game's fuel some 1,000
//! instructions on its way out, so a column is as few runs as it can be; and the waiting ones are capped (VC_QUEUE).
use super::nuke::{Kind, LOG_X, LOG_Z, kind};
use super::volcano::{Hf, VC_COLLAPSE, vc_front};
use super::*;
use std::cell::RefCell;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The land read reaches from VC_READ0 to VC_READ, the square of columns round the vent.
const VC_READ0: f64 = 236.0;
const VC_READ: i32 = 612;
const VC_GW: i32 = 2 * VC_READ + 1;
const VC_CHUNKS: i32 = 2 * (VC_READ / 16 + 3);
const VC_BELOW: u32 = 34;
const VC_ABOVE: u32 = 1;
const VC_PARTS: i32 = 248;
/// The chunks within this are force-loaded.
pub(super) const VC_LOAD: f64 = 576.0;
/// What each reaches to: the rim, the ignimbrite (the sheet's edge; its dust goes on past it, the trees' fates are by VC_FELLED).
const VC_RIM: f64 = 320.0;
const VC_IGN: f64 = 440.0;
/// The dust reaches this far, where the world has the land loaded (past what's force-loaded, round the player).
const VC_FAR: f64 = 1050.0;
/// The depth of the caldera.
const VC_DEEP: f64 = 90.0;
/// Past this the chunks go in with the wall; inside it from the edge in, VC_RATE blocks a second (PK_RATE's class).
const VC_IN: f64 = 262.0;
const VC_RATE: f64 = 1_200_000.0;
/// The most a stage's chunks may take the tick's count to. The chunks' count reads 2 to 3 times low by the game's
/// (`mod_soak` traced, by distance out, on every land): this keeps a stage's real work under some 15M, its last chunk
/// (at most 3M) and what else the tick does under 20M, 40% of a tick's fuel.
const VC_TICK: u64 = 4_800_000;
/// How long ahead of its time a chunk's edits are worked out.
const VC_LEAD: f32 = 4.0;
/// The most runs worked out and waiting to go in: a mod has 64 MB, a run takes 32 bytes.
const VC_QUEUE: usize = 200_000;
/// No more chunks are worked out while the mod holds this much (`mem`): the edits waiting behind a slow frame (`pace`) are
/// past `VC_QUEUE`'s count once they fall due, and they can pile up for as long as the frames stay slow.
const VC_HOLD: usize = 24 << 20;
/// How many parts of the read may be out at once (one is asked a tick, two taken in). Everything hangs on this. An answer
/// is 400 KB, and those asked ahead of the ones taken in add up in the mod's 64 MB (a late world hands over everything it
/// has at once); and each is a stretch of the server thread's time, so reads asked faster than they are answered fall
/// behind the server's tick, and the client's clock with it (`in_world`). Enough, though, that a slow world still gets
/// through the 248 parts before the land is wanted, with answers as late as a second or two.
const VC_FLIGHT: usize = 10;
/// When the chunks past the read are asked after.
const VC_FAR_ASK: f32 = 44.0;
/// A chunk's blocks inside the ring, for the pace.
const VC_COL: f64 = 118.0;
/// What the work of a column is reckoned at, in instructions, besides what `Blocks` counts of its runs.
const VC_UNIT: u64 = 300;

/// A column as read, packed into a 32-bit word (0: not read), 6 MB of them.
#[derive(Clone, Copy, Debug, Default)]
struct Col {
    g: i32,
    /// At most 35 over `g`: the read goes no further.
    top: i32,
    /// At most 40.
    trunk: u8,
    leaves: bool,
    /// 1 grass, 2 dirt.
    ground: u8,
    fluid: bool,
    /// Water deeper than the read reaches: `g` is no more than how far it read.
    deep: bool,
}
impl Col {
    /// What ash lies on: the ground, or the water's top.
    fn base(&self) -> i32 {
        if self.fluid { self.top } else { self.g }
    }
    fn pack(&self) -> u32 {
        1 | u32::from(self.fluid) << 1
            | u32::from(self.ground) << 2
            | u32::from(self.leaves) << 4
            | u32::from(self.deep) << 5
            | u32::from(self.trunk & 63) << 6
            | ((self.top - self.g).clamp(0, 63) as u32) << 12
            | ((self.g + 2048).clamp(0, 4095) as u32) << 18
    }
    fn unpack(w: u32) -> Option<Col> {
        if w & 1 == 0 {
            return None;
        }
        let g = (w >> 18 & 4095) as i32 - 2048;
        Some(Col {
            fluid: w >> 1 & 1 != 0,
            ground: (w >> 2 & 3) as u8,
            leaves: w >> 4 & 1 != 0,
            deep: w >> 5 & 1 != 0,
            trunk: (w >> 6 & 63) as u8,
            g,
            top: g + (w >> 12 & 63) as i32,
        })
    }
}

/// The chunks of the read the world had not loaded yet, in the order found: a chunk is loaded or not as a whole, so one
/// that wasn't is one entry here, not a place for each of its columns (there can be a million of those).
struct Missing {
    /// Whether each chunk (from the read's corner) is in the list.
    listed: Vec<bool>,
    list: std::collections::VecDeque<(i32, i32)>,
}
impl Default for Missing {
    fn default() -> Self {
        Missing { listed: vec![false; (VC_CHUNKS * VC_CHUNKS) as usize], list: Default::default() }
    }
}
impl Missing {
    /// The chunks a side the read reaches over, whatever the vent's place in its own chunk.
    fn index(cx: i32, cz: i32, bx: i32, bz: i32) -> Option<usize> {
        let (i, k) = (cx - (bx >> 4) + VC_CHUNKS / 2, cz - (bz >> 4) + VC_CHUNKS / 2);
        ((0..VC_CHUNKS).contains(&i) && (0..VC_CHUNKS).contains(&k)).then_some((k * VC_CHUNKS + i) as usize)
    }
    /// Column (x, z) answered as not loaded.
    fn add(&mut self, x: i32, z: i32, bx: i32, bz: i32) {
        let (cx, cz) = (x >> 4, z >> 4);
        if let Some(j) = Self::index(cx, cz, bx, bz)
            && !self.listed[j]
        {
            self.listed[j] = true;
            self.list.push_back((cx, cz));
        }
    }
    /// The next chunks' columns still to be read, about `n` of them.
    fn take(&mut self, cols: &[u32], bx: i32, bz: i32, n: usize) -> Vec<(i32, i32)> {
        let mut out = Vec::with_capacity(n + 256);
        let (q0, q1) = (VC_READ0 * VC_READ0, f64::from(VC_READ * VC_READ));
        while out.len() < n {
            let Some((cx, cz)) = self.list.pop_front() else { break };
            if let Some(j) = Self::index(cx, cz, bx, bz) {
                self.listed[j] = false;
            }
            crate::meter::spend(40 * 256);
            for z in cz * 16..cz * 16 + 16 {
                for x in cx * 16..cx * 16 + 16 {
                    let (dx, dz) = (x - bx, z - bz);
                    let e = f64::from(dx * dx + dz * dz);
                    if e > q0 && e <= q1 && cols.get(((dz + VC_READ) * VC_GW + dx + VC_READ) as usize) == Some(&0) {
                        out.push((x, z));
                    }
                }
            }
        }
        out
    }
}

/// How far out part `part` of the read reaches: rings from VC_READ0 out, as many columns in each.
fn read_reach(part: i32) -> f64 {
    let (a, b) = (VC_READ0 * VC_READ0, f64::from(VC_READ * VC_READ));
    (a + (b - a) * f64::from(part) / f64::from(VC_PARTS)).sqrt()
}
/// The columns of ring `part`.
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let (r0, r1) = (read_reach(part), read_reach(part + 1));
    let (q0, q1) = (r0 * r0, r1 * r1);
    let n = r1.ceil() as i32;
    let mut out = Vec::new();
    for dz in -n..=n {
        let d = f64::from(dz * dz);
        if d > q1 {
            continue;
        }
        let wo = (q1 - d).sqrt().floor() as i32;
        let wi = if q0 >= d { (q0 - d).sqrt().floor() as i32 } else { -1 };
        let keep = |dx: i32| {
            let e = d + f64::from(dx * dx);
            e > q0 && e <= q1
        };
        if wi < 0 {
            out.extend((-wo..=wo).filter(|&dx| keep(dx)).map(|dx| (bx + dx, bz + dz)));
        } else {
            out.extend((-wo..-wi).chain(wi + 1..=wo).filter(|&dx| keep(dx)).map(|dx| (bx + dx, bz + dz)));
        }
    }
    crate::meter::spend(60 * out.len() as u64 + 200 * (2 * n + 1) as u64);
    out
}
/// One answer taken in: each column's ground and what stands on it; those not loaded kept to be asked again.
fn take_in(cols: &mut [u32], missing: &mut Missing, a: &crate::columns::Answer, bx: i32, bz: i32) {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    crate::meter::spend(2_000 + 4_000 * a.palette.len() as u64);
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else {
            crate::meter::spend(60);
            missing.add(x, z, bx, bz);
            continue;
        };
        let base = surface - a.below;
        crate::meter::spend(200 + 12 * blocks.len() as u64);
        let mut c = Col::default();
        let mut top = None;
        let mut g = None;
        for j in (0..blocks.len()).rev() {
            let (k, w) = kinds.get(blocks[j] as usize).copied().unwrap_or((Kind::Loose, 0));
            match k {
                Kind::Air => {}
                Kind::Ground => {
                    top.get_or_insert(base + j as i32);
                    g = Some(j);
                    c.ground = w;
                    break;
                }
                Kind::Fluid => {
                    c.fluid = true;
                    top.get_or_insert(base + j as i32);
                }
                Kind::Leaves => {
                    c.leaves = true;
                    top.get_or_insert(base + j as i32);
                }
                _ => {
                    top.get_or_insert(base + j as i32);
                }
            }
        }
        let (ii, kk) = (x - bx + VC_READ, z - bz + VC_READ);
        let Some(gj) = g else {
            // (the sea, or a lake deeper than it reads)
            if c.fluid && (0..VC_GW).contains(&ii) && (0..VC_GW).contains(&kk) {
                c.deep = true;
                c.g = base;
                c.top = top.unwrap_or(base);
                cols[(kk * VC_GW + ii) as usize] = c.pack();
            }
            continue;
        };
        c.g = base + gj as i32;
        c.top = top.unwrap_or(c.g);
        let mut n = 0;
        while gj + 1 + n < blocks.len() {
            match kinds.get(blocks[gj + 1 + n] as usize) {
                Some(&(Kind::Log, _)) => n += 1,
                _ => break,
            }
        }
        c.trunk = n.min(40) as u8;
        if (0..VC_GW).contains(&ii) && (0..VC_GW).contains(&kk) {
            cols[(kk * VC_GW + ii) as usize] = c.pack();
        }
    }
}

// ---- the shape --------------------------------------------------------------------------------------------------
/// One of the huge blocks of the land left standing in the lake, dropped whole with the floor: where, its half sizes
/// along its two axes (its axis turned `ca`, `sa`), how high it stands over the lake and how its top tilts.
#[derive(Clone, Copy, Default)]
struct Drop {
    x: f64,
    z: f64,
    ca: f64,
    sa: f64,
    ru: f64,
    rv: f64,
    h: f64,
    tilt: f64,
    ph: f64,
}
/// A hot place in the lake (a vent's mouth towards the ring, or an open pool).
#[derive(Clone, Copy, Default)]
struct Hot {
    x: f64,
    z: f64,
    r: f64,
    /// How hot, for a vent; an open pool's is 0.
    k: f64,
}
const VC_DROPS: usize = 7;
const VC_HOTS: usize = 15;
const VC_BANDS: usize = 192;

#[derive(Clone, Copy)]
pub(super) struct Shape {
    cx: f64,
    cz: f64,
    seed: u32,
    ph: [f64; 5],
    gy: i32,
    /// The caldera's floor.
    floor: i32,
    drops: [Drop; VC_DROPS],
    hots: [Hot; VC_HOTS],
    /// The rock by depth under the land: an index into ROCKS for each block's depth, in beds of two to nine.
    beds: [u8; VC_BANDS],
}
impl Shape {
    fn new(cx: f64, cz: f64, seed: u32, gy: i32) -> Self {
        let ph = [1u32, 2, 3, 4, 5].map(|k| TAU * mh(k, seed, 0xc7));
        let mut s = Shape { cx, cz, seed, ph, gy, floor: gy - VC_DEEP as i32, drops: [Drop::default(); VC_DROPS], hots: [Hot::default(); VC_HOTS], beds: [0; VC_BANDS] };
        // the beds, darker with depth, a pale ash bed now and then
        let mut d = 0usize;
        let mut k = 0u32;
        while d < VC_BANDS {
            let h = mh(k, seed, 0xd1);
            let mut n = 2 + (h * h * 8.0) as usize;
            let deep = d as f64 / 120.0;
            let p = mh(k, seed, 0xd2);
            let rock = if p < 0.08 {
                // (a thin ash bed, a thin baked soil)
                n = 1 + n / 4;
                if mh(k, seed, 0xd3) < 0.4 { R_PALE } else { R_BAKED }
            } else {
                // (mostly by the depth, some of each everywhere)
                let q = (deep + 0.42 * mh(k, seed, 0xd4)).min(1.25);
                if q < 0.34 {
                    R_TUFF
                } else if q < 0.6 {
                    R_SLATE
                } else if q < 0.85 {
                    R_BASALT
                } else {
                    R_BLACK
                }
            };
            for j in d..(d + n).min(VC_BANDS) {
                s.beds[j] = rock;
            }
            d += n;
            k += 1;
        }
        // the hot places: vents along the wall's foot, a few pools by them, one or two out in the lake
        let (mut i, a0) = (0, TAU * mh(9, seed, 0xd5));
        for v in 0..6 {
            let a = a0 + TAU * (f64::from(v) + 0.55 * mh(v as u32, seed, 0xd6)) / 6.0;
            let r = s.edge(a) - 84.0 - 26.0 * mh(v as u32, seed, 0xd7);
            s.hots[i] = Hot { x: cx + r * a.cos(), z: cz + r * a.sin(), r: 56.0 + 44.0 * mh(v as u32, seed, 0xd8), k: 0.65 + 0.35 * mh(v as u32, seed, 0xd9) };
            i += 1;
            // (its pool, between the vent and the wall if it can)
            let (ra, rr) = (a + 0.16 * (mh(v as u32, seed, 0xda) - 0.5), r + 14.0 - 34.0 * mh(v as u32, seed, 0xdb));
            s.hots[i] = Hot { x: cx + rr * ra.cos(), z: cz + rr * ra.sin(), r: 15.0 + 25.0 * mh(v as u32, seed, 0xdc).powi(2), k: 0.0 };
            i += 1;
        }
        for v in 0..3u32 {
            let (a, r) = (TAU * mh(v, seed, 0xdd), 40.0 + 110.0 * mh(v, seed, 0xde));
            s.hots[i] = Hot { x: cx + r * a.cos(), z: cz + r * a.sin(), r: 7.0 + 10.0 * mh(v, seed, 0xdf), k: 0.0 };
            i += 1;
        }
        // the blocks standing in the lake: spread round it, none on another
        let a0 = TAU * mh(21, seed, 0xe0);
        for (n, d) in s.drops.iter_mut().enumerate() {
            let k = n as u32;
            let a = a0 + TAU * (n as f64 + 0.6 * mh(k, seed, 0xe1)) / VC_DROPS as f64;
            let edge = VC_RING_F + 9.0 * (3.0 * a + ph[0]).sin();
            let r = (edge - 96.0) * (0.3 + 0.62 * mh(k, seed, 0xe2).sqrt());
            let turn = a + 0.9 * (mh(k, seed, 0xe3) - 0.5);
            *d = Drop {
                x: cx + r * a.cos(),
                z: cz + r * a.sin(),
                ca: turn.cos(),
                sa: turn.sin(),
                ru: 14.0 + 20.0 * mh(k, seed, 0xe4),
                rv: 22.0 + 30.0 * mh(k, seed, 0xe5),
                h: 15.0 + 32.0 * mh(k, seed, 0xe6),
                tilt: 0.1 + 0.3 * mh(k, seed, 0xe7),
                ph: TAU * mh(k, seed, 0xe8),
            };
        }
        s
    }
    /// The caldera's edge at bearing a: wandering, bitten into in scallops where its walls slumped.
    fn edge(&self, a: f64) -> f64 {
        let p = self.ph;
        VC_RING_F + 9.0 * (3.0 * a + p[0]).sin() + 7.0 * (5.0 * a + p[1]).sin() + 4.5 * (11.0 * a + p[2]).sin() + 2.5 * (23.0 * a + p[3]).sin() - 12.0 * (7.0 * a + p[4]).sin().abs()
    }
}
const VC_RING_F: f64 = 284.0;

/// A number from 0 to 1 for `k`, cheaply (a block's pick, thousands of them a stage).
fn pick(k: i32, seed: u32) -> f64 {
    f64::from(pcg(k as u32 ^ seed) >> 16) / 65536.0
}
/// Smooth noise from 0 to 1, a cheaper `vnoise` (one hash a corner): thousands of these a chunk.
fn qnoise(x: f64, z: f64, scale: f64, seed: u32) -> f64 {
    crate::meter::spend(110);
    let (fx, fz) = (x / scale, z / scale);
    let (ix, iz) = (fx.floor(), fz.floor());
    let (tx, tz) = (fx - ix, fz - iz);
    let (sx, sz) = (tx * tx * (3.0 - 2.0 * tx), tz * tz * (3.0 - 2.0 * tz));
    let (i, k) = (ix as i32 as u32, iz as i32 as u32);
    let h = |i: u32, k: u32| f64::from(pcg(i.wrapping_mul(73_856_093) ^ k.wrapping_mul(19_349_663) ^ seed) >> 16) / 65536.0;
    let (a, b, c, d) = (h(i, k), h(i + 1, k), h(i, k + 1), h(i + 1, k + 1));
    a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz
}
/// Smooth noise round the vent: `n` cells a turn of bearing `a` (it closes up), and along `v` (its cells a unit long).
fn ring_noise(a: f64, n: i32, v: f64, seed: u32) -> f64 {
    crate::meter::spend(110);
    let fa = a / TAU * f64::from(n);
    let (ia, iv) = (fa.floor(), v.floor());
    let (ta, tv) = (fa - ia, v - iv);
    let (sa, sv) = (ta * ta * (3.0 - 2.0 * ta), tv * tv * (3.0 - 2.0 * tv));
    let (i0, i1) = ((ia as i32).rem_euclid(n), (ia as i32 + 1).rem_euclid(n));
    let j = iv as i32;
    let h = |i: i32, j: i32| f64::from(pcg((i as u32).wrapping_mul(73_856_093) ^ (j as u32).wrapping_mul(19_349_663) ^ seed) >> 16) / 65536.0;
    let (p, q, r, t) = (h(i0, j), h(i1, j), h(i0, j + 1), h(i1, j + 1));
    p + (q - p) * sa + (r - p) * sv + (p - q - r + t) * sa * sv
}
/// The nearest of a jittered lattice of cells round (x, z), `size` apart: how far from the border with the next, in
/// blocks, the cell's own number and its middle.
fn cells(x: f64, z: f64, size: f64, seed: u32) -> (f64, u32, f64, f64) {
    crate::meter::spend(450);
    let (fx, fz) = (x / size, z / size);
    let (ix, iz) = (fx.floor() as i32, fz.floor() as i32);
    let (mut d1, mut d2, mut id, mut mx, mut mz) = (1e9f64, 1e9f64, 0u32, 0.0, 0.0);
    for dz in -1..=1 {
        for dx in -1..=1 {
            let (cx, cz) = (ix + dx, iz + dz);
            let h = pcg((cx as u32).wrapping_mul(0x9E37_79B1) ^ (cz as u32).wrapping_mul(0x85EB_CA6B) ^ seed);
            let (px, pz) = (f64::from(cx) + f64::from(h & 1023) / 1023.0, f64::from(cz) + f64::from(h >> 10 & 1023) / 1023.0);
            let (ex, ez) = (px - fx, pz - fz);
            let d = ex * ex + ez * ez;
            if d < d1 {
                d2 = d1;
                d1 = d;
                id = h;
                mx = px;
                mz = pz;
            } else if d < d2 {
                d2 = d;
            }
        }
    }
    ((d2.sqrt() - d1.sqrt()) * size, id, mx * size, mz * size)
}

// the rocks of the walls: each its block for a hash, so a bed is never one flat colour
const R_TUFF: u8 = 0;
const R_SLATE: u8 = 1;
const R_BASALT: u8 = 2;
const R_BLACK: u8 = 3;
const R_PALE: u8 = 4;
const R_BAKED: u8 = 5;
fn rock(kind: u8, h: f64) -> &'static str {
    match kind {
        R_TUFF => {
            if h < 0.62 {
                "minecraft:tuff"
            } else if h < 0.85 {
                "minecraft:cobbled_deepslate"
            } else {
                "minecraft:deepslate"
            }
        }
        R_SLATE => {
            if h < 0.5 {
                "minecraft:deepslate"
            } else if h < 0.85 {
                "minecraft:cobbled_deepslate"
            } else {
                "minecraft:smooth_basalt"
            }
        }
        R_BASALT => {
            if h < 0.6 {
                "minecraft:smooth_basalt"
            } else if h < 0.85 {
                "minecraft:basalt"
            } else {
                "minecraft:blackstone"
            }
        }
        R_BLACK => {
            if h < 0.74 {
                "minecraft:blackstone"
            } else if h < 0.95 {
                "minecraft:smooth_basalt"
            } else {
                "minecraft:black_terracotta"
            }
        }
        R_PALE => {
            if h < 0.5 {
                "minecraft:tuff"
            } else {
                "minecraft:andesite"
            }
        }
        _ => {
            if h < 0.7 {
                "minecraft:black_terracotta"
            } else {
                "minecraft:gray_terracotta"
            }
        }
    }
}
/// A column's face in beds from y0 up to y1: its rock `shift` blocks down from where it lay (a slumped or tilted block
/// carries its beds down with it), the beds leaning (`lean`), their edges never straight, a bed one block over its height.
fn beds_edit(b: &mut Blocks, s: &Shape, x: i32, z: i32, y0: i32, y1: i32, shift: i32, lean: f64) {
    let hc = pick(x * 13 + z * 7, s.seed ^ 0xc9);
    let d0 = s.gy + 30 - shift + (lean + 2.4 * hc) as i32;
    let mut y = y1;
    crate::meter::spend(160);
    while y >= y0 {
        let k = (d0 - y).rem_euclid(VC_BANDS as i32) as usize;
        let bed = s.beds[k];
        // (down through the bed)
        let mut n = 1;
        while y - n >= y0 && n < 12 && s.beds[(k + n as usize) % VC_BANDS] == bed {
            n += 1;
        }
        let h = pick(x * 3 + (y - n / 2) / 3 * 17 + z * 29, s.seed ^ 0xce);
        let m = if y < s.floor + 14 && bed == R_BLACK && h > 0.965 { "minecraft:magma_block" } else { rock(bed, h) };
        b.run(x, z, y - n + 1, y, m);
        y -= n;
    }
}
/// The rubble at the foot of the walls.
fn rubble(x: i32, y: i32, z: i32, seed: u32) -> &'static str {
    let h = pick(x * 7 + y * 23 + z * 41, seed ^ 0xcb);
    if h < 0.36 {
        "minecraft:cobbled_deepslate"
    } else if h < 0.5 {
        "minecraft:tuff"
    } else if h < 0.72 {
        "minecraft:blackstone"
    } else if h < 0.9 {
        "minecraft:basalt"
    } else {
        "minecraft:deepslate"
    }
}
/// One tone of ash with a fine grain in it, darker along the wet streaks (`dark`, 0 to 1).
fn ash_block(x: i32, y: i32, z: i32, seed: u32, dark: f64) -> &'static str {
    let h = pick(x * 5 + y * 19 + z * 3, seed ^ 0xca);
    let d = dark + 0.3 * (h - 0.5);
    if d > 0.8 {
        if h < 0.6 { "minecraft:mud" } else { "minecraft:gray_concrete_powder" }
    } else if d > 0.58 {
        if h < 0.4 {
            "minecraft:gray_concrete_powder"
        } else if h < 0.7 {
            "minecraft:cyan_terracotta"
        } else {
            "minecraft:tuff"
        }
    } else if d > 0.3 {
        if h < 0.4 {
            "minecraft:dead_brain_coral_block"
        } else if h < 0.72 {
            "minecraft:tuff"
        } else {
            "minecraft:cyan_terracotta"
        }
    } else if h < 0.42 {
        "minecraft:dead_brain_coral_block"
    } else if h < 0.72 {
        "minecraft:dead_tube_coral_block"
    } else if h < 0.9 {
        "minecraft:gravel"
    } else {
        "minecraft:tuff"
    }
}
/// The thin pale dust past the sheet, and the pumice floating on the water.
fn dust_block(x: i32, z: i32, seed: u32) -> &'static str {
    let h = pick(x * 11 + z * 37, seed ^ 0xcf);
    if h < 0.34 {
        "minecraft:dead_horn_coral_block"
    } else if h < 0.62 {
        "minecraft:gravel"
    } else if h < 0.86 {
        "minecraft:andesite"
    } else {
        "minecraft:light_gray_concrete_powder"
    }
}

/// What's worked out on a coarse grid over a chunk and read smoothly between (arc tangents, sines and broad noise a column
/// are most of a chunk's work otherwise): every 4 blocks from a block's width outside it.
const GN: usize = 6;
type Gf = [[f64; GN]; GN];
#[derive(Default)]
struct Grid {
    /// Its corner, the bearing (unwrapped over the chunk).
    x: i32,
    z: i32,
    a: Gf,
    e: Gf,
    /// How wide the wall is, and the rim.
    w: Gf,
    rw: Gf,
    /// How far out the sheet's edge wanders here, less being further.
    lobe: Gf,
    wx: Gf,
    wz: Gf,
    lean: Gf,
    /// Broad patches of the dust.
    patch: Gf,
    /// How hard the ring burst here, for the crown.
    crown: Gf,
    hot: Gf,
    pool: Gf,
}
impl Grid {
    fn new(s: &Shape, x0: i32, z0: i32) -> Self {
        let mut g = Grid { x: x0 - 4, z: z0 - 4, ..Default::default() };
        let a0 = (f64::from(z0) + 8.0 - s.cz).atan2(f64::from(x0) + 8.0 - s.cx);
        let mid = (f64::from(x0) + 8.0 - s.cx).hypot(f64::from(z0) + 8.0 - s.cz);
        let inner = mid < 300.0;
        for j in 0..GN {
            for i in 0..GN {
                let (px, pz) = (f64::from(g.x) + 4.0 * i as f64 + 0.5, f64::from(g.z) + 4.0 * j as f64 + 0.5);
                let (dx, dz) = (px - s.cx, pz - s.cz);
                let mut a = dz.atan2(dx);
                while a - a0 > PI {
                    a -= TAU;
                }
                while a - a0 < -PI {
                    a += TAU;
                }
                g.a[j][i] = a;
                g.e[j][i] = s.edge(a);
                g.w[j][i] = 40.0 + 30.0 * ring_noise(a, 13, 0.5, s.seed ^ 0xd2) + 12.0 * ring_noise(a, 47, 0.5, s.seed ^ 0xd3);
                g.rw[j][i] = 40.0 + 40.0 * ring_noise(a, 9, 0.5, s.seed ^ 0xd4);
                g.crown[j][i] = ((0.7 * ring_noise(a, 8, 0.5, s.seed ^ 0xde) + 0.3 * ring_noise(a, 31, 0.5, s.seed ^ 0xdf) - 0.3) * 3.0).clamp(0.05, 1.0);
                g.lobe[j][i] = 56.0 * (ring_noise(a, 17, 0.5, s.seed ^ 0xd5) - 0.5) + 40.0 * (qnoise(px, pz, 61.0, s.seed ^ 0xd6) - 0.5) + 18.0 * (qnoise(px, pz, 23.0, s.seed ^ 0xd7) - 0.5);
                g.wx[j][i] = 30.0 * (qnoise(px, pz, 57.0, s.seed ^ 0xd8) - 0.5);
                g.wz[j][i] = 30.0 * (qnoise(px, pz, 57.0, s.seed ^ 0xd9) - 0.5);
                g.lean[j][i] = 14.0 * qnoise(px, pz, 110.0, s.seed ^ 0xda);
                g.patch[j][i] = 0.62 * qnoise(px, pz, 52.0, s.seed ^ 0xdb) + 0.38 * qnoise(px, pz, 21.0, s.seed ^ 0xdc);
                if inner {
                    let (mut hot, mut pool) = (0.0f64, -1.0f64);
                    for v in &s.hots {
                        let (ex, ez) = (px + g.wx[j][i] - v.x, pz + g.wz[j][i] - v.z);
                        let q = (ex * ex + ez * ez) / (v.r * v.r);
                        if v.k > 0.0 {
                            hot = hot.max(v.k * (-q * 1.6).exp());
                        } else {
                            pool = pool.max(1.0 - q.sqrt());
                        }
                    }
                    // (the blocks standing in it glow at their feet a little)
                    for d in &s.drops {
                        let (ex, ez) = ((px - d.x) / (d.ru + d.rv), (pz - d.z) / (d.ru + d.rv));
                        hot = hot.max(0.42 * (-(ex * ex + ez * ez) * 2.5).exp());
                    }
                    crate::meter::spend(100 * (VC_HOTS + VC_DROPS) as u64);
                    let round = 0.62 * ((pool + 1.0) / 1.6).clamp(0.0, 1.0).powi(3);
                    g.hot[j][i] = hot.max(round) + 0.42 * (qnoise(px, pz, 44.0, s.seed ^ 0xdd) - 0.62).max(0.0);
                    g.pool[j][i] = pool;
                }
            }
        }
        crate::meter::spend((GN * GN * 900) as u64);
        g
    }
    fn at(&self, f: &Gf, x: i32, z: i32) -> f64 {
        let (fx, fz) = (f64::from(x - self.x) * 0.25, f64::from(z - self.z) * 0.25);
        let (i, j) = ((fx as usize).min(GN - 2), (fz as usize).min(GN - 2));
        let (u, v) = (fx - i as f64, fz - j as f64);
        (f[j][i] * (1.0 - u) + f[j][i + 1] * u) * (1.0 - v) + (f[j + 1][i] * (1.0 - u) + f[j + 1][i + 1] * u) * v
    }
}

/// A column's rough shape, for its neighbours: how high it stands, how far its rock has dropped or been lifted and what
/// it is.
#[derive(Clone, Copy, Default)]
struct Rel {
    top: i32,
    shift: i32,
    what: u8,
}
const W_FLOOR: u8 = 0;
const W_ROCK: u8 = 1;
const W_TALUS: u8 = 2;
const W_CAP: u8 = 3;
const W_OUT: u8 = 4;

struct Ctx<'a> {
    s: &'a Shape,
    hf: &'a Hf,
    cols: &'a [u32],
    bx: i32,
    bz: i32,
    g: Grid,
    y1: i32,
    drops: Vec<&'a Drop>,
    /// The columns of the chunk and one round it (x0 - 1 ..= x0 + 16), where the caldera or the rim reach.
    rel: Option<Box<[[Rel; 18]; 18]>>,
    x0: i32,
    z0: i32,
}
impl Ctx<'_> {
    fn col(&self, x: i32, z: i32) -> Option<Col> {
        let (i, k) = (x - self.bx + VC_READ, z - self.bz + VC_READ);
        if i < 0 || k < 0 || i >= VC_GW || k >= VC_GW {
            return None;
        }
        self.cols.get((k * VC_GW + i) as usize).and_then(|&v| Col::unpack(v))
    }
    fn land(&self, x: i32, z: i32) -> f64 {
        f64::from(self.s.gy) + self.hf.at(f64::from(x) + 0.5 - self.s.cx, f64::from(z) + 0.5 - self.s.cz)
    }
    /// How high the rim stands over the land here: slabs of the land broken and tilted up, higher towards the lip, a few
    /// of them shards standing well over it (the crown), cracks between. `p` how far past the lip, `rw` the rim's width.
    fn rim(&self, x: i32, z: i32, p: f64, rw: f64) -> (f64, f64) {
        if p > rw * 1.3 {
            return (0.0, 0.0);
        }
        let s = self.s;
        let (wx, wz) = (self.g.at(&self.g.wx, x, z), self.g.at(&self.g.wz, x, z));
        let (fx, fz) = (f64::from(x) + wx, f64::from(z) + wz);
        let (gap, id, mx, mz) = cells(fx, fz, 21.0, s.seed ^ 0xe1);
        let h = |k: u32| f64::from(pcg(id ^ k) >> 16) / 65536.0;
        // (the slab's middle, how far past the lip it lies)
        let (ox, oz) = (mx - wx - s.cx, mz - wz - s.cz);
        let rc = (ox * ox + oz * oz).sqrt();
        let (px, pz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
        let pc = p + (rc - (px * px + pz * pz).sqrt());
        let q = (pc / rw).clamp(0.0, 1.3);
        let a = 26.0 * (1.0 - (q / 1.15).min(1.0)).powi(2) + 7.0 * (1.0 - (q / 1.15).min(1.0));
        let mut up = a * (0.3 + 0.7 * h(0x51));
        // (the slab's top, dipping outwards, a bit round the way too)
        let (nx, nz) = (ox / rc, oz / rc);
        let mut dip = (0.32 + 0.6 * h(0x54)) * (a / 33.0 + 0.25);
        let (rx, rz) = (px - ox, pz - oz);
        let along = rx * nx + rz * nz;
        let side = -rx * nz + rz * nx;
        // the crown: where the ring burst hardest, slabs thrust up on end, wedges of rock; little between
        let gate = self.g.at(&self.g.crown, x, z);
        if q < 0.4 && h(0x52) < 0.6 * gate {
            let tall = 5.0 + 34.0 * h(0x53).powi(3) * gate;
            up += tall * (gap / 3.0).clamp(0.0, 1.0);
            dip = 0.5 + 1.2 * h(0x57);
        }
        up += -dip * along + (h(0x55) - 0.5) * dip * side;
        let smooth = up;
        // (the broken top of it)
        up += 3.0 * (pick(x.div_euclid(2) * 67 + z.div_euclid(2) * 131, s.seed ^ 0xe2) - 0.5) * (1.0 - q.min(1.0));
        // (the cracks between the slabs)
        if gap < 2.4 {
            up -= (2.4 - gap) * (1.0 + 2.0 * h(0x56)) * (1.0 - q.min(1.0));
        }
        (up.max(-3.0), smooth)
    }
    /// The height of the land before the rim: the ground, and water counts as ground (it's filled).
    fn base(&self, c: Option<Col>, x: i32, z: i32) -> f64 {
        c.map_or_else(|| self.land(x, z), |c| f64::from(c.base()))
    }
    /// A column of the caldera or the rim, how it will stand.
    fn relief(&self, x: i32, z: i32) -> Rel {
        crate::meter::spend(VC_UNIT);
        let s = self.s;
        let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
        let r = (dx * dx + dz * dz).sqrt();
        let e = self.g.at(&self.g.e, x, z);
        let u = e - r;
        let w = self.g.at(&self.g.w, x, z);
        let f = s.floor;
        if u > w * 1.08 {
            for d in &self.drops {
                let (ex, ez) = (f64::from(x) + 0.5 - d.x, f64::from(z) + 0.5 - d.z);
                let (a, b) = (ex * d.ca + ez * d.sa, -ex * d.sa + ez * d.ca);
                if a.abs() > d.ru * 2.2 || b.abs() > d.rv * 2.2 {
                    continue;
                }
                let th = b.atan2(a);
                let k = d.ph;
                let m = (a / d.ru).hypot(b / d.rv) * (1.0 + 0.2 * (2.0 * th + k).sin() + 0.13 * (3.0 * th + 2.0 * k).sin() + 0.09 * (5.0 * th + 3.0 * k).sin() + 0.08 * (9.0 * th + k).sin()) + 0.5 * (self.g.at(&self.g.patch, x, z) - 0.5);
                if m < 1.0 {
                    // (broken along faults as it dropped)
                    let (gap, id, _, _) = cells(f64::from(x), f64::from(z), 13.0, s.seed ^ d.ph.to_bits() as u32);
                    let step = f64::from(pcg(id) >> 16) / 65536.0;
                    let edge = 9.0 * (1.0 - ((1.0 - m) / 0.22).clamp(0.0, 1.0)).powi(2);
                    let top = f64::from(f) + d.h + d.tilt * a + 11.0 * (step - 0.5) - edge - if gap < 1.2 { 3.0 } else { 0.0 };
                    let drop = (f64::from(s.gy) - f64::from(f) - d.h) as i32;
                    return Rel { top: top.max(f64::from(f) + 2.0) as i32, shift: drop, what: W_CAP };
                }
                if m < 1.5 {
                    // (the rubble round its foot)
                    let k = (1.5 - m) / 0.5;
                    let n = pick(x.div_euclid(2) * 7 + z.div_euclid(2) * 13, s.seed ^ 0xeb);
                    return Rel { top: f + (d.h * 0.42 * k * k + 2.5 * n) as i32, shift: 0, what: W_TALUS };
                }
            }
            return Rel { top: f, shift: 0, what: W_FLOOR };
        }
        if u > 0.0 {
            // the wall: a scarp, the slumped blocks below it, each dropped and turned back on its own, then the rubble
            let c = self.col(x, z);
            let lip = self.base(c, x, z) + apron(0.0) + self.rim(x, z, 0.0, self.g.at(&self.g.rw, x, z)).0;
            let depth = (lip - f64::from(f)).max(12.0);
            let sw = u / w;
            let a = self.g.at(&self.g.a, x, z);
            // (cells along the wall, each so many blocks along it and across it; they close up round the ring)
            const ACROSS: f64 = 15.0;
            const ROUND: i32 = 37;
            let at = a / TAU * f64::from(ROUND);
            let (ia, iu) = (at.floor() as i32, (u / ACROSS).floor() as i32);
            let (mut d1, mut d2, mut id, mut uc) = (1e9f64, 1e9f64, 0u32, 0.0);
            for dv in -1..=1 {
                for da in -1..=1 {
                    let h = pcg(((ia + da).rem_euclid(ROUND) as u32).wrapping_mul(0x9E37_79B1) ^ ((iu + dv) as u32).wrapping_mul(0x85EB_CA6B) ^ s.seed);
                    let (pa, pv) = (f64::from(ia + da) + f64::from(h & 1023) / 1023.0, f64::from(iu + dv) + f64::from(h >> 10 & 1023) / 1023.0);
                    let (ea, ev) = ((pa - at) * 0.52, pv - u / ACROSS);
                    let d = ea * ea + ev * ev;
                    if d < d1 {
                        d2 = d1;
                        d1 = d;
                        id = h;
                        uc = pv * ACROSS;
                    } else if d < d2 {
                        d2 = d;
                    }
                }
            }
            crate::meter::spend(450);
            let h = |k: u32| f64::from(pcg(id ^ k) >> 16) / 65536.0;
            let sc = (uc / w).max(0.0);
            // (how far down the cell's middle has gone; the scarp's cells a good way at once)
            let q = (0.2 + 0.86 * sc + 0.14 * (h(0x61) - 0.5)).clamp(0.14, 1.1);
            // (turned back: its far side higher)
            let back = (0.12 + 0.3 * h(0x62)) * (u - uc) / w;
            let rock = lip - depth * (q - back);
            // the rubble: fans under the scarp, thick here, thin there
            let fan = ring_noise(a, 29, 0.5, s.seed ^ 0xe5);
            let n = pick(x * 19 + z * 7, s.seed ^ 0xe6);
            let rough = 1.6 * n + 1.6 * pick(x / 3 * 5 + z / 3 * 11, s.seed ^ 0xe7);
            let talus = f64::from(f) + (10.0 + 30.0 * fan) * {
                let k = ((1.08 - sw) / 0.62).clamp(0.0, 1.0);
                k * k.sqrt()
            } + rough;
            let edge = d2.sqrt() - d1.sqrt();
            let crack = if edge < 0.09 { 2.0 + 2.0 * h(0x63) } else { 0.0 };
            if talus >= rock - crack {
                return Rel { top: talus as i32, shift: 0, what: W_TALUS };
            }
            let top = (rock - crack).max(f64::from(f) + 1.0);
            return Rel { top: top as i32, shift: ((lip - top) * 0.82) as i32 + (h(0x64) * 6.0) as i32, what: W_ROCK };
        }
        let rw = self.g.at(&self.g.rw, x, z);
        let p = -u;
        if p > rw * 1.3 {
            return Rel { top: i32::MIN, shift: 0, what: W_OUT };
        }
        let c = self.col(x, z);
        let (up, smooth) = self.rim(x, z, p, rw);
        let base = self.base(c, x, z);
        Rel { top: (base + apron(-p) + up) as i32, shift: -(smooth * 0.85) as i32, what: W_ROCK }
    }
    fn near(&self, x: i32, z: i32) -> Rel {
        match &self.rel {
            Some(m) => m[(z - self.z0 + 1) as usize][(x - self.x0 + 1) as usize],
            None => self.relief(x, z),
        }
    }
}

/// The caldera's lake at (x, z): dark crust in big irregular plates cut into smaller ones where it runs hot, thin veins
/// of lava in the cracks towards the vents, dim and then dark away from them; open lava in a few pools.
fn lake_edit(b: &mut Blocks, ctx: &Ctx, x: i32, z: i32) {
    let s = ctx.s;
    let g = &ctx.g;
    let f = s.floor;
    let (wx, wz) = (g.at(&g.wx, x, z), g.at(&g.wz, x, z));
    let (fx, fz) = (f64::from(x) + wx, f64::from(z) + wz);
    let hot = g.at(&g.hot, x, z);
    let (gap2, id2, _, _) = cells(fx + 311.0, fz - 97.0, 15.0, s.seed ^ 0xe9);
    let wob = qnoise(f64::from(x), f64::from(z), 7.0, s.seed ^ 0xea) - 0.5;
    let pool = g.at(&g.pool, x, z) + 0.42 * wob + 0.3 * (g.at(&g.patch, x, z) - 0.5);
    if pool > 0.0 && !(gap2 > 2.6 && id2 & 7 < 2 && pool < 0.3) {
        // open lava, crust floating on it near its edge
        b.run(x, z, f - 3, f - 2, "minecraft:magma_block");
        b.run(x, z, f - 1, f - 1, "minecraft:lava");
        b.run(x, z, f, ctx.y1, "minecraft:air");
        return;
    }
    let (gap1, id1, _, _) = cells(fx, fz, 47.0, s.seed);
    let heat = hot + 0.5 * wob;
    let w1 = 0.5 + 2.1 * heat.max(0.0).powi(2);
    let w2 = if heat > 0.34 { 2.1 * (heat - 0.34) } else { 0.0 };
    // (the plates broken up further in places, by cracks long cooled)
    let seam = 0.9 * (qnoise(f64::from(x), f64::from(z), 31.0, s.seed ^ 0xec) - 0.36).max(0.0) * 2.4;
    let (crack, how) = if gap1 < w1 {
        (true, heat + 0.14)
    } else if gap2 < w2.max(seam) {
        (true, heat - 0.08)
    } else {
        (false, 0.0)
    };
    if crack {
        if how > 0.44 {
            b.run(x, z, f - 3, f - 2, "minecraft:magma_block");
            b.run(x, z, f - 1, f - 1, "minecraft:lava");
            b.run(x, z, f, ctx.y1, "minecraft:air");
        } else if how > 0.2 {
            b.run(x, z, f - 3, f - 1, "minecraft:magma_block");
            b.run(x, z, f, ctx.y1, "minecraft:air");
        } else {
            // (long cooled: a dark seam)
            b.run(x, z, f - 3, f - 2, "minecraft:blackstone");
            b.run(x, z, f - 1, ctx.y1, "minecraft:air");
        }
        return;
    }
    // a plate
    let big = pcg(id1 ^ 0x11);
    let small = pcg(id2 ^ 0x12);
    let off = (big % 5) as i32 / 2 - 1 + if heat > 0.2 { (small % 3) as i32 - 1 } else { i32::from(small % 4 == 0) - i32::from(small % 5 == 0) };
    let top = f + off;
    let h = pick(x * 31 + z * 57, id1);
    let tone = (big >> 8) % 8;
    let m = if heat > 0.36 && gap1.min(gap2) < 2.4 && h < 0.8 * (heat - 0.3) {
        "minecraft:magma_block"
    } else if h < 0.5 + 0.06 * f64::from(tone) {
        "minecraft:blackstone"
    } else if h < 0.8 + 0.02 * f64::from(tone) {
        "minecraft:polished_blackstone"
    } else if tone > 5 {
        "minecraft:basalt"
    } else {
        "minecraft:polished_blackstone"
    };
    b.run(x, z, top - 2, top, m);
    b.run(x, z, top + 1, ctx.y1, "minecraft:air");
}

/// A column of rock (the walls, the rim, the blocks in the lake): its faces in beds, how far they show worked out from its
/// neighbours; `ground` how high the land stood if the rock is lifted over it.
fn rock_edit(b: &mut Blocks, ctx: &Ctx, x: i32, z: i32, r: Rel, ground: i32) {
    let s = ctx.s;
    let lean = ctx.g.at(&ctx.g.lean, x, z);
    let mut low = r.top - 2;
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        low = low.min(ctx.near(x + dx, z + dz).top - 1);
    }
    let low = low.max(r.top - 30);
    if low > ground + 1 {
        b.run(x, z, ground + 1, low - 1, "minecraft:tuff");
    }
    // (ash lying on what's near flat)
    let flat = r.top - low <= 2 && pick(x * 3 + z * 19, s.seed ^ 0xef) < 0.75;
    beds_edit(b, s, x, z, low, r.top - i32::from(flat), r.shift, lean);
    if flat {
        b.run(x, z, r.top, r.top, ash_block(x, r.top, z, s.seed, 0.25));
    }
}

/// Past the rim: the sheet, the dust and the trees. (ρ how far out by the sheet's own wandering edge)
fn out_edit(b: &mut Blocks, ctx: &Ctx, c: Col, x: i32, z: i32, r: f64, rel: Rel) {
    let s = ctx.s;
    let g = &ctx.g;
    let lobe = g.at(&g.lobe, x, z);
    let rho = r + lobe;
    let base = c.base();
    let hl = ctx.land(x, z);
    // the ash in the low ground, how far it sits under the land round it, deeper down the valleys
    let low = hl - f64::from(base);
    let rho = rho - 2.2 * low.clamp(-4.0, 18.0);
    let a = g.at(&g.a, x, z);
    let bend = 0.00045 * lobe;
    let n1 = ring_noise(a + bend, 401, r / 170.0, s.seed ^ 0xa1);
    let n2 = ring_noise(a + bend, 977, r / 96.0, s.seed ^ 0xa2);
    let gather = g.at(&g.patch, x, z);
    let wet = ((0.6 * n1 + 0.4 * n2 - 0.57) * (0.3 + 1.2 * gather) * 6.0).clamp(0.0, 0.8);
    if rho < VC_IGN {
        // the sheet
        let fall = 1.0 - ((rho - 330.0) / (VC_IGN - 330.0)).clamp(0.0, 1.0).powi(2);
        let pond = (hl + 3.0 - f64::from(base)).clamp(0.0, 18.0) * fall;
        let ridge = (-low / 7.0).clamp(0.0, 1.0);
        let t = pond + (1.3 - 1.3 * ridge) * (0.45 + fall) + apron(-(r - g.at(&g.e, x, z)));
        let cut = if wet > 0.62 { 1.0 } else { 0.0 };
        // (never a smooth slope: on flat water its steps would be a contour map's rings)
        let rough = if t > 0.6 { 2.0 * (qnoise(f64::from(x), f64::from(z), 5.5, s.seed ^ 0xa7) - 0.5) + pick(x * 37 + z * 59, s.seed ^ 0xa8) - 0.5 } else { 0.0 };
        let top = base + (t - cut * 0.9 + rough).round().max(0.0) as i32;
        let mut top = top;
        // what stands is swept off
        let stands = c.top.max(base);
        // (a block flung out of the crater)
        let lump = lump(x, z, r, s.seed);
        if rel.what != W_OUT && rel.top >= top {
            // (the rim's rock stands clear of the ash)
            if stands > rel.top {
                b.run(x, z, rel.top + 1, stands, "minecraft:air");
            }
            rock_edit(b, ctx, x, z, rel, base);
            return;
        }
        if lump > 0 {
            top += lump;
        }
        if stands > top {
            b.run(x, z, top + 1, stands, "minecraft:air");
        }
        let was_water = c.fluid;
        let dark = if was_water { (wet + 0.62).min(0.92) } else if pond > 7.0 { wet * 0.6 } else { wet };
        let m = if lump > 0 { rubble(x, top, z, s.seed) } else { ash_block(x, top, z, s.seed, dark) };
        // (one run, all of it: the ash under the top is no one's to see)
        b.run(x, z, if c.deep { base - 1 } else { (c.g + 1).min(top) }, top, m);
        // (a tree's charred stump showing through at the sheet's edge)
        if c.trunk > 0 && !c.fluid && lump == 0 && rho > 384.0 {
            b.run(x, z, top + 1, top + 1 + i32::from(pick(x * 3 + z * 5, s.seed) > 0.5), CHAR);
        }
        return;
    }
    // past the sheet: how much of it is ash here, patches on patches, drawn out along the flows, thinning away
    let q = ((rho - VC_IGN + 20.0) / 180.0).clamp(0.0, 1.0);
    let cover = dust_cover(rho);
    let fine = qnoise(f64::from(x), f64::from(z), 6.5, s.seed ^ 0xa4);
    let n = (0.6 * g.at(&g.patch, x, z) + 0.24 * fine + 0.16 * pick(x * 17 + z * 23, s.seed ^ 0xa5) - 0.5 - 0.1 * wet) * 2.7 + 0.5;
    let ash = n < cover;
    let rt = r + 0.45 * lobe;
    if c.fluid {
        // pumice floating, the shallows choked
        if ash || (c.top - c.g <= 1 && n < cover * 1.5) {
            b.run(x, z, c.top, c.top, if q < 0.4 { ash_block(x, c.top, z, s.seed, 0.3) } else { dust_block(x, z, s.seed) });
        }
        return;
    }
    stand_edit(b, ctx, c, x, z, rt);
    if ash {
        let m = if q < 0.3 { ash_block(x, c.g, z, s.seed, wet * (1.0 - 2.0 * q)) } else { dust_block(x, z, s.seed) };
        b.run(x, z, c.g, c.g, m);
        // (what grew on it, buried)
        if c.top > c.g && c.trunk == 0 && !c.leaves {
            b.run(x, z, c.g + 1, c.top, "minecraft:air");
        }
    } else if c.ground == 1 && rho < 540.0 && pick(x * 29 + z * 3, s.seed ^ 0xa6) < 1.0 - (rho - 430.0) / 110.0 {
        // (the grass burnt off)
        b.run(x, z, c.g, c.g, if fine < 0.5 { "minecraft:coarse_dirt" } else { "minecraft:dirt" });
    }
}

/// How much of the land the dust covers `rho` out: all of it at the sheet's edge, a tenth by 600, none by VC_FAR.
fn dust_cover(rho: f64) -> f64 {
    let q = ((rho - VC_IGN + 20.0) / 180.0).clamp(0.0, 1.0);
    ((1.0 - q) * (1.0 - q).sqrt()).max(0.1 * (1.0 - (rho - 600.0) / (VC_FAR - 600.0))) * 1.04
}
/// A chunk past what's read, where the world has it loaded: the odd patch of dust, counted from the ground's height.
fn vc_far_chunk(q: &mut Plan, s: &Shape, t: f32, x0: i32, z0: i32) {
    let (ox, oz) = (f64::from(x0) + 8.0 - s.cx, f64::from(z0) + 8.0 - s.cz);
    let cover = dust_cover(ox.hypot(oz));
    // (most chunks have none: the broad noise says so at the corners, and they are not sent again for nothing)
    let at = |x: i32, z: i32| 0.6 * (0.62 * qnoise(f64::from(x), f64::from(z), 52.0, s.seed ^ 0xdb) + 0.38 * qnoise(f64::from(x), f64::from(z), 21.0, s.seed ^ 0xdc));
    let edge = [at(x0, z0), at(x0 + 16, z0), at(x0, z0 + 16), at(x0 + 16, z0 + 16)];
    let (lo, hi) = (edge.iter().cloned().fold(9.0, f64::min), edge.iter().cloned().fold(-9.0, f64::max));
    // (what the patches need of the noise: the column's own part is at most 0.4)
    let need = (cover - 0.5) / 2.7 + 0.5;
    if lo - 0.16 > need {
        return;
    }
    let mut b = Blocks::default();
    for z in z0..z0 + 16 {
        for x in x0..x0 + 16 {
            crate::meter::spend(60);
            let (u, v) = (f64::from(x - x0) / 16.0, f64::from(z - z0) / 16.0);
            let coarse = (edge[0] * (1.0 - u) + edge[1] * u) * (1.0 - v) + (edge[2] * (1.0 - u) + edge[3] * u) * v;
            let n = coarse + 0.24 * qnoise(f64::from(x), f64::from(z), 6.5, s.seed ^ 0xa4) + 0.16 * pick(x * 17 + z * 23, s.seed ^ 0xa5);
            if n < need {
                let m = dust_block(x, z, s.seed);
                b.put(x, z, -1, -1, m, Some("#minecraft:azalea_root_replaceable"), true);
                b.put(x, z, -1, -1, m, Some("minecraft:water"), true);
                b.put(x, z, 0, 0, "minecraft:air", Some("minecraft:short_grass"), true);
            }
        }
    }
    let _ = hi;
    if !b.runs.is_empty() {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// What the ring itself piled up round the rim, `u` inside the caldera's edge: the land rises to the crater.
fn apron(u: f64) -> f64 {
    let k = (1.0 + u.min(0.0) / 130.0).clamp(0.0, 1.0);
    22.0 * k * k * k
}
/// A block flung out of the crater lying here: how high it stands (0: none).
fn lump(x: i32, z: i32, r: f64, seed: u32) -> i32 {
    const S: i32 = 11;
    let (ix, iz) = (x.div_euclid(S), z.div_euclid(S));
    let k = ix * 7919 + iz * 104_729;
    let chance = 0.3 * (1.0 - (r - 320.0) / 90.0);
    if pick(k, seed ^ 0xeb) > chance {
        return 0;
    }
    let (px, pz) = (pick(k, seed ^ 0xec) * 7.0 + 2.0, pick(k, seed ^ 0xed) * 7.0 + 2.0);
    let (ex, ez) = (f64::from(x.rem_euclid(S)) - px, f64::from(z.rem_euclid(S)) - pz);
    let size = 1.4 + 2.6 * pick(k, seed ^ 0xee);
    let d = size - ex.hypot(ez);
    if d <= 0.0 { 0 } else { (d * 1.1).ceil() as i32 }
}

/// What the heat did to what stands past the sheet, by `rt`, how far out: (the trunks felled by `vc_fell`) burnt stumps,
/// then trunks left standing bare and black, then scorched trees with what's left of their crowns gone brown, then the
/// leaves only, browning less and less.
fn stand_edit(b: &mut Blocks, ctx: &Ctx, c: Col, x: i32, z: i32, rt: f64) {
    let s = ctx.s;
    let k = x * 31 + z * 17;
    let h = pick(k, s.seed ^ 0x81);
    if c.trunk > 0 {
        let top = c.g + i32::from(c.trunk);
        match fate(x, z, rt, s.seed) {
            Fate::Felled => {
                let stump = 1 + (h * 1.6) as i32;
                b.run(x, z, c.g + 1, c.g + stump, CHAR);
                if c.top > c.g + stump {
                    b.run(x, z, c.g + 1 + stump, c.top, "minecraft:air");
                }
            }
            Fate::Bare => {
                let keep = 2 + ((f64::from(c.trunk) - 1.0) * (0.45 + 0.55 * h)) as i32;
                let keep = keep.min(i32::from(c.trunk));
                b.run(x, z, c.g + 1, c.g + keep, if h < 0.55 { CHAR } else { "minecraft:dark_oak_log" });
                if c.top > c.g + keep {
                    b.run(x, z, c.g + 1 + keep, c.top, "minecraft:air");
                }
            }
            Fate::Scorched => {
                b.run(x, z, c.g + 1, top, "minecraft:dark_oak_log");
            }
            Fate::Standing => {}
        }
    }
    if c.trunk == 0 && c.top > c.g && (c.leaves || c.top > c.g + 1) {
        // the crowns
        if rt < VC_BARE + 15.0 {
            b.run(x, z, c.g + 1, c.top, "minecraft:air");
            return;
        }
        let p = qnoise(f64::from(x), f64::from(z), 8.0, s.seed ^ 0x84);
        let burn = 1.0 - (rt - VC_BARE) / (VC_GREEN - VC_BARE);
        if burn <= 0.0 {
            return;
        }
        // (nearest the bare ones most of it has gone, what's left brown; further the crown stays, browning in places)
        if h < burn * burn * 0.9 {
            b.run(x, z, c.g + 1, c.top, "minecraft:air");
        } else if p + 0.5 * h - 0.25 < burn * 1.1 {
            let (m, mid) = browned(h, burn);
            let cut = c.g + 1 + ((c.top - c.g) * 2) / 3;
            b.put(x, z, c.g + 1, cut, m, Some("#minecraft:leaves"), false);
            b.put(x, z, cut + 1, c.top, mid, Some("#minecraft:leaves"), false);
        }
    }
}
/// A browned crown's blocks, lower and upper, the worse burnt the darker.
fn browned(h: f64, burn: f64) -> (&'static str, &'static str) {
    let pick = |v: f64| {
        if v < 0.3 + 0.5 * burn {
            VC_TWIG
        } else if v < 0.5 + 0.4 * burn {
            VC_LEAF_RED
        } else {
            VC_LEAF_ORANGE
        }
    };
    (pick(h), pick((h * 7.3).fract()))
}
const CHAR: &str = "minecraft:basalt";
const VC_TWIG: &str = "minecraft:mangrove_roots";
const VC_LEAF_RED: &str = "minecraft:red_poplar_leaves[persistent=true]";
const VC_LEAF_ORANGE: &str = "minecraft:orange_poplar_leaves[persistent=true]";
/// Felled up to about here, bare black trunks to VC_BARE, scorched to VC_SCORCH, the leaves browning to VC_GREEN.
const VC_FELLED: f64 = 482.0;
const VC_BARE: f64 = 526.0;
const VC_SCORCH: f64 = 562.0;
const VC_GREEN: f64 = 596.0;
#[derive(PartialEq, Clone, Copy)]
enum Fate {
    Felled,
    Bare,
    Scorched,
    Standing,
}
fn fate(x: i32, z: i32, rt: f64, seed: u32) -> Fate {
    let k = x * 41 + z * 67;
    let j = rt + 30.0 * (pick(k, seed ^ 0x85) - 0.5);
    if j < VC_FELLED {
        Fate::Felled
    } else if j < VC_BARE {
        if pick(k, seed ^ 0x86) < (VC_BARE - j) / (VC_BARE - VC_FELLED) * 0.7 { Fate::Felled } else { Fate::Bare }
    } else if j < VC_SCORCH {
        Fate::Scorched
    } else {
        Fate::Standing
    }
}

/// The trees standing on (x, z)'s chunk felled: lying on the land pointing away from the vent, once the wall has swept
/// the land they lie on. Charred trunks, some broken in two.
fn vc_fell(due: &mut Vec<(f32, Blocks)>, ctx: &Ctx, x0: i32, z0: i32) {
    let s = ctx.s;
    let mut b = Blocks::default();
    let mut far = 0.0f64;
    for z in z0..z0 + 16 {
        for x in x0..x0 + 16 {
            crate::meter::spend(40);
            let Some(c) = ctx.col(x, z) else { continue };
            if c.trunk < 3 || c.fluid {
                continue;
            }
            let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            let r = (dx * dx + dz * dz).sqrt();
            let lobe = ctx.g.at(&ctx.g.lobe, x, z);
            if r + lobe - 2.2 * (ctx.land(x, z) - f64::from(c.g)).clamp(-4.0, 18.0) < VC_IGN + 2.0 || fate(x, z, r + 0.45 * lobe, s.seed) != Fate::Felled {
                continue;
            }
            let k = x * 13 + z * 53;
            let turn = dz.atan2(dx) + 0.5 * (pick(k, s.seed ^ 0x87) - 0.5);
            let (ux, uz) = (turn.cos(), turn.sin());
            let (lx_, lz_) = if ux.abs() > uz.abs() { (LOG_X[5], LOG_Z[5]) } else { (LOG_Z[5], LOG_X[5]) };
            let _ = lz_;
            let black = pick(k, s.seed ^ 0x88) < 0.6;
            let log = if black { if ux.abs() > uz.abs() { "minecraft:basalt[axis=x]" } else { "minecraft:basalt[axis=z]" } } else { lx_ };
            let want = ((f64::from(c.trunk) - 1.0) * (0.6 + 0.4 * pick(k, s.seed ^ 0x89))) as i32;
            let want = want.clamp(2, 8);
            let brk = 2 + (pick(k, s.seed ^ 0x8a) * 6.0) as i32;
            let mut y = c.g + 1;
            for n in 2..2 + want {
                if n == brk {
                    continue;
                }
                let (lx, lz) = ((f64::from(x) + 0.5 + ux * f64::from(n)).floor() as i32, (f64::from(z) + 0.5 + uz * f64::from(n)).floor() as i32);
                let Some(l) = ctx.col(lx, lz) else { break };
                if l.fluid || (l.g + 1 - y).abs() > 1 {
                    break;
                }
                y = l.g + 1;
                b.run(lx, lz, y, y, log);
            }
            far = far.max(r + f64::from(want));
        }
    }
    if !b.runs.is_empty() {
        due.push((vc_due(far + 10.0) + 0.4, b));
    }
}

/// When the wall of ash reaches r, past VC_IN; inside it, when the caldera's chunks there are due.
pub(super) fn vc_due(r: f64) -> f32 {
    if r >= VC_IN {
        // (the front's speed is falling, its way known only forward: a few steps of Newton)
        let mut c: f64 = 0.0;
        for _ in 0..6 {
            let v = 25.0 + 35.0 * (-c / 14.0).exp();
            c = (c + (r - vc_front(c)) / v).max(0.0);
        }
        return VC_COLLAPSE + c as f32 + 0.25;
    }
    let area = PI * (VC_IN * VC_IN - r * r);
    VC_COLLAPSE + 1.0 + (area * VC_COL / VC_RATE) as f32
}

struct Work {
    s: Shape,
    hf: Rc<RefCell<Hf>>,
    cols: Vec<u32>,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    missing: Missing,
    retry: Option<(u32, f32)>,
    /// The chunks' corners, by when they are due.
    chunks: Vec<(f32, i32, i32)>,
    next: usize,
    /// The chunks past the read asked after (a column of each), and those loaded, by when they are due.
    far_tag: u32,
    far: Vec<(f32, i32, i32)>,
    far_next: usize,
    /// What's worked out and not yet due: when, how many runs, and all of them.
    queue: std::collections::VecDeque<(f32, usize)>,
    queued: usize,
    /// The columns never loaded have been said.
    said: bool,
}
impl Work {
    fn new(s: Shape, bx: i32, bz: i32) -> Self {
        let mut chunks = Vec::new();
        let due = DueTable::new();
        let n = (f64::from(VC_READ) + 24.0) as i32 / 16 + 1;
        let (c0x, c0z) = (bx >> 4, bz >> 4);
        for dz in -n..=n {
            for dx in -n..=n {
                let (x, z) = ((c0x + dx) * 16, (c0z + dz) * 16);
                // (its middle, and the far corner: the wall has passed all of it)
                let (mx, mz) = (f64::from(x) + 8.0 - s.cx, f64::from(z) + 8.0 - s.cz);
                let rm = (mx * mx + mz * mz).sqrt();
                if rm - 12.0 > f64::from(VC_READ) {
                    continue;
                }
                chunks.push((due.at(if rm + 11.4 >= VC_IN { rm + 11.4 } else { rm }), x, z));
            }
        }
        chunks.sort_by(|a, b| a.0.total_cmp(&b.0));
        crate::meter::spend(300 * chunks.len() as u64);
        Work { s, hf: Default::default(), cols: Vec::new(), tags: (0..VC_PARTS).map(|_| crate::columns::new_tag()).collect(), asked: 0, taken: 0, missing: Missing::default(), retry: None, chunks, next: 0, far_tag: 0, far: Vec::new(), far_next: 0, queue: Default::default(), queued: 0, said: false }
    }
}

/// One chunk's edits, due at `t`.
fn vc_chunk(q: &mut Plan, w: &Work, t: f32, x0: i32, z0: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let s = w.s;
    let hf = w.hf.borrow();
    let (ox, oz) = (f64::from(x0) + 8.0 - s.cx, f64::from(z0) + 8.0 - s.cz);
    let mid = ox.hypot(oz);
    // (a chunk the world never loaded has nothing to change)
    if mid > VC_RIM + 120.0 && !w.cols.is_empty() {
        let known = |x: i32, z: i32| {
            let (i, k) = (x - bx + VC_READ, z - bz + VC_READ);
            i >= 0 && k >= 0 && i < VC_GW && k < VC_GW && w.cols[(k * VC_GW + i) as usize] != 0
        };
        crate::meter::spend(300);
        if ![(1, 1), (14, 1), (1, 14), (14, 14), (8, 8)].iter().any(|&(i, k)| known(x0 + i, z0 + k)) {
            return;
        }
    }
    let y1 = (f64::from(s.gy) + hf.max_near(ox, oz) + 48.0).min(318.0) as i32;
    let reach = |d: &&Drop| (d.x - s.cx - ox).abs().max((d.z - s.cz - oz).abs()) < 2.3 * d.ru.max(d.rv) + 12.0;
    let mut ctx = Ctx { s: &s, hf: &hf, cols: &w.cols, bx, bz, g: Grid::new(&s, x0, z0), y1, drops: s.drops.iter().filter(reach).collect(), rel: None, x0, z0 };
    // (every column of the caldera and the rim, and one round the chunk, its shape first: how far its faces show)
    let inner = mid < VC_RIM + 110.0;
    if inner {
        let mut m = Box::new([[Rel::default(); 18]; 18]);
        for (j, row) in m.iter_mut().enumerate() {
            for (i, v) in row.iter_mut().enumerate() {
                *v = ctx.relief(x0 - 1 + i as i32, z0 - 1 + j as i32);
            }
        }
        ctx.rel = Some(m);
    }
    let mut b = Blocks::default();
    for z in z0..z0 + 16 {
        for x in x0..x0 + 16 {
            vc_col_edit(&mut b, &ctx, x, z, inner);
        }
    }
    if !b.runs.is_empty() {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
    if !w.cols.is_empty() {
        let mut due = Vec::new();
        vc_fell(&mut due, &ctx, x0, z0);
        for (tf, b) in due {
            q.ev.push((tf, Act::Blocks(Box::new(b))));
        }
    }
}

/// The edits to column (x, z).
fn vc_col_edit(b: &mut Blocks, ctx: &Ctx, x: i32, z: i32, inner: bool) {
    crate::meter::spend(VC_UNIT);
    let s = ctx.s;
    let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
    let r = (dx * dx + dz * dz).sqrt();
    let u = ctx.g.at(&ctx.g.e, x, z) - r;
    let air = "minecraft:air";
    let rel = if inner { ctx.near(x, z) } else { Rel { top: i32::MIN, shift: 0, what: W_OUT } };
    if u > 0.0 {
        let top = rel.top;
        match rel.what {
            W_FLOOR => return lake_edit(b, ctx, x, z),
            W_TALUS => {
                let mut low = top - 2;
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    low = low.min(ctx.near(x + dx, z + dz).top - 1);
                }
                let low = low.max(top - 9);
                let m = top - (top - low) / 2;
                b.run(x, z, low, m - 1, rubble(x, m, z, s.seed ^ 3));
                b.run(x, z, m, top, rubble(x, top, z, s.seed));
            }
            _ => rock_edit(b, ctx, x, z, rel, ctx.land(x, z) as i32 - 2),
        }
        b.run(x, z, top + 1, ctx.y1, air);
        // (what the wall cuts into sealed)
        b.put(x, z, s.floor - 4, top - 3, "minecraft:tuff", Some("minecraft:water"), false);
        b.put(x, z, s.floor - 4, top - 3, "minecraft:magma_block", Some("minecraft:lava"), false);
        return;
    }
    let Some(c) = ctx.col(x, z) else { return };
    if u > -4.0 {
        b.put(x, z, s.floor - 4, c.g, "minecraft:tuff", Some("minecraft:water"), false);
        b.put(x, z, s.floor - 4, c.g, "minecraft:magma_block", Some("minecraft:lava"), false);
    }
    out_edit(b, ctx, c, x, z, r, rel);
}

/// `vc_due` for a chunk of many: it's six rounds of an exponential a time, thousands of chunks to the tick the list is
/// made otherwise. From a table over the land past the ring, a column's time out, every 8 blocks.
struct DueTable(Vec<f32>);
impl DueTable {
    const STEP: f64 = 8.0;
    fn new() -> Self {
        DueTable((0..=((VC_FAR + 40.0 - VC_IN) / Self::STEP) as usize + 1).map(|i| vc_due(VC_IN + i as f64 * Self::STEP)).collect())
    }
    fn at(&self, r: f64) -> f32 {
        if r < VC_IN {
            return vc_due(r);
        }
        let f = (r - VC_IN) / Self::STEP;
        let i = (f as usize).min(self.0.len() - 2);
        self.0[i] + (self.0[i + 1] - self.0[i]) * (f - i as f64) as f32
    }
}
/// The chunks past the read and within VC_FAR: `each(x, z, how far their middle is, squared)`, a row at a time.
fn far_chunks(bx: i32, bz: i32, s: &Shape, mut each: impl FnMut(i32, i32, f64)) {
    let n = VC_FAR as i32 / 16 + 1;
    let (near, far) = ((f64::from(VC_READ) - 12.0).powi(2), VC_FAR * VC_FAR);
    crate::meter::spend(20 * u64::from((2 * n + 1).unsigned_abs()).pow(2));
    for dz in -n..=n {
        for dx in -n..=n {
            let (x, z) = (((bx >> 4) + dx) * 16, ((bz >> 4) + dz) * 16);
            let (ex, ez) = (f64::from(x) + 8.0 - s.cx, f64::from(z) + 8.0 - s.cz);
            let r = ex * ex + ez * ez;
            if r > near && r < far {
                each(x, z, r);
            }
        }
    }
}

/// One stage of the land's work: the reads, then the chunks coming due.
fn vc_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        if wk.cols.is_empty() {
            // (zeroed by the allocator: the land's square costs no fuel to make, the pages only when written)
            wk.cols = vec![0u32; (VC_GW * VC_GW) as usize];
        }
        if wk.asked < wk.tags.len() && wk.asked - wk.taken < VC_FLIGHT {
            let part = wk.asked;
            q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: VC_BELOW, above: VC_ABOVE }));
            wk.asked += 1;
        }
        for _ in 0..2 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                take_in(&mut wk.cols, &mut wk.missing, &a, bx, bz);
                wk.taken += 1;
            }
        }
        // (what the world had not loaded asked again, in lots, while there is time)
        if wk.taken == wk.tags.len() && now < VC_COLLAPSE + 2.0 {
            if let Some((tag, since)) = wk.retry {
                if let Some(a) = crate::columns::take(tag) {
                    take_in(&mut wk.cols, &mut wk.missing, &a, bx, bz);
                    wk.retry = None;
                } else if now > since + 3.0 {
                    wk.retry = None;
                }
            } else if !wk.missing.list.is_empty() {
                let cols = wk.missing.take(&wk.cols, bx, bz, 6000);
                let tag = crate::columns::new_tag();
                q.ev.push((now, Act::Read { tag, columns: cols, below: VC_BELOW, above: VC_ABOVE }));
                wk.retry = Some((tag, now));
            }
        }
        if now >= VC_COLLAPSE + 2.0 && !wk.said {
            wk.said = true;
            if !wk.missing.list.is_empty() {
                #[cfg(not(test))]
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("supervolcano: {} chunks of the land never loaded", wk.missing.list.len()));
            }
        }
        // (which chunks past the read are loaded, once the land's near done)
        if now >= VC_FAR_ASK && wk.far_tag == 0 {
            wk.far_tag = crate::ground::new_tag();
            let mut cols = Vec::new();
            far_chunks(bx, bz, &wk.s, |x, z, _| cols.push((x + 8, z + 8)));
            crate::meter::spend(200 * cols.len() as u64);
            q.ev.push((now, Act::Survey { tag: wk.far_tag, columns: cols }));
        } else if wk.far_tag != 0 && wk.far.is_empty() && crate::ground::ready(wk.far_tag) {
            let due = DueTable::new();
            let mut far = Vec::new();
            far_chunks(bx, bz, &wk.s, |x, z, r| {
                if crate::ground::at(x + 8, z + 8).is_some() {
                    far.push((due.at(r.sqrt() + 12.0), x, z));
                }
            });
            far.sort_by(|a, b| a.0.total_cmp(&b.0));
            // (none loaded: nothing to wait for)
            if far.is_empty() {
                far.push((0.0, i32::MIN, 0));
            }
            crate::meter::spend(400 * far.len() as u64);
            wk.far = far;
        }
        while wk.queue.front().is_some_and(|e| e.0 <= now) {
            wk.queued -= wk.queue.pop_front().map_or(0, |e| e.1);
        }
        while wk.next < wk.chunks.len() && wk.chunks[wk.next].0 <= now + VC_LEAD && crate::meter::spent() < VC_TICK && wk.queued < VC_QUEUE && crate::mem::live() < VC_HOLD {
            let (t, x, z) = wk.chunks[wk.next];
            let n0 = q.ev.len();
            vc_chunk(q, wk, t, x, z);
            let mut runs = 0;
            for e in &mut q.ev[n0..] {
                if let Act::Blocks(b) = &mut e.1 {
                    b.runs.shrink_to_fit();
                    runs += b.runs.len();
                }
            }
            // (it's let go when due: `chunks` is in that order, and a falling tree's edit a moment after is counted with it)
            wk.queue.push_back((t, runs));
            wk.queued += runs;
            wk.next += 1;
        }
        while wk.far_next < wk.far.len() && wk.far[wk.far_next].0 <= now + VC_LEAD && crate::meter::spent() < VC_TICK {
            let (t, x, z) = wk.far[wk.far_next];
            if x != i32::MIN {
                vc_far_chunk(q, &wk.s, t, x, z);
            }
            wk.far_next += 1;
        }
        wk.next < wk.chunks.len() || now < VC_FAR_ASK + 6.0 || wk.far_next < wk.far.len()
    };
    if more {
        q.later(now + 0.05, move |q| vc_work(q, w, now + 0.05));
    }
}

/// The forceloads that keep the chunks within `r` of `point` loaded, a row of chunks each: `pk_load_rows`'s, which by way
/// of its lists and sets costs this many chunks 18 million instructions on the tick the strike fires.
fn vc_load_rows(point: [f64; 3], r: f64) -> Vec<[i32; 4]> {
    let (c0x, c1x) = (((point[0] - r).floor() as i32) >> 4, ((point[0] + r).floor() as i32) >> 4);
    let (c0z, c1z) = (((point[2] - r).floor() as i32) >> 4, ((point[2] + r).floor() as i32) >> 4);
    let reach = |cx: i32, cz: i32| {
        let (x0, z0) = (f64::from(cx * 16), f64::from(cz * 16));
        let nx = (point[0] - x0).clamp(0.0, 16.0) + x0 - point[0];
        let nz = (point[2] - z0).clamp(0.0, 16.0) + z0 - point[2];
        nx * nx + nz * nz <= r * r
    };
    let mut out = Vec::new();
    for cz in c0z..=c1z {
        // (a circle crosses a row of chunks in one span)
        let first = (c0x..=c1x).find(|&cx| reach(cx, cz));
        let last = (c0x..=c1x).rev().find(|&cx| reach(cx, cz));
        if let (Some(a), Some(b)) = (first, last) {
            out.push([a * 16, cz * 16, b * 16 + 15, cz * 16 + 15]);
        }
    }
    out
}

/// The land's work in the plan: the chunks round it force-loaded, its stages from a little after it fires; the land's
/// height handed over as it comes (`hf`).
pub(super) fn vc_land_plan(p: &mut Plan, laser: &'static Laser, seed: u32, hf: Rc<RefCell<Hf>>) {
    let (bx, by, bz) = (p.bx, p.by, p.bz);
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let point = [cx, f64::from(by) + 1.0, cz];
    let load = vc_load_rows(point, VC_LOAD);
    for [x0, z0, x1, z1] in &load {
        p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
    }
    for [x0, z0, x1, z1] in &load {
        p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
    }
    let s = Shape::new(cx, cz, seed, by + 1);
    p.later(0.2, move |q| {
        let mut w = Work::new(s, q.bx, q.bz);
        w.hf = hf;
        let w = Rc::new(RefCell::new(w));
        // (the land asked for once its chunks have had a moment to load)
        q.later(3.0, move |q| vc_work(q, w, 3.0));
    });
    // (what lives there dies as the wall goes over)
    for r in [300, 400, 520] {
        let t = vc_due(f64::from(r));
        p.at(t, format!("execute positioned {cx:.1} {} {cz:.1} run kill @e[type=!minecraft:player,distance=..{r}]", by + 1));
    }
}

/// The crater a lava bomb leaves where it lands: a few blocks of the land gone, lined with basalt and magma (counted from
/// each column's ground, so it needs no read).
pub(super) fn vc_bomb_crater(x: i32, z: i32, r: i32, seed: u32) -> Blocks {
    let mut b = Blocks::default();
    for dz in -r..=r {
        for dx in -r..=r {
            let q = dx * dx + dz * dz;
            if q > r * r {
                continue;
            }
            let u = 1.0 - f64::from(q).sqrt() / f64::from(r + 1);
            let d = (u * f64::from(r) * 0.8).ceil() as i32;
            let (px, pz) = (x + dx, z + dz);
            b.put(px, pz, -d, 8, "minecraft:air", None, true);
            let m = if mh((px * 7 + pz * 13) as u32, seed, 0xcc) < 0.3 { "minecraft:magma_block" } else { "minecraft:basalt" };
            b.put(px, pz, -d - 1, -d - 1, m, None, true);
        }
    }
    b
}

#[cfg(test)]
#[path = "vc_land_view.rs"]
mod view;

#[cfg(test)]
mod tests {
    use super::*;

    /// Column (x, z)'s runs on land at 64: the lowest block and the highest, and where the air over it starts.
    fn column(x: i32, z: i32) -> (i32, i32, i32) {
        let s = Shape::new(0.5, 0.5, 37, 65);
        let mut w = Work { s, hf: Default::default(), cols: vec![Col { g: 64, top: 64, ..Default::default() }.pack(); (VC_GW * VC_GW) as usize], tags: Vec::new(), asked: 0, taken: 0, missing: Missing::default(), retry: None, chunks: Vec::new(), next: 0, far_tag: 0, far: Vec::new(), far_next: 0, queue: Default::default(), queued: 0, said: false };
        w.hf.borrow_mut().set(&vec![Some(0.0); crate::strike::volcano::VC_HN * crate::strike::volcano::VC_HN], 1500.0);
        let mut p = Plan { laser: &crate::lasers::SUPERVOLCANO, ev: Vec::new(), rng: Rng::new(7), bx: 0, by: 64, bz: 0 };
        vc_chunk(&mut p, &w, 50.0, x.div_euclid(16) * 16, z.div_euclid(16) * 16);
        let (mut lo, mut hi, mut air) = (i32::MAX, i32::MIN, i32::MAX);
        for e in &p.ev {
            if let Act::Blocks(b) = &e.1 {
                for r in b.runs.iter().filter(|r| r.x == x && r.z == z && r.only.is_none()) {
                    lo = lo.min(r.y);
                    hi = hi.max(r.y + r.height as i32 - 1);
                    if b.palette[r.block as usize] == "minecraft:air" {
                        air = air.min(r.y);
                    }
                }
            }
        }
        (lo, hi, air)
    }
    #[test]
    fn the_caldera_has_its_shape() {
        let s = Shape::new(0.5, 0.5, 37, 65);
        // (the middle: down to the floor, up past the land)
        let (lo, hi, _) = column(3, 3);
        assert!(hi >= 100, "up to {hi}");
        assert!((-31..=-26).contains(&lo), "floor at {lo}");
        // (its edge wanders about the ring, and stays inside the reach of the read)
        let mut lo_e = f64::MAX;
        let mut hi_e: f64 = 0.0;
        for k in 0..720 {
            let e = s.edge(f64::from(k) * TAU / 720.0);
            lo_e = lo_e.min(e);
            hi_e = hi_e.max(e);
        }
        assert!(lo_e > VC_READ0 + 8.0 && hi_e < VC_RIM - 6.0, "{lo_e}..{hi_e}");
        // (the wall comes down from the land to the floor)
        let e = s.edge(0.0) as i32;
        assert!(column(e - 110, 3).2 < -20, "floor {:?}", column(e - 110, 3));
        assert!(column(e - 4, 3).2 > 25, "lip {:?}", column(e - 4, 3));
    }
    #[test]
    fn a_column_packs_and_unpacks() {
        let c = Col { g: -40, top: -5, trunk: 40, leaves: true, ground: 2, fluid: true, deep: true };
        let u = Col::unpack(c.pack()).unwrap();
        assert_eq!((u.g, u.top, u.trunk, u.leaves, u.ground, u.fluid, u.deep), (-40, -5, 40, true, 2, true, true));
        assert!(Col::unpack(0).is_none());
        // (the highest and lowest the world goes, and a top that is the ground)
        for g in [-64, 0, 319] {
            let u = Col::unpack(Col { g, top: g, ..Default::default() }.pack()).unwrap();
            assert_eq!((u.g, u.top, u.trunk, u.leaves), (g, g, 0, false));
        }
    }
    #[test]
    fn the_land_goes_in_behind_the_wall_and_by_the_end() {
        for r in [270.0, 320.0, 400.0, 500.0, 530.0] {
            let t = vc_due(r);
            let f = vc_front(f64::from(t - VC_COLLAPSE));
            assert!(f >= r, "{r} due at {t} with the front at {f}");
            assert!(f < r + 40.0, "{r} due at {t} with the front at {f}");
        }
        assert!(vc_due(0.0) < 78.0, "the middle at {}", vc_due(0.0));
    }
    #[test]
    fn the_table_of_when_keeps_to_vc_due() {
        let t = DueTable::new();
        for k in 0..400 {
            let r = 200.0 + f64::from(k) * 2.2;
            assert!((t.at(r) - vc_due(r)).abs() < 0.02, "{r}: {} {}", t.at(r), vc_due(r));
        }
    }
    #[test]
    fn the_forceloads_are_the_same_rows() {
        for point in [[0.5, 65.0, 0.5], [905_000.5, 59.0, 181_000.5], [-1234.5, 70.0, 777.5]] {
            let a = vc_load_rows(point, VC_LOAD);
            let b = pk_load_rows(point, 0.0, VC_LOAD);
            assert_eq!(a, b, "at {point:?}");
        }
    }
    #[test]
    fn the_chunks_not_loaded_are_asked_for_whole_and_once() {
        let mut m = Missing::default();
        let mut cols = vec![0u32; (VC_GW * VC_GW) as usize];
        let (bx, bz) = (1000, -2000);
        // (a chunk's columns, one column of another; the ones past the read and inside its hole aren't asked)
        for x in 1296..1312 {
            for z in -2000..-1984 {
                m.add(x, z, bx, bz);
            }
        }
        m.add(1000, -2400, bx, bz);
        m.add(1000, -2000, bx, bz);
        assert_eq!(m.list.len(), 3);
        // (one of them read since)
        cols[((-1995 - bz + VC_READ) * VC_GW + 1305 - bx + VC_READ) as usize] = Col::default().pack();
        let first = m.take(&cols, bx, bz, 1);
        assert_eq!(first.len(), 255);
        assert!(first.iter().all(|&(x, z)| x >> 4 == 1300 >> 4 && z >> 4 == -2000 >> 4 && (x, z) != (1305, -1995)));
        let rest = m.take(&cols, bx, bz, 6000);
        assert!(rest.iter().all(|&(x, z)| f64::from((x - bx) * (x - bx) + (z - bz) * (z - bz)).sqrt() > VC_READ0));
        assert!(m.list.is_empty());
        // (asked again it can be listed again)
        m.add(1300, -2000, bx, bz);
        assert_eq!(m.list.len(), 1);
    }
    #[test]
    fn a_chunk_stays_light() {
        crate::meter::reset();
        let s = Shape::new(0.5, 0.5, 37, 65);
        let w = Work { s, hf: Default::default(), cols: vec![Col { g: 64, top: 74, leaves: true, trunk: 6, ground: 1, ..Default::default() }.pack(); (VC_GW * VC_GW) as usize], tags: Vec::new(), asked: 0, taken: 0, missing: Missing::default(), retry: None, chunks: Vec::new(), next: 0, far_tag: 0, far: Vec::new(), far_next: 0, queue: Default::default(), queued: 0, said: false };
        let mut worst = 0;
        for (x, z) in [(0, 0), (0, 268), (288, 0), (0, 350), (-420, 0), (0, 490)] {
            crate::meter::reset();
            let mut p = Plan { laser: &crate::lasers::SUPERVOLCANO, ev: Vec::new(), rng: Rng::new(7), bx: 0, by: 64, bz: 0 };
            let t0 = std::time::Instant::now();
            vc_chunk(&mut p, &w, 50.0, x, z);
            let el = t0.elapsed();
            let m = crate::meter::spent();
            worst = worst.max(m);
            let runs: usize = p.ev.iter().map(|e| if let Act::Blocks(b) = &e.1 { b.runs.len() } else { 0 }).sum();
            eprintln!("chunk {x} {z}: {runs} runs, {:.2}M counted, {el:?}", m as f64 / 1e6);
            assert!(m < 1_200_000, "a chunk at {x} {z} counted {m}");
        }
    }
}
