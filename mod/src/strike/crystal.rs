//! The crystal bloom's plan: the land waking, the first shards punching up, the bloom, the resonance and the
//! detonation, with their sounds; then what it leaves in real blocks: the geode crater round a crystal-lined well to
//! bedrock where the heart stood, the stumps of the spires where they stood (cut as the pass breaks them), the broken
//! pieces lying by them, the shards that were thrown out lying where they came down, the fissures and the land frosted
//! over with crystal. shaders/crystalbloom.wgsl draws the same spires, breaks them at the same heights and throws the
//! same shards (cb_*): keep the two in step.
use super::{Act, Blocks, Plan, Rng, Target, bedrock_top, falloff, mh, pk_cells, pk_load_rows, sky_top, sound_from, vnoise, wing_angle};
use crate::lasers::Laser;
use std::f64::consts::PI;

const TAU: f64 = 2.0 * PI;
pub(super) const CB_N: usize = 46;
pub(super) const CB_LEADS: usize = 6;
const CB_FIELD: f64 = 150.0;
const CB_SINK: f64 = 40.0;
const CB_PUNCH0: f32 = 3.5;
const CB_PUNCH_DT: f32 = 0.62;
const CB_BULGE: f32 = 0.7;
const CB_STRUGGLE: f32 = 0.9;
const CB_BLOOM0: f32 = 7.6;
const CB_BLOOM_V: f32 = 4.6;
const CB_RES: f32 = 14.0;
pub(super) const CB_DET: f32 = 22.0;
pub(super) const CB_FRAGS: usize = 96;
const CB_G: f64 = 22.0;
/// The crater: CB_BOWL round (its edge wandering), CB_BOWL_D deep in the middle, a well CB_WELL round down to bedrock
/// where the heart stood; dug a chunk column at a time from the middle out at CB_DIG_V blocks a second (cb_dig_t).
pub(super) const CB_BOWL: f64 = 88.0;
pub(super) const CB_BOWL_D: f64 = 28.0;
const CB_WELL: f64 = 10.0;
const CB_DIG_V: f64 = 70.0;
/// How far behind cb_dig_t a chunk column may be dug (as blocks further out): strike.wgsl waits for that and the chunk
/// round a point (CB_SLACK + 12 out) before it shows it open.
const CB_SLACK: f64 = 8.0;
/// The fissures: CB_CRACKS from the crater out to CB_CRACK_R at most, opening as the shock (CB_SHOCK_V) reaches them.
pub(super) const CB_CRACKS: usize = 9;
const CB_CRACK_R: f64 = 205.0;
const CB_SHOCK_V: f64 = 170.0;
/// The land blown clear out to CB_BLAST, CB_ABOVE up (to the sky over the middle, out to CB_CORE); frosted with crystal
/// out to CB_FROST; shards strewn out to CB_STREW; the chunks out to CB_LOAD kept loaded while it works.
pub(super) const CB_BLAST: f64 = 130.0;
const CB_ABOVE: i32 = 24;
const CB_CORE: f64 = 16.0;
const CB_FROST: f64 = 165.0;
pub(super) const CB_STREW: f64 = 235.0;
const CB_THROW: f64 = 225.0;
const CB_LOAD: f64 = 240.0;

/// Each crystal colour's blocks: its body, its glassy skin, the bands across it, and the glowing heart down its middle.
/// In the order of strike.wgsl's cb_hue: violet, magenta, rose, ice, cyan, deep blue.
const CB_FAMILY: [[&str; 4]; 6] = [
    ["minecraft:amethyst_block", "minecraft:purple_stained_glass", "minecraft:magenta_stained_glass", "minecraft:pearlescent_froglight"],
    ["minecraft:amethyst_block", "minecraft:magenta_stained_glass", "minecraft:pink_stained_glass", "minecraft:pearlescent_froglight"],
    ["minecraft:calcite", "minecraft:pink_stained_glass", "minecraft:magenta_stained_glass", "minecraft:pearlescent_froglight"],
    ["minecraft:quartz_block", "minecraft:white_stained_glass", "minecraft:light_blue_stained_glass", "minecraft:sea_lantern"],
    ["minecraft:packed_ice", "minecraft:light_blue_stained_glass", "minecraft:cyan_stained_glass", "minecraft:sea_lantern"],
    ["minecraft:blue_ice", "minecraft:blue_stained_glass", "minecraft:light_blue_stained_glass", "minecraft:sea_lantern"],
];
/// The colour the pass shows a hue in once they have burst (its colours turned that far by then).
fn cb_family(hue: f64) -> usize {
    (((hue + 0.45).rem_euclid(1.0)) * 6.0) as usize % 6
}

fn smoothstep(a: f64, b: f64, x: f64) -> f64 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Spire i: its foot off the target (x, z), when it sets off, how tall it grows (strike.wgsl's cb_place).
pub(super) fn cb_place(i: usize, seed: f32) -> [f64; 4] {
    let s = seed as u32;
    let u = i as u32;
    if i < 5 {
        let a = mh(0, s, 1) * TAU + i as f64 * 2.39996 + (mh(u, s, 2) - 0.5) * 0.5;
        let r = 42.0 + 34.0 * mh(u, s, 3);
        let t = f64::from(CB_PUNCH0) + i as f64 * f64::from(CB_PUNCH_DT) + (mh(u, s, 4) - 0.5) * 0.12;
        return [a.cos() * r, a.sin() * r, t, 190.0 + 90.0 * mh(u, s, 5)];
    }
    if i == 5 {
        return [(mh(u, s, 3) - 0.5) * 4.0, (mh(u, s, 4) - 0.5) * 4.0, f64::from(CB_PUNCH0) + 5.0 * f64::from(CB_PUNCH_DT) + 0.1, 330.0];
    }
    let c = (i - 6) / 4;
    let j = (i - 6) % 4;
    let fc = c as f64;
    let ac = mh(7, s, 6) * TAU + fc * 2.39996 + (mh(c as u32, s, 7) - 0.5) * 0.4;
    let rc = 34.0 + 108.0 * ((fc + 0.5) / 10.0).sqrt() + (mh(c as u32, s, 8) - 0.5) * 16.0;
    let (mut x, mut z) = (ac.cos() * rc, ac.sin() * rc);
    if j > 0 {
        let aj = ac + (j as f64 - 2.0) * 1.9 + (mh(u, s, 9) - 0.5) * 1.2;
        let dj = 7.0 + 11.0 * mh(u, s, 10);
        x += aj.cos() * dj;
        z += aj.sin() * dj;
    }
    let r = x.hypot(z);
    let big = if j == 0 { 0.75 + 0.25 * mh(u, s, 11) } else { 0.25 + 0.45 * mh(u, s, 11) };
    let h = (36.0 + 230.0 * big * big) * (1.0 - 0.45 * (r / CB_FIELD).clamp(0.0, 1.0));
    let t = f64::from(CB_BLOOM0) + f64::from(CB_BLOOM_V) * (r / CB_FIELD).clamp(0.0, 1.0) + 0.35 * mh(u, s, 12) + 0.12 * j as f64;
    [x, z, t, h]
}
/// Spire i's radius, lean off upright, which way it leans, and its turn about its axis (strike.wgsl's cb_form).
pub(super) fn cb_form(i: usize, seed: f32, p: [f64; 4]) -> [f64; 4] {
    let s = seed as u32;
    let u = i as u32;
    let out = p[1].atan2(p[0]);
    if i == 5 {
        return [30.0, 0.035, mh(u, s, 13) * TAU, mh(u, s, 14) * TAU];
    }
    let mut r = 5.0 + p[3] * 0.065 + 3.0 * mh(u, s, 15);
    let mut lean = 0.14 + 0.36 * mh(u, s, 16);
    let mut hd = out + (mh(u, s, 17) - 0.5) * 1.3;
    if i < 5 {
        r = 14.0 + 5.0 * mh(u, s, 15);
        lean = 0.08 + 0.14 * mh(u, s, 16);
    } else if (i - 6) % 4 > 0 {
        let c = (i - 6) / 4;
        let m = cb_place(6 + c * 4, seed);
        hd = (p[1] - m[1]).atan2(p[0] - m[0]) + (mh(u, s, 17) - 0.5) * 0.7;
        lean = 0.3 + 0.45 * mh(u, s, 16);
    }
    [r, lean, hd, mh(u, s, 14) * TAU]
}
/// Where spire i breaks as they burst: the height up its axis (0: it shatters whole), and the break's tilt across it
/// (strike.wgsl's cb_break).
pub(super) fn cb_break(i: usize, seed: f32, h: f64) -> [f64; 3] {
    let s = seed as u32;
    let u = i as u32;
    if i == 5 {
        return [0.0; 3];
    }
    let bh = (h * (0.1 + 0.26 * mh(u, s, 18))).clamp(7.0, 64.0);
    let ta = mh(u, s, 19) * TAU;
    let tl = 0.25 + 0.55 * mh(u, s, 20);
    [bh, ta.cos() * tl, ta.sin() * tl]
}
fn cb_hue(i: usize, seed: f32, p: [f64; 4]) -> f64 {
    (0.13 * i as f64 + mh(i as u32, seed as u32, 23) * 0.18 + p[1].atan2(p[0]) / TAU * 0.6).rem_euclid(1.0)
}
fn cross(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn dot(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn norm(a: [f64; 3]) -> [f64; 3] {
    let l = dot(a, a).sqrt().max(1e-12);
    [a[0] / l, a[1] / l, a[2] / l]
}
/// A frame round axis `a`, turned `rot` about it (strike.wgsl's cb_frame).
fn cb_frame(a: [f64; 3], rot: f64) -> ([f64; 3], [f64; 3]) {
    let u = norm(cross(a, [0.0, 0.0, 1.0]));
    let w = cross(u, a);
    let (c, s) = (rot.cos(), rot.sin());
    ([u[0] * c + w[0] * s, u[1] * c + w[1] * s, u[2] * c + w[2] * s], [-u[0] * s + w[0] * c, -u[1] * s + w[1] * c, -u[2] * s + w[2] * c])
}
/// When the crater `r` out is dug (strike.wgsl's cb_dig_t).
pub(super) fn cb_dig_t(r: f64) -> f32 {
    CB_DET + 0.1 + (r / CB_DIG_V) as f32
}
/// Fissure i: its heading, how far out it runs, and its heading `r` out as it wanders (strike.wgsl's cb_crack).
pub(super) fn cb_crack(i: usize, seed: f32) -> (f64, f64) {
    let s = seed as u32;
    let a = (i as f64 + 0.7 * mh(i as u32, s, 31)) * TAU / CB_CRACKS as f64 + mh(99, s, 32) * TAU;
    (a, CB_BOWL + 50.0 + (CB_CRACK_R - CB_BOWL - 50.0) * mh(i as u32, s, 33))
}
pub(super) fn cb_crack_a(i: usize, r: f64, seed: f32) -> f64 {
    let fi = i as f64;
    cb_crack(i, seed).0 + 0.08 * (r * 0.05 + fi * 3.0).sin() + 0.04 * (r * 0.13 + fi).sin()
}
/// When the fissures open `r` out: as the shock reaches them, but not before the land over them is cleared (and so on
/// out, the same way: strike.wgsl's cb_crack_t).
pub(super) fn cb_crack_t(r: f64) -> f32 {
    let shock = CB_DET + 0.2 + (r / CB_SHOCK_V) as f32;
    shock.max(cb_dig_t(r + 20.0) + 0.05)
}

/// strike.wgsl's pcg3d (the gradient noise's hash), for the shards' random numbers.
fn pcg3d(v0: [u32; 3]) -> [u32; 3] {
    let mut v = v0.map(|x| x.wrapping_mul(1_664_525).wrapping_add(1_013_904_223));
    v[0] = v[0].wrapping_add(v[1].wrapping_mul(v[2]));
    v[1] = v[1].wrapping_add(v[2].wrapping_mul(v[0]));
    v[2] = v[2].wrapping_add(v[0].wrapping_mul(v[1]));
    v = v.map(|x| x ^ (x >> 16));
    v[0] = v[0].wrapping_add(v[1].wrapping_mul(v[2]));
    v[1] = v[1].wrapping_add(v[2].wrapping_mul(v[0]));
    v[2] = v[2].wrapping_add(v[0].wrapping_mul(v[1]));
    v
}
fn cb_h3(f: usize, k: u32, seed: f32) -> [f64; 3] {
    pcg3d([f as u32, k, seed as u32]).map(|x| f64::from(x) / 4_294_967_295.0)
}
/// Shard f thrown out as they burst (strike.wgsl's cb_frag_from, cb_frag_v, cb_frag_land): where it comes down (x, z
/// off the target), when (seconds after the burst), its hue and how big it is.
pub(super) fn cb_frag(f: usize, seed: f32) -> (f64, f64, f64, f64, f64) {
    let (h1, h2, h3) = (cb_h3(f, 41, seed), cb_h3(f, 42, seed), cb_h3(f, 313, seed));
    let a = h1[0] * TAU;
    let r = CB_FIELD * 0.85 * h1[1].sqrt();
    let y = 12.0 + 250.0 * h1[2].powf(1.6) * (1.0 - 0.55 * r / CB_FIELD);
    let (px, pz) = (a.cos() * r, a.sin() * r);
    let ol = (px + 0.01).hypot(pz);
    let (ox, oz) = ((px + 0.01) / ol, pz / ol);
    let az = (h2[1] - 0.5) * 1.4;
    let (o2x, o2z) = (ox * az.cos() - oz * az.sin(), ox * az.sin() + oz * az.cos());
    let vy = 6.0 + 40.0 * h3[2];
    let tl = (vy + (vy * vy + 2.0 * CB_G * y).sqrt()) / CB_G;
    // (no further out than the land kept loaded)
    let vh = (22.0 + 70.0 * h2[2] + y * 0.12).min((CB_THROW - r).max(10.0) / tl);
    (px + o2x * vh * tl, pz + o2z * vh * tl, tl, h1[0] * 0.6 + 0.3 * h2[0], 1.5 + 5.0 * h3[0] * h3[0])
}

/// A crystal as blocks: a convex solid given by its planes (in its own frame round `b`), and its colour.
struct CbSolid {
    b: [f64; 3],
    e1: [f64; 3],
    a: [f64; 3],
    e2: [f64; 3],
    planes: Vec<([f64; 3], f64)>,
    /// How far out round `b` it reaches across the land.
    reach: f64,
    /// Its radius, how far its sides are from its axis.
    r: f64,
    family: usize,
}
impl CbSolid {
    fn local(&self, q: [f64; 3]) -> [f64; 3] {
        [dot(q, self.e1), dot(q, self.a), dot(q, self.e2)]
    }
    /// Where the column at (x, z) runs through it: from y0 to y1 up from b.
    fn span(&self, x: f64, z: f64) -> Option<(f64, f64)> {
        let o = self.local([x - self.b[0], 0.0, z - self.b[2]]);
        let d = [self.e1[1], self.a[1], self.e2[1]];
        let (mut t0, mut t1) = (-1e9f64, 1e9f64);
        for (n, w) in &self.planes {
            let dn = dot(*n, d);
            let num = w - dot(*n, o);
            if dn.abs() < 1e-9 {
                if num < 0.0 {
                    return None;
                }
                continue;
            }
            let t = num / dn;
            if dn < 0.0 { t0 = t0.max(t) } else { t1 = t1.min(t) }
        }
        (t0 < t1).then_some((t0, t1))
    }
    /// How far (x, y, z) up from b is inside its sides (the nearest of the first six planes), and from its axis.
    fn depth(&self, x: f64, y: f64, z: f64) -> (f64, f64) {
        let q = self.local([x - self.b[0], y, z - self.b[2]]);
        let side = self.planes[..6].iter().map(|(n, w)| (w - dot(*n, q)) / dot(*n, *n).sqrt()).fold(f64::MAX, f64::min);
        (side, q[0].hypot(q[2]))
    }
    /// Its blocks in column (x, z), from no lower than `floor` (in the world): a glassy skin a block or two thick, bands
    /// across it, its body, a glowing heart down its middle. `rel`: put them counted from the column's ground (the
    /// ground taken to be `rel`, the first air over it), for a piece lying on the land.
    fn column(&self, bl: &mut Blocks, x: i32, z: i32, floor: i32, sky: i32, rel: Option<i32>) {
        let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
        let Some((y0, y1)) = self.span(fx, fz) else { return };
        let by = self.b[1];
        let lo = ((by + y0 - 0.5).ceil() as i32).max(floor);
        let hi = ((by + y1 - 0.5).floor() as i32).min(sky);
        if hi < lo {
            return;
        }
        let (side, ax) = self.depth(fx, (y0 + y1) * 0.5, fz);
        let [body, skin, band, heart] = CB_FAMILY[self.family];
        let off = rel.unwrap_or(0);
        let put = |bl: &mut Blocks, a: i32, b: i32, blk: &'static str| bl.put(x, z, a - off, b - off, blk, None, rel.is_some());
        if side < 1.6 {
            // the skin, banded every seven blocks
            let mut y = lo;
            while y <= hi {
                let bnd = (y + 3 * self.family as i32).rem_euclid(7) == 0;
                let next = if bnd { y } else { (y + 6 - (y + 3 * self.family as i32).rem_euclid(7)).min(hi) };
                put(bl, y, next, if bnd { band } else { skin });
                y = next + 1;
            }
        } else if ax < self.r * 0.22 {
            // the heart: glowing in stretches up its middle
            let mut y = lo;
            while y <= hi {
                let lit = (y.div_euclid(5)) % 2 == 0;
                let next = (y.div_euclid(5) * 5 + 4).min(hi);
                put(bl, y, next, if lit { heart } else { body });
                y = next + 1;
            }
        } else {
            put(bl, lo, hi, body);
        }
    }
}
/// The stump spire i leaves (cut at its break), or none (the heart shatters whole). `point`: the target.
fn cb_stump(i: usize, seed: f32, point: [f64; 3]) -> Option<CbSolid> {
    let p = cb_place(i, seed);
    let f = cb_form(i, seed, p);
    let br = cb_break(i, seed, p[3]);
    if br[0] < 0.5 {
        return None;
    }
    let hue = cb_hue(i, seed, p);
    let a = [f[1].sin() * f[2].cos(), f[1].cos(), f[1].sin() * f[2].sin()];
    let (e1, e2) = cb_frame(a, f[3]);
    let (r, h) = (f[0], p[3]);
    let rt = r * 0.8;
    let tip = (rt * (1.3 + 1.5 * mh(i as u32, seed as u32, 24))).min(h + CB_SINK * 0.5);
    let hb = h - tip;
    let tp = (r - rt) / (hb + CB_SINK).max(1.0);
    let apex = [(mh(i as u32, seed as u32, 21) - 0.5) * 0.7, (mh(i as u32, seed as u32, 22) - 0.5) * 0.7];
    let mut planes = Vec::new();
    for k in 0..6 {
        let th = k as f64 * PI / 3.0;
        let sk = 1.0 + 0.35 * ((hue * 91.7 + k as f64 * 0.618).rem_euclid(1.0) - 0.5);
        planes.push(([th.cos(), tp, th.sin()], (r - tp * CB_SINK) * sk));
    }
    for k in 0..6 {
        let th = k as f64 * PI / 3.0;
        let m = (rt - (th.cos() * apex[0] + th.sin() * apex[1]) * rt) / tip.max(0.5);
        planes.push(([th.cos(), m, th.sin()], rt + m * hb));
    }
    planes.push(([0.0, -1.0, 0.0], CB_SINK));
    planes.push(([br[1], 1.0, br[2]], br[0]));
    let reach = r * 1.3 + (br[0] + CB_SINK) * f[1].sin() + 2.0;
    Some(CbSolid { b: [point[0] + p[0], point[1], point[2] + p[1]], e1, a, e2, planes, reach, r, family: cb_family(hue) })
}
/// The broken length of spire i lying on the land by its stump, toppled the way it leaned, for the tallest of them.
fn cb_fallen(i: usize, seed: f32, point: [f64; 3]) -> Option<CbSolid> {
    let p = cb_place(i, seed);
    if i == 5 || p[3] < 150.0 || !(i < CB_LEADS || (i - 6) % 4 == 0) {
        return None;
    }
    let f = cb_form(i, seed, p);
    let br = cb_break(i, seed, p[3]);
    let s = seed as u32;
    let len = (p[3] * 0.3).clamp(25.0, 80.0);
    let rp = f[0] * 0.85;
    let hd = f[2] + (mh(i as u32, s, 25) - 0.5) * 0.5;
    let dist = br[0] * f[1].sin() + len * 0.5 + rp + 5.0;
    let a = norm([hd.cos(), -0.1 - 0.1 * mh(i as u32, s, 26), hd.sin()]);
    let (e1, e2) = cb_frame(a, f[3] + 0.4);
    let b = [point[0] + p[0] + hd.cos() * dist, point[1] + rp * 0.5, point[2] + p[1] + hd.sin() * dist];
    let mut planes = Vec::new();
    for k in 0..6 {
        let th = k as f64 * PI / 3.0;
        planes.push(([th.cos(), 0.0, th.sin()], rp));
    }
    // (its ends broken across, slanting)
    let t1 = mh(i as u32, s, 27) * TAU;
    let t2 = mh(i as u32, s, 28) * TAU;
    planes.push(([t1.cos() * 0.5, 1.0, t1.sin() * 0.5], len * 0.5));
    planes.push(([t2.cos() * 0.5, -1.0, t2.sin() * 0.5], len * 0.5));
    let hue = cb_hue(i, seed, p);
    Some(CbSolid { b, e1, a, e2, planes, reach: len * 0.5 + rp * 0.6 + 2.0, r: rp, family: cb_family(hue) })
}

/// How deep the crater is under (dx, dz) from its middle (blocks under the target's ground; `bottom` as deep as it
/// goes, to bedrock): a bowl, its edge wandering, its floor a little uneven; the well down the middle.
pub(super) fn cb_depth(dx: f64, dz: f64, seed: u32, bottom: i32) -> i32 {
    let r = dx.hypot(dz);
    if r > CB_BOWL * 1.12 {
        return 0;
    }
    let (ca, sa) = (dx / r.max(1e-6), dz / r.max(1e-6));
    let round = |rad: f64, scale: f64, k: u32| vnoise(ca * rad + 1000.0, sa * rad + 1000.0, scale, seed ^ k) * 2.0 - 1.0;
    if r < cb_well_r(ca, sa, seed) {
        return bottom;
    }
    let edge = CB_BOWL * (1.0 + 0.08 * round(300.0, 70.0, 0x501) + 0.03 * round(300.0, 20.0, 0x502));
    if r >= edge {
        return 0;
    }
    let u = r / edge;
    let d = CB_BOWL_D * (1.0 - u * u).powf(0.75) + 2.5 * (vnoise(dx, dz, 14.0, seed ^ 0x503) - 0.5);
    (d.round() as i32).clamp(0, bottom)
}
fn cb_well_r(ca: f64, sa: f64, seed: u32) -> f64 {
    CB_WELL * (1.0 + 0.2 * (vnoise(ca * 60.0 + 1000.0, sa * 60.0 + 1000.0, 9.0, seed ^ 0x504) * 2.0 - 1.0))
}

/// The crystal bloom. The land round the target wakes with a hum, cracks of light spreading out over it; five shards
/// punch up out of it one after another, each heard from where it breaks the ground, then the heart; the bloom runs out
/// over the land; they resonate, and detonate. The land is blown clear out to 130 blocks, the geode crater dug from the
/// middle out and the stumps built as it reaches them, the fissures opened as the shock reaches them; the shards come
/// down where they were thrown, the broken spires lie by their stumps and the land is frosted with crystal.
pub(super) fn crystalbloom_plan(laser: &'static Laser, target: &Target, terrain: bool, dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let r2 = |v: f64| (v * 100.0).round() / 100.0;
    let (tx, ty, tz) = (r2(target.point[0]), r2(target.point[1]), r2(target.point[2]));
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let late = |x: f64, y: f64, z: f64| (((x - me[0]).powi(2) + (y - me[1]).powi(2) + (z - me[2]).powi(2)).sqrt() / 343.0) as f32;
    let _ = wing_angle(target.point, me);
    let (lt, dist) = sound_from(target.point, me);
    let fo = falloff(dist).max(0.4);

    // the land waking: its hum and groan from the start, heard from the middle, the ground trembling more and more
    p.at(0.2, bar("CRYSTAL BLOOM: THE LAND WAKES", laser.color));
    p.csound(lt, "wake", 10.0, 1.0);
    for k in 0..6 {
        p.shake(0.4 + k as f32 * 0.5 + lt, (0.04 + 0.02 * k as f32) * fo, 0.8);
    }
    // the first shards: each heard breaking the ground and surging up from where it stands, three takes in turn; the
    // ground jolting as it breaks, catches, gives and surges
    for i in 0..CB_LEADS {
        let pl = cb_place(i, shader_seed);
        let (x, z) = (tx + pl[0], tz + pl[1]);
        let t = pl[2] as f32;
        let lag = late(x, ty, z);
        let (_, d) = sound_from([x, ty, z], me);
        let w = falloff(d).max(0.3);
        let take = 1 + i % 3;
        let pitch = if i == 5 { 0.82 } else { p.rng.uniform(0.94, 1.08) };
        p.at(t - CB_BULGE + lag, format!("playsound orbital:crystalbloom.punch{take} block @a {x:.1} {ty} {z:.1} 4 {pitch:.2} 0.95"));
        p.shake(t - CB_BULGE + lag, 0.06 * w, CB_BULGE + 0.2);
        p.shake(t + lag, 0.35 * w, 0.5);
        p.shake(t + 0.34 + lag, 0.18 * w, 0.35);
        p.shake(t + 0.66 + lag, 0.2 * w, 0.35);
        p.shake(t + CB_STRUGGLE + lag, if i == 5 { 0.8 } else { 0.55 } * w, 1.6);
        // earth and rock bursting up round it
        p.at(t, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {x:.1} {} {z:.1} 6 1 6 1.2 300 force"#, ty + 1.0));
        p.at(t + CB_STRUGGLE, format!(r#"particle minecraft:block{{block_state:"minecraft:stone"}} {x:.1} {} {z:.1} 8 2 8 1.6 300 force"#, ty + 1.0));
        p.at(t + CB_STRUGGLE, format!("particle minecraft:end_rod {x:.1} {} {z:.1} 6 10 6 0.08 40 force", ty + 6.0));
    }
    // the bloom: its chimes and grinding, heard from the middle as it runs out; the land shuddering under it
    p.at(CB_BLOOM0, bar("BLOOM", laser.color));
    p.csound(CB_BLOOM0 - 0.3 + lt, "bloom", 10.0, 1.0);
    for k in 0..10 {
        p.shake(CB_BLOOM0 + k as f32 * 0.55 + lt, 0.12 * fo, 0.6);
    }
    // the resonance, building to the detonation; a breath; the burst, and the shards tinkling down after it
    p.at(CB_RES, bar("RESONANCE", "aqua"));
    p.csound(CB_RES + lt, "resonance", 10.0, 1.0);
    let mut tk = CB_RES + 0.5;
    while tk < CB_DET - 0.4 {
        let u = (tk - CB_RES) / (CB_DET - CB_RES);
        p.shake(tk + lt, (0.05 + 0.2 * u * u) * fo, 0.6);
        tk += 0.6 - 0.35 * u;
    }
    p.at(CB_DET, bar("DETONATION", "white"));
    // (the burst is 0.05 s into its sound)
    p.csound(CB_DET - 0.05 + lt, "shatter", 10.0, 1.0);
    p.shake(CB_DET + lt, fo, 4.0);
    p.csound(CB_DET + 1.4 + lt, "tinkle", 10.0, 1.0);
    p.csound(CB_DET + 5.0 + lt, "after", 9.0, 1.0);
    for k in 0..5 {
        p.shake(CB_DET + 1.5 + k as f32 * 0.9 + lt, 0.12 * fo, 1.0);
    }

    // ---- particles in the world ----
    for i in 0..12 {
        // the light seeping up out of the land as it wakes
        let tk = 0.5 + i as f32 * 0.3;
        let s = 20.0 + 9.0 * f64::from(i);
        p.at(tk, format!("particle minecraft:end_rod {tx} {} {tz} {s:.1} 0.5 {s:.1} 0.01 30 force", ty + 0.5));
    }
    for i in 0..14 {
        // the air shimmering round them as they resonate
        let tk = CB_RES + 0.5 * i as f32;
        p.at(tk, format!("particle minecraft:glow {tx} {} {tz} 60 60 60 0.05 60 force", ty + 60.0));
    }
    let hy = ty + 150.0;
    p.at(CB_DET, format!("particle minecraft:flash {tx} {hy} {tz} 0 0 0 0 1 force"));
    p.at(CB_DET, format!("particle minecraft:end_rod {tx} {hy} {tz} 20 40 20 1.5 900 force"));
    p.at(CB_DET + 0.05, format!(r#"particle minecraft:block{{block_state:"minecraft:amethyst_block"}} {tx} {} {tz} 60 30 60 2.0 600 force"#, ty + 40.0));
    p.at(CB_DET + 0.05, format!(r#"particle minecraft:block{{block_state:"minecraft:purple_stained_glass"}} {tx} {} {tz} 60 30 60 2.0 400 force"#, ty + 40.0));
    for i in 0..20 {
        // glitter coming down over everything
        let tk = CB_DET + 0.6 + i as f32 * 0.4;
        p.at(tk, format!("particle minecraft:end_rod {tx} {} {tz} 140 40 140 0.02 80 force", ty + 50.0));
        p.at(tk, format!("particle minecraft:wax_off {tx} {} {tz} 120 30 120 0 60 force", ty + 30.0));
    }
    for tk in [0.1, 0.8, 2.0, 4.0, 7.0] {
        p.at(CB_DET + tk, format!("execute positioned {tx} {ty} {tz} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..160]"));
    }

    if terrain {
        let (floor_y, sky, point) = (bedrock_top(dimension), sky_top(dimension), target.point);
        let s = shader_seed as u32;
        // the chunks it works in kept loaded from the start until every change is made (a row of chunks a forceload)
        let load = pk_load_rows(point, 0.0, CB_LOAD);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // each spire breaking the ground: a hole round it and the earth heaped up round that
        for i in 0..CB_N {
            let pl = cb_place(i, shader_seed);
            let f = cb_form(i, shader_seed, pl);
            p.later(pl[2] as f32 - 0.3, move |q| cb_punch(q, point, pl, f, s));
        }
        // the crater, the land blown clear round it and the stumps, a few chunk columns a stage, nearest first
        // (no more than about five chunk columns a tick: one is put off a little, by up to what strike.wgsl allows for,
        // when more fall due together)
        let mut cells = pk_cells(point, CB_BLAST * 1.1 + 4.0);
        let mut last = 0.0f32;
        for c in cells.iter_mut() {
            let t = cb_dig_t(c.2).max(last + 0.01).min(cb_dig_t(c.2 + CB_SLACK));
            last = t;
            c.2 = f64::from(t);
        }
        // (worked out well ahead, while they resonate: there are many, and the mod works out one a tick)
        for group in cells.chunks(6) {
            let group = group.to_vec();
            let t0 = group[0].2 as f32;
            p.later(t0 - 1.6, move |q| {
                let stumps: Vec<CbSolid> = (0..CB_N).filter_map(|i| cb_stump(i, shader_seed, point)).collect();
                for (x0, z0, t) in group {
                    cb_dig_cell(q, point, x0, z0, t as f32, floor_y, sky, shader_seed, &stumps);
                }
            });
        }
        // the fissures, each worked out well before it opens (while they resonate, with the crater's stages)
        for i in 0..CB_CRACKS {
            let len = cb_crack(i, shader_seed).1;
            p.later(CB_DET - 2.6 + i as f32 * 0.05, move |q| cb_fissure(q, point, i, shader_seed, CB_BOWL * 0.85, len));
        }
        // the shards coming down where they were thrown
        for part in 0..8 {
            let fs: Vec<usize> = (part..CB_FRAGS).step_by(8).collect();
            let first = fs.iter().map(|&f| cb_frag(f, shader_seed).2).fold(f64::MAX, f64::min) as f32;
            p.later(CB_DET + first.min(1.0) - 3.2 + part as f32 * 0.05, move |q| cb_landed(q, point, &fs, shader_seed));
        }
        // the broken spires lying by their stumps, once the land under them is clear
        for i in 0..CB_N {
            if cb_fallen(i, shader_seed, point).is_some() {
                let t = CB_DET + 2.6 + 0.1 * i as f32;
                p.later(t - 1.5, move |q| {
                    if let Some(c) = cb_fallen(i, shader_seed, point) {
                        let mut b = Blocks::default();
                        cb_solid(&mut b, &c, -1000, Some(point[1].floor() as i32));
                        q.ev.push((t, Act::Blocks(Box::new(b))));
                    }
                });
            }
        }
        // the land frosted with crystal and strewn with shards, a ring at a time from the middle out
        for part in 0..12u32 {
            let t = CB_DET + 2.8 + part as f32 * 0.25;
            p.later(t - 1.2, move |q| cb_strew(q, point, s, part, t));
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

/// Every block of solid `c` (no lower than `floor`), column by column.
fn cb_solid(b: &mut Blocks, c: &CbSolid, floor: i32, rel: Option<i32>) {
    // (round the stretch of its axis it lies along, as wide as it is)
    let half = c.reach;
    let (ex, ez) = (c.a[0] * half, c.a[2] * half);
    let w = c.r * 1.25 + 1.0;
    let (x0, x1) = ((c.b[0] - ex.abs() - w).floor() as i32, (c.b[0] + ex.abs() + w).ceil() as i32);
    let (z0, z1) = ((c.b[2] - ez.abs() - w).floor() as i32, (c.b[2] + ez.abs() + w).ceil() as i32);
    for z in z0..=z1 {
        for x in x0..=x1 {
            c.column(b, x, z, floor, i32::MAX, rel);
        }
    }
}

/// Spire `pl` breaking the ground as it sets off: a hole round it, the earth heaped round the hole, and its sound.
fn cb_punch(p: &mut Plan, point: [f64; 3], pl: [f64; 4], f: [f64; 4], seed: u32) {
    let (cx, cz) = (point[0] + pl[0], point[2] + pl[1]);
    let rh = f[0] * 1.15 + 1.0;
    let deep = (2.0 + f[0] * 0.25).round() as i32;
    let mut b = Blocks::default();
    let ext = (rh + 4.0).ceil() as i32;
    for z in (cz.floor() as i32 - ext)..=(cz.floor() as i32 + ext) {
        for x in (cx.floor() as i32 - ext)..=(cx.floor() as i32 + ext) {
            let d = (f64::from(x) + 0.5 - cx).hypot(f64::from(z) + 0.5 - cz);
            let n = vnoise(f64::from(x), f64::from(z), 3.0, seed ^ 0x511);
            if d < rh {
                b.put(x, z, -deep, -1, "minecraft:air", None, true);
            } else if d < rh + 1.5 + 2.0 * n {
                let blk = if n > 0.7 { "minecraft:cobblestone" } else if n > 0.4 { "minecraft:coarse_dirt" } else { "minecraft:rooted_dirt" };
                let h = if d < rh + 1.0 { 1 } else { 0 };
                b.put(x, z, 0, h, blk, None, true);
            }
        }
    }
    p.ev.push((pl[2] as f32, Act::Blocks(Box::new(b))));
}

/// Dig the crater under chunk column (x0, z0) at `t`, straight into the chunks, and clear the land over it: the bowl
/// dug to its floor and lined as a geode is (amethyst over calcite over smooth basalt; here and there quartz instead,
/// or rose glass), seams of light through its floor near the middle, crystals jutting up off it; the faces of the
/// ground round it lined; the well down the middle to the bedrock, its walls in the same shells, a glowing pool at its
/// foot; and the stumps of the spires standing in it built where they stood.
fn cb_dig_cell(p: &mut Plan, point: [f64; 3], x0: i32, z0: i32, t: f32, floor_y: i32, sky: i32, seed: f32, stumps: &[CbSolid]) {
    let by = p.by;
    let s = seed as u32;
    let mut b = Blocks::default();
    // (what stands high over the middle, cleared on a tick of its own a little later: it is a lot of blocks)
    let mut high = Blocks::default();
    let mut dep = [[0i32; 18]; 18];
    for (j, row) in dep.iter_mut().enumerate() {
        for (i, d) in row.iter_mut().enumerate() {
            let (dx, dz) = (f64::from(x0 + i as i32 - 1) + 0.5 - point[0], f64::from(z0 + j as i32 - 1) + 0.5 - point[2]);
            *d = cb_depth(dx, dz, s, by - floor_y);
        }
    }
    for j in 1..17 {
        for i in 1..17 {
            let (x, z) = (x0 + i as i32 - 1, z0 + j as i32 - 1);
            let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
            let (dx, dz) = (fx - point[0], fz - point[2]);
            let r = dx.hypot(dz);
            let blast = CB_BLAST * (0.93 + 0.14 * vnoise(dx, dz, 50.0, s ^ 0x505));
            let core = CB_CORE * (0.9 + 0.2 * vnoise(dx, dz, 20.0, s ^ 0x506));
            let dd = dep[j][i];
            let top = (by + CB_ABOVE).min(sky);
            if r < blast || dd > 0 {
                let y0 = if dd > 0 { by - dd + 1 } else { by + 1 };
                b.run(x, z, y0, top, "minecraft:air");
            }
            if r < core {
                high.run(x, z, top + 1, sky, "minecraft:air");
            }
            let dmax = [dep[j - 1][i], dep[j + 1][i], dep[j][i - 1], dep[j][i + 1]].into_iter().max().unwrap_or(0);
            let zone = vnoise(fx, fz, 40.0, s ^ 0x507);
            let inner = if zone > 0.72 { "minecraft:smooth_quartz" } else if zone < 0.2 { "minecraft:pink_stained_glass" } else { "minecraft:amethyst_block" };
            if dd == 0 {
                // the face of the ground round it, lined (only where it is ground)
                for y in (by - dmax + 1).max(floor_y)..=by {
                    b.put(x, z, y, y, inner, Some("#minecraft:sculk_replaceable"), false);
                }
                continue;
            }
            let fy = by - dd;
            if dd >= by - floor_y {
                // the well: open to its foot, a glowing pool there
                b.run(x, z, floor_y + 1, fy.max(floor_y + 1), "minecraft:air");
                let n = vnoise(fx, fz, 4.0, s ^ 0x508);
                b.put(x, z, floor_y - 1, floor_y - 1, "minecraft:amethyst_block", Some("#minecraft:sculk_replaceable"), false);
                b.run(x, z, floor_y, floor_y, if n > 0.6 { "minecraft:pearlescent_froglight" } else if n > 0.3 { "minecraft:amethyst_block" } else { "minecraft:calcite" });
                continue;
            }
            // the floor: its inner shell, calcite, then smooth basalt; seams of light through it near the middle
            let seam = (vnoise(fx, fz, 11.0, s ^ 0x509) - 0.5).abs() < 0.025 && r < 60.0;
            b.run(x, z, (fy - 5).max(floor_y), fy - 3, "minecraft:smooth_basalt");
            b.run(x, z, (fy - 2).max(floor_y), fy - 1, "minecraft:calcite");
            b.run(x, z, fy, fy, if seam { "minecraft:pearlescent_froglight" } else { inner });
            // the faces down to deeper ground beside it
            if dmax > dd {
                b.run(x, z, (by - dmax + 1).max(floor_y), fy - 1, inner);
            }
            // the well's walls round it, in the same shells, out from it
            let ca = dx / r.max(1e-6);
            let sa = dz / r.max(1e-6);
            let wr = cb_well_r(ca, sa, s);
            if r < wr + 3.5 {
                let blk = if r < wr + 1.2 { inner } else if r < wr + 2.4 { "minecraft:calcite" } else { "minecraft:smooth_basalt" };
                b.run(x, z, floor_y, fy - 1, blk);
            }
            // crystals jutting up off the floor
            let h = mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, s, 0x50a);
            if h > 0.985 - 0.02 * (1.0 - r / CB_BOWL) {
                let tall = 1 + ((h - 0.96) * 160.0) as i32 % 4;
                b.run(x, z, fy + 1, fy + tall, if zone > 0.5 { "minecraft:purple_stained_glass" } else { "minecraft:amethyst_block" });
                b.run(x, z, fy + tall + 1, fy + tall + 1, "minecraft:amethyst_cluster");
            }
        }
    }
    // the stumps standing here, built into the dug ground
    for c in stumps {
        let (cx, cz) = (c.b[0], c.b[2]);
        if cx + c.reach < f64::from(x0) || cx - c.reach > f64::from(x0 + 16) || cz + c.reach < f64::from(z0) || cz - c.reach > f64::from(z0 + 16) {
            continue;
        }
        for z in z0..z0 + 16 {
            for x in x0..x0 + 16 {
                let d = dep[(z - z0 + 1) as usize][(x - x0 + 1) as usize];
                c.column(&mut b, x, z, (by - d - 3).max(floor_y + 1), sky, None);
            }
        }
    }
    p.ev.push((t, Act::Blocks(Box::new(b))));
    if !high.runs.is_empty() {
        let slot = ((x0 >> 4) ^ (z0 >> 4)).rem_euclid(8);
        p.ev.push((t + 0.6 + slot as f32 * 0.05, Act::Blocks(Box::new(high))));
    }
}

/// Fissure i from `r0` to `r1` out: cut a few blocks wide and deep along the line strike.wgsl draws it, as it opens,
/// its floor crystal with glowing seams, its walls lined with calcite and amethyst.
fn cb_fissure(p: &mut Plan, point: [f64; 3], i: usize, seed: f32, r0: f64, r1: f64) {
    let len = cb_crack(i, seed).1;
    let s = seed as u32;
    let mut r = r0;
    while r < r1 {
        let a = cb_crack_a(i, r, seed);
        let share = (1.0 - (r - CB_BOWL) / (len - CB_BOWL)).clamp(0.0, 1.0);
        let hw = 1.0 + 2.2 * share;
        let depth = (5.0 + 13.0 * share).round() as i32;
        let (cx, cz) = (point[0] + a.cos() * r, point[2] + a.sin() * r);
        let mut b = Blocks::default();
        let e = hw.ceil() as i32 + 2;
        for z in (cz.floor() as i32 - e)..=(cz.floor() as i32 + e) {
            for x in (cx.floor() as i32 - e)..=(cx.floor() as i32 + e) {
                let (dx, dz) = (f64::from(x) + 0.5 - point[0], f64::from(z) + 0.5 - point[2]);
                let rr = dx.hypot(dz);
                if rr < CB_BOWL * 0.85 || rr > len {
                    continue;
                }
                let aa = cb_crack_a(i, rr, seed);
                let lat = (dx * aa.sin() - dz * aa.cos()).abs();
                let along = (dx * aa.cos() + dz * aa.sin() - r).abs();
                if along > 2.0 {
                    continue;
                }
                let n = vnoise(f64::from(x), f64::from(z), 5.0, s ^ 0x50b);
                if lat < hw {
                    b.put(x, z, -depth - 1, -depth - 1, if n > 0.72 { "minecraft:pearlescent_froglight" } else { "minecraft:amethyst_block" }, None, true);
                    b.put(x, z, -depth, -1, "minecraft:air", None, true);
                } else if lat < hw + 1.5 {
                    b.put(x, z, -depth, -1, if n > 0.5 { "minecraft:amethyst_block" } else { "minecraft:calcite" }, Some("#minecraft:sculk_replaceable"), true);
                }
            }
        }
        p.ev.push((cb_crack_t(r), Act::Blocks(Box::new(b))));
        r += 3.0;
    }
}

/// The shards `fs` coming down where they were thrown, each a crystal of its colour standing up out of the land, a
/// cluster on its top.
fn cb_landed(p: &mut Plan, point: [f64; 3], fs: &[usize], seed: f32) {
    for &f in fs {
        let (x, z, tl, hue, sz) = cb_frag(f, seed);
        let [_, skin, band, _] = CB_FAMILY[cb_family(hue)];
        let (bx, bz) = ((point[0] + x).floor() as i32, (point[2] + z).floor() as i32);
        let h = (1.0 + sz * 0.6).round() as i32;
        let w = i32::from(sz > 4.5);
        let mut b = Blocks::default();
        for dz in 0..=w {
            for dx in 0..=w {
                let hh = h - (dx + dz) * 2;
                if hh <= 0 {
                    continue;
                }
                b.put(bx + dx, bz + dz, -1, hh - 2, skin, None, true);
                b.put(bx + dx, bz + dz, hh - 1, hh - 1, band, None, true);
                b.put(bx + dx, bz + dz, hh, hh, "minecraft:amethyst_cluster", None, true);
            }
        }
        p.ev.push((CB_DET + tl as f32, Act::Blocks(Box::new(b))));
    }
}

/// Part `part` of twelve of the land round it, in rings from the middle out: frosted over with calcite in drifts, amethyst
/// glinting in them, out to CB_FROST; small shards strewn over it, thinning out to CB_STREW.
fn cb_strew(p: &mut Plan, point: [f64; 3], seed: u32, part: u32, t: f32) {
    let (ra, rb) = (CB_BOWL * 0.9 + (CB_STREW - CB_BOWL * 0.9) * f64::from(part) / 12.0, CB_BOWL * 0.9 + (CB_STREW - CB_BOWL * 0.9) * f64::from(part + 1) / 12.0);
    let mut b = Blocks::default();
    let ext = rb.ceil() as i32;
    let pz = point[2].floor() as i32;
    for z in (pz - ext)..=(pz + ext) {
        // (only the ring: from its outer edge in to its inner one, either side)
        let dz = f64::from(z) + 0.5 - point[2];
        let wo = (rb * rb - dz * dz).max(0.0).sqrt();
        let wi = (ra * ra - dz * dz).max(0.0).sqrt();
        let (xo0, xo1) = ((point[0] - wo).floor() as i32, (point[0] + wo).ceil() as i32);
        let (xi0, xi1) = ((point[0] - wi).ceil() as i32, (point[0] + wi).floor() as i32 - 1);
        for x in (xo0..=xo1).filter(|x| wi <= 0.0 || *x < xi0 || *x > xi1) {
            let (fx, fz) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
            let r = (fx - point[0]).hypot(fz - point[2]);
            if r < ra || r >= rb {
                continue;
            }
            let thin = 1.0 - smoothstep(CB_BOWL, CB_FROST, r);
            let n = vnoise(fx, fz, 16.0, seed ^ 0x50c);
            if r < CB_FROST && n > 0.6 - 0.25 * thin {
                let blk = if vnoise(fx, fz, 4.0, seed ^ 0x50d) > 0.82 { "minecraft:amethyst_block" } else { "minecraft:calcite" };
                b.put(x, z, -1, -1, blk, Some("#minecraft:dirt"), true);
            }
            let h = mh((x.wrapping_mul(31) ^ z.wrapping_mul(97)) as u32, seed, 0x50e);
            let strew = 0.02 * (1.0 - smoothstep(CB_BOWL, CB_STREW, r));
            if h < strew {
                let k = h / strew;
                if k < 0.35 {
                    b.put(x, z, 0, 0, "minecraft:amethyst_cluster", None, true);
                } else if k < 0.6 {
                    b.put(x, z, 0, 0, "minecraft:large_amethyst_bud", None, true);
                } else if k < 0.85 {
                    b.put(x, z, 0, 0, "minecraft:purple_stained_glass", None, true);
                    b.put(x, z, 1, 1, "minecraft:amethyst_cluster", None, true);
                } else {
                    b.put(x, z, 0, 1, "minecraft:amethyst_block", None, true);
                    b.put(x, z, 2, 2, "minecraft:medium_amethyst_bud", None, true);
                }
            }
        }
    }
    p.ev.push((t, Act::Blocks(Box::new(b))));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{block_cost, plan};

    const SEED: f32 = 37.0;
    const POINT: [f64; 3] = [10.5, 65.0, -2.5];
    /// The whole plan, every stage worked out, as (when, command) (blocks as the fills they stand for).
    fn cmds(me: [f64; 3], dimension: &str) -> Vec<(f32, String)> {
        let target = Target { block: [10, 64, -3], point: POINT };
        let mut ev = plan(&crate::lasers::CRYSTAL_BLOOM, &target, true, dimension, SEED, me, 0);
        let mut out = Vec::new();
        while let Some((t, act)) = ev.pop() {
            match act {
                Act::Cmd(c) | Act::Spare(c) => out.push((t, c)),
                Act::Blocks(b) => out.extend(b.as_fills().into_iter().map(|c| (t, c))),
                Act::Later(job) => ev.extend(job()),
                _ => {}
            }
        }
        out
    }
    /// An absolute fill's corners and block.
    fn fill(c: &str) -> Option<([i32; 6], String)> {
        let w: Vec<&str> = c.split_whitespace().collect();
        if w.len() < 8 || w[0] != "fill" {
            return None;
        }
        let n: Vec<i32> = w[1..7].iter().filter_map(|v| v.parse().ok()).collect();
        (n.len() == 6).then(|| ([n[0], n[1], n[2], n[3], n[4], n[5]], w[7].to_string()))
    }
    /// A fill counted from the column's ground: its column, from and to, and block.
    fn surf_fill(c: &str) -> Option<(i32, i32, i32, i32, String)> {
        let w: Vec<&str> = c.split_whitespace().collect();
        if w.first() != Some(&"execute") || !c.contains("run fill") {
            return None;
        }
        let f = |s: &str| s.trim_start_matches('~').parse::<i32>().unwrap_or(0);
        Some((w[2].parse().ok()?, w[4].parse().ok()?, f(w[11]), f(w[14]), w[16].to_string()))
    }

    #[test]
    fn crystalbloom_fills_fit_and_reach_bedrock() {
        // every fill under the cap and the build limit, every change made within the strike, the well down to bedrock,
        // and every forceload under 256 chunks and let go again
        for me in [[10.5, 66.0, 330.0], [600.0, 70.0, -400.0]] {
            for (dimension, sky, floor) in [("minecraft:overworld", 319, -59), ("minecraft:the_nether", 122, 5)] {
                let cmds = cmds(me, dimension);
                let mut deepest = i32::MAX;
                for (t, c) in &cmds {
                    assert!(block_cost(c).unwrap_or(0) <= 32768, "{c}");
                    assert!(*t < crate::lasers::CRYSTAL_BLOOM.length, "{t}: {c}");
                    if let Some((n, _)) = fill(c) {
                        assert!(n[1].max(n[4]) <= sky, "{c}");
                        deepest = deepest.min(n[1].min(n[4]));
                    }
                }
                assert!(deepest == floor || deepest == floor - 1, "the well reaches {deepest}");
                let adds: Vec<&String> = cmds.iter().map(|(_, c)| c).filter(|c| c.starts_with("forceload add")).collect();
                let mut chunks = std::collections::HashSet::new();
                for a in &adds {
                    let n: Vec<i32> = a.split_whitespace().skip(2).map(|v| v.parse().unwrap()).collect();
                    assert!(((n[2] >> 4) - (n[0] >> 4) + 1) * ((n[3] >> 4) - (n[1] >> 4) + 1) <= 256, "{a}");
                    for cx in (n[0] >> 4)..=(n[2] >> 4) {
                        for cz in (n[1] >> 4)..=(n[3] >> 4) {
                            chunks.insert((cx, cz));
                        }
                    }
                    assert!(cmds.iter().any(|(_, c)| *c == a.replace("add", "remove")), "{a} never let go");
                }
                assert!(chunks.len() <= 900, "{} chunks", chunks.len());
            }
        }
    }
    #[test]
    fn crystalbloom_changes_nothing_round_it() {
        // every block changed `strict` (nothing round it told: no sand falls, nothing flows), and nothing that flows or
        // spreads: no lava, no fire, no water
        let cmds = cmds([10.5, 66.0, 330.0], "minecraft:overworld");
        for (_, c) in &cmds {
            let run = c.rsplit(" run ").next().unwrap();
            if run.starts_with("fill") || run.starts_with("setblock") {
                assert!(run.ends_with(" strict"), "{c}");
                for bad in ["minecraft:lava", "minecraft:fire", "minecraft:water", "budding_amethyst"] {
                    assert!(!c.contains(bad), "{c}");
                }
            }
        }
    }
    #[test]
    fn crystalbloom_crater_follows_the_shader() {
        // the crater is dug from the middle out no later than strike.wgsl's cb_open starts it glowing (when the chunk
        // round a point has been dug), never wider than its wandering edge, no deeper than the bowl but for the well
        let cmds = cmds([10.5, 66.0, 330.0], "minecraft:overworld");
        let by = 64;
        let mut cols = 0;
        for (t, c) in &cmds {
            let Some((n, b)) = fill(c) else { continue };
            if b != "minecraft:air" || n[1] > by || n[0] != n[3] {
                continue;
            }
            let (dx, dz) = (f64::from(n[0]) + 0.5 - POINT[0], f64::from(n[2]) + 0.5 - POINT[2]);
            let r = dx.hypot(dz);
            assert!(r < CB_BOWL * 1.12 + 1.0, "dug {r:.0} out: {c}");
            assert!(*t >= cb_dig_t(r - 12.0) - 1e-3 && *t <= cb_dig_t(r + 20.0) + 1e-3, "{r:.0} out dug at {t}: {c}");
            let depth = by - n[1] + 1;
            if r > CB_WELL * 1.25 {
                assert!(f64::from(depth) <= CB_BOWL_D + 3.0, "{r:.0} out dug {depth} deep: {c}");
            }
            cols += 1;
        }
        assert!(cols > 15000, "{cols} columns");
    }
    #[test]
    fn crystalbloom_stumps_stand_where_the_spires_did() {
        // each spire but the heart leaves its stump where strike.wgsl stands it, as tall as it breaks it, built before
        // the pass stops drawing it
        let cmds = cmds([10.5, 66.0, 330.0], "minecraft:overworld");
        for i in 0..CB_N {
            let p = cb_place(i, SEED);
            let f = cb_form(i, SEED, p);
            let br = cb_break(i, SEED, p[3]);
            let (x, z) = ((POINT[0] + p[0]).floor() as i32, (POINT[2] + p[1]).floor() as i32);
            if i == 5 {
                continue;
            }
            // (built through its middle a little over the ground, after the crater round it is dug)
            let y = (POINT[1] + (br[0] * 0.4).min(4.0)).floor() as i32;
            let t = cmds
                .iter()
                .filter_map(|(t, c)| fill(c).map(|(n, b)| (t, n, b)))
                .filter(|(_, n, b)| n[0] == x && n[2] == z && b != "minecraft:air" && n[1].min(n[4]) <= y && n[1].max(n[4]) >= y)
                .map(|(t, _, _)| *t)
                .fold(f32::MIN, f32::max);
            assert!(t > 0.0, "spire {i}: no stump at {x} {y} {z}");
            let _ = f;
            let stop = cb_dig_t(p[0].hypot(p[1]) + f[0] * 1.3 + br[0] * 0.8 + 20.0) + 0.15;
            assert!(t <= stop, "spire {i}: built at {t}, after the pass stops drawing it at {stop}");
        }
    }
    #[test]
    fn crystalbloom_shards_land_where_thrown() {
        // each shard the pass throws out comes down as a crystal where its path meets the ground, as it does
        let cmds = cmds([10.5, 66.0, 330.0], "minecraft:overworld");
        for f in 0..CB_FRAGS {
            let (x, z, tl, _, _) = cb_frag(f, SEED);
            // (its path as strike.wgsl has it: where it is at tl, on the ground)
            let (h1, h2, h3) = (cb_h3(f, 41, SEED), cb_h3(f, 42, SEED), cb_h3(f, 313, SEED));
            let y0 = 12.0 + 250.0 * h1[2].powf(1.6) * (1.0 - 0.55 * 0.85 * h1[1].sqrt());
            let vy = 6.0 + 40.0 * h3[2];
            assert!((y0 + vy * tl - 0.5 * CB_G * tl * tl).abs() < 1e-6 && tl > 0.0 && h2[0] >= 0.0, "shard {f}");
            let (bx, bz) = ((POINT[0] + x).floor() as i32, (POINT[2] + z).floor() as i32);
            let t = CB_DET + tl as f32;
            assert!(cmds.iter().any(|(tt, c)| (tt - t).abs() < 1e-4 && surf_fill(c).is_some_and(|s| s.0 == bx && s.1 == bz)), "shard {f} not landed at {bx} {bz}");
            assert!(x.hypot(z) < CB_LOAD, "shard {f} lands out of the loaded land");
        }
    }
    #[test]
    fn crystalbloom_cracks_follow_the_shader() {
        // each fissure is cut along the line strike.wgsl draws it on, as it opens there, and not before the land over it
        // has been cleared
        let point = POINT;
        for i in 0..CB_CRACKS {
            let mut p = Plan { laser: &crate::lasers::CRYSTAL_BLOOM, ev: Vec::new(), rng: Rng::new(7), bx: 10, by: 64, bz: -3 };
            let len = cb_crack(i, SEED).1;
            cb_fissure(&mut p, point, i, SEED, CB_BOWL * 0.85, len);
            let mut cuts = 0;
            for (t, a) in &p.ev {
                let Act::Blocks(b) = a else { continue };
                for c in b.as_fills() {
                    let Some((x, z, _, _, blk)) = surf_fill(&c) else { continue };
                    if blk != "minecraft:air" {
                        continue;
                    }
                    let (dx, dz) = (f64::from(x) + 0.5 - point[0], f64::from(z) + 0.5 - point[2]);
                    let r = dx.hypot(dz);
                    let aa = cb_crack_a(i, r, SEED);
                    assert!((dx * aa.sin() - dz * aa.cos()).abs() < 3.3, "fissure {i}: a cut off its line");
                    assert!((*t - cb_crack_t(r)).abs() < 0.08, "fissure {i}: cut at {t} {r:.0} out, not {}", cb_crack_t(r));
                    if r < CB_BLAST {
                        assert!(*t >= cb_dig_t(r + 20.0), "fissure {i}: cut before the land over it is cleared");
                    }
                    cuts += 1;
                }
            }
            assert!(cuts > 30, "fissure {i}: {cuts} cuts");
        }
    }
    #[test]
    fn crystalbloom_spires_stand_in_the_field() {
        // the spires stand round the target, the first five round the middle and breaking the ground in turn, the heart
        // last of them and in the middle, the bloom after them, running out; every shard comes down by the strike's end
        for i in 0..CB_N {
            let p = cb_place(i, SEED);
            let r = p[0].hypot(p[1]);
            assert!(r < CB_FIELD + 20.0 && p[3] > 20.0 && p[3] <= 330.0, "{i}: {r} {}", p[3]);
            if i < 5 {
                assert!((40.0..80.0).contains(&r) && p[2] < cb_place(5, SEED)[2], "{i}");
            } else if i > 5 {
                assert!(p[2] > cb_place(5, SEED)[2] && p[2] < f64::from(CB_DET) - 5.0, "{i}: {}", p[2]);
            }
        }
        for f in 0..CB_FRAGS {
            assert!(f64::from(CB_DET) + cb_frag(f, SEED).2 < f64::from(crate::lasers::CRYSTAL_BLOOM.length) - 1.0, "shard {f}");
        }
    }
    /// What its `world.edit-blocks` changes ask of the game, tick by tick: runs, blocks and chunk columns, the busiest
    /// ticks and when the last change lands. `cargo test --release cb_edit_profile -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn cb_edit_profile() {
        let target = Target { block: [10, 64, -3], point: POINT };
        let mut ev = plan(&crate::lasers::CRYSTAL_BLOOM, &target, true, "minecraft:overworld", SEED, [10.5, 66.0, 330.0], 0);
        let mut ticks: std::collections::BTreeMap<u32, (usize, u64, std::collections::HashSet<(i32, i32)>)> = Default::default();
        while let Some((t, act)) = ev.pop() {
            match act {
                Act::Blocks(b) => {
                    let e = ticks.entry((t / 0.05).ceil() as u32).or_default();
                    for r in &b.runs {
                        e.0 += 1;
                        e.1 += u64::from(r.height);
                        e.2.insert((r.x >> 4, r.z >> 4));
                    }
                }
                Act::Later(job) => ev.extend(job()),
                _ => {}
            }
        }
        let total: u64 = ticks.values().map(|v| v.1).sum();
        println!("{} ticks with edits, {total} blocks in all, the last at {:.2} s", ticks.len(), *ticks.keys().last().unwrap() as f32 * 0.05);
        let mut busy: Vec<_> = ticks.iter().map(|(k, v)| (v.1, v.0, v.2.len(), *k as f32 * 0.05)).collect();
        busy.sort_by(|a, b| b.0.cmp(&a.0));
        for (b, r, c, t) in busy.iter().take(5) {
            println!("{t:6.2} s: {b} blocks, {r} runs, {c} chunk columns");
        }
    }
}
