//! The sinkhole's plan: no beam and nothing from the sky. The land round the target trembles, birds go up, hairline
//! cracks race out over it; a patch in the middle gives a few blocks with a crack (real blocks, moved down whole with
//! what stands on them); then the ground caves in from the middle out, ring by ring, each ring broken into slabs that
//! strain, tilt and drop into a pit down to bedrock, the dust boiling up out of it and rolling out over the land.
//!
//! What it leaves is real blocks: a pit about 225 across (its edge wandering) down to bedrock, its walls sheer and
//! jagged in strata bands (ledges with rubble on them, overhangs with roots hanging from them, the world's own strata,
//! caves and ores laid open), a heap of rubble at its foot, the water and lava the walls cut through sealed in.
//!
//! shaders/sinkhole.wgsl draws the same slabs, cut the same way (`ShGeo`, handed to it with render.set-data as
//! `sh_table`), and lets each go when the mod has dug the land under it: keep the SH_* and the table in step.
use super::{Act, Blocks, Col, Plan, Rng, Target, bedrock_top, falloff, mh, pk_cells, pk_load_rows, sky_top, sound_from, tidy, vnoise};
use super::sh_land::{self, Land, READ_ABOVE, READ_BELOW, READ_ROWS, SH_GRID, SH_GW, SH_MAT, Shared};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The pit's mean radius at the top (its edge wanders about 15% either way, `rim`).
pub(super) const SH_R: f64 = 112.0;
/// The first give (the middle drops 4 blocks), the sag after it (3 more), and the collapse setting out from the middle.
pub(super) const SH_GIVE: f32 = 6.0;
pub(super) const SH_SAG: f32 = 7.3;
pub(super) const SH_C0: f32 = 8.6;
/// A slab is drawn by the pass from SH_LEAD before it lets go (straining in place); the land under it is dug
/// SH_DIG_AHEAD before it lets go, under it (shaders/sinkhole.wgsl's SH_LEAD, SH_FALL).
#[cfg(test)]
const SH_LEAD: f32 = 0.45;
const SH_DIG_AHEAD: f32 = 0.1;
/// As each slab goes, the land under it is dug SH_TOP_D deep (and cleared SH_ABOVE up, and from its own ground
/// SH_SURF_LO..SH_SURF_HI); the rest, down to bedrock, from SH_DEEP0 on, at SH_DEEP_RATE blocks a second.
const SH_TOP_D: i32 = 25;
const SH_ABOVE: i32 = 36;
const SH_SURF_LO: i32 = -20;
const SH_SURF_HI: i32 = 28;
pub(super) const SH_DEEP0: f32 = 16.0;
const SH_DEEP_RATE: f64 = 1_000_000.0;
/// The walls: strata bands SH_BAND tall under the top one (which is the rim itself, SH_TOP_BAND deep), each cut back or
/// left standing out as a ledge by up to about SH_JAG blocks.
const SH_BAND: i32 = 7;
const SH_TOP_BAND: i32 = 5;
/// How far in from and out past the rim a column can be cut at some depth (the bands' reach), for the walls' columns.
const SH_IN: f64 = 13.0;
const SH_OUT: f64 = 6.5;
/// How far the bands just under the rim's are cut back past it at most (an overhang that far, no further).
const SH_OVERHANG: f64 = 2.5;
/// The chunks out to SH_LOAD kept loaded while it works.
const SH_LOAD: f64 = SH_R * 1.2 + 18.0;
/// Mobs and dropped items within SH_KILL killed as it goes.
const SH_KILL: i32 = 140;

// ---- what the pass reads (render.set-data): see shaders/sinkhole.wgsl ----
/// Words 0..8: the slabs' count, the rings' count, the rim's four phases; from SH_RG the rings (SH_RW words each: inner
/// radius, wobble phase, sectors, first sector's angle, first slab); from SH_WF the waterfalls (the count, then four
/// words each from SH_WF + 4: angle, half-width in radians, the water's top over the target's ground, when it pours); from
/// SH_SB the slabs, SH_SW words each: th0, th1, rin0, rin1, rout0, rout1, when it lets go, its ground's height over
/// the target's and its slope along x and z (from `sh_heights`), thick, g, alpha, twist, drift, whether its land was read
/// (1), grow_in, grow_out, and once its land is read (`sh_land_done`) the columns it covers in the land's square (lowest
/// x and z, highest x and z) and how low its underside and how high what stands on it reach, from the target's ground
/// (see `ShSlab`). From SH_MAT the materials, and from SH_GRID the land's columns (sh_land.rs).
pub(super) const SH_RG: usize = 8;
pub(super) const SH_RW: usize = 5;
pub(super) const SH_MAXR: usize = 11;
pub(super) const SH_WF: usize = 64;
pub(super) const SH_NWF: usize = 6;
pub(super) const SH_SB: usize = 96;
pub(super) const SH_SW: usize = 24;

#[derive(Clone, Copy, Debug)]
pub(super) struct ShRing {
    /// Its inner radius (as the rim's mean is SH_R), its wobble's phase, its sectors, the first sector's angle, its first slab.
    pub b: f64,
    pub q: f64,
    pub n: usize,
    pub th0: f64,
    pub off: usize,
}
/// A slab of the land: sector [th0, th1] of its ring, its corners' radii, when it lets go, and how it falls.
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct ShSlab {
    pub ring: usize,
    pub th0: f64,
    pub th1: f64,
    pub rin0: f64,
    pub rin1: f64,
    pub rout0: f64,
    pub rout1: f64,
    pub t: f32,
    pub thick: f64,
    pub g: f64,
    pub alpha: f64,
    pub twist: f64,
    pub drift: f64,
}
impl ShSlab {
    /// Its corners (x, z from the middle): inner at th0, inner at th1, outer at th1, outer at th0.
    pub fn corners(&self) -> [(f64, f64); 4] {
        let rin0 = self.rin0.max(0.6);
        let rin1 = self.rin1.max(0.6);
        [
            (rin0 * self.th0.cos(), rin0 * self.th0.sin()),
            (rin1 * self.th1.cos(), rin1 * self.th1.sin()),
            (self.rout1 * self.th1.cos(), self.rout1 * self.th1.sin()),
            (self.rout0 * self.th0.cos(), self.rout0 * self.th0.sin()),
        ]
    }
    pub fn centroid(&self) -> (f64, f64) {
        let c = self.corners();
        (c.iter().map(|p| p.0).sum::<f64>() / 4.0, c.iter().map(|p| p.1).sum::<f64>() / 4.0)
    }
}

/// The sinkhole's layout for a seed: the rim, the rings and the slabs they are cut into.
pub(super) struct ShGeo {
    pub seed: u32,
    pub ph: [f64; 4],
    pub rings: Vec<ShRing>,
    pub slabs: Vec<ShSlab>,
}

/// When the collapse reaches `r` out: the middle first, slowly, a stall while the ring round it holds, then the rest in
/// a rush that quickens as it goes.
pub(super) fn sh_front(r: f64) -> f32 {
    if r < 30.0 {
        SH_C0 + (0.9 * r / 30.0) as f32
    } else {
        SH_C0 + 2.0 + (4.4 * ((r - 30.0) / (SH_R - 30.0)).clamp(0.0, 1.4).powf(0.75)) as f32
    }
}

thread_local! {
    /// The last layout worked out (the plan and the pass's table both want it as the strike starts: once is enough).
    static GEO: std::cell::RefCell<Option<(u32, Rc<ShGeo>)>> = const { std::cell::RefCell::new(None) };
}

impl ShGeo {
    /// The layout for `seed`, worked out once.
    pub fn shared(seed: f32) -> Rc<ShGeo> {
        let key = seed.to_bits();
        if let Some(g) = GEO.with(|c| c.borrow().as_ref().filter(|(k, _)| *k == key).map(|(_, g)| g.clone())) {
            return g;
        }
        let g = Rc::new(ShGeo::new(seed));
        GEO.with(|c| *c.borrow_mut() = Some((key, g.clone())));
        g
    }
    pub fn new(seed: f32) -> Self {
        let s = seed as u32;
        let h = |i: u32, k: u32| mh(i, s, k);
        let ph = [0, 1, 2, 3].map(|i| h(i, 0x700) * TAU);
        let mut b = vec![0.0, 15.0 + 3.0 * h(0, 0x701)];
        loop {
            let last = *b.last().unwrap_or(&0.0);
            let next = last + 11.0 + 0.055 * last + 4.0 * h(b.len() as u32, 0x701);
            if next > SH_R - 8.0 || b.len() >= SH_MAXR {
                break;
            }
            b.push(next);
        }
        let mut geo = ShGeo { seed: s, ph, rings: Vec::new(), slabs: Vec::new() };
        let mut off = 0;
        for (j, &bj) in b.iter().enumerate() {
            let outer = b.get(j + 1).copied().unwrap_or(SH_R);
            let mid = 0.5 * (bj + outer);
            let n = if j == 0 { 5 } else { ((TAU * mid) / (15.0 + 4.0 * h(j as u32, 0x702))).round().max(4.0) as usize };
            geo.rings.push(ShRing { b: bj, q: h(j as u32, 0x704) * TAU, n, th0: h(j as u32, 0x703) * TAU, off });
            off += n;
        }
        for j in 0..geo.rings.len() {
            let n = geo.rings[j].n;
            for m in 0..n {
                let (th0, th1) = (geo.edge(j, m), geo.edge(j, m + 1));
                let am = 0.5 * (th0 + th1);
                let rm = 0.5 * (geo.ring_r(j, am) + geo.ring_r(j + 1, am));
                let k = (geo.rings[j].off + m) as u32;
                let hh = |c: u32| h(k, c);
                let mut t = if j == 0 {
                    SH_C0 + 0.13 * m as f32
                } else {
                    // (jittered, the front running ahead and lagging round the ring, and now and then one holding on)
                    let stall = if hh(0x711) > 0.9 { 0.5 } else { 0.0 };
                    sh_front(rm) + (0.32 * (2.0 * hh(0x712) - 1.0) + 0.4 * (2.0 * am + ph[0]).sin() * (rm / SH_R) + stall) as f32
                };
                t = t.max(SH_C0 + 0.05);
                geo.slabs.push(ShSlab {
                    ring: j,
                    th0,
                    th1,
                    rin0: geo.ring_r(j, th0),
                    rin1: geo.ring_r(j, th1),
                    rout0: geo.ring_r(j + 1, th0),
                    rout1: geo.ring_r(j + 1, th1),
                    t,
                    thick: 10.0 + 9.0 * hh(0x713),
                    g: 26.0 + 8.0 * hh(0x714),
                    alpha: 0.6 + 1.2 * hh(0x715),
                    twist: (hh(0x716) - 0.5) * 0.5,
                    drift: 1.5 + 2.0 * hh(0x717),
                });
            }
        }
        geo
    }
    /// How far slab k's inner and outer edges bulge past the chords between its corners (the pass grows its shape by
    /// that): sampled along them.
    pub fn grows(&self, k: usize) -> (f64, f64) {
        let sl = self.slabs[k];
        let j = sl.ring;
        let c = sl.corners();
        let (mx, mz) = sl.centroid();
        let past = |a: (f64, f64), b: (f64, f64), j: usize| {
            let (ex, ez) = (b.0 - a.0, b.1 - a.1);
            let l = ex.hypot(ez).max(1e-9);
            let (mut nx, mut nz) = (ez / l, -ex / l);
            if nx * (mx - a.0) + nz * (mz - a.1) > 0.0 {
                nx = -nx;
                nz = -nz;
            }
            let ns = if j <= 1 { 16 } else { 6 };
            (1..ns)
                .map(|i| {
                    let th = sl.th0 + (sl.th1 - sl.th0) * f64::from(i) / f64::from(ns);
                    let r = self.ring_r(j, th).max(0.6);
                    nx * (r * th.cos() - a.0) + nz * (r * th.sin() - a.1)
                })
                .fold(0.0, f64::max)
        };
        (past(c[0], c[1], j), past(c[2], c[3], j + 1))
    }
    /// The rim: how far out the pit's top edge is at angle `a`.
    pub fn rim(&self, a: f64) -> f64 {
        let p = self.ph;
        SH_R * (1.0 + 0.07 * (3.0 * a + p[0]).sin() + 0.04 * (5.0 * a + p[1]).sin() + 0.025 * (11.0 * a + p[2]).sin() + 0.012 * (23.0 * a + p[3]).sin())
    }
    /// Ring j's inner edge at angle `a` (the last ring's outer edge is the rim).
    pub fn ring_r(&self, j: usize, a: f64) -> f64 {
        self.ring_r_on(j, a, self.rim(a))
    }
    /// As `ring_r`, the rim there given.
    fn ring_r_on(&self, j: usize, a: f64, rim: f64) -> f64 {
        if j == 0 {
            0.0
        } else if j >= self.rings.len() {
            rim
        } else {
            let r = &self.rings[j];
            r.b * rim / SH_R + 2.0 * (7.0 * a + r.q).sin()
        }
    }
    fn jit(&self, j: usize, m: usize) -> f64 {
        0.35 * (mh((m % self.rings[j].n) as u32, self.seed, 0x710 + j as u32) - 0.5)
    }
    /// The angle of edge m of ring j's sectors (edge n is edge 0 a turn on).
    pub fn edge(&self, j: usize, m: usize) -> f64 {
        let r = &self.rings[j];
        r.th0 + TAU * (m as f64 + self.jit(j, m)) / r.n as f64
    }
    /// The slab the land at (dx, dz) from the middle is part of (none: outside the rim).
    pub fn slab_at(&self, dx: f64, dz: f64) -> Option<usize> {
        let r = dx.hypot(dz);
        let a = dz.atan2(dx);
        self.slab_on(r, a, self.rim(a))
    }
    /// As `slab_at`, at radius r and angle a, the rim there given.
    fn slab_on(&self, r: f64, a: f64, rim: f64) -> Option<usize> {
        if r >= rim {
            return None;
        }
        // (the ring: from a guess by the mean radii, the wobbles only a few blocks)
        let mut j = 0;
        while j + 1 < self.rings.len() && r * SH_R / rim >= self.rings[j + 1].b + 3.0 {
            j += 1;
        }
        while j > 0 && r < self.ring_r_on(j, a, rim) {
            j -= 1;
        }
        while j + 1 < self.rings.len() && r >= self.ring_r_on(j + 1, a, rim) {
            j += 1;
        }
        let ring = &self.rings[j];
        let n = ring.n;
        let u = (a - ring.th0).rem_euclid(TAU) / TAU * n as f64;
        let m0 = (u.floor() as usize).min(n - 1);
        let m = if u < m0 as f64 + self.jit(j, m0) {
            (m0 + n - 1) % n
        } else if u >= (m0 + 1) as f64 + self.jit(j, m0 + 1) {
            (m0 + 1) % n
        } else {
            m0
        };
        Some(ring.off + m)
    }
    /// The strata band a depth `y` (under the target's ground `by`) is in, at a column with band shift `s`: 0 the
    /// rim's own, then SH_BAND tall each; and band k's lowest and highest y.
    fn band_of(by: i32, s: i32, y: i32) -> usize {
        if y > by - SH_TOP_BAND - 1 { 0 } else { (((by - SH_TOP_BAND - 1 - y + s) / SH_BAND) + 1) as usize }
    }
    fn band_span(by: i32, s: i32, k: usize) -> (i32, i32) {
        if k == 0 {
            return (by - SH_TOP_BAND, i32::MAX);
        }
        let hi = by - SH_TOP_BAND - 1 - (k as i32 - 1) * SH_BAND + if k == 1 { 0 } else { -s };
        let lo = by - SH_TOP_BAND - k as i32 * SH_BAND - s;
        (lo, hi)
    }
    /// A column's band shift (the strata dip a little round the pit).
    fn shift(&self, ca: f64, sa: f64) -> i32 {
        (3.0 * vnoise(ca * SH_R + 1000.0, sa * SH_R + 1000.0, 25.0, self.seed ^ 0x730)).round() as i32
    }
    /// How far out band k's wall is at the angle (ca, sa), y `mid` the band's middle: the rim, cut back or standing out.
    fn band_r(&self, rim: f64, ca: f64, sa: f64, k: usize, by: i32, mid: i32) -> f64 {
        if k == 0 {
            return rim;
        }
        let (x, z) = (ca * SH_R + 1000.0, sa * SH_R + 1000.0);
        let kk = k as u32;
        let j = 7.0 * (vnoise(x, z, 10.0, self.seed ^ (0x720 + kk)) - 0.45) + 3.0 * (vnoise(x, z, 3.5, self.seed ^ (0x760 + kk)) - 0.5);
        // (the bands under the rim's own cut back no more than SH_OVERHANG past it: the land over them is left standing
        // on what is under it, never out over the pit)
        let j = if k <= 2 { j.min(SH_OVERHANG) } else { j };
        rim + j - 0.04 * f64::from((by - mid).max(0))
    }
}

/// What the pass reads of the sinkhole (render.set-data, on the tick after it starts: `Act::Table`): the rim, the rings and the slabs; the
/// slabs' ground and the waterfalls come later, as the world says where the ground is (`sh_heights`).
pub(super) fn sh_table(seed: f32) -> Vec<u32> {
    let g = ShGeo::shared(seed);
    let mut w = vec![0.0f32; SH_MAT];
    w[0] = g.slabs.len() as f32;
    w[1] = g.rings.len() as f32;
    for i in 0..4 {
        w[2 + i] = g.ph[i] as f32;
    }
    for (j, r) in g.rings.iter().enumerate() {
        let b = SH_RG + j * SH_RW;
        w[b] = r.b as f32;
        w[b + 1] = r.q as f32;
        w[b + 2] = r.n as f32;
        w[b + 3] = r.th0 as f32;
        w[b + 4] = r.off as f32;
    }
    for (k, s) in g.slabs.iter().enumerate() {
        let b = SH_SB + k * SH_SW;
        let (gi, go) = g.grows(k);
        let v = [s.th0, s.th1, s.rin0, s.rin1, s.rout0, s.rout1, f64::from(s.t), 0.0, 0.0, 0.0, s.thick, s.g, s.alpha, s.twist, s.drift, 0.0, gi, go];
        for (i, x) in v.iter().enumerate() {
            w[b + i] = *x as f32;
        }
    }
    let mut out: Vec<u32> = w.into_iter().map(f32::to_bits).collect();
    out.extend(sh_land::mat_words());
    out
}

/// The sinkhole. Tremors, birds going up and cracks racing out over the land; a patch in the middle gives, then sags;
/// then the collapse, from the middle out, slab by slab, into a pit down to bedrock, with the dust rolling out of it and
/// the rocks still falling a long time after.
pub(super) fn sinkhole_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let geo = ShGeo::shared(shader_seed);
    // the land as it really is, read from the world as it starts (whether or not the terrain goes: the pass draws the
    // slabs with it either way), and worked out a few thousand columns a tick
    let land: Shared = Rc::new(RefCell::new(Land::new(geo.slabs.len(), if terrain { 7 } else { 0 })));
    {
        let parts = SH_GW.div_ceil(READ_ROWS);
        let tags: Rc<Vec<u32>> = Rc::new((0..parts).map(|_| crate::columns::new_tag()).collect());
        for part in 0..parts {
            let (geo, tags) = (geo.clone(), tags.clone());
            let t = 0.1 + 0.05 * part as f32;
            p.later(t, move |q| {
                let columns = sh_land::read_columns(&geo, q.bx, q.bz, part * READ_ROWS, (part + 1) * READ_ROWS);
                q.ev.push((t, Act::Read { tag: tags[part], columns, below: READ_BELOW, above: READ_ABOVE }));
            });
        }
        let (geo, land) = (geo.clone(), land.clone());
        p.later(0.3, move |q| sh_land_step(q, geo, land, tags, 0, 0, 0.3, 0));
    }
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let late = |x: f64, y: f64, z: f64| (((x - me[0]).powi(2) + (y - me[1]).powi(2) + (z - me[2]).powi(2)).sqrt() / 343.0) as f32;
    let (lt, dist) = sound_from([cx, gy, cz], me);
    let fo = falloff(dist).max(0.35);

    // ---- unease: a rumble felt more than heard, tremors that come and go, ground groaning and cracking round it ----
    p.at(0.2, bar("SEISMIC WARNING: TREMORS UNDER THE TARGET", laser.color));
    p.csound(lt, "rumble", 10.0, 1.0);
    let mut tk = 0.3f32;
    while tk < SH_C0 {
        let u = tk / SH_C0;
        let s = (0.025 + 0.09 * u * u) * p.rng.uniform(0.5, 1.4) as f32;
        let d = p.rng.uniform(0.4, 1.1) as f32;
        p.shake(tk + lt, s * fo, d);
        tk += p.rng.uniform(0.25, 0.9) as f32 * (1.2 - 0.6 * u);
    }
    // (groans and cracks out over the land, each heard from where it is, late by how far that is)
    let mut sounds: Vec<(f32, &str, f64, f64, f32)> = Vec::new();
    let mut tg = 1.1f32;
    let mut take = 0;
    while tg < 8.2 {
        let (a, r) = (p.rng.uniform(0.0, TAU), p.rng.uniform(20.0, SH_R * 1.1));
        take = (take + 1 + p.rng.int(0, 1) as usize) % 3;
        sounds.push((tg, ["groan1", "groan2", "groan3"][take], a, r, p.rng.uniform(0.85, 1.12) as f32));
        tg += p.rng.uniform(0.7, 1.6) as f32;
    }
    // (the cracks racing out in spurts, a crack heard for each, where its front got to; and one more as it stalls)
    let spurts = sh_spurts(geo.seed);
    for (i, &(t, r)) in spurts.iter().enumerate() {
        let a = mh(i as u32, geo.seed, 0x7c1) * TAU;
        let r = r.min(SH_R * 1.05);
        sounds.push((t, ["crack1", "crack2", "crack3"][i % 3], a, r, (0.85 + 0.3 * mh(i as u32, geo.seed, 0x7c2)) as f32));
        if i % 2 == 1 {
            sounds.push((t + SH_SPURT, ["crack2", "crack3", "crack1"][i % 3], a + 1.9, r * 0.8, 1.1));
        }
    }
    for (t, name, a, r, pitch) in sounds {
        let (x, z) = (cx + a.cos() * r, cz + a.sin() * r);
        p.at(t + late(x, gy, z), format!("playsound orbital:sinkhole.{name} block @a {x:.1} {gy} {z:.1} 4 {pitch:.2} 0.9"));
    }
    p.at(3.6, bar("SEISMIC WARNING: THE GROUND IS GIVING WAY", "red"));
    // (each spurt of the cracks puffing dust up out of them where it ran, and loose bits crumbling in)
    for (i, &(t, r)) in spurts.iter().enumerate() {
        let r0 = if i == 0 { 0.0 } else { spurts[i - 1].1 };
        let (geo, land) = (geo.clone(), land.clone());
        p.later(t - 0.1, move |q| sh_spurt_fx(q, &geo, &land, i, t, r0, r));
    }

    // ---- the first give: a crack, the middle drops, dust puffs up; then it sags further ----------------------------
    p.at(SH_GIVE + lt - 0.02, format!("playsound orbital:sinkhole.give block @a {cx:.1} {gy} {cz:.1} 6 1.0 1.0"));
    p.shake(SH_GIVE + lt, 0.42 * fo, 1.2);
    p.at(SH_SAG + lt, format!("playsound orbital:sinkhole.crack2 block @a {cx:.1} {gy} {cz:.1} 6 0.8 1.0"));
    p.shake(SH_SAG + lt, 0.3 * fo, 1.0);
    for (t, n) in [(SH_GIVE, 260), (SH_SAG, 180)] {
        p.at(t + 0.05, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {cx:.1} {:.1} {cz:.1} 9 1 9 0.3 {n} force"#, gy - 3.0));
        p.at(t + 0.1, format!("particle minecraft:campfire_cosy_smoke {cx:.1} {:.1} {cz:.1} 10 0.5 10 0.01 {} force", gy - 2.0, n / 4));
    }

    // ---- the collapse: a deep boom as the middle goes, the grinding roar of the rest going, the rim's slabs heard
    // cracking off one by one; the land shaking under it ---------------------------------------------------------
    p.at(SH_C0, bar("COLLAPSE", "white"));
    // (the boom 0.6 s into its sound: the strain before it)
    p.csound(SH_C0 - 0.6 + lt, "collapse", 10.0, 1.0);
    p.csound(SH_C0 + 1.2 + lt, "rockfall", 10.0, 1.0);
    p.shake(SH_C0 + lt, 0.9 * fo, 2.5);
    let mut ts = SH_C0 + 0.6;
    while ts < 16.0 {
        let (s, d) = (p.rng.uniform(0.12, 0.3) as f32, p.rng.uniform(0.5, 1.2) as f32);
        p.shake(ts + lt, s * fo, d);
        ts += p.rng.uniform(0.3, 0.8) as f32;
    }
    // (each slab's crack as it lets go and the dirt it throws up: worked out with the slab, on a stage of its own)
    // the pass's table, worked out on the tick after it fires (too much for the tick it fires in, with the plan)
    {
        let seed = shader_seed;
        p.later(0.05, move |q| q.ev.push((0.05, Act::Table(sh_table(seed)))));
    }
    let mut order: Vec<usize> = (0..geo.slabs.len()).collect();
    order.sort_by(|a, b| geo.slabs[*a].t.total_cmp(&geo.slabs[*b].t));
    let mut at: Vec<f32> = order.iter().map(|&k| geo.slabs[k].t - SH_DIG_AHEAD - 2.2).collect();
    for i in (0..at.len().saturating_sub(1)).rev() {
        at[i] = at[i].min(at[i + 1] - 0.05);
    }
    // the slabs, a stage each, well ahead (spaced a tick apart, the latest first): with the terrain on, the land under
    // each dug as it lets go
    let sky = sky_top(dimension);
    for (k, t) in order.into_iter().zip(at) {
        let geo = geo.clone();
        let land = land.clone();
        p.later(t.max(0.5), move |q| {
            sh_slab_fx(q, &geo, &land, k, me);
            if terrain {
                sh_top(q, &geo, &land, k, sky);
            }
        });
    }
    p.at(16.5, bar("SINKHOLE", laser.color));
    // ---- the roar dying into an echoing near-silence: pebbles trickling down the walls ------------------------------
    p.csound(17.5 + lt, "trickle", 10.0, 1.0);
    let mut ta = 16.5f32;
    for _ in 0..10 {
        // (aftershocks: the walls settling)
        let s = p.rng.uniform(0.03, 0.09) as f32;
        p.shake(ta + lt, s * fo, 0.8);
        ta += p.rng.uniform(0.9, 1.6) as f32;
    }
    for i in 0..30 {
        // (grit and pebbles running off the rim)
        let t = 17.0 + i as f32 * 0.5;
        let a = p.rng.uniform(0.0, TAU);
        let r = geo.rim(a) - 1.0;
        let (x, z) = (cx + a.cos() * r, cz + a.sin() * r);
        p.at(t, format!(r#"particle minecraft:falling_dust{{block_state:"minecraft:dirt"}} {x:.1} {:.1} {z:.1} 3 2 3 0 25 force"#, gy - 2.0));
    }
    for tk in [SH_C0 + 0.5, 11.0, 13.5, 16.0, 20.0] {
        p.at(tk, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,distance=..{SH_KILL}]"));
    }

    // the ground under the slabs and round the rim, asked of the world, and given to the pass
    {
        let tag = crate::ground::new_tag();
        let geo2 = geo.clone();
        p.later(0.25, move |q| q.ev.push((0.25, Act::Survey { tag, columns: sh_survey_columns(&geo2, q.bx, q.bz) })));
        let geo = geo.clone();
        p.later(0.8, move |q| sh_heights(q, geo, tag, 0.8, terrain));
    }
    if terrain {
        let floor_y = bedrock_top(dimension);
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, SH_LOAD);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // the first give and the sag: the middle moved down whole, with what stands on it
        for (t, y0, y1, drop) in [(SH_GIVE, by - 12, by + 30, 4), (SH_SAG, by - 16, by + 26, 3)] {
            let geo = geo.clone();
            p.later(t - 1.0, move |q| {
                for c in sh_give(&geo, bx, bz, y0, y1, drop) {
                    q.at(t, c);
                }
            });
        }
        // the rest of it down to bedrock, the walls' ledges and roots, the rubble at its foot, a chunk column at a time
        // from the middle out
        let cells = pk_cells(point, SH_R * 1.17 + SH_OUT + 1.0);
        let mut t = SH_DEEP0;
        let mut items: Vec<(f32, (i32, i32))> = Vec::new();
        for (x0, z0, _) in cells {
            items.push((t, (x0, z0)));
            t += (256.0 * f64::from(by - floor_y - SH_TOP_D) / SH_DEEP_RATE) as f32;
        }
        for pair in items.chunks(2) {
            let pair = pair.to_vec();
            let geo = geo.clone();
            p.later(pair[0].0 - 1.5, move |q| {
                for (t, (x0, z0)) in pair {
                    sh_deep(q, &geo, x0, z0, t, floor_y);
                }
            });
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The cracks' spurts (shaders/sinkhole.wgsl's sh_crack_at mirrors them): when each sets off, and how far out it has
/// run when it stops, over SH_SPURT. They race out from the middle in fits and starts, faster than the eye can follow
/// each, stalling between.
pub(super) const SH_SPURTS: usize = 10;
pub(super) const SH_SPURT: f32 = 0.2;
pub(super) fn sh_spurts(seed: u32) -> Vec<(f32, f64)> {
    (0..SH_SPURTS)
        .map(|i| {
            let t = 1.0 + 6.4 * (i as f64 + 0.15 + 0.7 * mh(i as u32, seed, 0x7c0)) / SH_SPURTS as f64;
            let r = SH_R * 1.3 * ((i + 1) as f64 / SH_SPURTS as f64).powf(0.85);
            (t as f32, r)
        })
        .collect()
}

/// Spurt i of the cracks (running from r0 out to r at `t`): dust puffing up out of the new cracks, along the slabs'
/// edges it opened, and loose bits crumbling into them.
fn sh_spurt_fx(p: &mut Plan, g: &ShGeo, land: &Shared, i: usize, t: f32, r0: f64, r: f64) {
    let (cx, cz) = (f64::from(p.bx) + 0.5, f64::from(p.bz) + 0.5);
    let gy = p.by + 1;
    let l = land.borrow();
    for j in 0..8u32 {
        let h = |c: u32| mh(i as u32 * 8 + j, g.seed, c);
        let a = h(0x7c3) * TAU;
        let rr = r0 + (r - r0) * h(0x7c4);
        let Some(k) = g.slab_at(rr * a.cos(), rr * a.sin()) else { continue };
        // (on its edge: the corner of the slab nearest)
        let (px, pz) = (rr * a.cos(), rr * a.sin());
        let c = g.slabs[k].corners();
        let (ex, ez) = c.iter().copied().min_by(|u, v| (u.0 - px).hypot(u.1 - pz).total_cmp(&(v.0 - px).hypot(v.1 - pz))).unwrap_or((px, pz));
        let (x, z) = (cx + 0.5 * (ex + px), cz + 0.5 * (ez + pz));
        let y = l.ground_at(p.bx, p.bz, x.floor() as i32, z.floor() as i32, gy).unwrap_or(gy);
        let at = t + SH_SPURT * ((rr - r0) / (r - r0).max(1.0)) as f32;
        p.at(at, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {x:.1} {}.2 {z:.1} 1.2 0.1 1.2 0.15 14 force"#, y));
        p.at(at + 0.05, format!("particle minecraft:campfire_cosy_smoke {x:.1} {}.1 {z:.1} 1.0 0.1 1.0 0.004 2 force", y));
        p.at(at + 0.3, format!(r#"particle minecraft:falling_dust{{block_state:"minecraft:coarse_dirt"}} {x:.1} {}.4 {z:.1} 1.0 0.1 1.0 0 6 force"#, y));
    }
}

/// Slab k's crack as it lets go (every few slabs', more of the rim's: those are near enough to pick out), the dirt it
/// throws up, and the bits crumbling off its edges into the widening cracks round it the second before.
fn sh_slab_fx(p: &mut Plan, g: &ShGeo, land: &Shared, k: usize, me: [f64; 3]) {
    let s = g.slabs[k];
    let (x, z) = s.centroid();
    let (x, z) = (f64::from(p.bx) + 0.5 + x, f64::from(p.bz) + 0.5 + z);
    let gy0 = p.by + 1;
    let l = land.borrow();
    let (bx, bz) = (p.bx, p.bz);
    let ground = |x: f64, z: f64| f64::from(l.ground_at(bx, bz, x.floor() as i32, z.floor() as i32, gy0).unwrap_or(gy0));
    let gy = ground(x, z);
    let rim = s.ring + 1 >= g.rings.len();
    if mh(k as u32, g.seed, 0x7a0) < if rim { 0.22 } else { 0.08 } {
        let name = ["crack1", "crack2", "crack3"][k % 3];
        let pitch = 0.7 + 0.35 * mh(k as u32, g.seed, 0x7a1);
        let (late, _) = sound_from([x, gy, z], me);
        p.at(s.t + late, format!("playsound orbital:sinkhole.{name} block @a {x:.1} {gy} {z:.1} 5 {pitch:.2} 0.6"));
    }
    if k % 2 == 0 {
        p.at(s.t + 0.25, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {x:.1} {:.1} {z:.1} 5 1 5 0.25 40 force"#, gy - 1.0));
    }
    if k % 3 == 0 || rim {
        let c = s.corners();
        let (ex, ez) = (f64::from(bx) + 0.5 + 0.5 * (c[2].0 + c[3].0), f64::from(bz) + 0.5 + 0.5 * (c[2].1 + c[3].1));
        p.at(s.t - 0.9, format!(r#"particle minecraft:falling_dust{{block_state:"minecraft:dirt"}} {ex:.1} {:.1} {ez:.1} 2.5 0.2 2.5 0 10 force"#, ground(ex, ez) + 0.3));
    }
}

/// The land's answers worked through, a part (a query) at a time and PER_TICK columns a tick, waiting for each to come in;
/// given to the pass once it is all in (or as far as it got, if the world has not answered by the time the collapse is
/// near). Columns whose chunks were not loaded yet (a strike far off, the chunks round it only now forced loaded) are
/// asked again, a few times, until 6 s: the pass is given the land after each round (`retry` the round).
#[allow(clippy::too_many_arguments)]
fn sh_land_step(q: &mut Plan, g: Rc<ShGeo>, land: Shared, tags: Rc<Vec<u32>>, part: usize, start: usize, at: f32, retry: u32) {
    let next = |q: &mut Plan, g: Rc<ShGeo>, land: Shared, tags: Rc<Vec<u32>>, part: usize, start: usize| {
        q.later(at + 0.05, move |q| sh_land_step(q, g, land, tags, part, start, at + 0.05, retry));
    };
    if part >= tags.len() {
        sh_land_done(q, &g, &land, at);
        let missing = std::mem::take(&mut land.borrow_mut().missing);
        if !missing.is_empty() && retry < 4 && at < 5.5 {
            // (asked again a little later, as one query)
            let tag = crate::columns::new_tag();
            let t = at + 0.6;
            q.later(t, move |q| {
                q.ev.push((t, Act::Read { tag, columns: missing, below: READ_BELOW, above: READ_ABOVE }));
                sh_land_step(q, g, land, Rc::new(vec![tag]), 0, 0, t, retry + 1);
            });
        }
        return;
    }
    let Some(a) = crate::columns::get(tags[part]) else {
        if at < SH_C0 - 0.6 {
            next(q, g, land, tags, part, start);
        } else {
            sh_land_done(q, &g, &land, at);
        }
        return;
    };
    let mats: Vec<(u8, sh_land::Class)> = a.palette.iter().map(|n| sh_land::material(n)).collect();
    let end = sh_land::work(&mut land.borrow_mut(), &g, &a, &mats, q.bx, q.by + 1, q.bz, start, retry > 0);
    if end >= a.columns.len() {
        next(q, g, land, tags, part + 1, 0);
    } else {
        next(q, g, land, tags, part, end);
    }
}

/// The land handed to the pass: its columns, and each slab's bounds in them (its words 15 and 18 to 23).
/// A slab drawn as its land only once every column of it is in (one with holes in it would show the pit through them);
/// until then, and if never, as a block of ground.
fn sh_land_done(q: &mut Plan, g: &ShGeo, land: &Shared, at: f32) {
    let l = land.borrow();
    q.ev.push((at, Act::Words { index: SH_GRID as u32, words: l.words.clone() }));
    for (k, s) in g.slabs.iter().enumerate() {
        let b = l.bounds[k];
        if b[0] > b[2] || l.missing_n[k] > 0 {
            continue;
        }
        let under = l.lowest[k] - 1 - s.thick.round() as i32;
        let base = (SH_SB + k * SH_SW) as u32;
        for (i, v) in [(15, 1), (18, b[0]), (19, b[1]), (20, b[2]), (21, b[3]), (22, under), (23, b[5])] {
            q.ev.push((at, Act::Data { index: base + i, value: v as f32 }));
        }
    }
}

/// The columns asked about as it starts: under each slab (its middle and towards each corner) and round the rim.
fn sh_survey_columns(g: &ShGeo, bx: i32, bz: i32) -> Vec<(i32, i32)> {
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let mut out = Vec::new();
    for s in &g.slabs {
        for (x, z) in sh_samples(s) {
            out.push(((cx + x).floor() as i32, (cz + z).floor() as i32));
        }
    }
    for (x, z) in sh_rim_samples(g) {
        out.push(((cx + x).floor() as i32, (cz + z).floor() as i32));
    }
    out
}
/// Where a slab's ground is asked: its middle, and three quarters of the way out to each corner.
fn sh_samples(s: &ShSlab) -> [(f64, f64); 5] {
    let (mx, mz) = s.centroid();
    let c = s.corners();
    let f = |i: usize| (mx + 0.75 * (c[i].0 - mx), mz + 0.75 * (c[i].1 - mz));
    [(mx, mz), f(0), f(1), f(2), f(3)]
}
/// Round the rim, a block and a half out, about a block apart.
fn sh_rim_samples(g: &ShGeo) -> Vec<(f64, f64)> {
    let n = (TAU * SH_R).ceil() as usize;
    (0..n)
        .map(|i| {
            let a = i as f64 / n as f64 * TAU;
            let r = g.rim(a) + 1.5;
            (a.cos() * r, a.sin() * r)
        })
        .collect()
}

/// The world's answer read once it is in (tried again a little later until then, and done without after the give):
/// each slab's ground (how high it lies over the target's, and how it slopes), and where water meets the rim (the
/// waterfalls the pass pours over it), given to the pass.
fn sh_heights(q: &mut Plan, g: Rc<ShGeo>, tag: u32, at: f32, terrain: bool) {
    if !crate::ground::ready(tag) {
        if at < SH_GIVE - 0.5 {
            q.later(at + 0.2, move |q| sh_heights(q, g, tag, at + 0.2, terrain));
        }
        return;
    }
    let (cx, cz) = (f64::from(q.bx) + 0.5, f64::from(q.bz) + 0.5);
    let gy = q.by + 1;
    let col = |x: f64, z: f64| ((cx + x).floor() as i32, (cz + z).floor() as i32);
    for (k, s) in g.slabs.iter().enumerate() {
        let pts = sh_samples(s);
        let hs: Vec<Option<f64>> = pts.iter().map(|&(x, z)| crate::ground::at(col(x, z).0, col(x, z).1).map(|h| f64::from(h - gy))).collect();
        let Some((top, sx, sz)) = sh_fit(&pts, &hs) else { continue };
        // (the middle's slabs went down with the give and the sag)
        let top = if s.ring == 0 && terrain { top - 7.0 } else { top };
        let b = (SH_SB + k * SH_SW) as u32;
        q.ev.push((at, Act::Data { index: b + 7, value: top as f32 }));
        q.ev.push((at, Act::Data { index: b + 8, value: sx as f32 }));
        q.ev.push((at, Act::Data { index: b + 9, value: sz as f32 }));
    }
    // the waterfalls: where the rim's columns stand under water, in runs at least three blocks long, the widest first
    let rim = sh_rim_samples(&g);
    let n = rim.len();
    let wet: Vec<Option<i32>> = rim
        .iter()
        .map(|&(x, z)| {
            let (i, j) = col(x, z);
            crate::ground::water(i, j).and_then(|d| crate::ground::at(i, j).map(|h| h + d - gy))
        })
        .collect();
    let mut runs: Vec<(usize, usize, i32)> = Vec::new();
    if let Some(dry) = wet.iter().position(Option::is_none) {
        let mut i = 0;
        while i < n {
            let k = (dry + i) % n;
            if wet[k].is_none() {
                i += 1;
                continue;
            }
            let (start, mut len, mut top) = (k, 0, i32::MIN);
            while i < n && wet[(dry + i) % n].is_some() {
                top = top.max(wet[(dry + i) % n].unwrap_or(0));
                len += 1;
                i += 1;
            }
            if len >= 3 {
                runs.push((start, len, top));
            }
        }
    }
    runs.sort_by(|a, b| b.1.cmp(&a.1));
    runs.truncate(SH_NWF);
    q.ev.push((at, Act::Data { index: SH_WF as u32, value: runs.len() as f32 }));
    for (w, (start, len, top)) in runs.into_iter().enumerate() {
        let a = (start as f64 + 0.5 * len as f64) / n as f64 * TAU;
        let half = 0.5 * len as f64 / n as f64 * TAU;
        // (it pours once the rim's slab there has gone)
        let r = g.rim(a) - 3.0;
        let on = g.slab_at(a.cos() * r, a.sin() * r).map_or(SH_C0 + 6.0, |k| g.slabs[k].t + 0.3);
        let b = (SH_WF + 4 + w * 4) as u32;
        for (i, v) in [a, half, f64::from(top), f64::from(on)].into_iter().enumerate() {
            q.ev.push((at, Act::Data { index: b + i as u32, value: v as f32 }));
        }
    }
}
/// A plane through a slab's ground: its height at the middle (the samples' median, so a trunk or a hollow under one
/// doesn't throw it) and its slope along x and z, from the samples near enough to it.
fn sh_fit(pts: &[(f64, f64); 5], hs: &[Option<f64>]) -> Option<(f64, f64, f64)> {
    let mut known: Vec<f64> = hs.iter().flatten().copied().collect();
    if known.is_empty() {
        return None;
    }
    known.sort_by(f64::total_cmp);
    let med = known[known.len() / 2];
    let top = hs[0].filter(|h| (h - med).abs() <= 3.0).unwrap_or(med);
    let (mut sxx, mut sxz, mut szz, mut sxh, mut szh) = (0.0, 0.0, 0.0, 0.0, 0.0);
    for i in 1..5 {
        let Some(h) = hs[i].filter(|h| (h - med).abs() <= 6.0) else { continue };
        let (dx, dz, dh) = (pts[i].0 - pts[0].0, pts[i].1 - pts[0].1, h - top);
        sxx += dx * dx;
        sxz += dx * dz;
        szz += dz * dz;
        sxh += dx * dh;
        szh += dz * dh;
    }
    let det = sxx * szz - sxz * sxz;
    let (sx, sz) = if det.abs() > 1e-6 { ((sxh * szz - szh * sxz) / det, (szh * sxx - sxh * sxz) / det) } else { (0.0, 0.0) };
    Some((top, sx.clamp(-1.2, 1.2), sz.clamp(-1.2, 1.2)))
}

/// The middle moved down `drop` blocks whole (`clone`, a row at a time: the ground and what stands on it, trees and
/// all), from y0 to y1, and what was over it left as air: the first give, and the sag after it.
fn sh_give(g: &ShGeo, bx: i32, bz: i32, y0: i32, y1: i32, drop: i32) -> Vec<String> {
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let mut out = Vec::new();
    let mut tops = Vec::new();
    let reach = (g.rings.get(1).map_or(18.0, |r| r.b) * 1.2 + 3.0).ceil() as i32;
    for z in bz - reach..=bz + reach {
        let inside: Vec<i32> = (bx - reach..=bx + reach)
            .filter(|&x| {
                let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
                g.slab_at(dx, dz).is_some_and(|k| g.slabs[k].ring == 0)
            })
            .collect();
        let (Some(&x0), Some(&x1)) = (inside.first(), inside.last()) else { continue };
        out.push(format!("clone {x0} {y0} {z} {x1} {y1} {z} {x0} {} {z} strict replace force", y0 - drop));
        tops.push(format!("fill {x0} {} {z} {x1} {y1} {z} minecraft:air strict", y1 - drop + 1));
    }
    out.extend(tops);
    out
}

/// What a column of the pit is, band by band: (band, lowest y, highest y, whether it is cut away there), bottom first,
/// from `floor_y` up to `top`.
fn sh_bands(g: &ShGeo, r: f64, a: f64, rim: f64, by: i32, floor_y: i32, top: i32) -> Vec<(usize, i32, i32, bool)> {
    if r < rim - SH_IN {
        // (inside the walls' reach: cut through)
        return if top >= floor_y + 1 { vec![(1, floor_y + 1, top, true)] } else { Vec::new() };
    }
    let (ca, sa) = (a.cos(), a.sin());
    let s = g.shift(ca, sa);
    let kmax = ShGeo::band_of(by, s, floor_y + 1);
    let mut out = Vec::new();
    for k in (0..=kmax).rev() {
        let (lo, hi) = ShGeo::band_span(by, s, k);
        let (lo, hi) = (lo.max(floor_y + 1), hi.min(top));
        if hi < lo {
            continue;
        }
        let air = if r > rim + SH_OUT {
            false
        } else {
            r < g.band_r(rim, ca, sa, k, by, (lo + hi) / 2)
        };
        out.push((k, lo, hi, air));
    }
    out
}

/// Slab k's land dug out, SH_DIG_AHEAD before it lets go (the pass draws it in its place over the hole from then): its
/// columns cut through from SH_TOP_D under the target's ground up to their real tops (the land's read: a mountain, the
/// trees on it, the snow on them, all of it, so nothing is left hanging over the pit), the walls' bands as they are cut;
/// a column not read cleared to SH_ABOVE over the target's ground and from its own ground SH_SURF_LO..SH_SURF_HI; the
/// water and lava round the rim next to it sealed in; and the plants and leaves left hanging over the edge, and what is
/// left of trees cut through there, cleared the tick after.
fn sh_top(p: &mut Plan, g: &ShGeo, land: &Shared, k: usize, sky: i32) {
    let s = g.slabs[k];
    let (by, bx, bz) = (p.by, p.bx, p.bz);
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let c = s.corners();
    let (mut x0, mut z0, mut x1, mut z1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
    // (its corners and its edges along the rings, which wander out past the corners)
    let mut edge = Vec::with_capacity(34);
    for i in 0..=16 {
        let th = s.th0 + (s.th1 - s.th0) * f64::from(i) / 16.0;
        for j in [s.ring, s.ring + 1] {
            let r = g.ring_r(j, th);
            edge.push((r * th.cos(), r * th.sin()));
        }
    }
    for (x, z) in c.iter().chain(edge.iter()) {
        x0 = x0.min(*x);
        z0 = z0.min(*z);
        x1 = x1.max(*x);
        z1 = z1.max(*z);
    }
    let rim_slab = s.ring + 1 >= g.rings.len();
    let m = if rim_slab { SH_OUT + 2.0 } else { 3.0 };
    let (xa, xb) = ((cx + x0 - m).floor() as i32, (cx + x1 + m).ceil() as i32);
    let (za, zb) = ((cz + z0 - m).floor() as i32, (cz + z1 + m).ceil() as i32);
    let top = (by + SH_ABOVE).min(sky);
    let mut b = Blocks::default();
    let mut seal = Blocks::default();
    let mut any = false;
    let l = land.borrow();
    for z in za..=zb {
        for x in xa..=xb {
            let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
            let (r, a) = (dx.hypot(dz), dz.atan2(dx));
            let rim = g.rim(a);
            match g.slab_on(r, a, rim) {
                Some(j) if j == k => {
                    any = true;
                    let real = l.top_at(bx, bz, x, z);
                    let hi = real.map_or(top, |t| (t - 1).min(sky).max(by - SH_TOP_BAND));
                    for (_, lo, hi, air) in sh_bands(g, r, a, rim, by, by - SH_TOP_D - 1, hi) {
                        if air {
                            b.run(x, z, lo, hi, "minecraft:air");
                        }
                    }
                    if real.is_none() {
                        b.put(x, z, SH_SURF_LO, SH_SURF_HI, "minecraft:air", None, true);
                    }
                }
                None if rim_slab => {
                    // (round the rim: what would run out over the edge, held in)
                    if r < rim + SH_OUT + 1.0 {
                        seal.put(x, z, by - SH_TOP_D, by + 12, "minecraft:barrier", Some("minecraft:water"), false);
                        seal.put(x, z, by - SH_TOP_D, by + 12, "minecraft:magma_block", Some("minecraft:lava"), false);
                    }
                }
                _ => {}
            }
        }
    }
    if !any {
        return;
    }
    let t = s.t - SH_DIG_AHEAD;
    // (the seal first: in the same tick, before the land next to it goes)
    if !seal.runs.is_empty() {
        p.ev.push((t - 0.05, Act::Blocks(Box::new(seal))));
    }
    p.ev.push((t, Act::Blocks(Box::new(b))));
    if rim_slab {
        let td = tidy(xa, za, xb, zb, 18, -1, |x, z| {
            let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
            if dx.hypot(dz) < g.rim(dz.atan2(dx)) { Col::Cleared } else { Col::Kept }
        });
        if !td.runs.is_empty() {
            p.ev.push((t + 0.05, Act::Blocks(Box::new(td))));
        }
    }
}

/// The rubble at the pit's foot, by where it lies: what fell in, in drifts of one kind or another.
fn sh_rubble(zone: f64) -> &'static str {
    if zone < 0.22 {
        "minecraft:cobbled_deepslate"
    } else if zone < 0.42 {
        "minecraft:cobblestone"
    } else if zone < 0.56 {
        "minecraft:stone"
    } else if zone < 0.7 {
        "minecraft:coarse_dirt"
    } else if zone < 0.84 {
        "minecraft:dirt"
    } else {
        "minecraft:tuff"
    }
}

/// Chunk column (x0, z0) of the pit dug on down to bedrock at `t` (and, past the rim, the walls cut back under it),
/// with the walls as they are cut: rubble on the ledges, moss on a few, roots hanging under the overhangs near the top;
/// the water and lava the walls cut through sealed in (lava cooled to magma, water to barrier near the top, where it
/// shows as water held at the edge, and to tuff deeper); and a heap of rubble at its foot, from what fell in.
fn sh_deep(p: &mut Plan, g: &ShGeo, x0: i32, z0: i32, t: f32, floor_y: i32) {
    let (by, bx, bz) = (p.by, p.bx, p.bz);
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let s = g.seed;
    let mut b = Blocks::default();
    let mut seal = Blocks::default();
    for z in z0..z0 + 16 {
        for x in x0..x0 + 16 {
            let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
            let r = dx.hypot(dz);
            let a = dz.atan2(dx);
            let rim = g.rim(a);
            if r > rim + SH_OUT + 2.0 {
                continue;
            }
            if r > rim - SH_IN {
                // (the walls' water and lava held in, out past where they are cut: lava cooled to magma, water to
                // barrier near the top, where it shows as the water held at the edge, and to tuff deeper)
                let top_w = by + 12;
                seal.put(x, z, floor_y + 1, top_w, "minecraft:magma_block", Some("minecraft:lava"), false);
                seal.put(x, z, by - 12, top_w, "minecraft:barrier", Some("minecraft:water"), false);
                seal.put(x, z, floor_y + 1, by - 13, "minecraft:tuff", Some("minecraft:water"), false);
            }
            let (fx, fz) = (f64::from(x), f64::from(z));
            // (a column the collapse took the top of keeps it as it was dug; one past the rim is cut back under it)
            let topped = r < rim;
            let hi = if topped { by - SH_TOP_D - 1 } else { by - SH_TOP_BAND - 1 };
            let bands = sh_bands(g, r, a, rim, by, floor_y, hi);
            let mut any_air = false;
            for &(_, lo, hi, air) in &bands {
                if air {
                    b.run(x, z, lo, hi, "minecraft:air");
                    any_air = true;
                }
            }
            // the walls' rock darker the deeper (the stone of them only: their ores, dirt and seals kept): tuff from a
            // quarter of the way down, deepslate from half, blackstone at the foot, the bounds between wandering
            if r > rim - SH_IN - 1.0 {
                let d = f64::from(by - floor_y);
                let wob = 7.0 * (vnoise(fx, fz, 9.0, s ^ 0x7d0) - 0.5) + 2.0 * (vnoise(fx, fz, 2.5, s ^ 0x7d1) - 0.5);
                let z1 = by - (0.27 * d + wob) as i32;
                let z2 = by - (0.5 * d + wob) as i32;
                let z3 = by - (0.74 * d + wob) as i32;
                for &(_, lo, hi, air) in &bands {
                    if air {
                        continue;
                    }
                    for (y0, y1, blk) in [(z2 + 1, z1, "minecraft:tuff"), (z3 + 1, z2, "minecraft:deepslate"), (floor_y + 1, z3, "minecraft:blackstone")] {
                        let (y0, y1) = (lo.max(y0), hi.min(y1));
                        if y1 >= y0 {
                            b.put(x, z, y0, y1, blk, Some("#minecraft:base_stone_overworld"), false);
                        }
                    }
                }
            }
            if !any_air {
                continue;
            }
            // the ledges: rubble on top of a band standing out under one cut back, moss on some
            for w in bands.windows(2) {
                let ((_, lo_b, _, air_b), (_, lo_a, _, air_a)) = (w[0], w[1]);
                if !air_b && air_a {
                    let n = vnoise(fx, fz, 4.0, s ^ 0x790 ^ lo_a as u32);
                    if n > 0.35 {
                        let h = if n > 0.72 { 1 } else { 0 };
                        let zone = vnoise(fx, fz, 9.0, s ^ 0x791);
                        let blk = if zone > 0.78 { "minecraft:moss_block" } else if zone > 0.55 { "minecraft:mossy_cobblestone" } else { sh_rubble(zone * 0.9) };
                        b.run(x, z, lo_a, lo_a + h, blk);
                    }
                }
                // the overhangs: roots hanging from under one standing out over one cut back, near the top
                if air_b && !air_a && lo_a > by - 32 && vnoise(fx, fz, 3.0, s ^ 0x792 ^ lo_a as u32) > 0.45 {
                    let _ = lo_b;
                    b.run(x, z, lo_a - 1, lo_a - 1, "minecraft:hanging_roots");
                }
            }
            // the rubble at its foot, where it is cut to the bottom: heaped higher towards the middle
            if bands.first().is_some_and(|f| f.3) {
                let h = (2.0 + 7.0 * vnoise(fx, fz, 16.0, s ^ 0x793) + 3.0 * vnoise(fx, fz, 5.0, s ^ 0x794) + 9.0 * (1.0 - r / rim).max(0.0)) as i32;
                let zone = vnoise(fx, fz, 13.0, s ^ 0x795);
                b.run(x, z, floor_y + 1, floor_y + h, sh_rubble(zone));
                let crown = vnoise(fx, fz, 6.0, s ^ 0x796);
                let lump = mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, s, 0x797);
                if lump > 0.994 {
                    // (a trunk that came down with its land)
                    b.run(x, z, floor_y + h + 1, floor_y + h + 2, "minecraft:oak_log");
                } else if crown > 0.7 {
                    b.run(x, z, floor_y + h + 1, floor_y + h + 1, if crown > 0.85 { "minecraft:grass_block" } else { "minecraft:coarse_dirt" });
                } else if lump > 0.9 {
                    b.run(x, z, floor_y + h + 1, floor_y + h + 1, "minecraft:mossy_cobblestone");
                }
            }
        }
    }
    if !seal.runs.is_empty() {
        p.ev.push((t - 0.05, Act::Blocks(Box::new(seal))));
    }
    if !b.runs.is_empty() {
        p.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path cargo test --release sh_write_table -- --ignored`: the table the pass reads, for
    /// tools/preview.py (a line `index value` a word), and, with SH_WATER, a waterfall at that angle.
    #[test]
    #[ignore]
    fn sh_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let mut w = super::sh_table(seed);
        // (the land, unless SH_LAND=0: snow on a grass block over dirt over stone, flat at the preview's ground (its
        // target's block at 0 64 0), now and then a patch of gravel or stone, spruces and a few oaks standing on it)
        if std::env::var("SH_LAND").map_or(true, |v| v != "0") {
            for (i, v) in synth_land(seed) {
                if w.len() <= i as usize {
                    w.resize(i as usize + 1, 0);
                }
                w[i as usize] = v;
            }
        }
        if let Ok(a) = std::env::var("SH_WATER") {
            let a: f32 = a.parse().unwrap();
            let g = super::ShGeo::new(seed);
            let r = g.rim(f64::from(a)) - 3.0;
            let k = g.slab_at(f64::from(a).cos() * r, f64::from(a).sin() * r).unwrap();
            w[super::SH_WF] = 1.0f32.to_bits();
            for (i, v) in [a, 0.05, -1.0, g.slabs[k].t + 0.3].into_iter().enumerate() {
                w[super::SH_WF + 4 + i] = v.to_bits();
            }
        }
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }

    fn synth_column(x: i32, z: i32) -> Option<(i32, Vec<&'static str>)> {
        use super::mh;
        let h = |k: u32| mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, 3, k);
        let patch = super::vnoise(f64::from(x), f64::from(z), 9.0, 77);
        let g = 64;
        let hh = |x: i32, z: i32, k: u32| mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, 3, k);
        let spruce = h(1) > 0.965;
        let oak = !spruce && h(2) > 0.992;
        // (the leaves of a spruce standing near: two out low, one out higher, a tip over it)
        let mut near = 99;
        for dz in -2i32..=2 {
            for dx in -2i32..=2 {
                if hh(x + dx, z + dz, 1) > 0.965 {
                    near = near.min(dx.abs() + dz.abs());
                }
            }
        }
        let canopy = |y: i32| near < 99 && ((y >= g + 3 && y <= g + 6 && near <= 2) || (y >= g + 6 && y <= g + 9 && near <= 1) || (y == g + 10 && near == 0));
        let ground = if patch > 0.78 { "minecraft:stone" } else if patch < 0.12 { "minecraft:gravel" } else { "minecraft:grass_block" };
        let block = |y: i32| -> &'static str {
            if y < g - 3 {
                "minecraft:stone"
            } else if y < g {
                if ground == "minecraft:grass_block" { "minecraft:dirt" } else { ground }
            } else if y == g {
                ground
            } else if spruce && y <= g + 7 {
                "minecraft:spruce_log"
            } else if canopy(y) {
                "minecraft:spruce_leaves"
            } else if oak && y <= g + 4 {
                "minecraft:oak_log"
            } else if oak && (g + 3..=g + 6).contains(&y) {
                "minecraft:oak_leaves"
            } else if y == g + 1 && ground != "minecraft:gravel" {
                "minecraft:snow"
            } else {
                "minecraft:air"
            }
        };
        let top = (g + 2..=g + 11).rev().find(|&y| block(y) != "minecraft:air").map_or(g + 1, |y| y + 1);
        Some((top, (top - 24..=top).map(block).collect()))
    }
    /// The land's words (the columns, and the slabs' bounds) for the preview's strike, as the mod works them out.
    fn synth_land(seed: f32) -> Vec<(u32, u32)> {
        use super::*;
        crate::ground::set_test(Some(|_, _| Some(65)));
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let mut ev = crate::strike::plan(&crate::lasers::SINKHOLE, &target, false, "minecraft:overworld", seed, [0.5, 100.0, 300.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Vec::new();
        while let Some((_, a)) = ev.pop() {
            match a {
                Act::Survey { tag, columns } => crate::ground::test_answer(tag, &columns),
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &synth_column),
                Act::Words { index, words } => out.extend(words.into_iter().enumerate().map(|(i, v)| (index + i as u32, v))),
                Act::Data { index, value } => out.push((index, value.to_bits())),
                Act::Later(job) | Act::Soon(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        crate::ground::set_test(None);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    fn edits(seed: f32) -> Vec<(f32, Blocks)> {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::SINKHOLE, &target, true, "minecraft:overworld", seed, [10.5, 66.0, 330.0], 0);
        let mut out = Vec::new();
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Blocks(b) => out.push((t, *b)),
                Act::Later(job) | Act::Soon(job) => ev.extend(job()),
                _ => {}
            }
        }
        out
    }

    #[test]
    fn sinkhole_slabs_tile_the_pit() {
        // every column inside the rim is one slab's, and lies inside the pass's shape for it (its corners' quad, grown
        // as the pass grows it); the slabs let go from the middle out
        for seed in [7.0, 37.0, 501.0] {
            let g = ShGeo::new(seed);
            assert!(g.slabs.len() > 100 && g.slabs.len() < 260, "{} slabs", g.slabs.len());
            assert!(SH_SB + g.slabs.len() * SH_SW < SH_MAT);
            for x in -140..140 {
                for z in -140..140 {
                    let (dx, dz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
                    let Some(k) = g.slab_at(dx, dz) else { continue };
                    assert!(sh_pass_covers(&g, k, dx, dz, 0.0), "seed {seed}: {x} {z} of slab {k} outside its shape");
                }
            }
            for s in &g.slabs {
                assert!(s.t >= SH_C0 && s.t < 16.0, "{}", s.t);
            }
            let _ = g.grows(0);
        }
    }
    /// strike.wgsl's sh_slab_hit, flat: whether (x, z) is inside slab s's quad, grown by the pass's margin less `less`.
    fn sh_pass_covers(g: &ShGeo, k: usize, x: f64, z: f64, less: f64) -> bool {
        let s = &g.slabs[k];
        let (grow_in, grow_out) = g.grows(k);
        let c = s.corners();
        let (mx, mz) = s.centroid();
        for i in 0..4 {
            let (a, b) = (c[i], c[(i + 1) % 4]);
            let (ex, ez) = (b.0 - a.0, b.1 - a.1);
            let l = ex.hypot(ez);
            if l < 1e-6 {
                continue;
            }
            // (the outward normal: away from the middle of the slab)
            let (mut nx, mut nz) = (ez / l, -ex / l);
            if nx * (mx - a.0) + nz * (mz - a.1) > 0.0 {
                nx = -nx;
                nz = -nz;
            }
            let grow = 1.0 + [grow_in, 0.0, grow_out, 0.0][i] - less;
            if nx * (x - a.0) + nz * (z - a.1) > grow {
                return false;
            }
        }
        true
    }

    #[test]
    fn sinkhole_digs_to_bedrock_under_each_slab_before_it_goes() {
        // the land under every slab is dug before the slab lets go and after the pass starts drawing it, and the pit is
        // cut on down to bedrock; nothing is cut outside the rim but the walls' bands, near it
        for seed in [7.0, 19.0] {
            digs_to_bedrock(seed);
        }
    }
    fn digs_to_bedrock(seed: f32) {
        let g = ShGeo::new(seed);
        let ev = edits(seed);
        let (cx, cz) = (10.5, -2.5);
        let mut top_dug: std::collections::HashMap<(i32, i32), f32> = Default::default();
        let mut deep: std::collections::HashSet<(i32, i32)> = Default::default();
        for (t, b) in &ev {
            for r in &b.runs {
                if r.only.is_some() || b.palette[r.block as usize] != "minecraft:air" || r.surface.is_some() {
                    continue;
                }
                let (dx, dz) = (f64::from(r.x) + 0.5 - cx, f64::from(r.z) + 0.5 - cz);
                let rr = dx.hypot(dz);
                assert!(rr < g.rim(dz.atan2(dx)) + SH_OUT + 0.5, "{} {} cut outside the rim", r.x, r.z);
                if r.y + r.height as i32 > 64 {
                    top_dug.entry((r.x, r.z)).or_insert(*t);
                }
                if r.y <= -58 {
                    deep.insert((r.x, r.z));
                }
            }
        }
        let mut n = 0;
        for x in -150..150 {
            for z in -150..150 {
                let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
                let Some(k) = g.slab_at(dx, dz) else { continue };
                let (gx, gz) = (x, z);
                let t = *top_dug.get(&(gx, gz)).unwrap_or_else(|| panic!("{gx} {gz} not dug"));
                let s = g.slabs[k];
                assert!(t <= s.t && t >= s.t - SH_LEAD, "{gx} {gz}: dug at {t}, slab {k} lets go at {}", s.t);
                if dx.hypot(dz) < g.rim(dz.atan2(dx)) - SH_IN {
                    assert!(deep.contains(&(gx, gz)), "{gx} {gz} not dug to bedrock");
                }
                n += 1;
            }
        }
        assert!(n > 30_000, "{n}");
    }

    #[test]
    fn sinkhole_changes_nothing_that_flows() {
        // nothing it puts down flows, falls or spreads
        for (_, b) in edits(37.0) {
            for name in &b.palette {
                assert!(!["minecraft:water", "minecraft:lava", "minecraft:sand", "minecraft:gravel", "minecraft:vine", "minecraft:red_sand"].contains(name), "{name}");
            }
        }
    }

    #[test]
    fn sinkhole_waterfalls_from_the_rim() {
        // water standing at the rim becomes a waterfall the pass pours, once the slab there has gone
        crate::ground::set_test(Some(|_, _| Some(64)));
        let g = ShGeo::new(7.0);
        let (cx, cz) = (10.5f64, -2.5f64);
        let wet: Vec<((i32, i32), i32)> = sh_rim_samples(&g)
            .into_iter()
            .filter(|(x, z)| z.atan2(*x).abs() < 0.15)
            .map(|(x, z)| (((cx + x).floor() as i32, (cz + z).floor() as i32), 3))
            .collect();
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::SINKHOLE, &target, true, "minecraft:overworld", 7.0, [10.5, 66.0, 330.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut data: std::collections::HashMap<u32, f32> = Default::default();
        while let Some((_, a)) = ev.pop() {
            match a {
                Act::Survey { tag, columns } => {
                    crate::ground::test_answer(tag, &columns);
                    crate::ground::set_test_water(&wet);
                }
                Act::Data { index, value } => {
                    data.insert(index, value);
                }
                Act::Later(job) | Act::Soon(job) => {
                    // (in time order: the survey before the stage that reads it)
                    let mut more = job();
                    more.sort_by(|a, b| b.0.total_cmp(&a.0));
                    ev.extend(more);
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        crate::ground::set_test(None);
        assert_eq!(data.get(&(SH_WF as u32)), Some(&1.0));
        let a = data[&(SH_WF as u32 + 4)];
        assert!(a.abs() < 0.05 || (a - TAU as f32).abs() < 0.05, "{a}");
        assert_eq!(data[&(SH_WF as u32 + 6)], 2.0);
    }
}

#[cfg(test)]
mod land {
    use super::sh_land::{ColInfo, SH_G};
    use super::*;
    use crate::strike::plan;

    /// A steep snowy mountain over the target (its ground 64): the ground block's height at (x, z).
    fn mountain(x: i32, z: i32) -> i32 {
        let (x, z) = (f64::from(x), f64::from(z));
        (64.0 + 70.0 * (0.5 + 0.5 * (x * 0.021).sin() * (z * 0.018 + 0.4).cos()) + 6.0 * (x * 0.13 + z * 0.07).sin()).round() as i32
    }
    fn tree(x: i32, z: i32) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 0.97
    }
    /// Its column as the world reads it: stone under dirt under a grass block, snow on it, now and then a spruce (a
    /// trunk 7 high, its leaves 4 to 11 up); its top, and its blocks from 24 under it to it, bottom first.
    fn column(x: i32, z: i32) -> Option<(i32, Vec<&'static str>)> {
        let g = mountain(x, z);
        let t = tree(x, z);
        let block = |y: i32| -> &'static str {
            if y < g - 3 {
                "minecraft:stone"
            } else if y < g {
                "minecraft:dirt"
            } else if y == g {
                "minecraft:grass_block"
            } else if t && y <= g + 7 {
                "minecraft:spruce_log"
            } else if t && y <= g + 11 && y >= g + 4 {
                "minecraft:spruce_leaves"
            } else if y == g + 1 {
                "minecraft:snow"
            } else {
                "minecraft:air"
            }
        };
        let top = if t { g + 12 } else { g + 2 };
        Some((top, (top - 24..=top).map(block).collect()))
    }
    fn ground(x: i32, z: i32) -> Option<i32> {
        Some(mountain(x, z) + 1)
    }

    struct Played {
        blocks: Vec<(f32, Blocks)>,
        words: Vec<u32>,
        data: std::collections::HashMap<u32, f32>,
    }
    /// The plan played out in time order against the mountain, the world's answers given at once.
    fn play(seed: f32, terrain: bool) -> Played {
        play_with(seed, terrain, 0)
    }
    /// As `play`, the columns east of x 50 not loaded for the first `late` queries.
    fn play_with(seed: f32, terrain: bool, late: usize) -> Played {
        crate::ground::set_test(Some(ground));
        crate::columns::clear();
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::SINKHOLE, &target, terrain, "minecraft:overworld", seed, [10.5, 66.0, 330.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Played { blocks: Vec::new(), words: Vec::new(), data: Default::default() };
        let mut reads = 0;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Survey { tag, columns } => crate::ground::test_answer(tag, &columns),
                Act::Read { tag, columns, below, above } => {
                    reads += 1;
                    if reads <= late {
                        crate::columns::test_answer(tag, &columns, below, above, &|x, z| if x > 50 { None } else { column(x, z) });
                    } else {
                        crate::columns::test_answer(tag, &columns, below, above, &column);
                    }
                }
                Act::Blocks(b) => out.blocks.push((t, *b)),
                Act::Words { index, words } => {
                    assert_eq!(index as usize, SH_GRID);
                    out.words = words;
                }
                Act::Data { index, value } => {
                    out.data.insert(index, value);
                }
                Act::Later(job) | Act::Soon(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        crate::ground::set_test(None);
        out
    }

    #[test]
    fn sinkhole_leaves_nothing_floating_over_a_mountain() {
        // every column of the pit is cleared from the rim's own band up to its very top (the mountain, its trees and
        // its snow), with nothing left between; and nothing past the rim is cut back more than SH_OVERHANG under the land
        // over it
        let g = ShGeo::new(19.0);
        let pl = play(19.0, true);
        let (cx, cz) = (10.5, -2.5);
        let mut air: std::collections::HashMap<(i32, i32), Vec<(i32, i32)>> = Default::default();
        for (_, b) in &pl.blocks {
            for r in &b.runs {
                if r.only.is_some() || r.surface.is_some() || b.palette[r.block as usize] != "minecraft:air" {
                    continue;
                }
                air.entry((r.x, r.z)).or_default().push((r.y, r.y + r.height as i32 - 1));
            }
        }
        let mut n = 0;
        for x in -130..150 {
            for z in -140..140 {
                let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
                if g.slab_at(dx, dz).is_none() {
                    continue;
                }
                let (top, _) = column(x, z).unwrap();
                let mut spans = air.get(&(x, z)).cloned().unwrap_or_default();
                spans.sort();
                // (from under the rim's own band up to the top, without a gap: the ledges under it are the walls')
                let mut reach = 64 - SH_TOP_BAND - 1;
                for (lo, hi) in spans {
                    if lo <= reach + 1 {
                        reach = reach.max(hi);
                    }
                }
                assert!(reach >= top - 1, "{x} {z}: cleared to {reach}, its top is {}: {:?}", top - 1, air.get(&(x, z)));
                n += 1;
            }
        }
        assert!(n > 30_000, "{n}");
        // (the overhangs: under the rim's own band, a column cut more than SH_OVERHANG past the rim is cut only deep)
        for (&(x, z), spans) in &air {
            let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
            let past = dx.hypot(dz) - g.rim(dz.atan2(dx));
            if past > SH_OVERHANG + 1.0 {
                for &(_, hi) in spans {
                    assert!(hi < 64 - SH_TOP_BAND - 2 * SH_BAND, "{x} {z}: {past:.1} past the rim, cut up to {hi}");
                }
            }
        }
    }

    #[test]
    fn sinkhole_slabs_carry_the_land_they_were_cut_from() {
        // the pass's columns: each the slab's that digs it, with the land's real blocks (snow on the mountain, the
        // spruces on it), inside its slab's bounds; and each slab's bounds given to the pass
        let g = ShGeo::new(7.0);
        let pl = play(7.0, true);
        assert_eq!(pl.words.len(), 3 * SH_GW * SH_GW);
        let (cx, cz) = (10.5, -2.5);
        let (mut trees, mut snow, mut n) = (0, 0, 0);
        for x in -130..150 {
            for z in -140..140 {
                let (dx, dz) = (f64::from(x) + 0.5 - cx, f64::from(z) + 0.5 - cz);
                let Some(k) = g.slab_at(dx, dz) else { continue };
                let i = Land::index(10, -3, x, z).unwrap();
                let (c, slab) = ColInfo::from_words([pl.words[3 * i], pl.words[3 * i + 1], pl.words[3 * i + 2]]).unwrap_or_else(|| panic!("{x} {z} not read"));
                assert_eq!(slab, Some(k), "{x} {z}");
                let m = mountain(x, z);
                let give = if g.slabs[k].ring == 0 { 7 } else { 0 };
                assert_eq!(c.h, m + 1 - 65 - give, "{x} {z}");
                assert_eq!(c.top, 1);
                // (the biome's tints: a dappled forest's east of x 40)
                assert_eq!(c.grass >> 19, if x > 40 { 0xDF6827 >> 19 } else { 0x91BD59 >> 19 }, "{x} {z}");
                if tree(x, z) {
                    assert_eq!((c.log, c.log_top, c.leaf, c.leaf_lo, c.leaf_hi), (29, 7, 34, 8, 11), "{x} {z}");
                    trees += 1;
                } else {
                    assert!(c.snow && c.log == 0);
                    snow += 1;
                }
                // (inside its bounds, as the pass has them)
                let b = (SH_SB + k * SH_SW) as u32;
                let d = |j: u32| pl.data[&(b + j)] as i32;
                assert_eq!(d(15), 1);
                let (ci, ck) = (x - 10 + SH_G, z + 3 + SH_G);
                assert!(ci >= d(18) && ck >= d(19) && ci <= d(20) && ck <= d(21), "{x} {z} outside slab {k}'s bounds");
                assert!(c.h - 1 >= d(22) && c.highest() < d(23));
                n += 1;
            }
        }
        assert!(trees > 300 && snow > 20_000 && n > 30_000, "{trees} {snow} {n}");
    }

    #[test]
    fn sinkhole_asks_again_for_land_not_loaded_yet() {
        // the columns not loaded when first asked are asked again, and every slab drawn as its land in the end
        let g = ShGeo::new(7.0);
        let pl = play_with(7.0, false, 6);
        for k in 0..g.slabs.len() {
            assert_eq!(pl.data.get(&((SH_SB + k * SH_SW) as u32 + 15)), Some(&1.0), "slab {k}");
        }
        let i = Land::index(10, -3, 90, -3).unwrap();
        assert!(pl.words[3 * i] >> 31 == 1);
        // never answered: those slabs stay blocks of ground
        let pl = play_with(7.0, false, 99);
        let (cx, cz) = (10.5, -2.5);
        for (k, s) in g.slabs.iter().enumerate() {
            let (x, _) = s.centroid();
            if x + cx > 70.0 {
                assert_eq!(pl.data.get(&((SH_SB + k * SH_SW) as u32 + 15)), None, "slab {k}");
            }
            let _ = cz;
        }
    }

    #[test]
    fn sinkhole_land_is_read_with_the_terrain_off_too() {
        let pl = play(37.0, false);
        assert!(pl.blocks.is_empty());
        assert!(pl.words.iter().any(|w| w >> 31 == 1));
    }
}

#[cfg(test)]
mod stage_cost {
    use super::*;
    use crate::strike::plan;
    /// `cargo test --release sh_stage_cost -- --ignored --nocapture`: the heaviest stages, each the best of three.
    #[test]
    #[ignore]
    fn sh_stage_cost() {
        let target = Target { block: [-1041, 42, 860], point: [-1040.5, 43.0, 860.5] };
        let mut runs: Vec<Vec<(f32, f64, usize, usize)>> = Vec::new();
        for _ in 0..3 {
            let t0 = std::time::Instant::now();
            let mut ev = plan(&crate::lasers::SINKHOLE, &target, true, "minecraft:overworld", 19.0, [-1055.5, 230.0, 860.5], 0);
            let mut out = vec![(-1.0, t0.elapsed().as_secs_f64() * 1000.0, ev.len(), 0)];
            while let Some((t, a)) = ev.pop() {
                if let Act::Later(job) | Act::Soon(job) = a {
                    let s = std::time::Instant::now();
                    let more = job();
                    let ms = s.elapsed().as_secs_f64() * 1000.0;
                    let r: usize = more.iter().map(|e| if let Act::Blocks(b) = &e.1 { b.runs.len() } else { 0 }).sum();
                    out.push((t, ms, more.len(), r));
                    ev.extend(more);
                }
            }
            out.sort_by(|a, b| a.0.total_cmp(&b.0));
            runs.push(out);
        }
        let mut best: Vec<(f32, f64, usize, usize)> = (0..runs[0].len()).map(|i| (runs[0][i].0, runs.iter().map(|r| r[i].1).fold(f64::MAX, f64::min), runs[0][i].2, runs[0][i].3)).collect();
        best.sort_by(|a, b| b.1.total_cmp(&a.1));
        for b in best.iter().take(8) {
            println!("stage at {:6.2} s: {:.3} ms, {} acts, {} runs", b.0, b.1, b.2, b.3);
        }
    }
}
