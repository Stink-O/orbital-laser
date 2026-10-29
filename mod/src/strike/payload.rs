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
/// The object shows (fading in), turns into its dive, and strikes.
pub(super) const PL_SEEN: f32 = 3.0;
pub(super) const PL_TURN: f32 = 11.0;
pub(super) const PL_HIT: f32 = 13.6;
/// The path's samples (the trail is drawn through them), from PL_SEEN to PL_HIT.
pub(super) const PL_N: usize = 128;
/// The column's billows.
pub(super) const PL_PUFFS: usize = 18;
/// The column's height (over the ground) as its rise slows, about 20 s after the strike.
pub(super) const PL_HC: f64 = 235.0;
/// The table (render.set-data): words 0..16 the header (samples, first sample's time, their spacing, the wind's x and
/// z, the column's height, the billows' count); from PL_P the path, three words a sample (x, y, z from the target's
/// ground); from PL_PF the billows, PL_PW words each (launch, rise time, height share, radius, x and z off the axis).
pub(super) const PL_P: usize = 16;
pub(super) const PL_PF: usize = PL_P + 3 * PL_N;
pub(super) const PL_PW: usize = 8;

/// The crater's mean radius and depth, how far its rim's heap reaches (in its radii), the land flattened and the trees
/// felled out to PL_FLAT, the grass charred out to PL_CHAR, the rubble strewn out to PL_RUBBLE.
const PL_CRATER_R: f64 = 21.0;
const PL_CRATER_D: f64 = 9.0;
const PL_RIM: f64 = 1.65;
const PL_FLAT: f64 = 85.0;
const PL_CHAR: f64 = 100.0;
const PL_RUBBLE: f64 = 105.0;
/// The land read: every column out to PL_READ, PL_BELOW under its top (a tall tree's top down to its ground).
const PL_READ: i32 = 108;
const PL_GW: i32 = 2 * PL_READ + 1;
const PL_BELOW: u32 = 44;
const PL_ABOVE: u32 = 1;
const PL_PARTS: i32 = 6;
/// The blast's edits worked out in this many bands of rows, a stage each.
const PL_BANDS: i32 = 40;
/// Mobs and dropped items within PL_KILL killed as it strikes.
const PL_KILL: i32 = 90;

/// Where the object is and how it moves: everything worked out from the strike's seed and where the player stands.
#[derive(Clone, Debug)]
pub(super) struct PlGeo {
    pub seed: u32,
    /// Its drift's start and end (from the target's ground), and its loops.
    s0: [f64; 3],
    s1: [f64; 3],
    e1: [f64; 3],
    e2: [f64; 3],
    rho: f64,
    omega: f64,
    phase: f64,
    /// The wind (blocks a second, x and z): the trail and the column drift with it.
    pub wind: (f64, f64),
}

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
fn len(a: [f64; 3]) -> f64 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}
fn norm(a: [f64; 3]) -> [f64; 3] {
    let l = len(a).max(1e-9);
    [a[0] / l, a[1] / l, a[2] / l]
}

impl PlGeo {
    /// `me`: the player from the target's ground point.
    pub fn new(seed: f32, me: [f64; 3]) -> Self {
        let seed = seed as u32;
        let r = |k: u32| mh(k, seed, 0x9a1);
        let d = me[0].hypot(me[2]);
        // (towards the player, and across their view)
        let u = if d > 1.0 { [me[0] / d, 0.0, me[2] / d] } else { [0.0, 0.0, 1.0] };
        let s = [-u[2], 0.0, u[0]];
        let side = if r(1) < 0.5 { -1.0 } else { 1.0 };
        let dd = d.clamp(60.0, 700.0);
        // high over the target, off to one side and a little towards the player, drifting across and down
        let s0 = [0.0, 330.0 + 40.0 * r(2), 0.0];
        let s0 = add(add(s0, u, dd * (0.18 + 0.1 * r(3))), s, side * (150.0 + 60.0 * r(4)));
        let s1 = [0.0, 245.0 + 25.0 * r(5), 0.0];
        let s1 = add(add(s1, u, dd * (0.12 + 0.08 * r(6))), s, -side * (40.0 + 50.0 * r(7)));
        let along = norm([s1[0] - s0[0], 0.0, s1[2] - s0[2]]);
        let perp = [-along[2], 0.0, along[0]];
        // the loops: in a plane tilted up out of the horizontal, so they corkscrew
        let tilt = 0.45 + 0.3 * r(8);
        let e2 = norm([perp[0] * (1.0 - tilt), tilt, perp[2] * (1.0 - tilt)]);
        let wa = TAU * r(9);
        let ws = 2.0 + 2.5 * r(10);
        PlGeo {
            seed,
            s0,
            s1,
            e1: along,
            e2,
            rho: 38.0 + 14.0 * r(11),
            omega: TAU / (3.6 + 1.0 * r(12)) * if r(13) < 0.5 { -1.0 } else { 1.0 },
            phase: TAU * r(14),
            wind: (wa.cos() * ws, wa.sin() * ws),
        }
    }
    fn drift(&self, t: f64) -> [f64; 3] {
        let tau = t - f64::from(PL_SEEN);
        let span = f64::from(PL_TURN - PL_SEEN);
        let v = (tau / span).clamp(-0.2, 1.2);
        let base = add(self.s0, [self.s1[0] - self.s0[0], self.s1[1] - self.s0[1], self.s1[2] - self.s0[2]], v);
        // (the loops wax and wane: lazy, never regular)
        let rho = self.rho * (0.65 + 0.35 * (0.8 * tau + self.phase * 0.7).sin());
        let th = self.omega * tau + self.phase;
        let l = add([0.0; 3], self.e1, rho * (th.cos() - self.phase.cos()));
        let l = add(l, self.e2, rho * (th.sin() - self.phase.sin()));
        let bob = 6.0 * (0.9 * tau + 1.3 * self.phase).sin();
        add(add(base, l, 1.0), [0.0, 1.0, 0.0], bob)
    }
    /// Where it is at strike time `t` (from the target's ground), from PL_SEEN to PL_HIT.
    pub fn pos(&self, t: f64) -> [f64; 3] {
        let turn = f64::from(PL_TURN);
        if t <= turn {
            return self.drift(t);
        }
        // the dive: a curve from where the drift left it, carried on the way it was going, bending down to the target,
        // faster and faster
        let p1 = self.drift(turn);
        let v1 = add(self.drift(turn), self.drift(turn - 0.05), -1.0);
        let c = add(p1, norm(v1), 55.0);
        let c = add(c, [0.0, 1.0, 0.0], 15.0);
        let w = ((t - turn) / f64::from(PL_HIT - PL_TURN)).clamp(0.0, 1.0);
        let s = 0.3 * w + 0.7 * w * w * w;
        let a = (1.0 - s) * (1.0 - s);
        let b = 2.0 * (1.0 - s) * s;
        [a * p1[0] + b * c[0], a * p1[1] + b * c[1], a * p1[2] + b * c[2]]
    }
}

/// The column's billows: (launch after the strike, rise time, share of the column's height, radius, x and z off its
/// axis). The stem's low and narrow, then the body, then the head, the highest launched first.
pub(super) fn pl_puffs(seed: u32) -> Vec<[f64; 6]> {
    (0..PL_PUFFS)
        .map(|i| {
            let h = |k: u32| mh(i as u32, seed, 0x5f0 + k);
            let (t0, hf, rad) = if i < 5 {
                (0.05 + 0.5 * h(0), 0.06 + 0.3 * (i as f64 / 5.0) + 0.06 * h(1), 24.0 + 12.0 * h(2))
            } else if i < 11 {
                (0.1 + 0.7 * h(0), 0.38 + 0.36 * ((i - 5) as f64 / 6.0) + 0.06 * h(1), 34.0 + 16.0 * h(2))
            } else {
                (0.0 + 0.5 * h(0), 0.72 + 0.32 * ((i - 11) as f64 / 7.0) + 0.05 * h(1), 42.0 + 20.0 * h(2))
            };
            let tau = 3.6 + 2.4 * h(3);
            let a = TAU * h(4);
            let off = rad * (0.2 + 0.55 * h(5)) * if i < 5 { 0.6 } else { 1.0 };
            [t0, tau, hf, rad, a.cos() * off, a.sin() * off]
        })
        .collect()
}

/// What the pass reads (see PL_P): worked out on the tick after it fires.
pub(super) fn pl_table(seed: f32, me: [f64; 3]) -> Vec<u32> {
    let g = PlGeo::new(seed, me);
    let mut w = vec![0.0f32; PL_PF + PL_PUFFS * PL_PW];
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
    w.into_iter().map(f32::to_bits).collect()
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

/// What the blast makes of column (x, z): Kept, or its new ground's top (`Some`) and whether it was cleared.
fn new_ground(c: &Column, s: &Shape, x: i32, z: i32) -> Option<i32> {
    let (r, a, u) = s.at(x, z);
    if u < 1.0 {
        Some(c.g - bowl(u).round() as i32)
    } else if u < PL_RIM {
        Some(c.g + heap(u).round() as i32)
    } else if r < s.flat(a) {
        Some(c.g)
    } else {
        None
    }
}
/// Water or lava within a column's reach: dig nothing there or next to it.
fn wet_near(land: &Land, bx: i32, bz: i32, x: i32, z: i32) -> bool {
    [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|(dx, dz)| at(land, bx, bz, x + dx, z + dz).is_some_and(|c| c.fluid))
}

/// The crater, the rim's heap, the flattened land and the charred grass, over rows k0..k1 of the land's square.
fn pl_blast_rows(q: &mut Plan, land: &Land, s: &Shape, k0: i32, k1: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let mut b = Blocks::default();
    for k in k0..k1 {
        for i in 0..PL_GW {
            let (x, z) = (bx - PL_READ + i, bz - PL_READ + k);
            let Some(c) = at(land, bx, bz, x, z) else { continue };
            let (r, _, u) = s.at(x, z);
            if r > PL_CHAR + 6.0 || c.fluid {
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
                    let d = if u < 0.6 { 1 } else { 0 };
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
                    b.put(x, z, c.g - PL_CRATER_D as i32 - 2, c.g, "minecraft:dirt", Some("minecraft:water"), false);
                    b.put(x, z, c.g - PL_CRATER_D as i32 - 2, c.g, "minecraft:stone", Some("minecraft:lava"), false);
                }
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
                }
            }
        }
    }
    q.ev.push((PL_HIT + 0.05, Act::Blocks(Box::new(b))));
}
/// What is left hanging round what changed over rows k0..k1 (leaves of a tree whose trunk went, plants whose ground
/// went), on a stage of its own.
fn pl_tidy_rows(q: &mut Plan, land: &Land, s: &Shape, k0: i32, k1: i32) {
    let (bx, bz) = (q.bx, q.bz);
    let col = |x: i32, z: i32| -> Col {
        match at(land, bx, bz, x, z) {
            Some(c) if !c.fluid && new_ground(c, s, x, z).is_some() && !(wet_near(land, bx, bz, x, z) && new_ground(c, s, x, z) != Some(c.g)) => Col::Cleared,
            _ => Col::Kept,
        }
    };
    let t = tidy(bx - PL_READ, bz - PL_READ + k0, bx + PL_READ, bz - PL_READ + k1 - 1, 40, -1, col);
    if !t.runs.is_empty() {
        q.ev.push((PL_HIT + 0.2, Act::Blocks(Box::new(t))));
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
        if c.fluid || u < PL_RIM || r > s.flat(a) - 1.0 || (c.g - gy).abs() > 1 || wet_near(land, bx, bz, x, z) {
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
            if u < PL_RIM || r > s.flat(a) - 1.0 {
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
    q.ev.push((PL_HIT + 0.35, Act::Blocks(Box::new(b))));
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
    for (i, w) in waves.into_iter().enumerate() {
        if !w.runs.is_empty() {
            q.ev.push((PL_HIT + 1.6 + 1.1 * i as f32, Act::Blocks(Box::new(w))));
        }
    }
}

/// The payload. Calm; the object high in the sky drifting down in lazy loops; the dive; the strike: a flash, the column
/// boiling up, the shockwave's dust rushing out over the land and over the player, debris raining down; the column
/// standing over it all a long time.
pub(super) fn payload_plan(laser: &'static Laser, target: &Target, terrain: bool, _dimension: &str, shader_seed: f32, me: [f64; 3]) -> Vec<(f32, Act)> {
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
        p.later(0.05, move |q| q.ev.push((0.05, Act::Table(pl_table(s, rel)))));
    }

    // ---- calm, then something up there ------------------------------------------------------------------------------
    p.at(1.2, bar("ORBITAL TRACKING: OBJECT DESCENDING", "gray"));
    // (its whine and rumble, heard faintly from up there: late by how far it is)
    let (dl, _) = sound_from(add([cx, gy, cz], geo.pos(f64::from(PL_SEEN)), 1.0), me);
    p.csound(PL_SEEN - 0.3 + dl.min(1.6), "drift", 10.0, 1.0);
    p.at(7.5, bar("ORBITAL TRACKING: OBJECT DESCENDING", "gray"));
    // ---- the dive: its roar and whistle as it comes down, cut off as it strikes ----------------------------------
    p.at(PL_TURN + 0.2, bar("PAYLOAD INBOUND", "red"));
    p.csound(PL_TURN, "dive", 10.0, 1.0);
    // ---- the strike: a near-silent breath, the blast reaching the player late by how far it is, with the dust's rush
    // and the jolt, the debris coming down round them, the long rolling tail after -----------------------------------
    let arrive = PL_HIT + late;
    p.csound(arrive - 0.02, "blast", 10.0, 1.0);
    p.csound(arrive - 0.15, "rush", 10.0, 1.0);
    p.csound(arrive + 2.4, "tail", 10.0, 1.0);
    p.shake(arrive, 0.85 * fo, 2.6);
    p.shake(arrive + 0.35, 0.35 * fo, 1.5);
    let mut ts = arrive + 0.8;
    while ts < arrive + 7.0 {
        let s = p.rng.uniform(0.05, 0.16) as f32 * fo;
        let d = p.rng.uniform(0.4, 0.9) as f32;
        p.shake(ts, s, d);
        ts += p.rng.uniform(0.35, 1.1) as f32;
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
        p.at(t, format!("execute positioned {cx:.1} {gy} {cz:.1} run kill @e[type=!minecraft:player,distance=..{PL_KILL}]"));
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
        let fb = 8;
        let rows = (PL_GW + fb - 1) / fb;
        for j in 0..fb {
            let (land, used) = (land.clone(), used.clone());
            p.later(PL_HIT - 2.8 + 0.1 * j as f32, move |q| pl_felled(q, &land.borrow(), &shape, &used, j * rows, ((j + 1) * rows).min(PL_GW)));
        }
        p.later(PL_HIT - 1.9, move |q| pl_rubble(q, &land.borrow(), &shape, &used));
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
        let w = super::pl_table(seed, [me[0] - 0.5, me[1] - 65.0, me[2] - 0.5]);
        let text: String = w.iter().enumerate().map(|(i, v)| format!("{i} {v}u\n")).collect();
        std::fs::write(std::env::var("CB_OUT").unwrap(), text).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::plan;

    #[test]
    fn payload_path_drifts_then_dives_onto_the_target() {
        for seed in [3.0, 37.0, 512.0, 991.0] {
            let g = PlGeo::new(seed, [0.0, 5.0, 300.0]);
            let p0 = g.pos(f64::from(PL_SEEN));
            assert!(p0[1] > 250.0, "{p0:?}");
            let end = g.pos(f64::from(PL_HIT));
            assert!(len(end) < 1e-6, "{end:?}");
            // (it never goes underground before it strikes, and it moves smoothly)
            let mut last = p0;
            let mut t = f64::from(PL_SEEN);
            while t < f64::from(PL_HIT) {
                t += 0.02;
                let q = g.pos(t.min(f64::from(PL_HIT)));
                assert!(q[1] > -0.01, "{t} {q:?}");
                assert!(len(add(q, last, -1.0)) < 14.0, "{t}");
                last = q;
            }
            // (the dive is fast at the end)
            let v = len(add(g.pos(f64::from(PL_HIT)), g.pos(f64::from(PL_HIT) - 0.05), -1.0)) / 0.05;
            assert!(v > 200.0, "{v}");
        }
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
    fn column(x: i32, z: i32) -> Option<(i32, Vec<&'static str>)> {
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
        let (below, above) = (PL_BELOW as i32, PL_ABOVE as i32);
        Some((top, (top - below..top + above).map(block).collect()))
    }

    fn played(terrain: bool) -> Vec<(f32, Blocks)> {
        crate::columns::clear();
        let target = Target { block: [10, 64, -3], point: [10.5, 65.0, -2.5] };
        let mut ev = plan(&crate::lasers::PAYLOAD, &target, terrain, "minecraft:overworld", 37.0, [10.5, 66.0, 300.0], 0);
        ev.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut out = Vec::new();
        let mut table = false;
        while let Some((t, a)) = ev.pop() {
            match a {
                Act::Read { tag, columns, below, above } => crate::columns::test_answer(tag, &columns, below, above, &column),
                Act::Blocks(b) => out.push((t, *b)),
                Act::Table(w) => {
                    assert_eq!(w.len(), PL_PF + PL_PUFFS * PL_PW);
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
        out
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
        assert!(played(false).is_empty());
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
