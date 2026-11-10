//! The Sky Breaks' panes, come down as real land (adapted from the Supervolcano's lodged plates, strike/vc_lodge.rs on
//! its branch). The pass flies each pane down from the sky (shaders/skybreak.wgsl's sb_shard) into a pose it settles in
//! (`Pose`): lying low on a plane fitted to the ground under it (7 to 20 degrees), its leading end a third of its length
//! in the ground, what it lifts packed under with crushed earth so nothing of it is held up by air, the earth it
//! ploughed up heaped against its edges, broken pieces of it stuck in the ground round it, cracks and rubble round its
//! foot, and everything that stood near it gone. The pane itself: its sky on top (blue ice, a paler haze of packed ice,
//! blocky clouds of snow), packed ice through it, a rim of pale glass at its broken edges and the dark of what was behind
//! the sky underneath (obsidian, flecked with crying obsidian). The drawn pane stays where it came down until every
//! chunk of it is in the world, then goes: the real one is in the same place, block for block
//! (`a_lodged_pane_is_where_the_pass_draws_it`).
//!
//! The panes are known as it fires: their sites' chunks are force-loaded from then, the ground under each is asked at
//! once (a small `world.surface-height` query) and settles its pose long before it breaks free, so the pass's path down
//! never changes in the air; its blocks go in from when it hits, a chunk at a time with what a read says stands there
//! (`sb_tick`). A pane on land that never loaded, or one that would come down on the player, stays drawn.
use super::nuke::{Kind, LEAVES, LOG_X, LOG_Z, kind};
use super::skybreak::{SB_HEAL, SB_SAG, SB_SH, SB_SW, TAU, sb_pane_events};
use super::*;
use std::cell::{Cell, RefCell};
use std::rc::Rc;

/// How much of its length goes into the ground.
const SB_BURY: f64 = 0.38;
/// How steeply it lies, degrees, from and to: a pane thrown down on the land, never a wing held up in the air.
const SB_LOW: f64 = 11.0;
const SB_STEEP: f64 = 24.0;
/// The steepest bank of ground it follows.
const SB_BANK: f64 = 16.0;
/// How the earth it shoved up falls away from it: blocks down a block out, on a grid this far apart.
const SB_FALLOFF: f64 = 1.2;
const SB_TS: usize = 6;
/// How far up its edge the earth is heaped (a share of its height there).
const SB_UP: f64 = 0.55;
const SB_TALL: f64 = 34.0;
/// A chunk not loaded yet as its blocks are wanted is asked again later, until this (then left out, and said so).
const SB_GIVE_UP: f32 = super::skybreak::SB_LEN - 8.0;
/// How far round a site its chunks are force-loaded.
pub(super) const SB_PATCH: f64 = 152.0;
/// Everything standing within this (plus half its length) of where it lands is gone; for this much further the trees are
/// felled, lying pointing away from it, and what else stood there swept off.
const SB_CLEAR: f64 = 30.0;
const SB_FELL: f64 = 32.0;
/// The blocks read under each column's top.
const SB_BELOW: u32 = 30;
/// A stage's work on the blocks, counted; how many chunks a read asks at a time, how many reads may be out at once, and
/// how many chunks may wait to go in.
const SB_TICK: u64 = 9_500_000;
const SB_LOT: usize = 12;
const SB_FLIGHT: usize = 3;
const SB_QUEUE: u32 = 48;
/// What share of the ground under a pane must have answered for it to settle; how long it is held back each time it
/// hasn't by the time it should break free, and how late it may land at most.
const SB_LOADED: f64 = 0.6;
const SB_HOLD: f32 = 1.6;
const SB_LATEST: f32 = SB_HEAL - 5.0;

#[derive(Clone, Copy, Debug)]
pub(super) struct Pose {
    pub r: [[f64; 3]; 3],
    pub c: [f64; 3],
}
impl Pose {
    pub fn world(&self, lp: [f64; 3]) -> [f64; 3] {
        let r = &self.r;
        [0, 1, 2].map(|i| self.c[i] + r[i][0] * lp[0] + r[i][1] * lp[1] + r[i][2] * lp[2])
    }
    pub fn local(&self, w: [f64; 3]) -> [f64; 3] {
        let d = [w[0] - self.c[0], w[1] - self.c[1], w[2] - self.c[2]];
        let r = &self.r;
        [0, 1, 2].map(|i| r[0][i] * d[0] + r[1][i] * d[1] + r[2][i] * d[2])
    }
    /// As a quaternion (x, y, z, w) turning its own frame into the world's.
    pub fn quat(&self) -> [f64; 4] {
        let m = &self.r;
        let t = m[0][0] + m[1][1] + m[2][2];
        let q = if t > 0.0 {
            let s = 2.0 * (1.0 + t).sqrt();
            [(m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s, 0.25 * s]
        } else if m[0][0] > m[1][1] && m[0][0] > m[2][2] {
            let s = 2.0 * (1.0 + m[0][0] - m[1][1] - m[2][2]).sqrt();
            [0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s, (m[2][1] - m[1][2]) / s]
        } else if m[1][1] > m[2][2] {
            let s = 2.0 * (1.0 + m[1][1] - m[0][0] - m[2][2]).sqrt();
            [(m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s, (m[0][2] - m[2][0]) / s]
        } else {
            let s = 2.0 * (1.0 + m[2][2] - m[0][0] - m[1][1]).sqrt();
            [(m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s, (m[1][0] - m[0][1]) / s]
        };
        let n = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).sqrt();
        q.map(|v| v / n)
    }
}
fn cross(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn norm(a: [f64; 3]) -> [f64; 3] {
    let l = (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt().max(1e-12);
    a.map(|v| v / l)
}
fn dot(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

// ---- what the pane is made of: keep in step with skybreak.wgsl's sb_hash, sb_vn, sb_sky -----------------------------
/// A number from 0 to 1 for the cell (i, k).
pub(super) fn sb_hash(i: i32, k: i32, seed: u32) -> f64 {
    f64::from(pcg((i as u32).wrapping_mul(73_856_093) ^ (k as u32).wrapping_mul(19_349_663) ^ seed)) / 4_294_967_296.0
}
/// Smooth value noise from 0 to 1, a lattice a unit apart.
pub(super) fn sb_vn(x: f64, z: f64, seed: u32) -> f64 {
    let (ix, iz) = (x.floor(), z.floor());
    let (tx, tz) = (x - ix, z - iz);
    let (sx, sz) = (tx * tx * (3.0 - 2.0 * tx), tz * tz * (3.0 - 2.0 * tz));
    let (i, k) = (ix as i32, iz as i32);
    let (a, b, c, d) = (sb_hash(i, k, seed), sb_hash(i + 1, k, seed), sb_hash(i, k + 1, seed), sb_hash(i + 1, k + 1, seed));
    a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz
}
/// What the sky on a pane shows at (qx, qz) of the pane (where it was in the sky): 0 its blue, 1 a paler haze, 2 cloud
/// (blocky, in cells of six blocks, the way the game's clouds are).
pub(super) fn sb_sky(qx: f64, qz: f64, seed: u32) -> u8 {
    crate::meter::spend(400);
    let (cx, cz) = ((qx / 6.0).floor(), (qz / 6.0).floor());
    let n = sb_vn((cx + 0.5) / 6.0, (cz + 0.5) / 6.0, seed ^ 0x3c1) + 0.16 * (sb_hash(cx as i32, cz as i32, seed ^ 0x3c2) - 0.5);
    if n > 0.62 {
        return 2;
    }
    u8::from(sb_vn(qx / 23.0, qz / 23.0, seed ^ 0x3c3) > 0.66)
}
const SKY: [&str; 3] = ["minecraft:blue_ice", "minecraft:packed_ice", "minecraft:snow_block"];
const CORE: &str = "minecraft:packed_ice";
const RIM: &str = "minecraft:light_blue_stained_glass";
const BACK: &str = "minecraft:obsidian";
const BACK_FLECK: &str = "minecraft:crying_obsidian";

/// A pane that comes down.
pub(super) struct Shard {
    pub i: usize,
    pub cell: usize,
    /// Its corners (x, z) from its middle, counter-clockwise, as it was in the sky (its own frame: y up through it, its
    /// sky underneath, at y = -th / 2).
    pub poly: Vec<[f64; 2]>,
    /// Its edges: a corner and the unit normal pointing in (for how far in from an edge a point is, with no square root).
    edges: Vec<[f64; 4]>,
    pub th: f64,
    /// Its middle in the sky (x, z from the target's column), when it breaks free, when it lands, where (x, z).
    pub sky: [f64; 2],
    pub tr: f32,
    pub hit: f32,
    pub site: [f64; 2],
    /// The way it lies, its low end first.
    pub lay: (f64, f64),
    tilt: f64,
    roll: f64,
    /// Its long way (its own x, z) and how far it reaches along it and across, from its middle.
    long: [f64; 2],
    s0: f64,
    s1: f64,
    w0: f64,
    w1: f64,
    pub pose: Pose,
    /// Where it comes down (from the target's ground).
    pub foot: [f64; 3],
    slope: (f64, f64),
    u_top: f64,
    fall: Fall,
    list: RefCell<Option<Vec<(i32, i32)>>>,
    /// The chunks whose edits have been made, and what felled trees running out of them leave to the chunks not yet made
    /// (each chunk's corner: its logs and leaves, x, z, from and to over its ground there, the block).
    done: RefCell<crate::ground::FxMap<(i32, i32), ()>>,
    spill: RefCell<crate::ground::FxMap<(i32, i32), Vec<Spilled>>>,
    rocks: Vec<Boulder>,
    spalls: Vec<Spall>,
    cracks: Vec<[f64; 5]>,
}
/// Part of a felled tree left to the chunk it lies into: x, z, from and to over the ground there, the block.
type Spilled = (i32, i32, i32, i32, &'static str);
/// How high the earth stands round it: a grid from `o`, `n` by `m`, `SB_TS` apart.
#[derive(Default)]
struct Fall {
    o: (f64, f64),
    n: usize,
    m: usize,
    t: Vec<f32>,
}
#[derive(Clone, Copy)]
struct Boulder {
    x: f64,
    z: f64,
    r: f64,
    h: f64,
    m: u8,
    c: f64,
    s: f64,
}
/// A broken piece of it stuck in the ground round the foot: a box turned its own way.
#[derive(Clone, Copy)]
struct Spall {
    c: [f64; 3],
    e: [[f64; 3]; 3],
    half: [f64; 3],
    cloud: bool,
}
/// A stretch of a world column inside the pane, from the target's ground: y0 to y1, and its line through the pane
/// (its own point at height 0, and how it changes a block up) for what each block of it is.
#[derive(Clone, Copy)]
struct Stretch {
    y0: f64,
    y1: f64,
    a: [f64; 3],
    b: [f64; 3],
}

impl Shard {
    #[allow(clippy::too_many_arguments)]
    pub fn new(i: usize, cell: usize, poly: Vec<[f64; 2]>, th: f64, sky: [f64; 2], site: [f64; 2], tr: f32, hit: f32, lay: (f64, f64), seed: u32, _me: [f64; 3]) -> Shard {
        // (its long way: the line through its corners they lie closest to, its leading end the inner one)
        let (mut xx, mut xz, mut zz) = (0.0, 0.0, 0.0);
        for v in &poly {
            xx += v[0] * v[0];
            xz += v[0] * v[1];
            zz += v[1] * v[1];
        }
        let a = 0.5 * (2.0 * xz).atan2(xx - zz);
        let mut long = [a.cos(), a.sin()];
        if long[0] * lay.0 + long[1] * lay.1 < 0.0 {
            long = [-long[0], -long[1]];
        }
        let (mut s0, mut s1, mut w0, mut w1) = (f64::MAX, f64::MIN, f64::MAX, f64::MIN);
        for v in &poly {
            let s = v[0] * long[0] + v[1] * long[1];
            let w = -v[0] * long[1] + v[1] * long[0];
            s0 = s0.min(s);
            s1 = s1.max(s);
            w0 = w0.min(w);
            w1 = w1.max(w);
        }
        let edges = (0..poly.len())
            .map(|k| {
                let (p, q) = (poly[k], poly[(k + 1) % poly.len()]);
                let (ex, ez) = (q[0] - p[0], q[1] - p[1]);
                let l = ex.hypot(ez).max(1e-9);
                [p[0], p[1], -ez / l, ex / l]
            })
            .collect();
        let k = i as u32;
        // (each as it happened to land: most low, the odd one higher; not all lying the way they came, or over the same
        // side)
        let tilt = (SB_LOW + (SB_STEEP - SB_LOW) * mh(k, seed, 0xd6).powf(1.4)).to_radians();
        let roll = (12.0 * (2.0 * mh(k, seed, 0xd7) - 1.0)).to_radians();
        let yaw = (35.0 * (2.0 * mh(k, seed, 0xd8) - 1.0)).to_radians();
        let lay = (lay.0 * yaw.cos() - lay.1 * yaw.sin(), lay.0 * yaw.sin() + lay.1 * yaw.cos());
        let mut s = Shard {
            i,
            cell,
            poly,
            edges,
            th,
            sky,
            tr,
            hit,
            site,
            lay,
            tilt,
            roll,
            long,
            s0,
            s1,
            w0,
            w1,
            pose: Pose { r: [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]], c: [0.0; 3] },
            foot: [site[0], 0.0, site[1]],
            slope: (0.0, 0.0),
            u_top: 0.0,
            fall: Fall::default(),
            list: RefCell::new(None),
            done: RefCell::default(),
            spill: RefCell::default(),
            rocks: Vec::new(),
            spalls: Vec::new(),
            cracks: Vec::new(),
        };
        s.set_pose(0.0, (0.0, 0.0));
        s
    }
    /// Its length along its long way.
    pub fn size(&self) -> f64 {
        self.s1 - self.s0
    }
    fn wide(&self) -> f64 {
        self.w1 - self.w0
    }
    /// The pose with the ground `gs` at its foot sloping `slope`: its long way down the way it lies at its tilt, its sky
    /// turned up, `SB_BURY` of its length past where its middle sheet meets the ground.
    fn set_pose(&mut self, gs: f64, slope: (f64, f64)) {
        *self.list.borrow_mut() = None;
        let d = [self.lay.0, 0.0, self.lay.1];
        let (cs, sn) = (self.tilt.cos(), self.tilt.sin());
        let fl = [cs * d[0], -sn, cs * d[2]];
        let fn0 = [sn * d[0], cs, sn * d[2]];
        let fw0 = norm(cross(fl, fn0));
        // (a little over on one side)
        let (cr, sr) = (self.roll.cos(), self.roll.sin());
        let fnr = norm([0, 1, 2].map(|i| fn0[i] * cr + fw0[i] * sr));
        // (all of that on the ground it comes down on, not on the level)
        let gn = norm([-slope.0, 1.0, -slope.1]);
        let sf = gn[0].hypot(gn[2]);
        let (fl, fnr) = if sf > 1e-6 {
            let k = [gn[2] / sf, 0.0, -gn[0] / sf];
            let tip = |v: [f64; 3]| {
                let (c, x, d) = (cross(k, v), gn[1], dot(k, v));
                [0, 1, 2].map(|i| v[i] * x + c[i] * sf + k[i] * d * (1.0 - x))
            };
            (tip(fl), tip(fnr))
        } else {
            (fl, fnr)
        };
        // (its own long way to `fl`, its own up (the dark side) to under it, so its sky faces up)
        let el = [self.long[0], 0.0, self.long[1]];
        let en = [0.0, 1.0, 0.0];
        let ew = cross(el, en);
        let nf = fnr.map(|v| -v);
        let wf = cross(fl, nf);
        let mut r = [[0.0; 3]; 3];
        for (i, row) in r.iter_mut().enumerate() {
            for (j, v) in row.iter_mut().enumerate() {
                *v = fl[i] * el[j] + nf[i] * en[j] + wf[i] * ew[j];
            }
        }
        let sp = self.s1 - SB_BURY * (self.s1 - self.s0);
        let lp = [self.long[0] * sp, 0.0, self.long[1] * sp];
        let mut p = Pose { r, c: [0.0; 3] };
        let w = p.world(lp);
        p.c = [self.site[0] - w[0], gs - w[1], self.site[1] - w[2]];
        self.pose = p;
        self.foot = [self.site[0], gs, self.site[1]];
        self.slope = slope;
        self.u_top = (0.5 * self.th / sn).min(SB_BURY * (self.s1 - self.s0));
    }
    /// The ground under the whole of it from what's known of the land's height at (x, z) (blocks from the target's
    /// column): how high at its site and how it slopes, a plane through what lies under the pane, a little low where the
    /// land is rough.
    fn bed(&self, pts: &[(i32, i32, f64)], bx: i32, bz: i32) -> Option<(f64, (f64, f64))> {
        let (n, mut sx, mut sz, mut sh, mut xx, mut xz, mut zz, mut xh, mut zh) = (pts.len() as f64, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
        if pts.is_empty() {
            return None;
        }
        for &(x, z, h) in pts {
            let (dx, dz) = (f64::from(x - bx) - self.site[0], f64::from(z - bz) - self.site[1]);
            sx += dx;
            sz += dz;
            sh += h;
            xx += dx * dx;
            xz += dx * dz;
            zz += dz * dz;
            xh += dx * h;
            zh += dz * h;
        }
        if n < 8.0 {
            return Some((sh / n, (0.0, 0.0)));
        }
        let (mx, mz, mh) = (sx / n, sz / n, sh / n);
        let (cxx, cxz, czz, cxh, czh) = (xx - n * mx * mx, xz - n * mx * mz, zz - n * mz * mz, xh - n * mx * mh, zh - n * mz * mh);
        let det = cxx * czz - cxz * cxz;
        let (mut a, mut b) = if det.abs() > 1.0 { ((cxh * czz - czh * cxz) / det, (czh * cxx - cxh * cxz) / det) } else { (0.0, 0.0) };
        let t = a.hypot(b);
        let most = SB_BANK.to_radians().tan();
        if t > most {
            a *= most / t;
            b *= most / t;
        }
        let c = mh - a * mx - b * mz;
        let mut e = 0.0;
        for &(x, z, h) in pts {
            let r = h - (c + a * (f64::from(x - bx) - self.site[0]) + b * (f64::from(z - bz) - self.site[1]));
            e += r * r;
        }
        Some((c - (0.4 * (e / n).sqrt()).min(8.0), (a, b)))
    }
    /// The pass's words for it (`gone`: when its blocks are all in, 0 not yet, under 0 never: it stays drawn).
    pub fn words(&self, gone: f64) -> Vec<u32> {
        let mut w = [0.0f64; SB_SW];
        for (n, v) in self.poly.iter().enumerate().take(4) {
            w[2 * n] = v[0];
            w[2 * n + 1] = v[1];
        }
        if self.poly.len() == 3 {
            w[6] = self.poly[2][0];
            w[7] = self.poly[2][1];
        }
        w[8] = self.poly.len() as f64;
        w[9] = self.th;
        w[10] = self.sky[0];
        w[11] = self.sky[1];
        w[12] = f64::from(self.tr);
        w[13] = f64::from(self.hit);
        w[14] = gone;
        w[15] = self.cell as f64;
        let q = self.pose.quat();
        w[16..20].copy_from_slice(&q);
        w[20..23].copy_from_slice(&self.pose.c);
        w[23] = self.lay.0;
        w[24] = self.lay.1;
        w[25..28].copy_from_slice(&self.foot);
        w[28] = self.size();
        crate::meter::spend(2_000);
        w.iter().map(|v| (*v as f32).to_bits()).collect()
    }
    /// The vertical line through (wx, wz) from the target's column: where it is inside the pane, if anywhere.
    fn span(&self, wx: f64, wz: f64) -> Option<Stretch> {
        crate::meter::spend(900);
        let a = self.pose.local([wx, 0.0, wz]);
        let r = &self.pose.r;
        let b = [r[1][0], r[1][1], r[1][2]];
        let (mut t0, mut t1) = (-1.0e9f64, 1.0e9f64);
        // (between its two faces)
        // (a hair inside its faces and edges: a block's centre right on one is drawn by the pass's f32 test either way)
        let h = 0.5 * self.th - 2e-3;
        if b[1].abs() < 1e-6 {
            return None;
        }
        let (u, v) = ((-h - a[1]) / b[1], (h - a[1]) / b[1]);
        t0 = t0.max(u.min(v));
        t1 = t1.min(u.max(v));
        // (and inside each of its edges)
        let n = self.poly.len();
        for k in 0..n {
            let (p, q) = (self.poly[k], self.poly[(k + 1) % n]);
            let (ex, ez) = (q[0] - p[0], q[1] - p[1]);
            let al = ex * (a[2] - p[1]) - ez * (a[0] - p[0]) - 2e-3 * (ex.abs() + ez.abs());
            let be = ex * b[2] - ez * b[0];
            if be.abs() < 1e-9 {
                if al < 0.0 {
                    return None;
                }
                continue;
            }
            let c = -al / be;
            if be > 0.0 {
                t0 = t0.max(c);
            } else {
                t1 = t1.min(c);
            }
        }
        (t1 > t0).then_some(Stretch { y0: t0, y1: t1, a, b })
    }
    /// How far (its own x, z) is in from its nearest edge.
    fn inset(&self, x: f64, z: f64) -> f64 {
        let mut d = f64::MAX;
        for e in &self.edges {
            d = d.min((x - e[0]) * e[2] + (z - e[1]) * e[3]);
        }
        d
    }
    /// What the pane's block is at the point `l` of its own frame, `gy` the target's ground's Y and (x, y, z) the block.
    fn pane_block(&self, l: [f64; 3], inset: f64, sky: &mut Option<&'static str>, x: i32, y: i32, z: i32, seed: u32) -> &'static str {
        // (from its sky face: the sky on it, then the ice through it, the dark of the back of the sky under it)
        let d = l[1] + 0.5 * self.th;
        if inset < 1.0 {
            return RIM;
        }
        if d < 1.15 {
            // (the same for the stretch's top blocks: they lie within a block of each other in its frame)
            return *sky.get_or_insert_with(|| SKY[sb_sky(l[0] + self.sky[0], l[2] + self.sky[1], seed) as usize]);
        }
        if d > self.th - 1.15 {
            return if sb_hash(x * 7 + y, z, seed ^ 0x3c5) < 0.07 { BACK_FLECK } else { BACK };
        }
        CORE
    }
    /// One column of the pane, blocks from the world's `gy` up (`floor`: the lowest worth laying, none: all of it).
    fn pane_col(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, floor: Option<i32>, seed: u32) -> Option<Stretch> {
        let s = self.span(wx, wz)?;
        let (mut y0, y1) = ((s.y0 + f64::from(gy) - 0.5).ceil() as i32, ((s.y1 + f64::from(gy) - 0.5).floor() as i32).min(318));
        if let Some(f) = floor {
            y0 = y0.max(f);
        }
        let mut run: Option<(i32, &'static str)> = None;
        // (how far in from each edge, along the column: a line in t for each)
        let mut lines = [(0.0f64, 0.0f64); 6];
        for (k, e) in self.edges.iter().enumerate().take(6) {
            lines[k] = ((s.a[0] - e[0]) * e[2] + (s.a[2] - e[1]) * e[3], s.b[0] * e[2] + s.b[2] * e[3]);
        }
        let ne = self.edges.len().min(6);
        let mut sky = None;
        for y in y0..=y1 {
            let t = f64::from(y) + 0.5 - f64::from(gy);
            let l = [s.a[0] + s.b[0] * t, s.a[1] + s.b[1] * t, s.a[2] + s.b[2] * t];
            let inset = lines[..ne].iter().fold(f64::MAX, |m, &(c, k)| m.min(c + k * t));
            let m = self.pane_block(l, inset, &mut sky, x, y, z, seed);
            match run {
                Some((from, k)) if std::ptr::eq(k, m) => {
                    let _ = from;
                }
                Some((from, k)) => {
                    b.run(x, z, from, y - 1, k);
                    run = Some((y, m));
                }
                None => run = Some((y, m)),
            }
        }
        if let Some((from, k)) = run {
            b.run(x, z, from, y1, k);
        }
        crate::meter::spend(600 * (y1 - y0 + 1).max(0) as u64 + 1_500);
        Some(s)
    }
    /// What it does to the ground: the rubble, the broken pieces of it and the cracks round it, once it is known where
    /// it stands.
    fn litter(&mut self, seed: u32) {
        self.make_fall();
        self.rocks.clear();
        self.spalls.clear();
        self.cracks.clear();
        let s = seed ^ (self.i as u32).wrapping_mul(0x9e37);
        let (dx, dz) = self.lay;
        let (ax, az) = (-dz, dx);
        let w = 0.5 * self.wide();
        let (ut, f) = (self.u_top, self.foot);
        let m = |k: u32, q: u32| mh(k, s, q);
        let place = |u: f64, v: f64| (f[0] + dx * u + ax * v, f[2] + dz * u + az * v);
        for k in 0..46 {
            let a = m(k, 0xe0);
            // (most heaped at its foot, in front; the rest strewn)
            let u = if a < 0.6 { ut + 4.0 + 36.0 * m(k, 0xe1).powi(2) } else { -ut - 50.0 + (2.0 * ut + 110.0) * m(k, 0xe1) };
            let v = (w + 36.0) * (2.0 * m(k, 0xe2) - 1.0);
            let (x, z) = place(u, v);
            let r = 1.5 + 4.5 * m(k, 0xe3).powi(3);
            let a = TAU * m(k, 0xe9);
            self.rocks.push(Boulder { x, z, r, h: r * (0.5 + 0.5 * m(k, 0xe4)), m: (m(k, 0xe5) * 5.0) as u8, c: a.cos(), s: a.sin() });
        }
        // (pieces broken off it, stuck in the ground about its foot and down its sides)
        for k in 0..12 {
            let u = -ut * 0.5 + (2.0 * ut + 40.0) * m(k, 0xe6);
            let side = if m(k, 0xe7) < 0.5 { -1.0 } else { 1.0 };
            let v = side * (w * (0.3 + 0.8 * m(k, 0xe8)) + 8.0);
            let (x, z) = place(u, v);
            let (len, wid, thk) = (6.0 + 8.0 * m(k, 0xe9), 4.0 + 6.0 * m(k, 0xea), 2.0 + 2.0 * m(k, 0xeb));
            let (yaw, dip) = (TAU * m(k, 0xec), (12.0 + 26.0 * m(k, 0xed)).to_radians());
            let l = [yaw.cos() * dip.cos(), -dip.sin(), yaw.sin() * dip.cos()];
            let n = norm([yaw.cos() * dip.sin(), dip.cos(), yaw.sin() * dip.sin()]);
            let e = norm(cross(l, n));
            let gyk = f[1] + self.slope.0 * (x - f[0]) + self.slope.1 * (z - f[2]);
            let c = [x, gyk + 0.05 * len * dip.sin(), z];
            self.spalls.push(Spall { c, e: [l, n, e], half: [len * 0.5, thk * 0.5, wid * 0.5], cloud: m(k, 0xee) < 0.3 });
        }
        // (cracks out from round it)
        let reach = 0.5 * self.size();
        for k in 0..9 {
            let a = TAU * (f64::from(k) + 0.8 * m(k, 0xf0)) / 9.0;
            let (mut x, mut z) = (f[0] - dx * 0.3 * reach + (0.55 * reach) * a.cos(), f[2] - dz * 0.3 * reach + (0.55 * reach) * a.sin());
            let len = 18.0 + 40.0 * m(k, 0xf1).powi(2);
            let mut b = a;
            let mut left = len;
            let mut wd = 1.6 + 1.6 * m(k, 0xf2);
            let mut j = 0;
            while left > 0.0 {
                let st = 4.0 + 6.0 * m(k * 7 + j, 0xf3);
                b += 1.5 * (m(k * 7 + j, 0xf4) - 0.5);
                let (nx, nz) = (x + st * b.cos(), z + st * b.sin());
                self.cracks.push([x, z, nx, nz, wd]);
                x = nx;
                z = nz;
                left -= st;
                wd = (wd * 0.9).max(0.7);
                j += 1;
            }
        }
    }
    /// How high the ground is heaped at (u, v) from the foot, u along its way (negative: dug).
    fn heap(&self, u: f64, v: f64, n: f64) -> f64 {
        let w = 0.5 * self.wide();
        let ut = self.u_top;
        let size = (0.7 + self.size() / 300.0).min(1.3);
        let e = 1.0 - smooth(w - 8.0, w + 24.0, v.abs());
        let bell = |x: f64| {
            let k = 1.0 + 0.5 * x * x;
            1.0 / (k * k)
        };
        // (a lip in front: what it ploughed up; down its sides, less)
        let f = (u - ut - 6.0) / (if u > ut + 6.0 { 13.0 } else { 6.0 });
        let lip = 11.0 * size * bell(f) * e;
        let sv = (v.abs() - w - 6.0) / 10.0;
        let side = 5.0 * size * bell(sv) * smooth(-ut - 40.0, -ut - 8.0, u) * (1.0 - smooth(ut, ut + 18.0, u));
        // (round where it went in the crater it punched, and behind it the ground it tore open as it went)
        let dc = (u - 0.3 * ut).hypot(v * 0.8) / (0.45 * self.size() + 6.0);
        let crater = 7.0 * size * (1.0 - dc * dc).max(0.0);
        let bu = (u + ut + 16.0) / 24.0;
        let dug = 4.0 * bell(bu) * e;
        (lip + side) * (0.45 + 1.1 * n) - (dug + crater) * (0.6 + 0.8 * n)
    }
    /// Whether (wx, wz) is in the band past the cleared ground where the trees are felled.
    fn felled(&self, wx: f64, wz: f64) -> bool {
        (wx - self.foot[0]).hypot(wz - self.foot[2]) < SB_CLEAR + 0.5 * self.size() + SB_FELL
    }
    /// Whether (wx, wz) is near enough where it lands that what stood there is gone.
    fn cleared(&self, u: f64, v: f64, wx: f64, wz: f64) -> bool {
        let w = 0.5 * self.wide();
        let len = self.size();
        (u > -self.u_top - 60.0 - 0.3 * len && u < self.u_top + 70.0 && v.abs() < w + 44.0) || (wx - self.foot[0]).hypot(wz - self.foot[2]) < SB_CLEAR + 0.5 * len
    }
    /// A column's ground: heaped or dug, what stood on it gone, its cracks, its rubble, the broken pieces of the pane: the
    /// world's Y its ground is at afterwards (none where it isn't known). `col`: what the read said stands there.
    #[allow(clippy::too_many_arguments)]
    fn ground_col(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, col: Option<&Col>, seed: u32, near_ones: &Near) -> Option<i32> {
        let (dx, dz) = self.lay;
        let (ox, oz) = (wx - self.foot[0], wz - self.foot[2]);
        let (u, v) = (ox * dx + oz * dz, oz * dx - ox * dz);
        // (counted as the game counts it: `mod_soak` traced a chunk's ground at about three times the parts' sum)
        crate::meter::spend(1_400);
        if !self.cleared(u, v, wx, wz) {
            // (past it, a band where the trees are felled and the rest swept off: what stood there gone, the trunks laid
            // down after (`felled`))
            if let Some(c) = col.filter(|_| self.felled(wx, wz)) {
                let g = if c.fluid { c.top } else { c.g };
                if c.top > g {
                    b.run(x, z, g + 1, c.top, "minecraft:air");
                }
                return Some(g);
            }
            return col.map(|c| c.g);
        }
        let n = qnoise(wx, wz, 9.0, seed ^ 0x51);
        let n2 = qnoise(wx, wz, 3.5, seed ^ 0x52);
        let h = self.heap(u, v, 0.65 * n + 0.35 * n2);
        let air = "minecraft:air";
        let mut cracked = 2.0e9f64;
        for &c in &near_ones.cracks {
            let c = &self.cracks[c];
            let (sx, sz) = (c[2] - c[0], c[3] - c[1]);
            let t = (((wx - c[0]) * sx + (wz - c[1]) * sz) / (sx * sx + sz * sz)).clamp(0.0, 1.0);
            let (ex, ez) = (wx - c[0] - t * sx, wz - c[1] - t * sz);
            cracked = cracked.min((ex * ex + ez * ez) / (c[4] * c[4]));
        }
        crate::meter::spend(30 * near_ones.cracks.len() as u64);
        let hh = h.round() as i32;
        let g = match col {
            Some(c) => {
                let g = if c.fluid { c.top } else { c.g };
                if c.top > g {
                    b.run(x, z, g + 1, c.top, air);
                }
                g
            }
            None => {
                if hh > 0 {
                    b.put(x, z, 0, hh - 1, heap_block(n, n2), None, true);
                } else if hh < 0 {
                    b.put(x, z, hh, -1, air, None, true);
                }
                return None;
            }
        };
        let mut top = g + hh;
        if hh > 0 {
            b.run(x, z, g + 1, top - 1, "minecraft:dirt");
            b.run(x, z, top, top, heap_block(n, n2));
        } else if hh < 0 {
            b.run(x, z, top + 1, g, air);
            b.run(x, z, top, top, heap_block(n, n2));
        }
        if cracked < 1.0 {
            // (open down the middle, tuff either side)
            if cracked < 0.2 {
                b.run(x, z, top - 6, top - 5, "minecraft:tuff");
                b.run(x, z, top - 4, top, air);
                top -= 5;
            } else {
                b.run(x, z, top - 3, top, "minecraft:tuff");
            }
        }
        for &r in &near_ones.rocks {
            let r = &self.rocks[r];
            // (broken, not round: its corners by the way it lies, its top in steps)
            let (ex, ez) = ((wx - r.x) / r.r, (wz - r.z) / r.r);
            if ex.abs() > 1.5 || ez.abs() > 1.5 {
                continue;
            }
            let q = 0.55 * (ex * r.c + ez * r.s).abs() + 0.55 * (ez * r.c - ex * r.s).abs() + 0.4 * (ex * ex + ez * ez).sqrt();
            if q < 1.0 {
                let y = top + (r.h * (1.0 - q * q).sqrt() * (0.7 + 0.6 * n2)).round() as i32;
                b.run(x, z, top, y, boulder_block(r.m, n2));
                top = y;
            }
        }
        crate::meter::spend(20 * near_ones.rocks.len() as u64);
        for &s in &near_ones.spalls {
            let s = &self.spalls[s];
            let far = s.half[0] + s.half[2] + 2.0;
            if (wx - s.c[0]).abs() > far || (wz - s.c[2]).abs() > far {
                continue;
            }
            if let Some((y0, y1)) = box_span(s, wx, wz) {
                let (a, c) = ((y0 + f64::from(gy) - 0.5).ceil() as i32, (y1 + f64::from(gy) - 0.5).floor() as i32);
                let lo = a.max(top - 2);
                b.run(x, z, lo, c, CORE);
                if c >= lo {
                    b.run(x, z, c, c, if s.cloud { SKY[2] } else { SKY[0] });
                }
            }
        }
        crate::meter::spend(60 * near_ones.spalls.len() as u64);
        Some(top)
    }
    /// What lies under it where it stands clear of the ground: the land it came down on, crushed and shoved up under it,
    /// so nothing of it is held up by air.
    #[allow(clippy::too_many_arguments)]
    fn under(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, g: i32, c: &Col, s: &Stretch, seed: u32) {
        let y = (s.y0 + f64::from(gy) - 0.5).ceil() as i32 - 1;
        if y <= g {
            return;
        }
        let n = qnoise(wx, wz, 17.0, seed ^ 0x53);
        let bed = if c.fluid { c.g + 1 } else { g + 1 };
        let h = f64::from(y - bed + 1);
        let a = bed + (h * (0.35 + 0.3 * n)) as i32;
        let d = (y - 1 - (2.0 + 3.0 * n) as i32).max(a);
        b.run(x, z, bed, a, if n < 0.5 { "minecraft:tuff" } else { "minecraft:cobblestone" });
        b.run(x, z, a + 1, d, if n < 0.4 { "minecraft:dirt" } else { "minecraft:coarse_dirt" });
        b.run(x, z, d + 1, y, "minecraft:coarse_dirt");
        if c.top > y {
            b.run(x, z, y + 1, c.top, "minecraft:air");
        }
        crate::meter::spend(800);
    }
    /// How high the earth shoved up against it stands round it, coarsely: some of the way up it, falling away
    /// `SB_FALLOFF` a block from there. Once, as it comes to rest.
    fn make_fall(&mut self) {
        let st = SB_TS as f64;
        let (mut x0, mut z0, mut x1, mut z1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for v in &self.poly {
            for d in [-0.5 * self.th, 0.5 * self.th] {
                let w = self.pose.world([v[0], d, v[1]]);
                (x0, z0, x1, z1) = (x0.min(w[0]), z0.min(w[2]), x1.max(w[0]), z1.max(w[2]));
            }
        }
        let (ox, oz) = (((x0 - SB_TALL) / st).floor() * st, ((z0 - SB_TALL) / st).floor() * st);
        let (n, m) = (((x1 + SB_TALL - ox) / st) as usize + 2, ((z1 + SB_TALL - oz) / st) as usize + 2);
        let mut t = vec![f32::MIN; n * m];
        for k in 0..m {
            for i in 0..n {
                if let Some(s) = self.span(ox + st * i as f64, oz + st * k as f64) {
                    // (up its edge a good way, so its broken side stands out of a slope of its own wreckage, never a bare
                    // wall; less up its middle)
                    let gk = self.foot[1] + self.slope.0 * (ox + st * i as f64 - self.foot[0]) + self.slope.1 * (oz + st * k as f64 - self.foot[2]);
                    t[k * n + i] = (gk.max(s.y0) + SB_UP * (s.y0 - gk).max(0.0)) as f32;
                }
            }
        }
        let (d1, d2) = ((SB_FALLOFF * st) as f32, (SB_FALLOFF * st * 1.4142) as f32);
        let mut pass = |k: usize, i: usize, rel: [(i32, i32, f32); 4]| {
            for (a, b, d) in rel {
                let (ii, kk) = (i as i32 + a, k as i32 + b);
                if ii >= 0 && kk >= 0 && (ii as usize) < n && (kk as usize) < m {
                    let v = t[kk as usize * n + ii as usize];
                    if v != f32::MIN && v - d > t[k * n + i] {
                        t[k * n + i] = v - d;
                    }
                }
            }
        };
        for k in 0..m {
            for i in 0..n {
                pass(k, i, [(-1, 0, d1), (0, -1, d1), (-1, -1, d2), (1, -1, d2)]);
            }
        }
        for k in (0..m).rev() {
            for i in (0..n).rev() {
                pass(k, i, [(1, 0, d1), (0, 1, d1), (1, 1, d2), (-1, 1, d2)]);
            }
        }
        crate::meter::spend(2_600 * (n * m) as u64);
        self.fall = Fall { o: (ox, oz), n, m, t };
    }
    /// A column beside it: the earth it shoved up, heaped against its edge so no wall of it stands sheer.
    #[allow(clippy::too_many_arguments)]
    fn talus(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, g: i32, c: &Col, seed: u32) {
        let (st, f) = (SB_TS as f64, &self.fall);
        let (u, v) = ((wx - f.o.0) / st, (wz - f.o.1) / st);
        if u < 0.0 || v < 0.0 || u as usize + 1 >= f.n || v as usize + 1 >= f.m {
            return;
        }
        let (i, k) = (u as usize, v as usize);
        let at = |a: usize, b: usize| f.t[(k + b) * f.n + i + a];
        if at(0, 0) == f32::MIN || at(1, 0) == f32::MIN || at(0, 1) == f32::MIN || at(1, 1) == f32::MIN {
            return;
        }
        let (fu, fv) = (u - i as f64, v - k as f64);
        let h = (f64::from(at(0, 0)) * (1.0 - fu) + f64::from(at(1, 0)) * fu) * (1.0 - fv) + (f64::from(at(0, 1)) * (1.0 - fu) + f64::from(at(1, 1)) * fu) * fv;
        if h + f64::from(gy) + 4.0 < f64::from(g) {
            return;
        }
        let n1 = qnoise(wx, wz, 7.0, seed ^ 0x54);
        let n2 = qnoise(wx, wz, 3.0, seed ^ 0x55);
        crate::meter::spend(900);
        let y = (h + f64::from(gy) + 4.0 * (n1 - 0.5) + 2.0 * (n2 - 0.5)).round() as i32;
        if y <= g {
            return;
        }
        let bed = if c.fluid { c.g + 1 } else { g + 1 };
        b.run(x, z, bed, y - 1, if n1 < 0.5 { "minecraft:dirt" } else { "minecraft:coarse_dirt" });
        b.run(x, z, y, y, heap_block(n1, n2));
        if c.top > y {
            b.run(x, z, y + 1, c.top, "minecraft:air");
        }
    }
    /// The edits of the chunk with corner (x0, z0): its ground, then the pane. `read`: what stands on each of its columns
    /// (x then z), none where the world has not said.
    #[allow(clippy::too_many_arguments)]
    pub fn chunk(&self, x0: i32, z0: i32, bx: i32, bz: i32, gy: i32, seed: u32, read: Option<&[Option<Col>]>) -> Blocks {
        let mut b = Blocks::default();
        let (mx, mz) = (f64::from(x0 - bx) + 8.0, f64::from(z0 - bz) + 8.0);
        let in_reach = |x: f64, z: f64, r: f64| (x - mx).abs() < r + 8.5 && (z - mz).abs() < r + 8.5;
        let near = Near {
            rocks: self.rocks.iter().enumerate().filter(|(_, r)| in_reach(r.x, r.z, r.r)).map(|e| e.0).collect(),
            spalls: self.spalls.iter().enumerate().filter(|(_, r)| in_reach(r.c[0], r.c[2], r.half[0] + r.half[2])).map(|e| e.0).collect(),
            cracks: self.cracks.iter().enumerate().filter(|(_, c)| in_reach(0.5 * (c[0] + c[2]), 0.5 * (c[1] + c[3]), 0.5 * (c[0] - c[2]).hypot(c[1] - c[3]) + c[4])).map(|e| e.0).collect(),
        };
        crate::meter::spend(30 * (self.rocks.len() + self.spalls.len() + self.cracks.len()) as u64);
        // (each column's ground, then the pane over it, then what is heaped against it or packed under it: in that order for
        // each column, as the edit makes them)
        let mut gs = [None; 256];
        for z in z0..z0 + 16 {
            for x in x0..x0 + 16 {
                let (wx, wz) = (f64::from(x - bx), f64::from(z - bz));
                let j = ((z - z0) * 16 + x - x0) as usize;
                let col = read.and_then(|r| r[j].as_ref());
                gs[j] = self.ground_col(&mut b, x, z, wx, wz, gy, col, seed, &near);
            }
        }
        crate::trace("sb ground");
        // (the felled trees: each trunk that stood in the band laid down on the ground pointing away from where the pane
        // struck, its crown at its end. One that runs out of this chunk into one not made yet is finished there, on its
        // ground (`spill`); one that would run into a chunk already made, or none of the pane's, falls along its other
        // way, or lies shorter, never cut off at the chunk's edge)
        self.done.borrow_mut().insert((x0, z0), ());
        let inside = |lx: i32, lz: i32| lx >= x0 && lz >= z0 && lx < x0 + 16 && lz < z0 + 16;
        let at = |lx: i32, lz: i32| ((lz - z0) * 16 + lx - x0) as usize;
        if let Some(v) = self.spill.borrow_mut().remove(&(x0, z0)) {
            for (lx, lz, lo, hi, blk) in v {
                if let Some(g) = gs[at(lx, lz)] {
                    b.run(lx, lz, g + lo, g + hi, blk);
                }
            }
        }
        if let Some(read) = read {
            let list = self.list.borrow();
            let done = self.done.borrow();
            let later = |lx: i32, lz: i32| {
                let c = ((lx >> 4) * 16, (lz >> 4) * 16);
                !done.contains_key(&c) && list.as_ref().is_some_and(|l| l.contains(&c))
            };
            let ok = |lx: i32, lz: i32| if inside(lx, lz) { gs[at(lx, lz)].is_some() } else { later(lx, lz) };
            let mut spill: Vec<Spilled> = Vec::new();
            for z in z0..z0 + 16 {
                for x in x0..x0 + 16 {
                    let j = at(x, z);
                    let (Some(c), Some(_)) = (read[j].as_ref(), gs[j]) else { continue };
                    let (wx, wz) = (f64::from(x - bx), f64::from(z - bz));
                    let (ox, oz) = (wx - self.foot[0], wz - self.foot[2]);
                    let (u, v) = (ox * self.lay.0 + oz * self.lay.1, oz * self.lay.0 - ox * self.lay.1);
                    if c.trunk < 3 || c.fluid || self.cleared(u, v, wx, wz) || !self.felled(wx, wz) {
                        continue;
                    }
                    let sg = |d: f64, k: u32| if d > 0.0 || (d == 0.0 && mh(k, seed, 0xe1) < 0.5) { 1 } else { -1 };
                    let ways = if ox.abs() >= oz.abs() { [(sg(ox, j as u32), 0), (0, sg(oz, j as u32))] } else { [(0, sg(oz, j as u32)), (sg(ox, j as u32), 0)] };
                    let full = i32::from(c.trunk.min(10));
                    // (the longest it can lie each way, its crown's middle and its tip on ground it can have)
                    let fits = |(sx, sz): (i32, i32), len: i32| (1..=len + 1).all(|k| ok(x + sx * k, z + sz * k));
                    let pick = ways.iter().find(|&&w| fits(w, full)).map(|&w| (w, full)).or_else(|| {
                        (3..full).rev().find_map(|len| ways.iter().find(|&&w| fits(w, len)).map(|&w| (w, len)))
                    });
                    let Some(((sx, sz), len)) = pick else { continue };
                    let log = if sx != 0 { LOG_X[c.wood as usize % 9] } else { LOG_Z[c.wood as usize % 9] };
                    let leaves = LEAVES[c.wood as usize % 9];
                    let mut put = |b: &mut Blocks, lx: i32, lz: i32, lo: i32, hi: i32, blk: &'static str| {
                        if inside(lx, lz) {
                            if let Some(g) = gs[at(lx, lz)] {
                                b.run(lx, lz, g + lo, g + hi, blk);
                            }
                        } else if later(lx, lz) {
                            spill.push((lx, lz, lo, hi, blk));
                        }
                    };
                    for k in 1..=len {
                        put(&mut b, x + sx * k, z + sz * k, 1, 1, log);
                    }
                    // (its crown, crushed where it fell)
                    let (ex, ez) = (x + sx * len, z + sz * len);
                    for (dx, dz) in [(0, 0), (sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx), (sx - sz, sz - sx)] {
                        let mid = (dx, dz) == (0, 0);
                        put(&mut b, ex + dx, ez + dz, 1 + i32::from(mid), if mid { 2 } else { 1 }, leaves);
                    }
                    crate::meter::spend(4_000);
                }
            }
            drop(done);
            let mut sm = self.spill.borrow_mut();
            for e in spill {
                sm.entry(((e.0 >> 4) * 16, (e.1 >> 4) * 16)).or_default().push(e);
            }
        }
        let mut sp = [None; 256];
        for z in z0..z0 + 16 {
            for x in x0..x0 + 16 {
                let (wx, wz) = (f64::from(x - bx), f64::from(z - bz));
                let j = ((z - z0) * 16 + x - x0) as usize;
                sp[j] = self.pane_col(&mut b, x, z, wx, wz, gy, gs[j].map(|g| g - 1), seed);
            }
        }
        crate::trace("sb pane");
        for z in z0..z0 + 16 {
            for x in x0..x0 + 16 {
                let (wx, wz) = (f64::from(x - bx), f64::from(z - bz));
                let j = ((z - z0) * 16 + x - x0) as usize;
                let col = read.and_then(|r| r[j].as_ref());
                if let (Some(g), Some(c)) = (gs[j], col) {
                    match sp[j] {
                        None => self.talus(&mut b, x, z, wx, wz, gy, g, c, seed),
                        Some(s) => self.under(&mut b, x, z, wx, wz, gy, g, c, &s, seed),
                    }
                }
            }
        }
        crate::trace("sb talus");
        b
    }
    /// The chunks it changes, nearest its foot first.
    pub fn chunks(&self, bx: i32, bz: i32) -> Vec<(i32, i32)> {
        if let Some(l) = self.list.borrow().as_ref() {
            return l.clone();
        }
        let l = self.work_out_chunks(bx, bz);
        *self.list.borrow_mut() = Some(l.clone());
        l
    }
    fn work_out_chunks(&self, bx: i32, bz: i32) -> Vec<(i32, i32)> {
        let mut set: crate::ground::FxMap<(i32, i32), ()> = Default::default();
        let mut add = |x: f64, z: f64| {
            set.insert((((x).floor() as i32 + bx) >> 4, ((z).floor() as i32 + bz) >> 4), ());
        };
        // (the pane: its own frame on a grid, both faces)
        let (mut lx0, mut lz0, mut lx1, mut lz1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for v in &self.poly {
            (lx0, lz0, lx1, lz1) = (lx0.min(v[0]), lz0.min(v[1]), lx1.max(v[0]), lz1.max(v[1]));
        }
        let mut lx = lx0;
        while lx <= lx1 + 4.0 {
            let mut lz = lz0;
            while lz <= lz1 + 4.0 {
                if self.inset(lx.min(lx1), lz.min(lz1)) > -4.0 {
                    for d in [-0.5 * self.th, 0.5 * self.th] {
                        let w = self.pose.world([lx.min(lx1), d, lz.min(lz1)]);
                        add(w[0], w[2]);
                    }
                }
                lz += 4.0;
            }
            lx += 4.0;
        }
        // (the ground round its foot)
        let (dx, dz) = self.lay;
        let (ax, az) = (-dz, dx);
        let w = 0.5 * self.wide() + 46.0;
        let mut u = -self.u_top - 64.0 - 0.3 * self.size();
        while u < self.u_top + 74.0 {
            let mut v = -w;
            while v <= w {
                if u * u + v * v < (SB_PATCH - 12.0) * (SB_PATCH - 12.0) {
                    add(self.foot[0] + dx * u + ax * v, self.foot[2] + dz * u + az * v);
                }
                v += 8.0;
            }
            u += 8.0;
        }
        let r = SB_CLEAR + 0.5 * self.size() + SB_FELL + 4.0;
        let mut dz = -r;
        while dz <= r + 8.0 {
            let mut dx = -r;
            while dx <= r + 8.0 {
                let (ex, ez) = (dx.clamp(-r, r), dz.clamp(-r, r));
                let lim = (r + 6.0).min(SB_PATCH - 10.0);
                if ex * ex + ez * ez <= lim * lim {
                    add(self.foot[0] + ex, self.foot[2] + ez);
                }
                dx += 8.0;
            }
            dz += 8.0;
        }
        let (fx, fz) = (self.foot[0], self.foot[2]);
        for c in self.cracks.iter().filter(|c| (c[2] - fx).powi(2) + (c[3] - fz).powi(2) < (SB_PATCH - 12.0) * (SB_PATCH - 12.0)) {
            add(c[0], c[1]);
            add(c[2], c[3]);
        }
        // (and all the earth it shoved up reaches: a chunk left out would cut its heap off in a straight wall)
        let f = &self.fall;
        for k in 0..f.m {
            for i in 0..f.n {
                let (x, z) = (f.o.0 + (i * SB_TS) as f64, f.o.1 + (k * SB_TS) as f64);
                let (ox, oz) = (x - self.foot[0], z - self.foot[2]);
                let y = self.foot[1] + self.slope.0 * ox + self.slope.1 * oz;
                if f64::from(f.t[k * f.n + i]) > y - 12.0 && ox * ox + oz * oz < (SB_PATCH - 6.0) * (SB_PATCH - 6.0) {
                    add(x, z);
                }
            }
        }
        let mut out: Vec<(i32, i32)> = set.keys().map(|&(a, b)| (a * 16, b * 16)).collect();
        let (fx, fz) = (self.foot[0] + f64::from(bx), self.foot[2] + f64::from(bz));
        let key = |c: &(i32, i32)| ((f64::from(c.0) + 8.0 - fx).powi(2) + (f64::from(c.1) + 8.0 - fz).powi(2)) as i64;
        out.sort_by_key(key);
        crate::meter::spend(300 * (out.len() as u64 + 400));
        out
    }
    /// Whether any of the pane itself is in the chunk with corner (x0, z0).
    fn in_chunk(&self, x0: i32, z0: i32, bx: i32, bz: i32) -> bool {
        crate::meter::spend(30_000);
        (0..25).any(|k| self.span(f64::from(x0 - bx) + 1.5 + 3.25 * f64::from(k % 5), f64::from(z0 - bz) + 1.5 + 3.25 * f64::from(k / 5)).is_some())
    }
    /// Whether the player is in or right by it as it comes down.
    fn near_player(&self, p: [f64; 3]) -> bool {
        for (a, b) in [(0.0, 0.0), (6.0, 0.0), (-6.0, 0.0), (0.0, 6.0), (0.0, -6.0)] {
            if let Some(s) = self.span(p[0] + a, p[2] + b)
                && s.y1 > p[1] - 8.0
                && s.y0 < p[1] + 8.0
            {
                return true;
            }
        }
        (p[0] - self.foot[0]).hypot(p[2] - self.foot[2]) < 0.5 * self.size() + 8.0
    }
    /// The columns asked about it: across the way it comes down, where it meets the ground, and a column of each chunk.
    fn asked_cols(&self, bx: i32, bz: i32) -> Vec<(i32, i32)> {
        let (dx, dz) = self.lay;
        let (ax, az) = (-dz, dx);
        let w = 0.5 * self.wide() + 8.0;
        let ut = 0.5 * self.size() + 8.0;
        let mut out = Vec::new();
        let mut u = -ut;
        while u <= ut {
            let mut v = -w;
            while v <= w {
                out.push(((self.foot[0] + dx * u + ax * v).floor() as i32 + bx, (self.foot[2] + dz * u + az * v).floor() as i32 + bz));
                v += 7.0;
            }
            u += 7.0;
        }
        out.extend(self.chunks(bx, bz).iter().map(|c| (c.0 + 8, c.1 + 8)));
        crate::meter::spend(100 * out.len() as u64);
        out
    }
    /// The ground it comes down on, from the query, and how much of what was asked answered.
    fn ground_of(&self, bx: i32, bz: i32, gy: i32) -> (Option<(f64, (f64, f64))>, f64) {
        let cols = self.asked_cols(bx, bz);
        let (mut got, mut under) = (0.0f64, 0.0f64);
        let mut pts = Vec::with_capacity(cols.len());
        // (only those under it count for its bed, and for whether its land is in)
        let (dx, dz) = self.lay;
        for &(x, z) in &cols {
            let (ox, oz) = (f64::from(x - bx) - self.foot[0], f64::from(z - bz) - self.foot[2]);
            let (u, v) = (ox * dx + oz * dz, oz * dx - ox * dz);
            if u.abs() >= 0.5 * self.size() + 8.0 || v.abs() >= 0.5 * self.wide() + 8.0 {
                continue;
            }
            under += 1.0;
            let Some(g) = crate::ground::at(x, z) else { continue };
            got += 1.0;
            pts.push((x, z, f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)));
        }
        crate::meter::spend(160 * cols.len() as u64);
        (self.bed(&pts, bx, bz), got / under.max(1.0))
    }
    /// What the tests and the preview do at once: its ground at (x, z) from `h`, its pose settled, its litter made.
    #[cfg(test)]
    pub fn settle_test(&mut self, h: &dyn Fn(i32, i32) -> f64, bx: i32, bz: i32, seed: u32) {
        let pts: Vec<(i32, i32, f64)> = self
            .asked_cols(bx, bz)
            .iter()
            .filter(|&&(x, z)| {
                let (ox, oz) = (f64::from(x - bx) - self.foot[0], f64::from(z - bz) - self.foot[2]);
                let (u, v) = (ox * self.lay.0 + oz * self.lay.1, oz * self.lay.0 - ox * self.lay.1);
                u.abs() < 0.5 * self.size() + 8.0 && v.abs() < 0.5 * self.wide() + 8.0
            })
            .map(|&(x, z)| (x, z, h(x, z)))
            .collect();
        let (gs, slope) = self.bed(&pts, bx, bz).unwrap();
        self.set_pose(gs, slope);
        self.litter(seed);
        let _ = self.chunks(bx, bz);
    }
}
/// What of its rubble, broken pieces and cracks reach a chunk.
struct Near {
    rocks: Vec<usize>,
    spalls: Vec<usize>,
    cracks: Vec<usize>,
}
/// The vertical line (x, z) through a box.
fn box_span(s: &Spall, wx: f64, wz: f64) -> Option<(f64, f64)> {
    let (mut y0, mut y1) = (-1.0e9f64, 1.0e9f64);
    for i in 0..3 {
        let e = s.e[i];
        let base = (wx - s.c[0]) * e[0] + (wz - s.c[2]) * e[2] - s.c[1] * e[1];
        let h = s.half[i];
        if e[1].abs() < 1e-6 {
            if base.abs() > h {
                return None;
            }
            continue;
        }
        let (a, b) = ((-h - base) / e[1], (h - base) / e[1]);
        y0 = y0.max(a.min(b));
        y1 = y1.min(a.max(b));
    }
    (y1 > y0).then_some((y0, y1))
}
pub(super) fn heap_block(n: f64, n2: f64) -> &'static str {
    if n2 > 0.74 {
        "minecraft:gravel"
    } else if n < 0.3 {
        "minecraft:rooted_dirt"
    } else if n2 < 0.28 {
        "minecraft:cobblestone"
    } else {
        "minecraft:coarse_dirt"
    }
}
fn boulder_block(m: u8, n: f64) -> &'static str {
    match m {
        0 => "minecraft:stone",
        1 => "minecraft:tuff",
        2 => if n < 0.5 { "minecraft:coarse_dirt" } else { "minecraft:dirt" },
        3 => "minecraft:cobblestone",
        _ => "minecraft:andesite",
    }
}
/// Smooth noise from 0 to 1, cheap (one hash a corner): thousands of these a chunk.
pub(super) fn qnoise(x: f64, z: f64, scale: f64, seed: u32) -> f64 {
    crate::meter::spend(110);
    sb_vn(x / scale, z / scale, seed)
}

// ---- the land as read ------------------------------------------------------------------------------------------------
/// A column as read: its ground's Y, the highest block over it, whether water stands on it, its trunk.
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct Col {
    pub g: i32,
    pub top: i32,
    pub fluid: bool,
    /// The trunk standing on it (logs), and its wood (nuke.rs's WOODS).
    pub trunk: u8,
    pub wood: u8,
}
/// Column i of an answer: its ground and what stands on it (none: not loaded, or nothing to go by).
pub(super) fn column_of(a: &crate::columns::Answer, i: usize, kinds: &[(Kind, u8)]) -> Option<Col> {
    let (surface, blocks) = a.column(i)?;
    let base = surface - a.below;
    crate::meter::spend(200 + 12 * blocks.len() as u64);
    let mut c = Col::default();
    let mut top = None;
    for j in (0..blocks.len()).rev() {
        let (k, _) = kinds.get(blocks[j] as usize).copied().unwrap_or((Kind::Loose, 0));
        match k {
            Kind::Air => {}
            Kind::Ground => {
                top.get_or_insert(base + j as i32);
                c.g = base + j as i32;
                c.top = top.unwrap_or(c.g);
                // (the trunk on it: logs straight up from its ground)
                let mut k = j + 1;
                while k < blocks.len() {
                    match kinds.get(blocks[k] as usize) {
                        Some(&(Kind::Log, w)) => {
                            if c.trunk == 0 {
                                c.wood = w;
                            }
                            c.trunk = c.trunk.saturating_add(1);
                        }
                        _ => break,
                    }
                    k += 1;
                }
                return Some(c);
            }
            Kind::Fluid => {
                c.fluid = true;
                top.get_or_insert(base + j as i32);
            }
            _ => {
                top.get_or_insert(base + j as i32);
            }
        }
    }
    // (the sea, or a lake deeper than it reads)
    c.fluid.then(|| Col { g: base, top: top.unwrap_or(base), fluid: true, trunk: 0, wood: 0 })
}

// ---- the panes as the strike goes on ---------------------------------------------------------------------------------
#[derive(Clone, Copy, PartialEq, Debug)]
enum Step {
    Idle,
    /// Asked: (the query, when).
    Asked(u32, f32),
    /// Its pose settled.
    Settled,
    Building,
    Done,
    /// No blocks: it stays drawn.
    Failed,
}
/// Chunks of it asked of the world together.
struct Lot {
    shard: usize,
    tag: u32,
    asked: f32,
    chunks: Vec<(i32, i32)>,
    next: usize,
    read: Option<Rc<crate::columns::Answer>>,
    kinds: Vec<(Kind, u8)>,
    answered: bool,
}
/// The panes, shared by the stages that settle and land them.
pub(super) struct Lodge {
    pub shards: Vec<Shard>,
    pub seed: u32,
    terrain: bool,
    me: [f64; 3],
    /// The target's ground point in the world.
    at: [f64; 3],
    stage: Vec<Step>,
    todo: Vec<Vec<(i32, i32)>>,
    next: Vec<usize>,
    made: Vec<u32>,
    sent: Vec<Rc<Cell<u32>>>,
    /// Chunks of each left out (never loaded).
    lost: Vec<u32>,
    lots: std::collections::VecDeque<Lot>,
    pub landed: u32,
}
pub(super) type Shared = Rc<RefCell<Lodge>>;
impl Lodge {
    pub fn new(shards: Vec<Shard>, seed: u32, terrain: bool, me: [f64; 3], at: [f64; 3]) -> Self {
        let n = shards.len();
        Lodge {
            shards,
            seed,
            terrain,
            me,
            at,
            stage: vec![Step::Idle; n],
            todo: vec![Vec::new(); n],
            next: vec![0; n],
            made: vec![0; n],
            sent: (0..n).map(|_| Rc::default()).collect(),
            lost: vec![0; n],
            lots: Default::default(),
            landed: 0,
        }
    }
    /// Whether pane i has no blocks coming.
    pub fn failed(&self, i: usize) -> bool {
        matches!(self.stage.get(i), Some(Step::Failed))
    }
}
/// The stages that settle the panes and bring them in, from as it fires.
pub(super) fn sb_lodge_plan(p: &mut Plan, l: Shared) {
    p.later(0.15, move |q| {
        // (should it be stopped with one half built, it finishes it: never due otherwise)
        let f = l.clone();
        q.ev.push((1.0e9, Act::Cleanup(Box::new(move || sb_finish(f)))));
        sb_tick(q, l, 0.15);
    });
}
/// A stage a tick while there is anything to do.
fn sb_tick(q: &mut Plan, l: Shared, now: f32) {
    let now = now.max(clock());
    let more = {
        let mut g = l.borrow_mut();
        let w = &mut *g;
        let (bx, bz, gy) = (q.bx, q.bz, q.by + 1);
        for i in 0..w.shards.len() {
            if crate::meter::spent() > 2_000_000 {
                break;
            }
            let (tr, hit) = (w.shards[i].tr, w.shards[i].hit);
            match w.stage[i] {
                Step::Idle => {
                    let tag = crate::ground::new_tag();
                    crate::trace("sb asked<");
                    q.ev.push((now, Act::Survey { tag, columns: w.shards[i].asked_cols(bx, bz) }));
                    crate::trace("sb asked>");
                    w.stage[i] = Step::Asked(tag, now);
                }
                Step::Asked(tag, at) => {
                    // (its path down is set before it starts to tear free: never changed in the air. If its land isn't in
                    // by then, it is held back a little (its sounds with it: they go out as it settles), as often as it
                    // can be, and asked again)
                    let late = now + 0.3 > tr - SB_SAG - 1.4;
                    let (gs, share) = if crate::ground::ready(tag) { w.shards[i].ground_of(bx, bz, gy) } else { (None, 0.0) };
                    if share < SB_LOADED {
                        if late && w.shards[i].hit + SB_HOLD <= SB_LATEST {
                            w.shards[i].tr += SB_HOLD;
                            w.shards[i].hit += SB_HOLD;
                            q.ev.push((now, Act::Words { index: (SB_SH + i * SB_SW) as u32, words: w.shards[i].words(0.0) }));
                            w.stage[i] = Step::Idle;
                        } else if late {
                            sb_fail(q, w, i, now, "its land never loaded");
                            let s = &w.shards[i];
                            sb_pane_events(q, i, s.tr, s.hit, s.foot, s.size(), w.me, w.at, w.seed, false);
                        } else if now > at + 1.5 {
                            // (its chunks may still come: asked again a little later)
                            w.stage[i] = Step::Idle;
                        }
                        continue;
                    }
                    let Some((gs, slope)) = gs else {
                        sb_fail(q, w, i, now, "its land never loaded");
                        continue;
                    };
                    let seed = w.seed;
                    let s = &mut w.shards[i];
                    crate::trace("sb settle<");
                    s.set_pose(gs, slope);
                    s.litter(seed);
                    w.todo[i] = s.chunks(bx, bz);
                    crate::trace("sb settle>");
                    q.ev.push((now, Act::Words { index: (SB_SH + i * SB_SW) as u32, words: s.words(0.0) }));
                    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("skybreak: pane {i} comes down at {:.0} {:.0} {:.0} at {hit:.1} s", w.at[0] + s.foot[0], w.at[1] + gs, w.at[2] + s.foot[2]));
                    let (tr, hit, foot, size) = (s.tr, s.hit, s.foot, s.size());
                    sb_pane_events(q, i, tr, hit, foot, size, w.me, w.at, w.seed, w.terrain);
                    w.stage[i] = if w.terrain { Step::Settled } else { Step::Failed };
                }
                // (once it has slammed down and is still: the pass draws it until then)
                Step::Settled if now >= hit + super::skybreak::SB_SETTLE => {
                    let p = crate::sdk::game::get_player().map_or(w.me, |p| [p.x - w.at[0], p.y - w.at[1], p.z - w.at[2]]);
                    if w.shards[i].near_player(p) {
                        sb_fail(q, w, i, now, "the player is there");
                        w.todo[i].clear();
                    } else {
                        w.stage[i] = Step::Building;
                    }
                }
                Step::Building if w.next[i] >= w.todo[i].len() && w.sent[i].get() >= w.made[i] && !w.lots.iter().any(|l| l.shard == i) => {
                    // (all of it in: the pass lets the drawn one go; or some of it never loaded: drawn on over it)
                    let lost = w.lost[i];
                    q.ev.push((now, Act::Data { index: (SB_SH + i * SB_SW + 14) as u32, value: if lost > 0 { -1.0 } else { now.max(1.0) } }));
                    w.stage[i] = Step::Done;
                    w.landed += 1;
                    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("skybreak: pane {i} in the world {:.1} s after it hit, {} chunks{}", now - hit, w.made[i], if lost > 0 { format!(", {lost} never loaded (it stays drawn)") } else { String::new() }));
                }
                _ => {}
            }
        }
        // (the reads: each lot of chunks asked when there's room for what it will make)
        let waiting: u32 = (0..w.shards.len()).map(|i| w.made[i] - w.sent[i].get()).sum();
        let held: usize = w.lots.iter().map(|l| l.chunks.len() - l.next).sum();
        if w.lots.len() < SB_FLIGHT && waiting + (held as u32) < SB_QUEUE {
            for i in 0..w.shards.len() {
                if w.stage[i] == Step::Building && w.next[i] < w.todo[i].len() {
                    let end = (w.next[i] + SB_LOT).min(w.todo[i].len());
                    let chunks: Vec<(i32, i32)> = w.todo[i][w.next[i]..end].to_vec();
                    w.next[i] = end;
                    let columns: Vec<(i32, i32)> = chunks.iter().flat_map(|c| (0..256).map(move |j| (c.0 + (j & 15), c.1 + (j >> 4)))).collect();
                    let tag = crate::columns::new_tag();
                    crate::meter::spend(40 * columns.len() as u64);
                    q.ev.push((now, Act::Read { tag, columns, below: SB_BELOW, above: 1 }));
                    w.lots.push_back(Lot { shard: i, tag, asked: now, chunks, next: 0, read: None, kinds: Vec::new(), answered: false });
                    break;
                }
            }
        }
        // (what's been read made into blocks, as much as a tick should)
        let seed = w.seed;
        while crate::meter::spent() < SB_TICK {
            let Some(lot) = w.lots.front_mut() else { break };
            if !lot.answered {
                if let Some(a) = crate::columns::take(lot.tag) {
                    lot.kinds = a.palette.iter().map(|n| kind(n)).collect();
                    crate::meter::spend(2_000 + 4_000 * a.palette.len() as u64);
                    lot.read = Some(a);
                    lot.answered = true;
                } else if now > lot.asked + 3.5 {
                    // (given up on: its answer, should it come, isn't kept)
                    crate::columns::forget(lot.tag);
                    lot.answered = true;
                } else {
                    break;
                }
            }
            let (x0, z0) = lot.chunks[lot.next];
            let i = lot.shard;
            let read = lot.read.as_ref().map(|a| {
                let base = lot.next * 256;
                crate::meter::spend(4_000);
                (0..256).map(|j| column_of(a, base + j, &lot.kinds)).collect::<Vec<Option<Col>>>()
            });
            // (a chunk the world hasn't loaded yet can't take its blocks: asked again later, as long as there's time)
            let unloaded = lot.read.as_ref().is_none_or(|a| (0..256).filter(|&j| a.bases.get(lot.next * 256 + j).copied().flatten().is_none()).count() > 128);
            lot.next += 1;
            if lot.next >= lot.chunks.len() {
                w.lots.pop_front();
            }
            if unloaded {
                crate::meter::spend(30_000);
                if now < SB_GIVE_UP {
                    w.todo[i].push((x0, z0));
                } else if w.shards[i].in_chunk(x0, z0, bx, bz) {
                    // (only a chunk with some of the pane itself in it keeps the pane drawn: its ground alone doesn't)
                    w.lost[i] += 1;
                }
                continue;
            }
            crate::trace("sb chunk<");
            let mut b = w.shards[i].chunk(x0, z0, bx, bz, gy, seed, read.as_deref());
            crate::trace("sb chunk>");
            b.runs.shrink_to_fit();
            b.cleanup = true;
            b.clear_of_player = true;
            b.sent = Some(w.sent[i].clone());
            w.made[i] += 1;
            q.ev.push((now, Act::Blocks(Box::new(b))));
        }
        w.stage.iter().any(|s| !matches!(s, Step::Done | Step::Failed)) || !w.lots.is_empty()
    };
    if more {
        q.later(now + 0.05, move |q| sb_tick(q, l, now + 0.05));
    }
}
/// No blocks for pane i: it stays drawn.
fn sb_fail(q: &mut Plan, w: &mut Lodge, i: usize, now: f32, why: &str) {
    w.stage[i] = Step::Failed;
    if w.terrain {
        q.ev.push((now, Act::Data { index: (SB_SH + i * SB_SW + 14) as u32, value: -1.0 }));
    }
    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("skybreak: pane {i} stays drawn: {why}"));
}
/// The strike stopped with a pane half built: the rest of it goes in, a few chunks a stage, on what's known without a
/// read.
fn sb_finish(l: Shared) -> Vec<(f32, Act)> {
    let mut out = Vec::new();
    let more = {
        let mut g = l.borrow_mut();
        let w = &mut *g;
        w.lots.clear();
        let (bx, bz, gy) = ((w.at[0] - 0.5).round() as i32, (w.at[2] - 0.5).round() as i32, w.at[1] as i32);
        for _ in 0..3 {
            let Some(i) = (0..w.shards.len()).find(|&i| w.stage[i] == Step::Building && w.next[i] < w.todo[i].len()) else { return out };
            let (x0, z0) = w.todo[i][w.next[i]];
            w.next[i] += 1;
            let mut b = w.shards[i].chunk(x0, z0, bx, bz, gy, w.seed, None);
            b.cleanup = true;
            b.clear_of_player = true;
            out.push((0.0, Act::Blocks(Box::new(b))));
        }
        true
    };
    if more {
        out.push((0.0, Act::Cleanup(Box::new(move || sb_finish(l)))));
    }
    out
}

/// A wood for the tests and the preview: a tree (its trunk 6 high) at the middle of each 9-block cell the hash picks, its
/// crown round it (5 across, from 4 to 7 over the ground).
#[cfg(test)]
pub(super) fn wood_at(x: i32, z: i32) -> (bool, bool) {
    let (cx, cz) = (x.div_euclid(9), z.div_euclid(9));
    let tree = sb_hash(cx, cz, 77) < 0.55;
    let (tx, tz) = (cx * 9 + 4, cz * 9 + 4);
    (tree && x == tx && z == tz, tree && (x - tx).abs() <= 2 && (z - tz).abs() <= 2)
}

/// The land a pane leaves (its own blocks and its ground's) as the preview's voxels: `x y z r g b` a line, on the preview's
/// flat land (its ground's top at `gy` - 1, grass on dirt), each column played through the edits and its top dozen
/// blocks written in their average colours (with the preview's `vox=2` the land is dug under them).
#[cfg(test)]
pub(super) fn voxels(s: &Shard, gy: i32, seed: u32) -> String {
    use std::collections::HashMap;
    let mut cols: HashMap<(i32, i32), Vec<&'static str>> = HashMap::new();
    let base = gy - 40;
    let fresh = |x: i32, z: i32| -> Vec<&'static str> {
        let (trunk, crown) = wood_at(x, z);
        (base..gy + 8)
            .map(|y| match y {
                _ if y == gy - 1 => "minecraft:grass_block",
                _ if y < gy - 1 => "minecraft:dirt",
                _ if trunk && y < gy + 6 => "minecraft:oak_log",
                _ if crown && y >= gy + 4 && y < gy + 8 => "minecraft:oak_leaves",
                _ => "minecraft:air",
            })
            .collect()
    };
    let names: Vec<&'static str> = SKY.iter().chain([CORE, RIM, BACK, BACK_FLECK].iter()).chain(
        ["minecraft:dirt", "minecraft:coarse_dirt", "minecraft:rooted_dirt", "minecraft:gravel", "minecraft:cobblestone", "minecraft:stone", "minecraft:tuff", "minecraft:andesite", "minecraft:air", "minecraft:grass_block"].iter(),
    ).copied().chain(LOG_X.iter().chain(LOG_Z.iter()).chain(LEAVES.iter()).copied()).chain(["minecraft:oak_log", "minecraft:oak_leaves"]).collect();
    for (x0, z0) in s.chunks(0, 0) {
        let read: Vec<Option<Col>> = (0..256)
            .map(|j| {
                let (trunk, crown) = wood_at(x0 + (j & 15), z0 + (j >> 4));
                Some(Col { g: gy - 1, top: if crown { gy + 7 } else { gy - 1 }, fluid: false, trunk: if trunk { 6 } else { 0 }, wood: 0 })
            })
            .collect();
        let b = s.chunk(x0, z0, 0, 0, gy, seed, Some(&read));
        let e = b.edit();
        for r in &e.runs {
            let name = names.iter().find(|n| **n == e.palette[r.block as usize].as_str()).copied().unwrap_or("minecraft:stone");
            let c = cols.entry((r.x, r.z)).or_insert_with(|| fresh(r.x, r.z));
            let (y0, y1) = if r.surface.is_some() {
                let top = c.iter().rposition(|n| !n.ends_with(":air")).map_or(base, |i| base + i as i32) + 1;
                (top + r.y, top + r.y + r.height as i32 - 1)
            } else {
                (r.y, r.y + r.height as i32 - 1)
            };
            for y in y0..=y1 {
                let i = y - base;
                if i < 0 {
                    continue;
                }
                let i = i as usize;
                if c.len() <= i {
                    c.resize(i + 1, "minecraft:air");
                }
                c[i] = name;
            }
        }
    }
    let mut out = String::new();
    for ((x, z), c) in cols {
        let Some(top) = c.iter().rposition(|n| !n.ends_with(":air")) else { continue };
        for (i, n) in c.iter().enumerate().skip(top.saturating_sub(12)) {
            if n.ends_with(":air") {
                continue;
            }
            let rgb = if *n == "minecraft:grass_block" {
                [96, 150, 70]
            } else if n.contains("leaves") {
                [58, 110, 40]
            } else if n.contains("_log") {
                [104, 82, 50]
            } else {
                super::hurricane::hu_block(n).map_or([128, 128, 128], |b| super::hu_blocks::HU_BLOCKS[b as usize].top)
            };
            out.push_str(&format!("{x} {} {z} {:.3} {:.3} {:.3}\n", base + i as i32, f64::from(rgb[0]) / 255.0, f64::from(rgb[1]) / 255.0, f64::from(rgb[2]) / 255.0));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::super::skybreak::{Mesh, sb_shards};
    use super::*;
    use std::collections::HashSet;

    const ME: [f64; 3] = [0.0, 5.0, 300.0];
    fn panes(hills: f64, seed: u32) -> Vec<Shard> {
        let mesh = Mesh::new(seed, ME);
        let mut shards = sb_shards(&mesh, seed, ME);
        for s in &mut shards {
            s.settle_test(&|x, z| hills * ((f64::from(x) + 0.5) * 0.013).sin() * ((f64::from(z) + 0.5) * 0.017).cos(), 0, 0, seed);
        }
        shards
    }
    fn blocks_of(s: &Shard, seed: u32) -> HashSet<(i32, i32, i32)> {
        let mut set = HashSet::new();
        for (x0, z0) in s.chunks(0, 0) {
            let b = s.chunk(x0, z0, 0, 0, 65, seed, None);
            let e = b.edit();
            for r in &e.runs {
                let n = &e.palette[r.block as usize];
                if r.surface.is_none() && [SKY[0], SKY[1], SKY[2], CORE, RIM, BACK, BACK_FLECK].contains(&n.as_str()) {
                    for y in r.y..r.y + r.height as i32 {
                        set.insert((r.x, y, r.z));
                    }
                }
            }
        }
        set
    }
    /// The pass's test of a block being in the pane (skybreak.wgsl's sb_in): its centre inside the prism of its pose.
    fn drawn_in(s: &Shard, p: [f64; 3]) -> bool {
        let w = s.words(0.0);
        let f = |j: usize| f64::from(f32::from_bits(w[j]));
        let q = [f(16), f(17), f(18), f(19)];
        let c = [f(20), f(21), f(22)];
        let d = [p[0] - c[0], p[1] - c[1], p[2] - c[2]];
        // (the inverse turn: the conjugate)
        let u = [-q[0], -q[1], -q[2]];
        let t = cross(u, d);
        let t = [t[0] + q[3] * d[0], t[1] + q[3] * d[1], t[2] + q[3] * d[2]];
        let t2 = cross(u, t);
        let l = [d[0] + 2.0 * t2[0], d[1] + 2.0 * t2[1], d[2] + 2.0 * t2[2]];
        let th = f(9);
        if l[1].abs() > 0.5 * th {
            return false;
        }
        let n = f(8) as usize;
        (0..n).all(|k| {
            let (a, b) = ([f(2 * k), f(2 * k + 1)], [f(2 * ((k + 1) % n)), f(2 * ((k + 1) % n) + 1)]);
            (b[0] - a[0]) * (l[2] - a[1]) - (b[1] - a[1]) * (l[0] - a[0]) >= 0.0
        })
    }
    /// The blocks are where the pass draws the pane as it lies: every block's centre inside what it draws, and every
    /// block of the world whose centre is inside it (and over the ground's heap) is there. (The target's ground at Y 65.)
    #[test]
    fn a_lodged_pane_is_where_the_pass_draws_it() {
        for (hills, seed) in [(0.0, 37), (25.0, 5)] {
            for s in &panes(hills, seed) {
                let set = blocks_of(s, seed);
                assert!(set.len() > 8_000, "pane {}: {} blocks", s.i, set.len());
                let out = set.iter().filter(|&&(x, y, z)| !drawn_in(s, [f64::from(x), f64::from(y) + 0.5 - 65.0, f64::from(z)])).count();
                assert!(out == 0, "pane {}: {out} blocks outside what the pass draws", s.i);
                let (mut holes, mut inner) = (0, 0);
                let c = s.foot;
                for x in (c[0] as i32 - 90..c[0] as i32 + 90).step_by(3) {
                    for z in (c[2] as i32 - 90..c[2] as i32 + 90).step_by(3) {
                        for y in (-30..60).step_by(2) {
                            if drawn_in(s, [f64::from(x), f64::from(y) + 0.5, f64::from(z)]) {
                                // (under the ground's own top where its heap is, the ground's work may lay earth instead:
                                // only what stands over the ground counts)
                                if f64::from(y) + 0.5 > c[1] + 2.0 {
                                    inner += 1;
                                    holes += usize::from(!set.contains(&(x, y + 65, z)));
                                }
                            }
                        }
                    }
                }
                assert!(inner > 100, "pane {}: {inner}", s.i);
                assert!((holes as f64) < 0.02 * inner as f64, "pane {}: {holes} holes of {inner}", s.i);
            }
        }
    }
    /// Lying low with its low end in the ground, its sky up; clear of the player and of each other.
    #[test]
    fn they_lie_low_and_keep_off_the_player() {
        for seed in [37, 5, 1234, 77] {
            let ps = panes(0.0, seed);
            assert!(ps.len() >= 4, "seed {seed}: only {} panes", ps.len());
            for s in &ps {
                // (its sky's normal: its own -y, turned into the world)
                let sky_n = [-s.pose.r[0][1], -s.pose.r[1][1], -s.pose.r[2][1]];
                let tilt = sky_n[1].clamp(-1.0, 1.0).acos().to_degrees();
                assert!((SB_LOW - 0.5..SB_STEEP + 13.0).contains(&tilt), "seed {seed} pane {}: {tilt} degrees", s.i);
                let set = blocks_of(s, seed);
                let ys: Vec<i32> = set.iter().map(|b| b.1).collect();
                let (lo, hi) = (*ys.iter().min().unwrap(), *ys.iter().max().unwrap());
                assert!((8..45).contains(&(hi - 65)), "seed {seed} pane {}: it stands {} high", s.i, hi - 65);
                assert!(lo < 65 - 4, "seed {seed} pane {}: {lo} to {hi}", s.i);
                let under = set.iter().filter(|b| b.1 < 65).count() as f64 / set.len() as f64;
                assert!((0.1..0.6).contains(&under), "seed {seed} pane {}: {under} of it under the ground", s.i);
                for b in set.iter().step_by(17) {
                    let d = (f64::from(b.0) - ME[0]).hypot(f64::from(b.2) - ME[2]);
                    assert!(d > 60.0, "seed {seed} pane {}: a block {d} from the player", s.i);
                }
                for t in &ps {
                    if t.i != s.i {
                        assert!((s.site[0] - t.site[0]).hypot(s.site[1] - t.site[1]) >= SB_APART_TEST, "seed {seed}: panes {} and {}", s.i, t.i);
                    }
                }
            }
        }
    }
    const SB_APART_TEST: f64 = 117.0;
    /// In a wood: past the cleared ground the trees lie felled, pointing away from where the pane struck, no trunk left
    /// standing in the band; past the band they stand as they were.
    #[test]
    fn the_trees_round_it_are_felled() {
        let s = &panes(0.0, 37)[0];
        let (mut laid, mut standing) = (0, 0);
        for (x0, z0) in s.chunks(0, 0) {
            let read: Vec<Option<Col>> = (0..256)
                .map(|j| {
                    let (trunk, crown) = wood_at(x0 + (j & 15), z0 + (j >> 4));
                    Some(Col { g: 64, top: if crown { 72 } else { 64 }, fluid: false, trunk: if trunk { 6 } else { 0 }, wood: 2 })
                })
                .collect();
            let b = s.chunk(x0, z0, 0, 0, 65, 37, Some(&read));
            let e = b.edit();
            for r in &e.runs {
                let n = e.palette[r.block as usize].as_str();
                if n.contains("birch_log[axis=") {
                    laid += 1;
                    let (ox, oz) = (f64::from(r.x) - s.foot[0], f64::from(r.z) - s.foot[2]);
                    let d = ox.hypot(oz);
                    assert!(d > SB_CLEAR + 0.5 * s.size() - 2.0 && d < SB_CLEAR + 0.5 * s.size() + SB_FELL + 12.0, "a log {d} out");
                    assert!(r.y == 65 || r.y > 65, "a log at {}", r.y);
                }
            }
            // (every trunk in the band cleared: an air run over its column from its ground)
            for j in 0..256 {
                let (x, z) = (x0 + (j & 15), z0 + (j >> 4));
                if wood_at(x, z).0 && s.felled(f64::from(x), f64::from(z)) {
                    let cleared = e.runs.iter().any(|r| r.x == x && r.z == z && e.palette[r.block as usize].ends_with(":air") && r.y <= 66);
                    standing += usize::from(!cleared);
                }
            }
        }
        assert!(laid > 20, "only {laid} logs laid down");
        assert_eq!(standing, 0, "{standing} trunks left standing in the band");
    }
    /// A felled tree is never cut off where a chunk ends: its trunk runs on into the next chunk (laid with that chunk's
    /// edit) or lies the other way or shorter, and every crown keeps the leaf past its tip.
    #[test]
    fn felled_trees_are_whole_across_chunk_edges() {
        use std::collections::HashMap;
        for (k, seed) in [(0usize, 37u32), (2, 37), (1, 5)] {
            let s = &panes(0.0, seed)[k];
            let mut world: HashMap<(i32, i32, i32), String> = HashMap::new();
            for (x0, z0) in s.chunks(0, 0) {
                let read: Vec<Option<Col>> = (0..256)
                    .map(|j| {
                        let (trunk, crown) = wood_at(x0 + (j & 15), z0 + (j >> 4));
                        Some(Col { g: 64, top: if crown { 72 } else { 64 }, fluid: false, trunk: if trunk { 6 } else { 0 }, wood: 2 })
                    })
                    .collect();
                let e = s.chunk(x0, z0, 0, 0, 65, seed, Some(&read)).edit();
                for r in e.runs.iter().filter(|r| r.surface.is_none()) {
                    for y in r.y.max(64)..(r.y + r.height as i32).min(70) {
                        world.insert((r.x, y, r.z), e.palette[r.block as usize].clone());
                    }
                }
            }
            let is = |p: (i32, i32, i32), w: &str| world.get(&p).is_some_and(|n| n.contains(w));
            let (mut crowns, mut cut, mut edge) = (0, 0, 0);
            for (&(x, y, z), n) in &world {
                if y != 66 || !n.contains("birch_leaves") || !is((x, 65, z), "birch_log") {
                    continue;
                }
                // (the crown's middle over the trunk's tip: the trunk runs back from it, the leaf past it beyond)
                let axis_x = is((x, 65, z), "axis=x");
                let back = if axis_x { [(-1, 0), (1, 0)] } else { [(0, -1), (0, 1)] };
                let Some(&(bx, bz)) = back.iter().find(|d| is((x + d.0, 65, z + d.1), "birch_log")) else { continue };
                crowns += 1;
                if !is((x - bx, 65, z - bz), "birch_leaves") {
                    cut += 1;
                }
                edge += usize::from(if axis_x { (x - bx).div_euclid(16) != x.div_euclid(16) } else { (z - bz).div_euclid(16) != z.div_euclid(16) });
            }
            eprintln!("seed {seed} pane {k}: {crowns} felled crowns, {edge} with their tip's leaf over a chunk's edge, {cut} cut");
            assert!(crowns > 10, "seed {seed} pane {k}: only {crowns} felled trees");
            assert_eq!(cut, 0, "seed {seed} pane {k}: {cut} of {crowns} felled trees cut off at a chunk's edge");
        }
    }
    /// No stage of a pane's work outweighs a tick: a chunk's edits counted well under the stage's share (the fork's
    /// `mod_soak` traced a chunk at about 1.8M of the game's fuel, the meter at 2.3M: it reads high, as it should).
    #[test]
    fn a_chunk_of_a_pane_is_cheap() {
        for s in &panes(20.0, 37) {
            for (x0, z0) in s.chunks(0, 0).iter().take(40) {
                let read: Vec<Option<Col>> = (0..256).map(|_| Some(Col { g: 64, top: 70, fluid: false, trunk: 0, wood: 0 })).collect();
                crate::meter::reset();
                let _ = s.chunk(*x0, *z0, 0, 0, 65, 37, Some(&read));
                let spent = crate::meter::spent();
                assert!(spent < 4_000_000, "pane {} chunk {x0} {z0}: {spent}", s.i);
            }
        }
    }
}
#[cfg(test)]
mod profile {
    use super::*;
    /// `cargo test --release sb_profile -- --ignored --nocapture`: what a chunk's columns cost, part by part.
    #[test]
    #[ignore]
    fn sb_profile() {
        let mesh = super::super::skybreak::Mesh::new(37, [0.0, 5.0, 300.0]);
        let mut shards = super::super::skybreak::sb_shards(&mesh, 37, [0.0, 5.0, 300.0]);
        for s in &mut shards {
            s.settle_test(&|_, _| 0.0, 0, 0, 37);
        }
        let read: Vec<Option<Col>> = (0..256).map(|_| Some(Col { g: 64, top: 70, fluid: false, trunk: 0, wood: 0 })).collect();
        let s = &shards[0];
        let chunks = s.chunks(0, 0);
        let t = std::time::Instant::now();
        let mut n = 0;
        for (x0, z0) in &chunks {
            let _ = s.chunk(*x0, *z0, 0, 0, 65, 37, Some(&read));
            n += 1;
        }
        let whole = t.elapsed().as_secs_f64() / n as f64;
        let (mut tg, mut tp, mut tt) = (0.0, 0.0, 0.0);
        let near = Near { rocks: (0..s.rocks.len()).collect(), spalls: (0..s.spalls.len()).collect(), cracks: (0..s.cracks.len()).collect() };
        let mut b = Blocks::default();
        for (x0, z0) in &chunks {
            for z in *z0..z0 + 16 {
                for x in *x0..x0 + 16 {
                    let (wx, wz) = (f64::from(x), f64::from(z));
                    let c = Col { g: 64, top: 70, fluid: false, trunk: 0, wood: 0 };
                    let t0 = std::time::Instant::now();
                    let g = s.ground_col(&mut b, x, z, wx, wz, 65, Some(&c), 37, &near);
                    let t1 = std::time::Instant::now();
                    let sp = s.pane_col(&mut b, x, z, wx, wz, 65, g.map(|g| g - 1), 37);
                    let t2 = std::time::Instant::now();
                    if let Some(g) = g {
                        match sp {
                            None => s.talus(&mut b, x, z, wx, wz, 65, g, &c, 37),
                            Some(sp) => s.under(&mut b, x, z, wx, wz, 65, g, &c, &sp, 37),
                        }
                    }
                    let t3 = std::time::Instant::now();
                    tg += (t1 - t0).as_secs_f64();
                    tp += (t2 - t1).as_secs_f64();
                    tt += (t3 - t2).as_secs_f64();
                }
            }
            b = Blocks::default();
        }
        let k = 1e6 / n as f64;
        eprintln!("{n} chunks: a chunk {:.0} us; per chunk ground {:.0} us (all rocks near), pane {:.0} us, talus/under {:.0} us; {} rocks {} spalls {} cracks",
            whole * 1e6, tg * k, tp * k, tt * k, s.rocks.len(), s.spalls.len(), s.cracks.len());
    }
}
