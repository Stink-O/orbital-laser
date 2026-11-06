//! The ten biggest plates the Supervolcano's mount throws, come down as real land. The pass flies them as it does all 95
//! (shaders/volcano_mount.wgsl's vm_plates), but these are aimed (`Site`), eased into a pose (`Pose`, lying low on the land, its
//! low end in the ground and what it lifts packed under with crushed earth) and stay there as real blocks: their own land's surface, soil and rock, torn
//! and burnt on the underside, with a lip of ground heaped in front of them, cracks of tuff round them and rubble at the
//! foot. The drawn plate stays where it came down until every chunk of it is in the world, and then goes: the real one is
//! in the same place (`a_lodged_plate_is_where_the_pass_draws_it`).
//!
//! Everything but what the plan knows as it fires is worked out on the way: the sites when it fires (the chunks they need
//! are force-loaded from then, so a strike left half way lets them go); the plates at the end of the mount's tables
//! (`Slab::new`); the ground under each from 19.5 s (a small `world.surface-height` query, the coarse survey misses local
//! heights), which settles its pose before its last seconds (`settle`); its blocks from when it hits, a chunk at a time
//! with what a read says stands there (`vl_tick`), so none of it is held for long. A plate on land that never loaded, or
//! one that would come down on the player, stays drawn and goes into the ground as the others do.
use super::vc_land::{Col, VC_BELOW, column_of, qnoise};
use super::*;
use std::cell::{Cell, RefCell};
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
pub(super) const VL_N: usize = 10;
/// How many are aimed at the player's side.
const VL_NEAR: usize = 5;
/// Where the pass reads them: a word a thrown plate (its place in the list and one, 0 if it isn't one of these), then
/// VL_W words each. Keep in step with volcano_mount.wgsl's VL_*.
pub(super) const VL_MAP: usize = super::vc_mount::VM_BASE + 7000;
pub(super) const VL_BASE: usize = super::vc_mount::VM_BASE + 7100;
pub(super) const VL_W: usize = 16;
/// Seconds before it hits that the tumble and the way begin to ease into where it comes to rest.
const VL_EASE: f64 = 3.5;
/// How far it slides along the way it comes down in those seconds, faster and faster.
const VL_SLIDE: f64 = 110.0;
/// How much of its length goes into the ground.
const VL_BURY: f64 = 0.42;
/// How steeply it lies, degrees, from and to: a slab thrown down on the land, never a wing held up in the air.
const VL_LOW: f64 = 7.0;
const VL_STEEP: f64 = 20.0;
/// The steepest bank of ground it follows.
const VL_BANK: f64 = 16.0;
/// How the earth it shoved up falls away from it: blocks down a block out, its edge's samples this far apart, how many.
const VL_FALL: f64 = 1.25;
const VL_TS: usize = 8;
const VL_TALL: f64 = 44.0;
/// A plate's thickness at the least.
const VL_THICK: f64 = 30.0;
/// How far round a site its chunks are force-loaded.
pub(super) const VL_PATCH: f64 = 160.0;
/// How far from the vent the sites lie: past the deposit and the felled trees, or the land's work buries them.
const VL_R0: f64 = 570.0;
const VL_R1: f64 = 860.0;
/// How near a player a site's middle may lie (its plate reaches some 120 from it), and how far from them the near ones.
const VL_ME0: f64 = 310.0;
const VL_ME1: f64 = 460.0;
const VL_G: f64 = 34.0;
const VL_BRK: f64 = 18.7;
const VL_TH: f64 = 2.5;
/// A stage's work on the blocks, counted, and how many chunks a read asks at a time, in flight at a time, and may wait
/// to go in at a time.
const VL_TICK: u64 = 9_500_000;
const VL_LOT: usize = 12;
const VL_FLIGHT: usize = 3;
const VL_QUEUE: u32 = 48;
const VL_ASK: f32 = 19.5;
/// What share of a plate's ground must have answered for it to come down as blocks.
const VL_LOADED: f64 = 0.96;

/// Where one comes down and the way it travels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct Site {
    pub x: f64,
    pub z: f64,
    pub dir: (f64, f64),
    pub near: bool,
}
/// The ten sites for a player at `me` from the vent: five on their side, within sight of them (render distance is 512
/// blocks, and past that the land's changes don't show until they fly closer), the others round the mount.
pub(super) fn vl_sites(seed: u32, me: [f64; 3]) -> Vec<Site> {
    let phi = me[2].atan2(me[0]);
    let dist = me[0].hypot(me[2]).max(1.0);
    let mut out: Vec<Site> = Vec::with_capacity(VL_N);
    for i in 0..VL_NEAR {
        let k = i as u32;
        let mut best = (f64::MAX, 0.0, 0.0);
        for n in 0..160u32 {
            let m = |q: u32| mh(k * 100 + n, seed, q);
            let rho = VL_ME0 + (VL_ME1 - VL_ME0) * m(0xd0);
            let psi = 1.15 * (2.0 * m(0xd1) - 1.0);
            let (x, z) = (me[0] - rho * (phi + psi).cos(), me[2] - rho * (phi + psi).sin());
            let (x, z) = if rho.max(dist - VL_R1) > VL_ME1 {
                // (a player far off: as near them as the sites go)
                let a = phi + 0.4 * (2.0 * m(0xd1) - 1.0);
                ((VL_R1 - 30.0 * m(0xd0)) * a.cos(), (VL_R1 - 30.0 * m(0xd0)) * a.sin())
            } else {
                (x, z)
            };
            let r = x.hypot(z);
            let sep = out.iter().map(|s| (s.x - x).hypot(s.z - z)).fold(1.0e9, f64::min);
            let over = 8.0 * (VL_R0 - r).max(r - VL_R1).max(0.0) + 3.0 * (175.0 - sep).max(0.0) + (VL_ME0 - (me[0] - x).hypot(me[2] - z)).max(0.0);
            if over < best.0 {
                best = (over, x, z);
            }
            if over == 0.0 {
                break;
            }
        }
        let (x, z) = (best.1, best.2);
        // (it comes down across the look from the player: seen from the side, a slab stuck in the ground; and on out from
        // the vent, as what was thrown does)
        let (sx, sz) = (x - me[0], z - me[2]);
        let sn = sx.hypot(sz).max(1.0);
        let a = sz.atan2(sx) + (0.8 + 0.6 * mh(k, seed, 0xd2)) * if x * sz / sn - z * sx / sn > 0.0 { -1.0 } else { 1.0 };
        out.push(Site { x, z, dir: (a.cos(), a.sin()), near: true });
    }
    for i in VL_NEAR..VL_N {
        let k = i as u32;
        let u = ((i - VL_NEAR) as f64 + 0.5 + 0.55 * (mh(k, seed, 0xd3) - 0.5)) / (VL_N - VL_NEAR) as f64;
        let a = phi + 1.1 + (TAU - 2.2) * u;
        let r = VL_R0 + 15.0 + (VL_R1 - VL_R0 - 15.0) * mh(k, seed, 0xd4);
        let d = a + 0.8 * (mh(k, seed, 0xd5) - 0.5);
        out.push(Site { x: r * a.cos(), z: r * a.sin(), dir: (d.cos(), d.sin()), near: false });
    }
    out
}
/// The forceloads that hold a site's chunks (one row of chunks each).
pub(super) fn vl_patch(point: [f64; 3], s: &Site) -> Vec<[i32; 4]> {
    super::vc_land::vc_load_rows([point[0] + s.x, point[1], point[2] + s.z], VL_PATCH)
}

/// Where a plate comes to rest: `r` turns its own frame (rows), `c` where its middle lies, from the vent's ground.
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
    fn quat(&self) -> [f64; 4] {
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

/// A plate as it was on the mount: what `Slab::new` needs of the mount's tables.
pub(super) struct Rock {
    pub id: usize,
    pub rest: [f64; 3],
    pub v: [f64; 3],
    pub tr: f64,
    pub tau: f64,
    pub axis: (f64, f64),
    pub spin: f64,
    pub th: f64,
    pub plane: (f64, f64),
    /// Its columns: their place from the vent (the mount's grid, VM_STEP apart), the land's top as the pass has it at the
    /// burst, the material on top and under that, how far from the smaller breaks in it.
    pub cols: Vec<RockCol>,
}
#[derive(Clone, Copy)]
pub(super) struct RockCol {
    pub i: i32,
    pub k: i32,
    pub top: f32,
    pub m: u8,
    pub kind: u8,
    pub d2: f32,
}
/// How thick a thrown plate is at (x, z) of the mount, a share of its thickness (volcano_mount.wgsl's vl_thk): its
/// underside torn, never a plane.
pub(super) fn vl_thk(x: f64, z: f64) -> f64 {
    let a = (x * 0.083 + 1.3 * (z * 0.047).sin()).sin() * (z * 0.071 - 0.9).sin();
    let b = (x * 0.19 - z * 0.13 + 0.7).sin() * (z * 0.17 + x * 0.05).sin();
    0.82 + 0.13 * a + 0.05 * b
}
const STEP: f64 = super::vc_mount::VM_STEP as f64;
const HALF: f64 = super::vc_mount::VM_HALF as f64;
/// How high the earth stands round a plate: a grid from `o`, `n` by `m`, `VL_TS` apart.
#[derive(Default)]
struct Fall {
    o: (f64, f64),
    n: usize,
    m: usize,
    t: Vec<f32>,
}
/// A plate come down.
pub(super) struct Slab {
    pub rock_id: usize,
    pub site: Site,
    pub hit: f64,
    pub near_rank: usize,
    tilt: f64,
    roll: f64,
    /// The way it lies, its low end first: near the way it came down.
    pub lay: (f64, f64),
    pub rest: [f64; 3],
    pub v: [f64; 3],
    tr: f64,
    tau: f64,
    pub g: f64,
    axis: (f64, f64),
    spin: f64,
    pub th: f64,
    plane: (f64, f64),
    /// Its land's top, from the plane through the middle, what's thick there and the rest of a column, on the grid `g0`
    /// (from the vent, VM_STEP apart), the columns not its own filled from those beside them.
    gw: usize,
    gh: usize,
    g0: (f64, f64),
    t: Vec<f32>,
    thick: Vec<f32>,
    mat: Vec<u8>,
    cr: Vec<u8>,
    /// The patches of its rock, and where it still burns: the grid's own noise (a column's own would be most of its work).
    nz: [Vec<f32>; 4],
    /// Whether a block's column of the mount is its own, a bit each from (b0).
    bw: usize,
    bh: usize,
    b0: (i32, i32),
    bits: Vec<u64>,
    /// Its land's top over the plane: from, to, and the mean; its length along `long`, from the rest's middle.
    tlo: f64,
    thi: f64,
    tmean: f64,
    long: [f64; 3],
    s0: f64,
    s1: f64,
    wide: f64,
    pub pose: Pose,
    fall: Fall,
    /// Where it comes down (from the vent's ground).
    pub foot: [f64; 3],
    u_top: f64,
    bits_done: bool,
    list: RefCell<Option<Vec<(i32, i32)>>>,
    rocks: Vec<Boulder>,
    spalls: Vec<Spall>,
    cracks: Vec<[f64; 5]>,
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
    top: &'static str,
}
impl Slab {
    pub fn new(rock: &Rock, site: Site, hit: f64, near_rank: usize, seed: u32, g: f64) -> Slab {
        let (mut i0, mut k0, mut i1, mut k1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for c in &rock.cols {
            i0 = i0.min(c.i);
            k0 = k0.min(c.k);
            i1 = i1.max(c.i);
            k1 = k1.max(c.k);
        }
        // (a row round it: the pass's corners and a walk off its edge find a height there)
        let (i0, k0) = (i0 - 2, k0 - 2);
        let (gw, gh) = ((i1 + 3 - i0) as usize, (k1 + 3 - k0) as usize);
        let n = gw * gh;
        crate::meter::spend(600 * n as u64);
        let g0 = (f64::from(i0) * STEP - HALF, f64::from(k0) * STEP - HALF);
        let (pa, pb) = rock.plane;
        let mut t = vec![f32::MAX; n];
        let mut mat = vec![0u8; n];
        let mut cr = vec![255u8; n];
        let (mut tlo, mut thi, mut sum) = (f64::MAX, f64::MIN, 0.0);
        let (mut xx, mut xz, mut zz) = (0.0, 0.0, 0.0);
        for c in &rock.cols {
            let j = (c.k - k0) as usize * gw + (c.i - i0) as usize;
            let (dx, dz) = (f64::from(c.i) * STEP - HALF - rock.rest[0], f64::from(c.k) * STEP - HALF - rock.rest[2]);
            let v = f64::from(c.top) - rock.rest[1] - pa * dx - pb * dz;
            t[j] = v as f32;
            mat[j] = c.m | c.kind << 6;
            cr[j] = (c.d2 * 8.0).min(255.0) as u8;
            tlo = tlo.min(v);
            thi = thi.max(v);
            sum += v;
            xx += dx * dx;
            xz += dx * dz;
            zz += dz * dz;
        }
        let tmean = sum / (rock.cols.len().max(1) as f64);
        // (out to the rows round it, from the columns beside each)
        for _ in 0..4 {
            let old = t.clone();
            let om = mat.clone();
            for k in 0..gh {
                for i in 0..gw {
                    let j = k * gw + i;
                    if old[j] != f32::MAX {
                        continue;
                    }
                    let (mut s, mut c, mut m) = (0.0, 0.0, 0);
                    for (a, b) in [(-1i32, 0i32), (1, 0), (0, -1), (0, 1)] {
                        let (ii, kk) = (i as i32 + a, k as i32 + b);
                        if ii >= 0 && kk >= 0 && (ii as usize) < gw && (kk as usize) < gh {
                            let q = kk as usize * gw + ii as usize;
                            if old[q] != f32::MAX {
                                s += old[q];
                                c += 1.0;
                                m = om[q];
                            }
                        }
                    }
                    if c > 0.0 {
                        t[j] = s / c;
                        mat[j] = m;
                    }
                }
            }
        }
        for v in &mut t {
            if *v == f32::MAX {
                *v = tmean as f32;
            }
        }
        let thick = (0..n)
            .map(|j| {
                let (x, z) = (g0.0 + (j % gw) as f64 * STEP, g0.1 + (j / gw) as f64 * STEP);
                (rock.th * vl_thk(x, z)) as f32
            })
            .collect();
        // (its long way: along it the thing goes into the ground)
        let tr2 = xx + zz;
        let a = 0.5 * (2.0 * xz).atan2(xx - zz);
        let _ = tr2;
        let (lx, lz) = (a.cos(), a.sin());
        let (nx, nz) = (-pa, -pb);
        let long = norm([lx, -(nx * lx + nz * lz), lz]);
        let (mut s0, mut s1, mut w0, mut w1) = (f64::MAX, f64::MIN, f64::MAX, f64::MIN);
        for c in &rock.cols {
            let (dx, dz) = (f64::from(c.i) * STEP - HALF - rock.rest[0], f64::from(c.k) * STEP - HALF - rock.rest[2]);
            let s = dx * long[0] + dz * long[2];
            let w = -dx * long[2] + dz * long[0];
            s0 = s0.min(s);
            s1 = s1.max(s);
            w0 = w0.min(w);
            w1 = w1.max(w);
        }
        let k = rock.id as u32;
        // (each as it happened to land: most low, the odd one higher; not all lying the way they came, or over the same
        // side)
        let tilt = (VL_LOW + (VL_STEEP - VL_LOW) * mh(k, seed, 0xd6).powf(1.6)).to_radians();
        let roll = (15.0 * (2.0 * mh(k, seed, 0xd7) - 1.0)).to_radians();
        let yaw = (42.0 * (2.0 * mh(k, seed, 0xd8) - 1.0)).to_radians();
        let lay = (site.dir.0 * yaw.cos() - site.dir.1 * yaw.sin(), site.dir.0 * yaw.sin() + site.dir.1 * yaw.cos());
        let mut s = Slab {
            rock_id: rock.id,
            site,
            hit,
            near_rank,
            tilt,
            roll,
            lay,
            rest: rock.rest,
            v: rock.v,
            tr: rock.tr,
            tau: rock.tau,
            g,
            axis: rock.axis,
            spin: rock.spin,
            th: rock.th,
            plane: rock.plane,
            gw,
            gh,
            g0,
            t,
            thick,
            mat,
            cr,
            nz: Default::default(),
            bw: 0,
            bh: 0,
            b0: (0, 0),
            bits: Vec::new(),
            tlo,
            thi,
            tmean,
            long,
            s0,
            s1,
            wide: w1 - w0,
            pose: Pose { r: [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]], c: [0.0; 3] },
            fall: Fall::default(),
            foot: [site.x, 0.0, site.z],
            u_top: 0.0,
            bits_done: false,
            list: RefCell::new(None),
            rocks: Vec::new(),
            spalls: Vec::new(),
            cracks: Vec::new(),
        };
        s.set_pose(0.0, (0.0, 0.0));
        s
    }
    /// The pose with the ground `gs` at its foot: its plane to the way it comes down at its tilt, the leading end of its
    /// length the one nearer how it is tumbling, `VL_BURY` of it past where it meets the ground.
    fn set_pose(&mut self, gs: f64, slope: (f64, f64)) {
        *self.list.borrow_mut() = None;
        let d = [self.lay.0, 0.0, self.lay.1];
        let up = [0.0, 1.0, 0.0];
        let (cs, sn) = (self.tilt.cos(), self.tilt.sin());
        let fl = [cs * d[0], -sn, cs * d[2]];
        let fn0 = [sn * d[0], cs, sn * d[2]];
        let fw0 = norm(cross(fl, fn0));
        // (a little over on one side)
        let (cr, sr) = (self.roll.cos(), self.roll.sin());
        let fnr = [0, 1, 2].map(|i| fn0[i] * cr + fw0[i] * sr);
        let fw = norm(cross(fl, fnr));
        // (all of that on the ground it comes down on, not on the level)
        let gn = norm([-slope.0, 1.0, -slope.1]);
        let sf = gn[0].hypot(gn[2]);
        let (fl, fnr, fw) = if sf > 1e-6 {
            let k = [gn[2] / sf, 0.0, -gn[0] / sf];
            let tip = |v: [f64; 3]| {
                let (c, x, d) = (cross(k, v), gn[1], dot(k, v));
                [0, 1, 2].map(|i| v[i] * x + c[i] * sf + k[i] * d * (1.0 - x))
            };
            (tip(fl), tip(fnr), tip(fw))
        } else {
            (fl, fnr, fw)
        };
        let en = norm([-self.plane.0, 1.0, -self.plane.1]);
        let _ = up;
        let mut best: Option<(f64, Pose, f64)> = None;
        let q_end = self.spin_quat(self.hit);
        for sign in [1.0, -1.0] {
            let el = self.long.map(|v| v * sign);
            let el = norm([0, 1, 2].map(|i| el[i] - en[i] * dot(el, en)));
            let ew = norm(cross(el, en));
            let mut r = [[0.0; 3]; 3];
            for (i, row) in r.iter_mut().enumerate() {
                for (j, v) in row.iter_mut().enumerate() {
                    *v = fl[i] * el[j] + fnr[i] * en[j] + fw[i] * ew[j];
                }
            }
            // (the point of its middle sheet that stays at the ground: `VL_BURY` back from its leading end)
            let (a, b) = if sign > 0.0 { (self.s1, self.s1 - self.s0) } else { (-self.s0, self.s1 - self.s0) };
            let sp = sign * (a - VL_BURY * b);
            let mid = self.tmean - 0.5 * self.th;
            let lp = [self.long[0] * sp, self.long[1] * sp + mid, self.long[2] * sp];
            let mut p = Pose { r, c: [0.0; 3] };
            let w = p.world(lp);
            p.c = [self.site.x - w[0], gs - w[1], self.site.z - w[2]];
            let q = p.quat();
            let d = (q[0] * q_end[0] + q[1] * q_end[1] + q[2] * q_end[2] + q[3] * q_end[3]).abs();
            if best.as_ref().is_none_or(|b| d > b.0) {
                best = Some((d, p, sp));
            }
        }
        self.pose = best.unwrap().1;
        self.foot = [self.site.x, gs, self.site.z];
        self.u_top = (0.5 * self.th / sn).min(VL_BURY * (self.s1 - self.s0));
    }
    /// The ground under the whole of it, from what's known of the land's height at (x, z): how high at its site and how it
    /// slopes, a plane through what lies under the plate (a steep bank or a shore by its foot must not leave the rest of
    /// it stood up on a stack of earth), a little low where the land is rough.
    fn bed(&self, pts: &[(i32, i32, f64)], bx: i32, bz: i32) -> Option<(f64, (f64, f64))> {
        let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
        let mut sp = Vec::new();
        let (mut n, mut sx, mut sz, mut sh, mut xx, mut xz, mut zz, mut xh, mut zh) = (0.0f64, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
        let (mut all, mut alls) = (0.0f64, 0.0f64);
        for &(x, z, h) in pts {
            all += 1.0;
            alls += h;
            let (wx, wz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
            self.spans(wx, wz, &mut sp);
            if sp.is_empty() {
                continue;
            }
            let (dx, dz) = (wx - self.site.x, wz - self.site.z);
            n += 1.0;
            sx += dx;
            sz += dz;
            sh += h;
            xx += dx * dx;
            xz += dx * dz;
            zz += dz * dz;
            xh += dx * h;
            zh += dz * h;
        }
        if all == 0.0 {
            return None;
        }
        if n < 8.0 {
            return Some((alls / all, (0.0, 0.0)));
        }
        // (the plane h = c + a dx + b dz, by least squares, its slope no steeper than the land's own hills)
        let (mx, mz, mh) = (sx / n, sz / n, sh / n);
        let (cxx, cxz, czz, cxh, czh) = (xx - n * mx * mx, xz - n * mx * mz, zz - n * mz * mz, xh - n * mx * mh, zh - n * mz * mh);
        let det = cxx * czz - cxz * cxz;
        let (mut a, mut b) = if det.abs() > 1.0 { ((cxh * czz - czh * cxz) / det, (czh * cxx - cxh * cxz) / det) } else { (0.0, 0.0) };
        let t = a.hypot(b);
        let most = VL_BANK.to_radians().tan();
        if t > most {
            a *= most / t;
            b *= most / t;
        }
        let c = mh - a * mx - b * mz;
        let mut e = 0.0;
        for &(x, z, h) in pts {
            let (wx, wz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
            self.spans(wx, wz, &mut sp);
            if !sp.is_empty() {
                let r = h - (c + a * (wx - self.site.x) + b * (wz - self.site.z));
                e += r * r;
            }
        }
        Some((c - (0.4 * (e / n).sqrt()).min(10.0), (a, b)))
    }
    /// How the tumble has turned it `t` into the strike, the pass's way.
    fn spin_quat(&self, t: f64) -> [f64; 4] {
        let a = 0.5 * self.spin * (t - self.tr);
        let (s, c) = (a.sin(), a.cos());
        [self.axis.0 * s, 0.0, self.axis.1 * s, c]
    }
    /// Its middle at `t`, as the pass flies it (vm_flown), before the ease.
    fn flown(&self, t: f64) -> [f64; 3] {
        let s = (t - VL_BRK).max(0.0);
        let a = t - self.tr - s;
        let eh = VL_TH * (1.0 - (-s / VL_TH).exp());
        let vy = self.v[1] - VL_G * a;
        let mut c = [self.rest[0] + self.v[0] * (a + eh), self.rest[1] + (self.v[1] - 0.5 * VL_G * a) * a, self.rest[2] + self.v[2] * (a + eh)];
        if s > 0.0 {
            let vt = self.g * self.tau;
            c[1] += (vy + vt) * self.tau * (1.0 - (-s / self.tau).exp()) - vt * s;
        }
        c
    }
    /// The aim of its flight: where its middle has to be as it hits, before the ease slides it in.
    pub fn aim(&self) -> [f64; 3] {
        [self.pose.c[0] - VL_SLIDE * self.lay.0, self.pose.c[1], self.pose.c[2] - VL_SLIDE * self.lay.1]
    }
    /// Its pose over ground at `gs`, and the flight that takes it there: how fast it is thrown (its gravity set too).
    pub fn fly(&mut self, gs: f64) -> [f64; 3] {
        self.set_pose(gs, (0.0, 0.0));
        let aim = self.aim();
        let a = VL_BRK - self.tr;
        let sec = self.hit - VL_BRK;
        let eh = VL_TH * (1.0 - (-sec / VL_TH).exp());
        self.v[0] = (aim[0] - self.rest[0]) / (a + eh);
        self.v[2] = (aim[2] - self.rest[2]) / (a + eh);
        let vy = self.v[1] - VL_G * a;
        let y = self.rest[1] + (self.v[1] - 0.5 * VL_G * a) * a;
        let e = self.tau * (1.0 - (-sec / self.tau).exp());
        self.g = (y + vy * e - aim[1]) / (self.tau * (sec - e));
        self.v
    }
    /// The pass's words for it (`gone`: when it goes, 0 not yet, under 0 it goes into the ground).
    pub fn words(&self, gone: f64) -> Vec<u32> {
        let q = self.pose.quat();
        let f = self.flown(self.hit);
        let d = [self.pose.c[0] - f[0], self.pose.c[1] - f[1], self.pose.c[2] - f[2]];
        let w = [q[0], q[1], q[2], q[3], d[0], d[1], d[2], gone, self.hit - VL_EASE, self.foot[0], self.foot[1], self.foot[2], self.rock_id as f64, self.lay.0, self.lay.1, 0.5 * (self.s1 - self.s0)];
        crate::meter::spend(2_000);
        w.iter().map(|v| (*v as f32).to_bits()).collect()
    }
    /// Whose columns are whose, block by block, as the pass's broken edges have it (a table worked out for each at
    /// the end of the mount's tables, in a stage of its own).
    pub fn set_bits(&mut self, own: &dyn Fn(usize, usize) -> bool, seed: u32) {
        // (the wander of the edges (vm_in_plate's jit) at the grid's own corners, smooth between)
        let (sd, n) = (seed ^ self.rock_id as u32, self.gw * self.gh);
        for (a, (scale, salt)) in self.nz.iter_mut().zip([(13.0, 0x41), (8.0, 0x42), (27.0, 0x45), (61.0, 0x46)]) {
            *a = (0..n).map(|j| qnoise(self.g0.0 + (j % self.gw) as f64 * STEP, self.g0.1 + (j / self.gw) as f64 * STEP, scale, sd ^ salt) as f32).collect();
        }
        crate::meter::spend(1_000 * n as u64);
        let (bw, bh) = ((self.gw - 1) * STEP as usize, (self.gh - 1) * STEP as usize);
        self.bw = bw;
        self.bh = bh;
        self.b0 = (self.g0.0 as i32, self.g0.1 as i32);
        self.bits = vec![0u64; (bw * bh).div_ceil(64)];
        crate::meter::spend(2_000 * (self.gw * self.gh) as u64 + 60 * (bw * bh) as u64);
        let (gw, gh) = (self.gw, self.gh);
        let mut jit = vec![(0f32, 0f32); gw * gh];
        for k in 0..gh {
            for i in 0..gw {
                let (x, z) = (self.g0.0 + i as f64 * STEP, self.g0.1 + k as f64 * STEP);
                jit[k * gw + i] = (((z * 0.43 + x * 0.11).sin() * 0.8) as f32, ((x * 0.47 - z * 0.13).sin() * 0.8) as f32);
            }
        }
        let s = STEP as usize;
        for bz in 0..bh {
            let (k, fz) = (bz / s, (bz % s) as f32 / STEP as f32);
            for bx in 0..bw {
                let (i, fx) = (bx / s, (bx % s) as f32 / STEP as f32);
                let j = k * gw + i;
                let m = |a: f32, b: f32, c: f32, d: f32| (a * (1.0 - fx) + b * fx) * (1.0 - fz) + (c * (1.0 - fx) + d * fx) * fz;
                let jx = m(jit[j].0, jit[j + 1].0, jit[j + gw].0, jit[j + gw + 1].0);
                let jz = m(jit[j].1, jit[j + 1].1, jit[j + gw].1, jit[j + gw + 1].1);
                // (the pass's: the corner nearest the block, the wander added)
                let (gi, gk) = (i as f32 + fx + 0.5 + jx, k as f32 + fz + 0.5 + jz);
                if own(gi.max(0.0) as usize, gk.max(0.0) as usize) {
                    let q = bz * bw + bx;
                    self.bits[q / 64] |= 1 << (q % 64);
                }
            }
        }
        self.bits_done = true;
    }
    /// The mount's column its grid starts at (for `set_bits`).
    pub fn grid_cells(&self) -> (usize, usize) {
        (((self.g0.0 + HALF) / STEP) as usize, ((self.g0.1 + HALF) / STEP) as usize)
    }
    #[inline]
    fn own(&self, lx: f64, lz: f64) -> bool {
        let (x, z) = ((lx + self.rest[0] - f64::from(self.b0.0)) as i32, (lz + self.rest[2] - f64::from(self.b0.1)) as i32);
        if x < 0 || z < 0 || x >= self.bw as i32 || z >= self.bh as i32 {
            return false;
        }
        let q = z as usize * self.bw + x as usize;
        self.bits[q / 64] >> (q % 64) & 1 != 0
    }
    /// The nearest grid cell and how far into it, at (lx, lz) of its own frame.
    #[inline]
    fn cell(&self, lx: f64, lz: f64) -> (usize, f32, f32) {
        let u = (lx + self.rest[0] - self.g0.0) / STEP;
        let v = (lz + self.rest[2] - self.g0.1) / STEP;
        let (u, v) = (u.clamp(0.0, (self.gw - 2) as f64 + 0.999), v.clamp(0.0, (self.gh - 2) as f64 + 0.999));
        let (i, k) = (u as usize, v as usize);
        (k * self.gw + i, (u - i as f64) as f32, (v - k as f64) as f32)
    }
    #[inline]
    fn lerp(&self, a: &[f32], c: (usize, f32, f32)) -> f64 {
        let (j, u, v) = c;
        let w = self.gw;
        f64::from((a[j] * (1.0 - u) + a[j + 1] * u) * (1.0 - v) + (a[j + w] * (1.0 - u) + a[j + w + 1] * u) * v)
    }
    /// The column of the world (wx, wz) from the vent through it: the stretches (from, to) of height that are in it, from
    /// the vent's ground, and for each how high its top and underside are along that line.
    fn spans(&self, wx: f64, wz: f64, out: &mut Vec<Stretch>) {
        out.clear();
        let p = &self.pose;
        let (dx, dy, dz) = (wx - p.c[0], -p.c[1], wz - p.c[2]);
        let r = &p.r;
        let a = [r[0][0] * dx + r[1][0] * dy + r[2][0] * dz, r[0][1] * dx + r[1][1] * dy + r[2][1] * dz, r[0][2] * dx + r[1][2] * dy + r[2][2] * dz];
        let b = [r[1][0], r[1][1], r[1][2]];
        let (pa, pb) = self.plane;
        let h0 = a[1] - pa * a[0] - pb * a[2];
        let h1 = b[1] - pa * b[0] - pb * b[2];
        // (the two faces, each found in a few steps: what's along the line is as good as flat for that)
        let mut yt = (self.tmean - h0) / h1;
        for _ in 0..5 {
            let c = self.cell(a[0] + b[0] * yt, a[2] + b[2] * yt);
            yt = 0.5 * yt + 0.5 * (self.lerp(&self.t, c) - h0) / h1;
        }
        let mut yb = yt - self.th / h1;
        for _ in 0..6 {
            let c = self.cell(a[0] + b[0] * yb, a[2] + b[2] * yb);
            yb = 0.5 * yb + 0.5 * (self.lerp(&self.t, c) - self.lerp(&self.thick, c) - h0) / h1;
        }
        if yb >= yt {
            return;
        }
        // (a line through its broken edge is in it only part of the way)
        let mut y = yb;
        let mut start: Option<f64> = None;
        while y < yt + 2.9 {
            let yy = y.min(yt);
            let inside = self.own(a[0] + b[0] * yy, a[2] + b[2] * yy);
            match (inside, start) {
                (true, None) => {
                    // (its edge found to within a block and a half)
                    let m = yy - 1.5;
                    start = Some(if m > yb && self.own(a[0] + b[0] * m, a[2] + b[2] * m) { m } else { yy });
                }
                (false, Some(s)) => {
                    let m = yy - 1.5;
                    out.push(Stretch { y0: s, y1: if self.own(a[0] + b[0] * m, a[2] + b[2] * m) { yy } else { m }, top: yt, h1 });
                    start = None;
                }
                _ => {}
            }
            y += 3.0;
        }
        if let Some(s) = start {
            out.push(Stretch { y0: s, y1: yt, top: yt, h1 });
        }
        crate::meter::spend(1_500);
    }
    /// The material under what stood on it, at the plate's own (lx, lz).
    fn top_mat(&self, lx: f64, lz: f64) -> (u8, u8, u8) {
        let u = ((lx + self.rest[0] - self.g0.0) / STEP + 0.5).clamp(0.0, (self.gw - 1) as f64) as usize;
        let v = ((lz + self.rest[2] - self.g0.1) / STEP + 0.5).clamp(0.0, (self.gh - 1) as f64) as usize;
        let m = self.mat[v * self.gw + u];
        (m & 63, m >> 6, self.cr[v * self.gw + u])
    }
    /// One column of the plate, blocks from the world's `base` up. `floor`: the lowest worth laying (none: all of it).
    fn plate_col(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, floor: Option<i32>, sp: &mut Vec<Stretch>) {
        self.spans(wx, wz, sp);
        for s in sp.iter() {
            crate::meter::spend(1_200);
            let (mut y0, y1) = ((s.y0 + f64::from(gy) - 0.5).ceil() as i32, ((s.y1 + f64::from(gy) - 0.5).floor() as i32).min(318));
            if let Some(f) = floor {
                y0 = y0.max(f);
            }
            if y1 < y0 {
                continue;
            }
            let wy = |d: f64| (s.top - d / s.h1 + f64::from(gy) - 0.5).floor() as i32;
            // (what it is at this point of the plate: from the point of the line in the middle of the stretch)
            let lp = self.pose.local([wx, 0.5 * (s.y0 + s.y1), wz]);
            let (m, kind, crack) = self.top_mat(lp[0], lp[2]);
            let c = self.cell(lp[0], lp[2]);
            let (n, n2) = (self.lerp(&self.nz[0], c), self.lerp(&self.nz[1], c));
            let thick = self.lerp(&self.thick, c);
            let (surface, soil) = lodged_top(m, kind, n2);
            let at_top = s.y1 >= s.top - 0.01;
            // (the small breaks in it opened: its top cut down along them, as the pass draws them dark)
            let cut = if at_top && crack < 10 { 2 + (4.0 * (1.0 - f64::from(crack) / 10.0)) as i32 } else { 0 };
            let y1 = y1 - cut;
            if y1 < y0 {
                continue;
            }
            // (down from its top: its surface, as thick as its slope's steps; the soil; the rock, darker the deeper; the
            // torn underside)
            let step = 1 + (1.0 / self.pose.r[1][1].abs().max(0.3) - 0.4) as i32;
            let top_of_soil = y1 - step;
            let soil_d = if soil.is_some() { 3.0 + 4.0 * n } else { 0.0 };
            let y_soil = wy(soil_d + 1.0).min(top_of_soil);
            let y_rock = wy(0.55 * thick + 7.0 * (n2 - 0.5));
            let y_under = wy(thick - 3.0 - 4.0 * n2);
            let burnt = vl_burnt(self.lerp(&self.nz[2], c), self.lerp(&self.nz[3], c), n);
            let (rock, deep) = rocks(n, n2);
            b.run(x, z, y0, y_under.min(y1), burnt);
            b.run(x, z, y0.max(y_under + 1), y_rock.min(y1), deep);
            b.run(x, z, y0.max(y_rock + 1), y_soil.min(y1), rock);
            if at_top {
                if let Some(sl) = soil {
                    b.run(x, z, y0.max(y_soil + 1), top_of_soil, sl);
                } else {
                    b.run(x, z, y0.max(y_soil + 1), top_of_soil, rock);
                }
                b.run(x, z, y0.max(top_of_soil + 1), y1, if cut > 0 { "minecraft:tuff" } else { surface });
            } else {
                b.run(x, z, y0.max(y_soil + 1), y1, soil.unwrap_or(rock));
            }
        }
    }
    /// What it does to the ground: the rubble and cracks round it, worked out once it is known where it stands.
    fn litter(&mut self, seed: u32) {
        self.make_fall();
        let s = seed ^ (self.rock_id as u32).wrapping_mul(0x9e37);
        let (dx, dz) = self.lay;
        let (ax, az) = (-dz, dx);
        let w = 0.5 * self.wide;
        let (ut, f) = (self.u_top, self.foot);
        let m = |k: u32, q: u32| mh(k, s, q);
        let place = |u: f64, v: f64| (f[0] + dx * u + ax * v, f[2] + dz * u + az * v);
        for k in 0..60 {
            let a = m(k, 0xe0);
            // (most heaped at its foot, in front; the rest strewn)
            let u = if a < 0.6 { ut + 4.0 + 42.0 * m(k, 0xe1).powi(2) } else { -ut - 50.0 + (2.0 * ut + 130.0) * m(k, 0xe1) };
            let v = (w + 42.0) * (2.0 * m(k, 0xe2) - 1.0);
            let (x, z) = place(u, v);
            let r = 1.5 + 6.0 * m(k, 0xe3).powi(3);
            let a = TAU * m(k, 0xe9);
            self.rocks.push(Boulder { x, z, r, h: r * (0.5 + 0.5 * m(k, 0xe4)), m: (m(k, 0xe5) * 5.0) as u8, c: a.cos(), s: a.sin() });
        }
        for k in 0..14 {
            let u = -ut * 0.5 + (2.0 * ut + 34.0) * m(k, 0xe6);
            let side = if m(k, 0xe7) < 0.5 { -1.0 } else { 1.0 };
            let v = side * (w * (0.35 + 0.8 * m(k, 0xe8)) + 8.0);
            let (x, z) = place(u, v);
            let (len, wid, thk) = (9.0 + 15.0 * m(k, 0xe9), 6.0 + 9.0 * m(k, 0xea), 2.5 + 3.0 * m(k, 0xeb));
            let (yaw, dip) = (TAU * m(k, 0xec), (30.0 + 40.0 * m(k, 0xed)).to_radians());
            let l = [yaw.cos() * dip.cos(), -dip.sin(), yaw.sin() * dip.cos()];
            let n = norm([yaw.cos() * dip.sin(), dip.cos(), yaw.sin() * dip.sin()]);
            let e = norm(cross(l, n));
            let c = [x, f[1] + 0.25 * len * dip.sin(), z];
            self.spalls.push(Spall { c, e: [l, n, e], half: [len * 0.5, thk * 0.5, wid * 0.5], top: if m(k, 0xee) < 0.5 { "minecraft:dirt" } else { "minecraft:stone" } });
        }
        // (cracks of tuff, out from round it)
        let reach = 0.5 * (self.s1 - self.s0);
        for k in 0..11 {
            let a = TAU * (f64::from(k) + 0.8 * m(k, 0xf0)) / 11.0;
            let (mut x, mut z) = (f[0] - dx * 0.3 * reach + (0.55 * reach) * a.cos(), f[2] - dz * 0.3 * reach + (0.55 * reach) * a.sin());
            let len = 22.0 + 52.0 * m(k, 0xf1).powi(2);
            let mut b = a;
            let mut left = len;
            let mut wd = 1.8 + 1.8 * m(k, 0xf2);
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
        let w = 0.5 * self.wide;
        let ut = self.u_top;
        let size = (0.7 + (self.s1 - self.s0) / 300.0).min(1.3);
        let e = 1.0 - smooth(w - 8.0, w + 26.0, v.abs());
        // (a lip in front: what it ploughed up, against its face; and down its sides, less)
        let f = (u - ut - 7.0) / (if u > ut + 7.0 { 15.0 } else { 7.0 });
        let bell = |x: f64| {
            let k = 1.0 + 0.5 * x * x;
            1.0 / (k * k)
        };
        let lip = 15.0 * size * bell(f) * e;
        let sv = (v.abs() - w - 8.0) / 11.0;
        let side = 6.0 * size * bell(sv) * smooth(-ut - 50.0, -ut - 10.0, u) * (1.0 - smooth(ut, ut + 20.0, u));
        // (behind it the ground it tore open as it went in, under the overhang)
        let bu = (u + ut + 20.0) / 28.0;
        let dug = 5.0 * bell(bu) * e;
        (lip + side) * (0.45 + 1.1 * n) - dug * (0.5 + n)
    }
    /// A column's ground: heaped or dug, the trees on it gone, its cracks, its rubble: the world's Y its ground is at
    /// afterwards. `col`: what the read said stands there.
    fn ground_col(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, col: Option<&Col>, seed: u32, near_ones: &Near) -> Option<i32> {
        let (dx, dz) = self.lay;
        let (ox, oz) = (wx - self.foot[0], wz - self.foot[2]);
        let (u, v) = (ox * dx + oz * dz, oz * dx - ox * dz);
        let w = 0.5 * self.wide;
        let len = self.s1 - self.s0;
        let near = u > -self.u_top - 70.0 - 0.3 * len && u < self.u_top + 90.0 && v.abs() < w + 56.0;
        crate::meter::spend(420);
        if !near {
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
                    let m = heap_block(n, n2);
                    b.put(x, z, 0, hh - 1, m, None, true);
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
                b.run(x, z, lo, c, "minecraft:stone");
                if c >= lo {
                    b.run(x, z, c, c, s.top);
                }
            }
        }
        crate::meter::spend(60 * near_ones.spalls.len() as u64);
        Some(top)
    }
    /// What lies under it where it stands clear of the ground: the land it came down on, crushed and shoved up under it,
    /// so nothing of it is held up by air. `sp`: its stretches in this column, `g` the ground's top as `ground_col` left it.
    fn under(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, g: i32, c: &Col, sp: &[Stretch], seed: u32) {
        let Some(low) = sp.iter().map(|s| s.y0).reduce(f64::min) else { return };
        let y = (low + f64::from(gy) - 0.5).ceil() as i32 - 1;
        if y <= g {
            return;
        }
        let n = qnoise(wx, wz, 17.0, seed ^ 0x53);
        let bed = if c.fluid { c.g + 1 } else { g + 1 };
        // (in beds, whose edges wander: a stripe of its own to a column would show as bars down its face)
        let h = f64::from(y - bed + 1);
        let a = bed + (h * (0.35 + 0.3 * n)) as i32;
        let d = (y - 1 - (2.0 + 4.0 * n) as i32).max(a);
        b.run(x, z, bed, a, "minecraft:tuff");
        b.run(x, z, a + 1, d, "minecraft:cobbled_deepslate");
        b.run(x, z, d + 1, y, "minecraft:coarse_dirt");
        if c.top > y {
            b.run(x, z, y + 1, c.top, "minecraft:air");
        }
        crate::meter::spend(800);
    }
    /// How high the earth shoved up under it stands round it, coarsely, from the vent's ground: its underside where it is,
    /// falling away `VL_FALL` a block from there. Once, as it comes to rest: a chunk's worth of this each chunk was a sixth
    /// of all its work.
    fn make_fall(&mut self) {
        let st = VL_TS as f64;
        let (mut x0, mut z0, mut x1, mut z1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for k in 0..self.gh {
            for i in 0..self.gw {
                if self.cr[k * self.gw + i] != 255 {
                    let (lx, lz) = (self.g0.0 + i as f64 * STEP - self.rest[0], self.g0.1 + k as f64 * STEP - self.rest[2]);
                    let w = self.pose.world([lx, f64::from(self.t[k * self.gw + i]) + self.plane.0 * lx + self.plane.1 * lz, lz]);
                    (x0, z0, x1, z1) = (x0.min(w[0]), z0.min(w[2]), x1.max(w[0]), z1.max(w[2]));
                }
            }
        }
        let (ox, oz) = (((x0 - VL_TALL) / st).floor() * st, ((z0 - VL_TALL) / st).floor() * st);
        let (n, m) = (((x1 + VL_TALL - ox) / st) as usize + 2, ((z1 + VL_TALL - oz) / st) as usize + 2);
        let mut t = vec![f32::MIN; n * m];
        let mut sp = Vec::with_capacity(3);
        for k in 0..m {
            for i in 0..n {
                self.spans(ox + st * i as f64, oz + st * k as f64, &mut sp);
                if let Some(y) = sp.iter().map(|s| s.y0).reduce(f64::min) {
                    t[k * n + i] = y as f32;
                }
            }
        }
        let (d1, d2) = ((VL_FALL * st) as f32, (VL_FALL * st * 1.4142) as f32);
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
        crate::meter::spend(40 * (n * m) as u64);
        self.fall = Fall { o: (ox, oz), n, m, t };
    }
    /// A column beside it: the earth it shoved up, heaped against its edge so no wall of it stands sheer.
    fn talus(&self, b: &mut Blocks, x: i32, z: i32, wx: f64, wz: f64, gy: i32, g: i32, c: &Col, seed: u32) {
        let (st, f) = (VL_TS as f64, &self.fall);
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
        let y = (h + f64::from(gy) + 5.0 * (n1 - 0.5) + 2.5 * (n2 - 0.5)).round() as i32;
        if y <= g {
            return;
        }
        let bed = if c.fluid { c.g + 1 } else { g + 1 };
        b.run(x, z, bed, y - 1, if n1 < 0.45 { "minecraft:dirt" } else { "minecraft:tuff" });
        b.run(x, z, y, y, heap_block(n1, n2));
        if c.top > y {
            b.run(x, z, y + 1, c.top, "minecraft:air");
        }
    }
    /// The edits of the chunk with corner (x0, z0): its ground, then the plate. `read`: what stands on each of its columns
    /// (x then z), none where the world has not said.
    pub fn chunk(&self, x0: i32, z0: i32, bx: i32, bz: i32, gy: i32, seed: u32, read: Option<&[Option<Col>]>) -> Blocks {
        let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
        let mut b = Blocks::default();
        let mut sp: Vec<Stretch> = Vec::with_capacity(3);
        // (what lies round the chunk: most of it lies nowhere near)
        let (mx, mz) = (f64::from(x0) + 8.0 - cx, f64::from(z0) + 8.0 - cz);
        let in_reach = |x: f64, z: f64, r: f64| (x - mx).abs() < r + 8.5 && (z - mz).abs() < r + 8.5;
        let near = Near {
            rocks: self.rocks.iter().enumerate().filter(|(_, r)| in_reach(r.x, r.z, r.r)).map(|e| e.0).collect(),
            spalls: self.spalls.iter().enumerate().filter(|(_, r)| in_reach(r.c[0], r.c[2], r.half[0] + r.half[2])).map(|e| e.0).collect(),
            cracks: self.cracks.iter().enumerate().filter(|(_, c)| in_reach(0.5 * (c[0] + c[2]), 0.5 * (c[1] + c[3]), 0.5 * (c[0] - c[2]).hypot(c[1] - c[3]) + c[4])).map(|e| e.0).collect(),
        };
        crate::meter::spend(30 * (self.rocks.len() + self.spalls.len() + self.cracks.len()) as u64);
        for z in z0..z0 + 16 {
            for x in x0..x0 + 16 {
                let (wx, wz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
                let col = read.and_then(|r| r[((z - z0) * 16 + x - x0) as usize].as_ref());
                let g = self.ground_col(&mut b, x, z, wx, wz, gy, col, seed, &near);
                self.plate_col(&mut b, x, z, wx, wz, gy, g.map(|g| g - 1), &mut sp);
                if let (Some(g), Some(c)) = (g, col) {
                    if sp.is_empty() {
                        self.talus(&mut b, x, z, wx, wz, gy, g, c, seed);
                    } else {
                        self.under(&mut b, x, z, wx, wz, gy, g, c, &sp, seed);
                    }
                }
            }
        }
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
        let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
        let mut set: crate::ground::FxMap<(i32, i32), ()> = Default::default();
        let mut add = |x: f64, z: f64| {
            set.insert((((x + cx).floor() as i32) >> 4, ((z + cz).floor() as i32) >> 4), ());
        };
        // (the plate: every cell of its grid that's its own, its top and underside)
        for k in 0..self.gh {
            for i in 0..self.gw {
                if self.cr[k * self.gw + i] == 255 {
                    continue;
                }
                let (lx, lz) = (self.g0.0 + i as f64 * STEP - self.rest[0], self.g0.1 + k as f64 * STEP - self.rest[2]);
                let t = f64::from(self.t[k * self.gw + i]);
                let y = t + self.plane.0 * lx + self.plane.1 * lz;
                for d in [0.0, self.th] {
                    let w = self.pose.world([lx, y - d, lz]);
                    add(w[0], w[2]);
                }
            }
        }
        // (the ground round its foot)
        let (dx, dz) = self.lay;
        let (ax, az) = (-dz, dx);
        let w = 0.5 * self.wide + 50.0;
        let mut u = -self.u_top - 60.0;
        while u < self.u_top + 90.0 {
            let mut v = -w;
            while v <= w {
                // (no further than its site's chunks are held)
                if u * u + v * v < (VL_PATCH - 12.0) * (VL_PATCH - 12.0) {
                    add(self.foot[0] + dx * u + ax * v, self.foot[2] + dz * u + az * v);
                }
                v += 8.0;
            }
            u += 8.0;
        }
        let (fx, fz) = (self.foot[0], self.foot[2]);
        for c in self.cracks.iter().filter(|c| (c[2] - fx).powi(2) + (c[3] - fz).powi(2) < (VL_PATCH - 12.0) * (VL_PATCH - 12.0)) {
            add(c[0], c[1]);
            add(c[2], c[3]);
        }
        let mut out: Vec<(i32, i32)> = set.keys().map(|&(a, b)| (a * 16, b * 16)).collect();
        let (fx, fz) = (self.foot[0] + cx, self.foot[2] + cz);
        let key = |c: &(i32, i32)| ((f64::from(c.0) + 8.0 - fx).powi(2) + (f64::from(c.1) + 8.0 - fz).powi(2)) as i64;
        out.sort_by_key(key);
        crate::meter::spend(200 * (self.gw * self.gh + out.len()) as u64);
        out
    }
    /// Whether (wx, wz) from the vent lies in its reach: the land's work leaves it alone.
    pub fn covers(&self, wx: f64, wz: f64) -> bool {
        let (ox, oz) = (wx - self.foot[0], wz - self.foot[2]);
        let (u, v) = (ox * self.lay.0 + oz * self.lay.1, oz * self.lay.0 - ox * self.lay.1);
        v.abs() < 0.5 * self.wide + 40.0 && u > -(self.s1 - self.s0) - 10.0 && u < self.u_top + 70.0
    }
}
/// What of its rubble and cracks reach a chunk.
struct Near {
    rocks: Vec<usize>,
    spalls: Vec<usize>,
    cracks: Vec<usize>,
}
/// A stretch of a world column inside a plate, from the vent's ground, with how high the plate's top is along that line.
#[derive(Clone, Copy)]
struct Stretch {
    y0: f64,
    y1: f64,
    top: f64,
    h1: f64,
}
fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
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
/// What its top is: the block on top, and the soil under that (none: rock to the top).
fn lodged_top(m: u8, kind: u8, n: f64) -> (&'static str, Option<&'static str>) {
    let dirt = Some("minecraft:dirt");
    match (kind, m) {
        (3, _) | (_, 10) | (_, 11) => ("minecraft:snow_block", dirt),
        (_, 3) => ("minecraft:coarse_dirt", dirt),
        (_, 4) => ("minecraft:podzol", dirt),
        (_, 6) => ("minecraft:mud", dirt),
        (_, 9) => ("minecraft:mycelium", dirt),
        (_, 12 | 13) => ("minecraft:stone", None),
        (_, 14) => ("minecraft:andesite", None),
        (_, 15) => ("minecraft:diorite", None),
        (_, 16) => ("minecraft:granite", None),
        (_, 17) => ("minecraft:tuff", None),
        (_, 19) => ("minecraft:calcite", None),
        (_, 20) => ("minecraft:gravel", None),
        (_, 21) => ("minecraft:sand", Some("minecraft:sandstone")),
        (_, 22) => ("minecraft:red_sand", Some("minecraft:red_sandstone")),
        (_, 23) => ("minecraft:clay", dirt),
        // (what was water drained off it: its bed)
        (2, _) | (_, 25) => (if n < 0.5 { "minecraft:gravel" } else { "minecraft:clay" }, None),
        _ => ("minecraft:grass_block", dirt),
    }
}
/// The rock in it: the upper and the deeper, in patches.
fn rocks(n: f64, n2: f64) -> (&'static str, &'static str) {
    let rock = if n < 0.34 { "minecraft:andesite" } else if n2 > 0.72 { "minecraft:cobblestone" } else { "minecraft:stone" };
    let deep = if n < 0.42 { "minecraft:tuff" } else if n2 > 0.6 { "minecraft:cobbled_deepslate" } else { "minecraft:deepslate" };
    (rock, deep)
}
/// Its underside: torn dark rock, a few veins of what still burns.
fn vl_burnt(n27: f64, n61: f64, n: f64) -> &'static str {
    let vein = (n27 - 0.5).abs() < 0.022 && n61 > 0.46;
    if vein {
        "minecraft:magma_block"
    } else if n < 0.45 {
        "minecraft:basalt"
    } else if n < 0.72 {
        "minecraft:blackstone"
    } else {
        "minecraft:smooth_basalt"
    }
}
fn heap_block(n: f64, n2: f64) -> &'static str {
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
        2 => if n < 0.5 { "minecraft:basalt" } else { "minecraft:blackstone" },
        3 => "minecraft:cobbled_deepslate",
        _ => "minecraft:andesite",
    }
}

// ---- the plates as the strike goes on --------------------------------------------------------------------------------
#[derive(Clone, Copy, PartialEq, Debug)]
enum Step {
    /// Waiting for the ground under it to be asked about.
    Idle,
    /// Asked: (the query, when).
    Asked(u32, f32),
    /// Its pose settled, in the air.
    Settled,
    /// Its blocks going in.
    Building,
    Done,
    /// No blocks: drawn into the ground as the others are.
    Failed,
}
/// Chunks of it asked of the world together.
struct Lot {
    slab: usize,
    tag: u32,
    asked: f32,
    chunks: Vec<(i32, i32)>,
    next: usize,
    read: Option<Rc<crate::columns::Answer>>,
    kinds: Vec<(super::nuke::Kind, u8)>,
    answered: bool,
}
/// The plates, shared by the mount's tables, the stages that land them and the land's work (which leaves them alone).
pub(super) struct Lodge {
    pub sites: Vec<Site>,
    pub slabs: Vec<Slab>,
    seed: u32,
    terrain: bool,
    me: [f64; 3],
    vent: [f64; 3],
    stage: Vec<Step>,
    todo: Vec<Vec<(i32, i32)>>,
    next: Vec<usize>,
    made: Vec<u32>,
    sent: Vec<Rc<Cell<u32>>>,
    lots: std::collections::VecDeque<Lot>,
    pub landed: u32,
}
pub(super) type Shared = Rc<RefCell<Lodge>>;
impl Lodge {
    pub fn new(sites: Vec<Site>, seed: u32, terrain: bool, me: [f64; 3], vent: [f64; 3]) -> Self {
        Lodge { sites, slabs: Vec::new(), seed, terrain, me, vent, stage: Vec::new(), todo: Vec::new(), next: Vec::new(), made: Vec::new(), sent: Vec::new(), lots: Default::default(), landed: 0 }
    }
    pub fn set_slabs(&mut self, slabs: Vec<Slab>) {
        let n = slabs.len();
        self.slabs = slabs;
        self.stage = vec![Step::Idle; n];
        self.todo = vec![Vec::new(); n];
        self.next = vec![0; n];
        self.made = vec![0; n];
        self.sent = (0..n).map(|_| Rc::default()).collect();
    }
    /// Whether the land's work should leave column (wx, wz) from the vent alone.
    pub fn covers(&self, wx: f64, wz: f64) -> bool {
        self.slabs.iter().enumerate().any(|(i, s)| !matches!(self.stage[i], Step::Failed) && s.covers(wx, wz))
    }
    /// Whether any plate comes down near the chunk at (wx, wz) from the vent (its middle).
    pub fn near(&self, wx: f64, wz: f64) -> bool {
        self.slabs.iter().any(|s| (s.foot[0] - wx).hypot(s.foot[2] - wz) < 260.0)
    }
    /// The pass's words: which plates, and each where it stands as far as is known (with the terrain off they go on into
    /// the ground).
    pub fn words(&self) -> (Vec<u32>, Vec<u32>) {
        let mut map = vec![0u32; super::vc_mount::VM_FLY];
        let mut w = Vec::with_capacity(VL_N * VL_W);
        for (i, s) in self.slabs.iter().enumerate() {
            map[s.rock_id] = i as u32 + 1;
            w.extend(s.words(if self.terrain { 0.0 } else { -1.0 }));
        }
        (map, w)
    }
}
/// The stages that bring them in, from a little before the first can be asked about.
pub(super) fn vl_plan(p: &mut Plan, l: Shared) {
    p.later(VL_ASK, move |q| {
        // (should it be stopped with one half built, it finishes it: never due otherwise)
        let f = l.clone();
        q.ev.push((1.0e9, Act::Cleanup(Box::new(move || vl_finish(f)))));
        vl_tick(q, l, VL_ASK);
    });
}
/// The columns asked about a plate: across the way it comes down, where it meets the ground, and a column of each chunk.
fn asked_cols(s: &Slab, bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let (dx, dz) = s.lay;
    let (ax, az) = (-dz, dx);
    let w = 0.5 * s.wide + 8.0;
    let ut = s.u_top.min(32.0) + 8.0;
    let mut out = Vec::new();
    let mut u = -ut;
    while u <= ut {
        let mut v = -w;
        while v <= w {
            out.push(((s.foot[0] + dx * u + ax * v + cx).floor() as i32, (s.foot[2] + dz * u + az * v + cz).floor() as i32));
            v += 7.0;
        }
        u += 7.0;
    }
    let n = out.len();
    out.extend(s.chunks(bx, bz).iter().map(|c| (c.0 + 8, c.1 + 8)));
    crate::meter::spend(100 * out.len() as u64);
    let _ = n;
    out
}
/// A stage a tick while there is anything to do.
fn vl_tick(q: &mut Plan, l: Shared, now: f32) {
    // (it takes its turn with the other stages: a tick in two, as often as not)
    let now = now.max(clock());
    let more = {
        let mut g = l.borrow_mut();
        let w = &mut *g;
        let (bx, bz, gy) = (q.bx, q.bz, q.by + 1);
        for i in 0..w.slabs.len() {
            // (what's asked and answered shared out over the ticks)
            if crate::meter::spent() > 2_000_000 {
                break;
            }
            let hit = w.slabs[i].hit as f32;
            match w.stage[i] {
                Step::Idle if now >= VL_ASK => {
                    let tag = crate::ground::new_tag();
                    q.ev.push((now, Act::Survey { tag, columns: asked_cols(&w.slabs[i], bx, bz) }));
                    w.stage[i] = Step::Asked(tag, now);
                }
                Step::Asked(tag, at) => {
                    let late = now + 0.4 > hit - VL_EASE as f32;
                    if !crate::ground::ready(tag) {
                        if late {
                            vl_fail(q, w, i, now, "not answered");
                        }
                        continue;
                    }
                    let (gs, share) = ground_of(&w.slabs[i], bx, bz, gy);
                    if share < VL_LOADED && !late {
                        // (its chunks may still come: asked again a little later)
                        if now > at + 1.5 {
                            w.stage[i] = Step::Idle;
                        }
                        continue;
                    }
                    let Some((gs, slope)) = gs.filter(|_| share >= VL_LOADED && w.terrain) else {
                        if w.terrain {
                            vl_fail(q, w, i, now, "its land never loaded");
                        } else {
                            w.stage[i] = Step::Failed;
                        }
                        continue;
                    };
                    let seed = w.seed;
                    let s = &mut w.slabs[i];
                    s.set_pose(gs, slope);
                    s.litter(seed);
                    w.todo[i] = s.chunks(bx, bz);
                    q.ev.push((now, Act::Words { index: (VL_BASE + i * VL_W) as u32, words: s.words(0.0) }));
                    let size = (s.s1 - s.s0) * s.wide;
                    #[cfg(not(test))]
                    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("supervolcano: plate {} comes down at {:.0} {:.0} {:.0} at {hit:.1} s", s.rock_id, w.vent[0] + s.foot[0], w.vent[1] + gs, w.vent[2] + s.foot[2]));
                    let at = [w.vent[0] + s.foot[0], w.vent[1] + gs, w.vent[2] + s.foot[2]];
                    super::vc_sound::plate_down(q, hit, at, w.me, size);
                    w.stage[i] = Step::Settled;
                }
                Step::Settled if now >= hit => {
                    if near_player(&w.slabs[i], w.me, w.vent) {
                        vl_fail(q, w, i, now, "the player is there");
                        w.todo[i].clear();
                    } else {
                        w.stage[i] = Step::Building;
                    }
                }
                Step::Building if w.next[i] >= w.todo[i].len() && w.sent[i].get() >= w.made[i] => {
                    q.ev.push((now, Act::Data { index: (VL_BASE + i * VL_W + 7) as u32, value: now.max(1.0) }));
                    w.stage[i] = Step::Done;
                    w.landed += 1;
                    #[cfg(not(test))]
                    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("supervolcano: plate {} in the world {:.1} s after it hit, {} chunks", w.slabs[i].rock_id, now - hit, w.made[i]));
                }
                _ => {}
            }
        }
        // (the reads: each lot of chunks asked when there's room for what it will make)
        let waiting: u32 = (0..w.slabs.len()).map(|i| w.made[i] - w.sent[i].get()).sum();
        let held: usize = w.lots.iter().map(|l| l.chunks.len() - l.next).sum();
        if w.lots.len() < VL_FLIGHT && waiting + (held as u32) < VL_QUEUE {
            // (those the player can see first: the others stay drawn as long as they have to)
            let first = (0..w.slabs.len()).filter(|&i| w.slabs[i].site.near).chain((0..w.slabs.len()).filter(|&i| !w.slabs[i].site.near));
            for i in first.collect::<Vec<usize>>() {
                if w.stage[i] == Step::Building && w.next[i] < w.todo[i].len() {
                    let end = (w.next[i] + VL_LOT).min(w.todo[i].len());
                    let chunks: Vec<(i32, i32)> = w.todo[i][w.next[i]..end].to_vec();
                    w.next[i] = end;
                    let columns: Vec<(i32, i32)> = chunks.iter().flat_map(|c| (0..256).map(move |j| (c.0 + (j & 15), c.1 + (j >> 4)))).collect();
                    let tag = crate::columns::new_tag();
                    crate::meter::spend(40 * columns.len() as u64);
                    q.ev.push((now, Act::Read { tag, columns, below: VC_BELOW, above: 1 }));
                    w.lots.push_back(Lot { slab: i, tag, asked: now, chunks, next: 0, read: None, kinds: Vec::new(), answered: false });
                    break;
                }
            }
        }
        // (what's been read made into blocks, as much as a tick should)
        let seed = w.seed;
        while crate::meter::spent() < VL_TICK {
            let Some(lot) = w.lots.front_mut() else { break };
            if !lot.answered {
                if let Some(a) = crate::columns::take(lot.tag) {
                    lot.kinds = a.palette.iter().map(|n| super::nuke::kind(n)).collect();
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
            crate::trace("plate chunk<");
            let (x0, z0) = lot.chunks[lot.next];
            let i = lot.slab;
            let read = lot.read.as_ref().map(|a| {
                let base = lot.next * 256;
                crate::meter::spend(4_000);
                (0..256).map(|j| column_of(a, base + j, &lot.kinds)).collect::<Vec<Option<Col>>>()
            });
            lot.next += 1;
            let finished = lot.next >= lot.chunks.len();
            if finished {
                w.lots.pop_front();
            }
            crate::trace("plate read");
            let mut b = w.slabs[i].chunk(x0, z0, bx, bz, gy, seed, read.as_deref());
            crate::trace(&format!("plate chunk> {}", b.runs.len()));
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
        q.later(now + 0.05, move |q| vl_tick(q, l, now + 0.05));
    }
}
/// No blocks for plate i: the pass takes it on into the ground.
fn vl_fail(q: &mut Plan, w: &mut Lodge, i: usize, now: f32, why: &str) {
    w.stage[i] = Step::Failed;
    q.ev.push((now, Act::Data { index: (VL_BASE + i * VL_W + 7) as u32, value: -1.0 }));
    #[cfg(not(test))]
    crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("supervolcano: plate {} stays drawn: {why}", w.slabs[i].rock_id));
    #[cfg(test)]
    let _ = why;
}
/// The ground it comes down on, from the query, and how much of what was asked answered.
fn ground_of(s: &Slab, bx: i32, bz: i32, gy: i32) -> (Option<(f64, (f64, f64))>, f64) {
    let cols = asked_cols(s, bx, bz);
    let mut got = 0.0f64;
    let mut pts = Vec::with_capacity(cols.len());
    for &(x, z) in &cols {
        let Some(g) = crate::ground::at(x, z) else { continue };
        got += 1.0;
        pts.push((x, z, f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)));
    }
    crate::meter::spend(160 * cols.len() as u64);
    (s.bed(&pts, bx, bz), got / cols.len().max(1) as f64)
}
/// Whether the player is in or right by the plate as it comes down.
fn near_player(s: &Slab, me: [f64; 3], vent: [f64; 3]) -> bool {
    let p = crate::sdk::game::get_player().map_or(me, |p| [p.x - vent[0], p.y - vent[1], p.z - vent[2]]);
    let mut sp = Vec::new();
    for (a, b) in [(0.0, 0.0), (6.0, 0.0), (-6.0, 0.0), (0.0, 6.0), (0.0, -6.0)] {
        s.spans(p[0] + a, p[2] + b, &mut sp);
        if sp.iter().any(|t| t.y1 > p[1] - 8.0 && t.y0 < p[1] + 8.0) {
            return true;
        }
    }
    false
}
/// The strike stopped with a plate half built: the rest of it goes in, a chunk a stage, on what's known without a read.
fn vl_finish(l: Shared) -> Vec<(f32, Act)> {
    let mut out = Vec::new();
    let more = {
        let mut g = l.borrow_mut();
        let w = &mut *g;
        w.lots.clear();
        let (bx, bz, gy) = (w.vent[0].floor() as i32, w.vent[2].floor() as i32, w.vent[1] as i32);
        for _ in 0..3 {
            let Some(i) = (0..w.slabs.len()).find(|&i| w.stage[i] == Step::Building && w.next[i] < w.todo[i].len()) else { return out };
            let (x0, z0) = w.todo[i][w.next[i]];
            w.next[i] += 1;
            let mut b = w.slabs[i].chunk(x0, z0, bx, bz, gy, w.seed, None);
            b.cleanup = true;
            b.clear_of_player = true;
            out.push((0.0, Act::Blocks(Box::new(b))));
        }
        true
    };
    if more {
        out.push((0.0, Act::Cleanup(Box::new(move || vl_finish(l)))));
    }
    out
}

#[cfg(test)]
impl Lodge {
    /// What the game's stages do, at once: plate i's ground known, its pose settled, its chunks' list made.
    pub(super) fn settle_test(&mut self, i: usize, h: &dyn Fn(i32, i32) -> f64, bx: i32, bz: i32) -> Vec<(i32, i32)> {
        let seed = self.seed;
        let s = &mut self.slabs[i];
        let pts: Vec<(i32, i32, f64)> = asked_cols(s, bx, bz).iter().map(|&(x, z)| (x, z, h(x, z))).collect();
        let (gs, slope) = s.bed(&pts, bx, bz).unwrap();
        s.set_pose(gs, slope);
        s.litter(seed);
        s.chunks(bx, bz)
    }
}

#[cfg(test)]
mod tests {
    use super::super::vc_mount::{VM_FLT, VM_FLY, VM_GW, VM_PLATE, VM_PW, VM_W0, VM_W2, table, vm_burst_h};
    use super::*;
    use std::collections::HashSet;

    const ME: [f64; 3] = [0.0, 5.0, 1000.0];
    fn land(hills: f64) -> (Vec<(usize, Vec<u32>)>, Shared) {
        table::all_lodged(37, ME, &|x, z| hills * (x * 0.013).sin() * (z * 0.017).cos(), &|x, z| Some(table::preview_col(x, z, hills)))
    }
    /// The pass at the moment it hands over: where plate `i` (of the ten) lies, its own words only.
    struct Drawn<'a> {
        i: usize,
        rest: [f64; 3],
        c: [f64; 3],
        q: [f64; 4],
        th: f64,
        w0: &'a [u32],
        w2: &'a [u32],
    }
    fn rot(q: [f64; 4], v: [f64; 3]) -> [f64; 3] {
        let u = [q[0], q[1], q[2]];
        let t = cross(u, v);
        let t = [t[0] + q[3] * v[0], t[1] + q[3] * v[1], t[2] + q[3] * v[2]];
        let t2 = cross(u, t);
        [v[0] + 2.0 * t2[0], v[1] + 2.0 * t2[1], v[2] + 2.0 * t2[2]]
    }
    fn drawn<'a>(all: &'a [(usize, Vec<u32>)], n: usize) -> Drawn<'a> {
        let get = |k: usize| all.iter().rev().find(|t| t.0 == k).unwrap().1.as_slice();
        let (pl, fl, lw, map) = (get(VM_PLATE), get(VM_FLT), get(VL_BASE), get(VL_MAP));
        let f = |t: &[u32], j: usize| f64::from(f32::from_bits(t[j]));
        let i = (0..VM_FLY).find(|&k| map[k] == n as u32 + 1).unwrap();
        let b = i * VM_PW;
        let lb = n * VL_W;
        let hb = vm_burst_h();
        let rest = [f(pl, b), f(pl, b + 2) + f(pl, b + 3) * hb, f(pl, b + 1)];
        let (tr, hit, tau, g) = (f(pl, b + 8), f(fl, i * 4 + 2), f(fl, i * 4), f(fl, i * 4 + 1));
        let (v, s) = ([f(pl, b + 9), f(pl, b + 10), f(pl, b + 11)], hit - VL_BRK);
        let eh = VL_TH * (1.0 - (-s / VL_TH).exp());
        let a = hit - tr - s;
        let mut c = [rest[0] + v[0] * (a + eh), rest[1] + (v[1] - 0.5 * VL_G * a) * a, rest[2] + v[2] * (a + eh)];
        let vy = v[1] - VL_G * a;
        c[1] += (vy + g * tau) * tau * (1.0 - (-s / tau).exp()) - g * tau * s;
        let c = [c[0] + f(lw, lb + 4), c[1] + f(lw, lb + 5), c[2] + f(lw, lb + 6)];
        let q = [f(lw, lb), f(lw, lb + 1), f(lw, lb + 2), f(lw, lb + 3)];
        Drawn { i, rest, c, q, th: f(pl, b + 7), w0: get(VM_W0), w2: get(VM_W2) }
    }
    impl Drawn<'_> {
        fn own(&self, g: (usize, usize)) -> bool {
            (self.w2[g.1 * VM_GW + g.0] & 255) as usize == self.i
        }
        /// vm_top: its land's top at (x, z) of the mount, from its own columns.
        fn top(&self, x: f32, z: f32) -> Option<f32> {
            let (gx, gz) = (((x + 480.0) / 4.0).clamp(0.0, 239.999), ((z + 480.0) / 4.0).clamp(0.0, 239.999));
            let (ci, ck) = (gx as usize, gz as usize);
            let (u, v) = (gx - ci as f32, gz - ck as f32);
            let hb = vm_burst_h() as f32;
            let (mut s, mut k) = (0.0, 0.0);
            for (a, b, m) in [(0, 0, (1.0 - u) * (1.0 - v)), (1, 0, u * (1.0 - v)), (0, 1, (1.0 - u) * v), (1, 1, u * v)] {
                if self.own((ci + a, ck + b)) {
                    let w = self.w0[(ck + b) * VM_GW + ci + a];
                    let land = (w & 0x7ff) as f32 * 0.5 - 512.0;
                    let p = ((w >> 11) & 0x7ff) as f32 * (1.6 / 2047.0) - 0.25;
                    s += (land + p * hb) * m;
                    k += m;
                }
            }
            (k > 1e-4).then_some(s / k)
        }
        /// vm_in_plate at the point (from the vent) of the world, `grow` blocks' grace.
        fn inside(&self, w: [f64; 3], grow: f32) -> bool {
            let d = [w[0] - self.c[0], w[1] - self.c[1], w[2] - self.c[2]];
            let lp = rot([-self.q[0], -self.q[1], -self.q[2], self.q[3]], d);
            let (x, z) = ((lp[0] + self.rest[0]) as f32, (lp[2] + self.rest[2]) as f32);
            let (jx, jz) = ((z * 0.43 + x * 0.11).sin() * 0.8, (x * 0.47 - z * 0.13).sin() * 0.8);
            let g = (((x + 480.0) / 4.0 + 0.5 + jx).clamp(0.0, 240.0) as usize, ((z + 480.0) / 4.0 + 0.5 + jz).clamp(0.0, 240.0) as usize);
            if !self.own(g) {
                return false;
            }
            let y = (lp[1] + self.rest[1]) as f32;
            let Some(top) = self.top(x, z) else { return false };
            let th = (self.th * vl_thk(f64::from(x), f64::from(z))) as f32;
            y <= top + grow && y >= top - th - grow
        }
    }
    fn blocks_of(s: &Slab) -> HashSet<(i32, i32, i32)> {
        let mut set = HashSet::new();
        for (x0, z0) in s.chunks(0, 0) {
            let b = s.chunk(x0, z0, 0, 0, 65, 37, None);
            let e = b.edit();
            for r in &e.runs {
                if r.surface.is_none() && !e.palette[r.block as usize].ends_with(":air") {
                    for y in r.y..r.y + r.height as i32 {
                        set.insert((r.x, y, r.z));
                    }
                }
            }
        }
        set
    }
    /// At the moment it hands over the blocks are where the pass draws the plate: none of them outside what it draws, a
    /// block's grace for the two ways of breaking an edge, and no hole in what it draws. (The vent at 0.5, 0.5, its ground
    /// at Y 65.)
    #[test]
    fn a_lodged_plate_is_where_the_pass_draws_it() {
        for hills in [0.0, 30.0] {
            let (all, l) = land(hills);
            let l = l.borrow();
            for n in 0..l.slabs.len() {
                let (d, s) = (drawn(&all, n), &l.slabs[n]);
                let set = blocks_of(s);
                assert!(set.len() > 150_000, "plate {n}: {} blocks", set.len());
                let (mut out, mut total) = (0, 0);
                for (j, &(x, y, z)) in set.iter().enumerate() {
                    if j % 7 == 0 {
                        total += 1;
                        // (the two ways of breaking an edge a block or two apart)
                        let p = [f64::from(x), f64::from(y) + 0.5 - 65.0, f64::from(z)];
                        out += usize::from(![[0.0, 0.0], [2.5, 0.0], [-2.5, 0.0], [0.0, 2.5], [0.0, -2.5]].iter().any(|o| d.inside([p[0] + o[0], p[1], p[2] + o[1]], 2.5)));
                    }
                }
                assert!((out as f64) < 0.025 * total as f64, "plate {n}: {out} of {total} blocks outside what the pass draws");
                // (and every block of the world inside what the pass draws, well in from its faces and edges, is there)
                let (mut holes, mut inner) = (0, 0);
                let c = s.foot;
                for x in (c[0] as i32 - 150..c[0] as i32 + 150).step_by(5) {
                    for z in (c[2] as i32 - 150..c[2] as i32 + 150).step_by(5) {
                        for y in (-60..240).step_by(3) {
                            let w = [f64::from(x), f64::from(y) + 0.5, f64::from(z)];
                            if [[0.0, 0.0, 0.0], [5.0, 0.0, 0.0], [-5.0, 0.0, 0.0], [0.0, 0.0, 5.0], [0.0, 0.0, -5.0], [0.0, 8.0, 0.0], [0.0, -5.0, 0.0]].iter().all(|o| d.inside([w[0] + o[0], w[1] + o[1], w[2] + o[2]], 0.0)) {
                                inner += 1;
                                holes += usize::from(!set.contains(&(x, y + 65, z)));
                            }
                        }
                    }
                }
                assert!(inner > 40, "plate {n}: {inner}");
                assert!((holes as f64) < 0.04 * inner as f64, "plate {n}: {holes} holes of {inner}");
            }
        }
    }
    #[test]
    fn they_keep_off_the_player_the_ash_and_each_other() {
        for seed in [37, 5, 1234] {
            for me in [[0.0, 5.0, 1000.0], [700.0, 5.0, -800.0], [-1300.0, 20.0, 300.0]] {
                let sites = vl_sites(seed, me);
                assert_eq!(sites.len(), VL_N);
                let phi = me[2].atan2(me[0]);
                for (i, s) in sites.iter().enumerate() {
                    let (r, d) = (s.x.hypot(s.z), (s.x - me[0]).hypot(s.z - me[2]));
                    assert!((VL_R0 - 1.0..VL_R1 + 30.0).contains(&r), "seed {seed} site {i}: {r} from the vent");
                    assert!(d >= VL_ME0 - 1.0, "seed {seed} site {i}: {d} from the player");
                    assert!((s.dir.0.hypot(s.dir.1) - 1.0).abs() < 1e-9);
                    if s.near {
                        assert!(i < VL_NEAR && (d < VL_ME1 + 10.0 || me[0].hypot(me[2]) > 1100.0), "seed {seed} near site {i}: {d} from the player");
                    } else {
                        let off = ((s.z.atan2(s.x) - phi).rem_euclid(TAU) - PI).abs();
                        assert!(off < 2.3, "seed {seed} far site {i} on the player's side");
                    }
                    for t in &sites[..i] {
                        assert!((s.x - t.x).hypot(s.z - t.z) > 110.0, "seed {seed}: sites {i} and another");
                    }
                }
            }
        }
        // (the plates themselves: all of what stands over the ground at least 150 from the player)
        let (_, l) = land(0.0);
        for s in &l.borrow().slabs {
            for b in blocks_of(s).iter().step_by(11) {
                let d = (f64::from(b.0) - ME[0]).hypot(f64::from(b.2) - ME[2]);
                assert!(d > 150.0, "rock {}: a block {d} from the player", s.rock_id);
            }
        }
    }
    /// Lying low with its low end in the ground, nowhere near standing up; and it isn't a sheet.
    #[test]
    fn it_stands_as_it_should() {
        let (_, l) = land(0.0);
        for s in &l.borrow().slabs {
            let up = s.pose.world([0.0, 0.0, 0.0])[1] - s.foot[1];
            let n = norm([-s.plane.0, 1.0, -s.plane.1]);
            let tilt = dot(s.pose.r[1], n).clamp(-1.0, 1.0).acos().to_degrees();
            assert!((VL_LOW - 1.0..VL_STEEP + 17.0).contains(&tilt), "rock {}: {tilt} degrees", s.rock_id);
            assert!(up > 2.0, "rock {}: its middle {up} over the ground", s.rock_id);
            let set = blocks_of(s);
            let ys: Vec<i32> = set.iter().map(|b| b.1).collect();
            let (lo, hi) = (*ys.iter().min().unwrap(), *ys.iter().max().unwrap());
            assert!((25..85).contains(&(hi - 65)), "rock {}: it stands {} high", s.rock_id, hi - 65);
            assert!(lo < 65 - 10 && hi < 318, "rock {}: {lo} to {hi}", s.rock_id);
            let under = set.iter().filter(|b| b.1 < 65).count() as f64 / set.len() as f64;
            assert!((0.02..0.6).contains(&under), "rock {}: {under} of it under the ground", s.rock_id);
        }
    }
}

/// In the tests: the word that tells the pass plate i is in the world.
#[cfg(test)]
pub(crate) fn vl_gone_word(i: usize) -> usize {
    VL_BASE + i * VL_W + 7
}
