//! The nuke's plan: the Payload's big brother (strike/payload.rs, whose land reading, crater, felled trees, rubble and
//! thrown blocks this follows, scaled up). A dark bomb shows high in the sky over the target and falls, steeper and
//! faster, a thin pale trail behind it; it bursts NK_BURST blocks over the land: a blinding white flash, a fireball
//! swelling and rising into a mushroom cloud hundreds of blocks tall, its stem pulled up out of the land, the shockwave
//! racing out over it in a wall of dust, debris and real blocks thrown far round it.
//!
//! The timeline (strike seconds; the sounds arrive late by the distance, 343 blocks a second, as the Payload's):
//! 0 fired; NK_SEEN (2.0) the bomb shows ~900 up; `nuke.fall` from 1.5 to the burst; NK_HIT (11.0) the burst (the
//! flash is silent); `nuke.ground` as the ground carries the shock (five times the air's speed); `nuke.blast` (or
//! `nuke.blast_far` past ~300 blocks, cross-faded to 900) as the air does, `nuke.shockwave` with it as the front passes
//! the player, `nuke.rumble` 1.5 s after it (30 to 40 s), `nuke.debris` 3 s after it within 700 blocks; the strike ends
//! at 90 s (lasers.rs's length).
//!
//! What it leaves is real blocks: a crater about NK_CRATER_R * 2 (200) across and NK_CRATER_D (40) deep, its walls
//! stepped in terraces and scorched, glazed with greenish glass on its floor, its rim a broken ridge of rock and earth
//! turned over; the land flattened round it out to about NK_FLAT (230; the trees felled and lying pointing away from
//! it), past that out to NK_FLAT + NK_BAND (300) crowns stripped and many trees knocked flat, the grass charred out to
//! about NK_CHAR (290) in streaks, rubble strewn out to NK_RUBBLE (280), mobs and dropped items killed within NK_KILL
//! (300); past that, out to NK_FLASH (480), what faces the fireball scorched by its flash and what is hidden from it
//! left as it was (nk_flash_rows). Nothing that flows; nothing dug next to water or lava; the odd fire far out.
//!
//! shaders/nuke.wgsl draws the bomb, its trail, the flash, the fireball, the mushroom cloud, the shockwave, the dust and
//! the debris from the table `nk_table` hands it (render.set-data). Keep the NK_* here and there in step.
use super::{Act, Blocks, Col, Plan, Rng, Target, falloff, mh, pk_load_rows, sound_from, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The bomb shows high in the sky, falls faster from NK_TURN, and bursts at NK_HIT, NK_BURST blocks over the target's
/// ground.
pub(super) const NK_SEEN: f32 = 2.0;
pub(super) const NK_TURN: f32 = 8.0;
pub(super) const NK_HIT: f32 = 11.0;
pub(super) const NK_BURST: f64 = 45.0;
/// How fast the ground carries the strike's shock (blocks a second): five times the air's.
const NK_GROUND_V: f64 = 5.0 * 343.0;
/// The path's samples (the trail is drawn through them), from NK_SEEN to NK_HIT.
pub(super) const NK_N: usize = 128;
/// The cloud's billows.
pub(super) const NK_PUFFS: usize = 18;
/// The mushroom cap's height over the ground as its rise slows (the pass's own rise curve).
pub(super) const NK_HC: f64 = 430.0;
/// The table (render.set-data): words 0..16 the header (samples, first sample's time, their spacing, the wind's x and
/// z, the cloud's height, the billows' count, the shed pieces' count, the debris' count); from NK_P the path, three
/// words a sample (x, y, z from the target's ground); from NK_PF the billows, NK_PW words each; from NK_FR the shed
/// pieces (none for the nuke: the bomb sheds nothing).
pub(super) const NK_P: usize = 16;
pub(super) const NK_PF: usize = NK_P + 3 * NK_N;
pub(super) const NK_PW: usize = 8;
pub(super) const NK_FR: usize = 560;
pub(super) const NK_FW: usize = 12;
pub(super) const NK_CHUNKS: usize = 0;
pub(super) const NK_SPARKS: usize = 0;

/// The crater's mean radius and depth, how far its rim's heap reaches (in its radii), the land flattened and the trees
/// felled out to NK_FLAT, the grass charred out to NK_CHAR, the rubble strewn out to NK_RUBBLE.
const NK_CRATER_R: f64 = 100.0;
const NK_CRATER_D: f64 = 40.0;
const NK_RIM: f64 = 1.4;
const NK_FLAT: f64 = 230.0;
const NK_CHAR: f64 = 290.0;
const NK_RUBBLE: f64 = 280.0;
/// Past the flattened land, a band this wide where the blast only half did its work: crowns stripped of their leaves,
/// many trees knocked flat, leaves and branches strewn.
const NK_BAND: f64 = 70.0;
/// The land read: every column out to NK_READ, NK_BELOW under its top (a tall tree's top down to its ground).
const NK_READ: i32 = 300;
const NK_GW: i32 = 2 * NK_READ + 1;
const NK_BELOW: u32 = 36;
const NK_ABOVE: u32 = 1;
const NK_PARTS: i32 = 32;
/// The blast's edits worked out in this many bands of rows, a stage each.
const NK_BANDS: i32 = 90;
/// Mobs and dropped items within NK_KILL killed as it bursts.
const NK_KILL: i32 = 300;
/// Real blocks thrown out of the crater as it bursts (nk_thrown).
const NK_THROWN: usize = 160;

/// Where the bomb is and how it moves: everything worked out from the strike's seed and where the player stands. It
/// shows high over the far side of the target, off to one side as the player looks, and falls on one steep arc onto
/// the burst point, NK_BURST over the target's ground, slow on the sky at first, then faster and faster.
#[derive(Clone, Debug)]
pub(super) struct NkGeo {
    pub seed: u32,
    /// Which way it comes from (from the target, level), how far off it shows, and how high.
    dir: [f64; 3],
    dh: f64,
    y0: f64,
    /// The wind (blocks a second, x and z): the trail and the cloud drift with it.
    pub wind: (f64, f64),
}

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
fn len(a: [f64; 3]) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}

/// The arc's shape: at its start it already falls this much of its slope at the end (steep from the first).
const NK_GLIDE: f64 = 0.6;
/// How far along the arc it is, against the time from showing to bursting: this much of it a steady fall, the rest
/// coming faster and faster.
const NK_CRAWL: f64 = 0.3;
const NK_RUSH: f64 = 2.4;

impl NkGeo {
    /// `me`: the player from the target's ground point.
    pub fn new(seed: f32, me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |k: u32| mh(k, seed, 0x9b1);
        let d = me[0].hypot(me[2]);
        let u = if d > 1.0 { [me[0] / d, 0.0, me[2] / d] } else { [0.0, 0.0, 1.0] };
        // (from beyond the target and off to one side, 40 to 60 degrees round from straight beyond it)
        let side = if r(1) < 0.5 { -1.0 } else { 1.0 };
        let phi = (40.0 + 20.0 * r(2)).to_radians() * side;
        let (c, s) = (phi.cos(), phi.sin());
        let dir = [-u[0] * c + u[2] * s, 0.0, -u[2] * c - u[0] * s];
        let wa = TAU * r(9);
        let ws = 2.0 + 2.0 * r(10);
        NkGeo { seed, dir, dh: 260.0 + 90.0 * r(3), y0: 880.0 + 120.0 * r(4), wind: (wa.cos() * ws, wa.sin() * ws) }
    }
    /// How far along the arc it is at strike time `t`, 0 as it shows to 1 as it bursts.
    fn along(t: f64) -> f64 {
        let w = ((t - f64::from(NK_SEEN)) / f64::from(NK_HIT - NK_SEEN)).clamp(0.0, 1.0);
        NK_CRAWL * w + (1.0 - NK_CRAWL) * w.powf(NK_RUSH)
    }
    /// Where it is at strike time `t` (from the target's ground), from NK_SEEN to NK_HIT: at NK_HIT the burst point.
    pub fn pos(&self, t: f64) -> [f64; 3] {
        let u = Self::along(t);
        let y = NK_BURST + (self.y0 - NK_BURST) * (1.0 - (NK_GLIDE * u + (1.0 - NK_GLIDE) * u * u));
        add([0.0, y, 0.0], self.dir, self.dh * (1.0 - u))
    }
}

/// The column's billows: (launch after the strike, rise time, share of the column's height, radius, x and z off its
/// axis). The stem's low and narrow, then the body, then the head, the highest launched first.
pub(super) fn nk_puffs(seed: u32) -> Vec<[f64; 6]> {
    // (it bursts up fast, most of its height in a second, as it does in the clip, then swells and climbs slowly on:
    // the head first, the body and the narrower stem boiling up under it)
    (0..NK_PUFFS)
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

/// The pieces shed as it comes in through the air (see NK_FR). As in the third clip: a few glowing chunks breaking off
/// in the seconds before the dive, flung out to the side and falling away behind it, each burning a second or three
/// and trailing its own thin smoke; and in the last seconds a spray of small sparks off the fireball, gone in a moment.
pub(super) fn nk_fragments(g: &NkGeo) -> Vec<[f64; 11]> {
    let mut out = Vec::new();
    let vel = |t: f64| {
        let (a, b) = (g.pos(t - 0.02), g.pos(t + 0.02));
        [(b[0] - a[0]) / 0.04, (b[1] - a[1]) / 0.04, (b[2] - a[2]) / 0.04]
    };
    for i in 0..NK_CHUNKS + NK_SPARKS {
        let h = |k: u32| mh(i as u32, g.seed, 0x7a0 + k);
        let spark = i >= NK_CHUNKS;
        let hit = f64::from(NK_HIT);
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

/// What the pass reads (see NK_P): worked out on the tick after it fires.
pub(super) fn nk_table(seed: f32, me: [f64; 3]) -> Vec<u32> {
    let g = NkGeo::new(seed, me);
    let mut w = vec![0.0f32; NK_FR + (NK_CHUNKS + NK_SPARKS) * NK_FW];
    let dt = f64::from(NK_HIT - NK_SEEN) / (NK_N - 1) as f64;
    w[0] = NK_N as f32;
    w[1] = NK_SEEN;
    w[2] = dt as f32;
    w[3] = g.wind.0 as f32;
    w[4] = g.wind.1 as f32;
    w[5] = NK_HC as f32;
    w[6] = NK_PUFFS as f32;
    for i in 0..NK_N {
        let p = g.pos(f64::from(NK_SEEN) + dt * i as f64);
        for k in 0..3 {
            w[NK_P + 3 * i + k] = p[k] as f32;
        }
    }
    for (i, p) in nk_puffs(g.seed).iter().enumerate() {
        for k in 0..6 {
            w[NK_PF + NK_PW * i + k] = p[k] as f32;
        }
    }
    w[7] = (NK_CHUNKS + NK_SPARKS) as f32;
    w[8] = NK_DEBRIS as f32;
    for (i, f) in nk_fragments(&g).iter().enumerate() {
        for k in 0..11 {
            w[NK_FR + NK_FW * i + k] = f[k] as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

/// The debris the pass draws (chunks and specks of earth thrown out, falling back far round it): from NK_DB, NK_DW words
/// each, worked out once here rather than for every chunk at every pixel: its bearing (x and z), how far out it is torn
/// up, its speed out and up, when it is thrown (after the strike), its size, e^(k t0) (k its drag), its spin. Keep in
/// step with payload.wgsl's nk_chunk.
pub(super) const NK_DB: usize = 10496;
pub(super) const NK_DW: usize = 10;
pub(super) const NK_DEBRIS: usize = 160;
fn nk_debris_words(seed: u32) -> Vec<u32> {
    let mut w = vec![0.0f32; NK_DEBRIS * NK_DW];
    let v = f64::from(343.0f32);
    for i in 0..NK_DEBRIS {
        let h = |k: u32| mh(i as u32, seed, k);
        let ang = h(0x301) * TAU;
        let big = h(0x303);
        // (torn up all over the blast's middle, each as the blast reaches it, not all from one point: most thrown a
        // few hundred blocks, a third far, some of those coming down round the player)
        // (the nuke's: torn up over a far wider middle, thrown far harder)
        let r0 = 10.0 + 110.0 * h(0x306).sqrt();
        let far = h(0x307) < 0.4;
        let el = if far { 0.4 + 0.45 * h(0x302) } else { 0.3 + 0.9 * h(0x302) };
        let sp = (if far { 140.0 + 80.0 * h(0x304) } else { 50.0 + 80.0 * h(0x304).powf(0.7) }) * (1.0 - 0.25 * big);
        let t0 = r0 / v + 0.12 * h(0x305);
        let row = [ang.cos(), ang.sin(), r0, el.cos() * sp, el.sin() * sp, t0, 0.2 + 1.6 * big * big * big, (0.06 * t0).exp(), 3.0 + 6.0 * h(0x308), 0.0];
        for (k, x) in row.iter().enumerate() {
            w[NK_DW * i + k] = *x as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

// ---- the land's shape round it, for the pass: the dust follows it ----------------------------------------------
/// A coarse heightfield of the land round the target, for the pass (the dust and the shockwave hug it, climbing the
/// hills, filling the hollows, thinner in the lee of a ridge): NK_HN x NK_HN cells over a square NK_HF's second word
/// across each way from the target. From NK_HF: the cells a side, that half-width, the lowest and highest ground (from
/// the target's), then from NK_HF + 8 a word a cell: its height in the low 16 bits (an eighth of a block, from 512 under
/// the target's ground), how sheltered it is from the blast by the land between in the next 8 (0 to 255).
pub(super) const NK_HF: usize = 1024;
pub(super) const NK_HN: usize = 96;
/// How far the heightfield reaches round the target, for a player `dme` off.
fn nk_hf_reach(dme: f64) -> f64 {
    (dme * 1.25 + 250.0).clamp(450.0, 1600.0)
}
/// The columns the heightfield is read from (row by row, z then x).
fn nk_hf_columns(bx: i32, bz: i32, reach: f64) -> Vec<(i32, i32)> {
    let n = NK_HN as i32;
    let step = 2.0 * reach / f64::from(n - 1);
    let at = |i: i32| (-reach + step * f64::from(i)).round() as i32;
    (0..n).flat_map(|k| (0..n).map(move |i| (bx + at(i), bz + at(k)))).collect()
}
/// The heightfield's ground (from the target's), from what the world gave (the first air over each column; none where
/// the land was not loaded, the mean of what was there: not the player's height, who may be up a tower or flying), a
/// trunk or a pillar caught in a cell put down to the ground round it.
fn nk_hf_ground(heights: &[Option<f64>], reach: f64, _me: [f64; 3]) -> Vec<f64> {
    let _ = reach;
    let n = NK_HN;
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
fn nk_hf_shelter(h: &[f64], reach: f64, k0: usize, k1: usize) -> Vec<f64> {
    let n = NK_HN;
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
/// The heightfield's words (from NK_HF).
fn nk_hf_pack(h: &[f64], shelter: &[f64], reach: f64) -> Vec<u32> {
    let (lo, hi) = h.iter().fold((f64::MAX, f64::MIN), |(a, b), &x| (a.min(x), b.max(x)));
    let mut w = vec![(NK_HN as f32).to_bits(), (reach as f32).to_bits(), (lo as f32).to_bits(), (hi as f32).to_bits(), 0, 0, 0, 0];
    let q = |x: f64| ((x + 512.0) * 8.0).round().clamp(0.0, 65535.0) as u32;
    let b = |x: f64| (x * 255.0).round().clamp(0.0, 255.0) as u32;
    w.extend(h.iter().zip(shelter).map(|(&g, &s)| q(g) | b(s) << 16));
    w
}
/// All of it at once (the tests, tools/preview).
#[cfg(test)]
fn nk_hf_words(heights: &[Option<f64>], reach: f64, me: [f64; 3]) -> Vec<u32> {
    let h = nk_hf_ground(heights, reach, me);
    let s = nk_hf_shelter(&h, reach, 0, NK_HN);
    nk_hf_pack(&h, &s, reach)
}
/// The heightfield, once the world has answered (asking again a little later until it has, while there is time): its
/// ground on one stage, its shelter on three more (each well under a tick's fuel), then sent.
fn nk_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, me: [f64; 3], gy: i32, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < NK_HIT {
            q.later(at_t + 0.2, move |q| nk_hf_step(q, tag, columns, reach, me, gy, at_t + 0.2));
        }
        return;
    }
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    let h = Rc::new(nk_hf_ground(&heights, reach, me));
    let parts = 3;
    let shelter: Rc<RefCell<Vec<f64>>> = Default::default();
    for j in 0..parts {
        let (h, shelter) = (h.clone(), shelter.clone());
        let t = at_t + 0.05 * (j + 1) as f32;
        q.later(t, move |q| {
            let (k0, k1) = (j * NK_HN / parts, (j + 1) * NK_HN / parts);
            shelter.borrow_mut().extend(nk_hf_shelter(&h, reach, k0, k1));
            if j + 1 == parts {
                q.ev.push((t, Act::Words { index: NK_HF as u32, words: nk_hf_pack(&h, &shelter.borrow(), reach) }));
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
    /// Every part taken in (the stages that use it wait for it).
    done: bool,
}
type Shared = Rc<RefCell<Land>>;

fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    let (i, k) = (x - bx + NK_READ, z - bz + NK_READ);
    if i < 0 || k < 0 || i >= NK_GW || k >= NK_GW {
        return None;
    }
    land.cols.get((k * NK_GW + i) as usize).filter(|c| c.known)
}

/// The columns read in part `part` (rows of the square, within NK_READ of the target).
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let rows = (NK_GW + NK_PARTS - 1) / NK_PARTS;
    let mut out = Vec::new();
    for k in part * rows..((part + 1) * rows).min(NK_GW) {
        let dz = k - NK_READ;
        for dx in -NK_READ..=NK_READ {
            if dx * dx + dz * dz <= NK_READ * NK_READ {
                out.push((bx + dx, bz + dz));
            }
        }
    }
    out
}

/// One answer taken in: each column's ground, what stands on it and over it.
fn take_in(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32) {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
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
                    c.fluid = true;
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
        let (ii, kk) = (x - bx + NK_READ, z - bz + NK_READ);
        if (0..NK_GW).contains(&ii) && (0..NK_GW).contains(&kk) {
            land.cols[(kk * NK_GW + ii) as usize] = c;
        }
    }
}

/// The land's parts taken in a stage each, as they are answered (and the columns not loaded yet asked again, once).
fn nk_land_step(q: &mut Plan, land: Shared, tags: Rc<Vec<u32>>, part: usize, at_t: f32, retry: u32) {
    if part >= tags.len() {
        land.borrow_mut().done = true;
        let missing = std::mem::take(&mut land.borrow_mut().missing);
        if !missing.is_empty() && retry < 2 && at_t < NK_HIT - 4.0 {
            let tag = crate::columns::new_tag();
            let t = at_t + 0.8;
            q.later(t, move |q| {
                q.ev.push((t, Act::Read { tag, columns: missing, below: NK_BELOW, above: NK_ABOVE }));
                q.later(t + 0.15, move |q| nk_land_step(q, land, Rc::new(vec![tag]), 0, t + 0.15, retry + 1));
            });
        }
        return;
    }
    let Some(a) = crate::columns::take(tags[part]) else {
        if at_t < NK_HIT - 4.0 {
            q.later(at_t + 0.1, move |q| nk_land_step(q, land, tags, part, at_t + 0.1, retry));
        }
        return;
    };
    take_in(&mut land.borrow_mut(), &a, q.bx, q.bz);
    // (and the parts after it already in, in the same stage: a stage a part would queue behind the blast's)
    let mut part = part + 1;
    let mut n = 1;
    while part < tags.len() && n < 8 {
        let Some(a) = crate::columns::get(tags[part]) else { break };
        let _ = crate::columns::take(tags[part]);
        take_in(&mut land.borrow_mut(), &a, q.bx, q.bz);
        part += 1;
        n += 1;
    }
    q.later(at_t + 0.05, move |q| nk_land_step(q, land, tags, part, at_t + 0.05, retry));
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
        let rc = NK_CRATER_R * self.wob(a) * (0.94 + 0.12 * vnoise(f64::from(x), f64::from(z), 7.0, self.seed ^ 0x31));
        (r, a, r / rc)
    }
    fn flat(&self, a: f64) -> f64 {
        NK_FLAT * (1.0 + 0.08 * (2.0 * a + self.ph[2]).sin() + 0.05 * (7.0 * a + self.ph[0]).sin())
    }
}
/// How deep the crater is at u (its radii out): a bowl; and how high its rim's heap stands past it.
fn bowl(u: f64) -> f64 {
    if u >= 1.0 {
        return 0.0;
    }
    // (a broad bowl, its walls stepped in terraces five deep where they slumped, the steps rounded off)
    let d = NK_CRATER_D * (1.0 - u * u).powf(0.7);
    let k = d / 5.0;
    let step = k.floor() + ((k.fract() - 0.55) / 0.45).clamp(0.0, 1.0).powi(2);
    // (the floor itself not stepped)
    let w = ((u - 0.35) / 0.2).clamp(0.0, 1.0);
    d * (1.0 - w) + step * 5.0 * w
}
/// The rim's heap past the edge (u in crater radii): the land thrown up and turned over, a broken ridge some ten high
/// just past the edge, falling away over the next forty percent, ragged (`n`, 0 to 1, breaks it up).
fn heap(u: f64, n: f64) -> f64 {
    if u < 1.0 || u > NK_RIM {
        return 0.0;
    }
    let ridge = 10.0 * (-(u - 1.07).powi(2) / 0.006).exp() + 3.0 * (1.0 - (u - 1.0) / (NK_RIM - 1.0));
    ridge * (0.35 + 0.95 * n)
}
/// The scorched ground of the crater's floor and walls: broad patches of one or another.
fn scorched(x: i32, y: i32, z: i32, u: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) + f64::from(y) * 0.37, f64::from(z), 4.5, seed ^ 0x51);
    let m = vnoise(f64::from(x), f64::from(z) - f64::from(y) * 0.5, 2.2, seed ^ 0x52);
    // (the middle of the floor fused by the fireball into a greenish glass, as at Trinity, in a few glazed patches)
    let g = vnoise(f64::from(x), f64::from(z), 3.0, seed ^ 0x53);
    if u < 0.42 && g > 0.66 {
        "minecraft:green_stained_glass"
    } else if u < 0.55 && n > 0.62 {
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
    // (the deep rock the crater dug up, turned over onto its rim in slabs)
    let m = vnoise(f64::from(x), f64::from(z) + f64::from(y) * 1.7, 5.0, seed ^ 0x62);
    if m > 0.78 {
        "minecraft:deepslate"
    } else if m < 0.14 {
        "minecraft:tuff"
    } else if n > 0.74 {
        "minecraft:cobblestone"
    } else if n > 0.6 {
        "minecraft:stone"
    } else if n < 0.2 {
        "minecraft:rooted_dirt"
    } else if n < 0.45 {
        "minecraft:coarse_dirt"
    } else {
        "minecraft:dirt"
    }
}
/// The charred grass round it: coarse dirt and podzol, patchier further out, in streaks running out from the middle
/// (the flash's and the blast's, as burnt round a ground zero) that carry it further out along them.
fn charred(x: i32, z: i32, r: f64, a: f64, seed: u32) -> Option<&'static str> {
    let n = vnoise(f64::from(x), f64::from(z), 6.0, seed ^ 0x71);
    let m = vnoise(f64::from(x), f64::from(z), 2.0, seed ^ 0x72);
    // (looked up round a circle, so the streaks close up with no seam: about seventy of them, uneven)
    let k = 11.0 + 0.004 * r;
    let st = vnoise(a.cos() * k, a.sin() * k, 1.0, seed ^ 0x73);
    let out = (r + 45.0 * (st - 0.5)).max(0.0);
    let reach = 0.25 + 0.7 * (1.0 - ((out - NK_CRATER_R * 1.5) / (NK_CHAR - NK_CRATER_R * 1.5)).clamp(0.0, 1.0)).powf(1.3) + 0.22 * (st - 0.5);
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
    (0.0..NK_BAND).contains(&e).then(|| 1.0 - e / NK_BAND)
}
/// A tree in the band knocked flat (more of them near the flattened land).
fn knocked(c: &Column, s: &Shape, x: i32, z: i32) -> bool {
    c.trunk >= 3 && !c.fluid && band(s, x, z).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x91) < 0.75 * p.powf(1.1))
}
/// What the blast makes of column (x, z): Kept, or its new ground's top (`Some`) and whether it was cleared.
fn new_ground(c: &Column, s: &Shape, x: i32, z: i32) -> Option<i32> {
    let (r, a, u) = s.at(x, z);
    if u < 1.0 {
        Some(c.g - bowl(u).round() as i32)
    } else if u < NK_RIM {
        let n = vnoise(f64::from(x), f64::from(z), 4.0, s.seed ^ 0x35);
        Some(c.g + heap(u, n).round() as i32)
    } else if r < s.flat(a) || knocked(c, s, x, z) {
        Some(c.g)
    } else {
        None
    }
}
/// Water or lava within a column's reach: dig nothing there or next to it.
fn wet_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    // (the nuke's crater is deep: two columns of ground kept between it and any water)
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (1, -1), (-1, 1), (-1, -1)].iter().any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid))
}

/// The crater, the rim's heap, the flattened land and the charred grass, over rows k0..k1 of the land's square.
fn nk_blast_rows(q: &mut Plan, shared: Shared, shape: Shape, k0: i32, k1: i32, at_t: f32, now: f32) {
    // (the land not all in yet: wait for it, a while)
    if !shared.borrow().done && now < NK_HIT - 2.0 {
        q.later(now + 0.1, move |q| nk_blast_rows(q, shared, shape, k0, k1, at_t, now + 0.1));
        return;
    }
    {
        let land = shared.borrow();
        nk_blast_band(q, &land, &shape, k0, k1, at_t);
    }
    q.later(now, move |q| nk_tidy_rows(q, &shared.borrow(), &shape, k0, k1, at_t + 0.1));
}
fn nk_blast_band(q: &mut Plan, land: &Land, s: &Shape, k0: i32, k1: i32, at_t: f32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut b = Blocks::default();
    for k in k0..k1 {
        for i in 0..NK_GW {
            let (x, z) = (bx - NK_READ + i, bz - NK_READ + k);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            let (r, ang, u) = s.at(x, z);
            if r > f64::from(NK_READ) || c.fluid {
                continue;
            }
            let wet = wet_near(land, bx, bz, x, z);
            match new_ground(c, s, x, z) {
                Some(top) if top < c.g && !wet => {
                    // the crater: dug, everything over it gone, its new face scorched (two deep near the middle), and
                    // what water or lava lies just under it sealed
                    b.run(x, z, top + 1, c.top.max(c.g), "minecraft:air");
                    b.put(x, z, top - 3, top - 1, "minecraft:stone", Some("minecraft:water"), false);
                    b.put(x, z, top - 3, top - 1, "minecraft:stone", Some("minecraft:lava"), false);
                    // (and what water or lava the crater's walls open, in the ground round it, sealed: 18 deep it cuts
                    // into the water under the land near the sea's level)
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        b.put(x + dx, z + dz, top - 3, c.g, "minecraft:stone", Some("minecraft:water"), false);
                        b.put(x + dx, z + dz, top - 3, c.g, "minecraft:stone", Some("minecraft:lava"), false);
                    }
                    let d = if u < 0.75 { 1 } else { 0 };
                    for y in top - d..=top {
                        b.run(x, z, y, y, scorched(x, y, z, u, s.seed));
                    }
                }
                Some(top) if top > c.g && !wet => {
                    // the rim: earth heaped on it, what stood there swept off
                    for y in c.g + 1..=top {
                        b.run(x, z, y, y, ejecta(x, y, z, s.seed));
                    }
                    if c.top > top {
                        b.run(x, z, top + 1, c.top, "minecraft:air");
                    }
                    // (and the water or lava the crater's wall would open, under it, sealed)
                    b.put(x, z, c.g - NK_CRATER_D as i32 - 2, c.g, "minecraft:dirt", Some("minecraft:water"), false);
                    b.put(x, z, c.g - NK_CRATER_D as i32 - 2, c.g, "minecraft:stone", Some("minecraft:lava"), false);
                }
                Some(_) => {
                    // flattened: everything standing on the land swept off (a felled tree's stump left), the grass charred
                    let stump = if c.trunk > 0 { 1 + (mh((x * 31 + z * 17) as u32, s.seed, 0x81) * 2.0) as i32 } else { 0 };
                    if c.top > c.g + stump {
                        b.run(x, z, c.g + 1 + stump, c.top, "minecraft:air");
                    }
                    if c.ground == 1
                        && let Some(m) = charred(x, z, r, ang, s.seed)
                    {
                        b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                    }
                }
                None => {
                    if c.ground == 1
                        && let Some(m) = charred(x, z, r, ang, s.seed)
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
    q.ev.push((at_t, Act::Blocks(Box::new(b))));
}
/// What is left hanging round what changed over rows k0..k1 (leaves of a tree whose trunk went, plants whose ground
/// went), on a stage of its own.
fn nk_tidy_rows(q: &mut Plan, land: &Land, s: &Shape, k0: i32, k1: i32, at_t: f32) {
    let (bx, bz) = (q.bx, q.bz);
    let col = |x: i32, z: i32| -> Col {
        match at(land, bx, bz, x, z) {
            Some(c) if !c.fluid && new_ground(c, s, x, z).is_some() && !(wet_near(land, bx, bz, x, z) && new_ground(c, s, x, z) != Some(c.g)) => Col::Cleared,
            _ => Col::Kept,
        }
    };
    let t = tidy(bx - NK_READ, bz - NK_READ + k0, bx + NK_READ, bz - NK_READ + k1 - 1, 40, -1, col);
    if !t.runs.is_empty() {
        q.ev.push((at_t, Act::Blocks(Box::new(t))));
    }
}

/// The trees felled, lying on the land pointing away from the blast (their leaves crushed round their crowns, stripped
/// off near it), and the rubble strewn over it all, landing a few seconds after.
type Used = Rc<RefCell<std::collections::HashSet<(i32, i32)>>>;
fn nk_felled(q: &mut Plan, shared: Shared, shape: Shape, used: Used, k0: i32, k1: i32, now: f32) {
    if !shared.borrow().done && now < NK_HIT - 1.0 {
        q.later(now + 0.1, move |q| nk_felled(q, shared, shape, used, k0, k1, now + 0.1));
        return;
    }
    nk_felled_band(q, &shared.borrow(), &shape, &used, k0, k1);
}
/// The felled trees go in once the blast's bands are all in (which clear what stood there).
const NK_LAID: f32 = NK_HIT + 0.08 + 0.05 * NK_BANDS as f32 + 0.3;
fn nk_felled_band(q: &mut Plan, land: &Land, s: &Shape, used: &Used, k0: i32, k1: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut used = used.borrow_mut();
    let mut b = Blocks::default();
    // (a column a log may lie on: flattened, not the crater or its rim, dry, its ground near the last one's)
    let lie = |x: i32, z: i32, gy: i32| -> Option<i32> {
        let c = at(land, bx, bz, x, z)?;
        let (r, a, u) = s.at(x, z);
        if c.fluid || u < NK_RIM || (c.g - gy).abs() > 1 || wet_near(land, bx, bz, x, z) {
            return None;
        }
        // (past the flattened land: only on open ground)
        if r > s.flat(a) - 1.0 && (band(s, x, z).is_none() || c.trunk > 0 || c.top > c.g + 1) {
            return None;
        }
        Some(c.g)
    };
    for k in k0..k1 {
        for i in 0..NK_GW {
            let (x, z) = (bx - NK_READ + i, bz - NK_READ + k);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            if c.trunk < 3 || c.fluid {
                continue;
            }
            let (r, a, u) = s.at(x, z);
            if u < NK_RIM || (r > s.flat(a) - 1.0 && !knocked(c, s, x, z)) {
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
            if let (Some((lx, lz, _)), true) = (last, r > 110.0 && c.leaves != 255) {
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
    q.ev.push((NK_LAID, Act::Blocks(Box::new(b))));
}
/// The rubble: chunks of the ground thrown out, more near it, landing over a few seconds.
fn nk_rubble(q: &mut Plan, land: &Land, s: &Shape, used: &Used) {
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
    for _ in 0..1200 {
        let r = NK_CRATER_R * 1.05 + (NK_RUBBLE - NK_CRATER_R * 1.05) * rng.next().powf(1.7);
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
        let w = ((r / NK_RUBBLE) * 3.99) as usize;
        waves[w.min(3)].run(x, z, y, y, m);
        used.insert((x, z));
        // (now and then a bigger chunk: two side by side)
        if rng.next() < 0.25 && r < 140.0 {
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
        for n in 0..1200 {
            let r = NK_CRATER_R * 1.45 + (NK_FLAT * 1.1 + NK_BAND - NK_CRATER_R * 1.45) * rng.next().powf(0.8);
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
            q.ev.push((NK_LAID + 0.3 + 0.9 * i as f32, Act::Blocks(Box::new(w))));
        }
    }
}

/// Real blocks thrown out of the crater as it is blasted open: the ground that was there (grass and dirt off its top, the
/// stone and tuff under it, now and then a log of the wood growing round it), flung outward and up over the first second
/// and a half, at all speeds, so some come down by the rim and some arc far out over the flattened land. Some land as
/// blocks, the rest break up where they land (CancelDrop); none drops an item.
fn nk_thrown(q: &mut Plan, land: &Land, s: &Shape, part: u64) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410 ^ (part << 20));
    let mut woods = [0u32; 9];
    for c in land.cols.iter().filter(|c| c.known && c.trunk > 0) {
        woods[c.wood as usize] += 1;
    }
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let mut n = 0;
    for _ in 0..NK_THROWN * 3 / 2 {
        if n >= NK_THROWN / 2 {
            break;
        }
        // (from anywhere in the crater, more from its middle)
        let r = NK_CRATER_R * 0.85 * rng.next().sqrt();
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
        let h = 0.6 + 3.2 * rng.next().powf(1.4);
        let vy = 1.0 + 1.8 * rng.next();
        let (vx, vz) = (ang.cos() * h, ang.sin() * h);
        let y = f64::from(c.g) + 1.2 + 2.5 * rng.next();
        // (most in the first half second, the last ones at a second and a half)
        let t = NK_HIT + 0.05 + 1.5 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

// ---- the flash: what faces the fireball past the blast's reach, scorched ---------------------------------------------
/// Past the land the blast knocks over (NK_READ) out to NK_FLASH, what the flash sees is scorched: the leaves facing
/// it burnt off, the wood and planks charred dark, the grass burnt to bare earth, the plants gone, wool blackened,
/// the odd fire lit; what the land, a tree or a wall hides from it is left as it was (the flash's shadows). Read as it
/// starts (NK_FL_PARTS queries, NK_FL_BELOW under each column's top), worked out in NK_FL_BANDS stages ahead and put in
/// over the second and a half after the burst.
const NK_FLASH: i32 = 480;
const NK_FL_W: i32 = 2 * NK_FLASH + 1;
const NK_FL_PARTS: i32 = 32;
const NK_FL_BELOW: u32 = 30;
/// The line of sight worked out along NK_FL_RAYS rays out from the fireball, in NK_FL_SWEEPS stages; then the edits in
/// NK_FL_BANDS stages of rows.
const NK_FL_RAYS: i32 = 3400;
const NK_FL_SWEEPS: i32 = 16;
const NK_FL_BANDS: i32 = 12;
/// What a column holds that the flash changes, a bit each: the leaves of each wood (0-8), the logs of each (9-17),
/// a grass block on top (18), the plants (19-24), wool and carpet (25-26), planks of three woods (27-29).
const FL_PLANTS: [&str; 6] = ["minecraft:short_grass", "minecraft:tall_grass", "minecraft:fern", "minecraft:large_fern", "minecraft:dandelion", "minecraft:poppy"];
const FL_OTHER: [(&str, &str); 5] = [
    ("minecraft:white_wool", "minecraft:black_wool"),
    ("minecraft:white_carpet", "minecraft:black_carpet"),
    ("minecraft:oak_planks", "minecraft:dark_oak_planks"),
    ("minecraft:spruce_planks", "minecraft:dark_oak_planks"),
    ("minecraft:birch_planks", "minecraft:dark_oak_planks"),
];
fn fl_bit(name: &str) -> u32 {
    let n = name.split('[').next().unwrap_or(name);
    if let Some(i) = LEAF_NAMES.iter().position(|l| *l == n) {
        return 1 << i;
    }
    if let Some(i) = LOG_Y.iter().position(|l| *l == n) {
        return 1 << (9 + i);
    }
    if n == "minecraft:grass_block" {
        return 1 << 18;
    }
    if let Some(i) = FL_PLANTS.iter().position(|l| *l == n) {
        return 1 << (19 + i);
    }
    FL_OTHER.iter().position(|(l, _)| *l == n).map_or(0, |i| 1 << (25 + i))
}
struct Flash {
    /// Each column's top (i16::MIN: not known), its ground, what it holds, and the lowest of it the fireball sees
    /// (i16::MAX: not worked out); over the square out to NK_FLASH. How many of the reads are in.
    top: Vec<i16>,
    g: Vec<i16>,
    mats: Vec<u32>,
    seen: Vec<i16>,
    parts: usize,
}
type FlashShared = Rc<RefCell<Flash>>;
fn fl_idx(bx: i32, bz: i32, x: i32, z: i32) -> Option<usize> {
    let (i, k) = (x - bx + NK_FLASH, z - bz + NK_FLASH);
    (i >= 0 && k >= 0 && i < NK_FL_W && k < NK_FL_W).then(|| (k * NK_FL_W + i) as usize)
}
/// The ring's columns read in part `part` (a run of rows of it, past NK_READ and within NK_FLASH, about as many columns
/// in each part: some 15,000, half a query's worth at NK_FL_BELOW deep).
fn fl_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let ring = |dz: i32, dx: i32| {
        let r2 = dx * dx + dz * dz;
        r2 > NK_READ * NK_READ && r2 <= NK_FLASH * NK_FLASH
    };
    let count = |dz: i32| (-NK_FLASH..=NK_FLASH).filter(|&dx| ring(dz, dx)).count();
    let total: usize = (-NK_FLASH..=NK_FLASH).map(count).sum();
    let per = total.div_ceil(NK_FL_PARTS as usize);
    let mut out = Vec::new();
    let mut seen = 0usize;
    for dz in -NK_FLASH..=NK_FLASH {
        let n = count(dz);
        let k = (seen + n / 2) / per;
        seen += n;
        if k as i32 == part || (part == NK_FL_PARTS - 1 && k as i32 > part) {
            out.extend((-NK_FLASH..=NK_FLASH).filter(|&dx| ring(dz, dx)).map(|dx| (bx + dx, bz + dz)));
        }
    }
    out
}
fn fl_take_in(fl: &mut Flash, a: &crate::columns::Answer, bx: i32, bz: i32) {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    let bits: Vec<u32> = a.palette.iter().map(|n| fl_bit(n)).collect();
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else { continue };
        let Some(ix) = fl_idx(bx, bz, x, z) else { continue };
        let base = surface - a.below;
        let mut top = None;
        let mut m = 0u32;
        for j in (0..blocks.len()).rev() {
            let b = blocks[j] as usize;
            let (k, _) = kinds.get(b).copied().unwrap_or((Kind::Loose, 0));
            if k == Kind::Air {
                continue;
            }
            top.get_or_insert(base + j as i32);
            m |= bits.get(b).copied().unwrap_or(0);
            if k == Kind::Ground || k == Kind::Fluid {
                fl.g[ix] = (base + j as i32) as i16;
                if k == Kind::Fluid {
                    m = 0;
                }
                break;
            }
        }
        if let Some(t) = top {
            fl.top[ix] = t as i16;
            fl.mats[ix] = m;
        }
    }
}
fn nk_flash_step(q: &mut Plan, fl: FlashShared, tags: Rc<Vec<u32>>, part: usize, at_t: f32) {
    if part >= tags.len() {
        return;
    }
    let Some(a) = crate::columns::take(tags[part]) else {
        if at_t < NK_HIT - 4.5 {
            q.later(at_t + 0.1, move |q| nk_flash_step(q, fl, tags, part, at_t + 0.1));
        }
        return;
    };
    fl_take_in(&mut fl.borrow_mut(), &a, q.bx, q.bz);
    fl.borrow_mut().parts += 1;
    // (the next but one asked for only now: a few megabytes an answer, they are kept in hand two at a time)
    if part + 2 < tags.len() {
        let columns = fl_columns(q.bx, q.bz, part as i32 + 2);
        q.ev.push((at_t, Act::Read { tag: tags[part + 2], columns, below: NK_FL_BELOW, above: 1 }));
    }
    q.later(at_t + 0.05, move |q| nk_flash_step(q, fl, tags, part + 1, at_t + 0.05));
}
/// The flash's line of sight along rays j0..j1 out from the fireball: going out along each, the steepest the land and
/// what stands on it rise towards the fireball so far, and so for each column past the blast's reach the lowest of it
/// the fireball sees over them (the land, the trees and the walls between). Waits for the land to be in.
fn nk_flash_sweep(q: &mut Plan, fl: FlashShared, land: Shared, s: Shape, gy: i32, j0: i32, j1: i32, now: f32) {
    if (fl.borrow().parts < NK_FL_PARTS as usize || !land.borrow().done) && now < NK_HIT - 1.5 {
        q.later(now + 0.1, move |q| nk_flash_sweep(q, fl, land, s, gy, j0, j1, now + 0.1));
        return;
    }
    let (bx, bz) = (q.bx, q.bz);
    let hb = f64::from(gy) + NK_BURST;
    let land = land.borrow();
    let mut fl = fl.borrow_mut();
    for j in j0..j1 {
        let th = TAU * f64::from(j) / f64::from(NK_FL_RAYS);
        let (ux, uz) = (th.cos(), th.sin());
        // (the steepest slope from the fireball to anything passed so far)
        let mut m = f64::NEG_INFINITY;
        let mut last = (i32::MIN, i32::MIN);
        let mut d = 2.0;
        while d <= f64::from(NK_FLASH) {
            let (x, z) = ((s.cx + ux * d).floor() as i32, (s.cz + uz * d).floor() as i32);
            if (x, z) != last {
                last = (x, z);
                let h = if let Some(c) = at(&land, bx, bz, x, z) {
                    Some(f64::from(c.top))
                } else {
                    fl_idx(bx, bz, x, z).filter(|&i| fl.top[i] != i16::MIN).map(|i| f64::from(fl.top[i]))
                };
                if d > f64::from(NK_READ)
                    && let Some(i) = fl_idx(bx, bz, x, z)
                {
                    // (seen from its own top down to where the slope so far passes over it)
                    let lo = (hb + m * d).ceil();
                    let lo = if lo.is_finite() { lo.clamp(-32000.0, 32000.0) as i16 } else { i16::MIN };
                    fl.seen[i] = fl.seen[i].min(lo);
                }
                if let Some(h) = h {
                    m = m.max((h + 1.0 - hb) / d);
                }
            }
            d += 0.7;
        }
    }
}
/// The flash's scorching over rows k0..k1 of its square: what lies over the lowest of each column the fireball sees
/// changed, more surely the nearer it is.
fn nk_flash_rows(q: &mut Plan, fl: &Flash, s: &Shape, k0: i32, k1: i32, at_t: f32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut b = Blocks::default();
    for k in k0..k1 {
        for i in 0..NK_FL_W {
            let (x, z) = (bx - NK_FLASH + i, bz - NK_FLASH + k);
            let ix = (k * NK_FL_W + i) as usize;
            let m = fl.mats[ix];
            if m == 0 || fl.top[ix] == i16::MIN || fl.seen[ix] == i16::MAX {
                continue;
            }
            let r = (s.cx - (f64::from(x) + 0.5)).hypot(s.cz - (f64::from(z) + 0.5));
            if r <= f64::from(NK_READ) || r > f64::from(NK_FLASH) {
                continue;
            }
            let top = i32::from(fl.top[ix]);
            let g = i32::from(fl.g[ix]);
            let lo = i32::from(fl.seen[ix]).max(g);
            if lo > top {
                continue;
            }
            // (surely near the blast's reach, a third as often at the flash's)
            let p = 1.0 - 0.65 * ((r - f64::from(NK_READ)) / f64::from(NK_FLASH - NK_READ)).powf(1.3);
            let h0 = (x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32;
            let roll = |salt: u32| mh(h0, s.seed, salt);
            for w in 0..9 {
                if m & (1 << w) != 0 && roll(0xf1) < 0.9 * p {
                    b.put(x, z, lo, top, "minecraft:air", Some(LEAF_NAMES[w]), false);
                }
                if m & (1 << (9 + w)) != 0 && w != 5 && roll(0xf2) < p {
                    b.put(x, z, lo, top, "minecraft:dark_oak_log", Some(LOG_Y[w]), false);
                }
            }
            let plants = (m >> 19) & 0x3f;
            if g + 1 >= lo {
                for (n, name) in FL_PLANTS.iter().enumerate() {
                    if plants & (1 << n) != 0 && roll(0xf3) < 0.95 * p {
                        let to = if roll(0xf4) < 0.08 { "minecraft:dead_bush" } else { "minecraft:air" };
                        b.put(x, z, g + 1, g + 2, to, Some(name), false);
                    }
                }
            }
            if m & (1 << 18) != 0 && g >= lo && roll(0xf5) < p {
                let to = if roll(0xf6) < 0.3 { "minecraft:podzol" } else { "minecraft:coarse_dirt" };
                b.put(x, z, g, g, to, Some("minecraft:grass_block"), false);
                // (now and then a fire on the bare ground, where nothing over it would carry it up)
                if m & 0x1ff == 0 && plants == 0 && roll(0xf7) < 1.0 / 5000.0 {
                    b.put(x, z, g + 1, g + 1, "minecraft:fire", Some("minecraft:air"), false);
                }
            }
            for (n, (from, to)) in FL_OTHER.iter().enumerate() {
                if m & (1 << (25 + n)) != 0 && roll(0xf8) < p {
                    b.put(x, z, lo, top, to, Some(from), false);
                }
            }
        }
    }
    if !b.runs.is_empty() {
        q.ev.push((at_t, Act::Blocks(Box::new(b))));
    }
}

/// The shockwave's jolt reaching the player at `t`, `fo` as hard: the Payload's (a hard hit, strong quick swings, a
/// shudder fading), harder and longer.
fn nk_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 1.4);
    p.shake(t + 0.05, 0.6 * fo, 6.0);
    for n in 0..10 {
        p.shake(t + 0.1 * (n + 1) as f32, (1.0 - 0.04 * n as f32) * fo, 0.16);
    }
    for n in 0..30 {
        let u = n as f32 / 30.0;
        p.shake(t + 1.1 + 0.1 * n as f32, (0.7 * (1.0 - u).powf(1.2) + 0.1) * fo, 0.12);
    }
}

/// How loud the shockwave's gust is `dist` blocks off: all of it within ~70 blocks, a half at ~600, a third past ~1,100.
fn nk_shock_vol(dist: f64) -> f32 {
    (1.15 / (1.0 + dist / 450.0)).clamp(0.3, 1.0) as f32
}

/// How much of the blast is heard as the far one (`blast_far`), `dist` blocks off: none within 300, all of it past 900.
fn nk_far(dist: f64) -> f32 {
    let u = ((dist - 300.0) / 600.0).clamp(0.0, 1.0);
    (u * u * (3.0 - 2.0 * u)) as f32
}

/// The nuke. Calm; the bomb high in the sky falling; the burst: the flash (silent), the fireball and the mushroom cloud,
/// the shockwave's dust over the land and over the player late by how far they are, with the blast and its jolt, the
/// debris coming down, the long rumble after; the cloud standing over it all a long time.
pub(super) fn nuke_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let geo = NkGeo::new(shader_seed, rel);
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    // (heard from the burst point, over the ground)
    let (late, dist) = sound_from([cx, gy + NK_BURST, cz], me);
    let fo = falloff(dist * 0.4).max(0.45);

    // the pass's table, on the tick after it fires
    {
        let s = shader_seed;
        p.later(0.05, move |q| {
            q.ev.push((0.05, Act::Table(nk_table(s, rel))));
            q.ev.push((0.05, Act::Words { index: NK_DB as u32, words: nk_debris_words(s as u32) }));
        });
    }
    // (and the land's shape round it, asked of the world as it starts, the heightfield on a later tick)
    {
        let reach = nk_hf_reach(rel[0].hypot(rel[2]));
        let columns = Rc::new(nk_hf_columns(bx, bz, reach));
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        p.later(0.4, move |q| nk_hf_step(q, tag, columns, reach, rel, by + 1, 0.4));
    }

    // ---- the fall ---------------------------------------------------------------------------------------------------
    p.at(0.6, bar("WARNING: NUCLEAR DEVICE RELEASED", "red"));
    p.at(5.0, bar("WARNING: NUCLEAR DEVICE INBOUND", "red"));
    p.at(NK_TURN, bar("TAKE COVER", "yellow"));
    // (its fall, heard from up there: whistling down onto the burst, cut there)
    p.csound(NK_SEEN - 0.5, "fall", 10.0, 1.0);
    // ---- the burst: the flash is silent; the land's answer through the ground first, felt more than heard ----------
    let tg = NK_HIT + (dist / NK_GROUND_V) as f32;
    let gap = NK_HIT + late - tg;
    let gv = ((1.0 / (1.0 + dist / 1200.0)).clamp(0.35, 1.0) * (f64::from(gap - 0.05) / 0.9).clamp(0.3, 1.0).powf(1.2)) as f32;
    p.csound(tg - 0.02, "ground", 10.0 * gv, 1.0);
    if gap > 0.08 {
        p.shake(tg, 0.5 * (2.0 / (1.0 + dist / 500.0)).clamp(0.4, 1.0) as f32, 0.6);
    }
    // ---- the air's: the blast, the shockwave's roar as the front passes, the jolt, the long rumble after -------------
    let arrive = NK_HIT + late;
    let far = nk_far(dist);
    if far < 1.0 {
        p.csound(arrive - 0.02, "blast", 10.0 * (1.0 - far), 1.0);
    }
    if far > 0.0 {
        // (and quieter yet the further off it is: a kilometre and a half off, about three quarters as loud)
        p.csound(arrive - 0.02, "blast_far", 10.0 * far * ((1.25 / (1.0 + dist / 2000.0)).min(1.0) as f32), 1.0);
    }
    // (the gust of the front going past: violent close by, a third as loud a kilometre and more off, where it is a gust
    // of wind and grit and no more)
    p.csound(arrive - 0.2, "shockwave", 10.0 * nk_shock_vol(dist), 1.0);
    p.csound(arrive + 1.5, "rumble", 10.0, 1.0);
    nk_jolt(&mut p, arrive, (2.2 / (1.0 + dist / 600.0)).clamp(0.5, 1.0) as f32);
    let mut ts = arrive + 4.2;
    while ts < arrive + 16.0 {
        let s = p.rng.uniform(0.05, 0.14) as f32 * fo;
        let d = p.rng.uniform(0.4, 0.9) as f32;
        p.shake(ts, s, d);
        ts += p.rng.uniform(0.5, 1.2) as f32;
    }
    // (debris thudding and pattering down round the player if they are near enough to be under it)
    if dist < 700.0 {
        let near = (1.0 - dist / 700.0) as f32;
        p.csound(arrive + 3.0, "debris", 10.0 * (0.5 + 0.5 * near), 1.0);
        if near > 0.3 {
            p.csound(arrive + 9.0, "debris", 10.0 * (0.25 + 0.4 * near), 0.9);
        }
        let mut td = arrive + 3.2;
        for _ in 0..(8.0 + 14.0 * near) as usize {
            let n = (14.0 + 60.0 * near * p.rng.next() as f32) as i32;
            p.at(td, format!(r#"execute at @s run particle minecraft:block{{block_state:"minecraft:coarse_dirt"}} ~ ~14 ~ 18 6 18 0.6 {n} force @s"#));
            p.at(td + 0.1, format!(r#"execute at @s run particle minecraft:falling_dust{{block_state:"minecraft:sand"}} ~ ~10 ~ 16 6 16 0 {} force @s"#, n * 2));
            td += p.rng.uniform(0.25, 0.9) as f32;
        }
    }
    p.at(NK_HIT + 2.0, bar("NUCLEAR DETONATION", "gold"));
    for t in [NK_HIT + 0.1, NK_HIT + 1.5, NK_HIT + 4.0, NK_HIT + 8.0] {
        p.at(t, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{NK_KILL}]"));
    }
    // (real smoke and grit round the crater, for anyone close)
    p.at(NK_HIT + 0.1, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 20 6 20 0 20 force", gy + 3.0));
    p.at(NK_HIT + 0.2, format!(r#"particle minecraft:block{{block_state:"minecraft:dirt"}} {cx:.1} {:.1} {cz:.1} 40 8 40 1.0 800 force"#, gy + 4.0));
    for i in 0..10 {
        let t = NK_HIT + 1.0 + i as f32 * 1.6;
        p.at(t, format!("particle minecraft:campfire_signal_smoke {cx:.1} {:.1} {cz:.1} 30 3 30 0.03 60 force", gy + 1.0));
    }

    if terrain {
        let land: Shared = Rc::new(RefCell::new(Land { cols: vec![Column::default(); (NK_GW * NK_GW) as usize], missing: Vec::new(), done: false }));
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, NK_READ as f64 + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // the land read as it starts (a query a part, each a stage of its own), taken in a stage a part
        let tags: Rc<Vec<u32>> = Rc::new((0..NK_PARTS).map(|_| crate::columns::new_tag()).collect());
        for part in 0..NK_PARTS {
            let tags = tags.clone();
            let t = 0.1 + 0.05 * part as f32;
            p.later(t, move |q| {
                let columns = read_columns(q.bx, q.bz, part);
                q.ev.push((t, Act::Read { tag: tags[part as usize], columns, below: NK_BELOW, above: NK_ABOVE }));
            });
        }
        {
            let land = land.clone();
            p.later(0.6, move |q| nk_land_step(q, land, tags, 0, 0.6, 0));
        }
        // the blast's edits worked out ahead, a band of rows a stage, the middle's first (their blocks going in after
        // the burst, a band a tick or so, from the middle out), and what each leaves hanging, each on a stage of its own
        let shape = Shape { cx, cz, ph: [TAU * mh(1, geo.seed, 0xc1), TAU * mh(2, geo.seed, 0xc1), TAU * mh(3, geo.seed, 0xc1)], seed: geo.seed };
        let bands = NK_BANDS;
        let rows = (NK_GW + bands - 1) / bands;
        let mut order: Vec<i32> = (0..bands).collect();
        order.sort_by_key(|&j| (2 * j + 1 - bands).abs());
        for (n, &j) in order.iter().enumerate() {
            let (k0, k1) = (j * rows, ((j + 1) * rows).min(NK_GW));
            let t = 3.0 + 0.04 * n as f32;
            let at = NK_HIT + 0.08 + 0.05 * n as f32;
            let l1 = land.clone();
            p.later(t, move |q| nk_blast_rows(q, l1, shape, k0, k1, at, t));
        }
        // the trees felled, a band of rows a stage, then the rubble and the blocks thrown
        let used: Used = Default::default();
        let fb = 26;
        let rows = (NK_GW + fb - 1) / fb;
        for j in 0..fb {
            let (land, used) = (land.clone(), used.clone());
            p.later(5.0 + 0.05 * j as f32, move |q| nk_felled(q, land, shape, used, j * rows, ((j + 1) * rows).min(NK_GW), 5.0));
        }
        for part in 0..2u64 {
            let land = land.clone();
            p.later(NK_HIT - 0.7 + 0.1 * part as f32, move |q| nk_thrown(q, &land.borrow(), &shape, part));
        }
        {
            let land = land.clone();
            p.later(NK_HIT - 0.9, move |q| nk_rubble(q, &land.borrow(), &shape, &used));
        }
        // the flash's scorching past the blast's reach: the ring read as it starts, worked out a band of rows a stage
        let fl: FlashShared = Rc::new(RefCell::new(Flash {
            top: vec![i16::MIN; (NK_FL_W * NK_FL_W) as usize],
            g: vec![0; (NK_FL_W * NK_FL_W) as usize],
            mats: vec![0; (NK_FL_W * NK_FL_W) as usize],
            seen: vec![i16::MAX; (NK_FL_W * NK_FL_W) as usize],
            parts: 0,
        }));
        let ftags: Rc<Vec<u32>> = Rc::new((0..NK_FL_PARTS).map(|_| crate::columns::new_tag()).collect());
        for part in 0..2 {
            let ftags = ftags.clone();
            let t = 1.0 + 0.05 * part as f32;
            p.later(t, move |q| {
                let columns = fl_columns(q.bx, q.bz, part);
                q.ev.push((t, Act::Read { tag: ftags[part as usize], columns, below: NK_FL_BELOW, above: 1 }));
            });
        }
        {
            let fl = fl.clone();
            p.later(1.2, move |q| nk_flash_step(q, fl, ftags, 0, 1.2));
        }
        let gyi = by + 1;
        let per = (NK_FL_RAYS + NK_FL_SWEEPS - 1) / NK_FL_SWEEPS;
        for j in 0..NK_FL_SWEEPS {
            let (fl, land) = (fl.clone(), land.clone());
            let t = 4.5 + 0.1 * j as f32;
            p.later(t, move |q| nk_flash_sweep(q, fl, land, shape, gyi, j * per, ((j + 1) * per).min(NK_FL_RAYS), t));
        }
        let rows = (NK_FL_W + NK_FL_BANDS - 1) / NK_FL_BANDS;
        for j in 0..NK_FL_BANDS {
            let fl = fl.clone();
            let t = 8.0 + 0.1 * j as f32;
            let at = NK_HIT + 0.05 + 0.12 * j as f32;
            p.later(t, move |q| nk_flash_rows(q, &fl.borrow(), &shape, j * rows, ((j + 1) * rows).min(NK_FL_W), at));
        }
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path NK_ME=x,y,z cargo test --release nk_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the target's ground at the preview's (0.5 65 0.5), the
    /// player at NK_ME.
    #[test]
    #[ignore]
    fn nk_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let mut w = super::nk_table(seed, rel);
        // (the land's shape, as tools/preview draws it: NK_HILLS=H its hills (main.rs's hills_h), flat otherwise)
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let reach = super::nk_hf_reach(rel[0].hypot(rel[2]));
        let heights: Vec<Option<f64>> = super::nk_hf_columns(0, 0, reach)
            .iter()
            .map(|&(x, z)| {
                let (x, z) = (f64::from(x) + 0.5, f64::from(z) + 0.5);
                Some(hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin()))
            })
            .collect();
        let hf = super::nk_hf_words(&heights, reach, rel);
        w.resize(super::NK_HF + hf.len(), 0);
        w[super::NK_HF..].copy_from_slice(&hf);
        let db = super::nk_debris_words(seed as u32);
        w.resize(super::NK_DB + db.len(), 0);
        w[super::NK_DB..].copy_from_slice(&db);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    #[test]
    fn nuke_sounds_are_its_own_and_arrive_late_by_the_distance() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let sounds = |z: f64| -> Vec<(f32, String, f32)> {
            plan(&crate::lasers::NUKE, &target, false, "minecraft:overworld", 37.0, [10.5, 66.0, z], 0)
                .into_iter()
                .filter_map(|(t, a)| if let Act::Sound { event, volume, .. } = a { Some((t, event, volume)) } else { None })
                .collect()
        };
        let near = sounds(200.0);
        let has = |v: &[(f32, String, f32)], s: &str| v.iter().find(|e| e.1 == format!("orbital:nuke.{s}")).map(|e| e.0);
        for s in ["fall", "blast", "ground", "shockwave", "debris", "rumble"] {
            assert!(has(&near, s).is_some(), "{s}");
        }
        assert!(has(&near, "blast_far").is_none());
        // (the flash is silent: nothing of the burst is heard until the ground and the air carry it)
        assert!(near.iter().all(|e| e.1.ends_with("fall") || e.0 > NK_HIT), "{near:?}");
        let far = sounds(1500.0);
        assert!(has(&far, "blast").is_none() && has(&far, "blast_far").is_some());
        assert!(has(&far, "blast_far").unwrap() > has(&near, "blast").unwrap() + 3.0);
        assert!(has(&far, "ground").unwrap() < has(&far, "blast_far").unwrap());
    }

    #[test]
    fn nuke_falls_from_high_up_onto_its_burst_point() {
        for seed in [3.0, 37.0, 512.0, 991.0] {
            let me = [0.0, 5.0, 600.0];
            let g = NkGeo::new(seed, me);
            let p0 = g.pos(f64::from(NK_SEEN));
            assert!(p0[1] > 800.0, "{p0:?}");
            let end = g.pos(f64::from(NK_HIT));
            assert!(len(add(end, [0.0, NK_BURST, 0.0], -1.0)) < 1e-6, "{end:?}");
            let mut last = p0;
            let mut t = f64::from(NK_SEEN);
            while t < f64::from(NK_HIT) {
                t += 0.02;
                let q = g.pos(t.min(f64::from(NK_HIT)));
                assert!(q[1] <= last[1] + 1e-9 && q[1] >= NK_BURST - 1e-6, "{t} {q:?}");
                last = q;
            }
        }
        let w = nk_table(37.0, [0.0, 5.0, 300.0]);
        assert!(w.len() <= NK_HF && NK_PF + NK_PUFFS * NK_PW <= NK_FR && NK_HF + 8 + NK_HN * NK_HN <= NK_DB);
    }

    #[test]
    fn nuke_heightfield_follows_the_land_and_shelters_behind_a_ridge() {
        let me = [0.0, 0.0, 300.0];
        let reach = nk_hf_reach(300.0);
        let cols = nk_hf_columns(0, 0, reach);
        assert_eq!(cols.len(), NK_HN * NK_HN);
        // (a ridge 30 high across the way to the player at z 150, a trunk standing in one cell, the far corner not loaded)
        let heights: Vec<Option<f64>> = cols
            .iter()
            .enumerate()
            .map(|(c, &(x, z))| {
                if c == 10 * NK_HN + 10 {
                    return Some(25.0);
                }
                if x > 300 && z > 300 {
                    return None;
                }
                Some(30.0 * (-(f64::from(z) - 150.0).powi(2) / 2000.0).exp() + 0.0 * f64::from(x))
            })
            .collect();
        let w = nk_hf_words(&heights, reach, me);
        assert_eq!(w.len(), 8 + NK_HN * NK_HN);
        assert_eq!(f32::from_bits(w[0]), NK_HN as f32);
        let cell = |x: f64, z: f64| {
            let step = 2.0 * reach / (NK_HN - 1) as f64;
            let (i, k) = (((x + reach) / step).round() as usize, ((z + reach) / step).round() as usize);
            let v = w[8 + k * NK_HN + i];
            (f64::from(v & 0xffff) / 8.0 - 512.0, f64::from((v >> 16) & 0xff) / 255.0)
        };
        let step = 2.0 * reach / (NK_HN - 1) as f64;
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
    fn column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let g = ground_h(x, z);
        let t = tree(x, z);
        let wet = pond(x, z);
        let block = |y: i32| -> &'static str {
            if wet {
                return if y < g - 3 { "minecraft:dirt" } else if y <= g { "minecraft:water" } else { "minecraft:air" };
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
        let top = if t { g + 9 } else { g + 2 };
        let (below, above) = (below as i32, above as i32);
        Some((top, (top - below..top + above).map(block).collect()))
    }

    fn played(terrain: bool) -> Vec<(f32, Blocks)> {
        played_all(terrain).0
    }
    fn played_all(terrain: bool) -> (Vec<(f32, Blocks)>, Vec<(f32, String)>) {
        crate::columns::clear();
        let mut cmds = Vec::new();
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::NUKE, &target, terrain, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Vec::new();
        let mut table = false;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| column(x, z, below, above)),
                Act::Blocks(b) => out.push((t, *b)),
                Act::Cmd(c) => cmds.push((t, c)),
                Act::Table(w) => {
                    assert_eq!(w.len(), NK_FR + (NK_CHUNKS + NK_SPARKS) * NK_FW);
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
    fn nuke_digs_a_crater_fells_the_trees_and_floods_nothing() {
        let blocks = played(true);
        assert!(!blocks.is_empty());
        let fills: Vec<String> = blocks.iter().flat_map(|(_, b)| b.as_fills()).collect();
        // nothing that burns, flows or spreads is placed
        for f in &fills {
            for bad in ["lava ", "water ", "fire", "magma", "sand ", "concrete_powder"] {
                assert!(!f.contains(&format!(" minecraft:{bad}")) || f.contains(" replace "), "{f}");
            }
        }
        // the middle dug about NK_CRATER_D deep
        let mid = fills.iter().find(|f| f.starts_with("fill 10 ") && f.contains(" -3 10 ") && f.contains("minecraft:air")).expect("the middle dug");
        let y0: i32 = mid.split_whitespace().nth(2).unwrap().parse().unwrap();
        assert!((ground_h(10, -3) - y0 + 1 - NK_CRATER_D as i32).abs() <= 1, "{mid}");
        // trees felled: logs lying along x or z
        let lying = fills.iter().filter(|f| f.contains("_log[axis=")).count();
        assert!(lying > 20, "{lying}");
        // past the flattened land: crowns stripped, and some trees knocked flat there (logs lying beyond NK_FLAT)
        let stripped = fills.iter().filter(|f| f.ends_with("minecraft:air replace minecraft:oak_leaves strict")).count();
        assert!(stripped > 10, "{stripped}");
        let far_logs = fills
            .iter()
            .filter(|f| f.contains("_log[axis="))
            .filter(|f| {
                let w: Vec<f64> = f.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap_or(0.0)).collect();
                (w[0] - 10.0).hypot(w[2] + 3.0) > NK_FLAT * 1.15
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
    fn nuke_flash_scorches_what_faces_it_past_the_blast() {
        let (out, _) = played_all(true);
        let (mut scorched, mut leaves, mut far) = (0, 0, 0);
        for (t, b) in &out {
            for f in b.as_fills() {
                let w: Vec<f64> = f.split_whitespace().skip(1).take(3).filter_map(|v| v.parse().ok()).collect();
                if w.len() < 3 {
                    continue;
                }
                let r = (w[0] - 10.0).hypot(w[2] + 3.0);
                if r > f64::from(NK_READ) + 1.0 {
                    assert!(r < f64::from(NK_FLASH) + 1.5, "{f}");
                    assert!(*t > NK_HIT && *t < NK_HIT + 2.0, "{t} {f}");
                    scorched += 1;
                    leaves += usize::from(f.contains("air replace minecraft:oak_leaves"));
                    far += usize::from(r > 440.0);
                }
            }
        }
        assert!(scorched > 1000 && leaves > 100 && far > 10, "{scorched} {leaves} {far}");
    }

    #[test]
    fn nuke_leaves_the_land_alone_with_the_terrain_off() {
        let (blocks, cmds) = played_all(false);
        assert!(blocks.is_empty());
        assert!(!cmds.iter().any(|(_, c)| c.contains("falling_block {")), "no blocks thrown with the terrain off");
    }

    #[test]
    fn nuke_throws_real_blocks_out_of_the_crater() {
        let (_, cmds) = played_all(true);
        let thrown: Vec<&(f32, String)> = cmds.iter().filter(|(_, c)| c.starts_with("summon minecraft:falling_block")).collect();
        // a fair number, over the second and a half after it strikes, a few a tick at most
        assert!(thrown.len() >= 60 && thrown.len() <= NK_THROWN, "{} thrown", thrown.len());
        let mut per_tick = std::collections::HashMap::new();
        for (t, c) in &thrown {
            assert!(*t > NK_HIT && *t < NK_HIT + 1.6, "{t}");
            *per_tick.entry((t * 20.0) as i32).or_insert(0) += 1;
            // never dropping an item; out of the crater (the target at 10 -3), outward and up
            assert!(c.contains("DropItem:0b"), "{c}");
            let w: Vec<f64> = c.split_whitespace().skip(2).take(3).map(|v| v.parse().unwrap()).collect();
            assert!((w[0] - 10.5).hypot(w[2] + 2.5) < NK_CRATER_R, "{c}");
            let m = c.split("Motion:[").nth(1).unwrap();
            let v: Vec<f64> = m.trim_end_matches("]}").split(',').map(|v| v.trim_end_matches('d').parse().unwrap()).collect();
            assert!(v[1] > 0.5, "{c}");
            assert!((w[0] - 10.5) * v[0] + (w[2] + 2.5) * v[2] >= -1.0e-6, "{c}");
            // of the ground that was there: no grass or leaves of a plant, nothing that flows
            assert!(!c.contains("water") && !c.contains("lava") && !c.contains("sand\""), "{c}");
        }
        assert!(per_tick.values().all(|&k| k <= 16), "{per_tick:?}");
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
    /// `cargo test --release nk_stage_cost -- --ignored --nocapture`: the heaviest stages (native time; see the fuel
    /// harness for the game's measure).
    #[test]
    #[ignore]
    fn nk_stage_cost() {
        let target = Target { block: [-1041, 64, 860], point: [-1040.5, 65.0, 860.5] };
        let t0 = std::time::Instant::now();
        let mut ev = plan(&crate::lasers::NUKE, &target, true, "minecraft:overworld", 19.0, [-1040.5, 70.0, 1160.5], 0);
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
