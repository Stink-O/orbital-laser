//! The nuke's plan: the Payload's big brother (strike/payload.rs, whose land reading, crater, felled trees, rubble and
//! thrown blocks this follows, scaled up). A bomb comes in from orbit, a white-hot streak across the sky, sheds its
//! heat, arcs over into a steep dive, faster and faster (NkGeo); it bursts NK_BURST blocks over the land: a
//! blinding white flash, a fireball swelling and rising into a mushroom cloud hundreds of blocks tall, its stem pulled
//! up out of the land, the shockwave racing out over it in a wall of dust, debris and real blocks thrown far round it.
//!
//! The timeline (strike seconds; the sounds arrive late by the distance, 343 blocks a second, as the Payload's): 0
//! fired; NK_SEEN (0.8) the bomb shows, far off and high; NK_COOL (6.0) its heat shed, arcing over into its dive;
//! `nuke.fall` from 1.5 to the burst; NK_HIT (11.0) the burst (the flash is silent); `nuke.ground` as the ground
//! carries the shock (five times the air's speed); `nuke.blast` (or `nuke.blast_far` past ~300 blocks, cross-faded to
//! 900) as the air does, `nuke.shockwave` with it as the front passes the player, `nuke.rumble` 1.5 s after it (30 to
//! 40 s), `nuke.debris` 3 s after it within 700 blocks; the strike ends at 90 s (lasers.rs's length).
//!
//! What it leaves is real blocks: a crater about NK_CRATER_R * 2 (200) across and NK_CRATER_D (40) deep, its walls
//! stepped in terraces and scorched, glazed with greenish glass on its floor, its rim a broken ridge of rock and earth
//! turned over; the land flattened round it out to about NK_FLAT (230; the trees felled and lying pointing away from
//! it), past that out to NK_FLAT + NK_BAND (300) crowns stripped and many trees knocked flat, the grass charred out to
//! about NK_CHAR (290) in streaks, rubble strewn out to NK_RUBBLE (280), mobs and dropped items killed within NK_KILL
//! (300); past that, out to NK_FLASH (480), what faces the fireball scorched by its flash and what is hidden from it
//! left as it was (nk_flash_part). All of it goes in as one wave from the middle out, each ring as the shockwave
//! reaches it or as soon after as the world takes the blocks (Wave, nk_work). Water it cuts goes like any other block
//! (what is left flows in, as round TNT); the lava in the ground it bares sealed; the odd fire far out.
//!
//! shaders/nuke.wgsl draws the bomb, its trail, the flash, the fireball, the mushroom cloud, the shockwave, the dust
//! and the debris from the table `nk_table` hands it (render.set-data). Keep the NK_* here and there in step.
use super::{Act, Blocks, Col, Plan, Rng, TIDY_BORDER, Target, falloff, mh, pk_load_rows, sound_from, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The bomb shows high in the sky, falls faster from NK_TURN, and bursts at NK_HIT, NK_BURST blocks over the target's
/// ground: low, so the fireball meets the land from its first frames (the pass sets it on the heightfield's ground
/// round the target, pl_g0 in nuke.wgsl, and spreads its foot over it, pl_foot).
pub(super) const NK_SEEN: f32 = 0.8;
pub(super) const NK_TURN: f32 = 8.0;
pub(super) const NK_HIT: f32 = 11.0;
pub(super) const NK_BURST: f64 = 12.0;
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
pub(super) const NK_CHUNKS: usize = 8;
pub(super) const NK_SPARKS: usize = 24;

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
const NK_PARTS: i32 = 64;
/// Mobs and dropped items within NK_KILL killed as it bursts.
const NK_KILL: i32 = 300;
/// Real blocks thrown out of the crater as it bursts (nk_thrown).
const NK_THROWN: usize = 160;

/// Where the bomb is and how it moves: everything worked out from the strike's seed and where the player stands. It
/// comes in from orbit: it shows far off beyond the target and to one side as the player looks, a white-hot streak
/// across the sky on a long shallow slant (about 500 blocks a second, slowing hard in the thickening air), sheds its
/// heat (NK_COOL) and arcs over into a steep dive, faster and faster onto the burst point, NK_BURST over the target's
/// ground. The path is laid out from its speed and slope against
/// time, then moved so that it ends on the burst point at NK_HIT.
#[derive(Clone, Debug)]
pub(super) struct NkGeo {
    pub seed: u32,
    /// Where it is every NK_GEO_DT seconds from NK_SEEN (from the target's ground), the last at NK_HIT.
    path: Vec<[f64; 3]>,
    /// The wind (blocks a second, x and z): the trail and the cloud drift with it.
    pub wind: (f64, f64),
}

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
fn len(a: [f64; 3]) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}
fn sstep(a: f64, b: f64, x: f64) -> f64 {
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// The re-entry's heat is shed between NK_COOL - 0.6 and NK_COOL + 1.0 (keep it in step with nuke.wgsl's PL_COOL).
pub(super) const NK_COOL: f32 = 6.0;
const NK_GEO_DT: f64 = 0.005;

impl NkGeo {
    /// `me`: the player from the target's ground point.
    pub fn new(seed: f32, me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |k: u32| mh(k, seed, 0x9b1);
        let d = me[0].hypot(me[2]);
        let u = if d > 1.0 { [me[0] / d, 0.0, me[2] / d] } else { [0.0, 0.0, 1.0] };
        // (it comes from beyond the target and off to one side, 50 to 65 degrees round from straight beyond it, so it
        // crosses the sky as the player looks, coming towards them)
        let side = if r(1) < 0.5 { -1.0 } else { 1.0 };
        let phi = (50.0 + 15.0 * r(2)).to_radians() * side;
        let (c, s) = (phi.cos(), phi.sin());
        let from = [-u[0] * c + u[2] * s, 0.0, -u[2] * c - u[0] * s];
        let wa = TAU * r(9);
        let ws = 2.0 + 2.0 * r(10);
        // (its speed and its slope below the level against time: hypersonic and shallow, slowing harder as the air
        // thickens; then arcing over into a steep dive, gathering speed all the way down)
        let v0 = 410.0 + 60.0 * r(3);
        let g0 = (6.0 + 4.0 * r(4)).to_radians();
        let (seen, cool, hit) = (f64::from(NK_SEEN), f64::from(NK_COOL), f64::from(NK_HIT));
        let speed = |t: f64| {
            let w = ((t - seen) / (cool - seen)).clamp(0.0, 1.0);
            let hyper = v0 - (v0 - 140.0) * w.powf(1.5);
            let dive = 140.0 + 195.0 * ((t - cool) / (hit - cool)).clamp(0.0, 1.0).powf(1.7);
            if t < cool { hyper } else { dive }
        };
        let slope = |t: f64| {
            let w = ((t - seen) / (cool - seen)).clamp(0.0, 1.0);
            let a = g0 + (18f64.to_radians() - g0) * w * w;
            a + (75f64.to_radians() - 18f64.to_radians()) * sstep(cool + 1.2, cool + 3.4, t)
        };
        let n = ((f64::from(NK_HIT) - seen) / NK_GEO_DT).round() as usize;
        let mut path = Vec::with_capacity(n + 1);
        let mut p = [0.0f64; 3];
        path.push(p);
        for i in 0..n {
            let t = seen + NK_GEO_DT * (i as f64 + 0.5);
            let (v, a) = (speed(t), slope(t));
            p = add(p, [-from[0] * a.cos(), -a.sin(), -from[2] * a.cos()], v * NK_GEO_DT);
            path.push(p);
        }
        let shift = add([0.0, NK_BURST, 0.0], p, -1.0);
        for q in &mut path {
            *q = add(*q, shift, 1.0);
        }
        NkGeo { seed, path, wind: (wa.cos() * ws, wa.sin() * ws) }
    }
    /// Where it is at strike time `t` (from the target's ground), from NK_SEEN to NK_HIT: at NK_HIT the burst point.
    pub fn pos(&self, t: f64) -> [f64; 3] {
        if t >= f64::from(NK_HIT) {
            return self.path[self.path.len() - 1];
        }
        let u = ((t - f64::from(NK_SEEN)) / NK_GEO_DT).clamp(0.0, (self.path.len() - 1) as f64);
        let i = (u.floor() as usize).min(self.path.len() - 2);
        let f = u - i as f64;
        add(self.path[i], add(self.path[i + 1], self.path[i], -1.0), f)
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

/// The pieces shed as it comes in through the air (see NK_FR): its heat shield breaking up in the re-entry, a few
/// glowing chunks and a spray of sparks torn off it, slowed at once by the air and falling away behind the streak,
/// burning out (the chunks trailing their own thin smoke); none once it has shed its heat.
pub(super) fn nk_fragments(g: &NkGeo) -> Vec<[f64; 11]> {
    let mut out = Vec::new();
    let vel = |t: f64| {
        let (a, b) = (g.pos(t - 0.02), g.pos(t + 0.02));
        [(b[0] - a[0]) / 0.04, (b[1] - a[1]) / 0.04, (b[2] - a[2]) / 0.04]
    };
    for i in 0..NK_CHUNKS + NK_SPARKS {
        let h = |k: u32| mh(i as u32, g.seed, 0x7a0 + k);
        let spark = i >= NK_CHUNKS;
        let (seen, cool) = (f64::from(NK_SEEN), f64::from(NK_COOL));
        // (from half a second after it shows until it cools, more of them as it slows hardest)
        let t0 = if spark { seen + 0.6 + (cool - seen - 0.4) * h(0).powf(0.8) } else { seen + 1.0 + (cool - seen - 1.4) * h(0).powf(0.7) };
        let p0 = g.pos(t0);
        let v = vel(t0);
        let sp = len(v).max(1.0);
        let dir = [v[0] / sp, v[1] / sp, v[2] / sp];
        // (flung out across its path, a random way round it)
        let a = TAU * h(1);
        let side = {
            let up = if dir[1].abs() > 0.95 { [1.0, 0.0, 0.0] } else { [0.0, 1.0, 0.0] };
            let s1 = [dir[1] * up[2] - dir[2] * up[1], dir[2] * up[0] - dir[0] * up[2], dir[0] * up[1] - dir[1] * up[0]];
            let l1 = len(s1).max(1e-9);
            let s1 = [s1[0] / l1, s1[1] / l1, s1[2] / l1];
            let s2 = [dir[1] * s1[2] - dir[2] * s1[1], dir[2] * s1[0] - dir[0] * s1[2], dir[0] * s1[1] - dir[1] * s1[0]];
            add(add([0.0; 3], s1, a.cos()), s2, a.sin())
        };
        let kick = if spark { 25.0 + 70.0 * h(2) } else { 15.0 + 45.0 * h(2) };
        let keep = if spark { 0.7 + 0.2 * h(3) } else { 0.8 + 0.15 * h(3) };
        let v0 = add(add([0.0; 3], v, keep), side, kick);
        let life = if spark { 0.4 + 0.6 * h(5) } else { 1.2 + 1.2 * h(5) };
        let size = if spark { 1.0 + 1.2 * h(6) } else { 1.3 + 1.0 * h(6) };
        let drag = if spark { 1.6 + 1.2 * h(7) } else { 0.8 + 0.6 * h(7) };
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
    crate::meter::spend(600 * columns.len() as u64);
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
            crate::meter::spend(9_000_000);
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
    /// How many trunks of each wood stand on it (the commonest is the one strewn and thrown).
    woods: [u32; 9],
    /// Every part taken in (the stages that use it wait for it).
    done: bool,
}

fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    crate::meter::spend(30);
    let (i, k) = (x - bx + NK_READ, z - bz + NK_READ);
    if i < 0 || k < 0 || i >= NK_GW || k >= NK_GW {
        return None;
    }
    land.cols.get((k * NK_GW + i) as usize).filter(|c| c.known)
}

/// How far out part `part` of the land's read reaches: the parts are rings from the middle out, as many columns in
/// each (the wave's stages wait only for the rings they reach into).
fn read_reach(part: i32) -> f64 {
    f64::from(NK_READ) * (f64::from(part + 1) / f64::from(NK_PARTS)).sqrt()
}
/// The columns read in part `part`: those of its ring.
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let r1 = read_reach(part).min(f64::from(NK_READ));
    let q0 = if part == 0 { -1.0 } else { read_reach(part - 1).powi(2) };
    let q1 = r1 * r1;
    let n = r1.ceil() as i32;
    let mut out = Vec::new();
    for dz in -n..=n {
        let d = f64::from(dz * dz);
        if d > q1 {
            continue;
        }
        // (the row's run within r1 less its run within r0)
        let wo = (q1 - d).sqrt().floor() as i32;
        let wi = if q0 >= d { (q0 - d).sqrt().floor() as i32 } else { -1 };
        for dx in -wo..=wo {
            let e = d + f64::from(dx * dx);
            if dx.abs() > wi || e > q0 {
                if e > q0 && e <= q1 {
                    out.push((bx + dx, bz + dz));
                }
            }
        }
    }
    crate::meter::spend(60 * out.len() as u64);
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
        crate::meter::spend(600 + 50 * blocks.len() as u64);
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
        if c.trunk > 0 {
            land.woods[c.wood as usize] += 1;
        }
        let (ii, kk) = (x - bx + NK_READ, z - bz + NK_READ);
        if (0..NK_GW).contains(&ii) && (0..NK_GW).contains(&kk) {
            land.cols[(kk * NK_GW + ii) as usize] = c;
        }
    }
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
        crate::meter::spend(500);
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
/// outer (None outside it). (`ra`: its radius and bearing, from `Shape::at`.)
fn band_ra(s: &Shape, (r, a): (f64, f64)) -> Option<f64> {
    let e = r - s.flat(a);
    (0.0..NK_BAND).contains(&e).then(|| 1.0 - e / NK_BAND)
}
fn band(s: &Shape, x: i32, z: i32) -> Option<f64> {
    let (r, a, _) = s.at(x, z);
    band_ra(s, (r, a))
}
/// A tree in the band knocked flat (more of them near the flattened land).
fn knocked_ra(c: &Column, s: &Shape, x: i32, z: i32, ra: (f64, f64)) -> bool {
    c.trunk >= 3 && !c.fluid && band_ra(s, ra).is_some_and(|p| mh((x.wrapping_mul(92_821) ^ z.wrapping_mul(68_917)) as u32, s.seed, 0x91) < 0.75 * p.powf(1.1))
}
fn knocked(c: &Column, s: &Shape, x: i32, z: i32) -> bool {
    let (r, a, _) = s.at(x, z);
    knocked_ra(c, s, x, z, (r, a))
}
/// What the blast makes of column (x, z): Kept, or its new ground's top (`Some`) and whether it was cleared. (`rau`:
/// `Shape::at`'s.)
fn new_ground_at(c: &Column, s: &Shape, x: i32, z: i32, (r, a, u): (f64, f64, f64)) -> Option<i32> {
    if u < 1.0 {
        Some(c.g - bowl(u).round() as i32)
    } else if u < NK_RIM {
        let n = vnoise(f64::from(x), f64::from(z), 4.0, s.seed ^ 0x35);
        Some(c.g + heap(u, n).round() as i32)
    } else if r < s.flat(a) || knocked_ra(c, s, x, z, (r, a)) {
        Some(c.g)
    } else {
        None
    }
}
fn new_ground(c: &Column, s: &Shape, x: i32, z: i32) -> Option<i32> {
    new_ground_at(c, s, x, z, s.at(x, z))
}
/// Water or lava within a column's reach: dig nothing there or next to it.
fn wet_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    // (the nuke's crater is deep: two columns of ground kept between it and any water)
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (1, -1), (-1, 1), (-1, -1)].iter().any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid))
}

// ---- the wave: the land's changes from the middle out ------------------------------------------------------------
/// The blast's changes go into the world as one wave from the middle out, a ring at a time: each ring as the shockwave
/// reaches it, or as soon after as the world takes the blocks the rings inside it change (NK_RATE a second, of what
/// each ring is expected to change: `nk_cost`); the crater first, then its rim, the flattened land and its felled
/// trees, the charred grass, the stripped crowns, and last the flash's scorching out to NK_FLASH.
const NK_RATE: f64 = 350_000.0;
/// The rings (NK_RING wide) are worked out in parts of about NK_ITEM columns, split by angle, never by rows.
const NK_RING: f64 = 4.0;
const NK_ITEM: f64 = 250.0;
/// The flash's rings: wider, in bigger parts (most of its columns change nothing).
const NK_FL_RING: f64 = 8.0;
const NK_FL_ITEM: f64 = 3000.0;
/// What a column at radius r is expected to change (blocks), for the wave's pace.
fn nk_cost(r: f64) -> f64 {
    let u = r / NK_CRATER_R;
    if u < 1.0 {
        bowl(u) + 8.0
    } else if u < NK_RIM {
        heap(u, 0.5) + 8.0
    } else if r < NK_FLAT {
        // (the trees swept off and their crowns tidied: a lot of light for the game to work out again)
        10.0
    } else if r < f64::from(NK_READ) {
        6.0
    } else {
        // (the flash's: few blocks, but its parts are worked out last, and the wave waits for them)
        2.2
    }
}
/// When the wave reaches radius r (a block at a time out to past NK_FLASH).
#[derive(Clone)]
struct Wave(Rc<Vec<f32>>);
impl Wave {
    fn new() -> Self {
        let mut out = Vec::new();
        let mut work = 0.0;
        for r in 0..=NK_FLASH + 16 {
            let rf = f64::from(r);
            let shock = (rf * rf + NK_BURST * NK_BURST).sqrt() / 343.0;
            // (from the moment the shock touches the ground under the burst)
            out.push(NK_HIT + 0.05 + shock.max(NK_BURST / 343.0 + work / NK_RATE) as f32);
            work += TAU * (rf + 0.5) * nk_cost(rf + 0.5);
        }
        Wave(Rc::new(out))
    }
    fn at(&self, r: f64) -> f32 {
        self.0[(r.max(0.0) as usize).min(self.0.len() - 1)]
    }
    /// When the wave has swept the whole of the chunk column holding block column (x, z) (`cx`, `cz` the target's
    /// middle): every edit to a chunk goes in on the one tick, so the game redraws each of its sections once, not
    /// once a ring.
    fn chunk(&self, cx: f64, cz: f64, x: i32, z: i32) -> f32 {
        let (mx, mz) = (f64::from((x >> 4) * 16) + 8.0, f64::from((z >> 4) * 16) + 8.0);
        self.at((mx - cx).hypot(mz - cz) + 11.4)
    }
}
/// A part of a ring: radii r0..r1 from the target's middle, its angles a0 to a0 + da.
#[derive(Clone, Copy, Debug)]
struct Sector {
    r0: f64,
    r1: f64,
    a0: f64,
    da: f64,
    /// How far through its ring's parts it is (0 the first): its edits go in that far between the wave reaching the
    /// ring's inner edge and its outer, so a ring's parts go in over the ticks between, not all in one.
    frac: f64,
}
impl Sector {
    fn when(&self, wave: &Wave) -> f32 {
        let (t0, t1) = (wave.at(self.r0), wave.at(self.r1));
        t0 + (t1 - t0) * self.frac as f32
    }
}
impl Sector {
    fn holds(&self, dx: f64, dz: f64) -> bool {
        let q = dx * dx + dz * dz;
        if q < self.r0 * self.r0 || q >= self.r1 * self.r1 {
            return false;
        }
        self.da >= TAU - 1e-9 || (dz.atan2(dx) - self.a0).rem_euclid(TAU) < self.da
    }
    /// The block columns whose middles lie in it, round (cx, cz); and the box they lie in.
    fn cells(&self, cx: f64, cz: f64) -> (Vec<(i32, i32)>, [i32; 4]) {
        // (its box: the corners and wherever it crosses an axis)
        let (mut x0, mut z0, mut x1, mut z1) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        let mut add = |a: f64, r: f64| {
            let (x, z) = (cx + a.cos() * r, cz + a.sin() * r);
            x0 = x0.min(x);
            z0 = z0.min(z);
            x1 = x1.max(x);
            z1 = z1.max(z);
        };
        let n = 12;
        for k in 0..=n {
            let a = self.a0 + self.da.min(TAU) * f64::from(k) / f64::from(n);
            add(a, self.r0);
            add(a, self.r1);
        }
        let (x0, z0, x1, z1) = ((x0 - 1.0).floor() as i32, (z0 - 1.0).floor() as i32, (x1 + 1.0).ceil() as i32, (z1 + 1.0).ceil() as i32);
        let mut out = Vec::new();
        crate::meter::spend(200 * ((x1 - x0 + 1) as u64) * ((z1 - z0 + 1) as u64));
        let (q0, q1) = (self.r0 * self.r0, self.r1 * self.r1);
        for z in z0..=z1 {
            let dz = f64::from(z) + 0.5 - cz;
            for x in x0..=x1 {
                let dx = f64::from(x) + 0.5 - cx;
                let q = dx * dx + dz * dz;
                if q >= q0 && q < q1 && self.holds(dx, dz) {
                    out.push((x, z));
                }
            }
        }
        (out, [x0, z0, x1, z1])
    }
}
/// The rings from r0 to r1, `w` wide (twice that past the crater), each split by angle into parts of about `item`
/// columns and no more than `arc` blocks along (their seams turned from ring to ring).
fn sectors(r0: f64, r1: f64, w: f64, item: f64, arc: f64) -> Vec<Sector> {
    let mut out = Vec::new();
    let mut r = r0;
    let mut k = 0;
    while r < r1 {
        let w = if r >= NK_CRATER_R { 2.0 * w } else { w };
        // (no ring left thinner than half its width at the end)
        let e = if r + 1.5 * w >= r1 { r1 } else { r + w };
        let n = (PI * (e * e - r * r) / item).ceil().max((TAU * e / arc).ceil()).max(1.0);
        let turn = TAU * (f64::from(k) * 0.618_034).fract();
        for j in 0..n as usize {
            out.push(Sector { r0: r, r1: e, a0: turn + TAU * j as f64 / n, da: if n <= 1.0 { TAU } else { TAU / n }, frac: j as f64 / n });
        }
        r = e;
        k += 1;
    }
    out
}

// ---- the water: only what the crater breaks into, to its own level ----------------------------------------------
/// How far down the ground under column (x, z)'s new floor `top` is opened to its neighbours: down past the lowest of
/// their new floors (each worked out near enough from its ground and how far out it lies), so the water and lava in the
/// ground there are sealed over the whole of the face the crater bares.
fn seal_lo(land: &Land, bx: i32, bz: i32, x: i32, z: i32, top: i32, r: f64, ang: f64, u: f64) -> i32 {
    let rc = if u > 1e-6 { r / u } else { NK_CRATER_R };
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

/// The blast's edits to column (x, z): the crater dug, its rim heaped, the land flattened
/// and charred, the crowns stripped.
fn nk_blast_col(b: &mut Blocks, land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32, cleared: Option<&mut bool>) {
    crate::meter::spend(400);
    let Some(c) = at(land, bx, bz, x, z) else { return };
    let (r, ang, u) = s.at(x, z);
    if r > f64::from(NK_READ) || c.lava {
        return;
    }
    let wet = wet_near(land, bx, bz, x, z);
    let ng = new_ground_at(c, s, x, z, (r, ang, u));
    if let Some(k) = cleared {
        *k = !c.fluid && ng.is_some();
    }
    match ng {
        Some(top) if top < c.g => {
            // the crater: dug, everything over it gone, its new face scorched (two deep near the middle), the water and
            // lava in the ground it bares sealed; where it broke into a body of water at the surface (a lake, a river,
            // the sea) and is joined to it below its level, filled with still water to that level (never higher than
            // the land stood)
            // (water it cuts into goes like any other block: what is left of it flows in, as round a TNT blast)
            b.run(x, z, top + 1, c.top.max(c.g), "minecraft:air");
            // (the lava in the ground it bares sealed: lava pouring in would burn everything)
            let lo = seal_lo(land, bx, bz, x, z, top, r, ang, u);
            b.put(x, z, lo, top - 1, "minecraft:stone", Some("minecraft:lava"), false);
            let d = if u < 0.75 { 1 } else { 0 };
            for y in top - d..=top {
                b.run(x, z, y, y, scorched(x, y, z, u, s.seed));
            }
        }
        Some(top) if top > c.g && !wet && !c.fluid => {
            // the rim: earth heaped on it, what stood there swept off (none heaped in or by the water); right by the
            // crater's edge, what its wall bares sealed
            for y in c.g + 1..=top {
                b.run(x, z, y, y, ejecta(x, y, z, s.seed));
            }
            if c.top > top {
                b.run(x, z, top + 1, c.top, "minecraft:air");
            }
            if u < 1.08 {
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
            if c.leaves != 255
                && let Some(p) = band_ra(s, (r, ang))
                && vnoise(f64::from(x), f64::from(z), 5.0, s.seed ^ 0x93) < 0.25 + 0.75 * p
            {
                let keep = ((f64::from(c.top - c.g)) * (1.0 - (0.35 + 0.8 * p).min(1.0))).floor() as i32;
                b.put(x, z, c.g + 1 + keep, c.top, "minecraft:air", Some(LEAF_NAMES[c.leaves as usize]), false);
            }
        }
    }
}

/// Edits sorted into the ticks they go in at.
#[derive(Default)]
struct Due(std::collections::BTreeMap<i32, Blocks>);
impl Due {
    fn get(&mut self, t: f32) -> &mut Blocks {
        self.0.entry((t / 0.05).ceil() as i32).or_default()
    }
    fn push(self, q: &mut Plan) {
        for (k, b) in self.0 {
            if !b.runs.is_empty() {
                q.ev.push((k as f32 * 0.05, Act::Blocks(Box::new(b))));
            }
        }
    }
}

/// One part of a ring of the blast: its edits as the wave reaches it, what they leave hanging tidied the tick after,
/// and the trees standing in it felled (lying out over the land past it, once the wave has swept that too).
/// How much more than its estimate it cost (1 for land of the usual height: tall forest is dearer).
fn nk_blast_part(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, cache: &mut [u8], wave: &Wave, sec: &Sector) -> f64 {
    let (bx, bz) = (q.bx, q.bz);
    let (cells, [x0, z0, x1, z1]) = sec.cells(s.cx, s.cz);
    let t = sec.when(wave);
    let mut b = Blocks::default();
    // (what each column was made, for the tidying: cleared through or left)
    let gw = (x1 - x0 + 1) as usize;
    let mut grid = vec![false; gw * (z1 - z0 + 1) as usize];
    for &(x, z) in &cells {
        nk_blast_col(&mut b, land, s, bx, bz, x, z, grid.get_mut((z - z0) as usize * gw + (x - x0) as usize));
    }
    // (each chunk's edits on the tick the wave has swept all of it: its sections redrawn once)
    let when = |x: i32, z: i32| wave.chunk(s.cx, s.cz, x, z).max(t);
    for (tc, b) in b.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    // (what is left hanging round what changed: leaves of a tree whose trunk went, plants whose ground went)
    // (well within the flattened land, where every column is cleared through, nothing is left hanging: only by water,
    // lava or a column not read)
    let inner = sec.r1 + f64::from(TIDY_BORDER) + 1.0 < 0.86 * NK_FLAT;
    let need = !inner || grid.iter().zip(0..).any(|(&k, i)| !k && sec.holds(f64::from(x0 + i % gw as i32) + 0.5 - s.cx, f64::from(z0 + i / gw as i32) + 0.5 - s.cz)) || {
        let b = TIDY_BORDER;
        (z0 - b..=z1 + b).any(|z| (x0 - b..=x1 + b).any(|x| at(land, bx, bz, x, z).is_none_or(|c| c.fluid)))
    };
    // (the columns round it, outside it, as the wave leaves them: so nothing is tidied twice; what each is made of
    // worked out once and kept)
    for &(x, z) in &cells {
        let i = ((z - bz + NK_READ) * NK_GW + x - bx + NK_READ) as usize;
        if let Some(k) = cache.get_mut(i) {
            *k = if grid[(z - z0) as usize * gw + (x - x0) as usize] { 1 } else { 2 };
        }
    }
    let tb = if !need { Blocks::default() } else { tidy(x0, z0, x1, z1, 40, -1, |x, z| {
        let (i, k) = (x - bx + NK_READ, z - bz + NK_READ);
        if i < 0 || k < 0 || i >= NK_GW || k >= NK_GW {
            return Col::Kept;
        }
        let ix = (k * NK_GW + i) as usize;
        if cache[ix] == 0 {
            let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            let cleared = match at(land, bx, bz, x, z) {
                Some(c) if c.fluid => false,
                // (well within the flattened land: cleared through, whatever its edge does)
                Some(_) if dx * dx + dz * dz < (0.86 * NK_FLAT).powi(2) => true,
                // (well past it: only a tree knocked flat)
                Some(c) if dx * dx + dz * dz > (1.14 * NK_FLAT).powi(2) && c.trunk < 3 => false,
                Some(c) => new_ground(c, s, x, z).is_some(),
                None => false,
            };
            // (3, 4: what the wave will make of it, not reached yet)
            cache[ix] = if cleared { 3 } else { 4 };
        }
        if cache[ix] == 1 || cache[ix] == 3 { Col::Cleared } else { Col::Kept }
    }) };
    // (what hangs over a column left as it was reaches no higher than what the read saw on it: the runs cut to that, and
    // none where nothing stood over its ground)
    let mut tb = tb;
    tb.runs.retain_mut(|r| {
        // (none over a column the wave has not reached yet: its own part tidies round it)
        let (i, k) = (r.x - bx + NK_READ, r.z - bz + NK_READ);
        if i < 0 || k < 0 || i >= NK_GW || k >= NK_GW || cache[(k * NK_GW + i) as usize] > 2 {
            return false;
        }
        if r.surface.is_none() || r.y != 2 {
            return true;
        }
        match at(land, bx, bz, r.x, r.z) {
            Some(c) if c.trunk == 0 && !c.fluid => {
                let h = c.top - c.g - 2;
                r.height = r.height.min(h.max(0) as u32);
                h > 0
            }
            _ => true,
        }
    });
    // (on the same tick as the chunk's edits, after them: one redraw)
    for (tc, b) in tb.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    let mut due = Due::default();
    nk_fell(&mut due, land, s, used, wave, bx, bz, &cells);
    due.push(q);
    let tall: i32 = cells.iter().filter_map(|&(x, z)| at(land, bx, bz, x, z)).filter(|c| !c.fluid).map(|c| (c.top - c.g).max(0)).sum();
    1.0 + f64::from(tall) / cells.len().max(1) as f64 / 35.0
}

/// The trees standing on `cells` felled, lying on the land pointing away from the blast (their leaves crushed round
/// their crowns, stripped off near it), each put in once the wave has swept the land it lies on.
// (a cheap hash: the standard one costs far more fuel a lookup)
type Used = crate::ground::FxSet<(i32, i32)>;
fn nk_fell(due: &mut Due, land: &Land, s: &Shape, used: &mut Used, wave: &Wave, bx: i32, bz: i32, cells: &[(i32, i32)]) {
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
    for &(x, z) in cells {
        crate::meter::spend(40);
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
        let mut put: Vec<(i32, i32, i32, &'static str)> = Vec::new();
        for n in 1..=want {
            let (lx, lz) = (x + sx * n, z + sz * n);
            if used.contains(&(lx, lz)) {
                break;
            }
            let Some(g2) = lie(lx, lz, gy) else { break };
            put.push((lx, lz, g2 + 1, log));
            used.insert((lx, lz));
            gy = g2;
            last = Some((lx, lz));
        }
        // (the crown crushed round its end, further out where the blast has not stripped it)
        if let (Some((lx, lz)), true) = (last, r > 110.0 && c.leaves != 255) {
            let leaves = LEAVES[c.leaves as usize];
            for (ox, oz) in [(sx, sz), (sz, sx), (-sz, -sx), (sx + sz, sz + sx), (sx - sz, sz - sx)] {
                let (fx, fz) = (lx + ox, lz + oz);
                if used.contains(&(fx, fz)) {
                    continue;
                }
                if let Some(g2) = lie(fx, fz, gy) {
                    put.push((fx, fz, g2 + 1, leaves));
                    used.insert((fx, fz));
                }
            }
        }
        if put.is_empty() {
            continue;
        }
        // (down once the wave has swept the farthest of it, a ring past)
        let far = put.iter().map(|&(px, pz, _, _)| (f64::from(px) + 0.5 - s.cx).hypot(f64::from(pz) + 0.5 - s.cz)).fold(0.0, f64::max);
        let b = due.get(put.iter().map(|&(px, pz, _, _)| wave.chunk(s.cx, s.cz, px, pz)).fold(wave.at(far + NK_RING + 1.0), f32::max) + 0.05);
        for (px, pz, y, m) in put {
            b.run(px, pz, y, y, m);
        }
    }
}

/// The rubble: chunks of the ground thrown out, more near it, landing over a few seconds.
/// Each lands just after the wave has swept where it lands, the nearer sooner.
fn nk_rubble(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, wave: &Wave) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7e57);
    let mut due = Due::default();
    let lands = |r: f64, k: f64| wave.at(r + 2.0 * NK_RING) + (0.2 + 0.3 * k) as f32;
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
    crate::meter::spend(2_400 * 600);
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
        let t = lands(r, rng.next());
        due.get(t).run(x, z, y, y, m);
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
                due.get(t).run(x2, z2, y, y, m);
                used.insert((x2, z2));
            }
        }
    }
    // leaves and broken branches strewn over the outer land and the band, of the wood that grows here
    let woods = land.woods;
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
            due.get(lands(r, rng.next())).run(x, z, y, y, m);
            used.insert((x, z));
        }
    }
    due.push(q);
}

/// Real blocks thrown out of the crater as it is blasted open: the ground that was there (grass and dirt off its top, the
/// stone and tuff under it, now and then a log of the wood growing round it), flung outward and up over the first second
/// and a half, at all speeds, so some come down by the rim and some arc far out over the flattened land. Some land as
/// blocks, the rest break up where they land (CancelDrop); none drops an item.
fn nk_thrown(q: &mut Plan, land: &Land, s: &Shape, wave: &Wave, part: u64) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410 ^ (part << 20));
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let mut n = 0;
    crate::meter::spend(NK_THROWN as u64 * 3 / 2 * 3_000);
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
        // (as the wave digs the crater out there, the middle's first, a few at a time over the next second)
        let t = wave.at(r) + 0.05 + 1.2 * rng.next().powf(1.3) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

// ---- the flash: what faces the fireball past the blast's reach, scorched ---------------------------------------------
/// Past the land the blast knocks over (NK_READ) out to NK_FLASH, what the flash sees is scorched: the leaves facing
/// it burnt off, the wood and planks charred dark, the grass burnt to bare earth, the plants gone, wool blackened,
/// the odd fire lit; what the land, a tree or a wall hides from it is left as it was (the flash's shadows). Read as it
/// starts (NK_FL_PARTS queries, NK_FL_BELOW under each column's top), worked out in parts of its ring after the blast's
/// and put in as the wave reaches them, last of all.
const NK_FLASH: i32 = 480;
const NK_FL_W: i32 = 2 * NK_FLASH + 1;
const NK_FL_PARTS: i32 = 96;
const NK_FL_BELOW: u32 = 30;
/// The line of sight worked out along NK_FL_RAYS rays out from the fireball, in NK_FL_SWEEPS parts; then the edits in
/// parts of its ring.
const NK_FL_RAYS: i32 = 3400;
const NK_FL_SWEEPS: i32 = 48;
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
fn fl_idx(bx: i32, bz: i32, x: i32, z: i32) -> Option<usize> {
    let (i, k) = (x - bx + NK_FLASH, z - bz + NK_FLASH);
    (i >= 0 && k >= 0 && i < NK_FL_W && k < NK_FL_W).then(|| (k * NK_FL_W + i) as usize)
}
/// The ring's columns read in part `part` (a run of rows of it, past NK_READ and within NK_FLASH, about as many columns
/// in each part: some 15,000, half a query's worth at NK_FL_BELOW deep).
fn fl_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    // (each row's run out to the flash's reach less the run within the blast's: the widest dx in each)
    let half = |r: i32, dz: i32| -> i32 {
        let m = r * r - dz * dz;
        if m < 0 {
            return -1;
        }
        let mut w = f64::from(m).sqrt() as i32;
        while w * w > m {
            w -= 1;
        }
        while (w + 1) * (w + 1) <= m {
            w += 1;
        }
        w
    };
    let count = |dz: i32| (2 * half(NK_FLASH, dz) + 1 - (2 * half(NK_READ, dz) + 1).max(0)).max(0) as usize;
    let total: usize = (-NK_FLASH..=NK_FLASH).map(count).sum();
    let per = total.div_ceil(NK_FL_PARTS as usize);
    let mut out = Vec::new();
    let mut seen = 0usize;
    for dz in -NK_FLASH..=NK_FLASH {
        let n = count(dz);
        let k = (seen + n / 2) / per;
        seen += n;
        if k as i32 == part || (part == NK_FL_PARTS - 1 && k as i32 > part) {
            let (wo, wi) = (half(NK_FLASH, dz), half(NK_READ, dz));
            out.extend((-wo..=wo).filter(|&dx| dx.abs() > wi).map(|dx| (bx + dx, bz + dz)));
            crate::meter::spend(60 * (2 * wo + 1) as u64);
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
        crate::meter::spend(600 + 50 * blocks.len() as u64);
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
/// The flash's line of sight along rays j0..j1 out from the fireball: going out along each, the steepest the land and
/// what stands on it rise towards the fireball so far, and so for each column past the blast's reach the lowest of it
/// the fireball sees over them (the land, the trees and the walls between). Waits for the land to be in.
fn nk_flash_sweep(fl: &mut Flash, land: &Land, s: &Shape, bx: i32, bz: i32, gy: i32, j0: i32, j1: i32) {
    let hb = f64::from(gy) + NK_BURST;
    if fl.top.is_empty() {
        return;
    }
    for j in j0..j1 {
        let th = TAU * f64::from(j) / f64::from(NK_FL_RAYS);
        let (ux, uz) = (th.cos(), th.sin());
        // (the steepest slope from the fireball to anything passed so far)
        let mut m = f64::NEG_INFINITY;
        let mut last = (i32::MIN, i32::MIN);
        let mut d = 2.0;
        crate::meter::spend(140 * u64::from(NK_FLASH as u32));
        while d <= f64::from(NK_FLASH) {
            let (x, z) = ((s.cx + ux * d).floor() as i32, (s.cz + uz * d).floor() as i32);
            if (x, z) != last {
                last = (x, z);
                let h = if let Some(c) = at(land, bx, bz, x, z) {
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
/// The flash's scorching over a part of its ring: what lies over the lowest of each column the fireball sees changed,
/// more surely the nearer it is, as the wave reaches it.
fn nk_flash_part(q: &mut Plan, fl: &Flash, s: &Shape, wave: &Wave, sec: &Sector) {
    let (bx, bz) = (q.bx, q.bz);
    let mut b = Blocks::default();
    if fl.top.is_empty() {
        return;
    }
    let (cells, _) = sec.cells(s.cx, s.cz);
    {
        for &(x, z) in &cells {
            crate::meter::spend(120);
            let Some(ix) = fl_idx(bx, bz, x, z) else { continue };
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
            // (all of it near the blast's reach, still more than half at the flash's)
            let p = 1.0 - 0.45 * ((r - f64::from(NK_READ)) / f64::from(NK_FLASH - NK_READ)).powf(1.5);
            let h0 = (x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32;
            let roll = |salt: u32| mh(h0, s.seed, salt);
            for w in 0..9 {
                if m & (1 << w) != 0 && roll(0xf1) < p {
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
        let t = sec.when(wave);
        for (tc, b) in b.split_by(|x, z| wave.chunk(s.cx, s.cz, x, z).max(t)) {
            q.ev.push((tc, Act::Blocks(Box::new(b))));
        }
    }
}

// ---- the land's work: one stage a tick, in order --------------------------------------------------------------------
/// All the land's work is one chain of stages, a tick each, so none of it ever waits behind the rest or queues out of
/// order: the land read (its rings asked from the middle out and taken in as they are answered), the flash's ring read,
/// the blast's parts ring by ring from the middle out, the flash's line of sight and its parts.
/// Each stage does about NK_BUDGET columns' worth (well under a tick's fuel).
const NK_BUDGET: f64 = 1200.0;
/// About what a unit of that work costs in instructions (the game's count of the stages' fuel over their estimates).
const NK_UNIT: f64 = 15_000.0;
enum Job {
    Thrown(u64),
    Rubble,
    Sweep(i32, i32),
    Blast(Sector),
    Flash(Sector),
}
struct Work {
    land: Land,
    fl: Flash,
    s: Shape,
    wave: Wave,
    used: Used,
    /// What the blast made of each column of the land's square (0 not yet known, 1 cleared through, 2 left), for the
    /// tidying.
    made: Vec<u8>,
    gy: i32,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    retry: Option<u32>,
    retried: bool,
    ftags: Vec<u32>,
    fasked: usize,
    ftaken: usize,
    jobs: std::collections::VecDeque<Job>,
    sweeps: usize,
}
impl Work {
    fn new(s: Shape, gy: i32) -> Self {
        let mut jobs = std::collections::VecDeque::new();
        jobs.push_back(Job::Thrown(0));
        jobs.push_back(Job::Thrown(1));
        let per = (NK_FL_RAYS + NK_FL_SWEEPS - 1) / NK_FL_SWEEPS;
        for j in 0..NK_FL_SWEEPS {
            jobs.push_back(Job::Sweep(j * per, ((j + 1) * per).min(NK_FL_RAYS)));
        }
        let mut rubble = false;
        for sec in sectors(0.0, f64::from(NK_READ) + 1.0, NK_RING, NK_ITEM, 150.0) {
            if !rubble && sec.r0 >= NK_CRATER_R * NK_RIM {
                jobs.push_back(Job::Rubble);
                rubble = true;
            }
            jobs.push_back(Job::Blast(sec));
        }
        for sec in sectors(f64::from(NK_READ) + 1.0, f64::from(NK_FLASH) + 1.0, NK_FL_RING, NK_FL_ITEM, 1000.0) {
            jobs.push_back(Job::Flash(sec));
        }
        Work {
            land: Land { cols: vec![Column::default(); (NK_GW * NK_GW) as usize], missing: Vec::new(), woods: [0; 9], done: false },
            fl: Flash { top: Vec::new(), g: Vec::new(), mats: Vec::new(), seen: Vec::new(), parts: 0 },
            s,
            wave: Wave::new(),
            used: Default::default(),
            made: vec![0; (NK_GW * NK_GW) as usize],
            gy,
            tags: (0..NK_PARTS).map(|_| crate::columns::new_tag()).collect(),
            asked: 0,
            taken: 0,
            retry: None,
            retried: false,
            ftags: (0..NK_FL_PARTS).map(|_| crate::columns::new_tag()).collect(),
            fasked: 0,
            ftaken: 0,
            jobs,
            sweeps: NK_FL_SWEEPS as usize,
        }
    }
    /// How far out the land is in (every column within it read).
    fn ready(&self) -> f64 {
        if self.land.done {
            return f64::INFINITY;
        }
        let r = if self.taken == 0 { 0.0 } else { read_reach(self.taken as i32 - 1) };
        let (bx, bz) = (self.s.cx.floor() as i32, self.s.cz.floor() as i32);
        let m = self.land.missing.iter().map(|&(x, z)| f64::from(x - bx).hypot(f64::from(z - bz)) - 1.0).fold(f64::INFINITY, f64::min);
        r.min(m)
    }
    /// Whether job `j` can be done now; and whether the jobs after it must wait for it (the wave's parts go in order).
    fn can(&self, j: &Job) -> (bool, bool) {
        match j {
            Job::Thrown(_) => (self.ready() >= NK_CRATER_R * 1.3, false),
            Job::Rubble => (self.land.done, false),
            Job::Sweep(..) => (self.land.done && self.ftaken >= NK_FL_PARTS as usize, false),
            Job::Blast(sec) => (self.ready() >= sec.r1 + 12.0, true),
            Job::Flash(_) => (self.sweeps == 0, true),
        }
    }
    fn cost(j: &Job) -> f64 {
        match j {
            Job::Thrown(_) => 900.0,
            Job::Rubble => NK_BUDGET,
            Job::Sweep(j0, j1) => 12.0 * f64::from(j1 - j0),
            Job::Blast(s) | Job::Flash(s) => {
                let a = s.da.min(TAU) / 2.0 * (s.r1 * s.r1 - s.r0 * s.r0);
                // (a column's work: the crater's, its rim's, the flattened land's, the band's past it (tidied), the
                // flash's, measured)
                let u = s.r0 / NK_CRATER_R;
                let k = if matches!(j, Job::Flash(_)) {
                    1.0 / 19.0
                } else if u < 1.0 {
                    0.9
                } else if u < NK_RIM {
                    0.6
                } else if s.r1 + 4.0 < 0.86 * NK_FLAT {
                    0.6
                } else {
                    0.75
                };
                a * k
            }
        }
    }
}

/// One stage of the land's work.
fn nk_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        let mut spent = 0.0;
        // the reads: the land's rings one a stage from the middle out, then the flash's ring two at a time
        if wk.asked < wk.tags.len() {
            // (two a stage: the parts are small, so none is much to take in on a tick)
            for _ in 0..2.min(wk.tags.len() - wk.asked) {
                let part = wk.asked;
                q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: NK_BELOW, above: NK_ABOVE }));
                wk.asked += 1;
                spent += 75.0;
            }
        } else {
            for _ in 0..2 {
                if wk.fasked < wk.ftags.len() && wk.fasked < wk.ftaken + 6 {
                    let part = wk.fasked;
                    q.ev.push((now, Act::Read { tag: wk.ftags[part], columns: fl_columns(bx, bz, part as i32), below: NK_FL_BELOW, above: 1 }));
                    wk.fasked += 1;
                    spent += 50.0;
                }
            }
        }
        // their answers taken in as they come (up to four of the land's, one of the flash's)
        for _ in 0..4 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                take_in(&mut wk.land, &a, bx, bz);
                wk.taken += 1;
                spent += 300.0;
            }
        }
        if wk.taken == wk.tags.len() && !wk.land.done {
            // (the columns not loaded yet asked again, once, while there is time)
            if wk.land.missing.is_empty() || wk.retried || now > NK_HIT - 1.0 {
                wk.land.done = true;
            } else if let Some(tag) = wk.retry {
                if let Some(a) = crate::columns::take(tag) {
                    wk.land.missing.clear();
                    take_in(&mut wk.land, &a, bx, bz);
                    wk.land.missing.clear();
                    wk.retried = true;
                    wk.land.done = true;
                }
            } else if now > 1.6 {
                let tag = crate::columns::new_tag();
                q.ev.push((now, Act::Read { tag, columns: wk.land.missing.clone(), below: NK_BELOW, above: NK_ABOVE }));
                wk.retry = Some(tag);
            }
        }
        // (the flash's square made a part a stage as its first answer comes: some megabytes)
        let n = (NK_FL_W * NK_FL_W) as usize;
        if wk.fasked > 0 && wk.fl.seen.is_empty() {
            if wk.fl.top.is_empty() {
                wk.fl.top = vec![i16::MIN; n];
            } else if wk.fl.g.is_empty() {
                wk.fl.g = vec![0; n];
            } else if wk.fl.mats.is_empty() {
                wk.fl.mats = vec![0; n];
            } else {
                wk.fl.seen = vec![i16::MAX; n];
            }
            crate::meter::spend(6 * n as u64);
            spent += 500.0;
        } else {
            for _ in 0..3 {
                if wk.ftaken < wk.fasked
                    && !crate::meter::full()
                    && let Some(a) = crate::columns::take(wk.ftags[wk.ftaken])
                {
                    fl_take_in(&mut wk.fl, &a, bx, bz);
                    wk.fl.parts += 1;
                    wk.ftaken += 1;
                    spent += 130.0;
                }
            }
        }
        // the jobs: the first that can be done (never past one of the wave's parts that cannot yet: they go in order)
        loop {
            let mut pick = None;
            for (i, j) in wk.jobs.iter().enumerate() {
                let (can, blocks) = wk.can(j);
                if can {
                    pick = Some(i);
                    break;
                }
                if blocks {
                    break;
                }
            }
            let Some(i) = pick else { break };
            let c = Work::cost(&wk.jobs[i]);
            // (and none past the tick's mark for its work, whatever the estimates said: `meter`)
            if spent > 0.0 && (spent + c > NK_BUDGET || crate::meter::full()) {
                break;
            }
            spent += c;
            // (what the job is expected to cost, on top of what its loops count: `meter` reads high, not low)
            crate::meter::spend((c * NK_UNIT) as u64);
            let job = wk.jobs.remove(i).unwrap_or(Job::Rubble);
            match job {
                Job::Thrown(part) => nk_thrown(q, &wk.land, &wk.s, &wk.wave, part),
                Job::Rubble => {
                    let wave = wk.wave.clone();
                    nk_rubble(q, &wk.land, &wk.s, &mut wk.used, &wave);
                }
                Job::Sweep(j0, j1) => {
                    nk_flash_sweep(&mut wk.fl, &wk.land, &wk.s, bx, bz, wk.gy, j0, j1);
                    wk.sweeps -= 1;
                }
                Job::Blast(sec) => {
                    let wave = wk.wave.clone();
                    let k = nk_blast_part(q, &wk.land, &wk.s, &mut wk.used, &mut wk.made, &wave, &sec);
                    spent += c * (k - 1.0);
                }
                Job::Flash(sec) => nk_flash_part(q, &wk.fl, &wk.s, &wk.wave, &sec),
            }
        }
        !wk.jobs.is_empty()
    };
    // (and given up long after the burst if the world never answers)
    if more && now < NK_HIT + 12.0 {
        q.later(now + 0.05, move |q| nk_work(q, w, now + 0.05));
    }
}

/// The shockwave's jolt reaching the player at `t`, `fo` as hard: a violent hit (the camera at the game's hardest for
/// some two seconds, kicked again and again), then a heavy shudder dying away over eight or nine. The game's shake tops
/// out at a few degrees, so the pass knocks the picture about on top of it (nuke.wgsl's `pl_jolt`). Some 70 jolts, a
/// few a tick: nothing the tick's work notices.
fn nk_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 2.6);
    // (kicked again and again through the hit: each short, hard, the camera's swing renewed)
    for n in 0..18 {
        let u = n as f32 / 18.0;
        p.shake(t + 0.06 + 0.09 * n as f32, (1.0 - 0.35 * u) * fo, 0.22);
    }
    // (the shudder: a long heavy one under it, and quick heaves in it, slowing and fading)
    p.shake(t + 0.4, 0.8 * fo, 9.0);
    let mut ts = t + 1.7;
    let mut n = 0;
    while ts < t + 9.0 {
        let u = (ts - t - 1.7) / 7.3;
        p.shake(ts, (0.75 * (1.0 - u).powf(1.3) + 0.12) * fo, 0.3);
        ts += 0.12 + 0.1 * u;
        n += 1;
    }
    debug_assert!(n < 60);
}

/// The front's knockback close in (`Act::Shove`): blocks a tick out from the blast and up (a jump's is 0.42: thrown a
/// little over a jump's height, some six blocks back), and past how far none (`strike::knock_share`).
const NK_KNOCK_OUT: f32 = 0.8;
const NK_KNOCK_UP: f32 = 0.55;
const NK_KNOCK_REACH: f32 = 600.0;

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
    p.csound(1.5, "fall", 10.0, 1.0);
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
    nk_jolt(&mut p, arrive, (2.4 / (1.0 + dist / 500.0)).clamp(0.35, 1.0) as f32);
    // (and the front knocks the player back and up: hardest within two hundred, none past six hundred)
    p.ev.push((arrive, Act::Shove { from: [cx, gy + NK_BURST, cz], out: NK_KNOCK_OUT, up: NK_KNOCK_UP, reach: NK_KNOCK_REACH }));
    let mut ts = arrive + 9.0;
    while ts < arrive + 18.0 {
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
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, NK_READ as f64 + 4.0);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((laser.length - 1.0, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        // the land's work, one chain of stages from as it starts: its changes going in from the middle out with the wave
        let shape = Shape { cx, cz, ph: [TAU * mh(1, geo.seed, 0xc1), TAU * mh(2, geo.seed, 0xc1), TAU * mh(3, geo.seed, 0xc1)], seed: geo.seed };
        // (its state made on a stage of its own, not as it fires: the land's square of columns is some megabytes)
        p.later(0.15, move |q| {
            crate::meter::spend(12_000_000);
            let work = Rc::new(RefCell::new(Work::new(shape, by + 1)));
            q.later(0.2, move |q| nk_work(q, work, 0.2));
        });
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
        let f = |x: f64, z: f64| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        // (PL_FLUSH=1: moved so the target's own ground is the target's, as the preview's `flush=1` draws it)
        let f0 = if std::env::var("PL_FLUSH").is_ok_and(|v| v == "1") { f(0.5, 0.5) } else { 0.0 };
        let heights: Vec<Option<f64>> = super::nk_hf_columns(0, 0, reach)
            .iter()
            .map(|&(x, z)| Some(f(f64::from(x) + 0.5, f64::from(z) + 0.5) - f0))
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
    thread_local! {
        /// The land the tests' world answers with: 0 the forest with its pond; 1 the forest over an aquifer (water
        /// in the ground 8 to 14 under it everywhere) with a river 200 off; 2 the forest by the sea (west of x -50,
        /// its surface at 62); 3 the forest with a river through the crater (12 wide at z 75, its surface at 62).
        static LAND: std::cell::Cell<u8> = const { std::cell::Cell::new(0) };
    }
    /// The water standing over column (x, z), if any: its bed and its surface.
    fn water_at(x: i32, z: i32) -> Option<(i32, i32)> {
        match LAND.with(|l| l.get()) {
            0 => pond(x, z).then(|| (ground_h(x, z) - 3, ground_h(x, z))),
            1 => ((z - 197).abs() < 6).then_some((55, 62)),
            2 => (x < -50).then_some((50, 62)),
            4 => Some((40, 62)),
            3 => ((z - 75).abs() < 6).then_some((55, 62)),
            _ => None,
        }
    }
    /// The worst cases for a stage's work (LAND 5 on): 5 deep ocean (water from 20 to 62, deeper than a read sees),
    /// 6 lakes and land in a pattern, 7 mountains (60 high, steep), 8 a dense jungle (every column a tall tree), 9
    /// the forest only half loaded (nothing east of x 150).
    fn worst(land: u8, x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let (below, above) = (below as i32, above as i32);
        let make = |top: i32, f: &dyn Fn(i32) -> &'static str| Some((top, (top - below..top + above).map(f).collect()));
        match land {
            5 => make(62, &|y| if y < 20 { "minecraft:stone" } else if y <= 62 { "minecraft:water" } else { "minecraft:air" }),
            6 => {
                let wet = (f64::from(x) * 0.031).sin() * (f64::from(z) * 0.027).cos() > 0.3;
                if wet {
                    make(62, &|y| if y < 52 { "minecraft:sand" } else if y <= 62 { "minecraft:water" } else { "minecraft:air" })
                } else {
                    make(66, &|y| if y < 66 { "minecraft:dirt" } else if y == 66 { "minecraft:grass_block" } else { "minecraft:air" })
                }
            }
            7 => {
                let g = (100.0 + 60.0 * (f64::from(x) * 0.02).sin() * (f64::from(z) * 0.025).cos()).round() as i32;
                make(g, &move |y| if y < g { "minecraft:stone" } else if y == g { "minecraft:snow_block" } else { "minecraft:air" })
            }
            8 => {
                let g = 70;
                let h = 20 + ((x * 7 + z * 13).rem_euclid(14));
                make(g + h + 3, &move |y| {
                    if y < g {
                        "minecraft:dirt"
                    } else if y == g {
                        "minecraft:grass_block"
                    } else if y <= g + h && (x + z) % 2 == 0 {
                        "minecraft:jungle_log"
                    } else {
                        "minecraft:jungle_leaves"
                    }
                })
            }
            _ => {
                if x > 150 {
                    return None;
                }
                LAND.with(|l| l.set(0));
                let c = column(x, z, below as u32, above as u32);
                LAND.with(|l| l.set(9));
                c
            }
        }
    }
    fn column(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let land = LAND.with(|l| l.get());
        if land >= 5 {
            return worst(land, x, z, below, above);
        }
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
    fn nuke_digs_a_crater_and_fells_the_trees() {
        LAND.with(|l| l.set(0));
        let blocks = played(true);
        assert!(!blocks.is_empty());
        let fills: Vec<String> = blocks.iter().flat_map(|(_, b)| b.as_fills()).collect();
        // nothing that burns or flows is placed (the fire is the flash's, far out); the pond in the crater is too small
        // to matter: no water placed at all
        for f in &fills {
            for bad in ["lava ", "magma", "sand ", "concrete_powder", "water "] {
                assert!(!f.contains(&format!(" minecraft:{bad}")) || f.contains(" replace "), "{f}");
            }
        }
        // the middle dug about NK_CRATER_D deep
        let mid = fills.iter().find(|f| f.starts_with("fill 10 ") && f.contains(" -3 10 ") && f.ends_with("minecraft:air strict")).expect("the middle dug");
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
        // the crown of a felled tree never left in the air: every leaves block at a tree's column cleared
        for x in -100..120 {
            for z in -100..100 {
                if !tree(x, z) {
                    continue;
                }
                let r = (f64::from(x) - 10.0).hypot(f64::from(z) + 3.0);
                if r < 70.0 && water_at(x, z).is_none() {
                    let g = ground_h(x, z);
                    assert!(fills.iter().any(|f| f.starts_with(&format!("fill {x} ")) && f.contains(&format!(" {z} {x} ")) && f.contains("minecraft:air") && f.contains(&format!(" {} {z} ", g + 8))), "tree at {x} {z} left standing");
                }
            }
        }
    }

    #[test]
    fn nuke_crater_digs_water_like_any_block() {
        // (at the sea: the crater cuts into it as into the land, places no water and seals none; only lava is sealed)
        LAND.with(|l| l.set(2));
        let fills: Vec<String> = played(true).iter().flat_map(|(_, b)| b.as_fills()).collect();
        assert!(!fills.iter().any(|f| f.contains("minecraft:water")), "{:?}", fills.iter().find(|f| f.contains("minecraft:water")));
        assert!(fills.iter().any(|f| f.starts_with("fill -60 ") && f.ends_with("minecraft:air strict")), "the sea dug");
        assert!(fills.iter().any(|f| f.ends_with("minecraft:stone replace minecraft:lava strict")));
        LAND.with(|l| l.set(0));
    }

    /// `cargo test --release nuke_no_stage_too_heavy_anywhere -- --ignored --nocapture`, on its own (other tests running
    /// beside it slow every stage down): the timing half of `nuke_land_goes_in_in_order_anywhere`.
    #[test]
    #[ignore]
    fn nuke_no_stage_too_heavy_anywhere() {
        nuke_anywhere(true);
    }
    /// Wherever it strikes, the land's edits go in on time (but in a jungle of tall trees, where they trail the wave a
    /// little) and from the middle out.
    #[test]
    fn nuke_land_goes_in_in_order_anywhere() {
        nuke_anywhere(false);
    }
    fn nuke_anywhere(timed: bool) {
        if timed && cfg!(debug_assertions) {
            return;
        }
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for land in [0u8, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
            LAND.with(|l| l.set(land));
            let mut best: Vec<f64> = Vec::new();
            let mut late_all = 0.0f32;
            for _ in 0..2 {
                let ev = plan(&crate::lasers::NUKE, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
                let p = crate::strike::sim::play(ev, 30.0, &column);
                let late = p.edits.iter().map(|e| e.0 - e.1).fold(0.0f32, f32::max);
                // (each tick's middle further out than the last's, less what lands a moment behind the wave: felled trees, rubble)
                let mut by: std::collections::BTreeMap<i32, Vec<f64>> = Default::default();
                for (t, _, b) in &p.edits {
                    for u in &b.runs {
                        by.entry((t / 0.05).round() as i32).or_default().push((f64::from(u.x) - 10.0).hypot(f64::from(u.z) + 3.0));
                    }
                }
                let mut last = 0.0f64;
                for (k, mut rs) in by {
                    rs.sort_by(f64::total_cmp);
                    let m = rs[rs.len() / 2];
                    if (k as f32) * 0.05 < Wave::new().at(f64::from(NK_FLASH)) {
                        assert!(m >= last - 80.0, "land {land}: tick {k}: {m:.0} after {last:.0}");
                    }
                    last = last.max(m);
                }
                let ms = p.stages.iter().map(|s| s.2).fold(0.0, f64::max);
                eprintln!("LAND {land}: {} stages, edits {late:.2} s late at most, heaviest {ms:.2} ms", p.stages.len());
                late_all = late_all.max(late);
                let ms: Vec<f64> = p.stages.iter().map(|s| s.2).collect();
                best = if best.is_empty() { ms } else { best.iter().zip(&ms).map(|(a, b)| a.min(*b)).collect() };
            }
            let worst = best.iter().copied().fold(0.0, f64::max);
            let mut idx: Vec<usize> = (0..best.len()).collect();
            idx.sort_by(|a, b| best[*b].total_cmp(&best[*a]));
            eprintln!("LAND {land} heaviest: {:?}", idx.iter().take(4).map(|&i| (i, best[i])).collect::<Vec<_>>());
            assert!(!timed || worst < 1.3, "land {land}: a stage took {worst:.2} ms");
            // (a jungle of tall trees over every column is more work than the chain keeps up with the wave: its edits
            // trail it, still in order, by a few seconds)
            assert!(late_all < if land == 8 { 5.0 } else { 0.3 }, "land {land}: an edit {late_all:.2} s late");
        }
        LAND.with(|l| l.set(0));
    }

    #[test]
    fn nuke_land_changes_sweep_out_from_the_middle_with_the_wave() {
        // played as the mod plays it (one stage a tick): nothing changes before the wave reaches it, the wave keeps up
        // (no edit goes in late), and it sweeps out from the middle
        LAND.with(|l| l.set(0));
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(&crate::lasers::NUKE, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
        let p = crate::strike::sim::play(ev, 30.0, &column);
        let wave = Wave::new();
        let mut last = 0.0f64;
        let mut by_tick: std::collections::BTreeMap<i32, Vec<f64>> = Default::default();
        for (t, due, b) in &p.edits {
            assert!(t - due < 0.2, "an edit {:.2} s late", t - due);
            for u in &b.runs {
                let r = (f64::from(u.x) + 0.5 - 10.5).hypot(f64::from(u.z) + 0.5 + 2.5);
                if *t < wave.at(r - 4.0 * NK_RING - 4.0) - 0.06 {
                    let f = b.as_fills()[b.runs.iter().position(|v| std::ptr::eq(v, u)).unwrap()].clone();
                    panic!("at {r:.0} at {t:.2}, before the wave ({:.2}): {f}", wave.at(r));
                }
                by_tick.entry((t / 0.05).round() as i32).or_default().push(r);
            }
        }
        // (the middle of what changes each tick, while the wave runs, further out tick by tick)
        for (k, mut rs) in by_tick.into_iter().filter(|(k, _)| (*k as f32) * 0.05 < wave.at(f64::from(NK_FLASH))) {
            rs.sort_by(f64::total_cmp);
            let m = rs[rs.len() / 2];
            assert!(m >= last - 30.0, "tick {k}: {m:.0} after {last:.0}");
            last = last.max(m);
        }
        assert!(last > 400.0, "{last}");
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
                    assert!(*t > Wave::new().at(f64::from(NK_READ)) && *t < Wave::new().at(f64::from(NK_FLASH) + 16.0) + 0.1, "{t} {f}");
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
            assert!(*t > NK_HIT && *t < Wave::new().at(NK_CRATER_R) + 1.3, "{t}");
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
    /// `cargo test --release nk_wave_profile -- --ignored --nocapture`: the land's edits as the mod plays them out
    /// (one stage a tick): how far out they reach a quarter second at a time, how many blocks, and the latest stage.
    #[test]
    #[ignore]
    fn nk_wave_profile() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(&crate::lasers::NUKE, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
        let p = crate::strike::sim::play(ev, 30.0, &column);
        let mut bins: std::collections::BTreeMap<i32, (u64, usize, f64, f64, Vec<f64>)> = Default::default();
        let mut per_tick: std::collections::BTreeMap<i32, u64> = Default::default();
        let mut all_tick: std::collections::BTreeMap<i32, (u64, u64)> = Default::default();
        let mut late = 0.0f32;
        // (the chunks each quarter second's and each tick's edits touch: a chunk changed is sent whole to the client)
        let mut chunks: std::collections::BTreeMap<i32, std::collections::HashSet<(i32, i32)>> = Default::default();
        let mut tick_chunks: std::collections::BTreeMap<i32, std::collections::HashSet<(i32, i32)>> = Default::default();
        for (t, due, b) in &p.edits {
            late = late.max(t - due);
            for u in &b.runs {
                chunks.entry((t / 0.25) as i32).or_default().insert((u.x >> 4, u.z >> 4));
                tick_chunks.entry((t / 0.05).round() as i32).or_default().insert((u.x >> 4, u.z >> 4));
            }
            let e = bins.entry((t / 0.25) as i32).or_insert((0, 0, f64::MAX, 0.0, Vec::new()));
            for u in &b.runs {
                let r = (f64::from(u.x) - 10.0).hypot(f64::from(u.z) + 3.0);
                if u.only.is_none() && u.surface.is_none() {
                    e.0 += u64::from(u.height);
                }
                e.1 += 1;
                e.2 = e.2.min(r);
                e.3 = e.3.max(r);
                e.4.push(r);
                if u.only.is_none() && u.surface.is_none() {
                    *per_tick.entry((t / 0.05).round() as i32).or_default() += u64::from(u.height);
                }
                let e = all_tick.entry((t / 0.05).round() as i32).or_default();
                e.0 += u64::from(u.height);
                e.1 += 1;
            }
        }
        for (k, (blocks, runs, lo, hi, mut rs)) in bins {
            rs.sort_by(f64::total_cmp);
            let pc = |f: f64| rs[((rs.len() - 1) as f64 * f) as usize];
            let n = chunks.get(&k).map_or(0, |c| c.len());
            println!("{:6.2} s: {blocks:8} blocks {runs:7} runs {n:5} chunks, r {lo:5.0} [{:5.0} {:5.0} {:5.0}] {hi:5.0}", k as f32 * 0.25, pc(0.1), pc(0.5), pc(0.9));
        }
        let worst = p.stages.iter().map(|s| s.1 - s.0).fold(0.0f32, f32::max);
        let heavy = p.stages.iter().map(|s| s.2).fold(0.0f64, f64::max);
        let busiest = per_tick.values().max().copied().unwrap_or(0);
        if std::env::var("NK_BUSY").is_ok() {
            let k = *all_tick.iter().max_by_key(|(_, v)| v.0).unwrap().0;
            let mut by: std::collections::HashMap<String, (u64, u64)> = Default::default();
            for (t, _, b) in &p.edits {
                if (t / 0.05).round() as i32 != k {
                    continue;
                }
                for (u, f) in b.runs.iter().zip(b.as_fills()) {
                    let key = f.split(" run ").last().unwrap().split_whitespace().skip(7).collect::<Vec<_>>().join(" ");
                    let e = by.entry(key).or_default();
                    e.0 += u64::from(u.height);
                    e.1 += 1;
                }
            }
            let mut v: Vec<_> = by.into_iter().collect();
            v.sort_by(|a, b| b.1.0.cmp(&a.1.0));
            println!("BUSY tick {:.2}: {:?}", k as f32 * 0.05, &v[..v.len().min(8)]);
        }
        if std::env::var("NK_STAGES").is_ok() {
            for st in p.stages.iter().take(400) {
                println!("stage due {:6.2} ran {:6.2} {:.3} ms", st.0, st.1, st.2);
            }
        }
        println!("busiest tick {} chunks", tick_chunks.values().map(|c| c.len()).max().unwrap_or(0));
        println!("{} stages, the latest {worst:.2} s late, the heaviest {heavy:.3} ms; edits at most {late:.2} s late; busiest tick {busiest} blocks set (unfiltered), {} blocks touched, {} runs", p.stages.len(), all_tick.values().map(|v| v.0).max().unwrap_or(0), all_tick.values().map(|v| v.1).max().unwrap_or(0));
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
#[cfg(test)]
mod wave_t {
    #[test]
    #[ignore]
    fn nk_wave_times() {
        let w = super::Wave::new();
        for r in [0.0, 25.0, 50.0, 75.0, 100.0, 140.0, 180.0, 230.0, 300.0, 380.0, 480.0] {
            let shock = ((r * r + super::NK_BURST * super::NK_BURST) as f64).sqrt() / 343.0;
            println!("r {r:4}: {:.2} s after the burst (the shock {:.2})", w.at(r) - super::NK_HIT, shock);
        }
    }
}
