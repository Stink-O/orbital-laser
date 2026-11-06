//! The Tsunami's plan: a wave of dark, debris-laden water 320 blocks high and over five kilometres wide rises on the
//! horizon beyond the target, crosses the land at about 100 blocks a second, sweeps the target away, washes over the
//! player and drains off, leaving mud, gravel and wreckage.
//!
//! The wave is a closed-form model, the same in the pass (shaders/tsunami.wgsl: keep the TS_* and the functions in
//! step): the front reaches a point at `arr`, the water there rises over the face, holds, then drains away (`prof`), its
//! height by `env` (grown as it comes in, weaker as it runs inland, spent at its end, weaker towards its flanks). So
//! nothing is kept from frame to frame, and the land's work, the sounds, the carry and the shakes all take their times
//! from the same functions.
//!
//! The real land under it: every column of a swath about 700 across (`mask`) is read (`world.read-columns`) in the
//! order the front reaches it; each chunk is changed on one tick (`world.edit-blocks`) a second after its water is
//! deep, hidden under it: everything that stood on the land goes (trees, plants, buildings: all but what `stays`), the
//! soil is scoured to mud, packed mud, gravel, sand and coarse dirt in streaks along the flow, the wreckage of what
//! stood there is laid back down along the flow, a few boulders are left, and every mob and item in the chunk dies.
//!
//! Timeline (TS_LEN 42 s): the wave rises on the horizon (0 to 3 s), crosses the land at TS_V0 (TS_T, 9 s, at the
//! target; slowing past it), reaches the player (`arr` at their place, about 14.7 s from 400 blocks), washes over them,
//! holds 6.5 s, drains over 14 s.
//!
//! Keep the TS_* here and in tsunami.wgsl in step.
#![cfg_attr(not(test), allow(dead_code))]
use super::hu_blocks::HU_BLOCKS;
use super::hurricane::hu_block;
use super::sh_land::{self, Class};
use super::{Act, Blocks, Plan, Rng, Target, falloff, mh, pcg, wing_angle};
use crate::lasers::Laser;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

// ---- the model (tsunami.wgsl's ts_*; kept in step) ------------------------------------------------------------------
pub(crate) const TS_LEN: f32 = 42.0;
/// When the front crosses the target, its speed there (blocks a second; it slows past it by TS_C), the sea level it rises
/// from under the target's ground, its amplitude over that at full strength, the face's width, the seconds the water
/// holds, then drains over, and how far the water behind the crest sits under it (a share).
pub(crate) const TS_T: f64 = 9.0;
pub(crate) const TS_V0: f64 = 100.0;
pub(crate) const TS_C: f64 = 1.07e-5;
pub(crate) const TS_SEA: f64 = 100.0;
pub(crate) const TS_A: f64 = 420.0;
pub(crate) const TS_FACE: f64 = 105.0;
pub(crate) const TS_HOLD: f64 = 6.5;
pub(crate) const TS_DRAIN: f64 = 14.0;
pub(crate) const TS_LOW: f64 = 0.15;

pub(crate) fn smooth(a: f64, b: f64, x: f64) -> f64 {
    let u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    u * u * (3.0 - 2.0 * u)
}
fn fh21(i: i32, j: i32) -> f32 {
    pcg(i as u32 ^ pcg(j as u32)) as f32 * (1.0 / 4_294_967_295.0)
}
/// The pass's fvnoise (value noise on the PCG hash), 0 to 1.
pub(crate) fn fvnoise(x: f32, z: f32) -> f32 {
    crate::meter::spend(160);
    let (i, j) = (x.floor(), z.floor());
    let (fx, fz) = (x - i, z - j);
    let (ux, uz) = (fx * fx * (3.0 - 2.0 * fx), fz * fz * (3.0 - 2.0 * fz));
    let (i, j) = (i as i32, j as i32);
    let a = fh21(i, j) + (fh21(i + 1, j) - fh21(i, j)) * ux;
    let b = fh21(i, j + 1) + (fh21(i + 1, j + 1) - fh21(i, j + 1)) * ux;
    a + (b - a) * uz
}

/// Where the wave is: the target's ground, the way it moves (towards the player), across, how far the player stood from
/// the target and how far past it the wave runs before it is spent.
#[derive(Clone, Debug)]
pub(crate) struct TsGeo {
    pub t: [f64; 3],
    pub m: [f64; 2],
    pub n: [f64; 2],
    pub dp: f64,
    pub send: f64,
    pub sd: f32,
}
impl TsGeo {
    pub fn new(target: &Target, me: [f64; 3], shader_seed: f32) -> TsGeo {
        let [bx, by, bz] = target.block;
        let (tx, tz) = (f64::from(bx) + 0.5, f64::from(bz) + 0.5);
        let a = f64::from(wing_angle(target.point, me));
        let m = [a.cos(), a.sin()];
        let dp = (me[0] - tx).hypot(me[2] - tz);
        TsGeo { t: [tx, f64::from(by) + 1.0, tz], m, n: [-m[1], m[0]], dp, send: (dp + 160.0).min(720.0), sd: (shader_seed * 0.618_034).fract() * 40.0 }
    }
    /// (s, u) of the world point (x, z): out along the wave's way from the target, and across it.
    pub fn su(&self, x: f64, z: f64) -> (f64, f64) {
        let (dx, dz) = (x - self.t[0], z - self.t[2]);
        (dx * self.m[0] + dz * self.m[1], dx * self.n[0] + dz * self.n[1])
    }
    pub fn tau(s: f64) -> f64 {
        let sp = s.max(0.0);
        s / TS_V0 + TS_C * sp * sp
    }
    /// How long the face takes to go over a point `s` out (seconds).
    pub fn rise_t(s: f64) -> f64 {
        TS_FACE / Self::vel(s)
    }
    pub fn vel(s: f64) -> f64 {
        1.0 / (1.0 / TS_V0 + 2.0 * TS_C * s.max(0.0))
    }
    pub fn lag(&self, s: f64, u: f64) -> f64 {
        crate::meter::spend(60);
        let sd = f64::from(self.sd);
        3.0e-7 * u * u + (0.34 * (u * 0.0043 + sd + s * 0.0011).sin() + 0.13 * (u * 0.0127 + sd * 1.7 - s * 0.0023).sin() + 0.05 * (u * 0.0331 + sd * 0.6 + s * 0.0041).sin()) * smooth(-650.0, -150.0, s)
    }
    /// When the front reaches (s, u).
    pub fn arr(&self, s: f64, u: f64) -> f64 {
        TS_T + Self::tau(s) + self.lag(s, u)
    }
    /// How strong the wave is at (s, u), 0 to about 1.
    pub fn env(&self, s: f64, u: f64) -> f64 {
        crate::meter::spend(60);
        let sd = f64::from(self.sd);
        let up = 0.22 + 0.78 * if s > -380.0 { 1.0 } else { smooth(-950.0, -600.0, s + 20.0 * (u * 0.0031 + sd * 2.1).sin() + 12.0 * (u * 0.0083 + sd * 0.7).sin()) };
        let dec = 1.0 - 0.345 * smooth(-640.0, -40.0, s);
        let run = 1.0 - 0.13 * smooth(0.0, self.send, s);
        let end = 1.0 - smooth(self.send - 80.0, self.send + 30.0, s);
        let lat = 1.0 - smooth(1900.0, 3300.0, u.abs());
        let lump = 1.0 + 0.028 * (u * 0.0063 + sd * 1.7 + s * 0.0016).sin() + 0.024 * (u * 0.0171 + sd * 0.9 - s * 0.0031).sin() + 0.016 * (u * 0.0419 + sd * 2.3 + s * 0.0047).sin();
        up * dec * run * end * lat * lump
    }
    /// How far it has drained at `s` at `t`, 0 to 1 (the pass's ts_x): all the land's water goes together, the seaward side
    /// a little first.
    pub fn drained(&self, t: f64, s: f64) -> f64 {
        let t0 = TS_T + Self::tau(self.dp) + Self::rise_t(self.dp) + TS_HOLD + 0.0016 * (s - self.dp);
        ((t - t0) / TS_DRAIN).clamp(0.0, 1.0)
    }
    /// The level `lv` (over the target's ground) as it drains, `x`: down hard at first, slowing as it nears the land (the
    /// pass's ts_fall).
    pub fn fall(lv: f64, x: f64) -> f64 {
        if x <= 0.0 {
            return lv;
        }
        let e = smooth(0.0, 0.42, x);
        lv + (12.0 - 118.0 * x * x - lv) * e
    }
    /// The water's height over its sea (0 to 1) `tau` seconds after the front reached a point `s` out.
    pub fn prof(tau: f64, s: f64) -> f64 {
        if tau <= 0.0 {
            return 0.0;
        }
        let tr = TS_FACE / Self::vel(s);
        let rr = (tau / tr).clamp(0.0, 1.0);
        rr.powf(1.7) * (1.0 - TS_LOW * smooth(tr, tr * 3.0, tau))
    }
    /// The level the water holds at (s, u), over the target's ground (a column's ground is `g - t[1]` over it).
    pub fn peak(&self, s: f64, u: f64) -> f64 {
        TS_A * self.env(s, u) - TS_SEA
    }
    /// The surface's height over the target's ground at (s, u) at `t`, none where there is no water.
    pub fn level(&self, s: f64, u: f64, t: f64) -> Option<f64> {
        let env = self.env(s, u);
        if env < 0.03 {
            return None;
        }
        let p = Self::prof(t - self.arr(s, u), s);
        let x = self.drained(t, s);
        (p > 0.0 && x < 1.0).then(|| Self::fall(TS_A * env * p - TS_SEA, x))
    }
    /// Where the middle of the front is at `t` (the inverse of tau).
    pub fn front(t: f64) -> f64 {
        let tt = t - TS_T;
        if tt < 0.0 {
            return tt * TS_V0;
        }
        let b = 1.0 / TS_V0;
        (-b + (b * b + 4.0 * TS_C * tt).sqrt()) / (2.0 * TS_C)
    }
    /// When the front reaches the player's place (the middle of its line), and when the water there first reaches their
    /// eye (feet at `feet_y`): none if the wave never gets that high there.
    pub fn at_player(&self, feet_y: f64) -> (f64, Option<f64>) {
        let (s, u) = (self.dp, 0.0);
        let a = self.arr(s, u);
        let want = feet_y + 1.62 - self.t[1];
        let (mut lo, mut hi) = (a, a + TS_FACE / Self::vel(s) + TS_HOLD);
        if self.level(s, u, hi).is_none_or(|l| l < want) {
            return (a, None);
        }
        for _ in 0..24 {
            let mid = 0.5 * (lo + hi);
            if self.level(s, u, mid).is_some_and(|l| l >= want) {
                hi = mid;
            } else {
                lo = mid;
            }
        }
        (a, Some(hi))
    }
}

// ---- what the pass reads (render.set-data) ----------------------------------------------------------------------------
/// The block types the wave's debris is made of, each its HU_BKW words at TSB + TSBW * its place (the Hurricane's bk_words:
/// the game's own textures through the atlas); the pass picks among them by the land the wave is over (`TSM`: for each
/// 16 by 16 cell of the land in the wave's own axes, the share of its columns with trees on them and with buildings, a
/// byte each, and over them the land's height over the target's ground + 2048, from TSM_S0 along it and TSM_U0 across it).
pub(crate) const TS_KINDS: [&str; 24] = [
    "minecraft:oak_log", "minecraft:spruce_log", "minecraft:birch_log", "minecraft:dark_oak_log", "minecraft:oak_planks",
    "minecraft:spruce_planks", "minecraft:cobblestone", "minecraft:stone_bricks", "minecraft:bricks", "minecraft:glass",
    "minecraft:hay_block", "minecraft:white_wool", "minecraft:oak_leaves", "minecraft:spruce_leaves", "minecraft:dirt",
    "minecraft:grass_block", "minecraft:mud", "minecraft:gravel", "minecraft:mossy_cobblestone", "minecraft:bookshelf",
    "minecraft:barrel", "minecraft:crafting_table", "minecraft:acacia_planks", "minecraft:sand",
];
pub(crate) const TSB: usize = 64;
pub(crate) const TSBW: usize = 12;
pub(crate) const TSM: usize = 384;
pub(crate) const TSM_S: usize = 64;
pub(crate) const TSM_U: usize = 44;
const TSM_S0: f64 = -320.0;
const TSM_U0: f64 = -352.0;
pub(crate) const TS_WORDS: usize = TSM + TSM_S * TSM_U;

/// The pass's table before the land is read: the block types' words, the map empty (the pass then takes a wood's share).
fn table_words(terrain: bool) -> Vec<u32> {
    let mut w = vec![0u32; TS_WORDS];
    w[2] = f32::from(u8::from(terrain)).to_bits();
    w[3] = TS_KINDS.len() as u32;
    for (i, name) in TS_KINDS.iter().enumerate() {
        if let Some(b) = hu_block(name) {
            w[TSB + TSBW * i..TSB + TSBW * (i + 1)].copy_from_slice(&super::hurricane::bk_words(b, 0, 0));
        }
    }
    w
}
/// A cell of the map for the column at (s, u), if it is on it.
fn map_cell(s: f64, u: f64) -> Option<usize> {
    let (i, j) = (((s - TSM_S0) / 16.0).floor(), ((u - TSM_U0) / 16.0).floor());
    (i >= 0.0 && j >= 0.0 && (i as usize) < TSM_S && (j as usize) < TSM_U).then(|| j as usize * TSM_S + i as usize)
}

// ---- the land's swath ------------------------------------------------------------------------------------------------
/// How far across (half) the land's work reaches, how far upstream of the target and how far it is let fade.
const TS_HALF: f64 = 345.0;
const TS_UP: f64 = 300.0;
/// How strongly the wave's work reaches (s, u): the share of its columns changed, 1 in the middle, fading out at its flanks
/// and at both ends.
fn mask(geo: &TsGeo, s: f64, u: f64) -> f64 {
    let lat = 1.0 - smooth(255.0, TS_HALF, u.abs());
    let along = smooth(-TS_UP, -TS_UP + 130.0, s) * (1.0 - smooth(geo.send - 50.0, geo.send + 20.0, s));
    lat * along
}
/// The chunks the work covers (every chunk whose middle is within reach with a chunk's margin), with when the front
/// reaches its middle, in the order it does.
fn swath_chunks(geo: &TsGeo) -> Vec<(i32, i32, f64)> {
    let (tx, tz) = (geo.t[0], geo.t[2]);
    let reach = TS_UP + geo.send + TS_HALF + 40.0;
    let (c0, c1) = (((tx - reach) / 16.0).floor() as i32, ((tx + reach) / 16.0).ceil() as i32);
    let (r0, r1) = (((tz - reach) / 16.0).floor() as i32, ((tz + reach) / 16.0).ceil() as i32);
    let mut out = Vec::new();
    for cz in r0..=r1 {
        for cx in c0..=c1 {
            let (x, z) = (f64::from(cx * 16) + 8.0, f64::from(cz * 16) + 8.0);
            let (s, u) = geo.su(x, z);
            if u.abs() > TS_HALF + 14.0 || s < -TS_UP - 14.0 || s > geo.send + 14.0 {
                continue;
            }
            out.push((cx, cz, geo.arr(s, u)));
        }
    }
    crate::meter::spend(200 * out.len() as u64);
    out.sort_by(|a, b| a.2.total_cmp(&b.2));
    out
}
/// The forceloads that keep those chunks loaded (a row of chunks a forceload, at most 256 chunks each).
fn load_rows(chunks: &[(i32, i32, f64)]) -> Vec<[i32; 4]> {
    let mut rows: std::collections::BTreeMap<i32, Vec<i32>> = Default::default();
    for &(cx, cz, _) in chunks {
        rows.entry(cz).or_default().push(cx);
    }
    let mut out = Vec::new();
    for (cz, mut xs) in rows {
        xs.sort_unstable();
        let mut start = xs[0];
        for k in 1..=xs.len() {
            if k == xs.len() || xs[k] != xs[k - 1] + 1 || xs[k] - start >= 15 {
                out.push([start * 16, cz * 16, xs[k - 1] * 16 + 15, cz * 16 + 15]);
                if k < xs.len() {
                    start = xs[k];
                }
            }
        }
    }
    out
}

// ---- reading and changing the land -----------------------------------------------------------------------------------
/// How much of each column is read (down from its world-surface top, and up from it), and the chunks in a read (about
/// 25,000 columns: under the game's 1,048,576 blocks a query).
const TS_BELOW: u32 = 40;
const TS_ABOVE: u32 = 1;
const TS_PART: usize = 96;
/// A stage's work (`meter`), and how long the land's work waits for chunks the world has not loaded before it leaves them.
const TS_STAGE: u64 = 5_000_000;
const TS_LAND_BY: f64 = 38.0;

fn chance(x: i32, z: i32, seed: u32, k: u32) -> f64 {
    mh((x as u32).wrapping_mul(73_856_093) ^ (z as u32).wrapping_mul(19_349_663), seed, k)
}
/// A number for the column that varies over the land in patches a tree or two across (0 to 1, mostly middling), so the
/// ragged edge of what the wave takes goes round whole trees: a bit of the column's own on top.
fn coherent(x: i32, z: i32, seed: u32) -> f64 {
    let (fx, fz) = (x as f32, z as f32);
    let n = 0.6 * fvnoise(fx * 0.045 + seed as f32, fz * 0.045) + 0.3 * fvnoise(fx * 0.12 + 7.0, fz * 0.12 + seed as f32 * 0.5);
    // (stretched a little so it reaches both ends of 0 to 1 and the edge is a real edge)
    ((f64::from(n) - 0.12) * 1.25 + 0.1 * chance(x, z, seed, 1)).clamp(0.0, 1.0)
}
/// A block's name with its state, kept for the strike's edits (each name made once).
fn interned(name: String) -> &'static str {
    thread_local! {
        static NAMES: RefCell<HashMap<String, &'static str>> = RefCell::new(Default::default());
    }
    NAMES.with(|n| *n.borrow_mut().entry(name).or_insert_with_key(|k| Box::leak(k.clone().into_boxed_str())))
}
/// Whether the wave leaves block `name` where it is, whatever it is: what can't be broken and what holds things.
fn stays(name: &str) -> bool {
    let n = name.trim_start_matches("minecraft:");
    const EXACT: [&str; 34] = [
        "bedrock", "barrier", "end_portal_frame", "end_portal", "end_gateway", "command_block", "chain_command_block",
        "repeating_command_block", "structure_block", "structure_void", "jigsaw", "light", "reinforced_deepslate",
        "spawner", "trial_spawner", "vault", "moving_piston", "nether_portal", "chest", "trapped_chest", "ender_chest",
        "barrel", "furnace", "blast_furnace", "smoker", "hopper", "dispenser", "dropper", "brewing_stand", "lectern",
        "chiseled_bookshelf", "decorated_pot", "crafter", "jukebox",
    ];
    EXACT.contains(&n) || n.ends_with("shulker_box") || n.ends_with("campfire") || n.ends_with("_shelf") || matches!(n, "beacon" | "conduit" | "respawn_anchor" | "lodestone" | "test_block" | "test_instance_block")
}
/// What the soil is, for the scouring: 1 soil (dirt, grass, podzol, mycelium, farmland, a path, moss, snow, ice), 2 sand,
/// 3 gravel, 0 anything else (rock, clay, mud: left as it is).
fn soil_of(name: &str) -> u8 {
    match name.trim_start_matches("minecraft:") {
        "grass_block" | "dirt" | "coarse_dirt" | "podzol" | "mycelium" | "rooted_dirt" | "farmland" | "dirt_path" | "moss_block" | "snow_block" | "powder_snow" | "ice" | "packed_ice" | "blue_ice" | "mud" => 1,
        "sand" | "red_sand" | "suspicious_sand" => 2,
        "gravel" | "suspicious_gravel" => 3,
        _ => 0,
    }
}
/// A block the wreckage is made of (a full block from a building or a tree: timber, stone, brick, wool, hay, clay).
fn wreck_ok(name: &str) -> bool {
    let n = name.trim_start_matches("minecraft:");
    if ["slab", "stairs", "door", "pane", "fence", "wall", "sign", "carpet", "button", "plate", "torch", "lantern", "bed", "banner", "chain", "bars", "ladder", "glass", "leaves", "wire"].iter().any(|k| n.contains(k)) {
        return false;
    }
    ["planks", "_log", "_wood", "cobblestone", "stone_bricks", "bricks", "_wool", "hay_block", "terracotta", "sandstone", "andesite", "diorite", "granite", "_stem", "bamboo_block"].iter().any(|k| n.contains(k))
}
/// A log laid on its side along the flow (`along_x`), as its block name with state.
fn lying(name: &str, along_x: bool) -> &'static str {
    interned(format!("{name}[axis={}]", if along_x { "x" } else { "z" }))
}

/// A palette name's class for the wave (as the Hurricane's): 0 air, 1 water, 2 the land's own ground, 3 logs, 4 leaves, 5
/// plants, 6 light things, 7 buildings, 8 stays (and whatever the table doesn't know: left as it is, with nothing under
/// it touched); and what its ground is if it is the ground: the scouring's kind (`soil_of`).
#[derive(Clone, Copy, Debug)]
struct Kind {
    class: u8,
    soil: u8,
    /// Whether it makes wreckage (`wreck_ok`: string searches, so once a name, not once a block).
    wreck: bool,
}
fn kind_of(name: &str) -> Kind {
    crate::meter::spend(12_000);
    match hu_block(name) {
        Some(_) if stays(name) => Kind { class: 8, soil: 0, wreck: false },
        Some(b) => {
            let k = &HU_BLOCKS[b as usize];
            Kind { class: k.class, soil: if k.class == 2 { soil_of(k.name) } else { 0 }, wreck: k.class == 7 && wreck_ok(name) }
        }
        None => Kind {
            class: match sh_land::material(name).1 {
                Class::Air => 0,
                Class::Water => 1,
                _ => 8,
            },
            soil: 0,
            wreck: false,
        },
    }
}

/// What a column of a read holds: the land's ground (the first block down from its top that is the land's own or stays),
/// the highest thing standing on it, whether water covers it, and the ground block's name index.
#[derive(Clone, Copy, Debug)]
struct Col {
    g: i32,
    top: i32,
    fluid: bool,
    soil: u8,
    /// Standing on it: the logs there and the wreck block to lay (a palette index; u16::MAX none).
    wreck: u16,
    logs: u8,
    stand: u8,
    tree: bool,
    bld: bool,
    /// Air, water or something that stays within a few blocks under its ground (a cave, an overhang): no pond leans on it.
    hole: bool,
    /// The top of the water over it, if any.
    wtop: i32,
}

struct Cur {
    a: Rc<crate::columns::Answer>,
    kinds: Vec<Kind>,
    chunks: Vec<(i32, i32, f64)>,
    k: usize,
}

struct Work {
    geo: TsGeo,
    chunks: Vec<(i32, i32, f64)>,
    tags: Vec<u32>,
    asked: usize,
    taken: usize,
    cur: Option<Cur>,
    /// Chunks the world had not loaded when it answered, asked again till it has; the query out for some of them.
    retry: Vec<(i32, i32, f64)>,
    retry_q: Option<(u32, Vec<(i32, i32, f64)>, f64)>,
    next_retry: f64,
    seed: u32,
    gy: i32,
    /// The map's counts of columns with trees and with buildings, a cell each, and whether it changed since the pass was told.
    map: Vec<(u16, u16, i32, u16)>,
    map_dirty: bool,
    map_told: f64,
    /// The chunks changed, the columns swept and what was taken, for the tests and the log.
    changed: usize,
    swept: u64,
    done: bool,
    boats: u32,
    /// The land as each chunk was left, for the ponds; the tiles of it still to look at, and the columns of water so far.
    lands: HashMap<(i32, i32), Box<[Land; 256]>>,
    tiles: Option<Vec<(i32, i32)>>,
    ponded: u32,
}

/// A column as the ponds see it: its height, whether water may stand on it, whether it lets water away whatever its height.
#[derive(Clone, Copy, Debug)]
struct Land {
    h: i16,
    fill: bool,
    drains: bool,
}
impl Land {
    const NONE: Land = Land { h: i16::MIN, fill: false, drains: true };
}

// ---- the water it leaves ---------------------------------------------------------------------------------------------
/// How many chunks a tile of the ponds' work is across, its columns across, and the most it leaves over a hollow's floor,
/// in all. The edge of a tile holds no water, so nothing ever runs across one, or out of what was read.
const TS_TILE: i32 = 4;
const TS_T_W: usize = 64;
const TS_POND_DEEP: i32 = 3;
const TS_PONDS: u32 = 26_000;

/// The water that stays on a tile: for each column (`land`, row by row) the level its water stands at, if any. Priority
/// flood: from the edge and whatever drains, lowest first, each column's level the higher of its own height and the
/// lowest way out of it; then each hollow is let down to `TS_POND_DEEP` over its floor. Every column with water has, on all
/// four sides, water at the same level or a column at least that high (`no_pond_leaks`).
fn ponds(land: &[Land], n: usize) -> Vec<(usize, i16)> {
    use std::cmp::Reverse;
    use std::collections::BinaryHeap;
    crate::meter::spend(40 * land.len() as u64);
    let mut level = vec![i16::MIN; land.len()];
    let mut seen = vec![false; land.len()];
    let mut heap: BinaryHeap<Reverse<(i16, u32)>> = BinaryHeap::with_capacity(4 * n);
    for (i, l) in land.iter().enumerate() {
        let (x, z) = (i % n, i / n);
        if x == 0 || z == 0 || x == n - 1 || z == n - 1 || l.drains {
            seen[i] = true;
            // (what drains takes the water down to its own height, or to nothing if nothing is known of it)
            level[i] = l.h;
            heap.push(Reverse((l.h, i as u32)));
        }
    }
    while let Some(Reverse((lv, i))) = heap.pop() {
        crate::meter::spend(700);
        let i = i as usize;
        let (x, z) = (i % n, i / n);
        let mut go = |j: usize| {
            if !seen[j] {
                seen[j] = true;
                let l = lv.max(land[j].h);
                level[j] = l;
                heap.push(Reverse((l, j as u32)));
            }
        };
        if x > 0 {
            go(i - 1);
        }
        if x + 1 < n {
            go(i + 1);
        }
        if z > 0 {
            go(i - n);
        }
        if z + 1 < n {
            go(i + n);
        }
    }
    // each hollow (the columns under its level, joined side by side) let down to a few blocks over its floor; a column
    // that may not hold water closes the whole hollow
    let mut group = vec![false; land.len()];
    let mut out = Vec::new();
    let mut stack = Vec::new();
    let mut members = Vec::new();
    for i in 0..land.len() {
        crate::meter::spend(12);
        if group[i] || level[i] <= land[i].h {
            continue;
        }
        group[i] = true;
        stack.push(i);
        members.clear();
        let (mut floor, mut ok) = (i16::MAX, true);
        while let Some(c) = stack.pop() {
            crate::meter::spend(160);
            members.push(c);
            floor = floor.min(land[c].h);
            ok &= land[c].fill;
            let (x, z) = (c % n, c / n);
            for (d, on) in [(c.wrapping_sub(1), x > 0), (c + 1, x + 1 < n), (c.wrapping_sub(n), z > 0), (c + n, z + 1 < n)] {
                if on && !group[d] && level[d] > land[d].h {
                    group[d] = true;
                    stack.push(d);
                }
            }
        }
        if !ok || members.len() < 4 {
            continue;
        }
        let lv = level[i].min(floor.saturating_add(TS_POND_DEEP as i16));
        for &c in &members {
            if land[c].h < lv {
                out.push((c, lv));
            }
        }
    }
    out
}
/// When the water falls past `y` over the target's ground at `s` (it stands there till then), or none if it never covers it.
fn falls_past(geo: &TsGeo, s: f64, y: f64) -> Option<f64> {
    let top = TS_A * geo.env(s, 0.0) * (1.0 - TS_LOW) - TS_SEA;
    if top < y {
        return None;
    }
    let (mut lo, mut hi) = (0.0f64, 1.0f64);
    for _ in 0..14 {
        let mid = 0.5 * (lo + hi);
        if TsGeo::fall(top, mid) > y {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    Some(TS_T + TsGeo::tau(geo.dp) + TsGeo::rise_t(geo.dp) + TS_HOLD + 0.0016 * (s - geo.dp) + lo * TS_DRAIN)
}
/// One stage of the ponds: a tile at a time, once the land is all read.
fn ts_ponds(wk: &mut Work, now: f64, q: &mut Plan) {
    let tile = TS_TILE;
    if wk.tiles.is_none() {
        let mut t: Vec<(i32, i32)> = wk.chunks.iter().map(|&(cx, cz, _)| (cx.div_euclid(tile), cz.div_euclid(tile))).collect();
        t.sort_unstable();
        t.dedup();
        crate::meter::spend(100 * t.len() as u64);
        wk.tiles = Some(t);
    }
    let mut buf = vec![Land::NONE; TS_T_W * TS_T_W];
    while crate::meter::spent() < TS_STAGE && wk.ponded < TS_PONDS {
        let Some(tiles) = wk.tiles.as_mut() else { return };
        let Some((tx, tz)) = tiles.pop() else { return };
        for cz in 0..tile {
            for cx in 0..tile {
                let at = |i: usize| (cz as usize * 16 + i / 16) * TS_T_W + cx as usize * 16 + i % 16;
                match wk.lands.get(&(tx * tile + cx, tz * tile + cz)) {
                    Some(l) => l.iter().enumerate().for_each(|(i, c)| buf[at(i)] = *c),
                    None => (0..256).for_each(|i| buf[at(i)] = Land::NONE),
                }
            }
        }
        crate::meter::spend(3 * (TS_T_W * TS_T_W) as u64);
        // (a tile with nothing swept on it holds nothing of ours)
        let found = ponds(&buf, TS_T_W);
        if found.is_empty() {
            continue;
        }
        // (each chunk's water in on one tick, while the falling water still hides it)
        let mut by_chunk: HashMap<(i32, i32), (Blocks, i16)> = HashMap::new();
        for (i, lv) in found {
            let (lx, lz) = ((i % TS_T_W) as i32, (i / TS_T_W) as i32);
            let (x, z) = (tx * tile * 16 + lx, tz * tile * 16 + lz);
            let e = by_chunk.entry((x >> 4, z >> 4)).or_insert_with(|| (Blocks { clear_of_player: true, ..Default::default() }, lv));
            e.0.put(x, z, i32::from(buf[i].h) + 1, i32::from(lv), "minecraft:water", None, false);
            e.1 = e.1.max(lv);
            crate::meter::spend(200);
            wk.ponded += 1;
        }
        for ((cx, cz), (b, lv)) in by_chunk {
            let (s, _) = wk.geo.su(f64::from(cx * 16) + 8.0, f64::from(cz * 16) + 8.0);
            let t = falls_past(&wk.geo, s, f64::from(lv) - wk.geo.t[1] + 1.5).map_or(now + 0.1, |t| t.max(now + 0.1));
            q.ev.push((t as f32, Act::Blocks(Box::new(b))));
        }
    }
}

/// The block the soil's top turns to in streaks along the flow (`n`, a noise stretched along it, 0 to 1; `h` a roll of the
/// column's own): mud, packed mud, coarse dirt, gravel, sand, clay.
fn scoured(kind: u8, n: f64, h: f64) -> &'static str {
    match kind {
        2 => {
            if n < 0.5 { "minecraft:sand" } else if n < 0.72 { "minecraft:gravel" } else if h < 0.5 { "minecraft:coarse_dirt" } else { "minecraft:mud" }
        }
        3 => {
            if n < 0.55 { "minecraft:gravel" } else if n < 0.8 { "minecraft:coarse_dirt" } else { "minecraft:sand" }
        }
        _ => {
            if n < 0.30 {
                "minecraft:mud"
            } else if n < 0.46 {
                if h < 0.6 { "minecraft:mud" } else { "minecraft:packed_mud" }
            } else if n < 0.62 {
                "minecraft:coarse_dirt"
            } else if n < 0.80 {
                if h < 0.7 { "minecraft:gravel" } else { "minecraft:coarse_dirt" }
            } else if h < 0.5 {
                "minecraft:sand"
            } else {
                "minecraft:clay"
            }
        }
    }
}

/// One chunk of a read: its columns swept, scoured and strewn, as one edit.
fn ts_chunk(w: &mut Work, cur: &Cur, k: usize, now: f64, q: &mut Plan) -> bool {
    let (cx, cz, arr) = cur.chunks[k];
    let a = &*cur.a;
    let (x0, z0) = (cx * 16, cz * 16);
    // (the chunk's columns, in the order they were asked: row by row)
    let mut cols: Vec<Option<Col>> = Vec::with_capacity(256);
    let mut missing = false;
    for i in 0..256 {
        let Some((surface, blocks)) = a.column(k * 256 + i) else {
            missing = true;
            break;
        };
        crate::meter::spend(260);
        let base = surface - a.below;
        let (mut g, mut top, mut fluid, mut soil, mut wreck) = (None, None, false, 0u8, u16::MAX);
        let (mut hole, mut wtop) = (false, i32::MIN);
        let (mut logs, mut stand) = (0u8, 0u8);
        let (mut tree, mut bld) = (false, false);
        for j in (0..blocks.len()).rev() {
            crate::meter::spend(24);
            let b = blocks[j];
            let kind = cur.kinds.get(b as usize).copied().unwrap_or(Kind { class: 8, soil: 0, wreck: false });
            let y = base + j as i32;
            match kind.class {
                0 => continue,
                1 => {
                    fluid = true;
                    wtop = wtop.max(y);
                }
                2 | 8 => {
                    g = Some(y);
                    soil = kind.soil;
                    hole = kind.class == 8;
                    for k in 1..=4 {
                        crate::meter::spend(24);
                        if j >= k && cur.kinds.get(blocks[j - k] as usize).is_none_or(|n| n.class != 2) {
                            hole = true;
                        }
                    }
                    break;
                }
                class => {
                    top.get_or_insert(y);
                    stand = stand.saturating_add(1);
                    if class == 3 {
                        logs = logs.saturating_add(1);
                    }
                    tree |= class == 3 || class == 4;
                    bld |= class == 7;
                    if wreck == u16::MAX && (kind.wreck || class == 3) {
                        wreck = b;
                    }
                }
            }
        }
        cols.push(g.map(|g| Col { g, top: top.unwrap_or(g), fluid, soil, wreck, logs, stand, tree, bld, hole, wtop }));
    }
    if missing {
        return false;
    }
    let mut b = Blocks { clear_of_player: true, ..Default::default() };
    let geo = &w.geo;
    let ty = geo.t[1];
    // (what the wave does is worked out for each 4 by 4 cells' middle: its strength, the water's height, the streak)
    let mut cell = [(0.0f64, 0.0f64, 0.0f64); 16];
    for (c, v) in cell.iter_mut().enumerate() {
        let (mx, mz) = (f64::from(x0 + (c % 4) as i32 * 4) + 2.0, f64::from(z0 + (c / 4) as i32 * 4) + 2.0);
        let (s, u) = geo.su(mx, mz);
        let m = mask(geo, s, u);
        *v = if m > 0.0 { (m, geo.peak(s, u), f64::from(fvnoise((s * 0.011) as f32 + geo.sd, (u * 0.075) as f32))) } else { (0.0, 0.0, 0.0) };
    }
    // (the wreck to strew: a column's wood or building, laid down in the chunk along the flow)
    let mut wrecks: Vec<(usize, u16, u8)> = Vec::new();
    let mut gs = [i32::MIN; 256];
    let mut reached = [false; 256];
    // (the land as the ponds will see it: its height after all this, and what they may not lean on or fill)
    let mut land = [Land::NONE; 256];
    let mut drift: Vec<(usize, &'static str, i32)> = Vec::new();
    let along_x = geo.m[0].abs() > geo.m[1].abs();
    for i in 0..256 {
        let (lx, lz) = (i % 16, i / 16);
        let (x, z) = (x0 + lx as i32, z0 + lz as i32);
        let Some(c) = cols[i] else { continue };
        gs[i] = c.g;
        land[i] = Land { h: (if c.fluid { c.wtop.max(c.g) } else { c.g }) as i16, fill: false, drains: c.hole || c.fluid };
        crate::meter::spend(420);
        // (the pass's map: trees, buildings, the land's height, a column in four for the height)
        if c.tree || c.bld || (lx % 2 == 0 && lz % 2 == 0) {
            let (s, u) = geo.su(f64::from(x) + 0.5, f64::from(z) + 0.5);
            if let Some(mc) = map_cell(s, u) {
                let e = &mut w.map[mc];
                e.0 += u16::from(c.tree);
                e.1 += u16::from(c.bld);
                if lx % 2 == 0 && lz % 2 == 0 {
                    e.2 += c.g - ty as i32;
                    e.3 += 1;
                }
                w.map_dirty = true;
            }
        }
        let (m, peak, n) = cell[(lz / 4) * 4 + lx / 4];
        let over = peak - (f64::from(c.g) - ty);
        let take = !c.fluid && m > 0.0 && coherent(x, z, w.seed) < m && over >= 2.0;
        if !take {
            // (a tree the water went through and left: some timber jammed up in its crown)
            if !c.fluid && c.tree && c.top > c.g + 4 && over > -8.0 && (m > 0.0 || over < 10.0) && chance(x, z, w.seed, 11) < 0.02 {
                let y = c.g + 1 + (f64::from(c.top - c.g) * (0.45 + 0.35 * chance(x, z, w.seed, 12))) as i32;
                let log = lying("minecraft:oak_log", along_x);
                for k in 0..4 {
                    let (ax, az) = if along_x { (k.min(15 - lx as i32), 0) } else { (0, k.min(15 - lz as i32)) };
                    b.put(x + ax, z + az, y, y, log, None, false);
                }
            }
            continue;
        }
        reached[i] = true;
        w.swept += 1;
        // (what is left of what stood there: snapped trunks, the footings of the walls)
        let keep = if c.bld {
            ((fvnoise(x as f32 * 0.21 + w.seed as f32, z as f32 * 0.21) * 3.6) as i32 - (chance(x, z, w.seed, 13) < 0.15) as i32).clamp(0, i32::from(c.stand).min(3))
        } else if c.logs > 0 && chance(x, z, w.seed, 9) < 0.6 {
            (1 + (chance(x, z, w.seed, 10) * 3.0) as i32).min(i32::from(c.logs))
        } else {
            0
        };
        if c.top > c.g {
            b.put(x, z, c.g + 1 + keep, c.top, "minecraft:air", None, false);
            if c.wreck != u16::MAX && chance(x, z, w.seed, 2) < (0.04 + 0.014 * f64::from(c.stand.min(12))).min(0.18) {
                wrecks.push((i, c.wreck, c.logs));
            }
        }
        let mut ground = c.g + keep;
        land[i] = Land { h: ground as i16, fill: keep == 0 && !c.hole, drains: c.hole };
        // (the soil scoured in streaks along the flow, the strongest of them gouged out in channels)
        if c.soil != 0 && keep == 0 {
            let r = scoured(c.soil, n, chance(x, z, w.seed, 7));
            let side = |dx: usize, dz: usize| cols.get(lz.min(15).wrapping_add(dz).min(255) * 16 + lx + dx).copied().flatten().is_some_and(|c| c.fluid);
            let by_water = side(1, 0) || side(0, 1) || (lx > 0 && cols[i - 1].is_some_and(|c| c.fluid)) || (lz > 0 && cols[i - 16].is_some_and(|c| c.fluid));
            if c.soil == 1 && n > 0.74 && !by_water && over > 6.0 && chance(x, z, w.seed, 3) < 0.92 {
                let d = 1 + ((n - 0.74) / 0.26 * 4.0) as i32;
                b.put(x, z, c.g - d + 1, c.g, "minecraft:air", None, false);
                ground = c.g - d;
                gs[i] = ground;
                b.put(x, z, ground, ground, if chance(x, z, w.seed, 14) < 0.5 { "minecraft:gravel" } else { "minecraft:mud" }, None, false);
                land[i].h = ground as i16;
            } else {
                b.put(x, z, c.g, c.g, r, None, false);
                if c.soil == 1 && n > 0.7 && chance(x, z, w.seed, 3) < 0.35 {
                    b.put(x, z, c.g - 1, c.g - 1, if r == "minecraft:gravel" { "minecraft:gravel" } else { "minecraft:mud" }, None, false);
                }
            }
        }
        // (the wrack: what it carried dropped at the limit of its reach, in a line along the high water)
        let edge = over < 8.0 || m < 0.3;
        if edge && keep == 0 && chance(x, z, w.seed, 15) < 0.3 {
            let pick = chance(x, z, w.seed, 16);
            let block = if pick < 0.42 {
                lying(if pick < 0.2 { "minecraft:oak_log" } else { "minecraft:spruce_log" }, along_x)
            } else if pick < 0.7 {
                "minecraft:oak_planks"
            } else if pick < 0.85 {
                "minecraft:spruce_planks"
            } else {
                "minecraft:gravel"
            };
            drift.push((i, block, if pick < 0.7 { 1 } else { 1 + (chance(x, z, w.seed, 17) * 2.0) as i32 }));
        }
    }
    for (i, block, h) in drift {
        if reached[i] && gs[i] != i32::MIN {
            let (x, z) = (x0 + (i % 16) as i32, z0 + (i / 16) as i32);
            b.put(x, z, gs[i] + 1, gs[i] + h, block, None, false);
            land[i].h = (gs[i] + h) as i16;
            land[i].fill = false;
        }
    }
    // the wreckage: laid in the chunk, downstream of where it stood, a log along the flow or a block of what the
    // building was, a stack or two high
    for (i, wb, logs) in wrecks {
        let (x, z) = (x0 + (i % 16) as i32, z0 + (i / 16) as i32);
        let name = &a.palette[wb as usize];
        let (dx, dz) = ((geo.m[0] * (2.0 + 11.0 * chance(x, z, w.seed, 4))).round() as i32, (geo.m[1] * (2.0 + 11.0 * chance(x, z, w.seed, 5))).round() as i32);
        crate::meter::spend(1_500);
        let log = logs > 0 && name.contains("log") || name.contains("wood");
        let len = if log { 3 + (chance(x, z, w.seed, 6) * 5.0) as i32 } else { 1 };
        for step in 0..len {
            let (ox, oz) = if log { (if along_x { step } else { 0 }, if along_x { 0 } else { step }) } else { (0, 0) };
            let (lx, lz) = (((i % 16) as i32 + dx + ox).clamp(0, 15), ((i / 16) as i32 + dz + oz).clamp(0, 15));
            let j = (lz * 16 + lx) as usize;
            if !reached[j] || gs[j] == i32::MIN {
                continue;
            }
            crate::meter::spend(1_500);
            let plain = name.split('[').next().unwrap_or(name);
            let block: &'static str = if log { lying(plain, along_x) } else { interned(plain.to_string()) };
            let h = if log { 1 } else { 1 + (chance(x, z, w.seed, 8) * 2.0) as i32 };
            b.put(x0 + lx, z0 + lz, gs[j] + 1, gs[j] + h, block, None, false);
            land[j].h = i16::try_from(gs[j] + h).unwrap_or(i16::MAX);
            land[j].fill = false;
        }
    }
    // a few boulders: a lump of rock a few blocks across, where the flow dropped it
    for n in 0..3u32 {
        if chance(cx, cz, w.seed, 20 + n) > 0.18 {
            continue;
        }
        let i = (chance(cx, cz, w.seed, 30 + n) * 255.0) as usize;
        let (lx, lz) = ((i % 16).min(14) as i32, (i / 16).min(14) as i32);
        let rock = ["minecraft:cobblestone", "minecraft:mossy_cobblestone", "minecraft:andesite", "minecraft:tuff"][(chance(cx, cz, w.seed, 40 + n) * 4.0) as usize % 4];
        for (ox, oz) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let j = ((lz + oz) * 16 + lx + ox) as usize;
            if reached[j] && gs[j] != i32::MIN {
                let h = 1 + ((chance(x0 + lx + ox, z0 + lz + oz, w.seed, 50) * 2.0) as i32);
                b.put(x0 + lx + ox, z0 + lz + oz, gs[j] + 1, gs[j] + h, rock, None, false);
                land[j].h = i16::try_from(gs[j] + h).unwrap_or(i16::MAX);
                land[j].fill = false;
            }
        }
    }
    w.lands.insert((cx, cz), Box::new(land));
    let rise = TsGeo::rise_t(w.geo.su(f64::from(x0) + 8.0, f64::from(z0) + 8.0).0);
    let t = (arr + rise + 0.2).max(now + 0.1) as f32;
    if !b.runs.is_empty() {
        w.changed += 1;
        q.ev.push((t, Act::Blocks(Box::new(b))));
    }
    // (every mob and dropped item in the chunk, as the water reaches it)
    q.ev.push((t - 0.4, Act::Cmd(format!("kill @e[type=!minecraft:player,x={x0},y=-70,z={z0},dx=15,dy=520,dz=15]"))));
    // (now and then a boat, carried off some lake or river and left far inland, out on the mud)
    if w.boats < 36 && chance(cx, cz, w.seed, 60) < 0.05 {
        let i = 17 * (1 + (chance(cx, cz, w.seed, 61) * 13.0) as usize);
        if reached[i] && gs[i] != i32::MIN {
            let kind = if chance(cx, cz, w.seed, 62) < 0.6 { "oak" } else { "spruce" };
            let yaw = (chance(cx, cz, w.seed, 63) * 360.0) as i32;
            q.ev.push((t + 0.8, Act::Cmd(format!("summon minecraft:{kind}_boat {} {} {} {{Rotation:[{yaw}f,0f]}}", x0 + (i % 16) as i32, gs[i] + 1, z0 + (i / 16) as i32))));
            w.boats += 1;
        }
    }
    true
}

/// The next answer in, worked out for its chunks: a retry's if one is out and in, else the next part's.
fn next_answer(wk: &mut Work) -> Option<Cur> {
    if let Some((tag, _, _)) = &wk.retry_q
        && let Some(a) = crate::columns::take(*tag)
    {
        let (_, chunks, _) = wk.retry_q.take()?;
        crate::meter::spend(2_000);
        let kinds: Vec<Kind> = a.palette.iter().map(|n| kind_of(n)).collect();
        return Some(Cur { a, kinds, chunks, k: 0 });
    }
    if wk.taken < wk.asked
        && let Some(a) = crate::columns::take(wk.tags[wk.taken])
    {
        let part = wk.taken;
        wk.taken += 1;
        crate::meter::spend(2_000);
        let kinds: Vec<Kind> = a.palette.iter().map(|n| kind_of(n)).collect();
        let (c0, c1) = (part * TS_PART, ((part + 1) * TS_PART).min(wk.chunks.len()));
        return Some(Cur { a, kinds, chunks: wk.chunks[c0..c1].to_vec(), k: 0 });
    }
    None
}

/// One stage of the land's work: the reads asked a few at a time in the order the front reaches the chunks, their answers
/// taken in as they come and worked chunk by chunk, the chunks the world had not loaded asked again.
fn ts_work(q: &mut Plan, w: Rc<RefCell<Work>>, now: f64) {
    let more = {
        let mut guard = w.borrow_mut();
        let wk = &mut *guard;
        // the reads: up to three out at a time
        while wk.asked < wk.tags.len() && wk.asked < wk.taken + 3 {
            let part = wk.asked;
            let (c0, c1) = (part * TS_PART, ((part + 1) * TS_PART).min(wk.chunks.len()));
            let mut columns = Vec::with_capacity((c1 - c0) * 256);
            for &(cx, cz, _) in &wk.chunks[c0..c1] {
                for i in 0..256 {
                    columns.push((cx * 16 + (i % 16), cz * 16 + (i / 16)));
                }
            }
            crate::meter::spend(40 * columns.len() as u64);
            q.ev.push((now as f32, Act::Read { tag: wk.tags[part], columns, below: TS_BELOW, above: TS_ABOVE }));
            wk.asked += 1;
        }
        // their answers, as they come: chunk by chunk until the stage has done its share
        while crate::meter::spent() < TS_STAGE {
            if wk.cur.is_none() {
                wk.cur = next_answer(wk);
            }
            let Some(mut cur) = wk.cur.take() else { break };
            while cur.k < cur.chunks.len() && crate::meter::spent() < TS_STAGE {
                let k = cur.k;
                cur.k += 1;
                if !ts_chunk(wk, &cur, k, now, q) {
                    wk.retry.push(cur.chunks[k]);
                }
            }
            if cur.k < cur.chunks.len() {
                wk.cur = Some(cur);
            }
        }
        // the map told to the pass about once a second
        if wk.map_dirty && now >= wk.map_told + 1.0 {
            wk.map_told = now;
            wk.map_dirty = false;
            let words: Vec<u32> = wk
                .map
                .iter()
                .map(|&(t, b, h, n)| {
                    let g = if n > 0 { (h / i32::from(n) + 2048).clamp(1, 0xFFFF) as u32 } else { 0 };
                    ((t * 255 / 160).min(255)) as u32 | (((b * 255 / 90).min(255)) as u32) << 8 | g << 16
                })
                .collect();
            crate::meter::spend(30 * words.len() as u64);
            q.ev.push((now as f32, Act::Words { index: TSM as u32, words }));
        }
        // the chunks not loaded yet (a target far off, its chunks only forceloaded as it fired): asked again, a few
        // dozen at a time, until they are or until TS_LAND_BY
        if wk.retry_q.is_none() && !wk.retry.is_empty() && now >= wk.next_retry {
            if now > TS_LAND_BY {
                crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("tsunami: {} chunks of the land never loaded; left alone there", wk.retry.len()));
                wk.retry.clear();
            } else {
                let take = wk.retry.len().min(60);
                let chunks: Vec<(i32, i32, f64)> = wk.retry.drain(..take).collect();
                let mut columns = Vec::with_capacity(chunks.len() * 256);
                for &(cx, cz, _) in &chunks {
                    for i in 0..256 {
                        columns.push((cx * 16 + (i % 16), cz * 16 + (i / 16)));
                    }
                }
                let tag = crate::columns::new_tag();
                q.ev.push((now as f32, Act::Read { tag, columns, below: TS_BELOW, above: TS_ABOVE }));
                wk.retry_q = Some((tag, chunks, now));
                wk.next_retry = now + 0.4;
            }
        }
        // the water it leaves, once all the land is known
        let read = wk.taken == wk.tags.len() && wk.cur.is_none() && wk.retry.is_empty() && wk.retry_q.is_none();
        if (read || now > TS_LAND_BY) && !wk.tiles.as_ref().is_some_and(Vec::is_empty) && crate::meter::spent() < TS_STAGE {
            ts_ponds(wk, now, q);
        }
        if read && wk.tiles.as_ref().is_some_and(|t| t.is_empty() || wk.ponded >= TS_PONDS) {
            wk.done = true;
            crate::sdk::log::write(crate::sdk::log::Level::Info, &format!("tsunami: {} chunks changed, {} columns swept, {} columns of water left, {} boats", wk.changed, wk.swept, wk.ponded, wk.boats));
        }
        !wk.done && now < TS_LAND_BY + 6.0
    };
    if more {
        q.later((now + 0.05) as f32, move |q| ts_work(q, w, now + 0.05));
    }
}

// ---- the plan ----------------------------------------------------------------------------------------------------------
pub(super) fn tsunami_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
    let [bx, by, bz] = target.block;
    let seed = (bx as i64).wrapping_mul(73_856_093) ^ (bz as i64).wrapping_mul(19_349_663) ^ by as i64;
    let mut p = Plan { laser, ev: Vec::new(), rng: Rng::new(seed as u64), bx, by, bz };
    let s = shader_seed as u32;
    let geo = TsGeo::new(target, me, shader_seed);
    let dp = geo.dp;
    let len = laser.length;

    // ---- the pass's table (what it reads: none yet but the terrain flag) --------------------------------------------
    p.later(0.04, move |q| q.ev.push((0.05, Act::Table(table_words(terrain)))));

    // ---- when it reaches the target and the player, the water over their head ----------------------------------------
    let t_t = geo.arr(0.0, 0.0);
    let (t_front, t_imm) = geo.at_player(me[1]);
    let tp = t_imm.unwrap_or(t_front);

    // ---- the sounds (strike/ts_sounds.rs) ----------------------------------------------------------------------------
    super::ts_sounds::ts_sounds(&mut p, &geo, me, s, t_t, tp, t_imm.is_some());

    // ---- the camera: the ground trembling as it comes, the blow at the target, the hard hit as it reaches the player,
    // then what is left of the surge shaking them until it drains ----------------------------------------------------
    let fo = falloff((dp - 100.0).max(0.0));
    let mut t = 1.1;
    while t < tp - 0.2 {
        let k = smooth(1.0, tp, t);
        p.shake(t as f32, (0.025 + 0.11 * k) as f32 * fo.max(0.4), 0.5);
        t += 0.35;
    }
    p.shake((t_t + dp / 343.0) as f32, 0.55 * fo.max(0.3), 3.0);
    if t_imm.is_some() {
        p.shake(tp as f32, 0.95, 2.4);
        let mut t = tp + 0.8;
        while t < tp + 17.0 {
            let k = 1.0 - smooth(tp + 2.0, tp + 17.0, t);
            p.shake(t as f32, (0.1 + 0.4 * k) as f32, 0.6);
            t += 0.45;
        }
    }

    // ---- the land: forceloaded and read in the order the front reaches it, then swept, scoured and strewn -------------
    if terrain {
        let chunks = swath_chunks(&geo);
        let load = load_rows(&chunks);
        for [x0, z0, x1, z1] in &load {
            p.at(0.0, format!("forceload add {x0} {z0} {x1} {z1}"));
        }
        for [x0, z0, x1, z1] in &load {
            p.ev.push((len - 0.5, Act::Spare(format!("forceload remove {x0} {z0} {x1} {z1}"))));
        }
        let parts = chunks.len().div_ceil(TS_PART);
        let work = Rc::new(RefCell::new(Work {
            geo,
            chunks,
            tags: (0..parts).map(|_| crate::columns::new_tag()).collect(),
            asked: 0,
            taken: 0,
            cur: None,
            retry: Vec::new(),
            retry_q: None,
            next_retry: 0.0,
            seed: s,
            gy: by + 1,
            map: vec![(0, 0, 0, 0); TSM_S * TSM_U],
            map_dirty: false,
            map_told: -1.0,
            changed: 0,
            swept: 0,
            done: false,
            boats: 0,
            lands: HashMap::new(),
            tiles: None,
            ponded: 0,
        }));
        p.later(0.1, move |q| ts_work(q, work, 0.1));
    }
    p.ev.sort_by(|a, b| a.0.total_cmp(&b.0));
    p.ev
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::sim;

    fn the_laser() -> &'static Laser {
        crate::lasers::LASERS.iter().find(|l| l.key == "tsunami").copied().expect("the tsunami")
    }
    fn geo(dp: f64, seed: f32) -> TsGeo {
        TsGeo::new(&Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] }, [0.5, 65.0, dp], seed)
    }
    #[test]
    fn the_front_comes_in_order_and_the_water_rises_holds_and_drains() {
        for seed in [1.0, 37.0, 80.0] {
            let g = geo(400.0, seed);
            // (the arrival grows with s along the middle, the front's inverse agrees within the lobes' lag)
            let mut last = f64::MIN;
            for s in (-900..700).step_by(20) {
                let a = g.arr(f64::from(s), 0.0);
                assert!(a > last - 0.6, "{s}: {a} after {last}");
                last = last.max(a);
                assert!((TsGeo::front(a - g.lag(f64::from(s), 0.0)) - f64::from(s)).abs() < 1.0);
            }
            // (the front crosses the target at 9 s, give or take its lobes' lag)
            assert!((g.arr(0.0, 0.0) - TS_T).abs() < 0.7);
            // (the water over a point: none before the front, up the face, the peak held, then drained to none)
            let (s, u) = (200.0, 0.0);
            let a = g.arr(s, u);
            assert!(g.level(s, u, a - 0.5).is_none());
            let rise = TsGeo::rise_t(s);
            let (l1, l2) = (g.level(s, u, a + 0.5 * rise).unwrap(), g.level(s, u, a + rise + 1.0).unwrap());
            assert!(l2 > l1 && l2 > 60.0 && l2 < 190.0, "{l1} {l2}");
            assert!(g.level(s, u, a + rise + TS_HOLD + TS_DRAIN + 4.0).is_none());
            // (spent at its end, and not at all out on its flanks)
            assert!(g.peak(g.send + 60.0, 0.0) < -50.0);
            assert!(g.peak(100.0, 3250.0) < -50.0);
            // (it runs 130 over the target's ground at full strength)
            assert!(g.peak(-300.0, 0.0) > 100.0, "{}", g.peak(-300.0, 0.0));
        }
    }
    #[test]
    fn it_reaches_the_player_when_the_sounds_say() {
        let g = geo(400.0, 37.0);
        let (a, imm) = g.at_player(65.0);
        let imm = imm.expect("over their head");
        assert!(a > 14.0 && a < 15.5 && imm >= a && imm < a + 2.0, "{a} {imm}");
        // (a hill higher than the wave: it never covers them)
        assert!(g.at_player(400.0).1.is_none());
    }
    #[test]
    fn the_swath_covers_the_path_in_the_order_the_front_comes() {
        let g = geo(400.0, 37.0);
        let c = swath_chunks(&g);
        assert!(c.len() > 800 && c.len() < 3300, "{} chunks", c.len());
        assert!(c.windows(2).all(|w| w[0].2 <= w[1].2));
        let rows = load_rows(&c);
        assert!(rows.len() < 400, "{} forceloads", rows.len());
        for [x0, z0, x1, z1] in rows {
            assert!((x1 - x0 + 1) / 16 * ((z1 - z0 + 1) / 16) <= 256);
        }
    }
    #[test]
    fn the_plan_sounds_in_the_order_the_wave_reaches_them() {
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let plan = tsunami_plan(the_laser(), &target, false, "minecraft:overworld", 37.0, [0.5, 65.0, 400.0]);
        let at = |name: &str| plan.iter().find_map(|(t, a)| matches!(a, Act::Sound { event, .. } if event == &format!("orbital:tsunami.{name}")).then_some(*t));
        let (rupture, rumble, crash, engulf, under, drain) = (at("rupture").unwrap(), at("rumble").unwrap(), at("crash").unwrap(), at("engulf").unwrap(), at("under").unwrap(), at("drain").unwrap());
        assert!(rupture == 0.0 && rumble == 1.5 && crash > 9.0 && crash < 11.0 && engulf > 14.0 && under > engulf && drain > under + 8.0);
        // (nothing with the terrain off but the pass's table (a stage), sounds and shakes: no read, no edit, no forceload)
        assert!(plan.iter().all(|(_, a)| !matches!(a, Act::Read { .. } | Act::Blocks(_))));
        assert_eq!(plan.iter().filter(|(_, a)| matches!(a, Act::Later(_))).count(), 1, "only the table's stage");
        assert!(plan.iter().all(|(_, a)| !matches!(a, Act::Cmd(c) if c.contains("forceload"))));
    }
    /// A wooded land with a village's block of houses, flat, the grass at the target's ground.
    fn land(x: i32, z: i32, below: u32, above: u32) -> Option<(i32, Vec<&'static str>)> {
        let hills: f32 = std::env::var("PL_HILLS").map_or(0.0, |v| v.parse().unwrap());
        crate::strike::hurricane::synth_column(x, z, below, above, 65, hills, true)
    }
    /// `CB_SEED=37 CB_OUT=path PL_HILLS=H cargo test --release ts_write_table -- --ignored`: the table the pass reads, for
    /// tools/preview.py (a line `index value` a word): the target at the preview's 0.5 65 0.5, the player 300 south of it, on
    /// its wooded land with a village of houses round the target (the map's shares as the plan reads them).
    #[test]
    #[ignore]
    fn ts_write_table() {
        let seed: f32 = std::env::var("CB_SEED").map_or(37.0, |v| v.parse().unwrap());
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let ev = tsunami_plan(the_laser(), &target, true, "minecraft:overworld", seed, [0.5, 66.0, 300.5]);
        let mut data: Vec<u32> = Vec::new();
        crate::columns::clear();
        let mut ev = ev;
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        while let Some((_, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &|x, z| land(x, z, below, above)),
                Act::Table(w) => {
                    if data.len() < w.len() {
                        data.resize(w.len(), 0);
                    }
                    data[..w.len()].copy_from_slice(&w);
                }
                Act::Words { index, words } => {
                    let i = index as usize;
                    if data.len() < i + words.len() {
                        data.resize(i + words.len(), 0);
                    }
                    data[i..i + words.len()].copy_from_slice(&words);
                }
                Act::Later(job) | Act::Soon(job) | Act::Cleanup(job) => {
                    ev.extend(job());
                    ev.sort_by(|a, b| b.0.total_cmp(&a.0));
                }
                _ => {}
            }
        }
        let text: String = data.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
    /// Any land, any drains: every pond held, on all four sides, by the same water or by land at least its height, and none
    /// on the tile's edge or on what may not hold water.
    #[test]
    fn no_pond_leaks() {
        let mut rng = 0x1234_5678u32;
        let mut filled = 0;
        for round in 0..300 {
            let n = 32;
            let mut land = vec![Land { h: 60, fill: true, drains: false }; n * n];
            for (i, l) in land.iter_mut().enumerate() {
                let (x, z) = ((i % n) as f32, (i / n) as f32);
                let k = round as f32;
                l.h = (64.0 + 5.0 * (x * 0.31 + k).sin() * (z * 0.27 - k * 0.7).cos() + 2.5 * (x * 0.13 - z * 0.21 + k).sin()) as i16;
                rng = pcg(rng);
                l.h += (rng % 3) as i16 - 1;
                if rng % 97 == 0 {
                    l.fill = false;
                }
                if rng % 211 == 0 {
                    *l = Land::NONE;
                }
            }
            let found = ponds(&land, n);
            let mut lv = vec![i16::MIN; n * n];
            for &(i, l) in &found {
                assert!(land[i].fill && !land[i].drains && land[i].h < l);
                assert!(i32::from(l) - i32::from(land[i].h) <= TS_POND_DEEP);
                lv[i] = l;
                filled += 1;
            }
            for &(i, l) in &found {
                let (x, z) = (i % n, i / n);
                assert!(x > 0 && z > 0 && x + 1 < n && z + 1 < n, "water on the edge");
                for j in [i - 1, i + 1, i - n, i + n] {
                    assert!(lv[j] == l || land[j].h >= l, "{i} at {l}, {j}: land {} water {}", land[j].h, lv[j]);
                }
            }
        }
        assert!(filled > 2000, "only {filled} columns held water");
    }
    #[test]
    fn the_water_falls_past_the_land_when_it_should() {
        let g = geo(400.0, 37.0);
        let t = falls_past(&g, 300.0, 10.0).expect("it covers that");
        assert!(g.level(300.0, 0.0, t - 0.3).unwrap() > 10.0 && g.level(300.0, 0.0, t + 0.6).unwrap() < 11.0, "{t}");
        assert!(falls_past(&g, 300.0, 400.0).is_none());
    }
    #[test]
    fn the_wave_sweeps_the_land_in_its_order_and_every_stage_is_light() {
        let target = Target { block: [0, 64, 0], point: [0.5, 65.0, 0.5] };
        let plan = tsunami_plan(the_laser(), &target, true, "minecraft:overworld", 37.0, [0.5, 65.0, 400.0]);
        let played = sim::play(plan, 42.0, &|x, z, b, a| land(x, z, b, a));
        let g = geo(400.0, 37.0);
        assert!(played.edits.len() > 600, "{} edits", played.edits.len());
        // (each chunk's edit goes in a second or so after its water arrives, never before it; and only in the swath)
        let mut early = 0;
        for (_, due, b) in &played.edits {
            let r = &b.runs[0];
            let (s, u) = g.su(f64::from(r.x) + 0.5, f64::from(r.z) + 0.5);
            assert!(u.abs() < TS_HALF + 32.0 && s > -TS_UP - 32.0 && s < g.send + 32.0, "{s} {u}");
            let a = g.arr(s, u);
            if f64::from(*due) < a + 0.3 {
                early += 1;
            }
        }
        assert!(early < played.edits.len() / 50, "{early} edits before their water");
        // (the trees go, the soil is scoured, nothing placed where it would be in the water of a lake: none here)
        let air = played.edits.iter().flat_map(|e| e.2.as_fills()).filter(|f| f.contains("minecraft:air")).count();
        let mud = played.edits.iter().flat_map(|e| e.2.as_fills()).filter(|f| f.contains("minecraft:mud") || f.contains("minecraft:gravel")).count();
        assert!(air > 1000 && mud > 5000, "{air} sweeps {mud} scours");
        // (every chunk's mobs killed)
        assert!(played.cmds.iter().filter(|(_, c)| c.starts_with("kill @e[type=!minecraft:player")).count() > 800);
        // (and every stage far from the tick's fuel)
        let worst = played.stages.iter().map(|s| s.2).fold(0.0, f64::max);
        assert!(worst < 30.0, "a stage took {worst} ms");
        // (the chunks it forceloaded are let go before the strike ends)
        let adds = played.cmds.iter().filter(|(_, c)| c.starts_with("forceload add")).count();
        let removes = played.cmds.iter().filter(|(t, c)| c.starts_with("forceload remove") && *t < TS_LEN).count();
        assert_eq!(adds, removes);
    }
}
