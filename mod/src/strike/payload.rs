//! The payload's plan: no beam. Something bright appears high in the sky over the target and drifts down on a lazy,
//! looping path, a thin pale smoke trail curling behind it; it turns and dives, a fireball now, its trail a dark column
//! hung in the sky in the shape of its path; it strikes the land, a flash and a burst of fire, and a huge column of smoke
//! boils up out of it, the shockwave racing out over the land as a wall of dust, debris raining down far round it.
//!
//! What it leaves is real blocks: a bomb crater about 42 across and 9 deep (scorched, its rim heaped with what it threw
//! out), the land flattened round it out to about 85 (the trees felled and lying pointing away from it), the grass
//! charred out to about 100, rubble strewn over it all. Nothing that burns, flows or spreads.
//!
//! shaders/payload.wgsl draws the object, its trail, the column, the dust and the debris from the table `pl_table` hands
//! it (render.set-data): the path sampled, the column's billows. Keep the PL_* here and there in step.
use super::{Act, Blocks, Col, Plan, Rng, Target, falloff, mh, pk_load_rows, sound_from, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The object shows (fading in) high in the sky, starts its fast final descent (a fireball by then), and strikes.
pub(super) const PL_SEEN: f32 = 3.0;
pub(super) const PL_TURN: f32 = 10.6;
pub(super) const PL_HIT: f32 = 13.6;
/// How long the dive's sound runs before its cut-off (tools/sounds_payload.py reads it: the dive starts at PL_TURN).
const PL_DIVE_SND: f32 = 3.0;
/// How fast the ground carries the strike's shock (blocks a second): five times the air's, so it is felt well before
/// the blast is heard (tools/sounds_payload.py's `ground`).
const PL_GROUND_V: f64 = 5.0 * 343.0;
/// The path's samples (the trail is drawn through them), from PL_SEEN to PL_HIT.
pub(super) const PL_N: usize = 128;
/// The column's billows.
pub(super) const PL_PUFFS: usize = 18;
/// The column's height (over the ground) as its rise slows, about 20 s after the strike.
pub(super) const PL_HC: f64 = 235.0;
/// The table (render.set-data): words 0..16 the header (samples, first sample's time, their spacing, the wind's x and
/// z, the column's height, the billows' count, the shed pieces' count); from PL_P the path, three words a sample (x, y,
/// z from the target's ground); from PL_PF the billows, PL_PW words each (launch, rise time, height share, radius, x and
/// z off the axis); from PL_FR the shed pieces.
pub(super) const PL_P: usize = 16;
pub(super) const PL_PF: usize = PL_P + 3 * PL_N;
pub(super) const PL_PW: usize = 8;
/// The pieces it sheds coming in (from PL_FR, PL_FW words each, PL_CHUNKS burning chunks then PL_SPARKS sparks): when it
/// lets go (strike time), how long it burns, its size (blocks), 0 for a chunk or 1 for a spark, its drag (a second),
/// where it lets go (x, y, z from the target's ground) and its velocity then (blocks a second).
pub(super) const PL_FR: usize = 560;
pub(super) const PL_FW: usize = 12;
pub(super) const PL_CHUNKS: usize = 8;
pub(super) const PL_SPARKS: usize = 16;

/// The crater's mean radius and depth, how far its rim's heap reaches (in its radii), the land flattened and the trees
/// felled out to PL_FLAT, the grass charred out to PL_CHAR, the rubble strewn out to PL_RUBBLE.
const PL_CRATER_R: f64 = 21.0;
const PL_CRATER_D: f64 = 9.0;
const PL_RIM: f64 = 1.65;
const PL_FLAT: f64 = 85.0;
const PL_CHAR: f64 = 100.0;
const PL_RUBBLE: f64 = 105.0;
/// Past the flattened land, a band this wide where the blast only half did its work: crowns stripped of their leaves
/// (wholly near it, their tops further out), some trees knocked flat, leaves and branches strewn.
const PL_BAND: f64 = 24.0;
/// The land read: every column out to PL_READ, PL_BELOW under its top (a tall tree's top down to its ground).
const PL_READ: i32 = 120;
const PL_GW: i32 = 2 * PL_READ + 1;
const PL_BELOW: u32 = 44;
const PL_ABOVE: u32 = 1;
const PL_PARTS: i32 = 6;
/// The blast's edits worked out in this many bands of rows, a stage each.
const PL_BANDS: i32 = 40;
/// Mobs and dropped items within PL_KILL killed as it strikes.
const PL_KILL: i32 = 90;
/// Real blocks thrown out of the crater as it strikes (pl_thrown).
const PL_THROWN: usize = 90;

/// Where the object is and how it moves: everything worked out from the strike's seed and where the player stands.
/// It is shot down from orbit: it shows high in the sky over the far side of the target, off to one side of it as the
/// player looks, and comes down on one clean ballistic arc onto the target, a long shallow glide high up first, slow on
/// the sky, then steeper and faster, the last part a fast descent.
#[derive(Clone, Debug)]
pub(super) struct PlGeo {
    pub seed: u32,
    /// Which way it comes from (from the target, level), how far off it shows, and how high.
    dir: [f64; 3],
    dh: f64,
    y0: f64,
    /// The wind (blocks a second, x and z): the trail and the column drift with it.
    pub wind: (f64, f64),
}

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
fn len(a: [f64; 3]) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}

/// The arc's shape: at its start it already falls this much of its slope at the end (a shallow glide, steepening).
const PL_GLIDE: f64 = 0.25;
/// How far along the arc it is, against the time from showing to striking (0 to 1): this much of it a steady crawl
/// over the sky, the rest coming faster and faster.
const PL_CRAWL: f64 = 0.42;
const PL_RUSH: f64 = 3.5;

impl PlGeo {
    /// `me`: the player from the target's ground point.
    pub fn new(seed: f32, me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |k: u32| mh(k, seed, 0x9a1);
        let d = me[0].hypot(me[2]);
        // (from the target towards the player)
        let u = if d > 1.0 { [me[0] / d, 0.0, me[2] / d] } else { [0.0, 0.0, 1.0] };
        // it comes from beyond the target and well off to one side (50 to 65 degrees round from straight beyond it):
        // seen from the player, high in the sky ahead and off to one side, its arc crossing the sky to the target rather
        // than coming straight at them
        let side = if r(1) < 0.5 { -1.0 } else { 1.0 };
        let phi = (50.0 + 15.0 * r(2)).to_radians() * side;
        let (c, s) = (phi.cos(), phi.sin());
        let dir = [-u[0] * c + u[2] * s, 0.0, -u[2] * c - u[0] * s];
        let wa = TAU * r(9);
        let ws = 2.0 + 2.5 * r(10);
        PlGeo { seed, dir, dh: 1150.0 + 300.0 * r(3), y0: 1100.0 + 200.0 * r(4), wind: (wa.cos() * ws, wa.sin() * ws) }
    }
    /// How far along the arc it is at strike time `t`, 0 as it shows to 1 as it strikes.
    fn along(t: f64) -> f64 {
        let w = ((t - f64::from(PL_SEEN)) / f64::from(PL_HIT - PL_SEEN)).clamp(0.0, 1.0);
        PL_CRAWL * w + (1.0 - PL_CRAWL) * w.powf(PL_RUSH)
    }
    /// Where it is at strike time `t` (from the target's ground), from PL_SEEN to PL_HIT.
    pub fn pos(&self, t: f64) -> [f64; 3] {
        let u = Self::along(t);
        let y = self.y0 * (1.0 - (PL_GLIDE * u + (1.0 - PL_GLIDE) * u * u));
        add([0.0, y, 0.0], self.dir, self.dh * (1.0 - u))
    }
}

/// The column's billows: (launch after the strike, rise time, share of the column's height, radius, x and z off its
/// axis). The stem's low and narrow, then the body, then the head, the highest launched first.
pub(super) fn pl_puffs(seed: u32) -> Vec<[f64; 6]> {
    // (it bursts up fast, most of its height in a second, as it does in the clip, then swells and climbs slowly on:
    // the head first, the body and the narrower stem boiling up under it)
    (0..PL_PUFFS)
        .map(|i| {
            let h = |k: u32| mh(i as u32, seed, 0x5f0 + k);
            let (t0, hf, rad) = if i < 5 {
                (0.1 + 0.35 * h(0), 0.06 + 0.3 * (i as f64 / 5.0) + 0.06 * h(1), 22.0 + 10.0 * h(2))
            } else if i < 11 {
                (0.05 + 0.25 * h(0), 0.4 + 0.34 * ((i - 5) as f64 / 6.0) + 0.06 * h(1), 32.0 + 14.0 * h(2))
            } else {
                (0.0 + 0.12 * h(0), 0.74 + 0.28 * ((i - 11) as f64 / 7.0) + 0.05 * h(1), 50.0 + 18.0 * h(2))
            };
            let tau = 0.5 + 0.35 * h(3);
            let a = TAU * h(4);
            let off = rad * (0.2 + 0.55 * h(5)) * if i < 2 { 1.1 } else if i < 5 { 0.5 } else { 1.0 };
            [t0, tau, hf, rad, a.cos() * off, a.sin() * off]
        })
        .collect()
}

/// The pieces shed as it comes in through the air (see PL_FR). As in the third clip: a few glowing chunks breaking off
/// in the seconds before the dive, flung out to the side and falling away behind it, each burning a second or three
/// and trailing its own thin smoke; and in the last seconds a spray of small sparks off the fireball, gone in a moment.
pub(super) fn pl_fragments(g: &PlGeo) -> Vec<[f64; 11]> {
    let mut out = Vec::new();
    let vel = |t: f64| {
        let (a, b) = (g.pos(t - 0.02), g.pos(t + 0.02));
        [(b[0] - a[0]) / 0.04, (b[1] - a[1]) / 0.04, (b[2] - a[2]) / 0.04]
    };
    for i in 0..PL_CHUNKS + PL_SPARKS {
        let h = |k: u32| mh(i as u32, g.seed, 0x7a0 + k);
        let spark = i >= PL_CHUNKS;
        let hit = f64::from(PL_HIT);
        // (the chunks let go between 6.5 and 0.7 s before it strikes, more of them later; the sparks in the last 3.5)
        let t0 = if spark { hit - 3.5 + 3.3 * h(0).sqrt() } else { hit - 6.5 + 5.8 * h(0).powf(0.7) };
        let p0 = g.pos(t0);
        let v = vel(t0);
        let sp = len(v).max(1.0);
        let dir = [v[0] / sp, v[1] / sp, v[2] / sp];
        // (flung out across its path, a random way round it, a little up more often than down)
        let a = TAU * h(1);
        let side = {
            let up = if dir[1].abs() > 0.95 { [1.0, 0.0, 0.0] } else { [0.0, 1.0, 0.0] };
            let s1 = [dir[1] * up[2] - dir[2] * up[1], dir[2] * up[0] - dir[0] * up[2], dir[0] * up[1] - dir[1] * up[0]];
            let l1 = len(s1).max(1e-9);
            let s1 = [s1[0] / l1, s1[1] / l1, s1[2] / l1];
            let s2 = [dir[1] * s1[2] - dir[2] * s1[1], dir[2] * s1[0] - dir[0] * s1[2], dir[0] * s1[1] - dir[1] * s1[0]];
            add(add([0.0; 3], s1, a.cos()), s2, a.sin())
        };
        let kick = if spark { 40.0 + 110.0 * h(2) } else { 70.0 + 110.0 * h(2) };
        let keep = if spark { 0.55 + 0.3 * h(3) } else { 0.35 + 0.35 * h(3) };
        let v0 = add(add([0.0; 3], v, keep), side, kick);
        let v0 = add(v0, [0.0, 1.0, 0.0], if spark { 0.0 } else { 15.0 * h(4) });
        let life = if spark { 0.35 + 0.6 * h(5) } else { 1.5 + 2.2 * h(5) };
        let size = if spark { 0.25 + 0.35 * h(6) } else { 0.9 + 1.4 * h(6) };
        let drag = if spark { 1.8 + 1.5 * h(7) } else { 0.35 + 0.5 * h(7) };
        out.push([t0, life, size, if spark { 1.0 } else { 0.0 }, drag, p0[0], p0[1], p0[2], v0[0], v0[1], v0[2]]);
    }
    out
}

/// What the pass reads (see PL_P): worked out on the tick after it fires.
pub(super) fn pl_table(seed: f32, me: [f64; 3]) -> Vec<u32> {
    let g = PlGeo::new(seed, me);
    let mut w = vec![0.0f32; PL_FR + (PL_CHUNKS + PL_SPARKS) * PL_FW];
    let dt = f64::from(PL_HIT - PL_SEEN) / (PL_N - 1) as f64;
    w[0] = PL_N as f32;
    w[1] = PL_SEEN;
    w[2] = dt as f32;
    w[3] = g.wind.0 as f32;
    w[4] = g.wind.1 as f32;
    w[5] = PL_HC as f32;
    w[6] = PL_PUFFS as f32;
    for i in 0..PL_N {
        let p = g.pos(f64::from(PL_SEEN) + dt * i as f64);
        for k in 0..3 {
            w[PL_P + 3 * i + k] = p[k] as f32;
        }
    }
    for (i, p) in pl_puffs(g.seed).iter().enumerate() {
        for k in 0..6 {
            w[PL_PF + PL_PW * i + k] = p[k] as f32;
        }
    }
    w[7] = (PL_CHUNKS + PL_SPARKS) as f32;
    w[8] = PL_DEBRIS as f32;
    for (i, f) in pl_fragments(&g).iter().enumerate() {
        for k in 0..11 {
            w[PL_FR + PL_FW * i + k] = f[k] as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

/// The debris the pass draws (chunks and specks of earth thrown out, falling back far round it): from PL_DB, PL_DW words
/// each, worked out once here rather than for every chunk at every pixel: its bearing (x and z), how far out it is torn
/// up, its speed out and up, when it is thrown (after the strike), its size, e^(k t0) (k its drag), its spin. Keep in
/// step with payload.wgsl's pl_chunk.
pub(super) const PL_DB: usize = 10496;
pub(super) const PL_DW: usize = 10;
pub(super) const PL_DEBRIS: usize = 120;
fn pl_debris_words(seed: u32) -> Vec<u32> {
    let mut w = vec![0.0f32; PL_DEBRIS * PL_DW];
    let v = f64::from(343.0f32);
    for i in 0..PL_DEBRIS {
        let h = |k: u32| mh(i as u32, seed, k);
        let ang = h(0x301) * TAU;
        let big = h(0x303);
        // (torn up all over the blast's middle, each as the blast reaches it, not all from one point: most thrown a
        // few hundred blocks, a third far, some of those coming down round the player)
        let r0 = 6.0 + 40.0 * h(0x306).sqrt();
        let far = h(0x307) < 0.35;
        let el = if far { 0.45 + 0.4 * h(0x302) } else { 0.35 + 0.85 * h(0x302) };
        let sp = (if far { 90.0 + 45.0 * h(0x304) } else { 30.0 + 50.0 * h(0x304).powf(0.7) }) * (1.0 - 0.25 * big);
        let t0 = r0 / v + 0.12 * h(0x305);
        let row = [ang.cos(), ang.sin(), r0, el.cos() * sp, el.sin() * sp, t0, 0.12 + 0.98 * big * big * big, (0.06 * t0).exp(), 3.0 + 6.0 * h(0x308), 0.0];
        for (k, x) in row.iter().enumerate() {
            w[PL_DW * i + k] = *x as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

// ---- the land's shape round it, for the pass: the dust follows it ----------------------------------------------
/// A coarse heightfield of the land round the target, for the pass (the dust and the shockwave hug it, climbing the
/// hills, filling the hollows, thinner in the lee of a ridge): PL_HN x PL_HN cells over a square PL_HF's second word
/// across each way from the target. From PL_HF: the cells a side, that half-width, the lowest and highest ground (from
/// the target's), then from PL_HF + 8 a word a cell: its height in the low 16 bits (an eighth of a block, from 512 under
/// the target's ground), how sheltered it is from the blast by the land between in the next 8 (0 to 255).
pub(super) const PL_HF: usize = 1024;
pub(super) const PL_HN: usize = 96;
/// How far the heightfield reaches round the target, for a player `dme` off.
fn pl_hf_reach(dme: f64) -> f64 {
    (dme * 1.25 + 150.0).clamp(260.0, 1150.0)
}
/// The columns the heightfield is read from (row by row, z then x).
fn pl_hf_columns(bx: i32, bz: i32, reach: f64) -> Vec<(i32, i32)> {
    let n = PL_HN as i32;
    let step = 2.0 * reach / f64::from(n - 1);
    let at = |i: i32| (-reach + step * f64::from(i)).round() as i32;
    (0..n).flat_map(|k| (0..n).map(move |i| (bx + at(i), bz + at(k)))).collect()
}
/// The heightfield's ground (from the target's), from what the world gave (the first air over each column; none where
/// the land was not loaded, the mean of what was there: not the player's height, who may be up a tower or flying), a
/// trunk or a pillar caught in a cell put down to the ground round it.
fn pl_hf_ground(heights: &[Option<f64>], reach: f64, _me: [f64; 3]) -> Vec<f64> {
    let _ = reach;
    let n = PL_HN;
    let (sum, cnt) = heights.iter().flatten().fold((0.0, 0.0), |(s, c), &h| (s + h, c + 1.0));
    let guess = if cnt > 0.0 { sum / cnt } else { 0.0 };
    let raw: Vec<f64> = heights.iter().map(|h| h.unwrap_or(guess)).collect();
    let mut h = raw.clone();
    for k in 1..n - 1 {
        for i in 1..n - 1 {
            let c = k * n + i;
            let mut v = [raw[c - 1], raw[c + 1], raw[c - n], raw[c + n]];
            v.sort_by(f64::total_cmp);
            let med = 0.5 * (v[1] + v[2]);
            if raw[c] > med + 4.0 {
                h[c] = med;
            }
        }
    }
    h
}
/// How sheltered the cells of rows k0..k1 are: how far the land between each and the blast stands over the line from
/// the blast, a few blocks up, to just over the cell's ground (0 to 1).
fn pl_hf_shelter(h: &[f64], reach: f64, k0: usize, k1: usize) -> Vec<f64> {
    let n = PL_HN;
    let step = 2.0 * reach / (n - 1) as f64;
    let pos = |i: usize| -reach + step * i as f64;
    let at = |x: f64, z: f64| {
        let fi = ((x + reach) / step).clamp(0.0, (n - 1) as f64);
        let fk = ((z + reach) / step).clamp(0.0, (n - 1) as f64);
        let (i, k) = ((fi as usize).min(n - 2), (fk as usize).min(n - 2));
        let (u, v) = (fi - i as f64, fk - k as f64);
        let c = k * n + i;
        (h[c] * (1.0 - u) + h[c + 1] * u) * (1.0 - v) + (h[c + n] * (1.0 - u) + h[c + n + 1] * u) * v
    };
    (k0 * n..k1 * n)
        .map(|c| {
            let (x, z) = (pos(c % n), pos(c / n));
            let r = x.hypot(z);
            if r < 30.0 {
                return 0.0;
            }
            let (src, dst) = (8.0, h[c] + 3.0);
            let steps = ((r / step) as usize).clamp(2, 10);
            let mut over: f64 = 0.0;
            for j in 1..steps {
                let f = j as f64 / steps as f64;
                over = over.max(at(x * f, z * f) - (src + (dst - src) * f));
            }
            let s = (over / 14.0).clamp(0.0, 1.0);
            s * s * (3.0 - 2.0 * s)
        })
        .collect()
}
/// The heightfield's words (from PL_HF).
fn pl_hf_pack(h: &[f64], shelter: &[f64], reach: f64) -> Vec<u32> {
    let (lo, hi) = h.iter().fold((f64::MAX, f64::MIN), |(a, b), &x| (a.min(x), b.max(x)));
    let mut w = vec![(PL_HN as f32).to_bits(), (reach as f32).to_bits(), (lo as f32).to_bits(), (hi as f32).to_bits(), 0, 0, 0, 0];
    let q = |x: f64| ((x + 512.0) * 8.0).round().clamp(0.0, 65535.0) as u32;
    let b = |x: f64| (x * 255.0).round().clamp(0.0, 255.0) as u32;
    w.extend(h.iter().zip(shelter).map(|(&g, &s)| q(g) | b(s) << 16));
    w
}
/// All of it at once (the tests, tools/preview).
#[cfg(test)]
fn pl_hf_words(heights: &[Option<f64>], reach: f64, me: [f64; 3]) -> Vec<u32> {
    let h = pl_hf_ground(heights, reach, me);
    let s = pl_hf_shelter(&h, reach, 0, PL_HN);
    pl_hf_pack(&h, &s, reach)
}
/// The heightfield, once the world has answered (asking again a little later until it has, while there is time): its
/// ground on one stage, its shelter on three more (each well under a tick's fuel), then sent.
fn pl_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, me: [f64; 3], gy: i32, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < PL_HIT {
            q.later(at_t + 0.2, move |q| pl_hf_step(q, tag, columns, reach, me, gy, at_t + 0.2));
        }
        return;
    }
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    let h = Rc::new(pl_hf_ground(&heights, reach, me));
    let parts = 3;
    let shelter: Rc<RefCell<Vec<f64>>> = Default::default();
    for j in 0..parts {
        let (h, shelter) = (h.clone(), shelter.clone());
        let t = at_t + 0.05 * (j + 1) as f32;
        q.later(t, move |q| {
            let (k0, k1) = (j * PL_HN / parts, (j + 1) * PL_HN / parts);
            shelter.borrow_mut().extend(pl_hf_shelter(&h, reach, k0, k1));
            if j + 1 == parts {
                q.ev.push((t, Act::Words { index: PL_HF as u32, words: pl_hf_pack(&h, &shelter.borrow(), reach) }));
            }
        });
    }
}

// ---- the land, read from the world ------------------------------------------------------------------------------
/// What a block is to the blast: nothing, water or lava (left alone), leaves, a log, something standing on the ground
/// (plants, snow, fences, a shed), or the ground itself.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Air,
    Fluid,
    Leaves,
    Log,
    Loose,
    Ground,
}
const WOODS: [&str; 9] = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak"];
const LOG_X: [&str; 9] = [
    "minecraft:oak_log[axis=x]",
    "minecraft:spruce_log[axis=x]",
    "minecraft:birch_log[axis=x]",
    "minecraft:jungle_log[axis=x]",
    "minecraft:acacia_log[axis=x]",
    "minecraft:dark_oak_log[axis=x]",
    "minecraft:mangrove_log[axis=x]",
    "minecraft:cherry_log[axis=x]",
    "minecraft:pale_oak_log[axis=x]",
];
const LOG_Z: [&str; 9] = [
    "minecraft:oak_log[axis=z]",
    "minecraft:spruce_log[axis=z]",
    "minecraft:birch_log[axis=z]",
    "minecraft:jungle_log[axis=z]",
    "minecraft:acacia_log[axis=z]",
    "minecraft:dark_oak_log[axis=z]",
    "minecraft:mangrove_log[axis=z]",
    "minecraft:cherry_log[axis=z]",
    "minecraft:pale_oak_log[axis=z]",
];
const LOG_Y: [&str; 9] = [
    "minecraft:oak_log",
    "minecraft:spruce_log",
    "minecraft:birch_log",
    "minecraft:jungle_log",
    "minecraft:acacia_log",
    "minecraft:dark_oak_log",
    "minecraft:mangrove_log",
    "minecraft:cherry_log",
    "minecraft:pale_oak_log",
];
const LEAF_NAMES: [&str; 9] = [
    "minecraft:oak_leaves",
    "minecraft:spruce_leaves",
    "minecraft:birch_leaves",
    "minecraft:jungle_leaves",
    "minecraft:acacia_leaves",
    "minecraft:dark_oak_leaves",
    "minecraft:mangrove_leaves",
    "minecraft:cherry_leaves",
    "minecraft:pale_oak_leaves",
];
const LEAVES: [&str; 9] = [
    "minecraft:oak_leaves[persistent=true]",
    "minecraft:spruce_leaves[persistent=true]",
    "minecraft:birch_leaves[persistent=true]",
    "minecraft:jungle_leaves[persistent=true]",
    "minecraft:acacia_leaves[persistent=true]",
    "minecraft:dark_oak_leaves[persistent=true]",
    "minecraft:mangrove_leaves[persistent=true]",
    "minecraft:cherry_leaves[persistent=true]",
    "minecraft:pale_oak_leaves[persistent=true]",
];
fn wood_of(name: &str, suffix: &str) -> u8 {
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    n.strip_suffix(suffix).and_then(|w| WOODS.iter().position(|x| *x == w)).map_or(0, |i| i as u8)
}
fn kind(name: &str) -> (Kind, u8) {
    let n = name.strip_prefix("minecraft:").unwrap_or(name);
    if n.ends_with("air") {
        return (Kind::Air, 0);
    }
    if matches!(n, "water" | "lava" | "bubble_column" | "seagrass" | "tall_seagrass" | "kelp" | "kelp_plant") {
        return (Kind::Fluid, 0);
    }
    if n.ends_with("_leaves") {
        return (Kind::Leaves, wood_of(name, "_leaves"));
    }
    if n.ends_with("_log") || n.ends_with("_wood") || n.ends_with("_stem") {
        return (Kind::Log, wood_of(name, "_log"));
    }
    const GROUND: [&str; 34] = [
        "grass_block", "dirt", "podzol", "mycelium", "stone", "deepslate", "sand", "gravel", "clay", "terracotta", "ice",
        "snow_block", "mud", "moss_block", "granite", "diorite", "andesite", "tuff", "calcite", "basalt", "blackstone",
        "netherrack", "_ore", "bedrock", "sandstone", "rooted_dirt", "farmland", "dirt_path", "obsidian", "magma_block",
        "pale_moss_block", "soul_sand", "soul_soil", "cobblestone",
    ];
    if GROUND.iter().any(|g| n.contains(g)) && !n.contains("_slab") && !n.contains("_stairs") && !n.contains("_wall") {
        return (Kind::Ground, u8::from(n == "grass_block") + 2 * u8::from(n == "dirt" || n == "podzol" || n == "mycelium" || n == "rooted_dirt"));
    }
    (Kind::Loose, 0)
}

/// A column as read: its ground block's height, the highest block over it (its ground if nothing stands on it), the
/// trunk standing on it (its height and wood), the leaves over it, what its ground is (1 grass, 2 dirt), and whether
/// water or lava is there (left alone).
#[derive(Clone, Copy, Debug, Default)]
struct Column {
    known: bool,
    fluid: bool,
    /// The fluid is lava (kept apart, sealed as ever).
    lava: bool,
    /// The water's own surface here (not what hangs over it).
    wtop: i32,
    g: i32,
    top: i32,
    trunk: u8,
    wood: u8,
    leaves: u8,
    ground: u8,
}

struct Land {
    cols: Vec<Column>,
    missing: Vec<(i32, i32)>,
}
type Shared = Rc<RefCell<Land>>;

fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    let (i, k) = (x - bx + PL_READ, z - bz + PL_READ);
    if i < 0 || k < 0 || i >= PL_GW || k >= PL_GW {
        return None;
    }
    land.cols.get((k * PL_GW + i) as usize).filter(|c| c.known)
}

/// The columns read in part `part` (rows of the square, within PL_READ of the target).
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let rows = (PL_GW + PL_PARTS - 1) / PL_PARTS;
    let mut out = Vec::new();
    for k in part * rows..((part + 1) * rows).min(PL_GW) {
        let dz = k - PL_READ;
        for dx in -PL_READ..=PL_READ {
            if dx * dx + dz * dz <= PL_READ * PL_READ {
                out.push((bx + dx, bz + dz));
            }
        }
    }
    out
}

/// One answer taken in: each column's ground, what stands on it and over it.
fn take_in(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32) {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    let lavas: Vec<bool> = a.palette.iter().map(|n| n.contains("lava")).collect();
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else {
            land.missing.push((x, z));
            continue;
        };
        let base = surface - a.below;
        let mut c = Column { known: true, leaves: 255, ..Default::default() };
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
                    if !c.fluid {
                        c.wtop = base + j as i32;
                    }
                    c.fluid = true;
                    c.lava |= lavas.get(blocks[j] as usize).copied().unwrap_or(false);
                    top.get_or_insert(base + j as i32);
                }
                Kind::Leaves => {
                    if c.leaves == 255 {
                        c.leaves = w;
                    }
                    top.get_or_insert(base + j as i32);
                }
                _ => {
                    top.get_or_insert(base + j as i32);
                }
            }
        }
        let Some(gj) = g else {
            // (no ground within reach: a very tall tree, or over the void; left alone)
            continue;
        };
        c.g = base + gj as i32;
        c.top = top.unwrap_or(c.g);
        let mut n = 0;
        while gj + 1 + n < blocks.len() {
            match kinds.get(blocks[gj + 1 + n] as usize) {
                Some(&(Kind::Log, w)) => {
                    c.wood = w;
                    n += 1;
                }
                _ => break,
            }
        }
        c.trunk = n.min(40) as u8;
        let (ii, kk) = (x - bx + PL_READ, z - bz + PL_READ);
        if (0..PL_GW).contains(&ii) && (0..PL_GW).contains(&kk) {
            land.cols[(kk * PL_GW + ii) as usize] = c;
        }
    }
}

/// The land's parts taken in a stage each, as they are answered (and the columns not loaded yet asked again, once).
fn pl_land_step(q: &mut Plan, land: Shared, tags: Rc<Vec<u32>>, part: usize, at_t: f32, retry: u32) {
    if part >= tags.len() {
        let missing = std::mem::take(&mut land.borrow_mut().missing);
        if !missing.is_empty() && retry < 2 && at_t < PL_HIT - 4.0 {
            let tag = crate::columns::new_tag();
            let t = at_t + 0.8;
            q.later(t, move |q| {
                q.ev.push((t, Act::Read { tag, columns: missing, below: PL_BELOW, above: PL_ABOVE }));
                q.later(t + 0.15, move |q| pl_land_step(q, land, Rc::new(vec![tag]), 0, t + 0.15, retry + 1));
            });
        }
        return;
    }
    let Some(a) = crate::columns::get(tags[part]) else {
        if at_t < PL_HIT - 4.0 {
            q.later(at_t + 0.1, move |q| pl_land_step(q, land, tags, part, at_t + 0.1, retry));
        }
        return;
    };
    take_in(&mut land.borrow_mut(), &a, q.bx, q.bz);
    q.later(at_t + 0.05, move |q| pl_land_step(q, land, tags, part + 1, at_t + 0.05, retry));
}

// ---- the crater and what lies round it -------------------------------------------------------------------------------
/// The crater's shape round the target: its edge wanders.
#[derive(Clone, Copy)]
struct Shape {
    cx: f64,
    cz: f64,
    ph: [f64; 3],
    seed: u32,
}
impl Shape {
    fn wob(&self, a: f64) -> f64 {
        1.0 + 0.1 * (3.0 * a + self.ph[0]).sin() + 0.06 * (5.0 * a + self.ph[1]).sin() + 0.035 * (9.0 * a + self.ph[2]).sin()
    }
    /// What the blast makes of column (x, z): how far its ground goes down (or up, its rim's heap), whether it is
    /// flattened, and how far out it is (in the crater's radii).
    fn at(&self, x: i32, z: i32) -> (f64, f64, f64) {
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let r = dx.hypot(dz);
        let a = dz.atan2(dx);
        let rc = PL_CRATER_R * self.wob(a) * (0.94 + 0.12 * vnoise(f64::from(x), f64::from(z), 7.0, self.seed ^ 0x31));
        (r, a, r / rc)
    }
    fn flat(&self, a: f64) -> f64 {
        PL_FLAT * (1.0 + 0.08 * (2.0 * a + self.ph[2]).sin() + 0.05 * (7.0 * a + self.ph[0]).sin())
    }
}
/// How deep the crater is at u (its radii out): a bowl; and how high its rim's heap stands past it.
fn bowl(u: f64) -> f64 {
    if u < 1.0 { PL_CRATER_D * (1.0 - u * u).powf(0.75) } else { 0.0 }
}
fn heap(u: f64) -> f64 {
    if u < 1.0 || u > PL_RIM { 0.0 } else { 3.4 * (-(u - 1.12).powi(2) / 0.06).exp() + 0.6 * (1.0 - (u - 1.0) / (PL_RIM - 1.0)) }
}
/// The scorched ground of the crater's floor and walls: broad patches of one or another.
fn scorched(x: i32, y: i32, z: i32, u: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) + f64::from(y) * 0.37, f64::from(z), 4.5, seed ^ 0x51);
    let m = vnoise(f64::from(x), f64::from(z) - f64::from(y) * 0.5, 2.2, seed ^ 0x52);
    if u < 0.55 && n > 0.62 {
        "minecraft:blackstone"
    } else if n > 0.7 {
        "minecraft:basalt"
    } else if n < 0.22 {
        "minecraft:tuff"
    } else if m > 0.72 {
        "minecraft:gravel"
    } else if m < 0.2 {
        "minecraft:cobbled_deepslate"
    } else {
        "minecraft:coarse_dirt"
    }
}
/// The rim's heap: earth and broken rock thrown out of the crater.
fn ejecta(x: i32, y: i32, z: i32, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) * 1.3 + f64::from(y) * 0.71, f64::from(z) * 1.3, 3.0, seed ^ 0x61);
    if n > 0.74 {
        "minecraft:cobblestone"
    } else if n > 0.62 {
        "minecraft:stone"
    } else if n < 0.2 {
        "minecraft:rooted_dirt"
    } else if n < 0.45 {
        "minecraft:coarse_dirt"
    } else {
        "minecraft:dirt"
    }
}
/// The charred grass round it: coarse dirt and podzol, patchier further out.
fn charred(x: i32, z: i32, r: f64, seed: u32) -> Option<&'static str> {
    let n = vnoise(f64::from(x), f64::from(z), 6.0, seed ^ 0x71);
    let m = vnoise(f64::from(x), f64::from(z), 2.0, seed ^ 0x72);
    let reach = 0.12 + 0.68 * (1.0 - ((r - 30.0) / (PL_CHAR - 30.0)).clamp(0.0, 1.0)).powf(1.5);
    if 0.55 * n + 0.45 * m > 1.0 - reach {
        Some(if m > 0.66 { "minecraft:podzol" } else if n > 0.7 { "minecraft:dirt" } else { "minecraft:coarse_dirt" })
    } else {
        None
    }
}

/// How hard the blast still hits column (x, z) in the band past the flattened land: 1 at its inner edge, to 0 at its
/// outer (None outside it).
fn band(s: &Shape, x: i32, z: i32) -> Option<f64> {
    let (r, a, _) = s.at(x, z);
    let e = r - s.flat(a);
    (0.0..PL_BAND).contains(&e).then(|| 1.0 - e / PL_BAND)
}
/// A tree in the band knocked flat (more of them near the flattened land).
fn knocked(c: &Column, s: &Shape, x: i32, z: i32) -> bool {
    c.trunk >= 3 && !c.fluid && band(s, x, z).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x91) < 0.55 * p.powf(1.3))
}
/// What the blast makes of column (x, z): Kept, or its new ground's top (`Some`) and whether it was cleared.
fn new_ground(c: &Column, s: &Shape, x: i32, z: i32) -> Option<i32> {
    let (r, a, u) = s.at(x, z);
    if u < 1.0 {
        Some(c.g - bowl(u).round() as i32)
    } else if u < PL_RIM {
        Some(c.g + heap(u).round() as i32)
    } else if r < s.flat(a) || knocked(c, s, x, z) {
        Some(c.g)
    } else {
        None
    }
}
/// Water or lava within a column's reach: dig nothing there or next to it.
fn wet_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid))
}

/// When the blast reaches radius r of the land (its edits go in from the middle out with the shockwave).
fn pl_wave(r: f64) -> f32 {
    PL_HIT + 0.05 + (r / 343.0) as f32
}
fn pl_wave_at(s: &Shape, x: i32, z: i32) -> f32 {
    pl_wave((f64::from(x) + 0.5 - s.cx).hypot(f64::from(z) + 0.5 - s.cz))
}
/// How far down the ground under column (x, z)'s new floor `top` is opened to its neighbours (nuke.rs's seal_lo).
fn seal_lo(land: &Land, bx: i32, bz: i32, x: i32, z: i32, top: i32, r: f64, ang: f64, u: f64) -> i32 {
    let rc = if u > 1e-6 { r / u } else { PL_CRATER_R };
    let (ca, sa) = (ang.cos(), ang.sin());
    let mut lo = top;
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let Some(n) = at(land, bx, bz, x + dx, z + dz) else { continue };
        let un = u + (f64::from(dx) * ca + f64::from(dz) * sa) / rc;
        let f = if un < 1.0 { n.g - bowl(un.max(0.0)).round() as i32 } else { n.g };
        lo = lo.min(f);
    }
    lo - 3
}
/// The crater, the rim's heap, the flattened land and the charred grass, over rows k0..k1 of the land's square.
fn pl_blast_rows(q: &mut Plan, land: &Land, s: &Shape, k0: i32, k1: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut b = Blocks::default();
    for k in k0..k1 {
        for i in 0..PL_GW {
            let (x, z) = (bx - PL_READ + i, bz - PL_READ + k);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            let (r, ang, u) = s.at(x, z);
            if r > f64::from(PL_READ) || c.lava {
                continue;
            }
            let wet = wet_near(land, bx, bz, x, z);
            match new_ground(c, s, x, z) {
                Some(top) if top < c.g => {
                    // the crater: dug, everything over it gone, its new face scorched (two deep near the middle), the
                    // lava under it sealed; cut into the water as into the land: below the water's level it is filled
                    // with still water (no higher than the land stood), not left dry behind a wall
                    // (water it cuts into goes like any other block: what is left of it flows in, as round TNT)
                    b.run(x, z, top + 1, c.top.max(c.g), "minecraft:air");
                    // (the lava in the ground it bares sealed: its floor and the faces it opens)
                    let lo = seal_lo(land, bx, bz, x, z, top, r, ang, u);
                    b.put(x, z, lo, top - 1, "minecraft:stone", Some("minecraft:lava"), false);
                    let d = if u < 0.6 { 1 } else { 0 };
                    for y in top - d..=top {
                        b.run(x, z, y, y, scorched(x, y, z, u, s.seed));
                    }
                }
                Some(top) if top > c.g && !wet && !c.fluid => {
                    // the rim: earth heaped on it, what stood there swept off (none heaped in or by the water)
                    for y in c.g + 1..=top {
                        b.run(x, z, y, y, ejecta(x, y, z, s.seed));
                    }
                    if c.top > top {
                        b.run(x, z, top + 1, c.top, "minecraft:air");
                    }
                    if u < 1.1 {
                        let lo = seal_lo(land, bx, bz, x, z, c.g, r, ang, u);
                        if lo < c.g - 3 {
                            b.put(x, z, lo, c.g, "minecraft:stone", Some("minecraft:lava"), false);
                        }
                    }
                }
                _ if c.fluid => {}
                Some(_) => {
                    // flattened: everything standing on the land swept off (a felled tree's stump left), the grass charred
                    let stump = if c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, s.seed, 0x81) * 2.0) as i32 } else { 0 };
                    if c.top > c.g + stump {
                        b.run(x, z, c.g + 1 + stump, c.top, "minecraft:air");
                    }
                    if c.ground == 1
                        && let Some(m) = charred(x, z, r, s.seed)
                    {
                        b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                    }
                }
                None => {
                    if c.ground == 1
                        && let Some(m) = charred(x, z, r, s.seed)
                    {
                        b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                    }
                    // in the band past it: the crowns stripped, in patches, wholly near it and their tops further out
                    if let Some(p) = band(s, x, z)
                        && c.leaves != 255
                        && vnoise(f64::from(x), f64::from(z), 5.0, s.seed ^ 0x93) < 0.25 + 0.75 * p
                    {
                        let keep = ((f64::from(c.top - c.g)) * (1.0 - (0.35 + 0.8 * p).min(1.0))).floor() as i32;
                        b.put(x, z, c.g + 1 + keep, c.top, "minecraft:air", Some(LEAF_NAMES[c.leaves as usize]), false);
                    }
                }
            }
        }
    }
    // (in from the middle out, as the shockwave reaches each column)
    for (t, b) in b.split_by(|x, z| pl_wave_at(s, x, z)) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}
/// What is left hanging round what changed over rows k0..k1 (leaves of a tree whose trunk went, plants whose ground
/// went), on a stage of its own.
fn pl_tidy_rows(q: &mut Plan, land: &Land, s: &Shape, k0: i32, k1: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let col = |x: i32, z: i32| -> Col {
        match at(land, bx, bz, x, z) {
            Some(c) if !c.fluid && new_ground(c, s, x, z).is_some() => Col::Cleared,
            _ => Col::Kept,
        }
    };
    let t = tidy(bx - PL_READ, bz - PL_READ + k0, bx + PL_READ, bz - PL_READ + k1 - 1, 40, -1, col);
    for (t, b) in t.split_by(|x, z| pl_wave_at(s, x, z) + 0.15) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}

/// The trees felled, lying on the land pointing away from the blast (their leaves crushed round their crowns, stripped
/// off near it), and the rubble strewn over it all, landing a few seconds after.
type Used = Rc<RefCell<std::collections::HashSet<(i32, i32)>>>;
fn pl_felled(q: &mut Plan, land: &Land, s: &Shape, used: &Used, k0: i32, k1: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut used = used.borrow_mut();
    let mut b = Blocks::default();
    // (a column a log may lie on: flattened, not the crater or its rim, dry, its ground near the last one's)
    let lie = |x: i32, z: i32, gy: i32| -> Option<i32> {
        let c = at(land, bx, bz, x, z)?;
        let (r, a, u) = s.at(x, z);
        if c.fluid || u < PL_RIM || (c.g - gy).abs() > 1 || wet_near(land, bx, bz, x, z) {
            return None;
        }
        // (past the flattened land: only on open ground)
        if r > s.flat(a) - 1.0 && (band(s, x, z).is_none() || c.trunk > 0 || c.top > c.g + 1) {
            return None;
        }
        Some(c.g)
    };
    for k in k0..k1 {
        for i in 0..PL_GW {
            let (x, z) = (bx - PL_READ + i, bz - PL_READ + k);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            if c.trunk < 3 || c.fluid {
                continue;
            }
            let (r, a, u) = s.at(x, z);
            if u < PL_RIM || (r > s.flat(a) - 1.0 && !knocked(c, s, x, z)) {
                continue;
            }
            let (dx, dz) = (a.cos(), a.sin());
            let (sx, sz, log) = if dx.abs() > dz.abs() { (dx.signum() as i32, 0, LOG_X[c.wood as usize]) } else { (0, dz.signum() as i32, LOG_Z[c.wood as usize]) };
            let h = |kk: u32| mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, s.seed, kk);
            let want = (i32::from(c.trunk) - 1).clamp(2, 4 + (h(1) * 4.0) as i32);
            let mut last = None;
            let mut gy = c.g;
            for n in 1..=want {
                let (lx, lz) = (x + sx * n, z + sz * n);
                if used.contains(&(lx, lz)) {
                    break;
                }
                let Some(g2) = lie(lx, lz, gy) else { break };
                b.run(lx, lz, g2 + 1, g2 + 1, log);
                used.insert((lx, lz));
                gy = g2;
                last = Some((lx, lz, g2));
            }
            // (the crown crushed round its end, further out where the blast has not stripped it)
            if let (Some((lx, lz, _)), true) = (last, r > 46.0 && c.leaves != 255) {
                let leaves = LEAVES[c.leaves as usize];
                for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx), (sx - sz, sz - sx)] {
                    let (fx, fz) = (lx + ox, lz + oz);
                    if used.contains(&(fx, fz)) {
                        continue;
                    }
                    if let Some(g2) = lie(fx, fz, gy) {
                        b.run(fx, fz, g2 + 1, g2 + 1, leaves);
                        used.insert((fx, fz));
                    }
                }
            }
            // (and the stump: what is left standing of the trunk, its top broken)
            let _ = LOG_Y;
        }
    }
    // (each log down once the blast has swept where it lies)
    for (t, b) in b.split_by(|x, z| pl_wave_at(s, x, z) + 0.3) {
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
}
/// The rubble: chunks of the ground thrown out, more near it, landing over a few seconds.
fn pl_rubble(q: &mut Plan, land: &Land, s: &Shape, used: &Used) {
    let (bx, bz) = (q.bx, q.bz);
    let mut used = used.borrow_mut();
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7e57);
    let mut waves: Vec<Blocks> = (0..4).map(|_| Blocks::default()).collect();
    const RUBBLE: [&str; 9] = [
        "minecraft:cobblestone",
        "minecraft:cobblestone",
        "minecraft:stone",
        "minecraft:coarse_dirt",
        "minecraft:dirt",
        "minecraft:cobbled_deepslate",
        "minecraft:tuff",
        "minecraft:andesite",
        "minecraft:mossy_cobblestone",
    ];
    for _ in 0..220 {
        let r = PL_CRATER_R * 1.05 + (PL_RUBBLE - PL_CRATER_R * 1.05) * rng.next().powf(1.7);
        let a = rng.uniform(0.0, TAU);
        let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
        let Some(c) = at(land, bx, bz, x, z) else { continue };
        if c.fluid || used.contains(&(x, z)) || wet_near(land, bx, bz, x, z) {
            continue;
        }
        let y = match new_ground(c, s, x, z) {
            Some(top) => top + 1,
            // (past the flattened land: only where nothing taller than a plant stands)
            None if c.top <= c.g + 1 && c.trunk == 0 => c.g + 1,
            None => continue,
        };
        let m = *rng.pick(&RUBBLE);
        let w = ((r / PL_RUBBLE) * 3.99) as usize;
        waves[w.min(3)].run(x, z, y, y, m);
        used.insert((x, z));
        // (now and then a bigger chunk: two side by side)
        if rng.next() < 0.25 && r < 60.0 {
            let (x2, z2) = (x + rng.int(-1, 1), z + rng.int(-1, 1));
            if !used.contains(&(x2, z2))
                && let Some(c2) = at(land, bx, bz, x2, z2)
                && !c2.fluid
                && let Some(t2) = new_ground(c2, s, x2, z2)
                && t2 + 1 == y
            {
                waves[w.min(3)].run(x2, z2, y, y, m);
                used.insert((x2, z2));
            }
        }
    }
    // leaves and broken branches strewn over the outer land and the band, of the wood that grows here
    let mut woods = [0u32; 9];
    for c in land.cols.iter().filter(|c| c.known && c.trunk > 0) {
        woods[c.wood as usize] += 1;
    }
    let wood = (0..9).max_by_key(|&i| woods[i]).unwrap_or(0);
    if woods[wood] > 0 {
        for n in 0..300 {
            let r = 45.0 + (PL_FLAT * 1.1 + PL_BAND - 45.0) * rng.next().powf(0.8);
            let a = rng.uniform(0.0, TAU);
            let (x, z) = ((s.cx + a.cos() * r).floor() as i32, (s.cz + a.sin() * r).floor() as i32);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            if c.fluid || used.contains(&(x, z)) || wet_near(land, bx, bz, x, z) {
                continue;
            }
            let y = match new_ground(c, s, x, z) {
                Some(top) if top == c.g => top + 1,
                None if c.top <= c.g + 1 && c.trunk == 0 => c.g + 1,
                _ => continue,
            };
            let m = if n % 6 == 0 { if rng.next() < 0.5 { LOG_X[wood] } else { LOG_Z[wood] } } else { LEAVES[wood] };
            waves[3].run(x, z, y, y, m);
            used.insert((x, z));
        }
    }
    for (i, w) in waves.into_iter().enumerate() {
        if !w.runs.is_empty() {
            q.ev.push((PL_HIT + 1.6 + 1.1 * i as f32, Act::Blocks(Box::new(w))));
        }
    }
}

/// Real blocks thrown out of the crater as it is blasted open: the ground that was there (grass and dirt off its top, the
/// stone and tuff under it, now and then a log of the wood growing round it), flung outward and up over the first second
/// and a half, at all speeds, so some come down by the rim and some arc far out over the flattened land. Some land as
/// blocks, the rest break up where they land (CancelDrop); none drops an item.
fn pl_thrown(q: &mut Plan, land: &Land, s: &Shape) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410);
    let mut woods = [0u32; 9];
    for c in land.cols.iter().filter(|c| c.known && c.trunk > 0) {
        woods[c.wood as usize] += 1;
    }
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let mut n = 0;
    for _ in 0..PL_THROWN * 3 {
        if n >= PL_THROWN {
            break;
        }
        // (from anywhere in the crater, more from its middle)
        let r = PL_CRATER_R * 0.85 * rng.next().sqrt();
        let a = rng.uniform(0.0, TAU);
        let (x, z) = (s.cx + a.cos() * r, s.cz + a.sin() * r);
        let (ix, iz) = (x.floor() as i32, z.floor() as i32);
        let Some(c) = at(land, bx, bz, ix, iz) else { continue };
        if !c.known || c.fluid || wet_near(land, bx, bz, ix, iz) {
            continue;
        }
        let deep = rng.next();
        let blk = match (c.ground, deep) {
            (_, d) if d < 0.08 && wood.is_some() => LOG_Y[wood.unwrap_or(0)],
            (1, d) if d < 0.4 => "minecraft:grass_block",
            (1 | 2, d) if d < 0.62 => "minecraft:dirt",
            (_, d) if d < 0.72 => "minecraft:coarse_dirt",
            (_, d) if d < 0.82 => "minecraft:cobblestone",
            (_, d) if d < 0.9 => "minecraft:stone",
            (_, d) if d < 0.96 => "minecraft:tuff",
            _ => "minecraft:cobbled_deepslate",
        };
        // (outward from the middle (straight up near it, leaning out further off), at speeds from a lob that lands by
        // the rim to a hard throw that comes down a hundred blocks off; blocks a tick)
        let ang = if r > 1.0 { a } else { rng.uniform(0.0, TAU) };
        let h = 0.35 + 2.0 * rng.next().powf(1.4);
        let vy = 0.7 + 1.3 * rng.next();
        let (vx, vz) = (ang.cos() * h, ang.sin() * h);
        let y = f64::from(c.g) + 1.2 + 2.5 * rng.next();
        // (most in the first half second, the last ones at a second and a half)
        let t = PL_HIT + 0.05 + 1.5 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

/// The payload. Calm; the object high in the sky drifting down in lazy loops; the dive; the strike: a flash, the column
/// boiling up, the shockwave's dust rushing out over the land and over the player, debris raining down; the column
/// standing over it all a long time.
/// The shockwave's jolt reaching the player at `t`, `fo` as hard (see payload_plan): as in the clips, a hard hit and
/// strong quick swings for over half a second (sharp aftershocks every other tick), then a shudder of smaller quick
/// jolts fading over the next one and a half, a long faint rumble under it all.
fn pl_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 0.8);
    p.shake(t + 0.05, 0.45 * fo, 3.5);
    for n in 0..6 {
        p.shake(t + 0.1 * (n + 1) as f32, (1.0 - 0.05 * n as f32) * fo, 0.14);
    }
    for n in 0..17 {
        let u = n as f32 / 17.0;
        p.shake(t + 0.7 + 0.1 * n as f32, (0.62 * (1.0 - u).powf(1.2) + 0.08) * fo, 0.1);
    }
}

/// How much of the blast is heard through a long stretch of air (`blast_far`), `dist` blocks off: none within 500,
/// all of it past 1,500 (a smooth step between).
fn pl_far(dist: f64) -> f32 {
    let u = ((dist - 500.0) / 1000.0).clamp(0.0, 1.0);
    (u * u * (3.0 - 2.0 * u)) as f32
}

pub(super) fn payload_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3], blast_alt: bool) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let geo = PlGeo::new(shader_seed, rel);
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let (late, dist) = sound_from([cx, gy, cz], me);
    let fo = falloff(dist).max(0.3);

    // the pass's table, on the tick after it fires
    {
        let s = shader_seed;
        p.later(0.05, move |q| {
            q.ev.push((0.05, Act::Table(pl_table(s, rel))));
            q.ev.push((0.05, Act::Words { index: PL_DB as u32, words: pl_debris_words(s as u32) }));
        });
    }
    // (and the land's shape round it, asked of the world as it starts, the heightfield on a later tick)
    {
        let reach = pl_hf_reach(rel[0].hypot(rel[2]));
        let columns = Rc::new(pl_hf_columns(bx, bz, reach));
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        p.later(0.4, move |q| pl_hf_step(q, tag, columns, reach, rel, by + 1, 0.4));
    }

    // ---- calm, then something up there ------------------------------------------------------------------------------
    p.at(1.2, bar("ORBITAL TRACKING: OBJECT DESCENDING", "gray"));
    // (its whine and rumble, heard faintly from up there: late by how far it is)
    let (dl, _) = sound_from(add([cx, gy, cz], geo.pos(f64::from(PL_SEEN)), 1.0), me);
    p.csound(PL_SEEN - 0.3 + dl.min(1.6), "drift", 10.0, 1.0);
    p.at(7.5, bar("ORBITAL TRACKING: OBJECT DESCENDING", "gray"));
    // ---- the dive: its roar and whistle as it comes down, cut off as it strikes ----------------------------------
    p.at(PL_TURN + 0.2, bar("PAYLOAD INBOUND", "red"));
    // (its roar and whistle are cut off dead PL_DIVE_SND in: started that long before it strikes, as its fast final
    // descent starts, so the cut falls on the strike)
    p.csound(PL_HIT - PL_DIVE_SND, "dive", 10.0, 1.0);
    // ---- the land's answer through the ground, long before the air's: a deep thump and a rumble, felt more than heard,
    // fainter further off, and a faint early jolt with it (never on the blast's own tick). Close in, the blast comes
    // hard on its heels and drowns it: it is made quieter there, so the two together stay under full scale.
    let tg = PL_HIT + (dist / PL_GROUND_V) as f32;
    let gap = PL_HIT + late - tg;
    // (the third clip's near strike, some 230 blocks off, has the thump about as heavy as the first clip's at 450: only
    // right under it, where the blast lands on top of it, is it let down much)
    let gv = ((1.0 / (1.0 + dist / 900.0)).clamp(0.3, 1.0) * (f64::from(gap - 0.05) / 0.9).clamp(0.25, 1.0).powf(1.5)) as f32;
    p.csound(tg - 0.02, if blast_alt { "ground_alt" } else { "ground" }, 10.0 * gv, 1.0);
    if gap > 0.08 {
        p.shake(tg, 0.45 * (1.6 / (1.0 + dist / 400.0)).clamp(0.35, 1.0) as f32, 0.35);
    }
    // ---- the strike: a near-silent breath, the blast reaching the player late by how far it is, with the dust's rush
    // and the jolt, the debris coming down round them, the long rolling tail after -----------------------------------
    let arrive = PL_HIT + late;
    // (from far off the air has taken its top: the blast cross-faded into the same one darkened, 500 to 1,500 blocks)
    let far = pl_far(dist);
    let (bn, bf) = if blast_alt { ("blast_alt", "blast_alt_far") } else { ("blast", "blast_far") };
    if far < 1.0 {
        p.csound(arrive - 0.02, bn, 10.0 * (1.0 - far), 1.0);
    }
    if far > 0.0 {
        p.csound(arrive - 0.02, bf, 10.0 * far, 1.0);
    }
    p.csound(arrive - 0.15, "rush", 10.0, 1.0);
    p.csound(arrive + 2.4, "tail", 10.0, 1.0);
    // (the jolt as the front hits, as in the clip: a hard hit, then sharp aftershocks a tick apart every other tick for
    // half a second, a rumbling shudder of small quick jolts fading over the next two seconds, a long faint rumble under
    // it all. The game's shake is smooth noise: the quick jolts, each fading within a tick or two, make it judder.
    // Each on a tick of its own, as the jolts of one tick are sent as one, lasting as long as the longest.)
    // (felt far out: as hard as in the clip a few hundred blocks off, still there over a kilometre away)
    pl_jolt(&mut p, arrive, (1.6 / (1.0 + dist / 400.0)).clamp(0.35, 1.0) as f32);
    let mut ts = arrive + 2.6;
    while ts < arrive + 7.0 {
        let s = p.rng.uniform(0.04, 0.1) as f32 * fo;
        let d = p.rng.uniform(0.3, 0.6) as f32;
        p.shake(ts, s, d);
        ts += p.rng.uniform(0.5, 1.2) as f32;
    }
    // (debris thudding and pattering down round the player if they are near enough to be under it)
    if dist < 420.0 {
        let near = (1.0 - dist / 420.0) as f32;
        p.csound(PL_HIT + 3.2 + (dist / 160.0) as f32, "debris", 10.0 * (0.45 + 0.55 * near), 1.0);
        let mut td = PL_HIT + 3.4 + (dist / 160.0) as f32;
        for _ in 0..(6.0 + 10.0 * near) as usize {
            let n = (10.0 + 50.0 * near * p.rng.next() as f32) as i32;
            p.at(td, format!(r#"execute at @s run particle minecraft:block{{block_state:"minecraft:coarse_dirt"}} ~ ~14 ~ 18 6 18 0.6 {n} force @s"#));
            p.at(td + 0.1, format!(r#"execute at @s run particle minecraft:falling_dust{{block_state:"minecraft:sand"}} ~ ~10 ~ 16 6 16 0 {} force @s"#, n * 2));
            td += p.rng.uniform(0.25, 0.9) as f32;
        }
    }
    p.at(PL_HIT + 1.5, bar("PAYLOAD DETONATED", "gold"));
    for t in [PL_HIT + 0.1, PL_HIT + 1.5, PL_HIT + 4.0] {
        p.at(t, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{PL_KILL}]"));
    }
    // (real smoke and grit round the crater, for anyone close)
    p.at(PL_HIT + 0.1, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 6 3 6 0 6 force", gy + 2.0));
    p.at(PL_HIT + 0.2, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {cx:.1} {:.1} {cz:.1} 14 6 14 0.8 400 force"#, gy + 4.0));
    for i in 0..8 {
        let t = PL_HIT + 1.0 + i as f32 * 1.4;
        p.at(t, format!("particle minecraft:campfire_signal_smoke {cx:.1} {:.1} {cz:.1} 10 2 10 0.02 30 force", gy + 1.0));
    }

    if terrain {
        let land: Shared = Rc::new(RefCell::new(Land { cols: vec![Column::default(); (PL_GW * PL_GW) as usize], missing: Vec::new() }));
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, PL_READ as f64 + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // the land read as it starts (a few queries, each a stage of its own), taken in a stage a part
        let tags: Rc<Vec<u32>> = Rc::new((0..PL_PARTS).map(|_| crate::columns::new_tag()).collect());
        for part in 0..PL_PARTS {
            let tags = tags.clone();
            let t = 0.1 + 0.05 * part as f32;
            p.later(t, move |q| {
                let columns = read_columns(q.bx, q.bz, part);
                q.ev.push((t, Act::Read { tag: tags[part as usize], columns, below: PL_BELOW, above: PL_ABOVE }));
            });
        }
        {
            let land = land.clone();
            p.later(0.5, move |q| pl_land_step(q, land, tags, 0, 0.5, 0));
        }
        // the blast's edits worked out well ahead, a band of rows a stage (a stage's work kept well under a tick's fuel),
        // and what it leaves hanging round them, each on a stage of its own
        let shape = Shape { cx, cz, ph: [TAU * mh(1, geo.seed, 0xc1), TAU * mh(2, geo.seed, 0xc1), TAU * mh(3, geo.seed, 0xc1)], seed: geo.seed };
        let bands = PL_BANDS;
        let rows = (PL_GW + bands - 1) / bands;
        for j in 0..bands {
            let (k0, k1) = (j * rows, ((j + 1) * rows).min(PL_GW));
            let t = PL_HIT - 7.0 + 0.1 * j as f32;
            let l1 = land.clone();
            p.later(t, move |q| pl_blast_rows(q, &l1.borrow(), &shape, k0, k1));
            let l2 = land.clone();
            p.later(t + 0.05, move |q| pl_tidy_rows(q, &l2.borrow(), &shape, k0, k1));
        }
        // the trees felled, a band of rows a stage, then the rubble
        let used: Used = Default::default();
        let fb = 11;
        let rows = (PL_GW + fb - 1) / fb;
        for j in 0..fb {
            let (land, used) = (land.clone(), used.clone());
            p.later(PL_HIT - 3.0 + 0.1 * j as f32, move |q| pl_felled(q, &land.borrow(), &shape, &used, j * rows, ((j + 1) * rows).min(PL_GW)));
        }
        {
            let land = land.clone();
            p.later(PL_HIT - 0.7, move |q| pl_thrown(q, &land.borrow(), &shape));
        }
        p.later(PL_HIT - 0.9, move |q| pl_rubble(q, &land.borrow(), &shape, &used));
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path PL_ME=x,y,z cargo test --release pl_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the target's ground at the preview's (0.5 65 0.5), the
    /// player at PL_ME.
    #[test]
    #[ignore]
    fn pl_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let mut w = super::pl_table(seed, rel);
        // (the land's shape, as tools/preview draws it: PL_HILLS=H its hills (main.rs's hills_h), flat otherwise)
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let reach = super::pl_hf_reach(rel[0].hypot(rel[2]));
        let heights: Vec<Option<f64>> = super::pl_hf_columns(0, 0, reach)
            .iter()
            .map(|&(x, z)| {
                let (x, z) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
                Some(hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin()))
            })
            .collect();
        let hf = super::pl_hf_words(&heights, reach, rel);
        w.resize(super::PL_HF + hf.len(), 0);
        w[super::PL_HF..].copy_from_slice(&hf);
        let db = super::pl_debris_words(seed as u32);
        w.resize(super::PL_DB + db.len(), 0);
        w[super::PL_DB..].copy_from_slice(&db);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    #[test]
    fn payload_alternative_blast_swaps_its_two_sounds() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let sounds = |option: usize| -> Vec<String> {
            plan(&crate::lasers::PAYLOAD, &target, false, "minecraft:overworld", 37.0, [10.5, 66.0, 450.0], option)
                .into_iter()
                .filter_map(|(_, a)| if let Act::Sound { event, .. } = a { Some(event) } else { None })
                .collect()
        };
        let (main, alt) = (sounds(0), sounds(1));
        let has = |v: &[String], s: &str| v.iter().any(|e| e.ends_with(s));
        assert!(has(&main, "payload.blast") && has(&main, "payload.ground"));
        assert!(!has(&main, "payload.blast_alt") && !has(&main, "payload.ground_alt"));
        assert!(has(&alt, "payload.blast_alt") && has(&alt, "payload.ground_alt"));
        assert!(!has(&alt, "payload.blast") && !has(&alt, "payload.ground"));
        assert_eq!(main.len(), alt.len());
    }

    #[test]
    fn payload_blast_from_far_off_is_heard_through_the_air() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let blasts = |z: f64, option: usize| -> Vec<(String, f32)> {
            plan(&crate::lasers::PAYLOAD, &target, false, "minecraft:overworld", 37.0, [10.5, 66.0, z], option)
                .into_iter()
                .filter_map(|(_, a)| if let Act::Sound { event, volume, .. } = a { Some((event, volume)) } else { None })
                .filter(|(e, _)| e.contains("payload.blast"))
                .collect()
        };
        let names = |v: &[(String, f32)]| v.iter().map(|(e, _)| e.rsplit('.').next().unwrap().to_string()).collect::<Vec<_>>();
        assert_eq!(names(&blasts(300.0, 0)), ["blast"]);
        assert_eq!(names(&blasts(2500.0, 0)), ["blast_far"]);
        assert_eq!(names(&blasts(2500.0, 1)), ["blast_alt_far"]);
        let mid = blasts(1000.0, 1);
        assert_eq!(names(&mid), ["blast_alt", "blast_alt_far"]);
        assert!((mid[0].1 + mid[1].1 - 1.0).abs() < 1e-4, "{mid:?}");
    }

    #[test]
    fn payload_sheds_its_pieces_before_it_strikes_and_they_fall_away_behind_it() {
        let g = PlGeo::new(37.0, [0.0, 5.0, 300.0]);
        let f = pl_fragments(&g);
        assert_eq!(f.len(), PL_CHUNKS + PL_SPARKS);
        for p in &f {
            let (t0, life) = (p[0], p[1]);
            assert!(t0 > f64::from(PL_TURN) - 4.0 && t0 < f64::from(PL_HIT) - 0.1, "{p:?}");
            assert!(life > 0.2 && life < 4.0 && p[2] > 0.0, "{p:?}");
            // (it lets go where the object is)
            let at = g.pos(t0);
            assert!(len(add(at, [p[5], p[6], p[7]], -1.0)) < 1e-6);
            // (and falls behind it: slower than the object along its path)
            let v = [p[8], p[9], p[10]];
            let d = add(g.pos(t0 + 0.02), g.pos(t0 - 0.02), -1.0);
            let along = (v[0] * d[0] + v[1] * d[1] + v[2] * d[2]) / len(d);
            assert!(along < len(d) / 0.04, "{p:?}");
        }
        // (the table's words for them, where the pass reads them)
        let w = pl_table(37.0, [0.0, 5.0, 300.0]);
        assert_eq!(f32::from_bits(w[7]) as usize, PL_CHUNKS + PL_SPARKS);
        assert!(w.len() <= PL_HF && PL_PF + PL_PUFFS * PL_PW <= PL_FR && PL_HF + 8 + PL_HN * PL_HN <= PL_DB);
        assert_eq!(f32::from_bits(w[PL_FR]), f[0][0] as f32);
    }

    #[test]
    fn payload_path_arcs_down_from_high_up_onto_the_target() {
        for seed in [3.0, 37.0, 512.0, 991.0] {
            let me = [0.0, 5.0, 300.0];
            let g = PlGeo::new(seed, me);
            let p0 = g.pos(f64::from(PL_SEEN));
            assert!(p0[1] > 1000.0, "{p0:?}");
            let end = g.pos(f64::from(PL_HIT));
            assert!(len(end) < 1e-6, "{end:?}");
            // (seen from the player it shows ahead of them, high and off to one side, not behind them)
            let v = add(p0, me, -1.0);
            let az = (-v[0] * me[0] - v[2] * me[2]) / (v[0].hypot(v[2]) * me[0].hypot(me[2]));
            assert!(az > 0.5 && az < 0.9, "{az}");
            let el = v[1].atan2(v[0].hypot(v[2])).to_degrees();
            assert!(el > 25.0 && el < 55.0, "{el}");
            // (it only ever comes down, steeper and faster as it goes, smoothly)
            let mut last = p0;
            let mut slope = 0.0;
            let mut t = f64::from(PL_SEEN);
            while t < f64::from(PL_HIT) {
                t += 0.02;
                let q = g.pos(t.min(f64::from(PL_HIT)));
                let d = add(q, last, -1.0);
                assert!(q[1] > -0.01 && d[1] <= 0.0, "{t} {q:?}");
                assert!(len(d) < 16.0, "{t}");
                let sl = -d[1] / d[0].hypot(d[2]).max(1e-9);
                assert!(sl >= slope - 1e-9, "{t} {sl} {slope}");
                slope = sl;
                last = q;
            }
            assert!(slope > 1.4, "{slope}");
            // (a slow crawl over the sky for seconds, a fast descent at the end)
            let sp = |t: f64| len(add(g.pos(t), g.pos(t - 0.05), -1.0)) / 0.05;
            assert!(sp(f64::from(PL_SEEN) + 3.0) < 110.0, "{}", sp(f64::from(PL_SEEN) + 3.0));
            assert!(sp(f64::from(PL_HIT)) > 500.0, "{}", sp(f64::from(PL_HIT)));
            assert!(g.pos(f64::from(PL_TURN))[1] > 600.0, "{:?}", g.pos(f64::from(PL_TURN)));
        }
    }

    #[test]
    fn payload_heightfield_follows_the_land_and_shelters_behind_a_ridge() {
        let me = [0.0, 0.0, 300.0];
        let reach = pl_hf_reach(300.0);
        let cols = pl_hf_columns(0, 0, reach);
        assert_eq!(cols.len(), PL_HN * PL_HN);
        // (a ridge 30 high across the way to the player at z 150, a trunk standing in one cell, the far corner not loaded)
        let heights: Vec<Option<f64>> = cols
            .iter()
            .enumerate()
            .map(|(c, &(x, z))| {
                if c == 10 * PL_HN + 10 {
                    return Some(25.0);
                }
                if x > 300 && z > 300 {
                    return None;
                }
                Some(30.0 * (-(f64::from(z) - 150.0).powi(2) / 400.0).exp() + 0.0 * f64::from(x))
            })
            .collect();
        let w = pl_hf_words(&heights, reach, me);
        assert_eq!(w.len(), 8 + PL_HN * PL_HN);
        assert_eq!(f32::from_bits(w[0]), PL_HN as f32);
        let cell = |x: f64, z: f64| {
            let step = 2.0 * reach / (PL_HN - 1) as f64;
            let (i, k) = (((x + reach) / step).round() as usize, ((z + reach) / step).round() as usize);
            let v = w[8 + k * PL_HN + i];
            (f64::from(v & 0xffff) / 8.0 - 512.0, f64::from((v >> 16) & 0xff) / 255.0)
        };
        let step = 2.0 * reach / (PL_HN - 1) as f64;
        assert!(cell(-reach + 10.0 * step, -reach + 10.0 * step).0.abs() < 1.0, "the trunk stays");
        assert!((cell(0.0, 150.0).0 - 30.0).abs() < 4.0);
        assert!(cell(0.0, 200.0).1 > 0.5, "{:?}", cell(0.0, 200.0));
        assert!(cell(0.0, -200.0).1 < 0.05 && cell(0.0, 60.0).1 < 0.05);
        // (the land not loaded: the mean of what was, a little over the flat with the ridge in it)
        assert!(cell(reach, reach).0 > 0.0 && cell(reach, reach).0 < 5.0, "{:?}", cell(reach, reach));
    }

    /// A forest on rolling land (its ground about 64): oaks now and then, a pond south-west of the target.
    fn ground_h(x: i32, z: i32) -> i32 {
        (64.0 + 3.0 * (f64::from(x) * 0.05).sin() * (f64::from(z) * 0.04).cos()).round() as i32
    }
    fn tree(x: i32, z: i32) -> bool {
        mh((x.wrapping_mul(73) ^ z.wrapping_mul(179)) as u32, 5, 0x99) > 0.985
    }
    fn pond(x: i32, z: i32) -> bool {
        ((x + 40) * (x + 40) + (z - 30) * (z - 30)) < 49
    }
    thread_local! {
        /// The land the tests' world answers with: 0 the forest with its pond; 1 the forest over an aquifer (water
        /// in the ground 8 to 14 under it); 2 by the sea (west of x -5, its surface at 62); 3 a river through the
        /// crater (12 wide at z 15, its surface at 62).
        static LAND: std::cell::Cell<u8> = const { std::cell::Cell::new(0) };
    }
    fn water_at(x: i32, z: i32) -> Option<(i32, i32)> {
        match LAND.with(|l| l.get()) {
            0 => pond(x, z).then(|| (ground_h(x, z) - 3, ground_h(x, z))),
            2 => (x < -5).then_some((54, 62)),
            3 => ((z - 15).abs() < 6).then_some((57, 62)),
            _ => None,
        }
    }
    fn column(x: i32, z: i32) -> Option<(i32, Vec<&'static str>)> {
        let land = LAND.with(|l| l.get());
        let wet = water_at(x, z);
        let g = if land == 0 { ground_h(x, z) } else { wet.map_or(64, |w| w.0) };
        let t = wet.is_none() && tree(x, z);
        let block = |y: i32| -> &'static str {
            if let Some((bed, top)) = wet {
                return if y < bed { "minecraft:dirt" } else if y <= top { "minecraft:water" } else { "minecraft:air" };
            }
            if land == 1 && y < g - 8 && y >= g - 14 {
                return "minecraft:water";
            }
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
        let top = if let Some((_, w)) = wet { w } else if t { g + 9 } else { g + 2 };
        let (below, above) = (PL_BELOW as i32, PL_ABOVE as i32);
        Some((top, (top - below..top + above).map(block).collect()))
    }

    #[test]
    fn payload_crater_digs_water_like_any_block() {
        for land in [2, 3] {
            LAND.with(|l| l.set(land));
            let fills: Vec<String> = played(true).iter().flat_map(|(_, b)| b.as_fills()).collect();
            assert!(!fills.iter().any(|f| f.contains("minecraft:water")), "{land}");
        }
        LAND.with(|l| l.set(0));
    }
    #[test]
    fn payload_land_changes_sweep_out_from_the_middle() {
        LAND.with(|l| l.set(0));
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(&crate::lasers::PAYLOAD, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 300.0], 0);
        let p = crate::strike::sim::play(ev, 30.0, &|x, z, _, _| column(x, z));
        assert!(!p.edits.is_empty());
        for (t, due, b) in &p.edits {
            assert!(t - due < 0.2, "an edit {:.2} s late", t - due);
            for u in &b.runs {
                let r = (f64::from(u.x) + 0.5 - 10.5).hypot(f64::from(u.z) + 0.5 + 2.5);
                assert!(*t >= pl_wave(r - 4.0) - 0.06, "at {r:.0} at {t:.2}, before the blast ({:.2})", pl_wave(r));
            }
        }
    }

    fn played(terrain: bool) -> Vec<(f32, Blocks)> {
        played_all(terrain).0
    }
    fn played_all(terrain: bool) -> (Vec<(f32, Blocks)>, Vec<(f32, String)>) {
        crate::columns::clear();
        let mut cmds = Vec::new();
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::PAYLOAD, &target, terrain, "minecraft:overworld", 37.0, [10.5, 66.0, 300.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Vec::new();
        let mut table = false;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &column),
                Act::Blocks(b) => out.push((t, *b)),
                Act::Cmd(c) => cmds.push((t, c)),
                Act::Table(w) => {
                    assert_eq!(w.len(), PL_FR + (PL_CHUNKS + PL_SPARKS) * PL_FW);
                    table = true;
                }
                Act::Later(job) | Act::Soon(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        assert!(table);
        (out, cmds)
    }

    #[test]
    fn payload_digs_a_crater_fells_the_trees_and_floods_nothing() {
        let blocks = played(true);
        assert!(!blocks.is_empty());
        let fills: Vec<String> = blocks.iter().flat_map(|(_, b)| b.as_fills()).collect();
        // nothing that burns, flows or spreads is placed
        for f in &fills {
            for bad in ["lava ", "water ", "fire", "magma", "sand ", "concrete_powder"] {
                assert!(!f.contains(&format!(" minecraft:{bad}")) || f.contains(" replace "), "{f}");
            }
        }
        // the middle dug about PL_CRATER_D deep
        let mid = fills.iter().find(|f| f.starts_with("fill 10 ") && f.contains(" -3 10 ") && f.contains("minecraft:air")).expect("the middle dug");
        let y0: i32 = mid.split_whitespace().nth(2).unwrap().parse().unwrap();
        assert!((ground_h(10, -3) - y0 + 1 - PL_CRATER_D as i32).abs() <= 1, "{mid}");
        // trees felled: logs lying along x or z
        let lying = fills.iter().filter(|f| f.contains("_log[axis=")).count();
        assert!(lying > 20, "{lying}");
        // past the flattened land: crowns stripped, and some trees knocked flat there (logs lying beyond PL_FLAT)
        let stripped = fills.iter().filter(|f| f.ends_with("minecraft:air replace minecraft:oak_leaves strict")).count();
        assert!(stripped > 10, "{stripped}");
        let far_logs = fills
            .iter()
            .filter(|f| f.contains("_log[axis="))
            .filter(|f| {
                let w: Vec<f64> = f.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap_or(0.0)).collect();
                (w[0] - 10.0).hypot(w[2] + 3.0) > PL_FLAT * 1.15
            })
            .count();
        assert!(far_logs > 3, "{far_logs}");
        // the pond left alone, and nothing dug next to it (what stood on its banks may go)
        for f in &fills {
            let w: Vec<i32> = f.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap_or(0)).collect();
            if f.contains("minecraft:air") && w.len() == 3 {
                let (x, y, z) = (w[0], w[1], w[2]);
                let near = pond(x, z) || pond(x + 1, z) || pond(x - 1, z) || pond(x, z + 1) || pond(x, z - 1);
                assert!(!near || y > ground_h(x, z), "{f}");
            }
        }
        // the crown of a felled tree never left in the air: every leaves block at a tree's column cleared
        for x in -100..120 {
            for z in -100..100 {
                if !tree(x, z) {
                    continue;
                }
                let r = (f64::from(x) - 10.0).hypot(f64::from(z) + 3.0);
                if r < 70.0 && !pond(x, z) {
                    let g = ground_h(x, z);
                    assert!(fills.iter().any(|f| f.starts_with(&format!("fill {x} ")) && f.contains(&format!(" {z} {x} ")) && f.contains("minecraft:air") && f.contains(&format!(" {} {z} ", g + 8))), "tree at {x} {z} left standing");
                }
            }
        }
    }

    #[test]
    fn payload_leaves_the_land_alone_with_the_terrain_off() {
        let (blocks, cmds) = played_all(false);
        assert!(blocks.is_empty());
        assert!(!cmds.iter().any(|(_, c)| c.contains("falling_block {")), "no blocks thrown with the terrain off");
    }

    #[test]
    fn payload_throws_real_blocks_out_of_the_crater() {
        let (_, cmds) = played_all(true);
        let thrown: Vec<&(f32, String)> = cmds.iter().filter(|(_, c)| c.starts_with("summon minecraft:falling_block")).collect();
        // a fair number, over the second and a half after it strikes, a few a tick at most
        assert!(thrown.len() >= 60 && thrown.len() <= PL_THROWN, "{} thrown", thrown.len());
        let mut per_tick = std::collections::HashMap::new();
        for (t, c) in &thrown {
            assert!(*t > PL_HIT && *t < PL_HIT + 1.6, "{t}");
            *per_tick.entry((t * 20.0) as i32).or_insert(0) += 1;
            // never dropping an item; out of the crater (the target at 10 -3), outward and up
            assert!(c.contains("DropItem:0b"), "{c}");
            let w: Vec<f64> = c.split_whitespace().skip(2).take(3).map(|v| v.parse().unwrap()).collect();
            assert!((w[0] - 10.5).hypot(w[2] + 2.5) < PL_CRATER_R, "{c}");
            let m = c.split("Motion:[").nth(1).unwrap();
            let v: Vec<f64> = m.trim_end_matches("]}").split(',').map(|v| v.trim_end_matches('d').parse().unwrap()).collect();
            assert!(v[1] > 0.5, "{c}");
            assert!((w[0] - 10.5) * v[0] + (w[2] + 2.5) * v[2] >= -1.0e-6, "{c}");
            // of the ground that was there: no grass or leaves of a plant, nothing that flows
            assert!(!c.contains("water") && !c.contains("lava") && !c.contains("sand\""), "{c}");
        }
        assert!(per_tick.values().all(|&k| k <= 12), "{per_tick:?}");
        // some land as blocks, some break up where they land
        let breaks = thrown.iter().filter(|(_, c)| c.contains("CancelDrop:1b")).count();
        assert!(breaks > 10 && breaks < thrown.len() - 10, "{breaks}");
        // and they are not killed in the air as the land round it is cleared of what lives there
        assert!(cmds.iter().filter(|(_, c)| c.contains("kill @e")).all(|(_, c)| c.contains("type=!minecraft:falling_block")));
    }
}

#[cfg(test)]
mod stage_cost {
    use super::*;
    use crate::strike::plan;
    /// `cargo test --release pl_stage_cost -- --ignored --nocapture`: the heaviest stages (native time; see the fuel
    /// harness for the game's measure).
    #[test]
    #[ignore]
    fn pl_stage_cost() {
        let target = Target { block: [-1041, 64, 860], point: [-1040.5, 65.0, 860.5] };
        let t0 = std::time::Instant::now();
        let mut ev = plan(&crate::lasers::PAYLOAD, &target, true, "minecraft:overworld", 19.0, [-1040.5, 70.0, 1160.5], 0);
        println!("plan: {:.3} ms, {} acts", t0.elapsed().as_secs_f64() * 1000.0, ev.len());
        let mut out = Vec::new();
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| {
                    let g = 64 + ((x + z) % 3);
                    let tree = (x * 7 + z * 13) % 41 == 0;
                    let top = if tree { g + 9 } else { g + 1 };
                    let b = (top - below as i32..top + above as i32)
                        .map(|y| if y < g { "minecraft:dirt" } else if y == g { "minecraft:grass_block" } else if tree && y <= g + 6 { "minecraft:oak_log" } else if tree { "minecraft:oak_leaves" } else { "minecraft:air" })
                        .collect();
                    Some((top, b))
                }),
                Act::Later(job) | Act::Soon(job) => {
                    let s = std::time::Instant::now();
                    let more = job();
                    out.push((t, s.elapsed().as_secs_f64() * 1000.0, more.len()));
                    ev.extend(more);
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        out.sort_by(|a, b| b.1.total_cmp(&a.1));
        for b in out.iter().take(8) {
            println!("stage at {:6.2} s: {:.3} ms, {} acts", b.0, b.1, b.2);
        }
    }
}
