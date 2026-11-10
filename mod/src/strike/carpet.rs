//! The Carpet Bomb's plan: no beam. A bomber high over the land, unseen but for its contrail drawing across the sky
//! towards the player, lets go a stick of ten bombs: dark streaks dropping steeply one after another, they walk a line of
//! blasts across the land towards the player, each a low, wide fireball hugging the ground, a ring of dust racing out
//! and a rolling wall of dust left along the line, blast after blast, the last the biggest, close in front of them.
//!
//! What it leaves is real blocks: a row of bomb craters (scorched, their rims heaped with what they threw out), the
//! land round and between them flattened (the trees felled lying pointing away from the blast that felled them), the
//! grass charred, rubble strewn. Each blast works on the land as the ones before it left it (`Land`'s state): a crater
//! is never filled by the next one's rim, a log laid by one is not swept off by the next.
//!
//! Built on the Payload's (strike/payload.rs): its land read, its crater's materials, its felled trees, its rubble and
//! thrown blocks, its jolt and its sounds. shaders/carpetbomb.wgsl draws it from `cp_bomb_words`: keep the CP_* in step.
use super::payload::{self, Column, LEAF_NAMES, LEAVES, LOG_X, LOG_Y, LOG_Z, PL_ABOVE, PL_BELOW};
use super::{Act, Blocks, Col, Plan, Rng, Target, mh, sound_from, surf, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;

/// The bombs in the stick, the first one's blast (strike time), the time between them (the last one's a breath
/// longer), the ground between them (blocks), how big the last is (the others about 1).
pub(super) const CP_N: usize = 13;
pub(super) const CP_T0: f32 = 7.0;
/// The bomber: it comes out of the haze far beyond the target this soon, flies the line's way at this speed (blocks a
/// second), lets the stick go one after another over CP_RIPPLE seconds from CP_RELEASE as it passes over the start of
/// the line, and flies on past the player, out of sight a little after the last blast (carpetbomb.wgsl).
pub(super) const CP_APPEAR: f32 = 0.3;
const CP_PLANE_V: f64 = 170.0;
pub(super) const CP_RELEASE: f32 = 4.4;
const CP_RIPPLE: f32 = 1.8;
const CP_GAP: f32 = 0.6;
const CP_LAST_GAP: f32 = 1.0;
const CP_SPACING: f64 = 22.0;
pub(super) const CP_BIG: f64 = 1.55;
/// The last bomb comes down at least this far (level) from where the player stood: the line is drawn back if they
/// aimed closer.
pub(super) const CP_MIN_ME: f64 = 100.0;
/// A bomb's land worked out over the stages from this long before it strikes, in a window of its own (the next bomb's
/// starts as its ends): each bomb works on the land the one before left.
const CP_LEAD: f32 = 2.0;
/// The stages a bomb's blast takes (rows of its square), then its tidy, its felled trees, its rubble and thrown blocks.
const CP_PARTS: i32 = 6;
/// A crater's rim heap reaches this far (in its radii).
const CP_RIM: f64 = 1.6;
/// The land read in this many parts (each a query and a stage).
const CP_READS: usize = 16;

/// The table (render.set-data): words 0..16 the header (the bombs' count, the line's way (level, from the far end
/// towards the player), the wind, the bomber's speed along the line, the first bomb's place along it, the last's), from
/// CP_B the bombs, CP_BW words each (when it strikes, x, z and its ground's height from the target's ground point, its
/// size, its place along the line, a hash), from CP_DB the debris (CP_DW words a piece, CP_DPB a bomb, the last twice
/// that), the land's heightfield at payload::PL_HF.
pub(super) const CP_B: usize = 16;
pub(super) const CP_BW: usize = 8;
pub(super) const CP_DB: usize = 10496;
pub(super) const CP_DW: usize = 10;
pub(super) const CP_DPB: usize = 24;

/// One bomb: when it strikes, where (from the target's ground point), how big, how far along the line (0 the target,
/// the player's side positive: its place on the line's way), a hash of its own.
#[derive(Clone, Copy, Debug)]
pub(super) struct Bomb {
    pub t: f32,
    pub x: f64,
    pub z: f64,
    pub s: f64,
    pub along: f64,
    pub h: u32,
}

/// The stick: its line's way (level, towards the player), its bombs (the first the farthest), the wind, the bomber's
/// speed along the line.
#[derive(Clone, Debug)]
pub(super) struct CpGeo {
    pub seed: u32,
    pub dir: [f64; 2],
    pub bombs: Vec<Bomb>,
    pub wind: (f64, f64),
    pub vb: f64,
}

impl CpGeo {
    /// `me`: the player from the target's ground point. The last bomb comes down on the target (or CP_MIN_ME short of the
    /// player, if they aimed closer than that), the others walking up to it from beyond, along the way they look.
    pub fn new(seed: f32, me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |i: u32, k: u32| mh(i, seed, 0xcb0 + k);
        let d = me[0].hypot(me[2]);
        let u = if d > 1.0 { [me[0] / d, me[2] / d] } else { [0.0, 1.0] };
        // (the stick comes in a little off the way they look, from ahead and to one side: its blasts sweep across the
        // picture towards them rather than piling up one behind another)
        let phi = (32.0 + 8.0 * r(0, 6)).to_radians() * if r(0, 7) < 0.5 { -1.0 } else { 1.0 };
        let dir = [u[0] * phi.cos() - u[1] * phi.sin(), u[0] * phi.sin() + u[1] * phi.cos()];
        let side = [-dir[1], dir[0]];
        // (the last on the target, or drawn back from them along the way they look if they aimed too close)
        let back = (CP_MIN_ME - d).max(0.0);
        let base = [-u[0] * back, -u[1] * back];
        let mut along = vec![0.0; CP_N];
        for b in (0..CP_N - 1).rev() {
            along[b] = along[b + 1] - (CP_SPACING + 5.0 * (r(b as u32, 0) - 0.5));
        }
        let mut t = CP_T0;
        let ph = TAU * r(0, 9);
        let bombs: Vec<Bomb> = (0..CP_N)
            .map(|b| {
                let last = b == CP_N - 1;
                if b > 0 {
                    t += if last { CP_LAST_GAP } else { CP_GAP + 0.16 * (r(b as u32, 1) as f32 - 0.5) };
                }
                // (a stick falls nearly in a line: it wanders a few blocks across it)
                let lat = if last { 0.0 } else { 3.0 * (0.8 * b as f64 + ph).sin() + 2.0 * (r(b as u32, 2) - 0.5) };
                let s = if last { CP_BIG } else { 0.9 + 0.2 * r(b as u32, 3) };
                let (x, z) = (base[0] + dir[0] * along[b] + side[0] * lat, base[1] + dir[1] * along[b] + side[1] * lat);
                // (`along`: its place along the line's way, from the target)
                Bomb { t, x, z, s, along: x * dir[0] + z * dir[1], h: (mh(b as u32, seed, 0xcb7) * 16_777_216.0) as u32 }
            })
            .collect();
        let vb = (along[CP_N - 2] - along[0]) / f64::from(bombs[CP_N - 2].t - bombs[0].t);
        let wa = TAU * r(0, 4);
        let ws = 1.5 + 2.0 * r(0, 5);
        CpGeo { seed, dir, bombs, wind: (wa.cos() * ws, wa.sin() * ws), vb }
    }
}

/// The table's header and its bombs (see CP_B), `ys` each bomb's ground from the target's (0 until the world answers).
fn cp_bomb_words(g: &CpGeo, ys: &[f64]) -> Vec<u32> {
    let mut w = vec![0.0f32; CP_B + CP_N * CP_BW];
    w[0] = CP_N as f32;
    w[1] = g.dir[0] as f32;
    w[2] = g.dir[1] as f32;
    w[3] = g.wind.0 as f32;
    w[4] = g.wind.1 as f32;
    w[5] = g.vb as f32;
    w[6] = g.bombs[0].along as f32;
    w[7] = g.bombs[CP_N - 1].along as f32;
    // (where the line passes the target, across its way: off it only when the stick was drawn back)
    let last = g.bombs[CP_N - 1];
    let across = last.x * -g.dir[1] + last.z * g.dir[0];
    w[8] = (-g.dir[1] * across) as f32;
    w[9] = (g.dir[0] * across) as f32;
    // (the bomber: its speed, the middle of its release and where it is along the line then (a little short of the
    // first bomb's place: the stick falls on forward), when it comes out of the haze)
    w[10] = CP_PLANE_V as f32;
    w[11] = CP_RELEASE + 0.5 * CP_RIPPLE;
    w[12] = CP_RIPPLE;
    w[13] = (g.bombs[0].along - 40.0) as f32;
    w[14] = CP_APPEAR;
    for (i, b) in g.bombs.iter().enumerate() {
        let o = CP_B + CP_BW * i;
        w[o] = b.t;
        w[o + 1] = b.x as f32;
        w[o + 2] = b.z as f32;
        w[o + 3] = ys.get(i).copied().unwrap_or(0.0) as f32;
        w[o + 4] = b.s as f32;
        w[o + 5] = b.along as f32;
        w[o + 6] = (b.h % 1000) as f32;
    }
    w.into_iter().map(f32::to_bits).collect()
}
/// The debris each blast throws (as the Payload's, payload.rs's pl_debris_words, smaller): its bearing, how far out it
/// is torn up, its speed out and up, when (after its blast), its size, e^(k t0), its spin. Keep in step with
/// carpetbomb.wgsl's cp_chunk.
pub(super) fn cp_debris_words(g: &CpGeo) -> Vec<u32> {
    let n = (CP_N + 2) * CP_DPB;
    let mut w = vec![0.0f32; n * CP_DW];
    for (bi, bomb) in g.bombs.iter().enumerate() {
        let last = bi == CP_N - 1;
        let count = if last { 3 * CP_DPB } else { CP_DPB };
        for j in 0..count {
            let i = bi * CP_DPB + j;
            let h = |k: u32| mh(i as u32, g.seed, 0xd00 + k);
            let ang = h(1) * TAU;
            let big = h(3);
            // (the last's pieces thrown harder and further, bigger)
            let s = bomb.s * if last { 1.6 } else { 1.0 };
            let r0 = (4.0 + 19.0 * h(6).sqrt()) * s;
            let far = h(7) < 0.2;
            let el = if far { 0.5 + 0.35 * h(2) } else { 0.45 + 0.75 * h(2) };
            let sp = (if far { 45.0 + 25.0 * h(4) } else { 20.0 + 30.0 * h(4).powf(0.7) }) * (1.0 - 0.25 * big) * s.sqrt();
            let t0 = r0 / 343.0 + 0.1 * h(5);
            let row = [ang.cos(), ang.sin(), r0, el.cos() * sp, el.sin() * sp, t0, (0.1 + 0.75 * big * big * big) * s.sqrt(), (0.06 * t0).exp(), 3.0 + 6.0 * h(8), 0.0];
            for (k, x) in row.iter().enumerate() {
                w[CP_DW * i + k] = *x as f32;
            }
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

// ---- one blast's work on the land ---------------------------------------------------------------------------------
/// A blast on the land: where (in the world), how big, its crater's wandering edge.
#[derive(Clone, Copy, Debug)]
struct Blast {
    cx: f64,
    cz: f64,
    t: f32,
    s: f64,
    ph: [f64; 3],
    seed: u32,
    /// The last, biggest: its crater wider and deeper, the land flattened, the trees felled and the grass charred further.
    big: bool,
}
impl Blast {
    // (a bomb's crater about 25 across and 8 deep, the next ones' overlapping it into a ragged trench; the land flattened
    // to 35, the trees felled to 50, charred to 55. The last's about 65 across and 16 deep, terraced, flattened to 110,
    // felled to 150, charred to 170; all with a size of about 1, the last's 1.55)
    fn crater_r(&self) -> f64 {
        self.s * if self.big { 21.0 } else { 12.5 }
    }
    fn crater_d(&self) -> f64 {
        self.s * if self.big { 10.6 } else { 8.0 }
    }
    fn flat_r(&self) -> f64 {
        self.s * if self.big { 71.0 } else { 35.0 }
    }
    fn char_r(&self) -> f64 {
        self.s * if self.big { 110.0 } else { 55.0 }
    }
    fn band_w(&self) -> f64 {
        self.s * if self.big { 26.0 } else { 15.0 }
    }
    /// How far round it its land work reaches.
    fn reach(&self) -> f64 {
        (self.flat_r() * 1.13 + self.band_w()).max(self.char_r()) + 2.0
    }
    fn kill_r(&self) -> f64 {
        self.s * if self.big { 80.0 } else { 40.0 }
    }
    fn wob(&self, a: f64) -> f64 {
        1.0 + 0.1 * (3.0 * a + self.ph[0]).sin() + 0.06 * (5.0 * a + self.ph[1]).sin() + 0.035 * (9.0 * a + self.ph[2]).sin()
    }
    /// Column (x, z): how far from its middle, which way, how far out in its crater's radii.
    fn at(&self, x: i32, z: i32) -> (f64, f64, f64) {
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let r = dx.hypot(dz);
        let a = dz.atan2(dx);
        let rc = self.crater_r() * self.wob(a) * (0.94 + 0.12 * vnoise(f64::from(x), f64::from(z), 5.0, self.seed ^ 0x31));
        (r, a, r / rc)
    }
    fn flat(&self, a: f64) -> f64 {
        self.flat_r() * (1.0 + 0.1 * (2.0 * a + self.ph[2]).sin() + 0.06 * (7.0 * a + self.ph[0]).sin())
    }
    fn bowl(&self, u: f64) -> f64 {
        if u >= 1.0 {
            return 0.0;
        }
        let d = self.crater_d() * (1.0 - u * u).powf(0.75);
        if !self.big {
            return d;
        }
        // (the last's walls stepped down in terraces three deep, each lip rounded)
        let k = d / 3.0;
        (k.floor() + (((k.fract() - 0.7) / 0.3).clamp(0.0, 1.0)).powi(2)) * 3.0
    }
    fn heap(&self, u: f64) -> f64 {
        if !(1.0..=CP_RIM).contains(&u) {
            return 0.0;
        }
        self.s * if self.big { 2.2 } else { 1.3 } * (2.8 * (-(u - 1.12).powi(2) / 0.05).exp() + 0.5 * (1.0 - (u - 1.0) / (CP_RIM - 1.0)))
    }
    /// How hard it still hits the column at distance r and bearing a in the band past its flattened land: 1 at its inner
    /// edge to 0 at its outer.
    fn band_ra(&self, r: f64, a: f64) -> Option<f64> {
        let e = r - self.flat(a);
        (0.0..self.band_w()).contains(&e).then(|| 1.0 - e / self.band_w())
    }
    fn knocked_ra(&self, c: &Column, x: i32, z: i32, r: f64, a: f64) -> bool {
        c.trunk >= 3 && !c.fluid && self.band_ra(r, a).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, self.seed, 0x91) < 0.55 * p.powf(1.3))
    }
    /// When its front reaches column (x, z): its edits go in from the middle out.
    fn wave_at(&self, x: i32, z: i32) -> f32 {
        self.t + 0.05 + ((f64::from(x) + 0.5 - self.cx).hypot(f64::from(z) + 0.5 - self.cz) / 343.0) as f32
    }
    /// The charred grass round it, patchier further out (payload.rs's `charred`).
    fn charred(&self, x: i32, z: i32, r: f64) -> Option<&'static str> {
        let n = vnoise(f64::from(x), f64::from(z), 6.0, self.seed ^ 0x71);
        let m = vnoise(f64::from(x), f64::from(z), 2.0, self.seed ^ 0x72);
        let inner = 0.35 * self.char_r();
        let reach = 0.12 + 0.68 * (1.0 - ((r - inner) / (self.char_r() - inner)).clamp(0.0, 1.0)).powf(1.5);
        (0.55 * n + 0.45 * m > 1.0 - reach).then(|| if m > 0.66 { "minecraft:podzol" } else if n > 0.7 { "minecraft:dirt" } else { "minecraft:coarse_dirt" })
    }
}

/// What has happened to a column so far.
const DUG: u8 = 1;
const HEAPED: u8 = 2;
/// A tree standing there was felled (its stump left), or is to be by the blast under way.
const FELLED: u8 = 4;
const FELL_NOW: u8 = 8;
/// A felled log, a crown or a piece of rubble lies there: the next blast leaves it.
const LAID: u8 = 16;

/// The land along the line: every column within a blast's reach, as read, and what the blasts have made of it so far
/// (its ground's top, its highest block, what happened to it, the last bomb to change it).
struct Land {
    x0: i32,
    z0: i32,
    w: i32,
    h: i32,
    cols: Vec<Column>,
    g: Vec<i32>,
    top: Vec<i32>,
    flag: Vec<u8>,
    last: Vec<u8>,
    missing: Vec<(i32, i32)>,
}
type Shared = Rc<RefCell<Land>>;
impl Land {
    fn new(blasts: &[Blast]) -> Land {
        let (mut x0, mut z0, mut x1, mut z1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for b in blasts {
            let r = b.reach().ceil() as i32 + 2;
            x0 = x0.min(b.cx.floor() as i32 - r);
            z0 = z0.min(b.cz.floor() as i32 - r);
            x1 = x1.max(b.cx.floor() as i32 + r);
            z1 = z1.max(b.cz.floor() as i32 + r);
        }
        let (w, h) = (x1 - x0 + 1, z1 - z0 + 1);
        let n = (w * h) as usize;
        Land { x0, z0, w, h, cols: vec![Column::default(); n], g: vec![0; n], top: vec![0; n], flag: vec![0; n], last: vec![0; n], missing: Vec::new() }
    }
    fn idx(&self, x: i32, z: i32) -> Option<usize> {
        let (i, k) = (x - self.x0, z - self.z0);
        (i >= 0 && k >= 0 && i < self.w && k < self.h).then(|| (k * self.w + i) as usize)
    }
    fn known(&self, x: i32, z: i32) -> Option<usize> {
        self.idx(x, z).filter(|&i| self.cols[i].known)
    }
    fn put(&mut self, x: i32, z: i32, c: Column) {
        if let Some(i) = self.idx(x, z) {
            self.cols[i] = c;
            self.g[i] = c.g;
            self.top[i] = c.top.max(c.g);
        }
    }
    /// Water or lava in it or next to it: dig nothing there.
    fn wet_near(&self, x: i32, z: i32) -> bool {
        [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|(dx, dz)| self.known(x + dx, z + dz).is_some_and(|i| self.cols[i].fluid))
    }
    /// Nothing over its ground and nothing laid on it: a log or rubble may lie there.
    fn open(&self, i: usize) -> bool {
        self.top[i] == self.g[i] && self.flag[i] & (LAID | DUG | HEAPED) == 0 && !self.cols[i].fluid
    }
}

/// The columns to read in part `part` (rows of the land's square, each within a blast's reach): each row's stretches
/// within a blast's reach worked out from the blasts, not a look at every column of the square.
fn cp_read_columns(blasts: &[Blast], x0: i32, z0: i32, w: i32, h: i32, part: usize) -> Vec<(i32, i32)> {
    let rows = (h + CP_READS as i32 - 1) / CP_READS as i32;
    let mut out = Vec::new();
    let mut spans: Vec<(i32, i32)> = Vec::new();
    for k in part as i32 * rows..((part as i32 + 1) * rows).min(h) {
        let z = z0 + k;
        let fz = f64::from(z) + 0.5;
        spans.clear();
        for b in blasts {
            let r = b.reach() + 1.0;
            let dz = fz - b.cz;
            if dz.abs() > r {
                continue;
            }
            let half = (r * r - dz * dz).sqrt();
            let (a, e) = (((b.cx - half) - 0.5).ceil() as i32, ((b.cx + half) - 0.5).floor() as i32);
            spans.push((a.max(x0), e.min(x0 + w - 1)));
        }
        spans.sort_unstable();
        let mut next = i32::MIN;
        for &(a, e) in &spans {
            for x in a.max(next)..=e {
                out.push((x, z));
            }
            next = next.max(e + 1);
        }
    }
    crate::meter::spend(40 * out.len() as u64 + 200 * (rows as u64) * blasts.len() as u64);
    out
}

/// The land's parts taken in a stage each, as they are answered (the columns not loaded yet asked again, twice).
fn cp_land_step(q: &mut Plan, land: Shared, tags: Rc<Vec<u32>>, part: usize, at_t: f32, until: f32, retry: u32) {
    if part >= tags.len() {
        let missing = std::mem::take(&mut land.borrow_mut().missing);
        if !missing.is_empty() && retry < 2 && at_t < until {
            let tag = crate::columns::new_tag();
            let t = at_t + 0.8;
            q.later(t, move |q| {
                q.ev.push((t, Act::Read { tag, columns: missing, below: PL_BELOW, above: PL_ABOVE }));
                q.later(t + 0.15, move |q| cp_land_step(q, land, Rc::new(vec![tag]), 0, t + 0.15, until, retry + 1));
            });
        }
        return;
    }
    let Some(a) = crate::columns::get(tags[part]) else {
        if at_t < until {
            q.later(at_t + 0.1, move |q| cp_land_step(q, land, tags, part, at_t + 0.1, until, retry));
        }
        return;
    };
    {
        let mut l = land.borrow_mut();
        let mut missing = Vec::new();
        let mut got = Vec::new();
        payload::take_in_each(&a, |x, z, c| got.push((x, z, c)), |x, z| missing.push((x, z)));
        for (x, z, c) in got {
            l.put(x, z, c);
        }
        l.missing.extend(missing);
    }
    q.later(at_t + 0.05, move |q| cp_land_step(q, land, tags, part + 1, at_t + 0.05, until, retry));
}

/// Blast `b` (the `n`th) over rows k0..k1 of its square: its crater, its rim's heap, the land it flattens, the grass it
/// chars and the crowns it strips past that, on the land as the blasts before it left it.
fn cp_blast_rows(q: &mut Plan, land: &mut Land, b: &Blast, n: u8, k0: i32, k1: i32) {
    let rr = b.reach().ceil() as i32;
    let (ix, iz) = (b.cx.floor() as i32, b.cz.floor() as i32);
    let mut out = Blocks::default();
    crate::meter::spend(2_500 * ((k1 - k0) * (2 * rr + 1)) as u64);
    let reach2 = b.reach() * b.reach();
    for z in iz - rr + k0..iz - rr + k1 {
        let dz = f64::from(z) + 0.5 - b.cz;
        for x in ix - rr..=ix + rr {
            // (out of its reach: nothing worked out at all)
            let dx = f64::from(x) + 0.5 - b.cx;
            if dx * dx + dz * dz > reach2 {
                continue;
            }
            let Some(i) = land.known(x, z) else { continue };
            let c = land.cols[i];
            if c.lava {
                continue;
            }
            let (r, ang, u) = b.at(x, z);
            let (gc, tc, fl) = (land.g[i], land.top[i], land.flag[i]);
            if u < 1.0 {
                // the crater: dug (deeper where an earlier one was), everything over it gone, its new face scorched, the
                // lava under it sealed; cut into water as into land, as the Payload's
                let floor = (c.g - b.bowl(u).round() as i32).min(gc);
                out.run(x, z, floor + 1, tc.max(gc), "minecraft:air");
                out.put(x, z, floor - 3, floor - 1, "minecraft:stone", Some("minecraft:lava"), false);
                let d = if u < 0.6 { 1 } else { 0 };
                for y in floor - d..=floor {
                    out.run(x, z, y, y, payload::scorched(x, y, z, u, b.seed));
                }
                land.g[i] = floor;
                land.top[i] = floor;
                land.flag[i] = DUG;
                land.last[i] = n + 1;
                continue;
            }
            let wet = land.wet_near(x, z);
            if u < CP_RIM && !wet && !c.fluid {
                // the rim: earth heaped on it, what stood there swept off; never over an earlier crater
                if fl & DUG != 0 {
                    continue;
                }
                let top = (c.g + b.heap(u).round() as i32).max(gc);
                for y in gc + 1..=top {
                    out.run(x, z, y, y, payload::ejecta(x, y, z, b.seed));
                }
                if tc > top {
                    out.run(x, z, top + 1, tc, "minecraft:air");
                }
                land.g[i] = top;
                land.top[i] = top;
                land.flag[i] = (fl & !(FELL_NOW | LAID)) | HEAPED;
                land.last[i] = n + 1;
                continue;
            }
            if c.fluid {
                continue;
            }
            let band = b.band_ra(r, ang);
            if r < b.flat(ang) || (fl & (FELLED | DUG | HEAPED) == 0 && b.knocked_ra(&c, x, z, r, ang)) {
                // flattened: what stands on the land swept off (a felled tree's stump left, what an earlier blast laid
                // left lying), the grass charred
                let keep = if fl & (FELLED | LAID | DUG | HEAPED) != 0 {
                    tc
                } else {
                    gc + if c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, b.seed, 0x81) * 2.0) as i32 } else { 0 }
                };
                if tc > keep {
                    out.run(x, z, keep + 1, tc, "minecraft:air");
                    land.last[i] = n + 1;
                }
                land.top[i] = keep.min(tc);
                if c.trunk >= 3 && fl & (FELLED | DUG | HEAPED) == 0 {
                    land.flag[i] |= FELLED | FELL_NOW;
                }
            } else if fl & (FELLED | LAID) == 0
                && let Some(p) = band
                && c.leaves != 255
                && tc > gc + 1
                && vnoise(f64::from(x), f64::from(z), 5.0, b.seed ^ 0x93) < 0.25 + 0.75 * p
            {
                // in the band past it: the crowns stripped, in patches, wholly near it and their tops further out
                let keep = (f64::from(tc - gc) * (1.0 - (0.35 + 0.8 * p).min(1.0))).floor() as i32;
                out.put(x, z, gc + 1 + keep, tc, "minecraft:air", Some(LEAF_NAMES[c.leaves as usize]), false);
            }
            if c.ground == 1
                && gc == c.g
                && fl & (DUG | HEAPED) == 0
                && let Some(m) = b.charred(x, z, r)
            {
                out.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
            }
        }
    }
    for (t, bl) in out.split_by(|x, z| b.wave_at(x, z)) {
        q.ev.push((t, Act::Blocks(Box::new(bl))));
    }
}

/// What blast `n` left hanging round what it changed (leaves of a tree whose trunk went, plants whose ground went).
fn cp_tidy(q: &mut Plan, land: &Land, b: &Blast, n: u8, k0: i32, k1: i32) {
    let rr = b.reach().ceil() as i32;
    let (ix, iz) = (b.cx.floor() as i32, b.cz.floor() as i32);
    let col = |x: i32, z: i32| -> Col {
        match land.idx(x, z) {
            Some(i) if land.last[i] == n + 1 && !land.cols[i].fluid => Col::Cleared,
            _ => Col::Kept,
        }
    };
    let t = tidy(ix - rr, iz - rr + k0, ix + rr, iz - rr + k1 - 1, 40, -1, col);
    for (t, bl) in t.split_by(|x, z| b.wave_at(x, z) + 0.15) {
        q.ev.push((t, Act::Blocks(Box::new(bl))));
    }
}

/// The trees blast `n` felled, lying on the land pointing away from it (their crowns crushed round their ends further
/// out), each down once its front has swept where it lies.
fn cp_felled(q: &mut Plan, land: &mut Land, b: &Blast, k0: i32, k1: i32) {
    let rr = b.reach().ceil() as i32;
    let (ix, iz) = (b.cx.floor() as i32, b.cz.floor() as i32);
    let mut out = Blocks { clear_of_player: true, ..Default::default() };
    crate::meter::spend(300 * ((k1 - k0) * (2 * rr + 1)) as u64);
    for z in iz - rr + k0..iz - rr + k1 {
        for x in ix - rr..=ix + rr {
            let Some(i) = land.known(x, z) else { continue };
            if land.flag[i] & FELL_NOW == 0 {
                continue;
            }
            land.flag[i] &= !FELL_NOW;
            let c = land.cols[i];
            let (r, a, _) = b.at(x, z);
            let (dx, dz) = (a.cos(), a.sin());
            let (sx, sz, log) = if dx.abs() > dz.abs() { (dx.signum() as i32, 0, LOG_X[c.wood as usize]) } else { (0, dz.signum() as i32, LOG_Z[c.wood as usize]) };
            let h = |k: u32| mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, b.seed, k);
            let want = (i32::from(c.trunk) - 1).clamp(2, 3 + (h(1) * 4.0) as i32);
            let mut gy = c.g;
            let mut last = None;
            for k in 1..=want {
                let (lx, lz) = (x + sx * k, z + sz * k);
                let Some(j) = land.known(lx, lz) else { break };
                if !land.open(j) || (land.g[j] - gy).abs() > 1 || land.wet_near(lx, lz) {
                    break;
                }
                let g2 = land.g[j];
                out.run(lx, lz, g2 + 1, g2 + 1, log);
                land.top[j] = g2 + 1;
                land.flag[j] |= LAID;
                gy = g2;
                last = Some((lx, lz));
            }
            // (its crown crushed round its end, out where the blast has not stripped it)
            if let (Some((lx, lz)), true) = (last, r > 0.55 * b.flat_r() && c.leaves != 255) {
                for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx)] {
                    let (fx, fz) = (lx + ox, lz + oz);
                    let Some(j) = land.known(fx, fz) else { continue };
                    if land.open(j) && (land.g[j] - gy).abs() <= 1 && !land.wet_near(fx, fz) {
                        let g2 = land.g[j];
                        out.run(fx, fz, g2 + 1, g2 + 1, LEAVES[c.leaves as usize]);
                        land.top[j] = g2 + 1;
                        land.flag[j] |= LAID;
                    }
                }
            }
        }
    }
    for (t, bl) in out.split_by(|x, z| b.wave_at(x, z) + 0.3) {
        q.ev.push((t, Act::Blocks(Box::new(bl))));
    }
}

/// Blast `n`'s rubble, landing over a couple of seconds after it, and the real blocks it throws out of its crater
/// (some landing as blocks, the rest breaking up where they land; none dropping an item).
fn cp_rubble_and_thrown(q: &mut Plan, land: &mut Land, b: &Blast, big: bool) {
    let mut rng = Rng::new(u64::from(b.seed) ^ 0x7e57);
    let mut waves: Vec<Blocks> = (0..3).map(|_| Blocks { clear_of_player: true, ..Default::default() }).collect();
    const RUBBLE: [&str; 8] = [
        "minecraft:cobblestone",
        "minecraft:cobblestone",
        "minecraft:stone",
        "minecraft:coarse_dirt",
        "minecraft:dirt",
        "minecraft:cobbled_deepslate",
        "minecraft:tuff",
        "minecraft:andesite",
    ];
    let reach = b.flat_r() * 1.3;
    for _ in 0..if big { 320 } else { 60 } {
        let r = b.crater_r() * 1.05 + (reach - b.crater_r() * 1.05) * rng.next().powf(1.6);
        let a = rng.uniform(0.0, TAU);
        let (x, z) = ((b.cx + a.cos() * r).floor() as i32, (b.cz + a.sin() * r).floor() as i32);
        let Some(i) = land.known(x, z) else { continue };
        if !land.open(i) || land.wet_near(x, z) {
            continue;
        }
        let y = land.g[i] + 1;
        waves[((r / reach) * 2.99) as usize].run(x, z, y, y, *rng.pick(&RUBBLE));
        land.top[i] = y;
        land.flag[i] |= LAID;
    }
    for (k, w) in waves.into_iter().enumerate() {
        if !w.runs.is_empty() {
            q.ev.push((b.t + 1.4 + 0.9 * k as f32, Act::Blocks(Box::new(w))));
        }
    }
    // (the last's few fires left burning on its rim: on netherrack, out in the heaped earth, nothing that burns within
    // two blocks of them, so they burn on and spread to nothing)
    if big {
        let mut fires = Blocks { clear_of_player: true, ..Default::default() };
        let mut lit = 0;
        for _ in 0..80 {
            if lit >= 8 {
                break;
            }
            let a = rng.uniform(0.0, TAU);
            let r = b.crater_r() * rng.uniform(1.08, 1.28);
            let (x, z) = ((b.cx + a.cos() * r).floor() as i32, (b.cz + a.sin() * r).floor() as i32);
            let Some(i) = land.known(x, z) else { continue };
            let safe = (-2..=2).all(|dz| (-2..=2).all(|dx| land.known(x + dx, z + dz).is_some_and(|j| land.flag[j] & (DUG | HEAPED) != 0 && land.flag[j] & LAID == 0 && !land.cols[j].fluid)));
            if !safe || land.flag[i] & HEAPED == 0 || land.top[i] != land.g[i] {
                continue;
            }
            let g = land.g[i];
            fires.run(x, z, g, g, "minecraft:netherrack");
            fires.run(x, z, g + 1, g + 1, "minecraft:fire");
            land.top[i] = g + 1;
            land.flag[i] |= LAID;
            lit += 1;
        }
        if !fires.runs.is_empty() {
            q.ev.push((b.t + 2.2, Act::Blocks(Box::new(fires))));
        }
    }
    // (thrown: the ground that was there, a log of the wood round about now and then)
    let mut woods = [0u32; 9];
    let rr = b.crater_r().ceil() as i32 * 3;
    for z in (b.cz as i32 - rr..=b.cz as i32 + rr).step_by(3) {
        for x in (b.cx as i32 - rr..=b.cx as i32 + rr).step_by(3) {
            if let Some(i) = land.known(x, z)
                && land.cols[i].trunk > 0
            {
                woods[land.cols[i].wood as usize] += 1;
            }
        }
    }
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let want = if big { 120 } else { 24 };
    let mut n = 0;
    for _ in 0..want * 3 {
        if n >= want {
            break;
        }
        let r = b.crater_r() * 0.85 * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = (b.cx + a.cos() * r, b.cz + a.sin() * r);
        let (ix, iz) = (x.floor() as i32, z.floor() as i32);
        let Some(i) = land.known(ix, iz) else { continue };
        let c = land.cols[i];
        if c.fluid || land.wet_near(ix, iz) {
            continue;
        }
        let deep = rng.next();
        let blk = match (c.ground, deep) {
            (_, d) if d < 0.07 && wood.is_some() => LOG_Y[wood.unwrap_or(0)],
            (1, d) if d < 0.4 => "minecraft:grass_block",
            (1 | 2, d) if d < 0.62 => "minecraft:dirt",
            (_, d) if d < 0.74 => "minecraft:coarse_dirt",
            (_, d) if d < 0.86 => "minecraft:cobblestone",
            (_, d) if d < 0.94 => "minecraft:stone",
            _ => "minecraft:tuff",
        };
        let ang = if r > 1.0 { a } else { rng.uniform(0.0, TAU) };
        // (thrown out of a crater this big further and higher)
        let k = b.s.sqrt() * if big { 1.5 } else { 1.25 };
        let hs = (0.3 + 1.3 * rng.next().powf(1.4)) * k;
        let vy = (0.6 + 1.0 * rng.next()) * k;
        let (vx, vz) = (ang.cos() * hs, ang.sin() * hs);
        let y = f64::from(c.g) + 1.2 + 2.0 * rng.next();
        let t = b.t + 0.05 + 1.2 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

/// The chunks the land work reaches round the line, as forceload boxes a row of chunks each.
fn cp_load_boxes(blasts: &[Blast]) -> Vec<[i32; 4]> {
    let mut set = std::collections::BTreeSet::new();
    for b in blasts {
        let r = b.reach() + 4.0;
        let (c0, c1) = (((b.cx - r) / 16.0).floor() as i32, ((b.cx + r) / 16.0).floor() as i32);
        let (k0, k1) = (((b.cz - r) / 16.0).floor() as i32, ((b.cz + r) / 16.0).floor() as i32);
        for k in k0..=k1 {
            for c in c0..=c1 {
                let nx = b.cx.clamp(f64::from(c * 16), f64::from(c * 16 + 16));
                let nz = b.cz.clamp(f64::from(k * 16), f64::from(k * 16 + 16));
                if (nx - b.cx).hypot(nz - b.cz) <= r {
                    set.insert((k, c));
                }
            }
        }
    }
    let mut out: Vec<[i32; 4]> = Vec::new();
    for (k, c) in set {
        match out.last_mut() {
            Some(l) if l[1] == k * 16 && l[2] == c * 16 - 1 && (l[2] - l[0] + 1) / 16 < 32 => l[2] = c * 16 + 15,
            _ => out.push([c * 16, k * 16, c * 16 + 15, k * 16 + 15]),
        }
    }
    out
}

/// A sound of another laser's (`payload.blast_alt`), following the player, `volume` 0 to 1.
fn cue(p: &mut Plan, t: f32, event: &str, volume: f64, pitch: f64) {
    if volume > 0.001 {
        p.ev.push((t.max(0.0), Act::Sound { event: format!("orbital:{event}"), at: None, volume: volume.clamp(0.0, 1.0) as f32, pitch: pitch as f32 }));
    }
}

/// The ground carries a blow five times as fast as the air (payload.rs's PL_GROUND_V).
const GROUND_V: f64 = payload::PL_GROUND_V;
/// How much of a blast is its far take at `d` blocks: none within 220, all past 480.
fn blast_far(d: f64) -> f64 {
    let u = ((d - 220.0) / 260.0).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}

/// The bombs' sounds (tools/sounds_carpetbomb.py, round 4, after Kyle's reference: a carpet bombing run as filmed): the
/// aircraft droning over the first seconds; no falling sound; each bomb heard through the air (d/343) as a soft-fronted,
/// low, rolling blast whose rumble rolls on for seconds, so a stick landing every half second rolls into one wall of
/// sound, duller and later from the far end of the line, louder and nearer as it walks in; more far off from other
/// sticks between them. Only the last, biggest one gets the Payload's whole alternative blast, its rush and its tail,
/// and the Nuke's alternative blast under it, and the ground's thump ahead of it.
fn cp_sounds(p: &mut Plan, geo: &CpGeo, at: [f64; 3], me: [f64; 3]) {
    // (its drone following it over: five overlapping, swelling as it passes nearest, a little lower as it goes away)
    for (t, v, pitch) in [(0.1, 0.45, 1.04), (3.3, 0.7, 1.03), (6.2, 1.0, 1.0), (9.1, 0.7, 0.95), (12.0, 0.4, 0.92)] {
        cue(p, t, "carpetbomb.drone", v, pitch);
    }
    let last = CP_N - 1;
    let d_last = sound_from([at[0] + geo.bombs[last].x, at[1], at[2] + geo.bombs[last].z], me).1.max(1.0);
    for (b, bomb) in geo.bombs.iter().enumerate() {
        let w = [at[0] + bomb.x, at[1], at[2] + bomb.z];
        let (late, d) = sound_from(w, me);
        let h = |k: u32| mh(b as u32, geo.seed, 0xe10 + k);
        let arrive = bomb.t + late;
        if b == last {
            // (the ground's thump ahead of the air's blast; let down where the blast lands on top of it)
            let tg = bomb.t + (d / GROUND_V) as f32;
            let gap = f64::from(arrive - tg);
            let gv = (0.45 + 0.55 / (1.0 + d / 200.0)) * ((gap - 0.05) / 0.9).clamp(0.3, 1.0).powf(1.2);
            cue(p, tg - 0.02, "payload.ground_alt", gv.max(0.7), 0.9);
            let far = f64::from(payload::pl_far(d));
            cue(p, arrive - 0.02, "payload.blast_alt", 1.0 - far, 0.92);
            cue(p, arrive - 0.02, "payload.blast_alt_far", far, 0.92);
            // (the Nuke's under it, and the same again lower, for a deeper, longer low end)
            cue(p, arrive - 0.02, "nuke.blast_alt", 0.8, 1.0);
            cue(p, arrive - 0.02, "nuke.blast_alt", 0.5, 0.8);
            cue(p, arrive - 0.15, "payload.rush", 1.0, 1.0);
            cue(p, arrive + 2.4, "payload.tail", 1.0, 1.0);
        } else {
            // (its blast: its soft front 0.03 s into its file)
            let v = 0.35 + 0.6 * (d_last / d).min(1.0).powf(1.3);
            let fs = blast_far(d);
            let pitch = 0.94 + 0.1 * h(3);
            cue(p, arrive - 0.03, &format!("carpetbomb.blast{}", 1 + b % 4), v * (1.0 - fs), pitch);
            cue(p, arrive - 0.03, &format!("carpetbomb.blast_far{}", 1 + b % 3), v * fs, pitch);
        }
    }
    // (more of the run further off, other sticks coming down out on the land: far blasts between the line's)
    let span = geo.bombs[last - 1].t - geo.bombs[0].t;
    let extra = 9u32;
    for k in 0..extra {
        let h = |j: u32| mh(k, geo.seed, 0xe80 + j);
        let t = geo.bombs[0].t + 0.25 + (span + 0.6) * (k as f32 + 0.3 + 0.4 * h(0) as f32) / extra as f32 + (650.0 + 250.0 * h(1)) as f32 / 343.0 - 0.6;
        cue(p, t, &format!("carpetbomb.blast_far{}", 1 + k % 3), 0.22 + 0.15 * h(2), 0.9 + 0.08 * h(3));
    }
}

/// The carpet bomb. Calm a moment, a contrail drawing over; the stick falls and walks its blasts up the line to the
/// player, the last close in front of them; the dust rolling along the line and the craters smoking after.
pub(super) fn carpet_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let geo = Rc::new(CpGeo::new(shader_seed, rel));
    let last = CP_N - 1;

    // the pass's table and the debris, on the tick after it fires
    {
        let geo = geo.clone();
        p.later(0.05, move |q| {
            q.ev.push((0.05, Act::Table(cp_bomb_words(&geo, &[]))));
            q.ev.push((0.05, Act::Words { index: CP_DB as u32, words: cp_debris_words(&geo) }));
        });
    }
    // the land's shape round the line for the dust to hug, and each bomb's ground, asked of the world as it starts
    {
        let dme = rel[0].hypot(rel[2]);
        let span = -geo.bombs[0].along + 90.0;
        let reach = (dme * 1.25 + 150.0).max(span).clamp(260.0, 1150.0);
        let mut columns = payload::pl_hf_columns(bx, bz, reach);
        columns.extend(geo.bombs.iter().map(|b| ((cx + b.x).floor() as i32, (cz + b.z).floor() as i32)));
        let columns = Rc::new(columns);
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        let geo = geo.clone();
        p.later(0.4, move |q| cp_hf_step(q, tag, columns, reach, rel, by + 1, geo, 0.4));
    }

    cp_sounds(&mut p, &geo, [cx, gy, cz], me);
    for (b, bomb) in geo.bombs.iter().enumerate() {
        let big = b == last;
        let (wx, wz) = (cx + bomb.x, cz + bomb.z);
        let (ix, iz) = (wx.floor() as i32, wz.floor() as i32);
        let (late, d) = sound_from([wx, gy, wz], me);
        let arrive = bomb.t + late;
        // (the jolt as each front reaches them, harder the nearer, the last's the hardest; the ground's faint one first)
        let fo = (1.5 / (1.0 + d / 300.0)).clamp(0.15, 1.0) as f32 * if big { 1.0 } else { 0.6 };
        let tg = bomb.t + (d / GROUND_V) as f32;
        if arrive - tg > 0.08 {
            p.shake(tg, 0.4 * fo, 0.3);
        }
        if big {
            // (the last's the Nuke's jolt: kicked again and again through the hit, a long heavy shudder after)
            super::nuke::nk_jolt(&mut p, arrive, (2.4 / (1.0 + d / 500.0)).clamp(0.35, 1.0) as f32);
        } else {
            payload::pl_jolt(&mut p, arrive, fo);
        }
        if big {
            let mut ts = arrive + 2.6;
            while ts < arrive + 7.0 {
                let s = p.rng.uniform(0.04, 0.1) as f32 * fo;
                let du = p.rng.uniform(0.3, 0.6) as f32;
                p.shake(ts, s, du);
                ts += p.rng.uniform(0.5, 1.2) as f32;
            }
            // (and the last one's front throws them back a little, if they are near enough)
            p.ev.push((arrive, Act::Shove { from: [wx, gy, wz], out: 0.75, up: 0.5, reach: 320.0 }));
        }
        // (what lives there killed, real smoke and grit for anyone close)
        let kill = Blast { cx: wx, cz: wz, t: bomb.t, s: bomb.s, ph: [0.0; 3], seed: 0, big }.kill_r().round() as i32;
        for t in if big { vec![0.1, 1.5, 4.0] } else { vec![0.1, 1.5] } {
            p.at(bomb.t + t, surf(ix, iz, &format!("kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{kill}]")));
        }
        p.at(bomb.t + 0.1, surf(ix, iz, &format!("particle minecraft:explosion_emitter ~ ~2 ~ {0} 2 {0} 0 {1} force", if big { 5 } else { 3 }, if big { 6 } else { 3 })));
        p.at(bomb.t + 0.2, surf(ix, iz, &format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} ~ ~4 ~ {0} 4 {0} 0.8 {1} force"#, if big { 12 } else { 7 }, if big { 300 } else { 120 })));
        for k in 0..if big { 6 } else { 2 } {
            p.at(bomb.t + 1.0 + 1.6 * k as f32, surf(ix, iz, "particle minecraft:campfire_signal_smoke ~ ~1 ~ 6 2 6 0.02 16 force"));
        }
    }

    if terrain {
        let blasts: Rc<Vec<Blast>> = Rc::new(
            geo.bombs
                .iter()
                .map(|b| {
                    let r = |k: u32| mh(b.h, geo.seed, 0xc10 + k);
                    Blast { cx: cx + b.x, cz: cz + b.z, t: b.t, s: b.s, ph: [TAU * r(1), TAU * r(2), TAU * r(3)], seed: b.h ^ geo.seed, big: b.s > 1.4 }
                })
                .collect(),
        );
        for [x0, z0, x1, z1] in cp_load_boxes(&blasts) {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        let land: Shared = Rc::new(RefCell::new(Land::new(&blasts)));
        // the land read as it starts (a query and a stage a part), taken in a stage a part
        let tags: Rc<Vec<u32>> = Rc::new((0..CP_READS).map(|_| crate::columns::new_tag()).collect());
        // (asked four parts a stage: working out which columns is cheap, taking the answers in is the work)
        for batch in 0..CP_READS.div_ceil(4) {
            let (tags, blasts, land) = (tags.clone(), blasts.clone(), land.clone());
            let t = 0.1 + 0.05 * batch as f32;
            p.later(t, move |q| {
                let (x0, z0, w, h) = {
                    let l = land.borrow();
                    (l.x0, l.z0, l.w, l.h)
                };
                for part in batch * 4..(batch * 4 + 4).min(CP_READS) {
                    let columns = cp_read_columns(&blasts, x0, z0, w, h, part);
                    q.ev.push((t, Act::Read { tag: tags[part], columns, below: PL_BELOW, above: PL_ABOVE }));
                }
            });
        }
        {
            let land = land.clone();
            let until = geo.bombs[last].t - CP_LEAD - 0.5;
            p.later(0.35, move |q| cp_land_step(q, land, tags, 0, 0.35, until, 0));
        }
        // each bomb's work in a window of its own before it strikes, in order: its blast a band of rows a stage, what it
        // leaves hanging, its felled trees, its rubble and thrown blocks
        for (n, b) in blasts.iter().enumerate() {
            let b = *b;
            let n8 = n as u8;
            // (the last's work in a longer window of its own, from just after the one before it is done)
            let t0 = b.t - if b.big { CP_LEAD + 0.6 } else { CP_LEAD };
            let rows = 2 * b.reach().ceil() as i32 + 1;
            // (the last's land in more, smaller stages: nothing waits after it)
            let parts = if b.big { 40 } else { CP_PARTS };
            let per = (rows + parts - 1) / parts;
            let mut k = 0;
            for j in 0..parts {
                let l = land.clone();
                let (k0, k1) = (j * per, ((j + 1) * per).min(rows));
                p.later(t0 + 0.05 * k as f32, move |q| cp_blast_rows(q, &mut l.borrow_mut(), &b, n8, k0, k1));
                k += 1;
            }
            let tparts = if b.big { 8 } else { 1 };
            for j in 0..tparts {
                let l = land.clone();
                let (k0, k1) = (j * rows / tparts, (j + 1) * rows / tparts);
                p.later(t0 + 0.05 * k as f32, move |q| cp_tidy(q, &l.borrow(), &b, n8, k0, k1));
                k += 1;
            }
            let fparts = if b.big { 8 } else { 1 };
            for j in 0..fparts {
                let l = land.clone();
                let (k0, k1) = (j * rows / fparts, (j + 1) * rows / fparts);
                p.later(t0 + 0.05 * k as f32, move |q| cp_felled(q, &mut l.borrow_mut(), &b, k0, k1));
                k += 1;
            }
            let l = land.clone();
            let big = n == last;
            p.later(t0 + 0.05 * k as f32, move |q| cp_rubble_and_thrown(q, &mut l.borrow_mut(), &b, big));
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// The heightfield and each bomb's ground, once the world has answered (asking again a little later until it has).
#[allow(clippy::too_many_arguments)]
fn cp_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, me: [f64; 3], gy: i32, geo: Rc<CpGeo>, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < geo.bombs[CP_N - 1].t {
            q.later(at_t + 0.2, move |q| cp_hf_step(q, tag, columns, reach, me, gy, geo, at_t + 0.2));
        }
        return;
    }
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    let nh = payload::PL_HN * payload::PL_HN;
    crate::meter::spend(400 * nh as u64);
    let h = payload::pl_hf_ground(&heights[..nh], reach, me);
    let flat = vec![0.0; h.len()];
    q.ev.push((at_t, Act::Words { index: payload::PL_HF as u32, words: payload::pl_hf_pack(&h, &flat, reach) }));
    // (a bomb's own column not answered: the heightfield's ground there)
    let ys: Vec<f64> = (0..CP_N).map(|i| heights[nh + i].unwrap_or_else(|| nearest(&h, reach, geo.bombs[i].x, geo.bombs[i].z))).collect();
    q.ev.push((at_t, Act::Words { index: 0, words: cp_bomb_words(&geo, &ys) }));
}
/// The heightfield's ground nearest (x, z) (from the target).
fn nearest(h: &[f64], reach: f64, x: f64, z: f64) -> f64 {
    let n = payload::PL_HN;
    let step = 2.0 * reach / (n - 1) as f64;
    let i = ((x + reach) / step).round().clamp(0.0, (n - 1) as f64) as usize;
    let k = ((z + reach) / step).round().clamp(0.0, (n - 1) as f64) as usize;
    h[k * n + i]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    const AT: Target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };

    /// The player `d` blocks (level) from the target, `a` round from south.
    fn me_at(d: f64, a: f64) -> [f64; 3] {
        [10.5 + d * a.sin(), 70.0, -2.5 + d * a.cos()]
    }

    #[test]
    fn carpet_bombs_walk_a_line_up_to_the_player() {
        for d in [5.0, 40.0, 120.0, 300.0, 900.0] {
            for a in [0.0, 1.0, 2.6, 4.4] {
                let me = me_at(d, a);
                let rel = [me[0] - 10.5, me[1] - 65.0, me[2] + 2.5];
                let g = CpGeo::new(37.0, rel);
                assert_eq!(g.bombs.len(), CP_N);
                let dme = |b: &Bomb| (rel[0] - b.x).hypot(rel[2] - b.z);
                for w in g.bombs.windows(2) {
                    // in order along the line, each nearer the player, a little under a second apart
                    assert!(w[1].along > w[0].along + 15.0 && w[1].along < w[0].along + 30.0, "{d} {a}: {:?}", g.bombs);
                    assert!(dme(&w[1]) < dme(&w[0]), "{d} {a}");
                    let gap = w[1].t - w[0].t;
                    assert!((0.5..=1.05).contains(&gap), "{gap}");
                }
                let lastb = g.bombs[CP_N - 1];
                // the last the biggest and nearest, on the target unless that was too close, never on the player
                assert!(g.bombs.iter().all(|b| b.s <= lastb.s) && lastb.s > 1.4);
                assert!(g.bombs.iter().all(|b| dme(b) >= CP_MIN_ME - 1.0), "{d} {a}");
                if d >= CP_MIN_ME {
                    assert!(lastb.x.hypot(lastb.z) < 1e-6);
                } else {
                    assert!((dme(&lastb) - CP_MIN_ME).abs() < 1.0, "{}", dme(&lastb));
                }
                // a line: none strays more than a few blocks off it
                for b in &g.bombs {
                    let off = (b.x - lastb.x) * -g.dir[1] + (b.z - lastb.z) * g.dir[0];
                    assert!(off.abs() < 5.0, "{off}");
                }
                // the stick's walk at the bomber's speed, about the spacing a gap
                assert!((g.vb - CP_SPACING / f64::from(CP_GAP)).abs() < 6.0, "{}", g.vb);
                // the bomber lets each bomb go well before it strikes, the stick over CP_RIPPLE as it comes over the line
                for (k, b) in g.bombs.iter().enumerate() {
                    let rel = CP_RELEASE + CP_RIPPLE * k as f32 / (CP_N - 1) as f32;
                    assert!(rel > CP_APPEAR + 3.5 && b.t - rel > 2.0, "bomb {k} let go at {rel}, strikes at {}", b.t);
                }
                // and the length: the last blast's dust has time to settle
                assert!(lastb.t < crate::lasers::CARPET_BOMB.length - 18.0);
            }
        }
    }

    /// A wood on rolling land (its ground about 64), oaks now and then.
    fn ground_h(x: i32, z: i32) -> i32 {
        (64.0 + 3.0 * (f64::from(x) * 0.05).sin() * (f64::from(z) * 0.04).cos()).round() as i32
    }
    fn tree(x: i32, z: i32) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 0.985
    }
    fn column(x: i32, z: i32) -> Option<(i32, Vec<&'static str>)> {
        let g = ground_h(x, z);
        let t = tree(x, z);
        let block = |y: i32| -> &'static str {
            if y < g - 3 {
                "minecraft:stone"
            } else if y < g {
                "minecraft:dirt"
            } else if y == g {
                "minecraft:grass_block"
            } else if t && y <= g + 6 {
                "minecraft:oak_log"
            } else if t && y <= g + 8 && y >= g + 4 {
                "minecraft:oak_leaves"
            } else if y == g + 1 && (x + z) % 3 == 0 {
                "minecraft:short_grass"
            } else {
                "minecraft:air"
            }
        };
        let top = if t { g + 9 } else { g + 2 };
        let (below, above) = (PL_BELOW as i32, PL_ABOVE as i32);
        Some((top, (top - below..top + above).map(block).collect()))
    }
    fn played(terrain: bool, me: [f64; 3]) -> crate::strike::sim::Played {
        let ev = plan(&crate::lasers::CARPET_BOMB, &AT, terrain, "minecraft:overworld", 37.0, me, 0);
        crate::strike::sim::play(ev, crate::lasers::CARPET_BOMB.length, &|x, z, _, _| column(x, z))
    }
    fn words(f: &str) -> Vec<i32> {
        f.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap_or(0)).collect()
    }

    #[test]
    fn carpet_leaves_a_row_of_craters_and_fells_the_trees() {
        let me = me_at(130.0, 0.4);
        let rel = [me[0] - 10.5, me[1] - 65.0, me[2] + 2.5];
        let g = CpGeo::new(37.0, rel);
        let p = played(true, me);
        let fills: Vec<String> = p.edits.iter().flat_map(|(_, _, b)| b.as_fills()).collect();
        assert!(!fills.is_empty());
        for f in &fills {
            for bad in ["lava ", "water ", "magma", "sand ", "concrete_powder"] {
                assert!(!f.contains(&format!(" minecraft:{bad}")) || f.contains(" replace "), "{f}");
            }
        }
        // every bomb's middle dug about its depth (none filled again by the next one's rim)
        for b in &g.bombs {
            let (x, z) = ((10.5 + b.x).floor() as i32, (-2.5 + b.z).floor() as i32);
            let dug = fills.iter().filter(|f| f.starts_with(&format!("fill {x} ")) && f.contains(&format!(" {z} {x} ")) && f.contains("minecraft:air")).map(|f| words(f)[1]).min().expect("the middle dug");
            let depth = ground_h(x, z) - (dug - 1);
            let want = b.s * if b.s > 1.4 { 10.6 } else { 8.0 };
            assert!((f64::from(depth) - want).abs() <= 2.0, "bomb at {x} {z}: {depth} deep, not {want:.1}");
            assert!(!fills.iter().any(|f| f.starts_with(&format!("fill {x} ")) && f.contains(&format!(" {z} {x} ")) && (f.contains("dirt") || f.contains("cobble") || f.contains("stone")) && !f.contains("replace") && words(f)[1] > ground_h(x, z) - 1), "the middle at {x} {z} heaped over");
        }
        // the last's few fires, each on netherrack, nothing else set alight
        let fires: Vec<&String> = fills.iter().filter(|f| f.contains(" minecraft:fire")).collect();
        assert!(!fires.is_empty() && fires.len() <= 8, "{} fires", fires.len());
        for f in &fires {
            let w = words(f);
            assert!(fills.iter().any(|n| n.contains("minecraft:netherrack") && words(n) == vec![w[0], w[1] - 1, w[2]]), "{f} not on netherrack");
        }
        // the craters: the last's about 65 across (dug two or more under the land), and the small ones' run into one
        // trench (the ground half way between each two dug)
        let lb = g.bombs[CP_N - 1];
        let (lx, lz) = (10.5 + lb.x, -2.5 + lb.z);
        let mut dug = std::collections::HashSet::new();
        for f in fills.iter().filter(|f| f.contains("minecraft:air") && !f.contains("replace")) {
            let w = words(f);
            if w[1] <= ground_h(w[0], w[2]) - 1 {
                dug.insert((w[0], w[2]));
            }
        }
        let big = dug.iter().filter(|(x, z)| (f64::from(*x) + 0.5 - lx).hypot(f64::from(*z) + 0.5 - lz) < 45.0).count();
        let want = std::f64::consts::PI * (21.0 * lb.s).powi(2);
        assert!((big as f64) > 0.7 * want && (big as f64) < 1.4 * want, "the last's crater {big} columns, not about {want:.0}");
        let mut joined = 0;
        for w in g.bombs[..CP_N - 1].windows(2) {
            let (mx, mz) = ((10.5 + 0.5 * (w[0].x + w[1].x)).floor() as i32, (-2.5 + 0.5 * (w[0].z + w[1].z)).floor() as i32);
            joined += usize::from(dug.contains(&(mx, mz)));
        }
        assert!(joined >= CP_N - 4, "only {joined} of the small craters run into the next");
        // trees felled, lying along x or z (some out past 120 blocks from the last)
        let far_felled = fills
            .iter()
            .filter(|f| f.contains("_log[axis="))
            .filter(|f| {
                let w = words(f);
                (f64::from(w[0]) + 0.5 - lx).hypot(f64::from(w[2]) + 0.5 - lz) > 120.0
            })
            .count();
        assert!(far_felled > 3, "{far_felled} trees felled past 120");
        let lying = fills.iter().filter(|f| f.contains("_log[axis=")).count();
        assert!(lying > 30, "{lying}");
        // nothing laid where the player stands
        for (_, _, b) in &p.edits {
            if b.clear_of_player {
                continue;
            }
            for r in &b.runs {
                let laid = !b.edit().palette[r.block as usize].contains("air");
                assert!(!laid || !crate::strike::in_player(r.x, r.z, r.y, r.y + r.height as i32 - 1, me) || r.only.is_some());
            }
        }
        // and it goes in on time, each blast's edits from its own front out
        for (t, due, _) in &p.edits {
            assert!(t - due < 0.25, "an edit {:.2} s late", t - due);
        }
        // thrown blocks, out of each crater as it strikes, and never killed in the air
        let thrown: Vec<&(f32, String)> = p.cmds.iter().filter(|(_, c)| c.starts_with("summon minecraft:falling_block")).collect();
        assert!(thrown.len() > 250 && thrown.len() <= (CP_N - 1) * 24 + 120, "{}", thrown.len());
        assert!(p.cmds.iter().filter(|(_, c)| c.contains("kill @e")).all(|(_, c)| c.contains("type=!minecraft:falling_block") && c.contains("type=!minecraft:player")));
    }

    #[test]
    fn carpet_spreads_each_craters_work_over_its_own_stages() {
        let me = me_at(160.0, 2.0);
        let rel = [me[0] - 10.5, me[1] - 65.0, me[2] + 2.5];
        let g = CpGeo::new(37.0, rel);
        let p = played(true, me);
        // each bomb's land worked out on several stages of its own, all before it strikes, none slow
        for (n, b) in g.bombs.iter().enumerate() {
            let win = p.stages.iter().filter(|s| s.1 >= b.t - CP_LEAD - 0.01 && s.1 < b.t).count();
            assert!(win >= CP_PARTS as usize + 3, "bomb {n}: {win} stages");
        }
        for (due, ran, ms) in &p.stages {
            assert!(ran - due < 0.6, "a stage due at {due} ran at {ran}");
            if !cfg!(debug_assertions) {
                assert!(*ms < 25.0, "a stage due at {due} took {ms} ms");
            }
        }
        // the edits go in a wave a blast, never all of a crater on one tick
        let mut ticks = std::collections::BTreeMap::new();
        for (t, _, b) in &p.edits {
            *ticks.entry((t * 20.0).round() as i32).or_insert(0usize) += b.runs.len();
        }
        assert!(ticks.len() > 40, "{} ticks", ticks.len());
        let most = ticks.values().max().copied().unwrap_or(0);
        let all: usize = ticks.values().sum();
        assert!(most * 6 < all, "{most} of {all} runs on one tick");
    }

    #[test]
    fn carpet_reads_every_column_within_a_blasts_reach_and_no_more() {
        let g = CpGeo::new(37.0, [140.0, 5.0, -260.0]);
        let blasts: Vec<Blast> = g.bombs.iter().map(|b| Blast { cx: 10.5 + b.x, cz: -2.5 + b.z, t: b.t, s: b.s, ph: [0.0; 3], seed: 1, big: b.s > 1.4 }).collect();
        let land = Land::new(&blasts);
        let mut got: Vec<(i32, i32)> = (0..CP_READS).flat_map(|p| cp_read_columns(&blasts, land.x0, land.z0, land.w, land.h, p)).collect();
        let mut want = Vec::new();
        for k in 0..land.h {
            for i in 0..land.w {
                let (x, z) = (land.x0 + i, land.z0 + k);
                if blasts.iter().any(|b| (f64::from(x) + 0.5 - b.cx).hypot(f64::from(z) + 0.5 - b.cz) <= b.reach() + 1.0) {
                    want.push((x, z));
                }
            }
        }
        got.sort_unstable();
        want.sort_unstable();
        let n = got.len();
        got.dedup();
        assert_eq!(n, got.len(), "a column read twice");
        assert_eq!(got.len(), want.len());
        assert!(got.iter().zip(&want).filter(|(a, b)| a != b).count() * 200 < want.len(), "the spans' edges off by more than rounding");
    }

    #[test]
    fn carpet_leaves_the_land_alone_with_the_terrain_off() {
        let p = played(false, me_at(130.0, 0.4));
        assert!(p.edits.is_empty());
        assert!(!p.cmds.iter().any(|(_, c)| c.contains("falling_block {") || c.starts_with("forceload")));
    }

    fn cues(me: [f64; 3]) -> Vec<(f32, String, f32, f32)> {
        let ev = plan(&crate::lasers::CARPET_BOMB, &AT, false, "minecraft:overworld", 37.0, me, 0);
        let mut v: Vec<(f32, String, f32, f32)> = ev
            .into_iter()
            .filter_map(|(t, a)| match a {
                Act::Sound { event, volume, pitch, at } => {
                    assert!(at.is_none());
                    Some((t, event, volume, pitch))
                }
                _ => None,
            })
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        v
    }

    /// Only sounds the owner approved, each with its file; each blast late by its distance, the ground's thump ahead
    /// of it; never two blasts in a row the same; the last the loudest.
    #[test]
    fn carpet_sounds_are_the_approved_ones_timed_by_distance() {
        // (the carpet bomb's own, tools/sounds_carpetbomb.py's, and for the last bomb approved ones as they are)
        let approved = [
            "carpetbomb.drone", "carpetbomb.blast1", "carpetbomb.blast2", "carpetbomb.blast3", "carpetbomb.blast4", "carpetbomb.blast_far1",
            "carpetbomb.blast_far2", "carpetbomb.blast_far3", "payload.ground_alt", "payload.blast_alt", "payload.blast_alt_far", "payload.rush",
            "payload.tail", "nuke.blast_alt",
        ];
        let events = std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../orbital-sounds/assets/orbital/sounds.json")).unwrap();
        for d in [70.0, 150.0, 600.0, 1400.0] {
            let me = me_at(d, 0.7);
            let rel = [me[0] - 10.5, me[1] - 65.0, me[2] + 2.5];
            let g = CpGeo::new(37.0, rel);
            let c = cues(me);
            for (t, e, v, pitch) in &c {
                let k = e.strip_prefix("orbital:").unwrap();
                assert!(approved.contains(&k), "{k} isn't an approved sound");
                assert!(events.contains(&format!("\"{k}\"")), "{k} not in sounds.json");
                assert!(*t >= 0.0 && *v > 0.0 && *v <= 1.0 && (0.78..=1.1).contains(pitch), "{k} at {t}: {v} {pitch}");
            }
            let blasts: Vec<&(f32, String, f32, f32)> = c.iter().filter(|e| e.1.contains("payload.blast_alt") || e.1.contains("carpetbomb.blast")).collect();
            // (no falling sound; only the last bomb gets the whole blast)
            assert!(!c.iter().any(|e| e.1.contains("fall") || e.1.contains("whistle")));
            let lb = g.bombs[CP_N - 1];
            let heard_last = lb.t + sound_from([10.5 + lb.x, 65.0, -2.5 + lb.z], me).0;
            for e in c.iter().filter(|e| e.1.contains("payload.blast_alt") || e.1.contains("nuke.") || e.1.contains("rush") || e.1.contains("tail")) {
                assert!(e.0 > heard_last - 0.2, "{d}: {} at {} before the last bomb's blast", e.1, e.0);
            }
            for e in c.iter().filter(|e| e.1.contains("carpetbomb.blast")) {
                assert!(len_of(&e.1) < 6.5, "{} is long", e.1);
            }
            for (n, b) in g.bombs.iter().enumerate() {
                let (late, _) = sound_from([10.5 + b.x, 65.0, -2.5 + b.z], me);
                let heard: Vec<_> = blasts.iter().filter(|e| (e.0 - (b.t + late)).abs() < 0.05).collect();
                assert!(!heard.is_empty(), "{d}: bomb {n}'s blast at {}", b.t + late);
                if n == CP_N - 1 {
                    let thump = c.iter().filter(|e| e.1.ends_with("ground_alt")).map(|e| e.0).filter(|t| *t > b.t - 0.05 && *t < b.t + late + 0.01).count();
                    assert!(thump >= 1, "{d}: the last bomb's thump");
                }
            }
            let loud = |n: usize| blasts.iter().filter(|e| (e.0 - (g.bombs[n].t + sound_from([10.5 + g.bombs[n].x, 65.0, -2.5 + g.bombs[n].z], me).0)).abs() < 0.035).map(|e| e.2).fold(0.0, f32::max);
            for n in 0..CP_N - 1 {
                assert!(loud(n) < loud(CP_N - 1), "{d}: bomb {n} as loud as the last");
            }
            // (the opening never silent: the aircraft's drone from the start)
            assert!(c.first().is_some_and(|e| e.0 < 0.5 && e.1.contains("drone")));
        }
    }

    /// A sound file's length in seconds, from its last Ogg page's granule position (44.1 kHz).
    fn len_of(event: &str) -> f32 {
        let file = event.strip_prefix("orbital:").unwrap_or(event).replacen('.', "/", 1);
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("../orbital-sounds/assets/orbital/sounds/{file}.ogg"));
        let b = std::fs::read(&path).unwrap_or_else(|_| panic!("{event} has no file"));
        let i = (0..b.len() - 14).rev().find(|&i| &b[i..i + 4] == b"OggS").expect("an Ogg page");
        u64::from_le_bytes(b[i + 6..i + 14].try_into().unwrap()) as f32 / 44_100.0
    }

    /// `CP_ME=300 CP_OUT=path cargo test --release cp_write_cues -- --ignored`: the strike's sounds as the player CP_ME
    /// blocks from the target hears them, `t event volume pitch` a line, for tools/sounds_carpetbomb.py's `--mix`.
    #[test]
    #[ignore]
    fn cp_write_cues() {
        let d: f64 = std::env::var("CP_ME").map_or(300.0, |v| v.parse().unwrap());
        let out: String = cues(me_at(d, 0.7)).iter().map(|(t, e, v, p)| format!("{t:.3} {e} {v:.3} {p:.3}\n")).collect();
        std::fs::write(std::env::var("CP_OUT").unwrap(), out).unwrap();
    }

    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z cargo test --release cp_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the target's ground at the preview's (0.5 65 0.5).
    #[test]
    #[ignore]
    fn cp_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 65.0, 120.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let g = CpGeo::new(seed, rel);
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let ground = |x: f64, z: f64| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        let ys: Vec<f64> = g.bombs.iter().map(|b| ground(b.x + 0.5, b.z + 0.5)).collect();
        let mut w = cp_bomb_words(&g, &ys);
        let reach = (rel[0].hypot(rel[2]) * 1.25 + 150.0).max(-g.bombs[0].along + 90.0).clamp(260.0, 1150.0);
        let heights: Vec<Option<f64>> = payload::pl_hf_columns(0, 0, reach).iter().map(|&(x, z)| Some(ground(f64::from(x) + 0.5, f64::from(z) + 0.5))).collect();
        let h = payload::pl_hf_ground(&heights, reach, rel);
        let hf = payload::pl_hf_pack(&h, &vec![0.0; h.len()], reach);
        w.resize(payload::PL_HF + hf.len(), 0);
        w[payload::PL_HF..].copy_from_slice(&hf);
        let db = cp_debris_words(&g);
        w.resize(CP_DB + db.len(), 0);
        w[CP_DB..].copy_from_slice(&db);
        let out: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), out).unwrap();
    }
}
