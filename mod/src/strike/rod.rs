//! The Rod from God's plan: a tungsten rod dropped from orbit, kinetic, no explosive (strike/nuke.rs, whose land
//! reading, wave, felled trees, rubble and thrown blocks this follows, tightened round a deep punch of a crater). A
//! colossal dark metal rod comes straight down out of the sky onto the target (RdGeo: plumb vertical, a bright star
//! high overhead at first, faster and faster, the last second very fast), radiant: god rays streaming out of it and down
//! round it, a column of light along its path; in silence but for a faint hiss at the very end. It strikes: a blinding
//! radiant burst, the ground rippling out in rings, a narrow jet of molten rock up its path, a short plume of dust and a
//! ring of it racing out over the ground. It stays: driven into the crater's floor, standing upright in its middle,
//! still glowing (RD_ROD_UP: real blocks, left after the strike).
//!
//! The timeline (strike seconds; the sounds arrive late by the distance, 343 blocks a second, as the Nuke's): 0 fired;
//! RD_SEEN (1.0) the rod shows, some 3,000 blocks up; `rod.hiss` from RD_HIT - 1.6, cut dead on the impact; RD_HIT
//! (7.0) the impact (the flash is silent); `rod.ground` as the ground carries the shock (five times the air's speed);
//! `rod.blast` (or `rod.blast_far` past ~250 blocks, cross-faded to 800) as the air does, with the jolt and the
//! knockback; `rod.rumble` 1 s after it, `rod.debris` 2.5 s after it within 500 blocks (and again at 7 s within 350);
//! the strike ends at 60 s (lasers.rs's length).
//!
//! What it leaves is real blocks: a crater about RD_CRATER_R * 2 (120) across and RD_CRATER_D (50) deep, a punch, not a
//! bowl (its walls steep, its floor fractured stone fused into dark glass in patches), the rod standing in its middle
//! (11 wide, RD_ROD_UP over the floor, standing 30 over the land round it, and RD_ROD_DOWN under it: forged polished
//! blackstone banded in gold and chiseled blackstone, a cap of light on its top); its rim a raised ridge of the
//! ground turned over (the deep rock on top, the dirt under it) out to about RD_CRATER_R * RD_RIM (90); the land flattened
//! round it out to about RD_FLAT (200; the trees felled and lying pointing away from it), past that out to RD_FLAT +
//! RD_BAND (240) crowns stripped and some trees knocked flat; the ground dusted with what the crater threw out in rays
//! running out from it, and rubble strewn in the same rays out to RD_RUBBLE (250); mobs and dropped items killed within
//! RD_KILL (200). All of it goes in as one wave from the middle out, each ring as the shockwave reaches it or as soon
//! after as the world takes the blocks (Wave, rd_work). Water it cuts goes like any other block (what is left flows
//! in, as round TNT); the lava in the ground it bares sealed.
//!
//! shaders/rod.wgsl draws the rod, its light (god rays, the column of light, the glare), the burst, the ripple, the jet,
//! the plume, the dust ring and the debris from the table `rd_table` hands it (render.set-data), and the standing rod's
//! glow over its blocks. Keep the RD_* here and there in step.
use super::{Act, Blocks, Col, Plan, Rng, TIDY_BORDER, Target, falloff, mh, pk_load_rows, sound_from, tidy, vnoise};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::f64::consts::PI;
use std::rc::Rc;

const TAU: f64 = 2.0 * PI;
/// The rod shows high in the sky at RD_SEEN and strikes at RD_HIT, on the target's ground (RD_BURST over it: none).
pub(super) const RD_SEEN: f32 = 1.0;
pub(super) const RD_HIT: f32 = 7.0;
/// The descent's sound (`rod.hiss`, tools/sounds_rod.py) starts this long before the impact, cut on it.
const RD_HISS: f32 = 5.8;
pub(super) const RD_BURST: f64 = 0.0;
/// How fast the ground carries the strike's shock (blocks a second): five times the air's.
const RD_GROUND_V: f64 = 5.0 * 343.0;
/// The path's samples (the trail is drawn through them), from RD_SEEN to RD_HIT.
pub(super) const RD_N: usize = 128;
/// The column of dust's height (the pass's own rise curve tops out about here).
pub(super) const RD_HC: f64 = 300.0;
/// The table (render.set-data): words 0..16 the header (samples, first sample's time, their spacing, the wind's x and
/// z, the column's height, 0, 0, the debris' count); from RD_P the path, three words a sample (x, y, z from the
/// target's ground); up to RD_FR.
pub(super) const RD_P: usize = 16;
pub(super) const RD_FR: usize = 560;

/// The crater's mean radius and depth, how far its rim's heap reaches (in its radii), the land flattened and the trees
/// felled out to RD_FLAT, the ground dusted out to RD_CHAR, the rubble strewn out to RD_RUBBLE.
const RD_CRATER_R: f64 = 60.0;
const RD_CRATER_D: f64 = 50.0;
const RD_RIM: f64 = 1.5;
const RD_FLAT: f64 = 200.0;
const RD_CHAR: f64 = 160.0;
const RD_RUBBLE: f64 = 250.0;
/// Past the flattened land, a band this wide where the blast only half did its work: crowns stripped of their leaves,
/// some trees knocked flat.
const RD_BAND: f64 = 40.0;
/// The land read: every column out to RD_READ, RD_BELOW under its top (a tall tree's top down to its ground).
const RD_READ: i32 = 256;
const RD_GW: i32 = 2 * RD_READ + 1;
const RD_BELOW: u32 = 36;
const RD_ABOVE: u32 = 1;
const RD_PARTS: i32 = 48;
/// Mobs and dropped items within RD_KILL killed as it strikes.
const RD_KILL: i32 = 200;
/// Real blocks thrown out of the crater as it strikes (rd_thrown): more than the Nuke's, and higher, in a cone.
const RD_THROWN: usize = 240;
/// The rays the ejecta lie in round the crater (the dusting and the rubble follow them).
const RD_RAYS: f64 = 17.0;
/// The rod left standing in the crater's middle: RD_ROD_UP blocks over its floor (the floor's top at the target's
/// ground less RD_CRATER_D), RD_ROD_DOWN under it, on the columns within RD_ROD_R2 (squared, in blocks) of the target's:
/// a round rod eleven wide, its top 30 over the land round the crater. Keep in step with rod.wgsl's RD_TOP_END, RD_L
/// and RD_R.
const RD_ROD_UP: i32 = 80;
const RD_ROD_DOWN: i32 = 30;
const RD_ROD_R2: i32 = 26;
/// The ring of light round its foot: the columns past the rod out to this (squared).
const RD_ROD_RING2: i32 = 45;

/// Where the rod is: plumb over the target, coming straight down onto it, faster and faster (RD_V0 to RD_V1 blocks a
/// second, most of the gain in the last second: RD_VP), then in its last fraction of a second a last hard burst, up
/// by RD_VB more (RD_VBP: how late it comes) so it slams in. It strikes at RD_HIT whatever the profile.
#[derive(Clone, Debug)]
pub(super) struct RdGeo {
    pub seed: u32,
    /// The way it comes down (straight down), and the wind (blocks a second, x and z): the dust drifts with it.
    dir: [f64; 3],
    pub wind: (f64, f64),
}
const RD_V0: f64 = 250.0;
const RD_V1: f64 = 1600.0;
const RD_VP: f64 = 3.0;
const RD_VB: f64 = 4000.0;
const RD_VBP: f64 = 40.0;

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
#[cfg(test)]
fn len(a: [f64; 3]) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}

impl RdGeo {
    /// `me`: the player from the target's ground point.
    pub fn new(seed: f32, _me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |k: u32| mh(k, seed, 0xb71);
        let dir = [0.0, -1.0, 0.0];
        let wa = TAU * r(9);
        let ws = 1.5 + 2.0 * r(10);
        RdGeo { seed, dir, wind: (wa.cos() * ws, wa.sin() * ws) }
    }
    /// How far it still has to go at strike time `t` (none from RD_HIT on).
    fn left(t: f64) -> f64 {
        let (seen, hit) = (f64::from(RD_SEEN), f64::from(RD_HIT));
        let tl = hit - seen;
        let w = ((t - seen) / tl).clamp(f64::NEG_INFINITY, 1.0);
        // (its speed RD_V0 + (RD_V1 - RD_V0) w^RD_VP + RD_VB w^RD_VBP, w the share of the fall gone)
        let wp = w.max(0.0);
        tl * (RD_V0 * (1.0 - w) + (RD_V1 - RD_V0) * (1.0 - wp.powf(RD_VP + 1.0)) / (RD_VP + 1.0) + RD_VB * (1.0 - wp.powf(RD_VBP + 1.0)) / (RD_VBP + 1.0))
    }
    /// Where it is at strike time `t` (from the target's ground): at RD_HIT the target's ground.
    pub fn pos(&self, t: f64) -> [f64; 3] {
        add([0.0, RD_BURST, 0.0], self.dir, -Self::left(t))
    }
}

/// What the pass reads (see RD_P): worked out on the tick after it fires.
pub(super) fn rd_table(seed: f32, me: [f64; 3]) -> Vec<u32> {
    let g = RdGeo::new(seed, me);
    let mut w = vec![0.0f32; RD_FR];
    let dt = f64::from(RD_HIT - RD_SEEN) / (RD_N - 1) as f64;
    w[0] = RD_N as f32;
    w[1] = RD_SEEN;
    w[2] = dt as f32;
    w[3] = g.wind.0 as f32;
    w[4] = g.wind.1 as f32;
    w[5] = RD_HC as f32;
    for i in 0..RD_N {
        let p = g.pos(f64::from(RD_SEEN) + dt * i as f64);
        for k in 0..3 {
            w[RD_P + 3 * i + k] = p[k] as f32;
        }
    }
    w[8] = RD_DEBRIS as f32;
    w.into_iter().map(f32::to_bits).collect()
}

/// The debris the pass draws (chunks and specks of rock thrown up out of the crater in a cone, falling back round it):
/// from RD_DB, RD_DW words each, worked out once here rather than for every chunk at every pixel: its bearing (x and
/// z), how far out it is torn up, its speed out and up, when it is thrown (after the strike), its size, e^(k t0) (k its
/// drag), its spin. Keep in step with rod.wgsl's pl_chunk.
pub(super) const RD_DB: usize = 10496;
pub(super) const RD_DW: usize = 10;
pub(super) const RD_DEBRIS: usize = 256;
fn rd_debris_words(seed: u32) -> Vec<u32> {
    let mut w = vec![0.0f32; RD_DEBRIS * RD_DW];
    for i in 0..RD_DEBRIS {
        let h = |k: u32| mh(i as u32, seed, k);
        let ang = h(0x301) * TAU;
        let big = h(0x303);
        // (thrown up out of the crater in a steep cone, most of it high, a few low and far; the big ones slower)
        let r0 = 3.0 + 50.0 * h(0x306).sqrt();
        let low = h(0x307) < 0.22;
        let el = if low { 0.45 + 0.35 * h(0x302) } else { 1.0 + 0.42 * h(0x302) };
        let sp = (if low { 70.0 + 60.0 * h(0x304) } else { 45.0 + 70.0 * h(0x304).powf(0.8) }) * (1.0 - 0.3 * big);
        let t0 = r0 / 1500.0 + 0.3 * h(0x305) * h(0x305);
        let row = [ang.cos(), ang.sin(), r0, el.cos() * sp, el.sin() * sp, t0, 0.2 + 1.4 * big * big * big, (0.06 * t0).exp(), 3.0 + 6.0 * h(0x308), 0.0];
        for (k, x) in row.iter().enumerate() {
            w[RD_DW * i + k] = *x as f32;
        }
    }
    w.into_iter().map(f32::to_bits).collect()
}

// ---- the land's shape round it, for the pass: the dust follows it ----------------------------------------------
/// A coarse heightfield of the land round the target, for the pass (the dust and the shockwave hug it, climbing the
/// hills, filling the hollows, thinner in the lee of a ridge): RD_HN x RD_HN cells over a square RD_HF's second word
/// across each way from the target. From RD_HF: the cells a side, that half-width, the lowest and highest ground (from
/// the target's), then from RD_HF + 8 a word a cell: its height in the low 16 bits (an eighth of a block, from 512 under
/// the target's ground), how sheltered it is from the blast by the land between in the next 8 (0 to 255).
pub(super) const RD_HF: usize = 1024;
pub(super) const RD_HN: usize = 96;
/// How far the heightfield reaches round the target, for a player `dme` off.
fn rd_hf_reach(dme: f64) -> f64 {
    (dme * 1.25 + 250.0).clamp(450.0, 1600.0)
}
/// The columns the heightfield is read from (row by row, z then x).
fn rd_hf_columns(bx: i32, bz: i32, reach: f64) -> Vec<(i32, i32)> {
    let n = RD_HN as i32;
    let step = 2.0 * reach / f64::from(n - 1);
    let at = |i: i32| (-reach + step * f64::from(i)).round() as i32;
    (0..n).flat_map(|k| (0..n).map(move |i| (bx + at(i), bz + at(k)))).collect()
}
/// The heightfield's ground (from the target's), from what the world gave (the first air over each column; none where
/// the land was not loaded, the mean of what was there: not the player's height, who may be up a tower or flying), a
/// trunk or a pillar caught in a cell put down to the ground round it.
fn rd_hf_ground(heights: &[Option<f64>], reach: f64, _me: [f64; 3]) -> Vec<f64> {
    let _ = reach;
    let n = RD_HN;
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
fn rd_hf_shelter(h: &[f64], reach: f64, k0: usize, k1: usize) -> Vec<f64> {
    let n = RD_HN;
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
/// The heightfield's words (from RD_HF).
fn rd_hf_pack(h: &[f64], shelter: &[f64], reach: f64) -> Vec<u32> {
    let (lo, hi) = h.iter().fold((f64::MAX, f64::MIN), |(a, b), &x| (a.min(x), b.max(x)));
    let mut w = vec![(RD_HN as f32).to_bits(), (reach as f32).to_bits(), (lo as f32).to_bits(), (hi as f32).to_bits(), 0, 0, 0, 0];
    let q = |x: f64| ((x + 512.0) * 8.0).round().clamp(0.0, 65535.0) as u32;
    let b = |x: f64| (x * 255.0).round().clamp(0.0, 255.0) as u32;
    w.extend(h.iter().zip(shelter).map(|(&g, &s)| q(g) | b(s) << 16));
    w
}
/// All of it at once (the tests, tools/preview).
#[cfg(test)]
fn rd_hf_words(heights: &[Option<f64>], reach: f64, me: [f64; 3]) -> Vec<u32> {
    let h = rd_hf_ground(heights, reach, me);
    let s = rd_hf_shelter(&h, reach, 0, RD_HN);
    rd_hf_pack(&h, &s, reach)
}
/// The heightfield, once the world has answered (asking again a little later until it has, while there is time): its
/// ground on one stage, its shelter on three more (each well under a tick's fuel), then sent.
fn rd_hf_step(q: &mut Plan, tag: u32, columns: Rc<Vec<(i32, i32)>>, reach: f64, me: [f64; 3], gy: i32, at_t: f32) {
    if !crate::ground::ready(tag) {
        if at_t < RD_HIT {
            q.later(at_t + 0.2, move |q| rd_hf_step(q, tag, columns, reach, me, gy, at_t + 0.2));
        }
        return;
    }
    crate::meter::spend(600 * columns.len() as u64);
    let heights: Vec<Option<f64>> = columns
        .iter()
        .map(|&(x, z)| crate::ground::at(x, z).map(|g| f64::from(g + crate::ground::water(x, z).unwrap_or(0) - gy)))
        .collect();
    let h = Rc::new(rd_hf_ground(&heights, reach, me));
    let parts = 3;
    let shelter: Rc<RefCell<Vec<f64>>> = Default::default();
    for j in 0..parts {
        let (h, shelter) = (h.clone(), shelter.clone());
        let t = at_t + 0.05 * (j + 1) as f32;
        q.later(t, move |q| {
            let (k0, k1) = (j * RD_HN / parts, (j + 1) * RD_HN / parts);
            crate::meter::spend(9_000_000);
            shelter.borrow_mut().extend(rd_hf_shelter(&h, reach, k0, k1));
            if j + 1 == parts {
                q.ev.push((t, Act::Words { index: RD_HF as u32, words: rd_hf_pack(&h, &shelter.borrow(), reach) }));
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
    /// The columns of each ring (part) of the read the world had not loaded when it answered, asked again till it has.
    missing: Vec<Vec<(i32, i32)>>,
    /// How many trunks of each wood stand on it (the commonest is the one strewn and thrown).
    woods: [u32; 9],
    /// Every part taken in (the stages that use it wait for it).
    done: bool,
}

fn at(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> Option<&Column> {
    crate::meter::spend(30);
    let (i, k) = (x - bx + RD_READ, z - bz + RD_READ);
    if i < 0 || k < 0 || i >= RD_GW || k >= RD_GW {
        return None;
    }
    land.cols.get((k * RD_GW + i) as usize).filter(|c| c.known)
}

/// How far out part `part` of the land's read reaches: the parts are rings from the middle out, as many columns in
/// each (the wave's stages wait only for the rings they reach into).
fn read_reach(part: i32) -> f64 {
    f64::from(RD_READ) * (f64::from(part + 1) / f64::from(RD_PARTS)).sqrt()
}
/// The columns read in part `part`: those of its ring.
fn read_columns(bx: i32, bz: i32, part: i32) -> Vec<(i32, i32)> {
    let r1 = read_reach(part).min(f64::from(RD_READ));
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
        // (only the ring's own columns gone over, not the whole disc within it: the outer rings' discs are some
        // hundred thousand columns, and two are asked a stage)
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

/// One answer for ring `part` taken in: each column's ground, what stands on it and over it (those not loaded kept to
/// be asked again).
fn take_in(land: &mut Land, a: &crate::columns::Answer, bx: i32, bz: i32, part: usize) {
    let kinds: Vec<(Kind, u8)> = a.palette.iter().map(|n| kind(n)).collect();
    let lavas: Vec<bool> = a.palette.iter().map(|n| n.contains("lava")).collect();
    crate::meter::spend(2_000 + 4_000 * a.palette.len() as u64);
    for (i, &(x, z)) in a.columns.iter().enumerate() {
        let Some((surface, blocks)) = a.column(i) else {
            crate::meter::spend(60);
            land.missing[part].push((x, z));
            continue;
        };
        let base = surface - a.below;
        // (as the game counts it: some 2M a part's answer of 4,400 columns)
        crate::meter::spend(200 + 12 * blocks.len() as u64);
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
        let (ii, kk) = (x - bx + RD_READ, z - bz + RD_READ);
        if (0..RD_GW).contains(&ii) && (0..RD_GW).contains(&kk) {
            land.cols[(kk * RD_GW + ii) as usize] = c;
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
        1.0 + 0.06 * (3.0 * a + self.ph[0]).sin() + 0.04 * (5.0 * a + self.ph[1]).sin() + 0.025 * (9.0 * a + self.ph[2]).sin()
    }
    /// What the blast makes of column (x, z): how far its ground goes down (or up, its rim's heap), whether it is
    /// flattened, and how far out it is (in the crater's radii).
    fn at(&self, x: i32, z: i32) -> (f64, f64, f64) {
        crate::meter::spend(500);
        let (dx, dz) = (f64::from(x) + 0.5 - self.cx, f64::from(z) + 0.5 - self.cz);
        let r = dx.hypot(dz);
        let a = dz.atan2(dx);
        // (its wall rough but not fluted: steep as it is, finer noise on its edge would stand it up in spikes)
        let rc = RD_CRATER_R * self.wob(a) * (0.97 + 0.06 * vnoise(f64::from(x), f64::from(z), 14.0, self.seed ^ 0x31));
        (r, a, r / rc)
    }
    fn flat(&self, a: f64) -> f64 {
        RD_FLAT * (1.0 + 0.08 * (2.0 * a + self.ph[2]).sin() + 0.05 * (7.0 * a + self.ph[0]).sin())
    }
    /// How strongly bearing `a` lies in one of the ejecta's rays (0 to 1: about RD_RAYS of them round it, uneven, each
    /// its own width and reach).
    fn ray(&self, a: f64) -> f64 {
        let k = RD_RAYS / PI;
        let st = vnoise(a.cos() * k, a.sin() * k, 1.0, self.seed ^ 0x73);
        ((st - 0.5) / 0.25).clamp(0.0, 1.0)
    }
}
/// How deep the crater is at u (its radii out): a punch, not a bowl: a broad floor, its walls dropping steeply under the
/// rim.
fn bowl(u: f64) -> f64 {
    if u >= 1.0 {
        return 0.0;
    }
    RD_CRATER_D * (1.0 - u.powi(5)).powf(0.6)
}
/// The rim's heap past the edge (u in crater radii): the ground thrown up and turned over, a ridge some ten high just
/// past the edge, falling away over the next half radius, ragged (`n`, 0 to 1, breaks it up).
fn heap(u: f64, n: f64) -> f64 {
    if u < 1.0 || u > RD_RIM {
        return 0.0;
    }
    let ridge = 9.0 * (-(u - 1.05).powi(2) / 0.004).exp() + 3.5 * (1.0 - (u - 1.0) / (RD_RIM - 1.0));
    ridge * (0.4 + 0.9 * n)
}
/// The crater's floor and walls, hallowed by it: its floor lined in white and gold (quartz in blocks, pillars and carved,
/// calcite, gold and raw gold, veins of glowstone and shroomlight, now and then white or yellow glazed terracotta or
/// amethyst), dark fused rock (obsidian, blackstone, tinted glass) in patches low on the floor round the rod's
/// foot for contrast; up its walls calcite, smooth stone, end stone and quartz bricks, gold in seams, some plain stone.
fn scorched(x: i32, y: i32, z: i32, u: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) + f64::from(y) * 0.37, f64::from(z), 4.0, seed ^ 0x51);
    let m = vnoise(f64::from(x), f64::from(z) - f64::from(y) * 0.5, 2.2, seed ^ 0x52);
    let g = vnoise(f64::from(x), f64::from(z), 3.0, seed ^ 0x53);
    let f = mh((x.wrapping_mul(73_856_093) ^ y.wrapping_mul(19_349_663) ^ z.wrapping_mul(83_492_791)) as u32, seed, 0x54);
    if u < 0.62 {
        if u < 0.4 && g > 0.68 {
            if m > 0.55 { "minecraft:tinted_glass" } else if n > 0.5 { "minecraft:obsidian" } else { "minecraft:blackstone" }
        } else if f < 0.03 {
            if m > 0.5 { "minecraft:glowstone" } else { "minecraft:shroomlight" }
        } else if n > 0.78 {
            if f < 0.3 { "minecraft:raw_gold_block" } else { "minecraft:gold_block" }
        } else if f < 0.05 {
            if n > 0.5 { "minecraft:white_glazed_terracotta" } else { "minecraft:yellow_glazed_terracotta" }
        } else if f < 0.065 {
            "minecraft:amethyst_block"
        } else if m > 0.62 {
            "minecraft:calcite"
        } else if n < 0.25 {
            "minecraft:chiseled_quartz_block"
        } else if m < 0.3 {
            "minecraft:quartz_pillar"
        } else if n > 0.55 {
            "minecraft:smooth_quartz"
        } else {
            "minecraft:quartz_block"
        }
    } else if n > 0.8 && m > 0.45 {
        "minecraft:gold_block"
    } else if f < 0.02 {
        "minecraft:glowstone"
    } else if n > 0.66 {
        "minecraft:quartz_bricks"
    } else if n < 0.2 {
        "minecraft:stone"
    } else if m > 0.68 {
        "minecraft:end_stone"
    } else if m < 0.25 {
        "minecraft:smooth_stone"
    } else {
        "minecraft:calcite"
    }
}
/// The rim's heap: the ground thrown out of the crater and turned over as it landed (an overturned flap), the deep rock
/// on top bleached white by it (calcite, diorite, end stone, flecks of gold), the soil under it; `k`: how far up the
/// heap (0 its foot, 1 its top).
fn ejecta(x: i32, y: i32, z: i32, k: f64, seed: u32) -> &'static str {
    let n = vnoise(f64::from(x) * 1.3 + f64::from(y) * 0.71, f64::from(z) * 1.3, 3.0, seed ^ 0x61);
    let k = k + 0.3 * (n - 0.5);
    if k > 0.62 {
        if n > 0.82 { "minecraft:raw_gold_block" } else if n > 0.6 { "minecraft:calcite" } else if n < 0.3 { "minecraft:end_stone" } else { "minecraft:diorite" }
    } else if k > 0.3 {
        if n > 0.7 { "minecraft:calcite" } else if n > 0.45 { "minecraft:smooth_stone" } else if n < 0.2 { "minecraft:andesite" } else { "minecraft:stone" }
    } else if n < 0.35 {
        "minecraft:rooted_dirt"
    } else if n < 0.6 {
        "minecraft:coarse_dirt"
    } else {
        "minecraft:dirt"
    }
}
/// The grass round it blessed by what the crater threw out: in rays running out from it white and gold (white concrete,
/// calcite, quartz, gold, now and then a glowstone or shroomlight set in the ground, lighting it at night), all over just
/// past the rim; round them, and further out along them, the grass gone pale (pale moss) out to about RD_CHAR (the
/// longest rays further).
fn charred(s: &Shape, x: i32, z: i32, r: f64, a: f64, seed: u32) -> Option<&'static str> {
    let n = vnoise(f64::from(x), f64::from(z), 5.0, seed ^ 0x71);
    let m = vnoise(f64::from(x), f64::from(z), 2.0, seed ^ 0x72);
    let f = mh((x.wrapping_mul(73_856_093) ^ z.wrapping_mul(19_349_663)) as u32, seed, 0x74);
    let ray = s.ray(a);
    let reach = RD_CRATER_R * 1.9 + (RD_CHAR * 1.3 - RD_CRATER_R * 1.9) * ray;
    let k = (1.0 - ((r - RD_CRATER_R * RD_RIM) / (reach - RD_CRATER_R * RD_RIM).max(1.0)).clamp(0.0, 1.0)).powf(0.8);
    let v = 0.6 * n + 0.4 * m;
    let w = k * (0.55 + 0.45 * ray) + 0.08;
    if v < w {
        Some(if f < 0.02 {
            "minecraft:glowstone"
        } else if f < 0.03 {
            "minecraft:shroomlight"
        } else if f < 0.07 {
            "minecraft:gold_block"
        } else if m > 0.66 {
            "minecraft:quartz_block"
        } else if n > 0.62 {
            "minecraft:calcite"
        } else {
            "minecraft:white_concrete"
        })
    } else if v < w + 0.22 && k > 0.0 {
        Some("minecraft:pale_moss_block")
    } else {
        None
    }
}
/// A white flower on the blessed grass (pale moss) now and then, where nothing stands.
fn blessed_flower(x: i32, z: i32, seed: u32) -> Option<&'static str> {
    let f = mh((x.wrapping_mul(19_349_663) ^ z.wrapping_mul(73_856_093)) as u32, seed, 0x75);
    if f < 0.05 {
        Some("minecraft:lily_of_the_valley")
    } else if f < 0.09 {
        Some("minecraft:oxeye_daisy")
    } else {
        None
    }
}

/// How hard the blast still hits column (x, z) in the band past the flattened land: 1 at its inner edge, to 0 at its
/// outer (None outside it). (`ra`: its radius and bearing, from `Shape::at`.)
fn band_ra(s: &Shape, (r, a): (f64, f64)) -> Option<f64> {
    let e = r - s.flat(a);
    (0.0..RD_BAND).contains(&e).then(|| 1.0 - e / RD_BAND)
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
    } else if u < RD_RIM {
        let n = vnoise(f64::from(x), f64::from(z), 8.0, s.seed ^ 0x35);
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
    // (the crater is deep: two columns of ground kept between it and any water)
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (1, -1), (-1, 1), (-1, -1)].iter().any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid))
}

// ---- the wave: the land's changes from the middle out ------------------------------------------------------------
/// The blast's changes go into the world as one wave from the middle out, a ring at a time: each ring as the shockwave
/// reaches it, or as soon after as the world takes the blocks the rings inside it change (RD_RATE a second, of what
/// each ring is expected to change: `rd_cost`); the crater first, then its rim, the flattened land and its felled
/// trees, the dusted grass, the stripped crowns, out to the land read.
const RD_RATE: f64 = 350_000.0;
/// The rings (RD_RING wide) are worked out in parts of about RD_ITEM columns, split by angle, never by rows.
const RD_RING: f64 = 4.0;
const RD_ITEM: f64 = 250.0;
/// What a column at radius r is expected to change (blocks), for the wave's pace.
fn rd_cost(r: f64) -> f64 {
    let u = r / RD_CRATER_R;
    if r < 7.0 {
        // (the rod stands there: all of its height)
        bowl(u) + 8.0 + f64::from(RD_ROD_UP + RD_ROD_DOWN)
    } else if u < 1.0 {
        bowl(u) + 8.0
    } else if u < RD_RIM {
        heap(u, 0.5) + 8.0
    } else if r < RD_FLAT {
        // (the trees swept off and their crowns tidied: a lot of light for the game to work out again)
        10.0
    } else {
        6.0
    }
}
/// When the wave reaches radius r (a block at a time out to past RD_READ).
#[derive(Clone)]
struct Wave(Rc<Vec<f32>>);
impl Wave {
    fn new() -> Self {
        let mut out = Vec::new();
        let mut work = 0.0;
        for r in 0..=RD_READ + 16 {
            let rf = f64::from(r);
            let shock = (rf * rf + RD_BURST * RD_BURST).sqrt() / 343.0;
            // (from the moment it strikes)
            out.push(RD_HIT + 0.05 + shock.max(RD_BURST / 343.0 + work / RD_RATE) as f32);
            work += TAU * (rf + 0.5) * rd_cost(rf + 0.5);
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
        let w = if r >= RD_CRATER_R { 2.0 * w } else { w };
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
    let rc = if u > 1e-6 { r / u } else { RD_CRATER_R };
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
fn rd_blast_col(b: &mut Blocks, land: &Land, s: &Shape, bx: i32, bz: i32, x: i32, z: i32, cleared: Option<&mut bool>) {
    crate::meter::spend(400);
    let Some(c) = at(land, bx, bz, x, z) else { return };
    let (r, ang, u) = s.at(x, z);
    if r > f64::from(RD_READ) || c.lava {
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
            let d = if u < 0.62 { 1 } else { 0 };
            for y in top - d..=top {
                b.run(x, z, y, y, scorched(x, y, z, u, s.seed));
            }
            rd_rod_col(b, land, bx, bz, x, z);
        }
        Some(top) if top > c.g && !wet && !c.fluid => {
            // the rim: earth heaped on it, what stood there swept off (none heaped in or by the water); right by the
            // crater's edge, what its wall bares sealed
            let hk = f64::from((top - c.g).max(1));
            for y in c.g + 1..=top {
                b.run(x, z, y, y, ejecta(x, y, z, f64::from(y - c.g) / hk, s.seed));
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
                && let Some(m) = charred(s, x, z, r, ang, s.seed)
            {
                b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                if m == "minecraft:pale_moss_block"
                    && let Some(fl) = blessed_flower(x, z, s.seed)
                {
                    b.put(x, z, c.g + 1, c.g + 1, fl, Some("minecraft:air"), false);
                }
            }
        }
        None => {
            if c.ground == 1
                && let Some(m) = charred(s, x, z, r, ang, s.seed)
            {
                b.put(x, z, c.g, c.g, m, Some("minecraft:grass_block"), false);
                if m == "minecraft:pale_moss_block"
                    && let Some(fl) = blessed_flower(x, z, s.seed)
                {
                    b.put(x, z, c.g + 1, c.g + 1, fl, Some("minecraft:air"), false);
                }
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

/// The rod, where column (x, z) is one of its own: driven into the crater's middle, standing upright from RD_ROD_DOWN
/// under its floor to RD_ROD_UP over it (the floor's depth at the target's own column, so it stands straight on any
/// land; within the world's height): a forged rod of polished blackstone, its outside banded every so often in gold
/// and in chiseled blackstone, a collar of gold low on it and two bands of gold round its top, capped with light
/// (froglight in the middle, gold round it); round its foot a ring of glowstone and shroomlight set in the floor.
fn rd_rod_col(b: &mut Blocks, land: &Land, bx: i32, bz: i32, x: i32, z: i32) {
    let (dx, dz) = (x - bx, z - bz);
    let d2 = dx * dx + dz * dz;
    if d2 > RD_ROD_RING2 {
        return;
    }
    let Some(g) = at(land, bx, bz, bx, bz).map(|c| c.g) else { return };
    let floor = g - RD_CRATER_D as i32;
    if d2 > RD_ROD_R2 {
        // (a ring of light round its foot, set in the floor)
        b.run(x, z, floor, floor, if (dx + dz).rem_euclid(2) == 0 { "minecraft:glowstone" } else { "minecraft:shroomlight" });
        return;
    }
    let lo = (floor - RD_ROD_DOWN).max(-63);
    let top = (floor + RD_ROD_UP).min(318);
    b.run(x, z, lo, top - 1, "minecraft:polished_blackstone");
    // (its bands only on its outside, where they show)
    if d2 >= 17 {
        let mut y = floor + 4;
        while y < top - 8 {
            let k = (y - floor) / 9;
            b.run(x, z, y, y, if k % 3 == 1 { "minecraft:gold_block" } else { "minecraft:chiseled_polished_blackstone" });
            y += 9;
        }
        b.run(x, z, floor + 1, floor + 2, "minecraft:gold_block");
        for y in [top - 2, top - 5] {
            b.run(x, z, y, y, "minecraft:gold_block");
        }
    }
    b.run(x, z, top, top, if d2 <= 10 { "minecraft:ochre_froglight" } else { "minecraft:gold_block" });
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
fn rd_blast_part(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, cache: &mut [u8], wave: &Wave, sec: &Sector) -> f64 {
    let (bx, bz) = (q.bx, q.bz);
    let (cells, [x0, z0, x1, z1]) = sec.cells(s.cx, s.cz);
    let t = sec.when(wave);
    let mut b = Blocks::default();
    // (what each column was made, for the tidying: cleared through or left)
    let gw = (x1 - x0 + 1) as usize;
    let mut grid = vec![false; gw * (z1 - z0 + 1) as usize];
    for &(x, z) in &cells {
        rd_blast_col(&mut b, land, s, bx, bz, x, z, grid.get_mut((z - z0) as usize * gw + (x - x0) as usize));
    }
    // (each chunk's edits on the tick the wave has swept all of it: its sections redrawn once)
    let when = |x: i32, z: i32| wave.chunk(s.cx, s.cz, x, z).max(t);
    for (tc, b) in b.split_by(when) {
        q.ev.push((tc, Act::Blocks(Box::new(b))));
    }
    // (what is left hanging round what changed: leaves of a tree whose trunk went, plants whose ground went)
    // (well within the flattened land, where every column is cleared through, nothing is left hanging: only by water,
    // lava or a column not read)
    let inner = sec.r1 + f64::from(TIDY_BORDER) + 1.0 < 0.86 * RD_FLAT;
    let need = !inner || grid.iter().zip(0..).any(|(&k, i)| !k && sec.holds(f64::from(x0 + i % gw as i32) + 0.5 - s.cx, f64::from(z0 + i / gw as i32) + 0.5 - s.cz)) || {
        let b = TIDY_BORDER;
        (z0 - b..=z1 + b).any(|z| (x0 - b..=x1 + b).any(|x| at(land, bx, bz, x, z).is_none_or(|c| c.fluid)))
    };
    // (the columns round it, outside it, as the wave leaves them: so nothing is tidied twice; what each is made of
    // worked out once and kept)
    for &(x, z) in &cells {
        let i = ((z - bz + RD_READ) * RD_GW + x - bx + RD_READ) as usize;
        if let Some(k) = cache.get_mut(i) {
            *k = if grid[(z - z0) as usize * gw + (x - x0) as usize] { 1 } else { 2 };
        }
    }
    let tb = if !need { Blocks::default() } else { tidy(x0, z0, x1, z1, 40, -1, |x, z| {
        let (i, k) = (x - bx + RD_READ, z - bz + RD_READ);
        if i < 0 || k < 0 || i >= RD_GW || k >= RD_GW {
            return Col::Kept;
        }
        let ix = (k * RD_GW + i) as usize;
        if cache[ix] == 0 {
            let (dx, dz) = (f64::from(x) + 0.5 - s.cx, f64::from(z) + 0.5 - s.cz);
            let cleared = match at(land, bx, bz, x, z) {
                Some(c) if c.fluid => false,
                // (well within the flattened land: cleared through, whatever its edge does)
                Some(_) if dx * dx + dz * dz < (0.86 * RD_FLAT).powi(2) => true,
                // (well past it: only a tree knocked flat)
                Some(c) if dx * dx + dz * dz > (1.14 * RD_FLAT).powi(2) && c.trunk < 3 => false,
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
        let (i, k) = (r.x - bx + RD_READ, r.z - bz + RD_READ);
        if i < 0 || k < 0 || i >= RD_GW || k >= RD_GW || cache[(k * RD_GW + i) as usize] > 2 {
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
    rd_fell(&mut due, land, s, used, wave, bx, bz, &cells);
    due.push(q);
    let tall: i32 = cells.iter().filter_map(|&(x, z)| at(land, bx, bz, x, z)).filter(|c| !c.fluid).map(|c| (c.top - c.g).max(0)).sum();
    1.0 + f64::from(tall) / cells.len().max(1) as f64 / 35.0
}

/// The trees standing on `cells` felled, lying on the land pointing away from the blast (their leaves crushed round
/// their crowns, stripped off near it), each put in once the wave has swept the land it lies on.
// (a cheap hash: the standard one costs far more fuel a lookup)
type Used = crate::ground::FxSet<(i32, i32)>;
fn rd_fell(due: &mut Due, land: &Land, s: &Shape, used: &mut Used, wave: &Wave, bx: i32, bz: i32, cells: &[(i32, i32)]) {
    // (a column a log may lie on: flattened, not the crater or its rim, dry, its ground near the last one's)
    let lie = |x: i32, z: i32, gy: i32| -> Option<i32> {
        let c = at(land, bx, bz, x, z)?;
        let (r, a, u) = s.at(x, z);
        if c.fluid || u < RD_RIM || (c.g - gy).abs() > 1 || wet_near(land, bx, bz, x, z) {
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
        if u < RD_RIM || (r > s.flat(a) - 1.0 && !knocked(c, s, x, z)) {
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
        let b = due.get(put.iter().map(|&(px, pz, _, _)| wave.chunk(s.cx, s.cz, px, pz)).fold(wave.at(far + RD_RING + 1.0), f32::max) + 0.05);
        for (px, pz, y, m) in put {
            b.run(px, pz, y, y, m);
        }
    }
}

/// The rubble: chunks of the ground thrown out, more near it, landing over a few seconds.
/// Each lands just after the wave has swept where it lands, the nearer sooner.
fn rd_rubble(q: &mut Plan, land: &Land, s: &Shape, used: &mut Used, wave: &Wave) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7e57);
    let mut due = Due::default();
    let lands = |r: f64, k: f64| wave.at(r + 2.0 * RD_RING) + (0.2 + 0.3 * k) as f32;
    // (white and gold: what the crater's lining threw out, now and then a light)
    const RUBBLE: [&str; 12] = [
        "minecraft:calcite",
        "minecraft:calcite",
        "minecraft:quartz_block",
        "minecraft:smooth_quartz",
        "minecraft:white_concrete",
        "minecraft:end_stone",
        "minecraft:diorite",
        "minecraft:cobblestone",
        "minecraft:stone",
        "minecraft:raw_gold_block",
        "minecraft:gold_block",
        "minecraft:glowstone",
    ];
    crate::meter::spend(2_400 * 1100);
    for _ in 0..2200 {
        // (in rays out from the crater: all round it near the rim, further out only along them, the longest out to
        // RD_RUBBLE)
        let r = RD_CRATER_R * 1.05 + (RD_RUBBLE - RD_CRATER_R * 1.05) * rng.next().powf(1.5);
        let a = rng.uniform(0.0, TAU);
        let ray = s.ray(a);
        let reach = RD_CRATER_R * 2.0 + (RD_RUBBLE - RD_CRATER_R * 2.0) * ray;
        if r > RD_CRATER_R * 1.8 && (r > reach || rng.next() > 0.1 + 0.9 * ray) {
            continue;
        }
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
            let r = RD_CRATER_R * 1.45 + (RD_FLAT * 1.1 + RD_BAND - RD_CRATER_R * 1.45) * rng.next().powf(0.8);
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
fn rd_thrown(q: &mut Plan, land: &Land, s: &Shape, wave: &Wave, part: u64) {
    let (bx, bz) = (q.bx, q.bz);
    let mut rng = Rng::new(u64::from(s.seed) ^ 0x7410 ^ (part << 20));
    let woods = land.woods;
    let wood = (0..9).max_by_key(|&i| woods[i]).filter(|&i| woods[i] > 0);
    let mut n = 0;
    crate::meter::spend(RD_THROWN as u64 * 3 / 2 * 3_000);
    for _ in 0..RD_THROWN * 3 / 2 {
        if n >= RD_THROWN / 2 {
            break;
        }
        // (from anywhere in the crater, more from its middle)
        // (none from round the rod, to come down on it)
        let r = 14.0 + (RD_CRATER_R * 0.85 - 14.0) * rng.next().sqrt();
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
            (_, d) if d < 0.8 => "minecraft:calcite",
            (_, d) if d < 0.87 => "minecraft:quartz_block",
            (_, d) if d < 0.92 => "minecraft:stone",
            (_, d) if d < 0.96 => "minecraft:raw_gold_block",
            _ => "minecraft:cobblestone",
        };
        // (outward from the middle (straight up near it, leaning out further off), at speeds from a lob that lands by
        // the rim to a hard throw that comes down a hundred blocks off; blocks a tick)
        let ang = if r > 1.0 { a } else { rng.uniform(0.0, TAU) };
        // (the rod's: thrown up in a steep cone, higher than the Nuke's and less far)
        let h = 0.3 + 1.6 * rng.next().powf(1.3);
        let vy = 2.0 + 2.6 * rng.next();
        let (vx, vz) = (ang.cos() * h, ang.sin() * h);
        let y = f64::from(c.g) + 1.2 + 2.5 * rng.next();
        // (as the wave digs the crater out there, the middle's first, a few at a time over the next second)
        let t = wave.at(r) + 0.05 + 0.6 * rng.next().powf(1.5) as f32;
        let keep = if rng.next() < 0.45 { "" } else { ",CancelDrop:1b" };
        q.ev.push((t, Act::Cmd(format!("summon minecraft:falling_block {x:.2} {y:.2} {z:.2} {{BlockState:{{Name:\"{blk}\"}},Time:1,DropItem:0b{keep},Motion:[{vx:.3}d,{vy:.3}d,{vz:.3}d]}}"))));
        n += 1;
    }
}

// ---- the land's work: one stage a tick, in order --------------------------------------------------------------------
/// All the land's work is one chain of stages, a tick each, so none of it ever waits behind the rest or queues out of
/// order: the land read (its rings asked from the middle out and taken in as they are answered), then the blast's parts
/// ring by ring from the middle out.
/// Each stage does about RD_BUDGET columns' worth (well under a tick's fuel).
const RD_BUDGET: f64 = 1200.0;
/// About what a unit of that work costs in instructions (the game's count of the stages' fuel over their estimates).
const RD_UNIT: f64 = 15_000.0;
/// How long the land's work waits for columns the world has not loaded (a target far off, its chunks forceloaded and
/// generated as the strike goes on) before it leaves them out: some 35 s after the burst.
const RD_LAND_BY: f32 = RD_HIT + 30.0;
/// How long, once the crater's land is in, it waits for more of the rest to come.
const RD_PATIENCE: f32 = 4.0;
enum Job {
    Thrown(u64),
    Rubble,
    Blast(Sector),
}
struct Work {
    land: Land,
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
    /// The ring of unloaded columns asked again (one at a time, the rings in turn): its tag, ring, columns and when.
    retry: Option<(u32, usize, Vec<(i32, i32)>, f32)>,
    /// The ring to ask again next, and when.
    rnext: usize,
    rat: f32,
    /// Columns not loaded at the last stage, and when last some came.
    left: usize,
    came: f32,
    jobs: std::collections::VecDeque<Job>,
}
impl Work {
    fn new(s: Shape, gy: i32) -> Self {
        let mut jobs = std::collections::VecDeque::new();
        jobs.push_back(Job::Thrown(0));
        jobs.push_back(Job::Thrown(1));
        let mut rubble = false;
        for sec in sectors(0.0, f64::from(RD_READ) + 1.0, RD_RING, RD_ITEM, 150.0) {
            if !rubble && sec.r0 >= RD_CRATER_R * RD_RIM {
                jobs.push_back(Job::Rubble);
                rubble = true;
            }
            jobs.push_back(Job::Blast(sec));
        }
        Work {
            land: Land { cols: vec![Column::default(); (RD_GW * RD_GW) as usize], missing: vec![Vec::new(); RD_PARTS as usize], woods: [0; 9], done: false },
            s,
            wave: Wave::new(),
            used: Default::default(),
            made: vec![0; (RD_GW * RD_GW) as usize],
            gy,
            tags: (0..RD_PARTS).map(|_| crate::columns::new_tag()).collect(),
            asked: 0,
            taken: 0,
            retry: None,
            rnext: 0,
            rat: 0.0,
            left: usize::MAX,
            came: 0.0,
            jobs,
        }
    }
    /// How far out the land is in (every column within it read): out to the rings taken in, short of the first ring
    /// with columns the world had not loaded (those asked again, and the ring being asked). A few dozen steps however
    /// much is missing: it is asked again for each job each stage.
    fn ready(&self) -> f64 {
        if self.land.done {
            return f64::INFINITY;
        }
        crate::meter::spend(400);
        let r = if self.taken == 0 { 0.0 } else { read_reach(self.taken as i32 - 1) };
        let mut first = self.land.missing.iter().position(|m| !m.is_empty()).unwrap_or(usize::MAX);
        if let Some((_, part, _, _)) = &self.retry {
            first = first.min(*part);
        }
        if first == usize::MAX {
            return r;
        }
        let inner = if first == 0 { 0.0 } else { read_reach(first as i32 - 1) };
        r.min(inner - 1.0)
    }
    /// Columns still not loaded.
    fn unloaded(&self) -> usize {
        self.land.missing.iter().map(Vec::len).sum::<usize>() + self.retry.as_ref().map_or(0, |r| r.2.len())
    }
    /// Whether job `j` can be done now; and whether the jobs after it must wait for it (the wave's parts go in order).
    fn can(&self, j: &Job) -> (bool, bool) {
        match j {
            Job::Thrown(_) => (self.ready() >= RD_CRATER_R * 1.3, false),
            Job::Rubble => (self.land.done, false),
            Job::Blast(sec) => (self.ready() >= sec.r1 + 12.0, true),
        }
    }
    fn cost(j: &Job) -> f64 {
        match j {
            Job::Thrown(_) => 900.0,
            Job::Rubble => RD_BUDGET,
            Job::Blast(s) => {
                let a = s.da.min(TAU) / 2.0 * (s.r1 * s.r1 - s.r0 * s.r0);
                // (a column's work: the crater's, its rim's, the flattened land's, the band's past it (tidied), the
                // measured)
                let u = s.r0 / RD_CRATER_R;
                let k = if u < 1.0 {
                    0.9
                } else if u < RD_RIM {
                    0.6
                } else if s.r1 + 4.0 < 0.86 * RD_FLAT {
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
fn rd_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f32) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        let (bx, bz) = (q.bx, q.bz);
        let mut spent = 0.0;
        // the reads: the land's rings two a stage from the middle out
        if wk.asked < wk.tags.len() {
            // (two a stage: the parts are small, so none is much to take in on a tick)
            for _ in 0..2.min(wk.tags.len() - wk.asked) {
                let part = wk.asked;
                q.ev.push((now, Act::Read { tag: wk.tags[part], columns: read_columns(bx, bz, part as i32), below: RD_BELOW, above: RD_ABOVE }));
                wk.asked += 1;
                spent += 75.0;
            }
        }
        // their answers taken in as they come (up to four a stage)
        // (their take-in counts high: the game's count of its fuel is a fraction of the meter's)
        for _ in 0..4 {
            if wk.taken < wk.asked
                && !crate::meter::full()
                && let Some(a) = crate::columns::take(wk.tags[wk.taken])
            {
                let part = wk.taken;
                take_in(&mut wk.land, &a, bx, bz, part);
                if part == 0 {
                    // (the burst's ground from the land read, not from where the designator's ray met it: far off that is
                    // the far terrain's rough copy of it)
                    if let Some(c) = wk.land.cols.get((RD_READ * RD_GW + RD_READ) as usize).filter(|c| c.known) {
                        wk.gy = if c.fluid { c.wtop } else { c.g } + 1;
                    }
                }
                wk.taken += 1;
                spent += 300.0;
            }
        }
        if wk.taken == wk.tags.len() && !wk.land.done {
            // (the columns the world had not loaded yet, as at a target far off in the far terrain, its chunks only
            // forceloaded as the strike began: asked again a ring at a time, the rings in turn, until it has, and the
            // land's work waits for them (parked: a few steps a stage), its changes going in late as they come; given up
            // on long after the burst)
            if let Some((tag, part, _, since)) = &wk.retry {
                let (tag, part, since) = (*tag, *part, *since);
                if let Some(a) = crate::columns::take(tag) {
                    take_in(&mut wk.land, &a, bx, bz, part);
                    wk.retry = None;
                    spent += 300.0;
                } else if now > since + 3.0 {
                    // (the answer lost: its columns asked again later)
                    if let Some((_, part, cols, _)) = wk.retry.take() {
                        wk.land.missing[part] = cols;
                    }
                }
            }
            let left = wk.unloaded();
            if left < wk.left && wk.left != usize::MAX {
                wk.came = now;
            }
            wk.left = left;
            // (the crater's land in and nothing more coming for a while, as land that will not load past the edge of
            // what the world has: the rest left out, not the whole of the land held back for it)
            let stalled = now - wk.came > RD_PATIENCE && wk.ready() >= RD_CRATER_R * 1.3;
            if left == 0 {
                wk.land.done = true;
            } else if now > RD_LAND_BY || stalled {
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("rod: {left} columns of the land never loaded; the terrain left out there"));
                wk.land.done = true;
            } else if wk.retry.is_none() && now >= wk.rat {
                let n = wk.land.missing.len();
                if let Some(part) = (0..n).map(|j| (wk.rnext + j) % n).find(|&j| !wk.land.missing[j].is_empty()) {
                    let cols = std::mem::take(&mut wk.land.missing[part]);
                    crate::meter::spend(40 * cols.len() as u64);
                    let tag = crate::columns::new_tag();
                    q.ev.push((now, Act::Read { tag, columns: cols.clone(), below: RD_BELOW, above: RD_ABOVE }));
                    wk.retry = Some((tag, part, cols, now));
                    wk.rnext = part + 1;
                    // (the next a little later: the world given time to load them)
                    wk.rat = now + 0.1;
                    spent += 150.0;
                }
            }
        }
        crate::trace("rd land taken");
        // the jobs: the first that can be done (never past one of the wave's parts that cannot yet: they go in order)
        loop {
            let mut pick = None;
            for (i, j) in wk.jobs.iter().enumerate() {
                crate::meter::spend(300);
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
            if spent > 0.0 && (spent + c > RD_BUDGET || crate::meter::full()) {
                break;
            }
            spent += c;
            // (what the job is expected to cost, on top of what its loops count: `meter` reads high, not low)
            crate::meter::spend((c * RD_UNIT) as u64);
            let job = wk.jobs.remove(i).unwrap_or(Job::Rubble);
            let job_kind = match &job { Job::Thrown(_) => 0, Job::Rubble => 1, Job::Blast(_) => 2 };
            match job {
                Job::Thrown(part) => rd_thrown(q, &wk.land, &wk.s, &wk.wave, part),
                Job::Rubble => {
                    let wave = wk.wave.clone();
                    rd_rubble(q, &wk.land, &wk.s, &mut wk.used, &wave);
                }
                Job::Blast(sec) => {
                    let wave = wk.wave.clone();
                    let k = rd_blast_part(q, &wk.land, &wk.s, &mut wk.used, &mut wk.made, &wave, &sec);
                    spent += c * (k - 1.0);
                }
            }
            crate::trace(match &job_kind { 0 => "rd thrown", 1 => "rd rubble", _ => "rd blast" });
        }
        !wk.jobs.is_empty()
    };
    // (and given up long after the burst if the world never answers: the land's changes may go in this late, a target
    // far off loading slowly)
    if more && now < RD_LAND_BY + 25.0 {
        q.later(now + 0.05, move |q| rd_work(q, w, now + 0.05));
    }
}

/// The shockwave's jolt reaching the player at `t`, `fo` as hard: a violent, sharp hit (the camera at the game's
/// hardest for a second and a half, kicked again and again), then a shudder dying away over five or six seconds:
/// sharper and shorter than the Nuke's. The pass knocks the picture about on top of it (rod.wgsl's `pl_jolt`).
fn rd_jolt(p: &mut Plan, t: f32, fo: f32) {
    p.shake(t, fo, 1.8);
    for n in 0..12 {
        let u = n as f32 / 12.0;
        p.shake(t + 0.05 + 0.08 * n as f32, (1.0 - 0.4 * u) * fo, 0.2);
    }
    p.shake(t + 0.3, 0.65 * fo, 6.0);
    let mut ts = t + 1.2;
    while ts < t + 6.0 {
        let u = (ts - t - 1.2) / 4.8;
        p.shake(ts, (0.6 * (1.0 - u).powf(1.4) + 0.08) * fo, 0.28);
        ts += 0.13 + 0.1 * u;
    }
}

/// The front's knockback close in (`Act::Shove`): blocks a tick out from the impact and up (a jump's is 0.42), and past
/// how far none (`strike::knock_share`): a smaller, sharper push than the Nuke's.
const RD_KNOCK_OUT: f32 = 0.65;
const RD_KNOCK_UP: f32 = 0.5;
const RD_KNOCK_REACH: f32 = 450.0;

/// How much of the blast is heard as the far one (`blast_far`), `dist` blocks off: none within 250, all of it past 800.
fn rd_far(dist: f64) -> f32 {
    let u = ((dist - 250.0) / 550.0).clamp(0.0, 1.0);
    (u * u * (3.0 - 2.0 * u)) as f32
}

/// The rod. Silence; the streak tearing down out of the sky, a faint hiss at the very end; the impact: the flash
/// (silent), the shockwave, the fountain of rock and the column of dust, the dust ring racing out over the land and
/// over the player late by how far they are, with the crack-boom, its jolt and its push, the debris coming down, the
/// rumble after; the column falling back and spreading.
pub(super) fn rod_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let (cx, cz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
    let gy = f64::from(by) + 1.0;
    let rel = [me[0] - cx, me[1] - gy, me[2] - cz];
    let geo = RdGeo::new(shader_seed, rel);
    let bar = |text: &str, color: &str| format!(r#"title @s actionbar {{"text":"{text}","color":"{color}","bold":true}}"#);
    let (late, dist) = sound_from([cx, gy, cz], me);
    let fo = falloff(dist * 0.4).max(0.45);

    // the pass's table, on the tick after it fires
    {
        let s = shader_seed;
        p.later(0.05, move |q| {
            q.ev.push((0.05, Act::Table(rd_table(s, rel))));
            q.ev.push((0.05, Act::Words { index: RD_DB as u32, words: rd_debris_words(s as u32) }));
        });
    }
    // (and the land's shape round it, asked of the world as it starts, the heightfield on a later tick)
    {
        let reach = rd_hf_reach(rel[0].hypot(rel[2]));
        let columns = Rc::new(rd_hf_columns(bx, bz, reach));
        let tag = crate::ground::new_tag();
        let cols = columns.clone();
        p.later(0.1, move |q| q.ev.push((0.1, Act::Survey { tag, columns: cols.to_vec() })));
        p.later(0.4, move |q| rd_hf_step(q, tag, columns, reach, rel, by + 1, 0.4));
    }

    // ---- the fall: silent, but for a faint hiss right at the end, cut dead on the impact ----------------------------
    p.at(0.4, bar("KINETIC STRIKE: ROD RELEASED", "white"));
    p.at(RD_HIT - 2.5, bar("IMPACT IMMINENT", "red"));
    p.csound(RD_HIT - RD_HISS, "hiss", 10.0, 1.0);
    // ---- the impact: the flash is silent; the ground's answer first, felt more than heard ---------------------------
    let tg = RD_HIT + (dist / RD_GROUND_V) as f32;
    let gap = RD_HIT + late - tg;
    let gv = ((1.0 / (1.0 + dist / 1200.0)).clamp(0.35, 1.0) * (f64::from(gap - 0.05) / 0.9).clamp(0.3, 1.0).powf(1.2)) as f32;
    p.csound(tg - 0.02, "ground", 10.0 * gv, 1.0);
    if gap > 0.08 {
        p.shake(tg, 0.45 * (2.0 / (1.0 + dist / 400.0)).clamp(0.35, 1.0) as f32, 0.5);
    }
    // ---- the air's: the crack-boom, the jolt and the push as the front passes, the rumble after ---------------------
    let arrive = RD_HIT + late;
    let far = rd_far(dist);
    if far < 1.0 {
        p.csound(arrive - 0.02, "blast", 10.0 * (1.0 - far), 1.0);
    }
    if far > 0.0 {
        p.csound(arrive - 0.02, "blast_far", 10.0 * far * ((1.25 / (1.0 + dist / 2000.0)).min(1.0) as f32), 1.0);
    }
    p.csound(arrive + 1.0, "rumble", 10.0, 1.0);
    // (the rod left standing in the crater humming as it cools: heard round it, where it stands, not in the ears)
    p.ev.push((arrive + 1.0, Act::Sound { event: laser.sound("hum"), at: Some([cx, gy - 20.0, cz]), volume: 1.0, pitch: 1.0 }));
    rd_jolt(&mut p, arrive, (2.0 / (1.0 + dist / 400.0)).clamp(0.3, 1.0) as f32);
    p.ev.push((arrive, Act::Shove { from: [cx, gy, cz], out: RD_KNOCK_OUT, up: RD_KNOCK_UP, reach: RD_KNOCK_REACH }));
    let mut ts = arrive + 6.0;
    while ts < arrive + 12.0 {
        let s = p.rng.uniform(0.04, 0.11) as f32 * fo;
        let d = p.rng.uniform(0.4, 0.9) as f32;
        p.shake(ts, s, d);
        ts += p.rng.uniform(0.5, 1.2) as f32;
    }
    // (debris thudding and pattering down round the player if they are near enough to be under it)
    if dist < 500.0 {
        let near = (1.0 - dist / 500.0) as f32;
        p.csound(arrive + 2.5, "debris", 10.0 * (0.5 + 0.5 * near), 1.0);
        if near > 0.3 {
            p.csound(arrive + 7.0, "debris", 10.0 * (0.25 + 0.4 * near), 0.9);
        }
        let mut td = arrive + 2.7;
        for _ in 0..(6.0 + 12.0 * near) as usize {
            let n = (12.0 + 50.0 * near * p.rng.next() as f32) as i32;
            p.at(td, format!(r#"execute at @s run particle minecraft:block{{block_state:"minecraft:cobblestone"}} ~ ~14 ~ 16 6 16 0.6 {n} force @s"#));
            p.at(td + 0.1, format!(r#"execute at @s run particle minecraft:falling_dust{{block_state:"minecraft:gravel"}} ~ ~10 ~ 14 6 14 0 {} force @s"#, n * 2));
            td += p.rng.uniform(0.25, 0.9) as f32;
        }
    }
    p.at(RD_HIT + 1.5, bar("KINETIC IMPACT", "gray"));
    for t in [RD_HIT + 0.1, RD_HIT + 1.0, RD_HIT + 3.0, RD_HIT + 6.0] {
        p.at(t, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,type=!minecraft:falling_block,distance=..{RD_KILL}]"));
    }
    // (real dust and grit round the crater, for anyone close)
    p.at(RD_HIT + 0.05, format!("particle minecraft:explosion_emitter {cx:.1} {:.1} {cz:.1} 12 4 12 0 12 force", gy + 2.0));
    p.at(RD_HIT + 0.1, format!(r#"particle minecraft:block{{block_state:"minecraft:stone"}} {cx:.1} {:.1} {cz:.1} 25 10 25 1.2 800 force"#, gy + 4.0));
    for i in 0..8 {
        let t = RD_HIT + 1.0 + i as f32 * 1.5;
        p.at(t, format!("particle minecraft:campfire_signal_smoke {cx:.1} {:.1} {cz:.1} 25 3 25 0.03 50 force", gy + 1.0));
    }

    if terrain {
        let point = [cx, gy, cz];
        let load = pk_load_rows(point, 0.0, RD_READ as f64 + 4.0);
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
            crate::meter::spend(9_000_000);
            let work = Rc::new(RefCell::new(Work::new(shape, by + 1)));
            q.later(0.2, move |q| rd_work(q, work, 0.2));
        });
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod table {
    /// `CB_SEED=37 CB_OUT=path RD_ME=x,y,z cargo test --release rd_write_table -- --ignored`: the table the pass reads,
    /// for tools/preview.py (a line `index value` a word), the target's ground at the preview's (0.5 65 0.5), the
    /// player at RD_ME.
    #[test]
    #[ignore]
    fn rd_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let me: Vec<f64> = std::env::var("PL_ME").map_or(vec![0.0, 70.0, 300.0], |v| v.split(',').map(|x| x.parse().unwrap()).collect());
        let rel = [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5];
        let mut w = super::rd_table(seed, rel);
        // (the land's shape, as tools/preview draws it: RD_HILLS=H its hills (main.rs's hills_h), flat otherwise)
        let hills: f64 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        let reach = super::rd_hf_reach(rel[0].hypot(rel[2]));
        let f = |x: f64, z: f64| hills * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin());
        // (PL_FLUSH=1: moved so the target's own ground is the target's, as the preview's `flush=1` draws it)
        let f0 = if std::env::var("PL_FLUSH").is_ok_and(|v| v == "1") { f(0.5, 0.5) } else { 0.0 };
        let heights: Vec<Option<f64>> = super::rd_hf_columns(0, 0, reach)
            .iter()
            .map(|&(x, z)| Some(f(f64::from(x) + 0.5, f64::from(z) + 0.5) - f0))
            .collect();
        let hf = super::rd_hf_words(&heights, reach, rel);
        w.resize(super::RD_HF + hf.len(), 0);
        w[super::RD_HF..].copy_from_slice(&hf);
        let db = super::rd_debris_words(seed as u32);
        w.resize(super::RD_DB + db.len(), 0);
        w[super::RD_DB..].copy_from_slice(&db);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    #[test]
    fn rod_sounds_are_its_own_and_arrive_late_by_the_distance() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let sounds = |z: f64| -> Vec<(f32, String, f32)> {
            plan(&crate::lasers::ROD, &target, false, "minecraft:overworld", 37.0, [10.5, 66.0, z], 0)
                .into_iter()
                .filter_map(|(t, a)| if let Act::Sound { event, volume, .. } = a { Some((t, event, volume)) } else { None })
                .collect()
        };
        let near = sounds(200.0);
        let has = |v: &[(f32, String, f32)], s: &str| v.iter().find(|e| e.1 == format!("orbital:rod.{s}")).map(|e| e.0);
        for s in ["hiss", "blast", "ground", "debris", "rumble", "hum"] {
            assert!(has(&near, s).is_some(), "{s}");
        }
        assert!(has(&near, "blast_far").is_none());
        // (the fall is silent but for the hiss, cut on the impact; the flash too: nothing of the impact is heard until
        // the ground and the air carry it)
        assert!(near.iter().all(|e| e.1.ends_with("hiss") || e.0 > RD_HIT), "{near:?}");
        assert!((has(&near, "hiss").unwrap() - (RD_HIT - RD_HISS)).abs() < 1e-4);
        let far = sounds(1500.0);
        assert!(has(&far, "blast").is_none() && has(&far, "blast_far").is_some() && has(&far, "debris").is_none());
        assert!(has(&far, "blast_far").unwrap() > has(&near, "blast").unwrap() + 3.0);
        assert!(has(&far, "ground").unwrap() < has(&far, "blast_far").unwrap());
        // (the crack-boom from 200 blocks off as far behind the impact as the sound takes)
        assert!((has(&near, "blast").unwrap() - (RD_HIT + (200.0f64.hypot(1.0) / 343.0) as f32 - 0.02)).abs() < 0.02);
    }

    #[test]
    fn rod_falls_from_high_up_onto_its_burst_point() {
        for seed in [3.0, 37.0, 512.0, 991.0] {
            let me = [0.0, 5.0, 600.0];
            let g = RdGeo::new(seed, me);
            let p0 = g.pos(f64::from(RD_SEEN));
            assert!(p0[1] > 2500.0, "{p0:?}");
            // (plumb over the target)
            assert!(p0[0].hypot(p0[2]) < 1e-6, "{p0:?}");
            let end = g.pos(f64::from(RD_HIT));
            assert!(len(add(end, [0.0, RD_BURST, 0.0], -1.0)) < 1e-6, "{end:?}");
            let mut last = p0;
            let mut t = f64::from(RD_SEEN);
            while t < f64::from(RD_HIT) {
                t += 0.02;
                let q = g.pos(t.min(f64::from(RD_HIT)));
                assert!(q[1] <= last[1] + 1e-9 && q[1] >= RD_BURST - 1e-6, "{t} {q:?}");
                last = q;
            }
            // (the last second very fast: over a third of the fall, ending at over 1,500 blocks a second)
            let h1 = g.pos(f64::from(RD_HIT) - 1.0)[1];
            assert!(h1 > 0.33 * p0[1], "{h1} {p0:?}");
            // (and a last hard burst in its last fraction of a second: over 4,000 blocks a second in its last 0.02 s,
            // twice what it was going a quarter second before)
            let v = |t: f64| (g.pos(t - 0.01)[1] - g.pos(t + 0.01)[1]) / 0.02;
            assert!(v(f64::from(RD_HIT) - 0.01) > 4000.0 && v(f64::from(RD_HIT) - 0.01) > 2.0 * v(f64::from(RD_HIT) - 0.25), "{} {}", v(f64::from(RD_HIT) - 0.01), v(f64::from(RD_HIT) - 0.25));
        }
        let w = rd_table(37.0, [0.0, 5.0, 300.0]);
        assert!(w.len() <= RD_HF && RD_P + 3 * RD_N <= RD_FR && RD_HF + 8 + RD_HN * RD_HN <= RD_DB);
    }

    #[test]
    fn rod_heightfield_follows_the_land_and_shelters_behind_a_ridge() {
        let me = [0.0, 0.0, 300.0];
        let reach = rd_hf_reach(300.0);
        let cols = rd_hf_columns(0, 0, reach);
        assert_eq!(cols.len(), RD_HN * RD_HN);
        // (a ridge 30 high across the way to the player at z 150, a trunk standing in one cell, the far corner not loaded)
        let heights: Vec<Option<f64>> = cols
            .iter()
            .enumerate()
            .map(|(c, &(x, z))| {
                if c == 10 * RD_HN + 10 {
                    return Some(25.0);
                }
                if x > 300 && z > 300 {
                    return None;
                }
                Some(30.0 * (-(f64::from(z) - 150.0).powi(2) / 2000.0).exp() + 0.0 * f64::from(x))
            })
            .collect();
        let w = rd_hf_words(&heights, reach, me);
        assert_eq!(w.len(), 8 + RD_HN * RD_HN);
        assert_eq!(f32::from_bits(w[0]), RD_HN as f32);
        let cell = |x: f64, z: f64| {
            let step = 2.0 * reach / (RD_HN - 1) as f64;
            let (i, k) = (((x + reach) / step).round() as usize, ((z + reach) / step).round() as usize);
            let v = w[8 + k * RD_HN + i];
            (f64::from(v & 0xffff) / 8.0 - 512.0, f64::from((v >> 16) & 0xff) / 255.0)
        };
        let step = 2.0 * reach / (RD_HN - 1) as f64;
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
            2 => (x < -30).then_some((50, 62)),
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
        let mut ev = plan(&crate::lasers::ROD, &target, terrain, "minecraft:overworld", 37.0, [10.5, 66.0, 400.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Vec::new();
        let mut table = false;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| column(x, z, below, above)),
                Act::Blocks(b) => out.push((t, *b)),
                Act::Cmd(c) => cmds.push((t, c)),
                Act::Table(w) => {
                    assert_eq!(w.len(), RD_FR);
                    table = true;
                }
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
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
    fn rod_digs_a_crater_and_fells_the_trees() {
        LAND.with(|l| l.set(0));
        let blocks = played(true);
        assert!(!blocks.is_empty());
        let fills: Vec<String> = blocks.iter().flat_map(|(_, b)| b.as_fills()).collect();
        // nothing that burns or flows is placed; no water placed at all
        for f in &fills {
            for bad in ["lava ", "magma", "sand ", "concrete_powder", "water "] {
                assert!(!f.contains(&format!(" minecraft:{bad}")) || f.contains(" replace "), "{f}");
            }
        }
        // the middle dug about RD_CRATER_D deep
        let mid = fills.iter().find(|f| f.starts_with("fill 10 ") && f.contains(" -3 10 ") && f.ends_with("minecraft:air strict")).expect("the middle dug");
        let y0: i32 = mid.split_whitespace().nth(2).unwrap().parse().unwrap();
        assert!((ground_h(10, -3) - y0 + 1 - RD_CRATER_D as i32).abs() <= 1, "{mid}");
        // a punch, not a bowl: still most of its depth most of the way out to its edge
        assert!(bowl(0.8) > 0.75 * RD_CRATER_D && bowl(0.97) < 0.4 * RD_CRATER_D);
        // its floor fractured and fused into dark glass in patches; its rim heaped with the deep rock turned over on top
        assert!(fills.iter().any(|f| f.ends_with("minecraft:tinted_glass strict") || f.ends_with("minecraft:obsidian strict")));
        // hallowed: its lining white and gold, lit by veins of light; its rim bleached; the grass round it blessed
        let count = |m: &str| fills.iter().filter(|f| f.contains(&format!("minecraft:{m} "))).count();
        assert!(count("quartz_block") + count("smooth_quartz") + count("quartz_pillar") + count("chiseled_quartz_block") > 200);
        assert!(count("gold_block") > 20 && count("glowstone") + count("shroomlight") > 20 && count("calcite") > 100);
        assert!(count("white_concrete") > 50 && count("pale_moss_block") > 100 && count("lily_of_the_valley") + count("oxeye_daisy") > 5);
        // rubble strewn in rays far out, past the flattened land's middle
        let far_rubble = fills
            .iter()
            .filter(|f| {
                let w: Vec<f64> = f.split_whitespace().skip(1).take(6).map(|v| v.parse().unwrap_or(0.0)).collect();
                w[1] == w[4] && (w[0] - 10.0).hypot(w[2] + 3.0) > 180.0 && (f.ends_with("calcite strict") || f.ends_with("quartz_block strict"))
            })
            .count();
        assert!(far_rubble > 10, "{far_rubble}");
        // trees felled: logs lying along x or z
        let lying = fills.iter().filter(|f| f.contains("_log[axis=")).count();
        assert!(lying > 20, "{lying}");
        // past the flattened land: crowns stripped, and some trees knocked flat there (logs lying beyond RD_FLAT)
        let stripped = fills.iter().filter(|f| f.ends_with("minecraft:air replace minecraft:oak_leaves strict")).count();
        assert!(stripped > 10, "{stripped}");
        let far_logs = fills
            .iter()
            .filter(|f| f.contains("_log[axis="))
            .filter(|f| {
                let w: Vec<f64> = f.split_whitespace().skip(1).take(3).map(|v| v.parse().unwrap_or(0.0)).collect();
                (w[0] - 10.0).hypot(w[2] + 3.0) > RD_FLAT * 1.15
            })
            .count();
        assert!(far_logs > 3, "{far_logs}");
        // the crown of a felled tree never left in the air: every leaves block at a tree's column cleared
        for x in -140..160 {
            for z in -140..140 {
                if !tree(x, z) {
                    continue;
                }
                let r = (f64::from(x) - 10.0).hypot(f64::from(z) + 3.0);
                // (in the crater and over the flattened land past its rim; on the rim the heap may bury the crown)
                if (r < 50.0 || (r > 100.0 && r < 140.0)) && water_at(x, z).is_none() {
                    let g = ground_h(x, z);
                    assert!(fills.iter().any(|f| f.starts_with(&format!("fill {x} ")) && f.contains(&format!(" {z} {x} ")) && f.contains("minecraft:air") && f.contains(&format!(" {} {z} ", g + 8))), "tree at {x} {z} left standing");
                }
            }
        }
    }

    #[test]
    fn rod_stands_in_its_crater_once_the_land_is_in() {
        // (every block of the rod, the last thing put there of all the strike's edits, in the order they go in)
        LAND.with(|l| l.set(0));
        let mut blocks = played(true);
        blocks.sort_by(|a, b| a.0.total_cmp(&b.0));
        let (bx, bz) = (10, -3);
        // (only those over the rod's box)
        let fills: Vec<String> = blocks
            .iter()
            .flat_map(|(_, b)| b.as_fills())
            .filter(|f| {
                let w: Vec<i32> = f.split_whitespace().skip(1).take(6).filter_map(|v| v.parse().ok()).collect();
                w.len() == 6 && w[0].min(w[3]) <= bx + 7 && w[0].max(w[3]) >= bx - 7 && w[2].min(w[5]) <= bz + 7 && w[2].max(w[5]) >= bz - 7
            })
            .collect();
        let floor = ground_h(bx, bz) - RD_CRATER_D as i32;
        let top = floor + RD_ROD_UP;
        let mut cols = 0;
        for x in bx - 7..=bx + 7 {
            for z in bz - 7..=bz + 7 {
                let rod = (x - bx).pow(2) + (z - bz).pow(2) <= RD_ROD_R2;
                cols += i32::from(rod);
                for y in floor - RD_ROD_DOWN..=top + 2 {
                    let last = fills.iter().rev().find(|f| {
                        let w: Vec<i32> = f.split_whitespace().skip(1).take(6).filter_map(|v| v.parse().ok()).collect();
                        w.len() == 6 && !f.contains(" replace ") && (w[0].min(w[3])..=w[0].max(w[3])).contains(&x) && (w[1].min(w[4])..=w[1].max(w[4])).contains(&y) && (w[2].min(w[5])..=w[2].max(w[5])).contains(&z)
                    });
                    let is_rod = last.is_some_and(|f| ["polished_blackstone", "gold_block", "chiseled_polished_blackstone", "ochre_froglight"].iter().any(|m| f.contains(&format!("minecraft:{m} "))));
                    let d2 = (x - bx).pow(2) + (z - bz).pow(2);
                    if !rod && d2 <= RD_ROD_RING2 && y == floor {
                        // (the ring of light round its foot)
                        assert!(last.is_some_and(|f| f.contains("minecraft:glowstone ") || f.contains("minecraft:shroomlight ")), "{x} {y} {z}: {last:?}");
                        continue;
                    }
                    if rod {
                        assert_eq!(is_rod, y <= top, "{x} {y} {z}: {last:?}");
                    } else {
                        assert!(!last.is_some_and(|f| f.contains("minecraft:polished_blackstone ")), "{x} {y} {z}: {last:?}");
                    }
                }
            }
        }
        // (round, eleven wide; its top light; standing 30 over the land round it)
        assert_eq!(cols, 89);
        assert!(fills.iter().any(|f| f.starts_with(&format!("fill {bx} {top} {bz} ")) && f.contains("minecraft:ochre_froglight")));
        assert_eq!(top - ground_h(bx, bz), RD_ROD_UP - RD_CRATER_D as i32);
        // (nothing thrown out of the crater from round it, to come down on it)
        let (_, cmds) = played_all(true);
        for (_, c) in cmds.iter().filter(|(_, c)| c.starts_with("summon minecraft:falling_block")) {
            let w: Vec<f64> = c.split_whitespace().skip(2).take(3).map(|v| v.parse().unwrap()).collect();
            assert!((w[0] - 10.5).hypot(w[2] + 2.5) >= 13.9, "{c}");
        }
    }

    #[test]
    fn rod_crater_digs_water_like_any_block() {
        // (at the sea: the crater cuts into it as into the land, places no water and seals none; only lava is sealed)
        LAND.with(|l| l.set(2));
        let fills: Vec<String> = played(true).iter().flat_map(|(_, b)| b.as_fills()).collect();
        assert!(!fills.iter().any(|f| f.contains("minecraft:water")), "{:?}", fills.iter().find(|f| f.contains("minecraft:water")));
        assert!(fills.iter().any(|f| f.starts_with("fill -40 ") && f.ends_with("minecraft:air strict")), "the sea dug");
        assert!(fills.iter().any(|f| f.ends_with("minecraft:stone replace minecraft:lava strict")));
        LAND.with(|l| l.set(0));
    }

    /// `cargo test --release rod_no_stage_too_heavy_anywhere -- --ignored --nocapture`, on its own (other tests running
    /// beside it slow every stage down): the timing half of `rod_land_goes_in_in_order_anywhere`.
    #[test]
    #[ignore]
    fn rod_no_stage_too_heavy_anywhere() {
        rod_anywhere(true);
    }
    /// Wherever it strikes, the land's edits go in on time (but in a jungle of tall trees, where they trail the wave a
    /// little) and from the middle out.
    #[test]
    fn rod_land_goes_in_in_order_anywhere() {
        rod_anywhere(false);
    }
    fn rod_anywhere(timed: bool) {
        if timed && cfg!(debug_assertions) {
            return;
        }
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        for land in [0u8, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
            LAND.with(|l| l.set(land));
            let mut best: Vec<f64> = Vec::new();
            let mut late_all = 0.0f32;
            for _ in 0..2 {
                let ev = plan(&crate::lasers::ROD, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
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
                    if (k as f32) * 0.05 < Wave::new().at(f64::from(RD_READ)) {
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
    fn rod_land_changes_sweep_out_from_the_middle_with_the_wave() {
        // played as the mod plays it (one stage a tick): nothing changes before the wave reaches it, the wave keeps up
        // (no edit goes in late), and it sweeps out from the middle
        LAND.with(|l| l.set(0));
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(&crate::lasers::ROD, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
        let p = crate::strike::sim::play(ev, 30.0, &column);
        let wave = Wave::new();
        let mut last = 0.0f64;
        let mut by_tick: std::collections::BTreeMap<i32, Vec<f64>> = Default::default();
        for (t, due, b) in &p.edits {
            assert!(t - due < 0.2, "an edit {:.2} s late", t - due);
            for u in &b.runs {
                let r = (f64::from(u.x) + 0.5 - 10.5).hypot(f64::from(u.z) + 0.5 + 2.5);
                if *t < wave.at(r - 4.0 * RD_RING - 4.0) - 0.06 {
                    let f = b.as_fills()[b.runs.iter().position(|v| std::ptr::eq(v, u)).unwrap()].clone();
                    panic!("at {r:.0} at {t:.2}, before the wave ({:.2}): {f}", wave.at(r));
                }
                by_tick.entry((t / 0.05).round() as i32).or_default().push(r);
            }
        }
        // (the middle of what changes each tick, while the wave runs, further out tick by tick)
        for (k, mut rs) in by_tick.into_iter().filter(|(k, _)| (*k as f32) * 0.05 < wave.at(f64::from(RD_READ))) {
            rs.sort_by(f64::total_cmp);
            let m = rs[rs.len() / 2];
            assert!(m >= last - 30.0, "tick {k}: {m:.0} after {last:.0}");
            last = last.max(m);
        }
        assert!(last > 220.0, "{last}");
    }

    #[test]
    fn rod_leaves_the_land_alone_with_the_terrain_off() {
        let (blocks, cmds) = played_all(false);
        assert!(blocks.is_empty());
        assert!(!cmds.iter().any(|(_, c)| c.contains("falling_block {")), "no blocks thrown with the terrain off");
    }

    #[test]
    fn rod_throws_real_blocks_out_of_the_crater() {
        let (_, cmds) = played_all(true);
        let thrown: Vec<&(f32, String)> = cmds.iter().filter(|(_, c)| c.starts_with("summon minecraft:falling_block")).collect();
        // a fair number, over the second and a half after it strikes, a few a tick at most
        assert!(thrown.len() >= 60 && thrown.len() <= RD_THROWN, "{} thrown", thrown.len());
        let mut per_tick = std::collections::HashMap::new();
        for (t, c) in &thrown {
            assert!(*t > RD_HIT && *t < Wave::new().at(RD_CRATER_R) + 1.3, "{t}");
            *per_tick.entry((t * 20.0) as i32).or_insert(0) += 1;
            // never dropping an item; out of the crater (the target at 10 -3), outward and up
            assert!(c.contains("DropItem:0b"), "{c}");
            let w: Vec<f64> = c.split_whitespace().skip(2).take(3).map(|v| v.parse().unwrap()).collect();
            assert!((w[0] - 10.5).hypot(w[2] + 2.5) < RD_CRATER_R, "{c}");
            let m = c.split("Motion:[").nth(1).unwrap();
            let v: Vec<f64> = m.trim_end_matches("]}").split(',').map(|v| v.trim_end_matches('d').parse().unwrap()).collect();
            assert!(v[1] > 0.5, "{c}");
            assert!((w[0] - 10.5) * v[0] + (w[2] + 2.5) * v[2] >= -1.0e-6, "{c}");
            // of the ground that was there: no grass or leaves of a plant, nothing that flows
            assert!(!c.contains("water") && !c.contains("lava") && !c.contains("sand\""), "{c}");
        }
        assert!(per_tick.values().all(|&k| k <= 24), "{per_tick:?}");
        // some land as blocks, some break up where they land
        let breaks = thrown.iter().filter(|(_, c)| c.contains("CancelDrop:1b")).count();
        assert!(breaks > 10 && breaks < thrown.len() - 10, "{breaks}");
        // and they are not killed in the air as the land round it is cleared of what lives there
        assert!(cmds.iter().filter(|(_, c)| c.contains("kill @e")).all(|(_, c)| c.contains("type=!minecraft:falling_block")));
    }
    /// `cargo test --release rd_wave_profile -- --ignored --nocapture`: the land's edits as the mod plays them out
    /// (one stage a tick): how far out they reach a quarter second at a time, how many blocks, and the latest stage.
    #[test]
    #[ignore]
    fn rd_wave_profile() {
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let ev = plan(&crate::lasers::ROD, &target, true, "minecraft:overworld", 37.0, [10.5, 66.0, 500.0], 0);
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
        if std::env::var("RD_BUSY").is_ok() {
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
        if std::env::var("RD_STAGES").is_ok() {
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
    /// `cargo test --release rd_stage_cost -- --ignored --nocapture`: the heaviest stages (native time; see the fuel
    /// harness for the game's measure).
    #[test]
    #[ignore]
    fn rd_stage_cost() {
        let target = Target { block: [-1041, 64, 860], point: [-1040.5, 65.0, 860.5] };
        let t0 = std::time::Instant::now();
        let mut ev = plan(&crate::lasers::ROD, &target, true, "minecraft:overworld", 19.0, [-1040.5, 70.0, 1160.5], 0);
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
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
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
    fn rd_wave_times() {
        let w = super::Wave::new();
        for r in [0.0, 25.0, 50.0, 75.0, 100.0, 140.0, 180.0, 230.0, 300.0, 380.0, 480.0] {
            let shock = ((r * r + super::RD_BURST * super::RD_BURST) as f64).sqrt() / 343.0;
            println!("r {r:4}: {:.2} s after the burst (the shock {:.2})", w.at(r) - super::RD_HIT, shock);
        }
    }
}
